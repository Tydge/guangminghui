extends SceneTree
var main
var checks=0
var failures=[]
var samples=[]
var folder=""
var overflows=[]
func check(ok: bool,label: String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func button(node: Node,value: String):
 for b in node.find_children("*","Button",true,false):
  if b.text==value:return b
 return null
func act(g: GameState,kind: String,args: Dictionary={}) -> Dictionary:
 for a in g.legal_actions(0):
  if a.type==kind and args.keys().all(func(k):return a.get(k)==args[k]):return a
 return {}
func put(g: GameState,id: String,p: int,parent: String):g.decks.group.erase(id);g._enter(id,p,parent,1)
func fixture() -> GameState:
 main._start_game(181);main.modal_open=true;main.thinking=false
 var g=main.game;g.nodes={};g.hands=[{"group":[],"plot":[],"resource":[]},{"group":[],"plot":[],"resource":[]}];g.decks={"group":CardDB.ids("group"),"plot":CardDB.ids("plot"),"resource":CardDB.ids("resource")};g.factions=["I06","I03"];g.phase="main";g.current=0;g.turns=[2,2]
 for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
 put(g,"G001",0,"R0");put(g,"G033",0,"R0");put(g,"G071",1,"R1");put(g,"G076",1,"G071")
 g.world="P36";g.decks.plot.erase("P36")
 for id in ["G027","G134","G080","G131"]:g.decks.group.erase(id);g.hands[0].group.append(id)
 for id in ["P03","P14","P22","P33","P54"]:g.decks.plot.erase(id);g.hands[0].plot.append(id)
 for id in ["E03","E14"]:g.decks.resource.erase(id);g.hands[0].resource.append(id)
 main.selected="G076";main._refresh(false);return g
func audit(node: Node,name: String):
 for child in node.get_children():
  if child is Control and child.is_visible_in_tree():
   if child is Label or child is Button:
    check(not GameLocale.has_chinese(child.text) or child.text=="中文",name+" translated: "+child.text)
    if child is Button and not child.clip_text and not child is OptionButton:
     var width=child.get_theme_font("font").get_string_size(child.text,HORIZONTAL_ALIGNMENT_LEFT,-1,child.get_theme_font_size("font_size")).x
     if child.icon!=null:width+=child.get_theme_constant("icon_max_width")+child.get_theme_constant("h_separation")
     if width>child.size.x-30:overflows.append({"screen":name,"text":child.text,"width":width,"size":str(child.size)})
   if child is CardView:
    for row in child.text_layout():check(not GameLocale.has_chinese(row.text),name+" translated card")
  audit(child,name)
func take(name: String):
 for i in 3:await process_frame
 audit(main,name)
 if folder=="" or DisplayServer.get_name()=="headless":return
 var deadline=Time.get_ticks_msec()+5000
 while not CardDB.art_requests.is_empty() and Time.get_ticks_msec()<deadline:CardDB.collect_art(8);await process_frame
 await process_frame;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder+"/"+name+".png");samples.append(name)
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
 GameLocale.set_language("zh")
 main=load("res://scenes/main.tscn").instantiate();main.settings_path="user://localization-test.cfg"
 DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path))
 root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.03
 main._settings();main.large_layer.find_child("LanguageChoice",true,false).item_selected.emit(1)
 check(GameLocale.english(),"Settings switches immediately to English")
 GameLocale.set_language("zh");main._load_settings();check(GameLocale.english(),"Language loads from saved settings")
 var config=ConfigFile.new();check(config.load(main.settings_path)==OK and config.get_value("settings","language")=="en","Language preference saved")
 main._clear(main.large_layer);main._menu();await take("en-menu")
 for profile in [{"name":"desktop","size":Vector2i(1600,900),"compact":false},{"name":"mobile","size":Vector2i(1280,720),"compact":true}]:
  root.size=profile.size;main.compact=profile.compact;await process_frame
  main._settings();await take(profile.name+"-settings")
  main._clear(main.large_layer);main._start_game(181);main.modal_open=true;await take(profile.name+"-faction")
  main.game.act(0,main.game.legal_actions(0)[0]);main._refresh();await take(profile.name+"-initial-group")
  main.game.act(0,main.game.legal_actions(0).filter(func(a):return a.type=="initial")[0]);main._refresh();await take(profile.name+"-initial-resource")
  var g=fixture();main._resize();main.modal_open=true;await take(profile.name+"-board")
  for id in ["G076","G134","P33","E14","I06"]:
   main._inspect(id);await take(profile.name+"-reader-"+id);main._close_inspection();main.modal_open=true
  main._draw_deck_picker();await take(profile.name+"-deck-draw");main._clear(main.large_layer)
  for kind in ["faction","group","plot","resource"]:
   main.collection_filter=kind;main.interactions.catalog(true);await take(profile.name+"-catalog-"+kind)
  main._clear(main.large_layer)
  for page in ["basic","alignments","disaster","cards","controls"]:main._help(page);await take(profile.name+"-help-"+page)
  main._clear(main.large_layer)
  var attack=act(g,"attack",{"src":"G001","target":"G071","mode":"control"});check(not attack.is_empty(),"Preview attack fixture legal")
  main._review_action(attack);await take(profile.name+"-attack-preview");main._clear(main.large_layer)
  check(g.act(0,attack),"Begin ordinary battle");g.act(1,g.legal_actions(1).filter(func(a):return a.type=="pass")[0]);main._refresh();await take(profile.name+"-battle")
  var choices=g.legal_actions(0).filter(func(a):return a.type=="support" and a.src=="G033")
  main._dispatch_options(choices);await take(profile.name+"-support-mode");main.interactions.cancel();main.modal_open=true
  g.decks.plot.erase("P01");g.hands[0].plot.append("P01")
  var plot=act(g,"plot",{"id":"P01","target":"G001"});check(not plot.is_empty(),"English combat Plot legal")
  main._do_action(0,plot);main.presentation_tween.pause();await take(profile.name+"-plot-reveal")
  check(g.hands[0].plot.has("P01") and main.busy,"English reveal retains input and rules lock")
  main.presentation_tween.play()
  while main.busy:await process_frame
  main.modal_open=true
  await take(profile.name+"-battle-plot-record")
  var before=JSON.stringify([g.nodes,g.hands,g.battle,g.rng.state])
  main._settings();main._change_language("zh");check(not GameLocale.english(),"Switch back to Chinese")
  check(JSON.stringify([g.nodes,g.hands,g.battle,g.rng.state])==before,"Switch preserves live match and RNG")
  main._change_language("en");main._close_settings();main.modal_open=true
  check(main.overlay.has_node("BattleWindow"),"Closing settings restores translated battle")
  main._dispatch_options(choices);var step=main.interactions.picker.next_key();main._settings();main._change_language("zh");main._close_settings()
  check(main.interactions.picker.next_key()==step,"Pending mode survives language switch")
  main._settings();main._change_language("en");main._close_settings();main.interactions.cancel();main.modal_open=true
 for cid in CardDB.cards:
  main._inspect(cid);audit(main.detail_layer,"all-card reader "+cid);main._close_inspection();main.modal_open=true
 var g=fixture();g._finish(0,g.title("P54")+" · 目标阴谋宣告胜利");main._refresh();main.modal_open=true
 await take("english-victory")
 for panel in main.overlay.get_children():
  if panel is Panel:
   for label in panel.find_children("*","Label",true,false):check(panel.get_global_rect().encloses(label.get_global_rect()),"Victory text contained: "+label.text+" rect="+str(label.get_global_rect())+" panel="+str(panel.get_global_rect()))
 check(GameLocale.missing.is_empty(),"No untranslated composed strings")
 check(overflows.is_empty(),"English buttons including icons fit their allotted width")
 var report={"checks":checks,"failures":failures,"missing":GameLocale.missing,"overflows":overflows,"captures":samples,"profiles":["1600x900","1280x720"],"android_device_tested":false}
 FileAccess.open("res://tests/localization-ui-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("ENGLISH UI: "+JSON.stringify(report))
 DirAccess.remove_absolute(ProjectSettings.globalize_path(main.settings_path));main._menu();await create_timer(0.6).timeout;GameLocale.set_language("zh");main.queue_free();await process_frame;await process_frame;quit(0 if failures.is_empty() else 1)
