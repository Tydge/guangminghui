extends "res://tests/test_ai_rehearsal.gd"
const Planner=preload("res://scripts/ai_planner.gd")

func probe(g: GameState,p: int,level: String):
	give(g,"P13",1-p)
	var original=g.observation(p,false);var rules=JSON.stringify(CardDB.cards)
	var before=state_key(g);var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=811
	var first=bot.pick(original);var sample=Planner.model(original,331)
	check(first in original.actions and before==state_key(g),"Decision is legal and cannot mutate any live rule state: "+level+"/"+g.phase)
	# Change facts that this player cannot see, including the next actual dice.
	g.hands[1-p].plot.erase("P13");g.decks.plot.append("P13")
	g.decks.plot.erase("P14");g.hands[1-p].plot.append("P14")
	for kind in g.decks:g.decks[kind].reverse()
	g.rng.randi()
	var altered=g.observation(p,false);before=state_key(g);bot.rng.seed=811
	var second=bot.pick(altered);var other=Planner.model(altered,331)
	check(original==altered,"Actual enemy hand, deck order and RNG are absent from observation: "+level+"/"+g.phase)
	check(first==second,"Unseen permutations cannot change the selected command: "+level+"/"+g.phase)
	check(sample!=null and other!=null and sample.hands==other.hands and sample.decks==other.decks and sample.rng.state==other.rng.state,"Rule samples come only from observation and the AI's independent seed: "+level+"/"+g.phase)
	check(before==state_key(g) and rules==JSON.stringify(CardDB.cards),"Both decisions leave live state and shared card definitions untouched: "+level+"/"+g.phase)
	check(not altered.has("rng") and altered.decks.plot is int and altered.opponent_counts.plot is int,"Policies receive counts instead of true hidden lists: "+level+"/"+g.phase)

func run():
	for level in ["normal","hard"]:
		var g=fresh();put(g,"G001");put(g,"G071",1);probe(g,0,level)
		g=fresh();put(g,"G005");put(g,"G076",1)
		g._launch_attack(0,{"src":"R0","target":"G076","mode":"control"});probe(g,1,level)
		g=fresh();put(g,"G005");put(g,"G076",1);give(g,"P12");give(g,"P15",1)
		g._launch_attack(0,{"src":"R0","target":"G076","mode":"control"});g.battle.responder=0
		g.act(0,action(g,0,"plot",{"id":"P12"}));check(g.phase=="plot_response","Fixture uses the actual counter window")
		probe(g,1,level)
	print("AI FAIRNESS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
