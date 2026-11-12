## 世界层地面光环绘制（world.draw_nest_auras 一族：巢穴光环、尖啸、重负环、伊祖米克灯；灯标 draw_beacons）。docs/286 §4 第三批从 render/world.gd 原样拆出，行为不变。
## 全部是 static func，第一个参数 wv = world；状态（beacon_seen 等）仍在 world 上，经 wv. 读写。
extends RefCounted

const W = preload("res://scripts/render/world.gd")
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")
const LateRead2 = preload("res://scripts/render/late_read2.gd")   # 后期可读性第二批（docs/251：light_share / ground_ring_edge / crowd_env_dim）
const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
## ---- 灯标（docs/49d §13.5 方案 C；逻辑在玩法系统，字段一律 get() 带缺省）：
## g.beacons 每项 {pos, lit, r 点燃光圈, clear_r 清痕半径, count_end / count_max 点燃进度, safe_end 安全区结束}
## 熄灭：暗灯塔 + 脚下暖色光圈呼吸（「站进来」）+ 点燃进度环；点燃瞬间：暖光爆扩到清痕半径；
## 亮着：灯室发光 + 旋转的灯塔光束 + 安全区虚线圈（剩余秒数），安全区结束后只留灯光
const BEACON_COL := Color(1.0, 0.78, 0.42)


## 巢涌者神经光环（docs/48 P1：帧条放大 4.6 倍后颗粒很粗，画在实体层会盖住其他东西）：
## 地面层程序绘制——淡紫柔光底、两道向内收的涟漪、缓慢转动的虚线外圈 = 判定范围
static func draw_nest_auras(wv: W) -> void:
	var g: Game = wv.g
	for e in g.enemies:
		if e.dead:
			continue
		if float(e.get("burden_r", 0.0)) > 0.0 and e.get("cocoon_t", 0.0) <= 0.0:
			_burden_ring(wv, e)
		# 不给每只敌人新建默认空数组 / 空字典（docs/50 §14）
		var lm = e.get("lamps")
		if lm is Array and not lm.is_empty():
			_izu_lamps(wv, e)
		var ed: Dictionary = D.ENEMIES.get(e.type, W._NO_DEF)
		if ed.has("aura_arts_mult") and (float(e.get("seal_t", 0.0)) > g.t or e.stun > 0.0):
			continue
		if ed.has("scream_r") and not ed.has("aura_r"):
			if g.t >= float(e.get("scream_t0", INF)) and g.t < float(e.get("scream_t1", -1.0)):
				_scream_aura(wv, e, float(ed.scream_r))
			continue
		if not ed.has("aura_r"):
			continue
		var ar: float = ed.aura_r
		if not wv.view_rect(ar + 20.0).has_point(e.pos):
			continue   # 屏外不画（性能 9/30：原来全场每只都画）
		var lite: bool = Bal.v("render/nest_aura_lite", 0.0) > 0.0   # docs/139 §8：只留一层淡底 + 不转的虚线边界
		var ac := Color(0.9, 0.5, 1.6)
		if LateRead2.on("ground_ring_edge"):
			var nk: float = LateRead2.nest_k()
			if nk > 0.0 and not lite:
				# V9 巢穴例外（nest_k，缺省 0.5）：保留约 nest_k 倍原填充 + 贴图，边一圈明显呼吸（1.6 秒），留一道内收涟漪；我方 / 中立光环仍只画边
				var tex9 := wv._lazy_tex("fx_nest_aura_big")
				if tex9 != null:
					var fw9: float = tex9.get_width() / 4.0
					var fr9 := int(g.t * 10.0) % 4
					g.wcv.draw_texture_rect_region(tex9, Rect2(e.pos - Vector2.ONE * ar, Vector2.ONE * ar * 2.0), Rect2(fr9 * fw9, 0, fw9, tex9.get_height()), Color(1, 1, 1, (0.5 if g.t - float(e.get("aura_pulse_t", -1.0)) < 0.15 else 0.35) * nk))
				for q in 4:
					wv.tb_circle(e.pos, ar * (1.0 - q * 0.22), Color(ac.r, ac.g, ac.b, minf(0.035 * nk, 0.0175)), 1.0, 32)
				var u9: float = fmod(g.t * 0.5 + e.id * 0.17, 1.0)
				wv.tb_ring(e.pos, ar * (1.0 - u9 * 0.85), 1.5, Color(ac.r, ac.g, ac.b, 0.28 * (1.0 - u9)), 40)
				var br: float = 0.5 + 0.5 * sin((g.t / 1.6 + float(e.id) * 0.13) * TAU)
				var eb: float = 0.55 + 0.45 * br
				if g.t - float(e.get("aura_pulse_t", -1.0)) < 0.15:
					eb = 1.0
				var rotn: float = g.t * 0.4 + e.id
				for q in 18:
					var an: float = rotn + q * TAU / 18.0
					wv.tb_arc(e.pos, ar, an, an + TAU / 36.0, 2.0 + 1.5 * br, Color(ac.r, ac.g, ac.b, eb), 3)
				continue
			# docs/251 V9：只画边 + 呼吸，填充一层 ≤ 0.04；脉冲（aura_pulse_t 0.15 秒）时边加亮，代替原来贴图整片加亮
			wv.tb_circle(e.pos, ar, Color(ac.r, ac.g, ac.b, LateRead2.fill_a(0.03)), 1.0, 32)
			var pk: bool = g.t - float(e.get("aura_pulse_t", -1.0)) < 0.15
			var ea9: float = 0.85 if pk else 0.6 * LateRead2.edge_breath(g.t, float(e.id) * 0.13)
			var rot9: float = g.t * 0.4 + e.id
			for q in 18:
				var a9: float = rot9 + q * TAU / 18.0
				wv.tb_arc(e.pos, ar, a9, a9 + TAU / 36.0, 2.0, Color(ac.r, ac.g, ac.b, ea9), 3)
			continue
		var aura_tex := wv._lazy_tex("fx_nest_aura_big") if not lite else null
		if aura_tex != null:
			var fw: float = aura_tex.get_width() / 4.0
			var frame := int(g.t * 10.0) % 4
			g.wcv.draw_texture_rect_region(aura_tex, Rect2(e.pos - Vector2.ONE * ar, Vector2.ONE * ar * 2.0), Rect2(frame * fw, 0, fw, aura_tex.get_height()), Color(1, 1, 1, 0.5 if g.t - float(e.get("aura_pulse_t", -1.0)) < 0.15 else 0.35))
		# 柔光底 / 内收涟漪 / 转动虚线外圈都进无贴图批，函数末尾一次提交（原来每只约 24 次绘制调用）
		if lite:
			wv.tb_circle(e.pos, ar, Color(ac.r, ac.g, ac.b, 0.05), 1.0, 32)
			for q in 18:
				var a0l: float = e.id + q * TAU / 18.0
				wv.tb_arc(e.pos, ar, a0l, a0l + TAU / 36.0, 2.0, Color(ac.r, ac.g, ac.b, 0.45), 3)
			continue
		for q in 4:
			wv.tb_circle(e.pos, ar * (1.0 - q * 0.22), Color(ac.r, ac.g, ac.b, 0.035), 1.0, 32)
		for q in 2:
			var u: float = fmod(g.t * 0.5 + q * 0.5 + e.id * 0.17, 1.0)
			wv.tb_ring(e.pos, ar * (1.0 - u * 0.85), 1.5, Color(ac.r, ac.g, ac.b, 0.28 * (1.0 - u)), 40)
		var rot: float = g.t * 0.4 + e.id
		for q in 18:
			var a0: float = rot + q * TAU / 18.0
			wv.tb_arc(e.pos, ar, a0, a0 + TAU / 36.0, 2.0, Color(ac.r, ac.g, ac.b, 0.55), 3)

	wv.tb_flush()


## 箱形恐鱼尖叫光环（docs/145 §4 A；画法按画面观感会话 10-25「圆圈收敛」口径）：随它移动、地面层；
## 常亮淡底 + 不转的 18 段虚线边界（起始角按 e.id 固定），不加涟漪 / 脉动 / 贴图；危险色；
## 尖叫开始 0.2 秒内边界 0.7 → 0.45（一次性），队长在圈内时边界 0.6。判定同 enemy_ai._scream（直线距离 < r）
static func _scream_aura(wv: W, e: Dictionary, r: float) -> void:
	var g: Game = wv.g
	if not wv.view_rect(r + 20.0).has_point(e.pos):
		return
	var c: Color = g.optical.col_danger if g.optical_on else W.ENEMY_TELL
	var since: float = g.t - float(e.scream_t0)
	var ea: float = lerpf(0.7, 0.45, clampf(since / 0.2, 0.0, 1.0))
	if g.ppos.distance_to(e.pos) < r:
		ea = maxf(ea, 0.6)
	wv.tb_circle(e.pos, r, Color(c.r, c.g, c.b, 0.05), 1.0, 40)
	var a0: float = float(e.id) * 0.37
	for q in 18:
		var s0: float = a0 + q * TAU / 18.0
		wv.tb_arc(e.pos, r, s0, s0 + TAU / 36.0, 2.0, Color(c.r, c.g, c.b, ea), 3)


## 偏执泡影「认知负担」光环（e.burden_r，主控在圈里 e.burden_in）：地面紫色符文圈缓慢旋转；主控在圈里时加亮、符文逆转
static func _burden_ring(wv: W, e: Dictionary) -> void:
	var g: Game = wv.g
	var r: float = float(e.burden_r)
	var inn: bool = e.get("burden_in", false)
	var c := Color(0.8, 0.45, 1.4)
	var a: float = 0.85 if inn else 0.45
	var gy: float = wv.ground_y()
	var o: Vector2 = e.pos
	var sq := func(v: Vector2) -> Vector2: return o + Vector2(v.x, v.y * gy)   # 地面椭圆：纵向按 GROUND_Y 压（原来用画布变换，改算顶点好进批）
	# 10-27（docs/170）：去掉整片平涂和实线外圈（像 UI 光盘），外缘改成一圈缓慢漂移的小泡沫
	wv.tb_circle(o, r, Color(c.r, c.g, c.b, 0.02 if inn else 0.008), gy, 48)
	for q in 44:
		var fa: float = q * TAU / 44.0 + g.t * 0.08 + 0.05 * sin(g.t * 1.3 + q * 1.7)
		var fr: float = 2.0 + 1.5 * absf(sin(q * 2.3 + g.t * 0.9))
		wv.tb_arc(sq.call(Vector2.from_angle(fa) * (r - 3.0 + 4.0 * sin(q * 0.9 + g.t))), fr, 0.0, TAU, 1.0, Color(c.r, c.g, c.b, 0.55 * a), 8)
	if Bal.v("render/burden_lite", 0.0) > 0.0:
		return   # docs/139 §8：只留淡底 + 外圈（不画内圈与转动符文）
	wv.tb_arc(o, r - 14.0, 0.0, TAU, 1.0, Color(c.r, c.g, c.b, 0.3 * a), 72, gy)
	var rot: float = g.t * (0.35 if inn else 0.15)
	var rc := Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, a)
	for q in 16:
		var ang: float = rot + q * TAU / 16.0
		var p := Vector2.from_angle(ang) * (r - 7.0)
		var tn := Vector2.from_angle(ang + PI / 2.0)
		var nr := Vector2.from_angle(ang)
		# 一枚符文：竖划 + 按序号变化的横 / 斜划
		wv.tb_line(sq.call(p - nr * 5.0), sq.call(p + nr * 5.0), rc, 1.5)
		match q % 3:
			0:
				wv.tb_line(sq.call(p - tn * 3.0), sq.call(p + tn * 3.0), rc, 1.5)
			1:
				wv.tb_line(sq.call(p + nr * 5.0), sq.call(p + nr * 1.0 + tn * 4.0), rc, 1.5)
			_:
				wv.tb_line(sq.call(p - nr * 5.0), sq.call(p - nr * 1.0 - tn * 4.0), rc, 1.5)


## 伊祖米克灯柱（e.lamps = [{pos, lit, prog}]，e.lamp_r）：未点亮 = 暗色石灯 + 脚下 40 半径的点亮进度环；
## 点亮 = 暖黄光圈（半径 lamp_r）+ 圈内「安全」标记（全场地波躲在这里），地波蓄力时光圈加亮脉动
static func _izu_lamps(wv: W, e: Dictionary) -> void:
	var g: Game = wv.g
	var lr: float = float(e.get("lamp_r", 120.0))
	var waving := false
	for w in g.warns:
		if not w.done and w.get("act", "") == "izu_wave":
			waving = true
	for lp in e.lamps:
		var p: Vector2 = lp.get("pos", Vector2.ZERO)
		var lit: bool = lp.get("lit", false)
		var pulse: float = 0.5 + 0.5 * sin(g.t * (10.0 if waving else 3.0))
		g.wcv.draw_set_transform(p, 0.0, Vector2(1.0, wv.ground_y()))
		if lit:
			g.wcv.draw_circle(Vector2.ZERO, lr, Color(1.0, 0.8, 0.4, LateRead2.fill_a((0.12 + 0.08 * pulse) if waving else 0.08)))   # docs/251 V9：填充封顶 0.04（地波蓄力时边本来就加粗脉动）
			g.wcv.draw_arc(Vector2.ZERO, lr, 0.0, TAU, 56, Color(1.8, 1.4, 0.6, 0.6 + 0.35 * pulse if waving else 0.55), 3.0 if waving else 2.0)
		else:
			g.wcv.draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 32, Color(1.0, 0.8, 0.45, 0.35), 1.5)
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if not lit and float(lp.get("prog", 0.0)) > 0.0:
			wv._ground_ring(p + Vector2(0, 2), 40.0, clampf(float(lp.prog), 0.0, 1.0), Color(1.6, 1.3, 0.6))
		# 石灯本体：Codex v14 prop_lamp_post（20×32，f0 熄灭、f1–f2 点亮循环，脚底第 29 行）；缺图时退回程序拼图
		if g.tex.get("prop_lamp_post") != null:
			g.vfx.spr("prop_lamp_post", 3, (1 + int(g.t * 4.0) % 2) if lit else 0, p, wv._hpx("prop_lamp_post"), false, Color.WHITE, Vector2(0.5, 30.0 / 32.0))
			if lit:
				g.wcv.draw_circle(p + Vector2(0, -40), 14.0 + 3.0 * pulse, Color(1.8, 1.4, 0.7, 0.25))
				UI.text(g.wcv, g.font, p + Vector2(-40, 26), "安全", 13 if not waving else 16, Color(1.0, 0.9, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
			continue
		var base := Color(0.32, 0.36, 0.42) if not lit else Color(0.5, 0.48, 0.44)
		g.wcv.draw_rect(Rect2(p + Vector2(-11, -8), Vector2(22, 8)), Color(0.1, 0.11, 0.14))
		g.wcv.draw_rect(Rect2(p + Vector2(-10, -7), Vector2(20, 6)), base)
		g.wcv.draw_rect(Rect2(p + Vector2(-5, -34), Vector2(10, 27)), Color(0.1, 0.11, 0.14))
		g.wcv.draw_rect(Rect2(p + Vector2(-4, -33), Vector2(8, 25)), base)
		g.wcv.draw_rect(Rect2(p + Vector2(-9, -48), Vector2(18, 15)), Color(0.1, 0.11, 0.14))
		g.wcv.draw_rect(Rect2(p + Vector2(-8, -47), Vector2(16, 13)), Color(1.9, 1.5, 0.7) if lit else Color(0.18, 0.24, 0.3))
		g.wcv.draw_rect(Rect2(p + Vector2(-10, -51), Vector2(20, 4)), Color(0.1, 0.11, 0.14))
		if lit:
			g.wcv.draw_circle(p + Vector2(0, -40), 14.0 + 3.0 * pulse, Color(1.8, 1.4, 0.7, 0.25))
			UI.text(g.wcv, g.font, p + Vector2(-40, 26), "安全", 13 if not waving else 16, Color(1.0, 0.9, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)


static func draw_beacons(wv: W) -> void:
	var g: Game = wv.g
	var bs = g.get("beacons")
	if not (bs is Array):
		return
	wv.beacon_seen = wv.beacon_seen.filter(func(s): return bs.any(func(b): return is_same(b, s[0])))
	var tx: Texture2D = wv._lazy_tex("prop_beacon")
	for b in bs:
		var pos: Vector2 = b.get("pos", Vector2.ZERO)
		var lit: bool = b.get("lit", false)
		var s: Array = []
		for s2 in wv.beacon_seen:
			if is_same(s2[0], b):
				s = s2
		if s.is_empty():
			wv.beacon_seen.append([b, lit])
		elif lit and not s[1]:
			s[1] = true
			beacon_burst(wv, b)
		var r: float = float(b.get("r", 70.0))
		var pulse: float = 0.5 + 0.5 * sin(g.t * 3.0)
		g.wcv.draw_set_transform(pos, 0.0, Vector2(1.0, wv.ground_y()))
		var br9: float = LateRead2.edge_breath(g.t, pos.x * 0.003)   # docs/251 V9：开时填充封顶 0.04、边呼吸；关时 = 1
		if not lit:
			g.wcv.draw_circle(Vector2.ZERO, r, Color(BEACON_COL.r, BEACON_COL.g, BEACON_COL.b, LateRead2.fill_a(0.07 + 0.05 * pulse)))
			for q in 20:
				var a0: float = g.t * 0.3 + q * TAU / 20.0
				wv.tb_arc(pos, r, a0, a0 + TAU / 40.0, 2.0, Color(BEACON_COL.r * 1.5, BEACON_COL.g * 1.5, BEACON_COL.b * 1.5, 0.55 * br9), 3, wv.ground_y())   # 虚线进批（原来 20 段各一次调用）
			# 引路圈（docs/56 a，beacon/guide_r > 0 才有）：guide_r 处一圈很淡的同款虚线，寿命过 guide_life 即消失
			var gr: float = float(b.get("guide_r", 0.0))
			if gr > 0.0 and float(b.get("age", 0.0)) <= float(b.get("guide_life", 45.0)):
				for q in 28:
					var a2: float = -g.t * 0.2 + q * TAU / 28.0
					wv.tb_arc(pos, gr, a2, a2 + TAU / 56.0, 1.5, Color(BEACON_COL.r * 1.3, BEACON_COL.g * 1.3, BEACON_COL.b * 1.3, (0.16 + 0.04 * pulse) * LateRead2.ring_vis()), 3, wv.ground_y())
		else:
			var left: float = float(b.get("safe_end", 0.0)) - g.t
			if left > 0.0:
				var cr: float = float(b.get("clear_r", 260.0))
				g.wcv.draw_circle(Vector2.ZERO, cr, Color(BEACON_COL.r, BEACON_COL.g, BEACON_COL.b, LateRead2.fill_a(0.05) * (0.5 if LateRead2.on("ground_ring_edge") else 1.0)))
				for q in 36:
					var a1: float = -g.t * 0.1 + q * TAU / 36.0
					wv.tb_arc(pos, cr, a1, a1 + TAU / 72.0, 2.0, Color(BEACON_COL.r * 1.4, BEACON_COL.g * 1.4, BEACON_COL.b * 1.4, (0.45 if left > 5.0 else 0.45 * absf(sin(g.t * 8.0))) * LateRead2.ring_vis()), 3, wv.ground_y())
			if LateRead2.on("ground_ring_edge"):
				# V9：灯标脚下的亮盘改成一圈亮边 + 极淡底（亮盘在暗场里是整片发光的半透明几何）
				g.wcv.draw_circle(Vector2.ZERO, 46.0, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.4, LateRead2.fill_a(0.16)))
				g.wcv.draw_arc(Vector2.ZERO, 46.0, 0.0, TAU, 40, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.4, 0.55 * br9), 2.0)
			else:
				g.wcv.draw_circle(Vector2.ZERO, 46.0, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.4, (0.16 + 0.06 * pulse) * LateRead2.ring_vis()))
		g.wcv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		wv.tb_flush()
		# 点燃进度（暖色环；读 prog / need，离开光圈时进度缓慢回退也看得到）
		if not lit and float(b.get("prog", 0.0)) > 0.0:
			var k: float = clampf(float(b.prog) / maxf(0.1, float(b.get("need", 2.5))), 0.0, 1.0)   # prog 离开圈会缓慢回退、不清零
			wv._ground_ring(pos + Vector2(0, 4), 30.0, k, Color(BEACON_COL.r * 1.6, BEACON_COL.g * 1.6, BEACON_COL.b * 1.3))
		if tx != null:
			var sc: float = Game.PX / A.hires_of(tx)
			g.vfx.spr("prop_beacon", 2, 1 if lit else 0, pos + Vector2(0, 3.0 * Game.PX), sc, false, Color.WHITE, Vector2(0.5, 41.0 / 44.0))
		var lamp: Vector2 = pos + Vector2(0, -(41.0 - 10.0) * Game.PX)
		if lit:
			# 灯塔光束：从灯室往外旋转的一道扇形暖光 + 灯室光晕
			var ang: float = g.t * 1.4
			for side in [0.0, PI]:
				var d0 := Vector2.from_angle(ang + side - 0.12)
				var d1 := Vector2.from_angle(ang + side + 0.12)
				var L: float = 220.0
				g.wcv.draw_colored_polygon(PackedVector2Array([lamp, lamp + Vector2(d0.x, d0.y * 0.5) * L, lamp + Vector2(d1.x, d1.y * 0.5) * L]), Color(BEACON_COL.r * 1.5, BEACON_COL.g * 1.5, BEACON_COL.b * 1.2, 0.10))
			g.wcv.draw_circle(lamp, 16.0, Color(1.8, 1.5, 0.9, 0.25 + 0.1 * pulse))
			var lf: float = float(b.get("safe_end", 0.0)) - g.t
			if lf > 0.0:
				UI.text(g.wcv, g.font, pos + Vector2(-80, 30), "安全区 %d 秒" % ceili(lf), 12, Color(1.0, 0.85, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 160, 3)
		else:
			# 未点燃：灯室一点琥珀色呼吸光（10-28 用户「灯塔还没被激活时加提醒」；原来是很淡的灰蓝，看不出在等人点）
			var br: float = 0.5 + 0.5 * sin(g.t * 2.4)
			g.wcv.draw_circle(lamp, 9.0 + 3.0 * br, Color(1.0, 0.68, 0.32, 0.16 + 0.16 * br))
			g.wcv.draw_circle(lamp, 4.0, Color(1.5, 1.05, 0.55, 0.55 + 0.35 * br))


## 点燃瞬间：暖白爆闪 + 一道光环扩到清痕半径 + 放射光束 + 火花
static func beacon_burst(wv: W, b: Dictionary) -> void:
	var g: Game = wv.g
	var pos: Vector2 = b.get("pos", Vector2.ZERO)
	g.fx.append({"kind": "beacon_burst", "pos": pos, "r": float(b.get("clear_r", 260.0)), "life": 0.9, "max": 0.9})
	g.vfx.sparks(pos + Vector2(0, -60), Vector2.ZERO, Color(1.8, 1.4, 0.7), 18, 300.0)
	wv._flash(Color(1.0, 0.85, 0.55), 0.3)
	g.vfx.beacon_ignite(b)   # docs/54：柔光 + 余烬 + 溟痕退散
