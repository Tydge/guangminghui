extends SceneTree
var checks=0
var failures=[]
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func fresh(faction="I01") -> GameState:
	var g=GameState.new(761);g.nodes={};g.factions=[faction,"I01"];g.current=0;g.turns=[2,2];g.phase="main"
	for kind in g.decks:
		g.decks[kind]=CardDB.ids(kind);g.discards[kind]=[]
		for p in [0,1]:g.hands[p][kind]=[]
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	return g
func put(g: GameState,id: String,p=0,parent=""):
	g.decks[g.card(id).kind].erase(id)
	if id.begins_with("E"):g.nodes[id]={"card":id,"owner":p,"parent":"","token":int(g.card(id).action),"attached":[],"resource_slot":g.resources.field(p).size()}
	else:
		if parent=="":
			for candidate in g.field(p):
				if g.can_parent(candidate):parent=candidate;break
		g._enter(id,p,parent,1)
func give(g: GameState,id: String,p=0):g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,type: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==type and args.keys().all(func(k):return a.get(k,false if args[k] is bool else null)==args[k]):return a
	return {}
func apply(g: GameState,p: int,type: String,args: Dictionary={}):
	var a=action(g,p,type,args);check(not a.is_empty(),"Legal "+type+str(args))
	if not a.is_empty():check(g.act(p,a),"Apply "+type)
	check(g.validate().is_empty(),"Card conservation: "+str(g.validate()))
func drain(g: GameState):
	for i in 20:
		if g.phase!="choice" or g.choice.kind!="w_auto":return
		apply(g,g.choice.player,"trigger")
func finish(g: GameState):g.battle.bonus_a=100;g.battle.fixed_dice=[1,1];g._resolve_battle()
func run():
	check(CardDB.ids("faction").size()==12 and CardDB.ids("group").size()==170 and CardDB.ids("plot").size()==70 and CardDB.ids("resource").size()==23,"12/170/70/23 composition")
	# Independent quotas, including alternative payments and an exhausted root.
	var g=fresh();put(g,"G098");give(g,"G043");give(g,"G044");give(g,"E01");apply(g,0,"deploy",{"id":"E01","supply":true,"fee":"G044"});check(g.deploy_used and not g.auto_used and g.token("R0"),"Australia consumes deployment only");apply(g,0,"auto",{"id":"G043","parent":"R0"});check(g.auto_used and action(g,0,"deploy").is_empty(),"Each quota is consumed once")
	g=fresh();put(g,"G098");give(g,"G043");give(g,"G044");give(g,"E01");apply(g,0,"auto",{"id":"G043","parent":"R0"});apply(g,0,"deploy",{"id":"E01","supply":true});check(not g.token("R0") and g.deploy_used,"Australia deploys after takeover without a root action")
	# Smuggling pays before revealing legal relic choices and never reveals deck order.
	g=fresh();put(g,"G138");give(g,"P10");g.decks.resource.erase("E19");g.decks.resource.push_front("E19")
	var before=JSON.stringify(g.observation(0));check(not before.contains('"E19"'),"Unpaid smuggling does not expose peek identities")
	var rng_before=g.rng.state;var command=action(g,0,"ability",{"src":"G138","target":"P10"});var plan=ActionFlow.plan(g,0,command)
	check(g.rng.state==rng_before and "P10" in g.hands[0].plot and g.token("G138"),"Smuggling preview leaves live costs and RNG untouched");check(not plan.moves.is_empty(),"Smuggling previews its Plot payment and Resource peek")
	apply(g,0,"ability",{"src":"G138","target":"P10"});check(g.choice.kind=="n_relic" and g.choice.peek.size()==3 and "P10" in g.discards.plot and not g.token("G138"),"Smuggling peeks three only after paying its action and Plot")
	check(g.choice.options.all(func(k):return g.has(k,"秘宝")),"Only peeked relics may be taken");apply(g,0,"choose",{"id":"E19"});check("E19" in g.hands[0].resource and action(g,0,"ability",{"src":"G138"}).is_empty(),"Smuggler takes one peeked relic once per turn")
	g=fresh();put(g,"G138");give(g,"P10");g.discards.resource=g.decks.resource.duplicate();g.decks.resource=[];apply(g,0,"ability",{"src":"G138","target":"P10"});check(g.choice.peek.size()==3 and g.discards.resource.is_empty(),"Smuggling refills an exhausted Resource deck before looking");apply(g,0,"choose",{"id":""})
	g=fresh();put(g,"G138");give(g,"P10");apply(g,0,"ability",{"src":"G138","target":"P10"});check(g.choice.options.is_empty() and g.choice.peek.size()==3,"Top three can have no relic even when deeper relics exist");apply(g,0,"choose",{"id":""});check(g.phase=="main" and g.hands[0].resource.is_empty() and "P10" in g.discards.plot and not g.token("G138"),"Empty peek or skipping never refunds payment")
	# Druid aura, World Orders, and direct auras remain distinct from personal effects.
	g=fresh();put(g,"G049");put(g,"G062");put(g,"G005",1);check(g.attack_preview("G005","G062","destroy").defense==3 and g.wave.disaster_preview({"id":"P31","payer":"G005","target":"G062"}).defense==3,"Druids protect allied Green destruction and disasters");g.nodes.G049.silenced=true;check(g.attack_preview("G005","G062","destroy").defense==0,"Disabled Druid aura ends")
	g=fresh();put(g,"G155");put(g,"G170");put(g,"G055",0,"G170");check(g.stat("G055","r")==6,"Temple grants R to direct Magic child");give(g,"P62");apply(g,0,"plot",{"id":"P62"});check(g.stat("G170","r")==6 and g.stat("G155","gp")==1,"Traditional World Order changes conservative R and GP");apply(g,0,"ability",{"src":"G155","target":"G170"});check(g.has("G170","狂热"),"Rally temporarily adds Fanatic");g._complete_end();check(not g.has("G170","狂热"),"Rally expires at turn end")
	# New economy abilities, with staged costs and hand limits.
	g=fresh();put(g,"G151");give(g,"E01");apply(g,0,"ability",{"src":"G151","target":"E01"});check(g.hands[0].resource.size()==1 and g.hands[0].plot.size()==1,"Harbour cycles cargo and draws a Plot")
	g=fresh();put(g,"G156");put(g,"G043",0,"G156");check(g.hand_limit(0)==6,"Barbershop adds Plot capacity only with a direct child");g.nodes.G043.parent="R0";check(g.hand_limit(0)==5,"Barbershop loses capacity when empty")
	g=fresh();put(g,"G157");var plot_order=g.decks.plot.duplicate();apply(g,0,"ability",{"src":"G157"});check(g.choice.peek==plot_order.slice(0,3),"Tarot secretly views three Plots");apply(g,0,"choose",{"id":""});check(g.decks.plot==plot_order and g.hands[0].plot.is_empty(),"Tarot restores the exact original order without taking a card")
	g=fresh();put(g,"G159");put(g,"G001");g.nodes.G001.token=0;put(g,"E01");apply(g,0,"ability",{"src":"G159","target":"G001","other":"E01"});check("E01" in g.scrap and g.token("G001") and g.recharged.has("G001"),"Arms deal scraps a Device and restores Military once")
	g=fresh();put(g,"G162");give(g,"E01");g._discard(0,"E01");give(g,"G043");apply(g,0,"ability",{"src":"G162","target":"E01","fee":"G043"});check("E01" in g.hands[0].resource and "G043" in g.discards.group,"Repair Workshop recovers a discarded Device for a Group")
	g=fresh();put(g,"G164");put(g,"G043");g.nodes.G043.silenced=true;apply(g,0,"ability",{"src":"G164","target":"G043"});check(not g.nodes.G043.silenced,"Crystal circle clears disabled ability state")
	g=fresh();put(g,"G168");give(g,"E01");apply(g,0,"ability",{"src":"G168","target":"E01"});check(g.hands[0].group.size()==1 and g.hands[0].plot.size()==1 and "E01" in g.discards.resource,"Marketplace trades a Resource hand card for two kinds of card")
	# Support restrictions and bonuses respect their actual source and paid participant.
	g=fresh();put(g,"G153");put(g,"G119",0,"G153");put(g,"G055");put(g,"G024",1);g._launch_attack(0,{"src":"G055","target":"G024","mode":"destroy"});check(g.support_detail("G119",g.battle).basis=="P","Xi grants direct Communist child full support")
	g=fresh();put(g,"G001");put(g,"G154");put(g,"G005",1);g.current=1;apply(g,1,"attack",{"src":"G005","target":"G001","mode":"control"});check(g.battle_values().alignment==8,"Fixture has two shared alignments");apply(g,0,"support",{"src":"G154"});check(g.battle_values().alignment==4,"Khaby caps attack alignment bonus after defensive support")
	g=fresh();put(g,"G158");put(g,"G119",0,"G158");put(g,"G005",1);g.current=1;apply(g,1,"attack",{"src":"G005","target":"G119","mode":"destroy"});apply(g,0,"self_defend",{"src":"G119"});check(g.battle.self==2*g.stat("G119","p")+3,"Kitchen adds self-defense for direct Communist child")
	g=fresh();put(g,"G161");put(g,"G055");put(g,"G075",1);give(g,"P10");g._launch_attack(0,{"src":"G055","target":"G075","mode":"control"});apply(g,1,"pass");var staked=action(g,0,"support",{"src":"G161","stake":true});var expected=staked.get("power",0);apply(g,0,"support",{"src":"G161","stake":true});check("P10" in g.discards.plot and g.battle.support_a==expected,"Casino discards its Plot before adding two")
	g=fresh();put(g,"G163");put(g,"G075");g.nodes.G075.extra_tags=["绿色"];put(g,"G003",1);put(g,"G002",1);put(g,"G007",1);g.current=1;apply(g,1,"attack",{"src":"G003","target":"G075","mode":"control"});check(g.support_detail("G002",g.battle).basis=="GP","Farmers force first attacker support to GP");apply(g,0,"pass");apply(g,1,"support",{"src":"G002"});check(g.support_detail("G007",g.battle).basis=="P","Later attacker support regains usual eligibility")
	g=fresh();put(g,"G169",0,"R0");put(g,"G043",0,"G169");put(g,"G005",1);var b={"src":"G005","target":"G169","attacker":1,"defender":0,"mode":"control"};check(g.support_power("G043",b)==g.stat("G043","p"),"Bonus belongs to Shared Apartment, not all its children");g.nodes.G043.parent="R0";g.nodes.G169.parent="G043";b.target="G043";check(g.support_power("G169",b)==g.stat("G169","p")+3,"Apartment adds three only when defending its parent")
	# Deployment and post-entry benefits wait in the existing trigger queue.
	g=fresh();put(g,"G165");give(g,"E01");apply(g,0,"deploy",{"id":"E01"});check(g.phase=="choice" and g.choice.source=="G165" and g.hands[0].group.is_empty(),"Open Hardware draws only through a queued source reveal");drain(g);check(g.hands[0].group.size()==1,"Open Hardware draws after its trigger")
	g=fresh();put(g,"E20");give(g,"G062");apply(g,0,"auto",{"id":"G062","parent":"R0"});check(g.hands[0].group.is_empty() and g.choice.source=="E20","Community Solar queues its Group draw");drain(g);check(g.hands[0].group.size()==1,"Community Solar receives a Group after reveal")
	g=fresh();put(g,"E16");check(g.resource_hand_limit(0)==3,"Warehouse increases Resource capacity");give(g,"P63");apply(g,0,"plot",{"id":"P63"});check(g.resource_hand_limit(0)==4,"Circular Economy stacks capacity");give(g,"E17");apply(g,0,"deploy",{"id":"E17"});drain(g);check(g.hands[0].resource.size()==1,"Circular Economy draws after first Facility deployment")
	# Medical station, sword, and resource-targeting Plots.
	g=fresh();put(g,"E17");put(g,"G075");g.nodes.G075.devastated=true;apply(g,0,"resource",{"src":"E17","target":"G075"});check(not g.wave.devastated("G075") and not g.token("E17"),"Medical Station rebuilds non-Huge Place")
	g=fresh();put(g,"G055");put(g,"G043",1);put(g,"E19");g._launch_attack(0,{"src":"G055","target":"G043","mode":"control"});apply(g,1,"pass");apply(g,0,"resource",{"src":"E19"});check(g.battle.bonus_a==5 and "E19" in g.scrap,"Peachwood sword gives five and is scrapped")
	g=fresh();put(g,"E01");give(g,"P65");apply(g,0,"plot",{"id":"P65","target":"E01"});check("E01" in g.scrap and g.choice.peek.size()==3,"Trade-in pays before Resource selection");apply(g,0,"choose",{"id":g.choice.options[0]});check(g.hands[0].resource.size()==1,"Trade-in selects one Resource")
	g=fresh();put(g,"G043");give(g,"P66");give(g,"E01");g.nodes.R0.token=0;apply(g,0,"plot",{"id":"P66","target":"E01","payer":"G043"});check(g.nodes.has("E01") and not g.token("G043") and g.deploy_used and not g.auto_used,"Airlift spends a non-root Group action and uses deployment quota")
	g=fresh();put(g,"G055");put(g,"G003",1);put(g,"G043",1);give(g,"P67");apply(g,0,"plot",{"id":"P67","target":"G003","payer":"G055"});var context={"src":"R0","target":"G043","mode":"control","attacker":0,"defender":1};check(g.support_power("G003",context)==0,"Talisman Seal blocks support");g._complete_end();check(not g.nodes.G003.get("no_support",false),"Support seal expires")
	g=fresh();put(g,"G094");g.nodes.G094.devastated=true;give(g,"P68");apply(g,0,"plot",{"id":"P68","target":"G094"});check(not g.wave.devastated("G094") and g.nodes.G094.prepared,"Ecological Restoration rebuilds and prepares Green Place")
	g=fresh();give(g,"P70");give(g,"P13",1);g.exposed.append("P13");apply(g,0,"plot",{"id":"P70","target":"P13"});check(g.hands[1].plot.is_empty() and g.decks.plot.front()=="P13" and "P13" not in g.exposed,"Inside Job returns the exposed Plot to the top without replacement")
	# Four new factions: dual action, support, free self-defense, and supply recovery.
	g=fresh("I09");g._begin_draw({"group":false,"plot":false});check(g.nodes.R0.token==2,"UFO refills to two root actions");give(g,"G043");apply(g,0,"research",{"deck":"plot"});check(g.nodes.R0.token==1,"Extra draw spends only one UFO action");apply(g,0,"auto",{"id":"G043","parent":"R0"});check(g.nodes.R0.token==0,"UFO can then take over with its second action")
	g=fresh("I10");put(g,"G055");put(g,"G052");put(g,"G024",1);g._launch_attack(0,{"src":"G055","target":"G024","mode":"destroy"});check(g.support_detail("G052",g.battle).basis=="P","Assassins use Violent P for destruction support")
	g=fresh("I11");put(g,"G062");put(g,"G005",1);g.current=1;apply(g,1,"attack",{"src":"G005","target":"G062","mode":"destroy"});apply(g,0,"self_defend",{"src":"G062","nature":true});check(g.token("G062") and "G062" not in g.battle.paid and action(g,0,"self_defend").is_empty(),"Gaia retains the token, excludes paid eligibility, and cannot defend twice")
	g=fresh("I12");put(g,"G119");g.nodes.G119.token=0;give(g,"E01");check(g.resource_hand_limit(0)==3,"Red Council stores one extra Resource");apply(g,0,"deploy",{"id":"E01"});drain(g);check(g.choice.kind=="n_recharge" and not g.token("G119"),"Council recovery waits for target selection");apply(g,0,"choose",{"id":"G119"});check(g.token("G119") and g.recharged.has("G119"),"Council restores a Communist group once")
	# Relics use distinct continuous, action, and one-shot paths.
	g=fresh();put(g,"G055");put(g,"E21");put(g,"G005",1);check(g.attack_preview("G005","G055","control").defense==2,"Solomon adds only ordinary Control defense");check(g.attack_preview("G005","G055","destroy").defense==0,"Solomon does not alter Destroy defense")
	g=fresh();put(g,"E22");give(g,"E01");apply(g,0,"resource",{"src":"E22","target":"E01"});check(not g.token("E22") and g.hands[0].plot.size()==2 and g.hands[0].resource.is_empty(),"Stone spends its own action and exchanges one Resource for two Plots")
	g=fresh();put(g,"G055");put(g,"G003",1);put(g,"G001",1,"G003");put(g,"E23");g._launch_attack(0,{"src":"G055","target":"G001","mode":"control"});apply(g,1,"pass");var old=g.battle_values();apply(g,0,"resource",{"src":"E23"});check(g.battle_values().loyalty==0 and g.battle_values().strength==old.strength+old.loyalty and "E23" in g.scrap,"Scepter scraps itself and removes exactly loyalty defense")
	# A positive support bonus may enable GP 0, but never bypass a prohibition.
	g=fresh();put(g,"G161");put(g,"G055");put(g,"G075",1);give(g,"P10");g._launch_attack(0,{"src":"G055","target":"G075","mode":"control"});apply(g,1,"pass");check(g.support_power("G161",g.battle)==0 and not action(g,0,"support",{"src":"G161","stake":true}).is_empty(),"Casino offers its paid support even with GP 0");apply(g,0,"support",{"src":"G161","stake":true});check("P10" in g.discards.plot and g.battle.support_a==2,"Casino pays a Plot for two support")
	g=fresh();put(g,"G161");put(g,"G055");put(g,"G075",1);put(g,"E18");g._launch_attack(0,{"src":"G055","target":"G075","mode":"control"});check(g.support_power("G161",g.battle)==1,"Cold Wallet enables Criminal GP 0 support");g.nodes.G161.no_support=true;check(g.support_power("G161",g.battle)==0,"Seal prohibition overrides the Wallet bonus");g.nodes.G161.no_support=false;g.battle.solo=true;check(g.support_power("G161",g.battle)==0,"Solo attack forbids support including fixed bonuses")
	g=fresh();put(g,"G152");put(g,"E01");put(g,"G005",1);var disaster={"id":"P31","payer":"G005","target":"G152"};var protected=g.wave.disaster_preview(disaster);g.resources.remove("E01");check(protected.strength==g.wave.disaster_preview(disaster).strength,"Israel ordinary destruction shield does not apply to disasters")
	g=fresh();put(g,"G166");put(g,"G043",1);check(g.attack_preview("G166","G043","destroy").position==7,"Drone racers remove three position defense");check(g.attack_preview("G166","G043","control").position==10,"Drone racers do not affect Control position")
	g=fresh();put(g,"G167");give(g,"G024");g._launch_attack(0,{"src":"G167","target":"G024","mode":"control"});finish(g);check(not g.token("G167") and g.choice.source=="G167","Recruitment restoration is deferred until after entry");drain(g);check(g.token("G167") and g.recharged.has("G167"),"Recruitment restores its leader once")
	g=fresh();put(g,"G160");put(g,"G026",1);give(g,"E01",1);g._launch_attack(0,{"src":"G160","target":"G026","mode":"control"});finish(g);check("E01" in g.hands[1].resource,"Ransomware does not discard during control movement");drain(g);check(g.choice.kind=="n_discard" and g.choice.player==1,"Ransomware lets the affected player choose Resource payment");apply(g,1,"choose",{"id":"E01"});check("E01" in g.discards.resource,"Ransomware discards after its trigger")
	g=fresh();put(g,"G136");put(g,"G138");give(g,"G043");apply(g,0,"ability",{"src":"G138","target":"G043"});check(g.used.has(g.renewal.quota("G136")) and "G043" in g.discards.group,"Common Supply may pay Smuggling's Plot fee")
	g=fresh();put(g,"G005");put(g,"G094",1);give(g,"P64");apply(g,0,"plot",{"id":"P64","payer":"G005","target":"G094"});check(g.battle.has("disaster") and g.battle_values().power+g.battle_values().ability==19,"Wildfire receives its Green Place bonus");finish(g);check(g.nodes.has("G094") and g.wave.devastated("G094"),"Wildfire devastates rather than destroys")
	g=fresh();put(g,"G034");put(g,"G055");put(g,"G024",1);give(g,"P69",1);g._launch_attack(0,{"src":"G055","target":"G024","mode":"control"});g.battle.paid.append("G034");var backlash=action(g,1,"plot",{"id":"P69"});check(backlash.get("backlash",0)==2,"Viral Backlash counts only paid Media");apply(g,1,"plot",{"id":"P69"});check(g.battle.bonus_a==-2,"Viral Backlash reduces the opponent's attack")
	# New goal is active, counterable, and evaluated by the shared goal engine.
	for faction in ["I09","I10","I11","I12"]:
		g=fresh(faction);var rule=CovenantRules.FACTIONS[faction];var candidates=CardDB.ids("group").filter(func(k):return rule.traits.any(func(t):return t in CardDB.get_card(k).align+CardDB.get_card(k).tags))
		for id in candidates.slice(0,rule.groups):put(g,id);g.nodes[id].learned=10
		check(g.goal(0).met,"New faction criterion met "+faction);g.nodes[candidates[0]].devastated=true;check(not g.goal(0).met,"Devastated member cannot satisfy faction count "+faction)
	g=fresh("I10");put(g,"G005");put(g,"G043",1);g._launch_attack(0,{"src":"G005","target":"G043","mode":"destroy"});finish(g);check(g.hands[0].plot.is_empty() and g.wave.queue.is_empty(),"Assassins no longer reward destruction with a Plot");drain(g);check(g.hands[0].plot.is_empty(),"No delayed Assassin draw remains");put(g,"G044",1);g._launch_attack(0,{"src":"R0","target":"G044","mode":"destroy"});finish(g);drain(g);check(g.hands[0].plot.is_empty(),"Later destruction also gives no Assassin draw")
	g=fresh();for id in ["G049","G062","G094","G158","G163"]:put(g,id)
	put(g,"E16");put(g,"E20");give(g,"P61");check(g.covenant.progress(0,"P61").met,"Green Future counts Green groups and Facility resources");apply(g,0,"plot",{"id":"P61"});check(g.phase=="over" and g.winner==0,"Green Future wins only when played")
	var report={"checks":checks,"failures":failures};FileAccess.open("res://tests/contemporary-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("CONTEMPORARY: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
