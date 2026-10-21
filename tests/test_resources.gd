extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	var g=GameState.new(902);g.nodes={};g.factions=["I01","I05"];g.current=0;g.turns=[2,2];g.phase="main"
	for kind in g.decks:
		g.decks[kind]=CardDB.ids(kind);g.discards[kind]=[]
		for p in [0,1]:g.hands[p][kind]=[]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func put(g: GameState,id: String,p: int=0,parent: String="") -> void:
	var kind=g.card(id).kind;g.decks[kind].erase(id)
	for who in [0,1]:g.hands[who][kind].erase(id)
	if kind=="resource":g.nodes[id]={"card":id,"owner":p,"parent":"","token":1 if g.card(id).action else 0,"attached":[],"resource_slot":g.resources.field(p).size()}
	else:g._enter(id,p,g.root(p) if parent=="" else parent,1)
func give(g: GameState,id: String,p: int=0) -> void:
	var kind=g.card(id).kind;g.decks[kind].erase(id);g.hands[p][kind].append(id)
func action(g: GameState,p: int,type: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==type and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func apply(g: GameState,p: int,type: String,args: Dictionary={}) -> void:
	var a=action(g,p,type,args);check(not a.is_empty(),"Legal "+type+str(args))
	if not a.is_empty():check(g.act(p,a),"Applied "+type)
	check(g.validate().is_empty(),"Conservation "+str(g.validate()))
func _initialize() -> void:
	CardDB.load_all();check(CardDB.ids("resource").size()==15 and CardDB.ids("plot").size()==60,"New card counts")
	var g=GameState.new(44);apply(g,0,"faction",{"id":"I01"});apply(g,0,"initial",{"id":g.hands[0].group[0]});apply(g,0,"initial_resource",{"id":g.resource_candidates[0][0]})
	check(g.hands[0].resource.size()==1 and g.hands[1].resource.size()==1 and g.decks.resource.size()==13,"Opening resource each, separate deck")
	check(g.decks.group.all(func(k):return g.card(k).kind=="group"),"Group deck contains no resources")
	g=fresh();var count=g.decks.resource.size();apply(g,0,"draw",{}) if false else null
	g.phase="draw";apply(g,0,"draw",{"group":true,"plot":true,"filter_group":false,"filter_plot":false})
	check(g.decks.resource.size()==count and g.hands[0].resource.is_empty(),"Normal turn draw never draws resources")
	apply(g,0,"research",{"deck":"resource"});check(g.hands[0].resource.size()==1 and not g.token("R0") and not g.auto_used,"Root draw costs action but not deployment quota")
	g.nodes.R0.token=1;apply(g,0,"research",{"deck":"resource"});g.nodes.R0.token=1
	var snapshot=g.decks.resource.duplicate();var before_rng=g.rng.state
	check(action(g,0,"research",{"deck":"resource"}).is_empty() and g._draw(0,"resource")=="" and snapshot==g.decks.resource and before_rng==g.rng.state,"Full resource hand blocks draws without changing deck or RNG")
	g=fresh();give(g,"E01");var d=action(g,0,"deploy",{"id":"E01"});var plan=ActionFlow.plan(g,0,d)
	check(not g.nodes.has("E01") and g.token("R0") and "E01" in g.hands[0].resource,"Deployment rehearsal leaves actual state unchanged")
	apply(g,0,"deploy",{"id":"E01"});check(not g.token("E01") and not g.resources.recoverable("E01") and g.auto_used,"Entry resources cannot act or recharge")
	check("E01" not in g.field(0) and "E01" not in g.groups(0) and g.children("R0").is_empty(),"Resource never belongs to group tree")
	g.captured.clear();g.resources.refill(0);check(g.token("E01"),"Next own turn refill")
	put(g,"G023");give(g,"G042");apply(g,0,"attack",{"src":"G023","target":"G042","mode":"control"})
	g.battle.responder=0;var strength=g.battle_values().strength;apply(g,0,"resource",{"src":"E01"})
	check(g.battle_values().strength==strength+2 and not g.token("E01") and g.nodes.has("E01") and g.battle.entries.back().id=="E01","Radar effect and visible battle record, retains resource")
	check(g.support_power("E01",g.battle)==0,"Resource cannot P or GP support")
	g=fresh();put(g,"E02");put(g,"G043");g.nodes.G043.token=0;apply(g,0,"resource",{"src":"E02","target":"G043"})
	check(g.token("G043") and "E02" in g.scrap and not g.nodes.has("E02"),"Battery consumes itself and restores one group")
	g=fresh();put(g,"E03");put(g,"G072");var defense=g.passive_defense("G072","destroy")
	check(g.disaster_defense("G072")==defense+3,"Satellite disaster-only defense")
	g.nodes.E03.silenced=true;check(g.disaster_defense("G072")==defense,"Silenced passive resource ceases")
	g=fresh();put(g,"E04");give(g,"G043");apply(g,0,"auto",{"id":"G043","parent":"R0"})
	check(g.phase=="choice" and g.choice.get("source","")=="E04" and g.hands[0].plot.is_empty(),"Archive reward queued after entry, not immediate")
	apply(g,0,"trigger",{"src":"E04"});check(g.hands[0].plot.size()==1,"Archive trigger grants plot")
	g.resources.entry_reward(0);check(g.wave.queue.is_empty(),"Archive once per own turn")
	g=fresh();put(g,"E05");check(g.resource_hand_limit(0)==3 and g.hand_limit(0)==6,"Vault adjusts both caps")
	for i in 4:g._draw(0,"resource")
	check(g.hands[0].resource.size()==3,"Multi draw obeys increased cap")
	g.resources.remove("E05");g._after_effect();check(g.choice.kind=="e_limit","Losing capacity opens resource discard")
	apply(g,0,"choose",{"id":g.hands[0].resource[0]});check(g.hands[0].resource.size()==2,"Capacity decrease discards to legal limit")
	g=fresh();put(g,"E06");apply(g,0,"resource",{"src":"E06"});check(g.hands[0].group.size()==2 and g.choice.kind=="e_discard","Quantum computer draws groups then chooses cost")
	apply(g,0,"choose",{"id":g.hands[0].group[0]});check(g.hands[0].group.size()==1 and not g.token("E06"),"Quantum selection consumes own action")
	g=fresh();put(g,"G043");put(g,"G072",1);put(g,"E07",1);apply(g,0,"attack",{"src":"G043","target":"G072","mode":"destroy"});apply(g,1,"resource",{"src":"E07"})
	check(g.battle.bonus_d==6 and "E07" in g.scrap,"Amulet destroy-only defensive response")
	g=fresh();put(g,"E08");apply(g,0,"resource",{"src":"E08"});check(g.choice.kind=="e_probe" and g.choice.peek.size()==3,"Probe privately views three resources")
	check(g.observation(1).choice.is_empty(),"Private probe choices hidden from opponent")
	var pick=g.choice.options[0];apply(g,0,"choose",{"id":pick});check(pick in g.hands[0].resource,"Probe takes one resource")
	g=fresh();put(g,"E09");put(g,"G099");put(g,"G043",1);var b={"src":"R0","target":"G043","mode":"control","attacker":0,"defender":1}
	var detail=g.support_detail("G099",b);check(detail.basis=="GP" and detail.power==g.stat("G099","gp")+1,"Coastal GP support benefits")
	g=fresh();put(g,"E10");put(g,"G023");put(g,"G001");apply(g,0,"resource",{"src":"E10","target":"G001","parent":"G023"});check(g.nodes.G001.parent=="G023" and g.token("G001") and not g.token("E10"),"Drone pays its own action for legal group move")
	g=fresh();put(g,"G093");put(g,"E01");g.nodes.E01.token=0;apply(g,0,"resource",{"src":"G093","target":"E01"})
	check(g.token("E01") and not g.token("G093") and not g.resources.recoverable("E01"),"Russia restores gadget once with group action")
	g=fresh();put(g,"G098");give(g,"G043");give(g,"E01");g.nodes.R0.token=0;apply(g,0,"deploy",{"id":"E01","fee":"G043"});check("G043" in g.discards.group and g.auto_used,"Australia trades group card for deployment action")
	g=fresh();put(g,"G092");var base_gp=g.stat("G092","gp");put(g,"E01");put(g,"E03");check(g.stat("G092","gp")==mini(g.stat("G092","p"),base_gp+2),"India scales GP with current resources")
	g=fresh();put(g,"E01");put(g,"E03");give(g,"E05");var options=g.legal_actions(0).filter(func(a):return a.type=="deploy")
	check(options.size()==2,"Full field explicitly chooses resource to replace")
	apply(g,0,"deploy",{"id":"E05","replace":"E01"});check(g.resources.field(0).size()==2 and g.nodes.E05.resource_slot==0 and "E01" in g.scrap,"Replacement preserves left/right slot and scraps old card")
	g=fresh();put(g,"G043");put(g,"E01",1);give(g,"P56");give(g,"P15",1);apply(g,0,"plot",{"id":"P56","target":"E01","payer":"G043"});apply(g,1,"counter")
	check(g.nodes.has("E01") and not g.token("G043"),"Resource plot countered normally, action fee remains paid")
	g=fresh();put(g,"G043");put(g,"E01",1);give(g,"P56");apply(g,0,"plot",{"id":"P56","target":"E01","payer":"G043"});check("E01" in g.scrap,"Resource demolition scraps target")
	g=fresh();give(g,"P57");apply(g,0,"plot",{"id":"P57"});check(g.choice.peek.size()==2,"Resource research sees two cards")
	apply(g,0,"choose",{"id":g.choice.options[0]});check(g.hands[0].resource.size()==1,"Research takes one resource")
	g=fresh();put(g,"E05",1);put(g,"G023");put(g,"G001",1);give(g,"P58");apply(g,0,"plot",{"id":"P58","target":"E05"});check(not g.resources.ready("E05") and g.resource_hand_limit(1)==2,"Blockade disables passive and cap")
	g._complete_end();check(g.resources.ready("E05"),"Blockade expires at turn end")
	for seed in 12:
		g=GameState.new(seed+100);apply(g,0,"faction",{"id":"I01"});apply(g,0,"initial",{"id":g.hands[0].group[0]});apply(g,0,"initial_resource",{"id":g.resource_candidates[0][0]});check(g.validate().is_empty(),"Opening conservation across seeds")
	print("RESOURCE TESTS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
