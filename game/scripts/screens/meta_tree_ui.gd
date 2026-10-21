extends Control
## 局外 · 认知塑造页（docs/109 §4，标题页磁贴「认知塑造」打开）。节点按线排成行：同一行从左往右要依次点亮；大节点另要求已点总量。
## 点击或 Enter 点亮选中的节点；R 推荐（按推荐顺序把余额点完）；X 两次全部重置（免费，全部退回）；Esc 返回。
## 画法：深色面板 + 青色描边（docs/37 IS3 风格），设计尺寸 1280×720，整体按界面大小缩放。只改 Cfg.meta_*，规则在 core/meta.gd。
signal closed

const UI = preload("res://scripts/ui.gd")
const Meta = preload("res://scripts/core/meta.gd")

const DESIGN := Vector2(1280, 720)
const LINES := ["攻击", "生命", "减伤", "回复", "护盾", "经验", "资源", "大节点"]
const CW := 118.0
const CH := 46.0
const GAP := 8.0
const ROW_H := 54.0
const X0 := 132.0
const Y0 := 134.0

var font: Font
var grid: Array = []        # 每行的节点 id
var sel := Vector2i(0, 0)   # 选中（行，列）
var rects := {}             # 节点 id → Rect2（设计坐标）
var buttons: Array = []     # [Rect2, 动作]
var reset_armed := false
var flash_t := -10.0
var flash_id := ""
var t := 0.0
var k := 1.0
var off := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
	hide()


func _build() -> void:
	grid.clear()
	var nodes := Meta.nodes()
	for ln in LINES:
		var row: Array = []
		for id in nodes:
			if str(nodes[id].get("line", "")) == ln:
				row.append(id)
		if not row.is_empty():
			grid.append(row)


func open() -> void:
	_build()
	sel = Vector2i(0, 0)
	reset_armed = false
	show()


func close() -> void:
	hide()
	closed.emit()


func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()


func _sel_id() -> String:
	if grid.is_empty():
		return ""
	var r := clampi(sel.x, 0, grid.size() - 1)
	return grid[r][clampi(sel.y, 0, grid[r].size() - 1)]


## 节点状态：on 已点 / ok 可点 / poor 余额不够 / lock 前置或门槛未到
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
	if Meta.buy(id):
		Sfx.play("relic", -4.0)
		flash_t = t
		flash_id = id
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
		for id in rects:
			if (rects[id] as Rect2).has_point(p):
				var pos := _pos_of(id)
				if pos == sel:
					_buy(id)
				else:
					sel = pos
					reset_armed = false
					Sfx.play("ui_move", -6.0)
				get_viewport().set_input_as_handled()
				return
		for b in buttons:
			if (b[0] as Rect2).has_point(p):
				_act(b[1])
				get_viewport().set_input_as_handled()
				return
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
				d = Vector2i(-1, 0)
			KEY_DOWN, KEY_S:
				d = Vector2i(1, 0)
			KEY_LEFT, KEY_A:
				d = Vector2i(0, -1)
			KEY_RIGHT, KEY_D:
				d = Vector2i(0, 1)
		if d != Vector2i.ZERO and not grid.is_empty():
			sel.x = clampi(sel.x + d.x, 0, grid.size() - 1)
			sel.y = clampi(sel.y + d.y, 0, grid[sel.x].size() - 1)
			reset_armed = false
			Sfx.play("ui_move", -6.0)
		get_viewport().set_input_as_handled()


func _pos_of(id: String) -> Vector2i:
	for r in grid.size():
		var c: int = grid[r].find(id)
		if c >= 0:
			return Vector2i(r, c)
	return sel


func _draw() -> void:
	k = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	off = ((size - DESIGN * k) / 2.0).floor()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.07, 0.97))
	draw_set_transform(off, 0.0, Vector2(k, k))
	var mouse := (get_local_mouse_position() - off) / k
	# 标题与余额
	UI.en(self, font, Vector2(48, 52), "COGNITIVE SHAPING", 13, UI.CYAN, 4.0)
	UI.text(self, font, Vector2(48, 94), "认知塑造", 32, UI.TEXT)
	UI.text(self, font, Vector2(214, 92), "每次探索结算获得生机细胞，点亮后在之后的探索中生效", 14, UI.SUB)
	var avail := Meta.available()
	UI.text(self, font, Vector2(DESIGN.x - 360, 66), "生机细胞", 14, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 160)
	UI.text(self, font, Vector2(DESIGN.x - 190, 72), str(avail), 34, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 140)
	UI.text(self, font, Vector2(DESIGN.x - 460, 98), "累计获得 %d  ·  已点 %d / %d" % [Meta.earned_total(), Meta.spent(Cfg.meta_shape), Meta.total_cost()], 13, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 410)
	draw_line(Vector2(48, 114), Vector2(DESIGN.x - 48, 114), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), 1.0)
	# 节点网格
	rects.clear()
	var nodes := Meta.nodes()
	for r in grid.size():
		var y := Y0 + r * ROW_H
		var row: Array = grid[r]
		UI.text(self, font, Vector2(48, y + CH / 2.0 + 6.0), str(nodes[row[0]].line), 15, UI.SUB)
		for c in row.size():
			var id: String = row[c]
			var rr := Rect2(X0 + c * (CW + GAP), y, CW, CH)
			rects[id] = rr
			if c > 0 and nodes[id].has("req"):
				draw_line(Vector2(rr.position.x - GAP, y + CH / 2.0), Vector2(rr.position.x, y + CH / 2.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5), 2.0)
			_draw_node(id, rr, Vector2i(r, c) == sel, rr.has_point(mouse))
	_draw_detail(mouse)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_node(id: String, r: Rect2, selected: bool, hov: bool) -> void:
	var nd: Dictionary = Meta.nodes()[id]
	var st := _state(id)
	var fill := Color(0.039, 0.078, 0.118, 0.9)
	var edge := Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.5)
	var ink := UI.TEXT
	var cost_col := UI.SUB
	match st:
		"on":
			fill = Color(UI.CYAN.r * 0.25, UI.CYAN.g * 0.25, UI.CYAN.b * 0.25, 0.95)
			edge = UI.CYAN
		"ok":
			edge = UI.GOLD
			cost_col = UI.GOLD
		"poor":
			cost_col = UI.SUB
		"lock":
			ink = Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, 0.6)
			edge = Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.25)
			cost_col = Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, 0.5)
	if selected:
		UI.rbox(self, r.grow(3.0), 6, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.18 + 0.06 * sin(t * 4.0)))
	UI.rbox(self, r, 4, fill, UI.CYAN if selected else (edge.lightened(0.2) if hov else edge), 2 if selected else 1)
	if id == flash_id and t - flash_t < 0.4:
		UI.rbox(self, r, 4, Color(1, 1, 1, 0.5 * (1.0 - (t - flash_t) / 0.4)))
	UI.text_fit(self, font, r.position + Vector2(10, 20), str(nd.name), 14, ink, r.size.x - 20, 10)
	var cost_s := "已点亮" if st == "on" else "%d" % int(nd.cost)
	UI.text(self, font, r.position + Vector2(10, 38), cost_s, 12, UI.CYAN if st == "on" else cost_col)
	if st == "lock":
		UI.text(self, font, r.position + Vector2(r.size.x - 44, 38), "未解锁", 10, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, 0.6))


func _draw_detail(mouse: Vector2) -> void:
	var r := Rect2(48, Y0 + 8 * ROW_H + 6, DESIGN.x - 96, 124)
	UI.rbox(self, r, 6, Color(0.03, 0.06, 0.1, 0.92), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.4), 1)
	buttons.clear()
	var id := _sel_id()
	if id != "":
		var nd: Dictionary = Meta.nodes()[id]
		var st := _state(id)
		UI.text(self, font, r.position + Vector2(22, 34), str(nd.name), 20, UI.TEXT)
		UI.text(self, font, r.position + Vector2(22, 64), str(nd.desc), 15, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 640)
		var line: String
		match st:
			"on":
				line = "已点亮：之后的每次探索生效"
			"ok":
				line = "点亮需要 %d 生机细胞（余额 %d）" % [int(nd.cost), Meta.available()]
			"poor":
				line = "需要 %d 生机细胞，余额 %d" % [int(nd.cost), Meta.available()]
			_:
				if nd.has("req") and not Cfg.meta_shape.get(str(nd.req), false):
					line = "先点亮「%s」" % str(Meta.nodes()[str(nd.req)].name)
				else:
					line = "已点总量达到 %d 后可点亮（现为 %d）" % [int(nd.get("need", 0)), Meta.spent(Cfg.meta_shape)]
		UI.text(self, font, r.position + Vector2(22, 98), line, 13, UI.GOLD if st == "ok" else UI.SUB)
	var bw := 128.0
	var bx := r.end.x - 22.0 - bw * 4 - 10.0 * 3
	var items := [["点亮", "Enter", "buy"], ["推荐", "R", "rec"], ["再按确认重置" if reset_armed else "全部重置", "X", "reset"], ["返回", "Esc", "back"]]
	for i in items.size():
		var br := Rect2(bx + i * (bw + 10.0), r.position.y + r.size.y / 2.0 - 20.0, bw, 40)
		buttons.append([br, items[i][2]])
		var hov := br.has_point(mouse)
		var warn: bool = items[i][2] == "reset" and reset_armed
		draw_rect(br, (UI.RED if warn else UI.CYAN) if hov or warn else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
		var bink := Color(0.04, 0.07, 0.09) if hov or warn else UI.TEXT
		UI.text_fit(self, font, br.position + Vector2(12, 26), items[i][0], 15, bink, bw - 56, 11)
		if not Pad.touch:
			UI.keycap(self, font, Vector2(br.end.x - UI.cwidth(font, items[i][1], 10) - 16, br.position.y + 11), items[i][1], bink, 10)
