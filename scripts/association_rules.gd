extends RefCounted
## Recruitment, civic organizations and the associated resources. Match-owned state only.
var state: WeakRef
var g:
	get:return state.get_ref()
func _init(game):state=weakref(game)
func ready(id: String,p: int=-1) -> bool:return g.wave.enabled(id,p)
func unused(id: String) -> bool:return not g.used.has("association:"+id)
func mark(id: String) -> void:g.used["association:"+id]=true
func normal(b: Dictionary) -> bool:return not b.has("disaster")
func printed(id: String,traits: Array) -> bool:
	return traits.any(func(t):return t in g.card(id).align or t in g.card(id).tags)
func fee_options(p: int,exclude: String="") -> Array:
	return g.renewal.plot_costs(p).filter(func(id):return id!=exclude)
func pay_fee(p: int,id: String) -> void:
	if g.card(id).kind=="group":g.used[g.renewal.quota("G136")]=true
	g._discard(p,id)
func extra_tags(id: String,result: Array) -> Array:
	if not g.nodes.has(id):return result
	if g.nodes[id].get("privatized",false):result.erase("共产")
	if g.nodes[id].get("a_commie",false) and "共产" not in result:result.append("共产")
	if g.nodes[id].parent=="G176" and ready("G176") and "太空" in result and "绿色" not in result:result.append("绿色")
	return result
func adjust_stat(id: String,key: String,value: int) -> int:
	if not g.nodes.has(id):return value
	if key=="r" and g.nodes[id].parent=="G172" and ready("G172") and g.token("G172"):value+=2
	if id=="G180" and key in ["p","r"] and ready(id) and g.resources.field(g.owner(id)).size()==2:value+=2
	return value
func loyalty_bonus(id: String) -> int:
	return 4 if g.nodes.has(id) and not g.is_root(id) and g.has(id,"银行") and g.resources.ready("E26",g.owner(id)) and g.token(g.nodes[id].parent) else 0
func support_override(id: String,b: Dictionary,d: Dictionary) -> Dictionary:
	if id=="G186" and ready(id) and normal(b) and g.owner(id)==b.defender and g.has(b.target,"狂热"):
		d={"base":g.stat(id,"p"),"basis":"P","reason":"末日布道"}
	return d
func support_bonus(id: String,b: Dictionary) -> int:
	if not normal(b) or not ready(id):return 0
	if id=="G181":return mini(2,g.children(id).filter(func(k):return g.has(k,"共产")).size())
	if id=="G185" and g.hands[g.owner(id)].group.size()>=3:return 2
	return 0
func can_privatize(id: String) -> bool:
	if not g.nodes.has(id) or not g.has(id,"共产"):return false
	# Losing Communist status can remove the housing aura from this parent.
	if not g.renewal.housing_bonus(id):return true
	return g.children(id).size()<=mini(3,int(g.card(id).slots)+int("P19" in g.nodes[id].attached))
func ability_actions(src: String,p: int) -> Array:
	var out: Array=[]
	if not g.wave.available(src,p) or not unused(src) or (src!="G183" and not g.token(src)):return out
	var targets: Array=[]
	match src:
		"G171":targets=[""] if not g.decks.group.is_empty() else []
		"G179":targets=g.discards.group.filter(func(k):return printed(k,["太空"]))
		"G182":
			for target in g.groups(p)+g.groups(1-p):
				if g.has(target,"共产"):continue
				for fee in fee_options(p):out.append(g._a("ability","思想动员 → "+g.title(target),{"src":src,"target":target,"fee":fee}))
		"G183":
			for payer in g.children(src).filter(func(k):return g.has(k,"共产") and g.token(k)):
				for target in g.groups(p).filter(func(k):return k!=payer and g.has(k,"共产") and g.can_recharge(k)):
					out.append(g._a("ability","换岗 → "+g.title(target),{"src":src,"target":target,"payer":payer,"free":true}))
		"G184":targets=g.resources.field(p)
		"G187":targets=g.children(src)
		"G193":targets=g.groups(p).filter(can_privatize)
	for target in targets:out.append(g._a("ability",g.card(src).effect.get_slice("：",0)+(" → "+g.title(target) if target!="" else ""),{"src":src,"target":target}))
	return out
func plot_actions(id: String,p: int) -> Array:
	var out: Array=[];var actors=g.groups(p).filter(func(k):return g.token(k))
	match id:
		"P71":
			for actor in actors:
				for trait_name in alignments():
					for fee in fee_options(p,id):out.append(g._a("plot",g.title(id),{"id":id,"src":id,"target":"","payer":actor,"tag":trait_name,"fee":fee}))
		"P72":
			if g.can_enemy(p):
				for target in g.groups(1-p):
					if not g.has(g.nodes[target].parent,"银行"):continue
					for parent in g.field(1-p):
						if not g.can_parent(parent,target):continue
						for actor in actors.filter(func(k):return g.has(k,"银行") or g.has(k,"犯罪")):
							out.append(g._a("plot",g.title(id),{"id":id,"src":id,"target":target,"parent":parent,"payer":actor}))
		"P73":out.append(g._a("plot",g.title(id),{"id":id,"src":id,"target":""}))
		"P74":
			if not g.auto_used and not g.decks.group.is_empty():
				for actor in actors.filter(func(k):return g.has(k,"魔法") and g.can_parent(k)):
					out.append(g._a("plot",g.title(id),{"id":id,"src":id,"target":actor,"payer":actor}))
		"P75":
			if g.can_enemy(p) and not g.hands[1-p].group.is_empty():
				for actor in actors.filter(func(k):return g.has(k,"犯罪")):
					out.append(g._a("plot",g.title(id),{"id":id,"src":id,"target":"","payer":actor}))
	return out
func alignments() -> Array:return ["政府","企业","自由","保守","和平","暴力","正统","怪异","狂热","犯罪"]
func all_traits() -> Array:
	var out=alignments()
	for id in CardDB.ids("group"):
		for tag in g.card(id).tags:
			if tag not in out:out.append(tag)
	return out
func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="main" and g.current==p:
		for a in out.duplicate():
			if a.type=="attack" and a.src=="G192" and a.mode=="control" and ready("G192",p):
				for fee in fee_options(p,a.target):
					var v=a.duplicate();v.self_lock=true;v.fee=fee;v.label+=" · 财务迷雾";out.append(v)
		if not g.deploy_used and g.wave.available("G173",p) and g.token("G173"):
			var replacements=g.resources.field(p) if g.resources.field(p).size()==2 else [""]
			for id in g.hands[p].resource:
				if not g.has(id,"设施"):continue
				for replacement in replacements:out.append(g._a("deploy","项目融资 · "+g.title(id),{"id":id,"src":id,"replace":replacement,"funded":true}))
		for src in g.resources.field(p):
			if not g.resources.ready(src,p):continue
			if src=="E25" and not g.decks.group.is_empty():out.append(g._a("resource",g.title(src),{"src":src,"target":""}))
			if src=="E27" and g.token(src):
				for target in g.discards.group.filter(func(k):return printed(k,["共产"])):
					for fee in fee_options(p):out.append(g._a("resource",g.title(src),{"src":src,"target":target,"fee":fee}))
			if src=="E29" and not g.decks.group.is_empty():
				for trait_name in all_traits():out.append(g._a("resource",g.title(src),{"src":src,"target":"","tag":trait_name}))
			if src=="E30":
				for target in g.groups(p).filter(func(k):return (g.has(k,"魔法") or g.has(k,"太空")) and g.can_parent(g.root(p),k)):
					out.append(g._a("resource",g.title(src),{"src":src,"target":target,"parent":g.root(p)}))
	if g.phase=="choice" and g.choice.get("player",-1)==p and g.choice.get("kind","")=="a_tug":
		out=[]
		for parent in g.choice.options:out.append(g._a("choose","移至 · "+g.title(parent),{"id":parent,"src":g.choice.source}))
		out.append(g._a("choose","跳过",{"id":""}))
	if g.phase=="battle" and g.battle.get("responder",-1)==p:
		var b=g.battle
		out=out.filter(func(a):return a.type!="support" or not b.get("supporters",[]).any(func(k):return k.id==a.src))
		if normal(b) and ready("G189",p) and unused("G189") and g.token("G189") and b.defender==p and g.nodes[b.target].parent=="G189":
			for a in out.duplicate():
				if a.type=="support" and a.src=="G189":
					var v=a.duplicate();v.sword_guard=true;v.label+=" · 护山剑阵免行动";out.append(v)
		if normal(b) and b.target=="G194" and b.defender==p and g.wave.available("G194",p) and g.token("G194") and not b.get("responded",false):
			out.append(g._a("vanish","大变活人 · 整支回手，取消攻击",{"src":"G194","target":"G194"}))
	return out
func before_attack(p: int,a: Dictionary) -> void:
	if a.get("self_lock",false):
		pay_fee(p,a.fee);g.battle.self_lock=true
		g._battle_record("ability",p,"G192",a.target,"财务迷雾 · 目标不能自卫")
func handle(p: int,a: Dictionary) -> bool:
	if a.type=="choose" and g.choice.get("kind","").begins_with("a_"):choose(a.id);return true
	if a.type=="vanish":vanish(p);return true
	if a.type=="deploy" and a.get("funded",false):
		g.spend("G173");var command=a.duplicate();command.free=true;g.resources.deploy(p,command);g._after_effect();return true
	if a.type=="resource" and a.src.begins_with("E") and int(a.src.substr(1))>=24:resource(p,a);return true
	if a.type!="ability" or not a.src.begins_with("G") or int(a.src.substr(1))<171:return false
	var src=a.src;var target=a.get("target","")
	mark(src)
	if src=="G183":g.spend(a.payer)
	else:g.spend(src)
	match src:
		"G171":search(p,src,4,["犯罪","银行"],false,true)
		"G179":recover(p,target)
		"G182":pay_fee(p,a.fee);g.nodes[target].a_commie=true
		"G183":g.nodes[target].token=1;g.recharged[target]=true
		"G184":g.resources.remove(target);reward(src,p,["group","group","plot"])
		"G187":g._return_subtree(target);reward(src,p,["group","group"])
		"G193":g.nodes[target].erase("a_commie");g.nodes[target].privatized=true
	g._log(g.title(src)+" · "+g.card(src).effect.get_slice("：",0),"ability",{"id":src,"target":target})
	g._after_effect();return true
func resource(p: int,a: Dictionary) -> void:
	match a.src:
		"E25":g.resources.remove(a.src);search(p,a.src,3,["太空"],true)
		"E27":g.spend(a.src);pay_fee(p,a.fee);recover(p,a.target)
		"E29":g.resources.remove(a.src);search(p,a.src,10,[a.tag],false,false,"shuffle",2)
		"E30":
			g.resources.remove(a.src);g.nodes[a.target].parent=g.root(p)
			g.wave.defer({"kind":"a_random","source":a.src,"player":p,"traits":["魔法","太空"]})
	g._after_effect()
func recover(p: int,id: String) -> void:
	g.discards.group.erase(id);g.hands[p].group.append(id);g._flow(id,"discard","hand",p)
func resolve_plot(a: Dictionary) -> bool:
	if int(a.id.substr(1))<71:return false
	var p=a.player
	match a.id:
		"P71":search(p,a.id,3,[a.tag],true)
		"P72":g.nodes[a.target].parent=a.parent
		"P73":g.wave.set_world(a.id)
		"P74":search(p,a.id,5,[],false,true,"shuffle",1,a.target)
		"P75":g._set_choice(p,"暗中挖角 · 选择1张团体",g.hands[1-p].group,"a_poach",{"source":a.id,"opponent":1-p})
	if a.id!="P73":g._spent_plot(a.id)
	g.wave.plot_rewards(p,a.id,a);g._after_effect();return true
func search(p: int,source: String,n: int,traits: Array,random_pool: bool=false,public: bool=false,rest: String="shuffle",amount: int=1,parent: String="") -> void:
	var peek: Array=[]
	if random_pool:
		var pool=g.decks.group.filter(func(id):return printed(id,traits));g._shuffle(pool)
		peek=pool.slice(0,n)
		for id in peek:g.decks.group.erase(id);g._flow(id,"deck","choice",p)
	else:
		# A search sees only the current deck, never silently reshuffles its discard.
		for i in mini(n,g.decks.group.size()):
			var id=g.decks.group.pop_front();peek.append(id);g._flow(id,"deck","choice",p)
	var options=peek.filter(func(id):return (traits.is_empty() or printed(id,traits)) and (parent=="" or g.card(id).p<=3))
	var data={"source":source,"peek":peek,"rest":rest,"remaining":amount,"parent":parent,"public":public}
	if public:
		for event in g.motion_events:
			if event.to=="choice" and event.id in peek:event.public=true
	if source=="E24":
		g._set_choice(p,"招募情报站 · 可弃1张团体换取候选",g.hands[p].group,"a_intel_fee",data,true)
	else:
		g._set_choice(p,g.title(source)+" · 选择团体",options,"a_search",data,true)
func finish_search(c: Dictionary) -> void:
	for id in c.peek:g.decks.group.append(id);g._flow(id,"choice","deck",c.player)
	if c.rest=="shuffle":g._shuffle(g.decks.group)
func choose(id: String) -> void:
	var c=g.choice.duplicate(true);var p=c.player;g.choice={};g.phase="main"
	match c.kind:
		"a_search":
			if id!="":
				c.peek.erase(id);c.options.erase(id)
				if c.parent!="":
					g.auto_used=true;var before=g.field(p);g._enter(id,p,c.parent);g.captured[id]=true;g._entry_rewards(id,p,c.parent,before);auto_reward(id,p,c.parent)
					g._flow(id,"choice","board",p)
				else:
					g.hands[p].group.append(id);g._flow(id,"choice","hand",p)
					if c.public and id not in g.exposed:g.exposed.append(id)
				c.remaining-=1
				if c.remaining>0 and not c.options.is_empty():
					g._set_choice(p,c.label,c.options,c.kind,c,true);return
			finish_search(c)
		"a_intel_fee":
			if id=="":finish_search(c)
			else:
				g._discard(p,id);g._set_choice(p,"招募情报站 · 选择1张团体",c.peek,"a_search",c,false);return
		"a_fund_fee":
			if id!="":g._discard(p,id);reward(c.source,p,["group","group"])
		"a_soul_fee":
			if id!="" and c.target in g.graves[p]:
				pay_fee(p,id);mark(c.source);g.graves[p].erase(c.target);g.hands[p].group.append(c.target);g._flow(c.target,"grave","hand",p)
		"a_poach":
			g.hands[c.opponent].group.erase(id);g.hands[p].group.append(id);g.exposed.erase(id);g.locked.erase(id)
			g._flow(id,"hand","hand",p);g.motion_events.back().from_player=c.opponent
		"a_tug":
			if id!="":mark(c.source);g.nodes[c.source].parent=id
	g._after_effect()
func held_cards(c: Dictionary) -> Array:
	if c.get("kind","")=="x_overflow":return held_cards(c.saved_choice)
	return c.get("peek",[]) if c.get("kind","") in ["a_search","a_intel_fee"] else []
func reward(source: String,p: int,decks: Array) -> void:
	g.wave.defer({"kind":"a_draw","source":source,"player":p,"decks":decks})
func entry_reward(id: String,p: int,before: Array) -> void:
	if p!=g.current:return
	if id!="G174" and "G174" in before and ready("G174",p) and unused("G174") and g.has(id,"共产"):
		mark("G174");g.wave.defer({"kind":"a_fund","source":"G174","player":p})
	if "G191" in before and ready("G191",p) and unused("G191") and g.has(id,"狂热") and not g.has(id,"绿色"):
		mark("G191");g.wave.defer({"kind":"a_green","source":"G191","player":p,"target":id})
func auto_reward(id: String,p: int,parent: String) -> void:
	if parent=="G175" and ready(parent,p) and g.has(id,"太空"):reward(parent,p,["resource"])
func draw_finished(p: int) -> void:
	if g.world=="P73" and g.groups(p).filter(func(id):return not g.wave.devastated(id) and (g.has(id,"保守") or g.has(id,"狂热"))).size()>=3:reward("P73",p,["group"])
	if g.resources.ready("E24",p) and not g.decks.group.is_empty():g.wave.defer({"kind":"a_intel","source":"E24","player":p})
func end_turn() -> void:
	var p=g.current
	if ready("G188",p) and g.token("G188") and not g.decks.group.is_empty():g.wave.defer({"kind":"a_policy","source":"G188","player":p})
	if ready("G195",p) and g.children("G195").any(func(k):return g.has(k,"银行") and g.token(k)):reward("G195",p,["group","plot"])
func movement_snapshot() -> Dictionary:
	var out={}
	for id in g.nodes:
		if g.card(id).kind=="group":out[id]={"parent":g.nodes[id].parent,"owner":g.owner(id)}
	return out
func moved(before: Dictionary) -> void:
	var p=g.current
	if not g.resources.ready("E28",p) or not unused("E28"):return
	for id in before:
		if g.nodes.has(id) and before[id].owner==p and g.owner(id)==p and before[id].parent!=g.nodes[id].parent and g.has(g.nodes[id].parent,"保守"):
			mark("E28");g.wave.defer({"kind":"a_random","source":"E28","player":p,"traits":["保守"]});return
func ark_source(b: Dictionary) -> String:
	if not normal(b) and not g.wave.devastated(b.target) and g.has(b.target,"太空") and g.has(b.target,"地点") and ready("G178",b.defender) and unused("G178"):return "G178"
	return ""
func prevent_destroy(b: Dictionary) -> bool:
	var source=ark_source(b)
	if source=="" or b.get("rescue",false):return false
	mark(source);g.wave.defer({"kind":"a_notice","source":source,"player":b.defender});return true
func battle_finished(b: Dictionary,destroyed: bool) -> void:
	if not normal(b):return
	for member in b.get("supporters",[]):
		if member.id=="G177" and g.owner(member.id)==member.owner and ready(member.id) and unused(member.id):
			g.wave.defer({"kind":"a_tug","source":member.id,"player":member.owner})
	if destroyed and b.src=="G190" and ready("G190",b.attacker) and unused("G190"):
		g.wave.defer({"kind":"a_soul","source":"G190","player":b.attacker,"target":b.target})
func trigger(task: Dictionary) -> void:
	var p=task.player;var src=task.source
	match task.kind:
		"a_draw":
			for deck in task.decks:g._draw(p,deck)
		"a_fund":
			if not g.hands[p].group.is_empty():g._set_choice(p,"互助征集 · 可弃1张团体，抽2张团体",g.hands[p].group,"a_fund_fee",{"source":src},true)
		"a_green":
			if g.nodes.has(task.target):
				var tags=g.nodes[task.target].get_or_add("extra_tags",[])
				if "绿色" not in tags:tags.append("绿色")
		"a_policy":search(p,src,5,["保守"],false,false,"bottom")
		"a_intel":search(p,src,3,[],false,true,"bottom")
		"a_random":
			var pool=g.decks.group.filter(func(k):return printed(k,task.traits))
			if not pool.is_empty():
				var id=pool[g.rng.randi_range(0,pool.size()-1)];g.decks.group.erase(id);g.hands[p].group.append(id);g._flow(id,"deck","hand",p)
			g._shuffle(g.decks.group)
		"a_tug":
			if g.owner(src)==p and ready(src) and unused(src):
				var options=g.field(p).filter(func(k):return g.can_parent(k,src))
				if not options.is_empty():g._set_choice(p,"轨道修正 · 可选择新上级",options,"a_tug",{"source":src},true)
		"a_soul":
			if task.target in g.graves[p] and not fee_options(p).is_empty():g._set_choice(p,"收魂 · 可弃1张阴谋，取得摧毁目标",fee_options(p),"a_soul_fee",{"source":src,"target":task.target},true)
	if task.kind.begins_with("a_"):g._log(g.title(src)+" · "+g.card(src).effect.get_slice("：",0),"ability",{"id":src})
func vanish(p: int) -> void:
	var b=g.battle.duplicate(true);var values=g.battle_values()
	g._battle_record("ability",p,"G194","G194","大变活人 · 取消攻击");b.entries=g.battle.entries.duplicate(true)
	g.spend("G194");g._return_subtree("G194")
	for id in b.spent:g.discards.plot.push_front(id)
	b.merge({"values":values,"dice":[],"success":false,"cancelled":true,"rescued":false,"destroyed":false,"devastated":false,"guarded":false},true)
	g.last_battle=b;g.battle={};g.phase="main";g._after_effect()
func reader(id: String) -> Array:
	if not g.nodes.has(id):return []
	var out: Array=[]
	if g.nodes[id].get("a_commie",false):out.append("临时共产 · 回合结束消失")
	if g.nodes[id].get("privatized",false):out.append("私有化 · 移除政府与共产，获得企业")
	if g.nodes[id].parent=="G176" and ready("G176") and g.has(id,"太空"):out.append("生态穹顶 · 获得绿色")
	if loyalty_bonus(id)>0:out.append("双重授权 · 忠诚防御+4")
	if g.nodes[id].parent=="G172" and ready("G172") and g.token("G172"):out.append("稳健储蓄 · R+2")
	if id=="G180" and ready(id) and g.resources.field(g.owner(id)).size()==2:out.append("保障供应 · P+2、R+2")
	if not unused(id):out.append("本回合能力次数已用")
	return out
func presentation_cards(a: Dictionary) -> Array:
	var out: Array=[]
	if a.type=="deploy" and a.get("funded",false):out.append("G173")
	if a.get("self_lock",false):out.append("G192")
	if a.get("sword_guard",false) or a.type=="vanish":out.append(a.src)
	if a.type=="support" and a.src in ["G181","G185","G186"]:
		if support_bonus(a.src,g.battle)>0 or (a.src=="G186" and normal(g.battle) and g.owner(a.src)==g.battle.defender and g.has(g.battle.target,"狂热")):out.append(a.src)
	if a.type=="choose" and g.choice.get("kind","").begins_with("a_") and a.id!="":out.append(g.choice.get("source",""))
	return out
