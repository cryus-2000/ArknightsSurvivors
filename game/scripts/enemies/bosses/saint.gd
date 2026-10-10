## 圣徒伊比利亚 / 圣徒卡门（type iberia / carmen，docs/38 §2.2）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 圣徒（本项目设定：同一人物两档，原作依据 PRTS 圣徒卡门 / 圣徒伊比利亚；docs/38 §2.2）：弹药（enemies.json ammo：卡门 3、伊比利亚 1）打空后近战；
	# 打空才装填，装填中被打断会跪地破绽。伊比利亚（强化档）：裁决射线（贯穿全屏）；卡门（常规档）：狙击（锁定线）、退避跳
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
	# 卡门第二幕：弹药打空先「炮身近战」boss/carmen_sword 秒（贴身冲撞 + 炮身横扫），再装填（§8.3；10-01 起不再是剑，判定不变）
	if e.get("sword_t", 0.0) > 0.0:
		e.sword_t -= dt
		if ready and dist < 240.0 and _cd(e, "sword", 1.6):
			if dist > 100.0:
				_warn(e, "line", 0.6, {"ang": dir.angle(), "wid": 20.0, "track": 0.2, "act": "stab", "spd": 600.0, "name": "炮身突进", "col": Color(1.0, 0.35, 0.3), "dmg": e.dmg * 1.3})
			else:
				_warn(e, "cone", 0.6, {"ang": dir.angle(), "half": 0.9, "r": 110.0, "track": 0.2, "act": "bite", "name": "炮身横扫", "col": Color(1.0, 0.35, 0.3), "dmg": e.dmg * 1.4})
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
			e.ammo = int(D.ENEMIES[e.type].get("ammo", 3))   # 卡门 3 发、伊比利亚 1 发（数值 10-01）
			e.ai = "ranged"
			e.count_end = 0.0
			g.vfx.add_text(e.pos + Vector2(0, -44), "装填完毕", Color(1.0, 0.8, 0.5), 14)
			for k in 3:
				_warn(e, "line", 0.9 + 0.6 * k, {"ang": dir.angle(), "len": 980.0, "wid": 14.0, "track": 0.3 + 0.6 * k, "act": "shot",
					"name": "三连瞄准" if k == 0 else "", "col": Color(1.0, 0.8, 0.4), "dmg": e.dmg * Bal.v("boss/saint_volley_mult", 1.2), "lock": k == 0})
	else:
		e.reload_t -= dt
		# 弹药打空才装填（原来每 14 秒一次）；卡门第二幕先炮身近战
		if e.ammo <= 0 and e.reload_t <= 0.0 and e.get("sword_t", 0.0) <= 0.0 and e.stun <= 0.0 and e.wind <= 0.0 and e.get("break_t", 0.0) <= 0.0:
			if e.type == "carmen" and e.get("gates_passed", 0) >= 1 and not e.get("sword_done", false):
				e.sword_t = Bal.v("boss/carmen_sword", 8.0)
				e.sword_done = true
				e.ai = "melee"
				g.vfx.add_text(e.pos + Vector2(0, -50), "炮身近战", Color(1.0, 0.5, 0.4), 18)
				Sfx.play("carmen_sword", -2.1, 1.0, 0.0)
			else:
				e.sword_done = false
				var rt: float = Bal.v("boss/iberia_reload", 2.2) if e.type == "iberia" else Bal.v("boss/carmen_reload", 3.0)   # 伊比利亚强化档装填 4 → 2.2 秒（数值 10-01）
				e.channel = rt
				e.reload_dmg = 0.0
				e.count_end = g.t + rt   # 读条环（界面与美术读 count_end / count_max）
				e.count_max = rt
				g.vfx.add_text(e.pos + Vector2(0, -44), "装填中……", Color(1.0, 0.8, 0.5), 16)


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
