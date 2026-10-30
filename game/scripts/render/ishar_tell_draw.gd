extends RefCounted
## 伊莎玛拉地面预警（docs/170，10-27）：取代光学观感的斜线填充与闪烁描边。
## 暗红低填充 + 2 像素格「涟漪」勾边（落点圈：三道涟漪向中心收拢 = 读条；直线：两侧点列 + 沿线推进的水纹；扇形：外弧点列 + 内弧推进）。
## 范围与判定几何完全一致（同一份 pos / r / len / wid / half）；只画面，不写模拟状态、不用随机数。render/ishar_tell 0 = 退回通用画法。
const Bal = preload("res://scripts/core/balance.gd")
const Beam = preload("res://scripts/render/boss_beam.gd")
const Combos = preload("res://scripts/enemies/bosses/ishar_combos.gd")
const CORE := Color(0.62, 1.0, 0.86)   # 光束本体 = 她的专属青绿；预警底仍是暗红
const ACTS := ["ishar_strike", "ishar_line", "ishar_echo", "ishar_sweep", "ishar_dash", "bite", "sweep"]
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


## 光束蓄力（10-31 用户「激光不像激光」，render/ishar_laser 1）：预警期只画一条 2 像素细瞄准线（她的专属色，亮度随读条递增，锁定后变实）
## + 发射口一颗越来越大的光点 + 向内收的聚光颗粒；最后 0.15 秒瞄准线转白、发射口光点最亮 = 马上开火。开火后才出现有宽度的光束（_laser），预警和实线一眼分开
static func _charge(g, w: Dictionary, d: Vector2, k: float) -> void:
	var kk: float = k * k
	var b: Vector2 = w.pos + d * float(w.len)
	var hot: bool = float(w.dur) - float(w.t) < 0.15
	var locked: bool = float(w.t) >= float(w.get("track", 0.0))
	var lc: Color = Color(1, 1, 1, 0.9) if hot else Color(CORE.r, CORE.g, CORE.b, (0.35 if not locked else 0.55) + 0.35 * kk)
	g.draw_line(w.pos, b, lc, 2.0)
	_dot(g, w.pos, 3.0 + float(w.wid) * 0.3 * kk, 0.4 + 0.6 * kk)
	var pool = Beam.grains(g) if Cfg.quality != "low" else null
	if pool != null and Beam.take(g, 2) > 0:
		var ang: float = g.t * 7.0 + w.pos.x
		var dir := Vector2.from_angle(ang)
		pool.push("mote_in", w.pos + dir * (28.0 + 20.0 * (1.0 - k)), -dir, CORE)


## 开火 + 消散（g.fx kind = ishar_beam_fade，由 ishar_combos 在结算帧写入）：hold 期间是稳定光束（开火前 0.06 秒从 0.3 宽张满 + 白闪）；
## 之后整条一起收细、外晕先散、两端光点缩小、淡出（10-31 起不再断成碎段：用户「不要拼接感」）
static func _fades(g) -> void:
	for f in g.fx:
		if f.kind != "ishar_beam_fade" or f.life <= 0.0:
			continue
		var hold: float = float(f.get("hold", 0.0))
		var el: float = float(f.max) - float(f.life)
		var a: Vector2 = f.a
		var b: Vector2 = f.b
		var d: Vector2 = (b - a).normalized()
		var L: float = a.distance_to(b)
		if el < hold:
			_laser(g, a, d, L, float(f.wid), clampf(0.3 + el / 0.06, 0.3, 1.0), clampf(1.0 - el / 0.1, 0.0, 1.0), 1.0, 1.0)
			continue
		var p: float = clampf((el - hold) / maxf(0.01, float(f.max) - hold), 0.0, 1.0)
		var fl: float = clampf(1.0 - p / 0.2, 0.0, 1.0) if hold <= 0.0 else 0.0
		_laser(g, a, d, L, float(f.wid), lerpf(1.0, 0.15, p), fl, 1.0 - p, (1.0 - p) * (1.0 - p))


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
			g.draw_colored_polygon(pts, Color(FILL.r, FILL.g, FILL.b, 0.3 * fade))   # 10-28：地带内受治疗降低，底色比预警更实
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


## 统一光束（10-31 用户「所有激光统一一套」：细亮芯 + 外晕、起止端光点、不拼接）：一整条一次画完（每层一个多边形，没有分段 / 贴图平铺）。
## 由外到内：两层低透明外晕（宽 1.0 / 0.7）→ 专属色光身（0.34）→ 亮色（0.16）→ 2–4 像素白芯；起点一颗大光点、终点一颗小光点。
## open = 宽度比例（开火张开、消散收细）；flash = 开火白闪；alpha = 整体透明；glow = 外晕透明（消散时先散）
static func _laser(g, a: Vector2, d: Vector2, L: float, wid: float, open: float, flash: float, alpha := 1.0, glow := 1.0) -> void:
	var b: Vector2 = a + d * L
	var o: Vector2 = d.orthogonal()
	var w: float = wid * 2.0 * open   # wid 是半宽（与判定的 line wid 同口径）：光束外晕正好贴着判定边（10-31 用户「跟踪大激光粗一倍」）
	for q in [[1.0, 0.1], [0.7, 0.16]]:
		var n: Vector2 = o * w * 0.5 * float(q[0])
		g.draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), Color(CORE.r, CORE.g, CORE.b, float(q[1]) * alpha * glow))
	var n1: Vector2 = o * maxf(2.0, w * 0.17)
	g.draw_colored_polygon(PackedVector2Array([a + n1, b + n1, b - n1, a - n1]), Color(CORE.r, CORE.g, CORE.b, 0.8 * alpha))
	var hi: Color = CORE.lerp(Color.WHITE, 0.6)
	var n2: Vector2 = o * maxf(1.5, w * 0.08)
	g.draw_colored_polygon(PackedVector2Array([a + n2, b + n2, b - n2, a - n2]), Color(hi.r, hi.g, hi.b, 0.95 * alpha))
	var n3: Vector2 = o * clampf(wid * 0.03, 1.0, 2.0) * minf(1.0, open * 1.5)
	g.draw_colored_polygon(PackedVector2Array([a + n3, b + n3, b - n3, a - n3]), Color(1, 1, 1, alpha))
	if flash > 0.0:
		var nf: Vector2 = o * w * 0.4
		g.draw_colored_polygon(PackedVector2Array([a + nf, b + nf, b - nf, a - nf]), Color(1, 1, 1, 0.5 * flash * alpha))
	_dot(g, a, maxf(4.0, wid * 0.42 * open) * (1.0 + 0.4 * flash), alpha)
	_dot(g, b, maxf(3.0, wid * 0.26 * open) * (1.0 + 0.6 * flash), alpha * 0.9)


## 光点：外晕（专属色，低透明）→ 亮色 → 白芯
static func _dot(g, p: Vector2, r: float, alpha: float) -> void:
	g.draw_circle(p, r * 1.7, Color(CORE.r, CORE.g, CORE.b, 0.18 * alpha))
	var hi: Color = CORE.lerp(Color.WHITE, 0.6)
	g.draw_circle(p, r, Color(hi.r, hi.g, hi.b, 0.85 * alpha))
	g.draw_circle(p, r * 0.5, Color(1, 1, 1, alpha))


static func _sweeps(g) -> void:
	for e in g.bosses:
		for key in Combos.SWEEPS:
			_sweep_draw(g, e.get(key, {}))


static func _sweep_draw(g, s: Dictionary) -> void:
		if s.is_empty():
			return
		var el: float = g.t - float(s.t0)
		var d := Vector2.from_angle(float(s.ang))
		_laser(g, s.pos, d, float(s.len), float(s.wid), clampf(0.3 + el / 0.06, 0.3, 1.0), clampf(1.0 - el / 0.12, 0.0, 1.0))
		var pool = Beam.grains(g) if Cfg.quality != "low" else null
		if pool != null and Beam.take(g, 1) > 0:
			var t: float = fmod(el * 1.7, 1.0)
			pool.push("bfx_flash", s.pos + d * float(s.len) * t, d.orthogonal() * (1.0 if int(el * 30.0) % 2 == 0 else -1.0), CORE)


## 每幕场地（docs/170 §15）：二幕每 2.4 秒从她脚下扩出一道很淡的海嗣潮纹（压迫）；三幕整个场地罩一层腐红底色，亮度 4 秒一呼吸（缓慢、不闪）。一幕不加
static func _arena(g) -> void:
	var gy: float = g.combat.GROUND_Y
	for e in g.bosses:
		if e.dead or e.phase != 2 or Bal.v("render/ishar_act_style", 1.0) <= 0.0:
			continue
		var act: int = clampi(int(e.get("gates_passed", 0)), 0, 2)
		var c: Color = Combos.act_mood(e)
		var R: float = g.zone_r if g.zone_frozen else 650.0
		if act == 2:
			var pts := PackedVector2Array()
			for i in 49:
				var an: float = TAU * i / 48.0
				pts.append(g.zone_c + Vector2(cos(an), sin(an) * gy) * R)
			g.draw_colored_polygon(pts, Color(0.55, 0.06, 0.16, 0.2 + 0.04 * sin(g.t * TAU / 4.0)))
		if act >= 1:
			var ph: float = fmod(g.t / 2.4, 1.0)
			var rr: float = lerpf(60.0, R, ph)
			var m: int = clampi(int(rr * TAU / 16.0), 12, 160)
			for i in m:
				if i % 3 == 0:
					continue
				var an: float = TAU * i / m
				_sq(g, e.pos + Vector2(cos(an), sin(an) * gy) * rr, Color(c.r, c.g, c.b, 0.22 * (1.0 - ph)))


## 连线护盾（ishar._web_shield）：与连线同色的护罩（层数越多越实）+ 头顶层数刻度（亮 = 在、暗 = 碎了等回复）
static func _shield(g) -> void:
	var gy: float = g.combat.GROUND_Y
	for e in g.bosses:
		var layers: Array = e.get("web_layers", [])
		if e.dead or layers.is_empty():
			continue
		var up: int = int(e.get("web_sh_up", 0))
		var c: Color = Combos.COL
		var r: float = e.r + 18.0
		if up > 0:
			var pts := PackedVector2Array()
			for i in 33:
				var an: float = TAU * i / 32.0
				pts.append(e.pos + Vector2(0, -e.r * 0.5) + Vector2(cos(an), sin(an) * 0.85) * r)
			g.draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.06 + 0.03 * up))
			var n: int = clampi(int(r * TAU / 8.0), 16, 60)
			for i in n:
				if (i + int(g.t * 6.0)) % 4 == 0:
					continue
				var an: float = TAU * i / n
				_sq(g, e.pos + Vector2(0, -e.r * 0.5) + Vector2(cos(an), sin(an) * 0.85) * r, Color(c.r, c.g, c.b, 0.3 + 0.08 * up))
		var w0: float = layers.size() * 8.0
		for k in layers.size():
			var on: bool = float(layers[k].hp) > 0.0
			var q: Vector2 = e.pos + Vector2(-w0 * 0.5 + k * 8.0 + 4.0, -e.r * 2.0 - 30.0)
			g.draw_rect(Rect2((q * 0.5).floor() * 2.0 - Vector2(2, 2), Vector2(6, 6)), Color(c.r, c.g, c.b, 0.95) if on else Color(1, 1, 1, 0.18))


## 三幕歌声围拢（10-29 用户「青绿点线不清楚」）：红色场地底色固定不动；围拢圈 = 3 像素实线（专属色）+ 两侧暗描边 + 内侧一圈流动亮点，
## 圈外到场地边压一层暗幕（站在暗处 = 在掉血），圈越收暗幕越大，「被围住」一眼可见
static func _fence(g) -> void:
	var gy: float = g.combat.GROUND_Y
	for e in g.bosses:
		var f: Dictionary = e.get("ishar_fence", {})
		if e.dead or f.is_empty():
			continue
		var R: float = g.bai.boss("ishar").cards()._fence_r(e)
		var c: Color = Combos.act_col(e)
		var Ro: float = maxf(R + 40.0, (g.zone_r if g.zone_frozen else 650.0) + 60.0)
		var n: int = 64
		var ring := PackedVector2Array()
		for i in n + 1:
			var an: float = TAU * i / n
			ring.append(f.c + Vector2(cos(an), sin(an) * gy) * R)
		var veil := Color(0.02, 0.0, 0.03, Bal.v("render/ishar_fence_veil", 0.42))
		for i in n:
			var a0: float = TAU * i / n
			var a1: float = TAU * (i + 1) / n
			g.draw_colored_polygon(PackedVector2Array([ring[i], ring[i + 1],
				f.c + Vector2(cos(a1), sin(a1) * gy) * Ro, f.c + Vector2(cos(a0), sin(a0) * gy) * Ro]), veil)
		var pulse: float = 0.8 + 0.2 * sin(g.t * TAU / 1.2)
		g.draw_polyline(ring, Color(0.02, 0.05, 0.06, 0.8), 7.0)
		g.draw_polyline(ring, Color(c.r, c.g, c.b, pulse), 3.0)
		var m: int = clampi(int(R * TAU / 22.0), 24, 160)
		for i in m:
			var an: float = TAU * (float(i) + fmod(g.t * 1.5, 1.0)) / m
			_sq(g, f.c + Vector2(cos(an), sin(an) * gy) * (R - 8.0), Color(1.0, 1.0, 1.0, 0.55 * pulse))


static func draw(g) -> void:
	_arena(g)
	_fence(g)
	_zones(g)
	_fades(g)
	_sweeps(g)
	_shield(g)
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
