extends Node
var game: Node
var frames := 0
var fails := 0
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func check(v: bool, label: String) -> void:
	if not v:
		fails += 1
		push_error(label)
func choose(ev: String, suffix: String) -> void:
	game.endg.open(ev)
	for i in game.choices.size():
		if str(game.choices[i].id).ends_with(suffix):
			game.progression.pick(i)
			return
	check(false, "missing choice " + ev + suffix)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	# 路线测试显式提供结局一通关前置，不依赖本机存档或 --balance 隐式解锁。
	game.endg.all_unlocked = true
	game.t = 250.0
	choose("madness", ":0")
	check(game.knight.alive and game.relics.has("222"), "madness choice summons living knight")
	game.t = 450.0
	choose("knight_stay", ":1")
	check(game.relics.has("225") and game.state == game.S.PLAY and not game.panel.visible, "knight_stay grants bone blood and closes")
	check(game.endg.cur == "knight", "knight route with living knight")
	# 深蓝之心线（docs/154）：开端 → 深蓝之心（房间付源石锭、可连选）→ 园林 → 赞歌
	_fresh_game()
	game.ingots = 30
	choose("opening", ":0")
	check(game.relics.has("220") and game.endg.cur == "standard", "opening: bishop's research does not change the ending yet")
	choose("heart", ":2")
	check(game.state == game.S.CHOICE and game.endg.opened_id == "heart" and game.ingots == 22, "a room costs 8 ingots and the lab stays open")
	check(not game.choices.any(func(o): return o.id == "heart:2"), "a searched room is not offered again")
	var garden := -1
	for i in game.choices.size():
		if game.choices[i].id == "heart:5":
			garden = i
	game.progression.pick(garden)
	check(game.relics.has("221") and game.endg.opened_id == "hymn", "garden grants the heart and opens the hymn")
	choose("hymn", ":1")
	check(game.endg.cur == "deep" and game.state == game.S.PLAY, "deep line ends at ending three")
	# 升华线：开端 → 深蓝仪式 → 升华（三句都可选，灯火不限）
	_fresh_game()
	game.lamp = 5.0
	choose("opening", ":1")
	check(game.relics.has("242") and game.endg.cur == "standard", "opening: blue memory starts the ascension line")
	choose("ritual", ":0")
	check(game.endg.opened_id == "ascend" and game.choices.size() == 3, "ritual leads to ascend with three answers")
	choose("ascend", ":0")
	check(game.relics.has("238") and game.endg.cur == "resolve", "resolve at lamp 5 still reaches ending four")
	choose("madness", ":0")   # 下面的骑士出圈检查要一名在场的骑士
	check(game.endg.cur == "resolve", "ascension token outranks the knight (priority)")
	game.zone_state = 2
	game.zone_c = Vector2.ZERO
	game.zone_r = 400.0
	game.ppos = Vector2.ZERO
	var b: Dictionary = game.spawner.spawn_enemy("knight_boss", Vector2(390, 0))
	b.age = 10.0
	for side in [-1.0, 1.0]:
		b.pos = Vector2(side * 390.0, 0)
		b.kb = Vector2(side * 1500.0, 0)
		b.kb_self = true
		game.enemies_sys.update(0.1)
		check(absf(b.pos.x) <= 244.0, "boss charge keeps drawn body inside tide on both sides")
		game.knight.pos = Vector2(side * 390.0, 0)
		game.knight.state = "charge"
		game.knight.st = 0.0
		game.knight.dash_dir = Vector2(side, 0)
		game.knight.update(0.1)
		check(game.knight.pos.length() <= 267.0, "ally charge stays inside tide")
	# 圈顶最大画幅角点：受击拉伸与上浮同时存在也必须在圆内。
	b.pos = Vector2(0, -390)
	b.kb = Vector2(0, -1500)
	b.kb_self = true
	b.squash = 0.14
	game.enemies_sys.update(0.1)
	for side in [-1.0, 1.0]:
		var corner := Vector2(side * (48.0 * 1.4 * 1.3 + 2.0), -(80.0 * 1.4 + 16.0))
		check((b.pos + corner).distance_to(game.zone_c) <= game.zone_r, "boss upper corner and lift remain in circle")
	game.knight.pos = Vector2(0, -390)
	game.knight.state = "charge"
	game.knight.st = 0.0
	game.knight.dash_dir = Vector2.UP
	game.knight.update(0.1)
	for side in [-1.0, 1.0]:
		var corner := Vector2(side * (48.0 * 1.4 + 2.0), -(80.0 * 1.4 + 2.0))
		check((game.knight.pos + corner).distance_to(game.zone_c) <= game.zone_r, "ally upper corner remains in circle")
	game.zone_c = Vector2(90, -60)
	game.zone_r = 210.0
	game.enemies_sys.update(0.1)
	game.knight.state = "retreat"
	game.ppos = Vector2(900, 0)
	game.knight.update(0.1)
	check(b.pos.distance_to(game.zone_c) <= 54.0, "boss follows shrinking shifted arena")
	check(game.knight.pos.distance_to(game.zone_c) <= 77.0, "ally retreat cannot follow player into tide")
	_final_flow()
	_walk_death()
	_camera_glance_matches_spawn()
	print("ROUTE KNIGHT REGRESSION: ", fails, " failures")
	game.queue_free()
	game = null
	# Muting does not release mixer-owned playbacks. Let queued starts settle,
	# then destroy the players and allow the audio thread to retire its refs.
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(fails)


## 新开一局（结局线已解锁、无待开面板）
func _fresh_game() -> void:
	game.queue_free()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.endg.all_unlocked = true


## 新开一局骑士路线（狂徒妄念 → 骑士加入），黑潮已启动，队长在原点
func _fresh_knight_game(zone_c: Vector2) -> void:
	game.queue_free()
	game = load("res://game.tscn").instantiate()
	add_child(game)
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	game.endg.all_unlocked = true
	game.t = 160.0
	choose("madness", ":0")
	check(game.knight.alive and game.endg.cur == "knight", "fresh route game has living knight")
	game.zone_state = 2
	game.zone_c = zone_c
	game.zone_r = 520.0
	game.ppos = Vector2.ZERO
	game.facing = 1.0
	game.knight.pos = Vector2(-66, 26)
	game.vfx.banner_log.clear()


func _count_banner(sub: String) -> int:
	var n := 0
	for s in game.vfx.banner_log:
		if str(s).contains(sub):
			n += 1
	return n


## 一帧终局逻辑（game.gd 的顺序：终局预告 → 骑士 tick_final → 骑士 update）
func _final_step(dt: float) -> void:
	game.t += dt
	game.endg.tick_final_warning()
	game.knight.tick_final()
	game.knight.update(dt)


## 结局二终局流程（2026-10-14 用户定）：9:00 走向黑潮中心、到达入潮消失、提醒只一次、消失后不参与、10:00 Boss 从中心出现
func _final_flow() -> void:
	const Dt = preload("res://scripts/data.gd")
	_fresh_knight_game(Vector2(300, 0))
	game.t = 538.0
	for i in 20:
		_final_step(0.05)   # 到 539.0：还没到 9:00
	check(game.knight.state != "walk" and not game.knight.walked, "knight does not walk before 9:00")
	check(_count_banner("黑潮中心") == 0, "no walk banner before 9:00")
	var walk_seen := false
	var t_arrive := -1.0
	for i in 1100:   # 539.0 → 594.0
		_final_step(0.05)
		if game.knight.state == "walk":
			walk_seen = true
		if game.knight.submerged and t_arrive < 0.0:
			t_arrive = game.t
	check(walk_seen, "knight walks to the tide center from 9:00")
	check(game.knight.walked, "walked flag set once")
	check(t_arrive > 540.0 and t_arrive < 548.0, "knight reaches center and submerges within a few seconds (t=%.1f)" % t_arrive)
	check(game.knight.submerged and not game.knight.alive, "knight is submerged, no longer a living ally")
	check(game.knight_alive and game.endg.cur == "knight", "ending flag keeps knight route while submerged")
	check(game.knight.vanish_pos.distance_to(game.zone_c) <= 8.0, "knight vanished at the tide center")
	check(_count_banner("骑士走向了黑潮中心") == 1, "walk reminder shown exactly once (got %d)" % _count_banner("骑士走向了黑潮中心"))
	check(_count_banner("没入") == 1, "submerge banner shown once")
	check(game.endg.reserved_relic_slots() >= 1, "submerged knight still reserves the ending relic slot")
	# 消失后不参与：不吃治疗、不拉仇恨、不出手、不被碰到
	game.knight.hp = 100.0
	game.knight.heal(500.0)
	check(game.knight.hp == 100.0, "submerged knight takes no healing")
	var mob: Dictionary = {}
	for k in Dt.ENEMIES:
		var dd: Dictionary = Dt.ENEMIES[k]
		if dd.get("ai", "") == "melee" and not dd.get("boss", false) and not dd.get("no_spawn", false) and float(dd.get("dmg", 0.0)) > 0.0:
			mob = game.spawner.spawn_enemy(k, game.knight.vanish_pos + Vector2(10, 0))
			break
	check(not mob.is_empty(), "found a melee mob type for the submerged check")
	if not mob.is_empty():
		mob.aggro = Vector2.INF
		mob.elite = true
		game.enemies_sys.build_grid()
		var st0: String = game.knight.state
		var hp0: float = game.knight.hp
		for i in 40:
			_final_step(0.05)
		check(mob.aggro == Vector2.INF, "submerged knight pulls no aggro")
		check(game.knight.hp == hp0 and game.knight.state == st0 and not game.knight.alive, "submerged knight neither attacks nor gets hit")
		mob.dead = true
	# 10:00：最终 Boss 从黑潮中心出现，寒冰重生横幅照旧
	game.spawner.boss_idx = Dt.BOSS_TIMES.size() - 1
	game.t = 600.0
	game.spawner.update(0.05)
	var fb = game.final_boss
	check(fb != null and fb.type == "knight_boss", "final boss is the last knight")
	if fb != null:
		check(fb.pos.distance_to(Vector2(300, 0)) <= 12.0, "final boss rises at the tide center (d=%.1f)" % fb.pos.distance_to(Vector2(300, 0)))
	check(_count_banner("寒冰重生 —— 最后的骑士") == 1, "rebirth banner shown at 10:00")
	check(game.knight_alive and not game.knight.alive and not game.knight.submerged, "after take_over the ally slot is gone, ending flag stays")


## 9:00 之后、到达之前阵亡：走原阵亡逻辑（退行 223、结局回退），不入潮
func _walk_death() -> void:
	const Dt = preload("res://scripts/data.gd")
	_fresh_knight_game(Vector2(900, 0))
	game.t = 540.0
	_final_step(0.05)
	check(game.knight.state == "walk", "knight walking at 9:00")
	game.knight.hp = 1.0
	var mob: Dictionary = {}
	for k in Dt.ENEMIES:
		var dd: Dictionary = Dt.ENEMIES[k]
		if dd.get("ai", "") == "melee" and not dd.get("boss", false) and not dd.get("no_spawn", false) and float(dd.get("dmg", 0.0)) > 0.0:
			mob = game.spawner.spawn_enemy(k, game.knight.pos)
			break
	if not mob.is_empty():
		mob.elite = true
		for i in 10:
			mob.pos = game.knight.pos
			game.enemies_sys.build_grid()
			_final_step(0.05)
	check(game.knight.fallen and not game.knight.alive and not game.knight.submerged, "knight killed on the way falls (no submerge)")
	check(game.relics.has("223") and game.endg.cur != "knight", "walk death grants 223 and the ending falls back")
	check(_count_banner("没入") == 0, "no submerge banner after a walk death")


## 10-20 修：enter_arena 的 freeze_zone 会把场地圆心拉向主控，take_over 当时给的落点可能被后面的 arena_clamp 挪走；
## 镜头一瞥（camera_glance）必须用挪走之后的最终落点，否则镜头看的地方是空的（正式局「刚开始骑士没有出现」）。
## 主控离旧黑潮圆心够远（> arena_r - 100），才会触发 freeze_zone 的圆心内收、进而触发 arena_clamp 的二次搬移。
func _camera_glance_matches_spawn() -> void:
	const Dt = preload("res://scripts/data.gd")
	_fresh_knight_game(Vector2(300, 0))
	game.knight.alive = false
	game.knight.submerged = true
	game.knight.vanish_pos = Vector2(300, 0)
	game.ppos = Vector2(1300, 0)   # 离旧黑潮圆心 1000，远超 arena_r(520) - 100
	game.spawner.boss_idx = Dt.BOSS_TIMES.size() - 1
	game.t = 600.0
	game.spawner.update(0.05)
	var fb = game.final_boss
	check(fb != null and fb.type == "knight_boss", "final boss spawns via take_over + arena_clamp")
	if fb != null:
		check(fb.pos.distance_to(Vector2(300, 0)) > 60.0, "arena_clamp actually moved the spawn point in this setup (sanity check)")
		check(game.glance_pos.distance_to(fb.pos) <= 12.0, "camera glances at the knight's actual (post-clamp) spawn point, not the stale pre-clamp one (d=%.1f)" % game.glance_pos.distance_to(fb.pos))
