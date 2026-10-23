extends Node
## 移动攻击（docs/128 §3，character._move_swap）回归：每名有 sprites.move_attack 的干员——
##   ① 帧条随局内贴图集加载（game.gd / choice_panel.load_op_tex 的槽表含 move_attack；10-24 架构盘点发现漏登记，_move_swap 恒取到 null）
##   ② 出手动作期间移动（mv > RUN_ENTER）播的是 move_attack 贴图，帧序号与原地普攻相同（按出手帧对齐，玩法读数不变）
##   ③ 站定出手仍播原地 attack；动作结束后不残留
##   ④ 有移动攻击条时，出手后移动不再提前切跑步（收势不被截）
const Ch = preload("res://scripts/characters/character.gd")
const Op = preload("res://scripts/characters/data_operator.gd")
var g
var checks := 0
var failures := 0


func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var n := 0
	for cid in Ch.list_ids():
		var d: Dictionary = Ch.load_def(cid)
		var sp: Dictionary = d.get("sprites", {})
		if not sp.has("move_attack"):
			continue
		n += 1
		var mtn: String = sp.move_attack.tex
		ok(g.tex.get(mtn) != null, "%s move_attack 帧条已随贴图集加载（%s）" % [cid, mtn])
		var o = Op.new(g, d.duplicate(true))
		o.pos = g.ppos
		o.start_attack(o.pos + Vector2(80, 0))
		ok(o.anim_tex("move_attack") != null, "%s anim_tex(move_attack) 取得到" % cid)
		var hf: int = o.anim_hframes(o.anim_tex("attack"), "attack")
		ok(o.anim_hframes(o.anim_tex("move_attack"), "move_attack") == hf, "%s move_attack 帧数与普攻相同（%d）" % [cid, hf])
		# 动作窗口内逐段取样：移动 vs 站定，同一时刻帧序号相同、贴图不同
		var dur: float = o.attack_dur
		var hits := 0
		for k in 6:
			o.attack_t = dur * (1.0 - (k + 0.5) / 6.0)
			o.anim_kind = o.act_anim
			o.mv = 0.0
			var st0: Dictionary = o.anim_state()
			o.mv = Ch.RUN_ENTER + 60.0
			var st1: Dictionary = o.anim_state()
			if str(st1.get("kind", "")) != o.act_anim:
				continue   # 原生动作覆盖层接管的时段（数据干员的 native_motion 等）不在本测试范围
			hits += 1
			ok(st1.get("tex") == o.anim_tex("move_attack"), "%s 移动中出手播 move_attack（段 %d）" % [cid, k])
			ok(st0.get("tex") != o.anim_tex("move_attack"), "%s 站定出手仍播原地普攻（段 %d）" % [cid, k])
			ok(int(st1.get("frame", -1)) == int(st0.get("frame", -2)), "%s 移动 / 站定同一出手帧（段 %d：%s vs %s）" % [cid, k, st1.get("frame"), st0.get("frame")])
		ok(hits > 0, "%s 动作窗口内至少有一段由普攻帧条出画" % cid)
		# 出手后在移动：有移动攻击条时不提前让位给跑步
		o.attack_t = maxf(0.001, dur - o.attack_fire_at - 0.01)
		o.mv = Ch.RUN_ENTER + 60.0
		ok(not o.act_anim_yield(), "%s 出手后移动不截掉收势" % cid)
		# 动作结束：不残留
		o.attack_t = 0.0
		ok(o.anim_state().get("tex") != o.anim_tex("move_attack"), "%s 动作结束后不再播 move_attack" % cid)
	ok(n >= 19, "有 move_attack 槽的干员 %d 名（≥ 19）" % n)
	print("MOVE ATTACK %d checks, %d failed (%d operators)" % [checks, failures, n])
	get_tree().quit(0 if failures == 0 else 1)
