extends Control
## 局外 · 认知塑造页（docs/109 §4；视觉 docs/125 §8 B2，10-22 用户选定）。只改 Cfg.meta_*，规则与数据在 core/meta.gd / data/meta_tree.json。
## 版式（设计尺寸 1280×720，整体按界面大小等比缩放）：左侧浅灰斜切栏 = 标题 / 生机细胞 / 当前节点；右侧暗场「塑造图谱」= 根在底部中央、
## 每条链一列向上生长（相邻列错半格、两侧略外斜）；底栏 = 推荐 / 重置 + 消耗 + 「确认塑造」。
## 背景：不规则碎片只留 1 px 轮廓（不填充），带延伸引线、刻度与小标注（莱茵生命实验室图纸感，用户 10-22「强调线条感」）；
## 每片各自慢漂 + 自旋，速度按两组慢正弦相乘起伏（偶有停顿与加速）；靠近选中节点时提亮。
## 招牌动效：解锁时枝条从父节点长亮到新节点（0.55 秒，白色光头）→ 节点落定暖白 + 外扩环（0.45 秒）。
## 操作：点节点选中、再点 / Enter / 「确认塑造」塑造；↑↓ 沿链、←→ 换链；R 推荐（按推荐顺序把余额点完）；X 两次全部重置（免费退回）；Esc 返回。
signal closed

const UI = preload("res://scripts/ui.gd")
const HS = preload("res://scripts/screens/hh_style.gd")
const Meta = preload("res://scripts/core/meta.gd")

const DESIGN := Vector2(1280, 720)
const GX0 := 372.0                  # 图谱区（设计坐标）
const GX1 := 1280.0
const GY0 := 64.0
const GY1 := 652.0
const BAR_H := 48.0
const COL_GAP := 86.0
const STEP := 92.0
## 链的列序（左 → 右）：根节点 id；数据里新增的根接在最后
const ROOT_ORDER := ["disp1", "shop1", "gold1", "pick1", "xp1", "sh1", "atk1", "hp1", "def1", "reg1"]
## 末节的质变 / 汇总短句（链顶小斜块）：取自各末节 desc 的规则部分
const RULE_TAG := {"atk5": "处决", "hp5": "濒死免死", "def4": "久守减伤", "reg5": "回复 +1.0", "sh2": "碎盾反震",
	"xp4": "升级再升", "gold3": "源石锭 +12", "shop3": "行商 -18%", "disp4": "绝处逢生", "pick4": "拾取 +52"}

const BASE := Color8(19, 23, 30)
const LINE_ON := Color8(232, 246, 255)
const LINE_OK := Color8(56, 214, 240)
const LINE_LOCK := Color8(70, 84, 100)
const NODE_ON := Color8(255, 240, 214)
const NODE_LOCK := Color8(80, 92, 108)
const LABEL := Color8(220, 226, 234)
const LABEL_LOCK := Color8(110, 120, 134)
const TAG := Color8(70, 180, 240)
const FRAG := Color8(190, 236, 250)
const LIT_DUR := 1.0
const LIT_GROW := 0.55

var font: Font
var view: Control                   # 设计坐标画布（节点自身缩放，像素字的屏幕格才算得对）
var chains: Array = []              # 每条链的节点 id（从根往末节）
var pos := {}                       # 节点 id → 设计坐标；"root" = 根
var sel := Vector2i(0, 0)           # 选中（链，节数）
var buttons: Array = []             # [Rect2, 动作]（设计坐标）
var reset_armed := false
var lit_id := ""                    # 解锁演出中的节点
var lit_t0 := -10.0
var open_t0 := -10.0
var t := 0.0
var k := 1.0
var off := Vector2.ZERO
var frags: Array = []
var marks: Array = []


static var _re_head: RegEx

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
	view = Control.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.size = DESIGN
	view.draw.connect(_draw_view)
	add_child(view)
	_make_frags()
	hide()


func _build() -> void:
	chains.clear()
	pos.clear()
	var nodes := Meta.nodes()
	var child := {}
	var roots: Array = []
	for id in nodes:
		if nodes[id].has("req"):
			child[str(nodes[id].req)] = id
		else:
			roots.append(id)
	roots.sort_custom(func(a, b): return _root_rank(a) < _root_rank(b))
	for r in roots:
		var ch: Array = [r]
		while child.has(ch[-1]) and ch.size() < 12:
			ch.append(child[ch[-1]])
		chains.append(ch)
	var rx := (GX0 + GX1) / 2.0
	pos["root"] = Vector2(rx, GY1 - 26.0)
	var n := chains.size()
	for i in n:
		var c := i - (n - 1) / 2.0
		var x := rx + c * COL_GAP
		var y := GY1 - 112.0 - (i % 2) * 30.0 - (4.0 - absf(c)) * 6.0
		for j in chains[i].size():
			pos[chains[i][j]] = Vector2(x + c * 3.0 * j, y - j * STEP)


func _root_rank(id: String) -> int:
	var r := ROOT_ORDER.find(id)
	return r if r >= 0 else 100


func open() -> void:
	_build()
	sel = Vector2i(0, 0)
	# 缺省选第一个能塑造的节点（没有就第一条链的根）
	for i in chains.size():
		for j in chains[i].size():
			if _state(chains[i][j]) == "ok" and sel == Vector2i(0, 0):
				sel = Vector2i(i, j)
	reset_armed = false
	lit_id = ""
	open_t0 = t
	show()


func close() -> void:
	hide()
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	for f in frags:
		_frag_step(f, delta)
	for m in marks:
		m.p += m.v * delta
		m.p = Vector2(wrapf(m.p.x, GX0 - 60.0, GX1 + 60.0), wrapf(m.p.y, -40.0, DESIGN.y + 40.0))
	view.queue_redraw()
	queue_redraw()


func _sel_id() -> String:
	if chains.is_empty():
		return ""
	var r := clampi(sel.x, 0, chains.size() - 1)
	return chains[r][clampi(sel.y, 0, chains[r].size() - 1)]


## 节点状态：on 已塑造 / ok 可塑造 / poor 余额不够 / lock 前置或门槛未到
func _state(id: String) -> String:
	var shape: Dictionary = Cfg.meta_shape
	if shape.get(id, false):
		return "on"
	var nd: Dictionary = Meta.nodes()[id]
	if nd.has("req") and not shape.get(str(nd.req), false):
		return "lock"
	if Meta.spent(shape) < int(nd.get("need", 0)):
		return "lock"
	return "ok" if Meta.can_buy(shape, id, Meta.earned_total()) else "poor"


func _buy(id: String) -> void:
	reset_armed = false
	if id != "" and Meta.buy(id):
		Sfx.play("relic", -4.0)
		lit_id = id
		lit_t0 = t
	else:
		Sfx.play("ui_move", -6.0)


func _act(a: String) -> void:
	match a:
		"buy":
			_buy(_sel_id())
		"rec":
			reset_armed = false
			Meta.buy_recommended()
			Sfx.play("ui_ok")
		"reset":
			if reset_armed:
				Meta.reset()
				reset_armed = false
				lit_id = ""
				Sfx.play("ui_ok")
			else:
				reset_armed = true
				Sfx.play("ui_move")
		"back":
			Sfx.play("ui_ok")
			close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (get_local_mouse_position() - off) / k
		for i in chains.size():
			for j in chains[i].size():
				if p.distance_to(pos[chains[i][j]]) < 24.0:
					if Vector2i(i, j) == sel:
						_buy(chains[i][j])
					else:
						sel = Vector2i(i, j)
						reset_armed = false
						Sfx.play("ui_move", -6.0)
					get_viewport().set_input_as_handled()
					return
		for b in buttons:
			if (b[0] as Rect2).has_point(p):
				_act(b[1])
				break
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = Pad.kc(event)
		var d := Vector2i.ZERO
		match kc:
			KEY_ESCAPE, KEY_BACKSPACE:
				_act("back")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_act("buy")
			KEY_R:
				_act("rec")
			KEY_X:
				_act("reset")
			KEY_UP, KEY_W:
				d = Vector2i(0, 1)
			KEY_DOWN, KEY_S:
				d = Vector2i(0, -1)
			KEY_LEFT, KEY_A:
				d = Vector2i(-1, 0)
			KEY_RIGHT, KEY_D:
				d = Vector2i(1, 0)
		if d != Vector2i.ZERO and not chains.is_empty():
			sel.x = clampi(sel.x + d.x, 0, chains.size() - 1)
			sel.y = clampi(sel.y + d.y, 0, chains[sel.x].size() - 1)
			reset_armed = false
			Sfx.play("ui_move", -6.0)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 背景碎片（只描边）
func _make_frags() -> void:
	var rng := RandomNumberGenerator.new()   # 独立种子：不碰局内随机数，每次打开同一幅底纹
	rng.seed = 20261022
	for i in 17:
		var fs := exp(rng.randf_range(log(50.0), log(300.0)))
		var r := fs / 2.0
		var pts := PackedVector2Array()
		if rng.randf() < 0.3:   # 切角板块：矩形随机切掉 1–2 个角
			var w := r * rng.randf_range(0.8, 1.4)
			var h := r * rng.randf_range(0.3, 0.8)
			var c1 := r * rng.randf_range(0.1, 0.35)
			var c2 := r * rng.randf_range(0.0, 0.3)
			pts = PackedVector2Array([Vector2(-w + c1, -h), Vector2(w, -h), Vector2(w, h - c2), Vector2(w - c2, h), Vector2(-w, h), Vector2(-w, -h + c1)])
		else:                   # 不规则多边形：3–8 边，角度与半径都抖
			var angs: Array = []
			for _j in rng.randi_range(3, 8):
				angs.append(rng.randf() * TAU)
			angs.sort()
			for a in angs:
				pts.append(Vector2.from_angle(a) * r * rng.randf_range(0.6, 1.0))
		var ext: Array = []     # 延伸引线：从某个顶点沿一条边的方向拉出去
		for _j in rng.randi_range(1, 2):
			var vi := rng.randi_range(0, pts.size() - 1)
			ext.append([vi, rng.randf_range(70.0, 260.0), rng.randf() < 0.5])
		frags.append({
			"p": Vector2(rng.randf_range(GX0 - 80.0, GX1 + 80.0), rng.randf_range(-60.0, DESIGN.y + 60.0)),
			"pts": pts, "rot": rng.randf() * TAU, "spin": deg_to_rad(rng.randf_range(-2.0, 2.0)),
			"dir": rng.randf() * TAU, "v": rng.randf_range(0.5, 3.0), "turn": rng.randf_range(-0.03, 0.03),
			"w1": rng.randf_range(0.05, 0.18), "w2": rng.randf_range(0.11, 0.31), "p1": rng.randf() * TAU, "p2": rng.randf() * TAU,
			"a": rng.randf_range(0.16, 0.32), "ext": ext, "inner": rng.randf() < 0.35, "ticks": rng.randf() < 0.4,
			"label": ("%s-%02d" % ["RLKTM"[rng.randi_range(0, 4)], rng.randi_range(1, 99)]) if rng.randf() < 0.35 else "",
			"num": "%.2f" % rng.randf_range(0.0, 9.0), "clock": rng.randf() * 60.0,
		})
	for i in 12:
		marks.append({"p": Vector2(rng.randf_range(GX0, GX1), rng.randf_range(GY0, GY1)), "v": Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6)),
			"kind": rng.randi_range(0, 2)})


## 速度倍率：两组慢正弦相乘再截断 → 0（停顿）到 ~1.8（加速）之间起伏
func _gain(f: Dictionary) -> float:
	var s: float = f.clock
	return maxf(0.0, 0.75 + 1.1 * sin(f.w1 * s + f.p1) * sin(f.w2 * s + f.p2) + 0.25 * sin(f.w2 * 2.3 * s))


func _frag_step(f: Dictionary, dt: float) -> void:
	f.clock += dt
	var g := _gain(f)
	f.p += Vector2.from_angle(f.dir) * f.v * g * dt
	f.rot += f.spin * (0.4 + 0.6 * g) * dt
	f.dir += f.turn * dt
	f.p = Vector2(wrapf(f.p.x, GX0 - 200.0, GX1 + 200.0), wrapf(f.p.y, -200.0, DESIGN.y + 200.0))


func _draw_frags(ci: CanvasItem) -> void:
	var sp: Vector2 = pos.get(_sel_id(), Vector2(-999, -999))
	var lp: Vector2 = pos.get(lit_id, Vector2(-999, -999))
	var pulse := maxf(0.0, 1.0 - (t - lit_t0) / 0.6) if lit_id != "" else 0.0
	for f in frags:
		var c: Vector2 = f.p
		var near := maxf(0.0, 1.0 - c.distance_to(sp) / 260.0) + pulse * maxf(0.0, 1.0 - c.distance_to(lp) / 200.0) * 1.5
		var a: float = minf(0.7, f.a * (1.0 + 0.9 * near))
		var col := Color(FRAG, a)
		var xf := Transform2D(f.rot, c)
		var pts := PackedVector2Array()
		for q in f.pts:
			pts.append(xf * q)
		var loop := pts.duplicate()
		loop.append(pts[0])
		ci.draw_polyline(loop, col, 1.0)
		for e in f.ext:   # 延伸引线（带端头短横 / 每 10 一道刻度）
			var v0: Vector2 = pts[e[0]]
			var v1: Vector2 = pts[(e[0] + 1) % pts.size()]
			var dv := (v0 - v1).normalized()
			var end: Vector2 = v0 + dv * float(e[1])
			ci.draw_line(v0, end, Color(FRAG, a * 0.75), 1.0)
			var nrm := dv.orthogonal()
			ci.draw_line(end - nrm * 4.0, end + nrm * 4.0, Color(FRAG, a * 0.75), 1.0)
			if e[2]:
				for s in range(10, int(float(e[1])), 10):
					var tl := 5.0 if s % 50 == 0 else 2.0
					var pp := v0 + dv * s
					ci.draw_line(pp, pp + nrm * tl, Color(FRAG, a * 0.6), 1.0)
		if f.inner:
			var p1: Vector2 = pts[pts.size() / 2]
			ci.draw_line(pts[0], p1, Color(FRAG, a * 0.5), 1.0)
		if f.ticks:   # 沿第一条边的刻度
			var e0: Vector2 = pts[0]
			var e1: Vector2 = pts[1]
			var L := e0.distance_to(e1)
			var nn := (e1 - e0).normalized().orthogonal()
			for j in range(1, int(L / 8.0)):
				var pp := e0.lerp(e1, j * 8.0 / L)
				ci.draw_line(pp, pp + nn * (5.0 if j % 5 == 0 else 2.0), col, 1.0)
		if f.label != "":
			var l0: Vector2 = pts[0]
			ci.draw_polyline(PackedVector2Array([l0, l0 + Vector2(14, -10), l0 + Vector2(54, -10)]), col, 1.0)
			ci.draw_string(font, l0 + Vector2(16, -13), f.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(FRAG, minf(0.8, a + 0.12)))
			ci.draw_string(font, l0 + Vector2(58, -6), f.num, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
	for m in marks:
		var p: Vector2 = m.p
		var c2 := Color(FRAG, 0.3)
		match m.kind:
			0:
				ci.draw_line(p - Vector2(5, 0), p + Vector2(5, 0), c2, 1.0)
				ci.draw_line(p - Vector2(0, 5), p + Vector2(0, 5), c2, 1.0)
			1:
				ci.draw_line(p, p + Vector2(40, 0), c2, 1.0)
				for j in 5:
					ci.draw_line(p + Vector2(j * 10, 0), p + Vector2(j * 10, -4.0 if j % 2 == 0 else -2.0), c2, 1.0)
			_:
				ci.draw_polyline(PackedVector2Array([p + Vector2(0, 8), p, p + Vector2(8, 0)]), c2, 1.0)
				ci.draw_polyline(PackedVector2Array([p + Vector2(30, 22), p + Vector2(30, 30), p + Vector2(22, 30)]), c2, 1.0)


# ---------------------------------------------------------------- 绘制
func _draw() -> void:
	k = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	off = ((size - DESIGN * k) / 2.0).floor()
	view.position = off
	view.scale = Vector2(k, k)
	draw_rect(Rect2(Vector2.ZERO, size), BASE)
	# 宽屏（手机横屏）左右留边：左边接上浅灰栏、底边接上底栏，不露出一条暗缝
	var bar_y := off.y + (DESIGN.y - BAR_H) * k
	draw_rect(Rect2(0, 0, off.x + 2.0, bar_y), HS.LIGHT)
	draw_rect(Rect2(0, bar_y, size.x, size.y - bar_y), Color8(14, 17, 22))


func _draw_view() -> void:
	var ci := view
	var mouse := (get_local_mouse_position() - off) / k
	ci.draw_rect(Rect2(Vector2.ZERO, DESIGN), BASE)
	_draw_frags(ci)
	_draw_graph(ci, mouse)
	_draw_left(ci)
	_draw_bars(ci, mouse)


## 进入：九条链从根部依次长出（每条晚 0.04 秒，0.35 秒长完）；减少动态效果直接到位
func _grow(i: int) -> float:
	if Cfg.reduce_motion:
		return 1.0
	return UI.ease_out(clampf((t - open_t0 - 0.04 * i) / 0.35, 0.0, 1.0))


func _draw_graph(ci: CanvasItem, mouse: Vector2) -> void:
	var nodes := Meta.nodes()
	var lit_f := (t - lit_t0) / LIT_DUR if lit_id != "" else 2.0
	if lit_f >= 1.0:
		lit_id = ""
	# 枝条
	for i in chains.size():
		var gr := _grow(i)
		var prev := "root"
		for id in chains[i]:
			var a: Vector2 = pos[prev]
			var b: Vector2 = a.lerp(pos[id], gr)
			var st := _state(id)
			if id == lit_id:
				ci.draw_dashed_line(a, b, LINE_LOCK, 2.0, 4.0)
				var g := minf(1.0, lit_f / LIT_GROW)
				var m := a.lerp(b, UI.ease_out(g))
				ci.draw_line(a, m, LINE_ON, 4.0)
				if g < 1.0:
					ci.draw_circle(m, 6.0, Color.WHITE)
					ci.draw_circle(m, 11.0, Color(1, 1, 1, 0.25))
			elif st == "on":
				ci.draw_line(a, b, LINE_ON, 4.0)
			elif st == "ok" or st == "poor":
				ci.draw_dashed_line(a, b, LINE_OK if st == "ok" else UI.fa(LINE_OK, 0.55), 2.0, 6.0)
			elif prev == "root":
				ci.draw_dashed_line(a, b, LINE_LOCK, 2.0, 4.0)
			else:
				ci.draw_line(a, b, LINE_LOCK, 1.5)
			prev = id
	# 根：认知核心
	var rp: Vector2 = pos["root"]
	HS.fill(ci, _diamond(rp, 20.0), BASE)
	ci.draw_polyline(_loop(_diamond(rp, 20.0)), LINE_ON, 2.0)
	HS.fill(ci, _diamond(rp, 9.0), LINE_ON)
	# 节点 + 链顶标签
	var sid := _sel_id()
	for i in chains.size():
		var gr := _grow(i)
		if gr < 0.98:
			continue
		var ch: Array = chains[i]
		for j in ch.size():
			var id: String = ch[j]
			_draw_node(ci, id, j == ch.size() - 1, id == sid, (pos[id] as Vector2).distance_to(mouse) < 24.0, lit_f)
		var top: Vector2 = pos[ch[-1]]
		var tag: String = RULE_TAG.get(ch[-1], "")
		var ln := str(nodes[ch[0]].get("line", ""))
		if tag != "":
			var tw := UI.cwidth(font, tag, 12) + 14.0
			var tr := Rect2(top.x - tw / 2.0, top.y - 50.0, tw, 20.0)
			HS.para(ci, tr, Color(0, 0, 0, 0), TAG, 1.0)
			UI.text_at(ci, font, tr.get_center(), tag, 12, TAG, "mm")
		UI.text_at(ci, font, top + Vector2(0, -70), ln, 12, LABEL_LOCK, "ma")


func _draw_node(ci: CanvasItem, id: String, last: bool, selected: bool, hov: bool, lit_f: float) -> void:
	var p: Vector2 = pos[id]
	var st := _state(id)
	if id == lit_id and lit_f < LIT_GROW:
		st = "ok"
	var r := 17.0 if last else 15.0
	var pts := _diamond(p, r + 3.0) if last else _octa(p, r)
	match st:
		"on":
			HS.fill(ci, pts, NODE_ON)
			_icon(ci, id, p, Color8(30, 40, 56), 7.0)
		"ok", "poor":
			HS.fill(ci, pts, BASE)
			var col := LINE_OK if st == "ok" else UI.fa(LINE_OK, 0.5)
			if st == "ok":   # 可塑造：外圈 1.6 秒呼吸
				var br := 0.5 + 0.5 * sin(t * TAU / 1.6)
				var ring := PackedVector2Array()
				for q in pts:
					ring.append(p + (q - p) * (1.25 + 0.12 * br))
				ci.draw_polyline(_loop(ring), UI.fa(LINE_OK, 0.3 + 0.35 * br), 1.0)
			ci.draw_polyline(_loop(pts), col, 2.0)
			_icon(ci, id, p, col, 7.0)
		_:
			HS.fill(ci, pts, BASE)
			ci.draw_polyline(_loop(pts), NODE_LOCK, 1.0)
			_icon(ci, id, p, NODE_LOCK, 6.0)
	if id == lit_id and lit_f >= LIT_GROW:   # 解锁落定：外扩环
		var e := (lit_f - LIT_GROW) / (1.0 - LIT_GROW)
		ci.draw_arc(p, 18.0 + 34.0 * e, 0.0, TAU, 32, UI.fa(LINE_OK, 1.0 - e), 2.0)
	if selected:   # 四角角标
		var q := r + 12.0
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var c: Vector2 = p + s * q
			ci.draw_line(c, c - Vector2(s.x * 7.0, 0), HS.CYB, 2.0)
			ci.draw_line(c, c - Vector2(0, s.y * 7.0), HS.CYB, 2.0)
	var lc := LABEL if st != "lock" else LABEL_LOCK
	if hov and not selected:
		lc = LABEL.lightened(0.2)
	UI.text_at(ci, font, p + Vector2(0, r + 8.0), str(Meta.nodes()[id].name), 13, lc, "ma", selected)


func _octa(c: Vector2, r: float) -> PackedVector2Array:
	var h := r * 0.5
	return PackedVector2Array([c + Vector2(-r, -h), c + Vector2(-h, -r), c + Vector2(h, -r), c + Vector2(r, -h),
		c + Vector2(r, h), c + Vector2(h, r), c + Vector2(-h, r), c + Vector2(-r, h)])


func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])


func _loop(pts: PackedVector2Array) -> PackedVector2Array:
	var l := pts.duplicate()
	l.append(pts[0])
	return l


## 线别小图标（按节点 id 前缀）
func _icon(ci: CanvasItem, id: String, c: Vector2, col: Color, s: float) -> void:
	var p := id.rstrip("0123456789")
	match p:
		"atk":
			ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, 2.0)
			ci.draw_line(c + Vector2(s, -s), c + Vector2(-s, s), col, 2.0)
		"hp":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(-s / 3, 0), c + Vector2(-s / 6, -s), c + Vector2(s / 6, s), c + Vector2(s / 3, 0), c + Vector2(s, 0)]), col, 2.0)
		"def":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(-s, -s)]), col, 2.0)
		"reg":
			ci.draw_rect(Rect2(c.x - 1, c.y - s, 2, s * 2), col)
			ci.draw_rect(Rect2(c.x - s, c.y - 1, s * 2, 2), col)
		"sh":
			var hx := PackedVector2Array()
			for q in 7:
				hx.append(c + Vector2.from_angle(q * TAU / 6.0) * (s + 1))
			ci.draw_polyline(hx, col, 2.0)
		"xp":
			for o in [-4.0, 3.0]:
				ci.draw_polyline(PackedVector2Array([c + Vector2(-s, o + 3), c + Vector2(0, o - 4), c + Vector2(s, o + 3)]), col, 2.0)
		"gold":
			ci.draw_polyline(_loop(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, s), c + Vector2(-s * 0.7, 0)])), col, 2.0)
		"shop":
			ci.draw_arc(c, s, 0.0, TAU, 20, col, 2.0)
			ci.draw_rect(Rect2(c.x - 1, c.y - s + 3, 2, s * 2 - 6), col)
		_:
			for q in 4:
				ci.draw_rect(Rect2(c + Vector2(-s + (q % 2) * (s + 1), -s + (q / 2) * (s + 1)), Vector2(s - 1, s - 1)), col, false, 1.0)


func _draw_left(ci: CanvasItem) -> void:
	var by := DESIGN.y - BAR_H
	HS.fill(ci, PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(340 + 60.0 * (1.0 - by / DESIGN.y), by), Vector2(0, by)]), HS.LIGHT)
	ci.draw_line(Vector2(400, 0), Vector2(340 + 60.0 * (1.0 - by / DESIGN.y), by), HS.CYB, 2.0)
	# 标题块：黑底白字反色斜块 + 黄标
	HS.fill(ci, PackedVector2Array([Vector2(28, 62), Vector2(300, 62), Vector2(288, 116), Vector2(16, 116)]), HS.INK)
	UI.text_at(ci, font, Vector2(34, 89), "认知塑造", 36, Color8(240, 242, 246), "lm", true)
	ci.draw_rect(Rect2(248, 72, 38, 8), HS.YEL)
	HS.solid_px(ci, Vector2(30, 136), "COGNITION SHAPING", 2.0, HS.INK2)
	# 生机细胞
	UI.text_at(ci, font, Vector2(30, 168), "生机细胞", 16, HS.INK2)
	UI.text_at(ci, font, Vector2(28, 186), str(Meta.available()), 64, HS.RIB, "la", true)
	var done := 0
	for id in Cfg.meta_shape:
		if Cfg.meta_shape[id]:
			done += 1
	UI.text_at(ci, font, Vector2(186, 204), "已塑造  %d / %d" % [done, Meta.nodes().size()], 15, HS.INK, "la", true)
	UI.text_at(ci, font, Vector2(186, 228), "累计获得  %d" % Meta.earned_total(), 15, HS.INK2)
	ci.draw_line(Vector2(30, 282), Vector2(316, 282), HS.MUTE, 1.0)
	# 当前节点
	var id := _sel_id()
	if id == "":
		return
	var nd: Dictionary = Meta.nodes()[id]
	var st := _state(id)
	UI.text_at(ci, font, Vector2(30, 296), "当前节点", 16, HS.INK2)
	UI.text_at(ci, font, Vector2(30, 320), str(nd.name), 28, HS.INK, "la", true)
	var desc := str(nd.desc)
	var head := desc.get_slice("。", 0)
	var rest := desc.substr(head.length() + 1) if desc.contains("。") else ""
	if _re_head == null:
		_re_head = RegEx.create_from_string("^(.*?)\\s*([+\\-][0-9.]+%?)$")   # 只编译一次（原来每帧编译，10-25 帧率审计）
	var m := _re_head.search(head)
	var y := 366.0
	if m != null:
		UI.text_at(ci, font, Vector2(30, y), m.get_string(1), 16, HS.INK)
		UI.text_at(ci, font, Vector2(28, y + 20), m.get_string(2), 52, HS.RIB, "la", true)
		y += 92.0
	else:
		y = _para(ci, Vector2(30, y), head, 17, HS.INK, 286.0) + 10.0
	if rest != "":
		var tw := HS.tag(ci, font, Vector2(30, y), "质变", 0.8, HS.YEL)
		y = _para(ci, Vector2(30 + tw + 8, y + 2), rest, 13, HS.INK, 286.0 - tw - 8) + 10.0
	var line: String
	match st:
		"on":
			line = "已塑造：之后的每次探索生效"
		"ok":
			line = "塑造需要 %d 生机细胞" % int(nd.cost)
		"poor":
			line = "需要 %d 生机细胞，余额 %d" % [int(nd.cost), Meta.available()]
		_:
			if nd.has("req") and not Cfg.meta_shape.get(str(nd.req), false):
				line = "先塑造「%s」" % str(Meta.nodes()[str(nd.req)].name)
			else:
				line = "已塑造总量达到 %d 后开放（现为 %d）" % [int(nd.get("need", 0)), Meta.spent(Cfg.meta_shape)]
	UI.text_at(ci, font, Vector2(30, maxf(y + 4.0, 560.0)), line, 14, HS.RIB if st == "ok" else HS.INK2)
	# 这条链的末节质变（选的不是末节时预告）
	var ch: Array = chains[clampi(sel.x, 0, chains.size() - 1)]
	var last: String = ch[-1]
	if last != id and str(Meta.nodes()[last].desc).contains("。"):
		UI.text_at(ci, font, Vector2(30, 590), "末节  %s · %s" % [str(Meta.nodes()[last].name), RULE_TAG.get(last, "")], 13, HS.INK2)


## 按宽度折行（逐字），返回末行底 y
func _para(ci: CanvasItem, p: Vector2, s: String, sz: int, col: Color, w: float) -> float:
	var line := ""
	var y := p.y
	for c in s:
		if UI.cwidth(font, line + c, sz) > w:
			UI.text_at(ci, font, Vector2(p.x, y), line, sz, col)
			y += sz + 6.0
			line = ""
		line += c
	if line != "":
		UI.text_at(ci, font, Vector2(p.x, y), line, sz, col)
		y += sz + 6.0
	return y


func _draw_bars(ci: CanvasItem, mouse: Vector2) -> void:
	buttons.clear()
	# 顶：图谱标题 + 返回
	UI.text_at(ci, font, Vector2(GX0 + 40, 30), "塑造图谱", 24, LABEL, "lm", true)
	HS.solid_px(ci, Vector2(GX0 + 154, 31), "COGNITION MAP", 2.0, LABEL_LOCK)
	ci.draw_line(Vector2(GX0 + 40, 58), Vector2(DESIGN.x - 28, 58), UI.fa(LABEL_LOCK, 0.6), 1.0)
	var back := Rect2(DESIGN.x - 168, 12, 140, 36)
	HS.para(ci, back, Color(1, 1, 1, 0.12) if back.has_point(mouse) else Color(0, 0, 0, 0), Color(1, 1, 1, 0.8))
	UI.text_at(ci, font, back.get_center(), Pad.hint("返回  Esc", "返回  Ⓑ", "返回"), 15, UI.TEXT, "mm", true)
	buttons.append([back, "back"])
	# 底栏
	var by := DESIGN.y - BAR_H
	HS.bottom_bar(ci, DESIGN, BAR_H)
	var x := 24.0
	for it in [["推荐", "R", "rec"], ["再按确认重置" if reset_armed else "全部重置", "X", "reset"]]:
		var w := UI.cwidth(font, it[0], 15) + (40.0 if not Pad.touch else 24.0)
		var r := Rect2(x, by + 9, w, 30)
		var warn: bool = it[2] == "reset" and reset_armed
		HS.para(ci, r, UI.fa(UI.RED, 0.85) if warn else (Color(1, 1, 1, 0.12) if r.has_point(mouse) else Color(0, 0, 0, 0)), Color(1, 1, 1, 0.5))
		var tx := UI.text_at(ci, font, Vector2(r.position.x + 14, r.get_center().y), it[0], 15, UI.TEXT, "lm")
		if not Pad.touch:
			UI.text_at(ci, font, Vector2(r.position.x + 22 + tx, r.get_center().y + 1), it[1], 12, UI.fa(UI.TEXT, 0.6), "lm")
		buttons.append([r, it[2]])
		x += w + 14.0
	var id := _sel_id()
	var st := _state(id) if id != "" else "lock"
	var main := Rect2(DESIGN.x - 292, by, 292, BAR_H)
	if st == "on":
		UI.text_at(ci, font, Vector2(main.position.x - 24, by + BAR_H / 2.0), "已塑造", 16, LABEL_LOCK, "rm")
	elif id != "":
		UI.text_at(ci, font, Vector2(main.position.x - 24, by + BAR_H / 2.0), "消耗 %d 生机细胞" % int(Meta.nodes()[id].cost), 16, LABEL if st == "ok" else LABEL_LOCK, "rm")
	HS.fill(ci, PackedVector2Array([Vector2(main.position.x + 12, by), Vector2(DESIGN.x, by), Vector2(DESIGN.x, DESIGN.y), Vector2(main.position.x, DESIGN.y)]),
		HS.CYB if st == "ok" else Color8(60, 68, 80))
	UI.text_at(ci, font, main.get_center() + Vector2(6, 0), "确认塑造", 22, HS.INK if st == "ok" else LABEL_LOCK, "mm", true)
	if not Pad.touch:
		UI.text_at(ci, font, main.get_center() + Vector2(68, 1), "Enter", 12, UI.fa(HS.INK if st == "ok" else LABEL_LOCK, 0.7), "lm")
	buttons.append([main, "buy"])
