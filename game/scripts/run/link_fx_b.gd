## 技能连携 B 组 10 人画面（docs/199 §7.5；用户 10-31 连携美术重做，pixfx 做法 + 打击感原则，不加冲击帧、不整屏白闪）：
## 归溟幽灵鲨 / 水月 / 塞雷娅 / 铃兰 / 逻各斯 / 星熊 / 推进之王 / 艾丽妮 / 拉普兰德 / 流明。
## skill_link.gd 各人那段只在原画法处调这里（判定、时序、伤害、位移都留在原处不动）；贴图缺时各函数返回 false，调用方照画原来的程序占位。
## 散布 / 变体按 LFX.h / LFX.vseed（出手时刻 + 位置的哈希），不抽模拟随机数。
extends RefCounted

const LFX = preload("res://scripts/run/link_fx_common.gd")


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
