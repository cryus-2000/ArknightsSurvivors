extends RefCounted
## EA 演练沿用正式 Boss 生成、AI 和战斗；跳过波次/经济/结局，进度在退出时还原。
const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
const Squads = preload("res://scripts/run/practice_squads.gd")   # 成品分队（测试台到场快照，docs/170）
const Meta = preload("res://scripts/core/meta.gd")
var g: Game
var active := false
var started_at := 0.0
var config: Dictionary = {}
var saved_progress: Dictionary = {}
var targets: Array = []
var squad_snap: Dictionary = {}   # 选了成品分队时：这组 Boss 对应登场位的快照
# ---- 演练记录（11-01 用户想看「最新的 Boss 试炼用时和造成的伤害」：原来试炼局不写 runs.jsonl）。只记账，不改玩法
var move := ""                     # 当前这一下的招式标签（telegraph.warn_damage 结算期间设，结算完清空）
var boss_dmg: Dictionary = {}      # 干员 id → 对 Boss（含二阶段）造成的有效伤害
var boss_dmg_type: Dictionary = {} # Boss 类型 → 受到的有效伤害
var taken: Dictionary = {}         # 招式标签 → 队长承受伤害（安全模式下照记，只是血会补满）
var taken_n: Dictionary = {}       # 招式标签 → 命中次数
var casts: Dictionary = {}         # 招式标签 → 出手次数（有伤害的预警，每段算一次；命中率 = taken.hits / casts）
var phase_log: Array = []          # [Boss 类型, 阶段, 进入时刻（演练秒）]；击破记成阶段 0
var _phase_seen: Dictionary = {}
var recorded := false

func _init(game: Game) -> void:
	g = game

## 体检分支专用（claude/boss-diag-1101，不合入）：--diagtrial=<Boss 组用 + 连接>:<成品分队> 起一局演练，--diagbot 保留批跑模式让机器人打，
## --diagmax=<秒> 超时收尾；每局结束打印 TRIALREC <run.trial JSON> 后退出
static func diag() -> bool:
	return Cfg.dev_args().has("--diagbot")


func consume() -> void:
	for a in Cfg.dev_args():
		if a.begins_with("--diagtrial="):
			var p: PackedStringArray = a.substr(12).split(":")
			Cfg.boss_trial_request = {"group": Array(p[0].split("+")), "operator": "mizuki", "growth": 2, "phase": 1, "safe": true, "squad": p[1] if p.size() > 1 else ""}
	Meta.practice_budget = -1
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
	# 成品分队：开局干员、认知档都按快照（认知在 Meta.apply_run 读 practice_budget，那一步在本函数之后、setup 之前）
	Meta.practice_budget = -1
	squad_snap = {}
	var sq := str(config.get("squad", ""))
	if sq != "":
		squad_snap = Squads.snap_for(sq, group)
		var info: Dictionary = Squads.squad(sq)
		if not squad_snap.is_empty():
			config.operator = str(info.get("op", config.get("operator", "")))
			Meta.practice_budget = int(info.get("meta", 0))
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
	if not diag():
		g.mode = g.Mode.PLAY   # 演练按正式模式跑（不记自测 / 批跑）
	g.state = g.S.PLAY
	# 按正式登场时间计算 Boss 血量，演练计时不触发普通波次或结局事件。
	g.t = 600.0 if g.spawner.is_final_boss_type(config.group[0]) else 420.0
	started_at = g.t
	g.ppos = Vector2.ZERO
	g.spawner.enter_arena(config.group[0])
	g.ppos = g.map.push_out(g.zone_c + Vector2(150, 50), 12.0)
	g.ch.pos = g.ppos
	if not squad_snap.is_empty():
		g.bench.apply_build(squad_snap)   # 成品分队：重放那支队伍打到这只 Boss 时的成长（干员 / 精英化 / 藏品 / 选卡）
		g.ppos = g.map.push_out(g.zone_c + Vector2(150, 50), 12.0)   # 换队长会把位置挪到新队长身上：摆回演练起点
		g.ch.pos = g.ppos
		g.show_queue.clear()
		g.sync_stats()
	else:
		var guard := 0
		while g.ch.elite < int(config.get("growth", 2)) and not g.ch.next_node().is_empty() and guard < 24:
			guard += 1
			var node: Dictionary = g.ch.next_node()
			var choices: Dictionary = g.ch.elite_choices(node) if node.get("type", "") == "elite" else {}
			g.ch.advance(choices.keys()[0] if not choices.is_empty() else "")
		g.show_queue.clear()
		g.sync_stats()
		Squads.lift(g, config.group)   # 自选队长：等级与属性补到打到这只 Boss 时的平均水平（不再是 1 级白板）
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
	_watch_phases()
	if diag() and not recorded:
		var cap := 300.0
		for a in Cfg.dev_args():
			if a.begins_with("--diagmax="):
				cap = float(a.substr(10))
		if won() or g.t - started_at > cap:
			record("win" if won() else "timeout")
			g.get_tree().quit()
			return
	for e in targets:
		if e.type == "ishar" and e.phase == 1:
			g.ishar.practice_targets(e)
	g.lamp = 100.0
	if config.get("safe", true):
		g.hp = g.max_hp
	g.pending_levelups = 0
	g.pending_chests = 0
	g.chest_src.clear()
	g.gems.clear()
	g.show_queue.clear()

## 每帧看各 Boss 的阶段：变了就记一笔（击破记阶段 0）
func _watch_phases() -> void:
	for i in targets.size():
		var e: Dictionary = targets[i]
		var ph: int = 0 if e.dead else int(e.get("phase", 1))
		var key := "%d" % i
		if int(_phase_seen.get(key, -1)) != ph:
			_phase_seen[key] = ph
			phase_log.append([str(e.type), ph, snappedf(g.t - started_at, 0.1)])


## 队长掉血（combat.lose_hp 调用）：按招式标签记；没有招式标签的按来源键（敌弹 / 接触 / 冲击环 / 侵蚀……）
func on_lose(amount: float, src: String) -> void:
	if not active or amount <= 0.0:
		return
	var key: String = move if move != "" else src
	taken[key] = float(taken.get(key, 0.0)) + amount
	taken_n[key] = int(taken_n.get(key, 0)) + 1


## Boss 放出一段有伤害的预警（telegraph.warn 调用）：按招式标签数出手次数
func on_cast(w: Dictionary) -> void:
	if not active or float(w.get("dmg", 0.0)) <= 0.0:
		return
	var key := move_tag(w)
	casts[key] = int(casts.get(key, 0)) + 1


## 对 Boss 的有效伤害（telemetry.on_dmg 调用）
func on_boss_dmg(op: String, e: Dictionary, eff: float) -> void:
	if not active or eff <= 0.0 or not e.get("boss", false) or e.get("friendly", false):
		return
	boss_dmg[op] = float(boss_dmg.get(op, 0.0)) + eff
	var ty := str(e.type)
	boss_dmg_type[ty] = float(boss_dmg_type.get(ty, 0.0)) + eff


## 招式标签：Boss 类型 / 招式名（无名的分段用皮肤或动作名）
static func move_tag(w: Dictionary) -> String:
	var o = w.get("owner")
	var ty: String = str(o.get("type", "")) if o is Dictionary else ""
	var nm: String = str(w.get("name", ""))
	if nm == "":
		nm = str(w.get("skin", ""))
	if nm == "":
		nm = str(w.get("act", ""))
	return ty + "/" + nm


## 一局演练的记录（telemetry.save_trial 写进 runs.jsonl 的 run.trial）：胜 / 负 / 退出各写一次
func report(result: String) -> Dictionary:
	_watch_phases()
	var bosses: Array = []
	for e in targets:
		bosses.append({"type": str(e.type), "phase": int(e.get("phase", 1)), "dead": bool(e.dead),
			"hp": snappedf(maxf(0.0, float(e.hp)), 1.0), "maxhp": snappedf(float(e.maxhp), 1.0),
			"hp_pct": snappedf(maxf(0.0, float(e.hp)) / maxf(1.0, float(e.maxhp)), 0.001)})
	# 各阶段用时：按 phase_log 相邻两笔相减（最后一段到结束）
	var dur: float = snappedf(g.t - started_at, 0.1)
	var phases: Array = []
	for i in phase_log.size():
		var p: Array = phase_log[i]
		if int(p[1]) == 0:
			continue
		var t1: float = dur
		for j in range(i + 1, phase_log.size()):
			if str(phase_log[j][0]) == str(p[0]):
				t1 = float(phase_log[j][2])
				break
		phases.append({"type": str(p[0]), "phase": int(p[1]), "t0": float(p[2]), "t": snappedf(t1 - float(p[2]), 0.1)})
	var dmg_ops := {}
	for k in boss_dmg:
		dmg_ops[k] = snappedf(float(boss_dmg[k]), 1.0)
	var dmg_types := {}
	for k in boss_dmg_type:
		dmg_types[k] = snappedf(float(boss_dmg_type[k]), 1.0)
	var tk := {}
	for k in taken:
		tk[k] = {"dmg": snappedf(float(taken[k]), 0.1), "hits": int(taken_n.get(k, 0))}
	var killer: Dictionary = {}
	if result == "dead":
		killer = g.telemetry.killer()
	return {"group": config.get("group", []), "phase": int(config.get("phase", 1)), "growth": int(config.get("growth", 2)),
		"squad": str(config.get("squad", "")), "operator": str(config.get("operator", "")), "safe": bool(config.get("safe", true)),
		"ops": g.squad.ops.map(func(o): return str(o.id)), "leader_elite": int(g.ch.elite) if g.ch != null else 0, "level": g.level,
		"max_hp": snappedf(g.max_hp, 1.0), "result": result, "t": dur, "phases": phases, "phase_log": phase_log.duplicate(true),
		"bosses": bosses, "boss_dmg": dmg_ops, "boss_dmg_type": dmg_types, "taken": tk, "casts": casts.duplicate(),
		"taken_total": snappedf(taken.values().reduce(func(a, b): return a + b, 0.0), 0.1),
		"downs": int(g.squad.downs_n), "dead": result == "dead", "killer": killer}


## 写一次（胜 / 负进入时 game._process 调；退出时 game._exit_tree 调）
func record(result: String) -> void:
	if not active or recorded:
		return
	recorded = true
	if diag():
		print("TRIALREC ", JSON.stringify(report(result)))
		return
	g.telemetry.save_trial(result, report(result))


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
	Meta.practice_budget = -1
