## 技能连携 B 组 10 人画面（docs/199 §7.5；用户 10-31 连携美术重做，pixfx 做法 + 打击感原则，不加冲击帧、不整屏白闪）：
## 归溟幽灵鲨 / 水月 / 塞雷娅 / 铃兰 / 逻各斯 / 星熊 / 推进之王 / 艾丽妮 / 拉普兰德 / 流明。
## skill_link.gd 各人那段只在原画法处调这里（判定、时序、伤害、位移都留在原处不动）；贴图缺时各函数返回 false，调用方照画原来的程序占位。
## 散布 / 变体按 LFX.h / LFX.vseed（出手时刻 + 位置的哈希），不抽模拟随机数。
extends RefCounted

const LFX = preload("res://scripts/run/link_fx_common.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")


# ================================================================ 拉普兰德：月牙剑气（冷紫蓝；她的技能剑气是细长冷蓝，这里是一道大月牙横扫）
const LP_CRES := ["fx_lk_lp_cres1", "fx_lk_lp_cres2", "fx_lk_lp_cres3"]


## 剑气飞行中每帧：月牙（凸面朝前）+ 两层残影；q = 当前中心，dd = 方向
static func lp_wave(u, a: Dictionary, q: Vector2, dd: Vector2, k: float) -> bool:
	if not LFX.on() or not u.fx_ready(LP_CRES[0]):
		return false
	if not a.has("lp_n"):
		a["lp_n"] = LFX.pick(u, LP_CRES, LFX.vseed(u, q))
	var name: String = a.lp_n
	var t: Texture2D = u._strip_tex(name)
	var sc: float = 150.0 / LFX.tex_h(u, name)   # 月牙横跨约 150（判定宽 140）
	var ang: float = dd.angle()
	for g in [2, 1, 0]:   # 残影在后
		var al: float = [1.0, 0.45, 0.2][g]
		u.strip(name, q - dd * 26.0 * g, {"ang": ang, "sc": sc * (1.0 - 0.06 * g), "life": 0.05, "col": LFX.tint(Color(0.82, 0.8, 1.0), 1.0, al)})
	if int(k * 30.0) % 2 == 0:
		u.grain("blade", q - dd * 30.0, -dd, Color(0.6, 0.6, 0.9), 2)
	return true


## 剑气过完：区域里留一道冷紫斩痕（地面层，冷却变暗）
static func lp_scar(u, a: Dictionary, sp: Vector2, ep: Vector2) -> void:
	if not LFX.on() or not u.fx_ready(LP_CRES[0]):
		return
	u.shape({"kind": "blade", "a": sp, "b": ep, "w": 4.0, "col": Color(0.55, 0.52, 0.85), "glow": Color(0.25, 0.22, 0.5), "life": 0.6, "layer": "back"})


# ================================================================ 归溟幽灵鲨：暗红替身冲斩（她的终结技是弹射撕裂 + 巨锯，这里是一道直线替身斩）
const SP_SLASH := ["fx_lk_sp_slash1", "fx_lk_sp_slash2", "fx_lk_sp_slash3"]


## 替身冲刺中每帧：她本人帧条的暗红剪影 + 拖影
static func sp_ghost(u, p, q: Vector2, d: Vector2) -> bool:
	if not LFX.on() or not u.fx_ready(SP_SLASH[0]):
		return false
	var pr: Dictionary = p.portrait()
	var tn: String = str(pr.get("tex", ""))
	var tx: Texture2D = u._strip_tex(tn) if tn != "" else null
	if tx != null:
		var fw: float = tx.get_width() / float(maxi(1, int(pr.get("frames", 1))))
		for g in 3:
			u.strip(tn, q - d * 18.0 * g, {"uw": fw, "o": Vector2(fw * 0.5, tx.get_height() * 0.8), "sx": -1.0 if d.x < 0.0 else 1.0, "life": 0.08,
				"col": Color(0.42, 0.04, 0.07, [0.9, 0.45, 0.2][g])})
	u.shape({"kind": "band", "a": q - d * 60.0, "b": q, "w": 10.0, "col": Color(0.5, 0.05, 0.08), "fill": 0.35, "life": 0.05})   # 拖影条（打击感 3：拖影代替补间）
	return true


## 斩出：一道撕裂斩痕（血红 → 暗红冷却，留在地面）+ 血红火花
static func sp_cut(u, fp: Vector2, tp: Vector2) -> bool:
	if not LFX.on() or not u.fx_ready(SP_SLASH[0]):
		return false
	var vs: float = LFX.vseed(u, tp)
	var name: String = LFX.pick(u, SP_SLASH, vs)
	var t: Texture2D = u._strip_tex(name)
	var L: float = fp.distance_to(tp)
	var ang: float = (tp - fp).angle()
	var sy: float = -1.0 if LFX.h(vs) < 0.5 else 1.0
	u.strip(name, fp, {"ang": ang, "o": Vector2(0.0, t.get_height() * 0.5), "sx": L / LFX.tex_w(u, name), "sy": sy, "life": 0.9, "fade": 0.5,
		"col": Color(1.0, 0.95, 0.95, 1.0), "col1": Color(0.35, 0.05, 0.08, 0.9), "cold": 0.35})
	u.strip(name, fp, {"layer": "back", "ang": ang, "o": Vector2(0.0, t.get_height() * 0.5), "sx": L / LFX.tex_w(u, name), "sy": sy * 0.6, "life": 1.6, "fade": 0.8,
		"col": Color(0.45, 0.06, 0.09, 0.85)})   # 地上留的口子
	for q in 5:
		var pp: Vector2 = fp.lerp(tp, (q + 0.3 + 0.4 * LFX.h(vs + q)) / 5.0)
		u.grain("sh_shard", pp, (tp - fp).normalized().orthogonal() * (1.0 if q % 2 == 0 else -1.0), Color(0.75, 0.1, 0.12), 3)
	u.light(fp.lerp(tp, 0.6), 140.0, Color(0.55, 0.08, 0.1), 0.25)
	return true


# ================================================================ 推进之王：冲阵 + 尾锤（灰金尘、砸坑；她的终结技是跃空砸落的大裂网，这里是地面冲锋 + 一个坑）
const SG_CRATER := ["fx_lk_sg_crater1", "fx_lk_sg_crater2", "fx_lk_sg_crater3"]
const SG_ROCK := "fx_ul_rock"


## 冲锋中每帧：脚下翻起的尘 + 拖影条
static func sg_dash(u, q: Vector2, d: Vector2) -> bool:
	if not LFX.on() or not u.fx_ready(SG_CRATER[0]):
		return false
	u.shape({"kind": "band", "a": q - d * 70.0, "b": q, "w": 22.0, "col": Color(0.55, 0.45, 0.3), "fill": 0.3, "life": 0.05})
	var hq: float = LFX.h(q.x * 0.071 + q.y * 0.113)   # 尘按哈希隔几帧冒一团、左右错开、大小不一（预审：每帧一团等距像贴片）
	if hq < 0.35:
		var side: Vector2 = d.orthogonal() * (hq * 60.0 - 10.0)
		u.grain("bfx_dust", q + side + Vector2(0, 8), -d.rotated((hq - 0.17) * 2.0), Color(0.45, 0.4, 0.33) if hq < 0.2 else Color(0.32, 0.29, 0.25), 2 + int(hq * 12.0))
	return true


## 尾锤：砸坑（3 种）+ 坑口碎石顶起落回（大小不一、少数高飞）+ 两团分层尘 + 灯 + 轻震
static func sg_slam(u, c: Vector2) -> bool:
	if not LFX.on() or not u.fx_ready(SG_CRATER[0]):
		return false
	var vs: float = LFX.vseed(u, c)
	var name: String = LFX.pick(u, SG_CRATER, vs)
	var sc: float = 130.0 / LFX.tex_w(u, name)
	u.strip(name, c + Vector2(0, 4), {"layer": "back", "sc": sc * 0.7, "sc1": sc, "scd": 0.06, "sy": 0.62, "sx": -1.0 if LFX.h(vs) < 0.5 else 1.0,
		"life": 1.8, "fade": 0.8, "col": Color(1.08, 1.04, 0.95, 1.0), "col1": Color(0.62, 0.58, 0.54, 0.95), "cold": 0.5})
	if u.fx_ready(SG_ROCK):
		for q in 8:
			var hq: float = LFX.h(vs + q * 3.7)
			var dv := Vector2.from_angle(TAU * (q + hq) / 8.0)
			var high: bool = q % 3 == 0
			var vy: float = (280.0 if high else 120.0) + 60.0 * hq
			u.strip(SG_ROCK, c + dv * (30.0 + 25.0 * hq), {"f": [0, 1, 3][q % 3], "sc": (0.5 if high else 0.32) + 0.15 * hq, "v": dv * (60.0 if high else 22.0) + Vector2(0, -vy),
				"grav": 1500.0, "life": 2.0 * vy / 1500.0, "spin": (hq - 0.5) * 9.0, "sx": -1.0 if hq < 0.5 else 1.0, "col": Color(0.9, 0.85, 0.76)})
	for q in 2:   # 尘：两团、明暗两层
		var dq := Vector2.from_angle(LFX.h(vs + 9.0 + q) * TAU)
		u.grain("bfx_dust", c + dq * 20.0, dq, Color(0.62, 0.56, 0.46) if q == 0 else Color(0.36, 0.32, 0.27), 8)
	u.light(c, 170.0, Color(0.85, 0.65, 0.3), 0.3)
	u.shake(2.5, 0.12)
	return true


# ================================================================ 星熊：瞬到队长身侧举「般若」盾（琥珀金；她的技能是重斩，这里是挡在队长前的一面盾）
const HS_SHIELD := "fx_lk_hs_shield"


## 举盾期间每帧：盾面朝敌（正视贴图压扁成俯视下的竖牌）+ 受光边；fa = 透明度
static func hs_shield(u, pos: Vector2, side: Vector2, fa: float, t: float) -> bool:
	if not LFX.on() or not u.fx_ready(HS_SHIELD):
		return false
	var sh: float = LFX.tex_h(u, HS_SHIELD)
	var sc: float = 64.0 / sh
	var tx: Texture2D = u._strip_tex(HS_SHIELD)
	var bob: float = 1.5 * sin(t * 9.0)
	u.strip(HS_SHIELD, pos + side * 6.0 + Vector2(0, 8 + bob), {"o": Vector2(tx.get_width() * 0.5, tx.get_height()), "sc": sc, "sx": 0.75 if side.x >= 0.0 else -0.75,
		"life": 0.05, "col": Color(1, 1, 1, fa)})
	return true


## 盾落定那一下：盾面金边亮一下 + 尘 + 挡下的火星
static func hs_plant(u, pos: Vector2, side: Vector2) -> void:
	u.light(pos, 120.0, Color(0.9, 0.65, 0.25), 0.25)
	u.grain("bfx_dust", pos + Vector2(0, 10), side.orthogonal(), Color(0.55, 0.5, 0.42), 6)
	u.grain("bfx_dust", pos + Vector2(0, 10), -side.orthogonal(), Color(0.55, 0.5, 0.42), 6)
	u.grain("sh_glint", pos + side * 10.0 + Vector2(0, -20), side, Color(0.95, 0.75, 0.35), 6)


# ================================================================ 铃兰：4 团狐火（狐首形火团，绕身转一圈再追敌；她的终结技是忍冬一斩，技能是九尾 / 光域，这里是小狐火）
const SZ_FOX := ["fx_lk_sz_fox1", "fx_lk_sz_fox2", "fx_lk_sz_fox3"]


## 每帧每团：q = 当前位置，dv = 运动方向（转圈时为切线）；j = 第几团
static func sz_fox(u, q: Vector2, dv: Vector2, j: int) -> bool:
	if not LFX.on() or not u.fx_ready(SZ_FOX[0]):
		return false
	var name: String = SZ_FOX[j % 3]
	var sc: float = 26.0 / LFX.tex_h(u, name)
	u.strip(name, q, {"sc": sc, "sx": -1.0 if dv.x < 0.0 else 1.0, "life": 0.05, "col": Color(1.05, 1.0, 0.95, 0.95)})   # 小狐形狐火：始终竖直，按运动方向左右翻
	return true


## 命中：一小团狐火粒子 + 短灯
static func sz_pop(u, p: Vector2) -> void:
	u.grain("fire", p, Vector2.UP, Color(1.0, 0.7, 0.3), 5)
	u.light(p, 80.0, Color(0.9, 0.6, 0.25), 0.18)


# ================================================================ 逻各斯：黑金咒文环（区域上空转一圈，消弹处留黑金碎屑）
const LO_RING := "fx_lk_lo_ring"


static func lo_ring(u, c: Vector2, R: float, t: float) -> bool:
	if not LFX.on() or not u.fx_ready(LO_RING):
		return false
	var sc: float = R * 2.0 / LFX.tex_w(u, LO_RING)
	var k: float = clampf(t / 0.12, 0.0, 1.0)
	var fa: float = clampf((0.8 - t) / 0.25, 0.0, 1.0)
	u.strip(LO_RING, c, {"sc": sc * lerpf(1.25, 1.0, k), "sy": 0.55, "ang": t * 0.9, "life": 0.05, "col": Color(1, 1, 1, 0.9 * fa)})
	return true


# ================================================================ 艾丽妮：提灯一照（提灯贴图举在她身前、光扫过区域）→ 补一刺（细冷白刺线）
const IR_LAMP := ["fx_lk_ir_lamp1", "fx_lk_ir_lamp2", "fx_lk_ir_lamp3"]


static func ir_lamp(u, p, c: Vector2, r: float) -> bool:
	if not LFX.on() or not u.fx_ready(IR_LAMP[0]):
		return false
	var vs: float = LFX.vseed(u, c)
	var name: String = LFX.pick(u, IR_LAMP, vs)
	var tx: Texture2D = u._strip_tex(name)
	var d: Vector2 = (c - p.pos).normalized() if c != p.pos else Vector2.RIGHT
	u.strip(name, p.pos + d * 18.0 + Vector2(0, -34), {"o": Vector2(tx.get_width() * 0.5, 0.0), "sc": 40.0 / LFX.tex_h(u, name), "life": 0.9, "fade": 0.3,
		"col": Color(1, 1, 1, 1), "spin": 0.4 * (1.0 if LFX.h(vs) < 0.5 else -1.0)})
	# 光：从提灯扇形扫到区域（暖金、半透明、不实心发白）
	u.shape({"kind": "sector", "c": p.pos + Vector2(0, -20), "r": p.pos.distance_to(c) + r, "a": d.angle(), "half": 0.32, "col": Color(0.85, 0.7, 0.35), "fill": 0.14, "life": 0.6})
	u.shape({"kind": "circle", "c": c, "r": r, "col": Color(0.55, 0.42, 0.18), "fill": 0.14, "layer": "back", "life": 0.9})
	u.light(c, r + 50.0, Color(0.8, 0.62, 0.3), 0.8)
	for q in 8:
		var pp: Vector2 = c + Vector2.from_angle(TAU * (q + LFX.h(vs + q)) / 8.0) * r * (0.3 + 0.6 * LFX.h(vs + q * 2.0))
		u.grain("mote_up", pp, Vector2.UP, Color(0.9, 0.75, 0.4), 2)
	return true


# ================================================================ 塞雷娅：钙质护盾 + 区域钙化（地面冒出 3 种钙晶簇，散布 / 镜像 / 大小按哈希）
const SA_CALC := ["fx_lk_sa_calc1", "fx_lk_sa_calc2", "fx_lk_sa_calc3"]


static func sa_ground(u, c: Vector2, r: float) -> bool:
	if not LFX.on() or not u.fx_ready(SA_CALC[0]):
		return false
	var vs: float = LFX.vseed(u, c)
	for j in 7:
		var hh: float = LFX.h(vs + j * 3.3)
		var off: Vector2 = Vector2.from_angle(TAU * (j + hh) / 7.0) * r * (0.2 + 0.7 * LFX.h(vs + j * 5.1))
		var name: String = SA_CALC[int(LFX.h(vs + j) * 3.0) % 3]
		var tx: Texture2D = u._strip_tex(name)
		var sc: float = (26.0 + 14.0 * hh) / LFX.tex_h(u, name)
		u.strip(name, c + off, {"o": Vector2(tx.get_width() * 0.5, tx.get_height() - 2.0), "sc": sc * 0.3, "sc1": sc, "scd": 0.08, "sx": -1.0 if hh < 0.5 else 1.0,
			"delay": 0.03 * j, "life": 1.6, "fade": 0.4, "col": Color(0.78, 0.82, 0.88, 1)})   # 压暗一档（晶面偏白）
	return true


# ================================================================ 水月：区域里 6 名敌人脚下钻出小触手（3 种，按序号挑 / 镜像）
const MZ_TEN := ["fx_lk_mz_ten1", "fx_lk_mz_ten2", "fx_lk_mz_ten3"]


static func mz_tentacles(u, ts: Array) -> bool:
	if not LFX.on() or not u.fx_ready(MZ_TEN[0]):
		return false
	var vs: float = LFX.vseed(u, ts[0].pos if not ts.is_empty() else Vector2.ZERO)
	for j in ts.size():
		var e = ts[j]
		var hh: float = LFX.h(vs + j * 2.7)
		var name: String = MZ_TEN[int(hh * 3.0) % 3]
		var tx: Texture2D = u._strip_tex(name)
		var sc: float = (34.0 + 10.0 * hh) / LFX.tex_h(u, name)
		u.strip(name, e.pos + Vector2(8.0 * (hh - 0.5), 8.0), {"o": Vector2(tx.get_width() * 0.5, tx.get_height() - 2.0), "sc": sc * 0.3, "sc1": sc, "scd": 0.1, "sx": -1.0 if hh < 0.5 else 1.0,
			"delay": 0.04 * j, "life": 1.0, "fade": 0.3})
		u.shape({"kind": "circle", "c": e.pos + Vector2(0, 8), "r": 12.0, "col": Color(0.03, 0.03, 0.08), "fill": 0.6, "layer": "back", "life": 1.0, "delay": 0.04 * j})
	return true


# ================================================================ 流明：灼烧光点（预烘焙粒子帧条 ult_ember，暖象牙 / 淡青，在区域里错开冒；她的终结技是光柱 + 碎光环）
static func lu_motes(u, c: Vector2, r: float, t: float) -> bool:
	if not LFX.on() or not u.fx_ready(PF.BURST_S):
		return false
	if int(t * 30.0) % 4 != 0:
		return true
	var hh: float = LFX.h(t * 7.3 + c.x * 0.01)
	var p: Vector2 = c + Vector2.from_angle(hh * TAU) * r * sqrt(LFX.h(hh * 13.0))
	PF.particles(u, p, 40, "ult_ember", [Color(0.55, 0.5, 0.36) if hh < 0.5 else Color(0.36, 0.5, 0.52)], 0.0, hh * 97.0, 60.0)
	return true


# ================================================================ 转给 B 组的 A 组 5 人（协调人 10-31）：凯尔希 / 歌蕾蒂娅 / 安洁莉娜 / 艾雅法拉 / 维什戴尔
# 全部复用 ult-fx-power 已有的 pixfx 贴图（终结技同族元素，缩小一档、颜色不变），不另出图；只画画面。

# ---------------- 艾雅法拉：熔岩块高抛砸地（熔岩块 fx_ey_rock 2 种、落点 fx_ey_fork 分叉熔缝冷却 + 碎岩 + 粒子）
const EY_ROCK := "fx_ey_rock"
const EY_FORKS := ["fx_ey_fork1", "fx_ey_fork2", "fx_ey_fork3", "fx_ey_fork4"]


static func ey_rock(u, a: Dictionary, pos: Vector2, k: float, R: float) -> bool:
	if not LFX.on() or not u.fx_ready(EY_ROCK):
		return false
	if not a.has("ey_f"):
		a["ey_f"] = int(LFX.h(LFX.vseed(u, pos)) * 2.0) % 2
	var sc: float = R * 2.2 / (LFX.tex_w(u, EY_ROCK) * 0.5)
	u.strip(EY_ROCK, pos, {"f": int(a.ey_f), "sc": sc * minf(1.0, 0.5 + k * 3.0), "ang": k * 5.0, "life": 0.05})
	return true


static func ey_slam(u, c: Vector2, hr: float, R: float) -> bool:
	if not LFX.on() or not u.fx_ready(EY_FORKS[0]):
		return false
	var vs: float = LFX.vseed(u, c)
	PF.crack_net(u, EY_FORKS, c, hr * 1.05, 6, LFX.h(vs) * TAU, vs, 0.12, Color(1.0, 0.62, 0.3), Color(0.22, 0.07, 0.04), R * 0.5)
	PF.particles(u, c, 200, "ult_burst_s", [Color(0.75, 0.3, 0.08), Color(0.4, 0.12, 0.05)], 0.0, vs, hr * 0.8)
	PF.particles(u, c, 40, "ult_ember", [Color(0.7, 0.35, 0.1)], 0.1, vs + 3.0, 60.0)
	for q in 6:
		var hq: float = LFX.h(vs + q * 3.7)
		var dv := Vector2.from_angle(TAU * (q + hq) / 6.0)
		PF.rock(u, c + dv * R * 0.6, dv * (40.0 + 50.0 * hq), 160.0 + 120.0 * hq, hq, 0.32, 0.0, Color(1.0, 0.75, 0.6))
	u.shape({"kind": "ellipse", "c": c, "rx": R * 1.3, "ry": R * 0.6, "col": Color(0.2, 0.05, 0.03), "fill": 0.75, "layer": "back", "life": 1.8})   # 焦坑
	u.light(c, 260.0, Color(0.9, 0.42, 0.12), 0.5)
	return true


# ---------------- 歌蕾蒂娅：甩钩拖拽 → 落地一小团漩涡收一下 + 水色粒子（终结技那张漩涡缩到区域大小）
const GL_VORTEX := "fx_gl_vortex"


static func gl_land(u, c: Vector2, r: float) -> bool:
	if not LFX.on() or not u.fx_ready(GL_VORTEX):
		return false
	var vs: float = LFX.vseed(u, c)
	var rr: float = LFX.tex_w(u, GL_VORTEX) * 0.5
	u.strip(GL_VORTEX, c, {"layer": "back", "sc": r * 1.1 / rr, "sc1": r * 0.35 / rr, "scd": 0.35, "spin": -7.0, "ang": LFX.h(vs) * TAU, "life": 0.45, "fade": 0.2,
		"col": Color(1.0, 1.05, 1.1, 0.85)})
	PF.particles(u, c, 160, "ult_burst_s", [Color(0.25, 0.55, 0.62), Color(0.4, 0.7, 0.78)], 0.3, vs, r * 0.7)
	u.light(c, 200.0, Color(0.3, 0.62, 0.7), 0.35)
	return true


# ---------------- 安洁莉娜：三颗小重力核心绕区域收拢（终结技核心 fx_an_core 缩小）→ 落定砸坑 fx_an_crater + 紫粒子
const AN_CORE := "fx_an_core"
const AN_CRATER := "fx_an_crater"


static func an_core(u, sp: Vector2, k: float, j: int) -> bool:
	if not LFX.on() or not u.fx_ready(AN_CORE):
		return false
	var sc: float = 20.0 / (LFX.tex_w(u, AN_CORE) * 0.5)
	u.strip(AN_CORE, sp, {"sc": sc * (1.0 + 0.3 * sin(k * 20.0 + j)), "ang": k * 8.0 + j, "life": 0.05, "col": Color(1.05, 1.0, 1.1, 0.95)})
	return true


static func an_land(u, c: Vector2, r: float) -> bool:
	if not LFX.on() or not u.fx_ready(AN_CRATER):
		return false
	var vs: float = LFX.vseed(u, c)
	var rr: float = LFX.tex_w(u, AN_CRATER) * 0.5
	u.strip(AN_CRATER, c, {"layer": "back", "sc": r * 0.55 / rr, "sy": 0.62, "ang": 0.0, "sx": -1.0 if LFX.h(vs) < 0.5 else 1.0, "life": 1.2, "fade": 0.5,
		"col": Color(1.0, 1.0, 1.0, 0.9)})
	PF.particles(u, c, 180, "ult_burst_s", [Color(0.45, 0.28, 0.65), Color(0.28, 0.16, 0.42)], 0.0, vs, r * 0.6)
	u.light(c, 160.0, Color(0.55, 0.35, 0.8), 0.35)
	return true


# ---------------- 维什戴尔：好礼——暗红残影 0.35 秒后炸开（终结技弹坑 fx_ws_crater 4 种 + 红粒子，缩到半径 60）
const WS_CRATER := "fx_ws_crater"


static func wd_blast(u, gp: Vector2, j: int) -> bool:
	if not LFX.on() or not u.fx_ready(WS_CRATER):
		return false
	var vs: float = LFX.vseed(u, gp) + j
	var fw: float = LFX.tex_w(u, WS_CRATER) / 4.0
	var sc: float = 70.0 / fw * (0.8 + 0.4 * LFX.h(vs))
	u.strip(WS_CRATER, gp + Vector2(0, 4), {"layer": "back", "f": int(LFX.h(vs * 1.7) * 4.0) % 4, "sc": sc, "sy": 0.6, "sx": -1.0 if LFX.h(vs) < 0.5 else 1.0,
		"life": 1.2, "fade": 0.5})
	PF.particles(u, gp, 150, "ult_burst_s", [Color(0.75, 0.12, 0.12), Color(0.4, 0.06, 0.08)], 0.0, vs, 70.0)
	PF.particles(u, gp, 30, "ult_ember", [Color(0.7, 0.25, 0.15)], 0.08, vs + 2.0, 40.0)
	if j % 3 == 0:
		u.light(gp, 110.0, Color(0.8, 0.2, 0.15), 0.25)
	return true


static func wd_ghost(u, pos: Vector2) -> bool:   # 死者原地留暗红残影：几缕往上飘的暗红余烬
	if not LFX.on() or not u.fx_ready(WS_CRATER):
		return false
	PF.particles(u, pos + Vector2(0, -12), 30, "ult_ember", [Color(0.5, 0.06, 0.08)], 0.0, pos.x * 0.37, 30.0)
	u.shape({"kind": "ellipse", "c": pos + Vector2(0, -16), "rx": 10.0, "ry": 16.0, "col": Color(0.45, 0.05, 0.08), "fill": 0.45, "life": 0.35})
	return true


# ---------------- 凯尔希：Mon3tr 落到队长前方挡一下——落地碎裂 + 绿色粒子 + 推开（她的终结技是红色爆，这里用本人青绿）
static func ka_block(u, mp: Vector2, sd: Vector2) -> bool:
	if not LFX.on() or not u.fx_ready(PF.BURST_S):
		return false
	var vs: float = LFX.vseed(u, mp)
	PF.particles(u, mp + sd * 30.0, 160, "ult_burst_s", [Color(0.3, 0.7, 0.55), Color(0.18, 0.42, 0.34)], 0.0, vs, 90.0)
	PF.cracks(u, ["fx_ul_crack_fork", "fx_ul_crack_fork2"], mp, PF.angles(4, sd.angle() - 0.8, vs).slice(0, 3), [60.0, 75.0, 55.0],
		{"seed": vs, "r0": 10.0, "rev": 0.06, "rev0": 0.2, "life": 0.9, "fade": 0.4, "col": Color(0.5, 0.95, 0.75), "col1": Color(0.1, 0.22, 0.18), "cold": 0.35, "small": 0.4, "big": 0.55})
	for q in 4:   # 落地重量：几块碎石往外蹦 + 两团尘（预审：缺地面反馈）
		var hq: float = LFX.h(vs + q * 2.9)
		var dv: Vector2 = Vector2.from_angle(sd.angle() + (hq - 0.5) * 2.4)
		PF.rock(u, mp + dv * 20.0, dv * (50.0 + 40.0 * hq), 130.0 + 90.0 * hq, hq, 0.3, 0.0)
	u.grain("bfx_dust", mp + Vector2(0, 8), sd.orthogonal(), Color(0.5, 0.48, 0.44), 6)
	u.grain("bfx_dust", mp + Vector2(0, 8), -sd.orthogonal(), Color(0.32, 0.3, 0.28), 6)
	u.light(mp, 150.0, Color(0.35, 0.85, 0.6), 0.4)
	return true
