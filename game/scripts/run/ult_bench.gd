## 终结技对齐测试场景 ult_bench（docs/198 §3.4）：--balance --ultbench --op=<队长>（无头）。
## 时间锁 5:00 的敌人倍率；队长在场景中心不动、无敌、攻击力 0（只量终结技本身：伤害从 e.ult_d 读，普攻 / 技能打不出伤害）；
## 桌面参考视野 1524 × 857 内均匀摆 120 只普通小怪（每 10 只 1 只重型）、3 只精英（200 / 350 / 500，分在默认瞄准方向两侧）、
## 1 只中期 Boss（420，只测伤害）；敌人不移动、不攻击。瞄准 4 个方向（右、右上 45°、上、敌群最密处）各放一次。
## --ultbench=cluster：同样 120 只聚成 3 团（§3.4 第二场景，查聚怪时的上限）。
## --ultbench=area：量判定面积（协调人 10-31「统一终结技打击范围」）：队长周围 ±AREA_HX × ±AREA_HY 且半径 AREA_R 以内每 AREA_STEP 一只打不死的普通小怪（血量 × 1e6，
##   终结技小怪预算按基准生命算、与血量无关，所以只掉血不倒），瞄右 / 右上 / 上三次；被打到（e.ult_d > 0）的格数 × 格面积 = 各段判定的并集面积，
##   另报被打到的格的质心离队长多远（形状在身边还是前方）、最远一格多远。招式本身的目标上限（能天使 ult/ex_tgt）照样生效。
## 每行另报 dmg = 本次终结技对场景内全部敌人造成的伤害合计（基准生命的倍数）、hit_n = 被打到的小怪只数。
## --ub_t=秒（均匀 / 聚怪档）：时间锁在这一刻（缺省 300），小怪按 waves.json 这一刻的威胁档刷怪池轮流摆（代替固定的 fractal / offspring），
##   另报 clear = 被打到的小怪里倒下的比例（「范围内清光」口径，协调人 10-31）与各种类的 [倒下, 被打到]。
## 每次打印 ULTBENCH {…}，最后打印 ULTBENCH_AVG {…} 并退出。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const NORMAL := "fractal"
const HEAVY := "offspring"
const ELITE := "skimmer"
const BOSS := "bishop"
const FINAL := "paranoia"
const AIMS := [0.0, -PI / 4.0, -PI / 2.0, INF]   # 右 / 右上 / 上 / 最密处
const AREA_STEP := 40.0
const AREA_HX := 1400.0
const AREA_HY := 1000.0
const AREA_R := 1280.0

var g
var cluster := false
var T0 := 300.0
var pool: Array = []
var area := false
var _f := 0
var _trial := -1
var _stage := ""
var _wait := 0.0
var _set: Array = []
var _t_press := 0.0
var _peak := 0
var rows: Array = []
var _c0 := Vector2.ZERO


func _init(game, arg: String) -> void:
	g = game
	cluster = arg == "cluster"
	area = arg == "area"
	for a in Cfg.dev_args():
		if a.begins_with("--ub_t="):
			T0 = float(a.substr(7))
			var w = JSON.parse_string(FileAccess.get_file_as_string("res://data/waves.json"))
			for tier in w.threat:
				if float(tier.t) <= T0:
					pool = tier.pool


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
				if _trial >= (3 if area else AIMS.size()):
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
	g.t = T0
	g.ppos = Vector2.ZERO if g.ppos == Vector2.INF else g.ppos
	var c: Vector2 = g.ppos
	g.invuln = 999.0
	g.hp = g.max_hp
	_set.clear()
	var pts: Array = []
	if area:
		var nx: int = int(AREA_HX * 2.0 / AREA_STEP)
		var ny: int = int(AREA_HY * 2.0 / AREA_STEP)
		for yi in ny:
			for xi in nx:
				var p := c + Vector2(-AREA_HX + (xi + 0.5) * AREA_STEP, -AREA_HY + (yi + 0.5) * AREA_STEP)
				if p.distance_to(c) > AREA_R:
					continue   # 离队长 1300 以外的敌人会被挪到屏幕边（enemies.gd），格子只摆在圆内
				var e: Dictionary = g.spawner.spawn_enemy(NORMAL, p)
				_pin(e)
				e.hp *= 1e6
				e.maxhp = e.hp
				e["_bk"] = "normal"
				_set.append(e)
		return
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
		var tp: String = str(pool[i % pool.size()]) if not pool.is_empty() else (HEAVY if i % 10 == 9 else NORMAL)
		var e: Dictionary = g.spawner.spawn_enemy(tp, pts[i])
		_pin(e)
		e["_bk"] = "normal" if not pool.is_empty() or i % 10 != 9 else "heavy"
		e["_tp"] = tp
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
	var fin: bool = Cfg.dev_args().has("--ub_final")   # 最终 Boss（偏执泡影）代替中期 Boss，量终结技对最终 Boss 的份额（ult/final）
	var b: Dictionary = g.spawner.spawn_enemy(FINAL if fin else BOSS, c + Vector2.from_angle(0.2) * 420.0)
	_pin(b)
	b["_bk"] = "boss"
	if not b in g.bosses:
		g.bosses.append(b)
	if fin:
		g.final_boss = b
	_set.append(b)


func _pin(e: Dictionary) -> void:
	e["_p0"] = e.pos   # 出生位置（被拉拢 / 击退后仍按原格记面积）
	e.spd = 0.0
	e.dmg = 0.0
	e["dormant"] = false


func _press() -> void:
	var u = g.ult
	u.energy = u.FULL
	u.cells = 0
	g.t = T0
	_peak = 0
	_t_press = g.t
	u.last_hit_t = -1.0
	u.press_q()
	u.q_held = false
	var a: float = AIMS[_trial]
	var ld = g.squad.leader()
	_c0 = ld.pos
	if a != INF:
		var d := Vector2.from_angle(a)
		u.aim_dir = d
		u.aim = ld.pos + d * 260.0
	# 最密处：保留 ult.gd 的默认光标 / 默认方向


func _measure() -> void:
	var ref: float = maxf(1.0, g.ult.ref_hp())
	var dmg := 0.0
	var hit_n := 0
	var cen := Vector2.ZERO
	var far := 0.0
	var in_view := 0
	var c0: Vector2 = _c0   # 按下 Q 时队长的位置（有的招式会位移）
	for e in _set:
		var d: float = float(e.get("ult_d", 0.0)) if int(e.get("ult_s", -1)) == g.ult.serial else 0.0
		dmg += d
		if d > 0.0 and (e._bk == "normal" or e._bk == "heavy"):
			hit_n += 1
			var p: Vector2 = e.get("_p0", e.pos)
			cen += p - c0
			far = maxf(far, p.distance_to(c0))
			if absf(p.x - c0.x) <= g.ult.VIEW.x * 0.5 and absf(p.y - c0.y) <= g.ult.VIEW.y * 0.5:
				in_view += 1
	if area:
		var ar := {"op": str(g.squad.leader().id), "aim": ["right", "upright", "up"][_trial], "area": true,
			"area_k": snappedf(float(hit_n) * AREA_STEP * AREA_STEP / 1000.0, 1.0), "hit_n": hit_n,
			"view_k": snappedf(float(in_view) * AREA_STEP * AREA_STEP / 1000.0, 1.0),
			"cen_d": snappedf((cen / maxf(1.0, float(hit_n))).length(), 1.0), "far": snappedf(far, 1.0),
			"dmg": snappedf(dmg / ref, 0.1), "dur": snappedf(maxf(0.0, g.ult.last_hit_t - _t_press), 0.01), "shapes_peak": _peak}
		rows.append(ar)
		print("ULTBENCH ", JSON.stringify(ar))
		return
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
	var by := {}
	var cl := [0, 0]
	for e in _set:
		if e._bk != "normal" or float(e.get("ult_d", 0.0)) <= 0.0:
			continue
		var tp: String = str(e.get("_tp", ""))
		if not by.has(tp):
			by[tp] = [0, 0]
		by[tp][1] += 1
		cl[1] += 1
		if e.dead:
			by[tp][0] += 1
			cl[0] += 1
	var row := {"op": str(g.squad.leader().id), "aim": ["right", "upright", "up", "dense"][_trial], "cluster": cluster,
		"minion": snappedf(100.0 * all_dead / maxf(1.0, n.normal[1] + n.heavy[1]), 0.1),
		"normal": snappedf(100.0 * n.normal[0] / maxf(1.0, n.normal[1]), 0.1), "heavy": snappedf(100.0 * n.heavy[0] / maxf(1.0, n.heavy[1]), 0.1),
		"elite": snappedf(100.0 * _avg(el), 0.1), "boss": snappedf(100.0 * boss, 0.1), "boss_invuln": inv,
		"dur": snappedf(maxf(0.0, g.ult.last_hit_t - _t_press), 0.01), "shapes_peak": _peak,
		"hit_n": hit_n, "dmg": snappedf(dmg / ref, 0.1), "t": T0, "clear": snappedf(100.0 * cl[0] / maxf(1.0, cl[1]), 0.1), "by": by}
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
	var avg := {"op": rows[0].op, "cluster": cluster, "area": area}
	for k in (["area_k", "view_k", "hit_n", "cen_d", "far", "dmg", "dur", "shapes_peak"] if area else ["minion", "normal", "heavy", "elite", "boss", "dur", "shapes_peak", "hit_n", "dmg", "clear"]):
		avg[k] = snappedf(_avg(rows.map(func(r): return r[k])), 0.1 if k != "dur" else 0.01)
	if not area:
		var by := {}
		for r in rows:
			for tp in r.by:
				if not by.has(tp):
					by[tp] = [0, 0]
				by[tp][0] += int(r.by[tp][0])
				by[tp][1] += int(r.by[tp][1])
		avg["by"] = by
		avg["t"] = T0
	print("ULTBENCH_AVG ", JSON.stringify(avg))
	_clear()
	g.get_tree().quit()
