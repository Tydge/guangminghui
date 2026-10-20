class_name AiAgent
extends RefCounted
## No GameState reference. This agent receives only a redacted observation.

var rng = RandomNumberGenerator.new()

func _init() -> void:rng.randomize()

func pick(o: Dictionary) -> Dictionary:
	var actions=o.actions
	if actions.is_empty():return {}
	var best=actions[0];var score=-INF
	for action in actions:
		var value=_score(action,o)+rng.randf()*0.05
		if value>score:score=value;best=action
	return best

func _card(id: String,o: Dictionary) -> Dictionary:
	var c=CardDB.get_card(o.nodes[id].card if o.nodes.has(id) else id).duplicate(true)
	for key in o.get("effective",{}).get(id,{}):c[key]=o.effective[id][key]
	return c

func _value(id: String,o: Dictionary) -> float:
	if id=="":return 0
	var c=_card(id,o);var faction=o.factions[o.player]
	var traits=c.get("align",[])+c.get("tags",[])
	var value=float(c.p)*1.2+c.slots*1.8+c.gp*0.5
	if faction=="I02" and ("企业" in traits or "银行" in traits):value+=5
	if faction=="I03" and "计算机" in traits:value+=8
	if faction=="I04" and "怪异" in traits:value+=5
	if faction=="I05":value+=c.p*0.35
	if faction=="I06" and "地点" in traits:value+=7+int("巨大" in traits)*3
	if o.nodes.has(id) and o.nodes[id].get("devastated",false):value*=0.55
	if id in ["G012","G066","G028","G063","G021"]:value+=3
	return value

func _score(a: Dictionary,o: Dictionary) -> float:
	if a.type in ["trick","militia"] or (a.type=="ability" and int(a.src.substr(1))>=131):return _renewal_score(a,o)
	if a.type in ["synergy","lift"] or (a.type=="ability" and a.src in ["G116","G120","G127"]):return _synergy_score(a,o)
	if a.type in ["rebuild","wave","fact_check"] or (a.type=="ability" and (a.src.begins_with("R") or int(a.src.substr(1))>=81)):return _expansion_score(a,o)
	match a.type:
		"faction":return 1
		"initial":return _value(a.id,o)
		"draw":return float(int(a.group)+int(a.plot))*5+int(a.get("filter_group",false))+int(a.get("filter_plot",false))
		"choose":
			var kind=o.choice.get("kind","")
			if a.id=="":return -20
			var value=_value(a.id,o) if a.id.begins_with("G") else _plot_value(a.id)
			return -value if kind in ["discard_any","discard_group","limit","emptyvee","w_export","w_reroll","w_tax","w_epidemic","w_tsunami","x_overflow","x_scry"] else value
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
				"G015":return 5-_plot_value(a.target)*0.15
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
			if a.has("plot_fee"):cost+=_plot_value(a.plot_fee)*0.2
			return 4+n*0.4+_value(leader,o)*0.04-cost
		"rescue":return 24
		"mediate":return 5.2+_value(o.battle.target,o)*0.04 if o.battle_values.strength>=2 else -2
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
	if parent=="G017" and c.p<=2:return 8
	if parent=="G035" and "媒体" in traits:return 6
	if parent=="G073" and ("企业" in traits or "科学" in traits):return 4
	if parent=="G077" and ("企业" in traits or "银行" in traits):return 4
	if parent=="G041" and "怪异" in traits:return 4
	if parent=="G016":return 2
	if parent=="G081" and ("太空" in traits or "计算机" in traits):return 4
	if "名人" in traits and "地点" in _card(parent,o).tags:return 1
	return 0

func _plot_value(id: String) -> float:
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
		"G102":return 7-_plot_value(a.target)*0.25
		"G107":return 10 if a.target in o.revealed.get("own_plot",[]) else 5-_plot_value(a.target)*0.2
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
		"G116":return 8+_plot_value(a.target)*0.3
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
		"P47":return 7+_plot_value(a.target)*0.35
		"P48":
			var gain=0
			for id in o.nodes:
				if o.nodes[id].owner!=o.player or o.nodes[id].token==0 or id in o.battle.paid or id in [o.battle.src,o.battle.target]:continue
				if "共产" in _card(id,o).tags:gain+=maxi(0,_card(id,o).p-_card(id,o).gp)
			return 4+gain if gain>0 and strength<10 else -3
		"P49":return 10+_value(a.target,o)*0.2
		"P50":return 3+a.disaster_bonus-_plot_value(a.fee)*0.25 if strength<16 else -3
	return -5

func _renewal_score(a: Dictionary,o: Dictionary) -> float:
	if a.type=="trick":return 25-(_plot_value(a.fee)*0.3 if a.fee.begins_with("P") else _value(a.fee,o)*0.2)
	if a.type=="militia":return 7+a.power*0.5 if o.battle_values.strength>=2 else -2
	match a.src:
		"G135":return 9+_value(a.target,o)*0.1
		"G138":
			var own=o.nodes[a.target].owner==o.player
			if a.attachment=="P45":return -8 if own else 9+_card(a.target,o).gp*2
			return 7 if own else -8
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
