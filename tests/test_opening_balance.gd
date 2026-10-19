extends SceneTree
var checks=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func action(g: GameState,p: int,kind: String,args: Dictionary={}) -> Dictionary:
	for a in g.legal_actions(p):
		if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
	return {}
func fresh() -> GameState:
	var g=GameState.new(81);g.act(0,g.legal_actions(0)[0]);g.phase="main";g.current=0;g.turns=[1,1];g.hands=[{"group":[],"plot":[]},{"group":[],"plot":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot")};g.nodes.R0.token=1;g.nodes.R1.token=1;return g
func put(g: GameState,id: String,parent: String) -> void:g.decks.group.erase(id);g._enter(id,0,parent,1)
func give(g: GameState,id: String) -> void:g.decks[g.card(id).kind].erase(id);g.hands[0][g.card(id).kind].append(id)
func _initialize() -> void:
	var first_players: Array=[]
	for seed_value in range(1,33):
		var g=GameState.new(seed_value);g.act(0,g.legal_actions(0)[0])
		check(g.hands[0].plot.size()==2 and g.hands[1].plot.size()==2,"Both players have two plots before initiative")
		var initial=g.legal_actions(0)[0];g.act(0,initial);var first=g.current;var second=1-first;first_players.append(first)
		check(g.hands[first].plot.size()==2 and g.hands[second].plot.size()==3,"Only actual second player receives exactly one additional plot")
		check(g.decks.plot.size()==CardDB.ids("plot").size()-5 and g.exposed.is_empty(),"Compensation draws once from shared deck and does not reveal identity")
		check(g.hands[0].group.size()==4 and g.hands[1].group.size()==4,"Compensation leaves opening group selection unchanged")
		check(g.logs.back().contains("后手额外抽1张阴谋"),"Initiative log makes compensation visible")
		check(not g.act(0,initial) and g.hands[0].plot.size()+g.hands[1].plot.size()==5,"Replaying setup command cannot duplicate compensation")
		check(g.validate().is_empty(),"Compensated opening conserves all cards")
	check(0 in first_players and 1 in first_players,"Compensation covers both human and AI going second")
	var g=fresh();put(g,"G020","R0");give(g,"G026");give(g,"P17")
	var takeover=action(g,0,"auto",{"id":"G026","parent":"G020"});check(not takeover.is_empty() and g.act(0,takeover),"Normal automatic takeover remains available")
	check(not g.token("G026") and g.captured.has("G026") and not g.can_recharge("G026"),"Automatic entrant has no action and shares the recruitment recovery lock")
	check(not g.token("R0") and g.auto_used and action(g,0,"auto").is_empty(),"Root action and once-per-turn cost remain enforced")
	check(action(g,0,"attack",{"src":"G026"}).is_empty(),"New automatic entrant cannot lead an attack")
	check(action(g,0,"ability",{"src":"G020","target":"G026"}).is_empty(),"Power Company cannot bypass entry lock")
	check(action(g,0,"plot",{"id":"P17","target":"G026"}).is_empty(),"Reload plot cannot bypass entry lock")
	g._request_end();check(g.current==1,"Normal turn end advances to opponent")
	g.act(1,action(g,1,"draw",{"group":false,"plot":false}));check(not g.token("G026"),"Opponent's natural refill does not ready the newcomer")
	g._request_end();g.act(0,action(g,0,"draw",{"group":false,"plot":false}));check(g.token("G026") and not g.captured.has("G026"),"Newcomer receives its normal action at the next own turn")
	check(g.validate().is_empty(),"Entry lock and later refill conserve cards")
	for root_ready in [false,true]:
		g=fresh();put(g,"G017","R0");give(g,"G043");g.nodes.R0.token=int(root_ready)
		check(g.act(0,action(g,0,"auto",{"id":"G043","parent":"G017"})),"Free franchise works with either root token state")
		check(g.token("R0")==root_ready and not g.token("G043") and not g.can_recharge("G043") and g.auto_used,"Franchise waives only root cost, not the entry action lock or quota")
		check(g.validate().is_empty(),"Franchise conserves cards")
	print("OPENING BALANCE: %d checks, %d failures"%[checks,failures.size()]);FileAccess.open("res://tests/opening-balance-report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"));quit(0 if failures.is_empty() else 1)
