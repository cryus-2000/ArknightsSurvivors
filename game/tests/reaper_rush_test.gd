extends Node
## Reaper wound transition: one scythe pair, accelerated pursuit, bounded nerve ripple.
var g: Node
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	call_deferred("run_checks")

func run_checks() -> void:
	g.set_process(false)
	g.t = 120.0
	g.ppos = Vector2(210, 0)
	var e: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	var base_speed: float = e.spd
	e.hp -= 1.0
	g.eai.pattern(e, Vector2.RIGHT, 210.0, 0.016, base_speed)
	check(e.enraged, "first hit activates reaper rush")
	check(e.spd > base_speed and e.spd <= base_speed * 1.6, "rush speed rises but stays bounded")
	check(e.wake_t > 0.0, "scythes unfold before rush")
	var normal: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	g.eai.pattern(normal, Vector2.RIGHT, 200.0, 0.016, normal.spd)
	check(not normal.dormant and not normal.enraged, "proximity wake does not trigger wounded rush")
	var crowded: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	crowded.dormant = false
	crowded.age = 5.0
	crowded.extra_next = 0.0
	crowded.hp -= 1.0
	g.eai.pattern(crowded, Vector2.RIGHT, 200.0, 0.016, crowded.spd)
	check(crowded.enraged, "wound transition is immediate even when secondary is ready")
	e.wake_t = 0.0
	g.ppos = Vector2(80, 0)
	g.nerve_aura_t = 0.0
	g.eai.pattern(e, Vector2.RIGHT, 80.0, 0.5, e.spd)
	check(g.nerve_aura_t > 0.0, "nearby reaper creates nerve ripple")
	g.nerve_aura_t = 0.0
	g.ppos = Vector2(160, 0)
	g.eai.pattern(e, Vector2.RIGHT, 160.0, 0.5, e.spd)
	check(g.nerve_aura_t == 0.0, "ripple does not damage outside radius")
	# pattern() 开头的受伤分支只在转狂奔那一帧提前 return：狂奔之后「镰肢直刺」（_secondary）照常走得到
	e.wake_t = 0.0
	e.wind = 0.0
	e.age = 5.0
	e.extra_next = 0.0
	g.warns.clear()
	g.ppos = Vector2(200, 0)
	var sv: Vector2 = g.eai.pattern(e, Vector2.RIGHT, 200.0, 0.016, e.spd)
	check(sv == Vector2.ZERO and g.warns.any(func(w): return w.get("secondary", false)), "enraged reaper still uses its secondary pierce")
	# docs/95 §18 临战自身流失：enemy/reaper_rush_drain（缺省 0.04 = 原作每秒 4%），展开镰肢期间不掉，耗尽算死亡并计数
	var Bal = load("res://scripts/core/balance.gd")
	Bal._load()
	if not (Bal._data.get("enemy") is Dictionary):
		Bal._data["enemy"] = {}
	var dr: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	dr.hp -= 1.0
	g.ppos = Vector2(400, 0)
	g.eai.pattern(dr, Vector2.RIGHT, 400.0, 0.016, dr.spd)
	var hp_wake: float = dr.hp
	g.eai.pattern(dr, Vector2.RIGHT, 400.0, 0.2, dr.spd)
	check(is_equal_approx(dr.hp, hp_wake), "no drain while scythes unfold")
	dr.wake_t = 0.0
	Bal._data["enemy"]["reaper_rush_drain"] = 0.0
	var hp0: float = dr.hp
	g.eai.pattern(dr, Vector2.RIGHT, 400.0, 1.0, dr.spd)
	check(is_equal_approx(dr.hp, hp0), "drain 0 keeps old behaviour")
	Bal._data["enemy"].erase("reaper_rush_drain")
	g.eai.pattern(dr, Vector2.RIGHT, 400.0, 1.0, dr.spd)
	check(absf((hp0 - dr.hp) - dr.maxhp * 0.04) < 0.01, "default drain is 4%% max hp per second (%.2f)" % (hp0 - dr.hp))
	var n0: int = g.telemetry.reaper_drain_deaths
	dr.hp = dr.maxhp * 0.01
	g.eai.pattern(dr, Vector2.RIGHT, 400.0, 1.0, dr.spd)
	check(dr.dead and g.telemetry.reaper_drain_deaths == n0 + 1, "drained reaper dies and is counted")
	# docs/96 §2.2 出手特效挂点：warn 带 atk_fx 时结算放帧条（这里借第 1 批已有的 fx_corrode_hit 代替还没交的 fx_reaper_scythe），朝左出手镜像
	var fx_e: Dictionary = g.spawner.new_enemy("reaper", Vector2.ZERO)
	g.enemies.append(fx_e)
	g.invuln = 100.0
	for side in [1.0, -1.0]:
		g.fx.clear()
		var fw: Dictionary = g.bai._warn(fx_e, "cone", 0.8, {"ang": 0.0 if side > 0.0 else PI, "half": 0.9, "r": 145.0, "act": "bite", "dmg": 1.0, "atk_fx": "fx_corrode_hit", "atk_fx_origin": [12, 19]})
		g.bai._warn_resolve(fw)
		var spr: Array = g.fx.filter(func(f): return f.get("kind", "") == "sprite" and f.get("name", "") == "fx_corrode_hit")
		check(spr.size() == 1 and spr[0].get("enemy", false) and bool(spr[0].get("flip", false)) == (side < 0.0), "atk_fx plays on resolve, mirrored when facing left (side %d)" % int(side))
	g.warns.clear()
	g.fx.clear()
	if failures == 0:
		print("PASS: reaper rush")
	get_tree().quit(1 if failures else 0)
