extends Node
## Rendering helpers must not retain their owners after a run or gallery closes.
const World = preload("res://scripts/render/world.gd")
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Crack = preload("res://scripts/render/ground_crack.gd")
const Character = preload("res://scripts/characters/character.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func _ready() -> void:
	# Never entering the tree must also be safe (previews and unit fixtures).
	for cycle in 3:
		var world = World.new(null)
		var wr : WeakRef = weakref(world)
		var bullet : WeakRef = weakref(world.bulfx)
		var sink : WeakRef = weakref(world._gc_sink)
		check(world.bulfx.w == world and world._gc_sink.w == world, "live world backrefs")
		world = null
		check(wr.get_ref() == null, "world released %d" % cycle)
		check(bullet.get_ref() == null, "bullet helper released %d" % cycle)
		check(sink.get_ref() == null, "ground helper released %d" % cycle)
		var px = Pxp.new()
		var pr : WeakRef = weakref(px)
		var refs: Array = []
		for method in ["_ex", "_an", "_sa", "_szx", "_ir", "_wd", "_lp"]:
			var child = px.call(method)
			check(child.r == px, "live pxplane backref " + method)
			refs.append(weakref(child))
			child = null
		# A cached resource must disappear with the owner, not await another tick.
		var held = Resource.new()
		var hr : WeakRef = weakref(held)
		px.tex["sentinel"] = held
		held = null
		px = null
		check(pr.get_ref() == null, "pxplane released %d" % cycle)
		check(hr.get_ref() == null, "cached resource released %d" % cycle)
		for i in refs.size():
			check(refs[i].get_ref() == null, "pxplane child released %d/%d" % [cycle, i])
		var op = Character.new(null, {})
		var opr : WeakRef = weakref(op)
		op._gc_sink = Crack.CvSink.new(op)
		check(op._gc_sink.owner == op, "live character sink backref")
		op = null
		check(opr.get_ref() == null, "character released %d" % cycle)
	# A caller retaining a helper must not keep its old run alive either.
	var world = World.new(null)
	var surviving_bullet = world.bulfx
	var surviving_ground = world._gc_sink
	var wr : WeakRef = weakref(world)
	world = null
	check(wr.get_ref() == null, "retained world helpers do not retain owner")
	check(surviving_bullet.w == null and surviving_ground.w == null, "expired world backrefs are null")
	var px = Pxp.new()
	var surviving_child = px._szx()
	var pr : WeakRef = weakref(px)
	px = null
	check(pr.get_ref() == null, "retained pxplane child does not retain owner")
	check(surviving_child.r == null, "expired pxplane backref is null")
	print("RENDER LIFETIME failures=", failures)
	get_tree().quit(1 if failures else 0)
