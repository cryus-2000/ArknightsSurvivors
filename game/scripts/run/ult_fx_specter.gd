## 归溟幽灵鲨终结技「弹射撕裂」pixelfx 放开版画法（docs/242；开关 fx/px_unleashed，缺图退回 ult_fx_c.sb_*）。
## 设计不动（用户 10-30 / 10-31 定稿）：红黑剪影在敌人间弹射、每处落一把小锯 → 最后一圈前大锯从上方压下 → 落地磨地 → 猛地横切过整片敌群 → 锯收小飞回。
## 只换画风：小锯 / 弹射血线 / 撕痕 / 巨锯 / 横切 / 切痕换成 pixelfx 帧条（tools/pixelfx_fx/impacts/ak-specter-ul-ult.js，先装饰后核心），
## 不再用铃兰斩痕染色、pixgen 整圈锯和 ult_burst 粒子；地面裂网 / 隆起 / 烟尘 / 余震沿用 pixfx 公共冲击件（用户 10-30 认可的裂地做法）。
## 时序、伤害、判定留在 ult_moves_b._su_* 不动；散布按 PF.h 哈希，不抽模拟随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")

const MINI := "fx_specter_ul_umini"
const BIG := "fx_specter_ul_ubig"
const DASH := "fx_specter_ul_udash"
const TEAR := "fx_specter_ul_utear"
const CUT := "fx_specter_ul_ucut"
const SCAR := "fx_specter_ul_uscar"
## 各件烤制尺寸换成世界像素（1x × PX 2）：小锯半径 34、巨锯半径 70、血线长 104、撕痕长 36、横切长 212、切痕长 210
const MINI_R := 68.0
const BIG_R := 140.0
const DASH_L := 208.0
const TEAR_L := 72.0
const CUT_L := 424.0
const SCAR_L := 420.0
const RED := Color(0.62, 0.11, 0.13)


static func on(u) -> bool:
	return Bal.vi("fx/px_unleashed", 0) > 0 and u.fx_ready(MINI) and u.fx_ready(BIG)


## 先装饰（透明度 × fx/px_deco_k）后核心；终结技不分档（E2）
static func _s2(u, base: String, c: Vector2, opt: Dictionary) -> void:
	var vf = u.g.vfx
	var dn: String = vf.px_ul_tex(base, 1, false, "deco", 2)
	var dk: float = vf.px_deco_k()
	if dn != "" and dk > 0.0:
		var od := opt.duplicate()
		var cc: Color = opt.get("col", Color.WHITE)
		od["col"] = Color(cc.r, cc.g, cc.b, cc.a * dk)
		od.erase("hf")
		u.strip(dn, c, od)
	u.strip(vf.px_ul_tex(base, 1, false, "core", 2), c, opt)


## 线状件：p0 → p0 + 方向 × L，原点在帧条中点，按长度拉伸
static func _line(u, base: String, base_l: float, p0: Vector2, ang: float, L: float, opt: Dictionary) -> void:
	var o2 := {"ang": ang, "sx": L / base_l}
	o2.merge(opt)
	_s2(u, base, p0 + Vector2.from_angle(ang) * L * 0.5, o2)


static func sb_start(u, a: Dictionary, o, c: Vector2) -> void:
	a["sb"] = true
	a["sbu"] = true
	a["sb_vs"] = PF.vseed(u, c)
	a["sb_cur"] = c
	a["sb_pts"] = []
	var pr: Dictionary = o.portrait() if o.has_method("portrait") else {}
	a["sb_tex"] = str(pr.get("tex", ""))
	a["sb_fr"] = int(pr.get("frames", 1))
	u.light(c, 120.0, Color(0.5, 0.08, 0.1), 0.15)


static func sb_hit(a: Dictionary, p: Vector2) -> void:
	a.sb_pts.append(p)


## 红黑剪影闪现在 p（同 ult_fx_c._sb_ghost：她待机帧第 0 帧染暗红）
static func _ghost(u, a: Dictionary, p: Vector2, fs: float, delay: float, life: float) -> void:
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
		else:
			p = c + Vector2.from_angle(PF.h(vs + k * 3.1) * TAU) * R * (0.35 + 0.6 * PF.h(vs + k * 7.7))
		if p.distance_to(cur) < 60.0:
			p += Vector2.from_angle(PF.h(vs + k * 5.3) * TAU) * 120.0
		var dl: float = dt * k
		var ang: float = (p - cur).angle()
		var L: float = maxf(40.0, cur.distance_to(p))
		_line(u, DASH, DASH_L, cur, ang, L, {"sy": 1.0, "delay": dl})   # 弹射血线
		_ghost(u, a, p, -1.0 if p.x < cur.x else 1.0, dl, 0.16)
		var ta: float = ang + PI * 0.5 + (PF.h(vs + k * 2.3) - 0.5) * 1.2   # 落点撕痕（转角按哈希）
		var tl: float = 70.0 + 60.0 * PF.h(vs + k * 4.4)
		_line(u, TEAR, TEAR_L, p - Vector2.from_angle(ta) * tl * 0.5, ta, tl, {"layer": "back", "delay": dl + 0.02, "sy": 1.0 + 0.4 * PF.h(vs + k)})
		var sr: float = 80.0 + 24.0 * PF.h(vs + k * 6.1)   # 弹到这里锯一下（用户 10-31「闪出去弹射的时候也要带锯子」「小圆锯画大一点」）
		_s2(u, MINI, p + Vector2(0, -6), {"sc": sr / MINI_R, "delay": dl, "sx": -1.0 if PF.h(vs + k * 2.2) < 0.5 else 1.0})
		cur = p
	a.sb_cur = cur
	if tick == n - 1:
		sb_warn(u, a, c, R, pts)
	if tick >= n:
		sb_finale(u, a, c, R, pts)


## 收尾预兆（最后一圈前 0.25 秒）：落点地面压暗的锯影越来越大 + 巨锯从上方压下来
static func sb_warn(u, a: Dictionary, c: Vector2, R: float, pts: Array) -> void:
	var ctr: Vector2 = c
	if pts.size() >= 2:
		var sum := Vector2.ZERO
		for p in pts:
			sum += p
		ctr = c.lerp(sum / pts.size(), 0.5)
	a["sb_ctr"] = ctr
	var r1: float = R * 0.75
	var T := 0.25
	u.strip(u.g.vfx.px_ul_tex(BIG, 1, false, "core", 2), ctr + Vector2(0, 6), {"layer": "back", "sc": r1 * 0.4 / BIG_R, "sc1": r1 * 1.05 / BIG_R, "scd": T, "life": T + 0.04,
		"col": Color(0.0, 0.0, 0.02, 0.55), "fps": 40.0})   # 锯影压在地上
	_s2(u, BIG, ctr + Vector2(0, -170), {"sc": r1 * 1.25 / BIG_R, "sc1": r1 * 1.02 / BIG_R, "scd": T, "v": Vector2(0, 170.0 / T), "life": T,
		"col": Color(0.85, 0.8, 0.82, 0.8), "fps": 40.0})   # 大锯从上方压下来
	u.light(ctr, r1, Color(0.4, 0.05, 0.08), T)


## 收尾：巨锯落地（冲击帧里进剪影）→ 磨地 → 横切 → 锯收小飞回；裂网 / 隆起 / 烟尘 / 余震沿用 pixfx 公共冲击件
static func sb_finale(u, a: Dictionary, c: Vector2, R: float, pts: Array) -> void:
	var ctr: Vector2 = a.get("sb_ctr", c)
	var r1: float = R * 0.75
	_s2(u, BIG, ctr, {"sc": r1 / BIG_R, "hf": true})   # 巨锯落地：首帧白热 → 狂转磨地 0.85 秒
	var vs: float = float(a.sb_vs) + 55.0
	var ca: float = PF.h(vs + 77.0) * PI - PI * 0.5
	var cd: Vector2 = Vector2.from_angle(ca)
	var CL: float = R * 2.1
	var cp0: Vector2 = ctr - cd * CL * 0.5
	var T_CUT := 0.6
	_s2(u, MINI, ctr, {"sc": r1 * 0.9 / MINI_R, "delay": T_CUT - 0.06, "life": 0.08, "v": cd * CL * 0.5 / 0.08})   # 锯冲出去
	_line(u, CUT, CUT_L, cp0, ca, CL, {"delay": T_CUT, "sy": 1.6})   # 横切：一帧伸满 → 血红 → 上下错开
	_line(u, SCAR, SCAR_L, cp0, ca, CL, {"layer": "back", "delay": T_CUT, "sy": 1.4, "life": 2.2, "fade": 1.0})   # 深切痕慢慢冷却
	u.stop_later(T_CUT, Bal.v("ult/sb_cut_stop", 0.12))
	var nv: Vector2 = cd.orthogonal()
	for q in 6:   # 切口两侧碎石往两边飞（pixfx 公共碎石）
		var hq: float = PF.h(vs + 90.0 + q * 2.7)
		var pq: Vector2 = cp0 + cd * CL * (q + 0.5) / 6.0
		var side: float = 1.0 if q % 2 == 0 else -1.0
		PF.rock(u, pq, nv * side * (140.0 + 120.0 * hq), 150.0 + 100.0 * hq, hq, 0.34, T_CUT, Color(0.95, 0.75, 0.75))
	PF.dust(u, ctr, R * 0.9, T_CUT + 0.03, vs + 13.0, Vector2.ZERO, Color(0.4, 0.28, 0.28))
	_s2(u, MINI, ctr + cd * CL * 0.5, {"sc": r1 * 0.8 / MINI_R, "delay": T_CUT + 0.14, "life": 0.3, "sc1": r1 * 0.16 / MINI_R, "scd": 0.3,
		"v": (c - (ctr + cd * CL * 0.5)) / 0.3})   # 飞回她手里
	u.g.vfx.stop(Bal.v("ult/sb_hitstop", 0.16), "ult", true)
	u.light(ctr, r1, Color(0.55, 0.08, 0.1), 0.25)
	for q in 6:   # 锯开的口子：一圈不规整的撕痕（角度、长度按哈希）
		var ta: float = TAU * (q + PF.h(vs + q)) / 6.0
		var tl: float = r1 * (0.4 + 0.4 * PF.h(vs + q * 3.0))
		_line(u, TEAR, TEAR_L, ctr + Vector2.from_angle(ta) * r1 * 0.3, ta, tl, {"layer": "back", "delay": 0.12 + 0.02 * q, "sy": 1.3})
	var forks: Array = ["fx_ul_crack_fork", "fx_ul_crack_fork2", "fx_ul_crack_fork3", "fx_ul_crack_fork4"]
	PF.crack_net(u, forks, ctr, r1 * 1.25, 9, PF.h(vs) * TAU, vs, 0.14, Color(0.8, 0.2, 0.18), Color(0.2, 0.04, 0.05), r1 * 0.35)
	PF.heave(u, ctr, r1 * 0.85, vs, 0.02, Color(0.9, 0.8, 0.8))
	for q in 4:
		var hq: float = PF.h(vs + q * 6.7)
		PF.dust(u, ctr + Vector2.from_angle(TAU * (q + hq) / 4.0) * r1 * (0.6 + 0.4 * hq), 110.0 + 60.0 * hq, 0.04 * q, vs + q,
			Vector2.from_angle(TAU * (q + hq) / 4.0) * 60.0, Color(0.55, 0.45, 0.45) if q % 2 == 0 else Color(0.3, 0.22, 0.22))
	PF.aftershock(u, ctr, r1, vs + 3.0, 0.3, 10, Color(0.9, 0.8, 0.8))
	u.shake(3.0, 0.15)
