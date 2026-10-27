extends RefCounted
## Read-only run-end presentation. No combat work, RNG or input registration in draw.
const RS = preload("res://scripts/run/run_stats.gd")
const HH = preload("res://scripts/screens/hh_style.gd")
const UM = preload("res://scripts/ui_motion.gd")
const Roster = preload("res://scripts/core/roster.gd")
const D = preload("res://scripts/data.gd")
var g
var topography: Texture2D = preload("res://art/ui/settlement/topography.png")
var navigation: Texture2D = preload("res://art/ui/settlement/navigation.png")
var _signature: Array = []
var model: Dictionary = {}
var rows: Array = []
var art: Dictionary = {}
var elapsed := 0.0
var offset := 0.0
var selected := 0
var dragging := false
var drag_x := 0.0
var drag_offset := 0.0
var moved := false
var scale := 1.0
var origin := Vector2.ZERO
class SquadCanvas extends Control:
	var screen
	func _draw() -> void:
		screen.draw_cards(self)

var squad_canvas: Control
var cells := 0
var vouchers := 0
const STRIDE := 224.0
## 底栏按钮反馈（10-28 用户「结算画面最下面点击按钮没有交互反馈」）：悬停高亮 + 青边、按下缩小变亮、点击音（ui_ok，悬停换按钮 ui_move）、
## 键盘 / 手柄焦点框（↓ 进入底栏、← → 换按钮、↑ 回编队、Enter / Ⓐ 按下）、触屏按下态；动作在按下后 PRESS_T 秒执行，按下态看得见
const PRESS_T := 0.09
var hover := ""        # 鼠标悬停的按钮 id
var focus := -1        # 键盘 / 手柄焦点在底栏第几个按钮（-1 = 焦点在编队卡）
var press_id := ""     # 正在播按下态的按钮
var press_t := 0.0
var _pending := ""     # 按下后待执行的动作
## 战绩分享卡（10-28 用户定样式 B「深海海报」；卡面 screens/share_card.gd，Toy 头像 / 二维码 / 保存 screens/share_toy.gd）
const ShareCard = preload("res://scripts/screens/share_card.gd")
const ShareToy = preload("res://scripts/screens/share_toy.gd")
var share
var share_toy
var share_open := false
var share_t := 0.0
var share_data := {}
const SHARE_K := 0.78                       # 卡 600×800 → 468×624
const SHARE_POS := Vector2(406, 40)         # 卡在 1280×720 里的左上角
const VIEW := Rect2(28, 288, 884, 350)
## 入场分段（docs/62 §3.21b，10-28 用户「出现的太快了」）：时间点按胜利写，失败整体拉长到 END_LOSS（打捞，慢一档）；
## 出场完成前任意按键 / 点击 / 触屏只跳到终态，按钮不响应
const END_WIN := 3.2
const END_LOSS := 3.8
const T_TITLE := 0.2     # 结果标题盖章
const T_RATE := 1.85     # 评级盖章
const T_CARDS := 1.9     # 编队卡开始升入
const T_LINE := 2.3      # 关键事件时间线
const T_FOOT := 2.85     # 底栏按钮升起
const LOSS_BAND := Color8(150, 160, 172)   # 失败：顶部浅色带压暗偏冷
var _o := Vector2.ZERO   # 当前页面原点（含盖章轻抖）
var _fa := 1.0           # 当前绘制组透明度（_text 乘上）
var _dx := 0.0           # 当前绘制组水平偏移（失败打捞的晃动）
var _blur := 0.0         # 失败打捞的失焦虚影（0 = 对焦）

func _init(host) -> void:
	g = host

func active() -> bool:
	return not g.trial.active and g.demo_op == "" and g.state in [g.S.WIN, g.S.DEAD]

func tick(dt: float) -> void:
	if not active():
		if is_instance_valid(squad_canvas):
			squad_canvas.hide()
		return
	if squad_canvas == null:
		squad_canvas = SquadCanvas.new()
		squad_canvas.screen = self
		squad_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		squad_canvas.clip_contents = true
		g.hud.add_child(squad_canvas)
	if model.is_empty():
		preload("res://scripts/core/frame_rec.gd").mark("settle")
		set_model(RS.model(RS.snapshot(g)))
		cells = int(g.meta_result.get("cells", 0))
		vouchers = int(g.roster_new.get("hunt", 0))
	var safe: Rect2 = Cfg.touch_safe_rect(g.get_viewport_rect().size / Cfg.ui_k)
	scale = minf(safe.size.x / 1280.0, safe.size.y / 720.0)
	origin = safe.position + (safe.size - Vector2(1280, 720) * scale) * 0.5
	squad_canvas.position = origin + VIEW.position * scale
	squad_canvas.size = VIEW.size * scale
	squad_canvas.modulate.a = clampf((g.state_age-g.hud_view.DEATH_T)/0.35,0,1) if g.state==g.S.DEAD else 1.0
	squad_canvas.visible = not share_open and not g.run_stats.open and not g.headhunt.open and (g.state == g.S.WIN or g.state_age >= g.hud_view.DEATH_T)
	if g.state == g.S.WIN or g.state_age >= g.hud_view.DEATH_T:
		var prev := elapsed
		elapsed = _end() if UM.rm() or UM.skip_all() or g.ui_skip else minf(_end(), elapsed + dt)
		if _won() and elapsed < _end():
			for t0 in [T_TITLE + 0.15, T_RATE + 0.15]:   # 盖章落定：低沉一声
				if prev < t0 and elapsed >= t0:
					Sfx.play("ui_ok", -7.0, 0.62, 0.0)
		if prev < _end():
			g.hud.queue_redraw()
	if share_open:
		share_t += dt
		g.hud.queue_redraw()
	if press_t > 0.0:
		press_t = maxf(0.0, press_t - dt)
		g.hud.queue_redraw()
		if press_t <= 0.0:
			press_id = ""
			if _pending != "":
				var act := _pending
				_pending = ""
				_run(act)
	var signature := [offset, selected, scale, elapsed, rows.size(), squad_canvas.visible]
	if signature != _signature:
		_signature = signature
		squad_canvas.queue_redraw()

func set_model(value: Dictionary) -> void:
	_signature.clear()
	model = value
	rows = model.get("rows", []).filter(func(r): return str(r.key) != RS.OTHER)
	offset = 0.0
	selected = 0
	art.clear()
	for row in rows:
		var idle: Dictionary = g.panel_ui.op_idle(str(row.key))
		if idle.is_empty():
			continue
		var tx: Texture2D = idle.tex
		if tx is CanvasTexture:
			tx = tx.diffuse_texture
		if tx == null:
			continue
		var image: Image = tx.get_image()
		if image == null:
			continue
		if image.is_compressed():
			image.decompress()
		var region := Rect2i(0, 0, int(idle.fw), int(idle.fh))
		var bounds := image.get_region(region).get_used_rect()
		art[row.key] = {"tex": tx, "bounds": Rect2(bounds)}

func _won() -> bool:
	return str(model.get("result", "")) == "win"

func _end() -> float:
	return END_WIN if _won() else END_LOSS

## 出场是否完成（完成前输入只跳过）
func done() -> bool:
	return elapsed >= _end()

func skip() -> void:
	elapsed = _end()
	g.hud.queue_redraw()

## 时间轴进度：t0 / dur 按胜利写，失败按 END_LOSS / END_WIN 拉长
func _k(t0: float, dur: float) -> float:
	var s: float = 1.0 if _won() else END_LOSS / END_WIN
	return clampf((elapsed - t0 * s) / (dur * s), 0.0, 1.0)

## 一组元素进场：胜利从左 14 px 滑入淡入；失败水平晃动 + 失焦虚影，逐渐对焦变实（§3.20 打捞）
func _enter(t0: float, dur: float) -> float:
	var p := _k(t0, dur)
	var e := UM.out_cubic(p)
	_fa = e
	if _won():
		_dx = -14.0 * (1.0 - e)
		_blur = 0.0
	else:
		_dx = sin(elapsed * 13.0 + t0 * 7.0) * 6.0 * (1.0 - e)
		_blur = 1.0 - e
	return p

## 盖章（胜利）：1.45 倍砸到 1 倍；失败改成打捞进场。画完调 _plain 复位
func _stamp(ci: CanvasItem, pivot: Vector2, t0: float) -> void:
	if not _won():
		_enter(t0, 0.5)
		return
	var p := _k(t0, 0.15)
	var s := lerpf(1.45, 1.0, UM.out_cubic(p))
	ci.draw_set_transform(_o + pivot * scale * (1.0 - s), 0, Vector2.ONE * scale * s)
	_fa = 0.0 if p <= 0.0 else minf(1.0, p * 2.5)
	_dx = 0.0
	_blur = 0.0

func _plain(ci: CanvasItem) -> void:
	ci.draw_set_transform(_o, 0, Vector2.ONE * scale)
	_fa = 1.0
	_dx = 0.0
	_blur = 0.0

## 盖章落定后 0.16 秒轻抖 2–3 px（只动结算页面绘制偏移）
func _shake() -> Vector2:
	if not _won() or UM.rm():
		return Vector2.ZERO
	for t0 in [T_TITLE + 0.15, T_RATE + 0.15]:
		var q: float = (elapsed - t0) / 0.16
		if q >= 0.0 and q < 1.0:
			var a := 3.0 * (1.0 - q)
			return Vector2(sin(q * 40.0) * a, cos(q * 33.0) * a * 0.6)
	return Vector2.ZERO

func max_offset() -> float:
	return maxf(0.0, rows.size() * STRIDE - VIEW.size.x)

func scroll(value: float) -> void:
	offset = clampf(value, 0.0, max_offset())

func select(index: int) -> void:
	selected = clampi(index, 0, maxi(0, rows.size() - 1))
	var left := selected * STRIDE
	if left < offset:
		scroll(left)
	elif left + 212.0 > offset + VIEW.size.x:
		scroll(left + 212.0 - VIEW.size.x)

## 评级（只展示，不影响奖励）。通关按档位分两级（10-22 用户）：倒地 0 次且用时 ≤ 12:30 取高档（常规 S / 高压 SS / 深潮 SSS），
## 否则低一级（A / S / SS）；失败：打到终局 Boss A、击败中期 Boss B、其余 C
const GRADE_FAST := 750.0

static func grade(m: Dictionary, preset: int) -> String:
	if str(m.get("result", "")) == "win":
		var top: bool = int(m.get("downs", 0)) == 0 and float(m.get("t", 0.0)) <= GRADE_FAST
		return (["S", "SS", "SSS"] if top else ["A", "S", "SS"])[clampi(preset, 0, 2)]
	# A requires the final boss to have appeared; B requires a defeated mid boss.
	var final_name := str(D.ENEMIES.get(D.ENDINGS.get(str(m.get("ending", "standard")), {}).get("boss", ""), {}).get("name", "")).replace('"', '')
	for boss in m.get("bosses", []):
		if final_name != "" and str(boss.name) == final_name:
			return "A"
	for boss in m.get("bosses", []):
		if float(boss.get("t1", -1)) >= 0 and not bool(boss.get("retreat", false)):
			return "B"
	return "C"

## 底栏按钮：[id, x, 宽, 文字, 主按钮]（与画法、点击区同一张表）
func _buttons() -> Array:
	var tch: bool = Pad.touch_ui()   # 触屏（手机 / 平板）不写键位
	var out: Array = [["share", 1148, 100, "分享战绩" if (Pad.using or tch) else "分享  V", false, Rect2(1148, 202, 100, 34)],
		["records", 28, 160, "作战数据  SELECT" if Pad.using else ("作战数据" if tch else "作战数据  Tab"), false]]
	if Cfg.runs_log_enabled():   # 对局记录（测试版 / 对内包）：点一下打开记录文件夹（10-22 用户）
		out.append(["runs", 206, 150, "对局记录", false])
	out.append(["title", 374, 250, "返回主界面  B" if Pad.using else ("返回主界面" if tch else "返回主界面  Esc"), false])
	out.append(["meta", 642, 250, "认知塑造  Y" if Pad.using else ("认知塑造" if tch else "认知塑造  X"), false])
	out.append(["hunt", 910, 342, ("寻访 ×%d  A" if Pad.using else ("寻访 ×%d" if tch else "寻访 ×%d  Enter")) % Roster.tickets(), Roster.tickets() > 0])
	return out


func _btn_rect(b: Array) -> Rect2:
	if b.size() > 5:
		return b[5]
	var ph: bool = Cfg.phone_ui()   # 手机：按钮 52 高
	return Rect2(float(b[1]), 660.0 if ph else 666.0, float(b[2]), 52.0 if ph else 40.0)


func _btn_at(p: Vector2) -> String:
	for b in _buttons():
		if _btn_rect(b).grow(2.0).has_point(p):
			return str(b[0])
	return ""


## 按下：先播按下态 + 点击音，PRESS_T 秒后再执行（换场景的动作立刻执行就看不到反馈）
func _press(id: String) -> void:
	if id == "" or _pending != "":
		return
	press_id = id
	press_t = PRESS_T
	_pending = id
	Sfx.play("ui_ok", -6.0)
	g.hud.queue_redraw()


func _run(id: String) -> void:
	match id:
		"records": _records()
		"runs": Cfg.show_runs_folder()
		"title", "meta", "hunt": _action(id)
		"share": _open_share()


func _open_share() -> void:
	if share == null:
		share = ShareCard.new(g)
	if share_toy == null:
		share_toy = ShareToy.new()
		g.add_child(share_toy)
		share_toy.setup(g)
	share_toy.want_profile()   # 紧跟玩家点按：平台的头像昵称确认弹窗要用户操作触发
	share_toy.status = ""
	share_data = share.data(self)
	share_open = true
	share_t = 0.0
	if is_instance_valid(squad_canvas):
		squad_canvas.hide()
	g.hud.queue_redraw()


func _close_share() -> void:
	share_open = false
	Sfx.play("ui_move", -8.0)
	g.hud.queue_redraw()


## 分享卡打开时的输入：Esc / Ⓑ / 点卡外 关闭；Enter / S / 点「保存图片」保存
func _share_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
			KEY_ESCAPE, KEY_T, KEY_V: _close_share()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_S: _save_share()
		g.hud.queue_redraw()
		return
	var p := Vector2.INF
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		p = _point(event.position)
	elif event is InputEventScreenTouch and event.pressed:
		p = _point(event.position)
	if p == Vector2.INF:
		return
	if _share_save().has_point(p):
		_save_share()
	elif _share_close().has_point(p) or not Rect2(SHARE_POS, Vector2(ShareCard.W, ShareCard.H) * SHARE_K).has_point(p):
		_close_share()


func _save_share() -> void:
	if share_toy == null or share_toy.busy:
		return
	Sfx.play("ui_ok", -8.0)
	share_toy.save(share, share_toy.fill(share_data.duplicate()))


func _share_save() -> Rect2:
	return Rect2(SHARE_POS.x + ShareCard.W * SHARE_K + 24, SHARE_POS.y + 40, 150, 42)


func _share_close() -> Rect2:
	return Rect2(SHARE_POS.x + ShareCard.W * SHARE_K + 24, SHARE_POS.y + ShareCard.H * SHARE_K - 42, 150, 42)


func _draw_share(ci: CanvasItem) -> void:
	var a: float = clampf(share_t / 0.18, 0.0, 1.0)
	ci.draw_rect(Rect2(-200, -200, 1680, 1120), Color(0.02, 0.03, 0.05, 0.78 * a))
	var k: float = SHARE_K * (0.94 + 0.06 * (1.0 - pow(1.0 - a, 3.0)))
	var sz := Vector2(ShareCard.W, ShareCard.H) * k
	var pos: Vector2 = SHARE_POS + (Vector2(ShareCard.W, ShareCard.H) * SHARE_K - sz) * 0.5
	ci.draw_set_transform(origin, 0, Vector2.ONE * scale)
	share.draw(ci, share_toy.fill(share_data), origin + pos * scale, k * scale)
	ci.draw_set_transform(origin, 0, Vector2.ONE * scale)
	ci.draw_rect(Rect2(pos, sz).grow(2), HH.CYB, false, 2.0)
	var sv := _share_save()
	_text(ci, sv.position.x, SHARE_POS.y + 6, "分享战绩", 20, HH.LIGHT)
	ci.draw_rect(sv, HH.CYB.lightened(0.2) if share_toy.busy else HH.CYB)
	_text(ci, sv.position.x + 16, sv.position.y + 10, "保存图片" if Pad.touch_ui() else "保存图片  Enter", 16, HH.INK)
	if share_toy.status != "":
		_text(ci, sv.position.x, sv.end.y + 12, share_toy.status, 13, HH.MUTE, 200)
	var c := _share_close()
	ci.draw_rect(c, HH.DARK2)
	_text(ci, c.position.x + 16, c.position.y + 10, "关闭" if Pad.touch_ui() else "关闭  Esc", 16, HH.LIGHT)
	ci.draw_set_transform(Vector2.ZERO)


func _set_hover(id: String) -> void:
	if id != hover:
		hover = id
		if id != "":
			Sfx.play("ui_move", -10.0)
		g.hud.queue_redraw()


func _point(p: Vector2) -> Vector2:
	return (p / Cfg.ui_k - origin) / scale

func input(event: InputEvent) -> bool:
	if not active() or model.is_empty():
		return false
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return true
	if share_open:
		_share_input(event)
		return true
	if not done():   # 出场中：第一下只跳到终态，不落到按钮上；悬停也不响应
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			skip()
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = Pad.kc(event)
		var bs: Array = _buttons()
		match key:
			KEY_DOWN, KEY_S:
				if focus < 0:
					focus = bs.size() - 1   # 进底栏：先落在主按钮（寻访）
					Sfx.play("ui_move", -10.0)
			KEY_UP, KEY_W:
				if focus >= 0:
					focus = -1
					Sfx.play("ui_move", -10.0)
			KEY_LEFT, KEY_A:
				if focus >= 0:
					focus = maxi(0, focus - 1)
					Sfx.play("ui_move", -10.0)
				else:
					select(selected - 1)
			KEY_RIGHT, KEY_D:
				if focus >= 0:
					focus = mini(bs.size() - 1, focus + 1)
					Sfx.play("ui_move", -10.0)
				else:
					select(selected + 1)
			KEY_HOME: select(0)
			KEY_END: select(rows.size() - 1)
			KEY_TAB, KEY_C: _press("records")
			KEY_V: _press("share")
			KEY_X, KEY_F: _press("meta")
			KEY_ESCAPE, KEY_T: _press("title")
			KEY_R: g._do_action("restart")
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if focus >= 0:
					_press(str(bs[mini(focus, bs.size() - 1)][0]))
				else:
					_press("hunt")
		g.hud.queue_redraw()
		return true
	if event is InputEventScreenDrag:
		if dragging:
			_drag(_point(event.position))
		return true
	if event is InputEventMouseMotion:
		if dragging:
			_drag(_point(event.position))
		else:
			_set_hover(_btn_at(_point(event.position)))
			if hover != "":
				focus = -1   # 鼠标接管：焦点框让给悬停
		return true
	if event is InputEventMouseButton:
		var p := _point(event.position)
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if VIEW.has_point(p):
				scroll(offset + (-80.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 80.0))
			return true
		if event.button_index == MOUSE_BUTTON_LEFT:
			_pointer(p, event.pressed)
		return true
	if event is InputEventScreenTouch:
		_pointer(_point(event.position), event.pressed)
		return true
	return true

func _drag(p: Vector2) -> void:
	if absf(p.x - drag_x) > 5:
		moved = true
	if moved:
		scroll(drag_offset + drag_x - p.x)

func _pointer(p: Vector2, pressed: bool) -> void:
	if pressed:
		var hit := _btn_at(p)
		if hit != "":
			_press(hit)   # 底栏与右侧「分享」按钮：按下态 + 点击音，PRESS_T 后执行（鼠标与触屏同一路）
			return
		if VIEW.has_point(p):
			dragging = true
			moved = false
			drag_x = p.x
			drag_offset = offset
		elif Rect2(28,638,884,14).has_point(p):
			scroll(offset + (-STRIDE if p.x < 470 else STRIDE))
		elif p.y >= (656 if Cfg.phone_ui() else 666):
			var id := _btn_at(p)
			if id == "" and p.x >= 28 and p.x < 200:
				id = "records"
			_press(id)   # 触屏按下也走这里：按下态 + 点击音，PRESS_T 后执行
	elif dragging:
		if not moved:
			select(int((p.x - VIEW.position.x + offset) / STRIDE))
		dragging = false

func _records() -> void:
	if is_instance_valid(squad_canvas):
		squad_canvas.hide()
	g.run_stats.show_model(model)

func _action(action: String) -> void:
	if action == "hunt":
		g.headhunt.maybe_open()
		if g.headhunt.open and is_instance_valid(squad_canvas):
			squad_canvas.hide()
	elif action == "meta":
		g.get_tree().set_meta("settlement_open_meta", true)
		g._do_action("title")
	elif action == "title":
		g._do_action("title")

## 手机横屏（10-26 用户 iPhone 实机）：整页按 1280×720 缩到约 0.87，11–13 号的小标只剩 6–7 pt；小字一律抬到 PHONE_MIN_FS，
## 基线不动（字往上长），各标签之间的留白够
const PHONE_MIN_FS := 15


func _text(ci: CanvasItem, x: float, y: float, text: String, size := 18, color := HH.LIGHT, width := -1.0) -> void:
	if _fa <= 0.0:
		return
	var fs := maxi(size, PHONE_MIN_FS) if Cfg.phone_ui() else size
	var c := Color(color, color.a * _fa)
	if _blur > 0.0:   # 失焦虚影：右侧错开一道淡影
		ci.draw_string(g.font, Vector2(x + _dx + 5.0 * _blur, y + size), text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, Color(color, color.a * 0.35 * _blur))
	ci.draw_string(g.font, Vector2(x + _dx, y + size), text, HORIZONTAL_ALIGNMENT_LEFT, width, fs, c)

func draw(ci: CanvasItem, vs: Vector2) -> void:
	if model.is_empty():
		return
	ci.draw_rect(Rect2(Vector2.ZERO, vs), HH.DARK)
	_o = origin + _shake() * scale
	_plain(ci)
	HH.backdrop(ci, Vector2(1280,720))
	ci.draw_texture(topography, Vector2.ZERO)
	ci.draw_rect(Rect2(0,0,1280,44), HH.INK)
	_text(ci,28,10,"作战结算",18)
	_text(ci,150,14,"OPERATION / REPORT",12,HH.MUTE)
	_text(ci,1120,12,"方舟幸存者",15,HH.LIGHT)
	var won := _won()
	# ① 顶部浅色带斜切扫入（失败压暗偏冷）
	var w := UM.out_cubic(_k(0.0, 0.35))
	if w > 0.0:
		HH.fill(ci, PackedVector2Array([Vector2(0,46),Vector2(716*w,46),Vector2(716*w-36,207),Vector2(0,207)]),HH.LIGHT if won else LOSS_BAND)
		ci.draw_texture_rect_region(navigation, Rect2(426,46,230,160), Rect2(0,140,230,160), Color(1,1,1,0.33*_k(0.2, 0.3)))
	# ② 结果标题（胜利盖章 / 失败打捞）
	_enter(0.35, 0.3)
	_text(ci,32,64,"01 / RESULT",12,HH.INK2)
	_text(ci,33,147,"OPERATION COMPLETE" if won else "OPERATION FAILED",21,HH.INK2)
	_stamp(ci, Vector2(130, 112), T_TITLE)
	_text(ci,29,85,"探索完成" if won else "探索终止",52,HH.INK)
	_plain(ci)
	# ③ 结局 / 用时 / 难度逐项
	_enter(0.55, 0.3)
	_text(ci,33,183,str(model.get("ending_name", "")) if won else str(model.get("killer", {}).get("name", "")),13,HH.INK2,340)
	_enter(0.67, 0.3)
	_text(ci,382,155,"探索用时",12,HH.INK2)
	_text(ci,382,176,RS_time(float(model.t)),21,HH.INK)
	_enter(0.79, 0.3)
	_text(ci,518,155,"难度档",12,HH.INK2)
	_text(ci,518,178,str(D.DIFF_PRESETS[clampi(g.preset,0,D.DIFF_PRESETS.size()-1)].name),18,HH.INK)
	# ④ 数字滚动：本局获得 → 总伤害 / 击败敌人
	_enter(0.9, 0.3)
	var count := UM.out_cubic(_k(0.95, 0.8))
	_text(ci,754,80,"本局获得",14,HH.MUTE)
	_text(ci,754,116,"生机细胞",13,HH.MUTE)
	_text(ci,754,140,"+%d" % int(cells*count),32)
	_text(ci,944,116,"寻访凭证",13,HH.MUTE)
	_text(ci,944,140,"×%d" % int(vouchers*count),32,HH.CYB)
	if bool(g.roster_new.get("short", false)):
		_text(ci,944,176,"探索不足 %d 分钟，不发放" % int(Roster.RUN_MIN_T / 60.0),11,HH.MUTE)
	_enter(1.0, 0.3)
	var roll := UM.out_cubic(_k(1.05, 0.8))
	_text(ci,32,232,"本局编队",20)
	_text(ci,140,239,"%d–%d / 共 %d 名" % [0 if rows.is_empty() else int(offset/STRIDE)+1,mini(rows.size(),ceili((offset+VIEW.size.x)/STRIDE)),rows.size()],12,HH.MUTE)
	_text(ci,440,237,"总伤害",12,HH.MUTE)
	_text(ci,500,231,g.run_stats.fmt_n(float(model.total)*roll),25)
	_text(ci,720,237,"击败敌人",12,HH.MUTE)
	_text(ci,810,231,str(int(float(model.kills)*roll)),25)
	ci.draw_line(Vector2(28,269),Vector2(28+884*UM.out_cubic(_k(1.0, 0.5)),269),HH.MUTE)
	# ⑤ 评级：框先淡入，字母盖章落定
	_enter(1.6, 0.3)
	ci.draw_rect(Rect2(1148,76,100,116),Color(HH.MUTE, _fa),false)
	_text(ci,1168,86,"RATING",11,HH.MUTE)
	_stamp(ci, Vector2(1180, 132), T_RATE)
	_text(ci,1156,108,grade(model,g.preset),42)
	_plain(ci)
	# ⑥ 编队卡在 squad_canvas 里逐张升入；滚动条随第一张卡出现
	_enter(T_CARDS, 0.4)
	ci.draw_line(Vector2(64,643),Vector2(876,643),Color(HH.DARK3, _fa),2)
	if max_offset() > 0:
		var thumb := 812.0*VIEW.size.x/(rows.size()*STRIDE)
		ci.draw_rect(Rect2(64+(812-thumb)*offset/max_offset(),641,thumb,3),Color(HH.CYB, _fa))
	_text(ci,28,631,"‹",18,HH.CYB)
	_text(ci,895,631,"›",18,HH.CYB)
	_plain(ci)
	# ⑦ 关键事件沿时间线逐条点亮
	_timeline(ci)
	# ⑧ 底栏升起
	var fp := UM.out_cubic(_k(T_FOOT, 0.35))
	ci.draw_rect(Rect2(0,652+80.0*(1.0-fp),1280,68),HH.INK)
	_draw_buttons(ci, fp)
	_plain(ci)
	ci.draw_set_transform(Vector2.ZERO)
	if share_open and share != null:
		_draw_share(ci)

## 底栏按钮：常态 / 悬停（提亮 + 青边）/ 按下（缩到 96%、更亮）/ 焦点（青色四角括号）；作战数据、对局记录是文字按钮（悬停才出底色）
func _draw_buttons(ci: CanvasItem, fp := 1.0) -> void:
	var ph: bool = Cfg.phone_ui()   # 手机：按钮 52 高、字 20
	var bs: Array = _buttons()
	for i in bs.size():
		var b: Array = bs[i]
		var id: String = b[0]
		var r := _btn_rect(b)
		# 出场：底栏按钮随底栏升起，右上「分享」淡入
		_fa = fp if b.size() > 5 else 1.0
		if b.size() <= 5:
			r.position.y += 80.0 * (1.0 - fp)
		var primary: bool = b[4]
		var text_btn: bool = id == "records" or id == "runs"
		var hov: bool = hover == id
		var foc: bool = focus == i
		var prs: bool = press_id == id
		if prs:
			r = Rect2(r.get_center() - r.size * 0.48, r.size * 0.96)
		var bg: Color = HH.CYB if primary else HH.DARK2
		if text_btn and not (hov or foc or prs):
			bg = Color(0, 0, 0, 0)
		elif hov or foc:
			bg = bg.lerp(HH.CYB, 0.18) if not primary else bg.lightened(0.18)
		if prs:
			bg = (HH.CYB if not primary else bg).lightened(0.3)
		bg.a *= _fa
		if bg.a > 0.0:
			ci.draw_rect(r, bg)
		if hov or prs:
			ci.draw_rect(r, HH.CYB, false, 2.0)
		if foc:
			var c := 10.0
			for corner in [[r.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)], [Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)], [r.end, Vector2(-1, 0), Vector2(0, -1)]]:
				var o: Vector2 = corner[0] + (corner[1] + corner[2]) * -3.0
				ci.draw_line(o, o + corner[1] * c, HH.CYB, 3.0)
				ci.draw_line(o, o + corner[2] * c, HH.CYB, 3.0)
		var fg: Color = HH.INK if (primary or prs) else (HH.LIGHT if (hov or foc or not text_btn) else HH.MUTE)
		var fs: int = (20 if ph else 18) if not text_btn else 16
		_text(ci, r.position.x + (20.0 if not text_btn else 0.0) + (4.0 if text_btn and (hov or foc or prs) else 0.0), r.position.y + (r.size.y - fs) * 0.5 - 2.0, str(b[3]), fs, fg)


func draw_cards(ci: CanvasItem) -> void:
	var first := int(offset / STRIDE)
	for i in rows.size():
		var x := 28.0 + i * STRIDE - offset
		if x + 212 < VIEW.position.x or x > VIEW.end.x:
			continue
		# 逐张从视窗下沿升入（错开 0.12 秒，最多 5 张参与错开）；失败升得慢、带晃动
		var t0 := T_CARDS + 0.12 * mini(maxi(i - first, 0), 4)
		var p := _k(t0, 0.4)
		if p <= 0.0:
			continue
		var e := UM.out_cubic(p)
		var sway := 0.0 if _won() else sin(elapsed * 11.0 + i) * 5.0 * (1.0 - e)
		ci.draw_set_transform(-VIEW.position * scale + Vector2(sway, 220.0 * (1.0 - e)) * scale, 0, Vector2.ONE * scale)
		_card(ci, rows[i], x, i, t0)
	_fa = 1.0
	_dx = 0.0
	_blur = 0.0

func _card(ci: CanvasItem, r: Dictionary, x: float, index: int, t0 := 0.0) -> void:
	_fa = 1.0
	_dx = 0.0
	_blur = 0.0
	HH.fill(ci,PackedVector2Array([Vector2(x+16,288),Vector2(x+210,288),Vector2(x+194,459),Vector2(x,459)]),HH.LIGHT if r.leader else HH.DARK2)
	ci.draw_rect(Rect2(x+16,288,40,3),HH.CYB if index==selected else r.col)
	if art.has(r.key):
		var a: Dictionary = art[r.key]
		var bb: Rect2 = a.bounds
		if bb.has_area():
			var k := floorf(minf(190/bb.size.x,146/bb.size.y)*2.0)/2.0
			k = maxf(0.5,k)
			var sz := bb.size*k
			ci.draw_texture_rect_region(a.tex,Rect2(Vector2(x+110-sz.x/2,451-sz.y).round(),sz),bb)
	_text(ci,x+8,474,str(r.name),24,HH.LIGHT,145)
	_text(ci,x+151,480,"队长" if r.leader else ("已离队" if r.left_t>=0 else ""),11,HH.CYB)
	_text(ci,x+8,513,"伤害占比",12,HH.MUTE)
	_text(ci,x+142,506,"%d%%" % int(r.pct),24)
	ci.draw_rect(Rect2(x+8,539,186,5),HH.DARK3)
	var fill := UM.out_cubic(_k(t0 + 0.3, 0.4))   # 卡落定后伤害条充满
	ci.draw_rect(Rect2(x+8,539,186*float(r.share)*fill,5),r.col)
	_text(ci,x+8,559,"参与击杀",13,HH.MUTE)
	_text(ci,x+145,553,str(r.kills),23)
	_text(ci,x+8,594,"参战时间",11,HH.MUTE)
	_text(ci,x+8,612,RS_time(float(r.in_s)),17)
	_text(ci,x+145,594,"技能次数",11,HH.MUTE)
	_text(ci,x+172,612,str(r.casts),17)

func _timeline(ci: CanvasItem) -> void:
	var lp := UM.out_cubic(_k(T_LINE, 0.55))   # 时间线自上而下画出，事件点随线头逐条点亮
	_enter(T_LINE - 0.1, 0.3)
	_text(ci,962,235,"关键事件",16,HH.MUTE)
	_plain(ci)
	if lp > 0.0:
		ci.draw_line(Vector2(995,304),Vector2(995,304+304*lp),HH.MUTE)
	var events: Array = [[0.0,"探索开始"]]
	for b in model.get("bosses",[]):
		if float(b.t1)>=0 and not bool(b.get("retreat",false)):
			events.append([float(b.t1),str(b.name)+" 击破"])
	if events.size() == 1 or absf(float(events.back()[0])-float(model.t)) > 1.0:
		events.append([float(model.t),"探索完成" if model.result=="win" else "探索终止"])
	var labels: Array = []
	for event in events:
		var y := 304.0+304.0*float(event[0])/maxf(1.0,float(model.t))
		labels.append(maxf(y, float(labels.back())+48.0) if not labels.is_empty() else y)
	for j in range(labels.size()-1,-1,-1):
		labels[j] = minf(float(labels[j]),608.0 if j==labels.size()-1 else float(labels[j+1])-48.0)
	for i in events.size():
		var y := 304.0+304.0*float(events[i][0])/maxf(1.0,float(model.t))
		if lp <= 0.0 or y > 304.0 + 304.0 * lp + 0.5:
			continue
		ci.draw_rect(Rect2(991,y-4,8,8),HH.CYB)
		_text(ci,1014,float(labels[i])-12,RS_time(float(events[i][0])),12,HH.MUTE)
		_text(ci,1014,float(labels[i])+8,events[i][1],13,HH.LIGHT,230)

static func RS_time(t: float) -> String:
	return "%02d:%02d" % [int(t)/60,int(t)%60]
