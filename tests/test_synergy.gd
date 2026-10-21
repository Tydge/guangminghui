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
	check(CardDB.cards.size()==226,"All 226 cards")
	check(CardDB.get_card("G081").align==["企业"] and CardDB.get_card("G083").align==["企业","和平"],"User requested Musk and Altman alignments")
	check(CardDB.get_card("G113").p==2 and CardDB.get_card("G113").r==6 and CardDB.get_card("G113").align==["政府","和平"],"Preserved edited Moonbase")
	check(CardDB.get_card("G114").align==["和平"] and CardDB.get_card("G115").gp==1 and CardDB.get_card("G116").gp==0,"Preserved edited space and magic stats")
	var g=fresh();put(g,"G113",1);put(g,"G028",1,"G113");put(g,"G052",1);var b=context("R0","G052")
	var d=g.support_detail("G028",b);check(d.basis=="P" and d.reason=="远程中继","Moonbase defense P ignores alignment")
	g.nodes.G113.silenced=true;check(g.support_detail("G028",b).basis=="GP","Moonbase ability silence removes qualification");g.nodes.G113.silenced=false
	b.disaster="P31";check(g.support_detail("G028",b).basis=="GP","Moonbase doesn't override disaster support")
	g=fresh();put(g,"G115",0);put(g,"G104",0);put(g,"G099",1);g.synergy.add_tag("G104","太空");b=context("R0","G099");b.amplify=true
	d=g.support_detail("G104",b);check(d.power==g.stat("G104",d.basis.to_lower())*2+1,"Satellite fixed bonus added after Cloud Providers multiplier")
	g.nodes.G104.attached.append("P45");b=context("R0","G063");check(g.support_detail("G104",b).power==0,"Satellite never unlocks zero-GP support");g.nodes.G104.attached.clear()
	g=fresh();put(g,"G114",0);put(g,"G028",0,"G114");give(g,"G043",0);apply(g,0,"attack",{"src":"R0","target":"G043","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G028"});check(g.hands[0].plot.is_empty(),"Orbit draw waits until whole battle ends")
	finish(g);check(g.hands[0].plot.is_empty() and g.choice.get("source","")=="G114","Orbit draw waits for its cue");automatic(g);check(g.hands[0].plot.size()==1,"Orbit science support draw")
	g=fresh();put(g,"G116",0);give(g,"P01",1);check(action(g,0,"ability",{"src":"G116"}).is_empty(),"Templars can't see or discard hidden plots");g.exposed.append("P01");apply(g,0,"ability",{"src":"G116","target":"P01"});check("P01" in g.discards.plot and not g.token("G116"),"Templars discard exposed plot with action")
	g=fresh();put(g,"G117",0);put(g,"G116",0);give(g,"P24",0);apply(g,0,"plot",{"id":"P24","target":"G116"});check(g.hands[0].plot.size()==2,"Magic-cost draw reward has not applied before cue");automatic(g);check(g.hands[0].plot.size()==3,"Witches reward actual magic plot cost")
	g=fresh();put(g,"G117",0);put(g,"G116",0);give(g,"P24",0);give(g,"P15",1);apply(g,0,"plot",{"id":"P24","target":"G116"});apply(g,1,"counter");check(g.wave.queue.is_empty() and g.hands[0].plot.is_empty(),"Canceled magic-cost plot gives no Witches reward")
	g=fresh();put(g,"G118",1);put(g,"G002",0);put(g,"G001",1);apply(g,0,"attack",{"src":"G002","target":"G001","mode":"control"});var old=g.battle_values();apply(g,1,"synergy",{"src":"G118"});var changed=g.battle_values();check(changed.alignment==0 and changed.loyalty==old.loyalty and changed.strength==old.strength-old.alignment,"Illusion only zeros alignment modifier")
	check("G118" not in g.battle.paid and not g.token("G118"),"Illusion spends action but is not combat participation")
	g=fresh();put(g,"G119",0);put(g,"G120",0,"G119");put(g,"G121",0,"G119");put(g,"G094",0,"G119");check(g.stat("G119","p")==7 and g.stat("G119","gp")==1,"Industrial growth per direct Communist child, unchanged GP")
	g.synergy.add_tag("G094","共产");check(g.stat("G119","p")==7,"Industrial growth cap 2");g.nodes.G119.silenced=true;check(g.stat("G119","p")==5,"Industrial growth disabled with ability")
	g=fresh();put(g,"G120",0);put(g,"G094",0);g.nodes.G094.token=0;give(g,"G043",0);apply(g,0,"ability",{"src":"G120","target":"G094","fee":"G043"});check(g.token("G120") and g.token("G094") and g.recharged.has("G094"),"Cooperative discards group, restores another, keeps own action")
	g.nodes.G094.token=0;give(g,"G044",0);check(action(g,0,"ability",{"src":"G120"}).is_empty(),"Cooperative once-per-turn and recharge limit")
	g=fresh();put(g,"G121",0);put(g,"G119",0);give(g,"G043",0);apply(g,0,"attack",{"src":"G119","target":"G043","mode":"control"});finish(g);check(not g.has("G043","共产") and g.choice.get("source","")=="G121","Nationalization awaits cue");automatic(g);check(g.has("G043","共产") and not g.can_recharge("G043"),"Nationalization grants tag without entry action")
	g.nodes.G043.owner=1;g.nodes.G043.parent="R1";check(g.has("G043","共产"),"Granted Communist tag survives capture");g._return_subtree("G043");check(not g.has("G043","共产"),"Granted tag clears on leaving")
	g=fresh();put(g,"G122",0);put(g,"G005",0);put(g,"G043",1);apply(g,0,"attack",{"src":"G005","target":"G043","mode":"destroy"});finish(g);automatic(g);check(g.hands[0].plot.size()==1 and g.destroyed[0]==1,"Military contractor rewards true ordinary Military leader kill")
	g=fresh();put(g,"G123",1);put(g,"G125",1);d=g.support_detail("G123",context("R0","G125"));check(d.basis=="P" and d.reason=="维和护卫","Peacekeepers P for Place defense")
	put(g,"G052",1);d=g.support_detail("G123",context("R0","G052"));check(d.basis=="GP","Peacekeepers not full P for other unmatched target")
	g=fresh();put(g,"G124",0);give(g,"G043",0);g._discard(0,"G043");g._after_effect();check(g.hands[0].plot.is_empty(),"Recycling cue precedes reward");automatic(g);check(g.hands[0].plot.size()==1,"Recycling discarded group hand reward")
	g=fresh();put(g,"G124",0);give(g,"G043",0);g._discard(0,"G043","failed_recruit");g._after_effect();check(g.wave.queue.is_empty() and g.choice.is_empty(),"Recycling excludes failed recruit cleanup")
	g=fresh();put(g,"G125",0);put(g,"G043",0);put(g,"G099",1);give(g,"P31",0);apply(g,0,"plot",{"id":"P31","payer":"G043","target":"G099"});apply(g,1,"pass");apply(g,0,"synergy",{"src":"G125"});check(g.battle.bonus_a==3 and "G125" not in g.battle.paid,"Dino disaster bonus not ordinary participation")
	g=fresh();put(g,"G126",0);put(g,"G017",1);apply(g,0,"attack",{"src":"G126","target":"G017","mode":"control"});check(g.battle_values().no_self and action(g,1,"self_defend").is_empty() and g.token("G017"),"Union bans Corporate self-defense without removing target mark")
	g=fresh();put(g,"G127",0);put(g,"G017",0);attach(g,"P45","G017");apply(g,0,"ability",{"src":"G127","target":"G017","attachment":"P45"});check("P45" in g.discards.plot and not g.token("G127"),"Lawyer removes attached negative plot")
	g=fresh();put(g,"G127",0);put(g,"G047",1);attach(g,"P19","G047");put(g,"G043",1,"G047");put(g,"G044",1,"G047");put(g,"G045",1,"G047");check(not g.synergy.can_detach("G047","P19"),"Lawyer can't overflow printed slots")
	g=fresh();put(g,"G128",1);put(g,"G002",1);put(g,"G017",0);b=context("G017","G002");var v=g.battle_values(b);g.nodes.G128.silenced=true;check(v.strength==g.battle_values(b).strength-2,"Consumer watchdogs add contextual non-Corporate control defense")
	g=fresh();put(g,"G129",0);give(g,"G043",0);apply(g,0,"auto",{"id":"G043","parent":"R0"});automatic(g);check(g.hands[0].plot.size()==1 and not g.token("G043") and not g.can_recharge("G043"),"Credit union rewards weak recruit with entry lock retained")
	g=fresh();put(g,"G130",0);put(g,"G081",0);give(g,"G043",0);apply(g,0,"attack",{"src":"G081","target":"G043","mode":"control"});finish(g,false);check(g.hands[0].group==["G043"],"Failed recruit returns from committed battle zone");automatic(g);check(g.hands[0].group.size()==2,"Celebrity agency rewards failed completed attack")
	# Sniper and bodyguard retain all support, cost and ownership boundaries.
	g=fresh();put(g,"G005",0);put(g,"G081",1);give(g,"P43",0);apply(g,0,"attack",{"src":"G005","target":"G081","mode":"destroy"});apply(g,1,"pass");apply(g,0,"plot",{"id":"P43"});check(g.battle_values().position==0,"Sniper removes only position");check(not action(g,1,"self_defend").is_empty(),"Sniper doesn't prevent self defense")
	g=fresh();put(g,"G122",0);put(g,"G005",0);put(g,"G081",1);put(g,"G028",1,"G081");attach(g,"P44","G081");apply(g,0,"attack",{"src":"G005","target":"G081","mode":"destroy"});finish(g);check(g.choice.get("source","")=="P44" and "P44" in g.nodes.G081.attached and g.token("G081"),"Bodyguard pauses before state changes")
	automatic(g);check(g.nodes.has("G081") and g.nodes.has("G028") and not g.token("G081") and "P44" in g.discards.plot and g.destroyed[0]==0 and g.hands[0].plot.is_empty(),"Bodyguard keeps subtree, clears target action, no destruction rewards")
	g=fresh();put(g,"G043",0);put(g,"G081",1);put(g,"G063",1);g.nodes.G081.parent="G063";attach(g,"P44","G081");apply(g,0,"attack",{"src":"R0","target":"G081","mode":"destroy"});apply(g,1,"rescue");finish(g);check(g.last_battle.rescued and "G081" in g.hands[1].group and "P44" in g.discards.plot,"Red Cross rescue precedes bodyguard")
	g=fresh();put(g,"G002",0);put(g,"G025",1);give(g,"P45",0);apply(g,0,"plot",{"id":"P45","target":"G025","payer":"G002"});check(g.stat("G025","gp")==0 and g.stat("G025","p")==5,"Regulation zeroes GP only")
	g.current=1;g.nodes.G025.silenced=true;apply(g,1,"lift",{"src":"G025"});check(g.stat("G025","gp")==2 and "P45" in g.discards.plot and not g.token("G025"),"Target can lift regulation while own ability silenced")
	g=fresh();put(g,"G028",0);var printed_tags=g.card("G028").tags.duplicate();give(g,"P46",0);apply(g,0,"plot",{"id":"P46","target":"G028","tag":"计算机"});check(g.has("G028","计算机") and CardDB.get_card("G028").tags==printed_tags,"Technology grant doesn't mutate printed card")
	g=fresh();put(g,"G116",0);give(g,"P47",0);remove(g,"P48");g.discards.plot.append("P48");remove(g,"P15");g.discards.plot.append("P15");remove(g,"P31");g.discards.plot.append("P31");check(action(g,0,"plot",{"id":"P47","target":"P15"}).is_empty() and action(g,0,"plot",{"id":"P47","target":"P31"}).is_empty(),"Arcane recursion excludes counter and disaster")
	apply(g,0,"plot",{"id":"P47","target":"P48","payer":"G116"});check("P48" in g.hands[0].plot and "P48" not in g.locked and not g.token("G116"),"Arcane recovered battle plot usable immediately")
	g=fresh();put(g,"G119",0);put(g,"G002",1);give(g,"P48",0);apply(g,0,"attack",{"src":"R0","target":"G002","mode":"destroy"});apply(g,1,"pass");var before=g.support_detail("G119",g.battle).power;apply(g,0,"plot",{"id":"P48"});apply(g,1,"pass");var support=action(g,0,"support",{"src":"G119"});check(support.get("basis")=="P" and support.get("power")==g.stat("G119","p") and support.get("power")>before,"Mobilization enables future Communist P support")
	g=fresh();put(g,"G012",0);put(g,"G005",0);g.nodes.G005.token=0;give(g,"P49",0);apply(g,0,"plot",{"id":"P49","payer":"G012","target":"G005"});check(g.token("G005") and not g.token("G012") and g.hands[0].group.size()==1 and g.recharged.has("G005"),"Equipment financing pays Bank action and restores Military, draws group")
	g=fresh();put(g,"G043",0);put(g,"G099",1);give(g,"P31",0);give(g,"P50",0);give(g,"P35",0);apply(g,0,"plot",{"id":"P31","payer":"G043","target":"G099"});apply(g,1,"pass");apply(g,0,"plot",{"id":"P50","fee":"P35"});check(g.battle.bonus_a==6 and "P35" in g.discards.plot and not g.wave.devastated("G099"),"Cascading fee disaster gives 6, never runs sacrificed disaster")
	# A committed recruit cannot be recycled, discarded for tolls or put on deck bottom.
	g=fresh();put(g,"G091",0);put(g,"G028",0);give(g,"G102",0);apply(g,0,"attack",{"src":"R0","target":"G102","mode":"control"});apply(g,1,"pass");apply(g,0,"support",{"src":"G028"});check("G102" not in g.hands[0].group and g.phase=="battle","Committed recruit can't pay a support cost");finish(g);check(g.validate().is_empty(),"Successful recruit cannot also be in deck")
	# Pure AI view uses effective public stats, never opponent hidden cards.
	g=fresh();put(g,"G127",0);put(g,"G025",0);attach(g,"P45","G025");give(g,"P44",1);var o=g.observation(0);var bot=AiAgent.new();check(o.effective.G025.gp==0 and not o.hands.plot.has("P44") and not o.effective.has("P44"),"AI sees current public stats without hidden hands")
	check(bot.pick(o).type in ["ability","lift"],"AI recognizes useful regulatory removal")
	var commands=0;var completed=0
	for seed_value in range(21,27):
		g=GameState.new(seed_value);bot=AiAgent.new();bot.rng.seed=seed_value
		for step in 1200:
			if g.phase=="over":completed+=1;break
			var p=0 if not g.legal_actions(0).is_empty() else 1;o=g.observation(p)
			if o.actions.is_empty():check(false,"Synergy AI deadlock "+g.phase);break
			if not g.act(p,bot.pick(o)):check(false,"Synergy AI illegal action");break
			commands+=1
			if not g.validate().is_empty():check(false,"Synergy AI conservation seed%d step%d %s"%[seed_value,step,str(g.validate())]);break
	check(completed==6,"All six mixed-deck AI games complete")
	var report={"checks":checks,"failures":failures,"simulated_commands":commands,"completed_matches":completed,"cards":CardDB.cards.size()};FileAccess.open("res://tests/synergy-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("SYNERGY: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
