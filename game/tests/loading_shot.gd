extends Node
## 进局载入页截图（11-07 像素海面改版验收）：把 screens/loading_screen.gd 放进 SubViewport，按 --ls_p 的每个进度喂进去、等浪头推完再存一张。
##   godot --path game --fixed-fps 30 res://tests/loading_shot.tscn -- --ls_dir=<目录> --ls_w=1280 --ls_h=720 [--ls_p=0.35,1.0]
## 不进玩法、不改存档
var vp: SubViewport
var ls
var dir := ""
var plist: Array = [0.35, 1.0]
var idx := 0
var frames := 0


func _ready() -> void:
	var w := 1280
	var h := 720
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ls_dir="):
			dir = a.substr(9)
		elif a.begins_with("--ls_w="):
			w = int(a.substr(7))
		elif a.begins_with("--ls_h="):
			h = int(a.substr(7))
		elif a.begins_with("--ls_p="):
			plist = Array(a.substr(7).split(",")).map(func(x): return float(x))
	DirAccess.make_dir_recursive_absolute(dir)
	vp = SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	ls = load("res://scripts/screens/loading_screen.gd").new()
	vp.add_child(ls)
	ls.size = Vector2(w, h)
	ls.begin()


func _process(_dt: float) -> void:
	frames += 1
	if idx >= plist.size():
		get_tree().quit()
		return
	if frames == 2:
		ls.set_progress(float(plist[idx]), "构建战场", Vector2i(int(float(plist[idx]) * 40.0), 40))
	if frames == 50:
		vp.get_texture().get_image().save_png(dir + "/ls_%dx%d_p%03d.png" % [vp.size.x, vp.size.y, int(float(plist[idx]) * 100.0)])
		idx += 1
		frames = 0
