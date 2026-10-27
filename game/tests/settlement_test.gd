extends Node
const RS = preload("res://scripts/run/run_stats.gd")
const Screen = preload("res://scripts/screens/settlement_screen.gd")
class Probe extends Screen:
	var action_called := ""
	func _action(action: String) -> void:
		action_called = action

var game
var fails := 0
func ok(value: bool, label: String) -> void:
	if not value:
		fails += 1
		printerr("FAIL ",label)
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_process(false)
	game.state = game.S.WIN
	game.state_age = 3.0
	var raw := RS.fake_raw()
	for id in ["texas","lumen","exusiai"]:
		raw.ops.append({"id":id,"name":{"texas":"德克萨斯","lumen":"流明","exusiai":"能天使"}[id],"en":id,"col":[0.5,0.7,0.9],"leader":false,"t":500.0,"left":600.0})
	var m := RS.model(raw)
	var s = game.settlement
	s.set_model(m)
	s.tick(1.0)
	ok(s.rows.size()==7,"all seven historic operators")
	ok(s.rows[0].leader,"leader first")
	var saved_tex: Dictionary = game.tex.duplicate()
	for texture_key in game.tex:
		if game.tex[texture_key] is Texture2D and not game.tex[texture_key] is CanvasTexture:
			var wrapped := CanvasTexture.new()
			wrapped.diffuse_texture=game.tex[texture_key]
			game.tex[texture_key]=wrapped
	s.set_model(m)
	ok(s.art.size()==7,"normal-map CanvasTexture supplies all seven portraits")
	game.tex=saved_tex
	var rng_state = game.rng.state
	s.select(6)
	ok(s.selected==6 and s.offset>600,"last operator reachable")
	s.scroll(10000)
	ok(s.offset==s.max_offset(),"right clamp")
	s.scroll(-100)
	ok(s.offset==0,"left clamp")
	s.elapsed=0.9
	s._pointer(Vector2(700,400),true)
	s._drag(Vector2(200,400))
	s._pointer(Vector2(200,400),false)
	ok(s.offset==500 and not s.dragging,"drag scroll releases")
	ok(game.rng.state==rng_state,"visual navigation preserves RNG")
	var probe := Probe.new(game)
	probe.set_model(m)
	var key := InputEventKey.new()
	key.pressed=true
	key.keycode=KEY_F
	probe.input(key)
	ok(probe.action_called=="" and probe.press_id=="meta","button press shows its pressed state before acting")
	probe.tick(0.2)   # 按下态 PRESS_T 后才执行（10-28 底栏按钮反馈）
	ok(probe.action_called=="meta","game-menu controller Y opens growth")
	var mv := InputEventMouseMotion.new()
	mv.position = (probe._btn_rect(probe._buttons()[probe._buttons().size() - 1]).get_center() * probe.scale + probe.origin) * Cfg.ui_k
	probe.input(mv)
	ok(probe.hover=="hunt","mouse hover highlights the hovered footer button")
	var down := InputEventKey.new()
	down.pressed=true
	down.keycode=KEY_DOWN
	probe.input(down)
	ok(probe.focus==probe._buttons().size() - 1,"down moves keyboard / pad focus into the footer")
	key.keycode=KEY_END
	s.input(key)
	ok(s.selected==6,"public keyboard selects final operator")
	s.select(0)
	var touch := InputEventScreenTouch.new()
	touch.position=(s.origin+Vector2(700,400)*s.scale)*Cfg.ui_k
	touch.pressed=true
	s.input(touch)
	var drag := InputEventScreenDrag.new()
	drag.position=(s.origin+Vector2(200,400)*s.scale)*Cfg.ui_k
	s.input(drag)
	touch.pressed=false
	touch.position=drag.position
	s.input(touch)
	ok(s.offset>=499,"public touch drag scales to viewport")
	var emulated := InputEventMouseButton.new()
	emulated.device=InputEvent.DEVICE_ID_EMULATION
	emulated.pressed=true
	emulated.button_index=MOUSE_BUTTON_LEFT
	emulated.position=touch.position
	s.input(emulated)
	ok(not s.dragging,"emulated mouse cannot restart touch gesture")
	s._records()
	ok(game.run_stats.open and not s.squad_canvas.visible,"records hide scrolling foreground immediately")
	game.run_stats.close()

	var fast := m.duplicate(true)
	fast.downs=0
	fast.t=700.0
	for tier in 3:
		ok(Screen.grade(fast,tier)==["S","SS","SSS"][tier],"clear rating: no downs, within 12:30")
	var downed := fast.duplicate(true)
	downed.downs=1
	var slow := fast.duplicate(true)
	slow.t=760.0
	for tier in 3:
		ok(Screen.grade(downed,tier)==["A","S","SS"][tier],"clear rating: downed once drops one grade")
		ok(Screen.grade(slow,tier)==["A","S","SS"][tier],"clear rating: over 12:30 drops one grade")
	var edge := fast.duplicate(true)
	edge.t=750.0
	ok(Screen.grade(edge,0)=="S","clear rating: exactly 12:30 is still top")
	var dead := m.duplicate(true)
	dead.result="dead"
	dead.bosses=[]
	ok(Screen.grade(dead,0)=="C","early defeat rating")
	dead.bosses=[{"name":"mid","t1":20.0}]
	ok(Screen.grade(dead,0)=="B","mid defeat rating")
	# Screenshot mode uses the actual result draw path, offscreen and silent via runner.
	s.cells=28
	s.vouchers=4
	s.select(0)
	for arg in OS.get_cmdline_user_args():
		if arg == "--settlement-dead":
			game.state=game.S.DEAD
			s.model.result="dead"
		if arg == "--settlement-last":
			s.select(6)
	s.tick(1.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settlement-shot="):
			game.hud.queue_redraw()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.get_slice("=",1))
	game.queue_free()
	await get_tree().process_frame
	print("SETTLEMENT failures=%d" % fails)
	get_tree().quit(1 if fails else 0)
