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

const Materials = preload("res://scripts/render/final_boss_materials.gd")
const Bal = preload("res://scripts/core/balance.gd")
## Knight ice bodies use the docs/136 "ice" material: chips leave the advancing front, land on the ground line and cool.
## Low quality keeps them at the template's low_k share instead of switching them off; every hazard outline is drawn separately.
const KNIGHT_ICE := ["ice", "ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "spear", "crescent"]
const ICE_TINT := Color(1.0, 1.0, 1.0, 0.95)
static var ice_off := false # --iceab same-run perf rotation only

static func knight_ice(w: Dictionary) -> bool:
	var o = w.get("owner")
	return o is Dictionary and o.get("type", "") == "knight_boss" and str(w.get("skin", "")) in KNIGHT_ICE

static func _ice_pool(g):
	if ice_off or Bal.v("render/knight_ice_grains", 1.0) <= 0.0:
		return null
	return Beam.grains(g)

static func _chip(g, pool, p: Vector2, direction: Vector2, delay := 0.0, drop := 4.0, mist := false) -> void:
	# Shards land on a ground line a little below the emission point; every few emissions are low cold mist instead.
	if mist:
		pool.push("frost_mist", p + Vector2(0, -4), Vector2.UP, ICE_TINT, delay)
		return
	pool.push("ice", p, direction, ICE_TINT, delay, p.y + g.vrng.randf_range(1.0, drop))

static func _ring_dir(g, w: Dictionary) -> Vector2:
	# Elliptic ground ring direction outside a safe gap; ZERO when the sample lands inside the gap.
	var gy: float = g.combat.GROUND_Y
	var angle: float = g.vrng.randf_range(0.0, TAU)
	var v := Vector2(cos(angle), sin(angle) * gy)
	if w.has("gap_ang") and absf(angle_difference(v.angle(), float(w.gap_ang))) < float(w.gap_half) + 0.08:
		return Vector2.ZERO
	return v

## Front-edge chips while a Knight ice body advances (20Hz ticks, shared Boss emission budget).
static func _ice_trail(g, pool, h: Dictionary, ticks: int) -> void:
	var skin: String = str(h.get("skin", ""))
	var per: int = int({"ice_wave": 6, "crescent": 4, "ice_wall": 5, "ice_thrust": 3, "ice_lance": 1}.get(skin, 2))
	var count: int = Beam.take(g, ticks * per)
	var axis := Vector2.from_angle(float(h.get("ang", 0.0)))
	var velocity: Vector2 = h.get("velocity", Vector2.ZERO)
	var heading: Vector2 = velocity.normalized() if velocity.length_squared() > 1.0 else axis
	var across := heading.orthogonal()
	for i in count:
		match skin:
			"ice_wave":
				# The freezing front: chips pop off the current wave radius, one ring cell at a time.
				var v := _ring_dir(g, h)
				if v == Vector2.ZERO: continue
				var at: Vector2 = h.pos + v * (float(h.r) - g.vrng.randf_range(0.0, 10.0))
				_chip(g, pool, at, (v.normalized() * 0.55 + Vector2.UP).normalized(), 0.0, 4.0, i % 3 == 2)
			"crescent":
				var radial := Vector2.from_angle(float(h.ang) + g.vrng.randf_range(-float(h.half), float(h.half)))
				var at: Vector2 = h.pos - axis * float(h.get("arc_back", 0.0)) + radial * float(h.r)
				_chip(g, pool, at, (radial * 0.5 + Vector2.UP * 0.9 - heading * 0.3).normalized(), 0.0, 8.0, i % 3 == 2)
			"ice_wall":
				var at: Vector2 = h.pos + axis * g.vrng.randf_range(0.0, float(h.len)) + heading * float(h.wid)
				_chip(g, pool, at, (heading * 0.6 + Vector2.UP).normalized(), 0.0, 4.0, i % 3 == 2)
			"ice_thrust", "spear":
				var at: Vector2 = h.pos + axis * float(h.len) + across * g.vrng.randf_range(-1.0, 1.0) * float(h.get("wid", 12.0)) * 0.6
				_chip(g, pool, at, (axis * 0.4 + Vector2.UP + across * g.vrng.randf_range(-0.6, 0.6)).normalized(), 0.0, 4.0, i % 3 == 2)
			"ice_lance":
				var v := Vector2.from_angle(g.vrng.randf_range(0.0, TAU))
				var at: Vector2 = h.pos + Vector2(v.x, v.y * 0.62) * float(h.r) * sqrt(g.vrng.randf())
				_chip(g, pool, at, Vector2.UP, 0.0, 2.0, true)

static func _field_crystals(w: Dictionary) -> Array:
	# Same crystal placement as final_boss_materials._ice_field; read-only.
	var out: Array = []
	var inner: float = float(w.get("inner_r", 0.0))
	var half: float = float(w.get("half", PI / 16))
	for j in 6:
		var angle: float = float(w.ang) + sin(j * 2.7) * half * 0.36
		var edge: float = Materials.field_radius(w, angle) - 30.0
		if edge <= maxf(65.0, inner + 5.0): continue
		out.append(w.pos + Vector2.from_angle(angle) * lerpf(maxf(65.0, inner + 5.0), edge, (j + 0.5) / 6.0))
	return out

## Resolve / spawn: crystals and shards rise, then shatter later with emit_delay so the break frames are matched.
static func _ice_burst(g, pool, w: Dictionary) -> void:
	var skin: String = str(w.get("skin", ""))
	var d := Vector2.from_angle(float(w.get("ang", 0.0)))
	var n := d.orthogonal()
	match skin:
		"ice_field":
			var roots := _field_crystals(w)
			if roots.is_empty(): return
			var count: int = Beam.take(g, roots.size() * 3)   # per crystal: rise mist, then two break shards
			for i in count:
				var root: Vector2 = roots[i % roots.size()]
				if i < roots.size():
					_chip(g, pool, root, Vector2.UP, 0.0, 4.0, true)
				else:
					# Crystal break starts 0.30 s before the 0.95 s impact ends: shards spill from the column and settle.
					var at: Vector2 = root + Vector2(g.vrng.randf_range(-8.0, 8.0), -g.vrng.randf_range(10.0, 44.0))
					pool.push("ice", at, (Vector2.UP * 0.4 + Vector2(g.vrng.randf_range(-1.0, 1.0), 0)).normalized(), ICE_TINT, 0.65, root.y + g.vrng.randf_range(0.0, 6.0))
		"ice_lance":
			var count: int = Beam.take(g, 12)
			for i in count:
				var v := Vector2.from_angle(TAU * (i + g.vrng.randf()) / maxf(1.0, count))
				_chip(g, pool, w.pos + Vector2(v.x, v.y * 0.62) * float(w.r) * g.vrng.randf_range(0.2, 0.9), (v * 0.6 + Vector2.UP).normalized(), 0.0, 6.0, i % 2 == 1)
		"ice_wave":
			var count: int = Beam.take(g, 14)
			for i in count:
				var v := _ring_dir(g, w)
				if v == Vector2.ZERO: continue
				_chip(g, pool, w.pos + v * float(w.r), (v.normalized() * 0.6 + Vector2.UP).normalized(), 0.0, 4.0, i % 3 == 2)
		_:
			var count: int = Beam.take(g, 16 if w.shape == "line" else 10)
			for i in count:
				var at: Vector2 = w.pos
				if w.shape == "arc":
					var radial := Vector2.from_angle(float(w.ang) + g.vrng.randf_range(-float(w.half), float(w.half)))
					at += radial * float(w.r) - d * float(w.get("arc_back", 0.0))
				elif w.shape == "line":
					at += d * g.vrng.randf() * float(w.len) + n * g.vrng.randf_range(-1.0, 1.0) * float(w.wid) * 0.8
				_chip(g, pool, at, (Vector2.UP * 1.2 + n * g.vrng.randf_range(-0.6, 0.6) + d * 0.3).normalized(), 0.0, 4.0, i % 3 == 2)

## Retire / cancel: the body shatters into shards that drop to the ground and darken.
static func _ice_shatter(g, pool, h: Dictionary) -> void:
	var skin: String = str(h.get("skin", ""))
	var d := Vector2.from_angle(float(h.get("ang", 0.0)))
	var points: Array = []
	match skin:
		"ice_thrust", "spear":
			for i in 6: points.append(h.pos + d * float(h.len) * (0.4 + 0.1 * i))
		"crescent":
			for i in 10:
				points.append(h.pos - d * float(h.get("arc_back", 0.0)) + Vector2.from_angle(float(h.ang) + lerpf(-float(h.half), float(h.half), (i + 0.5) / 10.0)) * float(h.r))
		"ice_wave":
			for i in 16:
				var v := _ring_dir(g, h)
				if v != Vector2.ZERO: points.append(h.pos + v * float(h.r))
		"ice_wall":
			for i in 14: points.append(h.pos + d * float(h.len) * (i + 0.5) / 14.0 + Vector2(0, -g.vrng.randf_range(0.0, 30.0)))
		"ice_lance":
			for j in 3:
				for k in 3: points.append(h.pos + Vector2((j - 1) * float(h.r) * 0.45, (j % 2) * 10.0 - g.vrng.randf_range(6.0, 40.0)))
	if points.is_empty(): return
	var count: int = Beam.take(g, points.size())
	var drop: float = 30.0 if skin in ["ice_wall", "ice_lance"] else 10.0
	for i in count:
		var at: Vector2 = points[i]
		var side := Vector2(g.vrng.randf_range(-1.0, 1.0), 0.0)
		if i % 3 == 2:
			pool.push("frost_mist", at, Vector2.UP, ICE_TINT)
		else:
			pool.push("ice", at, (Vector2.UP * 0.7 + side).normalized(), ICE_TINT, 0.0, at.y + g.vrng.randf_range(6.0, drop))

## Knight dash: low cold mist and a rare kicked shard behind the charging body; the ground frost itself is a fixed hairline
## pattern revealed by arrival time (boss_attack_draw._dash_frost), not airborne specks. Called once per drawn frame, token-limited.
static func dash_frost(g, e: Dictionary) -> void:
	var pool = _ice_pool(g)
	if pool == null:
		return
	var v: Vector2 = e.get("kb", Vector2.ZERO)
	if v.length_squared() < 160000.0:
		return
	var heading := v.normalized()
	var count: int = Beam.take(g, 2)
	for i in count:
		var at: Vector2 = e.pos + Vector2(0, 18) + heading.orthogonal() * g.vrng.randf_range(-16.0, 16.0) - heading * g.vrng.randf_range(0.0, 20.0)
		_chip(g, pool, at, (Vector2.UP - heading * 0.4).normalized(), 0.0, 3.0, g.vrng.randf() < 0.7)

static func _color(w: Dictionary) -> Color:
	var c: Color = w.col
	match str(w.get("skin", "")):
		"ice", "ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "spear", "crescent", "step":
			return Color(0.48, 0.81, 1.0, 0.9)
		"phantom", "bubble":
			return Color(0.78, 0.48, 1.0, 0.9)   # 偏执泡影：紫（用户 10-27，原青）
		"choir":
			return Color(0.46, 0.92, 0.84, 0.9)
		"tide", "tentacle":
			return Color(0.34, 0.72, 0.87, 0.9)
	return c

static func _material(skin: String) -> String:
	match skin:
		"ice", "ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "spear", "crescent", "step": return "blade"
		"phantom", "choir": return "bfx_flash"
		"tentacle": return "fluid"
	return "water"

static func burst(g, w: Dictionary) -> void:
	if knight_ice(w):
		var ice = _ice_pool(g)
		if ice != null: _ice_burst(g, ice, w)
		return
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
			"arc":
				var radial := Vector2.from_angle(w.ang + g.vrng.randf_range(-w.half, w.half))
				p += radial * w.r - d*float(w.get("arc_back",0.0))
				direction = -d
			"line":
				# Jitter within strata: even coverage without a dotted grid across the beam.
				var u: float = (float(i) + g.vrng.randf()) / maxf(1.0, count)
				var side: float = -1.0 if i % 2 == 0 else 1.0
				var width: float = float(w.wid)
				var along: float = lerpf(GAP_MARGIN, float(w.len) - GAP_MARGIN, u) if skin == "tide" else u * float(w.len)
				p += d * along + n * side * width * g.vrng.randf_range(0.45, 0.9)
				direction = (n * side + d * g.vrng.randf_range(-0.25, 0.45)).normalized()
				if skin in ["ice", "ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "spear"]:
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
				if w.has("gap_ang") and absf(angle_difference(Vector2(cos(angle),sin(angle)*g.combat.GROUND_Y).angle(),float(w.gap_ang)))<float(w.gap_half)+.08: continue
				var radial := Vector2.from_angle(angle)
				var gy: float = g.combat.GROUND_Y
				var inner: float = float(w.get("inner_r", 0.0))
				var outer: float = float(w.r)
				var lower: float = minf(outer, maxf(outer * 0.85, inner + 4.0))
				p += Vector2(radial.x, radial.y * gy) * g.vrng.randf_range(lower, outer)
				direction = Vector2(radial.x, radial.y / gy).normalized()
				if inner > 0.0:
					# No gravity on an annulus: droplets must not fall back into its safe center.
					material = "blade" if skin == "ice_wave" else "bfx_flash"
			"cone":
				var angle: float = float(w.ang) + g.vrng.randf_range(-float(w.half), float(w.half))
				direction = Vector2.from_angle(angle)
				p += direction * float(w.r) * g.vrng.randf_range(0.78, 0.98)
		if skin == "bubble": p.y -= float(w.get("r", 24.0)) + 14.0
		pool.push(material, p, direction, color)

static func trail(g, h: Dictionary, dt: float) -> void:
	var pool = _ice_pool(g) if knight_ice(h) else _pool(g)
	if pool == null:
		return
	var age: float = float(h.age)
	var ticks: int = mini(3, floori(age / STEP) - floori(maxf(0.0, age - dt) / STEP))
	if ticks <= 0:
		return
	if knight_ice(h):
		# Thrust fronts leave no trail (user 10-27): chips landing behind a fast front line up as a tail. They only shatter on retire.
		if str(h.get("skin", "")) != "ice_thrust": _ice_trail(g, pool, h, ticks)
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
		if h.shape == "arc":
			var radial := Vector2.from_angle(h.ang + g.vrng.randf_range(-h.half, h.half))
			p += radial*h.r - heading*(h.wid+float(h.get("arc_back",0.0)))
		elif h.shape == "line":
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
		if skin == "bubble": p.y -= float(h.get("r", 24.0)) + 14.0
		pool.push(material, p, direction, color)

static func finish(g, h: Dictionary) -> void:
	if knight_ice(h):
		var ice = _ice_pool(g)
		if ice != null: _ice_shatter(g, ice, h)
		return
	# A travelling bubble breaks into a few droplets rather than leaving a hard disappearing disk.
	if str(h.get("skin", "")) == "bubble":
		burst(g, h)

## 撞柱冲锋（骑士独有招，10-27）：碎柱冰爆——白闪碎片向上四溅后落地、根部一圈冷雾；地面星形冰裂由 boss_attack_draw 的 knight_crash 画
static func pillar_crash(g, at: Vector2) -> void:
	var pool = _ice_pool(g)
	if pool == null:
		return
	var count: int = Beam.take(g, 30)
	for i in count:
		if i % 3 == 2:
			var v := Vector2.from_angle(TAU * float(i) / maxf(1.0, count))
			pool.push("frost_mist", at + Vector2(v.x * 26.0, v.y * 12.0), Vector2.UP, ICE_TINT)
		else:
			var dir := Vector2(g.vrng.randf_range(-1.0, 1.0), -g.vrng.randf_range(0.6, 1.4)).normalized()
			var p: Vector2 = at + Vector2(g.vrng.randf_range(-10.0, 10.0), -g.vrng.randf_range(10.0, 60.0))
			pool.push("ice", p, dir, ICE_TINT, 0.0, at.y + g.vrng.randf_range(-6.0, 14.0))
