extends SceneTree
var main
var checks=0
var failures: Array=[]
var folder=""
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func fixture() -> GameState:
	main._start_game(98);var g=main.game;g.nodes={};g.factions=["I01","I05"];g.phase="main";g.current=0;g.turns=[2,2]
	for kind in g.decks:
		g.decks[kind]=CardDB.ids(kind);g.discards[kind]=[]
		for p in [0,1]:g.hands[p][kind]=[]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	for row in [["G023",0],["G075",1]]:g.decks.group.erase(row[0]);g._enter(row[0],row[1],g.root(row[1]),1)
	main.modal_open=true;main.thinking=false;return g
func put(g: GameState,id: String,p: int,slot: int) -> void:
	g.decks.resource.erase(id);g.nodes[id]={"card":id,"owner":p,"parent":"","token":int(g.card(id).action),"attached":[],"resource_slot":slot}
func labels(node: Node) -> String:
	var text=""
	for child in node.get_children():
		if child is Label or child is Button:text+=child.text+"\n"
		text+=labels(child)
	return text
func capture(name: String) -> void:
	if folder=="" or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png")
func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--output="):folder=a.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1600,900);main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.03;main.board.motion_time_scale=0.03
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;main.compact=profile.compact;var g=fixture();put(g,"E01",0,0);put(g,"E03",0,1);put(g,"E05",1,0);put(g,"E07",1,1)
		for id in ["E06","E08"]:g.decks.resource.erase(id);g.hands[0].resource.append(id)
		main.hand_tab="resource";main.selected="E01";main._resize();main._refresh();main.board.fit_all()
		main.board.pan=main.board.camera_target;main.board.zoom=main.board.zoom_target;main.board.camera_animating=false;await create_timer(0.05).timeout
		check(main.board.targets.E01.y==main.board.targets.R0.y and main.board.targets.E01.x<main.board.targets.R0.x and main.board.targets.E03.x>main.board.targets.R0.x,"Resources flank root, same level "+profile.name)
		var rect=main.board.get_global_rect()
		for id in g.nodes:
			check(rect.encloses(main.board.cards[id].get_global_rect()),"All resources and groups visible in overview "+profile.name+id)
		for a in g.resources.field(0)+g.resources.field(1):
			for b in g.nodes:
				if a!=b:check(not main.board.cards[a].get_global_rect().intersects(main.board.cards[b].get_global_rect()),"Resource layout never overlaps "+a+b+profile.name)
		check(labels(main.hand_layer).contains("资源 2/2") and labels(main.hud).contains("资源 4"),"Three decks and resource hand cap visible "+profile.name)
		var toolbar=main.hud.get_node("ActionToolbar")
		for button in main.hand_layer.find_children("*","Button",true,false):check(not toolbar.get_global_rect().intersects(button.get_global_rect()),"Resource tab does not overlap action toolbar "+profile.name)
		var small=main.board.cards.E01.text_layout();check(not small.any(func(row):return row.text.contains("P0")),"Resource card omits P GP R")
		await capture(profile.name+"-resource-board")
		main._inspect("E01");await process_frame;var reader=labels(main.detail_layer);check(reader.contains("行动 1 / 1") and reader.contains("在场资源 2 / 2") and not reader.contains("控制防御"),"Reader shows resource state, no group defense "+profile.name)
		await capture(profile.name+"-resource-reader");main._close_inspection();main.modal_open=true
		main._inspect("E03");await process_frame;check(labels(main.detail_layer).contains("持续生效 · 无需行动"),"Passive reader clearly has no action marker "+profile.name);main._close_inspection()
		main.modal_open=true;check(g.validate().is_empty(),"UI fixture conserves all cards "+profile.name)
	var g=fixture();g.decks.resource.erase("E01");g.hands[0].resource.append("E01");main.hand_tab="resource";main._refresh();main.modal_open=false
	var a=g.legal_actions(0).filter(func(k):return k.type=="deploy")[0];var before=g.rng.state
	main._do_action(0,a);main.presentation_tween.pause();await process_frame
	check(main.busy and "E01" in g.hands[0].resource and not g.nodes.has("E01") and g.rng.state==before,"Deployment reveal pauses live logical state")
	main.presentation_tween.play();while main.busy:await process_frame
	main.modal_open=true;check(g.nodes.has("E01") and not g.token("E01") and g.auto_used,"Deployment commits once after animation")
	check(not main.busy and main.board.is_settled(),"Resource deployment settles before unlocking")
	g=fixture();g.decks.group.erase("G098");g._enter("G098",0,"R0",1);g.decks.group.erase("G001");g.hands[0].group.append("G001");g.decks.resource.erase("E01");g.hands[0].resource.append("E01")
	var options=g.legal_actions(0).filter(func(k):return k.type=="deploy" and k.id=="E01");main._refresh();main.interactions.begin(options);await process_frame
	check(labels(main.large_layer).contains("花主牌1行动") and labels(main.large_layer).contains("矿产供给 · 弃1张团体"),"Deployment offers concrete fees even with one discard candidate")
	main.interactions.pick("supply",true);await process_frame
	check(labels(main.large_layer).contains("弃牌 · 地方警察"),"Australia confirmation preserves selected fee")
	main.interactions.cancel();main.modal_open=true
	check(g.token("R0") and "G001" in g.hands[0].group and not g.nodes.has("E01"),"Cancel deployment preserves root, fee and resource")
	main._catalog();check(labels(main.large_layer).contains("资源 · 10"),"Catalog includes resources");main._clear(main.large_layer)
	CardDB.finish_art_requests();main.queue_free();await process_frame;await process_frame
	print("RESOURCE UI TESTS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
