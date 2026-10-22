extends SceneTree
const PAIRS=[["hard","normal"],["normal","easy"],["hard","easy"]]
const FACTIONS=["I01","I03","I05","I07","I09","I11","I12","I08"]
func _initialize():call_deferred("run")
func argument(prefix: String,fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):return arg.trim_prefix(prefix).to_int()
	return fallback
func text_argument(prefix: String,fallback: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):return arg.trim_prefix(prefix).validate_filename()
	return fallback
func add(counts: Dictionary,key: String,amount: int=1):counts[key]=counts.get(key,0)+amount
func family(a: Dictionary,g: GameState) -> String:
	if a.type=="attack":return a.mode+("_enemy" if g.nodes.has(a.target) else "_hand")
	if a.type=="research":return "research_"+a.deck
	return a.type
func signature(g: GameState) -> String:
	var rows=[];var ids=g.nodes.keys();ids.sort()
	for id in ids:rows.append([id,g.owner(id),g.nodes[id].parent,g.stat(id,"p"),g.stat(id,"gp"),g.stat(id,"r"),g.wave.devastated(id)])
	return JSON.stringify([rows,g.world,g.destroyed])
func shape(g: GameState,p: int) -> Dictionary:
	var depth=0;var root_children=0;var branch_size=0;var groups=g.groups(p)
	for id in groups:
		depth=maxi(depth,g.depth(id))
		if g.nodes[id].parent==g.root(p):root_children+=1;branch_size=maxi(branch_size,g.subtree(id).size())
	return {"groups":groups.size(),"depth":depth,"root_children":root_children,"largest_branch":branch_size}
func run():
	var quick="--quick" in OS.get_cmdline_user_args();var count=argument("--seeds=",2 if quick else 12);var lane=argument("--pair=",-1);var limit=argument("--max-commands=",1400)
	var offset=argument("--offset=",0);var stride=argument("--stride=",1);var label=text_argument("--label=","")
	var suffix="" if label=="" else "-"+label
	var results=[];var games=[];var totals={};var timing={};var hashes={}
	for path in ["data/cards.json","scripts/ai_agent.gd","scripts/ai_planner.gd","scripts/ai_structure.gd","scripts/ai_tactics.gd","scripts/contemporary_rules.gd"]:hashes[path]=FileAccess.get_sha256("res://"+path)
	for pair_id in PAIRS.size():
		if lane>=0 and lane!=pair_id:continue
		var levels=PAIRS[pair_id];var wins=[0,0];var draws=0;var unfinished=0;var commands=0;var first_wins=0
		for index in count:
			var seed_index=offset+index*stride
			for swap in [false,true]:
				var seed_value=801+seed_index;var faction=FACTIONS[seed_index%FACTIONS.size()];var g=GameState.new(seed_value)
				g.act(0,g.legal_actions(0).filter(func(a):return a.id==faction)[0]);g.factions[1]=faction;g.nodes.R1.card=faction
				var initial=g.hands[1].group.duplicate();initial.sort_custom(func(a,b):return g._initial_score(a,1)>g._initial_score(b,1));g.initial_ai=initial[0]
				var bots=[AiAgent.new(),AiAgent.new()];var hist=[{},{}];var attack_cards=[{},{}];var trace=[];var last_public=["",""];var quiet=[0,0];var longest=[0,0];var starts=["",""];var first=-1;var end_ready=[[],[]];var repeated=0;var turn_seen={};var last_turn=-1;var steps=0
				var trees=[[],[]]
				for p in [0,1]:bots[p].difficulty=levels[1-p if swap else p];bots[p].rng.seed=seed_value*101+p
				for step in limit:
					if g.phase=="over":break
					var p=0 if not g.legal_actions(0).is_empty() else 1;var o=g.observation(p,bots[p].difficulty=="easy");var rng_before=g.rng.state;var began=Time.get_ticks_msec();var a=bots[p].pick(o);var elapsed=Time.get_ticks_msec()-began
					if g.rng.state!=rng_before or a not in o.actions:push_error("AI benchmark invalid command or RNG mutation");quit(1);return
					var level=bots[p].difficulty
					if not timing.has(level):timing[level]=[]
					if o.phase=="main":timing[level].append(elapsed)
					if o.phase=="main":
						if first<0:first=p
						var kind=family(a,g);add(hist[p],kind)
						if not totals.has(level):totals[level]={}
						add(totals[level],kind)
						if starts[p]=="" and kind!="end":starts[p]=kind
						if a.type=="attack":add(attack_cards[p],a.src)
						if last_turn!=g.serial:turn_seen.clear();last_turn=g.serial
						var key=JSON.stringify(a)
						if turn_seen.has(key) and a.type not in ["end","research"]:repeated+=1
						turn_seen[key]=true
						if trace.size()<160:trace.append({"turn":g.serial,"seat":p,"kind":kind,"src":a.get("src",a.get("id","")),"target":a.get("target",a.get("parent",""))})
						if a.type=="end":end_ready[p].append(g.groups(p).filter(func(id):return g.token(id)).size());trees[p].append(shape(g,p))
					if not g.act(p,a) or not g.validate().is_empty():push_error("AI benchmark illegal or nonconserving transition");quit(1);return
					if o.phase=="main" and a.type=="end":
						var current=signature(g);quiet[p]=quiet[p]+1 if last_public[p]==current else 0;last_public[p]=current;longest[p]=maxi(longest[p],quiet[p])
					commands+=1;steps+=1
				if g.phase!="over":unfinished+=1
				elif g.winner<0:draws+=1
				else:
					wins[1-g.winner if swap else g.winner]+=1
					if g.winner==first:first_wins+=1
				var game={"seed":seed_value,"faction":faction,"levels":levels,"swap":swap,"winner":g.winner,"finished":g.phase=="over","commands":steps,"turns":g.turns,"first":first,"opening":starts,"actions":hist,"attack_leaders":attack_cards,"end_ready":end_ready,"max_quiet_turns":longest,"same_command_repeats":repeated,"trace":trace,"trees":trees,"final_trees":[shape(g,0),shape(g,1)]};games.append(game)
				print("AI GAME: "+JSON.stringify({"pair":levels,"seed":seed_value,"faction":faction,"swap":swap,"winner":g.winner,"finished":game.finished,"commands":steps,"quiet":longest}))
				FileAccess.open("res://tests/ai-benchmark-pair-%d%s-report.json"%[pair_id,suffix],FileAccess.WRITE).store_string(JSON.stringify({"hashes":hashes,"paired_seats":true,"games":games,"actions":totals,"timing":timing},"\t"))
		var result={"levels":levels,"wins":wins,"draws":draws,"unfinished":unfinished,"commands":commands,"first_player_wins":first_wins};results.append(result);print("AI BENCHMARK: "+JSON.stringify(result))
	var timing_summary={}
	for level in timing:
		var values=timing[level];values.sort();var total=0
		for ms in values:total+=ms
		timing_summary[level]={"decisions":values.size(),"mean_ms":float(total)/maxi(1,values.size()),"p95_ms":values[mini(values.size()-1,int(values.size()*0.95))] if not values.is_empty() else 0,"max_ms":values.back() if not values.is_empty() else 0}
	var report={"hashes":hashes,"paired_seats":true,"results":results,"matches":games,"actions":totals,"timing":timing_summary}
	var output="res://tests/ai-benchmark-pair-%d%s-report.json"%[lane,suffix] if lane>=0 else ("res://tests/ai-planning-benchmark%s-report.json"%suffix if quick else "res://tests/ai-benchmark%s-report.json"%suffix)
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));quit()
