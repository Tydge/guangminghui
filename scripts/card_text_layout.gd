class_name CardTextLayout
extends RefCounted
## Lay out complete lines. Fitting uses logarithmic search and a bounded shared cache.
static var fit_cache: Dictionary={}
static func fit(font: Font,text: String,width: float,height: float,fs: int,multiline: bool=false) -> String:
	if text=="" or height<font.get_height(fs):return ""
	var key=JSON.stringify([text,width,height,fs,multiline])
	if fit_cache.has(key):return fit_cache[key]
	var fits=func(value):return font.get_multiline_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,width,fs).y<=height+0.01 if multiline else font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x<=width
	var result=text
	if not fits.call(text):
		var lo=0;var hi=text.length()
		while lo<hi:
			var mid=(lo+hi+1)/2
			if fits.call(text.substr(0,mid)+"…"):lo=mid
			else:hi=mid-1
		result=text.substr(0,lo).strip_edges()+"…"
	if fit_cache.size()>=1024:fit_cache.clear()
	fit_cache[key]=result;return result

static func build(font: Font,area: Rect2,rows: Array,body: String,body_fs: int,small: bool) -> Array:
	var out: Array=[];var cursor=area.position.y
	if small:
		for attempt in 6:
			var needed=0.0
			for row in rows:needed+=ceilf(font.get_height(row.fs))+1
			if needed<=area.size.y:break
			for row in rows:row.fs=maxi(6,row.fs-1)
	for row in rows:
		var wrap=row.get("wrap",false)
		var h=ceilf(font.get_multiline_string_size(row.text,HORIZONTAL_ALIGNMENT_LEFT,area.size.x,row.fs).y if wrap else font.get_height(row.fs))
		if cursor+h>area.end.y:break
		var value=fit(font,row.text,area.size.x,h,row.fs,wrap)
		if value!="":out.append({"text":value,"fs":row.fs,"color":row.color,"rect":Rect2(area.position.x,cursor,area.size.x,h)})
		cursor+=h+(1 if small else 3)
	if body!="" and not small:
		cursor+=3
		var remaining=area.end.y-cursor
		var fs=body_fs
		while fs>12 and font.get_multiline_string_size(body,HORIZONTAL_ALIGNMENT_LEFT,area.size.x,fs).y>remaining:fs-=1
		var value=fit(font,body,area.size.x,remaining,fs,true)
		if value!="":
			var h=font.get_multiline_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,area.size.x,fs).y
			out.append({"text":value,"fs":fs,"color":Color("182d30"),"rect":Rect2(area.position.x,cursor,area.size.x,h)})
	return out
