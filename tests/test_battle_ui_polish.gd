extends "res://tests/test_contemporary.gd"
var main
var folder=""
var captures=[]
func texts(node: Node) -> String:
	var result=""
	for child in node.find_children("*","Label",true,false)+node.find_children("*","Button",true,false):result+=child.text+"\n"
	return result
func snapshot(g: GameState) -> String:return JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.scrap,g.battle,g.phase,g.used,g.victory,g.wave.queue,g.wave.response_queue,g.rng.state])
func attack_fixture() -> GameState:
	var g=fresh();put(g,"G055");put(g,"G025");put(g,"G001",1);put(g,"G071",1,"G001");return g
func goal_fixture(who: int) -> GameState:
	var g=fresh();g.current=who
	for id in ["G051","G013","G021","G052","G053"]:put(g,id,who)
	put(g,"G043",1-who);give(g,"P51",who);return g
func rules():
	var g=attack_fixture();put(g,"E01");put(g,"E19");var before=snapshot(g);var options=g.attack_options("G055","G071","control")
	check(options.resource_total==11 and options.support_total==options.group_support_total+11,"Ready radar and Magic sword add eleven to the preview total")
	check(options.resources.size()==2 and snapshot(g)==before,"Resource rehearsal neither changes the live match nor consumes RNG")
	check(g.attack_options("G025","G071","control").resource_total==3,"Magic-only resource is unavailable to an ordinary leader")
	give(g,"P15",1);before=snapshot(g);options=g.attack_options("G055","G071","control");check(not JSON.stringify(options).contains("P15") and snapshot(g)==before,"Resource preview cannot expose an opponent's hidden card or change its state")
	g.nodes.E01.token=0;check(g.attack_options("G055","G071","control").resource_total==8,"Exhausted action resource is excluded")
	g.nodes.E19.silenced=true;check(g.attack_options("G055","G071","control").resource_total==0,"Disabled resource is excluded")
	g=attack_fixture();put(g,"E01");put(g,"E23");options=g.attack_options("G055","G071","control")
	check(g.loyalty_defense("G071")==4 and options.resource_total==7,"Scepter uses this target's actual four loyalty plus radar's three")
	check(g.attack_options("G055","G071","destroy").resource_total==3,"Scepter cannot add to a Destroy attack")
	g=attack_fixture();put(g,"E01");put(g,"E12");options=g.attack_options("G055","G071","control")
	check(options.resource_total==3 and options.resources.any(func(e):return e.id=="E12" and e.conditional and e.bonus==0),"Conditional decoy is visible without inflating the unconditional total")
	g=attack_fixture();put(g,"E15");put(g,"E07");options=g.attack_options("G055","G071","control")
	check(options.resource_total==0 and options.resources.size()==1 and options.resources[0].id=="E15","Fixed dice has no additive power and defensive Phoenix is unavailable to the attacker")
	g.wave.plans[0]=[4,4];check(g.attack_options("G055","G071","control",{"use_plan":true}).resources.is_empty(),"Coin is omitted when the selected plan already fixes four plus four")
	g=attack_fixture();put(g,"E01");put(g,"E19");put(g,"G161");give(g,"P10");options=g.attack_options("G055","G071","control")
	apply(g,0,"attack",{"src":"G055","target":"G071","mode":"control"});apply(g,1,"pass")
	var responses=g.legal_actions(0)
	check(responses.back().type=="pass" and responses.any(func(a):return a.type=="resource") and responses.any(func(a):return a.get("stake",false)),"Pass follows resource and late-added casino responses")
	apply(g,0,"resource",{"src":"E01"});apply(g,1,"pass");apply(g,0,"resource",{"src":"E19"})
	check(g.battle.bonus_a==options.resource_total,"Actual resource resolution agrees with the preview total")
	check(g.legal_actions(1).back().type=="pass","Defender responses also end with pass")
	g=fresh();g.current=1;put(g,"G071");put(g,"G005",1);put(g,"G104");give(g,"P31",1);give(g,"P10")
	apply(g,1,"plot",{"id":"P31","payer":"G005","target":"G071"});check(g.legal_actions(0).back().type=="pass","Disaster responses end with pass after all extension actions")
	g=fresh();put(g,"G137");put(g,"G043",1);give(g,"P10");give(g,"P28",1);g.current=1;apply(g,1,"plot",{"id":"P28"})
	check(g.phase=="plot_response" and g.legal_actions(0).back().type=="accept_plot" and g.legal_actions(0).any(func(a):return a.type=="trick"),"Accept also follows late-added counter reactions")
	for who in [0,1]:
		g=goal_fixture(who);var copy=ActionFlow.copy_state(g);var a=action(g,who,"plot",{"id":"P51"});check(not a.is_empty(),"Goal declaration is legal")
		check(copy.act(who,a) and copy.victory.get("card","")=="P51" and g.victory.is_empty(),"Rehearsal keeps winning-card metadata private to the copy")
		check(g.act(who,a) and g.victory.kind=="goal" and g.victory.card=="P51" and g.winner==who,"Winning goal is recorded explicitly for either player")
	g=fresh("I05");g.destroyed[0]=6;put(g,"G043");put(g,"G044",1);g._complete_end();check(g.victory.kind=="faction" and g.victory.card=="I05","Faction victory records the winning faction")
	g=fresh();g.turns=[3,3];put(g,"G043");g._after_effect();check(g.victory.kind=="elimination" and g.winner==0,"Elimination has a distinct result reason")
	g=fresh("I05");g.factions[1]="I05";g.nodes.R1.card="I05";g.destroyed=[6,6];g._complete_end();check(g.winner==-1 and g.victory.kind=="draw","Simultaneous faction goals remain a draw")
func settle_frames():
	for i in 4:await process_frame
func take(name: String):
	if folder=="" or DisplayServer.get_name()=="headless":return
	var deadline=Time.get_ticks_msec()+4000
	while not CardDB.art_requests.is_empty() and Time.get_ticks_msec()<deadline:CardDB.collect_art(8);await process_frame
	await settle_frames();await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png");captures.append(name)
func window_idle():
	var deadline=Time.get_ticks_msec()+3000
	while main.window_access.transitioning and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.window_access.transitioning,"Window transition finishes")
func run():
	rules()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	GameLocale.set_language("zh");root.size=Vector2i(1440,1000);main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://battle-ui-polish-test.cfg";DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path));root.add_child(main);await settle_frames();main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.03
	for language in ["zh","en"]:
		GameLocale.set_language(language);main._menu();await settle_frames()
		var content=main.overlay.get_node("MenuContent");var identity=content.get_instance_id();var original={};var ticket=main.match_id
		for control in content.find_children("*","Control",true,false):original[control.get_instance_id()]=control.get_global_rect()
		check(content.global_position.is_equal_approx(main.size/2),"Menu starts centered at a non-default window aspect "+language)
		await take(language+"-menu-before")
		for level in ["easy","hard","normal"]:
			var choices=main.overlay.find_child("DifficultyOptions",true,false);var b=choices.get_children().filter(func(v):return v.get_meta("difficulty")==level)[0];b.pressed.emit();await settle_frames()
			check(is_instance_valid(content) and content.get_instance_id()==identity and main.match_id==ticket,"Changing difficulty does not rebuild or restart the menu "+language+level)
			check(main.ai_difficulty==level and b.button_pressed,"Difficulty selection updates in place "+language+level)
			for control in content.find_children("*","Control",true,false):check(control.get_global_rect()==original[control.get_instance_id()],"Menu layout never jumps on selection "+language+level+control.name)
		await take(language+"-menu-after")
		for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
			main._menu();content=main.overlay.get_node("MenuContent")
			root.size=profile.size;main.compact=profile.compact;await settle_frames()
			check(content.global_position.is_equal_approx(main.size/2),"Menu stays centered when the window changes "+profile.name)
			main._start_game(989);main.modal_open=true
			var g=attack_fixture();put(g,"E01");put(g,"E19");main.game=g;main.selected="";main._refresh();main.modal_open=true
			var a=action(g,0,"attack",{"src":"G055","target":"G071","mode":"control"});main._review_action(a);await settle_frames()
			var options=g.attack_options(a.src,a.target,a.mode);check(texts(main.large_layer).contains(GameLocale.text("支援  %d个 · 合计 +%d"%[options.supports.size()+2,options.support_total])),"Preview visibly includes ready resource power "+language+profile.name)
			var sword_button=main.large_layer.find_child("PreviewResource_E19",true,false)
			check(sword_button!=null and sword_button.text==GameLocale.text(options.resources.filter(func(e):return e.id=="E19")[0].label),"New resource types and their localized response labels are included automatically "+language+profile.name);await take(language+"-"+profile.name+"-preview")
			var conditional=attack_fixture();put(conditional,"E01");put(conditional,"E12");main.game=conditional;main._refresh();main._review_action(action(conditional,0,"attack",{"src":"G055","target":"G071","mode":"control"}));await settle_frames()
			var decoy=main.large_layer.find_child("PreviewResource_E12",true,false);var resource_scroll=main.large_layer.find_child("AttackResources",true,false)
			check(decoy!=null and decoy.text.contains(GameLocale.text("对手支援后可用")) and decoy.get_combined_minimum_size().x<=resource_scroll.size.x,"Conditional resource text fits without horizontal clipping "+language+profile.name);await take(language+"-"+profile.name+"-conditional")
			main.game=g
			main._clear(main.large_layer);main.preview_action={};g.act(0,a);g.act(1,action(g,1,"pass"));main._refresh();main.modal_open=true;await settle_frames()
			var pass_button=main.overlay.find_children("*","Button",true,false).filter(func(b):return b.text==GameLocale.text("不再追加"))[0]
			check(pass_button.get_parent().get_index()==pass_button.get_parent().get_parent().get_child_count()-1,"Pass is the final visible battle option "+language+profile.name);await take(language+"-"+profile.name+"-battle")
			for who in [0,1]:
				g=goal_fixture(who);g.act(who,action(g,who,"plot",{"id":"P51"}));main.game=g;main._refresh();main.modal_open=true;await settle_frames()
				var view=main.overlay.find_child("WinningGoal",true,false);check(view!=null and view.id=="P51","Only the explicitly winning goal is displayed "+language+profile.name+str(who))
				check(texts(main.overlay).contains(GameLocale.text("你获胜" if who==0 else "AI 获胜")) and texts(main.overlay).contains(GameLocale.text(g.card("P51").effect)),"Winner and exact goal reason are visible "+language+profile.name+str(who))
				var frozen=snapshot(g);await take(language+"-"+profile.name+"-goal-"+str(who));main.window_access.peek();await window_idle()
				check(main.window_access.browsing and not main.overlay.visible and main.board.visible and texts(main.hud).contains(GameLocale.text("返回结果")),"Finished matches can return to the visible battlefield "+language+profile.name)
				if who==0:await take(language+"-"+profile.name+"-postgame-board")
				main.board.focus(who);main.hand_tab="resource";main._refresh(false);main._inspect("G043");await process_frame;main._close_inspection();check(snapshot(g)==frozen and g.legal_actions(0).is_empty() and g.legal_actions(1).is_empty(),"Post-game camera, hands and inspection cannot advance rules")
				main.window_access.resume();await window_idle();check(main.overlay.visible and main.overlay.find_child("WinningGoal",true,false)==view and snapshot(g)==frozen,"Returning preserves the same result and winning card")
				if who==0:
					main.window_access.peek();await window_idle();root.size=profile.size+Vector2i(40,20);await settle_frames();main.window_access.resume();await window_idle()
					check(main.overlay.find_child("WinningGoal",true,false).id=="P51" and snapshot(g)==frozen,"Result can rebuild after a post-game window resize without changing the match");root.size=profile.size;await settle_frames()
			g=fresh("I05");g.destroyed[0]=6;put(g,"G043");put(g,"G044",1);g._complete_end();main.game=g;main._refresh();main.modal_open=true
			check(texts(main.overlay).contains(GameLocale.text(g.card("I05").goal)) and main.overlay.find_child("WinningGoal",true,false)==null,"Faction victory shows its actual condition without unrelated goals");await take(language+"-"+profile.name+"-faction")
			g=fresh();g.turns=[3,3];put(g,"G043",1);g._after_effect();main.game=g;main._refresh();main.modal_open=true
			check(texts(main.overlay).contains(GameLocale.text("AI 获胜")) and texts(main.overlay).contains(GameLocale.text(g.victory.reason)),"Elimination explicitly names the defeated side");await take(language+"-"+profile.name+"-elimination")
			check(g.validate().is_empty(),"Post-game UI fixture conserves cards")
			g=fresh("I05");g.factions[1]="I05";g.nodes.R1.card="I05";g.destroyed=[6,6];g._complete_end();main.game=g;main._refresh();main.modal_open=true
			check(texts(main.overlay).contains(GameLocale.text("平局")) and texts(main.overlay).contains(GameLocale.text("双方同时完成目标")),"Draw identifies the shared result rather than naming a winner");await take(language+"-"+profile.name+"-draw")
			var finished=main.game;var saved=snapshot(finished);main.window_access.peek();main._start_game(552);await settle_frames()
			check(not main.window_access.browsing and not main.window_access.transitioning and main.game.phase=="setup_faction" and snapshot(finished)==saved,"New game cancels post-game browsing transitions without touching the finished match")
		main._menu();await settle_frames()
	check(GameLocale.missing.is_empty(),"New menu, preview and result text is fully localized: "+str(GameLocale.missing))
	CardDB.finish_art_requests();main.queue_free();await process_frame;await process_frame;DirAccess.remove_absolute(ProjectSettings.globalize_path("user://battle-ui-polish-test.cfg"))
	print("BATTLE UI POLISH: "+JSON.stringify({"checks":checks,"failures":failures,"captures":captures}));quit(0 if failures.is_empty() else 1)
