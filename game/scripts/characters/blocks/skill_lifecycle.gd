## Effect adapters bind the authoritative counter; the controller never advances it.
extends RefCounted

static func bind(o, key: String, skill: int, source, field, foreground: bool, exclusive: bool, cleanup: Callable = Callable(), unit: String = "seconds") -> void:
	if skill < 0:
		return
	o.lifecycle[key] = {"skill": skill, "source": source, "field": field, "total": float(source[field]),
		"foreground": foreground, "exclusive": exclusive, "cleanup": cleanup, "unit": unit, "ended": false}

static func remaining(o, skill: int) -> float:
	var value := 0.0
	for effect in o.lifecycle.values():
		if effect.skill == skill:
			value = maxf(value, float(effect.source[effect.field]))
	return value

static func left(o, skill: int) -> float:
	var value := -1.0
	for effect in o.lifecycle.values():
		if effect.skill == skill and effect.foreground:
			value = maxf(value, maxf(0.0, float(effect.source[effect.field])))
	return value

static func duration(o, skill: int) -> float:
	var value := 0.0
	for effect in o.lifecycle.values():
		if effect.skill == skill and effect.foreground:
			value = maxf(value, effect.total)
	return value

static func owns(o, skill: int, except_key: String = "") -> bool:
	for key in o.lifecycle:
		var effect: Dictionary = o.lifecycle[key]
		if key != except_key and effect.skill == skill:
			return true
	return false

static func status(o, skill: int) -> Array:
	var out := []
	for key in o.lifecycle:
		var effect: Dictionary = o.lifecycle[key]
		if effect.skill == skill:
			var value := maxf(0.0, float(effect.source[effect.field]))
			out.append({"effect": key, "active": value > 0.0, "background": not effect.foreground,
				"remaining": value, "total": effect.total, "unit": effect.unit})
	return out

static func occupied(o) -> bool:
	for effect in o.lifecycle.values():
		if effect.exclusive and (float(effect.source[effect.field]) > 0.0 or (o.sq_i == effect.skill and o.sq_ph != 0)):
			return true
	return false

static func tick(o) -> void:
	var ended := {}
	for effect in o.lifecycle.values():
		if not effect.ended and float(effect.source[effect.field]) <= 0.0 and not (effect.exclusive and o.sq_i == effect.skill and o.sq_ph != 0):
			effect.ended = true
			ended[effect.skill] = true
	for skill in ended:
		var complete := true
		for effect in o.lifecycle.values():
			if effect.skill == skill and not effect.ended:
				complete = false
		if complete:
			o.phase_skill_end(skill)

static func cancel(o) -> void:
	var effects: Array = o.lifecycle.values()
	o.lifecycle = {}
	for effect in effects:
		effect.source[effect.field] = false if effect.source[effect.field] is bool else 0
		if effect.cleanup.is_valid():
			effect.cleanup.call()
