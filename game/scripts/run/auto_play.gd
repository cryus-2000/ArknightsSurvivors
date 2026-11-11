extends RefCounted
## 无敌测试包自动模式（11-11 用户：「测试性能的时候能不能加一个自动模式，我只要看会不会崩」）。
## 网址 auto=1（只在 Cfg.test_god 的网页包生效；调试版另认 --autoplay）：开局后机器人自己玩到结算；loop=1（或 --autoloop）结算后自动再来一局。
## 不走 --balance：对局仍是 Mode.PLAY，g.bot 保持 null——同屏上限 / 掉帧档 / 内存护栏 / 性能报告 / 闪退记录 / 画质自动档 / 实时帧率全照真人局。
## 机器人（core/bot.gd，expert 档）只私下用来出移动方向和选卡，由 game.gd 移动输入链调 move()；本脚本另处理选卡 / 事件 / 商人 / 精英化演出 / 结算重开。
## 终结技 / 连携按 ult.gd 的自动档放（_auto_ult / auto_combo 认 g.auto_play）。不抽对局随机数（选卡打分用 bot 自己的 rng）。
var g
var bot = null
var want_dash := false   # bot.gd 鸭爵追击时置位，game.gd 记下移动方向后冲刺
var _wait := 0.0         # 当前这个界面已经停了多久（真实秒）：选卡 / 商人像真人一样先看一会儿
var _shop_n := 0
var _end_t := 0.0        # 结算界面停了多久
var _looped := false
const PICK_WAIT := 1.2
const END_WAIT := 8.0    # 结算停 8 秒（性能报告在局终已经写好）再自动开下一局


static func wanted(game) -> bool:
	return Cfg.test_auto() and game.mode == game.Mode.PLAY and game.demo_op == "" and not game.trial.active


func _init(game) -> void:
	g = game
	if ResourceLoader.exists("res://scripts/core/bot.gd"):
		bot = load("res://scripts/core/bot.gd").new(g, "expert", 0)   # 发行包不带 bot.gd（release_slim DEV_SCRIPTS）；无敌包导出时保留（export_web.py --god）
	print("PF AUTOPLAY on loop=%s bot=%s" % [str(Cfg.test_loop()), str(bot != null)])


## 移动方向（game.gd 移动输入链；state == PLAY 时调）
func move(dt: float) -> Vector2:
	if bot == null:
		return Vector2.ZERO
	return bot.move(dt)


## 每帧（game._process，真实时间）
var _log_t := 0.0
func step(delta: float) -> void:
	var rd: float = delta / maxf(0.01, Engine.time_scale)
	var S = g.S
	_log_t += rd
	if _log_t >= 10.0:
		_log_t = 0.0
		print("PF AUTOPLAY st=%d kind=%s t=%.0f age=%.1f modal=%s" % [g.state, str(g.choice_kind), g.t, g.state_age, str(g.onboard.modal())])
	match g.state:
		S.CHOICE:
			_wait += rd
			if _wait >= PICK_WAIT:
				if g.choice_kind == "cross" and g.endg.flipped >= 0:
					return   # 翻面中，等计时器兑现
				_wait = 0.0
				g.progression.pick(_pick())
		S.SHOP:
			_wait += rd
			if _wait >= PICK_WAIT:
				_wait = 0.0
				_shop_n += 1
				var li: int = bot.shop_pick() if bot != null else -1
				if li >= 0:
					g.shop_sys.buy(li)
				else:
					for i in g.shop_items.size():
						if g.shop_sys.can_buy(g.shop_items[i]):
							g.shop_sys.buy(i)
							break
				if _shop_n % 3 == 0:
					g.shop_sys.close()
		S.SHOW:
			if g.show_t > 1.6:
				g.show_screen.close()
		S.INTRO:
			_wait += rd
			if _wait >= 2.0 and not g.onboard.modal():
				_wait = 0.0
				g.intro_screen.close()
		S.DEAD, S.WIN:
			_end_t += rd
			if Cfg.test_loop() and not _looped and _end_t >= END_WAIT and not g.victory.active:
				_looped = true
				print("PF AUTOPLAY restart t=%.0f" % g.t)
				g._do_action("restart")   # 手机网页整页重载后直接同队出发（core/run_reload.gd）
		_:
			_wait = 0.0


## 选卡：同 autotest.bot_pick 的分流（事件 / 翻节点按路线、更换队友 / 培养路线固定选法、其余 expert 打分）
func _pick() -> int:
	var k: String = g.choice_kind
	if k == "cross" or k == "event":
		return g.endg.bot_choice()
	if k == "swap":
		return g.progression.auto_swap_pick()
	if k == "branch":
		return g.progression.auto_branch_pick()
	var idx: Array = g.progression.auto_choices()
	if idx.is_empty():
		return 0
	if bot != null:
		var keep: Array = g.choices
		g.choices = idx.map(func(i): return keep[i])
		var sub: int = bot.pick(g.choices)
		g.choices = keep
		if sub >= 0:
			return int(idx[clampi(sub, 0, idx.size() - 1)])
	return int(idx[0])
