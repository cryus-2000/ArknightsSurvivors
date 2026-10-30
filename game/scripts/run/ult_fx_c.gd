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
const SZ_COLD := Color(0.5, 0.58, 0.66)
const SZ_PALE := Color(0.62, 0.66, 0.7)
const SZ_FOX := Color(0.7, 0.42, 0.16)


static func sz_v2(u) -> bool:
	return Bal.v("ult/sz_fx_v2", 1.0) > 0.0 and u.fx_ready(SZ_SLASH[0])


## 忍冬本体帧条到了没有（用户 10-30「忍冬刚出现不能说是发光的，得能看出人，然后是走路进场，一刀砍过去」）
static func sz_body(u) -> bool:
	return Bal.v("ult/sz_body_v2", 1.0) > 0.0 and u.fx_ready(SZ_WALK) and u.fx_ready(SZ_CUT)


## 本体版的现身段长度：走路 ult/sz_walk 秒 + 拔刀到出刀帧（瞬身那一下落在出刀帧）
static func sz_tp() -> float:
	return Bal.v("ult/sz_walk", 0.3) + SZ_CUT_HIT


static func sz_start(u, a: Dictionary, side: Vector2, tp: float) -> void:
	var vs: float = PF.vseed(u, side)
	a["sz_vs"] = vs
	if sz_body(u):   # 本体版：从铃兰身后走进来 → 到位停半拍 → 拔刀一刀
		var d: Vector2 = a.d
		a["sz_fs"] = -1.0 if d.x < -0.05 else 1.0
		var out: Vector2 = (side - Vector2(a.org)).normalized()
		var stand: Vector2 = side + out * 50.0   # 站位离铃兰再远一点，不和她的身体叠在一起
		a["sz_stand"] = stand
		a["sz_w0"] = stand + out * Bal.v("ult/sz_walk_dist", 150.0)   # 从外侧横着走进来
		var wd: Vector2 = stand - Vector2(a.sz_w0)
		a["sz_walker"] = u.strip(SZ_WALK, a.sz_w0, {"o": SZ_FOOT * A.hires_of(u._strip_tex(SZ_WALK)), "sc": SZ_SC, "loop": true, "fps": 16.0,
			"life": Bal.v("ult/sz_walk", 0.3) + 0.02, "sx": -1.0 if wd.x < 0.0 else 1.0})
		a["sz_dim"] = {"kind": "circle", "c": side + Vector2(0, -30), "r": 170.0, "col": Color(0.0, 0.0, 0.03), "fill": 0.0, "life": tp + 0.5}
		u.shape(a.sz_dim)
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


## 本体版每帧（整段都调）：走路缓停到位 → 到位那一刻顿帧（停半拍）+ 狐火 → 拔刀斩逐帧（出刀帧 = 瞬身）→ 收刀淡出
static func sz_body_step(u, a: Dictionary, t: float) -> void:
	var tw: float = Bal.v("ult/sz_walk", 0.3)
	var side: Vector2 = a.sz_stand
	if t < tw:
		var k: float = clampf(t / tw, 0.0, 1.0)
		a.sz_walker.c = Vector2(a.sz_w0).lerp(side, 1.0 - (1.0 - k) * (1.0 - k))   # 走到跟前放慢
		a.sz_dim.fill = 0.35 * k
		return
	if not a.has("sz_cut"):
		a.sz_walker.max = float(a.sz_walker.age)
		var tot: float = 0.0
		for x in SZ_CUT_DT:
			tot += float(x)
		a["sz_cut"] = u.strip(SZ_CUT, side, {"o": SZ_FOOT * A.hires_of(u._strip_tex(SZ_CUT)), "sc": SZ_SC, "f": 0, "sx": float(a.sz_fs), "life": tot + 0.3, "fade": 0.3})
		a["sz_c0"] = t
		u.g.vfx.stop(Bal.v("ult/sz_appear_stop", 0.22), "ult", true)   # 停半拍：画面层顿帧，不改模拟步长
		u.light(side + Vector2(0, -40), 180.0, Color(0.8, 0.78, 0.68), 0.3)
		PF.particles(u, side + Vector2(0, -30), 40, "ult_ember", [SZ_FOX, Color(0.62, 0.55, 0.36)], 0.0, float(a.sz_vs) + 7.0, 80.0)
	var e: float = t - float(a.sz_c0)
	var f: int = 0
	var acc: float = 0.0
	for i in SZ_CUT_DT.size():
		acc += float(SZ_CUT_DT[i])
		if e < acc:
			break
		f = mini(i + 1, SZ_CUT_DT.size() - 1)
	a.sz_cut.f = f
	a.sz_dim.fill = 0.35 * clampf(1.0 - (e - 0.4) / 0.3, 0.0, 1.0)


## 现身期间每帧：前 35% 淡入 + 周围压暗；到位那一刻顿帧 + 亮一下 + 狐火迸开
static func sz_appear(u, a: Dictionary, t: float, tp: float) -> void:
	if a.has("sz_walker"):
		sz_body_step(u, a, t)
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


static func sz_dash(u, a: Dictionary, side: Vector2, tip: Vector2, stall: float) -> void:
	var vs: float = float(a.sz_vs)
	if a.has("sz_stand"):
		side = Vector2(a.sz_stand) + Vector2(0, -24)   # 刀口高度
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
	# 主斩痕爆亮：就在出刀那一道上加粗爆亮（不另起一道，免得两道平行），白 → 冷蓝灰冷却
	var sname: String = PF.pick(u, SZ_SLASH, vs)
	if a.has("sz_main"):
		var m: Dictionary = a.sz_main
		a0 = m.c
		ang = float(m.ang)
		b0 = a0 + Vector2.from_angle(ang) * float(m.sx) * PF.tex_w(u, str(m.name))
		sname = str(m.name)
		m.max = float(m.age)
	_sz_slash(u, sname, a0, ang, a0.distance_to(b0), {"sy": 1.15, "life": 0.55, "fade": 0.3, "col": Color(1.05, 1.05, 1.05, 1.0), "col1": Color(0.45, 0.55, 0.7, 0.8), "cold": 0.35})
	u.light(org + d * (L - bk) * 0.5, maxf(L, hw) * 0.7, SZ_PALE, 0.3)
	var n: int = 7 + int(PF.h(vs) * 3.0)   # 7–9 处爆点，从斩痕起点往尽头一节节依次炸开（预审 10-30：同时炸连成一片）
	for k in n:
		var hh: float = PF.h(vs + k * 3.7)
		var x: float = lerpf(30.0 - bk, L - 30.0, (k + 0.2 + 0.6 * hh) / n)
		var p: Vector2 = org + d * x + d.orthogonal() * (hh - 0.5) * hw * 0.25
		var dl: float = 0.035 * k + 0.015 * hh
		PF.particles(u, p, 60, "ult_burst_s", [SZ_COLD, SZ_PALE], dl, vs + k)
		if k % 2 == 1:
			continue
		PF.particles(u, p, 40, "ult_ember", [SZ_FOX], dl + 0.08, vs + k * 5.0, 90.0)
	PF.particles(u, org + d * (L - bk) * 0.5, 300, "ult_burst", [SZ_COLD, SZ_PALE], 0.12, vs + 99.0, minf(hw, L) * 0.45)



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
	# 压缩点：水母群的重心往水月那边拉一点；压缩从横扫后段开始，到原「抓漏网」时刻炸开
	var sum := Vector2.ZERO
	for j in a.jl:
		sum += Vector2(j.p)
	a["jl_core"] = (sum / a.jl.size()).lerp(c, 0.25)
	a["jl_c0"] = float(a.T0) + float(a.T) * 0.55
	a["jl_c1"] = float(a.T0) + float(a.T) + 0.12


## 每帧：水母缓升 + 上下漂 + 伞盖一张一缩；丝带触手跟着飘、光往敌人那头一节节传
static func mz_jelly_step(u, a: Dictionary, t: float) -> void:
	var bt: float = float(a.get("jl_burst", -1.0))
	for j in a.jl:
		var s: Dictionary = j.s
		if s.age >= s.max:
			continue
		var k: float = clampf((t - float(j.d0)) / 0.55, 0.0, 1.0)
		var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
		var ph: float = float(j.ph)
		# 压缩：横扫后段起，水母被吸向压缩点、越缩越小越亮（先慢后快）
		var kc: float = clampf((t - float(a.jl_c0)) / (float(a.jl_c1) - float(a.jl_c0)), 0.0, 1.0)
		var kq: float = kc * kc
		var home: Vector2 = Vector2(j.p) + Vector2(0, 40.0 * (1.0 - ke) + 5.0 * sin(t * 2.2 + ph))
		s.c = home.lerp(Vector2(a.jl_core), kq)
		var pulse: float = sin(t * (5.0 + 10.0 * kc) + ph)
		s.sc = float(j.sc) * lerpf(1.0, 0.3, kq)
		s.sy = 1.0 + 0.08 * pulse
		s.sx = float(j.fs) * (1.0 - 0.05 * pulse)
		var b: float = 1.0 + 0.3 * kq
		s.col = Color(b, b, b, 0.78 * ke)
		if int(t * 60.0) % 9 == int(ph * 3.0) % 9:
			u.grain("mote_up", s.c, Vector2.UP, MZ_GLOW, 1)
	for r in a.jl_rib:
		_mz_rib_pose(u, a, r, t)
	# 压缩点：亮核越聚越亮、一圈暗压力环往里收
	if bt < 0.0 and t >= float(a.jl_c0):
		var kc2: float = clampf((t - float(a.jl_c0)) / (float(a.jl_c1) - float(a.jl_c0)), 0.0, 1.0)
		if not a.has("jl_cs"):
			a["jl_cs"] = {"kind": "circle", "c": a.jl_core, "r": 8.0, "col": Color(0.6, 0.85, 0.88), "fill": 0.0, "life": 2.0}
			a["jl_cr"] = {"kind": "ring", "c": a.jl_core, "r": 300.0, "w": 6.0, "col": Color(0.15, 0.3, 0.4, 0.0), "life": 2.0}
			u.shape(a.jl_cs)
			u.shape(a.jl_cr)
		a.jl_cs.r = lerpf(8.0, 46.0, kc2 * kc2)
		a.jl_cs.fill = 0.9 * kc2
		a.jl_cs.age = 0.0
		a.jl_cr.r = lerpf(300.0, 50.0, kc2)
		a.jl_cr.col = Color(0.2, 0.45, 0.55, 0.7 * kc2)
		a.jl_cr.age = 0.0
		if int(t * 60.0) % 2 == 0:
			var hq: float = PF.h(float(a.jl_vs) + t * 7.0)
			u.grain("mote_in", Vector2(a.jl_core) + Vector2.from_angle(hq * TAU) * 160.0, Vector2.from_angle(hq * TAU + PI), MZ_GLOW, 2)


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


## 抓漏网那一刻：所有水母同步一闪爆开（光点粒子 + 灯），之后慢慢飘散淡出
static func mz_jelly_burst(u, a: Dictionary, c: Vector2, t: float) -> void:
	a["jl_burst"] = t
	var vs: float = float(a.jl_vs) + 77.0
	var core: Vector2 = a.jl_core
	var R: float = float(a.R)
	for j in a.jl:   # 水母全被吞进核里
		j.s.max = float(j.s.age) + 0.04
	if a.has("jl_cs"):
		a.jl_cs.max = 0.0
		a.jl_cr.max = 0.0
	u.g.vfx.stop(Bal.v("ult/mz_jelly_stop", 0.1), "ult", true)   # 炸开前顿一下（画面层）
	u.shape({"kind": "circle", "c": core, "r": 90.0, "col": Color(0.75, 0.9, 0.92), "fill": 0.85, "life": 0.12})   # 爆闪（≤ 0.92）
	u.light(core, R * 0.9, Color(0.25, 0.45, 0.5), 0.4)
	PF.ring(u, LU_RINGS, core, 40.0, R * 0.85, 0.3, 0.7, {"seed": vs, "layer": "front", "col": Color(0.6, 0.95, 1.0, 0.9), "col1": Color(0.3, 0.3, 0.6, 0.6), "cold": 0.4, "fade": 0.4})
	PF.ring(u, LU_RINGS, core, 30.0, R * 0.6, 0.38, 0.6, {"seed": vs + 9.0, "col": Color(0.55, 0.45, 0.85, 0.6), "fade": 0.35, "delay": 0.05})
	PF.particles(u, core, 420, "ult_burst", [Color(0.38, 0.62, 0.68), Color(0.48, 0.4, 0.7)], 0.0, vs, R * 0.85)
	PF.particles(u, core, 300, "ult_burst", [Color(0.3, 0.55, 0.6)], 0.07, vs + 3.0, R * 0.55)
	for q in 6:   # 余光：一圈小光点慢慢往上飘
		var p: Vector2 = core + Vector2.from_angle(TAU * (q + PF.h(vs + q)) / 6.0) * R * (0.25 + 0.3 * PF.h(vs + q * 2.0))
		PF.particles(u, p, 30, "ult_ember", [Color(0.4, 0.66, 0.7)], 0.15 + 0.03 * q, vs + q * 5.0, 80.0)


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
		cur = p
	a.sb_cur = cur
	if tick >= n:
		sb_finale(u, a, c, R, pts)


## 收尾：巨型整圈锯在敌群中心落下、转一下锯开，血色光晕，然后消散
static func sb_finale(u, a: Dictionary, c: Vector2, R: float, pts: Array) -> void:
	var ctr: Vector2 = c
	if pts.size() >= 2:
		var sum := Vector2.ZERO
		for p in pts:
			sum += p
		ctr = c.lerp(sum / pts.size(), 0.5)
	var rr: float = PF.tex_w(u, SP_SAW) * 0.5
	var r1: float = R * 0.75
	u.strip(SP_SAW, ctr, {"sc": r1 * 1.5 / rr, "sc1": r1 * 1.08 / rr, "scd": 0.18, "spin": -9.0, "life": 0.85, "fade": 0.45,
		"col": Color(1.4, 0.35, 0.35, 0.45)})   # 血色光晕（大一圈、半透明）
	u.strip(SP_SAW, ctr, {"sc": r1 * 1.4 / rr, "sc1": r1 / rr, "scd": 0.18, "spin": -9.0, "life": 0.85, "fade": 0.4, "col": Color(1.05, 1.0, 1.0, 1.0)})
	u.g.vfx.stop(Bal.v("ult/sb_hitstop", 0.1), "ult", true)
	u.light(ctr, r1 * 1.2, Color(0.55, 0.08, 0.1), 0.35)
	PF.particles(u, ctr, 300, "ult_burst", [SB_RED, SB_DARK], 0.12, float(a.sb_vs) + 99.0, r1)
	var vs: float = float(a.sb_vs) + 55.0
	for q in 7:   # 锯开的口子：一圈不规整的撕裂痕
		var ta: float = TAU * (q + PF.h(vs + q)) / 7.0
		var tl: float = r1 * (0.4 + 0.4 * PF.h(vs + q * 3.0))
		_sz_slash(u, PF.pick(u, SZ_SLASH, vs + q), ctr + Vector2.from_angle(ta) * r1 * 0.3, ta, tl, {"layer": "back", "sy": 0.5, "rev": 0.12, "delay": 0.12,
			"life": 1.0, "fade": 0.5, "col": Color(1.0, 0.3, 0.25, 1.0), "col1": SB_DARK, "cold": 0.4})
