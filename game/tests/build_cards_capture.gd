extends Node
## 构筑可读性截图（docs/119 §4.3 / §4.4 / §4.5 验收用，不进快检）：招募卡、换人卡、藏品卡、商人预告各存一张 PNG。
##   桌面：godot --path game --resolution 1280x720 res://tests/build_cards_capture.tscn -- --balance --seed=1 --op=angelina --squad=skadi --shot_dir=<目录>
##   手机：同上加 --touch --resolution 1170x540（手机横屏版式 Cfg.phone_ui：触屏 + 比例 ≥ 1.9）
## 有窗口（截图要画面），用 tools/godot_runner 起（窗口放副屏 / 屏幕外、静音）。

var game: Node
var frames := 0
var step := 0
var dir := "res://../build/build_cards_shots"
var wait := 0
var tag := "desktop"
var hot := -1   # --hot=N：招募卡截图时键盘焦点停在第 N 张（看悬停提示，10-23 联动标签）
var recruit_ids: Array = ["wisadel", "exusiai", "irene"]   # --recruit=a,b,c 换招募卡三人（10-23 招募卡大小统一验收：ulpianus,skadi,mizuki）


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot_dir="):
			dir = a.substr(11)
		if a.begins_with("--hot="):
			hot = int(a.substr(6))
		if a.begins_with("--recruit="):
			recruit_ids = a.substr(10).split(",")
		if a == "--touch":
			tag = "phone"
	DirAccess.make_dir_recursive_absolute(dir)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir + "/%s_%s.png" % [tag, name])
	print("SHOT ", name)


func _process(_d: float) -> void:
	frames += 1
	if frames < 10:
		return
	# 对局停住（set_process(false)）后自己催重画：卡片 / 面板前景 / HUD
	for c in game.panel_box.get_children():
		c.queue_redraw()
	game.panel_fg.queue_redraw()
	game.hud.queue_redraw()
	game.panel_ui.animate_cards(1.0 / 60.0)   # 入场动效（卡片 modulate）由 game._process 推进，停住后自己推
	if wait > 0:
		wait -= 1
		return
	var g = game
	var pg = g.progression
	match step:
		10:
			shot("1_recruit_hot")
			g.kb_nav = false
			step = 1
			hot = -1
			return
		0:
			g.set_process(false)   # 停住对局：卡片与 HUD 仍会画
			g.ingots = 9
			pg.gain_relic("97")
			pg.gain_relic("130")
			var opts: Array = []
			for c in pg.recruit_cards():
				if recruit_ids.has(str(c.id)):
					opts.append(c)
			g.panel_ui.show_choices("招募干员", opts, "level")
			g.panel_ui.motion.skip()
			wait = 30
		1:
			shot("1_recruit")
			if hot >= 0 and step == 1:
				g.kb_nav = true
				g.nav_sel = hot
				g.panel_tip.queue_redraw()
				step = 10
				wait = 10
				return
			g.panel.visible = false
			g.state = g.S.PLAY
			g.squad.add("kaltsit")
			var card := {}
			for c in pg.swap_cards():
				if str(c.id) == "wisadel":
					card = c
			g.choices = []
			g.choice_kind = "level"
			g.panel_title_text = ""
			pg.open_swap(card, 0)
			g.panel_ui.motion.skip()
			wait = 30
		2:
			shot("2_swap")
			g.panel.visible = false
			pg.swap_ctx = {}
			var pool: Array = []
			for rid in ["95", "171", "234"]:
				var r: Dictionary = g.RL[rid]
				pool.append({"kind": "relic", "id": rid, "name": "【%s】%s" % [r.cat, g.rfx.display_name(rid)], "desc": g.rfx.display_desc(rid)})
			g.panel_ui.show_choices("获得藏品", pool, "relic")
			g.panel_ui.motion.skip()
			wait = 30
		3:
			shot("3_relic")
			g.panel.visible = false
			g.state = g.S.PLAY
			# 第一位商人：生成时定货架 + 预告（在画面内，头顶指示下方一行）
			g.merchant_idx = 1
			g.merchant = {"pos": g.ppos + Vector2(230, -40), "life": 52.0, "near": false, "purchases": 0}
			g.shop_items.clear()
			g.shop_refreshed = false
			g.shop_sys.prepare_first()
			g.hud.queue_redraw()
			wait = 30
		4:
			shot("4_merchant")
			g.merchant.pos = g.ppos + Vector2(1400, 300)   # 屏外：边缘圆圈 + 预告
			g.hud.queue_redraw()
			wait = 30
		5:
			shot("5_merchant_far")
			g.state = g.S.PLAY
			g.shop_sys.open()
			g.panel_ui.motion.skip()
			wait = 30
		6:
			shot("6_shop")
			get_tree().quit(0)
	step += 1
