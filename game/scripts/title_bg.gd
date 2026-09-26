extends Control
## 标题背景：蓝眼泪银河沙滩（全部程序生成，像素风）
## 画布 640×360，按 ×2 最近邻放大到 1280×720，与游戏内像素密度一致。
## 分层：天空与银河（预渲染）→ 远方海嗣剪影（巨型海嗣 + 海平线上的海嗣群，眼睛微光）→ 远景（礁石、深蓝之树剪影）→ 海面倒影与发光浪尖 → 海中水母 → 沙滩（湿沙 → 过渡 → 月光干沙）→ 涌浪与蓝眼泪 → 博士与水月（倒影只落在湿沙上）→ 发光叠加层
## 人物：博士站在浪边，身旁是本地图的固定人物（data/maps/<id>.json 的 title_guest，深海 = 水月）。

const A = preload("res://scripts/art.gd")
const TitleTree = preload("res://scripts/title_tree.gd")

const W := 640
const H := 360
const HZ := 150            # 海平线
const SHORE := 238         # 静水时的岸线
const K := 2.0             # 基准放大倍率（1280×720 时）
var ks := 2.0              # 实际倍率：按视口「覆盖」缩放，宽屏 / 高屏都不留边
const WAVE_PERIOD := 7.5
const FEET := Vector2(432, 311)          # 博士脚底
const GUEST_FEET := Vector2(482, 305)    # 地图固定人物（水月）：博士右侧稍后
const DOCTOR_TINT := Color(1.18, 1.22, 1.3)  # 博士衣服偏深，稍微提亮

var t := 0.0
var rng := RandomNumberGenerator.new()
var tex_sky: ImageTexture
var tex_sand: ImageTexture
var doctor := {}            # {idle: Texture2D, fi: 帧数, fps}
var guest := {}             # 地图固定人物 {idle, fi, fps}
var tex_light: Texture2D
var stars: Array = []       # [pos, size, phase, speed, col]
var crests: Array = []      # 远处发光浪尖 {y, x0, x1, life, max}
var tears: Array = []       # 沙滩上的蓝眼泪光点 {pos, life, max, ph}
var motes: Array = []       # 上升的荧光颗粒 {pos, v, ph}
var jellies: Array = []     # 海里的发光水母 {pos, r, ph, spd, col}
## 沙滩分带（按离岸线的距离 d，画布像素）：d < WET_END 湿沙（能反光），到 DRY_START 过渡完，之后是干沙
const WET_END := 40.0
const DRY_START := 78.0
const JELLY_COLS := [Color(0.35, 0.9, 1.0), Color(0.55, 0.6, 1.0), Color(1.0, 0.55, 0.85)]
var meteor := {}
var next_meteor := 3.0
var next_crest := 0.0
var tree: RefCounted        # 远景深蓝之树（title_tree.gd，一次性栅格化）
var tex_tree: ImageTexture
var tex_tree_glow: ImageTexture
var tex_terror: ImageTexture   # 远方海嗣剪影（海平线以上）
var terror_eyes: Array = []    # [pos, phase, col]
const TREE_BASE := Vector2(505, HZ + 2)
var off := Vector2.ZERO     # 画面居中偏移（非 16:9 窗口时）
var zoom := 1.0             # 旧开场的放大（已不用：非整数倍会糊，保留变量以免外部引用报错）
var pan := 0.0              # 开场镜头下摇：整幅画往下挪的原图像素数（取整，按 ks 整倍平移，不缩放）
var reveal := 1.0           # 开场：发光脚印依次亮起的进度 0–1
var eye_flash := 0.0        # 开场：远方海嗣睁眼一瞬的亮度加成
var steps: Array = []       # 发光脚印
var glow: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.seed = 20260924
	tex_light = A.tex("light")
	_load_figures()
	_build_sky()
	_build_sand()
	for i in 170:
		var p := Vector2(rng.randf_range(0, W), rng.randf_range(0, HZ - 6))
		var big := rng.randf() < 0.1
		var col := Color(0.8, 0.9, 1.0).lerp(Color(0.7, 0.8, 1.0) if rng.randf() < 0.5 else Color(1.0, 0.9, 0.8), rng.randf() * 0.6)
		stars.append([p, 2 if big else 1, rng.randf() * TAU, rng.randf_range(0.6, 2.4), col])
	for i in 40:
		motes.append({"pos": Vector2(rng.randf_range(200, W), rng.randf_range(170, H)), "v": rng.randf_range(3, 9), "ph": rng.randf() * TAU})
	for i in 5:
		jellies.append(_new_jelly(rng.randf_range(HZ + 8, SHORE - 24)))
	_build_terrors()
	tree = TitleTree.new()
	tree.build(W, H, TREE_BASE, 205.0, 7)
	tex_tree = ImageTexture.create_from_image(tree.img)
	tex_tree_glow = ImageTexture.create_from_image(tree.glow)
	# 走来的脚印（从左下到脚边）
	for i in 7:
		var k := float(i) / 6.0
		var p := Vector2(250, 352).lerp(FEET + Vector2(-14, 8), k)
		steps.append([p + Vector2(0, 3 if i % 2 == 0 else -3), 0.3 + 0.7 * k])
	# 发光叠加层（加法混合）
	glow = Control.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.draw.connect(_draw_glow)
	add_child(glow)
	# 开场先让几道浪、几颗蓝眼泪已经在场上
	for i in 90:
		_step(0.1)


func _process(delta: float) -> void:
	_step(delta)
	queue_redraw()
	glow.queue_redraw()


func _step(dt: float) -> void:
	t += dt
	# 流星
	next_meteor -= dt
	if next_meteor <= 0.0:
		next_meteor = rng.randf_range(4.0, 9.0)
		meteor = {"p": Vector2(rng.randf_range(180, 600), rng.randf_range(4, 60)), "v": Vector2(-rng.randf_range(160, 240), rng.randf_range(50, 90)), "life": 0.9}
	if not meteor.is_empty():
		meteor.p += meteor.v * dt
		meteor.life -= dt
		if meteor.life <= 0.0:
			meteor = {}
	# 远处发光浪尖：从海平线附近生成，向岸边移动、变长、再熄灭
	next_crest -= dt
	if next_crest <= 0.0:
		next_crest = rng.randf_range(0.08, 0.2)
		var cx := rng.randf_range(160, W + 40)
		var mx := 3.2 if rng.randf() < 0.5 else 2.2
		crests.append({"y": HZ + 6 + pow(rng.randf(), 0.7) * (SHORE - 26 - HZ), "x0": cx - rng.randf_range(10, 40), "x1": cx + rng.randf_range(10, 60), "life": mx, "max": mx})
	for c in crests:
		c.life -= dt
		c.y += dt * (2.0 + (c.y - HZ) * 0.06)
		c.x0 -= dt * 4.0
		c.x1 += dt * 4.0
	crests = crests.filter(func(c): return c.life > 0.0 and c.y < SHORE)
	# 涌浪前沿：冲上沙滩时沿线留下蓝眼泪
	for i in 3:
		var p := fmod(t / WAVE_PERIOD + i / 3.0, 1.0)
		for q in int(dt * 140.0 + rng.randf()) if p < 0.42 else 0:
			var x := rng.randf_range(120, W)
			tears.append({"pos": Vector2(x, _wave_y(i, x) + rng.randf_range(-1, 2)), "life": rng.randf_range(2.5, 6.0), "max": 6.0, "ph": rng.randf() * TAU})
	for tr in tears:
		tr.life -= dt
	tears = tears.filter(func(tr): return tr.life > 0.0)
	if tears.size() > 900:
		tears = tears.slice(tears.size() - 900)
	# 水母：伞盖一收一放地往上游（收缩时推进最快），左右轻摆；游到海平线附近从近岸处换一只
	for j in jellies:
		j.ph += dt * j.spd
		var push: float = maxf(0.0, sin(j.ph)) * 1.6 + 0.25
		j.pos.y -= push * 2.2 * dt
		j.pos.x += sin(j.ph * 0.37) * 1.5 * dt
		if j.pos.y < HZ + 6:
			var nj := _new_jelly(SHORE - 24.0)
			for k in nj:
				j[k] = nj[k]
	for m in motes:
		m.pos.y -= m.v * dt
		m.pos.x += sin(t * 0.8 + m.ph) * 4.0 * dt
		if m.pos.y < HZ + 10:
			m.pos = Vector2(rng.randf_range(200, W), H + 4)


## 第 i 道浪在 x 处的前沿高度（冲上 → 退回）
func _wave_front(i: int) -> float:
	var p := fmod(t / WAVE_PERIOD + i / 3.0, 1.0)
	var reach := 58.0 + 8.0 * sin(i * 2.1)
	var k: float
	if p < 0.42:
		k = 1.0 - pow(1.0 - p / 0.42, 2.2)          # 冲上沙滩：先快后慢
	else:
		k = 1.0 - smoothstep(0.42, 1.0, p)          # 退回
	return SHORE - 6.0 + reach * k


func _wave_y(i: int, x: float) -> float:
	# 越靠右（离观众越远）浪冲得越短，形成斜向海岸
	var slant := (x - 320.0) * 0.07
	return _wave_front(i) - slant + 3.0 * sin(x * 0.035 + i * 1.9) + 1.5 * sin(x * 0.11 + t * 1.3 + i)


func _wave_phase(i: int) -> float:
	return fmod(t / WAVE_PERIOD + i / 3.0, 1.0)


# ------------------------------------------------------------------ 绘制
func _draw() -> void:
	# 非 16:9 的窗口：按覆盖方式放大并居中裁切，不留边
	var vs := get_viewport_rect().size
	ks = K * maxf(vs.x / (W * K), vs.y / (H * K)) * zoom
	off = ((vs - Vector2(W, H) * ks) / 2.0).round() + Vector2(0, round(pan) * ks)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.03))
	draw_set_transform(off, 0.0, Vector2(ks, ks))
	draw_texture(tex_sky, Vector2.ZERO)
	# 星星闪烁
	for s in stars:
		var a: float = 0.35 + 0.65 * pow(0.5 + 0.5 * sin(t * s[3] + s[2]), 2.0)
		var c: Color = s[4]
		draw_rect(Rect2(s[0], Vector2(1, 1)), Color(c.r, c.g, c.b, a))
		if s[1] == 2 and a > 0.7:
			draw_rect(Rect2(s[0] + Vector2(-1, 0), Vector2(3, 1)), Color(c.r, c.g, c.b, (a - 0.7) * 1.6))
			draw_rect(Rect2(s[0] + Vector2(0, -1), Vector2(1, 3)), Color(c.r, c.g, c.b, (a - 0.7) * 1.6))
	# 远景：深蓝之树（海平线右侧）与水面倒影（压扁、随水波轻晃、越远越淡）
	# 远方海嗣：随海面缓慢起伏（往下沉 0–2 像素，海平线以下裁掉）；海面上一道暗倒影
	var sink: float = round(1.0 + sin(t * 0.33))
	draw_texture_rect_region(tex_terror, Rect2(Vector2(0, sink), Vector2(W, HZ + 2 - sink)), Rect2(Vector2.ZERO, Vector2(W, HZ + 2 - sink)))
	draw_set_transform(off + Vector2(sin(t * 0.7) * 1.0 * ks, (HZ + 2) * ks), 0.0, Vector2(ks, -ks * 0.4))
	draw_texture_rect_region(tex_terror, Rect2(Vector2(0, -(HZ + 2)), Vector2(W, HZ + 2)), Rect2(0, 0, W, HZ + 2), Color(0.3, 0.3, 0.5, 0.35))
	draw_set_transform(off, 0.0, Vector2(ks, ks))
	draw_texture(tex_tree, Vector2.ZERO)
	draw_set_transform(off + Vector2(sin(t * 0.9) * 1.2 * ks, (HZ + 2) * ks), 0.0, Vector2(ks, -ks * 0.45))
	draw_texture_rect_region(tex_tree, Rect2(Vector2(0, -(HZ + 2)), Vector2(W, HZ + 2)), Rect2(0, 0, W, HZ + 2), Color(0.5, 0.65, 0.85, 0.32))
	draw_set_transform(off, 0.0, Vector2(ks, ks))
	# 海里的水母（本体半透明，发光部分在加法层）
	for j in jellies:
		_draw_jelly(j, false)
	# 沙滩（岸线以下）
	draw_texture(tex_sand, Vector2(0, SHORE - 30))
	# 发光脚印
	for si in steps.size():
		var st: Array = steps[si]
		var sk: float = clampf(reveal * steps.size() - si, 0.0, 1.0)   # 开场：从远到近一枚枚亮起，刚亮时更亮
		if sk <= 0.0:
			continue
		var a: float = st[1] * (0.35 + 0.25 * sin(t * 1.5 + st[0].x)) * sk + (1.0 - sk) * 0.9 * float(sk > 0.0)
		draw_rect(Rect2(st[0].round(), Vector2(3, 1)), Color(0.3, 0.75, 1.0, a))
	# 涌浪：从后到前画三道水膜
	var order := [0, 1, 2]
	order.sort_custom(func(a, b): return _wave_front(a) < _wave_front(b))
	for i in order:
		_draw_wave(i)
	# 博士与水月（含倒影）
	_draw_figures()
	# 左侧压暗，保证菜单文字清晰
	var scrim := PackedColorArray([Color(0.0, 0.01, 0.03, 0.72), Color(0.0, 0.01, 0.03, 0.0), Color(0.0, 0.01, 0.03, 0.0), Color(0.0, 0.01, 0.03, 0.72)])
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(300, H), Vector2(0, H)]), scrim)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_wave(i: int) -> void:
	var p := _wave_phase(i)
	var adv := p < 0.42
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var top := float(HZ + 20)
	var x := 0.0
	while x <= W:
		pts.append(Vector2(x, top))
		x += 8.0
	x = W
	while x >= 0.0:
		pts.append(Vector2(x, _wave_y(i, x)))
		x -= 8.0
	var wa := 0.5 if adv else 0.5 * (1.0 - smoothstep(0.42, 1.0, p))
	for k in pts.size():
		var d: float = (pts[k].y - top) / 90.0
		cols.append(Color(0.02, 0.07, 0.16, wa * (0.4 + 0.6 * d)))
	draw_polygon(pts, cols)
	# 湿沙反光：刚退下去的一条暗亮带
	if not adv:
		var x2 := 150.0
		while x2 < W:
			var y := _wave_y(i, x2)
			draw_rect(Rect2(Vector2(x2, y + 1).round(), Vector2(4, 1)), Color(0.25, 0.4, 0.6, 0.12 * (1.0 - p)))
			x2 += 4.0


func _load_figures() -> void:
	var dd: Dictionary = _json("res://data/doctor.json").get("sprites", {})
	var dt: Texture2D = A.tex(str(dd.get("idle", "doctor_idle")))
	if dt == null:
		dt = A.tex("doctor")
	if dt != null:
		doctor = {"idle": dt, "fi": maxi(1, dt.get_width() / dt.get_height()), "fps": 4.0}
	var gid: String = str(_json("res://data/maps/%s.json" % Cfg.map_id).get("title_guest", ""))
	if gid != "":
		var gs := _slot(_json("res://data/characters/%s.json" % gid).get("sprites", {}).get("idle"))
		if not gs.is_empty():
			guest = {"idle": gs.tex, "fi": gs.n, "fps": gs.fps}


## 贴图槽：字符串或 {tex, frames, fps}
func _slot(v) -> Dictionary:
	if v == null:
		return {}
	var tn: String = v if v is String else str(v.get("tex", ""))
	var tx: Texture2D = A.tex(tn) if tn != "" else null
	if tx == null:
		return {}
	var n: int = int(v.frames) if v is Dictionary and v.has("frames") else maxi(1, tx.get_width() / tx.get_height())
	var fps: float = float(v.get("fps", 4.0)) if v is Dictionary else 4.0
	return {"tex": tx, "n": n, "fps": fps}


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _draw_figures() -> void:
	# 水月在后（先画），博士在前
	if not guest.is_empty():
		_draw_figure(guest.idle, guest.fi, guest.fps, GUEST_FEET, 0.2, 2)
	if not doctor.is_empty():
		_draw_figure(doctor.idle, doctor.fi, doctor.fps, FEET, 0.0, 2, 1.0, DOCTOR_TINT)


## 站在浅水里的人物：逐行错位的水波倒影 + 本体（帧条横向等宽，脚底在帧底部上方 foot_up 像素）
func _draw_figure(tx: Texture2D, frames: int, fps: float, feet: Vector2, phase: float, foot_up: int, alpha := 1.0, tint := Color.WHITE) -> void:
	var fh := tx.get_height()
	var fw := tx.get_width() / frames
	var f := int(t * fps + phase * 10.0) % frames
	var sc: float = 2.0 / A.hires_of(tx)
	foot_up = int(foot_up * A.hires_of(tx))
	var pos := feet - Vector2(fw * sc * 0.5, (fh - foot_up) * sc)
	var wet := 0.55
	for row in fh:
		var src := Rect2(f * fw, fh - 1 - row, fw, 1)
		var off := sin(t * 2.2 + row * 0.5 + phase) * (0.6 + row * 0.03)
		var dst := Rect2(Vector2(pos.x + off, feet.y - foot_up * sc + row * sc), Vector2(fw * sc, sc))
		var wy: float = feet.y - foot_up * sc + row * sc
		var damp: float = _wetness(feet.x, wy)
		if damp <= 0.02:
			continue
		draw_texture_rect_region(tx, dst, src, Color(0.35, 0.55, 0.95, wet * (1.0 - float(row) / fh) * 0.55 * alpha * damp))
	draw_texture_rect_region(tx, Rect2(pos.round(), Vector2(fw, fh) * sc), Rect2(f * fw, 0, fw, fh), Color(tint.r, tint.g, tint.b, alpha))


## 加法发光层：银河亮核、蓝眼泪、浪尖、荧光颗粒、流星
func _draw_glow() -> void:
	glow.draw_set_transform(off, 0.0, Vector2(ks, ks))
	# 深蓝之树：整体柔光呼吸 + 树冠光环 + 枝梢星点 + 沿主干上行的能量脉冲
	var tb := 0.85 + 0.15 * sin(t * 0.6)
	glow.draw_texture(tex_tree_glow, Vector2.ZERO, Color(tb, tb, tb, 1.0))
	# 海嗣的眼睛：暗红 / 紫色微光，各自慢慢明灭（偶尔整只熄掉，像在眨眼）
	var sink2: float = round(1.0 + sin(t * 0.33))
	for e in terror_eyes:
		var ea: float = pow(0.5 + 0.5 * sin(t * 0.8 + e[1]), 2.0)
		if sin(t * 0.21 + e[1] * 3.0) > 0.93:
			ea *= 0.1
		ea = minf(1.0, ea + eye_flash)   # 开场：远方海嗣齐齐睁眼一瞬
		var ep: Vector2 = e[0] + Vector2(0, sink2)
		if ep.y >= HZ:
			continue
		var ec: Color = e[2]
		glow.draw_rect(Rect2(ep, Vector2(1, 1)), Color(ec.r, ec.g, ec.b, 0.9 * ea))
		glow.draw_rect(Rect2(ep - Vector2(1, 0), Vector2(3, 1)), Color(ec.r, ec.g, ec.b, 0.25 * ea))
	var crown: Vector2 = tree.crown
	for k in 3:
		var rr: float = 26.0 + k * 22.0 + sin(t * 0.7 + k) * 3.0
		glow.draw_arc(crown, rr, 0.0, TAU, 48, Color(0.2, 0.5, 0.9, 0.12 - 0.03 * k), 6.0 - k)
	for tp in tree.tips:
		var a: float = 0.35 + 0.45 * pow(0.5 + 0.5 * sin(t * 1.6 + tp[1]), 3.0)
		glow.draw_rect(Rect2(tp[0].round(), Vector2(1, 1)), Color(0.55, 0.9, 1.0, a))
	for si in tree.strands.size():
		var path: PackedVector2Array = tree.strands[si]
		var ph: float = fmod(t * 0.22 + si * 0.137, 1.0)
		var idx: int = int(ph * (path.size() - 1))
		for k in 6:
			var j: int = clampi(idx - k, 0, path.size() - 1)
			glow.draw_rect(Rect2(path[j].round() - Vector2(1, 1), Vector2(2, 2)), Color(0.5, 0.85, 1.0, 0.45 * (1.0 - k / 6.0)))
	# 水母的发光：伞缘亮边 + 触须
	for j in jellies:
		_draw_jelly(j, true)
	# 远处浪尖
	for c in crests:
		var k: float = c.life / c.max
		var a: float = sin(k * PI) * 0.55
		var y: float = round(c.y)
		var near: float = clampf((c.y - HZ) / float(SHORE - HZ), 0.0, 1.0)
		a *= 0.5 + 0.8 * near
		var xx: float = c.x0
		while xx < c.x1:
			var n := 0.55 + 0.45 * sin(xx * 0.9 + t * 4.0)
			glow.draw_rect(Rect2(Vector2(xx, y), Vector2(2, 1)), Color(0.15, 0.6, 1.0, a * n))
			xx += 2.0
		glow.draw_rect(Rect2(Vector2(c.x0 + 4, y - 1), Vector2(maxf(0.0, c.x1 - c.x0 - 8), 1)), Color(0.05, 0.3, 0.75, a * 0.5))
		if near > 0.5:
			glow.draw_rect(Rect2(Vector2(c.x0 + 8, y + 1), Vector2(maxf(0.0, c.x1 - c.x0 - 16), 1)), Color(0.05, 0.3, 0.75, a * 0.35))
	# 涌浪前沿：冲上来时亮蓝，退去时变暗
	for i in 3:
		var p := _wave_phase(i)
		var br := (1.0 - p / 0.42 * 0.3) if p < 0.42 else 0.7 * (1.0 - smoothstep(0.42, 0.85, p))
		if br <= 0.01:
			continue
		var x := 0.0
		while x < W:
			var y := _wave_y(i, x)
			var n := 0.6 + 0.4 * sin(x * 0.7 + t * 5.0 + i)
			glow.draw_rect(Rect2(Vector2(x, y).round(), Vector2(2, 1)), Color(0.3, 0.8, 1.0, 0.9 * br * n))
			glow.draw_rect(Rect2(Vector2(x, y - 1).round(), Vector2(2, 1)), Color(0.1, 0.5, 1.0, 0.55 * br * n))
			glow.draw_rect(Rect2(Vector2(x, y - 3).round(), Vector2(2, 2)), Color(0.04, 0.22, 0.7, 0.35 * br * n))
			glow.draw_rect(Rect2(Vector2(x, y - 7).round(), Vector2(2, 4)), Color(0.02, 0.1, 0.4, 0.25 * br * n))
			x += 2.0
	# 蓝眼泪
	for tr in tears:
		var k: float = tr.life / tr.max
		var tw: float = 0.6 + 0.4 * sin(t * 6.0 + tr.ph)
		var a: float = clampf(k * 1.4, 0.0, 1.0) * tw
		glow.draw_rect(Rect2(tr.pos.round(), Vector2(1, 1)), Color(0.35, 0.85, 1.0, a))
		if a > 0.6:
			glow.draw_rect(Rect2(tr.pos.round() + Vector2(-1, 0), Vector2(3, 1)), Color(0.1, 0.4, 0.9, (a - 0.6)))
	# 荧光颗粒
	for m in motes:
		var a: float = 0.25 + 0.25 * sin(t * 2.0 + m.ph)
		glow.draw_rect(Rect2(m.pos.round(), Vector2(1, 1)), Color(0.4, 0.8, 1.0, a))
	# 流星
	if not meteor.is_empty():
		var a: float = clampf(meteor.life / 0.9, 0.0, 1.0)
		var dir: Vector2 = meteor.v.normalized()
		for k in 18:
			glow.draw_rect(Rect2((meteor.p - dir * k * 1.5).round(), Vector2(1, 1)), Color(0.7, 0.85, 1.0, a * (1.0 - k / 18.0)))
	# 博士身边的柔光（冷色）与一点暖色灯火；沿浪线的泛光
	glow.draw_set_transform(off, 0.0, Vector2.ONE)
	if tex_light != null:
		for i in 3:
			var p := _wave_phase(i)
			var br := (1.0 - p / 0.42 * 0.3) if p < 0.42 else 0.7 * (1.0 - smoothstep(0.42, 0.85, p))
			if br > 0.05:
				var x3 := 180.0
				while x3 < W:
					var wp := Vector2(x3, _wave_y(i, x3)) * ks
					glow.draw_texture_rect(tex_light, Rect2(wp - Vector2(70, 22), Vector2(140, 44)), false, Color(0.05, 0.25, 0.6, 0.35 * br))
					x3 += 40.0
		glow.draw_texture_rect(tex_light, Rect2(Vector2(0, HZ * ks - 90), Vector2(W * ks, 180)), false, Color(0.12, 0.08, 0.3, 0.35))
		var c := FEET * ks + Vector2(0, -60)
		var pulse := 1.0 + 0.04 * sin(t * 2.0)
		glow.draw_texture_rect(tex_light, Rect2(c - Vector2(210, 210) * pulse, Vector2(420, 420) * pulse), false, Color(0.12, 0.3, 0.55, 0.5))
		glow.draw_texture_rect(tex_light, Rect2(c + Vector2(-60, 10), Vector2(120, 120)), false, Color(0.5, 0.35, 0.15, 0.35 + 0.05 * sin(t * 9.0)))


func _new_jelly(y: float) -> Dictionary:
	return {"pos": Vector2(rng.randf_range(230, 400), y), "r": rng.randf_range(4.5, 7.5), "ph": rng.randf() * TAU,
		"spd": rng.randf_range(1.6, 2.6), "col": JELLY_COLS[rng.randi() % JELLY_COLS.size()]}


## 水母（像素画）：越靠海平线越小越淡；伞盖随 ph 收放，触须波动。glow=true 画加法层的亮边与触须
func _draw_jelly(j: Dictionary, glow_layer: bool) -> void:
	var depth: float = clampf((j.pos.y - HZ) / float(SHORE - HZ), 0.0, 1.0)
	var sc: float = 0.45 + 0.55 * depth
	var r: float = j.r * sc
	var pulse: float = sin(j.ph)
	var rw: float = r * (1.0 + 0.18 * pulse)          # 放开时宽而扁
	var rh: float = r * (0.85 - 0.15 * pulse)          # 收缩时窄而高
	var c: Color = j.col
	var a0: float = 0.35 + 0.65 * depth
	var ci: CanvasItem = glow if glow_layer else self
	var base: Vector2 = j.pos.round()
	var rows := int(ceil(rh))
	for dy in rows + 1:
		var k: float = 1.0 - float(dy) / maxf(rh, 1.0)
		var hw := int(round(rw * sqrt(maxf(0.0, 1.0 - k * k))))
		var y: float = base.y - rows + dy
		if glow_layer:
			# 伞缘：每行两端亮点 + 顶部一行亮
			ci.draw_rect(Rect2(Vector2(base.x - hw, y), Vector2(1, 1)), Color(c.r, c.g, c.b, 0.95 * a0))
			ci.draw_rect(Rect2(Vector2(base.x + hw, y), Vector2(1, 1)), Color(c.r, c.g, c.b, 0.95 * a0))
			if dy == 0 or dy == rows:
				ci.draw_rect(Rect2(Vector2(base.x - hw, y), Vector2(hw * 2 + 1, 1)), Color(c.r, c.g, c.b, 0.45 * a0))
		else:
			ci.draw_rect(Rect2(Vector2(base.x - hw, y), Vector2(hw * 2 + 1, 1)), Color(c.r * 0.55, c.g * 0.6, c.b * 0.75, 0.42 * a0))
	if glow_layer:
		# 柔光：伞盖周围一团
		if tex_light != null:
			var gr: float = r * 3.2
			ci.draw_texture_rect(tex_light, Rect2(base - Vector2(gr, gr + rows * 0.5), Vector2(gr, gr) * 2.0), false, Color(c.r * 0.5, c.g * 0.5, c.b * 0.5, 0.5 * a0))
		# 伞内一点亮核
		ci.draw_rect(Rect2(base + Vector2(0, -rows * 0.5).round(), Vector2(1, 1)), Color(1, 1, 1, 0.5 * a0))
		# 触须：3–4 根，向下飘，越往下越淡
		var n := 3 if r < 3.0 else 4
		var tl: float = r * (2.2 + 0.5 * pulse)
		for q in n:
			var x0: float = base.x + (q - (n - 1) * 0.5) * rw * 0.55
			for s in int(tl):
				var sway: float = sin(j.ph * 1.3 + s * 0.45 + q) * (0.4 + s * 0.12)
				var al: float = (1.0 - float(s) / tl) * 0.55 * a0
				ci.draw_rect(Rect2(Vector2(round(x0 + sway), base.y + 1 + s), Vector2(1, 1)), Color(c.r, c.g, c.b, al))


## 沙滩湿度：1 = 湿沙（浪能冲到、会反光），0 = 干沙
func _wetness(x: float, y: float) -> float:
	var d := y - (SHORE - (x - 320.0) * 0.07 + 2.0 * sin(x * 0.05))
	return 1.0 - smoothstep(WET_END, DRY_START, d)


# ------------------------------------------------------------------ 预渲染
## 远方海嗣：一只半浮出海面的巨型海嗣（隆起的背 + 尖脊 + 伸向夜空的长颈 + 两侧翘起的触手），
## 加上沿海平线站着的一群小海嗣。颜色接近黑的暗紫，越贴近海平线越被雾冲淡。
func _build_terrors() -> void:
	var img := Image.create(W, HZ + 2, false, Image.FORMAT_RGBA8)
	var r2 := RandomNumberGenerator.new()
	r2.seed = 4401
	var base_y := float(HZ + 1)
	# 背：宽大的隆起，边缘起伏不平 + 一排高低不一的尖脊
	var cx := 322.0
	var hw := 96.0
	for x in range(int(cx - hw), int(cx + hw) + 1):
		var u: float = (x - cx) / hw
		var h: float = 26.0 * pow(maxf(0.0, 1.0 - u * u), 0.7) + 3.0 * sin(x * 0.21) + 2.0 * sin(x * 0.53)
		var ph: float = fposmod(x - cx, 11.0)
		h += 6.0 * maxf(0.0, 1.0 - absf(ph - 5.5) / 1.8) * (1.0 - absf(u)) * (0.6 + 0.4 * sin(x * 0.9))
		_tvline(img, x, base_y - maxf(0.0, h), base_y)
	# 冠：一圈从背上升起、向外张开的长触须（中间最高），末梢微卷
	var crown := [
		[-52.0, 22.0, -76.0, 40.0, 5.0], [-30.0, 27.0, -42.0, 55.0, 6.0], [-10.0, 29.0, -13.0, 64.0, 7.0],
		[12.0, 29.0, 21.0, 61.0, 7.0], [32.0, 26.0, 50.0, 52.0, 6.0], [54.0, 21.0, 82.0, 38.0, 5.0],
	]
	for c in crown:
		var rx: float = cx + c[0]
		var tx: float = cx + c[2]
		var root := Vector2(rx, base_y - c[1] + 4)
		var tip := Vector2(tx, base_y - c[3])
		var mid := root.lerp(tip, 0.55) + Vector2((tx - rx) * -0.15, 0)
		var curl := tip + Vector2(signf(tx - cx) * 5.0, 3.0)
		_tstroke(img, [root, mid, tip, curl], c[4], 1.0)
	# 正面一排若隐若现的眼
	for k in 5:
		terror_eyes.append([Vector2(cx - 26 + k * 13 + (k % 2) * 2, base_y - 15 - (k % 2) * 3), k * 1.3, Color(1.0, 0.22, 0.3)])
	# 冠上两处发光器官
	terror_eyes.append([Vector2(cx - 12, base_y - 48), 2.2, Color(0.7, 0.35, 1.0)])
	terror_eyes.append([Vector2(cx + 20, base_y - 44), 3.6, Color(0.7, 0.35, 1.0)])
	# 海平线上的海嗣群：小小的尖头剪影，高低错落
	var packs := [170.0, 262.0, 452.0]
	for i in 12:
		var x: float = packs[i % 3] + r2.randf_range(-16.0, 16.0)
		var hh := r2.randf_range(4.0, 10.0)
		var ww := maxf(1.0, hh * 0.28)
		for dx in range(int(-ww), int(ww) + 1):
			_tvline(img, int(x) + dx, base_y - hh * (1.0 - absf(dx) / (ww + 1.0) * 0.5), base_y)
		# 头上的尖刺 / 触角
		_tvline(img, int(x), base_y - hh - r2.randf_range(1.0, 3.0), base_y - hh)
		if r2.randf() < 0.5:
			img.set_pixel(int(x) + (1 if r2.randf() < 0.5 else -1), int(base_y - hh - 1), _tcol(base_y - hh - 1))
		if r2.randf() < 0.35:
			terror_eyes.append([Vector2(int(x), int(base_y - hh + 1)), r2.randf() * TAU, Color(0.9, 0.3, 0.45) if r2.randf() < 0.5 else Color(0.6, 0.35, 1.0)])
	tex_terror = ImageTexture.create_from_image(img)


## 海嗣剪影的颜色：越贴近海平线越被紫色雾气冲淡
func _tcol(y: float) -> Color:
	var fog: float = clampf(1.0 - (HZ - y) / 110.0, 0.0, 1.0)
	var c := Color(0.05, 0.04, 0.09).lerp(Color(0.15, 0.11, 0.27), fog * 0.6)
	c.a = 0.45 + 0.45 * fog      # 越高越透，融进夜空
	return c


func _tvline(img: Image, x: int, y0: float, y1: float) -> void:
	if x < 0 or x >= W:
		return
	for y in range(maxi(0, int(round(y0))), mini(HZ + 2, int(round(y1)) + 1)):
		img.set_pixel(x, y, _tcol(y))


## 沿折线画一条由粗到细的笔划（每段按长度逐像素铺圆点）
func _tstroke(img: Image, pts: Array, w0: float, w1: float) -> void:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var acc := 0.0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		for k in int(seg * 2.0) + 1:
			var f: float = k / (seg * 2.0)
			var p: Vector2 = a.lerp(b, f)
			var w: float = lerpf(w0, w1, (acc + seg * f) / total) * 0.5
			for yy in range(int(p.y - w), int(p.y + w) + 1):
				for xx in range(int(p.x - w), int(p.x + w) + 1):
					if Vector2(xx, yy).distance_to(p) <= w + 0.3 and xx >= 0 and xx < W and yy >= 0 and yy < HZ + 2:
						img.set_pixel(xx, yy, _tcol(yy))
		acc += seg



func _build_sky() -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var n1 := FastNoiseLite.new()
	n1.seed = 7
	n1.frequency = 0.02
	n1.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = 11
	n2.frequency = 0.045
	n2.fractal_octaves = 3
	var n3 := FastNoiseLite.new()
	n3.seed = 3
	n3.frequency = 0.008
	# 银河：从左上斜向右侧海平线
	var a := Vector2(40, -40)
	var b := Vector2(640, 175)
	var dirv := (b - a).normalized()
	var nrm := dirv.orthogonal()
	for y in HZ:
		for x in W:
			var p := Vector2(x, y)
			var d: float = (p - a).dot(nrm)
			var along: float = (p - a).dot(dirv) / (b - a).length()
			var base := Color(0.012, 0.015, 0.05).lerp(Color(0.07, 0.07, 0.2), pow(float(y) / HZ, 1.6))
			base = base.lerp(Color(0.2, 0.14, 0.36), pow(float(y) / HZ, 6.0) * 0.8)
			var band: float = exp(-pow(d / 46.0, 2.0)) * (0.5 + 0.5 * (n1.get_noise_2d(x, y) * 0.5 + 0.5)) * (0.55 + 0.45 * along)
			var dust: float = exp(-pow((d - 5.0) / 11.0, 2.0)) * clampf(n2.get_noise_2d(x, y) * 0.8 + 0.5, 0.0, 1.0)
			band = maxf(0.0, band - dust * 0.55)
			var hue: float = clampf(n3.get_noise_2d(x, y) * 0.9 + 0.5, 0.0, 1.0)
			var bc := Color(0.55, 0.38, 0.85).lerp(Color(0.3, 0.7, 1.0), hue)
			var c := base.lerp(bc, clampf(band * 0.85, 0.0, 0.9))
			# 银河里的微星
			if rng.randf() < 0.004 + band * 0.08:
				c = c.lerp(Color(0.85, 0.9, 1.0), rng.randf_range(0.3, 0.8))
			img.set_pixel(x, y, _dither(c, x, y))
	# 海面：天空的模糊倒影，越近越暗
	for y in range(HZ, H):
		var dy := y - HZ
		for x in W:
			var sy := clampi(HZ - 1 - int(dy * 1.7), 0, HZ - 1)
			var sx := clampi(x + int(n1.get_noise_2d(x * 0.3, y * 3.0) * 10.0), 0, W - 1)
			var sc := img.get_pixel(sx, sy)
			var k: float = exp(-dy / 55.0)
			var c := Color(0.01, 0.03, 0.08).lerp(sc, 0.6 * k + 0.08)
			if dy <= 1:
				c = c.lerp(Color(0.2, 0.2, 0.4), 0.5)
			img.set_pixel(x, y, _dither(c, x, y))
	# 远处礁石剪影
	for x in W:
		var h1: float = maxf(0.0, 9.0 * sin(x * 0.02 + 1.0) + 6.0 * sin(x * 0.07) - 6.0) if x < 230 else 0.0
		var h2: float = maxf(0.0, 5.0 * sin(x * 0.05 + 2.0) + 3.0 * sin(x * 0.13) - 4.0) if x > 470 and x < 540 else 0.0
		var hh := int(maxf(h1, h2))
		for k in hh:
			img.set_pixel(x, HZ - 1 - k, Color(0.02, 0.025, 0.06))
	tex_sky = ImageTexture.create_from_image(img)


func _build_sand() -> void:
	var sh := H - SHORE + 30
	var img := Image.create(W, sh, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.06
	var n2 := FastNoiseLite.new()
	n2.seed = 17
	n2.frequency = 0.012
	for y in sh:
		for x in W:
			var wy := SHORE - 30 + y
			# 斜向岸线：右边岸线更高（更远）
			var edge := SHORE - (x - 320.0) * 0.07 + 2.0 * sin(x * 0.05)
			if wy < edge - 4:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var d: float = wy - edge
			var dry: float = smoothstep(WET_END, DRY_START, d)
			# 湿沙：深、偏蓝，带天光反射的横向亮纹（像一层薄水膜）
			var wet_c := Color(0.025, 0.045, 0.1).lerp(Color(0.05, 0.075, 0.15), clampf(d / WET_END, 0.0, 1.0))
			var sheen: float = clampf(n.get_noise_2d(x * 0.25, wy * 2.4) * 1.4 - 0.35, 0.0, 1.0)
			wet_c = wet_c.lerp(Color(0.16, 0.2, 0.36), sheen * 0.45 * (1.0 - clampf(d / WET_END, 0.0, 1.0) * 0.5))
			# 干沙：月光下偏冷的灰沙，越往前越亮一点；风吹的沙纹
			var far: float = clampf((d - DRY_START) / 60.0, 0.0, 1.0)
			var dry_c := Color(0.16, 0.155, 0.21).lerp(Color(0.25, 0.23, 0.28), far)
			var rip: float = sin(x * 0.11 + wy * 0.9 + n2.get_noise_2d(x, wy) * 9.0)
			if rip > 0.72:
				dry_c = dry_c.lightened(0.07)
			elif rip < -0.85:
				dry_c = dry_c.darkened(0.12)
			dry_c = dry_c.lerp(Color(0.2, 0.19, 0.25), clampf(n.get_noise_2d(x, wy * 2.0) * 0.5 + 0.2, 0.0, 1.0) * 0.35)
			var c := wet_c.lerp(dry_c, dry)
			# 高潮线：一道断续的海藻碎屑（深色），靠近湿干交界
			var tide: float = absf(d - (WET_END + 6.0) - 4.0 * sin(x * 0.07))
			if tide < 1.0 and n.get_noise_2d(x * 0.8, 3.0) > 0.05:
				c = Color(0.03, 0.04, 0.06)
			# 沙粒：干沙多、湿沙少
			var r := rng.randf()
			if r < 0.012 + 0.04 * dry:
				c = c.lightened(0.1 + 0.08 * dry)
			elif r > 0.985:
				c = c.darkened(0.2)
			# 最下方压暗，给菜单和画面收边
			c = c.lerp(Color(0.01, 0.012, 0.03), smoothstep(float(H - 46), float(H), float(wy)) * 0.55)
			var a := clampf((wy - edge + 4.0) / 4.0, 0.0, 1.0)
			var dd := _dither(c, x, y)
			dd.a = a
			img.set_pixel(x, y, dd)
	# 零星小贝壳 / 卵石（干沙上）：亮点 + 下方一像素阴影
	for i in 26:
		var sx := rng.randi_range(170, W - 4)
		var sy := rng.randi_range(4, sh - 6)
		var wy2 := SHORE - 30 + sy
		if _wetness(sx, wy2) > 0.4:
			continue
		var shell := Color(0.34, 0.31, 0.36) if rng.randf() < 0.6 else Color(0.42, 0.33, 0.38)
		img.set_pixel(sx, sy, shell)
		if rng.randf() < 0.5:
			img.set_pixel(sx + 1, sy, shell.darkened(0.15))
		img.set_pixel(sx, sy + 1, Color(0.05, 0.05, 0.08))
	tex_sand = ImageTexture.create_from_image(img)


## 4×4 有序抖动 + 颜色分级，得到像素画质感
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
func _dither(c: Color, x: int, y: int) -> Color:
	var th: float = (BAYER[(y % 4) * 4 + (x % 4)] / 16.0 - 0.5) / 28.0
	var q := 28.0
	return Color(round((c.r + th) * q) / q, round((c.g + th) * q) / q, round((c.b + th) * q) / q, 1.0)


## 远景深蓝之树
