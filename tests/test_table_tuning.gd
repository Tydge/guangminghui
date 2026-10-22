extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh(faction: String="I05") -> GameState:
	var g=GameState.new(732);g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.discards={"group":[],"plot":[],"resource":[]};g.graves=[[],[]];g.factions=[faction,"I05"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func put(g: GameState,id: String,p: int=0,parent: String="") -> void:
	g.decks.group.erase(id);g.hands[p].group.erase(id)
	if parent=="":
		for key in g.field(p):
			if g.can_parent(key):parent=key;break
	g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int=0) -> void:g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func apply(g: GameState,p: int,kind: String,args: Dictionary={}) -> void:
	var a=action(g,p,kind,args);check(not a.is_empty(),"Legal "+kind+str(args))
	if not a.is_empty():check(g.act(p,a),"Applied "+kind)
	check(g.validate().is_empty(),"Conservation after "+kind+str(g.validate()))
func settle(g: GameState,dice: Array=[1,1]) -> void:
	g.battle.fixed_dice=dice
	for i in 20:
		if g.phase!="battle":return
		apply(g,g.battle.responder,"pass")
func _initialize() -> void:
	CardDB.load_all()
	for row in [["G003",5,2,6],["G008",4,1,5],["G011",4,2,7],["G012",5,2,6],["G013",4,1,4],["G025",5,2,4]]:
		var c=CardDB.get_card(row[0]);check(int(c.p)==row[1] and int(c.gp)==row[2] and int(c.r)==row[3],"User printed values "+row[0])
	# Victory thresholds: exact boundary, no root power, and no count of unrelated groups.
	for faction in ["I01","I02","I03","I04","I07"]:
		var g=fresh(faction);put(g,"G052",1)
		var rule=CovenantRules.FACTIONS[faction]
		var ids=CardDB.ids("group").filter(func(id):return id!="G052" and (not rule.has("traits") or rule.traits.any(func(t):return g.has(id,t))))
		ids.sort_custom(func(a,b):return g.card(a).p<g.card(b).p)
		for id in ids.slice(0,rule.groups):put(g,id)
		var first=ids[0];g.nodes[first].learned=rule.power-g.goal(0).values.power-1
		check(g.nodes[first].learned>=0 and not g.goal(0).met and g.goal(0).values.power==rule.power-1,"Below goal threshold "+faction)
		g.nodes.R0.learned=100;check(not g.goal(0).met,"Root power never counts "+faction)
		g.nodes[first].learned+=1;check(g.goal(0).met and g.goal(0).values.power==rule.power,"Exact goal threshold "+faction)
		g._return_subtree(ids[rule.groups-1]);check(not g.goal(0).met,"Group count remains mandatory "+faction)
		check(g.validate().is_empty(),"Valid victory fixture "+faction)
	# UN uses current alignment and direct relationships; passives remain while devastated.
	var g=fresh();put(g,"G008");check(g.stat("G008","gp")==1,"UN base GP is one")
	put(g,"G001",0,"G008");put(g,"G010",0,"G008");put(g,"G003",0,"G001")
	check(g.stat("G008","gp")==3,"UN counts two direct government children, not grandchild")
	g.nodes.G010.mask=["企业"];check(g.stat("G008","gp")==2,"UN follows current government alignment")
	g.nodes.G010.erase("mask");g.nodes.G010.parent="R0";check(g.stat("G008","gp")==2,"UN follows reparenting immediately")
	g.nodes.G010.parent="G008";g.nodes.G008.silenced=true;check(g.stat("G008","gp")==1,"Silencing disables new UN passive")
	g.nodes.G008.silenced=false;put(g,"G004",0,"G008");check(g.stat("G008","gp")==4,"Three direct government children reach effective P cap")
	g.nodes.G008.devastated=true;check(g.stat("G008","gp")==2,"Devastated UN retains passive then halves effective GP")
	g.nodes.G008.devastated=false;g._return_subtree("G004");check(g.stat("G008","gp")==3,"Losing direct child updates GP")
	check(g.validate().is_empty(),"UN card conservation")
	# Weather defense is team-wide and disaster-only, with correct stacking and ownership.
	g=fresh();put(g,"G043");put(g,"G030",1);put(g,"G071",1);put(g,"G076",1)
	for id in ["P31","P32","P33","P34","P35"]:
		var v=g.wave.disaster_preview({"id":id,"payer":"G043","target":"G071"})
		check(v.defense==15,"Weather and China stack for "+id)
	check(g.card_context("G071").disaster_passive==15 and g.card_context("G071").destroy_passive==10,"Reader separates disaster aura from ordinary destruction defense")
	check(g.attack_preview("G043","G071","destroy").defense==10,"Weather never boosts ordinary destruction")
	check(g.attack_preview("G043","G030","destroy").defense==0,"Weather's obsolete self-only destruction defense is removed")
	check(g.wave.disaster_preview({"id":"P31","payer":"G043","target":"G076"}).base==4,"Swiss disaster base uses Power")
	g.nodes.G030.silenced=true;check(g.wave.disaster_preview({"id":"P31","payer":"G043","target":"G076"}).defense==0,"Silenced Weather aura stops")
	g.nodes.G030.silenced=false;g.nodes.G030.devastated=true;check(g.wave.disaster_preview({"id":"P31","payer":"G043","target":"G076"}).defense==5,"Devastated Weather retains passive")
	g.nodes.G030.devastated=false;g.nodes.G071.prepared=true;give(g,"P31");apply(g,0,"plot",{"id":"P31","payer":"G043","target":"G071"})
	check(g.battle_values().defense==15 and g.battle_values().bonus_d==4 and g.token("G030"),"Live disaster matches preview and stacks preparation without spending Weather action")
	check(g.legal_actions(1).all(func(a):return a.type!="mediate"),"Removed UN mediation cannot appear in disasters")
	g.nodes.G030.owner=0;g.nodes.G030.parent="R0";check(g.battle_values().defense==10,"Weather transfer no longer protects former owner")
	# Comic Books rewards a celebrity entering from hand after board motion, once per turn.
	g=fresh("I01");put(g,"G034");put(g,"G005");g.nodes.G005.learned=12;put(g,"G052",1);give(g,"G084");give(g,"G085")
	var bot=AiAgent.new();var observation=g.observation(0);var with_hero=bot._value("G034",observation);observation.hands.group=[]
	check(with_hero>bot._value("G034",observation),"AI recognizes Comic Books and celebrity hand synergy without private opponent information")
	g.nodes.G034.token=0;apply(g,0,"auto",{"id":"G084","parent":"R0"})
	check(g.phase=="choice" and g.choice.kind=="w_auto" and g.choice.source=="G034" and g.hands[0].plot.is_empty(),"Comic reward is deferred and does not require its action marker")
	var rng_before=g.rng.state;var plan=ActionFlow.plan(g,0,action(g,0,"trigger"))
	check(g.hands[0].plot.is_empty() and g.rng.state==rng_before and plan.moves.size()==1,"Comic draw rehearsal preserves live state and RNG")
	apply(g,0,"trigger");check(g.hands[0].plot.size()==1,"Comic draws once when reward resolves")
	apply(g,0,"attack",{"src":"G005","target":"G085","mode":"control"});settle(g)
	check(g.nodes.has("G085") and g.hands[0].plot.size()==1 and g.phase=="main","Second celebrity entering this turn gives no second reward")
	check(action(g,0,"ability",{"src":"G034"}).is_empty(),"Comic remains entirely passive")
	for variant in ["capture","silenced","ordinary"]:
		g=fresh("I01");put(g,"G034");put(g,"G005");g.nodes.G005.learned=12;put(g,"G052",1)
		if variant=="capture":put(g,"G084",1)
		else:give(g,"G084" if variant=="silenced" else "G010")
		if variant=="silenced":g.nodes.G034.silenced=true
		if variant=="capture":apply(g,0,"attack",{"src":"G005","target":"G084","mode":"control"});settle(g)
		else:apply(g,0,"auto",{"id":"G084" if variant=="silenced" else "G010","parent":"R0"})
		check(g.phase=="main" and g.hands[0].plot.is_empty(),"No Comic reward for "+variant)
	# Dentist bills only the failed ordinary attacker, after battle settlement, without a choice.
	for mode in ["control","destroy"]:
		g=fresh();put(g,"G005");g.nodes.G005.learned=20;put(g,"G067",1);give(g,"P10");give(g,"P17")
		apply(g,0,"attack",{"src":"G005","target":"G067","mode":mode});settle(g,[5,6])
		check(g.phase=="choice" and g.choice.source=="G067" and g.choice.player==0 and g.hands[0].plot.size()==2,"Failed "+mode+" queues bill after battle, before discard")
		var before=g.hands.duplicate(true);var bill_rng=g.rng.state;var bill_plan=ActionFlow.plan(g,0,action(g,0,"trigger"))
		check(g.hands==before and g.rng.state==bill_rng and bill_plan.moves.size()==1,"Bill rehearsal never discards or rerolls on live state")
		var discarded=bill_plan.moves[0].id;apply(g,0,"trigger")
		check(g.hands[0].plot.size()==1 and discarded in g.discards.plot and g.token("G067"),"Bill commits same random plot once and costs Dentist no marker")
		check(g.last_battle.entries.back().text.contains("高额账单") and g.last_battle.entries.back().text.contains(g.title(discarded)),"Public battle history identifies actual discarded card")
		check(action(g,1,"ability",{"src":"G067"}).is_empty(),"Dentist remains entirely passive")
	for variant in ["success","silenced","empty","disaster"]:
		g=fresh();put(g,"G005");g.nodes.G005.learned=20;put(g,"G067",1)
		if variant!="empty":give(g,"P10")
		if variant=="silenced":g.nodes.G067.silenced=true
		if variant=="disaster":
			g.nodes.G067.extra_tags=["地点"];give(g,"P31");apply(g,0,"plot",{"id":"P31","payer":"G005","target":"G067"})
		else:apply(g,0,"attack",{"src":"G005","target":"G067","mode":"control"})
		settle(g,[1,1] if variant=="success" else [5,6])
		check(g.phase=="main" and g.hands[0].plot.size()==(0 if variant=="empty" else 1),"No bill for "+variant)
	var report={"checks":checks,"failures":failures,"scope":"Edited data, faction goals, UN, Weather, Comic Books and Dentists"};FileAccess.open("res://tests/table-tuning-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("TABLE TUNING: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
