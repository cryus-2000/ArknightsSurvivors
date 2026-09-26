extends RefCounted
## 刷怪：按波次表（data/waves.json）和威胁曲线在屏幕外刷怪、刷精英 / 宝箱 / 拟态箱，生成敌人字典。
## 敌人的行为在 enemies/enemy_ai.gd，敌人的逐帧更新仍在 game.gd _update_enemies。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
const MAX_ENEMIES := 450
var horde_mult := 1.0
var horde_chest := false
var next_id := 0
var spawn_acc := 0.0
var next_elite: float = Bal.v("enemy/first_elite", 45.0)   # 首只精英出现时间（balance.json）
var horde_warned := -1.0
var boss_idx := 0
var mid_used: Array = []
var next_chest := 20.0


func _init(game: Game) -> void:
	g = game


func edge_pos() -> Vector2:
	return g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(720.0, 820.0)


func pick_type() -> String:
	var pool: Array = D.THREAT[g.threat].pool
	var pick: String = pool[g.rng.randi() % pool.size()]
	var caps := {"stone": (6 if g.t < 180.0 else (8 if g.t < 420.0 else 12)), "brood": 6, "offspring": 6 if g.t < 420.0 else 10, "spitter": 6, "burrower": 8, "hulk": 2, "ripper": 14}
	if caps.has(pick):
		var ns := 0
		for e in g.enemies:
			if e.type == pick and not e.dead:
				ns += 1
		if ns >= caps[pick]:
			pick = "slider" if g.threat >= 3 else "bone"
	return pick


func pick_elite() -> String:
	var pool: Array = []
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if d.get("role", "") == "elite" and g.t >= float(d.get("elite_after", 0.0)) and not d.get("no_spawn", false):
			pool.append(k)
	if pool.is_empty():
		return "pocket"
	return pool[g.rng.randi() % pool.size()]


func boss_alive() -> bool:
	for b in g.bosses:
		if not b.dead:
			return true
	return false


func update(dt: float) -> void:
	# Boss 按时间登场
	if boss_idx < D.BOSS_TIMES.size() and g.t >= D.BOSS_TIMES[boss_idx]:
		boss_idx += 1
		var group: Array = []
		if boss_idx == D.BOSS_TIMES.size():
			group = [D.ENDINGS[g.ending].boss]
		else:
			var pool: Array = []
			for i in D.MID_POOL.size():
				if not mid_used.has(i) and (boss_idx != 1 or D.MID_FIRST.is_empty() or D.MID_FIRST.has(i)):
					pool.append(i)
			var pick: int = pool[g.rng.randi() % pool.size()]
			if g.force_boss >= 0 and not mid_used.has(g.force_boss):
				pick = g.force_boss
			mid_used.append(pick)
			group = D.MID_POOL[pick]
		var base := edge_pos()
		if g.zone_state != 0 and base.distance_to(g.zone_c) > g.zone_r - 90.0:
			base = g.zone_c + (base - g.zone_c).normalized() * maxf(60.0, g.zone_r - 110.0)
		if boss_idx == D.BOSS_TIMES.size() and group == ["knight_boss"]:
			# 结局二：骑士在原地重生为最终 Boss；若骑士已不在，则从边缘出现
			if g.knight.alive:
				base = g.knight.take_over()
			g._show_banner("寒冰重生 —— 最后的骑士")
		var spawned: Array = []
		for k in group.size():
			var b := spawn_enemy(group[k], base + Vector2(k * 90.0, 0))
			g.bosses.append(b)
			spawned.append(b)
			g.boss = b
		if spawned.size() == 2:
			spawned[0].partner = spawned[1]
			spawned[1].partner = spawned[0]
		if boss_idx == D.BOSS_TIMES.size():
			g.final_boss = spawned[0]
		var names: Array = []
		for g_item in group:
			names.append(D.ENEMIES[g_item].name)
		g._show_banner("%s 出现了" % " 与 ".join(names))
		Sfx.play("roar", 2.0, 0.7, 0.0)
		Sfx.play_overlay("boss_in")
		g._shake(1.2)
	# 威胁等级上升：横幅 + 刷一小波新种类
	if g.threat < D.THREAT.size() - 1 and g.t >= D.THREAT[g.threat + 1].t:
		g.threat += 1
		var tr: Dictionary = D.THREAT[g.threat]
		g._show_banner("威胁上升 · %s —— 新的海嗣浮现" % tr.name)
		Sfx.play("roar", -1.0, 0.75, 0.0)
		g._shake(0.8)
		var fresh: Array = tr.pool.filter(func(x): return not D.THREAT[g.threat - 1].pool.has(x))
		if not fresh.is_empty():
			for k in 6:
				spawn_enemy(fresh[k % fresh.size()], edge_pos())
	var rate := Bal.v("enemy/spawn_base", 1.6) + g.t / Bal.v("enemy/spawn_div", 30.0)
	if boss_alive():
		rate *= 0.8
	if g.lamp < 30.0:
		rate *= 1.15
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if g.enemies.size() < MAX_ENEMIES:
			var ne := spawn_enemy(pick_type(), edge_pos())
			# 6 分钟后一部分海嗣直接以进化体出现（数量不变，质量提升）
			if not ne.elite and ne.ai != "static" and g.rng.randf() < D.THREAT[g.threat].get("evo", 0.0) * (2.0 if g.ending == "deep" else 1.0):
				g._evolve(ne)
			if g.ending == "resolve" and g.t >= 520.0:
				ne.weak = ""
	if g.t >= next_elite:
		next_elite += D.THREAT[g.threat].elite * (0.75 if g.diff >= 4 else 1.0)
		var et := pick_elite()
		spawn_enemy(et, edge_pos())
		if g.rfx.rule("resolve_elite") > 0:
			spawn_enemy(pick_elite(), edge_pos())
		if g.threat >= 4:
			var et2 := pick_elite()
			spawn_enemy(et2, edge_pos())
			g._show_banner("精英「%s」与「%s」同时出现！" % [D.ENEMIES[et].name, D.ENEMIES[et2].name])
		else:
			g._show_banner("精英「%s」出现！击败它获得藏品" % D.ENEMIES[et].name)
		Sfx.play("roar", -3.0)
	# 大群：Boss 在场时顺延（难度 7+ 不顺延）；9:30 之后不再刷（给最终 Boss 留空间）
	var horde_ok: bool = (not boss_alive() or g.diff >= 7) and g.t < 570.0
	if g.t >= g.next_horde - 3.0 and horde_warned != g.next_horde and horde_ok:
		horde_warned = g.next_horde
		g.horde_warn = 3.0
		g.horde_gap = g.rng.randf() * TAU
		Sfx.play("roar", -2.0, 0.55, 0.0)
	if g.t >= g.next_horde and horde_ok:
		g.next_horde += D.THREAT[g.threat].get("horde_every", 120.0)
		g.horde_warn = 0.0
		g.horde_hit = 1.2
		g._shake(1.4)
		g.fx.append({"kind": "horde_ring", "pos": g.ppos, "r": 640.0, "life": 0.9, "max": 0.9, "col": Color(0.75, 0.3, 1.0)})
		Sfx.play("roar", 2.0, 0.8, 0.0)
		# 数量：32 → 88（10 分钟），难度 7+ ×1.4；包围圈留 70° 缺口（预警时的箭头也留出这一侧），给玩家一条突围路线
		var n := int((Bal.v("enemy/horde_base", 24.0) + int(g.t / Bal.v("enemy/horde_div", 9.0))) * horde_mult * (1.4 if g.diff >= 7 else 1.0))
		if horde_chest:
			g._drop(g.ppos + Vector2(70, 0), "chest", 1.0)
		var gap_half := deg_to_rad(35.0)
		var span: float = TAU - gap_half * 2.0
		var hl := {"t": int(g.t), "n": n, "hp": 0.0, "killed": 0, "t80": -1, "minhp": g.hp, "hp0": g.hp, "comp": D.THREAT[g.threat].horde.duplicate()}
		g.horde_log.append(hl)
		for i in n:
			if g.enemies.size() >= MAX_ENEMIES + 60:
				break
			var ang: float = g.horde_gap + gap_half + span * (i + 0.5) / n
			var p := g.ppos + Vector2.from_angle(ang) * g.rng.randf_range(560.0, 640.0)
			var hp_: Array = D.THREAT[g.threat].horde
			var he := spawn_enemy(hp_[i % hp_.size()], p)
			he["horde"] = g.horde_log.size() - 1
			# 群体个体的接触伤害 ×0.7：被包围时不至于两下暴毙，压力来自数量而不是单体
			he.dmg *= 0.7
			hl.hp += he.maxhp
	# 补给箱
	if g.t >= next_chest:
		next_chest = g.t + g.rng.randf_range(35.0, 50.0)
		var nch := 0
		for e in g.enemies:
			if e.chest and e.get("event", "") == "":
				nch += 1
		if nch < 3:
			spawn_chest(g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(260.0, 420.0))
	# 溟痕
	if g.t >= g.next_mire:
		# 溟痕随时间越来越多、越来越大；缩圈后多出现在圈边
		g.next_mire = g.t + g.map.mire_next_interval(g.t)
		var mp := g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(160.0, 380.0)
		if g.zone_state != 0 and g.rng.randf() < 0.6:
			var ang := (g.ppos - g.zone_c).angle() + g.rng.randf_range(-0.8, 0.8)
			mp = g.zone_c + Vector2.from_angle(ang) * (g.zone_r - g.rng.randf_range(20.0, 120.0))
		if g.mires.size() < int(g.map.mire_cfg().get("max_count", 24)):
			g.mires.append(g.map.mire_new(mp, g.t, g.diff >= 8))
	# 商人
	if g.merchant.is_empty() and g.merchant_idx < g.MERCHANT_TIMES.size() and g.t >= g.MERCHANT_TIMES[g.merchant_idx]:
		g.merchant_idx += 1
		g.merchant = {"pos": g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * 260.0, "life": 60.0, "near": false}
		g.shop_items.clear()
		g.shop_refreshed = false
		g._show_banner("商人出现了 —— 去找他交易源石锭")
		Sfx.play("relic", -4.0)


func new_enemy(type: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = D.ENEMIES[type]
	var role: String = d.get("role", "")
	# 生命曲线：前 8 分钟线性到 ×4.4，之后放缓（后期靠进化体与远程比例提升压力，而不是堆血）
	# 曲线参数见 data/balance.json enemy 段（docs/27 §4）
	var hpm := g.enemy_hp_time_mult() * (1.0 + (0.15 if g.diff >= 1 else 0.0) + (0.2 if g.diff >= 10 else 0.0))
	var dmm := (1.0 + (0.15 if g.diff >= 2 else 0.0) + (0.2 if g.diff >= 10 else 0.0))
	var dmg_t := 1.0 + minf(g.t, Bal.v("enemy/dmg_knee", 480.0)) / Bal.v("enemy/dmg_div", 260.0)
	next_id += 1
	var e := {
		"id": next_id, "type": type, "name": d.name, "tex": d.tex, "pos": pos,
		"hp": d.hp * hpm * g.enemy_hp_mult, "maxhp": d.hp * hpm * g.enemy_hp_mult,
		"spd": d.spd * g.rng.randf_range(0.9, 1.1) * D.THREAT[g.threat].get("spd", 1.0), "dmg": d.dmg * dmg_t * dmm * g.enemy_dmg_mult,
		"r": d.r, "r0": d.r, "xp": d.xp, "age": 0.0,
		"evo": false, "elite": role == "elite", "boss": role == "boss", "stun": 0.0,
		"kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": d.ai, "range": d.get("range", 0.0), "cd": d.get("cd", 0.0) * g.enemy_cd_mult, "cdt": g.rng.randf() * d.get("cd", 1.0),
		"corrode": d.get("corrode", 0.0), "nerve": d.get("nerve", 0.0), "def": 1.0, "set_t": 0.0, "set_done": false,
		"chest": false, "hidden": false, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		# 状态字段统一在此初始化（Boss 招式 / 假死 / 冲刺 / 流血），避免各处 get() 默认值不一致
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "burst_w": 0.0, "burst_cd": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		# 贴图变体在生成时查一次，绘制时不再每帧拼字符串
		"tex_move": g.tex.get(d.tex + "_move") != null, "tex_feign": g.tex.get(d.tex + "_feign") != null, "tex_attack": g.tex.get(d.tex + "_attack") != null,
		"tex_charge": g.tex.get(d.tex + "_charge") != null, "tex_death": g.tex.get(d.tex + "_death") != null,
		"weak": d.get("weak", ""),
		"aggro": Vector2.INF, "corr_t": 0.0, "corr_dmg": 0.0,
	}
	if e.elite:
		e.hp *= Bal.v("enemy/elite_hp_mult", 7.0)
		e.maxhp = e.hp
		e.xp *= Bal.v("enemy/elite_xp_mult", 10.0)
		e.dmg *= Bal.v("enemy/elite_dmg_mult", 1.3)
	if e.boss:
		e.hp = d.hp * (1.0 + g.t / Bal.v("enemy/boss_hp_time_div", 600.0)) * (1.15 if g.diff >= 1 else 1.0) * g.enemy_hp_mult
		e.maxhp = e.hp
		e.spd = d.spd
		e.dmg = d.dmg * dmm * (1.25 if g.diff >= 10 else 1.0) * g.enemy_dmg_mult
	if type == "pocket":
		e.burst_at = e.maxhp * 0.85
	if type == "izumik":
		e.hp = e.maxhp * 0.35
		e.invuln = true
	if d.has("ammo"):
		e.ammo = d.ammo
		e.reload_t = 20.0
		e.channel = 0.0
	return e


func spawn_enemy(type: String, pos: Vector2) -> Dictionary:
	var e := new_enemy(type, pos)
	g.enemies.append(e)
	return e


## 补给箱；约 15% 是伪装的箱形恐鱼
func spawn_chest(pos: Vector2, event_id := "") -> void:
	next_id += 1
	g.enemies.append({
		"id": next_id, "type": "chest", "name": "补给箱" if event_id == "" else "海嗣祭坛", "tex": "e_chest" if event_id == "" else "e_event", "pos": pos, "hp": 22.0, "maxhp": 22.0,
		"event": event_id,
		"spd": 0.0, "dmg": 0.0, "r": 13.0, "r0": 13.0, "xp": 0.0, "age": 0.0, "evo": false, "elite": false, "boss": false,
		"stun": 0.0, "kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": "static", "range": 0.0, "cd": 0.0, "cdt": 0.0, "corrode": 0.0, "nerve": 0.0, "def": 1.0, "set_t": 0.0, "set_done": true,
		"chest": true, "hidden": event_id == "" and g.rng.randf() < 0.15, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "burst_w": 0.0, "burst_cd": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		"tex_move": false, "tex_feign": false, "tex_attack": false, "tex_charge": false, "tex_death": false,
	})


## 箱形恐鱼现形
func reveal_mimic(e: Dictionary) -> void:
	var m := new_enemy("mimic", e.pos)
	for k in m.keys():
		if k != "id":
			e[k] = m[k]
	e.flash = 0.2
	g._show_banner("箱形恐鱼！")
	g._add_text(e.pos + Vector2(0, -30), "伪装！", UI.RED, 20)
	Sfx.play("roar", -2.0, 1.3)
	g._shake(0.6)
	g._sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 14, 260.0)
