class_name ResourceRules
extends RefCounted
## Resources belong to a player, never to a branch of the power structure.
const PLOTS=["P56","P57","P58","P59","P60"]
var state: WeakRef
var g:
	get:return state.get_ref()
func _init(game) -> void:state=weakref(game)
func field(p: int) -> Array:return g.nodes.keys().filter(func(id):return g.owner(id)==p and g.card(id).kind=="resource")
func ready(id: String,p: int=-1) -> bool:return g.wave.enabled(id,p) and g.card(id).kind=="resource"
func recoverable(id: String) -> bool:return ready(id) and g.card(id).action and g.can_recharge(id)
func can_draw(p: int) -> bool:return g.hands[p].resource.size()<g.resource_hand_limit(p)
func can_evacuate(p: int) -> bool:
	var b=g.battle
	return not b.is_empty() and not b.has("disaster") and b.mode=="control" and b.defender==p and ready("E16",p) and b.target in g.groups(p)
func opening() -> void:
	g.phase="setup_resource"
	for p in [0,1]:g.resource_candidates[p]=g._take(p,"resource",5)
func opening_score(id: String,p: int) -> float:
	var value=12+int(g.card(id).action)*2
	if id in ["E03","E04","E05"]:value+=3
	if id=="E14" and g.groups(p).any(func(k):return g.has(k,"巨大")):value+=6
	if id=="E09" and g.groups(p).any(func(k):return g.has(k,"沿海")):value+=6
	if id=="E11" and g.groups(p).any(func(k):return g.stat(k,"p")>g.stat(k,"gp")+2):value+=6
	return value
func reroll(p: int) -> void:
	var pool=g.resource_candidates[p].duplicate()
	for id in pool:g.decks.resource.append(id);g._flow(id,"choice","deck",p)
	g._shuffle(g.decks.resource);g.resource_candidates[p]=g._take(p,"resource",pool.size());g.resource_rerolls[p]+=1
	g._log(g._who(p)+"重随了资源候选","resource_mulligan",{"player":p})
func select_opening(p: int,id: String) -> void:
	g.hands[p].resource.append(id);g._flow(id,"choice","hand",p)
	for other in g.resource_candidates[p]:
		if other!=id:g.decks.resource.append(other)
	g.resource_candidates[p]=[]
func deck_available(kind: String) -> bool:return not g.decks[kind].is_empty() or not g.discards[kind].is_empty()
func repair_hand() -> bool:
	if g.phase!="main":return false
	for p in [0,1]:
		if g.hands[p].resource.size()>g.resource_hand_limit(p):
			g._set_choice(p,"资源手牌上限 %d · 选择弃牌"%g.resource_hand_limit(p),g.hands[p].resource,"e_limit");return true
	return false
func refill(p: int) -> void:
	for id in field(p):g.nodes[id].token=1 if g.card(id).action else 0
func remove(id: String) -> void:
	var p=g.owner(id)
	g.nodes.erase(id);g.scrap.append(id);g._flow(id,"board","scrap",p)
	if ready("E13",p) and not g.used.has("e_museum:%d"%p):
		g.used["e_museum:%d"%p]=true
		var task={"kind":"draw","source":"E13","player":p,"deck":"plot","amount":2,"message":"私人博物馆 · 抽2张阴谋"}
		if g.battle.is_empty():g.wave.defer(task)
		else:g.wave.response_queue.append(task)
func entry_reward(p: int) -> void:
	if ready("E04",p) and not g.used.has("e_archive"):
		g.used.e_archive=true
		g.wave.defer({"kind":"draw","source":"E04","player":p,"deck":"plot","amount":1,"message":"私人档案库 · 抽1张阴谋"})
func support_detail(id: String,d: Dictionary) -> Dictionary:
	if d.basis=="GP" and d.power>0 and ready("E09",g.owner(id)) and g.has(id,"沿海"):
		d.power+=1;d.extra=d.get("extra",0)+1;d.reason+=" · 海底光缆+1"
	return d
func attack_options(context: Dictionary) -> Array:
	if field(context.attacker).is_empty():return []
	# Query the actual battle commands and rehearse each resource on isolated models.
	# This shares card eligibility and numeric effects with play, without touching live RNG.
	var model=ActionFlow.copy_state(g);var p=context.attacker;model.phase="battle";model.battle=context.duplicate(true)
	model.battle.merge({"responder":p,"passes":0,"support_a":0,"support_d":0,"bonus_a":0,"bonus_d":0,"self":0,"entries":[],"supporters":[],"support_counts":[0,0]},false)
	var direct=model.legal_actions(p).filter(func(a):return a.type=="resource" and model.card(a.src).kind=="resource")
	var result=[];var before=model.battle_values().strength
	for a in direct:
		var trial=ActionFlow.copy_state(model)
		if trial.act(p,a):result.append({"id":a.src,"label":a.label,"bonus":maxi(0,trial.battle_values().strength-before),"conditional":false})
	var potential=ActionFlow.copy_state(model)
	for id in potential.field(1-p):
		if potential.token(id):potential.battle.support_d+=potential.support_power(id,potential.battle)
	for a in potential.legal_actions(p):
		if a.type=="resource" and potential.card(a.src).kind=="resource" and not result.any(func(entry):return entry.id==a.src):result.append({"id":a.src,"label":a.label,"bonus":0,"conditional":true})
	return result
func country_actions(src: String,p: int) -> Array:
	if src not in ["G091","G093"] or not g.wave.available(src,p) or not g.token(src) or g.used.has(src):return []
	if src=="G091":
		var actions: Array=[]
		if can_draw(p) and deck_available("resource"):
			for fee in g.hands[p].group:actions.append(g._a("resource","矿产出口 · 弃1团体，抽1资源",{"src":src,"fee":fee}))
		return actions
	var out: Array=[]
	for id in field(p):
		if recoverable(id) and "装置" in g.tags(id):out.append(g._a("resource","军工整备 → "+g.title(id),{"src":src,"target":id}))
	return out
func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="setup_resource":
		if (g.human_duel and g.opening_picks.resource[p]=="") or (not g.human_duel and p==0):
			for id in g.resource_candidates[p]:out.append(g._a("initial_resource","选择「%s」"%g.title(id),{"id":id}))
			if g.resource_rerolls[p]<2:out.append(g._a("reroll_resource","重随资源",{}))
		return out
	if g.phase=="main" and g.current==p:
		if g.token(g.root(p)):
			for kind in ["group","resource","plot"]:
				if deck_available(kind) and (kind!="resource" or can_draw(p)):out.append(g._a("research","抽1张"+{"group":"团体","resource":"资源","plot":"阴谋"}[kind],{"src":g.root(p),"deck":kind}))
		if not g.deploy_used:
			for id in g.hands[p].resource:
				var replacements=field(p) if field(p).size()>=2 else [""]
				for old in replacements:
					if g.token(g.root(p)):out.append(g._a("deploy","部署资源 · 花主牌1行动",{"id":id,"src":id,"replace":old,"supply":false}))
					if g.wave.enabled("G098",p):
						for fee in g.hands[p].group:out.append(g._a("deploy","矿产供给 · 弃团体代替主牌行动",{"id":id,"src":id,"replace":old,"fee":fee,"supply":true}))
		for id in field(p):
			if not ready(id,p):continue
			if g.card(id).action and not g.token(id):continue
			match id:
				"E02":
					for target in g.groups(p):
						if g.can_recharge(target):out.append(g._a("resource","应急电池 · 恢复1行动，本回合P+4 · 报废",{"src":id,"target":target}))
				"E06":
					if not g.decks.group.is_empty() or not g.discards.group.is_empty():out.append(g._a("resource","量子计算机 · 抽2张团体，保留1张",{"src":id}))
				"E08":
					if can_draw(p) and not g.decks.resource.is_empty():out.append(g._a("resource","深空探测器 · 查看资源堆顶3张",{"src":id}))
				"E11":
					for target in g.groups(p):
						if g.stat(target,"p")>g.stat(target,"gp"):out.append(g._a("resource","卫星通讯 · 本回合GP等于P",{"src":id,"target":target}))
				"E10":
					for target in g.groups(p):
						for parent in g.field(p):
							if g.can_parent(parent,target):out.append(g._a("resource","后勤无人机 · 移动整支团体",{"src":id,"target":target,"parent":parent}))
	elif g.phase=="battle" and g.battle.responder==p:
		var b=g.battle
		if not b.has("disaster"):
			if can_evacuate(p):out.append(g._a("resource","安全屋 · 整支回手，取消攻击 · 报废",{"src":"E16","target":b.target}))
			var opposing="support_d" if p==b.attacker else "support_a"
			if ready("E12",p) and b[opposing]>0:out.append(g._a("resource","数字诱饵 · 对手支援-8 · 报废",{"src":"E12","target":b.target}))
			if ready("E15",p) and b.get("fixed_dice",[])!=[4,4]:out.append(g._a("resource","命运硬币 · 骰点固定4＋4 · 报废",{"src":"E15","target":b.target}))
			if p==b.attacker and ready("E01",p) and g.token("E01"):out.append(g._a("resource","战术雷达 · 强度+3 · 花资源1行动",{"src":"E01","target":b.target}))
			if p==b.defender and b.mode=="destroy" and ready("E07",p):out.append(g._a("resource","凤凰护符 · 防御+10 · 报废资源",{"src":"E07","target":b.target}))
	return out
func plot_actions(id: String,p: int) -> Array:
	var out: Array=[]
	if id=="P57":
		if can_draw(p) and not g.decks.resource.is_empty():out.append(g._a("plot","逆向研发 · 查看2张资源，取1张",{"id":id,"src":id,"target":""}))
	elif g.can_enemy(p):
		for target in field(1-p):
			if id in ["P59","P60"]:
				if id=="P59" and (not can_draw(p) or "装置" not in g.tags(target)):continue
				var required_tag="政府" if id=="P59" else "科学"
				for payer in g.groups(p):
					if not g.token(payer) or not g.has(payer,required_tag):continue
					for other in ([""] if id=="P59" else field(p)):
						var args={"id":id,"src":id,"target":target,"payer":payer}
						if other!="":args.other=other
						out.append(g._a("plot",g.title(id)+" → "+g.title(target),args))
				continue
			if id=="P58" and not ready(target):continue
			if id=="P56":
				for payer in g.groups(p):
					if g.token(payer):out.append(g._a("plot","精密爆破 → "+g.title(target),{"id":id,"src":id,"target":target,"payer":payer}))
			else:out.append(g._a("plot","技术封锁 → "+g.title(target),{"id":id,"src":id,"target":target}))
	return out
func handle(p: int,a: Dictionary) -> bool:
	if a.type=="reroll_resource":reroll(p);return true
	if a.type=="initial_resource":
		if g.human_duel:
			g.opening_picks.resource[p]=a.id
			if "" in g.opening_picks.resource:return true
			for who in [0,1]:select_opening(who,g.opening_picks.resource[who])
			g._shuffle(g.decks.resource);g._finish_opening();return true
		while g.resource_rerolls[1]<2 and g.resource_candidates[1].all(func(k):return opening_score(k,1)<15):reroll(1)
		var pool=g.resource_candidates[1].duplicate();pool.sort_custom(func(x,y):return opening_score(x,1)>opening_score(y,1))
		select_opening(0,a.id);select_opening(1,pool[0]);g._shuffle(g.decks.resource);g._finish_opening();return true
	if a.type=="research":
		g.spend(g.root(p));g._draw(p,a.deck);g._log(g._who(p)+"花主牌1行动抽取"+{"group":"团体","resource":"资源","plot":"阴谋"}[a.deck],"research",{"player":p});g._after_effect();return true
	if a.type=="deploy":deploy(p,a);g._after_effect();return true
	if a.type=="resource":
		var src=a.src;var target=a.get("target","")
		if src=="E16":evacuate(p,a);return true
		if src=="G091":g.nodes[src].token=0;g.used[src]=true;g._discard(p,a.fee);g._draw(p,"resource")
		elif src=="G093":g.nodes[src].token=0;g.used[src]=true;g.nodes[target].token=1;g.recharged[target]=true
		else:
			if g.card(src).action:g.nodes[src].token=0
			match src:
				"E11":g.nodes[target].compute=true
				"E12":
					remove(src);var opposing="support_d" if p==g.battle.attacker else "support_a";g.battle[opposing]=maxi(0,g.battle[opposing]-8)
				"E15":remove(src);g.battle.fixed_dice=[4,4]
				"E01":g.battle.bonus_a+=3
				"E02":remove(src);g.nodes[target].token=1;g.nodes[target].battery_power=4;g.recharged[target]=true
				"E06":
					var cards: Array=[]
					for i in 2:
						var drawn=g._draw(p,"group")
						if drawn!="":cards.append(drawn)
					if not cards.is_empty():g._set_choice(p,"量子计算机 · 保留1张团体",cards,"e_keep",{"new_cards":cards})
				"E07":remove(src);g.battle.bonus_d+=10
				"E08":
					probe(p,3,true)
				"E10":g.nodes[target].parent=a.parent
		g._log(g._who(p)+" · "+a.label,"resource",{"id":src,"target":target,"player":p})
		if not g.battle.is_empty():g._battle_record("resource",p,src,target,a.label,"已生效");g._response_changed(p)
		else:g._after_effect()
		return true
	if a.type=="choose" and g.choice.get("kind","").begins_with("e_"):
		var c=g.choice;g.choice={};g.phase="main"
		if c.kind in ["e_discard","e_limit"]:g._discard(p,a.id)
		elif c.kind=="e_keep":
			for id in c.new_cards:
				if id!=a.id:g._discard(p,id)
		elif c.kind=="e_probe":
			if a.id!="":g.hands[p][g.card(a.id).kind].append(a.id);g._flow(a.id,"choice","hand",p)
			for id in c.peek:
				if id!=a.id:g.decks.resource.append(id)
		g._after_effect();return true
	return false
func evacuate(p: int,a: Dictionary) -> void:
	var b=g.battle.duplicate(true);var values=g.battle_values();var target=a.target
	g._battle_record("resource",p,a.src,target,a.label,"已生效")
	b.entries=g.battle.entries.duplicate(true)
	remove(a.src);g._return_subtree(target)
	for id in b.spent:g.discards.plot.push_front(id)
	# Evacuation cancels combat; it is neither a failed roll nor a capture.
	# Paid actions stay spent, and no completed-battle abilities are triggered.
	b.merge({"values":values,"dice":[],"success":false,"cancelled":true,"rescued":false,"destroyed":false,"devastated":false,"guarded":false},true)
	g.last_battle=b;g.battle={};g.phase="main"
	g._log(g._who(p)+" · 紧急转移 · "+g.title(target)+" · 攻击取消","resource",{"id":a.src,"target":target,"player":p})
	g._after_effect()
func resolve_plot(a: Dictionary) -> bool:
	if a.id not in PLOTS:return false
	match a.id:
		"P56":remove(a.target)
		"P57":probe(a.player,2,false)
		"P58":g.nodes[a.target].silenced=true
		"P59":
			var previous=g.owner(a.target);g.nodes.erase(a.target);g.hands[a.player].resource.append(a.target)
			g._flow(a.target,"board","hand",a.player);g.motion_events.back().from_player=previous
			g._log(g._who(a.player)+"征用了「"+g.title(a.target)+"」","resource_transfer",{"id":a.target})
		"P60":
			var own=g.nodes[a.other];var enemy=g.nodes[a.target];var old_slot=own.resource_slot
			own.owner=enemy.owner;own.resource_slot=enemy.resource_slot;enemy.owner=a.player;enemy.resource_slot=old_slot
			for id in [a.other,a.target]:g.nodes[id].token=0;g.captured[id]=true
			g._log("技术交换 · "+g.title(a.other)+" ↔ "+g.title(a.target),"resource_swap",{"id":a.other,"target":a.target})
	g._spent_plot(a.id);g.wave.plot_rewards(a.player,a.id,a);g._after_effect();return true
func probe(p: int,n: int,optional: bool) -> void:
	var peek=g._take(p,"resource",mini(n,g.decks.resource.size()))
	g._set_choice(p,"选择1张资源加入手牌",peek,"e_probe",{"peek":peek},optional)
func presentation_cards(a: Dictionary) -> Array:
	var out: Array=[]
	if a.type in ["deploy","resource","research"]:out.append(a.get("id",a.get("src","")))
	if a.type=="deploy" and a.has("fee"):out.push_front("G098")
	return out
func context(id: String) -> Dictionary:
	return {"on_board":true,"resource":true,"owner":g.owner(id),"token":g.nodes[id].token,"active":ready(id),"captured":g.captured.has(id),"recharged":g.recharged.has(id),"slot":g.nodes[id].resource_slot}
func reader(id: String) -> String:
	var c=g.card(id)
	if id in g.scrap:return "已报废 · 本局不回收。"
	if id in g.discards.resource:return "资源弃牌堆 · 资源堆用尽时洗回。"
	if not g.nodes.has(id):return "资源 · "+c.category+" · "+c.mode+"\n尚未部署。主要阶段花主牌1行动，每回合可部署1次，与自动接管分别限次。"
	var text=("己方" if g.owner(id)==0 else "对方")+"资源 · "+("左侧" if g.nodes[id].resource_slot==0 else "右侧")+"\n在场资源 %d / 2"%field(g.owner(id)).size()
	text+="\n资源手牌 %d / %d"%[g.hands[g.owner(id)].resource.size(),g.resource_hand_limit(g.owner(id))]
	if c.action:
		text+="\n行动 %d / 1"%g.nodes[id].token
		if g.captured.has(id):text+=" · 本回合进场，不能获得行动"
		elif g.recharged.has(id):text+=" · 本回合额外恢复已用"
	else:text+="\n"+{"持续":"持续生效 · 无需行动","触发":"满足条件自动触发 · 无需行动","一次性":"报废自身发动 · 无需行动"}.get(c.mode,c.mode)
	if not ready(id):text+="\n技术封锁 · 失效至本回合结束"
	if id=="E04" and g.used.has("e_archive"):text+="\n本回合抽牌次数已用"
	if id=="E13" and g.used.has("e_museum:%d"%g.owner(id)):text+="\n本回合抽牌次数已用"
	if id=="E20" and g.used.has("community_solar"):text+="\n本回合抽牌次数已用"
	if id=="E16" and can_evacuate(g.owner(id)):text+="\n紧急转移 · 可在本次防守响应时使用"
	return text

func deploy(p: int,a: Dictionary) -> void:
	var slot=g.nodes[a.replace].resource_slot if a.get("replace","")!="" else (1 if field(p).any(func(k):return g.nodes[k].resource_slot==0) else 0)
	if a.get("replace","")!="":remove(a.replace)
	if a.has("fee"):g._discard(p,a.fee)
	elif not a.get("free",false):g.spend(g.root(p))
	g.deploy_used=true;g.hands[p].resource.erase(a.id)
	g.nodes[a.id]={"card":a.id,"owner":p,"parent":"","token":0,"attached":[],"resource_slot":slot}
	g._flow(a.id,"hand","resource_left" if slot==0 else "resource_right",p)
	g.captured[a.id]=true
	g._log(g._who(p)+"部署了「"+g.title(a.id)+"」","deploy",{"id":a.id,"player":p})
	g.contemporary.deployed(p,a.id)
