extends "res://tests/test_contemporary.gd"
const Planner=preload("res://scripts/ai_planner.gd")
const Structure=preload("res://scripts/ai_structure.gd")
func bare(g: GameState):
	for id in g.groups(0):g.nodes[id].mask=[]
func run():
	var g=fresh();put(g,"G001");put(g,"G002",0,"G001");put(g,"G005",0,"G002");bare(g)
	check(g.position_defense("G001")==10 and g.position_defense("G002")==5 and g.position_defense("G005")==0,"Deeper chains do not gain position defense")
	var chain=Structure.quality(g,0);g.nodes.G002.parent="R0";g.nodes.G005.parent="R0"
	check(Structure.quality(g,0)>chain,"With identical unaligned cards, protected independent branches beat a long chain")
	g.nodes.G002.parent="G001";g.nodes.G005.parent="G002"
	var safe=Structure.path_hold(g,"G005");g.nodes.G001.attached=["P26"]
	check(Structure.path_hold(g,"G005")>=safe,"Improving an ancestor cannot make its descendants less secure")
	# Place a valuable new group under the stronger of otherwise equivalent shallow anchors.
	g=fresh();put(g,"G044");put(g,"G052");put(g,"G005")
	for id in g.groups(0):g.nodes[id].mask=["政府","暴力"]
	give(g,"G002")
	var before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]);var strong=Structure.placement_hint(g,{"id":"G002","parent":"G005"});var weak=Structure.placement_hint(g,{"id":"G002","parent":"G044"})
	check(strong>weak,"Placement considers the capturable ancestor, not just the new Group")
	check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"Tentative placement restores the complete private model without hand/deck/RNG changes")
	var bot=AiAgent.new();bot.difficulty="hard";bot.rng.seed=334
	var observation=g.observation(0,false);var search=Planner.new(observation,"hard",13,bot.heuristic_pick,bot.heuristic_value)
	var ranked=search.rank(observation,8,search.samples[0]);var autos=ranked.filter(func(a):return a.type=="auto")
	check(not autos.is_empty() and autos[0].parent=="G005","Candidate ordering keeps a strong later-listed anchor ahead of weak early anchors")
	for level in ["normal","hard"]:
		g=fresh();put(g,"G001");put(g,"G002",0,"G001");bare(g);give(g,"G043")
		bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=333
		var o=g.observation(0,false);before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]);var a=bot.pick(o)
		check(a.type=="auto" and a.parent=="R0","Uses the available protected root slot rather than blindly extending a chain "+level+str(a))
		check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"Structural planning leaves the real match untouched "+level)
		# A real direct aura can outweigh a shallow placement; the fix is not a depth ban.
		g=fresh();put(g,"G156");give(g,"G153");a=bot.pick(g.observation(0,false))
		check(a.type=="auto" and a.parent=="G156","A useful direct aura can still justify a child branch "+level+str(a))
		g=fresh();put(g,"G001");put(g,"G043");put(g,"G044");give(g,"G002");a=bot.pick(g.observation(0,false))
		check(a.type=="auto" and a.parent=="G001","Shared alignments and loyalty can justify nesting under a compatible Group "+level+str(a))
	print("AI STRUCTURE: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
