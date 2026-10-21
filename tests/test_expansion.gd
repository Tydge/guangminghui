extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fresh() -> GameState:
	var g=GameState.new(81);g.nodes.clear();g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.discards={"group":[],"plot":[],"resource":[]};g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.graves=[[],[]];g.factions=["I01","I06"];g.phase="main";g.current=0;g.turns=[2,2]
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
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func apply(g: GameState,p: int,kind: String,args: Dictionary={}) -> void:
	var a=action(g,p,kind,args);check(not a.is_empty(),"Legal "+kind+" "+str(args))
	if not a.is_empty():check(g.act(p,a),"Apply "+kind)
func finish(g: GameState,dice: Array=[1,1]) -> void:
	g.battle.bonus_a=100;g.battle.rolled=dice;g._resolve_battle()
func automatic(g: GameState) -> void:
	for i in 12:
		if g.phase!="choice" or g.choice.kind!="w_auto":return
		var p=g.choice.player;apply(g,p,"trigger")
func _initialize() -> void:
	CardDB.load_all();check(CardDB.cards.size()==226,"All 226 cards loaded")
	check(CardDB.ids("faction").size()==8 and CardDB.ids("group").size()==150 and CardDB.ids("plot").size()==58 and CardDB.ids("resource").size()==10,"8/150/58/10 composition")
	check(CardDB.get_card("G099").p==3 and CardDB.get_card("G099").r==4 and CardDB.get_card("G091").gp==0,"Preserved user numeric changes")
	check(CardDB.get_card("G092").align==["政府"] and "计算机" not in CardDB.get_card("G092").tags and "军队" not in CardDB.get_card("G093").tags,"Preserved user alignment/tag changes")
	var g=fresh();put(g,"G081",0);put(g,"G028",0,"G081");check(g.has("G028","计算机"),"Musk gives computer to printed Space")
	g.nodes.G081.silenced=true;check(not g.has("G028","计算机"),"Silence removes Musk continuous grant");g.nodes.G081.silenced=false
	g.nodes.G028.parent="R0";check(not g.has("G028","计算机"),"Musk grant ends on leaving direct child")
	g=fresh();put(g,"G097",0);put(g,"G094",1);check(g.attack_preview("G097","G094","control").ability==5,"Canada green control +4 in preview")
	check(g.attack_preview("G097","G094","destroy").ability==0,"Canada no destroy bonus")
	put(g,"G071",1);check(g.attack_preview("G097","G071","destroy").defense==10,"China destroy defense +10")
	g.nodes.G071.devastated=true;check(g.stat("G071","p")==3 and g.stat("G071","gp")==0,"Devastation halves P/GP, including odd GP")
	check(not g.token("G071") and not g.can_recharge("G071"),"Devastated units cannot act/recharge")
	check(g.wave.disaster_preview({"id":"P31","payer":"G097","target":"G071"}).defense==10,"China disaster defense +10")
	g=fresh();put(g,"G083",0);give(g,"G043",0);apply(g,0,"ability",{"src":"G083"});check(g.wave.plans.has(0),"Altman stores public plan")
	g.nodes.G083.token=1;g.wave.plans[0]=[3,3];apply(g,0,"attack",{"src":"G083","target":"G043","use_plan":true});check(g.battle.fixed_dice==[3,3] and not g.wave.plans.has(0),"Plan fixed at attack start and consumed")
	g.battle.bonus_a=100;g._resolve_battle();check(g.last_battle.dice==[3,3] and g.last_battle.success,"Plan used as final dice")
	g=fresh();put(g,"G088",0);g.wave.end_turn();check(g.nodes.G088.training==1,"Ronaldo gains training with saved marker");give(g,"G043",0);apply(g,0,"attack",{"src":"G088","target":"G043","training":true});check(g.battle.bonus_a==2 and g.nodes.G088.training==0,"Training spent only on leading attack")
	g=fresh();put(g,"G087",0);put(g,"G043",1);give(g,"P01",0);give(g,"P03",0);apply(g,0,"attack",{"src":"G087","target":"G043","mode":"control"});apply(g,1,"pass");apply(g,0,"plot",{"id":"P01"});apply(g,1,"pass");apply(g,0,"plot",{"id":"P03"});check(g.phase=="choice" and g.choice.kind=="w_auto" and g.hands[0].plot.is_empty(),"Obama benefit waits for presentation command");automatic(g);check(g.used.has("G087") and g.hands[0].plot.size()==1,"Obama rewards two resolved alignment plots")
	g=fresh();put(g,"G086",0);apply(g,0,"ability",{"src":"G086"});check(g.hands[0].group.size()==1 and g.hands[1].group.size()==1 and g.hands[0].plot.size()==1,"MrBeast symmetric groups and own plot")
	g=fresh();put(g,"G082",0);give(g,"P36",0);g._discard(0,"P36");apply(g,0,"ability",{"src":"G082","target":"P36"});check(g.world=="P36" and not g.discards.plot.has("P36"),"Trump activates discarded world order")
	g=fresh();put(g,"G090",0);give(g,"G017",0);apply(g,0,"ability",{"src":"G090","target":"G017"});check("G017" in g.exposed,"Lei Jun announces group publicly");apply(g,0,"attack",{"src":"R0","target":"G017","mode":"control"});finish(g);check(g.phase=="choice" and g.choice.source=="G090" and g.hands[0].plot.is_empty(),"Announced recruitment reward waits until control settles");automatic(g);check(g.hands[0].plot.size()==1,"Announced corporate recruitment draws plot")
	g=fresh();put(g,"G092",0);put(g,"G023",0,"G092");put(g,"G043",1);var b={"src":"R0","target":"G043","mode":"control","attacker":0,"defender":1};check(g.support_detail("G092",b).basis=="GP" and g.support_power("G092",b)==g.stat("G092","gp"),"India uses its own GP without resources")
	g=fresh();put(g,"G003",0);put(g,"G103",0);put(g,"G004",0);put(g,"G104",0,"G103");put(g,"G011",1);give(g,"P11",0);apply(g,0,"attack",{"src":"G003","target":"G011","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G004"});apply(g,1,"pass");var amplified=action(g,0,"support",{"src":"G104","amplify":true});check(not amplified.is_empty() and amplified.power==10,"Cloud doubles base P then Nvidia adds +2")
	if not amplified.is_empty():g.act(0,amplified)
	check(g.battle.computer_supports[0]==2 and "P11" in g.discards.plot,"Amplification costs plot and records computer sequence")
	g=fresh();put(g,"G095",1);put(g,"G094",1);put(g,"G104",0);b={"src":"R0","target":"G094","mode":"control","attacker":0,"defender":1};check(g.support_power("G104",b)==0,"Indonesia blocks noncoastal GP support")
	put(g,"G111",0);put(g,"G098",0);check(g.support_detail("G098",b).basis=="P","Shipping alliance allows coastal P")
	g=fresh();put(g,"G100",1);put(g,"G094",1);put(g,"G002",0);put(g,"G003",0);put(g,"G007",0);apply(g,0,"attack",{"src":"G002","target":"G094","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G003"});apply(g,1,"pass");check(action(g,0,"support",{"src":"G007"}).is_empty(),"Canal second support needs group fee");give(g,"G043",0);check(action(g,0,"support",{"src":"G007","group_fee":"G043"}).size()>0,"Canal fee selectable")
	g=fresh();put(g,"G105",0);apply(g,0,"ability",{"src":"G105"});check(g.phase=="choice" and g.validate().is_empty(),"Draft pending cards conserved");var selected=g.choice.options[0];apply(g,0,"choose",{"id":selected});check(g.choice.player==1 and selected in g.hands[0].group and selected in g.exposed,"Draft first choice visible");apply(g,1,"choose",{"id":g.choice.options[0]});check(g.discards.group.size()==1 and g.validate().is_empty(),"Draft remainder discarded and conserved")
	g=fresh();put(g,"G106",1);give(g,"P22",0);give(g,"P10",1);g.exposed.append("P22");apply(g,0,"plot",{"id":"P22"});check(g.phase=="plot_response","Previously exposed plot allows fact check");apply(g,1,"fact_check");check(g.phase=="choice" and g.choice.kind=="w_tax","Fact check asks attacker to pay");apply(g,0,"choose",{"id":""});check(g.pending_plot.is_empty() and "P22" in g.discards.plot and not g.token("G106"),"Fact check cancel consumes original costs")
	g=fresh();put(g,"G109",0);put(g,"G097",0);g.nodes.G097.devastated=true;give(g,"P41",0);check(g.legal_actions(0).filter(func(a):return a.type=="rebuild" and a.target=="G097" and a.payers.size()==2).size()>0,"Huge normal rebuild needs two different actors")
	apply(g,0,"ability",{"src":"G109","target":"G097"});check(not g.wave.devastated("G097") and not g.token("G109"),"Engineers rebuild huge with one marker")
	g=fresh();put(g,"G110",1);put(g,"G097",1);give(g,"P31",0);put(g,"G043",0);apply(g,1,"ability",{"src":"G110","target":"G097"}) if false else g.nodes.G097.set("prepared",true)
	give(g,"P15",1);apply(g,0,"plot",{"id":"P31","payer":"G043","target":"G097"});check(g.phase=="plot_response" and g.token("G097") and g.nodes.G097.prepared,"Hoax window precedes marker/preparation removal");apply(g,1,"counter");check(g.nodes.G097.prepared and g.token("G097") and not g.token("G043"),"Cancelled disaster retains defense but not paid fee")
	g=fresh();put(g,"G043",0);put(g,"G009",1);put(g,"G097",1,"G009");give(g,"P35",0);g.nodes.G097.prepared=true;apply(g,0,"plot",{"id":"P35","payer":"G043","target":"G097"});automatic(g);check(g.token("G097") and not g.nodes.G097.prepared and g.battle.bonus_d==4,"Court preserves initial marker while preparation consumed");check(not action(g,1,"self_defend").is_empty(),"Protected target may self-defend in disaster");finish(g);check(g.wave.devastated("G097") and not g.token("G097") and g.destroyed[0]==0,"Disaster devastation clears protected marker, not a kill")
	g=fresh();put(g,"G043",0);put(g,"G093",1);put(g,"G017",1,"G093");put(g,"G024",1,"G093");apply(g,0,"attack",{"src":"G043","target":"G093","mode":"destroy"});finish(g);check(not g.nodes.has("G093") and "G017" in g.hands[1].group and "G024" in g.hands[1].group and g.destroyed[0]==1,"Russia now follows ordinary destruction without branch inheritance")
	g=fresh();put(g,"G043",0);put(g,"G063",1);put(g,"G094",1,"G063");give(g,"P31",0);apply(g,0,"plot",{"id":"P31","payer":"G043","target":"G094"});apply(g,1,"rescue");finish(g);check("G094" in g.hands[1].group and g.destroyed[0]==0 and g.last_battle.rescued,"Red Cross replaces entire disaster outcome")
	g=fresh();put(g,"G084",0);put(g,"G101",0);put(g,"G043",1);g.current=1;apply(g,1,"attack",{"src":"G043","target":"G084","mode":"destroy"});apply(g,0,"wave",{"src":"G101"});check(g.nodes.G084.parent=="G101" and g.phase=="battle" and not g.token("G101"),"Dubai moves attacked celebrity but battle continues")
	g=fresh();g.factions[0]="I06";g.nodes.R0.card="I06";put(g,"G023",0);put(g,"G043",0);put(g,"G017",0,"G023");var fold=action(g,0,"ability",{"src":"R0","target":"G043","other":"G017"});check(not fold.is_empty(),"Bermuda legal non-nested swap offered")
	if not fold.is_empty():g.act(0,fold)
	check(g.nodes.G017.parent=="R0" and g.nodes.G043.parent=="G023" and g.token("R0") and g.validate().is_empty(),"Bermuda swaps slots without marker or conservation changes")
	g=fresh();put(g,"G084",0);put(g,"G099",0);apply(g,0,"ability",{"src":"G084","parent":"G099"});check(g.nodes.G084.parent=="G099" and g.hands[0].plot.size()==1 and not g.token("G084"),"Taylor tours to a place, paying one marker and drawing")
	g=fresh();put(g,"G085",0);put(g,"G071",1);give(g,"P11",0);apply(g,0,"attack",{"src":"R0","target":"G071","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G085"});g.battle.bonus_a+=2-g.battle_values().strength;g.battle.rolled=[1,2];g._resolve_battle();check(g.choice.get("kind","")=="w_reroll","Beyonce offers one paid reroll on an ordinary failed roll");apply(g,0,"choose",{"id":"P11"});check(g.last_battle.get("rerolled",false) and "P11" in g.discards.plot,"Encore pays once and closes battle without another response round")
	g=fresh();put(g,"G089",0);put(g,"G016",0);put(g,"G071",1);apply(g,0,"attack",{"src":"R0","target":"G071","mode":"control"});apply(g,1,"pass");apply(g,0,"wave",{"src":"G089","target":"G016"});check("G089" not in g.battle.paid and not g.token("G089"),"Messi's paid ability is not ordinary participation");apply(g,1,"pass");check(action(g,0,"support",{"src":"G016"}).get("basis","")=="P","Messi grants full P to one unspent ally")
	g=fresh();put(g,"G091",0);put(g,"G020",0);put(g,"G071",1);give(g,"G043",0);apply(g,0,"attack",{"src":"R0","target":"G071","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G020"});check(g.choice.get("kind","")=="w_export","South Africa offers commodity conversion after science support");apply(g,0,"choose",{"id":"G043"});check(g.decks.group.back()=="G043" and g.hands[0].plot.size()==1 and g.phase=="battle","Commodity card goes openly to bottom without changing response order")
	g=fresh();put(g,"G096",0);put(g,"G017",0,"G096");give(g,"G043",0);apply(g,0,"ability",{"src":"G096","leader":"G017","target":"G043"});check(g.token("G017") and not g.token("G096") and "G017" in g.battle.paid and "G096" not in g.battle.paid,"Mexico delegates marker while only child counts as attack participant")
	g=fresh();put(g,"G094",0);put(g,"G062",0);put(g,"G099",0);put(g,"G109",0,"G094");g.nodes.G062.token=0;g.nodes.G099.devastated=true;g.nodes.G099.token=0;apply(g,0,"ability",{"src":"G109","target":"G099"});check(g.choice.get("kind","")=="w_recharge","Brazil offers green recovery after own rebuild");apply(g,0,"choose",{"id":"G062"});check(g.token("G062") and g.recharged.has("G062") and g.used.has("G094"),"Brazil obeys shared recovery quota")
	g=fresh();put(g,"G098",1);put(g,"G110",1);put(g,"G099",1);g.current=1;apply(g,1,"ability",{"src":"G110","target":"G099"});check(g.nodes.G099.prepared and not g.token("G110"),"Vaccine alliance adds one preparation for one marker");g.current=0;put(g,"G043",0);give(g,"P32",0);apply(g,0,"plot",{"id":"P32","payer":"G043","target":"G099"});automatic(g);check(not g.nodes.G099.prepared and g.hands[1].group.is_empty() and not g.used.has("G098"),"Australia no longer rewards disaster preparation")
	g=fresh();put(g,"G099",0);put(g,"G017",0,"G099");put(g,"G101",0);apply(g,0,"ability",{"src":"G099","target":"G017","parent":"G101"});check(g.nodes.G017.parent=="G101" and g.token("G099") and g.hands[0].group.size()==1,"Port transfers direct subtree free and draws once")
	g=fresh();put(g,"G102",0);give(g,"P11",0);g.rng.seed=23;var gamble=g._die();g.rng.seed=23;apply(g,0,"ability",{"src":"G102","target":"P11"});check(g.hands[0].plot.size()==(3 if gamble>=4 else 0) and g.token("G102"),"Vegas pays only a plot and uses one public die")
	g=fresh();put(g,"G107",0);give(g,"P13",0);g.locked.append("P13");g.exposed.append("P13");g.discards.plot.append_array(g.decks.plot);g.decks.plot.clear();apply(g,0,"ability",{"src":"G107","target":"P13"});check("P13" in g.hands[0].plot and "P13" in g.locked and g.hands[0].group.size()==1 and g.validate().is_empty(),"PR reshuffle does not bypass lock and rewards previously public card")
	g=fresh();put(g,"G043",0);put(g,"G108",1);put(g,"G099",1);give(g,"P32",0);apply(g,0,"plot",{"id":"P32","payer":"G043","target":"G099"});finish(g);check(g.choice.get("kind","")=="w_auto" and g.hands[1].plot.is_empty(),"Insurance payout waits for automatic presentation");automatic(g);check(g.hands[1].plot.size()==1 and g.used.has("G108"),"Insurance draws one for newly devastated place")
	g=fresh();put(g,"G087",0);put(g,"G112",0);put(g,"G052",1);give(g,"G043",0);g.current=1;apply(g,1,"attack",{"src":"G052","target":"G087","mode":"control"});apply(g,0,"wave",{"src":"G112","fee":"G043"});check(g.battle.bonus_d==3 and g.token("G112") and "G112" not in g.battle.paid,"Fans discard for defense without ordinary support participation")
	g=fresh();put(g,"G033",0);put(g,"G035",0);put(g,"G071",1);give(g,"P36",0);apply(g,0,"plot",{"id":"P36"});apply(g,0,"attack",{"src":"R0","target":"G071","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G033","algorithm":true});check(g.battle.algorithm_used,"Algorithm world order consumes one battle allowance");apply(g,1,"pass");check(action(g,0,"support",{"src":"G035","algorithm":true}).is_empty(),"Algorithm cannot convert a second media supporter")
	g=fresh();put(g,"G097",0);put(g,"G099",0);g.nodes.G097.devastated=true;g.nodes.G097.token=0;g.nodes.G099.devastated=true;g.nodes.G099.token=0;give(g,"P37",0);apply(g,0,"plot",{"id":"P37"});apply(g,0,"rebuild",{"src":"P37","target":"G097"});check(not g.wave.devastated("G097") and not g.token("G097") and g.token("R0"),"Resilience rebuilds huge place without granting action");check(action(g,0,"rebuild",{"src":"P37","target":"G099"}).is_empty(),"Resilience free allowance belongs to player and is once per own turn")
	g=fresh();put(g,"G035",0);put(g,"G081",1);put(g,"G028",1,"G081");give(g,"P38",0);apply(g,0,"plot",{"id":"P38","target":"G081","payer":"G035"});check(g.nodes.G081.silenced and not g.has("G028","计算机") and g.card("G081").p==5,"PR crisis disables printed ability, not printed numbers");g._complete_end();check(not g.nodes.G081.silenced and g.has("G028","计算机"),"PR crisis ends after end-of-turn cleanup")
	g=fresh();put(g,"G087",0);put(g,"G003",0);put(g,"G017",0,"G087");g.nodes.G017.token=0;put(g,"G011",1);give(g,"P39",0);apply(g,0,"plot",{"id":"P39","target":"G087"});apply(g,0,"attack",{"src":"G003","target":"G011","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G087"});finish(g);check(g.choice.get("kind","")=="w_recharge" and "P39" in g.nodes.G087.attached,"Brand waits until support's whole battle finishes");apply(g,0,"choose",{"id":"G017"});check(g.token("G017") and g.recharged.has("G017"),"Brand shares normal recovery limit")
	g=fresh();put(g,"G043",0);put(g,"G099",1);put(g,"G017",1,"G099");give(g,"P33",0);give(g,"P40",1);apply(g,0,"plot",{"id":"P33","payer":"G043","target":"G099"});apply(g,1,"plot",{"id":"P40","target":"G017","parent":"R1"});finish(g);check(g.nodes.has("G017") and g.nodes.G017.parent=="R1" and g.wave.devastated("G099"),"Emergency evacuation moves branch before tsunami returns remaining direct children")
	g=fresh();put(g,"G097",0);g.nodes.G097.devastated=true;g.nodes.G097.token=0;give(g,"G043",0);give(g,"P41",0);apply(g,0,"plot",{"id":"P41","target":"G097","fee":"G043"});check(not g.wave.devastated("G097") and not g.token("G097") and g.token("R0") and "G043" in g.discards.group,"Relief pays extra group only for huge and gives no marker")
	g=fresh();put(g,"G002",0);put(g,"G035",0);put(g,"G017",1);give(g,"P42",0);apply(g,0,"attack",{"src":"G002","target":"G017","mode":"control"});var old=g.battle_values();apply(g,1,"pass");apply(g,0,"plot",{"id":"P42","payer":"G035"});var changed=g.battle_values();check(old.alignment<0 and changed.alignment==-old.alignment and changed.loyalty==old.loyalty and changed.strength-old.strength==-2*old.alignment,"Reframing flips only total alignment modifier");check(not g.token("G035") and "G035" not in g.battle.paid,"Reframing fee does not confer combat plot eligibility")
	g=fresh();put(g,"G043",0);put(g,"G099",1);put(g,"G020",1,"G099");give(g,"P34",0);give(g,"P40",1);check(not g.wave.disaster_target("P34","G043") and g.wave.disaster_target("P34","G099"),"Nuclear accident requires place plus own/direct Science");apply(g,0,"plot",{"id":"P34","payer":"G043","target":"G099"});apply(g,1,"plot",{"id":"P40","target":"G020","parent":"R1"});finish(g);check(g.last_battle.success and g.destroyed[0]==1 and g.nodes.has("G020"),"Nuclear target legality fixed at launch, evacuation still saves branch")
	# All command generators and new state cleanup participate in actual AI matches.
	var commands=0
	for seed_value in range(1,5):
		g=GameState.new(seed_value);var bot=AiAgent.new();bot.rng.seed=seed_value
		for step in range(1000):
			if g.phase=="over":break
			var p=0 if not g.legal_actions(0).is_empty() else 1;var o=g.observation(p)
			if o.actions.is_empty():check(false,"Expansion deadlock "+g.phase);break
			var a=bot.pick(o)
			if not g.act(p,a):check(false,"Expansion AI command rejected");break
			commands+=1
			var errors=g.validate()
			if not errors.is_empty():check(false,"Expansion conservation seed%d step%d %s"%[seed_value,step,str(errors)]);break
	print("EXPANSION: %d checks, %d failures, %d simulated commands"%[checks,failures.size(),commands])
	var report={"checks":checks,"failures":failures,"simulated_commands":commands,"cards":CardDB.cards.size()};FileAccess.open("res://tests/expansion-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit(0 if failures.is_empty() else 1)
