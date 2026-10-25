extends Node
const Fixture = preload("res://tests/data_ops/attack_phases_fixture.gd")
const Ch = preload("res://scripts/characters/character.gd")
const DT := 1.0/60.0
var g
var checks := 0
var fails := 0
func ok(v: bool, label: String) -> void:
 checks += 1
 if not v:
  fails += 1
  printerr("FAIL: ",label)
func fresh(rate := 1.0, leader := true):
 var d: Dictionary=Ch.load_def("mizuki").duplicate(true)
 var o=Fixture.new(g,d)
 o.pos=g.ppos
 o.is_leader=leader
 o.elite=0
 o.sp=[-10000.0,-10000.0,-10000.0]
 g.stats.remove_source("mizuki_runtime_rate")
 g.stats.add(&"op_aspd","override",rate,"mizuki_runtime_rate","op:mizuki")
 o.refresh_stats()
 o.sync_stats(g.stats)
 g.enemies=[]
 g.enemies_sys.build_grid()
 return o
func target(o) -> Dictionary:
 var e: Dictionary=g.spawner.spawn_enemy("runner",o.pos+Vector2(80,0))
 e.hp=1000000.0
 e.maxhp=e.hp
 g.enemies_sys.build_grid()
 return e
func step(o, count: int) -> void:
 for k in count:
  g.t+=DT
  o.follow(DT,o.pos)
  o.update(DT)
func _ready() -> void:
 g=load("res://game.tscn").instantiate()
 add_child(g)
 await get_tree().process_frame
 g.set_process(false)
 test_s3_original()
 test_s3_fx()
 test_attacks()
 test_matrix()
 test_without_textures()
 test_overlap()
 test_growth()
 test_timing_validation()
 print("MIZUKI RUNTIME %d checks, %d failed" % [checks,fails])
 get_tree().quit(1 if fails else 0)
func test_attacks() -> void:
 for rate in [1.0,2.0,4.0]:
  var o=fresh(rate)
  var e=target(o)
  o.ammo[0]=2
  o.cd=0.0
  o.update(DT)
  ok(e.hp==1000000.0,"startup must not damage")
  ok(o.ammo[0]==2,"startup preserves S1 charge")
  ok(o.fire_t>0.0,"startup schedules release")
  ok(o.act_anim=="skill_s1_attack","S1 uses empowered attack pixels")
  var duration: float=o.attack_dur
  var cycle: float=o.cd
  ok(duration>=0.36-0.0001 and cycle>=duration+0.09-0.0001,"bounded full action plus visible rest")
  var fire_steps := int(ceil(o.fire_t/DT))
  step(o,fire_steps-1)
  ok(e.hp==1000000.0 and o.ammo[0]==2,"damage/charge wait for actual fire event")
  step(o,2)
  ok(e.hp<1000000.0 and o.ammo[0]==1 and o.atk_n==1,"one fire event consumes exactly one charge")
  step(o,maxi(0,int(ceil(o.attack_t/DT))-1))
  ok(o.atk_n==1,"no second release before recovery")
  o.on_leave()
  var empty=fresh(rate)
  empty.ammo[0]=1
  empty.update(DT)
  ok(not empty.acting() and empty.ammo[0]==1,"no target before startup preserves charge")
  var dying=target(empty)
  empty.cd=0.0
  empty.update(DT)
  dying.dead=true
  g.enemies_sys.build_grid()
  step(empty,60)
  ok(empty.ammo[0]==1 and empty.atk_n==0,"target dies during windup: no charge or phantom release")
  empty.on_leave()
func test_matrix() -> void:
 for slot in 3:
  for rate in [1.0,2.0,4.0]:
   for leader in [false,true]:
    for manual in [false,true]:
     var o=fresh(rate,leader)
     o.elite=2
     o.cd=1000.0
     o.sp[slot]=o.sp_need(slot)
     if manual:
      ok(o.cast_manual(slot),"manual entry slot%d"%slot)
     else:
      var ge: Dictionary=g.spawner.spawn_enemy("runner",o.pos+Vector2(80,0))   # 10-23 起 S2 / S3、10-25 起 S1 也要射程内有敌人才自动放（docs/151）；放一只近处的敌人
      ge.spd=0.0
      g.enemies_sys.build_grid()
      ok(o.charge_skills(0.0)==slot,"automatic entry slot%d"%slot)
      o.update(0.0)
     if slot>0:
      ok(o.s_t[slot]==0.0 and o.fire_t>0.0,"duration starts at release, not cast")
     step(o,32)
     ok(o.SkillLifecycle.owns(o,slot),"all skill effect counters have lifecycle owner")
     if slot==0:
      while o.acting(): step(o,1)
      ok(o.ammo[0]==1,"S1 charges through real entry")
      for repeat in 3:
       o.sp[0]=o.sp_need(0)
       o.update(0.0)
      ok(o.ammo[0]==3,"S1 accumulates only to configured cap")
     else:
      ok(o.s_t[slot]>float(o.B.skills[slot].dur)-0.5,"S2/S3 numeric duration retained")
      ok(o.sq_ph==2 and o.anim_state().kind=="skill_s%d_loop"%(slot+1),"startup reaches correct active loop")
      o.ammo[0]=1
      target(o)
      o.cd=0.0
      o.update(DT)
      ok(o.anim_state().kind=="skill_s1_attack","stocked S1 survives active-skill visual variant")
      step(o,60)
      o.cd=0.0
      o.update(DT)
      ok(o.atk_n>=1,"active skill still uses gameplay attack release")
      o.s_t[slot]=0.0
      while o.acting(): step(o,1)
      step(o,1)
      var n: int=o.atk_n
      ok(o.sq_ph==3,"last body action completes before end sequence")
      step(o,15)
      ok(o.atk_n==n,"no new attack during end sequence")
      o.cd=1000.0
      step(o,30)
      ok(o.sq_ph==0,"end returns to normal")
     # Queued tentacles and growing entities are owned, not global projectiles.
     o.hw.mz.delayed.append({"at":100.0})
     o.hw.mz.stakes.append({"t":100.0})
     o.hw.mz.s3_fx=0.3
     o.manual_buf=1.0
     o.on_leave()
     ok(o.fire_t<0.0 and not o.acting() and o.manual_buf==0.0,"leave clears pending fire and buffered skill")
     ok(o.ammo[0]==0 and o.s_t[slot]==0.0 and o.lifecycle.is_empty(),"leave cancels owned counters")
     ok(o.hw.mz.delayed.is_empty() and o.hw.mz.stakes.is_empty() and o.hw.mz.s3_fx==0.0,"leave clears dependent effects")
     o.sp[slot]=o.sp_need(slot)
     o.start_skill(Vector2.INF,slot)
     o.on_leave()
     step(o,40)
     ok(o.s_t[slot]==0.0 and o.ammo[0]==0,"redeploy then startup cancel has no residual release")
func test_growth() -> void:
 var o=fresh()
 o.elite=2
 o.cd=1000.0
 var e=target(o)
 e.hp=e.maxhp*.4
 o._sustain(0.0)
 var damage: float=o._dmg_bonus()
 e.hp=e.maxhp
 ok(damage>o._dmg_bonus(),"elite low-HP talent still scales damage")
 o.hw.mz.budget=0.0
 o.update(.1)
 ok(absf(o.hw.mz.budget-.005)<.00001,"kill-heal budget ticks once")
 ok(o.hw.mz.jel.size()>=1,"elite jelly state still advances")
 g.stats.add(&"mizuki_umbrella_area","add",.2,"mizuki_growth_test","op:mizuki")
 g.stats.add(&"mizuki_tentacle_targets","add",1.0,"mizuki_growth_test","op:mizuki")
 o.refresh_stats()
 o.sync_stats(g.stats)
 ok(o.hw.mz.st.area>1.1 and o.hw.mz.st.t_n>=2.0,"growth stats reach umbrella and tentacle helpers")
 o.update(.01)
 ok(o.hw.mz.jel.size()>=2,"growth expands jelly pool")
 g.stats.remove_source("mizuki_growth_test")
 o.on_leave()
func test_timing_validation() -> void:
 var spec: Dictionary=Ch.load_def("mizuki").sprites.attack.duplicate(true)
 ok(Ch.valid_attack_timing(spec),"bounded timing validates")
 for key in ["min_duration","min_rest"]:
  var bad=spec.duplicate(true)
  bad.attack_timing[key]=-0.1
  ok(not Ch.valid_attack_timing(bad),"negative timing bound rejected")
 var bad=spec.duplicate(true)
 bad.attack_timing.min_duration=99.0
 ok(not Ch.valid_attack_timing(bad),"minimum above duration rejected")

func test_overlap() -> void:
 var o=fresh()
 o.elite=2
 o.cd=1000.0
 for slot in [2,1]:
  o.sp[slot]=o.sp_need(slot)
  o.start_skill(Vector2.INF,slot)
  step(o,32)
 o.s_t[1]=0.0
 step(o,40)
 ok(o.s_t[2]>0.0 and o.sq_i==2 and o.sq_ph==2,"remaining S3 resumes after overlapping S2 end")
 o.on_leave()

func test_without_textures() -> void:
 var o=fresh()
 target(o)
 for key in o.def.sprites:
  var value=o.def.sprites[key]
  if value is Dictionary and value.has("tex"):
   value.tex="missing_mizuki_test"
 o.cd=0.0
 o.update(0.0)
 ok(o.fire_t>0.0 and o.atk_n==0,"missing texture retains gameplay attack anticipation")
 o.on_leave()
 o.elite=2
 o.cd=1000.0
 o.start_skill(Vector2.INF,1)
 ok(o.sq_ph==1 and o.fire_t>0.0 and o.s_t[1]==0.0,"missing texture retains sequence release timing")
 o.on_leave()

func test_s3_fx() -> void:
 var fx=load("res://scripts/characters/mizuki_s3_fx.gd")
 ok(fx.state(14.0,14.0,0.0).fade==0.0,"S3 visual enters at actual activation")
 ok(fx.state(13.5,14.0,0.0).fade==1.0,"S3 visual follows duration")
 ok(fx.state(0.0,14.0,0.0).fade==0.0,"S3 visual stops at expiry")
 ok(fx.state(5.0,14.0,0.0).pulse==0.0,"S3 quiet tips do not fake hits")
 ok(fx.state(5.0,14.0,0.3).frame==0,"S3 attack begins first frame")
 ok(fx.state(5.0,14.0,0.15).frame==3,"S3 attack follows elapsed event time")
 var o=fresh()
 var e=target(o)
 o.start_skill(Vector2.INF,2)
 step(o,20)
 o.cd=0.0
 var seen := false
 for i in 120:
  step(o,1)
  if float(o.hw.mz.s3_fx)>0.0:
   seen=true
   ok(e.hp<1000000.0,"S3 area visual follows real combat event")
   break
 ok(seen,"S3 area attack generates visual pulse")
 o.on_leave()
 ok(float(o.hw.mz.s3_fx)==0.0,"leave clears S3 visual pulse")

func test_s3_original() -> void:
 var o=fresh()
 o.s_t[2]=14.0
 var enemies := []
 for i in 8:
  var e: Dictionary=g.spawner.spawn_enemy("runner",o.pos+Vector2.from_angle(TAU*i/8.0)*100.0)
  e.hp=10000.0+i*100.0
  e.maxhp=e.hp
  e.stun=0.0
  enemies.append(e)
 g.enemies_sys.build_grid()
 var hp: float=g.hp
 g.fx=[]
 o.SegMizuki.h3_umbrella_release(o,o.B.attack)
 for i in enemies.size():
  ok(enemies[i].hp<enemies[i].maxhp,"S3 full centered area hits direction %d"%i)
  ok((enemies[i].stun>0.0)==(i<3),"S3 only lowest three receive extra-hit control %d"%i)
 ok(enemies[0].maxhp-enemies[0].hp>enemies[7].maxhp-enemies[7].hp,"lowest targets receive additional talent damage")
 ok(absf(enemies[0].stun-0.6)<0.001,"S3 selected-target stun is 0.6 seconds")
 ok(g.fx.all(func(f):return not str(f.kind) in ["tentacle","rift","tendril"]),"S3 does not spawn per-target tentacle visuals")
 o.s_t[1]=12.0
 for e in enemies:
  e.hp=e.maxhp
  e.stun=0.0
 o.SegMizuki.h3_umbrella_release(o,o.B.attack)
 ok(enemies.filter(func(e):return e.stun>0.0).size()==3,"S2 overlap does not add a fourth S3 extra target")
 o.hw.mz.st.t_n=2.0
 for e in enemies:
  e.hp=e.maxhp
  e.stun=0.0
 o.SegMizuki.h3_umbrella_release(o,o.B.attack)
 ok(enemies.filter(func(e):return e.stun>0.0).size()==4,"growth base-count increase remains active in S3")
 o.hw.mz.st.t_n=1.0
 o.s_t[2]=0.0
 for e in enemies:
  e.hp=e.maxhp
  e.stun=0.0
 o.SegMizuki.h3_umbrella_release(o,o.B.attack)
 ok(enemies.any(func(e):return e.stun>=float(o.base("s2_bind",0.0))),"S2 binding duration is preserved")
 o.s_t[2]=14.0
 ok(o.hw.mz.delayed.is_empty(),"S3 no longer queues echo damage")
 ok(g.hp==hp,"S3 does not charge HP")
 for e in enemies:e.dead=true
 g.enemies_sys.build_grid()
 o.SegMizuki.h3_umbrella_release(o,o.B.attack)
 ok(g.hp==hp,"S3 zero targets does not charge HP")
 var inside=target(o)
 var outside: Dictionary=g.spawner.spawn_enemy("runner",o.pos+Vector2(260,0))
 outside.hp=1000000.0
 outside.maxhp=outside.hp
 g.enemies_sys.build_grid()
 o.SegMizuki.h3_umbrella_release(o,o.B.attack)
 ok(inside.hp<1000000.0 and outside.hp==1000000.0,"S3 extra hits stay inside actual area")
 ok(absf(o.hw.mz.s3_fx_radius-o.SegMizuki.h3_umb_radius(o,o.B.attack))<0.001,"area FX receives actual radius")
 o.on_leave()
