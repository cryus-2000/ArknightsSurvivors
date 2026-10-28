extends RefCounted
## 最终 Boss 破绽的画面提示（用户 10-28「最终 Boss 的破绽字都不要」）：脚下一圈慢呼吸的金色地面环 + 剩余时间弧（满 → 空）。
## 四只最终 Boss（spawner.is_final_boss_type）共用一套；boss/break_text_final 1 = 恢复「破绽」字时也照画。纯画面，不碰随机数。
## boss_beam.draw_top 调用（顶层、世界坐标）


const GOLD := Color(1.0, 0.85, 0.45)


static func draw(g) -> void:
	for e in g.bosses:
		if e.dead or float(e.get("break_t", 0.0)) <= 0.0 or not g.spawner.is_final_boss_type(str(e.type)):
			continue
		var bt: float = float(e.break_t)
		var frac: float = clampf(bt / maxf(0.1, float(e.get("brk_len", bt))), 0.0, 1.0)
		var r: float = float(e.r) * 1.5 + 3.0 * sin(g.t * 3.0)
		g.draw_set_transform(e.pos, 0.0, Vector2(1.0, g.world.ground_y()))
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0, 0, 0, 0.45), 7.0)
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(GOLD.r, GOLD.g, GOLD.b, 0.3), 4.0)
		g.draw_arc(Vector2.ZERO, r, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, Color(GOLD.r, GOLD.g, GOLD.b, 1.0), 3.5)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
