extends "res://tests/test_contemporary.gd"
const Planner=preload("res://scripts/ai_planner.gd")
func run():
	for level in ["normal","hard"]:
		var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=217
		var g=fresh();put(g,"G083");g.nodes.R0.token=0
		var before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]);var o=g.observation(0)
		var model=Planner.model(o,41);check(model!=null and model.validate().is_empty(),"Redacted planning model conserves the pool "+level)
		var start=Time.get_ticks_msec();var chosen=bot.pick(o)
		check(chosen.type=="end","Planner declines a preparation ability with no subsequent attacker "+level)
		check(JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state])==before,"Planning leaves match, hidden deck and RNG untouched "+level)
		print("PLANNER SAMPLE "+level+": "+JSON.stringify({"milliseconds":Time.get_ticks_msec()-start,"search":bot.last_plan}))
		g=fresh();put(g,"G001");put(g,"G071",1);give(g,"P30");g.nodes.R0.token=0
		chosen=bot.pick(g.observation(0));check(chosen.type=="end","Planner declines an expiring disruption after its payer would be the last attacker "+level)
		g=fresh();put(g,"G023");put(g,"E11");g.nodes.R0.token=0;g.nodes.G023.token=0
		chosen=bot.pick(g.observation(0));check(chosen.type=="end","The same plan evaluation rejects an unused temporary Resource buff "+level)
		g=fresh();put(g,"G046");put(g,"G071",1);g.nodes.R0.token=0;chosen=bot.pick(g.observation(0));check(chosen.type=="end","An expiring free effect also loses to ending immediately when it has no payoff "+level)
		g=fresh();put(g,"G001");put(g,"G005");put(g,"G076",1);give(g,"P30");g.nodes.R0.token=0;g.nodes.G005.learned=22;g.wave.plans[0]=[1,1]
		chosen=bot.pick(g.observation(0));check(chosen.type=="plot" and chosen.id=="P30" and chosen.payer=="G001","Planner finds disruption followed by a successful attack "+level+str(chosen))
		# Different enemy hands/deck orders with the same redacted facts yield identical samples.
		var first=g.observation(0);var second=first.duplicate(true)
		var a=Planner.model(first,81);var b=Planner.model(second,81)
		check(a.hands==b.hands and a.decks==b.decks and a.rng.state==b.rng.state,"Information-set samples depend only on observations "+level)
		g=fresh();put(g,"G001");put(g,"G071",1);give(g,"P12",1);var one=g.observation(0);g.hands[1].plot=["P13"];g.decks.plot.erase("P13");g.decks.plot.append("P12");g.rng.randi();var two=g.observation(0)
		check(one==two,"Enemy secrets and live RNG cannot enter planning snapshots "+level)
		bot.rng.seed=811;var choice1=bot.pick(one);bot.rng.seed=811;var choice2=bot.pick(two);check(choice1==choice2,"Secret permutations cannot change the chosen plan "+level)
	# Compact production observations must retain rule-derived disaster ordering too.
	var disaster=fresh();put(disaster,"G043");put(disaster,"G094",1);give(disaster,"P64")
	var scorer=AiAgent.new();var compact=disaster.observation(0,false)
	var search=Planner.new(compact,"normal",411,scorer.heuristic_pick,scorer.heuristic_value)
	check(search.rank(compact,12,disaster)==search.rank(disaster.observation(0),12,disaster),"Compact snapshots retain the same rule-derived disaster ranking as full previews")
	var large=fresh()
	for i in range(1,25):put(large,"G%03d"%i,i%2)
	for i in range(71,81):give(large,"G%03d"%i)
	var large_bot=AiAgent.new();large_bot.difficulty="hard";large_bot.rng.seed=419;var started=Time.get_ticks_msec();var snapshot=large.observation(0,false);var result=large_bot.pick(snapshot);var elapsed=Time.get_ticks_msec()-started
	check(result in snapshot.actions and large_bot.last_plan.nodes<=128,"Large boards retain legal plans within the fixed node budget")
	check(Planner.shortlist(snapshot).size()<=64 and large.validate().is_empty(),"Large-board candidate pruning preserves the real game")
	print("PLANNER LARGE: "+JSON.stringify({"commands":snapshot.actions.size(),"milliseconds":elapsed,"search":large_bot.last_plan}))
	print("AI PLANNING: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
