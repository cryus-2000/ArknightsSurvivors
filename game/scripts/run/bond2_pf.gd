## 羁绊技 v2 合击的力量感层（11-07 用户：「力量感不够」→ 改成一下的合击）：只画，在 bond2.gd 命中那一刻调。
## 手法按 pixfx §5 / §6.6（乌尔比安裂地那套）：命中一刻最亮、1 秒内冷成暗色；分叉裂网从撞点往外长；团块烟尘逐帧出现消失；
## 撞车类才有碎石（斩击类只给烟尘，pixfx §6.6 第 5 条）；余震晚 0.3 秒。不震屏、不白屏、不冲击帧（docs/294 §3 羁绊技口径）。
## 散布全用哈希（PF.vseed：出招时刻 + 落点），不抽模拟随机数。后期（render/late_fx 起）烟尘 / 碎石减半（docs/293 A 版：变薄、减量）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")

const SG_FORKS := ["fx_sg_fork1", "fx_sg_fork2", "fx_sg_fork3", "fx_sg_fork4"]
const TX_C := Color(1.0, 0.62, 0.28)
const LP_C := Color(0.72, 0.66, 1.0)
const EX_C := Color(1.0, 0.45, 0.3)
const LAMP_C := Color(1.0, 0.86, 0.5)
const IR_C := Color(0.82, 0.6, 1.0)


static func _late(u) -> bool:
	return float(u.g.t) >= Bal.v("render/late_fx_t0", 480.0)


## 宿敌：十字斩落地——交点一下爆亮（两色粒子）→ 沿两道斩痕四个方向的分叉裂缝往外长（琥珀 / 淡紫，冷成暗灰）→
## 斩痕两侧翻起烟尘墙（每道 4 团、往斩痕两侧推开）；斩击类不出碎石（pixfx §6.6 第 5 条）
static func rival_hit(u, a: Dictionary) -> void:
	var c: Vector2 = a.c
	var L: float = float(a.L)
	var vs: float = PF.vseed(u, c)
	var late: bool = _late(u)
	u.light(c, 110.0, Color(1.0, 0.92, 0.85), 0.1)
	PF.particles(u, c + Vector2(-6, -18), 220, "ult_burst_s", [TX_C], 0.0, vs, L * 0.12)
	PF.particles(u, c + Vector2(6, -18), 220, "ult_burst_s", [LP_C], 0.02, vs + 3.0, L * 0.12)
	for half in 2:
		var d: Vector2 = a.d1 if half == 0 else a.d2
		var col: Color = TX_C if half == 0 else LP_C
		var angs: Array = []
		var lens: Array = []
		for sd in [1.0, -1.0]:
			angs.append((d * sd).angle() + (PF.h(vs + sd + half * 5.0) - 0.5) * 0.12)
			lens.append(L * (0.36 + 0.12 * PF.h(vs + sd * 3.0 + half)))
		PF.cracks(u, SG_FORKS, c, angs, lens, {"seed": vs + half * 17.0, "r0": 10.0, "rev": 0.12, "rev0": 0.25, "delay": 0.03, "life": 1.5, "fade": 0.6,
			"col": Color(minf(1.5, col.r * 1.4), minf(1.5, col.g * 1.4), minf(1.5, col.b * 1.4)), "col1": Color(0.16, 0.15, 0.16), "cold": 0.5, "small": 0.3, "big": 0.42})
		var nd: int = 2 if late else 4
		for q in nd:
			var hq: float = PF.h(vs + q * 5.1 + half * 11.0)
			var along: float = ((float(q) + 0.5) / float(nd) - 0.5) * L * 0.85
			var nv: Vector2 = d.orthogonal() * (1.0 if q % 2 == 0 else -1.0)
			PF.dust(u, c + d * along + nv * 14.0 + Vector2(0, 6), 70.0 + 40.0 * hq, 0.03 + absf(along) / L * 0.25, vs + q + half * 7.0, nv * 90.0, Color(0.62, 0.6, 0.58))
	PF.particles(u, c, 120, "ult_ember", [Color(0.9, 0.7, 0.55)], 0.3, vs + 9.0, L * 0.3)


## 企鹅物流：车开过去一路扬尘（i = 第几团，沿车道每 1/8 一团，往车后和两侧漂；不裂地、无碎石，用户 11-07「直接碾过去」）
static func penguin_trail(u, a: Dictionary, p: Vector2, i: int) -> void:
	var dl: Vector2 = a.dl
	if _late(u) and i % 2 == 1:
		return
	var vs: float = PF.vseed(u, a.c) + float(i) * 3.1
	var side: float = 1.0 if i % 2 == 0 else -1.0
	PF.dust(u, p - dl * 90.0 + dl.orthogonal() * side * 20.0 + Vector2(0, 8), 80.0 + 40.0 * PF.h(vs), 0.0, vs, -dl * 60.0 + dl.orthogonal() * side * 40.0, Color(0.6, 0.58, 0.55))


## 灯下审决：光矛落地——暖金 + 紫白一下爆亮、光圈里上升的光点；不裂地、不出碎石（审判是光，不是砸地；11-07 实机裂纹像枯树，去掉）
static func inq_hit(u, a: Dictionary) -> void:
	var c: Vector2 = a.c
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	var late: bool = _late(u)
	u.light(c, R * 1.0, Color(0.95, 0.85, 1.0), 0.16)
	PF.particles(u, c + Vector2(0, -20), 260, "ult_burst_s", [IR_C, LAMP_C], 0.0, vs, R * 0.5)
	PF.dust(u, c + Vector2(0, 8), 120.0, 0.02, vs + 2.0, Vector2.ZERO, Color(0.66, 0.6, 0.72))
	PF.particles(u, c, 140, "ult_ember", [LAMP_C, IR_C], 0.25, vs + 5.0, R * 0.7)
