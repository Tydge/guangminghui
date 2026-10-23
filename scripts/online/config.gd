extends RefCounted
const PROTOCOL=1
const URL="wss://47.119.37.251/play"
const RESPONSE_MS=15000
const OPENING_MS=60000
const TURN_MS=120000
const GRACE_MS=90000
static func build() -> Dictionary:
	return {"protocol":PROTOCOL,"code":JSON.parse_string(FileAccess.get_file_as_string("res://data/release.json")).code,"cards":FileAccess.get_sha256("res://data/cards.json")}
static func compatible(value: Dictionary) -> bool:
	var local=build()
	return value.get("protocol",-1)==local.protocol and value.get("code",-1)==local.code and value.get("cards","")==local.cards
static func secret() -> String:return Crypto.new().generate_random_bytes(32).hex_encode()
