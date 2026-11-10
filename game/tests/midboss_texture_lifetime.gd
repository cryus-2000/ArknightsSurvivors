extends RefCounted

const Run = preload("res://scripts/game.gd")

static func run(check: Callable) -> void:
	var g = Run.new()
	g.lazy_white = true
	g._evict_on = true
	for cfg in [["path", "e_path", "e_path_slam"], ["carmen", "e_saint", "e_carmen_spin"]]:
		var kind: String = cfg[0]
		var body: String = cfg[1]
		var special: String = cfg[2]
		check.call(not g._white_names(body).has(special), kind + " does not prewarm special whites")
		if kind == "carmen":
			check.call(not g._white_names(body).has("e_saint_dark_death"), "carmen leaves iberia death texture alone")
		g.ensure_white(body)
		g._load_enemy_tex(body)
		g.world._lazy_tex(special)
		g.boss_intro.prewarm(kind)
		var portrait: String = body + "@1x_portrait"
		var image_ref: WeakRef = weakref(g.tex[portrait])
		var special_ref: WeakRef = weakref(g.tex[special])
		g.world._ol_cache[special + "#4"] = GradientTexture1D.new()
		g.t += 100.0
		g.spawner._pre_group = [kind]
		g.spawner._pre_idx = 1
		g.spawner.boss_idx = 0
		g._white_release(5.0, true)
		check.call(g.tex.has(portrait) and g.tex.has(special) and g.tex.get(body) != null, kind + " prefetch retained under pressure")
		g.spawner.boss_idx = 1
		g.boss_intro.cur = {"bosses": [{"tex": body}]}
		g._white_release(5.0, true)
		check.call(g.tex.has(portrait), kind + " intro retains portrait")
		g.boss_intro.cur = {}
		g.fx = [{"name": body + "_death", "life": 1.0}]
		g._white_release(5.0, true)
		check.call(g.tex.get(body + "_death") != null, kind + " death animation retained")
		g.fx.clear()
		g._white_release(5.0)
		check.call(g.tex_deferred.has(body) and not g.tex.has(body), kind + " retires body")
		check.call(not g.tex.has(special) and not g.tex.has(special + "_white") and not g.world._ol_cache.has(special + "#4"), kind + " retires special and derivatives")
		check.call(not g.tex.has(portrait) and image_ref.get_ref() == null and special_ref.get_ref() == null, kind + " retired objects freed")
		g.tex_deferred["e_saint_dark"] = true
		g.ensure_enemy_tex(body)
		check.call(g.tex_deferred.has("e_saint_dark"), "respawn leaves the other saint deferred")
		g.ensure_white(body)
		g.boss_intro.prewarm(kind)
		check.call(g.tex.get(body) != null and g.world._lazy_tex(special) != null and g.tex.get(portrait) != null, kind + " reloads all three on next appearance")
	g.free()
