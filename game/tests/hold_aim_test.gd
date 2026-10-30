extends Node
## 10-31 按住瞄准全员验收（取代 10-24 手动普攻全员验收；用户定：普攻永远自动，按住瞄准只覆盖方向 / 目标）：
## 当前 --op 干员当队长，队长右边近处一只木桩 R、左边稍远一只木桩 L（自动索敌会先打 R），逐场景断言：
##   A 不按（自动）：R 掉血——和取消手动普攻前的自动模式一样
##   B 模拟按住瞄准朝左（doctor.sim_atk / sim_dir）：L 掉血；有方向的普攻（A 类 atk_aim）这一击朝左
##   C 空场按住瞄准朝右：照常出招（不要求有目标）
##   D 触屏瞄准键拖向左（touch_atk / touch_atk_dir）：L 掉血
##   E 松手：瞄准状态立即消失（aim_held 为假），再打又回到 R
## 凯尔希（普攻是命令 Mon3tr，support 形状）不断言出招事件，只看木桩掉血（B / D 是 Mon3tr 扑向左边那只）。
## 用法：godot --headless --path game res://tests/hold_aim_test.tscn -- --regression --balance --seed=1 --op=<id>
## 全部通过时打印 "HOLD AIM <id> failures=0"。

const DT := 1.0 / 60.0
var g
var o
var n := 0
var fails := 0
var id := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--op="): id = arg.get_slice("=", 1)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	o = g.squad.get_op(id)
	assert(o != null)
	g.doctor._ma_init = true
	g.doctor.aim_on = true   # 触屏场景走真实的 aim_held 判定（机器人 / 自动测试缺省不响应）
	var is_support: bool = str(o.def.blocks.attack.get("shape", "")) == "support"
	var r: Dictionary = await run_case(true, Vector2.ZERO, false, 150)
	ok(r.dmg_r > 0.0, "%s A 不按（自动）：右边近处木桩掉血（右 %.0f / 左 %.0f）" % [id, r.dmg_r, r.dmg_l])
	var one_side: bool = r.dmg_l <= 0.0   # 自动时只打右边的（不是两边都挨的范围普攻）：按住朝左就该主要打左边
	r = await run_case(true, Vector2.LEFT, false, 150)
	ok(r.dmg_l > 0.0, "%s B 按住瞄准朝左：左边木桩掉血（左 %.0f / 右 %.0f）" % [id, r.dmg_l, r.dmg_r])
	if one_side:
		ok(r.dmg_l > r.dmg_r, "%s B 按住瞄准朝左：左边挨得比右边多（左 %.0f / 右 %.0f）" % [id, r.dmg_l, r.dmg_r])
	if r.aim != Vector2.ZERO:
		ok(r.aim.dot(Vector2.LEFT) > 0.99, "%s B 按住瞄准朝左：这一击的方向朝左（%s）" % [id, r.aim])
	r = await run_case(false, Vector2.RIGHT, false, 90)
	if not is_support:
		ok(r.events >= 1, "%s C 空场按住瞄准：照常出招（%d 次）" % [id, r.events])
	r = await run_case(true, Vector2.LEFT, true, 150)
	ok(r.dmg_l > 0.0, "%s D 触屏瞄准键拖向左：左边木桩掉血（右 %.0f / 左 %.0f）" % [id, r.dmg_l, r.dmg_r])
	g.doctor.sim_atk = false
	ok(not g.doctor.aim_held() and not o.held_aim(), "%s E 松手后不再按住瞄准" % id)
	r = await run_case(true, Vector2.ZERO, false, 150)
	ok(r.dmg_r > 0.0, "%s E 松手后回到自动：右边木桩掉血（%.0f）" % [id, r.dmg_r])
	print("%d checks, %d failed" % [n, fails])
	print("HOLD AIM %s failures=%d" % [id, fails])
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


## 跑一个场景 steps 步：enemy = 放左右两只不动的木桩；aim = 按住瞄准的方向（ZERO = 不按）；touch = 走触屏瞄准键
func run_case(enemy: bool, aim: Vector2, touch: bool, steps: int) -> Dictionary:
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	o.s_t = [0.0, 0.0, 0.0]
	o.no_attack = false
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.cd = 0.0
	o.pending.clear()
	o.atk_aim = Vector2.ZERO
	if o.tx.has("dash"):
		o.tx.erase("dash")
	g.facing = 1.0
	g.move_in = Vector2.ZERO
	g.doctor._atk_prev = false
	g.touch.active = touch
	g.doctor.sim_atk = aim != Vector2.ZERO and not touch
	g.doctor.sim_dir = aim
	g.doctor.touch_atk = touch and aim != Vector2.ZERO
	g.doctor.touch_atk_dir = aim * 60.0 if touch else Vector2.ZERO
	var reach := 150.0 if str(o.def.get("class", "")) in ["狙击", "术师", "辅助", "医疗"] else 70.0
	var at_r: Vector2 = g.ppos + Vector2(reach * 0.6, 0)
	var at_l: Vector2 = g.ppos + Vector2(-reach * 0.9, 0)
	var dm_r: Dictionary = {}
	var dm_l: Dictionary = {}
	if enemy:
		dm_r = _dummy(at_r)
		dm_l = _dummy(at_l)
		g.enemies_sys.build_grid()
	var hp_r: float = float(dm_r.get("hp", 0.0))
	var hp_l: float = float(dm_l.get("hp", 0.0))
	var events := 0
	var last_n: int = o.atk_n + int(o.get("far_n"))
	var seen_aim := Vector2.ZERO
	for k in steps:
		o.sp = [-100000.0, -100000.0, -100000.0]   # 不放技能，只看普攻
		if enemy:
			for pair in [[dm_r, at_r], [dm_l, at_l]]:
				pair[0].pos = pair[1]
				pair[0].kb = Vector2.ZERO
				pair[0].hp = maxf(pair[0].hp, 1.0)
			g.enemies_sys.build_grid()
		g._update(DT)
		if o.atk_aim != Vector2.ZERO:
			seen_aim = o.atk_aim
		var now_n: int = o.atk_n + int(o.get("far_n"))
		events += now_n - last_n
		last_n = now_n
		await get_tree().process_frame
	g.doctor.sim_atk = false
	g.doctor.touch_atk = false
	g.doctor.touch_atk_dir = Vector2.ZERO
	g.touch.active = false
	var out := {"events": events, "aim": seen_aim,
		"dmg_r": hp_r - float(dm_r.get("hp", hp_r)) if enemy else 0.0,
		"dmg_l": hp_l - float(dm_l.get("hp", hp_l)) if enemy else 0.0}
	print("CASE enemy=%s aim=%s touch=%s -> events=%d aim_seen=%s dmg_r=%.0f dmg_l=%.0f" % [enemy, aim, touch, events, seen_aim, out.dmg_r, out.dmg_l])
	return out


func _dummy(at: Vector2) -> Dictionary:
	var dm: Dictionary = g.spawner.spawn_enemy("stone", at)
	dm.hp = 1000000.0
	dm.max_hp = dm.hp
	dm.spd = 0.0
	return dm
