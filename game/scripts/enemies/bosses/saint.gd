## 圣徒伊比利亚 / 圣徒卡门（type iberia / carmen，docs/38 §2.2；招式改版 docs/95 §6 / §7，10-14 第 2 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 伊比利亚（docs/142b §3.3 / §8.2 样板，10-25）：主轴「打断」——躲过手炮，趁装填冲刺穿身（一幕累计打掉 5% 也算）打断 → 晕眩，起身补满弹药再开炮。
##   一幕：手炮（② Kanpelle 橙色光束 3 倍粗）/ 轰击（① 曲射）；装填完毕没被打断 = 手炮·三连
##   二幕「延生」：装填 1.4 秒、只认冲刺穿身；装填一开始打出三连曲射（落点三角围住自己）；靠近时先抡一下；散射 2 波错位（patterns，phase_min 1）；
##         没打断 = 清膛 + 手炮·三连
## 卡门（docs/142b §3.4 / §8.2，10-25）：主轴「封锁线」——弹药 3 发，每枪狙击打完留一条带缺口的火线 6 秒（碰到掉血 + 减速），
##   三枪把场地切成跑道，玩家边跑边 S 形穿缺口绕到她身边；三枪后装填 3 秒（火线消退）= 压上去的窗口；冲刺穿身 / 累计 5% 打断 → 破绽，起身补满弹药。
##   一幕：第一枪瞄你，后两枪与它平行、左右各偏 carmen_lane_off；B 炮身横扫（贴脸）/ C 环射（④，patterns，不耗弹）/ 退避跳
##   二幕「守誓」：第三枪改成垂直穿过你脚下（锁你所在的跑道，1 秒里穿缺口换格）；装填一开始退避跳到远处，追上去吃 D 炮身砸击
## 机制不占名额：弹药、装填 / 打断 / 跪地破绽、站定窗口、远程段超时转近战、退避跳、炮身近战段
extends "res://scripts/enemies/bosses/boss_base.gd"

const MOVES_IBERIA := ["手炮", "轰击", "三连曲射", "抡击", "散射", "清膛"]
const MOVES_CARMEN := ["狙击", "炮身横扫", "环射", "炮身砸击"]
const TINT2_IBERIA := Color(1.14, 0.9, 0.84)   # 第二幕常驻橙红（斗篷边缘发红，docs/95 §6.2）
const TINT2_CARMEN := Color(1.12, 1.04, 0.86)   # 第二幕常驻金色亮边（docs/95 §7.2）


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 圣徒（本项目设定：同一人物两档，原作依据 PRTS 圣徒卡门 / 圣徒伊比利亚；docs/38 §2.2）：弹药（enemies.json ammo：卡门 3、伊比利亚 1）打空后近战；
	# 打空才装填，装填中被打断会跪地破绽。远程段最长 boss/saint_ranged_max 秒：到时弹药作废转近战追击。不然她剩一发子弹、站在射程外被签名招式拖着，
	# 永远打不空也不近身（9/29 实测伊比利亚卡在 50% 190 秒）
	var p2: bool = int(e.get("gates_passed", 0)) >= 1
	if p2:
		_tint2(e, TINT2_IBERIA if e.type == "iberia" else TINT2_CARMEN)
	if e.type != "iberia":
		_fire_step(e, dt)
	# 打断后起身：直接补满弹药、转回远程，0.8 秒后开火（不再装填——不然每次装填都能被打断，永远开不了火）
	if e.get("refill_on_rise", false) and float(e.get("break_t", 0.0)) <= 0.0 and e.stun <= 0.0:
		e.refill_on_rise = false
		e.ammo = int(D.ENEMIES[e.type].get("ammo", 1))
		e.ai = "ranged"
		e.reload_t = 0.0
		var cds: Dictionary = e.get("cds", {})
		var key: String = "judge" if e.type == "iberia" else "snipe"
		cds[key] = minf(float(cds.get(key, 0.0)), g.t + Bal.v("boss/iberia_rise_shot", 0.8))
		e.cds = cds
	if e.ai == "ranged" and e.channel <= 0.0:
		e.ranged_t = e.get("ranged_t", 0.0) + dt
		if e.ranged_t >= Bal.v("boss/saint_ranged_max", 6.0):
			_empty(e)
	else:
		e.ranged_t = 0.0
		# 近战追击段加速（e.haste：移速 ×1.4），真的追上来，破绽和读条才会在编队射程里发生
		if e.ai == "melee" and e.channel <= 0.0:
			e.haste = maxf(e.get("haste", 0.0), 0.1)
	# 装填打断（docs/38 §8.2）：读条中主控冲刺穿过她的身体也算打断
	if e.channel > 0.0 and _dash_through(e):
		saint_interrupt(e)
	# 伊比利亚第二幕装填完毕：清膛 → 手炮·三连（第一次先亮招式名 0.6 秒，期间 wind 占住出招窗口）
	if e.get("reload_follow", false):
		if _first_tell(e, "clear", "清膛"):
			e.reload_follow = false
			_clear(e, dir, dist)
			_volley(e, dir, 1.0)
		return
	# 卡门第二幕：弹药打空先「炮身近战」boss/carmen_sword 秒，再装填（§8.3）：近身横扫、100–240 炮身砸击（取代原炮身突进）
	if e.get("sword_t", 0.0) > 0.0:
		e.sword_t -= dt
		if ready:
			if dist < 110.0 and _cd(e, "sweep", 1.6):
				_sweep(e, dir)
			elif dist >= 100.0 and dist < 240.0 and float(e.get("cds", {}).get("smash", 0.0)) <= g.t:
				if _first_tell(e, "smash", "炮身砸击") and _cd(e, "smash", 1.6):
					_smash(e, dir)
	elif ready and e.channel <= 0.0:
		if e.type == "iberia":
			# C 轰击（有弹药、主控 160–520、lob 13 秒）与 A 手炮共用弹药：这一轮放了轰击就不放手炮
			if e.ammo > 0 and dist >= 160.0 and dist <= 520.0 and _cd(e, "lob", 13.0):
				_lob(e)
			elif e.ammo > 0 and _cd(e, "judge", 11.0):
				_cannon(e, dir)
		elif e.type == "carmen":
			# B 炮身横扫（两幕都有）：主控 <110，sweep 5 秒（弹药空的近战段 1.6 秒）
			if dist < 110.0 and _cd(e, "sweep", 1.6 if e.ai == "melee" else 5.0):
				_sweep(e, dir)
			# 退避跳：冷却 5 → 9 秒、距离缩短（720 → 480，约 128 像素），落地后站定 boss/saint_stand 秒（给低射程编队输出窗口）
			elif dist < 130.0 and _cd(e, "hop", Bal.v("boss/carmen_hop_cd", 9.0)):
				e.kb = -dir * Bal.v("boss/carmen_hop_spd", 480.0)
				e.wind = maxf(e.wind, 0.35 + Bal.v("boss/saint_stand", 1.5))
				e.pose = 0.35
				e.pose_max = 0.35
				g.vfx.sparks(e.pos, dir, Color(0.8, 0.8, 0.7), 10, 160.0)
				g.vfx.add_text(e.pos + Vector2(0, -50), "退避", Color(0.9, 0.9, 0.8), 14)
				Sfx.play("dodge", -8.0)
			elif e.ammo > 0 and _cd(e, "snipe", Bal.v("boss/carmen_lane_gap", 1.3)):
				_lane_shot(e, dir, int(D.ENEMIES[e.type].get("ammo", 3)) - int(e.ammo))
	# 伊比利亚二幕：装填中主控靠近（iberia_swing_r 90 内）先抡一下（原作近战模式），每次装填一次；冲刺无敌可以穿过去
	if e.type == "iberia" and p2 and e.channel > 0.0 and dist < Bal.v("boss/iberia_swing_r", 90.0) and not e.get("reload_swung", false):
		e.reload_swung = true
		_sweep(e, dir, "抡击", Bal.v("boss/iberia_swing_mult", 1.2))
	# 卡门二幕：装填中主控追到 100–240 内，炮身砸击一次（docs/142b §8.2「惩罚」）
	if e.type == "carmen" and p2 and e.channel > 0.0 and dist >= 100.0 and dist < 240.0 and not e.get("reload_smashed", false):
		e.reload_smashed = true
		_smash(e, dir)
	if e.channel > 0.0:
		e.channel -= dt
		if e.channel <= 0.0:
			# 没被打断：装填完毕。伊比利亚第二幕先清膛再三连，一幕直接三连（间隔 0.6 秒，都可以走开躲）；卡门直接回到封锁线三枪
			e.ammo = int(D.ENEMIES[e.type].get("ammo", 3))   # 卡门 3 发、伊比利亚 1 发（数值 10-01）
			e.ai = "ranged"
			e.count_end = 0.0
			g.vfx.add_text(e.pos + Vector2(0, -44), "装填完毕", Color(1.0, 0.8, 0.5), 14)
			if e.type == "iberia" and p2:
				e.reload_follow = true
			elif e.type == "iberia":
				_volley(e, dir, 0.0)
	else:
		e.reload_t -= dt
		# 弹药打空才装填（原来每 14 秒一次）；卡门第二幕先炮身近战
		if e.ammo <= 0 and e.reload_t <= 0.0 and e.get("sword_t", 0.0) <= 0.0 and e.stun <= 0.0 and e.wind <= 0.0 and e.get("break_t", 0.0) <= 0.0:
			if false and e.type == "carmen" and p2 and not e.get("sword_done", false):   # 炮身近战段由封锁线取代（docs/142b §3.4）
				e.sword_t = Bal.v("boss/carmen_sword", 8.0)
				e.sword_done = true
				e.ai = "melee"
				g.vfx.add_text(e.pos + Vector2(0, -50), "炮身近战", Color(1.0, 0.5, 0.4), 18)
				Sfx.play("carmen_sword", -2.1, 1.0, 0.0)
			else:
				e.sword_done = false
				var rt: float = Bal.v("boss/iberia_reload", 2.2) if e.type == "iberia" else Bal.v("boss/carmen_reload", 3.0)   # 伊比利亚强化档装填 4 → 2.2 秒（数值 10-01）
				if e.type == "iberia" and p2:
					rt = Bal.v("boss/iberia_reload_p2", 1.4)   # 二幕「延生」装填更快（docs/142b §3.3）
					_tri_lob(e)
				e.reload_swung = false
				e.reload_smashed = false
				if e.type == "carmen":
					# 装填开始：火线在装填时间里消退（窗口）；二幕退避跳到远处，压上去要多跑一段
					for fl in e.get("fire_lines", []):
						fl.until = minf(float(fl.until), g.t + rt)
					if p2:
						var away: Vector2 = (e.pos - g.ppos).normalized() if e.pos.distance_to(g.ppos) > 1.0 else Vector2.RIGHT
						e.kb = away * Bal.v("boss/carmen_reload_hop", 720.0)
						g.vfx.sparks(e.pos, away, Color(0.9, 0.9, 0.8), 12, 180.0)
						g.vfx.add_text(e.pos + Vector2(0, -50), "退避", Color(0.95, 0.92, 0.85), 14)
				e.channel = rt
				e.reload_dmg = 0.0
				e.count_end = g.t + rt   # 读条环（界面与美术读 count_end / count_max）
				e.count_max = rt
				g.vfx.add_text(e.pos + Vector2(0, -44), "装填中……", Color(1.0, 0.8, 0.5), 16)


## 图鉴 / Boss 演练：直接进入第二幕（伊比利亚装填完毕放清膛、卡门炮身近战段）
func setup_preview_phase2(e: Dictionary) -> void:
	e.gates_passed = maxi(1, int(e.get("gates_passed", 0)))
	_tint2(e, TINT2_IBERIA if e.type == "iberia" else TINT2_CARMEN)


func demo_moves(e: Dictionary) -> Array:
	return MOVES_IBERIA if e.type == "iberia" else MOVES_CARMEN


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	e.ammo = int(D.ENEMIES[e.type].get("ammo", 3))   # 验收逐招放：每招前补满弹药（环射要 3 发）
	e.ai = "ranged"
	match name:
		"手炮":
			_cannon(e, dir)
			return true
		"轰击":
			_lob(e)
			return true
		"三连曲射":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_tri_lob(e)
			return true
		"抡击":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_sweep(e, dir, "抡击", Bal.v("boss/iberia_swing_mult", 1.2))
			return true
		"清膛":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_clear(e, dir, dist)
			return true
		"狙击":
			_lane_shot(e, dir, 0)
			return true
		"炮身横扫":
			_sweep(e, dir)
			return true
		"炮身砸击":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_smash(e, dir)
			return true
		"散射", "环射":
			e.pattern_force = name
			return g.bai.patterns.try_attack(e, dir, dist)
	return false


## 远程段超时：弹药作废 → 近战追击 boss/saint_melee 秒后才装填
func _empty(e: Dictionary) -> void:
	e.ammo = 0
	e.ai = "melee"
	e.reload_t = maxf(e.get("reload_t", 0.0), Bal.v("boss/saint_melee", 8.0))


## 伊比利亚 A · 手炮（原「裁决」，改原作技能名；docs/95 §6.2）：980 × 16 条纹线，追踪 0.55 秒后锁定，总 1.1 秒；e.dmg × 2.6（iberia_judge_mult）；
## 耗 1 发（原作弹药 1）；出手后原地站 boss/saint_stand 秒不动、不出招（协调人 9/27：给低射程编队输出窗口）
func _cannon(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 1.1, {"ang": dir.angle(), "len": 980.0, "wid": 16.0, "track": 0.55, "act": "shot", "name": "手炮", "col": Color(1.0, 0.75, 0.3), "dmg": e.dmg * Bal.v("boss/iberia_judge_mult", 2.6),
		"kp": "iberia", "kp_k": 3.0})   # 结算画 Kanpelle 橙色光束 3 倍粗（docs/142b §8.5）
	e.wind = maxf(e.wind, 1.1 + Bal.v("boss/saint_stand", 1.5))
	_spend(e, 1)


## 伊比利亚 C · 轰击（本作原创，取材 PRTS「手炮」单发极重：这一发曲射落地）：主控位置 r80 固定落点，起手即锁定，1.1 秒；e.dmg × 2.2；
## 炮弹是纯画面（g.fx lob_shell 从本体沿抛物线飞到圈心、地面画阴影，world.gd），落点留 1.5 秒火光（boss_ai lob）；耗 1 发
func _lob(e: Dictionary) -> void:
	var w := _warn(e, "circle", 1.1, {"pos": g.ppos, "r": 80.0, "act": "lob", "name": "轰击", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 2.2})
	g.fx.append({"kind": "lob_shell", "a": e.pos + Vector2(0, -30), "b": w.pos, "life": w.dur, "max": w.dur, "enemy": true})
	_spend(e, 1)


## 伊比利亚二幕 · 三连曲射（docs/142b §8.2「拦路」）：装填一开始，本体为心 iberia_tri_r（95）的三角三点各落一圈 r iberia_tri_cr（38），
## 角度随机转一下（g.rng_enemy）；1.1 秒结算，e.dmg × iberia_tri_mult（1.2）；不耗弹。三圈之间留缝，冲进去打断要从缝里穿
func _tri_lob(e: Dictionary) -> void:
	var rot: float = g.rng_enemy.randf() * TAU
	var r: float = Bal.v("boss/iberia_tri_r", 95.0)
	for k in 3:
		var at: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(rot + TAU * k / 3.0) * Vector2(r, r * g.combat.GROUND_Y), 60.0)
		var w := _warn(e, "circle", 1.1, {"pos": at, "r": Bal.v("boss/iberia_tri_cr", 38.0), "act": "lob", "name": "三连曲射" if k == 0 else "",
			"col": g.vfx.boss_color(e.type), "dmg": e.dmg * Bal.v("boss/iberia_tri_mult", 1.2), "lock": false})
		g.fx.append({"kind": "lob_shell", "a": e.pos + Vector2(0, -30), "b": w.pos, "life": w.dur, "max": w.dur, "enemy": true})


## 伊比利亚 D · 清膛（本作原创，取材 PRTS「装弹」完成的一刻）：enemies.json patterns「清膛」（on_reload）——
## 本体为心 r70 空心环、缺口朝主控，总 0.9 秒；18 发火药残渣弹 360px/s、寿命 1.8 秒，e.dmg × 0.6
func _clear(e: Dictionary, dir: Vector2, dist: float) -> void:
	e.pattern_force = "清膛"
	g.bai.patterns.try_attack(e, dir, dist)


## 装填完毕的三连（原三连瞄准）：伊比利亚「手炮·三连」、卡门「狙击·三连」，3 条 980 × 14 逐条锁定、每条间隔 0.6 秒，e.dmg × 1.2；
## delay：前面先放了清膛时整体往后挪
func _volley(e: Dictionary, dir: Vector2, delay: float) -> void:
	var nm: String = "手炮·三连" if e.type == "iberia" else "狙击·三连"
	for k in 3:
		var vw := _warn(e, "line", 0.9 + 0.6 * k + delay, {"ang": dir.angle(), "len": 980.0, "wid": 14.0, "track": 0.3 + 0.6 * k + delay, "act": "shot",
			"name": nm if k == 0 else "", "col": Color(1.0, 0.8, 0.4), "dmg": e.dmg * Bal.v("boss/saint_volley_mult", 1.2), "lock": k == 0})
		if e.type == "iberia":
			vw.kp = "iberia"   # 三连也画 Kanpelle 光束（1 倍粗）
			vw.kp_k = 2.0


## 卡门 A · 狙击（保留）：1100 × 10 条纹细线，追踪 0.6 秒后锁定，总 1.2 秒；e.dmg × 2.6；不耗弹（她的三发留给环射）
func _snipe(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 1.2, {"ang": dir.angle(), "len": 1100.0, "wid": 10.0, "track": 0.6, "act": "shot", "name": "狙击", "col": Color(1.0, 0.85, 0.4), "dmg": e.dmg * 2.6})


## 卡门 · 封锁线（docs/142b §3.4，本作拟；取材 PRTS 弹药 3）：k = 这一轮第几枪（0–2），耗 1 发。
## 第一枪瞄主控（追踪 0.6、总 1.2）；一幕后两枪与第一枪锁定的方向平行、起点左右偏 carmen_lane_off（150），不追踪（总 1.0）；
## 二幕第三枪垂直于第一枪、穿过主控当前位置（追踪 0.3、总 1.0）。结算画 Kanpelle 象牙白光束，然后留一条火线（_fire_step）
func _lane_shot(e: Dictionary, dir: Vector2, k: int) -> void:
	var p2: bool = int(e.get("gates_passed", 0)) >= 1
	var la: Dictionary = e.get("last_act", {})
	var base_ang: float = float(e.get("lane_ang", dir.angle()))
	if str(la.get("name", "")) == "狙击" and float(la.get("t", -1.0)) > float(e.get("lane_set_t", -1.0)) and k > 0:
		base_ang = float(la.ang)
	var pos: Vector2 = e.pos
	var ang: float = dir.angle()
	var track: float = 0.6
	var dur: float = 1.2
	if k == 0:
		e.lane_ang = ang
		e.lane_set_t = g.t
	elif p2 and k == 2:
		ang = base_ang + PI * 0.5
		pos = g.ppos - Vector2.from_angle(ang) * 550.0
		track = 0.3
		dur = 1.0
	else:
		ang = base_ang
		pos = e.pos + Vector2.from_angle(base_ang).orthogonal() * Bal.v("boss/carmen_lane_off", 150.0) * (1.0 if k == 1 else -1.0)
		track = 0.0
		dur = 1.0
	var q: Array = e.get("lane_gaps", [])
	q.append(g.rng_enemy.randf_range(0.3, 0.7))
	e.lane_gaps = q
	_warn(e, "line", dur, {"pos": pos, "ang": ang, "len": 1100.0, "wid": 10.0, "track": track, "act": "shot", "name": "狙击",
		"col": Color(1.0, 0.94, 0.82), "dmg": e.dmg * Bal.v("boss/carmen_lane_mult", 1.56), "kp": "carmen", "kp_k": 2.0, "lock": k == 0})   # 原 2.0（10-25 加密 ×0.78）
	_spend(e, 1)


## 封锁线：每枪狙击结算后（last_act「狙击」、新的一次）沿线留一条火线 carmen_fire_life（6）秒，线上一处缺口（gap_t 处、长 carmen_fire_gap 80）；
## 主控碰到（线宽内、不在缺口里、没有无敌）每 0.5 秒掉 e.dmg × carmen_fire_mult（0.35）、减速 0.8 一秒。火线画在 render/boss_beam.draw_ground
func _fire_step(e: Dictionary, dt: float) -> void:
	var la: Dictionary = e.get("last_act", {})
	var lines: Array = e.get("fire_lines", [])
	if str(la.get("name", "")) == "狙击" and float(la.get("t", -1.0)) > float(e.get("fire_last_t", -1.0)):
		e.fire_last_t = float(la.t)
		var q: Array = e.get("lane_gaps", [])
		var gt: float = float(q.pop_front()) if not q.is_empty() else 0.5
		e.lane_gaps = q
		var a: Vector2 = la.pos
		lines.append({"a": a, "b": a + Vector2.from_angle(float(la.ang)) * float(la.len), "gap_t": gt, "gap_len": Bal.v("boss/carmen_fire_gap", 80.0),
			"until": g.t + Bal.v("boss/carmen_fire_life", 7.5), "born": g.t})   # 原 6 秒（10-25 激光持续更长）
	lines = lines.filter(func(fl): return g.t < float(fl.until))
	e.fire_lines = lines
	if g.invuln > 0.0 or g.t < float(e.get("fire_hit_at", 0.0)):
		return
	var pp: Vector2 = g.ppos
	for fl in lines:
		var ab: Vector2 = fl.b - fl.a
		var L: float = ab.length()
		if L < 1.0:
			continue
		var t: float = clampf((pp - fl.a).dot(ab) / (L * L), 0.0, 1.0)
		if (fl.a + ab * t).distance_to(pp) > 14.0:
			continue
		if absf(t - float(fl.gap_t)) * L < float(fl.gap_len) * 0.5:
			continue   # 站在缺口里
		e.fire_hit_at = g.t + 0.5
		g.combat.enemy_hit(e.dmg * Bal.v("boss/carmen_fire_mult", 0.35), {"boss": true, "src_type": e.type}, false, true, ["远程", "物理"], "boss_" + e.type)
		g.combat.slow_leader("carmen_fire", 1.0, 0.8)
		break


## 卡门 B · 炮身横扫（保留，两幕都有）：扇形 r110 半角 0.9，追踪 0.2 秒，总 0.8 秒（锁定 ≥ 0.51）；e.dmg × 1.4
func _sweep(e: Dictionary, dir: Vector2, nm := "炮身横扫", mult := 1.4) -> void:
	_warn(e, "cone", 0.8, {"ang": dir.angle(), "half": 0.9, "r": 110.0, "track": 0.2, "act": "bite", "name": nm, "col": g.vfx.boss_color(e.type), "dmg": e.dmg * mult,
		"lock": e.channel <= 0.0})   # 装填中的抡击不占出招窗口（装填照常读条）


## 卡门 D · 炮身砸击（本作原创，取材 PRTS 近战模式；取代炮身突进）：主控位置 r70 落点圈，起手即锁定，0.9 秒（锁定 ≥ 0.88）；
## 起手同时冲到圈边（kb_self 位移，不判定线），结算 e.dmg × 1.3 物理、命中减速 0.5 秒（boss_ai smash）
func _smash(e: Dictionary, dir: Vector2) -> void:
	var w := _warn(e, "circle", 0.9, {"pos": g.ppos, "r": 70.0, "act": "smash", "name": "炮身砸击", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 1.3,
		"slow_t": 0.5, "slow_mult": 0.7, "slow_kind": "boss_move"})
	var to: Vector2 = w.pos - e.pos
	var go: float = to.length() - float(w.r)
	if go > 4.0:
		e.kb = to.normalized() * sqrt(1800.0 * go)   # 击退每秒衰减 900：v² / 1800 = 冲出的距离
		e.kb_self = true
		e.dash_dir = dir


## 手炮 / 轰击耗弹；打空就转近战，站定窗口结束后装填（与 patterns 耗弹打空同口径，不加 saint_melee 追击段）
func _spend(e: Dictionary, n: int) -> void:
	e.ammo = maxi(0, int(e.ammo) - n)
	if e.ammo <= 0:
		e.ai = "melee"


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
	e.refill_on_rise = true   # 起身直接补满弹药再开火（docs/142b §3.3 / §3.4），不再装填
	g.combat.start_break(e, Bal.v("boss/saint_break", 5.0))
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4), "enemy": true})
	g.vfx.add_text(e.pos + Vector2(0, -60), "装填被打断！", Color(1.0, 0.85, 0.4), 20)
	Sfx.play("boom", -6.0, 1.2, 0.0)


## ---- 受击钩子（docs/101 B1c，10-15 从 combat.gd 搬来）
## 装填读条中累计伤害达到 boss/saint_break_dmg（5%）最大生命才打断（原来挨一下就打断、僵直 6 秒；docs/38 §8.2）
func on_damaged(e: Dictionary, dmg: float, _eff: float) -> void:
	if e.type == "iberia" and int(e.get("gates_passed", 0)) >= 1:
		return   # 二幕「延生」：累计伤害不再打断，只认冲刺穿身（docs/142b §3.3）
	if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
		e.reload_dmg = e.get("reload_dmg", 0.0) + dmg
		if e.reload_dmg >= e.maxhp * Bal.v("boss/saint_break_dmg", 0.05):
			saint_interrupt(e)
