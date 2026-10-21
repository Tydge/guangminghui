extends SceneTree
var checks=0
var failures: Array=[]
var main
var capture_images=false
var folder=ProjectSettings.globalize_path("user://test-captures/interaction-polish/")
var captures: Array=[]
var timings: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	main._start_game(181);var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I02","I03"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	main.modal_open=true;return g
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func text(node: Node) -> String:
	var result=""
	for label in node.find_children("*","Label",true,false):result+=label.text+"\n"
	return result
func button(node: Node,value: String) -> Button:
	for b in node.find_children("*","Button",true,false):
		if b.text==value:return b
	return null
func idle() -> void:
	var deadline=Time.get_ticks_msec()+6000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Animation completes and releases input")
func take(name: String) -> void:
	if not capture_images:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func fixture() -> GameState:
	var g=fresh()
	for entry in [["G005",0,"R0"],["G025",0,"R0"],["G073",0,"R0"],["G001",0,"G005"],["G002",0,"G005"],["G003",0,"G005"],["G081",0,"G025"],["G028",0,"G073"],["G119",1,"R1"]]:put(g,entry[0],entry[1],entry[2])
	g.decks.plot.erase("P45");g.nodes.G025.attached.append("P45");give(g,"P18",0);give(g,"P14",0);give(g,"G043",0)
	main.hand_tab="plot";main.selected="P18";main._refresh();main.modal_open=true;return g
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless";DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.1
	# All metadata and last rendered lines fit, including tags and full-card statuses.
	for id in CardDB.cards:
		for extent in [Vector2(94,142),Vector2(138,192),Vector2(220,385),Vector2(292,520),Vector2(350,742)]:
			var v=CardView.new();v.configure(id);v.size=extent;v.full=extent.x==350
			var runs=v.text_layout();check(not runs.is_empty(),"Text exists: "+id)
			for run in runs:check(run.rect.end.y<=extent.y-(14 if v.full else 8)-4 and run.rect.size.y>=v.font.get_height(run.fs)-0.01,"Complete visible text line: "+id)
			v.free()
	# Categories build a bounded page rather than all 130 groups and 50 plots.
	for kind in ["faction","group","plot"]:
		main.collection_filter=kind;var started=Time.get_ticks_usec();main.interactions.catalog(true);timings.append({"category":kind,"construction_ms":(Time.get_ticks_usec()-started)/1000.0})
		var views=main.large_layer.find_children("*","Control",true,false).filter(func(n):return n is CardView)
		check(views.size()<=16,"Catalog has bounded card count per page")
		if kind=="group":button(main.large_layer,"下一页").pressed.emit();check(main.interactions.collection_page==1,"Catalog pages navigate without full reconstruction of every card")
	main._clear(main.large_layer)
	# Clicking card artwork inspects; only the explicit button commits opening choices.
	main._start_game(81);var g=main.game
	var faction=main.overlay.find_children("*","Control",true,false).filter(func(n):return n is CardView)[0]
	faction.selected.emit(faction.id);check(g.phase=="setup_faction" and main.detail_layer.get_child_count()>0,"Faction artwork only inspects")
	main._close_inspection();button(main.overlay,"选择").pressed.emit();await idle();main.modal_open=true
	check(g.phase=="setup_group","Faction choice button commits")
	var initial=main.overlay.find_children("*","Control",true,false).filter(func(n):return n is CardView)[0]
	initial.selected.emit(initial.id);check(g.phase=="setup_group" and g.groups(0).is_empty(),"Initial group artwork only inspects")
	main._close_inspection();var hand_before=g.hands[0].group.duplicate();var plots_before=g.hands[0].plot.duplicate();var random_before=g.rng.state
	var reroll=action(g,0,"mulligan");main._do_action(0,reroll);main.modal_open=true;main.presentation_tween.pause()
	check(g.hands[0].group==hand_before and g.mulligans[0]==0 and g.rng.state==random_before,"Mulligan holds hand and RNG until return/draw motions finish")
	main.presentation_tween.play();await idle();check(g.mulligans[0]==1 and g.hands[0].group.size()==5 and g.hands[0].plot==plots_before and g.validate().is_empty(),"First mulligan exchanges all groups only")
	await main._do_action(0,action(g,0,"mulligan"));main.modal_open=true
	check(g.mulligans[0]==2 and action(g,0,"mulligan").is_empty() and main.overlay.get_node("OpeningMulligan").disabled,"Two-mulligan limit and disabled button")
	for seed_value in range(1,17):
		var model=GameState.new(seed_value);model.act(0,model.legal_actions(0)[0]);var plot_copy=model.hands.duplicate(true);var deck_n=model.decks.group.size()
		for p in [0,1]:
			for i in 2:check(model.act(p,action(model,p,"mulligan")) and model.hands[p].group.size()==5 and model.decks.group.size()==deck_n and model.hands[p].plot==plot_copy[p].plot and model.validate().is_empty(),"Both players' mulligan conserves cards and plots")
		check(not model.act(0,{"type":"mulligan","label":"重随"}),"Third mulligan rejected")
	# Large reorganization spaces become two board selections and one review.
	g=fixture();await main.board.wait_for_settlement();var choices=g.legal_actions(0).filter(func(a):return a.type=="plot" and a.id=="P18")
	check(choices.size()>20,"Reorganization fixture has a real combinatorial target space")
	main._action_list(choices);check(main.target_key=="target" and main.interactions.picker.active and main.large_layer.get_child_count()==0,"First step highlights unique movable groups")
	main._select_card("G001");check(main.target_key=="parent" and main.interactions.picker.actions.all(func(a):return a.target=="G001"),"Second step retains selected group and asks for parent")
	main._select_card("G073");check(main.large_layer.has_node("ActionConfirmation") and g.nodes.G001.parent=="G005" and "P18" in g.hands[0].plot,"Review is unpaid and doesn't move anything")
	button(main.large_layer,"上一步").pressed.emit();check(main.target_key=="parent","Back retains earlier choice")
	main.interactions.cancel();check(g.nodes.G001.parent=="G005" and "P18" in g.hands[0].plot,"Cancel preserves the entire command")
	main._action_list(choices);main._select_card("G001");main._select_card("G073");button(main.large_layer,"确认").pressed.emit();main.modal_open=true
	for i in 5:
		if main.presentation_layer.find_child("TargetHighlight",true,false)!=null:break
		main.presentation_tween.pause();main.presentation_tween.custom_step(10)
	check(main.presentation_layer.find_child("TargetHighlight",true,false)!=null and g.nodes.G001.parent=="G005" and "P18" in g.hands[0].plot,"Target flight and highlight precede plot payment and movement")
	if capture_images:
		main.presentation_tween.pause();main.presentation_tween.custom_step(0.018);await take("target-flight")
	main.presentation_tween.play();await idle();check(g.nodes.G001.parent=="G073" and "P18" in g.discards.plot,"Reorganization commits once after flight")
	# Draw/discard batches are rehearsed without changing live hands, deck order or RNG.
	g=fresh();g.phase="draw";main._refresh();var decks_before=g.decks.duplicate(true);random_before=g.rng.state
	var draw=action(g,0,"draw",{"group":true,"plot":true});main._do_action(0,draw);main.modal_open=true;main.presentation_tween.pause();main.presentation_tween.custom_step(0.01)
	check(g.hands[0].group.is_empty() and g.hands[0].plot.is_empty() and g.decks==decks_before and g.rng.state==random_before,"Draw doesn't arrive logically while flight is running")
	await take("draw-flight")
	main._do_action(0,draw);main._schedule_ai();check(not main.thinking,"Input and AI blocked throughout card transfer")
	main.presentation_tween.play();await idle();check(g.hands[0].group.size()==1 and g.hands[0].plot.size()==1 and g.validate().is_empty(),"Both deck draws arrive after animation")
	var discard_id=g.hands[0].group[0];g._set_choice(0,"弃一张",[discard_id],"discard_group");main._refresh();main._do_action(0,action(g,0,"choose",{"id":discard_id}));main.modal_open=true;main.presentation_tween.pause()
	check(discard_id in g.hands[0].group and discard_id not in g.discards.group,"Discard remains uncommitted during flight")
	if capture_images:main.presentation_tween.custom_step(0.01);await take("discard-flight")
	main.presentation_tween.play();await idle();check(discard_id not in g.hands[0].group and discard_id in g.discards.group,"Discard commits at landing")
	g=fresh();g.current=1;g.phase="draw";main._refresh();main._do_action(1,action(g,1,"draw",{"group":true,"plot":true}));main.modal_open=true;main.presentation_tween.pause()
	check(main.presentation_layer.find_children("*","Control",true,false).all(func(n):return not n is CardView),"AI draw animation contains only anonymous backs")
	main._start_game(91);await process_frame;check(not main.busy and g.hands[1].group.is_empty() and g.hands[1].plot.is_empty(),"Restart cancels pending transfer without drawing into old match")
	# Nested attachment inspection returns to the same group and scroll offset.
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"desktop-tall","size":Vector2i(1600,1000),"compact":false},{"name":"mobile","size":Vector2i(2400,1080),"compact":true},{"name":"mobile-16x9","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact;g=fixture();main._resize();main.modal_open=true
		main._inspect("G025");await process_frame;var scroll=main.detail_layer.find_child("ReaderScroll",true,false);scroll.scroll_vertical=50;var offset=scroll.scroll_vertical
		var attachment=button(main.detail_layer,"监管调查 · 查看");check(attachment!=null,"Attached plot offers inspection")
		attachment.pressed.emit();await process_frame;check(main.interactions.reader_id=="P45" and text(main.detail_layer).contains("目标的GP视为0"),"Attached plot opens complete effect and cost")
		await take(profile.name+"-attachment");main._close_inspection();await process_frame;check(main.interactions.reader_id=="G025" and main.detail_layer.find_child("ReaderScroll",true,false).scroll_vertical==offset and main.modal_open,"Return restores original group, scroll and paused match")
		main._close_inspection();main._action_list(g.legal_actions(0).filter(func(a):return a.type=="plot" and a.id=="P18"));await take(profile.name+"-select-group");main._select_card("G001");await take(profile.name+"-select-parent");main._select_card("G073");await take(profile.name+"-confirm");main.interactions.cancel()
		main.collection_filter="group";main.interactions.catalog(true);await create_timer(0.2).timeout;await take(profile.name+"-catalog")
		for b in main.large_layer.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and b.get_parent() is not Container:check(Rect2(Vector2.ZERO,main.size).encloses(b.get_global_rect()),"Catalog fixed button inside viewport")
		main._clear(main.large_layer);main._start_game(81);main.game.act(0,main.game.legal_actions(0)[0]);main._refresh();main.modal_open=true;await take(profile.name+"-opening")
		var opening_buttons=main.overlay.find_children("*","Button",true,false)
		for b in opening_buttons:check(Rect2(Vector2.ZERO,main.size).encloses(b.get_global_rect()),"Opening and mulligan controls inside viewport")
	# Rehearsal purity and deterministic agreement across ordinary AI commands.
	var rehearsed=0
	for seed_value in range(5,9):
		g=GameState.new(seed_value);var bot=AiAgent.new();bot.rng.seed=seed_value
		for step in 100:
			if g.phase=="over":break
			var p=0 if not g.legal_actions(0).is_empty() else 1;var a=bot.pick(g.observation(p));var original=JSON.stringify([g.hands,g.decks,g.nodes,g.phase,g.rng.state]);var expected=ActionFlow.copy_state(g);expected.act(p,a)
			ActionFlow.plan(g,p,a);check(JSON.stringify([g.hands,g.decks,g.nodes,g.phase,g.rng.state])==original,"Presentation rehearsal is pure")
			g.act(p,a);check(g.hands==expected.hands and g.decks==expected.decks and g.nodes==expected.nodes and g.phase==expected.phase and g.rng.state==expected.rng.state and g.validate().is_empty(),"Rehearsed and live rules agree exactly");rehearsed+=1
	var report={"checks":checks,"failures":failures,"rehearsed_commands":rehearsed,"catalog_timings":timings,"captures":captures,"android_device_tested":false};FileAccess.open("res://tests/interaction-polish-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("INTERACTION POLISH: "+JSON.stringify(report));main.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
