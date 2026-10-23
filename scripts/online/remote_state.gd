extends GameState
## Read-only UI model: hidden cards are anonymous counts; rules run on the host.
const ViewProjection=preload("res://scripts/online/projection.gd")
var packet={}
var preview_cache={}
var opening_waiting=false
func _init():super(1)
func install(data: Dictionary) -> void:
	packet=data;preview_cache.clear()
	for key in ["nodes","phase","current","serial","auto_used","deploy_used","battle","last_battle","pending_plot","resume_phase","used","recharged","captured","rewards","failed_recruits","exposed","world","logs","winner","victory","end_requested","last_event","scrap","factions","turns","destroyed","attacked","graves","initiative","mulligans","resource_rerolls","hands","decks","discards","locked","choice","resource_candidates","opening_waiting"]:
		if data.has(key):set(key,data[key].duplicate(true) if data[key] is Array or data[key] is Dictionary else data[key])
	wave.plans.clear()
	for who in data.get("plans",{}):wave.plans[int(who)]=data.plans[who]
func legal_actions(p: int) -> Array:return packet.get("actions",[]) if p==0 else []
func act(_p: int,_a: Dictionary) -> bool:return false
func stat(id: String,key: String,raw: bool=false) -> int:
	return int(packet.stats[id].get(key,0)) if not raw and packet.get("stats",{}).has(id) else super.stat(id,key,raw)
func alignments(id: String) -> Array:return packet.stats[id].align if packet.get("stats",{}).has(id) else super.alignments(id)
func tags(id: String) -> Array:return packet.stats[id].tags if packet.get("stats",{}).has(id) else super.tags(id)
func card_context(id: String) -> Dictionary:return packet.contexts[id] if packet.get("contexts",{}).has(id) else super.card_context(id)
func self_power(id: String) -> int:return packet.get("self_powers",{}).get(id,super.self_power(id))
func action_limit(id: String) -> int:return packet.get("action_limits",{}).get(id,1)
func hand_limit(p: int) -> int:return packet.get("limits",[5,5])[p]
func resource_hand_limit(p: int) -> int:return packet.get("resource_limits",[2,2])[p]
func goal(p: int) -> Dictionary:return packet.get("goals",[{"text":"","ratio":0,"met":false},{"text":"","ratio":0,"met":false}])[p]
func battle_values(b: Dictionary={}) -> Dictionary:return packet.get("battle_values",{}) if b.is_empty() else super.battle_values(b)
func attack_preview(src: String,target: String,mode: String,a: Dictionary={}) -> Dictionary:
	var key=ViewProjection.preview_key(a)
	return preview_cache[key].values if preview_cache.has(key) else super.attack_preview(src,target,mode,a)
func attack_options(_src: String,_target: String,_mode: String,a: Dictionary={}) -> Dictionary:
	return preview_cache.get(ViewProjection.preview_key(a),{}).get("options",{"supports":[],"plots":[],"support_total":0,"resources":[],"resource_total":0,"mobilized_supports":0})
