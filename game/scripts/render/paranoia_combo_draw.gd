extends RefCounted
## 偏执泡影连携攻势的画面（docs/170）：幻影放的空心泡（无判定）、群愿回响停住时的弹芯闪烁、换幕起手的收拢光环。纯画面，不碰随机数。
## boss_beam._paranoia_top 调用（顶层、世界坐标）


const Bal = preload("res://scripts/core/balance.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")
const A = preload("res://scripts/art.gd")


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
	var tw = g.world   # 泡膜走无贴图批（world.tb_*），一百颗弹也只提交一次
	var skin: bool = Bal.v("render/paranoia_bubble_skin", 1.0) > 0.0   # 0 = 不画泡膜（帧时对照）
	for b in e.get("pc_buls", []):
		if b.life <= 0.0 or not skin:
			continue
		var p2: Vector2 = b.pos + Vector2(0, -16)
		var rr: float = float(b.r) + 6.0
		var held: bool = b.has("p_go_at") and not b.has("p_stop_at")
		if held:
			rr += 3.0
		# 泡膜：极淡内填 + 2 像素淡紫膜 + 左上一道白高光；1 倍画面下要能看出是泡
		# 10-27 用户「泡泡颜色明显一点，太透明」：内填 0.1→0.3、膜 0.7→0.95 加粗到 2.5、内侧再一圈淡色厚膜
		# 10-27 用户「换成紫色泡泡」：淡紫 → 饱和紫（高光仍白）
		tw.tb_circle(p2, rr, Color(0.58, 0.2, 0.95, 0.34))
		tw.tb_ring(p2, rr - 2.0, 3.0, Color(0.66, 0.26, 1.0, 0.4))
		tw.tb_ring(p2, rr, 2.5, Color(0.82, 0.45, 1.0, 1.0 if held and blink else 0.95))
		tw.tb_arc(p2, rr - 3.5, PI * 1.05, PI * 1.5, 2.0, Color(1.0, 0.97, 1.0, 0.95), 5)
	tw.tb_flush()
	# 幻影：外缘一圈抖动的冷色虚边（真身没有），和更透的本体一起认
	for sl in e.get("decoys", []):
		var o = sl.get("o")
		if o == null or o.dead:
			continue
		var cpos: Vector2 = o.pos + Vector2(0, -o.r * 0.6)
		for q in 18:
			if (q + int(g.t * 12.0)) % 3 == 0:
				continue
			var a0: float = q * TAU / 18.0
			var rq: float = o.r * 1.15 + 3.0 * sin(g.t * 11.0 + q * 1.9)
			g.draw_arc(cpos, rq, a0, a0 + TAU / 22.0, 3, Color(0.7, 0.9, 1.0, 0.55), 1.5)
	# 幻象冲撞（用户 10-28「冲锋只是平移，加动态」）：预告期渐显并上下浮动；最后 0.35 秒向后蓄势（后退 + 压扁）；
	# 冲刺中沿方向拉长、身后 4 个渐淡残影、本体轻微抖动；地面层另画泡沫通道（draw_ground）
	var frames: int = A.enemy_frames(str(e.tex), 2)
	var foot: bool = g.foot_anchor.has(str(e.tex))
	var sc: float = g.world.enemy_scale(e) / A.hires_of(g.tex.get(str(e.tex)))
	var anc: Vector2 = Vector2(0.5, 1.0) if foot else Vector2(0.5, 0.5)
	var foot_off: Vector2 = Vector2(0, float(e.r) * 0.8 + 3.0 * g.PX) if foot else Vector2.ZERO
	for ln in e.get("pc_rush", []):
		if g.t < float(ln.t0):
			continue
		var d: Vector2 = ln.d
		var horiz: bool = absf(d.x) >= absf(d.y)
		var fr: int = int(g.t * 6.0) % frames
		var flip: bool = d.x < 0.0
		if g.t < float(ln.t_go):
			var fade: float = clampf((g.t - float(ln.t0)) / 0.4, 0.0, 1.0)
			var left: float = float(ln.t_go) - g.t
			var wind: float = clampf(1.0 - left / 0.35, 0.0, 1.0)   # 0 → 1：蓄势
			var p: Vector2 = ln.pos - d * 26.0 * wind * wind + Vector2(0, sin(g.t * 4.0 + float(ln.t0)) * 3.0 * (1.0 - wind))
			# 蓄势时沿冲刺方向压扁、垂直方向鼓起；抖动随蓄势加剧
			var k: float = 1.0 - 0.18 * wind
			var sq: Vector2 = Vector2(k, 2.0 - k) if horiz else Vector2(2.0 - k, k)
			p += Vector2(sin(g.t * 60.0), cos(g.t * 53.0)) * 1.5 * wind
			g.vfx.spr(str(e.tex), frames, fr, p + foot_off, sc, flip, Color(0.7, 0.85, 1.3, 0.5 * fade + 0.2 * wind), anc, sq)
			continue
		# 冲刺中：残影（越远越淡、越小），本体拉长
		var stretch: Vector2 = Vector2(1.3, 0.82) if horiz else Vector2(0.85, 1.25)
		for k2 in [4, 3, 2, 1]:
			var gp: Vector2 = ln.pos - d * 30.0 * k2
			var ga: float = 0.28 * (1.0 - k2 / 5.0)
			g.vfx.spr(str(e.tex), frames, fr, gp + foot_off, sc * (1.0 - 0.04 * k2), flip, Color(0.6, 0.45, 1.2, ga), anc, stretch)
		var jit: Vector2 = d.orthogonal() * sin(g.t * 45.0) * 2.0
		g.vfx.spr(str(e.tex), frames, fr, ln.pos + jit + foot_off, sc, flip, Color(0.75, 0.88, 1.35, 0.62), anc, stretch)
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


## 地面层：幻象冲撞的通道（暗红低填充 + 两侧泡沫边，冲出后淡去）
static func _rush_lanes(g, e: Dictionary) -> void:
	for ln in e.get("pc_rush", []):
		if g.t < float(ln.t0):
			continue
		var k: float = clampf((g.t - float(ln.t0)) / maxf(0.01, float(ln.t_go) - float(ln.t0)), 0.0, 1.0)
		var d: Vector2 = ln.d
		var n: Vector2 = d.orthogonal()
		var hw: float = 34.0
		var a: Vector2 = ln.a
		var b: Vector2 = ln.a + d * 780.0
		g.draw_colored_polygon(PackedVector2Array([a + n * hw, b + n * hw, b - n * hw, a - n * hw]), Color(0.42, 0.04, 0.1, 0.1 + 0.14 * k))
		var cnt: int = int(780.0 / 14.0)
		for side in [-1.0, 1.0]:
			for i in cnt:
				var br: float = 1.5 + 1.5 * absf(sin(i * 1.3 + side))
				g.world.tb_ring(a + d * (i * 14.0 + fmod(g.t * 40.0, 14.0)) + n * (hw - br) * side, br, 1.0, Color(0.95, 0.35, 0.45, 0.3 + 0.5 * k), 6)
		# 方向箭头：三个 V 形沿通道流动
		for q in 3:
			var x: float = fmod(g.t * 160.0 + q * 260.0, 780.0)
			var p: Vector2 = a + d * x
			g.world.tb_line(p - d * 10.0 + n * 10.0, p, Color(1.0, 0.6, 0.65, 0.5 * k), 2.0)
			g.world.tb_line(p - d * 10.0 - n * 10.0, p, Color(1.0, 0.6, 0.65, 0.5 * k), 2.0)
	g.world.tb_flush()


## 地面层（boss_beam._paranoia_ground）：凝视预警。形状 = 判定（pos 起、长 len、半宽 wid 的矩形）；
## 暗红低填充，两条长边是一串大小不一的小泡（随进度变亮、沿光束方向缓慢漂），锁定后中线收成一道细亮线
static func draw_ground(g, e: Dictionary) -> void:
	_rush_lanes(g, e)
	for w in g.warns:
		if w.done or not is_same(w.owner, e):
			continue
		if str(w.get("skin", "")) == "howl":
			_howl_warn(g, w)
			continue
		if str(w.get("skin", "")) != "gaze":
			continue
		var k: float = clampf(w.t / maxf(0.01, w.dur), 0.0, 1.0)
		var d := Vector2.from_angle(w.ang)
		var n: Vector2 = d.orthogonal()
		var wid: float = float(w.wid)
		var ln: float = float(w.len)
		var a: Vector2 = w.pos
		var locked: bool = w.t >= float(w.get("track", 0.0))
		g.draw_colored_polygon(PackedVector2Array([a + n * wid, a + d * ln + n * wid, a + d * ln - n * wid, a - n * wid]),
			Color(0.42, 0.04, 0.1, 0.12 + 0.12 * k))
		var step: float = 13.0
		var cnt: int = int(ln / step)
		var drift: float = fmod(g.t * 30.0, step)
		for side in [-1.0, 1.0]:
			for i in cnt:
				var x: float = i * step + drift
				if x > ln:
					break
				var br: float = 1.5 + 1.5 * absf(sin(i * 1.7 + side))
				var pp: Vector2 = a + d * x + n * (wid - br) * side
				g.world.tb_ring(pp, br, 1.0, Color(0.95, 0.35, 0.45, 0.35 + 0.5 * k), 6)
		# 蓄力：中线从 1 像素长到半宽的 0.6，亮度递增（锁定后更亮）；发射点有颗粒向内收
		var core_w: float = lerpf(1.0, wid * 0.6, pow(k, 1.5))
		var cb: float = (0.25 + 0.55 * k) * (1.2 if locked else 1.0)
		g.world.tb_line(a, a + d * ln, Color(0.95, 0.75, 1.0, minf(0.9, cb)), core_w)
		var gr = BossBeam.grains(g)
		if gr != null and k > 0.2 and BossBeam.take(g, 2) == 2:
			for q in 2:
				var off: Vector2 = Vector2.from_angle(g.t * 7.0 + q * PI) * (40.0 * (1.0 - k) + 14.0)
				gr.push("mote_in", a + Vector2(0, -18) + off, -off, Color(0.95, 0.82, 1.0))
		g.world.tb_flush()


## 呼号预警：扇形（pos、ang、半角 half、半径 r，形状 = 判定）暗红低填充 + 外弧一串小泡；进度用向外推的第二道泡弧表示
static func _howl_warn(g, w: Dictionary) -> void:
	var k: float = clampf(w.t / maxf(0.01, w.dur), 0.0, 1.0)
	var pts := PackedVector2Array([w.pos])
	for q in 17:
		pts.append(w.pos + Vector2.from_angle(w.ang - w.half + w.half * 2.0 * q / 16.0) * w.r)
	g.draw_colored_polygon(pts, Color(0.42, 0.04, 0.1, 0.12 + 0.12 * k))
	var n: int = int(w.r * w.half * 2.0 / 12.0)
	for i in n + 1:
		var a: float = w.ang - w.half + w.half * 2.0 * i / maxf(1.0, n)
		var br: float = 1.5 + 1.5 * absf(sin(i * 1.7))
		g.world.tb_ring(w.pos + Vector2.from_angle(a) * (w.r - br), br, 1.0, Color(0.95, 0.35, 0.45, 0.35 + 0.5 * k), 6)
		if i % 2 == 0:
			g.world.tb_ring(w.pos + Vector2.from_angle(a) * w.r * k, 1.5, 1.0, Color(1.0, 0.55, 0.6, 0.6 * k), 6)
	for sd in [-1.0, 1.0]:
		var d := Vector2.from_angle(w.ang + w.half * sd)
		g.world.tb_line(w.pos, w.pos + d * w.r, Color(0.95, 0.35, 0.45, 0.3 + 0.4 * k), 1.5)
	g.world.tb_flush()
