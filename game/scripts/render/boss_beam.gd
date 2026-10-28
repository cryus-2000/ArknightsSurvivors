extends RefCounted
## Boss 改版样板的画面（docs/142b §8.5、§3.1，10-25）：
## 1. "kp_beam"：Kanpelle · Ultimate Laser Pack 光束（tools/gen_boss_laser.py 导出 fx_kp_<boss>_<段>，每段 16 × 48、4 帧）。
##    起点 + 中段平铺 + 命中端，沿 a → b 旋转；先播开启 4 帧，再循环持续帧，最后开启倒放 = 关闭。纯画面，不碰随机数。
## 2. 骑士「斗牛」的寒气圈（地面层）与主控的寒冷条（顶层）：读 e.kcold / e.kcold_r（knight_boss.gd 写）。
## 3. 卡门火线、塑路者生路、泡影悬浮圈、伊莎玛拉连线、伊祖米克子代与茧（地面层）；接潮组同步护盾、泡影坠地 / 光环散开倒计时、伊莎玛拉音符与护盾格、伊祖米克来向箭头与强化层数（顶层）。
const A = preload("res://scripts/art.gd")
const Bal = preload("res://scripts/core/balance.gd")
const ParanoiaComboDraw = preload("res://scripts/render/paranoia_combo_draw.gd")
const BreakRing = preload("res://scripts/render/break_ring.gd")

const SEG := 16.0     # 每段宽（美术像素）
const HALF_H := 24.0  # 帧高 48 的一半（光束竖直居中）
const ON_T := 0.06    # 开启 / 关闭各 0.06 秒（4 帧；原 0.12，光束总长随 telegraph.KP_LIFE 收到 0.25 秒）
const FPS := 16.0     # 持续帧循环
# Boss 颗粒预算（令牌桶）：每秒补 render/boss_grain_rate（高档 600、中档减半）、最多攒 render/boss_grain_burst（高档 160、中档减半）；
# 每次要 n 颗只给桶里有的（超了降密度，不排队）。低档 fx_grains 不开 → grains() 返回 null，各处退回原画法
static var _tok := 0.0
static var _tok_us := 0


## Boss 特效颗粒层：光学观感颗粒开着、render/boss_fx_grains 开、且不在 --perfab 同局轮换的「旧」段（g.perf_alt）时返回 fx_grains，否则 null
static func grains(g):
	if g.optical == null or g.optical.grains == null or not g.optical.grains.on() or g.perf_alt or Bal.v("render/boss_fx_grains", 1.0) <= 0.0:
		return null
	return g.optical.grains


## 激光类特效已播时长（秒）：取模拟时间（max − life）与真实时间（第一次画时记下 rt0）里大的那个——
## 掉帧（30 帧以下 PlayClock 让模拟放慢）或顿帧（hitstop 暂停模拟）时，按模拟时间淡出会在真实时间里拖长（用户 10-26「激光打完消失得很慢」）；
## 判定在结算那一刻已结束，画面只看真实时间也不会和判定错开。正常帧率下两者相同
static func laser_el(f: Dictionary) -> float:
	var el: float = float(f.max) - float(f.life)
	var now: int = Time.get_ticks_msec()
	if not f.has("rt0"):
		f["rt0"] = now - int(el * 1000.0)
	return maxf(el, float(now - int(f.rt0)) / 1000.0)


## 从预算里要 n 颗，返回实际给的颗数（0..n）
static func take(g, n: int) -> int:
	var now: int = Time.get_ticks_usec()
	var hi: bool = g.optical.grains.level >= 2
	var rate: float = Bal.v("render/boss_grain_rate", 600.0) * (1.0 if hi else 0.5)
	var cap: float = Bal.v("render/boss_grain_burst", 160.0) * (1.0 if hi else 0.5)
	if _tok_us > 0:
		_tok = minf(cap, _tok + rate * float(now - _tok_us) / 1000000.0)
	else:
		_tok = cap
	_tok_us = now
	var give: int = mini(n, int(_tok))
	_tok -= float(give)
	return give


static func _tex(g, name: String) -> Texture2D:
	if not g.tex.has(name):
		g.tex[name] = A.tex(name)
	return g.tex[name]


## f：{"kind": "kp_beam", "a", "b", "life", "max", "boss": "iberia", "k": 世界像素 / 美术像素（缺省 2 = 1 倍粗，3 = 1.5 倍粗）}
static func draw(g, f: Dictionary) -> bool:
	var boss: String = str(f.get("boss", ""))
	var el: float = laser_el(f)
	var left: float = float(f.max) - el
	if left <= 0.0:
		return true   # 真实时间已到（掉帧 / 顿帧时模拟还没走完）：不再画
	var on_t: float = float(f.get("on_t", ON_T))   # 开合时长：缺省 ON_T，泡影凝视持续光束 0.15（docs/170）
	var on: bool = el < on_t or left < on_t
	var fr: int
	if el < on_t:
		fr = clampi(int(el / on_t * 4.0), 0, 3)
	elif left < on_t:
		fr = clampi(int(left / on_t * 4.0), 0, 3)   # 关闭 = 开启倒放
	else:
		fr = int(el * FPS) % 4
	var suf: String = "_on" if on else ""
	var t_src := _tex(g, "fx_kp_%s_src%s" % [boss, suf])
	var t_mid := _tex(g, "fx_kp_%s_mid%s" % [boss, suf])
	var t_hit := _tex(g, "fx_kp_%s_hit%s" % [boss, suf])
	if t_src == null or t_mid == null or t_hit == null:
		return false   # 缺图交回原画法（tracer）
	var k: float = float(f.get("k", 2.0))
	var a: Vector2 = f.a
	var b: Vector2 = f.b
	var lp: float = maxf(a.distance_to(b) / k, SEG * 2.0)   # 光束长度（美术像素），至少起点 + 命中端
	var src_rect := Rect2(fr * SEG, 0, SEG, HALF_H * 2.0)
	g.draw_set_transform(a, (b - a).angle(), Vector2(k, k))
	g.draw_texture_rect_region(t_src, Rect2(0, -HALF_H, SEG, HALF_H * 2.0), src_rect)
	var x: float = SEG
	while x < lp - SEG:
		var w: float = minf(SEG, lp - SEG - x)
		g.draw_texture_rect_region(t_mid, Rect2(x, -HALF_H, w, HALF_H * 2.0), Rect2(fr * SEG, 0, w, HALF_H * 2.0))
		x += SEG
	g.draw_texture_rect_region(t_hit, Rect2(lp - SEG, -HALF_H, SEG, HALF_H * 2.0), src_rect)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 平铺一段光束中段（a → b，k 倍、透明度 al）：卡门的火线等「留在地上的光束」
static func _tile(g, tex: Texture2D, a: Vector2, b: Vector2, k: float, fr: int, al: float) -> void:
	var lp: float = a.distance_to(b) / k
	if lp <= 0.5:
		return
	g.draw_set_transform(a, (b - a).angle(), Vector2(k, k))
	var x: float = 0.0
	while x < lp:
		var w: float = minf(SEG, lp - x)
		g.draw_texture_rect_region(tex, Rect2(x, -HALF_H, w, HALF_H * 2.0), Rect2(fr * SEG, 0, w, HALF_H * 2.0), Color(1, 1, 1, al))
		x += SEG
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 卡门的封锁线（saint.gd _fire_step 写 e.fire_lines）：Kanpelle 象牙白中段压暗平铺，缺口空出来、画白圈；最后 0.6 秒淡出
static func _fire_lines(g, e: Dictionary) -> void:
	var bc: Color = g.vfx.boss_color(str(e.type))
	var ember := Color(bc.r * 0.95, bc.g * 0.62, bc.b * 0.38)   # 余烬：专属色往暖、往暗压（象牙白 → 焦橙）
	for fl in e.get("fire_lines", []):
		var left: float = float(fl.until) - g.t
		var al: float = 0.55 * clampf(left / 0.6, 0.0, 1.0) * clampf((g.t - float(fl.get("born", 0.0))) / 0.15, 0.0, 1.0)
		var a: Vector2 = fl.a
		var b: Vector2 = fl.b
		var L: float = a.distance_to(b)
		if L < 1.0:
			continue
		var gt: float = float(fl.gap_t)
		var gh: float = float(fl.gap_len) * 0.5 / L
		# 贴地余烬带（用户 10-26：火线用激光帧条画，看起来像激光打完迟迟不消失）：每 14 像素一小段，hash 每秒换 5 次决定亮暗 / 断续，
		# 线宽 4、比激光暗得多；判定照旧（saint._fire_step：线宽 14 内、缺口外）
		var dirv: Vector2 = (b - a) / L
		var nrm: Vector2 = dirv.orthogonal()
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var n: int = int(L / 14.0)
		var tick: float = floor(g.t * 5.0)
		for i in n:
			var u0: float = float(i) / float(n)
			var u1: float = (float(i) + 0.75) / float(n)
			if absf((u0 + u1) * 0.5 - gt) < gh:
				continue   # 缺口里不画
			var h: float = fposmod(sin(float(i) * 12.9898 + tick * 4.11 + float(fl.born) * 7.0) * 43758.5453, 1.0)
			var j: float = (h - 0.5) * 4.0
			pts.append(a + dirv * (L * u0) + nrm * j)
			pts.append(a + dirv * (L * u1) + nrm * j)
			var k: float = 0.45 + 0.55 * h
			cols.append(Color(ember.r * (0.8 + 0.5 * k), ember.g * (0.8 + 0.5 * k), ember.b * (0.8 + 0.5 * k), al * k))
		if not cols.is_empty():
			g.draw_multiline_colors(pts, cols, 4.0)
		var gp: Vector2 = a.lerp(b, gt)
		g.draw_set_transform(gp, 0.0, Vector2(1.0, 0.6))
		g.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 20, Color(1, 1, 1, minf(1.0, al * 1.6)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 塑路者的生路（path.gd 写 e.paths）：钢蓝折线（低亮度宽线 + 亮芯）、每段末端金色路标；截断的路变暗、断口画叉
static func _paths(g, e: Dictionary) -> void:
	for p in e.get("paths", []):
		var pts: Array = p.pts
		var cut: bool = p.cut
		var al: float = 0.18 if cut else 0.42
		var pa := PackedVector2Array(pts)
		g.draw_polyline(pa, Color(0.55, 0.65, 1.0, al * 0.6), 9.0)
		g.draw_polyline(pa, Color(0.8, 0.88, 1.0, al * 1.6), 2.0)
		for i in range(1, pts.size()):
			var q: Vector2 = pts[i]
			if cut and i == int(p.get("cut_i", -1)):
				g.draw_line(q + Vector2(-8, -8), q + Vector2(8, 8), Color(1.0, 0.85, 0.4, 0.9), 3.0)
				g.draw_line(q + Vector2(-8, 8), q + Vector2(8, -8), Color(1.0, 0.85, 0.4, 0.9), 3.0)
				continue
			var c := Color(1.0, 0.82, 0.3, 0.35 if cut else 1.0)
			g.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 0), q + Vector2(0, 9), q + Vector2(-7, 0)]), c)
			g.draw_polyline(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 0), q + Vector2(0, 9), q + Vector2(-7, 0), q + Vector2(0, -9)]), Color(1, 1, 1, c.a), 1.5)


## 偏执泡影「打落」读法（docs/142b §3.5）：悬浮时身下白色双描边椭圆（主控冲刺可用时加亮）；
## 坠地 / 三幕光环散开时青色倒计时环（弧长 = 剩余比例）
static func _paranoia_ground(g, e: Dictionary) -> void:
	ParanoiaComboDraw.draw_ground(g, e)   # 凝视预警（暗红低填充 + 泡沫边，docs/170）
	if e.get("cocoon_t", 0.0) > 0.0 or e.phase != 1 or float(e.get("drop_until", 0.0)) > g.t:
		return   # 收招破绽期间照常画（可以打落），只有已坠地时不画
	var al: float = 0.75 if g.dash_ready() else 0.3
	g.draw_set_transform(e.pos + Vector2(0, e.r * 0.8), 0.0, Vector2(1.0, 0.45))
	g.draw_arc(Vector2.ZERO, e.r * 1.25, 0.0, TAU, 40, Color(1, 1, 1, al), 2.0)
	g.draw_arc(Vector2.ZERO, e.r * 1.25 + 5.0, 0.0, TAU, 40, Color(1, 1, 1, al * 0.6), 1.5)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _paranoia_top(g, e: Dictionary) -> void:
	ParanoiaComboDraw.draw_top(g, e)   # 连携攻势：幻影空心泡 / 起手聚光（docs/170）
	var left: float = 0.0
	if e.phase == 1 and float(e.get("drop_until", 0.0)) > g.t:
		left = (float(e.drop_until) - g.t) / maxf(0.1, Bal.v("boss/paranoia_drop_t", 4.0))
	elif e.phase == 2 and float(e.get("aura_off_until", 0.0)) > g.t:
		left = (float(e.aura_off_until) - g.t) / maxf(0.1, float(e.get("aura_off_max", 5.0)))
	if left <= 0.0:
		return
	var c := Color(0.45, 0.95, 1.0, 0.9)
	var r: float = e.r * 1.5
	g.draw_arc(e.pos, r, -PI * 0.5, -PI * 0.5 + TAU * left, 48, c, 3.0)
	g.draw_arc(e.pos, r, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.18), 1.5)


## 伊莎玛拉「破网」读法（docs/142b §3.6）：地面层——她到每只连线海嗣一条低亮度青绿细线、海嗣脚下金色描边圈，泪脚下金圈随心跳缩放；
## 顶层——连线海嗣头顶音符，她身上的护盾环按上限分格、亮格数 = 连线数（每断一根线少一格）
const ISHAR_LINK := Color(0.3, 1.0, 0.65)
const GOLD := Color(1.0, 0.82, 0.3)


static func _web_ground(g, e: Dictionary) -> void:
	for sl in e.get("web", []):
		var o = sl.o
		if o == null or o.dead:
			continue
		g.draw_line(e.pos, o.pos, Color(ISHAR_LINK.r, ISHAR_LINK.g, ISHAR_LINK.b, 0.28), 1.5)
		g.draw_set_transform(o.pos + Vector2(0, o.r * 0.8), 0.0, Vector2(1.0, 0.5))
		g.draw_arc(Vector2.ZERO, o.r + 6.0, 0.0, TAU, 24, Color(GOLD.r, GOLD.g, GOLD.b, 0.8), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var beat: float = pow(maxf(0.0, sin(g.t * 5.0)), 6.0)
	for o in e.get("eyes", []):
		if o.dead:
			continue
		g.draw_arc(o.pos, o.r + 8.0 + beat * 6.0, 0.0, TAU, 28, Color(GOLD.r, GOLD.g, GOLD.b, 0.6 + beat * 0.4), 2.5)


static func _web_top(g, e: Dictionary) -> void:
	var cap: int = int(e.get("web_cap", 0))
	if cap <= 0:
		return
	for sl in e.get("web", []):
		var o = sl.o
		if o == null or o.dead:
			continue
		var h: Vector2 = o.pos + Vector2(0, -o.r - 22.0 + sin(g.t * 3.0 + float(o.id)) * 2.0)
		g.draw_circle(h + Vector2(-3, 4), 3.0, GOLD)
		g.draw_line(h + Vector2(0, 4), h + Vector2(0, -6), GOLD, 1.5)
		g.draw_line(h + Vector2(0, -6), h + Vector2(4, -3), GOLD, 1.5)
	var n: int = int(e.get("web_n", 0))
	var r: float = float(e.r) * 1.45
	var step: float = TAU / float(cap)
	for i in cap:
		var a0: float = -PI * 0.5 + step * i + step * 0.1
		var on: bool = i < n
		g.draw_arc(e.pos, r, a0, a0 + step * 0.8, 8, Color(ISHAR_LINK.r, ISHAR_LINK.g, ISHAR_LINK.b, 0.85 if on else 0.15), 3.0 if on else 1.5)


## 伊祖米克「拦截」读法（docs/142b §3.7）：地面层——每只批次子代脚下金色描边圈 + 一条细线连向她，茧外青色倒计时环；
## 顶层——队长身边金色箭头指向每一路还在走的子代（重心），她头顶强化层数亮点（1–4）
static func _izumik_ground(g, e: Dictionary) -> void:
	for o in e.get("batch", []):
		if o.dead:
			continue
		if o.get("izu_cocoon", false):
			var left: float = clampf((float(o.cocoon_until) - g.t) / maxf(0.1, Bal.v("boss/izumik_cocoon_t", 4.0)), 0.0, 1.0)
			g.draw_arc(o.pos, o.r + 12.0, -PI * 0.5, -PI * 0.5 + TAU * left, 32, Color(0.45, 0.95, 1.0, 0.9), 3.0)
			continue
		g.draw_line(o.pos, e.pos, Color(GOLD.r, GOLD.g, GOLD.b, 0.16), 1.0)
		g.draw_set_transform(o.pos + Vector2(0, o.r * 0.8), 0.0, Vector2(1.0, 0.5))
		g.draw_arc(Vector2.ZERO, o.r + 6.0, 0.0, TAU, 24, Color(GOLD.r, GOLD.g, GOLD.b, 0.8), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _izumik_top(g, e: Dictionary) -> void:
	var sums: Dictionary = {}
	for o in e.get("batch", []):
		if o.dead or o.get("izu_cocoon", false):
			continue
		var k: int = int(o.get("izu_dir", 0))
		if not sums.has(k):
			sums[k] = [Vector2.ZERO, 0]
		sums[k][0] += o.pos
		sums[k][1] += 1
	for k in sums:
		var c: Vector2 = sums[k][0] / float(sums[k][1])
		if c.distance_to(g.ppos) < 140.0:
			continue
		var d: Vector2 = (c - g.ppos).normalized()
		var tip: Vector2 = g.ppos + d * 70.0
		var side: Vector2 = d.orthogonal() * 9.0
		var pts := PackedVector2Array([tip, tip - d * 16.0 + side, tip - d * 16.0 - side])
		g.draw_colored_polygon(pts, Color(GOLD.r, GOLD.g, GOLD.b, 0.9))
		g.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.2, 0.12, 0.0, 0.8), 1.5)
	var n: int = int(e.get("izu_stacks", 0))
	for i in n:
		var p: Vector2 = e.pos + Vector2((float(i) - (n - 1) * 0.5) * 12.0, -e.r - 30.0)
		g.draw_circle(p, 4.0, Color(0.5, 1.0, 0.6))
		g.draw_arc(p, 5.5, 0.0, TAU, 12, Color(1, 1, 1, 0.7), 1.0)


## ---- 每幕一套颗粒（docs/142b §8.2「特效 / 转场」列，docs/142 §1「肉眼可见」）：本体周围按这一幕的颜色 / 方向持续冒颗粒；
## 换幕那一刻（act_index 变了）从本体迸出一圈这一幕颜色的颗粒——不闪白、不加亮度（docs/137）。只在光学观感颗粒开着时画（fx_grains.on），纯画面，只用 g.vrng
## 每项：[颜色, 方式（"up" 上升 / "down" 下落 / "in" 流入本体 / "" 不冒）, 每秒颗数]；下标 = act_index
const ACT_LOOK := {
	"knight_boss": [[Color(0.6, 0.9, 1.0), "up", 18.0], [Color(0.88, 0.96, 1.0), "down", 24.0], [Color(0.4, 0.6, 0.98), "up", 26.0], [Color(0.92, 0.96, 1.0), "down", 30.0]],
	"path": [[Color(0.62, 0.66, 0.72), "down", 16.0], [Color(0.58, 0.5, 1.0), "up", 26.0]],
	"iberia": [[Color(1.0, 0.5, 0.2), "", 0.0], [Color(0.32, 0.27, 0.22), "up", 22.0]],
	"carmen": [[Color(1.0, 0.94, 0.82), "up", 10.0], [Color(1.0, 0.88, 0.55), "up", 24.0]],
	"bishop": [[Color(0.3, 0.35, 0.9), "up", 12.0], [Color(0.45, 0.65, 1.0), "down", 22.0]],
	"archon": [[Color(0.35, 0.9, 0.45), "up", 12.0], [Color(0.45, 1.0, 0.6), "down", 22.0]],
	"immortal": [[Color(0.65, 0.75, 1.0), "up", 12.0], [Color(0.82, 0.86, 1.0), "down", 22.0]],
	"paranoia": [[Color(0.78, 0.62, 1.0), "up", 18.0], [Color(1.0, 0.4, 0.85), "up", 24.0], [Color(0.32, 0.16, 0.42), "down", 28.0], [Color(0.95, 0.85, 1.0), "up", 30.0]],
	"ishar": [[Color(0.3, 1.0, 0.65), "up", 18.0], [Color(0.75, 0.2, 0.22), "down", 24.0], [Color(0.82, 1.0, 0.9), "up", 28.0]],
	"izumik": [[Color(0.4, 0.6, 1.0), "up", 18.0], [Color(0.5, 0.85, 1.0), "in", 26.0], [Color(0.85, 0.95, 1.0), "down", 28.0]],
}


## 这一幕的下标：一般 = 过了几道卡点；骑士重生 = 3；泡影落地 = 2、破茧后 = 3；伊莎玛拉 / 伊祖米克只算变身 / 扎根后（之前 -1 = 不冒）
static func act_index(e: Dictionary) -> int:
	var gp: int = int(e.get("gates_passed", 0))
	match str(e.type):
		"knight_boss":
			return 3 if e.phase == 2 else mini(gp, 2)
		"paranoia":
			if e.get("cocoon_t", 0.0) > 0.0:
				return -1
			if e.get("cocoon_done", false) and e.phase == 2:
				return 3
			return 2 if e.phase == 2 else mini(gp, 1)
		"ishar", "izumik":
			return mini(gp, 2) if e.phase == 2 else -1
	return mini(gp, ACT_LOOK.get(str(e.type), [[]]).size() - 1)


static func _act_look(g, e: Dictionary, grains) -> void:
	var looks: Array = ACT_LOOK.get(str(e.type), [])
	var i: int = act_index(e)
	if looks.is_empty() or i < 0 or i >= looks.size():
		return
	var lk: Array = looks[i]
	var c: Color = lk[0]
	var prev: int = int(e.get("look_i", -9))
	e["look_i"] = i
	if prev != -9 and prev != i:
		# 换幕：一圈（最多 48 颗）这一幕颜色的颗粒向外迸散
		var nb: int = take(g, 48)
		for k in nb:
			var d: Vector2 = Vector2.from_angle(TAU * k / maxf(1.0, float(nb)) + g.vrng.randf_range(-0.05, 0.05))
			grains.push("mote_burst", e.pos + d * float(e.r) * 0.6, d, c)
	var mode: String = lk[1]
	if mode == "":
		return
	var p: float = float(lk[2]) / 60.0
	while p > 0.0:
		if g.vrng.randf() < p and take(g, 1) > 0:
			var r: float = float(e.r)
			match mode:
				"up":
					grains.push("mote_up", e.pos + Vector2(g.vrng.randf_range(-1.4, 1.4) * r, g.vrng.randf_range(-0.6, 0.9) * r), Vector2.UP, c)
				"down":
					grains.push("mote_down", e.pos + Vector2(g.vrng.randf_range(-1.5, 1.5) * r, g.vrng.randf_range(-2.0, -0.6) * r), Vector2.DOWN, c)
				"in":
					var d2: Vector2 = Vector2.from_angle(g.vrng.randf() * TAU)
					grains.push("mote_in", e.pos + d2 * r * 3.2, -d2, c)
		p -= 1.0


## ---- Boss 冲击环（伊莎玛拉「大群之歌」、塑路者震地、蔑死体跃击）：用户 10-25「放出去的像是平推出去」「波纹内部多叠」「几何线条感太重」
const SONG_STEP := 0.07   # 折线每段弧度
const SONG_RIP := 26.0    # 内波纹间距（世界像素）


static func _song_r(sh: Dictionary, a: float, dr: float, t: float) -> float:
	var amp: float = 7.0 + float(sh.r) * 0.006   # 起伏随半径略增（大半径时 ±4 看着还是正圆）
	return float(sh.r) + dr + sin(a * 7.0 + t * 5.0) * amp + sin(a * 13.0 - t * 8.0) * amp * 0.35


## 一条断续的「颗粒带」（用户 10-25「波的几何线条感太重」）：沿弧每 SONG_STEP 一小段短划（占 70%，留缝），按 hash 决定这一段画不画（keep）、
## 半径抖动 ±jit/2、亮度起伏；hash 每秒换 6 次 → 闪烁、断续。一次 draw_multiline_colors 提交整条带（不逐段调用）
static func _song_band(g, sh: Dictionary, segs: Array, dr: float, gy: float, t: float, col: Color, width: float, keep: float, jit: float, seed: float) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var tick: float = floor(t * 6.0)
	for sg in segs:
		var a0: float = sg[0]
		var a1: float = sg[1]
		var n: int = maxi(2, int(ceil((a1 - a0) / SONG_STEP)))
		for i in n:
			var h: float = fposmod(sin(float(i) * 12.9898 + seed * 78.233 + tick * 3.17) * 43758.5453, 1.0)
			if h > keep:
				continue
			var aa: float = a0 + (a1 - a0) * float(i) / float(n)
			var ab: float = a0 + (a1 - a0) * (float(i) + 0.7) / float(n)
			var j: float = (h / maxf(0.01, keep) - 0.5) * jit
			var ra: float = _song_r(sh, aa, dr, t) + j
			var rb: float = _song_r(sh, ab, dr, t) + j
			pts.append(sh.pos + Vector2(cos(aa) * ra, sin(aa) * ra * gy))
			pts.append(sh.pos + Vector2(cos(ab) * rb, sin(ab) * rb * gy))
			var k: float = 0.55 + 0.45 * fposmod(h * 7.31, 1.0)
			cols.append(Color(col.r, col.g, col.b, col.a * k))
	if not cols.is_empty():
		g.draw_multiline_colors(pts, cols, width)


## Boss 冲击环（大群之歌、震地、跃击；判定不变：shot_pool.update_shocks 按 sh.r 一条环带）：
## 前沿 = 断续抖动的专属色颗粒带（亮芯 + 外侧柔光），往内三层越淡越宽越碎的尾带；伊莎玛拉另叠 4 圈由内向外流的内波纹（ripples）；
## 前沿沿途散颗粒（走预算）；缺口两侧照旧画金色出口短线。不加深色描边
static func draw_song(g, sh: Dictionary, gy: float, ripples: bool = true) -> void:
	var c: Color = sh.get("col", ISHAR_LINK)
	if str(sh.get("src_type", "")) != "ishar":
		c = g.vfx.boss_color(str(sh.get("src_type", "")))
	var k: float = clampf(float(sh.r) / maxf(1.0, float(sh.maxr)), 0.0, 1.0)
	var a: float = 1.0 - k * k * 0.7   # 越扩越淡（到最大半径剩 0.3），不是匀速一整块
	var t: float = g.t
	var gh: float = float(sh.get("gap_half", 0.0))
	var gaps: Array = sh.get("gaps", []) if gh > 0.0 else []
	var segs: Array = []
	if gaps.is_empty():
		segs.append([0.0, TAU])
	else:
		var starts: Array = []
		for ga in gaps:
			starts.append(fposmod(float(ga) + gh, TAU))
		starts.sort()
		for i in starts.size():
			var s0: float = starts[i]
			var s1: float = starts[(i + 1) % starts.size()] - gh * 2.0
			if s1 <= s0:
				s1 += TAU
			segs.append([s0, s1])
	var sd: float = float(sh.pos.x * 0.013 + sh.pos.y * 0.007)   # 每个环自己的 hash 种子
	# 尾带（由外往里：越淡、越宽、越碎）
	for j in 3:
		_song_band(g, sh, segs, -9.0 - 10.0 * j, gy, t - 0.05 * j, Color(c.r, c.g, c.b, (0.34 - 0.09 * j) * a), 5.0 + 2.5 * j, 0.8 - 0.15 * j, 6.0 + 3.0 * j, sd + 1.0 + j)
	if ripples:
		# 内波纹：4 圈由内向外流向前沿（一层层推出去），越往里越淡越细越碎，各圈错相起伏
		var flow: float = fposmod(t * 55.0, SONG_RIP)
		for q in 4:
			var dr2: float = -(16.0 + SONG_RIP * float(q) + (SONG_RIP - flow))
			if float(sh.r) + dr2 < 24.0:
				continue
			var depth: float = clampf(-dr2 / (SONG_RIP * 4.0 + 16.0), 0.0, 1.0)
			var lc: float = 1.15 - 0.35 * depth   # 外圈偏亮、里圈偏暗（同色系分明暗）
			_song_band(g, sh, segs, dr2, gy, t + 0.9 * float(q + 1), Color(c.r * lc, c.g * lc, c.b * lc, 0.6 * a * (1.0 - depth)), 3.0 - 1.6 * depth, 0.75 - 0.35 * depth, 5.0, sd + 7.0 + q)
	# 前沿：外侧柔光 + 本色亮带 + 浅色芯（都断续）
	_song_band(g, sh, segs, 4.0, gy, t, Color(c.r, c.g, c.b, 0.22 * a), 6.0, 0.7, 4.0, sd + 20.0)
	_song_band(g, sh, segs, 0.0, gy, t, Color(c.r * 1.25, c.g * 1.25, c.b * 1.25, a), 3.5, 0.9, 3.0, sd + 21.0)
	_song_band(g, sh, segs, 0.0, gy, t, Color(0.85 + c.r * 0.15, 0.85 + c.g * 0.15, 0.85 + c.b * 0.15, 0.8 * a), 1.4, 0.55, 2.0, sd + 22.0)
	for ga in gaps:
		for side in [-1.0, 1.0]:
			var v := Vector2.from_angle(float(ga) + side * gh)
			var p0: Vector2 = sh.pos + Vector2(v.x, v.y * gy) * (float(sh.r) - 16.0)
			var p1: Vector2 = sh.pos + Vector2(v.x, v.y * gy) * (float(sh.r) + 16.0)
			g.draw_line(p0, p1, Color(1.0, 0.85, 0.35, 0.9), 2.0)
	# 前沿沿途散颗粒 + 波内由内向外流的颗粒（走预算）
	var grains = grains(g)
	if grains != null and a > 0.2:
		for i in take(g, 5):
			var ang: float = g.vrng.randf() * TAU
			if not gaps.is_empty() and g.tele.in_gap(sh, ang):
				continue
			var v2 := Vector2.from_angle(ang)
			grains.push("mote_shed", sh.pos + Vector2(v2.x, v2.y * gy) * float(sh.r), v2, c)
		if ripples:
			for i in take(g, 2):
				var ang2: float = g.vrng.randf() * TAU
				if not gaps.is_empty() and g.tele.in_gap(sh, ang2):
					continue
				var v3 := Vector2.from_angle(ang2)
				grains.push("mote_shed", sh.pos + Vector2(v3.x, v3.y * gy) * float(sh.r) * g.vrng.randf_range(0.45, 0.9), v3, Color(c.r * 0.85, c.g * 0.85, c.b * 0.85))


## 大群之歌的起势（预警 0.8 秒里）：她身边一圈由外往里收的环 + 颗粒向她汇聚（「张开 → 吸气」），出手时由 draw_song 接上
static func _song_windup(g, e: Dictionary) -> void:
	for w in g.warns:
		if w.done or not is_same(w.owner, e) or str(w.act) != "song_ring":
			continue
		var k: float = clampf(float(w.t) / maxf(0.05, float(w.dur)), 0.0, 1.0)
		var c: Color = w.col
		var rr: float = lerpf(150.0, float(w.r), k * k)
		g.draw_set_transform(e.pos, 0.0, Vector2(1.0, 0.72))
		g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.15 + 0.5 * k), 2.0 + 3.0 * k)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var grains = grains(g)
		if grains != null:
			for i in take(g, 3):
				var d := Vector2.from_angle(g.vrng.randf() * TAU)
				grains.push("mote_in", e.pos + d * g.vrng.randf_range(140.0, 200.0), -d, c)
		return


## 地面层：骑士的寒气圈（低亮度，0 区域样式：只提示「进来会涨寒冷」，不伤人）；卡门的封锁线；塑路者的生路
static func draw_ground(g) -> void:
	var grains = grains(g)
	if grains != null:
		for e in g.bosses:
			if not e.dead:
				_act_look(g, e, grains)
	for e in g.bosses:
		if not e.dead and e.type == "carmen" and not e.get("fire_lines", []).is_empty():
			_fire_lines(g, e)
		if not e.dead and e.type == "path" and not e.get("paths", []).is_empty():
			_paths(g, e)
		if not e.dead and e.type == "paranoia":
			_paranoia_ground(g, e)
		if not e.dead and e.type == "ishar" and e.phase == 2:
			_web_ground(g, e)
			_song_windup(g, e)
		if not e.dead and e.type == "izumik" and e.phase == 2:
			_izumik_ground(g, e)
		if e.dead or e.type != "knight_boss" or e.phase == 2 or float(e.get("kcold_r", 0.0)) <= 0.0:
			continue
		var r: float = float(e.kcold_r)
		var off: bool = float(e.get("break_t", 0.0)) > 0.0   # 破绽期不涨寒冷：圈变淡
		var al: float = 0.05 if off else 0.11
		g.draw_set_transform(e.pos, 0.0, Vector2(1.0, 0.72))
		# Sparse fractures mark the active first-phase cold field without an opaque disc.
		for j in 12:
			var d := Vector2.from_angle(j*TAU/12)
			var bend := d.rotated(.12 if j%2==0 else -.1)
			g.draw_line(d*r*.42,bend*r*.69,Color(.43,.65,.75,al*1.1),1)
			g.draw_line(bend*r*.69,d*r*.89,Color(.43,.65,.75,al*1.1),1)
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.75, 0.95, 1.0, al * 2.6), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 接潮组「同步」护盾（docs/142b §3.8）：血少的那具身上一圈六边形护盾（专属色、缓慢旋转），读法「这具现在打不动，去打另一具」
static func _shields(g) -> void:
	for e in g.bosses:
		if e.dead or not e.get("pair_shield", false):
			continue
		var c: Color = g.vfx.boss_color(e.type)
		var r: float = float(e.r) * 1.7 + 6.0
		var rot: float = g.t * 0.6
		var pts := PackedVector2Array()
		for k in 7:
			pts.append(e.pos + Vector2.from_angle(rot + TAU * k / 6.0) * r)
		g.draw_colored_polygon(pts.slice(0, 6), Color(c.r, c.g, c.b, 0.10))
		g.draw_polyline(pts, Color(c.r * 0.6 + 0.4, c.g * 0.6 + 0.4, c.b * 0.6 + 0.4, 0.75), 2.5)


## 顶层：接潮护盾；主控脚下的寒冷条（骑士在场且寒冷 > 0 时）；满了之后「冻伤」期间整条变白
static func draw_top(g) -> void:
	_shields(g)
	BreakRing.draw(g)   # 最终 Boss 破绽：脚下金环 + 倒计时弧
	for e in g.bosses:
		if not e.dead and e.type == "paranoia":
			_paranoia_top(g, e)
		if not e.dead and e.type == "ishar" and e.phase == 2:
			_web_top(g, e)
		if not e.dead and e.type == "izumik" and e.phase == 2:
			_izumik_top(g, e)
	for e in g.bosses:
		if e.dead or e.type != "knight_boss":
			continue
		var v: float = clampf(float(e.get("kcold", 0.0)), 0.0, 1.0)
		var bite: bool = float(e.get("frostbite_until", 0.0)) > g.t
		if v <= 0.01 and not bite:
			continue
		var p: Vector2 = g.ppos + Vector2(-22, 16)
		g.draw_rect(Rect2(p - Vector2(1, 1), Vector2(46, 6)), Color(0.02, 0.04, 0.08, 0.85))
		var c: Color = Color(0.95, 1.0, 1.0) if bite else Color(0.55, 0.85, 1.0).lerp(Color(0.9, 0.98, 1.0), v)
		g.draw_rect(Rect2(p, Vector2(44.0 * (1.0 if bite else v), 4)), c)
		return
