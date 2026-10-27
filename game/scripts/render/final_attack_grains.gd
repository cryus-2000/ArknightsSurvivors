extends RefCounted
## Final Boss materials use the existing 2px CPU pool and shared Boss emission budget.
## Attack dictionaries stay read-only: particles cannot alter the warning, hit or motion geometry.
const Beam = preload("res://scripts/render/boss_beam.gd")
const STEP := 0.05
const GAP_MARGIN := 24.0 # Longer than the existing water template's lifetime drift.

static func _pool(g):
	if Cfg.quality == "low":
		return null
	return Beam.grains(g)

static func _color(w: Dictionary) -> Color:
	var c: Color = w.col
	match str(w.get("skin", "")):
		"ice", "spear", "crescent", "step":
			return Color(0.48, 0.81, 1.0, 0.9)
		"phantom", "bubble":
			return c.lerp(Color(0.66, 0.49, 0.93, 0.9), 0.35)
		"choir":
			return Color(0.46, 0.92, 0.84, 0.9)
		"tide", "tentacle":
			return Color(0.34, 0.72, 0.87, 0.9)
	return c

static func _material(skin: String) -> String:
	match skin:
		"ice", "spear", "crescent", "step": return "blade"
		"phantom", "choir": return "bfx_flash"
		"tentacle": return "fluid"
	return "water"

static func burst(g, w: Dictionary) -> void:
	var pool = _pool(g)
	if pool == null:
		return
	var skin: String = str(w.get("skin", ""))
	if skin == "tide" and w.shape == "line" and float(w.len) <= GAP_MARGIN * 2.0:
		return
	var wanted := 36 if w.shape == "line" else 20
	if skin == "bubble": wanted = 8
	elif skin == "step": wanted = 14
	elif w.shape == "circle" and float(w.r) > 100.0: wanted = 48
	var count: int = Beam.take(g, wanted)
	var d := Vector2.from_angle(float(w.get("ang", 0.0)))
	var n := d.orthogonal()
	var color := _color(w)
	var material := _material(skin)
	for i in count:
		var p: Vector2 = w.pos
		var direction := Vector2.UP
		match str(w.shape):
			"line":
				# Jitter within strata: even coverage without a dotted grid across the beam.
				var u: float = (float(i) + g.vrng.randf()) / maxf(1.0, count)
				var side: float = -1.0 if i % 2 == 0 else 1.0
				var width: float = float(w.wid)
				var along: float = lerpf(GAP_MARGIN, float(w.len) - GAP_MARGIN, u) if skin == "tide" else u * float(w.len)
				p += d * along + n * side * width * g.vrng.randf_range(0.45, 0.9)
				direction = (n * side + d * g.vrng.randf_range(-0.25, 0.45)).normalized()
				if skin in ["ice", "spear"]:
					# Broken crystal shards kick upward/outward instead of a radial firework.
					direction = (Vector2.UP * 1.2 + n * side * 0.55 + d * 0.3).normalized()
				elif skin == "tentacle":
					p += n * sin(u * 11.0) * width * 0.2
					direction = (n * side * 0.5 + Vector2.DOWN).normalized()
				elif skin == "tide":
					direction = Vector2(w.get("velocity", n)).normalized()
				elif skin == "step":
					direction = -d.rotated(g.vrng.randf_range(-0.3, 0.3))
			"circle":
				var angle: float = g.vrng.randf_range(0.0, TAU)
				var radial := Vector2.from_angle(angle)
				var gy: float = g.combat.GROUND_Y
				var inner: float = float(w.get("inner_r", 0.0))
				var outer: float = float(w.r)
				var lower: float = minf(outer, maxf(outer * 0.85, inner + 4.0))
				p += Vector2(radial.x, radial.y * gy) * g.vrng.randf_range(lower, outer)
				direction = Vector2(radial.x, radial.y / gy).normalized()
				if inner > 0.0:
					# No gravity on an annulus: droplets must not fall back into its safe center.
					material = "bfx_flash"
			"cone":
				var angle: float = float(w.ang) + g.vrng.randf_range(-float(w.half), float(w.half))
				direction = Vector2.from_angle(angle)
				p += direction * float(w.r) * g.vrng.randf_range(0.78, 0.98)
		pool.push(material, p, direction, color)

static func trail(g, h: Dictionary, dt: float) -> void:
	var pool = _pool(g)
	if pool == null:
		return
	var age: float = float(h.age)
	var ticks: int = mini(3, floori(age / STEP) - floori(maxf(0.0, age - dt) / STEP))
	if ticks <= 0:
		return
	var skin: String = str(h.get("skin", ""))
	if skin == "tide" and h.shape == "line" and float(h.len) <= GAP_MARGIN * 2.0:
		return
	var count: int = Beam.take(g, ticks * (7 if skin == "tide" else 3))
	var velocity: Vector2 = h.velocity
	var heading := velocity.normalized()
	var across := heading.orthogonal()
	var axis := Vector2.from_angle(float(h.get("ang", 0.0)))
	var material := _material(skin)
	var color := _color(h)
	for i in count:
		var p: Vector2 = h.pos
		var direction := -heading
		if h.shape == "line":
			var u: float = g.vrng.randf()
			var along: float = lerpf(GAP_MARGIN, float(h.len) - GAP_MARGIN, u) if skin == "tide" else u * float(h.len)
			p += axis * along
			p -= heading * g.vrng.randf_range(1.0, 7.0)
			if skin == "crescent":
				direction = (-heading + across * (u - 0.5)).normalized()
			elif skin == "tide":
				# Foam is shed behind the crest, so the leading damage edge stays readable.
				direction = (-heading * 0.7 + Vector2.UP * 0.6).normalized()
		else:
			var radius: float = float(h.get("r", 20.0))
			var side: float = g.vrng.randf_range(-0.75, 0.75)
			p -= heading * radius * 0.7
			p += across * radius * side
			direction = (-heading + across * side * 0.5).normalized()
		pool.push(material, p, direction, color)

static func finish(g, h: Dictionary) -> void:
	# A travelling bubble breaks into a few droplets rather than leaving a hard disappearing disk.
	if str(h.get("skin", "")) == "bubble":
		burst(g, h)
