extends Control
## A stable HUD element, above modal windows. It never owns or advances game time.
var active=false
var paused=true
var remaining=0.0
var maximum=15000.0
var stamped=0
var caption=""
var reduced=false
var last_second=-1
var warn: Callable
func _ready():mouse_filter=Control.MOUSE_FILTER_IGNORE;size=Vector2(72,76)
func update_clock(on: bool,hold: bool,left: float,total: float):
	active=on;paused=hold;remaining=left;maximum=maxf(1,total);stamped=Time.get_ticks_msec();queue_redraw()
func seconds() -> float:return maxf(0,remaining-(0 if paused else Time.get_ticks_msec()-stamped))/1000.0
func _process(_delta):
	var second=ceili(seconds()) if active else -1
	if active and not paused and second in [1,2,3] and second!=last_second and warn.is_valid():warn.call()
	last_second=second;queue_redraw()
func _draw():
	var center=Vector2(36,30);var radius=25.0;var gold=Color("d8ba77");var teal=Color("71d3c0");var danger=Color("ef9b6a")
	var value=seconds();var urgent=active and not paused and value<=5 and value>0
	var color=danger if urgent else (teal if active else Color("788780"))
	draw_circle(center,28,Color("092126"))
	draw_arc(center,radius,-PI/2,TAU-PI/2,64,Color("39514e"),4,true)
	if active:
		var ratio=clampf(value*1000/maximum,0,1)
		draw_arc(center,radius,-PI/2,-PI/2+TAU*ratio,64,color,4,true)
		if urgent and not reduced:
			var pulse=(sin(Time.get_ticks_msec()/170.0)+1)*0.5
			draw_arc(center,radius+3+pulse*2,0,TAU,64,Color(color,0.14+pulse*0.25),2,true)
	var text=str(ceili(value)) if active else "—"
	var font=CardDB.readable_font();var width=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
	draw_string(font,Vector2(center.x-width/2,37),text,HORIZONTAL_ALIGNMENT_LEFT,-1,19,color)
	if paused and active:draw_string(font,Vector2(56,15),"Ⅱ",HORIZONTAL_ALIGNMENT_LEFT,-1,11,gold)
	var label=GameLocale.text(caption);var label_width=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	draw_string(font,Vector2(center.x-label_width/2,72),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("e8ddbf"))
