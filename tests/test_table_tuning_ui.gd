extends SceneTree
var checks=0
var failures: Array=[]
var main
var capture=false
var folder=""
var captures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func text(node: Node) -> String:
	var result=""
	for label in node.find_children("*","Label",true,false):result+=label.text+"\n"
	return result
func fresh() -> GameState:
	main._start_game(172);main.modal_open=true
	var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.discards={"group":[],"plot":[]};g.graves=[[],[]];g.factions=["I01","I05"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func give(g: GameState,id: String) -> void:g.decks[g.card(id).kind].erase(id);g.hands[0][g.card(id).kind].append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func idle() -> void:
	var deadline=Time.get_ticks_msec()+7000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Presentation completes and releases input")
func take(name: String) -> void:
	if not capture:return
	var deadline=Time.get_ticks_msec()+5000
	while not CardDB.art_requests.is_empty() and Time.get_ticks_msec()<deadline:CardDB.collect_art(8);await process_frame
	await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if capture:DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.12
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact;main._resize()
		var g=fresh();put(g,"G008",0,"R0");put(g,"G010",0,"G008");put(g,"G030",1,"R1");put(g,"G075",1,"R1");main._refresh();main._inspect("G008")
		check(text(main.detail_layer).contains("GP2") and text(main.detail_layer).contains("直属政府下属1个"),"UN reader shows derived GP and child count")
		main._close_inspection();main.modal_open=true;main._inspect("G075")
		check(text(main.detail_layer).contains("国际气象组织 · 灾难防御+5") and g.card_context("G075").destroy_passive==0,"Reader explains disaster aura without applying it to ordinary destruction")
		await take(profile.name+"-weather-reader");main._close_inspection();main.modal_open=true
		# Entry animation fully finishes before Comic Books is revealed and draws a card.
		g=fresh();put(g,"G034",0,"R0");put(g,"G052",1,"R1");give(g,"G084");main._refresh();main.board.set_process(false)
		main._do_action(0,action(g,0,"auto",{"id":"G084","parent":"R0"}));main.modal_open=true
		check(main.busy and g.hands[0].plot.is_empty() and main.presentation_layer.find_child("PresentedCard",true,false)==null,"Comic trigger cannot overtake celebrity entry motion")
		main.board.set_process(true);await idle();main.modal_open=true
		check(g.phase=="choice" and g.choice.source=="G034" and main.board.is_settled(),"Comic reward starts after celebrity settles")
		main._do_action(0,action(g,0,"trigger"));main.modal_open=true;main.presentation_tween.pause()
		check(main.presentation_layer.find_child("PresentedCard",true,false).id=="G034" and text(main.presentation_layer).contains("英雄登场") and g.hands[0].plot.is_empty(),"Comic source and effect are shown before drawing")
		main.presentation_tween.play();await idle();main.modal_open=true;check(g.hands[0].plot.size()==1,"Comic draw arrives after its reveal and flight")
		# A failed attack shows and dismisses dice before the automatic dental bill.
		g=fresh();put(g,"G005",0,"R0");g.nodes.G005.learned=20;put(g,"G067",1,"R1");give(g,"P10");give(g,"P17")
		main._refresh();main._review_action(action(g,0,"attack",{"src":"G005","target":"G067","mode":"control"}))
		check(text(main.large_layer).contains("失败后随机弃1阴谋"),"Attack preview states dental bill risk before committing")
		main._clear(main.large_layer);main.preview_action={}
		g.act(0,action(g,0,"attack",{"src":"G005","target":"G067","mode":"control"}));g.battle.fixed_dice=[5,6];g.act(1,action(g,1,"pass"));main._refresh()
		main._do_action(0,action(g,0,"pass"));main.modal_open=true;main.presentation_tween.pause()
		check(main.presentation_layer.has_node("DiceResult") and g.phase=="battle" and g.hands[0].plot.size()==2,"Dental bill cannot preempt dice or discard early")
		main.presentation_tween.play();await idle();main.modal_open=true
		check(g.phase=="choice" and g.choice.source=="G067" and main.presentation_layer.get_child_count()==0,"Dice fully close before deferred dental bill")
		var rng_before=g.rng.state;main._do_action(0,action(g,0,"trigger"));main.modal_open=true;main.presentation_tween.pause()
		check(text(main.presentation_layer).contains("高额账单 · 对手随机弃1阴谋") and g.hands[0].plot.size()==2 and g.rng.state==rng_before,"Bill source reveal precedes actual random discard")
		main.presentation_tween.custom_step(10);main.presentation_tween.pause()
		check(main.presentation_layer.has_node("MovingCard") and g.hands[0].plot.size()==2 and g.rng.state==rng_before,"Randomly discarded card flies before live hand or RNG changes")
		main.presentation_tween.play();await idle();main.modal_open=true
		check(g.hands[0].plot.size()==1 and g.last_battle.entries.back().text.contains("高额账单"),"Exactly one random discard commits and appears in history")
		main._inspect("G067");check(text(main.detail_layer).contains("普通攻击失败后") or CardDB.get_card("G067").effect.contains("普通攻击失败后"),"Dentist text uses final passive bill ability")
		await take(profile.name+"-dentist-reader");main._close_inspection();main.modal_open=true
		check(g.validate().is_empty(),"New passive effects conserve cards")
	var report={"checks":checks,"failures":failures,"captures":captures,"profiles":["1600x900","1280x720"],"android_device_tested":false};FileAccess.open("res://tests/table-tuning-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("TABLE TUNING UI: "+JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
