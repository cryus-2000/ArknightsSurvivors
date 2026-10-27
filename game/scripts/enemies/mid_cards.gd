## 中期 Boss 弹幕与连段积木（docs/170，10-27）：塑路者（path.gd）与接潮组（bishop.gd 指挥两具）共用。
## 只放「弹体行为 / 有限连段队列」两样积木；招式本身仍在各 Boss 脚本里，预警与结算走正式管线（telegraph）。
## 状态全在敌人字典上，不新增随机数：弹体行为全部确定性（同 seed TRACE 不变）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")

const OWNER_CAP := 150     # 每具弹同屏上限（超出新弹直接不发，不挤旧弹）
const TOTAL_CAP := 420     # 全场敌弹上限（与 boss_patterns 同量级）
const REC1 := 0.22         # 连段段间收势：一幕 / 二幕（docs/169 口径）
const REC2 := 0.12
const Q_MAX := 4           # 每组最多 4 个命名攻击阶段
const Q_GUARD := 16.0      # 每组保护性上限（秒）


## ---- 弹体
## 弹：tier 0 小（r5）/ 1 中（r7）/ 2 大（r10）；画面 render/mid_card_draw（暗描边 + 本色 + 热白芯）。
## o：hold 秒（原地显形，之后才以 v0 出发；东方式「先排出图案再放」，本身就是预警）、acc 每秒加速、vmax / vmin、turn 每秒转角、
##    split {t, n, spread, spd, tier, depth}（到点分裂成 n 颗，depth > 0 时子弹再分）、mult 伤害倍率（× e.dmg × boss/mid_pattern_dmg，缺省 0.8：弹幕变密后单发整体下调，10-27 用户，云端测完再定）
static func shot(g, e: Dictionary, pos: Vector2, ang: float, spd: float, tier: int, o := {}) -> bool:
	var own := 0
	var total := 0
	for b in g.ebullets:
		if b.life > 0.0:
			total += 1
			if int(b.get("source_id", -1)) == int(e.id):
				own += 1
	if own >= OWNER_CAP or total >= TOTAL_CAP:
		return false
	_add(g, e, pos, ang, spd, tier, o)
	return true


static func _add(g, e: Dictionary, pos: Vector2, ang: float, spd: float, tier: int, o: Dictionary) -> void:
	var r: float = [5.0, 7.0, 10.0][clampi(tier, 0, 2)]
	var hold: float = float(o.get("hold", 0.0))
	var v0: Vector2 = Vector2.from_angle(ang) * spd
	var b := {"pos": pos, "vel": Vector2.ZERO if hold > 0.0 else v0, "v0": v0, "dmg": e.dmg * float(o.get("mult", 0.45)) * Bal.v("boss/mid_pattern_dmg", 0.8), "r": r,
		"life": float(o.get("life", 5.0)) + hold, "slow": false, "frost": 0.0, "corrode": float(o.get("corrode", 0.0)), "nerve": 0.0, "true": false,
		"kind": "mc", "mc": true, "tier": tier, "age": 0.0, "hold": hold, "home": false, "boss": true, "atk": "法术", "hit_cap": e.get("hit_cap", 0.0),
		"source_id": e.id, "col": o.get("col", g.vfx.boss_color(e.type)), "src_type": e.type, "no_rock": o.get("no_rock", false)}
	for k in ["acc", "vmax", "vmin", "turn", "split", "turn_until"]:
		if o.has(k):
			b[k] = o[k]
	g.ebullets.append(b)


## 每帧推进这一具的弹体行为（在 shots.step 的直线推进之前）：显形 → 出发、加减速、转弯、分裂
static func step_shots(g, e: Dictionary, dt: float) -> void:
	var born: Array = []
	for b in g.ebullets:
		if b.life <= 0.0 or not b.get("mc", false) or int(b.source_id) != int(e.id):
			continue
		b.age = float(b.age) + dt
		if float(b.hold) > 0.0:
			if b.age < float(b.hold):
				continue
			b.hold = 0.0
			b.vel = b.v0
		if b.has("acc"):
			var s: float = b.vel.length()
			var ns: float = clampf(s + float(b.acc) * dt, float(b.get("vmin", 0.0)), float(b.get("vmax", 9999.0)))
			b.vel = (b.vel / maxf(s, 0.001)) * ns if s > 0.001 else b.v0.normalized() * ns
		if b.has("turn") and b.age < float(b.get("turn_until", INF)):
			b.vel = b.vel.rotated(float(b.turn) * dt)
		var sp = b.get("split")
		if sp is Dictionary and b.age >= float(sp.t):
			b.life = 0.0
			var n: int = int(sp.n)
			var base: float = b.vel.angle() if b.vel.length() > 1.0 else b.v0.angle()
			for i in n:
				var a: float = base + (lerpf(-float(sp.spread), float(sp.spread), float(i) / float(n - 1)) if n > 1 else 0.0)
				var co := {"mult": b.dmg / maxf(1.0, float(e.dmg)), "col": b.col, "life": float(sp.get("life", 3.2))}
				if int(sp.get("depth", 0)) > 0:
					var sub: Dictionary = sp.duplicate()
					sub.depth = int(sp.depth) - 1
					sub.t = float(sp.get("t2", sp.t))
					sub.tier = maxi(0, int(sp.get("tier", 0)) - 1)
					co.split = sub
				if sp.has("acc"):
					co.acc = sp.acc
					co.vmax = sp.get("vmax", 9999.0)
				born.append([b.pos, a, float(sp.spd), int(sp.get("tier", 0)), co])
	for x in born:
		shot(g, e, x[0], x[1], x[2], x[3], x[4])


## ---- 有限连段（docs/169 口径：每组 ≤4 段、段间收势、结束给破绽；打断 / 无敌 / 假死 / 过卡点清队列）
## steps：[{actor, move}]；exec(actor, move) -> 这一段占用的秒数（< 0 = 放不出，跳过）
static func q_start(g, e: Dictionary, steps: Array, brk: float, partners := []) -> void:
	e.mc_q = steps.slice(0, Q_MAX)
	e.mc_q_at = g.t
	e.mc_q_brk = brk
	e.mc_q_end = INF
	e.mc_q_t0 = g.t
	e.mc_q_n = 0
	e.mc_q_partners = partners


static func q_active(e: Dictionary) -> bool:
	return not e.get("mc_q", []).is_empty() or float(e.get("mc_q_end", INF)) < INF


## 接潮搭档：主教（e.partner）的配合连段进行中
static func in_pair_combo(e: Dictionary) -> bool:
	var p = e.get("partner")
	return p is Dictionary and not p.dead and q_active(p)


static func q_cancel(g, e: Dictionary) -> void:
	if not q_active(e):
		return
	e.mc_q = []
	e.mc_q_end = INF
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done or float(w.dmg) <= 0.0 or not w.get("mc_combo", false))


## 每帧：连段进行中返回 true（占住出招窗口，别的招不插队）
static func q_step(g, e: Dictionary, exec: Callable, p2: bool) -> bool:
	if not q_active(e):
		return false
	var actors: Array = [e] + e.get("mc_q_partners", [])
	var broken := false
	for a in actors:
		if a == null or a.dead or a.get("coma", false) or a.get("invuln", false) or a.stun > 0.0 or (float(a.get("break_t", 0.0)) > 0.0 and is_same(a, e)):
			broken = true
	if broken or g.t - float(e.mc_q_t0) > Q_GUARD:
		q_cancel(g, e)
		return false
	if float(e.mc_q_end) < INF:
		if g.t >= float(e.mc_q_end):
			e.mc_q_end = INF
			for a in actors:
				g.combat.start_break(a, float(e.mc_q_brk))
				a.brk_label = "收招 · 破绽"
			# 破绽里与破绽后 0.6 秒不出新的图案弹幕（输出窗口不叠弹幕，协调人 10-27）
			e.pat_beat = maxf(float(e.get("pat_beat", 0.0)), g.t + float(e.mc_q_brk) + 0.6)
		return true
	if g.t < float(e.mc_q_at):
		return true
	for a in actors:
		if float(a.get("dash_t", 0.0)) > 0.0 or a.has("leap"):
			return true   # 等上一段的自冲 / 跃起真正落地
	while not e.mc_q.is_empty():
		var st: Dictionary = e.mc_q.pop_front()
		var dur: float = float(exec.call(st.actor, str(st.move)))
		if dur < 0.0:
			continue
		e.mc_q_n = int(e.mc_q_n) + 1
		for w in g.warns:
			if not w.done and (is_same(w.owner, st.actor)) and w.t <= 0.0:
				w.mc_combo = true
		e.mc_q_at = g.t + dur + (REC2 if p2 else REC1)
		if e.mc_q.is_empty():
			e.mc_q_end = g.t + dur + 0.1
		return true
	e.mc_q_end = g.t
	return true


## ---- 几何小工具
## a 关于「A、B 中垂线」的镜像方向（接潮组镜像弹幕）
static func mirror_ang(a: float, pa: Vector2, pb: Vector2) -> float:
	var axis: Vector2 = (pb - pa).normalized()   # 中垂线的法向 = 两体连线方向
	var d := Vector2.from_angle(a)
	return (d - 2.0 * d.dot(axis) * axis).angle()
