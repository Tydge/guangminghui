extends Node
## Deliberately independent of game classes. Mount before any game scripts preload.
const PROTOCOL=1
var channel: Dictionary={}
var bundled: Dictionary={}
var active: Dictionary={}
var folder=""
var startup_notice=""
var mounted=false

func _init() -> void:
	channel=read_json("res://data/update_channel.json")
	bundled=read_json("res://data/release.json")
	folder="user://updates/"+str(channel.get("base_id","unknown"))
	var args=OS.get_cmdline_user_args()
	if "--updates-test" in args:
		for arg in args:
			if arg.begins_with("--update-storage="):folder=arg.trim_prefix("--update-storage=")
	if (not OS.has_feature("windows_update") and "--updates-test" not in args) or "--test-defaults" in args or "--safe-mode" in args:return
	boot()

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func write_atomic(name: String,value: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	var path=folder.path_join(name)
	var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(value));file.close()
	return DirAccess.rename_absolute(path+".tmp",path)==OK

func remove(name: String) -> void:
	var path=folder.path_join(name)
	if FileAccess.file_exists(path):DirAccess.remove_absolute(path)

func validate_envelope(envelope: Dictionary) -> Dictionary:
	if not envelope.get("payload") is String or not envelope.get("signature") is String:return {}
	if envelope.payload.length()>350000 or envelope.signature.length()>2048:return {}
	var bytes=Marshalls.base64_to_raw(envelope.payload)
	var signature=Marshalls.base64_to_raw(envelope.signature)
	if bytes.is_empty() or signature.is_empty():return {}
	var key=CryptoKey.new()
	if key.load_from_string(channel.get("public_key",""),true)!=OK:return {}
	if not Crypto.new().verify(HashingContext.HASH_SHA256,bytes.get_string_from_utf8().sha256_buffer(),signature,key):return {}
	var data=JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary:return {}
	if data.get("schema")!=PROTOCOL or data.get("product")!=channel.get("product"):return {}
	if data.get("base_id")!=channel.get("base_id") or data.get("engine")!=bundled.get("engine"):return {}
	if data.get("platform")!=bundled.get("platform") or data.get("min_bootstrap",1)>PROTOCOL:return {}
	if not data.get("version") is String or data.version.length()>48:return {}
	if not data.get("code") is float and not data.get("code") is int:return {}
	if data.code!=floor(data.code) or data.code<1 or data.code>9007199254740991:return {}
	for kind in ["patch","full"]:
		if not data.has(kind):continue
		var item=data[kind]
		if not item is Dictionary or not item.get("url") is String or not item.get("sha256") is String:return {}
		if not item.url.begins_with(channel.get("origin","")+"/releases/"):return {}
		if item.sha256.length()!=64 or not item.sha256.is_valid_hex_number(false):return {}
		if not item.get("bytes") is float and not item.get("bytes") is int:return {}
		if item.bytes<1 or item.bytes>1073741824 or item.bytes!=floor(item.bytes):return {}
	if not channel.get("origin","").begins_with("https://"):return {}
	return data

func pack_path(data: Dictionary) -> String:
	return folder.path_join(data.patch.sha256+".pck") if data.has("patch") else ""

func verified_pack(data: Dictionary) -> bool:
	if not data.has("patch"):return false
	var path=pack_path(data)
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:return false
	var size=file.get_length();file.close()
	return size==int(data.patch.bytes) and FileAccess.get_sha256(path)==data.patch.sha256

func boot() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	# A patch that never reached a usable menu is not retried on every launch.
	var failed=read_json(folder.path_join("booting.json"))
	if not failed.is_empty():
		write_atomic("blocked.json",failed)
		var previous=read_json(folder.path_join("previous.json"))
		if previous.is_empty():remove("active.json")
		else:write_atomic("active.json",previous)
		remove("booting.json");remove("pending.json");startup_notice="rollback"
	var pending=read_json(folder.path_join("pending.json"))
	var candidate=validate_envelope(pending)
	if not candidate.is_empty() and candidate.code>bundled.get("code",0) and verified_pack(candidate):
		var previous=read_json(folder.path_join("active.json"))
		if not previous.is_empty():write_atomic("previous.json",previous)
		else:remove("previous.json")
		if write_atomic("active.json",pending):remove("pending.json")
	elif not pending.is_empty():remove("pending.json");startup_notice="invalid"
	var envelope=read_json(folder.path_join("active.json"))
	var data=validate_envelope(envelope)
	if data.is_empty() or data.code<=bundled.get("code",0):return
	if not verified_pack(data):remove("active.json");startup_notice="invalid";return
	write_atomic("booting.json",{"code":data.code})
	if ProjectSettings.load_resource_pack(pack_path(data)):
		active=data;mounted=true
	else:
		remove("active.json");remove("booting.json");startup_notice="invalid"

func confirm_startup() -> void:
	if mounted:remove("booting.json")

func current_release() -> Dictionary:
	return active if mounted else bundled
