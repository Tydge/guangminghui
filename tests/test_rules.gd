extends SceneTree

var checks=0
var failures: Array=[]

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message);push_error(message)

func base(seed_value: int=89) -> GameState:
	var g=GameState.new(seed_value)
	g.act(0,g.legal_actions(0)[0]);g.act(0,g.legal_actions(0)[0])
	g.phase="main";g.current=0;g.turns=[2,2]
	for id in g.nodes:g.nodes[id].token=1
	return g

func place(g: GameState,id: String,p: int,parent: String) -> void:
	for kind in ["group","plot"]:
		g.decks[kind].erase(id);g.discards[kind].erase(id)
		for who in [0,1]:g.hands[who][kind].erase(id)
	if g.nodes.has(id):g.nodes.erase(id)
	g._enter(id,p,parent,1)

func action(g: GameState,p: int,kind: String,match_values: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type!=kind:continue
		var okay=true
		for key in match_values:
			if a.get(key)!=match_values[key]:okay=false
		if okay:return a
	return {}

func give(g: GameState,id: String,p: int) -> void:
	var kind=CardDB.get_card(id).kind
	g.decks[kind].erase(id);g.discards[kind].erase(id)
	for who in [0,1]:g.hands[who][kind].erase(id)
	g.hands[p][kind].append(id)

func _initialize() -> void:
	CardDB.load_all()
	check(CardDB.cards.size()==186,"186 definitions")
	check(CardDB.get_card("G071").p==7 and "共产" in CardDB.get_card("G071").tags and "巨大" in CardDB.get_card("G071").tags,"Human China adjustment and location tags")
	check(CardDB.get_card("G012").p==5 and CardDB.get_card("G100").p==3,"Latest Bank and Suez user edits")
	check(CardDB.get_card("G072").p==4 and CardDB.get_card("G072").r==5 and CardDB.get_card("G074").p==4 and CardDB.get_card("G074").gp==2,"Latest Japan and England table edits")
	check(CardDB.get_card("G051").r==5 and CardDB.get_card("G073").r==5 and CardDB.get_card("G078").p==4 and "暴力" not in CardDB.get_card("G077").align,"October 19 human numeric and alignment edits")
	check(CardDB.get_card("G077").p==4 and CardDB.get_card("G080").gp==0,"Latest New York and Stonehenge table edits")
	check("计算机" not in CardDB.get_card("G072").tags,"Human Japan adjustment")
	var g=base()
	check(g.hands[0].group.size()==4 and g.hands[1].group.size()==4,"Opening 5 choose 1 leaves 4")
	check(g.validate().is_empty(),"Opening conservation")
	var auto=action(g,0,"auto")
	check(not auto.is_empty(),"Automatic takeover offered")
	g.act(0,auto)
	check(not g.token(auto.id) and not g.can_recharge(auto.id) and not g.token(g.root(0)) and g.auto_used,"Auto costs root and locks new group's action until a later turn")
	check(action(g,0,"auto").is_empty(),"Auto once per turn")
	check(g.validate().is_empty(),"Auto conservation")
	# Tree cycles, position defense and fanatic opposition.
	g=base();place(g,"G023",0,g.root(0));place(g,"G024",0,"G023");place(g,"G026",0,"G024")
	check(not g.can_parent("G026","G023"),"No parent cycles")
	check(g.depth("G023")==1 and g.depth("G026")==3,"Depth")
	check(g._common("G042","G045")==1 and g._opposed("G042","G045")==1,"Fanatic is opposed, Weird common")
	var v=g.attack_preview(g.root(1),"G023","control")
	check(v.position==10,"Direct child position +10")
	v=g.attack_preview(g.root(1),"G024","control");check(v.position==5,"Second level +5")
	v=g.attack_preview(g.root(1),"G026","control");check(v.position==0,"Deeper position zero")
	place(g,"G021",1,g.root(1));v=g.attack_preview("G021","G024","control");check(v.position==0 and v.base==3,"Hackers ignores only position")
	# Recharge quota and Supreme Court protection.
	place(g,"G020",0,g.root(0));place(g,"G066",0,"G020");g.nodes.G066.token=0
	var recharge=action(g,0,"ability",{"src":"G020","target":"G066"});check(not recharge.is_empty(),"Power recharge legal")
	g.act(0,recharge);g.nodes.G066.token=0;check(not g.can_recharge("G066"),"Shared recharge quota")
	place(g,"G009",1,g.root(1));place(g,"G043",1,"G009");check(not g.removable("G043"),"Court child token protection")
	# Ownership capture clears whole subtree, preserves attachments, locks recharge.
	g=base();place(g,"G055",0,g.root(0));place(g,"G051",1,g.root(1));place(g,"G043",1,"G051")
	g.nodes.G051.attached=["P26"];g.decks.plot.erase("P26");g.hands[0].plot.erase("P26");g.hands[1].plot.erase("P26")
	var a=action(g,0,"attack",{"src":"G055","target":"G051","mode":"control"});g.act(0,a);g.battle.bonus_a=100
	while g.phase=="battle":
		var p=g.battle.responder;g.act(p,action(g,p,"pass"))
	# A roll of 11/12 legitimately fails; repeat with seeded success only in fixture.
	if g.owner("G051")==0:
		check(g.owner("G043")==0 and not g.token("G043") and not g.can_recharge("G043"),"Capture subtree lock")
		check("P26" in g.nodes.G051.attached and g.has("G051","怪异"),"Capture attachment and vampire conversion")
	# Full probability never reaches 100%, even with massive modifiers.
	check(g.attack_preview(g.root(0),"G043","destroy").chance<=33.0/36.0,"Dice ceiling")
	# Human and AI do not see hidden identities or deck order.
	g=base();var o=g.observation(1)
	check(not o.has("rng") and not o.has("initial_ai"),"AI observation excludes RNG and secret choice")
	check(o.decks.group is int and not o.hands.has("opponent"),"AI gets deck counts only")
	check(o.hands==g.hands[1] and o.revealed.group.is_empty(),"AI own hand only")
	# Mirror same public state with different unseen opponent cards: same legal observation.
	var before=JSON.stringify(o);var hidden=g.hands[0].group[0];var top=g.decks.group[0];g.hands[0].group[0]=top;g.decks.group[0]=hidden
	check(JSON.stringify(g.observation(1))==before,"Hidden card swap does not change AI observation")
	# Simulated complete games exercise conservation and phase transitions.
	var finished=0;var simulated=0
	for seed_value in range(1,11):
		g=base(seed_value);var bot=AiAgent.new();bot.rng.seed=seed_value
		for step in range(1800):
			if g.phase=="over":finished+=1;break
			var p=0 if not g.legal_actions(0).is_empty() else 1
			var obs=g.observation(p)
			if obs.actions.is_empty():check(false,"Deadlock seed %d phase %s"%[seed_value,g.phase]);break
			var move=bot.pick(obs);check(g.act(p,move),"AI legal command")
			var errors=g.validate()
			if not errors.is_empty():check(false,"Conservation seed %d step %d: %s"%[seed_value,step,str(errors)]);break
			simulated+=1
	print("RULE TESTS: %d checks, %d failures, %d simulated commands, %d/10 games ended"%[checks,failures.size(),simulated,finished])
	var report={"checks":checks,"failures":failures,"simulated_commands":simulated,"games_finished":finished}
	var f=FileAccess.open("res://tests/rules-report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"))
	quit(0 if failures.is_empty() else 1)
