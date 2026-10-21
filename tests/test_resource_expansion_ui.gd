extends "res://tests/test_resources_ui.gd"

func idle() -> void:
	while main.busy:await process_frame
	main.modal_open=true
func settle() -> void:
	main._refresh();await main.board.wait_for_settlement();await process_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.04;main.board.motion_time_scale=0.04
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		print("UI profile: "+profile.name);root.size=profile.size;main.compact=profile.compact;main._start_game(22)
		var g=main.game;g.act(0,g.legal_actions(0)[0]);g.act(0,g.legal_actions(0)[0]);main.modal_open=true;main._resize();main._refresh();await process_frame
		check(g.phase=="setup_resource" and labels(main.overlay).contains("选择初始资源"),"Opening resources follow groups "+profile.name)
		var faces=main.overlay.find_children("*","Control",true,false).filter(func(n):return n is CardView)
		check(faces.size()==5,"Five resource candidates visible "+profile.name)
		for face in faces:check(main.get_global_rect().encloses(face.get_global_rect()),"Candidate within viewport "+profile.name)
		faces[0].selected.emit(faces[0].id);check(g.phase=="setup_resource" and main.detail_layer.get_child_count()>0,"Candidate image inspects without choosing");main._close_inspection();main.modal_open=true
		check(main.overlay.get_node("ResourceMulligan").text.contains("2"),"Resource reroll count shown")
		await capture(profile.name+"-resource-opening")
		print("UI picker");g=fixture();main._refresh();main._draw_deck_picker();await process_frame
		var picker=main.large_layer.get_node("DrawDeckPicker");check(labels(picker).contains("花主牌1行动") and labels(picker).contains("团体") and labels(picker).contains("资源") and labels(picker).contains("阴谋"),"Compact three deck picker with action fee "+profile.name)
		check(main.get_global_rect().encloses(picker.get_global_rect()),"Deck picker within viewport "+profile.name);await capture(profile.name+"-deck-picker");main._clear(main.large_layer)
		for id in ["E01","E02"]:g.decks.resource.erase(id);g.hands[0].resource.append(id)
		main._draw_deck_picker();check(labels(main.large_layer).contains("资源 · 手牌已满"),"Full resource hand explains unavailable deck");main._clear(main.large_layer)
		print("UI camera");g=fixture();g.decks.group.erase("G001");g.hands[0].group.append("G001");await settle();main.board.camera_animating=false;main.board.pan=Vector2(-5000,-5000)
		var auto=g.legal_actions(0).filter(func(a):return a.type=="auto" and a.id=="G001" and a.parent=="G023")[0]
		var state=JSON.stringify(g.nodes);var random=g.rng.state
		main._do_action(0,auto);main.modal_open=true
		if main.presentation_tween!=null:main.presentation_tween.pause()
		await process_frame
		check(main.busy and JSON.stringify(g.nodes)==state and g.rng.state==random,"Camera stage holds live board and RNG before own takeover "+profile.name)
		main.presentation_tween.play();await idle()
		check(g.nodes.has("G001") and main.board.get_global_rect().encloses(main.board.cards.G001.get_global_rect()),"Takeover landing visible after framing "+profile.name)
		print("UI reorg");g.decks.group.erase("G043");g._enter("G043",0,"G001",0);g.nodes.R0.token=1;await settle()
		var move=g.legal_actions(0).filter(func(a):return a.type=="move" and a.src=="G001" and a.parent=="R0")[0]
		var planned=ActionFlow.plan(g,0,move);check("G043" in planned.camera_ids,"Reorganization camera includes descendants")
		main.board.pan=Vector2(5000,5000);main.board.camera_animating=false;main._do_action(0,move);main.modal_open=true;await idle()
		for id in ["G001","G043","R0","G023"]:check(main.board.get_global_rect().encloses(main.board.cards[id].get_global_rect()),"Old/new reorganization branches fit "+profile.name+id)
		await capture(profile.name+"-reorganization-camera")
		main.board.collapsed.R0=true;main._refresh(false);await process_frame;await process_frame
		check(main.board.targets.has("G043") and not main.board.cards.G043.visible,"Folded descendants retain valid positions "+profile.name)
		main.board.reveal(["G043"]);main._refresh(false);await main.board.wait_for_settlement()
		check(main.board.cards.G043.visible and main.board.is_settled(),"Expansion restores complete branch layout "+profile.name)
		print("UI exchange");g=fixture();put(g,"E06",0,0);put(g,"E15",1,0);g.decks.group.erase("G020");g._enter("G020",0,"R0",1);g.decks.plot.erase("P60");g.hands[0].plot.append("P60");await settle()
		var swap=g.legal_actions(0).filter(func(a):return a.type=="plot" and a.id=="P60")[0];var plan=ActionFlow.plan(g,0,swap)
		check(plan.target=="E15" and plan.other_target=="E06","Swap highlights both public resources")
		main.board.pan=Vector2(-5000,-5000);main.board.camera_animating=false;main._do_action(0,swap);main.modal_open=true;await idle()
		check(g.owner("E15")==0 and g.owner("E06")==1 and main.board.is_settled(),"Exchange animates both landings before unlock")
		check(g.validate().is_empty(),"UI flow conserves all cards "+profile.name)
		g=fixture();g.current=1;g.decks.group.erase("G043");g.hands[1].group.append("G043");await settle()
		main.board.pan=Vector2(-5000,5000);main.board.camera_animating=false
		var ai_auto=g.legal_actions(1).filter(func(a):return a.type=="auto" and a.id=="G043" and a.parent=="R1")[0]
		state=JSON.stringify(g.nodes);main._do_action(1,ai_auto);main.modal_open=true;main.presentation_tween.pause();await process_frame
		check(main.busy and JSON.stringify(g.nodes)==state,"AI takeover waits for camera too "+profile.name)
		main.presentation_tween.play();await idle()
		check(g.owner("G043")==1 and main.board.get_global_rect().encloses(main.board.cards.G043.get_global_rect()),"AI landing is visible "+profile.name)
		await capture(profile.name+"-ai-takeover-camera")
	CardDB.finish_art_requests();main.queue_free();await process_frame;await process_frame
	print("RESOURCE EXPANSION UI: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
