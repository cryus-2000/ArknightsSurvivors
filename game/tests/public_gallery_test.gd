extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	Cfg.unlock_all = false
	Cfg.gallery_seen = []
	Cfg.seen_relics = []
	Cfg.endings_cleared = []
	var gallery = load("res://scripts/gallery.gd").new()
	add_child(gallery)
	gallery.set_process(false)
	for page in 7:
		gallery.tab = page
		gallery._build()
		check(not gallery.entries.is_empty(), "page populated")
		for entry in gallery.entries:
			check(bool(entry.get("locked", false)) == (page != 0), "initial page lock " + str(page))
	var g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	g.set_process(false)
	g.enemies = [{"type": "bone", "pos": g.ppos, "dead": false}]
	g.gems = [{"kind": "xp", "pos": g.ppos}]
	g.mires.clear()
	g.merchant.clear()
	preload("res://scripts/run/gallery_progress.gd").observe(g)
	check(Cfg.gallery_seen.is_empty(), "demo cannot unlock")
	g.demo_op = ""
	g.autotest = false
	preload("res://scripts/run/gallery_progress.gd").observe(g)
	check(Cfg.gallery_seen.has("enemy:bone") and Cfg.gallery_seen.has("item:EXP"), "real encounter unlocks")
	gallery.tab = 1
	gallery._build()
	for entry in gallery.entries:
		if entry.id == "bone":
			check(not entry.locked, "encounter visible in gallery")
	g.enemies.clear()
	g.gems.clear()
	g.queue_free()
	gallery.queue_free()
	print("PUBLIC GALLERY failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
