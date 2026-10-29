extends Node
## 界面冒烟（docs/126 R6）：把玩家会走过的每一屏打开 → 等若干帧（真的画）→ 关闭，进出两遍：
##   godot --headless --path game res://tests/ui_smoke_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit
## 检查三件事：
##   ① 无脚本错误：本测试自己不判，由 tools/check.py 的 check_scene 扫输出里的 SCRIPT ERROR / 解析错误（和其余场景回归同口径）；
##   ② 无缺图：Art._cache 里值为 null 的键就是「请求过但没找到」的贴图（Art.tex 缺图时存 null）。每屏打开前后各取一份，新增的 null 键记为这一屏的缺图；
##      允许名单 OPTIONAL_PREFIX 里的是有程序画法回退的可选特效图（art.gd 注释写明「缺图回退」），其余新增缺图一律失败；
##   ③ 进出不留残余：第一遍之后各屏关闭后的节点数记成基线，第二遍同屏关闭后节点数不得再涨（容差 3），否则是每开一次就泄漏节点。
## 覆盖：标题页（选人 / 难度 / 图鉴 / 寻访 / 认知塑造 / 蚀刻章 / 设置 / 操作说明 / 致谢 / Boss 演练）；局内（HUD / 暂停 / 暂停里的设置 / 属性面板 / 胜利结算 / 作战记录 / 对局记录 / 失败结算）。
## 没覆盖（明确跳过，见汇报）：标题·寻访（带任何测试参数时 Roster 名册未启用，open_browse 返回 false，运行时打印「跳过」）；标题 → 局内的真实换场景（change_scene 会杀掉本测试）；结算页上的寻访（headless 里依赖局外存档状态）；
##   手机触屏版式（有 touch_layout / cam_resize_touch / op_select 等专项）；音频（--audio-driver Dummy / 静音）。
## 全部通过打印 "UI SMOKE failures=0"。
const Art = preload("res://scripts/art.gd")
const RS = preload("res://scripts/run/run_stats.gd")
## 有程序回退的可选特效图 / 占位前缀（不算缺图）
const OPTIONAL_PREFIX := ["fx_", "ui_opt_"]
## 假数据造成的缺图：RS.fake_raw() 里的假藏品 id 999（结算页按它找图标），不是真缺图
const FAKE_DATA := ["relic_999"]
const FRAMES := 8
var title: Control
var game: Node
var n := 0
var fails := 0
var base_nodes := {}
var missing_all := {}


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: UI SMOKE " + what)


func frames(k := FRAMES) -> void:
	for i in k:
		await get_tree().process_frame


func nulls() -> Dictionary:
	var out := {}
	for k in Art._cache:
		if Art._cache[k] == null:
			out[k] = true
	return out


func is_optional(name: String) -> bool:
	if name in FAKE_DATA:
		return true
	for p in OPTIONAL_PREFIX:
		if name.begins_with(p):
			return true
	return false


## 一屏：打开 → 等帧 → 检查开着 → 关闭 → 等帧 → 检查关了；pass_i = 0 记节点基线，1 比对
func screen(tag: String, pass_i: int, open_c: Callable, is_open_c: Callable, close_c: Callable) -> void:
	var m0 := nulls()
	open_c.call()
	await frames()
	ok(bool(is_open_c.call()), tag + "：打开后是开着的")
	var m1 := nulls()
	for k in m1:
		if not m0.has(k):
			missing_all[tag + " / " + k] = true
			if not is_optional(k):
				ok(false, "%s：缺图 %s（Art.tex 找不到）" % [tag, k])
	close_c.call()
	await frames()
	ok(not bool(is_open_c.call()), tag + "：关闭后是关着的")
	var cnt: int = get_tree().get_node_count()
	if pass_i == 0:
		base_nodes[tag] = cnt
	else:
		ok(cnt <= int(base_nodes.get(tag, cnt)) + 3, "%s：第二遍关闭后节点数 %d 超过第一遍 %d（每开一次泄漏节点？）" % [tag, cnt, int(base_nodes.get(tag, cnt))])


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	await title_part()
	await game_part()
	var names: Array = missing_all.keys()
	names.sort()
	if not names.is_empty():
		print("UI SMOKE 可选缺图（有回退，不算失败）/ 已计失败的缺图：", ", ".join(PackedStringArray(names)))
	print("%d checks, %d failed" % [n, fails])
	print("UI SMOKE failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func title_part() -> void:
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2.ZERO
	title.size = Vector2(1280, 720)
	await frames(4)
	var entries: Array = [
		["标题·选人", func(): title._open_op_pick(false), func(): return title.op_pick, func(): title.op_pick = false],
		["标题·难度", func(): title.diff_pick = true, func(): return title.diff_pick, func(): title.diff_pick = false],
		["标题·图鉴", func(): title.gallery.open(), func(): return title.gallery.visible, func(): title.gallery.close()],
		["标题·认知塑造", func(): title.meta_ui.open(), func(): return title.meta_ui.visible, func(): title.meta_ui.close()],
		["标题·蚀刻章", func(): title.medals_ui.open(), func(): return title.medals_ui.visible, func(): title.medals_ui.close()],
		["标题·设置", func(): title.settings.open(), func(): return title.settings.visible, func(): title.settings.close()],
		["标题·操作说明", func(): title.guide = true, func(): return title.guide, func(): title.guide = false],
		["标题·致谢", func(): title._open_credits(), func(): return title.credits, func(): title.credits = false],
	]
	if preload("res://scripts/core/roster.gd").active():
		entries.append(["标题·寻访", func(): title.hunt_ui.open(), func(): return title.hunt_ui.visible, func(): title.hunt_ui.hh.open = false])
	else:
		print("UI SMOKE 跳过：标题·寻访（带测试参数时 Roster 名册未启用，open_browse 直接返回 false）")
	if Cfg.can_boss_trial():
		entries.append(["标题·Boss 演练", func(): title.boss_trial.open(), func(): return title.boss_trial.visible, func(): title.boss_trial.close()])
	else:
		print("UI SMOKE 跳过：标题·Boss 演练（Cfg.can_boss_trial() 为假，本机存档未解锁）")
	for pass_i in 2:
		for e in entries:
			await screen(e[0], pass_i, e[1], e[2], e[3])
	title.queue_free()
	await frames(3)


func game_part() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
	await frames(3)
	var g = game
	g.headless_batch = false   # 无头批跑默认不画世界 / HUD；冒烟要真的走一遍绘制
	g.set_process(false)       # 状态手动摆，帧由本测试驱动 _process 以外的绘制
	var S = g.S
	var fake := RS.model(RS.fake_raw())
	var entries: Array = [
		["局内·HUD", func(): g.state = S.PLAY, func(): return g.state == S.PLAY, func(): g.state = S.PAUSE],
		["局内·暂停", func(): g.state = S.PAUSE, func(): return g.state == S.PAUSE, func(): g.state = S.PLAY],
		["局内·属性面板", func(): g.state = S.STATS, func(): return g.state == S.STATS, func(): g.state = S.PLAY],
		["局内·暂停里的设置", func(): g.state = S.PAUSE; g.settings.open(), func(): return g.settings.visible, func(): g.settings.close(); g.state = S.PLAY],
		["结算·胜利", func(): g.state = S.WIN; g.state_age = 3.0; g.settlement.set_model(fake), func(): return g.state == S.WIN, func(): g.state = S.PLAY],
		["结算·作战记录", func(): g.state = S.WIN; g.state_age = 3.0; g.run_stats.show_model(fake), func(): return g.run_stats.open, func(): g.run_stats.close(); g.state = S.PLAY],
		["结算·对局记录", func(): g.state = S.WIN; g.state_age = 3.0; g.run_log.open_log(), func(): return g.run_log.open, func(): g.run_log.close(); g.state = S.PLAY],
		["结算·失败", func(): g.state = S.DEAD; g.state_age = 3.0; g.settlement.set_model(fake), func(): return g.state == S.DEAD, func(): g.state = S.PLAY],
	]
	g.set_process(true)
	for pass_i in 2:
		for e in entries:
			await screen(e[0], pass_i, e[1], e[2], e[3])
	g.queue_free()
	await frames(2)
