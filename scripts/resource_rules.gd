class_name ResourceRules
extends RefCounted
## Resources belong to a player, never to a branch of the power structure.
const PLOTS=["P56","P57","P58"]
var state: WeakRef
var g:
	get:return state.get_ref()
func _init(game) -> void:state=weakref(game)
func field(p: int) -> Array:return g.nodes.keys().filter(func(id):return g.owner(id)==p and g.card(id).kind=="resource")
func ready(id: String,p: int=-1) -> bool:return g.wave.enabled(id,p) and g.card(id).kind=="resource"
func recoverable(id: String) -> bool:return ready(id) and g.card(id).action and g.can_recharge(id)
func can_draw(p: int) -> bool:return g.hands[p].resource.size()<g.resource_hand_limit(p)
func opening() -> void:
	for p in [0,1]:g._draw(p,"resource")
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
func entry_reward(p: int) -> void:
	if ready("E04",p) and not g.used.has("e_archive"):
		g.used.e_archive=true
		g.wave.defer({"kind":"draw","source":"E04","player":p,"deck":"plot","amount":1,"message":"私人档案库 · 抽1张阴谋"})
func support_detail(id: String,d: Dictionary) -> Dictionary:
	if d.basis=="GP" and d.power>0 and ready("E09",g.owner(id)) and g.has(id,"沿海"):
		d.power+=1;d.extra=d.get("extra",0)+1;d.reason+=" · 海底光缆+1"
	return d
func country_actions(src: String,p: int) -> Array:
	if src!="G093" or not g.wave.available(src,p) or not g.token(src) or g.used.has(src):return []
	var out: Array=[]
	for id in field(p):
		if recoverable(id) and "装置" in g.tags(id):out.append(g._a("resource","军工整备 → "+g.title(id),{"src":src,"target":id}))
	return out
func augment_actions(p: int,out: Array) -> Array:
	if g.phase=="main" and g.current==p:
		if g.token(g.root(p)) and can_draw(p) and (not g.decks.resource.is_empty() or not g.discards.resource.is_empty()):out.append(g._a("research","抽1张资源 · 花主牌1行动",{"src":g.root(p)}))
		if not g.auto_used:
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
						if g.can_recharge(target):out.append(g._a("resource","应急电池 · 报废，恢复1行动",{"src":id,"target":target}))
				"E06":
					if not g.decks.group.is_empty() or not g.discards.group.is_empty():out.append(g._a("resource","量子计算机 · 抽2弃1团体",{"src":id}))
				"E08":
					if can_draw(p) and not g.decks.resource.is_empty():out.append(g._a("resource","深空探测器 · 查看资源堆顶3张",{"src":id}))
				"E10":
					for target in g.groups(p):
						for parent in g.field(p):
							if g.can_parent(parent,target):out.append(g._a("resource","后勤无人机 · 移动整支团体",{"src":id,"target":target,"parent":parent}))
	elif g.phase=="battle" and g.battle.responder==p:
		var b=g.battle
		if not b.has("disaster"):
			if p==b.attacker and ready("E01",p) and g.token("E01"):out.append(g._a("resource","战术雷达 · 强度+2 · 花资源1行动",{"src":"E01","target":b.target}))
			if p==b.defender and b.mode=="destroy" and ready("E07",p):out.append(g._a("resource","凤凰护符 · 防御+6 · 报废资源",{"src":"E07","target":b.target}))
	return out
func plot_actions(id: String,p: int) -> Array:
	var out: Array=[]
	if id=="P57":
		if can_draw(p) and not g.decks.resource.is_empty():out.append(g._a("plot","逆向研发 · 查看2张资源，取1张",{"id":id,"src":id,"target":""}))
	elif g.can_enemy(p):
		for target in field(1-p):
			if id=="P58" and not ready(target):continue
			if id=="P56":
				for payer in g.groups(p):
					if g.token(payer):out.append(g._a("plot","精密爆破 → "+g.title(target),{"id":id,"src":id,"target":target,"payer":payer}))
			else:out.append(g._a("plot","技术封锁 → "+g.title(target),{"id":id,"src":id,"target":target}))
	return out
func handle(p: int,a: Dictionary) -> bool:
	if a.type=="research":
		g.nodes[g.root(p)].token=0;g._draw(p,"resource");g._log(g._who(p)+"花主牌1行动抽取资源","research",{"player":p});g._after_effect();return true
	if a.type=="deploy":
		var slot=g.nodes[a.replace].resource_slot if a.get("replace","")!="" else (1 if field(p).any(func(k):return g.nodes[k].resource_slot==0) else 0)
		if a.get("replace","")!="":remove(a.replace)
		if a.has("fee"):g._discard(p,a.fee)
		else:g.nodes[g.root(p)].token=0
		g.auto_used=true;g.hands[p].resource.erase(a.id)
		g.nodes[a.id]={"card":a.id,"owner":p,"parent":"","token":0,"attached":[],"resource_slot":slot}
		g._flow(a.id,"hand","resource_left" if slot==0 else "resource_right",p)
		g.captured[a.id]=true
		g._log(g._who(p)+"部署了「"+g.title(a.id)+"」","deploy",{"id":a.id,"player":p});g._after_effect();return true
	if a.type=="resource":
		var src=a.src;var target=a.get("target","")
		if src=="G093":g.nodes[src].token=0;g.used[src]=true;g.nodes[target].token=1;g.recharged[target]=true
		else:
			if g.card(src).action:g.nodes[src].token=0
			match src:
				"E01":g.battle.bonus_a+=2
				"E02":remove(src);g.nodes[target].token=1;g.recharged[target]=true
				"E06":
					g._draw(p,"group");g._draw(p,"group");g._set_choice(p,"量子计算机 · 弃1张团体",g.hands[p].group,"e_discard")
				"E07":remove(src);g.battle.bonus_d+=6
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
		elif c.kind=="e_probe":
			if a.id!="":g.hands[p][g.card(a.id).kind].append(a.id);g._flow(a.id,"choice","hand",p)
			for id in c.peek:
				if id!=a.id:g.decks.resource.append(id)
		g._after_effect();return true
	return false
func resolve_plot(a: Dictionary) -> bool:
	if a.id not in PLOTS:return false
	match a.id:
		"P56":remove(a.target)
		"P57":probe(a.player,2,false)
		"P58":g.nodes[a.target].silenced=true
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
	if not g.nodes.has(id):return "资源 · "+c.category+" · "+c.mode+"\n尚未部署。主要阶段花主牌1行动，与自动接管共用每回合1次机会。"
	var text=("己方" if g.owner(id)==0 else "对方")+"资源 · "+("左侧" if g.nodes[id].resource_slot==0 else "右侧")+"\n在场资源 %d / 2"%field(g.owner(id)).size()
	text+="\n资源手牌 %d / %d"%[g.hands[g.owner(id)].resource.size(),g.resource_hand_limit(g.owner(id))]
	if c.action:
		text+="\n行动 %d / 1"%g.nodes[id].token
		if g.captured.has(id):text+=" · 本回合进场，不能获得行动"
		elif g.recharged.has(id):text+=" · 本回合额外恢复已用"
	else:text+="\n"+{"持续":"持续生效 · 无需行动","触发":"满足条件自动触发 · 无需行动","一次性":"报废自身发动 · 无需行动"}.get(c.mode,c.mode)
	if not ready(id):text+="\n技术封锁 · 失效至本回合结束"
	if id=="E04" and g.used.has("e_archive"):text+="\n本回合抽牌次数已用"
	return text
