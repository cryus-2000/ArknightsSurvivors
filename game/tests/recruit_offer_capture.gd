extends Node
## 入队邀请二选一截图（docs/252 验收用，不进快检）：铜印 / 银印 / 事件三种来源各存一张 PNG，另存一张键盘焦点在「婉拒」上的。
##   桌面：godot --path game --resolution 1280x720 res://tests/recruit_offer_capture.tscn -- --balance --seed=1 --op=eyjafjalla --shot_dir=<目录>
##   手机：同上加 --touch --resolution 1170x540
## 有窗口（截图要画面），本机用 tools/godot_runner 起（窗口放副屏 / 屏幕外、静音）；云端用 xvfb-run。

var game: Node
var frames := 0
var step := 0
var wait := 0
var dir := "res://../build/recruit_offer_shots"
var tag := "desktop"
const STEPS := [["copper", "skadi", -1], ["silver", "wisadel", -1], ["event", "suzuran", -1], ["copper", "texas", 1]]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
		if a == "--touch":
			tag = "phone"
	DirAccess.make_dir_recursive_absolute(dir)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames < 30:
		return
	if frames == 30:
		game.set_process(false)   # 停住对局（机器人不会替我们选）：卡片与 HUD 仍会画，下面自己催重画
	for c in game.panel_box.get_children():
		c.queue_redraw()
	game.panel_fg.queue_redraw()
	game.panel_tip.queue_redraw()
	game.hud.queue_redraw()
	game.panel_ui.animate_cards(1.0 / 60.0)
	if wait > 0:
		wait -= 1
		if wait == 0:
			var s: Array = STEPS[step]
			get_viewport().get_texture().get_image().save_png(dir + "/%s_%s%s.png" % [tag, s[0], "_focus" if int(s[2]) >= 0 else ""])
			print("SHOT ", s[0])
			game.panel.visible = false
			game.state = game.S.PLAY
			step += 1
		return
	if step >= STEPS.size():
		get_tree().quit()
		return
	var st: Array = STEPS[step]
	game.progression.open_offer({"src": st[0], "id": st[1]})
	if int(st[2]) >= 0:
		game.nav_sel = int(st[2])
		game.kb_nav = true
	game.panel_ui.motion.skip()
	wait = 30
