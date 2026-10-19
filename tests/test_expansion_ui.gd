extends SceneTree
var checks=0
var failures: Array=[]
var main
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	main._start_game(181);var g=main.game;g.act(0,g.legal_actions(0)[0]);g.phase="main";g.current=0;g.turns=[2,2];g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.nodes.R0.token=1;g.nodes.R1.token=1;return g
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func text(node: Node) -> String:
	var result=""
	for label in node.find_children("*","Label",true,false):result+=label.text+"\n"
	return result
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func idle() -> void:
	var deadline=Time.get_ticks_msec()+5000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Expansion presentation releases lock")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.12
	main._start_game(181);main._refresh();await process_frame
	var faction_views=main.overlay.find_children("*","Control",true,false).filter(func(n):return n is CardView)
	check(faction_views.size()==6,"Six faction cards fit opening selection")
	for v in faction_views:check(v.global_position.x>=0 and v.global_position.x+v.size.x<=main.size.x,"Faction selection stays within viewport")
	for card_size in [Vector2(94,142),Vector2(138,192),Vector2(292,520),Vector2(350,742)]:
		var frame=CardView.art_frame(card_size,8 if card_size.x<300 else 14)
		check(is_equal_approx(frame.size.x,frame.size.y),"Small, side preview and large cards share exactly 1:1 artwork structure")
	for image_size in [Vector2(1254,1254),Vector2(1024,1536),Vector2(1536,1024)]:
		for frame_size in [Vector2(78,66),Vector2(122,100),Vector2(322,340)]:
			var frame=Rect2(Vector2(8,8),frame_size);var fitted=CardView.art_destination(image_size,frame)
			check(is_equal_approx(fitted.size.x/fitted.size.y,image_size.x/image_size.y),"Complete artwork keeps original aspect without distortion")
			check(frame.encloses(fitted) and fitted.get_center().distance_to(frame.get_center())<0.01,"Full image fits inside frame with centered same-color margins")
	var g=fresh();put(g,"G108",0,"R0");g.wave.auto_trigger({"kind":"draw","source":"G108","quota":"ui-insurance","player":0,"amount":1,"message":"灾害承保"},"main");main._refresh()
	var trigger=action(g,0,"trigger");check(not trigger.is_empty(),"Automatic trigger command available without choice button")
	main._do_action(0,trigger);await create_timer(0.03).timeout
	check(main.busy and main.presenting and g.hands[0].plot.is_empty(),"Payout waits until animation has fully finished")
	check(text(main.presentation_layer).contains("保险财团"),"Animation identifies passive effect source")
	await idle();check(g.hands[0].plot.size()==1,"Payout happens once after presentation")
	g=fresh();put(g,"G043",0,"R0");put(g,"G097",1,"R1");g.decks.plot.erase("P31");g.hands[0].plot.append("P31");main._refresh()
	var disaster=action(g,0,"plot",{"id":"P31","payer":"G043","target":"G097"});main._review_action(disaster);await process_frame
	check(text(main.large_layer).contains("摧毁") and text(main.large_layer).contains("威力"),"Disaster preview has distinct chance and power")
	check(g.phase=="main" and "P31" in g.hands[0].plot and g.token("G043"),"Disaster preview does not pay or change phase")
	main._clear(main.large_layer);g.nodes.G097.devastated=true;g.nodes.G097.token=0;g.nodes.G097.prepared=true;main._inspect("G097");await process_frame
	var details=text(main.detail_layer);check(details.contains("受灾") and details.contains("防备") and details.contains("灾难基础防御"),"Large card shows expanded status clearly")
	main._close_inspection();main._select_card("G043");main._refresh();check(g.validate().is_empty(),"New UI interactions conserve cards")
	main.compact=true;main._resize();main._inspect("G097");await process_frame;check(main.detail_layer.get_child_count()>0,"Landscape mobile reader supports new state");main._close_inspection()
	g=fresh();put(g,"G096",0,"R0");put(g,"G019",0,"G096");put(g,"G097",1,"R1");g.decks.plot.erase("P42");g.hands[0].plot.append("P42");put(g,"G033",0,"R0");main._refresh()
	var delegated=action(g,0,"ability",{"src":"G096","leader":"G019","target":"G097"});main._review_action(delegated);await process_frame
	check(main.preview_action.get("delegate","")=="G096" and main.preview_action.get("src","")=="G019","Delegated attack opens preview with actual leader")
	check(g.phase=="main" and g.token("G096") and g.token("G019"),"Delegated preview spends no action before confirmation")
	check(text(main.large_layer).contains("墨西哥支付行动"),"Delegated preview explains who pays action")
	var options=g.attack_options("G019","G097","control",main.preview_action)
	check(not options.supports.any(func(entry):return entry.id=="G096"),"Delegated preview excludes the paying card from support")
	var plot_buttons=main.large_layer.find_children("*","Button",true,false).filter(func(b):return b.text.contains(g.title("P42")))
	check(plot_buttons.size()==1 and plot_buttons[0].text.ends_with(" · 可用"),"Non-numeric plot effect displays available without misleading +0")
	main._clear(main.large_layer)
	g._set_choice(0,"选择1张团体",["G096","G019"],"review");main._refresh();await process_frame;await process_frame
	var card_views=main.overlay.find_children("*","Control",true,false).filter(func(n):return n is CardView)
	check(card_views.size()==2 and is_equal_approx(card_views[0].size.x,card_views[1].size.x),"Choice cards keep equal widths regardless of card-name length")
	var choose_buttons=main.overlay.find_children("*","Button",true,false).filter(func(b):return b.text=="选择")
	for b in choose_buttons:check(Rect2(Vector2.ZERO,main.size).encloses(b.get_global_rect()),"Choice buttons remain fully visible below square artwork")
	print("EXPANSION UI: %d checks, %d failures"%[checks,failures.size()]);FileAccess.open("res://tests/expansion-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
