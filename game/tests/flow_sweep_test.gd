extends Node
## 设置 / 暂停菜单全量过一遍（docs/335）：设置面板的每一行各向两个方向调一次（再调回原值）、子页（性能报告 / 触屏布局）开了能关、
## 标签页逐个切；局内暂停菜单的 resume / settings / guide / demos / stats 动作各走一次，状态能回到暂停 / 对局。
## （restart / title 会换场景，由 lifecycle_cycle_test 的整局销毁路径和真机连测覆盖。）
##   godot --headless --path game res://tests/flow_sweep_test.tscn -- --regression --seed=1 --op=skadi --squad=kaltsit
## 脚本错误由 check.py 扫输出；本测试只判界面状态。全部通过打印 "FLOW SWEEP failures=0"。
const SetPanel = preload("res://scripts/settings_panel.gd")
var fails := 0
var n := 0


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: FLOW SWEEP " + what)


func frames(k := 4) -> void:
	for i in k:
		await get_tree().process_frame


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	await settings_part()
	await pause_part()
	print("%d checks, %d failed" % [n, fails])
	print("FLOW SWEEP failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func settings_part() -> void:
	var title = load("res://main.tscn").instantiate()
	add_child(title)
	await frames(2)
	title.intro = title.INTRO_LEN
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(4)
	var sp = title.settings
	sp.open()
	await frames(4)
	ok(sp.visible, "设置没打开")
	# 记下所有行的当前值，调完还原（测试不写存档，但同进程后面还要用）
	var saved := {}
	for row in SetPanel.ROWS:
		if row.key != "":
			saved[row.key] = Cfg.get(row.key)
	for i in SetPanel.ROWS.size():
		var row: Dictionary = SetPanel.ROWS[i]
		if row.type in ["runs", "cloud", "cloud_pull", "cloud_push", "back", "touchpad", "perf"]:
			continue   # 会开系统文件夹 / 联网 / 关闭本页：下面单独测子页
		for dir in [1, -1]:
			sp._adjust(i, dir)
			await frames(2)
			ok(sp.visible, "设置行 %s 调整后面板消失" % row.cn)
	# 还原
	for k in saved:
		Cfg.set(k, saved[k])
	Cfg.apply()
	for i in SetPanel.ROWS.size():
		var row: Dictionary = SetPanel.ROWS[i]
		if row.type == "perf":
			sp._adjust(i, 1)
			await frames(4)
			ok(sp.perf_view != null and sp.perf_view.visible, "性能报告页没打开")
			sp.perf_view.close()
			await frames(3)
			ok(not sp.perf_view.visible and sp.visible, "性能报告页关不回设置")
		elif row.type == "touchpad":
			sp._adjust(i, 1)
			await frames(4)
			ok(sp.editor != null and sp.editor.visible, "触屏布局页没打开")
			sp.editor.close(false)
			await frames(3)
			ok(not sp.editor.visible and sp.visible, "触屏布局页关不回设置")
	# 标签页逐个切
	for t in 5:
		sp._set_tab(t)
		await frames(2)
		ok(sp.visible, "切到标签 %d 后面板消失" % t)
	# 返回行
	for i in SetPanel.ROWS.size():
		if SetPanel.ROWS[i].type == "back":
			sp._adjust(i, 1)
	await frames(3)
	ok(not sp.visible, "返回行没关设置")
	title.queue_free()
	await frames(3)


func pause_part() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await frames(4)
	g.headless_batch = false
	var S = g.S
	g.state = S.PAUSE
	await frames(4)
	g._do_action("settings")
	await frames(4)
	ok(g.settings.visible, "暂停·设置 没打开")
	g.settings.close()
	await frames(3)
	ok(g.state == S.PAUSE, "暂停·设置 关闭后不在暂停")
	g._do_action("guide")
	await frames(4)
	g._do_action("demos")
	await frames(4)
	g._do_action("stats")
	await frames(4)
	g._do_action("resume")
	await frames(3)
	ok(g.state == S.PLAY, "暂停·继续 没回到对局")
	g.queue_free()
	await frames(3)
