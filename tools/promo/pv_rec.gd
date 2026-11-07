extends SceneTree
## PV 实机录制监视（11-08，60 秒主版 / 15 秒竖版；不进游戏代码）：跑一局 game.tscn，按时间窗把每帧存成 jpg，
## 同时记下这段里真正放出的音效（Sfx.trace，渲染帧号 → 段内帧号），后期离线混音。
## 参数（跟在 -- 之后，和 --balance 等游戏参数放一起）：
##   --pv_out=目录            输出：<目录>/seg_<序号>_<类>_t<起始秒>/f00000.jpg … + sfx.json，<目录>/pv.log
##   --pv_maxt=秒             到点退出
##   --pv_win=起-止,起-止      固定录制窗口（游戏秒）
##   --pv_rtfrom=秒           从这一秒起才开预录环（和游戏的 --rtfrom 一致，快进段不抓图）
##   --pv_ult=秒,秒            到点把终结技能量充满（机器人随即自动放）
##   --pv_autoult             每次终结技起手单独录一段（预录 90 帧 + 起手后 5 秒）
##   --pv_choice              三选一面板打开时录一段（预录 30 帧，关掉后再录 2.5 秒）
##   --pv_beacon              灯标开始充能时录一段（预录 60 帧，点亮后再录 3 秒）
##   --pv_bossult=比例         中期 Boss 生命低于这个比例时充满终结技一次（击杀镜头）
##   --pv_ring=秒:只数:半径    到点在队长四周一圈刷普通怪（开场包围）
##   --pv_elite=秒:种类:dx:dy  到点在队长旁刷一只精英（指挥集火镜头）
var g: Node = null
var sfx: Node = null
var out := "."
var maxt := 120.0
var rtfrom := 0.0
var wins: Array = []
var ult_at: Array = []
var auto_ult := false
var rec_choice := false
var rec_beacon := false
var boss_ult := -1.0
var boss_ult_done := false
var ring_spec: Array = []
var elite_spec: Array = []
var log_f: FileAccess = null
var ring: Array = []          # [Image, 渲染帧号, 游戏秒]
var ring_max := 0
var cur := {}                 # {dir, kind, until, n, f0, ts}
var seg_i := 0
var last_serial := -1
var last_hf := 0
var next_log := 0.0
var win_done := {}
var choice_on := false
var choice_end := -1.0
var beacon_rec := {}          # 已录过的灯标（按 pos 字符串）
var beacon_until := -1.0
var trim_at := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pv_out="):
			out = a.substr(9)
		elif a.begins_with("--pv_maxt="):
			maxt = float(a.substr(10))
		elif a.begins_with("--pv_rtfrom="):
			rtfrom = float(a.substr(12))
		elif a.begins_with("--pv_win="):
			for w in a.substr(9).split(",", false):
				var p: PackedStringArray = w.split("-")
				wins.append([float(p[0]), float(p[1])])
		elif a.begins_with("--pv_ult="):
			for v in a.substr(9).split(",", false):
				ult_at.append(float(v))
		elif a == "--pv_autoult":
			auto_ult = true
		elif a == "--pv_choice":
			rec_choice = true
		elif a == "--pv_beacon":
			rec_beacon = true
		elif a.begins_with("--pv_bossult="):
			boss_ult = float(a.substr(13))
		elif a.begins_with("--pv_ring="):
			ring_spec = Array(a.substr(10).split(":"))
		elif a.begins_with("--pv_elite="):
			elite_spec = Array(a.substr(11).split(":"))
	ring_max = 90 if auto_ult else (60 if (rec_beacon or rec_choice) else 0)
	DirAccess.make_dir_recursive_absolute(out)
	log_f = FileAccess.open(out + "/pv.log", FileAccess.WRITE)
	_log("PVINIT args=%s" % " ".join(OS.get_cmdline_user_args()))
	change_scene_to_file.call_deferred("res://game.tscn")


func _log(s: String) -> void:
	log_f.store_line(s)
	log_f.flush()


func _on_screen(p: Vector2) -> bool:
	var d: Vector2 = p - g.ppos
	return absf(d.x) < 1000.0 and absf(d.y) < 560.0


func _start(kind: String, dur: float, pre: int) -> void:
	if not cur.is_empty():
		cur.until = maxf(float(cur.until), g.t + dur)
		_log("PVEXT %s t=%.2f seg=%d n=%d" % [kind, g.t, seg_i, int(cur.n)])
		return
	seg_i += 1
	var use: Array = ring.slice(maxi(0, ring.size() - pre)) if pre > 0 else []
	var t0: float = float(use[0][2]) if not use.is_empty() else g.t
	var d := "%s/seg_%02d_%s_t%05.1f" % [out, seg_i, kind, t0]
	DirAccess.make_dir_recursive_absolute(d)
	var f0: int = int(use[0][1]) if not use.is_empty() else Engine.get_process_frames()
	cur = {"dir": d, "kind": kind, "until": g.t + dur, "n": 0, "f0": f0, "ts": []}
	for it in use:
		(it[0] as Image).save_jpg("%s/f%05d.jpg" % [d, int(cur.n)], 0.95)
		cur.ts.append(snappedf(float(it[2]), 0.0001))
		cur.n = int(cur.n) + 1
	ring.clear()
	_log("PVSEG %s seg=%d dir=%s t0=%.3f pre=%d" % [kind, seg_i, d.get_file(), t0, int(cur.n)])


func _end_seg() -> void:
	var f0: int = int(cur.f0)
	var f1: int = f0 + int(cur.n)
	var tr: Array = []
	if sfx != null:
		for e in sfx.trace:
			var fr: int = int(e[0])
			if fr >= f0 and fr < f1:
				tr.append([fr - f0, str(e[1]), float(e[2]), float(e[3])])
	var fh := FileAccess.open(str(cur.dir) + "/sfx.json", FileAccess.WRITE)
	fh.store_string(JSON.stringify({"kind": cur.kind, "n": cur.n, "fps": 60, "ts": cur.ts, "sfx": tr}))
	fh.close()
	_log("PVEND seg=%d dir=%s n=%d t=%.2f sfx=%d" % [seg_i, str(cur.dir).get_file(), int(cur.n), g.t, tr.size()])
	cur = {}


func _ev(s: String) -> void:
	_log("PVEV %s t=%.3f seg=%d n=%d" % [s, g.t, seg_i if not cur.is_empty() else -1, int(cur.get("n", -1))])


func _spawn_ring() -> void:
	var n: int = int(ring_spec[1])
	var r: float = float(ring_spec[2])
	var types := ["fractal", "slider", "runner", "fractal", "bone"]
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var rr: float = r + 70.0 * float(i % 3) / 2.0
		var e: Dictionary = g.spawner.spawn_enemy(types[i % types.size()], g.ppos + Vector2.from_angle(a) * Vector2(rr * 1.35, rr))
		e.age = 5.0
	_ev("ring n=%d r=%.0f" % [n, r])


func _spawn_elite() -> void:
	var e: Dictionary = g.spawner.spawn_enemy(str(elite_spec[1]), g.ppos + Vector2(float(elite_spec[2]), float(elite_spec[3])))
	e.age = 5.0
	if not e.elite:
		e.elite = true
		e.hp *= 7.0
		e.maxhp = e.hp
	_ev("elite %s" % str(elite_spec[1]))


func _fill_ult(why: String) -> void:
	if g.ult == null:
		return
	g.ult.energy = g.ult.FULL
	g.ult.full_since = g.t
	_ev("fill %s" % why)


func _process(_dt: float) -> bool:
	if g == null:
		g = current_scene
		if g == null or not ("autotest" in g):
			g = null
			return false
		sfx = root.get_node_or_null("Sfx")
		if sfx != null:
			sfx.trace_on = true
	if g.t > maxt:
		if not cur.is_empty():
			_end_seg()
		_log("PVDONE t=%.1f segs=%d" % [g.t, seg_i])
		quit()
		return false
	var playing: bool = g.state == g.S.PLAY
	# ---- 强制事件
	if playing:
		while not ult_at.is_empty() and g.t >= float(ult_at[0]):
			ult_at.pop_front()
			_fill_ult("plan")
		if not ring_spec.is_empty() and g.t >= float(ring_spec[0]):
			_spawn_ring()
			ring_spec = []
		if not elite_spec.is_empty() and g.t >= float(elite_spec[0]):
			_spawn_elite()
			elite_spec = []
		if boss_ult > 0.0 and not boss_ult_done:
			for b in g.bosses:
				if not b.dead and b != g.final_boss and float(b.hp) < float(b.maxhp) * boss_ult:
					boss_ult_done = true
					_fill_ult("boss %s hp=%.0f/%.0f" % [str(b.type), float(b.hp), float(b.maxhp)])
					break
	# ---- 固定窗口
	for i in wins.size():
		var w: Array = wins[i]
		if g.t >= float(w[0]) and g.t < float(w[1]) and not win_done.has(i):
			win_done[i] = true
			_start("win", float(w[1]) - g.t, 0)
	# ---- 终结技
	var u = g.ult
	if u != null:
		if int(u.serial) != last_serial:
			if last_serial >= 0:
				var cid: String = str(u.caster.id) if u.caster != null else "x"
				_ev("ULT kind=%s caster=%s" % [str(u.kind), cid])
				if auto_ult:
					_start("ult_" + cid, 5.0, 90)
			last_serial = int(u.serial)
		var hf: int = int(u._hf_n[0]) if "_hf_n" in u else 0
		if hf > 0 and last_hf == 0:
			_ev("HF")
		last_hf = hf
	# ---- 三选一
	var is_choice: bool = g.state == g.S.CHOICE
	if is_choice and not choice_on:
		choice_on = true
		_ev("CHOICE open")
		if rec_choice:
			_start("choice", 30.0, 30)
	elif not is_choice and choice_on:
		choice_on = false
		_ev("CHOICE close")
		if rec_choice and not cur.is_empty():
			cur.until = g.t + 2.5
	# ---- 灯标
	if rec_beacon and playing:
		for b in g.beacons:
			var key := str(b.pos)
			if not b.lit and float(b.prog) > 0.05 and not beacon_rec.has(key):
				beacon_rec[key] = true
				_ev("BEACON charge %s" % key)
				_start("beacon", 12.0, 60)
			if b.lit and beacon_rec.get(key, false) == true:
				beacon_rec[key] = "lit"
				_ev("BEACON lit %s" % key)
				if not cur.is_empty():
					cur.until = g.t + 3.0
	# ---- 状态日志
	if g.t >= next_log:
		next_log = g.t + 0.25
		var ne := 0
		var eb := 0
		if playing:
			for e in g.enemies:
				if not e.dead and _on_screen(e.pos):
					ne += 1
			for b in g.ebullets:
				if _on_screen(b.pos):
					eb += 1
		var bs := []
		for b in g.bosses:
			if not b.dead:
				bs.append("%s:%.2f" % [str(b.type), float(b.hp) / maxf(1.0, float(b.maxhp))])
		_log("PVLOG t=%.2f seg=%d n=%d lamp=%d ne=%d eb=%d boss=%s st=%d ult=%s wheel=%s" % [g.t, seg_i if not cur.is_empty() else -1, int(cur.get("n", -1)),
			int(g.lamp), ne, eb, ",".join(bs), int(g.state), str(u.phase) if u != null else "-", str(g.wheel.is_open) if g.get("wheel") != null else "-"])
	# ---- 存帧
	if not cur.is_empty():
		var img: Image = g.get_viewport().get_texture().get_image()
		img.save_jpg("%s/f%05d.jpg" % [cur.dir, int(cur.n)], 0.95)
		cur.ts.append(snappedf(float(g.t), 0.0001))
		cur.n = int(cur.n) + 1
		if g.t >= float(cur.until) and not (rec_choice and choice_on):
			_end_seg()
	elif ring_max > 0 and g.t >= rtfrom:
		ring.append([g.get_viewport().get_texture().get_image(), Engine.get_process_frames(), g.t])
		if ring.size() > ring_max:
			ring.pop_front()
	# 音效记录只留最近 20 秒（不在录时）
	if sfx != null and cur.is_empty() and Engine.get_process_frames() >= trim_at:
		trim_at = Engine.get_process_frames() + 600
		var keep_from: int = Engine.get_process_frames() - 1200
		var tr: Array = sfx.trace
		var k := 0
		while k < tr.size() and int(tr[k][0]) < keep_from:
			k += 1
		if k > 0:
			sfx.trace = tr.slice(k)
	return false
