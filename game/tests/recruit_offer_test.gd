extends Node
## 入队邀请二选一的回归（docs/247，用户 11-05：自动招募改成「接受入队 / 婉拒」）：
##   godot --headless --path game res://tests/recruit_offer_test.tscn -- --regression --balance --seed=1 --op=eyjafjalla
##   （再加 --touch 跑触屏排版；加 --bot_solo=1 查单人局机器人一律婉拒）
## 第 5 帧起：
##   ① 机器人局（--balance）铜印 / 银印 / 事件同一帧自动结算：缺省接受（入队、档位对），--bot_solo=1 婉拒（不入队、成长三选一 +1、银印全队 +1 节点）
##   ② 玩家局的二选一面板（open_offer）：两张卡、接受卡是干员卡（头像 = recruit）、第一行写档位，婉拒卡写替代成长；
##      键盘数字键 / 方向键 + 回车（手柄由 Pad 翻成同样的键）/ 触屏点卡都能选；接受 / 婉拒结果对；不占升级次数
##   ③ 编队已满：铜印 / 事件直接改为一次成长三选一、银印全队推进，不弹二选一
## 全部通过打印 "RECRUIT OFFER failures=0"。

const Character = preload("res://scripts/characters/character.gd")
var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	var P = game.progression
	ok(P.offer_auto(), "--balance 局自动结算邀请")
	if P.solo_bot():
		test_bot_solo()
	else:
		test_bot_accept()
		test_panel()
		test_full()
	print("%d checks, %d failed" % [n, fails])
	print("RECRUIT OFFER failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func _free_ids(k: int) -> Array:
	return game.progression.recruit_cards().slice(0, k).map(func(c): return str(c.id))


func _reset_squad() -> void:
	for o in game.squad.ops.duplicate():
		if not o.is_leader:
			game.squad.remove(o.id)
	game.pending_levelups = 0
	game.show_queue.clear()   # 精英化演出排在升级前面（check_pending），各段互不影响
	game.state = game.S.PLAY
	game.panel.visible = false


## ① 缺省：铜印 / 银印 / 事件都直接入队，档位同改前
func test_bot_accept() -> void:
	_reset_squad()
	var P = game.progression
	var r0: int = game.rng.state
	game.rfx._recruit_one()
	ok(game.squad.size() == 2, "铜印：机器人接受入队（编队 %d）" % game.squad.size())
	ok(game.squad.ops[1].prog == 1, "铜印：入队推进 1 个节点（%d）" % game.squad.ops[1].prog)
	ok(game.state == game.S.PLAY and game.pending_levelups == 0, "铜印：同一帧结算，不弹面板、不加升级")
	ok(game.rng.state != r0, "铜印：抽人照旧用 g.rng")
	game.rfx._silver_seal()
	ok(game.squad.size() == 3 and game.squad.ops[2].elite >= 1, "银印：机器人接受，以精英一入队")
	_reset_squad()
	game.endg._recruit()
	ok(game.squad.size() == 2 and game.squad.ops[1].prog == 0, "事件：机器人接受，精英零入队")
	ok(P.offer_log.size() == 3 and P.offer_log.all(func(x): return x[3] == "accept"), "遥测记 3 次接受 %s" % [P.offer_log])


## --bot_solo=1：一律婉拒；升级 / 强制招募不出招募卡
func test_bot_solo() -> void:
	_reset_squad()
	var lead_prog: int = game.ch.prog
	game.rfx._recruit_one()
	ok(game.squad.size() == 1 and game.pending_levelups == 1, "单人机器人：铜印婉拒 → 成长三选一 +1")
	game.pending_levelups = 0
	game.rfx._silver_seal()
	ok(game.squad.size() == 1 and game.pending_levelups == 1 and game.ch.prog == lead_prog + 1, "单人机器人：银印婉拒 → 队长推进 1 节点 + 成长三选一")
	game.pending_levelups = 0
	game.endg._recruit()
	ok(game.squad.size() == 1 and game.pending_levelups == 1, "单人机器人：事件婉拒 → 成长三选一 +1")
	game.level = 6
	ok(not game.guide.must_recruit(game.progression.recruit_cards()), "单人机器人：Lv.6 只有 1 人也不进强制招募画面")
	game.choices = [{"kind": "recruit", "id": "skadi", "name": "x"}, {"kind": "filler", "id": "atk", "name": "y"}]
	ok(game.progression.auto_choices() == [1], "单人机器人：升级卡不选招募卡")


func _open(src: String) -> String:
	var cid: String = _free_ids(1)[0]
	game.progression.open_offer({"src": src, "id": cid})
	return cid


## ② 玩家局的二选一面板
func test_panel() -> void:
	_reset_squad()
	var P = game.progression
	var cid := _open("copper")
	ok(game.state == game.S.CHOICE and game.choice_kind == "offer", "铜印：弹出二选一并暂停")
	ok(game.choices.size() == 2, "两张卡")
	var acc: Dictionary = game.choices[0]
	ok(acc.kind == "recruit" and acc.get("offer", false) and str(acc.id) == cid, "接受卡是这名干员的招募卡（画头像）")
	ok(str(acc.desc).begins_with("以精英零加入\n成长节点 1/"), "铜印接受卡写档位：%s" % str(acc.desc).substr(0, 30))
	ok(str(acc.cat).begins_with("接受入队"), "接受卡标签「接受入队」")
	ok(game.choices[1].kind == "offer_decline" and game.choices[1].name == "婉拒" and str(game.choices[1].desc) == "改为一次成长三选一", "婉拒卡")
	ok(game.panel_box.get_child_count() == 2, "面板建了两张卡（%d）" % game.panel_box.get_child_count())
	ok(game.panel_ui.option_description(acc).begins_with("以精英零"), "卡面说明第一行是档位")
	# 键盘数字键 2 = 婉拒
	var ev := InputEventKey.new()
	ev.keycode = KEY_2
	ev.physical_keycode = KEY_2
	ev.pressed = true
	game._unhandled_input(ev)
	ok(not game.squad.has(cid), "数字键 2 婉拒：不入队")
	ok(game.pending_levelups == 1, "婉拒：成长三选一 +1（%d）" % game.pending_levelups)
	ok(game.state == game.S.CHOICE and game.choice_kind == "level", "婉拒后接着弹成长三选一（%s 状态 %d 延迟 %.2f）" % [game.choice_kind, game.state, game.lvup_delay])
	ok(P.offer_log[-1][3] == "decline", "遥测记婉拒")
	_reset_squad()
	# 方向键 / 回车（手柄同一路径）：右移再左移回到接受卡
	cid = _open("silver")
	ok(str(game.choices[0].desc).begins_with("以精英一加入"), "银印接受卡写「以精英一加入」")
	ok(str(game.choices[1].desc).contains("全队各推进 1 个成长节点") and str(game.choices[1].desc).contains("成长三选一"), "银印婉拒卡写全队推进 + 成长三选一")
	game._nav_key(KEY_RIGHT)
	game._nav_key(KEY_LEFT)
	game._nav_key(KEY_ENTER)
	ok(game.squad.has(cid) and game.squad.get_op(cid).elite >= 1, "回车接受银印：以精英一入队")
	ok(game.pending_levelups == 0 and game.state != game.S.CHOICE, "接受：不占升级次数、关面板（精英化演出照常排队（升级 %d 状态 %d 面板 %s）" % [game.pending_levelups, game.state, game.choice_kind])
	_reset_squad()
	# 银印婉拒：全队推进 + 成长三选一
	var p0: int = game.ch.prog
	cid = _open("silver")
	game.progression.pick(1)
	ok(not game.squad.has(cid) and game.ch.prog == p0 + 1 and game.pending_levelups == 1, "银印婉拒：队长 +1 节点、成长三选一 +1")
	_reset_squad()
	# 触屏 / 鼠标：点卡（Button.pressed）
	cid = _open("event")
	ok(str(game.choices[0].desc).begins_with("以精英零加入\n") and not str(game.choices[0].desc).contains("成长节点"), "事件接受卡写「以精英零加入」")
	var b0: Button = game.panel_box.get_child(0)
	ok(b0.size.x > 100.0 or b0.custom_minimum_size.x > 100.0, "接受卡有可点区域（%s）" % b0.custom_minimum_size)
	b0.pressed.emit()
	if game.state == game.S.CHOICE and game.choice_kind == "offer":
		b0.pressed.emit()   # 手机卡带「详情」时第一次点可能只开详情：点卡身仍是选择（_phone_press）
	ok(game.squad.has(cid), "点接受卡：入队")
	_reset_squad()
	# 排队：玩家局（offer_auto 为假）排进队列，check_pending 时才弹；排队期间编队满 → 按满员处理
	var m0 = game.mode
	game.mode = game.Mode.PLAY
	var bot0 = game.bot
	game.bot = null
	ok(not P.offer_auto(), "玩家局：不自动结算")
	game.rfx._recruit_one()
	ok(game.squad.size() == 1 and P.offer_queue.size() == 1, "玩家局铜印：先排队，不直接入队")
	game.check_pending()
	ok(game.state == game.S.CHOICE and game.choice_kind == "offer", "check_pending 弹出二选一")
	game.progression.pick(0)
	ok(game.squad.size() == 2 and game.squad.ops[1].prog == 1, "玩家局接受铜印：入队并推进 1 节点")
	game.mode = m0
	game.bot = bot0


## ③ 编队已满：不弹二选一
func test_full() -> void:
	_reset_squad()
	for cid in _free_ids(2):
		game.squad.add(cid)
	ok(game.squad.is_full(), "编队已满（%d）" % game.squad.size())
	var P = game.progression
	var q0: int = P.offer_log.size()
	game.rfx._recruit_one()
	ok(game.pending_levelups == 1 and game.state == game.S.PLAY, "满员铜印：成长三选一，不弹二选一")
	game.pending_levelups = 0
	game.endg._recruit()
	ok(game.pending_levelups == 1, "满员事件：成长三选一")
	var pr: Array = game.squad.ops.map(func(o): return o.prog)
	game.rfx._silver_seal()
	ok(game.squad.ops.map(func(o): return o.prog) != pr, "满员银印：全队推进")
	ok(P.offer_log.size() == q0, "满员不记邀请")
