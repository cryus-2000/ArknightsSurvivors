## 水月（特种，契约 v2.1）：伞击 + 天赋「创伤性癔症」触手追击；三个自动技能：S1 唤醒 / S2 囚徒困境 / S3 镜花水月。
## 精一解锁 S2 与天赋二「反移情」，精二解锁 S3。与其他干员同构；旧的潮刃 / 群触路线与技能进阶已下线（docs/23 §17）。
extends "res://scripts/characters/character.gd"

const UI = preload("res://scripts/ui.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")

# 技能参数
const S1_MULT := 3.0            # 唤醒：强化一击伤害倍率
const S1_RADIUS := 1.3
const S1_BURST_R := 80.0        # 唤醒命中处的范围冲击（创伤扩散）
const S1_BURST_MULT := 0.6
const S2_DUR := 12.0            # 囚徒困境：持续、挥伞间隔倍率、束缚
const S2_INTERVAL := 0.5
const S2_BIND := 1.0
const S3_DUR := 14.0            # 镜花水月：持续、范围、伤害、晕眩、镜像
const S3_RADIUS := 1.45
const S3_MULT := 1.8
const S3_STUN := 0.6
const S3_ECHO_MULT := 0.6

var swing_cd := 0.0
var u_dmg_mult := 1.0
var u_area_mult := 1.0
var u_spd_mult := 1.0
var t_mult := 0.6                # 天赋一：触手追击倍率
var rib_bonus := 0.0
var extra_targets := 0
var delayed: Array = []          # 延时攻击（创伤扩散、镜像）
var afterimg: Array = []         # 镜花水月残影
var afterimg_t := 0.0
var s1_charges := 0              # 唤醒：待用的强化次数
var s2_active := 0.0
var s3_active := 0.0
var mirror_pos := Vector2.ZERO   # S3 镜像分身位置
var mirror_face := 1.0
var heal_budget := 0.0           # 反移情击杀回复：每秒上限


func _swing_radius() -> float:
	var r: float = base("swing_radius", 95.0) * u_area_mult
	if s3_active > 0.0:
		r *= S3_RADIUS
	return r


func _dmg_bonus() -> float:
	var m: float = stat(&"dmg") * stat(&"op_atk")
	if elite >= 1 and _low_hp_enemy_near():
		m *= 1.22
	if g.backlight and g.lamp < 30.0:
		m *= 1.3
	return m


func _low_hp_enemy_near() -> bool:
	for j in g._query(pos, 160.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.hp < e.maxhp * 0.5 and e.pos.distance_to(pos) < 160.0:
			return true
	return false


func update(dt: float) -> void:
	heal_budget = min(heal_budget + dt * 0.05, 0.05)
	s2_active = maxf(0.0, s2_active - dt)
	if s3_active > 0.0:
		s3_active -= dt
		mirror_pos = mirror_pos.lerp(pos + Vector2(-face * 80.0, -10.0), minf(1.0, dt * 8.0))
		afterimg_t -= dt
		if afterimg_t <= 0.0:
			afterimg_t = 0.06
			var ast := anim_state()
			if not ast.is_empty():
				afterimg.push_front({"pos": pos, "frame": ast.frame, "tex": ast.tex, "hf": ast.hf, "flip": ast.flip})
			if afterimg.size() > 5:
				afterimg.pop_back()
	else:
		afterimg.clear()
	# 三个技能充能；到点直接发动（水月的技能都是状态型，不需要起手动作）
	var ready := charge_skills(dt)
	if ready >= 0:
		spend_sp(ready)
		match ready:
			0:
				s1_charges = mini(3, s1_charges + 1)
				g._add_text(pos + Vector2(0, -80), "唤醒", UI.GOLD, 15)
			1:
				s2_active = S2_DUR
				_skill_cast(1)
			2:
				s3_active = S3_DUR
				mirror_pos = pos
				_skill_cast(2)
	# 延时攻击
	for i in range(delayed.size() - 1, -1, -1):
		var dl: Dictionary = delayed[i]
		dl.at -= dt
		if dl.at <= 0.0:
			delayed.remove_at(i)
			_run_delayed(dl)
	swing_cd -= dt
	if swing_cd <= 0.0:
		var radius := _swing_radius()
		var targets = g._nearest(1, radius + 60.0, pos)
		if targets.size() > 0:
			var interval: float = base("swing_interval", 0.9) * u_spd_mult / stat(&"op_aspd") * (1.5 if g.atk_slow > 0.0 else 1.0) * g.rfx.umbrella_interval_mult()
			if s2_active > 0.0:
				interval *= S2_INTERVAL
			swing_cd = max(0.18, interval)
			_umbrella(targets[0])
		else:
			swing_cd = 0.1


func skill_active_left(i: int) -> float:
	return [0.0, s2_active, s3_active][i]


func skill_active_dur(i: int) -> float:
	return [1.0, S2_DUR, S3_DUR][i]


func _umbrella(target: Dictionary) -> void:
	var radius := _swing_radius()
	var half := deg_to_rad(min(180.0, 75.0 + rib_bonus))
	var ang: float = (target.pos - pos).angle()
	face_to(ang)
	attack_t = attack_dur
	var dmg: float = base("umbrella_dmg", 18.0) * u_dmg_mult * _dmg_bonus()
	if s3_active > 0.0:
		dmg *= S3_MULT
	# S1「唤醒」：有储备时这一击强化
	var empowered := false
	if s1_charges > 0:
		s1_charges -= 1
		empowered = true
		dmg *= S1_MULT * skill_power()
		radius *= S1_RADIUS
	# 攻击方向：常态单方向；镜花水月三方向
	var dirs: Array = [ang]
	if s3_active > 0.0:
		dirs = [ang, ang + TAU / 3.0, ang - TAU / 3.0]
	var seen := {}
	var hit: Array = []
	for d in dirs:
		for e in g._arc_hit(pos, d, half, radius):
			if not seen.has(e.id):
				seen[e.id] = true
				hit.append(e)
	g.crit_hit = empowered
	dmg *= g.rfx.single_hit_mult(hit.size())
	for e in hit:
		g._hit("伞击", ["empowered"] if empowered else [])
		g._damage(e, dmg)
		if not e.boss:
			e.kb += (e.pos - pos).normalized() * (360.0 if empowered else 240.0)
		if s3_active > 0.0 and not e.dead:
			e.stun = maxf(e.stun, S3_STUN)
	g.crit_hit = false
	Sfx.play("swing_heavy" if empowered else "swing", -3.0 if empowered else -7.0)
	if hit.size() > 0:
		Sfx.play("hit", -2.0 if empowered else -5.0, 0.85 if empowered else 1.0)
		g.hitstop = max(g.hitstop, 0.09 if empowered else 0.03)
		for k in min(hit.size(), 6):
			var he: Dictionary = hit[k]
			g._sparks(he.pos, he.pos - pos, UI.GOLD if empowered else Color(0.85, 0.97, 1.0), 4 if empowered else 3, 260.0)

	# 天赋「创伤性癔症」：触手追击命中目标中生命最低的敌人
	var alive := hit.filter(func(e): return not e.dead)
	alive.sort_custom(func(a, b): return a.hp < b.hp)
	var n: int = 1 + extra_targets + g.rfx.tentacle_targets_extra()
	if s2_active > 0.0:
		n += 1
	if s3_active > 0.0:
		n += 1
	var tdmg: float = dmg * t_mult
	var stun := 0.0
	if s3_active > 0.0:
		stun = 1.0
	elif s2_active > 0.0:
		stun = S2_BIND
	for i in min(n, alive.size()):
		_spawn_tentacle(alive[i], tdmg, stun)
	if g.grip:
		for e in alive:
			if not e.dead and g.rng.randf() < 0.2:
				_spawn_tentacle(e, tdmg * 0.6, 0.0)

	# 唤醒：命中处范围冲击（创伤扩散）
	if empowered and hit.size() > 0:
		var ip: Vector2 = hit[0].pos
		g.fx.append({"kind": "impact", "pos": ip, "ang": ang, "life": 0.35, "max": 0.35, "col": UI.GOLD})
		g.fx.append({"kind": "ring", "pos": ip, "r": 70.0, "life": 0.3, "max": 0.3, "col": UI.GOLD})
		g.flash = maxf(g.flash, 0.12)
		for k in mini(hit.size(), 3):
			delayed.append({"at": 0.06 * k, "kind": "burst", "pos": hit[k].pos, "dmg": dmg * S1_BURST_MULT, "r": S1_BURST_R})
	# 镜花水月：镜像分身同步挥伞
	if s3_active > 0.0:
		delayed.append({"at": 0.12, "kind": "echo", "ang": ang, "dmg": dmg * S3_ECHO_MULT * skill_power(), "half": half, "radius": radius, "dirs": dirs.size()})

	# ---- 斩击表现
	var slash_col := Color.WHITE
	if empowered:
		slash_col = Color(1.6, 1.3, 0.7)
	elif s3_active > 0.0:
		slash_col = Color(1.2, 0.85, 1.6)
	elif s2_active > 0.0:
		slash_col = Color(0.8, 1.1, 1.5)
	var slash_tex = g._slash_tex("awaken" if empowered else ("mirage" if s3_active > 0.0 else "base"))
	if slash_tex.begins_with("fx_umbrella_slash"):
		slash_col = Color(1.15, 1.15, 1.15)
	if empowered and alive.size() > 0:
		g._anim("fx_s1_burst", alive[0].pos, 0.35)
	for k in min(hit.size(), 3):
		g._hit_fx(hit[k], hit[k].pos - pos)
	for d in dirs:
		g._slash_fx(pos, d, half, radius, slash_col, slash_tex, 0.26 if empowered else 0.22)
	if empowered and not slash_tex.begins_with("fx_umbrella_slash"):
		g._slash_fx(pos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)


## 延时攻击的执行
func _run_delayed(dl: Dictionary) -> void:
	match dl.kind:
		"burst":
			# 创伤扩散：目标处的范围冲击
			for j in g._query(dl.pos, dl.r):
				var e: Dictionary = g.enemies[j]
				if not e.dead and e.pos.distance_to(dl.pos) < dl.r + e.r:
					g._hit("技能·法术")
					g._damage(e, dl.dmg)
					if not e.boss:
						e.kb += (e.pos - dl.pos).normalized() * 200.0
			g.fx.append({"kind": "burst", "pos": dl.pos, "r": dl.r, "life": 0.4, "max": 0.4, "col": UI.GOLD})
			g._sparks(dl.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 10, 280.0)
			Sfx.play("boom", -10.0, 1.4, 0.1)
		"echo":
			# 镜像：身后的镜像分身朝它身边的敌人同步挥伞
			var mp: Vector2 = mirror_pos
			var ma: float = dl.ang
			var near_d: float = dl.radius * 1.4
			for e in g.enemies:
				if e.dead:
					continue
				var dd: float = mp.distance_to(e.pos)
				if dd < near_d:
					near_d = dd
					ma = (e.pos - mp).angle()
			var dirs: Array = [ma]
			if dl.dirs > 1:
				dirs = [ma, ma + TAU / 3.0, ma - TAU / 3.0]
			var seen := {}
			for d in dirs:
				for e in g._arc_hit(mp, d, dl.half, dl.radius):
					if seen.has(e.id):
						continue
					seen[e.id] = true
					g._hit("技能", ["echo"])
					g._damage(e, dl.dmg)
					if not e.dead:
						e.stun = maxf(e.stun, S3_STUN * 0.5)
				g._slash_fx(mp, d, dl.half, dl.radius, Color(1.0, 0.9, 1.2, 0.8) if g._slash_tex("mirage").begins_with("fx_") else Color(0.9, 0.6, 1.6, 0.8), g._slash_tex("mirage"), 0.3)
			mirror_face = -1.0 if cos(ma) < 0.0 else 1.0
			Sfx.play("swing", -9.0, 0.7, 0.05)


## 技能发动：光环爆发 + 震屏 + 推开身边小怪
func _skill_cast(i: int) -> void:
	Sfx.play("skill", -1.0, 1.0 if i == 1 else 0.8, 0.0)
	g._anim("fx_cast", pos, 0.5, g.PX * (1.3 if i == 2 else 1.0), true)
	g._shake(0.5 if i == 1 else 0.8)
	g.flash = maxf(g.flash, 0.25)
	var c: Color = Color(0.45, 0.8, 1.0) if i == 1 else UI.PURPLE
	g.fx.append({"kind": "ring", "pos": pos, "r": 160.0, "life": 0.5, "max": 0.5, "col": c})
	g.fx.append({"kind": "ring", "pos": pos, "r": 260.0, "life": 0.7, "max": 0.7, "col": c})
	g.fx.append({"kind": "rays", "pos": pos, "life": 0.6, "max": 0.6, "col": c})
	g._sparks(pos + Vector2(0, -20), Vector2.ZERO, c, 24, 360.0)
	for j in g._query(pos, 140.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.boss and not e.chest:
			e.kb += (e.pos - pos).normalized() * 420.0


func _spawn_tentacle(target: Dictionary, dmg: float, stun: float) -> void:
	var p: Vector2 = target.pos
	g._hit("触手")
	g._damage(target, dmg)
	if not target.dead:
		target.stun = max(target.stun, stun if stun > 0.0 else 0.25)
	# 触手表现：地面裂隙 → 触手破土 → 冲击环；再从水月脚下连一道触须线到目标
	g.fx.append({"kind": "rift", "pos": p, "r": 26.0, "life": 0.25, "max": 0.25})
	var tl: float = 0.4 if g.tex.get("fx_tentacle_strike") != null else 0.6
	g.fx.append({"kind": "tentacle", "pos": p, "life": tl, "max": tl, "flip": g.rng.randf() < 0.5})
	g._fx_sprite("fx_tentacle_grab", p + Vector2(0, -target.r * 0.6), g.PX * clampf(target.r / 12.0, 1.0, 2.0), g.rng.randf() * TAU)
	g.fx.append({"kind": "tendril", "a": pos + Vector2(0, 6), "b": p + Vector2(0, 6), "life": 0.32, "max": 0.32, "seed": randf() * 10.0})
	g.fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 34.0, "life": 0.3, "max": 0.3, "col": Color(0.8, 0.45, 1.0)})
	Sfx.play("tentacle", -4.0)
	g._sparks(p + Vector2(0, 8), Vector2.UP, Color(0.75, 0.5, 1.0), 7, 200.0)


## 技能的地面表现（在角色之下）
func _draw_skill_floor() -> void:
	var base_p = pos + Vector2(0, 6)
	# 灯火照亮范围（光中敌人受伤 +25%）
	var lr = g._lamp_r()
	g.draw_set_transform(base_p, 0.0, Vector2(1.0, 0.5))
	for q in 32:
		if q % 2 == 0:
			g.draw_arc(Vector2.ZERO, lr, TAU * q / 32.0 + g.t * 0.1, TAU * (q + 1) / 32.0 + g.t * 0.1, 3, Color(1.6, 1.3, 0.8, 0.22), 1.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s3_active > 0.0:
		# 镜花水月：脚下的镜面水域 + 涟漪
		var r: float = 110.0
		var fade := clampf(s3_active / 1.0, 0.0, 1.0) * clampf((S3_DUR - s3_active) / 0.4, 0.0, 1.0)
		g.draw_set_transform(base_p, 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, r, Color(0.5, 0.35, 1.0, 0.13 * fade))
		for q in 3:
			var rp := fmod(g.t * 0.6 + q / 3.0, 1.0)
			g.draw_arc(Vector2.ZERO, r * rp, 0.0, TAU, 48, Color(1.4, 1.0, 2.2, (1.0 - rp) * 0.55 * fade), 2.0)
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.2, 0.9, 2.0, 0.7 * fade), 2.5)
		for q in 12:
			var dv := Vector2.from_angle(q * TAU / 12.0 - g.t * 0.4)
			g.draw_line(dv * (r - 10.0), dv * r, Color(1.4, 1.1, 2.2, 0.8 * fade), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s2_active > 0.0:
		var fade2 := clampf(s2_active / 1.0, 0.0, 1.0)
		g.draw_set_transform(base_p, 0.0, Vector2(1.0, 0.45))
		g.draw_arc(Vector2.ZERO, 58.0, 0.0, TAU, 40, Color(0.6, 1.1, 1.8, 0.6 * fade2), 2.0)
		g.draw_arc(Vector2.ZERO, 66.0, g.t * 3.0, g.t * 3.0 + PI, 24, Color(0.6, 1.1, 1.8, 0.4 * fade2), 3.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s1_charges > 0:
		# 唤醒蓄满：脚下金色光环
		g.draw_set_transform(base_p, 0.0, Vector2(1.0, 0.45))
		g.draw_arc(Vector2.ZERO, 34.0 + 3.0 * sin(g.t * 8.0), 0.0, TAU, 32, Color(2.0, 1.5, 0.6, 0.7), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 技能的覆盖层表现（在角色之上）
func _draw_skill_over() -> void:
	if s2_active > 0.0:
		# 囚徒困境：环绕的锁链
		var fade2 := clampf(s2_active / 1.0, 0.0, 1.0)
		for q in 10:
			var an = g.t * 2.6 + q * TAU / 10.0
			var p = pos + Vector2(cos(an) * 46.0, sin(an) * 20.0 - 26.0)
			var front := sin(an) > 0.0
			UI.diamond(g, p, 4.5 if front else 3.5, Color(0.02, 0.05, 0.08, fade2), Color(0.7, 1.3, 2.0, fade2 * (1.0 if front else 0.5)))
		# 被束缚的敌人：锁环
		for j in g._query(pos, 320.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.stun < 0.15:
				continue
			for q in 3:
				var an2: float = g.t * 4.0 + q * TAU / 3.0 + e.id
				UI.diamond(g, e.pos + Vector2(cos(an2) * (e.r + 6.0), sin(an2) * (e.r + 6.0) * 0.4 - 4.0), 3.0, Color(0.02, 0.05, 0.08, 0.9), Color(0.6, 1.2, 2.0, 0.9))
	if s3_active > 0.0:
		# 镜花水月：环绕的镜片
		for q in 6:
			var an = -g.t * 1.4 + q * TAU / 6.0
			var p = pos + Vector2(cos(an) * 64.0, sin(an) * 26.0 - 30.0 + sin(g.t * 3.0 + q) * 4.0)
			var w := 5.0 + 3.0 * absf(cos(g.t * 2.0 + q))
			g.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(w, 0), p + Vector2(0, 12), p + Vector2(-w, 0)]),
				Color(1.3, 1.0, 2.2, 0.75))
			g.draw_line(p + Vector2(0, -12), p + Vector2(0, 12), Color(2.5, 2.2, 3.0, 0.9), 1.0)


## 水月专属属性（带 mizuki_ 前缀）
func stat_defs() -> Dictionary:
	return StatDefs.MIZUKI


## 属性块 → 缓存变量（战斗代码读缓存，避免每帧查表）
func sync_stats(st) -> void:
	u_dmg_mult = st.value(&"mizuki_umbrella_dmg")
	u_area_mult = st.value(&"mizuki_umbrella_area")
	u_spd_mult = st.value(&"mizuki_umbrella_interval")
	rib_bonus = st.value(&"mizuki_umbrella_arc")
	t_mult = st.value(&"mizuki_tentacle_mult")
	extra_targets = int(st.value(&"mizuki_tentacle_targets")) - 1


func _draw_tentacle(f: Dictionary) -> void:
	var a: float = 1.0 - f.life / f.max
	# 底部紫色辉光，让触手在暗处也能看清
	g.draw_set_transform(f.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	g.draw_circle(Vector2.ZERO, 22.0, Color(0.9, 0.4, 1.6, 0.35 * (1.0 - a)))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.tex.get("fx_tentacle_strike") != null:
		# V7：32×48 × 6 帧，脚底锚点 (16,46)；第 3 帧（命中）略提亮
		var fr := clampi(int(a * 6.0), 0, 5)
		var col := Color(1.35, 1.25, 1.5) if fr == 3 else Color.WHITE
		g._spr("fx_tentacle_strike", 6, fr, f.pos + Vector2(0, 10), g.PX * 1.25, f.flip, col, Vector2(0.5, 46.0 / 48.0))
		return
	var fr := clampi(int(a * 5.0 / 0.75), 0, 4)
	var sc = g.PX * 1.7
	g._spr("tentacle", 5, fr, f.pos + Vector2(0, 10), sc, f.flip, tentacle_col(1.35) if a < 0.3 else tentacle_col(), Vector2(0.5, 1.0))


## 角色脚下的光环（缺帧条时的程序版）
func draw_auras() -> void:
	if s2_active > 0.0 and g.tex.get("fx_s2_aura") == null:
		g.draw_arc(pos + Vector2(0, -10), 30.0 + sin(g.t * 6.0) * 2.0, 0.0, TAU, 20, Color(0.5, 0.8, 1.0, 0.6), 2.0)
	if s3_active > 0.0 and g.tex.get("fx_s3_aura") == null:
		g.draw_arc(pos + Vector2(0, -10), 40.0 + sin(g.t * 4.0) * 3.0, 0.0, TAU, 24, Color(0.8, 0.55, 1.0, 0.7), 3.0)
		g.draw_circle(pos + Vector2(0, -10), 36.0, Color(0.6, 0.4, 1.0, 0.08))


## 地面层专属实体：触手追击、技能地面表现、残影与镜像分身
func draw_entities_floor() -> void:
	for f in g.fx:
		if f.kind == "tentacle":
			_draw_tentacle(f)
	_draw_skill_floor()
	for i in range(afterimg.size() - 1, -1, -1):
		var ai: Dictionary = afterimg[i]
		var aa: float = 0.45 * (1.0 - float(i) / afterimg.size())
		draw_body_at(ai.pos, ai.flip, Color(0.9, 0.55, 1.8, aa), {"tex": ai.tex, "frame": ai.frame, "hf": ai.hf, "flip": ai.flip})
	if s3_active > 0.0:
		var ma: float = minf(1.0, s3_active * 3.0) * (0.62 + 0.08 * sin(g.t * 6.0))
		draw_body_at(mirror_pos, mirror_face < 0.0, Color(0.85, 0.6, 1.9, ma))


## 加法发光层：技能光环 + 受控标记
func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	if s2_active > 0.0 and g.tex.get("fx_s2_aura") != null:
		g._spr_on(ci, "fx_s2_aura", g.FXF.fx_s2_aura, loop, pos + Vector2(0, 4))
	if s3_active > 0.0 and g.tex.get("fx_s3_aura") != null:
		g._spr_on(ci, "fx_s3_aura", g.FXF.fx_s3_aura, loop, pos + Vector2(0, 4))
	var mark := "fx_s2_bind" if s2_active > 0.0 else "fx_stun"
	if g.tex.get(mark) != null:
		for e in g.enemies:
			if e.stun > 0.3:
				g._spr_on(ci, mark, g.FXF[mark], loop + e.id, e.pos + Vector2(0, -e.r - 10))


## 状态栏条目：[文字, 颜色, 进度 0..1 或 -1]
func status_items() -> Array:
	var items: Array = []
	if s1_charges > 0:
		items.append(["唤醒 ×%d" % s1_charges, UI.GOLD, -1.0])
	if s2_active > 0.0:
		items.append(["囚徒困境", Color(0.45, 0.8, 1.0), s2_active / S2_DUR])
	if s3_active > 0.0:
		items.append(["镜花水月", UI.PURPLE, s3_active / S3_DUR])
	return items


## 属性面板：角色专属数值行
func stats_rows() -> Array:
	var interval: float = base("swing_interval", 0.9) * u_spd_mult / stat(&"op_aspd")
	var half: float = minf(180.0, 75.0 + rib_bonus)
	return [
		["伞击伤害", "%d" % int(base("umbrella_dmg", 18.0) * u_dmg_mult * g.dmg_mult)], ["全局伤害", "×%.2f" % g.dmg_mult], ["挥伞间隔", "%.2f 秒" % max(0.18, interval)],
		["挥砍半径", "%d" % int(base("swing_radius", 95.0) * u_area_mult)], ["挥砍角度", "%d°" % int(half * 2.0)], ["触手倍率", "×%.2f" % t_mult],
		["追击目标", "%d" % (1 + extra_targets)], ["技力回复", "×%.2f" % g.sp_mult],
	]


## 击杀钩子：天赋二「反移情」按预算回血（精一解锁）
func on_kill(_e: Dictionary) -> void:
	if elite >= 1:
		var got: float = min(0.01, heal_budget)
		heal_budget -= got
		g._heal(g.max_hp * got)


## 触手颜色：常态蓝色，海嗣化后紫色
func tentacle_col(bright := 1.0) -> Color:
	if rej.is_empty():
		return Color(0.62 * bright, 0.9 * bright, 1.35 * bright)
	return Color(1.25 * bright, 0.7 * bright, 1.6 * bright)
