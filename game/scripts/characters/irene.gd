## 艾丽妮（近卫·剑豪，契约 v2.1，docs/26 第二批）：控制 + 处决。刺剑直线穿刺一列敌人，每次两段；唯一会把敌人打浮空的干员。
## S1 疾风：下一次刺击命中的第一个敌人浮空 1 秒，落下时补一刺（两段各 ×1.6）；
## S2 碎潮：前方锥形斩击最多 8 名 ×2.8，浮空 2 秒（精英 1 秒，Boss 不浮空）；
## S3 审判（照原作「判决」，2026-09-26）：冲击波掀起周身 r160 全部敌人 ×1.9 并浮空 4 秒，随后她转着身用手炮向四周连射 12 发，
## 每发打随机目标周围小范围 ×1.55（原作 300% / 250% 的比例，总伤害与旧版持平），优先打浮空目标。
## 天赋 涤罪之焰：对浮空 / 眩晕 / 束缚（slow）中的敌人伤害 +30%。
## 可见成长（docs/25 §5.2，审判庭司法词）：N1 再审：刺击 3 段；N2 严律：刺击更长（+25%）更宽（+40%）；
## N4 卷风：疾风浮空的目标卷起身边 70 内的敌人；N5 二度裂潮：碎潮 0.35 秒后再斩一次（80%）；
## 精二「追诉」：刺中浮空 / 被她控住的敌人时追加一发手炮（手炮一发的 60%，0.4 秒一次）。
## 浮空 = e.stun + e.air（Boss 跳跃已在用的高度字段，game.gd 绘制时按 air 抬高），本脚本每帧写一条 sin 弧线；不改 game.gd。
extends "res://scripts/characters/character.gd"

const PINK := Color(0.95, 0.6, 0.8)
const SILVER := Color(0.9, 0.92, 1.0)
const LAMP := Color(1.0, 0.85, 0.5)
const LEASH := 170.0

var cd := 0.4
var second_t := -1.0          # 第二刺倒计时
var second_ang := 0.0
var second_mult := 1.0
var gust_next := false        # S1：下一次刺击带浮空
var airborne: Array = []      # {e, t, dur, h}
var strikes: Array = []       # S3 手炮轰击队列：{t}
var judge_c := Vector2.INF
var judge_left := 0.0
var thrust_n := 0             # 刺击计数：两段刺击左右错开
var draw_spin_t := 0.0        # S3 转身开火的转身残影剩余时间
# ---- 可见成长
var retrial_on := false       # N1 再审：第三段刺击
var strict_on := false        # N2 严律：刺击更长更宽
var gale_on := false          # N4 卷风
var tide2_on := false         # N5 二度裂潮
var pursue_on := false        # 精二 追诉
var pursue_cd := 0.0
var stage_i := 0              # 当前刺击段数（1 / 2 / 3）
var tide2_t := -1.0           # 二度裂潮倒计时
var tide2_swing := false      # 二度裂潮那一斩的动作已起手，出手帧由 _release_skill 结算


## 四边形：对齐网格后宽度可能收成 0（两侧顶点重合）→ 退化时画成一条线，避免三角化报错
func _quad(q: PackedVector2Array, c: Color) -> void:
	if q[1].distance_to(q[3]) < 2.0:
		g.draw_line(q[0], q[2], c, 2.0)
	else:
		g.draw_colored_polygon(q, c)


## 刺击光束：u = 进度 0→1；前 30% 伸到最长（缓出），之后宽度收细、淡出；顶点对齐 2 像素网格保持像素感
func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "gale":
		# 卷风：贴地三道玫瑰色旋风弧由外向内收拢，外圈一道淡环标出卷起范围
		var u0: float = 1.0 - a
		g.draw_set_transform(f.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		g.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 32, Color(PINK.r, PINK.g, PINK.b, 0.35 * a), 1.5)
		for q in 3:
			var rr: float = f.r * (1.0 - 0.6 * u0) * (1.0 - q * 0.22)
			var a0: float = u0 * 9.0 + q * TAU / 3.0
			g.draw_arc(Vector2.ZERO, rr, a0, a0 + 2.0, 12, Color(PINK.r * 1.5, PINK.g * 1.4, PINK.b * 1.5, 0.8 * a), 3.0 - q * 0.6)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return true
	if f.kind != "thrust":
		return false
	var u: float = 1.0 - a
	var ext: float = 1.0 - pow(1.0 - minf(1.0, u / 0.3), 3.0)
	var d: Vector2 = f.dir
	var n: Vector2 = d.orthogonal()
	var L: float = f.len * ext
	var o: Vector2 = f.pos + d * 14.0 * u          # 整体略向前推
	var tip: Vector2 = o + d * L
	var wide: float = f.w * (1.0 - 0.7 * maxf(0.0, (u - 0.3) / 0.7))
	var c: Color = f.col
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	if L < 12.0:
		return true   # 刚伸出、还太短：对齐网格后会退化，不画
	# 外层：玫瑰色长菱形（尾细、70% 处最宽、剑尖尖）
	_quad(PackedVector2Array([P.call(o + d * 6.0), P.call(o + d * L * 0.7 + n * wide * 0.5), P.call(tip), P.call(o + d * L * 0.7 - n * wide * 0.5)]),
		Color(c.r, c.g, c.b, 0.55 * a))
	# 内芯：白热细线
	_quad(PackedVector2Array([P.call(o + d * L * 0.25), P.call(o + d * L * 0.72 + n * wide * 0.18), P.call(tip + d * 2.0), P.call(o + d * L * 0.72 - n * wide * 0.18)]),
		Color(2.2, 2.1, 2.2, 0.95 * a))
	# 两侧速度线
	for s in [-1.0, 1.0]:
		var off: Vector2 = n * s * (wide * 0.5 + 5.0)
		g.draw_line(P.call(o + d * L * 0.35 + off), P.call(o + d * L * 0.85 + off), Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 0.45 * a), 1.0)
	# 剑尖星形闪光（伸到最长那一刻最亮）；有 fx_star_hit_rose 帧条时由帧条画
	if u > 0.2 and u < 0.75 and g.tex.get("fx_star_hit_rose") == null:
		var k: float = 1.0 - absf(u - 0.35) / 0.4
		var sz: float = 7.0 * k
		g.draw_line(P.call(tip - d * sz), P.call(tip + d * sz), Color(2.4, 2.2, 2.4, k), 2.0)
		g.draw_line(P.call(tip - n * sz * 0.6), P.call(tip + n * sz * 0.6), Color(2.4, 2.2, 2.4, k), 2.0)
	return true


func _reach() -> float:
	return base("len", 180.0) * stat(&"op_range") * (base("strict_len", 1.25) if strict_on else 1.0)


func _width() -> float:
	return base("width", 26.0) * (base("strict_width", 1.4) if strict_on else 1.0)


## 成长节点（data/characters/irene.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"retrial":
			retrial_on = true
		"strict":
			strict_on = true
		"gale":
			gale_on = true
		"tide2":
			tide2_on = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		pursue_on = true


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 40.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	_update_airborne(dt)
	_update_strikes(dt)
	pursue_cd = maxf(0.0, pursue_cd - dt)
	if second_t >= 0.0:
		second_t -= dt
		if second_t < 0.0:
			second_t = -1.0
			stage_i += 1
			if stage_i == 3:
				# 再审：第三段刺击（刺击伤害 60%）
				_thrust(second_ang, second_mult * base("retrial_mult", 0.6), false)
			else:
				_thrust(second_ang, second_mult, false)
				if retrial_on:
					second_t = _stage_gap()
	if tide2_t >= 0.0:
		tide2_t -= dt
		if tide2_t < 0.0:
			tide2_t = -1.0
			# 二度裂潮：有空就先起一个技能动作，出手帧再斩（docs/45 #8：原来待机姿势时刀光凭空出现）；正在出手就直接斩
			if acting():
				_shattertide(base("tide2_mult", 0.8))
			else:
				tide2_swing = true
				_start_action("skill", Vector2.INF, 0.5, 0.2)
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		gust_next = true
		fx({"kind": "glow", "pos": pos + Vector2(10.0 * face, -30), "r": 14.0, "life": 0.3, "col": PINK, "alpha": 0.5})
		return
	if ready > 0:
		var ts: Array = nearest_enemies(1, 220.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts2: Array = nearest_enemies(1, _reach() + 20.0, pos)
		if ts2.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 0.8) / stat(&"op_aspd")
			start_attack(ts2[0].pos)


## 出手帧（第一刺）；第二刺按帧条的 second 帧延后
func _release() -> void:
	var ts: Array = nearest_enemies(1, _reach() + 40.0, pos)
	var ang: float = facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var mult := 1.0
	var gust := gust_next
	gust_next = false
	if gust:
		mult = base("s1_mult", 1.6) * skill_power()
	stage_i = 1
	var first := _thrust(ang, mult, gust)
	second_t = _stage_gap()
	second_ang = ang
	second_mult = mult
	if gust and not first.is_empty():
		# 疾风：第一个命中者浮空 1 秒，落下时再补一刺
		_lift(first, 1.0, 26.0)
		fx({"kind": "ring", "pos": first.pos, "r": 30.0, "r0": 6.0, "life": 0.3, "col": PINK, "floor": true})
		# 卷风：浮空的目标卷起身边 70 内的敌人一起浮空 0.8 秒；贴地一圈旋风
		if gale_on:
			var gr: float = base("gale_r", 70.0)
			for j in query_ids(first.pos, gr + 30.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or is_same(e, first) or e.pos.distance_to(first.pos) > gr + e.r:
					continue
				_lift(e, base("gale_lift", 0.8), 20.0)
			fx({"kind": "gale", "pos": first.pos, "r": gr, "life": 0.45, "floor": true})


## 段间隔：按帧条的 second 帧与出手帧之差
func _stage_gap() -> float:
	var spec := sprite_spec("attack")
	var fps: float = float(spec.get("fps", 12))
	return maxf(0.05, (float(spec.get("second", 3)) - float(spec.get("fire", 1))) / fps)


## 直线穿刺：返回命中的第一个敌人（最近的）
func _thrust(ang: float, mult: float, tag_gust: bool) -> Dictionary:
	var d := Vector2.from_angle(ang)
	var o: Vector2 = pos + Vector2(0, -12)
	var L: float = _reach()
	var W: float = _width()
	var hits: Array = []
	for j in query_ids(o + d * L * 0.5, L * 0.6 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - o
		var along: float = rel.dot(d)
		if along < -e.r or along > L + e.r:
			continue
		if absf(rel.cross(d)) > W * 0.5 + e.r:
			continue
		hits.append([along, e])
	hits.sort_custom(func(a, b): return a[0] < b[0])
	var dmg: float = base("atk", 24.0) * _dmg_bonus() * mult
	var first: Dictionary = {}
	for h in hits:
		var e: Dictionary = h[1]
		# 追诉：刺中浮空 / 被她控住的敌人时追加一发手炮（先判定：本次伤害可能把它打死）
		var pursue: bool = pursue_on and pursue_cd <= 0.0 and not e.dead and (e.get("air", 0.0) > 0.0 or _is_airborne(e))
		log_hit("疾风" if tag_gust else "刺剑")
		deal_damage(e, dmg * _talent_mult(e))
		if pursue:
			pursue_cd = base("pursue_cd", 0.4)
			_cannon(e.pos, base("atk", 24.0) * base("s3_strike_mult", 1.55) * base("pursue_mult", 0.6) * _dmg_bonus(), "追诉")
		fx({"kind": "spark", "pos": e.pos + Vector2(0, -e.r * 0.5), "vel": d * 120.0 + Vector2(g.rng.randf_range(-40, 40), -60), "life": 0.25, "col": SILVER, "sz": 2.0, "drag": 3.0})
		if first.is_empty():
			first = e
			spawn_fx_sprite("fx_thrust_hit_rose", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.9, ang)
	# 刺击光束（2026-09-25，替换原来的弧光帧条：她是刺剑，不是斩击）：细长尖头光束瞬间伸到最长再收细消失，
	# 剑尖星形闪光 + 两侧速度线；两段刺击左右错开几像素（参考《哈迪斯》长矛突刺、《死亡细胞》细剑）
	thrust_n += 1
	var side: float = 4.0 if thrust_n % 2 == 0 else -4.0
	# 光束从剑身高度出剑（op_irene_attack@2x 出手帧：握剑手约在脚底前 12、上 32）；命中判定仍用贴地的 o（docs/32 §3）
	var st: Vector2 = pos + Vector2(0, -32) + d * 12.0 + d.orthogonal() * side
	var tsc: float = g.PX * clampf(L / 128.0, 0.9, 1.1)
	# Codex 刺击光束（64×12，左端出剑，长度伸缩 ≤ 1.1）；缺图退回程序光束 + 剑尖星芒
	if not spawn_fx_sprite("fx_irene_thrust", st + d * 32.0 * tsc, tsc, ang, false, false, Color(1.1, 0.8, 1.0) if tag_gust else Color.WHITE):
		fx({"kind": "thrust", "pos": st, "dir": d, "len": L, "w": 9.0 if tag_gust else 7.0, "life": 0.16,
			"col": PINK if not tag_gust else Color(1.1, 0.7, 0.95)})
		spawn_fx_sprite("fx_star_hit_rose", st + d * (L + 10.0), g.PX * 0.8)
	elif strict_on:
		# 严律：帧条长度伸缩上限 1.1，更长更宽的部分由程序光束叠出（剑尖星芒标出新的刺击末端）
		fx({"kind": "thrust", "pos": st, "dir": d, "len": L, "w": 7.0 * base("strict_width", 1.4), "life": 0.16, "col": PINK if not tag_gust else Color(1.1, 0.7, 0.95)})
		spawn_fx_sprite("fx_star_hit_rose", st + d * (L + 6.0), g.PX * 0.8)
	if stage_i == 3:
		# 第三段（再审）：剑尖多一道金色星芒，和前两段区分
		fx({"kind": "glow", "pos": st + d * L, "r": 10.0, "life": 0.18, "col": LAMP, "alpha": 0.7})
	Sfx.op(id, "atk", 0.0, 1.0, 0.08)
	if not first.is_empty():
		Sfx.op(id, "hit")
	return first


## 天赋：对受控敌人 +30%
func _talent_mult(e: Dictionary) -> float:
	if elite >= 1 and (e.get("air", 0.0) > 0.0 or e.stun > 0.0 or e.slow > 0.0):
		return 1.0 + base("talent_bonus", 0.3)
	return 1.0


# ---------------------------------------------------------------- 浮空

func _lift(e: Dictionary, dur: float, h: float) -> void:
	if e.dead or e.boss or dur <= 0.0:
		return
	if e.elite:
		dur *= 0.5
	for a in airborne:
		if is_same(a.e, e):
			a.dur = maxf(a.dur, dur)
			a.t = 0.0
			return
	airborne.append({"e": e, "t": 0.0, "dur": dur, "h": h})
	e.stun = maxf(e.stun, dur)


func _update_airborne(dt: float) -> void:
	if airborne.is_empty():
		return
	for a in airborne:
		a.t += dt
		var e: Dictionary = a.e
		if e.dead:
			e.air = 0.0
			a.t = a.dur + 1.0
			continue
		var k: float = clampf(a.t / a.dur, 0.0, 1.0)
		e.air = sin(k * PI) * a.h
		e.kb = Vector2.ZERO
		if k >= 1.0:
			e.air = 0.0
	airborne = airborne.filter(func(a): return a.t < a.dur)


func _airborne_enemies(c: Vector2, r: float) -> Array:
	var out: Array = []
	for a in airborne:
		if not a.e.dead and a.e.pos.distance_to(c) < r:
			out.append(a.e)
	return out


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	if tide2_swing:
		tide2_swing = false
		_shattertide(base("tide2_mult", 0.8))
		return
	match cur_skill:
		1:
			_shattertide(1.0)
			# 二度裂潮（原作 S2 可存 2 次）：0.35 秒后再斩一次，80% 伤害
			if tide2_on:
				tide2_t = base("tide2_delay", 0.35)
			# 发动音 op_irene_s2 由 spend_sp 播放（锥形重斩本身）
		2:
			# 审判（照原作）：以她为中心的冲击波掀起周身全部敌人、浮空 4 秒；随后转身手炮连射 12 发
			var r3: float = base("s3_r", 160.0) * stat(&"op_range")
			var dmg3: float = base("atk", 24.0) * base("s3_mult", 1.9) * _dmg_bonus() * skill_power()
			for e in arc_targets(pos + Vector2(0, -10), 0.0, PI, r3):
				log_hit("审判")
				deal_damage(e, dmg3 * _talent_mult(e))
				_lift(e, base("s3_lift", 4.0), 44.0)
			judge_c = pos
			judge_left = 3.6
			strikes.clear()
			for i in int(base("s3_strikes", 12.0)):
				strikes.append({"t": 0.35 + i * 0.25})
			# 冲击波：提灯一闪 → 两道贴地冲击环由内向外扩散 + 放射光线；被掀起的敌人脚下各一小圈
			fx({"kind": "glow", "pos": _lantern(true), "r": 30.0, "life": 0.25, "col": Color(1.8, 1.5, 0.9), "alpha": 0.8})
			fx({"kind": "ring", "pos": pos, "r": r3, "r0": 16.0, "life": 0.4, "col": LAMP, "floor": true, "w": 5.0})
			fx({"kind": "ring", "pos": pos, "r": r3 * 0.75, "r0": 8.0, "life": 0.55, "col": PINK, "floor": true, "w": 2.5})
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -30), "life": 0.6, "max": 0.6, "col": LAMP})
			g.hitstop = maxf(g.hitstop, 0.08)
			show_banner("审判")


## 碎潮：前方锥形，最多 8 名，×2.8 × mult，浮空 2 秒（每次重新瞄准最近的敌人）
func _shattertide(mult: float) -> void:
	var ts: Array = nearest_enemies(1, 240.0, pos)
	var ang: float = facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var r: float = _reach() * 1.3
	var hits: Array = arc_targets(pos + Vector2(0, -10), ang, 0.8, r)
	hits.sort_custom(func(a, b): return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos))
	var dmg: float = base("atk", 24.0) * base("s2_mult", 2.8) * _dmg_bonus() * skill_power() * mult
	var n: int = mini(int(base("s2_n", 8.0)), hits.size())
	for i in n:
		var e: Dictionary = hits[i]
		log_hit("碎潮")
		deal_damage(e, dmg * _talent_mult(e))
		_lift(e, 2.0, 34.0)
	# 第二斩：镜像翻转 + 偏银白，与第一斩区分
	var second: bool = mult < 1.0
	var tint: Color = Color(1.1, 1.15, 1.35) if second else Color.WHITE
	if not spawn_fx_sprite("fx_slash_heavy_rose", pos + Vector2(0, -14) + Vector2.from_angle(ang) * r * 0.32, r * 1.0 / 28.0, ang, second, false, tint):   # 贴近剑（docs/45 #8）
		slash_fx(pos + Vector2(0, -14), ang, 0.8, r, SILVER if second else PINK, "slash", 0.25)
	fx_sparks(pos + Vector2.from_angle(ang) * r * 0.5, SILVER, 10, 200.0, 0.4, 2.5, 200.0)
	if second:
		Sfx.op(id, "atk", 2.0, 0.9)


func skill_active_left(i: int) -> float:
	return judge_left if i == 2 else 0.0


## 一技能是「下一次」强化：放出后到这一击打出去之前算未完成（图鉴演示等它打完再切段，c820b22）
func skill_pending(i: int) -> bool:
	return i == 0 and gust_next


func skill_active_dur(i: int) -> float:
	return 3.0 if i == 2 else 1.0


func _update_strikes(dt: float) -> void:
	judge_left = maxf(0.0, judge_left - dt)
	draw_spin_t = maxf(0.0, draw_spin_t - dt)
	if strikes.is_empty():
		return
	var r3: float = base("s3_r", 160.0) * stat(&"op_range")
	for s in strikes:
		s.t -= dt
		if s.t <= 0.0:
			# 优先砸浮空目标，其次范围内随机敌人
			# 手炮是远程：优先打审判圈内的浮空目标，其次她身边 1.6 倍范围内最近的几个
			var pool: Array = _airborne_enemies(judge_c, r3)
			if pool.is_empty():
				pool = nearest_enemies(6, r3 * 1.6, pos)
			if pool.is_empty():
				continue
			var e: Dictionary = pool[g.rng.randi() % pool.size()]
			var c: Vector2 = e.pos
			# 转身开火：每一发先转向目标（原作她转着身向四周射击），身后留一道转身的残影
			var prev_face: float = face
			face_to((c - pos).angle())
			if face != prev_face:
				draw_spin_t = 0.12
			_cannon(c, base("atk", 24.0) * base("s3_strike_mult", 1.8) * _dmg_bonus() * skill_power(), "手炮轰击")
	strikes = strikes.filter(func(s): return s.t > 0.0)


## 手炮一发（审判连射与精二追诉共用）：目标周围 40 小范围伤害。
## 表现照原作：炮口一闪 → 弹道光直线打到目标 → 目标处带黑烟的小爆炸（ansimuz 素材；缺图退回程序）
func _cannon(c: Vector2, dmg: float, src: String) -> void:
	area_hit(src, c, 40.0, dmg, 0.0, 0.0)
	var muzzle: Vector2 = pos + Vector2(12.0 * face, -30)
	spawn_fx_sprite("fx_muzzle_flash", muzzle, g.PX * 0.7)
	fx({"kind": "line", "pos": muzzle, "to": c + Vector2(0, -10), "life": 0.08, "col": Color(1.0, 0.8, 0.6), "w": 2.0})
	if not spawn_fx_sprite("fx_cannon_burst", c + Vector2(0, 6), g.PX * 1.2, 0.0, false, true):
		fx({"kind": "glow", "pos": c + Vector2(0, -10), "r": 18.0, "life": 0.2, "col": LAMP, "alpha": 0.6})
	fx({"kind": "ring", "pos": c, "r": 34.0, "r0": 6.0, "life": 0.25, "col": LAMP, "floor": true})
	Sfx.op(id, "big", -4.0, 1.0, 0.1)


func _is_airborne(e: Dictionary) -> bool:
	for a in airborne:
		if is_same(a.e, e):
			return true
	return false


# ---------------------------------------------------------------- 绘制

func _draw_skill_over() -> void:
	# 举灯 / 审判期间：提灯亮
	if judge_left > 0.0 or (acting() and act_kind == "skill"):
		var p := _lantern(acting() and act_kind == "skill")
		g.draw_circle(p, 5.0 + sin(g.t * 20.0), Color(1.6, 1.3, 0.7, 0.8))
		g.draw_circle(p, 12.0, Color(1.0, 0.85, 0.5, 0.2))
	# 转身开火：身后一道半圆的玫瑰色转身弧 + 反向的淡残影
	if draw_spin_t > 0.0:
		var k: float = draw_spin_t / 0.12
		var c: Vector2 = pos + Vector2(0, -24)
		var a0: float = PI * 0.5 if face > 0.0 else -PI * 0.5   # 身后半圆（原来的三元表达式对 void 取值会报错）
		g.draw_arc(c, 22.0, a0, a0 + PI, 16, Color(PINK.r * 1.5, PINK.g * 1.4, PINK.b * 1.4, 0.7 * k), 4.0)
		draw_body_at(pos, face > 0.0, Color(PINK.r * 1.3, PINK.g * 1.2, PINK.b * 1.3, 0.45 * k))
	# 浮空敌人脚下的小影环
	for a in airborne:
		if not a.e.dead:
			g.draw_set_transform(a.e.pos + Vector2(0, a.e.r * 0.8), 0.0, Vector2(1.0, 0.5))
			g.draw_arc(Vector2.ZERO, a.e.r * 0.9, 0.0, TAU, 20, Color(PINK.r, PINK.g, PINK.b, 0.5), 1.5)
			g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func status_items() -> Array:
	var out: Array = []
	if gust_next:
		out.append(["疾风", PINK])
	if judge_left > 0.0:
		out.append(["审判", LAMP])
	return out


## 提灯位置（docs/32 §3）：平时提在身前下方（op_irene_idle@2x：脚底前 19、上 15），举灯技能帧举过头顶（skill 第 4 帧：前 21、上 60）
func _lantern(raised: bool) -> Vector2:
	return pos + (Vector2(20.0 * face, -56.0) if raised else Vector2(16.0 * face, -15.0))
