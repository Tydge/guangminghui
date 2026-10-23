extends "res://tests/test_contemporary.gd"
const Planner=preload("res://scripts/ai_planner.gd")
var test_bot=AiAgent.new()
func search(g: GameState):
	test_bot.difficulty="hard"
	return Planner.new(g.observation(0,false),"hard",187,test_bot.heuristic_pick,test_bot.heuristic_value)
func run():
	var g=fresh();put(g,"G005");put(g,"G076",1);give(g,"G043");g.nodes.R0.token=0;g.nodes.R1.token=0
	var planner=search(g)
	g._launch_attack(0,{"src":"G005","target":"G043","mode":"control"});g.battle.bonus_a+=6-g.battle_values().strength
	check(search(g).max_depth==1,"Response search evaluates the complete battle without repeatedly expanding the following main phase")
	var before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state,g.battle]);var branches=planner.settle_distribution(ActionFlow.copy_state(g));var probability=0.0;var success=0.0
	for branch in branches:
		probability+=branch.probability
		if branch.state.nodes.has("G043"):success+=branch.probability
	check(branches.size()==2 and is_equal_approx(probability,1.0),"Equivalent ordinary battle outcomes merge into a normalized distribution")
	check(is_equal_approx(success,15.0/36),"Strength six is evaluated at its true 2d6 success probability")
	check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state,g.battle]),"Chance enumeration never changes the live battle or RNG")
	g.battle.fixed_dice=[3,4];branches=planner.settle_distribution(ActionFlow.copy_state(g));check(branches.size()==1 and not branches[0].state.nodes.has("G043"),"Fixed dice are resolved as the known outcome rather than averaged")
	g=fresh();put(g,"G005");put(g,"G071",1);g.nodes.R0.token=0;g.nodes.R1.token=0;planner=search(g)
	g.wave.start_disaster({"id":"P31","payer":"G005","target":"G071","player":0});g.battle.bonus_a+=8-g.battle_values().strength
	branches=planner.settle_distribution(ActionFlow.copy_state(g));var destroyed=0.0;var devastated=0.0;var survived=0.0
	for branch in branches:
		var state: GameState=branch.state
		if not state.nodes.has("G071"):destroyed+=branch.probability
		elif state.wave.devastated("G071"):devastated+=branch.probability
		else:survived+=branch.probability
	check(is_equal_approx(destroyed,6.0/36) and is_equal_approx(devastated,20.0/36) and is_equal_approx(survived,10.0/36),"The real disaster rules preserve separate destruction, devastation and failure probabilities")
	var rule={"groups":6,"power":28};var one={"ratio":0.2,"values":{"groups":2,"power":6}};var two={"ratio":0.2,"values":{"groups":3,"power":6}}
	check(Planner.goal_value(two,rule)>Planner.goal_value(one,rule),"Progress on a non-bottleneck requirement still has strategic value")
	g=fresh();put(g,"G005");put(g,"G001",0,"G005");put(g,"G002",0,"G005");put(g,"G003",0,"G002");put(g,"G053",1);put(g,"G033",1,"G053");g.nodes.R1.token=0;g.nodes.G053.token=0;g.nodes.G033.token=0
	test_bot.rng.seed=291;var snapshot=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]);var chosen=test_bot.pick(g.observation(0,false))
	check(chosen.type=="attack" and chosen.mode=="control" and chosen.target=="G053","Recognize a profitable whole-branch capture enabled by full P support: "+str(chosen))
	check(snapshot==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"Strategic branch-capture planning preserves real rules and RNG")
	# Ongoing battles have committed cards outside either hand. The reconstruction
	# must keep those public cards out of the unknown pool, including pending Plots.
	g=fresh();put(g,"G005");put(g,"G076",1);give(g,"G043");give(g,"P12");give(g,"P15",1)
	g._launch_attack(0,{"src":"G005","target":"G043","mode":"control"})
	for p in [0,1]:
		var sampled=Planner.model(g.observation(p,false),91)
		check(sampled!=null and sampled.validate().is_empty() and sampled.battle==g.battle,"Both sides reconstruct committed hand targets without duplicating hidden cards")
	g.battle.responder=0;g.act(0,action(g,0,"plot",{"id":"P12"}))
	check(g.phase=="plot_response","Fixture opens the real counter window")
	for p in [0,1]:
		var sampled=Planner.model(g.observation(p,false),92)
		check(sampled!=null and sampled.validate().is_empty() and sampled.pending_plot==g.pending_plot and sampled.resume_phase=="battle","Pending Plot and spent cards reconstruct with the actual response phase")
	# A fixed failure needs no additional defense. A fixed success on the final
	# surviving group deserves the Phoenix resource even when it must be scrapped.
	g=fresh();put(g,"G001");put(g,"G076",1);put(g,"E07",1);g.turns=[3,3];g.nodes.G001.token=0;g.nodes.R1.token=0;g.nodes.G076.token=0
	g._launch_attack(0,{"src":"R0","target":"G076","mode":"destroy"});g.battle.fixed_dice=[3,4];g.battle.bonus_a+=6-g.battle_values().strength
	test_bot.rng.seed=31;chosen=test_bot.pick(g.observation(1,false));check(chosen.type=="pass","Do not scrap a defensive resource against a fixed failing attack")
	g.battle.bonus_a+=1;test_bot.rng.seed=31;chosen=test_bot.pick(g.observation(1,false))
	check(chosen.type=="resource" and chosen.src=="E07","Generic battle search spends a resource to prevent actual elimination")
	print("AI EXPECTATION: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
