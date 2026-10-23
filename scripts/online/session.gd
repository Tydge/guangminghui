extends Node
const Config=preload("res://scripts/online/config.gd")
const ViewProjection=preload("res://scripts/online/projection.gd")
const RemoteState=preload("res://scripts/online/remote_state.gd")
const ClockRing=preload("res://scripts/online/clock_ring.gd")
var host: WeakRef
var m:
	get:return host.get_ref()
var socket: WebSocketPeer
var url=Config.URL
var storage="user://online-session.cfg"
var code=""
var token=""
var in_room=false
var started=false
var connecting=false
var reconnecting=false
var intentional=false
var screen=false
var ready_self=false
var lobby_data={}
var clock={}
var revision=-1
var tx=-1
var epoch=0
var deadline=0
var retry_at=0
var retry_until=0
var ping_at=0
var pending_join={}
var last_error=""
var input_code=""
var submitting=false
var submitted_revision=-1
var preview_wait={}
var ring_layer: Control
var rings=[]
var saved_reader=""
func _init(main):host=weakref(main)
func _ready():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-url="):url=arg.trim_prefix("--online-url=")
		if arg.begins_with("--online-storage="):storage=arg.trim_prefix("--online-storage=")
	ring_layer=Control.new();ring_layer.name="OnlineClocks";ring_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;ring_layer.z_index=1000;m.add_child(ring_layer);ring_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ring_layer.hide()
	for p in [0,1]:
		var ring=ClockRing.new();ring.caption="你" if p==0 else "对手"
		if p==0:ring.warn=func():m._sound("select")
		ring_layer.add_child(ring);rings.append(ring)
func _process(_delta):
	var now=Time.get_ticks_msec()
	ring_layer.visible=started
	for p in [0,1]:rings[p].position=Vector2(m.size.x-260+p*80,15);rings[p].reduced=m.reduced_motion
	if socket!=null:
		socket.poll();var state=socket.get_ready_state()
		if state==WebSocketPeer.STATE_OPEN:
			if connecting:
				connecting=false;send(pending_join)
			while socket!=null and socket.get_available_packet_count()>0:
				var bytes=socket.get_packet()
				if bytes.size()>4194304:network_lost();break
				var data=JSON.parse_string(bytes.get_string_from_utf8())
				if data is Dictionary:receive(data)
			if now-ping_at>10000:send({"op":"ping"});ping_at=now
		elif state==WebSocketPeer.STATE_CLOSED:network_lost()
	if connecting and now>deadline:network_lost()
	if reconnecting and socket==null:
		if now>retry_until:last_error="重连超时，返回房间后可再次尝试。";reconnecting=false;if_screen_error()
		elif now>=retry_at:connect_join({"op":"resume","code":code,"token":token,"build":Config.build()},true)
func send(data: Dictionary):
	if socket!=null and socket.get_ready_state()==WebSocketPeer.STATE_OPEN:socket.send_text(JSON.stringify(data))
func connect_join(message: Dictionary,retry: bool=false):
	if connecting:return
	pending_join=message;intentional=false;connecting=true;deadline=Time.get_ticks_msec()+7000
	socket=WebSocketPeer.new();socket.inbound_buffer_size=4194304;socket.outbound_buffer_size=65536;socket.max_queued_packets=128
	if socket.connect_to_url(url)!=OK:network_lost();return
	if not retry:last_error="";render_entry()
func network_lost():
	if socket!=null:socket.close();socket=null
	connecting=false
	if intentional:return
	if in_room:
		if not reconnecting:
			reconnecting=true;retry_until=Time.get_ticks_msec()+90000;epoch+=1;m._finish_presentation(false);m.board.reset_motion();submitting=false
			if started:pause_clock();m._toast("连接中断，正在自动重连…");m._online_wait()
		retry_at=Time.get_ticks_msec()+1500
	else:last_error="无法连接对战服务器，可重试或返回本地游戏。";if_screen_error()
func pause_clock():
	if not clock.is_empty():clock.paused=true;apply_clock(clock)
func if_screen_error():
	if screen and not started:render_entry()
	elif started:connection_error()
func connection_error():
	pause_clock();m._set_busy(false)
	var p=panel("连接中断")
	m._paragraph(last_error,p,Rect2(28,120,p.size.x-56,130),25,m.CREAM)
	if token!="":
		var retry=m._button("重试连接",func():reconnecting=true;retry_until=Time.get_ticks_msec()+90000;retry_at=0;m._clear(m.overlay);m._online_wait(),p,true);retry.position=Vector2(28,p.size.y-80)
	m._button("返回主菜单",leave,p).position=Vector2(p.size.x-220,p.size.y-80)
func enter():
	screen=true;last_error="";render_entry()
func panel(title: String) -> Panel:
	m._clear(m.overlay);m._clear(m.large_layer);m.modal_open=true;m._dim(m.overlay,0.85)
	var extent=Vector2(minf(900,m.size.x-90),minf(560,m.size.y-80));var p=m._panel(m.overlay,Rect2((m.size-extent)/2,extent));p.name="OnlineLobby"
	m._label(title,p,34,m.GOLD).position=Vector2(28,24)
	return p
func render_entry():
	if not screen or started:return
	var p=panel("好友对战");var width=p.size.x
	m._paragraph("创建房间，把房间号发给朋友。无需注册。",p,Rect2(28,88,width-56,60),22,m.TEAL)
	var create=m._button("创建房间",func():connect_join({"op":"create","build":Config.build()}),p,true);create.position=Vector2(28,175);create.size=Vector2(width-56,60);create.disabled=connecting
	var input=LineEdit.new();input.name="RoomCode";input.placeholder_text=GameLocale.text("输入6位房间号");input.text=input_code;input.max_length=6;input.position=Vector2(28,270);input.size=Vector2(width-245,62);input.add_theme_font_size_override("font_size",28);p.add_child(input)
	input.text_changed.connect(func(value):input_code=value.strip_edges())
	var join=m._button("加入房间",func():join_code(input.text),p,true);join.position=Vector2(width-200,270);join.size=Vector2(172,62);join.disabled=connecting
	input.text_submitted.connect(join_code)
	var saved=load_session()
	if not saved.is_empty():
		var resume=m._button("重返上次房间",func():code=saved.code;token=saved.token;in_room=true;connect_join({"op":"resume","code":code,"token":token,"build":Config.build()}),p);resume.position=Vector2(28,365);resume.size=Vector2(260,50);resume.disabled=connecting
	m._paragraph("正在连接…" if connecting else last_error,p,Rect2(28,p.size.y-130,width-56,52),19,m.TEAL if connecting else Color("e4ac94"))
	m._button("返回",leave,p).position=Vector2(28,p.size.y-70)
func join_code(value: String):
	input_code=value.strip_edges()
	if input_code.length()!=6 or not input_code.is_valid_int():last_error="请输入6位数字房间号。";render_entry();return
	connect_join({"op":"join","code":input_code,"build":Config.build()})
func render_lobby():
	if not screen or started:return
	var p=panel("好友对战");var width=p.size.x
	m._paragraph("房间号",p,Rect2(28,92,220,36),21,m.TEAL)
	m._label(code,p,52,m.GOLD).position=Vector2(28,128)
	m._button("复制房间号",func():DisplayServer.clipboard_set(code);m._toast("房间号已复制"),p).position=Vector2(width-230,140)
	var connected=lobby_data.get("connected",[true,false]);var prepared=lobby_data.get("ready",[false,false]);ready_self=prepared[0]
	for who in [0,1]:
		var text=("你" if who==0 else "对手")+" · "+("已准备" if prepared[who] else ("未准备" if connected[who] else "等待加入"))
		m._paragraph(text,p,Rect2(28+who*(width-56)/2,240,(width-70)/2,60),27,m.TEAL if prepared[who] else m.CREAM)
	m._paragraph("回合120秒 · 每次战斗响应15秒 · 断线自动重连",p,Rect2(28,330,width-56,75),20,m.CREAM)
	var button=m._button("取消准备" if ready_self else "准备开战",func():send({"op":"ready","value":not ready_self}),p,true);button.position=Vector2(width-250,p.size.y-80);button.size=Vector2(222,55);button.disabled=connecting or reconnecting
	m._button("离开房间",ask_leave,p).position=Vector2(28,p.size.y-80)
func receive(data: Dictionary):
	match data.get("op",""):
		"joined":
			var resumed=reconnecting
			code=str(data.code);token=str(data.token);in_room=true;reconnecting=false;connecting=false;save_session()
			if resumed and started:m._toast("已重新连接，继续对局。")
		"lobby":lobby_data=data;if not started:render_lobby()
		"clock":apply_clock(data)
		"state":
			started=true
			if not started or data.get("resume",false) or m.game==null or m.game.phase=="over" and data.state.phase.begins_with("setup"):epoch+=1;m._online_install(data.state,true)
			else:m._online_install(data.state,false)
			started=true;revision=int(data.revision);submitting=false
		"prepare":
			revision=int(data.revision);tx=int(data.tx);submitting=true;m._online_prepare(data)
		"commit":
			revision=int(data.revision);tx=int(data.tx);m._online_commit(data)
		"release":
			# An older release can still be in flight when the player submits a command.
			# Keep that command locked until its own transaction advances the revision.
			if submitting and int(data.revision)<=submitted_revision:return
			if data.has("clock"):apply_clock(data.clock)
			if m.presenting or data.state.phase=="over" and m.busy:epoch+=1;m._finish_presentation(false);m.board.reset_motion()
			revision=int(data.revision);submitting=false;m._online_install(data.state,false);m._set_busy(false);m._refresh()
			if saved_reader!="":var id=saved_reader;saved_reader="";m._inspect(id)
		"preview":
			if int(data.revision)!=revision or preview_wait.is_empty() or data.key!=ViewProjection.preview_key(preview_wait):return
			m.game.preview_cache[data.key]={"values":data.values,"options":data.options};var a=preview_wait;preview_wait={};m._review_action(a)
		"left":pass
		"error":
			var messages={"version":"双方需要相同版本，请先检查更新。","missing":"房间不存在或已结束。","full":"房间已满或正在对战。","expired":"房间已失效，请重新创建。","stale":"局势已更新，请重新选择。","busy":"正在结算，请稍候。","reconnecting":"正在等待对手重连。","closed":"房主已离开，请重新创建房间。"}
			last_error=messages.get(data.get("reason",""),"连接失败，请重试。")
			if data.get("reason","") in ["missing","expired","version","closed"]:
				in_room=false;token="";clear_session();reconnecting=false
				if socket!=null:socket.close();socket=null
			submitting=false
			if started and not in_room:connection_error()
			elif started:
				m._toast(last_error)
				if not m.presenting:m._set_busy(false);m._refresh()
			else:
				if not in_room and socket!=null:socket.close();socket=null
				render_entry()
func apply_clock(data: Dictionary):
	clock=data
	for p in [0,1]:rings[p].update_clock(data.active[p],data.paused,data.left[p],data.total[p])
	if started and m.game!=null:
		var label=m.hud.find_child("OnlineStatus",true,false)
		if label!=null:
			label.text=GameLocale.text("对局结束" if m.game.phase=="over" else status_text())
			if not data.connected[1] and m.game.phase!="over":label.text+=" · "+str(ceili(data.grace[1]/1000.0))+"s"
func status_text() -> String:
	if reconnecting:return "正在重新连接…"
	if not clock.is_empty() and not clock.connected[1]:return "等待对手重连"
	if m.game==null:return "好友对战"
	if submitting and not m.presenting:return "正在提交操作…"
	if m.game.phase.begins_with("setup"):return "已确认 · 等待对手" if m.game.opening_waiting else {"setup_faction":"选择光明会","setup_group":"选择初始手下","setup_resource":"选择初始资源"}.get(m.game.phase,"")
	if clock.get("paused",true):return "效果结算 · 暂停计时"
	return "轮到你响应" if clock.get("kind","")=="response" and clock.active[0] else ("等待对手响应" if clock.get("kind","")=="response" else ("你的回合" if m.game.current==0 else "对手的回合"))
func submit(a: Dictionary):
	if submitting or reconnecting or not in_room or socket==null or socket.get_ready_state()!=WebSocketPeer.STATE_OPEN:return
	submitting=true;submitted_revision=revision;preview_wait={};m._online_wait();send({"op":"action","id":a.get("_net","")})
func request_preview(a: Dictionary):
	preview_wait=a.duplicate(true)
	var actual=a.get("delegate_command",a)
	send({"op":"preview","id":actual.get("_net",""),"key":ViewProjection.preview_key(a)})
func rematch_request():send({"op":"rematch"});m._toast("已请求再来一局，等待对手确认。")
func ask_leave():
	var p=panel("离开房间？")
	m._paragraph("对局开始后离开将视为认输。",p,Rect2(28,120,p.size.x-56,80),25)
	m._button("继续对局",func():m._clear(m.overlay);m._refresh() if started else render_lobby(),p,true).position=Vector2(28,p.size.y-85)
	m._button("离开房间",leave,p).position=Vector2(p.size.x-190,p.size.y-85)
func leave():
	intentional=true;send({"op":"leave"});in_room=false;started=false;screen=false;reconnecting=false;connecting=false;submitting=false;epoch+=1;token="";code="";clock={};clear_session()
	if socket!=null:socket.close();socket=null
	m._menu()
func save_session():
	if "--test-defaults" in OS.get_cmdline_user_args() and storage=="user://online-session.cfg":return
	var file=ConfigFile.new();file.set_value("session","code",code);file.set_value("session","token",token);file.set_value("session","url",url);file.save(storage)
func load_session() -> Dictionary:
	if "--test-defaults" in OS.get_cmdline_user_args() and storage=="user://online-session.cfg":return {}
	var file=ConfigFile.new()
	if file.load(storage)!=OK or file.get_value("session","url","")!=url:return {}
	return {"code":file.get_value("session","code",""),"token":file.get_value("session","token","")}
func clear_session():
	if "--test-defaults" in OS.get_cmdline_user_args() and storage=="user://online-session.cfg":return
	if FileAccess.file_exists(storage):DirAccess.remove_absolute(storage)
func _exit_tree():
	intentional=true
	if socket!=null:socket.close()
