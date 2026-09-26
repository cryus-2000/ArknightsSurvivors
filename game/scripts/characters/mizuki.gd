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
# ---- 可见成长（docs/25 §5：只长触手，原作依据「创伤性癔症」触手追击 / S3 苍白触手铺开）
var awaken_burst := false        # N4「唤醒 · 涌」：唤醒一击额外钻出 2 根触手
var bind_drag := false           # N5「囚徒 · 缚」：囚徒困境期间触手把目标拖向水月
var stake_on := false            # 精二：触手命中后留在原地继续抽打（触手桩）
var stakes: Array = []           # {pos, t, tick, dmg, flip}
const STAKE_LIFE := 1.5
const STAKE_EVERY := 0.5
const STAKE_R := 60.0
const STAKE_MAX := 6


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
	for j in query_ids(pos, 160.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.hp < e.maxhp * 0.5 and e.pos.distance_to(pos) < 160.0:
			return true
	return false


## 成长节点（data/characters/mizuki.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"tentacle_a", "tentacle_b":
			g.stats.add(&"mizuki_tentacle_targets", "flat", 1.0, "prog:%s:%s" % [id, nid], "op:" + id)
			refresh_stats()
		"awaken_burst":
			awaken_burst = true
		"bind_drag":
			bind_drag = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		stake_on = true


func _update_stakes(dt: float) -> void:
	for s in stakes:
		s.t -= dt
		s.tick -= dt
		if s.tick <= 0.0 and s.t > 0.0:
			s.tick = STAKE_EVERY
			var any := false
			for j in query_ids(s.pos, STAKE_R + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(s.pos) > STAKE_R + e.r:
					continue
				any = true
				log_hit("触手")
				deal_damage(e, s.dmg)
			if any:
				spawn_fx_sprite("fx_mizuki_tentacle", s.pos + Vector2(0, 10), g.PX * 0.85, 0.0, s.flip, true, deep_col())
				s.flip = not s.flip
	stakes = stakes.filter(func(s): return s.t > 0.0)


func update(dt: float) -> void:
	heal_budget = min(heal_budget + dt * 0.05, 0.05)
	_update_stakes(dt)
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
				float_text(pos + Vector2(0, -80), "唤醒", UI.GOLD, 15)
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
		var targets = nearest_enemies(1, radius + 60.0, pos)
		if targets.size() > 0:
			# 藏品加速（极速之手 / 国王的新枪 / 投币玩具）已由 relic_fx 写进全队的 op_aspd，不再单独乘
			var interval: float = base("swing_interval", 0.9) * u_spd_mult / stat(&"op_aspd") * (1.5 if g.atk_slow > 0.0 else 1.0)
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
		for e in arc_targets(pos, d, half, radius):
			if not seen.has(e.id):
				seen[e.id] = true
				hit.append(e)
	# 镜花水月（原作：一大片苍白触手铺开）：每次挥伞在主方向前方铺开一片触手群
	if s3_active > 0.0:
		spawn_fx_sprite("fx_mizuki_tentacle_mass", pos + Vector2.from_angle(ang) * radius * 0.55 + Vector2(0, 12), g.PX * 0.9, 0.0, cos(ang) < 0.0, true, deep_col())
	g.crit_hit = empowered
	dmg *= g.rfx.single_hit_mult(hit.size())
	for e in hit:
		log_hit("伞击", ["empowered"] if empowered else [])
		deal_damage(e, dmg)
		if not e.boss:
			e.kb += (e.pos - pos).normalized() * (360.0 if empowered else 240.0)
		if s3_active > 0.0 and not e.dead:
			e.stun = maxf(e.stun, S3_STUN)
	g.crit_hit = false
	if empowered:
		Sfx.play("swing_heavy", -3.0)
	else:
		Sfx.op(id, "atk", 3.0)
	if hit.size() > 0:
		Sfx.op(id, "hit", 8.0 if empowered else 4.0, 0.85 if empowered else 1.0)
		g.hitstop = max(g.hitstop, 0.09 if empowered else 0.03)
		for k in min(hit.size(), 6):
			var he: Dictionary = hit[k]
			sparks(he.pos, he.pos - pos, UI.GOLD if empowered else Color(0.85, 0.97, 1.0), 4 if empowered else 3, 260.0)

	# 天赋「创伤性癔症」：触手追击命中目标中生命最低的敌人
	var alive := hit.filter(func(e): return not e.dead)
	alive.sort_custom(func(a, b): return a.hp < b.hp)
	var n: int = 1 + extra_targets   # 藏品重做（docs/35）后不再有「触手目标数」藏品
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
	# 「唤醒 · 涌」：强化一击时，身边再钻出 2 根触手打附近的敌人
	if empowered and awaken_burst:
		var near: Array = nearest_enemies(2, radius * 1.6, pos)
		for ne in near:
			if not ne.dead:
				_spawn_tentacle(ne, tdmg, 0.4)
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
	var slash_tex = slash_tex_name("awaken" if empowered else ("mirage" if s3_active > 0.0 else "base"))
	if slash_tex.begins_with("fx_umbrella_slash"):
		slash_col = Color(1.15, 1.15, 1.15)
	if empowered and alive.size() > 0:
		play_anim_fx("fx_s1_burst", alive[0].pos, 0.35)
	for k in min(hit.size(), 3):
		enemy_hit_fx(hit[k], hit[k].pos - pos)
	for d in dirs:
		slash_fx(pos, d, half, radius, slash_col, slash_tex, 0.26 if empowered else 0.22)
	if empowered and not slash_tex.begins_with("fx_umbrella_slash"):
		slash_fx(pos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)


## 延时攻击的执行
func _run_delayed(dl: Dictionary) -> void:
	match dl.kind:
		"burst":
			# 创伤扩散：目标处的范围冲击
			for j in query_ids(dl.pos, dl.r):
				var e: Dictionary = g.enemies[j]
				if not e.dead and e.pos.distance_to(dl.pos) < dl.r + e.r:
					log_hit("技能·法术")
					deal_damage(e, dl.dmg)
					if not e.boss:
						e.kb += (e.pos - dl.pos).normalized() * 200.0
			g.fx.append({"kind": "burst", "pos": dl.pos, "r": dl.r, "life": 0.4, "max": 0.4, "col": UI.GOLD})
			sparks(dl.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 10, 280.0)
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
				for e in arc_targets(mp, d, dl.half, dl.radius):
					if seen.has(e.id):
						continue
					seen[e.id] = true
					log_hit("技能", ["echo"])
					deal_damage(e, dl.dmg)
					if not e.dead:
						e.stun = maxf(e.stun, S3_STUN * 0.5)
				slash_fx(mp, d, dl.half, dl.radius, Color(1.0, 0.9, 1.2, 0.8) if slash_tex_name("mirage").begins_with("fx_") else Color(0.9, 0.6, 1.6, 0.8), slash_tex_name("mirage"), 0.3)
			mirror_face = -1.0 if cos(ma) < 0.0 else 1.0
			Sfx.op(id, "atk", 0.0, 0.8)


## 技能发动：光环爆发 + 震屏 + 推开身边小怪
func _skill_cast(i: int) -> void:
	# 发动音由 spend_sp 统一播放（op_mizuki_s2 / s3）
	play_anim_fx("fx_cast", pos, 0.5, g.PX * (1.3 if i == 2 else 1.0), true)
	screen_shake(0.5 if i == 1 else 0.8)
	g.flash = maxf(g.flash, 0.25)
	var c: Color = Color(0.45, 0.8, 1.0) if i == 1 else UI.PURPLE
	g.fx.append({"kind": "ring", "pos": pos, "r": 160.0, "life": 0.5, "max": 0.5, "col": c})
	g.fx.append({"kind": "ring", "pos": pos, "r": 260.0, "life": 0.7, "max": 0.7, "col": c})
	g.fx.append({"kind": "rays", "pos": pos, "life": 0.6, "max": 0.6, "col": c})
	sparks(pos + Vector2(0, -20), Vector2.ZERO, c, 24, 360.0)
	for j in query_ids(pos, 140.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.boss and not e.chest:
			e.kb += (e.pos - pos).normalized() * 420.0


func _spawn_tentacle(target: Dictionary, dmg: float, stun: float) -> void:
	var p: Vector2 = target.pos
	log_hit("触手")
	deal_damage(target, dmg)
	if not target.dead:
		target.stun = max(target.stun, stun if stun > 0.0 else 0.25)
		# 「囚徒 · 缚」：囚徒困境期间，触手把被束缚的敌人拖向水月
		if bind_drag and s2_active > 0.0 and not target.boss:
			target.kb += (pos - target.pos).normalized() * (160.0 if target.elite else 320.0)
	# 精二：触手留在原地继续抽打（最多 6 根，旧的先消失）
	if stake_on:
		if stakes.size() >= STAKE_MAX:
			stakes.pop_front()
		stakes.append({"pos": p, "t": STAKE_LIFE, "tick": STAKE_EVERY, "dmg": dmg * 0.4, "flip": g.rng.randf() < 0.5})
	# 触手表现：地面裂隙 → 触手破土 → 冲击环；再从水月脚下连一道触须线到目标
	g.fx.append({"kind": "rift", "pos": p, "r": 26.0, "life": 0.25, "max": 0.25})
	# Codex 苍白水母触手（原作水月：海月水母触手，根部在底）；缺图退回旧触手帧条
	if not spawn_fx_sprite("fx_mizuki_tentacle", p + Vector2(0, 10), g.PX, 0.0, g.rng.randf() < 0.5, true, deep_col()):
		var tl: float = 0.4 if g.tex.get("fx_tentacle_strike") != null else 0.6
		g.fx.append({"kind": "tentacle", "pos": p, "life": tl, "max": tl, "flip": g.rng.randf() < 0.5})
	spawn_fx_sprite("fx_tentacle_grab", p + Vector2(0, -target.r * 0.6), g.PX * clampf(target.r / 12.0, 1.0, 2.0), g.rng.randf() * TAU, false, false, deep_col(1.4))
	g.fx.append({"kind": "tendril", "a": pos + Vector2(0, 6), "b": p + Vector2(0, 6), "life": 0.32, "max": 0.32, "seed": randf() * 10.0})
	g.fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 34.0, "life": 0.3, "max": 0.3, "col": deep_col(1.6)})
	Sfx.play("tentacle", -4.0)
	sparks(p + Vector2(0, 8), Vector2.UP, deep_col(1.5), 7, 200.0)


## 技能的地面表现（在角色之下）
func _draw_skill_floor() -> void:
	var base_p = pos + Vector2(0, 6)
	# 灯火照亮范围（光中敌人受伤 +25%）
	var lr = lamp_radius()
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
## 常驻的苍白小水母（原作：水月是海月水母）：数量 = 触手追击数，一眼看出触手长到了几根。
## 每只是半透明伞盖 + 三缕垂下的触须，在水月身后上方缓慢漂浮；精二后多一圈淡紫光。
func _draw_jellies() -> void:
	var n: int = 1 + extra_targets
	var c: Color = tentacle_col()
	for k in n:
		# 围着水月的腰身一圈排开（身前身后都有），比无人机低，不会被挡住
		var ang: float = g.t * 0.6 + k * TAU / float(n)
		var ph: float = g.t * 1.3 + k * 2.1
		var p: Vector2 = pos + Vector2(cos(ang) * 34.0, -34.0 + sin(ang) * 12.0 + sin(ph * 1.7) * 3.0)
		if stake_on:
			g.draw_circle(p, 13.0, Color(0.9, 0.6, 1.6, 0.16))
		# Codex 帧条 fx_mizuki_jelly（12×16 × 4 帧，6fps 循环，中心锚点）；每只错开相位
		if _fx_strip("fx_mizuki_jelly", 4, int(g.t * 6.0) + k * 3, p + Vector2(0, 6)):
			continue
		# 伞盖
		g.draw_set_transform(p, 0.0, Vector2(1.0, 0.62))
		g.draw_circle(Vector2.ZERO, 8.5, Color(c.r, c.g, c.b, 0.6))
		g.draw_arc(Vector2.ZERO, 8.5, PI, TAU, 14, Color(1.7, 1.9, 2.3, 0.9), 1.6)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 触须
		for q in 3:
			var x0: float = (q - 1) * 4.0
			var pts := PackedVector2Array()
			for s in 5:
				pts.append(p + Vector2(x0 + sin(ph * 2.0 + s * 0.9 + q) * (1.0 + s * 0.9), 3.0 + s * 4.5))
			g.draw_polyline(pts, Color(c.r, c.g, c.b, 0.65 - q * 0.08), 1.5)


## 可选帧条：首次用到时 A.tex 懒加载并缓存进 g.tex（缺图缓存 null）
func _fx_tex(name: String) -> Texture2D:
	if not g.tex.has(name):
		g.tex[name] = A.tex(name)
	return g.tex[name]


## 帧条贴图（有图画图、缺图返回 false 走程序版）；1 美术像素 = PX 世界像素，@2x 高清帧条按 A.hires_of 半倍画；anchor 为帧内比例锚点
func _fx_strip(name: String, frames: int, frame: int, p: Vector2, anchor := Vector2(0.5, 0.5), ang := 0.0, col := Color.WHITE, flip := false) -> bool:
	var tx: Texture2D = _fx_tex(name)
	if tx == null:
		return false
	var fw: float = float(tx.get_width() / frames)
	var fh: float = float(tx.get_height())
	var k: float = g.PX / A.hires_of(tx)
	g.draw_set_transform(p.round(), ang, Vector2(-k if flip else k, k))
	g.draw_texture_rect_region(tx, Rect2(-Vector2(fw, fh) * anchor, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


func _draw_skill_over() -> void:
	_draw_jellies()
	if s2_active > 0.0:
		# 囚徒困境：环绕的锁链
		var fade2 := clampf(s2_active / 1.0, 0.0, 1.0)
		for q in 10:
			var an = g.t * 2.6 + q * TAU / 10.0
			var p = pos + Vector2(cos(an) * 46.0, sin(an) * 20.0 - 26.0)
			var front := sin(an) > 0.0
			UI.diamond(g, p, 4.5 if front else 3.5, Color(0.02, 0.05, 0.08, fade2), Color(0.7, 1.3, 2.0, fade2 * (1.0 if front else 0.5)))
		# 被束缚的敌人：锁环
		for j in query_ids(pos, 320.0):
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
	# 成长节点写在 op:mizuki 作用域，必须按本干员作用域读（之前读全局值，节点加成不生效）
	var sc := scopes()
	u_dmg_mult = st.value_for(&"mizuki_umbrella_dmg", sc)
	u_area_mult = st.value_for(&"mizuki_umbrella_area", sc)
	u_spd_mult = st.value_for(&"mizuki_umbrella_interval", sc)
	rib_bonus = st.value_for(&"mizuki_umbrella_arc", sc)
	t_mult = st.value_for(&"mizuki_tentacle_mult", sc)
	extra_targets = int(st.value_for(&"mizuki_tentacle_targets", sc)) - 1


func _draw_tentacle(f: Dictionary) -> void:
	var a: float = 1.0 - f.life / f.max
	# 底部紫色辉光，让触手在暗处也能看清
	g.draw_set_transform(f.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	var gc: Color = deep_col(1.4)
	g.draw_circle(Vector2.ZERO, 22.0, Color(gc.r, gc.g, gc.b, 0.35 * (1.0 - a)))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.tex.get("fx_tentacle_strike") != null:
		# V7：32×48 × 6 帧，脚底锚点 (16,46)；第 3 帧（命中）略提亮
		var fr := clampi(int(a * 6.0), 0, 5)
		var col := deep_col(1.3 if fr == 3 else 1.0)
		draw_spr("fx_tentacle_strike", 6, fr, f.pos + Vector2(0, 10), g.PX * 1.25, f.flip, col, Vector2(0.5, 46.0 / 48.0))
		return
	var fr := clampi(int(a * 5.0 / 0.75), 0, 4)
	var sc = g.PX * 1.7
	draw_spr("tentacle", 5, fr, f.pos + Vector2(0, 10), sc, f.flip, deep_col(1.35) if a < 0.3 else deep_col(), Vector2(0.5, 1.0))


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
	# 触手桩：地面一圈淡紫水痕 + 裂隙，随剩余时间淡出
	for s in stakes:
		var a: float = clampf(s.t / 0.4, 0.0, 1.0)
		g.draw_set_transform(s.pos + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, STAKE_R * 0.8, Color(0.55, 0.4, 0.85, 0.12 * a))
		g.draw_arc(Vector2.ZERO, STAKE_R * 0.8, 0.0, TAU, 24, Color(0.85, 0.7, 1.2, 0.45 * a), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
		draw_spr_on(ci, "fx_s2_aura", g.FXF.fx_s2_aura, loop, pos + Vector2(0, 4))
	if s3_active > 0.0 and g.tex.get("fx_s3_aura") != null:
		draw_spr_on(ci, "fx_s3_aura", g.FXF.fx_s3_aura, loop, pos + Vector2(0, 4))
	var mark := "fx_s2_bind" if s2_active > 0.0 else "fx_stun"
	if g.tex.get(mark) != null:
		for e in g.enemies:
			if e.stun > 0.3:
				draw_spr_on(ci, mark, g.FXF[mark], loop + e.id, e.pos + Vector2(0, -e.r - 10))


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
		heal_leader(g.max_hp * got, "水月")


## 触手本体的染色（2026-09-26 用户定：深蓝色）：Codex 触手图是苍白青色，乘上这个颜色就成深海蓝；
## 海嗣化（被排斥）后改成深紫。小水母 / 触须线仍用 tentacle_col 的浅色
func deep_col(bright := 1.0) -> Color:
	if rej.is_empty():
		return Color(0.22 * bright, 0.34 * bright, 0.88 * bright)
	return Color(0.62 * bright, 0.34 * bright, 1.0 * bright)


## 触手颜色：常态蓝色，海嗣化后紫色
func tentacle_col(bright := 1.0) -> Color:
	if rej.is_empty():
		return Color(0.62 * bright, 0.9 * bright, 1.35 * bright)
	return Color(1.25 * bright, 0.7 * bright, 1.6 * bright)
