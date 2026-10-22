extends Node
## 凯尔希本体 / 流明 / 艾丽妮换 64 画布新条（10-20）：出手时刻与旧 48 条逐位相同（docs/108 §9）。
##   godot --headless --path game res://tests/klc_contract_test.tscn -- --regression --balance --seed=1 --op=irene
## 校验：三人 json 契约零错误；每个动作槽的逻辑总时长 / 出手时刻 = 旧条 frames / fps、(fire + 0.5) / fps；
## 出手帧起点 = 出手时刻（画面与伤害对齐）；艾丽妮段间隔仍 2 / 12；艾丽妮选「再审」时普攻换播三段刺、收尾斩不被覆盖；
## 流明光柱一发起手播 attack_beam。全部通过时打印 "KLC CONTRACT failures=0"。

const Ch = preload("res://scripts/characters/character.gd")
const C = preload("res://scripts/characters/operator_contract.gd")
const NM = preload("res://scripts/characters/native_motion.gd")

## [干员, 槽, 旧帧数, 旧 fps, 旧出手帧]
const OLD := [
	["kaltsit", "attack", 4, 14.0, 2], ["kaltsit", "skill", 6, 12.0, 3], ["kaltsit", "command", 6, 12.0, 2],
	["lumen", "attack", 4, 12.0, 2], ["lumen", "attack_beam", 4, 12.0, 2], ["lumen", "skill", 6, 12.0, 3], ["lumen", "skill_s2", 6, 12.0, 3],
	["lumen", "skill_s3_start", 6, 12.0, 3],
	["irene", "attack", 5, 12.0, 1], ["irene", "skill", 7, 12.0, 3], ["irene", "skill_s2", 7, 12.0, 3], ["irene", "skill_s3_start", 7, 12.0, 3],
]

var game: Node
var frames := 0
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
	for id in ["kaltsit", "lumen", "irene"]:
		var d: Dictionary = Ch.load_def(id)
		ok(Ch.validate_operator(id, d) and C.errors(d).is_empty(), "%s json 通过契约校验 %s" % [id, str(C.errors(d))])
	var o = game.squad.get_op("irene")
	for r in OLD:
		var op = o if r[0] == "irene" else _make(r[0])
		if op == null:
			ok(false, "建不出 %s" % r[0])
			continue
		var spec: Dictionary = op.sprite_spec(r[1])
		var old_dur := float(r[2]) / float(r[3])
		var old_fire := (float(r[4]) + 0.5) / float(r[3])
		var lw: Array = Ch.logic_window(spec) if spec.has("logic") else [-1.0, -1.0]
		ok(lw[0] == old_dur and lw[1] == old_fire, "%s.%s 逻辑窗口 %.17f / %.17f = 旧 %.17f / %.17f" % [r[0], r[1], lw[0], lw[1], old_dur, old_fire])
		if not r[1].begins_with("skill_s3"):   # 走 _start_action 的槽：实跑一次，读运行时的窗口与出手时刻
			op._start_action("skill" if r[1].begins_with("skill") else "attack", Vector2.INF, 0.5, 0.25, r[1])
			var expected_dur: float = float(spec.attack_timing.duration) if spec.has("attack_timing") else old_dur
			ok(absf(op.attack_dur-expected_dur)<1e-9 and absf(op.attack_fire_at-old_fire)<1e-9, "%s.%s 使用确认的收势并保留原出手时刻" % [r[0], r[1]])
			op.attack_t = 0.0
			op.fire_t = -1.0
		var k := int(spec.fire)   # 画面：出手帧起点 = 出手时刻（1e-9 内，json 小数解析误差）
		ok(absf(op.frames_seconds(r[1], range(k)) - old_fire) < 1e-9, "%s.%s 出手帧 %d 起点对准出手时刻" % [r[0], r[1], k])
	# 艾丽妮段间隔（_h3_stage_gap）不变：(second − fire) / fps = 2 / 12
	var a: Dictionary = o.sprite_spec("attack")
	ok((float(a.second) - float(a.fire)) / float(a.fps) == (3.0 - 1.0) / 12.0, "艾丽妮段间隔 2 / 12")
	# 第二段命中时刻 = 刺出帧 4 起点（画面）
	ok(absf(o.frames_seconds("attack", range(4)) - (1.5 / 12.0 + 2.0 / 12.0)) < 1e-9, "艾丽妮第二刺帧对准第二段命中")
	# 再审：普攻起手换播三段刺；收尾斩在播时不被覆盖
	o.taken = o.taken + ["retrial"] if o.get("taken") is Array else ["retrial"]
	o.start_attack(o.pos + Vector2(60, 0))
	ok(str(o.native_motion.get("clip", "")) == "attack_retrial", "再审：普攻起手播 attack_retrial（%s）" % str(o.native_motion.get("clip", "")))
	var st: Dictionary = NM.state(o, {"kind": "finisher", "frame": 1, "tex": null})
	ok(str(st.kind) == "finisher", "收尾斩在 yield 里不被三段刺覆盖")
	# 艾丽妮 S3（sprites.skills.s3.lock）：持续期间普攻 / 收尾斩不换画面，只播空中连射
	o.attack_t = 0.0
	o.native_motion.clip = ""
	o.hw.ir.erase("fin_t")
	o.start_skill(o.pos + Vector2(60, 0), 2)
	ok(o.sq_ph != 0 and o.seq_locked(), "艾丽妮 S3 起手进锁定序列（sq_ph %d）" % o.sq_ph)
	o.attack_t = 0.0
	o.sq_ph = 2
	o.sq_t = 0.3
	o.start_attack(o.pos + Vector2(60, 0))
	ok(o.sq_ph == 2, "S3 持续中普攻起手不打断序列")
	ok(str(o.anim_state().kind) == "skill_s3_loop", "S3 持续中普攻仍播空中连射（%s）" % str(o.anim_state().kind))
	o.hw.ir["fin_t"] = 0.0
	o.hw.ir["fin_anim"] = "finisher"
	ok(str(o.anim_state().kind) == "skill_s3_loop", "S3 持续中收尾斩不换画面（%s）" % str(o.anim_state().kind))
	o._sq_clear()
	o.hw.ir.erase("fin_t")
	o.attack_t = 0.0
	# 流明：光柱充满后起手播 attack_beam
	var lm = _make("lumen")
	if lm != null:
		var SegLumen = load("res://scripts/characters/blocks/seg_lumen.gd")
		lm.elite = 2
		lm.hw.lm.empowered = 3
		ok(SegLumen._h3_lantern_anim(lm, lm.hw.lm, [{}]) == "attack_beam", "流明光柱起手播 attack_beam")
		lm.hw.lm.empowered = 0
		ok(SegLumen._h3_lantern_anim(lm, lm.hw.lm, [{}]) == "", "流明普通光弹播 attack")
	print("KLC CONTRACT failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _make(id: String):
	var o = game.squad.get_op(id)
	if o != null:
		return o
	if game.squad.is_full():
		return null
	game.squad.add(id, false)
	return game.squad.get_op(id)


func ok(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: " + msg)
