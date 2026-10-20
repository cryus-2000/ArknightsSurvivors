extends Node
## 新契约「只填 json」试点（docs/108 §9.1，德克萨斯）：帧条不变，只在 json 写 sprites.skills / extra_sprites。
##   godot --headless --path game res://tests/texas_contract_test.tscn -- --regression --balance --seed=1 --op=texas
## 校验：数据契约零错误；S1 / S2 单条与原来相同；S3 起手播 skill → 持续期站立播 idle、移动播 run → 结束回普通状态；
## S2 永久技能由生命周期默认绑定（后台、permanent）。全部通过时打印 "TEXAS CONTRACT failures=0"。

const Ch = preload("res://scripts/characters/character.gd")
const C = preload("res://scripts/characters/operator_contract.gd")
const DT := 1.0 / 60.0

var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var d: Dictionary = Ch.load_def("texas")
	ok(Ch.validate_operator("texas", d) and C.errors(d).is_empty(), "德克萨斯 json 通过契约校验")
	var o = game.squad.get_op("texas")
	ok(o != null, "德克萨斯在编队里（--op=texas）")
	if o != null:
		test_s1(o)
		test_s3(o)
		test_s2(o)
	print("%d checks, %d failed" % [n, fails])
	print("TEXAS CONTRACT failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func kind(o) -> String:
	return str(o.anim_state().get("kind", ""))


## 推进 t 秒；vel ≠ 0 时每帧把目标往前挪（主控 follow 把 pos 设成目标，速度由位移算）
func step(o, t: float, vel := Vector2.ZERO) -> void:
	for i in int(round(t / DT)):
		o.follow(DT, o.pos + vel * DT)


func settle(o) -> void:
	o.s_t = [0.0, 0.0, 0.0]
	step(o, 1.0)


func test_s1(o) -> void:
	o.start_skill(Vector2.INF, 0)
	ok(o.sq_ph == 0 and o.act_anim == "skill", "S1 单条 anim = skill，不进序列")
	ok(absf(o.attack_t - 7.0 / 12.0) < 0.002 and absf(o.fire_t - 3.5 / 12.0) < 0.002, "S1 窗口 / 出手与原单条相同（7 帧 12fps，f3 中点）")
	settle(o)


func test_s3(o) -> void:
	o.start_skill(Vector2.INF, 2)
	ok(o.sq_ph == 1 and o.act_anim == "skill" and kind(o) == "skill", "S3 进序列起手段，播 skill")
	ok(absf(o.attack_t - 7.0 / 12.0) < 0.002 and absf(o.fire_t - 3.5 / 12.0) < 0.002, "S3 起手窗口与原单条相同")
	step(o, 0.7)
	ok(o.skill_active_left(2) > 0.0 and o.sq_ph == 2 and kind(o) == "idle", "S3 持续期站立：循环播 idle")
	step(o, 0.5, Vector2(240, 0))
	ok(o.sq_ph == 2 and kind(o) == "run", "S3 持续期移动：播 run")
	step(o, 0.5)
	o.s_t[2] = 0.0
	step(o, 0.1)
	ok(o.sq_ph == 0, "S3 结束：没写 end，序列直接退出")
	ok(kind(o) in ["idle", "run"], "S3 结束回普通待机 / 跑步")


func test_s2(o) -> void:
	o.start_skill(Vector2.INF, 1)
	step(o, 1.0)
	var st: Array = o.skill_effect_status(1)
	ok(o.perm_on[1] and not st.is_empty() and st[0].unit == "permanent" and st[0].background, "S2 永久：生命周期默认绑定为后台 permanent")
	ok(not o.skills_occupied(), "S2 永久不占用技能通道")
