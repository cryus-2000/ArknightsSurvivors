## 队长手感探针（全员手感排查，10-29）：只在 --feelprobe 时由 telemetry 建出，只观察、不改状态、不用随机数
## 记录：贴身 / 被围秒数、想走却走不动（区分敌方控制与自身动作）、被技能带着位移、技能发动后 2 秒承伤与身边敌人变化
extends RefCounted

const CAST_WIN := 2.0

var g
var near_s := 0.0          # 身边贴着至少 1 只敌人（距离 < 敌人半径 + 22）
var crowd_s := 0.0         # 90 范围内 ≥ 4 只
var taken_near := 0.0      # 贴身时承伤
var taken_all := 0.0
var want_s := 0.0          # 机器人想移动的秒数
var stuck_cc_s := 0.0      # 想走但被眩晕 / 冻结
var stuck_self_s := 0.0    # 想走但实际位移 < 30%（非控制，多为自身动作 / 技能锁步）
var pulled_s := 0.0        # 没冲刺却位移 > 1.6 倍移速（技能带着走）
var casts: Array = []      # 进行中的发动窗口
var cast_n := 0
var cast_risky := 0        # 发动后 2 秒承伤 ≥ 发动前 2 秒 ×2 且 ≥ 5% 最大生命
var cast_taken := 0.0
var cast_near_d := 0.0     # 发动 1 秒后贴身敌人数 − 发动时
var hist: Array = []       # [t, 累计承伤]，留 2 秒
var _last_pos := Vector2.INF
var _taken_prev := 0.0


func _init(game) -> void:
	g = game


func _near_counts() -> Vector2i:
	var a := 0
	var b := 0
	for j in g.enemies_sys.query(g.ppos, 90.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var d: float = e.pos.distance_to(g.ppos)
		if d < float(e.r) + 22.0:
			a += 1
		if d < 90.0:
			b += 1
	return Vector2i(a, b)


func tick(dt: float, taken_total: float) -> void:
	if g.ch == null or g.state != g.S.PLAY:
		_last_pos = g.ppos
		return
	var nc := _near_counts()
	var inc: float = maxf(0.0, taken_total - _taken_prev)
	_taken_prev = taken_total
	taken_all += inc
	if nc.x > 0:
		near_s += dt
		taken_near += inc
	if nc.y >= 4:
		crowd_s += dt
	if _last_pos != Vector2.INF and dt > 0.0:
		var step: float = g.ppos.distance_to(_last_pos)
		var full: float = maxf(1.0, float(g.speed) * dt)
		if g.move_in != Vector2.ZERO and g.dash_t <= 0.0:
			want_s += dt
			if g.pstun > 0.0 or g.root_t > 0.0:
				stuck_cc_s += dt
			elif step < 0.3 * full:
				stuck_self_s += dt
		if g.dash_t <= 0.0 and step > 1.6 * full:
			pulled_s += dt
	_last_pos = g.ppos
	hist.append([g.t, taken_total])
	while hist.size() > 1 and hist[0][0] < g.t - CAST_WIN:
		hist.pop_front()
	for c in casts:
		if not c.has("n1") and g.t >= c.t + 1.0:
			c["n1"] = nc.x
	while not casts.is_empty() and g.t >= casts[0].t + CAST_WIN:
		var c: Dictionary = casts.pop_front()
		var after: float = taken_total - float(c.tk)
		cast_taken += after
		if after >= maxf(2.0 * float(c.before), 0.05 * float(g.max_hp)):
			cast_risky += 1
		cast_near_d += float(c.get("n1", nc.x)) - float(c.n0)


func on_cast(op_id: String) -> void:
	if g.ch == null or op_id != g.ch.id:
		return
	var tk: float = _taken_prev
	var before: float = tk - (float(hist[0][1]) if not hist.is_empty() else tk)
	cast_n += 1
	casts.append({"t": g.t, "tk": tk, "before": before, "n0": _near_counts().x})


func report() -> Dictionary:
	var t: float = maxf(1.0, g.t)
	var done: int = maxi(1, cast_n - casts.size())
	return {"near_pct": snappedf(100.0 * near_s / t, 0.1), "crowd_pct": snappedf(100.0 * crowd_s / t, 0.1),
		"taken_near_pct": snappedf(100.0 * taken_near / maxf(1.0, taken_all), 0.1),
		"stuck_cc_pct": snappedf(100.0 * stuck_cc_s / maxf(1.0, want_s), 0.1), "stuck_self_pct": snappedf(100.0 * stuck_self_s / maxf(1.0, want_s), 0.1),
		"pulled_pm": snappedf(pulled_s / t * 60.0, 0.01), "casts": cast_n, "cast_risky_pct": snappedf(100.0 * cast_risky / done, 0.1),
		"cast_taken_avg": snappedf(cast_taken / done, 0.1), "cast_near_d": snappedf(cast_near_d / done, 0.01)}
