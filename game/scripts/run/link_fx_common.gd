## 技能连携（docs/199 §7.5）画面公用件（用户 10-31「先做美术」；两组会话 claude/link-fx-a / link-fx-b 共用、内容一致）：
## ① 衔接：现身段（skill_link.PRE 0.18 秒）里队长先亮一下队长色 → 一道接力光从队长飞到接手队友脚下（队长色渐变到队友色、带拖尾）→ 队友脚下亮起本人色光柱；
## ② 小工具：哈希 / 变体种子 / 挑变体 / 贴图宽。
## 只画画面（u.strip / u.shape / u.light / u.grain），不抽模拟随机数；不加冲击帧、不整屏白闪（用户 10-31）；亮度 ≤ 0.85。
## 贴图缺时 appear() 返回 false，调用方照画原来的程序光柱。
extends RefCounted

const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")
const BEACONS := ["fx_link_beacon1", "fx_link_beacon2", "fx_link_beacon3"]   # 中性灰竖光柱（按人着色）
const RELAY := ["fx_link_relay1", "fx_link_relay2", "fx_link_relay3"]        # 中性灰彗星光（头在右、尾往左）


## 总开关 ult/link_fx_v2（缺省 1；0 = 原来的程序占位，录新旧对照用）
static func on() -> bool:
	return Bal.v("ult/link_fx_v2", 1.0) > 0.0


static func h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


## 每次出手的变体种子（出手时刻 + 位置的哈希；同种子同局可重现）
static func vseed(u, c: Vector2) -> float:
	return floorf(h(u.g.t * 1.37 + c.x * 0.013 + c.y * 0.029) * 997.0)


static func pick(u, names: Array, x: float) -> String:
	var ok: Array = []
	for n in names:
		if u.fx_ready(n):
			ok.append(n)
	return "" if ok.is_empty() else str(ok[int(h(x) * ok.size()) % ok.size()])


## 贴图在 sc 1 时的世界宽 / 高
static func tex_w(u, name: String) -> float:
	var t: Texture2D = u._strip_tex(name)
	return t.get_width() / A.hires_of(t) * u.g.PX if t != null else 1.0


static func tex_h(u, name: String) -> float:
	var t: Texture2D = u._strip_tex(name)
	return t.get_height() / A.hires_of(t) * u.g.PX if t != null else 1.0


## 着色：贴图是中性灰，乘上人色；整体亮度封顶 0.85
static func tint(c: Color, k := 1.0, al := 1.0) -> Color:
	var m: float = maxf(c.r, maxf(c.g, c.b))
	var s: float = minf(k, 0.85 / maxf(0.01, m) * 1.15)
	return Color(c.r * s, c.g * s, c.b * s, al)


## 现身段每帧调（t = 0..PRE）：第一帧放衔接（队长亮 → 接力光 → 队友光柱），之后光柱随 t 收细；返回 false = 贴图缺，调用方照旧画
static func appear(u, p, t: float, pre: float, cp: Color) -> bool:
	if not on() or not u.fx_ready(BEACONS[0]):
		return false
	var key := "link_fx_t0"
	var t0: float = float(p.get_meta(key, -99.0)) if p.has_meta(key) else -99.0
	if u.g.t - t0 > pre + 0.05:   # 新的一次现身：放一次衔接
		p.set_meta(key, u.g.t)
		_handoff(u, p, pre, cp)
	return true


static func _handoff(u, p, pre: float, cp: Color) -> void:
	var vs: float = vseed(u, p.pos)
	var ld = u.g.squad.leader() if u.g.squad != null else null
	var lp: Vector2 = ld.pos if ld != null and ld.pos != Vector2.INF else p.pos
	var lc: Color = u._col(ld) if ld != null else cp
	# 队长身上亮一下（队长色，短）
	u.light(lp, 70.0, lc, 0.12)
	u.grain("mote_up", lp + Vector2(0, -20), Vector2.UP, lc, 3)
	# 接力光：从队长胸口飞到队友脚下，0.1 秒内显现到头（rev），头部队友色、尾部队长色两层叠
	var a0: Vector2 = lp + Vector2(0, -22)
	var b0: Vector2 = p.pos + Vector2(0, -6)
	var L: float = a0.distance_to(b0)
	if L > 24.0 and u.fx_ready(RELAY[0]):
		var name: String = pick(u, RELAY, vs)
		var tw: float = tex_w(u, name)
		var th: float = u._strip_tex(name).get_height()
		var ang: float = (b0 - a0).angle()
		var sy: float = (-1.0 if h(vs + 1.0) < 0.5 else 1.0) * 0.8
		u.strip(name, a0, {"ang": ang, "o": Vector2(0.0, th * 0.5), "sx": L / tw, "sy": sy, "rev": 0.1, "rev0": 0.05, "life": pre + 0.12, "fade": 0.14,
			"col": tint(lc, 1.0, 0.75)})
		u.strip(name, a0, {"ang": ang, "o": Vector2(0.0, th * 0.5), "sx": L / tw, "sy": sy * 0.55, "rev": 0.1, "rev0": 0.05, "life": pre + 0.1, "fade": 0.12,
			"col": tint(cp, 1.05, 0.95)})
	# 队友脚下：本人色光柱（3 种按 vseed 挑、随机镜像），0.08 秒后（接力光到）立起
	var bn: String = pick(u, BEACONS, vs + 3.0)
	var bt: Texture2D = u._strip_tex(bn)
	var bh: float = tex_h(u, bn)
	var sc: float = 96.0 / maxf(1.0, bh)
	u.strip(bn, p.pos + Vector2(0, 4), {"o": Vector2(bt.get_width() * 0.5, bt.get_height() - 2.0), "sc": sc, "sx": -1.0 if h(vs + 2.0) < 0.5 else 1.0,
		"delay": 0.07, "life": pre + 0.2, "fade": 0.2, "col": tint(cp, 1.0, 0.85)})
	u.light(p.pos, 90.0, cp, pre + 0.1)
