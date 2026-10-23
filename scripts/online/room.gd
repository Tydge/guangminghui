extends RefCounted
## Authoritative room. Input, clocks and transactions share one monotonic server loop.
const Config=preload("res://scripts/online/config.gd")
const ViewProjection=preload("res://scripts/online/projection.gd")
var code=""
var game: GameState
var peers=[-1,-1]
var tokens=["",""]
var ready=[false,false]
var rematch=[false,false]
var issued=[{},{}]
var revision=0
var sequence=0
var pending={}
var queued=[]
var outgoing=[]
var started=false
var released=false
var grace=[Config.GRACE_MS,Config.GRACE_MS]
var opening_left=[Config.OPENING_MS,Config.OPENING_MS]
var opening_phase=""
var turn_left=Config.TURN_MS
var turn_serial=-1
var response_left=Config.RESPONSE_MS
var clock_actor=-1
var clock_kind=""
var idle_turns=[0,0]
var acted_serial=[-1,-1]
var last_tick=0
var last_broadcast=0
var touched=0
var checkpoint: Callable
var restart_intent={}

func _init(room_code: String,seed_value: int=0,now: int=0):
	code=room_code;game=GameState.new(seed_value,true);last_tick=now;touched=now
	tokens[0]=Config.secret();tokens[1]=Config.secret()
func emit(p: int,message: Dictionary):
	if peers[p]>=0:outgoing.append({"peer":peers[p],"message":message})
func both_connected() -> bool:return peers[0]>=0 and peers[1]>=0
func lobby(p: int) -> Dictionary:
	return {"op":"lobby","code":code,"you":p,"connected":[peers[p]>=0,peers[1-p]>=0],"ready":[ready[p],ready[1-p]],"rematch":[rematch[p],rematch[1-p]],"started":started}
func broadcast_lobby():
	for p in [0,1]:emit(p,lobby(p))
func attach(p: int,peer: int,now: int):
	peers[p]=peer;touched=now;last_tick=now
	if not pending.is_empty():
		# Replaying a stage on the resumed client requires a fresh acknowledgement.
		pending["presented" if pending.stage=="present" else "settled"][p]=false
		if both_connected() and pending.has("timeout_left"):
			pending.deadline=now+pending.timeout_left;pending.erase("timeout_left")
	emit(p,{"op":"joined","code":code,"token":tokens[p],"seat":p})
	broadcast_lobby()
	if started:
		emit(p,{"op":"state","revision":revision,"state":state_for(p),"resume":true})
		if not pending.is_empty():
			if pending.stage=="present":send_prepare(p)
			else:emit(p,{"op":"commit","tx":pending.id,"revision":revision,"state":state_for(p),"result":ViewProjection.relative(pending.plan.result,p)})
		elif both_connected():drive(now)
		broadcast_clock(now)
	save()
func detach(p: int,now: int):
	if both_connected() and not pending.is_empty():pending.timeout_left=maxi(0,pending.deadline-now)
	peers[p]=-1;last_tick=now;released=false;touched=now;broadcast_lobby();broadcast_clock(now);save()
func claim_seat(p: int):
	tokens[p]=Config.secret();ready[p]=false;rematch[p]=false
func leave_seat(p: int,now: int):
	tokens[p]="";ready[p]=false;rematch[p]=false;detach(p,now)
func state_for(p: int) -> Dictionary:
	var actions=game.legal_actions(p);issued[p]={};var display=[]
	for i in actions.size():
		var key="%d:%d"%[revision,i];issued[p][key]=actions[i].duplicate(true)
		var a=actions[i].duplicate(true);a._net=key;display.append(a)
	return ViewProjection.view(game,p,display)
func send_state(p: int,op: String="state"):
	var message={"op":op,"revision":revision,"state":state_for(p)}
	if op=="release":message.clock=clock_for(p)
	emit(p,message)
func start(now: int):
	started=true;ready=[true,true];released=false
	for p in [0,1]:send_state(p)
	drive(now);save()
func input(p: int,message: Dictionary,now: int):
	touched=now
	match message.get("op",""):
		"ready":
			if started:return
			ready[p]=bool(message.get("value",true));broadcast_lobby()
			if ready[0] and ready[1] and both_connected():start(now)
		"rematch":
			if game.phase!="over":return
			rematch[p]=true;broadcast_lobby()
			if rematch[0] and rematch[1] and both_connected():
				game=GameState.new(0,true);revision+=1;sequence+=1;pending={};queued=[];rematch=[false,false];grace=[Config.GRACE_MS,Config.GRACE_MS];opening_phase="";turn_serial=-1;clock_actor=-1;clock_kind="";idle_turns=[0,0];acted_serial=[-1,-1];start(now)
		"action":intent(p,str(message.get("id","")),now)
		"presented","settled":
			if pending.is_empty() or int(message.get("tx",-1))!=pending.id:return
			if message.op=="presented" and pending.stage=="present":
				pending.presented[p]=true
				if pending.presented[0] and pending.presented[1] and both_connected():commit(now)
			elif message.op=="settled" and pending.stage=="settle":
				pending.settled[p]=true
				if pending.settled[0] and pending.settled[1] and both_connected():pending={};drive(now)
		"preview":preview(p,str(message.get("id","")),str(message.get("key","")))
		"resign":forfeit(p,"对手认输",now)

func intent(p: int,key: String,now: int):
	if not started or game.phase=="over" or not issued[p].has(key):
		emit(p,{"op":"error","reason":"stale"});return
	var a=issued[p][key]
	if not both_connected():emit(p,{"op":"error","reason":"reconnecting"});return
	if not pending.is_empty():
		# Simultaneous opening selections may arrive during the other seat's reveal.
		if game.phase.begins_with("setup") and p!=pending.actor and not queued.any(func(item):return item.player==p):
			queued.append({"player":p,"action":a.duplicate(true)});emit(p,{"op":"accepted","id":key,"queued":true});return
		emit(p,{"op":"error","reason":"busy"});return
	if a not in game.legal_actions(p):emit(p,{"op":"error","reason":"stale"});send_state(p);return
	emit(p,{"op":"accepted","id":key,"queued":false})
	acted_serial[p]=game.serial;idle_turns[p]=0;prepare(p,a,now)

func prepare(p: int,a: Dictionary,now: int,notice: String=""):
	if a not in game.legal_actions(p):return
	released=false;sequence+=1
	var plan=ActionFlow.plan(game,p,a)
	var after=ActionFlow.copy_state(game)
	if not after.act(p,a):return
	pending={"id":sequence,"actor":p,"action":a.duplicate(true),"plan":plan,"after":after,"stage":"present","presented":[false,false],"settled":[false,false],"deadline":now+Config.PRESENT_MS,"notice":notice}
	for who in [0,1]:send_prepare(who)
	broadcast_clock(now);save()
func send_prepare(p: int):
	emit(p,{"op":"prepare","tx":pending.id,"revision":revision,"state":state_for(p),"plan":ViewProjection.presentation(game,pending.after,p,pending.actor,pending.action,pending.plan),"notice":ViewProjection.relative(pending.notice,p)})
func commit(now: int):
	if pending.is_empty() or pending.stage!="present" or not both_connected():return
	if not game.act(pending.actor,pending.action):
		pending={}
		for p in [0,1]:send_state(p)
		drive(now);return
	revision+=1;pending.stage="settle";pending.deadline=now+Config.SETTLE_MS
	for p in [0,1]:emit(p,{"op":"commit","tx":pending.id,"revision":revision,"state":state_for(p),"result":ViewProjection.relative(pending.plan.result,p)})
	save()
func actor() -> int:
	if game.phase=="battle":return game.battle.get("responder",-1)
	if game.phase=="plot_response":return 1-game.pending_plot.player
	if game.phase in ["choice","discard"]:return game.choice.get("player",-1)
	return game.current
func response_phase() -> bool:return not game.battle.is_empty() or game.phase=="plot_response" or game.resume_phase=="battle" and game.phase in ["choice","discard"]
func drive(now: int):
	last_tick=now
	if not both_connected() or not pending.is_empty():return
	if not restart_intent.is_empty():
		var task=restart_intent;restart_intent={}
		if task.action in game.legal_actions(task.player):prepare(task.player,task.action,now);return
	while not queued.is_empty():
		var task=queued.pop_front()
		if task.action in game.legal_actions(task.player):prepare(task.player,task.action,now);return
	if game.phase!="over" and not game.phase.begins_with("setup"):
		var p=actor();var legal=game.legal_actions(p) if p>=0 else []
		if legal.size()==1 and legal[0].type in ["trigger","pass","accept_plot"]:prepare(p,legal[0],now);return
	refresh_clock()
	released=true
	for p in [0,1]:send_state(p,"release")
	broadcast_clock(now);save()
func refresh_clock():
	if game.phase.begins_with("setup"):
		if opening_phase!=game.phase:opening_phase=game.phase;opening_left=[Config.OPENING_MS,Config.OPENING_MS]
		clock_kind="opening";clock_actor=-1;return
	if game.serial!=turn_serial:turn_serial=game.serial;turn_left=Config.TURN_MS
	var p=actor();var kind="response" if response_phase() else "turn"
	if kind=="response" and (clock_kind!=kind or clock_actor!=p):response_left=Config.RESPONSE_MS
	clock_actor=p;clock_kind=kind
func clock_for(p: int) -> Dictionary:
	var paused=not released or not both_connected() or not pending.is_empty() or game.phase=="over"
	var actors=[];var left=[];var total=[]
	for who in [p,1-p]:
		var active=not game.legal_actions(who).is_empty() if clock_kind=="opening" else who==clock_actor
		actors.append(active and game.phase!="over")
		left.append(opening_left[who] if clock_kind=="opening" else (response_left if clock_kind=="response" else turn_left))
		total.append(Config.OPENING_MS if clock_kind=="opening" else (Config.RESPONSE_MS if clock_kind=="response" else Config.TURN_MS))
	return {"op":"clock","revision":revision,"kind":clock_kind,"active":actors,"left":left,"total":total,"paused":paused,"connected":[peers[p]>=0,peers[1-p]>=0],"grace":[grace[p],grace[1-p]]}
func broadcast_clock(now: int):
	last_broadcast=now
	for p in [0,1]:emit(p,clock_for(p))
func tick(now: int):
	var elapsed=maxi(0,now-last_tick);last_tick=now
	if not started:return
	if game.phase!="over" and not both_connected():
		for p in [0,1]:
			if peers[p]<0:
				grace[p]=maxi(0,grace[p]-elapsed)
				if grace[p]==0:forfeit(p,"对手断线超时",now);break
	elif not pending.is_empty():
		if now>=pending.deadline:
			var flags=pending.presented if pending.stage=="present" else pending.settled
			for p in [0,1]:
				if not flags[p]:emit(p,{"op":"close","reason":"slow"});detach(p,now)
	elif released and game.phase!="over":
		if clock_kind=="opening":
			for p in [0,1]:
				if not game.legal_actions(p).is_empty():
					opening_left[p]=maxi(0,opening_left[p]-elapsed)
					if opening_left[p]==0:timeout(p,now);break
		elif clock_actor>=0:
			if clock_kind=="response":response_left=maxi(0,response_left-elapsed)
			else:turn_left=maxi(0,turn_left-elapsed)
			if (response_left if clock_kind=="response" else turn_left)==0:timeout(clock_actor,now)
	if now-last_broadcast>=250:broadcast_clock(now)
func timeout(p: int,now: int):
	var legal=game.legal_actions(p)
	if legal.is_empty():return
	var a={};var notice=game._who(p)+"选择超时 · 已自动完成必要选择"
	for kind in ["pass","accept_plot","end"]:
		var found=legal.filter(func(item):return item.type==kind)
		if not found.is_empty():a=found[0];notice=game._who(p)+{"pass":"响应超时 · 不再追加","accept_plot":"响应超时 · 放行","end":"回合超时 · 自动结束"}[kind];break
	if a.is_empty():
		var optional=legal.filter(func(item):return item.type=="choose" and item.get("id","!")=="")
		var safe=legal.filter(func(item):return item.type in ["faction","initial","initial_resource","choose","draw"])
		if not optional.is_empty():a=optional[0]
		elif not safe.is_empty():a=safe[0]
	if a.is_empty():return
	if a.type=="end" and acted_serial[p]!=game.serial:
		idle_turns[p]+=1
		if idle_turns[p]>=2:forfeit(p,"对手连续两回合未操作",now);return
	prepare(p,a,now,notice)
func forfeit(p: int,reason: String,now: int):
	if game.phase=="over":return
	pending={};queued=[];released=true;game.winner=1-p;game.phase="over";game.victory={"kind":"forfeit","reason":reason};revision+=1
	for who in [0,1]:send_state(who,"release")
	broadcast_clock(now);save()
func preview(p: int,key: String,local_key: String):
	if not issued[p].has(key) or not pending.is_empty():return
	var a=issued[p][key];var command=a
	if a.type=="ability" and a.get("src","")=="G096":command={"src":a.leader,"target":a.target,"mode":"control","use_plan":a.get("use_plan",false),"delegate":"G096"}
	if command.get("type","")!="attack" and not command.has("delegate"):return
	var values=game.attack_preview(command.src,command.target,command.mode,command)
	var options=game.attack_options(command.src,command.target,command.mode,command)
	emit(p,{"op":"preview","revision":revision,"key":local_key,"values":ViewProjection.relative(values,p),"options":ViewProjection.relative(options,p)})
func save():
	if checkpoint.is_valid():checkpoint.call(self)

func record() -> Dictionary:
	var state={}
	for prop in game.get_property_list():
		if not (prop.usage&PROPERTY_USAGE_SCRIPT_VARIABLE) or prop.name in ["rng","wave","synergy","renewal","covenant","resources","contemporary","association"]:continue
		state[prop.name]=game.get(prop.name)
	state.rng_seed=str(game.rng.seed);state.rng_state=str(game.rng.state)
	state.wave={}
	for key in ["plans","announced","queue","response_queue"]:state.wave[key]=game.wave.get(key)
	return {"code":code,"tokens":tokens,"ready":ready,"started":started,"state":state,"revision":revision,"sequence":sequence,"grace":grace,"opening_left":opening_left,"opening_phase":opening_phase,"turn_left":turn_left,"turn_serial":turn_serial,"response_left":response_left,"clock_actor":clock_actor,"clock_kind":clock_kind,"idle_turns":idle_turns,"acted_serial":acted_serial,"intent":{"player":pending.actor,"action":pending.action} if pending.get("stage","")=="present" else {},"saved_unix":Time.get_unix_time_from_system(),"build":Config.build()}
static func restore(data: Dictionary,now: int):
	if not Config.compatible(data.get("build",{})):return null
	# JSON has only floating-point numbers. Restore integral rule values before
	# strict Array/Dictionary membership checks or canonical command comparison.
	data=integer_values(data)
	var room=load("res://scripts/online/room.gd").new(str(data.code),1,now)
	for key in ["tokens","ready","started","revision","sequence","grace","opening_left","opening_phase","turn_left","turn_serial","response_left","clock_actor","clock_kind","idle_turns","acted_serial"]:room.set(key,data[key])
	for key in data.state:
		if key not in ["rng_seed","rng_state","wave"]:room.game.set(key,data.state[key])
	room.game.rng.seed=int(data.state.rng_seed);room.game.rng.state=int(data.state.rng_state)
	for key in ["plans","announced","queue","response_queue"]:room.game.wave.set(key,data.state.wave[key])
	var plans={}
	for key in room.game.wave.plans:plans[int(key)]=room.game.wave.plans[key]
	room.game.wave.plans=plans;room.restart_intent=data.get("intent",{})
	var downtime=maxi(0,int((Time.get_unix_time_from_system()-data.get("saved_unix",0))*1000))
	for p in [0,1]:room.grace[p]=maxi(0,room.grace[p]-downtime)
	return room
static func integer_values(value):
	if value is Dictionary:
		var out={}
		for key in value:out[key]=integer_values(value[key])
		return out
	if value is Array:return value.map(integer_values)
	if value is float and value==floor(value):return int(value)
	return value
