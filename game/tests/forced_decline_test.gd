extends Node
## 强制招募画面可婉拒（用户 11-05「加上」，docs/252 第 5 条）：真人局 Lv.5 编队只有队长时弹强制招募，末尾多一项「婉拒」（招募卡下方的小按钮）；
## 选婉拒 → 这一次升级改为普通成长三选一（不再全是招募卡），这一档之后不再弹强制招募；数字键能走到婉拒（选项数 = 招募卡 + 1）
var game: Node
var frames := 0
var failures := 0


func check(v: bool, label: String) -> void:
	if not v:
		failures += 1
		print("FAIL ", label)


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _all_recruit() -> bool:
	return game.choices.all(func(o): return str(o.get("kind", "")) == "recruit")


func _process(_dt: float) -> void:
	frames += 1
	if frames == 5:
		game.pending_levelups = 0
		game.pending_chests = 0
		game.show_queue.clear()
		game.state = game.S.PLAY
		game.level = 5
		check(game.squad.size() == 1, "solo squad at start (%d)" % game.squad.size())
		check(not game.progression.offer_auto(), "real-player run (decline offered only here)")
		game.progression.open_levelup()
		var n: int = game.choices.size()
		check(n >= 2 and str(game.choices[n - 1].get("kind", "")) == "recruit_decline", "forced recruit panel ends with 婉拒 (%s)" % [game.choices.map(func(o): return o.get("kind", ""))])
		check(game.choices.slice(0, n - 1).all(func(o): return str(o.get("kind", "")) == "recruit"), "the other options are recruit cards")
		check(game.panel_ui.decline_btn.visible and int(game.panel_ui.decline_btn.get_meta("i", -1)) == n - 1, "decline button shown and wired to the last option")
		game.progression.pick(n - 1)
		check(game.state == game.S.CHOICE and not _all_recruit(), "declining opens an ordinary growth choice")
		check(not game.panel_ui.decline_btn.visible, "no decline button on the ordinary choice")
		check(game.progression.forced_declined == 1, "Lv.5 tier marked declined (%d)" % game.progression.forced_declined)
		game.panel.visible = false
		game.state = game.S.PLAY
		game.level = 6
		game.progression.open_levelup()
		check(not (game.choices.size() > 0 and _all_recruit() and game.panel_ui.decline_btn.visible), "declined tier does not force recruit again at Lv.6")
		print("FORCED DECLINE failures=%d" % failures)
		get_tree().quit(1 if failures else 0)
