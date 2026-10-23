extends RefCounted
## Only this explicit projection crosses the network. Never serialize GameState/RNG.
const PLAYER_KEYS=["owner","player","attacker","defender","responder","winner","current","from_player","to_player","actor"]
static func relative(value,p: int,key: String=""):
	if value is Dictionary:
		var out={}
		for k in value:out[relative(k,p,"__key")]=relative(value[k],p,str(k))
		return out
	if value is Array:return value.map(func(v):return relative(v,p))
	if value is String:
		if value in ["R0","R1"]:return "R%d"%(int(value.substr(1))^p)
		var text=value.replace("玩家一","你" if p==0 else "对手").replace("玩家二","对手" if p==0 else "你")
		if p==1 and key=="__key" and (text.ends_with(":0") or text.ends_with(":1")):text=text.left(-1)+str(1-int(text.right(1)))
		return text
	if key in PLAYER_KEYS and (value is int or value is float) and (value==0 or value==1):return int(value)^p
	return value

static func visible(g: GameState,p: int) -> Array:
	var ids=[]
	for id in g.nodes:
		ids.append(id);ids.append_array(g.nodes[id].attached)
	for kind in g.decks:
		ids.append_array(g.hands[p][kind]);ids.append_array(g.discards[kind])
	ids.append_array(g.scrap);ids.append_array(g.exposed)
	for grave in g.graves:ids.append_array(grave)
	ids.append(g.world);ids.append(g.pending_plot.get("id",""));ids.append_array(g.battle.get("spent",[]))
	if g.battle.get("hand_target",false):ids.append(g.battle.target)
	ids.append_array(g.resource_candidates[p])
	if g.choice.get("player",-1)==p:
		ids.append_array(g.choice.get("options",[]));ids.append_array(g.choice.get("peek",[]));ids.append(g.choice.get("revealed_card",""))
	return ids

static func view(g: GameState,p: int,actions: Array=[]) -> Dictionary:
	var data={}
	for key in ["nodes","phase","current","serial","auto_used","deploy_used","battle","last_battle","pending_plot","resume_phase","used","recharged","captured","rewards","failed_recruits","exposed","world","logs","winner","victory","end_requested","last_event","scrap"]:
		data[key]=relative(g.get(key),p,key)
	# last_event can name a privately drawn/stolen card; UI only needs public motion cues.
	for key in ["id","target"]:
		if data.last_event.has(key) and data.last_event[key] not in relative(visible(g,p),p):data.last_event.erase(key)
	for key in ["factions","turns","destroyed","attacked","graves","initiative","mulligans","resource_rerolls"]:
		var a=g.get(key);data[key]=relative([a[p],a[1-p]],p) if a.size()==2 else []
	data.hands=[g.hands[p].duplicate(true),{"group":[],"plot":[],"resource":[]}]
	for kind in g.decks:
		for i in g.hands[1-p][kind].size():
			var id=g.hands[1-p][kind][i]
			data.hands[1][kind].append(id if id in g.exposed else "_hidden_%s_%d"%[kind,i])
	data.decks={}
	for kind in g.decks:data.decks[kind]=Array(range(g.decks[kind].size()))
	data.discards=g.discards.duplicate(true)
	data.locked=g.locked.filter(func(id):return id in visible(g,p))
	data.choice=relative(g.choice,p) if g.choice.get("player",-1)==p else {"player":1,"kind":"remote_wait"}
	data.resource_candidates=[g.resource_candidates[p].duplicate(),[]]
	data.opening_waiting=g.phase.begins_with("setup") and g.opening_picks.get(g.phase.trim_prefix("setup_"),["",""])[p]!=""
	data.actions=relative(actions,p)
	data.stats={};data.contexts={};data.self_powers={};data.action_limits={}
	for id in g.nodes:
		var local_id=relative(id,p)
		data.stats[local_id]={"p":g.stat(id,"p"),"gp":g.stat(id,"gp"),"r":g.stat(id,"r"),"slots":g.stat(id,"slots"),"align":g.alignments(id),"tags":g.tags(id)}
		data.contexts[local_id]=relative(g.card_context(id),p)
		data.self_powers[local_id]=g.self_power(id);data.action_limits[local_id]=g.action_limit(id)
	data.goals=[g.goal(p),g.goal(1-p)]
	data.limits=[g.hand_limit(p),g.hand_limit(1-p)]
	data.resource_limits=[g.resource_hand_limit(p),g.resource_hand_limit(1-p)]
	data.battle_values=relative(g.battle_values(),p)
	data.plans={}
	for who in g.wave.plans:data.plans[str(int(who)^p)]=g.wave.plans[who]
	return data

static func presentation(before: GameState,after: GameState,p: int,actor: int,a: Dictionary,plan: Dictionary) -> Dictionary:
	var out=relative(plan,p);var known=visible(before,p)+visible(after,p)
	for i in plan.moves.size():
		if plan.moves[i].id not in known:out.moves[i].id="_hidden_motion_%d"%i
	# These are public board nodes, never hands, deck orders or private choice buffers.
	var reveals=[]
	for id in before.wave.presentation_cards(actor,a):
		if id not in known:continue
		var shown={"type":a.type,"presentation_id":id}
		for key in ["src","target","id","payer","other","attachment"]:
			if a.has(key) and a[key] in known:shown[key]=relative(a[key],p)
		if a.type=="ability" and a.get("src","")=="G149" and id==a.get("other",""):shown.presentation_role="公开身份模板"
		if id=="G139" and not plan.get("minor",{}).is_empty():shown.minor_roll=plan.minor.roll
		reveals.append({"player":(before.owner(id) if before.nodes.has(id) else actor)^p,"action":shown})
	out.reveals=reveals
	return out

static func preview_key(a: Dictionary) -> String:
	return JSON.stringify([a.get("src",""),a.get("target",""),a.get("mode",""),a.get("use_plan",false),a.get("solo",false),a.get("delegate","")])
