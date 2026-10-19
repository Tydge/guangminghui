extends SceneTree

var checks=0
var failures: Array=[]
var capture_images=false
var image_folder="res://tests/"

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message);push_error(message)

func _initialize() -> void:call_deferred("run")

func place(g: GameState,id: String,p: int,parent: String) -> void:
	g.decks.group.erase(id)
	for hand in g.hands:hand.group.erase(id)
	g._enter(id,p,parent,1)

func give(g: GameState,id: String,p: int) -> void:
	g.decks.plot.erase(id);g.hands[p].plot.append(id)

func fresh() -> GameState:
	var g=GameState.new(151);g.act(0,g.legal_actions(0)[0])
	g.factions=["I01","I04"];g.nodes.R1.card="I04";g.turns=[2,2];g.current=0;g.phase="main"
	g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}]
	g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")}
	g.nodes.R0.token=1;g.nodes.R1.token=1
	place(g,"G025",0,"R0");place(g,"G001",0,"R0");place(g,"G021",0,"R0")
	place(g,"G024",0,"G025");place(g,"G043",0,"G025")
	place(g,"G023",1,"R1");place(g,"G006",1,"G023");place(g,"G063",1,"R1")
	for id in ["P05","P04","P02","P12","P13","P15","P24"]:give(g,id,0)
	for id in ["P01","P10"]:give(g,id,1)
	return g

func apply(g: GameState,p: int,type: String,args: Dictionary={}) -> void:
	var candidates=g.legal_actions(p).filter(func(a):
		if a.type!=type:return false
		for key in args:
			if a.get(key)!=args[key]:return false
		return true)
	check(not candidates.is_empty(),"Legal %s %s"%[type,str(args)])
	if not candidates.is_empty():check(g.act(p,candidates[0]),"Apply "+type)

func status(options: Dictionary,id: String) -> String:
	return options.plots.filter(func(entry):return entry.id==id)[0].status

func labels(node: Node) -> String:
	var text=""
	for item in node.find_children("*","Label",true,false):text+=item.text+"\n"
	return text

func capture(name: String) -> void:
	if not capture_images:return
	await process_frame;await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(image_folder+name+".png")

func run() -> void:
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):image_folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	var g=fresh();check(g.validate().is_empty(),"Fixture conserves cards")
	var before=JSON.stringify([g.nodes,g.hands,g.decks,g.battle,g.phase,g.used,g.recharged,g.last_event]);var random_before=g.rng.state
	var options=g.attack_options("G025","G023","control")
	check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.battle,g.phase,g.used,g.recharged,g.last_event]) and g.rng.state==random_before,"Preflight does not spend actions, move cards or consume randomness")
	var video=options.supports.filter(func(entry):return entry.id=="G024")[0]
	var hacker=options.supports.filter(func(entry):return entry.id=="G021")[0]
	check(video.basis=="P" and video.power==3,"Direct child uses P with telephone command")
	check(hacker.basis=="GP" and hacker.power==2,"Unmatched non-child uses GP")
	check(not options.supports.any(func(entry):return entry.id=="G001"),"Zero GP and no full-power qualification cannot support")
	check(status(options,"P05")=="可用" and status(options,"P12")=="可用","Leader alignment and control plot available before attack")
	check(status(options,"P04")=="先支援","Criminal plot requires the GP supporter to join first")
	check(status(options,"P02")=="不可用" and status(options,"P13")=="不可用","Unused violent group and wrong attack mode do not unlock plots")
	check(status(options,"P15")=="反应" and status(options,"P24")=="不可用","Counter is conditional and main-phase plot is unavailable")
	check(not JSON.stringify(options).contains("P10") and not JSON.stringify(options).contains("P01"),"Preflight does not reveal enemy plots")
	apply(g,0,"attack",{"src":"G025","target":"G023","mode":"control"});apply(g,1,"pass")
	check(not g.legal_actions(0).any(func(a):return a.type=="plot" and a.id=="P04"),"Conditional plot is not legal before support payment")
	apply(g,0,"support",{"src":"G021"});check(g.battle.support_a==2,"Live GP support matches preflight value")
	apply(g,1,"pass");apply(g,0,"plot",{"id":"P04"})
	check(g.battle.bonus_a==4,"GP supporter receives the full fixed plot bonus")

	g=fresh();var context=g.card_context("G024")
	check(context.loyalty==4 and context.position==5 and context.depth==2,"Card context derives loyalty and position from the live parent")
	var v=g.attack_preview("R1","G024","control")
	check(context.control_total==v.base+v.loyalty+v.position+v.defense,"Reader baseline agrees with live control calculation")
	g.nodes.G024.parent="G001";check(g.card_context("G024").loyalty==0,"Loyalty updates after reparenting")
	g.nodes.G024.parent="G025"
	give(g,"P26",0);give(g,"P27",0);apply(g,0,"plot",{"id":"P26","target":"G024"});apply(g,0,"plot",{"id":"P27","target":"G024"})
	context=g.card_context("G024")
	check(context.printed.p==3 and g.stat("G024","p")==4 and g.stat("G024","r")==5,"Printed and attachment-modified stats remain distinct")
	g.recharged.G024=true;check(g.card_context("G024").recharged,"Reader exposes recharge quota")
	check(g.card_context("G001").position==10 and g.card_context("G043").position==5,"Direct and second-level position values")
	check(not g.card_context("G080").on_board and g.card_context("G080").position==0,"Off-board cards have no tree defense")

	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main._start_game(4318);main.game=g;main._refresh();main.board.opening_view(false)
	main._inspect("G024");await process_frame
	check(labels(main.detail_layer).contains("忠诚 +4") and labels(main.detail_layer).contains("位置 +5") and labels(main.detail_layer).contains("当前  P4"),"Desktop full reader displays current defense and modified stats")
	await capture("光明会_大卡额外数值")
	main._close_inspection();main.compact=true;main._resize();main._inspect("G024");await process_frame
	check(labels(main.detail_layer).contains("忠诚 +4") and labels(main.detail_layer).contains("额外恢复次数已用"),"Mobile scrollable reader exposes the same derived state")
	await capture("光明会_移动大卡数值")
	main._close_inspection();main.compact=false;main.game=fresh();g=main.game;main._refresh()
	var attack=g.legal_actions(0).filter(func(a):return a.type=="attack" and a.src=="G025" and a.target=="G023" and a.mode=="control")[0]
	main._review_action(attack);await process_frame
	check(labels(main.large_layer).contains("支援  4个") and labels(main.large_layer).contains("1张需先支援"),"Concise preflight includes support count and conditional plot count")
	check(not labels(main.large_layer).contains("不适用于本次攻击"),"Preflight does not expand all detailed conditions by default")
	await capture("光明会_精简攻击预览")
	main._clear(main.large_layer);main.preview_action={}
	apply(g,0,"attack",{"src":"G025","target":"G023","mode":"control"})
	apply(g,1,"support",{"src":"G006"});apply(g,0,"support",{"src":"G024"});apply(g,1,"plot",{"id":"P01"})
	check(g.phase=="plot_response" and g.battle.entries.back().status=="待结算","Played enemy plot stays visibly pending during counter window")
	apply(g,0,"counter")
	check(g.battle.entries.any(func(entry):return entry.id=="P01" and entry.status=="已被反制"),"Counter updates the original plot entry")
	apply(g,1,"plot",{"id":"P10"})
	main._refresh();await process_frame;await process_frame
	var feed=labels(main.overlay)
	check(feed.contains("AI · 特勤局 支援防守 +3（P）") and feed.contains("民调利好") and feed.contains("已被反制"),"Battle feed exposes the opponent's group, support value, plot and counter result")
	await capture("光明会_双方战斗记录")
	g.battle.bonus_a=100
	while g.phase=="battle":apply(g,g.battle.responder,"pass")
	check(not g.last_battle.is_empty() and g.last_battle.entries.size()==6,"Full public history survives battle resolution")
	check(g.validate().is_empty(),"History retains references without duplicating cards")
	main._refresh();main._battle_history();await process_frame
	check(labels(main.large_layer).contains("AI · 特勤局") and labels(main.large_layer).contains("民调利好"),"Completed battle can be reopened")
	await capture("光明会_战后回看")
	print("BATTLE CLARITY TESTS: %d checks, %d failures"%[checks,failures.size()])
	var f=FileAccess.open("res://tests/battle-clarity-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	main.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
