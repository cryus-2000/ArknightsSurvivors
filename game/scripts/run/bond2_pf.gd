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


## 狼衔剑：巨剑钉进终点——琥珀 / 淡紫两色爆亮、从剑脚往外长一圈分叉裂缝、几团烟尘往外推（斩击类不出碎石）
static func rival_hit(u, a: Dictionary) -> void:
	var c: Vector2 = a.E
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	u.light(c, R, Color(1.0, 0.85, 0.6), 0.12)
	PF.particles(u, c + Vector2(0, -18), 240, "ult_burst_s", [TX_C], 0.0, vs, R * 0.7)
	PF.particles(u, c + Vector2(0, -18), 200, "ult_burst_s", [LP_C], 0.03, vs + 3.0, R * 0.6)
	var angs: Array = []
	var lens: Array = []
	for q in 5:
		angs.append(TAU * (float(q) + PF.h(vs + q)) / 5.0)
		lens.append(R * (0.6 + 0.35 * PF.h(vs + q * 2.3)))
	PF.cracks(u, SG_FORKS, c, angs, lens, {"seed": vs, "r0": 8.0, "rev": 0.1, "rev0": 0.2, "delay": 0.02, "life": 1.4, "fade": 0.6,
		"col": Color(1.4, 0.9, 0.45), "col1": Color(0.16, 0.15, 0.16), "cold": 0.5, "small": 0.3, "big": 0.4})
	if not _late(u):
		for q in 3:
			var dv := Vector2.from_angle(TAU * (float(q) + PF.h(vs + q * 1.7)) / 3.0)
			PF.dust(u, c + Vector2(dv.x, dv.y * 0.7) * R * 0.4, 90.0, 0.04 * float(q), vs + q, dv * 90.0, Color(0.6, 0.56, 0.62))


## 狼衔剑：剑尖犁地一路扬起的土（每 2 拍一团，往车道两侧漂）+ 一小把淡紫碎光
static func wolf_trail(u, a: Dictionary, p: Vector2) -> void:
	var dl: Vector2 = a.dl
	var vs: float = PF.vseed(u, p)
	if not _late(u):
		var sd: float = 1.0 if PF.h(vs) > 0.5 else -1.0
		PF.dust(u, p - dl * 70.0 + Vector2(0, 8), 60.0 + 30.0 * PF.h(vs + 1.0), 0.0, vs, -dl * 40.0 + dl.orthogonal() * sd * 50.0, Color(0.58, 0.52, 0.5))
	PF.particles(u, p + Vector2(0, -14), 60, "ult_burst_s", [LP_C], 0.0, vs + 2.0, 30.0)


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


## 串刺：槊尾钉住那一下——槊尖处一团水花 + 冷蓝粒子
static func tide_open(u, a: Dictionary) -> void:
	var c: Vector2 = a.E
	var vs: float = PF.vseed(u, c)
	u.light(c, 70.0, GL_A, 0.1)
	PF.particles(u, c + Vector2(0, -10), 160, "ult_burst_s", [GL_C, FOAM], 0.0, vs, 60.0)
	if not _late(u):
		PF.dust(u, c + Vector2(0, 6), 70.0, 0.02, vs + 1.0, Vector2.ZERO, Color(0.55, 0.62, 0.72))


## 串刺：幽灵鲨一刀锯开——橙色火星 + 幽灵鲨蓝粒子 + 一团水雾
static func tide_saw(u, a: Dictionary) -> void:
	var c: Vector2 = a.P
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	u.light(c, R, SP_A, 0.12)
	PF.particles(u, c + Vector2(0, -14), 220, "ult_burst_s", [SP_A, SP_H], 0.0, vs, R * 0.8)
	PF.particles(u, c + Vector2(0, -14), 160, "ult_burst_s", [SP_C], 0.03, vs + 2.0, R * 0.6)
	if not _late(u):
		PF.dust(u, c + Vector2(0, 8), R * 1.1, 0.03, vs + 4.0, Vector2.ZERO, Color(0.55, 0.62, 0.72))


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


## 击锯：锯刃嵌进地里炸开——橙色火星 + 斯卡蒂蓝粒子 + 碎石（撞地类）+ 尘团
static func fins_dive(u, a: Dictionary) -> void:
	var c: Vector2 = a.E
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	u.light(c, R, SP_A, 0.12)
	PF.particles(u, c + Vector2(0, -12), 260, "ult_burst_s", [SP_A, Color(1.0, 0.9, 0.7)], 0.0, vs, R * 0.8)
	PF.particles(u, c + Vector2(0, -12), 180, "ult_burst_s", [SK_C, FOAM], 0.03, vs + 3.0, R * 0.6)
	if not _late(u):
		PF.dust(u, c + Vector2(0, 8), R * 1.1, 0.03, vs + 5.0, Vector2.ZERO, Color(0.6, 0.6, 0.62))
		PF.heave(u, c, R * 0.45, vs, 0.02, Color(0.8, 0.8, 0.84), 70.0)


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


## 收力一剑：斯卡蒂一剑劈在那一堆上——只在小圈里爆亮、粒子不外飞（收着力），一道短裂口 + 一团水雾
static func lesson_cut(u, a: Dictionary) -> void:
	var c: Vector2 = a.Pp
	var R: float = float(a.r)
	var vs: float = PF.vseed(u, c)
	u.light(c, R * 0.8, SK_H, 0.12)
	PF.particles(u, c + Vector2(0, -14), 220, "ult_burst_s", [SK_C, FOAM], 0.0, vs, R * 0.45)
	PF.cracks(u, SG_FORKS, c, [-0.9, 2.24], [R * 0.5, R * 0.45], {"seed": vs, "r0": 6.0, "rev": 0.08, "rev0": 0.2, "delay": 0.0, "life": 1.2, "fade": 0.5,
		"col": Color(0.9, 1.1, 1.5), "col1": Color(0.15, 0.16, 0.2), "cold": 0.4, "small": 0.25, "big": 0.35})
	if not _late(u):
		PF.dust(u, c + Vector2(0, 8), R * 0.9, 0.03, vs + 4.0, Vector2.ZERO, Color(0.58, 0.64, 0.74))
