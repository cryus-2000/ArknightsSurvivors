extends Control
## 局外 · 认知塑造页（docs/109 §4；10-25 重做，art/incoming/meta_ui_1025/）。只改 Cfg.meta_*，规则与数据在 core/meta.gd / data/meta_tree.json。
## 版式：原作水月「认知塑造」的节点语言 + 深蓝之树的根系——树干从顶栏垂下，分出几条主根（探索 / 成长 / 战斗 / 生存），每条线从主根分叉成
## 一条细根，节点按弧长排在根上，越深越高阶；根尖越过末节再长一小段。布局在 data/meta_roots.json（art/incoming/meta_ui_1025/layout.py 生成）。
## 两种画风（用户挑定前都留着，--metastyle=tree|sea）：
##   tree 深蓝之树：水下像素场景（树冠的光、光柱、海床），树干带荧光脉络，已塑造的根发青光、有汁液流动；一屏放下，节点只写名字。
##   sea 原作夜海：夜空 + 地平线 + 海面横纹，白色连线、进入质变节点的线上有蓝色三角；节点写名称 + 一行效果；画布 1.5 倍，镜头跟随、可拖动。
## 像素层（背景、树干、根、节点）画进低分辨率 SubViewport（1 格 = 2 设计单位，最近邻放大）；文字、外框、详情卡画在 view（设计单位）里保持清晰。
## 节点照原作：黑盘 + 白环 + 白色图形 + 点状外环、右下消耗；质变节点（带 rule 的）是放射条纹大盘。已塑造 = 白盘黑图；可塑造 = 黄色点环转动呼吸；
## 余额不够 = 灰环；未解锁 = 暗。招牌动效：塑造时一道光沿根从上一节流到新节点（0.55 秒）→ 节点翻白 + 外扩环（0.45 秒）。
## 操作：方向键 / 手柄十字键按方向找最近的节点；点节点选中、再点 / Enter / 详情卡「塑造」塑造；R 推荐（按推荐顺序把余额点完）；X 两次全部重置（免费退回）；
## Esc 返回；画布比屏幕大时拖动 / 滚轮平移，换选中后镜头跟随。减少动态效果：不生长、不呼吸、无汁液流动，镜头直接到位。
signal closed

const UI = preload("res://scripts/ui.gd")
const HS = preload("res://scripts/screens/hh_style.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const Meta = preload("res://scripts/core/meta.gd")
const Icons = preload("res://scripts/screens/meta_icons.gd")

## 链的顺序（--metasel=链,节 按这个；数据里新增的根接在最后）
const ROOT_ORDER := ["disp1", "shop1", "gold1", "pick1", "xp1", "sh1", "atk1", "hp1", "def1", "reg1"]
## 质变节点的规则短名（详情卡标签）
const RULE_TAG := {"atk5": "处决", "hp5": "濒死免死", "def4": "久守减伤", "reg3": "低血回复", "sh1": "碎盾反震", "xp4": "升级再升",
	"disp1": "四选一", "disp2": "免费刷新", "disp3": "开局藏品", "disp4": "绝处逢生"}
## 分组（主根）：前缀 → 组；组名 / 英文 / 组色（详情卡标签与主根旁的小标）
const GROUP_OF := {"shop": 0, "gold": 0, "pick": 0, "xp": 1, "disp": 1, "atk": 2, "sh": 2, "hp": 3, "def": 3, "reg": 3}
const GROUPS := [["探索", "EXPLORE", Color8(255, 196, 70)], ["成长", "GROWTH", Color8(168, 150, 255)], ["战斗", "COMBAT", Color8(255, 112, 98)],
	["生存", "SURVIVAL", Color8(92, 214, 152)]]
const MAIN_GROUP := {"L": 0, "C": 1, "R1": 2, "R2": 3}

const PX_DESIGN := 2.0        # 像素格的目标大小（设计单位）；实际 pxu 按屏幕取整（见 _fit）
const RN_DESIGN := 16.0       # 普通节点半径（设计单位）
const RK_DESIGN := 22.0       # 质变节点半径
const LIT_DUR := 1.0
const LIT_GROW := 0.55

## 像素层颜色
const C_TRUNK := Color8(7, 18, 29)
const C_TRUNK_HI := Color8(70, 128, 156)
const C_ROOT := Color8(40, 72, 96)
const C_ROOT_HI := Color8(66, 108, 134)
const C_SAP := Color8(118, 238, 255)
const C_LINE := Color8(204, 212, 222)
const C_LINE_DIM := Color8(88, 100, 116)
const C_DISC := Color8(10, 15, 22)
const C_WHITE := Color8(238, 243, 246)
const C_POOR := Color8(138, 150, 163)
const C_LOCK := Color8(70, 82, 96)
const C_YEL := Color8(255, 206, 0)
const C_ARROW := Color8(72, 150, 255)
## 文字颜色（view 层）
const T_ON := Color8(236, 241, 245)
const T_POOR := Color8(160, 172, 184)
const T_LOCK := Color8(104, 116, 130)
const T_SUB := Color8(150, 164, 178)

var style := "tree"
var font: Font
var vp: SubViewport           # 像素层
var bgrect: ColorRect
var bgmat: ShaderMaterial
var wn: Node2D                # 像素层里画树干 / 根 / 节点（像素格坐标）
var under: Control            # 放像素层画面（设计单位，在 view 下面）
var pix: TextureRect
var view: Control             # 文字 / 外框 / 详情卡（设计单位）
var lay: Dictionary = {}
var chains: Array = []        # 每条链的节点 id（从第一节往末节）
var geo := {}                 # 链前缀 → 整条根的采样点（世界坐标）
var ni := {}                  # 节点 id → 在本链 geo 里的下标
var pos := {}                 # 节点 id → 世界坐标（设计单位）
var mains := {}               # 主根名 → 采样点
var sel := Vector2i(0, 0)     # 选中（链，节）
var hover := ""
var buttons: Array = []       # [Rect2, 动作]（设计坐标）
var reset_armed := false
var lit_id := ""              # 塑造演出中的节点
var lit_t0 := -10.0
var open_t0 := -10.0
var t := 0.0
var kd := 1.0                 # 界面单位 / 设计单位
var vs := Vector2(1280, 720)  # 视口（设计单位）
var cam := Vector2.ZERO       # 视口左上角（世界坐标，设计单位）
var cam_px := Vector2.ZERO    # 取整到像素格后的镜头
var follow := true            # 换选中后镜头跟随；拖动后停跟，直到下一次换选中
var drag := 0                 # 0 没按 / 1 按下 / 2 拖动中
var drag_p := Vector2.ZERO
var drag_cam := Vector2.ZERO
var motes: Array = []
var pxu := 2.0                # 1 像素格 = pxu 设计单位：一格恰好是整数个屏幕像素（720p / 1080p = 2，900p = 2.4），任何分辨率都是整齐的方块
var rn := 8                   # 普通 / 质变节点半径（像素格）
var rk := 11

static var _re_head: RegEx
static var _re_sum: RegEx


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
	for a in Cfg.dev_args():
		if a.begins_with("--metastyle="):
			style = a.substr(12)
	vp = SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.size = Vector2i(642, 362)
	add_child(vp)
	bgrect = ColorRect.new()
	bgmat = ShaderMaterial.new()
	bgmat.shader = preload("res://shaders/meta_bg.gdshader")
	bgrect.material = bgmat
	vp.add_child(bgrect)
	wn = Node2D.new()
	wn.draw.connect(_draw_world)
	vp.add_child(wn)
	under = Control.new()
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(under)
	pix = TextureRect.new()
	pix.texture = vp.get_texture()
	pix.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pix.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pix.stretch_mode = TextureRect.STRETCH_SCALE
	pix.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_child(pix)
	view = Control.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.draw.connect(_draw_view)
	add_child(view)
	var rng := RandomNumberGenerator.new()   # 独立种子：不碰局内随机数
	rng.seed = 20261025
	for i in 46:
		motes.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(3.0, 9.0), rng.randf() * TAU, rng.randf() < 0.3])
	hide()


func _pre(id: String) -> String:
	return id.rstrip("0123456789")


func _is_key(id: String) -> bool:
	for ef in Meta.nodes()[id].get("effects", []):
		if ef.has("rule") or ef.has("start_relic"):
			return true
	return false


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func _bez(c: Array, u: float) -> Vector2:
	var w := 1.0 - u
	return (c[0] as Vector2) * w * w * w + (c[1] as Vector2) * 3.0 * w * w * u + (c[2] as Vector2) * 3.0 * w * u * u + (c[3] as Vector2) * u * u * u


func _bez_pts(c: Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		out.append(_bez(c, float(i) / n))
	return out


func _build() -> void:
	chains.clear()
	geo.clear()
	ni.clear()
	pos.clear()
	mains.clear()
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta_roots.json"))
	lay = j.get("orig" if style == "sea" else "scene", {}) if j is Dictionary else {}
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
	var ms: Dictionary = lay.get("mains", {})
	for m in ms:
		var spec: Array = ms[m]
		mains[m] = _bez_pts([_v(spec[0]), _v(spec[1]), _v(spec[2]), _v(spec[3])], 48)
	var rs: Dictionary = lay.get("roots", {})
	for ci in chains.size():
		var ch: Array = chains[ci]
		var p := _pre(ch[0])
		if not rs.has(p):   # 布局里没有的新线：挂在右边临时排一列（数据加线后跑 layout.py 补上）
			for k in ch.size():
				pos[ch[k]] = Vector2(1200.0, 160.0 + k * 90.0)
				ni[ch[k]] = 0
			geo[p] = PackedVector2Array([Vector2(1200, 120), Vector2(1200, 160.0 + ch.size() * 90.0)])
			continue
		var spec: Array = rs[p]
		var mspec: Array = ms[spec[0]]
		var mc := [_v(mspec[0]), _v(mspec[1]), _v(mspec[2]), _v(mspec[3])]
		var c := [_bez(mc, float(spec[1])), _v(spec[2]), _v(spec[3]), _v(spec[4])]
		var pts := _bez_pts(c, 140)
		var acc := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			acc.append(acc[i - 1] + pts[i].distance_to(pts[i - 1]))
		var total: float = acc[acc.size() - 1]
		var n := ch.size()
		for k in n:
			var f: float = float(spec[5]) + (float(spec[6]) - float(spec[5])) * (float(k) / (n - 1) if n > 1 else 1.0)
			var idx := acc.bsearch(f * total)
			idx = clampi(idx, 0, pts.size() - 1)
			pos[ch[k]] = pts[idx]
			ni[ch[k]] = idx
		geo[p] = pts


func _root_rank(id: String) -> int:
	var r := ROOT_ORDER.find(id)
	return r if r >= 0 else 100


func open() -> void:
	_fit()
	_build()
	sel = Vector2i(0, 0)
	# 缺省选第一个能塑造的节点（没有就第一条链的第一节）
	var found := false
	for i in chains.size():
		for k in chains[i].size():
			if not found and _state(chains[i][k]) == "ok":
				sel = Vector2i(i, k)
				found = true
	reset_armed = false
	lit_id = ""
	open_t0 = t
	follow = true
	drag = 0
	cam = _cam_center()
	cam = _cam_goal()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	show()


func close() -> void:
	hide()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	closed.emit()


## 版面：设计高 720（手机 640），宽随屏；像素层按视口大小（像素格）建
func _fit() -> void:
	if size.y < 8.0 or size.x < 8.0:   # 还没排版（标题页 _ready 里就 open 的截图路径）：等下一帧
		return
	var h := 640.0 if Cfg.phone_ui() else 720.0
	kd = size.y / h
	vs = size / kd
	under.scale = Vector2(kd, kd)
	view.scale = Vector2(kd, kd)
	under.size = vs
	view.size = vs
	var sk: float = TUI.ctx(view).k   # 屏幕像素 / 设计单位
	var n := maxi(1, roundi(PX_DESIGN * sk))
	pxu = n / sk
	rn = maxi(5, roundi(RN_DESIGN / pxu))
	rk = maxi(7, roundi(RK_DESIGN / pxu))
	var vpx := Vector2i(mini(ceili(vs.x / pxu) + 2, 2048), mini(ceili(vs.y / pxu) + 2, 2048))
	if vp.size != vpx:
		vp.size = vpx
	bgrect.size = Vector2(vpx)
	pix.size = Vector2(vpx) * pxu


func _world() -> Vector2:
	var w: Array = lay.get("world", [1280, 720])
	return Vector2(float(w[0]), float(w[1]))


func _pannable() -> bool:
	var rg := _cam_range()
	return rg.size.x > 1.0 or rg.size.y > 1.0


## 选中节点应当落在的视口区域（设计坐标）：桌面在详情卡右边、顶栏下面；手机在底条上面
func _safe() -> Rect2:
	if Cfg.phone_ui():
		return Rect2(40.0, 120.0, vs.x - 80.0, vs.y - 120.0 - SHEET_H - 64.0)
	return Rect2(380.0, 130.0, vs.x - 420.0, vs.y - 196.0)


## 镜头能去的范围：世界比视口大的那一维 = 世界范围（四周留一点）；比视口小 = 在余量里平移（世界始终整个可见）；
## 手机底部多留一条底条的高度，最深的节点也能拉到底条上面
func _cam_range() -> Rect2:
	var w := _world()
	var lo := Vector2.ZERO
	var hi := Vector2.ZERO
	if w.x <= vs.x:
		lo.x = w.x - vs.x
	else:
		lo.x = -40.0
		hi.x = w.x - vs.x + 40.0
	var extra := SHEET_H + 24.0 if Cfg.phone_ui() else 0.0
	if w.y <= vs.y:
		lo.y = w.y - vs.y
		hi.y = minf(0.0 + extra, maxf(0.0, w.y + extra - vs.y))
	else:
		lo.y = -20.0
		hi.y = w.y - vs.y + 30.0 + extra
	return Rect2(lo, hi - lo)


## 镜头目标：打开时居中；之后换选中只挪到让选中节点进安全区为止（不乱晃）
func _cam_goal() -> Vector2:
	var c := cam
	if follow:
		var sp: Vector2 = pos.get(_sel_id(), _world() / 2.0)
		var sf := _safe()
		c.x = clampf(c.x, sp.x - sf.end.x, sp.x - sf.position.x)
		c.y = clampf(c.y, sp.y - sf.end.y, sp.y - sf.position.y)
	return _clamp_cam(c)


## 打开时的镜头：世界居中；比视口大时让树冠落在顶部标题下方、水平居中
func _cam_center() -> Vector2:
	var c := (_world() - vs) / 2.0
	var cr := _v(lay.get("crown", [556, 170]))
	if _world().y > vs.y:
		c.y = cr.y - 170.0
	if _world().x > vs.x:
		c.x = cr.x - vs.x * 0.5
	return _clamp_cam(c)


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	_fit()
	var goal := _cam_goal()
	if drag == 2:
		goal = cam
	if Cfg.reduce_motion or drag == 2:
		cam = goal
	else:
		cam = cam.lerp(goal, 1.0 - exp(-delta * 7.0))
	cam_px = (cam / pxu).round() * pxu
	bgmat.set_shader_parameter("style", 1.0 if style == "sea" else 0.0)
	bgmat.set_shader_parameter("size", Vector2(vp.size))
	bgmat.set_shader_parameter("cam", cam_px / pxu)
	bgmat.set_shader_parameter("world", _world() / pxu)
	bgmat.set_shader_parameter("crown", _v(lay.get("crown", [556, 170])) / pxu)
	bgmat.set_shader_parameter("time", t)
	bgmat.set_shader_parameter("still", 1.0 if Cfg.reduce_motion else 0.0)
	wn.queue_redraw()
	view.queue_redraw()


func _sel_id() -> String:
	if chains.is_empty():
		return ""
	var r := clampi(sel.x, 0, chains.size() - 1)
	return chains[r][clampi(sel.y, 0, chains[r].size() - 1)]


func _select(id: String) -> void:
	for i in chains.size():
		var k: int = chains[i].find(id)
		if k >= 0:
			if Vector2i(i, k) != sel:
				sel = Vector2i(i, k)
				Sfx.play("ui_move", -6.0)
			reset_armed = false
			follow = true
			return


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


## 世界坐标 → 设计坐标（取整到像素格，文字和像素层对齐）
func _to_view(w: Vector2) -> Vector2:
	return ((w - cam_px) / pxu).round() * pxu


func _node_at(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for id in pos:
		var r := (rk if _is_key(id) else rn) * pxu + 8.0
		var d := _to_view(pos[id]).distance_to(p)
		if d < r and d < bd:
			bd = d
			best = id
	return best


## 方向导航：↑↓ 先沿本条根走（下 = 更深的下一节、上 = 上一节）；走不了，或 ←→，就在方向 d 上（夹角 < 70°）
## 找「距离 ×（1 + 2.2 × 偏角）」最小的节点
func _nav(d: Vector2) -> void:
	var cur := _sel_id()
	if cur == "":
		return
	var p0: Vector2 = pos[cur]
	if d.y != 0.0:
		var ch: Array = chains[clampi(sel.x, 0, chains.size() - 1)]
		var nk: int = ch.find(cur) + (1 if d.y > 0.0 else -1)
		if nk >= 0 and nk < ch.size() and ((pos[ch[nk]] as Vector2) - p0).normalized().dot(d) > 0.2:
			_select(ch[nk])
			return
	var best := ""
	var bs := INF
	for id in pos:
		if id == cur:
			continue
		var v: Vector2 = pos[id] - p0
		var l := v.length()
		if l < 1.0:
			continue
		var c := v.dot(d) / l
		if c < 0.34:
			continue
		var s := l * (1.0 + 2.2 * (1.0 - c))
		if s < bs:
			bs = s
			best = id
	if best != "":
		_select(best)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		var p := view.get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				drag = 1
				drag_p = p
				drag_cam = cam
			else:
				var was := drag
				drag = 0
				if was != 2:
					_click(p)
		elif event.pressed and _pannable() and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			follow = false
			cam.y += -60.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0
			cam = _clamp_cam(cam)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var p := view.get_local_mouse_position()
		if drag == 1 and p.distance_to(drag_p) > 8.0 and _pannable():
			drag = 2
			follow = false
		if drag == 2:
			cam = _clamp_cam(drag_cam - (p - drag_p))
		hover = _node_at(p)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = Pad.kc(event)
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
				_nav(Vector2.UP)
			KEY_DOWN, KEY_S:
				_nav(Vector2.DOWN)
			KEY_LEFT, KEY_A:
				_nav(Vector2.LEFT)
			KEY_RIGHT, KEY_D:
				_nav(Vector2.RIGHT)
		get_viewport().set_input_as_handled()


func _clamp_cam(c: Vector2) -> Vector2:
	var rg := _cam_range()
	return Vector2(clampf(c.x, rg.position.x, rg.end.x), clampf(c.y, rg.position.y, rg.end.y))


func _click(p: Vector2) -> void:
	for b in buttons:
		if (b[0] as Rect2).has_point(p):
			_act(b[1])
			return
	var id := _node_at(p)
	if id == "":
		return
	if id == _sel_id():
		_buy(id)
	else:
		_select(id)


# ---------------------------------------------------------------- 像素层
## 世界 → 像素格（视口内）
func _a(w: Vector2) -> Vector2:
	return ((w - cam_px) / pxu).round()


## 开场：主根先长（0–0.35 秒），各线随后（每条晚 0.03 秒、0.45 秒长完）；减少动态效果直接到位
func _grow_main() -> float:
	if Cfg.reduce_motion:
		return 1.0
	return UI.ease_out(clampf((t - open_t0) / 0.35, 0.0, 1.0))


func _grow(i: int) -> float:
	if Cfg.reduce_motion:
		return 1.0
	return UI.ease_out(clampf((t - open_t0 - 0.22 - 0.03 * i) / 0.45, 0.0, 1.0))


func _draw_world() -> void:
	var ci := wn
	if lay.is_empty():
		return
	if style == "tree":
		_draw_trunk(ci)
	else:
		_draw_start(ci)
	_draw_mains(ci)
	for i in chains.size():
		_draw_chain(ci, i)
	if style == "tree":
		_draw_motes(ci)
	var sid := _sel_id()
	for i in chains.size():
		var g := _grow(i)
		var ch: Array = chains[i]
		var p := _pre(ch[0])
		var lim := int(g * (geo[p].size() - 1))
		for id in ch:
			if ni[id] <= lim:
				_draw_node(ci, id, id == sid)


## 树干（深蓝之树）：从视口顶上垂到树冠，越往下越细、底部张开接主根；左亮右暗两道边、几道树皮纹、两条荧光脉络往下流；
## 树冠是一颗发光的「心」，外面两圈点状圆环（原作「开始」处的大圆）
func _draw_trunk(ci: CanvasItem) -> void:
	var cr := _v(lay.get("crown", [556, 170]))
	var n := 18
	var l := PackedVector2Array()
	var rr := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / n
		var y := lerpf(-70.0, cr.y + 4.0, u)
		var x := cr.x + sin(u * 3.1 + 0.6) * 8.0 * (1.0 - u)
		var w := lerpf(70.0, 12.0, pow(u, 0.65))
		if u > 0.8:
			w += (u - 0.8) / 0.2 * 18.0   # 根部张开
		l.append(_a(Vector2(x - w, y)))
		rr.append(_a(Vector2(x + w * 0.9, y)))
	var poly := l.duplicate()
	for i in range(rr.size() - 1, -1, -1):
		poly.append(rr[i])
	# 一层淡辉光把树干从水色里托出来
	var mid := PackedVector2Array()
	for i in n + 1:
		mid.append(l[i].lerp(rr[i], 0.5))
	ci.draw_polyline(mid, Color(C_SAP, 0.05), (rr[0].x - l[0].x) + 14.0)
	ci.draw_polyline(mid, Color(C_SAP, 0.06), (rr[0].x - l[0].x) * 0.5 + 10.0)
	ci.draw_colored_polygon(poly, C_TRUNK)
	# 树皮纹
	for v in 5:
		var line := PackedVector2Array()
		for i in n + 1:
			line.append((l[i].lerp(rr[i], 0.14 + v * 0.17) + Vector2(sin(i * 1.3 + v * 2.0) * 0.8, 0)).round())
		ci.draw_polyline(line, Color(0.02, 0.07, 0.11, 0.8), 1.0)
	ci.draw_polyline(l, C_TRUNK_HI, 2.0)
	ci.draw_polyline(rr, Color(C_SAP, 0.35), 1.0)
	# 荧光脉络：两条，带一层辉光；光点往下流
	for v in 2:
		var vein := PackedVector2Array()
		for i in n + 1:
			vein.append(l[i].lerp(rr[i], 0.36 + v * 0.3 + 0.07 * sin(i * 0.8 + v * 3.0)).round())
		ci.draw_polyline(vein, Color(C_SAP, 0.10), 3.0)
		ci.draw_polyline(vein, Color(C_SAP, 0.38), 1.0)
		if not Cfg.reduce_motion:
			for q in 3:
				var f := fmod(t * 0.22 + q / 3.0 + v * 0.17, 1.0)
				var k := int(f * n)
				ci.draw_rect(Rect2(vein[k] - Vector2(0, 1), Vector2(1, 3)), Color(C_SAP, 0.9))
	# 树冠：两圈点状圆环 + 发光的心
	var c := _a(cr)
	for r: int in [26, 40]:
		var m := 40 if r == 26 else 56
		for k in m:
			if k % 2 == 0:
				var d: Vector2 = Vector2.from_angle(k * TAU / m) * float(r)
				ci.draw_rect(Rect2((c + d).floor(), Vector2(1, 1)), Color(C_SAP, 0.22 if r == 26 else 0.12))
	var br := 0.0 if Cfg.reduce_motion else 0.5 + 0.5 * sin(t * TAU / 3.0)
	ci.draw_circle(c, 10.0, Color(C_SAP, 0.08 + 0.04 * br))
	ci.draw_circle(c, 6.0, Color(C_SAP, 0.22))
	ci.draw_circle(c, 3.5, C_SAP)
	ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)


## 夜海：树冠位置是原作的「开始」——小菱形 + 圆环
func _draw_start(ci: CanvasItem) -> void:
	var c := _a(_v(lay.get("crown", [556, 170])))
	for r: int in [30, 46]:
		var n := 64
		for k in n:
			if k % 2 == 0:
				var d: Vector2 = Vector2.from_angle(k * TAU / n) * float(r)
				ci.draw_rect(Rect2((c + d).floor(), Vector2(1, 1)), Color(C_LINE, 0.18 if r == 30 else 0.1))
	var dm := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)])
	ci.draw_colored_polygon(dm, C_DISC)
	dm.append(dm[0])
	ci.draw_polyline(dm, C_WHITE, 1.0)
	ci.draw_rect(Rect2(c - Vector2(1, 1), Vector2(3, 3)), C_WHITE)


func _seg_pts(pts: PackedVector2Array, i0: int, i1: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(maxi(0, i0), mini(pts.size(), i1 + 1)):
		out.append(_a(pts[i]))
	return out


## 主根：粗、渐细；所在组有已塑造的节点时带一层淡青光
func _draw_mains(ci: CanvasItem) -> void:
	var g := _grow_main()
	var ms: Dictionary = lay.get("mains", {})
	for m in mains:
		var pts: PackedVector2Array = mains[m]
		var spec: Array = ms[m]
		var lim := int(g * (pts.size() - 1))
		var lit := false
		for p in GROUP_OF:
			if GROUP_OF[p] == MAIN_GROUP.get(m, -1):
				for id in Cfg.meta_shape:
					if Cfg.meta_shape[id] and _pre(id) == p:
						lit = true
		var pieces := 6
		for k in pieces:
			var i0 := floori(float(k * (pts.size() - 1)) / pieces)
			var i1 := floori(float((k + 1) * (pts.size() - 1)) / pieces)
			if i0 >= lim:
				break
			var w := lerpf(float(spec[4]), float(spec[5]), (k + 0.5) / pieces) / pxu
			var sp := _seg_pts(pts, i0, mini(i1, lim))
			if sp.size() < 2:
				continue
			if style == "tree":
				if lit:
					ci.draw_polyline(sp, Color(C_SAP, 0.14), w + 3.0)
				ci.draw_polyline(sp, C_ROOT, maxf(1.0, round(w)))
				ci.draw_polyline(sp, Color(C_ROOT_HI, 0.8), 1.0)
				if k in [1, 3, 5] and sp.size() > 3:   # 细须：从主根往下斜出一小截
					var q := sp[sp.size() / 2]
					var tg := (sp[sp.size() - 1] - sp[0]).normalized()
					var dn := Vector2(tg.y, -tg.x) if tg.x < 0.0 else Vector2(-tg.y, tg.x)
					var ln := 7.0 + (k % 3) * 3.0
					ci.draw_polyline(PackedVector2Array([q, (q + dn * ln * 0.5 + tg * 2.0).round(), (q + dn * ln + tg * 5.0).round()]), Color(C_ROOT, 0.8), 1.0)
			else:
				ci.draw_polyline(sp, Color(C_LINE, 0.85), 2.0)


func _draw_chain(ci: CanvasItem, i: int) -> void:
	var ch: Array = chains[i]
	var p := _pre(ch[0])
	var pts: PackedVector2Array = geo[p]
	var lim := int(_grow(i) * (pts.size() - 1))
	var prev := 0
	var n := ch.size()
	var lit_f := (t - lit_t0) / LIT_DUR if lit_id != "" else 2.0
	for k in n:
		var id: String = ch[k]
		var i1: int = ni[id]
		var sp := _seg_pts(pts, prev, mini(i1, lim))
		if sp.size() >= 2:
			var st := _state(id)
			if id == lit_id and lit_f < LIT_GROW:
				st = "ok"
			var w := 1.0
			if style == "tree":
				w = clampf(4.0 - k * 0.6, 1.5, 4.0)
				if st == "on":
					ci.draw_polyline(sp, Color(C_SAP, 0.22), w + 3.0)
					ci.draw_polyline(sp, C_ROOT, w)
					ci.draw_polyline(sp, C_SAP, 1.0)
				else:
					ci.draw_polyline(sp, C_ROOT if st != "lock" else Color(C_ROOT, 0.7), w)
					if st == "ok":
						ci.draw_polyline(sp, Color(C_ROOT_HI, 0.9), 1.0)
			else:
				match st:
					"on":
						ci.draw_polyline(sp, Color(C_SAP, 0.25), 5.0)
						ci.draw_polyline(sp, C_SAP, 2.0)
					"ok", "poor":
						ci.draw_polyline(sp, C_LINE, 2.0)
					_:
						ci.draw_polyline(sp, C_LINE_DIM, 2.0)
				if _is_key(id) and sp.size() > 6:   # 原作：进入大节点的线上有蓝色三角
					var m := floori(sp.size() * 0.6)
					var dv := (sp[mini(m + 2, sp.size() - 1)] - sp[maxi(m - 2, 0)]).normalized()
					var q := sp[m]
					var tri := PackedVector2Array([q + dv * 4.0, q - dv * 2.0 + dv.orthogonal() * 3.5, q - dv * 2.0 - dv.orthogonal() * 3.5])
					ci.draw_colored_polygon(tri, C_ARROW)
			# 塑造演出：光从上一节沿根流到新节点
			if id == lit_id and lit_f < LIT_GROW:
				var gf := UI.ease_out(clampf(lit_f / LIT_GROW, 0.0, 1.0))
				var m2 := int(gf * (sp.size() - 1))
				var part := sp.slice(0, m2 + 1)
				if part.size() >= 2:
					ci.draw_polyline(part, Color(C_SAP, 0.35), 5.0)
					ci.draw_polyline(part, Color.WHITE, 2.0 if style == "sea" else 1.0)
				ci.draw_circle(sp[m2], 3.0, Color(1, 1, 1, 0.35))
				ci.draw_rect(Rect2(sp[m2] - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
			# 汁液：已塑造的根上，小光点慢慢往下流
			elif style == "tree" and _state(id) == "on" and not Cfg.reduce_motion:
				var gap := 9
				var off := int(t * 14.0) % gap
				for q in range(off, sp.size(), gap):
					ci.draw_rect(Rect2(sp[q], Vector2(1, 1)), Color(1, 1, 1, 0.85))
		prev = i1
	# 根尖：越过末节再长一小段，渐细渐暗
	var tl := _seg_pts(pts, prev, lim)
	if tl.size() >= 2:
		ci.draw_polyline(tl, Color(C_ROOT if style == "tree" else C_LINE_DIM, 0.6), 1.0)


func _draw_motes(ci: CanvasItem) -> void:
	var w := _world()
	for m in motes:
		var u: Vector2 = m[0]
		var y := fposmod(u.y * w.y - (0.0 if Cfg.reduce_motion else t * float(m[1])), w.y)
		var x := u.x * w.x + (0.0 if Cfg.reduce_motion else sin(t * 0.4 + float(m[2])) * 6.0)
		var a := 0.35 + 0.25 * sin(t * 0.8 + float(m[2]))
		ci.draw_rect(Rect2(_a(Vector2(x, y)), Vector2(1, 1)), Color(C_SAP if m[3] else C_ROOT_HI, a))


func _draw_node(ci: CanvasItem, id: String, selected: bool) -> void:
	var p := _a(pos[id])
	var key := _is_key(id)
	var r := rk if key else rn
	var st := _state(id)
	var lit_f := (t - lit_t0) / LIT_DUR if lit_id != "" else 2.0
	if lit_f >= 1.0:
		lit_id = ""
	if id == lit_id and lit_f < LIT_GROW:
		st = "ok"
	var rm := Cfg.reduce_motion
	var ring := C_WHITE
	var fill := C_DISC
	var ic := C_WHITE
	match st:
		"on":
			fill = C_WHITE
			ic = C_DISC
		"poor":
			ring = C_POOR
			ic = C_POOR
		"lock":
			ring = C_LOCK
			ic = C_LOCK
	# 质变节点：放射条纹（已塑造慢转）
	if key:
		var rc := Color(C_WHITE, 0.9) if st == "on" else (Color(ring, 0.55))
		var rot := (t * 0.05 if st == "on" and not rm else 0.0)
		for k in 28:
			var dv := Vector2.from_angle(k * TAU / 28.0 + rot)
			var l1 := r + (5 if k % 2 == 0 else 3)
			ci.draw_line(p + dv * (r + 2), p + dv * l1, rc, 1.0)
	# 点状外环：可塑造 = 黄、转动呼吸；已塑造 = 白；其余不画
	if st == "ok" or st == "on":
		var dr := r + (7 if key else 3)
		var n := 24 if key else 14
		var rot2 := (t * 0.6 if st == "ok" and not rm else 0.0)
		var a := 1.0
		var col := Color(C_WHITE, 0.55)
		if st == "ok":
			a = 0.55 + 0.45 * sin(t * TAU / 1.6) if not rm else 1.0
			col = Color(C_YEL, a)
		for k in n:
			var dv := Vector2.from_angle(k * TAU / n + rot2) * dr
			ci.draw_rect(Rect2((p + dv).floor(), Vector2(1, 1)), col)
	if st == "on":   # 已塑造：一圈很淡的青光
		ci.draw_circle(p, r + 5.0, Color(C_SAP, 0.10))
		ci.draw_circle(p, r + 2.5, Color(C_SAP, 0.16))
	ci.draw_circle(p, r + 0.5, fill)
	ci.draw_arc(p, r, 0.0, TAU, 40, ring, 1.0)
	if key:
		ci.draw_arc(p, r - 2, 0.0, TAU, 36, Color(ring if st != "on" else C_DISC, 0.5), 1.0)
	var tex := Icons.tex(id if _pre(id) == "disp" else _pre(id))
	ci.draw_texture(tex, p - Vector2(5, 5), ic)
	# 塑造落定：外扩环
	if id == lit_id and lit_f >= LIT_GROW:
		var e := (lit_f - LIT_GROW) / (1.0 - LIT_GROW)
		ci.draw_arc(p, r + 2 + 16.0 * e, 0.0, TAU, 40, Color(C_SAP, 1.0 - e), 1.0)
	# 选中：四角黄角标（轻微呼吸）
	if selected:
		var q := r + (11 if key else 6) + (0.0 if rm else roundf(sin(t * TAU / 1.2) * 0.6 + 0.4))
		for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var c: Vector2 = p + s * q
			ci.draw_line(c, c - Vector2(s.x * 4.0, 0), C_YEL, 1.0)
			ci.draw_line(c, c - Vector2(0, s.y * 4.0), C_YEL, 1.0)
	elif id == hover:
		ci.draw_arc(p, r + 3, 0.0, TAU, 40, Color(C_WHITE, 0.4), 1.0)


# ---------------------------------------------------------------- 文字 / 外框（设计单位）
func _draw_view() -> void:
	var ci := view
	buttons.clear()
	if lay.is_empty():
		return
	_draw_labels(ci)
	if style == "tree":
		_draw_groups(ci)
		_draw_ruler(ci)
	_draw_chrome(ci)
	_draw_card(ci)


func _txt(ci: CanvasItem, p: Vector2, s: String, sz: int, col: Color, anchor := "ma", bold := false) -> float:
	# 深色描边：压在根和背景上也看得清
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := p.x - (w / 2.0 if anchor[0] == "m" else (w if anchor[0] == "r" else 0.0))
	var y := p.y + font.get_ascent(sz)
	ci.draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0.02, 0.05, 0.08, 0.85))
	ci.draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	if bold:
		ci.draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 1, col)
	return w


func _effect_line(id: String) -> String:
	var s := str(Meta.nodes()[id].desc).get_slice("。", 0)
	return s if s.length() <= 16 else s.substr(0, 15) + "…"


func _draw_labels(ci: CanvasItem) -> void:
	var sid := _sel_id()
	var c := TUI.ctx(ci)
	for i in chains.size():
		var g := _grow(i)
		var ch: Array = chains[i]
		var p := _pre(ch[0])
		var lim := int(g * (geo[p].size() - 1))
		var spec: Array = lay.get("roots", {}).get(p, [])
		var side: String = str(spec[7]) if spec.size() > 7 else "b"
		for k in ch.size():
			var id: String = ch[k]
			if ni[id] > lim:
				continue
			var d := _to_view(pos[id])
			if d.x < -80.0 or d.x > vs.x + 80.0 or d.y < -40.0 or d.y > vs.y + 40.0:
				continue
			var key := _is_key(id)
			var r := (rk if key else rn) * pxu
			var off := 16.0 if key else 6.0
			var st := _state(id)
			var col := T_ON if st == "on" or st == "ok" else (T_POOR if st == "poor" else T_LOCK)
			var nm := str(Meta.nodes()[id].name)
			# 标签方向（布局 roots 第 8 项）：b 下 / r 右 / l 左 / z 左右交错
			var sd := side
			if sd == "z":
				sd = "r" if k % 2 == 0 else "l"
			var lh := 38.0 if style == "sea" else 18.0
			var anchor := "ma"
			var np := Vector2(d.x, d.y + r + off)
			if sd == "r":
				anchor = "la"
				np = Vector2(d.x + r + off + 6.0, d.y - lh / 2.0)
			elif sd == "l":
				anchor = "ra"
				np = Vector2(d.x - r - off - 6.0, d.y - lh / 2.0)
			# 标签底板：根从节点往下延伸，会穿过名字；垫一块半透明暗底，线从底板后面过
			var pw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			if style == "sea":
				pw = maxf(pw, font.get_string_size(_effect_line(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
			pw += 12.0
			var px0 := np.x - pw / 2.0 if anchor == "ma" else (np.x - 6.0 if anchor == "la" else np.x - pw + 6.0)
			ci.draw_rect(Rect2(px0, np.y - 2.0, pw, lh + 2.0), Color(0.02, 0.05, 0.09, 0.72))
			if id == sid:   # 选中：黄色名牌
				var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22.0
				var x0 := np.x - w / 2.0 if anchor == "ma" else (np.x - 8.0 if anchor == "la" else np.x - w + 8.0)
				HS.para(ci, Rect2(x0, np.y - 2.0, w, 21.0), HS.YEL)
				UI.text_at(ci, font, Vector2(x0 + w / 2.0, np.y + 8.5), nm, 14, HS.INK, "mm", true)
			else:
				_txt(ci, np, nm, 13, col, anchor)
			if style == "sea":
				_txt(ci, np + Vector2(0, 20.0), _effect_line(id), 11, T_SUB if st != "lock" else T_LOCK, anchor)
			# 消耗：右下角像素数字（已塑造不写）
			if st != "on":
				var cp := d + Vector2(r * 0.78, r * 0.62)
				var s := str(int(Meta.nodes()[id].cost))
				var tw := TUI.ptext_w(c, s, 1.5)
				ci.draw_rect(Rect2(cp.x - 3.0, cp.y - 8.0, tw + 15.0, 16.0), Color(0.02, 0.04, 0.07, 0.9))
				TUI.pdiamond(ci, c, cp + Vector2(2, 0), 2, TUI.cell(c, 1.0), C_YEL if st == "ok" else col)
				TUI.ptext(ci, c, cp + Vector2(8, 0), s, 1.5, C_YEL if st == "ok" else col)


## 主根旁的组名小标（深蓝之树）
func _draw_groups(ci: CanvasItem) -> void:
	var c := TUI.ctx(ci)
	var a := _grow_main()
	var spots := {"L": [0.55, Vector2(0, -26)], "C": [0.55, Vector2(-34, 0)], "R1": [0.48, Vector2(18, -6)], "R2": [0.52, Vector2(0, -26)]}
	for m in mains:
		var g: int = MAIN_GROUP.get(m, 0)
		var sp: Array = spots.get(m, [0.5, Vector2.ZERO])
		var pts: PackedVector2Array = mains[m]
		var d := _to_view(pts[int(float(sp[0]) * (pts.size() - 1))]) + (sp[1] as Vector2)
		var col: Color = GROUPS[g][2]
		UI.diamond(ci, d + Vector2(-6, 0), 3.5, UI.fa(col, a))
		var w := _txt(ci, d + Vector2(2, -8), GROUPS[g][0], 12, UI.fa(col, a), "la")
		TUI.ptext(ci, c, d + Vector2(8 + w, 0), GROUPS[g][1], 1.0, UI.fa(T_SUB, 0.8 * a))


## 左缘深度刻度尺（-0000M，每 60 一道长刻度；到详情卡上沿为止）
func _draw_ruler(ci: CanvasItem) -> void:
	var c := TUI.ctx(ci)
	var x := 14.0
	var y0 := 120.0
	var y1 := vs.y - 316.0
	ci.draw_line(Vector2(x, y0), Vector2(x, y1), Color(T_SUB, 0.35), 1.0)
	var y := y0
	while y <= y1:
		var wy := y + cam_px.y
		var big := int(round(wy)) % 60 == 0
		ci.draw_line(Vector2(x, y), Vector2(x + (8.0 if big else 4.0), y), Color(T_SUB, 0.5 if big else 0.3), 1.0)
		if big:
			TUI.ptext(ci, c, Vector2(x + 12.0, y), "-%04dM" % int(wy / 6.0 + 20.0), 1.0, Color(T_SUB, 0.55))
		y += 12.0


func _draw_chrome(ci: CanvasItem) -> void:
	var mouse := view.get_local_mouse_position()
	var done := 0
	for id in Cfg.meta_shape:
		if Cfg.meta_shape[id]:
			done += 1
	if style == "sea":
		_draw_title_orig(ci, done)
	else:
		HS.topbar(ci, font, vs, ["COGNITION", "SHAPING"], "认知塑造", 1.0, "", "")
		# 生机细胞 + 已塑造
		var rx := vs.x - 470.0
		ci.draw_texture_rect(Icons.tex("cell"), Rect2(rx, 17, 22, 22), false, C_SAP)
		UI.text_at(ci, font, Vector2(rx + 30, 10), "生机细胞", 11, T_SUB)
		var nw := UI.text_at(ci, font, Vector2(rx + 30, 24), str(Meta.available()), 24, UI.TEXT, "la", true)
		UI.text_at(ci, font, Vector2(rx + 38 + nw, 34), "/ 累计 %d" % Meta.earned_total(), 12, T_SUB)
		UI.text_at(ci, font, Vector2(rx + 186, 10), "已塑造", 11, T_SUB)
		UI.text_at(ci, font, Vector2(rx + 186, 26), "%d / %d" % [done, Meta.nodes().size()], 20, UI.TEXT, "la", true)
	# 返回
	var back := Rect2(vs.x - 160, 12, 140, 36)
	HS.para(ci, back, Color(1, 1, 1, 0.12) if back.has_point(mouse) else Color(0, 0, 0, 0), Color(1, 1, 1, 0.8))
	UI.text_at(ci, font, back.get_center(), Pad.hint("返回  Esc", "返回  Ⓑ", "返回"), 15, UI.TEXT, "mm", true)
	buttons.append([back, "back"])
	# 推荐 / 全部重置
	var bw := 168.0
	var r2 := Rect2(vs.x - 20 - bw, 74, bw, 34)
	var r1 := Rect2(r2.position.x - 14 - 116, 74, 116, 34)
	var tch: bool = Pad.touch
	HS.ghost_btn(ci, font, r1, "推荐", "" if tch else "R", 0.86)
	if reset_armed:
		HS.para(ci, r2, UI.fa(UI.RED, 0.85))
	HS.ghost_btn(ci, font, r2, "再按确认重置" if reset_armed else "全部重置", "" if tch else "X", 0.86)
	buttons.append([r1, "rec"])
	buttons.append([r2, "reset"])
	# 操作提示（顶栏下左）
	var pan := _pannable()
	var hint: String = ("点节点选中 · 再点塑造" + (" · 拖动平移" if pan else "")) if tch 		else Pad.hint("方向键 选择  ·  Enter 塑造" + ("  ·  拖动 平移" if pan else ""), "十字键 选择  ·  Ⓐ 塑造", "")
	UI.text_at(ci, font, Vector2(24, 84), hint, 12, UI.fa(T_SUB, 0.85))


## 原作式标题（夜海）：顶部一条渐隐暗带，居中「徽记 + 认知塑造 + 英文小字」，右侧「合计生机细胞」大字 + 已塑造
func _draw_title_orig(ci: CanvasItem, done: int) -> void:
	for i in 16:   # 画布往下滚时，滚进标题区的根和节点在这条暗带里淡掉
		ci.draw_rect(Rect2(0, i * 8.0, vs.x, 8.0), Color(0.01, 0.02, 0.04, 0.92 * pow(1.0 - i / 16.0, 0.7)))
	var cx := vs.x * 0.5
	var ex := cx - 150.0
	ci.draw_arc(Vector2(ex, 42), 22.0, 0.0, TAU, 48, Color(C_WHITE, 0.9), 2.0, true)
	ci.draw_arc(Vector2(ex, 42), 15.0, deg_to_rad(200), deg_to_rad(470), 40, Color(C_WHITE, 0.7), 2.0, true)
	ci.draw_texture_rect(Icons.tex("cell"), Rect2(ex - 11, 31, 22, 22), false, C_WHITE)
	UI.text_at(ci, font, Vector2(ex + 34, 40), "认知塑造", 32, C_WHITE, "lm", true)
	HS.spaced(ci, font, Vector2(ex + 36, 70), "COGNITION  //  SHAPING", 9, T_SUB, 3.0)
	var rx := cx + 60.0
	ci.draw_line(Vector2(rx - 22, 20), Vector2(rx - 22, 66), Color(T_SUB, 0.4), 1.0)
	UI.text_at(ci, font, Vector2(rx, 16), "合计生机细胞", 12, T_SUB)
	var nw := UI.text_at(ci, font, Vector2(rx, 30), str(Meta.available()), 28, C_SAP, "la", true)
	UI.text_at(ci, font, Vector2(rx + nw + 8, 44), "/ %d" % Meta.earned_total(), 14, T_SUB)
	UI.text_at(ci, font, Vector2(rx + 150, 16), "已塑造", 12, T_SUB)
	UI.text_at(ci, font, Vector2(rx + 150, 32), "%d / %d" % [done, Meta.nodes().size()], 22, C_WHITE, "la", true)


## 详情卡。桌面：左下浅色档案卡（左黄条、右上切角、「NODE // 认知节点」、组色标签、名称、效果大字、质变、本线进度、状态、塑造按钮），
## 高度随内容、底边对齐；手机：贴底一条（名称 + 效果 ｜ 本线进度 + 状态 ｜ 塑造按钮），把上面的根让出来
func _draw_card(ci: CanvasItem) -> void:
	var id := _sel_id()
	if id == "":
		return
	var slide := 1.0 if Cfg.reduce_motion else UI.ease_out(clampf((t - open_t0 - 0.15) / 0.3, 0.0, 1.0))
	if Cfg.phone_ui():
		_draw_sheet(ci, id, slide)
		return
	var w := 326.0
	var bh := _card_body(ci, Vector2(0, 0), w, id, false)
	var h := bh + 62.0
	var r := Rect2(24.0 - (1.0 - slide) * 60.0, vs.y - 20.0 - h, w, h)
	var cut := 22.0
	HS.fill(ci, PackedVector2Array([r.position + Vector2(6, 6), Vector2(r.end.x - cut + 6, r.position.y + 6), Vector2(r.end.x + 6, r.position.y + cut + 6),
		r.end + Vector2(6, 6), Vector2(r.position.x + 6, r.end.y + 6)]), Color(0, 0, 0, 0.35))
	HS.fill(ci, PackedVector2Array([r.position, Vector2(r.end.x - cut, r.position.y), Vector2(r.end.x, r.position.y + cut), r.end, Vector2(r.position.x, r.end.y)]), HS.LIGHT)
	ci.draw_rect(Rect2(r.position, Vector2(5, r.size.y)), HS.YEL)
	_card_body(ci, r.position, w, id, true)
	var br := Rect2(r.position.x + 18.0, r.end.y - 50.0, w - 40.0, 36.0)
	_card_button(ci, br, id)


## 卡片正文（不含按钮）：draw = false 时只量高度。返回正文高度
func _card_body(ci: CanvasItem, o: Vector2, w: float, id: String, draw: bool) -> float:
	var nd: Dictionary = Meta.nodes()[id]
	var st := _state(id)
	var ch: Array = chains[clampi(sel.x, 0, chains.size() - 1)]
	var g: int = GROUP_OF.get(_pre(id), 0)
	var x := o.x + 22.0
	var y := o.y + 16.0
	var tw := w - 44.0
	if draw:
		HS.spaced(ci, font, Vector2(x, y + 10), "NODE  //  认知节点", 10, HS.INK2, 2.0)
		var gt: String = GROUPS[g][0]
		var gw := UI.cwidth(font, gt, 12) + 18.0
		var gr := Rect2(o.x + w - 88.0 - gw, y - 2.0, gw, 20.0)
		HS.para(ci, gr, HS.INK)
		UI.text_at(ci, font, gr.get_center(), gt, 12, GROUPS[g][2], "mm", true)
		UI.text_at(ci, font, Vector2(o.x + w - 26.0, y + 8.0), "%d / %d" % [ch.find(id) + 1, ch.size()], 14, HS.INK2, "rm", true)
	y += 26.0
	if draw:
		UI.text_at(ci, font, Vector2(x - 2.0, y), str(nd.name), 26, HS.INK, "la", true)
	y += 40.0
	# 效果：「名称 +数值」拆成标签 + 大字；其余整句
	var desc := str(nd.desc)
	var head := desc.get_slice("。", 0)
	var rest := desc.substr(head.length() + 1) if desc.contains("。") else ""
	if _re_head == null:
		_re_head = RegEx.create_from_string("^(.*?)\\s*([+\\-][0-9.]+%?)$")
	var m := _re_head.search(head)
	if m != null:
		if draw:
			UI.text_at(ci, font, Vector2(x, y), m.get_string(1), 14, HS.INK)
			UI.text_at(ci, font, Vector2(x - 2.0, y + 16.0), m.get_string(2), 34, HS.RIB, "la", true)
		y += 58.0
	else:
		y = _para(ci, Vector2(x, y), head, 15, HS.INK, tw, draw) + 4.0
	# 质变：黄标签（规则短名）+ 规则正文
	if RULE_TAG.has(id):
		var tg: String = RULE_TAG[id]
		var tgw := UI.cwidth(font, tg, int(14 * 0.72)) + 22.0 * 0.72
		if draw:
			HS.tag(ci, font, Vector2(x, y), tg, 0.72, HS.YEL)
		if rest != "":
			y = maxf(_para(ci, Vector2(x + tgw + 8.0, y + 2.0), rest, 12, HS.INK, tw - tgw - 8.0, draw), y + 22.0) + 6.0
		else:
			if draw:
				UI.text_at(ci, font, Vector2(x + tgw + 8.0, y + 3.0), "质变节点", 12, HS.INK2)
			y += 28.0
	# 本线：小方格（已塑造实心、可塑造蓝框、其余灰框）+ 合计
	if draw:
		ci.draw_line(Vector2(x, y + 2.0), Vector2(o.x + w - 22.0, y + 2.0), UI.fa(HS.MUTE, 0.6), 1.0)
	y += 12.0
	var sm := _chain_sum(ch)
	if draw:
		for q in ch.size():
			var cst := _state(ch[q])
			var box := Rect2(x + q * 15.0, y + 1.0, 10.0, 10.0)
			if cst == "on":
				ci.draw_rect(box, HS.INK)
			else:
				ci.draw_rect(box, HS.RIB if cst == "ok" else HS.MUTE, false, 1.5)
		var sx := x + ch.size() * 15.0 + 6.0
		var s2 := ("本线合计  " + sm) if sm != "" else "本线尚未塑造"
		while s2.length() > 4 and UI.cwidth(font, s2, 12) > o.x + w - 22.0 - sx:
			s2 = s2.substr(0, s2.length() - 2) + "…"
		UI.text_at(ci, font, Vector2(sx, y - 2.0), s2, 12, HS.INK2)
	y += 22.0
	if draw:
		UI.text_at(ci, font, Vector2(x, y), _state_line(id), 13, HS.RIB if st == "ok" else HS.INK2)
	y += 20.0
	return y - o.y


func _state_line(id: String) -> String:
	var nd: Dictionary = Meta.nodes()[id]
	match _state(id):
		"on":
			return "已塑造：之后的每次探索生效"
		"ok":
			return "塑造需要 %d 生机细胞" % int(nd.cost)
		"poor":
			return "需要 %d 生机细胞，余额 %d" % [int(nd.cost), Meta.available()]
	if nd.has("req") and not Cfg.meta_shape.get(str(nd.req), false):
		return "先塑造「%s」" % str(Meta.nodes()[str(nd.req)].name)
	return "已塑造总量达到 %d 后开放（现为 %d）" % [int(nd.get("need", 0)), Meta.spent(Cfg.meta_shape)]


func _card_button(ci: CanvasItem, br: Rect2, id: String) -> void:
	var st := _state(id)
	if st == "ok":
		HS.main_btn(ci, font, br, "塑造", "" if Pad.touch else "Enter", 0.86)
	else:
		HS.para(ci, br, HS.LIGHT2, HS.MUTE)
		UI.text_at(ci, font, br.get_center(), "已塑造" if st == "on" else ("生机细胞不足" if st == "poor" else "尚未解锁"), 16, HS.INK2, "mm", true)
	buttons.append([br, "buy"])


const SHEET_H := 92.0


## 手机：贴底一条
func _draw_sheet(ci: CanvasItem, id: String, slide: float) -> void:
	var nd: Dictionary = Meta.nodes()[id]
	var st := _state(id)
	var ch: Array = chains[clampi(sel.x, 0, chains.size() - 1)]
	var g: int = GROUP_OF.get(_pre(id), 0)
	var r := Rect2(12.0, vs.y - 12.0 - SHEET_H + (1.0 - slide) * 40.0, vs.x - 24.0, SHEET_H)
	HS.fill(ci, PackedVector2Array([r.position, Vector2(r.end.x - 18.0, r.position.y), Vector2(r.end.x, r.position.y + 18.0), r.end, Vector2(r.position.x, r.end.y)]), HS.LIGHT)
	ci.draw_rect(Rect2(r.position, Vector2(5, r.size.y)), HS.YEL)
	var x := r.position.x + 22.0
	var gt: String = GROUPS[g][0]
	var gw := UI.cwidth(font, gt, 12) + 18.0
	HS.para(ci, Rect2(x, r.position.y + 12.0, gw, 20.0), HS.INK)
	UI.text_at(ci, font, Vector2(x + gw / 2.0, r.position.y + 22.0), gt, 12, GROUPS[g][2], "mm", true)
	UI.text_at(ci, font, Vector2(x + gw + 10.0, r.position.y + 8.0), str(nd.name), 22, HS.INK, "la", true)
	var col2 := r.position.x + r.size.x * 0.46
	var head := str(nd.desc).get_slice("。", 0)
	while head.length() > 4 and UI.cwidth(font, head, 14) > col2 - x - 16.0:
		head = head.substr(0, head.length() - 2) + "…"
	UI.text_at(ci, font, Vector2(x, r.position.y + 48.0), head, 14, HS.INK)
	for q in ch.size():
		var cst := _state(ch[q])
		var box := Rect2(col2 + q * 15.0, r.position.y + 18.0, 10.0, 10.0)
		if cst == "on":
			ci.draw_rect(box, HS.INK)
		else:
			ci.draw_rect(box, HS.RIB if cst == "ok" else HS.MUTE, false, 1.5)
	UI.text_at(ci, font, Vector2(col2 + ch.size() * 15.0 + 8.0, r.position.y + 14.0), "%d / %d" % [ch.find(id) + 1, ch.size()], 13, HS.INK2, "la", true)
	UI.text_at(ci, font, Vector2(col2, r.position.y + 48.0), _state_line(id), 14, HS.RIB if st == "ok" else HS.INK2)
	_card_button(ci, Rect2(r.end.x - 232.0, r.position.y + 22.0, 210.0, 46.0), id)


## 本线已塑造部分的合计：同前缀数值相加（「全体伤害 +4%」×3 → 「全体伤害 +12%」）；纯规则的线列规则名
func _chain_sum(ch: Array) -> String:
	if _re_sum == null:
		_re_sum = RegEx.create_from_string("^(.*?)([+\\-])([0-9.]+)(%?)(.*)$")
	var acc := {}
	var order: Array = []
	var rules: Array = []
	for id in ch:
		if not Cfg.meta_shape.get(id, false):
			continue
		var head := str(Meta.nodes()[id].desc).get_slice("。", 0).get_slice("（", 0)
		var m := _re_sum.search(head)
		if m == null:
			if RULE_TAG.has(id):
				rules.append(RULE_TAG[id])
			continue
		var key := [m.get_string(1), m.get_string(2), m.get_string(4), m.get_string(5)]
		var ks := "|".join(key)
		if not acc.has(ks):
			acc[ks] = [key, 0.0]
			order.append(ks)
		acc[ks][1] += float(m.get_string(3))
	var parts: Array = []
	for ks in order:
		var key: Array = acc[ks][0]
		var v: float = acc[ks][1]
		var vs_ := ("%.2f" % v).rstrip("0").rstrip(".")
		parts.append("%s%s%s%s%s" % [key[0], key[1], vs_, key[2], key[3]])
	parts.append_array(rules)
	return "，".join(parts)


## 按宽度折行（逐字），返回末行底 y；draw = false 时只量
func _para(ci: CanvasItem, p: Vector2, s: String, sz: int, col: Color, w: float, draw := true) -> float:
	var line := ""
	var y := p.y
	for ch in s:
		if UI.cwidth(font, line + ch, sz) > w:
			if draw:
				UI.text_at(ci, font, Vector2(p.x, y), line, sz, col)
			y += sz + 5.0
			line = ""
		line += ch
	if line != "":
		if draw:
			UI.text_at(ci, font, Vector2(p.x, y), line, sz, col)
		y += sz + 5.0
	return y
