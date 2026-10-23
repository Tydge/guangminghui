class_name AiAgent
extends RefCounted
## No GameState reference. This agent receives only a redacted observation.

const Tactics=preload("res://scripts/ai_tactics.gd")
const Planner=preload("res://scripts/ai_planner.gd")
var difficulty="normal"
var planning=true
var last_plan={}
var planning_active=false
var plan_revision=0
var cancel_mutex=Mutex.new()
var cancel_requested=false
var workers: Array=[]
var rng = RandomNumberGenerator.new()

func _init() -> void:rng.randomize()

func pick(o: Dictionary) -> Dictionary:
	var fallback=heuristic_pick(o)
	if difficulty=="easy" or not planning or not Planner.applicable(o):return fallback
	var search=Planner.new(o,difficulty,rng.randi(),heuristic_pick,heuristic_value)
	while not search.done:
		if is_cancelled():return {}
		search.step()
	last_plan={"nodes":search.visited,"depth":search.max_depth,"samples":search.samples.size()}
	return search.result(fallback)

func pick_async(o: Dictionary,tree: SceneTree,valid: Callable) -> Dictionary:
	if difficulty=="easy" or not planning or not Planner.applicable(o):return heuristic_pick(o)
	# The worker owns its agent, RNG, snapshots and rule models. It never touches UI
	# or the real game. Joining only after completion keeps rendering responsive.
	CardDB.load_all()
	var worker=get_script().new();worker.difficulty=difficulty;worker.rng.seed=rng.randi()
	var task=Thread.new();var error=task.start(worker.pick.bind(o.duplicate(true)))
	if error!=OK:return heuristic_pick(o)
	var job={"thread":task,"agent":worker};workers.append(job)
	plan_revision+=1;var revision=plan_revision;planning_active=true;var cancelled=false
	while task.is_alive():
		if not valid.call():cancelled=true;worker.cancel()
		await tree.process_frame
	var command=task.wait_to_finish() if task.is_started() else {}
	workers.erase(job)
	if revision==plan_revision:planning_active=false;last_plan=worker.last_plan.duplicate(true)
	return {} if cancelled or not valid.call() else command

func cancel():
	cancel_mutex.lock();cancel_requested=true;cancel_mutex.unlock()

func is_cancelled() -> bool:
	cancel_mutex.lock();var value=cancel_requested;cancel_mutex.unlock();return value

func cancel_all():
	for job in workers:job.agent.cancel()

func shutdown():
	cancel_all()
	for job in workers:
		if job.thread.is_started():job.thread.wait_to_finish()
	workers.clear()

func heuristic_value(action: Dictionary,o: Dictionary) -> float:
	var value=_score(action,o)
	if difficulty!="easy":value=Tactics.adjusted(action,o,value,difficulty=="hard")
	if difficulty=="hard":value-=Tactics.defense_reserve(action,o)
	return value

func heuristic_pick(o: Dictionary) -> Dictionary:
	if difficulty=="hard" and o.phase=="battle":
		o=o.duplicate();o.support_budget=Tactics.support_budget(o)
	var actions=Planner.shortlist(o)
	if actions.is_empty():return {}
	if difficulty=="easy" and o.phase=="battle" and rng.randf()<0.24:
		for a in actions:
			if a.type=="pass":return a
	var best=actions[0];var score=-INF
	for action in actions:
		var value=heuristic_value(action,o)
		value+=rng.randf()*(8.0 if difficulty=="easy" else 0.03)
		if value>score:score=value;best=action
	return best

func _card(id: String,o: Dictionary) -> Dictionary:
	var c=CardDB.get_card(o.nodes[id].card if o.nodes.has(id) else id).duplicate(true)
	for key in o.get("effective",{}).get(id,{}):c[key]=o.effective[id][key]
	return c

func _value(id: String,o: Dictionary) -> float:
	if id=="":return 0
	var c=_card(id,o)
	if c.kind=="resource":return 11+int(c.action)*2+int(id in ["E03","E04","E05"])*3
	var faction=o.factions[o.player]
	var traits=c.get("align",[])+c.get("tags",[])
	var value=float(c.p)*1.2+c.slots*1.8+c.gp*0.5
	if faction=="I02" and ("企业" in traits or "银行" in traits):value+=5
	if faction=="I03" and "计算机" in traits:value+=8
	if faction=="I04" and "怪异" in traits:value+=5
	if faction=="I05":value+=c.p*0.35
	if faction=="I06" and "地点" in traits:value+=7+int("巨大" in traits)*3
	if faction=="I07" and ("和平" in traits or "暴力" in traits):value+=6
	if faction=="I08" and "魔法" in traits:value+=10
	if faction=="I09" and "太空" in traits:value+=8
	if faction=="I10" and "暴力" in traits:value+=8
	if faction=="I11" and "绿色" in traits:value+=9
	if faction=="I12" and "共产" in traits:value+=9
	for goal_id in o.get("secret_goals",{}):
		match goal_id:
			"P51":value+=6 if "犯罪" in traits else 0
			"P52":value+=4 if c.p<=3 else 0
			"P53":value+=5 if "军队" in traits else 0
			"P54":value+=3*int("名人" in traits)+3*int("媒体" in traits)
			"P55":
				for a in c.align:
					if a not in o.secret_goals[goal_id].covered:value+=2
	if o.nodes.has(id) and o.nodes[id].get("devastated",false):value*=0.55
	if id in ["G012","G066","G028","G063","G021"]:value+=3
	if id=="G034" and o.hands.group.any(func(k):return "名人" in CardDB.get_card(k).tags):value+=3
	if "名人" in traits and o.nodes.has("G034") and o.nodes.G034.owner==o.player and not o.nodes.G034.get("silenced",false):value+=2
	return value

func _score(a: Dictionary,o: Dictionary) -> float:
	if a.type in ["resource","deploy","research"] or (a.type=="plot" and a.id in ResourceRules.PLOTS):return _resource_score(a,o)
	if a.type=="plot" and CovenantRules.PLOTS.has(a.id):return 1000
	if (a.type=="ability" and ((a.src.begins_with("R") and o.factions[o.player]=="I09") or a.src=="G138" or int(a.src.substr(1))>=151)) or (a.type=="plot" and int(a.id.substr(1))>=62):return _contemporary_score(a,o)
	if a.type=="ability" and a.get("pacify",false):
		return 40+_card(a.target,o).p if o.goals[o.player].ratio<1 else -1
	if a.type in ["trick","militia"] or (a.type=="ability" and int(a.src.substr(1))>=131):return _renewal_score(a,o)
	if a.type in ["synergy","lift"] or (a.type=="ability" and a.src in ["G116","G120","G127"]):return _synergy_score(a,o)
	if a.type in ["rebuild","wave","fact_check"] or (a.type=="ability" and (a.src.begins_with("R") or int(a.src.substr(1))>=81)):return _expansion_score(a,o)
	match a.type:
		"faction":return 1
		"initial":return _value(a.id,o)
		"initial_resource":return _value(a.id,o)
		"draw":return float(int(a.group)+int(a.plot))*5+int(a.get("filter_group",false))+int(a.get("filter_plot",false))
		"choose":
			var kind=o.choice.get("kind","")
			if kind=="n_inside":return _plot_value(o.choice.revealed_card,o) if a.id=="bottom" else 0
			if kind=="c_goal_limit":return _plot_value(a.id,o)
			if a.id=="":return -20
			var value=_value(a.id,o) if a.id.begins_with("G") or a.id.begins_with("E") else _plot_value(a.id,o)
			return -value if kind in ["discard_any","discard_group","limit","emptyvee","w_reroll","w_tax","w_epidemic","w_tsunami","x_overflow","x_scry","e_limit","e_discard"] else value
		"counter":return 30 if o.phase=="plot_response" else 0
		"accept_plot":return 0
		"auto":
			var slots=_card(a.parent,o).slots
			return 60+_value(a.id,o)+slots*0.1+_placement_value(a.id,a.parent,o)
		"ability":
			match a.src:
				"G002","G038":return 2
				"G003","G059":return 6+_value(a.target,o)*0.2
				"G004","G080":return 4
				"G010","G011","G013","G028","G056":return 12
				"G015":return 5-_plot_value(a.target,o)*0.15
				"G016":return 15+_value(a.target,o)*0.1
				"G036":return 10+int(o.nodes.has("G035"))*3
				"G037":return 8 if o.nodes[a.target].token>0 else -1
				"G072","G074":return 12
				"G078":return 10+_card(a.target,o).p-_card(a.target,o).gp if o.nodes[a.target].token>0 else -1
				"G046":return 5-_value(a.target,o)*0.1
				"G020":return 14+_value(a.target,o)*0.1
				"G065":
					if o.nodes[a.target].owner==o.player and o.factions[o.player]=="I04":return 1
					return -3
				_:return -5
		"plot":
			if int(a.id.substr(1))>=43:return _synergy_plot(a,o)
			if int(a.id.substr(1))>=31:return _expansion_plot(a,o)
			if o.phase=="battle":
				var strength=o.battle_values.strength
				if (o.battle.attacker==o.player and strength>=10) or (o.battle.attacker!=o.player and strength<2):return -2
				if a.id=="P16":return 35 if strength>=5 else -1
				return 8
			match a.id:
				"P17":return 20+_value(a.target,o)*0.2
				"P19":return 12 if _card(a.target,o).slots==0 else 3
				"P26","P27":return 10
				"P21","P23","P24","P25":return 12
				"P14":return 8-_value(a.target,o)*0.2
				"P22":return 2
				"P28":return 4
				"P29":return -2 if o.factions[o.player]=="I05" else 2
				"P30":return 6
				_:return -4
		"attack":return _attack_score(a,o)
		"support","self_defend":
			var b=o.battle
			var ours=b.attacker==o.player
			var leader=b.src if ours else b.target
			var n=a.get("power",_card(a.src,o).p if a.type=="support" else _card(a.src,o).p*2)
			var strength=o.battle_values.strength
			if ours and strength>=10:return -2
			if not ours and strength<2:return -2
			var cost=_value(a.group_fee,o)*0.1 if a.has("group_fee") else 0.0
			if a.has("plot_fee"):cost+=_plot_value(a.plot_fee,o)*0.2
			if a.has("resource_fee"):cost+=_value(a.resource_fee,o)*0.3
			return 4+n*0.4+_value(leader,o)*0.04-cost
		"rescue":return 24
		"pass":return 0
		"move":return -20
		"end":return 0
	return -10

func _placement_value(id: String,parent: String,o: Dictionary) -> float:
	var c=_card(id,o);var traits=c.align+c.tags
	if parent=="G133" and "共产" in traits:return 7
	if id=="G134" and "共产" in _card(parent,o).tags and _card(parent,o).slots<3:return 5
	if parent=="G140" and "狂热" in traits:return 5
	if parent=="G142" and "太空" in traits:return 3
	if parent=="G113" and "太空" in traits:return 5
	if parent=="G114" and "科学" in traits:return 5
	if parent=="G119" and "共产" in traits:return 5
	if parent=="G008" and "国家" in traits and _card(parent,o).gp<_card(parent,o).p:return 4
	if parent=="G017" and c.p<=2:return 8
	if parent=="G035" and "媒体" in traits:return 6
	if parent=="G073" and ("企业" in traits or "科学" in traits):return 4
	if parent=="G077" and ("企业" in traits or "银行" in traits):return 4
	if parent=="G041" and "怪异" in traits:return 4
	if parent=="G016":return 2
	if parent=="G081" and ("太空" in traits or "计算机" in traits):return 4
	if "名人" in traits and "地点" in _card(parent,o).tags:return 1
	return 0

func _plot_value(id: String,o: Dictionary={}) -> float:
	if CovenantRules.PLOTS.has(id):return 8+80*o.get("secret_goals",{}).get(id,{}).get("ratio",0)
	if id in ["P15","P16","P12","P13","P17"]:return 12
	if id in ["P21","P23","P24","P25","P27"]:return 9
	return 5

func _attack_score(a: Dictionary,o: Dictionary) -> float:
	var preview=o.previews.get(JSON.stringify(a),{})
	var strength=float(preview.get("strength",0))+float(preview.get("support_max",0))*0.7
	var enemy=o.nodes.has(a.target)
	if enemy:
		if o.nodes[a.target].token>0 and not preview.get("no_self",false):strength-=_card(a.target,o).p*0.8
	if strength<2:return -5
	var chance=minf(0.917,(strength-1.0)/9.0)
	var value=_value(a.target,o)
	if enemy:value+=8
	if enemy and a.target=="G067" and not o.nodes.G067.get("silenced",false) and not o.hands.plot.is_empty():value-=(1-chance)*6
	if a.mode=="destroy":value*=0.7;value+=6 if o.factions[o.player]=="I05" else 0
	if enemy and o.goals[1-o.player].ratio>=0.8:value+=15
	return chance*value-3

func _expansion_score(a: Dictionary,o: Dictionary) -> float:
	if a.type=="rebuild":return 26+_value(a.target,o)*0.4-a.payers.size()*3
	if a.type=="fact_check":return 18 if o.opponent_counts.plot==0 else 5
	if a.type=="wave":
		if a.src=="G101":return 8
		if a.src=="G112":return 8-_value(a.fee,o)*0.08 if o.battle_values.strength>=2 else -3
		if a.src=="G089":return 4+_card(a.target,o).p*0.25 if o.battle_values.strength<10 else -3
	if a.src.begins_with("R"):return -3
	match a.src:
		"G082":return 5 if o.world!=a.target else -2
		"G083":return 7
		"G084","G099":return 9
		"G086","G105":return 10
		"G090":return 2
		"G096":
			var v=_value(a.target,o)
			return 8+v*0.2 if not o.nodes.has(a.target) else 3
		"G102":return 4.5-_plot_value(a.target,o)*0.25
		"G107":return 10 if a.target in o.revealed.get("own_plot",[]) else 5-_plot_value(a.target,o)*0.2
		"G109":return 25+_value(a.target,o)*0.2
		"G110":return 7+_value(a.target,o)*0.12
	return -3

func _expansion_plot(a: Dictionary,o: Dictionary) -> float:
	if a.id in ["P31","P32","P33","P34","P35"]:
		var v=o.previews.get(JSON.stringify(a),{})
		return v.get("chance",0.0)*(_value(a.target,o)+12)+v.get("destroy_chance",0.0)*8-5
	match a.id:
		"P36":return 5
		"P37":
			var balance=0
			for id in o.nodes:
				if o.nodes[id].get("devastated",false):balance+=1 if o.nodes[id].owner==o.player else -1
			return 12+balance*8
		"P38":return 8+_value(a.target,o)*0.1
		"P39":return 14
		"P40":return 12+_value(a.target,o)*0.1
		"P41":return 28+_value(a.target,o)*0.3-(_value(a.fee,o)*0.15 if a.has("fee") else 0)
		"P42":return -o.battle_values.alignment*3 if o.battle_values.alignment<0 else -5
	return -3

func _synergy_score(a: Dictionary,o: Dictionary) -> float:
	if a.type=="lift":return 5+CardDB.get_card(a.src).gp*2
	if a.type=="synergy":
		if a.effect=="illusion":return o.battle_values.alignment*2.0 if o.battle_values.strength>=2 else -3
		return 5 if o.battle_values.strength<16 else -2
	match a.src:
		"G116":return 8+_plot_value(a.target,o)*0.3
		"G120":return 9+_value(a.target,o)*0.25-_value(a.fee,o)*0.18
		"G127":
			var own=o.nodes[a.target].owner==o.player
			if a.attachment=="P45":return 14 if own else -10
			return -10 if own else 8+_value(a.target,o)*0.2
	return -5

func _synergy_plot(a: Dictionary,o: Dictionary) -> float:
	var strength=o.battle_values.get("strength",0)
	match a.id:
		"P43":return float(o.battle_values.position)*1.4 if strength<10 and o.battle_values.position>0 else -3
		"P44":return 7+_value(a.target,o)*0.4
		"P45":return 7+_card(a.target,o).gp*3 if _card(a.target,o).gp>0 else -4
		"P46":
			var value=3.0
			if a.tag=="计算机" and o.factions[o.player]=="I03":value+=10
			var parent=o.nodes[a.target].parent
			if (a.tag=="太空" and parent=="G113") or (a.tag=="科学" and parent=="G114"):value+=6
			if a.tag=="太空" and o.nodes.has("G115") and o.nodes.G115.owner==o.player:value+=3
			return value
		"P47":return 7+_plot_value(a.target,o)*0.35
		"P48":
			var gain=0
			for id in o.nodes:
				if o.nodes[id].owner!=o.player or o.nodes[id].token==0 or id in o.battle.paid or id in [o.battle.src,o.battle.target]:continue
				if "共产" in _card(id,o).tags:gain+=maxi(0,_card(id,o).p-_card(id,o).gp)
			return 4+gain if gain>0 and strength<10 else -3
		"P49":return 10+_value(a.target,o)*0.2
		"P50":return 3+a.disaster_bonus-_plot_value(a.fee,o)*0.25 if strength<16 else -3
	return -5

func _renewal_score(a: Dictionary,o: Dictionary) -> float:
	if a.type=="trick":return 25-(_plot_value(a.fee,o)*0.3 if a.fee.begins_with("P") else _value(a.fee,o)*0.2)
	if a.type=="militia":return 7+a.power*0.5 if o.battle_values.strength>=2 else -2
	match a.src:
		"G135":return 9+_value(a.target,o)*0.1
		"G141":return 2+_placement_value(a.target,a.src,o)
		"G144":return 5
		"G148":return 8-_value(a.fee,o)*0.2
		"G149":
			var new_align=CardDB.get_card(a.other).align
			var value=-2.0
			for target in o.hands.group:
				var target_align=CardDB.get_card(target).align
				value=maxf(value,2.0*(new_align.filter(func(v):return v in target_align and v!="狂热").size()-_card(a.target,o).align.filter(func(v):return v in target_align and v!="狂热").size()))
			return value
	return -4

func _resource_score(a: Dictionary,o: Dictionary) -> float:
	var owned=o.nodes.keys().filter(func(k):return o.nodes[k].owner==o.player and _card(k,o).kind=="resource")
	if a.type=="deploy":
		var old=a.get("replace","")
		if old!="" and _value(a.id,o)<=_value(old,o):return -5
		return 57+_value(a.id,o)-(6 if a.has("fee") else 0)-(8 if old!="" else 0)
	if a.type=="research":
		match a.deck:
			"group":return 10 if o.hands.group.size()<3 else 1
			"plot":return 11 if o.hands.plot.size()<3 else 2
		return 14 if owned.size()<2 else (-2 if o.hands.resource.size()>0 else 2)
	if a.type=="plot":
		if a.id=="P59":return 22+_value(a.target,o)
		if a.id=="P60":return 8+_value(a.target,o)-_value(a.other,o)
		if a.id=="P56":return 20+_value(a.target,o)
		if a.id=="P57":return 17 if owned.size()<2 else 5
		return 9
	match a.src:
		"E16":
			var risk=float(o.battle_values.chance)
			var value=0.0
			for id in Tactics.branch(a.target,o):value+=_value(id,o)
			# Compare losing a whole branch to withdrawing it and spending the facility.
			return risk*value*2.0-(1.0-risk)*value*0.7-_value(a.src,o)*0.6
		"E17":return 30+_value(a.target,o)*0.2
		"E19":return 12 if o.battle_values.strength<10 else -4
		"E22":return (14 if o.hands.plot.size()<3 else 5)-_value(a.target,o)*0.3
		"E23":return 8+o.battle_values.loyalty if o.battle_values.strength<10 else -4
		"E01":return 8 if o.battle_values.strength<10 else -3
		"E07":return 13 if o.battle_values.strength>=2 else -3
		"E02":return 18+_value(a.target,o)*0.1
		"E06":return 15
		"E08":return 12 if owned.size()<2 else 3
		"E10":return _placement_value(a.target,a.parent,o)-5
		"E11":return 8+_card(a.target,o).p-_card(a.target,o).gp
		"E12":return 10 if o.battle_values.strength>=2 and o.battle_values.strength<=15 else -3
		"E15":return (18 if o.battle_values.strength>=7 else -4) if o.battle.attacker==o.player else (18 if o.battle_values.strength<7 else -4)
		"G091":return 13-_value(a.fee,o)*0.2
		"G093":return 17
	return -2

func _contemporary_score(a: Dictionary,o: Dictionary) -> float:
	if a.type=="resource":return 30+_value(a.target,o)*0.2 if a.src=="E17" else (12 if o.battle_values.strength<10 else -4)
	if a.type=="ability":
		if a.src.begins_with("R") and o.factions[o.player]=="I09":return 8 if o.hands.group.any(func(k):return "太空" in _card(k,o).tags) else 16
		match a.src:
			"G138":return 12-(_plot_value(a.target,o)*0.75 if a.target.begins_with("P") else _value(a.target,o)*0.4)
			"G151","G168":return 9
			"G155":return 5 if o.nodes[a.target].token>0 else -2
			"G157":return 12
			"G159":return 18+_value(a.target,o)*0.2-_value(a.other,o)*0.4
			"G162":return 12+_value(a.target,o)*0.3-_value(a.fee,o)*0.2
			"G164":return 15+_value(a.target,o)*0.3
	if a.type=="plot":
		match a.id:
			"P62":
				var balance=0
				for k in o.nodes:
					if "保守" in _card(k,o).align:balance+=1 if o.nodes[k].owner==o.player else -1
				return balance*4-1
			"P63":return 4 if o.hands.resource.size()>0 else 1
			"P64":var v=o.previews.get(JSON.stringify(a),{});return v.get("chance",0.0)*(_value(a.target,o)+15)-5
			"P65":return 8 if a.target in ["E01","E06","E11"] else 2
			"P66":return 25+_value(a.target,o)
			"P67":return 5+_card(a.target,o).gp*2
			"P68":return 30+_value(a.target,o)*0.4
			"P69":return 3+a.backlash if o.battle_values.strength in range(2,15) else -3
			"P70":return 8
	return -4
