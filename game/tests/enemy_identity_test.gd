extends Node
const D = preload("res://scripts/data.gd")
const Seal = preload("res://scripts/characters/blocks/ob_summon.gd")
var g: Node
var frames := 0
var fails := 0
var checks := 0
func _ready() -> void:
 g = load("res://game.tscn").instantiate()
 add_child(g)
func ok(b: bool, label: String) -> void:
 checks += 1
 if not b:
  fails += 1
  printerr("FAIL: ", label)
func spawn(kind: String) -> Dictionary:
 var e: Dictionary = g.spawner.spawn_enemy(kind, g.ppos + Vector2(600, 0))
 e.hp = 10000.0
 e.maxhp = 10000.0
 e.hidden = false
 e.invuln = false
 e.weak = ""
 return e
func hit(e: Dictionary, kind: String) -> float:
 var h: Dictionary = g.hit.duplicate(true)
 h["range"] = "远程"
 h["kind"] = kind
 var hp: float = e.hp
 g.combat.damage(e, 100.0, h)
 return hp - float(e.hp)
func _process(_dt: float) -> void:
 frames += 1
 if frames != 5: return
 set_process(false)
 g.set_process(false)
 var stone := spawn("stone")
 var phys := hit(stone, "物理")
 var arts := hit(stone, "法术")
 var true_hit := hit(stone, "真实")
 stone.set_t = 20.0
 ok(hit(stone, "物理") < phys * 0.8, "entrench reduces physical damage")
 ok(is_equal_approx(hit(stone, "法术"), arts), "entrench does not reduce arts")
 ok(is_equal_approx(hit(stone, "真实"), true_hit), "entrench does not reduce true damage")
 stone.set_t = 0.0
 ok(is_equal_approx(hit(stone, "物理"), phys), "entrench expires without residual armor")
 var tracer := spawn("tracer")
 phys = hit(tracer, "物理")
 tracer.hp = tracer.maxhp * 0.5
 g.eai._thrust(tracer, D.ENEMIES.tracer, Vector2.RIGHT, 600.0, 0.01)
 ok(tracer.enraged, "tracer still enrages")
 ok(hit(tracer, "物理") < phys * 0.8, "tracer hardened at half HP")
 var nest := spawn("nest")
 g.enemies_sys.add_cc(nest, 4.0)
 ok(is_equal_approx(nest.stun, 2.0), "nest stun duration halved")
 var mimic := spawn("mimic")
 g.enemies_sys.add_cc(mimic, 4.0)
 ok(mimic.stun <= 0.0, "mimic stun immunity")
 g.enemies_sys.add_cc(mimic, -INF, 2.0)
 ok(mimic.slow > 0.0, "mimic still susceptible to generic slow")
 var o = g.squad.get_op("sstest")
 Seal.seal_apply(o, mimic, {"dur": 4.0})
 ok(float(mimic.get("seal_t", 0.0)) <= g.t, "mimic seal immunity")
 nest.stun = 0.0
 nest.slow = 0.0
 g.enemies_sys.add_cc(nest, -INF, 2.0, "stop")
 ok(nest.slow == 0.0, "nest immune to stop")
 g.enemies_sys.add_cc(nest, -INF, 2.0)
 ok(is_equal_approx(nest.slow, 2.0), "nest accepts ordinary slow")
 mimic.stun = 0.0
 g.enemies_sys.add_cc(mimic, 2.0, -INF, "airborne")
 ok(is_equal_approx(mimic.stun, 2.0), "mimic still airborne")
 mimic.slow = 0.0
 g.enemies_sys.add_cc(mimic, -INF, 2.0, "cold")
 ok(mimic.slow == 0.0, "mimic cold immunity")
 nest.slow = 0.0
 g.enemies_sys.add_cc(nest, -INF, 2.0, "cold")
 ok(is_equal_approx(nest.slow, 1.0), "nest cold resistance")
 g.enemies = [stone]
 stone.set_done = true
 stone.set_t = 0.1
 stone.stun = 1.0
 stone.weak = "法术"
 g.enemies_sys.update(0.2)
 ok(stone.set_t == 0.0, "entrench expires while stunned")
 ok(stone.weak == D.ENEMIES.stone.get("weak", ""), "expiry restores base weakness")
 test_aura()
 test_pocket()
 print("ENEMY IDENTITY checks=%d failures=%d" % [checks, fails])
 g.enemies = []
 g.final_boss = null
 g.free()
 get_tree().quit(1 if fails else 0)

func aura_hit() -> float:
 g.hp = g.max_hp
 g.invuln = 0.0
 g.shield = 0
 g.lamp = 100.0
 g.enemies_sys.nest_tick = 0.0
 var hp: float = g.hp
 g.enemies_sys.update_nest_aura(0.5, false)
 return hp - float(g.hp)
func test_aura() -> void:
 g.enemies = []
 g.spawner.spawn_chest(g.ppos + Vector2(300, 0))
 g.enemies_sys.update_nest_aura(0.5, false)
 ok(true, "ordinary chests are excluded from aura definitions")
 var a := spawn("nest")
 a.pos = g.ppos + Vector2(30, 0)
 a.stun = 0.0
 a.dmg = 50.0
 var one := aura_hit()
 ok(one > 0.0, "nest aura damages health")
 var b := spawn("nest")
 b.pos = a.pos
 b.stun = 0.0
 b.dmg = a.dmg
 ok(is_equal_approx(aura_hit(), one), "overlapping auras do not stack")
 b.dmg = 100.0
 var two := aura_hit()
 ok(is_equal_approx(two, one * 2.0), "strongest aura wins")
 g.enemies.reverse()
 ok(is_equal_approx(aura_hit(), two), "aura independent of enemy order")
 a.pos = g.ppos + Vector2(600, 0)
 b.pos = a.pos
 ok(aura_hit() == 0.0, "outside aura no damage")
 a.pos = g.ppos
 a["seal_t"] = g.t + 10.0
 ok(aura_hit() == 0.0, "sealed aura stops")
 a["seal_t"] = 0.0
 a.dead = true
 ok(aura_hit() == 0.0, "dead aura stops")
 a.dead = false
 var hp: float = g.hp
 g.enemies_sys.update_nest_aura(0.5, true)
 ok(g.hp == hp, "sanctuary suppresses aura")
 g.invuln = 1.0
 g.enemies_sys.update_nest_aura(0.5, false)
 ok(g.hp == hp, "dash invulnerability suppresses aura")
func test_pocket() -> void:
 g.enemies = []
 var e := spawn("pocket")
 e.spd = 0.0
 e.burst_at = e.maxhp * 0.85
 e.hp = e.maxhp * 0.50
 g.enemies_sys.update(0.1)
 ok(e.burst_w > 0.0, "crossing thresholds starts telegraph")
 var first: float = e.burst_at
 for i in 14:
  g.t += 0.1
  g.enemies_sys.update(0.1)
 ok(is_equal_approx(e.burst_at, first - e.maxhp * 0.15), "large hit queues next threshold after cooldown")
 ok(e.has("burst_fx_t"), "burst has existing visual")
 e.dead = true
 var at: float = e.burst_fx_t
 for i in 20:
  g.t += 0.1
  g.enemies_sys.update(0.1)
 ok(e.burst_fx_t == at, "death cancels pending burst")
