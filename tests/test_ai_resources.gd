extends "res://tests/test_contemporary.gd"

func quiet() -> GameState:
	var g=fresh();put(g,"G001");put(g,"G076",1)
	g.nodes.G001.token=0;g.nodes.G076.token=0
	return g
func decide(g: GameState,level: String,seed_value: int,p: int=0) -> Dictionary:
	var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=seed_value
	var before=JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.rng.state,g.used])
	var observation=g.observation(p,false);var result=bot.pick(observation)
	check(result in observation.actions,"Resource decision remains legal "+level)
	check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.rng.state,g.used]),"Resource search leaves live match and RNG untouched "+level)
	return result
func run():
	for level in ["easy","normal","hard"]:
		for seed_value in [11,31,241,1009]:
			var g=quiet();put(g,"E06");g.nodes.R0.token=0
			var selected=decide(g,level,seed_value)
			check(selected.type=="resource" and selected.src=="E06","Spend Quantum's otherwise expiring action for a lasting card "+level)
			g=quiet();selected=decide(g,level,seed_value)
			check(selected.type=="research" and selected.deck=="resource","Invest in a resource reserve when both field slots are empty and no takeover is available "+level)
			g=quiet();give(g,"E06");selected=decide(g,level,seed_value)
			check(selected.type=="deploy" and selected.id=="E06","Deploy useful infrastructure instead of passing with a resource in hand "+level)
			g=quiet();put(g,"E08");g.nodes.R0.token=0;selected=decide(g,level,seed_value)
			check(selected.type=="resource" and selected.src=="E08","Probe can build the resource reserve without spending root action "+level)
			g=quiet();put(g,"E08");put(g,"E03");give(g,"E01");give(g,"E02");g.nodes.R0.token=0;selected=decide(g,level,seed_value)
			check(selected.type=="end","Do not force resource use when the hand is full "+level)
			g=quiet();put(g,"E03");put(g,"E21");selected=decide(g,level,seed_value)
			check(not (selected.type=="research" and selected.deck=="resource"),"Occupied field slots reduce the value of paying for another backup "+level)
			g=quiet();put(g,"E03");put(g,"E21");give(g,"E01");selected=decide(g,level,seed_value)
			check(selected.type!="deploy","Do not scrap a deployed Resource merely to inflate usage counts "+level)
			g=quiet();put(g,"E11");g.nodes.R0.token=0;selected=decide(g,level,seed_value)
			check(selected.type=="end","Still reject temporary GP preparation that nobody can use "+level)
			g=quiet();give(g,"G005");give(g,"E03");selected=decide(g,level,seed_value)
			check(selected.type=="auto" and selected.id=="G005","Strong immediate expansion still competes successfully with resource investment "+level)
			g=quiet();put(g,"E01");g._launch_attack(0,{"src":"R0","target":"G076","mode":"destroy"});g.battle.responder=0;g.battle.bonus_a+=6-g.battle_values().strength;selected=decide(g,level,seed_value)
			check(selected.type=="resource" and selected.src=="E01","Use Radar when it improves the current attack "+level)
			g=quiet();put(g,"E07",1);g.turns=[3,3];g.nodes.R1.token=0;g._launch_attack(0,{"src":"R0","target":"G076","mode":"destroy"});g.battle.bonus_a+=6-g.battle_values().strength;selected=decide(g,level,seed_value,1)
			check(selected.type=="resource" and selected.src=="E07","Use a defensive Resource when it saves the target "+level)
	print("AI RESOURCE DECISIONS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
