extends SceneTree
var checks=0
var failures: Array=[]
var main
var captures: Array=[]
var capture=false
var folder=""
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func text(node: Node) -> String:
	var result=""
	for l in node.find_children("*","Label",true,false):result+=l.text+"\n"
	return result
func fresh(faction: String="I05") -> GameState:
	main._start_game(181);main.modal_open=true
	var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.discards={"group":[],"plot":[],"resource":[]};g.graves=[[],[]];g.factions=[faction,"I01"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func put(g: GameState,id: String,p: int=0) -> void:
	g.decks.group.erase(id)
	for parent in g.field(p):
		if g.can_parent(parent):g._enter(id,p,parent,1);return
func give(g: GameState,id: String,p: int=0) -> void:g.decks.plot.erase(id);g.hands[p].plot.append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func goal_fixture() -> GameState:
	var g=fresh()
	for id in ["G051","G013","G021","G052","G053"]:put(g,id)
	give(g,"P51");main.selected="P51";main.hand_tab="plot";main._refresh();main.modal_open=true;return g
func idle() -> void:
	var deadline=Time.get_ticks_msec()+7000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Presentation completes")
func take(name: String) -> void:
	if not capture:return
	var deadline=Time.get_ticks_msec()+10000
	while not CardDB.art_requests.is_empty() and Time.get_ticks_msec()<deadline:CardDB.collect_art(8);await process_frame
	await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func inside(node: Node) -> void:
	for b in node.find_children("*","Button",true,false):
		if b.is_visible_in_tree() and b.get_parent() is not Container:check(Rect2(Vector2.ZERO,main.size).encloses(b.get_global_rect()),"Button inside viewport "+b.text)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if capture:DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.12
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact;main._start_game(181);main.modal_open=true;main._resize()
		var first=main.overlay.find_children("*","CardView",true,false)
		check(first.size()==4 and main.game.legal_actions(0).size()==8,"Eight factions split into readable pages")
		inside(main.overlay);await take(profile.name+"-factions-1")
		var phase=main.game.phase;first[0].selected.emit(first[0].id);check(main.game.phase==phase and main.detail_layer.get_child_count()>0,"Opening art click only inspects")
		main._close_inspection();main.modal_open=true;main.faction_page=1;main._phase_overlay()
		var second=main.overlay.find_children("*","CardView",true,false);check(second.any(func(v):return v.id=="I07") and second.any(func(v):return v.id=="I08"),"New factions accessible on page two")
		inside(main.overlay);await take(profile.name+"-factions-2")
		var g=goal_fixture();main._resize();main._inspect("P51");await process_frame
		check(text(main.detail_layer).contains("力量20/20") and text(main.detail_layer).contains("可被反制"),"Reader shows private goal progress and timing")
		inside(main.detail_layer);await take(profile.name+"-goal-reader");main._close_inspection();main.modal_open=true
		check(main.hud.find_children("*","Button",true,false).any(func(b):return b.text=="宣告胜利"),"Selected met goal has explicit declaration button")
		main._do_action(0,action(g,0,"plot",{"id":"P51"}));main.modal_open=true;main.presentation_tween.pause()
		check(main.busy and g.winner==-2 and "P51" in g.hands[0].plot and g.phase=="main","Declaration reveal cannot commit or win early")
		check(text(main.presentation_layer).contains("宣告胜利"),"Declaration animation clearly names intent")
		main.presentation_tween.play();await idle();check(g.winner==0 and main.overlay.get_child_count()>0,"Victory appears after declaration animation and settlement")
		await take(profile.name+"-goal-victory")
	# Animation cancellation, countering, delayed rewards, and target cue all retain the shared flow.
	var g=goal_fixture();give(g,"P15",1);main._do_action(0,action(g,0,"plot",{"id":"P51"}));main.modal_open=true;await idle()
	check(g.phase=="plot_response" and g.winner==-2,"Declaration opens ordinary counter response")
	main._do_action(1,action(g,1,"counter"));main.modal_open=true;main.presentation_tween.pause();check(g.phase=="plot_response" and g.winner==-2,"Counter waits for its reveal")
	main.presentation_tween.play();await idle();check(g.phase=="main" and g.winner==-2 and "P51" in g.discards.plot,"Counter cancels goal without false victory")
	g=goal_fixture();main._do_action(0,action(g,0,"plot",{"id":"P51"}));main.presentation_tween.pause();main._start_game(81);await process_frame
	check(main.game!=g and main.game.phase=="setup_faction" and g.winner==-2 and not main.busy,"Restart cancels declaration without stale victory")
	g=fresh("I07");put(g,"G007");main._refresh();main.modal_open=true
	main._do_action(0,action(g,0,"ability",{"pacify":true}));main.modal_open=true;main.presentation_tween.pause();check(g.has("G007","暴力") and g.token("R0"),"Peace conversion waits for source reveal")
	main.presentation_tween.play();await idle();check(g.has("G007","和平") and not g.has("G007","暴力") and not g.token("R0"),"Peace conversion commits after source and target animations")
	main._inspect("G007");check(text(main.detail_layer).contains("化干戈"),"Reader explains lasting peace conversion");main._close_inspection()
	g=fresh();give(g,"P51");give(g,"P52",1);main._refresh();main.modal_open=true;main._inspect("P52")
	check(not text(main.detail_layer).contains("尚未达成") and not text(main.detail_layer).contains("团体0/9"),"Hidden opponent goal progress is not exposed by reader")
	main._close_inspection();g.exposed.append("P52");main._inspect("P52");check(text(main.detail_layer).contains("团体0/9"),"Exposed goal can show public progress")
	var report={"checks":checks,"failures":failures,"captures":captures,"profiles":["1600x900","1280x720"],"android_device_tested":false};FileAccess.open("res://tests/covenant-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("COVENANT UI: "+JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
