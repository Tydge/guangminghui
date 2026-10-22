extends "res://tests/test_contemporary.gd"
func run():
	var choices={};var neutral={}
	for level in ["normal","hard"]:
		choices[level]={};neutral[level]={}
		for faction in ["I01","I03","I09"]:
			var g=fresh(faction)
			for id in ["G071","G025","G028"]:give(g,id)
			var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=172
			var a=bot.pick(g.observation(0,false));choices[level][faction]=a.get("id",a.type)
			var expected={"I01":"G071","I03":"G025","I09":"G028"}
			check(a.type=="auto" and a.id==expected[faction],"The same hand adapts recruitment to the faction goal "+level+" "+faction+str(a))
		for seed_value in range(1,13):
			var g=fresh()
			for id in ["G001","G052"]:give(g,id)
			var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=seed_value
			var o=g.observation(0,false);var before=JSON.stringify([g.nodes,g.hands,g.rng.state]);var a=bot.pick(o)
			check(a in o.actions and before==JSON.stringify([g.nodes,g.hands,g.rng.state]),"Repeated-choice probes stay legal and leave the real game intact")
			var id=a.get("id",a.type);neutral[level][id]=neutral[level].get(id,0)+1
		var salon=fresh();put(salon,"G156");give(salon,"G153")
		var arranger=AiAgent.new();arranger.difficulty=level;arranger.rng.seed=91
		var chosen=arranger.pick(salon.observation(0,false))
		check(chosen.type=="auto" and chosen.parent=="G156","Generic planning uses the new Salon aura without a per-card placement rule "+level+str(chosen))
		var apartment=fresh();put(apartment,"G169");put(apartment,"G001",0,"G169");put(apartment,"G025",0,"G169");give(apartment,"G069")
		chosen=arranger.pick(apartment.observation(0,false))
		check(chosen.type=="auto" and chosen.parent=="G169","Generic planning completes the new Apartment threshold "+level+str(chosen))
	# Under a decisive public threat the defender must choose a real response, not a canned pass.
	var bot=AiAgent.new();bot.difficulty="hard"
	var g=fresh();put(g,"G005");put(g,"G071",1);g.nodes.G071.learned=8
	g.current=1;g._launch_attack(1,{"src":"G071","target":"G005","mode":"control"})
	g.battle.bonus_a=20-g.battle_values().strength
	var o=g.observation(0,false);var a=bot.pick(o)
	check(a.type in ["self_defend","support"],"Hard AI responds to a threatened Group rather than always passing")
	var report={"checks":checks,"failures":failures,"goal_choices":choices,"equal_material_choices":neutral}
	FileAccess.open("res://tests/ai-behavior-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("AI BEHAVIOR: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
