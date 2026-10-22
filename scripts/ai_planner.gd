extends RefCounted
## Short plans on information-set samples. No live GameState, RNG, enemy hand or deck order.
const Structure=preload("res://scripts/ai_structure.gd")
var player=0
var level="normal"
var policy: Callable
var evaluator: Callable
var candidates: Array=[]
var samples: Array=[]
var scores: Array=[]
var jobs: Array=[]
var visited=0
var done=false
var max_depth=2
var width=1
var max_nodes=32

static func applicable(o: Dictionary) -> bool:return o.get("phase","")=="main" and o.get("current",-1)==o.player and o.has("public_state") and o.actions.size()>1

static func shortlist(o: Dictionary,limit: int=64,placements: Dictionary={}) -> Array:
	if o.phase!="main" or o.actions.size()<=limit:return o.actions
	var ranked=[];var cache={}
	for id in o.nodes:
		var c=CardDB.get_card(o.nodes[id].card).duplicate();c.merge(o.effective[id],true);cache[id]=c
	for a in o.actions:
		var src=a.get("src","");var target=a.get("target",a.get("id",""));var c=cache.get(target,CardDB.get_card(target));var value=0.0
		match a.type:
			"end":value=10000
			"plot":value=9000 if CovenantRules.PLOTS.has(a.id) else 10
			"auto":value=20+c.p+c.slots+placements.get(JSON.stringify([a.id,a.parent]),0.0)
			"attack":
				var defender=c.get("defense_control",c.get("r",0)) if a.mode=="control" else c.get("defense_destroy",c.get("p",0))
				value=10+cache[src].p-defender+c.get("p",0)*0.2
				if a.get("use_plan",false):value+=1
			"deploy":value=16
			"ability","resource","rebuild":value=12
			"research":value=4
			"move":value=-5
		if a.has("fee"):value-=CardDB.get_card(a.fee).get("p",2)*0.15
		ranked.append({"action":a,"value":value})
	ranked.sort_custom(func(a,b):return a.value>b.value)
	var buckets={};var counts={}
	for entry in ranked:
		var a=entry.action;var key=JSON.stringify([a.type,a.get("src",a.get("id","")),a.get("mode","")])
		if counts.get(key,0)>=3:continue
		counts[key]=counts.get(key,0)+1
		if not buckets.has(a.type):buckets[a.type]=[]
		buckets[a.type].append(a)
	var selected=[]
	while selected.size()<limit:
		var before=selected.size()
		for kind in buckets:
			if not buckets[kind].is_empty():selected.append(buckets[kind].pop_front())
			if selected.size()>=limit:break
		if selected.size()==before:break
	return selected

static func model(o: Dictionary,seed_value: int) -> GameState:
	var g=GameState.new(seed_value);g.nodes=o.nodes.duplicate(true);g.factions=o.factions.duplicate();g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}]
	g.hands[o.player]=o.hands.duplicate(true);g.discards=o.discards.duplicate(true);g.graves=o.graves.duplicate(true);g.scrap=o.scrap.duplicate();g.phase=o.phase;g.current=o.current;g.world=o.world;g.turns=o.turns.duplicate()
	for key in o.public_state:
		if key!="wave":
			var value=o.public_state[key];g.set(key,value.duplicate(true) if value is Array or value is Dictionary else value)
	for key in o.public_state.wave:g.wave.set(key,o.public_state.wave[key].duplicate(true))
	g.rng.seed=seed_value
	var known=[]
	for id in g.nodes:
		if not g.is_root(id):known.append(id)
		known.append_array(g.nodes[id].attached)
	known.append(g.world);known.append_array(g.scrap)
	for grave in g.graves:known.append_array(grave)
	var enemy=1-o.player
	for kind in g.decks:
		known.append_array(g.discards[kind]);known.append_array(g.hands[o.player][kind]);g.hands[enemy][kind]=o.revealed.get(kind,[]).duplicate();known.append_array(g.hands[enemy][kind])
	for kind in g.decks:
		var pool=CardDB.ids(kind).filter(func(id):return id not in known);g._shuffle(pool)
		var missing=o.opponent_counts[kind]-g.hands[enemy][kind].size()
		for i in missing:
			var index=0
			if kind=="plot" and g.hands[enemy].plot.any(func(id):return g.covenant.is_goal(id)):
				while index<pool.size()-1 and g.covenant.is_goal(pool[index]):index+=1
			if pool.is_empty():return null
			g.hands[enemy][kind].append(pool.pop_at(index))
		g.decks[kind]=pool
		if pool.size()!=o.decks[kind]:return null
	return g

func _init(o: Dictionary,difficulty: String,seed_value: int,pick_policy: Callable,score_policy: Callable):
	player=o.player;level=difficulty;policy=pick_policy;evaluator=score_policy
	max_depth=3 if level=="hard" else 2;width=2 if level=="hard" else 1;max_nodes=128 if level=="hard" else 24
	var root_width=8 if level=="hard" else 5
	if o.actions.size()>120:width=1;root_width=6 if level=="hard" else 4;max_nodes=40 if level=="hard" else 20
	if o.actions.size()>500:root_width=4;max_nodes=24 if level=="hard" else 16
	for i in 2:
		var g=model(o,seed_value+i*104729)
		if g==null:done=true;return
		samples.append(g)
	candidates=rank(o,root_width,samples[0])
	for a in o.actions:
		if a.type=="end" and a not in candidates:candidates.append(a)
	for i in candidates.size():
		scores.append([-INF,-INF])
		for s in samples.size():jobs.append({"root":i,"sample":s,"state":samples[s],"action":candidates[i],"depth":1})
	done=jobs.is_empty()

func rank(o: Dictionary,limit: int,g: GameState=null) -> Array:
	var ranked=[];var global_power=[0,0];var placements={}
	if g!=null:
		for id in g.nodes:
			if g.card(id).kind!="resource" and g.token(id):global_power[g.owner(id)]+=g.stat(id,"gp")
		for a in o.actions:
			if a.type=="auto":
				var key=JSON.stringify([a.id,a.parent])
				if not placements.has(key):placements[key]=Structure.placement_hint(g,a)
	for a in shortlist(o,24,placements):
		var context=o
		if g!=null and a.type=="attack":
			context=o.duplicate();context.previews={}
			var v=g.attack_preview(a.src,a.target,a.mode,a)
			# A cheap ordering estimate only. Full support eligibility and card effects
			# are resolved by the rules engine in each simulated battle, not duplicated here.
			v.support_max=maxi(0,global_power[player]-g.stat(a.src,"gp")) if not a.get("solo",false) else 0
			v.enemy_support_max=maxi(0,global_power[1-player]-g.stat(a.target,"gp")) if g.owner(a.target)>=0 else 0
			v.self_max=g.self_power(a.target) if g.nodes.has(a.target) and g.token(a.target) and not v.get("no_self",false) else 0
			context.previews[JSON.stringify(a)]=v
		elif g!=null and a.type=="plot" and a.id in GameState.WaveRules.DISASTERS:
			context=o.duplicate();context.previews={JSON.stringify(a):g.wave.disaster_preview(a)}
		var value=evaluator.call(a,context)
		if a.type=="auto":value+=placements.get(JSON.stringify([a.id,a.parent]),0.0)
		ranked.append({"action":a,"value":value})
	ranked.sort_custom(func(a,b):return a.value>b.value)
	var result=[];var counts={}
	for entry in ranked:
		var a=entry.action;var key=JSON.stringify([a.type,a.get("src",a.get("id",""))])
		if counts.get(key,0)>=2:continue
		counts[key]=counts.get(key,0)+1;result.append(a)
		if result.size()>=limit:break
	return result

func settle(g: GameState) -> bool:
	for i in 80:
		if g.phase in ["main","over","draw"]:return true
		var p=0 if not g.legal_actions(0).is_empty() else 1
		var o=g.observation(p,false)
		if o.actions.is_empty() or not g.act(p,policy.call(o)):return false
	return false

func utility(g: GameState) -> float:
	if g.phase=="over":return 10000 if g.winner==player else (-10000 if g.winner==1-player else -5)
	var value=0.0
	for p in [player,1-player]:
		var side=1.0 if p==player else -1.0
		for id in g.groups(p):
			var group_value=g.stat(id,"p")*1.6+g.stat(id,"gp")*1.4+g.stat(id,"slots")*0.5
			if g.wave.devastated(id):group_value*=0.5
			if p==player and g.token(id):group_value+=1+g.stat(id,"p")*0.35
			value+=side*group_value
		value+=side*Structure.quality(g,p)
		var ratio=g.goal(p).ratio
		value+=side*(20*ratio+50*pow(ratio,2)+g.resources.field(p).size()*5)
		if p==player:
			for id in g.resources.field(p):
				if g.card(id).action and g.token(id):value+=0.8
			value+=g.hands[p].group.size()*0.8+g.hands[p].plot.size()*2+g.hands[p].resource.size()*2
			value+=g.nodes[g.root(p)].token*2
			for id in g.covenant.held(p):
				var progress=g.covenant.progress(p,id).ratio;value+=10*progress+30*pow(progress,2)
		else:value-=g.hands[p].plot.size()*1.2+g.hands[p].resource.size()
	return value

func finish_value(g: GameState) -> float:
	if g.phase=="main" and g.current==player:
		var copy=ActionFlow.copy_state(g)
		for a in copy.legal_actions(player):
			if a.type=="end":
				copy.act(player,a);settle(copy);return utility(copy)-0.03
	return utility(g)

func step():
	if done:return
	if jobs.is_empty() or visited>=max_nodes:done=true;return
	var job=jobs.pop_front();var g=ActionFlow.copy_state(job.state);visited+=1
	if g.act(player,job.action) and settle(g):
		scores[job.root][job.sample]=maxf(scores[job.root][job.sample],finish_value(g)-job.depth*0.03)
		if job.depth<max_depth and g.phase=="main" and g.current==player:
			var o=g.observation(player,false)
			for a in rank(o,width,g):jobs.append({"root":job.root,"sample":job.sample,"state":g,"action":a,"depth":job.depth+1})
	done=jobs.is_empty() or visited>=max_nodes

func result(fallback: Dictionary) -> Dictionary:
	var best=fallback;var value=-INF
	for i in candidates.size():
		if not is_finite(scores[i][0]) or not is_finite(scores[i][1]):continue
		var score=(scores[i][0]+scores[i][1])/2
		if score>value:value=score;best=candidates[i]
	return best
