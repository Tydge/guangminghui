extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh(faction: String="I05") -> GameState:
	var g=GameState.new(196);g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.discards={"group":[],"plot":[],"resource":[]};g.graves=[[],[]];g.factions=[faction,"I01"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func remove(g: GameState,id: String) -> void:
	for kind in ["group","plot"]:
		g.decks[kind].erase(id);g.discards[kind].erase(id)
		for p in [0,1]:g.hands[p][kind].erase(id)
func put(g: GameState,id: String,p: int=0,parent: String="") -> void:
	remove(g,id)
	if parent=="":
		for key in g.field(p):
			if g.can_parent(key):parent=key;break
	g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int=0) -> void:remove(g,id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func apply(g: GameState,p: int,kind: String,args: Dictionary={}) -> void:
	var a=action(g,p,kind,args);check(not a.is_empty(),"Legal "+kind+str(args))
	if not a.is_empty():check(g.act(p,a),"Applied "+kind)
	check(g.validate().is_empty(),"Conservation "+str(g.validate()))
func goal_fixture(id: String) -> GameState:
	var g=fresh();var ids=[]
	match id:
		"P51":ids=["G051","G013","G021","G052","G053"]
		"P52":ids=["G010","G015","G017","G022","G033","G034","G001","G024","G011"]
		"P53":ids=["G001","G002","G003","G007"];g.destroyed[0]=3
		"P54":ids=["G084","G085","G131","G032","G001","G002","G003"]
		"P55":ids=["G055","G082","G084","G031","G045","G001","G010","G023","G025"]
		"P61":ids=["G049","G062","G094","G158","G163"]
	for key in ids:put(g,key)
	if id=="P61":
		for resource in ["E16","E20"]:
			g.decks.resource.erase(resource);g.nodes[resource]={"card":resource,"owner":0,"parent":"","token":0,"attached":[],"resource_slot":g.resources.field(0).size()}
	g.decks.plot.erase(id);g.hands[0].plot.append(id)
	return g
func _initialize() -> void:
	CardDB.load_all();check(CardDB.ids("faction").size()==12 and CardDB.ids("plot").size()==70,"Expanded card pool")
	var expected={"I01":[8,48],"I02":[6,30],"I03":[5,26],"I04":[5,25],"I07":[6,25],"I08":[5,24]}
	for id in expected:
		check(CovenantRules.FACTIONS[id].groups==expected[id][0] and CovenantRules.FACTIONS[id].power==expected[id][1],"User thresholds "+id)
	var g=fresh("I06")
	for id in ["G071","G093","G097","G098","G073"]:put(g,id)
	put(g,"G007");check(g.goal(0).values.power==26 and not g.goal(0).met,"Bermuda sums places only, not other groups")
	g.nodes.G071.learned=4;check(g.goal(0).met and g.goal(0).values.groups==5,"Bermuda requires five places and two huge, no seven-group gate")
	for id in CovenantRules.PLOTS:
		g=goal_fixture(id);check(g.covenant.progress(0,id).met,"Goal fixture met "+id)
		check(not action(g,0,"plot",{"id":id}).is_empty(),"Goal can actively declare "+id)
		g._after_effect();check(g.phase!="over","No automatic goal victory "+id)
		var before=g.phase;var plan=ActionFlow.plan(g,0,action(g,0,"plot",{"id":id}));check(g.phase==before and id in g.hands[0].plot and g.claim.is_empty(),"Declaration rehearsal isolated "+id)
		g.nodes.R0.token=0;apply(g,0,"plot",{"id":id});check(g.phase=="over" and g.winner==0 and id in g.discards.plot,"Declaration spends plot, not action "+id)
	# Boundary conditions and shared-tag counting.
	g=goal_fixture("P51");g.nodes.G053.learned=-1;check(not g.covenant.progress(0,"P51").met,"Crime power below threshold")
	g=goal_fixture("P52");g.nodes.G010.learned=8;check(g.covenant.progress(0,"P52").met,"Grassroots uses printed P after boosts")
	g.nodes.G022.devastated=true;check(not g.covenant.progress(0,"P52").met,"Devastated groups do not count")
	g=goal_fixture("P53");g.destroyed[0]=2;check(not g.covenant.progress(0,"P53").met,"Military requires actual destruction count")
	g=goal_fixture("P54");var v=g.covenant.progress(0,"P54").values;check(v.groups==7 and v.celebrity==3 and v.media==4,"Celebrity-media overlap counted once in total")
	g=goal_fixture("P55");check(g.covenant.progress(0,"P55").covered.size()==10,"All ten alignments including fanatic")
	g.nodes.G045.mask=["怪异"];check(not g.covenant.progress(0,"P55").met,"Temporary identity changes coverage")
	# Timing and ordinary counterplay.
	g=goal_fixture("P51");g.turns=[1,0];check(action(g,0,"plot",{"id":"P51"}).is_empty(),"First-round declaration blocked")
	g.turns=[2,2];g.phase="draw";check(action(g,0,"plot",{"id":"P51"}).is_empty(),"Declaration restricted to main phase")
	g.phase="main";g.current=1;check(action(g,0,"plot",{"id":"P51"}).is_empty(),"Cannot declare on opponent turn")
	g=goal_fixture("P51");give(g,"P15",1);apply(g,0,"plot",{"id":"P51"});check(g.phase=="plot_response" and g.winner==-2,"Goal waits for counter")
	apply(g,1,"counter",{"id":"P15"});check(g.phase=="main" and "P51" in g.discards.plot and g.winner==-2,"Deception cancels goal normally")
	g=goal_fixture("P51");put(g,"G137",1);give(g,"P01",1);apply(g,0,"plot",{"id":"P51"});apply(g,1,"trick",{"fee":"P01"});check(g.winner==-2 and not g.token("G137"),"Substitute trick cancels declaration")
	g=goal_fixture("P51");give(g,"P15",1);apply(g,0,"plot",{"id":"P51"});apply(g,1,"accept_plot");check(g.winner==0,"Accepted goal wins after response")
	# Goal hand cap, private choices, theft and recovery all use the same boundary.
	g=fresh();give(g,"P51");give(g,"P52");g._after_effect();check(g.choice.kind=="c_goal_limit" and g.choice.player==0,"Select one goal to keep")
	var o=g.observation(1);check(o.secret_goals.is_empty() and o.choice.is_empty(),"Opponent cannot see hidden goals or private keep choice")
	apply(g,0,"choose",{"id":"P52"});check(g.hands[0].plot==["P52"] and "P51" in g.discards.plot and g.phase=="main","Extra goal discarded and phase restored")
	g=fresh();give(g,"P51");give(g,"P52",1);give(g,"P23");put(g,"G001");apply(g,0,"plot",{"id":"P23","target":"G001"});check(g.choice.kind=="c_goal_limit","Stealing second goal asks which to keep")
	apply(g,0,"choose",{"id":"P52"});check(g.hands[1].plot.is_empty(),"Theft transfers goal ownership")
	g=fresh();give(g,"P51");remove(g,"P52");g.discards.plot.append("P52");put(g,"G013");apply(g,0,"ability",{"src":"G013"});apply(g,0,"choose",{"id":"P52"});check("P52" in g.locked,"Recovered goal keeps same-turn lock")
	# Peace conversion: lasting state, cost, temporary identity, ownership and leaving.
	g=fresh("I07");put(g,"G007");apply(g,0,"ability",{"pacify":true,"target":"G007"});check(g.alignments("G007")==["政府","和平"] and not g.token("R0") and g.token("G007"),"Pacify preserves other traits and target token")
	g.nodes.R0.token=1;check(action(g,0,"ability",{"pacify":true}).is_empty(),"Pacify once per own turn")
	var copy=ActionFlow.copy_state(g);copy.nodes.G007.pacified=false;check(g.has("G007","和平") and copy.has("G007","暴力"),"Rehearsal conversion isolated")
	g.nodes.G007.owner=1;g.nodes.G007.parent="R1";check(g.has("G007","和平"),"Pacification survives capture")
	g._return_subtree("G007");put(g,"G007",1);check(not g.has("G007","和平") and g.has("G007","暴力"),"Pacification clears on leaving")
	g=fresh("I07");put(g,"G010");g.nodes.G010.mask=["犯罪","暴力"];apply(g,0,"ability",{"pacify":true,"target":"G010"});check(g.alignments("G010")==["犯罪","和平"],"Current identity is pacified immediately")
	g.nodes.G010.erase("mask");check(g.has("G010","和平") and not g.has("G010","犯罪"),"Mask expiry keeps conversion, not other borrowed alignments")
	# Hermes P support, exclusions and higher priority restrictions.
	g=fresh("I08");put(g,"G055");put(g,"G138");put(g,"G008",1);g._launch_attack(0,{"src":"G055","target":"G008","mode":"control"});var detail=g.support_detail("G138",g.battle)
	check(detail.basis=="P" and detail.power==3 and detail.reason.contains("秘术共鸣"),"Magic leader unlocks P against nonmagic target")
	g.battle.army_gp_only=true;g.synergy.add_tag("G138","军队");check(g.support_detail("G138",g.battle).basis=="GP","Miyazaki restriction overrides Hermes")
	g=fresh("I08");put(g,"G116");put(g,"G117");put(g,"G005",1);g.current=1;g._launch_attack(1,{"src":"G005","target":"G116","mode":"destroy"});check(g.support_detail("G117",g.battle).basis=="P","Magic defense unlocks P without shared alignment")
	g.battle.disaster="P31";check(g.support_detail("G117",g.battle).basis=="GP","Hermes does not override disaster support")
	# Rewards finish before a declaration can settle into victory.
	g=goal_fixture("P53");put(g,"G035");put(g,"G032",0,"G035");apply(g,0,"plot",{"id":"P53"});check(g.phase=="choice" and not g.claim.is_empty() and g.winner==-2,"Goal waits for ordinary plot reward trigger")
	apply(g,0,"trigger");check(g.winner==0 and g.claim.is_empty(),"Reward settles then declaration wins")
	g=goal_fixture("P51");var bot=AiAgent.new();o=g.observation(0);check(bot.pick(o).type=="plot" and bot.pick(o).id=="P51","AI prioritizes a valid goal declaration")
	g=fresh("I07");put(g,"G007");check(bot.pick(g.observation(0)).get("pacify",false),"AI uses peace conversion")
	var report={"checks":checks,"failures":failures};FileAccess.open("res://tests/covenant-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("COVENANT: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
