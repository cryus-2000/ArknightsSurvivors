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
var _stuck := 0.0        # 同一选择界面已经尝试选了多久
const PICK_WAIT := 1.2
const END_WAIT := 8.0
const SUITE_TIMEOUT := 1500.0   # 连测：局内 25 分钟还没打完最终 Boss 就按「中途退出」记下、开下一局（不让一局卡死整轮）
const GodSuite = preload("res://scripts/core/god_suite.gd")
var _summary := false    # 结算停 8 秒（性能报告在局终已经写好）再自动开下一局


static func wanted(game) -> bool:
	return Cfg.test_auto() and game.mode == game.Mode.PLAY and game.demo_op == "" and not game.trial.active


func _init(game) -> void:
	g = game
	if ResourceLoader.exists("res://scripts/core/bot.gd"):
		bot = load("res://scripts/core/bot.gd").new(g, "expert", 0)   # 发行包不带 bot.gd（release_slim DEV_SCRIPTS）；无敌包导出时保留（export_web.py --god）
	print("PF AUTOPLAY on loop=%s bot=%s suite=%s" % [str(Cfg.test_loop()), str(bot != null), str(Cfg.test_suite())])
	if Cfg.test_suite():
		GodSuite.close_panel()   # 闪退后标题页弹过的进度面板
		GodSuite.start_run(g)    # 记「进行中」：没走到结算就是闪退（core/god_suite.gd）


## 连测超时（局内秒）；调试版 --suitetimeout=<秒> 改短，测超时 / 重开路径用
var _tmo := -1.0
func _timeout() -> float:
	if _tmo < 0.0:
		_tmo = SUITE_TIMEOUT
		for a in Cfg.dev_args():
			if a.begins_with("--suitetimeout="):
				_tmo = float(a.substr(15))
	return _tmo


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
		print("PF AUTOPLAY st=%d kind=%s n=%d t=%.0f age=%.1f modal=%s sq=%d lv=%d" % [g.state, str(g.choice_kind), g.choices.size(), g.t, g.state_age, str(g.onboard.modal()), g.squad.size(), g.level])
	if Cfg.test_suite() and not _looped and g.t >= _timeout() and g.state != S.DEAD and g.state != S.WIN:
		_looped = true
		print("PF AUTOPLAY suite timeout t=%.0f -> restart" % g.t)
		g._do_action.call_deferred("restart")   # 推迟到帧末：同帧后面的 settlement.tick 还要用视口（直接重开会报 !is_inside_tree）；离场照常走 game._exit_tree → perf_report.finish("quit") → GodSuite.run_done
		return
	match g.state:
		S.CHOICE:
			_wait += rd
			if _wait >= PICK_WAIT:
				if g.choice_kind == "cross" and g.endg.flipped >= 0:
					return   # 翻面中，等计时器兑现
				_wait = 0.0
				_stuck += PICK_WAIT
				if _stuck >= 15.0 and g.choices.is_empty():
					# 兜底（只自动模式）：候选为空的选择界面（11-11 网页仿真 7:30 藏品宝箱卡住 300 秒）不会被 pick 关掉——按「这次宝箱 / 升级作废」关面板回战斗
					print("PF AUTOPLAY stuck kind=%s t=%.0f -> close" % [str(g.choice_kind), g.t])
					if g.choice_kind == "relic":
						g.pending_chests = maxi(0, g.pending_chests - 1)
						if not g.chest_src.is_empty():
							g.chest_src.pop_front()
					elif g.choice_kind != "event":
						g.pending_levelups = maxi(0, g.pending_levelups - 1)
					g.panel.visible = false
					g.state = S.PLAY
					_stuck = 0.0
					return
				var pi: int = _pick()
				if pi >= 0 and pi < g.choices.size():
					print("PF AUTOPLAY pick kind=%s -> %s %s (of %s)" % [str(g.choice_kind), str(g.choices[pi].get("kind", "")), str(g.choices[pi].get("id", g.choices[pi].get("name", ""))), ",".join(g.choices.map(func(c): return str(c.get("kind", ""))))])
				g.progression.pick(pi)
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
				var any := false
				for it in g.shop_items:
					if g.shop_sys.can_buy(it):
						any = true
						break
				if _shop_n % 3 == 0 or not any:
					# 买不起了就走，并记下这个商人逛过（bot.gd 不再朝它走；11-11 用户：没钱也反复进商店）
					if not g.merchant.is_empty():
						g.merchant.auto_done = true
					print("PF AUTOPLAY shop close t=%.0f ingots=%d any=%s" % [g.t, g.ingots, str(any)])
					_shop_n = 0
					g.shop_sys.close()
		S.SHOW:
			if g.show_t > 1.6:
				g.show_screen.close()
		S.INTRO:
			_wait += rd
			if _wait >= 2.0 and not g.onboard.modal():
				_wait = 0.0
				g.intro_screen.close()
		S.PAUSE:
			# 失焦自动暂停（web_focus：来通知 / 切后台 / 测量窗口在屏幕外）后 3 秒自己继续：自动模式本来就没人按（11-11 网页仿真两局停在暂停里）
			# 只续「失焦引起」的暂停（web_focus.paused）；玩家自己按的暂停不动——要在暂停菜单里看 / 复制性能报告（11-11 用户：自动模式一直自己继续，导不出数据）
			if not g.web_focus.paused:
				_wait = 0.0
				return
			_wait += rd
			if _wait >= 3.0:
				_wait = 0.0
				print("PF AUTOPLAY resume t=%.0f" % g.t)
				g._do_action("resume")
		S.DEAD, S.WIN:
			_end_t += rd
			if Cfg.test_suite() and GodSuite.done() and not _summary and _end_t >= END_WAIT and not g.victory.active:
				_summary = true
				_looped = true
				print("PF AUTOPLAY suite finished")
				GodSuite.show_summary()   # 四局轮完：停在汇总页（网页 DOM 面板：复制全部 / 保存 / 重新连测）
			if Cfg.test_loop() and not _looped and _end_t >= END_WAIT and not g.victory.active:
				_looped = true
				print("PF AUTOPLAY restart t=%.0f" % g.t)
				g._do_action.call_deferred("restart")   # 推迟到帧末（同上）；手机网页整页重载后直接同队出发（core/run_reload.gd）
		_:
			_wait = 0.0
	if g.state != S.CHOICE:
		_stuck = 0.0


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
	# 11-11 用户：自动模式要多招队友（压力测试要满编队的特效 / 内存）——没满员时有招募卡就先招
	if not g.squad.is_full():
		for i in idx:
			if str(g.choices[i].get("kind", "")) == "recruit":
				return int(i)
	if bot != null:
		var keep: Array = g.choices
		g.choices = idx.map(func(i): return keep[i])
		var sub: int = bot.pick(g.choices)
		g.choices = keep
		if sub >= 0:
			return int(idx[clampi(sub, 0, idx.size() - 1)])
	return int(idx[0])
