## 小怪行为（从 game.gd 拆出）：按 data/enemies.json 的字段分派，不再按 type 名硬编码。
##   pattern: burrow 潜行破土咬击 / stomp 踏地震荡 / dash 蓄力冲刺 / acid 站桩吐酸 / nova 蓄力环形弹幕
##   远程：shot_n 弹数、shot_kind 弹种、shot_home 追踪、shot_spd 弹速、spit 抛射（落点预警）、spawn_on_shot 射击时召唤
## 状态仍在 game.gd 的敌人字典里，本文件通过 g 访问；Boss 招式见 boss_ai.gd。
extends RefCounted

const D = preload("res://scripts/data.gd")

var g  # Game (Node2D)


func _init(game) -> void:
	g = game


func def_of(e: Dictionary) -> Dictionary:
	return D.ENEMIES.get(e.type, {})


## 小怪的攻击模式（返回额外速度；返回 INF 表示走常规 AI）
func pattern(e: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	var d := def_of(e)
	match d.get("pattern", ""):
		"burrow":
			return _burrow(e, d, dir, dist, dt, spd)
		"stomp":
			return _stomp(e, d, dist)
		"dash":
			return _dash(e, d, dir, dist, dt, spd)
		"acid":
			return _acid(e, d, dir, dist, dt)
		"nova":
			return _nova(e, d, dist, dt)
	return Vector2.INF


## 潜行接近（半伤、不接触），近身后破土咬击，露头 up_time 秒再潜回
func _burrow(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	if e.get("under", true):
		e.under = true
		e.def = 1.0
		if dist < float(d.get("burrow_range", 84)) and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0:
			e.under = false
			e.def = 1.0
			e.up_t = float(d.get("up_time", 3.2))
			g.bai._warn(e, "circle", 0.6, {"follow": true, "r": 50.0, "act": "bite", "col": Color(0.8, 0.5, 1.0), "dmg": e.dmg * 1.3})
			g._sparks(e.pos, Vector2.UP, Color(0.5, 0.4, 0.7), 10, 200.0)
			return Vector2.ZERO
		return dir * spd
	e.up_t = e.get("up_t", 3.0) - dt
	if e.up_t <= 0.0 and dist > 120.0:
		e.under = true
		g._sparks(e.pos, Vector2.DOWN, Color(0.5, 0.4, 0.7), 8, 160.0)
	return Vector2.INF


## 近身时踏地震荡
func _stomp(e: Dictionary, d: Dictionary, dist: float) -> Vector2:
	if dist < float(d.get("stomp_range", 170)) and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and g.bai._cd(e, "stomp", float(d.get("stomp_cd", 6.0))):
		g.bai._warn(e, "circle", 0.9, {"follow": true, "r": float(d.get("stomp_r", 135)), "act": "slam", "col": Color(1.0, 0.8, 0.5), "dmg": e.dmg * 1.2})
	return Vector2.INF


## 蓄力 dash_wind 秒后高速冲刺
func _dash(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	e["dash_cd"] = e.get("dash_cd", g.rng.randf_range(1.5, 3.5)) - dt
	if e.get("dash_w", 0.0) > 0.0:
		e.dash_w -= dt
		if e.dash_w <= 0.0:
			e["dash_t"] = 0.35
		return Vector2.ZERO
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t -= dt
		return e.dash_dir * spd * float(d.get("dash_speed", 3.8))
	if e.dash_cd <= 0.0 and dist < float(d.get("dash_range", 240)) and dist > 40.0:
		e.dash_cd = g.rng.randf_range(3.0, 4.5)
		e["dash_w"] = float(d.get("dash_wind", 0.5))
		e["dash_dir"] = dir
		return Vector2.ZERO
	return Vector2.INF


## 站桩吐酸
func _acid(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float) -> Vector2:
	e.cdt -= dt
	if e.cdt <= 0.0 and dist < float(d.get("acid_range", 300)):
		e.cdt = float(d.get("acid_cd", 4.2))
		g.ebullets.append({"pos": e.pos, "vel": dir * 150.0, "dmg": 5.0 * (1.0 + g.t / 300.0), "slow": false, "r": 5.0, "life": 2.6,
			"corrode": 0.3, "nerve": 0.0, "true": false, "kind": "acid", "home": false})
	return Vector2.INF


## 发光蓄力后环形弹幕
func _nova(e: Dictionary, d: Dictionary, dist: float, dt: float) -> Vector2:
	e["nova_cd"] = e.get("nova_cd", g.rng.randf_range(2.0, 4.0)) - dt
	if e.get("nova_w", 0.0) > 0.0:
		e.nova_w -= dt
		if e.nova_w <= 0.0:
			var n: int = int(d.get("nova_n", 6)) + (2 if e.evo else 0)
			for k in n:
				g.ebullets.append({"pos": e.pos, "vel": Vector2.from_angle(TAU * k / n + e.id) * 150.0, "dmg": e.dmg * 0.3, "slow": false,
					"r": 5.0, "life": 2.6, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "nova", "home": false})
			Sfx.play("tentacle", -12.0, 0.7, 0.05)
		return Vector2.ZERO
	if e.nova_cd <= 0.0 and dist < float(d.get("nova_range", 320)):
		e.nova_cd = g.rng.randf_range(4.0, 5.5)
		e["nova_w"] = 0.6
		return Vector2.ZERO
	return Vector2.INF


## 远程攻击（小怪按表；Boss 的弹数 / 弹种分支保留在这里，等 Boss 表数据化时再迁）
func shoot(e: Dictionary, dir: Vector2) -> void:
	var d := def_of(e)
	if d.get("spit", false) or d.get("lob", false):
		lob(e)
		return
	var spd: float = float(d.get("shot_spd", 280.0 if e.boss else 200.0))
	var n: int = int(d.get("shot_n", 1))
	var kind: String = d.get("shot_kind", "orb")
	var home: bool = d.get("shot_home", false)
	if e.type == "ishar" and e.phase == 2:
		n = 3
	if e.type == "paranoia":
		n = 3 if e.phase == 1 else 5
	if e.type == "iberia":
		n = 5
	if e.has("ammo"):
		e.ammo -= 1
		if e.ammo <= 0:
			e.ai = "melee"
			g._add_text(e.pos + Vector2(0, -40), "弹药耗尽", Color(1.0, 0.8, 0.5), 14)
	for k in n:
		var dk := dir.rotated((k - (n - 1) / 2.0) * 0.22)
		g.ebullets.append({"pos": e.pos, "vel": dk * spd, "dmg": e.dmg * (0.7 if e.boss else 0.45) * (2.0 if e.has("ammo") else 1.0),
			"slow": e.type == "paranoia", "r": 7.0 if e.boss else 5.0, "life": 2.0 if not home else 3.5,
			"corrode": e.corrode, "nerve": 0.0, "true": e.type == "ishar" and e.phase == 2, "kind": kind, "home": home, "atk": d.get("atk", "法术"),
			"mire": e.type == "paranoia" and e.phase == 2})
	# 射击时召唤（投嗣育母：在水月附近放下注亡拟嗣，场上上限 spawn_max）
	var so: String = d.get("spawn_on_shot", "")
	if so != "":
		var nb := 0
		for o in g.enemies:
			if o.type == so and not o.dead:
				nb += 1
		if nb < int(d.get("spawn_max", 12)):
			g._spawn_enemy(so, g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(45.0, 75.0))


## 抛射碎石：落点预警，落地范围伤害（spit 的落点留下溟痕）
func lob(e: Dictionary) -> void:
	var to: Vector2 = g.ppos + Vector2(randf_range(-30, 30), randf_range(-30, 30)) + g.pvel * 0.6
	g.lobs.append({"from": e.pos, "to": to, "t": 0.0, "dur": 1.0, "r": 46.0, "dmg": e.dmg * 0.6, "mire": def_of(e).get("spit", false)})
