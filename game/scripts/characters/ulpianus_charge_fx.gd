extends RefCounted
## 乌尔比安 S3「必须开辟的通路」冲锋特效（10-24 用户「三技能的冲锋特效也做一下」，docs/138）：走 docs/136 像素颗粒模板（render/fx_grains.gd，
## 只调用现有 push / spark 接口），分三段——
##   起冲：掷锚飞行期间颗粒向锚尖收拢（蓄力、锚尖聚光），咬地一刻锚处一圈颗粒 + 起点蹬地水花；
##   路径：本体每帧新走过的线段上按 4 px 取样，脚下拖出深海水体颗粒（带冲锋方向的惯性散开、逐颗熄灭，寿命 ≤ 0.3 秒，不留长拖尾），前沿两侧分水；
##   终点：两圈向外的冲击颗粒 + 落到地面高度冷却的水花与碎屑（spark）。
## 沿途 / 落地命中接命中三档（vfx._tier_fx：沿途中档、落地前 6 名重档）。照明不另挂：起点一团拖拽尘帧条 + 落地 fx_splash_blue 帧条由光学观感登记成动态灯（共 ≤ 3 盏）。
## 低画质 / 关光学观感 / 关粒子（fx/grains、fx/ulp_charge_grains = 0、--grainab 轮换到 /g0）时 on() 为假，调用方照旧走锚链拖痕 + 拖拽尘的简化画法。
## 纯画面：随机只用 g.vrng，不碰玩法随机数，同 seed TRACE 不变

const Bal = preload("res://scripts/core/balance.gd")

const DEEP := Color(0.16, 0.34, 0.6)     # 深海暗蓝（水体底色）
const WATER := Color(0.3, 0.6, 0.86)     # 水体本色（乌尔比安本色 0.45 / 0.7 / 0.95 压暗一阶）
const CREST := Color(0.55, 0.82, 1.0)    # 浪尖亮蓝
const DEBRIS := Color(0.36, 0.4, 0.48)   # 碎屑（锚链钢灰压暗）
const PATH_CAP := 36                     # 路径单帧颗粒上限（模板 slash 单帧总上限 140，留给同帧刀光；冲锋约 15 帧 × 36 ≈ 同屏峰值 400 内）


static func grains(o):
	var g = o.g
	if g == null or not g.get("optical_on") or g.optical == null or g.optical.grains == null:
		return null
	var gr = g.optical.grains
	if not gr.on() or gr.off or Bal.v("fx/ulp_charge_grains", 1.0) <= 0.0:
		return null
	return gr


static func on(o) -> bool:
	return grains(o) != null


## 水体颗粒取色：多数本色、少数深色与浪尖
static func _water(g) -> Color:
	var u: float = g.vrng.randf()
	return CREST if u < 0.18 else (DEEP if u < 0.45 else WATER)


## 起冲（掷锚飞行中每帧）：锚尖周围 10–16 px 一圈颗粒朝锚尖收拢；k 为掷锚进度 0–1，越接近咬地越密
static func windup(o, tip: Vector2, k: float) -> void:
	var gr = grains(o)
	if gr == null:
		return
	var g = o.g
	var n: int = 2 + int(4.0 * k)
	if gr.level < 2:
		n = maxi(1, n / 2)
	for i in n:
		var a: float = g.vrng.randf() * TAU
		var rr: float = g.vrng.randf_range(10.0, 16.0)
		var p: Vector2 = tip + Vector2(cos(a) * rr, sin(a) * rr * 0.7)
		gr.push("slash", p, (tip - p).normalized(), CREST if g.vrng.randf() < 0.6 else WATER)


## 咬地一刻（冲锋开始）：锚处一圈向外的颗粒 + 起点向身后蹬出的水花
static func launch(o, start: Vector2, to: Vector2, dir: Vector2) -> void:
	var gr = grains(o)
	if gr == null:
		return
	var g = o.g
	var full: bool = gr.level >= 2
	var n: int = 20 if full else 10
	for i in n:
		var a: float = TAU * float(i) / float(n) + g.vrng.randf_range(-0.15, 0.15)
		var dv := Vector2(cos(a), sin(a) * 0.45)
		gr.push("slash", to + dv * 8.0, dv.normalized(), CREST if i % 3 == 0 else WATER)
	var foot: Vector2 = start + Vector2(0, 4)
	for i in (12 if full else 6):
		var side: float = g.vrng.randf_range(-1.0, 1.0)
		var p: Vector2 = foot + dir.orthogonal() * side * 8.0
		gr.push("slash", p, (-dir + dir.orthogonal() * side * 0.9).normalized(), _water(g))
	gr.spark(foot + Vector2(0, -4), foot.y + 2.0, WATER, 4 if full else 2)


## 冲锋路径（每帧）：本帧位移线段 a→c 上每 4 px 一个取样点（中画质 8 px），每点脚下 3 条横排（中间一条贴着位移线、两侧各偏 6 px），
## 初速方向 = 冲锋方向（惯性，模板 spread 内散开），两侧偏外；前沿另向两侧分水。单帧超 PATH_CAP 均匀抽稀
static func path(o, a: Vector2, c: Vector2) -> void:
	var gr = grains(o)
	if gr == null:
		return
	var g = o.g
	var seg: Vector2 = c - a
	var L: float = seg.length()
	if L < 0.5:
		return
	var d: Vector2 = seg / L
	var nv: Vector2 = d.orthogonal()
	var step: float = 4.0 if gr.level >= 2 else 8.0
	var cells: Array = []
	var ns: int = maxi(1, int(L / step))
	for i in ns:
		var q: Vector2 = a.lerp(c, (float(i) + g.vrng.randf()) / float(ns)) + Vector2(0, 4)
		for side in [-1.0, 0.0, 1.0]:
			var p: Vector2 = q + nv * (side * 6.0 + g.vrng.randf_range(-1.5, 1.5))
			cells.append([p, (d + nv * side * 0.7).normalized()])
	var stride: float = maxf(1.0, float(cells.size()) / float(PATH_CAP))
	var k := 0.0
	while int(k) < cells.size():
		var cl: Array = cells[int(k)]
		gr.push("slash", cl[0], cl[1], _water(g))
		k += stride
	# 前沿分水：身前两侧各 2 颗，朝外偏前
	for side in [-1.0, 1.0]:
		for j in 2:
			gr.push("slash", c + Vector2(0, 4) + nv * side * 9.0, (nv * side + d * 0.5).normalized(), CREST if j == 0 else WATER)


## 落地：两圈向外的冲击颗粒（扁椭圆贴地，与 ulp_wave 水环同比例）+ 一圈落到地面冷却的水花与碎屑
static func land(o, c: Vector2, r: float) -> void:
	var gr = grains(o)
	if gr == null:
		return
	var g = o.g
	var full: bool = gr.level >= 2
	var r0: float = clampf(r * 0.12, 12.0, 22.0)
	for ring in 2:
		var rr: float = r0 * (1.0 + float(ring))
		var n: int = (28 if ring == 0 else 36) if full else (14 if ring == 0 else 18)
		for i in n:
			var a: float = TAU * float(i) / float(n) + g.vrng.randf_range(-0.1, 0.1)
			var dv := Vector2(cos(a), sin(a) * 0.42)
			gr.push("slash", c + dv * rr, dv.normalized(), (CREST if ring == 0 else WATER) if i % 4 else DEEP)
	for i in (8 if full else 4):
		var a: float = TAU * float(i) / 8.0 + g.vrng.randf_range(-0.3, 0.3)
		var p: Vector2 = c + Vector2(cos(a), sin(a) * 0.42) * g.vrng.randf_range(6.0, r0 * 1.6)
		gr.spark(p + Vector2(0, -6), p.y, CREST if i % 2 == 0 else WATER, 3)
		if i % 2 == 1:
			gr.spark(p + Vector2(0, -2), p.y + 2.0, DEBRIS, 2)


## 命中三档：沿途中档（2）、落地重档（3）；vfx 不在（单元测试的假 g）就跳过
static func hit(o, e: Dictionary, tier: int) -> void:
	var g = o.g
	if g == null or g.get("vfx") == null or not g.vfx.has_method("_tier_fx"):
		return
	g.vfx._tier_fx(e, {"op": str(o.id)}, tier)
