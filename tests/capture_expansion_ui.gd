extends SceneTree
var main
var folder=ProjectSettings.globalize_path("user://test-captures/expansion/")
var failures: Array=[]
var captures: Array=[]
func _initialize() -> void:call_deferred("run")
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func fixture() -> GameState:
	main._start_game(81);var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I06","I03"];g.current=0;g.turns=[2,2];g.phase="main";g.world="P36";g.decks.plot.erase("P36")
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	for entry in [["G081",0,"R0"],["G073",0,"R0"],["G097",0,"R0"],["G023",0,"G081"],["G084",0,"G023"],["G109",0,"G097"],["G095",1,"R1"],["G099",1,"R1"],["G108",1,"R1"],["G101",1,"G099"],["G087",1,"G101"]]:put(g,entry[0],entry[1],entry[2])
	g.nodes.G099.devastated=true;g.nodes.G099.token=0;g.nodes.G097.prepared=true
	for id in ["G088","G104","G106","P31","P35","P37","P41"]:
		var kind=g.card(id).kind;g.decks[kind].erase(id);g.hands[0][kind].append(id)
	main.selected="G097";main.modal_open=true;main.thinking=false;return g
func take(name: String) -> void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
	for button in main.hud.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not Rect2(Vector2.ZERO,main.size).encloses(button.get_global_rect()):failures.append(name+" HUD button outside viewport: "+button.text)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(folder);root.size=Vector2i(1600,900)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.08
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"desktop-tall","size":Vector2i(1600,1000),"compact":false},{"name":"mobile","size":Vector2i(2400,1080),"compact":true},{"name":"mobile-16x9","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size
		main.compact=profile.compact;main._start_game(81);main.modal_open=true;main._resize();main._refresh()
		var prefix=profile.name
		await take(prefix+"-faction-selection")
		main.game.act(0,main.game.legal_actions(0)[0]);main._refresh();await take(prefix+"-initial-selection")
		var g=fixture();main._resize();main._refresh();main.board.fit_all();main.board.pan=main.board.camera_target;main.board.zoom=main.board.zoom_target;main.board.camera_animating=false;main.board._process(1)
		await take(prefix+"-board")
		main.hand_tab="plot";main._refresh();await take(prefix+"-plot-hand");main.hand_tab="group";main._refresh()
		main._inspect("G097");await take(prefix+"-large-card");main._close_inspection();main.modal_open=true
		main._inspect("G099");await take(prefix+"-devastated-card");main._close_inspection();main.modal_open=true
		main._review_action({"type":"attack","src":"G073","target":"G095","mode":"control"});await take(prefix+"-attack-preview");main.preview_action={};main._clear(main.large_layer)
		var action={}
		for a in g.legal_actions(0):
			if a.type=="plot" and a.id=="P31" and a.target=="G095" and a.payer=="G109":action=a;break
		main._review_action(action);await take(prefix+"-disaster-preview");main._clear(main.large_layer)
		g._set_choice(0,"选择1张团体",g.hands[0].group,"review");main._refresh();await take(prefix+"-choice");g.choice={};g.phase="main"
		g._launch_attack(0,{"src":"G073","target":"G095","mode":"control"});g.battle.bonus_a=22;main._refresh();await take(prefix+"-battle")
		if not g.validate().is_empty():failures.append(prefix+" card conservation: "+str(g.validate()))
	var report={"captures":captures,"failures":failures,"desktop_resolutions":["1600x900","1600x1000"],"mobile_resolutions":["2400x1080","1280x720"],"artwork_ratio":"1:1"};FileAccess.open(folder+"visual-checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print(JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
