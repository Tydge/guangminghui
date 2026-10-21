extends SceneTree
var checks=0
var failures=[]
var main
var captures=[]
var capture_images=false
var folder=ProjectSettings.globalize_path("user://test-captures/dice-sequence/")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize() -> void:call_deferred("run")
func pass_action(g: GameState,p: int) -> Dictionary:
	return g.legal_actions(p).filter(func(a):return a.type=="pass")[0]
func snapshot(g: GameState) -> String:
	return JSON.stringify([g.nodes,g.hands,g.decks,g.graves,g.destroyed,g.battle,g.last_battle,g.phase,g.winner,g.rng.state])
func fixture(mode: String,success: bool=true,victory: bool=false) -> GameState:
	main._start_game(81);var g=main.game
	g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I02","I03"];g.phase="main";g.current=0;g.turns=[3,3] if victory else [2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	for entry in [["G005",0,"R0"],["G001",1,"R1"],["G024",1,"G001"],["G025",1,"G024"]]:g.decks.group.erase(entry[0]);g._enter(entry[0],entry[1],entry[2],1)
	var attack=g.legal_actions(0).filter(func(a):return a.type=="attack" and a.src=="G005" and a.target=="G001" and a.mode==mode)[0]
	g.act(0,attack);g.battle.bonus_a=100 if success else -100;g.act(1,pass_action(g,1))
	for seed_value in range(1,20):
		g.rng.seed=seed_value
		if ActionFlow.plan(g,0,pass_action(g,0)).result.get("success",false)==success:break
	main.selected="G001";main.modal_open=true;main._refresh();main.board.reduced_motion=true;main.board.fit_all();main.board.pan=main.board.camera_target;main.board.zoom=main.board.zoom_target;main.board.camera_animating=false;main.board._process(1)
	return g
func take(label: String) -> void:
	if not capture_images:return
	await process_frame;await RenderingServer.frame_post_draw
	var path=folder+label+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func idle() -> void:
	var end=Time.get_ticks_msec()+4000
	while main.busy and Time.get_ticks_msec()<end:await process_frame
	check(not main.busy,"Settlement finishes and releases the input lock")
func run() -> void:
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	var mobile="--mobile" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(folder);root.size=Vector2i(1280,720) if mobile else Vector2i(1600,900)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.compact=mobile;main.sound_volume=0;main.presentation_time_scale=1.0
	for reduced in [false,true]:
		main.reduced_motion=reduced
		for mode in ["control","destroy"]:
			var g=fixture(mode);var a=pass_action(g,0);var planned=ActionFlow.plan(g,0,a).result
			var before=snapshot(g);var layout=main.board.targets.duplicate(true);var target_view=main.board.cards.G001
			main._do_action(0,a);main.modal_open=true;var dice_tween=main.presentation_tween;dice_tween.pause()
			check(main.presentation_layer.has_node("DiceResult") and main.busy,"Dice result begins before settlement: "+mode)
			check(snapshot(g)==before and main.board.targets==layout and main.board.cards.G001==target_view,"Live ownership, cards, RNG and board stay unchanged while dice are visible: "+mode)
			check(main.presentation_layer.find_child("MovingCard",true,false)==null,"No hand return or discard begins beneath dice: "+mode)
			main._do_action(0,a);main._schedule_ai();main._inspect("G001")
			check(not main.thinking and main.detail_layer.get_child_count()==0 and snapshot(g)==before,"Input and AI cannot advance the dice result")
			dice_tween.custom_step(0.20)
			await take(mode+("-reduced" if reduced else "-normal")+"-dice")
			var panel=main.presentation_layer.get_node("DiceResult");var hold=0.5 if reduced else 1.4;var fade=0.06 if reduced else 0.16
			dice_tween.custom_step(hold-0.20+fade*0.5)
			check(panel.modulate.a>0 and panel.modulate.a<1 and snapshot(g)==before and main.board.targets==layout,"Settlement waits through the complete dice-window fade: "+mode)
			main._resize();check(main.presentation_layer.has_node("DiceResult") and snapshot(g)==before,"Resize does not commit the pending result")
			dice_tween.custom_step(fade+0.1)
			check(not main.presentation_layer.has_node("DiceResult"),"Dice window is removed before aftermath: "+mode)
			if mode=="destroy":
				check(main.busy and snapshot(g)==before and main.presentation_layer.find_child("MovingCard",true,false)!=null,"Descendant return begins only after dice close, before live settlement")
			await idle();main.modal_open=true
			check(g.last_battle.dice==planned.dice and g.last_battle.success,"Displayed rehearsal matches the eventual real roll")
			if mode=="control":check(g.owner("G001")==0 and g.owner("G024")==0 and g.owner("G025")==0 and g.nodes.G001.parent=="G005","Control transfers the entire branch after the result closes")
			else:check(not g.nodes.has("G001") and "G001" in g.graves[0] and "G024" in g.hands[1].group and "G025" in g.hands[1].group,"Destruction and descendant return settle after the result closes")
			check(g.validate().is_empty(),"Post-dice settlement conserves cards")
			await take(mode+("-reduced" if reduced else "-normal")+"-settled")
	# Failed attacks with no roll, and decisive attacks which overwrite last_event.
	for victory in [false,true]:
		main.reduced_motion=true;var g=fixture("destroy",victory,victory);var before=snapshot(g);main._do_action(0,pass_action(g,0));main.modal_open=true
		main.presentation_tween.pause();check(main.presentation_layer.has_node("DiceResult") and snapshot(g)==before,"Failure and victory both defer state until their result closes")
		main.presentation_tween.custom_step(1);await idle();main.modal_open=true
		check(g.phase=="over" and g.winner==0 if victory else g.nodes.has("G001") and not g.last_battle.success,"Victory screen or failed attack follows, never precedes, the dice window")
	# Restart cancels even while the dice window is partially fading.
	var g=fixture("control");var before=snapshot(g);main._do_action(0,pass_action(g,0));main.presentation_tween.pause();main.presentation_tween.custom_step(0.53)
	main._start_game(92);await process_frame;await process_frame
	check(main.game!=g and snapshot(g)==before and not main.busy and not main.presenting and not main.presentation_layer.has_node("DiceResult"),"Restart cancels the pending roll and cannot mutate the old match")
	var report={"checks":checks,"failures":failures,"captures":captures};FileAccess.open("res://tests/dice-sequence-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("DICE SEQUENCE: "+JSON.stringify(report));main.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
