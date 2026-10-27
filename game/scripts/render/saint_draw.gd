## 圣徒光束的蓄力与消散（docs/171 §7，用户 10-27「激光要有蓄力和消散的感觉」）。纯画面：只读 g.warns / 敌人字典，颗粒只用 g.vrng。
## 蓄力：预警线 w.saint_beam = true 时代替斜纹填充与轮廓——光束从 1 像素细线长到预警宽度，亮度随进度上升，锁定后加白芯；
##       两侧危险色细边标出判定宽度；枪口外一圈颗粒向枪口收拢（mote_in，走 Boss 颗粒预算）。
## 开火：Kanpelle 光束原样短闪（boss_beam.draw）。
## 消散：saint.gd 结算后写 e.beam_fades，FADE 秒内光束变细、断成碎段并逐段熄灭，第一帧沿线迸一串颗粒。
extends RefCounted

const BossBeam = preload("res://scripts/render/boss_beam.gd")
const FADE := 0.32


static func charge(g, w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var k: float = clampf(w.t / maxf(0.01, w.dur), 0.0, 1.0)
	var d := Vector2.from_angle(float(w.ang))
	var a: Vector2 = w.pos + Vector2(0, -16)
	var b: Vector2 = a + d * float(w.len)
	var n: Vector2 = d.orthogonal()
	var hw: float = float(w.wid)
	var bc: Color = g.vfx.boss_color(str(e.type))
	var dc: Color = g.optical.col_danger if g.optical_on else Color(1.0, 0.3, 0.3)
	var locked: bool = float(w.get("track", 0.0)) <= 0.0 or w.t >= float(w.track)
	# 判定宽度：危险色细边（不闪、不填充），锁定后加亮
	var ea: float = (0.35 + 0.35 * k) * (1.3 if locked else 1.0)
	g.draw_line(a + n * hw, b + n * hw, Color(dc.r, dc.g, dc.b, minf(1.0, ea)), 2.0)
	g.draw_line(a - n * hw, b - n * hw, Color(dc.r, dc.g, dc.b, minf(1.0, ea)), 2.0)
	# 光束本体：由细到粗、由暗到亮
	var bw: float = lerpf(1.0, hw * 1.2, pow(k, 0.8))
	g.draw_line(a, b, Color(bc.r, bc.g, bc.b, 0.18 + 0.5 * k), bw)
	if locked:
		var ck: float = 1.6 + 0.6 * k
		g.draw_line(a, b, Color(ck, ck * 0.95, ck * 0.85, 0.35 + 0.5 * k), maxf(1.0, bw * 0.35))
	# 枪口聚光：颗粒从外圈收拢，越接近开火越多
	var gr = BossBeam.grains(g)
	if gr != null and g.vrng.randf() < 0.35 + 0.6 * k:
		for i in BossBeam.take(g, 2):
			var q := Vector2.from_angle(g.vrng.randf() * TAU)
			gr.push("mote_in", a + q * g.vrng.randf_range(34.0, 60.0), -q, bc)


## 伊比利亚「余烬」（docs/171 §9）：落地前 = 落点危险色细圈由大收小 + 从她头顶飞来的火点；落地后 = 暗橙烧地 + 闪烁外沿 + 余烬上飘，最后 0.5 秒变淡
static func embers(g, e: Dictionary) -> void:
	var em: Array = e.get("embers", [])
	if em.is_empty():
		return
	var bc: Color = g.vfx.boss_color(str(e.type))
	var dc: Color = g.optical.col_danger if g.optical_on else Color(1.0, 0.3, 0.3)
	var gr = BossBeam.grains(g)
	for x in em:
		var r: float = float(x.r)
		if g.t < float(x.arm):
			var k: float = clampf((g.t - float(x.born)) / maxf(0.01, float(x.arm) - float(x.born)), 0.0, 1.0)
			g.draw_arc(x.pos, r * (1.35 - 0.35 * k), 0.0, TAU, 32, Color(dc.r, dc.g, dc.b, 0.35 + 0.5 * k), 2.0)
			var fp: Vector2 = Vector2(x.from).lerp(x.pos, k) + Vector2(0, -90.0 * 4.0 * k * (1.0 - k))
			g.draw_circle(fp, 5.0, Color(1.4, 1.0, 0.7))
			g.draw_circle(fp, 8.0, Color(bc.r, bc.g, bc.b, 0.45))
			continue
		var fade: float = clampf((float(x.until) - g.t) / 0.5, 0.0, 1.0)
		var fl: float = 0.85 + 0.15 * sin(g.t * 17.0 + float(x.born) * 5.0)
		g.draw_circle(x.pos, r, Color(bc.r * 0.6, bc.g * 0.35, bc.b * 0.2, 0.32 * fade))
		g.draw_circle(x.pos, r * 0.55, Color(bc.r, bc.g * 0.7, bc.b * 0.4, 0.22 * fade * fl))
		g.draw_arc(x.pos, r, 0.0, TAU, 32, Color(bc.r * 1.3, bc.g, bc.b, 0.75 * fade * fl), 2.0)
		if gr != null and g.vrng.randf() < 0.3 * fade:
			for i in BossBeam.take(g, 1):
				gr.push("mote_up", x.pos + Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf() * r, Vector2.UP, bc)


static func fades(g, e: Dictionary) -> void:
	embers(g, e)
	var fl: Array = e.get("beam_fades", [])
	if fl.is_empty():
		return
	var bc: Color = g.vfx.boss_color(str(e.type))
	var gr = BossBeam.grains(g)
	for f in fl:
		var p: float = clampf((g.t - float(f.born)) / FADE, 0.0, 1.0)
		if p >= 1.0:
			continue
		var a: Vector2 = f.a
		var b: Vector2 = f.b
		var L: float = a.distance_to(b)
		if L < 1.0:
			continue
		var d: Vector2 = (b - a) / L
		if not f.get("burst", false):
			f["burst"] = true
			if gr != null:
				var m: int = BossBeam.take(g, clampi(int(L / 40.0), 6, 24))
				for i in m:
					gr.push("bfx_flash", a + d * L * g.vrng.randf(), d.orthogonal() * (1.0 if g.vrng.randf() < 0.5 else -1.0), bc)
		var wd: float = maxf(1.0, float(f.wid) * 1.1 * (1.0 - p))
		var seg: float = 18.0
		var cnt: int = int(L / seg)
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in cnt:
			var h: float = fposmod(sin(float(i) * 12.9898 + float(f.born) * 3.7) * 43758.5453, 1.0)
			if h < p * 1.15:
				continue   # 逐段熄灭
			var u0: float = float(i) * seg
			pts.append(a + d * u0)
			pts.append(a + d * (u0 + seg * (0.85 - 0.45 * p)))
			var lk: float = 1.4 - 0.6 * p
			cols.append(Color(bc.r * lk, bc.g * lk, bc.b * lk, 0.85 * (1.0 - p)))
		if not cols.is_empty():
			g.draw_multiline_colors(pts, cols, wd)
