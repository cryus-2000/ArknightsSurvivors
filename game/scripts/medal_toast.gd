extends CanvasLayer
## 蚀刻章获得提示（autoload，10-30 用户「获得刻章的时候能不能添加一个提示」）：core/medals.gd 在新获得章时把 {key, t} 放进 Medals.pending 队列，这里取出来弹小横幅。
## 样式：左上（局内）/ 右上（标题）滑入 / 滑出的小横幅（章图标 + 「获得蚀刻章」+ 章名），约 3 秒，配一声轻音效；多枚排队、每枚间隔 0.5 秒；有「减少动态效果」时改为 ≤ 0.12 秒淡入淡出。
## 时机（docs/37 / docs/62：不挡操作、不打断战斗）：
##   - 局内（game.tscn）：战斗中（PLAY）当场弹；选卡 / 商店 / 事件 / 暂停 / 演出 / 开场指南（非 PLAY 的状态）先排队，回到战斗再弹；
##     倒下 / 通关（DEAD / WIN）等结算面板淡入（state_age ≥ 2 秒）后依次弹——局终补判的章都在这里；
##   - 标题：读档补录的章在回到标题后依次弹；蚀刻章页开着时队列直接清空（页内本来就能看到）；boot 画面等其它场景先不弹。
## 点横幅：标题界面跳到蚀刻章页（选中这枚）；局内只是关掉。位置避开手机摇杆 / 按键与右上的藏品 / 倍速 / 暂停。
## 测试 / 截图：--medaltoast=key,key 开局 1 秒后入队（只在内存）；--medaltoastshot 在第一枚横幅滑入完毕时存一张 shot_medaltoast.png 到 --shotdir=。

const Medals = preload("res://scripts/core/medals.gd")
const UI = preload("res://scripts/ui.gd")
const ICONS := "res://art/ui/medals/medal_%d.png"
const HOLD := 3.0        # 完全显示的时长
const SLIDE := 0.28      # 滑入 / 滑出
const FADE := 0.12       # 减少动态效果：淡入淡出
const GAP := 0.5         # 两枚之间的间隔

var _font: Font
var _ui: Control
var _cur: Dictionary = {}
var _age := 0.0
var _gap := 0.0
var _last_ms := 0
var _tex := {}
var _shot_t := -1.0
var _forced: Array = []


class Banner extends Control:
	var host

	func _draw() -> void:
		host._paint(self)

	func _gui_input(event: InputEvent) -> void:
		host._on_gui(event)


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load("res://fonts/ui.ttf")
	_ui = Banner.new()
	_ui.host = self
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ui.visible = false
	add_child(_ui)
	for a in Cfg.dev_args():
		if a.begins_with("--medaltoast="):
			_forced = a.substr(13).split(",", false)
			_shot_t = 0.0 if Cfg.dev_args().has("--medaltoastshot") else -1.0
			get_tree().create_timer(1.0).timeout.connect(func():
				for k in _forced:
					if not Medals.def(k).is_empty():
						Medals.pending.append({"key": k, "t": 0}))


func _process(_dt: float) -> void:
	var ms := Time.get_ticks_msec()
	var dt := clampf((ms - _last_ms) / 1000.0, 0.0, 0.25)   # 真实时间：卡顿 / 时间缩放不拉长横幅
	_last_ms = ms
	if _cur.is_empty():
		_gap = maxf(0.0, _gap - dt)
		_ui.visible = false
		if Medals.pending.is_empty() or _gap > 0.0 or not _gate():
			return
		_cur = Medals.pending.pop_front()
		_age = 0.0
		_ui.visible = true
		_play()
	else:
		_age += dt
		if _age >= _total():
			_cur = {}
			_gap = GAP
			_ui.visible = false
			_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return
	_layout()
	_ui.queue_redraw()
	if _shot_t >= 0.0 and not _cur.is_empty():
		_shot_t += dt
		if _shot_t >= 1.0:
			_shot_t = -1.0
			var dir := "user://"
			for a in Cfg.dev_args():
				if a.begins_with("--shotdir="):
					dir = a.substr(10)
			get_viewport().get_texture().get_image().save_png(dir.trim_suffix("/") + "/shot_medaltoast.png")
			print("MEDALTOAST shot %s" % dir)


func _total() -> float:
	return HOLD + (2.0 * FADE if Cfg.reduce_motion else 2.0 * SLIDE)


## 能不能弹：局内只在战斗中 / 结算面板出来后；标题在没开别的界面时；蚀刻章页开着就清队列
func _gate() -> bool:
	var sc := get_tree().current_scene
	if sc == null:
		return false
	if sc.get("medals_ui") != null:
		if sc.medals_ui.visible:
			Medals.pending.clear()
			return false
		return not sc._overlay_open()
	if sc.get("hud") != null and sc.get("state") != null:
		var st: int = sc.state
		if st == sc.S.PLAY:
			return true
		return (st == sc.S.DEAD or st == sc.S.WIN) and float(sc.get("state_age")) >= 2.0
	return false


func _play() -> void:
	Sfx.play("ui_ok", -4.0, 1.3)


# ---------------------------------------------------------------- 版式
func _size() -> Vector2:
	var phone: bool = Cfg.phone_ui()
	var name := str(Medals.def(str(_cur.key)).get("name", ""))
	var nw: float = UI.cwidth(_font, name, 15 if not phone else 13)
	return Vector2(maxf(190.0 if not phone else 168.0, 62.0 + nw + 20.0), 46.0 if not phone else 40.0)


## 当前横幅的位置（视口坐标）：局内在左上（生命 / 灯火条和 buff 行的下面；右上是藏品 / 倍速 / 暂停，右侧下半是摇杆 / 按键），
## 标题在右上（左上是 Logo）；贴安全区；滑入从屏幕边外滑进来
func _layout() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var sz := _size()
	var ins: Array = Cfg.safe_insets()
	var sc := get_tree().current_scene
	var left: bool = sc != null and sc.get("hud") != null
	var phone: bool = Cfg.phone_ui()
	var mx := 14.0 + float(ins[0] if left else ins[2])
	var y := ((126.0 if not phone else 112.0) if left else (88.0 if not phone else 54.0)) + float(ins[1])
	var p := _progress()
	var x := mx if left else vs.x - sz.x - mx
	if not Cfg.reduce_motion:
		var off := (sz.x + mx + 4.0) * (-1.0 if left else 1.0)
		x += off * (1.0 - UI.ease_out(p[0])) * (1.0 if p[0] < 1.0 else 0.0)
		x += off * UI.ease_out(p[1]) * (1.0 if p[1] > 0.0 else 0.0)
	_ui.position = Vector2(x, y)
	_ui.size = sz
	_ui.mouse_filter = Control.MOUSE_FILTER_STOP if _alpha() > 0.5 else Control.MOUSE_FILTER_IGNORE


## [滑入进度 0..1, 滑出进度 0..1]
func _progress() -> Array:
	var sl: float = FADE if Cfg.reduce_motion else SLIDE
	return [clampf(_age / sl, 0.0, 1.0), clampf((_age - sl - HOLD) / sl, 0.0, 1.0)]


func _alpha() -> float:
	if not Cfg.reduce_motion:
		return 1.0
	var p := _progress()
	return minf(p[0], 1.0 - p[1])


func _icon(id: int) -> Texture2D:
	if not _tex.has(id):
		_tex[id] = load(ICONS % id) if ResourceLoader.exists(ICONS % id) else null
	return _tex[id]


func _paint(ci: Control) -> void:
	if _cur.is_empty():
		return
	var d: Dictionary = Medals.def(str(_cur.key))
	var a := _alpha()
	var sz: Vector2 = ci.size
	var phone: bool = Cfg.phone_ui()
	UI.panel(ci, Rect2(Vector2.ZERO, sz), UI.fa(UI.BG, 0.94 * a), UI.fa(UI.CYAN, 0.55 * a), 8.0)
	ci.draw_rect(Rect2(0, 5, 3, sz.y - 10), UI.fa(UI.CYAN, a))   # 左侧青色小竖条（可操作：点开）
	var isz := sz.y - 8.0
	var tex := _icon(int(d.get("id", 0)))
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(Vector2(8, 4), Vector2(isz, isz)), false, Color(1, 1, 1, a))
	var tx := isz + 16.0
	UI.text_at(ci, _font, Vector2(tx, sz.y * 0.34), "获得蚀刻章", 11 if not phone else 10, UI.fa(UI.SUB, a), "lm")
	UI.text_at(ci, _font, Vector2(tx, sz.y * 0.70), str(d.get("name", "")), 15 if not phone else 13, UI.fa(UI.TEXT, a), "lm")


func _on_gui(event: InputEvent) -> void:
	var press: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if not press or _cur.is_empty():
		return
	_ui.accept_event()
	var sc := get_tree().current_scene
	var key := str(_cur.key)
	_age = maxf(_age, SLIDE + HOLD)   # 直接开始滑出
	if sc != null and sc.get("medals_ui") != null and not sc._overlay_open():
		Medals.pending.clear()
		Sfx.play("ui_ok", -6.0)
		sc.transition.switch_page(func():
			sc.medals_ui.open()
			sc.medals_ui.sel = maxi(0, sc.medals_ui._index_of(key)))
