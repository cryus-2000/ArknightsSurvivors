## 最后的骑士（type knight_boss，docs/38 §2.7 / §8.8；招式改版 docs/95 §4，10-14；主轴改版 docs/142b §3.1 / §8.2 样板，10-25）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 主轴「斗牛」：平时重甲（受伤 × knight_armor 0.4），引它冲锋撞上冰柱 → 眩晕 knight_stake_break（2.5）秒（受伤 × knight_break_taken 2.0；用户 10-25「撞上冰柱之后让他眩晕一会」）。
##   原作反冻（受到伤害时给来源附加寒冷）按自动攻击改成「寒气圈」：队长在它脚下 knight_cold_r 内寒冷条上涨，满了冻伤（减速 + 下一击 × 1.75，原作打冻结 175%）。
##   五根冰柱分散成批；全部撞完后统一预告再生，不到期、不由掷枪或转幕补齐。
##   二幕「冰原」（66%）：桩撞一次就碎、不再自动补，靠新招「掷枪」落地立桩（最多 4 根）；冲锋路径留冰面 3 秒，站上去寒冷条照涨
##   三幕「掷枪」（33%）：掷枪两连；冲锋后再转向冲一次（折线）；寒气圈 180、冻伤更久
##   重生「冲锋形态」（原作）：桩挡不住它（撞碎继续冲）；平时走得慢（× knight_reborn_spd 0.5），靠冲锋三连追人，连冲后喘气破绽；
##       重生时原作「释放当前波次」：刷一波 knight_rebirth_wave（16）只
## 最终 Boss 保留已有小怪，停止普通刷新；重生那一波属于机制召唤。
extends "res://scripts/enemies/bosses/boss_base.gd"

const ICE := Color(0.6, 0.9, 1.4)
const MOVES := ["冲锋", "冰线", "长枪连刺", "掷枪", "长枪回旋"]


## 当前第几幕：0 = 一幕，1 = 二幕（66%），2 = 三幕（33%）；重生后按 phase 2 另算
func _act(e: Dictionary) -> int:
	return int(e.get("gates_passed", 0))


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	if e.get("channel", 0.0) > 0.0:
		e.channel -= dt
		if e.channel <= 0.0:
			e.invuln = false
	if e.has("brk_label") and float(e.get("break_t", 0.0)) <= 0.0:
		e.erase("brk_label")   # 撞柱眩晕 / 喘气破绽结束：别的破绽（韧性）照旧写「破绽」
	elif str(e.get("brk_label", "")) == "眩晕":
		# 撞柱眩晕期间完全定住：不走（wind 让移动速度为 0）、不被击退、不转向（enemies.gd 每帧按主控方向翻面，这里改回撞柱时的朝向）
		e.wind = maxf(float(e.get("wind", 0.0)), float(e.break_t))
		e.kb = Vector2.ZERO
		e.fx = float(e.get("stun_fx", e.fx))
	_knight_stakes(e, dt)
	_cold_step(e, dt)
	_ice_step(e)
	# 连冲：重生后一组 1 + knight_p2_chain 次（第一次全长、后两次 70%，docs/49d 11.8）；三幕冲锋后再转向冲一次。连冲完喘气 2.5 秒（普通破绽，docs/38 §8.8）
	if int(e.get("dash2", 0)) > 0 and e.get("dash_t", 0.0) <= 0.0 and e.get("wind", 0.0) <= 0.0:
		e.dash2 = int(e.dash2) - 1
		var rw := _warn(e, "line", 0.6, {"ang": dir.angle(), "len": 364.0, "wid": 34.0, "track": 0.3, "act": "dash", "fit_len": true, "name": "再冲锋", "col": ICE,
			"dmg": _bite(e, e.dmg * Bal.v("boss/knight_charge_mult", 1.7))})
		if int(e.dash2) <= 0:
			e.breath_at = g.t + rw.dur + 0.6
	if e.has("breath_at") and g.t >= float(e.breath_at):
		e.erase("breath_at")
		g.combat.start_break(e, Bal.v("boss/knight_breath", 2.5))
		e.brk_label = "破绽"
	if not (ready and e.channel <= 0.0 and e.get("wind", 0.0) <= 0.0):
		return
	# 冰线之后的寒冷追击（沿冰线冲锋）：最高优先；二阶段它就是三连的第一冲
	if g.t >= float(e.get("hunt_follow_at", INF)):
		e.hunt_follow_at = INF
		_warn(e, "line", 0.7, {"ang": float(e.get("hunt_angle", dir.angle())), "len": 520.0, "wid": 32.0,
			"fit_len": true, "act": "dash", "name": "寒冷追击", "col": Color(0.65, 0.95, 1.4), "dmg": _bite(e, e.dmg * 1.35)})
		if e.phase == 2:
			e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))
		return
	if dist < 160.0 and e.phase == 2 and float(e.get("cds", {}).get("spin", 0.0)) <= g.t:
		# D 长枪回旋：二阶段近身先回旋后连刺（和连刺互斥）；第一次先亮招式名 0.6 秒（§0.2）——喘气结束时还贴着它就吃这一下
		if _first_tell(e, "spin", "长枪回旋") and _cd(e, "spin", 7.0):
			_spin(e, dir)
		return
	# 掷枪（二幕起，重生后不放）：桩少于 4 根、主控在 160–620 时；落点立一根新桩（_spear_land）
	if e.phase == 1 and _act(e) >= 1 and dist >= 160.0 and dist <= 620.0 \
			and _cd(e, "spear", Bal.v("boss/knight_spear_cd", 8.0)):
		_spear(e, dir, dist)
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
	e.spd *= Bal.v("boss/knight_reborn_spd", 0.5)
	e.invuln = true
	e.channel = 1.5
	e.stun = 0.0
	e.kb = Vector2.ZERO
	e.stakes = []
	_tint2(e, Color(0.82, 0.92, 1.25))
	g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES + g.bai.finals.NAMES["knight_boss"]


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if g.bai.finals.force_move(e, name, dir, dist):
		return true
	match name:
		"冲锋":
			_charge(e, dir)
		"冰线":
			_hunt(e, dir, dist)
		"长枪连刺":
			_stab(e, dir)
		"掷枪":
			if e.phase != 1:
				return false
			_spear(e, dir, dist)
		"长枪回旋":
			if e.phase != 2:
				return false
			_spin(e, dir)
		_:
			return false
	return true


## 冻伤的下一击 × knight_frostbite_mult（1.75，原作「攻击冻结目标攻击力 175%」）：放招时消耗
func _bite(e: Dictionary, dmg: float) -> float:
	if e.get("frostbite_hit", false):
		e.frostbite_hit = false
		return dmg * Bal.v("boss/knight_frostbite_mult", 1.75)
	return dmg


## A · 冲锋：520 × 34 条纹线，追踪 0.4 秒后锁定，总 0.8 秒；e.dmg × 1.7（冲锋期间碰到结算一次）；重生后带三连；三幕后面再转向冲一次（折线）
func _charge(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.4, "act": "dash", "fit_len": true, "name": "冲锋", "col": ICE,
		"dmg": _bite(e, e.dmg * Bal.v("boss/knight_charge_mult", 1.7))})
	if e.phase == 2:
		e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))
	elif _act(e) >= 2:
		e.dash2 = 1


## A 变体 · 冰线（用户 9/28 加、10-14 定保留）：细线 18 宽、追踪 0.25，结算留冰脊并标出追击方向，0.25 秒后「寒冷追击」沿线冲锋
func _hunt(e: Dictionary, dir: Vector2, dist: float) -> void:
	_warn(e, "line", 0.85, {"ang": dir.angle(), "len": clampf(dist + 60.0, 240.0, 560.0), "wid": 18.0,
		"track": 0.25, "act": "frost_track", "name": "冰线", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 0.4})


## B · 长枪连刺：三段扇形，每段间隔 0.6 秒、锁定 0.4 秒；前两段 r125 半角 0.8，第 3 段改 r150 半角 0.5 的前刺（更长更窄，锁定 ≥0.44）；e.dmg × 1.1 / 段
func _stab(e: Dictionary, dir: Vector2) -> void:
	var m: float = _bite(e, e.dmg * 1.1)
	for k in 3:
		var thrust: bool = k == 2
		_warn(e, "cone", 0.6 + 0.6 * k, {"ang": dir.angle(), "half": 0.5 if thrust else 0.8, "r": 150.0 if thrust else 125.0, "track": 0.2 + 0.6 * k,
			"act": "bite", "name": "长枪连刺" if k == 0 else "", "col": ICE, "dmg": m, "lock": k == 0, "thrust": thrust})
	e.wind = 1.9


## 掷枪（本作拟，docs/142b §3.1 / §8.2；二幕起）：朝主控掷出长枪，直线 14 宽、追踪 0.4 秒、总 1.0 秒；e.dmg × 1.0；
## 落地处立一根新冰枪桩（_spear_land 读 last_act）——它是威胁，也是你下一次引它撞桩的资源。三幕两连（第二枪晚 0.6 秒，各自追踪）
func _spear(e: Dictionary, dir: Vector2, dist: float) -> void:
	var n: int = 2 if _act(e) >= 2 else 1
	for k in n:
		_warn(e, "line", 1.0 + 0.6 * k, {"ang": dir.angle(), "len": clampf(dist, 160.0, 520.0), "wid": 14.0, "track": 0.4 + 0.6 * k, "act": "shot",
			"name": "掷枪", "col": Color(0.75, 0.95, 1.4), "dmg": e.dmg, "lock": k == 0, "spear": true})


## D · 长枪回旋（二阶段，本作原创）：以骑士为心 r150 的空心环（刀光轨迹），缺口在面向主控的反方向 ±40°（弧长 ≥80px），总 1.0 秒；
## 躲法：走进缺口（绕到他身后）或走出 r150；e.dmg × 1.3，附寒冷 2 秒
func _spin(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "circle", 1.0, {"follow": true, "r": 150.0, "act": "spin_ring", "gap_ang": dir.angle() + PI, "gap_half": 0.7, "ang": dir.angle(),
		"name": "长枪回旋", "col": ICE, "dmg": _bite(e, e.dmg * 1.3), "chill": 2.0})


## 寒气圈与寒冷条（原作反冻，按自动攻击改，docs/142b §3.1）：队长在 kcold_r 内、或站在冲锋留下的冰面上 → 寒冷条每秒涨 1 / knight_cold_fill；
## 不在 → 每秒落 1 / knight_cold_decay。破绽期间不涨。满了「冻伤」：knight_frostbite 秒减速（受 Boss 战移速下限 0.7）、下一击 × 1.75，然后清零
func _cold_step(e: Dictionary, dt: float) -> void:
	e.kcold_r = Bal.v("boss/knight_cold_r3", 180.0) if (_act(e) >= 2 and e.phase == 1) else Bal.v("boss/knight_cold_r", 140.0)
	if e.phase == 2 or float(e.get("break_t", 0.0)) > 0.0 or e.get("invuln", false):
		e.kcold = maxf(0.0, float(e.get("kcold", 0.0)) - dt / Bal.v("boss/knight_cold_decay", 2.5))
		return
	var near: bool = g.combat.ground_d(g.ppos, e.pos) < float(e.kcold_r)
	var on_ice: bool = false
	for s in e.get("ice_strips", []):
		if Geometry2D.get_closest_point_to_segment(g.ppos, s.a, s.b).distance_to(g.ppos) < 26.0:
			on_ice = true
			break
	if near or on_ice:
		e.kcold = float(e.get("kcold", 0.0)) + dt / Bal.v("boss/knight_cold_fill", 3.0)
	else:
		e.kcold = maxf(0.0, float(e.get("kcold", 0.0)) - dt / Bal.v("boss/knight_cold_decay", 2.5))
	if float(e.kcold) >= 1.0:
		e.kcold = 0.0
		var t: float = Bal.v("boss/knight_frostbite", 1.5) * (1.35 if _act(e) >= 2 else 1.0)
		e.frostbite_until = g.t + t
		e.frostbite_hit = true
		g.combat.slow_leader("knight_frostbite", t, 0.5)
		g.combat.frost_leader(t, "boss")
		g.vfx.add_text(g.ppos + Vector2(0, -104), "冻伤！下一击加重", Color(0.75, 0.95, 1.4), 16)
		g.vfx.sparks(g.ppos, Vector2.UP, Color(0.8, 1.2, 1.6), 12, 160.0)
		Sfx.play("stake_shatter", -10.0, 1.3, 0.0)


## 二幕起冲锋路径留冰面 3 秒（冰棱带）：读 last_act（warn_resolve 写），每次冲锋记一条
func _ice_step(e: Dictionary) -> void:
	var st: Array = e.get("ice_strips", [])
	st = st.filter(func(s): return g.t < float(s.until))
	var la: Dictionary = e.get("last_act", {})
	if e.phase == 1 and _act(e) >= 1 and str(la.get("act", "")) == "dash" and float(la.get("t", -1.0)) > float(e.get("ice_last_t", -1.0)):
		e.ice_last_t = float(la.t)
		var a: Vector2 = la.pos
		var b: Vector2 = a + Vector2.from_angle(float(la.ang)) * float(la.len)
		st.append({"a": a, "b": b, "until": g.t + Bal.v("boss/knight_ice_life", 3.0)})
		g.fx.append({"kind": "frost_track", "a": a, "b": b, "life": Bal.v("boss/knight_ice_life", 3.0), "max": Bal.v("boss/knight_ice_life", 3.0), "enemy": true})
	e.ice_strips = st


## 掷枪落地立桩（docs/142b §3.1）：last_act 是「掷枪」且是新的一次 → 线端立一根桩（离场地边 ≥100）


## ---- 最后的骑士：冰柱（docs/38 §8.8 的冰枪桩；docs/142b §3.1 改为开局就有，10-25 用户「设置成冰柱，多一点，4–5 个」）。
## 场上 boss/knight_stakes（5）根冰柱（判定 r 22），离主控 ≥120、离场地边 ≥100、彼此 ≥90；破土升起帧条见 tools/gen_ice_pillar.py。
## 冰柱只挡骑士：冲锋撞柱后眩晕；整批耗尽再等 1.5 秒，随后预告 1 秒升起新柱。
## 重生后（冲锋形态，原作不可阻挡）撞碎桩继续冲。主控和子弹都不受影响。冲锋预警会标出这一冲会不会撞桩（w.stake_hit，画面画「破」字端盖）
func _knight_stakes(e: Dictionary, _dt: float) -> void:
	if not e.has("stakes"):
		e.stakes = []
		_place_stakes(e, int(Bal.v("boss/knight_stakes", 5.0)))
		g.vfx.add_text(e.pos + Vector2(0, -70), "长枪插地 · 冰柱破土", Color(0.6, 0.9, 1.4), 18)
	e.stakes = e.stakes.filter(func(s): return float(s.until) > 0.0)
	if e.stakes.is_empty():
		if not e.has("stakes_empty_at"):
			e.stakes_empty_at = g.t + 1.5
		elif g.t >= float(e.stakes_empty_at):
			e.erase("stakes_empty_at")
			_place_stakes(e, int(Bal.v("boss/knight_stakes", 5.0)))
	# 冲锋中撞桩
	if e.get("kb_self", false) and e.kb.length() > 100.0:
		for s in e.stakes:
			if g.t >= float(s.born) and e.pos.distance_to(s.pos) < e.r + 22.0:
				s.until = 0.0
				_shatter(s.pos, 1.0)   # 撞柱崩碎
				g.vfx.sparks(s.pos, Vector2.UP, Color(0.8, 1.2, 1.6), 16, 260.0)
				if e.phase == 2:
					# 冲锋形态：桩挡不住，撞碎继续冲
					Sfx.play("stake_shatter", -4.0, 0.9, 0.0)
					g.vfx.add_text(s.pos + Vector2(0, -40), "撞碎", Color(0.8, 0.95, 1.4), 14)
					continue
				e.kb = Vector2.ZERO
				e.kb_self = false
				e.dash_t = 0.0
				e.dash2 = 0
				e.erase("breath_at")
				g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
				# 撞柱眩晕（用户 10-25）：knight_stake_break（2.5）秒不动不出招、受伤 × knight_break_taken（2.0）；头顶星 + 「眩晕」读秒（world 读 brk_label；骑士别的破绽不写字）
				g.combat.start_break(e, Bal.v("boss/knight_stake_break", 2.5))
				e.brk_label = "眩晕"
				e.stun_fx = e.fx
				Sfx.play("stake_hit", 2.0, 1.0, 0.0)   # 撞桩、长枪脱手
				g.fx.append({"kind": "ring", "pos": s.pos, "r": 70.0, "life": 0.5, "max": 0.5, "col": Color(0.6, 0.9, 1.4), "enemy": true})
				Sfx.play("boom", -4.0, 1.2, 0.0)
				break


## 冰柱崩碎：有冰柱帧条用 prop_ice_pillar_break（0.75 倍，同 world._draw_stakes），没有退回旧冰枪桩碎裂；a = 透明度（自然到期半透明）
func _shatter(pos: Vector2, a: float) -> void:
	if g.tex.get("prop_ice_pillar_break") != null:
		g.vfx.fx_sprite("prop_ice_pillar_break", pos, g.PX * 0.75, 0.0, false, true, Color(1, 1, 1, a))
	else:
		g.vfx.fx_sprite("prop_ice_stake_break", pos, g.PX, 0.0, false, true, Color(1, 1, 1, a))


func _place_stakes(e: Dictionary, want: int) -> void:
	# Batch invariant: no source (throw, phase change, time) fills a partially used batch.
	if not e.stakes.is_empty():
		return
	var center: Vector2 = g.zone_next_c if g.zone_frozen else e.pos
	var radius: float = minf(360.0, (g.zone_next_r - 110.0) * 0.72) if g.zone_frozen else 320.0
	var offset: float = g.rng_enemy.randf() * TAU
	for k in want:
		var p: Vector2 = center + Vector2.from_angle(offset + TAU * k / want) * radius
		# Keep five sectors, move a sector radially if the player occupies its landing point.
		if p.distance_to(g.ppos) < 100.0:
			p = center + Vector2.from_angle(offset + TAU * k / want) * radius * 0.6
		p = g.combat.arena_clamp(p, 110.0)
		e.stakes.append({"pos": p, "until": INF, "born": g.t + 1.0})
		_warn(e, "circle", 1.0, {"pos": p, "r": 24.0, "act": "", "dmg": 0.0, "lock": false, "col": ICE})


## ---- 受击钩子
## 重甲（docs/142b §3.1）：平时受伤 × knight_armor（0.4）；破绽期（撞桩 / 喘气）合计 × knight_break_taken（2.0，除掉公共破绽加成 boss/break_mult）
func taken_mult(e: Dictionary) -> float:
	if float(e.get("break_t", 0.0)) > 0.0:
		return Bal.v("boss/knight_break_taken", 2.0) / maxf(0.01, Bal.v("boss/break_mult", 1.4))
	return Bal.v("boss/knight_armor", 0.4)


## 转幕保留当前冰柱批次，不额外补柱。
func on_gate(_e: Dictionary) -> void:
	pass   # Existing pillars persist across acts; only an exhausted batch is renewed.


## 第一次归零不死，寒冰重生（二阶段「冲锋形态」）
func on_lethal(e: Dictionary) -> bool:
	if e.phase != 1:
		return super.on_lethal(e)
	Sfx.play_cue("phase", e.type, "start")
	e.phase = 2
	e.hp = e.maxhp * 0.5
	e.spd *= Bal.v("boss/knight_reborn_spd", 0.5)   # 原作冲锋形态：移速 −50%，靠冲锋三连追人
	e.invuln = true
	e.channel = 1.5
	e.stun = 0.0
	e.kb = Vector2.ZERO
	e.kcold = 0.0
	e.ice_strips = []
	e["tint2"] = Color(0.82, 0.92, 1.25)   # 二阶段常驻冰蓝着色（docs/95 §4.2；render/world 乘色，不改帧条）
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))   # 重生清预警（§4.3 节奏表）
	if not g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0):
		g.fx.append({"kind": "ring", "pos": e.pos, "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.9, 1.4)})
	g.vfx.show_banner("冲锋形态：冰柱挡不住了——躲过三连冲，趁喘气打")
	Sfx.play("roar", 0.0, 0.9, 0.0)
	g.vfx.shake_screen(1.2)
	# 原作「释放当前波次」：刷一波普通海嗣（场地边缘）
	for k in int(Bal.v("boss/knight_rebirth_wave", 16.0)):
		g.spawner.spawn_enemy(g.spawner.pick_type(), g.combat.arena_clamp(g.spawner.edge_pos(), 60.0))   # 夹进场地圈内：别刷到够不着的地方
	return true
