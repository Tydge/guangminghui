extends SceneTree
var checks=0
var failures: Array=[]
var capture_images=false
var image_folder="res://tests/"

func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures.append(text);push_error(text)

func fresh() -> GameState:
	var g=GameState.new(81);g.act(0,g.legal_actions(0)[1]);g.factions=["I02","I02"];g.nodes.R1.card="I02"
	g.turns=[2,2];g.phase="main";g.current=0;g.nodes.R0.token=1;g.nodes.R1.token=1
	g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")}
	return g

func place(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)

func action(g: GameState,type: String,args: Dictionary) -> Dictionary:
	for a in g.legal_actions(0):
		if a.type!=type:continue
		var matches=true
		for key in args:
			if a.get(key)!=args[key]:matches=false
		if matches:return a
	return {}

func text_labels(node: Node) -> String:
	var result=""
	for item in node.find_children("*","Label",true,false):result+=item.text+"\n"
	return result

func capture(name: String) -> void:
	if not capture_images:return
	await process_frame;await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(image_folder+name+".png")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):image_folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.15;main._start_game(4318)
	var g=fresh();main.game=g;place(g,"G072",0,"R0")
	for id in ["G034","G043"]:g.decks.group.erase(id)
	g.decks.group=["G034","G043"]+g.decks.group
	main._refresh();main._select_card("G072");await main._do_action(0,action(g,"ability",{"src":"G072"}));await process_frame
	check(g.phase=="choice" and text_labels(main.overlay).contains("内容出海"),"Japan opens the real filtered-card choice UI")
	var shown_cards=main.overlay.find_children("*","Control",true,false).filter(func(node):return node is CardView)
	check(shown_cards.size()==4,"Human choice UI shows all four legally peeked cards, including invalid choices")
	await capture("光明会_新机制_日本内容出海")
	await main._do_action(0,action(g,"choose",{"id":"G034"}));await process_frame
	check("G034" in g.hands[0].group and g.phase=="main","Japan choice returns to live match")
	g=fresh();main._start_game(4318);main.game=g
	place(g,"G016",0,"R0");place(g,"G078",0,"R0");place(g,"G036",0,"R0");place(g,"G024",0,"G016");place(g,"G037",0,"G024");place(g,"G071",1,"R1")
	# Leave room below P after advertising +3 so compute remains a legal follow-up.
	g.nodes.G024.learned=1
	give(g,"P27",0);await main._do_action(0,action(g,"plot",{"id":"P27","target":"G024"}))
	await main._do_action(0,action(g,"ability",{"src":"G036","target":"G024"}))
	await main._do_action(0,action(g,"ability",{"src":"G037","target":"G024"}))
	await main._do_action(0,action(g,"ability",{"src":"G078","target":"G024"}))
	g.nodes.G024.token=0;await main._do_action(0,action(g,"ability",{"src":"G016","target":"G024"}))
	main._inspect("G024");await process_frame
	var reader=text_labels(main.detail_layer)
	check(reader.contains("借贷负债") and reader.contains("GP等于有效P") and reader.contains("定向投放") and reader.contains("新增标签 · 媒体"),"Desktop reader displays every new status and converted tag")
	await capture("光明会_新机制_状态大卡")
	main._close_inspection();main.compact=true;main._resize();main._inspect("G024");await process_frame
	check(text_labels(main.detail_layer).contains("借贷负债") and text_labels(main.detail_layer).contains("新增标签 · 媒体"),"Mobile reader also exposes new states")
	main._close_inspection();main.compact=false
	give(g,"P17",0);await main._do_action(0,action(g,"plot",{"id":"P17","target":"G078"}))
	var attack=action(g,"attack",{"src":"G078","target":"G071","mode":"control"});main._review_action(attack);await process_frame
	var resources=main.large_layer.find_children("*","Button",true,false).map(func(button):return button.text)
	check(resources.any(func(label):return label.contains("电子游戏") and label.contains("GP +%d"%g.stat("G024","gp"))),"Preflight uses boosted effective GP without expanding rule text")
	await capture("光明会_新机制_攻击预览")
	main._clear(main.large_layer);main.preview_action={}
	g=fresh();main._start_game(4318);main.game=g;place(g,"G005",0,"R0");place(g,"G051",1,"R1");place(g,"G008",1,"R1");place(g,"G010",1,"G008")
	await main._do_action(0,action(g,"attack",{"src":"G005","target":"G051","mode":"destroy"}))
	var support=g.legal_actions(1).filter(func(a):return a.type=="support" and a.src=="G008")[0];await main._do_action(1,support);main.modal_open=true;main._refresh();await process_frame
	check(text_labels(main.overlay).contains("联合国 支援防守 +2（GP）"),"Updated effective GP appears in the public action feed")
	await capture("光明会_新机制_联合国响应")
	check(g.validate().is_empty(),"Modern UI actions conserve cards")
	await create_timer(0.25).timeout
	print("MODERN UI: %d checks, %d failures"%[checks,failures.size()])
	var f=FileAccess.open("res://tests/modern-ui-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	main.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
