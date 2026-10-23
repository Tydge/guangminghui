extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame
	if "--english" in OS.get_cmdline_user_args():GameLocale.set_language("en")
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.15;main.ai.rng.seed=469;main._start_game(469)
	var driver=AiAgent.new();driver.rng.seed=300
	var started=Time.get_ticks_msec();var player_commands=0
	while main.game.phase!="over" and Time.get_ticks_msec()-started<300000:
		if main.busy or main.thinking:await create_timer(0.03).timeout;continue
		var legal=main.game.legal_actions(0)
		if not legal.is_empty():
			var a=driver.pick(main.game.observation(0));player_commands+=1
			await main._do_action(0,a)
		else:main._schedule_ai()
		await process_frame
	var success=main.game.phase=="over" and main.game.validate().is_empty()
	if GameLocale.english():success=success and GameLocale.missing.is_empty()
	var report={"language":GameLocale.language,"untranslated":GameLocale.missing,"complete":success,"winner":main.game.winner,"player_commands":player_commands,"turns":main.game.turns,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,"phase":main.game.phase}
	print("UI MATCH: "+JSON.stringify(report))
	var f=FileAccess.open("res://tests/match-en-report.json" if GameLocale.english() else "res://tests/match-report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"));main._menu();CardDB.finish_art_requests();await create_timer(0.6).timeout;main.queue_free();await process_frame;await process_frame;quit(0 if success else 1)
