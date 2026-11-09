extends RefCounted

const BossDraw = preload("res://scripts/render/boss_bullet_draw.gd")

class Canvas:
	var submissions := []
	func draw_texture_rect_region(tex, rect, region, color) -> void:
		submissions.append([tex.get_instance_id(), rect, region, color])

class Run extends Canvas:
	var bosses := []
	var ebullets := []
	var draw_off := Vector2.ZERO
	var optical_on := false
	var t := 0.0
	var spawner: Object
	var world: Object
	var wcv: Object
	func is_final_boss_type(kind: String) -> bool:
		return kind == "paranoia"
	func mobile_cap() -> bool:
		return true
	func view_rect(_margin: float) -> Rect2:
		return Rect2(-100, -100, 200, 200)
	func wd_new(_bit: int) -> bool:
		return false
	func tb_flush() -> void:
		pass
	func tb_circle(_pos, _r, _color, _scale, _sides) -> void:
		pass

static func run(check: Callable) -> void:
	var g := Run.new()
	g.spawner = g
	g.world = g
	g.wcv = g
	var top := Canvas.new()
	var d = BossDraw.new(g)
	d.warm("carmen")
	d._release_idle_atlases()
	check.call(d._atlas.has("carmen"), "queued cells retain atlas")
	while not d._queue.is_empty():
		d._pump(3)
	g.bosses = [{"type": "carmen", "dead": false}]
	g.t = 5.0
	d.frame(null)
	check.call(d._atlas.has("carmen"), "live boss retains atlas")
	var b := {"src_type": "carmen", "boss": true, "r": 6.0, "pos": Vector2.ZERO, "life": 2.0}
	g.ebullets = [b]
	d.draw(g)
	var first: Array = g.submissions.duplicate()
	check.call(first.size() == 1, "boss projectile submits one shell")
	g.bosses.clear()
	b.hidden = true
	d.world_atlases.clear()
	d._release_idle_atlases()
	check.call(d._atlas.has("carmen"), "hidden surviving bullet retains atlas")
	b.hidden = false
	g.wcv = top
	d.draw(g)
	check.call(first == top.submissions, "orphan projectile submits identical texture, geometry and modulation")
	g.wcv = g
	d.draw(g)
	g.ebullets.clear()
	d.top_atlases.clear()
	d._release_idle_atlases()
	check.call(d._atlas.has("carmen"), "unfinished world canvas retains atlas")
	g.ebullets = [b]
	g.wcv = top
	d.draw(g)
	g.ebullets.clear()
	d.world_atlases.clear()
	d._release_idle_atlases()
	check.call(d._atlas.has("carmen"), "unfinished upper canvas retains atlas")
	d.top_atlases.clear()
	var pixels: PackedByteArray = d._atlas.carmen.img.get_data()
	var image_ref: WeakRef = weakref(d._atlas.carmen.img)
	var texture_ref: WeakRef = weakref(d._atlas.carmen.tex)
	d.warm("paranoia")
	while not d._queue.is_empty():
		d._pump(3)
	g.t = 10.0
	d.frame(null)
	check.call(not d._atlas.has("carmen") and not d._warmed.has("carmen"), "idle mid boss retired on mobile sweep")
	check.call(image_ref.get_ref() == null and texture_ref.get_ref() == null, "CPU image and texture released")
	check.call(d._atlas.has("paranoia"), "final boss atlas retained")
	d.warm("carmen")
	while not d._queue.is_empty():
		d._pump(3)
	check.call(pixels == d._atlas.carmen.img.get_data(), "rewarmed atlas pixels match")
	g.spawner = null
	g.world = null
	g.wcv = null
