extends "res://tests/test_contemporary.gd"

func snapshot(g: GameState) -> String:return JSON.stringify([g.nodes,g.decks,g.discards,g.hands,g.rng.state,g.used,g.choice])
func run():
	var g=fresh("I09");g.decks.group.erase("G029");g.decks.group.push_front("G029");var deck=g.decks.group.duplicate();var before=snapshot(g)
	var cmd=action(g,0,"ability",{"src":"R0"});var plan=ActionFlow.plan(g,0,cmd)
	check(not cmd.is_empty() and snapshot(g)==before,"Contact rehearsal cannot alter real hand/deck/RNG/action")
	check(plan.moves.size()==5 and plan.moves.all(func(e):return e.from=="deck" and e.to=="choice"),"Contact previews five private draw flights")
	apply(g,0,"ability",{"src":"R0"})
	check(g.choice.peek==deck.slice(0,5) and g.hands[0].group.is_empty() and not g.token("R0"),"Contact pays one action before privately viewing the top five")
	check(g.observation(1,false).choice.is_empty() and g.choice.options.all(func(k):return g.has(k,"太空")),"Only the owner sees contact; only Space may be taken")
	var peeked=g.choice.peek.duplicate();var selected=g.choice.options[0]
	before=snapshot(g);plan=ActionFlow.plan(g,0,action(g,0,"choose",{"id":selected}));check(snapshot(g)==before and plan.moves.filter(func(e):return e.to=="deck").size()==4,"Unselected cards fly back before the live deck is shuffled")
	apply(g,0,"choose",{"id":selected})
	check(g.hands[0].group==[selected] and peeked.filter(func(k):return k!=selected).all(func(k):return k in g.decks.group),"Take exactly one Space Group, shuffle every other inspected card back")
	g.nodes.R0.token=1;check(action(g,0,"ability",{"src":"R0"}).is_empty(),"Recovering the root does not bypass contact's per-turn quota")
	g=fresh("I09");g.discards.group=g.decks.group.duplicate();g.decks.group=[]
	apply(g,0,"ability",{"src":"R0"});apply(g,0,"choose",{"id":""});check(g.hands[0].group.is_empty() and g.decks.group.size()==170,"Contact uses the normal reshuffle rule and allows declining")
	g=fresh("I09");g.graves[0]=g.decks.group.slice(2);g.decks.group=g.decks.group.slice(0,2)
	apply(g,0,"ability",{"src":"R0"});check(g.choice.peek.size()==2 and g.choice.options.is_empty(),"Short deck/no Space still offers a private view")
	apply(g,0,"choose",{"id":""});check(g.decks.group.size()==2 and not g.token("R0"),"Declining never refunds action")
	g=fresh("I07");check(g.stat("R0","p")==6,"Shangri-La's latest printed P is six")
	for faction in ["I09","I10"]:
		g=fresh(faction);var required_trait="太空" if faction=="I09" else "暴力"
		for id in CardDB.ids("group").filter(func(k):return required_trait in g.card(k).tags+g.card(k).align).slice(0,5):put(g,id);g.nodes[id].learned=10
		check(not g.goal(0).met,"Five Groups cannot satisfy the latest six-Group goal "+faction)
		var sixth=CardDB.ids("group").filter(func(k):return required_trait in g.card(k).tags+g.card(k).align and not g.nodes.has(k))[0];put(g,sixth);g.nodes[sixth].learned=10
		check(g.goal(0).met,"Six eligible Groups with enough P meet goal "+faction)
	# GP aura is not an extra P-support bonus and respects current, direct relations.
	g=fresh();put(g,"G050");put(g,"G043",0,"G050");put(g,"G041",0,"G050");put(g,"G023");put(g,"G005",1)
	check(g.stat("G050","gp")==2,"Two direct Weird children add two GP")
	var b={"src":"G023","target":"G005","mode":"control","attacker":0,"defender":1}
	check(g.support_detail("G050",b).basis=="GP" and g.support_power("G050",b)==2,"Remote choir support uses its boosted GP")
	b.src="G043";check(g.support_power("G050",b)==2,"Shared alignment/parent P support gets no extra choir bonus")
	g.nodes.G050.silenced=true;check(g.stat("G050","gp")==0,"Silence disables choir GP")
	g.nodes.G050.silenced=false;g.nodes.G041.parent="G023";check(g.stat("G050","gp")==1,"Moving a child immediately reduces GP")
	check(ActionFlow.copy_state(g).stat("G050","gp")==1,"Rehearsal rebinds the dynamic GP aura")
	g.decks.plot.erase("P45");g.nodes.G050.attached.append("P45");check(g.stat("G050","gp")==0,"Regulatory Inquiry overrides choir GP bonuses")
	g=fresh();put(g,"G057");give(g,"G001");give(g,"G043")
	check(g.attack_preview("G057","G001","control").ability==3 and g.attack_preview("G057","G043","control").ability==1,"Gun Lobby only gets its new control bonus against Violent targets")
	g.nodes.G057.silenced=true;check(g.attack_preview("G057","G001","control").ability==1,"Disabled Lobby bonus ends")
	g=fresh();put(g,"G170");put(g,"G055",0,"G170");check(g.stat("G055","r")==g.card("G055").r+2,"Temple gives direct Magic children two R")
	# PR Crisis forces final GP to zero, even with P=GP effects or external buffs.
	g=fresh();put(g,"G032");put(g,"G082",1);g.nodes.G082.compute=true;g.nodes.G082.ad_gp=3;give(g,"P38")
	apply(g,0,"plot",{"id":"P38","target":"G082"})
	check(g.stat("G082","gp")==0 and g.nodes.G082.silenced,"PR Crisis zeros GP after all other modifiers")
	g.nodes.G082.silenced=false;check(g.stat("G082","gp")==0,"Removing ability silence does not remove the separate GP penalty")
	g._complete_end();check(g.stat("G082","gp")==g.card("G082").gp,"PR Crisis expires at turn end")
	g=fresh();put(g,"G082");g.nodes.G082.silenced=true;check(g.stat("G082","gp")==g.card("G082").gp,"Other silence effects do not zero GP")
	# Random private peek happens after counterplay; later placement is deterministic.
	for position in ["top","bottom"]:
		g=fresh();give(g,"P70");give(g,"P13",1);give(g,"P17",1);before=snapshot(g);cmd=action(g,0,"plot",{"id":"P70"})
		ActionFlow.plan(g,0,cmd);check(snapshot(g)==before,"Inside Job rehearsal preserves RNG before reveal")
		apply(g,0,"plot",{"id":"P70"});selected=g.choice.revealed_card;deck=g.decks.plot.duplicate();var rng_before=g.rng.state
		check(g.choice.kind=="n_inside" and selected in g.hands[1].plot and g.observation(1,false).choice.is_empty() and selected not in g.exposed,"Random card stays in hand pending owner's private placement decision")
		cmd=action(g,0,"choose",{"id":position});plan=ActionFlow.plan(g,0,cmd)
		check(plan.moves.any(func(e):return e.id==selected and e.from=="hand" and e.to=="deck") and g.hands[1].plot.size()==2,"Placement rehearses hand-to-deck without prematurely changing the live hand")
		apply(g,0,"choose",{"id":position})
		check(g.decks.plot==([selected]+deck if position=="top" else deck+[selected]) and g.rng.state==rng_before and g.hands[1].plot.size()==1,"Inside Job honors chosen position without shuffle or replacement")
	g=fresh();give(g,"P70");give(g,"P15",1);give(g,"P13",1);before=str(g.rng.state);apply(g,0,"plot",{"id":"P70"});check(g.phase=="plot_response","Inside Job waits for reaction before random reveal");apply(g,1,"counter")
	check(str(g.rng.state)==before and g.hands[1].plot==["P13"] and g.choice.is_empty(),"Countered Inside Job neither peeks nor moves a hidden card")
	# Battery P boost is temporary, not an extra recovery loophole.
	g=fresh();put(g,"E02");put(g,"G043");g.nodes.G043.token=0;var power=g.stat("G043","p");apply(g,0,"resource",{"src":"E02","target":"G043"})
	check(g.stat("G043","p")==power+2 and g.token("G043") and not g.can_recharge("G043"),"Battery restores action and grants temporary Power")
	g._complete_end();check(g.stat("G043","p")==power,"Battery P expires at end of turn")
	# Decoy reduces accumulated support by exactly six, on either side.
	for side in [0,1]:
		g=fresh();put(g,"G043");put(g,"G023",1);put(g,"E12",side);g._launch_attack(0,{"src":"G043","target":"G023","mode":"destroy"});g.battle.responder=side
		var opposing="support_d" if side==0 else "support_a";g.battle[opposing]=10
		apply(g,side,"resource",{"src":"E12"});check(g.battle[opposing]==4,"Decoy subtracts six from the opposing support total")
	# Quantum keep choice never includes the old hand. Both moves are rehearsed.
	g=fresh();put(g,"E06");give(g,"G170");deck=g.decks.group.slice(0,2);apply(g,0,"resource",{"src":"E06"})
	check(g.choice.options==deck and g.hands[0].group==["G170"]+deck and g.observation(1,false).choice.is_empty(),"Quantum offers only its two new private cards")
	selected=deck[0];cmd=action(g,0,"choose",{"id":selected});plan=ActionFlow.plan(g,0,cmd)
	check(plan.moves.size()==1 and plan.moves[0].to=="discard" and g.hands[0].group==["G170"]+deck,"Discard flight precedes live card movement")
	apply(g,0,"choose",{"id":selected});check(g.hands[0].group==["G170",selected] and deck[1] in g.discards.group,"Old hand retained; only the unchosen new card is discarded")
	g=fresh();put(g,"E06");put(g,"G124");apply(g,0,"resource",{"src":"E06"});apply(g,0,"choose",{"id":g.choice.options[0]});check(g.choice.get("source","")=="G124" and g.hands[0].plot.is_empty(),"Quantum's discarded new hand card queues normal recycling rewards");drain(g);check(g.hands[0].plot.size()==1,"Quantum integrates with the existing discard trigger")
	g=fresh();put(g,"E06");g.graves[0]=g.decks.group.slice(1);g.decks.group=g.decks.group.slice(0,1);apply(g,0,"resource",{"src":"E06"});apply(g,0,"choose",{"id":g.choice.options[0]});check(g.hands[0].group.size()==1 and g.discards.group.is_empty(),"A one-card deck keeps its only card without demanding an unrelated discard")
	# Museum triggers for ordinary Devices, once, after scrap; not for itself.
	g=fresh();put(g,"E13");put(g,"E02");put(g,"G043");g.nodes.G043.token=0;apply(g,0,"resource",{"src":"E02","target":"G043"})
	check(g.hands[0].plot.is_empty() and g.choice.get("source","")=="E13","Non-Relic scrap queues Museum reward after source motion")
	drain(g);check(g.hands[0].plot.size()==2,"Museum draws two Plots")
	put(g,"E01");g.resources.remove("E01");g._after_effect();drain(g);check(g.hands[0].plot.size()==2,"Further scraps this turn cannot repeat Museum reward")
	g=fresh();put(g,"E13");g.resources.remove("E13");g._after_effect();check(g.wave.queue.is_empty() and g.phase=="main","Museum does not reward its own destruction")
	# Huge rebuilding rewards all rebuilding methods; never intact/small targets.
	g=fresh();put(g,"E14");put(g,"G071");g.nodes.G071.devastated=true;apply(g,0,"rebuild",{"target":"G071","payers":["R0"]})
	check(g.hands[0].group.is_empty() and g.choice.get("source","")=="E14","Rebuild reward waits behind the table animation")
	drain(g);check(g.hands[0].group.size()==1,"Repair vehicle draws one Group after rebuilding a Huge Place")
	g.wave.rebuild("G071");g._after_effect();check(g.phase=="main","Rebuilding an intact Place cannot farm cards")
	g.nodes.G071.devastated=true;give(g,"P37");apply(g,0,"plot",{"id":"P37"});apply(g,0,"rebuild",{"src":"P37","target":"G071"});drain(g);check(g.hands[0].group.size()==2,"Free reconstruction still earns the Huge rebuild reward")
	var agent=AiAgent.new();g=fresh("I09");var observation=g.observation(0,false);check(agent.heuristic_pick(observation) in observation.actions,"AI can choose the new root ability from sanitized information")
	print("CONTACT / TABLE TUNING: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
