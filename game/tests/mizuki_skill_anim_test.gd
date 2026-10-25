extends Node
## Real action clock: startup -> fire -> full recovery; active loop variants and end.
const Ch = preload("res://scripts/characters/character.gd")
const DT := 1.0/60.0
var game
var n := 0
var fails := 0
func ok(value: bool, label: String) -> void:
 n+=1
 if not value:
  fails+=1
  printerr("FAIL: ",label)
func step(o, count: int) -> void:
 for k in count:
  o.follow(DT,o.pos)
  o.update(DT)
func _ready() -> void:
 game=load("res://game.tscn").instantiate()
 add_child(game)
 await get_tree().process_frame
 game.set_process(false)
 var o=game.squad.get_op("mizuki")
 o.pos=game.ppos
 o.elite=2
 o.sp=[-10000.0,-10000.0,-10000.0]
 game.enemies=[]
 game.enemies_sys.build_grid()
 ok(Ch.validate_operator("mizuki",o.def),"native sprites and sequences validate")
 ok(not o.B.has("_free"),"no immediate-damage free flow")
 for slot in [1,2]:
  o.on_leave()
  o.cd=1000.0
  o.sp[slot]=o.sp_need(slot)
  o.start_skill(Vector2.INF,slot)
  var stem: String="skill_s%d"%(slot+1)
  ok(o.sq_ph==1 and o.anim_state().kind==stem and o.anim_state().frame==0,"native startup f0 without idle flash")
  ok(o.acting() and o.fire_t>0.0 and o.s_t[slot]==0.0,"startup owns gameplay window")
  step(o,32)
  ok(o.sq_ph==2 and o.anim_state().kind==stem+"_loop","startup reaches loop")
  var seen := {}
  for k in 60:
   step(o,1)
   seen[o.anim_state().frame]=true
  ok(seen.size()==8,"all eight active-loop frames appear")
  o.cd=0.9
  o.start_attack(o.pos+Vector2.RIGHT*80,0.5,0.25,"",0.9)
  ok(o.anim_state().kind==stem+"_attack" and o.anim_state().frame==0,"attack variant starts at f0")
  var last := -1
  var all_frames := {}
  while o.acting():
   var state: Dictionary=o.anim_state()
   if state.kind==stem+"_attack":
    ok(state.frame>=last,"attack frames do not jump backward")
    last=state.frame
    all_frames[last]=true
   o.cd=1000.0
   step(o,1)
  ok(last==7 and all_frames.size()==8,"complete attack variant before returning to loop")
  step(o,1)
  ok(o.anim_state().kind==stem+"_loop","full recovery returns to loop")
  # S1 instant activation stores charge without interrupting loop or consuming it.
  var near_e: Dictionary=game.spawner.spawn_enemy("runner",o.pos+Vector2(60,0))   # 10-25 自动技能要射程内有敌人才放（docs/151）
  near_e.spd=0.0
  game.enemies_sys.build_grid()
  o.sp[0]=o.sp_need(0)
  o.update(0.0)
  ok(o.ammo[0]==1 and o.sq_i==slot,"S1 stacks while sustained skill owns loop")
  o.start_attack(o.pos+Vector2.RIGHT*80,0.5,0.25,"skill_s1_attack",0.9)
  ok(o.anim_state().kind=="skill_s1_attack","S1 empowered art takes precedence over loop variant")
  o.cd=1000.0
  step(o,60)
  ok(o.sq_i==slot and o.anim_state().kind==stem+"_loop","S1 action returns to original active loop")
  o.mv=200.0
  step(o,1)
  ok(o.anim_state().kind==stem+"_loop","active pose remains stable during movement")
  o.s_t[slot]=0.0
  step(o,1)
  ok(o.sq_ph==3 and o.anim_state().kind==stem+"_end","expiry plays end strip")
  step(o,32)
  ok(o.sq_ph==0 and o.anim_state().kind=="idle","end returns to idle")
 # Missing variant configuration falls back to normal attack without blocking release.
 o.on_leave()
 var sequence: Dictionary=o.def.sprites.skills.s2.duplicate(true)
 o.def.sprites.skills.s2.erase("attack")
 o.cd=1000.0
 o.start_skill(Vector2.INF,1)
 step(o,32)
 o.start_attack(o.pos+Vector2.RIGHT*80,0.5,0.25,"",0.9)
 ok(o.anim_state().kind=="attack" and o.fire_t>0.0,"missing optional variant uses ordinary timed attack")
 o.def.sprites.skills.s2=sequence
 o.on_leave()
 print("%d checks, %d failed"%[n,fails])
 print("MIZUKI SKILL ANIM failures=%d"%fails)
 get_tree().quit(1 if fails else 0)
