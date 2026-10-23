extends SceneTree
## Explicit opt-in integration test against a signed fixture on the update host.
var checks=0
var failures=[]
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func settled(client,seconds=20):
	var deadline=Time.get_ticks_msec()+int(seconds*1000)
	while client.request!=null and Time.get_ticks_msec()<deadline:
		await process_frame
	check(client.request==null,"HTTP request finishes within deadline")
	if client.request!=null:client.cancel()
func run():
	if "--live-update-test" not in OS.get_cmdline_user_args():print("Live test requires --live-update-test");quit(2);return
	var main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://live-update-qa-settings.cfg";root.add_child(main);await process_frame
	main.updates.local_mode=false
	var b=load("res://scripts/update_bootstrap.gd").new();main.updates.boot=b
	b.folder="user://live-update-qa-%d"%OS.get_process_id()
	if "--production-current" in OS.get_cmdline_user_args():
		main.updates.check_updates();await settled(main.updates)
		check(main.updates.status=="latest","Published channel signature and current version accepted")
		main.queue_free();await process_frame;await process_frame;b.free()
		print("LIVE CURRENT CHECKS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1);return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--update-storage="):b.folder=arg.trim_prefix("--update-storage=")
	b.channel.manifest_path="/releases/qa-20261023/manifest.json"
	main.updates.check_updates();await settled(main.updates)
	check(main.updates.status=="available","Public HTTPS and real release signature accepted")
	if main.updates.status!="available":main.queue_free();await process_frame;b.free();print(JSON.stringify(failures));quit(1);return
	main._start_game(1518);main.modal_open=true;var before=main.game.rng.state
	main.updates.download_update();await process_frame;main.updates.cancel()
	check(main.updates.status=="available" and not FileAccess.file_exists(b.pack_path(main.updates.available)+".part"),"Cancellation removes incomplete download")
	main.updates.download_update();await settled(main.updates,30)
	check(main.updates.status=="ready" and b.verified_pack(main.updates.available),"Real HTTPS download staged after hash verification")
	check(main.game.rng.state==before and main.game.phase=="setup_faction","Background download leaves local match untouched")
	check(not FileAccess.file_exists("res://probe.gdc"),"Downloaded code is not mounted during current match")
	main._menu();main.updates.boot=b
	var pending=b.read_json(b.folder+"/pending.json");var path=b.pack_path(main.updates.available)
	check(not pending.is_empty() and FileAccess.file_exists(path),"Valid pending manifest and immutable cached file saved")
	var good=main.updates.available.duplicate(true)
	main.updates.status="idle";b.channel.manifest_path="/releases/qa-20261023/bad-hash.json"
	main.updates.check_updates();await settled(main.updates);main.updates.download_update();await settled(main.updates,30)
	check(main.updates.status=="invalid","Incorrect downloaded hash rejected over real HTTPS")
	check(b.read_json(b.folder+"/pending.json")==pending,"Failed download preserves earlier valid staged update")
	main.updates.available=good;main.updates.envelope=pending;main.updates.status="ready"
	# Test the restart API without actually relaunching this script-capable QA engine.
	if not OS.has_feature("windows_update"):
		b.boot();check(b.mounted and load("res://probe.gd").marker()=="compiled patch loaded","Bootstrap mounts compiled GDScript before game reload")
		b.confirm_startup()
	if "--leave-staged" not in OS.get_cmdline_user_args():
		for name in DirAccess.get_files_at(b.folder):DirAccess.remove_absolute(b.folder+"/"+name)
		DirAccess.remove_absolute(b.folder)
	main.queue_free();await process_frame;await process_frame;b.free()
	print("LIVE UPDATE CHECKS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
