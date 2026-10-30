## pixfx 公用画法（docs/199 §7.6–7.8，做法见 .claude/skills/pixfx）：pixgen 出的单张大贴图 + 代码驱动动画，给 ult_moves_b / _c 的各人终结技用。
## 全是画面：只调 u.strip / u.shape / u.grain / u.light，不碰 u.hit 与模拟随机数（散布按 h() 哈希）。
## 贴图都是 @2x、1 纹素 = 1 世界像素（sc 1 时），一格 3×3 纹素 = ult/px_grid。
extends RefCounted

const A = preload("res://scripts/art.gd")
const ROCK := "fx_ul_rock"   # 4 帧地块（第 2 帧整块发青，不用）
const WALL := "fx_ul_dust_wall"   # 尘土墙长条（截弦长段沿圈摆）


static func h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


## 贴图在 sc 1 时的世界宽度
static func tex_w(u, name: String) -> float:
	var t: Texture2D = u._strip_tex(name)
	return t.get_width() / A.hires_of(t) * u.g.PX if t != null else 1.0


## 一块地块飞起落回：v 水平初速、vy 上抛速度（落回原高度的寿命 = 2·vy/grav）
static func rock(u, p: Vector2, v: Vector2, vy: float, hh: float, sc: float, delay: float, col := Color.WHITE) -> void:
	if not u.fx_ready(ROCK):
		return
	var grav: float = 1500.0
	u.strip(ROCK, p, {"f": [0, 1, 3, 0][int(hh * 97.0) % 4], "sc": sc + 0.2 * h(hh * 17.0), "col": col,
		"v": v + Vector2(0, -vy), "grav": grav, "life": 2.0 * vy / grav, "spin": (hh - 0.5) * 10.0, "delay": delay})


## 沿圈隆起：半径 r 上一圈地块顶起一小跳落回、每 4 块 1 块高飞；delay 整圈延后（波前到达时刻）
static func heave(u, c: Vector2, r: float, seed0: float, delay := 0.0, col := Color.WHITE, per := 120.0) -> void:
	var nr: int = maxi(4, roundi(TAU * r / per))
	for q in nr:
		var hh: float = h(seed0 * 37.0 + q * 7.0)
		var dv: Vector2 = Vector2.from_angle(seed0 * 0.41 + TAU * (q + 0.6 * hh) / nr)
		var p: Vector2 = c + dv * r * (0.86 + 0.16 * hh)
		var high: bool = q % 4 == 0
		rock(u, p, dv * ((60.0 + 80.0 * hh) if high else 25.0), (260.0 + 160.0 * hh) if high else (110.0 + 60.0 * hh), hh, 0.5 if high else 0.42, delay + 0.02 * (q % 3), col)
		if q % 3 == 0:
			u.grain("bfx_dust", p, dv, Color(0.58, 0.58, 0.56), 3)


## 余震：delay 秒后半径 R 内再跳一批碎石
static func aftershock(u, c: Vector2, R: float, seed0: float, delay: float, n := 10, col := Color.WHITE) -> void:
	for q in n:
		var hh: float = h(q * 5.0 + seed0 * 11.0)
		rock(u, c + Vector2.from_angle(TAU * (q + hh) / n) * R * (0.25 + 0.7 * hh), Vector2.ZERO, 120.0 + 60.0 * hh, hh, 0.4, delay + 0.05 * (q % 3), col)


## 尘土墙：WALL 截成弦长段沿圈摆一圈，整圈往外推、淡出
static func wall(u, c: Vector2, r: float, delay := 0.0, col := Color(1, 1, 1, 0.85)) -> void:
	if not u.fx_ready(WALL):
		return
	var t: Texture2D = u._strip_tex(WALL)
	var k: float = u.g.PX / A.hires_of(t)
	var n: int = maxi(12, roundi(TAU * r / 150.0))
	var chord: float = 2.0 * r * sin(PI / n)
	var uw: float = minf(t.get_width(), chord * 1.15 / k)
	for q in n:
		var a0: float = TAU * q / n
		var p0: Vector2 = c + Vector2.from_angle(a0) * r
		var p1: Vector2 = c + Vector2.from_angle(a0 + TAU / n) * r
		var d: Vector2 = (p1 - p0).normalized()
		u.strip(WALL, p0 - d * chord * 0.07, {"layer": "back", "ang": d.angle(), "o": Vector2(0.0, t.get_height() * 0.5),
			"ux": floorf(h(q * 3.0 + 7.0) * (t.get_width() - uw)), "uw": uw, "v": Vector2.from_angle(a0 + PI / n) * 140.0,
			"life": 0.6, "fade": 0.4, "col": col, "delay": delay})


## 放射裂网：name = 分叉裂缝贴图（左粗右细带分叉，原点左端中心）；angs 每条的角度，lens 每条的长度（世界）；
## opt：rev（显现秒数）/ rev0 / life / fade / col / col1 / cold / delay（最大随机错开）/ big（粗条的 sy）/ small
static func cracks(u, name: String, c: Vector2, angs: Array, lens: Array, opt: Dictionary) -> void:
	if not u.fx_ready(name):
		return
	var t: Texture2D = u._strip_tex(name)
	var tw: float = tex_w(u, name)
	for j in angs.size():
		var s := {"layer": "back", "ang": float(angs[j]), "o": Vector2(0.0, t.get_height() * 0.5),
			"sx": float(lens[j]) / tw, "sy": float(opt.get("big", 0.85) if j % 3 == 0 else opt.get("small", 0.55)) * (1.0 if j % 2 == 0 else -1.0),
			"delay": float(opt.get("delay", 0.04)) * h(j + 110.0), "rev": float(opt.get("rev", 0.3)), "rev0": float(opt.get("rev0", 0.15)),
			"life": float(opt.get("life", 1.4)), "fade": float(opt.get("fade", 0.6)), "col": opt.get("col", Color.WHITE)}
		if opt.has("col1"):
			s["col1"] = opt.col1
			s["cold"] = float(opt.get("cold", 0.6))
		u.strip(name, c, s)


## 不规整放射角度：n 条，从 a0 起均分、每条按哈希偏 ±0.35 格
static func angles(n: int, a0: float, seed0: float) -> Array:
	var out: Array = []
	for j in n:
		out.append(a0 + TAU * (j + (h(j + seed0) - 0.5) * 0.7) / n)
	return out


## 整圈环贴图从半径 r0 扩到 r1（dur 秒缓出），life 内淡出
static func ring(u, name: String, c: Vector2, r0: float, r1: float, dur: float, life: float, opt := {}) -> Dictionary:
	if not u.fx_ready(name):
		return {}
	var rr: float = tex_w(u, name) * 0.5
	var s := {"layer": str(opt.get("layer", "back")), "sc": r0 / rr, "sc1": r1 / rr, "scd": dur, "life": life,
		"fade": float(opt.get("fade", life * 0.5)), "ang": float(opt.get("ang", 0.0)), "col": opt.get("col", Color.WHITE), "delay": float(opt.get("delay", 0.0))}
	if opt.has("col1"):
		s["col1"] = opt.col1
		s["cold"] = float(opt.get("cold", 0.3))
	return u.strip(name, c, s)
