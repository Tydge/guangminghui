class_name GameInteractions
extends Node
var host: WeakRef
var m:
	get:return host.get_ref()
var picker=ActionPicker.new()
var picker_page=0
var collection_page=0
var reader_id=""
var reader_stack: Array=[]
var dimmed: Array=[]
func _init(main) -> void:host=weakref(main)

func reset() -> void:
	picker.clear();reader_stack.clear();reader_id="";restore_sources()
func restore_sources() -> void:
	for view in dimmed:
		if is_instance_valid(view):view.modulate.a=1.0
	dimmed.clear()

func catalog(reset_page: bool=false) -> void:
	if reset_page:collection_page=0
	m.modal_open=true;m._clear(m.large_layer);m._dim(m.large_layer)
	var p=m._panel(m.large_layer,Rect2(Vector2(45,40),m.size-Vector2(90,80)));p.name="Catalog"
	m._label("卡牌图鉴",p,32,m.GOLD).position=Vector2(28,18)
	var tabs=HBoxContainer.new();tabs.position=Vector2(270,15);tabs.add_theme_constant_override("separation",12);p.add_child(tabs)
	for kind in ["faction","group","plot","resource"]:m._button({"faction":"光明会","group":"团体","plot":"阴谋","resource":"资源"}[kind]+" · %d"%CardDB.ids(kind).size(),func():m.collection_filter=kind;catalog(true),tabs,kind==m.collection_filter)
	m._button("关闭",func():m._clear(m.large_layer);m.modal_open=false;m._schedule_ai(),p).position=Vector2(p.size.x-135,15)
	var scroll=ScrollContainer.new();scroll.name="CatalogScroll";scroll.position=Vector2(28,85);scroll.size=p.size-Vector2(56,180);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;p.add_child(scroll)
	var grid=GridContainer.new();grid.name="CatalogGrid";grid.columns=maxi(1,int((p.size.x-70)/240));grid.add_theme_constant_override("h_separation",18);grid.add_theme_constant_override("v_separation",22);scroll.add_child(grid)
	var ids=CardDB.ids(m.collection_filter);var count=grid.columns*2;var pages=ceili(float(ids.size())/count);collection_page=clampi(collection_page,0,maxi(0,pages-1))
	for id in ids.slice(collection_page*count,(collection_page+1)*count):
		var v=CardView.new();v.configure(id);v.custom_minimum_size=Vector2(220,385);grid.add_child(v);v.selected.connect(m._inspect);v.inspected.connect(m._inspect)
	for id in ids.slice((collection_page+1)*count,(collection_page+2)*count):CardDB.request_art(id)
	var footer=HBoxContainer.new();footer.position=Vector2(28,p.size.y-75);footer.add_theme_constant_override("separation",16);p.add_child(footer)
	var previous=m._button("上一页",func():collection_page-=1;catalog(),footer);previous.disabled=collection_page==0
	m._label("%d / %d"%[collection_page+1,pages],footer,22,m.GOLD)
	var next=m._button("下一页",func():collection_page+=1;catalog(),footer);next.disabled=collection_page>=pages-1

func begin(options: Array) -> void:
	if options.is_empty():return
	picker.begin(options);picker_page=0;step()
func show_targets(options_to_show: Array) -> void:
	if not picker.active:picker.begin(options_to_show)
	options()
func group_actions(actions: Array) -> Array:
	var groups: Dictionary={}
	for a in actions:
		var key=JSON.stringify([a.type,a.get("src",""),a.get("id","")])
		if not groups.has(key):groups[key]={"action":a,"options":[]}
		groups[key].options.append(a)
	return groups.values()
func cancel() -> void:
	picker.clear();m.action_candidates.clear();m._clear(m.large_layer);m._refresh();m._schedule_ai()
func back() -> void:
	if picker.back():picker_page=0;step()
	else:cancel()
func pick(key: String,value) -> void:
	picker.select(key,value);picker_page=0;step()
func label_for(key: String) -> String:
	var first=picker.actions[0]
	if key=="target" and first.get("src","") in ["G138","G168"]:return "选择弃牌费用"
	if key=="target" and first.get("src","") in ["G151","E22"]:return "选择洗回的资源"
	if key=="resource_fee" or (key=="other" and first.get("src","")=="G159") or (key=="target" and first.get("id","")=="P65"):return "选择报废的资源"
	if key=="target" and first.get("id","")=="P66":return "选择部署的资源"
	if key=="stake":return "庄家筹码 · 支援方式"
	if key=="other" and picker.actions[0].get("id","")=="P60":return "选择己方交换资源"
	if key=="supply":return "选择部署费用"
	var labels={"replace":"资源已满 · 选择报废替换的资源","target":"选择目标","leader":"选择带头团体","src":"选择能力或行动来源","parent":"选择新的上级","payer":"选择支付行动的团体","other":"选择另一团体","attachment":"选择要移除的附着","fee":"选择弃牌费用","plot_fee":"选择弃牌费用","group_fee":"选择团体费用","tag":"选择新增标签","use_plan":"选择掷骰方式","training":"自律训练 · 进攻方式","algorithm":"算法时代 · 支援方式","amplify":"弹性扩容 · 支援方式","solo":"孤军破袭 · 进攻方式","star":"星象助阵 · 支援方式"}
	if key.begins_with("payers:"):return "选择第%d个支付行动的团体"%(int(key.get_slice(":",1))+1)
	if key=="target" and (picker.actions[0].type=="resource" or picker.actions[0].get("id","") in ResourceRules.PLOTS):return "选择目标资源" if picker.actions[0].get("src","")=="G093" or picker.actions[0].get("id","") in ["P56","P58","P59","P60"] else "选择目标团体"
	if key=="target" and picker.actions[0].get("id","") in ["P21","P23","P24","P25"]:return "选择支付行动的团体"
	return labels.get(key,"选择操作")
func support_value(options: Array) -> String:
	var values: Array=[]
	for a in options:
		var value="%s +%d"%[a.get("basis","支援"),a.get("power",0)]
		if value not in values:values.append(value)
	return " / ".join(values)
func mode_title(key: String,value: bool) -> String:
	var options=picker.actions.filter(func(a):return a.get(key,false)==value)
	# Later optional bonuses have their own step; quote the unmodified support here.
	var plain=options.filter(func(a):return (key=="amplify" or picker.chosen.has("amplify") or not a.get("amplify",false)) and (key=="star" or not a.get("star",false)))
	var strength=support_value(plain if not plain.is_empty() else options)
	match key:
		"supply":return "矿产供给 · 弃1张团体" if value else "花主牌1行动"
		"algorithm":return ("算法时代 · "+strength+"（本战限1次）") if value else "普通支援 · "+strength
		"amplify":return ("弹性扩容 · "+strength+" · 另弃1张牌") if value else "普通支援 · "+strength
		"stake":return ("庄家筹码 · "+strength+" · 另弃1张阴谋") if value else "普通支援 · "+strength
		"star":return ("星象助阵 · "+strength+"，骰1–3再+2") if value else "普通支援 · "+strength
		"training":return "消耗1训练 · 攻击强度+2" if value else "不使用训练"
		"solo":return "孤军破袭 · 忽略位置，禁用进攻支援" if value else "普通摧毁 · 可接受进攻支援"
		"use_plan":
			var dice=m.game.wave.plans.get(m.game.owner(picker.actions[0].src),[])
			return "采用预案 · %d＋%d＝%d"%[dice[0],dice[1],dice[0]+dice[1]] if value and dice.size()==2 else "正常掷骰 · 两颗骰子"
	return "启用" if value else "不启用"
func mode_context() -> String:
	var a=picker.actions[0];var source=m.game.title(a.get("src",""))
	if a.type=="deploy":return source+" · 部署到主牌旁"
	if a.type=="support":return source+" · 支援"+("进攻" if m.game.owner(a.src)==m.game.battle.attacker else "防守")+" · 消耗1行动"
	return source+" → "+m.game.title(a.get("target",""))
func step() -> void:
	m._clear(m.large_layer);m._clear(m.hover_layer);m._clear(m.overlay);m.action_candidates.clear()
	var key=picker.next_key()
	if key=="":confirm();return
	var values=picker.values(key)
	if values.all(func(v):return v is String and m.game.nodes.has(v)):
		m._target(picker.actions,key,label_for(key));return
	options()
func options() -> void:
	var key=picker.next_key()
	if key=="":confirm();return
	m._clear(m.large_layer);m._dim(m.large_layer,0.55)
	var mode=key in ActionPicker.MODE_KEYS
	var extent=Vector2(minf(760 if mode else 1100,m.size.x-100),minf(400 if mode else 690,m.size.y-90));var p=m._panel(m.large_layer,Rect2((m.size-extent)/2,extent));p.name="StepPicker"
	var heading=m._label(label_for(key),p,29,m.GOLD);heading.position=Vector2(28,22);heading.size.x=extent.x-230;heading.clip_text=true
	if mode:m._paragraph(mode_context(),p,Rect2(28,80,extent.x-56,52),21,m.TEAL)
	m.window_access.offer(p)
	var values=picker.values(key);var per_page=8;var pages=ceili(values.size()/float(per_page));picker_page=clampi(picker_page,0,maxi(0,pages-1))
	var top=140 if mode else 80
	var col=m._scroll_column(p,Rect2(28,top,extent.x-56,extent.y-top-100))
	for value in values.slice(picker_page*per_page,(picker_page+1)*per_page):
		var row=HBoxContainer.new();row.add_theme_constant_override("separation",10);col.add_child(row)
		var card=value is String and CardDB.get_card(value).has("kind")
		if card:
			var v=CardView.new();v.configure(value,m.game);v.custom_minimum_size=Vector2(76,116);row.add_child(v);v.selected.connect(m._inspect);v.inspected.connect(m._inspect)
		var title=m.game.title(value) if card else (mode_title(key,value) if value is bool else str(value))
		var choose=m._button(title,func():pick(key,value),row,true);choose.name="ModeEnabled" if value is bool and value else ("ModeDefault" if value is bool else "ChooseOption");choose.custom_minimum_size=Vector2(230,56 if mode else 50);choose.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		if mode:choose.size_flags_horizontal=Control.SIZE_EXPAND_FILL;choose.alignment=HORIZONTAL_ALIGNMENT_LEFT
		if card:m._button("查看",func():m._inspect(value),row).size_flags_vertical=Control.SIZE_SHRINK_CENTER
	m._button("上一步",back,p).position=Vector2(28,extent.y-76)
	m._button("取消",cancel,p).position=Vector2(150,extent.y-76)
	if pages>1:
		var prev=m._button("上一页",func():picker_page-=1;options(),p);prev.position=Vector2(extent.x-360,extent.y-76);prev.disabled=picker_page==0
		m._label("%d/%d"%[picker_page+1,pages],p,20,m.GOLD).position=Vector2(extent.x-242,extent.y-66)
		var next=m._button("下一页",func():picker_page+=1;options(),p);next.position=Vector2(extent.x-156,extent.y-76);next.disabled=picker_page==pages-1
func confirm() -> void:
	var a=picker.actions[0]
	if a.type=="attack" or (a.type=="ability" and a.src=="G096") or (a.type=="plot" and a.id in GameState.WaveRules.DISASTERS):
		picker.clear();m._review_action(a);return
	m._clear(m.large_layer);m._dim(m.large_layer,0.2)
	var extent=Vector2(minf(720,m.size.x-100),370);var p=m._panel(m.large_layer,Rect2((m.size-extent)/2,extent));p.name="ActionConfirmation"
	var source=a.get("id",a.get("src",""));var heading=m._label(m.game.title(source),p,30,m.GOLD);heading.position=Vector2(28,24);heading.size.x=extent.x-235;heading.clip_text=true;heading.tooltip_text=GameLocale.text(heading.text)
	m.window_access.offer(p)
	var lines: Array=[]
	if a.type in ["deploy","resource","research"]:lines.append(a.label)
	if a.type=="ability" and a.get("free",false):lines.append("不消耗行动标记")
	if a.type=="deploy":lines.append("每回合可部署1次，与自动接管分别限次。")
	if a.type=="support":
		lines.append(("支援进攻" if m.game.owner(a.src)==m.game.battle.attacker else "支援防守")+" · "+support_value([a]))
		if a.get("algorithm",false):lines.append("算法时代 · 本战限1次")
		if a.get("amplify",false):lines.append("弹性扩容 · 基础支援翻倍")
		if a.get("star",false):lines.append("星象助阵 · 骰1–3再+2")
		lines.append("消耗该团体1行动")
	for key in ["replace","target","parent","payer","other","fee","plot_fee","group_fee","attachment","tag"]:
		if a.get(key,"")=="":continue
		var field_name={"replace":"报废替换","target":"目标","parent":"移至","payer":"行动","other":"另一团体","plot_fee":"弃牌","group_fee":"弃牌","fee":"弃牌","attachment":"附着","tag":"新增"}[key]
		if key=="other" and a.get("src","")=="G159":field_name="报废资源"
		lines.append(field_name+" · "+m.game.title(a[key]))
	if not a.get("payers",[]).is_empty():lines.append("行动 · "+" / ".join(a.payers.map(func(id):return m.game.title(id))))
	if lines.is_empty():lines.append(a.label)
	m._paragraph("\n".join(lines),p,Rect2(28,88,extent.x-56,182),23)
	m._button("上一步",back,p).position=Vector2(28,extent.y-76)
	m._button("取消",cancel,p).position=Vector2(150,extent.y-76)
	var commit=m._button("确认",func():picker.clear();m.action_candidates.clear();m._do_action(0,a),p,true);commit.position=Vector2(extent.x-168,extent.y-76);commit.size.x=140

func attachment_buttons(id: String,col: Control) -> void:
	if m.game==null or not m.game.nodes.has(id) or m.game.nodes[id].attached.is_empty():return
	var flow=HFlowContainer.new();flow.name="AttachedCards";flow.size_flags_horizontal=Control.SIZE_EXPAND_FILL;flow.add_theme_constant_override("h_separation",8);flow.add_theme_constant_override("v_separation",8);col.add_child(flow)
	for attachment in m.game.nodes[id].attached:
		var b=m._button(CardDB.name_of(attachment)+" · 查看",func():open_attached(attachment),flow);b.tooltip_text=GameLocale.text(CardDB.plot_text(CardDB.get_card(attachment)))
func open_attached(id: String) -> void:
	var scroll=m.detail_layer.find_child("ReaderScroll",true,false)
	reader_stack.append({"id":reader_id,"scroll":scroll.scroll_vertical if scroll!=null else 0})
	m._inspect(id,true)
func close_reader() -> bool:
	if reader_stack.is_empty():return false
	var frame=reader_stack.pop_back();m._inspect(frame.id,true)
	var scroll=m.detail_layer.find_child("ReaderScroll",true,false)
	if scroll!=null:scroll.set_deferred("scroll_vertical",frame.scroll)
	return true

func visible_card(id: String) -> Control:
	for layer in [m.hand_layer,m.overlay]:
		for view in layer.find_children("*","Control",true,false):
			if view is CardView and view.id==id and view.is_visible_in_tree():return view
	if m.board.cards.has(id) and m.board.cards[id].is_visible_in_tree():return m.board.cards[id]
	return null
func anchor(place: String,p: int,kind: String,id: String="",target: String="") -> Rect2:
	var area=Vector2(94,142);var center=m.size*0.5
	if place in ["resource_left","resource_right"]:
		var root_view=m.board.cards.get(m.game.root(p))
		if root_view!=null:
			area=m.board.card_size*m.board.zoom
			center=root_view.get_global_rect().get_center()+Vector2((-1 if place=="resource_left" else 1)*(m.board.card_size.x+32)*m.board.zoom,0)
		return Rect2(center-area*0.5,area)
	if place in ["board","attached"]:
		var view=visible_card(target if target!="" else id)
		if view!=null:return view.get_global_rect()
	if place=="hand":
		var view=visible_card(id)
		if view!=null:return view.get_global_rect()
		center=Vector2(m.size.x*0.36,m.size.y-90) if p==0 else Vector2(m.size.x*0.72,110)
	elif place in ["deck","discard","scrap"]:center=Vector2(m.size.x-400+["group","resource","plot"].find(kind)*140,122 if place=="deck" else 210)
	elif place=="choice":center=Vector2(m.size.x*0.5,m.size.y*0.45)
	return Rect2(center-area*0.5,area)
func known(id: String) -> bool:
	return id in m.game.resource_candidates[0] or m.game.nodes.has(id) or id in m.game.hands[0].group or id in m.game.hands[0].plot or id in m.game.hands[0].resource or id in m.game.exposed or id in m.game.discards.group or id in m.game.discards.plot or id in m.game.battle.get("spent",[]) or m.game.world==id or m.game.pending_plot.get("id","")==id
func flight(id: String,kind: String,show_face: bool) -> Control:
	var view=Panel.new();view.name="MovingCard";view.size=Vector2(94,142);view.mouse_filter=Control.MOUSE_FILTER_IGNORE;view.add_theme_stylebox_override("panel",m._style(Color("142c2e"),m.GOLD,2));m.presentation_layer.add_child(view)
	if show_face:
		var face=CardView.new();face.configure(id,m.game);face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);face.mouse_filter=Control.MOUSE_FILTER_IGNORE;view.add_child(face)
	else:
		var back=TextureRect.new();back.texture=load("res://assets/ui/%s_back.webp"%("group" if kind=="resource" else kind));back.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;back.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);back.mouse_filter=Control.MOUSE_FILTER_IGNORE;view.add_child(back)
	return view
func arc(view: Control,start: Rect2,finish: Rect2,t: float,lift: float) -> void:
	view.position=start.position.lerp(finish.position,t)-Vector2(0,sin(t*PI)*lift)
	view.scale=start.size.lerp(finish.size,t)/view.size
func target_cue(id: String,target: String) -> bool:
	m.board.reveal([target]);m.board.sync(m.game)
	var view=m.board.cards.get(target)
	if view==null:return true
	var rect=view.get_global_rect();var visible=m.board.get_global_rect().grow(-35)
	if not visible.encloses(rect):
		m.presenting=true;m._clear(m.presentation_layer);m.board.camera_animating=false
		var desired=m.board.size*0.5-m.board.targets[target]*m.board.zoom
		m.presentation_tween=m.create_tween();m.presentation_tween.tween_property(m.board,"pan",desired,(0.08 if m.reduced_motion else 0.30)*m.presentation_time_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		m.presentation_tween.finished.connect(func():m._finish_presentation(true),CONNECT_ONE_SHOT)
		if not await m.presentation_finished:return false
		m.board._process(0)
	m.presenting=true;m._clear(m.presentation_layer)
	var start=Rect2(m.size*0.5-Vector2(62,94),Vector2(124,188));var finish=view.get_global_rect()
	var card=flight(id,"plot",true)
	arc(card,start,finish,0,0);card.modulate.a=0
	var ring=Panel.new();ring.name="TargetHighlight";ring.mouse_filter=Control.MOUSE_FILTER_IGNORE;ring.position=finish.position-Vector2(5,5);ring.size=finish.size+Vector2(10,10);ring.add_theme_stylebox_override("panel",m._style(Color(0.2,0.65,0.55,0.14),m.TEAL,3));m.presentation_layer.add_child(ring)
	m._label("→ "+m.game.title(target),m.presentation_layer,23,m.GOLD).position=Vector2(clampf(finish.position.x,20,m.size.x-350),maxf(160,finish.position.y-38))
	m.presentation_tween=m.create_tween();m.presentation_tween.tween_property(card,"modulate:a",1.0,0.08*m.presentation_time_scale);m.presentation_tween.tween_method(func(t):arc(card,start,finish,t,35),0.0,1.0,(0.20 if m.reduced_motion else 0.48)*m.presentation_time_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	m.presentation_tween.tween_property(card,"modulate:a",0.0,0.12*m.presentation_time_scale);m.presentation_tween.parallel().tween_property(ring,"modulate:a",0.0,0.12*m.presentation_time_scale)
	m.presentation_tween.finished.connect(func():m._finish_presentation(true),CONNECT_ONE_SHOT)
	return await m.presentation_finished
func moves(events: Array) -> bool:
	if events.is_empty():return true
	m.presenting=true;m._clear(m.presentation_layer)
	var caption=m._label("",m.presentation_layer,24,m.GOLD);caption.position=Vector2(35,m.size.y-255)
	m.presentation_tween=m.create_tween().set_parallel(true)
	var delay=0.0;var signature="";var index=0;var last_end=0.0
	for event in events:
		var group=event.from+":"+event.to+":"+str(event.player)+":"+event.kind
		if group!=signature:delay=last_end+0.05 if signature!="" else 0.0;index=0;signature=group
		var start=anchor(event.from,event.get("from_player",event.player),event.kind,event.id,event.get("from_target",""));var finish=anchor(event.to,event.player,event.kind,event.id)
		var source=visible_card(event.id)
		if event.from in ["hand","board"] and source!=null and source not in dimmed:dimmed.append(source);source.modulate.a=0.0 if event.from=="board" else 0.12
		var show_face=(known(event.id) and event.from!="deck" and (event.from!="choice" or event.id in m.game.resource_candidates[0])) or event.to in ["resource_left","resource_right"]
		var view=flight(event.id,event.kind,show_face);view.modulate.a=0;arc(view,start,finish,0,0)
		var at=(delay+index*0.07)*m.presentation_time_scale;var duration=(0.22 if m.reduced_motion else 0.42)*m.presentation_time_scale
		var verb="摸牌" if event.from=="deck" else (("报废资源" if event.to=="scrap" else "弃牌") if event.to in ["discard","scrap"] else ("放回牌堆" if event.to=="deck" else "取得卡牌"))
		m.presentation_tween.tween_callback(func():caption.text=GameLocale.text(("你" if event.player==0 else ("AI" if event.player==1 else ""))+" · "+GameLocale.text(verb));view.modulate.a=1.0;m._sound("card")).set_delay(at)
		m.presentation_tween.tween_method(func(t):arc(view,start,finish,t,22),0.0,1.0,duration).set_delay(at).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		m.presentation_tween.tween_property(view,"modulate:a",0.0,0.08*m.presentation_time_scale).set_delay(at+duration)
		last_end=delay+index*0.07+(0.22 if m.reduced_motion else 0.42)+0.08;index+=1
	m.presentation_tween.finished.connect(func():m._finish_presentation(true),CONNECT_ONE_SHOT)
	return await m.presentation_finished

func prepare_board(plan: Dictionary) -> bool:
	var ids=plan.get("camera_ids",[])
	if ids.is_empty() or m.game.phase.begins_with("setup"):return true
	var board=m.board
	board.reveal(ids)
	# Reveal future parents too, without constructing a future public card on the live board.
	for id in ids:
		var parent=plan.board_after.get(id,{}).get("parent","")
		board.reveal([parent]);board.collapsed.erase(parent)
	board.sync(m.game)
	if not await board.wait_for_settlement():return false
	var before=BoardView.layout_nodes(plan.board_before,board.card_size,board.collapsed)
	var after=BoardView.layout_nodes(plan.board_after,board.card_size,board.collapsed)
	var bounds=Rect2();var first=true
	for id in ids:
		for positions in [before,after]:
			if not positions.has(id):continue
			var rect=Rect2(positions[id]-board.card_size/2,board.card_size)
			bounds=rect if first else bounds.merge(rect);first=false
	if first:return true
	board.camera_animating=false
	var safe=Rect2(Vector2(40,40),board.size-Vector2(80,80))
	var screen=Rect2(bounds.position*board.zoom+board.pan,bounds.size*board.zoom)
	# Ignore subpixel rounding so consecutive effects do not nudge the same framing.
	if safe.grow(1.0).encloses(screen):return true
	var zoom=minf(board.zoom,minf(safe.size.x/bounds.size.x,safe.size.y/bounds.size.y))
	zoom=clampf(zoom,0.10,1.8)
	var pan=board.size/2-bounds.get_center()*zoom
	m.presenting=true;m._clear(m.presentation_layer)
	m.presentation_tween=m.create_tween().set_parallel(true)
	var duration=(0.08 if m.reduced_motion else 0.32)*m.presentation_time_scale
	m.presentation_tween.tween_property(board,"pan",pan,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	m.presentation_tween.tween_property(board,"zoom",zoom,duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	m.presentation_tween.finished.connect(func():m._finish_presentation(true),CONNECT_ONE_SHOT)
	if not await m.presentation_finished:return false
	board._process(0)
	return true
