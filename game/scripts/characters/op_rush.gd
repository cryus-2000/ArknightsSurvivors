## 干员突击冲锋：爆发窗口的第一下冲锋（_rush_step / 撞怪 _rush_impact / 推开 _rush_push）、突击模式低频自冲刺（_roam_dash_*）、冲锋拖尾绘制。
## docs/286 §4 第三批从 characters/character.gd 原样拆出，行为不变：全部 static func，第一个参数 ov = 干员实例（成员经 ov.、常量 / 静态函数经 C.）。
## 入口 begin_rush（squad 调用）与状态变量（rush_* / _roam_dash_t）仍在 character.gd。
extends RefCounted

const C = preload("res://scripts/characters/character.gd")
const CmdBal = preload("res://scripts/core/balance.gd")


static func _roam_dash_cd(ov: C) -> float:
	return float(ov.def.get("command", {}).get("roam_dash_cd", CmdBal.v("command/roam_dash_cd", 7.0)))


static func _roam_dash_tick(ov: C, dt: float) -> void:
	var g = ov.g
	if CmdBal.v("command/roam_dash", 1.0) <= 0.0 or not bool(ov.def.get("command", {}).get("roam_dash", true)) or ov.is_leader:
		return
	if ov._roam_dash_t < 0.0:   # 本次出击第一次：按编队序号错开
		ov._roam_dash_t = _roam_dash_cd(ov) * (0.6 + 0.12 * float(maxi(0, g.squad.ops.find(ov))))
	if ov.rush_t > 0.0 or ov.cmd_down > 0.0:
		return
	ov._roam_dash_t -= dt
	if ov._roam_dash_t > 0.0:
		return
	ov.begin_rush()
	ov._roam_dash_t = _roam_dash_cd(ov) if ov.rush_t > 0.0 else 1.0


static func _rush_step(ov: C, dt: float) -> Vector2:
	var g = ov.g
	ov.rush_t -= dt
	var to: Vector2 = ov.rush_goal - ov.pos
	var sv: Vector2 = to.limit_length(CmdBal.v("command/rush_speed", 780.0) * dt)
	var np: Vector2 = ov.pos + sv
	var hit := false
	for j in ov.query_ids(np, 44.0):
		var en: Dictionary = g.enemies[j]
		if not en.dead and not en.chest and en.pos.distance_to(np) < float(en.r) + 20.0:
			hit = true
			break
	ov._rush_emit_t -= dt
	if ov._rush_emit_t <= 0.0:
		ov._rush_emit_t = 0.03
		_rush_push(ov, np, false)
	if hit or ov.rush_t <= 0.0 or sv.length() >= to.length() - 0.5:
		ov.rush_t = 0.0
		_rush_impact(ov, np)
	return sv


## 撞击：身边 command/rush_hit_r 内的怪被推开（精英 ×rush_kb_elite，Boss / 部件 / 宝箱免疫）
static func _rush_impact(ov: C, p: Vector2) -> void:
	var g = ov.g
	var hr: float = CmdBal.v("command/rush_hit_r", 56.0)
	var kb: float = CmdBal.v("command/rush_kb", 340.0)
	var n := 0
	for j in ov.query_ids(p, hr + 24.0):
		var en: Dictionary = g.enemies[j]
		if en.dead or en.boss or en.chest or en.get("part", false) or en.pos.distance_to(p) > hr + float(en.r):
			continue
		var dv: Vector2 = en.pos - p
		if dv.length_squared() < 1.0:
			dv = Vector2(ov.face if ov.face != 0.0 else 1.0, 0.0)
		ov.apply_kb(en, dv.normalized() * kb * (CmdBal.v("command/rush_kb_elite", 0.5) if en.elite else 1.0))
		n += 1
	if n > 0 or ov.rush_goal != Vector2.INF:
		_rush_push(ov, p, true)
		_rush_sfx(ov, "swing_heavy", -7.0)
	if g.get("trace_every") != null and g.trace_every > 0.0:
		print("CMD t=%.2f rush %s kb=%d" % [g.t, ov.id, n])
	ov.rush_goal = Vector2.INF


static func _rush_sfx(ov: C, name: String, vol: float) -> void:
	var g = ov.g
	if g.headless_batch:
		return
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.play(name, vol)


static func _rush_push(ov: C, p: Vector2, big: bool) -> void:
	var g = ov.g
	if g.headless_batch:
		return   # 纯画面：无头批跑不记
	ov._rush_seq += 1
	ov.rush_trail.append({"p": p, "a": 0.0, "n": ov._rush_seq, "big": big})


static func _rush_age(ov: C, dt: float) -> void:
	if ov.rush_trail.is_empty():
		return
	var life: float = CmdBal.v("command/rush_trail_life", 0.22)
	for tp in ov.rush_trail:
		tp.a += dt
	ov.rush_trail = ov.rush_trail.filter(func(tp): return tp.a < life)


## 金色轨迹：每个点 3 颗 2 / 4 像素的方块（序号哈希摆位），撞击点向外迸 8 颗；三阶透明度；新点带白芯。全部落在 2 px 网格上
static func _draw_rush_trail(ov: C) -> void:
	var g = ov.g
	var life: float = CmdBal.v("command/rush_trail_life", 0.22)
	var optical: bool = g.optical_on
	for tp in ov.rush_trail:
		var u: float = clampf(float(tp.a) / life, 0.0, 0.999)
		var q: float = [1.0, 0.6, 0.3][int(u * 3.0)]
		var base: Vector2 = tp.p + Vector2(0, -10)
		var n: int = tp.n
		var cnt: int = 8 if tp.big else 3
		for i in cnt:
			var off: Vector2
			if tp.big:
				off = Vector2.from_angle(TAU * i / 8.0 + float(n % 3) * 0.2) * (8.0 + u * 30.0)
			else:
				off = Vector2(float((n * 7 + i * 5) % 9 - 4) * 2.0, float((n * 3 + i * 11) % 9 - 4) * 2.0)
			var pt := Vector2(snappedf(base.x + off.x, 2.0), snappedf(base.y + off.y, 2.0))
			var s: float = 4.0 if u < 0.4 else 2.0
			var col := Color(1.0, 0.82, 0.3, q) if u > 0.33 else Color(1.0, 0.95, 0.7, q)
			ov.cv.draw_rect(Rect2(pt, Vector2(s, s)), col)
			if optical and u < 0.5 and i == 0:
				g.glow_next.append([pt, 4.0, Color(1.0, 0.78, 0.3)])
