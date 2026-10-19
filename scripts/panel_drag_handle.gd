class_name PanelDragHandle
extends Control
## Only the title strip owns this gesture; lists and card gestures keep their input.

signal moved(at: Vector2)
signal drag_started
signal drag_finished

var panel: Control
var dragging=false
var pointer=-2
var last_pointer=Vector2.ZERO

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape=Control.CURSOR_DRAG

func constrain(at: Vector2) -> Vector2:
	var viewport_size=panel.get_parent_control().size
	# Keep a useful section of the title reachable, while allowing the body offscreen.
	return Vector2(clampf(at.x,180-panel.size.x,viewport_size.x-180),clampf(at.y,8,viewport_size.y-58))

func move_to(at: Vector2) -> void:
	panel.position=constrain(at)
	moved.emit(panel.position)

func _begin(at: Vector2,index: int) -> void:
	if dragging:return
	dragging=true;pointer=index;last_pointer=at;drag_started.emit()

func _move(at: Vector2,index: int) -> void:
	if not dragging or pointer!=index:return
	move_to(panel.position+at-last_pointer);last_pointer=at

func _end(index: int) -> void:
	if not dragging or pointer!=index:return
	dragging=false;pointer=-2;drag_finished.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:_begin(event.global_position,-1)
		else:_end(-1)
		accept_event()
	elif event is InputEventMouseMotion and pointer==-1:
		_move(event.global_position,-1);accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:_begin(event.position,event.index)
		else:_end(event.index)
		accept_event()
	elif event is InputEventScreenDrag:
		_move(event.position,event.index);accept_event()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:_end(pointer)

func _exit_tree() -> void:
	_end(pointer)
