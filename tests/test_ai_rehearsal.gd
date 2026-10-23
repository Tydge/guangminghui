extends "res://tests/test_contemporary.gd"
func state_key(g: GameState) -> String:
	var state={}
	for property in g.get_property_list():
		if property.usage&PROPERTY_USAGE_SCRIPT_VARIABLE and property.name not in ["rng","wave","synergy","renewal","resources","contemporary","covenant"]:state[property.name]=g.get(property.name)
	state.rng=g.rng.state
	for key in ["plans","announced","queue","response_queue"]:state["wave_"+key]=g.wave.get(key)
	return JSON.stringify(state)
func run():
	var rng=RandomNumberGenerator.new();rng.seed=81;var transitions={}
	for seed_value in [217,311,761,1091]:
		var g=GameState.new(seed_value)
		for step in 350:
			if g.phase=="over":break
			var p=0 if not g.legal_actions(0).is_empty() else 1;var actions=g.legal_actions(p)
			var ranked=actions.filter(func(a):return a.type not in ["end","pass","accept_plot","reroll_resource","mulligan"])
			var a=actions[rng.randi_range(0,actions.size()-1)] if ranked.is_empty() or rng.randf()<0.2 else ranked[rng.randi_range(0,ranked.size()-1)]
			var trial=ActionFlow.copy_state(g);var before=JSON.stringify(a)
			var real_ok=g.act(p,a);var trial_ok=trial._act_generated(p,a)
			check(real_ok and trial_ok and state_key(g)==state_key(trial),"Generated-action rehearsal matches live validation and every rule module: "+a.type)
			check(JSON.stringify(a)==before and g.validate().is_empty(),"Rehearsal preserves caller commands, actual RNG and card conservation")
			transitions[a.type]=transitions.get(a.type,0)+1
	check(transitions.has("attack") and transitions.has("support") and transitions.has("plot") and transitions.has("choose") and transitions.has("end"),"Equivalence includes combat, choices, Plots and end-of-turn cleanup")
	print("AI REHEARSAL: "+JSON.stringify({"checks":checks,"transitions":transitions,"failures":failures}));quit(0 if failures.is_empty() else 1)
