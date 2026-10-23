extends SceneTree
var main
var checks=0
var failures=[]
var output=""
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func wait_for(predicate: Callable,label: String,seconds: float=6) -> bool:
	var end=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end:await process_frame
	var okay=predicate.call();check(okay,label);return okay
func idle():return await wait_for(func():return not main.busy,"Input unlocks after the complete cue and settlement")
func fresh() -> GameState:
	main._start_game(81);var g=main.game
	g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I02","I03"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	for entry in [["G005",0,"R0"],["G004",0,"R0"],["G001",1,"R1"],["G002",1,"R1"]]:g.decks.group.erase(entry[0]);g._enter(entry[0],entry[1],entry[2],1)
	g.decks.group.erase("G043");g.hands[0].group.append("G043")
	main.modal_open=true;main._refresh();main.board._process(100);main.board.camera_animating=false
	return g
func snapshot(g: GameState) -> String:return JSON.stringify([g.nodes,g.hands,g.decks,g.battle,g.last_battle,g.phase,g.rng.state,g.used])
func action(g: GameState,p: int,kind: String,values: Dictionary={}) -> Dictionary:
	return g.legal_actions(p).filter(func(a):return a.type==kind and values.keys().all(func(k):return a.get(k)==values[k]))[0]
func capture(name: String):
	if output=="" or DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output+"/"+name+".png")
func launch(g: GameState,target: String,mode: String) -> bool:
	var before=snapshot(g);main._do_action(0,action(g,0,"attack",{"src":"G005","target":target,"mode":mode}));main.modal_open=true
	if not await wait_for(func():return main.combat.stage=="trace","Arrow follows source framing"):return false
	main.presentation_tween.pause();await process_frame
	check(snapshot(g)==before and main.busy and not main.board.interaction_enabled,"Arrow plays before any cost, rule or RNG commit")
	check(main.board.zoom<=1.0 and main.board.zoom>=0.45 if not main.reduced_motion else main.board.zoom>0,"Source framing uses moderate zoom")
	check(main.board.get_global_rect().grow(1).encloses(main.board.cards.G005.get_global_rect()),"Source card visible before tracking")
	var duration=0.24 if main.reduced_motion else clampf(0.55+main.combat.point("G005").distance_to(main.combat.point(target))/1000,0.75,1.6)
	var pan=main.board.pan;main.presentation_tween.custom_step(((0.05 if main.reduced_motion else 0.15)+duration*0.55)*main.presentation_time_scale)
	check(main.combat.progress>0 and main.combat.progress<1,"Arrow grows progressively")
	if not main.reduced_motion:check(main.board.pan.distance_to(pan)>1,"Camera follows the moving arrow")
	check(snapshot(g)==before,"Partial arrow progress leaves real state unchanged")
	var extent=root.size;root.size+=Vector2i(32,24);await process_frame;main._resize()
	check(main.combat.stage=="trace" and main.combat.attack.target==target and snapshot(g)==before,"Resizing preserves the in-flight arrow and pending command")
	root.size=extent;await process_frame
	await capture(("mobile" if main.compact else "desktop")+"-"+mode+("-reduced" if main.reduced_motion else ""))
	main.presentation_tween.play()
	if not await idle():return false
	main.modal_open=true
	check(not g.token("G005") and not g.battle.is_empty(),"Attack starts exactly once after its cue")
	check(main.combat.attack.is_empty() and main.combat.stage=="","Arrow clears before response controls")
	return true
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(output)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.presentation_time_scale=0.25
	if "--english" in OS.get_cmdline_user_args():GameLocale.set_language("en")
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;main.compact=profile.compact;main._resize()
		for reduced in [false,true]:
			main.reduced_motion=reduced
			for mode in ["control","destroy"]:
				var g=fresh();main.board.pan=Vector2(-4000,3000);main.board.zoom=0.3
				if not await launch(g,"G001",mode):main.queue_free();quit(1);return
				check(g.validate().is_empty(),"Board attack preserves cards "+profile.name+mode)
			# A hand target is a public ghost throughout the battle; failure returns it.
			for success in [false,true]:
				var g=fresh();var before=snapshot(g)
				var camera_center=(main.board.size/2-main.board.pan)/main.board.zoom;var camera_zoom=main.board.zoom
				var plan=ActionFlow.plan(g,0,action(g,0,"attack",{"src":"G005","target":"G043","mode":"control"}))
				check(plan.attack.hand_target and not plan.board_after.has("G043") and plan.board_after.keys()==g.nodes.keys(),"Hand attack plan creates no future rule node")
				if not await launch(g,"G043","control"):main.queue_free();quit(1);return
				check(main.combat.ghost_id=="G043" and not g.nodes.has("G043") and not main.board.cards.has("G043") and "G043" not in g.hands[0].group,"Revealed recruit is a separate visual, not an owned group")
				for id in main.board.targets:check(not Rect2(main.combat.ghost_point-main.board.card_size/2,main.board.card_size).grow(6).intersects(Rect2(main.board.targets[id]-main.board.card_size/2,main.board.card_size)),"Recruit preview never covers an existing card")
				main.combat.ghost.inspected.emit("G043");check(main.interactions.reader_id=="G043","Public recruit can be inspected while choosing responses");main._close_inspection();main.modal_open=true
				g.battle.bonus_a=100 if success else -100;g.battle.rolled=[1,1] if success else [6,6];g.act(1,action(g,1,"pass"))
				var resolve=action(g,0,"pass");plan=ActionFlow.plan(g,0,resolve)
				check(plan.moves.any(func(e):return e.id=="G043" and e.from=="recruit" and e.to==("board" if success else "hand")),"Recruit outcome has one explicit landing")
				before=snapshot(g);main._do_action(0,resolve);main.modal_open=true
				main.presentation_tween.pause();check(main.presentation_layer.has_node("DiceResult") and snapshot(g)==before and main.combat.ghost_id=="G043","Dice precede recruit return or placement")
				main.presentation_tween.custom_step(10)
				if not await wait_for(func():return main.presentation_layer.find_child("MovingCard",true,false)!=null,"Recruit flies only after dice fully disappear"):main.queue_free();quit(1);return
				check(snapshot(g)==before and not main.presentation_layer.has_node("DiceResult"),"Recruit flight precedes true resolution")
				if not await idle():main.queue_free();quit(1);return
				check(main.combat.ghost_id=="" and not is_instance_valid(main.combat.ghost),"Temporary recruit is removed after resolution")
				check(g.nodes.has("G043") if success else "G043" in g.hands[0].group,"Recruit is owned on success or restored to hand on failure")
				if success:check(main.board.positions.G043==main.board.targets.G043 and main.board.cards.G043.modulate.a==1,"Successful flight lands without a second entry animation")
				else:check(absf(main.board.zoom-camera_zoom)<0.001 and ((main.board.size/2-main.board.pan)/main.board.zoom).distance_to(camera_center)<0.5,"Failed recruit restores the previous camera while returning to hand")
				check(g.validate().is_empty(),"Recruit outcome conserves all cards")
		# Actual support, with a bright outline on both participants and a real value.
		main.reduced_motion=false;var g=fresh();g.act(0,action(g,0,"attack",{"src":"G005","target":"G001","mode":"control"}));g.act(1,action(g,1,"pass"));main._refresh();main.board._process(100)
		var support=action(g,0,"support",{"src":"G004"});var detail=g.support_detail("G004",g.battle);var before=snapshot(g)
		main._do_action(0,support);main.modal_open=true
		if not await wait_for(func():return main.combat.stage=="support","Support highlight follows camera framing"):main.queue_free();quit(1);return
		main.presentation_tween.pause();main.presentation_tween.custom_step(0.09)
		check(main.combat.glow.src=="G004" and main.combat.glow.target=="G005" and main.combat.glow.power==detail.power and main.combat.glow.basis==detail.basis,"Support highlights the supporter and actual recipient, using exact effective power")
		check(main.combat.glow_amount>0.8 and snapshot(g)==before and not main.overlay.visible,"Support flashes before costs, with battle window hidden")
		await capture(profile.name+"-support")
		main.presentation_tween.play();await idle();main.modal_open=true;check(not g.token("G004"),"Support cost commits after highlight")
		# Automatic takeover has no attack arrow. Restart cancels an in-flight declaration.
		g=fresh();var auto=action(g,0,"auto",{"id":"G043"});check(ActionFlow.plan(g,0,auto).attack.is_empty(),"Automatic takeover never gets an attack arrow")
		main._do_action(0,action(g,0,"attack",{"src":"G005","target":"G043","mode":"control"}));main.modal_open=true
		if not await wait_for(func():return main.combat.stage=="trace","Restart fixture reaches arrow"):main.queue_free();quit(1);return
		before=snapshot(g);main._start_game(82);await process_frame
		check(snapshot(g)==before and main.combat.ghost_id=="" and main.combat.attack.is_empty() and not main.busy,"Restart cancels ghost, arrow, camera and pending rule commit")
	main._menu();main.queue_free();await process_frame;await process_frame
	if GameLocale.english():check(GameLocale.missing.is_empty(),"No untranslated animation labels")
	print("ATTACK PRESENTATION: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
