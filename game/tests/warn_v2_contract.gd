extends SceneTree
const Warn = preload("res://scripts/render/minion_warn.gd")
const Bal = preload("res://scripts/core/balance.gd")

class DrawSpy extends RefCounted:
	var calls: Array = []
	func draw_polyline(points, col, width):
		calls.append({"points": points, "col": col, "width": width})

func _initialize() -> void:
	var settings := Bal.sec("render")
	var old = settings.get("warn_v2", 0)
	var w := {"owner": {"elite": false, "boss": false}, "shape": "circle", "style": 1, "dur": 1.0, "t": 0.2}
	settings.warn_v2 = 0
	assert(not Warn.owns(w), "off must retain old rendering")
	settings.warn_v2 = 1
	assert(Warn.owns(w))
	assert(is_zero_approx(Warn.urgency(w)), "ordinary phase must not brighten")
	assert(is_equal_approx(Warn.progress(w), 0.2))
	# Zero-fill fallback must not access a canvas, even for overlapping calls.
	for overlap in 12:
		Warn.fill(null, w)
	var spy := DrawSpy.new()
	var g := {"wcv": spy, "combat": {"GROUND_Y": 0.7}}
	var sweep := {"shape": "line", "pos": Vector2.ZERO, "ang": 0.0, "len": 100.0, "wid": 10.0, "t": 0.5, "dur": 1.0, "dim": true}
	var points := Warn.timer_points(g, sweep)
	assert(points[0] == Vector2(50, 10) and points[1] == Vector2(50, -10), "line timer moves inside fixed rails")
	Warn.outline(g, sweep)
	assert(spy.calls.size() == 1 and spy.calls[0].col.a <= 0.45 and spy.calls[0].width == 2.0, "dim has one thin faint line, no backing or timer")
	sweep.shape = "cone"
	sweep.half = 0.6
	sweep.r = 100.0
	points = Warn.timer_points(g, sweep)
	assert(points[0] == Vector2.ZERO and points[1].is_equal_approx(Vector2(100, 0)), "cone timer sweeps angle, not radius")
	sweep.shape = "circle"
	points = Warn.timer_points(g, sweep)
	assert(points[0].is_equal_approx(Vector2(50, 0)) and points[12].is_equal_approx(Vector2(0, 35)), "one interior timer ring follows elapsed fraction")
	w.t = 0.85
	assert(is_equal_approx(Warn.urgency(w), 0.5))
	w.owner.elite = true
	assert(not Warn.owns(w), "elite presentation must not change")
	w.owner.elite = false
	w.owner.boss = true
	assert(not Warn.owns(w), "boss presentation must not change")
	w.owner.boss = false
	w.owner.squad = true
	assert(not Warn.owns(w), "squad members can be ordinary species with elite=false")
	w.owner.squad = false
	w.owner.cross_elite = true
	assert(not Warn.owns(w), "crossroads elite presentation must not change")
	w.owner.cross_elite = false
	w.must_dash = true
	assert(not Warn.owns(w), "mandatory dodge remains prominent")
	w.must_dash = false
	for style in [0,4,5]:
		w.style = style
		assert(not Warn.owns(w))
	w.style = 1
	w.owner = null
	assert(not Warn.owns(w), "ownerless warnings must keep baseline")
	settings.warn_v2 = old
	Bal.clear_cache()
	print("WARN_V2_CONTRACT PASS")
	quit()
