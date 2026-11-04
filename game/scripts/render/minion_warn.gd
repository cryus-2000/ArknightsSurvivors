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
	return Color(Bal.v("render/warn_v2_r", 0.70), Bal.v("render/warn_v2_g", 0.23), Bal.v("render/warn_v2_b", 0.24))

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

static func fill(_g, _w: Dictionary) -> void:
	# Zero-fill fallback: any number of overlaps has exactly zero interior opacity.
	# No per-warning alpha blend can enforce a nonzero global cap without a mask pass.
	pass

static func progress(w: Dictionary) -> float:
	return clampf(float(w.t) / maxf(0.01, float(w.dur)), 0.0, 1.0)

static func timer_points(g, w: Dictionary) -> PackedVector2Array:
	# Interior sweep means time only. The full outer danger boundary stays fixed.
	var p := progress(w)
	var pts := PackedVector2Array()
	if p <= 0.0:
		return pts
	match str(w.shape):
		"line":
			var d := Vector2.from_angle(w.ang)
			var n := d.orthogonal() * float(w.wid)
			var center: Vector2 = w.pos + d * float(w.len) * p
			pts.append_array([center - n, center + n])
		"cone":
			pts.append_array([w.pos, w.pos + Vector2.from_angle(w.ang - w.half + 2.0 * w.half * p) * w.r])
		"circle":
			for i in 49:
				var a: float = TAU * i / 48.0
				pts.append(w.pos + Vector2(cos(a), sin(a) * g.combat.GROUND_Y) * float(w.r) * p)
	return pts

static func timer(g, w: Dictionary, c: Color) -> void:
	var pts := timer_points(g, w)
	if pts.size() > 1:
		stroke(g, pts, c, 2.0)

static func stroke(g, points: PackedVector2Array, c: Color, width: float, dim := false) -> void:
	# A fixed dark keyline separates the boundary from both bright VFX and dark terrain.
	g.wcv.draw_polyline(points, Color(0.025, 0.035, 0.055, 0.65 if dim else 0.96), width + (2.0 if dim else 4.0))
	g.wcv.draw_polyline(points, c, width)

static func outline(g, w: Dictionary) -> void:
	var u := urgency(w)
	var c := color().lerp(Color(0.94, 0.20, 0.24), u)
	c.a = Bal.v("render/warn_v2_idle_a", 0.94)
	var pts := polygon(g, w)
	pts.append(pts[0])
	if w.get("dim", false):
		# Not on the leader's collision path: keep the extent readable without urgency marks.
		g.wcv.draw_polyline(pts, Color(0.64, 0.12, 0.19, 0.4), 2.0)
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

	# Coral interior sweep is separated spatially from the stable danger boundary.
	timer(g, w, Color(0.88, 0.43, 0.38, 1.0))
