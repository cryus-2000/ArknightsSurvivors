extends RefCounted
## 偏执泡影连携攻势的画面（docs/170）：幻影放的空心泡（无判定）、群愿回响停住时的弹芯闪烁、换幕起手的收拢光环。纯画面，不碰随机数。
## boss_beam._paranoia_top 调用（顶层、世界坐标）


const Bal = preload("res://scripts/core/balance.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")
const A = preload("res://scripts/art.gd")


static func draw_top(g, e: Dictionary) -> void:
	if e.get("gate_hold", false):
		_hard_film(g, e)
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
	var p2_look: bool = e.phase == 2
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
		if p2_look:
			# 二阶段「海嗣滴」（用户 10-28：二阶段换主色和弹体）：青蓝水滴形，尖端朝飞行方向，深色描边 + 亮芯；
			# 不透明，盖住公共管线画的紫色圆芯
			var fwd: Vector2 = b.vel.normalized() if b.vel.length_squared() > 1.0 else Vector2.RIGHT
			var side: Vector2 = fwd.orthogonal()
			var rb: float = float(b.r) + 3.0
			var pts := PackedVector2Array()
			for q in 10:
				var a: float = PI * 0.5 + PI * q / 9.0
				pts.append(p2 - fwd * rb * 0.2 + (side * cos(a) + fwd * sin(a)) * rb)
			pts.append(p2 + fwd * rb * 2.0)
			tw.tb_flush()
			g.draw_colored_polygon(pts, Color(0.02, 0.12, 0.16, 1.0))
			var inner := PackedVector2Array()
			for pt in pts:
				inner.append(p2 + (pt - p2) * 0.78)
			g.draw_colored_polygon(inner, Color(0.3, 0.85, 0.95, 1.0 if held and blink else 0.92))
			tw.tb_circle(p2 + fwd * 1.5, 2.5, Color(0.9, 1.0, 1.0, 1.0))
			continue
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
	# 力竭（破绽前 TIRE 秒）：身周一圈泡膜收瘪；破绽中的金环 + 倒计时弧是四只最终 Boss 共用的（render/break_ring）
	var tire_at: float = float(e.get("pc_tire_at", 0.0))
	var fp: Vector2 = e.pos + Vector2(0, -10)
	if tire_at > g.t:
		var kt: float = 1.0 - (tire_at - g.t) / 0.6
		var rt: float = lerpf(e.r * 2.4, e.r * 1.1, kt * kt)
		g.draw_arc(fp, rt, 0.0, TAU, 40, Color(core_col(e).r, core_col(e).g, core_col(e).b, 0.55 * (1.0 - kt) + 0.15), 2.0)
	_tide_tells(g, e)
	# 换幕起手 0.9 秒：收拢的双环（外 → 内）
	var dt: float = g.t - float(e.get("pc_gather_t", -99.0))
	if dt >= 0.0 and dt < 0.9:
		var k: float = dt / 0.9
		var r: float = lerpf(e.r * 4.0, e.r * 1.2, k)
		var c := Color(0.92, 0.85, 1.0, 0.6 * (1.0 - k))
		g.draw_arc(e.pos + Vector2(0, -10), r, 0.0, TAU, 48, c, 2.0)
		g.draw_arc(e.pos + Vector2(0, -10), r * 0.8, 0.0, TAU, 40, Color(c.r, c.g, c.b, c.a * 0.5), 1.5)


## 地面层：幻象冲撞的通道（暗红低填充 + 两侧泡沫边，冲出后淡去）
static func core_col(e: Dictionary) -> Color:
	return Color(0.35, 0.9, 1.0) if e.phase == 2 else Color(0.85, 0.55, 1.0)


## 起手提示（用户 10-28「有些招式该给提醒」）：弹幕段起手前 WINDUP 秒——环形招从脚下向外扩一圈虚线环，
## 瞄准招朝队长拉一道渐亮的点线；颜色同本阶段弹色（不是红色危险预警，不挡视线）
const RING_TELLS := ["无声波环", "偏执双旋", "沉浮双层", "侵蚀帘幕"]
const AIM_TELLS := ["群愿回响", "环流狙击", "镜影齐射"]


static func _emit_tells(g, e: Dictionary) -> void:
	var c: Color = core_col(e)
	for em in e.get("pc_emit", []):
		var wind: float = float(em.get("wind", 0.55))
		var left: float = float(em.t0) - g.t
		if left <= 0.0 or left > wind:
			continue
		var k: float = 1.0 - left / wind
		var n: String = str(em.name)
		if n == "潮涌环":
			continue   # 画在顶层（draw_top → _tide_tells），不被本体和队长挡住
		if n in RING_TELLS:
			var r: float = lerpf(e.r * 1.2, e.r * 3.2, k)
			for q in 16:
				var a0: float = TAU * q / 16.0 + g.t * 0.8
				g.draw_arc(e.pos + Vector2(0, -10), r, a0, a0 + TAU / 32.0, 4, Color(c.r, c.g, c.b, 0.25 + 0.5 * k), 2.0)
		elif n in AIM_TELLS:
			var d: Vector2 = (g.ppos - e.pos).normalized()
			for q in 10:
				var p: Vector2 = e.pos + Vector2(0, -16) + d * (30.0 + q * 26.0 * k)
				g.world.tb_ring(p, 2.0, 1.0, Color(c.r, c.g, c.b, (0.2 + 0.6 * k) * (1.0 - q / 12.0)), 6)
	g.world.tb_flush()


## 潮涌环起手（用户 10-28「提醒明显一点」）：1 秒内脚下画出和真水环同形的地面椭圆环（同粗细、同青蓝），
## 从脚下涨到 140 并一明一暗；第一道缺口（朝队长）留空并在两侧立亮标、外侧一个向外的 V；
## 后两道缺口的位置（依次转开 1.1 弧度）只画淡标。缺口方向在出手那刻按队长位置定，这里按当前位置预示
static func _tide_tells(g, e: Dictionary) -> void:
	for em in e.get("pc_emit", []):
		if str(em.name) != "潮涌环":
			continue
		var wind: float = float(em.get("wind", 0.55))
		var left: float = float(em.t0) - g.t
		if left > 0.0 and left <= wind:
			_tide_tell(g, e, em, 1.0 - left / wind)


static func _tide_tell(g, e: Dictionary, em: Dictionary, k: float) -> void:
	var c := Color(0.35, 0.9, 1.0)
	var o: Vector2 = e.pos
	var aim: float = (g.ppos + Vector2(0, -14) - o).angle()
	var gy: float = g.world.ground_y()
	var r: float = lerpf(60.0, 230.0, 1.0 - pow(1.0 - k, 2.0))
	var blink: float = 0.7 + 0.3 * sin(g.t * 18.0)
	var a: float = (0.5 + 0.5 * k) * blink
	var half: float = 0.42
	g.draw_set_transform(o, 0.0, Vector2(1.0, gy))
	# 环身：深色底 + 青蓝 + 白芯，缺口处留空
	var s0: float = aim + half
	var s1: float = aim + TAU - half
	g.draw_arc(Vector2.ZERO, r - 10.0, s0, s1, 64, Color(c.r, c.g, c.b, 0.22 * a), 14.0)
	g.draw_arc(Vector2.ZERO, r, s0, s1, 64, Color(0, 0, 0, 0.55 * a), 9.0)
	g.draw_arc(Vector2.ZERO, r, s0, s1, 64, Color(c.r, c.g, c.b, a), 5.0)
	g.draw_arc(Vector2.ZERO, r, s0, s1, 64, Color(1, 1, 1, 0.85 * a), 2.0)
	# 向她收拢的两道细水纹（「潮在涨」）
	for q in 2:
		var rq: float = r * (1.0 + 0.35 * (1.0 - fmod(k * 2.0 + q * 0.5, 1.0)))
		g.draw_arc(Vector2.ZERO, rq, s0, s1, 48, Color(c.r, c.g, c.b, 0.3 * a), 1.5)
	# 第一道缺口：两侧亮标 + 外侧向外的 V（从这里穿）
	for sd in [-1.0, 1.0]:
		var ea: Vector2 = Vector2.from_angle(aim + half * sd)
		g.draw_line(ea * (r - 14.0), ea * (r + 14.0), Color(1, 1, 1, 0.9 * a), 3.0)
	var dv: Vector2 = Vector2.from_angle(aim)
	var nv: Vector2 = dv.orthogonal()
	var tip: Vector2 = dv * (r + 34.0)
	g.draw_line(tip - dv * 12.0 + nv * 10.0, tip, Color(1, 1, 1, 0.85 * a), 2.5)
	g.draw_line(tip - dv * 12.0 - nv * 10.0, tip, Color(1, 1, 1, 0.85 * a), 2.5)
	# 后两道缺口：淡标
	for q in [1, 2]:
		var ga: float = aim + 1.1 * q * float(em.flip)
		var gv: Vector2 = Vector2.from_angle(ga)
		g.draw_line(gv * (r - 8.0), gv * (r + 10.0), Color(c.r, c.g, c.b, 0.55 * a / q), 3.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _tide_stain(g, e: Dictionary) -> void:
	# 二阶段场地（用户 10-28 嫌放射裂纹怪）：她脚下渗出一片海水渍——不规则深青水面、两道缓慢外扩的水纹、几颗上浮的小泡
	var pts := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 28:
		var a: float = TAU * i / 28.0
		var rr: float = 160.0 + 22.0 * sin(a * 3.0 + g.t * 0.5) + 12.0 * sin(a * 5.0 - g.t * 0.35)
		pts.append(e.pos + Vector2(cos(a), sin(a) * 0.55) * rr)
		inner.append(e.pos + Vector2(cos(a), sin(a) * 0.55) * rr * 0.55)
	g.draw_colored_polygon(pts, Color(0.02, 0.16, 0.22, 0.32))
	g.draw_colored_polygon(inner, Color(0.04, 0.26, 0.32, 0.22))
	for q in 2:
		var t: float = fmod(g.t * 0.35 + q * 0.5, 1.0)
		var r: float = lerpf(50.0, 200.0, t)
		var ring := PackedVector2Array()
		for i in 33:
			var a: float = TAU * i / 32.0
			ring.append(e.pos + Vector2(cos(a), sin(a) * 0.55) * r)
		g.draw_polyline(ring, Color(0.35, 0.9, 1.0, 0.3 * (1.0 - t)), 1.5)
	for q in 7:
		var ph: float = fmod(g.t * 0.45 + q * 0.37, 1.0)
		var bp: Vector2 = e.pos + Vector2(cos(q * 2.4), sin(q * 2.4) * 0.55) * (55.0 + q * 14.0) + Vector2(0, -ph * 26.0)
		g.world.tb_ring(bp, 1.5 + ph * 2.0, 1.0, Color(0.55, 0.95, 1.0, 0.6 * (1.0 - ph)), 6)
	g.world.tb_flush()


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
	# 二阶段：以她为中心的大片深青压暗地面（越远越淡，三层叠出渐变），「她认真了」
	if e.phase == 2 and float(e.get("cocoon_t", 0.0)) <= 0.0:
		for q in 3:
			g.draw_circle(e.pos, 900.0 - q * 260.0, Color(0.0, 0.05, 0.08, 0.1))
		_tide_stain(g, e)
	_rush_lanes(g, e)
	_emit_tells(g, e)
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


## 卡点泡膜硬化（10-28 防速杀，docs/170 §3w）：这一幕没满最短时长时伤害停在刻度上；身外一层硬化的多面泡壳（白紫棱面，缓慢转、棱上闪光），
## 壳外一圈细弧 = 还要撑多久（满 → 空）。和破绽的地面金环分开：这个在身上、冷色、硬边，读作「暂时打不动」而不是 bug
static func _hard_film(g, e: Dictionary) -> void:
	var o: Vector2 = e.pos + Vector2(0, -16)
	var r: float = float(e.r) * 1.35
	var c := Color(0.88, 0.8, 1.0) if e.phase == 1 else Color(0.7, 0.95, 1.0)
	var rot: float = g.t * 0.4
	var n := 9
	var pts := PackedVector2Array()
	for k in n + 1:
		pts.append(o + Vector2.from_angle(rot + TAU * k / n) * r)
	g.draw_colored_polygon(pts.slice(0, n), Color(c.r, c.g, c.b, 0.14))
	g.draw_polyline(pts, Color(0, 0, 0, 0.5), 5.0)
	g.draw_polyline(pts, Color(c.r, c.g, c.b, 0.9), 2.5)
	# 棱上闪光：一道亮点绕壳走
	var sk: float = fmod(g.t * 1.5, 1.0) * n
	var i0: int = int(sk)
	var sp: Vector2 = pts[i0].lerp(pts[i0 + 1], sk - i0)
	g.draw_circle(sp, 3.0, Color(1, 1, 1, 0.9))
	for k in n:
		g.draw_line(o + (pts[k] - o) * 0.72, pts[k], Color(1, 1, 1, 0.35), 1.0)
	var left: float = clampf(1.0 - float(e.get("act_t", 0.0)) / maxf(0.1, float(e.get("act_min", 1.0))), 0.0, 1.0)
	g.draw_arc(o, r + 9.0, -PI / 2.0, -PI / 2.0 + TAU * left, 40, Color(c.r, c.g, c.b, 0.85), 2.0)
