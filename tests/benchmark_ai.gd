extends SceneTree
func _initialize():call_deferred("run")
func run():
	var results=[];var games=[];var data_sha=FileAccess.get_sha256("res://data/cards.json")
	var quick="--quick" in OS.get_cmdline_user_args();var seed_limit=3 if quick else 13
	for levels in [["hard","normal"],["normal","easy"],["hard","easy"]]:
		var wins=[0,0];var draws=0;var unfinished=0;var commands=0
		for seed_value in range(1,seed_limit):
			for swap in [false,true]:
				var g=GameState.new(seed_value+800);var faction=["I01","I03","I09","I11"][(seed_value-1)%4]
				g.act(0,g.legal_actions(0).filter(func(a):return a.id==faction)[0]);g.factions[1]=faction;g.nodes.R1.card=faction
				var initial=g.hands[1].group.duplicate();initial.sort_custom(func(a,b):return g._initial_score(a,1)>g._initial_score(b,1));g.initial_ai=initial[0]
				var bots=[AiAgent.new(),AiAgent.new()]
				for p in [0,1]:bots[p].difficulty=levels[1-p if swap else p];bots[p].rng.seed=seed_value*101+p
				for step in 1400:
					if g.phase=="over":break
					var p=0 if not g.legal_actions(0).is_empty() else 1;var o=g.observation(p,bots[p].difficulty=="easy");var rng_before=g.rng.state
					var a=bots[p].pick(o)
					if g.rng.state!=rng_before or not g.act(p,a) or not g.validate().is_empty():push_error("AI benchmark invalid command or state");quit(1);return
					commands+=1
				if g.phase!="over":unfinished+=1
				elif g.winner<0:draws+=1
				else:wins[1-g.winner if swap else g.winner]+=1
				games.append({"seed":seed_value+800,"faction":faction,"levels":levels,"swap":swap,"winner":g.winner,"finished":g.phase=="over"})
		var result={"levels":levels,"wins":wins,"draws":draws,"unfinished":unfinished,"commands":commands};results.append(result);print("AI BENCHMARK: "+JSON.stringify(result))
	FileAccess.open("res://tests/ai-planning-benchmark-report.json" if quick else "res://tests/ai-benchmark-report.json",FileAccess.WRITE).store_string(JSON.stringify({"data_sha256":data_sha,"paired_seeds":true,"games":12 if quick else 72,"results":results,"matches":games},"\t"));quit()
