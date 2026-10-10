## 伊祖米克（type izumik，docs/38 §2.6 / §8.7）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
extends "res://scripts/enemies/bosses/boss_base.gd"


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, _dir: Vector2, _dist: float, ready: bool, _mate) -> void:
	if e.phase == 1:
		# 学习阶段（docs/38 §8.7）：固定 boss/izumik_learn（20）秒，无敌；血条从 35% 匀速涨到 100% 只是演出；子代回到本体被吸收 = 强化层数
		if not e.has("learn_t"):
			e.learn_t = Bal.v("boss/izumik_learn", 20.0)
			e.count_end = g.t + e.learn_t
			e.count_max = e.learn_t
		e.learn_t -= dt
		var lk: float = 1.0 - clampf(e.learn_t / maxf(1.0, e.count_max), 0.0, 1.0)
		e.hp = e.maxhp * (0.35 + 0.65 * lk)
		if e.bt > 4.0 * SKILL_COOLDOWN_SCALE:
			e.bt = 0.0
			for k in 2:
				var o: Dictionary = g.spawner.spawn_enemy("offspring", g.combat.arena_clamp(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * 140.0))
				o.feed = true
				o.feed_to = e
				o.spd = 45.0
		if e.learn_t <= 0.0:
			e.phase = 2
			e.invuln = false
			e.bt = 0.0
			e.hp = e.maxhp
			e.act_t = 0.0
			e.count_end = 0.0
			e.dmg *= pow(1.0 + Bal.v("boss/izumik_layer_dmg", 0.08), int(e.get("izu_layers", 0)))
			_izumik_lamps(e)
			Sfx.play_cue("phase", e.type, "start")
			g.vfx.show_banner("伊祖米克进入「解读阶段」！")
			Sfx.play("roar", 0.0, 0.8, 0.0)
			g.vfx.shake_screen(1.0)
	else:
		# 解读阶段（docs/38 §8.7）：灯柱 + 全场地波（取代原来每 7 秒的冲击波）
		_izumik_lamp_step(e, dt)
		var gp: int = int(e.get("gates_passed", 0))
		if gp >= 1 and not e.has("wave_next"):
			e.wave_next = g.t + 0.8   # 66% 卡点后先安静 0.8 秒
		if ready and gp >= 1 and g.t >= float(e.get("wave_next", INF)):
			var cd: float = Bal.v("boss/izumik_wave_cd2", 20.0) if gp >= 2 else Bal.v("boss/izumik_wave_cd", 25.0)
			var wt: float = Bal.v("boss/izumik_wave_charge", 2.0)
			e.wave_next = g.t + wt + cd
			Sfx.play("izu_wave_count", 0.7, 2.0 / maxf(wt, 0.5), 0.0)   # 地波读秒：文件 2 秒，按蓄力时长 wt 变速，结束正好落在结算
			_warn(e, "circle", wt, {"follow": true, "r": 2400.0, "act": "izu_wave", "name": "全场地波", "must_dash": true, "col": Color(0.5, 1.0, 0.7),
				"dmg": minf(e.dmg * 2.0, g.max_hp * Bal.v("boss/izumik_wave_cap", 0.25))})
			Sfx.play("skill", -2.0, 0.6)


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	e.phase = 2
	e.hp = e.maxhp
	e.invuln = false
	e.bt = 0.0


## ---- 伊祖米克（docs/38 §8.7）
## 吸收子代：强化层数 +1（最多 izumik_layer_max 层，每层解读阶段伤害 +izumik_layer_dmg）；借鉴项（docs/49 §5.2）：
## 每吸收一只学习期缩短 boss/izumik_absorb_cut 秒（缺省 0 = 不缩短）
func izumik_absorb(e: Dictionary) -> void:
	Sfx.play("izu_absorb", -9.5, 1.0, 0.0)   # 吸收子代
	e.izu_layers = mini(int(e.get("izu_layers", 0)) + 1, int(Bal.v("boss/izumik_layer_max", 5.0)))
	var cut: float = Bal.v("boss/izumik_absorb_cut", 0.0)
	if cut > 0.0 and e.has("learn_t"):
		e.learn_t -= cut
		e.count_end -= cut
	g.vfx.add_text(e.pos + Vector2(0, -50), "吸收 · 强化 %d" % e.izu_layers, Color(0.5, 1.0, 0.6), 16)


## 灯柱：解读阶段开始时在本体周围 220–300 处立 3 根（限制在场地内）。主控靠近 izumik_lamp_touch 内待 1 秒点亮；
## 点亮后形成 izumik_lamp_r（120）光圈：主控在里面每秒 +2 灯火、躲得开全场地波；子代进光圈减速
func _izumik_lamps(e: Dictionary) -> void:
	e.lamp_r = Bal.v("boss/izumik_lamp_r", 120.0)
	e.lamps = []
	var a0: float = g.rng.randf() * TAU
	for k in 3:
		var p: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(a0 + TAU * k / 3.0) * g.rng.randf_range(220.0, 300.0), 90.0)
		e.lamps.append({"pos": p, "lit": false, "prog": 0.0})


func _izumik_lamp_step(e: Dictionary, dt: float) -> void:
	var touch: float = Bal.v("boss/izumik_lamp_touch", 40.0)
	for l in e.get("lamps", []):
		if not l.lit:
			if g.ppos.distance_to(l.pos) < touch:
				l.prog += dt
				if l.prog >= 1.0:
					l.lit = true
					g.fx.append({"kind": "ring", "pos": l.pos, "r": e.lamp_r, "life": 0.6, "max": 0.6, "col": Color(1.4, 1.1, 0.5), "enemy": true})
					g.vfx.add_text(l.pos + Vector2(0, -40), "灯柱点亮", Color(1.0, 0.85, 0.4), 16)
					Sfx.play("izu_lamp_lit", -4.0, 1.0, 0.0)
			else:
				l.prog = maxf(0.0, l.prog - dt)
			continue
		if g.combat.ground_d(g.ppos, l.pos) < e.lamp_r:
			g.lamp = minf(g.lamp_cap, g.lamp + 2.0 * dt)
		for j in g.enemies_sys.query(l.pos, e.lamp_r):
			var o: Dictionary = g.enemies[j]
			if o.type == "offspring" and not o.dead:
				o.slow = maxf(o.slow, 0.2)


func izumik_safe(e: Dictionary) -> bool:
	for l in e.get("lamps", []):
		if l.lit and g.combat.ground_d(g.ppos, l.pos) < float(e.get("lamp_r", 120.0)):
			return true
	return false
