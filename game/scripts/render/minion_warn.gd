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
	return Color(Bal.v("render/warn_v2_r", 0.66), Bal.v("render/warn_v2_g", 0.62), Bal.v("render/warn_v2_b", 0.78))

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
	c.a = clampf(Bal.v("render/warn_v2_fill", 0.045), 0.0, 0.15)
	g.wcv.draw_colored_polygon(polygon(g, w), c)

static func outline(g, w: Dictionary) -> void:
	var u := urgency(w)
	var c := color().lerp(Color(0.92, 0.9, 0.98), u)
	# One short pulse inside the last 0.3 seconds, with no early pulsing.
	var flash: float = sin(clampf(u / 0.28, 0.0, 1.0) * PI) if u < 0.28 else 0.0
	c.a = lerpf(Bal.v("render/warn_v2_idle_a", 0.42), 0.95, maxf(u, flash))
	if w.get("dim", false):
		c.a *= Bal.v("fx/tell_dim_alpha", 0.2)
	var pts := polygon(g, w)
	pts.append(pts[0])
	# PX=2: one art pixel normally, two during the final signal.
	g.wcv.draw_polyline(pts, c, 4.0 if u > 0.0 else 2.0)
	if str(w.shape) == "line" and str(w.get("act", "")) in ["stab", "dash"]:
		var d := Vector2.from_angle(w.ang)
		var n := d.orthogonal()
		var tip: Vector2 = w.pos + d * float(w.len)
		var size: float = minf(float(w.wid), 10.0)
		g.wcv.draw_polyline(PackedVector2Array([tip - d * size + n * size, tip, tip - d * size - n * size]), c, 2.0)
