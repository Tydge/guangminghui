extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	var g=GameState.new(81);g.nodes.clear();g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.discards={"group":[],"plot":[],"resource":[]};g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.graves=[[],[]];g.factions=["I06","I05"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func remove(g: GameState,id: String) -> void:
	for kind in ["group","plot"]:
		g.decks[kind].erase(id);g.discards[kind].erase(id)
		for p in [0,1]:g.hands[p][kind].erase(id)
func put(g: GameState,id: String,p: int,parent: String) -> void:remove(g,id);g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:remove(g,id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func apply(g: GameState,p: int,kind: String,args: Dictionary={}) -> void:
	var a=action(g,p,kind,args);check(not a.is_empty(),"Legal "+kind+str(args))
	if not a.is_empty():check(g.act(p,a),"Applied "+kind)
	check(g.validate().is_empty(),"Conserved after "+kind+str(g.validate()))
func _initialize() -> void:
	CardDB.load_all()
	var c=CardDB.get_card("G056")
	check(c.p==3 and c.gp==1 and c.r==5 and c.align==["犯罪","狂热"],"Clone stats and alignments")
	var g=fresh();put(g,"G133",0,"R0");put(g,"G134",0,"G133");put(g,"G135",0,"G134")
	check(g.stat("G133","slots")==3,"Housing boosts direct Communist parent")
	check(g.stat("G134","slots")==2 and g.stat("G135","slots")==1,"No downward or self slot bonus")
	check(g.stat("G134","p")==4,"Existing factory power aura still works in opposite direction")
	g.nodes.G134.silenced=true;check(g.stat("G133","slots")==2,"Housing silence disables upward aura");g.nodes.G134.silenced=false
	g=fresh();put(g,"G001",0,"R0");put(g,"G134",0,"G001");check(g.stat("G001","slots")==2,"Non-Communist parent gets no slot")
	g=fresh();put(g,"G119",0,"R0");put(g,"G134",0,"G119");check(g.stat("G119","slots")==3,"Printed three-slot parent stays capped")
	g=fresh();put(g,"G133",0,"R0");put(g,"G043",0,"G133");put(g,"G044",0,"G133");give(g,"G134",0)
	check(action(g,0,"auto",{"id":"G134","parent":"G133"}).is_empty(),"Entry still needs an existing empty slot")
	g._return_subtree("G044");apply(g,0,"auto",{"id":"G134","parent":"G133"});check(g.stat("G133","slots")==3 and not g.token("G134"),"Auto entry applies passive aura without granting action")
	g=fresh();put(g,"G133",0,"R0");put(g,"G134",0,"G133");put(g,"G043",0,"G133");put(g,"G044",0,"G133")
	check(action(g,0,"ability",{"src":"R0","target":"G134","other":"G043"}).is_empty(),"Same-parent swaps stay excluded")
	put(g,"G001",0,"R0");check(action(g,0,"ability",{"src":"R0","target":"G134","other":"G001"}).is_empty(),"Cannot replace housing while losing an occupied extra slot")
	apply(g,0,"move",{"src":"G134","parent":"R0","payer":"R0"});check(g.stat("G133","slots")==2 and g.children("G133").size()==2 and g.phase=="main","Single move frees old slot as aura ends")
	g=fresh();put(g,"G133",0,"R0");put(g,"G134",0,"G133");put(g,"G043",0,"G133");put(g,"G044",0,"G133");g.current=1
	apply(g,1,"attack",{"src":"R1","target":"G134","mode":"control"});g.battle.bonus_a=100;g.battle.rolled=[1,1];g._resolve_battle()
	check(g.owner("G134")==1 and g.stat("G133","slots")==2 and g.children("G133").size()==2 and g.validate().is_empty(),"Taking housing frees the old occupied slot and ends its aura")
	g=fresh();put(g,"G133",0,"R0");put(g,"G134",0,"G133");put(g,"G001",0,"R0")
	apply(g,0,"ability",{"src":"R0","target":"G134","other":"G001"});check(g.nodes.G001.parent=="G133" and g.stat("G133","slots")==2,"Swap allowed when final capacity is legal")
	g=fresh();put(g,"G133",0,"R0");put(g,"G134",0,"G133");put(g,"G043",0,"G133");put(g,"G044",0,"G133");put(g,"G045",0,"G043")
	g.nodes.G134.silenced=true;g._after_effect();check(g.choice.get("kind")=="x_overflow" and g.choice.player==0,"Forced aura loss asks controller")
	apply(g,0,"choose",{"id":"G043"});check("G043" in g.hands[0].group and "G045" in g.hands[0].group and g.phase=="main","Chosen excess branch returns whole")
	g=fresh();put(g,"G135",0,"R0");put(g,"G134",0,"G135");remove(g,"P19");g.nodes.G135.attached.append("P19");put(g,"G043",0,"G135");check(g.stat("G135","slots")==3 and g.synergy.can_detach("G135","P19"),"Attachment can leave upward aura capacity")
	g.nodes.G134.silenced=true;check(not g.synergy.can_detach("G135","P19"),"Cannot remove last required slot attachment")
	g=fresh();put(g,"G133",0,"R0");put(g,"G134",0,"G133");var clone=ActionFlow.copy_state(g);clone.nodes.G134.silenced=true
	check(g.stat("G133","slots")==3 and clone.stat("G133","slots")==2,"Rehearsal aura stays isolated")
	var bot=AiAgent.new();var o=g.observation(0);check(bot._placement_value("G134","G133",o)>0 and bot._placement_value("G135","G134",o)==0,"AI prefers housing under Communist parent, not reverse")
	g=fresh();put(g,"G056",0,"R0");give(g,"G043",0);g._discard(0,"G043");apply(g,0,"ability",{"src":"G056","target":"G043"});check("G043" in g.hands[0].group and not g.token("G056"),"Clone backup ability preserved")
	var report={"checks":checks,"failures":failures,"scope":"Housing upward slot aura and Clone Arrangers only","full_suite_run":false};FileAccess.open("res://tests/housing-clone-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("HOUSING / CLONE: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
