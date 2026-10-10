## 最后的骑士（type knight_boss，docs/38 §2.7 / §8.8）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 最后的骑士（结局二）：冲锋（直线预警→突进+冰霜）/ 长枪连刺（近身三段扇形）/ 寒冰领域（20 秒一次，200 半径减速 6 秒）
	# 二阶段（首次归零后重生）：移速 +20%，冲锋连续两次
	var ice := Color(0.6, 0.9, 1.4)
	if e.get("channel", 0.0) > 0.0:
		e.channel -= dt
		if e.channel <= 0.0:
			e.invuln = false
	if e.get("frost_t", 0.0) > 0.0:
		e.frost_t -= dt
		if g.combat.ground_d(g.ppos, e.frost_pos) < 200.0:
			g.combat.frost_leader(0.15, "boss")   # 寒冰领域：控制遥测记为 Boss 来源
	_knight_stakes(e, dt)
	# 二阶段冲锋一组 1 + boss/knight_p2_chain 次（缺省 3 次一组），组后喘气 2.5 秒（普通破绽，docs/38 §8.8）
	if int(e.get("dash2", 0)) > 0 and e.get("dash_t", 0.0) <= 0.0 and e.get("wind", 0.0) <= 0.0:
		e.dash2 = int(e.dash2) - 1
		var rw := _warn(e, "line", 0.6, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.3, "act": "dash", "fit_len": true, "name": "再冲锋", "col": ice, "dmg": e.dmg * Bal.v("boss/knight_charge_mult", 1.7)})
		if int(e.dash2) <= 0:
			e.breath_at = g.t + rw.dur + 0.6
	if e.has("breath_at") and g.t >= float(e.breath_at):
		e.erase("breath_at")
		g.combat.start_break(e, Bal.v("boss/knight_breath", 2.5))
	if ready and e.channel <= 0.0 and e.get("wind", 0.0) <= 0.0:
		if e.age > 6.0 and _cd(e, "frost", 20.0):
			_warn(e, "circle", 1.0, {"follow": true, "r": 200.0, "act": "frost", "name": "寒冰领域", "col": ice, "dmg": e.dmg * 0.5})
		elif dist < 140.0 and _cd(e, "stab", 5.0):
			# 三段连刺：每段间隔 0.6 秒、每段锁定 0.4 秒（§1.9 连发间隔、docs/48 P0-2）
			for k in 3:
				_warn(e, "cone", 0.6 + 0.6 * k, {"ang": dir.angle(), "half": 0.8, "r": 125.0, "track": 0.2 + 0.6 * k, "act": "bite", "name": "长枪连刺" if k == 0 else "", "col": ice, "dmg": e.dmg * 1.1, "lock": k == 0})
			e.wind = 1.9
		elif dist >= 140.0 and _cd(e, "charge", 4.5 if e.phase == 2 else 6.0):
			_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.4, "act": "dash", "fit_len": true, "name": "冲锋", "col": ice, "dmg": e.dmg * Bal.v("boss/knight_charge_mult", 1.7)})
			if e.phase == 2:
				e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	e.phase = 2
	e.hp = e.maxhp * 0.5
	e.spd *= 1.2
	e.invuln = true
	e.channel = 1.5
	e.stun = 0.0
	e.kb = Vector2.ZERO
	g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0)


## ---- 最后的骑士：冰枪桩（docs/38 §8.8）。66% 卡点后长枪插地，场上立 boss/knight_stakes（3）根冰枪桩（r 22），离主控 ≥120、
## 离场地边 ≥100，每根存在 12 秒，少于 2 根时补。冰枪桩只挡骑士：冲锋路径碰到桩 → 长枪脱手，5 秒大破绽，桩碎。
## 主控和子弹都不受影响（不需要动态障碍表）。冲锋预警会标出这一冲会不会撞桩（w.stake_hit，画面画「破」字端盖）
func _knight_stakes(e: Dictionary, dt: float) -> void:
	if int(e.get("gates_passed", 0)) < 1:
		return
	if not e.has("stakes"):
		e.stakes = []
		g.vfx.add_text(e.pos + Vector2(0, -70), "长枪插地 · 冰枪桩", Color(0.6, 0.9, 1.4), 18)
	if e.stakes.any(func(s): return float(s.until) > 0.0 and g.t >= float(s.until)):   # 冰枪桩到期碎裂（撞桩的 until 置 0，不算）
		Sfx.play("stake_shatter", -6.4, 1.0, 0.0)
		for s in e.stakes:
			if float(s.until) > 0.0 and g.t >= float(s.until):
				g.vfx.fx_sprite("prop_ice_stake_break", s.pos, g.PX, 0.0, false, true, Color(1, 1, 1, 0.5))   # 自然到期：碎裂帧条半透明（v14）
	e.stakes = e.stakes.filter(func(s): return g.t < float(s.until))
	if e.stakes.size() < 2:
		var want: int = int(Bal.v("boss/knight_stakes", 3.0))
		var tries := 0
		while e.stakes.size() < want and tries < 20:
			tries += 1
			var p: Vector2 = g.combat.arena_clamp(g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(160.0, 320.0), 100.0)
			if p.distance_to(g.ppos) < 120.0:
				continue
			e.stakes.append({"pos": p, "until": g.t + Bal.v("boss/knight_stake_life", 12.0)})
			g.fx.append({"kind": "gcrack", "pos": p, "r": 66.0, "life": 0.9, "max": 0.9, "col": Color(0.55, 0.85, 1.3), "enemy": true, "opts": {"n": 6, "w0": Vector2(3.0, 4.5)}})   # 冰枪桩落地：小冰裂（纯画面，界面与美术 10-01）
	# 冲锋中撞桩
	if e.get("kb_self", false) and e.kb.length() > 100.0:
		for s in e.stakes:
			if e.pos.distance_to(s.pos) < e.r + 22.0:
				e.kb = Vector2.ZERO
				e.kb_self = false
				e.dash_t = 0.0
				e.dash2 = 0
				e.erase("breath_at")
				s.until = 0.0
				g.vfx.fx_sprite("prop_ice_stake_break", s.pos, g.PX, 0.0, false, true)   # 撞桩碎裂（Codex v14 prop_ice_stake_break）
				g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
				g.combat.start_break(e, Bal.v("boss/knight_stake_break", 5.0))
				Sfx.play("stake_hit", 2.0, 1.0, 0.0)   # 撞桩、长枪脱手
				g.fx.append({"kind": "ring", "pos": s.pos, "r": 70.0, "life": 0.5, "max": 0.5, "col": Color(0.6, 0.9, 1.4), "enemy": true})
				g.vfx.sparks(s.pos, Vector2.UP, Color(0.8, 1.2, 1.6), 16, 260.0)
				g.vfx.add_text(e.pos + Vector2(0, -70), "长枪脱手！", Color(1.0, 0.85, 0.4), 22)
				Sfx.play("boom", -4.0, 1.2, 0.0)
				break
