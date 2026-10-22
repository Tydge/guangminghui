extends "res://tests/test_contemporary.gd"

func run():
	var g=fresh("I09")
	check(g.stat("R0","p")==4 and g.stat("R0","gp")==2,"Edited UFO printed stats reach the root")
	var science=CardDB.ids("group").filter(func(k):return "科学" in g.card(k).tags and "太空" not in g.card(k).tags).slice(0,5)
	for id in science:put(g,id);g.nodes[id].learned=10
	check(g.goal(0).values.groups==0 and not g.goal(0).met,"Science without Space no longer advances the UFO goal")
	for id in science:g.synergy.add_tag(id,"太空")
	check(g.goal(0).met,"Five Space groups satisfy the edited UFO goal when power is sufficient")
	for id in ["I08","I09","I10","I11","I12"]:
		var expected={"I08":24,"I09":25,"I10":27,"I11":24,"I12":25}
		check(CovenantRules.FACTIONS[id].groups==5 and CovenantRules.FACTIONS[id].power==expected[id],"Edited shared faction evaluator "+id)
	check(g.card("G071").align==["政府","正统"] and g.card("G153").align==["政府","正统"],"China and Xi alignments match the table")
	check(g.card("G156").name=="连锁理发店" and g.card("G156").p==3 and g.card("G156").align==["正统"],"Explicit Barbershop data is applied while its redesign remains pending")
	# A private read-only view neither takes a card nor changes deck order/RNG.
	g=fresh();put(g,"G157");give(g,"E01");give(g,"E02")
	var deck=g.decks.plot.duplicate();var rng_before=g.rng.state;var snapshot=JSON.stringify([g.nodes,g.decks,g.hands,g.rng.state])
	var cmd=action(g,0,"ability",{"src":"G157"});var plan=ActionFlow.plan(g,0,cmd)
	check(not cmd.is_empty() and JSON.stringify([g.nodes,g.decks,g.hands,g.rng.state])==snapshot,"Tarot is independent of Resource capacity and rehearsals are isolated")
	check(not plan.is_empty(),"Tarot read-only action can be presented")
	apply(g,0,"ability",{"src":"G157"})
	check(g.choice.kind=="n_divine" and g.choice.peek==deck.slice(0,3),"Tarot looks at exactly the top three Plots")
	check(g.observation(1,false).choice.is_empty() and g.hands[0].plot.is_empty(),"The opponent cannot inspect Tarot's private view")
	check(g.legal_actions(0).size()==1 and g.legal_actions(0)[0].id=="","Read-only Tarot offers only completion, never a keep/reorder command")
	apply(g,0,"choose",{"id":""})
	check(g.decks.plot==deck and g.rng.state==rng_before,"Tarot restores exact order without consuming RNG")
	# The Arms Brokers' action is free, including while exhausted, but remains once per turn.
	g=fresh();put(g,"G159");put(g,"G001");put(g,"E01");g.nodes.G159.token=0;g.nodes.G001.token=0
	apply(g,0,"ability",{"src":"G159","target":"G001","other":"E01"})
	check(not g.token("G159") and g.token("G001") and "E01" in g.scrap,"Arms Brokers pay only the Device and can act with no mark")
	check(action(g,0,"ability",{"src":"G159"}).is_empty(),"Free Arms Brokers still cannot repeat this turn")
	# Casino fees use Plots and Common Supply, not deployed Resources.
	g=fresh();put(g,"G161");put(g,"G055");put(g,"G075",1);put(g,"G136");give(g,"G043")
	g._launch_attack(0,{"src":"G055","target":"G075","mode":"control"});apply(g,1,"pass")
	cmd=action(g,0,"support",{"src":"G161","stake":true,"plot_fee":"G043"})
	check(cmd.get("power",0)==2 and not cmd.has("resource_fee"),"GP-zero Casino gains two through the selected paid mode")
	apply(g,0,"support",{"src":"G161","stake":true,"plot_fee":"G043"})
	check("G043" in g.discards.group and g.used.has(g.renewal.quota("G136")),"Common Supply pays Casino's Plot cost once")
	g=fresh();put(g,"G161");put(g,"G055");put(g,"G075",1);put(g,"E01")
	g._launch_attack(0,{"src":"G055","target":"G075","mode":"control"});apply(g,1,"pass")
	check(action(g,0,"support",{"src":"G161","stake":true}).is_empty(),"An on-board Resource cannot pay the Casino's new cost")
	# Israel's Device shield affects ordinary Destroy only, including reader totals.
	g=fresh();put(g,"G152");put(g,"E01");put(g,"G005",1)
	var shown=g.card_context("G152");var ordinary=g.attack_preview("G005","G152","destroy");var calamity=g.wave.disaster_preview({"id":"P31","payer":"G005","target":"G152"})
	check(g.stat("G152","r")==5 and shown.destroy_passive==4 and shown.disaster_passive==0,"Israel reader distinguishes ordinary and disaster defenses")
	g.resources.remove("E01")
	check(ordinary.strength==g.attack_preview("G005","G152","destroy").strength-4,"Israel shield requires an on-board Device")
	check(calamity.strength==g.wave.disaster_preview({"id":"P31","payer":"G005","target":"G152"}).strength,"Israel shield never protects disasters")
	# The sword works for either ordinary attack, but not disasters or non-Magic leaders.
	g=fresh();put(g,"G055");put(g,"G043",1);put(g,"E19")
	g._launch_attack(0,{"src":"G055","target":"G043","mode":"destroy"});apply(g,1,"pass");apply(g,0,"resource",{"src":"E19"})
	check(g.battle.bonus_a==5 and "E19" in g.scrap,"Peachwood Sword now also supports ordinary Destroy")
	# Airlift spends a non-root Group mark even when countered; it preserves takeover quota.
	g=fresh();give(g,"P66");give(g,"E01")
	check(action(g,0,"plot",{"id":"P66"}).is_empty(),"A ready root alone cannot pay for Airlift")
	put(g,"G043");give(g,"P15",1);apply(g,0,"plot",{"id":"P66","payer":"G043"});apply(g,1,"counter")
	check(not g.token("G043") and g.token("R0") and not g.deploy_used and not g.auto_used and "E01" in g.hands[0].resource,"Countered Airlift spends its Group fee without deploying or taking over")
	# Inside Job moves one exposed card to the exact top, without a draw or shuffle.
	g=fresh();give(g,"P70");give(g,"P13",1);g.exposed.append("P13");g.locked.append("P13");rng_before=g.rng.state;deck=g.decks.plot.duplicate()
	apply(g,0,"plot",{"id":"P70","target":"P13"})
	check(g.decks.plot==["P13"]+deck and g.hands[1].plot.is_empty() and g.rng.state==rng_before,"Inside Job puts the card first without replacement or randomization")
	check("P13" not in g.exposed and "P13" not in g.locked,"Inside Job clears hand-only statuses")
	# Capacity governs hands only. Full hands reject voluntary draws before fees.
	g=fresh();put(g,"G091");put(g,"G138");give(g,"G043");give(g,"P10");give(g,"E01");give(g,"E02")
	deck=g.decks.resource.duplicate();rng_before=g.rng.state
	check(action(g,0,"research",{"deck":"resource"}).is_empty() and action(g,0,"resource",{"src":"G091"}).is_empty() and action(g,0,"ability",{"src":"G138"}).is_empty(),"Full Resource hands disable voluntary draw/take abilities")
	check(g._draw(0,"resource")=="" and g.decks.resource==deck and g.rng.state==rng_before and g.token("R0"),"Full hands skip the draw without moving a card, spending a mark or RNG")
	g.contemporary.draw_reward("P63",0,"resource","capacity_probe");g._after_effect();drain(g)
	check(g.hands[0].resource.size()==2 and g.decks.resource==deck,"A full-hand passive Resource draw is skipped rather than drawn and discarded")
	g=fresh();put(g,"E01");put(g,"E02")
	check(not action(g,0,"research",{"deck":"resource"}).is_empty(),"Two deployed Resources do not block drawing into an empty hand")
	print("CARD ADJUSTMENTS: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
