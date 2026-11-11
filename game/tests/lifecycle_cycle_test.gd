extends Node
## 全流程反复进出的内存释放测试（docs/335）：标题（图鉴 / 认知塑造 / 蚀刻章 / 设置 / 致谢 / 选人 / 难度 / Boss 演练）→ 关闭 → 销毁标题 →
## 开局（真的跑一小段）→ 暂停 / 设置 / 属性 / 胜利结算 / 作战记录 / 对局记录 / 失败结算 → 销毁对局 → 回标题，共 CYCLES 轮。
##   godot --headless --path game res://tests/lifecycle_cycle_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit
## 每轮结束读 Performance 的对象数 / 节点数 / 孤儿节点 / 资源数 / 静态内存 与 Art 贴图缓存条数。第 WARM 轮之后作基线（首轮会建各种缓存），
## 最后一轮不得超过基线（容差见 TOL）；孤儿节点必须为 0。读数表打印出来，泄漏时看哪一列在涨。
## 全部通过打印 "LIFECYCLE CYCLE failures=0"。
const Art = preload("res://scripts/art.gd")
const RS = preload("res://scripts/run/run_stats.gd")
var CYCLES := 10
const WARM := 2
const RUN_FRAMES := 30   # 无头 --balance 每帧推进多秒对局，30 帧约一分钟对局（再长会跑到平衡批跑的终点直接退出）
## 各读数相对基线允许的增量（节点 / 对象 / 资源取小量容差，静态内存取比例）
## 对象数容差 450：UI 的 StyleBox / 换行缓存有上限（ui.gd _rbox_cache 400、_wrap_cache 512），前几十轮会缓慢填满（实测 40 轮平台化，静态内存只 +0.9 MiB），不是泄漏；
## 节点 / 孤儿 / 资源数不该涨，容差很小
const TOL := {"nodes": 8, "objects": 450, "resources": 40, "art": 4}
const MEM_RATIO := 1.05
var fails := 0
var rows: Array = []


func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: LIFECYCLE " + what)


func frames(k := 6) -> void:
	for i in k:
		await get_tree().process_frame


func snap() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"art": Art._cache.size(),
		"tex_mem": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
	}


func _ready() -> void:
	for a in Cfg.dev_args():
		if a.begins_with("--cycles="):
			CYCLES = int(a.substr(9))   # 调试：缩短轮数找泄漏
	call_deferred("run")


func run() -> void:
	await frames(3)
	var base := snap()
	for i in CYCLES:
		if not Cfg.dev_args().has("--gameonly"):
			await title_part()
		if Cfg.dev_args().has("--orphans"):
			print("LIFECYCLE after title cycle ", i + 1, " objects=", int(Performance.get_monitor(Performance.OBJECT_COUNT)))
		if not Cfg.dev_args().has("--titleonly"):
			await game_part()
		if Cfg.dev_args().has("--orphans") and i == 2:
			Node.print_orphan_nodes()
		await frames(8)
		var s := snap()
		s["cycle"] = i + 1
		rows.append(s)
		print("LIFECYCLE cycle %2d nodes=%d orphans=%d objects=%d resources=%d art=%d mem=%.1fMiB tex=%.1fMiB" % [i + 1, s.nodes, s.orphans, s.objects, s.resources, s.art, s.mem / 1048576.0, s.tex_mem / 1048576.0])
	var b: Dictionary = rows[WARM - 1]
	var last: Dictionary = rows[rows.size() - 1]
	for k in TOL:
		ok(int(last[k]) <= int(b[k]) + int(TOL[k]), "%s 第 %d 轮 %d 超过第 %d 轮基线 %d + 容差 %d（反复进出越积越多）" % [k, CYCLES, last[k], WARM, b[k], TOL[k]])
	ok(float(last.mem) <= float(b.mem) * MEM_RATIO, "静态内存 第 %d 轮 %.1f MiB 超过基线 %.1f MiB 的 %d%%" % [CYCLES, last.mem / 1048576.0, b.mem / 1048576.0, int(MEM_RATIO * 100)])
	ok(int(last.orphans) <= int(base.orphans), "孤儿节点 %d（开测前 %d）" % [last.orphans, base.orphans])
	# 单调上涨检查：第 WARM 轮之后每一轮都比前一轮多（而不只是总量超限）也报出来作提示
	var mono := true
	for i in range(WARM, rows.size()):
		if int(rows[i].objects) <= int(rows[i - 1].objects):
			mono = false
	if mono:
		print("LIFECYCLE 提示：第 %d 轮起对象数逐轮上涨（可能是缓慢泄漏，容差内未判失败）" % (WARM + 1))
	print("LIFECYCLE CYCLE failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func title_part() -> void:
	var title = load("res://main.tscn").instantiate()
	add_child(title)
	await frames(2)
	title.intro = title.INTRO_LEN
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(4)
	var entries: Array = [
		["选人", func(): title._open_op_pick(false), func(): return title.op_pick, func(): title.op_pick = false],
		["难度", func(): title.diff_pick = true, func(): return title.diff_pick, func(): title.diff_pick = false],
		["图鉴", func(): title.gallery.open(), func(): return title.gallery.visible, func(): title.gallery.close()],
		["认知塑造", func(): title.meta_ui.open(), func(): return title.meta_ui.visible, func(): title.meta_ui.close()],
		["蚀刻章", func(): title.medals_ui.open(), func(): return title.medals_ui.visible, func(): title.medals_ui.close()],
		["设置", func(): title.settings.open(), func(): return title.settings.visible, func(): title.settings.close()],
		["操作说明", func(): title.guide = true, func(): return title.guide, func(): title.guide = false],
		["致谢", func(): title._open_credits(), func(): return title.credits, func(): title.credits = false],
	]
	if preload("res://scripts/core/roster.gd").active():
		entries.append(["寻访", func(): title.hunt_ui.open(), func(): return title.hunt_ui.visible, func(): title.hunt_ui.hh.open = false])
	if Cfg.can_boss_trial():
		entries.append(["Boss 演练", func(): title.boss_trial.open(), func(): return title.boss_trial.visible, func(): title.boss_trial.close()])
	var only := ""
	for a in Cfg.dev_args():
		if a.begins_with("--screen="):
			only = a.substr(9)   # 调试：只开某一屏（none = 一屏都不开）
	for e in entries:
		if only != "" and only != e[0]:
			continue
		e[1].call()
		await frames(6)
		ok(bool(e[2].call()), "标题·%s 打开后是开着的" % e[0])
		e[3].call()
		await frames(4)
		ok(not bool(e[2].call()), "标题·%s 关闭后是关着的" % e[0])
	title.queue_free()
	await frames(4)


func game_part() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await frames(3)
	g.headless_batch = false
	var S = g.S
	var fake := RS.model(RS.fake_raw())
	# 真的跑一小段（刷怪 / 开火 / 特效 / 选卡都走正常路径；机器人在 --balance 下自己走位选卡）
	await frames(RUN_FRAMES)
	g.set_process(false)
	var steps: Array = [
		[func(): g.state = S.PAUSE, func(): return g.state == S.PAUSE],
		[func(): g.settings.open(), func(): return g.settings.visible],
		[func(): g.settings.close(); g.state = S.STATS, func(): return g.state == S.STATS],
		[func(): g.state = S.WIN; g.state_age = 3.0; g.settlement.set_model(fake), func(): return g.state == S.WIN],
		[func(): g.run_stats.show_model(fake), func(): return g.run_stats.open],
		[func(): g.run_stats.close(); g.run_log.open_log(), func(): return g.run_log.open],
		[func(): g.run_log.close(); g.state = S.DEAD; g.state_age = 3.0; g.settlement.set_model(fake), func(): return g.state == S.DEAD],
	]
	g.set_process(true)
	for s in steps:
		s[0].call()
		await frames(6)
		ok(bool(s[1].call()), "局内步骤未生效")
	g.queue_free()
	await frames(4)
