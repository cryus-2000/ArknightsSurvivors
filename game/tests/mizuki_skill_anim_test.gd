extends Node
## 充满即发干员（attack.flow = free，水月）的多条技能帧条（docs/87 §3.5）局内单元测试：
##   godot --headless --path game res://tests/mizuki_skill_anim_test.tscn -- --regression --balance --seed=1 --op=mizuki --squad=skadi
## 把 game.tscn 当子节点跑起来，第 5 帧冻结主场景，直接按水月的充满即发入口（SegMizuki._h3_free_skill）发三个技能，按 1/60 秒推进 follow()：
## S2 skill_s2 [0, 1] 起手（纯画面：attack_t / fire_t 不动）→ 高速状态期间 skill_s2_loop 坐姿循环（伞击改播 attack 槽 skill_s2_attack：
## 按其 fire 帧对齐出手、播完回坐姿循环；attack_t / fire_t 不动）
## → 高速结束 skill_s2 f2 收势 → 待机；S1 / S3 单条（S3 播 sprites.skills.s3 指的 skill_s3 条）；循环期间放 S1 压过循环、播完接着循环。
## 全部通过时打印 "MIZUKI SKILL ANIM failures=0"。

const Ch = preload("res://scripts/characters/character.gd")
const SegMizuki = preload("res://scripts/characters/blocks/seg_mizuki.gd")
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
	var d: Dictionary = Ch.load_def("mizuki")
	ok(Ch.validate_operator("mizuki", d), "水月 JSON 通过校验（含 sprites.skills）")
	var o = game.squad.get_op("mizuki")
	ok(o != null, "水月在编队里（--op=mizuki）")
	if o != null:
		ok(bool(o.B.get("_free", false)), "水月是充满即发（attack.flow = free）")
		test_s1(o)
		test_s3(o)
		test_s2(o)
	print("%d checks, %d failed" % [n, fails])
	print("MIZUKI SKILL ANIM failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.002) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


func step(o, t: float) -> void:
	var k := int(round(t / DT))
	for i in k:
		o.follow(DT, o.pos)


func kind(o) -> String:
	return str(o.anim_state().get("kind", ""))


func frame(o) -> int:
	return int(o.anim_state().get("frame", -1))


## 充满即发：技力充满、走水月自己的入口（不经 start_skill）
func cast(o, i: int) -> void:
	o.sp[i] = o.sp_need(i)
	SegMizuki._h3_free_skill(o, i)


# ---------------------------------------------------------------- S1：单条 skill（纯画面）

func test_s1(o) -> void:
	o.attack_t = 0.0
	o.fire_t = -1.0
	cast(o, 0)
	ok(o.sq_ph == 0 and o.vis_anim == "skill" and kind(o) == "skill" and frame(o) == 0, "S1 单条：play_vis_anim skill f0")
	ok(o.attack_t <= 0.0 and o.fire_t < 0.0, "S1 纯画面：不占出手窗口")
	step(o, 0.4)
	ok(o.vis_anim == "" and kind(o) == "idle", "S1 播完回待机")


# ---------------------------------------------------------------- S3：单条，但播 sprites.skills.s3 指的 skill_s3 条

func test_s3(o) -> void:
	ok(o.skill_anim(2) == "skill_s3", "skill_anim(2) 读 sprites.skills.s3.anim = skill_s3")
	cast(o, 2)
	ok(o.sq_ph == 0 and o.vis_anim == "skill_s3" and kind(o) == "skill_s3" and frame(o) == 0, "S3 单条：播 skill_s3 f0")
	step(o, 0.4)
	ok(o.vis_anim == "" and kind(o) == "idle", "S3 播完回待机")
	o.s_t[2] = 0.0


# ---------------------------------------------------------------- S2：起手 → 高速期间坐姿循环 → 收势

func test_s2(o) -> void:
	o.attack_t = 0.0
	o.fire_t = -1.0
	cast(o, 1)
	ok(o.skill_active_left(1) > 0.0, "S2 高速状态已开始计时")
	ok(o.sq_ph == 1 and o.sq_i == 1 and o.vis_anim == "", "S2 进序列起手段（不是 play_vis_anim）")
	ok(o.attack_t <= 0.0 and o.fire_t < 0.0, "S2 纯画面：attack_t / fire_t 不动（同 seed 模拟不变）")
	ok(kind(o) == "skill_s2" and frame(o) == 0, "S2 起手画 skill_s2 f0")
	# 同帧起手的伞击（attack_t > 0）压不过起手段
	o.attack_t = o.attack_dur
	step(o, 0.15)
	ok(kind(o) == "skill_s2" and frame(o) == 1, "S2 0.15 s：起手 f1（伞击画面压不过起手段）")
	step(o, 0.15)
	ok(o.sq_ph == 2 and kind(o) == "skill_s2_loop", "S2 0.30 s：起手播完进坐姿循环")
	var seen := {}
	for i in 60:
		o.follow(DT, o.pos)
		seen[frame(o)] = true
	ok(kind(o) == "skill_s2_loop" and seen.size() >= 4, "S2 循环 1 秒：四帧轮换（%s）" % str(seen.keys()))
	# 循环期间伞击：attack 槽 → 画 skill_s2_attack（8 帧 6fps fire 3），按 fire 帧对齐出手（水月 attack 是字符串槽：出手时刻 = attack_dur / 2），播完回坐姿循环
	ok(o.skill_seq(1).get("attack", "") == "skill_s2_attack", "sprites.skills.s2.attack = skill_s2_attack")
	var vs: Dictionary = o.sprite_spec("skill_s2_attack")
	var vfps := float(vs.get("fps", 12.0))
	var off: float = (float(vs.get("fire", 0)) + 0.5) / vfps - o.attack_dur * 0.5   # 变体时间 = 普攻已播秒数 + off
	var vlen: float = float(vs.get("frames", 8)) / vfps
	o.attack_t = o.attack_dur
	o.follow(DT, o.pos)
	ok(kind(o) == "skill_s2_attack", "循环中伞击：画 attack 槽 skill_s2_attack（不是普通 attack）")
	near(o.attack_t, o.attack_dur - DT, "attack 槽只换画面：attack_t 照旧倒数")
	ok(o.fire_t < 0.0, "attack 槽只换画面：fire_t 不动")
	ok(frame(o) == int((DT + off) * vfps), "起手帧按 fire 对齐（第 1 帧 = f%d）" % int((DT + off) * vfps))
	# 出手时刻（attack_dur / 2）画的正是 fire 帧
	step(o, o.attack_dur * 0.5 - DT)
	ok(kind(o) == "skill_s2_attack" and frame(o) == int(vs.get("fire", 3)), "出手时刻画 fire 帧 f%d（实际 f%d）" % [int(vs.get("fire", 3)), frame(o)])
	# 普攻窗口结束后变体继续播到末帧，之后回循环
	step(o, o.attack_dur * 0.5 + DT)
	ok(o.attack_t <= 0.0 and kind(o) == "skill_s2_attack", "普攻窗口结束，变体继续播（不回循环）")
	var last := frame(o)
	var mono := true
	while o.sq_atk != "":
		o.follow(DT, o.pos)
		if o.sq_atk != "":
			mono = mono and frame(o) >= last
			last = frame(o)
	ok(mono and last == int(vs.get("frames", 8)) - 1, "变体单调播到末帧 f%d（实际 f%d）" % [int(vs.get("frames", 8)) - 1, last])
	ok(o.sq_ph == 2 and kind(o) == "skill_s2_loop", "伞击变体播完回坐姿循环")
	# 下一次伞击从头重新对齐；变体播到一半又伞击则重新对齐
	o.attack_t = o.attack_dur
	o.follow(DT, o.pos)
	ok(kind(o) == "skill_s2_attack" and frame(o) == int((DT + off) * vfps), "再次伞击：变体从头对齐")
	step(o, 0.3)
	var mid := frame(o)
	o.attack_t = o.attack_dur
	o.follow(DT, o.pos)
	ok(kind(o) == "skill_s2_attack" and frame(o) < mid, "变体播到一半再伞击：重新对齐（f%d → f%d）" % [mid, frame(o)])
	step(o, vlen)
	ok(o.sq_atk == "" and o.sq_ph == 2 and kind(o) == "skill_s2_loop", "播完回坐姿循环")
	# 循环期间放 S1：单条压过循环，播完接着循环
	cast(o, 0)
	ok(o.sq_ph == 2 and kind(o) == "skill", "循环中放 S1：画 skill，序列保留")
	step(o, 0.4)
	ok(o.vis_anim == "" and kind(o) == "skill_s2_loop", "S1 播完接着循环")
	# 跑步时仍画循环（坐姿）
	o.mv = 200.0
	o.follow(DT, o.pos)
	ok(kind(o) == "skill_s2_loop", "高速期间移动仍画坐姿循环")
	o.mv = 0.0
	# 高速结束 → 收势 f2 → 待机
	o.s_t[1] = 0.0
	o.follow(DT, o.pos)
	ok(o.sq_ph == 3 and kind(o) == "skill_s2" and frame(o) == 2, "高速结束：收势 skill_s2 f2")
	step(o, 0.15)
	ok(o.sq_ph == 0 and kind(o) == "idle", "收势播完回待机")
	ok(o.attack_t <= 0.0 and o.fire_t < 0.0, "整段序列没有碰出手窗口")
	# 没写 attack 槽的序列照旧：临时把 S2 的 attack 槽去掉，循环中伞击画普通 attack
	var sq2: Dictionary = o.def.sprites.skills.s2.duplicate()
	var no_atk: Dictionary = sq2.duplicate()
	no_atk.erase("attack")
	o.def.sprites.skills.s2 = no_atk
	cast(o, 1)
	step(o, 0.3)
	o.attack_t = o.attack_dur
	o.follow(DT, o.pos)
	ok(o.sq_ph == 2 and kind(o) == "attack", "没写 attack 槽：循环中伞击照旧画普通 attack")
	step(o, o.attack_dur)
	ok(o.sq_ph == 2 and kind(o) == "skill_s2_loop" and o.sq_atk == "", "普通 attack 播完接着循环")
	o.def.sprites.skills.s2 = sq2
	o.s_t[1] = 0.0
	step(o, 0.3)
