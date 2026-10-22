class_name GameState
extends RefCounted
const WaveRules = preload("res://scripts/wave_rules.gd")
const SynergyRules = preload("res://scripts/synergy_rules.gd")
const RenewalRules = preload("res://scripts/renewal_rules.gd")
var resources
const ContemporaryRules=preload("res://scripts/contemporary_rules.gd")
var contemporary
var scrap: Array=[]
var covenant
var renewal
var synergy
var wave
## Deterministic rules engine. Only act() mutates a normal match.
## Card identities in decks and opposing hands never enter AI observations.

var rng = RandomNumberGenerator.new()
var nodes: Dictionary = {}
var hands: Array = [{"group": [], "plot": [], "resource": []}, {"group": [], "plot": [], "resource": []}]
var decks: Dictionary = {"group": [], "plot": [], "resource": []}
var discards: Dictionary = {"group": [], "plot": [], "resource": []}
var graves: Array = [[], []]
var factions: Array = ["", ""]
var turns: Array = [0, 0]
var destroyed: Array = [0, 0]
var attacked: Array = [false, false]
var phase = "setup_faction"
var current = 0
var serial = 0
var auto_used = false
var deploy_used = false
var battle: Dictionary = {}
var last_battle: Dictionary = {}
var pending_plot: Dictionary = {}
var choice: Dictionary = {}
var resume_phase = "main"
var used: Dictionary = {}
var recharged: Dictionary = {}
var captured: Dictionary = {}
var rewards: Dictionary = {}
var failed_recruits: Array = []
var locked: Array = []
var exposed: Array = []
var world = ""
var logs: Array = []
var last_event: Dictionary = {}
var winner = -2
var end_requested = false
var claim: Dictionary={}
var draw_queue: Array = []
var initiative: Array = []
var initial_ai = ""
var mulligans: Array=[0,0]
var motion_events: Array=[]
var resource_candidates: Array=[[],[]]
var resource_rerolls: Array=[0,0]

func _flow(id: String,from: String,to: String,p: int) -> void:
	motion_events.append({"id":id,"from":from,"to":to,"player":p,"kind":card(id).kind})

func _mulligan(p: int) -> void:
	var returned=hands[p].group.duplicate();hands[p].group.clear()
	for id in returned:decks.group.append(id);_flow(id,"hand","deck",p)
	_shuffle(decks.group)
	for i in returned.size():_draw(p,"group")
	mulligans[p]+=1
	if p==1:
		var candidates=hands[1].group.duplicate();candidates.sort_custom(func(a,b):return _initial_score(a,1)>_initial_score(b,1));initial_ai=candidates[0]
	_log(_who(p)+"重随初始团体 · 剩余%d次"%(2-mulligans[p]),"mulligan",{"player":p})

func _init(seed_value: int = 0) -> void:
	resources=ResourceRules.new(self)
	contemporary=ContemporaryRules.new(self)
	wave=WaveRules.new(self)
	synergy=SynergyRules.new(self)
	renewal=RenewalRules.new(self)
	covenant=CovenantRules.new(self)
	CardDB.load_all()
	if seed_value == 0: rng.randomize()
	else: rng.seed = seed_value
	factions[1] = CardDB.ids("faction")[rng.randi_range(0,CardDB.ids("faction").size()-1)]
	for kind in decks:
		decks[kind] = CardDB.ids(kind)
		_shuffle(decks[kind])
	for kind in ["plot", "group"]:
		for _i in range(2 if kind == "plot" else 5):
			for p in [0, 1]: _draw(p, kind)
	var candidates = hands[1].group.duplicate()
	candidates.sort_custom(func(a, b): return _initial_score(a, 1) > _initial_score(b, 1))
	initial_ai = candidates[0]

func _initial_score(id: String, p: int) -> float:
	var c = CardDB.get_card(id)
	return c.p * 1.3 + c.slots * 2 + _affinity(id, p)

func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var v = a[i]; a[i] = a[j]; a[j] = v

func _log(message: String, event: String = "action", extra: Dictionary = {}) -> void:
	logs.append(message)
	last_event = extra.duplicate(true)
	last_event["text"] = message
	last_event["event"] = event
	if logs.size() > 150: logs.pop_front()

func root(p: int) -> String: return "R%d" % p
func card(id: String) -> Dictionary: return CardDB.get_card(nodes[id].card if nodes.has(id) else id)
func owner(id: String) -> int: return nodes[id].owner if nodes.has(id) else -1
func title(id: String) -> String: return card(id).get("name", id)
func is_root(id: String) -> bool: return id.begins_with("R")
func field(p: int) -> Array: return nodes.keys().filter(func(id): return nodes[id].owner == p and card(id).kind!="resource")
func groups(p: int) -> Array: return field(p).filter(func(id): return not is_root(id))
func children(id: String) -> Array: return nodes.keys().filter(func(k): return nodes[k].parent == id)
func action_limit(id: String) -> int:return 2 if is_root(id) and factions[owner(id)]=="I09" else 1
func self_power(id: String) -> int:return stat(id,"p")*2+contemporary.self_bonus(id)
func spend(id: String) -> void:nodes[id].token=maxi(0,int(nodes[id].token)-1)
func token(id: String) -> bool: return nodes.has(id) and nodes[id].token > 0 and not wave.devastated(id)
func tags(id: String) -> Array:
	var result=card(id).get("tags",[]).duplicate()
	if nodes.has(id):
		for tag in nodes[id].get("extra_tags",[]):
			if tag not in result:result.append(tag)
	return wave.extra_tags(id,result)

func has(id: String, trait_name: String) -> bool: return trait_name in alignments(id) or trait_name in tags(id)

func alignments(id: String) -> Array:
	var a = card(id).get("align", []).duplicate()
	if nodes.has(id):
		if nodes[id].get("vampire", false):
			a.erase("正统")
			if "怪异" not in a: a.append("怪异")
		if nodes[id].get("pacified",false):a=CovenantRules.peaceful(a)
		if nodes[id].get("flip", false):
			var liberal = "自由" in a; var conservative = "保守" in a
			a.erase("自由"); a.erase("保守")
			if liberal: a.append("保守")
			if conservative: a.append("自由")
	if nodes.has(id) and nodes[id].has("mask"):a=nodes[id].mask.duplicate()
	if nodes.has(id) and nodes[id].get("rally",false) and "狂热" not in a:a.append("狂热")
	return a

func stat(id: String, key: String,raw: bool=false) -> int:
	var c = card(id)
	var value = int(c.get(key, 0))
	if nodes.has(id):
		var attached = nodes[id].attached
		var parent=nodes[id].parent
		if key == "p" and "P27" in attached: value += 1
		if key == "r" and "P26" in attached: value += 2
		if key == "slots" and "P19" in attached: value = mini(3, value + 1)
		if world == "P28" and "正统" in alignments(id) and key in ["p", "r"]: value += 1
		if key=="r" and parent=="G073" and (has(id,"企业") or has(id,"科学")):value+=2
		if key == "gp":
			if id=="G092" and wave.enabled(id):value+=resources.field(owner(id)).size()
			if id=="G008" and wave.enabled(id):value+=children(id).filter(func(k):return has(k,"国家")).size()
			if factions[owner(id)] == "I03" and has(id, "计算机"): value += 1
			if parent=="G077" and (has(id,"企业") or has(id,"银行")):value+=1
			value+=nodes[id].get("ad_gp",0)
			if nodes[id].get("compute",false):value=stat(id,"p",true)
			value = mini(value, stat(id, "p",true))
	value=contemporary.adjust_stat(id,key,renewal.adjust_stat(id,key,synergy.adjust_stat(id,key,value)))
	if not raw and key in ["p","gp"] and wave.devastated(id):value=value/2
	return value

func subtree(id: String) -> Array:
	var result = [id]
	for c in children(id): result.append_array(subtree(c))
	return result

func depth(id: String) -> int:
	var d = 0; var k = id
	while nodes.has(k) and nodes[k].parent != "":
		d += 1; k = nodes[k].parent
	return d

func can_parent(parent: String, moving: String = "") -> bool:
	return nodes.has(parent) and children(parent).size() < stat(parent, "slots") and (moving == "" or parent not in subtree(moving)) and (moving == "" or nodes[moving].parent != parent)

func _enter(id: String, p: int, parent: String, action: int = 0) -> void:
	hands[p].group.erase(id)
	nodes[id] = {"card": id, "owner": p, "parent": parent, "token": action, "attached": [], "vampire": false, "flip": false}

func _draw(p: int, kind: String,destination: String="hand") -> String:
	if kind=="resource" and not resources.can_draw(p):return ""
	if decks[kind].is_empty() and not discards[kind].is_empty():
		decks[kind] = discards[kind].duplicate(); discards[kind].clear(); _shuffle(decks[kind])
	if decks[kind].is_empty(): return ""
	var id = decks[kind].pop_front(); hands[p][card(id).kind].append(id)
	_flow(id,"deck",destination,p)
	return id

func _take(p: int, kind: String, n: int) -> Array:
	var result: Array = []
	for _i in n:
		var id = _draw(p, kind,"choice")
		if id != "": hands[p][card(id).kind].erase(id); result.append(id)
	return result

func _discard(p: int, id: String,reason: String="effect") -> void:
	var kind = card(id).kind
	var held=id in hands[p][kind]
	hands[p][kind].erase(id); discards[kind].push_front(id)
	locked.erase(id); exposed.erase(id)
	if held:synergy.hand_discarded(p,id,reason)
	if held:_flow(id,"hand","discard",p)

func _return_subtree(id: String) -> void:
	var p = owner(id)
	for k in subtree(id):
		for attachment in nodes[k].attached: discards.plot.push_front(attachment)
		hands[p].group.append(k); nodes.erase(k)

func _common(a: String, b: String) -> int:
	var n = 0
	for x in alignments(a):
		if x != "狂热" and x in alignments(b): n += 1
	return n

func _opposed(a: String, b: String) -> int:
	var opposite = {"政府":"企业", "企业":"政府", "自由":"保守", "保守":"自由", "和平":"暴力", "暴力":"和平", "正统":"怪异", "怪异":"正统", "狂热":"狂热"}
	var n = 0
	for x in alignments(a):
		if opposite.get(x, "NONE") in alignments(b): n += 1
	return n

func _affinity(id: String, p: int) -> float:
	match factions[p]:
		"I02": return 3.0 if has(id,"企业") or has(id,"银行") else 0.0
		"I03": return 5.0 if has(id,"计算机") else 0.0
		"I04": return 3.0 if has(id,"怪异") else 0.0
		"I06": return 4.0 if has(id,"地点") else 0.0
		"I07": return 4.0 if has(id,"和平") or has(id,"暴力") else 0.0
		"I08": return 6.0 if has(id,"魔法") else 0.0
		"I09": return 5.0 if has(id,"科学") or has(id,"太空") else 0.0
		"I10": return 5.0 if has(id,"暴力") else 0.0
		"I11": return 5.0 if has(id,"绿色") else 0.0
		"I12": return 5.0 if has(id,"共产") else 0.0
		"I05": return float(card(id).p) * 0.35
	return float(card(id).p) * 0.25

func protected(p: int) -> bool: return turns[p] == 0 and not attacked[p]
func can_enemy(p: int) -> bool: return not protected(1 - p)
func can_recharge(id: String) -> bool: return nodes.has(id) and not token(id) and not recharged.has(id) and not captured.has(id) and not wave.devastated(id)
func auto_is_free(id: String,parent: String) -> bool:
	return parent=="G017" and nodes.has(parent) and card(id).p<=2
func removable(id: String) -> bool:
	return nodes.has(id) and not is_root(id) and token(id) and id != "G009" and nodes[id].parent != "G009"

func hand_limit(p: int) -> int:
	var n = 5
	if owner("G026") == p: n += 1
	if owner("G051") == p: n += mini(2, children("G051").filter(func(id): return has(id,"犯罪")).size())
	if resources.ready("E05",p):n+=1
	if contemporary.ready("G156",p) and not children("G156").is_empty():n+=1
	return n

func resource_hand_limit(p: int) -> int:
	return 2+int(resources.ready("E05",p))+contemporary.limit_bonus(p)

func goal(p: int) -> Dictionary:
	return covenant.faction_goal(p)

func observation(p: int,include_previews: bool=true) -> Dictionary:
	var public_nodes = nodes.duplicate(true)
	var effective: Dictionary={}
	for id in nodes:effective[id]={"p":stat(id,"p"),"gp":stat(id,"gp"),"r":stat(id,"r"),"slots":stat(id,"slots"),"tags":tags(id),"align":alignments(id)}
	for id in nodes:
		if not is_root(id) and card(id).kind=="group":
			var context=card_context(id);effective[id].defense_control=context.control_total;effective[id].defense_destroy=context.destroy_total
	var actions=legal_actions(p);var previews: Dictionary={}
	for a in (actions if include_previews else []):
		if a.type=="plot" and a.id in GameState.WaveRules.DISASTERS:
			previews[JSON.stringify(a)]=wave.disaster_preview(a);continue
		if a.type!="attack":continue
		var v=attack_preview(a.src,a.target,a.mode,a);var support=0;var opposition=0
		var context={"src":a.src,"target":a.target,"mode":a.mode,"attacker":p,"defender":owner(a.target),"solo":a.get("solo",false)}
		for id in field(p):
			if id!=a.src and token(id):support+=support_power(id,context)
		if owner(a.target)>=0:
			for helper in field(owner(a.target)):
				if helper!=a.target and token(helper):opposition+=support_power(helper,context)
		v["enemy_support_max"]=opposition;v["self_max"]=self_power(a.target) if nodes.has(a.target) and token(a.target) and not v.get("no_self",false) else 0
		v["support_max"]=support;previews[JSON.stringify(a)]=v
	var revealed = {"group":[], "plot":[]}
	for kind in revealed:
		for id in hands[1-p][kind]:
			if id in exposed: revealed[kind].append(id)
	var public_state={}
	for key in ["serial","destroyed","attacked","auto_used","deploy_used","used","recharged","captured","rewards","failed_recruits","exposed","end_requested"]:
		var value=get(key);public_state[key]=value.duplicate(true) if value is Array or value is Dictionary else value
	public_state.locked=locked.filter(func(id):return id in hands[p].plot or id in exposed)
	public_state.wave={"plans":wave.plans.duplicate(true),"announced":wave.announced.duplicate(true)}
	return {"public_state":public_state,"player":p,"nodes":public_nodes,"effective":effective,"hands":hands[p].duplicate(true),"opponent_counts":{"group":hands[1-p].group.size(),"plot":hands[1-p].plot.size(),"resource":hands[1-p].resource.size()},"revealed":revealed,"resource_hand_limit":resource_hand_limit(p),"decks":{"group":decks.group.size(),"plot":decks.plot.size(),"resource":decks.resource.size()},"discards":discards.duplicate(true),"scrap":scrap.duplicate(),"graves":graves.duplicate(true),"factions":factions.duplicate(),"goals":[goal(0),goal(1)],"secret_goals":covenant.private_goals(p),"pending_plot":pending_plot.duplicate(true),"auto_used":auto_used,"deploy_used":deploy_used,"turns":turns.duplicate(),"current":current,"phase":phase,"world":world,"battle":battle.duplicate(true),"battle_values":battle_values(),"choice":choice.duplicate(true) if choice.get("player",-1)==p else {},"actions":actions,"previews":previews}

func _a(kind: String, label: String, args: Dictionary = {}) -> Dictionary:
	var a = args.duplicate(); a["type"] = kind; a["label"] = label
	return a

func legal_actions(p: int) -> Array:
	return contemporary.augment_actions(p,resources.augment_actions(p,covenant.augment_actions(p,renewal.augment_actions(p,synergy.augment_actions(p,wave.augment_actions(p,_base_legal_actions(p)))))))

func _base_legal_actions(p: int) -> Array:
	var out: Array = []
	if phase == "over": return out
	if phase == "setup_faction":
		if p == 0:
			for id in CardDB.ids("faction"): out.append(_a("faction",CardDB.name_of(id),{"id":id}))
		return out
	if phase == "setup_group":
		if p == 0:
			for id in hands[0].group: out.append(_a("initial","选择「%s」"%title(id),{"id":id}))
		if mulligans[p]<2:out.append(_a("mulligan","重随 · 剩余%d次"%(2-mulligans[p])))
		return out
	if phase == "choice" or phase == "discard":
		if choice.get("player",-1) == p:
			for id in choice.get("options",[]): out.append(_a("choose",title(id),{"id":id}))
			if choice.get("optional",false): out.append(_a("choose","跳过",{"id":""}))
		return out
	if phase == "plot_response":
		if p == 1-pending_plot.player:
			if "P15" in hands[p].plot and "P15" not in locked: out.append(_a("counter","骗局 · 取消「%s」"%title(pending_plot.id),{"id":"P15"}))
			out.append(_a("accept_plot","放行"))
		return out
	if phase == "draw":
		if p == current:
			for g in [true,false]:
				for plot in [true,false]:
					for gf in ([true,false] if g and owner("G066")==p else [false]):
						for pf in ([true,false] if plot and owner("G012")==p else [false]):
							var label=("团体抽二留一" if gf else ("抽团体" if g else "不抽团体"))+" · "+("阴谋抽二留一" if pf else ("抽阴谋" if plot else "不抽阴谋"))
							out.append(_a("draw",label,{"group":g,"plot":plot,"filter_group":gf,"filter_plot":pf}))
		return out
	if phase == "battle": return _battle_actions(p)
	if phase != "main" or p != current: return out
	var fs = field(p); var gs = groups(p)
	for id in hands[p].group:
		for parent in fs:
			if can_parent(parent):
					if not auto_used and (token(root(p)) or auto_is_free(id,parent)): out.append(_a("auto",("连锁加盟 · 免主牌标记 → " if auto_is_free(id,parent) else "自动接管 → ")+title(parent),{"id":id,"parent":parent,"src":id}))
	for src in fs:
		if token(src):
			for target in hands[p].group:
				if can_parent(src): out.append(_a("attack","招募「%s」"%title(target),{"src":src,"target":target,"mode":"control"}))
			if can_enemy(p):
				for target in groups(1-p):
					if can_parent(src): out.append(_a("attack","控制「%s」"%title(target),{"src":src,"target":target,"mode":"control"}))
					out.append(_a("attack","摧毁「%s」"%title(target),{"src":src,"target":target,"mode":"destroy"}))
	for id in gs:
		for parent in fs:
			if can_parent(parent,id):
				for payer in [id,nodes[id].parent,parent,root(p)]:
					if token(payer):
						var a = _a("move","移动 → %s · 由%s行动"%[title(parent),title(payer)],{"src":id,"parent":parent,"payer":payer})
						if a not in out: out.append(a)
		out.append_array(_ability_actions(id,p))
	for id in hands[p].plot:
		if id not in locked: out.append_array(_main_plot_actions(id,p))
	out.append(_a("end","结束回合"))
	return out

func _ability_actions(src: String,p: int) -> Array:
	if not wave.available(src):return []
	if src in ["G091","G093","G092","G098"]:return resources.country_actions(src,p)
	if src=="G138" or int(src.substr(1))>=151:return contemporary.ability_actions(src,p)
	if int(src.substr(1))>=131:return renewal.ability_actions(src,p)
	if int(src.substr(1))>=113:return synergy.ability_actions(src,p)
	if int(src.substr(1))>=81:return wave.ability_actions(src,p)
	var out: Array = []
	if used.has(src): return out
	var cost = src not in ["G015","G016","G018","G022","G046"]
	if cost and not token(src): return out
	var targets: Array = []
	match src:
		"G002":
			if can_enemy(p) and hands[1-p].group.any(func(id):return id not in exposed): targets=[""]
		"G003", "G059":
			if can_enemy(p): targets=groups(1-p).filter(func(id):return removable(id) and (card(id).p<=3 if src=="G003" else has(id,"企业")))
		"G004", "G080":
			if not decks["plot" if src=="G004" else "group"].is_empty(): targets=[""]
		"G010":
			if not decks.plot.is_empty() or not discards.plot.is_empty(): targets=[""]
		"G011":
			if not decks.group.is_empty() or not discards.group.is_empty(): targets=[""]
		"G013":
			if not discards.plot.is_empty(): targets=[""]
		"G015": targets=renewal.plot_costs(p).duplicate()
		"G016":targets=children(src).filter(func(id):return can_recharge(id) and not nodes[id].get("debt",false))
		"G018":
			for moving in children(src):
				for parent in field(p):
					if can_parent(parent,moving):out.append(_a("ability","物流 · %s → %s"%[title(moving),title(parent)],{"src":src,"target":moving,"parent":parent}))
		"G020": targets=children(src).filter(func(id):return (has(id,"科学") or has(id,"计算机")) and can_recharge(id))
		"G022":
			for parent in field(p):
				if can_parent(parent,src):out.append(_a("ability","线路跳转 → %s"%title(parent),{"src":src,"target":src,"parent":parent}))
		"G028":
			if not decks.group.is_empty():targets=[""]
		"G036":targets=groups(p).filter(func(id):return has(id,"怪异") and not has(id,"媒体"))
		"G037":targets=groups(p).filter(func(id):return id!=src and has(id,"媒体") and stat(id,"gp")<stat(id,"p") and nodes[id].get("ad_gp",0)==0)
		"G038":
			if can_enemy(p) and hands[1-p].plot.any(func(id):return id not in exposed):targets=[""]
		"G046":targets=hands[p].group.duplicate()
		"G056":targets=discards.group.slice(0,3).filter(func(id):return card(id).p<=3)
		"G065":targets=(groups(p)+ (groups(1-p) if can_enemy(p) else [])).filter(func(id):return has(id,"自由") or has(id,"保守"))
		"G072":
			if not decks.group.is_empty():targets=[""]
		"G074":targets=discards.plot.slice(0,3).filter(func(id):return synergy.battle_plot(id))
		"G078":targets=groups(p).filter(func(id):return id!=src and has(id,"计算机") and stat(id,"gp")<stat(id,"p") and not nodes[id].get("compute",false))
	for target in targets:
		var effect_name = card(src).effect.split("：")[0]
		out.append(_a("ability",effect_name+(" → "+title(target) if target!="" else ""),{"src":src,"target":target}))
	return out

func _main_plot_actions(id: String,p: int) -> Array:
	if id in ResourceRules.PLOTS:return resources.plot_actions(id,p)
	if covenant.is_goal(id):return covenant.main_plots(id,p)
	if int(id.substr(1))>=61:return contemporary.plot_actions(id,p)
	if int(id.substr(1))>=43:return synergy.main_plots(id,p)
	if int(id.substr(1))>=31:return wave.main_plots(id,p)
	var out: Array = []; var targets: Array = []; var gs = groups(p)
	match id:
		"P14":targets=hands[p].group.duplicate()
		"P17":targets=gs.filter(func(k):return can_recharge(k))
		"P18":
			for target in gs:
				for parent in field(p):
					if can_parent(parent,target):out.append(_a("plot","重组 · %s → %s"%[title(target),title(parent)],{"id":id,"src":id,"target":target,"parent":parent}))
		"P19":targets=gs.filter(func(k):return card(k).slots<3 and stat(k,"slots")<3)
		"P21", "P23":
			if can_enemy(p) and not hands[1-p].plot.is_empty():targets=gs.filter(func(k):return token(k))
		"P22":
			if can_enemy(p) and hands[1-p].plot.any(func(k):return k not in exposed):targets=[""]
		"P24","P25":targets=gs.filter(func(k):return token(k))
		"P26":targets=gs
		"P27":targets=gs.filter(func(k):return card(k).p<=3)
		"P28","P29":targets=[""]
		"P30":
			if can_enemy(p):
				for target in groups(1-p).filter(func(k):return removable(k)):
					for payer in gs.filter(func(k):return token(k)):out.append(_a("plot","破坏 · %s · 由%s行动"%[title(target),title(payer)],{"id":id,"src":id,"target":target,"payer":payer}))
	for target in targets:
		var label=title(id)+(" → "+title(target) if target!="" else "")
		if id in ["P21","P23","P24","P25"]:label=title(id)+" · 由%s行动"%title(target)
		if id=="P14":label=title(id)+" · 弃「%s」"%title(target)
		out.append(_a("plot",label,{"id":id,"src":id,"target":target}))
	return out

func _battle_actions(p: int) -> Array:
	var out: Array = []
	if battle.get("responder",-1)!=p:return out
	for id in field(p):
		if token(id) and id not in battle.paid:
			if id==battle.target:
				out.append(_a("self_defend","自卫 · %s (+%d)"%[title(id),stat(id,"p")*2],{"src":id,"power":stat(id,"p")*2}))
			elif support_power(id,battle)>0:
				var detail=support_detail(id,battle)
				out.append(_a("support","支援 · %s (%s +%d)"%[title(id),detail.basis,detail.power],{"src":id,"power":detail.power,"basis":detail.basis}))
	if p==battle.defender and battle.mode=="destroy" and owner("G063")==p and nodes[battle.target].parent=="G063" and token("G063") and not used.has("G063"):
		out.append(_a("rescue","人道撤离 · 红十字会",{"src":"G063"}))
	for id in hands[p].plot:
		if id in locked:continue
		out.append_array(_combat_plot_actions(id,p,battle))
	out.append(_a("pass","不再追加"))
	return out

func _combat_plot_actions(id: String,p: int,b: Dictionary) -> Array:
	if int(id.substr(1))>=61:return contemporary.combat_plots(id,p,b)
	if int(id.substr(1))>=43:return synergy.combat_plots(id,p,b)
	if int(id.substr(1))>=31:return wave.combat_plots(id,p,b)
	if b.has("disaster") and id in ["P10","P12","P13","P16"]:return []
	var out: Array=[]
	var index=int(id.substr(1))
	if index>=1 and index<=9:
		var traits=["政府","暴力","自由","犯罪","企业","怪异","保守","和平","狂热"]
		for target in b.paid:
			if owner(target)==p and has(target,traits[index-1]):out.append(_a("plot",title(id)+" → "+title(target),{"id":id,"src":id,"target":target}))
	elif id in ["P10","P11","P20"] and p==b.defender:
		if id!="P20" or has(b.target,"计算机"):out.append(_a("plot",title(id),{"id":id,"src":id,"target":b.target}))
	elif (id=="P12" and p==b.attacker and b.mode=="control") or (id=="P13" and p==b.attacker and b.mode=="destroy") or (id=="P16" and p!=b.attacker):out.append(_a("plot",title(id),{"id":id,"src":id,"target":""}))
	return out

func support_detail(id: String,b: Dictionary) -> Dictionary:
	var unavailable={"id":id,"power":0,"basis":"—","reason":"不能支援"}
	if not nodes.has(id) or card(id).kind=="resource" or id==b.src or id==b.target:return unavailable
	var p = owner(id); var full = false
	var reason="无完整力量资格，使用全球力量"
	if p==b.attacker:
		full = _common(id,b.target)>0 if b.mode=="control" else _opposed(id,b.target)>0
		if full:reason="与目标有共同阵营" if b.mode=="control" else "与目标有相反阵营"
		if b.src=="G005" and b.mode=="destroy" and nodes[id].parent==b.src and has(id,"军队"):full=true;reason="五角大楼 · 直属军队"
		if b.src=="G025" and b.mode=="control" and nodes[id].parent==b.src:full=true;reason="电信公司 · 直属下属"
		if id=="G047" and nodes[id].parent==nodes[b.src].parent:full=true;reason="兄弟会 · 同级互助"
	else:
		if b.defender!=p:return unavailable
		if b.src=="G054" and b.mode=="destroy" and nodes[b.target].parent==id:return {"id":id,"power":0,"basis":"—","reason":"忍者禁止目标的直属上级支援"}
		full=_common(id,b.target)>0 or nodes[b.target].parent==id or nodes[id].parent==b.target
		if full:reason="与目标有共同阵营" if _common(id,b.target)>0 else "与目标互为直属上下级"
	var value=stat(id,"p") if full else stat(id,"gp")
	var base=value
	if id=="G007" and p==b.attacker and b.mode=="destroy":value+=2
	if id=="G068" and p==b.defender and has(b.target,"科学"):value+=2
	if id=="G075" and p==b.defender and has(b.target,"自由"):value+=4;reason+=" · 法国防守自由目标 +4"
	if id=="G050":value+=mini(2,children(id).filter(func(k):return has(k,"怪异")).size())
	return resources.support_detail(id,wave.support_detail(id,b,{"id":id,"power":value,"basis":"P" if full else "GP","reason":reason,"base":base,"extra":value-base}))

func support_power(id: String,b: Dictionary) -> int:return support_detail(id,b).power

func attack_options(src: String,target: String,mode: String,action: Dictionary={}) -> Dictionary:
	# Pure preview. Uses the same eligibility functions as the live response window.
	var p=owner(src)
	var context={"src":src,"target":target,"mode":mode,"attacker":p,"defender":owner(target),"paid":[src],"solo":action.get("solo",false)}
	var supports: Array=[];var plots: Array=[];var total=0
	for id in field(p):
		if id==src or id==action.get("delegate","") or not token(id):continue
		var detail=support_detail(id,context)
		if detail.power>0:supports.append(detail);total+=detail.power
	var potential=context.duplicate(true)
	for entry in supports:potential.paid.append(entry.id)
	var mobilized=0
	if "P48" in hands[p].plot and "P48" not in locked:
		var mobilization=context.duplicate(true);mobilization.mobilized=true
		for id in field(p):
			if id in [src,action.get("delegate","")] or not token(id):continue
			if support_detail(id,mobilization).power>support_detail(id,context).power:mobilized+=1
	for id in hands[p].plot:
		var now=_combat_plot_actions(id,p,context);var later=_combat_plot_actions(id,p,potential)
		var status="不可用";var reason="不适用于本次攻击";var targets: Array=[]
		if id in locked:reason="本回合回收的牌，不能打出"
		elif not now.is_empty():status="可用";targets=now.map(func(a):return a.target);reason="本次战斗可用"
		elif not later.is_empty():status="先支援";targets=later.map(func(a):return a.target);reason="须先让符合阵营的团体花标记支援"
		elif id=="P15":status="反应";reason="对手打出阴谋时可反制"
		elif card(id).category=="己方主要阶段":reason="仅主要阶段可用，不能在战斗中打出"
		var amount=4 if int(id.substr(1)) in range(1,10) else (6 if id in ["P12","P13"] else 0)
		plots.append({"id":id,"status":status,"reason":reason,"targets":targets,"bonus":amount})
	return {"supports":supports,"plots":plots,"support_total":total,"mobilized_supports":mobilized}

func position_defense(id: String) -> int:
	if not nodes.has(id) or is_root(id):return 0
	var value=10 if depth(id)==1 else (5 if depth(id)==2 else 0)
	if renewal.ready("G142") and (id=="G142" or (nodes[id].parent=="G142" and has(id,"太空"))):value=maxi(5,value)
	return value

func loyalty_defense(id: String) -> int:
	if not nodes.has(id) or is_root(id):return 0
	var value=4*_common(id,nodes[id].parent)
	if nodes[id].parent=="G140" and renewal.ready("G140") and has(id,"狂热"):value+=4
	if nodes[id].parent=="G041" and has(id,"怪异"):value=maxi(value,8)
	return value

func passive_defense(id: String,mode: String,src: String="") -> int:
	if not nodes.has(id) or is_root(id):return 0
	var value=0
	if mode=="control":
		if resources.ready("E21",owner(id)) and has(id,"魔法"):value+=2
		if factions[owner(id)]=="I04" and has(id,"怪异"):value+=2
		if "G006" in children(id):value+=2
		if id=="G042" and src!="" and (has(src,"科学") or has(src,"太空")):value+=4
		if id=="G039" and src!="" and has(src,"政府"):value+=4
	else:
		if id=="G058":value+=2
		if contemporary.ready("G049",owner(id)) and has(id,"绿色"):value+=3
		if id=="G071":value+=10
		if id=="G061" and src!="" and has(src,"暴力"):value+=4
	return value

func disaster_defense(id: String,src: String="") -> int:
	return (4 if id=="G152" and contemporary.ready(id) and resources.field(owner(id)).any(func(k):return has(k,"装置")) else 0)+passive_defense(id,"destroy",src)+(5 if wave.enabled("G030",owner(id)) else 0)+(3 if resources.ready("E03",owner(id)) else 0)

func card_context(id: String) -> Dictionary:
	if not nodes.has(id):return {"on_board":false,"loyalty":0,"position":0}
	if card(id).kind=="resource":return resources.context(id)
	var c=card(id);var position=position_defense(id);var loyalty=loyalty_defense(id)
	var control=passive_defense(id,"control");var destroy=passive_defense(id,"destroy")
	var destroy_base=stat(id,"r" if id=="G076" else "p")
	return {"on_board":true,"owner":owner(id),"root":is_root(id),"parent":nodes[id].parent,"depth":depth(id),"loyalty":loyalty,"position":position,"control_passive":control,"destroy_passive":destroy,"disaster_passive":disaster_defense(id),"disaster_base":stat(id,"p"),"control_total":stat(id,"r")+loyalty+position+control,"destroy_base":destroy_base,"destroy_total":destroy_base+position+destroy,"token":int(token(id)),"can_recharge":can_recharge(id),"recharged":recharged.has(id),"captured":captured.has(id),"used":used.has(id),"occupied":children(id).size(),"slots":stat(id,"slots"),"attached":nodes[id].attached.duplicate(),"printed":{"p":c.p,"gp":c.gp,"r":c.r,"slots":c.slots}}

func _battle_record(kind: String,p: int,id: String,target: String,message: String,status: String="") -> void:
	if battle.is_empty():return
	if not battle.has("entries"):battle.entries=[]
	battle.entries.append({"kind":kind,"player":p,"id":id,"target":target,"text":_who(p)+" · "+message,"status":status})

func _plot_record_status(id: String,status: String) -> void:
	if battle.is_empty():return
	if not battle.has("entries"):return
	for i in range(battle.entries.size()-1,-1,-1):
		if battle.entries[i].kind=="plot" and battle.entries[i].id==id:battle.entries[i].status=status;return

func attack_preview(src: String,target: String,mode: String,action: Dictionary={}) -> Dictionary:
	var b={"src":src,"target":target,"mode":mode,"attacker":owner(src),"defender":owner(target),"support_a":0,"support_d":0,"bonus_a":2 if action.get("training",false) else 0,"bonus_d":0,"self":0,"solo":action.get("solo",false)}
	if action.get("use_plan",false) and wave.plans.has(owner(src)):b.fixed_dice=wave.plans[owner(src)]
	return battle_values(b)

func battle_values(b: Dictionary = {}) -> Dictionary:
	if b.is_empty():b=battle
	if b.is_empty():return {}
	var src=b.src; var target=b.target; var mode=b.mode; var p=b.attacker
	var attack=stat(src,"p"); var alignment=4*(_common(src,target)-_opposed(src,target))*(1 if mode=="control" else -1)
	var base=stat(target,"r" if mode=="control" or target=="G076" else "p")
	var loyalty=0; var position=0; var ability=0; var defense=0
	if nodes.has(target):
		if mode=="control":loyalty=loyalty_defense(target)
		position=position_defense(target)
		if src=="G021" and mode=="control" and has(target,"计算机"):position=0
		defense=passive_defense(target,mode,src)
	if mode=="control":
		if factions[p]=="I01":ability+=1
		if factions[p]=="I02" and (has(src,"企业") or has(src,"银行")):ability+=2
		var traits={"G001":"犯罪","G029":"太空","G032":"媒体","G040":"保守","G045":"太空","G048":"魔法","G060":"犯罪","G062":"绿色","G064":"自由","G070":"保守"}
		if traits.has(src) and has(target,traits[src]):ability+=3 if src in ["G029","G048","G062"] else 2
	else:
		if factions[p]=="I05":ability+=2
		if world=="P29":ability-=2
		if src=="G053":ability+=2
		if src=="G019" and has(target,"绿色"):ability+=2
		if src=="G027" and has(target,"科学"):ability+=2
		if src=="G057" and has(target,"和平"):ability+=2
		if src=="G079" and has(target,"犯罪"):ability+=2
	var strength=attack+alignment+ability+b.get("support_a",0)+b.get("bonus_a",0)-base-loyalty-position-defense-b.get("support_d",0)-b.get("bonus_d",0)-b.get("self",0)
	var chance=0
	for x in range(1,7):
		for y in range(1,7):
			if x+y<=strength and x+y<=10:chance+=1
	return wave.values(b,{"power":attack,"alignment":alignment,"ability":ability,"base":base,"loyalty":loyalty,"position":position,"defense":defense,"support_a":b.get("support_a",0),"support_d":b.get("support_d",0)+b.get("self",0),"bonus_a":b.get("bonus_a",0),"bonus_d":b.get("bonus_d",0),"strength":strength,"chance":chance/36.0})

func act(p: int,a: Dictionary) -> bool:
	if a not in legal_actions(p):return false
	var applied=_apply_command(p,a)
	if applied:renewal.repair_slots()
	if applied:covenant.repair_hand()
	return applied

func _apply_command(p: int,a: Dictionary) -> bool:
	a=a.duplicate(true)
	motion_events.clear()
	last_event={}
	if contemporary.handle(p,a):return true
	if resources.handle(p,a):return true
	if covenant.handle(p,a):return true
	if renewal.handle(p,a):return true
	if synergy.handle(p,a):return true
	if wave.handle(p,a):return true
	match a.type:
		"mulligan":_mulligan(p)
		"faction":
			factions[0]=a.id
			for who in [0,1]:nodes[root(who)]={"card":factions[who],"owner":who,"parent":"","token":0,"attached":[]}
			phase="setup_group";_log("主牌揭晓 · %s 对 %s"%[title(root(0)),title(root(1))],"reveal")
		"initial":
			while mulligans[1]<2 and _initial_score(initial_ai,1)<11:_mulligan(1)
			_enter(a.id,0,root(0));_enter(initial_ai,1,root(1));_shuffle(decks.group)
			resources.opening()
			_log("初始手下同时亮出 · 选择初始资源","opening_resource")
		"draw":_begin_draw(a)
		"choose":_choose(a.id)
		"auto":
			var before=field(p);var free=auto_is_free(a.id,a.parent)
			if not free:spend(root(p))
			auto_used=true;failed_recruits.erase(a.id)
			_enter(a.id,p,a.parent);captured[a.id]=true;_entry_rewards(a.id,p,a.parent,before)
			_log("%s自动接管了%s%s · 本回合无行动标记"%[_who(p),title(a.id)," · 连锁加盟免主牌标记" if free else ""],"enter",{"id":a.id,"parent":a.parent})
			_after_effect()
		"move":spend(a.payer);nodes[a.src].parent=a.parent;_log("%s重组了势力结构"%_who(p),"move",{"id":a.src})
		"ability":_ability(p,a)
		"attack":_launch_attack(p,a)
		"self_defend", "rescue":
			spend(a.src);battle.paid.append(a.src)
			var message=""
			if a.type=="self_defend":battle.self=self_power(a.src);message="%s 自卫 · 防御 +%d"%[title(a.src),battle.self]
			elif a.type=="rescue":battle.rescue=true;used[a.src]=true;message="%s 登记人道撤离 → %s"%[title(a.src),title(battle.target)]
			_battle_record(a.type,p,a.src,battle.target,message)
			_log(_who(p)+" · "+message,"support",{"id":a.src,"player":p})
			_response_changed(p)
		"pass":
			battle.passes+=1;battle.responder=1-p
			if battle.passes>=2:_resolve_battle()
		"plot":_commit_plot(p,a)
		"counter":
			hands[p].plot.erase("P15");_spent_plot("P15")
			_plot_record_status(pending_plot.id,"已被反制")
			_battle_record("counter",p,"P15",pending_plot.id,"骗局 → 取消「%s」"%title(pending_plot.id),"已生效")
			_log(_who(p)+" · 骗局取消了「%s」"%title(pending_plot.id),"counter",{"id":"P15","player":p})
			_spent_plot(pending_plot.id);phase=resume_phase;pending_plot={}
			if phase=="battle":_response_changed(p)
			else:_after_effect()
		"accept_plot":_resolve_plot()
		"end":_request_end()
	return true

func _launch_attack(p: int,a: Dictionary) -> void:
	if a.has("delegate"):spend(a.delegate)
	else:spend(a.src)
	if nodes.has(a.target):attacked[p]=true
	else:
		if a.target not in failed_recruits:failed_recruits.append(a.target)
		# The revealed recruit is committed to this battle, so it cannot pay a hand cost.
		hands[p].group.erase(a.target)
	battle={"src":a.src,"target":a.target,"mode":a.mode,"attacker":p,"defender":owner(a.target),"responder":1-p,"passes":0,"paid":[a.src],"support_a":0,"support_d":0,"bonus_a":0,"bonus_d":0,"self":0,"rescue":false,"video":[],"spent":[],"entries":[],"before":field(p)}
	wave.before_attack(p,a)
	renewal.before_attack(a)
	battle.hand_target=not nodes.has(a.target)
	phase="battle";_log("%s → %s · %s"%[title(a.src),title(a.target),"控制" if a.mode=="control" else "摧毁"],"attack")
	_battle_record("attack",p,a.src,a.target,"%s → %s · %s"%[title(a.src),title(a.target),"控制" if a.mode=="control" else "摧毁"])
	wave.next_response_trigger()

func _finish_opening() -> void:
	while true:
		initiative=[[_die(),_die()],[_die(),_die()]]
		if initiative[0][0]+initiative[0][1]!=initiative[1][0]+initiative[1][1]:break
	current=0 if initiative[0][0]+initiative[0][1]>initiative[1][0]+initiative[1][1] else 1
	_draw(1-current,"plot")
	_log("初始手下同时亮出 · 你 %d，AI %d · %s先手 · %s后手额外抽1张阴谋"%[initiative[0][0]+initiative[0][1],initiative[1][0]+initiative[1][1],"你" if current==0 else "AI",_who(1-current)],"initiative")
	_start_turn()

func _die() -> int:return rng.randi_range(1,6)
func _who(p: int) -> String:return "你" if p==0 else "AI"

func _start_turn() -> void:
	wave.start_turn()
	serial+=1;auto_used=false;deploy_used=false;used.clear();recharged.clear();captured.clear();rewards.clear();failed_recruits.clear();locked.clear();exposed.clear();end_requested=false
	phase="draw"

func _begin_draw(a: Dictionary) -> void:
	draw_queue=[]
	for kind in ["group","plot"]:
		if a[kind]:draw_queue.append({"deck":kind,"filter":a.get("filter_"+kind,false)})
	phase="main";_advance_draw()

func _advance_draw() -> void:
	while not draw_queue.is_empty():
		var item=draw_queue.pop_front();var kind=item.deck;var source="G066" if kind=="group" else "G012"
		if item.filter and owner(source)==current:
			var options=_take(current,kind,2)
			if options.size()>1:
				_set_choice(current,"抽二留一 · 选择加入手牌",options,"draw_keep",{"deck":kind});return
			for id in options:hands[current][card(id).kind].append(id)
		else:_draw(current,kind)
	if owner("G031")==current and children("G031").filter(func(id):return has(id,"媒体")).size()>=2:_draw(current,"plot")
	for id in field(current):
		if wave.devastated(id):nodes[id].token=0;continue
		if nodes[id].get("debt",false):nodes[id].debt=false;_log("%s偿还借贷 · 本次不补行动标记"%title(id),"debt",{"id":id})
		else:nodes[id].token=action_limit(id)
	resources.refill(current)
	phase="main";_log("%s的主要阶段"%_who(current),"turn")

func _set_choice(p: int,label: String,options: Array,kind: String,data: Dictionary={},optional: bool=false) -> void:
	choice=data.duplicate(true);choice.merge({"player":p,"label":label,"options":options.duplicate(),"kind":kind,"optional":optional},true);phase="choice"

func _choose(id: String) -> void:
	var c=choice.duplicate(true);var p=c.player;choice={};phase="main"
	match c.kind:
		"draw_keep":
			var deck_kind=c.deck
			hands[p][card(id).kind].append(id)
			for k in c.options:
				if k!=id:decks[deck_kind].append(k)
			_advance_draw();return
		"discard_any":_discard(p,id)
		"discard_group":_discard(p,id)
		"agent":_discard(1-p,id);_log("安插特工弃掉了%s"%title(id),"discard")
		"nasa", "japan":
			if id!="":hands[p][card(id).kind].append(id)
			for k in c.peek:
				if k!=id:decks.group.append(k)
		"reorder":
			c.order.append(id);c.options.erase(id)
			if not c.options.is_empty():
				_set_choice(p,"下一张放在堆顶顺序中",c.options,"reorder",{"deck":c.deck,"order":c.order});return
			for k in range(c.order.size()-1,-1,-1):decks[c.deck].push_front(c.order[k])
		"emptyvee":
			if id!="":_discard(p,id);_draw(p,"plot")
		"limit":
			_discard(p,id)
			if hands[p].plot.size()>hand_limit(p):_limit_choice(p);return
	_after_effect()

func _ability(p: int,a: Dictionary) -> void:
	var src=a.src;var target=a.target;used[src]=true
	if src not in ["G015","G016","G018","G022","G046"]:nodes[src].token=0
	match src:
		"G002","G038":
			var kind="group" if src=="G002" else "plot"
			var hidden=hands[1-p][kind].filter(func(k):return k not in exposed)
			var id=hidden[rng.randi_range(0,hidden.size()-1)];exposed.append(id)
			_log("%s公开了%s"%[title(src),title(id)],"reveal",{"id":id})
		"G003","G059":nodes[target].token=0
		"G004","G080":
			var kind="plot" if src=="G004" else "group";var peek: Array=[]
			for _i in mini(3,decks[kind].size()):peek.append(decks[kind].pop_front())
			_set_choice(p,"选择最先抽到的牌",peek,"reorder",{"deck":kind,"order":[]})
		"G010":
			_draw(p,"plot");_set_choice(p,"投递 · 弃一张手牌",hands[p].group+hands[p].plot+hands[p].resource,"discard_any")
		"G011":
			_draw(p,"group");_draw(p,"group");_set_choice(p,"授信 · 弃一张团体",hands[p].group,"discard_group")
		"G013":
			var id=discards.plot.pop_front();hands[p].plot.append(id);locked.append(id);exposed.append(id)
		"G015":_discard(p,target);_draw(p,"group")
		"G016":nodes[target].token=1;nodes[target].debt=true;recharged[target]=true
		"G018","G022":nodes[target].parent=a.parent
		"G020":nodes[target].token=1;recharged[target]=true
		"G028":
			var peek: Array=[]
			for _i in mini(3,decks.group.size()):peek.append(decks.group.pop_front())
			var valid=peek.filter(func(k):return card(k).kind=="group" and (has(k,"科学") or has(k,"太空")))
			_set_choice(p,"轨道观测 · 可选择一张",valid,"nasa",{"peek":peek},true)
		"G036":
			if not nodes[target].has("extra_tags"):nodes[target].extra_tags=[]
			nodes[target].extra_tags.append("媒体")
		"G037":nodes[target].ad_gp=3
		"G046":_discard(p,target);_draw(p,"plot")
		"G056":discards.group.erase(target);hands[p].group.append(target)
		"G065":nodes[target].flip=not nodes[target].get("flip",false)
		"G072":
			var peek: Array=[]
			for _i in mini(4,decks.group.size()):peek.append(decks.group.pop_front())
			var valid=peek.filter(func(k):return card(k).kind=="group" and (has(k,"媒体") or has(k,"怪异")))
			_set_choice(p,"内容出海 · 可选择一张",valid,"japan",{"peek":peek},true)
		"G074":discards.plot.erase(target);hands[p].plot.append(target);locked.append(target);exposed.append(target)
		"G078":nodes[target].compute=true
	if src not in ["G002","G038"]:_log("%s · %s"%[title(src),card(src).effect.split("：")[0]],"ability",{"id":target})
	_after_effect()

func _commit_plot(p: int,a: Dictionary) -> void:
	var was_exposed=a.id in exposed
	hands[p].plot.erase(a.id)
	synergy.committed(p,a)
	wave.plot_committed(p,a)
	if a.id=="P14":_discard(p,a.target)
	if a.id in ["P21","P23","P24","P25"]:nodes[a.target].token=0
	if a.id in ["P30","P59","P60"]:nodes[a.payer].token=0
	resume_phase=phase;pending_plot=a.duplicate(true);pending_plot.player=p;pending_plot.was_exposed=was_exposed
	_log("%s打出%s"%[_who(p),title(a.id)],"plot",{"id":a.id})
	var message="打出「%s」"%title(a.id)
	if not battle.is_empty():
		if a.get("target","")!="":message+=" → "+title(a.target)
		var index=int(a.id.substr(1))
		var amount=4 if index in range(1,11) or a.id=="P20" else (2 if a.id=="P11" else (6 if a.id in ["P12","P13"] else 0))
		if amount>0:message+=" · %s +%d"%["攻击" if p==battle.attacker else "防御",amount]
		if a.id=="P16":message+=" · 令攻击失败"
		_battle_record("plot",p,a.id,a.get("target",""),message,"待结算")
	if renewal.can_counter(1-p) or ("P15" in hands[1-p].plot and "P15" not in locked) or (was_exposed and wave.available("G106",1-p) and token("G106") and not used.has("G106")):phase="plot_response"
	else:_resolve_plot()

func _spent_plot(id: String) -> void:
	if not battle.is_empty():battle.spent.append(id)
	else:discards.plot.push_front(id)

func _resolve_plot() -> void:
	var a=pending_plot.duplicate(true);pending_plot={};phase=resume_phase
	var p=a.player;var id=a.id;var target=a.get("target","");var stays=false
	_plot_record_status(id,"已生效")
	if contemporary.resolve_plot(a):return
	if resources.resolve_plot(a):return
	if covenant.resolve_plot(a):return
	if wave.resolve_plot(a):return
	var index=int(id.substr(1))
	if index>=1 and index<=9:battle["bonus_a" if p==battle.attacker else "bonus_d"]+=4
	else:
		match id:
			"P10","P20":battle.bonus_d+=4
			"P11":battle.bonus_d+=2
			"P12","P13":battle.bonus_a+=6
			"P14":_draw(p,"plot");_draw(p,"plot")
			"P16":battle["foiled"]=true
			"P17":nodes[target].token=1;recharged[target]=true
			"P18":nodes[target].parent=a.parent
			"P19","P26","P27":nodes[target].attached.append(id);stays=true
			"P21":_set_choice(p,"安插特工 · 查看并弃掉一张",hands[1-p].plot,"agent")
			"P22":
				for k in hands[1-p].plot:
					if k not in exposed:exposed.append(k)
			"P23":
				var k=hands[1-p].plot[rng.randi_range(0,hands[1-p].plot.size()-1)]
				hands[1-p].plot.erase(k);hands[p].plot.append(k)
			"P24":_draw(p,"plot");_draw(p,"plot")
			"P25":_draw(p,"group");_draw(p,"group")
			"P28","P29":
				if world!="":discards.plot.push_front(world)
				world=id;stays=true
			"P30":nodes[target].token=0
	if not stays:_spent_plot(id)
	wave.plot_rewards(p,id,a)
	if not battle.is_empty():
		if battle.get("foiled",false):_resolve_battle()
		else:_response_changed(p)
	else:_after_effect()

func _response_changed(p: int) -> void:
	battle.passes=0;battle.responder=1-p;phase="battle"
	wave.next_response_trigger()

func _resolve_battle() -> void:
	wave.resolve_battle()

func _reward_draw(src: String,p: int,kind: String) -> void:
	if current==p and owner(src)==p and not rewards.has(src):
		rewards[src]=true
		wave.defer({"kind":"draw","source":src,"player":p,"deck":kind,"amount":1,"message":"抽牌收益 · 抽1张"+("团体" if kind=="group" else "阴谋")})

func _entry_rewards(id: String,p: int,parent: String,before: Array) -> void:
	if p!=current:return
	resources.entry_reward(p)
	contemporary.entry_reward(id,p)
	synergy.entry_reward(id,p,before)
	if "G044" in before and owner("G044")==p and card(id).p>card("G044").p and (has(id,"科学") or has(id,"太空")):_reward_draw("G044",p,"group")
	if parent=="G069" and parent in before and has(id,"自由"):_reward_draw(parent,p,"group")
	if parent=="G033" and parent in before and has(id,"怪异") and not rewards.has(parent):
		rewards[parent]=true
		if not renewal.plot_costs(p).is_empty():_set_choice(p,"潮流更替 · 可弃一张阴谋重抽",renewal.plot_costs(p),"emptyvee",{},true)

func _after_effect() -> void:
	if renewal.repair_slots():return
	if resources.repair_hand():return
	if covenant.repair_hand():return
	if wave.drain():return
	if phase=="choice" or phase=="discard" or phase=="battle" or phase=="plot_response":return
	if covenant.settle_claim():return
	for p in [0,1]:
		if p!=current and hands[p].plot.size()>hand_limit(p):_limit_choice(p);return
	for p in [0,1]:
		if turns[p]>=3 and groups(p).is_empty():_finish(1-p,"%s的势力已被消灭"%_who(p));return
	if end_requested:_complete_end()

func _limit_choice(p: int) -> void:
	_set_choice(p,"阴谋手牌上限 %d · 选择弃牌"%hand_limit(p),hands[p].plot,"limit")
	phase="discard"

func _request_end() -> void:
	end_requested=true
	for id in failed_recruits.duplicate():
		if id in hands[current].group:_discard(current,id,"failed_recruit")
	failed_recruits.clear()
	if hands[current].plot.size()>hand_limit(current):_limit_choice(current)
	else:_complete_end()

func _complete_end() -> void:
	if used.has("renewal:cleanup"):
		for p in [0,1]:
			if hands[p].plot.size()>hand_limit(p):_limit_choice(p);return
		current=1-current;_start_turn();return
	wave.end_turn()
	turns[current]+=1
	if mini(turns[0],turns[1])>=1:
		var g0=goal(0).met;var g1=goal(1).met
		if g0 or g1:_finish(-1 if g0 and g1 else (0 if g0 else 1),"双方同时完成目标" if g0 and g1 else "光明会的计划已经完成");return
	for p in [0,1]:
		if turns[p]>=3 and groups(p).is_empty():_finish(1-p,"%s的势力已被消灭"%_who(p));return
	for id in nodes:
		nodes[id].erase("mask");nodes[id].erase("mask_card");nodes[id].erase("rally");nodes[id].erase("no_support")
		nodes[id]["silenced"]=false;nodes[id]["flip"]=false;nodes[id]["ad_gp"]=0;nodes[id]["compute"]=false
	used["renewal:cleanup"]=true
	_complete_end()

func _finish(p: int,reason: String) -> void:
	winner=p;phase="over";_log(reason,"victory")

func validate() -> Array:
	var errors: Array=[];var locations: Array=[]
	for kind in decks:
		locations.append_array(decks[kind]);locations.append_array(discards[kind])
		for p in [0,1]:locations.append_array(hands[p][kind])
	for p in [0,1]:locations.append_array(graves[p])
	locations.append_array(scrap)
	for pool in resource_candidates:locations.append_array(pool)
	for id in nodes:
		if choice.get("kind","")!="x_overflow" and children(id).size()>stat(id,"slots"):errors.append("Overfull "+id)
		if nodes[id].token<0 or nodes[id].token>action_limit(id):errors.append("Invalid token "+id)
		if is_root(id):
			if nodes[id].parent!="":errors.append("Root has parent "+id)
			continue
		locations.append(id);locations.append_array(nodes[id].attached)
		if card(id).kind=="resource":continue
		var parent=nodes[id].parent
		if not nodes.has(parent) or owner(parent)!=owner(id):errors.append("Invalid parent "+id)
		var visited: Array=[id];var k=parent
		while nodes.has(k) and k!="":
			if k in visited:errors.append("Cycle "+id);break
			visited.append(k);k=nodes[k].parent
	if world!="":locations.append(world)
	if not pending_plot.is_empty():locations.append(pending_plot.id)
	if not battle.is_empty():
		locations.append_array(battle.spent)
		if battle.get("hand_target",false):locations.append(battle.target)
	if choice.get("kind","")=="draw_keep":locations.append_array(choice.options)
	if choice.get("kind","")=="reorder":locations.append_array(choice.options);locations.append_array(choice.order)
	if choice.get("kind","") in ["nasa","japan"]:locations.append_array(choice.peek)
	locations.append_array(wave.held_cards())
	if choice.get("kind","") in ["e_probe","n_probe","n_relic"]:locations.append_array(choice.peek)
	if choice.get("kind","")=="x_overflow":
		var held=choice.saved_choice
		if held.get("kind","") in ["draw_keep","reorder"]:locations.append_array(held.options);locations.append_array(held.get("order",[]))
		if held.get("kind","") in ["nasa","japan","w_draft","e_probe","n_probe","n_relic"]:locations.append_array(held.peek)
	var seen: Dictionary={}
	for id in locations:
		if seen.has(id):errors.append("Duplicate "+id)
		seen[id]=true
	var expected=CardDB.ids("group").size()+CardDB.ids("plot").size()+CardDB.ids("resource").size()
	for p in [0,1]:
		if resources.field(p).size()>2:errors.append("Resource capacity")
	if seen.size()!=expected:errors.append("Card conservation %d/%d"%[seen.size(),expected])
	return errors
