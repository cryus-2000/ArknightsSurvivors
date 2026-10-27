extends RefCounted
const MaterialGrains = preload("res://scripts/render/final_attack_grains.gd")
const Bal = preload("res://scripts/core/balance.gd")
const KNIGHT_ICE := ["ice", "ice_field", "ice_wave", "ice_thrust", "ice_lance", "ice_wall", "crescent"]
## 最终首领的补充攻击。状态只存敌人字典；预警、命中与绘制使用同一份几何。
## 招式为本作改编：泡影的侵蚀与幻觉、骑士的长枪与寒冰、合唱与海流。
const NAMES := {
	"paranoia": ["追猎泡", "溟泡迸裂", "泡影收束"],
	"knight_boss": ["踏冰裂阵", "断潮劈击", "侧踏挑枪"],
	"ishar": ["合唱齐射", "合唱压境", "深海触腕"],
	"izumik": ["护群触腕", "迁徙潮", "深渊涌流"]}
var g
var hazards: Array = []
const PHASE2_NAMES := ["冰枪封径", "冻潮夹击"]

func names_for(e: Dictionary) -> Array:
	return (PHASE2_NAMES + NAMES[e.type]) if e.type=="knight_boss" and e.phase==2 else NAMES[e.type]

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
	var names: Array = names_for(e)
	var index: int = int(e.get("final_cycle", 0)) % names.size()
	e.final_cycle = index + 1
	return force_move(e, str(names[index]), dir, dist)

func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var base := {"act": "final_attack", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 0.85,
		"cancel_dead": true, "track": 0.0, "corrode": 0.3 if e.type == "paranoia" else 0.0,
		"true": e.type == "ishar", "arts": e.type in ["paranoia", "izumik"]}
	if e.type == "paranoia": base.col = Color(0.36, 0.78, 0.88)
	base.merge(d, true)
	if e.type == "knight_boss" and str(base.get("skin", "")) in KNIGHT_ICE:
		base.dmg = float(base.dmg) * Bal.v("boss/knight_ice_dmg_k", 0.8)   # 用户 10-27：弹幕变密后骑士冰锋 / 冰阵单发 ×0.8（旋钮，云端测完再定）
	base.hit_range = "近战" if shape == "cone" or str(d.get("skin", "")) == "spear" else "远程"
	var w: Dictionary = g.tele.warn(e, shape, dur, base)
	e.wind = maxf(e.wind, w.dur)
	e.cdt = maxf(e.cdt, w.dur + 0.7)
	g.bai.claim_token(e, g.t + w.dur + 0.7)
	return w

func force_move(e: Dictionary, name: String, dir: Vector2, _dist: float) -> bool:
	if not NAMES.has(e.type) or not names_for(e).has(name) or not enabled(e):
		return false
	var chained: bool = e.type == "knight_boss" and e.get("knight_combo_active", false)
	var side: Vector2 = dir.orthogonal()
	match name:
		"追猎泡":
			for k in 2:
				_warn(e, "circle", 1.0 + 0.3 * k, {"name": name if k == 0 else "", "pos": e.pos + dir * 70.0 + side * (130.0 if k == 0 else -130.0),
					"r": 24.0, "skin": "bubble", "motion": "pursuit", "ang": dir.angle(), "speed": 115.0, "life": 6.0, "turn_rate": 1.35})
		"溟泡迸裂":
			_warn(e, "circle", 1.5, {"name": name, "pos": e.pos + dir * 85.0,
				"r": 42.0, "skin": "bubble", "motion": "swelling", "ang": dir.angle(),
				"speed": 100.0, "life": 4.0, "dmg": e.dmg * 1.1})
		"泡影收束":
			var center: Vector2 = g.combat.arena_clamp(g.ppos, 140.0)
			var named := false
			for k in 16:
				var a: float = TAU * k / 16.0
				# 留出生长时的出口；每颗成熟后独立追踪，靠有限转向留出绕行空间。
				if absf(angle_difference(a, dir.angle())) < 0.7:
					continue
				_warn(e, "circle", 1.3 + (k % 4) * 0.18, {"name": "" if named else name, "pos": center + Vector2.from_angle(a) * 300.0,
					"r": 18.0, "skin": "bubble", "motion": "pursuit", "ang": a + PI, "speed": 100.0, "life": 5.5, "turn_rate": 0.85})
				named = true
		"踏冰裂阵":
			var first_duration := 1.3
			var center: Vector2 = g.zone_next_c if g.zone_frozen else e.pos
			var radius: float = g.zone_next_r if g.zone_frozen else 560.0
			for wave in 2:
				for spoke in 8:
					var w: Dictionary = _warn(e,"cone",1.3 if wave==0 else 2.7,{"name":name if spoke==0 else "", "pos":e.pos,
						"ang":dir.angle()+spoke*PI/4+wave*PI/8,"r":radius+e.pos.distance_to(center),"arena_center":center,"arena_radius":radius,"inner_r":60.0,"half":PI/16,"skin":"ice_field","chill":0.5,"ice_wave":wave,
						"tell_after":0.0 if wave==0 else first_duration})
					if wave==0: first_duration=w.dur
		"冰枪封径":
			for k in 3:
				_warn(e,"circle",1.2+k*.45,{"name":name if k==0 else "","pos":g.ppos+side*(k-1)*160.0,
					"r":105.0,"skin":"ice_lance","motion":"frost_zone","speed":0.0,"life":2.0,"chill":1.0})
		"冻潮夹击":
			# Keep the near-end escape inside the arena, even when aiming tangentially at its edge.
			if g.zone_frozen and (g.ppos-dir*228.0).distance_to(g.zone_next_c)>g.zone_next_r-20.0:
				dir=(g.ppos-g.zone_next_c).normalized()
				side=dir.orthogonal()
			for sign_side in [-1.0,1.0]:
				_warn(e,"line",1.4,{"name":name if sign_side<0 else "","pos":g.ppos-dir*180.0+side*420.0*sign_side,
					"ang":dir.angle(),"len":900.0,"wid":36.0,"skin":"ice_wall","motion":"wall",
					"velocity":side*(-sign_side*420.0),"life":1.0,"chill":0.8})
		"断潮劈击":
			_warn(e, "arc", 1.7, {"name": name, "ang": dir.angle(), "track": 0.85, "r": 640.0, "half": 0.52, "arc_back": 480.0, "wid": 26.0, "style": 3,
				"skin": "crescent", "motion": "crescent", "speed": 450.0, "accel": 5000.0, "max_speed": 1450.0, "life": 0.8, "dmg": e.dmg * 1.15})
			e.fx = dir.x
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
			for wave in 3:
				for k in sources.size():
					var source: Dictionary = sources[k]
					for lane in [-1,0,1]:
						_warn(e,"circle",1.35+.8*wave,{"name":name if wave==0 and k==0 and lane==0 else "","pos":source.pos,"r":18.0,
							"skin":"choir","motion":"linear","ang":(g.ppos-source.pos).angle()+lane*.32+(wave-1)*.12,"source":source,
							"speed":190.0,"life":4.2,"dmg":e.dmg*.6})
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
	if not chained: e.final_next = g.t + float(e.wind) + (5.0 if e.phase==2 else 7.0)
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
		h.base_r = float(w.r)
		if motion=="expanding":
			h.r=70.0
			h.inner_r=float(w.get("inner_r",70.0))
			h.base_inner_r=h.inner_r
		if w.get("skin","")=="ice_thrust":
			h.len=90.0
			h.speed=(w.len-h.len)/h.life
		h.velocity = w.get("velocity", Vector2.from_angle(w.ang) * float(h.get("speed", 0.0)))
		if hazards.size() < 80:
			hazards.append(h)
			MaterialGrains.burst(g, h)
	else:
		g.tele.warn_damage(w)
		var f: Dictionary = w.duplicate()
		f.kind = "final_impact"
		f.life = 0.95 if w.get("skin","")=="ice_field" else 0.5
		f.max = f.life
		f.enemy = true
		g.fx.append(f)
		MaterialGrains.burst(g, w)
	if w.name != "":   # One cue for the cast, not one loud layer per bubble/segment.
		Sfx.play("tentacle" if e.type != "knight_boss" else "swing", -9.0, 0.9)

func update(e: Dictionary, dt: float) -> void:
	var live: Array = []
	for h in hazards:
		if cancelled(h) or not g.bosses.has(h.owner):
			if h.owner.type=="knight_boss": _pop(h)
			continue
		if not is_same(h.owner, e):
			live.append(h)
			continue
		# Knight ice fronts must sweep the final partial frame before expiring.
		var finish_motion: bool = h.owner.type=="knight_boss"
		var step_dt: float = minf(dt,maxf(0.0,h.life-h.age)) if finish_motion else dt
		if finish_motion and is_equal_approx(step_dt,h.life-h.age): step_dt=h.life-h.age
		h.age += step_dt
		if h.age >= h.life and not finish_motion:
			_pop(h)
			continue
		if h.motion == "swelling":
			h.r = h.base_r * lerpf(1.0, 1.3, minf(1.0, h.age / 1.2))
		if h.motion == "pursuit":
			var a: float = rotate_toward(h.velocity.angle(), (g.ppos - h.pos).angle(), float(h.get("turn_rate", 1.0)) * dt)
			h.velocity = Vector2.from_angle(a) * h.speed
		var travel: Vector2 = h.velocity * step_dt
		if h.motion == "crescent":
			var forward := Vector2.from_angle(h.ang)
			travel = forward * (_accelerated_distance(h, h.age) - _accelerated_distance(h, maxf(0.0, h.age-step_dt)))
			h.velocity = forward * minf(h.max_speed, h.speed + h.accel*h.age)
		# Substeps bound swept movement to 10px even when a frame stalls.
		var expansion: float = float(h.get("wave_speed",0.0))*step_dt
		var steps: int = maxi(1, ceili(maxf(travel.length(),expansion) / 10.0))
		for k in steps:
			h.pos += travel / steps
			if h.motion=="expanding":
				h.r=minf(h.base_r,h.r+expansion/steps)
				h.inner_r=maxf(h.base_inner_r,h.r-46.0)
			if not h.hit and g.tele.hits_leader(h):
				g.tele.warn_damage(h)
				h.hit = true
				if h.skin == "bubble": break
		if h.hit and h.skin == "bubble":
			_pop(h)
			continue
		MaterialGrains.trail(g, h, step_dt)
		if finish_motion and h.age>=h.life:
			_knight_shards(h)
			_pop(h)
			continue
		live.append(h)
	hazards = live

func _pop(h: Dictionary) -> void:
	if h.owner.type=="knight_boss":
		var tail: Dictionary = h.duplicate()
		tail.erase("age")
		tail.kind="final_impact"
		tail.retiring=true
		tail.dmg=0.0
		tail.life=0.38
		tail.max=0.38
		g.fx.append(tail)
	if h.get("skin", "") == "ice_thrust" and not g is Dictionary:
		g.vfx.fx_sprite("fx_knight_ice_hit",h.pos+Vector2.from_angle(h.ang)*h.len,g.PX,h.ang)
	if h.get("skin", "") != "bubble":
		MaterialGrains.finish(g, h)
		return
	g.fx.append({"kind":"bubble_pop", "pos":h.pos, "r":float(h.r), "life":0.48, "max":0.48,
		"ang":h.velocity.angle(), "enemy":true})
	MaterialGrains.finish(g, h)

static func _accelerated_distance(h: Dictionary, age: float) -> float:
	var ramp := minf(age, (h.max_speed-h.speed)/h.accel)
	return h.speed*ramp + 0.5*h.accel*ramp*ramp + h.max_speed*(age-ramp)

## 骑士冰锋 / 冰波自然收尾碎出少量冰屑弹（knight_boss.ice_shards，10-27）；打断、撞柱不出
func _knight_shards(h: Dictionary) -> void:
	var e: Dictionary = h.owner
	var kb = g.bai.boss("knight_boss")
	if kb == null:
		return
	match str(h.get("skin", "")):
		"crescent":
			kb.ice_shards(e, h.pos + Vector2.from_angle(h.ang) * (float(h.r) - float(h.get("arc_back", 0.0))), float(h.ang), 5, 1.0, 160.0)
		"ice_thrust":
			kb.ice_shards(e, h.pos + Vector2.from_angle(h.ang) * float(h.len), float(h.ang), 3, 0.7, 150.0)
