extends RefCounted
## 图鉴 / 寻访的入场标志动效（11-05 用户「图鉴和寻访也得加上相关的图标动效，可以参考莱茵生命风格的动效」，参考 github.com/LBEILC/RhineLabUI）。
## 只借它的动效手法（逐笔描边、远处大圆环收拢锁定、卫星点依次出现、对角线合拢解密、磨砂变清、缩小淡出退场，缓动一律 smoothstep），
## 不用莱茵生命的标志、设定与配色；标志 = 罗德岛（用户允许，screens/rhodes_logo.gd），配色 = 本作 PRTS 冷白 + 青。用户定短版 ≤ 0.8 秒。
##   decrypt（图鉴「档案解密」，0.8 秒）：0–0.24 三角外框逐笔描出（线宽由细变粗）、0.1–0.3 标志点亮 → 0.28–0.46 两条对角线从两角向中心合拢
##     → 停 0.06 → 0.52–0.62 收回、标志退 → 0.56–0.8 磨砂层由糊变清揭开图鉴（frost()，宿主用 ui_frost 着色器；不能拷屏时平涂淡出）
##   access（寻访「接入请求」，0.8 秒）：0–0.2 终端逐字打 ACCESS PERMISSION REQUIRED → 0.08–0.4 两道大圆环从屏外收拢锁到标志、扫角 30° → 360°
##     → 0.2–0.42 三角外框描出、标志点亮 → 0.4–0.55 六个卫星点依次亮、中心一闪 → 0.6–0.8 整体缩小（1 → 0.54）+ 淡出，背景退去
## 点击 / 按键跳过并吞掉这次输入（宿主处理）；减少动态效果 ≤ 0.12 秒淡出；无头 / 截图直接终态（宿主 start(test = true)）。
const RhodesLogo = preload("res://scripts/screens/rhodes_logo.gd")
const UIMo = preload("res://scripts/ui_motion.gd")
const BG := Color(0.059, 0.063, 0.075)      # #0F1013
const W := Color(0.925, 0.933, 0.941)       # #ECEEF0
const SUB := Color(0.573, 0.592, 0.627)     # #9297A0
const ACC := Color(0.212, 0.886, 0.863)     # #36E2DC
const T := 0.8
const RM_T := 0.12
# 标志里三角的三个顶点（120 格坐标，按原图采样实测）
const TRI := [Vector2(60, 14), Vector2(114, 103), Vector2(6, 103)]

var kind := "decrypt"
var t0 := -100.0
var rmode := false
var host_frost := false   # 宿主有拷屏磨砂层（揭开阶段底色由它画）


func start(k: String, test := false) -> void:
	kind = k
	t0 = -100.0 if test else UIMo.now()
	rmode = UIMo.rm()


func elapsed() -> float:
	return UIMo.now() - t0


func active() -> bool:
	return elapsed() < (RM_T if rmode else T)


func skip() -> void:
	t0 = -100.0


static func ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


## 图鉴揭开阶段的磨砂量（1 = 全糊、0 = 清）；不在揭开阶段返回 -1
func frost() -> float:
	var t: float = elapsed()
	if kind != "decrypt" or rmode or not active() or t < 0.56:
		return -1.0
	return 1.0 - ss(0.56, 0.8, t)


## 三角外框按周长画到 f（0–1），线宽 w
func _trace(ci: CanvasItem, o: Vector2, s: float, f: float, col: Color, w: float) -> void:
	if f <= 0.0:
		return
	var pts: Array = []
	for v in TRI + [TRI[0]]:
		pts.append(o + (v as Vector2) * s)
	var total := 0.0
	for i in 3:
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var left: float = total * clampf(f, 0.0, 1.0)
	for i in 3:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		if left <= 0.0:
			break
		var e: Vector2 = a.lerp(b, minf(1.0, left / seg))
		ci.draw_line(a, e, col, w, true)
		if left < seg:
			ci.draw_rect(Rect2(e - Vector2(2, 2), Vector2(4, 4)), ACC)   # 笔头
		left -= seg


## 画在宿主画布最上层（宿主自己的画都画完以后调）
func draw(ci: CanvasItem, vs: Vector2, font: Font) -> void:
	var t: float = elapsed()
	if t < 0.0 or not active():
		return
	if rmode:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, 1.0 - t / RM_T))
		return
	if kind == "access":
		_draw_access(ci, vs, font, t)
	else:
		_draw_decrypt(ci, vs, t)


func _logo_geo(vs: Vector2, frac: float) -> Array:
	var span: float = maxf(120.0, roundf(vs.y * frac / 120.0) * 120.0)
	var s: float = span / 120.0
	var o: Vector2 = (vs / 2.0 - Vector2(span, span) / 2.0).round()
	return [o, s, span]


func _draw_decrypt(ci: CanvasItem, vs: Vector2, t: float) -> void:
	var fr: float = frost()
	if fr < 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, ss(0.0, 0.05, t)))
	elif not host_frost:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, fr))   # 没有磨砂层：平涂淡出
	var geo: Array = _logo_geo(vs, 0.3)
	var o: Vector2 = geo[0]
	var s: float = geo[1]
	var out: float = 1.0 - ss(0.5, 0.6, t)
	if out > 0.0:
		var tf: float = ss(0.0, 0.24, t)
		_trace(ci, o, s, tf, Color(W, out), lerpf(0.5, 2.0, ss(0.0, 0.1, t)))
		RhodesLogo.draw_bands(ci, o, s, 120, func(_b): return 0.0, Color(1, 1, 1, ss(0.1, 0.3, t) * out))
	# 对角线：从左上 / 右下两角向中心合拢 → 停 → 收回中心
	var c: Vector2 = vs / 2.0
	var join: float = ss(0.28, 0.46, t)
	var ret: float = ss(0.52, 0.62, t)
	if join > 0.0 and ret < 1.0:
		for corner in [Vector2.ZERO, vs]:
			var head: Vector2 = corner.lerp(c, join)
			var tail: Vector2 = corner.lerp(c, ret)
			ci.draw_line(tail, head, Color(W, 0.85), 1.5, true)
			ci.draw_line(tail, head, Color(ACC, 0.25), 5.0, true)
		if join >= 1.0:
			ci.draw_rect(Rect2(c - Vector2(3, 3), Vector2(6, 6)), Color(ACC, 1.0 - ret))


func _draw_access(ci: CanvasItem, vs: Vector2, font: Font, t: float) -> void:
	var ex: float = ss(0.6, 0.8, t)   # 退场
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, ss(0.0, 0.04, t) * (1.0 - ex)))
	var c: Vector2 = vs / 2.0
	var sc: float = 1.0 - 0.46 * ex
	var al: float = 1.0 - ex * ex * ex
	ci.draw_set_transform(c * (1.0 - sc), 0.0, Vector2(sc, sc))
	var geo: Array = _logo_geo(vs, 0.26)
	var o: Vector2 = geo[0]
	var s: float = geo[1]
	var span: float = geo[2]
	var R: float = span * 0.68
	# 终端逐字
	var msg := "ACCESS PERMISSION REQUIRED"
	var n: int = int(ceil(msg.length() * ss(0.0, 0.2, t)))
	var fs: int = int(round(maxf(11.0, vs.y / 60.0)))
	var tw: float = font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ty: float = c.y - R - 34.0
	ci.draw_string(font, Vector2(c.x - tw / 2.0, ty), msg.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(W, al))
	if n < msg.length() and int(t * 20.0) % 2 == 0:
		var cw: float = font.get_string_size(msg.substr(0, n), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		ci.draw_rect(Rect2(c.x - tw / 2.0 + cw + 2.0, ty - fs * 0.8, fs * 0.5, fs * 0.9), Color(ACC, al))
	# 两道大圆环：从屏外收拢锁定，扫角 30° → 360°
	var rk: float = ss(0.08, 0.4, t)
	var far: float = vs.length()
	for j in 2:
		var r: float = lerpf(far * (1.0 - 0.25 * j), R + 12.0 * j, rk)
		var sweep: float = deg_to_rad(lerpf(30.0, 360.0, rk))
		var a0: float = deg_to_rad(lerpf(470.0, -90.0, rk)) + j * PI
		ci.draw_arc(c, r, a0, a0 + sweep, 128, Color(W if j == 0 else ACC, (0.85 if j == 0 else 0.6) * al), 1.5 if j == 0 else 2.0, true)
	# 三角外框 + 标志
	_trace(ci, o, s, ss(0.2, 0.42, t), Color(W, al), lerpf(0.5, 2.0, ss(0.2, 0.28, t)))
	RhodesLogo.draw_bands(ci, o, s, 120, func(_b): return 0.0, Color(1, 1, 1, ss(0.3, 0.45, t) * al))
	# 卫星点依次亮 + 中心一闪
	for i in 6:
		var dk: float = ss(0.4 + i * 0.025, 0.46 + i * 0.025, t)
		if dk > 0.0:
			var p: Vector2 = c + Vector2.from_angle(-PI / 2.0 + i * TAU / 6.0) * (R + 12.0)
			ci.draw_circle(p, 3.5 * dk, Color(ACC if i % 2 == 0 else W, al))
	var fl: float = ss(0.44, 0.48, t) * (1.0 - ss(0.48, 0.58, t))
	if fl > 0.0:
		ci.draw_circle(c, span * 0.42, Color(ACC, 0.18 * fl * al))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
