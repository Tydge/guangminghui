extends RefCounted
## Small card interactions built on the existing action/response and presentation queues.
var state: WeakRef
var g:
	get: return state.get_ref()
const TECH = ["计算机","科学","太空"]

func _init(game) -> void: state=weakref(game)
func ready(id: String,p: int=-1) -> bool: return g.wave.enabled(id,p)
func normal(b: Dictionary) -> bool: return not b.has("disaster")
func battle_plot(id: String) -> bool:
	var category=g.card(id).get("category","")
	return category.contains("战斗") and not category.contains("反制") and id not in ["P15","P16"]
func disaster_plot(id: String) -> bool: return g.card(id).get("category","").ends_with("·灾难")

func adjust_stat(id: String,key: String,value: int) -> int:
	if not g.nodes.has(id):return value
	if id=="G119" and key=="p" and ready(id):
		value+=mini(2,g.children(id).filter(func(k):return g.has(k,"共产")).size())
	if key=="gp" and "P45" in g.nodes[id].attached:return 0
	return value

func enqueue(task: Dictionary,in_battle: bool=false) -> void:
	if in_battle:g.wave.response_queue.append(task)
	else:g.wave.queue.append({"kind":"synergy","task":task,"player":task.player})

func draw_reward(source: String,p: int,deck: String,in_battle: bool=false) -> void:
	var quota="synergy:"+source+":"+str(p)
	if not ready(source,p) or g.used.has(quota):return
	g.used[quota]=true
	enqueue({"kind":"s_draw","source":source,"player":p,"deck":deck},in_battle)

func hand_discarded(p: int,id: String,reason: String) -> void:
	if g.current==p and g.card(id).kind=="group" and reason not in ["limit","failed_recruit"]:
		draw_reward("G124",p,"plot",not g.battle.is_empty())

func entry_reward(id: String,p: int,before: Array) -> void:
	if p==g.current and "G129" in before and g.card(id).p<=2:draw_reward("G129",p,"plot")

func committed(p: int,a: Dictionary) -> void:
	var payer=a.get("payer",a.get("target","") if a.id in ["P21","P23","P24","P25"] else "")
	a.magic_payment=payer!="" and g.nodes.has(payer) and g.has(payer,"魔法")

func plot_reward(p: int,a: Dictionary) -> void:
	if a.get("magic_payment",false) and not g.card(a.id).category.contains("反制"):
		draw_reward("G117",p,"plot",not g.battle.is_empty())

func ability_actions(src: String,p: int) -> Array:
	var out: Array=[]
	if not ready(src,p) or g.used.has(src):return out
	if src!="G120" and not g.token(src):return out
	match src:
		"G116":
			if g.can_enemy(p):
				for target in g.hands[1-p].plot:
					if target in g.exposed:out.append(g._a("ability","封存秘闻 → "+g.title(target),{"src":src,"target":target}))
		"G120":
			for target in g.groups(p):
				if target==src or not g.can_recharge(target) or not (g.has(target,"共产") or g.has(target,"绿色")):continue
				for fee in g.hands[p].group:out.append(g._a("ability","互助储备 → %s · 弃%s"%[g.title(target),g.title(fee)],{"src":src,"target":target,"fee":fee}))
		"G127":
			for target in g.groups(p)+(g.groups(1-p) if g.can_enemy(p) else []):
				for attachment in g.nodes[target].attached:
					if can_detach(target,attachment):out.append(g._a("ability","撤销协议 · %s的%s"%[g.title(target),g.title(attachment)],{"src":src,"target":target,"attachment":attachment}))
	return out

func can_detach(target: String,id: String) -> bool:
	return id!="P19" or g.children(target).size()<=g.card(target).slots

func detach(target: String,id: String) -> void:
	g.nodes[target].attached.erase(id);g.discards.plot.push_front(id)

func main_plots(id: String,p: int) -> Array:
	var out: Array=[];var actors=g.groups(p).filter(func(k):return g.token(k))
	match id:
		"P44":
			for target in g.groups(p):
				if g.has(target,"名人") and id not in g.nodes[target].attached:out.append(g._a("plot","保镖 → "+g.title(target),{"id":id,"src":id,"target":target}))
		"P45":
			if g.can_enemy(p):
				for target in g.groups(1-p):
					if id in g.nodes[target].attached or not (g.has(target,"企业") or g.has(target,"银行")):continue
					for payer in actors.filter(func(k):return g.has(k,"政府") or g.has(k,"媒体")):out.append(g._a("plot","监管调查 → %s · %s行动"%[g.title(target),g.title(payer)],{"id":id,"src":id,"target":target,"payer":payer}))
		"P46":
			for target in g.groups(p):
				if not TECH.any(func(t):return g.has(target,t)):continue
				for tag in TECH:
					if not g.has(target,tag):out.append(g._a("plot","技术融合 → %s · +%s"%[g.title(target),tag],{"id":id,"src":id,"target":target,"tag":tag}))
		"P47":
			for target in g.discards.plot.filter(battle_plot):
				for payer in actors.filter(func(k):return g.has(k,"魔法")):out.append(g._a("plot","奥术回响 → %s · %s行动"%[g.title(target),g.title(payer)],{"id":id,"src":id,"target":target,"payer":payer}))
		"P49":
			for target in g.groups(p).filter(func(k):return g.has(k,"军队") and g.can_recharge(k)):
				for payer in actors.filter(func(k):return g.has(k,"银行")):out.append(g._a("plot","装备融资 → %s · %s行动"%[g.title(target),g.title(payer)],{"id":id,"src":id,"target":target,"payer":payer}))
	return out

func combat_plots(id: String,p: int,b: Dictionary) -> Array:
	var out: Array=[]
	if p!=b.attacker:return out
	if id=="P43" and normal(b) and b.mode=="destroy" and g.owner(b.target)==1-p and g.has(b.target,"名人") and not b.get("sniped",false):
		out.append(g._a("plot","狙击 · 忽略位置防御",{"id":id,"src":id,"target":b.target}))
	if id=="P48" and normal(b) and not b.get("mobilized",false) and g.field(p).any(func(k):return g.token(k) and g.has(k,"共产") and k not in b.get("paid",[]) and k not in [b.src,b.target]):
		out.append(g._a("plot","联合动员 · 后续共产支援可用P",{"id":id,"src":id,"target":b.target}))
	if id=="P50" and b.has("disaster"):
		for fee in g.hands[p].plot:
			if fee==id:continue
			var amount=6 if disaster_plot(fee) else 3
			out.append(g._a("plot","连锁事故 +%d · 弃%s"%[amount,g.title(fee)],{"id":id,"src":id,"target":b.target,"fee":fee,"disaster_bonus":amount}))
	return out

func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="main" and g.current==p:
		for id in g.groups(p):
			if "P45" in g.nodes[id].attached and g.token(id):out.append(g._a("lift","解除监管 · "+g.title(id)+"行动",{"src":id,"target":id,"id":"P45"}))
	if g.phase=="battle" and g.battle.get("responder",-1)==p:
		var b=g.battle
		if normal(b):
			if no_self_defense(b):out=out.filter(func(a):return a.type!="self_defend")
			if p==b.defender and ready("G118",p) and g.token("G118") and not b.get("alignment_zero",false) and g.battle_values().alignment!=0:
				out.append(g._a("synergy","障眼法 · 阵营修正归零",{"src":"G118","target":b.target,"effect":"illusion"}))
		elif p==b.attacker and ready("G125",p) and g.token("G125"):
			out.append(g._a("synergy","事故添乱 · 灾难威力+3",{"src":"G125","target":b.target,"effect":"disaster"}))
	return out

func no_self_defense(b: Dictionary) -> bool:
	return normal(b) and b.mode=="control" and b.src=="G126" and ready("G126") and g.has(b.target,"企业")

func support_override(id: String,b: Dictionary,base: int,basis: String,reason: String) -> Dictionary:
	if not normal(b):return {"base":base,"basis":basis,"reason":reason}
	var p=g.owner(id);var full=false;var source=""
	if p==b.attacker and b.get("mobilized",false) and g.has(id,"共产"):full=true;source="联合动员"
	if p==b.defender:
		if g.nodes[id].parent=="G113" and ready("G113",p) and g.has(id,"太空"):full=true;source="远程中继"
		if id=="G123" and ready(id,p) and (g.has(b.target,"名人") or g.has(b.target,"地点")):full=true;source="维和护卫"
	if full:return {"base":g.stat(id,"p"),"basis":"P","reason":source}
	return {"base":base,"basis":basis,"reason":reason}

func support_bonus(id: String,b: Dictionary) -> int:
	return 1 if normal(b) and ready("G115",g.owner(id)) and g.has(id,"太空") and g.has(b.target,"地点") else 0

func values(b: Dictionary,v: Dictionary) -> Dictionary:
	if normal(b):
		if b.get("sniped",false):v.strength+=v.position;v.position=0
		if b.get("alignment_zero",false):v.strength-=v.alignment;v.alignment=0
		if b.mode=="control" and g.nodes.has(b.target) and ready("G128",b.defender) and not g.has(b.target,"企业") and g.has(b.src,"企业"):
			v.defense+=2;v.strength-=2
		v["no_self"]=no_self_defense(b)
	return v

func handle(p: int,a: Dictionary) -> bool:
	if a.type=="trigger" and g.choice.get("task",{}).get("kind","").begins_with("s_"):
		var c=g.choice.duplicate(true);var task=c.task
		g.choice={};g.phase=c.resume
		match task.kind:
			"s_draw":
				g._draw(p,task.deck)
				g._log(g.title(task.source)+" · 抽1张"+("阴谋" if task.deck=="plot" else "团体"),"ability",{"id":task.source,"player":p,"passive":true})
			"s_tag":
				if g.nodes.has(task.target) and g.owner(task.target)==p:
					add_tag(task.target,"共产")
					g._log("公有化 · "+g.title(task.target)+"获得共产标签","ability",{"id":"G121","target":task.target,"player":p})
			"s_guard":
				g.battle.guard_presented=true;g.wave.resolve_battle();return true
		if c.resume=="battle":g.wave.next_response_trigger()
		g._after_effect();return true
	if a.type=="ability" and a.src in ["G116","G120","G127"]:
		g.used[a.src]=true
		if a.src!="G120":g.nodes[a.src].token=0
		match a.src:
			"G116":g._discard(1-p,a.target)
			"G120":g._discard(p,a.fee);g.nodes[a.target].token=1;g.recharged[a.target]=true
			"G127":detach(a.target,a.attachment)
		g._log(g._who(p)+" · "+a.label,"ability",{"id":a.src,"target":a.target,"player":p});g._after_effect();return true
	if a.type=="lift":
		g.nodes[a.src].token=0;detach(a.target,"P45")
		g._log(g.title(a.target)+" · 监管调查已解除","ability",{"id":"P45","target":a.target,"player":p});g._after_effect();return true
	if a.type=="synergy":
		g.nodes[a.src].token=0
		if a.effect=="illusion":g.battle.alignment_zero=true
		else:g.battle.bonus_a+=3
		g._battle_record("ability",p,a.src,a.target,a.label)
		g._log(g._who(p)+" · "+a.label,"ability",{"id":a.src,"player":p});g._response_changed(p);return true
	return false

func add_tag(target: String,tag: String) -> void:
	if not g.nodes[target].has("extra_tags"):g.nodes[target].extra_tags=[]
	if tag not in g.nodes[target].extra_tags:g.nodes[target].extra_tags.append(tag)

func resolve_plot(a: Dictionary) -> bool:
	if a.id not in ["P43","P44","P45","P46","P47","P48","P49","P50"]:return false
	var p=a.player
	match a.id:
		"P43":g.battle.sniped=true
		"P44","P45":g.nodes[a.target].attached.append(a.id)
		"P46":add_tag(a.target,a.tag)
		"P47":g.discards.plot.erase(a.target);g.hands[p].plot.append(a.target)
		"P48":g.battle.mobilized=true
		"P49":g.nodes[a.target].token=1;g.recharged[a.target]=true;g._draw(p,"group")
		"P50":g.battle.bonus_a+=a.disaster_bonus
	if a.id not in ["P44","P45"]:g._spent_plot(a.id)
	g.wave.plot_rewards(p,a.id,a)
	if not g.battle.is_empty():g._response_changed(p)
	else:g._after_effect()
	return true

func prepare_guard(b: Dictionary,destroy: bool) -> bool:
	if destroy and normal(b) and not b.rescue and not b.get("guard_presented",false) and "P44" in g.nodes[b.target].attached:
		g.wave.auto_trigger({"kind":"s_guard","source":"P44","target":b.target,"player":b.defender},"battle");return true
	return false

func guard_blocks(b: Dictionary) -> bool:
	if not normal(b) or not b.get("guard_presented",false) or "P44" not in g.nodes[b.target].attached:return false
	detach(b.target,"P44");g.nodes[b.target].token=0
	g._battle_record("ability",b.defender,"P44",b.target,"保镖 · 挡下摧毁","已消耗")
	return true

func battle_finished(b: Dictionary,success: bool,destroyed: bool) -> void:
	if not normal(b):return
	var p=b.attacker
	if success and b.mode=="control" and p==g.current and ready("G121",p) and g.has(b.src,"共产") and not g.has(b.target,"共产"):
		var quota="synergy:G121:"+str(p)
		if not g.used.has(quota):
			g.used[quota]=true;enqueue({"kind":"s_tag","source":"G121","target":b.target,"player":p})
	if p==g.current and destroyed and g.has(b.src,"军队"):draw_reward("G122",p,"plot")
	if p==g.current and g.has(b.src,"名人"):draw_reward("G130",p,"group")
	var holder=g.owner("G114")
	if holder==g.current and ready("G114",holder):
		for entry in b.get("supporters",[]):
			if entry.owner==holder and g.owner(entry.id)==holder and g.nodes[entry.id].parent=="G114" and g.has(entry.id,"科学"):
				draw_reward("G114",holder,"plot");break

func queue_task(task: Dictionary) -> bool:
	g.wave.auto_trigger(task,"main");return true

func presentation_cards(a: Dictionary) -> Array:
	if a.type=="synergy":return [a.src]
	if a.type=="lift":return ["P45"]
	var out: Array=[]
	if a.type=="support":
		var b=g.battle;var p=g.owner(a.src)
		var d=g.support_detail(a.src,b)
		if d.reason.begins_with("远程中继"):out.append("G113")
		if d.reason.begins_with("维和护卫"):out.append("G123")
		if d.reason.begins_with("联合动员"):out.append("P48")
		if support_bonus(a.src,b)>0:out.append("G115")
	return out
