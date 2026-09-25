## 推进之王（先锋，契约 v2.1）：节奏位。前压到博士身边的敌人面前抡锤，命中时为全队回复技力。
## S1 冲锋号令：全队技力 + 下一锤强化；S2 跃空锤：跃起空中转一圈、落地砸击范围晕眩 + 全队技力；S3 碎颅：8 秒重锤，命中概率眩晕，攻速下降。
## 特效（docs/25）：狮王金。锤击重弧 + 命中十字闪；命中后金色技力粒子飞向每名队友（回 DP）；砸地双环 + 地裂 + 火星。
extends "res://scripts/characters/character.gd"

const GOLD := Color(1.0, 0.78, 0.35)
const LEASH := 150.0          # 前压：只追博士这么远以内的敌人
const S3_DUR := 8.0

var cd := 0.4
var charge_next := false      # S1：下一锤 ×1.5
var skull := 0.0              # S3 碎颅剩余
var leap_t := -1.0            # S2 跃空锤：跃起后经过的秒数（-1 = 不在空中）
var leap_pos := Vector2.ZERO  # 起跳点
var leap_to := Vector2.ZERO   # 落点：朝最近的敌人跃过去（最多 90），落在它面前
const LEAP_DUR := 0.42
const LEAP_H := 42.0
const FLAME := Color(1.0, 0.55, 0.15)
var heavy_swing := false      # S3 碎颅期间：这一锤用技能动作（原 S2 双手砸地）出手


## 基础数值全部可由 data/characters/siege.json 的 base 段覆盖（docs/27 §3）
func _reach() -> float:
	return base("reach", 72.0) * stat(&"op_range")


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 26.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	skull = maxf(0.0, skull - dt)
	if leap_t >= 0.0:
		# 跃空锤：空中转一圈，落地砸击（在 follow 之后覆盖位置，沿起跳点 → 落点飞过去）
		leap_t += dt
		var lu: float = clampf(leap_t / LEAP_DUR, 0.0, 1.0)
		pos = leap_pos.lerp(leap_to, lu)
		if leap_t >= LEAP_DUR:
			leap_t = -1.0
			_slam()
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready == 0:
		spend_sp(0)
		charge_next = true
		g.squad.gain_sp(base("s1_sp", 0.15) * skill_power(), self)
		_sp_motes(2)
		fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 20.0, "life": 0.3, "col": GOLD, "alpha": 0.5})
		g._add_text(pos + Vector2(0, -80), "冲锋号令", GOLD, 14)
		return
	if ready > 0:
		start_skill(Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 1.0) / stat(&"op_aspd") * (1.33 if skull > 0.0 else 1.0)
			if skull > 0.0:
				# 碎颅：每一锤都是强化版砸地（播技能动作帧），出手时仍走 _release 结算
				heavy_swing = true
				_start_action("skill", ts[0].pos, 0.6, 0.3)
			else:
				start_attack(ts[0].pos)


func _release() -> void:
	var ang := facing_angle()
	var ts: Array = g._nearest(1, _reach() + 40.0, pos)
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var mult := 1.0
	if charge_next:
		charge_next = false
		mult *= base("s1_mult", 1.5) * skill_power()
	if skull > 0.0:
		mult *= base("s3_mult", 1.8) * skill_power()
	Sfx.op(id, "atk")
	var hits := melee_hit("锤击", pos + Vector2(0, -10), ang, 1.2, _reach(), base("atk", 30.0) * mult * _dmg_bonus(), 140.0)
	if skull > 0.0:
		for e in hits:
			if not e.dead and not e.boss and g.rng.randf() < 0.5:
				e.stun = maxf(e.stun, 0.8 * (0.5 if e.elite else 1.0))
	g._slash_fx(pos + Vector2(0, -14), ang, 1.0, _reach(), GOLD if skull <= 0.0 else Color(1.0, 0.6, 0.3))
	if skull > 0.0:
		# 碎颅的每一锤：落点一次小型砸地（闪光 + 冲击环 + 不规则地裂 + 火星）
		var hp: Vector2 = pos + Vector2(0, -6) + Vector2.from_angle(ang) * _reach() * 0.7
		fx({"kind": "glow", "pos": hp + Vector2(0, -4), "r": 24.0, "life": 0.14, "col": Color(2.0, 1.5, 0.8), "alpha": 0.8})
		fx({"kind": "ring", "pos": hp + Vector2(0, 6), "r": 58.0, "r0": 8.0, "life": 0.3, "col": FLAME, "floor": true, "w": 3.0})
		fx({"kind": "crack", "pos": hp + Vector2(0, 6), "r": 56.0, "life": 0.7, "col": FLAME, "floor": true, "n": 6})
		fx_sparks(hp, Color(1.0, 0.8, 0.35), 8, 220.0, 0.35, 2.5, 320.0)
		g.hitstop = maxf(g.hitstop, 0.04)
	if not hits.is_empty():
		# 每次命中（不论几个目标）全队 +0.5 秒技力，精一翻倍
		_squad_sp_seconds(base("hit_sp", 0.5) * (2.0 if elite >= 1 else 1.0))
		_sp_motes(1)
		Sfx.op(id, "hit", 2.0 if skull > 0.0 else 0.0, 0.85 if skull > 0.0 else 1.0)


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	# 命中点十字重击闪
	fx({"kind": "impact", "pos": e.pos + Vector2(0, -e.r * 0.5), "life": 0.15, "col": GOLD, "ang": g.rng.randf() * PI})


func _release_skill() -> void:
	if heavy_swing:
		heavy_swing = false
		_release()
		return
	match cur_skill:
		1:
			# 跃空锤（照原作）：跃起、空中抡锤转一圈，落地砸击（_slam）
			leap_t = 0.0
			leap_pos = pos
			leap_to = pos
			var ts: Array = g._nearest(1, 160.0, pos)
			if not ts.is_empty():
				var dv: Vector2 = ts[0].pos - pos
				leap_to = pos + dv.normalized() * clampf(dv.length() - 24.0, 0.0, 90.0)
				face = signf(dv.x) if absf(dv.x) > 1.0 else face
			fx({"kind": "ring", "pos": pos, "r": 26.0, "r0": 6.0, "life": 0.2, "col": GOLD, "floor": true, "w": 2.0})
		2:
			# 碎颅：8 秒重锤
			skull = S3_DUR
			fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 30.0, "life": 0.35, "col": Color(1.0, 0.6, 0.3), "alpha": 0.6})
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": GOLD})
			g._show_banner("碎颅")


## 跃空锤落地：伤害 / 眩晕 / 全队技力在这一刻结算；特效照原作截图：一圈向上窜的橙黄火焰 + 黄色光柱与放射光线 + 贴地冲击波
func _slam() -> void:
	var r: float = base("s2_r", 110.0) * stat(&"op_range")
	area_hit("震地", pos, r, base("atk", 30.0) * base("s2_mult", 2.2) * _dmg_bonus() * skill_power(), 220.0, 0.6)
	fx({"kind": "glow", "pos": pos + Vector2(0, -6), "r": 34.0, "life": 0.16, "col": Color(2.0, 1.7, 0.9), "alpha": 0.8})
	fx({"kind": "ring", "pos": pos, "r": r, "r0": 14.0, "life": 0.35, "col": FLAME, "floor": true, "w": 4.0})
	fx({"kind": "crack", "pos": pos + Vector2(0, 2), "r": r * 0.8, "life": 0.55, "col": GOLD, "floor": true, "n": 10, "ang": g.t})
	# 光柱 + 放射光线
	fx({"kind": "pillar", "pos": pos + Vector2(0, 2), "life": 0.38, "col": Color(1.9, 1.7, 0.6)})
	# 火（ansimuz 素材，照原作截图）：中心地面火圈张开 + 周围一圈大小不一的火焰；缺图退回程序水滴火苗
	if g._fx_sprite("fx_fire_aura", pos + Vector2(0, 6), clampf(r * 1.2 / 58.0, 2.0, 3.0), 0.0, false, true):
		for k in 8:
			var fa: float = k * TAU / 8.0 + g.rng.randf_range(-0.2, 0.2)
			var fr: float = r * g.rng.randf_range(0.35, 0.7)
			g._fx_sprite("fx_flames", pos + Vector2(cos(fa) * fr, sin(fa) * fr * 0.5 + 4.0), g.PX * g.rng.randf_range(0.7, 1.05), 0.0, g.rng.randf() < 0.5, true)
	else:
		_blaze_ring(r)
	fx_sparks(pos + Vector2(0, -4), Color(1.0, 0.8, 0.35), 12, 260.0, 0.4, 2.5, 320.0)
	g.hitstop = maxf(g.hitstop, 0.07)
	g.squad.gain_sp(base("s2_sp", 0.2) * skill_power(), self)
	_sp_motes(3)
	Sfx.op(id, "big")


## 程序火苗（缺 fx_flames 帧条时的后备）：落点周围贴地的椭圆上窜起，内圈高、外圈矮
func _blaze_ring(r: float) -> void:
	for k in 16:
		var a: float = k * TAU / 16.0 + g.rng.randf_range(-0.15, 0.15)
		var rr: float = r * g.rng.randf_range(0.25, 0.75)
		var p: Vector2 = pos + Vector2(cos(a) * rr, sin(a) * rr * 0.5 + 2.0)
		var inner: bool = rr < r * 0.5
		fx({"kind": "blaze", "pos": p, "vel": Vector2(cos(a) * 24.0, -g.rng.randf_range(10.0, 30.0)), "life": g.rng.randf_range(0.32, 0.48),
			"sz": g.rng.randf_range(20.0, 28.0) if inner else g.rng.randf_range(12.0, 18.0), "seed": g.rng.randf() * 10.0})


## 空中翻转的速度感（照原作，用户确认）：以干员为圆心的**实心**扇形渐变盘——旋转扫过的区域整块填白，
## 最前端（当前朝向）最亮，往后按角度逐渐透明，最长拖将近一整圈；前端一小条橙色。画在人物身后。
func _draw_spin_disc(c: Vector2, u: float) -> void:
	var sgn: float = 1.0 if face >= 0.0 else -1.0
	var head: float = -PI / 2.0 + u * TAU * sgn
	var sweep: float = minf(u * TAU + 0.6, 5.8)
	var R := 36.0
	var N := 36
	for i in N:
		var t0: float = float(i) / N
		var t1: float = float(i + 1) / N
		var a0: float = head - sgn * sweep * t0
		var a1: float = head - sgn * sweep * t1
		var k: float = pow(1.0 - t0, 1.7)
		var col := Color(1.9, 1.9, 2.0, 0.7 * k)
		g.draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * R, c + Vector2.from_angle(a1) * R]), col)
	# 前端：一条橙色的扫描边 + 外沿一段更亮的弧
	g.draw_line(c, c + Vector2.from_angle(head) * R, Color(FLAME.r * 1.6, FLAME.g * 1.4, FLAME.b, 0.9), 3.0)
	var o0: float = head - sgn * 0.5
	g.draw_arc(c, R, minf(o0, head), maxf(o0, head), 6, Color(2.2, 2.2, 2.3, 0.9), 3.0)


## 空中时的身体中心：脚底上方半个身高（按当前帧贴图的脚底锚点算），翻转与拖影圆环都以它为圆心
func _air_center(h: float) -> Vector2:
	var st := anim_state()
	if st.is_empty():
		return pos + Vector2(0, -h - 24.0)
	var tx: Texture2D = st.tex
	var fo: float = foot_off(tx, st.get("kind", ""))
	var pk: float = g.PX / A.hires_of(tx)
	return pos + Vector2(0, -h + (-tx.get_height() + fo) / 2.0 * pk)


## 空中：身体绕身体中心整圈翻转（贴图按帧画、只加旋转），高度抛物线；阴影由 squad 按 pos 画在地面
func draw_body() -> void:
	if leap_t < 0.0:
		super()
		return
	var st := anim_state()
	if st.is_empty():
		return
	var u: float = clampf(leap_t / LEAP_DUR, 0.0, 1.0)
	var h: float = 4.0 * LEAP_H * u * (1.0 - u)
	var ang: float = u * TAU * (1.0 if face >= 0.0 else -1.0)
	var tx: Texture2D = st.tex
	var hf: int = st.hf
	var fw: float = tx.get_width() / hf
	var fh: float = tx.get_height()
	var fo: float = foot_off(tx, st.get("kind", ""))
	var pk: float = g.PX / A.hires_of(tx)
	var cy: float = (-fh + fo) / 2.0                 # 身体中心相对脚底（贴图像素）
	var center: Vector2 = _air_center(h)
	_draw_spin_disc(center, u)
	g.draw_set_transform(center.round(), ang, Vector2(-pk if st.flip else pk, pk))
	g.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + fo - cy), Vector2(fw, fh)), Rect2(fw * (st.frame % hf), 0, fw, fh))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func skill_active_left(i: int) -> float:
	return skull if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


## 金色技力粒子：从她飞向每名队友
func _sp_motes(n: int) -> void:
	for o in g.squad.ops:
		if o == self or o.pos == Vector2.INF:
			continue
		for k in n:
			fx({"kind": "sp_mote", "pos": pos + Vector2(0, -22), "start": pos + Vector2(0, -22), "tgt": o, "life": 0.45 + 0.08 * k, "col": GOLD, "bend": g.rng.randf_range(-40, 40)})


func _draw_pfx(f: Dictionary, a: float) -> bool:
	match f.kind:
		"blaze":
			# 火焰（照原作截图）：下宽上尖的水滴形，边缘抖动的火苗；外层橙、内层黄白（高亮触发辉光），底部一团光晕；先窜高再缩小熄灭
			var k: float = 1.0 - a
			var h: float = f.sz * (0.55 + 0.9 * minf(1.0, k * 3.0)) * (0.4 + 0.6 * a)
			var w: float = f.sz * 0.36 * (0.5 + 0.5 * a)
			var b: Vector2 = f.pos
			g.draw_circle(b + Vector2(0, -h * 0.15), w * 1.4, Color(2.0, 0.9, 0.25, 0.22 * a))
			for layer in 2:
				var s2: float = 1.0 if layer == 0 else 0.55
				var hh: float = h * s2
				var ww: float = w * s2
				var left := PackedVector2Array()
				var right := PackedVector2Array()
				for i in 7:
					var t: float = float(i) / 6.0            # 0 = 底 → 1 = 火尖
					var hw: float = ww * sqrt(maxf(0.0, 1.0 - t)) * (0.75 + 1.6 * t if t < 0.15 else 1.0)
					var wob: float = sin(g.t * 22.0 + f.seed + t * 5.0) * ww * 0.3 * t
					left.append(b + Vector2(-hw + wob, -hh * t))
					right.append(b + Vector2(hw + wob, -hh * t))
				right.reverse()
				var pts: PackedVector2Array = left
				pts.append_array(right.slice(1))
				var col: Color = Color(2.0, 0.85, 0.22, 0.8 * a) if layer == 0 else Color(2.6, 2.1, 1.1, 0.9 * a)
				g.draw_colored_polygon(pts, col)
			return true
		"pillar":
			# 落地光柱：底宽上窄的黄色光束迅速升起再变细消失，外加几条向上张开的放射光线
			var k: float = 1.0 - a
			var H: float = 150.0 * minf(1.0, k * 4.0)
			var w: float = 30.0 * (1.0 - k * 0.8)
			var b: Vector2 = f.pos
			var c: Color = f.col
			g.draw_colored_polygon(PackedVector2Array([b + Vector2(-w, 0), b + Vector2(-w * 0.25, -H), b + Vector2(w * 0.25, -H), b + Vector2(w, 0)]), Color(c.r, c.g, c.b, 0.35 * a))
			g.draw_colored_polygon(PackedVector2Array([b + Vector2(-w * 0.35, 0), b + Vector2(-2, -H * 0.9), b + Vector2(2, -H * 0.9), b + Vector2(w * 0.35, 0)]), Color(2.2, 2.1, 1.6, 0.6 * a))
			for q in 6:
				var ang: float = -PI / 2.0 + (q - 2.5) * 0.28
				g.draw_line(b + Vector2(0, -8), b + Vector2(0, -8) + Vector2.from_angle(ang) * H * (0.6 + 0.08 * (q % 3)), Color(c.r, c.g, c.b, 0.5 * a), 2.0)
			return true
		"sp_mote":
			var k := 1.0 - a
			var to: Vector2 = f.tgt.pos + Vector2(0, -24)
			var p: Vector2 = f.start.lerp(to, k) + Vector2(0, -sin(k * PI) * 30.0) + f.start.direction_to(to).orthogonal() * sin(k * PI) * f.bend
			var tail: Vector2 = f.start.lerp(to, maxf(0.0, k - 0.12)) + Vector2(0, -sin(maxf(0.0, k - 0.12) * PI) * 30.0)
			g.draw_line(tail, p, Color(GOLD.r, GOLD.g, GOLD.b, 0.5), 2.0)
			g.draw_circle(p, 3.0, Color(2.2, 1.8, 0.9))
			return true
		"impact":
			var L := 10.0 + 14.0 * (1.0 - a)
			for q in 2:
				var dv := Vector2.from_angle(f.ang + q * PI / 2.0)
				g.draw_line(f.pos - dv * L, f.pos + dv * L, Color(2.0, 1.7, 1.0, a), 2.5)
			g.draw_circle(f.pos, 5.0 * a + 2.0, Color(2.4, 2.2, 1.6, a))
			return true
	return false


func draw_auras() -> void:
	if skull > 0.0 and pos != Vector2.INF:
		g.draw_arc(pos + Vector2(0, -22), 26.0 + 3.0 * sin(g.t * 9.0), 0.0, TAU, 24, Color(1.0, 0.6, 0.3, 0.4 + 0.15 * sin(g.t * 9.0)), 2.0)


## 全队（不含自己）技力 + 秒数
func _squad_sp_seconds(sec: float) -> void:
	for o in g.squad.ops:
		if o == self:
			continue
		for i in 3:
			if o.skill_unlocked(i) and o.sp_need(i) > 0.0:
				o.sp[i] = minf(o.sp_need(i), o.sp[i] + sec)


func status_items() -> Array:
	var out: Array = []
	if charge_next:
		out.append(["冲锋号令", GOLD])
	if skull > 0.0:
		out.append(["碎颅", Color(1.0, 0.6, 0.3)])
	return out
