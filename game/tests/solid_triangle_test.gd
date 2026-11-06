extends Node
## Single-color meshes must match expanded vertex colors, including operator modulation.
const Batch = preload("res://scripts/characters/batch_canvas.gd")
var failures := 0

class BaselineQuads extends Batch:
	func add_quads(pts: PackedVector2Array, cols: PackedColorArray) -> void:
		if mute:
			return
		if mod_on:
			cols = cols.duplicate()
			for i in cols.size():
				cols[i] = _dim(cols[i])
		_pts.append_array(pts if xf == Transform2D.IDENTITY else xf * pts)
		_cols.append_array(cols)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var color := Color(1.2, 0.32, 0.6, 0.75)
	for mods in [[1.0, 0.0, 1.0, 0.0], [0.45, 0.0, 1.0, 0.0], [0.7, 0.4, 1.3, 0.25]]:
		for xf in [Transform2D.IDENTITY, Transform2D(0.3, Vector2(1.5, -1.0), 0.0, Vector2(12, 8))]:
			var old = Batch.new(null)
			var compact = Batch.new(null)
			for cv in [old, compact]:
				cv.active = true
				cv.xf = xf
				cv.set_mod(mods[0], mods[1], mods[2], mods[3])
			var full := PackedColorArray([color, color, color, color])
			var one := PackedColorArray([color])
			old.add_tris(pts, full, idx)
			compact.add_tris(pts, one, idx)
			check(old._pts == compact._pts, "compact vertices and draw order")
			check(old._cols == compact._cols, "compact colors under modulation")
			check(one == PackedColorArray([color]) and full[0] == color, "caller colors unchanged")
			compact.mute = true
			var size: int = compact._pts.size()
			compact.add_tris(pts, one, idx)
			check(compact._pts.size() == size, "muted mesh emits nothing")
			var old_q = BaselineQuads.new(null)
			var new_q = Batch.new(null)
			var qp := PackedVector2Array()
			var qc := PackedColorArray()
			for i in 24:
				qp.append(Vector2(i, i % 3))
				qc.append(Color(color, 0.3 + 0.1 * (i / 6)))
			qc[13] = Color.CYAN # nonuniform input must still be accepted
			for cv in [old_q, new_q]:
				cv.xf = xf
				cv.set_mod(mods[0], mods[1], mods[2], mods[3])
				cv.add_quads(qp, qc)
				cv.add_quads(PackedVector2Array(), PackedColorArray())
			check(old_q._pts == new_q._pts and old_q._cols == new_q._cols, "consecutive quad colors and empty input")
			check(qc[13] == Color.CYAN, "quad source colors unchanged")
	print("SOLID TRIANGLE failures=", failures)
	if failures == 0 and Cfg.dev_args().has("--solidpixels"):
		await verify_pixels()
	if failures == 0 and Cfg.dev_args().has("--solidbench"):
		benchmark()
		benchmark_quads()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

class MeshCanvas extends Node2D:
	var compact := false
	var mods: Array = []
	var transform_mesh := Transform2D.IDENTITY
	func _draw() -> void:
		var cv = Batch.new(self)
		cv.active = true
		cv.xf = transform_mesh
		cv.set_mod(mods[0], mods[1], mods[2], mods[3])
		var pts := PackedVector2Array()
		var idx := PackedInt32Array()
		for i in 73:
			pts.append(Vector2(10 + i * 2, 30 + sin(i * 0.15) * 8))
			pts.append(Vector2(10 + i * 2, 46 + sin(i * 0.15) * 8))
		for i in 72:
			var k: int = i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
		var cols := PackedColorArray()
		cols.resize(1 if compact else pts.size())
		cols.fill(Color(0.4, 0.7, 1.0, 0.73))
		cv.add_tris(pts, cols, idx)
		cv.end()

func verify_pixels() -> void:
	if DisplayServer.get_name() == "headless":
		check(false, "--solidpixels requires rendering driver")
		return
	var cases := 0
	for mods in [[1.0, 0.0, 1.0, 0.0], [0.45, 0.0, 1.0, 0.0], [0.7, 0.4, 1.3, 0.25]]:
		for xf in [Transform2D.IDENTITY, Transform2D(0.15, Vector2(0.8, 1.0), 0.0, Vector2(12, 8))]:
			var views: Array = []
			for compact in [false, true]:
				var vp := SubViewport.new()
				vp.size = Vector2i(192, 128)
				vp.transparent_bg = true
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				add_child(vp)
				var mesh := MeshCanvas.new()
				mesh.compact = compact
				mesh.mods = mods
				mesh.transform_mesh = xf
				vp.add_child(mesh)
				views.append(vp)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var original: Image = views[0].get_texture().get_image()
			var a: PackedByteArray = original.get_data()
			var b: PackedByteArray = views[1].get_texture().get_image().get_data()
			check(original.get_used_rect().has_area() and a == b, "large mesh pixels match with modulation/transform")
			for vp in views:
				vp.queue_free()
			cases += 1
	print("SOLID PIXELS cases=%d failures=%d" % [cases, failures])

func benchmark() -> void:
	var canvas := Node2D.new()
	add_child(canvas)
	var cv = Batch.new(canvas)
	cv.active = true
	cv.set_mod(0.65, 0.3, 1.2, 0.15)
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in 73:
		pts.append(Vector2(i * 2, 0))
		pts.append(Vector2(i * 2, 4))
	for i in 72:
		var k: int = i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var col := Color(0.4, 0.7, 1.0, 0.8)
	var full := PackedColorArray()
	full.resize(pts.size())
	full.fill(col)
	var one := PackedColorArray([col])
	for pass_i in 6:
		for compact in [pass_i % 2 == 0, pass_i % 2 != 0]:
			var begin := Time.get_ticks_usec()
			for i in 2000:
				cv.add_tris(pts, one if compact else full, idx)
				RenderingServer.canvas_item_clear(canvas.get_canvas_item())
			print("SOLID_BENCH pass=%d compact=%s us=%d meshes=2000 vertices=%d" % [pass_i, compact, Time.get_ticks_usec() - begin, pts.size()])
	cv = null
	canvas.queue_free()

func benchmark_quads() -> void:
	var old = BaselineQuads.new(null)
	var optimized = Batch.new(null)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 600:
		pts.append(Vector2(i, i % 3))
		cols.append(Color(0.4, 0.7, 1.0, 0.3 + 0.1 * ((i / 6) % 5)))
	for cv in [old, optimized]:
		cv.set_mod(0.65, 0.3, 1.2, 0.15)
	for pass_i in 6:
		for compact in [pass_i % 2 == 0, pass_i % 2 != 0]:
			var cv = optimized if compact else old
			var begin := Time.get_ticks_usec()
			for i in 500:
				cv.add_quads(pts, cols)
				cv._pts = PackedVector2Array()
				cv._cols = PackedColorArray()
			print("QUAD_BENCH pass=%d compact=%s us=%d meshes=500 vertices=600" % [pass_i, compact, Time.get_ticks_usec() - begin])
