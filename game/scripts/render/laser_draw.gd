extends RefCounted
## 激光 / 光束改版原型（10-24 协调人转用户「现在的激光表现方式你觉得是不是可以更改一下？」，docs/138 §12）：
## 接管 world._draw_fx 里的 "beam"（治疗 / 无人机连线）、"bbeam"（Boss 粗光束）、"tracer"（狙击 / 穿刺弹道）三种画法，
## 以及干员画布上带 laser 标记的 "line"（艾琳枪线、维什戴尔炮线、流明折射；10-25 用户「激光就选 A」覆盖全部激光）。
## 10-29 起固定为 A 像素光束（旧开关 fx/laser_style 已删：0 原画法、2 B 颗粒光束两条一并删掉）。纯画面，随机只走 g.vrng。
## 共同点：光束 0.06 秒内从起点伸到终点（不再满长度瞬间出现）；颜色压回 ≤ 1（不靠 HDR 糊辉光）；不画常驻大光晕、不按 sin 抖宽度（原 bbeam 40 Hz 抖动）。
const BossBeam = preload("res://scripts/render/boss_beam.gd")
const Bal = preload("res://scripts/core/balance.gd")
const GROW := 0.06   # 伸出时长（秒）

## a = 剩余寿命比例（1 → 0）；ci = 画在哪个画布（缺省世界节点 g；干员激光线 "line" 传干员自己的画布）
static func draw(g, f: Dictionary, a: float, ci = null) -> void:
	# 淡出按模拟 / 真实时间里走得快的那个（boss_beam.laser_el）：掉帧、顿帧时也在寿命内收完（用户 10-26「激光打完消失得很慢」）
	a = minf(a, 1.0 - BossBeam.laser_el(f) / maxf(0.001, float(f.max)))
	if a <= 0.0:
		return
	if ci == null:
		ci = g
	var grains = g.optical.grains if g.optical != null and g.optical.grains != null and g.optical.grains.on() else null
	var p0: Vector2 = f.a if f.has("a") else f.pos   # 干员激光线（"line"，laser 标记）用 pos / to
	var p1: Vector2 = f.b if f.has("b") else f.get("to", f.pos)
	var el: float = float(f.max) * (1.0 - a)
	var grow: float = clampf(el / GROW, 0.0, 1.0)
	var pe: Vector2 = p0.lerp(p1, grow)
	var c: Color = _unit(f.col)
	var base: float = _base_w(f)
	if Bal.v("render/laser_v2", 1.0) > 0.0:
		_draw_v2(ci, p0, pe, c, base, a, el, el >= GROW)
		return
	_draw_a(ci, g, f, p0, pe, p1, c, base, a, el, grains)


## A 像素光束：宽度先张开再收（前 15% 寿命从 0.6 张到 1，之后收到 0.25）；三层硬边：外层本色 → 中层亮色 → 2 px 白芯；
## 伸到头那一刻沿线迸少量火花（每 24 px 一颗，最多 24），末端两帧小菱形命中闪
static func _draw_a(ci, g, f: Dictionary, p0: Vector2, pe: Vector2, p1: Vector2, c: Color, base: float, a: float, el: float, grains) -> void:
	var k: float = 1.0 - a
	var prof: float = lerpf(0.6, 1.0, k / 0.15) if k < 0.15 else lerpf(1.0, 0.25, (k - 0.15) / 0.85)
	var w: float = _snap2(base * prof)
	var hi: Color = c.lerp(Color.WHITE, 0.55)
	ci.draw_line(p0, pe, Color(c.r, c.g, c.b, 0.55 * a), w)
	ci.draw_line(p0, pe, Color(hi.r, hi.g, hi.b, 0.9 * a), _snap2(w * 0.5))
	ci.draw_line(p0, pe, Color(1, 1, 1, a), 2.0)
	if el >= GROW and el < GROW + 0.1:
		var s: float = 6.0 if el < GROW + 0.05 else 3.0
		var q: Vector2 = (p1 / 2.0).floor() * 2.0
		ci.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -s), q + Vector2(s, 0), q + Vector2(0, s), q + Vector2(-s, 0)]), Color(1, 1, 1, a))
	if grains != null and el >= GROW and not f.get("lz_emit", false):
		f["lz_emit"] = true
		var d: Vector2 = p1 - p0
		var n: int = mini(24, int(d.length() / 24.0))
		var nrm: Vector2 = d.normalized().orthogonal()
		for i in n:
			var t: float = (float(i) + g.vrng.randf()) / maxf(1.0, float(n))
			grains.push("slash", p0.lerp(p1, t), nrm * (1.0 if g.vrng.randf() < 0.5 else -1.0), c)


static func _base_w(f: Dictionary) -> float:
	match str(f.kind):
		"beam":
			return maxf(4.0, float(f.get("w", 2.5)) * 2.0)
		"bbeam":
			return maxf(8.0, float(f.get("wid", 20.0)) * 1.2)
		"line":
			return maxf(4.0, float(f.get("w", 2.0)) * 2.0)
		_:
			return maxf(4.0, float(f.get("wid", 8.0)) * 0.6)


static func _unit(c: Color) -> Color:
	var mx: float = maxf(c.r, maxf(c.g, c.b))
	return Color(c.r / mx, c.g / mx, c.b / mx) if mx > 1.0 else Color(c.r, c.g, c.b)


static func _snap2(v: float) -> float:
	return maxf(2.0, roundf(v / 2.0) * 2.0)


## ---- 统一激光（TA 审阅 docs/208 H3，10-31：「光束不像激光」；开关 render/laser_v2 缺省 1，0 = 上面的 A 像素光束）。
## 照伊莎玛拉那套（claude/ishar-polish ishar_tell_draw._laser，那边不改）：一整条一次画完，由外到内两层低透明外晕（宽 2.2 / 1.5 倍）→ 本色光身 → 亮色 → 白芯；
## 起点一颗大光点、伸到头后终点一颗小光点；开火前 0.06 秒从 0.3 宽张满 + 白闪，寿命后 85% 整条收细、外晕先散。各处只换颜色（敌方用敌方色）
static func _draw_v2(ci, p0: Vector2, pe: Vector2, c: Color, base: float, a: float, el: float, reached: bool) -> void:
	var k: float = 1.0 - a
	var open: float = clampf(0.3 + el / GROW, 0.3, 1.0) * (lerpf(1.0, 0.2, (k - 0.15) / 0.85) if k > 0.15 else 1.0)
	var flash: float = clampf(1.0 - el / 0.1, 0.0, 1.0)
	var glow: float = a * a
	var w: float = base * open
	ci.draw_line(p0, pe, Color(c.r, c.g, c.b, 0.1 * glow), _snap2(w * 2.2))
	ci.draw_line(p0, pe, Color(c.r, c.g, c.b, 0.16 * glow), _snap2(w * 1.5))
	ci.draw_line(p0, pe, Color(c.r, c.g, c.b, 0.8 * a), _snap2(maxf(2.0, w * 0.68)))
	var hi: Color = c.lerp(Color.WHITE, 0.6)
	ci.draw_line(p0, pe, Color(hi.r, hi.g, hi.b, 0.95 * a), _snap2(maxf(2.0, w * 0.32)))
	ci.draw_line(p0, pe, Color(1, 1, 1, a), 2.0)
	if flash > 0.0:
		ci.draw_line(p0, pe, Color(1, 1, 1, 0.5 * flash * a), _snap2(w * 0.8))
	dot(ci, p0, maxf(3.0, base * 0.42 * open) * (1.0 + 0.4 * flash), c, a)
	if reached:
		dot(ci, pe, maxf(2.0, base * 0.26 * open) * (1.0 + 0.6 * flash), c, a * 0.9)


## 光点：外晕（本色、低透明）→ 亮色 → 白芯
static func dot(ci, p: Vector2, r: float, c: Color, alpha: float) -> void:
	ci.draw_circle(p, r * 1.7, Color(c.r, c.g, c.b, 0.18 * alpha))
	var hi: Color = c.lerp(Color.WHITE, 0.6)
	ci.draw_circle(p, r, Color(hi.r, hi.g, hi.b, 0.85 * alpha))
	ci.draw_circle(p, r * 0.5, Color(1, 1, 1, alpha))


## Boss 帧条激光（kp_beam，原 BossBeam 平铺 Kanpelle 帧条，TA 审阅「粉白扁条、红色锯齿边」）改走统一激光：开合按 on_t、宽按 k、敌方色
const KP_COL := Color(1.0, 0.32, 0.4)


static func draw_kp(g, f: Dictionary) -> void:
	var el: float = BossBeam.laser_el(f)
	var left: float = float(f.max) - el
	if left <= 0.0:
		return
	var on_t: float = float(f.get("on_t", 0.06))
	var p0: Vector2 = f.a
	var p1: Vector2 = f.b
	var base: float = 9.0 * float(f.get("k", 2.0))
	var a: float = clampf(left / maxf(0.001, on_t * 2.0), 0.0, 1.0)
	var c: Color = _unit(f.get("col", KP_COL))
	_draw_v2(g, p0, p0.lerp(p1, clampf(el / GROW, 0.0, 1.0)), c, base, maxf(a, 0.25) if left > on_t * 2.0 else a, el, el >= GROW)
