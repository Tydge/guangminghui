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
func button(value: String) -> Button:
	for b in main.large_layer.find_children("*","Button",true,false):
		if b.text==value:return b
	return null
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func put(g: GameState,id: String,p: int,parent: String) -> void:g.decks.group.erase(id);g._enter(id,p,parent,1)
func fixture(media: String="G033") -> GameState:
	main._start_game(181);main.modal_open=true
	var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.factions=["I05","I01"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	put(g,"G001",0,"R0");put(g,media,0,"R0");put(g,"G071",1,"R1")
	g.decks.plot.erase("P36");g.world="P36"
	check(g.act(0,action(g,0,"attack",{"src":"G001","target":"G071","mode":"control"})),"Start real ordinary control battle")
	check(g.act(1,action(g,1,"pass")),"Attacker receives response after defender passes")
	main._refresh();main.modal_open=true;return g
func supports(g: GameState,id: String) -> Array:return g.legal_actions(0).filter(func(a):return a.type=="support" and a.src==id)
func idle() -> void:
	var deadline=Time.get_ticks_msec()+6000
	while (main.busy or main.window_access.transitioning) and Time.get_ticks_msec()<deadline:await process_frame
	check(not main.busy and not main.window_access.transitioning,"Animations finish and release input")
func take(name: String) -> void:
	if not capture:return
	var deadline=Time.get_ticks_msec()+5000
	while not CardDB.art_requests.is_empty() and Time.get_ticks_msec()<deadline:CardDB.collect_art(8);await process_frame
	await process_frame;await RenderingServer.frame_post_draw
	var path=folder+name+".png";root.get_texture().get_image().save_png(path);captures.append(path)
func inside(panel: Control) -> void:
	check(Rect2(Vector2.ZERO,main.size).encloses(panel.get_global_rect()),"Compact panel stays inside viewport")
	for b in panel.find_children("*","Button",true,false):
		check(panel.get_global_rect().encloses(b.get_global_rect()),"Complete option inside panel: "+b.text)
		check(b.text!="是" and b.text!="否","Every mode uses descriptive text")
		check(b.get_theme_font("font").get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x<=b.size.x-30,"Option text fits without clipping: "+b.text)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=").trim_suffix("/")+"/"
	capture="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	if capture:DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.12
	for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
		root.size=profile.size;await process_frame;main.compact=profile.compact;main._resize()
		var g=fixture();var choices=supports(g,"G033");var rng_before=g.rng.state;var battle_before=g.battle.duplicate(true)
		check(choices.size()==2,"Algorithm fixture has ordinary and converted support")
		main._dispatch_options(choices);await process_frame;await process_frame
		var panel=main.large_layer.get_node("StepPicker");inside(panel)
		check(panel.size.x<=760 and panel.size.y<=400,"Two choices do not occupy an oversized dialog")
		check(text(panel).contains("算法时代 · 支援方式") and text(panel).contains("空洞音乐台 · 支援进攻 · 消耗1行动"),"Mode identifies rule, supporter, side and action cost")
		check(button("普通支援 · GP +1")!=null and button("算法时代 · P +3（本战限1次）")!=null,"Options name exact legal support values and per-battle allowance")
		check(g.battle==battle_before and g.rng.state==rng_before and g.token("G033"),"Opening picker does not pay, reserve algorithm or advance RNG")
		await take(profile.name+"-algorithm-support")
		main.window_access.peek();await idle();check(main.window_access.browsing and not main.large_layer.visible,"Mode can park while viewing battlefield")
		main.window_access.resume();await idle();check(main.interactions.picker.next_key()=="algorithm" and main.large_layer.visible,"Returning retains exact mode step")
		button("算法时代 · P +3（本战限1次）").pressed.emit()
		check(text(main.large_layer).contains("支援进攻 · P +3") and text(main.large_layer).contains("本战限1次"),"Confirmation retains selected basis, amount and quota")
		check(g.battle==battle_before and g.rng.state==rng_before,"Selecting mode still does not commit")
		button("上一步").pressed.emit();button("普通支援 · GP +1").pressed.emit();button("确认").pressed.emit();main.modal_open=true;await idle()
		check(g.battle.support_a==1 and not g.battle.get("algorithm_used",false) and not g.token("G033"),"Ordinary option commits GP without consuming algorithm allowance")
		g=fixture();main._dispatch_options(supports(g,"G033"));button("算法时代 · P +3（本战限1次）").pressed.emit();button("确认").pressed.emit();main.modal_open=true;await idle()
		check(g.battle.support_a==3 and g.battle.algorithm_used and not g.token("G033"),"Converted option commits actual P and consumes allowance once")
		g=fixture("G104");g.world="";g.discards.plot.append("P36")
		for id in ["P02","P03"]:g.decks.plot.erase(id);g.hands[0].plot.append(id)
		main._refresh();main._dispatch_options(supports(g,"G104"));await process_frame;await process_frame
		check(main.interactions.picker.next_key()=="amplify","Optional expansion is selected before any expansion discard fee")
		check(button("普通支援 · GP +2")!=null and button("弹性扩容 · GP +4 · 另弃1张牌")!=null,"Expansion exposes both legal values and additional discard")
		inside(main.large_layer.get_node("StepPicker"));await take(profile.name+"-cloud-support")
		button("弹性扩容 · GP +4 · 另弃1张牌").pressed.emit();check(main.interactions.picker.next_key()=="plot_fee","Discard selected only after optional expansion is accepted")
		main.interactions.pick("plot_fee","P02");check(text(main.large_layer).contains("支援进攻 · GP +4") and text(main.large_layer).contains(g.title("P02")),"Fee confirmation retains support value as well as selected discard")
		button("上一步").pressed.emit();button("上一步").pressed.emit();button("普通支援 · GP +2").pressed.emit()
		check(main.large_layer.has_node("ActionConfirmation") and main.interactions.picker.actions[0].get("plot_fee","")=="","Backing out of expansion keeps free ordinary support available")
		main.interactions.cancel();check(g.token("G104") and g.hands[0].plot.size()==2,"Cancelling preserves action and both fee cards")
	# All boolean modes have concrete wording; no generic yes/no remains.
	var g=fixture();main.interactions.picker.begin(supports(g,"G033"))
	for key in ActionPicker.MODE_KEYS:
		if key=="use_plan":g.wave.plans[0]=[2,4]
		for enabled in [false,true]:check(main.interactions.mode_title(key,enabled) not in ["是","否","启用","不启用"],"Concrete effect wording for "+key)
	check(main.interactions.mode_title("use_plan",true).contains("2＋4＝6"),"Preplanned dice option displays actual saved dice")
	main.interactions.cancel()
	var report={"checks":checks,"failures":failures,"captures":captures,"profiles":["1600x900","1280x720"],"android_device_tested":false};FileAccess.open("res://tests/support-modes-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("SUPPORT MODES UI: "+JSON.stringify(report));main.queue_free();await process_frame;quit(0 if failures.is_empty() else 1)
