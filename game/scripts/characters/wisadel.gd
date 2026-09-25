## 维什戴尔（狙击，契约 v2.1）：炮击 → 余震爆炸 → 残影殉爆。
## S1 灰烬弹幕：接下来 3 发炮击 ×1.5 且必余震；S2 凋零处刑：一发 ×3 重炮 + 眩晕；S3 饱和炮击：8 发连射，每发余震。
## 炮弹是本干员自己的实体（抛物线飞行 → 落点爆炸 → 0.45 秒后原地余震），不走 game.gd 的子弹表。
## 索敌：打离博士最近的敌人（博士是唯一会掉血的）；最近几个距离相仿时挑周围敌人最多的落点。凋零处刑精英 / Boss 优先。
## 特效（docs/25）：黑红。弹体是黑红彗星（一整条连续轮廓：圆头最宽，沿轨迹平滑收细到尾尖，尾上带黑色碎屑）；落点从出膛起画收缩的红色准星；
## 落地橙白闪 → 黑烟 → 红环 → 带火头碎片 → 地面焦痕；余震只有地面双环 + 裂纹 + 上飘余烬。全程不震镜头。
extends "res://scripts/characters/character.gd"

const RED := Color(0.95, 0.22, 0.2)
const BOLT := Color(0.9, 0.08, 0.1)      # 弹体：黑红色能量光
const EMBER := Color(1.0, 0.55, 0.3)
const DARK := Color(0.1, 0.06, 0.08)
const CLUSTER_SLACK := 40.0      # 离博士最近的几个敌人距离相差在此以内时，改挑周围敌人最多的

var cd := 0.6
var shells: Array = []       # {from, to, t, dur, dmg, r, src, trail, quake, stun, light}
var quakes: Array = []       # 余震：{pos, t, dmg, r}
var shades: Array = []       # 残影（殉爆前摇）：{pos, t, dmg, r, depth}
var ash := 0                 # S1：剩余强化炮击数
var volley := 0              # S3：饱和炮击剩余发数
var volley_t := 0.0
var volley_tg: Array = []


func _aoe() -> float:
	return 52.0 * stat(&"op_range") * (1.15 if elite >= 1 else 1.0)


func _reach(k: float = 480.0) -> float:
	return k * stat(&"op_range")


# ---------------------------------------------------------------- 索敌

## 普攻 / S1 / S3 的目标：离博士最近；最近几个距离相仿（40px 内）时挑落点周围敌人最多的
func _target(reach: float) -> Dictionary:
	var cands: Array = []
	for e in g._nearest(6, reach, g.ppos):
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
	for e in g._nearest(24, reach, pos):
		if (e.elite or e.boss) and e.hp > hp:
			hp = e.hp
			best = e
	return best if not best.is_empty() else _target(reach)


func _count_around(c: Vector2, r: float) -> int:
	var n := 0
	for j in g._query(c, r):
		var q: Dictionary = g.enemies[j]
		if not q.dead and q.pos.distance_to(c) < r:
			n += 1
	return n


# ---------------------------------------------------------------- 更新

func update(dt: float) -> void:
	cd -= dt
	_update_shells(dt)
	if volley > 0:
		volley_t -= dt
		if volley_t <= 0.0:
			volley_t = 0.08
			volley -= 1
			var tg: Dictionary = volley_tg[volley % volley_tg.size()] if not volley_tg.is_empty() else {}
			var to: Vector2 = tg.pos if not tg.is_empty() and not tg.dead else _fallback_spot()
			if to != Vector2.INF:
				_fire(to + Vector2(g.rng.randf_range(-24, 24), g.rng.randf_range(-24, 24)), 34.0 * 1.6 * skill_power(), "饱和炮击", 1.2, true, 0.0, true)
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		ash = 3
		fx({"kind": "glow", "pos": _muzzle(), "r": 16.0, "life": 0.3, "col": RED, "alpha": 0.5})
		g._add_text(pos + Vector2(0, -80), "灰烬弹幕", RED, 14)
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
			cd = 1.4 / stat(&"op_aspd")
			start_attack(tgt.pos)


func _fallback_spot() -> Vector2:
	var tg := _target(_reach(520.0))
	return tg.pos if not tg.is_empty() else Vector2.INF


func _release() -> void:
	var tgt: Dictionary = _target(_reach(520.0))
	if tgt.is_empty():
		return
	if ash > 0:
		ash -= 1
		_fire(tgt.pos, 34.0 * 1.5 * skill_power(), "炮击", 1.1, true, 0.0)
	else:
		_fire(tgt.pos, 34.0, "炮击", 1.0, true, 0.0)


func _release_skill() -> void:
	match cur_skill:
		1:
			# 凋零处刑：一发重炮，眩晕 + 余震
			var tgt: Dictionary = _execute_target(_reach(540.0))
			if tgt.is_empty():
				return
			_fire(tgt.pos, 34.0 * 3.0 * skill_power(), "凋零处刑", 1.6, true, 0.8)
			fx({"kind": "glow", "pos": _muzzle(), "r": 28.0, "life": 0.3, "col": RED, "alpha": 0.6})
			fx_sparks(_muzzle(), EMBER, 10, 200.0, 0.3)
			Sfx.play("boom", -8.0, 0.6, 0.05)
		2:
			# 饱和炮击：离博士最近的 8 个不同目标轮流落弹
			var n := 8
			volley_tg = []
			for e in g._nearest(n, _reach(520.0), g.ppos):
				if e.pos.distance_to(pos) <= _reach(520.0):
					volley_tg.append(e)
			volley = n
			volley_t = 0.0
			fx({"kind": "glow", "pos": _muzzle(), "r": 24.0, "life": 0.3, "col": RED, "alpha": 0.5})
			fx_sparks(_muzzle(), EMBER, 8, 160.0, 0.3)
			Sfx.play("boom", -12.0, 0.8, 0.05)


func skill_active_left(i: int) -> float:
	return float(volley) * 0.08 if i == 2 else 0.0


func _muzzle() -> Vector2:
	return pos + Vector2(14.0 * face, -34)


func _fire(to: Vector2, base_dmg: float, src: String, size: float, quake: bool, stun: float, light := false) -> void:
	face = signf(to.x - pos.x) if absf(to.x - pos.x) > 2.0 else face
	var from := _muzzle()
	var dur: float = clampf(from.distance_to(to) / 900.0, 0.18, 0.5)
	shells.append({"from": from, "to": to, "t": 0.0, "dur": dur, "dmg": base_dmg * _dmg_bonus(), "r": _aoe() * size, "src": src,
		"trail": 0.0, "quake": quake, "stun": stun, "light": light, "hist": []})
	# 出膛：暗红锥形炮口焰 + 向后飞的橙色火星
	var dir := (to - from).normalized()
	fx({"kind": "muzzle", "pos": from, "dir": dir, "life": 0.08, "col": RED, "sz": 22.0 * size})
	for k in 3:
		fx({"kind": "spark", "pos": from, "vel": (-dir).rotated(g.rng.randf_range(-0.6, 0.6)) * g.rng.randf_range(60, 140), "life": 0.2, "col": EMBER, "sz": 2.0, "drag": 3.0})
	Sfx.play("swing", -15.0, 0.7, 0.05)


func _shell_pos(s: Dictionary) -> Vector2:
	return _shell_at(s, s.t / s.dur)


func _shell_at(s: Dictionary, k: float) -> Vector2:
	return s.from.lerp(s.to, k) + Vector2(0, -sin(k * PI) * minf(120.0, s.from.distance_to(s.to) * 0.35))


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
			# 余震：E1 起伤害 40% → 60%
			if s.quake:
				quakes.append({"pos": s.to, "t": 0.45, "dmg": s.dmg * (0.6 if elite >= 1 else 0.4), "r": s.r * 1.2})
	shells = shells.filter(func(s): return s.t < s.dur)
	for q in quakes:
		q.t -= dt
		if q.t <= 0.0:
			_explode(q.pos, q.dmg, q.r, "余震", 0, 0.0)
	quakes = quakes.filter(func(q): return q.t > 0.0)
	for sh in shades:
		sh.t -= dt
		if sh.t <= 0.0:
			_explode(sh.pos, sh.dmg, sh.r, "殉爆", sh.depth, 0.6)
	shades = shades.filter(func(sh): return sh.t > 0.0)


## 爆炸：范围伤害；E1 起被炸死的敌人留下残影，0.25 秒后殉爆并眩晕。light：饱和炮击的减量特效
func _explode(c: Vector2, dmg: float, r: float, src: String, depth: int, stun: float, light := false) -> void:
	var killed: Array = []
	for e in g._arc_hit(c, 0.0, PI, r):
		g._hit(src)
		g._damage(e, dmg)
		if not e.dead and g.rfx.sniper_execute(e, g.hit):
			g._hit("真实")
			g._damage(e, e.hp + 1.0)
		if e.dead:
			killed.append(e.pos)
		elif stun > 0.0 and not e.boss:
			e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
	match src:
		"余震":
			# 只在地面：双红环 + 裂纹 + 一圈向上的余烬，不闪光不冒烟
			fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.2, "life": 0.35, "col": RED, "floor": true, "w": 3.0})
			fx({"kind": "ring", "pos": c, "r": r * 0.65, "r0": r * 0.1, "life": 0.45, "col": Color(1.0, 0.45, 0.35), "floor": true, "w": 2.0})
			fx({"kind": "crack", "pos": c, "r": r * 0.7, "life": 0.35, "col": RED, "floor": true, "n": 7, "ang": c.x * 0.01})
			for k in (4 if light else 8):
				var ox: float = g.rng.randf_range(-r * 0.6, r * 0.6)
				fx({"kind": "spark", "pos": c + Vector2(ox, 0), "vel": Vector2(ox * 0.4, g.rng.randf_range(-110, -60)), "life": 0.4, "col": RED, "sz": 2.0, "grav": 160.0})
		"殉爆":
			fx({"kind": "smoke", "pos": c, "r": r * 0.8, "life": 0.45, "col": DARK})
			_impact_fx(c, r, light)
		"饱和炮击":
			_burst_fx(c, r)
		"凋零处刑":
			_burst_fx(c, r, true)
		_:
			_impact_fx(c, r, light)
	Sfx.play("boom", -16.0 if src == "余震" else -13.0, 1.2, 0.1)
	if elite >= 1 and depth < 1:
		for k in mini(killed.size(), 3):
			shades.append({"pos": killed[k], "t": 0.25, "dmg": dmg * 0.4, "r": r * 0.8, "depth": depth + 1})
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


## 饱和炮击的爆炸（照原作）：白粉核心星芒 → 放射状红色刀锋光条 → 紫灰烟环旋开 → 红色碎刃飞散
func _burst_fx(c: Vector2, r: float, small := false) -> void:
	var sc: float = 0.7 if small else 1.0
	fx({"kind": "burst", "pos": c, "r": r * 1.6 * sc, "life": 0.5 if small else 0.55, "seed": g.rng.randf() * TAU, "n": 8 if small else 12})
	fx({"kind": "smoke_ring", "pos": c, "r": r * 1.5 * sc, "life": 0.6 if small else 0.7, "seed": g.rng.randf() * TAU})
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
		"smoke_ring":
			# 紫灰烟环：由若干团烟组成的圆环，边旋边扩、变淡
			var k := 1.0 - a
			var rr: float = f.r * (0.55 + 0.55 * k)
			for q in 10:
				var ang: float = f.seed + q * TAU / 10.0 + k * 1.2
				var pp: Vector2 = f.pos + Vector2.from_angle(ang) * rr
				g.draw_circle(pp, f.r * (0.2 + 0.12 * k), Color(0.38, 0.24, 0.46, 0.4 * a))
				g.draw_circle(pp + Vector2(4, -4), f.r * (0.1 + 0.08 * k), Color(0.55, 0.36, 0.62, 0.28 * a))
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
		if pts.size() < 2:
			g.draw_circle(p, 5.5, Color(0.16, 0.02, 0.04))
			continue
		g.draw_colored_polygon(_comet_outline(pts, 11.0), Color(1.2, 0.08, 0.1, 0.3))
		g.draw_colored_polygon(_comet_outline(pts, 7.5), Color(0.34, 0.03, 0.06, 0.95))
		g.draw_colored_polygon(_comet_outline(pts, 4.0), Color(0.1, 0.01, 0.03, 1.0))


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
	if volley > 0:
		out.append(["饱和炮击", Color(1.0, 0.55, 0.45)])
	return out
