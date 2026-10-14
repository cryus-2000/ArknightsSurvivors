## 预警填充层绘制（docs/101 B2，10-15 从 boss_ai.draw_warns 搬来）：world._draw_warns_auras 在地面层调 draw_fills(g)。
## 只读 g.warns 与画面参数，不写状态、不碰随机数
extends RefCounted

const UI = preload("res://scripts/ui.gd")


## 预警绘制（地面填充层；轮廓 / 出口 / 端盖在 world.draw_warn_outlines）：结算瞬间闪白。
## 填充样式按 docs/95 §0.2 全局固定，玩家看形状就知道躲法、看颜色就知道是谁放的：
## ① 落点圈 实填（主色 100%）；② 直线 斜条纹（主色 70%，条纹随结算进度流向终点）；③ 扇形 暗填 + 亮边（45% 填充、外弧 130% 亮）；
## ④ 缺口环 空心（只画线、无填充）；0 预告 低亮度（25%，不发光）；⑤ 必须冲刺 同 ①（屏幕级提示在 HUD）
static func draw_fills(g) -> void:
	for w in g.warns:
		if w.get("dim", false):
			continue   # 打不到主控的杂兵预警只画淡轮廓（world.classify_tells / draw_warn_outlines，可读性 1.1.1，界面与美术）
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var c: Color = w.col
		var pulse: float = 0.5 + 0.5 * sin(g.t * 14.0)
		var fa := 0.10 + 0.14 * k
		var oa := 0.55 + 0.35 * pulse * k
		var st: int = int(w.get("style", 1))
		if w.done:
			var f: float = clampf(1.0 - (w.t - w.dur) / 0.25, 0.0, 1.0)
			c = Color(2.0, 2.0, 2.0)
			fa = 0.45 * f
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
		var fill := Color(c.r, c.g, c.b, fa * 1.3)
		var line := Color(c.r, c.g, c.b, oa)
		var bright := Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, oa)
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
