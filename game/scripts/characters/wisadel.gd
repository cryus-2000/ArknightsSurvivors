## 维什戴尔（狙击，契约 v2.1）：炮击 → 余震爆炸 → 残影殉爆。
## S1 灰烬弹幕：接下来 3 发炮击 ×1.5 且必余震；S2 凋零处刑：一发 ×3 重炮 + 眩晕；
## S3 饱和炮击（2026-09-25 改为次数型，用户要求）：装填 8 发巨型炮弹，之后的普攻换成巨炮（×1.6、爆炸范围 ×2、必余震、间隔 ×0.6），打完为止；所有炮弹都是高速平射。
## 炮弹是本干员自己的实体（高速平射 → 落点爆炸 → 0.45 秒后原地余震），不走 game.gd 的子弹表。
## 索敌：打离主控最近的敌人（主控是唯一会掉血的）；最近几个距离相仿时挑周围敌人最多的落点。凋零处刑精英 / Boss 优先。
## 特效（docs/25）：黑红。弹体是黑红彗星（一整条连续轮廓：圆头最宽，沿轨迹平滑收细到尾尖，尾上带黑色碎屑）；落点从出膛起画收缩的红色准星；
## 落地橙白闪 → 黑烟 → 红环 → 带火头碎片 → 地面焦痕；余震只有地面双环 + 裂纹 + 上飘余烬。全程不震镜头。
extends "res://scripts/characters/character.gd"

const RED := Color(0.95, 0.22, 0.2)
const BOLT := Color(0.9, 0.08, 0.1)      # 弹体：黑红色能量光
const EMBER := Color(1.0, 0.55, 0.3)
const DARK := Color(0.1, 0.06, 0.08)
const CLUSTER_SLACK := 40.0      # 离主控最近的几个敌人距离相差在此以内时，改挑周围敌人最多的

var cd := 0.6
var shells: Array = []       # {from, to, t, dur, dmg, r, src, trail, quake, stun, light}
var quakes: Array = []       # 余震：{pos, t, dmg, r}
var shades: Array = []       # 残影（殉爆前摇）：{pos, t, dmg, r, depth}
var ash := 0                 # S1：剩余强化炮击数
var ammo := 0                # S3：巨型炮弹剩余发数（次数型）
# ---- 可见成长（docs/25 §5：原作特性余震 / S1 额外余震 / S2 多目标 / 天赋与 S3 魂灵之影）
var echo_quake := false      # N1「余响」：每发余震再来一次（0.3 秒后，环更大）
var twin_shot := false       # N2「礼尚往来」：普攻同时打第二个目标（60%）
var ash_rings := false       # N4「余烬未冷」：灰烬弹幕的余震变成三圈并眩晕
var exec_mark := false       # N5「亡者回响」：凋零处刑炸到的敌人挂残影标记
var souls_on := false        # 精二「死魂灵的余息」：两个魂灵之影跟随、给敌人挂残影
var marks: Dictionary = {}   # 残影标记：e.id → {e, t}；被标记的敌人死亡必定殉爆
var souls: Array = []        # 魂灵之影：{p, st, tgt, cd}
const MARK_MAX := 12
const SHADE_MAX := 12


## 基础数值全部可由 data/characters/wisadel.json 的 base 段覆盖（docs/27 §3）
func _aoe() -> float:
	return base("aoe", 52.0) * stat(&"op_range") * (1.15 if elite >= 1 else 1.0)


## 索敌距离：代码里的 480 / 520 / 540 是原射程下的值，统一按 JSON range / 480 同比例缩放（2026-09-26 远程射程略缩）
func _reach(k: float = 480.0) -> float:
	return k * (base("range", 420.0) / 480.0) * stat(&"op_range")


# ---------------------------------------------------------------- 索敌

## 普攻 / S1 / S3 的目标：离主控最近；最近几个距离相仿（40px 内）时挑落点周围敌人最多的
func _target(reach: float) -> Dictionary:
	var cands: Array = []
	for e in nearest_enemies(6, reach, g.ppos):
		if e.pos.distance_to(pos) <= reach:
			cands.append(e)
	if cands.is_empty():
		return {}
	var d0: float = cands[0].pos.distance_to(g.ppos)
	var best: Dictionary = cands[0]
	var most := -1
	for e in cands:
		if e.pos.distance_to(g.ppos) - d0 > CLUSTER_SLACK:
			break
		var n := _count_around(e.pos, _aoe())
		if n > most:
			most = n
			best = e
	return best


## 凋零处刑：精英 / Boss 优先（血最多的），没有就打最近的
func _execute_target(reach: float) -> Dictionary:
	var best: Dictionary = {}
	var hp := -1.0
	for e in nearest_enemies(24, reach, pos):
		if (e.elite or e.boss) and e.hp > hp:
			hp = e.hp
			best = e
	return best if not best.is_empty() else _target(reach)


func _count_around(c: Vector2, r: float) -> int:
	var n := 0
	for j in query_ids(c, r):
		var q: Dictionary = g.enemies[j]
		if not q.dead and q.pos.distance_to(c) < r:
			n += 1
	return n


# ---------------------------------------------------------------- 更新

## 成长节点（data/characters/wisadel.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"echo_quake":
			echo_quake = true
		"twin_shot":
			twin_shot = true
		"ash_rings":
			ash_rings = true
		"exec_mark":
			exec_mark = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		souls_on = true


func update(dt: float) -> void:
	cd -= dt
	_update_shells(dt)
	_update_marks(dt)
	_update_souls(dt)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		ash = 3
		fx({"kind": "glow", "pos": _muzzle(), "r": 16.0, "life": 0.3, "col": RED, "alpha": 0.5})
		float_text(pos + Vector2(0, -80), "灰烬弹幕", RED, 14)
		return
	if ready > 0:
		var tg: Dictionary = _execute_target(_reach(540.0)) if ready == 1 else _target(_reach(520.0))
		start_skill(tg.pos if not tg.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var tgt: Dictionary = _target(_reach())
		if tgt.is_empty():
			cd = 0.2
		else:
			cd = base("cd", 1.4) / stat(&"op_aspd") * (base("s3_cd", 0.6) if ammo > 0 else 1.0)
			start_attack(tgt.pos)


func _release() -> void:
	var tgt: Dictionary = _target(_reach(520.0))
	if tgt.is_empty():
		return
	if ammo > 0:
		ammo -= 1
		_fire_giant(tgt.pos)
	elif ash > 0:
		ash -= 1
		var d1: float = base("atk", 30.0) * base("s1_mult", 1.5) * skill_power()
		_fire(tgt.pos, d1, "炮击", 1.1, true, 0.0, false, ash_rings)
		_twin(tgt, d1, ash_rings)
	else:
		_fire(tgt.pos, base("atk", 30.0), "炮击", 1.0, true, 0.0)
		_twin(tgt, base("atk", 30.0), false)


## N2「礼尚往来」：第二发炮弹打次优目标（候选里第一个离首发落点超过爆炸半径的；没有就取下一个候选），伤害 60%
func _twin(first: Dictionary, dmg: float, rings: bool) -> void:
	if not twin_shot:
		return
	var reach := _reach(520.0)
	var best: Dictionary = {}
	for e in nearest_enemies(8, reach, g.ppos):
		if e.id == first.id or e.pos.distance_to(pos) > reach:
			continue
		if best.is_empty():
			best = e
		if e.pos.distance_to(first.pos) > _aoe():
			best = e
			break
	if best.is_empty():
		return
	_fire(best.pos, dmg * base("twin_mult", 0.6), "炮击", 0.85, true, 0.0, false, rings)


func _release_skill() -> void:
	match cur_skill:
		1:
			# 凋零处刑：一发重炮，眩晕 + 余震
			var tgt: Dictionary = _execute_target(_reach(540.0))
			if tgt.is_empty():
				return
			_fire(tgt.pos, base("atk", 30.0) * base("s2_mult", 3.0) * skill_power(), "凋零处刑", base("s2_size", 1.6), true, 0.8)
			fx({"kind": "glow", "pos": _muzzle(), "r": 28.0, "life": 0.3, "col": RED, "alpha": 0.6})
			fx_sparks(_muzzle(), EMBER, 10, 200.0, 0.3)
			Sfx.op(id, "atk", 5.0, 0.75)
		2:
			# 饱和炮击：装填巨型炮弹，第一发立刻打出去，之后的普攻换成巨炮直到打完
			ammo = int(base("s3_ammo", 8.0))
			show_banner("饱和炮击：巨炮装填 ×%d" % ammo)
			fx({"kind": "glow", "pos": _muzzle(), "r": 30.0, "life": 0.4, "col": RED, "alpha": 0.6})
			fx_sparks(_muzzle(), EMBER, 10, 160.0, 0.3)
			var tg3: Dictionary = _target(_reach(540.0))
			if not tg3.is_empty():
				ammo -= 1
				_fire_giant(tg3.pos)
				cd = base("cd", 1.4) / stat(&"op_aspd") * base("s3_cd", 0.6)


## 次数型：S3 的「剩余时间」用剩余弹数表示（HUD 环 = 剩余 / 装填数，数字 = 剩几发；打完才重新充能）
func skill_active_left(i: int) -> float:
	return float(ammo) if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return base("s3_ammo", 8.0) if i == 2 else 1.0


## S1 灰烬弹幕的 3 发还没打完（图鉴演示等它打完再切段）
func skill_pending(i: int) -> bool:
	return i == 0 and ash > 0


## 巨型炮弹：伤害 ×1.6、爆炸范围 ×2、必余震；炮口焰加倍 + 后坐火星，落地顿帧
func _fire_giant(to: Vector2) -> void:
	_fire(to, base("atk", 30.0) * base("s3_mult", 1.6) * skill_power(), "饱和炮击", base("s3_size", 2.0), true, 0.0)
	var dir: Vector2 = (to - _muzzle()).normalized()
	fx({"kind": "glow", "pos": _muzzle(), "r": 26.0, "life": 0.16, "col": Color(1.8, 0.7, 0.5), "alpha": 0.8})
	for k in 8:
		fx({"kind": "spark", "pos": _muzzle(), "vel": (-dir).rotated(g.rng.randf_range(-0.9, 0.9)) * g.rng.randf_range(120, 260), "life": 0.3, "col": EMBER, "sz": 2.5, "drag": 3.0})


func _muzzle() -> Vector2:
	return pos + Vector2(14.0 * face, -34)


## rings：N4 灰烬弹幕的强化炮弹，余震变三圈并眩晕
func _fire(to: Vector2, base_dmg: float, src: String, size: float, quake: bool, stun: float, light := false, rings := false) -> void:
	face = signf(to.x - pos.x) if absf(to.x - pos.x) > 2.0 else face
	var from := _muzzle()
	# 高速炮弹（2026-09-25 还原原作，用户要求）：原来 900px/s、最高拱 120px 像迫击炮 → 2300px/s 又太快看不清炮弹
	# → 1500px/s、最高拱 18px：仍是平射，但炮弹本身看得见
	var dur: float = clampf(from.distance_to(to) / 1500.0, 0.08, 0.3)
	shells.append({"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": base_dmg * _dmg_bonus(), "r": _aoe() * size, "src": src,
		"trail": 0.0, "quake": quake, "stun": stun, "light": light, "hist": [], "size": size, "rings": rings})
	# 出膛：暗红锥形炮口焰 + 向后飞的橙色火星
	var dir := (to - from).normalized()
	fx({"kind": "muzzle", "pos": from, "dir": dir, "life": 0.07, "col": RED, "sz": 30.0 * size})
	fx({"kind": "glow", "pos": from, "r": 9.0 * size, "life": 0.06, "col": Color(2.0, 1.1, 0.8), "alpha": 0.8})
	for k in 3:
		fx({"kind": "spark", "pos": from, "vel": (-dir).rotated(g.rng.randf_range(-0.6, 0.6)) * g.rng.randf_range(60, 140), "life": 0.2, "col": EMBER, "sz": 2.0, "drag": 3.0})
	Sfx.op(id, "atk", 0.0 if size <= 1.2 else 3.0, 1.0 if size <= 1.2 else 0.85)


func _shell_pos(s: Dictionary) -> Vector2:
	return _shell_at(s, s.t / s.dur)


func _shell_at(s: Dictionary, k: float) -> Vector2:
	return s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(18.0, s.from.distance_to(s.to) * 0.05))


func _update_shells(dt: float) -> void:
	for s in shells:
		s.t += dt
		s.trail -= dt
		if s.trail <= 0.0 and s.t < s.dur:
			s.trail = 0.03
			# 彗尾上甩出的黑色碎屑（生成在彗头后方，不压在头上）
			var p: Vector2 = _shell_pos(s) if s.hist.size() < 3 else s.hist[s.hist.size() - 3]
			fx({"kind": "ember_shard", "pos": p, "vel": Vector2(g.rng.randf_range(-30, 30), g.rng.randf_range(-20, 30)), "life": 0.3, "col": DARK, "sz": 3.0, "ang": g.rng.randf() * TAU, "spin": 14.0, "grav": 200.0, "cold": true})
		if s.t < s.dur:
			s.hist.append(_shell_pos(s))
			if s.hist.size() > 9:
				s.hist.pop_front()
		if s.t >= s.dur:
			_explode(s.to, s.dmg, s.r, s.src, 0, s.stun, s.light)
			# 弹道余光：炮口到落点一道迅速消失的红线（高速炮弹的速度感）
			fx({"kind": "line", "pos": s.from, "to": s.to, "life": 0.09, "col": RED, "w": 2.0 * float(s.get("size", 1.0))})
			# 余震：E1 起伤害 40% → 60%
			if s.quake:
				var qd: float = s.dmg * (base("quake_e1", 0.6) if elite >= 1 else base("quake", 0.4))
				var qs: float = base("ash_stun", 0.8) if s.rings else 0.0
				quakes.append({"pos": s.to, "t": 0.45, "dmg": qd, "r": s.r * 1.2, "rings": s.rings, "stun": qs})
				# N1「余响」：0.3 秒后同一处再余震一次，范围 ×1.25
				if echo_quake:
					quakes.append({"pos": s.to, "t": 0.45 + base("quake2_delay", 0.3), "dmg": qd * base("quake2_mult", 1.0),
						"r": s.r * 1.2 * base("quake2_size", 1.25), "rings": s.rings, "stun": qs})
	shells = shells.filter(func(s): return s.t < s.dur)
	for q in quakes:
		q.t -= dt
		if q.t <= 0.0:
			_explode(q.pos, q.dmg, q.r, "余震", 0, q.stun, false, q.rings)
	quakes = quakes.filter(func(q): return q.t > 0.0)
	for sh in shades:
		sh.t -= dt
		if sh.t <= 0.0:
			_explode(sh.pos, sh.dmg, sh.r, "殉爆", sh.depth, 0.6)
	shades = shades.filter(func(sh): return sh.t > 0.0)


## 挂残影标记（N5 凋零处刑 / 精二魂灵之影）：mark_dur 秒内该敌人死亡（不论谁击杀）必定殉爆；同时最多 12 个
func _mark(e: Dictionary) -> void:
	if e.dead or e.get("chest", false):
		return
	if not marks.has(e.id) and marks.size() >= MARK_MAX:
		return
	marks[e.id] = {"e": e, "t": base("mark_dur", 4.0)}
	fx({"kind": "shade", "pos": e.pos + Vector2(0, -e.r * 0.5), "life": 0.3, "col": DARK})


func _update_marks(dt: float) -> void:
	if marks.is_empty():
		return
	for k in marks.keys():
		var mk: Dictionary = marks[k]
		mk.t -= dt
		if mk.t <= 0.0 or mk.e.dead:
			marks.erase(k)


## 击杀钩子：带残影标记的敌人殉爆（沿用天赋残影的 0.25 秒前摇 → 殉爆，伤害 = 攻击的 45%，mark_mult）
func on_kill(e: Dictionary) -> void:
	if not marks.has(e.id):
		return
	marks.erase(e.id)
	e["wis_det"] = true
	if shades.size() >= SHADE_MAX:
		return
	shades.append({"pos": e.pos, "t": 0.25, "dmg": base("atk", 30.0) * base("mark_mult", 0.45) * _dmg_bonus(), "r": _aoe() * 0.9, "depth": 1})
	fx({"kind": "shade", "pos": e.pos, "life": 0.3, "col": DARK})


## 精二「死魂灵的余息」：两个魂灵之影悬在维什戴尔肩后；每 2 秒各自飞向附近一名（优先未标记的）敌人挂上残影，再飞回来
func _update_souls(dt: float) -> void:
	if not souls_on or pos == Vector2.INF:
		return
	while souls.size() < 2:
		souls.append({"p": pos + Vector2(0, -50), "st": "idle", "tgt": null, "cd": 0.8 + 1.0 * souls.size()})
	var spd: float = base("soul_speed", 520.0)
	for k in souls.size():
		var s: Dictionary = souls[k]
		var home: Vector2 = _soul_home(k)
		match s.st:
			"idle":
				s.p = s.p.lerp(home, minf(1.0, dt * 6.0))
				s.cd -= dt
				if s.cd <= 0.0:
					var tg: Dictionary = _soul_target()
					if tg.is_empty():
						s.cd = 0.3
					else:
						s.tgt = tg
						s.st = "go"
						s.gt = g.t   # 俯冲帧从出发时刻开始播
						s.cd = base("soul_cd", 2.0)
			"go":
				var tg2 = s.tgt
				if tg2 == null or tg2.dead:
					s.st = "back"
				else:
					var to: Vector2 = tg2.pos + Vector2(0, -tg2.r - 10.0)
					s.p = s.p.move_toward(to, spd * dt)
					if g.rng.randf() < dt * 30.0:
						fx({"kind": "mote", "pos": s.p + Vector2(g.rng.randf_range(-4, 4), 6), "vel": Vector2(0, -20), "life": 0.35, "col": Color(0.3, 0.05, 0.08), "sz": 2.5})
					if s.p.distance_to(to) < 8.0:
						_mark(tg2)
						fx({"kind": "ring", "pos": tg2.pos, "r": tg2.r + 16.0, "r0": 4.0, "life": 0.3, "col": RED, "floor": true, "w": 2.0})
						s.st = "back"
			"back":
				s.p = s.p.move_toward(home, spd * dt)
				if s.p.distance_to(home) < 10.0:
					s.st = "idle"


func _soul_home(k: int) -> Vector2:
	var side: float = -1.0 if k == 0 else 1.0
	return pos + Vector2(side * 32.0 - face * 6.0, -78.0 + sin(g.t * 2.2 + k * 2.0) * 4.0)


## 魂灵之影的目标：离维什戴尔 soul_range 以内最近的未标记敌人；都标记过就取最近的
func _soul_target() -> Dictionary:
	var ts: Array = nearest_enemies(8, base("soul_range", 300.0), pos)
	for e in ts:
		if not marks.has(e.id) and not e.get("chest", false):
			return e
	return ts[0] if not ts.is_empty() else {}


## 爆炸：范围伤害；E1 起被炸死的敌人留下残影，0.25 秒后殉爆并眩晕。light：饱和炮击的减量特效；rings：N4 三圈余震
func _explode(c: Vector2, dmg: float, r: float, src: String, depth: int, stun: float, light := false, rings := false) -> void:
	var killed: Array = []
	for e in arc_targets(c, 0.0, PI, r):
		log_hit(src)
		deal_damage(e, dmg)
		if not e.dead and g.rfx.sniper_execute(e, g.hit):
			log_hit("真实")
			deal_damage(e, e.hp + 1.0)
		if e.dead:
			# 带残影标记的敌人已在 on_kill 里殉爆，这里不再重复留残影
			if not e.get("wis_det", false):
				killed.append(e.pos)
		else:
			if stun > 0.0 and not e.boss:
				e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
			# N5「亡者回响」：凋零处刑炸到的敌人全部挂上残影标记
			if src == "凋零处刑" and exec_mark:
				_mark(e)
	match src:
		"余震":
			# 只在地面：双红环 + 裂纹 + 一圈向上的余烬，不闪光不冒烟
			fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": RED, "floor": true, "w": 3.0})
			fx({"kind": "ring", "pos": c, "r": r * 0.65, "r0": r * 0.1, "life": 0.45, "col": Color(1.0, 0.45, 0.35), "floor": true, "w": 2.0})
			if rings:
				# 余烬未冷：外面再推出第三圈亮橙环（慢一拍、更粗），圈内被震到的敌人眩晕
				fx({"kind": "ring", "pos": c, "r": r * 1.3, "r0": r * 0.5, "life": 0.6, "col": Color(1.6, 0.6, 0.3), "floor": true, "w": 4.0})
				fx_sparks(c, EMBER, 6, 160.0, 0.35, 2.5, -80.0)
			fx({"kind": "crack", "pos": c, "r": r * 0.7, "life": 0.35, "col": RED, "floor": true, "n": 7, "ang": c.x * 0.01})
			for k in (4 if light else 8):
				var ox: float = g.rng.randf_range(-r * 0.6, r * 0.6)
				fx({"kind": "spark", "pos": c + Vector2(ox, 0), "vel": Vector2(ox * 0.4, g.rng.randf_range(-110, -60)), "life": 0.4, "col": RED, "sz": 2.0, "grav": 160.0})
		"殉爆":
			fx({"kind": "smoke", "pos": c, "r": r * 0.8, "life": 0.45, "col": DARK})
			_impact_fx(c, r, light)
		"饱和炮击":
			_burst_fx(c, r)
			g.hitstop = maxf(g.hitstop, 0.05)   # 巨炮落地：短顿帧
		"凋零处刑":
			_burst_fx(c, r, true)
		_:
			_impact_fx(c, r, light)
	if src == "余震":
		Sfx.op(id, "quake", 0.0, 1.0, 0.1)
	else:
		Sfx.op(id, "hit", -3.0 if light else 0.0, 1.0, 0.08)
	if elite >= 1 and depth < 1:
		for k in mini(killed.size(), 3):
			if shades.size() >= SHADE_MAX:
				break
			shades.append({"pos": killed[k], "t": 0.25, "dmg": dmg * base("shade", 0.4), "r": r * 0.8, "depth": depth + 1})
			fx({"kind": "shade", "pos": killed[k], "life": 0.3, "col": DARK})


## 落地：橙白闪 → 两团黑烟错开鼓起 → 红色冲击环 → 带火头的黑碎片 → 地面焦痕
func _impact_fx(c: Vector2, r: float, light: bool) -> void:
	fx({"kind": "flash", "pos": c, "r": r * 0.7, "life": 0.1})
	fx({"kind": "smoke", "pos": c, "r": r * (0.75 if light else 1.0), "life": 0.5, "col": DARK})
	if not light:
		fx({"kind": "smoke", "pos": c + Vector2(r * 0.25, -r * 0.2), "r": r * 0.7, "life": 0.6, "col": DARK, "delay": 0.06})
	fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.3, "life": 0.3, "col": RED, "w": 3.0})
	for k in (3 if light else 7):
		var v: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(90, 210) + Vector2(0, -90)
		fx({"kind": "ember_shard", "pos": c, "vel": v, "life": 0.5, "col": Color(0.25, 0.16, 0.18), "sz": 5.0, "ang": g.rng.randf() * TAU, "spin": 12.0, "grav": 420.0})
	fx_sparks(c, EMBER, 4 if light else 8, 200.0, 0.3)
	fx({"kind": "scorch", "pos": c, "r": r * 0.8, "life": 2.0, "floor": true})


## 饱和炮击 / 凋零处刑的爆炸：白粉核心星芒 → 放射状红色刀锋光条 → 贴地暗红冲击波 + 错落翻涌的黑烟 → 红色碎刃飞散
## （2026-09-25：原来的「紫灰烟环」是一圈等距的淡紫圆片，用户反馈太抽象，改为冲击波 + 黑烟）
func _burst_fx(c: Vector2, r: float, small := false) -> void:
	var sc: float = 0.7 if small else 1.0
	fx({"kind": "burst", "pos": c, "r": r * 1.6 * sc, "life": 0.5 if small else 0.55, "seed": g.rng.randf() * TAU, "n": 8 if small else 12})
	fx({"kind": "ring", "pos": c, "r": r * 1.45 * sc, "r0": r * 0.3, "life": 0.28, "col": RED, "floor": true, "w": 2.5, "alpha": 0.75})
	var n: int = 3 if small else 5
	var seed: float = g.rng.randf() * TAU
	for q in n:
		var ang: float = seed + q * TAU / n + g.rng.randf_range(-0.45, 0.45)
		var off: Vector2 = Vector2.from_angle(ang) * r * sc * g.rng.randf_range(0.3, 0.7)
		off.y *= 0.55
		fx({"kind": "smoke", "pos": c + off, "r": r * sc * g.rng.randf_range(0.32, 0.5), "life": g.rng.randf_range(0.5, 0.75), "col": DARK, "delay": q * 0.035})
	for k in (5 if small else 8):
		var v: Vector2 = Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(120, 260)
		fx({"kind": "sliver", "pos": c, "vel": v, "life": 0.45, "col": BOLT, "sz": g.rng.randf_range(6.0, 11.0), "ang": v.angle(), "drag": 2.5})
	fx({"kind": "scorch", "pos": c, "r": r * 0.9, "life": 2.0, "floor": true})


func _draw_pfx(f: Dictionary, a: float) -> bool:
	match f.kind:
		"muzzle":
			# 炮口焰：顺射向的扁锥，暗红外层 + 亮芯
			var d: Vector2 = f.dir
			var n: Vector2 = d.orthogonal()
			var L: float = f.sz * (0.6 + 0.4 * a)
			g.draw_colored_polygon(PackedVector2Array([f.pos + n * 3.0, f.pos + d * L, f.pos - n * 3.0, f.pos - d * 2.0]), Color(RED.r, RED.g, RED.b, 0.7 * a))
			g.draw_colored_polygon(PackedVector2Array([f.pos + n * 1.4, f.pos + d * L * 0.55, f.pos - n * 1.4]), Color(2.2, 1.2, 0.8, 0.9 * a))
			return true
		"burst":
			var k := 1.0 - a
			var r: float = f.r
			var sd: float = f.seed
			# 红色底光（先胀后消）
			g.draw_circle(f.pos, r * (0.3 + 0.5 * k), Color(1.3, 0.1, 0.22, 0.4 * a))
			# 放射状刀锋光条：12 根，长短错落，随时间向外抽出并变细
			var nq: int = f.get("n", 12)
			for q in nq:
				var h: float = fmod(sd * 7.3 + q * 2.399, 1.0)
				var ang: float = sd + q * TAU / nq + (h - 0.5) * 0.35
				var dv: Vector2 = Vector2.from_angle(ang)
				var nv: Vector2 = dv.orthogonal()
				var L: float = r * (0.55 + 0.7 * h) * minf(1.0, k * 2.2)
				var w: float = (2.5 + 3.5 * h) * (1.0 - k * 0.7)
				var s0: Vector2 = f.pos + dv * L * (0.1 + 0.35 * k)
				var s1: Vector2 = f.pos + dv * L
				var sm: Vector2 = f.pos + dv * L * 0.45
				g.draw_colored_polygon(PackedVector2Array([s0, sm + nv * w, s1, sm - nv * w]), Color(1.9, 0.1, 0.26, 0.9 * a))
				g.draw_colored_polygon(PackedVector2Array([s0, sm + nv * w * 0.3, s1, sm - nv * w * 0.3]), Color(2.4, 0.7, 0.8, 0.7 * a))
			# 核心：小而亮的白粉星芒，很快收掉
			var cr: float = r * 0.16 * (1.0 if k < 0.2 else maxf(0.0, 1.0 - (k - 0.2) / 0.45))
			g.draw_circle(f.pos, cr * 1.8, Color(1.6, 0.1, 0.12, 0.6 * a))
			g.draw_circle(f.pos, cr, Color(2.2, 0.5, 0.32, a))
			g.draw_circle(f.pos, cr * 0.45, Color(0.12, 0.02, 0.04, a))
			return true
		"sliver":
			# 红色碎刃：细长的双尖梭形，沿飞行方向
			var dv: Vector2 = Vector2.from_angle(f.ang) * f.sz
			var nv: Vector2 = dv.orthogonal().normalized() * 1.6
			g.draw_colored_polygon(PackedVector2Array([f.pos - dv, f.pos + nv, f.pos + dv, f.pos - nv]), Color(2.2, 0.3, 0.5, a))
			g.draw_line(f.pos - dv * 0.6, f.pos + dv * 0.6, Color(2.8, 1.4, 1.6, a), 1.0)
			return true
		"flash":
			# 落地一瞬的橙白闪光
			g.draw_circle(f.pos, f.r * (0.5 + 0.5 * a), Color(2.0, 0.4, 0.3, 0.75 * a))
			g.draw_circle(f.pos, f.r * 0.4 * a, Color(2.8, 1.6, 1.2, a))
			return true
		"smoke":
			# 黑烟团：膨胀、变淡、上鼓
			var age: float = f.max - f.life
			if age < f.get("delay", 0.0):
				return true
			var k := 1.0 - a
			var p: Vector2 = f.pos + Vector2(0, -22.0 * k)
			g.draw_circle(p, f.r * (0.4 + 0.8 * k), Color(0.14, 0.1, 0.12, 0.6 * a))
			g.draw_circle(p + Vector2(f.r * 0.25, -f.r * 0.2), f.r * (0.3 + 0.55 * k), Color(0.22, 0.15, 0.17, 0.45 * a))
			g.draw_circle(p + Vector2(-f.r * 0.2, -f.r * 0.1), f.r * (0.2 + 0.4 * k), Color(0.3, 0.2, 0.22, 0.3 * a))
			return true
		"ember_shard":
			# 黑色碎片，前端带一点火（cold：彗尾碎屑，不带火）
			var sv: Vector2 = Vector2.from_angle(f.ang) * f.sz
			g.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.45, f.pos + sv]), Color(0.16, 0.08, 0.12, a))
			if not f.get("cold", false):
				g.draw_circle(f.pos + sv, 1.6, Color(2.0, 0.9, 0.5, a))
			return true
		"scorch":
			# 地面焦痕：暗色椭圆，慢慢淡出
			g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
			g.draw_circle(Vector2.ZERO, f.r, Color(0.04, 0.02, 0.03, 0.45 * minf(1.0, a * 2.0)))
			g.draw_circle(Vector2(f.r * 0.15, 0), f.r * 0.55, Color(0.02, 0.01, 0.02, 0.35 * minf(1.0, a * 2.0)))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
		"shade":
			# 残影：黑色人形 + 一对红点，浮起
			var p: Vector2 = f.pos + Vector2(0, -6.0 - 10.0 * (1.0 - a))
			g.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
			g.draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.03, 0.05, 0.8 * a))
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			g.draw_circle(p + Vector2(-3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			g.draw_circle(p + Vector2(3, -7), 1.5, Color(2.0, 0.3, 0.3, a))
			return true
	return false


func draw_entities_floor() -> void:
	# 落点准星：出膛即出现，随炮弹接近收缩、变亮，落地时正好缩到爆炸半径
	for s in shells:
		var k: float = s.t / s.dur
		var rr: float = lerpf(s.r * 1.5, s.r, k)
		var al: float = 0.25 + 0.55 * k
		g.draw_set_transform(s.to, 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(RED.r, RED.g, RED.b, al), 1.5)
		for q in 4:
			var dv := Vector2.from_angle(q * PI / 2.0)
			g.draw_line(dv * rr * 0.55, dv * rr * 0.85, Color(RED.r, RED.g, RED.b, al), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in quakes:
		# 余响的第二次余震排在后面：进入最后 0.45 秒才画前兆环
		if q.t > 0.45:
			continue
		var a: float = 1.0 - q.t / 0.45
		g.draw_set_transform(q.pos, 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, q.r * (0.25 + 0.2 * a), 0.0, TAU, 20, Color(RED.r, RED.g, RED.b, 0.5 * a), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	# 彗星：一整条连续的轮廓，从彗头（圆头，最宽）沿飞行轨迹平滑收细到彗尾尖；
	# 三层同形叠画：外层暗红光 → 黑红体 → 黑芯，头尾之间没有接缝
	for s in shells:
		var p := _shell_at(s, s.t / s.dur)
		var pts: Array = []
		for q in s.hist:
			if pts.is_empty() or q.distance_to(pts[-1]) > 1.0:
				pts.append(q)
		if pts.is_empty() or p.distance_to(pts[-1]) > 1.0:
			pts.append(p)
		# 巨炮（size 2）粗 1.6 倍
		var wk: float = 1.0 + (float(s.get("size", 1.0)) - 1.0) * 0.6
		if pts.size() < 2:
			g.draw_circle(p, 5.5 * wk, Color(0.16, 0.02, 0.04))
			continue
		g.draw_colored_polygon(_comet_outline(pts, 11.0 * wk), Color(1.2, 0.08, 0.1, 0.3))
		g.draw_colored_polygon(_comet_outline(pts, 7.5 * wk), Color(0.34, 0.03, 0.06, 0.95))
		g.draw_colored_polygon(_comet_outline(pts, 4.0 * wk), Color(0.1, 0.01, 0.03, 1.0))
	_draw_marks()
	_draw_souls()


## 残影标记：敌人头顶一个小的黑色人形 + 一对红眼，上下浮动；最后 0.6 秒闪烁
func _draw_marks() -> void:
	for k in marks:
		var mk: Dictionary = marks[k]
		var e: Dictionary = mk.e
		if e.dead:
			continue
		if mk.t < 0.6 and fmod(mk.t * 8.0, 1.0) < 0.35:
			continue
		var p: Vector2 = e.pos + Vector2(0, -e.r - 18.0 + sin(g.t * 4.0 + e.id) * 2.0)
		g.draw_circle(p, 9.0, Color(0.9, 0.05, 0.1, 0.18))
		# Codex 帧条 fx_wisadel_mark（8×12 × 2 帧，4fps 循环）
		if _fx_strip("fx_wisadel_mark", 2, int(g.t * 4.0 + e.id * 0.5), p):
			continue
		_draw_shade_body(p, 5.5, 0.85)


## 魂灵之影：比标记大一号的黑色人形，身后拖一缕黑烟，红眼更亮
func _draw_souls() -> void:
	for s in souls:
		var p: Vector2 = s.p
		# Codex 帧条 fx_wisadel_soul（20×28 × 6 帧）：0–3 悬浮 8fps 循环；飞去挂标记时 4–5 俯冲 12fps 单次（停在第 5 帧），朝右、向左飞时镜像
		if _fx_tex("fx_wisadel_soul") != null:
			g.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.2 + 0.06 * sin(g.t * 6.0)))
			if s.st == "go":
				var tg = s.tgt
				var fl: bool = tg != null and not tg.dead and tg.pos.x < p.x
				_fx_strip("fx_wisadel_soul", 6, 4 + mini(1, int((g.t - float(s.get("gt", g.t))) * 12.0)), p, Vector2(0.5, 0.5), 0.0, Color.WHITE, fl)
			else:
				_fx_strip("fx_wisadel_soul", 6, (int(g.t * 8.0) + souls.find(s) * 2) % 4, p)
			continue
		var tail := PackedVector2Array()
		for q in 5:
			tail.append(p + Vector2(sin(g.t * 5.0 + q * 0.9) * (1.0 + q), 8.0 + q * 4.0))
		g.draw_polyline(tail, Color(0.08, 0.03, 0.05, 0.7), 5.0)
		g.draw_circle(p, 18.0, Color(1.0, 0.06, 0.12, 0.2 + 0.06 * sin(g.t * 6.0)))
		_draw_shade_body(p, 9.5, 0.95)


## 可选帧条：首次用到时 A.tex 懒加载并缓存进 g.tex（缺图缓存 null）
func _fx_tex(name: String) -> Texture2D:
	if not g.tex.has(name):
		g.tex[name] = A.tex(name)
	return g.tex[name]


## 帧条贴图（有图画图、缺图返回 false 走程序版）；1 美术像素 = PX 世界像素，@2x 高清帧条按 A.hires_of 半倍画；anchor 为帧内比例锚点
func _fx_strip(name: String, frames: int, frame: int, p: Vector2, anchor := Vector2(0.5, 0.5), ang := 0.0, col := Color.WHITE, flip := false) -> bool:
	var tx: Texture2D = _fx_tex(name)
	if tx == null:
		return false
	var fw: float = float(tx.get_width() / frames)
	var fh: float = float(tx.get_height())
	var k: float = g.PX / A.hires_of(tx)
	g.draw_set_transform(p.round(), ang, Vector2(-k if flip else k, k))
	g.draw_texture_rect_region(tx, Rect2(-Vector2(fw, fh) * anchor, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 残影人形：竖椭圆黑影 + 两点红眼（与天赋残影 fx 同形）
func _draw_shade_body(p: Vector2, r: float, al: float) -> void:
	g.draw_set_transform(p, 0.0, Vector2(1.0, 1.7))
	g.draw_circle(Vector2.ZERO, r, Color(0.05, 0.03, 0.05, al))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(1.2, 0.12, 0.16, 0.8 * al), 1.2)   # 暗红描边，在暗色地面上也分得清
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ey: float = -r * 0.75
	g.draw_circle(p + Vector2(-r * 0.35, ey), maxf(1.2, r * 0.18), Color(2.2, 0.3, 0.3, al))
	g.draw_circle(p + Vector2(r * 0.35, ey), maxf(1.2, r * 0.18), Color(2.2, 0.3, 0.3, al))


## 彗星轮廓：pts 从尾到头；半宽按 (u^1.6) 从 0 平滑增到 hw，头部接半圆帽
func _comet_outline(pts: Array, hw: float) -> PackedVector2Array:
	var n: int = pts.size()
	var L := PackedVector2Array()
	var R := PackedVector2Array()
	for i in n:
		var a0: Vector2 = pts[maxi(i - 1, 0)]
		var a1: Vector2 = pts[mini(i + 1, n - 1)]
		var nv: Vector2 = (a1 - a0).normalized().orthogonal()
		var u: float = float(i) / float(n - 1)
		var w: float = hw * pow(u, 1.3)
		L.append(pts[i] + nv * w)
		R.append(pts[i] - nv * w)
	var head: Vector2 = pts[n - 1]
	var dir: Vector2 = (pts[n - 1] - pts[n - 2]).normalized()
	var out := PackedVector2Array()
	out.append_array(L)
	# 半圆帽：从左侧绕过前方到右侧
	var a_start: float = dir.orthogonal().angle()
	for k in range(1, 8):
		out.append(head + Vector2.from_angle(a_start + PI * k / 8.0) * hw)
	R.reverse()
	out.append_array(R)
	return out


func status_items() -> Array:
	var out: Array = []
	if ash > 0:
		out.append(["灰烬弹幕 ×%d" % ash, RED])
	if ammo > 0:
		out.append(["巨炮 ×%d" % ammo, Color(1.0, 0.55, 0.45)])
	return out
