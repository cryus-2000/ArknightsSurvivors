extends Node
## 光感 + 粒子感体检（docs/270）：同 elite_demo_shot（图鉴演示放进 SubViewport 连拍），另外每帧量一次特效的「光 / 颗粒」账：
##   FXA <帧> <g.t> new=<材质:颗数,…> life=<新颗粒平均寿命> sz=<新颗粒平均边长> alive=<在场颗粒> L=<新灯 半径/强度/寿命;…>
##       gr=<fx_grains 在场颗粒> gnew=<fx_grains 新颗粒> sp=<新火星> gl=<fx_grains 新灯> glow=<发光点总数> emit=<px_plane emit 点数>
## 只读不改：新颗粒 / 新灯靠在条目尾部加一个标记认出（画面层数据，不进玩法、TRACE 不变）。
##   godot --path game --fixed-fps 30 res://tests/fx_audit_shot.tscn -- --shot_op=<id> --shot_stage=2 --shot_mode=3 --shot_dir=<目录>
##         [--shot_start=秒 --shot_every=帧 --shot_n=张 --shot_w=1280 --shot_h=720] [--bal=…]

var vp: SubViewport
var game: Node
var frames := 0
var saved := 0
var dir := ""
var start := 2.0
var every := 1
var n := 120
var _emit_a := 0.8


func _ready() -> void:
	var op := "skadi"
	var stage := 2
	var mode := -1
	var w := 1280
	var h := 720
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_op="):
			op = a.substr(10)
		elif a.begins_with("--shot_stage="):
			stage = int(a.substr(13))
		elif a.begins_with("--shot_mode="):
			mode = int(a.substr(12))
		elif a.begins_with("--shot_dir="):
			dir = a.substr(11)
		elif a.begins_with("--shot_start="):
			start = float(a.substr(13))
		elif a.begins_with("--shot_every="):
			every = maxi(1, int(a.substr(13)))
		elif a.begins_with("--shot_n="):
			n = int(a.substr(9))
		elif a.begins_with("--shot_w="):
			w = int(a.substr(9))
		elif a.begins_with("--shot_h="):
			h = int(a.substr(9))
	DirAccess.make_dir_recursive_absolute(dir)
	vp = SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.handle_input_locally = false
	add_child(vp)
	game = load("res://game.tscn").instantiate()
	game.demo_op = op
	game.demo_nodes = -1
	game.demo_sys.configure(stage, mode)
	vp.add_child(game)
	_emit_a = float(preload("res://scripts/core/balance.gd").v("fx/px_plane_emit", 0.8))


func _probe() -> String:
	var g = game
	var newm := {}
	var lsum := 0.0
	var ssum := 0.0
	var nn := 0
	var alive := 0
	var ls: Array = []
	if g.has_meta("fx_recipe"):
		var R = g.get_meta("fx_recipe")
		alive = R.parts.size()
		for q in R.parts:
			if q.has("_fxa"):
				continue
			q["_fxa"] = 1
			newm[q.m] = int(newm.get(q.m, 0)) + 1
			lsum += float(q.life)
			ssum += float(q.sz)
			nn += 1
		for L in R.lights:
			if L.size() > 7:
				continue
			L.append(1)
			ls.append("%d/%.2f/%.2f/%s" % [int(L[1]), float(L[5]), float(L[4]), (L[2] as Color).to_html(false)])
	var gr := 0
	var gnew := 0
	var sp := 0
	var gl := 0
	if "optical" in g and g.optical != null and g.optical.grains != null:
		var G = g.optical.grains
		gr = G.pos.size()
		for i in G.life.size():
			if G.life[i] == G.lmax[i] and G.delay[i] <= 0.0:
				gnew += 1
		for s in G.sparks:
			if s.size() > 6:
				continue
			s.append(1)
			sp += 1
		for L in G.lights:
			if L.size() > 5:
				continue
			L.append(1)
			gl += 1
	var glow := 0
	var emit := 0
	var gc = g.glow_cur if "glow_cur" in g else []
	glow = gc.size()
	for q in gc:
		if absf((q[2] as Color).a - _emit_a) < 0.002:
			emit += 1
	var ns: Array = []
	for k in newm:
		ns.append("%s:%d" % [k, newm[k]])
	return "FXA %d %.3f new=%s life=%.2f sz=%.1f alive=%d L=%s gr=%d gnew=%d sp=%d gl=%d glow=%d emit=%d" % [
		Engine.get_process_frames(), float(g.t), ",".join(ns) if ns.size() else "-", lsum / maxf(1, nn), ssum / maxf(1, nn), alive,
		";".join(ls) if ls.size() else "-", gr, gnew, sp, gl, glow, emit]


func _process(_dt: float) -> void:
	frames += 1
	if game != null and game.is_inside_tree() and "t" in game:
		print(_probe())
	if frames < int(start * 30.0):
		return
	if (frames - int(start * 30.0)) % every != 0:
		return
	if dir != "":
		vp.get_texture().get_image().save_png(dir + "/f_%04d.png" % saved)
	print("FXSHOT %d %d" % [saved, Engine.get_process_frames()])
	saved += 1
	if saved >= n:
		get_tree().quit()
