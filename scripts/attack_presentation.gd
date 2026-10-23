extends Control
## Board-only visuals. Ghost recruits never enter GameState.nodes or BoardView.cards.
var host: WeakRef
var m:
	get:return host.get_ref()
var ghost: CardView
var ghost_id=""
var ghost_source=""
var ghost_point=Vector2.ZERO
var previewing=false
var recruit_camera={}
var stage=""
var attack={}
var progress=0.0
var opacity=1.0
var glow={}
var glow_amount=0.0
var version=0
const CONTROL=Color("77e4cc")
const DESTROY=Color("f39577")
const SUPPORT=Color("8bd5f0")

func _init(main):host=weakref(main)
func _ready():name="AttackPresentation";mouse_filter=Control.MOUSE_FILTER_IGNORE;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func reset():
	version+=1;stage="";attack={};glow={};progress=0;glow_amount=0;previewing=false;clear_ghost();queue_redraw()
func clear_ghost():
	if is_instance_valid(ghost):remove_child(ghost);ghost.queue_free()
	ghost=null;ghost_id="";ghost_source="";recruit_camera={}
func point(id: String) -> Vector2:
	return ghost_point if id==ghost_id else m.board.positions.get(id,m.board.targets.get(id,Vector2.ZERO))
func rect(id: String) -> Rect2:
	return Rect2(point(id)*m.board.zoom+m.board.pan-m.board.card_size*m.board.zoom/2,m.board.card_size*m.board.zoom)
func global_rect(id: String) -> Rect2:return Rect2(rect(id).position+m.board.global_position,rect(id).size)
func free_recruit_position(src: String) -> Vector2:
	var center=m.board.targets.get(src,point(src))+Vector2(0,m.board.card_size.y+28)
	var width=m.board.card_size.x+30
	for i in range((m.board.targets.size()+2)*2):
		var offset=0 if i==0 else ceili(i/2.0)*(1 if i%2==1 else -1)
		var candidate=center+Vector2(offset*width,0)
		var area=Rect2(candidate-m.board.card_size/2,m.board.card_size).grow(12)
		if m.board.targets.values().all(func(at):return not area.intersects(Rect2(at-m.board.card_size/2,m.board.card_size))):return candidate
	return center+Vector2(width*(m.board.targets.size()+2),0)
func ensure_ghost(info: Dictionary):
	if ghost_id==info.target and is_instance_valid(ghost):return
	clear_ghost();ghost_id=info.target;ghost_source=info.src;ghost_point=free_recruit_position(info.src)
	ghost=CardView.new();ghost.name="RecruitPreview";ghost.configure(ghost_id,m.game);ghost.size=m.board.card_size;add_child(ghost)
	ghost.selected.connect(m._inspect);ghost.inspected.connect(m._inspect);ghost.hovered.connect(m._hover);ghost.wheel_zoom.connect(m.board._wheel)
	update_ghost()
func sync_state(g: GameState):
	if g.battle.get("hand_target",false):
		ensure_ghost(g.battle);previewing=false
	elif not previewing or not m.busy or g.nodes.has(ghost_id):clear_ghost()
	update_ghost();queue_redraw()
func update_ghost():
	if is_instance_valid(ghost):ghost.position=rect(ghost_id).position;ghost.scale=Vector2.ONE*m.board.zoom
func _process(_delta):
	if m==null:return
	update_ghost();queue_redraw()
func readable_zoom() -> float:return clampf((m.board.size.y-70)/m.board.card_size.y,0.45,1.0)
func screen(at: Vector2) -> Vector2:return at*m.board.zoom+m.board.pan
func _play(tween: Tween) -> bool:
	m.presenting=true;m.presentation_tween=tween
	tween.finished.connect(func():m._finish_presentation(true),CONNECT_ONE_SHOT)
	return await m.presentation_finished
func camera(center: Vector2,zoom: float,duration: float) -> bool:
	m.board.camera_animating=false
	var start_zoom=m.board.zoom;var start_center=(m.board.size/2-m.board.pan)/start_zoom
	var tween=m.create_tween()
	tween.tween_method(func(t):m.board.zoom=lerpf(start_zoom,zoom,t);m.board.pan=m.board.size/2-start_center.lerp(center,t)*m.board.zoom,0.0,1.0,duration*m.presentation_time_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return await _play(tween)
func frame_pair(a: Vector2,b: Vector2) -> float:
	var extent=(a-b).abs()+m.board.card_size+Vector2(65,85)
	return clampf(minf(readable_zoom(),minf(m.board.size.x/extent.x,m.board.size.y/extent.y)),0.10,1.0)
func launch(info: Dictionary) -> bool:
	var ticket=version;stage="focus";attack=info.duplicate(true);progress=0;opacity=1
	m.board.reveal([info.src,info.target]);m.board.sync(m.game)
	if not await m.board.wait_for_settlement():return false
	if ticket!=version:return false
	if info.hand_target:
		var entry={"center":(m.board.size/2-m.board.pan)/m.board.zoom,"zoom":m.board.zoom}
		var start=m.interactions.anchor("hand",int(info.attacker),"group",info.target)
		var original=m.interactions.visible_card(info.target)
		ensure_ghost(info);recruit_camera=entry;previewing=true;ghost.hide()
		if not await camera((point(info.src)+ghost_point)/2,frame_pair(point(info.src),ghost_point),0.16 if m.reduced_motion else 0.32):return false
		if ticket!=version:return false
		stage="recruit"
		var card=m.interactions.flight(info.target,"group",true)
		if original!=null and original not in m.interactions.dimmed:m.interactions.dimmed.append(original);original.modulate.a=0.12
		m.interactions.arc(card,start,global_rect(info.target),0,0)
		var tween=m.create_tween()
		tween.tween_method(func(t):m.interactions.arc(card,start,global_rect(info.target),t,28),0.0,1.0,(0.20 if m.reduced_motion else 0.45)*m.presentation_time_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(func():if is_instance_valid(ghost):ghost.show())
		if not await _play(tween):return false
		if ticket!=version:return false
	stage="focus"
	var origin=point(info.src);var target=point(info.target)
	var center=(origin+target)/2 if m.reduced_motion else origin
	var zoom=frame_pair(origin,target) if m.reduced_motion else readable_zoom()
	if not await camera(center,zoom,0.12 if m.reduced_motion else 0.36):return false
	if ticket!=version:return false
	stage="trace";m._sound("select")
	var tween=m.create_tween();tween.tween_interval((0.05 if m.reduced_motion else 0.15)*m.presentation_time_scale)
	var duration=0.24 if m.reduced_motion else clampf(0.55+origin.distance_to(target)/1000,0.75,1.6)
	tween.tween_method(func(t):
		progress=t
		if not m.reduced_motion:
			var focus=origin.lerp(arrow_point(t),smoothstep(0,0.25,t))
			m.board.pan=m.board.size/2-focus*m.board.zoom
		update_ghost();queue_redraw(),0.0,1.0,duration*m.presentation_time_scale).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not await _play(tween):return false
	if ticket!=version:return false
	stage="impact"
	if not m.reduced_motion:
		if not await camera(target,m.board.zoom,0.16):return false
		if ticket!=version:return false
	tween=m.create_tween();tween.tween_property(self,"opacity",0.0,(0.18 if m.reduced_motion else 0.40)*m.presentation_time_scale)
	if not await _play(tween):return false
	if ticket!=version:return false
	stage="";attack={};queue_redraw();return true
func support(info: Dictionary) -> bool:
	var ticket=version;stage="support";glow=info.duplicate(true);glow_amount=0
	var tween=m.create_tween()
	tween.tween_method(func(t):glow_amount=sin(t*PI);queue_redraw(),0.0,1.0,(0.30 if m.reduced_motion else 0.72)*m.presentation_time_scale)
	if not await _play(tween):return false
	if ticket!=version:return false
	stage="";glow={};queue_redraw();return true
func restore_recruit_camera(tween: Tween,at: float,duration: float):
	if recruit_camera.is_empty():return
	var start_center=(m.board.size/2-m.board.pan)/m.board.zoom;var start_zoom=m.board.zoom;var finish=recruit_camera.duplicate()
	m.board.camera_animating=false
	tween.tween_method(func(t):m.board.zoom=lerpf(start_zoom,finish.zoom,t);m.board.pan=m.board.size/2-start_center.lerp(finish.center,t)*m.board.zoom,0.0,1.0,duration).set_delay(at).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
func edge(center: Vector2,toward: Vector2) -> Vector2:
	var delta=toward-center
	var half=m.board.card_size/2+Vector2(7,7)
	var ratio=minf(half.x/maxf(absf(delta.x),0.001),half.y/maxf(absf(delta.y),0.001))
	return center+delta*minf(ratio,0.45)
func arrow_point(t: float) -> Vector2:
	var a=point(attack.src);var b=point(attack.target)
	var start=edge(a,b);var finish=edge(b,a);var delta=finish-start
	var bend=delta.orthogonal().normalized()*minf(60,delta.length()*0.12)
	return start.bezier_interpolate(start+delta*0.33+bend,start+delta*0.72+bend,finish,t)
func highlight(id: String,color: Color,amount: float):
	var area=rect(id).grow(5)
	draw_rect(area,Color(color,0.10*amount),true)
	for x in [area.position.x,area.end.x]:
		for y in [area.position.y,area.end.y]:
			var corner=Vector2(x,y);var dx=1 if x==area.position.x else -1;var dy=1 if y==area.position.y else -1
			draw_line(corner,corner+Vector2(dx*23,0),Color(color,amount),3,true);draw_line(corner,corner+Vector2(0,dy*23),Color(color,amount),3,true)
func badge(text: String,at: Vector2,color: Color,alpha: float=1.0):
	var font=CardDB.readable_font();var fs=18;var extent=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs)+Vector2(34,16)
	var area=Rect2(Vector2(clampf(at.x-extent.x/2,12,m.board.size.x-extent.x-12),clampf(at.y,12,m.board.size.y-extent.y-12)),extent)
	var style=StyleBoxFlat.new();style.bg_color=Color(Color("112e31"),0.96*alpha);style.border_color=Color(color,0.7*alpha);style.set_border_width_all(1);style.set_corner_radius_all(6);draw_style_box(style,area)
	draw_string(font,area.position+Vector2(17,extent.y-11),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color(color,alpha))
func _draw():
	if m==null or m.game==null:return
	if ghost_id!="" and is_instance_valid(ghost) and ghost.visible and ghost.modulate.a>0.05:
		highlight(ghost_id,CONTROL,0.65)
		if previewing:badge(GameLocale.text("待招募"),rect(ghost_id).get_center()+Vector2(0,m.board.card_size.y*m.board.zoom/2+7),CONTROL)
	if not attack.is_empty():
		var color=DESTROY if attack.mode=="destroy" else CONTROL
		if stage=="focus":highlight(attack.src,color,0.85)
		if stage in ["trace","impact"]:
			var path=PackedVector2Array()
			for i in 51:path.append(screen(arrow_point(progress*i/50.0)))
			if progress>0.01:
				draw_polyline(path,Color(color,0.15*opacity),13,true);draw_polyline(path,Color("0a2629",opacity),7,true);draw_polyline(path,Color(color,opacity),3,true)
				var tip=path[-1];var tangent=(tip-path[-2]).normalized();var normal=tangent.orthogonal()
				draw_colored_polygon(PackedVector2Array([tip+tangent*5,tip-tangent*15+normal*9,tip-tangent*15-normal*9]),Color(color,opacity))
				badge(GameLocale.text("摧毁" if attack.mode=="destroy" else "控制"),tip+Vector2(0,-56),color,opacity)
			if stage=="impact":highlight(attack.target,color,opacity)
	if not glow.is_empty():
		for id in [glow.src,glow.target]:highlight(id,SUPPORT,glow_amount)
		var text=GameLocale.text("自卫 +%d"%glow.power) if glow.kind=="self_defend" else GameLocale.text("支援 +%d（%s）"%[glow.power,glow.basis])
		badge(text,rect(glow.src).position+Vector2(rect(glow.src).size.x/2,-42),SUPPORT,glow_amount)
