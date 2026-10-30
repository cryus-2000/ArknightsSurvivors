extends Node
## 普通怪伤害曲线（docs/194，用户 10-29）单元测试（check.py 场景回归 dmg_curve）：目标曲线单调不降、封顶、一阶连续（相邻采样差平滑）、
## 经过关键点；各威胁档刷怪池「池平均一下」= 目标曲线（时间倍率按池平均基础伤害归一，换池不跳）；on 0 时 enabled() 为假。
const DmgCurve = preload("res://scripts/run/dmg_curve.gd")
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("DMG CURVE: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


func avg_hit(t: float, threat: int) -> float:
	return DmgCurve.pool_avg(threat) * DmgCurve.mult(t, threat) * DmgCurve.density_k() * Bal.v("dmg_curve/ref_taken", 0.9) - Bal.v("dmg_curve/ref_armor", 1.9)


func threat_at(t: float) -> int:
	var k := 0
	for i in D.THREAT.size():
		if t >= float(D.THREAT[i].t):
			k = i
	return k


func run() -> void:
	check(DmgCurve.enabled(), "缺省开启")
	var knots: Array = Bal.sec("dmg_curve").get("knots", [])
	check(knots.size() >= 3, "关键点至少 3 个")
	for kn in knots:
		check(absf(DmgCurve.target_raw(float(kn[0])) - float(kn[1])) < 1e-4, "曲线过关键点 %s" % str(kn))
	var last := -1.0
	var worst_step := 0.0
	var prev_step := -1.0
	var jump := 0.0
	for i in 721:
		var t := float(i)
		var v: float = DmgCurve.target(t)
		check(v >= last - 1e-6, "单调不降 t=%d" % i)
		if i > 0:
			var st: float = v - last
			worst_step = maxf(worst_step, st)
			if prev_step >= 0.0:
				jump = maxf(jump, absf(st - prev_step))
			prev_step = st
		last = v
	check(worst_step < 0.08, "相邻 1 秒增量不大于 0.08（无断崖），实际最大 %.3f" % worst_step)
	check(jump < 0.01, "相邻增量变化 < 0.01（一阶连续、无折点），实际最大 %.4f" % jump)
	var top: float = float(knots[knots.size() - 1][1])
	var top_cut: float = top * (1.0 - Bal.v("dmg_curve/mid_cut", 0.0)) * Bal.v("dmg_curve/scale", 1.0)   # 全程整体倍率（diff-1031 缺省 0.94）
	check(absf(DmgCurve.target(900.0) - top_cut) < 1e-4 and absf(DmgCurve.target(5000.0) - top_cut) < 1e-4, "末点之后封顶 %.1f" % top_cut)
	# 池平均一下 = 目标曲线（含换池的时刻前后各一秒）
	for t in [0.0, 60.0, 120.0, 180.0, 240.0, 279.0, 281.0, 299.0, 301.0, 399.0, 401.0, 519.0, 521.0, 600.0, 700.0]:
		var th := threat_at(t)
		var d: float = absf(avg_hit(t, th) - DmgCurve.target(t))
		check(d < 1e-3, "池平均一下 = 目标 t=%d 威胁 %d 差 %.4f" % [int(t), th, d])
	# 换池处池平均一下不跳（在目标曲线上，只差 1 秒的增量）
	for tb in [75.0, 170.0, 280.0, 400.0, 520.0]:
		var a: float = avg_hit(tb - 0.5, threat_at(tb - 0.5))
		var b: float = avg_hit(tb + 0.5, threat_at(tb + 0.5))
		check(absf(b - a) < 0.1, "换池 t=%d 前后池平均一下不跳（%.2f → %.2f）" % [int(tb), a, b])
	print("DMG CURVE failures=%d  0:00=%.1f 3:00=%.1f 5:00=%.1f 7:00=%.1f 10:00=%.1f" % [failures, DmgCurve.target(0.0), DmgCurve.target(180.0), DmgCurve.target(300.0), DmgCurve.target(420.0), DmgCurve.target(600.0)])
	get_tree().quit(1 if failures > 0 else 0)
