## Boss 行为与招式预警（从 game.gd 拆出）：所有状态仍在 game.gd，本文件通过 g 访问
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

# 只缩短招式之间的等待；预警、锁定、连段间隔与伤害保持原约定。
const SKILL_COOLDOWN_SCALE := 0.70

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
var patterns
var g  # Game (Node2D)


func _init(game) -> void:
	g = game
	patterns = Patterns.new(game)


## Boss 行为
func _boss_ai(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	e.bt += dt
	g.combat.gate_update(e, dt)   # 阶段卡点：每幕计时、护盾到时过卡点（docs/38 §1.3）
	if g.zone_frozen and is_same(e, g.final_boss):
		e.pos = g.combat.arena_clamp(e.pos, 80.0)   # 最终 Boss 场地：本体离圈边 ≥80（docs/38 §1.7）
	# 冲锋 / 突刺计时（_warn_resolve 的 "dash" / "stab" 写入）：Boss 不走 enemy_ai 的冲刺递减，必须在这里递减，
	# 否则骑士二阶段「再冲锋」（等 dash_t 归零）永远不会触发，冲锋帧条也会一直停在冲刺姿势（docs/38 B0 第 1 项）
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t = maxf(0.0, e.dash_t - dt)
	# 接潮：昏迷后回复；两者同时昏迷则一起倒下
	if e.get("coma", false):
		# 假死赛跑（docs/38 §8.4）：boss/pair_race 秒内血条涨回 pair_revive_hp（50%），期间打倒另一具 = 两具一起倒下；到时复苏
		e.coma_t = e.get("coma_t", 0.0) + dt
		var race: float = Bal.v("boss/pair_race", 8.0)
		e.hp = maxf(1.0, e.maxhp * Bal.v("boss/pair_revive_hp", 0.5) * minf(e.coma_t / race, 1.0))
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
		if e.coma_t >= race:
			e.coma = false
			e.invuln = false
			e.coma_t = 0.0
			e.revives = int(e.get("revives", 0)) + 1
			g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(0.4, 1.0, 0.9), "enemy": true})
			g.vfx.add_text(e.pos + Vector2(0, -50), "复苏（%d / %d）" % [e.revives, int(Bal.v("boss/pair_revives", 2.0))], Color(0.6, 1.0, 0.9), 18)
		return
	var ready: bool = e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and e.get("channel", 0.0) <= 0.0 and e.get("dash_t", 0.0) <= 0.0 and e.age > 2.0 and e.get("break_t", 0.0) <= 0.0   # break_t：Boss 自己的破绽硬直（§1.5）
	# 原作机制转译：冰线后的骑士冲锋、接潮双体的假死反击。均走正式预警管线。
	if ready and e.type == "knight_boss" and g.t >= float(e.get("hunt_follow_at", INF)):
		e.hunt_follow_at = INF
		_warn(e, "line", 0.7, {"ang": float(e.get("hunt_angle", dir.angle())), "len": 520.0, "wid": 32.0,
			"fit_len": true, "act": "dash", "name": "寒冷追击", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 1.35})
		ready = false
	if ready and e.type == "knight_boss" and dist >= 120.0 and dist <= 600.0 and _cd(e, "hunt", 12.0):
		_warn(e, "line", 0.85, {"ang": dir.angle(), "len": minf(560.0, dist + 60.0), "wid": 18.0,
			"track": 0.25, "act": "frost_track", "name": "冰线", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 0.4})
		ready = false
	var mate = e.get("partner")
	if mate != null and not mate.dead and mate.get("coma", false) and e.type in ["bishop", "archon", "immortal"]:
		if g.t >= float(e.get("link_visual_at", 0.0)):
			e.link_visual_at = g.t + 0.28
			g.fx.append({"kind": "tide_link", "a": e.pos, "b": mate.pos, "life": 0.36, "max": 0.36, "col": g.vfx.boss_color(e.type), "enemy": true})
		if ready and g.t >= float(e.get("link_next_at", 0.0)):
			e.link_next_at = g.t + Bal.v("boss/tide_link_cd", 4.5)
			_warn(e, "line", 0.9, {"ang": (mate.pos - e.pos).angle(), "len": e.pos.distance_to(mate.pos),
				"wid": 17.0, "act": "tide_link", "name": "接潮共鸣", "col": g.vfx.boss_color(e.type),
				"corrode": 0.25, "dmg": e.dmg * 0.55, "cancel_dead": true})
			ready = false
	if ready and patterns.try_attack(e, dir, dist):
		ready = false
	match e.type:
		"iberia", "carmen":
			# 圣徒：3 发弹药，打空后近战；定期装填，装填中被攻击会被打断并晕眩
			# 伊比利亚：裁决射线（贯穿全屏）；卡门：狙击（锁定线）、退避跳
			# 远程段最长 boss/saint_ranged_max 秒：到时弹药作废转近战追击。不然她剩一发子弹、站在射程外被签名招式拖着，
			# 永远打不空也不近身（9/29 实测伊比利亚卡在 50% 190 秒）
			if e.ai == "ranged" and e.channel <= 0.0:
				e.ranged_t = e.get("ranged_t", 0.0) + dt
				if e.ranged_t >= Bal.v("boss/saint_ranged_max", 6.0):
					e.ammo = 0
					e.ai = "melee"
					e.reload_t = maxf(e.get("reload_t", 0.0), Bal.v("boss/saint_melee", 8.0))
			else:
				e.ranged_t = 0.0
				# 近战追击段加速（e.haste：移速 ×1.4），真的追上来，破绽和读条才会在编队射程里发生
				if e.ai == "melee" and e.channel <= 0.0:
					e.haste = maxf(e.get("haste", 0.0), 0.1)
			# 装填打断（docs/38 §8.2）：读条中主控冲刺穿过她的身体也算打断
			if e.channel > 0.0 and g.dash_t > 0.0 and g.ppos.distance_to(e.pos) < e.r + 24.0:
				saint_interrupt(e)
			# 卡门第二幕：弹药打空先换剑 boss/carmen_sword 秒（贴身冲刺 + 扇形斩），再装填（§8.3）
			if e.get("sword_t", 0.0) > 0.0:
				e.sword_t -= dt
				if ready and dist < 240.0 and _cd(e, "sword", 1.6):
					if dist > 100.0:
						_warn(e, "line", 0.6, {"ang": dir.angle(), "wid": 20.0, "track": 0.2, "act": "stab", "spd": 600.0, "name": "圣徒之剑", "col": Color(1.0, 0.35, 0.3), "dmg": e.dmg * 1.3})
					else:
						_warn(e, "cone", 0.6, {"ang": dir.angle(), "half": 0.9, "r": 110.0, "track": 0.2, "act": "bite", "name": "剑斩", "col": Color(1.0, 0.35, 0.3), "dmg": e.dmg * 1.4})
			elif ready and e.channel <= 0.0:
				if e.type == "iberia" and _cd(e, "judge", 11.0):
					_warn(e, "line", 1.1, {"ang": dir.angle(), "len": 980.0, "wid": 16.0, "track": 0.55, "act": "shot", "name": "裁决", "col": Color(1.0, 0.75, 0.3), "dmg": e.dmg * Bal.v("boss/iberia_judge_mult", 2.6)})
					# 裁决后站定输出窗口（协调人 9/27：低射程编队追不上圣徒，伊比利亚中位 122 秒）：出手后原地站 boss/saint_stand 秒不动、不出招
					e.wind = maxf(e.wind, 1.1 + Bal.v("boss/saint_stand", 1.5))
				elif e.type == "carmen":
					# 退避跳：冷却 5 → 9 秒、距离缩短（720 → 480，约 128 像素），落地后站定 boss/saint_stand 秒（同上，给低射程编队输出窗口）
					if dist < 130.0 and _cd(e, "hop", Bal.v("boss/carmen_hop_cd", 9.0)):
						e.kb = -dir * Bal.v("boss/carmen_hop_spd", 480.0)
						e.wind = maxf(e.wind, 0.35 + Bal.v("boss/saint_stand", 1.5))
						e.pose = 0.35
						e.pose_max = 0.35
						g.vfx.sparks(e.pos, dir, Color(0.8, 0.8, 0.7), 10, 160.0)
						g.vfx.add_text(e.pos + Vector2(0, -50), "退避", Color(0.9, 0.9, 0.8), 14)
						Sfx.play("dodge", -8.0)
					elif dist > 150.0 and _cd(e, "snipe", 6.0 if e.get("gates_passed", 0) >= 1 else 8.0):
						_warn(e, "line", 1.2, {"ang": dir.angle(), "len": 1100.0, "wid": 10.0, "track": 0.6, "act": "shot", "name": "狙击", "col": Color(1.0, 0.85, 0.4), "dmg": e.dmg * 2.6})
			if e.channel > 0.0:
				e.channel -= dt
				if e.channel <= 0.0:
					# 没被打断：装填完毕，立刻连发三条瞄准线（间隔 0.6 秒，都可以走开躲）
					e.ammo = 3
					e.ai = "ranged"
					e.count_end = 0.0
					g.vfx.add_text(e.pos + Vector2(0, -44), "装填完毕", Color(1.0, 0.8, 0.5), 14)
					for k in 3:
						_warn(e, "line", 0.9 + 0.6 * k, {"ang": dir.angle(), "len": 980.0, "wid": 14.0, "track": 0.3 + 0.6 * k, "act": "shot",
							"name": "三连瞄准" if k == 0 else "", "col": Color(1.0, 0.8, 0.4), "dmg": e.dmg * Bal.v("boss/saint_volley_mult", 1.2), "lock": k == 0})
			else:
				e.reload_t -= dt
				# 弹药打空才装填（原来每 14 秒一次）；卡门第二幕先换剑
				if e.ammo <= 0 and e.reload_t <= 0.0 and e.get("sword_t", 0.0) <= 0.0 and e.stun <= 0.0 and e.wind <= 0.0 and e.get("break_t", 0.0) <= 0.0:
					if e.type == "carmen" and e.get("gates_passed", 0) >= 1 and not e.get("sword_done", false):
						e.sword_t = Bal.v("boss/carmen_sword", 8.0)
						e.sword_done = true
						e.ai = "melee"
						g.vfx.add_text(e.pos + Vector2(0, -50), "换剑", Color(1.0, 0.5, 0.4), 18)
					else:
						e.sword_done = false
						var rt: float = Bal.v("boss/iberia_reload", 4.0) if e.type == "iberia" else Bal.v("boss/carmen_reload", 3.0)
						e.channel = rt
						e.reload_dmg = 0.0
						e.count_end = g.t + rt   # 读条环（界面与美术读 count_end / count_max）
						e.count_max = rt
						g.vfx.add_text(e.pos + Vector2(0, -44), "装填中……", Color(1.0, 0.8, 0.5), 16)
		"path":
			# 塑路者：冲撞（直线预警→冲锋）、震地（近身蓄力→冲击波）、碎裂（75/50/25% 裂出分形）
			if ready:
				if dist < 170.0 and _cd(e, "slam", 9.0):
					# 震地：砸在主控当前位置（固定落点、不跟随 Boss），r 90（docs/48 P0-4；原来 r230 跟着 Boss 走）
					_warn(e, "circle", 1.0, {"pos": g.ppos, "r": 90.0, "act": "slam", "name": "震地", "col": Color(1.0, 0.55, 0.3), "dmg": e.dmg * 1.3})
				elif e.get("dash_left", 0) > 0 and e.get("dash_t", 0.0) <= 0.0:
					# 第二幕冲撞连段（docs/38 §8.1）：上一段冲完立刻接下一段，每段仍有完整预警
					e.dash_left -= 1
					_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.35, "act": "dash", "fit_len": true, "name": "", "col": Color(1.0, 0.35, 0.3)})
				elif dist > 150.0 and _cd(e, "dash", 6.0):
					_warn(e, "line", 0.9, {"ang": dir.angle(), "len": 440.0, "wid": 30.0, "track": 0.45, "act": "dash", "fit_len": true, "name": "冲撞", "col": Color(1.0, 0.35, 0.3)})
					if e.get("gates_passed", 0) >= 1:
						e.dash_left = int(Bal.v("boss/path_dash_chain", 1.0)) + int(e.get("dash_bonus", 0))   # 第二幕常驻 2 连，核心没打碎再加
						e.dash_bonus = 0
			var crack: int = e.get("crack", 0)
			if crack < 3 and e.hp < e.maxhp * (0.75 - 0.25 * crack):
				e.crack = crack + 1
				for k in 4:
					var fr: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(TAU * k / 4.0 + 0.4) * 56.0))
					fr.owner = e
				g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.2, "life": 0.35, "max": 0.35, "col": Color(0.6, 0.7, 1.0)})
				g.vfx.add_text(e.pos + Vector2(0, -60), "碎裂", Color(0.6, 0.7, 1.0), 18)
				Sfx.play("boom", -6.0, 1.3, 0.0)
			if e.get("gates_passed", 0) >= 1:
				_path_core(e)
		"bishop":
			# 接潮主教：潮汐柱（脚下三圈）、召潮（4 只海嗣）、祝福（治疗并加速搭档）
			if ready:
				var p = e.get("partner")
				if _cd(e, "pillar", 7.0):
					for k in 3:
						var off: Vector2 = Vector2.ZERO if k == 0 else Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(70.0, 130.0)
						_warn(e, "circle", 1.1, {"pos": g.ppos + off, "r": 64.0, "act": "pillar", "name": "潮汐柱" if k == 0 else "", "col": Color(0.4, 0.9, 1.0), "dmg": e.dmg * 1.1, "lock": k == 0})
				elif p != null and not p.dead and not p.get("coma", false) and p.hp < p.maxhp * 0.9 and _cd(e, "bless", 10.0):
					p.hp = minf(p.maxhp, p.hp + p.maxhp * 0.08)
					p.haste = 5.0
					e.pose = 0.5
					e.pose_max = 0.5
					# 敌方增益用敌方洋红（docs/48 ⑤：原来借用友方治疗十字和绿环，看着像我方在回血）
					g.fx.append({"kind": "ring", "pos": p.pos, "r": p.r * 2.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.3, 0.72)})
					g.fx.append({"kind": "rays", "pos": p.pos, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.3, 0.72)})
					g.vfx.add_text(e.pos + Vector2(0, -50), "祝福", Color(1.0, 0.45, 0.8), 16)
					g.vfx.add_text(p.pos + Vector2(0, -50), "加速", Color(1.0, 0.45, 0.8), 14)
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
				elif dist >= 160.0 and dist < 520.0 and _cd(e, "leap", 9.0):
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
			# 搭档苏醒时狂暴解除（docs/38 §2.3）
			if e.get("rage", false) and (p2 == null or p2.dead or not p2.get("coma", false)):
				e.rage = false
				e.spd /= 1.35
				e.dmg /= 1.2
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
							_warn(e, "circle", 1.0, {"pos": g.ppos + Vector2.from_angle(a0 + TAU * k / 4.0) * 88.0, "r": 70.0, "act": "burst", "name": "泡影爆裂" if k == 0 else "", "col": Color(0.85, 0.45, 1.0), "dmg": e.dmg * 1.2, "corrode": 0.5, "lock": k == 0})
		"izumik":
			if e.phase == 1:
				# 学习阶段：无敌，放出子代，子代回到本体会被吸收
				e.hp = min(e.maxhp, e.hp + e.maxhp * 0.012 * dt)
				if e.bt > 4.0 * SKILL_COOLDOWN_SCALE:
					e.bt = 0.0
					for k in 2:
						var o: Dictionary = g.spawner.spawn_enemy("offspring", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * 140.0))
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
				# 周期冲击波先给 1 秒预警（docs/48 P0-5：原来没有预警；专属「必须冲刺」样式由界面与美术按 must_dash 画）
				if ready and e.bt > 7.0 * SKILL_COOLDOWN_SCALE:
					e.bt = 0.0
					_warn(e, "circle", 1.0, {"follow": true, "r": 420.0, "act": "slam", "name": "解读冲击", "must_dash": true, "col": Color(0.5, 1.0, 0.7), "dmg": e.dmg * 1.2})
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
				if g.combat.ground_d(g.ppos, e.frost_pos) < 200.0:
					g.frost = maxf(g.frost, 0.15)
			if e.get("dash2", false) and e.get("dash_t", 0.0) <= 0.0 and e.get("wind", 0.0) <= 0.0:
				e.dash2 = false
				_warn(e, "line", 0.45, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.3, "act": "dash", "fit_len": true, "name": "再冲锋", "col": ice, "dmg": e.dmg * 1.5})
			if ready and e.channel <= 0.0 and e.get("wind", 0.0) <= 0.0:
				if e.age > 6.0 and _cd(e, "frost", 20.0):
					_warn(e, "circle", 1.0, {"follow": true, "r": 200.0, "act": "frost", "name": "寒冰领域", "col": ice, "dmg": e.dmg * 0.5})
				elif dist < 140.0 and _cd(e, "stab", 5.0):
					# 三段连刺：每段间隔 0.6 秒、每段锁定 0.4 秒（§1.9 连发间隔、docs/48 P0-2）
					for k in 3:
						_warn(e, "cone", 0.6 + 0.6 * k, {"ang": dir.angle(), "half": 0.8, "r": 125.0, "track": 0.2 + 0.6 * k, "act": "bite", "name": "长枪连刺" if k == 0 else "", "col": ice, "dmg": e.dmg * 1.1, "lock": k == 0})
					e.wind = 1.9
				elif dist >= 140.0 and _cd(e, "charge", 4.5 if e.phase == 2 else 6.0):
					_warn(e, "line", 0.8, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.4, "act": "dash", "fit_len": true, "name": "冲锋", "col": ice, "dmg": e.dmg * 1.5})
					if e.phase == 2:
						e.dash2 = true
		"ishar":
			# P1 治疗海嗣和充能由 IsharEncounter 负责；这里仅调度敌对海嗣形态。
			if e.phase == 2 and ready and g.t >= float(e.get("transform_until", 0.0)):
				_ishar_phase2(e, dir, dist)


## 以原作「三目标真实伤害」为基础的幸存者玩法改编。
## 下列提示是攻击形状说明，不冒称原作技能名；固定轮转避免近身招式永久压住远程招式。
func _ishar_phase2(e: Dictionary, dir: Vector2, dist: float) -> void:
	var d: Dictionary = D.ENEMIES.ishar.get("attack", {})
	if dist > float(d.get("range", 660.0)) or g.t < float(e.get("ishar_next_at", 0.0)):
		return
	var move: int = int(e.get("ishar_cycle", 0)) % 4
	var col := Color(0.35, 1.0, 0.9)
	var end := 0.0
	var echoes: Array = e.get("tear_echoes", [])
	if not echoes.is_empty():
		# 只保存变身前未压制的泪滴；锁定一刻的主控位置，各束同时结算。
		var target: Vector2 = g.combat.arena_clamp(g.ppos, 80.0)
		for source in echoes:
			var to_target: Vector2 = target - source
			var w := _warn(e, "line", 1.0, {"pos": source, "ang": to_target.angle(), "len": to_target.length(),
				"wid": 13.0, "act": "ishar_echo", "true": true, "name": "泪滴共鸣" if source == echoes[0] else "",
				"col": col, "dmg": e.dmg * 0.48, "cancel_dead": true, "lock": source == echoes[0]})
			end = maxf(end, w.dur)
		e.tear_echoes = []
		e.wind = maxf(e.wind, end)
		e.cdt = maxf(e.cdt, end)
		e.ishar_next_at = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE
		return
	e.ishar_cycle = (move + 1) % 4
	match move:
		0:
			# 一人主控制：三目标改为当前脚底与两侧三个固定落点；队员仍不受伤。
			var side := dir.orthogonal()
			var offsets := [0.0, -1.0, 1.0]
			for k in 3:
				var pos: Vector2 = g.combat.arena_clamp(g.ppos + side * offsets[k] * float(d.get("mark_spacing", 106.0)), 90.0)
				var w := _warn(e, "circle", float(d.get("mark_warn", 0.9)),
					{"pos": pos, "r": float(d.get("mark_radius", 56.0)), "act": "ishar_strike", "true": true,
					"name": "三点落击" if k == 0 else "", "col": col, "dmg": e.dmg * float(d.get("mark_mult", 0.65)),
					"cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		1:
			# 三条固定方向的射线同时释放，锁定后不追人；夹缝始终能避开。
			for k in 3:
				var w := _warn(e, "line", float(d.get("line_warn", 1.0)),
					{"ang": dir.angle() + (k - 1) * float(d.get("line_spread", 0.38)),
					"len": float(d.get("range", 660.0)), "wid": float(d.get("line_width", 14.0)),
					"act": "ishar_line", "true": true, "name": "三线扫射" if k == 0 else "", "col": col,
					"dmg": e.dmg * float(d.get("line_mult", 0.7)), "cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		2:
			var w := _warn(e, "cone", float(d.get("volley_warn", 0.8)),
				{"ang": dir.angle(), "r": 672.0, "half": 0.26, "track": 0.35, "act": "ishar_volley",
				"true": true, "name": "三重吐息", "col": col, "cancel_dead": true})
			end = w.dur
		3:
			var near: bool = dist < float(d.get("bite_range", 190.0))
			var w := _warn(e, "cone", float(d.get("maw_warn", 0.85)),
				{"ang": dir.angle(), "half": 0.85 if near else 0.46,
				"r": float(d.get("bite_range", 190.0)) if near else minf(dist + 40.0, float(d.get("range", 660.0))),
				"track": 0.3, "act": "bite" if near else "sweep", "true": true,
				"name": "近身撕咬" if near else "扇形横扫", "col": col,
				"dmg": e.dmg * float(d.get("maw_mult", 0.9)), "cancel_dead": true})
			end = w.dur
	# 完整连段期间停留且不插入普通射击；按经过难度修正后的真实预警长度计时。
	e.wind = maxf(e.wind, end)
	e.cdt = maxf(e.cdt, end)
	e["ishar_next_at"] = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE



## 图鉴 / Boss 演练使用正式二阶段的完整状态，避免只改贴图标记、却还留着一阶段行为。
## 正式受击触发仍由 combat.gd 结算；此入口只用于预览场景的起始条件。
func setup_preview_phase2(e: Dictionary) -> void:
	if e.phase == 2:
		return
	match e.type:
		"ishar":
			transform_ishar(e)
		"paranoia":
			e.phase = 2
			e.range = 400.0
			e.weak = "物理"
			e.dmg *= 1.2
			e.hover_lost = true
			e.ai = "melee"
			e.spd = 70.0
		"knight_boss":
			e.phase = 2
			e.hp = e.maxhp * 0.5
			e.spd *= 1.2
			e.invuln = true
			e.channel = 1.5
			e.stun = 0.0
			e.kb = Vector2.ZERO
			g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0)
		"izumik":
			e.phase = 2
			e.hp = e.maxhp
			e.invuln = false
			e.bt = 0.0


## 真实形态切换由逻辑记录起始时间，渲染和演练均使用同一个入口。
func transform_ishar(e: Dictionary) -> void:
	if e.phase == 2:
		return
	e.phase = 2
	e.friendly = false
	e.invuln = false   # 0.9 秒变身免伤由 combat 的 transform_until 护栏控制，不留永久无敌。
	e.ai = "melee"   # 接近主控，但伤害只从有预警的轮转招式结算。
	e["ishar_cycle"] = 0
	e["ishar_next_at"] = g.t + 0.9
	e["tear_echoes"] = []
	for o in g.enemies:
		if o.type == "tear" and is_same(o.get("owner", {}), e):
			if not o.dead and not g.ishar.tear_blocked(o):
				e.tear_echoes.append(o.pos)
				g.fx.append({"kind": "ring", "pos": o.pos, "r": 34.0, "life": 1.4, "max": 1.4,
					"col": Color(0.35, 1.0, 0.9), "enemy": true})
				g.fx.append({"kind": "tide_link", "a": o.pos, "b": e.pos, "life": 1.0, "max": 1.0,
					"col": Color(0.35, 1.0, 0.9), "enemy": true})
			o.dead = true
	e.dmg *= 1.6
	e.spd = maxf(e.spd, 58.0)
	e.r = 46.0
	e.r0 = 46.0
	e["transform_started"] = g.t
	e["transform_until"] = g.t + 0.9
	e.wind = maxf(e.wind, 0.9)
	e.pose = 0.0
	e.cdt = maxf(e.cdt, 0.9)
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	g.vfx.show_banner("伊莎玛拉 完成了转化！")
	Sfx.play("roar", 2.0, 0.6, 0.0)
	g.vfx.shake_screen(1.2)



## 塑路者「猎核」（docs/38 §8.1，50% 卡点之后）：场上最老的一块碎片发光成为核心部件（不动、固定血量），编队优先打它；
## 主控得带队走过去。打碎：其余碎片崩解、Boss 破绽 boss/path_core_break 秒；boss/path_core_time 秒没打碎：碎片冲回本体，
## 下一次冲撞多连几段（最多 3）。不回血。boss/path_core_gap 秒后出新核心
func _path_core(e: Dictionary) -> void:
	var core = e.get("core")
	if core != null:
		if core.dead:
			for o in g.enemies:
				if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
					o.dead = true
					g.vfx.sparks(o.pos, Vector2.ZERO, Color(0.6, 0.7, 1.0), 6, 160.0)
			g.combat.start_break(e, Bal.v("boss/path_core_break", 3.0))
			g.fx.append({"kind": "ring", "pos": core.pos, "r": 60.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4), "enemy": true})
			g.vfx.add_text(e.pos + Vector2(0, -70), "核心碎裂 —— 碎片崩解", Color(1.0, 0.85, 0.4), 20)
			Sfx.play("boom", -4.0, 1.4, 0.0)
			e.core = null
			e.core_next = g.t + Bal.v("boss/path_core_gap", 6.0)
		elif g.t >= float(e.core_until):
			var n := 0
			for o in g.enemies:
				if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
					n += 1
					g.fx.append({"kind": "reflow", "a": o.pos, "b": e.pos, "life": 0.7, "max": 0.7, "enemy": true})   # 碎片回流（world.gd 画）
					o.dead = true
			e.dash_bonus = mini(3, n)
			g.vfx.add_text(e.pos + Vector2(0, -70), "碎片回流 —— 冲撞 +%d 段" % e.dash_bonus, Color(1.0, 0.45, 0.35), 18)
			e.core = null
			e.core_next = g.t + Bal.v("boss/path_core_gap", 6.0)
		return
	if g.t < float(e.get("core_next", 0.0)):
		return
	var owned: Array = []
	for o in g.enemies:
		if o.type == "fractal" and not o.dead and is_same(o.get("owner"), e):
			owned.append(o)
	while owned.size() < 3:
		var fr: Dictionary = g.spawner.spawn_enemy("fractal", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(120.0, 200.0)))
		fr.owner = e
		owned.append(fr)
	var oldest: Dictionary = owned[0]
	for o in owned:
		if o.age > oldest.age:
			oldest = o
	oldest.part = true
	oldest.core = true
	oldest.spd = 0.0
	oldest.dmg = 0.0
	oldest.maxhp = e.maxhp * Bal.v("boss/path_core_hp", 0.04)
	oldest.hp = oldest.maxhp
	var ct: float = Bal.v("boss/path_core_time", 12.0)
	oldest.count_end = g.t + ct   # 倒计时环（界面与美术读 count_end / count_max）
	oldest.count_max = ct
	e.core = oldest
	e.core_until = g.t + ct
	g.vfx.add_text(oldest.pos + Vector2(0, -30), "核心", Color(1.0, 0.85, 0.4), 18)


## 圣徒装填被打断（docs/38 §8.2）：读条中累计受到 boss/saint_break_dmg（5%）最大生命的伤害，或主控冲刺穿过身体 →
## 大破绽 boss/saint_break（5 秒，break_t，受伤 ×1.4），弹药清空、转近战，boss/saint_reload_gap 秒后才会再装填
func saint_interrupt(e: Dictionary) -> void:
	if e.get("channel", 0.0) <= 0.0:
		return
	e.channel = 0.0
	e.ammo = 0
	e.ai = "melee"
	e.count_end = 0.0
	e.reload_t = Bal.v("boss/saint_reload_gap", 4.0)
	g.combat.start_break(e, Bal.v("boss/saint_break", 5.0))
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4), "enemy": true})
	g.vfx.add_text(e.pos + Vector2(0, -60), "装填被打断！", Color(1.0, 0.85, 0.4), 20)
	Sfx.play("boom", -6.0, 1.2, 0.0)


## Boss 招式冷却：到时返回 true 并重置
func _cd(e: Dictionary, key: String, dur: float) -> bool:
	if not e.has("cds"):
		e.cds = {}
	if e.cds.get(key, 0.0) <= g.t:
		e.cds[key] = g.t + dur * (SKILL_COOLDOWN_SCALE if e.boss else 1.0)
		return true
	return false



## Boss 招式预警：shape = circle / line / cone；dur 秒后结算 act
func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var w := {"shape": shape, "t": 0.0, "dur": dur, "owner": e, "pos": e.pos, "ang": 0.0, "r": 60.0, "len": 300.0, "wid": 14.0,
		"half": 0.8, "col": Color(1.0, 0.3, 0.35), "act": "", "dmg": e.dmg, "name": "", "corrode": 0.0, "done": false, "follow": false, "track": 0.0, "lock": true}
	w.merge(d, true)
	# 时序下限（§1.9、docs/48 P0-2）：Boss 预警总时长 ≥0.6 秒；锁定（追踪结束 → 结算）≥0.4 秒，不够时缩短追踪段
	if e.boss:
		w.dur = maxf(w.dur, 0.6)
		w.track = minf(w.track, maxf(0.0, w.dur - 0.4))
	# 冲刺 / 突刺的预警线长 = 实际冲出的距离（docs/48 P0-3：原来斥亡体画 190 冲 373、塑路者画 440 冲 214）：
	# 按击退每秒衰减 900 算，距离 = v²/1800 + 本体半径（自冲不受重型削减）。fit_len：按设计线长反推速度（骑士冲锋、塑路者冲撞要真冲到位）
	if w.act in ["dash", "stab"] and shape == "line":
		if w.get("fit_len", false):
			w.spd = sqrt(1800.0 * maxf(w.len - e.r, 40.0))
		else:
			var v: float = float(w.get("spd", 600.0 if w.act == "dash" else 800.0))
			w.len = v * v / 1800.0 + e.r
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
			if not e.dead or (w.shape == "circle" and not w.get("cancel_dead", false)):
				_warn_resolve(w)
	g.warns = g.warns.filter(func(w): return w.t < w.dur + 0.25)



func _warn_hit(w: Dictionary) -> bool:
	var pp: Vector2 = g.ppos + Vector2(0, -14)
	match w.shape:
		"circle":
			return g.combat.ground_d(g.ppos, w.pos) < w.r   # 画即判：主控脚底落在画出的椭圆里才算中（§1.9）
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
	# 伤害来源名：Boss 的招式记 boss_<类型>，普通怪 / 精英借用预警系统的招式记 atk_<类型>（引痕者前刺、钻地咬击、踏地等；
	# 原来一律记 boss_，统计里被误算成 Boss。Boss 保护看的是 enemy_hit 的 boss 标记 = e.boss，不看这个名字）
	g.dmg_src = ("boss_" if e.boss else "atk_") + e.type
	g.in_type = ["远程", "法术"] if w.act in ["pillar", "burst", "beam", "bring", "pattern_rain", "tide_link"] else (["远程", "物理"] if w.act == "shot" else ["近战", "物理"])
	var true_damage: bool = w.get("true", false)
	if true_damage:
		g.in_type = ["远程" if w.act in ["ishar_strike", "ishar_line", "ishar_volley", "ishar_echo"] else "近战", "真实"]
	if g.invuln <= 0.0:
		var hp_before: float = g.hp
		g.combat.enemy_hit(w.dmg, {"corrode": w.corrode, "boss": e.boss, "nerve": float(w.get("nerve", 0.0)),
			"frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "hit_cap": e.get("hit_cap", 0.0), "src_type": e.type, "warn": true}, true_damage, true)   # 预警系统精英也在用（钻地咬击、踏地），按放招的敌人算
		if not e.boss and g.hp < hp_before and float(w.get("stun", 0.0)) > 0.0 and g.t >= g.combat.enemy_stun_next:
			g.combat.enemy_stun_next = g.t + 8.0
			if not g.combat.stun_as_slow():
				g.pstun = maxf(g.pstun, minf(float(w.stun), 0.25))
		if stun_t > 0.0 and not g.combat.stun_as_slow(e.boss):   # Boss 战里僵直改成减速（docs/38 §1.11）
			g.pstun = maxf(g.pstun, stun_t)
		if slow and not g.combat.atk_slow_as_slow(3.0, e.boss):   # Boss 来源不写 atk_slow，改成移速减速（docs/38 §1.11）
			g.atk_slow = 3.0



func _warn_resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var c: Color = w.col
	if e.boss:
		# 预警结束后明确重新起攻击动作，而不是沿用蓄力末帧。
		e.pose = 0.35
		e.pose_max = 0.35
	# 出手事件（给画面层画攻击特效用，界面与美术读）：动作、形状、位置、朝向、范围、时刻
	e.last_act = {"act": w.act, "shape": w.shape, "pos": w.pos, "ang": w.ang, "r": w.r, "len": w.len, "wid": w.wid, "half": w.half, "t": g.t}
	if w.get("secondary", false):
		e.atk_until = g.t + 0.35
	var dv := Vector2.from_angle(w.ang)
	if str(w.act).begins_with("pattern_"):
		patterns.resolve(w)
		return
	if w.act == "tide_link" and (e.get("partner") == null or not e.partner.get("coma", false)):
		return
	if e.get("boss", false):
		g.vfx.boss_signature(w)
	match w.act:
		"frost_track":
			g.fx.append({"kind": "frost_track", "a": w.pos, "b": w.pos + dv * w.len,
				"life": 1.0, "max": 1.0, "enemy": true})
			for i in 8:
				var pos: Vector2 = w.pos + dv * w.len * (float(i) + 0.5) / 8.0
				g.fx.append({"kind": "frost_step", "pos": pos, "r": 13.0, "life": 0.9, "max": 0.9, "enemy": true})
			g.vfx.fx_sprite("fx_knight_impact", w.pos + dv * w.len, g.PX * 1.2)
			g.vfx.sparks(w.pos + dv * w.len, dv, c, 10, 180.0)
			e.hunt_angle = w.ang
			e.hunt_follow_at = g.t + 0.25
			Sfx.play("hit", -9.0, 1.4)
			_warn_damage(w)
		"tide_link":
			g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.55, "max": 0.55, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos + dv * w.len, g.PX * 1.2)
			Sfx.play("tentacle", -8.0, 1.1)
			_warn_damage(w)
		"ishar_echo":
			g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.55, "max": 0.55, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos, g.PX * 1.0)
			Sfx.play("tentacle", -8.0, 1.25)
			_warn_damage(w)
		"extra_volley":
			var a: Dictionary = w.extra
			var count: int = mini(int(a.count), 5)
			var kind: String = D.ENEMIES[e.type].get("shot_kind", "orb")
			var speed: float = float(a.speed)
			var spread: float = float(a.spread)
			for i in count:
				if g.ebullets.size() >= 240:
					break
				var angle: float = w.ang + lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, float(count - 1)))
				g.ebullets.append({"pos": w.pos, "vel": Vector2.from_angle(angle) * speed, "dmg": w.dmg,
					"r": 5.0, "life": 2.4, "slow": false, "frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "corrode": e.corrode,
					"nerve": float(w.get("nerve", 0.0)), "true": false, "kind": kind, "home": false,
					"atk": D.ENEMIES[e.type].get("atk", "法术"), "boss": false, "source_id": e.id})
			g.fx.append({"kind": "rays", "pos": w.pos, "life": 0.25, "max": 0.25, "col": c, "enemy": true})
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
		"ishar_strike":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.45, "max": 0.45, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, c, 10, 230.0)
			Sfx.play("tentacle", -6.0, 1.2)
			g.vfx.shake_screen(0.3)
			_warn_damage(w)
		"ishar_line":
			g.fx.append({"kind": "bbeam", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.28, "max": 0.28, "col": c, "wid": w.wid})
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
			g.vfx.shake_screen(0.25)
			_warn_damage(w)
		"ishar_volley":
			g.eai.shoot(e, dv)
			e.cdt = maxf(e.cdt, e.cd * 0.82)
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
			g.vfx.sparks(w.pos + dv * 24.0, dv, c if w.get("secondary", false) else Color(2.0, 1.6, 0.8), 8, 320.0)
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
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.45
			e.pose = 0.45
			e.pose_max = 0.45
			g.vfx.sparks(e.pos, -dv, Color(0.9, 0.9, 1.0), 10, 200.0)
			Sfx.play("swing", -4.0, 0.5)
		"stab":
			e.kb = dv * w.get("spd", 800.0)
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.2
			e.pose = 0.25
			e.pose_max = 0.25
			g.fx.append({"kind": "tracer", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.22, "max": 0.22, "col": c, "wid": w.wid})
			Sfx.play("swing", -6.0, 0.7)
			_warn_damage(w)
		"spawn":
			# 预告后生成（投嗣育母的注亡拟嗣，docs/48 P0-7）
			g.spawner.spawn_enemy(w.spawn, w.pos)
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
		"bite":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.25, "max": 0.25, "col": c})
			g.vfx.sparks(w.pos + dv * w.r * 0.65, dv, c, 6, 150.0)
			Sfx.play("swing", -6.0, 0.9)
			_warn_damage(w)
		"bring":
			for k in 14:
				var d2 := Vector2.from_angle(TAU * k / 14.0 + w.t)
				g.ebullets.append({"pos": w.pos, "vel": d2 * 252.0, "dmg": w.dmg, "slow": true, "r": 7.0, "life": 3.0,
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
