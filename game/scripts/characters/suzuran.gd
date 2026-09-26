## 铃兰（辅助，契约 v2.1）：减速光域（只减速不伤害）+ 向 2 名敌人发射追踪狐火。
## S1 狐火连珠：下一次普攻 5 发；S2 暖光（永久型）：充能一次后光域永久扩大、其他干员加攻、主控回复；S3 狐火迷雾：10 秒大光域，减速 60%、易伤 25%，期间不普攻。
## 特效（docs/25）：狐火金。光域为地面淡金椭圆 + 边缘绕行的六团狐火；狐火弹金白火球带火舌尾；技能期间光点上升。
## 可见成长（docs/25 §5）：身边常驻小狐火 = 每次普攻狐火数；三火归一的大狐火；狐火连珠定身金印；围炉狐火；精二九尾虚影。
extends "res://scripts/characters/character.gd"

const GOLD := Color(1.0, 0.82, 0.45)
const S3_DUR := 10.0

var cd := 0.5
var volley_next := false      # S1：下一次普攻改为 5 发
var warm := false             # S2 暖光（永久）
var haze_t := 0.0             # S3 狐火迷雾
var mote_t := 0.0
var heal_acc := 0.0
var pillar_t := 0.0
# ---- 可见成长（docs/25 §5：只长狐火。原作依据：技能演示三团狐火汇聚成一团射出；九尾）
var fox_plus := false            # N1「狐火点点」：每次普攻狐火 +1；身边常驻的小狐火数 = 每次普攻的狐火数
var merge_on := false            # N2「三火归一」：每第 3 次普攻，三团狐火在身前汇成一团大狐火射出（贯穿）
var seal_on := false             # N4「画地为牢」：狐火连珠命中的敌人被定身，脚下金色封印
var hearth_on := false           # N5「围炉」：暖光生效后，光域边缘的六团狐火灼伤碰到的敌人
var nine_tails := false          # 精二「九尾祈愿」：身后九尾虚影；每次普攻都三火归一
var atk_n := 0                   # 普攻计数（不含狐火连珠），决定哪一次三火归一
var merging := false             # 本次普攻是三火归一（起手到出手之间，三团狐火向身前汇聚）
var bigfox: Array = []           # 大狐火 {pos, vel, dmg, life, r, hit, trail}
var sealed: Array = []           # 狐火连珠射出的狐火（g.bullets 里同一个字典），命中后定身
var seals: Array = []            # 定身金印 {e, t}
var hearth_hit: Dictionary = {}  # 围炉：敌人 id → 下次可再受伤的时刻
const PROJ_MAX := 12             # 弹体上限：普通狐火 + 大狐火 + 围炉狐火合计
const SEAL_MAX := 6              # 地面金印上限


## 基础数值全部可由 data/characters/suzuran.json 的 base 段覆盖（docs/27 §3）
func aura_radius() -> float:
	var r: float = (base("aura", 85.0) + 15.0 * elite) * stat(&"op_range")
	if haze_t > 0.0:
		return r * 2.2
	return r * (1.6 if warm else 1.0)


## 成长节点（data/characters/suzuran.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"fox_plus":
			fox_plus = true
		"fox_merge":
			merge_on = true
		"fox_seal":
			seal_on = true
		"fox_hearth":
			hearth_on = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		nine_tails = true


## 每次普攻的狐火数（狐火点点 +1、祈愿 +1）
func shots_n() -> int:
	return int(base("shots", 2.0)) + (int(base("n1_shots", 1.0)) if fox_plus else 0) + (1 if elite >= 1 else 0)


## 下一次普攻是否三火归一（精二每次都是）
func _next_merge() -> bool:
	if nine_tails:
		return true
	var every: int = maxi(1, int(base("merge_every", 3.0)))
	return merge_on and atk_n % every == every - 1


func _hearth_live() -> bool:
	return hearth_on and warm and pos != Vector2.INF


## 还能再放几发弹体（普通狐火 + 大狐火 + 围炉狐火合计 ≤ 12）
func _proj_room() -> int:
	var live: int = bigfox.size() + (int(base("hearth_n", 6.0)) if _hearth_live() else 0)
	for b in g.bullets:
		if b.life > 0.0 and b.get("op", "") == id:
			live += 1
	return PROJ_MAX - live


func update(dt: float) -> void:
	cd -= dt
	_update_orbs(dt)
	_update_bigfox(dt)
	_update_seals(dt)
	if _hearth_live():
		_update_hearth()
	var on := warm or haze_t > 0.0
	if on:
		var was_haze := haze_t > 0.0
		haze_t = maxf(0.0, haze_t - dt)
		mote_t -= dt
		if mote_t <= 0.0:
			mote_t = 0.05 if haze_t <= 0.0 else 0.03
			var a: float = g.rng.randf() * TAU
			var rr: float = g.rng.randf() * aura_radius()
			fx({"kind": "mote", "pos": pos + Vector2(cos(a) * rr, sin(a) * rr * 0.55), "vel": Vector2(0, -40), "life": 0.7, "col": GOLD, "sz": 1.8})
		# 迷雾期间：光域里不时落下一根小光柱
		pillar_t -= dt
		if haze_t > 0.0 and pillar_t <= 0.0:
			pillar_t = 0.9
			var a2: float = g.rng.randf() * TAU
			var rr2: float = g.rng.randf_range(0.3, 0.9) * aura_radius()
			spawn_fx_sprite("fx_holy_pillar", pos + Vector2(cos(a2) * rr2, sin(a2) * rr2 * 0.55 + 4.0), g.PX * 0.7, 0.0, false, true)
		# 光域内的主控缓慢回复（原作：范围内友军回复）
		heal_acc += dt
		if heal_acc >= 1.0:
			heal_acc -= 1.0
			if g.hp < g.max_hp:
				heal_leader(g.max_hp * (0.01 if haze_t > 0.0 else 0.005), "铃兰")
		if was_haze and haze_t <= 0.0:
			# 迷雾刚结束：回到暖光（永久）或清除加成
			if warm:
				_field_buff(base("s2_buff", 0.15) * skill_power())
			else:
				g.stats.remove_source("suzuran_field")
				refresh_stats()
	var rad := aura_radius()
	for j in query_ids(pos, rad + 20.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(pos) > rad:
			continue
		e.slow = maxf(e.slow, 0.6 if haze_t > 0.0 else (0.4 if warm else 0.2))
		if elite >= 1 or haze_t > 0.0:
			e["aura_weak"] = maxf(float(e.get("aura_weak", 0.0)), 0.2)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		volley_next = true
		fx({"kind": "glow", "pos": pos + Vector2(0, -30), "r": 18.0, "life": 0.3, "col": GOLD, "alpha": 0.5})
		spawn_fx_sprite("fx_circle_gold", pos + Vector2(0, 4), g.PX * 1.6)
		return
	if ready > 0:
		start_skill(Vector2.INF, ready)
		return
	if haze_t > 0.0:
		return   # 狐火迷雾：期间不普攻
	if cd <= 0.0:
		var ts: Array = nearest_enemies(2, base("range", 380.0) * stat(&"op_range"), pos)
		if ts.is_empty():
			cd = 0.2
		else:
			cd = base("cd", 1.2) / stat(&"op_aspd")
			merging = _next_merge() and not volley_next
			start_attack(ts[0].pos)
			# Codex 三团狐火汇聚（原作：三团狐火合而为一再射出）：三火归一的那一次在身前播一遍
			if merging:
				spawn_fx_sprite("fx_suzuran_foxfire_gather", pos + Vector2(20.0 * face, -34), g.PX * 0.9)


func _release() -> void:
	var n: int = shots_n()
	var mult := 1.0
	var volley := false
	if volley_next:
		volley_next = false
		volley = true
		n = int(base("s1_shots", 5.0))
		mult = base("s1_mult", 1.2) * skill_power()
	var big := merging and not volley
	merging = false
	var ts: Array = nearest_enemies(n, 400.0 * stat(&"op_range"), pos)
	var from := pos + Vector2(12.0 * face, -30)
	if ts.is_empty():
		return
	if not volley:
		atk_n += 1
	var room := _proj_room()
	if big and room > 0:
		# 三火归一：身前汇成的一团大狐火朝最近的敌人直线射出、贯穿沿途敌人；多出来的狐火照常发射
		room -= 1
		n = maxi(0, n - 3)
		_fire_big(pos + Vector2(20.0 * face, -34), ts[0])
	for k in n:
		if room <= 0:
			break
		room -= 1
		var tg: Dictionary = ts[k % ts.size()]
		var d: Vector2 = (tg.pos - pos).normalized().rotated(0.6 * (1 if k % 2 == 0 else -1) * (1.0 + 0.3 * (k / 2)))
		# aoe：狐火命中时的小范围溅射（P5.1：纯单体的辅助单人开局清不动 1:15 的骨潮，永远到不了招募等级）
		var b := {"kind": "arcane", "pos": from, "vel": d * 330.0, "dmg": base("atk", 26.0) * mult * _dmg_bonus(),
			"life": 1.6, "r": 7.0, "aoe": base("aoe", 26.0), "home": tg, "turn": 7.0, "src": "狐火", "op": id, "fx_col": GOLD, "hidden": true, "etrail": 0.0}
		g.bullets.append(b)
		# 画地为牢：狐火连珠的狐火命中后定身（命中由 game.gd 结算，这里记住弹体，下一帧看它是否撞上了敌人）
		if volley and seal_on:
			sealed.append(b)
	fx({"kind": "glow", "pos": from, "r": 10.0, "life": 0.15, "col": GOLD, "alpha": 0.5})
	Sfx.op(id, "atk")


## 三火归一：大狐火（伤害 = 一团狐火 × merge_mult，贯穿，每名敌人只伤一次）
func _fire_big(from: Vector2, tg: Dictionary) -> void:
	var d: Vector2 = (tg.pos + Vector2(0, -8) - from).normalized()
	bigfox.append({"pos": from, "vel": d * base("merge_spd", 340.0), "dmg": base("atk", 26.0) * base("merge_mult", 2.2) * _dmg_bonus(),
		"life": base("merge_life", 1.3), "r": base("merge_r", 14.0), "hit": {}, "trail": 0.0})
	fx({"kind": "glow", "pos": from, "r": 24.0, "life": 0.22, "col": GOLD, "alpha": 0.7})
	fx({"kind": "ring", "pos": from, "r": 30.0, "r0": 6.0, "life": 0.25, "col": GOLD, "w": 2.0})


func _update_bigfox(dt: float) -> void:
	if bigfox.is_empty():
		return
	for f in bigfox:
		f.life -= dt
		f.pos += f.vel * dt
		f.trail -= dt
		if f.trail <= 0.0:
			f.trail = 0.03
			fx({"kind": "flame", "pos": f.pos - f.vel.normalized() * 10.0 + Vector2(g.rng.randf_range(-4, 4), g.rng.randf_range(-4, 4)), "vel": -f.vel * 0.12 + Vector2(0, -20), "life": 0.3, "col": GOLD, "sz": 11.0})
		for j in query_ids(f.pos, f.r + 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or f.hit.has(e.id) or e.pos.distance_to(f.pos) > f.r + e.r:
				continue
			f.hit[e.id] = true
			log_hit("狐火", ["pierce"])
			deal_damage(e, f.dmg)
			if not e.dead:
				e.slow = maxf(e.slow, 1.0)
			fx({"kind": "ring", "pos": e.pos, "r": 26.0, "r0": 6.0, "life": 0.22, "col": GOLD, "w": 2.5})
			fx_sparks(e.pos, GOLD, 4, 180.0, 0.3, 2.5)
	bigfox = bigfox.filter(func(f): return f.life > 0.0)


## 画地为牢：狐火连珠的狐火撞上敌人（game.gd 命中时把弹体 life 置 0；自然消散是负数）→ 定身 + 金印
func _update_seals(dt: float) -> void:
	for i in range(sealed.size() - 1, -1, -1):
		var b: Dictionary = sealed[i]
		if b.life > 0.0:
			continue
		sealed.remove_at(i)
		if b.life < 0.0:
			continue
		var best = null
		var bd := 40.0
		for j in query_ids(b.pos, 40.0):
			var e: Dictionary = g.enemies[j]
			var dd: float = e.pos.distance_to(b.pos) - e.r
			if not e.dead and dd < bd:
				bd = dd
				best = e
		if best == null or best.boss:
			continue
		var st: float = base("seal_stun_elite", 0.25) if best.elite else base("seal_stun", 0.5)
		best.stun = maxf(best.stun, st)
		var found := false
		for s2 in seals:
			if s2.e == best:
				s2.t = maxf(s2.t, st)
				found = true
		if not found:
			if seals.size() >= SEAL_MAX:
				seals.pop_front()
			seals.append({"e": best, "t": st})
	for s2 in seals:
		s2.t -= dt
	seals = seals.filter(func(s2): return s2.t > 0.0 and not s2.e.dead)


## 围炉：暖光光域边缘的六团狐火（与 draw_auras 画的位置一致）灼伤碰到的敌人，每名敌人 0.5 秒一次
func _update_hearth() -> void:
	var r := aura_radius()
	var n: int = int(base("hearth_n", 6.0))
	var dmg: float = base("atk", 26.0) * base("hearth_mult", 0.3) * _dmg_bonus()
	var every: float = base("hearth_cd", 0.5)
	for k in n:
		var a: float = g.t * 0.8 + k * TAU / n
		var p: Vector2 = pos + Vector2(4, 4) + Vector2(cos(a) * r, sin(a) * r * 0.55)
		for j in query_ids(p, 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(p) > 14.0 + e.r or float(hearth_hit.get(e.id, -1.0)) > g.t:
				continue
			hearth_hit[e.id] = g.t + every
			log_hit("围炉")
			deal_damage(e, dmg)
			fx({"kind": "flame", "pos": e.pos + Vector2(0, 4), "vel": Vector2(0, -30), "life": 0.3, "col": GOLD, "sz": 10.0})
	if hearth_hit.size() > 200:
		for key in hearth_hit.keys():
			if hearth_hit[key] < g.t:
				hearth_hit.erase(key)


## 狐火弹的火舌尾
func _update_orbs(dt: float) -> void:
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "arcane":
			continue
		b.etrail = b.get("etrail", 0.0) - dt
		if b.etrail <= 0.0:
			b.etrail = 0.05
			fx({"kind": "flame", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.08 + Vector2(0, -14), "life": 0.25, "col": GOLD, "sz": 7.0})


func _release_skill() -> void:
	heal_acc = 0.0
	match cur_skill:
		1:
			warm = true
			_field_buff(base("s2_buff", 0.15) * skill_power())
			show_banner("暖光：光域永久扩大")
		2:
			haze_t = S3_DUR
			_field_buff(base("s3_buff", 0.2) * skill_power())
			show_banner("狐火迷雾")
	fx({"kind": "ring", "pos": pos, "r": aura_radius(), "r0": 10.0, "life": 0.6, "col": GOLD, "floor": true})
	g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -24), "life": 0.5, "max": 0.5, "col": GOLD})
	# 圣光光柱（Pimen Holy VFX 02）：中心一根 + 光域边缘六根小的
	spawn_fx_sprite("fx_holy_pillar", pos + Vector2(0, 4), g.PX * (1.4 if cur_skill == 2 else 1.0), 0.0, false, true)
	var rr3 := aura_radius()
	for k in 6:
		var a3: float = k * TAU / 6.0 + g.t * 0.8
		spawn_fx_sprite("fx_holy_pillar", pos + Vector2(4, 4) + Vector2(cos(a3) * rr3, sin(a3) * rr3 * 0.55), g.PX * 0.6, 0.0, false, true)
	spawn_fx_sprite("fx_circle_gold", pos + Vector2(0, 4), g.PX * 2.2)


## 其他干员攻击加成：只写入别的干员的 op:<id> 作用域，不给自己
func _field_buff(v: float) -> void:
	g.stats.remove_source("suzuran_field")
	for o in g.squad.ops:
		if o != self:
			g.stats.add(&"op_atk", "add", v, "suzuran_field", "op:" + o.id)
	refresh_stats()


func skill_active_left(i: int) -> float:
	return haze_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


func _flame(p: Vector2, h: float, a: float) -> void:
	var wob: float = sin(g.t * 20.0 + p.x * 0.3) * 2.0
	g.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.35, 0), p + Vector2(wob, -h), p + Vector2(h * 0.35, 0)]), Color(GOLD.r, GOLD.g, GOLD.b, 0.75 * a))
	g.draw_colored_polygon(PackedVector2Array([p + Vector2(-h * 0.15, 0), p + Vector2(wob * 0.6, -h * 0.55), p + Vector2(h * 0.15, 0)]), Color(2.2, 2.0, 1.4, 0.8 * a))


func draw_auras() -> void:
	if pos == Vector2.INF:
		return
	if nine_tails:
		_draw_tails()
	var r := aura_radius()
	var on := warm or haze_t > 0.0
	g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	g.draw_circle(Vector2.ZERO, r, Color(GOLD.r, GOLD.g, GOLD.b, 0.09 if on else 0.05))
	g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(GOLD.r, GOLD.g, GOLD.b, (0.45 if on else 0.25) + 0.06 * sin(g.t * 3.0)), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _hearth_live():
		# 围炉：六团狐火变大、带热光，碰到的敌人会被灼伤
		var hn: int = int(base("hearth_n", 6.0))
		for k in hn:
			var a: float = g.t * 0.8 + k * TAU / hn
			var hp: Vector2 = pos + Vector2(4, 4) + Vector2(cos(a) * r, sin(a) * r * 0.55)
			g.draw_circle(hp + Vector2(0, -6), 12.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.22))
			_flame(hp, 15.0, 1.0)
		return
	# 边缘六团狐火绕行（迷雾时九团）
	var n: int = 9 if haze_t > 0.0 else 6
	for k in n:
		var a: float = g.t * 0.8 + k * TAU / n
		_flame(pos + Vector2(4, 4) + Vector2(cos(a) * r, sin(a) * r * 0.55), 9.0 if on else 6.0, 0.9 if on else 0.6)


## 精二「九尾祈愿」：身后一把淡金色的九尾虚影（扇形展开、尾尖更亮、缓慢摆动），画在人物之下
func _draw_tails() -> void:
	# 以腰后为根、朝上略向身后张开的一把大扇形，尾尖露出在头顶与身体两侧
	var root: Vector2 = pos + Vector2(-4.0 * face, -28)
	# Codex 帧条 fx_suzuran_ninetails（64×48 × 4 帧，4fps 循环，底部根点 (32,46) 放在腰后；整体 alpha 0.45）
	if _fx_strip("fx_suzuran_ninetails", 4, int(g.t * 4.0), root, Vector2(0.5, 46.0 / 48.0), 0.0, Color(1, 1, 1, 0.45), face < 0.0):
		return
	var center: float = -PI / 2.0 - 0.25 * face
	for k in 9:
		var t: float = (k - 4) / 4.0
		var a0: float = center + t * 1.25
		var sway: float = sin(g.t * 1.8 + k * 0.7) * 0.12
		var L: float = 92.0 - absf(t) * 22.0
		# 两层填充（外层淡、内层亮）+ 白色尾尖，不画描边线（线条会显得像触须）
		for layer in 2:
			var ws: float = 1.0 if layer == 0 else 0.5
			var left := PackedVector2Array()
			var right := PackedVector2Array()
			for i in 9:
				var u: float = i / 8.0
				var an: float = a0 + sway * u * 2.0 + u * u * 0.4 * signf(t + 0.001) * face
				var p: Vector2 = root + Vector2.from_angle(an) * L * u
				var w: float = (12.0 * sin(PI * minf(1.0, u * 1.05 + 0.1)) + 0.8) * ws
				var nv: Vector2 = Vector2.from_angle(an).orthogonal()
				left.append(p + nv * w)
				right.append(p - nv * w)
			right.reverse()
			var pts: PackedVector2Array = left
			pts.append_array(right)
			var al: float = (0.2 if layer == 0 else 0.22) + 0.04 * sin(g.t * 3.0 + k)
			g.draw_colored_polygon(pts, Color(GOLD.r * 1.3, GOLD.g * 1.2, GOLD.b, al) if layer == 0 else Color(2.0, 1.7, 1.0, al))
		var tip_an: float = a0 + sway * 2.0 + 0.4 * signf(t + 0.001) * face
		g.draw_circle(root + Vector2.from_angle(tip_an) * L * 0.9, 3.5, Color(2.4, 2.2, 1.8, 0.3))


## 身边常驻的小狐火：数量 = 每次普攻的狐火数（一眼看出狐火长到了几团）。
## 三火归一的那一次：出手前三团狐火向身前汇聚，出手时合成一团大狐火射出
func _draw_foxfires() -> void:
	if pos == Vector2.INF:
		return
	var n: int = shots_n()
	var conv := 0.0
	if merging:
		conv = 1.0
	elif haze_t <= 0.0 and _next_merge():
		conv = clampf(1.0 - cd / 0.45, 0.0, 1.0)
	var c: Vector2 = pos + Vector2(20.0 * face, -34)
	for k in n:
		var a: float = g.t * 1.6 + k * TAU / n
		var p: Vector2 = pos + Vector2(cos(a) * 40.0, -22.0 + sin(a) * 13.0 + sin(g.t * 3.0 + k) * 2.0)
		if k < 3 and conv > 0.0:
			if conv > 0.85:
				continue
			p = p.lerp(c, conv * conv)
		# 狐火：金色光晕 + 白热火芯，与铃兰本身的黄色尾巴区分开
		g.draw_circle(p + Vector2(0, -5), 9.0, Color(1.6, 1.1, 0.4, 0.35))
		# Codex 帧条 fx_suzuran_wisp（8×12 × 4 帧，8fps 循环，中心锚点；火苗底部对齐原火舌根部）
		if _fx_strip("fx_suzuran_wisp", 4, int(g.t * 8.0) + k, p + Vector2(0, -8)):
			continue
		_flame(p, 13.0, 1.0)
		g.draw_circle(p + Vector2(0, -4), 2.5, Color(2.6, 2.4, 1.8, 0.95))
	if conv > 0.5:
		var hh: float = lerpf(10.0, 22.0, (conv - 0.5) * 2.0)
		g.draw_circle(c + Vector2(0, -hh * 0.4), hh * 0.7, Color(GOLD.r, GOLD.g, GOLD.b, 0.3 * conv))
		_flame(c, hh, conv)


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


func _draw_skill_over() -> void:
	_draw_foxfires()
	# 三火归一的大狐火：大一圈的狐火弹 + 热光
	for f in bigfox:
		g.draw_circle(f.pos, 24.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.22))
		g.draw_circle(f.pos, 14.0, Color(2.0, 1.6, 0.8, 0.45))
		# Codex 帧条 proj_suzuran_bigfox（24×16 × 4 帧，10fps 循环，朝右 → 按速度方向旋转）
		if _fx_strip("proj_suzuran_bigfox", 4, int(g.t * 10.0), f.pos, Vector2(0.5, 0.5), f.vel.angle()):
			pass
		elif g.tex.get("proj_foxfire") != null:
			draw_spr_rot("proj_foxfire", int(g.t * 12.0) % 6, f.pos, f.vel.angle(), g.PX * 1.9)
		else:
			g.draw_circle(f.pos, 9.0, Color(2.4, 2.0, 1.2))
	# 狐火弹：OGA Light Bolt 调金（proj_foxfire），按速度方向旋转 + 外圈热光
	for b in g.bullets:
		if b.life <= 0.0 or b.get("op", "") != id or b.kind != "arcane":
			continue
		g.draw_circle(b.pos, 10.0, Color(GOLD.r, GOLD.g, GOLD.b, 0.22))
		if g.tex.get("proj_foxfire") != null:
			draw_spr_rot("proj_foxfire", int(g.t * 12.0 + b.pos.x * 0.05) % 6, b.pos, b.vel.angle(), g.PX)
		else:
			g.draw_circle(b.pos, 5.5, Color(2.2, 1.8, 1.0))


## 地面层：画地为牢的金色封印（跟着被定身的敌人）
func draw_entities_floor() -> void:
	for s2 in seals:
		var e: Dictionary = s2.e
		var a: float = clampf(s2.t / 0.15, 0.0, 1.0)
		var rr: float = e.r + 10.0
		g.draw_set_transform(e.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		g.draw_circle(Vector2.ZERO, rr, Color(GOLD.r, GOLD.g, GOLD.b, 0.12 * a))
		g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 28, Color(2.0, 1.6, 0.8, 0.85 * a), 2.0)
		g.draw_arc(Vector2.ZERO, rr * 0.68, 0.0, TAU, 20, Color(2.0, 1.6, 0.8, 0.5 * a), 1.0)
		for q in 4:
			var qa: float = g.t * 2.0 + q * TAU / 4.0
			g.draw_line(Vector2.from_angle(qa) * rr * 0.68, Vector2.from_angle(qa) * rr, Color(2.2, 1.8, 1.0, 0.8 * a), 1.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func status_items() -> Array:
	var out: Array = []
	if volley_next:
		out.append(["狐火连珠", GOLD])
	if haze_t > 0.0:
		out.append(["狐火迷雾", GOLD])
	return out
