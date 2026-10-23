extends "res://tests/test_contemporary.gd"
const Planner=preload("res://scripts/ai_planner.gd")

func compare_profiles(g: GameState,p: int):
	var o=g.observation(p,false);var baseline={};var before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state])
	for level in ["easy","normal","hard"]:
		var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=811
		var search=Planner.new(o,level,41,bot.heuristic_pick,bot.heuristic_value)
		var expected={"easy":1,"normal":2,"hard":4}[level] if o.phase=="main" else 1
		check(search.max_depth==expected,"Selected horizon reaches the common planner: "+level+"/"+o.phase)
		var values=o.actions.map(func(a):return bot.heuristic_value(a,o))
		var fallback=bot.heuristic_pick(o)
		var profile={"width":search.width,"nodes":search.max_nodes,"job_budget":search.job_budget,"candidates":search.candidates,"samples":search.samples.map(func(s):return JSON.stringify([s.hands,s.decks,s.rng.state])),"scores":values,"fallback":fallback,"rng":bot.rng.state}
		if baseline.is_empty():baseline=profile
		else:check(profile==baseline,"Identical scoring, breadth, budget, samples and tie breaking; only depth differs: "+level+"/"+o.phase)
	check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"All difficulty profiles preserve the real game")

func run():
	var g=fresh();put(g,"G001");put(g,"G005");put(g,"G076",1);give(g,"G043");give(g,"P30");give(g,"E06")
	compare_profiles(g,0)
	# Real crowded boards also share the same automatic budget reduction.
	g=fresh()
	for i in range(1,25):
		var p=i%2;var parents=g.field(p).filter(func(id):return g.can_parent(id))
		put(g,"G%03d"%i,p,parents[0])
	for i in range(71,81):give(g,"G%03d"%i)
	check(g.legal_actions(0).size()>500,"Fixture reaches the crowded-board policy")
	compare_profiles(g,0)
	g=fresh();put(g,"G005");put(g,"G076",1);give(g,"P12");give(g,"P15",1)
	g._launch_attack(0,{"src":"R0","target":"G076","mode":"control"})
	compare_profiles(g,1)
	var decisions=[]
	for level in ["easy","normal","hard"]:
		var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=117;decisions.append(bot.pick(g.observation(1,false)))
	check(decisions[0]==decisions[1] and decisions[1]==decisions[2],"Complete battle responses use the same policy without a random-pass handicap")
	g.battle.responder=0;g.act(0,action(g,0,"plot",{"id":"P12"}));compare_profiles(g,1)
	# Preparation has no lasting value alone. Two plies can see the actual attack
	# that follows; a one-ply player must not receive a special per-card shortcut.
	g=fresh();put(g,"G001");put(g,"G005");put(g,"G076",1);give(g,"P30")
	g.nodes.R0.token=0;g.nodes.G005.learned=22;g.wave.plans[0]=[1,1]
	for level in ["easy","normal","hard"]:
		var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=217
		var trial=ActionFlow.copy_state(g);var selected=bot.pick(trial.observation(0,false))
		if level=="easy":check(selected.type=="end","One ply does not invent value for an unconsumed preparation")
		else:
			check(selected.type=="plot" and selected.id=="P30" and selected.payer=="G001","Longer horizon finds preparation followed by a useful attack: "+level)
			trial.act(0,selected);var next=bot.pick(trial.observation(0,false))
			check(next.type=="attack" and next.src=="G005" and next.target=="G076","The preparation is actually followed by its attack: "+level)
	print("AI DEPTH LEVELS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
