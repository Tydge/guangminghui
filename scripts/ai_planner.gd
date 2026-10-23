extends RefCounted
## Short plans on information-set samples. No live GameState, RNG, enemy hand or deck order.
const Structure=preload("res://scripts/ai_structure.gd")
const Tactics=preload("res://scripts/ai_tactics.gd")
const RESOURCE_FIELD_VALUE=14.0
const RESOURCE_READY_HAND_VALUE=3.0
const RESOURCE_BACKUP_HAND_VALUE=1.0
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
var job_budget=8
var placement_cache={}

static func applicable(o: Dictionary) -> bool:
	return o.has("public_state") and o.actions.size()>1 and ((o.get("phase","")=="main" and o.get("current",-1)==o.player) or o.get("phase","") in ["battle","plot_response"])

static func shortlist(o: Dictionary,limit: int=64,placements: Dictionary={},affinities: Dictionary={}) -> Array:
	if o.phase not in ["main","battle","plot_response"] or o.actions.size()<=limit:return o.actions
	var ranked=[];var cache={};var branches={}
	for id in o.nodes:
		var c=CardDB.get_card(o.nodes[id].card).duplicate();c.merge(o.effective[id],true);cache[id]=c
		var ancestor=id
		while o.nodes.has(ancestor):
			branches[ancestor]=branches.get(ancestor,0)+1;ancestor=o.nodes[ancestor].parent
	for a in o.actions:
		var src=a.get("src","");var target=a.get("target",a.get("id",""));var c=cache.get(target,CardDB.get_card(target));var value=0.0
		match a.type:
			"end":value=10000
			"plot":value=9000 if CovenantRules.PLOTS.has(a.id) else 10
			"auto":value=20+c.p+c.slots+placements.get(JSON.stringify([a.id,a.parent]),0.0)
			"attack":
				var defender=c.get("defense_control",c.get("r",0)) if a.mode=="control" else c.get("defense_destroy",c.get("p",0))
				value=10+cache[src].p-defender+c.get("p",0)*0.2
				value+=affinities.get(JSON.stringify([src,target]),0)*(1 if a.mode=="control" else -1)
				if o.nodes.has(target) and o.nodes[target].owner!=o.player:value+=maxi(0,branches.get(target,1)-1)*2.5
				if a.get("use_plan",false):value+=1
			"deploy":value=16
			"ability","resource","rebuild":value=12
			"research":value=4
			"move":value=-5
			"support","self_defend":
				value=a.get("power",0)*2+int(a.get("nature",false))*2
				if a.has("plot_fee"):value-=3
				if a.has("resource_fee"):value-=8
				if a.has("group_fee"):value-=3
			"pass","accept_plot","counter","trick","fact_check":value=10000
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
	g.battle=o.battle.duplicate(true);g.pending_plot=o.pending_plot.duplicate(true)
	g.resume_phase="battle" if not g.battle.is_empty() else "main"
	var known=g.battle.get("spent",[]).duplicate()
	if not g.pending_plot.is_empty():known.append(g.pending_plot.id)
	if g.battle.get("hand_target",false):known.append(g.battle.target)
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
	max_depth=4 if level=="hard" else 2;width=2 if level=="hard" else 1;max_nodes=128 if level=="hard" else 24
	# Responses compare the complete battle, not an entire subsequent main phase
	# again after every helper. The next main decision replans from its real result.
	if o.phase!="main":max_depth=1
	var root_width=8 if level=="hard" else 5
	if o.actions.size()>120:width=1;root_width=6 if level=="hard" else 4;max_nodes=40 if level=="hard" else 20
	if o.actions.size()>500:root_width=4;max_nodes=24 if level=="hard" else 16
	for i in 2:
		var g=model(o,seed_value+i*104729)
		if g==null:done=true;return
		samples.append(g)
	candidates=rank(o,root_width,samples[0])
	for a in o.actions:
		if a.type in ["end","pass","accept_plot"] and a not in candidates:candidates.append(a)
	# Root commands originate in the observation; verify against both reconstructed
	# models once. Descendants already originate in their model's legal action list.
	for sample in samples:
		var legal=sample.legal_actions(player)
		candidates=candidates.filter(func(a):return a in legal)
	for i in candidates.size():
		scores.append([-INF,-INF])
		for s in samples.size():jobs.append({"root":i,"sample":s})
	job_budget=maxi(2,max_nodes/maxi(1,jobs.size()))
	done=jobs.is_empty()

func rank(o: Dictionary,limit: int,g: GameState=null) -> Array:
	if o.phase=="battle":
		o=o.duplicate();o.support_budget=Tactics.support_budget(o)
	var ranked=[];var placements={};var affinities={}
	if g!=null:
		var shape=g.nodes.duplicate(true)
		for id in shape:shape[id].erase("token")
		var board_key=JSON.stringify([shape,g.world,g.used,g.factions])
		placements=placement_cache.get(board_key,{})
		for a in o.actions:
			if a.type=="auto":
				var key=JSON.stringify([a.id,a.parent])
				if not placements.has(key):placements[key]=Structure.placement_hint(g,a)
		placement_cache[board_key]=placements
		for a in o.actions:
			if a.type=="attack":
				var pair=JSON.stringify([a.src,a.target])
				if not affinities.has(pair):affinities[pair]=4*(g._common(a.src,a.target)-g._opposed(a.src,a.target))
	for a in shortlist(o,64,placements,affinities):
		var context=o
		if g!=null and a.type=="attack":
			context=o.duplicate();context.previews={}
			var v=g.attack_preview(a.src,a.target,a.mode,a)
			# Full P support can be much larger than summed GP. Ask the actual rule
			# helpers for both sides before pruning attacks from the search.
			var battle={"src":a.src,"target":a.target,"mode":a.mode,"attacker":o.player,"defender":g.owner(a.target),"solo":a.get("solo",false)}
			v.support_max=0;v.enemy_support_max=0
			for id in g.field(o.player):
				if id!=a.src and id!=a.get("delegate","") and g.token(id):v.support_max+=g.support_power(id,battle)
			if g.owner(a.target)>=0:
				for id in g.field(g.owner(a.target)):
					if id!=a.target and g.token(id):v.enemy_support_max+=g.support_power(id,battle)
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
		var p=responding_player(g)
		var o=g.observation(p,false)
		if o.actions.is_empty() or not g._act_generated(p,policy.call(o)):return false
	return false

static func responding_player(g: GameState) -> int:
	if g.phase=="battle":return g.battle.responder
	if g.phase=="plot_response":return 1-g.pending_plot.player
	return g.choice.player

func utility(g: GameState) -> float:
	if g.phase=="over":return 10000 if g.winner==player else (-10000 if g.winner==1-player else -5)
	var value=0.0
	for p in [player,1-player]:
		var side=1.0 if p==player else -1.0
		for id in g.groups(p):
			# Even a small group supplies another recurring action and may carry an
			# important passive. Removing enemy bodies matters beyond printed Power.
			var group_value=4+g.stat(id,"p")*1.6+g.stat(id,"gp")*1.4+g.stat(id,"slots")*0.5
			if g.wave.devastated(id):group_value*=0.5
			if p==player and g.current!=p and g.token(id):group_value+=1+g.stat(id,"p")*0.35
			value+=side*group_value
		value+=side*Structure.quality(g,p)
		var progress=g.goal(p)
		var resources=g.resources.field(p).size()
		value+=side*(goal_value(progress,CovenantRules.FACTIONS[g.factions[p]])+resources*RESOURCE_FIELD_VALUE)
		if p==player:
			# This is an end-of-turn value. Resource actions cannot help on the enemy's
			# turn and refill next turn: hoarding a main-phase-only action is not income.
			var ready_resources=mini(g.hands[p].resource.size(),maxi(0,2-resources))
			var backups=g.hands[p].resource.size()-ready_resources
			value+=group_reserve(g,p)+g.hands[p].plot.size()*2
			value+=ready_resources*RESOURCE_READY_HAND_VALUE+backups*RESOURCE_BACKUP_HAND_VALUE
			if g.current!=p:value+=g.nodes[g.root(p)].token*2
			for id in g.covenant.held(p):
				value+=goal_value(g.covenant.progress(p,id),CovenantRules.PLOTS[id])*0.5
		else:value-=g.hands[p].plot.size()*1.2+g.hands[p].resource.size()
	return value

static func goal_value(progress: Dictionary,rule: Dictionary) -> float:
	# Reward every actual requirement as well as the bottleneck. A faction missing
	# one scarce trait must not treat unrelated raw Power as a substitute for victory.
	var total=0.0;var count=0
	for key in rule:
		if key=="traits":continue
		total+=minf(1.0,float(progress.values.get(key,0))/rule[key]);count+=1
	return 60*total/maxi(1,count)+180*pow(progress.ratio,3)

static func group_reserve(g: GameState,p: int) -> float:
	var values=[];var rule=CovenantRules.FACTIONS[g.factions[p]]
	for id in g.hands[p].group:
		var card=g.card(id);var value=1.0+(card.p*1.6+card.gp*1.4)*0.12
		if rule.get("traits",[]).any(func(t):return t in card.tags+card.align):value+=1.5
		values.append(value)
	values.sort();values.reverse();var total=0.0
	for i in values.size():total+=values[i]*pow(0.55,i)
	return total

func finish_value(g: GameState) -> float:
	if g.phase=="main":
		var copy=ActionFlow.copy_state(g)
		# End is unconditional in a main phase. Use the same engine dispatch and
		# cleanup without regenerating hundreds of unrelated attacks to find it.
		copy._act_generated(copy.current,copy._a("end","结束回合"));settle(copy)
		return utility(copy)-0.03
	return utility(g)

func step():
	if done:return
	if jobs.is_empty() or visited>=max_nodes:done=true;return
	var job=jobs.pop_front()
	scores[job.root][job.sample]=explore(samples[job.sample],candidates[job.root],1,mini(max_nodes,visited+job_budget))
	done=jobs.is_empty() or visited>=max_nodes

func explore(source: GameState,a: Dictionary,depth: int,limit: int) -> float:
	if visited>=limit:return finish_value(source)
	visited+=1
	var g=ActionFlow.copy_state(source)
	if not g._act_generated(player,a):return -INF
	var outcomes=settle_distribution(g)
	if outcomes.is_empty():return -INF
	var expected=0.0
	var remaining_outcomes=outcomes.size()
	for outcome in outcomes:
		var state: GameState=outcome.state;var best=finish_value(state)
		var branch_limit=mini(limit,visited+(limit-visited)/remaining_outcomes);remaining_outcomes-=1
		if depth<max_depth and state.phase=="main" and state.current==player and visited<branch_limit:
			for next in rank(state.observation(player,false),width,state):
				if next.type=="end" or visited>=branch_limit:continue
				best=maxf(best,explore(state,next,depth+1,branch_limit))
		expected+=outcome.probability*best
	return expected-0.03

func settle_distribution(g: GameState) -> Array:
	for i in 80:
		if g.phase in ["main","over","draw"]:return [{"state":g,"probability":1.0}]
		var p=responding_player(g)
		var o=g.observation(p,false)
		if o.actions.is_empty():return []
		var a=policy.call(o)
		# Enumerate actual 2d6 sums at the final response. The rule engine decides
		# success, destruction margins, rerolls, rescues, triggers and victory.
		# This removes the old "two lucky sampled rolls" attack valuation.
		if g.phase=="battle" and a.type=="pass" and g.battle.passes==1 and not g.battle.has("rolled") and not g.battle.has("fixed_dice") and not g.battle.get("foiled",false) and g.battle_values().strength>=2:
			var merged={}
			for total in range(2,13):
				var trial=ActionFlow.copy_state(g);trial._die();trial._die()
				trial.battle.rolled=[maxi(1,total-6),mini(6,total-1)]
				if not trial._act_generated(p,a):return []
				for outcome in settle_distribution(trial):
					var state: GameState=outcome.state
					var key=JSON.stringify([state.nodes,state.hands,state.decks,state.discards,state.graves,state.scrap,state.used,state.destroyed,state.exposed,state.locked,state.recharged,state.captured,state.failed_recruits,state.world,state.auto_used,state.deploy_used,state.current,state.turns,state.phase,state.winner,state.rng.state,state.end_requested,state.attacked,state.rewards,state.wave.queue,state.wave.response_queue,state.wave.plans,state.wave.announced])
					var probability=outcome.probability*(6-absi(7-total))/36.0
					if merged.has(key):merged[key].probability+=probability
					else:merged[key]={"state":state,"probability":probability}
			return merged.values()
		if not g._act_generated(p,a):return []
	return []

func result(fallback: Dictionary) -> Dictionary:
	var best=fallback;var value=-INF
	for i in candidates.size():
		if not is_finite(scores[i][0]) or not is_finite(scores[i][1]):continue
		var score=(scores[i][0]+scores[i][1])/2
		if score>value:value=score;best=candidates[i]
	return best
