## 艾雅法拉（术师，契约 v2.1）：熔岩弹（范围法伤）。
## S1 炽热：接下来 3 发火山弹范围 ×1.4 并点燃；S2 点燃：一发 ×2.5 熔岩弹 + 易伤；S3 火山：敌群最密处连续喷发 10 次并留下熔岩。
## 熔岩弹复用 game.gd 的 fire 子弹做命中（带 src / fx_col / hidden），弹体、喷发、熔岩池由本干员绘制。
## 特效（docs/25）：橙红白。熔岩球橙核白心 + 火星尾；喷发 = 地面红裂纹 → 熔岩柱 → 熔岩池冒泡；点燃 = 敌人身上的火舌。
extends "res://scripts/characters/character.gd"

const ORANGE := Color(1.0, 0.5, 0.2)
const LAVA := Color(0.95, 0.3, 0.08)

var cd := 0.6
var heat := 0               # S1：剩余强化火山弹数
var erupt := 0              # S3：剩余喷发次数
var erupt_t := 0.0
var lava: Array = []        # {pos, r, t, tick, dmg, bub}
var burns: Array = []       # 点燃：{e, t, dps, ft}
var pending: Array = []     # 喷发前摇：{pos, t}
# ---- 可见成长（docs/25 §5：原作 S1 二重咏唱 / S2 点燃溅射 / S3 火山落下熔岩弹）
var twin_cast := false      # N1「复咏」：每次施法 2 发（第二发 60%）
var embers_on := false      # N2「火星迸溅」：熔岩弹爆炸迸出 2 颗火星弹跳向附近敌人
var ignite_blobs := false   # N4「星火燎原」：点燃的重弹炸开后向外溅出 4 团熔岩
var meteor_on := false      # N5「熔岩天降」：火山每次喷发向 2 名随机敌人抛出熔岩弹
var triple := false         # 精二「三重咏唱」：每次施法 3 发，后两发 1.5 倍大、1.5 倍伤害
var queued: Array = []      # 复咏 / 三重咏唱的后续熔岩弹：{t, to, dmg, aoe, sz, hot}
var lobs: Array = []        # 抛射小火团（火星 / 熔岩团 / 熔岩天降）：{from, to, t, dur, dmg, r, src, h, sz}
const LOB_MAX := 12


## 基础数值全部可由 data/characters/eyjafjalla.json 的 base 段覆盖（docs/27 §3）
func _aoe() -> float:
	return base("aoe", 58.0) * stat(&"op_range") * (1.25 if elite >= 1 else 1.0)


## 成长节点（data/characters/eyjafjalla.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"twin_cast":
			twin_cast = true
		"embers":
			embers_on = true
		"ignite_blobs":
			ignite_blobs = true
		"meteor":
			meteor_on = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		triple = true


func update(dt: float) -> void:
	cd -= dt
	_update_ground(dt)
	_update_orbs(dt)
	_update_lobs(dt)
	for q in queued:
		q.t -= dt
		if q.t <= 0.0 and pos != Vector2.INF:
			_cast(pos + Vector2(10.0 * face, -30), q.to, q.dmg, q.aoe, "火山弹", q.hot, 0.0, q.sz)
	queued = queued.filter(func(q): return q.t > 0.0)
	for p in pending:
		p.t -= dt
		if p.t <= 0.0:
			_erupt(p.pos)
	pending = pending.filter(func(p): return p.t > 0.0)
	if erupt > 0:
		erupt_t -= dt
		if erupt_t <= 0.0:
			erupt_t = 0.2
			erupt -= 1
			var c: Vector2 = g._densest_point(440.0 * stat(&"op_range"), pos)
			if c == Vector2.INF:
				var ts: Array = g._nearest(1, 440.0 * stat(&"op_range"), pos)
				if ts.is_empty():
					erupt = 0
					return
				c = ts[0].pos
			var at: Vector2 = c + Vector2(g.rng.randf_range(-50, 50), g.rng.randf_range(-40, 40))
			pending.append({"pos": at, "t": 0.12})
			fx({"kind": "crack", "pos": at, "r": 40.0, "life": 0.3, "col": LAVA, "floor": true, "n": 6, "ang": at.x * 0.02})
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		heat = 3
		fx({"kind": "glow", "pos": pos + Vector2(0, -30), "r": 22.0, "life": 0.3, "col": ORANGE, "alpha": 0.5})
		g._add_text(pos + Vector2(0, -80), "炽热", ORANGE, 14)
		return
	if ready > 0:
		var ts: Array = g._nearest(1, 440.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, base("range", 380.0) * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = base("cd", 1.2) / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var ts: Array = g._nearest(1, 420.0 * stat(&"op_range"), pos)
	if ts.is_empty():
		return
	var hot := heat > 0
	if hot:
		heat -= 1
	var dmg: float = base("atk", 22.0) * (1.0 if not hot else skill_power())
	var aoe: float = _aoe() * (base("s1_aoe", 1.4) if hot else 1.0)
	_cast(pos + Vector2(10.0 * face, -30), ts[0].pos, dmg, aoe, "火山弹", hot, 0.0)
	fx({"kind": "glow", "pos": pos + Vector2(10.0 * face, -30), "r": 10.0, "life": 0.12, "col": ORANGE, "alpha": 0.6})
	# 复咏 / 三重咏唱：后续熔岩弹隔 0.12 秒依次出手，打其他目标（没有就在首发目标两侧偏开）
	var n: int = 2 if triple else (1 if twin_cast else 0)
	if n <= 0:
		return
	var tos: Array = _extra_targets(ts[0], n)
	for k in n:
		if triple:
			queued.append({"t": 0.12 * (k + 1), "to": tos[k], "dmg": dmg * base("tri_mult", 1.5), "aoe": aoe * base("tri_aoe", 1.2), "sz": base("tri_size", 1.5), "hot": hot})
		else:
			queued.append({"t": 0.12, "to": tos[k], "dmg": dmg * base("twin_mult", 0.6), "aoe": aoe, "sz": 0.85, "hot": hot})


## 后续熔岩弹的落点：首发目标之外最近的敌人；不够就在首发目标两侧垂直偏开 40px
func _extra_targets(first: Dictionary, n: int) -> Array:
	var out: Array = []
	for e in g._nearest(n + 3, 420.0 * stat(&"op_range"), pos):
		if e.id != first.id and out.size() < n:
			out.append(e.pos)
	var side: Vector2 = (first.pos - pos).normalized().orthogonal() * 40.0
	var k := 0
	while out.size() < n:
		out.append(first.pos + side * (1.0 if k % 2 == 0 else -1.0))
		k += 1
	return out


func _release_skill() -> void:
	match cur_skill:
		1:
			# 点燃：一发重弹 + 易伤
			var ts: Array = g._nearest(1, 440.0 * stat(&"op_range"), pos)
			if ts.is_empty():
				return
			_cast(pos + Vector2(10.0 * face, -30), ts[0].pos, base("atk", 22.0) * base("s2_mult", 2.5) * skill_power(), _aoe() * 1.3, "点燃弹", true, 6.0)
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.4, "max": 0.4, "col": ORANGE})
		2:
			erupt = int(base("s3_count", 10.0))
			erupt_t = 0.0
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": ORANGE})
			fx({"kind": "ring", "pos": pos, "r": 70.0, "r0": 10.0, "life": 0.5, "col": ORANGE, "floor": true})


func skill_active_left(i: int) -> float:
	return float(erupt) * 0.2 if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return 2.0 if i == 2 else 1.0


## sz：弹体大小倍率（三重咏唱的后两发 1.5 倍，复咏的第二发 0.85 倍）
func _cast(from: Vector2, target: Vector2, base_dmg: float, aoe: float, src: String, burn: bool, weak: float, sz := 1.0) -> void:
	var d: Vector2 = (target - from).normalized()
	face = signf(d.x) if absf(d.x) > 0.01 else face
	g.bullets.append({"kind": "fire", "pos": from, "vel": d * 360.0, "dmg": base_dmg * _dmg_bonus(), "life": 1.3, "r": 8.0 * sz,
		"aoe": aoe, "src": src, "op": id, "on_hit": self, "burn": burn, "weak": weak, "fx_col": ORANGE, "hidden": true, "etrail": 0.0, "sz": sz})
	Sfx.op(id, "atk")


## 自己的熔岩球：火星尾
func _update_orbs(dt: float) -> void:
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "fire":
			continue
		b.etrail = b.get("etrail", 0.0) - dt
		if b.etrail <= 0.0:
			b.etrail = 0.04
			fx({"kind": "spark", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.12 + Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-30, 10)), "life": 0.3, "col": ORANGE, "sz": 3.0})


## fire 子弹爆炸后由 game.gd 回调：熔岩飞溅；点燃 / 易伤
func bullet_exploded(b: Dictionary) -> void:
	for k in 6:
		fx({"kind": "mote", "pos": b.pos, "vel": Vector2(g.rng.randf_range(-90, 90), g.rng.randf_range(-160, -60)), "life": 0.45, "col": LAVA, "sz": 2.5, "grav": 320.0})
	fx({"kind": "ring", "pos": b.pos, "r": b.aoe, "r0": b.aoe * 0.3, "life": 0.3, "col": Color(0.8, 0.2, 0.05), "floor": true, "w": 2.0})
	# 命中火焰（Ninja Adventure Flam 调橙红），按爆炸半径缩放；点燃弹换成大团熔岩爆炸（ansimuz Explosion A）
	if b.get("src", "") == "点燃弹" and g._fx_sprite("fx_eyja_ignite_boom", b.pos + Vector2(0, -10), b.aoe * 2.3 / 68.0):
		g.hitstop = maxf(g.hitstop, 0.05)
	else:
		g._fx_sprite("fx_flam_hit", b.pos + Vector2(0, -8), g.PX * clampf(b.aoe / 60.0, 0.8, 1.5))
	# N2「火星迸溅」：普攻熔岩弹炸开迸出 2 颗火星，弹跳向附近的敌人（优先爆炸圈外的）
	if embers_on and b.get("src", "") == "火山弹":
		var near: Array = []
		for e in g._nearest(6, base("ember_reach", 200.0), b.pos):
			if e.pos.distance_to(b.pos) > b.aoe * 0.6 and near.size() < 2:
				near.append(e.pos)
		while near.size() < 2:
			near.append(b.pos + Vector2.from_angle(g.rng.randf() * TAU) * b.aoe * 1.5)
		for p in near:
			_lob(b.pos, p, b.dmg * base("ember_mult", 0.3), base("ember_r", 30.0), "火星", 30.0, 0.7)
	# N4「星火燎原」：点燃的重弹炸开后向四周溅出 4 团熔岩，各自落地再炸
	if ignite_blobs and b.get("src", "") == "点燃弹":
		var a0: float = g.rng.randf() * TAU
		for k in 4:
			var to: Vector2 = b.pos + Vector2.from_angle(a0 + k * TAU / 4.0) * b.aoe * 1.4
			_lob(b.pos, to, base("atk", 22.0) * base("blob_mult", 0.5) * _dmg_bonus() * skill_power(), base("blob_r", 40.0), "熔岩团", 44.0, 1.0)
	if b.get("burn", false) or b.get("weak", 0.0) > 0.0:
		for e in g._arc_hit(b.pos, 0.0, PI, b.aoe):
			if e.dead:
				continue
			if b.get("burn", false):
				burns.append({"e": e, "t": 3.0 + (1.0 if elite >= 1 else 0.0), "dps": b.dmg * 0.1, "ft": 0.0})
			if b.get("weak", 0.0) > 0.0:
				e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), b.weak)


func _erupt(c: Vector2) -> void:
	var r: float = base("s3_r", 75.0) * stat(&"op_range")
	var edmg: float = base("atk", 22.0) * base("s3_mult", 1.64) * _dmg_bonus() * skill_power()
	area_hit("火山", c, r, edmg)
	# N5「熔岩天降」：每次喷发再向附近 2 名随机敌人高抛一颗熔岩弹（喷发伤害的 50%）
	if meteor_on:
		var cands: Array = g._nearest(10, base("meteor_reach", 320.0), c)
		g._shuffle(cands)   # 对局随机数（同 seed 可复现，docs/36）
		for k in mini(2, cands.size()):
			_lob(c + Vector2(0, -30), cands[k].pos, edmg * base("meteor_mult", 0.5), base("meteor_r", 45.0), "熔岩天降", 120.0, 1.2)
	fx({"kind": "lava_pillar", "pos": c, "r": r, "life": 0.5, "col": ORANGE})
	g._fx_sprite("fx_flam_hit", c + Vector2(0, -20), g.PX * 1.7)
	fx({"kind": "glow", "pos": c, "r": r * 0.5, "life": 0.18, "col": Color(1.6, 0.9, 0.4), "alpha": 0.7})
	fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": ORANGE, "floor": true, "w": 3.0})
	for k in 8:
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-8, 8), -30), "vel": Vector2(g.rng.randf_range(-120, 120), g.rng.randf_range(-260, -120)), "life": 0.6, "col": LAVA, "sz": 3.0, "grav": 420.0})
	lava.append({"pos": c, "r": r * 0.8, "t": 3.0, "tick": 0.0, "bub": 0.0, "dmg": base("atk", 22.0) * base("lava_mult", 0.23) * _dmg_bonus() * skill_power()})
	Sfx.op(id, "big", 0.0, 1.0, 0.1)


## 抛射小火团：从 from 沿抛物线（最高 h）飞到 to，落地后范围爆炸；同时最多 LOB_MAX 个
func _lob(from: Vector2, to: Vector2, dmg: float, r: float, src: String, h: float, sz: float) -> void:
	if lobs.size() >= LOB_MAX:
		return
	var dur: float = clampf(from.distance_to(to) / 420.0, 0.25, 0.6) + (0.2 if h > 80.0 else 0.0)
	lobs.append({"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": dmg, "r": r, "src": src, "h": h, "sz": sz, "trail": 0.0})


func _lob_pos(l: Dictionary) -> Vector2:
	var k: float = clampf(l.t / l.dur, 0.0, 1.0)
	return l.from.lerp(l.to, k) + Vector2(0, -sin(k * PI) * l.h)


func _update_lobs(dt: float) -> void:
	for l in lobs:
		l.t += dt
		l.trail -= dt
		if l.trail <= 0.0 and l.t < l.dur:
			l.trail = 0.05
			fx({"kind": "spark", "pos": _lob_pos(l), "vel": Vector2(g.rng.randf_range(-20, 20), g.rng.randf_range(-20, 10)), "life": 0.25, "col": ORANGE, "sz": 2.0 * l.sz})
		if l.t >= l.dur:
			area_hit(l.src, l.to, l.r, l.dmg)
			fx({"kind": "ring", "pos": l.to, "r": l.r, "r0": l.r * 0.3, "life": 0.28, "col": LAVA, "floor": true, "w": 2.0})
			fx({"kind": "glow", "pos": l.to, "r": l.r * 0.6, "life": 0.18, "col": Color(1.6, 0.8, 0.3), "alpha": 0.6})
			for k in (6 if l.sz >= 1.0 else 3):
				fx({"kind": "mote", "pos": l.to, "vel": Vector2(g.rng.randf_range(-80, 80), g.rng.randf_range(-140, -50)), "life": 0.4, "col": LAVA, "sz": 2.0, "grav": 320.0})
			if l.sz >= 1.0:
				g._fx_sprite("fx_flam_hit", l.to + Vector2(0, -6), g.PX * clampf(l.r / 60.0, 0.6, 1.1))
	lobs = lobs.filter(func(l): return l.t < l.dur)


func _update_ground(dt: float) -> void:
	for l in lava:
		l.t -= dt
		l.tick -= dt
		l.bub -= dt
		if l.tick <= 0.0:
			l.tick = 0.5
			area_hit("熔岩", l.pos, l.r, l.dmg)
		if l.bub <= 0.0 and l.t > 0.4:
			l.bub = 0.18
			var a: float = g.rng.randf() * TAU
			var rr: float = g.rng.randf() * l.r * 0.8
			fx({"kind": "mote", "pos": l.pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -28), "life": 0.55, "col": ORANGE, "sz": 2.0})
	lava = lava.filter(func(l): return l.t > 0.0)
	for b in burns:
		b.t -= dt
		b.ft -= dt
		if b.e.dead:
			b.t = 0.0
			continue
		if b.ft <= 0.0:
			b.ft = 0.14
			fx({"kind": "flame", "pos": b.e.pos + Vector2(g.rng.randf_range(-b.e.r * 0.5, b.e.r * 0.5), -b.e.r * 0.4), "vel": Vector2(0, -20), "life": 0.3, "col": ORANGE, "sz": 9.0})
		if int((b.t + dt) * 2.0) != int(b.t * 2.0):
			g._hit("点燃")
			g._damage(b.e, b.dps * 0.5)
	burns = burns.filter(func(b): return b.t > 0.0)


func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "lava_pillar":
		# 熔岩柱：底宽上窄，先冲高再落下，白芯
		var k: float = sin(a * PI)
		var h: float = (60.0 + f.r * 0.5) * k
		var w: float = f.r * 0.45
		var p: Vector2 = f.pos
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(-w * 0.35, -h), p + Vector2(w * 0.35, -h), p + Vector2(w, 0)]), Color(LAVA.r, LAVA.g, LAVA.b, 0.8 * a))
		g.draw_colored_polygon(PackedVector2Array([p + Vector2(-w * 0.45, 0), p + Vector2(-w * 0.12, -h * 0.9), p + Vector2(w * 0.12, -h * 0.9), p + Vector2(w * 0.45, 0)]), Color(2.2, 1.6, 0.8, 0.85 * a))
		g.draw_circle(p + Vector2(0, -h), w * 0.35, Color(2.4, 1.9, 1.2, 0.8 * a))
		return true
	return false


func draw_entities_floor() -> void:
	for l in lava:
		var a: float = clampf(l.t / 0.6, 0.0, 1.0)
		g.draw_set_transform(l.pos, 0.0, Vector2(1.0, 0.55))
		g.draw_circle(Vector2.ZERO, l.r, Color(0.7, 0.15, 0.03, 0.3 * a))
		g.draw_circle(Vector2.ZERO, l.r * 0.6, Color(1.5, 0.55, 0.1, 0.22 * a + 0.06 * sin(g.t * 9.0 + l.pos.x)))
		g.draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 24, Color(1.8, 0.7, 0.2, 0.5 * a), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 熔岩池中心的翻滚熔岩（CodeManu sunburn 调橙红，循环）
		if g.tex.get("fx_sunburst") != null:
			g._spr_rot("fx_sunburst", int(g.t * 16.0 + l.pos.x * 0.1) % 16, l.pos + Vector2(0, -4), 0.0, l.r * 1.3 / 62.0, Color(1.0, 1.0, 1.0, 0.75 * a))


func draw_auras() -> void:
	# 火山生效期间：脚下热浪环呼吸
	if erupt > 0 and pos != Vector2.INF:
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, 56.0 + 6.0 * sin(g.t * 6.0), 0.0, TAU, 32, Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.35), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	# 自绘熔岩球：橙核白心 + 外圈热光
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "fire":
			continue
		var big: bool = b.get("src", "") == "点燃弹"
		var sz: float = float(b.get("sz", 1.0))
		var fl := 1.0 + 0.15 * sin(g.t * 40.0 + b.pos.x)
		g.draw_circle(b.pos, (17.0 if big else 13.0) * fl * sz, Color(1.6, 0.6, 0.15, 0.22))
		if big and g.tex.get("proj_eyja_ignite") != null:
			# 点燃弹（2026-09-26 用户要求更大）：拖着火焰尾的大彗星火球，头朝飞行方向
			g.draw_circle(b.pos, 26.0 * fl, Color(1.6, 0.5, 0.1, 0.25))
			g._spr_rot("proj_eyja_ignite", int(g.t * 14.0) % 5, b.pos - b.vel.normalized() * 14.0, b.vel.angle(), g.PX * 1.5)
		elif g.tex.get("proj_lavaball") != null:
			# 熔岩球（OGA Fireball 调橙红），按速度方向旋转
			g._spr_rot("proj_lavaball", int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX * (1.5 if big else 1.1) * sz)
		else:
			g.draw_circle(b.pos, (10.0 if big else 7.5) * fl * sz, Color(2.2, 0.9, 0.25, 0.9))
			g.draw_circle(b.pos, (4.5 if big else 3.5) * sz, Color(2.8, 2.4, 1.6))
	# 抛射小火团：橙色光晕 + 白黄芯；熔岩天降带一圈暗红外壳；地面有落点影子
	for l in lobs:
		var p: Vector2 = _lob_pos(l)
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		g.draw_set_transform(l.to, 0.0, Vector2(1.0, 0.5))
		g.draw_circle(Vector2.ZERO, 5.0 * l.sz * (0.5 + 0.5 * k), Color(0.1, 0.03, 0.02, 0.35))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rr: float = 5.5 * l.sz
		g.draw_circle(p, rr * 1.9, Color(1.6, 0.55, 0.12, 0.25))
		if l.src == "熔岩天降":
			g.draw_circle(p, rr * 1.2, Color(0.45, 0.08, 0.03, 0.95))
		g.draw_circle(p, rr, Color(2.2, 0.8, 0.2, 0.95))
		g.draw_circle(p, rr * 0.45, Color(2.8, 2.3, 1.4))


func status_items() -> Array:
	var out: Array = []
	if heat > 0:
		out.append(["炽热 ×%d" % heat, ORANGE])
	if erupt > 0:
		out.append(["火山", ORANGE])
	return out
