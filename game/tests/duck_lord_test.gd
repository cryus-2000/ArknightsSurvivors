extends Node
## 鸭爵（run/duck_lord.gd，docs/216 §11）：出现窗口、不动刷怪随机流、受击加速封顶低于队长、30 秒溜走不掉落、打倒必掉藏品 + 源石锭、关掉不出。
## 只经 tools/godot_runner.py 启动。
const Bal = preload("res://scripts/core/balance.gd")
var game: Node
var frames := 0
var failures := 0
var checks := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)


func chests() -> Array:
	return game.gems.filter(func(gm): return not gm.dead and gm.kind == "chest")


func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var duck = game.duck
	# 出现窗口（对局种子定）
	game.t = 1.0
	duck.update(0.0)
	check(duck.plan.size() == 2, "two appearances planned")
	check(float(duck.plan[0]) >= Bal.v("duck/t1_lo", 0) and float(duck.plan[0]) <= Bal.v("duck/t1_hi", 0), "first window 3-6 min: %s" % str(duck.plan))
	check(float(duck.plan[1]) >= Bal.v("duck/t2_lo", 0) and float(duck.plan[1]) <= Bal.v("duck/t2_hi", 0), "second window 8-12 min")
	check(duck.alive().is_empty(), "no duck before window")
	# 出现：不动 rng_spawn
	var st: int = game.rng_spawn.state
	game.t = float(duck.plan[0])
	duck.update(0.0)
	var e: Dictionary = duck.alive()
	check(not e.is_empty(), "duck spawns at first time")
	check(game.rng_spawn.state == st, "spawn does not consume rng_spawn")
	var off: Vector2 = (e.pos - game.ppos).abs()
	var half: Vector2 = game.view_size() * 0.5
	check(off.x <= half.x + 1.0 and off.y <= half.y + 1.0 and (off.x > half.x * 0.6 or off.y > half.y * 0.6), "spawns near screen edge, inside view")
	check(float(e.dmg) == 0.0 and not e.elite and not e.boss, "duck does not attack, not elite / boss")
	# 逃跑：远离队长
	var d0: float = e.pos.distance_to(game.ppos)
	for i in 30:
		game.t += 1.0 / 30.0
		game.enemies_sys.update(1.0 / 30.0)
	check(e.pos.distance_to(game.ppos) > d0 + 50.0, "runs away from leader")
	# 受击加速：叠层、封顶、低于队长移速
	var base: float = duck.speed(e)
	check(is_equal_approx(base, Bal.v("duck/spd", 0)), "base speed")
	game.combat.damage(e, 0.01, game.combat.make_hit("援护"))
	check(duck.speed(e) > duck.tier_speed(e) + 100.0 and duck.tier_speed(e) > base, "hit: burst dash on top of a higher tier")
	var t_hit: float = game.t
	game.t += Bal.v("duck/burst_t", 0.45) * 0.5
	var mid: float = duck.burst(e)
	game.t = t_hit + Bal.v("duck/burst_t", 0.45) + 0.01
	check(mid > 0.0 and mid < Bal.v("duck/burst_spd", 0) and duck.burst(e) == 0.0, "burst decays back to tier")
	game.t = t_hit
	game.combat.damage(e, 0.01, game.combat.make_hit("援护"))
	check(e.duck_hits.size() == 1, "hits within hit_gap count once")
	for i in 12:
		game.t += 0.25
		duck.on_hit(e)
	check(duck.tier_speed(e) <= Bal.v("duck/spd_max", 0) + 0.01, "tier speed capped")
	check(Bal.v("duck/spd_max", 999) < duck.chase_speed() and duck.chase_speed() > game.speed, "cap below walk + dash chase speed (catchable with dash)")
	game.t += Bal.v("duck/hit_t", 2.0) + 0.1
	check(is_equal_approx(duck.speed(e), base), "boost expires")
	# 时限到溜走：不掉落、不计击杀
	var c0: int = chests().size()
	var k0: int = game.kills
	game.t = float(e.duck_t0) + Bal.v("duck/flee_t", 30.0) + 0.01
	game.enemies_sys.update(1.0 / 30.0)
	check(e.dead and duck.log.fled == 1, "flees after flee_t")
	check(chests().size() == c0 and game.kills == k0, "fleeing drops nothing")
	# 第二次：打倒必掉藏品 + 源石锭
	game.t = float(duck.plan[1])
	duck.update(0.0)
	var e2: Dictionary = duck.alive()
	check(not e2.is_empty() and not is_same(e2, e), "second appearance")
	var ing0: int = game.gems.filter(func(gm): return not gm.dead and gm.kind == "ingot").size()
	game.combat.kill(e2)
	var cs: Array = chests()
	check(cs.size() == c0 + 1 and str(cs[-1].get("src", "")) == "duck", "kill drops one relic chest (src duck)")
	var ing1: int = game.gems.filter(func(gm): return not gm.dead and gm.kind == "ingot").size()
	check(ing1 - ing0 >= Bal.vi("duck/ingots", 6), "kill drops ingots")
	check(duck.log.killed == 1, "kill logged")
	game.t += 1000.0
	duck.update(0.0)
	check(duck.alive().is_empty() and duck.log.spawned == 2, "only two per run")
	# 关掉：不出
	var sec: Dictionary = Bal.sec("duck")
	sec["on"] = 0
	duck.plan = []
	duck.idx = 0
	game.t = 1.0
	duck.update(0.0)
	game.t = 2000.0
	duck.update(0.0)
	check(duck.alive().is_empty() and duck.log.spawned == 2, "duck/on = 0 spawns nothing")
	sec["on"] = 1
	check(is_equal_approx(Bal.v("relic/elite_drop_chance", 0), 0.2), "elite drop chance compensated to 0.2 (docs/216 §11.4)")
	print("DUCK LORD checks=%d failures=%d" % [checks, failures])
	get_tree().quit.call_deferred(failures)
