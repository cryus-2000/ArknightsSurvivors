## Sustained attack rounds. Effect execution belongs to the operator adapter.
extends RefCounted

static func start(o, i: int) -> void:
	if not o.phases.is_empty():
		return
	var config: Array = o.B.skills[i].attack_phases
	o.phases = {"skill": i, "index": 0, "config": config, "round": {}, "queue": [], "transition": 0.0, "ended": false}
	o.set_attack_phase(o.skill_seq(i).phases[0], false)
	o.cd = 0.0

static func active_left(o, i: int) -> float:
	var s: Dictionary = o.phases
	if s.is_empty() or int(s.skill) != i:
		return -1.0
	return maxf(o.s_t[i], maxf(o.attack_t, 0.00001 if not s.queue.is_empty() else 0.0) if not s.round.is_empty() else 0.0)

static func locked(o) -> bool:
	return not o.phases.is_empty()

static func attack_locked(o) -> bool:
	var s: Dictionary = o.phases
	return not s.is_empty() and (o.s_t[s.skill] <= 0.0 or s.transition > 0.0 or s.ended)

static func begin_round(o) -> void:
	var s: Dictionary = o.phases
	if s.is_empty():
		return
	s.round = s.config[s.index].duplicate(true)
	s.round["attack"] = o.cur_attack().duplicate(true)
	s.round["anim"] = o.skill_seq(s.skill).phases[s.index].attack
	s.queue = []
	o.cd *= float(s.round.interval_mult)

static func release(o) -> void:
	var s: Dictionary = o.phases
	if s.is_empty() or s.round.is_empty():
		return
	s.queue = []
	var offsets: Array = s.round.shot_offsets
	for shot in offsets.size():
		if shot == 0:
			o.phase_shot(s.round, shot)
		else:
			s.queue.append({"at": o.attack_fire_at + (o.attack_dur - o.attack_fire_at) * float(offsets[shot]), "shot": shot})

static func tick(o, dt: float) -> void:
	var s: Dictionary = o.phases
	if s.is_empty():
		return
	if o.pos == Vector2.INF or o.away():
		cancel(o)
		return
	s.transition = maxf(0.0, float(s.transition) - dt)
	var elapsed: float = o.attack_dur - o.attack_t
	while not s.queue.is_empty() and elapsed + 0.00001 >= float(s.queue[0].at):
		var event: Dictionary = s.queue.pop_front()
		o.phase_shot(s.round, int(event.shot))
	if not o.acting() and s.queue.is_empty():
		s.round = {}
	var i: int = s.skill
	if o.s_t[i] > 0.0 and not o.acting():
		var next: int = s.index
		for j in s.config.size():
			if o.s_t[i] <= o.s_dur[i] * (1.0 - float(s.config[j].at)):
				next = j
		if next != s.index:
			s.index = next
			s.transition = o.set_attack_phase(o.skill_seq(i).phases[next], true)
			o.cd = maxf(o.cd, s.transition)
	if not s.ended and active_left(o, i) <= 0.0:
		s.ended = true
		o.phase_skill_end(i)
	if s.ended and (o.sq_i != i or o.sq_ph == 0):
		o.phases = {}

static func cancel(o) -> void:
	if o.phases.is_empty():
		return
	o.s_t[o.phases.skill] = 0.0
	o.phases = {}
	o.cancel_skill_action()

static func validate(sb: Dictionary, p: String, ctx: Dictionary, attack, i: int, evaluate: Callable) -> void:
	if not attack is Dictionary:
		ctx.errs.append(p + ".attack_phases requires an attack object")
		return
	var phases = sb.get("attack_phases")
	if not phases is Array or phases.is_empty():
		ctx.errs.append(p + ".attack_phases must be a nonempty array")
		return
	if str(attack.get("flow", "")) == "free" or not str(attack.get("shape", "")) in ["circle", "cone", "cannon"]:
		ctx.errs.append(p + ".attack_phases requires circle/cone or a cannon adapter")
	if attack.has("armed") or attack.has("combo"):
		ctx.errs.append(p + ".attack_phases cannot combine armed/combo attacks")
	var dur: float = number(sb.get("dur"), p + ".dur", ctx, evaluate)
	if dur <= 0.0:
		ctx.errs.append(p + ".dur must be positive")
	var skills = ctx.sprites.get("skills", {})
	var seq = skills.get("s%d" % (i + 1), {}) if skills is Dictionary else null
	if not seq is Dictionary:
		ctx.errs.append(p + ".attack_phases requires an animation sequence object")
		return
	var animations = seq.get("phases", [])
	if not animations is Array or animations.size() != phases.size() or not seq.has("start") or seq.has("hold"):
		ctx.errs.append(p + ".attack_phases needs matching sprites.skills phases and a start sequence")
		return
	var previous := -1.0
	for j in phases.size():
		var stage = phases[j]
		var path := p + ".attack_phases[%d]" % j
		if not stage is Dictionary:
			ctx.errs.append(path + " must be an object")
			continue
		var at: float = number(stage.get("at"), path + ".at", ctx, evaluate)
		if at < 0.0 or at >= 1.0 or at <= previous or (j == 0 and at != 0.0):
			ctx.errs.append(path + ".at must start at zero and strictly increase below one")
		previous = at
		for key in ["interval_mult", "damage_mult"]:
			var value: float = number(stage.get(key), path + "." + key, ctx, evaluate)
			if value <= 0.0:
				ctx.errs.append(path + "." + key + " must be positive")
		var count: float = number(stage.get("burst"), path + ".burst", ctx, evaluate)
		if count < 1.0 or count != floor(count):
			ctx.errs.append(path + ".burst must be a positive integer")
		if not stage.get("target", "") in ["inherit", "random"]:
			ctx.errs.append(path + ".target must be inherit/random")
		if stage.get("target", "") == "random" and str(attack.get("shape", "")) == "circle" and str(attack.get("center", "")) != "target":
			ctx.errs.append(path + ".target random circle requires center target")
		var offsets = stage.get("shot_offsets")
		if not offsets is Array or offsets.size() != int(count):
			ctx.errs.append(path + ".shot_offsets must match burst")
		else:
			var prev := -1.0
			for k in offsets.size():
				var offset: float = number(offsets[k], path + ".shot_offsets", ctx, evaluate)
				if offset < 0.0 or offset >= 1.0 or offset <= prev or (k == 0 and offset != 0.0):
					ctx.errs.append(path + ".shot_offsets must start at zero and strictly increase below one")
				prev = offset
		if not animations[j] is Dictionary:
			ctx.errs.append(path + " animation must be an object")
			continue
		for key in ["loop", "attack", "end", "transition"]:
			if key == "transition" and j == 0 and not animations[j].has(key):
				continue
			var slot = animations[j].get(key, "")
			var spec = ctx.sprites.get(slot, {}) if slot is String else {}
			if not spec is Dictionary or not spec.has("tex") or not positive_number(spec.get("frames")) or not positive_number(spec.get("fps")):
				ctx.errs.append(path + "." + key + " must reference a valid sprite strip")

static func number(value, path: String, ctx: Dictionary, evaluate: Callable) -> float:
	if not (value is int or value is float or (value is String and "$" in value)):
		ctx.errs.append(path + " must be a finite number")
		return 0.0
	var result: Array = evaluate.call(value, ctx.base)
	if not result[0] or not is_finite(float(result[1])):
		ctx.errs.append(path + " must be a finite number")
		return 0.0
	return float(result[1])

static func has_swap(node) -> bool:
	if node is Dictionary:
		if str(node.get("verb", "")) == "swap_attack":
			return true
		for value in node.values():
			if has_swap(value):
				return true
	elif node is Array:
		for value in node:
			if has_swap(value):
				return true
	return false

## 全部 swap_attack 换上的普攻（校验用：持续攻击期间若别的技能换了普攻，begin_round 会用换后的那个）
static func swap_attacks(node, out: Array = []) -> Array:
	if node is Dictionary:
		if str(node.get("verb", "")) == "swap_attack":
			out.append(node.get("attack"))
		for value in node.values():
			swap_attacks(value, out)
	elif node is Array:
		for value in node:
			swap_attacks(value, out)
	return out

static func positive_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0
