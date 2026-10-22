extends RefCounted
## Public-position evaluation only. Never receives GameState, deck order or hidden hands.
static func chance(strength: float) -> float:
	var n=0
	for x in range(1,7):
		for y in range(1,7):
			if x+y<=mini(10,int(floor(strength))):n+=1
	return n/36.0
static func card(id: String,o: Dictionary) -> Dictionary:
	var c=CardDB.get_card(o.nodes[id].card if o.nodes.has(id) else id).duplicate(true)
	c.merge(o.get("effective",{}).get(id,{}),true);return c
static func branch(id: String,o: Dictionary) -> Array:
	var out=[id]
	for k in o.nodes:
		if o.nodes[k].parent==id:out.append_array(branch(k,o))
	return out
static func traits(id: String,o: Dictionary) -> Array:
	var c=card(id,o);return c.align+c.tags
static func pressure(id: String,o: Dictionary,p: int) -> float:
	var faction=o.factions[p];var c=card(id,o);var t=c.align+c.tags
	var relevant=faction=="I01" or CovenantRules.FACTIONS[faction].get("traits",[]).any(func(k):return k in t)
	var value=c.p*1.1+c.gp*0.6+c.slots
	if relevant:value+=7+10*o.goals[p].ratio
	if "绿色" in t and o.get("secret_goals",{}).has("P61") and p==o.player:value+=7
	return value
static func goal_potential(o: Dictionary,adding: Array) -> float:
	var p=o.player;var rules={o.factions[p]:CovenantRules.FACTIONS[o.factions[p]]}
	for id in o.get("secret_goals",{}):rules[id]=CovenantRules.PLOTS[id]
	var best=0.0
	for goal_id in rules:
		var rule=rules[goal_id];var values={"groups":0,"power":0,"small":0,"huge":0,"celebrity":0,"media":0,"destroyed":o.goals[p].values.destroyed,"alignments":0,"facilities":0};var coverage=[]
		var members=o.nodes.keys().filter(func(k):return o.nodes[k].owner==p and card(k,o).kind=="group" and not o.nodes[k].get("devastated",false))
		for id in adding:
			if o.nodes.has(id) and o.nodes[id].get("devastated",false):continue
			if id not in members:members.append(id)
		for id in members:
			var c=card(id,o);var t=c.align+c.tags
			if rule.has("traits") and not rule.traits.any(func(k):return k in t):continue
			values.groups+=1;values.power+=c.p;values.small+=int(c.p<=3);values.huge+=int("巨大" in t);values.celebrity+=int("名人" in t);values.media+=int("媒体" in t)
			for a in c.align:
				if a not in coverage:coverage.append(a)
		values.alignments=coverage.size()
		for id in o.nodes:
			if o.nodes[id].owner==p and card(id,o).kind=="resource" and "设施" in card(id,o).tags:values.facilities+=1
		var ratio=1.0
		for key in rule:
			if key!="traits":ratio=minf(ratio,float(values[key])/rule[key])
		var old=o.goals[p].ratio if goal_id==o.factions[p] else o.secret_goals[goal_id].ratio
		best=maxf(best,(ratio-old)*85+(220 if ratio>=1 and old<1 else 0))
	return best
static func adjusted(a: Dictionary,o: Dictionary,base: float,hard: bool) -> float:
	var p=o.player
	if a.type=="end":
		if o.goals[p].met and o.turns[1-p]>=1:return 150 if not o.goals[1-p].met else -10
		return 0
	if a.type=="move":
		var old=o.nodes[a.src].parent
		var t=traits(a.src,o);var gain=0.0
		for parent in [old,a.parent]:
			var factor=1 if parent==a.parent else -1
			if parent=="G133" and "共产" in t:gain+=factor*7
			if parent=="G170" and "魔法" in t:gain+=factor*3
			if parent=="G153" and "共产" in t:gain+=factor*4
			if parent=="G008" and "国家" in t:gain+=factor*5
			if parent=="G134":gain+=0
		return gain-4 if hard else -8
	if a.type=="auto":return 23+pressure(a.id,o,p)+(6 if a.get("parent","").begins_with("R") else 0)+base*0.08+(goal_potential(o,[a.id]) if hard else 0)
	if a.type=="deploy":
		var existing=o.nodes.keys().filter(func(k):return o.nodes[k].owner==p and card(k,o).kind=="resource")
		var value=20.0+(5 if existing.size()<2 else -9)
		if a.id in ["E04","E05"]:value+=5
		if a.id=="E13" and not existing.any(func(k):return "秘宝" in card(k,o).tags):value-=9
		if a.id=="E20" and not o.hands.group.any(func(k):return "绿色" in traits(k,o)):value-=4
		if a.get("replace","")!="":value-=10
		if a.has("fee"):value-=card(a.fee,o).p
		if hard and a.id=="E04" and o.actions.any(func(k):return k.type=="auto") and o.nodes["R%d"%p].token>1:value+=25
		return value
	if a.type=="research":
		if o.actions.any(func(k):return k.type=="auto") and o.nodes[a.src].token==1:return -6
		return base
	if a.type=="attack":
		var v=o.previews.get(JSON.stringify(a),{});var enemy=o.nodes.has(a.target)
		var own=float(v.get("support_max",0))*(0.75 if hard else 0.55)
		# Available defense is an upper bound: spending every defender is rarely optimal.
		var opposition=float(v.get("enemy_support_max",0))*(0.35 if hard else 0.25)+float(v.get("self_max",0))*(0.6 if hard else 0.5)
		var strength=float(v.get("strength",0))+own-opposition
		var probability=chance(strength)
		if v.has("fixed_dice"):probability=1 if v.fixed_dice[0]+v.fixed_dice[1]<=mini(10,strength) else 0
		var value=pressure(a.target,o,p)
		if enemy:
			value+=12+10*o.goals[1-p].ratio
			if a.mode=="control":
				for child in branch(a.target,o).slice(1):value+=pressure(child,o,p)*0.65
			if hard and a.mode=="control" and o.goals[1-p].ratio>=0.75:value+=12
		if a.mode=="destroy":value*=0.7;value+=14 if o.factions[p]=="I05" else 0
		elif hard:value+=goal_potential(o,branch(a.target,o) if enemy else [a.target])
		var root_cost=7 if a.src.begins_with("R") and o.actions.any(func(k):return k.type=="auto") and o.nodes[a.src].token==1 else 0
		return probability*value-(1-probability)*5-4-root_cost
	if a.type in ["support","self_defend"] and hard:
		var b=o.battle;var ours=b.attacker==p;var strength=float(o.battle_values.strength);var n=a.get("power",0)
		var before=chance(strength);var after=chance(strength+n if ours else strength-n)
		var gain=after-before if ours else before-after
		# Several helpers can cross the dice threshold together even if the first alone cannot.
		# Count each source once; optional modes and alternative fees are not extra helpers.
		var remaining={}
		for candidate in o.actions:
			if candidate.type in ["support","self_defend"] and candidate.src!=a.src:remaining[candidate.src]=maxi(remaining.get(candidate.src,0),candidate.get("power",0))
		var total=0
		for amount in remaining.values():total+=amount
		for fraction in [0.25,0.5,0.75,1.0]:
			var future=strength+(total*fraction if ours else -total*fraction)
			var combined=chance(future+n)-chance(future) if ours else chance(future)-chance(future-n)
			gain=maxf(gain,combined*0.8)
		var value=pressure(b.target,o,p)+18
		if o.nodes.has(b.target):value+=branch(b.target,o).size()*4
		var cost=0.8 if a.get("nature",false) else 2.2
		if a.has("plot_fee"):cost+=2.8
		if a.has("resource_fee"):cost+=8
		if a.has("group_fee"):cost+=3
		return gain*value-cost
	if a.type in ["counter","trick","fact_check"] and hard:
		var plot=o.get("pending_plot",{});var id=plot.get("id","")
		var price=3.0 if a.type=="counter" else 6.0
		if a.type=="fact_check" and o.opponent_counts.plot>0:return 3
		if CovenantRules.PLOTS.has(id):return 500-price
		if not o.battle.is_empty():
			var n=6 if id in ["P12","P13"] else (4 if id in ["P10","P20"] or int(id.substr(1)) in range(1,10) else 2)
			var strength=o.battle_values.strength;var delta=absf(chance(strength+n)-chance(strength-n))
			return delta*(pressure(o.battle.target,o,p)+20)-price
		if id in ["P56","P59","P64","P67"]:return 20
		if id in ["P22","P25"]:return -3
		return 4
	if a.type=="plot" and hard and o.phase=="battle" and not CovenantRules.PLOTS.has(a.id):
		if a.id=="P16":return 45*chance(o.battle_values.strength)-5
		if a.id in ["P10","P11","P12","P13","P20"] or int(a.id.substr(1)) in range(1,10):
			var n=6 if a.id in ["P12","P13"] else (2 if a.id=="P11" else 4);var ours=o.battle.attacker==p;var strength=o.battle_values.strength
			return absf(chance(strength+(n if ours else -n))-chance(strength))*(pressure(o.battle.target,o,p)+22)-3
	return base

static func defense_reserve(a: Dictionary,o: Dictionary) -> float:
	if o.phase!="main" or a.type not in ["ability","attack","move","rebuild","resource","plot"]:return 0
	var p=o.player;var opponents=o.nodes.keys().filter(func(k):return o.nodes[k].owner!=p and card(k,o).kind=="group" and not o.nodes[k].get("devastated",false))
	if opponents.is_empty():return 0
	var actors=a.get("payers",[]).duplicate();var src=a.get("src","")
	if a.type in ["ability","attack","move","resource"] and o.nodes.has(src) and card(src,o).kind=="group":
		if a.type!="ability" or (src not in ["G015","G016","G018","G022","G046","G090","G099","G102","G141","G148"] and not a.get("free",false)):actors.append(src)
	if a.has("payer"):actors.append(a.payer)
	if a.type=="plot" and a.id in ["P21","P23","P24","P25"]:actors.append(a.target)
	var available=o.nodes.keys().filter(func(k):return o.nodes[k].owner==p and card(k,o).kind=="group" and o.nodes[k].token>0 and not o.nodes[k].get("devastated",false)).size()
	var cost=0.0;var seen=[]
	for id in actors:
		if id in seen or not o.nodes.has(id) or o.nodes[id].token!=1 or card(id,o).kind!="group":continue
		seen.append(id)
		# A token protects its holder and can support other groups. Deep, valuable branches
		# and the last ready defenders deserve more than a low-value cycling ability.
		cost+=3+card(id,o).p*0.7+mini(3,branch(id,o).size()-1)*2+o.goals[p].ratio*3+(3 if available<=2 else 0)
	return cost*(0.3 if a.type=="attack" else 1.0)
