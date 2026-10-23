extends SceneTree
var checks=0
var failures=[]
var key: CryptoKey
var boot
var payload: Dictionary
var folder=""
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func signed(data: Dictionary) -> Dictionary:
	var text=JSON.stringify(data)
	return {"payload":Marshalls.raw_to_base64(text.to_utf8_buffer()),"signature":Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256,text.sha256_buffer(),key))}
func clone_boot():
	var b=load("res://scripts/update_bootstrap.gd").new();b.channel=boot.channel.duplicate(true);b.bundled=boot.bundled.duplicate(true);b.folder=folder;return b
func run():
	print("Update QA: manifest validation")
	boot=load("res://scripts/update_bootstrap.gd").new()
	folder="user://update-regression-%d"%OS.get_process_id();boot.folder=folder;DirAccess.make_dir_recursive_absolute(folder)
	key=Crypto.new().generate_rsa(2048);boot.channel.public_key=key.save_to_string(true)
	var source=folder+"/probe.txt";FileAccess.open(source,FileAccess.WRITE).store_string("mounted after restart")
	var pack=folder+"/fixture.pck";var writer=PCKPacker.new();writer.pck_start(pack);writer.add_file("res://update-test-probe.txt",source);writer.flush()
	var file=FileAccess.open(pack,FileAccess.READ);var bytes=file.get_length();file.close()
	var digest=FileAccess.get_sha256(pack)
	DirAccess.rename_absolute(pack,folder+"/"+digest+".pck")
	payload=boot.bundled.duplicate(true);payload.merge({"schema":1,"product":"illuminati","code":boot.bundled.code+1,"version":"0.2.0-test","patch":{"url":boot.channel.origin+"/releases/test/update.pck","sha256":digest,"bytes":bytes}} ,true)
	check(not boot.validate_envelope(signed(payload)).is_empty(),"Valid signed manifest accepted")
	var forged=signed(payload);forged.signature=Marshalls.raw_to_base64(PackedByteArray([1,2,3]))
	check(boot.validate_envelope(forged).is_empty(),"Invalid signature rejected")
	for change in [{"base_id":"other"},{"product":"other"},{"engine":"0.0"},{"platform":"other"},{"min_bootstrap":99},{"schema":9},{"code":0},{"code":1.5},{"version":35}]:
		var bad=payload.duplicate(true);bad.merge(change,true);check(boot.validate_envelope(signed(bad)).is_empty(),"Invalid manifest field "+str(change))
	for change in [{"url":"https://untrusted.invalid/releases/a.pck"},{"sha256":"../../test"},{"bytes":0},{"bytes":1073741825}]:
		var bad=payload.duplicate(true);bad.patch.merge(change,true);check(boot.validate_envelope(signed(bad)).is_empty(),"Invalid file descriptor "+str(change))
	var client=UpdateClient.new();root.add_child(client);client.boot=boot;client.local_mode=false
	print("Update QA: staging and boot")
	client.available=payload;client.envelope=signed(payload);client.status="available"
	var current=client.current().duplicate(true);client.download_update()
	check(client.status=="ready","Verified cached patch staged")
	check(client.current()==current and not FileAccess.file_exists("res://update-test-probe.txt"),"Staging does not mount or change running version")
	boot.boot();check(boot.mounted and FileAccess.get_file_as_string("res://update-test-probe.txt")=="mounted after restart","Early boot mounts native PCK")
	check(boot.read_json(folder+"/booting.json").code==payload.code,"Unconfirmed patch has rollback marker")
	boot.confirm_startup();check(not FileAccess.file_exists(folder+"/booting.json"),"Usable menu confirms startup")
	check(client.current().code==payload.code,"Client reports mounted release")
	var second=payload.duplicate(true);second.code+=1
	boot.write_atomic("pending.json",signed(second));var candidate=clone_boot();candidate.boot()
	check(candidate.active.code==second.code,"Next patch replaces previous pending atomically")
	var recovered=clone_boot();recovered.boot()
	check(recovered.mounted and recovered.active.code==payload.code and recovered.startup_notice=="rollback","Failed startup rolls back to previous verified patch")
	check(recovered.read_json(folder+"/blocked.json").code==second.code,"Failed build is not automatically retried")
	recovered.confirm_startup();candidate.free();recovered.free();client.queue_free();await process_frame
	# A real slow HTTP request cannot prevent game setup, settings, or cancellation.
	var server=TCPServer.new();var port=19000+OS.get_process_id()%1000
	print("Update QA: slow HTTP and UI")
	check(server.listen(port,"127.0.0.1")==OK,"Slow-response fixture listens")
	var main=load("res://scenes/main.tscn").instantiate();root.add_child(main);print("Update QA: main created");await process_frame
	print("Update QA: main first frame")
	main.updates.boot=clone_boot();main.updates.local_mode=false;var test_boot=main.updates.boot;test_boot.channel.origin="http://127.0.0.1:"+str(port);test_boot.channel.manifest_path="/never-respond";main.updates.check_timeout=1.0
	var before=Time.get_ticks_msec();main.updates.check_updates()
	print("Update QA: check started")
	check(Time.get_ticks_msec()-before<100,"Version check returns without waiting for network")
	main._start_game(3461);main.modal_open=true;var rng=main.game.rng.state
	print("Update QA: local game started")
	check(main.game.phase=="setup_faction","Local game starts during pending check")
	main._updates();print("Update QA: window opened");await process_frame
	check(main.update_window!=null and main.update_window.cancel_button.visible,"Manual window exposes check cancellation")
	main.update_window.close();check(main.updates.request!=null,"Closing panel leaves check in background")
	print("Update QA: window closed")
	var deadline=Time.get_ticks_msec()+4000;var frames=0
	while main.updates.request!=null and Time.get_ticks_msec()<deadline:
		frames+=1
		await process_frame
	print("Update QA: timeout completed")
	check(main.updates.status=="offline" and frames>10,"Slow server times out while frames keep running")
	check(main.game.rng.state==rng and main.game.phase=="setup_faction","Timeout leaves match and RNG unchanged")
	main.updates.available=payload;main.updates.status="downloading";main.updates.downloaded_bytes=bytes/2;main._updates();await process_frame
	print("Update QA: download progress and apply gate")
	check(absf(main.update_window.meter.value-50)<1,"Progress displays downloaded bytes")
	check(not main.update_window.apply_button.visible,"No apply before download finishes")
	main.updates.status="ready";main.update_window.render();check(main.update_window.apply_button.disabled,"Applying never interrupts an active match")
	main.update_window.close();main._menu();main._updates();await process_frame
	check(not main.update_window.apply_button.disabled,"Applying enabled at main menu")
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--output=") or DisplayServer.get_name()=="headless":continue
		var output=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(output)
		for language in ["en","zh"]:
			main.update_window.close();GameLocale.set_language(language);main._menu();main._updates()
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/updates-"+language+".png")
	main.update_window.close();main.updates.status="idle";main.updates.check_updates();main.updates.cancel()
	check(main.updates.request==null and main.updates.status=="idle","Check cancels immediately")
	main.queue_free();await process_frame;await process_frame;test_boot.free();server.stop()
	for name in ["probe.txt",digest+".pck","active.json","previous.json","pending.json","booting.json","blocked.json"]:
		var path=folder+"/"+name
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder);boot.free()
	var restart_client=UpdateClient.new();root.add_child(restart_client);restart_client.local_mode=false
	check(not restart_client.apply_update(),"Cannot apply an unfinished download")
	restart_client.status="ready"
	check(restart_client.apply_update(),"Ready update schedules automatic reopen")
	check(OS.is_restart_on_exit_set() and OS.get_restart_on_exit_arguments()[0]=="--","Native restart API preserves user argument separator")
	OS.set_restart_on_exit(false);restart_client.free()
	print("UPDATE CHECKS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
