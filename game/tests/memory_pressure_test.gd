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

func check_warm_roster(g) -> void:
	const Art = preload("res://scripts/art.gd")
	const FIRST := "fx_wisadel_cannon"
	const NEXT := "fx_skadi_surge"
	const ALLY := "fx_an_core"  # --squad=angelina in both runs
	const SHARED := "fx_dust_seq"
	var previous: String = Cfg.character_id
	Cfg.character_id = "wisadel"
	var first: Array = Probe.loading_warm_lists()[0]
	check(first.has(FIRST) and first.has(ALLY) and first.has(SHARED) and not first.has(NEXT), "departure only prewarms squad and shared FX")
	for key in [FIRST, NEXT, ALLY, SHARED]:
		Art.uncache(key)
	Art.outrun_track = true
	for key in [FIRST, NEXT, ALLY, SHARED]:
		Art.tex(key)
	g._drop_outrun_tex()
	var kept := Art.cache_keys()
	check(kept.has(FIRST) and kept.has(ALLY) and kept.has(SHARED) and not kept.has(NEXT), "battle entry keeps the same FX as departure")
	Cfg.character_id = "skadi"
	var second: Array = Probe.loading_warm_lists()[0]
	check(second.has(NEXT) and second.has(ALLY) and second.has(SHARED) and not second.has(FIRST), "selecting a new leader rebuilds departure FX after battle entry")
	g.tex_lazy_fx["wisadel"] = [FIRST]
	g.panel_ui.load_op_tex("wisadel")
	check(g.tex.get(FIRST) is Texture2D and not g.tex_lazy_fx.has("wisadel"), "recruitment loads an operator deferred at departure")
	Cfg.character_id = previous

func _ready() -> void:
	var g = Probe.new()
	check_warm_roster(g)
	for i in 20:
		g._mem_guard(5.0)
	check(g.trims == 1, "sustained pressure trims once, got %d" % g.trims)
	check(g.evictions == 20, "every over-budget probe still evicts newly idle textures")
	check(Cfg.quality != "low", "default fallback no longer lowers quality (render/mem_guard_lowq 0, 11-07)")
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
