extends RefCounted
## Heuristic structure quality, not a capture probability. Reads an isolated rule model.
## A descendant is only as secure as the weakest capturable ancestor above it.
static func material(g: GameState,id: String) -> float:
	return 2+g.stat(id,"p")*1.6+g.stat(id,"gp")*1.4

static func hold(g: GameState,id: String) -> float:
	var defense=maxi(0,g.stat(id,"r")+g.loyalty_defense(id)+g.position_defense(id)+g.passive_defense(id,"control"))
	return float(defense)/(defense+12.0)

static func path_hold(g: GameState,id: String) -> float:
	var value=1.0;var current=id
	while g.nodes.has(current) and not g.is_root(current):
		value=minf(value,hold(g,current));current=g.nodes[current].parent
	return value

static func member_value(g: GameState,id: String) -> float:
	return material(g,id)*0.6*(path_hold(g,id)-0.5)+g.position_defense(id)*0.08

static func quality(g: GameState,p: int) -> float:
	var value=0.0
	for id in g.groups(p):value+=member_value(g,id)
	return value

static func placement_hint(g: GameState,a: Dictionary) -> float:
	var id=a.id;var parent=a.parent
	var before_parent=g.stat(parent,"p")*1.6+g.stat(parent,"gp")*1.4
	var printed=CardDB.get_card(id)
	# Tentative nodes live only on the planner's private model and are removed below.
	# No action, trigger, hand/deck change, or RNG advance occurs here.
	g.nodes[id]={"card":id,"owner":g.owner(parent),"parent":parent,"token":0,"attached":[]}
	var value=member_value(g,id)+(g.stat(id,"p")-printed.p)*1.6+(g.stat(id,"gp")-printed.gp)*1.4
	value+=g.stat(parent,"p")*1.6+g.stat(parent,"gp")*1.4-before_parent
	g.nodes.erase(id)
	return value
