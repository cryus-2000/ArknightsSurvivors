extends Node
## 时间缩放组合回归（docs/126 R6 / arch_review_1029 风险 5）：play_clock_test、feedback_test 只各测各的，这里在真游戏的 _process 上同时开多种缩放源，
## 量 g.t 每帧实际前进多少，断言它等于约定的组合规则，并且退出每个模态后回到 1：
##   godot --headless --path game res://tests/time_scale_combo_test.tscn -- --regression --balance --seed=1 --op=skadi --squad=kaltsit
## 现行规则（game._process，读代码得出；这是特征测试，规则改了要同步改这里）：
##   ① 模拟步长 dt = min(真实帧, 0.05) × 圆盘系数 wheel.slow()（圆盘开 = command/wheel_slow 0.2，否则 1）；
##   ② 然后三选一：最终 Boss 击破慢动作 victory.active → g.t += 真实帧 × victory.time_scale(real)，圆盘与倍速都不乘；
##      否则顿帧 hitstop>0（且设置开）→ 模拟整帧暂停，hitstop -= 真实帧；
##      否则 PlayClock.steps(dt)：真实帧先封顶 2/60，再 × 倍速（1× / 1.5×），拆成 ≤1/48 的小步。
##   没有「选点」减速这个缩放源（手动技能选落点不改时间），所以组合是 圆盘 × 倍速 / 顿帧 / 击破慢动作 三条互斥路径。
## 全部通过打印 "TIME SCALE COMBO failures=0"。
const PlayClock = preload("res://scripts/run/play_clock.gd")
const FR := 1.0 / 60.0
var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String) -> void:
	ok(absf(a - b) < 1e-6, "%s（实得 %.6f，应为 %.6f）" % [what, a, b])


## 推一帧真实时间，返回 g.t 前进量
func adv(delta := FR) -> float:
	var g = game
	var t0: float = g.t
	g._process(delta)
	return g.t - t0


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	var g = game
	g.set_process(false)
	g.realtime = true
	g.playclock_test = true   # 按玩家局的 PlayClock 分步（run_setup 里 --playclock --realtime 的效果）
	Cfg.hitstop = true
	var save_speed: float = Cfg.play_speed
	ok(g.state == g.S.PLAY, "起点在 PLAY（实际 %d）" % g.state)
	if g.state != g.S.PLAY:
		finish(save_speed)
		return
	g.hitstop = 0.0
	g.wheel.is_open = false
	Cfg.play_speed = 1.0
	near(adv(), FR, "基线：1× 无模态，一帧前进一帧")
	Cfg.play_speed = 1.5
	near(adv(), FR * 1.5, "倍速 1.5×")
	var ws: float = g.wheel.slow()
	near(ws, 1.0, "圆盘关时系数 1")
	g.wheel.is_open = true
	ws = g.wheel.slow()
	near(ws, 0.2, "圆盘开时系数 = command/wheel_slow（缺省 0.2）")
	near(adv(), FR * ws * 1.5, "圆盘 × 倍速：0.2 × 1.5 = 0.3")
	Cfg.play_speed = 1.0
	near(adv(), FR * ws, "圆盘 1×：0.2")
	# 封顶：很长的真实帧先封到 2/60 再乘倍速（圆盘在封顶前乘）
	g.wheel.is_open = false
	Cfg.play_speed = 1.5
	near(adv(0.05), PlayClock.MAX_STEPS / 60.0 * 1.5, "长帧：先封顶 2/60 再 × 1.5")
	g.wheel.is_open = true
	near(adv(0.05), minf(0.05 * ws, PlayClock.MAX_STEPS / 60.0) * 1.5, "长帧 + 圆盘：0.05 × 0.2 = 0.01 不到封顶，× 1.5")
	# 顿帧：模拟整帧暂停（圆盘、倍速都开着也一样），hitstop 按真实帧间隔递减
	g.hitstop = 0.05
	near(adv(), 0.0, "顿帧 + 圆盘 + 1.5×：模拟暂停")
	near(g.hitstop, 0.05 - FR, "顿帧按真实帧间隔递减（不乘圆盘 / 倍速）")
	g.hitstop = 0.0
	g.wheel.is_open = false
	near(adv(), FR * 1.5, "顿帧结束后（圆盘已关）回到 1.5×")
	# 设置里关掉顿帧：hitstop>0 也照常推进
	Cfg.hitstop = false
	g.hitstop = 0.05
	near(adv(), FR * 1.5, "设置关顿帧：hitstop>0 不暂停")
	Cfg.hitstop = true
	g.hitstop = 0.0
	# 最终 Boss 击破慢动作：圆盘与倍速都不乘，只看 victory.time_scale
	var v = g.victory
	v.active = true
	v.finale = true
	v.real = 0.0
	v.elapsed = 0.0
	g.wheel.is_open = true
	Cfg.play_speed = 1.5
	var tmid: float = (v.FIN_IN + v.FIN_DUR - v.FIN_OUT) * 0.5
	v.real = tmid
	var want: float = FR * v.time_scale(v.real + FR)
	near(adv(), want, "击破慢动作中（圆盘开 + 1.5×）：只乘 victory.time_scale = 0.15，圆盘与倍速不乘")
	ok(absf(v.time_scale(tmid) - v.FIN_SCALE) < 1e-6, "慢动作中段系数 = FIN_SCALE")
	# 退出各模态后全部回到 1
	v.active = false
	v.finale = false
	v.real = 0.0
	v.elapsed = 0.0
	g.wheel.is_open = false
	g.hitstop = 0.0
	Cfg.play_speed = 1.0
	near(adv(), FR, "退出圆盘 / 顿帧 / 慢动作 / 倍速后：回到 1")
	near(g.wheel.slow(), 1.0, "退出后圆盘系数 1")
	near(v.time_scale(0.0), 1.0, "非 finale 的 victory.time_scale 恒 1")
	finish(save_speed)


func finish(save_speed: float) -> void:
	Cfg.play_speed = save_speed
	print("%d checks, %d failed" % [n, fails])
	print("TIME SCALE COMBO failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
