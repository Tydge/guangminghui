class_name CardDB
extends RefCounted

static var cards: Dictionary = {}
static var art_cache: Dictionary = {}
static var ui_font: Font
static var art_requests: Dictionary={}

static func readable_font() -> Font:
	if ui_font==null:
		var path="res://assets/fonts/NotoSansSC.ttf"
		if ResourceLoader.exists(path):
			var variation=FontVariation.new();variation.base_font=load(path);variation.variation_opentype={"wght":550};variation.variation_embolden=0.65;ui_font=variation
		else:ui_font=ThemeDB.fallback_font
	return ui_font

static func load_all() -> void:
	if cards.is_empty():
		cards = JSON.parse_string(FileAccess.get_file_as_string("res://data/cards.json"))

static func get_card(id: String) -> Dictionary:
	load_all()
	return cards.get(id, {})

static func request_art(id: String) -> void:
	if art_cache.has(id) or art_requests.has(id):return
	var path="res://assets/cards/%s.webp"%id
	if ResourceLoader.exists(path):
		# The headless dummy renderer cannot safely create textures on loader threads.
		if DisplayServer.get_name()=="headless":art_cache[id]=load(path);return
		var err=ResourceLoader.load_threaded_request(path,"Texture2D")
		if err==OK:art_requests[id]=path

static func collect_art(limit: int=3) -> void:
	for id in art_requests.keys():
		if limit<=0:break
		if ResourceLoader.load_threaded_get_status(art_requests[id])==ResourceLoader.THREAD_LOAD_LOADED:
			art_cache[id]=ResourceLoader.load_threaded_get(art_requests[id]);art_requests.erase(id);limit-=1

static func finish_art_requests() -> void:
	for id in art_requests.keys():art_cache[id]=ResourceLoader.load_threaded_get(art_requests[id])
	art_requests.clear()

static func art(id: String,nonblocking: bool=false) -> Texture2D:
	if nonblocking and not art_cache.has(id):
		request_art(id)
		if art_cache.has(id):return art_cache[id]
		if not art_requests.has(id):return null
		if ResourceLoader.load_threaded_get_status(art_requests[id])!=ResourceLoader.THREAD_LOAD_LOADED:return null
		art_cache[id]=ResourceLoader.load_threaded_get(art_requests[id]);art_requests.erase(id)
	if not art_cache.has(id):
		var path = "res://assets/cards/%s.webp" % id
		art_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return art_cache[id]

static func name_of(id: String) -> String:
	return get_card(id).get("name", id)

static func ids(kind: String) -> Array:
	load_all()
	return cards.keys().filter(func(id): return cards[id].kind == kind)

static func plot_text(c: Dictionary) -> String:
	return "目标 · "+c.get("target","")+"\n效果 · "+c.get("effect","")+"\n费用 · "+c.get("cost","")
