extends Node
## 海嗣祭坛不是索敌对象：祭坛在场、没有敌人时，所有干员的索敌 / 区域查询 / 扇形 / 最密点都查不到它，
## 连续自动更新数秒祭坛血量不变、也没有弹丸或事件打开；补给箱（没有 event）仍照常可被索敌
const Character = preload("res://scripts/characters/character.gd")
var game: Node
var frames := 0
var fails := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		push_error(label)
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	game.enemies.clear()
	game.ppos = Vector2.ZERO
	game.spawner.spawn_chest(Vector2(90, 0), "altar_test")
	var altar: Dictionary = game.enemies[-1]
	altar.invuln = true
	game.enemies_sys.build_grid()
	check(game.enemies_sys.query(Vector2.ZERO, 400.0).is_empty(), "grid query does not return the altar")
	check(game.enemies_sys.nearest(3, 400.0).is_empty(), "nearest ignores the altar")
	check(game.enemies_sys.in_range(400.0).is_empty(), "in_range ignores the altar")
	check(game.enemies_sys.densest_point(400.0) == Vector2.INF, "densest point ignores the altar")
	for cid in Character.list_ids():
		var op = Character.create(game, cid)
		op.pos = Vector2.ZERO
		check(op.nearest_enemies(3, 400.0).is_empty(), cid + " does not pick the altar as a target")
		check(op.nearest_raw(3, 400.0).is_empty(), cid + " manual snap does not pick the altar")
		check(op.query_ids(Vector2.ZERO, 400.0).is_empty(), cid + " area query excludes the altar")
		check(op.arc_targets(Vector2.ZERO, 0.0, PI, 400.0).is_empty(), cid + " attack arc excludes the altar")
	var squad_ids: Array = []
	for cid in ["mizuki", "wisadel", "kaltsit"]:
		var op = Character.create(game, cid)
		op.pos = Vector2.ZERO
		game.stats.define_all(op.stat_defs())
		for i in 180:
			op.update(0.0166)
			game.enemies_sys.build_grid()
		check(altar.hp == 22.0 and not altar.dead, cid + " never attacks the altar")
	check(game.bullets.is_empty(), "no operator projectile was fired with only an altar in range")
	# 补给箱（没有 event）仍然是可打的目标
	game.spawner.spawn_chest(Vector2(60, 0))
	game.enemies_sys.build_grid()
	check(game.enemies_sys.nearest(1, 400.0).size() == 1, "an ordinary supply chest is still targetable")
	print("ALTAR NOT TARGET: %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)
