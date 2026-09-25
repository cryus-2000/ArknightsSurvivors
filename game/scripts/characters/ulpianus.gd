## 乌尔比安（近卫·撼地者，契约 v2.1，docs/26 第二批）：精英猎手。锚击砸身前一片（全部命中）；掷出带锁链的锚，自己顺着锁链弹射过去砸下。
## S1 必须接触：向最近精英（无则敌群最密处）掷锚，锚咬住后顺锁链弹射到锚点，落地砸击半径 90 内 ×1.7 并眩晕；
## S2 必须坚守（永久）：攻击 +40%、锚击范围 +30%、天赋层数上限 10 → 15；
## S3 必须开辟：掷锚到敌群最密处，弹射过去落地 r140 ×3 并眩晕 3 秒（精英 1.5、Boss 0.8），之后 8 秒锚击间隔 -30%。
## 天赋 血脉滋养：击杀精英 +1 层、Boss +3 层，每层攻击 +4%；编队里其他深海猎人（斯卡蒂、幽灵鲨）获得一半。
## 全部走现成挂点，不改 game.gd：弹射 = 在 update 里覆盖自身 pos（follow 之后执行），眩晕 = e.stun，层数走 stats.add(op:<id>)。
## 表现（2026-09-25 重做）：锚画成他手里那把深色钩锚（黑蓝锚身 + 一只大弯钩 + 蓝色刃光），锁链绷直；
## 掷出 → 咬地（顿帧、蓝色水花）→ 人沿锁链弹射（残影 + 速度线）→ 落地砸击。
extends "res://scripts/characters/character.gd"

const STEEL := Color(0.55, 0.75, 0.95)
const CHAIN := Color(0.62, 0.68, 0.78)
const ABYSS := Color(0.1, 0.12, 0.2)        # 锚身：黑蓝
const EDGE := Color(0.4, 0.62, 1.1)         # 刃光：深海蓝
const WATER := Color(0.45, 0.78, 1.0)
const LEASH := 170.0
const HUNTERS := ["skadi", "specter_unchained"]

var cd := 0.5
var stacks := 0
var kept := false             # S2 必须坚守（永久）
var haste_t := 0.0            # S3 之后 8 秒锚击加速
## 锚：{kind, phase: "throw" / "zip", t, dur, from, to, start, trail}
## throw：锚从手里飞向 to；zip：锚咬在 to，人从 start 弹射到落点
var anchor: Dictionary = {}


func _reach() -> float:
	return base("reach", 70.0) * stat(&"op_range") * (1.3 if kept else 1.0)


func _stack_cap() -> int:
	return int(base("stack_cap", 10.0)) + (5 if kept else 0)


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 28.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	haste_t = maxf(0.0, haste_t - dt)
	_update_anchor(dt)
	if acting() or not anchor.is_empty():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		var aim := _skill_target(ready)
		start_skill(aim if aim != Vector2.INF else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 40.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 1.5) / stat(&"op_aspd") * (0.7 if haste_t > 0.0 else 1.0)
			start_attack(ts[0].pos)


## 锚击：身前半径内全部敌人
func _release() -> void:
	var ts: Array = g._nearest(1, _reach() + 60.0, pos)
	var ang: float = facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var c: Vector2 = pos + Vector2.from_angle(ang) * _reach() * 0.55
	melee_hit("锚击", c, 0.0, PI, _reach(), base("atk", 38.0) * _dmg_bonus(), 90.0)
	# 抡锚弧光（Ninja Slash01 钢蓝重调色）+ 落地
	g._fx_sprite("fx_slash_heavy_steel", pos + Vector2(0, -16) + Vector2.from_angle(ang) * _reach() * 0.45, _reach() * 1.3 / 28.0, ang)
	_slam_fx(c, _reach(), 1.0)
	Sfx.op(id, "atk", 0.0, 1.0, 0.06)


## 砸地：地裂 + 冲击环 + 深海蓝水珠（不用帧条水花：它前几帧是米黄色的尘团，和深海不搭）
func _slam_fx(c: Vector2, r: float, k: float) -> void:
	fx({"kind": "crack", "pos": c, "r": r * 0.9, "life": 0.4 * k, "col": STEEL, "floor": true, "n": 7})
	fx({"kind": "ring", "pos": c, "r": r, "r0": 10.0, "life": 0.3 * k, "col": STEEL, "floor": true, "w": 3.0})
	_splash(c, int(8 * k), 1.0 * k)
	fx_sparks(c + Vector2(0, -8), CHAIN, 6, 150.0, 0.35, 2.5, 220.0)


## 深海蓝水珠：向上迸开、带重力落回
func _splash(c: Vector2, n: int, k: float) -> void:
	for i in n:
		var a: float = -PI / 2.0 + g.rng.randf_range(-1.1, 1.1)
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-10, 10), -4), "vel": Vector2.from_angle(a) * g.rng.randf_range(90, 190) * k,
			"life": g.rng.randf_range(0.35, 0.5), "col": WATER, "sz": 2.0 if i % 2 == 0 else 1.5, "grav": 420.0})


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.15, "col": STEEL, "alpha": 0.5})


# ---------------------------------------------------------------- 技能

func _skill_target(i: int) -> Vector2:
	if i == 0:
		# 最近的精英；没有就敌群最密处
		var best: Dictionary = {}
		var bd := INF
		for j in g._query(pos, 420.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or not (e.elite or e.boss):
				continue
			var d: float = e.pos.distance_to(pos)
			if d < bd:
				bd = d
				best = e
		if not best.is_empty():
			return best.pos
	var c: Vector2 = g._densest_point(400.0, pos)
	if c == Vector2.INF:
		var ts: Array = g._nearest(1, 400.0, pos)
		return ts[0].pos if not ts.is_empty() else Vector2.INF
	return c


func _release_skill() -> void:
	match cur_skill:
		0, 2:
			var to := _skill_target(cur_skill)
			if to == Vector2.INF:
				sp[cur_skill] = sp_need(cur_skill) * 0.6   # 没目标：退回大半充能
				return
			anchor = {"kind": cur_skill, "phase": "throw", "t": 0.0, "dur": base("s1_throw" if cur_skill == 0 else "s3_throw", 0.16 if cur_skill == 0 else 0.22),
				"from": _hand(), "to": to, "trail": []}
		1:
			kept = true
			g.stats.add(&"op_atk", "add", 0.4, "ulpianus_kept", "op:" + id)
			g._sync_stats()
			_apply_stacks()
			g._show_banner("必须坚守：攻击与范围永久提升")
			fx({"kind": "ring", "pos": pos, "r": 90.0, "r0": 8.0, "life": 0.5, "col": STEEL, "floor": true})
			g._fx_sprite("fx_shield_amber", pos + Vector2(0, -20), g.PX * 1.4, 0.0, false, false, Color(0.7, 0.9, 1.2))


func skill_active_left(i: int) -> float:
	return haste_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return base("s3_haste", 8.0) if i == 2 else 1.0


func _hand() -> Vector2:
	return pos + Vector2(8.0 * face, -22)


func _update_anchor(dt: float) -> void:
	if anchor.is_empty():
		return
	anchor.t += dt
	var k: float = clampf(anchor.t / anchor.dur, 0.0, 1.0)
	if anchor.phase == "throw":
		anchor.trail.push_front(_anchor_pos(k))
		if anchor.trail.size() > 4:
			anchor.trail.pop_back()
		if k >= 1.0:
			_anchor_bite()
	else:
		# 弹射：先慢后快（k²），人沿锁链飞向锚点；途中留残影
		var kk: float = k * k
		pos = (anchor.start as Vector2).lerp(anchor.land, kk)
		face = signf(anchor.land.x - anchor.start.x) if absf(anchor.land.x - anchor.start.x) > 1.0 else face
		anchor.trail.push_front(pos)
		if anchor.trail.size() > 5:
			anchor.trail.pop_back()
		if k >= 1.0:
			_zip_land()
			anchor = {}


## 锚在飞行中的位置：近乎平直（10 像素弧度）
func _anchor_pos(k: float) -> Vector2:
	return (anchor.from as Vector2).lerp(anchor.to, k) + Vector2(0, -sin(k * PI) * 10.0)


## 锚咬地：顿帧 + 冲击环 + 水珠，转入弹射
func _anchor_bite() -> void:
	var to: Vector2 = anchor.to
	var dir: Vector2 = (to - pos).normalized() if to.distance_to(pos) > 1.0 else Vector2(face, 0)
	var big: bool = anchor.kind == 2
	g.hitstop = maxf(g.hitstop, 0.07 if big else 0.05)
	fx({"kind": "glow", "pos": to + Vector2(0, -6), "r": 18.0 if big else 14.0, "life": 0.12, "col": Color(1.4, 1.7, 2.3), "alpha": 0.8})
	fx({"kind": "ring", "pos": to, "r": 48.0 if big else 36.0, "r0": 6.0, "life": 0.22, "col": STEEL, "floor": true, "w": 3.0})
	_splash(to, 6, 0.8)
	for i in 6:
		var a: float = dir.angle() + g.rng.randf_range(-0.9, 0.9)
		fx({"kind": "spark", "pos": to + Vector2(0, -6), "vel": Vector2.from_angle(a) * g.rng.randf_range(160, 300), "life": 0.22, "col": CHAIN, "sz": 2.5})
	# 落点停在锚前一点（锚咬在敌人身上，人砸在它面前）
	var land: Vector2 = to - dir * 18.0
	anchor.phase = "zip"
	anchor.t = 0.0
	anchor.dur = clampf(pos.distance_to(land) / 1400.0, 0.08, 0.2)
	anchor.start = pos
	anchor.land = land
	anchor.trail = []
	melee_tgt = null


## 弹射落地：砸击
func _zip_land() -> void:
	var c: Vector2 = anchor.land
	if anchor.kind == 0:
		var r: float = base("s1_r", 90.0) * stat(&"op_range")
		var dmg: float = base("atk", 38.0) * base("s1_mult", 1.7) * _dmg_bonus() * skill_power()
		for j in g._query(c, r + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(c) > r + e.r:
				continue
			g._hit("掷锚")
			g._damage(e, dmg)
			if not e.dead:
				e.stun = maxf(e.stun, base("s1_stun", 0.6) * (0.5 if e.elite or e.boss else 1.0))
				if not e.boss:
					e.kb += (e.pos - c).normalized() * 50.0
		_slam_fx(c, r, 1.0)
		g.hitstop = maxf(g.hitstop, 0.06)
		Sfx.op(id, "atk", 2.0, 0.85)
	else:
		# 必须开辟：落点 r140 ×3 + 眩晕
		var r3: float = base("s3_r", 140.0) * stat(&"op_range")
		var dmg3: float = base("atk", 38.0) * base("s3_mult", 3.0) * _dmg_bonus() * skill_power()
		for j in g._query(c, r3 + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(c) > r3 + e.r:
				continue
			g._hit("必须开辟")
			g._damage(e, dmg3)
			if not e.dead:
				var st: float = base("s3_stun", 3.0) * (0.27 if e.boss else (0.5 if e.elite else 1.0))
				e.stun = maxf(e.stun, st)
				e.kb += (e.pos - c).normalized() * 60.0
		_slam_fx(c, r3, 1.6)
		_splash(c, 10, 1.3)
		haste_t = base("s3_haste", 8.0)
		g._fx_sprite("fx_circle_steel", c + Vector2(0, 4), g.PX * (r3 / 40.0))
		g._add_text(c + Vector2(0, -70), "必须开辟", STEEL, 18)
		g.hitstop = maxf(g.hitstop, 0.1)
		Sfx.op(id, "big")


# ---------------------------------------------------------------- 天赋：血脉滋养

func on_kill(e: Dictionary) -> void:
	if elite < 1:
		return
	var add := 0
	if e.boss:
		add = 3
	elif e.elite:
		add = 1
	if add <= 0 or stacks >= _stack_cap():
		return
	stacks = mini(_stack_cap(), stacks + add)
	_apply_stacks()
	g._add_text(pos + Vector2(0, -60), "血脉 ×%d" % stacks, STEEL, 13)
	fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 16.0, "life": 0.3, "col": Color(0.9, 0.3, 0.35), "alpha": 0.5})


func _apply_stacks() -> void:
	g.stats.remove_source("ulpianus_blood")
	var v: float = stacks * base("stack_atk", 0.04)
	if v > 0.0:
		g.stats.add(&"op_atk", "add", v, "ulpianus_blood", "op:" + id)
		for o in g.squad.ops:
			if o != self and o.id in HUNTERS:
				g.stats.add(&"op_atk", "add", v * 0.5, "ulpianus_blood", "op:" + o.id)
	g._sync_stats()


# ---------------------------------------------------------------- 绘制

func _draw_skill_over() -> void:
	if anchor.is_empty():
		return
	var k: float = clampf(anchor.t / anchor.dur, 0.0, 1.0)
	var hand: Vector2 = _hand()
	var throwing: bool = anchor.phase == "throw"
	var p: Vector2 = _anchor_pos(k) if throwing else (anchor.to as Vector2) + Vector2(0, -6)
	var d: Vector2 = ((anchor.to as Vector2) - (anchor.from as Vector2)).normalized()
	# 弹射中：人身后的残影与速度线
	if not throwing:
		var tr: Array = anchor.trail
		var mv_d: Vector2 = ((anchor.land as Vector2) - (anchor.start as Vector2)).normalized()
		for i in range(tr.size() - 1, 0, -1):
			draw_body_at(tr[i], face < 0.0, Color(EDGE.r, EDGE.g, EDGE.b, 0.35 * (1.0 - float(i) / tr.size())))
		for s in 3:
			var off: Vector2 = mv_d.orthogonal() * (s - 1) * 10.0 + Vector2(0, -20)
			g.draw_line(pos - mv_d * 16.0 + off, pos - mv_d * (56.0 + s * 14.0) + off, Color(1.3, 1.5, 1.8, 0.4), 1.5)
	# 锁链：绷直，暗描边 + 链节交替
	g.draw_line(hand, p, Color(0.04, 0.05, 0.08, 0.75), 5.0)
	g.draw_line(hand, p, Color(CHAIN.r, CHAIN.g, CHAIN.b, 0.95), 2.5)
	var links: int = clampi(int(hand.distance_to(p) / 10.0), 1, 50)
	for i in links:
		var q: Vector2 = hand.lerp(p, float(i) / links)
		if i % 2 == 0:
			g.draw_circle(q, 2.6, Color(CHAIN.r * 0.7, CHAIN.g * 0.7, CHAIN.b * 0.75))
		else:
			g.draw_circle(q, 1.3, Color(1.1, 1.2, 1.35))
	# 飞行中：锚的残影 + 速度线
	if throwing:
		var tr2: Array = anchor.trail
		for i in range(tr2.size() - 1, 0, -1):
			_draw_anchor(tr2[i], d, 0.3 * (1.0 - float(i) / tr2.size()))
		for s in 3:
			var off2: Vector2 = d.orthogonal() * (s - 1) * 9.0
			g.draw_line(p - d * 24.0 + off2, p - d * (58.0 + s * 12.0) + off2, Color(1.3, 1.5, 1.8, 0.35), 1.5)
	_draw_anchor(p, d, 1.0)


## 他手里那把钩锚：黑蓝锚身（长杆）+ 一只大弯钩向后弯 + 一根短倒刺；刃口一道深海蓝光
## （程序画的过渡版；Codex 出 proj_ulpianus_anchor 帧条后换成贴图，见 docs/30）
func _draw_anchor(p: Vector2, d: Vector2, a: float) -> void:
	var n: Vector2 = d.orthogonal()
	var outline := Color(0.02, 0.03, 0.06, 0.85 * a)
	var body := Color(ABYSS.r * 1.6, ABYSS.g * 1.6, ABYSS.b * 1.6, a)
	var edge := Color(EDGE.r * 1.3, EDGE.g * 1.3, EDGE.b * 1.3, a)
	var head: Vector2 = p + d * 12.0
	var tail: Vector2 = p - d * 18.0
	# 锚杆
	g.draw_line(tail, head, outline, 8.0)
	g.draw_line(tail, head, body, 5.0)
	# 大弯钩：从锚头朝一侧向后弯出
	var hook := PackedVector2Array()
	for i in 8:
		var u: float = float(i) / 7.0
		var ang: float = lerpf(0.0, 2.4, u)
		hook.append(head + n * sin(ang) * 15.0 - d * (1.0 - cos(ang)) * 11.0)
	g.draw_polyline(hook, outline, 9.0)
	g.draw_polyline(hook, body, 5.5)
	g.draw_polyline(hook.slice(0, 7), edge, 1.5)
	g.draw_circle(hook[hook.size() - 1], 2.5, edge)
	# 另一侧的短倒刺
	g.draw_line(head - d * 2.0, head - d * 9.0 - n * 7.0, outline, 6.0)
	g.draw_line(head - d * 2.0, head - d * 9.0 - n * 7.0, body, 3.0)
	# 锚头尖 + 尾环
	g.draw_colored_polygon(PackedVector2Array([head + d * 7.0, head + n * 3.0, head - n * 3.0]), body)
	g.draw_line(head, head + d * 6.0, edge, 1.5)
	g.draw_arc(tail - d * 3.0, 3.5, 0.0, TAU, 12, Color(CHAIN.r, CHAIN.g, CHAIN.b, a), 2.0)


func status_items() -> Array:
	var out: Array = []
	if stacks > 0:
		out.append(["血脉 ×%d" % stacks, Color(0.9, 0.4, 0.45)])
	if haste_t > 0.0:
		out.append(["开辟", STEEL])
	return out


func stats_rows() -> Array:
	return [["血脉层数", "%d / %d" % [stacks, _stack_cap()]]]
