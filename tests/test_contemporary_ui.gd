extends SceneTree
var main
var checks=0
var failures=[]
var captures=[]
var folder=""
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func take(name: String):
	for i in 3:await process_frame
	if folder=="" or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+name+".png");captures.append(name)
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://contemporary-ui-test.cfg";root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.02
	for language in ["zh","en"]:
		GameLocale.set_language(language)
		for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
			root.size=profile.size;main.compact=profile.compact;await process_frame;main._menu();await take(language+"-"+profile.name+"-difficulty")
			var choices=main.overlay.find_child("DifficultyOptions",true,false);check(choices!=null and choices.get_child_count()==3,"Three difficulty choices visible")
			for level in ["easy","normal","hard"]:
				main.ai_difficulty=level;main._start_game(591);main.modal_open=true;check(main.ai.difficulty==level,"Selected difficulty reaches live AI")
			main.faction_page=2;main._refresh();main.modal_open=true;await take(language+"-"+profile.name+"-new-factions")
			main._settings();var difficulty=main.large_layer.find_child("DifficultyChoice",true,false);check(difficulty!=null and difficulty.item_count==3,"Settings exposes all difficulties")
			var before=JSON.stringify([main.game.nodes,main.game.hands,main.game.rng.state]);difficulty.item_selected.emit(0);check(main.ai_difficulty=="easy" and JSON.stringify([main.game.nodes,main.game.hands,main.game.rng.state])==before,"Changing difficulty preserves match and RNG");main._close_settings();main.modal_open=true
			main.collection_filter="group";main.interactions.catalog(true);await process_frame;await process_frame
			var scroll=main.large_layer.find_child("CatalogScroll",true,false);var card=main.large_layer.find_child("CatalogGrid",true,false).get_child(0);var point=card.global_position+Vector2(80,80)
			check(card.wheel_zoom.get_connections().is_empty(),"Catalog cards do not own board zoom")
			for i in 4:
				var event=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=true;root.push_input(event,true);await process_frame
			check(scroll.scroll_vertical>0,"Wheel over catalog artwork scrolls the catalog")
			await take(language+"-"+profile.name+"-catalog-scroll")
			for id in ["I09","I12","G138","G153","G161","P64","P67","E21","E22","E23"]:
				main._inspect(id);await process_frame;check(main.interactions.reader_id==id,"Reader opens new card "+id);await take(language+"-"+profile.name+"-reader-"+id);main._close_inspection();main.modal_open=true
			main._clear(main.large_layer);main.game.phase="choice";main.game.choice={"kind":"n_relic","label":"秘宝走私 · 可取1张秘宝","peek":["E01","E19","E21"],"options":["E19","E21"],"player":0,"optional":true};main._refresh();main.modal_open=true;await process_frame
			check(main.overlay.find_children("*","CardView",true,false).size()==3,"Smuggling shows all three inspected cards, including non-Relics")
			var disabled=main.overlay.find_children("*","Button",true,false).filter(func(btn):return btn.text==GameLocale.text("非秘宝 · 洗回"));check(disabled.size()==1 and disabled[0].disabled,"Non-Relic remains readable but cannot be taken")
			await take(language+"-"+profile.name+"-smuggling")
	check(GameLocale.missing.is_empty(),"No untranslated new UI strings: "+str(GameLocale.missing))
	var config=ConfigFile.new();check(config.load(main.settings_path)==OK and config.get_value("settings","difficulty")=="easy","Difficulty uses isolated persistent settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path));main._menu();main.queue_free();await process_frame
	print("CONTEMPORARY UI: "+JSON.stringify({"checks":checks,"failures":failures,"captures":captures}));quit(0 if failures.is_empty() else 1)
