extends Node
## 浊心斯卡蒂 / 归溟幽灵鲨新美术（10-20）：逻辑出手窗口不变、画面出手帧起点 = 伤害时刻（native_motion.clips）、
## 归溟 S3 重锯 / 反向第二圈换条、替身闪现现身 / 消散槽，全部纯画面、不消耗玩法 RNG。
const Ch = preload("res://scripts/characters/character.gd")
const NativeMotion = preload("res://scripts/characters/native_motion.gd")
const SegSpecter = preload("res://scripts/characters/blocks/seg_specter.gd")
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
	var sp = game.squad.get_op("specter_unchained")
	var sk = game.squad.get_op("skalter")
	ok(sp != null and sk != null, "两人都在编队里")
	if sp != null and sk != null:
		var rng = game.rng_states()
		ok(Ch.validate_operator("specter_unchained", sp.def), "归溟 json 通过契约校验")
		ok(Ch.validate_operator("skalter", sk.def), "浊心 json 通过契约校验")
		test_specter(sp)
		test_skalter(sk)
		test_puppet(sp)
		ok(game.rng_states() == rng, "动画不消耗玩法 RNG")
	print("%d checks, %d failed" % [n, fails])
	print("SKALTER SPECTER ANIM failures=%d" % fails)
	get_tree().quit(1 if fails else 0)

func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)

func step(o, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		o.follow(DT, o.pos)
		NativeMotion.tick(o, DT)   # 原生动作时钟在 data_operator.update 里推进，这里只推画面

func st(o) -> Dictionary:
	return o.anim_state()

func test_specter(o) -> void:
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.s_t[2] = 0.0
	o.cd = 1.2
	o.start_attack(Vector2.INF)
	ok(is_equal_approx(o.attack_t, 2.5 / 12.0 + 0.7) and is_equal_approx(o.fire_t, 2.5 / 12.0), "环斩保留出手时刻，逻辑包含已确认的 0.7 秒收势")
	o.fire_t = -1.0   # 只推进画面，不实际出手
	var fire_frame := int(o.sprite_spec("attack").fire)
	step(o, 0.18)
	ok(st(o).kind == "attack" and int(st(o).frame) < fire_frame, "伤害时刻前还在前摇帧")
	step(o, 0.05)
	ok(st(o).kind == "attack" and int(st(o).frame) == fire_frame, "伤害时刻（0.21 秒）画面正好到出手帧 %d" % fire_frame)
	step(o, 0.4)
	ok(o.attack_t > 0.0 and st(o).kind == "attack", "收势画面与逻辑窗口保持一致")
	step(o, 0.3)
	ok(st(o).kind == "idle", "整条播完回待机")
	# 反向第二圈：出手段镜像重播
	o.hw.sp["spin2_vis"] = 0.0
	var s2 := st(o)
	ok(s2.kind == "attack" and int(s2.frame) == fire_frame and bool(s2.flip) == (o.face >= 0.0), "反向第二圈从出手帧起镜像")
	o.hw.sp["spin2_vis"] = 0.5
	ok(st(o).kind == "idle", "反向圈播完让回")
	o.hw.sp.erase("spin2_vis")
	# S3：待机 / 普攻换原作重锯条，帧号同普攻
	o.s_t[2] = 5.0
	ok(st(o).kind == "idle_s3", "S3 期间待机换举锯待机")
	o.cd = 1.2
	o.start_attack(Vector2.INF)
	o.fire_t = -1.0
	step(o, 0.23)
	ok(st(o).kind == "attack_s3" and int(st(o).frame) == fire_frame, "S3 普攻换重锯条且出手帧同步")
	step(o, 0.7)
	o.s_t[2] = 0.0
	ok(st(o).kind == "idle", "S3 结束回普通待机")
	ok(o.anim_tex("doll_appear") != null and o.anim_tex("doll_vanish") != null and o.anim_tex("doll_spin") != null, "替身现身 / 连斩 / 消散帧条已加载")

func test_skalter(o) -> void:
	ok(o.skill_anim(0) == "skill" and o.skill_anim(1) == "skill_s2" and o.skill_anim(2) == "skill_s3", "浊心三技能各用原作起手条")
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.start_skill(Vector2.INF, 1)
	ok(is_equal_approx(o.attack_t, 7.0 / 12.0) and is_equal_approx(o.fire_t, 3.5 / 12.0), "技能仍用原施法窗口 7/12、出手 3.5/12")
	o.fire_t = -1.0
	var ff := int(o.sprite_spec("skill_s2").fire)
	step(o, 0.30)
	ok(st(o).kind == "skill_s2" and int(st(o).frame) == ff, "技能生效时刻画面在关键姿势帧 %d" % ff)
	step(o, 1.0)
	ok(st(o).kind == "idle", "技能画面播完回待机")
	ok(int(o.sprite_spec("idle").frames) == 36, "待机 36 帧加密")


## 二技能「操作替身」（10-29 用户）：她当队长时替身就站在玩家位置（镜头 / 受击 / 索敌都在 g.ppos），本体不画；
## 当队友时替身照旧跟在队长身侧；到期后本体回到替身所在处
func test_puppet(o) -> void:
	var sp: Dictionary = o.hw.sp
	var sub: Dictionary = {}
	for b in o.B.get("skills", [])[1].get("do", []):
		if str(b.get("_tag", "")) == "verb.substitute":
			sub = b
	ok(not sub.is_empty(), "二技能带替身积木")
	if sub.is_empty():
		return
	var was_leader: bool = o.is_leader
	o.is_leader = true
	game.ppos = Vector2(900, 700)
	sp.sub = sub
	SegSpecter._h3_fall(o, sp)
	ok(o.away() and sp.doll_pos == game.ppos, "队长：替身现身在玩家位置，本体离场")
	game.ppos = Vector2(1000, 640)
	SegSpecter._h3_doll_tick(o, sp, DT)
	ok(sp.doll_pos == game.ppos, "队长：移动的是替身（替身位置 = 玩家位置）")
	o.is_leader = false
	SegSpecter._h3_doll_tick(o, sp, DT)
	ok(sp.doll_pos != game.ppos, "队友：替身照旧跟在队长身侧，不站到队长身上")
	o.is_leader = true
	sp.doll_t = DT * 0.5
	SegSpecter._h3_doll_tick(o, sp, DT)
	ok(not o.away() and o.pos == game.ppos, "替身到期：操控回到本体，本体就在玩家位置")
	o.is_leader = was_leader
