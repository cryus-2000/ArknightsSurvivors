extends Node
## godot --headless --path game res://tests/run_journey_test.tscn -- --regression
const Journey = preload("res://scripts/core/run_reload.gd")
var demo_op := ""
var trial := {"active": false}
var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("RUN JOURNEY: " + what)


func _ready() -> void:
	demo_op = "mizuki"
	Journey.begin_run(self)
	demo_op = ""
	trial.active = true
	Journey.begin_run(self)
	trial.active = false
	check(Journey.run_identity().is_empty(), "演示与演练不计局数")
	Journey.begin_run(self)
	Journey.begin_run(self)
	var first := Journey.run_identity()
	check(first.run == 1, "同一个场景只记一次")
	Journey.mark_stage("settled")
	var saved := Journey.journey_snapshot(first)
	Journey.mark_stage("reload_request", "hunt")
	Journey.mark_stage("reload_failed", "hunt")
	Journey.mark_stage("title_ready")
	Journey.mark_stage("hunt_open")
	var second := duplicate()   # 不入树，仅提供不同的场景实例号
	Journey.begin_run(second)
	second.free()
	check(Journey.run_identity().run == 2, "同页再开累加")
	check("同页再开" in Journey.journey_lines(Journey.run_identity())[0], "给出同页再开来源")
	check(Journey.journey_snapshot(first).events.back().kind == "run_start", "旧局报告可补到下一局开局")
	check(Journey.journey_snapshot({}).is_empty(), "旧报告不串当前局")
	for i in 30:
		Journey.mark_stage("hunt_open")
	check(Journey.journey_snapshot(first).is_empty(), "环形窗口淘汰")
	check(not Journey.journey_lines(first, saved).is_empty(), "旧局沿用局终快照")
	check(Journey.journey_lines({"session":first.session, "run":9}, saved).is_empty(), "不沿用别局快照")
	print("RUN JOURNEY failures=", failures)
	get_tree().quit(1 if failures else 0)
