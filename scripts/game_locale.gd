class_name GameLocale
extends RefCounted
## Presentation only: rule data, commands, and logs retain their canonical values.
static var language="zh"
static var phrases: Dictionary={}
static var templates: Array=[]
static var trie: Dictionary={}
static var cache: Dictionary={}
static var missing: Dictionary={}
static var cjk: RegEx
static var loaded=false

static func load_catalog() -> void:
	if loaded:return
	loaded=true
	var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/en.json"))
	phrases=catalog.ui
	for entry in catalog.templates:
		var regex=RegEx.new();var error=regex.compile(entry.pattern)
		assert(error==OK,"Invalid translation pattern: "+entry.source)
		var embedded: RegEx=null
		if not entry.source.begins_with("%"):
			embedded=RegEx.new();embedded.compile(entry.pattern.trim_prefix("^").trim_suffix("$"))
		templates.append({"regex":regex,"embedded":embedded,"text":entry.text})
	for source in phrases:
		var branch=trie
		for character in source:
			if not branch.has(character):branch[character]={}
			branch=branch[character]
		branch[""]=phrases[source]
	cjk=RegEx.new();cjk.compile("[\\x{3400}-\\x{9fff}]")

static func set_language(value: String) -> void:
	language="en" if value=="en" else "zh"
	load_catalog();cache.clear();missing.clear();CardTextLayout.fit_cache.clear()
	TranslationServer.set_locale("en" if english() else "zh_CN")

static func english() -> bool:return language=="en"
static func has_chinese(value: String) -> bool:
	load_catalog();return cjk.search(value)!=null
static func clean(value: String) -> String:
	return value.replace("「","\"").replace("」","\"").replace("（"," (").replace("）",")").replace("，",", ").replace("。",".").replace("：",": ").replace("；","; ").replace("＋","+").replace("／","/").replace("’","'").replace("‘","'")

static func text(value: String,depth: int=0) -> String:
	if not english() or value=="":return value
	load_catalog()
	if cache.has(value):return cache[value]
	if phrases.has(value):return clean(phrases[value])
	if not has_chinese(value):return clean(value)
	var result=""
	if depth<8:
		for entry in templates:
			var found=entry.regex.search(value)
			if found==null:continue
			result=entry.text
			for i in range(1,found.get_group_count()+1):result=result.replace("{%d}"%(i-1),text(found.get_string(i),depth+1))
			break
		if result=="":
			# Messages also appear inside status lines, decorated logs, and reader paragraphs.
			for entry in templates:
				if entry.embedded==null:continue
				var found=entry.embedded.search(value)
				if found==null:continue
				var body=entry.text
				for i in range(1,found.get_group_count()+1):body=body.replace("{%d}"%(i-1),text(found.get_string(i),depth+1))
				result=text(value.substr(0,found.get_start()),depth+1)+body+text(value.substr(found.get_end()),depth+1)
				break
	if result=="" and depth<8:
		if value.begins_with("◈  "):result="◈  "+text(value.trim_prefix("◈  "),depth+1)
	if result=="":
		# Longest known phrase wins; template literals also cover composed status lines.
		var at=0
		while at<value.length():
			var branch=trie;var end=at;var best="";var stop=at
			while end<value.length() and branch.has(value[end]):
				branch=branch[value[end]];end+=1
				if branch.has(""):best=branch[""];stop=end
			if stop>at:result+=best;at=stop
			else:result+=value[at];at+=1
	result=clean(result)
	if has_chinese(result) and result!="中文":missing[value]=result
	if cache.size()>4096:cache.clear()
	cache[value]=result
	return result

static func alignments(values: Array,hand: bool=false) -> String:
	if not english():return " ".join(values) if hand else " · ".join(values)
	var short={"政府":"GOV","企业":"COR","自由":"LIB","保守":"CON","和平":"PEA","暴力":"VIO","正统":"STR","怪异":"WEI","犯罪":"CRI","狂热":"FAN"}
	var tiny={"政府":"GV","企业":"CO","自由":"LI","保守":"CV","和平":"PE","暴力":"VI","正统":"ST","怪异":"WE","犯罪":"CR","狂热":"FA"}
	return " ".join(values.map(func(v):return (tiny if hand else short).get(v,text(v))))

static func progress(value: String) -> String:
	return " · ".join(Array(value.split(" · ")).map(func(part):return text(part)))
