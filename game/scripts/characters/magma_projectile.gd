extends RefCounted
## Solid magma projectiles: stable crust, short directional flame, compressed landing.

const A = preload("res://scripts/art.gd")
const CRUST := Color(0.18, 0.09, 0.07)
const HOT := Color(1.0, 0.43, 0.08)

static func position_at(from: Vector2, to: Vector2, k: float, height: float) -> Vector2:
	# Finite velocity at both ends; one early crest followed by accelerating descent.
	return from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k) * (1.18 - 0.36 * k))

static func draw_fireball(o, p: Vector2, direction: Vector2, size: float, age: float) -> void:
	var dim: float = o.g.world.fx_dim
	o.cv.draw_circle(p, 8.0 * size, Color(HOT, dim * 0.15))
	if o.g.tex.get("proj_lavaball") != null and o.g.V6_FRAMES.has("proj_lavaball"):
		var spec: Array = o.g.V6_FRAMES.proj_lavaball
		o.draw_spr_rot("proj_lavaball", int(age * float(spec[1])) % int(spec[0]), p, direction.angle(), o.g.PX * size, Color(1, 1, 1, dim))
	else:
		o.cv.draw_circle(p, 5.0 * size, Color(HOT, dim))
		o.cv.draw_circle(p, 2.0 * size, Color(1.0, 0.85, 0.35, dim))

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

static func fireball_impact(o, p: Vector2, radius: float, size: float) -> void:
	o.fx({"kind": "fireball_burst", "pos": p + Vector2(0, -5), "r": clampf(radius * 0.3, 12.0, 24.0) * sqrt(size), "life": 0.24})

## S2 点燃弹命中爆燃（10-22 用户「命中几乎没表现」）：短促火焰炸开 + 向外火星 + 地面焦痕 / 余烬。纯画面，随机只用 g.vrng。
## 有 Codex 帧条 fx_eyja_ignite_hit（单子见 art/incoming/codex_order_eyja_handoff.md）时炸开用它，否则用旧 fx_eyja_ignite_boom 占位
static func ignite_hit(o, p: Vector2, radius: float, size: float) -> void:
	var r: float = clampf(radius * 0.5, 18.0, 40.0) * sqrt(size)
	var sparks := []
	for i in 10:
		var ang: float = -PI * 0.5 + (float(i) / 10.0 - 0.5) * PI * 1.7 + o.g.vrng.randf_range(-0.15, 0.15)
		sparks.append([Vector2.from_angle(ang), o.g.vrng.randf_range(0.7, 1.25)])
	o.fx({"kind": "ignite_scorch", "pos": p, "r": r, "life": 1.1, "floor": true})
	o.fx({"kind": "ignite_hit", "pos": p, "r": r, "life": 0.42, "sparks": sparks})

static func draw_ignite_hit(o, f: Dictionary) -> void:
	var age: float = float(f.max) - float(f.life)
	var k: float = clampf(age / float(f.max), 0.0, 1.0)
	var dim: float = o.g.world.fx_dim
	var r: float = float(f.r)
	var p: Vector2 = f.pos
	var flash: float = maxf(0.0, 1.0 - age / 0.07) * dim
	if flash > 0.0:
		o.cv.draw_circle(p + Vector2(0, -6), r * 0.55, Color(1.0, 0.9, 0.6, flash * 0.8))
	var tex := "fx_eyja_ignite_hit" if o._fx_tex("fx_eyja_ignite_hit") != null and o.g.V6_FRAMES.has("fx_eyja_ignite_hit") else "fx_eyja_ignite_boom"   # 懒加载：g.tex 只预载 json 引用过的贴图
	if o._fx_tex(tex) != null and o.g.V6_FRAMES.has(tex):
		var spec: Array = o.g.V6_FRAMES[tex]
		var fr: int = mini(int(age / float(f.max) * float(spec[0])), int(spec[0]) - 1)   # 整条压进 life 播完
		var fw: float = float(o.g.tex[tex].get_width()) / float(spec[0]) / A.hires_of(o.g.tex[tex])
		var own: bool = tex == "fx_eyja_ignite_hit"   # Codex 版原点 (32,44)（爆心偏下），占位条按中心
		o.draw_spr_rot(tex, fr, p + (Vector2(0, -4) if own else Vector2(0, -r * 0.35)), 0.0, r * 1.7 / fw, Color(1, 1, 1, dim * clampf((float(f.life)) / 0.12, 0.0, 1.0)), Vector2(32, 44) * A.hires_of(o.g.tex[tex]) if own else Vector2(-1, -1))
	else:
		var scale := Vector2.ONE * r / 10.0 * (0.7 + 0.5 * k)
		_poly(o, [Vector2(-10, 0), Vector2(-6, -5), Vector2(-3, -11), Vector2(0, -6), Vector2(3, -13), Vector2(6, -5), Vector2(10, 0), Vector2(4, 3), Vector2(-4, 3)], p, 0.0, scale, Color(HOT, (1.0 - k) * dim))
	for sp in f.sparks:
		var d: Vector2 = sp[0]
		var dist: float = r * 1.6 * float(sp[1]) * (1.0 - pow(1.0 - k, 2.0))
		var head: Vector2 = p + Vector2(d.x * dist, d.y * dist * 0.75 + 30.0 * k * k) + Vector2(0, -6)
		var tail: Vector2 = head - d * (5.0 + 8.0 * (1.0 - k))
		var a: float = (1.0 - k) * dim
		o.cv.draw_line(_snap(tail), _snap(head), Color(2.2, 0.8 + 0.6 * (1.0 - k), 0.2, a), 2.0)   # HDR 进辉光

static func draw_ignite_scorch(o, f: Dictionary) -> void:
	var age: float = float(f.max) - float(f.life)
	var dim: float = o.g.world.fx_dim
	var r: float = float(f.r) * (0.75 + 0.25 * minf(age / 0.12, 1.0))
	var fade: float = minf(1.0, float(f.life) / 0.35) * dim
	var scale := Vector2(r / 10.0, r / 20.0)
	_poly(o, [Vector2(-10, 0), Vector2(-7, -6), Vector2(-1, -8), Vector2(7, -6), Vector2(10, 0), Vector2(6, 6), Vector2(-2, 8), Vector2(-8, 5)], f.pos, 0.0, scale, Color(0.1, 0.05, 0.04, fade * 0.7))
	var heat: float = clampf(1.0 - age / 0.6, 0.0, 1.0)
	_poly(o, [Vector2(-6, 0), Vector2(-3, -4), Vector2(3, -4), Vector2(7, 0), Vector2(3, 4), Vector2(-3, 4)], f.pos, 0.0, scale, Color(0.75, 0.18, 0.04, fade * (0.25 + 0.55 * heat)))
	for i in 6:
		var e: Vector2 = Vector2.from_angle(float(i) * TAU / 6.0 + 0.4) * Vector2(r * 0.7, r * 0.35) * (0.5 + 0.5 * float(i % 2))
		var tw: float = 0.6 + 0.4 * sin(age * 18.0 + float(i) * 1.7)
		o.cv.draw_rect(Rect2(_snap(f.pos + e), Vector2(2, 2)), Color(1.0, 0.5 + 0.3 * heat, 0.12, fade * tw))

static func draw_fireball_impact(o, f: Dictionary) -> void:
	var k: float = clampf(1.0 - float(f.life) / float(f.max), 0.0, 1.0)
	var radius: float = float(f.r) * (0.65 + 0.35 * k)
	var scale := Vector2.ONE * radius / 10.0
	var fade: float = (1.0 - k) * o.g.world.fx_dim
	_poly(o, [Vector2(-10, 0), Vector2(-6, -4), Vector2(-4, -9), Vector2(-1, -5), Vector2(2, -12), Vector2(5, -5), Vector2(8, -2), Vector2(10, 0), Vector2(4, 3), Vector2(-4, 3)], f.pos, 0.0, scale, Color(HOT, fade * 0.8))
	_poly(o, [Vector2(-5, 0), Vector2(-2, -5), Vector2(0, -2), Vector2(2, -6), Vector2(5, 0), Vector2(0, 2)], f.pos, 0.0, scale, Color(1.0, 0.8, 0.3, fade))
	var flash: float = maxf(0.0, 1.0 - k / 0.24) * o.g.world.fx_dim
	_poly(o, [Vector2(-3, 0), Vector2(0, -3), Vector2(3, 0), Vector2(0, 2)], f.pos, 0.0, scale, Color(1.0, 0.95, 0.65, flash))

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
	var texture := "fx_eyja_lava_pool"
	if o.g.tex.get(texture) != null and o.g.V6_FRAMES.has(texture):
		var spec: Array = o.g.V6_FRAMES[texture]
		var frame: int = int((float(l.dur) - float(l.t)) * float(spec[1])) % int(spec[0])
		o.draw_spr_rot(texture, frame, l.pos, 0.0, minf(float(l.r) / 26.0, 3.2), Color(1, 1, 1, fade * 0.75))
		return
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
