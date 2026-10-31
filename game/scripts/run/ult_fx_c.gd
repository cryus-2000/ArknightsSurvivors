## pixfx 第三组：归溟幽灵鲨 / 流明 / 水月 / 铃兰（docs/199 §7.9，做法见 .claude/skills/pixfx）。
## 只画画面：ult_moves_b / _c 里各人那段在原画法的位置调这里，u.hit、时序、半径、判定都留在原处不动；散布按 PF.h 哈希 / PF.vseed，不抽模拟随机数。
## 每人一个开关（缺省 1；0 = 原程序画法），贴图缺时自动退回旧版。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")
const A = preload("res://scripts/art.gd")


# ================================================================ 归溟幽灵鲨：整圈巨锯（ult/sp_saw_v2）
## 一张 pixgen 整圈锯（黑钢锯身 + 银刃口 + 缺口锯齿，中间空），按锯半径缩放、跟着队长走、持续转；
## 两层运动残影拖在后面（转速快，30 帧录像里不残影会像原地抖）；每圈咬一下（亮一拍 + 短灯 + 锯缘迸火星），锯到的敌人身上迸红 / 银火星。
const SP_SAW := "fx_sp_saw"
const SP_SPARK := [Color(0.66, 0.34, 0.12), Color(0.58, 0.6, 0.64), Color(0.6, 0.1, 0.12)]   # PF.particles 会 ×1.35 提亮，这里给暗一档


static func sp_v2(u) -> bool:
	return Bal.v("ult/sp_saw_v2", 1.0) > 0.0 and u.fx_ready(SP_SAW)


static func sp_start(u, a: Dictionary, c: Vector2) -> void:
	var dur: float = a.dur
	a["sp_rr"] = PF.tex_w(u, SP_SAW) * 0.5
	a["sp_vs"] = PF.vseed(u, c)
	a["sp_rot"] = PF.h(float(a.sp_vs)) * TAU
	a["sp_bite"] = 0.0
	a["sp_shadow"] = {"kind": "circle", "c": c, "r": 60.0, "col": Color(0.02, 0.03, 0.05), "fill": 0.28, "life": dur + 1.0, "layer": "back"}
	u.shape(a.sp_shadow)
	var saws: Array = []
	for k in [2, 1, 0]:   # 残影先画、本体最后（压在上面）
		saws.append(u.strip(SP_SAW, c, {"sc": 0.1, "life": dur + 1.0, "col": Color(1, 1, 1, [1.0, 0.38, 0.18][k]), "k": k}))
	a["sp_saws"] = saws
	u.light(c, 260.0, Color(0.75, 0.8, 0.9), 0.2)


## 每帧：R = 当前锯半径（放大中）；锯齿尖落在 R + 26（原程序锯齿外端）
static func sp_step(u, a: Dictionary, c: Vector2, R: float, dt: float) -> void:
	a.sp_rot = float(a.sp_rot) + dt * Bal.v("ult/sp_spin", 7.5)
	a.sp_bite = maxf(0.0, float(a.sp_bite) - dt)
	var sc: float = (R + 26.0) / float(a.sp_rr)
	var bite: float = clampf(float(a.sp_bite) / 0.08, 0.0, 1.0)
	for s in a.sp_saws:
		var k: int = int(s.k)
		s.c = c
		s.sc = sc
		s.ang = -(float(a.sp_rot) - 0.075 * k)   # 顺时针转（锯齿朝顺时针勾）；残影落后
		if k == 0:
			var b: float = 1.0 + 0.35 * bite
			s.col = Color(b, b, b, 1.0)
	a.sp_shadow.c = c
	a.sp_shadow.r = R * 0.98


## 每一圈（0.25 秒）咬一下：亮一拍、短灯、锯缘 3 处迸火星（按哈希挑位置）
static func sp_tick(u, a: Dictionary, c: Vector2, R: float, tick: int) -> void:
	a.sp_bite = 0.08
	u.light(c, R * 1.05, Color(0.7, 0.74, 0.82), 0.12)
	var vs: float = float(a.sp_vs)
	for q in 3:
		var hh: float = PF.h(vs + tick * 7.0 + q * 3.1)
		var p: Vector2 = c + Vector2.from_angle(TAU * (q + hh) / 3.0 + tick * 0.9) * R
		PF.particles(u, p, 40, "ult_burst_s", SP_SPARK, 0.0, vs + tick * 11.0 + q)


## 锯到的敌人（每圈最多 6 处，同原画法的计数）：红 / 银火星沿切线迸
static func sp_hit(u, a: Dictionary, p: Vector2, tick: int, i: int) -> void:
	var vs: float = float(a.sp_vs) + tick * 13.0 + i * 5.0
	PF.particles(u, p, 30, "ult_burst_s", [SP_SPARK[2], SP_SPARK[0]], 0.0, vs)
	if i % 2 == 0:
		u.grain("sh_shard", p, Vector2.from_angle(PF.h(vs) * TAU), Color(0.75, 0.15, 0.18), 4)


static func sp_end(u, a: Dictionary) -> void:
	for s in a.get("sp_saws", []):
		s.max = float(s.age) + 0.3
		s["fade"] = 0.3
	if a.has("sp_shadow"):
		a.sp_shadow.age = 0.0
		a.sp_shadow.max = 0.3


# ================================================================ 流明：灯塔光柱 + 光圈（ult/lu_fx_v2）
## 光柱 = pixgen 通透光面（几片竖向光幕 + 漂浮光点，亮度封顶 0.85），两层（本体 + 镜像淡层）从脚底往上长出、呼吸闪动；
## 升起前脚下一圈压暗 → 扩散那一刻大灯 + 碎光环（3 种变体按 vseed 挑）+ 光点颗粒迸开 → 冷成淡青；
## 每 0.5 秒一跳：小一圈碎光环 + 上飘光点；灯塔光束换成 pixgen 探照光束贴图（两道，跟原来同角度）。
const LU_PILLAR := "fx_lu_pillar"
const LU_RINGS := ["fx_lu_ring1", "fx_lu_ring2", "fx_lu_ring3"]
const LU_SHAFT := "fx_lu_shaft"
const LU_WARM := Color(0.92, 0.86, 0.66)
const LU_AQUA := Color(0.62, 0.8, 0.82)
const LU_PWARM := Color(0.6, 0.55, 0.4)   # 粒子帧条用（×1.35 后约 0.8，不发白）
const LU_PAQUA := Color(0.4, 0.55, 0.58)


static func lu_v2(u) -> bool:
	return Bal.v("ult/lu_fx_v2", 1.0) > 0.0 and u.fx_ready(LU_PILLAR)


static func lu_start(u, a: Dictionary, c: Vector2, dur: float) -> void:
	var vs: float = PF.vseed(u, c)
	a["lu_vs"] = vs
	var t: Texture2D = u._strip_tex(LU_PILLAR)
	var o := Vector2(0.0, t.get_height() * 0.5)   # 贴图横放：左端 = 柱脚
	var ps: Array = []
	for k in 2:
		ps.append(u.strip(LU_PILLAR, c + Vector2(0, 6), {"ang": -PI / 2.0, "o": o, "sy": -1.0 if k == 1 else 1.0, "sc": 1.0 + 0.12 * k,
			"rev": 0.22 + 0.08 * k, "rev0": 0.05, "life": float(a.t0) + dur + 0.45, "fade": 0.45, "col": Color(1, 1, 1, 0.5 if k == 0 else 0.22)}))   # 透明度压低：中心不能叠成实心白（预审 10-30）
	a["lu_ps"] = ps
	u.shape({"kind": "circle", "c": c, "r": float(a.R), "col": Color(0.0, 0.01, 0.03), "fill": 0.3, "life": float(a.t0) + 0.06, "layer": "back"})   # 升起前压暗
	u.light(c, 140.0, LU_PWARM, float(a.t0) + 0.1)
	for q in 6:
		u.grain("mote_up", c + Vector2((PF.h(vs + q) - 0.5) * 90.0, -10.0), Vector2.UP, LU_WARM, 3)


static func lu_boom(u, a: Dictionary, c: Vector2, R: float) -> void:
	var vs: float = float(a.lu_vs)
	u.light(c, R * 1.0, LU_PWARM, 0.3)   # 灯用暗一档的暖色，免得整片发白
	PF.ring(u, LU_RINGS, c, 40.0, R, float(a.exp), 0.75, {"seed": vs, "col": Color(1.05, 1.0, 0.85, 0.95), "col1": Color(0.55, 0.78, 0.82, 0.8), "cold": 0.45, "fade": 0.4})
	PF.ring(u, LU_RINGS, c, 40.0, R * 0.97, float(a.exp), 0.7, {"seed": vs + 41.0, "col": Color(1.0, 0.96, 0.82, 0.7), "col1": Color(0.5, 0.72, 0.76, 0.6), "cold": 0.45, "fade": 0.4})   # 第二层错开转角，补上第一层的缺口（预审：像一圈等距方块）
	PF.ring(u, LU_RINGS, c, 30.0, R * 0.8, float(a.exp) * 1.3, 0.6, {"seed": vs + 17.0, "col": Color(0.8, 0.88, 0.9, 0.35), "fade": 0.35, "delay": 0.05})
	PF.particles(u, c, 300, "ult_burst", [LU_PWARM, LU_PAQUA], 0.0, vs, R * 0.95)
	_lu_motes(u, c, R, vs + 3.0, 6, 0.1)


static func lu_step(u, a: Dictionary, c: Vector2, el: float, dur: float) -> void:
	var br: float = 0.94 + 0.05 * sin(el * 17.0) + 0.04 * sin(el * 41.0 + 1.3)   # 光幕呼吸闪动（贴图已封顶 0.85，这里不再提亮）
	for s in a.get("lu_ps", []):
		var al: float = float(s.col.a)
		s.col = Color(br, br, br, al)
	if el <= dur and int(el * 60.0) % 4 == 0:   # 柱身漂浮光点
		var vs: float = float(a.lu_vs)
		var hh: float = PF.h(vs + el * 13.0)
		u.grain("mote_up", c + Vector2((hh - 0.5) * 110.0, -40.0 - 420.0 * PF.h(hh * 7.0)), Vector2.UP, LU_WARM if hh < 0.6 else LU_AQUA, 2)


## 灯塔光束：两道探照光束贴图跟原扇形同角度；al = 当前透明度
static func lu_beams(u, a: Dictionary, c: Vector2, R: float, angs: Array, al: float) -> void:
	if not u.fx_ready(LU_SHAFT):
		return
	if not a.has("lu_bs"):
		var t: Texture2D = u._strip_tex(LU_SHAFT)
		var bs: Array = []
		for s in angs.size():
			bs.append(u.strip(LU_SHAFT, c, {"o": Vector2(0.0, t.get_height() * 0.5), "sx": R / PF.tex_w(u, LU_SHAFT), "life": 9.0}))
		a["lu_bs"] = bs
	for s in angs.size():
		var b: Dictionary = a.lu_bs[s]
		b.c = c
		b.ang = float(angs[s])
		b.col = Color(1, 1, 1, al)


static func lu_tick(u, a: Dictionary, c: Vector2, R: float, i: int) -> void:
	var vs: float = float(a.lu_vs) + 31.0 * (i + 1)
	PF.ring(u, LU_RINGS, c, R * 0.72, R, 0.3, 0.4, {"seed": vs, "col": Color(0.95, 0.92, 0.8, 0.55), "fade": 0.3})
	_lu_motes(u, c, R, vs, 4, 0.0)
	u.light(c, R * 0.9, LU_PWARM, 0.15)


## 光圈里散几团小光点（小号粒子帧条只能放到约 100 半径，再大一纹素就成大方块）
static func _lu_motes(u, c: Vector2, R: float, vs: float, n: int, delay: float) -> void:
	for q in n:
		var hh: float = PF.h(vs + q * 2.3)
		var p: Vector2 = c + Vector2.from_angle(TAU * (q + hh) / n) * R * (0.2 + 0.5 * PF.h(vs + q * 4.1))
		PF.particles(u, p, 40, "ult_ember", [LU_PWARM if q % 2 == 0 else LU_PAQUA], delay + 0.04 * (q % 3), vs + q, 90.0)


static func lu_end(u, a: Dictionary) -> void:
	for b in a.get("lu_bs", []):
		b.max = float(b.age) + 0.2
		b["fade"] = 0.2


# ================================================================ 水月：钻洞痕 + 小触手（ult/mz_grab_v2；大触手整条贴图是 session-2 的 ult/mz_fx_v2，在 ult_moves_b 里）
## 破土：根部压暗 + 地块隆起 + 暗色颗粒帧条 + 青色短灯；扫动：扫过的扇区淡淡压暗 + 尖端甩水沫；扫完大触手 0.3 秒淡出缩回；
## 小触手 = 3 种 pixgen 小触手（按 vseed 挑、镜像、转角）从地里钻出（rev 从根往上长），脚下一个暗洞 + 颗粒。
const MZ_SMALL := ["fx_mz_small1", "fx_mz_small2", "fx_mz_small3"]
const MZ_CYAN := Color(0.44, 0.88, 0.93)
const MZ_INK := Color(0.12, 0.15, 0.3)


static func mz_v2(u) -> bool:
	return Bal.v("ult/mz_grab_v2", 1.0) > 0.0 and u.fx_ready(MZ_SMALL[0])


static func mz_start(u, a: Dictionary, base: Vector2) -> void:
	var vs: float = PF.vseed(u, base)
	a["mz_vs"] = vs
	u.shape({"kind": "circle", "c": base, "r": 80.0, "col": Color(0.02, 0.02, 0.05), "fill": 0.75, "life": 1.3, "layer": "back"})
	PF.heave(u, base, 70.0, vs, 0.0, Color(0.7, 0.72, 0.85), 60.0)
	PF.particles(u, base, 60, "ult_burst_s", [MZ_INK, Color(0.25, 0.3, 0.5)], 0.0, vs)
	u.light(base, 200.0, MZ_CYAN, 0.25)


## 扫动中（每 0.03 秒）：尖端甩水沫 + 尖端短灯
static func mz_trail(u, a: Dictionary, tip: Vector2, ang: float, n: int) -> void:
	var tg: Vector2 = Vector2.from_angle(ang + PI / 2.0)
	u.grain("water", tip, tg, MZ_CYAN, 5)
	if n % 5 == 0:
		PF.particles(u, tip, 30, "ult_burst_s", [MZ_INK, Color(0.3, 0.5, 0.6)], 0.0, float(a.mz_vs) + n)


## 扫完：大触手缩回（沿原样淡出 0.3 秒）
static func mz_retract(u, a: Dictionary) -> void:
	for s in a.get("tsegs", []):
		a.fx.erase(s)
		s.max = float(s.age) + 0.3
		s["fade"] = 0.3
	PF.particles(u, a.base, 50, "ult_burst_s", [MZ_INK, Color(0.25, 0.3, 0.5)], 0.0, float(a.mz_vs) + 5.0)


## 一根小触手从 p 钻出：i = 序号（错开 + 挑变体）
static func mz_small(u, a: Dictionary, p: Vector2, i: int, sc: float, delay: float) -> void:
	var vs: float = float(a.mz_vs) + i * 7.0
	var name := PF.pick(u, MZ_SMALL, vs)
	if name == "":
		return
	var t: Texture2D = u._strip_tex(name)
	u.strip(name, p, {"ang": -PI / 2.0 + (PF.h(vs + 1.0) - 0.5) * 0.3, "o": Vector2(0.0, t.get_height() * 0.5), "sy": -1.0 if PF.h(vs + 2.0) < 0.5 else 1.0,
		"sc": sc * (0.9 + 0.2 * PF.h(vs + 3.0)), "rev": 0.12, "rev0": 0.1, "delay": delay, "life": 0.85, "fade": 0.3})
	u.shape({"kind": "circle", "c": p, "r": 22.0 * sc, "col": Color(0.02, 0.02, 0.05), "fill": 0.7, "life": 0.9, "delay": delay, "layer": "back"})
	PF.particles(u, p, 20, "ult_burst_s", [MZ_INK], delay, vs, 55.0 * sc)   # 根部土屑：小、暗（预审：每根一样的蓝色颗粒团）


# ================================================================ 铃兰：忍冬现身 → 瞬身斩 → 斩痕爆裂（ult/sz_fx_v2）
## 忍冬 = pixgen 白光人形（照 Codex 忍冬关键帧的轮廓），淡入；瞬身 = pixgen 连续冷色斩痕（亮芯 ≤ 0.9、边缘冷蓝灰）从她身边飞速显现到尽头，
## 停半拍 → 爆裂：只有这一道斩痕（用户 10-30「忍冬的应该只有一道」；3 种斩痕按 vseed 挑）——爆亮再冷却、沿痕冷白粒子从起点往尽头依次爆开 + 狐火橙余烬 + 大灯。
const SZ_FIG := "fx_sz_vulpis"   # 白光人形（本体帧条缺时的回退）
const SZ_WALK := "op_vulpis_walk"   # 忍冬本体（Spine 自产，PRTS 原作骨架 char_4026_vulpis，docs/207 §6.3）：96 画布、foot (48, 76)、朝右
const SZ_CUT := "op_vulpis_slash"
const SZ_FOOT := Vector2(48.0, 76.0)   # 1x 像素；按实际取到的贴图倍率换算（网页包可能是 @1x）
const SZ_CUT_DT := [0.06, 0.06, 0.08, 0.05, 0.10, 0.08, 0.10, 0.12]   # 拔刀斩逐帧时长，出刀帧 f4
const SZ_CUT_HIT := 0.25   # 拔刀开始到出刀帧的秒数（前 4 帧之和）
const SZ_SC := 1.25   # 忍冬比队员略大一点，一眼认得出是她出手
const SZ_SLASH := ["fx_sz_slash1", "fx_sz_slash2", "fx_sz_slash3"]
const SZ_RSLASH := ["fx_sz_rslash1", "fx_sz_rslash2", "fx_sz_rslash3"]   # 忍冬一刀：橙芯红边（用户 10-31「橙色 + 红色」；冷色那份留给幽灵鲨）
const SZ_HOT := Color(1.0, 0.55, 0.22)
const SZ_RED := Color(0.78, 0.1, 0.08)
const SZ_FOX := Color(0.7, 0.42, 0.16)


static func sz_v2(u) -> bool:
	return Bal.v("ult/sz_fx_v2", 1.0) > 0.0 and u.fx_ready(SZ_RSLASH[0])


## 忍冬本体帧条到了没有（用户 10-30「忍冬刚出现不能说是发光的，得能看出人，然后是走路进场，一刀砍过去」）
static func sz_body(u) -> bool:
	return Bal.v("ult/sz_body_v2", 1.0) > 0.0 and u.fx_ready(SZ_WALK) and u.fx_ready(SZ_CUT)


## 本体版的现身段长度：用户 10-31 改为不走路（现身 → 停半拍 → 化光闪出），和原来一样 ult/su_appear（0.3 秒），不再加长时序
static func sz_tp() -> float:
	return Bal.v("ult/su_appear", 0.3)


static func sz_start(u, a: Dictionary, side: Vector2, tp: float) -> void:
	var vs: float = PF.vseed(u, side)
	a["sz_vs"] = vs
	if sz_body(u):   # 本体版（用户 10-31）：她在铃兰身旁现身（本人形象）→ 停半拍、拔刀蓄势 → 化作一道光闪出去
		var d: Vector2 = a.d
		a["sz_fs"] = -1.0 if d.x < -0.05 else 1.0
		var out: Vector2 = (side - Vector2(a.org)).normalized()
		var stand: Vector2 = side + out * 50.0   # 站位离铃兰再远一点，不和她的身体叠在一起
		a["sz_stand"] = stand
		a["sz_cut"] = u.strip(SZ_CUT, stand, {"o": SZ_FOOT * A.hires_of(u._strip_tex(SZ_CUT)), "sc": SZ_SC, "f": 0, "sx": float(a.sz_fs), "life": tp + 0.3,
			"col": Color(1, 1, 1, 0.0)})
		a["sz_dim"] = {"kind": "circle", "c": stand, "r": 2600.0, "col": Color(0.0, 0.0, 0.03), "fill": 0.0, "hold": true, "life": tp + 1.0}   # 全局压暗（用户 10-31「突出忍冬」）
		u.shape(a.sz_dim)
		a.sz_cut["life"] = tp + 1.0
		u.shapes.erase(a.sz_cut)
		u.shapes.append(a.sz_cut)   # 忍冬画在压暗层上面
		u.light(stand + Vector2(0, -40), 140.0, Color(0.85, 0.82, 0.7), tp)
		return
	# 入场（用户 10-30「要把忍冬的入场停顿做出来，得让玩家知道是她来出手」）：周围压暗一圈 → 她放大现身 → 到位那一刻顿帧 ult/sz_appear_stop
	a["sz_dim"] = {"kind": "circle", "c": side + Vector2(0, -30), "r": 150.0, "col": Color(0.0, 0.0, 0.03), "fill": 0.0, "life": tp + 0.08}
	u.shape(a.sz_dim)
	if u.fx_ready(SZ_FIG):
		var t: Texture2D = u._strip_tex(SZ_FIG)
		a["sz_fig"] = u.strip(SZ_FIG, side, {"o": Vector2(t.get_width() / 2.0, t.get_height() - 3.0), "sc": 1.7, "life": tp + 0.06, "col": Color(1, 1, 1, 0.0),
			"sx": -1.0 if Vector2(a.d).x < 0.0 else 1.0})
	u.light(side + Vector2(0, -40), 140.0, Color(0.85, 0.82, 0.7), tp + 0.1)
	for q in 5:
		u.grain("mote_up", side + Vector2((PF.h(vs + q) - 0.5) * 60.0, -10.0 - 70.0 * PF.h(vs + q * 3.0)), Vector2.UP, Color(0.85, 0.75, 0.5), 2)


## 本体版每帧（现身段）：前 35% 淡入现身 → 到位顿帧停半拍 + 狐火 → 剩下的时间拔刀蓄势（逐帧 f0–f3）
static func sz_body_step(u, a: Dictionary, t: float, tp: float) -> void:
	if not a.has("sz_cut"):
		return
	var k: float = clampf(t / (tp * 0.35), 0.0, 1.0)
	a.sz_cut.col = Color(1, 1, 1, k)
	a.sz_dim.fill = 0.6 * k
	a.sz_dim.age = 0.0
	if k >= 1.0 and not a.has("sz_pop"):
		a["sz_pop"] = t
		var side: Vector2 = a.sz_stand
		u.g.vfx.stop(0.06, "ult", true)
		u.prep_slow(Bal.v("ult/sz_prep_slow_t", 0.55), Bal.v("ult/sz_prep_slow", 0.3))   # 预备式慢动作：拔刀蓄势那段放慢（演出类，不改模拟）
		u.light(side + Vector2(0, -40), 180.0, Color(0.85, 0.6, 0.42), 0.3)
		PF.particles(u, side + Vector2(0, -30), 24, "ult_ember", [SZ_FOX, SZ_RED], 0.0, float(a.sz_vs) + 7.0, 70.0)
	a.sz_cut.f = clampi(int(clampf((t - tp * 0.35) / (tp * 0.65), 0.0, 0.999) * 4.0), 0, 3)


## 现身期间每帧：前 35% 淡入 + 周围压暗；到位那一刻顿帧 + 亮一下 + 狐火迸开
static func sz_appear(u, a: Dictionary, t: float, tp: float) -> void:
	if a.has("sz_stand"):
		sz_body_step(u, a, t, tp)
		return
	var k: float = clampf(t / (tp * 0.35), 0.0, 1.0)
	if a.has("sz_fig"):
		var b: float = 1.0 + (0.25 if a.has("sz_pop") and t - float(a.sz_pop) < 0.06 else 0.0)
		a.sz_fig.col = Color(b, b, b, k * 0.95)
	a.sz_dim.fill = 0.4 * k
	if k >= 1.0 and not a.has("sz_pop"):
		a["sz_pop"] = t
		var side: Vector2 = a.side
		u.g.vfx.stop(Bal.v("ult/sz_appear_stop", 0.22), "ult", true)   # 画面层顿帧，不改模拟步长
		u.light(side + Vector2(0, -50), 200.0, Color(0.8, 0.78, 0.68), 0.3)
		PF.particles(u, side + Vector2(0, -40), 40, "ult_ember", [SZ_FOX, Color(0.62, 0.55, 0.36)], 0.0, float(a.sz_vs) + 7.0, 80.0)


static func _sz_slash(u, name: String, p: Vector2, ang: float, L: float, opt: Dictionary) -> Dictionary:
	var t: Texture2D = u._strip_tex(name)
	var s := {"ang": ang, "o": Vector2(0.0, t.get_height() * 0.5), "sx": L / PF.tex_w(u, name)}
	s.merge(opt)
	return u.strip(name, p, s)


## 一刀（用户 10-31「切回一刀，杀手快准狠」）：化光闪出那一下斩痕几乎一帧伸满、细而锐；停半拍后只在这一道上爆亮、
## 上下错开成两半（斩开），沿线只迸几颗火星，地上留一道暗红刀口。不加副斩、不铺爆点。
static func sz_dash(u, a: Dictionary, side: Vector2, tip: Vector2, stall: float) -> void:
	var vs: float = float(a.sz_vs)
	if a.has("sz_stand"):
		side = Vector2(a.sz_stand) + Vector2(0, -24)   # 刀口高度
		if a.has("sz_cut"):   # 化光闪出：人形亮成橙白一闪即消，沿斩向拖两层橙红残影
			var cs: Dictionary = a.sz_cut
			cs.col = Color(1.6, 1.3, 1.1, 1.0)
			cs.f = 4
			cs.max = float(cs.age) + 0.05
			if a.has("sz_dim"):   # 压暗撤掉
				a.sz_dim.max = float(a.sz_dim.age) + 0.1
				a.sz_dim["hold"] = false
			var dd: Vector2 = (tip - side).normalized()
			for g in 2:
				u.strip(SZ_CUT, Vector2(a.sz_stand) + dd * 60.0 * (g + 1), {"o": cs.o, "sc": SZ_SC, "f": 4, "sx": float(a.sz_fs) * (1.0 + 0.5 * (g + 1)),
					"life": 0.07, "fade": 0.07, "delay": 0.01 * g, "col": Color(1.0, 0.45, 0.25, 0.5 - 0.2 * g)})
	if a.has("sz_fig"):
		a.sz_fig.max = float(a.sz_fig.age) + 0.06
	var name: String = PF.pick(u, SZ_RSLASH, vs)
	var L: float = side.distance_to(tip)
	var ang: float = (tip - side).angle()
	a["sz_main"] = _sz_slash(u, name, side, ang, L, {"sy": 0.5, "rev": 0.03, "rev0": 0.0, "life": stall + 0.12, "col": Color(1.05, 0.95, 0.9, 1.0)})
	u.light(side.lerp(tip, 0.5), 200.0, SZ_HOT, 0.12)


static func sz_boom(u, a: Dictionary, org: Vector2, d: Vector2, bk: float, L: float, hw: float) -> void:
	var vs: float = float(a.sz_vs) + 50.0
	var a0: Vector2 = org - d * bk
	var b0: Vector2 = org + d * L
	var ang: float = d.angle()
	var sname: String = PF.pick(u, SZ_RSLASH, vs)
	if a.has("sz_main"):
		var m: Dictionary = a.sz_main
		a0 = m.c
		ang = float(m.ang)
		b0 = a0 + Vector2.from_angle(ang) * float(m.sx) * PF.tex_w(u, str(m.name))
		sname = str(m.name)
		m.max = float(m.age)
	var SL: float = a0.distance_to(b0)
	var dv: Vector2 = Vector2.from_angle(ang)
	var nv: Vector2 = dv.orthogonal()
	# 这一道爆亮（冲击帧）：橙白 → 暗红迅速冷却
	_sz_slash(u, sname, a0, ang, SL, {"sy": 0.95, "life": 0.3, "fade": 0.18, "col": Color(1.15, 0.85, 0.7, 1.0), "col1": Color(0.55, 0.04, 0.04, 0.9), "cold": 0.14, "hf": true})
	# 斩开：上下两半往两边错开、同时沿刀向滑一点
	for sd in [1.0, -1.0]:
		_sz_slash(u, sname, a0 + nv * sd * 4.0, ang, SL, {"sy": 0.45 * sd, "delay": 0.04, "life": 0.26, "fade": 0.2, "v": nv * sd * 70.0 + dv * 60.0 * sd,
			"col": Color(1.0, 0.5, 0.3, 0.9), "col1": Color(0.5, 0.03, 0.03, 0.7), "cold": 0.16})
	# 刀口：地上一道暗红细痕，慢慢褪
	_sz_slash(u, sname, a0, ang, SL, {"layer": "back", "sy": 0.32, "delay": 0.04, "life": 1.6, "fade": 0.7, "col": Color(0.32, 0.03, 0.03, 0.9)})
	# 刀痕爆裂（用户 10-31「最后接一个刀痕爆裂」→「喷溅去掉，要收敛但冲击力足」）：不加任何喷溅，力量全靠一条线上的反差——
	# 斩开后周围再压暗静一拍，刀口独亮；然后整条刀痕一下子绷开（一帧白热细芯 + 爆宽橙红 + 顿帧），立刻收回成更深更宽的刀口
	var TB: float = Bal.v("ult/sz_rupt_t", 0.32)
	u.shape({"kind": "circle", "c": a0.lerp(b0, 0.5), "r": 2600.0, "col": Color(0.0, 0.0, 0.02), "fill": 0.35, "hold": true, "delay": 0.14, "life": TB - 0.14})   # 静一拍：压暗
	_sz_slash(u, sname, a0, ang, SL, {"sy": 0.32, "delay": 0.14, "life": TB - 0.14, "col": Color(0.75, 0.12, 0.08, 0.95)})   # 刀口在压暗层上独亮
	_sz_slash(u, sname, a0, ang, SL, {"sy": 1.35, "delay": TB, "life": 0.2, "fade": 0.14,
		"col": Color(1.2, 0.7, 0.45, 1.0), "col1": Color(0.6, 0.04, 0.04, 0.9), "cold": 0.1})   # 绷开：爆宽后收
	u.shape({"kind": "band", "a": a0, "b": b0, "w": 8.0, "col": Color(0.9, 0.82, 0.7), "fill": 0.85, "life": 0.05, "delay": TB})   # 白热细芯一帧（≤ 0.9）
	u.stop_later(TB, Bal.v("ult/sz_rupt_stop", 0.1))
	_sz_slash(u, sname, a0, ang, SL, {"layer": "back", "sy": 0.5, "delay": TB, "life": 1.2, "fade": 0.8, "col": Color(0.26, 0.02, 0.02, 0.95)})   # 收成更深更宽的刀口
	u.light(a0.lerp(b0, 0.5), SL * 0.45, SZ_RED, 0.22)
	for k in 3:   # 只迸几颗火星：刀口三处
		var hh: float = PF.h(vs + k * 3.7)
		var p: Vector2 = a0.lerp(b0, (k + 0.3 + 0.4 * hh) / 3.0)
		PF.particles(u, p, 18, "ult_burst_s", [SZ_HOT, SZ_RED], 0.02 * k, vs + k, 50.0)


# ================================================================ 水月 · 水母群（ult/mz_jelly，协调人 10-30 转用户「做个大概的给我看看」：粗稿）
## 半透明发光水母从地底缓缓升起、触手像丝带慢慢飘；横扫打到的敌人由最近的水母伸丝带触手贴上去，光沿触手一节节传过去；
## 到原来「小触手抓漏网」那一刻所有水母同步一闪爆开，然后慢慢飘散淡出。节奏慢、要美，和别人的大砸大爆反差。
## 判定 / 时序 / 伤害照旧（横扫扇区、抓漏网都还在原时刻），只是画法换掉：大触手、钻洞、小触手不画。
const MZ_JELLY := ["fx_mz_jelly1", "fx_mz_jelly2", "fx_mz_jelly3"]
const MZ_JN := 9
const MZ_RIB_N := 10   # 丝带段数
const MZ_RIB_MAX := 10
const MZ_GLOW := Color(0.55, 0.9, 0.95)


static func mz_jelly(u) -> bool:
	return Bal.v("ult/mz_jelly", 1.0) > 0.0 and u.fx_ready(MZ_JELLY[0])


static func mz_jelly_start(u, a: Dictionary, c: Vector2, a0: float, span: float, R: float) -> void:
	var vs: float = PF.vseed(u, c)
	a["jl"] = []
	a["jl_vs"] = vs
	a["jl_rib"] = []
	for i in MZ_JN:
		var hh: float = PF.h(vs + i * 4.7)
		var ang: float = a0 + span * (float(i) + 0.2 + 0.6 * hh) / MZ_JN
		var p: Vector2 = c + Vector2.from_angle(ang) * R * (0.3 + 0.55 * PF.h(vs + i * 9.1))
		var name := PF.pick(u, MZ_JELLY, vs + i * 1.3)
		var t: Texture2D = u._strip_tex(name)
		var sc: float = (105.0 + 45.0 * PF.h(vs + i * 2.2)) / (PF.tex_w(u, name) * t.get_height() / t.get_width())   # 按高度定大小（三种水母宽窄不一）
		var fs: float = -1.0 if PF.h(vs + i * 6.6) < 0.5 else 1.0
		var s: Dictionary = u.strip(name, p + Vector2(0, 40), {"o": Vector2(t.get_width() * 0.5, t.get_height() * 0.22), "sc": sc, "sx": fs, "life": 4.0, "col": Color(1, 1, 1, 0.0)})
		a.jl.append({"s": s, "p": p, "ph": hh * TAU, "d0": 0.04 * i + 0.1 * hh, "fs": fs, "sc": sc})
		u.shape({"kind": "circle", "c": p + Vector2(0, 30), "r": 26.0, "col": Color(0.02, 0.04, 0.08), "fill": 0.45, "life": 0.8, "delay": 0.04 * i, "layer": "back"})   # 冒出的地面暗斑
		PF.particles(u, p + Vector2(0, 30), 20, "ult_burst_s", [MZ_INK], 0.04 * i, vs + i, 50.0)
	# 用户 10-31：不贴触手、不收拢；到原「抓漏网」时刻全部水母在各自位置一起炸开（顿帧 + 冲击帧）
	a["jl_c1"] = float(a.T0) + float(a.T) + 0.12
	a["jl_dim"] = {"kind": "circle", "c": c, "r": 2600.0, "col": Color(0.0, 0.01, 0.03), "fill": 0.0, "hold": true, "life": 9.0}   # 压缩时全屏渐暗（蓄力反差）
	u.shape(a.jl_dim)
	for j in a.jl:   # 水母画在压暗层上面
		u.shapes.erase(j.s)
		u.shapes.append(j.s)


## 每帧：水母缓升 + 上下漂 + 伞盖一张一缩；炸开前 0.45 秒各自压缩、全屏渐暗
static func mz_jelly_step(u, a: Dictionary, t: float) -> void:
	var bt: float = float(a.get("jl_burst", -1.0))
	if a.has("jl_dim") and bt < 0.0:
		var kd: float = clampf((t - (float(a.jl_c1) - 0.45)) / 0.45, 0.0, 1.0)
		a.jl_dim.fill = 0.5 * kd * kd
		a.jl_dim.age = 0.0
	for j in a.jl:
		var s: Dictionary = j.s
		if s.age >= s.max or bt >= 0.0:
			continue
		var k: float = clampf((t - float(j.d0)) / 0.55, 0.0, 1.0)
		var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
		var ph: float = float(j.ph)
		var kp: float = clampf((t - (float(a.jl_c1) - 0.45)) / 0.45, 0.0, 1.0)   # 炸开前 0.32 秒各自往里压缩（用户 10-31「参考上一稿的压缩爆炸」）
		var kq: float = kp * kp
		s.c = Vector2(j.p) + Vector2(0, 40.0 * (1.0 - ke) + 5.0 * sin(t * 2.2 + ph))
		var pulse: float = sin(t * (5.0 + 20.0 * kp) + ph)
		s.sc = float(j.sc) * lerpf(1.0, 0.4, kq)
		s.sy = 1.0 + 0.08 * pulse
		s.sx = float(j.fs) * (1.0 - 0.05 * pulse)
		var b: float = 1.0 + 0.5 * kq
		s.col = Color(b, b, b, 0.78 * ke)
		if kp > 0.0:
			if not j.has("core"):
				j["core"] = {"kind": "circle", "c": s.c, "r": 4.0, "col": Color(0.6, 0.86, 0.9), "fill": 0.0, "hold": true, "life": 2.0}
				j["ring"] = {"kind": "ring", "c": s.c, "r": 90.0, "w": 4.0, "col": Color(0.2, 0.42, 0.52, 0.0), "hold": true, "life": 2.0}
				u.shape(j.core)
				u.shape(j.ring)
			j.core.c = s.c
			j.core.r = lerpf(4.0, 18.0, kq)
			j.core.fill = 0.85 * kp
			j.ring.c = s.c
			j.ring.r = lerpf(95.0, 18.0, kp)
			j.ring.col = Color(0.22, 0.45, 0.55, 0.7 * kp)
			if int(t * 60.0) % 4 == int(ph) % 4:
				var hq: float = PF.h(ph + t * 9.0)
				u.grain("mote_in", s.c + Vector2.from_angle(hq * TAU) * 70.0, Vector2.from_angle(hq * TAU + PI), MZ_GLOW, 1)
		if int(t * 60.0) % 9 == int(ph * 3.0) % 9:
			u.grain("mote_up", s.c, Vector2.UP, MZ_GLOW, 1)


static func _mz_rib_pose(u, a: Dictionary, r: Dictionary, t: float) -> void:
	var j: Dictionary = r.j
	var p0: Vector2 = Vector2(j.s.c) + Vector2(0, 26)
	var p1: Vector2 = r.e
	var nrm: Vector2 = (p1 - p0).orthogonal().normalized()
	var ph: float = float(j.ph)
	var mid: Vector2 = p0.lerp(p1, 0.5) + nrm * (36.0 * sin(t * 3.0 + ph) + 20.0)
	var age: float = t - float(r.t0)
	var reveal: float = clampf(age / 0.15, 0.0, 1.0) * MZ_RIB_N
	var pk: float = (age - 0.12) / 0.3 * MZ_RIB_N   # 光传到哪一节
	var q0: Vector2 = p0
	for i in MZ_RIB_N:
		var kk: float = float(i + 1) / MZ_RIB_N
		var wob: Vector2 = nrm * 6.0 * sin(t * 6.0 + i * 0.9 + ph) * kk
		var q1: Vector2 = p0.lerp(mid, kk).lerp(mid.lerp(p1, kk), kk) + wob
		var sg: Dictionary = r.segs[i]
		sg.a = q0
		sg.b = q1
		var lit: float = clampf(1.0 - absf(float(i) - pk) / 1.6, 0.0, 1.0)
		var al: float = 0.0 if float(i) >= reveal else 0.5 + 0.45 * lit
		sg.col = Color(0.35 + 0.5 * lit, 0.62 + 0.26 * lit, 0.8 + 0.08 * lit, al)
		sg.w = 2.0 + 2.0 * lit
		q0 = q1
	if pk >= MZ_RIB_N and not r.has("pop"):
		r["pop"] = true
		PF.particles(u, p1, 30, "ult_burst_s", [Color(0.36, 0.6, 0.66), Color(0.5, 0.42, 0.7)], 0.0, float(a.jl_vs) + float(r.t0) * 31.0, 70.0)


## 横扫打到一个敌人（画面）：最近的水母伸一根丝带触手过去
static func mz_jelly_hit(u, a: Dictionary, p: Vector2, t: float) -> void:
	if Bal.v("ult/mz_jelly_rib", 0.0) <= 0.0:   # 用户 10-31：不再贴触手（缺省关）
		return
	if a.jl_rib.size() >= MZ_RIB_MAX:
		return
	var best: Dictionary = a.jl[0]
	var bd: float = INF
	for j in a.jl:
		var dd: float = Vector2(j.p).distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = j
	var segs: Array = []
	for i in MZ_RIB_N:
		var sg := {"kind": "line", "a": p, "b": p, "w": 2.0, "col": Color(0.4, 0.7, 0.85, 0.0), "life": 1.1}
		u.shape(sg)
		segs.append(sg)
	var r := {"j": best, "e": p, "t0": t, "segs": segs}
	a.jl_rib.append(r)
	_mz_rib_pose(u, a, r, t)


## 抓漏网那一刻：所有水母在各自位置同时炸开（用户 10-31「水母一起炸开」）——伞盖一鼓进冲击帧剪影 → 每只一团青紫粒子爆 + 碎环 + 水沫，
## 中心大灯；顿帧 / 冲击帧由框架 impact 给（调用方先把 hf 打开、横扫标 pre，冲击落在这一下）
static func mz_jelly_burst(u, a: Dictionary, c: Vector2, t: float) -> void:
	a["jl_burst"] = t
	var vs: float = float(a.jl_vs) + 77.0
	var R: float = float(a.R)
	var sum := Vector2.ZERO
	for i in a.jl.size():
		var j: Dictionary = a.jl[i]
		var s: Dictionary = j.s
		var p: Vector2 = s.c
		sum += p
		s["hf"] = true   # 冲击帧剪影里是一群水母
		s["sc1"] = float(s.sc) * 1.45
		s["scd"] = float(s.age) + 0.06
		s.col = Color(1.3, 1.35, 1.4, 0.9)
		s.max = float(s.age) + 0.1
		s["fade"] = 0.05
		if j.has("core"):
			j.core.max = 0.0
			j.ring.max = 0.0
		var hh: float = PF.h(vs + i * 3.1)
		u.shape({"kind": "circle", "c": p, "r": 34.0, "col": Color(0.7, 0.88, 0.9), "fill": 0.85, "life": 0.07})   # 每只的爆闪（≤ 0.9）
		PF.particles(u, p, 600, "ult_burst", [Color(0.38, 0.62, 0.68), Color(0.48, 0.4, 0.7)], 0.0, vs + i, 190.0 + 90.0 * hh)
		PF.particles(u, p, 40, "ult_burst_s", [Color(0.55, 0.85, 0.9)], 0.0, vs + i * 7.0, 70.0)
		PF.ring(u, LU_RINGS, p, 10.0, 130.0 + 60.0 * hh, 0.22, 0.5, {"seed": vs + i * 2.0, "layer": "front", "col": Color(0.55, 0.9, 0.95, 0.8), "col1": Color(0.3, 0.28, 0.6, 0.5), "cold": 0.3, "fade": 0.25})
		u.grain("water", p, Vector2.from_angle(hh * TAU), Color(0.55, 0.85, 0.9), 8)
		u.light(p, 110.0, Color(0.3, 0.55, 0.62), 0.25)
		PF.particles(u, p, 30, "ult_ember", [Color(0.4, 0.66, 0.7)], 0.15 + 0.03 * (i % 3), vs + i * 5.0, 60.0)
	var ctr: Vector2 = sum / maxf(1.0, float(a.jl.size()))
	if a.has("jl_dim"):   # 压暗一下撤掉：暗 → 亮的反差就是冲击
		a.jl_dim.max = 0.0
	u.g.vfx.stop(Bal.v("ult/mz_burst_stop", 0.16), "ult", true)
	for i in a.jl.size():   # 每只一圈碎裂冲击环（外扩先快后慢）+ 逐帧水雾往外翻
		var p2: Vector2 = Vector2(a.jl[i].s.c)
		var hh2: float = PF.h(vs + i * 5.7)
		u.shape({"kind": "ring", "c": p2, "r": 150.0 + 60.0 * hh2, "r1": 20.0, "w": 6.0, "col": Color(0.55, 0.85, 0.92, 0.85), "life": 0.4, "frag": true})
		PF.dust(u, p2, 130.0 + 60.0 * hh2, 0.02, vs + i * 3.0, Vector2.from_angle(hh2 * TAU) * 40.0, Color(0.42, 0.6, 0.66))
	u.shape({"kind": "ring", "c": ctr, "r": R * 1.05, "r1": 60.0, "w": 10.0, "col": Color(0.45, 0.75, 0.85, 0.8), "life": 0.55, "frag": true})   # 群心大冲击波
	u.light(ctr, R * 1.1, Color(0.3, 0.55, 0.62), 0.4)
	u.shake(3.0, 0.15)


# ================================================================ 归溟幽灵鲨 · 弹射撕裂（ult/sp_bounce，用户 10-30 新设计）
## 她化成一道红黑剪影，像弹珠一样在敌人之间来回弹射，锯刃每碰到一个就撕开一道口子（撕裂痕 + 血红火花），越弹越快；
## 收尾那一圈落下一把巨型整圈锯（带血色光晕），在敌群中心转一下、锯开后消散。
## 判定 / 时序 / 伤害照旧（每 0.25 秒一圈、圈内全吃）：每圈把这一圈锯到的敌人位置串成弹射路线，第 i 圈弹 1 + i/3 下（越弹越快）。
## 弹射线 / 撕裂痕借铃兰的斩痕贴图染成血红 / 暗红；剪影 = 她待机帧第 0 帧染暗红。
const SB_RED := Color(0.85, 0.12, 0.12)
const SB_DARK := Color(0.22, 0.02, 0.04)


static func sp_bounce(u) -> bool:
	return Bal.v("ult/sp_bounce", 1.0) > 0.0 and u.fx_ready(SP_SAW) and u.fx_ready(SZ_SLASH[0])


static func sb_start(u, a: Dictionary, o, c: Vector2) -> void:
	a["sb"] = true
	a["sb_vs"] = PF.vseed(u, c)
	a["sb_cur"] = c
	a["sb_pts"] = []
	var pr: Dictionary = o.portrait() if o.has_method("portrait") else {}
	a["sb_tex"] = str(pr.get("tex", ""))
	a["sb_fr"] = int(pr.get("frames", 1))
	u.light(c, 200.0, Color(0.5, 0.08, 0.1), 0.25)
	PF.particles(u, c, 60, "ult_burst_s", [SB_RED, SB_DARK], 0.0, float(a.sb_vs), 90.0)


## 这一圈锯到的敌人（每圈最多 6 处，同原计数）：记下位置给弹射路线用
static func sb_hit(a: Dictionary, p: Vector2) -> void:
	a.sb_pts.append(p)


## 红黑剪影闪现在 p（life 秒，delay 后出现），朝向 fs
static func _sb_ghost(u, a: Dictionary, p: Vector2, fs: float, delay: float, life: float) -> void:
	var tn: String = a.sb_tex
	if tn == "" or not u.fx_ready(tn):
		return
	var t: Texture2D = u._strip_tex(tn)
	var fw: float = t.get_width() / float(maxi(1, int(a.sb_fr)))
	u.strip(tn, p, {"ux": 0.0, "uw": fw, "o": Vector2(fw * 0.5, t.get_height() * 0.8), "sx": fs, "delay": delay, "life": life, "fade": life * 0.7,
		"col": Color(0.42, 0.04, 0.07, 0.9)})


static func sb_tick(u, a: Dictionary, c: Vector2, R: float, tick: int, n: int) -> void:
	var vs: float = float(a.sb_vs) + tick * 17.0
	var pts: Array = a.sb_pts
	a.sb_pts = []
	var nb: int = 1 + tick / 3   # 越弹越快：一圈 1 → 5 下
	var dt: float = 0.25 / float(nb)
	var cur: Vector2 = a.sb_cur
	for k in nb:
		var p: Vector2
		if k < pts.size():
			p = pts[int(PF.h(vs + k) * pts.size()) % pts.size()] if k > 0 else pts[0]
		else:   # 这圈没锯到几个：弹到圈内按哈希挑的点（角度 / 距离错开）
			p = c + Vector2.from_angle(PF.h(vs + k * 3.1) * TAU) * R * (0.35 + 0.6 * PF.h(vs + k * 7.7))
		if p.distance_to(cur) < 60.0:   # 同一点：往旁边错开
			p += Vector2.from_angle(PF.h(vs + k * 5.3) * TAU) * 120.0
		var dl: float = dt * k
		var ang: float = (p - cur).angle()
		var L: float = maxf(40.0, cur.distance_to(p))
		var name := PF.pick(u, SZ_SLASH, vs + k * 0.9)
		_sz_slash(u, name, cur, ang, L, {"sy": 0.55, "rev": minf(0.06, dt * 0.6), "rev0": 0.05, "delay": dl, "life": 0.3, "fade": 0.2,
			"col": Color(0.95, 0.2, 0.2, 0.95), "col1": Color(0.15, 0.02, 0.03, 0.8), "cold": 0.18})   # 弹射线：血红 → 暗红黑
		_sb_ghost(u, a, p, -1.0 if p.x < cur.x else 1.0, dl, 0.16)
		# 撕裂痕：落点一道短而粗的口子（转角按哈希），血红爆亮冷成暗红，留在地上
		var ta: float = ang + PI * 0.5 + (PF.h(vs + k * 2.3) - 0.5) * 1.2
		var tl: float = 70.0 + 60.0 * PF.h(vs + k * 4.4)
		var tn := PF.pick(u, SZ_SLASH, vs + k * 1.7 + 3.0)
		_sz_slash(u, tn, p - Vector2.from_angle(ta) * tl * 0.5, ta, tl, {"layer": "back", "sy": 0.45 * (-1.0 if PF.h(vs + k) < 0.5 else 1.0), "rev": 0.04, "delay": dl + 0.02,
			"life": 0.9, "fade": 0.5, "col": Color(1.0, 0.3, 0.25, 1.0), "col1": SB_DARK, "cold": 0.35})
		PF.particles(u, p, 40, "ult_burst_s", [SB_RED, SP_SPARK[0]], dl, vs + k * 11.0, 80.0)
		# 弹到这里锯一下（用户 10-31「闪出去弹射的时候也要带锯子」）：一把小锯落在落点转一下（缓出放大、快转、淡出）+ 火星
		var rr: float = PF.tex_w(u, SP_SAW) * 0.5
		var sr: float = 80.0 + 24.0 * PF.h(vs + k * 6.1)   # 用户 10-31「小圆锯没看出来，画大一点」
		u.strip(SP_SAW, p + Vector2(0, -6), {"sc": sr * 0.6 / rr, "sc1": sr / rr, "scd": 0.05, "spin": -22.0 * (1.0 if PF.h(vs + k) < 0.6 else -1.0),
			"ang": PF.h(vs + k * 2.2) * TAU, "delay": dl, "life": maxf(0.26, dt + 0.1), "fade": 0.1, "col": Color(1.1, 1.05, 1.05, 1.0)})
		u.strip(SP_SAW, p + Vector2(0, -6), {"sc": sr * 1.15 / rr, "spin": -22.0, "delay": dl, "life": 0.14, "fade": 0.1, "col": Color(1.4, 0.3, 0.3, 0.35)})   # 血色光晕
		u.grain("sh_shard", p, Vector2.from_angle(ang + PI * 0.5), Color(1.0, 0.6, 0.25), 4)
		cur = p
	a.sb_cur = cur
	if tick == n - 1:
		sb_warn(u, a, c, R, pts)
	if tick >= n:
		sb_finale(u, a, c, R, pts)


## 收尾预兆（最后一圈前 0.25 秒）：落点地面阴影一圈圈扩大压暗 + 大锯从上方压下来（越来越近、越转越快），锯缘火星往下掉
static func sb_warn(u, a: Dictionary, c: Vector2, R: float, pts: Array) -> void:
	var ctr: Vector2 = c
	if pts.size() >= 2:
		var sum := Vector2.ZERO
		for p in pts:
			sum += p
		ctr = c.lerp(sum / pts.size(), 0.5)
	a["sb_ctr"] = ctr
	var rr: float = PF.tex_w(u, SP_SAW) * 0.5
	var r1: float = R * 0.75
	var T := 0.25
	u.strip(SP_SAW, ctr + Vector2(0, 6), {"layer": "back", "sc": r1 * 0.4 / rr, "sc1": r1 * 1.05 / rr, "scd": T, "spin": -6.0, "life": T + 0.04,
		"col": Color(0.0, 0.0, 0.02, 0.55)})   # 阴影（锯的剪影压在地上，越来越大）
	u.strip(SP_SAW, ctr + Vector2(0, -170), {"sc": r1 * 1.25 / rr, "sc1": r1 * 1.02 / rr, "scd": T, "spin": -10.0, "v": Vector2(0, 170.0 / T), "life": T,
		"col": Color(0.8, 0.75, 0.78, 0.75)})   # 大锯从上方压下来
	u.light(ctr, r1, Color(0.4, 0.05, 0.08), T)
	for q in 6:
		var hq: float = PF.h(float(a.sb_vs) + q * 4.3)
		u.grain("sh_shard", ctr + Vector2.from_angle(hq * TAU) * r1 * 0.9 + Vector2(0, -120), Vector2.DOWN, Color(1.0, 0.55, 0.25), 2)


## 收尾：巨锯落地——冲击帧（剪影是这把锯）+ 顿帧 → 转一下锯开：血红分叉裂网撕开地面、碎石隆起飞溅、逐帧烟尘，0.3 秒后余震；然后消散
static func sb_finale(u, a: Dictionary, c: Vector2, R: float, pts: Array) -> void:
	var ctr: Vector2 = a.get("sb_ctr", c)
	var rr: float = PF.tex_w(u, SP_SAW) * 0.5
	var r1: float = R * 0.75
	u.strip(SP_SAW, ctr, {"sc": r1 * 1.5 / rr, "sc1": r1 * 1.08 / rr, "scd": 0.18, "spin": -9.0, "life": 0.85, "fade": 0.45,
		"col": Color(1.4, 0.35, 0.35, 0.45)})   # 血色光晕（大一圈、半透明）
	u.strip(SP_SAW, ctr, {"sc": r1 * 1.12 / rr, "sc1": r1 / rr, "scd": 0.06, "spin": -9.0, "life": 0.6, "col": Color(1.05, 1.0, 1.0, 1.0), "hf": true})
	# 收尾（用户 10-31「最后锯子也接一个有表现力的收尾」）：落地后原地狂转磨地 0.5 秒（一圈火星往外甩）→ 收小、飞回她手里
	# 切除（用户 10-31「收招做个冲击力的切除感」）：磨地 0.55 秒后巨锯猛地沿一条直线横切过整片敌群——切口一帧出现、顿 0.12、
	# 切口两侧碎屑往两边喷、地上留一道深切痕慢慢冷却；然后锯收小飞回她手里
	var vs: float = float(a.sb_vs) + 55.0
	var ca: float = PF.h(vs + 77.0) * PI - PI * 0.5
	var cd: Vector2 = Vector2.from_angle(ca)
	var CL: float = R * 2.1
	var cp0: Vector2 = ctr - cd * CL * 0.5
	var T_CUT := 0.6
	u.strip(SP_SAW, ctr, {"sc": r1 / rr, "spin": -30.0, "delay": T_CUT - 0.06, "life": 0.08, "v": cd * CL * 0.5 / 0.08, "col": Color(1.2, 1.1, 1.1, 1.0)})   # 锯冲出去
	var slash: String = PF.pick(u, SZ_SLASH, vs + 5.0)
	_sz_slash(u, slash, cp0, ca, CL, {"sy": 2.4, "delay": T_CUT, "life": 0.5, "fade": 0.3, "col": Color(1.15, 0.95, 0.95, 1.0), "col1": Color(0.6, 0.06, 0.08, 0.9), "cold": 0.2})
	_sz_slash(u, slash, cp0, ca, CL, {"layer": "back", "sy": 1.4, "delay": T_CUT, "life": 2.2, "fade": 1.0, "col": Color(0.3, 0.03, 0.05, 0.95)})   # 深切痕
	u.stop_later(T_CUT, Bal.v("ult/sb_cut_stop", 0.12))
	u.shape({"kind": "band", "a": cp0, "b": cp0 + cd * CL, "w": 46.0, "col": Color(0.85, 0.75, 0.75), "fill": 0.55, "life": 0.06, "delay": T_CUT})   # 切口一闪（≤ 0.85）
	var nv: Vector2 = cd.orthogonal()
	for q in 8:   # 切口两侧碎屑往两边喷
		var hq: float = PF.h(vs + 90.0 + q * 2.7)
		var pq: Vector2 = cp0 + cd * CL * (q + 0.5) / 8.0
		var side: float = 1.0 if q % 2 == 0 else -1.0
		PF.rock(u, pq, nv * side * (140.0 + 120.0 * hq), 150.0 + 100.0 * hq, hq, 0.34, T_CUT, Color(0.95, 0.75, 0.75))
		PF.particles(u, pq, 40, "ult_burst_s", [SB_RED, Color(1.0, 0.55, 0.2)], T_CUT, vs + q * 7.0, 70.0)
	PF.dust(u, ctr, R * 0.9, T_CUT + 0.03, vs + 13.0, Vector2.ZERO, Color(0.4, 0.28, 0.28))
	u.strip(SP_SAW, ctr + cd * CL * 0.5, {"sc": r1 * 0.8 / rr, "spin": -26.0, "delay": T_CUT + 0.14, "life": 0.3, "sc1": r1 * 0.16 / rr, "scd": 0.3,
		"v": (c - (ctr + cd * CL * 0.5)) / 0.3, "col": Color(1.1, 1.0, 1.0, 1.0)})   # 飞回她手里
	for q in 10:
		var hq: float = PF.h(float(a.sb_vs) + q * 3.9)
		var dq: Vector2 = Vector2.from_angle(TAU * (q + hq) / 10.0)
		PF.particles(u, ctr + dq * r1 * 0.95, 30, "ult_burst_s", [Color(1.0, 0.55, 0.2), SB_RED], 0.15 + 0.04 * q, float(a.sb_vs) + q, 60.0)
	u.light(c, 160.0, Color(0.6, 0.1, 0.12), 0.25)
	u.g.vfx.stop(Bal.v("ult/sb_hitstop", 0.16), "ult", true)
	u.light(ctr, r1 * 1.2, Color(0.55, 0.08, 0.1), 0.35)
	PF.particles(u, ctr, 300, "ult_burst", [SB_RED, SB_DARK], 0.12, float(a.sb_vs) + 99.0, r1)
	for q in 7:   # 锯开的口子：一圈不规整的撕裂痕
		var ta: float = TAU * (q + PF.h(vs + q)) / 7.0
		var tl: float = r1 * (0.4 + 0.4 * PF.h(vs + q * 3.0))
		_sz_slash(u, PF.pick(u, SZ_SLASH, vs + q), ctr + Vector2.from_angle(ta) * r1 * 0.3, ta, tl, {"layer": "back", "sy": 0.5, "rev": 0.12, "delay": 0.12,
			"life": 1.0, "fade": 0.5, "col": Color(1.0, 0.3, 0.25, 1.0), "col1": SB_DARK, "cold": 0.4})
	# 地面撕裂 + 碎屑 + 烟尘 + 余震（pixfx §6.6）
	var forks: Array = ["fx_ul_crack_fork", "fx_ul_crack_fork2", "fx_ul_crack_fork3", "fx_ul_crack_fork4"]
	PF.crack_net(u, forks, ctr, r1 * 1.25, 9, PF.h(vs) * TAU, vs, 0.14, Color(1.0, 0.35, 0.3), Color(0.25, 0.05, 0.06), r1 * 0.35)
	PF.heave(u, ctr, r1 * 0.85, vs, 0.02, Color(0.9, 0.8, 0.8))
	PF.heave(u, ctr, r1 * 0.45, vs + 9.0, 0.0, Color(0.9, 0.8, 0.8), 90.0)
	for q in 5:
		var hq: float = PF.h(vs + q * 6.7)
		PF.dust(u, ctr + Vector2.from_angle(TAU * (q + hq) / 5.0) * r1 * (0.6 + 0.4 * hq), 110.0 + 60.0 * hq, 0.04 * q, vs + q,
			Vector2.from_angle(TAU * (q + hq) / 5.0) * 60.0, Color(0.55, 0.45, 0.45) if q % 2 == 0 else Color(0.3, 0.22, 0.22))
	PF.aftershock(u, ctr, r1, vs + 3.0, 0.3, 10, Color(0.9, 0.8, 0.8))
	u.shake(3.0, 0.15)
