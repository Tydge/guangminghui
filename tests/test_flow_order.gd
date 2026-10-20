extends SceneTree
var main
var checks=0
var failures=[]
var captures=[]
var capture_images=false
var folder=ProjectSettings.globalize_path("user://test-captures/flow-order/")
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
func fresh() -> GameState:
	main._start_game(81);var g=main.game
	g.nodes={};g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.factions=["I02","I03"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	main.modal_open=true;return g
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func snapshot(g: GameState) -> String:
	return JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.graves,g.phase,g.choice,g.battle,g.winner,g.rng.state,g.wave.queue])
func button(layer: Node,value: String) -> Button:
	for b in layer.find_children("*","Button",true,false):
		if b.text==value:return b
	return null
func texts(layer: Node) -> String:
	return "\n".join(layer.find_children("*","Label",true,false).map(func(n):return n.text))
func idle() -> void:
	var deadline=Time.get_ticks_msec()+6000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Flow finishes and releases input")
func transition() -> void:
	var deadline=Time.get_ticks_msec()+2000
	while main.window_access.transitioning and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.window_access.transitioning,"Window transition finishes")
func settle() -> void:
	main._refresh();main.board._process(100);await main.board.wait_for_settlement()
func finish_cues() -> void:
	for i in 16:
		if not main.presenting:return
		var tween=main.presentation_tween;tween.pause();tween.custom_step(100)
func take(name: String) -> void:
	if not capture_images:return
	await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func battle(g: GameState,src: String,target: String,mode: String) -> void:
	g.act(0,action(g,0,"attack",{"src":src,"target":target,"mode":mode}));g.battle.bonus_a=100;g.battle.rolled=[2,2];g.act(1,action(g,1,"pass"));main._refresh()
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless";DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.presentation_time_scale=0.12;main.reduced_motion=false
	# Choice windows are parked, not destroyed. Inspecting and camera movement are read-only.
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact
		var g=fresh();put(g,"G072",0,"R0");put(g,"G005",1,"R1");give(g,"P18",0);give(g,"G043",0);main._refresh()
		await main._do_action(0,action(g,0,"ability",{"src":"G072"}));main.modal_open=true
		check(g.phase=="choice" and g.choice.peek.size()==4,"Content export opens a real private card choice")
		var pending=snapshot(g);var original=main.overlay.get_child(1)
		var scrollers=main.overlay.find_children("*","ScrollContainer",true,false);var scroll=scrollers[0];scroll.scroll_horizontal=80;var offset=scroll.scroll_horizontal
		button(main.overlay,"查看战场").pressed.emit();await transition()
		check(main.window_access.browsing and not main.overlay.visible and not main.large_layer.visible,"Choice can be temporarily hidden")
		check(button(main.hud,"返回操作窗口")!=null and button(main.hud,"结束回合  →")==null,"Read-only browsing has one clear return control")
		var pan=main.board.pan;var zoom=main.board.zoom;main.board.zoom_at(1.15,main.board.size/2);main.board.pan+=Vector2(50,-40)
		check(main.board.pan!=pan and main.board.zoom!=zoom and main.board.interaction_enabled,"Paused battlefield allows pan and zoom")
		main._select_card("G005");main._inspect("G005");check(main.interactions.reader_id=="G005","Opponent card remains inspectable while choice is parked");main._close_inspection()
		button(main.hand_layer,main._hand_tab_labels()[1]).pressed.emit();main._select_card("P18");main._inspect("P18");check(main.interactions.reader_id=="P18","Hand can be switched and inspected while paused");main._close_inspection()
		main._do_action(0,g.legal_actions(0)[0]);main._schedule_ai();main._perform_type("end")
		check(snapshot(g)==pending and not main.thinking,"Pending choice, RNG, costs and decks cannot advance during browsing")
		await take(profile.name+"-battlefield")
		button(main.hud,"返回操作窗口").pressed.emit();await transition();main.modal_open=true
		check(main.overlay.visible and main.overlay.get_child(1)==original and scroll.scroll_horizontal==offset and snapshot(g)==pending,"Returning restores the exact choice controls and scroll position")
		await take(profile.name+"-choice")
		# Multi-step plots keep their chosen target, history and confirmation through browsing.
		g=fresh();put(g,"G005",0,"R0");put(g,"G025",0,"R0");put(g,"G001",0,"G005");put(g,"G002",1,"R1");give(g,"P18",0);give(g,"P14",0);main._refresh()
		main._action_list(g.legal_actions(0).filter(func(a):return a.type=="plot" and a.id=="P18"));main._select_card("G001");main._select_card("G025")
		var picker=main.interactions.picker;var chosen=JSON.stringify([picker.actions,picker.chosen,picker.history]);original=main.large_layer.get_node("ActionConfirmation")
		button(main.large_layer,"查看战场").pressed.emit();await transition();main._select_card("G002");main.window_access.resume();await transition();main.modal_open=true
		check(main.large_layer.get_node("ActionConfirmation")==original and JSON.stringify([picker.actions,picker.chosen,picker.history])==chosen,"Reorganization confirmation and earlier selections survive browsing")
		# Resize rebuilds to the current viewport without losing the command.
		main.window_access.peek();await transition();root.size=Vector2i(1440,810);await process_frame;main._resize();main.window_access.resume();await transition();main.modal_open=true
		check(main.large_layer.has_node("ActionConfirmation") and JSON.stringify([picker.actions,picker.chosen,picker.history])==chosen,"Resize while browsing retains pending multi-step command")
		var confirm=main.large_layer.get_node("ActionConfirmation");check(Rect2(Vector2.ZERO,main.size).encloses(confirm.get_global_rect()),"Restored confirmation fits resized viewport")
		main.interactions.cancel()
		# Combat plots fly to an unobscured battlefield, then restore the response window.
		g=fresh();put(g,"G005",0,"R0");put(g,"G001",1,"R1");give(g,"P01",0);battle(g,"G005","G001","control");g.battle.passes=0
		main.floating_positions.battle=Vector2(40,165);main._refresh();var position=main.overlay.get_node("BattleWindow").position
		var response=snapshot(g);button(main.overlay,"查看战场").pressed.emit();await transition();main._schedule_ai();check(snapshot(g)==response and main.window_access.browsing,"Battle responses pause while looking around");main.window_access.resume();await transition();main.modal_open=true
		var plot=action(g,0,"plot",{"id":"P01"});pending=snapshot(g);main._do_action(0,plot);main.modal_open=true;main.presentation_tween.pause()
		check(not main.overlay.visible and main.busy and snapshot(g)==pending,"Battle window is hidden throughout plot reveal without paying early")
		for i in 8:
			if main.presentation_layer.has_node("TargetHighlight"):break
			main.presentation_tween.pause();main.presentation_tween.custom_step(100)
		check(main.presentation_layer.has_node("TargetHighlight") and not main.overlay.visible and snapshot(g)==pending,"Target flight is unobscured and rules wait for arrival")
		main.presentation_tween.pause();main.presentation_tween.custom_step(0.015);await take(profile.name+"-plot-target");finish_cues();await idle();main.modal_open=true
		check(main.overlay.visible and main.overlay.has_node("BattleWindow") and main.overlay.get_node("BattleWindow").position==position,"Battle response returns to its dragged position after effects")
	# Victory never covers the deciding control transfer, in either motion mode.
	for reduced in [false,true]:
		main.reduced_motion=reduced;var g=fresh();g.turns=[3,3];put(g,"G005",0,"R0");put(g,"G001",1,"R1");put(g,"G024",1,"G001");await settle();battle(g,"G005","G001","control")
		main.board.set_process(false);main._do_action(0,action(g,0,"pass"));main.modal_open=true;main.presentation_tween.pause()
		check(g.phase=="battle" and not texts(main.overlay).contains("计划得逞"),"Deciding roll is shown before real victory")
		finish_cues();check(main.busy and not main.board.is_settled() and g.phase=="over" and not main.overlay.visible,"Victory waits for branch transfer to finish")
		main._phase_overlay();main._victory_overlay();check(not texts(main.overlay).contains("计划得逞"),"Phase refresh cannot bypass the presentation lock")
		main.board.set_process(true);await idle();main.modal_open=true
		check(texts(main.overlay).contains("计划得逞") and main.board.is_settled() and g.owner("G024")==0,"Victory appears after the complete branch has landed")
	# The AI's deciding attack follows exactly the same gates.
	var ai_game=fresh();ai_game.current=1;ai_game.turns=[3,3];put(ai_game,"G005",1,"R1");put(ai_game,"G001",0,"R0");await settle()
	ai_game.act(1,action(ai_game,1,"attack",{"src":"G005","target":"G001","mode":"control"}));ai_game.battle.bonus_a=100;ai_game.battle.rolled=[2,2];ai_game.act(0,action(ai_game,0,"pass"));main._refresh()
	main.board.set_process(false);main._do_action(1,action(ai_game,1,"pass"));main.modal_open=true;main.presentation_tween.pause();check(ai_game.phase=="battle","AI victory waits for visible dice");finish_cues()
	check(main.busy and not main.overlay.visible and ai_game.winner==1,"AI victory window also waits for its transfer")
	main.board.set_process(true);await idle();main.modal_open=true;check(texts(main.overlay).contains("暗流反噬"),"AI victory is announced after landing")
	# Destroy rewards have a separate source cue and draw, after exits, before victory.
	main.reduced_motion=false;var g=fresh();g.turns=[3,3];put(g,"G052",0,"R0");put(g,"G001",1,"R1");put(g,"G024",1,"G001");await settle();battle(g,"G052","G001","destroy")
	main._do_action(0,action(g,0,"pass"));main.modal_open=true;finish_cues()
	for tween in main.board.visual_tweens:tween.pause()
	check(main.busy and g.phase=="choice" and g.choice.source=="G052" and g.hands[0].group.is_empty(),"Street gang reward is queued, without drawing during destruction")
	check(not main.overlay.visible and not main.presenting and "G024" in g.hands[1].group,"Descendant return precedes reward cue and destruction finishes under the input lock")
	for tween in main.board.visual_tweens:tween.play()
	await idle();main.modal_open=true;check(g.winner==-2 and not texts(main.overlay).contains("计划得逞"),"Victory checks wait for outstanding post-battle rewards")
	var before=snapshot(g);main._do_action(0,action(g,0,"trigger"));main.modal_open=true;main.presentation_tween.pause()
	check(main.presentation_layer.has_node("RevealBody") and snapshot(g)==before and main.board.is_settled(),"Reward source is shown only after the board settles; draw remains uncommitted")
	main.presentation_tween.custom_step(100);main.presentation_tween.pause();check(main.presentation_layer.has_node("MovingCard") and g.hands[0].group.is_empty(),"Reward draw flight follows its source cue and precedes the real draw")
	finish_cues();await idle();main.modal_open=true
	check(g.hands[0].group.size()==1 and g.phase=="over" and texts(main.overlay).contains("计划得逞") and g.validate().is_empty(),"Reward draw completes once, then victory is announced")
	# Entry rewards also wait for entry/layout motion, not only battle outcomes.
	g=fresh();put(g,"G044",0,"R0");put(g,"G001",1,"R1");give(g,"G023",0);await settle();main.board.set_process(false)
	main._do_action(0,action(g,0,"auto",{"id":"G023","parent":"R0"}));main.modal_open=true;finish_cues()
	check(main.busy and g.choice.get("source","")=="G044" and g.hands[0].group.is_empty(),"Recruitment reward is deferred until the new group has appeared")
	main.board.set_process(true);await idle();main.modal_open=true;main._do_action(0,action(g,0,"trigger"));main.modal_open=true;finish_cues();await idle();main.modal_open=true
	check(g.hands[0].group.size()==1 and g.validate().is_empty(),"Entry reward settles through the same source/draw queue")
	# Legacy control dividends and computer support recovery use deferred commands too.
	for entry in [["G014","G017","plot"],["G023","G024","group"]]:
		g=fresh();put(g,entry[0],0,"R0");give(g,entry[1],0);await settle();battle(g,entry[0],entry[1],"control")
		main._do_action(0,action(g,0,"pass"));main.modal_open=true;finish_cues();await idle();main.modal_open=true
		check(g.choice.get("source","")==entry[0] and g.hands[0][entry[2]].is_empty(),"Control dividend waits for its own source cue: "+entry[0])
		main._do_action(0,action(g,0,"trigger"));main.modal_open=true;finish_cues();await idle();main.modal_open=true
		check(g.hands[0][entry[2]].size()==1 and g.validate().is_empty(),"Control dividend is paid exactly once: "+entry[0])
	g=fresh();put(g,"G021",0,"R0");put(g,"G024",0,"G021");give(g,"G043",0);await settle()
	g.act(0,action(g,0,"attack",{"src":"G021","target":"G043","mode":"control"}));g.act(1,action(g,1,"pass"));g.act(0,action(g,0,"support",{"src":"G024"}));g.battle.bonus_a=100;g.battle.rolled=[2,2];g.act(1,action(g,1,"pass"));main._refresh()
	main._do_action(0,action(g,0,"pass"));main.modal_open=true;finish_cues();await idle();main.modal_open=true
	check(not g.token("G024") and g.choice.get("source","")=="G024","Video game recovery is queued after recruitment")
	main._do_action(0,action(g,0,"trigger"));main.modal_open=true;main.presentation_tween.pause();check(not g.token("G024"),"Recovery does not pay before its source cue ends");finish_cues();await idle();main.modal_open=true
	check(g.token("G024") and g.recharged.has("G024"),"Recovery pays after the source cue and retains its quota")
	# Two rewards cannot overtake each other's source reveal or draw flight.
	g=fresh();put(g,"G052",0,"R0");put(g,"G122",0,"R0");g.synergy.add_tag("G052","军队");put(g,"G001",1,"R1");await settle();battle(g,"G052","G001","destroy")
	main._do_action(0,action(g,0,"pass"));main.modal_open=true;finish_cues();await idle();main.modal_open=true
	for source in ["G052","G122"]:
		check(g.choice.get("source","")==source,"Chained reward source retains queue order: "+source)
		var state=snapshot(g);main._do_action(0,action(g,0,"trigger"));main.modal_open=true;main.presentation_tween.pause();check(snapshot(g)==state,"Chained reward waits through its source cue: "+source);finish_cues();await idle();main.modal_open=true
	check(g.hands[0].group.size()==1 and g.hands[0].plot.size()==1 and g.validate().is_empty(),"Both rewards resolve once through separate presentations")
	# Disaster preview can also be parked and rebuilt on resize.
	g=fresh();put(g,"G043",0,"R0");put(g,"G093",1,"R1");give(g,"P31",0);main._refresh();var disaster=action(g,0,"plot",{"id":"P31"});main._review_action(disaster);main.window_access.peek();await transition();root.size=Vector2i(1520,860);await process_frame;main._resize();main.window_access.resume();await transition();main.modal_open=true
	check(main.preview_action==disaster and button(main.large_layer,"发动灾难")!=null,"Disaster preview keeps its unpaid command through browse and resize")
	# Restart while layout is moving cancels the waiting flow without touching a new match.
	g=fresh();put(g,"G005",0,"R0");give(g,"G001",0);await settle();main.board.set_process(false);main._do_action(0,action(g,0,"auto",{"id":"G001","parent":"G005"}));main.modal_open=true;finish_cues();check(main.busy and main.board.settling,"Board wait is active before restart")
	main._start_game(98);main.board.set_process(true);await process_frame;check(not main.busy and not main.board.settling and main.game!=g and main.game.phase=="setup_faction","Restart cancels the board wait and cannot unlock or advance a later match")
	# A restart cancels a parked window, its transition, and any board wait.
	g=fresh();g._set_choice(0,"测试",[g.decks.group[0]],"discard_group");main._refresh();main.window_access.peek();main._start_game(99);await process_frame
	check(not main.window_access.browsing and not main.window_access.transitioning and main.overlay.visible and main.game.phase=="setup_faction","Restart cancels pending browse transition without restoring the old window")
	var report={"checks":checks,"failures":failures,"captures":captures};FileAccess.open("res://tests/flow-order-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("FLOW ORDER: "+JSON.stringify(report));main.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
