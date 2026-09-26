extends RefCounted
## 敌人的逐帧更新：移动 / 攻击调度（行为细节在 enemies/enemy_ai.gd、Boss 在 boss_ai.gd）、状态与形态变化、敌方抛射物与弹幕；
## 空间网格与索敌查询（query / nearest / arc_hit / densest_point，干员经 characters/op_api.gd 调用）。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
const CELL := 48.0
var evo_age := 35.0
var evo_xp := 2.0
var seed_heal := false
var mire_tick := 0.0


func _init(game: Game) -> void:
	g = game


func build_grid() -> void:
	g.grid.clear()
	for i in g.enemies.size():
		var e: Dictionary = g.enemies[i]
		if e.dead:
			continue
		var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		if g.grid.has(k):
			g.grid[k].append(i)
		else:
			g.grid[k] = [i]


func query(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var x0 := floori((pos.x - radius) / CELL)
	var x1 := floori((pos.x + radius) / CELL)
	var y0 := floori((pos.y - radius) / CELL)
	var y1 := floori((pos.y + radius) / CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var k := Vector2i(cx, cy)
			if g.grid.has(k):
				out.append_array(g.grid[k])
	if out.size() > 0 and out.max() >= g.enemies.size():
		out = out.filter(func(j): return j < g.enemies.size())
	return out


func update(dt: float) -> void:
	var dark_mod := 1.2 if g.lamp < 30.0 else 1.0
	for i in g.enemies.size():
		var e: Dictionary = g.enemies[i]
		if e.dead:
			continue
		e.age += dt
		e.flash -= dt
		e.jhit -= dt
		e.stun -= dt / g.control_mult
		# 韧性钩子（docs/38 §1.5）：白名单 Boss 身上的眩晕一定来自玩家一方（Boss 自己的硬直写 break_t），换成韧性后清零，不会被锁死
		if e.boss and e.stun > 0.0 and g.combat.tough_on(e):
			g.combat.add_tough(e, e.stun * Bal.v("boss/tough_per_stun", 5.0))
			e.stun = 0.0
		e.squash -= dt
		e.slow -= dt / g.control_mult
		if e.get("wind", 0.0) > 0.0:
			e.wind -= dt
		if e.get("pose", 0.0) > 0.0:
			e.pose -= dt
		if e.get("haste", 0.0) > 0.0:
			e.haste -= dt
		if e.get("aura_weak", 0.0) > 0.0:
			e.aura_weak -= dt
		if e.get("lit", 0.0) > 0.0:
			e.lit -= dt
		if e.get("requiem", 0.0) > 0.0:
			e.requiem -= dt
		# 流血（狙击干员）：每 0.5 秒结算一次
		if e.get("bleed", 0.0) > 0.0:
			e.bleed -= dt
			e["bleed_t"] = e.get("bleed_t", 0.0) + dt
			if e.bleed_t >= 0.5:
				e.bleed_t = 0.0
				g.combat.hit("援护")
				g.combat.damage(e, e.bleed_dps * 0.5)
				g.fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-6, 6), -4), "vel": Vector2(0, 60), "sz": 2.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.05, 0.1)})
				if e.dead:
					continue
		# 侵蚀（排异·无解困境）：受控敌人每 0.5 秒受一次触手法术伤害
		if e.get("corr_t", 0.0) > 0.0:
			e.corr_t -= dt
			e["corr_tick"] = e.get("corr_tick", 0.0) + dt
			if e.corr_tick >= 0.5:
				e.corr_tick = 0.0
				g.combat.hit("触手", ["corrode"])
				g.combat.damage(e, e.corr_dmg)
				g.fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-8, 8), -6), "vel": Vector2(0, -40), "sz": 2.5, "life": 0.45, "max": 0.45, "col": Color(1.2, 0.6, 1.6)})
				if e.dead:
					continue
		var to: Vector2 = g.ppos - e.pos
		var dist := to.length()
		var dir: Vector2 = to / max(dist, 0.001)
		if abs(dir.x) > 0.1 and e.ai != "static":
			e.fx = sign(dir.x)

		if e.chest:
			if dist > 1500.0:
				e.dead = true
			continue
		if dist > 1300.0 and not e.boss:
			if e.ai == "static" or e.get("dormant", false):
				e.dead = true
			else:
				e.pos = g.spawner.edge_pos()
			continue

		if not e.evo and not e.elite and not e.boss and e.ai != "static" and e.age > evo_age * maxf(0.55, 1.0 - g.t / 900.0):
			evolve(e)

		# 注亡拟嗣：生命持续流失
		if e.type == "brood":
			e.hp -= e.maxhp * 0.08 * dt
			if e.hp <= 0.0:
				e.dead = true
				continue
		if e.boss:
			g.bai._boss_ai(e, dt, dir, dist)
		if e.dead:
			continue

		# ---- 移动
		var v: Vector2 = e.kb * (0.3 if D.ENEMIES[e.type].get("heavy", false) else 1.0)
		var spd: float = e.spd * dark_mod * (0.65 if e.slow > 0.0 else 1.0)
		if e.get("channel", 0.0) > 0.0 or e.get("coma", false) or e.get("wind", 0.0) > 0.0 or e.get("dormant", false) or e.get("wake_t", 0.0) > 0.0:
			spd = 0.0
		if e.get("haste", 0.0) > 0.0:
			spd *= 1.4
		var move_dir := dir
		if e.feed and final_target_valid(e):
			move_dir = (e.feed_to.pos - e.pos).normalized()
		elif e.get("aggro", Vector2.INF) != Vector2.INF:
			# 海嗣分身吸引仇恨：本帧朝分身走（每帧由分身重新标记）
			move_dir = (e.aggro - e.pos).normalized()
			e.aggro = Vector2.INF
		var ov: Vector2 = g.eai.pattern(e, dir, dist, dt, spd) if e.stun <= 0.0 else Vector2.INF
		if ov != Vector2.INF:
			v += ov
		elif e.stun <= 0.0:
			match e.ai:
				"melee":
					v += move_dir * spd
				"ranged":
					e.set_t -= dt
					if e.get("hover", false) == false and D.ENEMIES[e.type].get("entrench", false) and not e.set_done and dist < e.range:
						# 固海凿石者：首次接敌时原地架起，大幅提高防御
						e.set_done = true
						e.set_t = 20.0
						e.weak = "法术"
						g.vfx.add_text(e.pos + Vector2(0, -24), "架起 · 法术弱点", Color(0.75, 0.8, 0.9), 14)
					if e.set_t > 0.0:
						pass
					elif dist > e.range * 0.85:
						v += dir * spd
					if e.set_t <= 0.0 and e.set_done:
						e.weak = D.ENEMIES[e.type].get("weak", "")
					e.cdt -= dt
					if spd > 0.0 and dist < e.range and e.cdt <= 0.0:
						e.cdt = e.cd
						g.eai.shoot(e, dir)
		e.kb = e.kb.move_toward(Vector2.ZERO, 900.0 * dt)

		# ---- 分离 + 吞噬
		if e.ai != "static":
			for j in query(e.pos, e.r + 20.0):
				if j == i:
					continue
				var o: Dictionary = g.enemies[j]
				if o.dead:
					continue
				var diff: Vector2 = e.pos - o.pos
				var d := diff.length()
				var min_d: float = e.r + o.r
				if d < min_d and d > 0.01:
					if e.evo and not o.evo and not o.elite and not o.boss and not o.chest and o.ai != "static" and d < e.r and g.rng.randf() < 0.015:
						e.hp += o.hp
						e.maxhp += o.maxhp
						e.r = min(e.r + 1.5, 32.0)
						e.xp += o.xp
						o.dead = true
						g.vfx.add_text(e.pos, "吞噬", Color(1.0, 0.4, 0.5))
						if seed_heal:
							g.combat.heal(g.max_hp * 0.05, "藏品")
						continue
					# 伊祖米克的子代被 Boss 吸收
					if e.feed and o.type == "izumik" and o.phase == 1:
						e.dead = true
						o.hp = min(o.maxhp, o.hp + o.maxhp * 0.08)
						g.vfx.add_text(o.pos + Vector2(0, -50), "吸收", Color(0.5, 1.0, 0.6), 16)
						break
					if not e.boss:
						e.pos += diff / d * (min_d - d) * 0.3
			if e.dead:
				continue
		e.pos += v * dt
		if not e.boss and e.ai != "static" and (i + g.frame_n) % 2 == 0:
			e.pos = g.map.push_out(e.pos, e.r * 0.8)

		# ---- 囊海爬行者：每失去 15% 生命爆发一次。有 0.8 秒鼓胀预警（docs/48 P0-6：原 0.4 秒低于 0.6 下限），爆发之间至少隔 1.2 秒（高输出下不会连爆秒人）
		if e.has("burst_at"):
			e.burst_cd = maxf(0.0, e.get("burst_cd", 0.0) - dt)
			if e.get("burst_w", 0.0) > 0.0:
				e.burst_w -= dt
				if e.burst_w <= 0.0:
					g.fx.append({"kind": "ring", "pos": e.pos, "r": 80.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.45, 1.0)})
					Sfx.play("tentacle", -2.0, 0.7)
					if g.combat.ground_d(g.ppos, e.pos) < 80.0:   # 画即判（§1.9）
						g.in_type = ["近战", "法术"]
						g.combat.enemy_hit(e.dmg * 0.5, {"corrode": 0.0, "nerve": 12.0}, true)
			elif e.hp <= e.burst_at and e.burst_cd <= 0.0:
				e.burst_at -= e.maxhp * 0.15
				e.burst_w = 0.8
				e.burst_cd = 1.2

		# ---- 接触伤害
		# 休眠中的收割者、自爆的狂奔者（V8）没有接触伤害；Boss 登场 2 秒内不造成接触伤害（docs/38 B0 第 6 项：边缘刷出贴脸）
		if e.dmg > 0.0 and (e.ai == "melee" or e.type == "brood") and dist < e.r + 12.0 and not e.get("coma", false) and not e.get("dormant", false) and not D.ENEMIES[e.type].get("no_contact", false) and not (e.boss and e.age < 2.0) and e.get("air", 0.0) <= 0.0 and not e.get("under", false):
			if D.ENEMIES[e.type].get("morph", false):
				morph(e)
				continue
			if g.invuln <= 0.0:
				g.dmg_src = "contact_" + e.type
				g.in_type = ["近战", "物理"]
				# 底海滑动者冲刺撞击：熄灭灯火
				if e.type == "slider" and e.get("dash_t", 0.0) > 0.0:
					g.lamp = maxf(0.0, g.lamp - 8.0)
					g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -8", Color(1.0, 0.6, 0.4), 14)
				if e.type in ["knight", "knight_boss"] and e.get("dash_t", 0.0) > 0.0:
					g.frost = maxf(g.frost, 2.0)
					g.vfx.add_text(g.ppos + Vector2(20, -60), "冰霜", Color(0.7, 0.9, 1.4), 14)
				g.combat.enemy_hit(e.dmg * dark_mod, e)
		# 伊莎玛拉之泪：站在上面持续受到真实伤害（Boss 的机制物件，算 Boss 来源）
		if e.type == "tear" and dist < e.r + 14.0:
			g.combat.lose_hp(6.0 * dt, "tear", true)
			g.hurt_flash = max(g.hurt_flash, 0.05)


func final_target_valid(e: Dictionary) -> bool:
	return e.has("feed_to") and e.feed_to != null and not e.feed_to.dead


## 伊祖米克的子代：碰到水月就蜕变成其他敌人
func morph(e: Dictionary) -> void:
	e.dead = true
	g.fx.append({"kind": "ring", "pos": e.pos, "r": 40.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 1.0, 0.6)})
	g.vfx.add_text(e.pos + Vector2(0, -24), "蜕变", Color(0.6, 1.0, 0.6), 16)
	for k in 2:
		g.spawner.spawn_enemy(["bone", "slider", "stone"][g.rng.randi() % 3], e.pos + Vector2.from_angle(g.rng.randf() * TAU) * 20.0)


func update_lobs(dt: float) -> void:
	for l in g.lobs:
		l.t += dt
		if l.t >= l.dur:
			g.fx.append({"kind": "explode", "pos": l.to, "r": l.r, "life": 0.35, "max": 0.35, "col": Color(0.5, 0.9, 0.5) if l.get("mire", false) else Color(0.8, 0.7, 0.55)})
			if l.get("mire", false) and g.mires.size() < 32:
				g.mires.append({"pos": l.to, "r": 12.0, "maxr": 44.0, "life": 7.0, "seed": g.rng.randf() * 100.0})
			g.vfx.sparks(l.to, Vector2.ZERO, Color(0.75, 0.7, 0.6), 8, 200.0)
			Sfx.play("boom", -14.0, 1.6, 0.1)
			if g.combat.ground_d(g.ppos, l.to) < l.r and g.invuln <= 0.0:   # 画即判（§1.9）
				g.dmg_src = "bullet"
				g.in_type = ["远程", "法术"]
				g.combat.enemy_hit(l.dmg * Bal.v("enemy/bullet_dmg_mult", 1.0), {})
	g.lobs = g.lobs.filter(func(l): return l.t < l.dur)


func update_ebullets(dt: float) -> void:
	update_lobs(dt)
	for b in g.ebullets:
		if b.life <= 0.0:
			continue
		if b.get("home", false):
			var want: Vector2 = (g.ppos + Vector2(0, -14) - b.pos).normalized() * b.vel.length()
			b.vel = b.vel.lerp(want, clampf(dt * 1.6, 0.0, 1.0))
		b.pos += b.vel * dt
		b.life -= dt
		var hitp: bool = b.pos.distance_to(g.ppos + Vector2(0, -14)) < b.r + 12.0
		if b.get("mire", false) and (hitp or b.life <= 0.0) and g.mires.size() < 32:
			g.mires.append({"pos": b.pos + Vector2(0, 10), "r": 10.0, "maxr": 52.0, "life": 10.0, "seed": g.rng.randf() * 100.0, "boss": b.get("boss", false)})
		if hitp:
			b.life = 0.0
			if b.get("slow", false) and not g.combat.atk_slow_as_slow(3.0, b.get("boss", false)):   # Boss 来源不写 atk_slow（docs/38 §1.11）
				g.atk_slow = 3.0
			g.dmg_src = "bullet"
			g.in_type = ["远程", "真实" if b["true"] else b.get("atk", "法术")]
			if g.invuln <= 0.0:
				g.combat.enemy_hit(b.dmg * Bal.v("enemy/bullet_dmg_mult", 1.0), b, b["true"])


## 玩家身上的持续状态：侵蚀掉血、神经损伤衰减、溟痕
func update_status(dt: float) -> void:
	g.combat.update_ctrl(dt)   # 主控减速计时；Boss 战中僵直恒为 0（docs/38 §1.11）
	g.pstun -= dt
	g.atk_slow -= dt
	g.frost = maxf(0.0, g.frost - dt)
	g.nerve = max(0.0, g.nerve - 6.0 * dt)
	if g.corrode_pool > 0.0:
		var tick: float = min(g.corrode_pool, (g.corrode_pool * 0.5 + 1.0) * dt)
		g.combat.drain_corrode(tick)
	var mired := false
	var mire_nat := false   # 站在自然溟痕里（不是 Boss 子弹留下的）：这一跳不算 Boss 来源
	var sanct: bool = g.squad.in_sanctuary(g.ppos)   # 流明灯塔：区内溟痕失效
	for m in g.mires:
		m.life -= dt
		m.r = min(m.maxr, m.r + 5.0 * dt)
		if g.combat.ground_d(g.ppos, m.pos) < m.r and not sanct:
			mired = true
			if not m.get("boss", false):
				mire_nat = true
	# 溟痕：减速 + 屏幕变暗 + 持续掉血（2.5/秒）+ 神经损伤
	g.in_mire = move_toward(g.in_mire, 1.0 if mired else 0.0, dt * (4.0 if mired else 2.5))
	if mired:
		# 溟痕侵蚀：每 0.5 秒结算一次（3 + 1.5% 最大生命），带飘字与轻微红闪
		mire_tick -= dt
		if mire_tick <= 0.0:
			mire_tick = 0.5
			# 溟痕每跳（0.5 秒）伤害：balance.json 的 enemy/mire_flat + 最大生命 × enemy/mire_pct，再乘难度修正 mire_dmg（缺省与原来相同）
			var md: float = (Bal.v("enemy/mire_flat", 3.0) + g.max_hp * Bal.v("enemy/mire_pct", 0.015)) * float(g.dmod.get("mire_dmg", 1.0))
			md = g.combat.lose_hp(md, "mire", not mire_nat)
			if md >= 1.0:   # Boss 溟痕这一跳被持续伤害上限截到不足 1 点时不闪、不飘「-0」（自然溟痕每跳 ≥3，照旧）
				g.red_flash = maxf(g.red_flash, 0.08)
				g.hp_shake = 0.2
				g.hurt_flash = maxf(g.hurt_flash, 0.06)
				g.vfx.add_text(g.ppos + Vector2(randf_range(-10, 10), -80), "-%d 溟痕" % int(md), Color(0.85, 0.45, 1.0), 15)
		g.head_bar_t = maxf(g.head_bar_t, 0.6)
	else:
		mire_tick = 0.0
	g.mires = g.mires.filter(func(m): return m.life > 0.0)
	for s in g.shocks:
		s.r += 320.0 * dt
		# 冲击环：环带宽 22，按地面椭圆算，且不超过最大半径（= 预警圈，docs/38 B0 第 5 项、docs/48 P0-1）
		var sd: float = g.combat.ground_d(g.ppos, s.pos)
		if not s.hit and absf(sd - s.r) < 22.0 and sd <= s.maxr:
			s.hit = true
			if g.invuln <= 0.0:
				if not g.combat.stun_as_slow(s.get("boss", false)):   # Boss 战里僵直改成减速（docs/38 §1.11）
					g.pstun = max(g.pstun, 0.5)
				g.dmg_src = "shock"
				g.in_type = ["近战", "物理"]
				g.combat.enemy_hit(s.dmg, {"boss": s.get("boss", false)}, true, true)   # 冲击环的 boss 标记由放招的敌人决定（boss_ai.gd）
	g.shocks = g.shocks.filter(func(s): return s.r < s.maxr)


func evolve(e: Dictionary) -> void:
	e.evo = true
	e.maxhp *= 1.8
	e.hp = e.maxhp
	e.r *= 1.3
	e.spd *= 1.15
	e.dmg *= 1.5
	e.xp *= evo_xp
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.3, 0.4)})


func nearest(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	if origin == Vector2.INF:
		origin = g.ppos
	var c: Array = []
	for j in query(origin, max_dist):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var d: float = e.pos.distance_squared_to(origin)
		if d < max_dist * max_dist:
			c.append([d, e])
	c.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in min(n, c.size()):
		out.append(c[i][1])
	return out


## 扇形判定：返回 origin 周围 radius 内、与 ang 夹角不超过 half 的敌人
func arc_hit(origin: Vector2, ang: float, half: float, radius: float) -> Array:
	var out: Array = []
	for j in query(origin, radius + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var off: Vector2 = e.pos - origin
		if off.length() > radius + e.r:
			continue
		if half < PI and abs(angle_difference(ang, off.angle())) > half + 0.15:
			continue
		out.append(e)
	return out


## 敌人最密集的位置（在 radius 内采样）
func densest_point(radius: float, origin: Vector2 = Vector2.INF) -> Vector2:
	var best := Vector2.INF
	var bn := 0
	var cand := nearest(12, radius, origin)
	for c in cand:
		var n := 0
		for j in query(c.pos, 90.0):
			if not g.enemies[j].dead and g.enemies[j].pos.distance_to(c.pos) < 90.0:
				n += 1
		if n > bn:
			bn = n
			best = c.pos
	return best
