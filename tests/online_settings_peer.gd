extends SceneTree
## One actual process per locale/settings profile; no shared GameLocale singleton.
const Config=preload("res://scripts/online/config.gd")
const ViewProjection=preload("res://scripts/online/projection.gd")
var folder=""
var role=0
var url=""
var main
var failures=[]
var checks=0
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func wait_for(predicate: Callable,label: String,seconds: float=15) -> bool:
	var deadline=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	var okay=predicate.call();check(okay,label);return okay
func write(name: String,data: Dictionary={}):FileAccess.open(folder+"/"+name+str(role)+".json",FileAccess.WRITE).store_string(JSON.stringify(data))
func both(name: String) -> bool:return FileAccess.file_exists(folder+"/"+name+"0.json") and FileAccess.file_exists(folder+"/"+name+"1.json")
func settled() -> bool:return main.game!=null and not main.busy and not main.online.submitting
func submit(a: Dictionary) -> bool:
	var revision=main.online.revision
	main._do_action(0,a)
	return await wait_for(func():return main.online.revision>revision and settled(),"Action committed after full presentation")
func snapshot() -> Dictionary:
	return {"revision":main.online.revision,"nodes":ViewProjection.relative(main.game.nodes,role),"phase":main.game.phase,"current":int(main.game.current)^role,"decks":main.game.decks,"discards":main.game.discards}
func finish():
	write("result",{"checks":checks,"failures":failures})
	if main!=null:main.online.intentional=true;main.queue_free();await process_frame;await process_frame
	quit(0 if failures.is_empty() else 1)
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--folder="):folder=arg.trim_prefix("--folder=")
		if arg.begins_with("--role="):role=int(arg.trim_prefix("--role="))
		if arg.begins_with("--url="):url=arg.trim_prefix("--url=")
	main=load("res://scenes/main.tscn").instantiate();main.settings_path=folder+"/settings"+str(role)+".cfg";root.add_child(main)
	main.presentation_time_scale=0.02 if role==0 else 0.06
	main.reduced_motion=role==0;main.compact=role==1;main.sound_volume=0.0
	GameLocale.set_language("en" if role==0 else "zh")
	main.online.url=url;main.online.storage=folder+"/session"+str(role)+".cfg";main.online.screen=true
	if role==0:
		main.online.connect_join({"op":"create","build":Config.build()})
		if not await wait_for(func():return main.online.in_room,"Create room"):await finish();return
		write("code",{"code":main.online.code})
	else:
		if not await wait_for(func():return FileAccess.file_exists(folder+"/code0.json"),"Receive invite code"):await finish();return
		main.online.join_code(JSON.parse_string(FileAccess.get_file_as_string(folder+"/code0.json")).code)
		if not await wait_for(func():return main.online.in_room,"Join room"):await finish();return
	main.online.send({"op":"ready","value":true})
	if not await wait_for(func():return main.online.started and settled(),"Both ready"):await finish();return
	check(not main.reduced_motion,"Full animations override the local preference in online mode")
	for kind in ["faction","initial","initial_resource"]:
		if not await wait_for(func():return settled() and main.game.legal_actions(0).any(func(a):return a.type==kind),"Opening "+kind):await finish();return
		var a=main.game.legal_actions(0).filter(func(item):return item.type==kind)[role if kind=="faction" else 0]
		if not await submit(a):await finish();return
	if not await wait_for(func():return settled() and main.game.phase=="draw","Opening complete"):await finish();return
	write("setup",snapshot())
	if not await wait_for(func():return both("setup"),"Both clients at same setup state"):await finish();return
	var revision=main.online.revision;var nodes=main.game.nodes.duplicate(true);var time_before=main.online.rings[0].seconds();var active=main.online.clock.active[0]
	main._settings()
	var motion=main.large_layer.find_child("ReducedMotion",true,false)
	check(motion!=null and motion.disabled and not motion.button_pressed,"Online setting clearly locks full animation")
	main._change_language("zh" if role==0 else "en")
	main.reduced_motion=true;main.sound_volume=0.25;main.compact=not main.compact;main._save_settings();main._resize()
	await create_timer(0.4).timeout
	check(main.online.revision==revision and main.game.nodes==nodes,"Settings never submit a game action")
	check(not main.reduced_motion and not main.board.reduced_motion,"Full board animation remains mandatory after changing settings")
	if active:check(main.online.rings[0].seconds()<time_before,"Settings do not reset or pause the online clock")
	var file=ConfigFile.new();file.load(main.settings_path);check(file.get_value("settings","reduced_motion",false),"Offline motion preference is saved independently")
	main._close_settings();write("settings",snapshot())
	if not await wait_for(func():return both("settings"),"Both settings profiles changed"):await finish();return
	if main.game.current==0:
		if not await submit(main.game.legal_actions(0).filter(func(a):return a.type=="draw")[0]):await finish();return
		var recruit=main.game.legal_actions(0).filter(func(a):return a.type=="auto")
		check(not recruit.is_empty(),"Shared-deck hand has a recruit")
		if not recruit.is_empty():
			if not await submit(recruit[0]):await finish();return
		write("moved")
	else:
		if not await wait_for(func():return both("settings") and FileAccess.file_exists(folder+"/moved"+str(1-role)+".json") and settled(),"Other client finishes draw and takeover"):await finish();return
	write("after",snapshot())
	if not await wait_for(func():return both("after"),"Both clients agree after mixed settings actions"):await finish();return
	if role==0:main.online.send({"op":"resign"})
	if not await wait_for(func():return main.game.phase=="over","Shared result"):await finish();return
	check(main.game.winner==(1^role),"Winner is identical across languages and seats")
	main.online.leave()
	check(main.reduced_motion,"Leaving online mode restores the stored offline preference")
	await finish()
