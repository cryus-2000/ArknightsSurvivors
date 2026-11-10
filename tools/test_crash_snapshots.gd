extends SceneTree
## Run using godot_runner with --headless --path game --script <absolute path to this file>.



func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var box = load("res://scripts/core/crash_box.gd")
	var points := {}
	for sec in range(1001):
		var wave := (1 if sec >= 210 else 0) + (1 if sec >= 420 else 0) + (1 if sec >= 600 else 0)
		var point := {"t": sec, "tex": 100, "buf": 7, "aud": 40, "mw": 10, "wasm": 286, "total": 198}
		if sec == 600:
			box._mark_before(points, wave)
			if points.before3.t != 599 or points.has("after3"):
				return fail("Interrupted Boss arrival must preserve only the last sample before the wave.")
		box._keep_snapshot(points, point, wave, sec == 20)
		if points.size() > 8:
			return fail("More than eight snapshots.")
	box._keep_snapshot(points, points.last, 9, false)
	if points.size() != 8 or points.peak.t != 20 or points.last.t != 1000:
		return fail("Peak, last sample or slot cap changed.")
	for i in range(1, 4):
		var at: int = [210, 420, 600][i-1]
		if points["before%d" % i].t != at-1 or points["after%d" % i].t != at:
			return fail("Wave %d brackets changed." % i)
	var stored = JSON.parse_string(JSON.stringify({"memory_snapshots": points}))
	var lines: PackedStringArray = box.snapshot_lines(stored)
	if lines.size() != 9 or not lines[1].contains("WASM 容量 286 MiB") or not box.snapshot_lines({}).is_empty():
		return fail("Stored or legacy report formatting changed.")
	var partial := {}
	box._keep_snapshot(partial, {"t": 5}, 1, true)
	if partial.has("before1") or not partial.has("after1"):
		return fail("A missing pre-Boss sample must not be fabricated.")
	print("CRASH_SNAPSHOT_PASS")
	quit()


func fail(reason: String) -> void:
	printerr(reason)
	quit(1)
