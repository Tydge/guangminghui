extends Control

signal presentation_finished(completed: bool)
const OnlineSession=preload("res://scripts/online/session.gd")
const RemoteState=preload("res://scripts/online/remote_state.gd")
const OnlineProjection=preload("res://scripts/online/projection.gd")
const AttackPresentation=preload("res://scripts/attack_presentation.gd")
var online
var combat

const GOLD=Color("d8ba77")
const CREAM=Color("e8ddbf")
const TEAL=Color("71d3c0")
var game: GameState
var ai=AiAgent.new()
var board: BoardView
var hud: Control
var hand_layer: Control
var inspector: Control
var overlay: Control
var large_layer: Control
var hover_layer: Control
var detail_layer: Control
var inspection_was_paused=false
var interactions: GameInteractions
var window_access: WindowAccess
var notification: Label
var selected=""
var hand_tab="group"
var action_candidates: Array=[]
var target_key="target"
var action_hint=""
var busy=false
var thinking=false
var compact=false
var preferred_reduced_motion=false
var reduced_motion: bool:
	get:return preferred_reduced_motion and not _online_active()
	set(value):preferred_reduced_motion=value
var sound_volume=0.6
var ai_difficulty="normal"
var faction_page=0
var font: Font
var sounds: Dictionary={}
var audio_pool: Array=[]
var modal_open=false
var collection_filter="faction"
var snapshot_mode=""
var match_id=0
var forced_pending=false
var preview_action: Dictionary={}
var presentation_layer: Control
var presentation_tween: Tween
var presenting=false
var panel_dragging=false
var floating_positions: Dictionary={}
# Regression harnesses can accelerate time; the user setting keeps the reading pause.
var presentation_time_scale=1.0
var settings_path="user://settings.cfg"
var updates: UpdateClient
var update_window: UpdateWindow
var auto_update_check=true

func _set_busy(value: bool) -> void:
	busy=value
	if window_access!=null:
		if value:window_access.begin_effect()
		else:window_access.end_effect()
	board.interaction_enabled=not value
	if value:
		board.cancel_card_gestures();board.drag=false;board.fingers.clear();board.touch_distance=0
	presentation_layer.visible=value

func _board_input_blocked(point: Vector2) -> bool:
	if busy:return true
	for layer in [overlay,large_layer,detail_layer]:
		for child in layer.get_children():
			if child is Control and child.is_visible_in_tree() and child.mouse_filter!=Control.MOUSE_FILTER_IGNORE and child.get_global_rect().has_point(point):return true
	return false

func _drag_title(p: Panel,text: String,key: String) -> void:
	p.name="BattleWindow" if key=="battle" else "AttackPreview"
	var handle=PanelDragHandle.new();handle.name="TitleDragHandle";handle.panel=p;handle.position=Vector2(8,6);handle.size=Vector2(p.size.x-16,52);p.add_child(handle)
	var title=_label(text,handle,25,GOLD);title.position=Vector2(18,10);title.size=Vector2(handle.size.x-125,38);title.clip_text=true
	var grip=_label("⠿ 拖动",handle,17,Color("a4ac94"));grip.position=Vector2(handle.size.x-98,15)
	if floating_positions.has(key):p.position=handle.constrain(floating_positions[key])
	handle.moved.connect(func(at):floating_positions[key]=at)
	handle.drag_started.connect(func():panel_dragging=true;board.cancel_card_gestures();board.drag=false;board.fingers.clear();board.touch_distance=0;_clear(hover_layer))
	handle.drag_finished.connect(func():panel_dragging=false;_schedule_ai())

func _ready() -> void:
	CardDB.load_all()
	interactions=GameInteractions.new(self)
	add_child(interactions)
	window_access=WindowAccess.new(self);add_child(window_access)
	font=CardDB.readable_font()
	var t=Theme.new();t.default_font=font;t.default_font_size=20;theme=t
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):snapshot_mode=arg.get_slice("=",1)
	if snapshot_mode!="":settings_path="user://export-snapshot-%d.cfg"%OS.get_process_id()
	compact=OS.has_feature("mobile");_load_settings();_build_shell();resized.connect(_resize)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot-language="):GameLocale.set_language(arg.trim_prefix("--snapshot-language="))
	updates=UpdateClient.new();updates.auto_check=auto_update_check;add_child(updates);updates.changed.connect(_sync_update_badge)
	online=OnlineSession.new(self);add_child(online)
	if snapshot_mode!="":_start_game(4318);_snapshot_setup()
	else:_menu()
	get_node("/root/UpdateBootstrap").confirm_startup()
	updates.call_deferred("startup_check")

func _style(color: Color=Color("142e32"),border: Color=Color("846e47"),width: int=1) -> StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=color;s.border_color=border;s.set_border_width_all(width);s.set_corner_radius_all(8);s.content_margin_left=16;s.content_margin_right=16;s.content_margin_top=9;s.content_margin_bottom=9;return s

func _button(text: String,callback: Callable,parent: Node,accent: bool=false) -> Button:
	var b=Button.new();b.text=GameLocale.text(text);b.custom_minimum_size=Vector2(104,46);b.add_theme_font_size_override("font_size",18 if GameLocale.english() else 20);b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;b.add_theme_color_override("font_color",CREAM);b.add_theme_color_override("font_hover_color",Color.WHITE);b.add_theme_stylebox_override("normal",_style(Color("254b47") if accent else Color("142c2e"),GOLD if accent else Color("6e7056")));b.add_theme_stylebox_override("hover",_style(Color("315953"),GOLD));b.add_theme_stylebox_override("pressed",_style(Color("416c60"),TEAL,2));b.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),TEAL,2));b.pressed.connect(func():
		if not busy and not window_access.transitioning:_sound("click");callback.call());parent.add_child(b);return b

func _label(text: String,parent: Node,fs: int=20,color: Color=CREAM) -> Label:
	var l=Label.new();l.text=GameLocale.text(text);l.add_theme_font_size_override("font_size",fs);l.add_theme_color_override("font_color",color);l.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(l);return l

func _paragraph(text: String,parent: Node,rect: Rect2,fs: int=22,color: Color=CREAM) -> Label:
	var l=Label.new();l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.add_theme_font_size_override("font_size",fs);l.add_theme_color_override("font_color",color);l.mouse_filter=Control.MOUSE_FILTER_IGNORE;l.text=GameLocale.text(text);parent.add_child(l);l.position=rect.position;l.size=rect.size
	if GameLocale.english():
		while fs>14 and font.get_multiline_string_size(l.text,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x,fs).y>rect.size.y:fs-=1
		l.add_theme_font_size_override("font_size",fs)
		l.clip_text=true;l.max_lines_visible=maxi(1,int(rect.size.y/font.get_height(fs)));l.size=rect.size
	return l

func _wrapped(text: String,parent: Node,fs: int=21,color: Color=CREAM) -> Label:
	var l=Label.new();l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.size_flags_horizontal=Control.SIZE_EXPAND_FILL;l.add_theme_font_size_override("font_size",fs);l.add_theme_color_override("font_color",color);l.mouse_filter=Control.MOUSE_FILTER_IGNORE;l.text=GameLocale.text(text);parent.add_child(l);return l

func _scroll_column(parent: Node,rect: Rect2) -> VBoxContainer:
	var scroll=ScrollContainer.new();scroll.position=rect.position;scroll.size=rect.size;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;parent.add_child(scroll)
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",14);scroll.add_child(col);return col

func _panel(parent: Node,rect: Rect2) -> Panel:
	var p=Panel.new();p.add_theme_stylebox_override("panel",_style(Color("10282bf8")));parent.add_child(p);p.position=rect.position;p.size=rect.size
	if ResourceLoader.exists("res://assets/ui/panel.webp"):
		var art=NinePatchRect.new();art.texture=load("res://assets/ui/panel.webp");art.patch_margin_left=85;art.patch_margin_right=85;art.patch_margin_top=85;art.patch_margin_bottom=85;art.scale=Vector2.ONE*0.26;art.size=rect.size/0.26;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;p.add_child(art)
	return p

func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()

func _build_shell() -> void:
	var background=TextureRect.new();background.texture=load("res://assets/ui/table.webp");background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	board=BoardView.new();board.input_blocked_at=_board_input_blocked;add_child(board);board.card_selected.connect(_select_card);board.card_inspected.connect(_inspect);board.card_hovered.connect(_hover)
	combat=AttackPresentation.new(self);board.add_child(combat)
	hud=Control.new();hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(hud)
	hand_layer=Control.new();hand_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(hand_layer)
	inspector=Control.new();inspector.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(inspector)
	overlay=Control.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(overlay)
	hover_layer=Control.new();hover_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;hover_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(hover_layer)
	large_layer=Control.new();large_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;large_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(large_layer)
	detail_layer=Control.new();detail_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;detail_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(detail_layer)
	presentation_layer=Control.new();presentation_layer.name="CardPresentation";presentation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);presentation_layer.mouse_filter=Control.MOUSE_FILTER_STOP;presentation_layer.hide();add_child(presentation_layer)
	notification=_label("",self,24,GOLD);notification.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for _i in range(6):
		var player=AudioStreamPlayer.new();add_child(player);audio_pool.append(player)
	var names={"click":"click_001","select":"select_002","card":"drop_001","open":"open_001","close":"close_001","success":"confirmation_002","fail":"error_001","turn":"bong_001","dice":"scroll_001","counter":"glitch_001"}
	for key in names:sounds[key]=load("res://assets/audio/%s.ogg"%names[key]) if ResourceLoader.exists("res://assets/audio/%s.ogg"%names[key]) else null
	_resize()

func _process(_delta: float) -> void:
	CardDB.collect_art()

func _resize() -> void:
	if board==null:return
	board.position=Vector2(26,158);board.size=Vector2(size.x-(54 if compact else 374),size.y-411)
	notification.position=Vector2(0,113);notification.size=Vector2(size.x,38)
	if game!=null:
		_refresh(not busy)
		if not preview_action.is_empty() and not busy and not window_access.browsing and not window_access.transitioning:_review_action(preview_action)
	if presenting:
		for panel_name in ["RevealBody","DiceResult"]:
			var body=presentation_layer.get_node_or_null(panel_name)
			if body!=null:body.position=(size-body.size)/2

func _sound(key: String) -> void:
	if sound_volume<=0 or sounds.get(key)==null:return
	for p in audio_pool:
		if not p.playing:p.stream=sounds[key];p.volume_db=linear_to_db(sound_volume*0.6);p.pitch_scale=randf_range(0.97,1.03);p.play();return

func _dim(layer: Control,opacity: float=0.85) -> void:
	var d=ColorRect.new();d.color=Color(0.015,0.04,0.045,opacity);d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layer.add_child(d)

func _menu() -> void:
	if online!=null and online.in_room:online.ask_leave();return
	ai.cancel_all()
	combat.reset()
	match_id+=1;_finish_presentation(false);window_access.reset();interactions.reset();_set_busy(false);board.reset_motion();thinking=false;forced_pending=false;panel_dragging=false;floating_positions.clear();notification.text="";preview_action={};_clear(detail_layer);_clear(hover_layer)
	_clear(overlay);_clear(hud);_clear(hand_layer);_clear(inspector);_clear(large_layer);game=null;board.visible=false;modal_open=true;_dim(overlay)
	var content=Control.new();content.name="MenuContent";content.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.add_child(content);content.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var heading=_label("ILLUMINATI",content,82,GOLD);heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;heading.position=Vector2(-400,-300);heading.size.x=800
	var sub=_label("光 明 会    /    暗 流 对 决",content,29,CREAM);sub.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;sub.position=Vector2(-400,-190);sub.size.x=800
	var art=TextureRect.new();art.texture=CardDB.art("I01");art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.position=Vector2(-150,-150);art.size=Vector2(300,220);content.add_child(art)
	var levels=HBoxContainer.new();levels.name="DifficultyOptions";levels.position=Vector2(-213,88);levels.add_theme_constant_override("separation",10);content.add_child(levels)
	var difficulty_group=ButtonGroup.new()
	for level in ["easy","normal","hard"]:
		var b=_button({"easy":"简单","normal":"普通","hard":"困难"}[level],func():_choose_menu_difficulty(level),levels);b.custom_minimum_size=Vector2(135,44);b.set_meta("difficulty",level);b.toggle_mode=true;b.button_group=difficulty_group;b.button_pressed=ai_difficulty==level;b.add_theme_stylebox_override("pressed",_style(Color("254b47"),GOLD,2))
	var start=_button("开始对局",func():_start_game(),content,true);start.position=Vector2(-225,145);start.size=Vector2(215,62)
	var friends=_button("好友对战",func():online.enter(),content,true);friends.name="OnlinePlay";friends.position=Vector2(10,145);friends.size=Vector2(215,62)
	var catalog=_button("卡牌图鉴",_catalog,content);catalog.position=Vector2(-150,221);catalog.size=Vector2(145,48)
	var settings=_button("设置",_settings,content);settings.position=Vector2(5,221);settings.size=Vector2(145,48)
	var version_button=_button("检查更新",_updates,content);version_button.name="MenuUpdate";version_button.position=Vector2(-150,284);version_button.size=Vector2(300,40);version_button.add_theme_font_size_override("font_size",17);_sync_update_badge()
	var foot=_label("1V1 · 共享牌堆 · 离线 AI",overlay,17,Color("9aa99a"));foot.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);foot.offset_top=-65;foot.offset_bottom=-25

func _choose_menu_difficulty(level: String) -> void:
	ai_difficulty=level;ai.difficulty=level
	var options=overlay.find_child("DifficultyOptions",true,false)
	if options!=null:
		for b in options.get_children():b.set_pressed_no_signal(b.get_meta("difficulty")==level)
	_save_settings()

func _start_game(seed_value: int=0) -> void:
	if _online_active():online.rematch_request();return
	ai.cancel_all()
	combat.reset()
	faction_page=0
	match_id+=1;_finish_presentation(false);window_access.reset();interactions.reset();_set_busy(false);board.reset_motion();thinking=false;forced_pending=false;panel_dragging=false;floating_positions.clear();preview_action={};_clear(large_layer);_clear(detail_layer);_clear(hover_layer)
	_clear_board()
	ai.difficulty=ai_difficulty;game=GameState.new(seed_value);selected="";action_candidates.clear();modal_open=false;board.visible=true;board.initialized=false;_refresh();_sound("open")

func _refresh(with_modal: bool=true) -> void:
	if game==null:return
	_clear(hud);_clear(hand_layer);_clear(inspector)
	board.game=game;board.selected_id=selected;board.legal_ids=[] if window_access.browsing else (interactions.picker.values(target_key) if interactions.picker.active and not action_candidates.is_empty() else action_candidates.map(func(a):return a.get(target_key,"")));board.reduced_motion=reduced_motion;board.motion_time_scale=presentation_time_scale
	if not game.nodes.is_empty():board.sync(game)
	combat.sync_state(game);combat.move_to_front()
	_draw_hud();_draw_hand();_draw_inspector()
	if with_modal and not window_access.browsing and not window_access.transitioning:_phase_overlay()

func _draw_hud() -> void:
	var w=size.x;var h=size.y
	var strip=ColorRect.new();strip.color=Color("071d21db");strip.position=Vector2(20,12);strip.size=Vector2(w-40,85);strip.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(strip)
	_label("ILLUMINATI",hud,30,GOLD).position=Vector2(35,20)
	var status={"setup_faction":"选择光明会","setup_group":"选择初始手下","setup_resource":"选择初始资源"}.get(game.phase,"你的回合" if game.current==0 else "AI 的回合")
	if game.phase=="battle":status="战斗响应"
	if busy:status="效果结算"
	elif game.phase=="over":status="对局结束"
	if _online_active():status=online.status_text() if game.phase!="over" else "对局结束"
	var status_label=_label(status,hud,22 if _online_active() else 25,TEAL if game.current==0 else Color("df9c8d"));status_label.name="OnlineStatus";status_label.position=Vector2(w/2-130,20);status_label.size.x=330;status_label.clip_text=true
	if not game.nodes.is_empty():
		_label("你 · "+CardDB.name_of(game.factions[0])+"   "+GameLocale.progress(game.goal(0).text),hud,18).position=Vector2(35,70)
		_label(_opponent_name()+" · "+CardDB.name_of(game.factions[1])+"   "+GameLocale.progress(game.goal(1).text),hud,18,Color("d69b8e")).position=Vector2(w/2+20,70)
	var menu=_button("☰",_settings,hud);menu.position=Vector2(w-92,16);menu.custom_minimum_size.x=54;menu.size=Vector2(54,46);menu.disabled=window_access.browsing
	var camera=HBoxContainer.new();camera.position=Vector2(35,105);camera.add_theme_constant_override("separation",7);hud.add_child(camera)
	_button("己方",func():board.focus(0),camera);_button("对手",func():board.focus(1),camera);_button("全局",func():board.fit_all(),camera)
	var minus=_button("−",func():board.zoom_at(0.85,board.size/2),camera);minus.custom_minimum_size.x=48
	var plus=_button("＋",func():board.zoom_at(1.18,board.size/2),camera);plus.custom_minimum_size.x=48
	for kind in ["group","resource","plot"]:
		var piles=_button({"group":"团体 ","resource":"资源 ","plot":"阴谋 "}[kind]+str(game.decks[kind].size()),_piles,hud);piles.position=Vector2(w-465+["group","resource","plot"].find(kind)*140,105);piles.size=Vector2(154 if GameLocale.english() else 132,46);piles.custom_minimum_size.x=125;piles.disabled=window_access.browsing
		if GameLocale.english():piles.position.x=w-515+["group","resource","plot"].find(kind)*162;piles.add_theme_font_size_override("font_size",16)
		var back="res://assets/ui/%s_back.webp"%("group" if kind=="resource" else kind)
		if ResourceLoader.exists(back):piles.icon=load(back);piles.expand_icon=true;piles.add_theme_constant_override("icon_max_width",22)
	if game.world!="":
		var order=_button("秩序 · "+CardDB.name_of(game.world).replace("新世界秩序：",""),func():_inspect(game.world),hud);order.position=Vector2(515,160)
	var eventtext=("查看战场 · 对局结束" if game.phase=="over" else ("查看战场 · 计时继续" if _online_active() else "查看战场 · 对局暂停")) if window_access.browsing else ("效果结算" if busy else (game.logs.back() if not game.logs.is_empty() else ""))
	var log_width=w-(385 if not compact else 70)-(155 if not game.last_battle.is_empty() else 0)
	var log_button=_button("◈  "+eventtext,_journal,hud);log_button.add_theme_font_size_override("font_size",16);log_button.custom_minimum_size.y=42;log_button.position=Vector2(35,h-249);log_button.size=Vector2(log_width,42);log_button.clip_text=true;log_button.disabled=window_access.browsing
	if not game.last_battle.is_empty():
		var history_button=_button("最近战斗",_battle_history,hud);history_button.add_theme_font_size_override("font_size",16);history_button.custom_minimum_size.y=42;history_button.position=Vector2(45+log_width,h-249);history_button.size=Vector2(145,42);history_button.disabled=window_access.browsing
	var tabs_width=8.0
	for caption in _hand_tab_labels():tabs_width+=maxf(104,font.get_string_size(GameLocale.text(caption),HORIZONTAL_ALIGNMENT_LEFT,-1,18 if GameLocale.english() else 20).x+32)
	var actions_x=35+tabs_width+18
	var action_scroll=ScrollContainer.new();action_scroll.name="ActionToolbar";action_scroll.position=Vector2(actions_x,h-205);action_scroll.size=Vector2(w-(350 if not compact else 35)-actions_x,54);action_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;hud.add_child(action_scroll)
	var actions=HBoxContainer.new();actions.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;actions.add_theme_constant_override("separation",8);action_scroll.add_child(actions)
	if window_access.browsing:
		_button("返回结果" if game.phase=="over" else "返回操作窗口",window_access.resume,actions,true)
	elif not action_candidates.is_empty():
		var hint=_label(action_hint,actions,19,TEAL);hint.clip_text=true;hint.custom_minimum_size.x=clampf(action_scroll.size.x-360,180,380);hint.tooltip_text=GameLocale.text(action_hint)
		_button("上一步",interactions.back,actions) if interactions.picker.active else null
		_button("取消",func():interactions.cancel(),actions);_button("列出目标",func():interactions.show_targets(action_candidates),actions)
	elif game.phase=="main" and game.current==0 and not busy:_context_actions(actions)
	else:_label(("等待对手操作…" if _online_active() else "AI 正在行动…") if thinking or _online_active() else "",actions,20,GOLD)
	if selected!="":_button("查看大卡",func():_inspect(selected),actions)
	if game.nodes.has(selected) and not game.children(selected).is_empty():_button("展开" if board.collapsed.get(selected,false) else "收起",func():board.collapsed[selected]=not board.collapsed.get(selected,false);_refresh(false),actions)
	if game.phase=="main" and game.current==0 and not window_access.browsing:
		var pending=game.failed_recruits.filter(func(id):return id in game.hands[0].group).size()
		var end=_button("结束回合 · 招募弃%d"%pending if pending>0 else "结束回合  →",func():_perform_type("end"),hud,true);end.position=Vector2(w-330,h-80);end.size=Vector2(285,56)
	_label("对手 · 团体%d / 阴谋%d / 资源%d"%[game.hands[1].group.size(),game.hands[1].plot.size(),game.hands[1].resource.size()],hud,16,Color("abafa0")).position=Vector2(w-342,h-128)

func _context_actions(parent: Control) -> void:
	var legal=game.legal_actions(0)
	var draws=legal.filter(func(a):return a.type=="research")
	var draw_button=_button("抽牌",_draw_deck_picker,parent,true)
	draw_button.disabled=draws.is_empty();draw_button.tooltip_text=GameLocale.text("花主牌1行动，从团体、资源或阴谋堆抽1张。")
	if selected=="":_label("选择手牌或场上团体",parent,20,Color("a5b6a6"));return
	if selected in game.hands[0].resource:
		var deploys=legal.filter(func(a):return a.type=="deploy" and a.id==selected)
		if not deploys.is_empty():_button("部署资源",func():_action_list(deploys),parent,true)
	elif game.nodes.has(selected) and game.card(selected).kind=="resource":
		var uses=legal.filter(func(a):return a.type=="resource" and a.src==selected)
		if not uses.is_empty():_button("使用资源",func():_action_list(uses),parent,true)
	elif selected in game.hands[0].group:
		var autos=legal.filter(func(a):return a.type=="auto" and a.id==selected)
		if not autos.is_empty():
			var takeover=_button("自动接管",func():_target(autos,"parent","选择接管位置"),parent,true)
			takeover.tooltip_text=GameLocale.text("免掷骰进场。新团体当回合无行动标记，且不能恢复。")
		var recruits=legal.filter(func(a):return a.type=="attack" and a.target==selected)
		if not recruits.is_empty():_button("攻击招募",func():_target(recruits,"src","选择带头团体"),parent)
	elif selected in game.hands[0].plot:
		var plots=legal.filter(func(a):return a.type=="plot" and a.id==selected)
		if not plots.is_empty():_button("宣告胜利" if game.covenant.is_goal(selected) else "打出阴谋",func():_action_list(plots),parent,true)
		elif game.covenant.is_goal(selected):
			var progress=game.covenant.progress(0,selected)
			var note="首轮结束后可宣告" if progress.met and mini(game.turns[0],game.turns[1])<1 else ("己方主要阶段可宣告" if progress.met else progress.text)
			_label(note,parent,18,Color("b8ae93"))
		else:_label("等待卡牌适用时机",parent,18,Color("b8ae93"))
	elif game.owner(selected)==0:
		for mode in ["control","destroy"]:
			var attacks=legal.filter(func(a):return a.type=="attack" and a.src==selected and a.mode==mode)
			if not attacks.is_empty():_button("控制" if mode=="control" else "摧毁",func():_target(attacks,"target","选择控制目标" if mode=="control" else "选择摧毁目标"),parent,mode=="control")
		var abilities=legal.filter(func(a):return a.type in ["ability","resource"] and a.src==selected)
		var lifts=legal.filter(func(a):return a.type=="lift" and a.src==selected)
		if not lifts.is_empty():_button("解除监管",func():_do_action(0,lifts[0]),parent,true)
		if not abilities.is_empty():_button("能力",func():_action_list(abilities),parent)
		var rebuilds=legal.filter(func(a):return a.type=="rebuild" and a.target==selected)
		if not rebuilds.is_empty():_button("重建",func():_action_list(rebuilds),parent,true)
		var moves=legal.filter(func(a):return a.type=="move" and a.src==selected)
		if not moves.is_empty():_button("重组",func():_target(moves,"parent","选择新的上级"),parent)
	elif game.nodes.has(selected):
		for mode in ["control","destroy"]:
			var attacks=legal.filter(func(a):return a.type=="attack" and a.target==selected and a.mode==mode)
			if not attacks.is_empty():_button("控制" if mode=="control" else "摧毁",func():_target(attacks,"src","选择带头团体 · "+game.title(selected)),parent,mode=="control")
		if game.is_root(selected):_label("对手主牌",parent,18,Color("c9988b"))
		elif not game.can_enemy(0):_label("对手仍受开局保护",parent,18,Color("c9988b"))

func _hand_tab_labels() -> Array:
	return ["团体  %d"%game.hands[0].group.size(),"阴谋  %d / %d"%[game.hands[0].plot.size(),game.hand_limit(0)],"资源 %d/%d"%[game.hands[0].resource.size(),game.resource_hand_limit(0)]]

func _draw_hand() -> void:
	var h=size.y
	var labels=_hand_tab_labels()
	var tabs=HBoxContainer.new();tabs.position=Vector2(35,h-205);tabs.add_theme_constant_override("separation",8);hand_layer.add_child(tabs)
	_button(labels[0],func():hand_tab="group";_refresh(false),tabs,hand_tab=="group")
	_button(labels[1],func():hand_tab="plot";_refresh(false),tabs,hand_tab=="plot")
	_button(labels[2],func():hand_tab="resource";_refresh(false),tabs,hand_tab=="resource")
	var scroll=ScrollContainer.new();scroll.position=Vector2(35,h-151);scroll.size=Vector2(size.x-(385 if not compact else 410),148);scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;hand_layer.add_child(scroll)
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",10);scroll.add_child(row)
	for id in game.hands[0][hand_tab]:
		var v=CardView.new();v.configure(id,game);v.custom_minimum_size=Vector2(94,142);v.chosen=id==selected;v.legal=id in interactions.picker.values(target_key) if interactions.picker.active and not action_candidates.is_empty() else action_candidates.any(func(a):return a.get(target_key,"")==id);row.add_child(v);_connect_card(v)
	if game.hands[0][hand_tab].is_empty():_label("暂无手牌",row,18,Color("9baa9d"))

func _connect_card(v: CardView) -> void:
	v.selected.connect(_select_card);v.inspected.connect(_inspect);v.hovered.connect(_hover)

func _draw_inspector() -> void:
	if compact:return
	var id=selected if selected!="" else (game.root(0) if game.nodes.has(game.root(0)) else "I01")
	var v=CardView.new();v.configure(id,game);v.position=Vector2(size.x-327,165);v.size=Vector2(292,minf(520,size.y-380));inspector.add_child(v);v.inspected.connect(_inspect);v.selected.connect(_inspect)

func _select_card(id: String) -> void:
	if busy or window_access.transitioning:return
	_sound("select");_clear(hover_layer)
	if window_access.browsing:
		selected=id;_refresh(false);return
	if interactions.picker.active and not action_candidates.is_empty():
		if id in interactions.picker.values(target_key):interactions.pick(target_key,id)
		return
	if not action_candidates.is_empty():
		var matching=action_candidates.filter(func(a):return a.get(target_key,"")==id)
		if matching.size()==1:_review_action(matching[0]);return
		if matching.size()>1:_action_list(matching);return
	selected=id
	if id in game.hands[0].group:hand_tab="group"
	if id in game.hands[0].plot:hand_tab="plot"
	if id in game.hands[0].resource:hand_tab="resource"
	_refresh(false)

func _target(actions: Array,key: String,hint: String) -> void:
	if window_access.browsing:return
	action_candidates=actions;target_key=key;action_hint=hint;board.reveal(interactions.picker.values(key) if interactions.picker.active else actions.map(func(a):return a.get(key,"")));_refresh(false)
	if compact:board.focus(1 if actions.any(func(a):return game.owner(a.get(key,""))==1) else 0)

func _action_list(actions: Array) -> void:
	if window_access.browsing:return
	interactions.begin(actions)

func _dispatch_options(options: Array) -> void:
	if options.size()>1:_action_list(options)
	elif not options.is_empty():_do_action(0,options[0])

func _review_action(a: Dictionary,all_plots: bool=false) -> void:
	if window_access.browsing:return
	if a.type=="plot" and a.id in GameState.WaveRules.DISASTERS:_review_disaster(a);return
	if a.type=="ability" and a.src=="G096":
		_review_action({"type":"attack","src":a.leader,"target":a.target,"mode":"control","use_plan":a.get("use_plan",false),"delegate":"G096","delegate_command":a},all_plots);return
	if a.type!="attack":_do_action(0,a);return
	if _online_active() and not game.preview_cache.has(OnlineProjection.preview_key(a)):
		preview_action=a.duplicate(true);online.request_preview(a);_toast("正在准备攻击预览…");return
	preview_action=a.duplicate(true)
	_clear(large_layer);_clear(hover_layer);_dim(large_layer,0.12)
	var extent=Vector2(minf(1120,size.x-100),minf(670,size.y-130))
	var p=_panel(large_layer,Rect2((size-extent)/2,extent))
	_drag_title(p,"控制攻击" if a.mode=="control" else "摧毁攻击","preview")
	window_access.offer(p,Vector2(-1,62))
	var heading=_label(game.title(a.src)+"  →  "+game.title(a.target),p,24);heading.position=Vector2(28,68);heading.size.x=extent.x-230;heading.clip_text=true;heading.tooltip_text=GameLocale.text(heading.text)
	var v=game.attack_preview(a.src,a.target,a.mode,a)
	if a.get("use_plan",false):_paragraph("采用预案 · %d＋%d"%game.wave.plans[0],p,Rect2(28,222,380,35),20,TEAL)
	var left_w=extent.x*0.39;var right_x=left_w+40
	_label("基础强度  %d"%v.strength,p,34,TEAL).position=Vector2(28,143)
	_label("成功率  %.1f%%"%(v.chance*100),p,27,CREAM).position=Vector2(28,195)
	_paragraph("力量 %d   阵营 %+d   能力 %+d\n\n防御 %d   忠诚 %d   位置 %d\n被动防御 %d"%[v.power,v.alignment,v.ability,v.base,v.loyalty,v.position,v.defense],p,Rect2(28,267,left_w-20,180),21)
	var note="墨西哥支付行动，带头者保留标记。\n" if a.has("delegate") else ""
	if v.get("no_self",false):note+="目标本次不能自卫。\n"
	if a.target=="G067" and game.wave.enabled("G067"):note+="高额账单 · 失败后随机弃1阴谋。\n"
	if a.get("solo",false):note+="孤军破袭 · 忽略位置，无进攻支援。\n"
	_paragraph(note+"尚未计入支援、资源与阴谋。\n确认后双方交替响应。",p,Rect2(28,extent.y-185,left_w-20,85),18,Color("aabbb0"))
	var options=game.attack_options(a.src,a.target,a.mode,a)
	var scroll=ScrollContainer.new();scroll.name="AttackResources";scroll.position=Vector2(right_x,125);scroll.size=Vector2(extent.x-right_x-28,extent.y-231);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;p.add_child(scroll)
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",10);scroll.add_child(col)
	_label("支援  %d个 · 合计 +%d"%[options.supports.size()+options.resources.filter(func(entry):return entry.bonus>0).size(),options.support_total],col,23,GOLD)
	var support_flow=HFlowContainer.new();support_flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL;support_flow.add_theme_constant_override("h_separation",8);support_flow.add_theme_constant_override("v_separation",8);col.add_child(support_flow)
	for entry in options.supports:
		var b=_button("%s  %s +%d"%[game.title(entry.id),entry.basis,entry.power],func():_inspect(entry.id),support_flow)
		b.add_theme_font_size_override("font_size",18);b.tooltip_text=GameLocale.text(entry.reason+"；消耗1个行动标记。点击查看卡牌。")
	if options.supports.is_empty() and options.resource_total==0:_label("暂无可用支援",col,18,Color("9aaca0"))
	if options.mobilized_supports>0:_label("联合动员可增强%d个支援"%options.mobilized_supports,col,17,TEAL)
	for entry in options.resources:
		var resource_button=_button(entry.label+("\n"+"对手支援后可用" if entry.conditional else ""),func():_inspect(entry.id),col);resource_button.name="PreviewResource_"+entry.id;resource_button.add_theme_font_size_override("font_size",18);resource_button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	var usable=options.plots.filter(func(entry):return entry.status!="不可用")
	_label("阴谋  %d张可用 · %d张需先支援"%[usable.filter(func(entry):return entry.status=="可用").size(),usable.filter(func(entry):return entry.status=="先支援").size()],col,23,GOLD)
	var plot_flow=HFlowContainer.new();plot_flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL;plot_flow.add_theme_constant_override("h_separation",8);plot_flow.add_theme_constant_override("v_separation",8);col.add_child(plot_flow)
	for entry in (options.plots if all_plots else usable):
		var suffix=" +%d"%entry.bonus if entry.status=="可用" and entry.bonus>0 else " · "+entry.status
		var b=_button(game.title(entry.id)+suffix,func():_inspect(entry.id),plot_flow,entry.status=="可用")
		b.add_theme_font_size_override("font_size",18);b.tooltip_text=GameLocale.text(entry.reason)
		if entry.status=="不可用":b.modulate=Color("95a39b")
	if usable.is_empty() and not all_plots:_label("暂无适用阴谋",col,18,Color("9aaca0"))
	var hidden=options.plots.size()-usable.size()
	if hidden>0:_button("收起不适用手牌" if all_plots else "其余 %d 张手牌"%hidden,func():_review_action(a,not all_plots),col)
	var cancel=_button("返回",func():preview_action={};_clear(large_layer),p);cancel.position=Vector2(28,extent.y-82);cancel.size=Vector2(160,56)
	var confirm=_button("发起攻击",func():preview_action={};_clear(large_layer);_do_action(0,a.get("delegate_command",a)),p,true);confirm.position=Vector2(extent.x-245,extent.y-82);confirm.size=Vector2(215,56)

func _perform_type(kind: String) -> void:
	if game==null:return
	for a in game.legal_actions(0):
		if a.type==kind:_do_action(0,a);return

func _do_action(p: int,a: Dictionary) -> void:
	if busy or window_access.browsing or window_access.transitioning or panel_dragging or game==null or a not in game.legal_actions(p):return
	if _online_active():online.submit(a);return
	var this_match=match_id
	var old_phase=game.phase
	interactions.picker.clear()
	var plan=ActionFlow.plan(game,p,a)
	action_candidates.clear();preview_action={};_clear(large_layer);_clear(hover_layer);modal_open=false
	_set_busy(true)
	if old_phase=="draw":_clear(overlay)
	for reveal in game.wave.presentation_cards(p,a):
		var shown=a.duplicate();shown.presentation_id=reveal
		if a.type=="ability" and a.src=="G149" and reveal==a.other:shown.presentation_role="公开身份模板"
		if reveal=="G139" and not plan.get("minor",{}).is_empty():shown.minor_roll=plan.minor.roll
		var actor=game.owner(reveal) if game.nodes.has(reveal) else p
		var completed=await _present_action(actor,shown)
		if not completed or game==null or this_match!=match_id:return
	if not plan.result.is_empty() and not plan.result.get("cancelled",false):
		if not await _present_result(plan.result):return
		if game==null or this_match!=match_id:return
	if not await interactions.battle_cue(plan):return
	if game==null or this_match!=match_id:return
	for target in [plan.target,plan.get("other_target","")]:
		if target=="":continue
		if not await interactions.target_cue(plan.source,target):return
		if game==null or this_match!=match_id:return
	if not plan.moves.is_empty():
		if not await interactions.moves(plan.moves,plan):return
		if game==null or this_match!=match_id:return
	# The rehearsal never mutates game or its RNG. Commit after the final landing.
	interactions.restore_sources()
	if not game.act(p,a):_set_busy(false);_refresh();_schedule_ai();return
	if a.type=="attack":floating_positions.erase("battle")
	if selected!="" and not game.nodes.has(selected) and selected not in game.hands[0].group and selected not in game.hands[0].plot and selected not in game.hands[0].resource:selected=""
	# Every action waits for board entry, exit and layout motion, including abilities
	# and turn-end effects. No new choice, automatic trigger or victory may overtake it.
	board.settlement_result=plan.result
	_refresh(false)
	await board.wait_for_settlement()
	if game==null or this_match!=match_id:return
	if a.type in ["auto","move","ability"]:_sound("card")
	if p==1 and a.type in ["support","self_defend","rescue","plot","counter"]:
		var history=game.battle.get("entries",[]) if not game.battle.is_empty() else game.last_battle.get("entries",[])
		if not history.is_empty():_toast(history.back().text)
	if old_phase=="setup_resource" and a.type=="initial_resource":_toast("先手骰点 · 你 %d + %d / AI %d + %d"%[game.initiative[0][0],game.initiative[0][1],game.initiative[1][0],game.initiative[1][1]])
	_set_busy(false)
	_refresh();_schedule_ai()
	if old_phase=="setup_resource" and a.type=="initial_resource":board.opening_view(compact)

func _present_action(player: int,a: Dictionary) -> bool:
	presenting=true
	_clear(presentation_layer)
	notification.modulate.a=0
	var id=a.get("presentation_id",a.get("id",a.get("src","")));var c=game.card(id)
	var is_plot=c.kind=="plot" and a.type in ["plot","counter"]
	var actor="你" if player==0 else _opponent_name()
	var accent=TEAL if player==0 else Color("e4ac94")
	var shade=ColorRect.new();shade.name="RevealShade";shade.color=Color(0.015,0.04,0.045,0.88);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;shade.modulate.a=0;presentation_layer.add_child(shade)
	var extent=Vector2(minf(790,size.x-100),minf(650,size.y-110))
	var body=Control.new();body.name="RevealBody";body.size=extent;body.position=(size-extent)/2;body.modulate.a=0;body.mouse_filter=Control.MOUSE_FILTER_IGNORE;presentation_layer.add_child(body)
	var card_width=extent.y*0.56
	var v=CardView.new();v.name="PresentedCard";v.configure(id,game,true);v.size=Vector2(card_width,extent.y);v.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(v)
	var x=card_width+40;var text_width=extent.x-x
	var kind=a.get("presentation_role","打出阴谋" if is_plot else "发动能力")
	if a.type=="deploy":kind="部署资源"
	if a.type=="research":kind="主牌行动 · 抽牌"
	if a.type=="resource":kind="使用资源" if c.kind=="resource" else "发动能力"
	if is_plot and game.covenant.is_goal(c.id):kind="宣告胜利"
	if a.type=="trigger":kind="效果触发"
	if a.type=="rebuild":kind="重建地点"
	if a.type=="lift":kind="解除监管"
	if a.type=="choose" and game.choice.get("kind","")=="w_draft":kind="公开选择"
	_paragraph(actor+" · "+kind,body,Rect2(x,extent.y*0.24,text_width,36),22,accent)
	_paragraph(c.name,body,Rect2(x,extent.y*0.33,text_width,128),34,GOLD)
	var rule=ColorRect.new();rule.color=Color(GOLD,0.65);rule.position=Vector2(x,extent.y*0.52);rule.size=Vector2(70,2);rule.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(rule)
	var effect_name=c.category if is_plot else c.effect.get_slice("：",0)
	if c.kind=="plot" and not is_plot:effect_name=c.name
	if is_plot:
		if game.covenant.is_goal(a.id):effect_name="目标达成 · 等待反制"
		match a.id:
			"P43":effect_name="本次忽略位置防御"
			"P44":effect_name="保护1次普通摧毁"
			"P45":effect_name="目标GP变为0"
			"P46":effect_name="获得"+a.get("tag","")+"标签"
			"P47":effect_name="回收1张战斗阴谋"
			"P48":effect_name="共产支援可用P"
			"P49":effect_name="恢复1标记 · 抽1团体"
			"P50":effect_name="本次灾难威力+%d"%a.disaster_bonus
	if a.has("presentation_role"):effect_name="采用印刷阵营 · "+" / ".join(c.align)
	if a.has("minor_roll"):effect_name="骰点 %d · 支援%s"%[a.minor_roll,"+2" if a.minor_roll<=3 else "不变"]
	if a.type=="trick":effect_name="弃1张阴谋 · 取消对手阴谋"
	if a.type=="rescue":effect_name="救援撤离"
	if a.type=="lift":effect_name="花1行动 · 解除监管"
	if a.type=="rebuild":effect_name="重建"
	if a.type=="trigger" and game.choice.get("task",{}).get("kind","")=="prepared":effect_name="防备消耗 · 防御+4"
	if a.type=="trigger" and game.choice.get("task",{}).get("kind","")=="s_guard":effect_name="保镖 · 挡下摧毁"
	if a.type=="trigger" and game.choice.get("task",{}).get("kind","")=="s_bill":effect_name="高额账单 · 对手随机弃1阴谋"
	if a.type=="trigger" and game.choice.get("task",{}).get("kind","")=="draw":effect_name=game.choice.task.get("message","抽牌收益")
	if a.type=="trigger" and game.choice.get("task",{}).get("kind","")=="battle_recharge":effect_name="战后恢复行动标记"
	if a.type=="choose" and game.choice.get("kind","")=="w_draft":effect_name="推荐流"
	if a.type in ["resource","research","deploy"]:effect_name=a.label
	if not GameLocale.english() and effect_name.length()>30:effect_name=effect_name.left(28)+"…"
	_paragraph(effect_name,body,Rect2(x,extent.y*0.58,text_width,80),25,CREAM)
	var target=a.get("target","")
	var target_text="目标 · "+game.title(target) if target!="" else ""
	if a.type=="ability" and a.src in ["G138","G168"]:target_text="弃牌 · "+game.title(target)
	var payer=a.get("payer","")
	if is_plot:
		if a.id in ["P28","P29","P36","P37"]:target_text="全场 · 公共秩序"
		elif a.id in ["P21","P22","P23"]:target_text="目标 · 对手阴谋手牌"
		elif a.id in ["P24","P25"]:target_text="抽取 · 2张"+("阴谋" if a.id=="P24" else "团体")
		elif a.id=="P14":target_text="弃牌 · "+game.title(target)
		if a.id in ["P21","P23","P24","P25"]:payer=target
		elif a.id in ["P30","P31","P32","P33","P34","P35","P42"]:payer=a.get("payer","")
		if a.type=="counter" and not game.pending_plot.is_empty():target_text="取消 · "+game.title(game.pending_plot.id)
	if target_text!="":_paragraph(target_text,body,Rect2(x,extent.y*0.77,text_width,65),20,accent)
	if payer!="":_paragraph("行动 · "+game.title(payer),body,Rect2(x,extent.y*0.89,text_width,50),17,Color("a4b6ab"))
	_sound("counter" if a.type=="counter" else "open")
	var fade_in=0.06 if reduced_motion else 0.22
	var hold=0.65 if a.type in ["trigger","support","rebuild"] else 1.25
	var fade_out=0.07 if reduced_motion else 0.28
	fade_in*=presentation_time_scale;hold*=presentation_time_scale;fade_out*=presentation_time_scale
	presentation_tween=create_tween()
	presentation_tween.set_parallel(true)
	presentation_tween.tween_property(shade,"modulate:a",1.0,fade_in)
	presentation_tween.tween_property(body,"modulate:a",1.0,fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	presentation_tween.chain().tween_interval(hold)
	presentation_tween.chain().tween_property(body,"modulate:a",0.0,fade_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	presentation_tween.parallel().tween_property(shade,"modulate:a",0.0,fade_out)
	presentation_tween.finished.connect(func():_finish_presentation(true),CONNECT_ONE_SHOT)
	return await presentation_finished

func _finish_presentation(completed: bool) -> void:
	if not presenting:return
	presenting=false
	if not completed and presentation_tween!=null:presentation_tween.kill()
	if not completed:interactions.restore_sources();combat.reset()
	presentation_tween=null
	_clear(presentation_layer)
	presentation_finished.emit(completed)

func _present_result(e: Dictionary) -> bool:
	presenting=true;_clear(overlay);_clear(large_layer);_clear(presentation_layer)
	var p=_panel(presentation_layer,Rect2(size/2-Vector2(330,145),Vector2(660,290)));p.name="DiceResult";var dice=e.get("dice",[])
	var rolling=dice.size()==2 and not reduced_motion
	var dice_label=_label("·      ·" if rolling else ("%d    +    %d"%dice if dice.size()==2 else "—"),p,70,GOLD);dice_label.position=Vector2(192,33)
	var outcome="保镖挡下摧毁" if e.get("guarded",false) else ("救援撤离" if e.get("rescued",false) else ("摧毁成功" if e.get("destroyed",false) else ("目标受灾" if e.get("devastated",false) else ("攻击成功" if e.get("success",false) else "攻击失败"))))
	var outcome_label=_label("",p,34,TEAL if e.get("success",false) else Color("d99884"));outcome_label.position=Vector2(230,153)
	presentation_tween=create_tween()
	if rolling:
		for _i in range(6):
			presentation_tween.tween_callback(func():dice_label.text="%d    +    %d"%[randi_range(1,6),randi_range(1,6)])
			presentation_tween.tween_interval(0.07*presentation_time_scale)
	presentation_tween.tween_callback(func():
		if dice.size()==2:dice_label.text="%d    +    %d"%dice
		outcome_label.text=GameLocale.text(outcome);_sound("success" if e.get("success",false) else "fail"))
	presentation_tween.tween_interval((0.5 if reduced_motion else 0.98)*presentation_time_scale)
	presentation_tween.tween_property(p,"modulate:a",0.0,(0.06 if reduced_motion else 0.16)*presentation_time_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	presentation_tween.finished.connect(func():_finish_presentation(true),CONNECT_ONE_SHOT)
	_sound("dice")
	return await presentation_finished

func _phase_overlay() -> void:
	if busy or window_access.browsing:return
	_clear(overlay)
	if interactions.picker.active:return
	if game.phase=="main":return
	if game.phase.begins_with("setup"):_setup_overlay();return
	if game.phase=="over":_victory_overlay();return
	if game.phase=="draw" and game.current==0:
		_dim(overlay);var p=_panel(overlay,Rect2(size/2-Vector2(310,170),Vector2(620,340)))
		window_access.offer(p);_label("抽牌",p,34,GOLD).position=Vector2(28,20);_label("从团体和阴谋堆各抽一张。",p,20).position=Vector2(28,78)
		var filtering=game.owner("G066")==0 or game.owner("G012")==0
		var all=_button("两类都抽 · 启用筛选" if filtering else "各抽一张",func():_do_action(0,game.legal_actions(0)[0]),p,true);all.position=Vector2(30,135);all.size=Vector2(560,65)
		var more=_button("其他抽牌方式",func():_action_list(game.legal_actions(0)),p);more.position=Vector2(30,220);more.size=Vector2(560,55)
	elif game.phase in ["choice","discard"]:
		if game.choice.get("kind","")=="w_auto":return
		if game.choice.get("player",-1)==0:_choice_overlay()
	elif game.phase=="plot_response":
		if game.pending_plot.player==1:
			if not game.battle.is_empty():_battle_overlay()
			var extent=Vector2(minf(900,size.x-100),560)
			_dim(overlay);var p=_panel(overlay,Rect2((size-extent)/2,extent));p.name="PlotResponse"
			var heading=_label("%s 打出「%s」"%[_opponent_name(),game.title(game.pending_plot.id)],p,28,GOLD);heading.position=Vector2(26,25);heading.size.x=p.size.x-56;heading.clip_text=true
			var col=_scroll_column(p,Rect2(26,90,extent.x-52,300));_wrapped(CardDB.plot_text(game.card(game.pending_plot.id)),col,22)
			var row=HFlowContainer.new();row.name="ResponseOptions";row.position=Vector2(26,420);row.size=Vector2(extent.x-52,112);row.add_theme_constant_override("h_separation",12);row.add_theme_constant_override("v_separation",10);p.add_child(row)
			var peek=window_access.offer(p);peek.reparent(row);peek.position=Vector2.ZERO
			for item in interactions.group_actions(game.legal_actions(0)):
				var a=item.action;var options=item.options
				var title={"counter":"骗局反制","trick":"替身骗局","fact_check":"事实核查","accept_plot":"放行"}.get(a.type,a.label)
				_button(title,func():_dispatch_options(options),row,a.type in ["counter","trick"])
	elif game.phase=="battle":_battle_overlay()

func _setup_overlay() -> void:
	if _online_active() and game.opening_waiting:
		_dim(overlay,0.65)
		var waiting=_panel(overlay,Rect2(size/2-Vector2(330,140),Vector2(660,280)))
		_paragraph("已确认 · 等待对手",waiting,Rect2(28,55,604,65),32,GOLD)
		_paragraph("双方确认后同时揭晓。",waiting,Rect2(28,135,604,55),22,TEAL)
		return
	_dim(overlay);var factions=game.phase=="setup_faction";var resources=game.phase=="setup_resource"
	var heading=_label("选择你的光明会" if factions else ("选择初始资源" if resources else "选择初始手下"),overlay,38,GOLD);heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;heading.position=Vector2(0,55);heading.size.x=size.x
	var note=_label("双方主牌同时揭晓 · 点击卡面查看完整能力" if factions else ("选1张加入手牌 · 其余返回资源堆" if resources else "从这五张中选一张 · 其余四张保留在手中"),overlay,20);note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;note.position=Vector2(0,117);note.size.x=size.x
	var actions=game.legal_actions(0).filter(func(a):return a.type in ["faction","initial","initial_resource"])
	var pages=ceili(actions.size()/4.0) if factions else 1
	if factions:
		faction_page=clampi(faction_page,0,pages-1);actions=actions.slice(faction_page*4,mini(actions.size(),faction_page*4+4))
	var count=actions.size();var cw=minf(250,(size.x-160)/maxi(1,count)-18);var ch=minf(400,size.y-405);var x=(size.x-(cw+18)*count+18)/2
	for i in actions.size():
		var a=actions[i];var frame=Control.new();frame.position=Vector2(x+i*(cw+18),185);frame.size=Vector2(cw,ch+110);overlay.add_child(frame)
		var v=CardView.new();v.configure(a.id,game);v.size=Vector2(cw,ch);frame.add_child(v);v.selected.connect(_inspect);v.inspected.connect(_inspect)
		if factions:
			var desc=_label(game.card(a.id).style,frame,19,TEAL);desc.position=Vector2(0,ch+12);desc.size.x=cw;desc.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var choose=_button("选择",func():_do_action(0,a),frame,true);choose.position=Vector2(0,ch+48);choose.size=Vector2(cw,55)
	_button("返回主菜单",_menu,overlay).position=Vector2(35,size.y-80)
	if factions and pages>1:
		var previous=_button("上一页",func():faction_page-=1;_phase_overlay(),overlay);previous.name="FactionPrevious";previous.position=Vector2(size.x/2-240,size.y-80);previous.size=Vector2(150,55);previous.disabled=faction_page==0
		var page=_label("%d / %d"%[faction_page+1,pages],overlay,23,GOLD);page.position=Vector2(size.x/2-50,size.y-69);page.size.x=100;page.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var next=_button("下一页",func():faction_page+=1;_phase_overlay(),overlay);next.name="FactionNext";next.position=Vector2(size.x/2+90,size.y-80);next.size=Vector2(150,55);next.disabled=faction_page==pages-1
	if not factions:
		var remaining=2-(game.resource_rerolls[0] if resources else game.mulligans[0])
		var reroll=_button("重随 · 剩余%d次"%remaining,func():_perform_type("reroll_resource" if resources else "mulligan"),overlay,true);reroll.name="ResourceMulligan" if resources else "OpeningMulligan";reroll.position=Vector2(235,size.y-80);reroll.size.x=230;reroll.disabled=remaining==0;reroll.tooltip_text=GameLocale.text("将5张候选资源放回并重抽；不影响团体和阴谋。" if resources else "全部团体手牌放回并洗牌，重抽等量团体；阴谋不变。")

func _choice_overlay() -> void:
	_dim(overlay);var c=game.choice;var p=_panel(overlay,Rect2(Vector2(75,105),size-Vector2(150,200)))
	var heading=_label(c.label,p,29,GOLD);heading.position=Vector2(28,24);heading.size.x=p.size.x-235;heading.clip_text=true;heading.tooltip_text=GameLocale.text(c.label);window_access.offer(p)
	var scroll=ScrollContainer.new();scroll.position=Vector2(28,86);scroll.size=p.size-Vector2(56,125);p.add_child(scroll)
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	var row=HBoxContainer.new();row.add_theme_constant_override("separation",20);scroll.add_child(row)
	row.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	if c.kind=="n_contact":
		scroll.size.y-=55
		var skip_action=game.legal_actions(0).filter(func(a):return a.id=="")[0]
		var skip=_button("全部放回" if c.options.is_empty() else "跳过",func():_do_action(0,skip_action),p);skip.name="ContactReturn";skip.position=Vector2(28,p.size.y-70);skip.size=Vector2(180,48)
	var card_height=minf(540,scroll.size.y-65);var card_width=minf(290,card_height*0.54)
	var actions=game.legal_actions(0)
	if c.kind=="n_inside":
		var v=CardView.new();v.name="InsideJobCard";v.configure(c.revealed_card,game,true);v.custom_minimum_size=Vector2(card_width,card_height);row.add_child(v);v.inspected.connect(_inspect);v.selected.connect(_inspect)
		var modes=VBoxContainer.new();modes.add_theme_constant_override("separation",16);modes.custom_minimum_size.x=minf(380,scroll.size.x-card_width-20);row.add_child(modes)
		for a in actions:
			var choose=_button(a.label,func():_do_action(0,a),modes,true);choose.name="InsideJobTop" if a.id=="top" else "InsideJobBottom";choose.custom_minimum_size.y=70
		return
	var items=c.peek if c.kind=="n_contact" else (c.peek+[""] if c.kind in ["nasa","japan","n_relic","n_divine"] else actions.map(func(a):return a.id))
	for id in items:
		var matching=actions.filter(func(a):return a.id==id)
		var a=matching[0] if not matching.is_empty() else {}
		if id=="":
			var skip=_button("看完返回" if c.kind=="n_divine" else ("全部放回" if c.options.is_empty() else "跳过"),func():_do_action(0,a),row);skip.custom_minimum_size=Vector2(140,55);skip.size_flags_vertical=Control.SIZE_SHRINK_END;continue
		var column=VBoxContainer.new();column.add_theme_constant_override("separation",8);column.size_flags_vertical=Control.SIZE_SHRINK_BEGIN;row.add_child(column)
		var v=CardView.new();v.configure(id,game,true);v.custom_minimum_size=Vector2(card_width,card_height);column.add_child(v);v.inspected.connect(_inspect);v.selected.connect(_inspect)
		if not a.is_empty():
			var choose=_button("选择",func():_do_action(0,a),column,true);choose.custom_minimum_size.y=55
		else:
			if c.kind!="n_divine":v.modulate=Color("a3ada6")
			var unavailable=_button("仅查看 · 原序放回" if c.kind=="n_divine" else ("非太空 · 洗回" if c.kind=="n_contact" else ("非秘宝 · 洗回" if c.kind=="n_relic" else "放回堆底")),func():pass,column);unavailable.disabled=true

func _battle_overlay() -> void:
	var b=game.battle;var v=game.battle_values();var width=minf(1320,size.x-100);var height=minf(680,size.y-170)
	var p=_panel(overlay,Rect2(Vector2((size.x-width)/2,size.y-height-30),Vector2(width,height)))
	_drag_title(p,(game.title(b.disaster) if b.has("disaster") else ("控制" if b.mode=="control" else "摧毁"))+" · "+game.title(b.src)+" → "+game.title(b.target),"battle");window_access.offer(p,Vector2(-1,62))
	var left_w=width*0.49
	_label("强度 %d    成功率 %.1f%%"%[v.strength,v.chance*100],p,32,TEAL).position=Vector2(26,66)
	var calculation="力量 %d  阵营 %+d  能力 %+d  支援 +%d  阴谋 +%d\n防御 %d  忠诚 %d  位置 %d  自卫/支援 %d  其他 %d"%[v.power,v.alignment,v.ability,v.support_a,v.bonus_a,v.base,v.loyalty,v.position,v.support_d,v.defense+v.bonus_d]
	if b.has("disaster"):calculation="威力%d  修正%+d  阴谋%+d\n防御%d  被动%d  支援/自卫%d  其他%d\n摧毁概率 %.1f%%"%[v.power,v.ability,v.bonus_a,v.base,v.defense,v.support_d,v.bonus_d,v.destroy_chance*100]
	_paragraph(calculation,p,Rect2(26,125,left_w-42,88),18)
	var changes: Array=[]
	if not b.has("disaster") and b.target=="G067" and game.wave.enabled("G067"):changes.append("高额账单 · 失败弃1阴谋")
	if v.get("no_self",false):changes.append("目标不能自卫")
	if b.get("sniped",false):changes.append("忽略位置")
	if b.get("alignment_zero",false):changes.append("阵营归零")
	if b.get("mobilized",false):changes.append("共产支援可用P")
	if b.has("fixed_dice"):changes.append("固定骰点 %d＋%d"%b.fixed_dice)
	if not changes.is_empty():_label(" · ".join(changes),p,16,GOLD).position=Vector2(26,201)
	_label("本次战斗",p,24,GOLD).position=Vector2(left_w+22,65)
	_battle_feed(p,Rect2(left_w+22,110,width-left_w-48,height-136),b.get("entries",[]))
	if b.responder==1 or game.phase=="plot_response":_label("等待对手响应" if _online_active() else "AI 正在响应…",p,24,GOLD).position=Vector2(26,235);return
	if game.legal_actions(0).size()==1 and game.legal_actions(0)[0].type=="pass":_label("双方完成响应，准备掷骰…",p,23,GOLD).position=Vector2(26,235);return
	_label("你的响应 · 追加一次后交给对方",p,20,Color("a6b5a6")).position=Vector2(26,224)
	var scroll=ScrollContainer.new();scroll.position=Vector2(26,270);scroll.size=Vector2(left_w-42,height-296);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;p.add_child(scroll)
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",7);scroll.add_child(col)
	for entry in interactions.group_actions(game.legal_actions(0)):
		var a=entry.action
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",8);col.add_child(row)
		var title=a.label if entry.options.size()==1 else game.title(a.get("id",a.get("src","")))+" · 选择方式或费用"
		var btn=_button(title,func():_dispatch_options(entry.options),row,a.type=="pass");btn.size_flags_horizontal=Control.SIZE_EXPAND_FILL;btn.alignment=HORIZONTAL_ALIGNMENT_LEFT;btn.add_theme_font_size_override("font_size",18);btn.custom_minimum_size.y=48;btn.clip_text=true;btn.tooltip_text=GameLocale.text(title)
		var detail_id=a.get("id",a.get("src",""))
		if detail_id!="":_button("查看",func():_inspect(detail_id),row)

func _battle_feed(parent: Node,rect: Rect2,entries: Array) -> void:
	var col=_scroll_column(parent,rect);col.name="BattleFeed"
	for entry in entries:
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",12);col.add_child(row)
		var art=TextureRect.new();art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;art.texture=CardDB.art(game.card(entry.id).id);art.custom_minimum_size=Vector2(58,62);row.add_child(art)
		var body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(body)
		_wrapped(entry.text,body,19,TEAL if entry.player==0 else Color("e2ac98"))
		if entry.get("status","")!="":_label(entry.status,body,16,Color("b9bfaa"))
		var show=_button("查看",func():_inspect(entry.id),row);show.custom_minimum_size=Vector2(62,44);show.add_theme_font_size_override("font_size",16)
	_scroll_feed_end(col.get_parent())

func _scroll_feed_end(scroll: ScrollContainer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll):scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)

func _battle_history() -> void:
	if window_access.browsing:return
	modal_open=true;_clear(large_layer);_dim(large_layer)
	var extent=Vector2(minf(1000,size.x-120),minf(730,size.y-110));var p=_panel(large_layer,Rect2((size-extent)/2,extent))
	_label("最近战斗",p,30,GOLD).position=Vector2(26,16)
	var b=game.last_battle
	if not b.is_empty():
		_label("%s → %s · %s"%[game.title(b.src),game.title(b.target),"攻击取消" if b.get("cancelled",false) else ("成功" if b.success else "失败")],p,23,TEAL).position=Vector2(26,70)
		_battle_feed(p,Rect2(26,125,extent.x-52,extent.y-220),b.entries)
	_button("收起战况",func():_clear(large_layer);modal_open=false;_schedule_ai(),p,true).position=Vector2(extent.x-180,extent.y-75)

func _victory_overlay() -> void:
	if busy:return
	var result=game.victory;var kind=result.get("kind","");var goal_id=result.get("card","") if kind=="goal" else ""
	var show_goal=game.covenant.is_goal(goal_id)
	var extent=Vector2(minf(980 if show_goal else 800,size.x-90),minf(750 if show_goal else 500,size.y-90))
	_dim(overlay);var p=_panel(overlay,Rect2((size-extent)/2,extent));p.name="VictoryWindow"
	var heading="平局" if game.winner<0 else ("你获胜" if game.winner==0 else ("对手获胜" if _online_active() else "AI 获胜"))
	var title=_paragraph(heading,p,Rect2(28,24,extent.x-56,72),46,GOLD);title.name="VictoryHeading";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var x=40.0
	if show_goal:
		var view=CardView.new();view.name="WinningGoal";view.configure(goal_id,game,true);view.size=Vector2(minf(270,(extent.y-200)*0.58),extent.y-200);view.position=Vector2(28,112);p.add_child(view);view.selected.connect(_inspect);view.inspected.connect(_inspect);x=view.position.x+view.size.x+34
	var col=_scroll_column(p,Rect2(x,112,extent.x-x-36,extent.y-225));col.get_parent().name="VictoryReason"
	if game.winner>=0 and game.nodes.has(game.root(game.winner)):_wrapped(game.title(game.root(game.winner)),col,27,TEAL)
	if kind=="goal":
		_wrapped("达成目标阴谋",col,24,GOLD);_wrapped(game.card(goal_id).effect,col,25)
	elif kind=="faction":
		_wrapped("达成光明会目标",col,24,GOLD);_wrapped(game.card(game.root(game.winner)).goal,col,25)
	elif kind=="elimination":_wrapped(result.reason,col,26,GOLD)
	elif kind=="draw":
		_wrapped("双方同时完成目标",col,25,GOLD)
		for who in [0,1]:_wrapped(game.title(game.root(who))+" · "+game.card(game.root(who)).goal,col,22)
	else:_wrapped(result.get("reason",game.logs.back() if not game.logs.is_empty() else ""),col,25)
	if _online_active():
		var invitation=_wrapped("",col,21,TEAL);invitation.name="OnlineRematchStatus"
	var width=minf(220,(extent.x-80)/3);var y=extent.y-80
	var again=_button("再来一局",func():_start_game(),p,true);again.position=Vector2(28,y);again.size=Vector2(width,52)
	if _online_active():again.name="OnlineRematchButton";online.update_rematch_ui()
	var peek=window_access.offer(p,Vector2((extent.x-width)/2,y));peek.size=Vector2(width,52)
	var menu=_button("主菜单",_menu,p);menu.position=Vector2(extent.x-width-28,y);menu.size=Vector2(width,52)

func _inspect(id: String,nested: bool=false) -> void:
	if busy or window_access.transitioning:return
	if detail_layer.get_child_count()==0:inspection_was_paused=modal_open
	if not nested:interactions.reader_stack.clear()
	interactions.reader_id=id;modal_open=true
	_clear(detail_layer);_clear(hover_layer);_dim(detail_layer)
	if compact:_mobile_detail(id);_sound("open");return
	var extent=Vector2(minf(1060,size.x-100),minf(790,size.y-70));var p=_panel(detail_layer,Rect2((size-extent)/2,extent))
	var card_w=350.0
	var v=CardView.new();v.configure(id,game,true);v.position=Vector2(24,24);v.size=Vector2(card_w,extent.y-48);p.add_child(v)
	var x=card_w+55;var c=game.card(id) if game!=null else CardDB.get_card(id)
	_paragraph(c.name,p,Rect2(x,22,extent.x-x-30,64),32,GOLD) if GameLocale.english() else _label(c.name,p,32,GOLD).set_position(Vector2(x,22))
	var col=_scroll_column(p,Rect2(x,92,extent.x-x-30,extent.y-190));col.get_parent().name="ReaderScroll"
	interactions.attachment_buttons(id,col)
	if c.kind=="plot":
		_wrapped(CardDB.plot_text(c),col,23)
		if game!=null and game.covenant.is_goal(c.id):_wrapped(game.covenant.reader_text(c.id),col,22,TEAL)
	else:
		_wrapped(c.effect,col,23,TEAL)
		_wrapped(_card_context_text(id),col,23)
		if c.kind=="faction":_wrapped("目标 · "+c.goal,col,22)
	var preview=_preview_note(id)
	if preview!="":_wrapped(preview,col,21,TEAL)
	var close=_button("返回团体" if not interactions.reader_stack.is_empty() else "收起大卡",_close_inspection,p,true);close.position=Vector2(extent.x-245,extent.y-78);close.size=Vector2(215,54);_sound("open")

func _preview_note(id: String) -> String:
	if preview_action.is_empty() or not preview_action.has("mode") or game==null:return ""
	var options=game.attack_options(preview_action.src,preview_action.target,preview_action.mode,preview_action)
	for entry in options.supports:
		if entry.id==id:return "本次可支援 +%d（%s）\n%s；需要1个行动标记。"%[entry.power,entry.basis,entry.reason]
	for entry in options.plots:
		if entry.id==id:
			var text="本次预览 · "+entry.status+"\n"+entry.reason
			var names=entry.targets.filter(func(k):return k!="").map(func(k):return game.title(k))
			if not names.is_empty():text+="\n适用团体 · "+" / ".join(names)
			return text
	return ""

func _card_context_text(id: String) -> String:
	if game==null:return "图鉴数值 · 进场后可查看忠诚、位置与当前状态。"
	if game.card(id).kind=="resource":return game.resources.reader(id)
	var context=game.card_context(id)
	if not context.on_board:return "未进场\n忠诚 +0   位置 +0\n进场后才可支援或自卫。"
	var lines: Array=[]
	lines.append(("己方" if context.owner==0 else "对方")+" · "+("光明会主牌" if context.root else "上级「%s」"%game.title(context.parent)))
	lines.append("行动标记  %d / %d    下属槽  %d / %d"%[context.token,game.action_limit(id),context.occupied,context.slots])
	if not context.root:
		lines.append("忠诚 +%d    位置 +%d（第%d层）"%[context.loyalty,context.position,context.depth])
		lines.append("控制防御 %d = 抗性%d + 忠诚%d + 位置%d + 被动%d"%[context.control_total,game.stat(id,"r"),context.loyalty,context.position,context.control_passive])
		lines.append("摧毁防御 %d = %s%d + 位置%d + 被动%d"%[context.destroy_total,"抗性" if id=="G076" else "力量",context.destroy_base,context.position,context.destroy_passive])
		var self_text="可自卫 +%d（不消耗标记）" if game.factions[context.owner]=="I11" and game.has(id,"绿色") else "可自卫 +%d（消耗1标记）"
		lines.append(self_text%game.self_power(id) if context.token>0 else "无标记 · 当前不可支援或自卫")
		if id=="G039":lines.append("对政府团体的控制攻击，额外防御 +4。")
		if id=="G061":lines.append("对暴力团体的摧毁攻击，额外防御 +4。")
		if id=="G042":lines.append("抵御科学或太空团体的控制攻击，额外防御 +4。")
		lines.append("以上未计攻击者能力、支援与阴谋。")
	else:lines.append("主牌不可成为攻击目标。")
	var printed=context.printed
	lines.append("印刷  P%d / GP%d / R%d / 槽%d\n当前  P%d / GP%d / R%d / 槽%d"%[printed.p,printed.gp,printed.r,printed.slots,game.stat(id,"p"),game.stat(id,"gp"),game.stat(id,"r"),game.stat(id,"slots")])
	if context.captured:lines.append("本回合进场或被夺取 · 不能获得行动标记。")
	elif context.recharged:lines.append("本回合额外恢复次数已用。")
	else:lines.append("本回合额外恢复次数未用。")
	if context.used:lines.append("本回合主动能力已用。")
	var n=game.nodes[id]
	lines.append_array(game.contemporary.reader(id))
	if n.get("devastated",false):lines.append("受灾 · P／GP减半；不能行动或补标记，不计胜利。需重建。")
	if n.get("prepared",false):lines.append("防备 · 下次灾难%s防御+4，发动时消耗。"%("或普通摧毁" if id=="G148" and game.renewal.ready(id) else ""))
	if id in ["G136","G137","G139","G145","G146"] and not game.renewal.unused(id):lines.append("本回合限次效果已用。")
	if n.get("learned",0)>0:lines.append("革命课堂 · 在场强化 P+%d。"%n.learned)
	if n.get("pacified",false):lines.append("化干戈 · 暴力转为和平，在场期间保留。")
	if n.has("mask"):lines.append("伪造身份 · 本回合阵营："+" / ".join(n.mask))
	if n.parent=="G133" and game.renewal.ready("G133") and game.has(id,"共产"):lines.append("自治工厂 · 直属共产下属 P+2。")
	if game.renewal.housing_bonus(id):lines.append("社区住房合作社 · 本团体下属槽+1，上限3。")
	if id=="G145" and game.renewal.ready(id) and game.renewal.unused(id) and game.token(id):lines.append("民兵动员 · 可免标记自卫 +%d。"%game.stat(id,"p"))
	if n.get("silenced",false):lines.append("本回合卡面能力失效。")
	if id=="G088":lines.append("训练 %d / 2"%n.get("training",0))
	if id=="G119" and game.synergy.ready(id):lines.append("联合生产 · 直属共产下属提供P+%d（上限2）。"%mini(2,game.children(id).filter(func(k):return game.has(k,"共产")).size()))
	if id=="G008" and game.wave.enabled(id):lines.append("联合协作 · 直属国家下属%d个。"%game.children(id).filter(func(k):return game.has(k,"国家")).size())
	if "P44" in n.attached:lines.append("保镖 · 挡下1次普通摧毁，随后弃掉并清空本团体标记。")
	if "P45" in n.attached:lines.append("监管调查 · GP 0；己方主要阶段可花本团体1标记解除。")
	if game.synergy.ready("G128",context.owner) and not game.has(id,"企业"):lines.append("消费者协会 · 抵御企业的控制攻击时，防御+2。")
	if id=="G083" and game.wave.plans.has(context.owner):lines.append("公开预案 · %d＋%d"%game.wave.plans[context.owner])
	if n.parent=="G081" and game.wave.enabled("G081"):lines.append("跨界整合 · 当前标签："+" / ".join(game.tags(id)))
	if game.has(id,"地点"):
		lines.append("灾难基础防御 %d；被动+%d；防备+%d。灾难不计忠诚和位置。"%[context.disaster_base,context.disaster_passive,4 if n.get("prepared",false) else 0])
		if game.wave.enabled("G030",context.owner):lines.append("国际气象组织 · 灾难防御+5。")
		if game.resources.ready("E03",context.owner):lines.append("防灾卫星 · 灾难防御+3。")
		if game.wave.devastated(id) and game.has(id,"巨大") and game.resources.ready("E14",context.owner):lines.append("重型抢修车 · 重建只需1行动，完成后抽1张团体。")
	if n.get("debt",false):lines.append("借贷负债：下次轮到控制者补标记时，跳过本团体一次；已有标记不移除。")
	if n.get("ad_gp",0)>0:lines.append("定向投放：本回合GP+%d，不超过有效P。"%n.ad_gp)
	if n.get("compute",false):lines.append("本回合GP等于有效P。")
	if not n.get("extra_tags",[]).is_empty():lines.append("新增标签 · "+" / ".join(n.extra_tags)+"（离场清除）")
	if n.parent=="G073" and (game.has(id,"企业") or game.has(id,"科学")):lines.append("工业标准：来自德国的抗性 +2。")
	if n.parent=="G077" and (game.has(id,"企业") or game.has(id,"银行")):lines.append("资本枢纽：来自纽约的GP +1，不超过P。")
	if not context.attached.is_empty():lines.append("附着 · "+" / ".join(context.attached.map(func(k):return CardDB.name_of(k))))
	if game.world!="":lines.append("公共秩序 · "+game.title(game.world).replace("新世界秩序：",""))
	if not game.battle.is_empty() and game.battle.target==id:
		var v=game.battle_values()
		lines.append("本次战斗 · 忠诚%d / 位置%d / 被动%d\n自卫与支援 +%d / 阴谋防御 +%d"%[v.loyalty,v.position,v.defense,v.support_d,v.bonus_d])
		if v.get("no_self",false):lines.append("集体谈判 · 本次不能自卫，仍可接受支援。")
	return "\n\n".join(lines)

func _mobile_detail(id: String) -> void:
	var c=game.card(id) if game!=null else CardDB.get_card(id)
	var p=_panel(detail_layer,Rect2(Vector2(35,35) if GameLocale.english() else Vector2(65,50),size-(Vector2(70,70) if GameLocale.english() else Vector2(130,100))))
	_label(c.name,p,36,GOLD).position=Vector2(32,22)
	if not GameLocale.english():_label(c.en,p,21,Color("a7baac")).position=Vector2(34,80)
	var picture=TextureRect.new();picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.texture=CardDB.art(c.id);picture.position=Vector2(32,140);picture.size=Vector2.ONE*minf(minf(415,p.size.y-250),p.size.x*0.35 if GameLocale.english() else 415);p.add_child(picture)
	var x=minf(490,p.size.x*0.39) if GameLocale.english() else 490.0;var a=game.alignments(id) if game!=null else c.align
	if c.kind not in ["plot","resource"]:
		var values=[game.stat(id,"p"),game.stat(id,"gp"),game.stat(id,"r"),game.stat(id,"slots")] if game!=null and game.nodes.has(id) else [c.p,c.gp,c.r,c.slots]
		_label("P %d   GP %d   R %d   下属槽 %d"%values,p,23 if GameLocale.english() else 30,CREAM).position=Vector2(x,140)
		_label(" · ".join(a),p,19 if GameLocale.english() else 27,TEAL).position=Vector2(x,200)
		_label(" / ".join(game.tags(id) if game!=null else c.tags),p,17 if GameLocale.english() else 22,Color("b7c7b0")).position=Vector2(x,249)
		if game!=null and game.nodes.has(id) and not game.is_root(id):_label("忠诚 +%d   位置 +%d"%[game.loyalty_defense(id),game.position_defense(id)],p,17 if GameLocale.english() else 24,TEAL).position=Vector2(x if GameLocale.english() else x+270,278 if GameLocale.english() else 249)
	else:_label(c.category+(" · "+c.mode if c.kind=="resource" else ""),p,22 if GameLocale.english() else 28,TEAL).position=Vector2(x,140)
	var text=c.effect
	if c.kind=="plot":
		text=CardDB.plot_text(c)
		if game!=null and game.covenant.is_goal(c.id):text+="\n\n"+game.covenant.reader_text(c.id)
	if c.kind=="faction":text+="\n\n胜利 · "+c.get("goal","")
	var body_y=205 if c.kind in ["plot","resource"] else 305
	var col=_scroll_column(p,Rect2(Vector2(x,body_y),Vector2(p.size.x-x-45,p.size.y-body_y-100)));col.get_parent().name="ReaderScroll"
	interactions.attachment_buttons(id,col)
	_wrapped(text,col,22 if GameLocale.english() else 27)
	if c.kind!="plot":_wrapped(_card_context_text(id),col,20 if GameLocale.english() else 25)
	var preview=_preview_note(id)
	if preview!="":_wrapped(preview,col,24,TEAL)
	var close=_button("返回团体" if not interactions.reader_stack.is_empty() else "收起大卡",_close_inspection,p,true);close.position=Vector2(p.size.x-305,p.size.y-82);close.size=Vector2(270,58)

func _close_inspection() -> void:
	if interactions.close_reader():return
	interactions.reader_id=""
	_clear(detail_layer);modal_open=inspection_was_paused;_sound("close");_schedule_ai()

func _hover(id: String,showing: bool) -> void:
	if compact or (modal_open and not window_access.browsing) or busy or (large_layer.visible and not large_layer.get_children().is_empty()) or not detail_layer.get_children().is_empty():return
	_clear(hover_layer)
	if not showing:return
	var v=CardView.new();v.configure(id,game,true);v.mouse_filter=Control.MOUSE_FILTER_IGNORE;v.position=Vector2(size.x-415,145);v.size=Vector2(380,size.y-230);hover_layer.add_child(v)

func _schedule_ai() -> void:
	if _online_active():return
	if window_access.browsing or window_access.transitioning or interactions.picker.active or thinking or busy or panel_dragging or modal_open or game==null or game.phase=="over" or game.phase.begins_with("setup"):return
	var forced=game.legal_actions(0)
	if forced.size()==1 and forced[0].type in ["pass","trigger"]:_forced_pass();return
	var legal=game.legal_actions(1)
	if legal.is_empty():return
	var this_match=match_id
	thinking=true;await get_tree().create_timer(0.12 if reduced_motion or legal.size()==1 else 0.55).timeout
	if this_match!=match_id:return
	if game==null or window_access.browsing or window_access.transitioning or busy or panel_dragging or modal_open:thinking=false;return
	var o=game.observation(1,false)
	var this_level=ai.difficulty
	var command=await ai.pick_async(o,get_tree(),func():return this_match==match_id and ai.difficulty==this_level and game!=null and not (window_access.browsing or window_access.transitioning or busy or panel_dragging or modal_open))
	if this_match!=match_id:return
	thinking=false
	if not command.is_empty():_do_action(1,command)
	else:_schedule_ai()

func _forced_pass() -> void:
	if forced_pending:return
	forced_pending=true;var this_match=match_id
	await get_tree().create_timer(0.15).timeout
	if this_match!=match_id:return
	forced_pending=false
	if game==null or window_access.browsing or window_access.transitioning or busy or panel_dragging or modal_open:return
	var legal=game.legal_actions(0)
	if legal.size()==1 and legal[0].type in ["pass","trigger"]:_do_action(0,legal[0])

func _toast(text: String) -> void:
	notification.text=GameLocale.text(text);notification.modulate.a=1
	var tween=create_tween();tween.tween_interval(3);tween.tween_property(notification,"modulate:a",0.0,0.4)

func _journal() -> void:
	if window_access.browsing:return
	modal_open=true
	_clear(large_layer);_dim(large_layer);var p=_panel(large_layer,Rect2(size/2-Vector2(440,330),Vector2(880,660)))
	_label("暗流记录",p,30,GOLD).position=Vector2(26,20)
	if not game.last_battle.is_empty():_button("最近战斗",_battle_history,p,true).position=Vector2(590,20)
	var scroll=ScrollContainer.new();scroll.position=Vector2(26,82);scroll.size=Vector2(828,495);p.add_child(scroll)
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",12);scroll.add_child(col)
	for line in game.logs:
		var l=_label(line,col,19);l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_button("关闭",func():_clear(large_layer);modal_open=false;_schedule_ai(),p).position=Vector2(725,592)

func _piles() -> void:
	if window_access.browsing:return
	modal_open=true
	_clear(large_layer);_dim(large_layer);var p=_panel(large_layer,Rect2(size/2-Vector2(440,320),Vector2(880,640)))
	_label("公开牌区",p,30,GOLD).position=Vector2(26,20)
	var scroll=ScrollContainer.new();scroll.position=Vector2(26,85);scroll.size=Vector2(828,460);p.add_child(scroll)
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(col)
	var piles={"团体弃牌":game.discards.group,"阴谋弃牌":game.discards.plot,"资源弃牌":game.discards.resource,"资源报废":game.scrap,"你的摧毁记录":game.graves[0],("对手的摧毁记录" if _online_active() else "AI 的摧毁记录"):game.graves[1],"已公开的对手手牌":game.exposed.filter(func(id):return id in game.hands[1].group or id in game.hands[1].plot)}
	for key in piles:
		_label(key+" · %d"%piles[key].size(),col,22,GOLD)
		for id in piles[key]:_button(game.title(id),func():_inspect(id),col)
	_button("关闭",func():_clear(large_layer);modal_open=false;_schedule_ai(),p).position=Vector2(725,570)

func _settings() -> void:
	if window_access.browsing:return
	modal_open=true;_clear(large_layer);_clear(hover_layer);_dim(large_layer);var p=_panel(large_layer,Rect2(size/2-Vector2(340,310),Vector2(680,620)))
	_label("设置",p,34,GOLD).position=Vector2(28,20);_label("音效",p,22).position=Vector2(30,100)
	var slider=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=0.05;slider.value=sound_volume;slider.position=Vector2(165,100);slider.size=Vector2(455,40);p.add_child(slider);slider.value_changed.connect(func(v):sound_volume=v;_save_settings())
	var motion=CheckButton.new();motion.name="ReducedMotion";motion.text=GameLocale.text("好友对战统一完整动画" if _online_active() else "减少动态效果");motion.button_pressed=reduced_motion;motion.disabled=_online_active();motion.position=Vector2(30,175);p.add_child(motion);motion.toggled.connect(func(v):reduced_motion=v;_save_settings())
	var mobile=CheckButton.new();mobile.text=GameLocale.text("横屏移动布局");mobile.button_pressed=compact;mobile.position=Vector2(30,238);p.add_child(mobile);mobile.toggled.connect(func(v):compact=v;_save_settings();_resize())
	_button("玩法与操作",_help,p).position=Vector2(30,370);_button("卡牌图鉴",_catalog,p).position=Vector2(310,370)
	_label("语言 / Language",p,22).position=Vector2(30,300)
	var language_choice=OptionButton.new();language_choice.name="LanguageChoice";language_choice.position=Vector2(325,292);language_choice.size=Vector2(290,48);language_choice.add_item("中文");language_choice.add_item("English");language_choice.select(1 if GameLocale.english() else 0);p.add_child(language_choice)
	language_choice.item_selected.connect(func(index):_change_language("en" if index==1 else "zh"))
	var difficulty_caption=_label("好友对战" if _online_active() else "AI难度",p,22);difficulty_caption.position=Vector2(30,435)
	var difficulty_choice=OptionButton.new();difficulty_choice.name="DifficultyChoice";difficulty_choice.position=Vector2(325,427);difficulty_choice.size=Vector2(290,48)
	for level in ["简单","普通","困难"]:difficulty_choice.add_item(GameLocale.text(level))
	difficulty_choice.select(["easy","normal","hard"].find(ai_difficulty));p.add_child(difficulty_choice)
	if _online_active():difficulty_choice.hide();_label(GameLocale.text("房间号")+" · "+online.code,p,22,TEAL).position=Vector2(325,435)
	difficulty_choice.item_selected.connect(func(index):ai_difficulty=["easy","normal","hard"][index];ai.difficulty=ai_difficulty;_save_settings())
	if game!=null:_button("返回主菜单",_menu,p).position=Vector2(30,530)
	var update_button=_button("检查更新",_updates,p);update_button.name="CheckUpdates";update_button.position=Vector2(325,485);update_button.size=Vector2(290,36);update_button.custom_minimum_size.y=36;update_button.add_theme_font_size_override("font_size",18)
	var close=_button("返回游戏" if game!=null else "返回",_close_settings,p,true);close.position=Vector2(440,530);close.size=Vector2(205,55)

func _help(page: String="basic") -> void:
	_clear(large_layer);_dim(large_layer);var p=_panel(large_layer,Rect2(size/2-Vector2(430,330),Vector2(860,660)))
	_label("玩法与操作",p,30,GOLD).position=Vector2(28,20)
	var tabs=HBoxContainer.new();tabs.position=Vector2(28,77);tabs.add_theme_constant_override("separation",12);p.add_child(tabs)
	for key in ["basic","alignments","disaster","cards","controls"]:_button({"basic":"基础","alignments":"阵营与标签","disaster":"灾难与状态","controls":"操作","cards":"卡面用语"}[key],func():_help(key),tabs,key==page)
	var pages={
		"alignments":"P力量：带头进攻、自卫和合资格支援。GP全球力量：不满足P支援条件时使用；P与GP不相加。R抗性：控制攻击的基础防御。\n\n相反阵营：政府↔企业、自由↔保守、和平↔暴力、正统↔怪异、狂热↔狂热。犯罪没有相反阵营。狂热不算共同阵营。\n控制攻击：带头者与目标每个共同阵营+4，每对相反阵营−4；摧毁攻击反过来。\n\n忠诚：目标与直属上级每个共同阵营+4，仅防控制，相反阵营不扣分。\n位置：主牌直属下属+10，下一层+5，更深+0；同时防控制与摧毁。\n自卫：目标花自身行动，额外防御+2P。\n\n支援时与受攻击目标比较：控制进攻共有阵营用P；摧毁进攻相反阵营用P；防守共有阵营或互为直属上下级用P。否则用GP，通常花支援者1行动。\n\n标签不是阵营：军队、共产、魔法、太空、名人、地点等只在卡文指定时生效；不会自动增加阵营修正。巨大与沿海也属于标签。国家用于国家级地点，州、城市与港口不计入。",
		"basic":"初始团体从五张手牌中选，可整手重随至多2次。\n初始团体选完后，从5张资源候选中选1张入手，可独立重随2次。团体、阴谋、资源使用独立牌堆。\n掷骰定先后，后手额外抽1张阴谋。\n抽牌 → 补行动 → 自由行动 → 回合末检查主牌目标。\n目标阴谋：己方主要阶段达标后主动打出，可被反制。\n\n自动接管：每回合一次，花主牌行动。新团体当回合无标记，且不能恢复；控制进场也相同。\n控制：带头者须有空槽，成功夺取整支子树。\n摧毁：只摧毁目标，其下属回原主人的手中。\n\n双方交替支援和出阴谋，连续放行才掷骰。\n2d6 ≤ 最终强度成功；11、12永远失败。\n\n支援控制：共有阵营可用P，否则GP。\n支援摧毁：相反阵营可用P，否则GP。\n支援防守：共有阵营或直属上下级可用P，否则GP。\n每个参战者通常花1个标记，P与GP不相加。",
		"disaster":"灾难只攻击地点，花1个非主牌团体标记策动。\n反制窗口后，目标失去标记，再消耗防备并交替响应。\n\n灾难以威力攻击目标P。\n忽略阵营、忠诚和位置；只有防守方可普通支援。\n普通攻击专用能力不适用于灾难。\n\n受灾：自身P／GP减半、不能行动，不计胜利；下属正常。\n重建：主要阶段花1个团体标记，巨大需2个不同团体；重型抢修车可减至1个。\n重建后不会立刻获得标记。\n\n防备：下次灾难防御+4。\n训练：C罗带头攻击时可花1枚换+2。\n预案：发动控制攻击时就决定是否采用。",
		"cards":"主动：己方主要阶段、每回合1次，花本团体1标记；写明免费则不花。\n恢复：无标记、未额外恢复，且不是本回合进场或被夺取。\n\n在场期间：易主保留，离场清除。\n直属光环：按卡文作用于直属上级或下属；来源禁能或关系结束则失效。\n槽位强制减少：控制者选超额分支整支回手；主动调整须先保证槽位合法。\n\n附着：随团体易主，团体离场弃掉。\n整支移动：连同下属，不重置状态。\n防备：最多1枚，消耗后本次防御+4。\n临时阵营在回合末恢复，手牌超限则弃至合法。\n\n目标阴谋：占阴谋手牌上限，每人最多1张。达标后在己方主要阶段打出宣告胜利；正常反制，不花行动标记。\n\n抽牌：主要阶段花主牌1行动，从三堆任选一堆抽1张。资源手牌默认上限2，满额不能抽资源。\n部署资源与自动接管各每回合1次，通常各花主牌1行动。\n场上资源最多2张，位于主牌左右；满额部署须报废替换1张。\n有行动能力的资源进场回合为0，下次己方回合补至1；额外恢复沿用通则。\n资源不计团体／P／团体标签目标，不参与普通支援。\n无行动标记的资源按卡文持续、触发或报废使用。报废资源本局不回收。征用入手不算报废；交换资源保留状态，但行动归0，进场回合不能恢复。",
		"controls":"空白处拖动平移，滚轮或双指缩放。\n己方／对手／全局按钮用于定位。\n\n单击选牌；悬停、右键、长按或「查看大卡」看完整卡。\n开局点图片只查看，点「选择」才确认。\n多目标操作分步选择，可返回或取消；确认前不支付。\n大卡的附着按钮可查看该牌，关闭后返回团体。\n抽弃牌与目标动效结束后才结算，期间暂停操作。\n\n可先选敌方目标，再选控制／摧毁和带头者。\n战斗与攻击预览可拖动标题栏。\n\n大卡、小卡与手牌均使用1:1图片区，不拉伸或裁切。\n\n音效：Kenney Interface Sounds / CC0。\n字体：Noto Sans SC / OFL。"}
	var col=_scroll_column(p,Rect2(28,147,804,405));_wrapped(pages[page],col,22)
	_button("返回设置",_settings,p).position=Vector2(640,585)

func _catalog() -> void:
	interactions.catalog()

func _save_settings() -> void:
	if settings_path=="user://settings.cfg" and "--test-defaults" in OS.get_cmdline_user_args():return
	var c=ConfigFile.new();c.set_value("settings","difficulty",ai_difficulty);c.set_value("settings","language",GameLocale.language);c.set_value("settings","volume",sound_volume);c.set_value("settings","compact",compact);c.set_value("settings","reduced_motion",preferred_reduced_motion);c.set_value("settings","auto_update_check",auto_update_check);c.save(settings_path)

func _load_settings() -> void:
	if settings_path=="user://settings.cfg" and "--test-defaults" in OS.get_cmdline_user_args():GameLocale.set_language("zh");return
	var default_language="en" if OS.has_feature("english_default") else "zh"
	GameLocale.set_language(default_language)
	var c=ConfigFile.new()
	if c.load(settings_path)==OK:
		auto_update_check=c.get_value("settings","auto_update_check",true)
		ai_difficulty=c.get_value("settings","difficulty","normal");ai_difficulty=ai_difficulty if ai_difficulty in ["easy","normal","hard"] else "normal";ai.difficulty=ai_difficulty
		GameLocale.set_language(c.get_value("settings","language",default_language));sound_volume=c.get_value("settings","volume",0.6);compact=c.get_value("settings","compact",compact);reduced_motion=c.get_value("settings","reduced_motion",false)

func _unhandled_key_input(e: InputEvent) -> void:
	if busy or window_access.transitioning:return
	if e is InputEventKey and e.pressed and e.keycode==KEY_ESCAPE:
		if update_window!=null:update_window.close()
		elif not detail_layer.get_children().is_empty():_close_inspection()
		elif window_access.browsing:window_access.resume()
		elif interactions.picker.active:interactions.back()
		elif not large_layer.get_children().is_empty():preview_action={};_clear(large_layer);modal_open=false;_schedule_ai()
		elif not action_candidates.is_empty():action_candidates.clear();_refresh(false)
		elif game!=null and game.phase=="plot_response" and game.pending_plot.player==1:window_access.peek()
		else:_settings()

func _snapshot_setup() -> void:
	if snapshot_mode=="menu":_menu();await _capture_snapshot();return
	if snapshot_mode=="factions":_refresh();await _capture_snapshot();return
	game.act(0,game.legal_actions(0)[0])
	if snapshot_mode=="initial":_refresh();await _capture_snapshot();return
	game.act(0,game.legal_actions(0)[0]);game.act(0,game.legal_actions(0)[0]);game.current=0;game.phase="main"
	for id in game.field(0):game.nodes[id].token=1
	if snapshot_mode!="setup":
		for _i in range(3):
			var autos=game.legal_actions(0).filter(func(a):return a.type=="auto")
			if not autos.is_empty():game.act(0,autos[0]);game.auto_used=false;game.nodes[game.root(0)].token=1
	selected=game.groups(0)[0];compact=snapshot_mode in ["mobile","mobile_detail"];_resize();_refresh()
	board.opening_view(compact)
	if snapshot_mode=="battle":
		var attacks=game.legal_actions(0).filter(func(a):return a.type=="attack")
		if not attacks.is_empty():game.act(0,attacks[0]);game.battle.responder=0;_refresh()
	if snapshot_mode in ["inspect","mobile_detail"]:_inspect("G024")
	await _capture_snapshot()

func _capture_snapshot() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(1.3).timeout
	var output="res://tests/snapshot_%s.png"%snapshot_mode
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot-output="):output=arg.trim_prefix("--snapshot-output=")
	if DisplayServer.get_name()!="headless":get_viewport().get_texture().get_image().save_png(output)
	get_tree().quit()

func _exit_tree() -> void:
	ai.shutdown()
	combat.reset()
	match_id+=1;_finish_presentation(false)
	board.reset_motion();window_access.reset()
	CardDB.finish_art_requests()
	for player in audio_pool:
		if is_instance_valid(player):player.stop();player.stream=null
	sounds.clear()

func _review_disaster(a: Dictionary) -> void:
	if window_access.browsing:return
	preview_action=a.duplicate(true);_clear(large_layer);_clear(hover_layer);_dim(large_layer,0.12)
	var extent=Vector2(minf(960,size.x-100),minf(640,size.y-120));var panel=_panel(large_layer,Rect2((size-extent)/2,extent))
	_drag_title(panel,game.title(a.id)+" → "+game.title(a.target),"disaster_preview")
	window_access.offer(panel,Vector2(-1,62))
	var v=game.wave.disaster_preview(a)
	_label("强度 %d"%v.strength,panel,38,TEAL).position=Vector2(30,100)
	_label("成功 %.1f%%   摧毁 %.1f%%"%[v.chance*100,v.destroy_chance*100],panel,28).position=Vector2(30,160)
	_paragraph("威力%d   修正%+d   基础防御%d   被动%d   防备%d"%[v.power,v.ability,v.base,v.defense,v.bonus_d],panel,Rect2(30,225,extent.x-60,55),22)
	_paragraph("行动 · "+game.title(a.payer)+"\n目标会在灾难开始时失去标记；法治保障可保护。\n忽略阵营、忠诚和位置。双方仍可响应。",panel,Rect2(30,300,extent.x-60,125),21)
	var col=_scroll_column(panel,Rect2(30,430,extent.x-60,extent.y-530));var row=HFlowContainer.new();col.add_child(row)
	for id in game.hands[0].plot:
		var context={"src":a.payer,"target":a.target,"mode":"destroy","disaster":a.id,"attacker":0,"defender":1,"paid":[a.payer]}
		if id not in game.locked and not game._combat_plot_actions(id,0,context).is_empty():_button(game.title(id),func():_inspect(id),row)
	_button("返回",func():preview_action={};_clear(large_layer),panel).position=Vector2(30,extent.y-80)
	_button("查看目标",func():_inspect(a.target),panel).position=Vector2(extent.x-400,extent.y-80)
	_button("发动灾难",func():preview_action={};_clear(large_layer);_do_action(0,a),panel,true).position=Vector2(extent.x-220,extent.y-80)

func _draw_deck_picker() -> void:
	var options=game.legal_actions(0).filter(func(a):return a.type=="research")
	_clear(large_layer);_dim(large_layer,0.35)
	var extent=Vector2(minf(650,size.x-100),390);var p=_panel(large_layer,Rect2((size-extent)/2,extent));p.name="DrawDeckPicker"
	_label("选择牌堆",p,30,GOLD).position=Vector2(28,22)
	_label("花主牌1行动 · 抽1张",p,21,TEAL).position=Vector2(28,78);window_access.offer(p)
	for i in 3:
		var deck=["group","resource","plot"][i];var choices=options.filter(func(a):return a.deck==deck)
		var caption={"group":"团体","resource":"资源","plot":"阴谋"}[deck]
		if choices.is_empty():caption+=" · "+("手牌已满" if deck=="resource" and not game.resources.can_draw(0) else "牌堆已空")
		var b=_button(caption,func():_do_action(0,choices[0]),p,true);b.position=Vector2(28+i*(extent.x-56)/3,142);b.size=Vector2((extent.x-76)/3,90);b.disabled=choices.is_empty()
	_button("返回",func():_clear(large_layer),p).position=Vector2(28,extent.y-78)

func _change_language(value: String) -> void:
	if busy or window_access.browsing or window_access.transitioning:return
	GameLocale.set_language(value);_save_settings()
	if game==null:_menu()
	else:
		var was_selected=selected
		_refresh(false);selected=was_selected
		if not interactions.reader_id.is_empty():
			var reader_history=interactions.reader_stack.duplicate()
			_clear(detail_layer);_inspect(interactions.reader_id,true);interactions.reader_stack=reader_history
	_settings()

func _close_settings() -> void:
	_clear(large_layer)
	if game!=null:
		if interactions.picker.active:interactions.step();return
		if not preview_action.is_empty():_review_action(preview_action);return
		_refresh()
	modal_open=false;_schedule_ai()

func _updates() -> void:
	if update_window!=null or busy:return
	update_window=UpdateWindow.new(self,updates);add_child(update_window)
	if updates.status in ["idle","offline","invalid"]:updates.check_updates()

func _sync_update_badge() -> void:
	if updates==null:return
	var badge=overlay.find_child("MenuUpdate",true,false)
	if badge==null:return
	var text="下载完成 · 应用更新" if updates.status=="ready" else ("发现新版本 · 查看" if updates.status in ["available","full"] else "检查更新")
	badge.text="v"+str(updates.current().get("version","?"))+" · "+GameLocale.text(text)

func _online_active() -> bool:return online!=null and online.started
func _opponent_name() -> String:return "对手" if _online_active() else "AI"

func _clear_board() -> void:
	combat.reset()
	for child in board.get_children():
		if child!=combat:board.remove_child(child);child.queue_free()
	board.cards.clear();board.positions.clear();board.targets.clear();board.collapsed.clear()

func _online_install(data: Dictionary,fresh: bool) -> void:
	if fresh or not game is RemoteState:
		ai.cancel_all();match_id+=1;_finish_presentation(false);window_access.reset();interactions.reset();board.reset_motion();thinking=false;forced_pending=false;panel_dragging=false
		_clear_board();board.initialized=false;floating_positions.clear();selected="";faction_page=0
		_clear(overlay);_clear(large_layer);_clear(detail_layer);_clear(hover_layer);game=RemoteState.new()
	game.install(data);board.visible=true;modal_open=false
	if game.phase=="over":notification.text=""
	if selected!="" and not game.nodes.has(selected) and selected not in game.hands[0].group and selected not in game.hands[0].plot and selected not in game.hands[0].resource:selected=""
	_refresh(false)

func _online_wait() -> void:
	if game==null:return
	if not detail_layer.get_children().is_empty():online.saved_reader=interactions.reader_id;_clear(detail_layer)
	window_access.reset();interactions.reset();action_candidates.clear();preview_action={};_clear(large_layer);_clear(overlay);_clear(hover_layer)
	modal_open=false;_set_busy(true)

func _online_prepare(message: Dictionary) -> void:
	if not message.get("plan",{}) is Dictionary or not message.plan.has("reveals"):
		online.network_lost();return
	var ticket=online.epoch;var transaction=int(message.tx)
	_online_wait();_online_install(message.state,false);_set_busy(true)
	if message.get("notice","")!="":_toast(message.notice)
	var plan=message.plan
	for reveal in plan.reveals:
		if not await _present_action(reveal.player,reveal.action):return
		if ticket!=online.epoch or transaction!=online.tx:return
	if not plan.result.is_empty() and not plan.result.get("cancelled",false):
		if not await _present_result(plan.result):return
		if ticket!=online.epoch or transaction!=online.tx:return
	if not await interactions.battle_cue(plan):return
	if ticket!=online.epoch or transaction!=online.tx:return
	for target in [plan.target,plan.get("other_target","")]:
		if target=="":continue
		if not await interactions.target_cue(plan.source,target):return
		if ticket!=online.epoch or transaction!=online.tx:return
	if not plan.moves.is_empty():
		if not await interactions.moves(plan.moves,plan):return
		if ticket!=online.epoch or transaction!=online.tx:return
	interactions.restore_sources();online.send({"op":"presented","tx":transaction})

func _online_commit(message: Dictionary) -> void:
	var ticket=online.epoch;var transaction=int(message.tx)
	_online_install(message.state,false);_set_busy(true)
	board.settlement_result=message.get("result",{});_refresh(false)
	if not await board.wait_for_settlement():return
	if ticket!=online.epoch or transaction!=online.tx:return
	online.send({"op":"settled","tx":transaction})
