extends RefCounted
## Solid magma projectiles: stable crust, short directional flame, compressed landing.

const CRUST := Color(0.18, 0.09, 0.07)
const HOT := Color(1.0, 0.43, 0.08)

static func position_at(from: Vector2, to: Vector2, k: float, height: float) -> Vector2:
	# Finite velocity at both ends; one early crest followed by accelerating descent.
	return from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k) * (1.18 - 0.36 * k))

static func draw(o, p: Vector2, direction: Vector2, size: float, age: float, spin := 1.0) -> void:
	var dim: float = o.g.world.fx_dim
	var scale := Vector2.ONE * size
	var d: Vector2 = direction.normalized() if direction.length_squared() > 0.01 else Vector2.RIGHT
	var tail: Vector2 = p - d * (14.0 + 2.0 * sin(age * 12.0)) * size
	var side: Vector2 = d.orthogonal() * 5.0 * size
	o.cv.draw_colored_polygon(PackedVector2Array([_snap(p + side), _snap(tail), _snap(p - side)]), Color(0.7, 0.15, 0.03, dim * 0.7))
	o.cv.draw_line(_snap(p - d * 4.0 * size), _snap(tail + d * 5.0 * size), Color(HOT, dim * 0.8), 2.0)
	var angle: float = age * 1.4 * spin
	_poly(o, [Vector2(-8, -6), Vector2(-2, -10), Vector2(6, -8), Vector2(10, -2), Vector2(8, 6), Vector2(2, 10), Vector2(-6, 8), Vector2(-10, 2)], p, angle, scale, Color(CRUST, dim))
	_poly(o, [Vector2(-6, -4), Vector2(0, -8), Vector2(6, -4), Vector2(4, 4), Vector2(-2, 6), Vector2(-6, 2)], p, angle, scale, Color(0.66, 0.17, 0.04, dim))
	_poly(o, [Vector2(-2, -6), Vector2(4, -4), Vector2(2, 2), Vector2(-4, 4), Vector2(-4, 0)], p, angle, scale, Color(HOT, dim))
	_poly(o, [Vector2(-8, -4), Vector2(-2, -8), Vector2(-2, -2), Vector2(-6, 2)], p, angle, scale, Color(0.31, 0.16, 0.1, dim))
	_poly(o, [Vector2(4, 0), Vector2(8, -2), Vector2(6, 6), Vector2(0, 8), Vector2(0, 4)], p, angle, scale, Color(0.26, 0.09, 0.05, dim))
	var xf := Transform2D(angle, scale, 0.0, p)
	for crack in [[Vector2(-2, -6), Vector2(0, -2), Vector2(-2, 2)], [Vector2(0, -2), Vector2(4, 0), Vector2(4, 4)]]:
		for i in 2:
			o.cv.draw_line(_snap(xf * crack[i]), _snap(xf * crack[i + 1]), Color(1.0, 0.72, 0.28, dim), 2.0)

static func impact(o, p: Vector2, radius: float, size: float) -> void:
	o.fx({"kind": "lava_spot", "mass": true, "pos": p, "r": clampf(radius * 0.42, 14.0, 32.0) * sqrt(size), "life": 0.4, "floor": true})

static func draw_impact(o, f: Dictionary) -> void:
	var age: float = float(f.max) - float(f.life)
	var spread: float = 0.6 + 0.4 * minf(age / 0.1, 1.0)
	var radius: float = float(f.r) * spread
	var scale := Vector2(radius / 10.0, radius / 23.0)
	var fade: float = minf(1.0, float(f.life) / 0.2) * o.g.world.fx_dim
	_poly(o, [Vector2(-10, 0), Vector2(-8, -6), Vector2(-2, -8), Vector2(6, -6), Vector2(10, 0), Vector2(6, 6), Vector2(-2, 8), Vector2(-8, 4)], f.pos, 0.0, scale, Color(CRUST, fade * 0.85))
	_poly(o, [Vector2(-8, 0), Vector2(-4, -4), Vector2(2, -6), Vector2(8, -2), Vector2(6, 4), Vector2(0, 6), Vector2(-6, 4)], f.pos, 0.0, scale, Color(0.75, 0.2, 0.04, fade * 0.8))
	var heat: float = clampf(1.0 - age / 0.3, 0.0, 1.0) * o.g.world.fx_dim
	o.cv.draw_line(_snap(f.pos + Vector2(-radius * 0.55, 0)), _snap(f.pos + Vector2(radius * 0.45, -2)), Color(HOT, heat), 2.0)
	var flash: float = maxf(0.0, 1.0 - age / 0.08) * o.g.world.fx_dim
	_poly(o, [Vector2(-4, 0), Vector2(-2, -2), Vector2(4, -2), Vector2(6, 0), Vector2(2, 2)], f.pos, 0.0, scale, Color(1.0, 0.8, 0.4, flash * 0.7))
	for i in 2:
		var d := Vector2.from_angle(float(i) * PI + 0.3)
		var p: Vector2 = _snap(f.pos + d * Vector2(radius * 1.15, radius * 0.5) - Vector2(0, sin(minf(1.0, age / 0.25) * PI) * 4.0))
		o.cv.draw_rect(Rect2(p, Vector2(4, 2)), Color(0.4, 0.14, 0.05, fade))

static func draw_pool(o, l: Dictionary) -> void:
	var fade: float = minf(1.0, float(l.t) / 0.4) * minf(1.0, (float(l.dur) - float(l.t)) / 0.12) * o.g.world.fx_dim
	var scale := Vector2(float(l.r) / 10.0, float(l.r) / 24.0)
	_poly(o, [Vector2(-10, 0), Vector2(-8, -6), Vector2(-2, -8), Vector2(6, -6), Vector2(10, 0), Vector2(6, 6), Vector2(-2, 8), Vector2(-8, 4)], l.pos, 0.0, scale, Color(CRUST, fade * 0.7))
	_poly(o, [Vector2(-8, 0), Vector2(-4, -4), Vector2(2, -6), Vector2(8, -2), Vector2(6, 4), Vector2(0, 6), Vector2(-6, 4)], l.pos, 0.0, scale, Color(0.7, 0.16, 0.04, fade * 0.65))
	var pulse: float = 0.45 + 0.05 * sin((float(l.dur) - float(l.t)) * 3.0)
	_poly(o, [Vector2(-6, 0), Vector2(-2, -2), Vector2(4, -4), Vector2(6, 0), Vector2(2, 2), Vector2(-4, 2)], l.pos, 0.0, scale, Color(HOT, fade * pulse))
	for crack in [[Vector2(-5, 0), Vector2(-2, -2)], [Vector2(0, 0), Vector2(3, 2)], [Vector2(4, -2), Vector2(6, 0)]]:
		o.cv.draw_line(_snap(l.pos + crack[0] * scale), _snap(l.pos + crack[1] * scale), Color(HOT, fade * 0.6), 2.0)

static func _poly(o, points: Array, p: Vector2, angle: float, scale: Vector2, color: Color) -> void:
	var xf := Transform2D(angle, scale, 0.0, p)
	var shape := PackedVector2Array()
	for point in points:
		shape.append(_snap(xf * point))
	o.cv.draw_colored_polygon(shape, color)

static func _snap(p: Vector2) -> Vector2:
	return (p / 2.0).round() * 2.0
