class_name UpdateWindow
extends Control
var host: WeakRef
var client: UpdateClient
var saved_modal=false
var panel: Panel
var caption: Label
var body: Label
var meter: ProgressBar
var amount: Label
var check_button: Button
var download_button: Button
var apply_button: Button
var cancel_button: Button
var full_button: Button
var auto_button: CheckButton
var m:
	get:return host.get_ref()

func _init(main,value: UpdateClient) -> void:
	host=weakref(main);client=value;saved_modal=main.modal_open
	main.modal_open=true;main.ai.cancel_all()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name="UpdateWindow";mouse_filter=Control.MOUSE_FILTER_STOP

func _ready() -> void:
	m._dim(self,0.93)
	panel=m._panel(self,Rect2(Vector2.ZERO,Vector2(700,570)))
	panel.set_anchors_preset(Control.PRESET_CENTER);panel.offset_left=-350;panel.offset_right=350;panel.offset_top=-285;panel.offset_bottom=285
	m._label("游戏更新",panel,32,m.GOLD).position=Vector2(28,22)
	caption=m._paragraph("",panel,Rect2(28,85,644,65),23,m.TEAL)
	var col=m._scroll_column(panel,Rect2(28,155,644,165));body=m._wrapped("",col,20)
	meter=ProgressBar.new();meter.name="DownloadProgress";meter.position=Vector2(28,333);meter.size=Vector2(644,24);panel.add_child(meter)
	var background=StyleBoxFlat.new();background.bg_color=Color("142c2e");background.border_color=m.GOLD;background.set_border_width_all(1);background.set_corner_radius_all(4);meter.add_theme_stylebox_override("background",background)
	var fill=StyleBoxFlat.new();fill.bg_color=Color("318e83");fill.set_corner_radius_all(4);meter.add_theme_stylebox_override("fill",fill)
	amount=m._label("",panel,18);amount.position=Vector2(28,365);amount.size=Vector2(644,32)
	auto_button=CheckButton.new();auto_button.text=GameLocale.text("启动时自动检查");auto_button.button_pressed=m.auto_update_check;auto_button.position=Vector2(28,410);panel.add_child(auto_button)
	auto_button.toggled.connect(func(value):m.auto_update_check=value;client.auto_check=value;m._save_settings())
	check_button=m._button("检查更新",client.check_updates,panel);check_button.position=Vector2(28,480);check_button.size=Vector2(205,54)
	download_button=m._button("下载更新",client.download_update,panel,true);download_button.position=Vector2(250,480);download_button.size=Vector2(200,54)
	apply_button=m._button("应用更新",func():
		if m.game==null or m.game.phase=="over":client.apply_update(),panel,true);apply_button.position=Vector2(250,480);apply_button.size=Vector2(200,54)
	full_button=m._button("下载完整包",func():OS.shell_open(client.available.full.url),panel,true);full_button.position=Vector2(250,480);full_button.size=Vector2(200,54)
	cancel_button=m._button("取消下载",client.cancel,panel);cancel_button.position=Vector2(250,480);cancel_button.size=Vector2(200,54)
	var close_button=m._button("返回",close,panel);close_button.position=Vector2(530,480);close_button.size=Vector2(142,54)
	client.changed.connect(render);render()

func render() -> void:
	if not is_instance_valid(caption):return
	var state=client.status
	var texts={"idle":"随时检查，离线也能继续游戏。","checking":"正在检查更新…","latest":"已是最新版本。","offline":"连接失败，可重试或继续离线游戏。","invalid":"更新校验失败，保留当前版本。","storage":"无法保存更新，请检查磁盘空间。","available":"发现新版本","full":"发现新版本，请下载完整包。","downloading":"正在下载更新…","ready":"下载完成，返回菜单后即可应用。","rollback":"更新未能正常启动，已保留可用版本。"}
	caption.text=GameLocale.text(texts.get(state,texts.idle))
	var current=client.current().get("version","?")
	body.text=GameLocale.text("当前版本：")+current
	if not client.available.is_empty():
		body.text+="\n"+GameLocale.text("新版本：")+client.available.version
		var notes=client.available.get("notes",{})
		body.text+="\n\n"+str(notes.get("en" if GameLocale.english() else "zh",""))
	if client.local_mode:body.text+="\n\n"+GameLocale.text("Godot开发模式：可检查版本，更新源码后按F5运行。")
	elif state=="ready":body.text+="\n\n"+GameLocale.text("应用时游戏会自动重新打开，无需手动重启。")
	meter.visible=state in ["downloading","ready"]
	var total=int(client.available.get("patch",{}).get("bytes",0))
	meter.value=100.0*client.downloaded_bytes/maxi(1,total)
	amount.text=String.humanize_size(client.downloaded_bytes)+" / "+String.humanize_size(total) if meter.visible else ""
	if state=="available":amount.text=GameLocale.text("下载大小：")+String.humanize_size(total)
	check_button.disabled=client.request!=null or state=="ready"
	download_button.visible=state=="available" and not client.local_mode
	apply_button.visible=state=="ready" and not client.local_mode
	apply_button.disabled=m.game!=null and m.game.phase!="over"
	full_button.visible=state=="full" and client.available.has("full")
	cancel_button.visible=state in ["checking","downloading"]
	cancel_button.text=GameLocale.text("取消检查" if state=="checking" else "取消下载")

func close() -> void:
	m.update_window=null;m.modal_open=saved_modal
	get_parent().remove_child(self);queue_free();m._schedule_ai()
