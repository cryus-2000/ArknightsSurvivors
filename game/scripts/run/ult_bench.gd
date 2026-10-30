## 终结技对齐测试场景 ult_bench（docs/198 §3.4）：--balance --ultbench --op=<队长>（无头）。
## 时间锁 5:00 的敌人倍率；队长在场景中心不动、无敌、攻击力 0（只量终结技本身：伤害从 e.ult_d 读，普攻 / 技能打不出伤害）；
## 桌面参考视野 1524 × 857 内均匀摆 120 只普通小怪（每 10 只 1 只重型）、3 只精英（200 / 350 / 500，分在默认瞄准方向两侧）、
## 1 只中期 Boss（420，只测伤害）；敌人不移动、不攻击。瞄准 4 个方向（右、右上 45°、上、敌群最密处）各放一次。
## --ultbench=cluster：同样 120 只聚成 3 团（§3.4 第二场景，查聚怪时的上限）。
## 每次打印 ULTBENCH {…}，最后打印 ULTBENCH_AVG {…} 并退出。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const NORMAL := "fractal"
const HEAVY := "offspring"
const ELITE := "skimmer"
const BOSS := "bishop"
const AIMS := [0.0, -PI / 4.0, -PI / 2.0, INF]   # 右 / 右上 / 上 / 最密处

var g
var cluster := false
var _f := 0
var _trial := -1
var _stage := ""
var _wait := 0.0
var _set: Array = []
var _t_press := 0.0
var _peak := 0
var rows: Array = []


func _init(game, arg: String) -> void:
	g = game
	cluster = arg == "cluster"


## autotest.step 每帧调（--ultbench 时只走这里）
func step() -> void:
	_f += 1
	if g.state != g.S.PLAY:
		if g.state == g.S.SHOW or g.panel.visible:
			g.state = g.S.PLAY   # 开局演出 / 选卡面板：直接回到战斗
		return
	if _f < 20:
		return
	if _trial < 0:
		_setup_once()
		_trial = 0
		_stage = "spawn"
	match _stage:
		"spawn":
			_spawn()
			_wait = 0.0
			_stage = "settle"
		"settle":
			_wait += 1.0 / 60.0
			if _wait >= 1.0:
				_press()
				_stage = "run"
		"run":
			g.hp = g.max_hp
			_peak = maxi(_peak, g.ult.shapes.size())
			if g.ult.phase == "":
				_wait = 0.0
				_stage = "tail"
		"tail":
			_wait += 1.0 / 60.0
			if _wait >= 0.6:
				_measure()
				_trial += 1
				if _trial >= AIMS.size():
					_stage = "done"
					_finish()
				else:
					_stage = "spawn"


func _setup_once() -> void:
	g.sandbox = true   # 不刷怪（game._update 跳过 spawner）
	if g.stats.has_stat(&"op_atk"):
		g.stats.set_base(&"op_atk", 0.0)
	if g.stats.has_stat(&"xp_gain"):
		g.stats.set_base(&"xp_gain", 0.0)   # 不升级、不弹选卡
	g.sync_stats()


func _clear() -> void:
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	g.bosses.clear()
	g.final_boss = null
	g.ebullets.clear()


func _spawn() -> void:
	_clear()
	g.t = 300.0
	g.ppos = Vector2.ZERO if g.ppos == Vector2.INF else g.ppos
	var c: Vector2 = g.ppos
	g.invuln = 999.0
	g.hp = g.max_hp
	_set.clear()
	var pts: Array = []
	if cluster:
		var cs := [c + Vector2(330, -120), c + Vector2(-380, 180), c + Vector2(120, 300)]
		for i in 120:
			var cc: Vector2 = cs[i % 3]
			var k: int = i / 3
			pts.append(cc + Vector2.from_angle(k * 2.39996) * 14.0 * sqrt(float(k + 1)))
	else:
		var hx: float = g.ult.VIEW.x * 0.5 - 40.0
		var hy: float = g.ult.VIEW.y * 0.5 - 40.0
		for yi in 10:
			for xi in 12:
				var p := c + Vector2(lerpf(-hx, hx, (xi + 0.5) / 12.0), lerpf(-hy, hy, (yi + 0.5) / 10.0))
				if p.distance_to(c) < 70.0:
					p += Vector2(90.0, 0.0)
				pts.append(p)
	for i in pts.size():
		var e: Dictionary = g.spawner.spawn_enemy(HEAVY if i % 10 == 9 else NORMAL, pts[i])
		_pin(e)
		e["_bk"] = "heavy" if i % 10 == 9 else "normal"
		_set.append(e)
	var ea := [-0.45, 0.45, -0.45]
	var ed := [200.0, 350.0, 500.0]
	for i in 3:
		var e: Dictionary = g.spawner.spawn_enemy(ELITE, c + Vector2.from_angle(ea[i]) * ed[i])
		if not e.elite:
			e.elite = true
			e.hp *= Bal.v("enemy/elite_hp_mult", 7.0)
			e.maxhp = e.hp
		_pin(e)
		e["_bk"] = "elite"
		_set.append(e)
	var b: Dictionary = g.spawner.spawn_enemy(BOSS, c + Vector2.from_angle(0.2) * 420.0)
	_pin(b)
	b["_bk"] = "boss"
	if not b in g.bosses:
		g.bosses.append(b)
	_set.append(b)


func _pin(e: Dictionary) -> void:
	e.spd = 0.0
	e.dmg = 0.0
	e["dormant"] = false


func _press() -> void:
	var u = g.ult
	u.energy = u.FULL
	u.cells = 0
	g.t = 300.0
	_peak = 0
	_t_press = g.t
	u.last_hit_t = -1.0
	u.press_q()
	u.q_held = false
	var a: float = AIMS[_trial]
	var ld = g.squad.leader()
	if a != INF:
		var d := Vector2.from_angle(a)
		u.aim_dir = d
		u.aim = ld.pos + d * 260.0
	# 最密处：保留 ult.gd 的默认光标 / 默认方向


func _measure() -> void:
	var n := {"normal": [0, 0], "heavy": [0, 0]}
	var el: Array = []
	var boss := 0.0
	var inv := false
	for e in _set:
		var bk: String = e._bk
		if bk == "normal" or bk == "heavy":
			n[bk][1] += 1
			if e.dead:
				n[bk][0] += 1
		elif bk == "elite":
			el.append(float(e.get("ult_d", 0.0)) / maxf(1.0, e.maxhp))
		else:
			boss = float(e.get("ult_d", 0.0)) / maxf(1.0, e.maxhp)
			inv = bool(e.get("invuln", false))
	var all_dead: int = n.normal[0] + n.heavy[0]
	var row := {"op": str(g.squad.leader().id), "aim": ["right", "upright", "up", "dense"][_trial], "cluster": cluster,
		"minion": snappedf(100.0 * all_dead / maxf(1.0, n.normal[1] + n.heavy[1]), 0.1),
		"normal": snappedf(100.0 * n.normal[0] / maxf(1.0, n.normal[1]), 0.1), "heavy": snappedf(100.0 * n.heavy[0] / maxf(1.0, n.heavy[1]), 0.1),
		"elite": snappedf(100.0 * _avg(el), 0.1), "boss": snappedf(100.0 * boss, 0.1), "boss_invuln": inv,
		"dur": snappedf(maxf(0.0, g.ult.last_hit_t - _t_press), 0.01), "shapes_peak": _peak}
	rows.append(row)
	print("ULTBENCH ", JSON.stringify(row))


static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()


func _finish() -> void:
	var avg := {"op": rows[0].op, "cluster": cluster}
	for k in ["minion", "normal", "heavy", "elite", "boss", "dur", "shapes_peak"]:
		avg[k] = snappedf(_avg(rows.map(func(r): return r[k])), 0.1 if k != "dur" else 0.01)
	print("ULTBENCH_AVG ", JSON.stringify(avg))
	_clear()
	g.get_tree().quit()
