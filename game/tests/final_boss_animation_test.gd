extends Node
const Art = preload("res://scripts/art.gd")
var failures := 0
var g
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.t = 100.0
	g.ppos = Vector2(200,0)
	for kind in ["paranoia","knight_boss","ishar","izumik"]:
		var e: Dictionary = g.spawner.new_enemy(kind,Vector2.ZERO)
		e.phase = 2 if kind in ["ishar","izumik"] else 1
		e.invuln = false
		e.friendly = false
		e.cocoon_t = 0.0
		g.bosses=[e]
		g.enemies=[e]
		for move in g.bai.finals.NAMES[kind]:
			e.erase("last_act")
			g.warns.clear()
			check(g.bai.finals.force_move(e,move,Vector2.RIGHT,200.0),move+" scheduled")
			if g.warns.is_empty():continue
			var w: Dictionary = g.warns[0]
			g.warns=[w]
			w.t=w.dur*0.99
			var pose: Dictionary = g.world.final_boss_animation(e)
			check(not pose.is_empty(),move+" real body casting strip")
			if pose.is_empty():continue
			var rd: Dictionary = Art.enemy_redraw(pose.name)
			var ev: int = rd.event_frames[0] if not rd.event_frames.is_empty() else int(rd.release_frame if rd.release_frame != null else rd.frames/2)
			check(pose.frames==rd.frames and pose.frame<ev,move+" native pre-release frames")
			var saved: Dictionary=w.duplicate(true)
			g.world.final_boss_animation(e)
			check(w==saved,move+" visual selector leaves warning unchanged")
			g.tele.warn_resolve(w)
			g.warns.clear()
			var t0: float=g.t
			pose=g.world.final_boss_animation(e)
			check(not pose.is_empty() and pose.frame==ev,move+" release event aligned")
			if not pose.is_empty():
				var strip: String=pose.name
				var times: Array=rd.sample_times
				for frame in range(ev,rd.frames):
					g.t=t0+float(times[frame])-float(times[ev])+0.0001
					pose=g.world.final_boss_animation(e)
					check(not pose.is_empty() and pose.name==strip and pose.frame==frame,move+" preserves authored recovery frame "+str(frame))
			g.t=t0+4.0
			check(g.world.final_boss_animation(e).is_empty(),move+" recovery ends")
			e.stun=1.0
			g.warns=[w]
			w.done=false
			check(g.world.final_boss_animation(e).is_empty(),move+" interrupted body cast clears")
			e.stun=0.0
			g.bai.finals.hazards.clear()
			g.fx.clear()
		g.enemies.clear()
	g.queue_free()
	await get_tree().process_frame
	print("FINAL BOSS ANIMATION failures=",failures)
	get_tree().quit(1 if failures else 0)
