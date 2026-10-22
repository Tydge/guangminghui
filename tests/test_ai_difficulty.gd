extends SceneTree
const Tactics=preload("res://scripts/ai_tactics.gd")
var checks=0
var failures=[]
func check(ok: bool,message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	check(is_equal_approx(Tactics.chance(2),1.0/36) and is_equal_approx(Tactics.chance(8),26.0/36),"Tactical AI uses exact 2d6 probabilities")
	check(is_equal_approx(Tactics.chance(99),33.0/36) and Tactics.chance(1)==0,"AI respects automatic 11/12 failure and minimum strength")
	for level in ["easy","normal","hard"]:
		var g=GameState.new(116);var bot=AiAgent.new();bot.difficulty=level;bot.rng.seed=51
		for i in 160:
			if g.phase=="over":break
			var p=0 if not g.legal_actions(0).is_empty() else 1;var before=JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]);var o=g.observation(p,level=="easy")
			check(not o.has("rng") and o.decks.group is int and o.opponent_counts.group is int,"AI observation contains counts instead of deck order or enemy hand")
			var action=bot.pick(o);check(before==JSON.stringify([g.nodes,g.hands,g.decks,g.rng.state]),"AI evaluation never mutates live state or RNG")
			if level!="easy" and o.phase=="main" and o.actions.size()>1:check(bot.last_plan.get("samples",0)==2,"Every ordinary planning snapshot reconstructs two independent samples")
			check(g.act(p,action) and g.validate().is_empty(),"Difficulty submits legal conserving commands")
	var b=AiAgent.new();b.difficulty="hard"
	var fake={"player":0,"actions":[{"type":"accept_plot","label":"放行"},{"type":"counter","id":"P15","label":"骗局"}],"phase":"plot_response","pending_plot":{"id":"P61"},"opponent_counts":{"plot":1},"battle":{}}
	check(b.pick(fake).type=="counter","Hard prioritizes countering a victory declaration")
	var g=GameState.new(19);g.factions=["I01","I03"];g.nodes={};g.phase="main";g.current=0
	for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
	g._enter("G151",0,"R0",1);g._enter("G043",0,"G151",1);g._enter("G005",1,"R1",1)
	var o=g.observation(0);var cycle={"type":"ability","src":"G151","target":"E01"};check(Tactics.defense_reserve(cycle,o)>9,"Hard reserves a last action on a valuable branch over low-value cycling")
	check(Tactics.defense_reserve({"type":"ability","src":"G015","target":"P10"},o)==0,"Free abilities incur no defense token cost")
	o.phase="battle";o.battle={"attacker":1,"defender":0,"target":"G151","src":"G005","mode":"control"};o.battle_values={"strength":23};o.actions=[{"type":"self_defend","src":"G151","power":8},{"type":"support","src":"G043","power":3},{"type":"support","src":"R0","power":3}]
	check(Tactics.chance(23)==Tactics.chance(15) and Tactics.adjusted(o.actions[0],o,0,true)>0,"Hard plans a chain of defenders even when the first alone does not change the dice chance")
	print("AI DIFFICULTY: "+JSON.stringify({"checks":checks,"failures":failures}));quit(0 if failures.is_empty() else 1)
