extends Node
## 多条技能帧条 + 循环状态（docs/87 §3.5，首例铃兰）的局内单元测试：
##   godot --headless --path game res://tests/suzuran_skill_anim_test.tscn -- --regression --balance --seed=1 --op=suzuran --squad=lumen
## 把 game.tscn 当子节点跑起来，第 5 帧冻结主场景，直接起手三个技能并按 1/60 秒推进 follow()：
## S1 单条 skill（出手 / 窗口与原来相同）；S2 attack f0 起手 → s2_hold 定格 250 ms → 待机（出手 = 定格开始）；
## S3 s3 [0, 1] 起手（fire f1）→ 迷雾期间 s3_loop 循环 → 迷雾结束 s3 [0, 2] 收势 → 待机；循环期间普攻压过、播完接着循环；
## 校验的正反例；没写 sprites.skills 的干员（队友）不受影响。全部通过时打印 "SUZURAN SKILL ANIM failures=0"。

const Ch = preload("res://scripts/characters/character.gd")
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
	test_validate()
	var o = game.squad.get_op("suzuran")
	ok(o != null, "铃兰在编队里（--op=suzuran）")
	if o != null:
		test_s1(o)
		test_s2(o)
		test_s3(o)
		test_sequence_overlap(o)
		test_mate()
	print("%d checks, %d failed" % [n, fails])
	print("SUZURAN SKILL ANIM failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.002) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


## 推进 t 秒（主控：follow 把 pos 设成 target）
func step(o, t: float) -> void:
	var k := int(round(t / DT))
	for i in k:
		o.follow(DT, o.pos)


func kind(o) -> String:
	return str(o.anim_state().get("kind", ""))


func frame(o) -> int:
	return int(o.anim_state().get("frame", -1))


# ---------------------------------------------------------------- 校验

func test_validate() -> void:
	var d: Dictionary = Ch.load_def("suzuran")
	ok(Ch.validate_operator("suzuran", d), "铃兰 JSON 通过校验（含 sprites.skills）")
	ok(d.sprites.skills.s3.start.anim == "skill_s3" and d.extra_sprites.has("skill_s3_loop"), "铃兰 sprites.skills 与 extra_sprites 齐全")
	var bads := {
		"hold 没 intro": func(x): x.sprites.skills.s2.erase("intro"),
		"hold 与 start 同写": func(x): x.sprites.skills.s2["start"] = "skill_s3",
		"键不是 s1–s3": func(x): x.sprites.skills["s4"] = {"anim": "skill"},
		"帧条不在 sprites": func(x): x.sprites.skills.s3.loop = "skill_nope",
		"帧条没列进 extra_sprites": func(x): x.extra_sprites = ["skill_s2_hold", "skill_s3"],
		"frames 越界": func(x): x.sprites.skills.s3.end["frames"] = [0, 8],
		"三种写法都没有": func(x): x.sprites.skills.s1 = {"fps": 8},
	}
	for name in bads:
		var x: Dictionary = Ch.load_def("suzuran")
		bads[name].call(x)
		ok(not Ch.validate_operator("suzuran", x), "反例应不通过：" + name)


# ---------------------------------------------------------------- S1：单条，与原来相同

func test_s1(o) -> void:
	o.start_skill(Vector2.INF, 0)
	ok(o.sq_ph == 0 and o.act_anim == "skill", "S1 走单条 skill，不进序列")
	near(o.attack_t, 0.375, "S1 窗口 = 3 帧 / 8fps")
	near(o.fire_t, 0.1875, "S1 出手 = f1 中点")
	ok(kind(o) == "skill" and frame(o) == 0, "S1 起手画 skill f0")
	step(o, 0.4)
	ok(o.attack_t <= 0.0 and kind(o) == "idle", "S1 播完回待机")


# ---------------------------------------------------------------- S2：起手一帧 → 定格 → 待机

func test_s2(o) -> void:
	o.perm_on[1] = false
	o.start_skill(Vector2.INF, 1)
	ok(o.sq_ph == 1 and o.sq_own and o.act_kind == "skill", "S2 进序列起手段")
	near(o.attack_t, 1.0 / 14.0 + 0.25, "S2 窗口 = attack 一帧 + 250 ms")
	near(o.fire_t, 1.0 / 14.0, "S2 出手 = 定格开始")
	ok(kind(o) == "skill_s2_intro" and frame(o) == 0, "S2 起手画专用起手条 f0")
	step(o, 0.05)
	ok(kind(o) == "skill_s2_intro" and frame(o) > 0 and not o.perm_on[1], "S2 0.05 s：仍是 attack f0，还没出手")
	step(o, 0.05)
	ok(o.sq_ph == 2 and kind(o) == "skill_s2_hold" and frame(o) == 0, "S2 0.10 s：定格 s2_hold")
	ok(o.perm_on[1], "S2 已出手（永久生效）")
	step(o, 0.2)
	ok(kind(o) == "skill_s2_hold", "S2 0.30 s：仍定格")
	step(o, 0.05)
	ok(o.sq_ph == 0 and o.attack_t <= 0.0 and kind(o) == "idle", "S2 0.35 s：定格结束回待机，窗口同时结束")


# ---------------------------------------------------------------- S3：起手 → 循环（迷雾期间）→ 收势

func test_s3(o) -> void:
	o.start_skill(Vector2.INF, 2)
	ok(o.sq_ph == 1 and o.act_anim == "skill_s3", "S3 进序列起手段")
	near(o.attack_t, 0.25, "S3 窗口 = 起手两帧 / 8fps")
	near(o.fire_t, 0.1875, "S3 出手 = f1 中点（与原单条相同）")
	ok(kind(o) == "skill_s3" and frame(o) == 0, "S3 起手画 s3 f0")
	step(o, 0.15)
	ok(kind(o) == "skill_s3" and frame(o) == 4, "S3 0.15 s：发力帧 f1")
	ok(o.skill_active_left(2) <= 0.0, "S3 0.15 s：还没出手（迷雾未起）")
	step(o, 0.05)
	ok(o.skill_active_left(2) > 0.0, "S3 0.20 s：已出手，迷雾计时在走")
	step(o, 0.1)
	ok(o.sq_ph == 2 and kind(o) == "skill_s3_loop" and o.attack_t <= 0.0, "S3 0.30 s：窗口结束，进入循环（不再 acting）")
	var seen := {}
	for i in 60:
		o.follow(DT, o.pos)
		seen[frame(o)] = true
	ok(kind(o) == "skill_s3_loop" and seen.has(0) and seen.has(1), "S3 循环 1 秒：两帧轮换")
	# 循环期间起手的别的动作压过循环，播完接着循环
	o.start_attack(Vector2.INF)
	ok(o.sq_ph == 2 and not o.sq_own and kind(o) == "attack", "S3 循环中普攻：画 attack，序列保留")
	step(o, 0.8)
	ok(o.attack_t <= 0.0 and kind(o) == "skill_s3_loop", "普攻播完接着循环")
	# 迷雾结束 → 收势 [0, 2] → 待机
	o.hw.sz.haze_t = 0.0
	o.follow(DT, o.pos)
	ok(o.sq_ph == 3 and kind(o) == "skill_s3_end" and frame(o) == 0, "迷雾结束：收势先回 f0")
	step(o, 0.15)
	ok(kind(o) == "skill_s3_end" and frame(o) == 4, "收势 0.15 s：f2")
	step(o, 0.15)
	ok(o.sq_ph == 0 and kind(o) == "idle", "收势播完回待机")
	# 起手途中被别的动作打断：序列作废
	o.start_skill(Vector2.INF, 2)
	step(o, 0.05)
	o.start_attack(Vector2.INF)
	ok(o.sq_ph == 0 and kind(o) == "attack", "起手途中普攻：序列作废，画 attack")
	step(o, 0.4)
	o.hw.sz.haze_t = 0.0


# ---------------------------------------------------------------- 没写 sprites.skills 的干员不受影响

func test_mate() -> void:
	var m = null
	for x in game.squad.ops:
		if x.id != "suzuran":
			m = x
			break
	ok(m != null, "有队友")
	if m == null:
		return
	ok(m.skill_seq(0).is_empty() and m.skill_seq(2).is_empty(), "队友 %s 没有 sprites.skills" % m.id)
	m.start_skill(Vector2.INF, 0)
	ok(m.sq_ph == 0 and m.act_kind == "skill", "队友技能照旧走单条")
	step(m, 1.0)
	ok(m.sq_ph == 0, "队友始终不进序列")


func test_sequence_overlap(o) -> void:
	for expires in [false, true]:
		o.start_skill(Vector2.INF, 2)
		step(o, 0.3)
		ok(o.sq_ph == 2, "重叠测试从 S3 循环开始")
		o.start_skill(Vector2.INF, 1)
		near(o.attack_t, 1.0 / 14.0 + 0.25, "重叠不改变 S2 出手窗口")
		near(o.fire_t, 1.0 / 14.0, "重叠不改变 S2 出手时刻")
		if expires:
			o.hw.sz.haze_t = 0.0
		step(o, 0.35)
		if expires:
			ok(o.sq_ph == 3 and kind(o) == "skill_s3", "被遮住时结束的 S3 只恢复收势")
		else:
			ok(o.sq_ph == 2 and kind(o) == "skill_s3_loop", "S2 序列结束恢复仍生效的 S3 循环")
			o.hw.sz.haze_t = 0.0
		step(o, 0.5)
		ok(o.sq_ph == 0 and kind(o) == "idle", "重叠序列最终回到待机")
