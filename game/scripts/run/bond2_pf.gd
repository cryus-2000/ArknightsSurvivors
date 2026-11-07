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
	PF.particles(u, c + Vector2(-6, -18), 220, "ult_burst_s", [TX_C], 0.0, vs, L * 0.08)
	PF.particles(u, c + Vector2(6, -18), 220, "ult_burst_s", [LP_C], 0.02, vs + 3.0, L * 0.08)
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


## 企鹅物流：车开过去一路扬尘（i = 第几团，沿车道每 1/8 一团，往车后和两侧漂；不裂地、无碎石，用户 11-07「直接碾过去」）
static func penguin_trail(u, a: Dictionary, p: Vector2, i: int) -> void:
	var dl: Vector2 = a.dl
	if _late(u) and i % 2 == 1:
		return
	var vs: float = PF.vseed(u, a.c) + float(i) * 3.1
	var side: float = 1.0 if i % 2 == 0 else -1.0
	PF.dust(u, p - dl * 90.0 + dl.orthogonal() * side * 20.0 + Vector2(0, 8), 80.0 + 40.0 * PF.h(vs), 0.0, vs, -dl * 60.0 + dl.orthogonal() * side * 40.0, Color(0.6, 0.58, 0.55))


## 企鹅物流：车丢出的炸弹落地——红橙一下爆亮、粒子一团、烟尘一团；后期只留爆亮和粒子
static func bomb_hit(u, a: Dictionary, p: Vector2, i: int) -> void:
	var vs: float = PF.vseed(u, p) + float(i)
	var R: float = float(a.br)
	u.light(p, R * 1.4, Color(1.0, 0.6, 0.35), 0.12)
	PF.particles(u, p + Vector2(0, -10), 200, "ult_burst_s", [EX_C, Color(1.0, 0.8, 0.4)], 0.0, vs, R * 0.9)
	if not _late(u):
		PF.dust(u, p + Vector2(0, 6), R * 1.3, 0.04, vs, Vector2(0, -20), Color(0.5, 0.46, 0.44))


## 灯下审决：光矛落地——暖金 + 紫白一下爆亮、光圈里上升的光点；不裂地、不出碎石（审判是光，不是砸地；11-07 实机裂纹像枯树，去掉）
static func inq_hit(u, a: Dictionary) -> void:
	var c: Vector2 = a.c
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	var late: bool = _late(u)
	u.light(c, R * 0.5, Color(0.95, 0.85, 1.0), 0.12)
	PF.particles(u, c + Vector2(0, -20), 260, "ult_burst_s", [IR_C, LAMP_C], 0.0, vs, R * 0.5)
	PF.dust(u, c + Vector2(0, 8), 120.0, 0.02, vs + 2.0, Vector2.ZERO, Color(0.66, 0.6, 0.72))
	PF.particles(u, c, 140, "ult_ember", [LAMP_C, IR_C], 0.25, vs + 5.0, R * 0.7)


# ---------------------------------------------------------------- 深海猎人五条（11-07）：颜色取各人定稿（data/fx_pxplane/*.json palette）
const SK_C := Color("#598cf2")   # 斯卡蒂 main
const SK_H := Color("#cddcfb")
const GL_C := Color("#4c80c7")   # 歌蕾蒂娅 main
const GL_A := Color("#b3a8ee")   # 歌蕾蒂娅 accent（淡紫）
const SP_C := Color("#3a77c2")   # 归溟幽灵鲨 main
const SP_H := Color("#c4e2fa")
const SP_A := Color("#ffa04a")   # 归溟幽灵鲨 accent（橙）
const UL_C := Color("#4463c8")   # 乌尔比安 main
const UL_H := Color("#c0cbf6")
const FOAM := Color(0.86, 0.93, 1.0)


## 链上疾驰：巨锚落地——一圈地块顶起 + 尘团 + 冷蓝粒子；砸地类有碎石
static func lesson_land(u, a: Dictionary) -> void:
	var c: Vector2 = a.F
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	var late: bool = _late(u)
	u.light(c, R * 0.6, UL_H, 0.12)
	PF.particles(u, c + Vector2(0, -16), 240, "ult_burst_s", [UL_C, UL_H], 0.0, vs, R * 0.8)
	PF.heave(u, c, R * 0.7, vs, 0.02, Color(0.8, 0.82, 0.88), 80.0)
	for q in (2 if late else 4):
		var dv := Vector2.from_angle(TAU * (float(q) + PF.h(vs + q)) / 4.0)
		PF.dust(u, c + Vector2(dv.x, dv.y * 0.7) * R * 0.6, 90.0, 0.03 * float(q), vs + q, dv * 90.0, Color(0.56, 0.6, 0.66))


## 引潮断线：海沟裂开——沿海沟两侧冒水雾尘团、冷蓝粒子
static func tide_open(u, a: Dictionary) -> void:
	var c: Vector2 = a.c
	var d: Vector2 = a.d
	var L: float = a.L
	var vs: float = PF.vseed(u, c)
	var nd: int = 3 if _late(u) else 6
	for q in nd:
		var along: float = ((float(q) + 0.5) / float(nd) - 0.5) * L * 0.9
		var sd: float = 1.0 if q % 2 == 0 else -1.0
		PF.dust(u, c + d * along + d.orthogonal() * sd * 18.0, 80.0, 0.02 * float(q), vs + q, d.orthogonal() * sd * 70.0, Color(0.55, 0.62, 0.72))
	PF.particles(u, c, 200, "ult_burst_s", [GL_C, GL_A], 0.0, vs, L * 0.25)


## 涡心落锚：一只锚砸在箭头尖上——冷蓝爆亮、粒子、尘团；第 3 只起才带碎石（免得五只都一样）
static func vortex_anchor(u, a: Dictionary, p: Vector2, i: int) -> void:
	var R: float = float(a.ar)
	var vs: float = PF.vseed(u, p) + float(i)
	u.light(p, R * 0.8, UL_H, 0.1)
	PF.particles(u, p + Vector2(0, -12), 160, "ult_burst_s", [UL_C, GL_A], 0.0, vs, R * 0.9)
	if not _late(u):
		PF.dust(u, p + Vector2(0, 6), R * 1.2, 0.03, vs, Vector2.ZERO, Color(0.56, 0.6, 0.66))
		if i >= 2:
			PF.heave(u, p, R * 0.5, vs, 0.0, Color(0.8, 0.82, 0.88), 70.0)


## 双鳍破浪：两片背鳍在圈心扎进水里——白浪粒子 + 两色粒子 + 尘团
static func fins_dive(u, a: Dictionary) -> void:
	var c: Vector2 = a.c
	var R: float = float(a.R)
	var vs: float = PF.vseed(u, c)
	u.light(c, R * 0.5, SK_H, 0.12)
	PF.particles(u, c + Vector2(-8, -14), 240, "ult_burst_s", [SK_C, FOAM], 0.0, vs, R * 0.5)
	PF.particles(u, c + Vector2(8, -14), 240, "ult_burst_s", [SP_C, SP_H], 0.02, vs + 3.0, R * 0.5)
	PF.dust(u, c + Vector2(0, 8), 120.0, 0.03, vs + 5.0, Vector2.ZERO, Color(0.62, 0.7, 0.8))


## 群猎合围：潮水在圈心合拢——大一团白浪粒子 + 各人色粒子 + 尘团
static func hunt_hit(u, a: Dictionary) -> void:
	var c: Vector2 = a.c
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	u.light(c, R * 0.5, FOAM, 0.12)
	PF.particles(u, c + Vector2(0, -16), 300, "ult_burst_s", [FOAM, SK_C, GL_A], 0.0, vs, R * 0.6)
	if not _late(u):
		PF.dust(u, c + Vector2(0, 8), 140.0, 0.03, vs + 5.0, Vector2.ZERO, Color(0.6, 0.68, 0.78))
		PF.heave(u, c, R * 0.4, vs, 0.04, Color(0.8, 0.85, 0.92), 80.0)
