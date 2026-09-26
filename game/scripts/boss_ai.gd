## Boss 行为与招式预警（从 game.gd 拆出）：所有状态仍在 game.gd，本文件通过 g 访问
extends RefCounted

const D = preload("res://scripts/data.gd")

var g  # Game (Node2D)


func _init(game) -> void:
	g = game


## Boss 行为
func _boss_ai(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	e.bt += dt
	g.combat.gate_update(e, dt)   # 阶段卡点：每幕计时、护盾到时过卡点（docs/38 §1.3）
	# 冲锋 / 突刺计时（_warn_resolve 的 "dash" / "stab" 写入）：Boss 不走 enemy_ai 的冲刺递减，必须在这里递减，
	# 否则骑士二阶段「再冲锋」（等 dash_t 归零）永远不会触发，冲锋帧条也会一直停在冲刺姿势（docs/38 B0 第 1 项）
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t = maxf(0.0, e.dash_t - dt)
	# 接潮：昏迷后回复；两者同时昏迷则一起倒下
	if e.get("coma", false):
		e.hp = min(e.maxhp, e.hp + e.maxhp * 0.1 * dt)
		var p = e.get("partner")
		if p != null and not p.dead and p.get("coma", false):
			e.coma = false
			p.coma = false
			e.invuln = false
			p.invuln = false
			g.combat.kill(e)
			g.combat.kill(p)
			g.vfx.show_banner("接潮双体 同时倒下")
			return
		if e.hp >= e.maxhp:
			e.coma = false
			e.invuln = false
			g.vfx.add_text(e.pos + Vector2(0, -50), "苏醒", Color(0.6, 1.0, 0.9), 18)
		return
	var ready: bool = e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and e.get("channel", 0.0) <= 0.0 and e.age > 2.0 and e.get("break_t", 0.0) <= 0.0   # break_t：Boss 自己的破绽硬直（§1.5）
	match e.type:
		"iberia", "carmen":
			# 圣徒：3 发弹药，打空后近战；定期装填，装填中被攻击会被打断并晕眩
			# 伊比利亚：裁决射线（贯穿全屏）；卡门：狙击（锁定线）、退避跳
			if ready and e.channel <= 0.0:
				if e.type == "iberia" and _cd(e, "judge", 11.0):
					_warn(e, "line", 1.1, {"ang": dir.angle(), "len": 980.0, "wid": 16.0, "track": 0.55, "act": "shot", "name": "裁决", "col": Color(1.0, 0.75, 0.3), "dmg": e.dmg * 2.2})
				elif e.type == "carmen":
					if dist < 130.0 and _cd(e, "hop", 5.0):
						e.kb = -dir * 720.0
						e.pose = 0.35
						e.pose_max = 0.35
						g.vfx.sparks(e.pos, dir, Color(0.8, 0.8, 0.7), 10, 160.0)
						g.vfx.add_text(e.pos + Vector2(0, -50), "退避", Color(0.9, 0.9, 0.8), 14)
						Sfx.play("dodge", -8.0)
					elif dist > 150.0 and _cd(e, "snipe", 8.0):
						_warn(e, "line", 1.2, {"ang": dir.angle(), "len": 1100.0, "wid": 10.0, "track": 0.6, "act": "shot", "name": "狙击", "col": Color(1.0, 0.85, 0.4), "dmg": e.dmg * 2.6})
			if e.channel > 0.0:
				e.channel -= dt
				if e.channel <= 0.0:
					e.ammo = 3
					e.ai = "ranged"
					g.vfx.add_text(e.pos + Vector2(0, -44), "装填完毕", Color(1.0, 0.8, 0.5), 14)
			else:
				e.reload_t -= dt
				if e.reload_t <= 0.0 and e.stun <= 0.0:
					e.reload_t = 20.0
					e.channel = 2.0
					g.vfx.add_text(e.pos + Vector2(0, -44), "装填中……", Color(1.0, 0.8, 0.5), 16)
		"path":
			# 塑路者：冲撞（直线预警→冲锋）、震地（近身蓄力→冲击波）、碎裂（75/50/25% 裂出分形）
			if ready:
				if dist < 170.0 and _cd(e, "slam", 9.0):
					_warn(e, "circle", 1.0, {"r": 230.0, "follow": true, "act": "slam", "name": "震地", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.3})
				elif dist > 150.0 and _cd(e, "dash", 6.0):
					_warn(e, "line", 0.9, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.45, "act": "dash", "spd": 620.0, "name": "冲撞", "col": Color(1.0, 0.35, 0.3)})
			var crack: int = e.get("crack", 0)
			if crack < 3 and e.hp < e.maxhp * (0.75 - 0.25 * crack):
				e.crack = crack + 1
				for k in 4:
					g.spawner.spawn_enemy("fractal", e.pos + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 56.0)
				g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.2, "life": 0.35, "max": 0.35, "col": Color(0.6, 0.7, 1.0)})
				g.vfx.add_text(e.pos + Vector2(0, -60), "碎裂", Color(0.6, 0.7, 1.0), 18)
				Sfx.play("boom", -6.0, 1.3, 0.0)
		"bishop":
			# 接潮主教：潮汐柱（脚下三圈）、召潮（4 只海嗣）、祝福（治疗并加速搭档）
			if ready:
				var p = e.get("partner")
				if _cd(e, "pillar", 7.0):
					for k in 3:
						var off: Vector2 = Vector2.ZERO if k == 0 else Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(70.0, 130.0)
						_warn(e, "circle", 1.1 + 0.15 * k, {"pos": g.ppos + off, "r": 64.0, "act": "pillar", "name": "潮汐柱" if k == 0 else "", "col": Color(0.4, 0.9, 1.0), "dmg": e.dmg * 1.1, "lock": k == 0})
				elif p != null and not p.dead and not p.get("coma", false) and p.hp < p.maxhp * 0.9 and _cd(e, "bless", 10.0):
					p.hp = minf(p.maxhp, p.hp + p.maxhp * 0.08)
					p.haste = 5.0
					e.pose = 0.5
					e.pose_max = 0.5
					g.fx.append({"kind": "ring", "pos": p.pos, "r": p.r * 2.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.8)})
					for k in 3:
						g.fx.append({"kind": "cross", "pos": p.pos + Vector2(randf_range(-18, 18), randf_range(-40, -5)), "life": 0.9, "max": 0.9, "delay": k * 0.08, "sz": 4.0})
					g.vfx.add_text(e.pos + Vector2(0, -50), "祝福", Color(0.5, 1.0, 0.8), 16)
					g.vfx.add_text(p.pos + Vector2(0, -50), "加速", Color(0.5, 1.0, 0.8), 14)
					Sfx.play("pickup", -6.0, 0.8)
				elif _cd(e, "summon", 14.0):
					e.pose = 0.6
					e.pose_max = 0.6
					for k in 4:
						var sp: Vector2 = e.pos + Vector2.from_angle(TAU * k / 4.0) * 70.0
						g.spawner.spawn_enemy("bone" if k % 2 == 0 else "slider", sp)
						g.fx.append({"kind": "ring", "pos": sp, "r": 22.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.9, 1.0)})
					g.vfx.add_text(e.pos + Vector2(0, -50), "召潮", Color(0.5, 0.9, 1.0), 16)
					Sfx.play("tentacle", -6.0, 0.8)
		"archon":
			# 接潮蔑死体：横扫（扇形重击+侵蚀）、跃击（跳砸目标点）
			if ready:
				if dist < 160.0 and _cd(e, "sweep", 5.0):
					_warn(e, "cone", 0.8, {"follow": true, "ang": dir.angle(), "half": 1.05, "r": 165.0, "track": 0.4, "act": "sweep", "name": "横扫", "col": Color(0.6, 1.0, 0.9), "dmg": e.dmg * 1.6, "corrode": 0.5})
				elif dist > 170.0 and dist < 520.0 and _cd(e, "leap", 9.0):
					var w := _warn(e, "circle", 1.0, {"pos": g.ppos, "r": 84.0, "act": "leap", "name": "跃击", "col": Color(0.6, 1.0, 0.9), "dmg": e.dmg * 1.5, "corrode": 0.5})
					e.leap = w
					e.leap_from = e.pos
			if e.has("leap"):
				var w2: Dictionary = e.leap
				var k := clampf(w2.t / w2.dur, 0.0, 1.0)
				e.pos = e.leap_from.lerp(w2.pos, k)
				e.air = sin(k * PI) * 150.0
				if w2.t >= w2.dur:
					e.erase("leap")
					e.air = 0.0
		"immortal":
			# 接潮斥亡体：连斩（三段突刺）、搭档昏迷时狂暴
			var p2 = e.get("partner")
			if p2 != null and not p2.dead and p2.get("coma", false) and not e.get("rage", false):
				e.rage = true
				e.spd *= 1.35
				e.dmg *= 1.2
				g.vfx.add_text(e.pos + Vector2(0, -50), "狂暴", Color(1.0, 0.4, 0.4), 18)
				g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.4, "max": 0.4, "col": Color(1.0, 0.3, 0.3)})
				Sfx.play("roar", -6.0, 1.3)
			if ready and e.get("combo_n", 0) > 0 and e.get("combo_t", 0.0) <= g.t:
				e.combo_n -= 1
				_warn(e, "line", 0.38, {"ang": dir.angle(), "len": 190.0, "wid": 22.0, "track": 0.19, "act": "stab", "spd": 820.0, "name": "" if e.combo_n < 2 else "连斩", "col": Color(0.6, 0.8, 1.0), "dmg": e.dmg * 1.1, "corrode": 0.5})
				e.combo_t = g.t + 0.62
			elif ready and dist < 280.0 and _cd(e, "combo", 6.0):
				e.combo_n = 3
				e.combo_t = 0.0
		"paranoia":
			# "偏执泡影"：一阶段 环形弹幕；二阶段 泡影爆裂、偏执凝视、子弹落地留溟痕
			if ready:
				if e.phase == 1:
					if _cd(e, "ring", 6.0):
						_warn(e, "circle", 0.6, {"follow": true, "r": 46.0, "act": "bring", "name": "泡影", "col": Color(0.8, 0.5, 1.0), "dmg": e.dmg * 0.6})
				else:
					if _cd(e, "gaze", 11.0):
						_warn(e, "line", 1.3, {"ang": dir.angle(), "len": 820.0, "wid": 26.0, "track": 0.65, "act": "beam", "name": "凝视", "col": Color(0.9, 0.4, 1.0), "dmg": e.dmg * 2.0, "corrode": 0.5})
					elif _cd(e, "burst", 7.0):
						var a0: float = g.rng.randf() * TAU
						for k in 4:
							_warn(e, "circle", 1.0 + 0.1 * k, {"pos": g.ppos + Vector2.from_angle(a0 + TAU * k / 4.0) * 88.0, "r": 70.0, "act": "burst", "name": "泡影爆裂" if k == 0 else "", "col": Color(0.85, 0.45, 1.0), "dmg": e.dmg * 1.2, "corrode": 0.5, "lock": k == 0})
		"izumik":
			if e.phase == 1:
				# 学习阶段：无敌，放出子代，子代回到本体会被吸收
				e.hp = min(e.maxhp, e.hp + e.maxhp * 0.012 * dt)
				if e.bt > 4.0:
					e.bt = 0.0
					for k in 2:
						var o: Dictionary = g.spawner.spawn_enemy("offspring", e.pos + Vector2.from_angle(g.rng.randf() * TAU) * 140.0)
						o.feed = true
						o.feed_to = e
						o.spd = 45.0
				if e.hp >= e.maxhp:
					e.phase = 2
					e.invuln = false
					e.bt = 0.0
					g.vfx.show_banner("伊祖米克进入「解读阶段」！")
					Sfx.play("roar", 0.0, 0.8, 0.0)
					g.vfx.shake_screen(1.0)
			else:
				# 解读阶段：周期冲击波，被波及会晕眩
				if e.bt > 7.0:
					e.bt = 0.0
					g.shocks.append({"pos": e.pos, "r": e.r, "maxr": 420.0, "dmg": e.dmg * 1.2, "hit": false, "boss": e.boss})
					Sfx.play("skill", -2.0, 0.6)
		"knight_boss":
			# 最后的骑士（结局二）：冲锋（直线预警→突进+冰霜）/ 长枪连刺（近身三段扇形）/ 寒冰领域（20 秒一次，200 半径减速 6 秒）
			# 二阶段（首次归零后重生）：移速 +20%，冲锋连续两次
			var ice := Color(0.6, 0.9, 1.4)
			if e.get("channel", 0.0) > 0.0:
				e.channel -= dt
				if e.channel <= 0.0:
					e.invuln = false
			if e.get("frost_t", 0.0) > 0.0:
				e.frost_t -= dt
				if g.ppos.distance_to(e.frost_pos) < 200.0:
					g.frost = maxf(g.frost, 0.15)
			if e.get("dash2", false) and e.get("dash_t", 0.0) <= 0.0 and e.get("wind", 0.0) <= 0.0:
				e.dash2 = false
				_warn(e, "line", 0.45, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.3, "act": "dash", "spd": 820.0, "name": "再冲锋", "col": ice, "dmg": e.dmg * 1.5})
			if ready and e.channel <= 0.0:
				if e.age > 6.0 and _cd(e, "frost", 20.0):
					_warn(e, "circle", 1.0, {"follow": true, "r": 200.0, "act": "frost", "name": "寒冰领域", "col": ice, "dmg": e.dmg * 0.5})
				elif dist < 140.0 and _cd(e, "stab", 5.0):
					for k in 3:
						_warn(e, "cone", 0.5 + 0.3 * k, {"ang": dir.angle(), "half": 0.8, "r": 125.0, "track": 0.3 + 0.3 * k, "act": "bite", "name": "长枪连刺" if k == 0 else "", "col": ice, "dmg": e.dmg * 1.1, "lock": k == 0})
					e.wind = 1.2
				elif dist > 150.0 and _cd(e, "charge", 4.5 if e.phase == 2 else 6.0):
					_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.4, "act": "dash", "spd": 780.0, "name": "冲锋", "col": ice, "dmg": e.dmg * 1.5})
					if e.phase == 2:
						e.dash2 = true
		"ishar":
			# 伊莎玛拉：召唤之泪；泪未被清除时持续充能，充满后变身
			if e.bt > 6.0:
				e.bt = 0.0
				_spawn_tears(e, 1)
			var ntear := 0
			for o in g.enemies:
				if o.type == "tear" and not o.dead:
					ntear += 1
			if e.phase == 1:
				e.charge += ntear * 3.0 * dt
				if e.charge >= 100.0:
					e.phase = 2
					e.dmg *= 1.6
					g.vfx.show_banner("伊莎玛拉 完成了转化！")
					Sfx.play("roar", 2.0, 0.6, 0.0)
					g.vfx.shake_screen(1.2)
			if not e.get("half", false) and e.hp < e.maxhp * 0.5:
				e.half = true
				e.dmg *= 1.3
				_spawn_tears(e, 2)
				g.vfx.show_banner("伊莎玛拉 愈发狂暴")
			# 治疗周围的海嗣
			e.heal_t = e.get("heal_t", 0.0) + dt
			if e.heal_t > 4.0:
				e.heal_t = 0.0
				var n := 0
				for j in g.enemies_sys.query(e.pos, 260.0):
					var o: Dictionary = g.enemies[j]
					if o.dead or o.boss or o.chest or n >= 3:
						continue
					o.hp = min(o.maxhp, o.hp + o.maxhp * 0.3)
					g.fx.append({"kind": "ring", "pos": o.pos, "r": 18.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 1.0, 0.7)})
					n += 1



## Boss 招式冷却：到时返回 true 并重置
func _cd(e: Dictionary, key: String, dur: float) -> bool:
	if not e.has("cds"):
		e.cds = {}
	if e.cds.get(key, 0.0) <= g.t:
		e.cds[key] = g.t + dur
		return true
	return false



## Boss 招式预警：shape = circle / line / cone；dur 秒后结算 act
func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var w := {"shape": shape, "t": 0.0, "dur": dur, "owner": e, "pos": e.pos, "ang": 0.0, "r": 60.0, "len": 300.0, "wid": 14.0,
		"half": 0.8, "col": Color(1.0, 0.3, 0.35), "act": "", "dmg": e.dmg, "name": "", "corrode": 0.0, "done": false, "follow": false, "track": 0.0, "lock": true}
	w.merge(d, true)
	# 难度缩短预警只压缩追踪段（跟着主控转向的那段），总时长至少 0.6 秒，原本就短于 0.6 的不动（docs/38 B0 第 5 项）；
	# 修正值大于 1（放宽）时整体拉长
	var wm := float(g.dmod.boss_warn)
	if wm < 1.0 and w.track > 0.0:
		var cut: float = minf(w.track * (1.0 - wm), maxf(0.0, w.dur - 0.6))
		w.track -= cut
		w.dur -= cut
	elif wm > 1.0:
		w.dur *= wm
		w.track *= wm
	g.warns.append(w)
	if w.lock:
		e.wind = maxf(e.get("wind", 0.0), w.dur)
		e.pose = w.dur + 0.3
		e.pose_max = w.dur + 0.3
	if w.name != "":
		# 招式名进 Boss 血条的副标题行，不再头顶浮字（docs/38 §1.15，hud.gd 读 move_name / move_t）
		e["move_name"] = w.name
		e["move_t"] = g.t
		Sfx.play("skill", -12.0, 1.4)
	return w



func _update_warns(dt: float) -> void:
	for w in g.warns:
		w.t += dt
		var e: Dictionary = w.owner
		if w.follow and not e.dead:
			w.pos = e.pos
		if w.track > 0.0 and w.t < w.track and w.shape != "circle":
			var want: float = (g.ppos + Vector2(0, -14) - w.pos).angle()
			w.ang = lerp_angle(w.ang, want, minf(1.0, dt * 10.0))
		if w.t >= w.dur and not w.done:
			w.done = true
			if not e.dead or w.shape == "circle":
				_warn_resolve(w)
	g.warns = g.warns.filter(func(w): return w.t < w.dur + 0.25)



func _warn_hit(w: Dictionary) -> bool:
	var pp: Vector2 = g.ppos + Vector2(0, -14)
	match w.shape:
		"circle":
			return pp.distance_to(w.pos) < w.r + 10.0
		"line":
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			return Geometry2D.get_closest_point_to_segment(pp, w.pos, b).distance_to(pp) < w.wid + 12.0
		"cone":
			var dv: Vector2 = pp - w.pos
			return dv.length() < w.r + 10.0 and absf(angle_difference(dv.angle(), w.ang)) < w.half + 0.12
	return false



func _warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	if not _warn_hit(w):
		return
	var e: Dictionary = w.owner
	g.dmg_src = "boss_" + e.type
	g.in_type = ["远程", "法术"] if w.act in ["pillar", "burst", "beam", "bring"] else (["远程", "物理"] if w.act == "shot" else ["近战", "物理"])
	if g.invuln <= 0.0:
		g.combat.enemy_hit(w.dmg, {"corrode": w.corrode, "boss": e.boss}, false, true)   # 预警系统精英也在用（钻地咬击、踏地），按放招的敌人算
		if stun_t > 0.0 and not g.combat.stun_as_slow(e.boss):   # Boss 战里僵直改成减速（docs/38 §1.11）
			g.pstun = maxf(g.pstun, stun_t)
		if slow and not g.combat.atk_slow_as_slow(3.0, e.boss):   # Boss 来源不写 atk_slow，改成移速减速（docs/38 §1.11）
			g.atk_slow = 3.0



func _warn_resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var c: Color = w.col
	var dv := Vector2.from_angle(w.ang)
	match w.act:
		"pillar":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.55, "max": 0.55, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.35, "max": 0.35, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.6, 1.2, 1.6), 14, 260.0)
			Sfx.play("tentacle", -5.0, 1.1)
			g.vfx.shake_screen(0.3)
			_warn_damage(w, 0.4)
		"frost":
			e.frost_pos = w.pos
			e.frost_t = 6.0
			g.fx.append({"kind": "frost", "pos": w.pos, "r": w.r, "life": 6.0, "max": 6.0, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.7, 1.0, 1.5), 16, 240.0)
			Sfx.play("skill", -4.0, 0.7)
			_warn_damage(w)
		"slam":
			g.shocks.append({"pos": w.pos, "r": e.r, "maxr": w.r, "dmg": w.dmg, "hit": false, "boss": e.boss})
			g.fx.append({"kind": "quake", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.8, 0.7, 0.6), 18, 300.0)
			Sfx.play("boom", 0.0, 0.6, 0.0)
			g.vfx.shake_screen(1.2)
			g.hitstop = maxf(g.hitstop, 0.05)
		"burst":
			g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": Color(0.7, 0.35, 1.0)})
			g.vfx.sparks(w.pos, Vector2.ZERO, Color(1.2, 0.6, 1.8), 12, 240.0)
			Sfx.play("boom", -8.0, 1.2, 0.0)
			_warn_damage(w)
		"shot":
			var b: Vector2 = w.pos + dv * w.len
			g.fx.append({"kind": "tracer", "a": w.pos + Vector2(0, -18), "b": b, "life": 0.35, "max": 0.35, "col": c, "wid": w.wid})
			g.vfx.sparks(w.pos + dv * 24.0, dv, Color(2.0, 1.6, 0.8), 8, 320.0)
			Sfx.play("hit", 0.0, 0.5, 0.0)
			g.vfx.shake_screen(0.4)
			_warn_damage(w)
		"beam":
			var b2: Vector2 = w.pos + dv * w.len
			g.fx.append({"kind": "bbeam", "a": w.pos + Vector2(0, -20), "b": b2, "life": 0.5, "max": 0.5, "col": c, "wid": w.wid})
			Sfx.play("skill", -2.0, 0.5)
			g.vfx.shake_screen(0.7)
			_warn_damage(w, 0.0, true)
		"sweep":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			g.vfx.sparks(w.pos + dv * w.r * 0.6, dv, Color(0.8, 1.4, 1.4), 12, 260.0)
			Sfx.play("swing", -2.0, 0.55)
			g.vfx.shake_screen(0.5)
			_warn_damage(w, 0.25)
		"leap":
			e.pos = w.pos
			e.air = 0.0
			e.erase("leap")
			# 冲击环不超过预警圆（docs/38 B0 第 5 项：原来 +40，圈外也会被打到）
			g.shocks.append({"pos": w.pos, "r": 10.0, "maxr": w.r, "dmg": w.dmg * 0.5, "hit": false, "boss": e.boss})
			g.fx.append({"kind": "quake", "pos": w.pos, "r": w.r, "life": 0.5, "max": 0.5, "col": c})
			g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r * 0.8, "life": 0.3, "max": 0.3, "col": Color(0.5, 0.9, 0.9)})
			Sfx.play("boom", -2.0, 0.8, 0.0)
			g.vfx.shake_screen(1.0)
			_warn_damage(w, 0.3)
		"dash":
			e.kb = dv * w.get("spd", 600.0)
			e.dash_dir = dv
			e.dash_t = 0.45
			e.pose = 0.45
			e.pose_max = 0.45
			g.vfx.sparks(e.pos, -dv, Color(0.9, 0.9, 1.0), 10, 200.0)
			Sfx.play("swing", -4.0, 0.5)
		"stab":
			e.kb = dv * w.get("spd", 800.0)
			e.dash_dir = dv
			e.dash_t = 0.2
			e.pose = 0.25
			e.pose_max = 0.25
			g.fx.append({"kind": "tracer", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.22, "max": 0.22, "col": c, "wid": w.wid})
			Sfx.play("swing", -6.0, 0.7)
			_warn_damage(w)
		"bite":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": (g.ppos - w.pos).angle(), "half": 0.9, "r": w.r + 10.0, "life": 0.25, "max": 0.25, "col": c})
			Sfx.play("swing", -8.0, 0.9)
			_warn_damage(w)
		"bring":
			for k in 14:
				var d2 := Vector2.from_angle(TAU * k / 14.0 + w.t)
				g.ebullets.append({"pos": w.pos, "vel": d2 * 210.0, "dmg": w.dmg, "slow": true, "r": 7.0, "life": 3.0,
					"corrode": 0.5, "nerve": 0.0, "true": false, "kind": "ebullet", "home": false, "boss": e.boss})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			Sfx.play("tentacle", -8.0, 1.3)



## 预警绘制：外框 + 随时间填满的内圈；结算瞬间闪白
func _draw_warns() -> void:
	for w in g.warns:
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var c: Color = w.col
		var pulse: float = 0.5 + 0.5 * sin(g.t * 14.0)
		var fa := 0.10 + 0.14 * k
		var oa := 0.55 + 0.35 * pulse * k
		if w.done:
			var f: float = clampf(1.0 - (w.t - w.dur) / 0.25, 0.0, 1.0)
			c = Color(2.0, 2.0, 2.0)
			fa = 0.45 * f
			oa = 0.9 * f
			k = 1.0
		# 颜色不再乘 1.7–2.0：乘完在灯光里褪成白色 / 粉彩，色相丢失（docs/48 全局 ④）；亮度靠 alpha 和白芯（world.draw_warn_outlines）
		var fill := Color(c.r, c.g, c.b, fa * 1.3)
		var line := Color(c.r, c.g, c.b, oa)
		match w.shape:
			"circle":
				g.draw_set_transform(w.pos, 0.0, Vector2(1.0, 0.72))
				g.draw_circle(Vector2.ZERO, w.r, fill)
				g.draw_circle(Vector2.ZERO, w.r * k, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 40, line, 2.5)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"line":
				g.draw_set_transform(w.pos, w.ang, Vector2.ONE)
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), fill)
				g.draw_rect(Rect2(0.0, -w.wid * k, w.len, w.wid * 2.0 * k), Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), line, false, 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"cone":
				var pts := PackedVector2Array([w.pos])
				var pts2 := PackedVector2Array([w.pos])
				for q in 17:
					var a: float = w.ang - w.half + w.half * 2.0 * q / 16.0
					var dv := Vector2.from_angle(a)
					pts.append(w.pos + dv * w.r)
					pts2.append(w.pos + dv * w.r * k)
				g.draw_colored_polygon(pts, fill)
				if k > 0.05:
					g.draw_colored_polygon(pts2, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				pts.append(w.pos)
				g.draw_polyline(pts, line, 2.5)



func _spawn_tears(e: Dictionary, n: int) -> void:
	for k in n:
		var cnt := 0
		for o in g.enemies:
			if o.type == "tear" and not o.dead:
				cnt += 1
		if cnt >= 6:
			return
		g.spawner.spawn_enemy("tear", e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(140.0, 240.0))


