extends Node
## Rendering helpers load only the requested packs and release their owners after a run or gallery closes.
const World = preload("res://scripts/render/world.gd")
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Crack = preload("res://scripts/render/ground_crack.gd")
const Character = preload("res://scripts/characters/character.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func check_px_metadata() -> void:
	var owners: Array = Pxp.META_PREFIXED.values() + Pxp.META_BAKED_PREFIX.values() + ["skadi"]
	for file in DirAccess.get_files_at("res://data"):
		if not file.begins_with("pxp_") or not file.ends_with(".json"):
			continue
		var owner: String = file.trim_prefix("pxp_").trim_suffix(".json")
		check(owner in owners, "unregistered pxplane pack " + file)
		owners.erase(owner)
		var entries = JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))
		if not entries is Dictionary or entries.is_empty():
			check(false, "invalid pxplane pack " + file)
			continue
		var prefix = Pxp.META_PREFIXED.find_key(owner)
		var key_prefix := str(prefix) + "_" if prefix != null else ""
		var seen_families := {}
		var px: Pxp
		for local_key in entries:
			if local_key == "_doc":
				continue
			var key := key_prefix + str(local_key)
			var family := key.get_slice("_", 0)
			# Exercise each namespace from cold, even when another key would have warmed the pack.
			if not seen_families.has(family):
				seen_families[family] = true
				px = Pxp.new()
			check(px._meta(key) == entries[local_key], "pxplane metadata " + key)
			check(px._meta_loaded.size() == 1 and px._meta_loaded.has(owner), "pxplane pack for " + key)
	check(owners.is_empty(), "missing pxplane packs " + str(owners))

func check_px_iteration() -> void:
	var px = Pxp.new()
	px.g = {"t": 1.0, "ppos": Vector2(10, 20), "opt_old": 0, "OPT_PXSTEP": 1, "OPT_PXEVICT": 2}
	var an := {"oid": "angelina", "ly": "gd", "k": "a", "t0": 0.0, "life": 3.0}
	var ka := {"oid": "kaltsit", "ly": "up", "k": "b", "t0": 0.0, "life": 3.0, "fol": Vector2(4, 6)}
	var wd := {"oid": "wisadel", "ly": "up", "k": "c", "t0": 0.0, "life": 0.1}
	for item in [an, ka, wd]:
		px._push(item)
	ka["klit"] = true  # 凯尔希登记骨架后才标记合拢时的照地光。
	var an_up := {"oid": "angelina", "ly": "up", "k": "d", "t0": 0.0, "life": 3.0}
	var drawn := []
	for item in px.items_for("angelina"):
		drawn.append(item.k)
		if item.k == "a":
			px._push(an_up)
	check(drawn == ["a", "d"], "pxplane same-pass append")
	check(px._upright_items == [ka, wd, an_up], "pxplane upright order across owners")
	check(is_same(px.items_for("kaltsit")[0], ka) and px.items_for("kaltsit")[0].klit, "pxplane shared upright state")
	var old_source: Array = px.items
	var old_wd: Array = px.items_for("wisadel")
	ka["stk"] = 0.1
	px._step()
	check(px.items_for("wisadel").is_empty() and px._upright_items == [ka, an_up], "pxplane expiry in every view")
	check(old_source == [an, ka, wd, an_up] and old_wd == [wd], "pxplane active iterators keep their old array on replacement")
	check(ka.t0 == 0.1 and not ka.has("stk"), "pxplane live hitstop applied once")
	check(px.items_for("kaltsit")[0].gp == Vector2(14, 26), "pxplane follow updates the shared item")
	px.items = px.items.filter(func(it): return it.oid != "angelina")
	check(px.items_for("angelina").is_empty() and px._upright_items == [ka], "pxplane replacement updates views")
	wd.ef = {"dead": true}
	wd.life = 3.0
	wd.stk = 0.1
	px.items = [wd, ka]
	px.g.opt_old = px.g.OPT_PXSTEP
	px.g.ppos = Vector2.ZERO
	px._step()
	check(px.items == [ka] and wd.has("stk") and ka.gp == Vector2(14, 26), "pxplane first item expired before hitstop, follow once per beat")
	px.g.t = 1.1
	px._step()
	check(ka.gp == Vector2(4, 6) and ka.t0 == 0.1, "pxplane next follow beat")
	for i in Pxp.ITEM_MAX:
		px._push({"oid": "wisadel", "ly": "gd", "k": str(i)})
	check(px.items.size() == Pxp.ITEM_MAX and px.items_for("wisadel") == px.items, "pxplane capped owner order")
	check(px.items_for("kaltsit").is_empty() and px._upright_items.is_empty(), "pxplane evicted oldest upright item")

func _ready() -> void:
	check_px_iteration()
	check_px_metadata()
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
