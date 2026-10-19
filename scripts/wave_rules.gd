extends RefCounted
## Expansion rules. Choices use the same private/public command boundary as the base game.
var state: WeakRef
var g:
	get: return state.get_ref()
var plans: Dictionary = {}
var announced: Dictionary = {}
var queue: Array = []
var response_queue: Array = []

func _init(game) -> void: state=weakref(game)
func devastated(id: String) -> bool: return g.nodes.has(id) and g.nodes[id].get("devastated",false)
func enabled(id: String,p: int=-1) -> bool:
	return g.nodes.has(id) and (p<0 or g.owner(id)==p) and not g.nodes[id].get("silenced",false)
func available(id: String,p: int=-1) -> bool: return enabled(id,p) and not devastated(id)
func normal(b: Dictionary) -> bool: return not b.has("disaster")
func once(key: String) -> bool: return not g.used.has(key)
func remember(key: String) -> void: g.used[key]=true
func start_turn() -> void: plans.clear();announced.clear();queue.clear();response_queue.clear()
func end_turn() -> void:
	for id in g.nodes:
		if id=="G088" and available(id,g.current) and g.token(id):g.nodes[id].training=mini(2,g.nodes[id].get("training",0)+1)

func extra_tags(id: String,result: Array) -> Array:
	if g.nodes.has(id) and g.nodes[id].parent=="G081" and enabled("G081"):
		var printed=g.card(id).tags
		if "计算机" in printed and "太空" not in result:result.append("太空")
		if "太空" in printed and "计算机" not in result:result.append("计算机")
	return result

func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="choice" and g.choice.get("kind","")=="w_auto":
		return [g._a("trigger",g.choice.label,{"src":g.choice.source})] if g.choice.player==p else []
	if g.phase=="main" and g.current==p:
		out=out.filter(func(a):return a.type!="ability" or available(a.src))
		if g.factions[p]=="I06" and once("fold"):
			var units=g.groups(p)
			for i in units.size():
				for j in range(i+1,units.size()):
					var a=units[i];var b=units[j]
					if g.nodes[a].parent!=g.nodes[b].parent and b not in g.subtree(a) and a not in g.subtree(b):
						out.append(g._a("ability","空间折叠 · %s ↔ %s"%[g.title(a),g.title(b)],{"src":g.root(p),"target":a,"other":b}))
		for target in g.groups(p):
			if not devastated(target):continue
			var actors=g.field(p).filter(func(k):return g.token(k))
			if g.world=="P37" and once("resilient:%d"%p):out.append(g._a("rebuild","韧性社会 · 免费重建「%s」"%g.title(target),{"src":"P37","target":target,"payers":[]}))
			for i in actors.size():
				if not g.has(target,"巨大"):out.append(g._a("rebuild","重建「%s」 · %s行动"%[g.title(target),g.title(actors[i])],{"src":target,"target":target,"payers":[actors[i]]}))
				else:
					for j in range(i+1,actors.size()):out.append(g._a("rebuild","重建「%s」 · %s＋%s"%[g.title(target),g.title(actors[i]),g.title(actors[j])],{"src":target,"target":target,"payers":[actors[i],actors[j]]}))
		var attacks=out.filter(func(a):return a.type=="attack")
		for attack in attacks:
			var variants=[attack]
			if plans.has(p) and attack.mode=="control":
				var a=attack.duplicate();a.use_plan=true;a.label+=" · 用预案 %d"%(plans[p][0]+plans[p][1]);out.append(a);variants.append(a)
			if attack.src=="G088" and enabled("G088") and g.nodes.G088.get("training",0)>0:
				for v in variants:
					var a=v.duplicate();a.training=true;a.label+=" · 训练+2";out.append(a)
	elif g.phase=="plot_response" and p==1-g.pending_plot.player:
		if enabled("G106",p) and g.token("G106") and once("G106") and g.pending_plot.get("was_exposed",false):out.append(g._a("fact_check","事实核查 · 追加弃牌费用",{"src":"G106"}))
	elif g.phase=="battle":out=battle_actions(p,out)
	return out

func ability_actions(src: String,p: int) -> Array:
	var out: Array=[]
	if not available(src,p) or not once(src):return out
	if src not in ["G090","G099","G102"] and not g.token(src):return out
	var targets: Array=[]
	match src:
		"G082":targets=g.discards.plot.filter(func(k):return g.card(k).category.contains("世界秩序"))
		"G083","G086":targets=[""]
		"G084":
			for parent in g.groups(p):
				if g.has(parent,"地点") and g.can_parent(parent,src):out.append(g._a("ability","全球巡演 → "+g.title(parent),{"src":src,"target":src,"parent":parent}))
		"G090":targets=g.hands[p].group.filter(func(k):return g.has(k,"企业"))
		"G096":
			for child in g.children(src):
				if not g.has(child,"企业") or devastated(child) or g.captured.has(child) or not g.can_parent(child):continue
				for target in g.hands[p].group+(g.groups(1-p) if g.can_enemy(p) else []):out.append(g._a("ability","委托制造 · %s → %s"%[g.title(child),g.title(target)],{"src":src,"target":target,"leader":child,"mode":"control"}))
		"G099":
			for moving in g.children(src):
				for parent in g.groups(p):
					if g.has(parent,"沿海") and g.can_parent(parent,moving):out.append(g._a("ability","中转港 · %s → %s"%[g.title(moving),g.title(parent)],{"src":src,"target":moving,"parent":parent}))
		"G102","G107":targets=g.hands[p].plot.duplicate()
		"G105":
			if not g.decks.group.is_empty() or not g.discards.group.is_empty():targets=[""]
		"G109":targets=g.groups(p).filter(func(k):return devastated(k))
		"G110":targets=g.groups(p).filter(func(k):return g.has(k,"地点") and not devastated(k) and not g.nodes[k].get("prepared",false))
	for target in targets:
		var label=g.card(src).effect.get_slice("：",0).replace("（主动）","")
		out.append(g._a("ability",label+(" → "+g.title(target) if target!="" else ""),{"src":src,"target":target}))
	if src=="G096" and plans.has(p):
		for original in out.duplicate():
			var a=original.duplicate();a.use_plan=true;a.label+=" · 用预案 %d"%(plans[p][0]+plans[p][1]);out.append(a)
	return out

func disaster_target(id: String,target: String) -> bool:
	if not g.has(target,"地点"):return false
	if id in ["P32","P33"] and not g.has(target,"沿海"):return false
	if id=="P34" and not g.has(target,"科学") and not g.children(target).any(func(k):return g.has(k,"科学")):return false
	if devastated(target):
		if id=="P32":return g.children(target).any(func(k):return g.removable(k))
		if id=="P33":return not g.has(target,"巨大") and not g.children(target).is_empty()
		if id=="P35":return g.has(target,"巨大") and not g.hands[g.owner(target)].plot.is_empty()
	return true

func main_plots(id: String,p: int) -> Array:
	var out: Array=[];var actors=g.groups(p).filter(func(k):return g.token(k))
	var targets: Array=[]
	if id in ["P31","P32","P33","P34","P35"]:
		if g.can_enemy(p):
			for target in g.groups(1-p):
				if disaster_target(id,target):
					for actor in actors:out.append(g._a("plot",g.title(id)+" → "+g.title(target)+" · "+g.title(actor)+"策动",{"id":id,"src":id,"target":target,"payer":actor}))
	elif id in ["P36","P37"]:targets=[""]
	elif id=="P38" and g.can_enemy(p):
		for target in g.groups(1-p).filter(func(k):return g.has(k,"名人") and not g.nodes[k].get("silenced",false)):
			for actor in actors.filter(func(k):return g.has(k,"媒体")):out.append(g._a("plot","公关危机 → "+g.title(target)+" · "+g.title(actor)+"行动",{"id":id,"src":id,"target":target,"payer":actor}))
	elif id=="P39":targets=g.groups(p).filter(func(k):return g.has(k,"名人"))
	elif id=="P41":
		for target in g.groups(p).filter(func(k):return devastated(k)):
			if g.has(target,"巨大"):
				for fee in g.hands[p].group:out.append(g._a("plot","灾后重建 → %s · 弃%s"%[g.title(target),g.title(fee)],{"id":id,"src":id,"target":target,"fee":fee}))
			else:targets.append(target)
	for target in targets:out.append(g._a("plot",g.title(id)+(" → "+g.title(target) if target!="" else ""),{"id":id,"src":id,"target":target}))
	return out

func combat_plots(id: String,p: int,b: Dictionary) -> Array:
	var out: Array=[]
	if id=="P40" and b.has("disaster") and p==b.defender:
		for child in g.children(b.target):
			for parent in g.field(p):
				if parent not in g.subtree(b.target) and g.can_parent(parent,child):out.append(g._a("plot","紧急疏散 · %s → %s"%[g.title(child),g.title(parent)],{"id":id,"src":id,"target":child,"parent":parent}))
	if id=="P42" and normal(b) and b.mode=="control" and p==b.attacker and not b.get("reframed",false):
		for actor in g.groups(p).filter(func(k):return g.token(k) and g.has(k,"媒体")):out.append(g._a("plot","逆向叙事 · "+g.title(actor)+"行动",{"id":id,"src":id,"target":b.target,"payer":actor}))
	return out

func support_detail(id: String,b: Dictionary,d: Dictionary) -> Dictionary:
	var p=g.owner(id)
	if not g.nodes.has(id) or id in [b.src,b.target] or devastated(id) or (p==b.attacker and not normal(b)):return {"id":id,"power":0,"basis":"—","reason":"不能支援"}
	var base=d.get("base",0);var extra=d.get("extra",0)
	if p==b.attacker:
		if normal(b) and ((enabled("G111",p) and g.has(id,"沿海") and g.has(b.target,"沿海")) or id in b.get("pass_to",[])):
			d.basis="P";base=g.stat(id,"p");d.reason="班轮网络" if id not in b.get("pass_to",[]) else "关键传球"
		if b.get("algorithm",false) and normal(b) and g.world=="P36" and g.has(id,"媒体") and d.basis=="GP" and not b.get("algorithm_used",false):d.basis="P";base=g.stat(id,"p");d.reason="算法时代"
		if id=="G092" and enabled(id):
			for child in g.children(id):
				if g.has(child,"计算机") and not devastated(child) and g.stat(child,"p")>base:base=g.stat(child,"p");d.basis="借P";d.reason="数字外包 · "+g.title(child)
	elif p!=b.defender:return {"id":id,"power":0,"basis":"—","reason":"不能支援"}
	if normal(b) and enabled("G111",p) and g.has(id,"沿海") and g.has(b.target,"沿海"):d.basis="P";base=g.stat(id,"p");d.reason="班轮网络"
	var override=g.synergy.support_override(id,b,base,d.basis,d.reason)
	base=override.base;d.basis=override.basis;d.reason=override.reason
	if p==b.attacker and enabled("G095",1-p) and normal(b) and g.has(b.target,"沿海") and not g.has(id,"沿海") and d.basis=="GP":base=0;extra=0;d.reason="海峡屏障 · 禁止此GP支援"
	if base<=0:d.power=0;return d
	if normal(b) and enabled("G103",p) and g.has(id,"计算机") and b.get("computer_supports",[0,0])[p]==1:extra+=2;d.reason+=" · 并行计算+2"
	if b.get("amplify",false) and id=="G104" and enabled(id):base*=2;d.reason+=" · 弹性扩容"
	var satellite=g.synergy.support_bonus(id,b)
	if satellite>0:extra+=satellite;d.reason+=" · 遥感网络+1"
	d.power=base+extra;d["base"]=base;d["extra"]=extra
	return d

func battle_actions(p: int,out: Array) -> Array:
	var b=g.battle
	if b.get("responder",-1)!=p:return out
	out=out.filter(func(a):return not (b.has("disaster") and a.type=="support" and p==b.attacker))
	# Generate the algorithm and cloud variants even if the unmodified GP would be zero.
	if normal(b):
		for id in g.field(p):
			if not g.token(id) or id in b.paid or id in [b.src,b.target]:continue
			var bases=[false,true] if p==b.attacker and g.world=="P36" and g.has(id,"媒体") and not b.get("algorithm_used",false) else [false]
			for algorithm in bases:
				if algorithm and g.support_detail(id,b).basis!="GP":continue
				var context=b.duplicate(true);context.algorithm=algorithm
				var d=g.support_detail(id,context)
				if d.power<=0:continue
				if algorithm:out.append(g._a("support","算法时代 · %s (P +%d)"%[g.title(id),d.power],{"src":id,"power":d.power,"basis":d.basis,"algorithm":true}))
				if id=="G104" and enabled(id):
					context.amplify=true;d=g.support_detail(id,context)
					for fee in g.hands[p].plot:out.append(g._a("support","弹性扩容 · +%d · 弃%s"%[d.power,g.title(fee)],{"src":id,"power":d.power,"basis":d.basis,"algorithm":algorithm,"amplify":true,"plot_fee":fee}))
		if p==b.attacker and enabled("G100",b.defender) and g.has(b.target,"沿海") and b.get("support_counts",[0,0])[p]==1:
			var revised: Array=[]
			for a in out:
				if a.type!="support":revised.append(a);continue
				for fee in g.hands[p].group:
					var v=a.duplicate();v.group_fee=fee;v.label+=" · 通行费弃"+g.title(fee);revised.append(v)
			out=revised
		if p==b.attacker and available("G089",p) and g.token("G089") and "G089" not in b.paid:
			for target in g.field(p):
				if target!="G089" and target not in b.paid and target!=b.src and g.token(target):out.append(g._a("wave","关键传球 → "+g.title(target),{"src":"G089","target":target}))
		if p==b.defender and available("G101",p) and g.token("G101") and b.entries.size()==1 and g.has(b.target,"名人") and g.can_parent("G101",b.target):out.append(g._a("wave","签证通道 · 撤入迪拜",{"src":"G101","target":b.target}))
		if p==b.defender and enabled("G112",p) and once("G112") and g.has(b.target,"名人"):
			for fee in g.hands[p].group:out.append(g._a("wave","自发应援 · 弃"+g.title(fee),{"src":"G112","target":b.target,"fee":fee}))
	return out

func before_attack(p: int,a: Dictionary) -> void:
	if a.mode=="control" and plans.has(p):
		if a.get("use_plan",false):g.battle.fixed_dice=plans[p].duplicate()
		plans.erase(p)
	if a.get("training",false):g.nodes[a.src].training-=1;g.battle.bonus_a+=2;g._battle_record("ability",p,"G088",a.target,"自律训练 · 强度+2")

func handle(p: int,a: Dictionary) -> bool:
	if a.type=="trigger":
		var c=g.choice.duplicate(true);g.choice={};g.phase=c.resume
		var task=c.task
		if task.kind=="prepared" and g.nodes.has(task.target):g.nodes[task.target].prepared=false
		if task.kind=="draw" and once(task.quota):
			remember(task.quota)
			for i in task.amount:g._draw(p,task.get("deck","plot"))
			g._log(g.title(a.src)+" · "+task.get("message","抽牌收益"),"ability",{"id":a.src})
		if c.resume=="battle":next_response_trigger()
		else:g._after_effect()
		return true
	if a.type=="choose" and g.choice.get("kind","").begins_with("w_"):choose(a.id);return true
	if a.type=="rebuild":
		for actor in a.payers:g.nodes[actor].token=0
		if a.src=="P37":remember("resilient:%d"%p)
		rebuild(a.target);g._log("重建完成 · "+g.title(a.target),"ability",{"id":a.target});g._after_effect();return true
	if a.type=="ability" and (g.is_root(a.src) or int(a.src.substr(1))>=81):ability(p,a);return true
	if a.type=="support":support(p,a);return true
	if a.type=="wave":
		match a.src:
			"G089":g.nodes[a.src].token=0;g.battle.get_or_add("pass_to",[]).append(a.target)
			"G101":g.nodes[a.src].token=0;g.nodes[a.target].parent=a.src
			"G112":g._discard(p,a.fee);g.battle.bonus_d+=3;remember(a.src)
		g._battle_record("ability",p,a.src,a.target,a.label);g._log(g._who(p)+" · "+a.label,"ability",{"id":a.src});g._response_changed(p);return true
	if a.type=="fact_check":
		g.nodes.G106.token=0;remember("G106")
		g._battle_record("ability",p,"G106",g.pending_plot.id,"事实核查 · 追加弃牌费用")
		g._set_choice(1-p,"事实核查 · 弃1张阴谋，否则取消出牌",g.hands[1-p].plot,"w_tax",{},true);return true
	return false

func ability(p: int,a: Dictionary) -> void:
	var src=a.src;var target=a.get("target","")
	if g.is_root(src):
		var parent=g.nodes[target].parent;g.nodes[target].parent=g.nodes[a.other].parent;g.nodes[a.other].parent=parent;remember("fold")
	else:
		remember(src)
		if src not in ["G090","G099","G102"]:g.nodes[src].token=0
		match src:
			"G082":g.discards.plot.erase(target);set_world(target)
			"G083":plans[p]=[g._die(),g._die()]
			"G084":g.nodes[src].parent=a.parent;g._draw(p,"plot")
			"G086":g._draw(p,"group");g._draw(1-p,"group");g._draw(p,"plot")
			"G090":announced[target]=p;if_not_exposed(target)
			"G096":
				g._launch_attack(p,{"src":a.leader,"target":target,"mode":"control","delegate":src,"use_plan":a.get("use_plan",false)});return
			"G099":g.nodes[target].parent=a.parent;g._draw(p,"group")
			"G102":
				g._discard(p,target);var roll=g._die()
				if roll>=4:
					for i in 3:g._draw(p,"plot")
				g._log("幸运押注 · 骰点 %d · %s"%[roll,"抽3张阴谋" if roll>=4 else "未获收益"],"ability",{"id":src});g._after_effect();return
			"G105":
				var peek=g._take(p,"group",3)
				if not peek.is_empty():g._set_choice(p,"推荐流 · 选择1张团体",peek,"w_draft",{"peek":peek,"initiator":p,"round":0})
			"G107":
				var revealed=target in g.exposed;g.hands[p].plot.erase(target);g.decks.plot.append(target);g._shuffle(g.decks.plot);g._draw(p,"plot")
				if revealed:g._draw(p,"group")
			"G109":rebuild(target)
			"G110":g.nodes[target].prepared=true
	var suffix=" · 预案 %d＋%d"%plans[p] if src=="G083" else ""
	g._log(g.title(src)+" · "+g.card(src).effect.get_slice("：",0)+suffix,"ability",{"id":src});g._after_effect()

func if_not_exposed(id: String) -> void:
	if id not in g.exposed:g.exposed.append(id)
func set_world(id: String) -> void:
	if g.world!="":g.discards.plot.push_front(g.world)
	g.world=id
func rebuild(target: String) -> void:
	g.nodes[target].devastated=false
	var p=g.owner(target)
	if p==g.current and enabled("G094",p) and once("G094"):
		var options=g.groups(p).filter(func(k):return g.has(k,"绿色") and g.can_recharge(k))
		if not options.is_empty():queue.append({"kind":"recharge","source":"G094","player":p,"options":options})

func support(p: int,a: Dictionary) -> void:
	var b=g.battle;var context=b.duplicate(true);context.algorithm=a.get("algorithm",false);context.amplify=a.get("amplify",false)
	var d=g.support_detail(a.src,context)
	if a.has("plot_fee"):g._discard(p,a.plot_fee)
	if a.has("group_fee"):g._discard(p,a.group_fee)
	g.nodes[a.src].token=0;b.paid.append(a.src)
	b["support_a" if p==b.attacker else "support_d"]+=d.power
	if a.get("algorithm",false):b.algorithm_used=true
	if not b.has("computer_supports"):b.computer_supports=[0,0]
	if not b.has("support_counts"):b.support_counts=[0,0]
	b.support_counts[p]+=1
	if g.has(a.src,"计算机"):b.computer_supports[p]+=1
	if not b.has("supporters"):b.supporters=[]
	b.supporters.append({"id":a.src,"owner":p})
	var lead=b.src if p==b.attacker else b.target
	if a.src=="G024" and g.has(lead,"计算机"):b.video.append({"id":a.src,"owner":p})
	var message="%s 支援%s +%d（%s）"%[g.title(a.src),"进攻" if p==b.attacker else "防守",d.power,d.basis]
	if a.has("plot_fee"):message+=" · 弃"+g.title(a.plot_fee)
	if a.has("group_fee"):message+=" · 通行费弃"+g.title(a.group_fee)
	g._battle_record("support",p,a.src,b.target,message);g._log(g._who(p)+" · "+message,"support",{"id":a.src,"player":p})
	if normal(b) and enabled("G091",p) and once("G091") and g.has(a.src,"科学") and not g.hands[p].group.is_empty():response_queue.append({"kind":"export","player":p})
	g._response_changed(p)

func plot_committed(p: int,a: Dictionary) -> void:
	if a.has("payer"):g.nodes[a.payer].token=0
	if a.has("fee"):g._discard(p,a.fee)

func resolve_plot(a: Dictionary) -> bool:
	var id=a.id;var p=a.player;var target=a.get("target","")
	if g.synergy.resolve_plot(a):return true
	if id in ["P31","P32","P33","P34","P35"]:start_disaster(a);return true
	if id not in ["P36","P37","P38","P39","P40","P41","P42"]:return false
	match id:
		"P36","P37":set_world(id)
		"P38":g.nodes[target].silenced=true
		"P39":g.nodes[target].attached.append(id)
		"P40":g.nodes[target].parent=a.parent
		"P41":rebuild(target)
		"P42":g.battle.reframed=true
	if id not in ["P36","P37","P39"]:g._spent_plot(id)
	plot_rewards(p,id,a)
	if not g.battle.is_empty():g._response_changed(p)
	else:g._after_effect()
	return true

func plot_rewards(p: int,id: String,a: Dictionary={}) -> void:
	g.synergy.plot_reward(p,a)
	if enabled("G035",p) and g.current==p and g.children("G035").any(func(k):return g.has(k,"媒体")):g._reward_draw("G035",p,"plot")
	if g.battle.is_empty() or not normal(g.battle) or int(id.substr(1)) not in range(1,10):return
	if not g.battle.has("alignment_plots"):g.battle.alignment_plots=[[],[]]
	var kinds=g.battle.alignment_plots[p]
	if id not in kinds:kinds.append(id)
	if kinds.size()==2 and enabled("G087",p) and once("G087"):
		response_queue.append({"kind":"draw","source":"G087","quota":"G087","player":p,"amount":1,"message":"联合倡议 · 抽1张阴谋"})
		g._battle_record("ability",p,"G087","","联合倡议 · 抽1张阴谋")

func start_disaster(a: Dictionary) -> void:
	var target=a.target;var p=a.player;var defense=0
	if g.removable(target):g.nodes[target].token=0
	if g.nodes[target].get("prepared",false):
		defense=4
		response_queue.append({"kind":"prepared","source":"G110","player":g.owner(target),"target":target})
		if enabled("G098",g.owner(target)) and not g.has(target,"巨大") and once("G098"):response_queue.append({"kind":"draw","source":"G098","quota":"G098","player":g.owner(target),"amount":1,"deck":"group","message":"灾害演练 · 抽1张团体"})
	g.attacked[p]=true
	g.battle={"src":a.payer,"target":target,"disaster":a.id,"mode":"destroy","attacker":p,"defender":g.owner(target),"responder":1-p,"passes":0,"paid":[a.payer],"support_a":0,"support_d":0,"bonus_a":0,"bonus_d":defense,"self":0,"rescue":false,"video":[],"spent":[a.id],"entries":[],"before":g.field(p)}
	g.phase="battle";g._battle_record("plot",p,a.id,target,g.title(a.id)+" → "+g.title(target),"已生效")
	if defense>0:g._battle_record("ability",g.owner(target),"G110",target,"防备 · 防御+4（已消耗）")
	plot_rewards(p,a.id,a)
	next_response_trigger()

func auto_trigger(task: Dictionary,resume: String) -> void:
	g._set_choice(task.player,g.title(task.source)+" · 效果生效",[],"w_auto",{"source":task.source,"task":task,"resume":resume})

func next_response_trigger() -> void:
	while not response_queue.is_empty():
		var task=response_queue.pop_front()
		if task.kind=="export":
			var p=task.player
			if enabled("G091",p) and once("G091") and not g.hands[p].group.is_empty():
				g._set_choice(p,"矿产出口 · 可将1张团体放到堆底，抽1张阴谋",g.hands[p].group,"w_export",{"source":"G091","resume":"battle"},true);return
		else:auto_trigger(task,"battle");return

func values(b: Dictionary,v: Dictionary) -> Dictionary:
	if not b.has("disaster"):
		if b.mode=="control" and b.src=="G097" and enabled("G097") and g.has(b.target,"绿色"):v.ability+=4;v.strength+=4
		if b.get("reframed",false):v.strength-=2*v.alignment;v.alignment=-v.alignment
	else:
		var power={"P31":14,"P32":14,"P33":16,"P34":18,"P35":12}[b.disaster]
		var ability=0
		if g.has(b.target,"巨大"):ability=-4 if b.disaster=="P31" else (4 if b.disaster=="P35" else 0)
		v.power=power;v.alignment=0;v.ability=ability;v.loyalty=0;v.position=0;v.base=g.stat(b.target,"r" if b.target=="G076" else "p")
		v.strength=power+ability+b.bonus_a-v.base-v.defense-b.bonus_d-b.support_d-b.self
	v=g.synergy.values(b,v)
	var chance=0;var kill=0;var threshold=4 if b.get("disaster","")=="P31" else 6
	for x in range(1,7):
		for y in range(1,7):
			if x+y<=v.strength and x+y<=10:
				chance+=1
				if b.get("disaster","") in ["P31","P34"] and v.strength-x-y>=threshold:kill+=1
	v.chance=chance/36.0;v.destroy_chance=kill/36.0
	if b.get("rescue",false):v.destroy_chance=0.0
	if b.has("fixed_dice"):v.chance=1.0 if b.fixed_dice[0]+b.fixed_dice[1]<=mini(10,v.strength) else 0.0
	return v

func disaster_preview(a: Dictionary) -> Dictionary:
	return g.battle_values({"src":a.payer,"target":a.target,"mode":"destroy","disaster":a.id,"attacker":g.owner(a.payer),"defender":g.owner(a.target),"support_a":0,"support_d":0,"bonus_a":0,"bonus_d":4 if g.nodes[a.target].get("prepared",false) else 0,"self":0})

func cancel_pending() -> void:
	var id=g.pending_plot.id;var responder=1-g.pending_plot.player;g._plot_record_status(id,"已被事实核查取消");g._spent_plot(id);g.pending_plot={};g.phase=g.resume_phase
	if g.phase=="battle":g._response_changed(responder)
	else:g._after_effect()

func choose(id: String) -> void:
	var c=g.choice.duplicate(true);var p=c.player;g.choice={};g.phase=c.get("resume","main")
	match c.kind:
		"w_export":
			if id!="":g.hands[p].group.erase(id);g.decks.group.append(id);remember("G091");g._draw(p,"plot")
		"w_draft":
			g.hands[p].group.append(id);if_not_exposed(id);c.peek.erase(id)
			g._log(g._who(p)+" · 推荐流选择「"+g.title(id)+"」","reveal",{"id":id,"player":p})
			if c.round==0 and not c.peek.is_empty():g._set_choice(1-p,"推荐流 · 对方选择1张",c.peek,"w_draft",{"peek":c.peek,"initiator":c.initiator,"round":1});return
			for rest in c.peek:g.discards.group.push_front(rest)
		"w_tax":
			if id=="":cancel_pending();return
			g._discard(p,id);g._resolve_plot();return
		"w_recharge":
			if id!="" and g.can_recharge(id):g.nodes[id].token=1;g.recharged[id]=true;remember(c.quota)
		"w_reroll":
			if id!="":g._discard(p,id);g.battle.erase("rolled");g.battle.rerolled=true
			else:g.battle.rerolled=true
			g.phase="battle";resolve_battle();return
		"w_inherit":g.battle.heir=id;g.battle.inherit_chosen=true;g.phase="battle";resolve_battle();return
		"w_hurricane":
			if id!="" and g.removable(id):g.nodes[id].token=0
		"w_tsunami":g._return_subtree(id)
		"w_epidemic":g._discard(p,id)
	if c.get("resume","main")=="battle":next_response_trigger()
	g._after_effect()

func drain() -> bool:
	if g.phase not in ["main"]:return false
	while not queue.is_empty():
		var task=queue.pop_front();var p=task.player
		match task.kind:
			"synergy":return g.synergy.queue_task(task.task)
			"recharge":
				var options=task.options.filter(func(k):return g.nodes.has(k) and g.owner(k)==p and g.can_recharge(k))
				var quota=task.get("quota",task.source)
				if not options.is_empty() and once(quota):g._set_choice(p,g.title(task.source)+" · 可恢复1个团体",options,"w_recharge",{"source":task.source,"quota":quota},true);return true
			"hurricane":
				var options=g.children(task.target).filter(func(k):return g.removable(k))
				if not options.is_empty():g._set_choice(p,"飓风 · 可移除1个下属标记",options,"w_hurricane",{},true);return true
			"tsunami":
				var options=g.children(task.target)
				if not options.is_empty():g._set_choice(p,"海啸 · 选择整支撤回手牌的下属",options,"w_tsunami");return true
			"epidemic":
				if not g.hands[p].plot.is_empty():g._set_choice(p,"疫情暴发 · 弃1张阴谋",g.hands[p].plot,"w_epidemic");return true
			"insurance":
				if enabled("G108",p) and once("G108"):
					auto_trigger({"kind":"draw","source":"G108","quota":"G108","player":p,"amount":task.amount,"message":"灾害承保 · 抽%d张阴谋"%task.amount},"main");return true
	return false

func resolve_battle() -> void:
	var b=g.battle
	if b.is_empty():return
	var v=g.battle_values(b);var dice: Array=[]
	if b.has("rolled"):dice=b.rolled
	elif v.strength>=2 and not b.get("foiled",false):
		dice=b.fixed_dice.duplicate() if b.has("fixed_dice") else [g._die(),g._die()]
		b.rolled=dice
	var success=dice.size()==2 and dice[0]+dice[1]<=mini(10,v.strength) and not b.get("foiled",false)
	if not success and normal(b) and not b.get("rerolled",false) and not b.has("fixed_dice") and dice.size()==2 and dice[0]+dice[1]<=10 and enabled("G085",b.attacker) and b.get("supporters",[]).any(func(k):return k.id=="G085" and k.owner==b.attacker) and not g.hands[b.attacker].plot.is_empty():
		g._set_choice(b.attacker,"安可 · 原骰%d＋%d · 可弃1张阴谋重掷"%dice,g.hands[b.attacker].plot,"w_reroll",{"source":"G085"},true);return
	var p=b.attacker;var target=b.target;var enemy=g.nodes.has(target);var rescued=false;var destroyed_target=false;var new_devastated=false
	var guarded=false
	var target_name=g.title(target);var affected=g.subtree(target).size() if enemy else 1
	var destroy=success and b.mode=="destroy"
	if b.has("disaster"):destroy=destroy and b.disaster in ["P31","P34"] and v.strength-dice[0]-dice[1]>=(4 if b.disaster=="P31" else 6)
	if g.synergy.prepare_guard(b,destroy):return
	if destroy and not b.rescue and target=="G093" and enabled(target) and not b.get("inherit_chosen",false) and not g.children(target).is_empty():
		g._set_choice(b.defender,"战略纵深 · 可选择继任分支",g.children(target),"w_inherit",{"source":"G093"},true);return
	if success:
		if b.mode=="control":
			if enemy:
				for id in g.subtree(target):g.nodes[id].owner=p;g.nodes[id].token=0;g.captured[id]=true
				g.nodes[target].parent=b.src
				if b.src=="G055":g.nodes[target].vampire=true
			else:g._enter(target,p,b.src);g.captured[target]=true;g.failed_recruits.erase(target)
			if b.src=="G014" and g.has(target,"企业"):g._reward_draw(b.src,p,"plot")
			if b.src=="G023" and g.has(target,"计算机"):g._reward_draw(b.src,p,"group")
			if announced.get(target,-1)==p:g._draw(p,"plot");announced.erase(target)
		elif b.rescue:rescued=true;g._return_subtree(target)
		elif destroy and g.synergy.guard_blocks(b):guarded=true
		elif destroy:
			var heir=b.get("heir","")
			if heir!="" and g.nodes.has(heir):g.nodes[heir].parent=g.nodes[target].parent
			for child in g.children(target):g._return_subtree(child)
			for attachment in g.nodes[target].attached:g.discards.plot.push_front(attachment)
			g.nodes.erase(target);g.graves[p].append(target);g.destroyed[p]+=1;destroyed_target=true
			if b.src=="G052":g._reward_draw(b.src,p,"group")
		elif b.has("disaster"):
			new_devastated=not devastated(target);g.nodes[target].devastated=true;g.nodes[target].token=0
			if b.disaster=="P32":queue.append({"kind":"hurricane","target":target,"player":p})
			if b.disaster=="P33" and not g.has(target,"巨大"):queue.append({"kind":"tsunami","target":target,"player":b.defender})
			if b.disaster=="P35" and g.has(target,"巨大"):queue.append({"kind":"epidemic","target":target,"player":b.defender})
	if b.has("disaster") and not rescued and (destroyed_target or new_devastated):queue.append({"kind":"insurance","player":b.defender,"amount":2 if destroyed_target else 1})
	for entry in b.video:
		if g.owner(entry.id)==entry.owner and g.can_recharge(entry.id):g.nodes[entry.id].token=1;g.recharged[entry.id]=true
	for entry in b.get("supporters",[]):
		if g.owner(entry.id)==entry.owner and "P39" in g.nodes[entry.id].attached:
			queue.append({"kind":"recharge","source":"P39","quota":"brand:"+entry.id,"player":entry.owner,"options":g.groups(entry.owner).filter(func(k):return g.has(k,"企业") and g.can_recharge(k))})
	for id in b.spent:g.discards.plot.push_front(id)
	g.last_battle=b.duplicate(true);g.last_battle.values=v;g.last_battle.dice=dice;g.last_battle.success=success;g.last_battle.rescued=rescued;g.last_battle.destroyed=destroyed_target;g.last_battle.devastated=new_devastated;g.last_battle.guarded=guarded
	if b.get("hand_target",false) and not success:g.hands[p].group.append(target)
	g.battle={};g.phase="main"
	g.synergy.battle_finished(b,success,destroyed_target)
	if success and b.mode=="control" and not enemy:g._entry_rewards(target,p,b.src,b.before)
	var outcome="保镖挡下摧毁" if guarded else ("救援撤离" if rescued else ("摧毁" if destroyed_target else ("受灾" if new_devastated else ("成功" if success else "失败"))))
	if success and b.mode=="control" and affected>1:outcome+=" · 夺取整支%d张"%affected
	g._log(target_name+" · "+outcome+(" · 骰子 %d＋%d"%dice if dice.size()==2 else " · 不掷骰"),"result",{"dice":dice,"success":success,"rescued":rescued,"guarded":guarded,"target":target,"mode":b.mode,"values":v})
	g._after_effect()

func presentation_cards(p: int,a: Dictionary) -> Array:
	var out: Array=g.synergy.presentation_cards(a)
	if a.type in ["ability","plot","counter","mediate","rescue","wave","fact_check","rebuild","trigger"]:out.append(a.get("id",a.get("src","")))
	if a.type=="choose" and g.choice.get("kind","").begins_with("w_") and a.id!="":out.append(g.choice.get("source",""))
	if a.type=="choose" and g.choice.get("kind","")=="w_draft" and p==1:out.append(a.id)
	if a.type=="support":
		if a.get("algorithm",false):out.append("P36")
		if a.get("amplify",false):out.append("G104")
		if enabled("G103",p) and normal(g.battle) and g.has(a.src,"计算机") and g.battle.get("computer_supports",[0,0])[p]==1:out.append("G103")
		if a.has("group_fee"):out.append("G100")
	if a.type=="end" and available("G088",p) and g.token("G088") and g.nodes.G088.get("training",0)<2:out.append("G088")
	return out.filter(func(k):return k!="")

func held_cards() -> Array:
	return g.choice.get("peek",[]) if g.choice.get("kind","")=="w_draft" else []
