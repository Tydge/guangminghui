extends SceneTree
var checks=0
var failures=[]
var main
var folder=""
func check(ok: bool,label: String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func fresh() -> GameState:
 var g=GameState.new(902);g.nodes={};g.factions=["I01","I05"];g.current=0;g.turns=[2,2];g.phase="main"
 for kind in g.decks:
  g.decks[kind]=CardDB.ids(kind);g.discards[kind]=[]
  for p in [0,1]:g.hands[p][kind]=[]
 for p in [0,1]:g.nodes[g.root(p)]={"card":g.factions[p],"owner":p,"parent":"","token":1,"attached":[]}
 return g
func put(g: GameState,id: String,p: int=0,parent: String=""):
 g.decks[g.card(id).kind].erase(id)
 if id.begins_with("E"):g.nodes[id]={"card":id,"owner":p,"parent":"","token":int(g.card(id).action),"attached":[],"resource_slot":g.resources.field(p).size()}
 else:g._enter(id,p,g.root(p) if parent=="" else parent,1)
func give(g: GameState,id: String,p: int=0):g.decks[g.card(id).kind].erase(id);g.hands[p][g.card(id).kind].append(id)
func action(g: GameState,p: int,type: String,args: Dictionary={}) -> Dictionary:
 for a in g.legal_actions(p):
  if a.type==type and args.keys().all(func(k):return a.get(k,false if args[k] is bool else null)==args[k]):return a
 return {}
func apply(g: GameState,p: int,type: String,args: Dictionary={}):
 var a=action(g,p,type,args);check(not a.is_empty(),"Legal "+type+str(args))
 if not a.is_empty():check(g.act(p,a),"Apply "+type)
 check(g.validate().is_empty(),"Card conservation")
func disaster(direct=false,coastal=false) -> GameState:
 var g=fresh();g.current=1;put(g,"G104");put(g,"G071",0,"G104" if direct else "R0");put(g,"G005",1)
 if coastal:g.nodes.G104.extra_tags=["沿海"];put(g,"E09")
 give(g,"P31",1);give(g,"P10");give(g,"P11");apply(g,1,"plot",{"id":"P31","target":"G071","payer":"G005"});return g
func rules():
 check(CardDB.get_card("G083").align==["企业","怪异"] and CardDB.get_card("G087").p==4,"Latest edited Altman alignments and Obama P are loaded")
 for outcome in [4,5,6]:
  var vegas=fresh();put(vegas,"G102");give(vegas,"P11")
  var selected_seed=-1
  for seed_value in 200:
   vegas.rng.seed=seed_value
   if vegas._die()==outcome:selected_seed=seed_value;break
  check(selected_seed>=0,"Find Vegas boundary roll");vegas.rng.seed=selected_seed
  apply(vegas,0,"ability",{"src":"G102","target":"P11"})
  check(vegas.hands[0].plot.size()==(3 if outcome>=5 else 0) and vegas.token("G102"),"Vegas 5–6 payout boundary, 4 fails")
 var edited=fresh();put(edited,"G037");put(edited,"G036");apply(edited,0,"ability",{"src":"G037","target":"G036"});check(edited.stat("G036","gp")==4 and edited.nodes.G036.ad_gp==3,"Edited advertising grants GP +3")
 edited=fresh();put(edited,"G001",1);put(edited,"G039");check(edited.attack_preview("G001","G039","control").defense==4,"Edited Underground Newspapers adds four against Government control")
 check(edited.attack_preview("G001","G039","destroy").defense==0,"Newspaper bonus does not apply to Destroy")
 var swiss=fresh();put(swiss,"G076");put(swiss,"G005",1);swiss.current=1;give(swiss,"P31",1)
 check(swiss.attack_preview("G005","G076","destroy").base==7,"Swiss ordinary Destroy still uses R")
 check(swiss.wave.disaster_preview({"id":"P31","payer":"G005","target":"G076"}).base==4,"Swiss disaster preview uses P")
 check(swiss.card_context("G076").disaster_base==4 and swiss.card_context("G076").destroy_base==7,"Reader separates Swiss disaster and ordinary defense")
 apply(swiss,1,"plot",{"id":"P31","payer":"G005","target":"G076"});check(swiss.battle_values().base==4,"Live Swiss disaster uses P")
 swiss.nodes.G076.learned=2;check(swiss.battle_values().base==6,"Swiss disaster follows effective P buffs")
 swiss.nodes.G076.devastated=true;check(swiss.battle_values().base==3 and swiss.stat("G076","r")==7,"Devastated Swiss disaster halves P, not R")
 var g=disaster();check(action(g,0,"plot",{"id":"P10"}).is_empty(),"Good Polls cannot defend disasters")
 var strength=g.battle_values().strength;apply(g,0,"plot",{"id":"P11"});check(g.battle_values().strength==strength-2,"Volunteer Aid still defends disaster")
 for mode in ["control","destroy"]:
  g=fresh();put(g,"G005",1);put(g,"G071");give(g,"P10");g.current=1;apply(g,1,"attack",{"src":"G005","target":"G071","mode":mode});strength=g.battle_values().strength;apply(g,0,"plot",{"id":"P10"});check(g.battle_values().strength==strength-4,"Good Polls defends normal "+mode)
 for direct in [false,true]:
  g=disaster(direct);var boosted=action(g,0,"support",{"src":"G104","amplify":true,"plot_fee":"P10"});var plain=action(g,0,"support",{"src":"G104","amplify":false})
  check(boosted.get("power",0)==(8 if direct else 4) and boosted.get("basis","")==("P" if direct else "GP"),"Cloud doubles eligible P or GP in disaster defense")
  check(plain.get("power",0)==(4 if direct else 2),"Unamplified defense remains available")
  check(g.observation(0).actions.has(boosted),"AI observation includes exact amplified defense")
  apply(g,0,"support",{"src":"G104","amplify":true,"plot_fee":"P10"});check(g.battle.support_d==boosted.power and not g.token("G104") and "P10" in g.discards.plot,"Cloud pays action and discard once, fee does not play Good Polls")
 g=disaster(false,true);check(action(g,0,"support",{"src":"G104","amplify":true}).get("power")==5,"Cable +1 is added after doubling GP 2")
 for restriction in ["silenced","devastated","spent","no_fee"]:
  g=disaster()
  if restriction=="no_fee":
   for id in g.hands[0].plot.duplicate():g._discard(0,id)
  elif restriction=="spent":g.nodes.G104.token=0
  else:g.nodes.G104[restriction]=true
  check(action(g,0,"support",{"src":"G104","amplify":true}).is_empty(),"Cloud respects "+restriction)
 g=disaster();put(g,"G136",0,"G104");g._discard(0,"P10");g._discard(0,"P11");give(g,"G043");apply(g,0,"support",{"src":"G104","amplify":true,"plot_fee":"G043"});check(g.battle.support_d==4 and g.used.has(g.renewal.quota("G136")),"Common Supply substitutes the disaster-support discard once")
 g=fresh();g.current=1;put(g,"G104",1);put(g,"G005",1);put(g,"G071");give(g,"P31",1);give(g,"P10",1);apply(g,1,"plot",{"id":"P31","payer":"G005","target":"G071"});apply(g,0,"pass");check(not g.legal_actions(1).any(func(a):return a.type=="support"),"Disaster attacker cannot use normal or amplified support")
 for method in ["normal","australia"]:
  g=fresh();put(g,"G098");give(g,"G043");give(g,"G044");give(g,"E01");give(g,"E03")
  apply(g,0,"deploy",{"id":"E01","supply":method=="australia"});check(g.auto_used and g.token("R0")== (method=="australia"),"Deployment consumes quota; Australia only replaces payment")
  check(not g.legal_actions(0).any(func(a):return a.type in ["auto","deploy"]),"Deployment blocks another deploy and takeover")
 g=fresh();put(g,"G098");give(g,"G043");give(g,"E01");apply(g,0,"auto",{"id":"G043","parent":"G098"});g.nodes.R0.token=1;check(action(g,0,"deploy").is_empty(),"Takeover also prevents Australia deployment even with restored root action")
func snapshot(g: GameState) -> String:return JSON.stringify([g.nodes,g.hands,g.decks,g.discards,g.phase,g.battle,g.pending_plot,g.rng.state,g.auto_used])
func button(node: Node,text: String):
 for b in node.find_children("*","Button",true,false):
  if b.text==GameLocale.text(text):return b
 return null
func mount(g: GameState):main._start_game(81);main.game=g;main.modal_open=true;main._refresh()
func transition():
 var deadline=Time.get_ticks_msec()+3000
 while main.window_access.transitioning and Time.get_ticks_msec()<deadline:await process_frame
 check(not main.window_access.transitioning,"Window transition finishes")
func key_escape():
 var e=InputEventKey.new();e.pressed=true;e.keycode=KEY_ESCAPE;main._unhandled_key_input(e)
func take(name: String):
 if folder=="" or DisplayServer.get_name()=="headless":return
 await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder+"/"+name+".png")
func ui():
 main=load("res://scenes/main.tscn").instantiate();root.add_child(main);await process_frame;main.sound_volume=0;main.reduced_motion=true;main.presentation_time_scale=0.04
 for language in ["zh","en"]:
  GameLocale.set_language(language)
  for compact in [false,true]:
   root.size=Vector2i(1280,720) if compact else Vector2i(1600,900);await process_frame;main.compact=compact
   for in_battle in [false,true]:
    var g=fresh();g.current=1;put(g,"G001");put(g,"G137");put(g,"G106");put(g,"G005",1);give(g,"P15");give(g,"P10")
    var id="P13" if in_battle else "P22";give(g,id,1);g.exposed.append(id)
    if in_battle:apply(g,1,"attack",{"src":"G005","target":"G001","mode":"destroy"});apply(g,0,"pass")
    apply(g,1,"plot",{"id":id});mount(g);await process_frame;await process_frame
    var panel=main.overlay.get_node("PlotResponse");var peek=panel.find_child("PeekBattlefield",true,false);check(peek.get_parent().name=="ResponseOptions","View Board sits alongside reaction decisions")
    for b in panel.find_children("*","Button",true,false):check(panel.get_global_rect().encloses(b.get_global_rect()),"Reaction option fits: "+b.text)
    var before=snapshot(g)
    if not compact and language=="zh" and DisplayServer.get_name()!="headless":
     var down=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=peek.get_global_rect().get_center();Input.parse_input_event(down);await process_frame
     var up=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_LEFT;up.position=down.position;Input.parse_input_event(up);await create_timer(0.04).timeout
    else:peek.pressed.emit()
    await transition();check(main.window_access.browsing and not main.overlay.visible,"Counter decision can park during main or battle phase")
    main._select_card("G005");main._inspect("P15");main._close_inspection();main._schedule_ai();main._do_action(0,g.legal_actions(0)[0]);check(snapshot(g)==before,"Browsing does not pay, resolve, consume RNG, or allow AI advancement")
    key_escape();await transition();check(not main.window_access.browsing and main.overlay.get_node("PlotResponse")==panel and snapshot(g)==before,"Esc restores exact reaction window and pending Plot")
    key_escape();await transition();check(main.window_access.browsing,"Esc from reaction window shows battlefield")
    button(main.hud,"返回操作窗口").pressed.emit();await transition();check(main.overlay.get_node("PlotResponse")==panel and snapshot(g)==before,"Return control preserves reaction choices")
    await take(language+("-mobile" if compact else "-desktop")+("-battle-counter" if in_battle else "-main-counter"))
    main.modal_open=true
   var g=disaster();mount(g);main._dispatch_options(g.legal_actions(0).filter(func(a):return a.type=="support" and a.src=="G104"));await process_frame;check(button(main.large_layer,"普通支援 · GP +2")!=null and button(main.large_layer,"弹性扩容 · GP +4 · 另弃1张牌")!=null,"Disaster defense exposes plain and doubled support")
   main.interactions.cancel();main.modal_open=true
   g=fresh();put(g,"G098");give(g,"G043");give(g,"E01");mount(g);main.interactions.picker.begin([action(g,0,"deploy",{"id":"E01","supply":true})]);main.interactions.confirm()
   var labels="\n".join(main.large_layer.find_children("*","Label",true,false).map(func(l):return l.text));check(labels.contains(GameLocale.text("与自动接管共用每回合1次机会。")),"Australia confirmation states shared quota")
   main.interactions.cancel();main.modal_open=true
   g=fresh();put(g,"G076");mount(g);main._inspect("G076");var swiss_text="\n".join(main.detail_layer.find_children("*","Label",true,false).map(func(l):return l.text))
   check(swiss_text.contains(GameLocale.text("灾难基础防御 4；被动+0；防备+0。灾难不计忠诚和位置。")),"Swiss reader shows P as disaster base in both languages")
   main._close_inspection();main.modal_open=true
 main._menu();await create_timer(0.6).timeout;main.queue_free();await process_frame;await process_frame;GameLocale.set_language("zh")
func run():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):folder=arg.trim_prefix("--output=");DirAccess.make_dir_recursive_absolute(folder)
 root.size=Vector2i(1600,900);rules();await ui()
 var report={"checks":checks,"failures":failures,"scope":"Disaster plots, cloud support, counter browsing, shared deployment quota","android_device_tested":false};FileAccess.open("res://tests/disaster-responses-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"));print("DISASTER RESPONSES: "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
