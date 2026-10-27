## 伊莎玛拉（type ishar，docs/38 §2.5 / §8.6；变身后招式改版 docs/95 §2，10-14）；一阶段由 run/ishar_encounter.gd 负责
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 变身后 4 招固定轮转：A 三点落击（①）→ B 三线扫射（②，逐条锁定）→ C 大群之歌（④ 双缺口扩散环，真伤）→ D 撕咬 / 横扫（③；66% 卡点后「濒死强化」2 段）
## 人形 / 抗争之泪 / 压制 / 变身 / 泪滴共鸣 / 潮涌迫近是机制，不动（用户 10-14 定）
## 主轴「破网」（docs/142b §3.6 / §8.2，10-25；取材 PRTS「她不再歌唱，它为大群发声」、濒死强化召 2 个泪，网本身本作拟）：
##   一幕「大群」：她的歌把海嗣连成网——每只连线海嗣（主轴目标，站到她周围 240 / 300 的一圈上）让她受伤 −10%，最多 ishar_web_cap（6）只；
##     每 ishar_choir_cd（6）秒「召唤合唱」从场边叫来最多 3 只补进空位。三点落击删掉（轮转改 三线扫射 → 大群之歌 → 撕咬）
##   二幕「濒死强化」：落下 2 个泪（歌眼，主轴目标）——泪在场时网上限 ishar_web_cap2（10），断掉的线 ishar_relink（3）秒后原位接上；
##     每 6 秒泪与她之间「共鸣」直线结算；轮转多一招「泪落」（两泪之间 5 个落点依次落）
##   三幕「回声」：被拆掉的连线海嗣 1.0 秒后原地爆开一个音圈；三线扫射分锁队长与两名队友，之后 2 秒不出招；大群之歌两圈先后扩散
extends "res://scripts/enemies/bosses/boss_base.gd"

const COL := Color(0.3, 1.0, 0.65)   # 青绿（docs/142b §8.4）
const MOVES := ["泪落", "三线扫射", "大群之歌", "撕咬"]   # 下标 = 轮转序号；泪落只在二幕有泪时进轮转
## 10-27 连段（docs/170）：二阶段改由 ishar_combos.gd 按幕出有限连段 + 图案弹幕；boss/ishar_combos 0 = 回到旧的固定轮转（云端对照用）
const Cards = preload("res://scripts/enemies/bosses/ishar_combos.gd")
var _cards


func cards():
	if _cards == null:
		_cards = Cards.new(g, self)
	return _cards


func cards_on() -> bool:
	return Bal.v("boss/ishar_combos", 1.0) > 0.0


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# P1 治疗海嗣和充能由 IsharEncounter 负责；这里仅调度敌对海嗣形态。
	if e.phase == 2 and _enraged(e) and not e.has("tint2"):
		_tint2(e, Color(1.18, 0.86, 0.9))   # 濒死强化：本体加红色着色（docs/95 §2.2 D）
	if e.phase == 2 and g.t >= float(e.get("transform_until", 0.0)):
		_web_step(e, dt)
		_eye_step(e)
	if e.phase == 2 and g.t >= float(e.get("transform_until", 0.0)):
		if cards_on():
			cards().step(e, dir, dist, ready)
		elif ready:
			_ishar_phase2(e, dir, dist)



## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	transform_ishar(e)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES + g.bai.finals.NAMES["ishar"] + Cards.NEW_MOVES + Cards.card_names()


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if g.bai.finals.force_move(e, name, dir, dist):
		if cards_on():
			e.final_next = INF
		return true
	if e.phase != 2:
		return false
	if cards().force(e, name):
		return true
	if Cards.NEW_MOVES.has(name):
		cards().play(e, name, dir, dist)
		return true
	var i: int = MOVES.find(name)
	if i < 0:
		return false
	e.tear_echoes = []
	e.ishar_cycle = i
	e.force_cycle = true
	e.ishar_next_at = g.t
	e.cds = {"ishar_close": g.t + 100.0}   # 验收只看轮转招，不让迫近插队
	_ishar_phase2(e, dir, minf(dist, 180.0) if name == "撕咬" else dist)
	return true


## 以原作「三目标真实伤害」为基础的幸存者玩法改编。固定轮转避免近身招式永久压住远程招式。
func _ishar_phase2(e: Dictionary, dir: Vector2, dist: float, forced := -1) -> void:
	var d: Dictionary = D.ENEMIES.ishar.get("attack", {})
	var move: int = forced
	var end := 0.0
	if forced < 0:
		# 潮涌迫近（协调人 9/30 定，见 _close_in）：原来她站在 660 射程边上、躲在杂兵墙后，近战队伍打不到（Boss A/B 9/30：高手用时中位 199 秒、15/50 没打死）
		if g.t >= float(e.get("ishar_next_at", 0.0)):
			var cdur := _close_in(e, dir, dist, "ishar", "潮涌迫近", COL)
			if cdur >= 0.0:
				e.ishar_next_at = g.t + cdur + 0.6
				return
		if dist > float(d.get("range", 660.0)) or g.t < float(e.get("ishar_next_at", 0.0)):
			return
		move = int(e.get("ishar_cycle", 0)) % 4
		if _fire_echoes(e):
			return
		if move == 0 and not e.get("force_cycle", false) and e.get("eyes", []).size() < 2:
			move = 1   # 泪落只在二幕两泪都在时进轮转（演练强制出招除外）
		e.force_cycle = false
		e.ishar_cycle = (move + 1) % 4
	var enraged: bool = _enraged(e)
	var act3: bool = int(e.get("gates_passed", 0)) >= 2
	var pause: float = 0.0
	match move:
		0:
			# 泪落（二幕，docs/142b §8.2「拦路」）：两泪之间的连线上 5 个落点 r48，依次落（每个晚 0.22 秒，首个 0.9 秒）；e.dmg × 0.6 真伤 / 圈。
			# 没有两泪（演练）时落在主控身前横排
			var eyes: Array = e.get("eyes", [])
			var a: Vector2 = eyes[0].pos if eyes.size() >= 2 else g.ppos - dir.orthogonal() * 220.0
			var b: Vector2 = eyes[1].pos if eyes.size() >= 2 else g.ppos + dir.orthogonal() * 220.0
			for k in 7:   # 10-25 加密：原 5 个、e.dmg × 0.6
				var pos: Vector2 = g.combat.arena_clamp(a.lerp(b, (float(k) + 0.5) / 7.0), 60.0)
				var w := _warn(e, "circle", 0.9 + 0.16 * k, {"pos": pos, "r": 48.0, "act": "ishar_strike", "true": true, "seq_no": k + 1,
					"name": "泪落" if k == 0 else "", "col": COL, "dmg": e.dmg * 0.47, "cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		1:
			# B · 三线扫射：三条 660 × 14 条纹线，夹角 0.38；逐条锁定（第 1 条 0.3 秒、之后各晚 0.15 秒），同时结算；每条锁定 ≥0.4；e.dmg × 0.7 真伤 / 线。
			# Kanpelle 青绿光束（§8.5）。三幕「分锁三人」：第 2、3 条改瞄两名队友（没有就照旧张开），之后 2 秒不出招（§8.2「定拍」：拆网的空档）
			# 10-25 用户「三条激光都要瞄准人打」：出招时锁定主控位置，4 条从本体两侧出发、都穿过锁定点（_aim_fan），之后不再转向；原来扇形张开 line_spread
			var fan: Array = _aim_fan(e, 4, float(d.get("range", 660.0)))
			var aims: Array = fan.map(func(f): return f.ang)
			if act3:
				var n := 1
				for o in g.squad.ops:
					if n >= 3:
						break
					if not o.is_leader and o.pos != Vector2.INF and o.pos.distance_to(e.pos) > 60.0:
						aims[n] = (o.pos - e.pos).angle()
						fan[n] = {"pos": e.pos, "ang": aims[n], "len": float(d.get("range", 660.0)), "aim_op": o}
						n += 1
				pause = Bal.v("boss/ishar_line_pause", 2.0)
			for k in 4:
				var w := _warn(e, "line", float(d.get("line_warn", 1.0)),
					{"pos": fan[k].pos, "ang": fan[k].ang,
					"len": fan[k].len, "wid": float(d.get("line_width", 14.0)), "track": 0.5, "aim_op": fan[k].get("aim_op"), "seq_no": k + 1,
					"act": "ishar_line", "true": true, "name": "三线扫射" if k == 0 else "", "col": COL, "kp": "ishar", "kp_k": 2.0,
					"dmg": e.dmg * float(d.get("line_mult", 0.7)) * 0.78, "cancel_dead": true, "lock": k == 0})   # ×0.78：10-25 加密
				end = maxf(end, w.dur)
		2:
			# C · 大群之歌（PRTS「她不再歌唱，它为大群发声」，招式名本作拟）：以本体为心 r90 起扩散的声波环（≤220px/s，到 r600 止），
			# 2 个缺口（朝主控 + 对侧），缺口在主控所在距离上弧长 ≥110px（濒死强化后缩到 80px 下限）、灯火 ≥70 加宽 1.5 倍；
			# 缺口提前 0.8 秒画出；环为真实伤害判定、命中一次；e.dmg × 0.9
			var arc: float = Bal.v("boss/ishar_song_gap_px", 110.0) if not enraged else 80.0
			if g.lamp >= 70.0:
				arc *= 1.5
			var gh: float = clampf(arc * 0.5 / maxf(dist, 90.0), 0.12, 1.0)
			var smult: float = Bal.v("boss/ishar_song_mult", 0.7)   # 原 0.9（10-25 加密 ×0.78）
			var w := _warn(e, "circle", 0.8, {"r": 90.0, "act": "song_ring", "gaps": [dir.angle(), dir.angle() + PI], "gap_half": gh,
				"maxr": 600.0, "spd": Bal.v("boss/ishar_song_spd", 220.0), "true": true, "name": "大群之歌", "col": COL,
				"dmg": e.dmg * smult, "cancel_dead": true})
			end = w.dur
			# 连续声波：普通三圈、末幕四圈，后续每秒一圈，缺口逐次转 0.28 弧度；避免突然转 90°，缩小贯穿整轮的共同安全方向。
			for q in (3 if act3 else 2):
				var ga: float = dir.angle() + 0.28 * float(q + 1)
				var w2 := _warn(e, "circle", 1.8 + 1.0 * q, {"r": 90.0, "act": "song_ring", "gaps": [ga, ga + PI], "gap_half": gh,
					"maxr": 600.0, "spd": Bal.v("boss/ishar_song_spd", 220.0), "true": true, "name": "", "col": COL,
					"dmg": e.dmg * smult, "cancel_dead": true, "lock": false})
				end = maxf(end, w2.dur)
		3:
			# D · 撕咬（近，半角 0.85、r190）/ 横扫（远，半角 0.46、r 到主控 +40 ≤660）：暗填扇形，追踪 0.3；e.dmg × 0.9 真伤。
			# 濒死强化（66% 卡点后）：2 段（第 2 段 0.6 秒后、方向镜像），每段 ×1.125
			var near: bool = dist < float(d.get("bite_range", 190.0))
			var segs: int = 2 if enraged else 1
			var mult: float = float(d.get("maw_mult", 0.9)) * (1.125 if enraged else 1.0)
			var mw: float = float(d.get("bite_warn", 1.1)) if near else float(d.get("maw_warn", 0.85))   # 撕咬扇边半宽的一半 72 → 锁定 ≥0.78，总 1.1；横扫 ≥0.55，总 0.85
			for k in segs:
				var w := _warn(e, "cone", mw + 0.6 * k,
					{"ang": dir.angle(), "half": 0.85 if near else 0.46,
					"r": float(d.get("bite_range", 190.0)) if near else minf(dist + 40.0, float(d.get("range", 660.0))),
					"track": 0.3 + 0.6 * k, "act": "bite" if near else "sweep", "true": true, "mirror": k == 1,
					"name": ("撕咬" if near else "横扫") if k == 0 else "", "col": COL,
					"dmg": e.dmg * mult, "cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
	# 完整连段期间停留且不插入普通射击；按经过难度修正后的真实预警长度计时。
	e.wind = maxf(e.wind, end)
	e.cdt = maxf(e.cdt, end)
	e["ishar_next_at"] = g.t + end + pause + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE * _ishar_haste(e)
	e["ishar_pause"] = pause


## 变身前未压制的泪滴齐射一次（锁定一刻的主控位置，各束同时结算）；放了返回 true
func _fire_echoes(e: Dictionary) -> bool:
	var d: Dictionary = D.ENEMIES.ishar.get("attack", {})
	var echoes: Array = e.get("tear_echoes", [])
	if echoes.is_empty():
		return false
	var end := 0.0
	var target: Vector2 = g.combat.arena_clamp(g.ppos, 80.0)
	for eye in echoes:
		if eye.dead:
			continue
		var source: Vector2 = eye.pos
		var to_target: Vector2 = target - source
		var w := _warn(e, "line", 1.0, {"pos": source, "ang": to_target.angle(), "len": to_target.length(),
			"wid": 13.0, "act": "ishar_echo", "true": true, "name": "泪滴共鸣" if is_same(eye, echoes[0]) else "", "kp": "ishar", "kp_k": 2.0,
			"col": COL, "dmg": e.dmg * Bal.v("boss/ishar_echo_mult", 0.6), "cancel_dead": true, "source": eye, "lock": is_same(eye, echoes[0])})
		end = maxf(end, w.dur)
	e.tear_echoes = []
	e.wind = maxf(e.wind, end)
	e.cdt = maxf(e.cdt, end)
	e.ishar_next_at = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE * _ishar_haste(e)
	return true


## 濒死强化（docs/95 §2.2 D）：过第一道卡点（66%）之后
func _enraged(e: Dictionary) -> bool:
	return int(e.get("gates_passed", 0)) >= 1


## 真实形态切换由逻辑记录起始时间，渲染和演练均使用同一个入口。
func transform_ishar(e: Dictionary) -> void:
	if e.phase == 2:
		return
	Sfx.play_cue("phase", e.type, "start")
	e.phase = 2
	e.friendly = false
	e.invuln = false   # 0.9 秒变身免伤由 combat 的 transform_until 护栏控制，不留永久无敌。
	e.ai = "melee"   # 接近主控，但伤害只从有预警的轮转招式结算。
	e["ishar_cycle"] = 0
	e["ishar_next_at"] = g.t + 0.9
	e["tear_echoes"] = []
	e.eyes = []
	e.card_live = false
	e.card_act = -1
	e.ishar_emits = []
	if cards_on():
		e.final_next = INF
	for o in g.enemies:
		if o.type == "tear" and is_same(o.get("owner", {}), e):
			if not o.dead and not o.get("purified", false):
				e.tear_echoes.append(o)
				_make_eye(e, o)
				e.eyes.append(o)
				g.fx.append({"kind": "ring", "pos": o.pos, "r": 34.0, "life": 1.4, "max": 1.4,
					"col": COL, "enemy": true})
				g.fx.append({"kind": "tide_link", "a": o.pos, "b": e.pos, "life": 1.0, "max": 1.0,
					"col": COL, "enemy": true})
			else:
				g.ishar.release_blessing(o)
				o.dead = true
	e.reso_next = g.t + 3.0
	e.dmg *= 1.6
	e.spd = maxf(e.spd, 58.0)
	e.r = 46.0
	e.r0 = 46.0
	e["transform_started"] = g.t
	e["transform_until"] = g.t + 0.9
	e.wind = maxf(e.wind, 0.9)
	e.pose = 0.0
	e.cdt = maxf(e.cdt, 0.9)
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	g.vfx.show_banner("伊莎玛拉 完成了转化！")
	Sfx.play("roar", 2.0, 0.6, 0.0)
	g.vfx.shake_screen(1.2)


## 伊莎玛拉强度上调（docs/38 §8.6）：过了卡点后轮换恢复时间 ×boss/ishar_gate_haste（0.8）
func _ishar_haste(e: Dictionary) -> float:
	return Bal.v("boss/ishar_gate_haste", 0.8) if int(e.get("gates_passed", 0)) >= 1 else 1.0


## ---- 主轴「破网」（docs/142b §3.6）
## 网的空位 e.web（[{o, next}]，数量 = 当前上限）；连线海嗣 = bone / slider 底子，ai static、伤害 0（不追人、无接触伤害、不出额外招），
## part = 主轴目标（自动攻击先打），每帧走向自己的位置（她周围 240 / 300 交错的一圈，每秒 110 像素）
func _web_step(e: Dictionary, dt: float) -> void:
	var eyes: Array = e.get("eyes", [])
	var cap: int = int(Bal.v("boss/ishar_web_cap2", 10.0)) if not eyes.is_empty() else int(Bal.v("boss/ishar_web_cap", 6.0))
	var slots: Array = e.get("web", [])
	while slots.size() < cap:
		slots.append({"o": null, "next": INF})
	var act3: bool = int(e.get("gates_passed", 0)) >= 2
	var live := 0
	for i in slots.size():
		var sl: Dictionary = slots[i]
		var o = sl.o
		if o != null and o.dead:
			if act3 and float(o.hp) <= 0.0:
				_echo_ring(e, o.pos)
			sl.o = null
			sl.next = g.t + Bal.v("boss/ishar_relink", 3.0) if not eyes.is_empty() else INF
			o = null
		if i >= cap:
			if o != null:
				_unlink(o)   # 泪碎了、上限回到 6：多出来的线断开，海嗣照常追人
				sl.o = null
			continue
		if o == null:
			if not eyes.is_empty() and g.t >= float(sl.next):
				sl.o = _web_mob(e, _slot_pos(e, i, cap), i)
				g.fx.append({"kind": "ring", "pos": sl.o.pos, "r": 28.0, "life": 0.4, "max": 0.4, "col": COL, "enemy": true})
			continue
		o.pos = o.pos.move_toward(_slot_pos(e, i, cap), 110.0 * dt)
		o.kb = Vector2.ZERO
		live += 1
	if slots.size() > cap:
		slots.resize(cap)
	e.web = slots
	e.web_n = live
	e.web_cap = cap
	# 召唤合唱：从场边叫来最多 3 只，补进空位（第一次在变身后 1 秒）
	if not e.has("choir_next"):
		e.choir_next = g.t + 1.0
	if g.t >= float(e.choir_next):
		e.choir_next = g.t + Bal.v("boss/ishar_choir_cd", 6.0)
		var n := 0
		for i in cap:
			if n >= 3:
				break
			if slots[i].o == null:
				slots[i].o = _web_mob(e, g.combat.arena_clamp(g.spawner.edge_pos(), 60.0), i)
				n += 1
		if n > 0:
			g.vfx.add_text(e.pos + Vector2(0, -60), "召唤合唱", COL, 16)
			Sfx.play("tentacle", -6.0, 1.2)


func _slot_pos(e: Dictionary, i: int, cap: int) -> Vector2:
	return g.combat.arena_clamp(e.pos + Vector2.from_angle(TAU * i / cap + 0.3) * (240.0 if i % 2 == 0 else 300.0), 60.0)


func _web_mob(e: Dictionary, pos: Vector2, i: int) -> Dictionary:
	var o: Dictionary = g.spawner.spawn_enemy("bone" if i % 2 == 0 else "slider", pos)
	o.web_keep = [o.ai, o.spd, o.dmg]   # 断线（_unlink）时还原
	o.ai = "static"
	o.dmg = 0.0
	o.spd = 0.0
	o.extra_next = INF
	o.web_of = e
	o.part = true
	g.enemies_sys.part_add(o)
	return o


func _unlink(o: Dictionary) -> void:
	o.part = false
	o.erase("web_of")
	var k: Array = o.get("web_keep", ["melee", 60.0, 5.0])
	o.ai = k[0]
	o.spd = float(k[1])
	o.dmg = float(k[2])
	o.extra_next = g.t + 3.0


## 三幕「回声」：被拆掉的连线海嗣原地留一个音圈，1.0 秒后爆开（r60，e.dmg × 0.4 真伤）
func _echo_ring(e: Dictionary, pos: Vector2) -> void:
	_warn(e, "circle", 1.0, {"pos": pos, "r": 60.0, "act": "ishar_strike", "true": true, "name": "", "col": COL,
		"dmg": e.dmg * Bal.v("boss/ishar_echo_ring_mult", 0.4), "cancel_dead": true, "lock": false})


## 二幕「濒死强化」的泪（歌眼）：bone 底子换泪的贴图，血量 = 她最大生命 × ishar_eye_hp（0.025），主轴目标；每 6 秒与她之间「共鸣」直线结算
func _eye_step(e: Dictionary) -> void:
	g.ishar.cleanup_blessings(e)
	var eyes: Array = e.get("eyes", []).filter(func(o): return not o.dead)
	e.eyes = eyes
	if eyes.is_empty() or g.t < float(e.get("reso_next", 0.0)):
		return
	e.reso_next = g.t + Bal.v("boss/ishar_reso_cd", 6.0)
	for o in eyes:
		var v: Vector2 = e.pos - o.pos
		_warn(e, "line", 1.0, {"pos": o.pos, "ang": v.angle(), "len": v.length(), "wid": 13.0, "act": "ishar_echo", "true": true,
			"name": "共鸣" if is_same(o, eyes[0]) else "", "col": COL, "kp": "ishar", "kp_k": 2.0,
			"dmg": e.dmg * Bal.v("boss/ishar_echo_mult", 0.6), "cancel_dead": true, "source": o, "lock": false})


func _eyes_spawn(e: Dictionary) -> void:
	g.ishar.cleanup_blessings(e) # 清理先于过滤：已被敌人列表回收的死亡歌眼仍在 eyes 中。
	g.ensure_enemy_tex("e_tear")
	var eyes: Array = e.get("eyes", []).filter(func(o): return not o.dead)
	var side: Vector2 = (g.ppos - e.pos).normalized().orthogonal() if g.ppos.distance_to(e.pos) > 1.0 else Vector2.RIGHT
	for s in [-1.0, 1.0]:
		if eyes.size() >= 3:
			break
		var o: Dictionary = g.spawner.spawn_enemy("bone", g.combat.arena_clamp(e.pos + side * 380.0 * s, 70.0))
		o.name = "伊莎玛拉之泪"
		o.tex = "e_tear"
		o.tex_move = false
		o.tex_attack = false
		o.tex_charge = false
		o.tex_feign = false
		o.tex_death = false
		o.r = 14.0
		o.r0 = 14.0
		o.xp = 0.0
		o.dmg = 0.0
		o.spd = 0.0
		o.ai = "static"
		o.extra_next = INF
		o.affix = ""
		o.shield_hp = 0.0
		o.maxhp = e.maxhp * Bal.v("boss/ishar_eye_hp", 0.025)
		o.hp = o.maxhp
		o.song_eye = true
		o.part = true
		o["dcs"] = true
		g.enemies_sys.part_add(o)
		eyes.append(o)
		g.fx.append({"kind": "tide_link", "a": e.pos, "b": o.pos, "life": 0.8, "max": 0.8, "col": COL, "enemy": true})
		g.fx.append({"kind": "ring", "pos": o.pos, "r": 40.0, "life": 0.6, "max": 0.6, "col": COL, "enemy": true})
	e.eyes = eyes
	e.reso_next = g.t + 3.0


## 人形留下的泪原地转为可破坏歌眼，不另外复制实体或掉落。
func _make_eye(e: Dictionary, o: Dictionary) -> void:
	o.erase("owner")
	o.type = "bone" # 与阶段歌眼一致，不继承旧敌对泪滴的接触扣血。
	o.friendly = false
	o.invuln = false
	o.ai = "static"
	o.spd = 0.0
	o.dmg = 0.0
	o.xp = 0.0
	o.extra_next = INF
	o.affix = ""
	o.shield_hp = 0.0
	o.maxhp = e.maxhp * Bal.v("boss/ishar_eye_hp", 0.025)
	o.hp = o.maxhp
	o.song_eye = true
	o.part = true
	o["dcs"] = true
	g.enemies_sys.part_add(o)


## 网的减伤：每只连线海嗣 −10%，下限 0.4（6 只；二幕上限 10 只也只到 0.4）
func taken_mult(e: Dictionary) -> float:
	if e.phase != 2:
		return 1.0
	return maxf(Bal.v("boss/ishar_web_floor", 0.4), 1.0 - Bal.v("boss/ishar_web_each", 0.1) * float(e.get("web_n", 0)))


## 过卡点：二幕落泪，三幕回声
func on_gate(e: Dictionary) -> void:
	if e.phase != 2:
		return
	if cards_on():
		cards().on_gate(e)   # 转幕清掉未出的段，下一组按新幕选
	if int(e.get("gates_passed", 0)) == 1:
		_eyes_spawn(e)


## 本体倒下：网与泪一起散
func on_kill(e: Dictionary) -> void:
	e.ishar_emits = []
	e.card_live = false
	for tear in g.ishar.tears(e):
		g.ishar.release_blessing(tear)
		tear.dead = true
	for sl in e.get("web", []):
		if sl.o != null and not sl.o.dead:
			_unlink(sl.o)
	for o in e.get("eyes", []):
		o.dead = true


## ---- 受击钩子（docs/101 B1c，10-15 从 combat.gd 搬来）
## 变身动画保护（transform_until，0.9 秒）：独立计时，结束后无需清理永久无敌标记
func block_damage(e: Dictionary) -> bool:
	return g.t < float(e.get("transform_until", 0.0))
