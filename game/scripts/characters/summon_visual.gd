extends RefCounted
## Display-only source timelines. Gameplay must never read this state.

static func start(state: Dictionary, meta: Dictionary, now: float, windup: float = 0.0) -> void:
	cancel(state)
	if not meta.is_empty():
		state.visual = {"meta": meta, "start": now, "windup": windup, "hit": -1.0}

static func cancel(state: Dictionary) -> void:
	state.erase("visual")

static func hit(state: Dictionary, now: float) -> void:
	if state.has("visual"):
		state.visual.hit = now

static func time(state: Dictionary, now: float) -> float:
	var v: Dictionary = state.visual
	var meta: Dictionary = v.meta
	if not meta.has("event"):
		return maxf(0.0, now - float(v.start))
	var event: float = float(meta.event)
	if float(v.hit) >= 0.0:
		return event + maxf(0.0, now - float(v.hit))
	return minf(event, maxf(0.0, now - float(v.start)) / maxf(0.0001, float(v.windup)) * event)

static func frame(meta: Dictionary, elapsed: float, loop: bool) -> int:
	var t := fposmod(maxf(elapsed, 0.0), float(meta.duration)) if loop else maxf(elapsed, 0.0)
	var times: Array = meta.times
	var result := 0
	for i in times.size():
		if float(times[i]) > t + 0.000001:
			break
		result = i
	return result

static func errors(sprites: Dictionary, extras: Array) -> Array:
	var out: Array = []
	for key in sprites:
		var spec = sprites[key]
		if not (spec is Dictionary) or not spec.has("visual"):
			continue
		var p: String = "sprites.%s.visual" % key
		var m = spec.visual
		if not (m is Dictionary):
			out.append(p + " must be a dictionary")
			continue
		var anim: String = str(m.get("anim", ""))
		var target = sprites.get(anim, {})
		if not (target is Dictionary) or not target.has("tex") or not anim in extras:
			out.append(p + " requires a native sprite slot in extra_sprites")
			continue
		var count = target.get("frames", null)
		if not _number(count) or float(count) <= 0.0 or float(count) != floorf(float(count)):
			out.append(p + " native frames must be a positive integer")
			continue
		var duration = m.get("duration", null)
		if not _number(duration) or float(duration) <= 0.0:
			out.append(p + ".duration must be positive")
			continue
		var times = m.get("times", null)
		if not (times is Array) or times.is_empty():
			out.append(p + ".times must contain source sample times")
			continue
		if float(times.size()) != float(count):
			out.append(p + ".times must match native frame count")
		var prev := -1.0
		for value in times:
			if not _number(value) or float(value) < 0.0 or float(value) <= prev or float(value) > float(duration):
				out.append(p + ".times must strictly ascend within duration")
				break
			prev = float(value)
		if not _number(times[0]) or float(times[0]) != 0.0:
			out.append(p + ".times must begin at zero")
		if m.has("event") and (not _number(m.event) or float(m.event) < 0.0 or float(m.event) > float(duration)):
			out.append(p + ".event must be within duration")
	return out

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))
