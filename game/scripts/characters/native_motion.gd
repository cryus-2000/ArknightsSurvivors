## Native body presentation reads gameplay phases; it never schedules hits or movement.
extends RefCounted

static func enabled(o) -> bool:
	return o.def.has("native_motion")

static func started(o) -> void:
	if not enabled(o): return
	var slot: String = o.act_anim
	if o.id == "ulpianus" and o.act_kind == "attack" and slot == "attack": slot = "attack_s2" if o.perm[1] else "attack"
	o.native_motion["clip"] = slot if o.def.native_motion.has(slot) else ""
	o.native_motion["t"] = 0.0
	o.native_motion["from"] = 0

static func tick(o, dt: float) -> void:
	if not enabled(o): return
	var n: Dictionary = o.native_motion
	n["t"] = float(n.get("t", 0.0)) + dt
	var leap: bool = o.hw.has("sg") and float(o.hw.sg.get("leap_t", -1.0)) >= 0.0
	var anchor: Dictionary = o.hw.get("anchor", {})
	var phase: String = str(anchor.get("phase", ""))
	var hook: bool = not o.hw.get("hooks", []).is_empty()
	if bool(n.get("leap", false)) and not leap:
		n.merge({"clip": "leap_native", "from": 5, "t": 0.0, "tail": 0.2}, true)
	if str(n.get("phase", "")) != "" and phase == "":
		n.merge({"clip": str(n.get("tether", "tether_native")), "from": 6, "t": 0.0, "tail": 0.16}, true)
	if bool(n.get("hook", false)) and not hook and phase == "":
		n.merge({"clip": "tether_native", "from": 6, "t": 0.0, "tail": 0.16}, true)
	n["leap"] = leap
	n["phase"] = phase
	n["hook"] = hook
	if phase != "": n["tether"] = "zip_native" if phase == "zip" or str(anchor.get("b", {}).get("mode", "")) == "zip" else "tether_native"

static func pose(o, slot: String, frame: int, fallback: Dictionary) -> Dictionary:
	var tx: Texture2D = o.anim_tex(slot)
	if tx == null: return fallback
	return {"tex": tx, "kind": slot, "frame": clampi(frame, 0, 7), "hf": 8, "flip": (o.face < 0.0) != o.sprite_mirror(slot)}

static func state(o, st: Dictionary) -> Dictionary:
	if not enabled(o) or st.is_empty() or st.kind in ["death", "hurt"]: return st
	if o.id == "siege":
		if o.hw.has("sg") and float(o.hw.sg.get("leap_t", -1.0)) >= 0.0:
			var u: float = float(o.hw.sg.leap_t) / float(o.hw.sg.get("leap_b", {}).get("t", 0.42))
			return pose(o, "leap_native", mini(4, int(u * 5.5)), st)
		if o.act_anim == "activation" and o.attack_t > 0.0:
			return pose(o, "idle", o.timed_frame("idle", range(8), o.g.t, true), st)
	else:
		var an: Dictionary = o.hw.get("anchor", {})
		if not an.is_empty():
			var k: float = clampf(float(an.t) / maxf(float(an.dur), 0.001), 0.0, 1.0)
			var slot := "zip_native" if str(an.phase) == "zip" or str(an.get("b", {}).get("mode", "")) == "zip" else "tether_native"
			var fr := 1 + mini(1, int(k * 2.0))
			if an.phase == "reel": fr = 3 + mini(1, int(k * 2.0))
			elif an.phase == "hold": fr = 5
			elif an.phase == "zip": fr = 3 + mini(1, int(k * 2.0))
			return pose(o, slot, fr, st)
		var hooks: Array = o.hw.get("hooks", [])
		if not hooks.is_empty():
			var hook: Dictionary = hooks[-1]
			var k: float = clampf(float(hook.t) / maxf(float(hook.dur), .001), 0.0, 1.0)
			var fr := 1 + mini(1, int(k * 2.0))
			if hook.phase == "taut": fr = 3
			elif hook.phase == "drag": fr = 4 + mini(1, int(k * 2.0))
			return pose(o, "tether_native", fr, st)
		if o.act_anim == "throw" and o.attack_t > 0.0:
			return pose(o, "idle", o.timed_frame("idle", range(8), o.g.t, true), st)
		for f in o.pfx:
			if str(f.get("kind", "")) == "whirl":
				return pose(o, "whirl_native", int((1.0 - float(f.life) / float(f.max)) * 8.0), st)
	var n: Dictionary = o.native_motion
	var slot: String = str(n.get("clip", ""))
	if slot == "": return st
	var start: int = int(n.get("from", 0))
	var duration: float = float(n.get("tail", .16)) if start > 0 else float(o.def.native_motion.get(slot, 0.0))
	if float(n.get("t", 0.0)) >= duration: return st
	var fr: int = start + int(float(n.t) / maxf(duration, .001) * (8 - start))
	return pose(o, slot, fr, st)
