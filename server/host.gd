extends Node
const Room=preload("res://scripts/online/room.gd")
const Config=preload("res://scripts/online/config.gd")
var listener=TCPServer.new()
var clients={}
var rooms={}
var next_peer=1
var storage="user://online-rooms"
var port=19081
var address="127.0.0.1"
var stopping=false
var last_checkpoint=0
func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
		if arg.begins_with("--bind="):address=arg.trim_prefix("--bind=")
		if arg.begins_with("--rooms="):storage=arg.trim_prefix("--rooms=")
	CardDB.load_all();DirAccess.make_dir_recursive_absolute(storage)
	for file in DirAccess.get_files_at(storage):
		if not file.ends_with(".json"):continue
		var data=JSON.parse_string(FileAccess.get_file_as_string(storage.path_join(file)))
		if data is Dictionary:
			var room=Room.restore(data,Time.get_ticks_msec())
			if room!=null and room.started and room.game.phase!="over":room.checkpoint=save_room;rooms[room.code]=room
	var error=listener.listen(port,address)
	if error!=OK:push_error("Cannot bind online server: "+str(error));get_tree().quit(1);return
	print("ONLINE READY ",address,":",port," build=",Config.build().code)
func _process(_delta):
	var now=Time.get_ticks_msec()
	while listener.is_connection_available():
		var stream=listener.take_connection()
		if clients.size()>=32:stream.disconnect_from_host();continue
		var ws=WebSocketPeer.new();ws.inbound_buffer_size=65536;ws.outbound_buffer_size=4194304;ws.max_queued_packets=64
		if ws.accept_stream(stream)!=OK:continue
		clients[next_peer]={"socket":ws,"room":"","seat":-1,"joined":now,"window":now,"count":0};next_peer+=1
	for id in clients.keys():
		if not clients.has(id):continue
		var c=clients[id];var ws=c.socket;ws.poll()
		if ws.get_ready_state()==WebSocketPeer.STATE_CLOSED:drop(id,now);continue
		if ws.get_ready_state()!=WebSocketPeer.STATE_OPEN:continue
		if c.room=="" and now-c.joined>10000:ws.close(1008,"Join timeout");drop(id,now);continue
		var count=0
		while ws.get_available_packet_count()>0 and count<16:
			var bytes=ws.get_packet();count+=1
			if bytes.size()>16384:ws.close(1009,"Packet too large");break
			if now-c.window>1000:c.window=now;c.count=0
			c.count+=1
			if c.count>30:ws.close(1008,"Rate limited");break
			var message=JSON.parse_string(bytes.get_string_from_utf8())
			if message is Dictionary:receive(id,message,now)
	for code in rooms.keys():
		var room=rooms[code];room.tick(now);flush(room,now)
		if not room.both_connected() and now-room.touched>600000 and (not room.started or room.game.phase=="over"):
			close_room(code,"expired",now)
	if now-last_checkpoint>=2000:
		last_checkpoint=now
		for room in rooms.values():
			if room.started and room.game.phase!="over" and room.both_connected():save_room(room)
	return
func send(id: int,message: Dictionary):
	if clients.has(id) and clients[id].socket.get_ready_state()==WebSocketPeer.STATE_OPEN:clients[id].socket.send_text(JSON.stringify(message))
func clear_client_room(id: int,now: int):
	if not clients.has(id):return
	clients[id].room="";clients[id].seat=-1;clients[id].joined=now
func close_room(code: String,reason: String,now: int,leaving_peer: int=-1):
	var room=rooms.get(code)
	rooms.erase(code)
	for id in clients:
		if clients[id].room!=code:continue
		clear_client_room(id,now)
		if id!=leaving_peer:send(id,{"op":"error","reason":reason})
	if room!=null:
		room.checkpoint=Callable();room.peers=[-1,-1];room.outgoing=[]
	if FileAccess.file_exists(storage.path_join(code+".json")):DirAccess.remove_absolute(storage.path_join(code+".json"))
func receive(id: int,message: Dictionary,now: int):
	if not clients.has(id):return
	var c=clients[id];var op=message.get("op","")
	if c.room!="" and (not rooms.has(c.room) or c.seat not in [0,1] or rooms[c.room].peers[c.seat]!=id):
		clear_client_room(id,now);send(id,{"op":"error","reason":"expired"});return
	if op=="ping":send(id,{"op":"pong","nonce":message.get("nonce",0)});return
	if c.room!="":
		var room=rooms[c.room]
		if op=="leave":
			if room.started:room.forfeit(c.seat,"对手离开房间",now)
			elif c.seat==0:
				close_room(room.code,"closed",now,id);send(id,{"op":"left"});return
			room.leave_seat(c.seat,now);clear_client_room(id,now);send(id,{"op":"left"});return
		room.input(c.seat,message,now);return
	if op not in ["create","join","resume"]:return
	if not Config.compatible(message.get("build",{})):send(id,{"op":"error","reason":"version"});return
	var room=null;var seat=-1
	if op=="create":
		if rooms.size()>=16:send(id,{"op":"error","reason":"full"});return
		var code=""
		while code=="" or rooms.has(code):code="%06d"%(Crypto.new().generate_random_bytes(4).decode_u32(0)%1000000)
		room=Room.new(code,0,now);room.checkpoint=save_room;rooms[code]=room;seat=0
	else:
		var code=str(message.get("code",""))
		if not rooms.has(code):send(id,{"op":"error","reason":"missing"});return
		room=rooms[code]
		if op=="resume":
			var token=str(message.get("token",""))
			for p in [0,1]:
				if token==room.tokens[p] and token!="":seat=p
			if seat<0:send(id,{"op":"error","reason":"expired"});return
			if room.peers[seat]>=0 and room.peers[seat]!=id:
				var old=room.peers[seat]
				if clients.has(old):clients[old].room="";clients[old].seat=-1;clients[old].socket.close(1000,"Session resumed")
		else:
			if room.started or room.peers[1]>=0:send(id,{"op":"error","reason":"full"});return
			seat=1;room.claim_seat(seat)
	c.room=room.code;c.seat=seat;room.attach(seat,id,now);flush(room,now)
func flush(room,now: int):
	var messages=room.outgoing;room.outgoing=[]
	for item in messages:
		if item.message.op=="close":
			if clients.has(item.peer):clients[item.peer].socket.close(1011,"Presentation timeout");drop(item.peer,now)
		else:send(item.peer,item.message)
func drop(id: int,now: int):
	if not clients.has(id):return
	var c=clients[id];clients.erase(id)
	if c.room!="" and rooms.has(c.room) and rooms[c.room].peers[c.seat]==id:rooms[c.room].detach(c.seat,now)
func save_room(room):
	var path=storage.path_join(room.code+".json");var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:push_error("Cannot save room checkpoint");return
	file.store_string(JSON.stringify(room.record()));file.close();DirAccess.rename_absolute(path+".tmp",path)
func _exit_tree():
	for room in rooms.values():save_room(room)
