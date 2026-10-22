extends "res://tests/test_contemporary.gd"
func run():
	var g=fresh();put(g,"G156");put(g,"G153",0,"G156")
	check(g.stat("G153","p")==g.card("G153").p+1 and g.hand_limit(0)==5,"Salon grants Celebrity P without the retired hand-capacity bonus")
	var copy=ActionFlow.copy_state(g);copy.nodes.G156.silenced=true
	check(copy.stat("G153","p")==g.card("G153").p and g.stat("G153","p")==g.card("G153").p+1,"Salon rules bind independently on rehearsals and silence disables the aura")
	g.nodes.G156.devastated=true;check(g.stat("G153","p")==g.card("G153").p+1,"Devastation does not disable an otherwise active passive aura")
	g.nodes.G153.parent="R0";put(g,"G043",0,"G156")
	check(g.stat("G153","p")==g.card("G153").p and g.stat("G043","p")==g.card("G043").p,"Salon excludes non-Celebrities and non-direct Celebrities")
	g.synergy.add_tag("G043","名人");check(g.stat("G043","p")==g.card("G043").p+1,"Salon follows currently granted Celebrity tags")
	check(g.contemporary.reader("G043").has("形象塑造 · 来自高档沙龙的P+1。"),"Reader identifies the Salon aura source")
	check(g.validate().is_empty(),"Salon fixture conserves the card pool")
	g=fresh();put(g,"G169");put(g,"G001",0,"G169");put(g,"G002",0,"G169")
	g.nodes.G001.mask=["政府","暴力"];g.nodes.G002.mask=["企业","正统"]
	check(g.stat("G169","slots")==3 and g.contemporary.tenant_alignments("G169").size()==4 and g.stat("G169","p")==2,"Apartment has three slots and no P bonus below five types")
	put(g,"G003",0,"G169");g.nodes.G003.mask=["自由","正统"]
	check(g.contemporary.tenant_alignments("G169").size()==5 and g.stat("G169","p")==5,"Apartment counts alignment types once across the three direct children")
	check(g.stat("G169","gp")==0 and g.stat("G169","r")==4,"Apartment increases P only")
	check(g.self_power("G169")==10 and g.card_context("G169").destroy_base==5,"Apartment strength reaches self-defense and printed/current reader values")
	check(g.contemporary.reader("G169").has("多元合租 · P+3已生效。"),"Reader shows the live threshold status")
	put(g,"G043",0,"G001");g.nodes.G043.mask=["怪异","和平","狂热"]
	check(g.contemporary.tenant_alignments("G169").size()==5,"Apartment excludes grandchildren")
	g.nodes.G003.parent="G001"
	check(g.contemporary.tenant_alignments("G169").size()==4 and g.stat("G169","p")==2,"Reparenting removes the Apartment aura immediately")
	g.nodes.G002.mask=["企业","正统","自由"];check(g.stat("G169","p")==5,"Temporary effective alignments can activate the Apartment")
	g.nodes.G169.silenced=true;check(g.stat("G169","p")==2,"Silencing disables Apartment strength without deleting tenant identities")
	g.nodes.G169.silenced=false;g.nodes.G169.devastated=true;check(g.stat("G169","p")==2,"Devastation halves the effective P after the Apartment aura")
	g.nodes.G169.devastated=false;copy=ActionFlow.copy_state(g);copy.nodes.G002.mask=["企业"]
	check(copy.stat("G169","p")==2 and g.stat("G169","p")==5,"Apartment rehearsals recompute the condition without modifying the live tree")
	put(g,"G005");g.nodes.G169.parent="G005";put(g,"G071",1)
	var battle={"src":"G071","target":"G005","attacker":1,"defender":0,"mode":"control"}
	check(g.support_power("G169",battle)==g.stat("G169","p"),"Apartment no longer has the retired extra parent-defense support bonus")
	check(g.validate().is_empty(),"Apartment fixture remains a valid tree")
	print("SALON / APARTMENT: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
