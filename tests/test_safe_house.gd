extends "res://tests/test_resources.gd"
var main
var folder=""
func _initialize() -> void:call_deferred("run")
func snapshot(g: GameState) -> String:return JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.scrap,g.battle,g.last_battle,g.phase,g.used,g.wave.queue,g.wave.response_queue,g.rng.state])
func fixture(defender: int=1) -> GameState:
	var g=fresh();g.current=1-defender
	put(g,"G023",1-defender);put(g,"G067",defender);put(g,"G043",defender,"G067");put(g,"E16",defender)
	return g
func start(g: GameState,mode: String="control"):
	apply(g,g.current,"attack",{"src":"G023","target":"G067","mode":mode})
func rules():
	for defender in [0,1]:
		var g=fixture(defender);check(g.resource_hand_limit(defender)==2,"Safe House removes the old Warehouse capacity bonus")
		check(action(g,defender,"resource",{"src":"E16"}).is_empty(),"No Safe House response outside combat")
		start(g);var a=action(g,defender,"resource",{"src":"E16"});check(not a.is_empty(),"Either player can evacuate a defending Group")
		check(g.legal_actions(defender).back().type=="pass","Pass remains last after Safe House response")
		check(g.resources.reader("E16").contains("可在本次防守响应时使用"),"Reader reports current response eligibility")
		apply(g,defender,"pass");apply(g,1-defender,"support",{"src":g.root(1-defender)})
		g.decks.plot.erase("P39");g.nodes.G043.attached.append("P39");g.nodes.G043.learned=2
		g.decks.plot.erase("P01");g.battle.spent.append("P01")
		var before=snapshot(g);var command=a.duplicate(true);var plan=ActionFlow.plan(g,defender,a)
		check(snapshot(g)==before and a==command,"Rehearsal preserves live state, RNG and caller command")
		check(plan.result.get("cancelled",false) and plan.result.dice.is_empty(),"Cancellation plan has no dice result")
		check(plan.moves.any(func(e):return e.id=="E16" and e.to=="scrap"),"Plan animates Safe House scrapping")
		for id in ["G067","G043"]:
			check(plan.moves.any(func(e):return e.id==id and e.to=="hand" and e.player==defender),"Whole branch returns to the correct hand "+id)
		check(plan.moves.any(func(e):return e.id=="P39" and e.to=="discard"),"Attached Plot is discarded on departure")
		check(plan.camera_ids.has("E16") and plan.camera_ids.has("G043") and plan.source=="E16" and plan.target=="G067","Camera and target cue cover resource and branch")
		var rng_before=g.rng.state;check(g.act(defender,a),"Evacuation commits")
		check(g.battle.is_empty() and g.phase=="main" and g.last_battle.cancelled,"Cancellation returns to attacker's main phase")
		check(g.last_battle.dice.is_empty() and g.rng.state==rng_before,"No dice or real RNG advancement")
		check("E16" in g.scrap and "E16" not in g.discards.resource and not g.nodes.has("E16"),"Safe House goes to unrecoverable scrap")
		check(["G067","G043"].all(func(k):return k in g.hands[defender].group and not g.nodes.has(k)),"Target and descendants return together")
		check("P39" in g.discards.plot and "P01" in g.discards.plot,"Attachments and spent combat Plots are cleaned up")
		check(not g.token("G023") and not g.token(g.root(1-defender)) and g.destroyed==[0,0] and g.graves==[[],[]],"Paid attack and support stay spent; no destruction credited")
		check(g.wave.queue.is_empty() and g.choice.is_empty(),"No Dentist failure or completed-combat recovery triggers")
		check(g.last_battle.entries.back().id=="E16" and g.last_battle.entries.back().target=="G067","History records source and evacuated target")
		check(g.validate().is_empty(),"Conservation after cancellation "+str(g.validate()))
	var g=fixture();start(g,"destroy");check(action(g,1,"resource",{"src":"E16"}).is_empty(),"No response to Destroy")
	g=fixture();put(g,"G071",1);give(g,"P31");apply(g,0,"plot",{"id":"P31","payer":"G023","target":"G071"});check(action(g,1,"resource",{"src":"E16"}).is_empty(),"No response to disasters")
	g=fixture();start(g);g.nodes.E16.silenced=true;check(action(g,1,"resource",{"src":"E16"}).is_empty(),"Silenced Safe House cannot respond")
	g=fixture();start(g);g.battle.responder=0;check(action(g,0,"resource",{"src":"E16"}).is_empty(),"Attackers cannot evacuate the opposing target")
	g=fresh();put(g,"G023");put(g,"E16",1);give(g,"G067");apply(g,0,"attack",{"src":"G023","target":"G067","mode":"control"});check(action(g,1,"resource",{"src":"E16"}).is_empty(),"No response to recruitment from hand")
	g=fixture();start(g);var ai=AiAgent.new();ai.difficulty="hard";g.nodes.G067.token=0;g.nodes.G043.token=0;g.nodes.R1.token=0
	g.battle.bonus_a=40;check(ai.pick(g.observation(1)).get("src","")=="E16","AI evacuates a branch under overwhelming capture pressure")
	g.battle.bonus_a=-40;check(ai.pick(g.observation(1)).type=="pass","AI preserves Safe House against impossible attacks")
	g.battle.bonus_a=40;g.battle.fixed_dice=[6,6];check(ai.pick(g.observation(1)).type=="pass","AI honors a fixed failing roll instead of wasting Safe House")
func labels(node: Node) -> String:
	var out=""
	for child in node.find_children("*","Label",true,false)+node.find_children("*","Button",true,false):out+=child.text+"\n"
	return out
func capture(name: String):
	if folder=="" or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/"+name+".png")
func ui():
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	main.sound_volume=0;main.presentation_time_scale=0.12;main.board.motion_time_scale=0.06
	for english in [false,true]:
		GameLocale.set_language("en" if english else "zh")
		for compact in [false,true]:
			root.size=Vector2i(1280,720) if compact else Vector2i(1600,900)
			for defender in [0,1]:
				main._start_game(39);main.modal_open=true;main.thinking=false;main.compact=compact
				var g=fixture(defender);start(g);main.game=g;main._resize();main._refresh();main.board.fit_all()
				await process_frame;await process_frame
				if defender==0:
					main._inspect("E16");CardDB.finish_art_requests();await capture(("en" if english else "zh")+("-compact" if compact else "-desktop")+"-card");main._close_inspection();main.modal_open=true
				var a=action(g,defender,"resource",{"src":"E16"});var before=snapshot(g);main.modal_open=false
				main._do_action(defender,a);main.presentation_tween.pause();await process_frame
				check(main.busy and snapshot(g)==before,"Reveal keeps live branch and RNG unchanged")
				check(main.presentation_layer.find_child("PresentedCard",true,false)!=null,"Safe House gets a source-card reveal")
				main.presentation_tween.play();var deadline=Time.get_ticks_msec()+7000;var saw_moves=false;var saw_hidden_window=false;var saw_dice=false;var unchanged=true
				while main.busy and Time.get_ticks_msec()<deadline:
					saw_dice=saw_dice or main.presentation_layer.find_child("DiceResult",true,false)!=null
					if not main.interactions.dimmed.is_empty():
						saw_moves=true;saw_hidden_window=saw_hidden_window or not main.overlay.visible
						unchanged=unchanged and snapshot(g)==before
					await process_frame
				main.modal_open=true
				check(not main.busy and main.board.is_settled(),"Settles before unlocking input")
				check(unchanged,"No live result during return/scrap flights")
				check(saw_moves and not saw_dice,"Return flights without a fake dice outcome")
				check(saw_hidden_window,"Combat window hides during flights")
				check(g.last_battle.cancelled and not main.board.cards.has("G043"),"Only settled state removes branch")
				main._battle_history();await process_frame
				check(labels(main.large_layer).contains("Attack cancelled" if english else "攻击取消"),"History shows cancellation, not failure")
				check(labels(main.large_layer).contains("Safe House" if english else "安全屋"),"History identifies Safe House")
				await capture(("en" if english else "zh")+("-compact" if compact else "-desktop")+"-"+str(defender));main._clear(main.large_layer)
	CardDB.finish_art_requests();main.queue_free();await process_frame;await process_frame
func run():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output=" ):folder=a.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	CardDB.load_all();rules();await ui()
	print("SAFE HOUSE TESTS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
