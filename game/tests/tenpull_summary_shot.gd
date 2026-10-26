extends Node
## 十连总览截图（10-26 设计自审）：--roster=new 下做一次新手十连，直接切到十人总览，等 3 秒截 shot_tenpull_summary.png。
## 用法：tools/godot_runner.py 静音离屏启动，--roster=new --shotdir=<已存在目录>（手机加 --touch，1480×720）

func _ready() -> void:
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			out = arg.substr(10)
	assert(out != "")
	var host = preload("res://scripts/screens/hunt_host.gd").new()
	add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.open()
	host.show()
	host.hh._act(0)
	host.hh._summary()
	host.hh._tr = ""
	for i in 200:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/shot_tenpull_summary.png")
	print("TENSHOT mode=%s n=%d" % [host.hh.mode, host.hh.results.size()])
	get_tree().quit()
