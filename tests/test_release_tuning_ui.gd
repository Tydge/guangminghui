extends "res://tests/test_contact_tuning_ui.gd"
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
	main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://release-tuning-ui.cfg";root.add_child(main);await process_frame
	main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.02
	for language in ["zh","en"]:
		GameLocale.set_language(language)
		for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
			root.size=profile.size;main.compact=profile.compact;await process_frame
			main.game=fixture("I07");main._refresh();await main.board.wait_for_settlement();main.modal_open=true
			for id in ["I07","G170","P52","P55","P67","E01","E02","E07","E12","E14","E15","E17","E19"]:
				main._inspect(id);await process_frame
				var cards=main.find_children("*","CardView",true,false).filter(func(c):return c.id==id and c.full)
				if profile.compact:
					var labels=main.detail_layer.find_children("*","Label",true,false)
					var body="\n".join(labels.map(func(label):return label.text))
					check(body.contains(GameLocale.text(CardDB.get_card(id).effect)),"Complete updated effect is present in mobile reader "+id+language)
					check(main.get_global_rect().encloses(main.detail_layer.get_child(0).get_global_rect()),"Mobile reader stays within viewport "+id+language)
				else:check(cards.size()==1,"Updated card can be inspected "+id+language+profile.name)
				if not profile.compact and not cards.is_empty():
					for frame in 120:
						if cards[0].art!=null:break
						await process_frame
					check(cards[0].art!=null,"Updated card artwork finishes its asynchronous load "+id+language)
					var rows=cards[0].text_layout()
					check(not rows.is_empty() and not rows.back().text.ends_with("…"),"Complete effect fits the full card "+id+language+profile.name)
				if id in ["E17","P67"]:await take(language+"-"+profile.name+"-"+id)
				main._close_inspection();main.modal_open=true
			var g=main.game
			for id in ["E17","G075"]:
				g.decks[g.card(id).kind].erase(id)
				if id=="E17":g.nodes[id]={"card":id,"owner":0,"parent":"","token":1,"attached":[],"resource_slot":0}
				else:g._enter(id,0,"R0",0);g.nodes[id].devastated=true
			main._refresh();await main.board.wait_for_settlement();main.modal_open=false
			var before=JSON.stringify([g.nodes,g.recharged,g.rng.state]);main._do_action(0,command("resource",{"src":"E17","target":"G075"}))
			check(main.busy and JSON.stringify([g.nodes,g.recharged,g.rng.state])==before,"Medical rebuild/recovery waits until the source and target animation finishes")
			await settled();main.modal_open=true
			check(not g.wave.devastated("G075") and g.token("G075") and g.recharged.has("G075"),"Displayed rebuild commits the eligible restored action")
			main._menu()
	check(GameLocale.missing.is_empty(),"All changed card text and action labels are translated: "+str(GameLocale.missing))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path));main.queue_free();await process_frame
	print("RELEASE TUNING UI: "+JSON.stringify({"checks":checks,"failures":failures,"captures":captures}));quit(0 if failures.is_empty() else 1)
