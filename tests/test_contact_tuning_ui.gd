extends "res://tests/test_contemporary_ui.gd"

func fixture(faction="I09") -> GameState:
	var g=GameState.new(803);g.nodes={};g.factions=[faction,"I01"];g.current=0;g.turns=[2,2];g.phase="main"
	for kind in g.decks:
		g.decks[kind]=CardDB.ids(kind);g.discards[kind]=[]
		for p in [0,1]:g.hands[p][kind]=[]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func command(kind: String,args: Dictionary={}) -> Dictionary:
	for a in main.game.legal_actions(0):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func settled():
	for i in 500:
		if not main.busy and not main.window_access.transitioning:return
		await create_timer(0.005).timeout
	check(false,"UI operation settles within timeout")
func state() -> String:return JSON.stringify([main.game.hands,main.game.decks,main.game.choice,main.game.rng.state])
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://contact-tuning-ui.cfg";root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.02
	for language in ["zh","en"]:
		GameLocale.set_language(language)
		for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
			root.size=profile.size;main.compact=profile.compact;await process_frame
			main.game=fixture();main.board.initialized=false;main._refresh();await main.board.wait_for_settlement()
			var g=main.game;var before=state();var a=command("ability",{"src":"R0"});main._do_action(0,a)
			check(main.busy and before==state(),"Contact source reveal locks input without changing live cards/RNG")
			await settled();main.modal_open=true
			check(g.choice.kind=="n_contact" and main.overlay.find_children("*","CardView",true,false).size()==5,"Contact displays every privately inspected Group")
			var disabled=main.overlay.find_children("*","Button",true,false).filter(func(b):return b.text==GameLocale.text("非太空 · 洗回"))
			check(disabled.size()==5 and disabled.all(func(b):return b.disabled),"Non-Space cards show a concrete unavailable state")
			var back=main.overlay.find_child("ContactReturn",true,false);check(back!=null and back.get_parent() is not Container and main.get_global_rect().encloses(back.get_global_rect()),"Return remains visible without scrolling through all five cards")
			await take(language+"-"+profile.name+"-contact")
			before=state();main._do_action(0,command("choose",{"id":""}));check(main.busy and state()==before,"Returning inspected cards finishes before the real deck/RNG changes");await settled()
			# The discarded random Plot remains private until this owner's choice view.
			main.game=fixture("I01");g=main.game;g.decks.plot.erase("P70");g.hands[0].plot=["P70"];g.decks.plot.erase("P13");g.hands[1].plot=["P13"];main.board.initialized=false;main._refresh();await main.board.wait_for_settlement()
			before=state();main._do_action(0,command("plot",{"id":"P70"}));check(main.busy and state()==before,"Inside Job does not peek before source animation finishes")
			await settled();main.modal_open=true
			var viewed=main.overlay.find_child("InsideJobCard",true,false);check(viewed!=null and viewed.id=="P13","Inside Job displays the randomly inspected full card")
			for name in ["InsideJobTop","InsideJobBottom"]:
				var button=main.overlay.find_child(name,true,false);check(button!=null and main.get_global_rect().encloses(button.get_global_rect()),"Concrete placement button stays on-screen "+name)
			check(main.interactions.private_choice_known("P13"),"Owner's placement flight may show the already viewed Plot")
			before=state();main.window_access.peek();await settled();check(main.window_access.browsing and state()==before,"Battlefield browsing preserves private decision and RNG")
			main.window_access.resume();await settled();check(main.overlay.find_child("InsideJobCard",true,false)==viewed and state()==before,"Return restores the same choice controls")
			await take(language+"-"+profile.name+"-inside-job")
			main._do_action(0,command("choose",{"id":"bottom"}));check(g.hands[1].plot==["P13"] and main.busy,"Placement flight finishes before the opponent's real hand changes")
			await settled();check(g.hands[1].plot.is_empty() and g.decks.plot.back()=="P13","Chosen destination commits after flight")
			main.game=fixture();g=main.game;g._set_choice(1,"第三类接触 · 可取1张太空团体",["G029"],"n_contact",{"peek":["G029"]},true)
			check(not main.interactions.known("G029"),"Opponent's private contact never exposes faces to the local player")
			# A fixed subset is shown for Quantum; clicking a card only inspects it.
			main.game=fixture("I01");g=main.game;g.decks.resource.erase("E06");g.nodes.E06={"card":"E06","owner":0,"parent":"","token":1,"attached":[],"resource_slot":0};g.decks.group.erase("G170");g.hands[0].group=["G170"];main.board.initialized=false;main._refresh();await main.board.wait_for_settlement()
			before=state();main._do_action(0,command("resource",{"src":"E06"}));check(g.hands[0].group==["G170"] and state()==before,"Quantum cards cannot arrive before draw flights")
			await settled();main.modal_open=true;check(g.choice.options.size()==2 and main.overlay.find_children("*","CardView",true,false).size()==2,"Quantum choice excludes all older hand cards")
			before=state();var card=main.overlay.find_children("*","CardView",true,false)[0];card.selected.emit(card.id);await process_frame;check(state()==before and main.interactions.reader_id==card.id,"Clicking candidate artwork inspects without choosing")
			main._close_inspection();await take(language+"-"+profile.name+"-quantum")
			main._inspect("I09");await take(language+"-"+profile.name+"-ufo-card");main._close_inspection();main._menu()
	check(GameLocale.missing.is_empty(),"New Chinese and English screens have no missing phrases: "+str(GameLocale.missing))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path));main.queue_free();await process_frame
	print("CONTACT / TABLE UI: "+JSON.stringify({"checks":checks,"failures":failures,"captures":captures}));quit(0 if failures.is_empty() else 1)
