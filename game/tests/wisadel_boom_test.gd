extends Node
## 维什戴尔同一处爆炸只画一次（用户 10-26「同一个落点的炮击爆炸动画有时会连续画好几次」）：
##   A 单元：同一点同一帧炸 3 次 → 动画 1 个、伤害照打 3 次；24 以内不再画、24 以外画、0.2 秒后再画；余震圈和爆炸动画各记各的；旋钮关掉恢复
##   B 实战：敌人挤成一团，放 S2（饱和复仇，4 连发打随机目标）+ S1，逐帧记炮击动画的位置 / 时间，开着去重时没有「0.2 秒内 24 以内」的两个；关掉去重时有（证明测得出）
## godot --headless --path game res://tests/wisadel_boom_test.tscn -- --balance --seed=1 --op=wisadel
## 全部通过时打印 "WISADEL BOOM checks=N failures=0"；--capture 时逐帧存图到 build/wisadel_boom_<on|off>/（录前后对比用）
const Seg = preload("res://scripts/characters/blocks/seg_wisadel.gd")
const Bal = preload("res://scripts/core/balance.gd")
var g
var checks := 0
var failures := 0


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func sprites() -> Array:
	return g.fx.filter(func(f): return f.get("name", "") == "fx_wisadel_cannon")


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	var capture: bool = OS.get_cmdline_user_args().has("--capture")
	var o = g.squad.get_op("wisadel")
	var a: Dictionary = o.B.attack
	unit_part(o, a)
	var dup_on: int = await scene_part(o, true, capture)
	var dup_off: int = await scene_part(o, false, capture)
	ok(dup_on == 0, "实战：开着去重，0.2 秒内 24 以内没有第二个爆炸动画（%d 对）" % dup_on)
	ok(dup_off > 0, "实战：关掉去重能看到重复（%d 对）——测试测得出" % dup_off)
	print("WISADEL BOOM checks=%d failures=%d dup_on=%d dup_off=%d" % [checks, failures, dup_on, dup_off])
	get_tree().quit(1 if failures > 0 else 0)


func clear_enemies() -> void:
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()


func unit_part(o, a: Dictionary) -> void:
	clear_enemies()
	var p: Vector2 = g.ppos + Vector2(200.0, 0.0)
	var foes: Array = []
	for k in 3:
		var e: Dictionary = g.spawner.spawn_enemy("bone", p + Vector2(k * 6.0, 0.0))
		e.hp = 1.0e6
		e.maxhp = 1.0e6
		e.spd = 0.0
		foes.append(e)
	g.enemies_sys.build_grid()
	g.fx.clear()
	o.pfx.clear()
	var wd: Dictionary = Seg._h4wd(o)
	wd.booms = []
	wd.qbooms = []
	wd.dup_skipped = 0
	var hp0: float = foes[0].hp
	Seg._h4_explode(o, a, p, 10.0, 60.0, "src", 0, 0.0)   # 先炸一次，量出一发的伤害（含倍率）
	var one: float = hp0 - foes[0].hp
	ok(one > 0.0 and sprites().size() == 1, "第一发：有伤害、画 1 个（%.1f）" % one)
	hp0 = foes[0].hp
	for k in 2:
		Seg._h4_explode(o, a, p, 10.0, 60.0, "src", 0, 0.0)
	ok(sprites().size() == 1, "同一点同一帧再炸 2 次：动画仍只 1 个（%d）" % sprites().size())
	ok(absf((hp0 - foes[0].hp) - 2.0 * one) < 0.01, "伤害照打（%.1f ≈ %.1f）" % [hp0 - foes[0].hp, 2.0 * one])
	ok(int(wd.dup_skipped) == 2, "记了 2 次去重（%d）" % int(wd.dup_skipped))
	Seg._h4_explode(o, a, p + Vector2(20.0, 0.0), 10.0, 60.0, "src", 0, 0.0)
	ok(sprites().size() == 1, "半径 24 以内不再画")
	Seg._h4_explode(o, a, p + Vector2(40.0, 0.0), 10.0, 60.0, "src", 0, 0.0)
	ok(sprites().size() == 2, "半径 24 以外画一个（%d）" % sprites().size())
	g.t += 0.25
	Seg._h4_explode(o, a, p, 10.0, 60.0, "src", 0, 0.0)
	ok(sprites().size() == 3, "0.2 秒之后同一处再画（%d）" % sprites().size())
	var rings0: int = o.pfx.filter(func(f): return f.get("kind", "") == "ring").size()
	Seg._h4_explode(o, a, p, 10.0, 60.0, "src", 0, 0.0, false, false, "quake")
	var rings1: int = o.pfx.filter(func(f): return f.get("kind", "") == "ring").size()
	ok(rings1 > rings0, "余震圈和爆炸动画各记各的：同处刚炸完，余震圈照画")
	Seg._h4_explode(o, a, p, 10.0, 60.0, "src", 0, 0.0, false, false, "quake")
	ok(o.pfx.filter(func(f): return f.get("kind", "") == "ring").size() == rings1, "同处两次余震，圈只画一次")
	# 旋钮关掉：恢复每发都画
	Bal._data["fx"]["boom_dedup_t"] = 0.0
	g.t += 1.0
	g.fx.clear()
	for k in 3:
		Seg._h4_explode(o, a, p, 10.0, 60.0, "src", 0, 0.0)
	ok(sprites().size() == 3, "fx/boom_dedup_t = 0：每发都画（%d）" % sprites().size())
	Bal._data["fx"]["boom_dedup_t"] = 0.2
	clear_enemies()


## 返回「0.2 秒内 24 以内」的炮击动画对数
func scene_part(o, dedup: bool, capture: bool) -> int:
	clear_enemies()
	Bal._data["fx"]["boom_dedup_t"] = 0.2 if dedup else 0.0
	o.is_leader = true
	o.pos = g.ppos
	o.sp = [0.0, 0.0, 0.0]
	var foes: Array = []
	for k in 8:   # 挤成一团的敌人（互相 ≤ 30）：S2 后半段的随机目标会落在很近的点上
		var e: Dictionary = g.spawner.spawn_enemy("bone", g.ppos + Vector2(230.0, 0.0) + Vector2(float(k % 4) * 7.0, float(k / 4) * 8.0))
		e.hp = 1.0e9
		e.maxhp = 1.0e9
		e.spd = 0.0
		foes.append(e)
	var wd: Dictionary = Seg._h4wd(o)
	wd.booms = []
	wd.qbooms = []
	wd.dup_skipped = 0
	wd.dup_kinds = {}
	g.fx.clear()
	var known: Array = []   # 已记录过的动画（Dictionary 按引用比，is_same）
	var rec: Array = []   # [{pos, t}]
	var out_dir := ProjectSettings.globalize_path("res://../build/wisadel_boom_%s" % ("on" if dedup else "off"))
	if capture:
		DirAccess.make_dir_recursive_absolute(out_dir)
		g.cam.zoom = Vector2(1.5, 1.5)
		g.glance_pos = g.ppos + Vector2(140.0, 0.0)
	o.start_skill(Vector2.INF, 1)
	var steps := int(7.0 / (1.0 / 60.0))
	for i in steps:
		g.hp = g.max_hp
		g.move_in = Vector2.ZERO
		for e in foes:
			e.hp = 1.0e9
		if capture:
			g.glance_pos = g.ppos + Vector2(140.0, 0.0)
			g.glance_t = g.glance_ease
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		for f in sprites():
			var is_new := true
			for k in known:
				if is_same(k, f):
					is_new = false
					break
			if is_new:
				known.append(f)
				rec.append({"pos": f.pos, "t": g.t})
		if capture and i % 2 == 0:
			g.world.update_visuals(1.0 / 60.0)
			g.world.present_step()
			g.queue_redraw()
			g.fx_add.queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join("f_%04d.png" % i))
	var dups := 0
	for i in rec.size():
		for j in range(i + 1, rec.size()):
			if absf(float(rec[i].t) - float(rec[j].t)) < 0.2 and Vector2(rec[i].pos).distance_to(Vector2(rec[j].pos)) <= 24.0:
				dups += 1
	print("  scene dedup=%s sprites=%d dups=%d skipped=%d kinds=%s" % [dedup, rec.size(), dups, int(wd.dup_skipped), wd.dup_kinds])
	Bal._data["fx"]["boom_dedup_t"] = 0.2
	clear_enemies()
	return dups
