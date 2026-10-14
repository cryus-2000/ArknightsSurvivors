## 最后的骑士（type knight_boss，docs/38 §2.7 / §8.8；招式改版 docs/95 §4，10-14）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 冲锋（②；冰线 → 寒冷追击是它的变体，用户 10-14 定保留）/ B 长枪连刺（③ 三段，第 3 段前刺）/ C 寒冷（① 受击触发：打他越勤越冷）/ D 长枪回旋（④ 二阶段缺口环）
## 机制不占名额：冰枪桩 / 撞桩破绽、重生、喘气破绽
extends "res://scripts/enemies/bosses/boss_base.gd"

const ICE := Color(0.6, 0.9, 1.4)
const MOVES := ["冲锋", "冰线", "长枪连刺", "寒冷", "长枪回旋"]


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	if e.get("channel", 0.0) > 0.0:
		e.channel -= dt
		if e.channel <= 0.0:
			e.invuln = false
	if e.get("frost_t", 0.0) > 0.0:
		# 寒冷留下的冰面（r180，6 秒）：只减速（−20%，§1.9「只减速地形」）；控制遥测记为 Boss 来源
		e.frost_t -= dt
		if g.combat.ground_d(g.ppos, e.frost_pos) < 180.0:
			g.combat.slow_leader("ice_floor", 0.2, 0.8, "boss")
	_knight_stakes(e, dt)
	# 二阶段冲锋一组 1 + boss/knight_p2_chain 次（缺省 3 次一组），第一次全长、后两次 70%（docs/49d 11.8），组后喘气 2.5 秒（普通破绽，docs/38 §8.8）
	if int(e.get("dash2", 0)) > 0 and e.get("dash_t", 0.0) <= 0.0 and e.get("wind", 0.0) <= 0.0:
		e.dash2 = int(e.dash2) - 1
		var rw := _warn(e, "line", 0.6, {"ang": dir.angle(), "len": 364.0, "wid": 34.0, "track": 0.3, "act": "dash", "fit_len": true, "name": "再冲锋", "col": ICE, "dmg": e.dmg * Bal.v("boss/knight_charge_mult", 1.7)})
		if int(e.dash2) <= 0:
			e.breath_at = g.t + rw.dur + 0.6
	if e.has("breath_at") and g.t >= float(e.breath_at):
		e.erase("breath_at")
		g.combat.start_break(e, Bal.v("boss/knight_breath", 2.5))
	if not (ready and e.channel <= 0.0 and e.get("wind", 0.0) <= 0.0):
		return
	# 冰线之后的寒冷追击（沿冰线冲锋）：最高优先；二阶段它就是三连的第一冲
	if g.t >= float(e.get("hunt_follow_at", INF)):
		e.hunt_follow_at = INF
		_warn(e, "line", 0.7, {"ang": float(e.get("hunt_angle", dir.angle())), "len": 520.0, "wid": 32.0,
			"fit_len": true, "act": "dash", "name": "寒冷追击", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 1.35})
		if e.phase == 2:
			e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))
		return
	# C 寒冷（受击触发，插队）：8 秒窗口内累计受到 ≥ knight_frost_pct（6%）最大生命的伤害，且主控在 r180 内；frost 10 秒
	if _frost_due(e, dist) and _cd(e, "frost", 10.0):
		_frost(e)
		return
	if dist < 160.0 and e.phase == 2 and float(e.get("cds", {}).get("spin", 0.0)) <= g.t:
		# D 长枪回旋：二阶段近身先回旋后连刺（和连刺互斥）；第一次先亮招式名 0.6 秒（§0.2）
		if _first_tell(e, "spin", "长枪回旋") and _cd(e, "spin", 7.0):
			_spin(e, dir)
		return
	if dist < 140.0 and _cd(e, "stab", 5.0):
		_stab(e, dir)
	elif dist >= 140.0 and _cd(e, "charge", 4.5 if e.phase == 2 else 6.0):
		# A 冲锋；冰线是它的变体：hunt 冷却到了（18 秒）且主控在 120–600 时改放冰线，0.25 秒后沿线寒冷追击
		if Bal.v("boss/knight_hunt", 1.0) > 0.0 and dist >= 120.0 and dist <= 600.0 and _cd(e, "hunt", 18.0):
			_hunt(e, dir, dist)
		else:
			_charge(e, dir)


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	e.phase = 2
	e.hp = e.maxhp * 0.5
	e.spd *= 1.2
	e.invuln = true
	e.channel = 1.5
	e.stun = 0.0
	e.kb = Vector2.ZERO
	e.frost_taken = 0.0
	_tint2(e, Color(0.82, 0.92, 1.25))
	g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	match name:
		"冲锋":
			_charge(e, dir)
		"冰线":
			_hunt(e, dir, dist)
		"长枪连刺":
			_stab(e, dir)
		"寒冷":
			_frost(e)
		"长枪回旋":
			if e.phase != 2:
				return false
			_spin(e, dir)
		_:
			return false
	return true


## A · 冲锋：520 × 34 条纹线，追踪 0.4 秒后锁定，总 0.8 秒；e.dmg × 1.7（冲锋期间碰到结算一次）；二阶段带三连
func _charge(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.4, "act": "dash", "fit_len": true, "name": "冲锋", "col": ICE, "dmg": e.dmg * Bal.v("boss/knight_charge_mult", 1.7)})
	if e.phase == 2:
		e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))


## A 变体 · 冰线（用户 9/28 加、10-14 定保留）：细线 18 宽、追踪 0.25，结算留冰脊并标出追击方向，0.25 秒后「寒冷追击」沿线冲锋
func _hunt(e: Dictionary, dir: Vector2, dist: float) -> void:
	_warn(e, "line", 0.85, {"ang": dir.angle(), "len": clampf(dist + 60.0, 240.0, 560.0), "wid": 18.0,
		"track": 0.25, "act": "frost_track", "name": "冰线", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 0.4})


## B · 长枪连刺：三段扇形，每段间隔 0.6 秒、锁定 0.4 秒；前两段 r125 半角 0.8，第 3 段改 r150 半角 0.5 的前刺（更长更窄，锁定 ≥0.44）；e.dmg × 1.1 / 段
func _stab(e: Dictionary, dir: Vector2) -> void:
	for k in 3:
		var thrust: bool = k == 2
		_warn(e, "cone", 0.6 + 0.6 * k, {"ang": dir.angle(), "half": 0.5 if thrust else 0.8, "r": 150.0 if thrust else 125.0, "track": 0.2 + 0.6 * k,
			"act": "bite", "name": "长枪连刺" if k == 0 else "", "col": ICE, "dmg": e.dmg * 1.1, "lock": k == 0, "thrust": thrust})
	e.wind = 1.9


## C · 寒冷（PRTS「受到伤害时给伤害来源附加寒冷 2 秒，生命低于 50% 延长到 4 秒」）：以骑士为心 r180 实填圈，前 0.4 秒跟随本体、后 0.8 秒锁定（总 1.2）；
## e.dmg × 0.5，命中附寒冷（一阶段 2 秒、二阶段 4 秒；走冰霜，受移速下限 0.7）；留下 r180 冰面 6 秒（只减速 −20%）
func _frost(e: Dictionary) -> void:
	e.frost_taken = 0.0
	e.frost_win_t = g.t
	_warn(e, "circle", 1.2, {"track": 0.4, "track_pos": "self", "r": 180.0, "act": "frost", "name": "寒冷", "col": ICE, "dmg": e.dmg * 0.5,
		"chill": 4.0 if e.phase == 2 else 2.0})


## D · 长枪回旋（二阶段，本作原创）：以骑士为心 r150 的空心环（刀光轨迹），缺口在面向主控的反方向 ±40°（弧长 ≥80px），总 1.0 秒；
## 躲法：走进缺口（绕到他身后）或走出 r150；e.dmg × 1.3，附寒冷 2 秒
func _spin(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "circle", 1.0, {"follow": true, "r": 150.0, "act": "spin_ring", "gap_ang": dir.angle() + PI, "gap_half": 0.7, "ang": dir.angle(),
		"name": "长枪回旋", "col": ICE, "dmg": e.dmg * 1.3, "chill": 2.0})


## 寒冷的受击条件（combat.damage 累计 e.frost_taken，8 秒滑窗）
func _frost_due(e: Dictionary, dist: float) -> bool:
	if dist >= 180.0:
		return false
	if g.t - float(e.get("frost_win_t", -99.0)) > Bal.v("boss/knight_frost_win", 8.0):
		return false
	return float(e.get("frost_taken", 0.0)) >= e.maxhp * Bal.v("boss/knight_frost_pct", 0.06)


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
