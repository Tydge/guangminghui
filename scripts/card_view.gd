class_name CardView
extends Control

signal selected(id: String)
signal inspected(id: String)
signal hovered(id: String, showing: bool)
signal wheel_zoom(factor: float, at: Vector2)

var id = ""
var definition: Dictionary = {}
var state: GameState
var full = false
var chosen = false
var legal = false
var enemy = false
var face_down = false
var collapsed_count=0
var font: Font
var art: Texture2D
var pressed_at = Vector2.ZERO
var press_time = -1.0
var hover_time = -1.0
var moved = false
var long_fired = false
var hover_fired = false

func _ready() -> void:
	mouse_entered.connect(func():hover_time=0.0)
	mouse_exited.connect(func():hover_time=-1.0;hover_fired=false;hovered.emit(id,false))
	if font==null:
		font=CardDB.readable_font()

func configure(uid: String,game: GameState=null,large: bool=false) -> void:
	id=uid;state=game;full=large
	definition=game.card(uid) if game!=null else CardDB.get_card(uid)
	art=CardDB.art(definition.get("id",uid),true)
	queue_redraw()

func _process(delta: float) -> void:
	if art==null and not definition.is_empty() and not face_down:
		art=CardDB.art(definition.id,true)
		if art!=null:queue_redraw()
	if press_time>=0:
		press_time+=delta
		if press_time>=0.48 and not moved and not long_fired:
			long_fired=true;hover_time=-1;inspected.emit(id)
	if hover_time>=0 and not full:
		hover_time+=delta
		if hover_time>=0.5 and not hover_fired and press_time<0:
			hover_fired=true;hovered.emit(id,true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP or event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			# Only board cards own the wheel; readers and catalog cards pass it to scrolling parents.
			if wheel_zoom.get_connections().is_empty():return
			if event.pressed:wheel_zoom.emit(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12,get_global_mouse_position())
			accept_event();return
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:pressed_at=event.global_position;press_time=0;moved=false;long_fired=false
			else:
				if press_time>=0 and not moved and not long_fired:selected.emit(id)
				press_time=-1
			accept_event()
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:inspected.emit(id);accept_event()
	elif event is InputEventMouseMotion and press_time>=0:
		if event.global_position.distance_to(pressed_at)>8:moved=true

func _text(text: String,at: Vector2,font_size: int,color: Color,width: float=-1) -> void:
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,color)

static func art_destination(image_size: Vector2,frame: Rect2) -> Rect2:
	var factor=minf(frame.size.x/maxf(1.0,image_size.x),frame.size.y/maxf(1.0,image_size.y))
	var fitted=image_size*factor
	return Rect2(frame.position+(frame.size-fitted)*0.5,fitted)

static func art_frame(card_size: Vector2,margin: float) -> Rect2:
	var side=maxf(1.0,card_size.x-margin*2)
	if card_size.x>=90 and card_size.x<200:
		# Reserve three readable metadata lines without making board/hand cards taller.
		var sizes=[14,12,12] if card_size.x>=120 else [12,11,11]
		var text_height=3.0;var card_font=CardDB.readable_font()
		for fs in sizes:text_height+=ceilf(card_font.get_height(fs))
		side=maxf(1.0,minf(side,card_size.y-margin*2-8-text_height))
	return Rect2(Vector2((card_size.x-side)/2,margin),Vector2.ONE*side)

func _draw() -> void:
	if definition.is_empty():return
	var rect=Rect2(Vector2.ZERO,size)
	var paper=Color("e6d9b8");var ink=Color("182d30");var gold=Color("c6a86c")
	var style=StyleBoxFlat.new();style.bg_color=Color("102a2d");style.border_color=Color("eece86") if chosen else (Color("62dcc2") if legal else (Color("ad7770") if enemy else gold));style.set_border_width_all(3 if chosen or legal else 1);style.set_corner_radius_all(8);style.shadow_color=Color(0,0,0,0.5);style.shadow_size=8;style.shadow_offset=Vector2(0,4)
	draw_style_box(style,rect)
	if face_down:
		for i in range(3):draw_arc(size*0.5,22+i*7,0,TAU,48,gold,1,true)
		_text("◆",size*0.5+Vector2(-8,5),22,gold)
		return
	var margin=8.0 if not full else 14.0
	var summary=not full and size.x>=200 and size.y>=300
	# One shared card structure: square artwork, followed by a separate text panel.
	var art_rect=art_frame(size,margin)
	var art_h=art_rect.size.y
	if art!=null:
		draw_texture_rect(art,art_destination(art.get_size(),art_rect),false)
	else:draw_rect(art_rect,Color("245455"))
	var info=Rect2(margin,art_h+margin,size.x-margin*2,size.y-art_h-margin*2)
	draw_rect(info,paper)
	for run in text_layout():
		draw_multiline_string(font,run.rect.position+Vector2(0,font.get_ascent(run.fs)),run.text,HORIZONTAL_ALIGNMENT_LEFT,run.rect.size.x,run.fs,-1,run.color)
	if state!=null and state.nodes.has(id) and (definition.kind!="resource" or definition.action):
		var n=state.nodes[id]
		var action_color=Color("70e2c7") if state.token(id) else Color("41514a")
		if n.get("devastated",false):draw_rect(Rect2(6,32,36,23),Color("7d3931"));_text("Dev" if GameLocale.english() else "灾",Vector2(12,49),15,Color("ffe1bf"))
		elif n.get("prepared",false):draw_rect(Rect2(6,32,36,23),Color("205b56"));_text("Prep" if GameLocale.english() else "备",Vector2(10,49),12 if GameLocale.english() else 15,Color("9affe1"))
		draw_circle(Vector2(size.x-14,14),7,action_color)
		if state.action_limit(id)>1:_text(str(n.token),Vector2(size.x-18,18),11,Color("142b29"))
		draw_arc(Vector2(size.x-14,14),9,0,TAU,24,gold,1,true)
		var slots=state.stat(id,"slots");var occupied=state.children(id).size()
		for i in slots:draw_circle(Vector2(size.x/2.0+(i-(slots-1)/2.0)*12,size.y-5),3,Color("ddbd78") if i<occupied else Color("455b54"))
		if not n.attached.is_empty():_text("◆".repeat(n.attached.size()),Vector2(9,23),12,gold)
		if n.get("vampire",false) or n.get("flip",false):_text(GameLocale.text("转化"),Vector2(9,art_h+2),11,Color("f6c68e"))
		if collapsed_count>0:
			draw_rect(Rect2(6,6,45,23),Color("173436"));_text("＋%d"%collapsed_count,Vector2(9,23),13,gold)
	if state!=null and definition.kind=="resource" and state.nodes.has(id) and not state.resources.ready(id):
		draw_rect(Rect2(6,6,58,23),Color("693b37"));_text(GameLocale.text("失效"),Vector2(9,23),12,Color("f6d6a0"))
	if state!=null and id in state.failed_recruits:
		draw_rect(Rect2(6,6,58,23),Color("693b37"));_text("Recruit" if GameLocale.english() else "待招募",Vector2(9,23),11,Color("f6d6a0"))

func text_layout() -> Array:
	if definition.is_empty():return []
	if font==null:font=CardDB.readable_font()
	var margin=14.0 if full else 8.0
	var summary=not full and size.x>=200 and size.y>=300
	var small=not full and not summary
	var readable_small=small and size.x>=90 and size.x<200
	var board_small=readable_small and size.x>=120
	var rows: Array=[];var ink=Color("182d30");var muted=Color("655d42");var teal=Color("548082")
	rows.append({"text":definition.name,"fs":22 if full else (16 if summary else (14 if board_small else 12)),"color":ink})
	if full and not GameLocale.english():rows.append({"text":definition.en,"fs":13,"color":muted})
	if definition.kind not in ["plot","resource"]:
		var stats: Array=[]
		for key in ["p","gp","r","slots"]:stats.append(state.stat(id,key) if state!=null and state.nodes.has(id) else definition[key])
		var line="P%d / GP%d  "%[stats[0],stats[1]]+("主牌" if definition.kind=="faction" else "R%d"%stats[2])
		if readable_small:line="P%d GP%d "%[stats[0],stats[1]]+("主牌" if definition.kind=="faction" else "R%d"%stats[2])
		if GameLocale.english() and small and definition.kind=="faction":line="P%d GP%d"%[stats[0],stats[1]]
		if not small:line+="  槽%d"%stats[3]
		rows.append({"text":line,"fs":17 if full else (12 if summary or board_small else (11 if readable_small else 9)),"color":ink})
	var align=state.alignments(id) if state!=null else definition.align
	var trait_text=(definition.category+" · "+definition.mode if definition.kind=="resource" else definition.category) if definition.kind in ["plot","resource"] else " · ".join(align)
	if readable_small and not board_small and definition.kind not in ["plot","resource"]:trait_text=" ".join(align)
	if GameLocale.english() and small and definition.kind not in ["plot","resource"]:trait_text=GameLocale.alignments(align,not board_small)
	if trait_text!="":rows.append({"text":trait_text,"fs":14 if full else (12 if board_small else (11 if summary or readable_small else 8)),"color":ink if not full else muted})
	if not small:
		var current_tags=state.tags(id) if state!=null else definition.tags
		if not current_tags.is_empty() and (definition.kind!="resource" or current_tags!=[definition.category]):rows.append({"text":" / ".join(current_tags),"fs":13 if full else 11,"color":teal})
		if full and state!=null and state.nodes.has(id) and not state.is_root(id) and definition.kind!="resource":rows.append({"text":"忠诚 +%d   位置 +%d"%[state.loyalty_defense(id),state.position_defense(id)],"fs":13,"color":teal})
	var effect=definition.effect if definition.kind!="plot" else CardDB.plot_text(definition)
	if definition.kind=="faction":effect=effect+"\n胜利 · "+definition.get("goal","") if full else "胜利 · "+definition.get("goal","")+"\n"+effect
	if state!=null and state.nodes.has(id):
		var n=state.nodes[id];var flags: Array=[]
		if not n.attached.is_empty():flags.append("附着 · "+" / ".join(n.attached.map(func(k):return CardDB.name_of(k))))
		if n.get("devastated",false):flags.append("受灾 · P/GP减半")
		if n.get("prepared",false):flags.append("防备+4")
		if n.get("pacified",false):flags.append("化干戈")
		if n.get("silenced",false):flags.append("能力失效")
		if n.get("pr_crisis",false):flags.append("公关GP 0")
		if n.get("battery_power",0)>0:flags.append("电池P+4")
		if id=="G088":flags.append("训练%d"%n.get("training",0))
		if state.used.has(id):flags.append("能力已用")
		if state.recharged.has(id):flags.append("额外恢复已用")
		if state.captured.has(id):flags.append("本回合不能补标记")
		if n.get("debt",false):flags.append("负债：下次不补标记")
		if n.get("ad_gp",0)>0:flags.append("广告GP+%d"%n.ad_gp)
		if n.get("compute",false):flags.append("算力GP=P")
		if "P44" in n.attached:flags.append("保镖保护")
		if "P45" in n.attached:flags.append("监管GP 0")
		if not flags.is_empty():effect+="\n"+" · ".join(flags)
	var top=art_frame(size,margin).end.y+3
	var inset=3.0 if readable_small else 5.0
	var area=Rect2(margin+inset,top,size.x-2*margin-inset*2,maxf(0,size.y-margin-5-top))
	for row in rows:
		row.text=GameLocale.text(row.text)
		if GameLocale.english() and not small:row.wrap=true
	return CardTextLayout.build(font,area,rows,GameLocale.text(effect) if not small else "",17 if full else 13,small)
