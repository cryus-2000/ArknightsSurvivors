extends Node
## 可见成长藏品的拿到前 / 后对照截帧（docs/163 §8 第 5 步）：tools/vis_growth_rec.py 调，开窗口（屏幕外）逐帧截图。
##   --vg_case=ranged | melee | summon   --vg_on=0 | 1   --vg_out=<目录>
## 同一场景、同一组敌人，--vg_on=1 时开场前发对应藏品；其余完全一样（同 seed、同帧数），两次的第 k 帧可直接左右拼。

const DT := 1.0 / 60.0
const FRAMES := 120
const CASES := {
	"ranged": {"op": "exusiai", "relics": ["58", "59"]},
	"melee": {"op": "lappland", "relics": ["63", "64"]},
	"summon": {"op": "wisadel", "relics": ["129", "130"]},
}


func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return d


func _ready() -> void:
	var cs: String = _arg("vg_case", "ranged")
	var on: bool = _arg("vg_on", "0") == "1"
	var out: String = _arg("vg_out", ProjectSettings.globalize_path("res://../build/visible_growth/raw"))
	DirAccess.make_dir_recursive_absolute(out)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.state = g.S.PLAY
	g.t = 60.0
	g.invuln = 1.0e9
	g.xp_need = 1.0e12
	var c: Dictionary = CASES[cs]
	var o = g.squad.get_op(str(c.op))
	o.sp = [-1.0e9, -1.0e9, -1.0e9]
	if cs == "summon":
		o.elite = 2
		o.refresh_stats()
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	var ctr: Vector2 = g.ppos
	o.pos = ctr
	for k in 9:
		var ang: float = -0.9 + 0.45 * (k % 5) + (0.2 if k >= 5 else 0.0)
		var d: float = (70.0 if k < 5 else 115.0) if cs == "melee" else (130.0 if k < 5 else 190.0)
		var e: Dictionary = g.spawner.spawn_enemy("stone", ctr + Vector2.from_angle(ang) * d)
		e.hp = 1.0e9
		e.max_hp = 1.0e9
	g.enemies_sys.build_grid()
	if on:
		for id in c.relics:
			g.progression.gain_relic(id)
	for f in FRAMES:
		g._update(DT)
		for e in g.enemies:
			e.hp = 1.0e9
		g.world.update_visuals(DT)
		g.world.present_step()
		g.queue_redraw()
		g.fx_add.queue_redraw()
		g.fg.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("%s_%d_%03d.png" % [cs, int(on), f]))
	print("VG CAPTURE done %s %d" % [cs, int(on)])
	get_tree().quit(0)
