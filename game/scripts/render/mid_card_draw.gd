## 中期 Boss 弹体与预警画法（docs/170，10-27）：塑路者、接潮组（enemies/mid_cards.gd 发的 kind "mc" 弹、skin "mc_*" 预警）。
## 只读不写模拟状态，不碰玩法随机数；全部吸附 2 世界像素格（粗像素观感），走 world.tb_* 合批。
## 弹体分三级（tier 0 小 / 1 中 / 2 大）：暗描边 → 本色体 → 亮环 → 热白芯；显形期（hold）只画一圈收缩的点环 + 半透明体，出发那一刻才实心——图案先排出来，本身就是预警。
## 预警：颗粒点描边（2×2 点沿轮廓流动）+ 极淡填充 + 从起点长出的进度点阵；不画斜线填充、不画矩形实框。危险色只给预警。
extends RefCounted

const DARK := Color(0.03, 0.03, 0.06, 0.92)


static func _snap(p: Vector2) -> Vector2:
	return p.snapped(Vector2(2.0, 2.0))


static func _dot(w, p: Vector2, c: Color, s := 2.0) -> void:
	var a := _snap(p)
	w.tb_quad(a, a + Vector2(s, 0), a + Vector2(s, s), a + Vector2(0, s), c)


## ---- 弹体（world._draw_ebullets_lobs_shocks 收集 b.mc 的弹后调用）
static func bullets(w, g, list: Array) -> void:
	for b in list:
		w.tb_circle(b.pos + Vector2(0, 2), b.r + 1.0, Color(0, 0, 0, 0.35), 0.45, 10)
	for b in list:
		var p: Vector2 = _snap(b.pos + Vector2(0, -16))
		var c: Color = b.col
		var r: float = float(b.r)
		var hold: float = float(b.get("hold", 0.0))
		if hold > 0.0:
			# 显形：点环从 2.2 倍半径收到 1 倍，体半透明
			var k: float = clampf(float(b.age) / maxf(hold, 0.01), 0.0, 1.0)
			var rr: float = r * lerpf(2.2, 1.0, k)
			var n: int = 6 + int(b.tier) * 2
			for i in n:
				var a: float = TAU * i / n + g.t * 3.0
				_dot(w, p + Vector2.from_angle(a) * rr, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.35 + 0.5 * k))
			w.tb_circle(p, r, Color(c.r, c.g, c.b, 0.25 + 0.35 * k), 1.0, 12)
			continue
		w.tb_circle(p, r + 2.0, DARK, 1.0, 12)
		w.tb_circle(p, r, Color(c.r * 0.85, c.g * 0.85, c.b * 0.85), 1.0, 12)
		w.tb_ring(p, r - 0.5, 1.5, Color(c.r * 1.35, c.g * 1.35, c.b * 1.35, 0.95), 12)
		var core: float = maxf(1.5, r * 0.34)
		w.tb_circle(p, core, Color(1.7, 1.7, 1.6), 1.0, 8)   # 热白芯（>1 进光学辉光）
		if int(b.tier) >= 2:
			# 大弹：前进方向一颗亮点，读得出朝向
			_dot(w, p + b.vel.normalized() * (r - 2.0), Color(1.6, 1.6, 1.6, 0.9))
	w.tb_flush()


## ---- 预警（world._draw_warns_auras 调；telegraph_draw.quiet 已把 skin "mc_*" 从通用填充 / 描边里摘掉）
static func warns(g) -> void:
	var w = g.world
	var drawn := false
	for t in g.warns:
		if not str(t.get("skin", "")).begins_with("mc_"):
			continue
		var beam: bool = t.shape == "line" and (str(t.get("kp", "")) != "" or str(t.act) == "tide_link")
		if t.done:
			if beam:
				_beam_fade(g, w, t)
				drawn = true
			continue
		drawn = true
		if beam:
			_beam_charge(g, w, t)
		var k: float = clampf(t.t / maxf(0.01, t.dur), 0.0, 1.0)
		var c: Color = g.optical.col_danger if g.optical_on else Color(t.col)
		var flow: float = g.t * 40.0
		var al: float = 0.55 + 0.4 * k
		var lock: bool = float(t.get("track", 0.0)) <= 0.0 or t.t >= float(t.track)
		if not lock:
			al *= 0.6   # 还在跟你转：点淡一些；锁定后全亮
		var dc := Color(c.r, c.g, c.b, al)
		var hot := Color(minf(1.5, c.r * 1.5), minf(1.5, c.g * 1.5 + 0.2), minf(1.5, c.b * 1.5 + 0.2), al)
		match t.shape:
			"circle":
				var gy: float = g.combat.GROUND_Y
				var r: float = float(t.r)
				var n: int = clampi(int(TAU * r / 9.0), 16, 72)
				for i in n:
					var a: float = TAU * (float(i) + fmod(flow / 9.0, 1.0)) / n
					_dot(w, t.pos + Vector2(cos(a) * r, sin(a) * r * gy), dc if i % 3 else hot)
				# 进度：内圈点环从圆心长到边
				var rk: float = r * k
				var m: int = clampi(int(TAU * rk / 12.0), 6, 48)
				for i in m:
					var a2: float = TAU * i / m
					_dot(w, t.pos + Vector2(cos(a2) * rk, sin(a2) * rk * gy), Color(c.r, c.g, c.b, 0.3 + 0.3 * k))
				w.tb_circle(t.pos, r, Color(c.r, c.g, c.b, 0.05 + 0.08 * k), gy, 28)
			"line":
				var d := Vector2.from_angle(float(t.ang))
				var nrm: Vector2 = d.orthogonal() * float(t.wid)
				var L: float = float(t.len)
				var x: float = fmod(flow, 10.0)
				while x < L:
					var q: Vector2 = t.pos + d * x
					_dot(w, q + nrm, dc)
					_dot(w, q - nrm, dc)
					x += 10.0
				# 进度：中线上箭头式点列从起点推到 k
				var y := 0.0
				while y < L * k:
					var q2: Vector2 = t.pos + d * y
					_dot(w, q2, hot)
					_dot(w, q2 + nrm * 0.45 - d * 6.0, Color(c.r, c.g, c.b, al * 0.6))
					_dot(w, q2 - nrm * 0.45 - d * 6.0, Color(c.r, c.g, c.b, al * 0.6))
					y += 18.0
				_dot(w, t.pos + d * L, hot, 4.0)
				w.tb_quad(t.pos + nrm, t.pos + d * L + nrm, t.pos + d * L - nrm, t.pos - nrm, Color(c.r, c.g, c.b, 0.04 + 0.07 * k))
			"cone":
				var r3: float = float(t.r)
				var a0: float = float(t.ang) - float(t.half)
				var a1: float = float(t.ang) + float(t.half)
				var n3: int = clampi(int((a1 - a0) * r3 / 9.0), 8, 48)
				for i in n3 + 1:
					_dot(w, t.pos + Vector2.from_angle(lerpf(a0, a1, float(i) / n3)) * r3, dc if i % 3 else hot)
				for s in [a0, a1]:
					var z: float = fmod(flow, 10.0)
					while z < r3:
						_dot(w, t.pos + Vector2.from_angle(s) * z, dc)
						z += 10.0
				var rk3: float = r3 * k
				for i in n3 + 1:
					_dot(w, t.pos + Vector2.from_angle(lerpf(a0, a1, float(i) / n3)) * rk3, Color(c.r, c.g, c.b, 0.3 + 0.3 * k))
				var pts := PackedVector2Array([t.pos])
				for i in 13:
					pts.append(t.pos + Vector2.from_angle(lerpf(a0, a1, i / 12.0)) * r3)
				w.tb_poly(pts, Color(c.r, c.g, c.b, 0.04 + 0.07 * k))
	if drawn:
		w.tb_flush()


## ---- 光束类（主教统一 / 换位连线、蔑死体蚀潮吐息；用户 10-27「蓄力」与「消散」）
## 蓄力：中线光芯从 1 像素粗到 0.6 × 半宽、亮度递增，两侧颗粒向中线内收（越近结算收得越快）；开火瞬间由正式光束（kp_beam）接手
static func _beam_charge(g, w, t: Dictionary) -> void:
	var k: float = clampf(t.t / maxf(0.01, t.dur), 0.0, 1.0)
	var c: Color = g.vfx.boss_color(str(t.owner.type)) if t.owner is Dictionary else Color(t.col)
	var d := Vector2.from_angle(float(t.ang))
	var nrm: Vector2 = d.orthogonal()
	var L: float = float(t.len)
	var hw: float = lerpf(1.0, float(t.wid) * 0.6, k * k)
	var lum: float = 0.6 + 0.9 * k
	w.tb_quad(t.pos + nrm * hw, t.pos + d * L + nrm * hw, t.pos + d * L - nrm * hw, t.pos - nrm * hw, Color(c.r * lum, c.g * lum, c.b * lum, 0.25 + 0.55 * k))
	var n: int = clampi(int(L / 14.0), 6, 60)
	for i in n:
		var u: float = (float(i) + 0.5) / n
		var ph: float = fmod(g.t * (1.2 + 2.8 * k) + float(i) * 0.37, 1.0)   # 0 → 1：从外侧收到中线
		var off: float = float(t.wid) * 1.8 * (1.0 - ph)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		_dot(w, t.pos + d * (u * L) + nrm * off * side, Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, (0.3 + 0.6 * k) * ph))


## 消散：结算后 0.25 秒（预警在 g.warns 里多留的这段），光束变细、按 12 像素断成碎段逐段熄灭，碎段上冒颗粒点
static func _beam_fade(g, w, t: Dictionary) -> void:
	var f: float = clampf((t.t - t.dur) / 0.25, 0.0, 1.0)
	if f >= 1.0:
		return
	var c: Color = g.vfx.boss_color(str(t.owner.type)) if t.owner is Dictionary else Color(t.col)
	var d := Vector2.from_angle(float(t.ang))
	var nrm: Vector2 = d.orthogonal()
	var L: float = float(t.len)
	var hw: float = float(t.wid) * 0.5 * (1.0 - f)
	var seg := 12.0
	var i := 0
	var x := 0.0
	while x < L:
		var keep: float = fmod(float(i) * 0.618, 1.0)   # 固定的熄灭顺序（不用随机）
		if keep > f:
			var a: Vector2 = t.pos + d * x
			var b: Vector2 = t.pos + d * minf(L, x + seg * 0.7)
			w.tb_quad(a + nrm * hw, b + nrm * hw, b - nrm * hw, a - nrm * hw, Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 0.8 * (1.0 - f)))
			_dot(w, a + nrm * (hw + 4.0 + 10.0 * f) * (1.0 if i % 2 == 0 else -1.0), Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.7 * (1.0 - f)))
		x += seg
		i += 1
