extends RefCounted
## 子弹与支援装置：医疗无人机（保底治疗，docs/23 §17）、玩家侧子弹的飞行与命中结算、狙击选目标。
## 干员自己的投射物在各干员脚本里；敌方子弹在 game.gd _update_ebullets。2026-09-26 从 game.gd 拆出。

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var drone_rescue_cd := 0.0       # Lv.3 急救冷却
const DRONE_HEAL := [0.0, 0.02, 0.03, 0.03, 0.02, 0.025]
const DRONE_EVERY := [0.0, 6.0, 6.0, 6.0, 6.0, 5.0]
const EXPLODE_R_PX := 26.0


func _init(game: Game) -> void:
	g = game


func update(dt: float) -> void:
	var dl: int = g.weapons.get("drone", 0)
	if dl <= 0:
		return
	var want := 2 if dl >= 4 else 1
	while g.drones.size() < want:
		g.drones.append({"pos": g.ppos + Vector2(0, -60), "cd": 2.0 + g.drones.size() * 2.5, "ang": g.drones.size() * PI, "beam": 0.0, "face": 1.0})
	drone_rescue_cd = maxf(0.0, drone_rescue_cd - dt)
	for i in g.drones.size():
		var dr: Dictionary = g.drones[i]
		dr.ang += dt * 1.2
		var want_pos: Vector2 = g.ppos + Vector2(cos(dr.ang) * 46.0, -66.0 + sin(dr.ang * 2.0) * 6.0)
		var prev: Vector2 = dr.pos
		dr.pos = dr.pos.lerp(want_pos, clampf(dt * 4.0, 0.0, 1.0))
		if absf(dr.pos.x - prev.x) > 0.3:
			dr.face = signf(dr.pos.x - prev.x)
		dr.beam = maxf(0.0, dr.beam - dt)
		dr.cd -= dt * g.sp_mult
		if dr.cd <= 0.0:
			dr.cd = DRONE_EVERY[dl]
			if g.hp < g.max_hp:
				drone_heal(dr, g.max_hp * DRONE_HEAL[dl], dl >= 5)
		# Lv.3：低血急救
		if dl >= 3 and drone_rescue_cd <= 0.0 and g.hp < g.max_hp * 0.4 and i == 0:
			drone_rescue_cd = 25.0
			drone_heal(dr, g.max_hp * 0.06, dl >= 5)
			g._add_text(g.ppos + Vector2(0, -110), "急救", Color(0.5, 1.0, 0.6), 16)


func drone_heal(dr: Dictionary, amount: float, cure: bool) -> void:
	g.combat.heal(amount, "无人机")
	if cure:
		g.nerve = 0.0
	dr.beam = 0.35
	g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(amount), Color(0.5, 1.0, 0.6), 14)
	g.fx.append({"kind": "beam", "a": dr.pos + Vector2(0, 6), "b": g.ppos + Vector2(0, -24), "life": 0.3, "max": 0.3, "col": Color(0.5, 1.0, 0.6), "w": 2.5})
	if not g._fx_sprite("fx_heal_aura_green", g.ppos + Vector2(0, 6), g.PX * 1.1, 0.0, false, true):
		for k in 4:
			g.fx.append({"kind": "cross", "pos": g.ppos + Vector2(randf_range(-18, 18), randf_range(-40, -8)), "life": 0.8, "max": 0.8, "delay": k * 0.08, "sz": randf_range(3.0, 4.5)})
	Sfx.play("pickup", -14.0, 1.4, 0.05)


func sniper_target(from: Vector2, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var score := -1.0
	for j in g.enemies_sys.query(from, reach):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(from) > reach:
			continue
		var sc: float = e.hp + (100000.0 if (e.elite or e.boss) else 0.0)
		if sc > score:
			score = sc
			best = e
	return best


func update_bullets(dt: float) -> void:
	for b in g.bullets:
		if b.life <= 0.0:
			continue
		# 追踪：导弹 / 紫色法术
		var hm = b.get("home")
		if hm != null:
			if hm.dead:
				if b.has("accel"):
					# 导弹：目标没了就改追导弹附近最近的敌人
					var best = null
					var bd := 460.0
					for j in g.enemies_sys.query(b.pos, 460.0):
						var q: Dictionary = g.enemies[j]
						if not q.dead and not q.chest and q.pos.distance_to(b.pos) < bd:
							bd = q.pos.distance_to(b.pos)
							best = q
					b.home = best
				else:
					# 法术追踪弹：从弹体附近重新找目标（原来从博士身边找，常常找不到就直线飞走）
					var nt := g.enemies_sys.nearest(1, 360.0, b.pos)
					b.home = nt[0] if nt.size() > 0 else null
			else:
				# 匀速转向（2026-09-25）：原来 vel.lerp(want) 转弯时向量变短 → 越绕越慢、显得疲软。
				# 现在速度大小恒定、只转方向；转向角速度随飞行时间增大，保证一定追上、不会绕圈；目标还在就不会中途消失
				var spd: float = b.vel.length() if b.has("accel") else b.get("spd", b.vel.length())
				b["spd"] = spd
				b["age"] = b.get("age", 0.0) + dt
				var turn: float = b.get("turn", 6.0) * (1.0 + b.age * 2.5)
				var a0: float = b.vel.angle()
				var a1: float = rotate_toward(a0, (hm.pos - b.pos).angle(), turn * dt)
				b.vel = Vector2.from_angle(a1) * spd
				b.life = maxf(b.life, 0.2)
		# 导弹：持续加速到最高速并保持（没有目标时直线飞行，不会减速）
		if b.has("accel"):
			var sp: float = minf(b.vel.length() + b.accel * dt, b.vmax)
			b.vel = b.vel.normalized() * sp
		b.pos += b.vel * dt
		b.life -= dt
		if b.kind == "fire" and not b.get("hidden", false):
			b.trail = b.get("trail", 0.0) - dt
			if b.trail <= 0.0:
				b.trail = 0.03
				g.fx.append({"kind": "spark", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.1 + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
					"sz": 3.0, "life": 0.3, "max": 0.3, "col": Color(0.75, 0.35, 1.0)})
		for j in g.enemies_sys.query(b.pos, 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or b.pos.distance_to(e.pos) > e.r + b.r:
				continue
			if b.get("hit", {}).has(e.id):
				continue
			bullet_hit(b, e)
			break


## 子弹命中：按种类结算伤害与特效
func bullet_hit(b: Dictionary, e: Dictionary) -> void:
	if b.has("src"):
		g.combat.hit(b.src, b.get("tags", []))
	else:
		g.combat.hit("潮汐弹" if b.kind == "tide" else ("法术援护" if b.kind in ["fire", "arcane"] else "援护"))
	match b.kind:
		"arrow":
			# 狙击：命中流血；扼喉之手处决
			g.combat.damage(e, b.dmg)
			if g.rfx.sniper_execute(e, g.hit):
				g._add_text(e.pos + Vector2(0, -e.r - 12), "处决", Color(1.0, 0.4, 0.4), 15)
				g.combat.hit("真实")
				g.combat.damage(e, e.hp + 1.0)
			if not e.dead:
				e["bleed"] = 3.0
				e["bleed_dps"] = b.dmg * 0.2
			for k in 7:
				g.fx.append({"kind": "spark", "pos": e.pos, "vel": b.vel.normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(80, 220),
					"sz": 3.0, "life": 0.4, "max": 0.4, "col": Color(0.85, 0.08, 0.12)})
			g.fx.append({"kind": "blood", "pos": e.pos + Vector2(0, e.r * 0.6), "life": 2.5, "max": 2.5, "seed": randf() * 10.0})
			g._fx_sprite("fx_arrow_hit", e.pos, g.PX, b.vel.angle())
			if b.get("pierce", false):
				if not b.has("hit_ids"):
					b["hit_ids"] = {}
				b.hit_ids[e.id] = true
			else:
				b.life = 0.0
		"fire":
			# 法术团：爆炸
			for k in g.enemies_sys.query(b.pos, b.aoe + 20.0):
				var o: Dictionary = g.enemies[k]
				if not o.dead and o.pos.distance_to(b.pos) < b.aoe + o.r:
					g.combat.damage(o, b.dmg)
					if b.get("slow", false):
						o.slow = maxf(o.slow, 1.2)
			# 术师法术团：紫色（对应重绘后的 fx_fire_explode）；导弹：暖黄
			var fc: Color = b.get("fx_col", Color(0.7, 0.3, 1.0) if b.kind == "fire" else Color(1.0, 0.8, 0.4))
			# 美术 V6：爆炸帧条按伤害半径缩放（半径 / 26，限制 1.5–3.0），首帧叠判定圈；干员配色（fx_col）走程序爆炸
			var ename := "fx_fire_explode" if b.kind == "fire" else "fx_missile_explode"
			if not b.has("fx_col") and g._fx_sprite(ename, b.pos, clampf(b.aoe / EXPLODE_R_PX, 1.5, 3.0)):
				g.fx[-1]["ring"] = b.aoe
			else:
				g.fx.append({"kind": "explode", "pos": b.pos, "r": b.aoe, "life": 0.4, "max": 0.4, "col": fc})
			for k in 6:
				g.fx.append({"kind": "spark", "pos": b.pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(60, 240), "sz": 3.0, "life": 0.45, "max": 0.45,
					"col": fc.lerp(Color(0.95, 0.85, 1.0) if b.kind == "fire" else Color(1, 0.95, 0.6), randf())})
			if b.has("op"):
				Sfx.op(b.op, "hit", 0.0, 1.0, 0.1)   # 干员法术弹（艾雅法拉熔岩弹）
			else:
				Sfx.play("boom", -14.0 if b.kind == "fire" else -11.0, 1.5, 0.1)
			b.life = 0.0
			# 干员自带的命中后效果（点燃 / 分裂等）
			if b.get("on_hit") != null:
				b.on_hit.bullet_exploded(b)
		"arcane":
			g.combat.damage(e, b.dmg)
			if not e.dead:
				e.slow = maxf(e.slow, 1.0)
			# 溅射（铃兰狐火 base.aoe）：主目标之外、半径内的其他敌人吃同样伤害
			if b.get("aoe", 0.0) > 0.0:
				for k in g.enemies_sys.query(b.pos, b.aoe + 20.0):
					var o: Dictionary = g.enemies[k]
					if o.id != e.id and not o.dead and o.pos.distance_to(b.pos) < b.aoe + o.r:
						g.combat.damage(o, b.dmg)
			if b.has("fx_col") or not g._fx_sprite("fx_arcane_hit", e.pos):
				g.fx.append({"kind": "ring", "pos": e.pos, "r": 22.0, "life": 0.25, "max": 0.25, "col": b.get("fx_col", Color(0.8, 0.45, 1.0))})
			g._sparks(e.pos, b.vel, b.get("fx_col", Color(0.85, 0.5, 1.0)), 3, 160.0)
			if b.has("op"):
				Sfx.op(b.op, "hit")   # 铃兰狐火
			b.life = 0.0
		"tide":
			# 潮汐弹：在敌人之间反弹
			g.combat.damage(e, b.dmg)
			if b.get("push", false) and not e.boss and not e.dead:
				e.kb += b.vel.normalized() * 220.0
			if not g._fx_sprite("fx_tide_hit", e.pos):
				g.fx.append({"kind": "ring", "pos": e.pos, "r": 20.0, "life": 0.25, "max": 0.25, "col": Color(0.45, 0.8, 1.0)})
			g._sparks(e.pos, b.vel, Color(0.6, 0.9, 1.0), 2, 160.0)
			b.hit[e.id] = true
			b.bounces -= 1
			if b.bounces < 0:
				b.life = 0.0
				return
			var nxt: Dictionary = {}
			var bd := 260.0
			for k in g.enemies_sys.query(e.pos, 260.0):
				var o: Dictionary = g.enemies[k]
				if o.dead or b.hit.has(o.id):
					continue
				var dd: float = o.pos.distance_to(e.pos)
				if dd < bd:
					bd = dd
					nxt = o
			if nxt.is_empty():
				b.life = 0.0
				return
			b.vel = (nxt.pos - b.pos).normalized() * b.vel.length()
			b.life = 1.0
			Sfx.play("pickup", -16.0, 1.8, 0.1)
		_:
			g.combat.damage(e, b.dmg)
			if not g._fx_sprite("fx_bullet_hit", b.pos, g.PX, b.vel.angle()):
				g._sparks(b.pos, b.vel, Color(0.7, 1.0, 1.0), 3, 200.0)
			b.life = 0.0
