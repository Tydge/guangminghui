extends SceneTree
const ViewProjection=preload("res://scripts/online/projection.gd")
var checks=0
var failures=[]
var mains=[]
var server_pid=-1
var port=19700
var folder=""
var output=""
var live_url=""
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func wait_until(predicate: Callable,label: String,seconds: float=8) -> bool:
	var deadline=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	var okay=predicate.call();check(okay,label);return okay
func settle() -> bool:
	return await wait_until(func():return mains.all(func(m):return m.game!=null and not m.busy and not m.online.submitting),"Both clients finish presentation and settlement",15)
func action(p: int,kind: String) -> bool:
	if not await wait_until(func():return not mains[p].window_access.transitioning and not mains[p].busy,"Input transition finished before "+kind):return false
	var legal=mains[p].game.legal_actions(0).filter(func(a):return a.type==kind)
	check(not legal.is_empty(),"Client has "+kind)
	if legal.is_empty():return false
	var previous=mains[p].online.revision
	mains[p]._do_action(0,legal[0])
	check(mains[p].busy or mains[p].online.revision>previous,"Submitting "+kind+" locks input")
	if not await wait_until(func():return mains.all(func(m):return m.online.revision>previous),"Both clients receive committed "+kind):return false
	return await settle()
func capture(name: String,p: int):
	audit(mains[p],name)
	if output=="" or DisplayServer.get_name()=="headless":return
	mains[1-p].hide();mains[p].show();await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/"+name+".png");mains[1-p].show()
func audit(node: Node,label: String):
	for child in node.get_children():
		if child is Control and child.is_visible_in_tree():
			if GameLocale.english() and (child is Label or child is Button):check(not GameLocale.has_chinese(child.text) or child.text=="中文",label+" translated "+child.text)
			if child is Button and not child.clip_text and not child is OptionButton:
				var width=child.get_theme_font("font").get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
				check(width<=child.size.x-26,label+" button fits: "+child.text)
		audit(child,label)
func stop():
	for m in mains:
		if m.online.started and m.game!=null and m.game.phase!="over":m.online.send({"op":"resign"})
	await create_timer(0.15).timeout
	for m in mains:
		m.online.intentional=true;m.queue_free()
	await process_frame;await process_frame
	if server_pid>0:OS.kill(server_pid)
	print("ONLINE UI CHECKS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
func put(g,id: String,p: int,parent: String):
	g.decks.group.erase(id);g.hands[p].group.append(id);g._enter(id,p,parent);g.nodes[id].token=1
func battle_after_restart() -> bool:
	# A private checkpoint fixture exercises restart recovery and real WS battle UI.
	# No fixture command or test backdoor exists in the network protocol.
	OS.kill(server_pid)
	if not await wait_until(func():return not OS.is_process_running(server_pid),"Test host stops before checkpoint fixture"):return false
	var path=folder+"/rooms/"+mains[0].online.code+".json"
	var data=JSON.parse_string(FileAccess.get_file_as_string(path))
	var room=load("res://scripts/online/room.gd").restore(data,Time.get_ticks_msec())
	var g=GameState.new(811,true);g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}]
	for kind in g.decks:g.decks[kind]=CardDB.ids(kind)
	g.factions=["I01","I02"];g.phase="main";g.current=0;g.turns=[3,3];g.serial=20
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	put(g,"G001",0,"R0");put(g,"G004",0,"R0");put(g,"G003",1,"R1");put(g,"G002",1,"R1")
	g.nodes.R0.learned=15
	for item in [{"id":"P12","player":0},{"id":"P15","player":1}]:g.decks.plot.erase(item.id);g.hands[item.player].plot.append(item.id)
	g.decks.resource.erase("E01");g.nodes.E01={"card":"E01","owner":0,"parent":"","token":1,"attached":[],"resource_slot":0}
	room.game=g;room.revision+=10;room.pending={};room.restart_intent={};room.turn_serial=-1;room.clock_kind="";room.clock_actor=-1
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(room.record()))
	DirAccess.remove_absolute(folder+"/server.log")
	server_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",folder+"/server.log","--script","res://server/online_server.gd","--","--test-defaults","--port="+str(port),"--rooms="+folder+"/rooms"])
	if not await wait_until(func():return mains.all(func(m):return not m.online.reconnecting and not m.busy and m.game.nodes.has("E01")),"Both clients recover authoritative checkpoint",12):return false
	var a=mains[0].game.legal_actions(0).filter(func(item):return item.type=="attack" and item.src=="R0" and item.target=="G003" and item.mode=="control")[0]
	for m in mains:m.presentation_time_scale=0.20
	var revision=mains[0].online.revision
	mains[0]._do_action(0,a)
	if not await wait_until(func():return mains.all(func(m):return m.combat.stage=="trace"),"Both peers show the declaration arrow before commit"):return false
	mains[1].presentation_tween.pause();await create_timer(0.65).timeout
	check(mains.all(func(m):return m.online.revision==revision and m.game.phase=="main" and m.busy and m.online.clock.paused),"Slower peer's arrow keeps both rules and thinking clocks paused")
	mains[1].presentation_tween.play()
	if not await settle():return false
	check(mains[0].game.phase=="battle","Two real clients enter battle")
	var responder=0 if mains[0].game.battle.responder==0 else 1
	check(mains[responder].online.clock.active[0] and mains[1-responder].online.clock.active[1],"Both see same battle responder")
	check(mains[responder].online.clock.total[0]==15000,"Response duration exactly 15 seconds")
	await capture("battle-response",responder)
	# First side spends a real response; the other side receives a fresh clock.
	var legal=mains[responder].game.legal_actions(0).filter(func(item):return item.type=="self_defend" or item.type=="support")
	check(not legal.is_empty(),"Responder has genuine support/self-defense")
	mains[responder]._do_action(0,legal[0]);await process_frame
	if not await settle():return false
	check(mains[1-responder].online.clock.active[0] and mains[1-responder].online.rings[0].seconds()>14,"Response handoff resets other side to 15 seconds")
	var attacker=0
	if mains[0].game.battle.responder==0:
		var plot=mains[0].game.legal_actions(0).filter(func(item):return item.type=="plot" and item.id=="P12")[0]
		mains[0]._do_action(0,plot);await process_frame
		if not await settle():return false
		check(mains[1].game.phase=="plot_response","Counter window reaches other player")
		var before=mains[1].online.rings[0].seconds();mains[1].window_access.peek();await create_timer(0.3).timeout
		check(mains[1].window_access.browsing and mains[1].online.rings[0].seconds()<before,"Viewing battlefield doesn't pause counter clock")
		mains[1].window_access.resume();await create_timer(0.1).timeout
		await capture("counter-response",1)
		if not await action(1,"counter"):return false
		check(mains[0].game.battle.responder==0 and mains[0].online.rings[0].seconds()>14,"Counter returns a fresh response to first player")
	# Let the real server expire one response; clients must not execute timeout locally.
	var old_responder=mains[0].game.battle.responder
	var until=Time.get_ticks_msec()+18000
	var captured_warning=false
	while mains[0].game.phase=="battle" and mains[0].game.battle.responder==old_responder and Time.get_ticks_msec()<until:
		if not captured_warning and mains[old_responder].online.rings[0].seconds()<3:
			captured_warning=true;await capture("response-warning",old_responder)
		await process_frame
	check(mains[0].game.phase!="battle" or mains[0].game.battle.responder!=old_responder,"Server timeout automatically hands off")
	if not await settle():return false
	await capture("timeout-handoff",1-old_responder)
	for i in 12:
		if mains[0].game.phase!="battle":break
		var p=mains[0].game.battle.responder
		if not await action(p,"pass"):return false
	check(not mains[0].game.last_battle.is_empty() and mains[1].game.last_battle.dice==mains[0].game.last_battle.dice and mains[1].game.last_battle.success==mains[0].game.last_battle.success,"Dice/result history agrees across seats")
	for success in [false,true]:
		if not await online_recruit(success):return false
	return true
func online_recruit(success: bool) -> bool:
	OS.kill(server_pid)
	if not await wait_until(func():return not OS.is_process_running(server_pid),"Host stops for private recruit fixture"):return false
	var path=folder+"/rooms/"+mains[0].online.code+".json"
	var room=load("res://scripts/online/room.gd").restore(JSON.parse_string(FileAccess.get_file_as_string(path)),Time.get_ticks_msec())
	var g=GameState.new(1,true);g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}]
	for kind in g.decks:g.decks[kind]=CardDB.ids(kind)
	g.factions=["I01","I02"];g.phase="main";g.current=0;g.turns=[2,2];g.serial=41 if success else 40
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	var src="R0" if success else "G042";var target="G043" if success else "G005"
	if not success:put(g,"G042",0,"R0")
	else:g.nodes.R0.learned=100
	put(g,"G004",0,"R0");put(g,"G001",1,"R1");g.decks.group.erase(target);g.hands[0].group.append(target)
	for candidate in 20:
		var rng=RandomNumberGenerator.new();rng.seed=candidate+1
		if rng.randi_range(1,6)+rng.randi_range(1,6)<=10:g.rng.seed=candidate+1;break
	room.game=g;room.revision+=100;room.pending={};room.restart_intent={};room.turn_serial=-1;room.clock_kind="";room.clock_actor=-1
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(room.record()));DirAccess.remove_absolute(folder+"/server.log")
	server_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",folder+"/server.log","--script","res://server/online_server.gd","--","--test-defaults","--port="+str(port),"--rooms="+folder+"/rooms"])
	if not await wait_until(func():return mains.all(func(m):return not m.online.reconnecting and not m.busy and m.game.serial==g.serial),"Both clients resume new authoritative recruit fixture",12):return false
	var candidates=mains[0].game.legal_actions(0).filter(func(item):return item.type=="attack" and item.src==src and item.target==target and item.mode=="control")
	check(not candidates.is_empty(),"Private fixture has a legal hand attack")
	if candidates.is_empty():return false
	var a=candidates[0]
	var revision=mains[0].online.revision;mains[0]._do_action(0,a)
	if not await wait_until(func():return mains.all(func(m):return m.online.revision>revision) and mains[0].game.phase=="battle","Recruit declaration commits after both animations"):return false
	if not await settle():return false
	check(mains.all(func(m):return m.combat.ghost_id==target and not m.game.nodes.has(target) and not m.board.cards.has(target)),"Both peers show the same public recruit without inventing ownership")
	# Interrupt once more during an actual battle: the public preview must recover.
	var token=mains[1].online.token;mains[1].online.network_lost()
	if not await wait_until(func():return not mains[1].online.reconnecting and not mains[1].busy,"Recruit battle resumes after client disconnect",12):return false
	check(mains[1].online.token==token and mains[1].combat.ghost_id==target,"Reconnect restores the recruit, not a duplicate or a hidden hand")
	for i in 12:
		if mains[0].game.phase!="battle":break
		if not await action(int(mains[0].game.battle.responder),"pass"):return false
	check(mains[0].game.last_battle.success==success and mains[1].game.last_battle.success==success,"Both recruit outcomes agree with authoritative dice")
	check(mains.all(func(m):return m.combat.ghost_id=="" and m.combat.attack.is_empty()),"No recruit or arrow remains after result settlement")
	check(mains[0].game.nodes.has(target) and mains[1].game.nodes.has(target) if success else target in mains[0].game.hands[0].group and not mains[1].game.nodes.has(target),"Successful recruit enters both boards; failed recruit returns only to its owner's hand")
	return true
func run():
	get_root().size=Vector2i(1600,900)
	port+=OS.get_process_id()%1000
	folder=ProjectSettings.globalize_path("res://work/online-ui-%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(output)
		if arg.begins_with("--live-url="):live_url=arg.trim_prefix("--live-url=")
	if live_url=="":
		server_pid=OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",folder+"/server.log","--script","res://server/online_server.gd","--","--test-defaults","--port="+str(port),"--rooms="+folder+"/rooms"])
		if not await wait_until(func():return FileAccess.file_exists(folder+"/server.log") and "ONLINE READY" in FileAccess.get_file_as_string(folder+"/server.log"),"Local authoritative server starts"):await stop();return
	for p in [0,1]:
		var m=load("res://scenes/main.tscn").instantiate();m.settings_path="user://online-ui-settings-%d-%d.cfg"%[OS.get_process_id(),p];root.add_child(m);m.presentation_time_scale=0.003;m.reduced_motion=true;m.sound_volume=0
		m.online.url=live_url if live_url!="" else "ws://127.0.0.1:"+str(port);m.online.storage="user://online-ui-session-%d-%d.cfg"%[OS.get_process_id(),p];m.online.screen=true;mains.append(m)
	if "--english" in OS.get_cmdline_user_args():GameLocale.set_language("en")
	if "--mobile" in OS.get_cmdline_user_args():root.size=Vector2i(1280,720);for m in mains:m.compact=true;m._resize()
	mains[0].online.connect_join({"op":"create","build":load("res://scripts/online/config.gd").build()})
	if not await wait_until(func():return mains[0].online.in_room,"Host creates room"):await stop();return
	check(mains[0].online.code.length()==6,"Six-digit invite code")
	mains[1].online.join_code(mains[0].online.code)
	if not await wait_until(func():return mains[1].online.in_room and mains[0].online.lobby_data.get("connected",[false,false])[1],"Second client joins room"):await stop();return
	await capture("lobby",0)
	for m in mains:m.online.send({"op":"ready","value":true})
	if not await settle():await stop();return
	check(mains[0].game.phase=="setup_faction" and mains[1].game.phase=="setup_faction","Both clients start faction selection")
	for phase in ["faction","initial","initial_resource"]:
		if not await action(0,phase):await stop();return
		check(mains[0].game.opening_waiting,"First selection waits without leaking opponent choice")
		if not await action(1,phase):await stop();return
		check(mains[0].game.factions[0]==mains[1].game.factions[1],"Faction views reverse correctly")
	check(mains[0].game.phase=="draw" and mains[1].game.phase=="draw","Both clients reach first turn")
	var first=0 if mains[0].game.current==0 else 1
	if not await action(first,"draw"):await stop();return
	check(mains[first].game.legal_actions(0).any(func(a):return a.type=="end") and mains[1-first].game.legal_actions(0).is_empty(),"Only current player can act")
	check(mains[first].online.clock.active[0] and mains[1-first].online.clock.active[1],"Both see active player's clock")
	check(mains[first].online.rings.size()==2,"Both circular clocks available")
	if "--live-attack" in OS.get_cmdline_user_args():
		var candidates=mains[first].game.legal_actions(0).filter(func(a):return a.type=="attack" and a.src=="R0" and a.mode=="control" and not mains[first].game.nodes.has(a.target))
		check(not candidates.is_empty(),"Public server offers a genuine hand recruit")
		if candidates.is_empty():await stop();return
		var target=candidates[0].target;var revision=mains[first].online.revision
		for m in mains:m.presentation_time_scale=0.20
		mains[first]._do_action(0,candidates[0])
		if not await wait_until(func():return mains.all(func(m):return m.combat.stage=="trace"),"Public host delivers the declaration animation before commit"):await stop();return
		check(mains.all(func(m):return m.online.revision==revision and m.online.clock.paused),"Public host pauses true state and clocks throughout the arrow")
		if not await wait_until(func():return mains.all(func(m):return m.online.revision>revision),"Public attack declared after both presentations"):await stop();return
		if not await settle():await stop();return
		check(mains.all(func(m):return m.combat.ghost_id==target),"Public host sends the new attack cue to both peers")
		for i in 20:
			if mains[0].game.battle.is_empty() and mains[0].game.phase=="main":break
			var p=int(mains[0].game.battle.responder) if mains[0].game.phase=="battle" else int(mains[0].game.choice.player)
			var kind="pass" if mains[0].game.phase=="battle" else "choose"
			if not await action(p,kind):await stop();return
		check(mains.all(func(m):return m.combat.ghost_id=="" and m.game.battle.is_empty()),"Public recruit settles without leftover visuals")
	var draws=mains[first].game.legal_actions(0).filter(func(a):return a.type=="auto")
	if not draws.is_empty():
		mains[first]._do_action(0,draws[0]);if not await settle():await stop();return
		check(mains[first].game.groups(0).size()==mains[1-first].game.groups(1).size(),"Deployment synchronized across perspectives")
	await capture("board",first)
	# Preview comes from host; reading it never commits an attack or consumes time anew.
	var attacks=mains[first].game.legal_actions(0).filter(func(a):return a.type=="attack")
	if not attacks.is_empty():
		var a=attacks[0];var state=mains[first].game.nodes.duplicate(true)
		mains[first]._review_action(a)
		if not await wait_until(func():return not mains[first].game.preview_cache.is_empty(),"Server computes attack preview"):await stop();return
		check(mains[first].game.nodes==state,"Preview doesn't commit rules")
		mains[first]._clear(mains[first].large_layer);mains[first].preview_action={}
	if not await action(first,"end"):await stop();return
	check(mains[1-first].game.current==0,"Turn moves to other human")
	# Disconnect/resume uses saved seat token, preserving perspective and true state.
	var m=mains[first];var before=m.game.nodes.duplicate(true);var saved_token=m.online.token
	m.online.network_lost()
	if not await wait_until(func():return not m.online.reconnecting and m.online.socket!=null and not m.busy,"Automatic reconnection restores seat",10):await stop();return
	check(m.online.token==saved_token and m.game.nodes==before,"Resume preserves same seat and board")
	if "--battle" in OS.get_cmdline_user_args():
		if not await battle_after_restart():await stop();return
	# Modal browsing does not suspend network clocks or block the other player.
	var current=0 if mains[0].game.current==0 else 1
	if mains[current].game.phase=="draw":
		if not await action(current,"draw"):await stop();return
	var bank=mains[current].online.rings[0].seconds();mains[current]._inspect(mains[current].game.root(0));await create_timer(0.4).timeout
	check(mains[current].online.rings[0].seconds()<bank,"Reading a large card keeps online time running")
	mains[current]._close_inspection();mains[current].online.send({"op":"resign"})
	if not await wait_until(func():return mains.all(func(item):return item.game.phase=="over"),"Resign gives synchronized results"):await stop();return
	check(mains[current].game.winner==1 and mains[1-current].game.winner==0,"Winner relative to each seat")
	await capture("result",1-current)
	for item in mains:item._start_game()
	if not await wait_until(func():return mains.all(func(item):return item.game.phase=="setup_faction" and not item.busy),"Both request rematch in same room"):await stop();return
	check(mains[0].online.code==mains[1].online.code,"Rematch keeps room code")
	await stop()
