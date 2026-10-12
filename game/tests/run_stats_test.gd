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
const Character = preload("res://scripts/characters/character.gd")

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
	# 右栏统计表：数值与模型一致
	var sv := {}
	for st in m.stats:
		sv[st.label] = st
	near(float(sv["造成伤害"].v), float(m.total), "统计表：造成伤害 = 全队伤害", 0.0001)
	ok(int(sv["技能发动"].v) == 60, "统计表：技能发动 = 各干员合计（%d）" % int(sv["技能发动"].v))
	ok(int(sv["藏品"].v) == 5 and int(sv["Boss 击破"].v) == 3 and int(sv["打开补给箱"].v) == 6, "统计表：藏品 / Boss 击破 / 补给箱")
	ok(sv.has("源石锭熔铸") and sv.has("海嗣祭坛") and int(sv["点亮引航灯标"].v) == 4, "统计表：熔铸、祭坛、灯标")
	near(float(sv["受到伤害"].v), float(m.leader.taken), "统计表：受到伤害 = 主控承伤", 0.0001)
	# 受到伤害与生命回复是两份独立记录（dmg_log / heal_log）：假记录里两者不同，统计表也必须不同
	near(float(sv["生命回复"].v), 6680.0, "统计表：生命回复 = heal 记录合计", 0.0001)
	near(float(sv["受到伤害"].v), 4659.0, "统计表：受到伤害 = dmg_log 合计 + 熄灯持续掉血", 0.0001)
	ok(absf(float(sv["受到伤害"].v) - float(sv["生命回复"].v)) > 1.0, "统计表：受到伤害与生命回复不是同一个数")
	ok(m.final_boss.name == "偏执泡影" and m.relic_list.size() == 5, "胜利：最终 Boss 与藏品列表")
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
	var sv := {}
	for st in m.stats:
		sv[st.label] = st
	ok(int(sv["击杀"].v) == int(game.kills) and int(sv["藏品"].v) == game.relics.size(), "真实局：统计表击杀 / 藏品数")
	ok(float(sv["获得经验"].v) > 0.0 and float(sv["探索时间"].v) >= 45.0, "真实局：统计表经验与时间")
	var dl := 0.0
	for k2 in game.dmg_log:
		dl += float(game.dmg_log[k2])
	var hl := 0.0
	for k2 in game.heal_log:
		hl += float(game.heal_log[k2])
	near(float(sv["受到伤害"].v), dl + (float(tm.dark_dmg) if float(tm.dark_dmg) > 0.5 else 0.0), "真实局：受到伤害 = dmg_log 合计（+ 熄灯掉血）", 0.001)
	near(float(sv["生命回复"].v), hl, "真实局：生命回复 = heal_log 合计", 0.001)
	ok(m.relic_list.size() == game.relics.size(), "真实局：藏品列表按拾取顺序全部列出")
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
	rs.key(KEY_DOWN)
	ok(rs.sel == 1, "↓ 选下一名干员")
	rs.key(KEY_UP)
	rs.key(KEY_UP)
	ok(rs.sel == 0, "↑ 到头不循环")
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
		ok(_cards().size() == 5, tag + "：编队条五张卡（四名干员 + 藏品与支援）")
		_in_bounds(vs, tag + " 总览")
		# 藏品不设上限（10-12）：60 件时藏品格不出区域、方向键走得到最后一件且它在视野里
		var keep: Array = rs.model.relic_list
		var many: Array = []
		for k in 60:
			many.append(keep[k % keep.size()].duplicate())
		rs.model.relic_list = many
		if vs.y < 560.0:
			rs._act("tab", 1)
		await _redraw()
		_in_bounds(vs, tag + " 60 件藏品")
		ok(rs.cells.filter(func(c): return c[1] == "relic").size() >= 30, tag + "：60 件藏品至少画出 30 格")
		rs.zone = 0
		rs.rel = 0
		for k in 80:
			rs._nav(1, 0)
		await _redraw()
		ok(rs.rel == 59 and rs.cells.any(func(c): return c[1] == "relic" and int(c[2]) == 59), tag + "：→ 走到第 60 件且在视野里")
		var grid_bot := 0.0
		for c in rs.cells:
			if c[1] == "relic":
				grid_bot = maxf(grid_bot, (c[0] as Rect2).end.y)
		ok(grid_bot <= rs._relic_rect.end.y + 0.5 and (vs.y < 560.0 or grid_bot < vs.y * 0.62), tag + "：60 件藏品格压缩 / 滚动后不压数据（格底 %.0f）" % grid_bot)
		var cw0: float = 99.0
		for c in rs.cells:
			if c[1] == "relic":
				cw0 = minf(cw0, (c[0] as Rect2).size.x)
		ok(cw0 >= 23.9, tag + "：藏品格最小压到 30 像素格（格宽 %.0f）" % cw0)
		await _redraw()
		ok(rs._pop_anchor.size.x > 0.0, tag + "：60 件时选中藏品仍有说明弹窗")
		# 200 件：压到 30 像素格也放不下，要滚动；选中最后一件时它滚进视野
		var lots: Array = []
		for k in 200:
			lots.append(keep[k % keep.size()].duplicate())
		rs.model.relic_list = lots
		rs.zone = 0
		rs.rel = 0
		await _redraw()
		for k in 220:
			rs._nav(1, 0)
		await _redraw()
		ok(rs.rel == 199 and (rs._rel_row0 > 0 or vs.y < 560.0) and rs.cells.any(func(c): return c[1] == "relic" and int(c[2]) == 199), tag + "：200 件时滚动到最后一件（第 %d 行起）" % (rs._rel_row0 + 1))
		_in_bounds(vs, tag + " 200 件藏品")
		rs.model.relic_list = keep
		rs.rel = 0
		rs.zone = 1
		if vs.y < 560.0:
			rs._act("tab", 0)
		await _redraw()
		if vs.y >= 560.0:
			ok(rs.cells.filter(func(c): return c[1] == "relic").size() == 5, tag + "：藏品格五格")
			rs.key(KEY_RIGHT)
			ok(rs.zone == 0, tag + "：编队列表 → 进藏品格")
			rs.key(KEY_RIGHT)
			ok(rs.rel == 1, tag + "：藏品格 → 选下一件")
			await _redraw()
			ok(rs.portraits.size() >= 1 and rs._pop_anchor.size.x > 0.0, tag + "：选中藏品时画说明弹窗")
			rs.key(KEY_LEFT)
			rs.key(KEY_LEFT)
			ok(rs.zone == 1, tag + "：藏品格最左 ← 回编队列表")
		else:
			for tb in [1, 2, 0]:
				rs._act("tab", tb)
				await _redraw()
				_in_bounds(vs, tag + " 第 %d 页" % tb)
				if tb == 1:
					ok(rs.cells.filter(func(c): return c[1] == "relic").size() == 5, tag + "：藏品页五格")
				if tb == 2:
					ok(rs.stat_scroll == 0, tag + "：数据页")
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
	await test_portraits()
	await test_killer()


func _check_portraits(tag: String) -> void:
	var bad: Array = []
	for pr in game.run_stats.portraits:
		var d: Rect2 = pr[0]
		var box: Rect2 = pr[1]
		if d.size.x <= 0.0 or d.position.x < box.position.x - 0.51 or d.position.y < box.position.y - 0.51 or d.end.x > box.end.x + 0.51 or d.end.y > box.end.y + 0.51:
			bad.append("%s in %s" % [d, box])
	ok(bad.is_empty(), "%s：像都在像框内 %s" % [tag, bad.slice(0, 3)])


## 18 名干员分批放进编队（每批 5 名），桌面与手机的总览、每名干员的详情：像都在像框内（像框都在卡片内，由版式保证）
func test_portraits() -> void:
	var rs = game.run_stats
	var ids: Array = Character.list_ids()
	ok(ids.size() >= 18, "干员名单 %d 名" % ids.size())
	var base: Dictionary = RunStats.fake_raw()
	var k := 0
	while k < ids.size():
		var batch: Array = ids.slice(k, k + 5)
		var raw: Dictionary = base.duplicate(true)
		raw.ops = []
		raw.op_out = {}
		for j in batch.size():
			var d: Dictionary = Character.load_def(batch[j])
			raw.ops.append({"id": batch[j], "name": str(d.get("name", batch[j])), "en": str(d.get("en", "")), "col": [0.5, 0.7, 0.9], "leader": j == 0, "t": j * 60.0, "left": -1.0})
			raw.op_out[batch[j]] = {"普攻": 1000.0 * (j + 1)}
		for vs in [Vector2(1280, 720), Vector2(1044, 481)]:
			game.hud.size = vs
			rs.show_model(RunStats.model(raw))
			await _redraw()
			var cnt: int = rs.portraits.size()
			ok(cnt >= batch.size() + 1, "像框数（%d）≥ 编队 %d + 主控卡" % [cnt, batch.size()])
			_check_portraits("%s %dx%d 总览" % [",".join(batch), int(vs.x), int(vs.y)])
			for j in batch.size():
				rs._detail(j)
				await _redraw()
				_check_portraits("%s %dx%d 详情" % [batch[j], int(vs.x), int(vs.y)])
			rs.close()
		k += 5


## 击倒者归属：侵蚀记给施加它的敌人、溟痕记成环境、最近 3 秒伤害最多的那一方
func test_killer() -> void:
	var tm = game.telemetry
	tm.blame.clear()
	tm.appliers.clear()
	tm.on_status("corrode", "bone", 30.0)
	tm.on_lose(5.0, "contact_slider")
	tm.on_lose(12.0, "corrode")
	var k: Dictionary = RunStats.killer_info(tm.killer())
	ok(k.get("type", "") == "bone" and k.get("cause", "") == "侵蚀", "侵蚀致死记给施加侵蚀的敌人（%s）" % [k])
	tm.blame.clear()
	tm.on_status("nerve", "", 1.0)
	tm.on_lose(20.0, "mire")
	tm.on_lose(8.0, "nerve")
	k = RunStats.killer_info(tm.killer())
	ok(k.get("env", "") == "mire" and k.get("name", "") == "溟痕", "溟痕致死是环境（%s）" % [k])
	tm.blame.clear()
	tm.on_lose(9.0, "zone")
	k = RunStats.killer_info(tm.killer())
	ok(k.get("env", "") == "zone" and k.get("name", "") == "黑潮", "黑潮致死是环境")
	var arts: Array = game.run_stats._env_art("zone")
	ok(arts.size() == 2 and arts[0] != null, "黑潮有图（不是占位菱形）")
