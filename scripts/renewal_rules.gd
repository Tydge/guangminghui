extends RefCounted
## Direct-parent/child auras and small tactical choices; all state lives on the match.
var state: WeakRef
var g:
	get:return state.get_ref()
func _init(game) -> void:state=weakref(game)
func ready(id: String,p: int=-1) -> bool:return g.wave.enabled(id,p)
func normal(b: Dictionary) -> bool:return not b.has("disaster")
func quota(id: String) -> String:return "renewal:"+id
func unused(id: String) -> bool:return not g.used.has(quota(id))

func adjust_stat(id: String,key: String,value: int) -> int:
	if not g.nodes.has(id):return value
	var parent=g.nodes[id].parent
	if key=="p":
		value+=g.nodes[id].get("learned",0)
		if parent=="G133" and ready(parent) and g.has(id,"共产"):value+=2
	if key=="slots" and housing_bonus(id):value=mini(3,value+1)
	return value

func housing_bonus(id: String) -> bool:
	return g.nodes.has(id) and ready("G134") and g.nodes.G134.parent==id and g.has(id,"共产")

func can_swap(a: String,b: String) -> bool:
	# Swapping replaces the child, unlike an ordinary move that also frees its slot.
	if "G134" not in [a,b]:return true
	var parent=g.nodes.G134.parent
	var capacity=mini(3,int(g.card(parent).slots)+int("P19" in g.nodes[parent].attached))
	return not housing_bonus(parent) or g.children(parent).size()<=capacity

func ability_actions(src: String,p: int) -> Array:
	var out: Array=[]
	if not g.wave.available(src,p) or g.used.has(src):return out
	if src not in ["G141","G148"] and not g.token(src):return out
	match src:
		"G135":
			for target in g.groups(p):
				if g.stat(target,"p")<=2 and (g.has(target,"自由") or g.has(target,"狂热")):out.append(g._a("ability","革命课堂 → "+g.title(target),{"src":src,"target":target}))
		"G141":
			for target in g.groups(p):
				if g.has(target,"太空") and g.can_parent(src,target):out.append(g._a("ability","轨道接驳 → "+g.title(target),{"src":src,"target":target}))
		"G144":
			if not g.decks.group.is_empty() or not g.decks.plot.is_empty():out.append(g._a("ability","双轨窃听",{"src":src,"target":""}))
		"G148":
			if not g.nodes[src].get("prepared",false):
				for fee in g.hands[p].group:out.append(g._a("ability","末日储备 · 弃"+g.title(fee),{"src":src,"target":src,"fee":fee}))
		"G149":
			for target in g.groups(p):
				for other in g.hands[p].group:
					if g.alignments(target)!=g.card(other).align:out.append(g._a("ability","伪造身份 · %s → %s"%[g.title(target)," / ".join(g.card(other).align)],{"src":src,"target":target,"other":other}))
	return out

func plot_costs(p: int) -> Array:
	return g.hands[p].plot+(g.hands[p].group if ready("G136",p) and unused("G136") else [])

func uses_grain(a: Dictionary) -> bool:
	var id=""
	if a.type=="ability" and a.src in ["G015","G102","G138"]:id=a.target
	elif a.type=="support":id=a.get("plot_fee","")
	elif a.type=="plot" and a.id=="P50":id=a.fee
	elif a.type=="trick":id=a.fee
	elif a.type=="choose" and g.choice.get("kind","") in ["emptyvee","w_tax","w_reroll"]:id=a.id
	return id.begins_with("G")

func can_counter(p: int) -> bool:
	return g.wave.available("G137",p) and g.token("G137") and unused("G137") and (not g.hands[p].plot.is_empty() or (ready("G136",p) and unused("G136") and not g.hands[p].group.is_empty()))

func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="main" and p==g.current:
		for a in out.duplicate():
			if a.type=="attack" and a.src=="G147" and a.mode=="destroy" and ready("G147",p):
				var v=a.duplicate();v.solo=true;v.label+=" · 孤军破袭（忽略位置，无进攻支援）";out.append(v)
		out=out.filter(func(a):return not (a.type=="ability" and a.src.begins_with("R") and not can_swap(a.target,a.other)))
	if g.phase=="plot_response" and p==1-g.pending_plot.player and can_counter(p):
		for fee in plot_costs(p):out.append(g._a("trick","替身骗局 · 弃"+g.title(fee),{"src":"G137","fee":fee}))
	if g.phase=="battle" and g.battle.get("responder",-1)==p:
		var b=g.battle
		if b.get("militia_self",false):out=out.filter(func(a):return a.type!="self_defend")
		if normal(b) and b.target=="G145" and p==b.defender and ready("G145",p) and g.token("G145") and "G145" not in b.paid and unused("G145") and not g.synergy.no_self_defense(b):
			out.append(g._a("militia","民兵动员 · 免标记 +%d"%g.stat("G145","p"),{"src":"G145","power":g.stat("G145","p")}))
		if normal(b) and ready("G139",p) and unused("G139"):
			for a in out.duplicate():
				if a.type=="support" and a.src=="G139":
					var v=a.duplicate();v.star=true;v.label+=" · 占星（1–3额外+2）";out.append(v)

	return out

func support_override(id: String,b: Dictionary,d: Dictionary) -> Dictionary:
	if d.basis=="—":return d
	if not normal(b):return d
	if g.owner(id)==b.attacker and b.get("solo",false):return {"base":0,"basis":"—","reason":"孤军破袭 · 无进攻支援"}
	if g.owner(id)==b.attacker and b.get("army_gp_only",false) and g.has(id,"军队"):
		return {"base":g.stat(id,"gp"),"basis":"GP","reason":"止战之声 · 后续军队仅GP"}
	return d

func support_bonus(id: String,b: Dictionary) -> int:
	if not normal(b):return 0
	var value=0
	if id=="G131" and ready(id) and g.owner(id)==b.defender:
		value+=mini(3,b.get("supporters",[]).filter(func(k):return k.owner==b.attacker).size())
	if id=="G139":value+=b.get("star_bonus",0)
	return value

func before_attack(a: Dictionary) -> void:
	if a.get("solo",false):g.battle.solo=true;g._battle_record("ability",g.battle.attacker,"G147",a.target,"孤军破袭 · 忽略位置，无进攻支援")
	if a.mode=="destroy" and a.target=="G148" and ready("G148") and g.nodes.G148.get("prepared",false):
		g.battle.bonus_d+=4
		g.wave.response_queue.append({"kind":"prepared","source":"G148","target":"G148","player":g.owner("G148")})

func values(b: Dictionary,v: Dictionary) -> Dictionary:
	if normal(b) and b.get("solo",false):v.strength+=v.position;v.position=0
	return v

func enqueue(task: Dictionary) -> void:g.wave.defer(task)
func battle_finished(b: Dictionary,success: bool,destroyed: bool) -> void:
	if not normal(b):return
	var p=b.attacker
	if destroyed and b.src=="G143" and ready("G143",p) and not b.get("old_attachments",[]).is_empty():enqueue({"kind":"x_loot","source":"G143","player":p,"options":b.old_attachments})
	if not success and ready("G146",b.defender) and unused("G146") and b.get("supporters",[]).any(func(k):return k.id=="G146" and k.owner==b.defender):
		enqueue({"kind":"x_escort","source":"G146","player":b.defender,"target":b.target})
	if success and b.mode=="control" and not b.get("hand_target",false) and b.src=="G150" and ready("G150",p) and g.wave.devastated(b.target) and g.has(b.target,"地点"):
		enqueue({"kind":"x_rebuild","source":"G150","player":p,"target":b.target})

func handle(p: int,a: Dictionary) -> bool:
	if uses_grain(a):g.used[quota("G136")]=true
	if a.type=="support":
		if a.get("star",false):
			g.used[quota("G139")]=true;g.battle.star_roll=g._die();g.battle.star_bonus=2 if g.battle.star_roll<=3 else 0
			g._battle_record("ability",p,"G139",g.battle.target,"星象助阵 · 骰点%d · 支援+%d"%[g.battle.star_roll,g.battle.star_bonus])
		g.wave.support(p,a)
		if normal(g.battle) and a.src=="G132" and ready(a.src,p) and p==g.battle.defender:g.battle.army_gp_only=true;g._battle_record("ability",p,"G132",g.battle.target,"止战之声 · 后续进攻军队仅GP")
		g.battle.erase("star_bonus");return true
	if a.type=="militia":
		g.used[quota("G145")]=true;g.battle.militia_self=true;g.battle.self=g.stat("G145","p")
		g._battle_record("self_defend",p,"G145","G145","民兵动员 · 免标记 +%d"%g.battle.self);g._response_changed(p);return true
	if a.type=="trick":
		g.nodes.G137.token=0;g.used[quota("G137")]=true;g._discard(p,a.fee)
		g._plot_record_status(g.pending_plot.id,"已被反制");g._battle_record("counter",p,"G137",g.pending_plot.id,"替身骗局 · 取消"+g.title(g.pending_plot.id),"已生效")
		g._spent_plot(g.pending_plot.id);g.phase=g.resume_phase;g.pending_plot={};g._log("替身骗局 · 取消阴谋","counter",{"id":"G137","player":p})
		if g.phase=="battle":g._response_changed(p)
		else:g._after_effect()
		return true
	if a.type=="ability" and int(a.src.substr(1))>=131:
		g.used[a.src]=true
		if a.src not in ["G141","G148"]:g.nodes[a.src].token=0
		match a.src:
			"G135":g.nodes[a.target].learned=g.nodes[a.target].get("learned",0)+1
			"G141":g.nodes[a.target].parent=a.src
			"G144":
				var options: Array=[]
				for kind in ["group","plot"]:
					if not g.decks[kind].is_empty():options.append(g.decks[kind][0])
				g._set_choice(p,"双轨窃听 · 可将1张置于原牌堆底",options,"x_scry",{},true)
			"G148":g._discard(p,a.fee);g.nodes[a.src].prepared=true
			"G149":g.nodes[a.target].mask=g.card(a.other).align.duplicate();g.nodes[a.target].mask_card=a.other;g.wave.if_not_exposed(a.other)
		g._log(g._who(p)+" · "+a.label,"ability",{"id":a.src,"target":a.get("target",""),"player":p});g._after_effect();return true
	if a.type=="trigger" and g.choice.get("task",{}).get("kind","").begins_with("x_"):
		var c=g.choice.duplicate(true);var task=c.task;g.choice={};g.phase=c.resume
		match task.kind:
			"x_loot":
				var options=task.options.filter(func(k):return k in g.discards.plot)
				if not options.is_empty():g._set_choice(p,"战利品 · 可回收1张原附着",options,"x_loot",{},true)
			"x_escort":
				if g.owner(task.target)==p and unused("G146"):
					var options=g.field(p).filter(func(k):return g.can_parent(k,task.target))
					if not options.is_empty():g._set_choice(p,"战后护送 · 可选择新的上级",options,"x_escort",{"target":task.target},true)
			"x_rebuild":
				if g.owner(task.target)==p and g.wave.devastated(task.target):g._set_choice(p,"趁乱收购 · 可免费重建",[task.target],"x_rebuild",{},true)
		g._after_effect();return true
	if a.type=="choose" and g.choice.get("kind","").begins_with("x_"):
		var c=g.choice.duplicate(true);g.choice={};g.phase="main"
		if a.id!="":
			match c.kind:
				"x_scry":
					var kind=g.card(a.id).kind;g.decks[kind].erase(a.id);g.decks[kind].append(a.id)
				"x_loot":g.discards.plot.erase(a.id);g.hands[p].plot.append(a.id)
				"x_escort":g.nodes[c.target].parent=a.id;g.used[quota("G146")]=true
				"x_rebuild":g.wave.rebuild(a.id)
				"x_overflow":g._return_subtree(a.id)
		if c.kind=="x_overflow":
			g.choice=c.saved_choice;g.phase=c.saved_phase
		g._after_effect();return true
	return false

func repair_slots() -> bool:
	if g.choice.get("kind","")=="x_overflow" or g.phase=="over":return false
	for id in g.nodes:
		if g.children(id).size()>g.stat(id,"slots"):
			g._set_choice(g.owner(id),g.title(id)+" · 下属槽失效，选择整支回手",g.children(id),"x_overflow",{"saved_phase":g.phase,"saved_choice":g.choice.duplicate(true),"source":id});return true
	return false

func presentation_cards(a: Dictionary) -> Array:
	var out: Array=[]
	if uses_grain(a):out.append("G136")
	if a.get("star",false):out.append("G139")
	if a.type=="ability" and a.src=="G149":out.append(a.src);out.append(a.other)
	if a.get("solo",false):out.append("G147")
	if a.type in ["militia","trick"]:out.append(a.src)
	if a.type=="support" and a.src in ["G131","G132"] and normal(g.battle):out.append(a.src)
	return out
