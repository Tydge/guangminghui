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
	main._start_game(181);var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.factions=["I02","I03"];g.phase="main";g.current=0;g.turns=[2,2]
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
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
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
	# Only public state changes after all effects finish fading.
	var g=fresh();put(g,"G025",0,"R0");attach(g,"P45","G025");main.selected="G025";main._refresh();main.modal_open=true
	var buttons=main.hud.find_children("*","Button",true,false).filter(func(b):return b.text=="解除监管")
	check(buttons.size()==1,"Regulated target offers short direct removal action")
	main._do_action(0,action(g,0,"lift",{"src":"G025"}));main.modal_open=true;main.presentation_tween.pause()
	check(g.token("G025") and g.stat("G025","gp")==0 and "P45" in g.nodes.G025.attached,"Removal cue precedes cost and GP restoration")
	check(text(main.presentation_layer).contains("解除监管") and not text(main.presentation_layer).contains("打出阴谋"),"Removal cue describes removal, not another plot play")
	main.presentation_tween.play();await idle();check(not g.token("G025") and "P45" not in g.nodes.G025.attached,"Removal resolves after full cue")
	g=fresh();put(g,"G081",1,"R1");put(g,"G005",0,"R0");attach(g,"P44","G081");g._launch_attack(0,{"src":"G005","target":"G081","mode":"destroy"});g.battle.bonus_a=100;g.battle.rolled=[1,1];g._resolve_battle();main._refresh()
	main._do_action(1,action(g,1,"trigger"));main.modal_open=true;main.presentation_tween.pause()
	check(main.presenting and g.token("G081") and "P44" in g.nodes.G081.attached and g.destroyed[0]==0,"AI bodyguard stays unconsumed during cue")
	check(text(main.presentation_layer).contains("AI · 效果触发") and text(main.presentation_layer).contains("挡下摧毁"),"Bodyguard cue identifies owner and prevented result")
	main.presentation_tween.play();await idle();check(g.last_battle.guarded and g.nodes.has("G081") and not g.token("G081"),"Bodyguard resolves after cue")
	g=fresh();put(g,"G028",0,"R0");give(g,"P46",0);main._refresh();main._do_action(0,action(g,0,"plot",{"id":"P46","target":"G028","tag":"计算机"}));main.modal_open=true;main.presentation_tween.pause()
	check(text(main.presentation_layer).contains("获得计算机标签") and not g.has("G028","计算机"),"Technology cue shows chosen tag before granting")
	main._start_game(1);await process_frame;check(not main.presenting and not main.game.nodes.has("G028"),"Restart cancels a pending new effect")
	# Inspect, compact attack resources and ordinary battle status on both aspect ratios.
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"desktop-tall","size":Vector2i(1600,1000),"compact":false},{"name":"mobile","size":Vector2i(2400,1080),"compact":true},{"name":"mobile-16x9","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact;g=fresh()
		put(g,"G119",0,"R0");put(g,"G120",0,"G119");put(g,"G121",0,"G119");put(g,"G127",0,"R0");put(g,"G081",0,"R0");put(g,"G113",0,"G081");put(g,"G114",0,"G113");put(g,"G115",0,"G114")
		put(g,"G025",1,"R1");put(g,"G126",1,"R1");put(g,"G118",1,"R1");attach(g,"P45","G119");attach(g,"P44","G081");g.synergy.add_tag("G115","科学");give(g,"P48",0);give(g,"P43",0);give(g,"P50",0);give(g,"G129",0);give(g,"G124",0)
		main.selected="G119";main.hand_tab="group";main._resize();main._refresh();main.modal_open=true;main.board.fit_all();main.board.pan=main.board.camera_target;main.board.zoom=main.board.zoom_target;main.board.camera_animating=false;main.board._process(1)
		check_panel(main.hud);await take(profile.name+"-board")
		main._inspect("G119");await process_frame;var details=text(main.detail_layer)
		check(details.contains("GP 0") and details.contains("印刷") and details.contains("当前") and details.contains("解除"),"Large reader shows current industrial power and regulatory status")
		check_panel(main.detail_layer);await take(profile.name+"-inspect");main._close_inspection();main.modal_open=true
		main._inspect("G115");check(text(main.detail_layer).contains("新增标签") and text(main.detail_layer).contains("科学"),"Large reader shows persistent tag grant");main._close_inspection();main.modal_open=true
		main._review_action(action(g,0,"attack",{"src":"G119","target":"G025","mode":"destroy"}));await process_frame
		check(text(main.large_layer).contains("联合动员可增强"),"Attack preview summarizes conditional support in one line");check_panel(main.large_layer);await take(profile.name+"-preview");main._clear(main.large_layer)
		g.current=1;g._launch_attack(1,{"src":"G126","target":"G081","mode":"control"});main._refresh();main.modal_open=true
		check(text(main.overlay).contains("目标不能自卫"),"Battle names self-defense restriction with a short status")
		check_panel(main.overlay);await take(profile.name+"-battle");check(g.validate().is_empty(),"Profile conserves new cards and attachments")
	var report={"checks":checks,"failures":failures,"captures":captures,"profiles":["1600x900","1600x1000","2400x1080","1280x720"],"android_device_tested":false};FileAccess.open("res://tests/synergy-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("SYNERGY UI: "+JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
