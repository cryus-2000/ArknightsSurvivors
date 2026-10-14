## 圣徒伊比利亚 / 圣徒卡门（type iberia / carmen，docs/38 §2.2；招式改版 docs/95 §6 / §7，10-14 第 2 批）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 伊比利亚 4 招：A 手炮（② 直线，原作技能名；装填完毕改手炮·三连）/ B 散射（③，patterns，不耗弹）/ C 轰击（① 曲射落点圈，耗弹）/ D 清膛（④，50% 后装填完毕先放）
## 卡门 4 招：A 狙击（②；装填完毕改狙击·三连）/ B 炮身横扫（③，两幕都有）/ C 环射（④ 三缺口环，patterns，耗 3 发）/ D 炮身砸击（① 落点圈，第二幕炮身近战段）
## 机制不占名额：弹药、装填 / 打断 / 跪地破绽、站定窗口、远程段超时转近战、退避跳、炮身近战段
extends "res://scripts/enemies/bosses/boss_base.gd"

const MOVES_IBERIA := ["手炮", "散射", "轰击", "清膛"]
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
	if e.channel > 0.0 and g.dash_t > 0.0 and g.ppos.distance_to(e.pos) < e.r + 24.0:
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
			elif dist > 150.0 and _cd(e, "snipe", 6.0 if p2 else 8.0):
				_snipe(e, dir)
	if e.channel > 0.0:
		e.channel -= dt
		if e.channel <= 0.0:
			# 没被打断：装填完毕。伊比利亚第二幕先清膛再三连，其余直接三连（间隔 0.6 秒，都可以走开躲）
			e.ammo = int(D.ENEMIES[e.type].get("ammo", 3))   # 卡门 3 发、伊比利亚 1 发（数值 10-01）
			e.ai = "ranged"
			e.count_end = 0.0
			g.vfx.add_text(e.pos + Vector2(0, -44), "装填完毕", Color(1.0, 0.8, 0.5), 14)
			if e.type == "iberia" and p2:
				e.reload_follow = true
			else:
				_volley(e, dir, 0.0)
	else:
		e.reload_t -= dt
		# 弹药打空才装填（原来每 14 秒一次）；卡门第二幕先炮身近战
		if e.ammo <= 0 and e.reload_t <= 0.0 and e.get("sword_t", 0.0) <= 0.0 and e.stun <= 0.0 and e.wind <= 0.0 and e.get("break_t", 0.0) <= 0.0:
			if e.type == "carmen" and p2 and not e.get("sword_done", false):
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
		"清膛":
			if int(e.get("gates_passed", 0)) < 1:
				return false
			_clear(e, dir, dist)
			return true
		"狙击":
			_snipe(e, dir)
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
	_warn(e, "line", 1.1, {"ang": dir.angle(), "len": 980.0, "wid": 16.0, "track": 0.55, "act": "shot", "name": "手炮", "col": Color(1.0, 0.75, 0.3), "dmg": e.dmg * Bal.v("boss/iberia_judge_mult", 2.6)})
	e.wind = maxf(e.wind, 1.1 + Bal.v("boss/saint_stand", 1.5))
	_spend(e, 1)


## 伊比利亚 C · 轰击（本作原创，取材 PRTS「手炮」单发极重：这一发曲射落地）：主控位置 r80 固定落点，起手即锁定，1.1 秒；e.dmg × 2.2；
## 炮弹是纯画面（g.fx lob_shell 从本体沿抛物线飞到圈心、地面画阴影，world.gd），落点留 1.5 秒火光（boss_ai lob）；耗 1 发
func _lob(e: Dictionary) -> void:
	var w := _warn(e, "circle", 1.1, {"pos": g.ppos, "r": 80.0, "act": "lob", "name": "轰击", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 2.2})
	g.fx.append({"kind": "lob_shell", "a": e.pos + Vector2(0, -30), "b": w.pos, "life": w.dur, "max": w.dur, "enemy": true})
	_spend(e, 1)


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
		_warn(e, "line", 0.9 + 0.6 * k + delay, {"ang": dir.angle(), "len": 980.0, "wid": 14.0, "track": 0.3 + 0.6 * k + delay, "act": "shot",
			"name": nm if k == 0 else "", "col": Color(1.0, 0.8, 0.4), "dmg": e.dmg * Bal.v("boss/saint_volley_mult", 1.2), "lock": k == 0})


## 卡门 A · 狙击（保留）：1100 × 10 条纹细线，追踪 0.6 秒后锁定，总 1.2 秒；e.dmg × 2.6；不耗弹（她的三发留给环射）
func _snipe(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 1.2, {"ang": dir.angle(), "len": 1100.0, "wid": 10.0, "track": 0.6, "act": "shot", "name": "狙击", "col": Color(1.0, 0.85, 0.4), "dmg": e.dmg * 2.6})


## 卡门 B · 炮身横扫（保留，两幕都有）：扇形 r110 半角 0.9，追踪 0.2 秒，总 0.8 秒（锁定 ≥ 0.51）；e.dmg × 1.4
func _sweep(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "cone", 0.8, {"ang": dir.angle(), "half": 0.9, "r": 110.0, "track": 0.2, "act": "bite", "name": "炮身横扫", "col": g.vfx.boss_color(e.type), "dmg": e.dmg * 1.4})


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
	g.combat.start_break(e, Bal.v("boss/saint_break", 5.0))
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4), "enemy": true})
	g.vfx.add_text(e.pos + Vector2(0, -60), "装填被打断！", Color(1.0, 0.85, 0.4), 20)
	Sfx.play("boom", -6.0, 1.2, 0.0)


## ---- 受击钩子（docs/101 B1c，10-15 从 combat.gd 搬来）
## 装填读条中累计伤害达到 boss/saint_break_dmg（5%）最大生命才打断（原来挨一下就打断、僵直 6 秒；docs/38 §8.2）
func on_damaged(e: Dictionary, dmg: float, _eff: float) -> void:
	if e.get("channel", 0.0) > 0.0 and e.has("ammo"):
		e.reload_dmg = e.get("reload_dmg", 0.0) + dmg
		if e.reload_dmg >= e.maxhp * Bal.v("boss/saint_break_dmg", 0.05):
			saint_interrupt(e)
