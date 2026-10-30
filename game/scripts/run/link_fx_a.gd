## 技能连携 A 组画面（用户 10-31「先做美术」；docs/199 §7.14；德克萨斯 / 能天使 / 浊心斯卡蒂 / 乌尔比安 / 斯卡蒂）：
## skill_link.gd 各人那段在结算点调这里一行，替掉原来的程序占位；不碰判定 / 时序 / 伤害。开关 ult/link_fx_a（缺省 1；0 = 原程序占位）。
## 口径：不加冲击帧、不整屏白闪（用户 10-31「一直闪频不太好」），亮度 ≤ 0.85；粒子用 pxburst 预烘焙帧条（PF.particles）；
## 色调跟本人终结技同系、但形状和终结技 / 技能分开：德克萨斯橙色直线冲斩、能天使红金曳光、浊心斯卡蒂暗红歌域、乌尔比安青黑锚链、斯卡蒂深蓝水痕。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")
const LFX = preload("res://scripts/run/link_fx_common.gd")

const TX := ["fx_lk_tx1", "fx_lk_tx2", "fx_lk_tx3"]
const TX_COL := Color(1.0, 0.62, 0.3)
const EX_RED := Color(1.0, 0.32, 0.26)
const EX_GOLD := Color(1.0, 0.8, 0.42)
const SK_RED := Color(0.85, 0.2, 0.28)
const UL_TEAL := Color(0.3, 0.75, 0.8)
const UL_FORKS := ["fx_ul_crack_fork", "fx_ul_crack_fork2", "fx_ul_crack_fork3", "fx_ul_crack_fork4"]
const SD_TRAIL := "fx_lk_sd_trail"
const SD_BLUE := Color(0.35, 0.6, 0.85)


static func on(u, need: String) -> bool:
	return Bal.v("ult/link_fx_a", 1.0) > 0.0 and u.fx_ready(need)


## 一段贴图沿 a → b 拉满（原点左端中心）
static func _span(u, name: String, a: Vector2, b: Vector2, opt: Dictionary) -> Dictionary:
	var t: Texture2D = u._strip_tex(name)
	var o := opt.duplicate()
	o["ang"] = (b - a).angle()
	o["o"] = Vector2(0.0, t.get_height() * 0.5)
	o["sx"] = a.distance_to(b) / PF.tex_w(u, name)
	return u.strip(name, a, o)


# ---------------------------------------------------------------- 德克萨斯：瞬身穿过主目标
## 斩痕 = 一道橙色直线冲斩（fx_lk_tx1–3，按种子挑变体），从起点往终点 0.06 秒显现、头亮尾散；目标处一团橙色粒子 + 逐帧烟尘留余韵
static func texas_cut(u, fp: Vector2, tp: Vector2, mid: Vector2) -> void:
	var vs: float = LFX.vseed(u, mid)
	var nm := PF.pick(u, TX, vs * 0.37)
	var t: Texture2D = u._strip_tex(nm)
	var uw: float = t.get_width() * 0.55   # 只截前段连续亮芯（后段一串断开的残影短划会被看成等距切片）
	var a0: Vector2 = fp - (tp - fp).normalized() * 30.0
	u.strip(nm, a0, {"ang": (tp - a0).angle(), "o": Vector2(0.0, t.get_height() * 0.5), "ux": t.get_width() - uw, "uw": uw,
		"sx": a0.distance_to(tp) / (PF.tex_w(u, nm) * 0.55), "sy": (1.0 if PF.h(vs) < 0.5 else -1.0) * 1.3, "rev": 0.06, "rev0": 0.1, "life": 0.5, "fade": 0.35,
		"col": Color(1.0, 0.95, 0.9), "col1": Color(0.7, 0.4, 0.25, 0.8), "cold": 0.3})
	PF.particles(u, mid, 120, "ult_burst_s", [TX_COL, Color(0.75, 0.35, 0.18)], 0.02, vs, 80.0)
	PF.dust(u, mid + Vector2(0, 8), 110.0, 0.05, vs, (tp - fp).normalized() * 60.0, Color(0.7, 0.62, 0.55))
	u.light(mid, 160.0, TX_COL, 0.25)


# ---------------------------------------------------------------- 能天使：一轮 8 发穿透曳光
## 每发 = 一颗红 / 金交替的短曳光（借德克萨斯冲斩的细条染色，0.12 秒从枪口飞到尽头）+ 枪口火花帧条 + 落点一小撮粒子；不画整条长线、不画闪光颗粒
static func exusiai_shot(u, fp: Vector2, tp: Vector2, i: int) -> void:
	var nm := PF.pick(u, TX, float(i) * 1.7)
	var col: Color = EX_RED if i % 2 == 0 else EX_GOLD
	var d: Vector2 = (tp - fp).normalized()
	var L: float = fp.distance_to(tp)
	var t: Texture2D = u._strip_tex(nm)
	u.strip(nm, fp, {"ang": d.angle(), "o": Vector2(t.get_width(), t.get_height() * 0.5), "sx": 90.0 / PF.tex_w(u, nm), "sy": 0.8, "v": d * L / 0.12, "life": 0.12,
		"col": Color(col.r * 1.1, col.g * 1.1, col.b * 1.1)})
	if u.fx_ready("fx_exusiai_muzzle"):
		u.strip("fx_exusiai_muzzle", fp, {"ang": d.angle(), "sc": 1.4})
	PF.particles(u, tp, 30, "ult_burst_s", [col], 0.1, float(i) * 3.1 + tp.x, 40.0)


# ---------------------------------------------------------------- 浊心斯卡蒂：歌声覆盖区域 3 秒
## 地面一片暗红歌域（fx_ult_skalter_domain_back 缩到区域、慢转、淡）+ 每 0.5 秒一圈暗红音尘从中心漾开；不画绕圈的圆点
static func skalter_song(u, c: Vector2, r: float, t: float, a: Dictionary) -> void:
	if not a.has("dom"):
		var nm := "fx_ult_skalter_domain_back"
		var tex: Texture2D = u._strip_tex(nm)
		var fw: float = PF.tex_w(u, nm) / 6.0
		a["dom"] = u.strip(nm, c, {"layer": "back", "sc": r * 2.0 / fw * 0.5, "sc1": r * 2.0 / fw, "scd": 0.3, "loop": true, "spin": 0.4, "life": 3.0, "fade": 0.5,
			"col": Color(1.0, 0.75, 0.8, 0.7)})
		PF.particles(u, c, 200, "ult_burst", [SK_RED, Color(0.45, 0.1, 0.16)], 0.0, LFX.vseed(u, c), r)
	if int(t * 2.0) != int(a.get("pulse", -1)) and t < 2.6:
		a["pulse"] = int(t * 2.0)
		PF.particles(u, c + Vector2(0, -10), 60, "ult_ember", [Color(SK_RED, 0.8)], 0.0, float(a.pulse) * 7.0 + c.x, r * 0.7)


# ---------------------------------------------------------------- 乌尔比安：掷锚钉住主目标
## 飞行：锚贴图（fx_ult_ulpianus_anchor_front 定帧）转着飞 + 身后一段锁链（链节贴图沿线铺）；钉下：小裂网 + 地块隆起 + 逐帧烟尘；拖拽期间锁链绷着
static func ulpianus_fly(u, fp: Vector2, q: Vector2, k: float) -> void:
	var d: Vector2 = (q - fp).normalized() if q != fp else Vector2.RIGHT
	u.strip("fx_ult_ulpianus_anchor_front", q, {"f": int(k * 8.0) % 4, "ang": d.angle() + k * 9.0, "sc": 0.9, "life": 0.04})
	if fp.distance_to(q) > 20.0:
		u.tiles_line("fx_ulpianus_chain_tile", fp, q, {"life": 0.04, "sc": 0.8})


static func ulpianus_pin(u, tp: Vector2) -> void:
	var vs: float = LFX.vseed(u, tp)
	PF.crack_net(u, UL_FORKS, tp, 130.0, 6, PF.h(vs) * TAU, vs, 0.15, Color(0.85, 1.0, 1.0), Color(0.3, 0.38, 0.42), 14.0)
	PF.heave(u, tp, 60.0, vs, 0.0, Color.WHITE, 60.0)
	PF.dust(u, tp + Vector2(0, 6), 120.0, 0.03, vs, Vector2.ZERO, Color(0.6, 0.66, 0.66))
	u.light(tp, 150.0, UL_TEAL, 0.3)


static func ulpianus_hold(u, from: Vector2, tp: Vector2) -> void:
	u.strip("fx_ult_ulpianus_anchor_front", tp + Vector2(0, -6), {"f": 0, "ang": (tp - from).angle(), "sc": 0.9, "life": 0.04})
	u.tiles_line("fx_ulpianus_chain_tile", from, tp, {"life": 0.04, "sc": 0.8})


# ---------------------------------------------------------------- 斯卡蒂：拖刃冲锋
## 冲锋时脚下水花粒子；冲过之后整条路线铺一道水痕（fx_lk_sd_trail 截段拉满，地面层，1.5 秒慢慢冷成暗蓝淡掉）+ 沿线三团逐帧烟尘（水雾）；
## 每跳水痕伤害时沿线漾一撮水珠
static func skadi_run(u, q: Vector2, t: float) -> void:
	if int(t * 60.0) % 3 == 0:
		PF.particles(u, q + Vector2(0, 8), 30, "ult_burst_s", [SD_BLUE, Color(0.7, 0.85, 0.95)], 0.0, t * 91.0 + q.x, 40.0)


static func skadi_trail(u, fp: Vector2, tp: Vector2) -> void:
	var vs: float = LFX.vseed(u, fp)
	var t: Texture2D = u._strip_tex(SD_TRAIL)
	var L: float = fp.distance_to(tp)
	var uw: float = minf(t.get_width() * 0.95, L / (PF.tex_w(u, SD_TRAIL) / t.get_width()))
	u.strip(SD_TRAIL, fp + Vector2(0, 8), {"layer": "back", "ang": (tp - fp).angle(), "o": Vector2(0.0, t.get_height() * 0.5), "ux": floorf(PF.h(vs) * (t.get_width() - uw)),
		"uw": uw, "sx": L / (uw * PF.tex_w(u, SD_TRAIL) / t.get_width()), "rev": 0.1, "rev0": 0.2, "life": 1.7, "fade": 0.6,
		"col": Color(1.0, 1.0, 1.05, 0.9), "col1": Color(0.35, 0.5, 0.65, 0.7), "cold": 1.0})
	for k in 3:
		PF.dust(u, fp.lerp(tp, (k + 0.5) / 3.0) + Vector2(0, 6), 90.0, 0.04 * k, vs + k, Vector2.ZERO, Color(0.6, 0.72, 0.82))
	u.light(fp.lerp(tp, 0.5), 160.0, SD_BLUE, 0.3)


static func skadi_tick(u, fp: Vector2, tp: Vector2, j: int) -> void:
	PF.particles(u, fp.lerp(tp, 0.2 + 0.3 * j), 40, "ult_burst_s", [SD_BLUE], 0.0, float(j) * 5.0 + fp.x, 50.0)
