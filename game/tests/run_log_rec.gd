extends Node
## 作战记录 / 对局记录录帧（10-29；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/run_log_rec.tscn -- --shotdir=<目录> --runslog=<runs.jsonl 副本> [--rec_leader=<id>] [--touch]
## 流程（按键直接喂各界面的 key()，原速）：失败结算 → 作战记录（↓ 换干员）→ 返回结算 → 对局记录（↓ ↑）→ ENTER 进最新一局的作战记录
##   → ENTER 干员详情 → ESC 总览 → ESC 对局记录 → ESC 结算。
## 对局记录读 --runslog 指的文件（同 telemetry.save_local 的测试路径）；本场景不跑对局，不会往里写。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const Screen = preload("res://scripts/screens/settlement_screen.gd")
const UM = preload("res://scripts/ui_motion.gd")

class Probe extends Screen:
	func _run(id: String) -> void:
		if id == "records":
			_records()

var game: Node
var frames := 0
var shot_dir := ""
var leader := "specter_unchained"
var s
var f := 0
var plan: Array = []   # [秒, 动作]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a.begins_with("--rec_leader="):
			leader = a.substr(13)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _raw() -> Dictionary:
	var raw: Dictionary = RunStats.fake_raw()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/%s.json" % leader))
	for o in raw.ops:
		o.leader = false
	raw.ops.insert(0, {"id": leader, "name": str(d.name), "en": str(d.get("en", leader.to_upper())), "col": d.col, "leader": true, "t": 0.0, "left": -1.0, "elite": 2})
	raw.op_out[leader] = {"普攻": 210000.0, "技能": 160000.0, "天赋": 52000.0}
	raw.op_kills[leader] = 900
	raw.op_casts[leader] = 24
	var gone: Dictionary = raw.ops.pop_back()
	raw.op_out.erase(gone.id)
	raw.result = "dead"
	raw.killer = {"type": "", "env": "dark", "name": "寂灭", "cause": "灯火寂灭后的持续伤害"}
	raw.t = 655.0
	raw.final_boss = {}
	return raw


func _process(d: float) -> void:
	frames += 1
	if frames == 4:
		game.set_process(false)
		game.hud.size = get_viewport().get_visible_rect().size / Cfg.ui_k   # 手机界面层放大（同 game 里 hud 的尺寸）
		game.state = Game.S.DEAD
		game.state_age = 99.0
		s = Probe.new(game)
		game.settlement = s
		s.set_model(RunStats.model(_raw()))
		s.cells = 41
		s.vouchers = 1
		var t0: float = s._end() + 1.0
		plan = [[t0, "records"], [t0 + 2.6, KEY_DOWN], [t0 + 3.3, KEY_DOWN], [t0 + 4.2, "esc"],
			[t0 + 5.4, "log"], [t0 + 6.4, "down"], [t0 + 6.9, "down"], [t0 + 7.3, "up"], [t0 + 7.8, "enter"],
			[t0 + 10.6, KEY_ENTER], [t0 + 12.4, KEY_ESCAPE], [t0 + 13.4, KEY_ESCAPE], [t0 + 14.6, "logesc"], [t0 + 15.6, "end"]]
	if s == null:
		return
	UM.advance(d)   # game 的 _process 停了，界面时钟手动推
	s.tick(d)
	game.kb_nav = true
	var now := f / 30.0
	while not plan.is_empty() and now >= float(plan[0][0]):
		var a = plan.pop_front()[1]
		match a:
			"records":
				s._run("records")
			"esc":
				game.run_stats.key(KEY_ESCAPE)
			"log":
				game.run_log.open_log()
			"down":
				game.run_log.key(KEY_DOWN)
			"up":
				game.run_log.key(KEY_UP)
			"enter":
				game.run_log.key(KEY_ENTER)
			"logesc":
				game.run_log.key(KEY_ESCAPE)
			"end":
				get_tree().quit(0)
				return
			_:
				game.run_stats.key(int(a))
	game.hud.queue_redraw()
	get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%04d.png" % f)
	f += 1
