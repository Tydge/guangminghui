extends SceneTree
var failures=[]
var checks=0
var pids=[]
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	var folder=ProjectSettings.globalize_path("res://work/online-settings-%d"%OS.get_process_id());DirAccess.make_dir_recursive_absolute(folder)
	var port=21000+OS.get_process_id()%1000
	pids.append(OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",folder+"/server.log","--script","res://server/online_server.gd","--","--test-defaults","--port="+str(port),"--rooms="+folder+"/rooms"]))
	var deadline=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline and (not FileAccess.file_exists(folder+"/server.log") or "ONLINE READY" not in FileAccess.get_file_as_string(folder+"/server.log")):await process_frame
	for p in [0,1]:pids.append(OS.create_process(OS.get_executable_path(),["--headless","--path",ProjectSettings.globalize_path("res://"),"--log-file",folder+"/peer"+str(p)+".log","--script","res://tests/online_settings_peer.gd","--","--test-defaults","--folder="+folder,"--role="+str(p),"--url=ws://127.0.0.1:"+str(port)]))
	deadline=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline and (OS.is_process_running(pids[1]) or OS.is_process_running(pids[2])):await process_frame
	for p in [0,1]:
		var path=folder+"/result"+str(p)+".json"
		check(FileAccess.file_exists(path),"Independent client completed: "+str(p))
		if FileAccess.file_exists(path):
			var data=JSON.parse_string(FileAccess.get_file_as_string(path));checks+=int(data.checks);check(data.failures.is_empty(),"Independent settings client: "+str(data.failures))
		check(not "ERROR:" in FileAccess.get_file_as_string(folder+"/peer"+str(p)+".log"),"No errors in client "+str(p))
	for name in ["setup","settings","after"]:
		var a=folder+"/"+name+"0.json";var b=folder+"/"+name+"1.json"
		check(FileAccess.file_exists(a) and FileAccess.file_exists(b),"Both settings snapshots exist: "+name)
		if FileAccess.file_exists(a) and FileAccess.file_exists(b):check(JSON.parse_string(FileAccess.get_file_as_string(a))==JSON.parse_string(FileAccess.get_file_as_string(b)),"Authoritative public states identical: "+name)
	for pid in pids:
		if OS.is_process_running(pid):OS.kill(pid)
	print("ONLINE INDEPENDENT SETTINGS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
