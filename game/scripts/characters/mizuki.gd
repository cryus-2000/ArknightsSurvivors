## 水月（从 game.gd 拆出）：伞击、天赋「创伤性癔症」触手追击、三个技能与进阶、精英化路线（潮刃 / 群触）及其专属实体与绘制。
## 通用玩家状态（位置、生命、等级、成长计数、技能等级）仍在 game.gd，通过 g 访问；本文件只放水月专属的东西。
extends "res://scripts/characters/character.gd"

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")

const GIANT_R := 185.0
const GIANT_RISE := 0.45
const GIANT_SINK := 2.1

var swing_cd := 0.0
var u_dmg_mult := 1.0
var u_area_mult := 1.0
var u_spd_mult := 1.0
var t_mult := 0.6                # 天赋一：触手追击倍率
var rib_bonus := 0.0
var extra_targets := 0
## 排异反应（结局四）：技能进阶被替换成海嗣化版本；键 = s1a s1b s2a s2b s3a s3b fallback
var rej: Dictionary = {}
const REJ_NAMES := {"s1a": "创伤扩散 → 溃裂：冲击范围 +50%、伤害 +30%，唤醒次数 +2", "s1b": "深层唤醒 → 群唤：触手 6 条，但唤醒不再强化伞击本身",
	"s2a": "双重困境 → 环触：反向斩变成全方向触手环，囚徒困境持续 −3 秒", "s2b": "无解困境 → 侵蚀：束缚变为持续法术伤害，不再传播",
	"s3a": "镜像 → 海嗣分身：分身独立行动并吸引仇恨，最大生命 −20", "s3b": "深海 → 溟海：幻境半径 ×1.5，但水月在幻境中也减速 15%",
	"fallback": "触手追击目标 +2，但灯火照亮加成对触手无效"}
var s1_need := 7                 # 唤醒：充能所需挥伞次数
var delayed: Array = []          # 延时攻击（深层唤醒触手、倒影、连击）
var s2_combo := 0
var afterimg: Array = []         # 镜花水月残影
var afterimg_t := 0.0
var s1_count := 0
var s1_charges := 0
var s2_sp := 10.0
var s2_active := 0.0
var s3_sp := 30.0
var s3_active := 0.0
var mirror_pos := Vector2.ZERO    # S3 镜像分身位置
var clone_t := 0.0                # 海嗣分身自主挥伞计时（排异）
var mirror_face := 1.0
var s3_pen_cd := 0.0
var heal_budget := 0.0           # 反移情击杀回复：每秒上限
var talent2_on := false
var evo1 := ""                   # 精英化一路线：blade 潮刃 / tendril 群触
var evo2 := ""                   # 精英化二质变
var evo_pending := false
var abyss_n := 0                 # 深渊巨斩计数
var giant_cd := 5.0              # 巨触吞噬冷却
var mother_cd := 0.0
var stakes: Array = []           # 触手桩 {pos, life, max, r, tick, dmg}
var giants: Array = []           # 巨触横扫 {pos, t, dur, ang0, dir, dmg, hit}
var fields: Array = []           # 触须阵 {pos, r, life, max, tick, bind}
var field_cd := 1.0
var tide_shot_cd := 1.0


func _init(game, def_: Dictionary) -> void:
	super(game, def_)


func _swing_radius() -> float:
	var r: float = base("swing_radius", 95.0) * u_area_mult
	if s3_active > 0.0:
		r *= 1.4
	return r


func _dmg_bonus() -> float:
	var m: float = stat(&"dmg") * stat(&"op_atk")
	if talent2_on and _low_hp_enemy_near():
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
	# 技力：随时间回复；技能生效期间不回复
	var P: Dictionary = D.SKILL_P
	if g.skill_lv.s2 >= 1:
		if s2_active > 0.0:
			s2_active -= dt
		else:
			s2_sp += dt * g.sp_mult * g._lamp_sp()
			if s2_sp >= P.s2_charge:
				s2_sp = 0.0
				s2_active = P.s2_dur - (3.0 if rej.has("s2a") else 0.0)
				_skill_cast("s2")
	if g.skill_lv.s3 >= 1:
		if s3_active > 0.0:
			s3_active -= dt
			if rej.has("s3a") and g.skill_lv.s3 >= 2:
				# 海嗣分身（排异）：自己找目标、自己挥伞、吸引周围仇恨
				var tgt = g._nearest(1, 320.0, pos)
				var want: Vector2 = pos + Vector2(-face * 80.0, -10.0)
				if not tgt.is_empty():
					want = tgt[0].pos + (mirror_pos - tgt[0].pos).normalized() * 60.0
				mirror_pos = mirror_pos.lerp(want, minf(1.0, dt * 3.0))
				clone_t -= dt
				if clone_t <= 0.0:
					clone_t = 0.55
					delayed.append({"at": 0.0, "kind": "echo", "ang": facing_angle(), "dmg": 18.0 * g.u_dmg_mult * g.dmg_mult * P.s3_echo_mult,
						"half": 1.3, "radius": 95.0 * g.u_area_mult, "dirs": 1})
				for j in g._query(mirror_pos, 200.0):
					var ce: Dictionary = g.enemies[j]
					if not ce.dead and not ce.boss and ce.ai == "melee":
						ce.aggro = mirror_pos
			else:
				mirror_pos = mirror_pos.lerp(pos + Vector2(-face * 80.0, -10.0), minf(1.0, dt * 8.0))
			# 深海幻境：周身敌人减速
			if g.skill_lv.s3 >= 3:
				var zr: float = P.s3_zone_r * (1.5 if rej.has("s3b") else 1.0)
				for j in g._query(pos, zr):
					var ze: Dictionary = g.enemies[j]
					if not ze.dead and ze.pos.distance_to(pos) < zr:
						ze.slow = maxf(ze.slow, 0.2)
				if rej.has("s3b"):
					g.atk_slow = maxf(g.atk_slow, 0.0)
					g.rej_slow = 0.85
			else:
				g.rej_slow = 1.0
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
			s3_sp += dt * g.sp_mult * g._lamp_sp()
			if s3_sp >= P.s3_charge:
				s3_sp = 0.0
				s3_active = P.s3_dur
				mirror_pos = pos
				_skill_cast("s3")
	# 延时攻击
	for i in range(delayed.size() - 1, -1, -1):
		var dl: Dictionary = delayed[i]
		dl.at -= dt
		if dl.at <= 0.0:
			delayed.remove_at(i)
			_run_delayed(dl)
	s3_pen_cd -= dt

	swing_cd -= dt
	if swing_cd <= 0.0:
		var radius := _swing_radius()
		var targets = g._nearest(1, radius + 60.0, pos)
		if targets.size() > 0:
			var interval: float = base("swing_interval", 0.9) * u_spd_mult * (1.5 if g.atk_slow > 0.0 else 1.0) * g.rfx.umbrella_interval_mult()
			if s2_active > 0.0:
				interval *= D.SKILL_P.s2_interval
			swing_cd = max(0.18, interval)
			_umbrella(targets[0])
		else:
			swing_cd = 0.1

	_update_evo_extras(dt)
	g._update_weapons(dt)


func _umbrella(target: Dictionary) -> void:
	var P: Dictionary = D.SKILL_P
	var radius := _swing_radius()
	var half := deg_to_rad(min(180.0, 75.0 + rib_bonus + 15.0 * g.growth.get("u_area", 0)))
	var ang: float = (target.pos - pos).angle()
	face_to(ang)
	attack_t = attack_dur
	var dmg: float = base("umbrella_dmg", 18.0) * u_dmg_mult * _dmg_bonus()
	if s3_active > 0.0:
		dmg *= P.s3_mult
	# S1「唤醒」：挥伞充能，满层后强化下一击
	var empowered := false
	if g.skill_lv.s1 >= 1:
		s1_count += 1
		if s1_count >= s1_need:
			s1_count = 0
			s1_charges = min(3, s1_charges + 1)
		if s1_charges > 0:
			s1_charges -= 1
			empowered = true
			if not rej.has("s1b"):
				dmg *= P.s1_mult
			radius *= P.s1_radius
	# 攻击方向：常态单方向；镜花水月三方向；深海形态全方向
	var dirs: Array = [ang]
	if s3_active > 0.0:
		if g.skill_lv.s3 >= 3:
			half = PI
		else:
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
			e.stun = maxf(e.stun, P.s3_stun)
	g.crit_hit = false
	Sfx.play("swing_heavy" if empowered else "swing", -3.0 if empowered else -7.0)
	if hit.size() > 0:
		Sfx.play("hit", -2.0 if empowered else -5.0, 0.85 if empowered else 1.0)
		g.hitstop = max(g.hitstop, 0.09 if empowered else 0.03)
		g._shake(0.6 if empowered else 0.18)
		g.cam_kick = Vector2.from_angle(ang) * (10.0 if empowered else 4.0)
		for k in min(hit.size(), 6):
			var he: Dictionary = hit[k]
			g._sparks(he.pos, he.pos - pos, UI.GOLD if empowered else Color(0.85, 0.97, 1.0), 4 if empowered else 3, 260.0)

	# 天赋「创伤性癔症」：触手追击命中目标中生命最低的敌人
	var alive := hit.filter(func(e): return not e.dead)
	alive.sort_custom(func(a, b): return a.hp < b.hp)
	var n: int = 1 + extra_targets + g.rfx.tentacle_targets_extra() + (2 if rej.has("fallback") else 0)
	if s2_active > 0.0:
		n += 1
	if s3_active > 0.0:
		n += 2 if g.skill_lv.s3 >= 3 else 1
	var tdmg: float = dmg * t_mult * (P.s1_mult if (empowered and rej.has("s1b")) else 1.0)
	var stun := 0.0
	if s3_active > 0.0:
		stun = 1.0
	elif s2_active > 0.0:
		stun = P.s2_bind
	for i in min(n, alive.size()):
		_spawn_tentacle(alive[i], tdmg, stun)
	if g.grip:
		for e in alive:
			if not e.dead and g.rng.randf() < 0.2:
				_spawn_tentacle(e, tdmg * 0.6, 0.0)

	# ---- S1 进阶
	if empowered and hit.size() > 0:
		var ip: Vector2 = hit[0].pos
		g.fx.append({"kind": "impact", "pos": ip, "ang": ang, "life": 0.35, "max": 0.35, "col": UI.GOLD})
		g.fx.append({"kind": "ring", "pos": ip, "r": 70.0, "life": 0.3, "max": 0.3, "col": UI.GOLD})
		g.flash = maxf(g.flash, 0.12)
		if g.skill_lv.s1 >= 2:
			for k in mini(hit.size(), P.s1_burst_max):
				delayed.append({"at": 0.06 * k, "kind": "burst", "pos": hit[k].pos, "dmg": dmg * P.s1_burst_mult * (1.3 if rej.has("s1a") else 1.0), "r": P.s1_burst_r * (1.5 if rej.has("s1a") else 1.0), "arts": true})
		if g.skill_lv.s1 >= 3:
			var tg = g._nearest(P.s1_deep_n + (2 if rej.has("s1b") else 0), P.s1_deep_range)
			for k in tg.size():
				delayed.append({"at": 0.12 + 0.07 * k, "kind": "deep", "target": tg[k], "dmg": dmg * P.s1_deep_mult})
	# ---- S2 进阶
	if s2_active > 0.0:
		if g.skill_lv.s2 >= 2 and rej.has("s2a"):
			# 环触（排异）：全方向触手环
			var ring = g._nearest(6, radius + 40.0, pos)
			for k in ring.size():
				delayed.append({"at": 0.04 * k, "kind": "combo", "target": ring[k], "dmg": tdmg * 0.7})
		elif g.skill_lv.s2 >= 2:
			# 双重困境：斩向另一方向最近的敌人
			var best: Dictionary = {}
			var bd := INF
			for j in g._query(pos, radius + 60.0):
				var e2: Dictionary = g.enemies[j]
				if e2.dead or seen.has(e2.id):
					continue
				var o2: Vector2 = e2.pos - pos
				if abs(angle_difference(ang, o2.angle())) < 1.05:
					continue
				var dd := o2.length()
				if dd < bd and dd < radius + 60.0:
					bd = dd
					best = e2
			if not best.is_empty():
				var a2: float = (best.pos - pos).angle()
				for e in g._arc_hit(pos, a2, half * 0.8, radius):
					if not seen.has(e.id):
						g._hit("技能")
						g._damage(e, dmg * P.s2_twin_mult)
						if not e.dead:
							e.stun = maxf(e.stun, 0.3)
				g._slash_fx(pos, a2, half * 0.8, radius, Color(0.8, 1.1, 1.4) if g._slash_tex().begins_with("fx_") else Color(0.5, 0.85, 1.4), g._slash_tex(), 0.18)
		if g.skill_lv.s2 >= 3:
			s2_combo += 1
			if s2_combo >= P.s2_combo_every:
				s2_combo = 0
				var tg2 = g._nearest(8, 220.0, pos)
				tg2.shuffle()
				for k in mini(P.s2_combo_n, tg2.size()):
					delayed.append({"at": 0.05 + 0.07 * k, "kind": "combo", "target": tg2[k], "dmg": tdmg * 0.8})
	# ---- S3 进阶：倒影
	if s3_active > 0.0 and g.skill_lv.s3 >= 2:
		delayed.append({"at": P.s3_echo_delay, "kind": "echo", "ang": ang, "dmg": dmg * P.s3_echo_mult,
			"half": half, "radius": radius, "dirs": dirs.size()})

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
		# 唤醒（旧素材）：外圈再叠一层更大的金色斩痕
		g._slash_fx(pos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)
	_evo_on_swing(ang, dmg)


## ---- 进化：潮刃（水刃）与群触（触手桩）
func _evo_on_swing(ang: float, dmg: float) -> void:
	if evo1 == "blade":
		var n := 1 + int(g.growth.get("b_count", 0)) + (1 if evo2 == "blade_moon" else 0)
		var size: float = (1.0 + 0.25 * g.growth.get("b_size", 0)) * (1.3 if evo2 == "blade_abyss" else 1.0)
		var wd: float = dmg * 1.0 * (1.0 + 0.3 * g.growth.get("b_dmg", 0))
		var rng_: float = 380.0 * (1.0 + 0.3 * g.growth.get("b_range", 0))
		for k in n:
			var a := ang + (k - (n - 1) / 2.0) * 0.28
			_fire_wave(a, wd, size, rng_, evo2 == "blade_moon", false)
		if evo2 == "blade_abyss":
			abyss_n += 1
			if abyss_n >= 4:
				abyss_n = 0
				_fire_wave(ang, wd * 3.0, size * 3.0, rng_ * 1.2, false, true)
				g._shake(0.6)
				Sfx.play("swing_heavy", -2.0, 0.6, 0.0)
	elif evo1 == "tendril":
		var n := 1 + int(g.growth.get("t_count", 0)) + (2 if evo2 == "tendril_mother" else 0) + (1 if evo2 == "tendril_giant" else 0)
		var pool = g._nearest(14, 270.0, pos)
		pool.shuffle()
		for k in mini(n, pool.size()):
			delayed.append({"at": 0.05 + 0.06 * k, "kind": "summon", "target": pool[k], "dmg": dmg * 0.6 * (1.0 + 0.3 * g.growth.get("t_power", 0))})


func _fire_wave(ang: float, dmg: float, size: float, dist: float, moon: bool, giant: bool) -> void:
	var spd := 560.0 if not giant else 420.0
	var life := dist / spd
	g.bullets.append({"kind": "wave", "pos": pos + Vector2(0, -18) + Vector2.from_angle(ang) * 20.0, "vel": Vector2.from_angle(ang) * spd,
		"dmg": dmg, "life": life * (2.0 if moon else 1.0), "max": life * (2.0 if moon else 1.0), "r": 20.0 * size, "size": size,
		"aoe": 0.0, "hit": {}, "moon": moon, "ret": false, "giant": giant})
	if not giant:
		Sfx.play("swing", -14.0, 1.6, 0.1)


## 触手桩：原地停留，定期鞭打范围内最近的敌人
func _add_stake(p: Vector2, dmg: float) -> void:
	if stakes.size() >= 16:
		stakes.pop_front()
	var life: float = 1.6 + 1.0 * g.growth.get("t_stake", 0)
	stakes.append({"pos": p, "life": life, "max": life, "r": 60.0 * (1.0 + 0.25 * g.growth.get("t_reach", 0)), "tick": 0.3,
		"dmg": dmg * 0.45, "flip": g.rng.randf() < 0.5, "whip": 0.0, "wt": Vector2.ZERO})


## 巨触横扫：破土 0.45s → 顺 / 逆时针扫一整圈（1.65s）→ 沉回海床；扫到的敌人受重击、晕眩并被甩开
func _update_giants(dt: float) -> void:
	for gi in giants:
		gi.t += dt
		if gi.t < GIANT_RISE or gi.t > GIANT_SINK:
			continue
		var k: float = (gi.t - GIANT_RISE) / (GIANT_SINK - GIANT_RISE)
		gi.ang = gi.ang0 + gi.dir * TAU * k
		var sweep := Vector2.from_angle(gi.ang)
		for j in g._query(gi.pos, GIANT_R + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or gi.hit.has(e.id):
				continue
			var rel: Vector2 = e.pos - gi.pos
			var dist := rel.length()
			if dist > GIANT_R + e.r or dist < 10.0:
				continue
			if absf(angle_difference(rel.angle(), gi.ang)) > 0.42:
				continue
			gi.hit[e.id] = true
			g._hit("巨触")
			g._damage(e, gi.dmg)
			if not e.dead:
				e.stun = maxf(e.stun, 0.9)
				if not e.boss:
					e.kb += (sweep.orthogonal() * gi.dir + rel.normalized() * 0.6).normalized() * 420.0
			g._sparks(e.pos, sweep.orthogonal() * gi.dir, Color(0.9, 0.6, 1.4), 4, 260.0)
		if int(gi.t * 12.0) != int((gi.t - dt) * 12.0):
			Sfx.play("tentacle", -12.0, 0.6, 0.1)
	giants = giants.filter(func(x): return x.t < x.dur)


func _draw_giant(gi: Dictionary) -> void:
	var tx: Texture2D = g.tex.get("tentacle")
	if tx == null:
		return
	# 地面阴影 + 扫过的弧
	g.draw_set_transform(gi.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	var tc: Color = tentacle_col()
	g.draw_circle(Vector2.ZERO, 46.0, Color(tc.r * 0.5, tc.g * 0.3, tc.b * 0.7, 0.35))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var rise: float = clampf(gi.t / GIANT_RISE, 0.0, 1.0)
	var sink: float = clampf((gi.t - GIANT_SINK) / (gi.dur - GIANT_SINK), 0.0, 1.0)
	var len_k: float = (1.0 - (1.0 - rise) * (1.0 - rise)) * (1.0 - sink)
	var ang: float = gi.ang if gi.t >= GIANT_RISE else gi.ang0
	if gi.t >= GIANT_RISE and gi.t <= GIANT_SINK:
		for q in 6:
			var a0: float = ang - gi.dir * (0.12 + 0.11 * q)
			var a1: float = ang - gi.dir * (0.11 * q)
			g.draw_arc(gi.pos, GIANT_R * 0.92, minf(a0, a1), maxf(a0, a1), 10, Color(tc.r, tc.g * 0.8, tc.b * 1.2, 0.55 - 0.08 * q), 26.0 - 3.0 * q)
	# V7 主体：升起（0–2 帧）→ 横扫期间保持第 3 帧 → 沉回（3–5 帧）
	var kt: Texture2D = g.tex.get("fx_kraken_rise")
	if kt != null:
		var kf := 2
		if gi.t < GIANT_RISE:
			kf = clampi(int(rise * 3.0), 0, 2)
		elif gi.t > GIANT_SINK:
			kf = clampi(3 + int(sink * 3.0), 3, 5)
		g._spr("fx_kraken_rise", 6, kf, gi.pos + Vector2(0, 12), g.PX * 1.3, gi.dir < 0.0, Color(1.15, 1.05, 1.25), Vector2(0.5, 90.0 / 96.0))
	# 触手本体：沿扫掠方向平躺，从根部长出
	var fw: int = tx.get_width() / 5
	var fh: int = tx.get_height()
	var fr: int = clampi(int(rise * 4.99), 0, 4)
	var sc_len: float = GIANT_R / float(fh) * len_k * 1.05
	var sc_w: float = g.PX * 4.6
	g.draw_set_transform(gi.pos, ang + PI / 2.0, Vector2(sc_w, sc_len))
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh), Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), tentacle_col(1.25))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _update_stakes(dt: float) -> void:
	for st in stakes:
		st.life -= dt
		st.tick -= dt
		st.whip = maxf(0.0, st.whip - dt)
		if st.tick <= 0.0:
			st.tick = 0.45
			var best: Dictionary = {}
			var bd: float = st.r
			for j in g._query(st.pos, st.r + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead:
					continue
				var d: float = e.pos.distance_to(st.pos)
				if d < bd:
					bd = d
					best = e
			if not best.is_empty():
				g._hit("触手桩")
				g._damage(best, st.dmg)
				st.whip = 0.18
				st.wt = best.pos
				if not best.boss:
					best.kb += (best.pos - st.pos).normalized() * 120.0
	stakes = stakes.filter(func(st): return st.life > 0.0)
	# 巨触吞噬：每 5 秒在敌群中心升起巨型触手
	if evo2 == "tendril_giant":
		giant_cd -= dt
		if giant_cd <= 0.0:
			var c = g._densest_point(400.0, pos)
			if c == Vector2.INF:
				giant_cd = 0.5
			else:
				giant_cd = 5.0
				g.fx.append({"kind": "rift", "pos": c, "r": 115.0, "life": 0.55, "max": 0.55})
				delayed.append({"at": 0.55, "kind": "giant", "pos": c, "dmg": (28.0 + g.level * 1.8) * g.dmg_mult * (1.0 + 0.3 * g.growth.get("t_power", 0))})
				Sfx.play("roar", -8.0, 1.6, 0.0)
	mother_cd -= dt


## 延时攻击的执行
func _run_delayed(dl: Dictionary) -> void:
	var P: Dictionary = D.SKILL_P
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
		"deep", "combo":
			var tg: Dictionary = dl.target
			if tg.dead:
				return
			_spawn_tentacle(tg, dl.dmg, P.s2_bind if dl.kind == "combo" else 0.4)
			g.fx.append({"kind": "ring", "pos": tg.pos, "r": 30.0, "life": 0.3, "max": 0.3,
				"col": UI.GOLD if dl.kind == "deep" else Color(0.45, 0.8, 1.0)})
			g.fx.append({"kind": "pillar", "pos": tg.pos, "life": 0.35, "max": 0.35,
				"col": Color(1.0, 0.8, 0.4) if dl.kind == "deep" else Color(0.5, 0.85, 1.0)})
		"summon":
			# 群触：召唤触手（命中后化为触手桩）
			var tg: Dictionary = dl.target
			if tg.dead:
				return
			var sp: Vector2 = tg.pos
			_spawn_tentacle(tg, dl.dmg, 0.35)
			_add_stake(sp, dl.dmg)
		"giant":
			# 巨触吞噬：破土后横扫一圈（见 _update_giants），先把中心的敌人拖过来
			for j in g._query(dl.pos, 135.0):
				var e: Dictionary = g.enemies[j]
				if not e.dead and not e.boss and e.pos.distance_to(dl.pos) < 115.0 + e.r:
					e.kb += (dl.pos - e.pos) * 2.0
			giants.append({"pos": dl.pos, "t": 0.0, "dur": 2.6, "ang0": g.rng.randf() * TAU, "dir": (1.0 if g.rng.randf() < 0.5 else -1.0), "dmg": dl.dmg, "hit": {}, "ang": 0.0})
			g.fx.append({"kind": "ring", "pos": dl.pos, "r": 130.0, "life": 0.5, "max": 0.5, "col": Color(0.8, 0.4, 1.0)})
			g._sparks(dl.pos, Vector2.UP, Color(0.8, 0.5, 1.0), 24, 360.0)
			g._shake(1.0)
			g.hitstop = maxf(g.hitstop, 0.06)
			Sfx.play("boom", -2.0, 0.6, 0.0)
		"echo":
			# 镜像：身后的镜像分身朝它身边的敌人同步挥伞（深海形态下三向）
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
						e.stun = maxf(e.stun, P.s3_stun * 0.5)
				g._slash_fx(mp, d, dl.half, dl.radius, Color(1.0, 0.9, 1.2, 0.8) if g._slash_tex("mirage").begins_with("fx_") else Color(0.9, 0.6, 1.6, 0.8), g._slash_tex("mirage"), 0.3)
			mirror_face = -1.0 if cos(ma) < 0.0 else 1.0
			Sfx.play("swing", -9.0, 0.7, 0.05)


## 技能发动：横幅 + 光环爆发 + 震屏
func _skill_cast(sid: String) -> void:
	g.rfx.on_skill_start()
	var sk: Dictionary = D.SKILLS[sid]
	# 技能名横幅已取消（每次释放都弹太吵）；首次获得技能仍有演示
	Sfx.play("skill", -1.0, 1.0 if sid == "s2" else 0.8, 0.0)
	g._anim("fx_cast", pos, 0.5, g.PX * (1.3 if sid == "s3" else 1.0), true)
	g._shake(0.5 if sid == "s2" else 0.8)
	g.flash = maxf(g.flash, 0.25)
	var c: Color = sk.col
	g.fx.append({"kind": "ring", "pos": pos, "r": 160.0, "life": 0.5, "max": 0.5, "col": c})
	g.fx.append({"kind": "ring", "pos": pos, "r": 260.0, "life": 0.7, "max": 0.7, "col": c})
	g.fx.append({"kind": "rays", "pos": pos, "life": 0.6, "max": 0.6, "col": c})
	g._sparks(pos + Vector2(0, -20), Vector2.ZERO, c, 24, 360.0)
	# 发动冲击：推开身边小怪
	for j in g._query(pos, 140.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.boss and not e.chest:
			e.kb += (e.pos - pos).normalized() * 420.0


func _spawn_tentacle(target: Dictionary, dmg: float, stun: float) -> void:
	var p: Vector2 = target.pos
	g._hit("触手")
	g._damage(target, dmg)
	if not target.dead:
		if rej.has("s2b") and stun > 0.3:
			# 侵蚀（排异）：束缚改为持续法术伤害
			target.stun = max(target.stun, 0.25)
			target.corr_t = stun * 2.0
			target.corr_dmg = dmg * 0.35
		else:
			target.stun = max(target.stun, stun if stun > 0.0 else 0.25)
		# 无解困境：束缚有限传播给身边 1 名敌人（不会再次传播）
		if s2_active > 0.0 and g.skill_lv.s2 >= 3 and stun > 0.0 and not rej.has("s2b"):
			var P: Dictionary = D.SKILL_P
			for j in g._query(p, P.s2_spread_r):
				var o: Dictionary = g.enemies[j]
				if o.dead or is_same(o, target) or o.boss or o.stun > 0.1:
					continue
				if o.pos.distance_to(p) < P.s2_spread_r:
					o.stun = P.s2_spread_bind
					g.fx.append({"kind": "chain", "a": p, "b": o.pos, "life": 0.3, "max": 0.3})
					break
	# 深海之母：被触手击杀的敌人会在附近唤出新的触手
	if target.dead and evo2 == "tendril_mother" and mother_cd <= 0.0:
		mother_cd = 0.15
		for j in g._query(p, 180.0):
			var o: Dictionary = g.enemies[j]
			if not o.dead and not is_same(o, target) and o.pos.distance_to(p) < 180.0:
				delayed.append({"at": 0.12, "kind": "summon", "target": o, "dmg": dmg * 0.8})
				break
	# 触手表现：地面裂隙 → 放大的触手破土 → 冲击环；再从水月脚下连一道触须线到目标
	g.fx.append({"kind": "rift", "pos": p, "r": 26.0, "life": 0.25, "max": 0.25})
	var tl: float = 0.4 if g.tex.get("fx_tentacle_strike") != null else 0.6
	g.fx.append({"kind": "tentacle", "pos": p, "life": tl, "max": tl, "flip": g.rng.randf() < 0.5})
	g._fx_sprite("fx_tentacle_grab", p + Vector2(0, -target.r * 0.6), g.PX * clampf(target.r / 12.0, 1.0, 2.0), g.rng.randf() * TAU)
	g.fx.append({"kind": "tendril", "a": pos + Vector2(0, 6), "b": p + Vector2(0, 6), "life": 0.32, "max": 0.32, "seed": randf() * 10.0})
	g.fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 34.0, "life": 0.3, "max": 0.3, "col": Color(0.8, 0.45, 1.0)})
	Sfx.play("tentacle", -4.0)
	g._sparks(p + Vector2(0, 8), Vector2.UP, Color(0.75, 0.5, 1.0), 7, 200.0)


## 水刃：穿透，每个敌人只命中一次；月轮飞到一半折返（回程可再次命中）
func _update_wave(b: Dictionary, dt: float) -> void:
	if b.moon and not b.ret and b.life < b.max * 0.5:
		b.ret = true
		b.hit = {}
	if b.ret:
		var back: Vector2 = pos + Vector2(0, -18) - b.pos
		b.vel = b.vel.lerp(back.normalized() * 620.0, clampf(dt * 6.0, 0.0, 1.0))
		if back.length() < 24.0:
			b.life = 0.0
			return
	for j in g._query(b.pos, b.r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or b.hit.has(e.id) or e.pos.distance_to(b.pos) > b.r + e.r:
			continue
		b.hit[e.id] = true
		g._hit("水刃")
		g._damage(e, b.dmg * (1.25 if b.ret else 1.0))   # 月轮回程 +25%：让月轮线与巨斩 / 群触持平
		if not e.dead:
			e.slow = maxf(e.slow, 1.0)
		if b.giant and not e.dead:
			e.stun = maxf(e.stun, 1.0)
		if not e.boss and not e.dead:
			e.kb += b.vel.normalized() * (260.0 if b.giant else 120.0)
		g._sparks(e.pos, b.vel, Color(0.7, 1.0, 1.0), 2, 180.0)
		g._fx_sprite("fx_tide_blade_hit", e.pos + Vector2(0, -e.r * 0.5), g.PX * clampf(b.size, 1.0, 2.5), b.vel.angle())
		# 基础可穿透 2 名，之后碎裂；碎裂时向周围溅射 60% 伤害（潮刃·贯：4 名 / 无限；深渊巨斩总是穿透）
		var pn: int = [2, 4, 999][int(g.growth.get("b_pierce", 0))]
		if not b.giant and b.hit.size() >= pn:
			b.life = 0.0
			_wave_shatter(b)
			return


## 水刃碎裂：以碎裂点为中心的小范围溅射（已被这道水刃命中过的不再受伤）
func _wave_shatter(b: Dictionary) -> void:
	var sr: float = 70.0 * b.size
	g.fx.append({"kind": "ring", "pos": b.pos, "r": sr, "life": 0.25, "max": 0.25, "col": Color(0.6, 1.0, 1.0)})
	for j in g._query(b.pos, sr + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or b.hit.has(e.id) or e.pos.distance_to(b.pos) > sr + e.r:
			continue
		g._hit("水刃")
		g._damage(e, b.dmg * 0.6)
		if not e.dead:
			e.slow = maxf(e.slow, 0.6)


## 水刃：月牙形水光（巨斩为金紫色）
func _draw_wave(b: Dictionary) -> void:
	var dir: Vector2 = b.vel.normalized()
	var R: float = 24.0 * b.size
	var c: Vector2 = b.pos - dir * R * 0.55
	var ang := dir.angle()
	var fade: float = clampf(b.life / 0.15, 0.0, 1.0)
	if b.giant and g.tex.get("proj_tide_blade_abyss") != null:
		# 深渊巨斩专用贴图（96×72，已是普通水刃的 3 倍，size 3 时按 1:1 显示）：
		# 底层大范围金紫辉光 + 两道残影 + 本体 + 刃口加法高光；出手瞬间带一圈扩散水环
		var spec_g: Array = g.V6_FRAMES["proj_tide_blade_abyss"]
		var fr_g := int(g.t * spec_g[1]) % int(spec_g[0])
		var sc_g: float = g.PX * b.size / 3.0
		var age: float = b.max - b.life
		# 辉光：用本体放大 12% 的低透明副本做贴合轮廓的光晕（比宽弧线更贴形，不会露出扇形色块）
		g._spr_rot("proj_tide_blade_abyss", fr_g, b.pos, ang, sc_g * 1.12, Color(1.5, 0.7, 2.2, 0.16 * fade))
		for k in range(2, 0, -1):
			var gp: Vector2 = b.pos - dir * (14.0 * k) * b.size / 3.0
			g._spr_rot("proj_tide_blade_abyss", (fr_g + 4 - k) % 4, gp, ang, sc_g * (1.0 - 0.04 * k), Color(1.2, 0.9, 1.6, (0.28 - 0.1 * k) * fade))
		g._spr_rot("proj_tide_blade_abyss", fr_g, b.pos, ang, sc_g, Color(1.0, 1.0, 1.0, fade))
		g._spr_rot("proj_tide_blade_abyss", fr_g, b.pos, ang, sc_g, Color(1.0, 0.85, 0.5, 0.25 * fade * (0.5 + 0.5 * sin(g.t * 18.0))))
		if age < 0.25:
			var k2: float = age / 0.25
			g.draw_arc(b.pos - dir * 10.0, R * (0.4 + 1.2 * k2), 0.0, TAU, 32, Color(1.6, 1.2, 2.2, 0.5 * (1.0 - k2)), 3.0)
		return
	var tn := "proj_tide_blade_moon" if b.moon else "proj_tide_blade"
	if g.tex.get(tn) != null:
		# V7：月牙水刃朝右，按速度方向旋转；深渊巨斩无专用图时放大并加一层辉光
		var spec: Array = g.V6_FRAMES[tn]
		var fr := int(g.t * spec[1]) % int(spec[0])
		var sc: float = g.PX * b.size * (1.0 if not b.giant else 1.15)
		if b.giant:
			g.draw_arc(c, R, ang - 1.15, ang + 1.15, 24, Color(1.8, 0.8, 2.4, 0.4 * fade), 10.0 * b.size)
			g._spr_rot(tn, fr, b.pos, ang, sc * 1.35, Color(1.6, 1.0, 2.0, 0.45 * fade))
		g._spr_rot(tn, fr, b.pos, ang, sc, Color(1.0, 1.0, 1.0, fade) if not b.giant else Color(1.4, 1.1, 1.6, fade))
		return
	var core := Color(2.2, 2.6, 2.8, fade) if not b.giant else Color(2.8, 2.2, 2.8, fade)
	var glow := Color(0.5, 1.4, 2.2, 0.35 * fade) if not b.giant else Color(1.8, 0.8, 2.4, 0.4 * fade)
	g.draw_arc(c, R, ang - 1.15, ang + 1.15, 24, glow, 10.0 * b.size)
	g.draw_arc(c, R, ang - 1.0, ang + 1.0, 20, core, 3.0 * b.size)
	g.draw_arc(c, R * 0.82, ang - 0.8, ang + 0.8, 16, Color(core.r, core.g, core.b, 0.5 * fade), 1.5 * b.size)


## 触手桩：扎根的触手，鞭打时伸向目标
func _draw_stake(st: Dictionary) -> void:
	var a: float = clampf(st.life / 0.3, 0.0, 1.0)
	g.draw_set_transform(st.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	g.draw_circle(Vector2.ZERO, 16.0, Color(0.15, 0.03, 0.22, 0.6 * a))
	g.draw_arc(Vector2.ZERO, st.r, 0.0, TAU, 32, Color(1.3, 0.6, 2.0, 0.18 * a), 1.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.tex.get("fx_tendril_stake") != null:
		# V7：待机 32×64 × 4 帧 @8fps，鞭打 48×64 × 4 帧 @16fps（第 2 帧命中），脚底 (16,62)
		var foot: Vector2 = st.pos + Vector2(0, 10)
		if st.whip > 0.0 and g.tex.get("fx_tendril_stake_whip") != null:
			var k: float = st.whip / 0.18
			var wf := clampi(int((1.0 - k) * 4.0), 0, 3)
			var flip: bool = st.wt.x < st.pos.x
			g._spr("fx_tendril_stake_whip", 4, wf, foot, g.PX * 0.8, flip, Color(1, 1, 1, a), Vector2(16.0 / 48.0, 62.0 / 64.0))
			var tip: Vector2 = foot + Vector2((-1.0 if flip else 1.0) * 40.0, -60.0)
			g.draw_line(tip, st.wt, Color(0.6, 0.25, 0.9, 0.7 * k), 4.0)
			g.draw_line(tip, st.wt, Color(1.8, 1.0, 2.6, 0.8 * k), 1.5)
		else:
			var sf := int(g.t * 8.0 + st.pos.x * 0.05) % 4
			g._spr("fx_tendril_stake", 4, sf, foot, g.PX * 0.8, st.flip, Color(1, 1, 1, a), Vector2(0.5, 62.0 / 64.0))
		return
	var fr := 3 + int(g.t * 4.0 + st.pos.x) % 2
	var tc := tentacle_col()
	g._spr("tentacle", 5, fr, st.pos + Vector2(0, 10), g.PX * 1.3, st.flip, Color(tc.r, tc.g, tc.b, a), Vector2(0.5, 1.0))
	if st.whip > 0.0:
		var k: float = st.whip / 0.18
		var tip: Vector2 = st.pos + Vector2(0, -20)
		g.draw_line(tip, st.wt, Color(0.6, 0.25, 0.9, k), 5.0)
		g.draw_line(tip, st.wt, Color(1.8, 1.0, 2.6, k), 1.5)


## 触须阵：地面符阵 + 触须
func _draw_field(f: Dictionary) -> void:
	var a := clampf(f.life / 0.3, 0.0, 1.0) * clampf((f.max - f.life) / 0.2, 0.0, 1.0)
	g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
	g.draw_circle(Vector2.ZERO, f.r, Color(0.35, 0.1, 0.5, 0.3 * a))
	g.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 40, Color(1.4, 0.8, 2.2, 0.8 * a), 2.5)
	g.draw_arc(Vector2.ZERO, f.r * 0.65, g.t * 2.0, g.t * 2.0 + PI * 1.4, 24, Color(1.4, 0.8, 2.2, 0.5 * a), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in 6:
		var an: float = q * TAU / 6.0 + f.r
		var p: Vector2 = f.pos + Vector2(cos(an) * f.r * 0.6, sin(an) * f.r * 0.3)
		var h := (14.0 + 10.0 * sin(g.t * 9.0 + q)) * a
		g.draw_line(p, p + Vector2(sin(g.t * 6.0 + q) * 5.0, -h), Color(0.5, 0.25, 0.7, a), 4.0)
		g.draw_circle(p + Vector2(sin(g.t * 6.0 + q) * 5.0, -h), 2.5, Color(1.4, 0.9, 2.0, a))


## 技能的地面表现（在角色之下）
func _draw_skill_floor() -> void:
	var P: Dictionary = D.SKILL_P
	var base = pos + Vector2(0, 6)
	# 灯火照亮范围（光中敌人受伤 +25%）
	var lr = g._lamp_r()
	g.draw_set_transform(base, 0.0, Vector2(1.0, 0.5))
	for q in 32:
		if q % 2 == 0:
			g.draw_arc(Vector2.ZERO, lr, TAU * q / 32.0 + g.t * 0.1, TAU * (q + 1) / 32.0 + g.t * 0.1, 3, Color(1.6, 1.3, 0.8, 0.22), 1.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s3_active > 0.0:
		# 镜花水月：脚下的镜面水域 + 涟漪
		var r: float = P.s3_zone_r if g.skill_lv.s3 >= 3 else 110.0
		var fade := clampf(s3_active / 1.0, 0.0, 1.0) * clampf((D.SKILL_P.s3_dur - s3_active) / 0.4, 0.0, 1.0)
		g.draw_set_transform(base, 0.0, Vector2(1.0, 0.45))
		g.draw_circle(Vector2.ZERO, r, Color(0.5, 0.35, 1.0, 0.13 * fade))
		for q in 3:
			var rp := fmod(g.t * 0.6 + q / 3.0, 1.0)
			g.draw_arc(Vector2.ZERO, r * rp, 0.0, TAU, 48, Color(1.4, 1.0, 2.2, (1.0 - rp) * 0.55 * fade), 2.0)
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.2, 0.9, 2.0, 0.7 * fade), 2.5)
		# 刻度符文
		for q in 12:
			var dv := Vector2.from_angle(q * TAU / 12.0 - g.t * 0.4)
			g.draw_line(dv * (r - 10.0), dv * r, Color(1.4, 1.1, 2.2, 0.8 * fade), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s2_active > 0.0:
		var fade2 := clampf(s2_active / 1.0, 0.0, 1.0)
		g.draw_set_transform(base, 0.0, Vector2(1.0, 0.45))
		g.draw_arc(Vector2.ZERO, 58.0, 0.0, TAU, 40, Color(0.6, 1.1, 1.8, 0.6 * fade2), 2.0)
		g.draw_arc(Vector2.ZERO, 66.0, g.t * 3.0, g.t * 3.0 + PI, 24, Color(0.6, 1.1, 1.8, 0.4 * fade2), 3.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.skill_lv.s1 >= 1 and s1_charges > 0:
		# 唤醒蓄满：脚下金色光环
		g.draw_set_transform(base, 0.0, Vector2(1.0, 0.45))
		g.draw_arc(Vector2.ZERO, 34.0 + 3.0 * sin(g.t * 8.0), 0.0, TAU, 32, Color(2.0, 1.5, 0.6, 0.7), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 技能的覆盖层表现（在角色之上）
func _draw_skill_over() -> void:
	g._draw_shield()
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


## 升级卡上的数值预览：「当前 → 升级后」
func _growth_preview(id: String) -> String:
	match id:
		"u_dmg": return "伞击伤害 %d → %d" % [int(base("umbrella_dmg", 18.0) * u_dmg_mult * g.dmg_mult), int(base("umbrella_dmg", 18.0) * u_dmg_mult * 1.15 * g.dmg_mult)]
		"u_area": return "挥砍半径 %d → %d" % [int(base("swing_radius", 95.0) * u_area_mult), int(base("swing_radius", 95.0) * u_area_mult * 1.12)]
		"u_spd": return "挥伞间隔 %.2f → %.2f 秒" % [base("swing_interval", 0.9) * u_spd_mult, base("swing_interval", 0.9) * u_spd_mult * 0.9]
		"t_dmg": return "触手倍率 ×%.2f → ×%.2f" % [t_mult, t_mult * 1.2]
		"sp": return "技力回复 ×%.2f → ×%.2f" % [g.sp_mult, g.sp_mult * 1.15]
		"dodge": return "闪避 %d%% → %d%%" % [int(g.dodge * 100), int(g.dodge * 100) + 5]
		"hp": return "最大生命 %d → %d" % [int(g.max_hp), int(g.max_hp) + 20]
		"speed": return "移动速度 %d → %d" % [int(g.speed), int(g.speed * 1.1)]
		"pickup": return "拾取范围 %d → %d" % [int(g.pickup), int(g.pickup * 1.3)]
		"regen": return "生命回复 %.1f → %.1f / 秒" % [g.regen, g.regen + 0.6]
		"armor": return "减伤 %d → %d" % [int(g.armor), int(g.armor) + 1]
		"wick": return "受击灯火损失 ×%.2f → ×%.2f" % [g.lamp_decay, g.lamp_decay * 0.85]
	return ""


func _apply_growth(id: String) -> void:
	var st = g.stats
	var src := "growth:" + id
	match id:
		"u_dmg": st.add(&"mizuki_umbrella_dmg", "mult", 1.15, src)
		"u_area": st.add(&"mizuki_umbrella_area", "mult", 1.1, src)
		"u_spd": st.add(&"mizuki_umbrella_interval", "mult", 0.92, src)
		"t_dmg": st.add(&"mizuki_tentacle_mult", "mult", 1.2, src)
	g._sync_stats()


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
	s1_need = int(st.value(&"mizuki_s1_swings"))


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


## 进化路线的周期性附加：群触·阵（触须阵）与潮刃·回响（潮汐弹）
func _update_evo_extras(dt: float) -> void:
	# 触须阵
	var fl: int = [0, 2, 4][int(g.growth.get("t_field", 0))] if evo1 == "tendril" else 0   # 群触·阵
	if fl > 0:
		field_cd -= dt
		if field_cd <= 0.0:
			field_cd = 3.5
			for k in (2 if fl >= 4 else 1):
				var c = g._densest_point(380.0, pos)
				if c != Vector2.INF:
					var fr := 70.0 * (1.3 if fl >= 2 else 1.0)
					var dur := 2.4 if fl >= 5 else 1.8
					fields.append({"pos": c + Vector2(randf_range(-30, 30), randf_range(-30, 30)) * k, "r": fr, "life": dur, "max": dur, "tick": 0.0,
						"bind": fl >= 3, "dmg": 9.0 * g.dmg_mult * (1.6 if fl >= 5 else 1.0)})
					Sfx.play("tentacle", -8.0, 0.7, 0.05)
	for f in fields:
		f.life -= dt
		f.tick -= dt
		if f.tick <= 0.0:
			f.tick = 0.3
			for j in g._query(f.pos, f.r + 20.0):
				var e: Dictionary = g.enemies[j]
				if not e.dead and e.pos.distance_to(f.pos) < f.r + e.r * 0.5:
					g._hit("触须阵")
					g._damage(e, f.dmg)
					if f.bind and not e.boss and not e.dead:
						e.stun = maxf(e.stun, 0.35)
	fields = fields.filter(func(f): return f.life > 0.0)
	# 潮汐弹
	var tl: int = [0, 2, 4][int(g.growth.get("b_echo", 0))] if evo1 == "blade" else 0   # 潮刃·回响
	if tl > 0:
		tide_shot_cd -= dt
		if tide_shot_cd <= 0.0:
			var ts3 = g._nearest(2, 420.0, pos)
			if ts3.is_empty():
				tide_shot_cd = 0.2
			else:
				tide_shot_cd = 2.2 * (0.7 if tl >= 5 else 1.0)
				var bounces := 3 + (2 if tl >= 2 else 0) + (3 if tl >= 5 else 0)
				for k in (2 if tl >= 3 else 1):
					var tg: Dictionary = ts3[k % ts3.size()]
					var d: Vector2 = (tg.pos - pos).normalized()
					g.bullets.append({"kind": "tide", "pos": pos + Vector2(0, -20), "vel": d * 520.0, "dmg": 16.0 * g.dmg_mult * (1.5 if tl >= 4 else 1.0),
						"life": 1.0, "r": 7.0, "aoe": 0.0, "bounces": bounces, "hit": {}, "push": tl >= 4})
				Sfx.play("pickup", -10.0, 0.8, 0.05)


## 角色脚下的光环（缺帧条时的程序版）
func draw_auras() -> void:
	if s2_active > 0.0 and g.tex.get("fx_s2_aura") == null:
		g.draw_arc(pos + Vector2(0, -10), 30.0 + sin(g.t * 6.0) * 2.0, 0.0, TAU, 20, Color(0.5, 0.8, 1.0, 0.6), 2.0)
	if s3_active > 0.0 and g.tex.get("fx_s3_aura") == null:
		g.draw_arc(pos + Vector2(0, -10), 40.0 + sin(g.t * 4.0) * 3.0, 0.0, TAU, 24, Color(0.8, 0.55, 1.0, 0.7), 3.0)
		g.draw_circle(pos + Vector2(0, -10), 36.0, Color(0.6, 0.4, 1.0, 0.08))


## 地面层专属实体：触手追击、技能地面表现、触须阵、触手桩、巨触、残影与镜像分身
func draw_entities_floor() -> void:
	for f in g.fx:
		if f.kind == "tentacle":
			_draw_tentacle(f)
	_draw_skill_floor()
	for f in fields:
		_draw_field(f)
	for st in stakes:
		_draw_stake(st)
	for gi in giants:
		_draw_giant(gi)
	for i in range(afterimg.size() - 1, -1, -1):
		var ai: Dictionary = afterimg[i]
		var aa: float = 0.45 * (1.0 - float(i) / afterimg.size())
		draw_body_at(ai.pos, ai.flip, Color(0.9, 0.55, 1.8, aa), {"tex": ai.tex, "frame": ai.frame, "hf": ai.hf, "flip": ai.flip})
	if s3_active > 0.0 and g.skill_lv.s3 >= 2:
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


## 任一技能是否生效中（音乐强度用）
func skill_active() -> bool:
	return s2_active > 0.0 or s3_active > 0.0


## 状态栏条目：[文字, 颜色, 进度 0..1 或 -1]
func status_items() -> Array:
	var items: Array = []
	if s1_charges > 0:
		items.append(["唤醒 ×%d" % s1_charges, UI.GOLD, -1.0])
	if s2_active > 0.0:
		items.append(["囚徒困境", Color(0.45, 0.8, 1.0), s2_active / D.SKILL_P.s2_dur])
	if s3_active > 0.0:
		items.append(["镜花水月", UI.PURPLE, s3_active / D.SKILL_P.s3_dur])
	return items


## 技能环：每个技能 [字, 名, 已解锁, 生效剩余秒, 生效总秒, 充能进度, 颜色, 层数点(-1 无)/当前层]
func skill_hud() -> Array:
	return [
		["唤", "唤醒", g.skill_lv.s1 >= 1, 0.0, 1.0, float(s1_count) / float(s1_need), UI.GOLD, 3, s1_charges],
		["囚", "囚徒困境", g.skill_lv.s2 >= 1, s2_active, D.SKILL_P.s2_dur, s2_sp / D.SKILL_P.s2_charge, Color(0.45, 0.8, 1.0), -1, 0],
		["镜", "镜花水月", g.skill_lv.s3 >= 1, s3_active, D.SKILL_P.s3_dur, s3_sp / D.SKILL_P.s3_charge, UI.PURPLE, -1, 0],
	]


## 属性面板：角色专属数值行
func stats_rows() -> Array:
	var interval: float = base("swing_interval", 0.9) * u_spd_mult
	var half: float = minf(180.0, 75.0 + rib_bonus + 15.0 * g.growth.get("u_area", 0))
	return [
		["伞击伤害", "%d" % int(base("umbrella_dmg", 18.0) * u_dmg_mult * g.dmg_mult)], ["全局伤害", "×%.2f" % g.dmg_mult], ["挥伞间隔", "%.2f 秒" % max(0.18, interval)],
		["挥砍半径", "%d" % int(base("swing_radius", 95.0) * u_area_mult)], ["挥砍角度", "%d°" % int(half * 2.0)], ["触手倍率", "×%.2f" % t_mult],
		["追击目标", "%d" % (1 + extra_targets)], ["技力回复", "×%.2f" % g.sp_mult],
	]


## 精英化路线标签 [文字, 颜色]；未选路线返回空
func evo_label() -> Array:
	if evo1 == "":
		return []
	var E: Dictionary = evo_table()
	return [E[evo1].name + ((" · " + E[evo2].name) if evo2 != "" else ""), E[evo1].col]


## 精英化一 / 二到达时的处理（stage 1：天赋二 + 等待选路线；stage 2：等待选质变）
## 精英化：一 = 解锁囚徒困境 + 天赋反移情 + 进化方向（choice = 路线 id）；二 = 解锁镜花水月 + 质变（choice = 质变 id）
func on_elite(stage: int, choice: String = "") -> void:
	if stage == 1:
		talent2_on = true
		g.skill_lv.s2 = maxi(g.skill_lv.s2, 1)
		g.elite_stage = 1
		g.show_queue.append({"head": "精英化一", "en": "ELITE  PROMOTION  I", "col": Color(0.5, 0.8, 1.0), "demo": "s2", "items": [
			g._skill_item("s2"),
			{"tag": "天赋", "tag_en": "TALENT", "glyph": "反", "name": "反移情", "desc": "击杀敌人时回复生命（每秒有上限）", "col": Color(0.5, 1.0, 0.65)}]})
		if choice != "":
			on_evo_pick(choice)
	elif stage == 2:
		g.elite_stage = 2
		if choice != "":
			on_evo_pick(choice)


## 成长线里的自定义节点：s1 = 解锁唤醒
func on_custom_node(nid: String, _choice: String = "") -> void:
	if nid == "s1":
		g.skill_lv.s1 = maxi(g.skill_lv.s1, 1)
		g.show_queue.append({"head": "技能解锁", "en": "SKILL  UNLOCKED", "col": UI.GOLD, "demo": "s1", "items": [g._skill_item("s1")]})


## 精英化节点的选项：一 = 进化路线，二 = 当前路线的质变
func elite_choices(n: Dictionary) -> Dictionary:
	var E: Dictionary = evo_table()
	var out: Dictionary = {}
	var ids: Array = evo_paths() if int(n.level) == 1 else evo_mutations(evo1)
	for k in ids:
		out[k] = {"name": E[k].name, "desc": E[k].desc, "icon": "evo_" + k, "col": E[k].col}
	return out


## 追加的深度卡：技能进阶（各两段）+ 当前进化路线的专属成长
func extra_cards() -> Array:
	var out: Array = []
	for sid in ["s1", "s2", "s3"]:
		var lv: int = g.skill_lv[sid]
		if lv >= 1 and lv < 3:
			var ad: Dictionary = skill_adv()[sid][lv - 1]
			if g.level >= ad.min_lv:
				out.append({"kind": "skill", "op": id, "id": sid, "name": "%s · %s" % [skills()[sid].name, ad.name], "desc": ad.desc, "stage": lv})
	var GT: Dictionary = growth_table()
	for gid in GT:
		var gr: Dictionary = GT[gid]
		if not gr.has("path") or gr.path != evo1:
			continue
		var n: int = g.growth.get(gid, 0)
		if n >= gr.max:
			continue
		var nm: String = gr.name if gr.max > 90 else "%s  %d/%d" % [gr.name, n + 1, gr.max]
		out.append({"kind": "growth", "op": id, "id": gid, "name": nm, "desc": gr.desc + "\n" + _growth_preview(gid)})
	return out


## 选中精英化选项（路线或质变）
func on_evo_pick(eid: String) -> void:
	var E: Dictionary = evo_table()
	var ev: Dictionary = E[eid]
	if not ev.has("path"):
		evo1 = eid
		g._show_banner("进化方向：%s" % ev.name)
		g.fx.append({"kind": "rays", "pos": pos, "life": 0.7, "max": 0.7, "col": ev.col})
		g.fx.append({"kind": "ring", "pos": pos, "r": 160.0, "life": 0.6, "max": 0.6, "col": ev.col})
		g._shake(0.6)
	else:
		evo2 = eid
		g.skill_lv.s3 = 1
		s3_sp = 30.0
		g.show_queue.append({"head": "精英化二", "en": "ELITE  PROMOTION  II", "col": Color(0.8, 0.55, 1.0), "demo": "s3", "items": [
			g._skill_item("s3"),
			{"tag": "质变", "tag_en": "EVOLUTION", "glyph": ev.glyph, "icon": "evo_" + eid, "name": "%s · %s" % [E[evo1].name, ev.name], "desc": ev.desc, "col": ev.col}]})


## 击杀钩子：天赋二「反移情」按预算回血
func on_kill(_e: Dictionary) -> void:
	if talent2_on:
		var got: float = min(0.01, heal_budget)
		heal_budget -= got
		g._heal(g.max_hp * got)


# ---- 表：本角色的技能 / 成长 / 精英化定义（目前仍在 data.gd）
func skills() -> Dictionary:
	return D.SKILLS


## 水月三个技能全部自动，没有手动技能
func try_manual_skill() -> bool:
	return false


## 排异反应：从已获得的技能进阶里随机换一个成海嗣化版本；没有可换的用兜底。返回说明文字
func apply_rejection() -> String:
	var cands: Array = []
	if g.skill_lv.s1 >= 2 and not rej.has("s1a"):
		cands.append("s1a")
	if g.skill_lv.s1 >= 3 and not rej.has("s1b"):
		cands.append("s1b")
	if g.skill_lv.s2 >= 2 and not rej.has("s2a"):
		cands.append("s2a")
	if g.skill_lv.s2 >= 3 and not rej.has("s2b"):
		cands.append("s2b")
	if g.skill_lv.s3 >= 2 and not rej.has("s3a"):
		cands.append("s3a")
	if g.skill_lv.s3 >= 3 and not rej.has("s3b"):
		cands.append("s3b")
	var key := "fallback"
	if not cands.is_empty():
		key = cands[g.rng.randi() % cands.size()]
	elif rej.has("fallback"):
		return "已无可海嗣化的进阶"
	rej[key] = true
	match key:
		"s1a":
			g.stats.add(&"mizuki_s1_swings", "flat", 2.0, "rejection")
			g._sync_stats()
		"s3a":
			g.stats.add(&"max_hp", "flat", -20.0, "rejection")
			g._sync_stats()
			g.hp = minf(g.hp, g.max_hp)
	return REJ_NAMES[key]


## 触手颜色：常态蓝色，海嗣化后紫色
func tentacle_col(bright := 1.0) -> Color:
	if rej.is_empty():
		return Color(0.62 * bright, 0.9 * bright, 1.35 * bright)
	return Color(1.25 * bright, 0.7 * bright, 1.6 * bright)


func skill_unlock() -> Dictionary:
	return D.SKILL_UNLOCK


func skill_adv() -> Dictionary:
	return D.SKILL_ADV


func growth_table() -> Dictionary:
	return D.GROWTH


func evo_table() -> Dictionary:
	return D.EVO
