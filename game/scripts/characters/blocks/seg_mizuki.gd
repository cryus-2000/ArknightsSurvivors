## 干员积木 · seg_mizuki（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_lumen.gd"

const MzVg = preload("res://scripts/characters/blocks/vis_growth.gd")   # 可见成长 #129（docs/163 / 163D）：触手桩在场上限 +1

const MizukiS3Fx = preload("res://scripts/characters/mizuki_s3_fx.gd")

const H3_GOLD := Color(0.957, 0.753, 0.306)   # 同 ui.gd GOLD（灯火金：唤醒）


static func _h3mz(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("mz"):
		h["mz"] = {"budget": 0.0, "stakes": [], "delayed": [], "s3_fx": 0.0, "s3_fx_radius": 0.0, "st": {}}
	return h.mz


## 专属属性缓存（data_operator.sync_stats 转来，同手写 sync_stats）
static func h3_sync_stats(o, st) -> void:
	if not hw_on(o) or not o.hw.has("mz"):
		return
	var sc: Array = o.scopes()
	var m: Dictionary = o.B.get("attack", _ED).get("stats", {})
	for k in m:
		o.hw.mz.st[k] = st.value_for(StringName(str(m[k])), sc)


static func _h3_st(o, k: String, def: float) -> float:
	return float(o.hw.mz.st.get(k, def))


## data_operator._dmg_bonus 转来（blocks.dmg_bonus）
static func h3_dmg_bonus(o) -> float:
	var db: Dictionary = o.B.get("dmg_bonus", {})
	var m: float = o.stat(&"dmg") * o.stat(&"op_atk")
	if db.get("ally", true):
		m *= o.g.ally_mult
	for it in db.get("mults", _EA):
		if not cond_true(o, it.get("cond", _ED)):
			continue
		var nl = it.get("near_low_hp", null)
		if nl is Dictionary and not _h3_low_hp_near(o, float(nl.get("r", 160.0)), float(nl.get("below", 0.5))):
			continue
		m *= float(it.get("mult", 1.0))
	return m


static func _h3_low_hp_near(o, r: float, below: float) -> bool:
	var g = o.g
	for j in o.query_ids(o.pos, r):
		var e: Dictionary = g.enemies[j]
		if not e.dead and e.hp < e.maxhp * below and e.pos.distance_to(o.pos) < r:
			return true
	return false


static func h3_umb_radius(o, a: Dictionary) -> float:
	return _h3_mults(o, float(a.get("r", 142.0)) * _h3_st(o, "area", 1.0) * o.stat(&"op_range"), a.get("r_mults", []))   # op_range：漆黑的舞鞋 / 长鞭等范围藏品（163B §3 核对：原来不吃）


## 常驻效果每帧推进一次；起手和命中由公共动作时钟驱动。
static func h3_tick_effects(o, dt: float) -> void:
	var g = o.g
	var mz := _h3mz(o)
	var a: Dictionary = o.B.get("attack", {})
	# 重叠技能的前台收势结束后，恢复仍有效的另一条循环，不重放起手。
	if o.sq_ph == 0 and not o.acting():
		for i in range(2, -1, -1):
			var sequence: Dictionary = o.skill_seq(i)
			if o.s_t[i] > 0.0 and sequence.has("loop"):
				o.sq = sequence
				o.sq_i = i
				o.sq_ph = 2
				o.sq_t = 0.0
				break
	var kh := _h3_talent_any(o, "verb.kill_heal")
	if not kh.is_empty():
		mz.budget = min(float(mz.budget) + dt * float(kh.get("regen", 0.05)), float(kh.get("cap", 0.05)))
	_h3_stakes_tick(o, mz, dt)
	_e3_jelly_tick(o, mz, dt)   # 精英化第 3 批：深蓝之籽
	_g202_mz_tick(o, mz, dt)   # docs/202：缠住（病理性依恋 / 强迫性重复）
	mz.s3_fx = maxf(0.0, float(mz.s3_fx) - dt)
	for i in range(mz.delayed.size() - 1, -1, -1):
		var dl: Dictionary = mz.delayed[i]
		dl.at -= dt
		if dl.at <= 0.0:
			mz.delayed.remove_at(i)
			_h3_run_delayed(o, dl)


static func h3_umbrella_start(o, a: Dictionary) -> void:
	if o.no_attack or o.cd > 0.0 or o.sq_ph == 3:
		return
	var radius := h3_umb_radius(o, a)
	var at: Vector2 = o.atk_point(o.nearest_enemies(1, radius + float(a.get("aim_pad", 60.0)), o.pos), radius)
	if at == Vector2.INF:
		o.cd = float(a.get("idle", 0.1))
		return
	o.cd = h3_umbrella_interval(o, a)
	var anim := ""
	for i in mini(3, o.B.skills.size()):
		if o.ammo[i] > 0:
			anim = str(o.B.skills[i].get("attack_patch", {}).get("anim", ""))
			break
	o.start_attack(at, 0.5, 0.25, anim, o.cd)


static func h3_umbrella_interval(o, a: Dictionary) -> float:
	var interval: float = float(a.get("every", 0.9)) * _h3_st(o, "interval", 1.0) / o.stat(&"op_aspd")
	if o.g.atk_slow > 0.0:
		interval *= float(a.get("slow_mult", 1.5))
	return maxf(float(a.get("min_cd", 0.18)), _h3_mults(o, interval, a.get("interval_mults", [])))


static func h3_umbrella_release(o, a: Dictionary) -> bool:
	var radius := h3_umb_radius(o, a)
	var targets: Array = o.nearest_enemies(1, radius + float(a.get("aim_pad", 60.0)), o.pos)
	if targets.is_empty() and not (o.held_aim() and o.atk_aim != Vector2.ZERO):
		return false   # 自动：没有目标就没出手；手动（10-24）：按了就沿玩家指向挥伞，周围没有敌人也照常出招（manual-aim 漏了这里）
	var angle: float = o.atk_angle((targets[0].pos - o.pos).angle() if not targets.is_empty() else o.atk_aim.angle())
	_h3_umbrella(o, a, o.pos + Vector2.from_angle(angle) * radius)
	return true


static func h3_cancel(o) -> void:
	var mz: Dictionary = o.hw.mz
	for key in ["stakes", "delayed", "jel", "binds", "cling"]:
		if mz.has(key):
			mz[key].clear()
	mz["marks"] = {}
	mz["rep"] = {}
	mz.s3_fx = 0.0
	mz.s3_fx_radius = 0.0
	mz.budget = 0.0


static func _h3_talent_any(o, tag: String) -> Dictionary:
	for sec in ["trait", "talent"]:
		for t in o.B.get(sec, []):
			for b in t.get("do", _EA):
				if str(b.get("_tag", "")) == tag:
					return b
	return {}


static func h3_full_circle(o, a: Dictionary) -> bool:
	return a.has("full_circle") and cond_true(o, a.full_circle.get("cond", _ED))


## 伞击
static func _h3_umbrella(o, a: Dictionary, at: Vector2) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	var radius: float = h3_umb_radius(o, a)
	var half: float = deg_to_rad(min(180.0, float(a.get("half_deg", 75.0)) + _h3_st(o, "arc", 0.0)))
	var ang: float = (at - o.pos).angle()
	o.face_to(ang)
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * _h3_st(o, "dmg", 1.0) * o._dmg_bonus()
	for m in a.get("dmg_mults", _EA):
		if cond_true(o, m.get("cond", _ED)):
			dmg *= float(m.get("mult", 1.0))
	var emp := {}
	var sk: Array = o.B.get("skills", [])
	for i in 3:
		if o.ammo[i] > 0 and i < sk.size():
			o.ammo[i] -= 1
			emp = sk[i].get("attack_patch", {})
			break
	var empowered: bool = not emp.is_empty()
	if empowered:
		dmg *= float(emp.get("mult", 1.0)) * o.skill_power()
		radius *= float(emp.get("r_mult", 1.0))
	var s3 := h3_full_circle(o, a)
	if s3:
		half = PI
	var hit: Array = o.arc_targets(o.pos, ang, half, radius)
	if s3:
		mz.s3_fx = 0.3
		mz.s3_fx_radius = radius
	g.crit_hit = empowered
	dmg *= g.rfx.single_hit_mult(hit.size()) * MzVg.crowd_mult(o, hit)
	var src: String = str(a.get("src", ""))
	var sm: Dictionary = _h4_sub(o, a.get("tentacle", _ED).get("smash", null))   # docs/202 病理性依恋·重斩
	for e in hit:
		o.log_hit(src, ["empowered"] if empowered else [])
		o.deal_damage(e, dmg * (_g202_smash_take(o, e, sm) if not sm.is_empty() else 1.0))
		if not e.boss:
			o.apply_kb(e, (e.pos - o.pos).normalized() * (float(emp.get("kb", 360.0)) if empowered else float(a.get("kb", 240.0))))
	g.crit_hit = false
	if empowered:
		var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
		if sfx != null:
			sfx.play("swing_heavy", -3.0)
	else:
		_h3_sfx(o, "atk", 3.0)
	if hit.size() > 0:
		_h3_sfx(o, "hit", 8.0 if empowered else 4.0, 0.85 if empowered else 1.0)
		o.impact_pause(0.09 if empowered else 0.03)
		for k in min(hit.size(), 6):
			var he: Dictionary = hit[k]
			o.sparks(he.pos, he.pos - o.pos, H3_GOLD if empowered else Color(0.85, 0.97, 1.0), 4 if empowered else 3, 260.0)
	# 触手追击
	var tb: Dictionary = a.get("tentacle", {})
	var alive := hit.filter(func(e): return not e.dead)
	alive.sort_custom(func(x, y): return x.hp < y.hp)
	var n: int = int(_h3_st(o, "t_n", 1.0))
	for m in tb.get("n_add", _EA):
		if cond_true(o, m.get("cond", _ED)):
			n += int(m.get("n", 1))
	var tdmg: float = dmg * _h3_st(o, "t_mult", 0.6)
	var tstun := 0.0
	for sv in tb.get("stun", _EA):
		if cond_true(o, sv.get("cond", _ED)):
			tstun = float(sv.get("dur", 0.0))
			break
	var hy: Dictionary = _h4_sub(o, tb.get("hyst", null))
	var lows: Array = []
	if not hy.is_empty() and hit.size() >= int(hy.get("hits", 4)):
		lows = alive.filter(func(e): return e.hp < e.maxhp * float(hy.get("below", 0.5)))
	if not lows.is_empty():
		var hn: int = maxi(n, mini(int(hy.get("max", 6)), lows.size()))
		var order: Array = lows.slice(0, int(hy.get("max", 6)))
		for e in alive:
			if order.size() >= hn:
				break
			if not order.has(e):
				order.append(e)
		for i in mini(hn, order.size()):
			_h3_tentacle(o, a, order[i], tdmg, tstun)
		o.fx({"kind": "ring", "pos": o.pos + Vector2(0, 4), "r": radius, "r0": radius * 0.4, "life": 0.35, "col": Color(0.85, 0.55, 1.5), "floor": true, "w": 2.5, "alpha": 0.8})
	else:
		for i in min(n, alive.size()):
			_h3_tentacle(o, a, alive[i], tdmg, tstun)
		if not s3 and hit.size() > 0 and alive.size() < n:
			var more: Array = o.nearest_enemies(n + 4, radius * float(tb.get("more_r", 1.6)), o.pos).filter(func(e): return not e.dead and not alive.has(e))
			for i in mini(n - alive.size(), more.size()):
				_h3_tentacle(o, a, more[i], tdmg, tstun)
	var sw = emp.get("swarm", null)
	if empowered and sw is Dictionary and cond_true(o, sw.get("cond", _ED)):
		var near: Array = o.nearest_enemies(int(sw.get("n", 2)), radius * float(sw.get("r_mult", 1.6)), o.pos)
		for ne in near:
			if not ne.dead:
				_h3_tentacle(o, a, ne, tdmg, float(sw.get("stun", 0.4)))
	# 唤醒：命中处范围冲击（创伤扩散）
	var bu = emp.get("burst", null)
	if empowered and hit.size() > 0 and bu is Dictionary:
		var ip: Vector2 = hit[0].pos
		# 10-24 用户「水月一技能造成的这些黄色的圆形可以去掉」：命中处的金色十字光团（impact）不画了；r70 金环本来就被 render/hit_rings 关着
		g.fx.append({"kind": "ring", "pos": ip, "r": 70.0, "life": 0.3, "max": 0.3, "col": H3_GOLD, "op_hit": true})
		g.flash = maxf(g.flash, 0.12)
		for k in mini(hit.size(), int(bu.get("n", 3))):
			mz.delayed.append({"at": float(bu.get("gap", 0.06)) * k, "kind": "burst", "pos": hit[k].pos, "dmg": dmg * float(bu.get("mult", 0.6)), "r": float(bu.get("r", 80.0)), "b": bu})
	# 斩击表现
	var slash_col := Color.WHITE
	if empowered:
		slash_col = Color(1.6, 1.3, 0.7)
	elif s3:
		slash_col = Color(1.2, 0.85, 1.6)
	elif o.s_t[1] > 0.0:
		slash_col = Color(0.8, 1.1, 1.5)
	var slash_tex: String = o.slash_tex_name("awaken" if empowered else ("mirage" if s3 else "base"))
	if slash_tex.begins_with("fx_umbrella_slash"):
		slash_col = Color(1.15, 1.15, 1.15)
	if empowered and alive.size() > 0:
		o.play_anim_fx("fx_s1_burst", alive[0].pos, 0.35)
	for k in min(hit.size(), 3):
		o.enemy_hit_fx(hit[k], hit[k].pos - o.pos)
	if not s3:
		o.slash_fx(o.pos, ang, half, radius, slash_col, slash_tex, 0.26 if empowered else 0.22)
	if empowered and not s3 and not slash_tex.begins_with("fx_umbrella_slash"):
		o.slash_fx(o.pos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)


static func _h3_tentacle(o, a: Dictionary, target: Dictionary, dmg: float, stun: float) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	var tb: Dictionary = a.get("tentacle", {})
	var p: Vector2 = target.pos
	o.log_hit(str(tb.get("src", "")))
	o.deal_damage(target, dmg)
	if not target.dead:
		o.add_cc(target, stun if stun > 0.0 else float(tb.get("stun_min", 0.25)))
		var dr = tb.get("drag", null)
		if dr is Dictionary and cond_true(o, dr.get("cond", _ED)) and not target.boss:
			o.apply_kb(target, (o.pos - target.pos).normalized() * (float(dr.get("kb_elite", 160.0)) if target.elite else float(dr.get("kb", 320.0))))
		var pulled: bool = _e3_pull(o, a, target)   # 精英化第 3 批：拖拽
		_e3_mark(o, target)   # 精英化第 3 批：深蓝之籽优先打被触手打过的
		_g202_repeat(o, tb, target, dmg)   # docs/202 强迫性重复
		_g202_cling(o, tb, target, pulled)   # docs/202 病理性依恋
	var sk = tb.get("stake", null)
	if sk is Dictionary and cond_true(o, sk.get("cond", _ED)):
		if mz.stakes.size() >= int(sk.get("max", 6)) + MzVg.summon_subs(g, "stake"):   # 只扩容量，仍由原触手攻击创建（163B §4）
			mz.stakes.pop_front()
		mz.stakes.append({"pos": p, "t": float(sk.get("life", 1.5)), "tick": float(sk.get("every", 0.5)), "dmg": dmg * float(sk.get("mult", 0.4)), "flip": g.vrng.randf() < 0.5, "b": sk})
	if h3_full_circle(o, a):
		return   # S3 的触手从整片范围同时出现，命中效果不重复逐敌生成。
	g.fx.append({"kind": "rift", "pos": p, "r": 26.0, "life": 0.25, "max": 0.25})
	if not o.spawn_fx_sprite("fx_mizuki_tentacle", p + Vector2(0, 10), g.PX * 0.8, 0.0, g.vrng.randf() < 0.5, true, Color(1,1,1,0.8)):
		var tl: float = 0.4 if g.tex.get("fx_tentacle_strike") != null else 0.6
		g.fx.append({"kind": "tentacle", "pos": p, "life": tl, "max": tl, "flip": g.vrng.randf() < 0.5})
	g.fx.append({"kind": "tendril", "a": o.pos + Vector2(0, 6), "b": p + Vector2(0, 6), "life": 0.32, "max": 0.32, "seed": g.vrng.randf() * 10.0})
	g.fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 34.0, "life": 0.3, "max": 0.3, "col": h3_deep_col(o, 1.6), "op_hit": true})
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null:
		sfx.play("tentacle", -4.0)
	o.sparks(p + Vector2(0, 8), Vector2.UP, h3_deep_col(o, 1.5), 7, 200.0)


static func _h3_stakes_tick(o, mz: Dictionary, dt: float) -> void:
	var g = o.g
	for s in mz.stakes:
		s.t -= dt
		s.tick -= dt
		if s.tick <= 0.0 and s.t > 0.0:
			var sk: Dictionary = s.b
			s.tick = float(sk.get("every", 0.5))
			var any := false
			var sr: float = float(sk.get("r", 60.0))
			for j in o.query_ids(s.pos, sr + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(s.pos) > sr + e.r:
					continue
				any = true
				o.log_hit(str(o.B.get("attack", _ED).get("tentacle", {}).get("src", "")))
				o.deal_damage(e, s.dmg)
			if any:
				o.spawn_fx_sprite("fx_mizuki_tentacle", s.pos + Vector2(0, 10), g.PX * 0.85 * 0.8, 0.0, s.flip, true, Color(1,1,1,0.8))
				s.flip = not s.flip
	mz.stakes = mz.stakes.filter(func(s): return s.t > 0.0)


static func _h3_run_delayed(o, dl: Dictionary) -> void:
	var g = o.g
	match str(dl.kind):
		"burst":
			var bu: Dictionary = dl.b
			for j in o.query_ids(dl.pos, dl.r):
				var e: Dictionary = g.enemies[j]
				if not e.dead and e.pos.distance_to(dl.pos) < dl.r + e.r:
					o.log_hit(str(bu.get("src", "")))
					o.deal_damage(e, dl.dmg)
					if not e.boss:
						o.apply_kb(e, (e.pos - dl.pos).normalized() * float(bu.get("kb", 200.0)))
			# 创伤扩散的金色实心圆 + 粗圆环（burst）不画了（10-24 用户），伤害 / 击退 / 火星照旧
			o.sparks(dl.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 10, 280.0)
			var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
			if sfx != null:
				sfx.play("boom", -10.0, 1.4, 0.1)


## 技能发动光环 + 推开身边小怪（同手写 _skill_cast）
static func h3_cast_push(o, b: Dictionary) -> void:
	var g = o.g
	var big: bool = b.get("big", false)
	o.play_anim_fx("fx_cast", o.pos, 0.5, g.PX * (1.3 if big else 1.0), true)
	o.screen_shake(0.8 if big else 0.5)
	g.flash = maxf(g.flash, 0.25)
	var c: Color = _mf_col(b.get("col", []), Color(0.45, 0.8, 1.0))
	if not big:
		g.fx.append({"kind": "ring", "pos": o.pos, "r": 160.0, "life": 0.5, "max": 0.5, "col": c, "op_hit": true})
		g.fx.append({"kind": "ring", "pos": o.pos, "r": 260.0, "life": 0.7, "max": 0.7, "col": c, "op_hit": true})
		g.fx.append({"kind": "rays", "pos": o.pos, "life": 0.6, "max": 0.6, "col": c, "op_spoke": true})
		o.sparks(o.pos + Vector2(0, -20), Vector2.ZERO, c, 24, 360.0)
	var r: float = float(b.get("r", 140.0))
	for j in o.query_ids(o.pos, r):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.boss and not e.chest:
			o.apply_kb(e, (e.pos - o.pos).normalized() * float(b.get("kb", 420.0)))


static func h3_kill_heal(o, b: Dictionary) -> void:
	var g = o.g
	var mz := _h3mz(o)
	var got: float = min(float(b.get("pct", 0.01)) * float(o.kill_w), float(mz.budget))   # 按击杀权重（docs/50 §16.8），仍受每秒预算约束
	mz.budget = float(mz.budget) - got
	o.heal_leader(g.max_hp * got, o.display_name())


## 触手本体的染色：look.deep（常态）/ look.deep_rej（排异后）× bright
static func h3_deep_col(o, bright := 1.0) -> Color:
	var lk: Dictionary = o.B.get("attack", _ED).get("look", {})
	var c: Color = _mf_col(lk.get("deep", []), Color(0.22, 0.34, 0.88)) if o.rej.is_empty() else _mf_col(lk.get("deep_rej", []), Color(0.62, 0.34, 1.0))
	return Color(c.r * bright, c.g * bright, c.b * bright)


static func h3_tentacle_col(o, bright := 1.0) -> Color:
	if not hw_on(o) or not o.hw.has("mz"):
		return Color(1.3, 1.1, 1.6)
	var lk: Dictionary = o.B.get("attack", _ED).get("look", {})
	var c: Color = _mf_col(lk.get("pale", []), Color(0.62, 0.9, 1.35)) if o.rej.is_empty() else _mf_col(lk.get("pale_rej", []), Color(1.25, 0.7, 1.6))
	return Color(c.r * bright, c.g * bright, c.b * bright)


# ---- 画面

static func _h3mz_draw_floor(o) -> void:
	var g = o.g
	var cv = o.cv
	var mz: Dictionary = o.hw.mz
	for f in g.fx:
		if f.kind == "tentacle":
			_h3_draw_tentacle(o, f)
	_e3_draw_binds(o)
	_g202_mz_draw(o)
	for s in mz.stakes:
		var a: float = clampf(s.t / 0.4, 0.0, 1.0)
		var sr: float = float(s.b.get("r", 60.0))
		cv.draw_set_transform(s.pos + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
		pass   # 10-29 特效审查：去掉整片半透明填充圆盘（遮敌人 / 弹幕），只留描边
		cv.draw_arc(Vector2.ZERO, sr * 0.8, 0.0, TAU, 24, Color(0.85, 0.7, 1.2, 0.45 * a), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var bp: Vector2 = o.pos + Vector2(0, 6)
	var lr: float = o.lamp_radius()
	cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.5))
	for q in 32:
		if q % 2 == 0:
			cv.draw_arc(Vector2.ZERO, lr, TAU * q / 32.0 + g.t * 0.1, TAU * (q + 1) / 32.0 + g.t * 0.1, 3, Color(1.6, 1.3, 0.8, 0.22), 1.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	MizukiS3Fx.draw(o, false)
	if o.s_t[1] > 0.0:
		var fade2 := clampf(o.s_t[1] / 1.0, 0.0, 1.0)
		cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
		cv.draw_arc(Vector2.ZERO, 58.0, 0.0, TAU, 40, Color(0.6, 1.1, 1.8, 0.6 * fade2), 2.0)
		cv.draw_arc(Vector2.ZERO, 66.0, g.t * 3.0, g.t * 3.0 + PI, 24, Color(0.6, 1.1, 1.8, 0.4 * fade2), 3.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if o.ammo[0] > 0:
		cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
		cv.draw_arc(Vector2.ZERO, 34.0 + 3.0 * sin(g.t * 8.0), 0.0, TAU, 32, Color(2.0, 1.5, 0.6, 0.7), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _h3_draw_tentacle(o, f: Dictionary) -> void:
	var g = o.g
	var cv = o.cv
	var a: float = 1.0 - f.life / f.max
	cv.draw_set_transform(f.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	var gc: Color = h3_deep_col(o, 1.4)
	cv.draw_circle(Vector2.ZERO, 22.0, Color(gc.r, gc.g, gc.b, 0.35 * (1.0 - a)))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if g.tex.get("fx_tentacle_strike") != null:
		var fr := clampi(int(a * 6.0), 0, 5)
		o.draw_spr("fx_tentacle_strike", 6, fr, f.pos + Vector2(0, 10), g.PX * 1.25, f.flip, h3_deep_col(o, 1.3 if fr == 3 else 1.0), Vector2(0.5, 46.0 / 48.0))
		return
	var fr2 := clampi(int(a * 5.0 / 0.75), 0, 4)
	o.draw_spr("tentacle", 5, fr2, f.pos + Vector2(0, 10), g.PX * 1.7, f.flip, h3_deep_col(o, 1.35) if a < 0.3 else h3_deep_col(o), Vector2(0.5, 1.0))


## 身后常驻的苍白小水母（数量 = 触手追击数）
static func _h3mz_draw_jellies(o) -> void:
	var g = o.g
	var cv = o.cv
	var n: int = int(_h3_st(o, "t_n", 1.0))
	var c: Color = h3_tentacle_col(o)
	var jg = o.B.get("attack", _ED).get("look", {}).get("jelly_glow", null)
	var glow: bool = jg is Dictionary and cond_true(o, jg.get("cond", _ED))
	for k in n:
		var ang: float = g.t * 0.6 + k * TAU / float(n)
		var ph: float = g.t * 1.3 + k * 2.1
		var p: Vector2 = o.pos + Vector2(cos(ang) * 34.0, -34.0 + sin(ang) * 12.0 + sin(ph * 1.7) * 3.0)
		if _e3_draw_jelly(o, k):   # 精英化第 3 批：离身游猎中的水母
			continue
		if glow:
			cv.draw_circle(p, 13.0, Color(0.9, 0.6, 1.6, 0.16))
		if o._fx_strip("fx_mizuki_jelly", 4, int(g.t * 6.0) + k * 3, p + Vector2(0, 6)):
			continue
		cv.draw_set_transform(p, 0.0, Vector2(1.0, 0.62))
		cv.draw_circle(Vector2.ZERO, 8.5, Color(c.r, c.g, c.b, 0.6))
		cv.draw_arc(Vector2.ZERO, 8.5, PI, TAU, 14, Color(1.7, 1.9, 2.3, 0.9), 1.6)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for q in 3:
			var x0: float = (q - 1) * 4.0
			var pts := PackedVector2Array()
			for s in 5:
				pts.append(p + Vector2(x0 + sin(ph * 2.0 + s * 0.9 + q) * (1.0 + s * 0.9), 3.0 + s * 4.5))
			cv.draw_polyline(pts, Color(c.r, c.g, c.b, 0.65 - q * 0.08), 1.5)


static func _h3mz_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	_h3mz_draw_jellies(o)
	if o.s_t[1] > 0.0:
		var fade2 := clampf(o.s_t[1] / 1.0, 0.0, 1.0)
		for q in 10:
			var an = g.t * 2.6 + q * TAU / 10.0
			var p = o.pos + Vector2(cos(an) * 46.0, sin(an) * 20.0 - 26.0)
			var front := sin(an) > 0.0
			o.draw_diamond(p, 4.5 if front else 3.5, Color(0.02, 0.05, 0.08, fade2), Color(0.7, 1.3, 2.0, fade2 * (1.0 if front else 0.5)))
		for j in o.query_ids(o.pos, 320.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.stun < 0.15:
				continue
			for q in 3:
				var an2: float = g.t * 4.0 + q * TAU / 3.0 + e.id
				o.draw_diamond(e.pos + Vector2(cos(an2) * (e.r + 6.0), sin(an2) * (e.r + 6.0) * 0.4 - 4.0), 3.0, Color(0.02, 0.05, 0.08, 0.9), Color(0.6, 1.2, 2.0, 0.9))
	MizukiS3Fx.draw(o, true)


static func _h3mz_draw_auras(o) -> void:
	var g = o.g
	var cv = o.cv
	if o.s_t[1] > 0.0 and g.tex.get("fx_s2_aura") == null:
		cv.draw_arc(o.pos + Vector2(0, -10), 30.0 + sin(g.t * 6.0) * 2.0, 0.0, TAU, 20, Color(0.5, 0.8, 1.0, 0.6), 2.0)


static func _h3mz_draw_add(o, ci, loop: int) -> void:
	var g = o.g
	if o.s_t[1] > 0.0 and g.tex.get("fx_s2_aura") != null:
		o.draw_spr_on(ci, "fx_s2_aura", g.FXF.fx_s2_aura, loop, o.pos + Vector2(0, 4))
	var mark := "fx_s2_bind" if o.s_t[1] > 0.0 else "fx_stun"
	if g.tex.get(mark) != null:
		for e in g.enemies:
			if e.stun > 0.3:
				o.draw_spr_on(ci, mark, g.FXF[mark], loop + e.id, e.pos + Vector2(0, -e.r - 10))


static func _h3mz_status(o) -> Array:
	var items: Array = []
	var sk: Array = o.def.get("skills", [])
	if o.ammo[0] > 0:
		items.append(["%s ×%d" % [str(sk[0].get("name", "")), o.ammo[0]], H3_GOLD, -1.0])
	if o.s_t[1] > 0.0:
		items.append([str(sk[1].get("name", "")), Color(0.45, 0.8, 1.0), o.s_t[1] / maxf(0.01, o.s_dur[1])])
	if o.s_t[2] > 0.0:
		items.append([str(sk[2].get("name", "")), Color(0.62, 0.55, 1.0), o.s_t[2] / maxf(0.01, o.s_dur[2])])
	return items


static func _h3mz_rows(o) -> Array:
	var a: Dictionary = o.B.get("attack", {})
	var timing: Dictionary = o.sprite_spec("attack").get("attack_timing", {})
	var interval: float = h3_umbrella_interval(o, a)   # 整条缩放后面板间隔 = 实际间隔（不再抬到 min_duration + min_rest）
	var half: float = minf(180.0, float(a.get("half_deg", 75.0)) + _h3_st(o, "arc", 0.0))
	return [
		["伞击伤害", "%d" % int(o.base(str(a.get("atk_key", "atk")), 0.0) * _h3_st(o, "dmg", 1.0) * o.g.dmg_mult)], ["全局伤害", "×%.2f" % o.g.dmg_mult], ["挥伞间隔", "%.2f 秒" % max(float(a.get("min_cd", 0.18)), interval)],
		["挥砍半径", "%d" % int(float(a.get("r", 142.0)) * _h3_st(o, "area", 1.0))], ["挥砍角度", "%d°" % int(half * 2.0)], ["触手倍率", "×%.2f" % _h3_st(o, "t_mult", 0.6)],
		["追击目标", "%d" % int(_h3_st(o, "t_n", 1.0))], ["技力回复", "×%.2f" % o.g.sp_mult],
	]


# ---------------------------------------------------------------- docs/202 成长节点：缠住（强迫性重复 / 病理性依恋 / 重斩）
#  attack.tentacle.repeat {cond, window, bind}  触手追击同一敌人 window 秒内第二次命中 → 触手缠绕它 bind 秒（精英减半，Boss 除外；控制走 add_cc_growth）
#  attack.tentacle.hyst   {cond, hits, below, max}  伞击一次命中 ≥ hits 名 → 追击改为全体追击：生命低于 below 的被伞击敌人各挨一根（至多 max 根，不少于原追击数）
#  attack.tentacle.cling  {cond, dur, near, smash_window}  被精一「拖拽」拖到身边（或本来就在身边 near 内）的敌人被缠住 dur 秒（精英减半，Boss 除外），缠住期间水月移动时带着走
#  attack.tentacle.smash  {cond, mult}  被缠住的敌人（cling.smash_window 秒内）受到的下一次伞击 × mult，消耗一次；触手从其脚下钻出
# 同屏缠住记录 ≤ 16 条；画面只用 g.vrng

const G202_CLING_MAX := 16


static func _g202_st(mz: Dictionary) -> void:
	if not mz.has("cling"):
		mz["cling"] = []
	if not mz.has("rep"):
		mz["rep"] = {}


static func _g202_mz_tick(o, mz: Dictionary, dt: float) -> void:
	_g202_st(mz)
	var cur: Vector2 = o.pos
	var last: Vector2 = mz.get("lastp", cur)
	mz["lastp"] = cur
	var cl: Array = mz.cling
	if cl.is_empty():
		return
	var d := Vector2.ZERO
	if cur != Vector2.INF and last != Vector2.INF:
		d = cur - last
		if d.length() > 60.0:
			d = Vector2.ZERO   # 瞬移 / 回位不带人
	for c in cl:
		c.t = float(c.t) - dt
		c.mark = float(c.mark) - dt
		if c.carry and float(c.t) > 0.0 and d != Vector2.ZERO and not c.e.dead:
			o.nudge(c.e, d)
	mz.cling = cl.filter(func(c): return float(c.mark) > 0.0 and not c.e.dead)


## 强迫性重复：同一敌人 window 秒内被触手第二次命中 → 缠绕
static func _g202_repeat(o, tb: Dictionary, target: Dictionary, dmg: float) -> void:
	var rp: Dictionary = _h4_sub(o, tb.get("repeat", null))
	if rp.is_empty() or target.boss or target.dead:
		return
	var g = o.g
	var mz: Dictionary = o.hw.mz
	_g202_st(mz)
	var id: int = int(target.id)
	var last: float = float(mz.rep.get(id, -99.0))
	if g.t - last <= float(rp.get("window", 3.0)):
		mz.rep.erase(id)
		var dur: float = float(rp.get("bind", 0.5)) * (0.5 if target.elite else 1.0)
		o.add_cc_growth(target, dur)
		if float(rp.get("mult", 0.0)) > 0.0:   # 缠紧的那一下：再受一次触手伤害 × mult
			o.log_hit(str(tb.get("src", "")))
			o.deal_damage(target, dmg * float(rp.mult))
		_g202_add_cling(mz, target, dur, dur, false, false)
		o.fx({"kind": "ring", "pos": target.pos + Vector2(0, 4), "r": target.r + 18.0, "r0": target.r + 4.0, "life": 0.35, "col": h3_deep_col(o, 1.8), "floor": true, "w": 3.0, "alpha": 0.9})
	else:
		mz.rep[id] = g.t
		if mz.rep.size() > 48:
			for k in mz.rep.keys():
				if float(mz.rep[k]) < g.t - float(rp.get("window", 3.0)):
					mz.rep.erase(k)


## 病理性依恋：被拖到身边的敌人缠住
static func _g202_cling(o, tb: Dictionary, target: Dictionary, pulled: bool) -> void:
	var cb: Dictionary = _h4_sub(o, tb.get("cling", null))
	if cb.is_empty() or target.boss or target.dead:
		return
	if not pulled and target.pos.distance_to(o.pos) > float(target.r) + float(cb.get("near", 70.0)):
		return
	var mz: Dictionary = o.hw.mz
	_g202_st(mz)
	var dur: float = float(cb.get("dur", 0.8)) * (0.5 if target.elite else 1.0)
	var sm: Dictionary = _h4_sub(o, tb.get("smash", null))
	var mark: float = maxf(dur, float(cb.get("smash_window", 1.6))) if not sm.is_empty() else dur
	o.add_cc_growth(target, dur)
	_g202_add_cling(mz, target, dur, mark, true, not sm.is_empty())


static func _g202_add_cling(mz: Dictionary, e: Dictionary, t: float, mark: float, carry: bool, smash: bool) -> void:
	for c in mz.cling:
		if is_same(c.e, e):
			c.t = maxf(float(c.t), t)
			c.mark = maxf(float(c.mark), mark)
			c.carry = c.carry or carry
			c.smash = c.smash or smash
			return
	if mz.cling.size() >= G202_CLING_MAX:
		mz.cling.pop_front()
	mz.cling.append({"e": e, "t": t, "mark": mark, "carry": carry, "smash": smash, "ph": 0.0})


## 病理性依恋·重斩：被缠住（且带 smash 标记）的敌人吃的下一次伞击 × mult，消耗；返回倍率（没有 = 1）
static func _g202_smash_take(o, e: Dictionary, sm: Dictionary) -> float:
	var mz: Dictionary = o.hw.mz
	if not mz.has("cling"):
		return 1.0
	for i in mz.cling.size():
		var c: Dictionary = mz.cling[i]
		if is_same(c.e, e) and c.smash:
			mz.cling.remove_at(i)
			var g = o.g
			var p: Vector2 = e.pos
			g.fx.append({"kind": "rift", "pos": p, "r": 30.0, "life": 0.3, "max": 0.3})
			if not o.spawn_fx_sprite("fx_mizuki_tentacle", p + Vector2(0, 10), g.PX * 0.9, 0.0, g.vrng.randf() < 0.5, true, Color(1, 1, 1, 0.9)):
				g.fx.append({"kind": "tentacle", "pos": p, "life": 0.4, "max": 0.4, "flip": g.vrng.randf() < 0.5})
			g.fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 52.0, "life": 0.35, "max": 0.35, "col": Color(0.9, 0.6, 1.6), "op_hit": true})
			o.sparks(p + Vector2(0, 8), Vector2.UP, Color(0.9, 0.6, 1.6), 9, 240.0)
			return float(sm.get("mult", 1.5))
	return 1.0


## 画面：缠住的敌人脚下两道反向旋转的弧 + 一根从水月连过去的触须（smash 标记期间偏亮紫）
static func _g202_mz_draw(o) -> void:
	var mz: Dictionary = o.hw.mz
	if not mz.has("cling") or mz.cling.is_empty():
		return
	var g = o.g
	var cv = o.cv
	for c in mz.cling:
		var e: Dictionary = c.e
		if e.dead:
			continue
		var live: bool = float(c.t) > 0.0
		var col: Color = Color(0.9, 0.6, 1.6) if c.smash else h3_deep_col(o, 1.8)
		var al: float = (0.9 if live else 0.55) * clampf(float(c.mark) / 0.3, 0.0, 1.0)
		var fp: Vector2 = e.pos + Vector2(0, float(e.r) * 0.6)
		cv.draw_set_transform(fp, 0.0, Vector2(1.0, 0.45))
		var r0: float = float(e.r) + 5.0
		var an: float = g.t * 3.0 + float(e.id)
		cv.draw_arc(Vector2.ZERO, r0, an, an + TAU * 0.78, 18, Color(col.r, col.g, col.b, al), 2.5)
		cv.draw_arc(Vector2.ZERO, r0 + 4.0, -an, -an + TAU * 0.6, 16, Color(col.r, col.g, col.b, al * 0.7), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if c.carry and live and o.pos != Vector2.INF:
			var a0: Vector2 = o.pos + Vector2(0, -10)
			var a1: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.4)
			var pts := PackedVector2Array()
			var nrm: Vector2 = (a1 - a0).orthogonal().normalized()
			for s in 7:
				var u: float = float(s) / 6.0
				pts.append(a0.lerp(a1, u) + nrm * sin(u * PI * 2.0 + g.t * 9.0) * 5.0 * sin(u * PI))
			cv.draw_polyline(pts, Color(col.r, col.g, col.b, al * 0.8), 2.0)


# ---------------------------------------------------------------- 水月：拖拽 / 深蓝之籽

static func _e3_pull(o, a: Dictionary, target: Dictionary) -> bool:
	var pl = a.get("tentacle", _ED).get("pull", null)
	if not (pl is Dictionary) or target.dead or not cond_true(o, pl.get("cond", _ED)):
		return false
	if displace_one(o, target, o.pos, pl):
		o.spawn_fx_sprite(str(pl.get("fx", "fx_mizuki_tentacle_curl")), target.pos + Vector2(0, -target.r * 0.5), o.g.PX * 0.8, 0.0, target.pos.x > o.pos.x)
		return true
	return false


## 第 k 只水母在身后的位置（同常驻画法）
static func _e3_jelly_home(o, k: int, n: int) -> Vector2:
	var g = o.g
	var ang: float = g.t * 0.6 + k * TAU / float(maxi(1, n))
	var ph: float = g.t * 1.3 + k * 2.1
	return o.pos + Vector2(cos(ang) * 34.0, -34.0 + sin(ang) * 12.0 + sin(ph * 1.7) * 3.0)


static func _e3_jelly_on(o) -> Dictionary:
	var jb = o.B.get("attack", _ED).get("jelly", null)
	if jb is Dictionary and cond_true(o, jb.get("cond", _ED)):
		return jb
	return {}


static func _e3_jelly_tick(o, mz: Dictionary, dt: float) -> void:
	var jb := _e3_jelly_on(o)
	if not mz.has("jel"):
		mz["jel"] = []
		mz["marks"] = {}
		mz["binds"] = []
	if jb.is_empty() or o.pos == Vector2.INF:
		mz.jel = []
		return
	var g = o.g
	var n: int = int(_h3_st(o, "t_n", 1.0))
	while mz.jel.size() < n:
		var k0: int = mz.jel.size()
		mz.jel.append({"ph": "home", "cd": 0.3 * k0, "p": _e3_jelly_home(o, k0, n), "v": Vector2.ZERO, "tgt": {}, "t": 0.0})
	while mz.jel.size() > n:
		mz.jel.pop_back()
	var rr: float = float(jb.get("r", 200.0)) * o.stat(&"op_range")
	var every: float = float(jb.get("every", 1.2))
	for m in jb.get("every_mults", _EA):
		if cond_true(o, m.get("cond", _ED)):
			every *= float(m.get("mult", 1.0))
	for k in n:
		var j: Dictionary = mz.jel[k]
		var home: Vector2 = _e3_jelly_home(o, k, n)
		match str(j.ph):
			"home":
				j.p = home
				j.cd = float(j.cd) - dt
				if float(j.cd) <= 0.0:
					var tgt := _e3_jelly_pick(o, mz, rr, k)
					if tgt.is_empty():
						j.cd = 0.25
					else:
						j.ph = "out"
						j.tgt = tgt
						j.t = 0.0
			"out":
				j.t = float(j.t) + dt
				var e: Dictionary = j.tgt
				if e.dead or float(j.t) > float(jb.get("max_t", 1.0)):
					j.ph = "back"
					continue
				var to: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
				var dv: Vector2 = to - (j.p as Vector2)
				var step: float = float(jb.get("speed", 420.0)) * dt
				if dv.length() <= step + float(e.r) * 0.5 + 4.0:
					j.p = to
					_e3_sting(o, jb, e)
					j.ph = "back"
				else:
					j.v = dv.normalized() * float(jb.get("speed", 420.0))
					j.p = (j.p as Vector2) + dv.normalized() * step
			"back":
				var dv2: Vector2 = home - (j.p as Vector2)
				var st2: float = float(jb.get("back", 160.0)) * dt
				if dv2.length() <= st2 + 2.0:
					j.p = home
					j.ph = "home"
					j.cd = every
				else:
					j.v = dv2.normalized() * float(jb.get("back", 160.0))
					j.p = (j.p as Vector2) + dv2.normalized() * st2
	for bd in mz.binds:
		bd.t = float(bd.t) - dt
	mz.binds = mz.binds.filter(func(x): return float(x.t) > 0.0 and not x.e.dead)


## 选目标：r 内、别的水母没盯上的；最近被触手打过的优先，其次最近的
static func _e3_jelly_pick(o, mz: Dictionary, rr: float, k: int) -> Dictionary:
	var g = o.g
	var taken := {}
	for q in mz.jel.size():
		var jq: Dictionary = mz.jel[q]
		if q != k and str(jq.ph) == "out" and not jq.tgt.is_empty():
			taken[int(jq.tgt.id)] = true
	var first := {}
	for e in o.nearest_enemies(10, rr, o.pos):
		if e.dead or taken.has(int(e.id)):
			continue
		if float(mz.marks.get(int(e.id), -99.0)) > float(g.t) - 3.0:
			return e
		if first.is_empty():
			first = e
	return first


static func _e3_sting(o, jb: Dictionary, e: Dictionary) -> void:
	var g = o.g
	var mz: Dictionary = o.hw.mz
	var a: Dictionary = o.B.get("attack", {})
	var dmg: float = o.base(str(a.get("atk_key", "atk")), 0.0) * _h3_st(o, "dmg", 1.0) * o._dmg_bonus()
	for m in a.get("dmg_mults", _EA):
		if cond_true(o, m.get("cond", _ED)):
			dmg *= float(m.get("mult", 1.0))
	o.log_hit(str(jb.get("src", "")))
	o.deal_damage(e, dmg * float(jb.get("mult", 0.4)))
	if not e.dead and not e.boss:
		var sd: float = float(jb.get("stun", 0.3)) * (0.5 if e.elite else 1.0)
		o.add_cc(e, sd)
		mz.binds.append({"e": e, "t": sd})
	if not o.spawn_fx_sprite(str(jb.get("sting_fx", "fx_mizuki_jelly_sting")), e.pos + Vector2(0, -e.r * 0.5), g.PX):
		o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.2, "col": Color(0.9, 0.6, 1.6), "alpha": 0.6})


static func _e3_mark(o, e: Dictionary) -> void:
	var mz: Dictionary = o.hw.mz
	if not mz.has("marks") or _e3_jelly_on(o).is_empty():
		return
	mz.marks[int(e.id)] = float(o.g.t)
	if mz.marks.size() > 64:
		for kk in mz.marks.keys():
			if float(mz.marks[kk]) < float(o.g.t) - 3.0:
				mz.marks.erase(kk)


## 水母画法（_h3mz_draw_jellies 转来）：在外的画拉长的水滴形 + 淡紫细尾；返回 true = 已画
static func _e3_draw_jelly(o, k: int) -> bool:
	var mz: Dictionary = o.hw.mz
	if not mz.has("jel") or k >= mz.jel.size():
		return false
	var j: Dictionary = mz.jel[k]
	if str(j.ph) == "home":
		return false
	var g = o.g
	var cv = o.cv
	var p: Vector2 = j.p
	var v: Vector2 = j.v
	var ang: float = v.angle() if v.length() > 1.0 else 0.0
	cv.draw_line(p - v.normalized() * 14.0, p, Color(0.9, 0.65, 1.5, 0.45), 2.0)
	if g.tex.get("fx_mizuki_jelly_dart") != null:
		fx_frame(cv, g, "fx_mizuki_jelly_dart", 6, int(g.t * 14.0 + k * 2) % 6, p, g.PX, Color.WHITE, Vector2(-1, -1), ang)
		return true
	return false


static func _e3_draw_binds(o) -> void:
	var mz: Dictionary = o.hw.mz
	if not mz.has("binds"):
		return
	var g = o.g
	var cv = o.cv
	for bd in mz.binds:
		var e: Dictionary = bd.e
		var bp: Vector2 = e.pos + Vector2(0, float(e.r) * 0.6)
		if g.tex.get("fx_mizuki_bind_ring") != null:
			fx_frame(cv, g, "fx_mizuki_bind_ring", 6, int(g.t * 10.0) % 6, bp, g.PX * clampf(float(e.r) / 10.0, 1.0, 2.0), Color(1, 1, 1, 0.9))
		else:
			cv.draw_set_transform(bp, 0.0, Vector2(1.0, 0.45))
			cv.draw_arc(Vector2.ZERO, float(e.r) + 4.0, 0.0, TAU, 20, Color(0.9, 0.65, 1.5, 0.8), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
