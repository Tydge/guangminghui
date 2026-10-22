extends SceneTree
## Verifies the final PCK using the script-capable engine; EXE snapshots run separately.
var checks=0
var failures=[]
var args={}
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():
	print("Export QA script initialized")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):args[arg.get_slice("=",0).trim_prefix("--")]=arg.substr(arg.find("=")+1)
	call_deferred("run")
func pixels(texture: Texture2D) -> String:
	var image=texture.get_image()
	if image==null:return ""
	image.convert(Image.FORMAT_RGBA8)
	return hash_bytes(image.get_data())
func hash_bytes(data: PackedByteArray) -> String:
	var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(data);return hash.finish().hex_encode()
func reference():
	CardDB.load_all();var paths=[]
	for id in CardDB.cards:paths.append("res://assets/cards/"+id+".webp")
	for name in DirAccess.get_files_at("res://assets/ui"):
		if name.ends_with(".webp"):paths.append("res://assets/ui/"+name)
	var manifest=[]
	for path in paths:
		var texture=ResourceLoader.load(path,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE)
		check(texture!=null,"Source texture "+path)
		var hash=pixels(texture);check(hash!="","Source pixels "+path)
		var image=Image.new();image.load_webp_from_buffer(FileAccess.get_file_as_bytes(path));image.convert(Image.FORMAT_RGBA8)
		var config=ConfigFile.new();config.load(path+".import")
		manifest.append({"source":path,"imported":config.get_value("remap","path"),"sha256":hash,"source_sha256":hash_bytes(image.get_data()),"width":texture.get_width(),"height":texture.get_height()})
	FileAccess.open(args.reference,FileAccess.WRITE).store_string(JSON.stringify(manifest))
	FileAccess.open(args.reference.get_base_dir()+"/GODOT-LICENSE.txt",FileAccess.WRITE).store_string(Engine.get_license_text())
	FileAccess.open(args.reference.get_base_dir()+"/GODOT-THIRD-PARTY.txt",FileAccess.WRITE).store_string(JSON.stringify({"copyright":Engine.get_copyright_info(),"licenses":Engine.get_license_info()},"  "))
func wait_action(main,p: int,a: Dictionary):
	check(not a.is_empty(),"Smoke action exists")
	main._do_action(p,a)
	while main.busy:await process_frame
func command(g: GameState,type: String) -> Dictionary:
	for a in g.legal_actions(0):
		if a.type==type:return a
	return {}
func capture(name: String):
	if not args.has("output"):return
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(args.output+"/"+name+".png")
func shipped():
	print("Export QA: opening texture reference")
	check(OS.has_feature("english_default"),"Windows share preset has English-default feature")
	print("Checking the exported PCK with Godot's script-capable binary")
	var reference_data=JSON.parse_string(FileAccess.get_file_as_string(args.verify))
	var verified=0
	for item in reference_data:
		if verified==0:print("First texture: ",item.source)
		var texture=ResourceLoader.load(item.source,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE)
		check(texture!=null,"Exported texture "+item.source)
		check(pixels(texture)==item.sha256,"Pixel-exact exported texture "+item.source)
		check(texture.get_width()==item.width and texture.get_height()==item.height,"Original resolution "+item.source)
		verified+=1
		if verified%25==0:print("Verified exported textures: ",verified," / ",reference_data.size())
	check(FileAccess.file_exists("res://data/cards.json") and FileAccess.file_exists("res://data/localization/en.json"),"Runtime JSON shipped")
	check(not FileAccess.file_exists("res://data/card_sync_config.json") and not FileAccess.file_exists("res://AGENTS.md") and not FileAccess.file_exists("res://tests/test_match.gd"),"No local configuration, instructions or tests shipped")
	var main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://windows-export-qa-%d.cfg"%OS.get_process_id();root.add_child(main);await process_frame
	check(GameLocale.english(),"Fresh exported install defaults to English")
	check(root.title=="Illuminati","English window title")
	main.sound_volume=0;main.presentation_time_scale=0.02;main.board.motion_time_scale=0.02
	CardDB.finish_art_requests();await capture("menu-en")
	main._start_game(568);main.modal_open=true
	await wait_action(main,0,command(main.game,"faction"));main.modal_open=true
	await wait_action(main,0,command(main.game,"initial"));main.modal_open=true
	await wait_action(main,0,command(main.game,"initial_resource"));main.modal_open=true
	var g=main.game;check(g.validate().is_empty(),"Shipped opening conserves all cards")
	main._refresh();main.board.fit_all();await create_timer(0.3).timeout;await capture("board-en")
	main._inspect("E16");CardDB.finish_art_requests();await process_frame;await capture("safe-house-en");main._close_inspection();main.modal_open=true
	var before_rng=g.rng.state;main._change_language("zh");check(not GameLocale.english() and g.rng.state==before_rng,"Chinese switch preserves match and RNG")
	main._change_language("en");check(GameLocale.english(),"Can switch back to English");main._close_settings();main.modal_open=true
	GameLocale.set_language("zh");main._load_settings();check(GameLocale.english(),"Saved language restored")
	main._close_inspection();main._clear(main.large_layer);main.modal_open=true
	# Drive a short real UI sequence, including the AI's own turn.
	if g.current==0 and g.phase=="draw":await wait_action(main,0,command(g,"draw"));main.modal_open=true
	if g.current==0 and g.phase=="main":
		var recruit=command(g,"auto")
		if not recruit.is_empty():await wait_action(main,0,recruit);main.modal_open=true
		if g.phase=="main":await wait_action(main,0,command(g,"end"))
	main.modal_open=false;main._schedule_ai()
	var deadline=Time.get_ticks_msec()+45000
	while (main.busy or main.thinking or g.current==1 or g.phase=="choice") and Time.get_ticks_msec()<deadline:
		if not main.busy and not main.thinking and g.phase in ["choice","discard","battle","plot_response"]:
			var options=g.legal_actions(0)
			if not options.is_empty():
				var skip=options.filter(func(a):return a.type in ["pass","accept_plot"])
				await wait_action(main,0,skip[0] if not skip.is_empty() else options[0])
		await process_frame
	main.modal_open=true;check(not main.busy and not main.thinking and g.current==0,"Exported AI completes its turn")
	check(g.validate().is_empty(),"Shipped UI/AI sequence conserves cards")
	check(GameLocale.missing.is_empty(),"No missing English during smoke sequence "+str(GameLocale.missing))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path));main.queue_free();await process_frame;await process_frame
func run():
	if args.has("reference"):reference()
	else:await shipped()
	print("WINDOWS EXPORT: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
