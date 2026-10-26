extends RefCounted
## Pure drawing. No RNG or quality-dependent damage geometry; low quality keeps all outlines.
static func draw(g, impacts := false) -> void:
	if not impacts:
		for w in g.warns:
			if w.act == "final_attack" and not w.done:
				_shape(g, w, 0.52 + 0.38 * clampf(w.t / w.dur, 0.0, 1.0), true)
		for h in g.bai.finals.hazards:
			if g.bosses.has(h.owner) and not g.bai.finals.cancelled(h):
				_shape(g, h, 0.9, false)
	else:
		for f in g.fx:
			if f.kind == "final_impact" and f.life > 0.0:
				_shape(g, f, float(f.life) / float(f.max), false)
	g.world.tb_flush()

static func _shape(g, w: Dictionary, alpha: float, warning: bool) -> void:
	var r = g.world
	var c: Color = w.col
	var skin: String = str(w.get("skin", ""))
	var core := Color(1.6, 1.85, 2.0, alpha)
	var edge := Color(0.025, 0.035, 0.065, minf(1.0, alpha + 0.3))
	var tint := Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, alpha)
	var phase: float = float(w.get("age", w.get("t", 0.0)))
	match str(w.shape):
		"circle":
			var inner: float = float(w.get("inner_r", 0.0))
			var gy: float = g.combat.GROUND_Y
			# Draw annuli as individual quads: no filled safe center and exact ground projection.
			for i in 40:
				var a: float = TAU * i / 40.0
				var b: float = TAU * (i + 1) / 40.0
				var va := Vector2(cos(a), sin(a) * gy)
				var vb := Vector2(cos(b), sin(b) * gy)
				r.tb_quad(w.pos + va * inner, w.pos + va * w.r, w.pos + vb * w.r, w.pos + vb * inner,
					Color(c.r, c.g, c.b, alpha * 0.22))
			r.tb_arc(w.pos, w.r, 0.0, TAU, 5.0, edge, 40, gy)
			r.tb_arc(w.pos, w.r, 0.0, TAU, 3.0, tint, 40, gy)
			if inner > 0.0:
				r.tb_arc(w.pos, inner, 0.0, TAU, 3.0, core, 40, gy)
			if skin == "bubble":
				r.tb_arc(w.pos, w.r * 0.95, phase, phase + PI * 0.8, 2.5, core, 12, gy)
				r.tb_arc(w.pos, w.r * 0.72, -2.7, -1.0, 3.0, core, 10, gy)
				r.tb_circle(w.pos + Vector2(-w.r * 0.3, -w.r * 0.2), 3.0, Color.WHITE)
			elif skin == "choir":
				for j in 3:
					r.tb_arc(w.pos, w.r * (0.4 + 0.2 * j), phase, phase + PI * 1.4, 2.0, tint, 16, gy)
		"line":
			var d := Vector2.from_angle(w.ang)
			var n := d.orthogonal()
			var end: Vector2 = w.pos + d * w.len
			if not warning and skin == "crescent":
				# A continuous tapered blade, not a rectangle or a string of disconnected particles.
				var middle: Vector2 = w.pos.lerp(end, 0.5)
				for j in 24:
					var u: float = j / 24.0 * 2.0 - 1.0
					var v: float = (j + 1) / 24.0 * 2.0 - 1.0
					var p: Vector2 = middle + d * u * 90.0 + n * (1.0 - u * u) * 13.0
					var q: Vector2 = middle + d * v * 90.0 + n * (1.0 - v * v) * 13.0
					var width: float = 3.0 + (1.0 - absf(u)) * 9.0
					r.tb_line(p, q, edge, width + 4.0)
					r.tb_line(p, q, tint, width)
					r.tb_line(p, q, core, maxf(1.5, width * 0.3))
				return
			if warning and skin == "tide":
				var travel: Vector2 = w.velocity * w.life
				r.tb_quad(w.pos, end, end + travel, w.pos + travel, Color(c.r, c.g, c.b, 0.1))
				r.tb_line(w.pos, w.pos + travel, tint, 2.0)
				r.tb_line(end, end + travel, tint, 2.0)
				for j in 6:
					var at: Vector2 = w.pos.lerp(end, 0.5) + travel * (j + 0.5) / 6.0
					var heading: Vector2 = travel.normalized()
					r.tb_line(at - heading * 12.0 + d * 9.0, at, core, 2.0)
					r.tb_line(at - heading * 12.0 - d * 9.0, at, core, 2.0)
			r.tb_line(w.pos, end, Color(c.r, c.g, c.b, alpha * 0.2), w.wid * 2.0)
			for s in [-1.0, 1.0]:
				r.tb_line(w.pos + n * w.wid * s, end + n * w.wid * s, edge, 5.0)
				r.tb_line(w.pos + n * w.wid * s, end + n * w.wid * s, core, 2.0)
			var count: int = maxi(3, mini(20, ceili(w.len / 32.0)))
			for i in count:
				var p: Vector2 = w.pos.lerp(end, (i + 0.5) / count)
				if skin in ["ice", "spear"]:
					r.tb_poly(PackedVector2Array([p - d * 10.0, p + n * w.wid * 0.7, p + d * 16.0, p - n * w.wid * 0.7]), tint)
				elif skin == "tentacle":
					var u: float = float(i) / count
					var v: float = float(i + 1) / count
					var p0: Vector2 = w.pos.lerp(end, u) + n * sin(u * 11.0 + phase * 4.0) * w.wid * 0.28
					var p1: Vector2 = w.pos.lerp(end, v) + n * sin(v * 11.0 + phase * 4.0) * w.wid * 0.28
					var width: float = w.wid * (1.15 - u * 0.9)
					r.tb_line(p0, p1, edge, width + 5.0)
					r.tb_line(p0, p1, Color(c.r * 0.6, c.g * 1.25, c.b * 1.4, alpha), width)
					r.tb_line(p0 - n * width * 0.25, p1 - n * width * 0.22, tint, 2.0)
					r.tb_circle(p0 + n * width * 0.2, maxf(1.5, width * 0.12), core, 1.0, 7)
				elif skin == "tide":
					var crest: Vector2 = p + n * sin(i * 1.8 + phase * 4.0) * w.wid * 0.35
					r.tb_arc(crest, w.wid * 0.65, w.ang - PI, w.ang, 3.5, core, 8)
				else:
					r.tb_line(p - n * w.wid * 0.6, p + n * w.wid * 0.6 + d * 8.0, tint, 2.0)
			if skin == "phantom":
				r.tb_circle(w.pos, 22.0, tint, 1.5, 14)
				r.tb_arc(w.pos, 30.0, 0.1, PI - 0.1, 3.0, core, 12)
		"cone":
			var pts := PackedVector2Array([w.pos])
			for i in 25:
				pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / 24.0) * w.r)
			r.tb_poly(pts, Color(c.r, c.g, c.b, alpha * 0.25))
			r.tb_arc(w.pos, w.r, w.ang - w.half, w.ang + w.half, 5.0, edge, 24)
			r.tb_arc(w.pos, w.r, w.ang - w.half, w.ang + w.half, 2.0, core, 24)
			for s in [-1.0, 1.0]:
				r.tb_line(w.pos, w.pos + Vector2.from_angle(w.ang + w.half * s) * w.r, core, 2.0)
			for j in 3:
				r.tb_arc(w.pos, w.r * (0.45 + j * 0.18), w.ang - w.half, w.ang + w.half, 3.0, tint, 12)
