## pixfx 第三组：归溟幽灵鲨 / 流明 / 水月 / 铃兰（docs/199 §7.9，做法见 .claude/skills/pixfx）。
## 只画画面：ult_moves_b / _c 里各人那段在原画法的位置调这里，u.hit、时序、半径、判定都留在原处不动；散布按 PF.h 哈希 / PF.vseed，不抽模拟随机数。
## 每人一个开关（缺省 1；0 = 原程序画法），贴图缺时自动退回旧版。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")


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
			"rev": 0.22 + 0.08 * k, "rev0": 0.05, "life": float(a.t0) + dur + 0.45, "fade": 0.45, "col": Color(1, 1, 1, 0.62 if k == 0 else 0.3)}))
	a["lu_ps"] = ps
	u.shape({"kind": "circle", "c": c, "r": float(a.R), "col": Color(0.0, 0.01, 0.03), "fill": 0.3, "life": float(a.t0) + 0.06, "layer": "back"})   # 升起前压暗
	u.light(c, 160.0, LU_WARM, float(a.t0) + 0.1)
	for q in 6:
		u.grain("mote_up", c + Vector2((PF.h(vs + q) - 0.5) * 90.0, -10.0), Vector2.UP, LU_WARM, 3)


static func lu_boom(u, a: Dictionary, c: Vector2, R: float) -> void:
	var vs: float = float(a.lu_vs)
	u.light(c, R * 1.15, LU_WARM, 0.35)
	PF.ring(u, LU_RINGS, c, 40.0, R, float(a.exp), 0.75, {"seed": vs, "col": Color(1.05, 1.0, 0.85, 0.95), "col1": Color(0.55, 0.78, 0.82, 0.8), "cold": 0.45, "fade": 0.4})
	PF.ring(u, LU_RINGS, c, 30.0, R * 0.8, float(a.exp) * 1.3, 0.6, {"seed": vs + 17.0, "col": Color(0.9, 0.95, 0.95, 0.5), "fade": 0.35, "delay": 0.05})
	PF.particles(u, c, 300, "ult_burst", [LU_PWARM, LU_PAQUA], 0.0, vs, R * 0.95)
	PF.particles(u, c, 120, "ult_ember", [LU_PWARM], 0.1, vs + 3.0, R * 0.5)


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
	PF.particles(u, c, 60, "ult_ember", [LU_PWARM, LU_PAQUA], 0.0, vs, R * 0.85)
	u.light(c, R * 0.9, LU_WARM, 0.15)


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
	if n % 3 == 0:
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
	PF.particles(u, p, 20, "ult_burst_s", [MZ_INK, Color(0.3, 0.34, 0.5)], delay, vs)


# ================================================================ 铃兰：忍冬现身 → 瞬身斩 → 斩痕爆裂（ult/sz_fx_v2）
## 忍冬 = pixgen 白光人形（照 Codex 忍冬关键帧的轮廓），淡入；瞬身 = pixgen 连续冷色斩痕（亮芯 ≤ 0.9、边缘冷蓝灰）从她身边飞速显现到尽头，
## 停半拍 → 爆裂：斩痕爆亮再冷却、沿痕一串冷白粒子爆（错开）+ 横贯带宽的交叉斩（3 种斩痕按 vseed 挑、转角 / 镜像各异）+ 狐火橙余烬 + 大灯。
const SZ_FIG := "fx_sz_vulpis"
const SZ_SLASH := ["fx_sz_slash1", "fx_sz_slash2", "fx_sz_slash3"]
const SZ_COLD := Color(0.5, 0.58, 0.66)
const SZ_PALE := Color(0.62, 0.66, 0.7)
const SZ_FOX := Color(0.7, 0.42, 0.16)


static func sz_v2(u) -> bool:
	return Bal.v("ult/sz_fx_v2", 1.0) > 0.0 and u.fx_ready(SZ_SLASH[0])


static func sz_start(u, a: Dictionary, side: Vector2, tp: float) -> void:
	var vs: float = PF.vseed(u, side)
	a["sz_vs"] = vs
	if u.fx_ready(SZ_FIG):
		var t: Texture2D = u._strip_tex(SZ_FIG)
		a["sz_fig"] = u.strip(SZ_FIG, side, {"o": Vector2(t.get_width() / 2.0, t.get_height() - 3.0), "life": tp + 0.06, "col": Color(1, 1, 1, 0.0),
			"sx": -1.0 if Vector2(a.d).x < 0.0 else 1.0})
	u.light(side + Vector2(0, -40), 140.0, Color(0.85, 0.82, 0.7), tp + 0.1)
	for q in 5:
		u.grain("mote_up", side + Vector2((PF.h(vs + q) - 0.5) * 60.0, -10.0 - 70.0 * PF.h(vs + q * 3.0)), Vector2.UP, Color(0.85, 0.75, 0.5), 2)


## 现身期间每帧：淡入（前 60%）
static func sz_appear(a: Dictionary, t: float, tp: float) -> void:
	if a.has("sz_fig"):
		a.sz_fig.col = Color(1, 1, 1, clampf(t / (tp * 0.6), 0.0, 1.0) * 0.92)


static func _sz_slash(u, name: String, p: Vector2, ang: float, L: float, opt: Dictionary) -> Dictionary:
	var t: Texture2D = u._strip_tex(name)
	var s := {"ang": ang, "o": Vector2(0.0, t.get_height() * 0.5), "sx": L / PF.tex_w(u, name)}
	s.merge(opt)
	return u.strip(name, p, s)


static func sz_dash(u, a: Dictionary, side: Vector2, tip: Vector2, stall: float) -> void:
	var vs: float = float(a.sz_vs)
	if a.has("sz_fig"):
		a.sz_fig.max = float(a.sz_fig.age) + 0.06
	var name: String = PF.pick(u, SZ_SLASH, vs)
	var L: float = side.distance_to(tip)
	var ang: float = (tip - side).angle()
	a["sz_main"] = _sz_slash(u, name, side, ang, L, {"sy": 0.9, "rev": 0.07, "rev0": 0.02, "life": stall + 0.12, "col": Color(1.0, 1.0, 1.0, 0.95)})
	u.light(side.lerp(tip, 0.3), 220.0, SZ_PALE, 0.15)
	for k in 6:   # 瞬身沿途的光屑
		var p: Vector2 = side.lerp(tip, (k + 0.5) / 6.0)
		u.grain("sh_glint", p, Vector2.from_angle(ang), SZ_PALE, 4)


static func sz_boom(u, a: Dictionary, org: Vector2, d: Vector2, bk: float, L: float, hw: float) -> void:
	var vs: float = float(a.sz_vs) + 50.0
	var a0: Vector2 = org - d * bk
	var b0: Vector2 = org + d * L
	var ang: float = d.angle()
	# 主斩痕爆亮：加粗一道，白 → 冷蓝灰冷却
	_sz_slash(u, PF.pick(u, SZ_SLASH, vs), a0, ang, a0.distance_to(b0), {"sy": 1.6, "life": 0.55, "fade": 0.3, "col": Color(1.05, 1.05, 1.05, 1.0), "col1": Color(0.45, 0.55, 0.7, 0.8), "cold": 0.35})
	u.light(org + d * (L - bk) * 0.5, maxf(L, hw) * 0.7, SZ_PALE, 0.3)
	var n: int = 7 + int(PF.h(vs) * 3.0)   # 7–9 处爆点，位置 / 错开按哈希
	for k in n:
		var hh: float = PF.h(vs + k * 3.7)
		var x: float = lerpf(30.0 - bk, L - 30.0, (k + 0.2 + 0.6 * hh) / n)
		var p: Vector2 = org + d * x + d.orthogonal() * (hh - 0.5) * hw * 0.25
		var dl: float = 0.012 * k + 0.02 * hh
		PF.particles(u, p, 60, "ult_burst_s", [SZ_COLD, SZ_PALE], dl, vs + k)
		var sg: float = 1.0 if k % 2 == 0 else -1.0
		var ca: float = d.orthogonal().angle() + sg * (0.3 + 0.35 * PF.h(vs + k * 1.3))
		var cl: float = hw * (1.4 + 0.7 * PF.h(vs + k * 2.9))
		var cd: Vector2 = Vector2.from_angle(ca)
		_sz_slash(u, PF.pick(u, SZ_SLASH, vs + k * 0.7), p - cd * cl * 0.5, ca, cl, {"sy": (0.45 + 0.3 * hh) * (-1.0 if hh < 0.5 else 1.0), "rev": 0.06, "rev0": 0.1,
			"delay": dl, "life": 0.32, "fade": 0.18, "col": Color(1, 1, 1, 0.9), "col1": Color(0.45, 0.55, 0.7, 0.7), "cold": 0.2})
		if k % 3 == 1:
			PF.particles(u, p, 40, "ult_ember", [SZ_FOX], dl + 0.08, vs + k * 5.0, 90.0)
	PF.particles(u, org + d * (L - bk) * 0.5, 300, "ult_burst", [SZ_COLD, SZ_PALE], 0.0, vs + 99.0, minf(hw, L) * 0.6)
