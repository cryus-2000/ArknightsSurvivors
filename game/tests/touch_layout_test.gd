extends Node
## 触屏按键布局回归（设置 → 游戏 → 触屏按键布局，用户 10-13）与超宽横屏适配：
## 1. touch_layout.gd：读档清洗、存档往返（ConfigFile 落盘再读）、相对锚点换比例、越界夹进安全区、缺省位置互不重叠、松手推开；
## 2. 局内：自定义位置真正用于点击（冲刺键 / 倍速键挪了位置后按新位置点得到）、改过位置的摇杆按圈内即固定摇杆；
##    触屏选卡时顶部中央计时器让位（hud.panel_over_top）；视口变了 ui_k 跟着重算；
## 3. 编辑页：拖动改位置并夹在安全区、拖到别的键身上会被推开、调大小、恢复默认、完成写回 Cfg.touch_layout。
## 存档文件只写 user://touch_layout_test.cfg（测试用户目录），不碰 settings.cfg。
const TL = preload("res://scripts/touch_layout.gd")
const HudSquad = preload("res://scripts/screens/hud_squad.gd")

var failures := 0
var game: Node
const SIZES := [Vector2(1045, 481), Vector2(1251, 481), Vector2(1000, 562), Vector2(1113, 835)]


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("TOUCH LAYOUT: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func inside(c: Vector2, k: String, s: float, safe: Rect2) -> bool:
	var b: Rect2 = TL.bounds(k, s)
	b.position += c
	return safe.grow(0.01).encloses(b)


func run() -> void:
	unit()
	await in_game()
	print("TOUCH LAYOUT failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func unit() -> void:
	# 编队区顶边常数与 hud_squad.squad_top 一致
	check(is_equal_approx(TL.SQUAD_TOP_UP, 16.0 + HudSquad.SQ_CARD.y + HudSquad.SQ_SK + 14.0 + 46.0), "SQUAD_TOP_UP 与 hud_squad.squad_top 不一致")
	# 读档清洗
	var raw := {"dash": {"ax": 1, "ay": 1, "x": 120.0, "y": 90, "s": 9.0}, "stick": {"ax": 0, "ay": 1, "x": "bad", "y": 3},
		"nope": {"ax": 0, "ay": 0, "x": 1, "y": 1}, "pause": "str", "speed": {"ax": 5, "ay": -2, "x": -50, "y": 99999, "s": 0.1}}
	var cl: Dictionary = TL.sanitize(raw)
	check(cl.has("dash") and is_equal_approx(cl.dash.s, TL.S_MAX), "缩放应夹到上限 (%s)" % [cl.get("dash")])
	check(not cl.has("stick") and not cl.has("nope") and not cl.has("pause"), "坏条目 / 未知键应丢掉 (%s)" % [cl.keys()])
	check(cl.has("speed") and cl.speed.ax == 1 and cl.speed.ay == 0 and cl.speed.x == 0.0 and cl.speed.y == 4000.0 and is_equal_approx(cl.speed.s, TL.S_MIN), "越界字段应夹紧 (%s)" % [cl.get("speed")])
	check(TL.sanitize(null).is_empty() and TL.sanitize([1, 2]).is_empty(), "非字典读档应得空布局")
	# 存档往返
	var lay := {"dash": TL.encode(Vector2(900, 300), Vector2(1045, 481), 1.25), "stick": TL.encode(Vector2(200, 380), Vector2(1045, 481), 0.8)}
	var c := ConfigFile.new()
	TL.save_to(c, lay)
	check(c.save("user://touch_layout_test.cfg") == OK, "测试存档写入失败")
	var c2 := ConfigFile.new()
	check(c2.load("user://touch_layout_test.cfg") == OK, "测试存档读取失败")
	var back: Dictionary = TL.load_from(c2)
	check(back == TL.sanitize(lay), "存档往返不一致 %s vs %s" % [back, lay])
	check(TL.load_from(ConfigFile.new()).is_empty(), "没有 [touch] 段应得空布局")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://touch_layout_test.cfg"))
	# 相对锚点：右下角的键换到 4:3 仍离右 / 下边同样远；左上角同理
	var a: Vector2 = Vector2(1045, 481)
	var b: Vector2 = Vector2(1113, 835)
	var e: Dictionary = TL.encode(Vector2(a.x - 100, a.y - 60), a, 1.0)
	check(TL.decode(e, b).is_equal_approx(Vector2(b.x - 100, b.y - 60)), "右下锚点换比例后应仍离右下 (100, 60)：%s" % TL.decode(e, b))
	var e2: Dictionary = TL.encode(Vector2(70, 50), a, 1.0)
	check(TL.decode(e2, b).is_equal_approx(Vector2(70, 50)), "左上锚点换比例不变")
	# 越界夹紧：每个键、两种极端缩放、四个点（含远在屏外）都夹进安全区
	for vs in SIZES:
		var safe: Rect2 = TL.safe_rect(vs, [30.0, 0.0, 44.0, 12.0])
		for k in TL.KEYS:
			for s in [TL.S_MIN, TL.S_MAX]:
				for p in [Vector2(-500, -500), Vector2(5000, 5000), Vector2(vs.x, 0), Vector2(0, vs.y)]:
					var cc: Vector2 = TL.clamp_center(p, k, s, safe)
					check(inside(cc, k, s, safe), "%s %s s=%.2f p=%s 夹紧后应在安全区内（%s）" % [vs, k, s, p, cc])
			var far := {k: {"ax": 1, "ay": 1, "x": -3000, "y": -3000, "s": 1.5}}
			var res: Dictionary = TL.resolve(vs, true, TL.sanitize(far), safe)
			check(inside(res[k].c, k, 1.5, safe), "%s %s 存档坐标越界时 resolve 也要夹回安全区" % [vs, k])
		# 缺省布局：都在安全区内，显示的按键两两不整个叠在一起
		for manual in [false, true]:
			var d: Dictionary = TL.resolve(vs, manual, {}, TL.safe_rect(vs))
			var shown: Array = ["stick", "dash", "skill", "pause", "stats", "speed", "cmd"] + (["atk"] if manual else [])
			for i in shown.size():
				check(inside(d[shown[i]].c, shown[i], 1.0, TL.safe_rect(vs)), "%s 缺省 %s 出了安全区" % [vs, shown[i]])
				for j in range(i + 1, shown.size()):
					var ki: String = shown[i]
					var kj: String = shown[j]
					check(not TL.too_close(d[ki].c, ki, 1.0, d[kj].c, kj, 1.0), "%s manual=%s 缺省 %s / %s 重叠" % [vs, manual, ki, kj])
	# 缺省位置与改版前一致（桌面 --touch 1113×626：冲刺 (1033, 384)、暂停 (1067, 186)、倍速 (1069, 93)）
	var d0: Dictionary = TL.resolve(Vector2(1113, 626), false, {}, TL.safe_rect(Vector2(1113, 626)))
	check(d0.dash.c.is_equal_approx(Vector2(1033, 626 - 196 - 14 - 32.2)), "桌面缺省冲刺键位置变了 %s" % d0.dash.c)
	check(d0.pause.c.is_equal_approx(Vector2(1067, 186)) and d0.speed.c.is_equal_approx(Vector2(1069, 93)), "桌面缺省暂停 / 倍速位置变了")
	# 松手推开：冲刺键扔到暂停键正上方 → 推到不算重叠且仍在安全区
	var vs0 := Vector2(1045, 481)
	var sf: Rect2 = TL.safe_rect(vs0)
	var dd: Dictionary = TL.resolve(vs0, false, {}, sf)
	var others := {}
	for k in ["stick", "skill", "pause", "stats", "speed"]:
		others[k] = dd[k]
	var p2: Vector2 = TL.separate("dash", dd.pause.c, 1.0, others, sf)
	check(p2 != Vector2.INF, "冲刺键应能被推开")
	if p2 != Vector2.INF:
		for k in others:
			check(not TL.too_close(p2, "dash", 1.0, others[k].c, k, others[k].s), "推开后冲刺键仍压着 %s" % k)
		check(inside(p2, "dash", 1.0, sf), "推开后冲刺键出了安全区")


func in_game() -> void:
	get_tree().root.size = Vector2i(1560, 720)   # 19.5:9：逻辑 1357×626，ui_k 1.3 → UI 约 1044×481
	await frames(2)
	Cfg.touch_layout = {}
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(6)
	for i in 400:
		if game.state == game.S.PLAY:
			break
		game.state = game.S.PLAY
		await frames(1)
	game.invuln = 999.0
	var vs: Vector2 = game.hud.size
	check(absf(Cfg.ui_k - Cfg.UI_K_PHONE) < 0.01 and Cfg.phone_ui(), "19.5:9 应是手机版式（ui_k=%.2f vs=%s）" % [Cfg.ui_k, vs])
	check(absf(game.cam.zoom.x - Cfg.ZOOM_PHONE_DEF / 100.0) < 0.001, "手机横屏战斗镜头缺省 %.2f（实际 %.2f）" % [Cfg.ZOOM_PHONE_DEF / 100.0, game.cam.zoom.x])
	# 界面大小 / 战斗画面缩放实时生效
	Cfg.ui_size_pct = 80
	Cfg.cam_zoom_pct = 140
	Cfg.apply()
	await frames(2)
	check(absf(Cfg.ui_k - Cfg.UI_K_PHONE * 0.8) < 0.01 and absf(game.ui_layer.scale.x - Cfg.ui_k) < 0.001, "界面大小 80%% 应实时生效（ui_k=%.3f）" % Cfg.ui_k)
	check(game.hud.size.is_equal_approx(Cfg.ui_size()), "界面大小改后 HUD 撑满 UI 区")
	check(absf(game.cam.zoom.x - 1.4) < 0.001, "战斗画面缩放 140%% 应实时生效（%.2f）" % game.cam.zoom.x)
	Cfg.ui_size_pct = 120
	Cfg.apply()
	await frames(2)
	check(Cfg.ui_size().y >= Cfg.UI_MIN_H - 0.5, "界面大小 120%% 时 UI 高不低于 %d（%.1f）" % [Cfg.UI_MIN_H, Cfg.ui_size().y])
	Cfg.ui_size_pct = 100
	Cfg.cam_zoom_pct = -1
	Cfg.apply()
	await frames(2)
	check(absf(Cfg.ui_k - Cfg.UI_K_PHONE) < 0.001 and absf(game.cam.zoom.x - 1.2) < 0.001, "恢复缺省")
	var cfgf := ConfigFile.new()
	Cfg.ui_size_pct = 115
	Cfg.cam_zoom_pct = 130
	cfgf.set_value("video", "ui_size", Cfg.ui_size_pct)
	cfgf.set_value("video", "cam_zoom", Cfg.cam_zoom_pct)
	check(int(cfgf.get_value("video", "ui_size")) == 115 and int(cfgf.get_value("video", "cam_zoom")) == 130, "界面大小 / 镜头缩放存档字段")
	Cfg.ui_size_pct = 100
	Cfg.cam_zoom_pct = -1
	Cfg.apply()
	await frames(2)
	vs = game.hud.size
	# 自定义：冲刺键挪到左下、放大；倍速键挪到左上；摇杆挪到左下另一处
	var dash_c := Vector2(300, vs.y - 120)
	var sp_c := Vector2(200, 160)
	var st_c := Vector2(120, vs.y - 110)
	Cfg.touch_layout = {"dash": TL.encode(dash_c, vs, 1.3), "speed": TL.encode(sp_c, vs, 1.2), "stick": TL.encode(st_c, vs, 1.2)}
	var L: Dictionary = game.touch.layout(vs)
	check(L.dash.c.is_equal_approx(dash_c) and is_equal_approx(L.dash.s, 1.3), "冲刺键应在自定义位置 %s" % L.dash.c)
	check(game.touch.speed_rect(vs).get_center().is_equal_approx(sp_c), "倍速键应在自定义位置")
	check(is_equal_approx(game.touch.stick_r(), TL.RADIUS * 1.2), "摇杆行程应按缩放（%.1f）" % game.touch.stick_r())
	# 点冲刺键（按 btn_rects；无头下 HUD 不画，手动按布局补一份）
	game.touch.btn_rects = [[Rect2(dash_c - Vector2(30, 30), Vector2(60, 60)), "dash"], [game.touch.speed_rect(vs), "speed"]]
	var sp0: float = Cfg.play_speed
	await tap(1, win(sp_c))
	await frames(2)
	check(Cfg.play_speed != sp0, "点自定义位置的倍速键应切倍速（%.1f → %.1f）" % [sp0, Cfg.play_speed])
	Cfg.play_speed = sp0
	game.dash_cd = 0.0
	await tap(2, win(dash_c))
	await frames(2)
	check(game.dash_cd > 0.0, "点自定义位置的冲刺键应冲刺（dash_cd=%.2f）" % game.dash_cd)
	# 摇杆改过位置：按在摇杆圈里 → 中心就是摇杆圈，偏右按下立刻有向右的输入
	game.state = game.S.PLAY
	var ev := InputEventScreenTouch.new()
	ev.index = 3
	ev.position = win(st_c + Vector2(40, 0))
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	check(game.touch.stick_id >= 0 and game.touch.stick_origin.is_equal_approx(st_c), "固定摇杆：中心应是摇杆圈（%s）" % game.touch.stick_origin)
	check(game.touch.move_vec().x > 0.4, "固定摇杆：圈内偏右按下应有向右输入（%s）" % game.touch.move_vec())
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(2)
	# 触屏选卡：顶部中央计时器让位
	game.progression.open_relic_choice()
	await frames(2)
	check(game.state != game.S.CHOICE or game.hud_view.panel_over_top(), "触屏选卡时 panel_over_top 应为真")
	game.panel.visible = false
	game.state = game.S.PLAY
	check(not game.hud_view.panel_over_top(), "对局中 panel_over_top 应为假")
	# 设置页触屏行的 ◀ / ▶（用户 10-13「设置大小不能减小只能放大」：触屏行宽约 1100，◀ 原来被判成 ▶）：
	# 画面页「界面大小」点 ◀ 减、点 ▶ 加。「战斗画面缩放」10-22 起不在设置里露出（键保留，下面仍直接调它验缩放逻辑）
	game.settings.open()
	game.settings._set_tab(1)
	await frames(3)
	check(not game.settings.cur.any(func(i): return game.settings.ROWS[i].key == "cam_zoom_pct"), "画面页不应再有战斗画面缩放行（设置精简 16 行）")
	for key in ["ui_size_pct"]:
		var si := -1
		for k in game.settings.cur.size():
			if game.settings.ROWS[game.settings.cur[k]].key == key:
				si = k
		check(si >= 0 and si < game.settings.row_rects.size(), "画面页应有 %s 行" % key)
		if si < 0 or si >= game.settings.row_rects.size():
			continue
		game.settings.sel = si
		game.settings._follow()
		await frames(3)
		var rr: Rect2 = game.settings.row_rects[si]
		var vx: float = rr.position.x + rr.size.x - 252.0
		var before: float = Cfg.ui_size_pct if key == "ui_size_pct" else Cfg.cam_zoom() * 100.0
		game.settings._tap(Vector2(vx - 4.0, rr.get_center().y), MOUSE_BUTTON_LEFT)
		await frames(2)
		var mid: float = Cfg.ui_size_pct if key == "ui_size_pct" else Cfg.cam_zoom() * 100.0
		check(mid < before - 0.5, "%s 点 ◀ 应减小（%.0f → %.0f）" % [key, before, mid])
		game.settings._tap(Vector2(vx + 186.0, rr.get_center().y), MOUSE_BUTTON_LEFT)
		await frames(2)
		var after: float = Cfg.ui_size_pct if key == "ui_size_pct" else Cfg.cam_zoom() * 100.0
		check(after > mid + 0.5, "%s 点 ▶ 应增大（%.0f → %.0f）" % [key, mid, after])
	for i in 20:
		game.settings._adjust(game.settings.ROWS.map(func(r): return r.key).find("cam_zoom_pct"), -1)
	check(absf(Cfg.cam_zoom() - 0.8) < 0.001 and absf(game.cam.zoom.x - 0.8) < 0.001, "战斗画面缩放可降到 80%%（%.2f）" % game.cam.zoom.x)
	check(game.view_size().x > game.get_viewport_rect().size.x, "拉远时 view_size 比视口大（地面按它铺满）")
	for i in 20:
		game.settings._adjust(game.settings.ROWS.map(func(r): return r.key).find("ui_size_pct"), -1)
	check(Cfg.ui_size_pct == 80 and Cfg.ui_k < Cfg.UI_K_PHONE * 0.85 and Cfg.phone_ui(), "界面大小 80%% 在手机横屏下确实变小（ui_k=%.3f）" % Cfg.ui_k)
	Cfg.ui_size_pct = 100
	Cfg.cam_zoom_pct = -1
	Cfg.apply()
	game.settings.visible = false
	await frames(2)
	# 编辑页：拖动 / 推开 / 调大小 / 恢复默认 / 完成
	Cfg.touch_layout = {}
	game.settings.open()
	game.settings.open_touch_editor()
	await frames(2)
	var ed: Control = game.settings.editor
	check(ed != null and ed.visible, "编辑页应打开")
	var E: Dictionary = ed.lay()
	ed._press(E.dash.c)
	ed._drag_to(Vector2(-400, 9999))   # 拖出屏幕左下
	ed._release()
	var E2: Dictionary = ed.lay()
	check(inside(E2.dash.c, "dash", 1.0, ed.safe()), "拖出屏幕的冲刺键应夹在安全区内（%s）" % E2.dash.c)
	check(ed.work.has("dash"), "拖动后应记下自定义位置")
	ed._press(E2.dash.c)
	ed._drag_to(E2.pause.c + (E2.dash.c - E2.dash.c))
	ed._drag_to(ed.lay().pause.c)
	ed._release()
	var E3: Dictionary = ed.lay()
	check(not TL.too_close(E3.dash.c, "dash", E3.dash.s, E3.pause.c, "pause", E3.pause.s), "拖到暂停键上的冲刺键应被推开（%s / %s）" % [E3.dash.c, E3.pause.c])
	ed.sel = "dash"
	ed._action("plus")
	ed._action("plus")
	check(is_equal_approx(ed.lay().dash.s, 1.2), "两次「+」后冲刺键应为 120%%（%.2f）" % ed.lay().dash.s)
	for i in 12:
		ed._action("minus")
	check(is_equal_approx(ed.lay().dash.s, TL.S_MIN), "缩小不低于 70%%（%.2f）" % ed.lay().dash.s)
	ed._action("reset")
	check(ed.work.is_empty(), "恢复默认应清空")
	ed.sel = "stats"
	ed._action("plus")
	ed._action("done")
	check(not ed.visible and Cfg.touch_layout.has("stats") and is_equal_approx(float(Cfg.touch_layout.stats.s), 1.1), "完成应写回 Cfg.touch_layout（%s）" % Cfg.touch_layout)
	# 「完成」在按下时关页：同一次点击的松手不能落到设置面板（触屏版松手才算点选，会误改下面那行）
	check(game.settings.eat_release, "编辑页关闭后应吞掉同一次点击的松手")
	var dn0: bool = Cfg.dmg_numbers
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = win(game.settings.size / 2.0)
	Input.parse_input_event(mb)
	await frames(2)
	check(Cfg.dmg_numbers == dn0 and not game.settings.eat_release, "松手被吞掉、没有改到别的设置")
	game.settings.close()
	# 转屏：视口变成 4:3 后 ui_k 跟着重算（_ui_fit），界面根控件撑满新的 UI 区
	get_tree().root.size = Vector2i(960, 720)
	await frames(3)
	check(absf(Cfg.ui_k - Cfg.ui_scale()) < 0.001 and absf(Cfg.ui_k - 1.113) < 0.01, "转成 4:3 后 ui_k 应重算为 1.11（%.3f）" % Cfg.ui_k)
	check(game.hud.size.is_equal_approx(Cfg.ui_size()), "HUD 应撑满新的 UI 区（%s vs %s）" % [game.hud.size, Cfg.ui_size()])
	Cfg.touch_layout = {}
	game.queue_free()
	await frames(3)


## UI 坐标 → 窗口坐标（parse_input_event 的触点按窗口像素给，引擎再按 content_scale 1.15 与界面层 ui_k 换回 UI 坐标）
func win(p: Vector2) -> Vector2:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	return p * Cfg.ui_k * (Vector2(get_tree().root.size) / vis)


func tap(idx: int, pos: Vector2) -> void:
	for pr in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = idx
		e.position = pos
		e.pressed = pr
		Input.parse_input_event(e)
		await get_tree().process_frame
