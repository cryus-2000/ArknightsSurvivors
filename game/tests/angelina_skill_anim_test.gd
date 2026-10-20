extends Node
## docs/105：统一序列的移动、倒放、影子与原施法时序。
const Ch = preload("res://scripts/characters/character.gd")
const DT := 1.0 / 60.0
var game: Node
var frames := 0
var n := 0
var fails := 0

func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)

func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var o = game.squad.get_op("angelina")
	ok(o != null, "安洁莉娜在编队里")
	if o != null:
		test_migration(o)
		test_sequence(o)
		test_validation()
	print("%d checks, %d failed" % [n, fails])
	print("ANGELINA SKILL ANIM failures=%d" % fails)
	get_tree().quit(1 if fails else 0)

func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)

func step(o, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		o.follow(DT, o.pos)

func kind(o) -> String:
	return str(o.anim_state().get("kind", ""))

func frame(o) -> int:
	return int(o.anim_state().get("frame", -1))

func test_sequence(o) -> void:
	# 独立于迁移 JSON，验证统一契约的各个画面阶段。
	o.def = o.def.duplicate(true)
	o.def.sprites.erase("skill_pose")
	o.def.sprites["skills"] = {"s3": {"start": "float_in", "loop": "float", "run": "float_move", "attack": "float_attack", "end": {"anim": "float_in", "reverse": true}, "shadow": 0.7, "shadow_a": 0.55}}
	ok(Ch.validate_operator("angelina", o.def), "统一契约通过校验")
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.s_t[2] = 10.0
	var rng = game.rng_states()
	o.play_vis_skill(2)
	ok(kind(o) == "float_in" and frame(o) == 0, "起飞从 f0 开始")
	step(o, 0.1)
	ok(kind(o) == "float_in" and frame(o) == 2, "起飞按逐帧时长前进")
	ok(o.shadow_k().x < 1.0 and o.shadow_k().x > 0.7, "起飞影子渐变")
	step(o, 0.3)
	ok(kind(o) == "float", "起飞结束进入浮空待机")
	ok(o.shadow_k().is_equal_approx(Vector2(0.7, 0.55)), "持续期影子系数")
	var seen := {}
	for i in 60:
		o.follow(DT, o.pos)
		seen[frame(o)] = true
	ok(seen.size() >= 7, "浮空待机八帧循环（末帧 16 ms 可能落在两次刷新之间）")
	o.mv = 200.0
	o.follow(DT, o.pos)
	ok(kind(o) == "float_move", "移动使用 run 槽")
	o.mv = 0.0
	o.follow(DT, o.pos)
	ok(kind(o) == "float", "停止回 loop")
	o.start_attack(Vector2.INF)
	ok(is_equal_approx(o.attack_t, 5.0 / 12.0) and is_equal_approx(o.fire_t, 2.5 / 12.0), "普攻仍用原出手窗口")
	o.fire_t = -1.0 # 本测试只推进画面，避免实际发弹消耗 RNG。
	o.follow(DT, o.pos)
	ok(kind(o) == "float_attack", "持续期普攻使用变体")
	step(o, 0.5)
	ok(kind(o) == "float", "普攻播完回循环")
	o.s_t[2] = 0.0
	o.follow(DT, o.pos)
	ok(kind(o) == "float_in" and frame(o) == 7, "收势倒放从 f7 开始")
	step(o, 0.1)
	ok(kind(o) == "float_in" and frame(o) == 5, "收势倒放到 f5")
	step(o, 0.5)
	ok(kind(o) == "idle" and o.shadow_k() == Vector2.ONE, "收势结束恢复待机与影子")
	ok(game.rng_states() == rng, "动画不消耗玩法 RNG")
	# 子段倒放不得改变定义里的帧数组。
	var seg := {"anim": "float_in", "frames": [0, 2, 3], "reverse": true}
	ok(o._seq_frames(seg, "float_in") == [3, 2, 0] and seg.frames == [0, 2, 3], "子段倒放且不修改 JSON")

func test_migration(o) -> void:
	ok(not o.def.sprites.has("skill_pose"), "旧 skill_pose 已移除")
	ok(o.skill_seq(2).get("enter", "") == "float_in", "施法后的纯画面 enter")
	o.start_skill(Vector2.INF, 2)
	ok(is_equal_approx(o.attack_t, 7.0 / 12.0), "S3 保留原施法窗口")
	ok(is_equal_approx(o.fire_t, 3.5 / 12.0), "S3 保留原 fire 中点")
	step(o, 0.6)
	ok(kind(o) == "float_in" and frame(o) == 0, "原施法完成才起飞")
	ok(o.attack_t <= 0.0 and o.fire_t < 0.0, "起飞不占逻辑窗口")
	o.start_attack(Vector2.INF)
	o.fire_t = -1.0
	step(o, 0.2)
	ok(o.sq_ph == 4 and kind(o) == "attack", "进入段被普攻遮住时保留序列")
	step(o, 0.6)
	ok(kind(o) == "float", "普攻后继续起飞并进入循环")
	o.start_skill(Vector2.INF, 0)
	step(o, 0.7)
	ok(o.sq_ph == 2 and kind(o) == "float", "循环期间其他技能结束后恢复浮空")
	o.s_t[2] = 0.0
	step(o, 0.7)

func test_validation() -> void:
	var bads := {
		"旧契约": func(x): x.sprites.skill_pose = {},
		"非法键": func(x): x.sprites.skills.s4 = {"anim": "skill"},
		"run 缺图槽": func(x): x.sprites.skills.s3.run = "missing",
		"enter 未加载": func(x): x.extra_sprites.erase("float_in"),
		"子段越界": func(x): x.sprites.skills.s3.end.frames = [8],
		"子段非整数": func(x): x.sprites.skills.s3.end.frames = [0.5],
		"reverse 类型": func(x): x.sprites.skills.s3.end.reverse = "yes",
		"run 无 loop": func(x): x.sprites.skills.s3.erase("loop"),
		"shadow 类型": func(x): x.sprites.skills.s3.shadow = "small",
		"单条混循环": func(x): x.sprites.skills.s3 = {"anim": "skill", "loop": "float", "end": "float_in"},
		"起手无循环": func(x): x.sprites.skills.s3 = {"start": "skill", "end": "float_in"},
		"单条混起手": func(x): x.sprites.skills.s3 = {"anim": "skill", "start": "skill", "loop": "float"},
	}
	for label in bads:
		var d: Dictionary = Ch.load_def("angelina").duplicate(true)
		bads[label].call(d)
		ok(not Ch.validate_operator("angelina", d), "拒绝非法契约：" + label)
