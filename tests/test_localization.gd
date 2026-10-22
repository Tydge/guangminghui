extends SceneTree
var checks=0
var failures=[]
var seen_logs={}
func check(ok: bool,label: String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 CardDB.load_all();GameLocale.set_language("en")
 check(GameLocale.has_chinese("政府"),"CJK detection works")
 for id in CardDB.ids("plot"):
  var c=CardDB.get_card(id)
  if c.name.begins_with("新世界秩序："):check(not GameLocale.has_chinese(GameLocale.text("秩序 · "+c.name.trim_prefix("新世界秩序："))),"World Order short HUD name translated "+id)
 check(GameLocale.text("贤者之石").contains("Philosopher's"),"English apostrophes use compact Latin glyphs")
 var catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/localization/en.json"))
 for source in catalog.ui:
  check(not GameLocale.has_chinese(GameLocale.text(source)) or source=="中文","Registered English phrase")
 var format=RegEx.new();format.compile("%%|%[+ 0-9]*(?:\\.\\d+)?[sdf]")
 for entry in catalog.templates:
  var arguments=[]
  for token in format.search_all(entry.source):
   if token.get_string()=="%%":continue
   arguments.append("地方警察" if token.get_string().ends_with("s") else (2.5 if token.get_string().ends_with("f") else 2))
  var sample=entry.source%arguments
  check(not GameLocale.has_chinese(GameLocale.text(sample)),"Template translated: "+sample)
  check(not GameLocale.has_chinese(GameLocale.text("◈  "+sample)),"Decorated template translated")
 check(GameLocale.text("你 · 骗局取消了「疫情暴发」")=='You · Hoax cancels "Epidemic"',"Decorated counter keeps complete verb")
 check(GameLocale.text("AI · 弃牌")=="AI · Discard","Discard caption resolves as a complete phrase")
 check(GameLocale.text("政府")=="Government" and GameLocale.text("企业")=="Corporate","Alignment terminology")
 check(GameLocale.alignments(["政府","暴力","犯罪"],true)=="GV VI CR","Compact alignment abbreviations")
 check(GameLocale.text("主牌揭晓 · 巴伐利亚光明会 对 网络")=="Factions revealed · Bavarian Illuminati vs. The Network","Factions reveal has correct English word order")
 check(GameLocale.text("韧性社会")=="Resilient Societies","World Order short title translated")
 check(GameLocale.progress("团体2/8 · 力量6/45")=="Groups 2/8 · Power 6/45","Goal progress spacing")
 for id in CardDB.cards:
  var c=CardDB.get_card(id)
  for field in ["name","effect","goal","cost","target","style","category"]:
   if c.has(field):check(not GameLocale.has_chinese(GameLocale.text(c[field])),id+" translated "+field)
  for dimensions in [Vector2(94,142),Vector2(138,192),Vector2(220,385),Vector2(350,742)]:
   var view=CardView.new();view.configure(id);view.size=dimensions;view.full=dimensions.x==350
   var runs=view.text_layout()
   check(not runs.is_empty(),id+" has text at "+str(dimensions))
   for row in runs:
    check(not GameLocale.has_chinese(row.text),id+" translated card row: "+row.text)
    check(row.rect.end.y<=dimensions.y-12.9,id+" complete row fits")
   if dimensions.x<200 and c.kind=="group":
    check(runs.size()==3 and runs[1].fs>=11 and runs[2].fs>=11,id+" readable metadata")
    check(not runs[1].text.ends_with("…") and not runs[2].text.ends_with("…"),id+" complete stats and alignments")
   view.free()
 # Translation must never enter rule commands or consume game RNG.
 var one=GameState.new(371);var two=GameState.new(371);var ai=AiAgent.new();ai.rng.seed=271
 for i in 220:
  if one.phase=="over":break
  var player=0 if not one.legal_actions(0).is_empty() else 1
  GameLocale.set_language("en")
  var command=ai.pick(one.observation(player));var original=command.duplicate(true)
  GameLocale.text(command.label)
  check(command==original and command in two.legal_actions(player),"English display preserves canonical command")
  check(one.act(player,command),"English game accepts action")
  for line in one.logs:
   if seen_logs.has(line):continue
   seen_logs[line]=GameLocale.text(line);check(not GameLocale.has_chinese(seen_logs[line]),"Live event translated: "+line+" -> "+seen_logs[line])
  GameLocale.set_language("zh");check(two.act(player,command),"Chinese game accepts same action")
  check(JSON.stringify([one.nodes,one.hands,one.decks,one.rng.state,one.logs,one.phase])==JSON.stringify([two.nodes,two.hands,two.decks,two.rng.state,two.logs,two.phase]),"Languages preserve identical rules and RNG")
 GameLocale.set_language("en")
 print("ENGLISH: %d checks, %d failures"%[checks,failures.size()])
 print("MISSING: "+JSON.stringify(GameLocale.missing))
 GameLocale.set_language("zh");quit(0 if failures.is_empty() else 1)
