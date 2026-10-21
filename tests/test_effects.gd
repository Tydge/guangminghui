extends SceneTree
var checks=0
var failures: Array=[]

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message);push_error(message)

func fresh() -> GameState:
	var g=GameState.new(151)
	g.act(0,g.legal_actions(0)[2])
	g.factions=["I03","I03"];g.nodes.R1.card="I03";g.phase="main";g.current=0;g.turns=[2,2]
	g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.discards={"group":[],"plot":[]}
	g.nodes.R0.token=1;g.nodes.R1.token=1
	return g

func place(g: GameState,id: String,p: int,parent: String) -> void:
	g.decks.group.erase(id);g.hands[0].group.erase(id);g.hands[1].group.erase(id);g._enter(id,p,parent,1)

func give(g: GameState,id: String,p: int) -> void:
	var kind=CardDB.get_card(id).kind;g.decks[kind].erase(id);g.hands[p][kind].append(id)

func find(g: GameState,p: int,type: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type!=type:continue
		var match_all=true
		for key in args:
			if a.get(key)!=args[key]:match_all=false
		if match_all:return a
	return {}

func apply(g: GameState,p: int,type: String,args: Dictionary={}) -> void:
	var a=find(g,p,type,args);check(not a.is_empty(),"Legal "+type+str(args))
	if not a.is_empty():check(g.act(p,a),"Accepted "+type)

func low_dice(g: GameState) -> void:
	var r=RandomNumberGenerator.new()
	for s in range(1,50):
		r.seed=s
		if r.randi_range(1,6)+r.randi_range(1,6)<=10:g.rng.seed=s;return

func resolve(g: GameState) -> void:
	low_dice(g)
	while g.phase=="battle":apply(g,g.battle.responder,"pass")
	automatic(g)

func automatic(g: GameState) -> void:
	for i in 12:
		if g.phase!="choice" or g.choice.kind!="w_auto":return
		apply(g,g.choice.player,"trigger")

func _initialize() -> void:
	CardDB.load_all()
	# Every simple control modifier is checked against the approved value.
	var cases={"G001":["G051",2],"G029":["G045",3],"G032":["G038",2],"G040":["G070",2],"G045":["G029",2],"G048":["G080",3],"G060":["G051",2],"G062":["G059",2],"G064":["G069",2],"G070":["G074",2]}
	for id in cases:
		var g=fresh();place(g,id,0,"R0");give(g,cases[id][0],0)
		check(g.attack_preview(id,cases[id][0],"control").ability==cases[id][1],id+" control modifier")
	for row in [["G019","G059",2],["G027","G066",2],["G053","G043",2],["G057","G043",2],["G079","G051",2]]:
		var g=fresh();place(g,row[0],0,"R0");place(g,row[1],1,"R1");check(g.attack_preview(row[0],row[1],"destroy").ability==row[2],row[0]+" destroy modifier")
	for row in [["G049",2],["G058",2],["G061",3],["G071",10]]:
		var g=fresh();place(g,"G001",0,"R0");place(g,row[0],1,"R1");check(g.attack_preview("G001",row[0],"destroy").defense==row[1],row[0]+" destroy defense")
	for row in [["G042",3],["G039",2]]:
		var g=fresh();place(g,"G001",0,"R0");place(g,row[0],1,"R1");check(g.attack_preview("G001",row[0],"control").defense==row[1],row[0]+" control defense")
	var g=fresh();place(g,"G076",1,"R1");check(g.attack_preview("R0","G076","destroy").base==7,"Swiss resistance destroy base")
	place(g,"G005",0,"R0");place(g,"G006",0,"G005");place(g,"G001",1,"R1")
	var b={"src":"G005","target":"G001","mode":"destroy","attacker":0,"defender":1}
	check(g.support_power("G006",b)==3,"Pentagon military full power")
	g=fresh();place(g,"G025",0,"R0");place(g,"G010",0,"G025");give(g,"G043",0)
	b={"src":"G025","target":"G043","mode":"control","attacker":0,"defender":-1};check(g.support_power("G010",b)==2,"Phone children full power")
	g=fresh();place(g,"G054",0,"R0");place(g,"G023",1,"R1");place(g,"G024",1,"G023")
	b={"src":"G054","target":"G024","mode":"destroy","attacker":0,"defender":1};check(g.support_power("G023",b)==0,"Ninja excludes immediate parent")
	# Draw replacements keep one and bottom the other, conserving all cards.
	for id in ["G012","G066"]:
		g=fresh();place(g,id,0,"R0");g.phase="draw";apply(g,0,"draw",{"group":id=="G066","plot":id=="G012"})
		check(g.phase=="choice" and g.choice.options.size()==2,id+" two choices")
		var options=g.choice.options.duplicate();apply(g,0,"choose",{"id":options[0]})
		var kind="group" if id=="G066" else "plot"
		check(options[0] in g.hands[0][kind] and g.decks[kind].back()==options[1],id+" bottom unchosen")
		check(g.validate().is_empty(),id+" conservation")
	# Each active mechanism is exercised, including no-cost trades and information choices.
	for id in ["G002","G003","G004","G010","G011","G013","G015","G018","G020","G022","G028","G038","G046","G056","G059","G065","G080"]:
		g=fresh();place(g,id,0,"R0")
		if id in ["G002","G038"]:give(g,"G043" if id=="G002" else "P10",1)
		if id in ["G003","G059"]:place(g,"G024",1,"R1")
		if id in ["G015"]:give(g,"P10",0)
		if id=="G046":give(g,"G043",0)
		if id=="G018":place(g,"G043",0,id)
		if id=="G022":place(g,"G023",0,"R0")
		if id=="G020":place(g,"G024",0,id);g.nodes.G024.token=0
		if id=="G065":place(g,"G064",0,"R0")
		if id in ["G013","G056"]:
			var k="P10" if id=="G013" else "G043";var kind="plot" if id=="G013" else "group";g.decks[kind].erase(k);g.discards[kind].push_front(k)
		var a=find(g,0,"ability",{"src":id});check(not a.is_empty(),id+" has legal activation")
		if not a.is_empty():
			g.act(0,a);check(g.used.has(id),id+" once per global turn")
			var guard=0
			while g.phase=="choice" and guard<6:
				guard+=1;g.act(0,g.legal_actions(0)[0])
			check(g.validate().is_empty(),id+" post-ability conservation")
	# Red Cross replacement returns entire branch without a kill or reward.
	g=fresh();place(g,"G052",0,"R0");place(g,"G063",1,"R1");place(g,"G051",1,"G063");place(g,"G043",1,"G051")
	apply(g,0,"attack",{"src":"G052","target":"G051","mode":"destroy"});apply(g,1,"rescue");g.battle.bonus_a=100;resolve(g)
	check("G051" in g.hands[1].group and "G043" in g.hands[1].group and g.destroyed[0]==0,"Rescue entire subtree no kill")
	check(not g.rewards.has("G052"),"Rescue prevents kill reward")
	# Hoax cancels effects without refunding plot or token fees.
	g=fresh();place(g,"G024",0,"R0");give(g,"P24",0);give(g,"P15",1)
	apply(g,0,"plot",{"id":"P24"});check(g.phase=="plot_response","Hoax reaction window")
	apply(g,1,"counter");check(not g.token("G024") and g.hands[0].plot.is_empty(),"Hoax keeps paid costs")
	check("P24" in g.discards.plot and "P15" in g.discards.plot,"Counter cards discarded")
	# Main phase plot behaviors, all costs and conservation.
	for id in ["P14","P17","P18","P19","P21","P22","P23","P24","P25","P26","P27","P28","P29","P30"]:
		g=fresh();place(g,"G024",0,"R0");place(g,"G043",0,"G024");place(g,"G064",1,"R1");give(g,id,0);give(g,"P10",1);give(g,"G042",0)
		if id=="P17":g.nodes.G043.token=0
		apply(g,0,"plot",{"id":id})
		if g.phase=="choice":apply(g,0,"choose")
		check(g.validate().is_empty(),id+" conservation")
	# Attachment and world auras affect P/R, not printed GP.
	g=fresh();place(g,"G010",0,"R0");give(g,"P27",0);apply(g,0,"plot",{"id":"P27"});check(g.stat("G010","p")==3 and g.stat("G010","gp")==0,"Grassroots P only")
	give(g,"P28",0);apply(g,0,"plot",{"id":"P28"});check(g.stat("G010","p")==4 and g.stat("G010","r")==4,"Law and Order P R")
	give(g,"P29",0);apply(g,0,"plot",{"id":"P29"});check(g.world=="P29" and "P28" in g.discards.plot,"One world order slot")
	# Combat plots P01-13/P20 and Foiled resolve through alternating responses.
	for number in range(1,14):
		g=fresh();var trait_cards=["G001","G001","G064","G051","G024","G041","G070","G063","G042"]
		var leader=trait_cards[number-1] if number<=9 else "G005";place(g,leader,0,"R0");place(g,"G024" if leader!="G024" else "G023",1,"R1")
		var target="G024" if leader!="G024" else "G023";var id="P%02d"%number;give(g,id,0 if number<=9 or number>=12 else 1)
		apply(g,0,"attack",{"src":leader,"target":target,"mode":"destroy" if number==13 else "control"})
		if number<=9 or number>=12:apply(g,1,"pass")
		apply(g,0 if number<=9 or number>=12 else 1,"plot",{"id":id})
		resolve(g);check(g.validate().is_empty(),id+" combat conservation")
	g=fresh();give(g,"G043",0);give(g,"P16",1);give(g,"P15",0);apply(g,0,"attack",{"src":"R0","target":"G043"});apply(g,1,"plot",{"id":"P16"});apply(g,0,"counter");check(g.phase=="battle" and not g.battle.get("foiled",false),"Hoax can cancel Foiled")
	resolve(g)
	# Video Games may recover once after supporting its Computer leader.
	g=fresh();place(g,"G021",0,"R0");place(g,"G024",0,"G021");give(g,"G043",0)
	apply(g,0,"attack",{"src":"G021","target":"G043"});apply(g,1,"pass");apply(g,0,"support",{"src":"G024"});g.battle.bonus_a=100;resolve(g)
	check(g.token("G024") and g.recharged.has("G024"),"Video Games recovers after Computer support")
	g.nodes.G024.token=0;check(not g.can_recharge("G024"),"Video Games shares the recharge quota")
	g=fresh();place(g,"G026",0,"R0");place(g,"G051",0,"R0");place(g,"G052",0,"G051");place(g,"G055",0,"G051")
	check(g.hand_limit(0)==8,"EFF and two criminal Mafia children stack")
	g=fresh();place(g,"G031",0,"R0");place(g,"G032",0,"G031");place(g,"G034",0,"G031");g.phase="draw";apply(g,0,"draw",{"group":false,"plot":false})
	check(g.hands[0].plot.size()==1,"Big Media bonus even when normal draws skipped")
	g=fresh();place(g,"G023",1,"R1");place(g,"G006",1,"G023");check(g.attack_preview("R0","G023","control").defense==2,"Secret Service protects parent passively")
	g=fresh();place(g,"G007",0,"R0");place(g,"G043",1,"R1");b={"src":"R0","target":"G043","mode":"destroy","attacker":0,"defender":1}
	check(g.support_power("G007",b)==8,"NATO destroy support +2")
	g=fresh();place(g,"G050",0,"R0");place(g,"G043",0,"G050");place(g,"G041",0,"G050");give(g,"G042",0);b={"src":"R0","target":"G042","mode":"control","attacker":0,"defender":-1}
	check(g.support_power("G050",b)==4,"Elvis direct weird choir +2")
	for source in ["G033","G044","G069"]:
		g=fresh();place(g,source,0,"R0")
		var incoming={"G033":"G043","G044":"G023","G069":"G064"}[source];give(g,incoming,0)
		if source=="G033":give(g,"P10",0)
		apply(g,0,"auto",{"id":incoming,"parent":"R0" if source=="G044" else source})
		automatic(g)
		if source=="G033":apply(g,0,"choose",{"id":"P10"});check(g.hands[0].plot.size()==1 and "P10" in g.discards.plot,"Empty Vee optional replace")
		else:check(g.hands[0].group.size()==1,source+" entry reward")
		check(g.validate().is_empty(),source+" entry conservation")
	g=fresh();place(g,"G024",1,"R1");give(g,"P20",1);apply(g,0,"attack",{"src":"R0","target":"G024"});apply(g,1,"plot",{"id":"P20"});check(g.battle.bonus_d==4,"Computer Security +4");resolve(g)
	# Below-two failure keeps the hand recruit retryable, including automatic takeover.
	g=fresh();place(g,"G022",0,"R0");give(g,"G071",0);apply(g,0,"attack",{"src":"G022","target":"G071"});resolve(g)
	check("G071" in g.hands[0].group and "G071" in g.failed_recruits,"Failed recruit remains pending")
	apply(g,0,"auto",{"id":"G071","parent":"R0"});check(not g.token("G071") and not g.can_recharge("G071") and "G071" not in g.failed_recruits,"Auto may rescue failed recruit without granting an action")
	for source in ["G012","G066"]:
		g=fresh();place(g,source,0,"R0");g.phase="draw"
		var args={"group":source=="G066","plot":source=="G012","filter_group":false,"filter_plot":false}
		apply(g,0,"draw",args);check(g.phase=="main" and g.hands[0]["group" if source=="G066" else "plot"].size()==1,source+" replacement is optional")
	g=fresh();place(g,"G028",0,"R0")
	for id in ["G027","G066","G023"]:g.decks.group.erase(id);g.decks.group.push_front(id)
	var peek=g.decks.group.slice(0,3);apply(g,0,"ability",{"src":"G028"});apply(g,0,"choose",{"id":""})
	check(g.hands[0].group.is_empty() and g.decks.group.slice(-3)==peek,"NASA may decline and keeps bottom order")
	check(g.validate().is_empty(),"NASA decline conserves cards")
	print("EFFECT TESTS: %d checks, %d failures"%[checks,failures.size()])
	var f=FileAccess.open("res://tests/effects-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));quit(0 if failures.is_empty() else 1)
