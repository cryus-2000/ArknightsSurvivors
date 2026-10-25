extends Node
## docs/156 事件插画接入自审：依次打开 6 件事件的面板各截一张（build/<--shots-out>/e_<id>.png），
## 并记录打开前 / 打开中 / 关面板后的显存（RENDER_TEXTURE_MEM_USED），确认插画按需加载、关面板即释放。

const IDS := ["opening", "madness", "knight_stay", "heart", "ascend", "glimmer"]
var g
var out := ""


func _wait(sec: float) -> void:
	for k in int(sec * 60.0):
		await get_tree().process_frame


func _vram() -> float:
	return Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0


func _ready() -> void:
	var od := "event_cg_shots"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots-out="):
			od = arg.get_slice("=", 1)
	out = ProjectSettings.globalize_path("res://../build/" + od)
	DirAccess.make_dir_recursive_absolute(out)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await _wait(1.5)
	g.state = g.S.PLAY
	g.pending_levelups = 0
	g.pending_chests = 0
	var base := _vram()
	var peak := 0.0
	for id in IDS:
		g.endg.open(id)
		await _wait(0.7)
		peak = maxf(peak, _vram())
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("e_%s.png" % id))
		g.panel.visible = false
		g.state = g.S.PLAY
		await _wait(0.2)
	var after := _vram()
	print("EVENT CG VRAM base=%.2f peak=%.2f after_close=%.2f MB loaded=%s" % [base, peak, after, str(g.panel_ui.ev_cg != null)])
	get_tree().quit(0)
