extends SceneTree
var checks=0
var failures: Array=[]

func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failures.append(text);push_error(text)

func fresh() -> GameState:
	var g=GameState.new(81);g.act(0,g.legal_actions(0)[1])
	g.factions=["I02","I02"];g.nodes.R1.card="I02";g.turns=[2,2];g.phase="main";g.current=0
	g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}]
	g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")}
	g.nodes.R0.token=1;g.nodes.R1.token=1
	return g

func place(g: GameState,id: String,p: int,parent: String) -> void:
	g.decks.group.erase(id);g._enter(id,p,parent,1)

func give(g: GameState,id: String,p: int) -> void:
	g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)

func find(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type!=kind:continue
		var matches=true
		for key in args:
			if a.get(key)!=args[key]:matches=false
		if matches:return a
	return {}

func apply(g: GameState,p: int,kind: String,args: Dictionary={}) -> void:
	var a=find(g,p,kind,args);check(not a.is_empty(),"Legal "+kind+str(args))
	if not a.is_empty():check(g.act(p,a),"Accepted "+kind)

func skip_draw(g: GameState,p: int) -> void:
	g.current=p;g._start_turn();apply(g,p,"draw",{"group":false,"plot":false})

func _initialize() -> void:
	var g=fresh()
	# Franchise is a distinct cost path: root may have no marker, but the turn quota remains.
	place(g,"G017",0,"R0");g.nodes.R0.token=0;give(g,"G043",0);give(g,"G001",0)
	check(find(g,0,"auto",{"id":"G001","parent":"G017"}).is_empty(),"Franchise does not waive cost for P3")
	apply(g,0,"auto",{"id":"G043","parent":"G017"})
	check(not g.token("R0") and not g.token("G043") and not g.can_recharge("G043") and g.auto_used,"Free franchise works with an exhausted root but the newcomer cannot act or recharge")
	check(find(g,0,"auto").is_empty(),"Free franchise still consumes the one automatic takeover")
	check(g.validate().is_empty(),"Franchise conservation")
	g=fresh();place(g,"G017",0,"R0");give(g,"G043",0);apply(g,0,"auto",{"id":"G043","parent":"G017"})
	check(g.token("R0"),"Free franchise preserves a ready root marker")
	# Borrowing consumes the extra-recovery quota and skips exactly one future natural refill.
	g=fresh();place(g,"G016",0,"R0");place(g,"G001",0,"G016");g.nodes.G001.token=0;g.nodes.G016.token=0
	apply(g,0,"ability",{"src":"G016","target":"G001"})
	check(g.token("G001") and not g.token("G016") and g.recharged.has("G001") and g.nodes.G001.debt,"Loan is free for lender, readies debtor, and records debt")
	g.nodes.G001.token=0;give(g,"P17",0)
	check(find(g,0,"plot",{"id":"P17","target":"G001"}).is_empty(),"Borrowing shares the recharge limit with plots")
	skip_draw(g,1);check(g.nodes.G001.debt,"Opponent refill does not consume debtor's debt")
	skip_draw(g,0);check(not g.token("G001") and not g.nodes.G001.debt,"Next own refill is skipped exactly once")
	skip_draw(g,0);check(g.token("G001"),"Following natural refill works normally")
	g=fresh();place(g,"G016",0,"R0");place(g,"G001",0,"G016");g.nodes.G001.token=0
	apply(g,0,"ability",{"src":"G016","target":"G001"});g.nodes.G001.owner=1;g.nodes.G001.parent="R1";g.nodes.G001.token=0
	skip_draw(g,1);check(not g.token("G001") and not g.nodes.G001.debt,"Debt follows ownership to the new controller's refill")
	check(g.validate().is_empty(),"Loan transfer conservation")
	# Hollywood adds a tag, not an alignment, and leaving play clears the conversion.
	g=fresh();place(g,"G036",0,"R0");place(g,"G042",0,"R0")
	var align_before=g.alignments("G042");apply(g,0,"ability",{"src":"G036","target":"G042"})
	check(g.has("G042","媒体") and g.alignments("G042")==align_before and CardDB.get_card("G042").tags.is_empty(),"Media conversion is a live extra tag without mutating printed data")
	g.nodes.G042.owner=1;g.nodes.G042.parent="R1";check(g.has("G042","媒体"),"Media conversion survives capture")
	g._return_subtree("G042");check(not g.has("G042","媒体"),"Media conversion clears on leaving play")
	check(g.validate().is_empty(),"Tag conversion conservation")
	# Ads and compute have distinct sizes, caps, durations and source costs.
	g=fresh();place(g,"G037",0,"R0");place(g,"G034",0,"R0")
	apply(g,0,"ability",{"src":"G037","target":"G034"})
	check(g.stat("G034","gp")==2 and g.stat("G034","p")==2 and not g.token("G037"),"Ads increase GP by two up to P without changing P")
	g._complete_end();check(g.stat("G034","gp")==0 and g.nodes.G034.ad_gp==0,"Ads expire at current turn end")
	g=fresh();place(g,"G078",0,"R0");place(g,"G021",0,"R0")
	apply(g,0,"ability",{"src":"G078","target":"G021"})
	check(g.stat("G021","gp")==4 and g.stat("G021","p")==4,"Compute replaces GP with current effective P")
	g._complete_end();check(g.stat("G021","gp")==2 and not g.nodes.G021.compute,"Compute expires at turn end")
	# Relationship auras are recomputed after movement and never double-count both tags.
	g=fresh();place(g,"G073",0,"R0");place(g,"G023",0,"G073")
	check(g.stat("G023","r")==7,"Industrial standard adds two R even when both corporate and scientific")
	g.nodes.G023.parent="R0";check(g.stat("G023","r")==5,"Industrial aura ends after leaving Germany")
	place(g,"G077",0,"R0");place(g,"G011",0,"G077");place(g,"G046",0,"G077")
	check(g.stat("G011","gp")==3,"Finance hub adds one GP, not two, to corporate bank")
	check(g.stat("G046","gp")==1,"Finance hub respects P cap")
	g.nodes.G011.parent="G073";check(g.stat("G011","gp")==2,"Finance aura ends after reparenting")
	# Echo chamber only changes control loyalty, and sibling aid only changes attacking support.
	g=fresh();place(g,"G041",0,"R0");place(g,"G043",0,"G041")
	check(g.loyalty_defense("G043")==8 and g.attack_preview("R1","G043","destroy").loyalty==0,"Echo chamber floors loyalty at eight only against control")
	g.nodes.G043.parent="R0";check(g.loyalty_defense("G043")==0,"Echo chamber ends with the parent relation")
	place(g,"G047",0,"R0");place(g,"G001",0,"R0");give(g,"G080",0)
	var b={"src":"G001","target":"G080","mode":"control","attacker":0,"defender":-1}
	check(g.support_detail("G047",b).basis=="P" and g.support_power("G047",b)==3,"Sibling aid grants P despite no common target alignment")
	b={"src":"R1","target":"G001","mode":"control","attacker":1,"defender":0}
	check(g.support_detail("G047",b).basis=="GP" and g.support_power("G047",b)==1,"Sibling aid does not grant P for defending a sibling")
	# France's new bonus is paid defensive support, never a passive aura or attack bonus.
	g=fresh();place(g,"G036",0,"R0");place(g,"G034",1,"R1")
	var before=g.attack_preview("G036","G034","control");place(g,"G075",1,"R1")
	var after=g.attack_preview("G036","G034","control")
	check(after==before,"France no longer provides a passive cultural aura")
	place(g,"G039",1,"R1")
	for mode in ["control","destroy"]:
		var defense={"src":"G036","target":"G039","mode":mode,"attacker":0,"defender":1}
		check(g.support_power("G075",defense)==g.stat("G075","p")+4,"France adds four to qualified defense of liberal targets: "+mode)
	place(g,"G046",1,"G034")
	var defense={"src":"G036","target":"G046","mode":"control","attacker":0,"defender":1}
	check(g.support_power("G075",defense)==g.stat("G075","gp"),"France gets no bonus defending a non-liberal target")
	var offense={"src":"G034","target":"G036","mode":"destroy","attacker":1,"defender":0}
	check(g.support_power("G075",offense)==g.stat("G075","p"),"France gets only regular P for attacking opposed targets")
	offense.mode="control";check(g.support_power("G075",offense)==g.stat("G075","gp"),"France gets only regular GP for attacking without alignment eligibility")
	apply(g,0,"attack",{"src":"G036","target":"G039","mode":"control"})
	var france_strength=g.battle_values().strength
	apply(g,1,"support",{"src":"G075"})
	check(g.nodes.G075.token==0 and g.battle_values().strength==france_strength-g.stat("G075","p")-4,"France spends a token and its bonus appears in actual battle values")
	check(g.battle.entries.back().text.contains("+8"),"France's complete support contribution is public")
	# Bavaria needs both six non-root groups and forty-five total effective P.
	g=fresh();g.factions[0]="I01";g.nodes.R0.card="I01"
	for id in ["G005","G007","G003"]:place(g,id,0,"R0")
	for id in ["G011","G020"]:place(g,id,0,"G005")
	check(not g.goal(0).met and g.goal(0).text.contains("5/6") and g.goal(0).text.ends_with("/45"),"Bavaria no longer wins at the old five-group threshold")
	place(g,"G073",0,"G007")
	check(not g.goal(0).met and g.goal(0).text.contains("6/6") and g.goal(0).text.ends_with("44/45"),"Six groups still need forty-five power")
	g._return_subtree("G073")
	place(g,"G071",0,"G007")
	check(g.goal(0).met,"Bavaria wins only when both new count and power thresholds are met")
	g._return_subtree("G071");check(not g.goal(0).met,"Losing a group breaks Bavaria's new victory condition")
	check(g.validate().is_empty(),"New victory thresholds preserve the normal game structure")
	# Streaming triggers on resolved plots once, never on a countered plot.
	g=fresh();place(g,"G035",0,"R0");place(g,"G032",0,"G035");give(g,"P26",0)
	g.decks.plot.erase("P10");g.decks.plot.push_front("P10")
	apply(g,0,"plot",{"id":"P26","target":"G032"})
	check(g.hands[0].plot==["P10"] and g.rewards.has("G035"),"First settled plot pays one streaming dividend")
	give(g,"P27",0);apply(g,0,"plot",{"id":"P27","target":"G032"})
	check(g.hands[0].plot==["P10"],"Streaming does not repeat within a turn")
	g=fresh();place(g,"G035",0,"R0");place(g,"G032",0,"G035");give(g,"P26",0);give(g,"P15",1)
	apply(g,0,"plot",{"id":"P26","target":"G032"});apply(g,1,"counter")
	check(g.hands[0].plot.is_empty() and not g.rewards.has("G035"),"Countered plot earns no streaming dividend")
	check(g.validate().is_empty(),"Streaming and counter conservation")
	# Japan privately filters four, preserves bottom order, permits decline, and never reveals peek to opponent.
	for decline in [false,true]:
		g=fresh();place(g,"G072",0,"R0")
		var peek=["G034","G001","G043","G017"]
		for id in peek:g.decks.group.erase(id)
		g.decks.group=peek+g.decks.group
		apply(g,0,"ability",{"src":"G072"})
		check(g.phase=="choice" and g.choice.peek==peek and g.choice.options==["G034","G043"],"Japan filters media or weird from exactly four existing cards")
		check(g.observation(1).choice.is_empty(),"Japan peek remains private")
		check(g.validate().is_empty(),"Japan pending-choice conservation")
		apply(g,0,"choose",{"id":"" if decline else "G043"})
		check(g.decks.group.slice(-4 if decline else -3)==(peek if decline else ["G034","G001","G017"]),"Japan bottoms unchosen cards in original order")
		check(g.validate().is_empty(),"Japan resolved conservation")
	g=fresh();place(g,"G072",0,"R0")
	for id in ["G001","G002","G003","G004"]:g.decks.group.erase(id)
	g.decks.group=["G001","G002","G003","G004"]+g.decks.group
	apply(g,0,"ability",{"src":"G072"})
	check(g.phase=="choice" and g.choice.options.is_empty() and g.choice.peek.size()==4 and g.legal_actions(0).size()==1,"Even without a valid choice, the player can inspect all peeked cards before returning them")
	apply(g,0,"choose",{"id":""});check(g.validate().is_empty(),"No-match peek preserves all cards")
	# England selects only combat plots among the discard top three, and locks reclaimed cards this turn.
	g=fresh();place(g,"G074",0,"R0")
	for id in ["P14","P10","P15"]:g.decks.plot.erase(id);g.discards.plot.append(id)
	check(find(g,0,"ability",{"src":"G074","target":"P14"}).is_empty(),"England rejects main-stage plot in the same top-three window")
	apply(g,0,"ability",{"src":"G074","target":"P10"})
	check(g.hands[0].plot==["P10"] and "P10" in g.locked and "P10" in g.exposed and g.discards.plot==["P14","P15"],"England recovers and locks the chosen combat plot, preserving other positions")
	check(g.validate().is_empty(),"England conservation")
	# UN is an explicit response, logged with value, unavailable on control attacks.
	g=fresh();place(g,"G005",0,"R0");place(g,"G043",1,"R1");place(g,"G008",1,"R1")
	apply(g,0,"attack",{"src":"G005","target":"G043","mode":"destroy"})
	var strength=g.battle_values().strength;apply(g,1,"mediate")
	check(g.battle_values().strength==strength-3 and not g.token("G008") and g.used.has("G008"),"Mediation spends UN marker and reduces attack strength by three")
	check(g.battle.entries.back().kind=="mediate" and g.battle.entries.back().text.contains("+3"),"Mediation has a public battle entry")
	g=fresh();place(g,"G005",0,"R0");place(g,"G043",1,"R1");place(g,"G008",1,"R1")
	apply(g,0,"attack",{"src":"G005","target":"G043","mode":"control"})
	check(find(g,1,"mediate").is_empty(),"UN mediation is not available on control attacks")
	print("MODERN MECHANICS: %d checks, %d failures"%[checks,failures.size()])
	var f=FileAccess.open("res://tests/modern-mechanics-report.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));quit(0 if failures.is_empty() else 1)
