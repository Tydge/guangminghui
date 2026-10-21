extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	var g=GameState.new(81);g.nodes.clear();g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.discards={"group":[],"plot":[],"resource":[]};g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.graves=[[],[]];g.factions=["I01","I05"];g.phase="main";g.current=0;g.turns=[2,2]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func remove(g: GameState,id: String) -> void:
	for kind in ["group","plot"]:
		g.decks[kind].erase(id);g.discards[kind].erase(id)
		for p in [0,1]:g.hands[p][kind].erase(id);g.graves[p].erase(id)
func put(g: GameState,id: String,p: int,parent: String="") -> void:
	remove(g,id)
	if parent=="":
		for k in g.field(p):
			if g.can_parent(k):parent=k;break
	g._enter(id,p,parent,1)
func give(g: GameState,id: String,p: int) -> void:
	remove(g,id);g.hands[p][g.card(id).kind].append(id)
func attach(g: GameState,id: String,target: String) -> void:remove(g,id);g.nodes[target].attached.append(id)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func apply(g: GameState,p: int,kind: String,args: Dictionary={}) -> void:
	var a=action(g,p,kind,args);check(not a.is_empty(),"Legal "+kind+" "+str(args))
	if not a.is_empty():check(g.act(p,a),"Apply "+kind)
	check(g.validate().is_empty(),"Conservation after "+kind+" "+str(args)+str(g.validate()))
func finish(g: GameState,win: bool=true) -> void:
	g.battle.bonus_a=100 if win else 0;g.battle.rolled=[1,1] if win else [6,6];g._resolve_battle()
func automatic(g: GameState) -> void:
	for i in 15:
		if g.phase!="choice" or g.choice.kind!="w_auto":return
		apply(g,g.choice.player,"trigger")
func context(src: String,target: String,mode: String="control") -> Dictionary:
	return {"src":src,"target":target,"mode":mode,"attacker":0,"defender":1,"paid":[src]}
func _initialize() -> void:
	CardDB.load_all()
	check(CardDB.cards.size()==226 and CardDB.ids("group").size()==150,"213 cards with 150 groups")
	var g=fresh();put(g,"G131",1);put(g,"G001",1);put(g,"G007",0);var b=context("R0","G001","destroy");b.supporters=[{"id":"G007","owner":0}]
	check(g.support_detail("G131",b).power==g.stat("G131","gp")+1,"Jackie adds per attacking supporter")
	b.supporters.resize(8)
	for i in 8:b.supporters[i]={"id":"G007","owner":0}
	check(g.support_detail("G131",b).power==g.stat("G131","gp")+3,"Jackie caps at 3")
	g=fresh();put(g,"G132",1);put(g,"G001",1);put(g,"G007",0);apply(g,0,"attack",{"src":"R0","target":"G001","mode":"destroy"});apply(g,1,"support",{"src":"G132"})
	check(g.battle.army_gp_only and g.support_detail("G007",g.battle).basis=="GP" and g.support_detail("G007",g.battle).power==g.stat("G007","gp")+2,"Miyazaki forces later NATO GP, keeps bonus")
	g.battle.mobilized=true;g.synergy.add_tag("G007","共产");check(g.support_detail("G007",g.battle).basis=="GP","Miyazaki beats mobilization")
	g=fresh();put(g,"G133",0);put(g,"G120",0,"G133");put(g,"G121",0,"G120");check(g.stat("G120","p")==g.card("G120").p+2 and g.stat("G121","p")==g.card("G121").p,"Factory direct aura only")
	g.nodes.G133.silenced=true;check(g.stat("G120","p")==g.card("G120").p,"Factory silence")
	g=fresh();put(g,"G120",0);put(g,"G134",0,"G120");put(g,"G043",0,"G120");put(g,"G044",0,"G120")
	check(g.stat("G120","slots")==3 and g.stat("G134","slots")==2,"Housing adds a slot to its Communist parent only")
	g.nodes.G134.silenced=true;g._after_effect();check(g.choice.kind=="x_overflow" and g.choice.player==0,"Lost aura asks controller to return branch")
	apply(g,0,"choose",{"id":"G043"});check("G043" in g.hands[0].group and g.stat("G120","slots")==2,"Overflow chooses branch, preserves conservation")
	g=fresh();put(g,"G135",0);put(g,"G133",0);apply(g,0,"ability",{"src":"G135","target":"G135"});check(g.stat("G135","p")==3,"Night school effective P target gets lasting +1")
	g.nodes.G135.token=1;g.used.clear();check(action(g,0,"ability",{"src":"G135","target":"G135"}).is_empty(),"School cannot target effective P over 2")
	g.nodes.G135.owner=1;g.nodes.G135.parent="R1";check(g.stat("G135","p")==3,"Learned power survives ownership")
	g._return_subtree("G135");g._enter("G135",1,"R1",1);check(g.stat("G135","p")==2,"Learned power clears on leaving")
	g=fresh();put(g,"G136",0);put(g,"G015",0);give(g,"G043",0);apply(g,0,"ability",{"src":"G015","target":"G043"});check("G043" in g.discards.group and not g.renewal.unused("G136"),"Granary pays cost with no plot in hand")
	give(g,"G044",0);g.used.erase("G015");check(action(g,0,"ability",{"src":"G015","target":"G044"}).is_empty(),"Granary once per turn")
	g=fresh();put(g,"G137",1);give(g,"P28",0);give(g,"P01",1);apply(g,0,"plot",{"id":"P28"});check(g.phase=="plot_response","Tricksters create counter window")
	apply(g,1,"trick",{"src":"G137","fee":"P01"});check(g.world=="" and "P28" in g.discards.plot and "P01" in g.discards.plot and not g.token("G137"),"Tricksters cancel without P15")
	g=fresh();put(g,"G138",0);put(g,"G015",0);put(g,"G014",1);attach(g,"P45","G015");apply(g,0,"ability",{"src":"G138","other":"G015","target":"G014","attachment":"P45"});check("P45" in g.nodes.G014.attached and g.stat("G014","gp")==0,"Smugglers move hostile attachment to enemy")
	g=fresh();put(g,"G139",0);put(g,"G001",1);apply(g,0,"attack",{"src":"R0","target":"G001","mode":"destroy"});apply(g,1,"pass");var a=action(g,0,"support",{"src":"G139","star":true});check(not a.is_empty(),"Optional astrology support")
	var original=g.rng.state;var plan=ActionFlow.plan(g,0,a);check(g.rng.state==original and plan.minor.roll in range(1,7),"Astrology rehearsal cannot advance live RNG")
	var n=g.support_detail("G139",g.battle).power;apply(g,0,"support",{"src":"G139","star":true});check(g.battle.star_roll==plan.minor.roll and g.battle.support_a==n+(2 if plan.minor.roll<=3 else 0),"Astrology roll and support commit match rehearsal")
	g=fresh();put(g,"G140",0);put(g,"G135",0,"G140");check(g.loyalty_defense("G135")==4,"Hidden oath counts fanatic for loyalty only");check(g._common("G135","G140")==0 and g._opposed("G135","G140")==2,"Oath doesn't rewrite battle alignments")
	g=fresh();put(g,"G141",0);put(g,"G028",0);g.nodes.G141.token=0;apply(g,0,"ability",{"src":"G141","target":"G028"});check(g.nodes.G028.parent=="G141" and not g.token("G141"),"Orbit port moves branch free")
	g=fresh();put(g,"G142",1);put(g,"G028",1,"G142");put(g,"G052",1,"G028");g.nodes.G142.parent="G052";g.nodes.G052.parent="R1";check(g.position_defense("G028")==5,"Deep space position floor at depth3")
	g.nodes.G142.silenced=true;check(g.position_defense("G028")==0,"Position floor source silence")
	g=fresh();put(g,"G143",0);put(g,"G043",1);attach(g,"P26","G043");apply(g,0,"attack",{"src":"G143","target":"G043","mode":"destroy"});finish(g);check("P26" in g.discards.plot and g.choice.get("source")=="G143","Loot waits for post-battle cue")
	automatic(g);apply(g,0,"choose",{"id":"P26"});check("P26" in g.hands[0].plot,"Loot recovers chosen attachment")
	g=fresh();put(g,"G144",0);var top=g.decks.group[0];var other=g.decks.plot[0];apply(g,0,"ability",{"src":"G144"});check(g.choice.options==[top,other] and g.observation(1).choice.is_empty(),"Satellite private top-deck choice")
	apply(g,0,"choose",{"id":top});check(g.decks.group.back()==top and g.decks.plot[0]==other,"Only selected top moves to own bottom")
	g=fresh();put(g,"G145",1);apply(g,0,"attack",{"src":"R0","target":"G145","mode":"control"});apply(g,1,"militia");check(g.token("G145") and "G145" not in g.battle.paid and g.battle.self==g.stat("G145","p"),"Militia keeps token, self P, not paid participant")
	apply(g,0,"pass");check(action(g,1,"self_defend").is_empty() and action(g,1,"militia").is_empty(),"Cannot stack free and paid self defense")
	g=fresh();put(g,"G146",1);put(g,"G001",1);apply(g,0,"attack",{"src":"R0","target":"G001","mode":"destroy"});apply(g,1,"support",{"src":"G146"});finish(g,false);automatic(g);check(g.choice.kind=="x_escort","Escort waits until failed battle concludes")
	apply(g,1,"choose",{"id":"G146"});check(g.nodes.G001.parent=="G146" and not g.renewal.unused("G146"),"Escort freely moves defended branch")
	g=fresh();put(g,"G147",0);put(g,"G119",0);put(g,"G001",1);a=action(g,0,"attack",{"src":"G147","target":"G001","mode":"destroy","solo":true});check(not a.is_empty(),"Guerrilla solo option")
	var v=g.attack_preview("G147","G001","destroy",a);check(v.position==0 and g.attack_options("G147","G001","destroy",a).supports.is_empty(),"Solo preview ignores position and shows no support")
	apply(g,0,"attack",{"src":"G147","target":"G001","mode":"destroy","solo":true});apply(g,1,"pass");check(action(g,0,"support").is_empty(),"Solo forbids all ordinary attack support")
	g=fresh();put(g,"G148",1);g.nodes.G148.prepared=true;apply(g,0,"attack",{"src":"R0","target":"G148","mode":"destroy"});check(g.phase=="choice" and g.choice.get("source")=="G148" and g.battle.bonus_d==4,"Enclave prepared cue precedes response")
	automatic(g);check(not g.nodes.G148.prepared,"Enclave prepared consumes after cue")
	g=fresh();put(g,"G148",0);give(g,"G043",0);g.nodes.G148.token=0;apply(g,0,"ability",{"src":"G148","fee":"G043"});check(g.nodes.G148.prepared and not g.token("G148"),"Enclave prepares without spending action")
	g=fresh();put(g,"G149",0);put(g,"G001",0);give(g,"G132",0);apply(g,0,"ability",{"src":"G149","target":"G001","other":"G132"});check(g.alignments("G001")==g.card("G132").align and "G132" in g.exposed and "G132" in g.hands[0].group,"Identity reveal stays hand, target temporary printed alignments")
	g._complete_end();check(g.alignments("G001")==g.card("G001").align,"Identity restores on turn end")
	g=fresh();put(g,"G150",0);put(g,"G099",1);g.nodes.G099.devastated=true;apply(g,0,"attack",{"src":"G150","target":"G099","mode":"control"});finish(g);check(g.wave.devastated("G099") and g.choice.get("source")=="G150","Rebuild waits until capture settlement")
	automatic(g);apply(g,0,"choose",{"id":"G099"});check(not g.wave.devastated("G099") and not g.token("G099") and g.captured.has("G099"),"Captured ruins rebuild without action token")
	# Granary applies to extra costs only, including no-plot Cloud and disaster fees.
	g=fresh();put(g,"G136",0);put(g,"G104",0);put(g,"G001",1);give(g,"G043",0);apply(g,0,"attack",{"src":"R0","target":"G001","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G104","plot_fee":"G043","amplify":true});check("G043" in g.discards.group and not g.renewal.unused("G136"),"Granary funds Cloud with group")
	g=fresh();put(g,"G136",0);put(g,"G043",0);put(g,"G099",1);give(g,"P31",0);give(g,"P50",0);give(g,"G044",0);apply(g,0,"plot",{"id":"P31","target":"G099","payer":"G043"});apply(g,1,"pass");apply(g,0,"plot",{"id":"P50","fee":"G044"});check(g.battle.bonus_a==3 and "G044" in g.discards.group,"Granary pays Cascading Accident for +3, not +6")
	# Long-lived boosts are copied into the rehearsal, not shared with the live module.
	g=fresh();put(g,"G133",0);put(g,"G120",0,"G133");var clone=ActionFlow.copy_state(g);clone.nodes.G133.silenced=true;check(g.stat("G120","p")==4 and clone.stat("G120","p")==2,"Rehearsal aura module points to clone")
	# Attached-slot removal preserves another slot aura instead of using printed capacity.
	g=fresh();put(g,"G135",0);put(g,"G134",0,"G135");attach(g,"P19","G135");put(g,"G043",0,"G135");check(g.synergy.can_detach("G135","P19"),"Detach may keep two children through housing aura")
	# Identity expiry must enforce the reduced Mafia hand limit before advancing turns.
	g=fresh();put(g,"G149",0);put(g,"G051",0);put(g,"G001",0,"G051");g.nodes.G001.mask=["犯罪"];give(g,"P01",0);give(g,"P02",0);give(g,"P03",0);give(g,"P04",0);give(g,"P05",0);give(g,"P06",0);g.end_requested=true;g._complete_end();check(g.phase=="discard" and g.current==0 and g.hand_limit(0)==5,"Identity expiry pauses turn for reduced limit");apply(g,0,"choose",{"id":"P01"});check(g.current==1 and g.turns[0]==3,"Cleanup resumes once without double turn counting")
	var report={"checks":checks,"failures":failures};FileAccess.open("res://tests/renewal-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("RENEWAL: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
