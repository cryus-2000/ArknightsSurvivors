extends RefCounted
## 伊莎玛拉地面预警（docs/170，10-27）：取代光学观感的斜线填充与闪烁描边。
## 暗红低填充 + 2 像素格「涟漪」勾边（落点圈：三道涟漪向中心收拢 = 读条；直线：两侧点列 + 沿线推进的水纹；扇形：外弧点列 + 内弧推进）。
## 范围与判定几何完全一致（同一份 pos / r / len / wid / half）；只画面，不写模拟状态、不用随机数。render/ishar_tell 0 = 退回通用画法。
const Bal = preload("res://scripts/core/balance.gd")
const Beam = preload("res://scripts/render/boss_beam.gd")
const Combos = preload("res://scripts/enemies/bosses/ishar_combos.gd")
const CORE := Color(0.62, 1.0, 0.86)   # 光束本体 = 她的专属青绿；预警底仍是暗红
const ACTS := ["ishar_strike", "ishar_line", "ishar_echo", "bite", "sweep"]
const FILL := Color(0.42, 0.05, 0.12)
const EDGE := Color(0.86, 0.26, 0.42)


static func owns(w: Dictionary) -> bool:
	var o = w.get("owner")
	var act: String = str(w.get("act", ""))
	# 补充招式里的直线预警（合唱齐射 choir、深海触腕 tentacle）也归这里；移动实体（合唱压境音波）仍由 boss_attack_draw 画材质
	var mine: bool = act in ACTS or (act == "final_attack" and w.get("shape", "") == "line" and str(w.get("skin", "")) in ["choir", "tentacle"])
	return mine and o is Dictionary and o.get("type", "") == "ishar" and not w.get("dim", false) and Bal.v("render/ishar_tell", 1.0) > 0.0


static func _sq(g, p: Vector2, c: Color) -> void:
	g.draw_rect(Rect2((p * 0.5).floor() * 2.0, Vector2(2, 2)), c)


## 光束蓄力：本体从 1 像素细线长到半宽的 35%，亮度随读条递增；发射口光点变大，聚光颗粒向内收
static func _charge(g, w: Dictionary, d: Vector2, k: float) -> void:
	var kk: float = k * k
	var half: float = lerpf(1.0, float(w.wid) * 0.35, kk)
	var a: float = 0.15 + 0.6 * kk
	var nrm: Vector2 = d.orthogonal() * half
	var b: Vector2 = w.pos + d * float(w.len)
	g.draw_colored_polygon(PackedVector2Array([w.pos + nrm, b + nrm, b - nrm, w.pos - nrm]), Color(CORE.r, CORE.g, CORE.b, a))
	g.draw_circle(w.pos, 3.0 + 9.0 * kk, Color(1.0, 1.0, 1.0, 0.25 + 0.6 * kk))
	var pool = Beam.grains(g) if Cfg.quality != "low" else null
	if pool != null and Beam.take(g, 2) > 0:
		var ang: float = g.t * 7.0 + w.pos.x
		var dir := Vector2.from_angle(ang)
		pool.push("mote_in", w.pos + dir * (28.0 + 20.0 * (1.0 - k)), -dir, CORE)


## 开火短闪 + 消散：前 0.06 秒整条白闪；之后光束变细、断成碎段、淡出（g.fx kind = ishar_beam_fade，由 ishar_combos 在结算帧写入）
static func _fades(g) -> void:
	for f in g.fx:
		if f.kind != "ishar_beam_fade" or f.life <= 0.0:
			continue
		var p: float = 1.0 - float(f.life) / float(f.max)
		var a: Vector2 = f.a
		var b: Vector2 = f.b
		var d: Vector2 = (b - a).normalized()
		var L: float = a.distance_to(b)
		if p < 0.17:
			var n0: Vector2 = d.orthogonal() * float(f.wid) * 0.9
			g.draw_colored_polygon(PackedVector2Array([a + n0, b + n0, b - n0, a - n0]), Color(1.0, 1.0, 1.0, 0.55 * (1.0 - p / 0.17)))
		var half: float = float(f.wid) * 0.45 * (1.0 - p)
		var seg := 22.0
		var gap: float = 2.0 + 18.0 * p   # 断口随时间变宽
		var col := Color(CORE.r, CORE.g, CORE.b, 0.8 * (1.0 - p))
		var s0 := 0.0
		var i := 0
		while s0 < L:
			var drift: float = (float((i * 37) % 7) - 3.0) * 3.0 * p   # 碎段各自轻微侧漂
			var o: Vector2 = d.orthogonal() * drift
			var s1: float = minf(L, s0 + seg - gap)
			var nn: Vector2 = d.orthogonal() * maxf(1.0, half)
			g.draw_colored_polygon(PackedVector2Array([a + d * s0 + nn + o, a + d * s1 + nn + o, a + d * s1 - nn + o, a + d * s0 - nn + o]), col)
			s0 += seg
			i += 1


## 歌声涟漪留下的地带：暗红低填充 + 每 0.6 秒从中心扩出一道像素涟漪，最后 0.4 秒淡出
static func _zones(g) -> void:
	var gy: float = g.combat.GROUND_Y
	for e in g.bosses:
		for z in e.get("ishar_zones", []):
			if g.t < float(z.born):
				continue
			var fade: float = clampf((float(z.until) - g.t) / 0.4, 0.0, 1.0)
			var pts := PackedVector2Array()
			for i in 33:
				var an: float = TAU * i / 32.0
				pts.append(z.pos + Vector2(cos(an), sin(an) * gy) * float(z.r))
			g.draw_colored_polygon(pts, Color(FILL.r, FILL.g, FILL.b, 0.2 * fade))
			for q in 2:
				var ph: float = fmod((g.t - float(z.born)) / 0.6 + q * 0.5, 1.0)
				var rr: float = float(z.r) * ph
				var m: int = clampi(int(rr * TAU / 12.0), 6, 60)
				for i in m:
					var an: float = TAU * i / m
					_sq(g, z.pos + Vector2(cos(an), sin(an) * gy) * rr, Color(EDGE.r, EDGE.g, EDGE.b, 0.55 * (1.0 - ph) * fade))
			var n: int = clampi(int(float(z.r) * TAU / 9.0), 16, 90)
			for i in n:
				if i % 2 == 0:
					var an: float = TAU * i / n
					_sq(g, z.pos + Vector2(cos(an), sin(an) * gy) * float(z.r), Color(EDGE.r, EDGE.g, EDGE.b, 0.5 * fade))


static func draw(g) -> void:
	_zones(g)
	_fades(g)
	var gy: float = g.combat.GROUND_Y
	for w in g.warns:
		if w.done or not owns(w):
			continue
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var tr: float = float(w.get("track", 0.0))
		var locked: bool = w.t >= tr
		var hot: float = 1.0 if w.dur - w.t < 0.15 else 0.0
		var fill := Color(FILL.r, FILL.g, FILL.b, 0.14 + 0.14 * k + 0.1 * hot)
		var edge := Color(EDGE.r, EDGE.g, EDGE.b, (0.55 if locked else 0.35) + 0.35 * hot)
		var ripple := Color(EDGE.r, EDGE.g, EDGE.b, 0.3 + 0.3 * k)
		match w.shape:
			"circle":
				var r: float = w.r
				var pts := PackedVector2Array()
				for i in 33:
					var a: float = TAU * i / 32.0
					pts.append(w.pos + Vector2(cos(a), sin(a) * gy) * r)
				g.draw_colored_polygon(pts, fill)
				var n: int = clampi(int(r * TAU / 9.0), 16, 120)
				for i in n:
					var a: float = TAU * i / n
					_sq(g, w.pos + Vector2(cos(a), sin(a) * gy) * r, edge)
				# 三道涟漪由外向圆心收拢，最后一道到达圆心 = 结算
				for q in 3:
					var rk: float = r * (1.0 - fmod(k + q / 3.0, 1.0) * 0.9) if k < 0.98 else r * 0.1
					var m: int = clampi(int(rk * TAU / 14.0), 8, 80)
					for i in m:
						if (i + q) % 3 == 0:
							continue   # 断续：读作水纹，不是第二道实线
						var a: float = TAU * i / m + q * 0.4
						_sq(g, w.pos + Vector2(cos(a), sin(a) * gy) * rk, ripple)
			"line":
				var d := Vector2.from_angle(w.ang)
				var nrm: Vector2 = d.orthogonal() * float(w.wid)
				var L: float = w.len
				g.draw_colored_polygon(PackedVector2Array([w.pos + nrm, w.pos + d * L + nrm, w.pos + d * L - nrm, w.pos - nrm]), fill)
				var s := 0.0
				var step: float = 8.0 if locked else 14.0   # 锁定前点列稀疏（还在跟踪），锁定后加密
				while s <= L:
					_sq(g, w.pos + d * s + nrm, edge)
					_sq(g, w.pos + d * s - nrm, edge)
					s += step
				# 沿线推进的水纹：读条到哪，水纹推到哪
				var front: float = L * k
				var f := 0.0
				while f < front:
					var amp: float = sin(f * 0.09 - g.t * 6.0) * float(w.wid) * 0.45
					_sq(g, w.pos + d * f + d.orthogonal() * amp, ripple)
					f += 6.0
				if Combos.is_beam(w):
					_charge(g, w, d, k)
			"cone":
				var pts := PackedVector2Array([w.pos])
				for i in 17:
					pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / 16.0) * w.r)
				g.draw_colored_polygon(pts, fill)
				var n: int = clampi(int(w.r * w.half * 2.0 / 8.0), 8, 90)
				for i in n + 1:
					_sq(g, w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / n) * w.r, edge)
				for s2 in [-1.0, 1.0]:
					var dv := Vector2.from_angle(w.ang + w.half * s2)
					var t := 12.0
					while t < w.r:
						_sq(g, w.pos + dv * t, edge)
						t += 10.0
				# 内弧从口部推向外沿
				var rk: float = w.r * k
				var m: int = clampi(int(rk * w.half * 2.0 / 10.0), 4, 70)
				for i in m + 1:
					if i % 2 == 0:
						_sq(g, w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * i / m) * rk, ripple)
