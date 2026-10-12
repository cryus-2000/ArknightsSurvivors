extends Node
## 作战记录（docs/77）快检：godot --headless --path game res://tests/run_stats_test.tscn -- --regression --balance --seed=1 --op=mizuki --squad=skadi
## A. 假记录（RunStats.fake_raw）：各行伤害之和 = 全队伤害、整数占比合计 100、占比小数合计 1、每行来源相加 = 该行伤害、
##    来源占比合计 100、离队干员的在队时长、承伤按敌人合并、最大余数法边界。
## B. 真实短局（机器人打到 45 秒）：按干员拆的输出合计 = dmg_out 合计、时间线分箱合计 = 输出合计、入队记录、模型守恒。
## C. 界面：结算上打开作战记录 → 卡片命中区 = 行数、方向键 / Enter / Esc / 点卡 / 换干员 / 返回；假记录在桌面 1280×720 与手机 1044×481 下排版不出界。
## 击杀是参与击杀（死前 3 秒内命中过），各行合计可以大于总击杀；runs.jsonl 的 op_stats 由 telemetry.op_summary() 给出。
## 全部通过时打印 "RUN STATS failures=0"。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")

var game: Node
var frames := 0
var n := 0
var fails := 0
var done := false


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
		print("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.01) -> void:
	ok(absf(a - b) <= eps * maxf(1.0, absf(b)), "%s（期望 %s，实际 %s）" % [what, b, a])


func _process(_d: float) -> void:
	frames += 1
	if done:
		return
	if frames == 3:
		test_model(RunStats.model(RunStats.fake_raw()), "假记录")
		test_fake_details()
	if frames > 3 and (game.t >= 45.0 or frames > 4000):
		done = true
		await test_real()
		await test_screen()
		print("%d checks, %d failed" % [n, fails])
		print("RUN STATS failures=%d" % fails)
		get_tree().quit(1 if fails > 0 else 0)


## 守恒：占比、来源、时间线
func test_model(m: Dictionary, tag: String) -> void:
	var rows: Array = m.rows
	ok(not rows.is_empty(), tag + "：有行")
	var s := 0.0
	var sh := 0.0
	var pc := 0
	for r in rows:
		s += float(r.dmg)
		sh += float(r.share)
		pc += int(r.pct)
		var ss := 0.0
		var sp := 0
		for x in r.sources:
			ss += float(x.v)
			sp += int(x.pct)
		near(ss, float(r.dmg), "%s：%s 来源相加 = 该行伤害" % [tag, r.name], 0.0001)
		if float(r.dmg) > 0.0:
			ok(sp == 100, "%s：%s 来源占比合计 100（%d）" % [tag, r.name, sp])
		ok(float(r.in_s) >= 1.0, "%s：%s 在队时长 ≥ 1" % [tag, r.name])
		near(float(r.dps), float(r.dmg) / float(r.in_s), "%s：%s 每秒伤害 = 伤害 / 在队时长" % [tag, r.name], 0.0001)
	near(s, float(m.total), tag + "：各行之和 = 全队伤害", 0.0001)
	if float(m.total) > 0.0:
		ok(pc == 100, "%s：整数占比合计 100（%d）" % [tag, pc])
		near(sh, 1.0, tag + "：占比合计 1", 0.000001)
	ok((m.timeline.series as Array).size() == maxi(1, int(ceil(float(m.t) / float(m.timeline.bin_s)))), tag + "：时间线格数 = 时长 / 10 秒")
	for col in m.timeline.series:
		ok((col as Array).size() == rows.size(), tag + "：时间线每格的行数 = 干员行数")
		break


func test_fake_details() -> void:
	var m: Dictionary = RunStats.model(RunStats.fake_raw())
	ok(m.rows[0].key == "mizuki" and m.rows[0].leader, "主控排第一")
	ok(m.rows[m.rows.size() - 1].key == RunStats.OTHER, "藏品与支援排最后")
	var sa: Dictionary = {}
	for r in m.rows:
		if r.key == "saria":
			sa = r
	near(float(sa.get("in_s", 0.0)), 210.0, "被替换离队的干员：在队时长 = 离队 − 入队")
	near(float(sa.get("left_t", -1.0)), 610.0, "离队时刻")
	near(float(sa.get("heal", 0.0)), 1840.0, "治疗量按干员名对上 heal 记录")
	var tk: Array = m.leader.taken_src
	ok(not tk.is_empty() and tk[0].name == "接潮主教" and absf(float(tk[0].v) - 2140.0) < 0.01, "承伤：同一 Boss 的招式与接触合并（接潮主教 2140）")
	ok(tk.any(func(x): return str(x.name).begins_with("寂灭")), "承伤：熄灯持续掉血单列")
	ok(m.best.op == "斯卡蒂" and int(m.best.v) == 18412, "最高单次：数值与干员名")
	ok(RunStats.pct_ints([1, 1, 1]).reduce(func(a, b): return a + b, 0) == 100, "最大余数法：三等分合计 100")
	ok(RunStats.pct_ints([0, 0]) == [0, 0], "最大余数法：全 0")
	ok(RunStats.pct_ints([999, 1]) == [100, 0] or RunStats.pct_ints([999, 1]) == [99, 1], "最大余数法：极端比例")
	ok(game.run_stats.fmt_n(1291000.0) == "1,291,000" and game.run_stats.fmt_n(12.0) == "12", "千分位")
	var top: Array = game.run_stats.top_sources(m.rows[0].sources, 3)
	var tv := 0.0
	var tp := 0
	for s in top:
		tv += float(s.v)
		tp += int(s.pct)
	ok(top.size() == 4 and top[3].name == "其他" and absf(tv - float(m.rows[0].dmg)) < 0.01 and tp == 100, "前 N 条 + 其他：数值与占比守恒")


func test_real() -> void:
	var tm = game.telemetry
	var out := 0.0
	for k in game.dmg_out:
		out += float(game.dmg_out[k])
	var op_sum := 0.0
	for op in tm.op_out:
		for s in tm.op_out[op]:
			op_sum += float(tm.op_out[op][s])
	var bin_sum := 0.0
	for b in tm.out_bins:
		for k in b:
			bin_sum += float(b[k])
	ok(out > 0.0, "真实局：45 秒内打出了伤害（%.0f）" % out)
	near(op_sum, out, "真实局：按干员拆的输出合计 = dmg_out 合计", 0.0001)
	near(bin_sum, out, "真实局：时间线分箱合计 = dmg_out 合计", 0.0001)
	var ids: Array = tm.joins.map(func(j): return j.id)
	ok(ids.has("mizuki") and ids.has("skadi"), "真实局：入队记录有主控与 --squad 干员（%s）" % [ids])
	ok(tm.op_out.has("mizuki"), "真实局：主控有按干员记的输出")
	var kmax := 0
	for k in tm.op_kills:
		kmax = maxi(kmax, int(tm.op_kills[k]))
	ok(kmax > 0 and kmax <= int(game.kills), "真实局：参与击杀每名干员（最多 %d）≤ 击杀（%d）" % [kmax, game.kills])
	var lead_k := int(tm.op_kills.get("mizuki", 0))
	ok(lead_k > 0, "真实局：主控有参与击杀")
	var osum: Array = tm.op_summary()
	var shs := 0.0
	for o in osum:
		shs += float(o.share)
	ok(osum.size() >= 2 and absf(shs - 1.0) < 0.01 and osum[0].id == "mizuki" and str(osum[0].top) != "", "真实局：runs.jsonl 按干员汇总（%d 行，占比合计 %.3f）" % [osum.size(), shs])
	ok(float(tm.best_hit.get("v", 0.0)) > 0.0, "真实局：有最高单次")
	var ls := 0.0
	for v in tm.lamp_s:
		ls += float(v)
	near(ls, float(game.t), "真实局：灯火四档时长合计 = 局内时间", 0.05)
	var m: Dictionary = RunStats.model(RunStats.snapshot(game))
	test_model(m, "真实局")
	near(float(m.total), out, "真实局：模型全队伤害 = dmg_out 合计", 0.0001)


func _redraw() -> void:
	game.hud.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame


func _cards() -> Array:
	return game.run_stats.cells.filter(func(c): return c[1] == "card")


func _in_bounds(vs: Vector2, tag: String) -> void:
	var bad: Array = []
	for c in game.run_stats.cells:
		var r: Rect2 = c[0]
		if r.position.x < -8.0 or r.position.y < -8.0 or r.end.x > vs.x + 8.0 or r.end.y > vs.y + 8.0:
			bad.append("%s %s" % [c[1], r])
	ok(bad.is_empty(), "%s：命中区都在屏幕内 %s" % [tag, bad])


func test_screen() -> void:
	game.set_process(false)   # 停住对局与机器人（平衡模式进结算会直接退出）
	var rs = game.run_stats
	game.hud.size = Vector2(1280, 720)   # 无头窗口只有 64×64
	game.state = Game.S.DEAD
	game.state_age = 99.0
	await _redraw()
	ok(game.result_btns.any(func(b): return b[1] == "stats"), "失败结算有「作战记录」按钮")
	game._do_action("stats")
	ok(rs.open and rs.page == 0, "按钮打开作战记录总览")
	await _redraw()
	var nrow: int = rs.rows().size()
	ok(_cards().size() == nrow and nrow >= 2, "总览：每行一张卡（%d / %d）" % [_cards().size(), nrow])
	ok(game.result_btns.is_empty(), "作战记录打开时结算按钮不接点击")
	rs.key(KEY_RIGHT)
	ok(rs.sel == 1, "→ 选下一张卡")
	rs.key(KEY_LEFT)
	rs.key(KEY_LEFT)
	ok(rs.sel == 0, "← 到头不循环")
	rs.key(KEY_ENTER)
	ok(rs.page == 1 and rs.sel == 0, "Enter 进详情")
	await _redraw()
	ok(rs.cells.any(func(c): return c[1] == "back"), "详情有返回按钮")
	rs.key(KEY_RIGHT)
	ok(rs.page == 1 and rs.sel == 1, "详情里 → 换下一名干员")
	rs.key(KEY_ESCAPE)
	ok(rs.page == 0, "Esc 回总览")
	await _redraw()
	var c1: Array = _cards()[1]
	rs.click((c1[0] as Rect2).get_center())
	ok(rs.page == 1 and rs.sel == 1, "点卡进该干员详情")
	await _redraw()
	for c in rs.cells:
		if c[1] == "back":
			rs.click((c[0] as Rect2).get_center())
			break
	ok(rs.page == 0, "点「返回总览」")
	rs.key(KEY_ESCAPE)
	ok(not rs.open, "总览 Esc 回结算")
	await _redraw()
	ok(game.result_btns.size() == 3, "回到结算：三个按钮")
	# 假记录：桌面 1280×720、手机 1044×481
	game.state = Game.S.WIN
	for vs in [Vector2(1280, 720), Vector2(1044, 481)]:
		game.hud.size = vs
		rs.show_model(RunStats.model(RunStats.fake_raw()))
		await _redraw()
		var tag := "假记录 %dx%d" % [int(vs.x), int(vs.y)]
		ok(_cards().size() == 5, tag + "：五张卡（四名干员 + 藏品与支援）")
		_in_bounds(vs, tag + " 总览")
		var cards: Array = _cards()
		var ok_gap := true
		for i in cards.size() - 1:
			if (cards[i][0] as Rect2).intersects(cards[i + 1][0]):
				ok_gap = false
		ok(ok_gap, tag + "：卡片不重叠")
		rs.key(KEY_ENTER)
		await _redraw()
		_in_bounds(vs, tag + " 主控详情")
		rs.key(KEY_RIGHT)
		await _redraw()
		_in_bounds(vs, tag + " 队友详情")
		rs.close()
