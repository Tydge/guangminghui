extends SceneTree
const Baseline=preload("res://tests/ai_baseline/ai_agent.gd")
const FACTIONS=["I01","I02","I03","I04","I05","I06","I07","I08","I09","I10","I11","I12"]
func _initialize():call_deferred("run")
func arg(key: String,fallback: int) -> int:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(key):return value.trim_prefix(key).to_int()
	return fallback
func output_name() -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--output="):return value.trim_prefix("--output=")
	return "res://tests/challenger-report.json"
static func opening_key(g: GameState) -> String:
	# Offline audit only. Never passed to either policy or its information model.
	return JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.rng.state,g.factions,g.current,g.turns,g.serial,g.initial_ai,g.used,g.resource_candidates,g.mulligans,g.resource_rerolls]).sha256_text()
func add(counts: Dictionary,key: String):counts[key]=counts.get(key,0)+1
func run():
	var count=arg("--pairs=",4);var offset=arg("--offset=",0);var stride=arg("--stride=",1);var seed_base=arg("--seed-base=",801)
	var command_limit=arg("--max-commands=",1800);var turn_limit=arg("--max-turns=",45)
	var mirror="--mirror" in OS.get_cmdline_user_args()
	var control="--baseline-control" in OS.get_cmdline_user_args();var opening_only="--opening-only" in OS.get_cmdline_user_args()
	var report={"baseline":JSON.parse_string(FileAccess.get_file_as_string("res://tests/ai_baseline/manifest.json")),"mirror_factions":mirror,"seed_base":seed_base,"offset":offset,"stride":stride,"pairs":count,"max_commands":command_limit,"max_turns":turn_limit,"started_utc":Time.get_datetime_string_from_system(true),"hashes":{},"games":[],"wins":0,"losses":0,"draws":0,"unfinished":0,"illegal":0}
	report.baseline_control=control;report.opening_only=opening_only
	for file in report.baseline.files:
		var path="res://tests/ai_baseline/"+file;var expected=report.baseline.files[file]
		if FileAccess.get_sha256(path)!=expected.frozen_sha256 and FileAccess.get_file_as_string(path).replace("\r\n","\n").sha256_text()!=expected.get("canonical_lf_sha256",""):
			push_error("Frozen baseline was modified: "+file);quit(1);return
	for file in ["scripts/ai_agent.gd","scripts/ai_planner.gd","scripts/ai_tactics.gd","scripts/ai_structure.gd","scripts/game_state.gd","scripts/action_flow.gd","scripts/resource_rules.gd","scripts/wave_rules.gd","scripts/synergy_rules.gd","scripts/renewal_rules.gd","scripts/contemporary_rules.gd","scripts/covenant_rules.gd","data/cards.json"]:report.hashes[file]=FileAccess.get_sha256("res://"+file)
	for index in count:
		var lane=offset+index*stride;var seed_value=seed_base+lane;var faction=FACTIONS[lane%FACTIONS.size()]
		for challenger in ([0] if control else [0,1]):
			var g=GameState.new(seed_value);g.act(0,g.legal_actions(0).filter(func(a):return a.id==faction)[0])
			if mirror:g.factions[1]=faction;g.nodes.R1.card=faction
			var initial=g.hands[1].group.duplicate();initial.sort_custom(func(a,b):return g._initial_score(a,1)>g._initial_score(b,1));g.initial_ai=initial[0]
			var bots=[AiAgent.new() if challenger==0 else Baseline.new(),AiAgent.new() if challenger==1 else Baseline.new()]
			if control:bots=[Baseline.new(),Baseline.new()]
			for p in [0,1]:bots[p].difficulty="hard";bots[p].rng.seed=seed_value*101+p
			var counts=[{},{}];var elapsed=[0,0];var maximum=[0,0];var trace=[];var steps=0;var first=-1;var serial=-1;var opening=""
			for step in command_limit:
				if g.phase=="over" or mini(g.turns[0],g.turns[1])>=turn_limit:break
				var p=0 if not g.legal_actions(0).is_empty() else 1;var o=g.observation(p,false);var rng_before=g.rng.state
				if o.phase=="main" and first<0:
					first=p;opening=opening_key(g)
					if opening_only:break
				if "--diagnostics" in OS.get_cmdline_user_args():
					FileAccess.open("res://work/benchmark-decision-%d.json"%offset,FileAccess.WRITE).store_string(JSON.stringify({"seed":seed_value,"challenger":challenger,"player":p,"step":step,"bot_state":bots[p].rng.state,"observation":o}))
					print("DECISION "+JSON.stringify({"seed":seed_value,"challenger":challenger,"player":p,"step":step,"phase":o.phase,"actions":o.actions.size(),"turns":o.turns}))
				var started=Time.get_ticks_msec();var a=bots[p].pick(o);var duration=Time.get_ticks_msec()-started
				elapsed[p]+=duration;maximum[p]=maxi(maximum[p],duration)
				if a not in o.actions or g.rng.state!=rng_before:push_error("Benchmark policy changed live RNG or returned an illegal command");report.illegal+=1;break
				var kind=a.type+"_"+a.deck if a.type=="research" else a.type
				add(counts[p],kind)
				if trace.size()<160 and o.phase=="main":trace.append({"turn":g.serial,"player":p,"type":kind,"src":a.get("src",a.get("id","")),"target":a.get("target",a.get("parent",""))})
				if not g.act(p,a) or not g.validate().is_empty():push_error("Benchmark transition rejected or broke card conservation");report.illegal+=1;break
				steps+=1
				if g.serial!=serial:
					serial=g.serial;report.current_game={"seed":seed_value,"challenger":challenger,"turns":g.turns,"steps":steps,"counts":counts};FileAccess.open(output_name(),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
			var outcome="unfinished"
			if g.phase!="over":report.unfinished+=1
			elif g.winner==challenger:report.wins+=1;outcome="win"
			elif g.winner<0:report.draws+=1;outcome="draw"
			else:report.losses+=1;outcome="loss"
			var game={"seed":seed_value,"faction":faction,"factions":g.factions,"challenger":challenger,"first":first,"opening_hash":opening,"outcome":outcome,"winner":g.winner,"turns":g.turns,"steps":steps,"counts":counts,"elapsed_ms":elapsed,"max_ms":maximum,"trace":trace,"victory":g.victory}
			report.games.append(game);FileAccess.open(output_name(),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
			print("CHALLENGER GAME: "+JSON.stringify({"seed":seed_value,"faction":faction,"seat":challenger,"outcome":outcome,"turns":g.turns,"steps":steps,"wins":report.wins,"losses":report.losses,"unfinished":report.unfinished}))
	print("CHALLENGER RESULT: "+JSON.stringify({"games":report.games.size(),"wins":report.wins,"losses":report.losses,"draws":report.draws,"unfinished":report.unfinished,"illegal":report.illegal}));quit(1 if report.illegal else 0)
