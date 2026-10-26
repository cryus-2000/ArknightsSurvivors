extends RefCounted
## 激光 / 光束改版原型（10-24 协调人转用户「现在的激光表现方式你觉得是不是可以更改一下？」，docs/138 §12）：
## 接管 world._draw_fx 里的 "beam"（治疗 / 无人机连线）、"bbeam"（Boss 粗光束）、"tracer"（狙击 / 穿刺弹道）三种画法，
## 以及干员画布上带 laser 标记的 "line"（艾琳枪线、维什戴尔炮线、流明折射；10-25 用户「激光就选 A」覆盖全部激光）。
## 开关 fx/laser_style：0 = 原样（缺省，返回 false 交回原画法）；1 = A 像素光束；2 = B 颗粒光束。纯画面，随机只走 g.vrng。
## 共同点：光束 0.06 秒内从起点伸到终点（不再满长度瞬间出现）；颜色压回 ≤ 1（不靠 HDR 糊辉光）；不画常驻大光晕、不按 sin 抖宽度（原 bbeam 40 Hz 抖动）。
const Bal = preload("res://scripts/core/balance.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")
const GROW := 0.06   # 伸出时长（秒）

static func style() -> int:
	return int(Bal.v("fx/laser_style", 0.0))


## a = 剩余寿命比例（1 → 0）；ci = 画在哪个画布（缺省世界节点 g；干员激光线 "line" 传干员自己的画布）。返回 true = 已画（调用方跳过原画法）
static func draw(g, f: Dictionary, a: float, ci = null) -> bool:
	var st: int = style()
	if st <= 0:
		return false
	# 淡出按模拟 / 真实时间里走得快的那个（boss_beam.laser_el）：掉帧、顿帧时也在寿命内收完（用户 10-26「激光打完消失得很慢」）
	a = minf(a, 1.0 - BossBeam.laser_el(f) / maxf(0.001, float(f.max)))
	if a <= 0.0:
		return true
	if ci == null:
		ci = g
	var grains = g.optical.grains if g.optical != null and g.optical.grains != null and g.optical.grains.on() else null
	if st == 2 and grains == null:
		st = 1   # 颗粒池不开（低画质 / 关光学观感）时退回 A
	var p0: Vector2 = f.a if f.has("a") else f.pos   # 干员激光线（"line"，laser 标记）用 pos / to
	var p1: Vector2 = f.b if f.has("b") else f.get("to", f.pos)
	var el: float = float(f.max) * (1.0 - a)
	var grow: float = clampf(el / GROW, 0.0, 1.0)
	var pe: Vector2 = p0.lerp(p1, grow)
	var c: Color = _unit(f.col)
	var base: float = _base_w(f)
	if st == 1:
		_draw_a(ci, g, f, p0, pe, p1, c, base, a, el, grains)
	else:
		_draw_b(ci, g, f, p0, pe, p1, c, base, a, el, grains)
	return true


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


## B 颗粒光束：只留 2 px 细芯（前七成寿命），光束本体在伸到头那一刻沿线每 2.5 px 生成一颗颗粒（最多 220），
## 顺着光束方向飘、按刀光模板冷却熄灭——光束「碎成颗粒」消散
static func _draw_b(ci, g, f: Dictionary, p0: Vector2, pe: Vector2, p1: Vector2, c: Color, base: float, a: float, el: float, grains) -> void:
	var k: float = 1.0 - a
	if k < 0.7:
		var hi: Color = c.lerp(Color.WHITE, 0.6)
		ci.draw_line(p0, pe, Color(hi.r, hi.g, hi.b, a), 2.0 if base < 8.0 else 4.0)
	if el >= GROW and not f.get("lz_emit", false):
		f["lz_emit"] = true
		var d: Vector2 = p1 - p0
		var dir: Vector2 = d.normalized()
		var nrm: Vector2 = dir.orthogonal()
		var n: int = mini(220, int(d.length() / 2.5))
		var half: float = base * 0.5
		for i in n:
			var t: float = (float(i) + g.vrng.randf()) / maxf(1.0, float(n))
			var off: Vector2 = nrm * g.vrng.randf_range(-half, half)
			grains.push("slash", p0.lerp(p1, t) + off, dir, c)


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
