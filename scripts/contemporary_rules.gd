extends RefCounted
## Contemporary cards. Match state stays on GameState; rehearsals bind a fresh module.
var state: WeakRef
var g:
	get:return state.get_ref()
func _init(game):state=weakref(game)
func ready(id: String,p: int=-1) -> bool:return g.wave.enabled(id,p)
func normal(b: Dictionary) -> bool:return not b.has("disaster")
func limit_bonus(p: int) -> int:
	return int(g.world=="P63")+int(g.factions[p]=="I12")
func tenant_alignments(id: String) -> Array:
	var result=[]
	for child in g.children(id):
		for alignment in g.alignments(child):
			if alignment not in result:result.append(alignment)
	return result
func seal_targets(target: String) -> Array:
	return [target]+g.children(target)
func adjust_stat(id: String,key: String,value: int) -> int:
	if not g.nodes.has(id):return value
	if key=="p":
		value+=int(g.nodes[id].get("battery_power",0))
		if g.nodes[id].parent=="G156" and ready("G156") and g.has(id,"名人"):value+=1
		if id=="G169" and ready(id) and tenant_alignments(id).size()>=5:value+=3
	if key in ["gp","r"] and g.world=="P62" and g.has(id,"保守"):value+=1
	if key=="r" and g.nodes[id].parent=="G170" and ready("G170") and g.has(id,"魔法"):value+=3
	if key=="gp":
		if id=="G050" and ready(id):value+=mini(2,g.children(id).filter(func(k):return g.has(k,"怪异")).size())
		value=0 if g.nodes[id].get("pr_crisis",false) or "P45" in g.nodes[id].attached else mini(value,g.stat(id,"p",true))
	return value
func support_override(id: String,b: Dictionary,d: Dictionary) -> Dictionary:
	var p=g.owner(id)
	if g.nodes[id].get("no_support",false):return {"base":0,"basis":"—","reason":"符箓封印 · 不能支援"}
	if g.nodes[id].parent=="G153" and ready("G153",p) and g.has(id,"共产"):d={"base":g.stat(id,"p"),"basis":"P","reason":"集中统筹"}
	if normal(b) and p==b.attacker and b.mode=="destroy" and g.factions[p]=="I10" and g.has(id,"暴力"):d={"base":g.stat(id,"p"),"basis":"P","reason":"刺客协会 · 致命协作"}
	if normal(b) and p==b.attacker and ready("G163",b.defender) and g.has(b.target,"绿色") and b.get("support_counts",[0,0])[p]==0:d={"base":g.stat(id,"gp"),"basis":"GP","reason":"拖拉机路障 · 首次进攻支援仅GP"}
	return d
func support_bonus(id: String,b: Dictionary) -> int:
	var value=int(g.has(id,"犯罪") and ready("E18",g.owner(id)))
	if id=="G161" and ready(id) and b.get("stake",false):value+=2
	return value
func self_bonus(id: String) -> int:
	return 3 if g.nodes[id].parent=="G158" and ready("G158") and g.has(id,"共产") else 0
func values(b: Dictionary,v: Dictionary) -> Dictionary:
	if normal(b) and b.src=="G057" and ready("G057") and b.mode=="control" and g.has(b.target,"暴力"):v.ability+=2;v.strength+=2
	if normal(b) and b.src=="G166" and ready("G166") and b.mode=="destroy":
		var amount=mini(3,v.position);v.position-=amount;v.strength+=amount
	if normal(b) and b.get("silent_reaction",false) and v.alignment>4:v.strength-=v.alignment-4;v.alignment=4
	if b.get("ignore_loyalty",false):v.strength+=v.loyalty;v.loyalty=0
	return v
func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="choice" and g.choice.get("kind","")=="n_inside" and g.choice.player==p:
		return [g._a("choose","放到阴谋堆顶",{"id":"top"}),g._a("choose","放到阴谋堆底",{"id":"bottom"})]
	if g.phase=="main" and g.current==p:
		if g.factions[p]=="I09":out.append_array(ability_actions(g.root(p),p))
		if ready("E17",p) and g.token("E17"):
			for target in g.groups(p):
				if g.wave.devastated(target) and g.has(target,"地点") and not g.has(target,"巨大"):out.append(g._a("resource","移动医疗站 · 重建并恢复行动 → "+g.title(target),{"src":"E17","target":target}))
		if ready("E22",p) and g.token("E22"):
			for target in g.hands[p].resource:out.append(g._a("resource","炼金置换 · 洗回1资源，抽2阴谋",{"src":"E22","target":target}))
	elif g.phase=="battle" and g.battle.responder==p:
		var b=g.battle
		if normal(b) and p==b.attacker and g.has(b.src,"魔法") and ready("E19",p):out.append(g._a("resource","雷击桃木剑 · 攻击强度+8 · 报废",{"src":"E19","target":b.target}))
		if normal(b) and p==b.attacker and b.mode=="control" and ready("E23",p) and g.nodes.has(b.target) and g.loyalty_defense(b.target)>0 and not b.get("ignore_loyalty",false):out.append(g._a("resource","王权之杖 · 忽略忠诚 · 报废",{"src":"E23","target":b.target}))
		var revised: Array=[]
		for original in out:
			var a=original.duplicate(true)
			if a.type=="self_defend":
				a.power+=self_bonus(a.src)
				if g.factions[p]=="I11" and g.has(a.src,"绿色"):a.nature=true;a.label="生命护持 · 免标记自卫 +%d"%a.power
				a.label="自卫 · %s (+%d)"%[g.title(a.src),a.power] if not a.get("nature",false) else a.label
				if b.get("nature_self",false):continue
			revised.append(a)
		# Build the paid mode from the legal support rules, including a zero-GP base.
		if ready("G161",p) and g.token("G161") and "G161" not in b.paid and "G161" not in [b.src,b.target]:
			var context=b.duplicate(true);context.stake=true
			var d=g.support_detail("G161",context)
			if d.power>0:
				for fee in g.renewal.plot_costs(p):
					var tolls=g.hands[p].group if normal(b) and p==b.attacker and ready("G100",b.defender) and g.has(b.target,"沿海") and b.get("support_counts",[0,0])[p]==1 else [""]
					for toll in tolls:
						if fee==toll:continue
						var v=g._a("support","庄家筹码 · +%d · 弃%s"%[d.power,g.title(fee)],{"src":"G161","stake":true,"plot_fee":fee,"power":d.power,"basis":d.basis})
						if toll!="":v.group_fee=toll;v.label+=" · 通行费弃"+g.title(toll)
						revised.append(v)
		out=revised
	return out
func ability_actions(src: String,p: int) -> Array:
	var out: Array=[]
	if not g.wave.available(src,p) or (src!="G159" and not g.token(src)) or g.used.has(src):return out
	var targets: Array=[]
	if g.is_root(src) and g.factions[p]=="I09":
		if g.resources.deck_available("group"):out.append(g._a("ability","第三类接触 · 查看团体堆顶5张",{"src":src,"target":""}))
		return out
	match src:
		"G138":
			if g.resources.can_draw(p) and g.resources.deck_available("resource"):targets=g.renewal.plot_costs(p).duplicate()
		"G151","G168":targets=g.hands[p].resource.duplicate()
		"G155":targets=g.groups(p).filter(func(k):return g.has(k,"保守") and not g.has(k,"狂热"))
		"G157":
			if not g.decks.plot.is_empty():targets=[""]
		"G159":
			for target in g.groups(p).filter(func(k):return g.has(k,"军队") and g.can_recharge(k)):
					for other in g.resources.field(p).filter(func(k):return g.has(k,"装置")):out.append(g._a("ability","武装交易 → "+g.title(target),{"src":src,"target":target,"other":other,"free":true}))
		"G162":
			if g.resources.can_draw(p):
				for target in g.discards.resource.filter(func(k):return g.has(k,"装置")):
					for fee in g.hands[p].group:out.append(g._a("ability","旧物新生 → "+g.title(target),{"src":src,"target":target,"fee":fee}))
		"G164":targets=g.groups(p).filter(func(k):return g.nodes[k].get("silenced",false))
	for target in targets:out.append(g._a("ability",g.card(src).effect.get_slice("：",0).replace("（主动）","")+(" → "+g.title(target) if target!="" else ""),{"src":src,"target":target}))
	return out
func plot_actions(id: String,p: int) -> Array:
	var out: Array=[];var targets: Array=[]
	match id:
		"P62","P63":targets=[""]
		"P64":return g.wave.main_plots(id,p)
		"P65":
			if g.resources.can_draw(p) and g.resources.deck_available("resource"):targets=g.resources.field(p).filter(func(k):return g.has(k,"装置"))
		"P66":
			if not g.deploy_used:
				for target in g.hands[p].resource:
					for old in (g.resources.field(p) if g.resources.field(p).size()>=2 else [""]):
						for payer in g.groups(p).filter(func(k):return g.token(k)):out.append(g._a("plot","紧急空运 → "+g.title(target),{"id":id,"src":id,"target":target,"replace":old,"payer":payer}))
		"P67":
			if g.can_enemy(p):
				for target in g.groups(1-p).filter(func(k):return seal_targets(k).any(func(child):return not g.nodes[child].get("no_support",false))):
					for payer in g.groups(p).filter(func(k):return g.token(k) and g.has(k,"魔法")):out.append(g._a("plot","符箓封印 → "+g.title(target),{"id":id,"src":id,"target":target,"payer":payer}))
		"P68":targets=g.groups(p).filter(func(k):return g.has(k,"地点") and g.has(k,"绿色") and g.wave.devastated(k))
		"P70":
			if g.can_enemy(p) and not g.hands[1-p].plot.is_empty():targets=[""]
	for target in targets:out.append(g._a("plot",g.title(id)+(" → "+g.title(target) if target!="" else ""),{"id":id,"src":id,"target":target}))
	return out
func media_count(p: int,b: Dictionary) -> int:return b.paid.filter(func(k):return g.owner(k)==p and g.has(k,"媒体")).size()
func combat_plots(id: String,p: int,b: Dictionary) -> Array:
	if id!="P69" or not normal(b) or media_count(1-p,b)==0:return []
	return [g._a("plot","热搜反噬 · 对手-%d"%mini(6,2*media_count(1-p,b)),{"id":id,"src":id,"target":"","backlash":mini(6,2*media_count(1-p,b))})]
func peek(p: int,n: int,kind: String,public: bool=false):
	var cards=g._take(p,"resource",n)
	if not cards.is_empty():g._set_choice(p,"选择1张资源加入手牌",cards,"n_probe",{"peek":cards,"return_kind":kind,"public":public})
func handle(p: int,a: Dictionary) -> bool:
	if a.type=="ability" and g.is_root(a.src) and g.factions[p]=="I09":
		g.spend(a.src);g.used[a.src]=true
		var cards=g._take(p,"group",5)
		g._set_choice(p,"第三类接触 · 可取1张太空团体",cards.filter(func(k):return g.has(k,"太空")),"n_contact",{"peek":cards},true)
		g._log(g._who(p)+" · 第三类接触","ability",{"id":a.src,"player":p});g._after_effect();return true
	if a.type=="ability" and a.src in ["G138","G151","G155","G157","G159","G162","G164","G168"]:
		if a.src!="G159":g.spend(a.src)
		g.used[a.src]=true
		match a.src:
			"G138":
				if a.target.begins_with("G"):g.used[g.renewal.quota("G136")]=true
				g._discard(p,a.target)
				var peeked=g._take(p,"resource",3)
				g._set_choice(p,"秘宝走私 · 可取1张秘宝",peeked.filter(func(k):return g.has(k,"秘宝")),"n_relic",{"peek":peeked},true)
			"G151":
				g.hands[p].resource.erase(a.target);g.decks.resource.append(a.target);g._flow(a.target,"hand","deck",p);g._shuffle(g.decks.resource);g._draw(p,"resource");g._draw(p,"plot")
			"G155":g.nodes[a.target].rally=true
			"G157":
				var cards=[]
				for i in mini(3,g.decks.plot.size()):cards.append(g.decks.plot.pop_front())
				g._set_choice(p,"占卜 · 查看阴谋堆顶",[],"n_divine",{"peek":cards},true)
			"G159":g.resources.remove(a.other);g.nodes[a.target].token=1;g.recharged[a.target]=true
			"G162":g._discard(p,a.fee);g.discards.resource.erase(a.target);g.hands[p].resource.append(a.target);g._flow(a.target,"discard","hand",p)
			"G164":g.nodes[a.target].silenced=false
			"G168":g._discard(p,a.target);g._draw(p,"group");g._draw(p,"plot")
		g._log(g._who(p)+" · "+a.label,"ability",{"id":a.src,"target":a.get("target",""),"player":p});g._after_effect();return true
	if a.type=="resource" and a.src in ["E17","E19","E22","E23"]:
		if a.src=="E17":g.spend(a.src);g.wave.rebuild(a.target,true)
		elif a.src=="E22":
			g.spend(a.src);g.hands[p].resource.erase(a.target);g.decks.resource.append(a.target);g._flow(a.target,"hand","deck",p);g._shuffle(g.decks.resource);g._draw(p,"plot");g._draw(p,"plot")
		elif a.src=="E23":g.resources.remove(a.src);g.battle.ignore_loyalty=true
		else:g.resources.remove(a.src);g.battle.bonus_a+=8
		g._log(g._who(p)+" · "+a.label,"resource",{"id":a.src,"target":a.target,"player":p})
		if not g.battle.is_empty():g._battle_record("resource",p,a.src,a.target,a.label,"已生效");g._response_changed(p)
		else:g._after_effect()
		return true
	if a.type=="self_defend" and a.get("nature",false):
		g.battle.nature_self=true;g.battle.self=a.power;g._battle_record("self_defend",p,a.src,a.src,a.label);g._response_changed(p);return true
	if a.type=="choose" and g.choice.get("kind","").begins_with("n_"):
		var c=g.choice.duplicate(true);g.choice={};g.phase="main"
		match c.kind:
			"n_contact":
				if a.id!="":g.hands[p].group.append(a.id);g._flow(a.id,"choice","hand",p)
				for id in c.peek:
					if id!=a.id:g.decks.group.append(id);g._flow(id,"choice","deck",p)
				g._shuffle(g.decks.group)
			"n_inside":
				var victim=1-p;var id=c.revealed_card
				g.hands[victim].plot.erase(id);g.exposed.erase(id);g.locked.erase(id)
				if a.id=="top":g.decks.plot.push_front(id)
				else:g.decks.plot.append(id)
				g._flow(id,"hand","deck",victim)
				g._log(g._who(p)+" · 组织渗透 · "+("放到阴谋堆顶" if a.id=="top" else "放到阴谋堆底"),"ability",{"id":"P70","player":p})
			"n_divine":
				for i in range(c.peek.size()-1,-1,-1):g.decks.plot.push_front(c.peek[i])
			"n_probe":
				if a.id!="" and g.resources.can_draw(p):g.hands[p].resource.append(a.id);g._flow(a.id,"choice","hand",p)
				for id in c.peek:
					if id!=a.id:g.decks.resource.append(id)
				if c.return_kind=="shuffle":g._shuffle(g.decks.resource)
			"n_relic":
				if a.id!="" and g.resources.can_draw(p):g.hands[p].resource.append(a.id);g._flow(a.id,"choice","hand",p)
				for id in c.peek:
					if id!=a.id:g.decks.resource.append(id)
				g._shuffle(g.decks.resource)
			"n_discard":g._discard(p,a.id)
			"n_recharge":
				if a.id!="" and g.can_recharge(a.id):g.nodes[a.id].token=1;g.recharged[a.id]=true
		g._after_effect();return true
	return false
func resolve_plot(a: Dictionary) -> bool:
	if a.id=="P64":g.wave.start_disaster(a);return true
	if a.id not in ["P62","P63","P65","P66","P67","P68","P69","P70"]:return false
	var p=a.player
	match a.id:
		"P62","P63":g.wave.set_world(a.id)
		"P65":g.resources.remove(a.target);peek(p,3,"shuffle")
		"P66":
			var deploy={"type":"deploy","id":a.target,"src":a.target,"replace":a.get("replace",""),"free":true};g.resources.deploy(p,deploy)
		"P67":
			for target in seal_targets(a.target):g.nodes[target].no_support=true
		"P68":g.wave.rebuild(a.target);g.nodes[a.target].prepared=true
		"P69":g.battle["bonus_d" if p==g.battle.attacker else "bonus_a"]-=a.backlash
		"P70":
			var hand=g.hands[1-p].plot
			if not hand.is_empty():g._set_choice(p,"组织渗透 · 选择放回位置",[],"n_inside",{"revealed_card":hand[g.rng.randi_range(0,hand.size()-1)]})
	if a.id not in ["P62","P63"]:g._spent_plot(a.id)
	g.wave.plot_rewards(p,a.id,a)
	if not g.battle.is_empty():g._response_changed(p)
	else:g._after_effect()
	return true
func draw_reward(src: String,p: int,deck: String,quota: String):
	if g.used.has(quota):return
	g.used[quota]=true;g.wave.defer({"kind":"draw","source":src,"player":p,"deck":deck,"amount":1,"message":g.title(src)+" · 抽1张"+{"group":"团体","plot":"阴谋","resource":"资源"}[deck]})
func deployed(p: int,id: String):
	if p!=g.current:return
	if g.has(id,"装置") and ready("G165",p):draw_reward("G165",p,"group","open_blueprints")
	if g.has(id,"设施") and g.world=="P63":draw_reward("P63",p,"resource","circular_economy:%d"%p)
	if g.factions[p]=="I12" and not g.used.has("collective_stores"):
		g.used.collective_stores=true;g.wave.defer({"kind":"n_recharge","source":g.root(p),"player":p})
func entry_reward(id: String,p: int):
	if g.current==p and g.has(id,"绿色") and g.resources.ready("E20",p):draw_reward("E20",p,"group","community_solar")
func battle_finished(b: Dictionary,success: bool,destroyed: bool):
	var p=b.attacker
	if not normal(b) or not success or b.mode!="control":return
	if b.src=="G167" and b.get("hand_target",false) and ready("G167",p) and not g.used.has("recruitment_spiral"):
		g.used.recruitment_spiral=true;g.wave.defer({"kind":"battle_recharge","source":"G167","player":p})
	if b.src=="G160" and not b.get("hand_target",false) and ready("G160",p) and g.has(b.target,"计算机") and not g.hands[1-p].resource.is_empty():g.wave.defer({"kind":"n_discard","source":"G160","player":1-p})
func trigger(task: Dictionary):
	var p=task.player
	if task.kind=="n_discard" and not g.hands[p].resource.is_empty():g._set_choice(p,"数字勒索 · 弃1张资源",g.hands[p].resource,"n_discard")
	if task.kind=="n_recharge":
		var options=g.groups(p).filter(func(k):return g.has(k,"共产") and g.can_recharge(k))
		if not options.is_empty():g._set_choice(p,"共同仓储 · 可恢复1个共产团体",options,"n_recharge",{},true)
func reader(id: String) -> Array:
	var out: Array=[]
	if g.nodes[id].get("pr_crisis",false):out.append("公关危机 · 本回合GP=0。")
	if g.nodes[id].get("battery_power",0)>0:out.append("应急电池 · 本回合P+4。")
	if id=="G050" and ready(id):out.append("信众合唱 · GP+%d。"%mini(2,g.children(id).filter(func(k):return g.has(k,"怪异")).size()))
	if g.nodes[id].parent=="G156" and ready("G156") and g.has(id,"名人"):out.append("形象塑造 · 来自高档沙龙的P+1。")
	if id=="G169":
		out.append("多元合租 · 直属下属阵营 %d / 5"%tenant_alignments(id).size())
		if ready(id) and tenant_alignments(id).size()>=5:out.append("多元合租 · P+3已生效。")
	if g.nodes[id].get("no_support",false):out.append("符箓封印 · 本回合不能支援，仍可自卫。")
	if g.nodes[id].get("rally",false):out.append("红帽集会 · 本回合增加狂热。")
	if g.nodes[id].parent=="G170" and ready("G170") and g.has(id,"魔法"):out.append("符箓庇护 · R+3。")
	if g.nodes[id].parent=="G153" and ready("G153") and g.has(id,"共产"):out.append("集中统筹 · 支援可用P。")
	if id in ["G165","G167","E20","R0","R1"]:
		var quota={"G165":"open_blueprints","G167":"recruitment_spiral","E20":"community_solar"}.get(id,"")
		if id.begins_with("R"):
			quota="collective_stores" if g.card(id).id=="I12" else ""
			if g.card(id).id=="I09":quota=id
		if quota!="" and g.used.has(quota):out.append("本回合触发次数已用。")
	return out
