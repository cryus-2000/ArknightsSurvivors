extends Node
## Sustained memory pressure must not repeatedly rebuild the font atlas.
class Probe:
	extends "res://scripts/game.gd"
	var trims := 0
	var evictions := 0
	func _mem_guard_trim_fonts() -> void:
		trims += 1
		super._mem_guard_trim_fonts()
	func _white_release(_delta: float, _now := false) -> void:
		evictions += 1

var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _ready() -> void:
	var g = Probe.new()
	for i in 20:
		g._mem_guard(5.0)
	check(g.trims == 1, "sustained pressure trims once, got %d" % g.trims)
	check(g.evictions == 20, "every over-budget probe still evicts newly idle textures")
	check(Cfg.guard_lowered and Cfg.quality == "low", "fallback still lowers quality")
	# A near-threshold oscillation must not re-arm expensive trimming.
	for i in 20:
		g._mem_guard_apply(519.0, 520.0)
		g._mem_guard_apply(530.0, 520.0)
	check(g.trims == 1, "threshold oscillation does not repeatedly trim")
	check(g.evictions == 40, "near-threshold pressure preserves immediate texture eviction")
	g._mem_guard_apply(480.0, 520.0)
	g._mem_guard_apply(530.0, 520.0)
	check(g.trims == 2, "a recovered episode can trim again")
	g._mem_guard_apply(480.0, 520.0)
	g._mem_guard_apply(530.0, 520.0)
	check(g.trims == 2, "cooldown prevents rapid recovered spikes from trimming")
	for i in 12:
		g._mem_guard_apply(640.0, 520.0)
	check(g.trims == 3, "rearmed pressure can trim once after cooldown")
	check(Cfg.render_scaled, "severe sustained pressure still scales resolution")
	for i in 20:
		g._mem_guard_apply(640.0, 520.0)
	check(g.trims == 3, "remaining over budget never repeats trim")
	check(g.perf_rep.guard_stage == 3, "report records highest applied fallback")
	g.free()
	print("MEMORY PRESSURE failures=", failures)
	get_tree().quit(1 if failures else 0)
