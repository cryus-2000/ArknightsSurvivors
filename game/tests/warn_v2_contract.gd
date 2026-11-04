extends SceneTree
const Warn = preload("res://scripts/render/minion_warn.gd")
const Bal = preload("res://scripts/core/balance.gd")

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
