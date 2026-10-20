extends Node
const LC = preload("res://scripts/characters/blocks/skill_lifecycle.gd")
class Owner:
 extends RefCounted
 var lifecycle := {}
 var sq_i := -1
 var sq_ph := 0
 var ends := []
 func phase_skill_end(i): ends.append(i)
var checks := 0
var failures := 0
func ok(value: bool, label: String):
 checks += 1
 if not value:
  failures += 1
  printerr("FAIL: " + label)
func _ready():
 var o := Owner.new()
 var source := {"remaining": 3.0}
 LC.bind(o, "independent", 0, source, "remaining", true, true)
 ok(LC.left(o, 0) == 3.0 and LC.left(o, 2) == -1.0, "state follows S1, not fixed S3")
 ok(LC.occupied(o), "count capability owns skill channel")
 source.remaining = 1.0
 ok(LC.left(o, 0) == 1.0, "no copied counter")
 source.remaining = 0.0
 o.sq_i = 0
 o.sq_ph = 3
 LC.tick(o)
 ok(o.ends.is_empty(), "exclusive end waits for sequence recovery")
 ok(LC.occupied(o), "recovery keeps ownership")
 o.sq_ph = 0
 LC.tick(o)
 ok(o.ends == [0] and LC.owns(o, 0), "end frame keeps the entry so legacy end paths stay suppressed")
 LC.tick(o)
 ok(o.ends == [0], "natural end once")
 ok(LC.left(o, 0) == -1.0 and not LC.owns(o, 0) and o.lifecycle.is_empty(), "ended effects are removed after recovery (docs/108 F3)")
 ok(not LC.occupied(o), "recovery releases ownership")
 source.remaining = 5.0
 LC.bind(o, "independent", 2, source, "remaining", false, false)
 ok(LC.left(o, 0) == -1.0, "refresh transfers ownership away from old slot")
 ok(LC.left(o, 2) == -1.0 and LC.remaining(o, 2) == 5.0, "background timer does not block recast")
 source.remaining = 8.0
 LC.bind(o, "independent", 2, source, "remaining", false, false)
 ok(o.ends == [0] and LC.remaining(o, 2) == 8.0, "refresh replaces owner without end")
 LC.cancel(o)
 ok(source.remaining == 0.0 and o.lifecycle.is_empty(), "cancel clears authoritative state")
 ok(o.ends == [0], "cancel does not dispatch natural end")
 source.remaining = 2.0
 LC.bind(o, "independent", 1, source, "remaining", true, false)
 ok(LC.left(o, 1) == 2.0, "redeploy can bind same source")
 var combined := Owner.new()
 var counters := {"background":1.0,"exclusive":1.0}
 LC.bind(combined,"a",1,counters,"background",false,false)
 LC.bind(combined,"b",1,counters,"exclusive",true,true)
 counters.background = 0.0
 counters.exclusive = 0.0
 combined.sq_i = 1
 combined.sq_ph = 3
 LC.tick(combined)
 ok(combined.ends.is_empty(),"background end cannot bypass another effect recovery")
 combined.sq_ph = 0
 LC.tick(combined)
 LC.tick(combined)
 ok(combined.ends == [1],"composed skill dispatches once after all effects finish")
 LC.tick(combined)
 ok(not LC.owns(combined, 1) and LC.left(combined, 1) == -1.0, "composed effects are removed together")
 LC.cancel(combined)
 await integration()
 print("SKILL LIFECYCLE checks=%d failures=%d" % [checks,failures])
 get_tree().quit(0 if failures == 0 else 1)

func integration():
 var g = load("res://game.tscn").instantiate()
 add_child(g)
 await get_tree().process_frame
 g.set_process(false)
 var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data_ops/attack_phases_fixture.json"))
 definition.id = "lifecycle_fixture"
 definition.name = "Lifecycle fixture"
 definition.sprites.erase("skills")
 definition.blocks.skills = [
  {"dur":0,"do":[{"verb":"calc_field","dur":0.1}]},
  {"dur":{"next_attacks":2},"do":[]},
  {"dur":0,"do":[{"verb":"saria_heal","pct":0,"hot":{"dur":0.1,"pct":0.01}}]}]
 var Fixture = load("res://tests/data_ops/attack_phases_fixture.gd")
 for rate in [1.0,2.0,4.0]:
  for leader in [false,true]:
   for manual in [false,true]:
    var o = Fixture.new(g,definition)
    o.pos = g.ppos
    o.is_leader = leader
    o.elite = 2
    o.sp = [-10000.0,-10000.0,-10000.0]
    g.stats.remove_source("lifecycle_test")
    g.stats.add(&"op_aspd","override",rate,"lifecycle_test","op:lifecycle_fixture")
    o.refresh_stats()
    for e in g.enemies: e.dead = true
    g.enemies = []
    var enemy: Dictionary = g.spawner.spawn_enemy("runner",o.pos+Vector2(50,0))
    enemy.dead = true
    g.enemies_sys.build_grid()
    o.sp[0] = o.sp_need(0)
    if manual:
     ok(o.cast_manual(0,Vector2.LEFT),"manual gate starts cross-slot field")
    else:
     ok(o.charge_skills(0.0)==0,"automatic gate selects cross-slot field")
     o.start_skill(Vector2.INF,0)
    o._release_skill()
    o.attack_t = 0.0
    o.fire_t = -1.0
    o.sp[0] = -10000.0
    ok(o.skill_active_left(0) > 0.0 and o.skill_active_left(2) == 0.0,"calc capability follows moved slot without targets")
    ok(o.skill_effect_status(0)[0].unit == "seconds","effect exposes timer unit")
    o.on_leave()
    ok(o.skill_active_left(0) == 0.0 and o.lifecycle.is_empty(),"leave cancels source state")
    o.pos = g.ppos
    o.cur_skill = 0
    o._release_skill()
    o.cd = 1000
    for k in 8: o.update(1.0/60)
    ok(o.ends == 1,"redeployed field ends exactly once")
    o.cur_skill = 2
    o._release_skill()
    ok(o.skill_active_left(2)==0.0 and not o.skills_occupied(),"hot permits recast and ordinary attacks")
    ok(o.skill_effect_status(2)[0].active and o.skill_effect_status(2)[0].background,"hot remains visible as active background effect")
    o._release_skill()
    for k in 8: o.update(1.0/60)
    ok(o.ends == 2,"refresh emits one eventual end")
    o.cur_skill = 1
    o._release_skill()
    ok(o.ammo[1] == 2 and o.skill_effect_status(1)[0].unit == "attacks","next attacks use shared status")
    o.ammo[1] = 0
    LC.tick(o)
    LC.tick(o)
    ok(o.ends == 3,"counts end once")
    o.on_leave()
    o = null
 # Permanent state uses the same bound array and must not occupy actions.
 var p = Fixture.new(g,definition)
 p.pos = g.ppos
 p.B.skills[1] = {"dur":"permanent","do":[]}
 p.cur_skill = 1
 p._release_skill()
 ok(p.perm_on[1] and not p.skills_occupied(),"permanent does not lock skills")
 ok(p.skill_effect_status(1)[0].unit == "permanent","permanent status is explicit")
 p.on_leave()
 ok(not p.perm_on[1] and not p.perm[1],"permanent clears for redeployment")
 p = null
 # Same adapters on another slot and an unrelated fixture identity.
 var moved = Fixture.new(g,definition)
 moved.pos = g.ppos
 moved.elite = 2
 moved.sp = [-10000.0,-10000.0,-10000.0]
 var adapter = load("res://scripts/characters/blocks/seg_skalter.gd")
 moved.B.skills[0] = {"dur":0,"do":[{"_tag":"verb.cannon_load","n":2}]}
 moved.cur_skill = 0
 moved._release_skill()
 ok(moved.skill_active_left(0)==2.0 and moved.skill_active_left(2)==0.0,"cannon loading follows S1 with dead target")
 ok(moved.skills_occupied(),"loaded counts own channel")
 LC.cancel(moved)
 moved._sq_clear()
 moved.B.skills[1] = {"dur":0,"do":[{"_tag":"verb.fox_cast","haze":0.2}]}
 moved.cur_skill = 1
 moved._release_skill()
 ok(moved.skill_active_left(1)==0.2 and moved.skill_active_left(2)==0.0,"haze follows S2")
 moved.on_leave()
 ok(moved.skill_active_left(1)==0.0,"haze cancellation clears source")
 # Instant next-attack path must register, including a refresh after depletion.
 moved.B.skills[2] = {"cast":"instant","dur":{"next_attacks":3},"do":[]}
 for repeat in 2:
  adapter.hw_instant(moved,2)
  ok(moved.skill_effect_status(2)[0].remaining==3.0,"instant duration binding")
  moved.ammo[2] = 0
  LC.tick(moved)
 ok(moved.ends==2,"instant reactivation ends once each")
 moved.on_leave()
 moved = null
 real_matrix(g,Fixture)
 g.queue_free()

func advance(o, frames: int) -> void:
 for k in frames:
  o.follow(1.0/60,o.pos)
  o.cd = 1000.0
  o.update(1.0/60)

func cast_real(o, slot: int, manual: bool, dying: Dictionary = {}) -> void:
 o.sp = [-10000.0,-10000.0,-10000.0]
 o.sp[slot] = o.sp_need(slot)
 o.cd = 1000.0
 if manual:
  ok(o.cast_manual(slot,Vector2.LEFT),"real manual entry %s S%d" % [o.id,slot+1])
 else:
  ok(o.charge_skills(0.0)==slot,"real automatic entry %s S%d" % [o.id,slot+1])
  o.update(0.0)
 if not dying.is_empty():
  dying.dead = true
  o.g.enemies_sys.build_grid()
 for k in 120:
  if not o.acting() and o.fire_t < 0.0:
   break
  advance(o,1)
 o.sp = [-10000.0,-10000.0,-10000.0]

func active_status(o, slot: int) -> bool:
 for effect in o.skill_effect_status(slot):
  if effect.active: return true
 return false

func real_matrix(g, Fixture) -> void:
 for id in ["wisadel","saria","suzuran"]:
  var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/%s.json" % id))
  for slot in 3:
   # Pairwise acceptance: normal/live, high speed/live, manual/empty, ally/dies before release.
   for mode in 4:
    var o = Fixture.new(g,definition)
    o.pos = g.ppos
    o.is_leader = mode != 3
    o.elite = 2
    g.stats.remove_source("real_lifecycle_rate")
    g.stats.add(&"op_aspd","override",4.0 if mode==1 else 1.0,"real_lifecycle_rate","op:"+id)
    o.refresh_stats()
    g.hp = g.max_hp*0.1
    for e in g.enemies: e.dead = true
    g.enemies = []
    g.bullets = []
    var enemy: Dictionary = {}
    if mode != 2:
     enemy = g.spawner.spawn_enemy("runner",o.pos+Vector2(90,0))
     enemy.hp = 1000000.0
     enemy.max_hp = enemy.hp
    g.enemies_sys.build_grid()
    var before_hp: float = g.hp
    cast_real(o,slot,mode==2,enemy if mode==3 else {})
    var label := "%s S%d case%d" % [id,slot+1,mode]
    if id=="saria" and slot==0:
     ok(g.hp>before_hp and not active_status(o,slot),label+" instant heal")
    else:
     ok(active_status(o,slot),label+" effect actually active")
    if slot==0 and id in ["wisadel","suzuran"]:
     var count: int = 3 if id=="wisadel" else 1
     ok(o.ammo[0]==count,label+" actual instant/manual activation stores charges")
     # No target before startup never consumes a charge.
     for e in g.enemies: e.dead = true
     g.enemies_sys.build_grid()
     o.cd = 0.0
     o.update(1.0/60)
     ok(o.ammo[0]==count and not o.acting(),label+" empty field retains stored charge")
     var live: Dictionary = g.spawner.spawn_enemy("runner",o.pos+Vector2(90,0))
     live.hp = 1000000.0
     live.max_hp = live.hp
     g.enemies_sys.build_grid()
     o.cd = 0.0
     o.update(1.0/60)
     ok(o.acting() and o.ammo[0]==count,label+" startup does not consume charge")
     if mode==3:
      live.dead = true
      g.enemies_sys.build_grid()
     for k in 100:
      if o.fire_t < 0.0: break
      advance(o,1)
     var expected: int = count if id=="wisadel" and mode==3 else count-1
     ok(o.ammo[0]==expected,label+" release consumes once with legacy target-death semantics")
    o.on_leave()
    ok(not o.skills_occupied() and o.fire_t<0.0 and o.manual_buf==0.0,label+" active cancel clears action owner")
    ok(not active_status(o,slot) and not o.perm[slot] and not o.perm_on[slot],label+" active cancel clears owned effect")
    # Same instance redeploy and a real unreleased skill start, without zeroing action timers.
    o.sp[slot] = o.sp_need(slot)
    o.start_skill(Vector2.INF,slot)
    ok(o.acting(),label+" redeploy can start")
    o.on_leave()
    o.sp = [-10000.0,-10000.0,-10000.0]
    advance(o,90)
    ok(not active_status(o,slot) and not o.skills_occupied(),label+" cancelled startup stays cancelled after follow/update")
    o.on_leave()
    o = null
 # Actual permanent warm -> haze -> natural expiry: retain warm and unrelated modifier.
 var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/suzuran.json"))
 var fox = Fixture.new(g,d)
 fox.pos = g.ppos
 fox.elite = 2
 g.enemies = []
 g.enemies_sys.build_grid()
 g.stats.add(&"op_atk","add",0.123,"lifecycle_unrelated","op:wisadel")
 cast_real(fox,1,false)
 var warm: float = field_bonus(g,"blk4:suzuran:field")
 ok(warm>0.0 and fox.perm_on[1],"real warm permanent field starts")
 cast_real(fox,2,false)
 ok(field_bonus(g,"blk4:suzuran:field")>warm,"real haze overrides warm buff")
 advance(fox,1000)
 ok(absf(field_bonus(g,"blk4:suzuran:field")-warm)<0.00001 and fox.perm_on[1],"natural haze expiry restores warm source")
 fox.on_leave()
 ok(field_bonus(g,"blk4:suzuran:field")==0.0 and absf(field_bonus(g,"lifecycle_unrelated")-0.123)<0.00001,"leave removes only own buff source")
 ok(not fox.perm[1] and not fox.perm_on[1],"real warm can activate after redeploy")
 cast_real(fox,1,false)
 ok(fox.perm_on[1],"real warm redeploy activation")
 fox.on_leave()
 g.stats.remove_source("lifecycle_unrelated")
 fox = null

func field_bonus(g, source: String) -> float:
 var total := 0.0
 for modifier in g.stats._mods.get(&"op_atk",[]):
  if modifier.source==source and modifier.scope=="op:wisadel":
   total += float(modifier.value)
 return total
