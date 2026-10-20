extends RefCounted
## Ulpianus-only visual envelope, on the body's 2 px world grid.
const GroundCrack = preload("res://scripts/render/ground_crack.gd")
const CRACK_EDGE := Color(0.3, 0.5, 0.61)
const WATER := Color(0.24, 0.52, 0.64)

static func spawn(o, c: Vector2, r: float, k: float) -> void:
	o.fx({"kind": "ulp_wave", "pos": c, "r": r, "life": 0.42, "floor": true})
	o.fx({"kind": "ulp_fracture", "pos": c, "r": r, "life": 0.72, "floor": true})
	splash(o, c, k)

static func splash(o, c: Vector2, k: float) -> void:
	o.spawn_fx_sprite("fx_splash_blue", c + Vector2(0, 6), o.g.PX * clampf(0.8 * k, 0.8, 1.6), 0.0, false, true)

static func draw(o, f: Dictionary, a: float) -> bool:
	var age: float = float(f.max) - float(f.life)
	if str(f.kind) == "ulp_fracture":
		if not f.has("cracks"):
			# Extend paths, keeping their world-space widths and 2 px grid unchanged.
			var reach: float = clampf(float(f.r) * 0.85 + 14.0, 64.0, 110.0)
			f.cracks = GroundCrack.build(f.pos, reach, 0.3, {"n": 5, "w0": Vector2(1.0, 1.6),
				"length": Vector2(0.75, 1.05), "steps": Vector2i(4, 5), "branch": 0.18, "crater": false, "gy": 0.42})
		GroundCrack.draw(f.cracks, age, minf(a, 0.78), CRACK_EDGE, GroundCrack.CvSink.new(o))
		# A thin upper lip stays readable on the dark floor after the splash clears.
		# Build the edge from the same paths; no enlarged texture or wide glow.
		var edge_alpha: float = 0.65 * clampf(float(f.life) / 0.22, 0.0, 1.0) * o.g.world.fx_dim
		var grow: float = clampf(age / 0.06, 0.0, 1.0)
		for segment in f.cracks.segs:
			if float(segment.ws[0]) < 1.0:
				continue
			var points: PackedVector2Array = segment.pts
			var count: int = mini(points.size(), maxi(2, int(ceil(points.size() * grow))))
			for i in count - 1:
				o.cv.draw_line(points[i] + Vector2(0, -2), points[i + 1] + Vector2(0, -2),
					Color(CRACK_EDGE, edge_alpha), 2.0)
		return true
	if str(f.kind) != "ulp_wave":
		return false
	var r: float = clampf(float(f.r) * 0.65, 22.0, 76.0)
	# Water crests first; the thin ground arcs follow after 80 ms.
	var pulling: bool = f.get("pull", false)
	var delay: float = 0.0 if pulling else 0.08
	var u: float = clampf((age - delay) / maxf(0.01, float(f.max) - delay), 0.0, 1.0)
	if u <= 0.0 or u >= 1.0:
		return true
	var phase: float = 1.0 - pow(1.0 - u, 2.0)
	var rr: float = lerpf(r, r * 0.32, phase) if pulling else lerpf(r * 0.32, r, phase)
	for i in 4:
		var arc := PackedVector2Array()
		var start: float = float(i) * PI * 0.5 + 0.18
		for j in 13:
			var angle: float = start + float(j) / 12.0 * 0.82
			arc.append(_snap(f.pos + Vector2(cos(angle) * rr, sin(angle) * rr * 0.4)))
		o.cv.draw_polyline(arc, Color(WATER, a * sin(u * PI) * 0.52 * float(f.get("alpha", 1.0))), 2.0)
	return true

static func _snap(p: Vector2) -> Vector2:
	return (p / 2.0).round() * 2.0
