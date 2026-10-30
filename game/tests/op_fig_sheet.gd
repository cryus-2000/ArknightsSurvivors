extends Node
## 干员小人大小对照（10-30 用户「对局记录和作战记录里面人物大小不一致」；不进快检）：开窗口逐张存图 sheet_<n>.png。
##   godot --path game res://tests/op_fig_sheet.tscn -- --shotdir=<目录> [--touch]
## 全部干员每 5 人一批放进作战记录编队（第一人当队长，队长卡 + 编队行）存一张总览；再存一张详情（第一人身份卡）；
## 最后一张对局记录：每局 4 人、5 局排满 20 人。动效直接终态。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const Character = preload("res://scripts/characters/character.gd")
const LogScreen = preload("res://scripts/screens/run_log_screen.gd")

var game: Node
var shot_dir := ""
var frames := 0
var shots: Array = []   # Callable：每个画一张
var n := 0
var wait := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _raw(batch: Array) -> Dictionary:
	var raw: Dictionary = RunStats.fake_raw()
	raw.ops = []
	raw.op_out = {}
	raw.result = "dead"
	raw.killer = {"type": "", "env": "dark", "name": "寂灭", "cause": ""}
	raw.final_boss = {}
	for j in batch.size():
		var d: Dictionary = Character.load_def(batch[j])
		raw.ops.append({"id": batch[j], "name": str(d.get("name", batch[j])), "en": str(d.get("en", "")), "col": d.get("col", [0.5, 0.7, 0.9]),
			"leader": j == 0, "t": j * 60.0, "left": -1.0})
		raw.op_out[batch[j]] = {"普攻": 40000.0 - 6000.0 * j}
	return raw


func _plan() -> void:
	var ids: Array = Character.list_ids()
	var k := 0
	while k < ids.size():
		var batch: Array = ids.slice(k, k + 5)
		shots.append(func(): _show(batch, false))
		shots.append(func(): _show(batch, true))
		k += 5
	shots.append(func(): _log(ids))


func _show(batch: Array, detail: bool) -> void:
	game.run_log.close()
	var rs = game.run_stats
	rs.show_model(RunStats.model(_raw(batch)))
	rs.skipped = true
	if detail:
		rs._detail(0)
		rs.skipped = true


func _log(ids: Array) -> void:
	game.run_stats.close()
	var lg = game.run_log
	lg.entries = []
	for i in ceili(ids.size() / 4.0):
		var grp: Array = ids.slice(i * 4, i * 4 + 4)
		var st: Array = []
		for id in grp:
			st.append({"id": id, "dmg": 1000})
		lg.entries.append(LogScreen.summary({"meta": {"result": "dead", "start_op": grp[0], "time": "2026-10-30T01:0%d:00" % i, "version": "2.0", "commit": "sheet"},
			"run": {"t": 300 + 60 * i, "kills": 500, "relics": 3, "op_stats": st, "bot": {"death_src": "dark"}}}))
	lg.open = true
	lg.sel = 0
	lg.t_open = -99.0


func _process(_d: float) -> void:
	frames += 1
	if frames == 4:
		game.set_process(false)
		game.hud.size = get_viewport().get_visible_rect().size / Cfg.ui_k
		game.state = Game.S.DEAD
		game.state_age = 99.0
		game.kb_nav = true
		_plan()
	if frames < 4:
		return
	if wait > 0:
		wait -= 1
		game.hud.queue_redraw()
		if wait == 0:
			get_viewport().get_texture().get_image().save_png(shot_dir + "/sheet_%02d.png" % n)
			n += 1
		return
	if shots.is_empty():
		get_tree().quit(0)
		return
	shots.pop_front().call()
	wait = 3
	game.hud.queue_redraw()
