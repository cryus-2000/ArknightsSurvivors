extends Node
## 寻访「用生机细胞兑换凭证」录屏（10-25）：入口（有细胞、没凭证）→ 点兑换 → 凭证 +1 → 寻访一次 → 拉包 → 揭示。
## 用法：tools/godot_runner.py 静音离屏启动，--fixed-fps 60 --roster=start5 --shotdir=<已存在目录> [--touch]；每 2 帧存一张 rec_NNNN.png（30 fps），tools/probes/headhunt_exchange_rec.py 转 mp4

const Headhunt = preload("res://scripts/screens/headhunt.gd")
var host
var out := ""
var n := 0
var frame := 0


func _grab() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	frame += 1
	if frame % 2 == 0:
		get_viewport().get_texture().get_image().save_png("%s/rec_%04d.png" % [out, n])
		n += 1


func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await _grab()


func _click(act) -> void:
	var box := Rect2()
	for r in host.hh.rects:
		if typeof(r[1]) == typeof(act) and r[1] == act:
			box = r[0]
			break
	assert(box.size.x > 0.0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = (box.get_center() * host.hh._k + host.hh._off) * Cfg.ui_k
	host.hh.input(ev)


func _ready() -> void:
	Headhunt.clock_frames = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			out = arg.substr(10)
	assert(out != "")
	Cfg.meta_dev = "dtest"
	Cfg.meta_earned = {"dtest": 40}
	Cfg.meta_bought = {}
	Cfg.roster_tickets = {}
	host = preload("res://scripts/screens/hunt_host.gd").new()
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.open()
	host.show()
	await _wait(1.4)
	_click("buy")   # 40 个细胞 → 兑换 1 张（−15）
	await _wait(1.3)
	_click("buy")   # 再兑 1 张（−15，剩 10，不够了）
	await _wait(1.4)
	_click("buy")   # 不够：只响一声，什么也不变
	await _wait(0.8)
	_click(0)       # 寻访一次（1 张）
	await _wait(6.5)
	print("HHREC frames=%d tickets=%d cells=%d" % [n, Roster_tickets(), Meta_avail()])
	get_tree().quit()


func Roster_tickets() -> int:
	return int(Cfg.roster_tickets.get("hunt", 0))


func Meta_avail() -> int:
	return preload("res://scripts/core/meta.gd").available()
