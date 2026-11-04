## 后期可读性第一批（docs/247，用户 11-05 批：只改画面、不改玩法和数值）。总开关 render/late_read（缺省 0 = 关，画面与基准一致），
## 各项可用 render/late_read_<项> 单独关（缺省 1 = 随总开关开）：
##   v1 受伤红边按「最近 1 秒承伤占最大生命」驱动（combat.hurt / world 衰减 / hud 红闪）
##   s1 小队 1 像素代表色描边 + 脚底光池（character.draw_body / world._draw_squad_pools）
##   s2 队长被敌方预警盖住时：1 = 照「被友方特效盖」那套画剪影；2 = 整支小队画到预警填充之上（缺省 2，见 docs/247 §3）
##   s3 放置物尺寸下限 + 我方色描边 + 0.8 秒呼吸、画到敌人之上（relic_fx 地雷 / 轰隆隆、逻各斯铭文、艾雅法拉熔池……统一 placed()）
##   v3 拥挤降噪只压装饰层（火花 / 碎片 / 光点 / 拖尾），我方核心恒为 1
##   v7 普通怪受击只 50% 混白（精英 / Boss 照旧整只闪）
##   v5 我方核心主形随精英化 + 等级放大：1 + k × (精英化档 + 等级档)，经 fx_int_scale 取整；E1 起再加 1 格加厚
## 只画不改状态，不抽 g.rng / g.vrng（同 seed TRACE 开关两边逐行一致，docs/36 §3.2）
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

static var _f := -1
static var _on := false
static var _sub := {}


static func _tick() -> void:
	var fn: int = Engine.get_process_frames()
	if fn == _f:
		return
	_f = fn
	_on = Bal.v("render/late_read", 0.0) > 0.0
	_sub.clear()


## 总开关，或某一项（"v1" / "s1" / "s2" / "s3" / "v3" / "v5" / "v7"）是否生效
static func on(item := "") -> bool:
	_tick()
	if not _on:
		return false
	if item == "":
		return true
	var v = _sub.get(item)
	if v == null:
		v = Bal.v("render/late_read_" + item, 1.0)
		_sub[item] = v
	return float(v) > 0.0


## 某一项的模式值（总开关关时返回 0）
static func mode(item: String, def := 1.0) -> float:
	_tick()
	if not _on:
		return 0.0
	return Bal.v("render/late_read_" + item, def)


static func k(key: String, def: float) -> float:
	return Bal.v("render/late_read_" + key, def)


## ---------------- V5：干员特效随成长放大 ----------------
## 档 = 精英化（0 / 1 / 2）+ 等级档（本干员成长节点数 node_lv 0–4 ÷ 4 × lv_w；干员没有独立等级，节点是逐人的成长）；缩放 = 1 + k × 档
static func grow_of(op) -> float:
	if op == null or not on("v5"):
		return 1.0
	var el: int = int(op.get("elite")) if op.get("elite") != null else 0
	var nl: float = float(op.get("node_lv")) if op.get("node_lv") != null else 0.0
	var lvt: float = clampf(nl / 4.0, 0.0, 1.0) * k("v5_lv_w", 0.4)
	return 1.0 + k("v5_k", 0.25) * (float(el) + lvt)


## 放大后的世界缩放（每贴图像素多少世界像素，未除 @2x 密度前的口径，同 vfx.spr_rot 的 scale）：
## 主形本来就大（帧最长边 × 缩放 ≥ v5_cap，缺省 140 世界像素）的不放大；放大后超过 v5_cap 的截到 v5_cap；
## 再经 vfx.int_scale 取整，且不小于原来取整后的值。返回 [缩放, 是否加厚]
static func grow_scale(g, tx: Texture2D, frames: int, base: float, gk: float, hi: float) -> Array:
	var b0: float = g.vfx.int_scale(base)
	if tx == null or gk <= 1.001:
		return [b0, false]
	var dim: float = maxf(float(tx.get_width()) / maxf(1.0, float(frames)), float(tx.get_height())) / maxf(0.01, hi) * absf(base)
	var cap: float = k("v5_cap", 140.0)
	if dim >= cap:
		return [b0, false]
	var t: float = base * minf(gk, cap / maxf(1.0, dim))
	return [signf(base) * maxf(absf(g.vfx.int_scale(t)), absf(b0)), true]


## 加厚档：E1 起 1 格（2 世界像素）描厚，E2 起 1 格 + 主色内芯更亮。0 = 不加厚
static func thick_of(op) -> int:
	if op == null or not on("v5"):
		return 0
	var el: int = int(op.get("elite")) if op.get("elite") != null else 0
	return 1 if el >= 1 else 0


## 画一帧帧条（同 vfx.spr_rot）时的加厚底：同一帧在上下左右各错 1 格、同色降透明度先画一遍，主形笔画整体粗 2 格
static func thick_under(ci, tx: Texture2D, src: Rect2, dst: Rect2, pos: Vector2, ang: float, sc: Vector2, col: Color, a := 0.55) -> void:
	var c := Color(col.r, col.g, col.b, col.a * a)
	var px := 2.0
	for d in [Vector2(-px, 0), Vector2(px, 0), Vector2(0, -px), Vector2(0, px)]:
		ci.draw_set_transform(pos + d, ang, sc)
		ci.draw_texture_rect_region(tx, dst, src, c)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ---------------- S3：放置物统一画法 ----------------
## 我方放置物（地雷 / 轰隆隆 / 铭文 / 熔池……）：本体半径不小于 r_min（缺省 render/late_read_s3_rmin 14），
## 深色底 + 我方色 1 格描边 + 0.8 秒呼吸的内芯（只在本体里亮，不往外扩光环）。ph：相位（按位置定，免得一群一起呼吸）。
## flat：贴地椭圆（y × 0.6）。col：我方色（干员代表色 / 藏品用青白），body：本体底色
static func placed(ci: CanvasItem, pos: Vector2, r: float, col: Color, body: Color, t: float, ph := 0.0, flat := true, pip := Color(0, 0, 0, 0)) -> void:
	var rr: float = maxf(r, k("s3_rmin", 14.0))
	var br: float = 0.5 + 0.5 * sin((t / k("s3_breath", 0.8) + ph) * TAU)
	var sy: float = 0.6 if flat else 1.0
	var p: Vector2 = (pos / 2.0).round() * 2.0
	ci.draw_set_transform(p, 0.0, Vector2(1.0, sy))
	ci.draw_circle(Vector2.ZERO, rr + 2.0, Color(0.02, 0.03, 0.06, 0.85))   # 深色外沿：压在敌人 / 地面上也分得开
	ci.draw_circle(Vector2.ZERO, rr, body)
	var hk: float = k("s3_hdr", 1.6)   # 描边 / 内芯超过 1：暗场（灯火低、深潮）里经光学层照样读得出，只在本体范围内亮
	ci.draw_arc(Vector2.ZERO, rr - 1.0, 0.0, TAU, 28, Color(col.r * hk, col.g * hk, col.b * hk, 0.8 + 0.2 * br), 3.0)
	var ck: float = hk * (0.6 + 0.6 * br)
	ci.draw_circle(Vector2.ZERO, rr * (0.36 + 0.12 * br), Color(col.r * ck, col.g * ck, col.b * ck, 0.6 + 0.4 * br))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if pip.a > 0.0:
		ci.draw_rect(Rect2(p + Vector2(-2, -rr * sy - 4.0), Vector2(4, 4)), pip)


## 大面积地面放置（熔池 / 铭文圈 / 狐火区）：不画填充（填充会盖住敌人），只在敌人之上补一圈我方色 1 格描边 + 呼吸
static func placed_rim(ci: CanvasItem, pos: Vector2, r: float, col: Color, t: float, ph := 0.0, sy := 0.55, a := 0.7) -> void:
	var br: float = 0.5 + 0.5 * sin((t / k("s3_breath", 0.8) + ph) * TAU)
	ci.draw_set_transform((pos / 2.0).round() * 2.0, 0.0, Vector2(1.0, sy))
	ci.draw_arc(Vector2.ZERO, r + 2.0, 0.0, TAU, 40, Color(0.02, 0.03, 0.06, 0.35 * a), 2.0)
	ci.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, a * (0.5 + 0.5 * br)), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 我方放置物统一色（藏品放置物：青白，避开危险红 / 洋红与结晶暖金）
const ALLY_COL := Color(0.55, 0.95, 1.0)
