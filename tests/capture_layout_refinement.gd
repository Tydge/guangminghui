extends "res://tests/capture_expansion_ui.gd"
var layout_metrics: Array=[]
func deep_fixture() -> GameState:
	main._start_game(81);var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I06","I03"];g.current=0;g.turns=[2,2];g.phase="main"
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	for entry in [["G073",0,"R0"],["G019",0,"G073"],["G097",0,"G019"],["G099",0,"G097"],["G023",0,"G099"],["G106",0,"G023"],["G104",0,"G106"],["G071",0,"R0"],["G103",0,"G071"],["G093",1,"R1"],["G095",1,"G093"],["G091",1,"G095"],["G100",1,"G091"],["G101",1,"G100"],["G098",1,"G101"]]:put(g,entry[0],entry[1],entry[2])
	for id in ["G088","G105","P31","P35","P37","P41"]:
		var kind=g.card(id).kind;g.decks[kind].erase(id);g.hands[0][kind].append(id)
	g.nodes.G106.token=0;g.captured.G106=true;g._log("你自动接管了事实核查网络 · 本回合无行动标记","enter");main.selected="G106";main.modal_open=true;main.thinking=false;return g
func settle() -> void:
	var b=main.board;b.pan=b.camera_target;b.zoom=b.zoom_target;b.camera_animating=false;b.reduced_motion=true;b._process(1)
func frame_check(p: int,label: String) -> void:
	var rect=main.board.get_global_rect()
	for id in main.board.cards:
		if not main.game.nodes.has(id) or (p>=0 and main.game.owner(id)!=p):continue
		if not rect.encloses(main.board.cards[id].get_global_rect()):failures.append(label+" camera clips "+id)
func footer_check(label: String) -> void:
	var toolbar=main.hud.get_node("ActionToolbar");var row_rect=toolbar.get_global_rect()
	for b in main.hand_layer.find_children("*","Button",true,false):
		if row_rect.intersects(b.get_global_rect()):failures.append(label+" hand tabs overlap action toolbar")
	for b in main.hud.find_children("*","Button",true,false):
		if b.text.begins_with("◈"):
			if b.get_global_rect().intersects(row_rect) or b.get_global_rect().intersects(main.board.get_global_rect()):failures.append(label+" journal overlaps board or actions "+str(b.get_global_rect())+" / "+str(row_rect))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(folder);root.size=Vector2i(1600,900)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.08
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"desktop-tall","size":Vector2i(1600,1000),"compact":false},{"name":"mobile","size":Vector2i(2400,1080),"compact":true},{"name":"mobile-16x9","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;main.compact=profile.compact;var g=fixture();g._log("你的主要阶段","turn");main._resize();main._refresh();main.board.fit_all();settle();await create_timer(0.35).timeout
		await take(profile.name+"-board");frame_check(-1,profile.name+" four-level overview");footer_check(profile.name)
		main.hand_tab="plot";main._refresh();await take(profile.name+"-plot-hand");main.hand_tab="group";main._refresh()
		var options=g.legal_actions(0).filter(func(a):return a.type=="attack" and a.target=="G095" and a.mode=="control")
		main._target(options,"src","选择带头团体 · 印度尼西亚");settle();await take(profile.name+"-target-selection");main.action_candidates.clear()
		g=deep_fixture();main._resize();main._refresh();main.board.fit_all();settle();await create_timer(0.35).timeout
		await take(profile.name+"-eight-level-overview");frame_check(-1,profile.name+" eight-level overview")
		main.board.focus(0);settle();await take(profile.name+"-eight-level-own");frame_check(0,profile.name+" own focus")
		layout_metrics.append({"profile":profile.name,"board":main.board.size,"card":main.board.card_size,"depth":8,"focused_zoom":main.board.zoom})
		main.board.focus(1);settle();await take(profile.name+"-enemy-focus");frame_check(1,profile.name+" enemy focus")
		main._inspect("G106");await take(profile.name+"-corrected-card");main._close_inspection();main.modal_open=true
		if not g.validate().is_empty():failures.append(profile.name+" card conservation: "+str(g.validate()))
	var report={"captures":captures,"failures":failures,"metrics":layout_metrics,"artwork_ratio":"1:1","board_card_height_before":212,"board_card_height_after":192,"hand_card_height_before":154,"hand_card_height_after":142,"desktop_900_board_height_before":405,"desktop_900_board_height_after":489};FileAccess.open(folder+"layout-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
