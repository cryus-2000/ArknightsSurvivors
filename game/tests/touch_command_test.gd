extends Node
## 触屏指挥「点选 → 预选 → 再点确认」回归（docs/315，11-07 用户「手机端指挥圆盘一点不明确」）。
## 全程走 Input.parse_input_event 的真实触点（Godot 缺省 emulate_mouse_from_touch，会跟着补一个模拟鼠标键，正是旧流程「点完就下令」的来源）：
##   点「指挥」键 → 点圆盘「集火」→ 手指抬起后不能下令 → 点精英 B = 预选 → 点精英 A = 换预选 → 再点 A = 下令（order_target = A）；
##   「部署」：点地面 = 预选 → 点别处 = 换落点 → 再点落点 = 下令（order_pos ≈ 落点）；
##   取消：信息板「取消」键、集火时点空白；圈外的地面点了不预选。手机比例（1560×720）一遍
var failures := 0
var game: Node


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("TOUCH COMMAND: " + what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 2) -> void:
	for i in n:
		await get_tree().process_frame


func hold_play(n: int) -> void:
	for i in n:
		game.state = game.S.PLAY
		game.pending_levelups = 0
		game.pending_chests = 0
		game.invuln = 1.0
		await get_tree().process_frame


## 一次点按（按下 + 抬起），p = UI 坐标
func tap(p: Vector2, idx := 0) -> void:
	# 事件坐标是窗口坐标：视口有拉伸时（无头 1560×720 窗口 → 视口按比例缩放）要乘回窗口 / 视口比
	var sp: Vector2 = p * Cfg.ui_k * Vector2(get_tree().root.size) / get_viewport().get_visible_rect().size
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = idx
		e.position = sp
		e.pressed = pressed
		Input.parse_input_event(e)
		await hold_play(2)


func cmd_btn() -> Vector2:
	for b in game.touch.btn_rects:
		if str(b[1]) == "cmd":
			return (b[0] as Rect2).get_center()
	return Vector2.INF


func wheel_item(id: String) -> Vector2:
	var W = game.wheel
	var i: int = W.item_index(id)
	return W.center + Vector2.from_angle(deg_to_rad(float(W.ANG[i]))) * (W.R_IN + W.R_OUT) * 0.5 * W._k()


func target_pt(e: Dictionary) -> Vector2:
	return game.hud_ct() * e.pos + Vector2(0, -float(e.r) * 0.5)


func begin(id: String) -> void:
	game.squad.stamina = 1.0
	var cb: Vector2 = cmd_btn()
	check(cb != Vector2.INF, "找不到「指挥」键")
	await tap(cb, 3)
	check(game.wheel.is_open, id + "：点「指挥」键应打开圆盘")
	await tap(wheel_item(id), 4)
	check(game.pick.active and game.pick.tap, id + "：选完指令应进入点选（active=%s tap=%s）" % [game.pick.active, game.pick.tap])
	check(not game.pick.pre_set, id + "：手指抬起 / 模拟鼠标键不能直接预选或下令")


func run() -> void:
	check(Cfg.touch_device(), "--touch 应开启触屏")
	get_tree().root.size = Vector2i(1560, 720)
	await frames(2)
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(6)
	await hold_play(4)
	check(game.touch.active, "触屏应开启")
	check(game.pick.proto_on(), "command/target_proto 应开")
	var A: Dictionary = game.spawner.spawn_enemy("knight", game.ppos + Vector2(260, -60))
	var B: Dictionary = game.spawner.spawn_enemy("mimic", game.ppos + Vector2(-300, 60))
	A.age = 5.0
	B.age = 5.0
	await hold_play(4)
	# ---- 集火
	await begin("focus")
	await tap(target_pt(B))
	check(game.pick.active and game.pick.pre_set and is_same(game.pick.pre_target, B), "集火：点 B 应预选 B")
	check(game.squad.order_kind != "focus", "集火：预选时还不能下令")
	await tap(target_pt(A))
	check(game.pick.active and is_same(game.pick.pre_target, A), "集火：点 A 应换成预选 A")
	await tap(target_pt(A))
	check(not game.pick.active, "集火：再点 A 应结束选点")
	check(game.squad.order_kind == "focus" and is_same(game.squad.order_target, A), "集火：应对 A 下令（kind=%s）" % game.squad.order_kind)
	# ---- 集火：点空白 = 取消
	if game.squad.has_method("clear_order"):
		game.squad.clear_order()
	await begin("focus")
	var vs: Vector2 = game.hud.size
	await tap(Vector2(vs.x * 0.62, vs.y * 0.12))
	check(not game.pick.active, "集火：点空白应取消")
	# ---- 部署
	await hold_play(30)
	await begin("point")
	var ct: Transform2D = game.hud_ct()
	var p1: Vector2 = ct * (game.ppos + Vector2(200, -80))
	var p2: Vector2 = ct * (game.ppos + Vector2(-220, 90))
	await tap(p1)
	check(game.pick.active and game.pick.pre_set, "部署：点地面应预选落点")
	check(game.squad.order_kind != "point", "部署：预选时还不能下令")
	await tap(p2)
	var w2: Vector2 = game.hud_ct().affine_inverse() * p2
	check(game.pick.active and game.pick.pre_pt.distance_to(w2) < 4.0, "部署：点别处应换落点")
	await tap(game.hud_ct() * game.pick.pre_pt)
	check(not game.pick.active, "部署：再点落点应结束选点")
	check(game.squad.order_kind == "point" and game.squad.order_pos.distance_to(w2) < 40.0, "部署：应在第二个落点下令（kind=%s pos=%s）" % [game.squad.order_kind, game.squad.order_pos])
	# ---- 部署：圈外不预选；「取消」键
	await hold_play(30)
	await begin("point")
	var far: Vector2 = game.hud_ct() * (game.ppos + Vector2(load("res://scripts/core/balance.gd").v("command/order_r", 560.0) + 200.0, 0))
	if Rect2(Vector2.ZERO, game.hud.size).has_point(far):
		await tap(far)
		check(game.pick.active and not game.pick.pre_set, "部署：圈外的地面不该预选")
	await hold_play(2)
	check(game.pick._cancel_r.has_area(), "部署：信息板应有「取消」键")
	var kind0: String = game.squad.order_kind
	var pos0: Vector2 = game.squad.order_pos
	await tap(game.pick._cancel_r.get_center())
	check(not game.pick.active, "部署：点「取消」应退出")
	check(game.squad.order_kind == kind0 and game.squad.order_pos == pos0, "部署：取消不应改指令")
	print("TOUCH COMMAND: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
