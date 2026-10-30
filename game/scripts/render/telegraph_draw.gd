## 预警填充层绘制（docs/101 B2，10-15 从 boss_ai.draw_warns 搬来）：world._draw_warns_auras 在地面层调 draw_fills(g)。
## 只读 g.warns 与画面参数，不写状态、不碰随机数
extends RefCounted

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const SaintDraw = preload("res://scripts/render/saint_draw.gd")
const LaserDraw = preload("res://scripts/render/laser_draw.gd")


## 预警绘制（地面填充层；轮廓 / 出口 / 端盖在 world.draw_warn_outlines）：结算瞬间闪白。
## 填充样式按 docs/95 §0.2 全局固定，玩家看形状就知道躲法、看颜色就知道是谁放的：
## ① 落点圈 实填（主色 100%）；② 直线 斜条纹（主色 70%，条纹随结算进度流向终点）；③ 扇形 暗填 + 亮边（45% 填充、外弧 130% 亮）；
## ④ 缺口环 空心（只画线、无填充）；0 预告 低亮度（25%，不发光）；⑤ 必须冲刺 同 ①（屏幕级提示在 HUD）
## 10-22b 用户：普通怪（非 Boss）远程攻击（直线射击 shot / 扇形连射 extra_volley）开火前不再画预警；预警本身照常计时、到点照常开火（纯画面）
static func quiet(w: Dictionary) -> bool:
	var o = w.get("owner")
	if str(w.get("skin", "")).begins_with("mc_"):
		return true   # 塑路者 / 接潮组的颗粒点预警（render/mid_card_draw，docs/170）
	# skin gaze / howl：偏执泡影凝视、呼号自己画预警（render/paranoia_combo_draw.gd，docs/170）
	return w.get("act", "") == "final_attack" or knight_line(w) or w.get("skin", "") in ["gaze", "howl"] or o is Dictionary and not o.get("boss", false) and str(w.get("act", "")) in ["shot", "extra_volley"]


## 最后的骑士的线形预警（冲锋 / 再冲锋 / 寒冷追击 / 冰线 / 掷枪）：10-27 改由 boss_attack_draw 画冰裂纹（暗红低填充 + 冰裂勾边 + 路线裂纹蔓延），
## 这里和 world.draw_warn_outlines 都跳过（不画斜线、箭头和结算白闪）。范围 = 判定矩形不变；render/knight_frost_tell = 0 恢复旧画法
static func knight_line(w: Dictionary) -> bool:
	var o = w.get("owner")
	return w.get("shape", "") == "line" and o is Dictionary and o.get("type", "") == "knight_boss" and str(w.get("act", "")) in ["dash", "frost_track", "shot"] and Bal.v("render/knight_frost_tell", 1.0) > 0.0


## 统一激光的预警（TA 审阅 docs/208 H3「预警线到实线要有明确转换」，照伊莎玛拉 ishar_tell_draw._charge；render/laser_v2 缺省 1）：
## 激光类直线预警（act beam）不再画宽矩形斜纹 + 轮廓，只画一条 2 像素瞄准线（危险色，亮度随读条递增）+ 发射口一颗越来越大的光点；
## 最后 0.15 秒瞄准线转白、光点最亮 = 马上开火。开火后才出现有宽度的光束（laser_draw），预警和实线一眼分开。只读不写
static func laser_warn(w: Dictionary) -> bool:
	return w.get("shape", "") == "line" and str(w.get("act", "")) == "beam" and Bal.v("render/laser_v2", 1.0) > 0.0


static func _laser_aim(g, w: Dictionary) -> void:
	var k: float = clampf(w.t / maxf(0.001, w.dur), 0.0, 1.0)
	var kk: float = k * k
	var c: Color = g.optical.col_danger if g.optical_on else w.col
	var d := Vector2.from_angle(w.ang)
	var b: Vector2 = w.pos + d * float(w.len)
	var hot: bool = float(w.dur) - float(w.t) < 0.15
	g.draw_line(w.pos, b, Color(1, 1, 1, 0.9) if hot else Color(c.r, c.g, c.b, 0.4 + 0.45 * kk), 2.0)
	LaserDraw.dot(g, w.pos, 3.0 + float(w.wid) * 0.3 * kk, c, 0.4 + 0.6 * kk)


## 预警形状的多边形（世界坐标；圆按贴地透视压扁）
static func _poly(g, w: Dictionary, scale_k := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match w.shape:
		"circle":
			for q in 28:
				var a: float = TAU * q / 28.0
				pts.append(w.pos + Vector2(cos(a) * w.r, sin(a) * w.r * g.combat.GROUND_Y) * scale_k)
		"line":
			var d := Vector2.from_angle(w.ang)
			var n: Vector2 = d.orthogonal() * float(w.wid) * scale_k
			pts.append_array([w.pos + n, w.pos + d * w.len + n, w.pos + d * w.len - n, w.pos - n])
		"cone":
			pts.append(w.pos)
			for q in 17:
				pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * q / 16.0) * w.r * scale_k)
	return pts


## 斜线填充：45° 斜线按 2 世界像素格对齐、随时间缓慢流动，裁进预警形状；进度 k 用内层更密的斜线表示（结算前填满）
static func _hatch(g, w: Dictionary, c: Color, a: float, k: float) -> void:
	var poly := _poly(g, w)
	if poly.size() < 3:
		return
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	var gap: float = maxf(10.0, roundf(maxf(bb.size.x, bb.size.y) / 40.0 / 2.0) * 2.0)
	var off: float = fmod(g.t * 12.0 * Bal.v("render/warn_hatch_flow", 1.0), gap)   # docs/139 §8：0 = 斜线不流动
	var col := Color(c.r, c.g, c.b, a)
	var x: float = bb.position.x - bb.size.y + off
	while x < bb.end.x:
		var a0 := Vector2(x, bb.position.y)
		var a1 := Vector2(x + bb.size.y, bb.end.y)
		for seg in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a0, a1]), poly):
			g.draw_polyline(seg, col, 2.0)
		x += gap
	if k > 0.05:
		var inner := _poly(g, w, k) if w.shape != "line" else _poly_line_k(w, k)
		if inner.size() >= 3:
			g.draw_colored_polygon(inner, Color(c.r, c.g, c.b, a * 0.35))


static func _poly_line_k(w: Dictionary, k: float) -> PackedVector2Array:
	var d := Vector2.from_angle(w.ang)
	var n: Vector2 = d.orthogonal() * float(w.wid)
	return PackedVector2Array([w.pos + n, w.pos + d * w.len * k + n, w.pos + d * w.len * k - n, w.pos - n])


static func draw_fills(g) -> void:
	for w in g.warns:
		if w.get("saint_beam", false):
			if not w.done:
				SaintDraw.charge(g, w)   # 圣徒光束蓄力（docs/171 §7）：代替斜纹填充与轮廓；结算白闪也不画（由消散接上）
			continue
		if w.get("dim", false) or quiet(w):
			continue   # 打不到主控的杂兵预警只画淡轮廓（world.classify_tells / draw_warn_outlines，可读性 1.1.1，界面与美术）
		if preload("res://scripts/render/ishar_tell_draw.gd").owns(w):
			continue   # 伊莎玛拉地面预警由 ishar_tell_draw 画（docs/170）
		if laser_warn(w):
			if not w.done:
				_laser_aim(g, w)   # 统一激光预警（docs/208 H3）：细瞄准线 + 发射口光点，代替斜纹填充与轮廓
			continue
		if w.get("act", "") == "izu_wave" and g.optical_on:
			continue   # 伊祖米克全场震撼 / 分享：预警浪纹与结算海浪由 izumik_attack_draw 画（docs/170），不铺整屏斜线、结算不整屏白闪
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var c: Color = w.col
		if g.optical_on:
			c = g.optical.col_danger   # 光学观感颜色语言（10-23）：敌方预警统一危险色，黑潮时随之偏红
		var pulse: float = 0.5 + 0.5 * sin(g.t * 14.0)
		var fa := 0.10 + 0.14 * k
		var oa := 0.55 + 0.35 * pulse * k
		var st: int = int(w.get("style", 1))
		if w.done:
			var f: float = clampf(1.0 - (w.t - w.dur) / 0.25, 0.0, 1.0)
			c = Color(2.0, 2.0, 2.0)
			fa = 0.45 * f * Bal.v("render/warn_flash_fill", 1.0)   # docs/139 §8：结算白闪的整片白填充（0 = 只闪轮廓）
			oa = 0.9 * f
			k = 1.0
		# 颜色不再乘 1.7–2.0：乘完在灯光里褪成白色 / 粉彩，色相丢失（docs/48 全局 ④）；亮度靠 alpha 和白芯（world.draw_warn_outlines）
		if st == 0:
			# 预告（如注亡拟嗣生成点、迫近）：没有伤害，压低亮度，别和伤害圈抢眼
			fa *= 0.25
			oa *= 0.45
		elif st == 2:
			fa *= 0.7
		elif st == 3:
			fa *= 0.45
		fa *= g.world.tell_fill   # 后期降噪（render/declutter tell_fill_k，缺省 1）：填充减淡、轮廓（world.draw_warn_outlines）加粗
		# 伊祖米克（docs/170）：预警不铺斜线，退回低填充 + 描边；补充攻击的填充与材质边已由 boss_attack_draw 画
		var izu: bool = w.get("owner") is Dictionary and str(w.owner.get("type", "")) == "izumik"
		if izu and w.get("act", "") == "final_attack":
			continue
		var hatched: bool = g.optical_on and g.optical.fx1 and not w.done and not izu
		if hatched:
			if st != 0 and st != 4:
				_hatch(g, w, c, clampf(fa * 4.2, 0.4, 0.85), k)   # 光学观感 ④（10-23）：地面预警一律斜线填充 + 闪烁描边（world.draw_warn_outlines），危险色
		var fill := Color(c.r, c.g, c.b, fa * 1.3)
		var line := Color(c.r, c.g, c.b, oa)
		var bright := Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, oa)
		if not hatched:
			match w.shape:
				"circle":
					g.draw_set_transform(w.pos, 0.0, Vector2(1.0, g.combat.GROUND_Y))
					if st == 4 and not w.done:
						# ④ 空心环：只画线；进度用一圈从内向外长的细环表示
						g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 48, line, 2.5)
						g.draw_arc(Vector2.ZERO, maxf(2.0, w.r * k), 0.0, TAU, 40, Color(c.r, c.g, c.b, oa * 0.5), 1.5)
					else:
						g.draw_circle(Vector2.ZERO, w.r, fill)
						g.draw_circle(Vector2.ZERO, w.r * k, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
						g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 40, line, 2.5)
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				"line":
					g.draw_set_transform(w.pos, w.ang, Vector2.ONE)
					g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), fill)
					if st == 2 and not w.done:
						# ② 斜条纹：间距 28，随结算进度向终点流动；总数按线长封顶（820 长约 30 条）
						var sc := Color(c.r, c.g, c.b, fa * 1.4)
						var off: float = fmod(k * 140.0 + g.t * 40.0, 28.0)
						var x: float = off - w.wid
						while x < w.len:
							g.draw_line(Vector2(x, -w.wid), Vector2(x + w.wid, w.wid), sc, 3.0)
							x += 28.0
					else:
						g.draw_rect(Rect2(0.0, -w.wid * k, w.len, w.wid * 2.0 * k), Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
					g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), line, false, 2.0)
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				"cone":
					var pts := PackedVector2Array([w.pos])
					var pts2 := PackedVector2Array([w.pos])
					for q in 17:
						var a: float = w.ang - w.half + w.half * 2.0 * q / 16.0
						var dv := Vector2.from_angle(a)
						pts.append(w.pos + dv * w.r)
						pts2.append(w.pos + dv * w.r * k)
					g.draw_colored_polygon(pts, fill)
					if k > 0.05:
						g.draw_colored_polygon(pts2, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * (1.0 if st == 3 else 1.6)))
					pts.append(w.pos)
					g.draw_polyline(pts, line, 2.5)
					if st == 3 and not w.done:
						g.draw_arc(w.pos, w.r, w.ang - w.half, w.ang + w.half, 20, bright, 3.5)   # ③ 亮边：外弧 130% 亮
		# 连发序号（凝视 1 / 2 / 3、叠影圈号）：circle 画在圈心上方，line / cone 画在起点
		var sq: int = int(w.get("seq_no", 0))
		if sq > 0 and not w.done:
			var sp: Vector2 = w.pos + (Vector2(0, -w.r * g.combat.GROUND_Y - 18.0) if w.shape == "circle" else Vector2.from_angle(w.ang) * 26.0 + Vector2(0, -22.0))
			g.draw_circle(sp, 9.0, Color(0.02, 0.02, 0.05, 0.8))
			g.draw_arc(sp, 9.0, 0.0, TAU, 16, Color(1, 1, 1, 0.9), 1.5)
			UI.text(g, g.font, sp + Vector2(-9.0, 5.0), str(sq), 12, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 18.0)
