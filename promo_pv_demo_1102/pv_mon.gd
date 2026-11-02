extends SceneTree
## PV 小样录帧监视（scratchpad，不入库）：--pv_out=目录 --pv_maxt=秒 --pv_rec=名@起@长（可多个）
var g: Node = null
var out := "."
var maxt := 660.0
var recs := []
var nohud := false
var last_serial := -1
var last_hf := 0
var next_log := 0.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pv_out="):
			out = a.substr(9)
		if a.begins_with("--pv_maxt="):
			maxt = float(a.substr(10))
		if a == "--pv_nohud":
			nohud = true
		if a.begins_with("--pv_rec="):
			var p: PackedStringArray = a.substr(9).split("@")
			recs.append({"name": p[0], "t0": float(p[1]), "dur": float(p[2]), "n": 0})
			DirAccess.make_dir_recursive_absolute(out + "/rec_" + p[0])

func _on_screen(p: Vector2) -> bool:
	var d: Vector2 = p - g.ppos
	return absf(d.x) < 1000.0 and absf(d.y) < 560.0

func _process(_dt: float) -> bool:
	if g == null:
		g = current_scene
		if g == null or not ("autotest" in g):
			g = null
			return false
	for r in recs:
		if g.t >= float(r.t0) and g.t < float(r.t0) + float(r.dur):
			g.get_viewport().get_texture().get_image().save_jpg("%s/rec_%s/f%04d.jpg" % [out, r.name, int(r.n)], 0.95)
			r.n = int(r.n) + 1
	if nohud and g.hud.visible:
		g.hud.visible = false
	if g.t > maxt:
		print("PVDONE")
		quit()
		return false
	var u = g.ult
	if u != null:
		if int(u.serial) != last_serial:
			if last_serial >= 0:
				print("PVULT t=%.3f f=%d kind=%s caster=%s" % [g.t, Engine.get_process_frames(), str(u.kind), str(u.caster.id) if u.caster != null else "-"])
			last_serial = int(u.serial)
		var hf: int = int(u._hf_n[0])
		if hf > 0 and last_hf == 0:
			print("PVHF t=%.3f f=%d" % [g.t, Engine.get_process_frames()])
		last_hf = hf
	if g.t >= next_log:
		next_log = g.t + 0.5
		var ne := 0
		for e in g.enemies:
			if not e.dead and _on_screen(e.pos):
				ne += 1
		var eb := 0
		for b in g.ebullets:
			if _on_screen(b.pos):
				eb += 1
		var bs := []
		for b in g.bosses:
			if not b.dead:
				bs.append(str(b.type))
		print("PVLOG t=%.1f lamp=%d ne=%d eb=%d boss=%s wheel=%s st=%d" % [g.t, int(g.lamp), ne, eb, ",".join(bs), str(g.wheel.is_open), int(g.state)])
	return false
