extends RefCounted
## Candidate presentation: exact tells underneath coarse pixel material bodies. No simulation writes.
static var _circle_points := PackedVector2Array()
static var _circle_gy := -INF
const DARK := Color(0.025, 0.045, 0.07)
const DANGER := Color(0.82, 0.24, 0.43)

static func _circle_geometry(gy: float) -> PackedVector2Array:
	if _circle_gy != gy:
		_circle_points.resize(41)
		for i in 41:
			var a: float = TAU * i / 40.0
			_circle_points[i] = Vector2(cos(a), sin(a) * gy)
		_circle_gy = gy
	return _circle_points

static func draw(g, impacts := false) -> void:
	if not impacts:
		for w in g.warns:
			if w.act == "final_attack" and not w.done:
				_shape(g, w, 0.65 + 0.25 * clampf(w.t / w.dur, 0.0, 1.0), true)
		for h in g.bai.finals.hazards:
			if g.bosses.has(h.owner) and not g.bai.finals.cancelled(h):
				_shape(g, h, 0.95, false)
	else:
		for f in g.fx:
			if f.kind == "final_impact" and f.life > 0.0:
				_shape(g, f, clampf(float(f.life) / float(f.max) * 1.5, 0.0, 1.0), false)
	g.world.tb_flush()

static func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2(2.0, 2.0))

static func _ink(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Stable visual variation: no gameplay RNG and no new jitter pattern on every frame.
static func _noise(i: int, salt := 0) -> float:
	var k: int = (i * 73471 + salt * 19391 + 137) & 65535
	k = ((k ^ (k >> 7)) * 127) & 65535
	return float(k) / 65535.0

static func _dot(r, p: Vector2, c: Color, size := 2.0) -> void:
	var a := _snap(p)
	var s := maxf(2.0, snappedf(size, 2.0))
	r.tb_quad(a, a + Vector2(s, 0), a + Vector2(s, s), a + Vector2(0, s), c)

static func _strip(r, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var n := (b - a).normalized().orthogonal() * width * 0.5
	r.tb_quad(_snap(a - n), _snap(b - n), _snap(b + n), _snap(a + n), c)

static func _facet(r, pts: Array, c: Color) -> void:
	var snapped := PackedVector2Array()
	for p in pts: snapped.append(_snap(p))
	r.tb_poly(snapped, c)

static func _ring(r, p: Vector2, radius: float, gy: float, width: float, c: Color, a0 := 0.0, a1 := TAU, broken := false) -> void:
	var count: int = clampi(ceili(radius * (a1 - a0) / 10.0), 12, 150)
	for i in count:
		if broken and _noise(i, 4) < 0.22: continue
		var a: float = lerpf(a0, a1, float(i) / count)
		var b: float = lerpf(a0, a1, float(i + 1) / count)
		_strip(r, p + Vector2(cos(a), sin(a) * gy) * radius, p + Vector2(cos(b), sin(b) * gy) * radius, width, c)

static func _circle_fill(r, w: Dictionary, gy: float, c: Color) -> void:
	var inner: float = float(w.get("inner_r", 0.0))
	var points := _circle_geometry(gy)
	for i in 40:
		var va := points[i]
		var vb := points[i + 1]
		r.tb_quad(w.pos + va * inner, w.pos + va * w.r, w.pos + vb * w.r, w.pos + vb * inner, c)

static func _warning(g, w: Dictionary, alpha: float) -> void:
	var r = g.world
	var p: Vector2 = w.pos
	var progress: float = clampf(float(w.get("t", 0.0)) / maxf(0.01, float(w.get("dur", 1.0))), 0.0, 1.0)
	var edge := _ink(DANGER, alpha)
	var fill := Color(0.24, 0.035, 0.085, 0.09 + progress * 0.06)
	var gy: float = g.combat.GROUND_Y
	match str(w.shape):
		"circle":
			_circle_fill(r, w, gy, fill)
			_ring(r, p, w.r, gy, 5.0, _ink(DARK, 0.8))
			_ring(r, p, w.r, gy, 2.0, edge)
			var inner: float = float(w.get("inner_r", 0.0))
			if inner > 0.0:
				_ring(r, p, inner, gy, 5.0, _ink(DARK, 0.9))
				_ring(r, p, inner, gy, 2.0, edge)
			# A short filling arc encodes time, not a solid white spell body.
			_ring(r, p, w.r, gy, 3.0, _ink(Color(1.0, 0.48, 0.57), alpha), -PI * 0.5, -PI * 0.5 + maxf(0.02, progress) * TAU)
		"line":
			var d := Vector2.from_angle(w.ang)
			var n := d.orthogonal()
			var end: Vector2 = p + d * w.len
			r.tb_quad(p - n * w.wid, end - n * w.wid, end + n * w.wid, p + n * w.wid, fill)
			for side in [-1.0, 1.0]:
				_strip(r, p + n * w.wid * side, end + n * w.wid * side, 5.0, _ink(DARK, 0.85))
				_strip(r, p + n * w.wid * side, end + n * w.wid * side, 2.0, edge)
			_strip(r, p - n * w.wid, p + n * w.wid, 2.0, edge)
			_strip(r, end - n * w.wid, end + n * w.wid, 2.0, edge)
			var lead: Vector2 = p + d * w.len * progress
			_strip(r, lead - d * 12.0 - n * minf(w.wid * 0.35, 10.0), lead, 2.0, edge)
			_strip(r, lead - d * 12.0 + n * minf(w.wid * 0.35, 10.0), lead, 2.0, edge)
			if w.get("skin", "") == "tide":
				var travel: Vector2 = w.velocity * w.life
				r.tb_quad(p, end, end + travel, p + travel, Color(0.25, 0.06, 0.1, 0.045))
				_strip(r, p, p + travel, 2.0, _ink(DANGER, 0.55))
				_strip(r, end, end + travel, 2.0, _ink(DANGER, 0.55))
				var v: Vector2 = travel.normalized()
				for j in 3:
					var at: Vector2 = p.lerp(end, 0.5) + travel * (j + 0.5) / 3.0
					_strip(r, at - v * 12 + d * 8, at, 2.0, edge)
					_strip(r, at - v * 12 - d * 8, at, 2.0, edge)
		"cone":
			var pts := PackedVector2Array([p])
			for i in 25: pts.append(p + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / 24.0) * w.r)
			r.tb_poly(pts, fill)
			_ring(r, p, w.r, 1.0, 2.0, edge, w.ang - w.half, w.ang + w.half)
			for side in [-1.0, 1.0]: _strip(r, p, p + Vector2.from_angle(w.ang + w.half * side) * w.r, 2.0, edge)

## A subdued material footprint keeps the complete damaging body legible underneath its bright details.
static func _footprint(r, w: Dictionary, gy: float, alpha: float) -> void:
	var skin: String = str(w.get("skin", ""))
	var tint := Color(0.22, 0.49, 0.57) if skin != "phantom" else Color(0.53, 0.28, 0.65)
	match str(w.shape):
		"line":
			var d := Vector2.from_angle(w.ang)
			var n := d.orthogonal()
			var end: Vector2 = w.pos + d * w.len
			var density: float = 0.055 if skin == "tentacle" else 0.22
			r.tb_quad(w.pos - n * w.wid, end - n * w.wid, end + n * w.wid, w.pos + n * w.wid, _ink(tint, alpha * density))
			for side in [-1.0, 1.0]:
				_strip(r, w.pos + n * w.wid * side, end + n * w.wid * side, 2, _ink(tint, alpha * 0.5))
		"circle":
			if skin == "choir":
				_circle_fill(r, w, gy, _ink(tint, alpha * 0.25))
				_ring(r, w.pos, w.r, gy, 2, _ink(tint, alpha * 0.65))
		"cone":
			var pts := PackedVector2Array([w.pos])
			for i in 25: pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / 24.0) * w.r)
			r.tb_poly(pts, _ink(tint, alpha * 0.2))
			_ring(r, w.pos, w.r, 1.0, 3, _ink(tint, alpha * 0.55), w.ang - w.half, w.ang + w.half)

static func _shape(g, w: Dictionary, alpha: float, warning: bool) -> void:
	if warning:
		_warning(g, w, alpha)
		return
	var r = g.world
	var skin: String = str(w.get("skin", ""))
	var age: float = float(w.get("age", float(w.get("max", 0.0)) - float(w.get("life", 0.0))))
	var p: Vector2 = w.pos
	var gy: float = g.combat.GROUND_Y
	_footprint(r, w, gy, alpha)
	match str(w.shape):
		"circle":
			if skin == "bubble": _bubble(r, p, float(w.r), gy, age, alpha, float(w.get("ang", 0.0)))
			elif skin == "choir": _choir_orb(r, p, float(w.r), float(w.get("ang", 0.0)), age, alpha)
			else: _surge(r, w, gy, age, alpha)
		"line":
			match skin:
				"phantom", "choir": _beam(r, w, age, alpha, skin == "phantom")
				"ice": _ice(r, w, age, alpha)
				"crescent": _blade(r, w, age, alpha)
				"step", "spear": _spear(r, w, age, alpha)
				"tentacle": _tentacle(r, p, float(w.ang), float(w.len), float(w.wid), age, alpha)
				"tide": _tide(r, w, age, alpha)
		"cone":
			for k in 3:
				var a: float = w.ang + (k - 1) * w.half * 0.62
				_tentacle(r, p, a, w.r * (1.0 - 0.08 * absf(k - 1)), 22.0, age + k * 0.07, alpha)

static func _bubble(r, p: Vector2, radius: float, gy: float, age: float, alpha: float, phase: float) -> void:
	var w := {"pos":p, "r":radius, "inner_r":0.0}
	_circle_fill(r, w, gy, Color(0.035, 0.015, 0.095, alpha * 0.72))
	_ring(r, p, radius, gy, 5, Color(0.19, 0.09, 0.3, alpha))
	_ring(r, p, radius * 0.92, gy, 3, Color(0.66, 0.32, 0.74, alpha), 0, TAU, true)
	_ring(r, p, radius * 0.83, gy, 3, Color(0.94, 0.67, 1.08, alpha), -2.8 + phase * 0.4 + sin(age * 2.0) * 0.2, -1.6 + phase * 0.4)
	_ring(r, p, radius * 0.6, gy, 2, Color(0.28, 0.12, 0.43, alpha), age * 1.5, age * 1.5 + PI)
	_facet(r, [p + Vector2(-radius * 0.55, 0), p + Vector2(-radius * 0.2, -radius * gy * 0.6), p + Vector2(radius * 0.3, -radius * gy * 0.3), p + Vector2(radius * 0.15, radius * gy * 0.5)], Color(0.13, 0.045, 0.22, alpha))
	for k in 7:
		var a: float = k * 2.4 + age * 0.55
		var q := p + Vector2(cos(a), sin(a) * gy) * radius * (0.55 + _noise(k) * 0.32)
		_dot(r, q, Color(0.54, 0.31, 0.66, alpha * 0.7))

static func _beam(r, w: Dictionary, age: float, alpha: float, phantom: bool) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var p: Vector2 = w.pos
	var body := Color(0.31, 0.12, 0.48, alpha) if phantom else Color(0.13, 0.48, 0.43, alpha)
	var bright := Color(0.84, 0.46, 1.0, alpha) if phantom else Color(0.48, 0.84, 0.69, alpha)
	var pearl := Color(1.18, 0.94, 1.2, alpha) if phantom else Color(1.14, 1.12, 0.87, alpha)
	var flash: float = maxf(0.0, 1.0 - age / 0.13)
	var count: int = ceili(w.len / 10.0)
	for i in count:
		var u: float = float(i) / count
		var v: float = float(i + 1) / count
		var wobble: float = sin(u * 24.0 - age * 28.0) * 2.0
		var a: Vector2 = p + d * w.len * u + n * wobble
		var b: Vector2 = p + d * w.len * v + n * sin(v * 24.0 - age * 28.0) * 2.0
		var width: float = w.wid * (0.75 + 0.45 * _noise(i, 2))
		_strip(r, a, b, width + 8.0, _ink(DARK, alpha * 0.9))
		_strip(r, a, b, width, body)
		_strip(r, a - n * width * 0.15, b - n * width * 0.15, width * 0.35, bright)
		if _noise(i, 11) > 0.32 or flash > 0.5:
			_strip(r, a, b, 2.0 + 2.0 * flash, pearl)
		if i % 3 == 0:
			var side: float = -1.0 if _noise(i, 8) < 0.5 else 1.0
			_dot(r, a + n * side * width * (0.6 + age * 3), _ink(bright, alpha * 0.65), 2.0)
	# Emission organ: split violet membrane or ivory choir fin, not a floating icon.
	for side in [-1.0, 1.0]:
		_facet(r, [p - d * 15, p - d * 8 + n * 22 * side, p + d * 21 + n * 10 * side, p + d * 8], body)
		_strip(r, p - d * 8 + n * 20 * side, p + d * 16 + n * 8 * side, 3, bright)
	_dot(r, p, pearl, 4)

static func _ice(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var count: int = maxi(4, ceili(w.len / 34.0))
	for i in count:
		var u: float = (i + 0.3 + _noise(i) * 0.35) / count
		var p: Vector2 = w.pos + d * w.len * u
		var h: float = w.wid * (0.4 + _noise(i, 1) * 0.65)
		var s: float = -1.0 if i % 2 else 1.0
		var tip: Vector2 = p + d * (12 + _noise(i, 3) * 16) + n * h * s
		_strip(r, p - d * 18, p + d * 20, 5, Color(0.035, 0.1, 0.16, alpha))
		_facet(r, [p - d * 10 - n * h * 0.3, tip, p + d * 8 + n * h * 0.15], Color(0.14, 0.32, 0.43, alpha))
		_facet(r, [p - d * 6, tip, p + n * h * 0.2], Color(0.42, 0.68, 0.78, alpha))
		_strip(r, p - d * 5, tip, 2, Color(0.83, 1.0, 1.12, alpha * (0.65 if age > 0.18 else 1.0)))

static func _blade(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var mid: Vector2 = w.pos + d * w.len * 0.5
	for i in 30:
		var u: float = float(i) / 30 * 2 - 1
		var v: float = float(i + 1) / 30 * 2 - 1
		var a: Vector2 = mid + d * u * w.len * 0.5 + n * (1 - u * u) * 12
		var b: Vector2 = mid + d * v * w.len * 0.5 + n * (1 - v * v) * 12
		var thick: float = 3 + (1 - absf(u)) * 11
		_strip(r, a - n * 4, b - n * 4, thick + 5, Color(0.04, 0.13, 0.2, alpha))
		_strip(r, a, b, thick, Color(0.21, 0.44, 0.56, alpha))
		_strip(r, a + n * 3, b + n * 3, 3, Color(0.75, 0.97, 1.12, alpha))
		if i % 4 == 1: _dot(r, a - n * (8 + fmod(age * 48 + i, 14)), Color(0.28, 0.52, 0.64, alpha * 0.7), 2)

static func _spear(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var n := d.orthogonal()
	var end: Vector2 = w.pos + d * w.len
	_strip(r, w.pos, end - d * 22, 6, Color(0.06, 0.15, 0.22, alpha))
	_strip(r, w.pos, end - d * 22, 2, Color(0.37, 0.58, 0.69, alpha))
	_facet(r, [end - d * 52 - n * 11, end, end - d * 52 + n * 11, end - d * 36], Color(0.3, 0.52, 0.64, alpha))
	_strip(r, end - d * 45 - n * 7, end, 2, Color(0.9, 1.08, 1.15, alpha))

static func _tentacle(r, p: Vector2, angle: float, length: float, width: float, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(angle)
	var n := d.orthogonal()
	var root_points: Array = []
	for j in 9:
		var a: float = PI * 0.5 + PI * j / 8.0
		root_points.append(p + d * cos(a) * width * 0.5 + n * sin(a) * width * 0.8)
	_facet(r, root_points, Color(0.065, 0.24, 0.28, alpha))
	var count: int = ceili(length / 9.0)
	for i in count:
		var u: float = float(i) / count
		var v: float = float(i + 1) / count
		var a := p + d * length * u + n * (sin(u * 8 + age * 6) * 0.18 + sin(u * 19) * 0.06) * width
		var b := p + d * length * v + n * (sin(v * 8 + age * 6) * 0.18 + sin(v * 19) * 0.06) * width
		var thick: float = width * (1.6 - pow(u, 0.65) * 1.45) * (0.87 + _noise(i / 3, 9) * 0.2)
		_strip(r, a, b, thick + 4, Color(0.015, 0.07, 0.105, alpha))
		_strip(r, a, b, thick, Color(0.065, 0.24, 0.28, alpha))
		_strip(r, a - n * thick * 0.22, b - n * thick * 0.22, maxf(2.0, thick * 0.26), Color(0.25, 0.58, 0.57, alpha))
		if i % 3 == 1 and u < 0.8:
			var at := a + n * thick * 0.22
			_dot(r, at, Color(0.025, 0.105, 0.16, alpha), 5)
			_dot(r, at - n * 2, Color(0.55, 0.72, 0.63, alpha * 0.85), 2)
		if _noise(i, 5) > 0.72:
			_facet(r, [a - n * thick * 0.36, a - d * 8 - n * thick * 0.7, b - n * thick * 0.36], Color(0.23, 0.52, 0.49, alpha))

static func _choir_orb(r, p: Vector2, radius: float, angle: float, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(angle)
	var n := d.orthogonal()
	# A dense wet body carries asymmetric ivory fins, with a ragged trailing skirt.
	_facet(r, [p-d*radius*.85, p-d*radius*.35-n*radius*.5, p+d*radius*.78-n*radius*.12, p+d*radius*.9, p+d*radius*.25+n*radius*.4, p-d*radius*.65+n*radius*.26], Color(0.08,0.32,0.34,alpha))
	for side in [-1.0, 1.0]:
		var extent: float = 0.8 if side < 0 else 0.55
		var lean: float = sin(age * 5) * 2
		_facet(r, [p-d*radius*.7+n*side*radius*.12, p-d*radius*.35+n*side*radius*extent, p+d*radius*.58+n*lean, p+d*radius*.1+n*side*radius*.1], Color(0.37,0.62,0.55,alpha))
		_facet(r, [p-d*radius*.35+n*side*radius*extent, p+d*radius*.58+n*lean, p-d*radius*.05+n*side*radius*.24], Color(0.72,0.81,0.64,alpha))
	for k in 4:
		var q: Vector2 = p-d*radius*(.6+_noise(k)*.25)+n*(k-1.5)*radius*.16
		_strip(r,q,q-d*(6+_noise(k,2)*7),2,Color(.19,.51,.48,alpha*.65))
	_strip(r,p-d*radius*.15,p+d*radius*.65,2,Color(1.05,1.1,.86,alpha))

static func _tide(r, w: Dictionary, age: float, alpha: float) -> void:
	var d := Vector2.from_angle(w.ang)
	var travel: Vector2 = w.get("velocity", d.orthogonal()).normalized()
	var count: int = ceili(w.len / 10.0)
	for i in count:
		var u: float = float(i) / count
		var v: float = float(i + 1) / count
		var height: float = w.wid * (0.45 + _noise(i / 2, 4) * 0.4)
		var a: Vector2 = w.pos + d * w.len * u
		var b: Vector2 = w.pos + d * w.len * v
		_strip(r, a - travel * height * 0.4, b - travel * height * 0.4, w.wid * 1.1, Color(0.035, 0.19, 0.27, alpha * 0.9))
		_strip(r, a, b, height, Color(0.08, 0.43, 0.48, alpha))
		_strip(r, a + travel * height * 0.35, b + travel * height * 0.35, 4, Color(0.43, 0.76, 0.73, alpha))
		if _noise(i, 12) > 0.4:
			_dot(r, a + travel * height * 0.45, Color(0.93, 1.02, 0.86, alpha), 2)
		if _noise(i, 17) > 0.55:
			_dot(r, a - travel * (height + fmod(age * 30 + i * 4, 15)), Color(0.18, 0.48, 0.53, alpha * 0.65), 3)

static func _surge(r, w: Dictionary, gy: float, age: float, alpha: float) -> void:
	var inner: float = float(w.get("inner_r", 0.0))
	_circle_fill(r, w, gy, Color(0.025, 0.14, 0.21, alpha * 0.15))
	for radius in [float(w.r), inner]:
		if radius <= 0: continue
		# Keep the inner crest wholly on the damaging side of the safe boundary.
		var crest: float = radius + 10.0 if radius == inner else radius - 8.0
		_ring(r, w.pos, crest, gy, 9, Color(0.05, 0.29, 0.37, alpha))
		_ring(r, w.pos, crest - 1, gy, 3, Color(0.3, 0.67, 0.68, alpha), 0, TAU, true)
		_ring(r, w.pos, crest, gy, 2, Color(0.71, 0.88, 0.78, alpha), age * 2, age * 2 + PI * 0.55, true)
