class_name ActionFlow
extends RefCounted
## Rehearse on an isolated deterministic copy. The live match commits only after all cues.
static func copy_state(source: GameState) -> GameState:
	var copy=GameState.new(1)
	for prop in source.get_property_list():
		if not (prop.usage&PROPERTY_USAGE_SCRIPT_VARIABLE) or prop.name in ["rng","wave","synergy"]:continue
		var value=source.get(prop.name)
		copy.set(prop.name,value.duplicate(true) if value is Array or value is Dictionary else value)
	copy.rng.seed=source.rng.seed;copy.rng.state=source.rng.state
	for key in ["plans","announced","queue","response_queue"]:copy.wave.set(key,source.wave.get(key).duplicate(true))
	return copy

static func zones(g: GameState) -> Dictionary:
	var result: Dictionary={}
	for kind in ["group","plot"]:
		for place in ["deck","discard"]:
			for id in (g.decks[kind] if place=="deck" else g.discards[kind]):result[id]={"place":place,"player":-1,"kind":kind}
		for p in [0,1]:
			for id in g.hands[p][kind]:result[id]={"place":"hand","player":p,"kind":kind}
	for id in g.nodes:
		if not g.is_root(id):result[id]={"place":"board","player":g.owner(id),"kind":"group"}
		for attachment in g.nodes[id].attached:result[attachment]={"place":"attached","player":g.owner(id),"kind":"plot","target":id}
	if g.world!="":result[g.world]={"place":"world","player":-1,"kind":"plot"}
	if not g.pending_plot.is_empty():result[g.pending_plot.id]={"place":"pending","player":g.pending_plot.player,"kind":"plot"}
	for id in g.battle.get("spent",[]):result[id]={"place":"spent","player":g.battle.attacker,"kind":"plot"}
	var peek=g.choice.get("peek",g.choice.get("options",[]) if g.choice.get("kind","") in ["draw_keep","reorder"] else [])
	for id in peek:result[id]={"place":"choice","player":g.choice.get("player",0),"kind":g.card(id).kind}
	return result

static func plan(g: GameState,p: int,a: Dictionary) -> Dictionary:
	var copy=copy_state(g);var before=zones(g)
	if not copy.act(p,a.duplicate(true)):return {"moves":[],"target":"","source":"","result":{}}
	var after=zones(copy);var moves=copy.motion_events.duplicate(true);var recorded: Array=[]
	for move in moves:
		recorded.append(move.id)
		if move.to=="choice" and after.get(move.id,{}).get("place","")=="hand":move.to="hand"
	for id in after:
		if id in recorded or not before.has(id):continue
		var start=before[id];var finish=after[id]
		if start==finish:continue
		if finish.place in ["hand","discard"] or (start.place=="deck" and finish.place=="choice") or (start.place=="hand" and finish.place=="deck"):
			moves.append({"id":id,"kind":finish.kind,"from":start.place,"to":finish.place,"player":finish.player if finish.place=="hand" else start.player,"from_player":start.player,"from_target":start.get("target","")})
	var played=a if a.type=="plot" else g.pending_plot
	var target="";var source=""
	if not played.is_empty() and copy.pending_plot.is_empty() and a.type not in ["counter","fact_check"] and not copy.last_event.get("event","")=="counter":
		var candidate=played.get("target","")
		# A few older plots store their payer in target; those affect hands/decks instead.
		if g.nodes.has(candidate) and played.id not in ["P21","P23","P24","P25"] and not (a.type=="choose" and a.get("id","")==""):
			target=candidate;source=played.id
	# Battle results must be read on the rehearsal, before any live settlement or motion.
	# after_effect may replace last_event with a victory/choice; last_battle stays intact.
	var result=copy.last_battle.duplicate(true) if not g.battle.is_empty() and copy.battle.is_empty() else {}
	return {"moves":moves,"target":target,"source":source,"result":result}
