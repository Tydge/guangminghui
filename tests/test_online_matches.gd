extends SceneTree
const Room=preload("res://scripts/online/room.gd")
const ViewProjection=preload("res://scripts/online/projection.gd")
var checks=0
var failures=[]
var actions=0
var games=0
func check(value: bool,message: String):
	checks+=1
	if not value:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func finish(room):
	for i in 200:
		if room.pending.is_empty():return
		var before=room.game.rng.state
		for p in [0,1]:
			var event=ViewProjection.presentation(room.game,room.pending.after,p,room.pending.actor,room.pending.action,room.pending.plan)
			var serialized=JSON.stringify(event);var known=ViewProjection.visible(room.game,p)+ViewProjection.visible(room.pending.after,p)
			for kind in room.game.decks:
				for id in room.game.decks[kind]+room.game.hands[1-p][kind]:
					if id not in known:check(('"'+id+'"') not in serialized,"Animation never exposes a hidden identity")
		check(room.game.rng.state==before,"Projection does not consume host RNG")
		var expected=room.pending.after.rng.state;var tx=room.pending.id
		for p in [0,1]:room.input(p,{"op":"presented","tx":tx},1000)
		check(room.game.rng.state==expected,"Commit matches rehearsed RNG exactly")
		check(room.game.validate().is_empty(),"Room action preserves card conservation")
		for p in [0,1]:room.input(p,{"op":"settled","tx":tx},1000)
	check(false,"Unbounded automatic trigger queue")
func run():
	for seed_value in [991,992,993]:
		var room=Room.new("123456",seed_value,1000);room.attach(0,1,1000);room.attach(1,2,1000);room.start(1000)
		var bots=[AiAgent.new(),AiAgent.new()]
		for p in [0,1]:bots[p].rng.seed=seed_value+p;bots[p].planning=false
		for step in 1400:
			if room.game.phase=="over":games+=1;break
			var p=0 if not room.game.legal_actions(0).is_empty() else 1
			var observation=room.game.observation(p,false)
			check(not observation.actions.is_empty(),"Online room has no deadlock")
			if observation.actions.is_empty():break
			var a=bots[p].heuristic_pick(observation)
			var view=room.state_for(p)
			var matching=view.actions.filter(func(candidate):return room.issued[p][candidate._net]==a)
			check(matching.size()==1,"Both perspectives retain exact canonical command IDs")
			if matching.size()!=1:break
			room.intent(p,matching[0]._net,1000);finish(room);actions+=1;room.outgoing.clear()
		print("Online simulated match seed=",seed_value," phase=",room.game.phase," commands=",actions)
	check(games==3,"All three online matches reach a real victory")
	print("ONLINE MATCH CHECKS: "+JSON.stringify({"checks":checks,"failures":failures,"commands":actions,"finished":games}));quit(0 if failures.is_empty() else 1)
