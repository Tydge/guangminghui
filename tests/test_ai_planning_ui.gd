extends SceneTree
var failures=[]
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.ai_difficulty="hard";main._start_game(181);main.modal_open=true
	var g=main.game;g.nodes={};g.factions=["I01","I01"];g.phase="main";g.current=1;g.turns=[2,2];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	for row in [["G001",0],["G003",1],["G083",1]]:g.decks.group.erase(row[0]);g._enter(row[0],row[1],g.root(row[1]),1)
	g.decks.group.erase("G075");g.hands[1].group.append("G075");main._refresh();main.modal_open=false
	var before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]);main._schedule_ai()
	for i in 100:
		await process_frame
		if main.ai.planning_active:break
	check(main.ai.planning_active and main.thinking,"Main loop yields frames while AI plans")
	check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"Async search never advances live rules")
	main._settings()
	var deadline=Time.get_ticks_msec()+3000
	while main.ai.planning_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.ai.planning_active and not main.thinking and before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"Opening settings cancels search without paying or acting")
	main._close_settings()
	for i in 100:
		await process_frame
		if main.ai.planning_active:break
	main.ai.cancel_all();main._settings();main._close_settings()
	deadline=Time.get_ticks_msec()+6000
	while before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]) and Time.get_ticks_msec()<deadline:await process_frame
	check(before!=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"A fast pause/resume reschedules a cancelled plan instead of stalling the AI")
	main._menu();await process_frame;check(main.game==null and not main.ai.planning_active,"New game/menu cancels stale plans")
	CardDB.finish_art_requests();main.queue_free();await process_frame;await process_frame
	print("AI PLANNING UI: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
