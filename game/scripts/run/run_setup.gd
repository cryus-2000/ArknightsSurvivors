extends RefCounted
## 开局设置（docs/126 C1，10-22 由 game.gd _ready 原样搬出）：难度预设 / 批跑难度参数、批跑与测试的命令行参数。
## game._ready 在原来的位置按原顺序调这两个函数（apply_difficulty 在属性初始化之前，apply_test_args 在 trial.setup 之前），
## 读写的仍是 game 的成员（g.preset / g.dmod / g.bot / g.bal_maxt …）；不抽随机数，同 seed 不变。

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Squad = preload("res://scripts/characters/squad.gd")


## 难度：标题页选的三档预设；批跑 --diff=（旧累计 0–10）/ --tier=（旧三档）/ --tide=（潮位）覆盖。随后按修正表改受击灯火损失与最大生命
static func apply_difficulty(g) -> void:
	g.preset = clampi(Cfg.difficulty, 0, D.DIFF_PRESETS.size() - 1)
	g.tier = int(D.DIFF_PRESETS[g.preset].tide)
	g.diff = g.tier
	g.dmod = D.dmod_for_preset(g.preset)   # 潮位表 + 该档的 enemy_scale（深潮档微降，docs/109 §15）
	for a in Cfg.dev_args():
		if a.begins_with("--diff="):
			# 批跑：旧累计难度 0–10 拼修正表（与旧数据对得上）
			g.diff = int(a.substr(7))
			g.preset = -1
			g.tier = D.tier_of_level(g.diff)
			g.dmod = D.dmod_for_level(g.diff)
		elif a.begins_with("--tier="):
			# 批跑旧三档：修正表与改动前逐局相同（潮位 8 比旧 Ⅷ 多寒流两键，所以 --tier=2 不走潮位表）
			var lt := clampi(int(a.substr(7)), 0, D.LEGACY_TIERS.size() - 1)
			g.preset = -1
			g.tier = int(D.LEGACY_TIERS[lt].level)
			g.diff = g.tier
			g.dmod = D.dmod_for_legacy(lt)
		elif a.begins_with("--tide="):
			g.preset = -1
			g.tier = clampi(int(a.substr(7)), 0, D.DIFFICULTY_TIERS.size() - 1)
			g.diff = g.tier
			g.dmod = D.dmod_for_tide(g.tier)   # 潮位正好是三档预设之一时带上该档的 enemy_scale（校准批跑与正式档同一张表）
	if float(g.dmod.lamp_hit) != 1.0:
		g.stats.add(&"light_decay", "mult", float(g.dmod.lamp_hit), "difficulty")   # 受击灯火损失（g.lamp_decay 只用于受击，combat.gd lose_hp）
	if float(g.dmod.max_hp) != 1.0:
		g.stats.add(&"max_hp", "mult", float(g.dmod.max_hp), "difficulty")


## 批跑 / 测试的命令行参数（都只在 debug 构建或测试参数下生效，Cfg.dev_args）：--balance 的机器人、截图、步长 / 计时 / TRACE、
## 提前 Boss、开局编入干员、直接推进成长节点
static func apply_test_args(g) -> void:
	if g.mode == g.Mode.BALANCE:
		var bot_p := "normal"
		var bot_seed := 0
		for a in Cfg.dev_args():
			if a.begins_with("--bot="):
				bot_p = a.substr(6)
			elif a.begins_with("--seed="):
				bot_seed = int(a.substr(7))
		g.bot = Bot.new(g, bot_p, bot_seed)
		if Bal.v("command/bot_roam", 0.0) > 0.0 and Squad.cmd_on():
			g.squad.set_stance(g.squad.ROAM)   # 之后耐力耗尽归队、回到 min_start 再突击（squad._tick_stamina）   # 指挥模式对照（docs/114）：机器人局常开突击；缺省 0 = 随行，同 seed 不变
	for arg in Cfg.dev_args():
		if arg.begins_with("--shotdir="):
			g.shot_dir = arg.substr(10)
		if arg.begins_with("--shots="):
			g.shot_at = []
			for v in arg.substr(8).split(","):
				g.shot_at.append(int(v))
	if g.mode == g.Mode.BALANCE:
		g.playclock_test = Cfg.dev_args().has("--playclock") and Cfg.dev_args().has("--realtime")
		if not g.playclock_test:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
		for a in Cfg.dev_args():
			if a.begins_with("--maxfps=") and g.playclock_test:
				Engine.max_fps = int(a.substr(9))   # docs/139 帧间隔实测：同玩家设置「最高帧率」（垂直同步开着时的 60 帧上限）
			if a.begins_with("--maxt="):
				g.bal_maxt = float(a.substr(7))
		g.prof_on = Cfg.dev_args().has("--prof")
		for a in Cfg.dev_args():
			if a.begins_with("--dt="):
				g.bal_dt = clampf(float(a.substr(5)), 0.004, 0.1)
		g.realtime = Cfg.dev_args().has("--realtime")
		for a in Cfg.dev_args():
			if a.begins_with("--rtfrom=") and g.realtime:
				g.rt_from = float(a.substr(9))
				g.realtime = false
		g.headless_batch = DisplayServer.get_name() == "headless" and not Cfg.dev_args().has("--drawtest")
		for a in Cfg.dev_args():
			if a.begins_with("--trace="):
				g.trace_every = float(a.substr(8))
			# --bosstimes=30,60,90：冒烟测试把 Boss 提前（中期 Boss × 2 + 最终 Boss），一局两分钟内跑完所有 Boss 代码
			if a.begins_with("--bosstimes="):
				D.BOSS_TIMES = Array(a.substr(12).split(",")).map(func(x): return float(x))
		OS.low_processor_usage_mode = false
		OS.low_processor_usage_mode_sleep_usec = 0
	for a in Cfg.dev_args():
		if a.begins_with("--forceboss="):
			g.force_boss = int(a.substr(12))
		# 测试：开局直接编入干员（逗号分隔 id，跟在开局干员之后）
		if a.begins_with("--squad="):
			for cid in a.substr(8).split(","):
				if g.squad.add(cid) != null:
					g.panel_ui.load_op_tex(cid)
	# 测试：全队直接推进 N 个成长节点（看精英化后的技能 / 特效）
	for a in Cfg.dev_args():
		if a.begins_with("--prog="):
			for o in g.squad.ops:
				for k in int(a.substr(7)):
					o.advance()
