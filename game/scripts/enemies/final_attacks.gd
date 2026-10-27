extends RefCounted
const MaterialGrains = preload("res://scripts/render/final_attack_grains.gd")
## 最终首领的补充攻击。状态只存敌人字典；预警、命中与绘制使用同一份几何。
## 招式为本作改编：泡影的侵蚀与幻觉、骑士的长枪与寒冰、合唱与海流。
const NAMES := {
	"paranoia": ["追猎泡", "幻影合围", "泡影收束"],
	"knight_boss": ["踏冰裂阵", "断潮劈击", "侧踏挑枪"],
	"ishar": ["合唱齐射", "合唱压境", "深海触腕"],
	"izumik": ["护群触腕", "迁徙潮", "深渊涌流"]}
var g
var hazards: Array = []

func _init(game) -> void:
	g = game

func enabled(e: Dictionary) -> bool:
	return NAMES.has(e.type) and not e.dead and not e.get("friendly", false) and not e.get("invuln", false) \
		and not e.get("coma", false) and float(e.get("cocoon_t", 0.0)) <= 0.0 \
		and (e.type not in ["ishar", "izumik"] or e.phase == 2)

func try_attack(e: Dictionary, dir: Vector2, dist: float) -> bool:
	if not enabled(e) or dist > 1000.0 or int(e.get("dash2", 0)) > 0 or e.has("breath_at") \
		or float(e.get("hunt_follow_at", INF)) < INF or e.has("leap"):
		return false
	if not e.has("final_next"):
		e.final_next = g.t + 5.0
	if g.t < float(e.final_next):
		return false
	var index: int = int(e.get("final_cycle", 0)) % 3
	e.final_cycle = index + 1
	return force_move(e, str(NAMES[e.type][index]), dir, dist)

func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var base := {"act": "final_attack", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 0.85,
		"cancel_dead": true, "track": 0.0, "corrode": 0.3 if e.type == "paranoia" else 0.0,
		"true": e.type == "ishar", "arts": e.type in ["paranoia", "izumik"]}
	base.merge(d, true)
	base.hit_range = "近战" if shape == "cone" or str(d.get("skin", "")) == "spear" else "远程"
	var w: Dictionary = g.tele.warn(e, shape, dur, base)
	e.wind = maxf(e.wind, w.dur)
	e.cdt = maxf(e.cdt, w.dur + 0.7)
	g.bai.claim_token(e, g.t + w.dur + 0.7)
	return w

func force_move(e: Dictionary, name: String, dir: Vector2, _dist: float) -> bool:
	if not NAMES.has(e.type) or not NAMES[e.type].has(name) or not enabled(e):
		return false
	var side: Vector2 = dir.orthogonal()
	match name:
		"追猎泡":
			for k in 2:
				_warn(e, "circle", 1.0 + 0.3 * k, {"name": name if k == 0 else "", "pos": e.pos + dir * 70.0 + side * (130.0 if k == 0 else -130.0),
					"r": 24.0, "skin": "bubble", "motion": "pursuit", "ang": dir.angle(), "speed": 115.0, "life": 4.5, "home_t": 1.8})
		"幻影合围":
			for k in 2:
				var p: Vector2 = g.combat.arena_clamp(e.pos + side * (210.0 if k == 0 else -210.0), 70.0)
				_warn(e, "line", 1.25 + 0.65 * k, {"name": name if k == 0 else "", "pos": p, "ang": (g.ppos - p).angle(),
					"len": 700.0, "wid": 24.0, "track": 0.55 + 0.65 * k, "skin": "phantom", "cancel_break": true})
		"泡影收束":
			var center: Vector2 = g.combat.arena_clamp(g.ppos, 140.0)
			var named := false
			for k in 16:
				var a: float = TAU * k / 16.0
				# 朝首领反方向留下约 90 度逃生口；向内移动，区别于原扩散环。
				if absf(angle_difference(a, dir.angle())) < 0.7:
					continue
				_warn(e, "circle", 1.3, {"name": "" if named else name, "pos": center + Vector2.from_angle(a) * 300.0,
					"r": 18.0, "skin": "bubble", "motion": "linear", "ang": a + PI, "speed": 100.0, "life": 2.5})
				named = true
		"踏冰裂阵":
			for k in 3:
				_warn(e, "line", 1.35 + 0.2 * k, {"name": name if k == 0 else "", "ang": dir.angle() + (k - 1) * 0.5,
					"len": 530.0, "wid": 19.0, "skin": "ice", "chill": 0.5})
		"断潮劈击":
			_warn(e, "line", 1.3, {"name": name, "ang": dir.angle(), "track": 0.55, "len": 550.0, "wid": 96.0,
				"skin": "crescent", "motion": "crescent", "speed": 245.0, "life": 2.25, "dmg": e.dmg * 1.15})
		"侧踏挑枪":
			var sign_side: float = -1.0 if int(e.get("final_cycle", 0)) % 2 else 1.0
			var to: Vector2 = g.combat.arena_clamp(g.map.push_out(e.pos + side * 170.0 * sign_side, e.r), 90.0)
			_warn(e, "line", 0.7, {"name": name, "ang": (to - e.pos).angle(), "len": e.pos.distance_to(to), "wid": 22.0,
				"skin": "step", "motion": "sidestep", "destination": to, "dmg": 0.0})
		"合唱齐射":
			var sources: Array = choir_sources(e)
			for k in sources.size():
				var source: Dictionary = sources[k]
				var p: Vector2 = source.pos
				_warn(e, "line", 1.2 + 0.4 * k, {"name": name if k == 0 else "", "pos": p, "ang": (g.ppos - p).angle(),
					"len": 780.0, "wid": 17.0, "track": 0.5 + 0.4 * k, "skin": "choir", "source": source, "dmg": e.dmg * 0.6})
		"合唱压境":
			var sources: Array = choir_sources(e)
			for k in sources.size():
				var source: Dictionary = sources[k]
				_warn(e, "circle", 1.35, {"name": name if k == 0 else "", "pos": source.pos, "r": 34.0,
					"skin": "choir", "motion": "linear", "ang": (g.ppos - source.pos).angle(), "source": source,
					"speed": 130.0, "life": 3.0, "dmg": e.dmg * 0.8})
		"深海触腕":
			# 两条触腕从两侧夹击；中心通道与外侧都可躲，非近身咬击的换名。
			for k in 2:
				var p: Vector2 = g.combat.arena_clamp(g.ppos + side * (150.0 if k == 0 else -150.0) - dir * 250.0, 60.0)
				_warn(e, "line", 1.3 + 0.4 * k, {"name": name if k == 0 else "", "pos": p, "ang": dir.angle(),
					"len": 520.0, "wid": 35.0, "skin": "tentacle", "dmg": e.dmg})
		"护群触腕":
			var p: Vector2 = e.pos
			# 优先守护最近一批；无子代的末幕也由本体发动，保持攻击可达。
			for child in e.get("batch", []):
				if not child.dead:
					p = child.pos
					break
			_warn(e, "cone", 1.35, {"name": name, "pos": p, "ang": (g.ppos - p).angle(), "r": 320.0,
				"half": 0.55, "track": 0.55, "skin": "tentacle", "dmg": e.dmg * 1.1})
		"迁徙潮":
			var center: Vector2 = g.zone_c if g.zone_state != 0 else e.pos
			var radius: float = minf(650.0, g.zone_r - 55.0) if g.zone_state != 0 else 550.0
			var gap: float = clampf((g.ppos - center).dot(side), -radius * 0.5, radius * 0.5)
			for k in 2:
				var lo: float = -radius if k == 0 else gap + 90.0
				var hi: float = gap - 90.0 if k == 0 else radius
				_warn(e, "line", 1.6, {"name": name if k == 0 else "", "pos": center - dir * radius + side * lo,
					"ang": side.angle(), "len": hi - lo, "wid": 19.0, "skin": "tide", "motion": "wall",
					"velocity": dir * 150.0, "life": radius * 2.0 / 150.0, "dmg": e.dmg})
		"深渊涌流":
			# 环带会向内塌陷，中心明确安全；两段不同半径要求一次内外位置选择。
			for k in 2:
				_warn(e, "circle", 1.5 + 0.85 * k, {"name": name if k == 0 else "", "pos": e.pos,
					"r": 360.0 - k * 120.0, "inner_r": 240.0 - k * 120.0, "skin": "abyss", "dmg": e.dmg})
	e.final_next = g.t + float(e.wind) + 7.0
	return true

func choir_sources(e: Dictionary) -> Array:
	var out: Array = []
	for slot in e.get("web", []):
		var o = slot.get("o")
		if o is Dictionary and not o.dead:
			out.append(o)
			if out.size() == 3:
				break
	# 清空海嗣有收益（只有一束/一列），但不会使本体永久失去这两招。
	if out.is_empty():
		out.append(e)
	return out

func cancelled(w: Dictionary) -> bool:
	var e: Dictionary = w.owner
	var source = w.get("source")
	return not enabled(e) or float(e.get("break_t", 0.0)) > 0.0 or float(e.get("stun", 0.0)) > 0.0 \
		or (source is Dictionary and source.get("dead", false))

func resolve(w: Dictionary) -> void:
	if cancelled(w):
		return
	var e: Dictionary = w.owner
	var motion: String = str(w.get("motion", ""))
	if motion == "sidestep":
		MaterialGrains.burst(g, w)
		e.pos = w.destination
		_warn(e, "line", 1.0, {"name": "侧踏挑枪", "pos": e.pos, "ang": (g.ppos - e.pos).angle(), "len": 420.0,
			"wid": 28.0, "track": 0.4, "skin": "spear", "dmg": e.dmg * 1.2})
		return
	if motion != "":
		var h: Dictionary = w.duplicate()
		h.age = 0.0
		h.hit = false
		h.velocity = w.get("velocity", Vector2.from_angle(w.ang) * float(w.get("speed", 0.0)))
		if motion == "crescent":
			var side := Vector2.from_angle(w.ang).orthogonal()
			h.pos = w.pos - side * 90.0
			h.ang = side.angle()
			h.len = 180.0
			h.wid = 18.0
		if hazards.size() < 80:
			hazards.append(h)
			MaterialGrains.burst(g, h)
	else:
		g.tele.warn_damage(w)
		var f: Dictionary = w.duplicate()
		f.kind = "final_impact"
		f.life = 0.38
		f.max = 0.38
		f.enemy = true
		g.fx.append(f)
		MaterialGrains.burst(g, w)
	if w.name != "":   # One cue for the cast, not one loud layer per bubble/segment.
		Sfx.play("tentacle" if e.type != "knight_boss" else "swing", -9.0, 0.9)

func update(e: Dictionary, dt: float) -> void:
	var live: Array = []
	for h in hazards:
		if cancelled(h) or not g.bosses.has(h.owner):
			continue
		if not is_same(h.owner, e):
			live.append(h)
			continue
		h.age += dt
		if h.age >= h.life:
			MaterialGrains.finish(g, h)
			continue
		if h.motion == "pursuit" and h.age < float(h.home_t):
			var a: float = lerp_angle(h.velocity.angle(), (g.ppos - h.pos).angle(), minf(1.0, dt * 1.8))
			h.velocity = Vector2.from_angle(a) * h.speed
		# Substeps bound swept movement to 10px even when a frame stalls.
		var steps: int = maxi(1, ceili(h.velocity.length() * dt / 10.0))
		for k in steps:
			h.pos += h.velocity * dt / steps
			if not h.hit and g.tele.hits_leader(h):
				g.tele.warn_damage(h)
				h.hit = true
		MaterialGrains.trail(g, h, dt)
		live.append(h)
	hazards = live
