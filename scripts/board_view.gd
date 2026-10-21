class_name BoardView
extends Control

signal card_selected(id: String)
signal card_inspected(id: String)
signal card_hovered(id: String,showing: bool)
signal settlement_finished(completed: bool)

var game: GameState
var cards: Dictionary={}
var targets: Dictionary={}
var positions: Dictionary={}
var card_size=Vector2(138,192)
var zoom=0.9
var pan=Vector2.ZERO
var focus_player=0
var selected_id=""
var legal_ids: Array=[]
var drag=false
var fingers: Dictionary={}
var touch_distance=0.0
var camera_target=Vector2.ZERO
var zoom_target=0.9
var camera_animating=false
var reduced_motion=false
var initialized=false
var collapsed: Dictionary={}
var interaction_enabled=true
var input_blocked_at: Callable
var motion_time_scale=1.0
var visual_tweens: Array=[]
var settlement_result: Dictionary={}
var settling=false

func track_motion(tween: Tween) -> Tween:
	visual_tweens.append(tween)
	tween.finished.connect(func():visual_tweens.erase(tween),CONNECT_ONE_SHOT)
	return tween
func reset_motion() -> void:
	for tween in visual_tweens:
		if tween.is_valid():tween.kill()
	visual_tweens.clear()
	settlement_result={}
	if settling:settling=false;settlement_finished.emit(false)
func is_settled() -> bool:
	if not visual_tweens.is_empty():return false
	for id in cards:
		if positions[id].distance_to(targets[id])*zoom>0.5:return false
	return true
func wait_for_settlement() -> bool:
	if is_settled():return true
	settling=true
	return await settlement_finished

func _ready() -> void:
	clip_contents=true;mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(func():if not initialized:fit_all())

func sync(g: GameState) -> void:
	game=g
	var outcome=g.last_event if settlement_result.is_empty() else settlement_result
	for id in g.nodes:
		if not cards.has(id):reveal([id])
	for id in cards.keys():
		if not g.nodes.has(id):
			var fading=cards[id];cards.erase(id);positions.erase(id)
			# Resource departures already land in the scrap pile during ActionFlow.
			if fading.definition.kind=="resource":fading.queue_free();continue
			var tween=track_motion(create_tween().set_parallel(true))
			var duration=(0.10 if reduced_motion else 0.5)*motion_time_scale
			if id==outcome.get("target","") and outcome.get("mode","")=="destroy" and not outcome.get("rescued",false):
				tween.tween_property(fading,"modulate",Color(1.0,0.3,0.18,0.0),duration);tween.tween_property(fading,"scale",fading.scale*0.75,duration)
			else:
				tween.tween_property(fading,"position",Vector2(size.x-35,-130) if fading.enemy else Vector2(45,size.y+50),duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT);tween.tween_property(fading,"modulate:a",0.0,duration)
			tween.chain().tween_callback(fading.queue_free)
	var left_width=maxf(_width(g.root(0)),card_size.x*3+96);var right_width=maxf(_width(g.root(1)),card_size.x*3+96)
	_layout(g.root(0),Vector2(left_width/2,0))
	_layout(g.root(1),Vector2(left_width+240+right_width/2,0))
	for p in [0,1]:
		if targets.has(g.root(p)):
			for id in g.resources.field(p):targets[id]=targets[g.root(p)]+Vector2((-1 if g.nodes[id].resource_slot==0 else 1)*(card_size.x+32),0)
	for id in g.nodes:
		if not cards.has(id):
			var view=CardView.new();view.configure(id,g);view.size=card_size;add_child(view)
			view.selected.connect(func(k):card_selected.emit(k));view.inspected.connect(func(k):card_inspected.emit(k));view.hovered.connect(func(k,showing):card_hovered.emit(k,showing));view.wheel_zoom.connect(_wheel)
			cards[id]=view;positions[id]=targets[id]+Vector2(0,100);view.modulate.a=0
			if g.card(id).kind=="resource":positions[id]=targets[id];view.modulate.a=1
			else:track_motion(create_tween()).tween_property(view,"modulate:a",1.0,0.3*motion_time_scale)
		cards[id].visible=not hidden_by_collapse(id)
		cards[id].collapsed_count=g.subtree(id).size()-1 if collapsed.get(id,false) else 0
		cards[id].enemy=g.owner(id)==1;cards[id].chosen=id==selected_id;cards[id].legal=id in legal_ids;cards[id].queue_redraw()
	if not initialized and not g.nodes.is_empty():initialized=true;fit_all()
	settlement_result={}
	queue_redraw()

func _width(id: String) -> float:
	if game==null or not game.nodes.has(id) or collapsed.get(id,false):return card_size.x+30
	var sum=0.0
	for child in game.children(id):sum+=_width(child)
	return maxf(card_size.x+30,sum)

func _layout(id: String,center: Vector2) -> void:
	if game==null or not game.nodes.has(id):return
	targets[id]=center
	if collapsed.get(id,false):return
	var kids=game.children(id);var start=center.x-_width(id)/2
	for child in kids:
		var w=_width(child);_layout(child,Vector2(start+w/2,center.y+card_size.y+28));start+=w

func _process(delta: float) -> void:
	if game==null:return
	if camera_animating:
		pan=pan.lerp(camera_target,1.0-exp(-delta*12))
		zoom=lerpf(zoom,zoom_target,1.0-exp(-delta*12))
		if pan.distance_to(camera_target)<0.5 and absf(zoom-zoom_target)<0.001:pan=camera_target;zoom=zoom_target;camera_animating=false
	for id in cards:
		positions[id]=targets[id] if reduced_motion else positions[id].lerp(targets[id],1.0-exp(-delta*10/maxf(0.01,motion_time_scale)))
		cards[id].position=positions[id]*zoom+pan-card_size*zoom/2
		cards[id].scale=Vector2.ONE*zoom
	if settling and is_settled():settling=false;settlement_finished.emit(true)
	queue_redraw()

func _draw() -> void:
	if game==null:return
	for id in game.nodes:
		var parent=game.nodes[id].parent
		if parent=="" or not positions.has(id) or not positions.has(parent) or hidden_by_collapse(id):continue
		var a=positions[parent]*zoom+pan+Vector2(0,card_size.y*zoom/2)
		var b=positions[id]*zoom+pan-Vector2(0,card_size.y*zoom/2)
		var middle=(a.y+b.y)/2
		var path=PackedVector2Array([a,Vector2(a.x,middle),Vector2(b.x,middle),b])
		draw_polyline(path,Color(0,0,0,0.5),5*zoom,true)
		draw_polyline(path,Color("c5a164") if game.owner(id)==0 else Color("b9786e"),1.7*zoom,true)
		draw_circle(b,3*zoom,Color("d9c494"))

func fit_all() -> void:
	if game==null or targets.is_empty():return
	var bounds=_bounds(-1)
	zoom_target=clampf(minf((size.x-100)/bounds.size.x,(size.y-48)/bounds.size.y),0.25,1.0)
	camera_target=size/2-bounds.get_center()*zoom_target;camera_animating=true

func focus(p: int) -> void:
	if game==null:return
	focus_player=p
	var bounds=_bounds(p)
	zoom_target=clampf(minf((size.x-110)/bounds.size.x,(size.y-48)/bounds.size.y),0.25,1.1)
	camera_target=size/2-bounds.get_center()*zoom_target;camera_animating=true

func opening_view(mobile: bool=false) -> void:
	if game==null or not targets.has(game.root(0)):return
	if mobile:focus(0);return
	zoom=0.95
	var center=(targets[game.root(0)].x+targets[game.root(1)].x)/2
	pan=Vector2(size.x/2-center*zoom,112);camera_animating=false

func cancel_card_gestures() -> void:
	for view in cards.values():view.moved=true;view.press_time=-1;view.hover_time=-1

func _input(e: InputEvent) -> void:
	if not visible or not interaction_enabled:return
	if e is InputEventScreenTouch:
		var blocked=input_blocked_at.is_valid() and input_blocked_at.call(e.position)
		if e.pressed and not blocked and get_global_rect().has_point(e.position):fingers[e.index]=e.position-global_position
		elif not e.pressed:fingers.erase(e.index)
		if fingers.size()<2:touch_distance=0
		else:cancel_card_gestures()
	elif e is InputEventScreenDrag and fingers.has(e.index):
		fingers[e.index]=e.position-global_position
		if fingers.size()>=2:
			var pts=fingers.values();var dist=pts[0].distance_to(pts[1]);var center=(pts[0]+pts[1])/2
			if touch_distance>0:zoom_at(dist/touch_distance,center)
			touch_distance=dist;cancel_card_gestures();get_viewport().set_input_as_handled()

func _bounds(p: int) -> Rect2:
	var bounds=Rect2();var first=true
	for id in targets:
		if not game.nodes.has(id) or hidden_by_collapse(id) or (p>=0 and game.owner(id)!=p):continue
		var rect=Rect2(targets[id]-card_size/2,card_size)
		bounds=rect if first else bounds.merge(rect);first=false
	return bounds

func hidden_by_collapse(id: String) -> bool:
	if game==null or not game.nodes.has(id):return false
	var parent=game.nodes[id].parent
	while parent!="" and game.nodes.has(parent):
		if collapsed.get(parent,false):return true
		parent=game.nodes[parent].parent
	return false

func reveal(ids: Array) -> void:
	for id in ids:
		if not game.nodes.has(id):continue
		var parent=game.nodes[id].parent
		while parent!="" and game.nodes.has(parent):collapsed.erase(parent);parent=game.nodes[parent].parent

func _wheel(factor: float,at: Vector2) -> void:
	if interaction_enabled:zoom_at(factor,at-global_position)

func zoom_at(factor: float,at: Vector2) -> void:
	var old=zoom;zoom=clampf(zoom*factor,0.25,1.8)
	pan=at-(at-pan)*(zoom/old);camera_animating=false

func _gui_input(e: InputEvent) -> void:
	if not interaction_enabled:return
	if e is InputEventMouseButton:
		if e.button_index==MOUSE_BUTTON_LEFT:drag=e.pressed;camera_animating=false;accept_event()
		elif e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom_at(1.12 if e.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.12,e.position);accept_event()
	elif e is InputEventMouseMotion and drag:pan+=e.relative;accept_event()
	elif e is InputEventScreenTouch:
		accept_event()
	elif e is InputEventScreenDrag:
		accept_event()
	elif e is InputEventMagnifyGesture:zoom_at(e.factor,e.position);accept_event()
	elif e is InputEventPanGesture:pan-=e.delta*22;camera_animating=false;accept_event()
