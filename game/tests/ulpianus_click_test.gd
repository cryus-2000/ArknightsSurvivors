extends Node
## 乌尔比安 S3 左键点击释放（10-26 用户「三技能要设置成鼠标点击也能够触发」）：godot --headless --path game res://tests/ulpianus_click_test.tscn -- --balance --op=ulpianus
## 技力满时左键点场地 = 以点击处为落点放 S3（吞掉这次点击）；技力没满 / 点在 HUD（顶栏、编队栏、声呐、暂停键）上 / 开了手动普攻 / 触屏时不接管，点击照旧；
## E 键照旧能放。全部通过时打印 "ULPIANUS CLICK failures=0"。

var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var o = game.squad.get_op("ulpianus")
	ok(o != null and o.is_leader, "乌尔比安是队长（--op=ulpianus）")
	if o != null:
		run(o)
	print("%d checks, %d failed" % [n, fails])
	print("ULPIANUS CLICK failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func reset(o, full: bool) -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	game.enemies_sys.build_grid()
	o.elite = 2
	o.pos = home()   # 视口中心对应的世界点（测试里游戏 process 停着，相机不跟人，按当前画布变换反算）
	game.ppos = o.pos
	o.face = 1.0
	if o.hw.has("anchor"):
		o.hw.anchor = {}
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.manual_buf = 0.0
	o.sp = [0.0, 0.0, o.sp_need(2) if full else o.sp_need(2) * 0.5]
	game.state = game.S.PLAY


func click(vp: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = vp
	ev.global_position = vp
	return ev


func home() -> Vector2:
	# 游戏 process 停着时相机不跟人、缩放也没初始化：手动把相机摆到 (1500, 900)、缩放 1，再按画布变换反算
	game.cam.zoom = Vector2.ONE
	game.cam.global_position = Vector2(1500, 900)
	game.cam.force_update_scroll()
	game.get_viewport().canvas_transform = Transform2D(0.0, game.get_viewport().get_visible_rect().size * 0.5 - Vector2(1500, 900))
	return Vector2(1500, 900)


## 世界坐标 → 视口坐标（点击事件的 position）
func vp_of(w: Vector2) -> Vector2:
	return game.get_viewport().get_canvas_transform() * w


func cast_started(o) -> bool:
	return not o.hw.get("anchor", {}).is_empty() or o.manual_buf > 0.0 or o.sp[2] < o.sp_need(2) * 0.5 or o.skill_active_left(2) > 0.0


func run(o) -> void:
	# 1. 技力满、点场地：放出，落点 = 点击处方向
	reset(o, true)
	var p0: Vector2 = o.pos
	var tgt: Vector2 = p0 + Vector2(260, 30)
	var vp := vp_of(tgt)
	ok(not game.hud_view.blocks_click(vp / Cfg.ui_k), "场地上的点不算 HUD（%s）" % vp)
	ok(game.doctor.click_skill(vp), "技力满时左键点场地被接管")
	var dir_ok := true
	for i in 60:
		game.enemies_sys.build_grid()
		o.follow(1.0 / 60.0, o.pos)
		o.update(1.0 / 60.0)
		var an: Dictionary = o.hw.get("anchor", {})
		if not an.is_empty() and an.has("to"):
			dir_ok = dir_ok and ((an.to as Vector2) - p0).normalized().dot((tgt - p0).normalized()) > 0.95
	ok(cast_started(o) or o.pos.x > p0.x + 100.0, "左键点击后 S3 放出（技力 %.1f / %.1f，位置 %s）" % [o.sp[2], o.sp_need(2), o.pos])
	ok(dir_ok, "锚掷向点击方向")
	ok(o.pos.x > p0.x + 100.0, "冲向点击处（x %.0f → %.0f）" % [p0.x, o.pos.x])
	# 2. 技力没满：不接管、不放
	reset(o, false)
	ok(not game.doctor.click_skill(vp), "技力没满时点击不被接管（点击照旧）")
	ok(not cast_started(o) or o.sp[2] >= o.sp_need(2) * 0.5, "技力没满时不放")
	# 3. 点在 HUD 上：不接管
	reset(o, true)
	var vs: Vector2 = game.hud.size
	var huds := {"顶栏左（生命 / 灯火）": Vector2(120, 40), "右下编队栏": Vector2(vs.x - 60, vs.y - 60), "左下声呐": Vector2(16 + 78 + 8, vs.y - 78 - 24), "顶部中央计时": Vector2(vs.x * 0.5, 30)}
	if game.pause_btn.has_area():
		huds["暂停键"] = game.pause_btn.get_center()
	for k in huds:
		ok(game.hud_view.blocks_click(huds[k]), "%s 算 HUD" % k)
		ok(not game.doctor.click_skill(huds[k] * Cfg.ui_k), "点在%s上不放技能" % k)
	ok(o.sp[2] >= o.sp_need(2), "点 HUD 后技力仍满（没放）")
	# 5. 走 game._unhandled_input 整条路：事件被吞掉并放出
	reset(o, true)
	game._unhandled_input(click(vp))
	ok(cast_started(o), "game._unhandled_input 左键点场地放 S3（技力 %.1f，manual_buf %.2f，持续 %.2f）" % [o.sp[2], o.manual_buf, o.skill_active_left(2)])
	# 6. E 键照旧
	reset(o, true)
	ok(game.doctor.try_manual_skill(Vector2.INF), "E 键入口照旧可用")
