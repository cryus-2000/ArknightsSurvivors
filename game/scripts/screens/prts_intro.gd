extends RefCounted
## 图鉴 / 寻访的入场标志动效（11-05 用户「图鉴和寻访也得加上相关的图标动效，可以参考莱茵生命风格的动效」，参考 github.com/LBEILC/RhineLabUI）。
## 只借它的动效手法（逐笔描边、远处大圆环收拢锁定、卫星点依次出现、对角线合拢解密、磨砂变清、缩小淡出退场，缓动一律 smoothstep），
## 不用莱茵生命的标志、设定与配色；标志 = 罗德岛（用户允许，screens/rhodes_logo.gd），配色 = 本作 PRTS 冷白 + 青。用户定短版 ≤ 0.8 秒。
##   decrypt（图鉴「档案解密」，0.8 秒）：0–0.24 三角外框逐笔描出（线宽由细变粗）、0.1–0.3 标志点亮 → 0.28–0.46 两条对角线从两角向中心合拢
##     → 停 0.06 → 0.52–0.62 收回 → 0.62–0.7 档案轮廓闪一下 → 0.66–0.78 轮廓撑满全屏 → 0.74–0.92 磨砂层由糊变清揭开图鉴（frost()，宿主用 ui_frost 着色器；不能拷屏时平涂淡出）
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
const T_DEC := 0.92   # 图鉴：收尾加「轮廓闪一下 → 撑满全屏进去」（11-05 用户「结束得很突兀，最后凭证的轮廓闪一下然后就进去」）
const RM_T := 0.12
# 标志里三角的三个顶点（120 格坐标，按原图采样实测）
const TRI := [Vector2(60, 14), Vector2(114, 103), Vector2(6, 103)]

var kind := "decrypt"
var t0 := -100.0
var rmode := false
var slow := 1.0   # 时间轴放慢倍数（图鉴 1.5 = 1.2 秒，11-05 用户「可以稍微慢一点」）；下面写的秒数都是 1 倍时的
var info := {}   # 宿主给的档案信息：count / total（图鉴收录数）
var host_frost := false   # 宿主有拷屏磨砂层（揭开阶段底色由它画）


func start(k: String, test := false) -> void:
	kind = k
	t0 = -100.0 if test else UIMo.now()
	rmode = UIMo.rm()


func elapsed() -> float:
	return (UIMo.now() - t0) / slow


func active() -> bool:
	return (UIMo.now() - t0) < (RM_T if rmode else (T_DEC if kind == "decrypt" else T) * slow)


func skip() -> void:
	t0 = -100.0


static func ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


## 图鉴揭开阶段的磨砂量（1 = 全糊、0 = 清）；不在揭开阶段返回 -1
func frost() -> float:
	var t: float = elapsed()
	if kind != "decrypt" or rmode or not active() or t < 0.74:
		return -1.0
	return 1.0 - ss(0.74, 0.92, t)


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
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, 1.0 - (UIMo.now() - t0) / RM_T))
		return
	if kind == "access":
		_draw_access(ci, vs, font, t)
	else:
		_draw_decrypt(ci, vs, font, t)


func _logo_geo(vs: Vector2, frac: float) -> Array:
	var span: float = maxf(120.0, roundf(vs.y * frac / 120.0) * 120.0)
	var s: float = span / 120.0
	var o: Vector2 = (vs / 2.0 - Vector2(span, span) / 2.0).round()
	return [o, s, span]


func _draw_decrypt(ci: CanvasItem, vs: Vector2, font: Font, t: float) -> void:
	# 11-05 二版（用户「图鉴的会不会有点太简约了，只是一个线条」）：做成一份档案——取景框四角收拢、页眉逐字 + 编号滚动、
	# 右侧四行遮挡条（像涂黑的机密）解密时从左往右退开露出档案信息、对角线加两道细伴线、合拢时中心闪 DECRYPTED，再磨砂变清
	var fr: float = frost()
	if fr < 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, ss(0.0, 0.05, t)))
	elif not host_frost:
		ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(BG, fr))   # 没有磨砂层：平涂淡出
	var out: float = 1.0 - ss(0.66, 0.7, t)   # 档案内容一直留到轮廓闪完
	var c: Vector2 = vs / 2.0
	var u: float = vs.y / 540.0   # 以 540 高为基准
	var geo: Array = _logo_geo(vs, 0.28)
	var s: float = geo[1]
	var span: float = geo[2]
	var gap: float = 26.0 * u
	var pw: float = 230.0 * u   # 右侧档案栏宽
	var gw: float = span + gap + pw
	var o := Vector2(roundf(c.x - gw / 2.0), roundf(c.y - span / 2.0))
	if out > 0.0:
		# 取景框：四角从外 40 收拢锁定
		var fb := Rect2(o - Vector2(18, 30) * u, Vector2(gw, span) + Vector2(36, 48) * u)
		var lk: float = (1.0 - ss(0.02, 0.22, t)) * 40.0 * u
		var L: float = 16.0 * u
		var fc := Color(W, 0.75 * out)
		for k in 4:
			var sx: float = -1.0 if k % 2 == 0 else 1.0
			var sy: float = -1.0 if k < 2 else 1.0
			var p: Vector2 = Vector2(fb.position.x if sx < 0 else fb.end.x, fb.position.y if sy < 0 else fb.end.y) + Vector2(sx, sy) * lk
			ci.draw_line(p, p + Vector2(-sx * L, 0), fc, 1.5)
			ci.draw_line(p, p + Vector2(0, -sy * L), fc, 1.5)
		# 页眉：逐字 + 编号滚动；下面一条细线从左长出
		var fs: int = int(round(10.0 * u))
		var head := "PRTS // OPERATOR ARCHIVE"
		var hn: int = int(ceil(head.length() * ss(0.04, 0.24, t)))
		ci.draw_string(font, Vector2(fb.position.x + 4.0 * u, fb.position.y + 14.0 * u), head.substr(0, hn), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(W, out))
		var no: int = int(round(lerpf(0.0, float(info.get("count", 0)), ss(0.06, 0.4, t))))
		var nos := "FILE No.%03d" % no
		ci.draw_string(font, Vector2(fb.end.x - 4.0 * u - font.get_string_size(nos, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, fb.position.y + 14.0 * u), nos, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(SUB, out))
		ci.draw_rect(Rect2(fb.position.x + 4.0 * u, fb.position.y + 20.0 * u, (fb.size.x - 8.0 * u) * ss(0.04, 0.26, t), 1), Color(SUB, 0.6 * out))
		# 标志：三角外框逐笔描出 → 点亮
		_trace(ci, o, s, ss(0.0, 0.24, t), Color(W, out), lerpf(0.5, 2.0, ss(0.0, 0.1, t)))
		RhodesLogo.draw_bands(ci, o, s, 120, func(_b): return 0.0, Color(1, 1, 1, ss(0.1, 0.3, t) * out))
		# 右侧档案栏：四行信息，上面压着遮挡条，0.3–0.46 逐行从左往右退开
		var px: float = o.x + span + gap
		var rows := [["档案类别", "干员"], ["权限等级", "Ⅲ"], ["收录", "%d / %d" % [info.get("count", 0), info.get("total", 0)]], ["状态", "已解密"]]
		var rh: float = span / 4.0
		var fs2: int = int(round(12.0 * u))
		for i in 4:
			var ry: float = o.y + i * rh
			var y0: float = ry + rh * 0.5
			var shown: float = ss(0.3 + i * 0.03, 0.42 + i * 0.03, t)
			ci.draw_rect(Rect2(px, ry + rh - 1.0, pw, 1), Color(SUB, 0.3 * out))
			if shown > 0.0:
				ci.draw_string(font, Vector2(px, y0 + fs2 * 0.35), str(rows[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(SUB, out))
				var vc: Color = ACC if i == 3 else W
				ci.draw_string(font, Vector2(px, y0 + fs2 * 0.35), str(rows[i][1]), HORIZONTAL_ALIGNMENT_RIGHT, pw, fs2, Color(vc, out * ss(0.4, 0.9, shown)))
			var bw: float = pw * (0.55 + 0.4 * absf(sin(i * 1.7 + 0.4))) * ss(0.06 + i * 0.02, 0.16 + i * 0.02, t)   # 遮挡条先从左长出
			var keep: float = 1.0 - shown
			if keep > 0.0 and bw > 0.0:
				var bx: float = px + bw * (1.0 - keep)   # 遮挡条从左往右退开：先露出字段名
				ci.draw_rect(Rect2(bx, y0 - 6.0 * u, bw * keep, 12.0 * u), Color(0.2, 0.21, 0.24, out))
				if shown > 0.0:
					ci.draw_rect(Rect2(bx, y0 - 6.0 * u, 2.0 * u, 12.0 * u), Color(ACC, 0.9 * out))
	# 收尾：档案轮廓闪一下（0.62–0.7）→ 轮廓撑满全屏、淡出（0.66–0.78），像镜头钻进档案；之后磨砂变清
	var fb2 := Rect2(o - Vector2(18, 30) * u, Vector2(gw, span) + Vector2(36, 48) * u)
	var fl2: float = ss(0.62, 0.65, t) * (1.0 - ss(0.66, 0.74, t))
	var ex: float = ss(0.66, 0.78, t)
	if fl2 > 0.0 or (ex > 0.0 and ex < 1.0):
		var r2 := Rect2(fb2.position.lerp(Vector2.ZERO, ex), fb2.size.lerp(vs, ex))
		var la: float = maxf(fl2, (1.0 - ex) * 0.8) if ex > 0.0 else fl2
		ci.draw_rect(r2.grow(3.0 * u), Color(ACC, 0.35 * la), false, 6.0 * u)
		ci.draw_rect(r2, Color(W, la), false, 2.0 * u)
		if fl2 > 0.0:
			ci.draw_rect(fb2, Color(W, 0.08 * fl2))
	# 对角线：主线 + 两道细伴线，从左上 / 右下两角向中心合拢 → 停 → 收回中心
	var join: float = ss(0.28, 0.46, t)
	var ret: float = ss(0.52, 0.62, t)
	if join > 0.0 and ret < 1.0:
		var nrm: Vector2 = Vector2(vs.y, -vs.x).normalized()
		for corner in [Vector2.ZERO, vs]:
			var head: Vector2 = corner.lerp(c, join)
			var tail: Vector2 = corner.lerp(c, ret)
			ci.draw_line(tail, head, Color(ACC, 0.22), 6.0, true)
			ci.draw_line(tail, head, Color(W, 0.9), 1.5, true)
			for side in [-1.0, 1.0]:
				var off: Vector2 = nrm * side * 9.0 * u
				var h2: Vector2 = corner.lerp(c, join * 0.92)
				ci.draw_line(tail + off, h2 + off, Color(W, 0.3), 1.0, true)
		if join >= 1.0:
			var fl: float = 1.0 - ret
			ci.draw_rect(Rect2(c - Vector2(4, 4) * u, Vector2(8, 8) * u), Color(ACC, fl))
			var dfs: int = int(round(10.0 * u))
			var dt := "DECRYPTED"
			var dw: float = font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs).x
			ci.draw_rect(Rect2(c.x - dw / 2.0 - 6.0 * u, c.y - 12.0 * u - dfs - 2.0 * u, dw + 12.0 * u, dfs + 8.0 * u), Color(BG, 0.92 * fl))   # 底板：别压在档案字上
			ci.draw_string(font, Vector2(c.x - font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs).x / 2.0, c.y - 12.0 * u), dt, HORIZONTAL_ALIGNMENT_LEFT, -1, dfs, Color(ACC, fl))


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
