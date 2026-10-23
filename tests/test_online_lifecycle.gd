extends SceneTree
const Room=preload("res://scripts/online/room.gd")
const Config=preload("res://scripts/online/config.gd")
var checks=0
var failures=[]
class FakeSocket extends RefCounted:
	var messages=[]
	var state=WebSocketPeer.STATE_OPEN
	func poll():pass
	func get_ready_state():return state
	func get_available_packet_count():return 0
	func send_text(value):messages.append(JSON.parse_string(value));return OK
	func close(_code=1000,_reason=""):state=WebSocketPeer.STATE_CLOSED
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func prepared(stage: String):
	var room=Room.new("123456",775,1000);room.attach(0,11,1000);room.attach(1,12,1000);room.start(1000)
	room.prepare(0,room.game.legal_actions(0)[0],1000)
	if stage=="settle":
		for p in [0,1]:room.input(p,{"op":"presented","tx":room.pending.id},1000)
	room.outgoing=[];return room
func closes(room) -> bool:return room.outgoing.any(func(e):return e.message.op=="close")
func state(room) -> String:return JSON.stringify([room.game.nodes,room.game.opening_picks,room.game.hands,room.game.rng.state])
func reconnection_cases():
	for stage in ["present","settle"]:
		for player in [0,1]:
			for already_acknowledged in [false,true]:
				var room=prepared(stage);var event="presented" if stage=="present" else "settled";var tx=room.pending.id
				var old_revision=room.revision;var original=state(room);var old_deadline=room.pending.deadline
				room.input(player if already_acknowledged else 1-player,{"op":event,"tx":tx},1000)
				room.detach(player,6000);var remaining=old_deadline-6000
				var now=46000 if stage=="present" else 26000;room.tick(now)
				check(room.grace[player]==50000 if stage=="present" else room.grace[player]==70000,"Disconnect consumes only cumulative grace: "+stage)
				room.attach(player,30+player,now);room.outgoing=[];room.tick(now)
				check(not closes(room) and room.pending.deadline==now+remaining,"Reconnect preserves the remaining stage budget rather than its expired wall-clock deadline: "+stage)
				check(room.pending.id==tx and room.pending.stage==stage and room.revision==old_revision and state(room)==original,"Reconnect preserves transaction identity, phase, real state and RNG")
				check(not room.pending[event][player],"Resumed client must acknowledge its replay even if it acknowledged before disconnecting")
				room.input(1-player,{"op":event,"tx":tx},now)
				check(room.pending.stage==stage,"Other client cannot finish while the resumed client is replaying")
				room.input(player,{"op":event,"tx":tx+100},now);check(room.pending.stage==stage,"Wrong transaction acknowledgement is ignored")
				room.input(player,{"op":event,"tx":tx},now+10)
				if stage=="present":
					check(room.revision==old_revision+1 and room.pending.stage=="settle","Recovered presentation commits exactly once")
					var committed=state(room);room.commit(now+11);room.input(player,{"op":"presented","tx":tx},now+12)
					check(room.revision==old_revision+1 and state(room)==committed,"Duplicate commit and old presentation ACK cannot repeat the action")
					for p in [0,1]:room.input(p,{"op":"settled","tx":tx},now+20)
				else:check(room.revision==old_revision and state(room)==original,"Recovered settlement never re-applies the committed action")
				check(room.pending.is_empty() and room.released,"Recovery returns control after both stage acknowledgements")
				var revision=room.revision;room.input(player,{"op":event,"tx":tx},now+30);check(room.revision==revision,"Late acknowledgement after release is harmless")
	var room=prepared("present");room.detach(0,4000);var remaining=room.pending.timeout_left
	room.tick(9000);room.detach(1,9000);room.tick(14000);room.attach(0,21,14000);room.tick(24000)
	check(room.pending.timeout_left==remaining and not room.both_connected(),"Second disconnect and first reconnect do not restart the frozen budget")
	room.attach(1,22,24000);check(room.pending.deadline==24000+remaining,"Only the final reconnect resumes the stage timeout")
	room.tick(26000);room.detach(0,26000);room.tick(36000);room.attach(0,23,36000)
	check(room.pending.deadline==36000+remaining-2000,"Repeated disconnect does not replenish connected animation time")
	room.outgoing=[];room.tick(room.pending.deadline)
	check(closes(room),"A genuinely exhausted connected animation budget still times out")
	room=prepared("present");room.detach(0,1000);room.tick(91000)
	check(room.grace[0]==0 and room.game.phase=="over" and room.pending.is_empty(),"Paused stage cannot bypass the ninety-second disconnect limit")
func client(host,id: int):
	var socket=FakeSocket.new();host.clients[id]={"socket":socket,"room":"","seat":-1,"joined":Time.get_ticks_msec(),"window":Time.get_ticks_msec(),"count":0};return socket
func expiry_cases():
	var host=load("res://server/host.gd").new();host.storage="user://online-lifecycle-%d"%OS.get_process_id();DirAccess.make_dir_recursive_absolute(host.storage)
	for finished in [false,true]:
		var socket=client(host,11);var room=Room.new("123456",775);room.attach(0,11,0);room.touched=-600001
		room.started=finished
		if finished:room.game.phase="over"
		host.rooms[room.code]=room;host.clients[11].room=room.code;host.clients[11].seat=0;room.checkpoint=host.save_room;host.save_room(room)
		var path=host.storage.path_join(room.code+".json");host._process(0)
		check(not host.rooms.has(room.code) and host.clients[11].room=="" and host.clients[11].seat==-1,"Expired lobby/finished room clears every connected room reference")
		check(socket.messages.any(func(e):return e.op=="error" and e.reason=="expired"),"Connected client receives the existing expired-room message")
		check(not FileAccess.file_exists(path) and not room.checkpoint.is_valid() and room.peers==[-1,-1],"Room closure detaches seats and removes its checkpoint/callback")
		room.save();check(not FileAccess.file_exists(path),"A closed room cannot resurrect a checkpoint")
		for op in ["ready","leave","action","preview"]:host.receive(11,{"op":op},Time.get_ticks_msec())
		check(host.rooms.is_empty(),"Late commands after expiry are harmless")
		# Also tolerate a stale reference from older cleanup paths at every entrance.
		for op in ["ready","leave","action","ping"]:
			host.clients[11].room="missing";host.clients[11].seat=0;host.receive(11,{"op":op},Time.get_ticks_msec())
			check(host.clients[11].room=="" and host.clients[11].seat==-1 and socket.messages.back().reason=="expired","Missing-room guard safely rejects "+op)
		host.receive(11,{"op":"create","build":Config.build()},Time.get_ticks_msec());var code=host.clients[11].room
		check(code!="" and host.rooms.has(code),"The same connection may create a new room after expiry")
		var guest=client(host,12);host.receive(12,{"op":"join","code":code,"build":Config.build()},Time.get_ticks_msec())
		check(host.clients[12].seat==1,"Another player can join the replacement room")
		host.receive(11,{"op":"leave"},Time.get_ticks_msec())
		check(host.rooms.is_empty() and host.clients[11].room=="" and host.clients[12].room=="","Host departure uses the same complete room cleanup")
		check(socket.messages.back().op=="left" and guest.messages.back().reason=="closed","Leaving host gets acknowledgement; guest gets explicit closure")
		host.receive(12,{"op":"ready"},Time.get_ticks_msec());host.drop(11,Time.get_ticks_msec());host.drop(12,Time.get_ticks_msec())
		check(not FileAccess.file_exists(host.storage.path_join(code+".json")),"Host departure and late drop cannot recreate the deleted room record")
	host.receive(999,{"op":"ready"},0);check(host.clients.is_empty(),"A packet from a removed connection is ignored")
	DirAccess.remove_absolute(host.storage);host.free()
func client_expiry_cases():
	var main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://online-lifecycle-ui.cfg";root.add_child(main);await process_frame
	main.sound_volume=0;main.online.storage="user://online-lifecycle-session.cfg"
	for language in ["zh","en"]:
		GameLocale.set_language(language)
		main.online.screen=true;main.online.in_room=true;main.online.code="123456";main.online.token="test-seat";main.online.save_session();main.online.render_lobby()
		check(FileAccess.file_exists(main.online.storage),"Fixture has isolated saved seat credentials")
		main.online.receive({"op":"error","reason":"expired"});await process_frame
		var buttons=main.overlay.find_children("*","Button",true,false);var labels=main.overlay.find_children("*","Label",true,false)
		check(not main.online.in_room and not main.online.reconnecting and main.online.token=="" and not FileAccess.file_exists(main.online.storage),"Expiry notification clears credentials without a reconnect loop: "+language)
		check(buttons.any(func(b):return b.text==GameLocale.text("创建房间") and not b.disabled) and labels.all(func(label):return label.text!="123456"),"Client returns to a usable room entry instead of the stale lobby: "+language)
		check(labels.any(func(label):return label.text==GameLocale.text("房间已失效，请重新创建。")),"Player sees a localized reason for the expired room: "+language)
	main.online.leave();main.queue_free();await process_frame
	DirAccess.remove_absolute("user://online-lifecycle-ui.cfg")
func run():
	reconnection_cases();expiry_cases();await client_expiry_cases()
	print("ONLINE LIFECYCLE: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
