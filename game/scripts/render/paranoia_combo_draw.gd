extends RefCounted
## 偏执泡影连携攻势的画面（docs/170）：幻影放的空心泡（无判定）、群愿回响停住时的弹芯闪烁、换幕起手的收拢光环。纯画面，不碰随机数。
## boss_beam._paranoia_top 调用（顶层、世界坐标）


static func draw_top(g, e: Dictionary) -> void:
	var fakes: Array = e.get("pc_fakes", [])
	for f in fakes:
		# 空心：只有一圈淡紫细边 + 极淡内填，和实心弹（亮芯 + 暗描边）一眼分开
		var p: Vector2 = f.pos + Vector2(0, -16)
		var a: float = clampf(float(f.life) / 0.6, 0.0, 1.0) * 0.55
		g.draw_circle(p, float(f.r), Color(0.78, 0.62, 1.0, a * 0.12))
		g.draw_arc(p, float(f.r), 0.0, TAU, 14, Color(0.85, 0.72, 1.0, a), 1.5)
	# 她的弹都是泡：公共管线画的亮芯 + 暗描边外面再套一层淡紫泡膜和左上高光；停住的花瓣泡膜鼓起、一明一暗（0.5 秒后对准你射出）
	var blink: bool = int(g.t * 10.0) % 2 == 0
	for b in e.get("pc_buls", []):
		if b.life <= 0.0:
			continue
		var p2: Vector2 = b.pos + Vector2(0, -16)
		var rr: float = float(b.r) + 4.0
		var held: bool = b.has("p_go_at") and not b.has("p_stop_at")
		if held:
			rr += 3.0
		g.draw_arc(p2, rr, 0.0, TAU, 14, Color(0.82, 0.7, 1.0, 0.85 if held and blink else 0.45), 1.5)
		if float(b.r) >= 8.0:
			g.draw_arc(p2, rr - 2.5, PI * 1.05, PI * 1.45, 4, Color(1.0, 0.97, 1.0, 0.8), 1.5)
	# 千目注视：杏仁形的眼，0.25 秒内睁开；开过枪的那只瞳孔短暂放亮
	for ey in e.get("pc_eyes", []):
		var ot: float = g.t - float(ey.open)
		if ot < 0.0 or g.t > float(ey.close):
			continue
		var op: float = clampf(ot / 0.25, 0.0, 1.0) * clampf((float(ey.close) - g.t) / 0.25, 0.0, 1.0)
		var c: Vector2 = ey.pos + Vector2(0, -16)
		var w: float = 15.0
		var hgt: float = 7.0 * op
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		for i in 9:
			var x: float = lerpf(-w, w, i / 8.0)
			var yk: float = 1.0 - pow(x / w, 2.0)
			top.append(c + Vector2(x, -hgt * yk))
			bot.append(c + Vector2(x, hgt * yk))
		var lid := Color(0.2, 0.08, 0.3, 0.75)
		g.draw_polyline(top, lid, 4.0)
		g.draw_polyline(bot, lid, 4.0)
		g.draw_polyline(top, Color(0.85, 0.72, 1.0, 0.9), 1.5)
		g.draw_polyline(bot, Color(0.85, 0.72, 1.0, 0.9), 1.5)
		if op > 0.5:
			var hot: bool = g.t - float(ey.get("fired", -9.0)) < 0.15
			var to_p: Vector2 = (g.ppos - ey.pos).normalized() * 3.0
			g.draw_circle(c + to_p, 3.5, Color(1.0, 0.95, 1.0, 0.95) if hot else Color(0.75, 0.55, 1.0, 0.9))
	# 换幕起手 0.9 秒：收拢的双环（外 → 内）
	var dt: float = g.t - float(e.get("pc_gather_t", -99.0))
	if dt >= 0.0 and dt < 0.9:
		var k: float = dt / 0.9
		var r: float = lerpf(e.r * 4.0, e.r * 1.2, k)
		var c := Color(0.92, 0.85, 1.0, 0.6 * (1.0 - k))
		g.draw_arc(e.pos + Vector2(0, -10), r, 0.0, TAU, 48, c, 2.0)
		g.draw_arc(e.pos + Vector2(0, -10), r * 0.8, 0.0, TAU, 40, Color(c.r, c.g, c.b, c.a * 0.5), 1.5)
