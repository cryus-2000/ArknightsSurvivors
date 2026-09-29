extends RefCounted
## EA 演练沿用正式 Boss 生成、AI 和战斗；跳过波次/经济/结局，进度在退出时还原。
const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
var g: Game
var active := false
var started_at := 0.0
var config: Dictionary = {}
var saved_progress: Dictionary = {}
var targets: Array = []

func _init(game: Game) -> void:
	g = game

func consume() -> void:
	if g.demo_op != "" or Cfg.boss_trial_request.is_empty():
		return
	var request: Dictionary = Cfg.boss_trial_request.duplicate(true)
	Cfg.boss_trial_request.clear()
	if not Cfg.can_boss_trial():
		return
	var group: Array = []
	for id in request.get("group", []):
		if D.ENEMIES.has(id) and D.ENEMIES[id].get("role", "") == "boss":
			group.append(id)
	if group.is_empty():
		return
	config = request
	config.group = group
	if not Character.list_ids().has(config.get("operator", "")):
		config.operator = "mizuki"
	active = true
	for key in ["diff_unlocked", "seen_shows", "seen_relics", "seen_intro", "endings_cleared", "opening_seen"]:
		var value = Cfg.get(key)
		saved_progress[key] = value.duplicate(true) if value is Array else value
	Cfg.practice_active = true

func setup() -> void:
	if not active:
		return
	g.autotest = false
	g.balance = false
	g.state = g.S.PLAY
	# 按正式登场时间计算 Boss 血量，演练计时不触发普通波次或结局事件。
	g.t = 600.0 if g.spawner.is_final_boss_type(config.group[0]) else 420.0
	started_at = g.t
	g.ppos = Vector2.ZERO
	g.spawner.enter_arena(config.group[0])
	g.ppos = g.map.push_out(g.zone_c + Vector2(150, 50), 12.0)
	g.ch.pos = g.ppos
	var guard := 0
	while g.ch.elite < int(config.get("growth", 2)) and not g.ch.next_node().is_empty() and guard < 24:
		guard += 1
		var node: Dictionary = g.ch.next_node()
		var choices: Dictionary = g.ch.elite_choices(node) if node.get("type", "") == "elite" else {}
		g.ch.advance(choices.keys()[0] if not choices.is_empty() else "")
	g.show_queue.clear()
	g.sync_stats()
	g.hp = g.max_hp
	g.hp_trail = g.hp
	for i in config.group.size():
		var id: String = config.group[i]
		var e: Dictionary = g.spawner.spawn_enemy(id, g.zone_c + Vector2(-120, (i - (config.group.size() - 1) * 0.5) * 100.0))
		targets.append(e)
		g.bosses.append(e)
		g.boss = e
		if g.spawner.is_final_boss_type(id):
			g.final_boss = e
		if int(config.get("phase", 1)) == 2:
			g.bai.setup_preview_phase2(e)
	if targets.size() == 2:
		targets[0].partner = targets[1]
		targets[1].partner = targets[0]
	g.vfx.show_banner("Boss 演练 · %s · 不记录通关进度" % ("观察模式（不会倒下）" if config.get("safe", true) else "实战模式"))
	maintain()

func maintain() -> void:
	for e in targets:
		if e.type == "ishar" and e.phase == 1:
			g.ishar.practice_targets(e)
	g.lamp = 100.0
	if config.get("safe", true):
		g.hp = g.max_hp
	g.pending_levelups = 0
	g.pending_chests = 0
	g.gems.clear()
	g.show_queue.clear()

func won() -> bool:
	return active and not targets.is_empty() and targets.all(func(e): return e.dead)

func retry() -> void:
	Cfg.boss_trial_request = config.duplicate(true)

func leave() -> void:
	if not active:
		return
	for key in saved_progress:
		Cfg.set(key, saved_progress[key])
	Cfg.practice_active = false
