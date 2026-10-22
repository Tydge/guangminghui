class_name CovenantRules
extends RefCounted
## One evaluator for public faction plans and private, actively played goal plots.
const FACTIONS={
	"I01":{"groups":8,"power":45},
	"I02":{"traits":["企业","银行"],"groups":6,"power":30},
	"I03":{"traits":["计算机"],"groups":5,"power":26},
	"I04":{"traits":["怪异"],"groups":5,"power":25},
	"I05":{"destroyed":6},
	"I06":{"traits":["地点"],"groups":5,"huge":2,"power":30},
	"I07":{"traits":["和平"],"groups":6,"power":25},
	"I08":{"traits":["魔法"],"groups":5,"power":25},
	"I09":{"traits":["科学","太空"],"groups":5,"power":26},
	"I10":{"traits":["暴力"],"groups":5,"power":26},
	"I11":{"traits":["绿色"],"groups":6,"power":24},
	"I12":{"traits":["共产"],"groups":6,"power":24}
}
const PLOTS={
	"P51":{"traits":["犯罪"],"groups":5,"power":20},
	"P52":{"groups":9,"small":6},
	"P53":{"traits":["军队"],"groups":4,"destroyed":3},
	"P54":{"groups":7,"celebrity":3,"media":4},
	"P55":{"groups":7,"alignments":10},
	"P61":{"traits":["绿色"],"groups":5,"facilities":2}
}
const ALIGNMENTS=["政府","企业","自由","保守","和平","暴力","正统","怪异","犯罪","狂热"]
const LABELS={"groups":"团体","power":"力量","huge":"巨大","small":"小团体","destroyed":"摧毁","celebrity":"名人","media":"媒体","alignments":"阵营","facilities":"设施"}
var state: WeakRef
var g:
	get:return state.get_ref()
func _init(game) -> void:state=weakref(game)
func is_goal(id: String) -> bool:return PLOTS.has(id)
func held(p: int) -> Array:return g.hands[p].plot.filter(is_goal)
func eligible(p: int) -> Array:return g.groups(p).filter(func(k):return not g.wave.devastated(k))
func progress(p: int,id: String) -> Dictionary:
	var rule=FACTIONS.get(id,PLOTS.get(id,{}));var all=eligible(p);var subset=all
	if rule.has("traits"):subset=all.filter(func(k):return rule.traits.any(func(t):return g.has(k,t)))
	var values={"groups":subset.size(),"power":0,"huge":0,"small":0,"destroyed":g.destroyed[p],"celebrity":0,"media":0,"alignments":0}
	var coverage: Array=[]
	for k in subset:
		values.power+=g.stat(k,"p")
		values.huge+=int(g.has(k,"巨大"));values.small+=int(g.card(k).p<=3)
		values.celebrity+=int(g.has(k,"名人"));values.media+=int(g.has(k,"媒体"))
		for a in g.alignments(k):
			if a in ALIGNMENTS and a not in coverage:coverage.append(a)
	values.alignments=coverage.size()
	values.facilities=g.resources.field(p).filter(func(k):return g.has(k,"设施")).size()
	var parts: Array=[];var ratio=1.0;var met=not rule.is_empty()
	for key in LABELS:
		if not rule.has(key):continue
		var target=rule[key];met=met and values[key]>=target;ratio=minf(ratio,float(values[key])/target)
		parts.append("%s%d/%d"%[LABELS[key],values[key],target])
	return {"met":met,"text":" · ".join(parts),"ratio":minf(1,ratio),"values":values,"covered":coverage}
func faction_goal(p: int) -> Dictionary:return progress(p,g.factions[p])
func can_declare(p: int,id: String) -> bool:
	return is_goal(id) and g.current==p and g.phase=="main" and mini(g.turns[0],g.turns[1])>=1 and progress(p,id).met
func private_goals(p: int) -> Dictionary:
	var result={}
	for id in held(p):result[id]=progress(p,id)
	return result
func main_plots(id: String,p: int) -> Array:
	return [g._a("plot","宣告胜利 · "+g.title(id),{"id":id,"src":id,"target":""})] if can_declare(p,id) else []
func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="main" and g.current==p and g.factions[p]=="I07" and g.wave.available(g.root(p),p) and g.token(g.root(p)) and not g.used.has("pacify"):
		for target in g.groups(p):
			if g.has(target,"暴力"):out.append(g._a("ability","化干戈 → "+g.title(target),{"src":g.root(p),"target":target,"pacify":true}))
	return out
func handle(p: int,a: Dictionary) -> bool:
	if a.type=="ability" and a.get("pacify",false):
		g.nodes[a.src].token=0;g.used.pacify=true;g.nodes[a.target].pacified=true
		if g.nodes[a.target].has("mask"):g.nodes[a.target].mask=peaceful(g.nodes[a.target].mask)
		g._log(g._who(p)+" · 化干戈 → "+g.title(a.target),"ability",{"id":a.src,"target":a.target,"player":p});g._after_effect();return true
	if a.type=="choose" and g.choice.get("kind","")=="c_goal_limit":
		var c=g.choice.duplicate(true)
		for id in held(p):
			if id!=a.id:g._discard(p,id,"goal_limit")
		g.choice={};g.phase=c.saved_phase;g._log(g._who(p)+"保留了1张目标阴谋","goal_keep",{"player":p});g._after_effect();return true
	return false
static func peaceful(a: Array) -> Array:
	var result=a.duplicate();result.erase("暴力")
	if "和平" not in result:result.append("和平")
	return result
func support_override(id: String,b: Dictionary,d: Dictionary) -> Dictionary:
	var p=g.owner(id);var leader=b.src if p==b.attacker else b.target
	if not b.has("disaster") and g.factions[p]=="I08" and g.wave.enabled(g.root(p),p) and g.has(id,"魔法") and g.has(leader,"魔法"):
		return {"base":g.stat(id,"p"),"basis":"P","reason":"赫尔墨斯门徒 · 秘术共鸣"}
	return d
func repair_hand() -> bool:
	# Complete existing selections first, without wrapping private peek buffers.
	if g.phase not in ["main","draw","battle","plot_response"]:return false
	for p in [0,1]:
		var goals=held(p)
		if goals.size()>1:
			g._set_choice(p,"目标阴谋最多1张 · 选择保留",goals,"c_goal_limit",{"saved_phase":g.phase});return true
	return false
func resolve_plot(a: Dictionary) -> bool:
	if not is_goal(a.id):return false
	g._spent_plot(a.id);g.claim={"player":a.player,"id":a.id}
	g.wave.plot_rewards(a.player,a.id,a);g._after_effect();return true
func settle_claim() -> bool:
	if g.claim.is_empty():return false
	var c=g.claim;g.claim={}
	if progress(c.player,c.id).met:g._finish(c.player,g.title(c.id)+" · 目标阴谋宣告胜利");return true
	g._log(g.title(c.id)+" · 目标条件已不满足","goal_failed");return false
func reader_text(id: String) -> String:
	for p in [0,1]:
		if id in g.hands[p].plot and (p==0 or id in g.exposed):
			var value=progress(p,id);var status="条件达成" if value.met else "尚未达成"
			return "%s · %s\n己方主要阶段主动打出，可被反制。"%[status,value.text]
	return "己方主要阶段达标后主动打出，可被反制。"
