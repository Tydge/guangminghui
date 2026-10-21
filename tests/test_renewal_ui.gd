extends SceneTree
var checks=0
var failures: Array=[]
var main
var capture_images=false
var folder=ProjectSettings.globalize_path("user://test-captures/synergy/")
var captures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	main._start_game(181);var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I02","I03"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	main.modal_open=true;return g
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)
func attach(g: GameState,id: String,target: String) -> void:g.decks.plot.erase(id);g.nodes[target].attached.append(id)
func text(node: Node) -> String:
	var result=""
	for label in node.find_children("*","Label",true,false):result+=label.text+"\n"
	return result
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func idle() -> void:
	var deadline=Time.get_ticks_msec()+5000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Synergy presentation releases lock")
func take(name: String) -> void:
	if not capture_images:return
	await process_frame
	var deadline=Time.get_ticks_msec()+5000
	while not CardDB.art_requests.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func check_panel(node: Node) -> void:
	for b in node.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and b.get_parent() is not Container:check(Rect2(Vector2.ZERO,main.size).encloses(b.get_global_rect()),"Fixed UI button in viewport: "+b.text)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless";DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.1
	var g=fresh();put(g,"G135",0,"R0");main._refresh();main._do_action(0,action(g,0,"ability",{"src":"G135","target":"G135"}));main.modal_open=true;main.presentation_tween.pause()
	check(main.busy and g.stat("G135","p")==2,"School remains unchanged during source reveal")
	main.presentation_tween.play();await idle();check(g.stat("G135","p")==3,"School grants power after complete source and target flight")
	g=fresh();put(g,"G139",0,"R0");put(g,"G001",1,"R1");g._launch_attack(0,{"src":"R0","target":"G001","mode":"destroy"});g.battle.responder=0;main._refresh();main._do_action(0,action(g,0,"support",{"src":"G139","star":true}));main.modal_open=true;main.presentation_tween.pause()
	var before=g.rng.state;check(g.token("G139") and g.battle.support_a==0,"Astrology no cost before cue")
	main.presentation_tween.play();await idle();check(not g.token("G139") and g.rng.state!=before and g.battle.entries.any(func(e):return e.text.contains("骰点")),"Astrology roll cue commits once and records result")
	var picker=ActionPicker.new();picker.begin([{"type":"attack","solo":false},{"type":"attack","solo":true}]);check(picker.next_key()=="solo","Solo option appears as explicit choice");picker.select("solo",true);check(picker.actions.size()==1 and picker.actions[0].solo,"Solo selection keeps correct variant")
	# Exercise the actual signal callback, including the one-option async branch.
	g=fresh();put(g,"G131",0,"R0");put(g,"G001",1,"R1");g._launch_attack(0,{"src":"R0","target":"G001","mode":"destroy"});g.battle.responder=0;main._refresh();main.modal_open=true
	var pass_buttons=main.overlay.find_children("*","Button",true,false).filter(func(b):return b.text=="不再追加")
	check(pass_buttons.size()==1,"Battle has pass button")
	pass_buttons[0].pressed.emit();await idle();check(g.battle.responder==1,"Real battle button dispatches async action safely")
	# Many alternative counter fees remain one command, followed by the normal fee picker.
	g=fresh();put(g,"G137",0,"R0");put(g,"G136",0,"R0");give(g,"P15",0);give(g,"P01",0);give(g,"P28",1)
	for n in range(131,136):give(g,"G%d"%n,0)
	g.current=1;g.act(1,action(g,1,"plot",{"id":"P28"}));main._refresh();main.modal_open=true
	check(main.overlay.find_children("*","Button",true,false).filter(func(b):return b.text=="替身骗局").size()==1,"Counter response groups all fee variants into one concise button")
	check_panel(main.overlay)
	main._help("cards");check(text(main.large_layer).contains("槽位强制减少"),"Slot-loss rule is in help, not housing card text");main._clear(main.large_layer)
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"desktop-tall","size":Vector2i(1600,1000),"compact":false},{"name":"mobile","size":Vector2i(2400,1080),"compact":true},{"name":"mobile-16x9","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact;g=fresh()
		put(g,"G134",0,"R0");put(g,"G133",0,"G134");put(g,"G135",0,"G133");put(g,"G132",0,"R0");put(g,"G148",0,"R0");put(g,"G147",1,"R1");put(g,"G131",1,"R1")
		g.nodes.G135.learned=1;g.nodes.G148.prepared=true
		for n in range(136,144):give(g,"G%d"%n,0)
		main.hand_tab="group";main.selected="G135";main._resize();main._refresh();main.modal_open=true;main.board.fit_all();main.board.pan=main.board.camera_target;main.board.zoom=main.board.zoom_target;main.board.camera_animating=false;main.board._process(1)
		check_panel(main.hud);await take(profile.name+"-new-board")
		main._inspect("G135");await process_frame;check(text(main.detail_layer).contains("在场强化 P+1") and text(main.detail_layer).contains("自治工厂"),"Reader shows lasting power and parent aura");check_panel(main.detail_layer);await take(profile.name+"-new-reader");main._close_inspection();main.modal_open=true
		main._inspect("G148");check(text(main.detail_layer).contains("或普通摧毁"),"Reader explains Enclave prepared scope");main._close_inspection();main.modal_open=true
		g.current=1;var a=action(g,1,"attack",{"src":"G147","target":"G135","mode":"destroy","solo":true});main._review_action(a);await process_frame;check(text(main.large_layer).contains("无进攻支援") and text(main.large_layer).contains("支援  0个"),"Solo preview concise and consistent");check_panel(main.large_layer);await take(profile.name+"-new-preview");main._clear(main.large_layer)
		g._launch_attack(1,a);main._refresh();main.modal_open=true;check_panel(main.overlay);await take(profile.name+"-new-battle")
	var report={"checks":checks,"failures":failures,"captures":captures,"profiles":["1600x900","1600x1000","2400x1080","1280x720"],"android_device_tested":false};FileAccess.open("res://tests/renewal-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("RENEWAL UI: "+JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
