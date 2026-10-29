extends Node
## g.hit 空描述符沿用上次（arch_review_1029 §4 / combat.gd:1089）的特征测试：
##   godot --headless --path game res://tests/hit_fallback_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit
## combat._damage 在 h 为空时用 `h = g.hit`（旧调用方式）。g.hit 是「最近一次 combat.hit(src)」留下的当前描述符，
## 所以：先用带干员归属的 h 打一下，g.hit 又恰好还留着那一下的描述符，再传空 h 调 damage，
## 这第二下的伤害会被记到上一下的干员 / 来源上（作战记录 op_out、dmg_out 都错记；本应记「_other」/ 「?」）。
## 这是**已知缺陷**，这里只记录当前行为（特征测试），不改玩法：以下标 [已知缺陷] 的断言固定的是错记的现状，
## 修复时（空 h 改为「视为无归属」）要把这几条翻成相反的断言；其余是回归保护（显式传 h 时归属正确、_damage 不改 g.hit）。
## 全部通过打印 "HIT FALLBACK failures=0"。
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


func out_of(op: String, src: String) -> float:
	return float(game.telemetry.op_out.get(op, {}).get(src, 0.0))


func tgt(pos: Vector2) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy("stone", pos)
	e.maxhp = 1.0e9
	e.hp = 1.0e9
	return e


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	var g = game
	g.set_process(false)
	g.enemies.clear()
	g.hit_src["FB_A"] = {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": [], "class": "", "op": "fb_op_a"}
	g.hit_src["FB_B"] = {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": [], "class": "", "op": "fb_op_b"}
	var ea := tgt(g.ppos + Vector2(300, 0))
	var eb := tgt(g.ppos + Vector2(300, 80))
	var ec := tgt(g.ppos + Vector2(300, 160))
	var ed := tgt(g.ppos + Vector2(300, 240))
	var ha: Dictionary = g.combat.make_hit("FB_A")
	var hb: Dictionary = g.combat.make_hit("FB_B")
	ok(ha.op == "fb_op_a" and hb.op == "fb_op_b", "make_hit 带上 op 归属")

	# 回归保护：显式传 h 时按 h 归属
	g.combat.damage(ea, 100.0, ha)
	var a1 := out_of("fb_op_a", "FB_A")
	ok(a1 > 0.0, "显式 h：伤害记到 fb_op_a / FB_A（%.2f）" % a1)
	ok(float(g.dmg_out.get("FB_A", 0.0)) > 0.0, "显式 h：dmg_out[FB_A] 有记账")
	g.combat.damage(eb, 100.0, hb)
	ok(out_of("fb_op_b", "FB_B") > 0.0, "显式 h（另一名干员）：记到 fb_op_b / FB_B")
	ok(out_of("fb_op_a", "FB_A") == a1, "显式 h（B）不动 A 的账")

	# [已知缺陷] g.hit 留着 A 的描述符，传空 h → 记到 A 头上
	g.hit = ha
	var other0 := out_of("_other", "?")
	var dmgA0 := float(g.dmg_out.get("FB_A", 0.0))
	g.combat.damage(ec, 100.0, {})
	ok(out_of("fb_op_a", "FB_A") > a1, "[已知缺陷] 空 h + g.hit 残留 A：伤害被错记给 fb_op_a（%.2f → %.2f）" % [a1, out_of("fb_op_a", "FB_A")])
	ok(float(g.dmg_out.get("FB_A", 0.0)) > dmgA0, "[已知缺陷] 空 h：dmg_out[FB_A] 也被错记")
	ok(out_of("_other", "?") == other0, "[已知缺陷] 空 h：没有记到「_other」")
	ok(g.hit == ha, "_damage 不改 g.hit（非致命一击）")

	# 对照：g.hit 是默认描述符（无 op）时，空 h 记「_other」/「?」，这是预期行为
	g.hit = {"src": "?", "emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []}
	var a2 := out_of("fb_op_a", "FB_A")
	g.combat.damage(ed, 100.0, {})
	ok(out_of("_other", "?") > other0, "g.hit 为默认无归属描述符时空 h 记到「_other」")
	ok(out_of("fb_op_a", "FB_A") == a2, "……且不动 A 的账")

	# 显式 h 压过残留的 g.hit
	g.hit = ha
	g.combat.damage(ed, 100.0, hb)
	var b_before := out_of("fb_op_b", "FB_B")
	var a_before := out_of("fb_op_a", "FB_A")
	g.combat.damage(ed, 100.0, hb)
	ok(out_of("fb_op_b", "FB_B") > b_before and out_of("fb_op_a", "FB_A") == a_before, "显式 h = B 时，残留的 g.hit = A 不会串账")
	g.enemies.clear()
	print("%d checks, %d failed" % [n, fails])
	print("HIT FALLBACK failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
