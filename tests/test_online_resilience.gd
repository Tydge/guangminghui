extends "res://tests/test_online_lifecycle.gd"
var main
var listener=TCPServer.new()
var peers=[]
var requests=[]
var test_url=""
var captures=[]
var output=""
func seat_cases():
	var host=load("res://server/host.gd").new();host.storage="user://online-seats-%d"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(host.storage)
	client(host,11);var old=client(host,12);var newcomer=client(host,13)
	host.receive(11,{"op":"create","build":Config.build()},1000);var code=host.clients[11].room;var room=host.rooms[code]
	host.receive(12,{"op":"join","code":code,"build":Config.build()},1000);var old_token=room.tokens[1]
	host.receive(12,{"op":"ready","value":true},1000);host.receive(12,{"op":"leave"},1000)
	check(room.tokens[1]=="" and not room.ready[1],"Voluntary departure invalidates credentials and clears readiness immediately")
	host.receive(13,{"op":"join","code":code,"build":Config.build()},1000);var new_token=room.tokens[1]
	check(new_token!="" and new_token!=old_token and not room.ready[1],"A new guest receives fresh credentials and an unready seat")
	host.receive(11,{"op":"ready","value":true},1000);check(not room.started,"Host readiness alone cannot start a replacement guest's game")
	for active in [false,true]:
		if active:host.receive(13,{"op":"ready","value":true},1000)
		host.receive(12,{"op":"resume","code":code,"token":old_token,"build":Config.build()},1000)
		check(room.peers[1]==13 and host.clients[13].room==code and newcomer.state==WebSocketPeer.STATE_OPEN,"Old guest cannot displace the new guest before or after starting")
		check(old.messages.back().reason=="expired","Old credentials receive an explicit expired response")
	host.drop(13,1000);var resumed=client(host,14);host.receive(14,{"op":"resume","code":code,"token":new_token,"build":Config.build()},2000)
	check(room.peers[1]==14 and room.tokens[1]==new_token and room.ready[1],"Temporary disconnect preserves the current guest's valid credentials and readiness")
	host.receive(14,{"op":"leave"},2000);host.receive(12,{"op":"resume","code":code,"token":new_token,"build":Config.build()},2000)
	check(room.tokens[1]=="" and room.peers[1]<0 and old.messages.back().reason=="expired","Explicitly leaving a started game also invalidates its seat credential")
	host.close_room(code,"closed",2000);host.free();DirAccess.remove_absolute("user://online-seats-%d"%OS.get_process_id())
func pump():
	while listener.is_connection_available():
		var peer=WebSocketPeer.new();peer.accept_stream(listener.take_connection());peers.append(peer)
	for peer in peers:
		peer.poll()
		while peer.get_available_packet_count()>0:requests.append(JSON.parse_string(peer.get_packet().get_string_from_utf8()))
	main.online._process(0);await process_frame
func open_socket(op: String="create"):
	main.online.leave();main.online.set_process(false);requests=[];main.online.screen=true;main.online.url=test_url
	main.online.in_room=op=="resume";main.online.token="fixture-token";main.online.code="123456"
	main.online.connect_join({"op":op,"build":Config.build(),"code":"123456","token":"fixture-token"},op=="resume")
	var deadline=Time.get_ticks_msec()+3000
	while Time.get_ticks_msec()<deadline and not requests.any(func(a):return a.op==op):await pump()
	check(main.online.socket!=null and main.online.socket.get_ready_state()==WebSocketPeer.STATE_OPEN and requests.any(func(a):return a.op==op),"Actual local WebSocket handshakes and receives the "+op+" request")
func confirmed_socket():
	await open_socket()
	var peer=peers.back();peer.send_text(JSON.stringify({"op":"joined","code":"123456","token":"fixture-token"}));peer.send_text(JSON.stringify({"op":"lobby","started":false,"connected":[true,true],"ready":[false,false],"rematch":[false,false]}))
	for i in 40:
		await pump()
		if not main.online.connecting:break
	check(main.online.in_room and not main.online.connecting,"Application-level joined and lobby messages complete the handshake")
func weak_network_cases():
	var port=24000+OS.get_process_id()%1000;check(listener.listen(port,"127.0.0.1")==OK,"Local blackhole server starts");test_url="ws://127.0.0.1:"+str(port)
	main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://online-resilience-ui.cfg";root.add_child(main);await process_frame
	main.sound_volume=0;main.online.storage="user://online-resilience-seat.cfg";main.online.set_process(false)
	for op in ["create","join","resume"]:
		await open_socket(op);check(main.online.connecting,"An open transport does not count as a confirmed "+op)
		main.online.receive({"op":"pong","nonce":0});check(main.online.connecting,"Unrelated pong does not confirm the room")
		# One real seven-second wait; subsequent cases use the same boundary directly.
		if op=="create":
			while main.online.connecting:await pump()
		else:main.online.deadline=Time.get_ticks_msec()-1;main.online._process(0)
		check(main.online.socket==null and not main.online.connecting,"Unconfirmed "+op+" stops waiting at seven seconds")
		if op!="resume":check(not main.online.reconnecting and main.overlay.find_children("*","Button",true,false).any(func(b):return b.text==GameLocale.text("创建房间") and not b.disabled),"Failed room entry offers a usable retry")
		else:check(main.online.reconnecting,"Unconfirmed resume enters bounded automatic recovery")
	await open_socket();main.online.receive({"op":"joined","code":"123456","token":"fixture-token"});main.online.deadline=Time.get_ticks_msec()-1;main.online._process(0)
	check(main.online.reconnecting,"A joined reply without a lobby/state cannot leave the UI permanently waiting")
	for fault in ["silence","pong","action","present","settle","preview","ready","rematch"]:
		await confirmed_socket();var s=main.online;var epoch_before=s.epoch;var now=Time.get_ticks_msec()
		if fault=="silence":s.last_received_at=now-Config.SILENCE_MS
		elif fault=="pong":
			s.ping_nonce=42;s.pong_deadline=now-1;s.receive({"op":"pong","nonce":41});check(s.pong_deadline>0,"An old pong cannot acknowledge a newer ping")
		else:
			s.wait_for(fault,Config.CONNECT_MS);s.wait_deadline=now-1;s.receive({"op":"pong","nonce":s.ping_nonce})
		s.check_deadlines(Time.get_ticks_msec())
		check(s.reconnecting and s.socket==null and s.epoch==epoch_before+1 and s.wait_kind=="","Open but unresponsive "+fault+" recovers and cancels stale local work")
		check(requests.all(func(a):return a.op!="action"),"Recovery never blindly replays a possibly committed action")
	await confirmed_socket();var s=main.online;var now=Time.get_ticks_msec();s.submitting=true;s.submitted_key="0:1"
	s.wait_for("action",Config.CONNECT_MS,now);var deadline=s.wait_deadline;s.receive({"op":"accepted","id":"wrong","queued":true},now)
	check(s.wait_deadline==deadline,"Unrelated acceptance cannot extend the submitted command deadline")
	s.receive({"op":"accepted","id":"0:1","queued":true},now);check(s.wait_deadline==now+Config.PRESENT_MS+Config.SETTLE_MS+Config.CONNECT_MS,"Simultaneous opening choices receive the legitimate queue budget")
	var clock={"connected":[true,true],"active":[false,false],"paused":true,"left":[15000,15000],"total":[15000,15000],"grace":[90000,90000]}
	s.apply_clock(clock);check(s.wait_left<0,"Ordinary animation pause does not disable the operation watchdog")
	s.wait_for("present",Config.PRESENT_MS+Config.CONNECT_MS);clock.connected=[true,false];s.apply_clock(clock);var left=s.wait_left;s.wait_deadline=now-1000;s.check_deadlines(now)
	check(not s.reconnecting and left>0,"Waiting for a disconnected opponent preserves the stage budget")
	clock.connected=[true,true];s.apply_clock(clock);check(s.wait_left<0 and s.wait_deadline>=now+left,"Opponent return resumes the preserved stage budget")
	for fault in ["action","preview","ready","rematch"]:
		clock.connected=[true,false];s.apply_clock(clock);s.wait_for(fault,Config.CONNECT_MS);check(s.wait_left<0,"An absent opponent does not suppress the server's own "+fault+" acknowledgement deadline")
	s.clear_wait();s.pong_deadline=now+1000;s.ping_nonce=55;s.receive({"op":"pong","nonce":55});check(s.pong_deadline==0,"Correct heartbeat acknowledgement restores liveness")
	s.network_lost();var retry_limit=s.retry_until;s.network_lost();check(s.retry_until==retry_limit,"Repeated network errors do not replenish the reconnect allowance")
	s.retry_until=Time.get_ticks_msec()-1;s._process(0);check(not s.reconnecting,"Automatic recovery stops with retry/back controls when its budget expires")
func take(name: String):
	if output=="" or DisplayServer.get_name()=="headless":return
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output+"/"+name+".png");captures.append(name)
func lost_confirmation_case():
	await confirmed_socket();var room=prepared("present");var initial=room.state_for(0);var command=initial.actions[0];var canonical=room.issued[0][command._net]
	main.online.started=true;main.online.revision=room.revision;main._online_install(initial,true);main._set_busy(false)
	main.online.submit(command)
	for i in 60:
		await pump()
		if requests.any(func(a):return a.op=="action"):break
	check(requests.filter(func(a):return a.op=="action").size()==1 and main.busy,"A real submission reaches the open server once and locks the UI")
	check(room.game.act(0,canonical),"Fixture authority commits the command while its confirmation is lost");room.revision+=1
	main.online.receive({"op":"pong","nonce":main.online.ping_nonce});main.online.wait_deadline=Time.get_ticks_msec()-1;await pump()
	check(main.online.reconnecting,"A lost action confirmation is detected even with a live pong stream")
	main.online.retry_at=0
	for i in 100:
		await pump()
		if requests.any(func(a):return a.op=="resume"):break
	check(requests.any(func(a):return a.op=="resume") and requests.filter(func(a):return a.op=="action").size()==1,"Recovery asks for authoritative state instead of resubmitting the action")
	var state=room.state_for(0);var peer=peers.back()
	for message in [{"op":"joined","code":"123456","token":"fixture-token"},{"op":"lobby","started":true,"rematch":[false,false]},{"op":"state","resume":true,"revision":room.revision,"state":state},{"op":"release","revision":room.revision,"state":state}]:peer.send_text(JSON.stringify(message))
	for i in 100:
		await pump()
		if not main.online.reconnecting and not main.busy:break
	check(not main.online.reconnecting and not main.busy and main.online.revision==room.revision and main.game.opening_waiting,"Recovered UI matches the already committed server state and unlocks normally")
func rematch_cases():
	await confirmed_socket();main.online.started=true;main.reduced_motion=true;main.presentation_time_scale=0.02
	var room=prepared("present");main.game=room.game;main.game.factions=["I01","I02"];main.game.nodes={}
	for p in [0,1]:main.game.nodes["R%d"%p]={"card":main.game.factions[p],"owner":p,"parent":"","token":0,"attached":[]}
	main.game.phase="over";main.game.winner=0;main.game.victory={"kind":"forfeit","reason":"对手认输"};main._set_busy(false)
	for language in ["zh","en"]:
		GameLocale.set_language(language)
		for compact in [false,true]:
			main.compact=compact;root.size=Vector2i(1280,720) if compact else Vector2i(1600,900);await process_frame
			main.online.lobby_data={"started":true,"rematch":[false,false]};main._refresh();await process_frame
			var panel=main.overlay.find_child("VictoryWindow",true,false);var button=main.overlay.find_child("OnlineRematchButton",true,false)
			main.online.receive({"op":"lobby","started":true,"rematch":[false,true]})
			check(main.overlay.find_child("VictoryWindow",true,false)==panel and button.text==GameLocale.text("接受邀请"),"Invitation updates the existing result panel in place")
			check(main.overlay.find_child("OnlineRematchStatus",true,false).text==GameLocale.text("对手邀请再来一局"),"Invitation is visible in "+language)
			await take(language+str(compact)+"-invitation")
			main.window_access.peek()
			for i in 12:await process_frame
			main.online.receive({"op":"lobby","started":true,"rematch":[false,true]});check(main.window_access.browsing and not main.overlay.visible,"Invitation cannot force a hidden result panel over battlefield browsing")
			main.window_access.resume()
			for i in 12:await process_frame
			main.online.rematch_request();check(button.disabled and button.text==GameLocale.text("请求中…"),"Clicking Accept locks the request while awaiting acknowledgement")
			main.online.receive({"op":"lobby","started":true,"rematch":[true,false]});check(button.disabled and button.text==GameLocale.text("等待确认") and main.online.wait_kind=="","Acknowledged request visibly waits for the other human without a network timeout")
			await take(language+str(compact)+"-waiting")
			for b in [button]:check(main.get_global_rect().encloses(b.get_global_rect()) and b.get_theme_font("font").get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x<=b.size.x-26,"Localized rematch control fits the desktop/mobile viewport")
	check(GameLocale.missing.is_empty(),"Networking statuses have complete English translations")
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(output)
	seat_cases();await weak_network_cases();await lost_confirmation_case();await rematch_cases()
	main.online.leave();main.queue_free();await process_frame;listener.stop()
	for peer in peers:peer.close()
	DirAccess.remove_absolute("user://online-resilience-ui.cfg");DirAccess.remove_absolute("user://online-resilience-seat.cfg")
	print("ONLINE RESILIENCE: "+JSON.stringify({"checks":checks,"failures":failures,"captures":captures}));quit(0 if failures.is_empty() else 1)
