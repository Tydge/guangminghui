class_name WindowAccess
extends Node
## Park the actual controls so private choices, paging and scroll positions survive.
var host: WeakRef
var m:
	get:return host.get_ref()
var browsing=false
var transitioning=false
var parked=[]
var effect_layers=[]
var saved_selected=""
var saved_tab=""
var saved_modal=false
var saved_size=Vector2.ZERO
var scrolls=[]
var transition: Tween
var version=0
func _init(main) -> void:host=weakref(main)
func layer_states() -> Array:
	var result=[]
	for layer in [m.overlay,m.large_layer]:result.append({"node":layer,"visible":layer.visible,"alpha":layer.modulate.a})
	return result
func restore(states: Array) -> void:
	for state in states:
		if is_instance_valid(state.node):state.node.visible=state.visible;state.node.modulate.a=state.alpha
func reset() -> void:
	version+=1
	if transition!=null:transition.kill();transition=null
	restore(parked);restore(effect_layers);parked=[];effect_layers=[];scrolls=[];browsing=false;transitioning=false
func begin_effect() -> void:
	if not effect_layers.is_empty():return
	effect_layers=layer_states()
	for state in effect_layers:state.node.hide()
func end_effect() -> void:restore(effect_layers);effect_layers=[]
func offer(panel: Control,at: Vector2=Vector2(-1,20)) -> Button:
	var button=m._button("查看战场",peek,panel);button.name="PeekBattlefield";button.custom_minimum_size=Vector2(144,40);button.position=Vector2(panel.size.x-170,at.y) if at.x<0 else at
	button.tooltip_text=GameLocale.text("暂时收起窗口，查看场上与手牌，再返回继续操作。")
	return button
func peek() -> void:
	if browsing or transitioning or m.busy or m.panel_dragging or m.game==null:return
	if m.game.phase.begins_with("setup") or m.game.phase=="over":return
	version+=1
	parked=layer_states();saved_selected=m.selected;saved_tab=m.hand_tab;saved_modal=m.modal_open;saved_size=m.size;scrolls=[]
	for state in parked:
		for scroll in state.node.find_children("*","ScrollContainer",true,false):scrolls.append(Vector2i(scroll.scroll_horizontal,scroll.scroll_vertical))
	browsing=true;transitioning=true;m.modal_open=true;pause_board();m._clear(m.hover_layer);m._refresh(false)
	transition=m.create_tween().set_parallel(true)
	for state in parked:
		if state.visible:transition.tween_property(state.node,"modulate:a",0.0,(0.04 if m.reduced_motion else 0.12)*m.presentation_time_scale)
	var ticket=version
	transition.finished.connect(func():
		if ticket!=version:return
		for state in parked:state.node.hide();state.node.modulate.a=state.alpha
		transition=null;transitioning=false;m.board.interaction_enabled=true,CONNECT_ONE_SHOT)
func resume() -> void:
	if not browsing:return
	if transition!=null:transition.kill()
	browsing=false;transitioning=true;m.modal_open=true;pause_board();m.selected=saved_selected;m.hand_tab=saved_tab;m._clear(m.detail_layer);m.interactions.reader_id="";m.interactions.reader_stack.clear();m._clear(m.hover_layer)
	if m.size!=saved_size:
		if m.interactions.picker.active:m.interactions.step()
		elif not m.preview_action.is_empty():m._review_action(m.preview_action)
		else:m._phase_overlay()
		restore_scrolls_later(version)
	for state in parked:
		if state.visible:state.node.modulate.a=0;state.node.show()
	transition=m.create_tween().set_parallel(true)
	for state in parked:
		if state.visible:transition.tween_property(state.node,"modulate:a",state.alpha,(0.04 if m.reduced_motion else 0.12)*m.presentation_time_scale)
	var ticket=version
	transition.finished.connect(func():
		if ticket!=version:return
		restore(parked);parked=[];transition=null;transitioning=false;m.modal_open=saved_modal;m.board.interaction_enabled=true;m._refresh(false);m._schedule_ai(),CONNECT_ONE_SHOT)

func pause_board() -> void:
	m.board.interaction_enabled=false;m.board.cancel_card_gestures();m.board.drag=false;m.board.fingers.clear();m.board.touch_distance=0

func restore_scrolls_later(ticket: int) -> void:
	for i in 3:await get_tree().process_frame
	if ticket!=version:return
	var index=0
	for layer in [m.overlay,m.large_layer]:
		for scroll in layer.find_children("*","ScrollContainer",true,false):
			if index<scrolls.size():scroll.scroll_horizontal=scrolls[index].x;scroll.scroll_vertical=scrolls[index].y
			index+=1
