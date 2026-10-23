extends "res://tests/test_contemporary.gd"
const Room=preload("res://scripts/online/room.gd")
const Remote=preload("res://scripts/online/remote_state.gd")
func snapshot(g: GameState) -> String:
	return JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state,g.recharged,g.captured,g.wave.queue,g.choice])
func seal_fixture() -> GameState:
	var g=fresh();put(g,"G055");put(g,"G003",1);put(g,"G001",1,"G003");put(g,"G002",1,"G001");put(g,"G007",1,"G003");give(g,"P67");return g
func run():
	var g=fresh("I07");check(g.stat("R0","p")==7,"Shangri-La uses printed P7 in the live engine")
	# Snapshot the direct children at resolution; the seal is not a persistent aura.
	g=seal_fixture();var before=snapshot(g);var cmd=action(g,0,"plot",{"id":"P67","target":"G003","payer":"G055"});var plan=ActionFlow.plan(g,0,cmd)
	check(snapshot(g)==before,"Multi-target seal rehearsal leaves the real state and RNG untouched")
	for id in ["G003","G001","G007"]:check(id in plan.camera_ids and plan.board_after[id].no_support,"Every sealed Group participates in the public cue: "+id)
	check(not plan.board_after.G002.get("no_support",false),"Grandchildren are not sealed")
	apply(g,0,"plot",{"id":"P67","target":"G003","payer":"G055"})
	var context={"src":"R0","target":"G002","attacker":0,"defender":1,"mode":"control"}
	for id in ["G003","G001","G007"]:
		check(g.support_power(id,context)==0 and "符箓封印" in "\n".join(g.contemporary.reader(id)),"Support denial is reflected in rules and full-card reader: "+id)
	g.nodes.G007.parent="R1";put(g,"G023",1,"G003")
	check(g.nodes.G007.no_support and not g.nodes.G023.get("no_support",false),"Moving a sealed child does not clear it; a later child is unaffected")
	g.nodes.G055.token=1;g.discards.plot.erase("P67");g.hands[0].plot.append("P67")
	check(not action(g,0,"plot",{"id":"P67","target":"G003"}).is_empty(),"An already sealed parent remains a valid target when a new child is unsealed")
	g.hands[0].plot.erase("P67");g.discards.plot.append("P67")
	apply(g,0,"attack",{"src":"R0","target":"G001","mode":"control"})
	check(not action(g,1,"self_defend").is_empty(),"Sealed target may still self-defend")
	g.battle={};g.phase="main";g._complete_end()
	check(["G003","G001","G007"].all(func(id):return not g.nodes[id].get("no_support",false)),"Every snapshot seal expires at the end of the turn")
	g=seal_fixture();give(g,"P15",1);apply(g,0,"plot",{"id":"P67","target":"G003","payer":"G055"});apply(g,1,"counter")
	check(["G003","G001","G007"].all(func(id):return not g.nodes[id].get("no_support",false)),"Counterplay prevents the entire seal, including children")
	# Rebuild first, then apply the usual one-extra-recovery rule, before rewards.
	for blocked in ["", "captured", "recharged"]:
		g=fresh();put(g,"E17");put(g,"E14");put(g,"G075");g.nodes.G075.devastated=true;g.nodes.G075.token=0
		if blocked!="":g.get(blocked)["G075"]=true
		before=snapshot(g);cmd=action(g,0,"resource",{"src":"E17","target":"G075"});plan=ActionFlow.plan(g,0,cmd)
		check(snapshot(g)==before and plan.board_after.G075.token==int(blocked==""),"Rebuild/recovery is fully rehearsed without changing live state: "+blocked)
		apply(g,0,"resource",{"src":"E17","target":"G075"})
		check(not g.wave.devastated("G075") and g.token("G075")== (blocked=="") and not g.token("E17"),"Medical Station rebuilds but honors recovery eligibility: "+blocked)
		check(g.hands[0].group.is_empty() and g.choice.get("source","")=="E14","Any-size Place reward waits for table settlement")
		drain(g);check(g.hands[0].group.size()==1,"Repair Vehicle rewards the rebuilt non-Huge Place exactly once")
		g.wave.rebuild("G075");g._after_effect();check(g.phase=="main","An intact Place cannot produce another rebuild reward")
	g=fresh();put(g,"E17");put(g,"G071");g.nodes.G071.devastated=true
	check(action(g,0,"resource",{"src":"E17"}).is_empty(),"Medical Station still cannot rebuild Huge Places")
	g=fresh();put(g,"G075");g.nodes.G075.devastated=true;g.nodes.G075.token=0;g.wave.rebuild("G075")
	check(not g.token("G075") and not g.recharged.has("G075"),"Ordinary rebuilds do not inherit Medical Station recovery")
	# The new fixed total is eight, in actual combat and the AI fallback.
	for strength in [7,8]:
		g=fresh();put(g,"E15");put(g,"G043",1);apply(g,0,"attack",{"src":"R0","target":"G043","mode":"destroy"});apply(g,1,"pass")
		g.battle.bonus_a+=strength-g.battle_values().strength;var agent=AiAgent.new();cmd=action(g,0,"resource",{"src":"E15"})
		check((agent._resource_score(cmd,g.observation(0,false))>0)==(strength==8),"AI evaluates Coin against its actual eight-point threshold")
		apply(g,0,"resource",{"src":"E15"});g._resolve_battle()
		check(g.last_battle.dice==[4,4] and g.last_battle.success==(strength==8),"Fixed 4+4 resolves with the correct boundary")
	# Goal thresholds and online presentation use the same authoritative engine.
	var goals=load("res://tests/test_covenant.gd").new()
	for goal in ["P52","P55"]:
		g=goals.goal_fixture(goal);check(g.covenant.progress(0,goal).met,"Updated goal fixture meets the current threshold: "+goal)
		if goal=="P52":
			g._return_subtree("G024");put(g,"G007")
			check(g.covenant.progress(0,goal).values.groups==9 and g.covenant.progress(0,goal).values.small==7 and not g.covenant.progress(0,goal).met,"Nine Groups with only seven printed low-P Groups no longer meet Grassroots")
			g=goals.goal_fixture(goal)
		var removed="G024" if goal=="P52" else "G025";g._return_subtree(removed)
		check(not g.covenant.progress(0,goal).met,"Dropping below the new nine-Group boundary blocks declaration: "+goal)
	goals.free()
	g=seal_fixture();var room=Room.new("654321",77,1000);room.game=g;room.started=true;room.attach(0,11,1000);room.attach(1,12,1000)
	cmd=action(g,0,"plot",{"id":"P67","target":"G003","payer":"G055"});room.prepare(0,cmd,1000)
	check(not g.nodes.G001.get("no_support",false),"Online prepare does not apply the child's seal early")
	room.input(0,{"op":"presented","tx":room.pending.id},1100)
	check(not g.nodes.G001.get("no_support",false),"One client finishing cannot commit the multi-target effect")
	room.input(1,{"op":"presented","tx":room.pending.id},1200)
	check(g.nodes.G001.no_support and room.pending.stage=="settle","Both presentations finish before authoritative seal commit")
	for player in [0,1]:
		var remote=Remote.new();remote.install(room.state_for(player))
		check(remote.nodes.G001.no_support and "符箓封印" in "\n".join(remote.contemporary.reader("G001")),"Both online readers show the same child's sealed state")
		check(not JSON.stringify(room.state_for(player)).contains('"rng"'),"Updated state projection does not expose server RNG")
	print("RELEASE TUNING: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
