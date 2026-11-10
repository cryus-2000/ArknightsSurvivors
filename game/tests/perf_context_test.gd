extends SceneTree
## 独立无头运行：--script res://tests/perf_context_test.gd
const Context := preload("res://scripts/core/perf_context.gd")
var failures := 0
var updates := 0


class Member:
	var id: String
	func _init(value: String):
		id = value
	func display_name() -> String:
		return "干员" + id


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)


func _initialize() -> void:
	var tracker := Context.new()
	tracker.changed.connect(func(): updates += 1)
	var run := {"squad": {"ops": [Member.new("1"), Member.new("2")]}}
	check(tracker.snapshot(run).is_empty() and Context.lines({}).is_empty(), "初始化及旧记录")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9007199254740993
	var state_before := rng.state
	tracker.seeded(rng.seed)
	tracker.configured("险路恶敌", 5, 7, 18)
	var ctx := tracker.snapshot(run)
	var decoded = JSON.parse_string(JSON.stringify(ctx))
	check(decoded.seed == "9007199254740993" and rng.state == state_before, "64 位种子 JSON 往返")
	check(decoded.tide == 5 and decoded.diff == 7 and decoded.meta_cells == 18, "本局实配")
	check(Context.lines(decoded)[2].contains("尚未登场"), "有效空历史")
	var boss := {"type": "a", "boss": true}
	var definition := {"role": "boss", "name": "首领甲"}
	tracker.admitted({"type":"part", "boss":true, "part":true}, definition, 5)
	tracker.admitted({"type":"ordinary", "boss":false}, definition, 7)
	tracker.admitted(boss, {"role":"mob"}, 12)
	check(updates == 2, "部件和普通单位不触发写入")
	tracker.admitted(boss, definition, 61.9)
	tracker.admitted(boss, definition, 88)
	boss.clear()
	ctx = tracker.snapshot(run)
	check(ctx.bosses == [{"id":"a", "name":"首领甲", "t":61}] and updates == 3, "实体离场仍保留首次登场")
	ctx.bosses.clear()
	run.squad.ops.pop_at(0)
	ctx = tracker.snapshot(run)
	check(ctx.squad == [{"id":"2", "name":"干员2"}] and ctx.bosses.size() == 1, "阵容更新与快照隔离")
	var rendered := "\n".join(Context.lines(ctx))
	check(rendered.contains("1:01 首领甲") and rendered.contains("干员2") and rendered.contains("难度等级 7"), "同一格式应用于保存与复制")
	for i in range(Context.MAX_BOSSES + 4):
		tracker.admitted({"type":str(i), "boss":true}, definition, 92)
	check(tracker.snapshot(run).bosses.size() == Context.MAX_BOSSES, "历史上限")
	var other := Context.new()
	rng.randomize()
	other.seeded(rng.seed)
	check(other.snapshot(run).seed == str(rng.seed) and other.snapshot(run).bosses.is_empty(), "随机开局种子与跨局隔离")
	if failures == 0:
		print("PERF_CONTEXT_OK")
	quit(int(failures != 0))
