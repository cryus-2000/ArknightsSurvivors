extends RefCounted

# Rendering only: actual skill timer and attack event own this effect's clock.
static func state(left: float, duration: float, pulse_left: float) -> Dictionary:
	var age := maxf(0.0, duration - left)
	return {"fade": clampf(age / 0.4, 0.0, 1.0) * clampf(left / 0.5, 0.0, 1.0),
		"age": age, "pulse": clampf(pulse_left / 0.3, 0.0, 1.0),
		"frame": clampi(int((0.3 - pulse_left) * 20.0), 0, 5)}

static func draw(o, front: bool) -> void:
	var v := state(o.s_t[2], o.s_dur[2], float(o.hw.mz.s3_fx))
	var fade: float = v.fade
	if fade <= 0.0 and v.pulse <= 0.0:
		return
	var cv = o.cv
	var age: float = v.age
	# Sparse horizontal water fragments, snapped to the same 2-world-pixel grid.
	if not front:
		for i in 18:
			var x := float((i * 47) % 180 - 90)
			var y := float((i * 19) % 42 - 18)
			var drift := fmod(age * 8.0 + i * 3.0, 12.0)
			var p: Vector2 = (o.pos + Vector2(x + drift, y + 10)).snapped(Vector2(2, 2))
			cv.draw_rect(Rect2(p, Vector2(8 + (i % 3) * 4, 2)), Color(0.32, 0.65, 0.85, 0.24 * fade))
	if not front and v.pulse > 0.0:
		# Entire field reacts to one release, regardless of enemy positions/count.
		var radius: float = float(o.hw.mz.s3_fx_radius)
		o.draw_spr("fx_mizuki_s3_field", 6, v.frame, o.pos, radius * 2.0 / 228.0, false, Color(1,1,1,0.8), Vector2(0.5,0.75))
