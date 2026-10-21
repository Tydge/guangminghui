extends SceneTree

var checks=0
var failures: Array=[]
var main: Control
var capture_images=false
var image_folder="res://tests/"

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)

func fresh() -> GameState:
	main._start_game(81)
	var g=main.game;g.act(0,g.legal_actions(0)[1]);g.factions=["I02","I02"];g.nodes.R1.card="I02"
	g.turns=[2,2];g.phase="main";g.current=0;g.nodes.R0.token=1;g.nodes.R1.token=1
	g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")}
	return g

func place(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)

func action(g: GameState,p: int,type: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type!=type:continue
		var matches=true
		for key in args:
			if a.get(key)!=args[key]:matches=false
		if matches:return a
	return {}

func button(parent: Node,text: String) -> Button:
	for b in parent.find_children("*","Button",true,false):
		if b.text==text:return b
	return null

func labels(parent: Node) -> String:
	var text=""
	for l in parent.find_children("*","Label",true,false):text+=l.text+"\n"
	return text

func capture(name: String) -> void:
	if not capture_images:return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(image_folder+name+".png")

func wait_idle() -> void:
	var deadline=Time.get_ticks_msec()+4000
	while main.busy and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy,"Presentation completes and releases the input lock")

func mouse_event(at: Vector2,pressed: bool) -> InputEventMouseButton:
	var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.global_position=at;return e

func _initialize() -> void:call_deferred("run")

func run() -> void:
	capture_images="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):image_folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.15
	# The real opponent-card controls lead to the same confirmation without paying early.
	var g=fresh();place(g,"G005",0,"R0");place(g,"G001",0,"G005");place(g,"G039",1,"R1")
	main._refresh();main._select_card("G039")
	check(button(main.hud,"控制")!=null and button(main.hud,"摧毁")!=null,"Opponent card offers both legal attack modes")
	button(main.hud,"控制").pressed.emit()
	check(main.target_key=="src" and main.action_candidates.all(func(a):return a.target=="G039" and a.mode=="control"),"Target-first selection retains the target and asks for a leader")
	check(main.board.legal_ids.has("G005") and not main.board.legal_ids.has("G039"),"Only eligible leaders are highlighted")
	await capture("光明会_先选目标")
	main._select_card("G005")
	check(main.preview_action.get("src")=="G005" and main.preview_action.get("target")=="G039" and g.phase=="main" and g.token("G005"),"Choosing a leader opens unpaid attack preview")
	check(main._board_input_blocked(Vector2(35,170)),"Floating preflight keeps background controls protected against accidental clicks")
	var preview=main.large_layer.get_node("AttackPreview");var grip=preview.get_node("TitleDragHandle")
	var before=preview.position;grip._gui_input(mouse_event(before+Vector2(80,25),true))
	var motion=InputEventMouseMotion.new();motion.global_position=before+Vector2(135,90);grip._gui_input(motion);grip._gui_input(mouse_event(motion.global_position,false))
	check(preview.position==before+Vector2(55,65),"Attack preview drags from its title")
	main._review_action(main.preview_action)
	check(main.large_layer.get_node("AttackPreview").position==before+Vector2(55,65),"Preview keeps its position when resources are refreshed")
	main.preview_action={};main._clear(main.large_layer);main.action_candidates.clear();main._select_card("G039");button(main.hud,"摧毁").pressed.emit();main._select_card("G001")
	check(main.preview_action.get("mode")=="destroy" and main.preview_action.get("src")=="G001","Target-first destruction chooses the requested leader")
	main.preview_action={};main._clear(main.large_layer);main.action_candidates.clear();main._select_card("R1")
	check(button(main.hud,"控制")==null and button(main.hud,"摧毁")==null,"Opponent root never offers an attack")
	g.turns[1]=0;main._select_card("G039")
	check(button(main.hud,"控制")==null and button(main.hud,"摧毁")==null,"Target-first controls respect opening protection")
	# Actual battle responses rebuild the window; mouse and touch positions survive.
	g.turns[1]=2;g.act(0,action(g,0,"attack",{"src":"G005","target":"G039","mode":"destroy"}));main._refresh()
	var panel=main.overlay.get_node("BattleWindow");grip=panel.get_node("TitleDragHandle");before=panel.position
	grip._gui_input(mouse_event(before+Vector2(70,25),true));motion.global_position=before+Vector2(150,-30);grip._gui_input(motion)
	check(main.panel_dragging and panel.position==before+Vector2(80,-55),"Battle window drags without committing responses")
	main._schedule_ai();check(not main.thinking,"AI does not rebuild the panel during an active drag")
	grip._gui_input(mouse_event(motion.global_position,false));main.modal_open=true
	var dragged=panel.position
	g.act(1,action(g,1,"pass"));main._refresh()
	check(main.overlay.get_node("BattleWindow").position==dragged,"Battle response refresh retains the dragged position")
	panel=main.overlay.get_node("BattleWindow");grip=panel.get_node("TitleDragHandle")
	var touch=InputEventScreenTouch.new();touch.index=4;touch.pressed=true;touch.position=dragged+Vector2(85,25);grip._gui_input(touch)
	var finger=InputEventScreenDrag.new();finger.index=4;finger.position=touch.position+Vector2(-35,35);grip._gui_input(finger)
	touch.pressed=false;grip._gui_input(touch)
	check(panel.position==dragged+Vector2(-35,35),"Touch title drag moves the battle window")
	var zoom=main.board.zoom;var at=panel.global_position+Vector2(80,30)
	touch.index=0;touch.pressed=true;touch.position=at;main.board._input(touch)
	touch.index=1;touch.position=at+Vector2(70,0);main.board._input(touch)
	check(main.board.fingers.is_empty() and main.board.zoom==zoom,"Touches on a floating panel never start a board pinch")
	grip._gui_input(mouse_event(panel.position+Vector2(70,25),true));main._resize()
	check(not main.panel_dragging,"Resizing during a title drag safely releases the AI and input gesture")
	panel=main.overlay.get_node("BattleWindow");grip=panel.get_node("TitleDragHandle")
	grip.move_to(Vector2(-9999,9999));check(panel.position.x+panel.size.x>=180 and panel.position.y<=main.size.y-58,"Dragged window always keeps its title reachable")
	grip.move_to(Vector2(245,490));await capture("光明会_可拖动战斗窗口")
	check(g.validate().is_empty(),"Target and drag interactions preserve all cards")
	# A plot is still in hand and the world is unchanged throughout the cue.
	g=fresh();place(g,"G039",0,"R0");give(g,"P28",0);main._refresh()
	var plot=action(g,0,"plot",{"id":"P28"});main._do_action(0,plot)
	main.presentation_tween.pause()
	check(main.busy and main.presenting and g.world=="" and "P28" in g.hands[0].plot,"Plot reveal starts before rules or costs are committed")
	main._do_action(0,plot);main._perform_type("end");main._inspect("G039");main._schedule_ai()
	check(main.detail_layer.get_child_count()==0 and g.phase=="main" and not main.thinking,"Double input, inspection, end turn and AI are blocked during reveal")
	var esc=InputEventKey.new();esc.pressed=true;esc.keycode=KEY_ESCAPE;main._unhandled_key_input(esc)
	check(main.large_layer.get_child_count()==0 and main.presenting,"Escape cannot interrupt the presentation to open settings")
	await create_timer(0.13).timeout
	check(g.world=="" and "P28" in g.hands[0].plot,"Rules remain unchanged while the card is visible")
	main.presentation_tween.custom_step(0.20)
	check(g.world=="" and main.presenting and main.presentation_layer.get_node("RevealBody").modulate.a<1,"Rules remain frozen through the fade-out, not just the hold")
	main.presentation_tween.play()
	await wait_idle()
	check(g.world=="P28" and "P28" not in g.hands[0].plot and not main.presentation_layer.visible and main.board.interaction_enabled,"Rules apply after fade-out and input is restored")
	# AI theft never exposes the remaining private hand during presentation.
	g=fresh();g.current=1;place(g,"G003",1,"R1");give(g,"P23",1);give(g,"P01",0);give(g,"P02",0);main._refresh();main.reduced_motion=false;main.presentation_time_scale=1.0
	main._do_action(1,action(g,1,"plot",{"id":"P23"}));main.modal_open=true
	check(g.hands[0].plot.size()==2 and g.nodes.G003.token==1 and g.hands[1].plot==["P23"],"AI theft and payer token wait for the full presentation")
	check(main.presentation_layer.find_children("PresentedCard","Control",true,false).size()==1 and labels(main.presentation_layer).contains("AI · 打出阴谋"),"Presentation identifies the acting side and the public played card")
	check(labels(main.presentation_layer).contains("目标 · 对手阴谋手牌") and labels(main.presentation_layer).contains("行动 · 中央情报局"),"Theft cue distinguishes the affected hand from the group paying its cost")
	await create_timer(0.38).timeout;await capture("光明会_阴谋出牌展示")
	check(g.hands[0].plot.size()==2,"AI has not stolen the card while its reveal is displayed")
	await wait_idle();main.reduced_motion=true;main.presentation_time_scale=0.15
	check(g.hands[0].plot.size()==1 and g.nodes.G003.token==0 and "P23" in g.discards.plot and g.hands[1].plot.size()==1,"AI theft settles once after presentation")
	check(g.validate().is_empty(),"Presented theft preserves hidden-card and deck conservation")
	# Active ability opens its choice only after fading out, on both layouts.
	g=fresh();place(g,"G072",0,"R0");main.compact=true;main._resize();main.reduced_motion=false;main.presentation_time_scale=1.0
	var deck_before=g.decks.group.duplicate();main._do_action(0,action(g,0,"ability",{"src":"G072"}))
	check(g.phase=="main" and g.choice.is_empty() and g.decks.group==deck_before and g.token("G072"),"Ability cue does not consume its marker or peek early")
	await create_timer(0.38).timeout;await capture("光明会_主动能力展示_横屏")
	check(labels(main.presentation_layer).contains("内容出海"),"Active cue shows the named ability")
	await wait_idle();main.reduced_motion=true;main.presentation_time_scale=0.15;main.compact=false
	check(g.phase=="choice" and not g.token("G072") and g.choice.peek.size()==4,"Ability choice begins only after the presentation ends")
	# A new match invalidates an in-flight action and cancels its tween safely.
	g=fresh();give(g,"P29",0);main._refresh();main._do_action(0,action(g,0,"plot",{"id":"P29"}))
	main._start_game(91);await create_timer(0.30).timeout
	check(main.game!=g and main.game.phase=="setup_faction" and g.world=="" and not main.busy and not main.presenting,"Restart cancels the old action without settling or unlocking a later match")
	# Reduced motion still leaves enough time to read the card, at production speed.
	g=fresh();give(g,"P29",0);main.presentation_time_scale=1.0;main._refresh()
	main._do_action(0,action(g,0,"plot",{"id":"P29"}));main.presentation_tween.pause();main.presentation_tween.custom_step(0.5)
	check(main.presenting and g.world=="","Reduced motion retains the reading pause instead of flashing past the card")
	main.presentation_tween.custom_step(0.9)
	await wait_idle()
	check(not main.busy and g.world=="P29","Reduced-motion production cue still settles only after its final fade")
	main.presentation_time_scale=0.15
	# Reactions wait as well: the committed plot can only be countered after both cues.
	g=fresh();give(g,"P28",0);give(g,"P15",1);main._refresh()
	await main._do_action(0,action(g,0,"plot",{"id":"P28"}));main.modal_open=true
	check(g.phase=="plot_response" and g.world=="","Plot reveal hands off to the counter window before applying its effect")
	main._do_action(1,action(g,1,"counter"));main.modal_open=true
	check(g.phase=="plot_response" and "P15" in g.hands[1].plot,"Counter card is not consumed during its cue")
	await wait_idle()
	check(g.world=="" and "P15" in g.discards.plot and "P28" in g.discards.plot,"Counter settles in order and prevents the original effect")
	check(g.validate().is_empty(),"Presentation and reaction chain preserves all cards")
	await create_timer(0.2).timeout
	print("PRESENTATION UI: %d checks, %d failures"%[checks,failures.size()])
	var f=FileAccess.open("res://tests/presentation-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	main.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
