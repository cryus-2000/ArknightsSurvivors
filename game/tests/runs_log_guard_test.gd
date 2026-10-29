extends Node
## 自动测试不写玩家的对局记录（telemetry.save_local）：不带 -- 参数、直接起 res://tests/ 场景的回归也不能写。
## 10-14 / 10-20 / 10-27 的 runs.jsonl 里混进的「水月 lv1 0 击杀 quit」就是这类场景（check.py 里额外参数为空的）绕过了 dev_args 判断。
const Telemetry = preload("res://scripts/run/telemetry.gd")
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)


func _ready() -> void:
	check(Telemetry.scene_is_test("res://tests/reaper_rush_test.tscn"), "tests 下的场景算测试")
	check(not Telemetry.scene_is_test("res://game.tscn"), "game.tscn 不算测试")
	check(not Telemetry.scene_is_test("res://main.tscn"), "main.tscn 不算测试")
	check(not Telemetry.scene_is_test("res://boot.tscn"), "boot.tscn 不算测试")
	check(not Telemetry.scene_is_test(""), "没有当前场景时不判测试（交给 dev_args 与发布判断）")
	check(get_tree().current_scene != null and Telemetry.scene_is_test(get_tree().current_scene.scene_file_path), "本测试自己的场景被认成测试")
	var path := "user://runs/runs.jsonl"
	var before := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 3:
		await get_tree().process_frame
	g.set_process(false)
	g.t = 200.0
	g.telemetry.save_local("quit")
	var after := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	check(after == before, "测试场景里 save_local 不往玩家的 runs.jsonl 追加（前 %d 后 %d）" % [before, after])
	check(not g.telemetry.saved, "被拦下的那次不占用 saved 标记")
	print("RUNS LOG GUARD failures=", failures)
	g.world._gc_sink = null
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)
