extends RefCounted
## Optional minion warning presentation. Never changes warning state or hit geometry.
const Bal = preload("res://scripts/core/balance.gd")

static func owns(w: Dictionary) -> bool:
	if Bal.v("render/warn_v2", 0.0) <= 0.0:
		return false
	var owner = w.get("owner")
	return owner is Dictionary and not owner.get("boss", false) and not owner.get("elite", false) and not owner.get("squad", false) and not owner.get("cross_elite", false) and not w.get("must_dash", false) and int(w.get("style", 1)) not in [0, 4, 5] and str(w.get("shape", "")) in ["circle", "line", "cone"]

static func urgency(w: Dictionary) -> float:
	return clampf(1.0 - (float(w.dur) - float(w.t)) / maxf(0.01, Bal.v("render/warn_v2_final", 0.3)), 0.0, 1.0)

static func color() -> Color:
	return Color(Bal.v("render/warn_v2_r", 0.82), Bal.v("render/warn_v2_g", 0.84), Bal.v("render/warn_v2_b", 0.9))

static func polygon(g, w: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match str(w.shape):
		"circle":
			for i in 48:
				var angle: float = TAU * i / 48.0
				pts.append(w.pos + Vector2(cos(angle), sin(angle) * g.combat.GROUND_Y) * float(w.r))
		"line":
			var d := Vector2.from_angle(w.ang)
			var n: Vector2 = d.orthogonal() * float(w.wid)
			pts.append_array([w.pos + n, w.pos + d * w.len + n, w.pos + d * w.len - n, w.pos - n])
		"cone":
			pts.append(w.pos)
			for i in 25:
				pts.append(w.pos + Vector2.from_angle(w.ang - w.half + 2.0 * w.half * i / 24.0) * w.r)
	return pts

static func fill(g, w: Dictionary) -> void:
	if w.done:
		return # No expanding inner disk or full-area resolution flash.
	var c := color()
	c.a = clampf(Bal.v("render/warn_v2_fill", 0.0), 0.0, 0.15)
	if c.a > 0.0:
		g.wcv.draw_colored_polygon(polygon(g, w), c)

static func stroke(g, points: PackedVector2Array, c: Color, width: float, dim := false) -> void:
	# A fixed dark keyline separates the boundary from both bright VFX and dark terrain.
	g.wcv.draw_polyline(points, Color(0.025, 0.035, 0.055, 0.65 if dim else 0.96), width + (2.0 if dim else 4.0))
	g.wcv.draw_polyline(points, c, width)

static func outline(g, w: Dictionary) -> void:
	var u := urgency(w)
	var c := color().lerp(Color.WHITE, u)
	c.a = Bal.v("render/warn_v2_idle_a", 0.94)
	var pts := polygon(g, w)
	pts.append(pts[0])
	if w.get("dim", false):
		# Not on the leader's collision path: keep the extent readable without urgency marks.
		stroke(g, pts, Color(0.55, 0.58, 0.65, 0.85), 2.0, true)
		return
	# PX=2: one art pixel normally, two in the last 0.3 s; no moving or flashing fill.
	var width := 4.0 if u > 0.0 else 2.0
	stroke(g, pts, c, width)
	if str(w.shape) == "line" and str(w.get("act", "")) in ["stab", "dash"]:
		var d := Vector2.from_angle(w.ang)
		var n := d.orthogonal()
		var tip: Vector2 = w.pos + d * float(w.len)
		var size: float = minf(float(w.wid), 12.0)
		stroke(g, PackedVector2Array([tip - d * size * 1.5 + n * size, tip, tip - d * size * 1.5 - n * size]), c, width)
	elif str(w.shape) == "cone":
		var front := PackedVector2Array()
		for i in 25:
			front.append(w.pos + Vector2.from_angle(w.ang - w.half + 2.0 * w.half * i / 24.0) * w.r)
		stroke(g, front, c, 4.0)
		# A short inset point marks the attack axis without extending the real outer edge.
		var d := Vector2.from_angle(w.ang)
		var n := d.orthogonal()
		var tip: Vector2 = w.pos + d * float(w.r)
		stroke(g, PackedVector2Array([tip - d * 14.0 + n * 7.0, tip, tip - d * 14.0 - n * 7.0]), c, width)
	elif str(w.shape) == "circle":
		var angle: float = float(w.get("ang", 0.0))
		for offset in [-0.28, 0.0, 0.28]:
			var a: float = angle + float(offset)
			var d := Vector2(cos(a), sin(a) * g.combat.GROUND_Y)
			var tip: Vector2 = w.pos + d * float(w.r)
			stroke(g, PackedVector2Array([tip - d * 10.0, tip]), c, width)
