class_name UpdateClient
extends Node
## No rule/AI dependencies; HTTP waits never block starting an offline match.
signal changed
var boot
var status="idle"
var available: Dictionary={}
var envelope: Dictionary={}
var downloaded_bytes=0
var request: HTTPRequest
var auto_check=true
var check_timeout=5.0
var checks_started=0
var local_mode=false

func _ready() -> void:
	boot=get_node("/root/UpdateBootstrap")
	local_mode=not OS.has_feature("windows_update")
	if not boot.read_json(boot.folder.path_join("pending.json")).is_empty():
		var saved=boot.read_json(boot.folder.path_join("pending.json"))
		var data=boot.validate_envelope(saved)
		if not data.is_empty() and boot.verified_pack(data) and data.code>current().get("code",0):available=data;envelope=saved;status="ready"
	if boot.startup_notice!="":status="rollback"

func current() -> Dictionary:
	return boot.current_release()

func disabled_for_tests() -> bool:
	var args=OS.get_cmdline_user_args()
	return "--test-defaults" in args or "--safe-mode" in args or "--no-update-check" in args or Array(args).any(func(a):return a.begins_with("--snapshot="))

func startup_check() -> void:
	if auto_check and not disabled_for_tests():check_updates()

func _process(_delta: float) -> void:
	if status=="downloading" and request!=null:
		var count=request.get_downloaded_bytes()
		if count!=downloaded_bytes:downloaded_bytes=count;changed.emit()

func check_updates() -> void:
	if request!=null or status=="ready":return
	checks_started+=1;status="checking";changed.emit()
	# Nonblocking per-frame polling avoids joining a stalled HTTP worker on timeout.
	var r=HTTPRequest.new();r.use_threads=false;r.download_chunk_size=262144;r.timeout=check_timeout;r.body_size_limit=262144;r.max_redirects=0;add_child(r);request=r
	r.request_completed.connect(func(result,code,_headers,body):
		if request!=r:return
		request=null;r.queue_free()
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200:_fail();return
		var parsed=JSON.parse_string(body.get_string_from_utf8())
		if not parsed is Dictionary:_fail("invalid");return
		var data=boot.validate_envelope(parsed)
		if data.is_empty():_fail("invalid");return
		var blocked=boot.read_json(boot.folder.path_join("blocked.json"))
		if data.code<=current().get("code",0):available={};status="latest"
		elif data.code==blocked.get("code",0):status="rollback"
		else:available=data;envelope=parsed;status="available" if data.has("patch") else "full"
		changed.emit(),CONNECT_ONE_SHOT)
	var error=r.request(boot.channel.origin+boot.channel.manifest_path,["Cache-Control: no-cache"])
	if error!=OK:request=null;r.queue_free();_fail()

func _fail(reason: String="offline") -> void:
	status=reason;changed.emit()

func download_update() -> void:
	if request!=null or status!="available" or local_mode:return
	if DirAccess.make_dir_recursive_absolute(boot.folder)!=OK:_fail("storage");return
	var path=boot.pack_path(available)
	if boot.verified_pack(available):_stage();return
	status="downloading";downloaded_bytes=0;changed.emit()
	var r=HTTPRequest.new();r.use_threads=false;r.download_chunk_size=262144;r.timeout=1200;r.max_redirects=0;r.body_size_limit=int(available.patch.bytes);r.download_file=path+".part";add_child(r);request=r
	r.request_completed.connect(func(result,code,_headers,_body):
		if request!=r:return
		request=null;r.queue_free()
		if result!=HTTPRequest.RESULT_SUCCESS or code!=200:_remove_part();_fail();return
		var file=FileAccess.open(path+".part",FileAccess.READ)
		var size=file.get_length() if file!=null else -1
		if file!=null:file.close()
		if size!=int(available.patch.bytes) or FileAccess.get_sha256(path+".part")!=available.patch.sha256:_remove_part();_fail("invalid");return
		if DirAccess.rename_absolute(path+".part",path)!=OK:_fail("storage");return
		_stage(),CONNECT_ONE_SHOT)
	if r.request(available.patch.url)!=OK:request=null;r.queue_free();_remove_part();_fail()

func _stage() -> void:
	if not boot.write_atomic("pending.json",envelope):_fail("storage");return
	status="ready";downloaded_bytes=int(available.patch.bytes);changed.emit()

func _remove_part() -> void:
	if available.has("patch"):
		var path=boot.pack_path(available)+".part"
		if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func cancel() -> void:
	if request==null:return
	var was_download=status=="downloading"
	request.cancel_request();request.queue_free();request=null
	_remove_part();status="available" if was_download else "idle";changed.emit()

func apply_update() -> bool:
	if status!="ready" or local_mode:return false
	var args=PackedStringArray()
	for value in OS.get_cmdline_user_args():
		if value!="--safe-mode" and not value.begins_with("--snapshot=") and not value.begins_with("--snapshot-output="):args.append(value)
	if not args.is_empty():args.insert(0,"--")
	OS.set_restart_on_exit(true,args);get_tree().quit();return true

func _exit_tree() -> void:
	if request!=null:request.cancel_request()
