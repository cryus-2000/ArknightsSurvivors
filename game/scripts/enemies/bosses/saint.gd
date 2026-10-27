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

## 出招组（docs/171，10-27 用户：打 Boss 要有图案、有规律可学、有节奏和压迫感；东方只是例子，不照搬符卡制度）：每幕 2 组，
## 每次补满弹药（装填完毕 / 打断起身）换下一组，幕制沿用 50% 卡点。seq = 一组连携（≤4 段，打空弹药 → 装填 = 收招破绽，主轴窗口）；
## name 只写进文档和血条副标题的招式名，都是本作改编（原作只有手炮 / 弹药 / 装填），不冒充原作技能。
## tri_crater：伊比利亚二幕装填时的三连曲射落地放弹坑碎弹
const CARDS := {
	"iberia": [
		[{"name": "手炮 · 炮线", "seq": ["cannon"]},
			{"name": "轰击 · 弹坑", "seq": ["lob"]}],
		[{"name": "延生 · 重炮弹", "seq": ["scatter", "shell"]},
			{"name": "延生 · 三角弹坑", "seq": ["lob_free", "cannon"], "tri_crater": true}],
	],
	"carmen": [
		[{"name": "狙击 · 封锁线", "seq": ["snipe", "snipe", "snipe"]},
			{"name": "狙击 · 曳光弹列", "seq": ["stream", "snipe", "snipe"]}],
		[{"name": "守誓 · 交叉封锁", "seq": ["snipe", "snipe", "snipe"]},
			{"name": "守誓 · 交叉弹列", "seq": ["ring", "xstream", "snipe", "snipe"]}],
	],
}
const COMBO_CAP := 18.0       # 一组出招的保护上限（同骑士连段，docs/169）
const SEG_GAP := 0.35         # 段间收势
const GLINT := Color(1.0, 0.32, 0.26)   # 出弹前的红色闪点 = 预警（红只给危险）
const CLEAR_COL := Color(1.0, 0.94, 0.78)   # 打断装填时她的在飞弹体化成的淡金白颗粒

const MOVES_IBERIA := ["手炮", "轰击", "三连曲射", "抡击", "散射", "清膛", "重炮弹"]
const MOVES_CARMEN := ["狙击", "炮身横扫", "环射", "炮身砸击", "曳光弹列", "交叉弹列"]
const TINT2_IBERIA := Color(1.14, 0.9, 0.84)   # 第二幕常驻橙红（斗篷边缘发红，docs/95 §6.2）
const TINT2_CARMEN := Color(1.12, 1.04, 0.86)   # 第二幕常驻金色亮边（docs/95 §7.2）


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# 圣徒（本项目设定：同一人物两档，原作依据 PRTS 圣徒卡门 / 圣徒伊比利亚；docs/38 §2.2）：弹药（enemies.json ammo：卡门 3、伊比利亚 1）打空后近战；
	# 打空才装填，装填中被打断会跪地破绽。远程段最长 boss/saint_ranged_max 秒：到时弹药作废转近战追击。不然她剩一发子弹、站在射程外被签名招式拖着，
	# 永远打不空也不近身（9/29 实测伊比利亚卡在 50% 190 秒）
	if not e.has("dmg_k"):
		# 单发伤害旋钮（协调人 10-27：弹幕变密，整体先 ×0.8，云端测完再定）：出场第一帧乘到 e.dmg 上，所有招式 / 弹体 / 火线 / 接触伤害一起缩
		e.dmg_k = Bal.v("boss/saint_dmg_mult", 0.8) if e.type == "iberia" else Bal.v("boss/carmen_dmg_mult", 1.3)   # 测试台 10-27 / 10-28：卡门 ×0.8 承伤只剩 15%，加收束后仍偏软
		e.dmg = float(e.dmg) * float(e.dmg_k)
		# 血量旋钮（协调人 10-27 测试台：单场 24–30 秒招式放不全，目标 45–75 秒）：出场第一帧乘到生命上（在 hp_mid / hp_x_ 之后）
		var hk: float = Bal.v("boss/iberia_hp_k", 2.9) if e.type == "iberia" else Bal.v("boss/carmen_hp_k", 2.4)
		e.hp = float(e.hp) * hk
		e.maxhp = float(e.maxhp) * hk
		e.budget_rate = float(e.get("budget_rate", 0.0)) * hk
	var p2: bool = int(e.get("gates_passed", 0)) >= 1
	if p2:
		_tint2(e, TINT2_IBERIA if e.type == "iberia" else TINT2_CARMEN)
	if e.type != "iberia":
		_fire_step(e, dt)
	_card_tick(e, p2)
	_bullets_step(e, dt)
	_watch_step(e)
	_pressure_step(e, dt, p2)
	# 打断后起身：直接补满弹药、转回远程，0.8 秒后开火（不再装填——不然每次装填都能被打断，永远开不了火）
	if e.get("refill_on_rise", false) and float(e.get("break_t", 0.0)) <= 0.0 and e.stun <= 0.0:
		e.refill_on_rise = false
		e.ammo = int(D.ENEMIES[e.type].get("ammo", 1))
		e.ai = "ranged"
		e.reload_t = 0.0
		e.wind = maxf(float(e.get("wind", 0.0)), Bal.v("boss/iberia_rise_shot", 0.8))
		_card_cycle(e)
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
			# 出招全部走当前出招组的队列（轰击 / 手炮 / 重炮弹共用 1 发弹药，打空就装填）
			if e.ammo > 0:
				_card_run(e, dir, dist)
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
			elif e.ammo > 0:
				_card_run(e, dir, dist)
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
			_card_cycle(e)
			if e.type == "iberia" and p2:
				e.reload_follow = true
			elif e.type == "iberia":
				_volley(e, dir, 0.0)
	else:
		e.reload_t -= dt
		# 弹药打空才装填（原来每 14 秒一次）；卡门第二幕先炮身近战
		var can_reload: bool = e.ammo <= 0 and e.reload_t <= 0.0 and e.get("sword_t", 0.0) <= 0.0 and e.stun <= 0.0 and e.wind <= 0.0 and e.get("break_t", 0.0) <= 0.0
		# 伊比利亚装填前先压上来（协调人 10-27：装填窗口要让近战够得到）：离主控 > iberia_reload_r 时先追 iberia_reload_walk 秒再原地装填
		if can_reload and e.type == "iberia" and dist > Bal.v("boss/iberia_reload_r", 160.0) and float(e.get("app_t", 0.0)) < Bal.v("boss/iberia_reload_walk", 1.8):
			e.app_t = float(e.get("app_t", 0.0)) + dt
			e.haste = maxf(e.get("haste", 0.0), 0.1)
			can_reload = false
		if can_reload:
			e.app_t = 0.0
			if false and e.type == "carmen" and p2 and not e.get("sword_done", false):   # 炮身近战段由封锁线取代（docs/142b §3.4）
				e.sword_t = Bal.v("boss/carmen_sword", 8.0)
				e.sword_done = true
				e.ai = "melee"
				g.vfx.add_text(e.pos + Vector2(0, -50), "炮身近战", Color(1.0, 0.5, 0.4), 18)
				Sfx.play("carmen_sword", -2.1, 1.0, 0.0)
			else:
				e.sword_done = false
				var rt: float = Bal.v("boss/iberia_reload", 3.0) if e.type == "iberia" else Bal.v("boss/carmen_reload", 3.0)   # 伊比利亚强化档装填 4 → 2.2 秒（数值 10-01）；10-27 测试台破绽输出 3%，2.2 → 3.0
				if e.type == "iberia" and p2:
					rt = Bal.v("boss/iberia_reload_p2", 2.6)   # 二幕「延生」装填更快（docs/142b §3.3 原 1.4；10-27 输出窗口探针 1.4 秒不够，docs/171 §6）
					var tri: Array = _tri_lob(e)
					if _card(e).get("tri_crater", false):
						for tw in tri:
							_watch(e, tw, "crater_tri")
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
		"重炮弹":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_shell(e, dir)
			return true
		"曳光弹列":
			_stream(e, dir, false)
			return true
		"交叉弹列":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_stream(e, dir, true)
			return true
	return false


## 远程段超时：弹药作废 → 近战追击 boss/saint_melee 秒后才装填
func _empty(e: Dictionary) -> void:
	e.ammo = 0
	e.ai = "melee"
	e.reload_t = maxf(e.get("reload_t", 0.0), Bal.v("boss/saint_melee", 8.0))


## 伊比利亚 A · 手炮（原「裁决」，改原作技能名；docs/95 §6.2）：980 × 16 条纹线，追踪 0.55 秒后锁定，总 1.1 秒；e.dmg × 2.6（iberia_judge_mult）；
## 耗 1 发（原作弹药 1）；出手后原地站 boss/saint_stand 秒不动、不出招（协调人 9/27：给低射程编队输出窗口）
func _cannon(e: Dictionary, dir: Vector2) -> Dictionary:
	var w := _warn(e, "line", 1.1, {"ang": dir.angle(), "len": 980.0, "wid": 16.0, "track": 0.55, "act": "shot", "name": "手炮", "col": Color(1.0, 0.75, 0.3), "dmg": e.dmg * Bal.v("boss/iberia_judge_mult", 2.6),
		"kp": "iberia", "kp_k": 3.0, "saint_beam": true})   # 结算画 Kanpelle 橙色光束 3 倍粗（docs/142b §8.5）；蓄力 / 消散画在 render/saint_draw（docs/171 §7）
	e.wind = maxf(e.wind, 1.1 + Bal.v("boss/saint_stand", 1.5))
	_spend(e, 1)
	return w


## 伊比利亚 C · 轰击（本作原创，取材 PRTS「手炮」单发极重：这一发曲射落地）：主控位置 r80 固定落点，起手即锁定，1.1 秒；e.dmg × 2.2；
## 炮弹是纯画面（g.fx lob_shell 从本体沿抛物线飞到圈心、地面画阴影，world.gd），落点留 1.5 秒火光（boss_ai lob）；耗 1 发（spend = false：连携里不耗弹的追加一发）
func _lob(e: Dictionary, spend := true) -> Dictionary:
	var w := _warn(e, "circle", 1.1, {"pos": g.ppos, "r": 80.0, "act": "lob", "name": "轰击", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 2.2})
	g.fx.append({"kind": "lob_shell", "a": e.pos + Vector2(0, -30), "b": w.pos, "life": w.dur, "max": w.dur, "enemy": true})
	if spend:
		_spend(e, 1)
	return w


## 伊比利亚二幕 · 三连曲射（docs/142b §8.2「拦路」）：装填一开始，本体为心 iberia_tri_r（95）的三角三点各落一圈 r iberia_tri_cr（38），
## 角度随机转一下（g.rng_enemy）；1.1 秒结算，e.dmg × iberia_tri_mult（1.2）；不耗弹。三圈之间留缝，冲进去打断要从缝里穿
func _tri_lob(e: Dictionary) -> Array:
	var rot: float = g.rng_enemy.randf() * TAU
	var r: float = Bal.v("boss/iberia_tri_r", 95.0)
	var out := []
	for k in 3:
		var at: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(rot + TAU * k / 3.0) * Vector2(r, r * g.combat.GROUND_Y), 60.0)
		var w := _warn(e, "circle", 1.1, {"pos": at, "r": Bal.v("boss/iberia_tri_cr", 38.0), "act": "lob", "name": "三连曲射" if k == 0 else "",
			"col": g.vfx.boss_color(e.type), "dmg": e.dmg * Bal.v("boss/iberia_tri_mult", 1.2), "lock": false})
		g.fx.append({"kind": "lob_shell", "a": e.pos + Vector2(0, -30), "b": w.pos, "life": w.dur, "max": w.dur, "enemy": true})
		out.append(w)
	return out


## 伊比利亚 D · 清膛（本作原创，取材 PRTS「装弹」完成的一刻）：enemies.json patterns「清膛」（on_reload）——
## 本体为心 r70 空心环、缺口朝主控，总 0.9 秒；18 发火药残渣弹 360px/s、寿命 1.8 秒，e.dmg × 0.6
func _clear(e: Dictionary, dir: Vector2, dist: float) -> void:
	e.pattern_force = "清膛"
	g.bai.patterns.try_attack(e, dir, dist)


## 装填完毕的三连（原三连瞄准）：伊比利亚「手炮·三连」、卡门「狙击·三连」，3 条 980 × 14 逐条锁定、每条间隔 0.6 秒，e.dmg × 1.2；
## delay：前面先放了清膛时整体往后挪
func _volley(e: Dictionary, dir: Vector2, delay: float) -> void:
	var nm: String = "手炮·三连" if e.type == "iberia" else "狙击·三连"
	e.wind = maxf(float(e.get("wind", 0.0)), 0.9 + 1.2 + delay + 0.6)   # 三连打完收势 0.6 秒再出下一组（输出窗口，docs/171 §6）
	for k in 3:
		var vw := _warn(e, "line", 0.9 + 0.6 * k + delay, {"ang": dir.angle(), "len": 980.0, "wid": 14.0, "track": 0.3 + 0.6 * k + delay, "act": "shot",
			"name": nm if k == 0 else "", "col": Color(1.0, 0.8, 0.4), "dmg": e.dmg * Bal.v("boss/saint_volley_mult", 1.2), "lock": k == 0, "saint_beam": true})
		_watch(e, vw, "fade")
		if e.type == "iberia":
			vw.kp = "iberia"   # 三连也画 Kanpelle 光束（1 倍粗）
			vw.kp_k = 2.0


## 卡门 A · 狙击（保留）：1100 × 10 条纹细线，追踪 0.6 秒后锁定，总 1.2 秒；e.dmg × 2.6；不耗弹（她的三发留给环射）
func _snipe(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 1.2, {"ang": dir.angle(), "len": 1100.0, "wid": 10.0, "track": 0.6, "act": "shot", "name": "狙击", "col": Color(1.0, 0.85, 0.4), "dmg": e.dmg * 2.6})


## 卡门 · 封锁线（docs/142b §3.4，本作拟；取材 PRTS 弹药 3）：k = 这一轮第几枪（0–2），耗 1 发。
## 第一枪瞄主控（追踪 0.6、总 1.2）；一幕后两枪出手即锁定主控当时的位置、从本体两侧斜穿过去（boss_base._aim_fan，不追踪，总 1.0；10-25 用户「都要瞄准人打」）；
## 二幕第三枪垂直于第一枪、穿过主控当前位置（追踪 0.3、总 1.0）。结算画 Kanpelle 象牙白光束，然后留一条火线（_fire_step）
func _lane_shot(e: Dictionary, dir: Vector2, k: int) -> Dictionary:
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
		# 10-25 用户「三条激光都要瞄准人打」：后两枪出手即锁定主控当时的位置，从本体两侧斜穿过去（原来与第一枪平行、左右偏 carmen_lane_off）
		var f: Dictionary = _aim_fan(e, 3, 1100.0)[0 if k == 1 else 2]
		pos = f.pos
		ang = f.ang
		track = 0.5
		dur = 1.0
	var q: Array = e.get("lane_gaps", [])
	q.append(g.rng_enemy.randf_range(0.3, 0.7))
	e.lane_gaps = q
	var w := _warn(e, "line", dur, {"pos": pos, "ang": ang, "len": 1100.0, "wid": 10.0, "track": track, "track_center": p2 and k == 2, "act": "shot", "name": "狙击",
		"col": Color(1.0, 0.94, 0.82), "dmg": e.dmg * Bal.v("boss/carmen_lane_mult", 1.56), "kp": "carmen", "kp_k": 2.0, "lock": k == 0, "saint_beam": true})   # 原 2.0（10-25 加密 ×0.78）
	_spend(e, 1)
	return w


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
		var fb: Vector2 = a + Vector2.from_angle(float(la.ang)) * float(la.len)
		var nn: Vector2 = (fb - a).normalized().orthogonal()
		lines.append({"a": a, "b": fb, "gap_t": gt, "gap_len": Bal.v("boss/carmen_fire_gap", 80.0),
			"until": g.t + Bal.v("boss/carmen_fire_life", 6.0), "born": g.t,
			"push": nn * (1.0 if (g.ppos - a).dot(nn) >= 0.0 else -1.0)})   # 收束方向：朝落枪时主控所在一侧平移（docs/171 §9）   # 6 秒（10-25 曾加到 7.5，10-26 用户嫌激光收得慢，退回）
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
		g.combat.enemy_hit(e.dmg * Bal.v("boss/carmen_fire_mult", 0.5), {"boss": true, "src_type": e.type}, false, true, ["远程", "物理"], "boss_" + e.type)
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
	e.cq = []
	e.sw = []
	_clear_screen(e)   # 打断 = 在飞的弹幕作废（主轴的奖励）
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4), "enemy": true})
	g.vfx.add_text(e.pos + Vector2(0, -60), "装填被打断！", Color(1.0, 0.85, 0.4), 20)
	Sfx.play("boom", -6.0, 1.2, 0.0)


## 伊比利亚装填读条中受伤 ×boss/iberia_reload_taken（协调人 10-27：破绽期输出目标 ≥25%；打断后的大破绽仍是 ×1.4 break_t）
func taken_mult(e: Dictionary) -> float:
	if float(e.get("channel", 0.0)) > 0.0:
		return Bal.v("boss/iberia_reload_taken", 1.8) if e.type == "iberia" else Bal.v("boss/carmen_reload_taken", 1.5)
	return 1.0


## ---- 受击钩子（docs/101 B1c，10-15 从 combat.gd 搬来）
## 装填读条中累计伤害达到 boss/saint_break_dmg（5%）最大生命才打断（原来挨一下就打断、僵直 6 秒；docs/38 §8.2）
func on_damaged(e: Dictionary, dmg: float, _eff: float) -> void:
	if e.type == "iberia" and int(e.get("gates_passed", 0)) >= 1:
		return   # 二幕「延生」：累计伤害不再打断，只认冲刺穿身（docs/142b §3.3）
	if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
		e.reload_dmg = e.get("reload_dmg", 0.0) + dmg
		if e.reload_dmg >= e.maxhp * Bal.v("boss/saint_break_dmg", 0.05):
			saint_interrupt(e)


## ---- 持续压力（docs/171 §9，用户 10-28「加不停顿的新招」）：出招之间也在压场，装填 / 破绽 / 起身前停下 = 输出窗口不受影响
## 卡门「收束」：火线落下后朝主控一侧平移（carmen_fire_drift 像素/秒），跑道越来越窄，要从缺口穿过去
## 伊比利亚「余烬」：每 iberia_ember_cd 秒往主控前进方向抛一团余烬，0.6 秒落地预警后烧 iberia_ember_life 秒，站在里面每 0.5 秒受伤 + 减速
func _calm(e: Dictionary) -> bool:
	return e.channel > 0.0 or float(e.get("break_t", 0.0)) > 0.0 or e.stun > 0.0 or float(e.get("gate_inv", 0.0)) > 0.0 or e.get("refill_on_rise", false)


func _pressure_step(e: Dictionary, dt: float, p2: bool) -> void:
	var calm: bool = _calm(e)
	if e.type == "carmen":
		if calm:
			return
		var v: float = Bal.v("boss/carmen_fire_drift_p2", 54.0) if p2 else Bal.v("boss/carmen_fire_drift", 44.0)
		for fl in e.get("fire_lines", []):
			if fl.has("push") and g.t - float(fl.born) > 0.6:
				fl.a += fl.push * v * dt
				fl.b += fl.push * v * dt
		return
	var em: Array = e.get("embers", [])
	if calm:
		for x in em:
			x.until = minf(float(x.until), g.t + 0.6)   # 窗口里余烬很快熄掉，近战压上去不踩火
	elif e.age > 3.0:
		e.ember_t = float(e.get("ember_t", 1.5)) - dt
		if e.ember_t <= 0.0 and em.size() < int(Bal.v("boss/iberia_ember_max", 6.0)):
			e.ember_t = Bal.v("boss/iberia_ember_cd_p2", 1.0) if p2 else Bal.v("boss/iberia_ember_cd", 1.4)
			var at: Vector2 = g.ppos + g.pvel * Bal.v("boss/iberia_ember_lead", 0.7) + Vector2.from_angle(g.rng_enemy.randf() * TAU) * g.rng_enemy.randf_range(0.0, 36.0)
			var arm: float = Bal.v("boss/iberia_ember_arm", 0.6)
			em.append({"pos": at, "from": e.pos + Vector2(0, -20), "r": Bal.v("boss/iberia_ember_r", 44.0), "born": g.t, "arm": g.t + arm,
				"until": g.t + arm + Bal.v("boss/iberia_ember_life", 2.6)})
	em = em.filter(func(x): return g.t < float(x.until))
	e.embers = em
	if g.invuln > 0.0 or g.t < float(e.get("ember_hit_at", 0.0)):
		return
	for x in em:
		if g.t >= float(x.arm) and g.ppos.distance_to(x.pos) < float(x.r):
			e.ember_hit_at = g.t + 0.5
			g.combat.enemy_hit(e.dmg * Bal.v("boss/iberia_ember_mult", 0.17), {"boss": true, "src_type": e.type}, false, true, ["远程", "法术"], "boss_" + e.type)
			g.combat.slow_leader("iberia_ember", 0.6, 0.8)
			break


## ---- 出招组（docs/171，10-27）：每幕 2 组、每组一串有限连携（≤4 段），打空弹药 → 装填 = 收招破绽，主轴（打断 / 封锁线）照旧
func _card(e: Dictionary) -> Dictionary:
	var ph: int = clampi(int(e.get("card_ph", 0)), 0, 1)
	var cards: Array = CARDS[e.type][ph]
	return cards[int(e.get("card_i", 0)) % cards.size()]


## 每帧：首组（登场 2 秒后）/ 转幕换组；停掉 patterns 的自动轮转（散射 / 环射只由出招组点名）；硬直、破绽、转幕无敌清队列
func _card_tick(e: Dictionary, p2: bool) -> void:
	e.pattern_next = g.t + 99.0
	var ph: int = 1 if p2 else 0
	if int(e.get("card_ph", -1)) != ph and float(e.get("age", 0.0)) >= 2.0:
		_card_set(e, ph, 0)
	if e.stun > 0.0 or float(e.get("break_t", 0.0)) > 0.0 or float(e.get("gate_inv", 0.0)) > 0.0:
		e.cq = []
	elif not e.get("cq", []).is_empty() and g.t - float(e.get("cq_t0", g.t)) > COMBO_CAP:
		e.cq = []


## 换组：只换下一串连携（不清弹、不加横幅；招式名照常进血条副标题）
func _card_set(e: Dictionary, ph: int, i: int) -> void:
	e.card_ph = ph
	e.card_i = i
	e.cq = []
	e.sw = []


## 补满弹药时（装填完毕 / 打断起身）换下一组：两组交替，玩家能学会「这一轮是哪一套」
func _card_cycle(e: Dictionary) -> void:
	if e.has("card_ph") and not e.get("card_hold", false):
		_card_set(e, int(e.card_ph), int(e.card_i) + 1)


## 队列空了就按当前卡装一组；段间至少 SEG_GAP 秒（各段自己的锁定 / 站定由 wind 管）
func _card_run(e: Dictionary, dir: Vector2, dist: float) -> void:
	if not e.has("card_ph"):
		return
	var q: Array = e.get("cq", [])
	if q.is_empty():
		q = (_card(e).seq as Array).duplicate()
		e.cq_t0 = g.t
	e.cq = q
	if g.t < float(e.get("cq_next", 0.0)):
		return
	var seg: String = str(q.pop_front())
	e.cq_next = g.t + _seg(e, seg, dir, dist)
	e.ranged_t = 0.0   # 连携在出招就不算「远程段拖着不打」


## 一段出招，返回到下一段的最小间隔
func _seg(e: Dictionary, seg: String, dir: Vector2, dist: float) -> float:
	match seg:
		"cannon":
			var cw := _cannon(e, dir)
			_watch(e, cw, "trail")
			_watch(e, cw, "fade")
		"lob":
			_watch(e, _lob(e), "crater")
		"lob_free":
			_lob(e, false)
		"shell":
			_shell(e, dir)
		"scatter":
			if dist > 320.0:
				return 0.0   # 散射是近身压制，远了跳过这段
			e.pattern_force = "散射"
			g.bai.patterns.try_attack(e, dir, dist)
		"ring":
			e.pattern_force = "环射"
			g.bai.patterns.try_attack(e, dir, dist)
		"stream":
			_stream(e, dir, false)
		"xstream":
			_stream(e, dir, true)
		"snipe":
			_watch(e, _lane_shot(e, dir, int(D.ENEMIES[e.type].get("ammo", 3)) - int(e.ammo)), "fade")
			return Bal.v("boss/carmen_lane_gap", 1.3)
	return SEG_GAP


## 伊比利亚二幕 · 重炮弹（本作改编）：0.6 秒枪口预警后打出 3 发大弹（扇形 ±0.34），减速滑行，1.15 秒后各炸成 6 片碎弹（寿命 1.4，相邻大弹错开）；耗 1 发。
## 大弹 e.dmg × 0.6、碎弹 × 0.3；大弹有发光核心（world.gd core_r），碎弹没有
func _shell(e: Dictionary, dir: Vector2) -> void:
	var muzzle: Vector2 = e.pos + dir * 28.0
	_muzzle_warn(e, dir, 0.6, "重炮弹")
	for k in 3:
		var a: float = dir.angle() + (k - 1) * 0.34
		_queue(e, muzzle, Vector2.from_angle(a) * 230.0, 0.6, 12.0, 0.6, {"life": 1.15, "core_r": 5.0, "core_col": Color(2.0, 1.55, 1.05),
			"acc": -170.0, "vmin": 45.0, "vmax": 230.0, "sp_t": 1.15, "sp_n": 6, "sp_spd": 120.0, "sp_life": 1.4, "sp_rot": a + PI / 6.0 * k}, false)
	e.wind = maxf(e.wind, 0.6 + Bal.v("boss/saint_stand", 1.5) * 0.7)
	Sfx.play("skill", -8.0, 0.7)
	_spend(e, 1)


## 卡门 · 曳光弹列（一幕，本作改编）/ 交叉弹列（二幕）：沿瞄准方向打出平行的直线弹列，空出一条跑道（随机偏左 / 右 1–2 列，不在你脚下）；耗 1 发。
## 一幕：7 列、间距 56，从本体身前出发；二幕：两组各 5 列、间距 64，分别沿瞄准方向 ±45° 从你身后 380 处交叉扫过你的位置，两组空道相交处 = 安全格。
## 每列 4 发（0.14 秒间隔）、速度 300 / 270，出弹前 0.7 / 0.6 秒在出弹点亮红闪；弹 r5 带小核心，e.dmg × 0.45
func _stream(e: Dictionary, dir: Vector2, cross: bool) -> void:
	e.lane_ang = dir.angle()
	e.lane_set_t = g.t
	var delay: float = 0.6 if cross else 0.7
	_muzzle_warn(e, dir, delay, "交叉弹列" if cross else "曳光弹列")
	var angs: Array = [dir.angle()] if not cross else [dir.angle() + PI * 0.25, dir.angle() - PI * 0.25]
	var n: int = 5 if cross else 7
	var spc: float = 64.0 if cross else 56.0
	var spd: float = 270.0 if cross else 300.0
	for a in angs:
		var fwd := Vector2.from_angle(float(a))
		var side: Vector2 = fwd.orthogonal()
		var off: int = [-2, -1, 1, 2][g.rng_enemy.randi() % 4]
		var gap_k: int = clampi((n - 1) / 2 + off, 0, n - 1)
		var center: Vector2 = (e.pos + fwd * 24.0) if not cross else (g.ppos - fwd * 380.0)
		for k in n:
			if k == gap_k:
				continue
			var o: Vector2 = center + side * (k - (n - 1) * 0.5) * spc
			for j in 4:
				_queue(e, o, fwd * spd, delay + j * 0.14, 5.0, 0.45, {"life": 2.8, "core_r": 2.0, "core_col": Color(2.0, 1.95, 1.8)}, j == 0)
	e.wind = maxf(e.wind, delay + 0.6)
	Sfx.play("skill", -8.0, 1.1)
	_spend(e, 1)


## 弹幕起手的正式预警：枪口小圈（不画矩形），dur 秒后结算 = 枪口火光（vfx.boss_signature），招式名进血条副标题；本身无伤害（弹体另算）
func _muzzle_warn(e: Dictionary, dir: Vector2, dur: float, nm: String) -> void:
	_warn(e, "circle", dur, {"pos": e.pos + dir * 28.0, "r": 18.0, "ang": dir.angle(), "act": "saint_volley", "name": nm, "col": GLINT, "dmg": 0.0, "lock": true})


## 延迟出弹：delay 秒后在 pos 生成；glint = 出弹点先亮红闪（预警），连发的后几发不再重复闪
func _queue(e: Dictionary, pos: Vector2, vel: Vector2, delay: float, r: float, mult: float, extra := {}, glint := true) -> void:
	var sp: Array = e.get("sp", [])
	sp.append({"t": g.t + delay, "pos": pos, "vel": vel, "r": r, "mult": mult, "x": extra})
	e.sp = sp
	if glint:
		g.fx.append({"kind": "ring", "pos": pos, "r": r + 6.0, "life": delay, "max": delay, "col": GLINT, "enemy": true})


## 生成一发圣徒弹（Boss 弹：专属色描边 + 同色系暗外描边由 world.gd 画；extra 可带 core_r / acc / sp_*）。同屏上限跟 boss_patterns 一样
func _bullet(e: Dictionary, pos: Vector2, vel: Vector2, r: float, mult: float, extra: Dictionary) -> void:
	var own := 0
	for b in g.ebullets:
		if b.life > 0.0 and b.get("source_id", -1) == e.id:
			own += 1
	if own >= g.bai.patterns.OWNER_CAP or g.ebullets.size() >= g.bai.patterns.TOTAL_CAP:
		return
	var b := {"pos": pos, "vel": vel, "dmg": e.dmg * mult, "r": r, "life": 2.6, "slow": false, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "true": false,
		"kind": "orb", "home": false, "boss": true, "atk": "物理", "hit_cap": e.get("hit_cap", 0.0), "source_id": e.id, "col": g.vfx.boss_color(e.type), "src_type": e.type}
	b.merge(extra, true)
	g.ebullets.append(b)


## 每帧：到点的延迟弹出膛；自己的弹体减速（acc / vmin / vmax）、到点炸成碎弹（sp_t / sp_n / sp_spd / sp_rot / sp_gap 缺口朝向 + sp_gh 半角）
func _bullets_step(e: Dictionary, dt: float) -> void:
	var sp: Array = e.get("sp", [])
	if not sp.is_empty():
		var keep := []
		for s in sp:
			if g.t >= float(s.t):
				_bullet(e, s.pos, s.vel, float(s.r), float(s.mult), s.x)
			else:
				keep.append(s)
		e.sp = keep
	var born := []
	for b in g.ebullets:
		if b.life <= 0.0 or b.get("source_id", -1) != e.id:
			continue
		if b.has("acc"):
			var v: float = b.vel.length()
			if v > 0.01:
				b.vel *= clampf(v + float(b.acc) * dt, float(b.vmin), float(b.vmax)) / v
		if b.has("sp_t"):
			b.sp_t = float(b.sp_t) - dt
			if b.sp_t <= 0.0:
				b.life = 0.0
				born.append(b)
	for b in born:
		_split(e, b.pos, int(b.sp_n), float(b.sp_spd), float(b.sp_rot), float(b.get("sp_gap", 0.0)), float(b.get("sp_gh", 0.0)), float(b.get("sp_life", 1.8)))


## 一处炸开：n 片碎弹（r5、无核心、寿命 2.3、e.dmg × 0.3），gh > 0 时朝 gap 方向留 ±gh 缺口；炸点放一圈颗粒迸散
func _split(e: Dictionary, at: Vector2, n: int, spd: float, rot: float, gap: float, gh: float, life := 2.3) -> void:
	for k in n:
		var a: float = rot + TAU * k / n
		if gh > 0.0 and absf(angle_difference(a, gap)) < gh:
			continue
		_bullet(e, at, Vector2.from_angle(a) * spd, 5.0, 0.3, {"life": life})
	var bc: Color = g.vfx.boss_color(e.type)
	g.fx.append({"kind": "ring", "pos": at, "r": 22.0, "life": 0.3, "max": 0.3, "col": bc, "enemy": true, "bfx": bc})
	Sfx.play("hit", -14.0, 1.3, 0.1)


## 盯一条预警：结算（w.done）后放追加的弹幕；被打断 / 换组时整表清掉
func _watch(e: Dictionary, w: Dictionary, kind: String) -> void:
	var sw: Array = e.get("sw", [])
	sw.append({"w": w, "k": kind, "until": g.t + float(w.dur) + 1.0})
	e.sw = sw


func _watch_step(e: Dictionary) -> void:
	var sw: Array = e.get("sw", [])
	if sw.is_empty():
		return
	var keep := []
	for s in sw:
		var w: Dictionary = s.w
		if w.get("done", false):
			_on_resolved(e, w, str(s.k))
		elif g.t < float(s.until):
			keep.append(s)
	e.sw = keep


## 连携追加：
##   trail（炮线）：手炮打完沿炮线留 5 发残弹（距本体 150–630，静止，e.dmg × 0.4），0.55 秒后各炸 6 片（相邻错开半格），往两侧慢慢扩散
##   crater（弹坑）：轰击落地炸 12 片，朝伊比利亚方向留 ±0.5 弧度缺口（缺口 = 冲向他的路）
##   crater_tri（三角弹坑）：三连曲射每个落点炸 8 片，朝伊比利亚方向留 ±0.7 缺口（三角里面不加弹）
func _on_resolved(e: Dictionary, w: Dictionary, kind: String) -> void:
	var to_boss: float = (e.pos - w.pos).angle()
	match kind:
		"fade":
			# 光束消散（render/saint_draw.fades）：Kanpelle 短闪之后接上，FADE 秒内变细断成碎段
			var fl: Array = e.get("beam_fades", []).filter(func(f): return g.t - float(f.born) < 0.5)
			fl.append({"a": w.pos + Vector2(0, -16), "b": w.pos + Vector2(0, -16) + Vector2.from_angle(float(w.ang)) * float(w.len), "wid": float(w.wid), "born": g.t + 0.12})
			e.beam_fades = fl
		"trail":
			var dv := Vector2.from_angle(float(w.ang))
			for k in 4:
				var p: Vector2 = w.pos + dv * (170.0 + 140.0 * k)
				if g.combat.arena_clamp(p, 30.0).distance_to(p) > 1.0:
					break
				_bullet(e, p, Vector2.ZERO, 11.0, 0.4, {"life": 0.6, "core_r": 4.0, "core_col": Color(2.0, 1.55, 1.05),
					"sp_t": 0.45, "sp_n": 5, "sp_spd": 120.0, "sp_life": 1.4, "sp_rot": float(w.ang) + (PI / 6.0 if k % 2 else 0.0)})
		"crater":
			_split(e, w.pos, 12, 120.0, to_boss + PI / 12.0, to_boss, 0.5, 1.8)
		"crater_tri":
			_split(e, w.pos, 6, 120.0, to_boss + PI / 6.0, to_boss, 0.7, 1.4)


## 打断时：自己的在飞弹体与未出膛的弹全部作废，化成淡金白颗粒（最多 48 个发射点，走颗粒预算；颗粒关着时直接消失）
func _clear_screen(e: Dictionary) -> void:
	e.sp = []
	e.embers = []
	var n := 0
	var gr = g.optical.grains if g.get("optical") != null else null
	var grains_on: bool = gr != null and gr.on() and not gr.off
	for b in g.ebullets:
		if b.life > 0.0 and b.get("source_id", -1) == e.id:
			b.life = 0.0
			if grains_on and n < 48:
				gr.push("mote_up", b.pos + Vector2(0, -16), Vector2.UP, CLEAR_COL)
				n += 1
