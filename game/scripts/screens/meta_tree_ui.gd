extends Control
## 局外 · 认知塑造页（docs/109 §4；10-25 重做，art/archive/incoming_1028/meta_ui_1025/）。只改 Cfg.meta_*，规则与数据在 core/meta.gd / data/meta_tree.json。
## 版式（10-26 用户：「每条线一个自绘星座，形状对应线的含义，按 Ⅰ→Ⅴ 一笔连下来，只写线名，不用地球星座名」）：从海底仰望星空——
## 每条认知线是一个自绘星座，节点是星，按 Ⅰ→… 一笔连下来（中间可以拐过点缀星把形状勾圆，末阶之后收笔闭合图形）：
## 攻击性 = 箭、生存本能 = 心、生命感悟 = 心跳脉搏、自我保护 = 盾、领导欲 = 王冠、好奇心 = 眼睛、多程信息处理那条 = 闪电、收藏癖 = 宝石、
## 交涉 = 天平、危机感 = 警示三角。星座旁只写线名，下附已塑造 / 总数；整条线点满时收笔和辅助线亮起，图形完整。
## 布局在 data/meta_roots.json（art/archive/incoming_1028/meta_ui_1025/layout.py 生成：形状、位置、星名 / 线名自动选方位避开连线）。
## 背景：海面淡光 + 满屏闪烁的发光微粒 + 一条星云带（meta_bg.gdshader），微粒缓缓上浮。
## 像素层（背景、星座连线、星）画进低分辨率 SubViewport（1 格 = 2 设计单位，最近邻放大）；文字、外框、详情卡画在 view（设计单位）里保持清晰。
## 三种状态：已塑造 = 亮星（白芯 + 十字星芒 + 青光），两头都亮的星座连线点亮、有光点流动；可塑造 = 黄白星闪烁 + 黄色点环转动；
## 余额不够 = 灰星；未解锁 = 暗星。质变节点 = 大亮星（八道星芒 + 伴星成团）。招牌动效：塑造时一道光从上一颗亮星沿这一笔流进新星（0.55 秒）→ 外扩环（0.45 秒）。
## 操作：方向键 / 手柄十字键按方向找最近的节点；点节点选中、再点 / Enter / 详情卡「塑造」塑造；R 推荐（按推荐顺序把余额点完）；X 两次全部重置（免费退回）；
## Esc 返回；画布比屏幕大时拖动 / 滚轮（Shift 横向）平移，换选中后镜头跟随。减少动态效果：不生长、不呼吸、无光点流动，镜头直接到位。
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
const GROUP_OF := {"shop": 0, "gold": 0, "pick": 0, "xp": 1, "disp": 1, "atk": 2, "sh": 2, "hp": 3, "def": 3, "reg": 3, "dodge": 3}
const GROUPS := [["探索", "EXPLORE", Color8(255, 196, 70)], ["成长", "GROWTH", Color8(168, 150, 255)], ["战斗", "COMBAT", Color8(255, 112, 98)],
	["生存", "SURVIVAL", Color8(92, 214, 152)]]

const PX_DESIGN := 2.0        # 像素格的目标大小（设计单位）；实际 pxu 按屏幕取整（见 _fit）
const RN_DESIGN := 16.0       # 普通节点半径（设计单位）
const RK_DESIGN := 22.0       # 质变节点半径
const LIT_DUR := 1.0
const LIT_GROW := 0.55

## 像素层颜色
const C_LINE := Color8(170, 196, 228)    # 星座连线 / 标记圈
const C_SAP := Color8(118, 238, 255)
const C_DISC := Color8(10, 15, 22)
const C_WHITE := Color8(238, 243, 246)
const C_POOR := Color8(138, 150, 163)
const C_LOCK := Color8(70, 82, 96)
const C_YEL := Color8(255, 206, 0)
## 文字颜色（view 层）
const T_ON := Color8(236, 241, 245)
const T_POOR := Color8(160, 172, 184)
const T_LOCK := Color8(104, 116, 130)
const T_SUB := Color8(150, 164, 178)

var font: Font
var vp: SubViewport           # 像素层
var bgrect: ColorRect
var bgmat: ShaderMaterial
var wn: Node2D                # 像素层里画星座连线 / 星（像素格坐标）
var under: Control            # 放像素层画面（设计单位，在 view 下面）
var pix: TextureRect
var view: Control             # 文字 / 外框 / 详情卡（设计单位）
var lay: Dictionary = {}
var chains: Array = []        # 每条链的节点 id（从第一节往末节）
var pos := {}                 # 节点 id → 世界坐标（设计单位）
var ord := {}                 # 节点 id → (第几条线, 第几颗)（开场按这个亮出）
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
var card_hide := false        # 详情卡收起（10-27 用户：左下角的卡要能点掉，被挡住的节点才看得见、点得到）：卡外「收起」/ 左下「详情」标签 / Z（手柄 Ⓧ）切换
var fit_all := false          # --metafit（开发截图）：整棵树缩进一屏、不画详情卡，做「原作 | 本作」对照用

static var _re_head: RegEx
static var _re_sum: RegEx


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = load("res://fonts/ui.ttf")
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
	fit_all = Cfg.dev_args().has("--metafit")
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


func _build() -> void:
	chains.clear()
	pos.clear()
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/meta_roots.json"))
	lay = j.get("scene", {}) if j is Dictionary else {}
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
	ord.clear()
	var st: Dictionary = lay.get("stars", {})
	var extra := 0
	for i in chains.size():
		for k in chains[i].size():
			var id: String = chains[i][k]
			ord[id] = Vector2i(i, k)
			if st.has(id):
				pos[id] = _v(st[id])
			else:   # 布局里没有的新节点：先排在右下角（数据加节点后跑 layout.py 补上）
				pos[id] = _world() - Vector2(60.0 + extra * 70.0, 60.0)
				extra += 1


func _pts(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in a:
		out.append(_v(q))
	return out


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
	if fit_all and not lay.is_empty():
		h = maxf(_world().y + 90.0, _world().x * size.y / size.x)
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
		return Rect2(40.0, 120.0, vs.x - 80.0, vs.y - 120.0 - (64.0 if card_hide else SHEET_H + 80.0))
	return Rect2(80.0 if card_hide else 380.0, 130.0, vs.x - (120.0 if card_hide else 420.0), vs.y - 196.0)


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
		lo.y = -60.0
		hi.y = w.y - vs.y + 30.0 + extra
	return Rect2(lo, hi - lo)


## 镜头目标：打开时居中；之后换选中只挪到让选中节点进安全区为止（不乱晃）
func _cam_goal() -> Vector2:
	if fit_all:
		return _cam_center()
	var c := cam
	if follow:
		var sp: Vector2 = pos.get(_sel_id(), _world() / 2.0)
		var sf := _safe()
		c.x = clampf(c.x, sp.x - sf.end.x, sp.x - sf.position.x)
		c.y = clampf(c.y, sp.y - sf.end.y, sp.y - sf.position.y)
	return _clamp_cam(c)


## 打开时的镜头：世界居中；比视口大时让顶部中心落在顶部标题下方、水平居中
func _cam_center() -> Vector2:
	var c := (_world() - vs) / 2.0
	var cr := _v(lay.get("crown", [556, 170]))
	if _world().y > vs.y:
		c.y = cr.y - 130.0   # 最上面的星座刚好在顶栏下面
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
	return "ok" if Meta.can_buy(shape, id, Meta.budget()) else "poor"


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
		"card":
			card_hide = not card_hide
			follow = true
			Sfx.play("ui_move", -6.0)


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
			var dw := -60.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0
			if event.shift_pressed:
				cam.x += dw
			else:
				cam.y += dw
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
			KEY_Z:
				_act("card")
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


## 开场：星座一颗接一颗亮出来（每条线晚 0.04 秒、每颗晚 0.07 秒），连线从上一颗往下一颗画过去；减少动态效果直接到位
func _appear(id: String) -> float:
	if Cfg.reduce_motion:
		return 1.0
	var o: Vector2i = ord.get(id, Vector2i.ZERO)
	return UI.ease_out(clampf((t - open_t0 - 0.1 - 0.04 * o.x - 0.07 * o.y) / 0.25, 0.0, 1.0))


func _draw_world() -> void:
	var ci := wn
	if lay.is_empty():
		return
	_draw_motes(ci)
	_draw_shapes(ci)
	var sid := _sel_id()
	for id in pos:
		if _appear(id) > 0.0:
			_draw_star(ci, id, id == sid)


## 每条线的星座（布局 shapes）：一笔从 Ⅰ 连到末阶，中间可以经过点缀星把形状勾圆；末阶之后的收笔把图形闭合。
## 一笔按节点切成段：两头都已塑造 = 亮线（白芯 + 青光 + 光点流动）；一头已塑造 = 点线；其余 = 很淡的细线。
## 收笔和辅助线（天平的立柱、警示三角的「!」…）平时很淡，整条线点满才亮起来。开场每段跟着它通向的那颗星一起画出来。
## 塑造演出：一道光从上一颗亮星沿这一段流进新星
func _draw_shapes(ci: CanvasItem) -> void:
	var lit_f := (t - lit_t0) / LIT_DUR if lit_id != "" else 2.0
	var shapes: Dictionary = lay.get("shapes", {})
	for ch in chains:
		var pre := _pre(ch[0])
		if not shapes.has(pre):
			continue
		var sh: Dictionary = shapes[pre]
		var full := true
		for id in ch:
			if not Cfg.meta_shape.get(id, false):
				full = false
		var g_end := _appear(ch[-1])
		# 辅助线
		for e in sh.get("extra", []):
			var a := _a(Vector2(float(e[0]), float(e[1])))
			var b := _a(Vector2(float(e[2]), float(e[3])))
			ci.draw_line(a, b, Color(C_SAP if full else C_LINE, (0.5 if full else 0.14) * g_end), 1.0)
		# 一笔：顶点 [世界坐标, 节点 id（点缀星 = ""）, 是否第一次到这颗星]
		var vs_: Array = []
		var seen := {}
		for e in sh.get("stroke", []):
			if str(e[0]) == "n":
				var id := str(e[1])
				vs_.append([pos.get(id, Vector2.ZERO), id, not seen.has(id)])
				seen[id] = true
			else:
				vs_.append([Vector2(float(e[1]), float(e[2])), "", false])
		var flow: Array = []   # 演出这一段的顶点
		for i in vs_.size() - 1:
			var pa := ""   # 往前最近的节点
			for j in range(i, -1, -1):
				if vs_[j][1] != "":
					pa = vs_[j][1]
					break
			var nb := ""   # 往后第一颗第一次到的节点（没有 = 收笔）
			for j in range(i + 1, vs_.size()):
				if vs_[j][1] != "":
					if vs_[j][2]:
						nb = vs_[j][1]
					break
			var g := _appear(nb) if nb != "" else g_end
			if g <= 0.0:
				continue
			var a: Vector2 = _a(vs_[i][0])
			var b: Vector2 = _a(vs_[i + 1][0])
			var dv := (b - a).normalized()
			var p0 := a + dv * ((_star_r(vs_[i][1]) + 3.0) if vs_[i][1] != "" else 2.0)
			var p1 := b - dv * ((_star_r(vs_[i + 1][1]) + 3.0) if vs_[i + 1][1] != "" else 2.0)
			if (p1 - p0).dot(dv) <= 0.0:
				continue
			p1 = p0.lerp(p1, g)
			var on_a := pa != "" and _state(pa) == "on"
			var on_b := nb != "" and _state(nb) == "on"
			var anim := nb != "" and nb == lit_id and lit_f < LIT_GROW and on_a
			if anim:
				if flow.is_empty():
					flow.append(p0)
				flow.append(p1)
			if (nb != "" and on_a and on_b and not anim) or (nb == "" and full):
				ci.draw_line(p0, p1, Color(C_SAP, 0.16), 3.0)
				ci.draw_line(p0, p1, Color(C_WHITE, 0.9), 1.0)
				if not Cfg.reduce_motion:
					var n := int(p0.distance_to(p1))
					var off := int(t * 10.0) % 12
					for q in range(off, n, 12):
						ci.draw_rect(Rect2((p0 + dv * q).floor(), Vector2(1, 1)), C_SAP)
			elif nb != "" and (on_a or on_b or anim):
				var n := int(p0.distance_to(p1))
				for q in range(0, n, 3):
					ci.draw_rect(Rect2((p0 + dv * q).floor(), Vector2(1, 1)), Color(C_LINE, 0.6))
			else:
				ci.draw_line(p0, p1, Color(C_LINE, 0.22 if nb != "" else 0.13), 1.0)
		if flow.size() >= 2:   # 光沿这一段（可能拐过点缀星）流进新星
			var total := 0.0
			for i in flow.size() - 1:
				total += (flow[i] as Vector2).distance_to(flow[i + 1])
			var left := total * UI.ease_out(clampf(lit_f / LIT_GROW, 0.0, 1.0))
			var e: Vector2 = flow[0]
			for i in flow.size() - 1:
				var s0: Vector2 = flow[i]
				var s1: Vector2 = flow[i + 1]
				var l := s0.distance_to(s1)
				e = s0.lerp(s1, clampf(left / maxf(l, 0.01), 0.0, 1.0))
				ci.draw_line(s0, e, Color(C_SAP, 0.35), 3.0)
				ci.draw_line(s0, e, Color.WHITE, 1.0)
				left -= l
				if left <= 0.0:
					break
			ci.draw_circle(e, 3.0, Color(1, 1, 1, 0.35))
			ci.draw_rect(Rect2(e - Vector2(1, 1), Vector2(3, 3)), Color.WHITE)
		# 点缀星：一笔里拐弯的点 + dots；整条线点满时变亮
		var i := 0
		var pts: Array = []
		for e in sh.get("stroke", []):
			if str(e[0]) == "d":
				pts.append(Vector2(float(e[1]), float(e[2])))
		for d in sh.get("dots", []):
			pts.append(_v(d))
		for q in pts:
			var p := _a(q)
			var a := (0.9 if full else (0.55 if Cfg.reduce_motion else 0.45 + 0.2 * sin(t * 1.3 + i * 2.1))) * g_end
			var col := C_SAP if full else C_LINE
			ci.draw_rect(Rect2(p, Vector2(1, 1)), Color(col, a))
			ci.draw_rect(Rect2(p - Vector2(1, 0), Vector2(3, 1)), Color(col, a * 0.35))
			ci.draw_rect(Rect2(p - Vector2(0, 1), Vector2(1, 3)), Color(col, a * 0.35))
			i += 1


## 漂浮的发光微粒：慢慢往上浮、左右轻摆
func _draw_motes(ci: CanvasItem) -> void:
	var w := _world()
	for m in motes:
		var u: Vector2 = m[0]
		var y := fposmod(u.y * w.y - (0.0 if Cfg.reduce_motion else t * float(m[1])), w.y)
		var x := u.x * w.x + (0.0 if Cfg.reduce_motion else sin(t * 0.4 + float(m[2])) * 6.0)
		var a := 0.35 + 0.25 * sin(t * 0.8 + float(m[2]))
		ci.draw_rect(Rect2(_a(Vector2(x, y)), Vector2(1, 1)), Color(C_SAP if m[3] else C_LINE, a * 0.7))


## 星的点击 / 连线留空半径（像素格）
func _star_r(id: String) -> float:
	return (5.0 if _is_key(id) else 3.0)


## 星：已塑造 = 亮星（白芯 + 十字星芒 + 青光，慢慢闪）；可塑造 = 黄白星，星芒一伸一缩地闪 + 黄色点环转动；
## 余额不够 = 灰星；未解锁 = 暗星（一点）。质变节点 = 大亮星：八道星芒、外圈细环，周围三四颗小伴星（星团）。
## 外圈一道很淡的细环标出点击范围（星图上的标记圈）。塑造落定：外扩环；选中：四角黄角标
func _draw_star(ci: CanvasItem, id: String, selected: bool) -> void:
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
	var g := _appear(id)
	var ph := float(id.hash() % 100) / 100.0 * TAU
	var tw := 1.0 if rm else 0.8 + 0.2 * sin(t * 1.7 + ph)
	var core := C_WHITE
	var arm := 0.0           # 星芒长度（像素格）
	var halo := 0.0
	match st:
		"on":
			arm = (9.0 if key else 6.0) * tw
			halo = 1.0
		"ok":
			core = Color8(255, 238, 170)
			arm = (7.0 if key else 4.0) * (1.0 if rm else 0.65 + 0.35 * sin(t * TAU / 1.6 + ph))
		"poor":
			core = C_POOR
			arm = 3.0 if key else 2.0
		"lock":
			core = Color(C_LOCK, 1.0)
	arm *= g
	# 标记圈
	ci.draw_arc(p, r, 0.0, TAU, 36, Color(C_LINE, (0.16 if st == "lock" else 0.26) * g), 1.0)
	if halo > 0.0:
		ci.draw_circle(p, r * 0.9, Color(C_SAP, 0.07 * g))
		ci.draw_circle(p, r * 0.5, Color(C_SAP, 0.14 * g))
	# 下一颗提示（10-26 用户「先点哪个」）：每个星座里第一颗还没塑造、前置已满足的星（只有它会是 ok / poor）——
	# 呼吸光晕 + 四道斜向长星芒慢慢亮暗（2.4 秒一呼吸，和本身的十字星芒错开 45°）。买得起暖白、买不起冷灰蓝且弱一档；
	# 减少动态效果时不呼吸，停在中间亮度。只有几个圆和像素点，手机 30 帧无负担
	if st == "ok" or st == "poor":
		var br := 0.5 if rm else 0.5 + 0.5 * sin(t * TAU / 2.4 + ph * 0.3)
		var hc := Color8(255, 236, 190) if st == "ok" else Color8(150, 170, 200)
		var k0 := (1.0 if st == "ok" else 0.55) * g
		ci.draw_circle(p, r * 1.6, Color(hc, 0.05 * k0 * (0.6 + 0.4 * br)))
		ci.draw_circle(p, r * 1.1, Color(hc, 0.08 * k0 * (0.5 + 0.5 * br)))
		var ln := r + 6.0 + 4.0 * br
		for k in 4:
			var dv := Vector2.from_angle(PI / 4.0 + k * PI / 2.0)
			for q in range(int(r * 0.6), int(ln)):
				ci.draw_rect(Rect2((p + dv * q).floor(), Vector2(1, 1)), Color(hc, (1.0 - float(q) / ln) * 0.55 * k0 * (0.35 + 0.65 * br)))
	# 星团：质变节点周围的小伴星（位置按 id 固定）
	if key:
		var rng := RandomNumberGenerator.new()
		rng.seed = id.hash()
		for c in 4:
			var cp := p + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(r * 0.45, r * 0.85)
			var ca := (0.9 if st == "on" else (0.6 if st != "lock" else 0.3)) * g * (1.0 if rm else 0.7 + 0.3 * sin(t * 2.3 + c * 1.7 + ph))
			ci.draw_rect(Rect2(cp.floor(), Vector2(1, 1)), Color(core, ca))
	# 星芒：十字长、斜向短（质变节点八道）
	if arm >= 1.0:
		for k in (8 if key else 4):
			var dv := Vector2.from_angle(k * TAU / (8 if key else 4) - PI / 2.0)
			var l := arm if k % 2 == 0 or not key else arm * 0.5
			for q in range(1, int(l) + 1):
				var a := (1.0 - float(q) / (l + 1.0)) * g
				ci.draw_rect(Rect2((p + dv * q).floor(), Vector2(1, 1)), Color(core, a))
	# 星芯：菱形（|x| + |y| < 半径），中心一点纯白
	var cs := (3 if key else 2) if st != "lock" else 1
	var ca := g if st == "on" or st == "ok" else (0.9 if st == "poor" else 0.75) * g
	for y in range(-cs + 1, cs):
		var hw := cs - 1 - absi(y)
		ci.draw_rect(Rect2(p + Vector2(-hw, y), Vector2(hw * 2 + 1, 1)), Color(core, ca))
	if st == "on" or st == "ok":
		ci.draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, g))
	# 可塑造：黄色点环转动呼吸
	if st == "ok":
		var n := 20 if key else 14
		var rot := t * 0.6 if not rm else 0.0
		var a := (0.55 + 0.45 * sin(t * TAU / 1.6)) if not rm else 1.0
		for k in n:
			var dv := Vector2.from_angle(k * TAU / n + rot) * (r + 2.0)
			ci.draw_rect(Rect2((p + dv).floor(), Vector2(1, 1)), Color(C_YEL, a * g))
	# 塑造落定：外扩环
	if id == lit_id and lit_f >= LIT_GROW:
		var e := (lit_f - LIT_GROW) / (1.0 - LIT_GROW)
		ci.draw_arc(p, r + 2 + 16.0 * e, 0.0, TAU, 40, Color(C_SAP, 1.0 - e), 1.0)
	# 选中：四角黄角标（轻微呼吸）
	if selected:
		var q := r + 5 + (0.0 if rm else roundf(sin(t * TAU / 1.2) * 0.6 + 0.4))
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
	_draw_chrome(ci)
	_draw_card(ci)


func _txt(ci: CanvasItem, p: Vector2, s: String, sz: int, col: Color, anchor := "ma", bold := false) -> float:
	# 深色描边：压在连线和背景上也看得清
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var x := p.x - (w / 2.0 if anchor[0] == "m" else (w if anchor[0] == "r" else 0.0))
	var y := p.y + font.get_ascent(sz)
	ci.draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0.02, 0.05, 0.08, 0.85))
	ci.draw_string(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	if bold:
		ci.draw_string_outline(font, Vector2(x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 1, col)
	return w


## 星旁的字：带罗马数字的线只写数字（线名标在星座旁），多程信息处理那条每颗名字不同，写全名
func _short(id: String) -> String:
	var nm := str(Meta.nodes()[id].name)
	return nm.right(1) if "ⅠⅡⅢⅣⅤⅥ".contains(nm.right(1)) else nm


func _draw_labels(ci: CanvasItem) -> void:
	var sid := _sel_id()
	var c := TUI.ctx(ci)
	# 星座旁的线名（星图标注），下面一行像素小字「已塑造 / 总数」
	var cs: Dictionary = lay.get("consts", {})
	for ch in chains:
		var pre := _pre(ch[0])
		if not cs.has(pre):
			continue
		var g := _appear(ch[0])
		if g <= 0.0:
			continue
		var d := _to_view(_v(cs[pre].at))
		var done := 0
		for id in ch:
			if Cfg.meta_shape.get(id, false):
				done += 1
		_txt(ci, d + Vector2(0, -10.0), str(cs[pre].name), 13, Color(0.66, 0.78, 0.92, (0.95 if done > 0 else 0.62) * g))
		var ps := "%d/%d" % [done, ch.size()]
		TUI.ptext(ci, c, d + Vector2(-TUI.ptext_w(c, ps, 1.0) / 2.0, 13.0), ps, 1.0, Color(T_SUB, 0.75 * g))
	# 星名 + 消耗：按布局 lside 摆在星的 右 / 左 / 下 / 上（layout.py 选的避开连线的那边）
	var sides: Dictionary = lay.get("lside", {})
	for ch in chains:
		for id: String in ch:
			var g := _appear(id)
			if g <= 0.0:
				continue
			var d := _to_view(pos[id])
			if d.x < -80.0 or d.x > vs.x + 80.0 or d.y < -40.0 or d.y > vs.y + 40.0:
				continue
			var r := (rk if _is_key(id) else rn) * pxu
			var st := _state(id)
			var col := T_ON if st == "on" or st == "ok" else (T_POOR if st == "poor" else T_LOCK)
			var sel_on := id == sid
			var nm := str(Meta.nodes()[id].name) if sel_on else _short(id)
			var nw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14 if sel_on else 13).x + (20.0 if sel_on else 0.0)
			var cost := "" if st == "on" else str(int(Meta.nodes()[id].cost))
			var w := nw + (14.0 + TUI.ptext_w(c, cost, 1.5) if cost != "" else 0.0)
			var np := Vector2(d.x + r + 6.0, d.y - 9.0)
			match str(sides.get(id, "r")):
				"l":
					np = Vector2(d.x - r - 6.0 - w, d.y - 9.0)
				"b":
					np = Vector2(d.x - w / 2.0, d.y + r + 4.0)
				"t":
					np = Vector2(d.x - w / 2.0, d.y - r - 22.0)
			if sel_on:   # 选中：黄色名牌写全名
				HS.para(ci, Rect2(np.x, np.y - 1.0, nw, 21.0), HS.YEL)
				UI.text_at(ci, font, Vector2(np.x + nw / 2.0, np.y + 9.5), nm, 14, HS.INK, "mm", true)
			else:
				_txt(ci, np, nm, 13, UI.fa(col, g), "la")
			if cost != "":
				var cc := C_YEL if st == "ok" else col
				var cx := np.x + nw + 6.0
				TUI.pdiamond(ci, c, Vector2(cx + 2.0, np.y + 9.0), 2, TUI.cell(c, 1.0), UI.fa(cc, g))
				TUI.ptext(ci, c, Vector2(cx + 8.0, np.y + 9.0), cost, 1.5, UI.fa(cc, g))


func _draw_chrome(ci: CanvasItem) -> void:
	var mouse := view.get_local_mouse_position()
	var done := 0
	for id in Cfg.meta_shape:
		if Cfg.meta_shape[id]:
			done += 1
	for i in 12:   # 顶栏下一条渐隐暗带：推荐 / 重置 / 提示压在连线上也看得清
		ci.draw_rect(Rect2(0, 60.0 + i * 6.0, vs.x, 6.0), Color(0.012, 0.02, 0.035, 0.92 * pow(1.0 - i / 12.0, 0.7)))
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
	UI.text_at(ci, font, back.get_center(), "返回", 15, UI.TEXT, "mm", true)
	UI.btn_key(ci, font, back, "" if Pad.using else "ESC", UI.SUB, 10, back.size.y * HS.SKEW + 10.0)   # 10-31 TA H7
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
	var hint: String
	if tch:
		hint = "点节点选中 · 再点塑造" + (" · 拖动平移" if pan else "")
	else:
		hint = Pad.hint("方向键 选择  ·  Enter 塑造  ·  Z 详情" + ("  ·  拖动 平移" if pan else ""), "十字键 选择  ·  Ⓐ 塑造  ·  Ⓧ 详情", "")
	UI.text_at(ci, font, Vector2(24, 84), hint, 12, UI.fa(T_SUB, 0.85))


## 详情卡。桌面：左下浅色档案卡（左黄条、右上切角、「NODE // 认知节点」、组色标签、名称、效果大字、质变、本线进度、状态、塑造按钮），
## 高度随内容、底边对齐；手机：贴底一条（名称 + 效果 ｜ 本线进度 + 状态 ｜ 塑造按钮），把上面的根让出来
func _draw_card(ci: CanvasItem) -> void:
	var id := _sel_id()
	if id == "" or fit_all:
		return
	var slide := 1.0 if Cfg.reduce_motion else UI.ease_out(clampf((t - open_t0 - 0.15) / 0.3, 0.0, 1.0))
	if card_hide:
		_draw_card_tab(ci, id)
		return
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
	_card_fold_btn(ci, Rect2(r.end.x - 96.0, r.position.y - 40.0, 96.0, 30.0))


## 卡外的「收起」键（卡上沿上方，压在暗场上）
func _card_fold_btn(ci: CanvasItem, r: Rect2) -> void:
	HS.ghost_btn(ci, font, r, "收起", "" if Pad.using or Pad.touch else "Z", 0.72)
	buttons.append([r, "card"])


## 卡收起后左下角的小标签：「详情」+ 选中节点名与消耗，点一下展开
func _draw_card_tab(ci: CanvasItem, id: String) -> void:
	var nd: Dictionary = Meta.nodes()[id]
	var s1 := "%s · %s" % [str(nd.name), "已塑造" if _state(id) == "on" else "%d 生机细胞" % int(nd.cost)]
	var key := "" if Pad.using else Pad.hint("Z", "Ⓧ", "")   # 10-31 TA H7：键名用按键牌，不混写
	var w := UI.cwidth(font, s1, 13) + UI.cwidth(font, "详情", 15) + (UI.cwidth(font, key, 12) + 22.0 if key != "" else 0.0) + 52.0
	var r := Rect2(16.0 if Cfg.phone_ui() else 24.0, vs.y - (12.0 if Cfg.phone_ui() else 20.0) - 34.0, w, 34.0)
	HS.para(ci, r, Color(0, 0, 0, 0.55), UI.fa(UI.TEXT, 0.85), 1.5)
	ci.draw_rect(Rect2(r.position.x + 8.0, r.position.y + 7.0, 4.0, r.size.y - 14.0), HS.YEL)
	var x := r.position.x + 20.0
	x += UI.text_at(ci, font, Vector2(x, r.get_center().y), "详情", 15, UI.TEXT, "lm", true) + 10.0
	x += UI.text_at(ci, font, Vector2(x, r.get_center().y + 1.0), s1, 13, UI.fa(UI.TEXT, 0.8), "lm") + 10.0
	if key != "":
		UI.keycap(ci, font, Vector2(x, r.get_center().y - 9.0), key, UI.fa(UI.TEXT, 0.7), 11)
	buttons.append([r, "card"])


## 卡片正文（不含按钮）：draw = false 时只量高度。返回正文高度
func _card_body(ci: CanvasItem, o: Vector2, w: float, id: String, draw: bool) -> float:
	var nd: Dictionary = Meta.nodes()[id]
	var st := _state(id)
	var ch: Array = chains[clampi(sel.x, 0, chains.size() - 1)]
	var g: int = GROUP_OF.get(_pre(id), 0)
	var x := o.x + 22.0
	var y := o.y + 16.0
	var tw := w - 44.0
	# 名称一行：左名称，右「组色标签 + 第几节 / 共几节」（右上切角留出来）
	if draw:
		UI.text_at(ci, font, Vector2(x - 2.0, y), str(nd.name), 24, HS.INK, "la", true)
		var gt: String = GROUPS[g][0]
		var gw := UI.cwidth(font, gt, 12) + 18.0
		var gr := Rect2(o.x + w - 84.0 - gw, y + 4.0, gw, 18.0)
		HS.para(ci, gr, HS.INK)
		UI.text_at(ci, font, gr.get_center(), gt, 12, GROUPS[g][2], "mm", true)
		UI.text_at(ci, font, Vector2(o.x + w - 30.0, y + 13.0), "%d / %d" % [ch.find(id) + 1, ch.size()], 14, HS.INK2, "rm", true)
	y += 34.0
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
			UI.text_at(ci, font, Vector2(x - 2.0, y + 16.0), m.get_string(2), 30, HS.RIB, "la", true)
		y += 52.0
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
	_card_fold_btn(ci, Rect2(r.end.x - 108.0, r.position.y - 42.0, 108.0, 34.0))


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
