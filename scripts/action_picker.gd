class_name ActionPicker
extends RefCounted
var active=false
var actions: Array=[]
var chosen: Dictionary={}
var history: Array=[]
const KEYS=["target","leader","src","parent","payer","other","attachment","fee","plot_fee","group_fee","tag","payers","use_plan","training","algorithm","amplify","solo","star"]
func begin(options: Array) -> void:
	active=true;actions=options.duplicate(true);chosen={};history=[]
func clear() -> void:active=false;actions=[];chosen={};history=[]
func values(key: String) -> Array:
	var result: Array=[]
	for a in actions:
		var candidates=a.get("payers",[]) if key.begins_with("payers:") else [a.get(key,false) if key in ["use_plan","training","algorithm","amplify","solo","star"] else a.get(key)]
		for v in candidates:
			if key.begins_with("payers:") and v in chosen.values():continue
			if v!=null and v not in result:result.append(v)
	return result
func next_key() -> String:
	for key in KEYS:
		if key=="payers" and actions.any(func(a):return not a.get("payers",[]).is_empty()):
			var count=actions.map(func(a):return a.get("payers",[]).size()).max()
			for i in count:
				var part="payers:"+str(i)
				if not chosen.has(part) and values(part).size()>1:return part
		elif not chosen.has(key) and values(key).size()>1:return key
	return ""
func select(key: String,value) -> void:
	history.append({"actions":actions.duplicate(true),"chosen":chosen.duplicate(true)})
	chosen[key]=value
	actions=actions.filter(func(a):return value in a.get("payers",[]) if key.begins_with("payers:") else a.get(key,false)==value if value is bool else a.get(key)==value)
func back() -> bool:
	if history.is_empty():return false
	var previous=history.pop_back();actions=previous.actions;chosen=previous.chosen;return true
