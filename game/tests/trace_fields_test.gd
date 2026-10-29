extends Node
## TRACE 新增字段（10-29，docs/126 R3，docs/36 §3.2）的灵敏度与只读性：
##   godot --headless --path game res://tests/trace_fields_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit,texas
## 同一局状态上只改一个量，对应哈希必须变（sq=队友位置 / 突击生命 / 技力 / 普攻计时；lamp；nd=神经损伤；rl=藏品数），
## 同一状态连算两次必须相同，且计算不动五条 rng 流（TRACE 只读）。全部通过打印 "TRACE FIELDS failures=0"。
var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func _rng() -> Array:
	var g = game
	return [g.rng.state, g.rng_spawn.state, g.rng_enemy.state, g.rng_drop.state, g.rng_op.state]


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	var g = game
	var at = g.autotest_sys
	ok(g.squad.ops.size() >= 2, "编队至少两人（队长 + 队友），实际 %d" % g.squad.ops.size())
	var rng0 := _rng()
	var line0: String = at.trace_extra()
	ok(line0 == at.trace_extra(), "同一状态连算两次相同")
	ok(_rng() == rng0, "计算不动五条 rng 流")
	ok(line0.contains(" sq=") and line0.contains(" lamp=") and line0.contains(" nd=") and line0.contains(" rl="), "四个字段都在: " + line0)
	var mate = null
	for o in g.squad.ops:
		if o != g.ch:
			mate = o
			break
	ok(mate != null, "找到队友")
	if mate != null:
		var base: int = at.trace_squad_hash()
		var cases := {
			"队友 x 位置": func(): mate.pos.x += 3.0,
			"队友 y 位置": func(): mate.pos.y += 3.0,
			"队友突击生命": func(): mate.cmd_hp -= 0.25,
			"队友 S1 技力": func(): mate.sp[0] += 5.0,
			"队友 S2 技力": func(): mate.sp[1] += 5.0,
			"队友 attack_t": func(): mate.attack_t += 0.1,
			"队友 fire_t": func(): mate.fire_t += 0.1,
		}
		if mate.get("cd") != null:
			cases["队友普攻冷却 cd"] = func(): mate.cd += 0.2
		if mate.get("atk_n") != null:
			cases["队友普攻次数 atk_n"] = func(): mate.atk_n += 1
		for k in cases:
			var snap := [mate.pos, mate.cmd_hp, mate.sp.duplicate(), mate.attack_t, mate.fire_t, mate.get("cd"), mate.get("atk_n")]
			cases[k].call()
			ok(at.trace_squad_hash() != base, "sq 对「%s」敏感" % k)
			mate.pos = snap[0]
			mate.cmd_hp = snap[1]
			mate.sp = snap[2]
			mate.attack_t = snap[3]
			mate.fire_t = snap[4]
			if snap[5] != null:
				mate.cd = snap[5]
			if snap[6] != null:
				mate.atk_n = snap[6]
			ok(at.trace_squad_hash() == base, "还原「%s」后 sq 回到原值" % k)
		# 浮点噪声（量化以下）不应造成假差异
		mate.pos.x += 0.001
		ok(at.trace_squad_hash() == base, "位置 0.001 的浮点噪声不改变 sq")
		mate.pos.x -= 0.001
	var l0: String = at.trace_extra()
	g.lamp += 1.0
	ok(at.trace_extra() != l0, "lamp 字段对灯火 ±1 敏感")
	g.lamp -= 1.0
	var nd0: int = at.trace_nerve_hash()
	for f in ["nerve", "nerve_lock", "nerve_taken_mult", "nerve_aura_t"]:
		var old: float = g.get(f)
		g.set(f, old + 0.5)
		ok(at.trace_nerve_hash() != nd0, "nd 对 %s 敏感" % f)
		g.set(f, old)
	ok(at.trace_nerve_hash() == nd0, "还原后 nd 回到原值")
	var rl0: String = at.trace_extra()
	g.relics.append("fake")
	ok(at.trace_extra() != rl0, "rl 字段对藏品数敏感")
	g.relics.pop_back()
	ok(at.trace_extra() == rl0, "全部还原后整串字段与开头相同")
	print("%d checks, %d failed" % [n, fails])
	print("TRACE FIELDS failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
