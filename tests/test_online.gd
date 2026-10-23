extends SceneTree
const Room=preload("res://scripts/online/room.gd")
const ViewProjection=preload("res://scripts/online/projection.gd")
const RemoteState=preload("res://scripts/online/remote_state.gd")
var checks=0
var failures=[]
var now=1000
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func finish(room):
	for i in 150:
		if room.pending.is_empty():return
		var id=room.pending.id
		for p in [0,1]:room.input(p,{"op":"presented","tx":id},now)
		for p in [0,1]:room.input(p,{"op":"settled","tx":id},now)
		check(room.sequence<1000,"Automatic settlement bounded")
	push_error("Settlement did not finish")
func choose(room,p: int,kind: String):
	var action=room.game.legal_actions(p).filter(func(a):return a.type==kind)[0]
	room.prepare(p,action,now);finish(room)
func opened():
	var room=Room.new("123456",881,now);room.attach(0,11,now);room.attach(1,12,now);room.input(0,{"op":"ready"},now);room.input(1,{"op":"ready"},now)
	choose(room,0,"faction");choose(room,1,"faction");choose(room,0,"initial");choose(room,1,"initial");choose(room,0,"initial_resource");choose(room,1,"initial_resource")
	return room
func put(g,id: String,p: int):
	for kind in g.decks:
		g.decks[kind].erase(id);g.discards[kind].erase(id)
		for who in [0,1]:g.hands[who][kind].erase(id)
	g.nodes.erase(id);g.hands[p].group.append(id);g._enter(id,p,g.root(p));g.nodes[id].token=1
func run():
	var room=Room.new("123456",879,now);room.attach(0,11,now);room.attach(1,12,now);room.input(0,{"op":"ready"},now)
	check(not room.started,"Both seats must prepare")
	room.input(1,{"op":"ready"},now);check(room.started,"Both prepared starts room")
	check(room.game.legal_actions(1).any(func(a):return a.type=="faction"),"Second human can choose faction")
	var view=room.state_for(0);var key=view.actions[0]._net;var original=room.game.rng.state
	room.intent(0,key,now)
	check(room.game.opening_picks.faction[0]=="" and room.game.rng.state==original,"Preparing changes neither live choice nor RNG")
	room.input(0,{"op":"presented","tx":room.pending.id},now)
	check(room.game.opening_picks.faction[0]=="","One finished client cannot commit early")
	var p1=room.state_for(1).actions[1]._net;room.intent(1,p1,now)
	check(room.queued.size()==1,"Simultaneous opening intent queued")
	finish(room)
	check(room.game.phase=="setup_group" and room.game.factions[0]!="" and room.game.factions[1]!="","Both choices revealed together after transactions")
	check(room.game.nodes.size()==2,"No automatic AI initial group")
	choose(room,0,"mulligan");check(room.game.mulligans==[1,0],"Human mulligans independent")
	choose(room,0,"initial")
	check(room.game.nodes.size()==2,"Initial group waits for both players")
	check(ViewProjection.view(room.game,0).opening_waiting,"Confirmed player sees waiting state")
	choose(room,1,"initial")
	check(room.game.phase=="setup_resource" and room.game.nodes.size()==4,"Initial groups enter together")
	var candidates=room.game.resource_candidates[1].duplicate();view=room.state_for(0)
	check(view.resource_candidates[1].is_empty(),"Opponent resource candidates hidden")
	for id in candidates:check(id not in JSON.stringify(view),"Candidate identity absent from opponent packet: "+id)
	choose(room,0,"initial_resource");check(room.game.hands[0].resource.is_empty(),"Opening resource picks staged until both confirm")
	choose(room,1,"initial_resource")
	check(room.game.phase=="draw" and room.game.hands[0].resource.size()==1 and room.game.hands[1].resource.size()==1,"Both resource hands populated")
	check(room.game.hands[1-room.game.current].plot.size()==3,"Only second player receives extra plot")
	check(room.game.validate().is_empty(),"Duel opening conservation")
	for p in [0,1]:
		view=room.state_for(p);var text=JSON.stringify(view)
		for a in view.actions:
			check(room.issued[p].has(a._net) and room.issued[p][a._net].type==a.type,"Opaque action IDs survive perspective mapping")
		for kind in room.game.decks:
			for id in room.game.decks[kind]:check(('"'+id+'"') not in text,"Deck identity not serialized")
			for id in room.game.hands[1-p][kind]:
				if id not in room.game.exposed:check(('"'+id+'"') not in text,"Opponent hand identity not serialized")
		check(not view.has("rng") and not view.has("rng_state"),"No server RNG on wire")
		var remote=RemoteState.new();remote.install(JSON.parse_string(text))
		check(remote.current==room.game.current^p,"Current player remapped")
		check(remote.owner("R0")==0 and remote.factions[0]==room.game.factions[p],"Both clients see own faction on left")
		for id in room.game.nodes:
			var local_id=ViewProjection.relative(id,p)
			for stat in ["p","gp","r","slots"]:check(remote.stat(local_id,stat)==room.game.stat(id,stat),"Remote effective stat matches host")
		check(not remote.act(0,{}),"Read-only client cannot resolve rules")
	var saved=JSON.parse_string(JSON.stringify(room.record()));var restored=Room.restore(saved,now)
	check(restored.game.rng.state==room.game.rng.state and restored.game.rng.seed==room.game.rng.seed,"Checkpoint retains full 64-bit RNG")
	check(restored.game.validate().is_empty(),"Checkpoint restores legal board")
	for id in restored.game.nodes:
		check(restored.state_for(1).nodes[ViewProjection.relative(id,1)].owner==1-int(restored.game.nodes[id].owner),"JSON checkpoint restores seat-relative ownership")
	check(ViewProjection.relative({"owner":0.0},1).owner==1,"JSON numeric owners reverse correctly")
	room=opened();choose(room,room.game.current,"draw")
	var player=room.game.current;room.game.turns=[2,2]
	# Both sides have real support choices; don't let an empty response skip the test.
	put(room.game,"G001",1-player);put(room.game,"G004",player)
	var attack=room.game.legal_actions(player).filter(func(a):return a.type=="attack" and a.src==room.game.root(player) and a.target=="G001" and a.mode=="control")[0]
	room.prepare(player,attack,now);finish(room)
	check(room.game.phase=="battle","Controlled fixture reaches interactive battle")
	if room.game.phase=="battle":
		check(room.response_left==15000,"Every battle response starts at 15 seconds")
		var responder=room.actor();var bank=room.turn_left;now+=7000;room.tick(now)
		check(room.response_left==8000 and room.turn_left==bank,"Only response clock runs in combat")
		var support=room.game.legal_actions(responder).filter(func(a):return a.type!="pass")
		if not support.is_empty():
			room.prepare(responder,support[0],now);var before=room.response_left;now+=2000;room.tick(now)
			check(room.response_left==before,"Animations never consume thinking time")
			finish(room)
			if room.game.phase=="battle":check(room.response_left==15000 and room.actor()!=responder,"Handoff gives opponent a fresh 15 seconds")
	room=opened();choose(room,room.game.current,"draw");player=room.game.current
	var bank=room.turn_left;now+=1000;room.tick(now);check(room.turn_left==bank-1000,"Main turn counts down")
	room.detach(1-player,now);bank=room.turn_left;now+=2000;room.tick(now)
	check(room.turn_left==bank and room.grace[1-player]==88000,"Disconnect pauses thinking and consumes shared grace")
	room.attach(1-player,99,now);now+=500;room.tick(now);check(room.turn_left==bank-500,"Reconnect resumes remaining turn")
	room.detach(1-player,now);now+=1000;room.tick(now);check(room.grace[1-player]==87000,"Repeated disconnect doesn't refresh grace")
	now+=88000;room.tick(now);check(room.game.phase=="over" and room.game.winner==player,"Grace exhaustion records victory")
	room=opened();choose(room,room.game.current,"draw");room.turn_left=1;now+=2;room.tick(now)
	check(not room.pending.is_empty() and room.pending.action.type=="end","Main timeout ends instead of attacking/spending")
	var before=room.game.rng.state;room.input(0,{"op":"action","id":"forged"},now);check(room.game.rng.state==before,"Forged command cannot mutate state")
	print("ONLINE CHECKS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
