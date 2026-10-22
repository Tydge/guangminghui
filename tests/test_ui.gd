extends SceneTree
var checks=0
var failures: Array=[]

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main)
	await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.12
	check(main.overlay.get_child_count()>0 and main.game==null,"Main menu builds")
	main._start_game(4318);await process_frame
	check(main.game.phase=="setup_faction" and main.game.legal_actions(0).size()==12,"Twelve faction choices")
	await main._do_action(0,main.game.legal_actions(0)[0]);await process_frame
	check(main.game.phase=="setup_group" and main.game.legal_actions(0).filter(func(a):return a.type=="initial").size()==5,"Five opening cards")
	await main._do_action(0,main.game.legal_actions(0)[0]);await process_frame
	check(main.game.phase=="setup_resource","Resource selection follows initial group")
	await main._do_action(0,main.game.legal_actions(0)[0]);await process_frame
	# Stop the scheduled AI while this deterministic fixture exercises UI handlers.
	main.modal_open=true;main.game.current=0;main.game.phase="main"
	for id in main.game.field(0):main.game.nodes[id].token=1
	main._refresh();main.modal_open=false
	var selected=main.game.hands[0].group[0]
	main._select_card(selected);await process_frame
	check(main.selected==selected and main.game.hands[0].group.has(selected),"Selecting does not play a card")
	var view=CardView.new();view.configure(selected,main.game);view.size=Vector2(140,192);root.add_child(view);view.inspected.connect(main._inspect);view.selected.connect(main._select_card)
	await process_frame
	var down=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.global_position=Vector2(40,40)
	var up=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.pressed=false;up.global_position=Vector2(40,40)
	view._gui_input(down);view._process(0.49)
	check(main.detail_layer.get_child_count()>0,"Long press opens complete card")
	main.selected="";view._gui_input(up)
	check(main.selected=="","Long press suppresses ordinary click")
	main._close_inspection();view._gui_input(down)
	var motion=InputEventMouseMotion.new();motion.global_position=Vector2(60,40);view._gui_input(motion);view._process(0.6);view._gui_input(up)
	check(main.detail_layer.get_child_count()==0 and main.selected=="","Moving more than 8 px cancels long press and click")
	var b=main.board;var at=Vector2(320,150);var world_before=(at-b.pan)/b.zoom;b.zoom_at(1.3,at)
	check(((at-b.pan)/b.zoom).distance_to(world_before)<0.01,"Zoom preserves cursor world point")
	var pan=b.pan;main._select_card(selected);await process_frame
	check(b.pan.distance_to(pan)<0.01,"Selection preserves camera")
	var autos=main.game.legal_actions(0).filter(func(a):return a.type=="auto" and a.id==selected)
	main._target(autos,"parent","选择接管位置");check(not main.action_candidates.is_empty(),"Target mode retains legal candidates")
	main._select_card(autos[0].parent)
	while main.busy:await process_frame
	await process_frame
	check(main.game.nodes.has(selected) and not main.game.token(selected) and not main.game.can_recharge(selected),"UI automatic takeover enters without an action and cannot recharge that turn")
	check(main.action_candidates.is_empty(),"Target selection clears after commit")
	# Catalog survives full-card inspection without losing its close button or AI pause.
	main._catalog();var catalog_children=main.large_layer.get_child_count();main._inspect("G071");main._close_inspection()
	check(main.large_layer.get_child_count()==catalog_children and main.modal_open,"Inspect returns to catalog")
	main._clear(main.large_layer);main.modal_open=false
	main.compact=true;main._resize();await process_frame
	check(main.inspector.get_child_count()==0 and main.board.size.x>main.size.x-100,"Mobile layout uses full board width")
	main.compact=false;main._resize();await process_frame
	check(main.inspector.get_child_count()==1,"Desktop inspector restored")
	check(main.game.validate().is_empty(),"UI actions conserve cards")
	var group=main.game.root(0)
	main.board.collapsed[group]=true;main._refresh(false)
	main.board.reveal(main.game.subtree(group));main._refresh(false)
	check(not main.board.collapsed.has(group) or not main.board.collapsed[group],"Target reveal expands collapsed ancestors")
	var point=main.board.global_position+Vector2(50,50)
	var finger0=InputEventScreenTouch.new();finger0.index=0;finger0.pressed=true;finger0.position=point;main.board._input(finger0)
	var finger1=InputEventScreenTouch.new();finger1.index=1;finger1.pressed=true;finger1.position=point+Vector2(100,0);main.board._input(finger1)
	var pinch=InputEventScreenDrag.new();pinch.index=1;pinch.position=point+Vector2(120,0);main.board._input(pinch)
	var scale_before=main.board.zoom;pinch.position=point+Vector2(170,0);main.board._input(pinch)
	check(main.board.zoom>scale_before,"Two-finger pinch zooms the board")
	finger0.pressed=false;finger1.pressed=false;main.board._input(finger0);main.board._input(finger1)
	main.compact=true;main._inspect("G071");check(main.detail_layer.get_child_count()>1,"Landscape card reader builds");main._close_inspection()
	main._inspect("G024");await process_frame
	var reader=main.detail_layer.get_children().filter(func(node):return node is Panel)[0]
	await process_frame
	var body=reader.find_children("*","Label",true,false).filter(func(node):return node.text.begins_with("再来一局"))
	check(body.size()==1 and body[0].get_line_count()>1 and body[0].global_position.x+body[0].size.x<=reader.global_position.x+reader.size.x,"Landscape text wraps inside scrollable panel")
	main._close_inspection();main.compact=false
	for player in [0,1]:
		main.game.decks.plot.append_array(main.game.hands[player].plot);main.game.hands[player].plot.clear()
	for id in main.game.nodes:main.game.nodes[id].token=0
	main.game.nodes.R0.token=1
	var recruit=main.game.legal_actions(0).filter(func(a):return a.type=="attack")[0]
	main.game.act(0,recruit);main.game.act(1,main.game.legal_actions(1).filter(func(a):return a.type=="pass")[0]);main._refresh();main._schedule_ai()
	await create_timer(0.3).timeout
	check(main.game.battle.is_empty(),"No-response human battle advances automatically")
	await create_timer(0.6).timeout
	main._start_game(190);main._do_action(0,main.game.legal_actions(0)[2]);await process_frame
	check(main.board.cards.R0.definition.id=="I03" and main.board.cards.R0.state==main.game,"Restart resets card art and game references")
	print("UI TESTS: %d checks, %d failures"%[checks,failures.size()])
	var f=FileAccess.open("res://tests/ui-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	main.queue_free();view.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
