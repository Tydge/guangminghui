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
	targets=layout_nodes(g.nodes,card_size,collapsed)
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

static func layout_children(nodes: Dictionary,id: String) -> Array:
	return nodes.keys().filter(func(k):return nodes[k].get("parent","")==id)
static func layout_width(nodes: Dictionary,id: String,extent: Vector2,folded: Dictionary) -> float:
	if not nodes.has(id) or folded.get(id,false):return extent.x+30
	var width=0.0
	for child in layout_children(nodes,id):width+=layout_width(nodes,child,extent,folded)
	return maxf(extent.x+30,width)
static func layout_branch(nodes: Dictionary,id: String,center: Vector2,extent: Vector2,folded: Dictionary,out: Dictionary) -> void:
	if not nodes.has(id):return
	out[id]=center
	var kids=layout_children(nodes,id);var width=layout_width(nodes,id,extent,folded)
	# Hidden descendants still need stable positions for processing and later expansion.
	if folded.get(id,false):
		width=0
		for child in kids:width+=layout_width(nodes,child,extent,folded)
	var start=center.x-width/2
	for child in kids:
		var child_width=layout_width(nodes,child,extent,folded)
		layout_branch(nodes,child,Vector2(start+child_width/2,center.y+extent.y+28),extent,folded,out);start+=child_width
static func layout_nodes(nodes: Dictionary,extent: Vector2,folded: Dictionary={}) -> Dictionary:
	var out: Dictionary={}
	var left=maxf(layout_width(nodes,"R0",extent,folded),extent.x*3+96)
	var right=maxf(layout_width(nodes,"R1",extent,folded),extent.x*3+96)
	layout_branch(nodes,"R0",Vector2(left/2,0),extent,folded,out)
	layout_branch(nodes,"R1",Vector2(left+240+right/2,0),extent,folded,out)
	for id in nodes:
		if not nodes[id].has("resource_slot"):continue
		var root_id="R%d"%nodes[id].owner
		if out.has(root_id):out[id]=out[root_id]+Vector2((-1 if nodes[id].resource_slot==0 else 1)*(extent.x+32),0)
	return out

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
