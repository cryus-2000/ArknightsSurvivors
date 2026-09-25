## 乌尔比安（近卫·撼地者，契约 v2.1，docs/26 第二批）：精英猎手 + 聚怪。锚击砸身前一片（全部命中），掷锚把敌人拖到脚下。
## S1 必须接触：向最近精英（无则敌群最密处）掷锚，锚链沿途最多 6 名敌人被拖到身前并受 ×1.7 伤害；
## S2 必须坚守（永久）：攻击 +40%、锚击范围 +30%、天赋层数上限 10 → 15；
## S3 必须开辟：掷锚到敌群最密处，落点 r140 ×3 并眩晕 3 秒（精英 1.5、Boss 0.8），自己瞬移到锚点，之后 8 秒锚击间隔 -30%。
## 天赋 血脉滋养：击杀精英 +1 层、Boss +3 层，每层攻击 +4%；编队里其他深海猎人（斯卡蒂、幽灵鲨）获得一半。
## 全部走现成挂点，不改 game.gd：拖拽 = 写敌人 pos / kb，眩晕 = e.stun，瞬移 = 改自身 pos，层数走 stats.add(op:<id>)。
extends "res://scripts/characters/character.gd"

const STEEL := Color(0.55, 0.75, 0.95)
const CHAIN := Color(0.75, 0.8, 0.85)
const LEASH := 170.0
const HUNTERS := ["skadi", "specter_unchained"]

var cd := 0.5
var stacks := 0
var kept := false             # S2 必须坚守（永久）
var haste_t := 0.0            # S3 之后 8 秒锚击加速
var anchor: Dictionary = {}   # 飞行中的锚：{from, to, t, dur, kind, dragged:[]}


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
	# 抡锚弧光（Ninja Slash01 钢蓝重调色）+ 落地碎石
	g._fx_sprite("fx_slash_heavy_steel", pos + Vector2(0, -16) + Vector2.from_angle(ang) * _reach() * 0.45, _reach() * 1.3 / 28.0, ang)
	_slam_fx(c, _reach(), 1.0)
	Sfx.op(id, "atk", 0.0, 1.0, 0.06)


func _slam_fx(c: Vector2, r: float, k: float) -> void:
	fx({"kind": "crack", "pos": c, "r": r * 0.9, "life": 0.4 * k, "col": STEEL, "floor": true, "n": 7})
	fx({"kind": "ring", "pos": c, "r": r, "r0": 10.0, "life": 0.3 * k, "col": STEEL, "floor": true, "w": 3.0})
	# 深海猎人：只用水花（橙色碎石是推进之王的狮王金，和钢蓝不搭）
	g._fx_sprite("fx_water_splash", c + Vector2(0, 6), g.PX * clampf(r / 70.0, 1.0, 1.4), 0.0, false, true)
	fx_sparks(c + Vector2(0, -8), CHAIN, 6, 150.0, 0.35, 2.5, 220.0)
	g.shake = maxf(g.shake, 2.5 * k)


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
		0:
			var to := _skill_target(0)
			if to == Vector2.INF:
				sp[0] = sp_need(0) * 0.6   # 没目标：退回大半充能
				return
			anchor = {"from": pos + Vector2(8.0 * face, -22), "to": to, "t": 0.0, "dur": base("s1_throw", 0.16), "kind": 0, "back": false, "trail": []}
		1:
			kept = true
			g.stats.add(&"op_atk", "add", 0.4, "ulpianus_kept", "op:" + id)
			g._sync_stats()
			_apply_stacks()
			g._show_banner("必须坚守：攻击与范围永久提升")
			fx({"kind": "ring", "pos": pos, "r": 90.0, "r0": 8.0, "life": 0.5, "col": STEEL, "floor": true})
			g._fx_sprite("fx_shield_amber", pos + Vector2(0, -20), g.PX * 1.4, 0.0, false, false, Color(0.7, 0.9, 1.2))
		2:
			var to2 := _skill_target(2)
			if to2 == Vector2.INF:
				sp[2] = sp_need(2) * 0.6
				return
			anchor = {"from": pos + Vector2(8.0 * face, -22), "to": to2, "t": 0.0, "dur": base("s3_throw", 0.24), "kind": 2, "back": false, "trail": []}


func skill_active_left(i: int) -> float:
	return haste_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return base("s3_haste", 8.0) if i == 2 else 1.0


func _update_anchor(dt: float) -> void:
	if anchor.is_empty():
		return
	anchor.t += dt
	var k: float = clampf(anchor.t / anchor.dur, 0.0, 1.0)
	# 残影：最近 4 个锚位
	anchor.trail.push_front(_anchor_pos(k))
	if anchor.trail.size() > 4:
		anchor.trail.pop_back()
	if not anchor.back:
		if k >= 1.0:
			_anchor_land()
	else:
		# 回收：被锚链串住的敌人一路被拽回脚边（先慢后快）
		var kk: float = k * k
		for dg in anchor.get("drag", []):
			var e: Dictionary = dg[0]
			if not e.dead:
				e.pos = dg[1].lerp(dg[2], kk)
		if k >= 1.0:
			_drag_arrive()
			anchor = {}


## 锚当前的位置：几乎平直地飞出（只留 10 像素弧度），回收时同样
func _anchor_pos(k: float) -> Vector2:
	return (anchor.from as Vector2).lerp(anchor.to, k) + Vector2(0, -sin(k * PI) * 10.0)


## 拖拽到位：结算伤害 + 脚下砸地
func _drag_arrive() -> void:
	var drag: Array = anchor.get("drag", [])
	if drag.is_empty():
		return
	var dmg: float = base("atk", 38.0) * base("s1_mult", 1.7) * _dmg_bonus() * skill_power()
	for dg in drag:
		var e: Dictionary = dg[0]
		if e.dead:
			continue
		e.kb = (e.pos - pos).normalized() * 40.0
		g._hit("掷锚")
		g._damage(e, dmg)
	var c: Vector2 = anchor.get("feet", pos)
	_slam_fx(c, _reach() * 0.8, 0.8)
	g.hitstop = maxf(g.hitstop, 0.06)
	g._add_text(c + Vector2(0, -50), "拖拽 ×%d" % drag.size(), STEEL, 14)


## 锚落地
func _anchor_land() -> void:
	var to: Vector2 = anchor.to
	if anchor.kind == 0:
		# 必须接触：沿链拖拽最多 6 名敌人到身前，×1.7
		var from: Vector2 = pos
		var dir: Vector2 = (to - from).normalized()
		var cands: Array = []
		for j in g._query((from + to) * 0.5, from.distance_to(to) * 0.6 + 60.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.boss:
				continue
			var rel: Vector2 = e.pos - from
			var along: float = rel.dot(dir)
			var side: float = absf(rel.cross(dir))
			if along > 20.0 and along < from.distance_to(to) + 30.0 and side < 34.0 + e.r:
				cands.append([along, e])
		cands.sort_custom(func(a, b): return a[0] > b[0])
		var n: int = mini(int(base("s1_drag", 6.0)), cands.size())
		# 不再瞬移：记下起点 / 落点，回收阶段一路拽回来，到位时才结算伤害（_drag_arrive）
		var drag: Array = []
		for i in n:
			var e: Dictionary = cands[i][1]
			var land: Vector2 = from + dir * (28.0 + e.r + i * 8.0) + dir.orthogonal() * g.rng.randf_range(-12, 12)
			e.stun = maxf(e.stun, 0.5 * (0.5 if e.elite else 1.0) + 0.2)
			e.kb = Vector2.ZERO
			drag.append([e, e.pos, land])
		anchor["drag"] = drag
		anchor["feet"] = from + dir * 30.0
		_bite_fx(to, dir, 1.0)
		if n == 0:
			g._add_text(to + Vector2(0, -40), "落空", STEEL, 14)
	else:
		# 必须开辟：落点 r140 ×3 + 眩晕，自己瞬移到锚点
		var r: float = base("s3_r", 140.0) * stat(&"op_range")
		var dmg3: float = base("atk", 38.0) * base("s3_mult", 3.0) * _dmg_bonus() * skill_power()
		for j in g._query(to, r + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(to) > r + e.r:
				continue
			g._hit("必须开辟")
			g._damage(e, dmg3)
			if not e.dead:
				var st: float = base("s3_stun", 3.0) * (0.27 if e.boss else (0.5 if e.elite else 1.0))
				e.stun = maxf(e.stun, st)
				e.kb += (e.pos - to).normalized() * 60.0
		fx({"kind": "ring", "pos": pos, "r": 30.0, "r0": 4.0, "life": 0.25, "col": STEEL, "floor": true})
		_bite_fx(to, (to - pos).normalized(), 1.6)
		g.hitstop = maxf(g.hitstop, 0.1)
		pos = to + Vector2(-16.0 * face, 6)
		melee_tgt = null
		_slam_fx(to, r, 1.6)
		g._fx_sprite("fx_rock_spike", to + Vector2(0, 6), g.PX * 2.0, 0.0, false, true)
		haste_t = base("s3_haste", 8.0)
		g._fx_sprite("fx_circle_steel", to + Vector2(0, 4), g.PX * (r / 40.0))
		g._add_text(to + Vector2(0, -70), "必须开辟", STEEL, 18)
		Sfx.op(id, "big")
	anchor.back = true
	anchor.trail = []
	anchor.t = 0.0
	anchor.dur = base("s1_pull", 0.2) if anchor.kind == 0 else 0.16
	anchor.from = to
	anchor.to = pos + Vector2(8.0 * face, -22)


## 锚咬地：短顿帧 + 钢蓝火花沿飞行方向迸开 + 冲击环 + 碎石
func _bite_fx(at: Vector2, dir: Vector2, k: float) -> void:
	g.hitstop = maxf(g.hitstop, 0.05 * k)
	fx({"kind": "glow", "pos": at + Vector2(0, -6), "r": 16.0 * k, "life": 0.12, "col": Color(1.6, 1.8, 2.2), "alpha": 0.8})
	fx({"kind": "ring", "pos": at, "r": 42.0 * k, "r0": 6.0, "life": 0.22, "col": STEEL, "floor": true, "w": 3.0})
	for i in int(8 * k):
		var a: float = dir.angle() + g.rng.randf_range(-0.9, 0.9)
		fx({"kind": "spark", "pos": at + Vector2(0, -6), "vel": Vector2.from_angle(a) * g.rng.randf_range(160, 320), "life": 0.25, "col": CHAIN, "sz": 2.5})
	g._fx_sprite("fx_water_splash", at + Vector2(0, 6), g.PX * 0.9 * k, 0.0, false, true)


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
	var p: Vector2 = _anchor_pos(k)
	var hand: Vector2 = pos + Vector2(8.0 * face, -22)
	# 锚头始终朝外（回收时也是锚冠朝外、被拖回来）
	var d: Vector2 = ((anchor.to - anchor.from) if not anchor.back else (anchor.from - anchor.to)).normalized()
	# 锁链：飞出时绷直，回收时略下垂；链节交替横竖，读得出是铁链
	var sag: float = 8.0 * sin(k * PI) if anchor.back else 0.0
	var mid: Vector2 = (hand + p) * 0.5 + Vector2(0, sag)
	g.draw_polyline(PackedVector2Array([hand, mid, p]), Color(0.1, 0.12, 0.16, 0.7), 5.0)
	g.draw_polyline(PackedVector2Array([hand, mid, p]), Color(CHAIN.r, CHAIN.g, CHAIN.b, 0.95), 2.5)
	var links: int = clampi(int(hand.distance_to(p) / 10.0), 2, 40)
	for i in links:
		var u: float = float(i) / links
		var q: Vector2 = hand.lerp(mid, u * 2.0) if u < 0.5 else mid.lerp(p, u * 2.0 - 1.0)
		if i % 2 == 0:
			g.draw_circle(q, 2.6, Color(CHAIN.r * 0.75, CHAIN.g * 0.75, CHAIN.b * 0.8))
		else:
			g.draw_circle(q, 1.4, Color(1.2, 1.3, 1.4))
	# 飞出时：残影 + 速度线
	if not anchor.back:
		var tr: Array = anchor.trail
		for i in range(tr.size() - 1, 0, -1):
			_draw_anchor(tr[i], d, 0.35 * (1.0 - float(i) / tr.size()))
		for s in 3:
			var off: Vector2 = d.orthogonal() * (s - 1) * 9.0
			g.draw_line(p - d * 26.0 + off, p - d * (60.0 + s * 12.0) + off, Color(1.4, 1.5, 1.7, 0.35), 1.5)
	_draw_anchor(p, d, 1.0)


## 船锚：锚杆 + 锚环 + 横杆 + 两只弯钩，2 倍大（原来是几根 3 像素细线，扔出去像根牙签）
func _draw_anchor(p: Vector2, d: Vector2, a: float) -> void:
	var n: Vector2 = d.orthogonal()
	var dark := Color(0.08, 0.1, 0.14, 0.8 * a)
	var body := Color(STEEL.r * 1.1, STEEL.g * 1.1, STEEL.b * 1.15, a)
	var hi := Color(1.6, 1.7, 1.9, a)
	var crown: Vector2 = p + d * 14.0         # 锚冠（朝外）
	var tail: Vector2 = p - d * 14.0          # 锚环端（连链）
	# 描边
	g.draw_line(tail, crown, dark, 8.0)
	g.draw_line(tail + d * 4.0 - n * 9.0, tail + d * 4.0 + n * 9.0, dark, 6.0)
	# 锚杆 + 横杆
	g.draw_line(tail, crown, body, 5.0)
	g.draw_line(tail + d * 4.0 - n * 8.0, tail + d * 4.0 + n * 8.0, body, 3.5)
	g.draw_line(tail + d * 1.0, crown - d * 2.0, hi, 1.5)
	# 两只弯钩：从锚冠向后弯
	for sgn in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 7:
			var u: float = float(i) / 6.0
			var ang: float = lerpf(0.0, 2.0, u)
			pts.append(crown + n * sgn * sin(ang) * 13.0 - d * (1.0 - cos(ang)) * 9.0)
		g.draw_polyline(pts, dark, 7.0)
		g.draw_polyline(pts, body, 4.0)
		g.draw_circle(pts[pts.size() - 1], 3.0, hi)
	# 锚环
	g.draw_arc(tail - d * 3.0, 4.0, 0.0, TAU, 12, body, 2.5)


func status_items() -> Array:
	var out: Array = []
	if stacks > 0:
		out.append(["血脉 ×%d" % stacks, Color(0.9, 0.4, 0.45)])
	if haste_t > 0.0:
		out.append(["开辟", STEEL])
	return out


func stats_rows() -> Array:
	return [["血脉层数", "%d / %d" % [stacks, _stack_cap()]]]
