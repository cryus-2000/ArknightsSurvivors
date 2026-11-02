extends SceneTree
## PV 小样一遍录（不入游戏代码）：边跑边把候选片段存成 jpg，日志实时写进 <out>/pv.log
##   --pv_out=目录 --pv_maxt=秒 --pv_win=起-止,起-止（固定窗口，游戏秒）
## 自动片段：终结技起手（带 60 帧预录 + 起手后 4.5 秒）、大群来袭横幅（6 秒）、最终 Boss 在场且屏内敌弹 ≥ 25（每段 5 秒、间隔 ≥ 6 秒）、
## 9:00 后屏内 ≥ 150 敌（4 秒，最多 3 段）。每段一个目录 rec_<序号>_<类>_t<起始秒>，帧 f0000.jpg 起
var g: Node = null
var out := "."
var maxt := 680.0
var wins: Array = []
var log_f: FileAccess = null
var ring: Array = []      # 最近 PRE 帧（Image）
const PRE := 60
var cur := {}            # 正在录的段：{dir, until, n}
var seg_i := 0
var last_serial := -1
var last_hf := 0
var next_log := 0.0
var boss_last := -99.0
var late_n := 0
var horde_last := -99.0
var win_done := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pv_out="):
			out = a.substr(9)
		if a.begins_with("--pv_maxt="):
			maxt = float(a.substr(10))
		if a.begins_with("--pv_win="):
			for w in a.substr(9).split(","):
				var p: PackedStringArray = w.split("-")
				wins.append([float(p[0]), float(p[1])])
	DirAccess.make_dir_recursive_absolute(out)
	log_f = FileAccess.open(out + "/pv.log", FileAccess.WRITE)
	_log("PVINIT")
	change_scene_to_file.call_deferred("res://game.tscn")


func _log(s: String) -> void:
	log_f.store_line(s)
	log_f.flush()


func _on_screen(p: Vector2) -> bool:
	var d: Vector2 = p - g.ppos
	return absf(d.x) < 1000.0 and absf(d.y) < 560.0


func _start(kind: String, dur: float, pre: bool) -> void:
	if not cur.is_empty():
		cur.until = maxf(float(cur.until), g.t + dur)   # 正在录：延长
		_log("PVEXT %s t=%.2f" % [kind, g.t])
		return
	seg_i += 1
	var t0: float = g.t - (float(ring.size()) / 30.0 if pre else 0.0)
	var d := "%s/rec_%02d_%s_t%05.1f" % [out, seg_i, kind, t0]
	DirAccess.make_dir_recursive_absolute(d)
	cur = {"dir": d, "until": g.t + dur, "n": 0}
	if pre:
		for im in ring:
			im.save_jpg("%s/f%04d.jpg" % [d, int(cur.n)], 0.92)
			cur.n = int(cur.n) + 1
	ring.clear()
	_log("PVSEG %s dir=%s t0=%.3f pre=%d" % [kind, d.get_file(), t0, int(cur.n)])


func _process(_dt: float) -> bool:
	if g == null:
		g = current_scene
		if g == null or not ("autotest" in g):
			if Engine.get_process_frames() % 300 == 0:
				_log("PVWAIT f=%d scene=%s" % [Engine.get_process_frames(), str(g)])
			g = null
			return false
	if g.t > maxt:
		_log("PVDONE t=%.1f" % g.t)
		quit()
		return false
	var playing: bool = g.state == g.S.PLAY
	# 固定窗口
	for i in wins.size():
		var w: Array = wins[i]
		if g.t >= float(w[0]) and g.t < float(w[1]) and not win_done.has(i):
			win_done[i] = true
			_start("win", float(w[1]) - g.t, false)
	var u = g.ult
	if u != null and playing:
		if int(u.serial) != last_serial:
			if last_serial >= 0:
				_log("PVULT t=%.3f kind=%s caster=%s" % [g.t, str(u.kind), str(u.caster.id) if u.caster != null else "-"])
				_start("ult_" + (str(u.caster.id) if u.caster != null else "x"), 4.5, true)
			last_serial = int(u.serial)
		var hf: int = int(u._hf_n[0])
		if hf > 0 and last_hf == 0:
			_log("PVHF t=%.3f seg=%d n=%d" % [g.t, seg_i, int(cur.get("n", -1))])
		last_hf = hf
	var ne := 0
	var eb := 0
	if playing:
		for e in g.enemies:
			if not e.dead and _on_screen(e.pos):
				ne += 1
		for b in g.ebullets:
			if _on_screen(b.pos):
				eb += 1
		if g.horde_warn > 0.6 and g.t - horde_last > 20.0:
			horde_last = g.t
			_start("horde", 6.0, false)
		if g.final_boss != null and not g.final_boss.dead and eb >= 25 and g.t - boss_last > 11.0:
			boss_last = g.t
			_start("boss", 5.0, false)
		if g.t >= 540.0 and ne >= 150 and late_n < 3 and cur.is_empty():
			late_n += 1
			_start("late", 4.0, false)
	if g.t >= next_log:
		next_log = g.t + 0.5
		var bs := []
		for b in g.bosses:
			if not b.dead:
				bs.append(str(b.type))
		_log("PVLOG t=%.1f lamp=%d ne=%d eb=%d boss=%s wheel=%s st=%d" % [g.t, int(g.lamp), ne, eb, ",".join(bs), str(g.wheel.is_open), int(g.state)])
	# 存帧：录段中直接存；否则进预录环
	var img: Image = g.get_viewport().get_texture().get_image()
	if not cur.is_empty():
		img.save_jpg("%s/f%04d.jpg" % [cur.dir, int(cur.n)], 0.92)
		cur.n = int(cur.n) + 1
		if g.t >= float(cur.until):
			_log("PVEND dir=%s n=%d t=%.2f" % [str(cur.dir).get_file(), int(cur.n), g.t])
			cur = {}
	elif playing:
		ring.append(img)
		if ring.size() > PRE:
			ring.pop_front()
	return false
