extends RefCounted
## 自动测试 / 平衡机器人（docs/29、docs/36）：--autotest / --balance 的逐帧驱动、截图开关、机器人走位与选卡。
## 只在带测试参数启动时运行；正常游戏不经过这里。2026-09-26 从 game.gd 拆出。

const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const D = preload("res://scripts/data.gd")
const UM = preload("res://scripts/ui_motion.gd")
const MotionShot = preload("res://scripts/run/motion_shot.gd")   # --motionshot / --motionrec / --motionperf / --motionpress（docs/62）
var g: Game
var mshot: MotionShot
var winshot := false
const KILL_TYPES := ["bone", "stone", "offspring", "runner", "floater", "reaper", "spitter", "tracer"]   # --killshot 一行 8 只
const KILL_SHOTS := [-1, 3, 8, 14, 22]   # --killshot 截图帧（相对击杀那一帧；-1 = 击杀前一帧）
var _kill_row: Array = []
var hunt_rec_end := 0  # --huntrec：进寻访结果后又录了几张
var touchtest_p0 := Vector2.ZERO
var bal_done := false
var _lampat_done := false   # --lampat 只生效一次
var zone_out_since := -1.0   # 普通机器人：本次出圈的开始时间（-1 = 在圈内）
var want_dash := false       # 普通机器人：这一帧要冲刺（出圈回圈用；game.gd 在记下移动方向后执行）
var shop_visits := 0
var lv_marks := {}
var bosstest := false
var bossintro_kill_at := -1   # --bossintro：登场演完后击杀 Boss 的帧号（之后 90 帧退出）
# --bossmoves=<type>[2][+<搭档>]（docs/95 §12 验收开关）：在主控旁刷出该 Boss（后缀 2 = 二阶段；+搭档 = 接潮组另一具，停在左上不出招），按 bosses/<type>.gd demo_moves 的顺序
# 逐招 force_move，预警进度 60% 截 shot_bossmove_<type>_<招>.png、结算后 8 帧截 _hit.png；全部放完退出
var bm_boss: Dictionary = {}
var ba_boss: Dictionary = {}   # --bossacts（docs/142b §9 逐幕演示 gif）：演示中的 Boss / 搭档 / 下一次过卡点的时刻
var ba_mate: Dictionary = {}
var ba_next := 0.0
var ba_ft := {"a": [], "b": []}   # --bossacts --perfab：每帧用时（微秒），a = 新画法、b = g.perf_alt 旧画法
var ba_us := 0
var bm_mate: Dictionary = {}   # --bossmoves=<type>[2]+<搭档>：接潮组的搭档（停在主控左上、不出招、不死，供「统一」等两体招式验收）
var bm_list: Array = []
var bm_i := 0
var bm_state := "idle"
var bm_shot := false
var bm_hit_at := 0
var bm_next_t := 0.0
var bm_tag := ""
var choice_wait := 0
var choice_shot := false
var choice_n := 0   # --choiceshots：每个选卡画面都截一张（shot_choice_<n>.png，干员文字验收）
var trace_last := -1
# --perf（仅测试，开窗口跑 --balance 时用）：按游戏时间分段记真实帧时间、渲染 CPU / GPU 时间与同屏敌人数，
# 结束时打印一行 PERF {...}。注意 --balance 每帧推进 0.066 秒（正常游戏约 0.017 秒），每帧的模拟量偏大，帧时间是偏保守的上界
var perf_on := false
var perf_last := 0
var perf := {}
var perf_prev := {}            # 上一帧的 g.prof 累计（配合 --prof：逐帧分段）
var perf_slow: Array = []      # 慢帧（≥ 33 毫秒）明细，结束时取最慢 25 帧
var perf_kills := 0
const A_ = preload("res://scripts/art.gd")
const PlayClockT = preload("res://scripts/run/play_clock.gd")
const Dc = preload("res://scripts/render/declutter.gd")   # 后期降噪预设（--clutterab / --clutterlog 量测，tools/late_clutter.py）
var perf_upd := 0
var perf_min := false          # --perfmin：按游戏分钟分段（docs/50 §10）
var perf_ab := 0               # --perfab=N：每 N 帧轮换 g.perf_alt，分 /a /b 两桶
var perf_line_buf := PackedStringArray()
var perf_line := false         # --perfline（docs/50 §26.9）：逐帧打印 PF 行（帧时、敌人数、绘制调用、--stackab 掩码），按敌人数分档算帧时曲线
var perf_dump: FileAccess = null   # --perfdump=<路径>：逐帧 CSV（帧时间、各列表长度、--prof 分段）
const PERF_DUMP_KEYS := ["engine", "draw_world", "draw_hud", "draw_fxadd", "draw_fg", "autotest", "pre", "spawn", "grid", "enemies", "squad", "bullets", "ebullets",
	"relic", "misc", "fx", "cleanup", "visuals", "tail", "dw_sorted_entities", "dw_gems", "dw_ground", "dw_mire", "dw_zone", "dw_fx", "dw_bullets", "dw_shadows", "dw_warns_auras", "dw_ebullets_lobs_shocks", "dw_tells_outlines", "dw_snow_tail", "dw_shield_drones"]
var opticalab := -1           # --opticalab=N（docs/50 §25）：每 N 帧轮换光学观感原型开 / 关；-1 = 还没读参数
var fx1ab := 0                # --fx1ab=N（docs/50 §25.2）：每 N 帧轮换特效处理第 1 步开 / 关（光学观感开着时）
var partab := 0               # --partab=N（docs/136 §2 排查）：每 N 帧轮换光学 GPU 粒子开 / 关（--perf 分 /p1 /p0 两桶）
var matab := 0                # --matab=N：每 N 帧轮换材质颗粒（fx/material_grains）开 / 关（--perf 分 /m1 /m0；要同时 --bal=fx/material_grains=1）
var grainab := 0              # --grainab=N：每 N 帧轮换刀光第四版（粒子）开 / 关（--perf 分 /g1 /g0）
var tierab := 0               # --tierab=N（docs/50 §25.3）：每 N 帧轮换命中三档开 / 关
# --stackab=N:m1,m2,…（docs/50 §26）：每 N 帧换下一个掩码（optical.ab_mask：1 CPU 颗粒 / 2 GPU 粒子 / 4 特效照明 / 8 发光层 / 16 低分辨率层 / 32 整套光学），
# --perf 分 /s<掩码> 桶；切换后 3 帧记进 /sx 不算（低分辨率层重挂、粒子重启）
var stackab := 0
var stack_masks: Array = [0]
var stack_i := 0
var stack_sw := -99
var vfxab := -1               # --vfxab=N（docs/54）：每 N 帧轮换 vfx.p2；-1 = 还没读参数
var vfxdemo := false           # --vfxdemo：按固定时刻强制灯标点燃 / 升级 / 灯火暗淡 / 精英 / 拾取 / 商人（录对照片段用）
var _vd_step := 0
var _vd_beacon = null
var sfx_win_t := 0.0           # --sfxstat 批跑：每 30 秒（局内时间）打印一次各音名的 [请求, 实播] 增量（SFXWIN），查哪个音连发；实播要配 --realtime 才是真实间隔
var sfx_win_prev := {}


## --vfxdemo（docs/54 录像用，只在 --balance 下）：t≥18 在主控旁放 3 片溟痕 + 1 座灯标，20 秒点燃；26 秒升级；
## 31 秒灯火降到 29 + 右侧刷一只精英 + 脚边掉灯油；34 秒商人出现。模拟随机数照常消耗（对照的两边同一套参数，仍逐帧相同）
func _vfx_demo() -> void:
	if not g.balance or g.state != g.S.PLAY:
		return
	if _vd_step == 0 and g.t >= 18.0:
		_vd_step = 1
		var bp: Vector2 = g.ppos + Vector2(90, 0)
		for k in 3:
			var m: Dictionary = g.map.mire_new(bp + Vector2.from_angle(k * 2.1) * 150.0, g.t, false)
			m.r = m.maxr
			m.life = 60.0
			g.mires.append(m)
		_vd_beacon = {"pos": bp, "lit": false, "prog": 0.0, "need": 2.5, "lit_t": -1.0, "count_end": 0.0, "count_max": 0.0, "dead": false,
			"r": 70.0, "clear_r": 260.0, "safe_end": 0.0, "age": 0.0, "out_t": 0.0, "relay_r": g.beacon_sys._sk("relay_r")}   # 接力环画面（docs/56 §8，旋钮关时 0）
		g.beacons.append(_vd_beacon)
	elif _vd_step == 1 and g.t >= 20.0:
		_vd_step = 2
		if _vd_beacon != null and not _vd_beacon.lit:
			g.beacon_sys._light(_vd_beacon)
	elif _vd_step == 2 and g.t >= 26.0:
		_vd_step = 3
		g.pickups.gain_xp(g.xp_need - g.xp + 0.5)
	elif _vd_step == 3 and g.t >= 31.0:
		_vd_step = 4
		g.lamp = 29.0
		g.spawner.spawn_enemy("pocket", g.ppos + Vector2(230, -30))
		g.pickups.drop(g.ppos + Vector2(50, 10), "oil", 10.0)
	elif _vd_step == 4 and g.t >= 34.0:
		_vd_step = 5
		if g.merchant.is_empty():
			g.merchant = {"pos": g.ppos + Vector2(-220, -70), "life": 60.0, "near": false, "purchases": 0}


func _init(game: Game) -> void:
	g = game
	mshot = MotionShot.new(game)


## --statsshot=<秒>[,dead]（docs/77 实机截图）：机器人照常打到第 <秒> 秒后直接进胜利（结局一）/ 失败结算，
## 依次截 结算面板（多了「作战记录」按钮）→ 作战记录总览动效中（0.3 秒）→ 总览终态 → 主控详情 → 第二名干员详情，
## 存到 --shotdir：shot_stats_result / _motion / _overview / _detail0 / _detail1.png，截完退出。无头不截（只走流程）。
## 失败截图可加 cause=corrode@<敌人类型> 或 cause=mire / zone 摆拍击倒者（倒下前补一段扣血记账，只影响击倒者显示）。
var _ss := {}
func _stats_shot() -> bool:
	if _ss.is_empty():
		_ss = {"on": false}
		for a in Cfg.dev_args():
			if a.begins_with("--statsshot="):
				var pp: PackedStringArray = a.substr(12).split(",")
				_ss = {"on": true, "sec": float(pp[0]), "dead": pp.has("dead"), "hold": pp.has("hold"), "phase": 0, "f": 0, "cause": ""}   # hold：停在结算页不截图（帧时记录 --ftrec 用）
				for q in pp:
					if q.begins_with("cause="):
						_ss.cause = q.substr(6)   # 截图摆拍：cause=corrode@<敌人类型> / cause=mire —— 倒下前补一段对应的扣血记账（只改击倒者显示）
	if not _ss.on:
		return false
	var shot := func(name: String) -> void:
		if DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_stats_%s.png" % name)
		print("STATSSHOT ", name)
	match int(_ss.phase):
		0:
			if g.state != g.S.PLAY or g.t < float(_ss.sec):
				return false
			if _ss.dead:
				var cz: String = str(_ss.cause)
				if cz.begins_with("corrode@"):
					g.telemetry.on_status("corrode", cz.substr(8), 40.0)
					g.telemetry.on_lose(30.0, "corrode")
				elif cz != "":
					g.telemetry.on_status("nerve", "", 5.0)
					g.telemetry.on_lose(30.0, cz)
				g.state = g.S.DEAD
			else:
				g.ending = "standard"
				g.endg.cur = "standard"
				g.state = g.S.WIN
			_ss.phase = 1
			_ss.f = 0
		1:
			_ss.f += 1
			if _ss.hold:
				return true
			if g.state_age > (2.6 if _ss.dead else 0.8):
				shot.call("result")
				g._do_action("stats")
				_ss.phase = 2
				_ss.t = UM.now()
		2:
			if UM.now() - float(_ss.t) >= 0.3 and not _ss.has("m"):
				_ss["m"] = true
				shot.call("motion")
			if UM.now() - float(_ss.t) >= 1.4 and not _ss.has("o"):
				_ss["o"] = true
				shot.call("overview")
				if Cfg.touch_device():
					g.run_stats.tab = 1   # 手机：再截「藏品」「数据」两页
			if _ss.has("o") and Cfg.touch_device() and g.run_stats.tab == 1 and UM.now() - float(_ss.t) >= 1.8:
				shot.call("tab1")
				g.run_stats.tab = 2
			if _ss.has("o") and Cfg.touch_device() and g.run_stats.tab == 2 and UM.now() - float(_ss.t) >= 2.2:
				shot.call("tab2")
				g.run_stats.tab = 0
			if _ss.has("o") and (not Cfg.touch_device() or UM.now() - float(_ss.t) >= 2.5) and g.run_stats.tab == 0:
				g.run_stats.key(KEY_ENTER)
				_ss.phase = 3
				_ss.t = UM.now()
		3:
			if UM.now() - float(_ss.t) >= 0.9:
				shot.call("detail0")
				if g.run_stats.rows().size() > 1:
					g.run_stats.key(KEY_RIGHT)
				_ss.phase = 4
				_ss.t = UM.now()
		4:
			if UM.now() - float(_ss.t) >= 0.9:
				shot.call("detail1")
				var m: Dictionary = g.run_stats.model
				print("STATSSHOT_MODEL ", JSON.stringify({"total": m.total, "taken": int(m.leader.taken), "heal": int(m.leader.heal), "heal_src": m.leader.heal_src.map(func(x): return [x.name, int(x.v)]), "taken_src": m.leader.taken_src.map(func(x): return [x.name, int(x.v)]), "hp": [int(g.hp), int(g.max_hp)], "floor": g.floor_hits, "hits": g.telemetry.hits, "rows": m.rows.map(func(r): return [r.key, int(r.dmg), r.pct, r.kills, r.casts, snappedf(r.join_t, 1)])}))
				g.get_tree().quit()
				_ss.phase = 5
	return true


## 平衡机器人选卡（docs/27 §6）：像一个「懂玩」的玩家——优先干员深度 / 技能卡，早期见招募就招，
## 被动按 data/balance.json bot.growth_weights 加权，填充卡只在没得选时拿；--botrandom 退回纯随机
func bot_pick() -> int:
	if g.choices.is_empty():
		return 0
	if g.choice_kind == "swap":
		return g.progression.auto_swap_pick()   # 更换队友画面（bot/swap 缺省 0 = 不替换）
	if g.choice_kind == "branch":
		return g.progression.auto_branch_pick()   # 培养路线二选一：固定路线（character.bot_route），不取随机数
	# 满员招募卡（更换队友）：bot/swap 关时不进候选，其余选法照旧；下标映射回 g.choices
	var idx: Array = g.progression.auto_choices()
	if idx.size() < g.choices.size():
		var keep: Array = g.choices
		g.choices = idx.map(func(k): return keep[k])
		var sub_i: int = _bot_pick_inner()
		g.choices = keep
		return int(idx[clampi(sub_i, 0, idx.size() - 1)])
	return _bot_pick_inner()


func _bot_pick_inner() -> int:
	if g.bot != null:
		var bp: int = g.bot.pick(g.choices)
		if bp >= 0:
			return bp
	if Cfg.dev_args().has("--botrandom"):
		return g.rng.randi() % g.choices.size()
	var W: Dictionary = Bal.sec("bot/weights")
	var GW: Dictionary = Bal.sec("bot/growth_weights")
	var early_recruit: int = Bal.vi("bot/prefer_recruit_before", 8)
	var ws: Array = []
	var total := 0.0
	for c in g.choices:
		var w: float = float(W.get(c.get("kind", ""), 1.0))
		if c.kind == "recruit" and g.level < early_recruit:
			w = 100.0
		elif c.kind == "growth":
			w *= float(GW.get(c.get("id", ""), 1.0))
		elif c.kind == "prog" and int(c.get("elite", 0)) > 0:
			w *= 1.5   # 精英化卡：解锁技能与天赋，价值最高
		ws.append(w)
		total += w
	var r := g.rng.randf() * total
	for i in ws.size():
		r -= ws[i]
		if r <= 0.0:
			return i
	return ws.size() - 1


## --knightshots（结局二终局验收，10-14；配 --balance --relics=222）：骑士开始走向黑潮中心后 24 帧截 shot_knight_walk.png，
## 入潮演出中截 shot_knight_sink.png，消失后 12 帧截 shot_knight_hud.png（HUD 灰格），最终 Boss 出现后 30 帧截 shot_knight_boss.png，
## 150 帧截 shot_knight_boss2.png 并退出。无头不截（只走流程）。
## 镜头一瞥开着时（缺省，game.camera_glance）：不用 view_override，截图按一瞥的节奏（--fixed-fps 60：0.35 秒去 + 0.6 秒停 + 0.35 秒回 = 78 帧）——
## sink（入潮 +24 帧，镜头停在圈心）、hud（+48 帧，仍在圈心）、sink_back（+90 帧，镜头已回到队长）、boss（+30 帧，圈心）、boss_back（+90 帧，队长）。
## 关着时（--bal=render/camera_glance=0）照旧用 view_override 把镜头指过去。
var _ks := {"walk": -1, "sink": -1, "hud": -1, "boss": -1}
func _knight_shots() -> void:
	var shot := func(name: String) -> void:
		if DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_knight_%s.png" % name)
		var kp: Vector2 = g.knight.pos - g.ppos
		var bp: Vector2 = (g.final_boss.pos - g.ppos) if g.final_boss != null else Vector2.INF
		print("KNIGHTSHOT %s t=%.1f knight_off=%s boss_off=%s zone_off=%s cam_off=%s" % [name, g.t, kp.round(), bp.round(), (g.zone_c - g.ppos).round(), (g.cam.position - g.ppos).round()])
	var k = g.knight
	var glance: bool = Bal.vi("render/camera_glance", 1) > 0 and not g.headless_batch
	# 黑潮中心通常在屏幕外（离队长 400–600）：一瞥关着时，入潮演出到灰格截图期间、Boss 登场后，镜头临时看向那里（只动镜头）
	g.view_override = Vector2.INF
	if not glance:
		if (k.alive and k.state == "sink") or (k.submerged and _ks.hud >= 0 and g.at_frames <= _ks.hud + 12):
			g.view_override = k.vanish_pos
		elif _ks.boss >= 0 and g.final_boss != null:
			g.view_override = g.final_boss.pos
	if _ks.walk < 0 and k.alive and k.state == "walk":
		_ks.walk = g.at_frames
	if _ks.walk >= 0 and g.at_frames == _ks.walk + 24:
		shot.call("walk")
	if _ks.sink < 0 and k.alive and k.state == "sink":
		_ks.sink = g.at_frames
	if _ks.sink >= 0 and g.at_frames == _ks.sink + (24 if glance else 7):
		shot.call("sink")
	if glance and _ks.sink >= 0 and g.at_frames == _ks.sink + 90:
		shot.call("sink_back")
	if _ks.hud < 0 and k.submerged:
		_ks.hud = g.at_frames
	if _ks.hud >= 0 and g.at_frames == _ks.hud + 12:
		shot.call("hud")
	if _ks.boss < 0 and g.final_boss != null and g.final_boss.type == "knight_boss":
		_ks.boss = g.at_frames
	if _ks.boss >= 0 and g.at_frames == _ks.boss + 30:
		shot.call("boss")
	if glance and _ks.boss >= 0 and g.at_frames == _ks.boss + 90:
		shot.call("boss_back")
	if _ks.boss >= 0 and g.at_frames == _ks.boss + 150:
		shot.call("boss2")   # Boss 登场演出过后，看得见 Boss 本体与场地
		g.get_tree().quit()


## --recframes=<起始秒>,<帧数>（docs/50 §10 顿帧前后对照录像，配 --playclock --fixed-fps 30）：游戏时间过了起始秒后连存 N 帧
## rec_<帧>.png 到 --shotdir；--legacyfeel：整局用旧的切步与顿帧规则（g.perf_alt + PlayClock.test_legacy）
var _rec_t0 := -2.0
var _rec_left := 0
var _rec_i := 0
func _rec_step() -> void:
	if _rec_t0 < -1.0:
		_rec_t0 = -1.0
		for a in Cfg.dev_args():
			if a.begins_with("--recframes="):
				var p: PackedStringArray = a.substr(12).split(",")
				_rec_t0 = float(p[0])
				_rec_left = int(p[1])
			if a == "--legacyfeel":
				g.perf_alt = true
				PlayClockT.test_legacy = true
	if _rec_t0 >= 0.0 and _rec_left > 0 and g.t >= _rec_t0 and g.state == g.S.PLAY and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/rec_%05d.png" % _rec_i)
		_rec_i += 1
		_rec_left -= 1
		if _rec_left == 0:
			g.get_tree().quit()


## --camlog=<起始秒>（docs/139 画面眩晕排查，仅测试）：游戏时间过了起始秒后每帧打印一行 CAMLOG：镜头位置 / 偏移、
## 画布变换原点（窗口像素）、镜头缩放、低分辨率贴图位置、本帧是否顿帧、正在后坐 / 形变的敌人数、敌人总数；
## --nohitstop：整局关命中顿帧（同设置「命中顿帧」关）
var _camlog_t0 := -2.0
func _camlog_step() -> void:
	if _camlog_t0 < -1.0:
		_camlog_t0 = -1.0
		for a in Cfg.dev_args():
			if a.begins_with("--camlog="):
				_camlog_t0 = float(a.substr(9))
			if a == "--nohitstop":
				Cfg.hitstop = false
			if a.begins_with("--perfdump=") and DisplayServer.get_name() != "headless":
				var sc: int = DisplayServer.window_get_current_screen()
				print("SCREEN idx=%d refresh=%.2f size=%s win=%s vsync=%d max_fps=%d" % [sc, DisplayServer.screen_get_refresh_rate(sc), str(DisplayServer.screen_get_size(sc)),
					str(DisplayServer.window_get_size()), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	if _camlog_t0 < 0.0 or g.t < _camlog_t0 or g.state != g.S.PLAY or g.cam == null:
		return
	var vp: Viewport = g.get_viewport()
	var xf: Transform2D = vp.get_final_transform() * vp.get_canvas_transform()
	var nrc := 0
	var nsq := 0
	for e in g.enemies:
		var rt: float = float(e.get("rc_t", g.world.rc_t))
		if g.t - float(e.get("rc_at", -99.0)) < rt:
			nrc += 1
		if float(e.get("squash", 0.0)) > 0.0:
			nsq += 1
	var lr: Vector2 = g.optical.lo_rect.position if g.optical != null and g.optical.lo_rect != null and g.optical_lo else Vector2.ZERO
	print("CAMLOG %d %.4f %.1f %.1f %.1f %.1f %.3f %.3f %.4f %.3f %.3f %d %d %d %d %.1f %.1f" % [Engine.get_process_frames(), g.t, g.cam.position.x, g.cam.position.y,
		g.cam.offset.x, g.cam.offset.y, xf.origin.x, xf.origin.y, xf.x.x, lr.x, lr.y, 1 if (g.hitstop > 0.0 and Cfg.hitstop) else 0, nrc, nsq, g.enemies.size(), g.ppos.x, g.ppos.y])


## --flashrec=<起始秒>,<帧数>[,<宽>]（docs/137 Boss 频闪测量，配 --balance --realtime --fixed-fps 30）：游戏时间过了起始秒后每帧
## 存一张缩到 <宽>（缺省 480）的 fr_<帧>.png 到 --shotdir，并在同目录 flashrec.csv 记同一帧的画面状态（Boss 白闪 / 阶段 / 茧、
## 震屏、全屏闪光、顿帧、命中星、预警数、登场演出），tools/boss_flash_measure.py 统计亮度跳变。
## --flashspawn=<boss>[2|_cocoon]：第 20 帧在主控旁刷出该 Boss（二阶段加 2，同 --bosstest；paranoia_cocoon 直接结茧），但时间照常走、自测不扣 Boss 血
var _fr_t0 := -2.0
var _fr_left := 0
var _fr_w := 480
var _fr_i := 0
var _fr_csv: FileAccess = null
var _fr_spawn := ""
func _flashrec_step() -> void:
	if _fr_t0 < -1.0:
		_fr_t0 = -1.0
		for a in Cfg.dev_args():
			if a.begins_with("--flashrec="):
				var p: PackedStringArray = a.substr(11).split(",")
				_fr_t0 = float(p[0])
				_fr_left = int(p[1])
				if p.size() > 2:
					_fr_w = int(p[2])
			if a.begins_with("--flashspawn="):
				_fr_spawn = a.substr(13)
	if _fr_spawn != "" and g.at_frames == 20:
		var b: Dictionary = g.spawner.spawn_enemy(_fr_spawn.trim_suffix("2").trim_suffix("_cocoon"), g.ppos + Vector2(230, -40))
		b.age = 5.0
		if _fr_spawn.ends_with("2"):
			g.bai.setup_preview_phase2(b)
		if _fr_spawn.ends_with("_cocoon"):
			g.bai.boss(b.type).paranoia_cocoon(b)   # 泡影茧（外壳白闪 +「抵抗」）
		g.bosses.append(b)
		g.boss = b
		if g.final_boss == null and g.spawner.is_final_boss_type(b.type):
			g.final_boss = b
	if _fr_spawn != "" and g.at_frames == 25 and Cfg.dev_args().has("--texdump"):
		for k in g.tex.keys():
			var ks := str(k)
			if (ks.begins_with("e_knight") or ks.begins_with("e_paranoia")) and not ks.ends_with("_white") and g.tex[k] != null:
				var wt = g.tex.get(ks + "_white")
				print("TEXDUMP %s %s white=%s same_src=%s" % [ks, g.tex[k].get_size(), wt.get_size() if wt != null else "none", str(wt == A_.white_of(g.tex[k])) if wt != null else "-"])
	if _fr_t0 < 0.0 or _fr_left <= 0 or g.t < _fr_t0 or DisplayServer.get_name() == "headless":
		return
	if _fr_csv == null:
		_fr_csv = FileAccess.open(g.shot_dir + "/flashrec.csv", FileAccess.WRITE)
		_fr_csv.store_line("i,frame,t,state,boss,hp,phase,cocoon,bflash,shake,gflash,hitstop,hstar,warns,intro,bx,by,br,fx")
	var bb = g.final_boss if g.final_boss != null else (g.bosses[0] if not g.bosses.is_empty() else null)
	if Cfg.dev_args().has("--enemydump") and _fr_i % 10 == 0 and bb != null:
		var near: Array = []
		for e in g.enemies:
			if not e.dead and (e.pos as Vector2).distance_to(bb.pos) < 700.0:
				near.append("%s/%s#%d@%d,%d%s" % [e.type, e.tex, e.id, e.pos.x, e.pos.y, " B" if e.boss else ""])
		print("ENEMYDUMP i=%d %s" % [_fr_i, " ".join(near)])
	var img: Image = g.get_viewport().get_texture().get_image()
	img.resize(_fr_w, int(_fr_w * img.get_height() / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
	img.save_png(g.shot_dir + "/fr_%05d.png" % _fr_i)
	var hs := 0
	for f in g.fx:
		if f.get("kind", "") == "hstar":
			hs += 1
	var vs: Vector2 = g.get_viewport().get_visible_rect().size
	var bs: Vector2 = (g.get_canvas_transform() * (bb.pos as Vector2)) / vs if bb != null else Vector2(-1, -1)
	var brr: float = float(bb.get("r", 0.0)) * g.get_canvas_transform().get_scale().y / vs.y if bb != null else 0.0
	_fr_csv.store_line("%d,%d,%.4f,%d,%s,%.0f,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%d,%d,%.4f,%.4f,%.4f,%d" % [_fr_i, g.at_frames, g.t, g.state,
		bb.type if bb != null else "", bb.hp if bb != null else 0.0, int(bb.get("phase", 0)) if bb != null else 0,
		float(bb.get("cocoon_t", 0.0)) if bb != null else 0.0, float(bb.get("flash", 0.0)) if bb != null else 0.0,
		g.shake, g.flash, g.hitstop, hs, g.warns.size(), 0 if g.boss_intro.cur.is_empty() else 1, bs.x, bs.y, brr,
		int(bb.fx) if bb != null else 0])
	_fr_i += 1
	_fr_left -= 1
	if _fr_left == 0:
		_fr_csv.close()
		g.get_tree().quit()


## --bossdup（docs/137 §7，仅测试，可无头）：每秒查一次场上活着的 Boss（g.enemies 里 role = boss 的），
## 不同组（不是接潮搭档）同时在场、或同一种 Boss 出现两只时打印 BOSSDUP t=… [类型#id@位置 …]
var _bd_on := -1
var _bd_last := -1
func _bossdup_step() -> void:
	if _bd_on < 0:
		_bd_on = 1 if Cfg.dev_args().has("--bossdup") else 0
	if _bd_on == 0 or int(g.t) == _bd_last:
		return
	_bd_last = int(g.t)
	var alive: Array = []
	for e in g.enemies:
		if not e.dead and str(D.ENEMIES.get(e.type, {}).get("role", "")) == "boss":
			alive.append(e)
	if alive.size() < 2:
		return
	var types := {}
	var dup := false
	var groups := 0
	for e in alive:
		if types.has(e.type):
			dup = true
		types[e.type] = true
		if e.get("partner") == null or not alive.has(e.partner) or int(e.id) < int(e.partner.id):
			groups += 1
	if dup or groups > 1:
		print("BOSSDUP t=%d %s" % [int(g.t), " ".join(alive.map(func(x): return "%s#%d@%d,%d%s%s" % [x.type, x.id, x.pos.x, x.pos.y, "" if g.bosses.has(x) else "(不在bosses)", "(final)" if is_same(x, g.final_boss) else ""]))])


## --optab=N / --optmask=位 / --optold=位（docs/50 §11，仅测试）：每 N 帧在新 / 旧实现之间轮换 g.opt_old（只在真实步长段轮换）；
## --perf 分 /new /old 两桶
var _optab := -1
var _optmask := 0xffff
func _opt_ab() -> void:
	if _optab < 0:
		_optab = 0
		for a in Cfg.dev_args():
			if a.begins_with("--optab="):
				_optab = int(a.substr(8))
			elif a.begins_with("--optmask="):
				_optmask = int(a.substr(10))
			elif a.begins_with("--optold="):
				g.opt_old = int(a.substr(9))
	if _optab > 0 and g.at_frames % _optab == 0 and g.realtime:
		g.opt_old = 0 if g.opt_old != 0 else _optmask


## 仅用于开发自测：快速模拟一整局，自动选择升级，打印状态后退出
## --cmdat=<秒>,<秒>,…（指挥模式录片 / 复现，docs/114）：游戏时间到这些秒各按一次指挥键（同玩家按 F），切换照常记进 squad.stance_log
var _cmd_at: Array = []
var _cmd_read := false
var _cmd_down_at := -1.0
var _swap_at: Array = []   # --swapat=<秒>,…（录片 / 复现，10-23）：到点各按一次 Q（切换队长）
func _cmd_step() -> void:
	if not _cmd_read:
		_cmd_read = true
		for a in Cfg.dev_args():
			if a.begins_with("--swapat="):
				_swap_at = Array(a.substr(9).split(",")).map(func(x): return float(x))
			if a.begins_with("--cmddown="):
				_cmd_down_at = float(a.substr(10))
			if a.begins_with("--cmdat="):
				_cmd_at = Array(a.substr(8).split(",")).map(func(x): return float(x))
	if _cmd_down_at >= 0.0 and g.state == g.S.PLAY and g.t >= _cmd_down_at:
		_cmd_down_at = -1.0
		for o in g.squad.ops:   # --cmddown=<秒>（录片用）：到点让全部队友原地倒地，看倒地姿势 / 复活
			if not o.is_leader:
				o.cmd_hp = 0.0
				o.cmd_down = Bal.v("command/revive_secs", 25.0)
				o.cmd_down_age = 0.0
				print("CMD t=%.2f down %s at %.0f,%.0f" % [g.t, o.id, o.pos.x, o.pos.y])
	if not _swap_at.is_empty() and g.state == g.S.PLAY and g.t >= float(_swap_at[0]):
		_swap_at.pop_front()
		g.squad.cycle_leader()
	if not _cmd_at.is_empty() and g.state == g.S.PLAY and g.t >= float(_cmd_at[0]):
		_cmd_at.pop_front()
		g.toggle_command()


func step() -> void:
	g.at_frames += 1
	if g.rt_from >= 0.0 and not g.realtime and g.t >= g.rt_from:
		g.realtime = true   # --rtfrom：快进结束，之后按真实步长（--fixed-fps 60 时每帧 1/60 秒）
		print("PF RTFROM t=%.1f" % g.t)   # 网页低配测量（tools/perf_web.py --throttle）：看到这行才开 CPU 节流，快进段不节流
	if vfxab < 0:
		vfxab = 0
		for a in Cfg.dev_args():
			if a.begins_with("--vfxab="):
				vfxab = int(a.substr(8))
		vfxdemo = Cfg.dev_args().has("--vfxdemo")
		opticalab = 0
		for a in Cfg.dev_args():
			if a.begins_with("--opticalab="):
				opticalab = int(a.substr(12))
			if a.begins_with("--fx1ab="):
				fx1ab = int(a.substr(8))
			if a.begins_with("--tierab="):
				tierab = int(a.substr(9))
			if a.begins_with("--partab="):
				partab = int(a.substr(9))
			if a.begins_with("--matab="):
				matab = int(a.substr(8))
			if a.begins_with("--grainab="):
				grainab = int(a.substr(10))
			if a.begins_with("--stackab="):
				var sp: PackedStringArray = a.substr(10).split(":")
				stackab = int(sp[0])
				stack_masks = Array(sp[1].split(",")).map(func(x): return int(x)) if sp.size() > 1 else [0, 1]
				g.optical.ab_mask = int(stack_masks[0])
			if a == "--nohud" and g.hud != null and g.hud.get_parent() is CanvasLayer:
				(g.hud.get_parent() as CanvasLayer).visible = false   # 概念样图底图（tools/probes/map_concept.py）：只要世界画面，界面层整层不画
			if a == "--optical":
				g.optical.force = 1   # 截图 / 录像：强制开光学观感（不改 balance）
			if a == "--nooptical":
				g.optical.force = 0
	if g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--perf"):
		_perf_sample()
	if g.mode == g.Mode.BALANCE and g.t >= sfx_win_t + 30.0 and Cfg.dev_args().has("--sfxstat"):
		_sfx_win()
	_rec_step()
	_camlog_step()
	_flashrec_step()
	_bossdup_step()
	_cmd_step()
	_opt_ab()   # 在 --perf 采样之后轮换：采样记的是上一帧所走的实现
	Dc.ab_step(g.at_frames)   # --clutterab=N：每 N 帧在降噪 0 档与当前档之间轮换（--perf 分 /d0 /dN 两桶）
	if opticalab > 0 and g.at_frames % opticalab == 0 and g.optical != null:
		g.optical.force = 0 if g.optical.force == 1 else 1   # --opticalab=N：同局轮换光学观感开 / 关（--perf 分 /opt /base 两桶）
	if partab > 0 and g.at_frames % partab == 0 and g.optical != null and g.optical.particles != null:
		g.optical.particles.set_active(not g.optical.particles.active)   # --partab=N：同局轮换 GPU 粒子（--perf 分 /p1 /p0）
	if grainab > 0 and g.at_frames % grainab == 0 and g.optical != null and g.optical.grains != null:
		g.optical.grains.off = not g.optical.grains.off   # --grainab=N：同局轮换刀光第四版
	if stackab > 0 and g.at_frames % stackab == 0 and g.optical != null:
		stack_i = (stack_i + 1) % stack_masks.size()   # --stackab：换下一个逐层关闭掩码
		g.optical.ab_mask = int(stack_masks[stack_i]) & 127
		if stack_masks.any(func(m): return int(m) & 128):
			Cfg.set_render_scale((int(stack_masks[stack_i]) & 128) != 0)   # 位 128：分辨率缩放（docs/50 §28 自动档第 3 级）
		stack_sw = g.at_frames
	if matab > 0 and g.at_frames % matab == 0 and g.optical != null and g.optical.grains != null:
		g.optical.grains.mat_off = not g.optical.grains.mat_off   # --matab=N：同局轮换材质颗粒
	if tierab > 0 and g.at_frames % tierab == 0:
		g.vfx.tier_off = not g.vfx.tier_off   # --tierab=N：同局轮换命中三档（--perf 分 /t1 /t0 两桶）
	if fx1ab > 0 and g.at_frames % fx1ab == 0 and g.optical != null:
		g.optical.fx1_force = 0 if g.optical.fx1_force == 1 else 1   # --fx1ab=N：同局轮换特效处理第 1 步（--perf 分 /fx1 /fx0 两桶）
	if vfxab > 0 and g.at_frames % vfxab == 0:
		g.vfx.p2 = not g.vfx.p2   # --vfxab=N：每 N 帧轮换画面特效二轮开 / 关（docs/54 同局对照测量；--perf 分 /on /off 两桶）
	if vfxdemo:
		_vfx_demo()
	if mshot.step():
		return   # 界面动效自测接管这一局（docs/62）
	if _stats_shot():
		return   # 作战记录截图接管（docs/77）
	if g.state == g.S.OPENING and Cfg.dev_args().has("--openshot"):
		if g.at_frames % 3 == 0 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_open_%03d.png" % g.at_frames)
		if g.at_frames > 240:
			g.get_tree().quit()
		return
	if g.state == g.S.INTRO:
		if g.intro_t > 0.5 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_intro_%d.png" % g.intro_page)
			if g.intro_page >= g.intro_screen.pages().size() - 1:
				g.get_tree().quit()
				return
			g.intro_page += 1
			g.intro_t = 0.0
		return
	if Cfg.dev_args().has("--gallery"):
		g.demo_sys.gallery_step()
		return
	if g.state == g.S.SHOP:
		var lane_i: int = g.bot.shop_pick() if g.bot != null else -1
		if lane_i >= 0:
			g.shop_sys.buy(lane_i)
		for i in (g.shop_items.size() if lane_i < 0 else 0):
			if g.shop_sys.can_buy(g.shop_items[i]):
				g.shop_sys.buy(i)
				break
		if shop_visits == 1 and DisplayServer.get_name() != "headless" and g.mode != g.Mode.BALANCE:
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_shop.png")
		shop_visits += 1
		if shop_visits % 3 == 0:
			g.shop_sys.close()
	for m in [120, 300, 480]:
		if g.t >= m and not lv_marks.has(m):
			lv_marks[m] = g.level
	if Cfg.dev_args().has("--knightshots"):
		_knight_shots()
	# --tabshot=<帧>：第 <帧> 帧打开 Tab 属性面板，3 帧后截图 shot_tab.png 并退出（干员文字验收：技能 / 天赋 / 普攻形态行，10-14）
	for a in Cfg.dev_args():
		if a.begins_with("--tabshot="):
			var tf := int(a.substr(10))
			if g.at_frames == tf:
				g.state = g.S.STATS
			if g.at_frames == tf + 3 and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_tab.png")
				g.get_tree().quit()
	if Cfg.dev_args().has("--fxtest"):
		g.ppos = Vector2(1500, 900)
		if g.at_frames == 90:
			g.hp = g.max_hp * 0.2
			g.combat.hurt(g.max_hp * 0.1)
		if g.at_frames == 96 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_hurt.png")
		if g.at_frames == 175:
			g.zone_c = g.ppos + Vector2(560, 60)
			g.zone_r = 480.0
			g.zone_state = 3
			g.zone_t = -999.0
		if g.at_frames == 188 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_zone.png")
		if g.at_frames == 130:
			g.state = g.S.STATS
		if g.at_frames == 132:
			for c in g.stats_cells:
				if c[1] == "relic":
					Input.warp_mouse(c[0].get_center())
					break
		if g.at_frames == 134 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_stats.png")
			g.state = g.S.PLAY
		if g.at_frames == 20:
			g.weapons = {"drone": 4}
			for rid in ["118", "199", "100"]:
				g.relics.append(rid)
				g.progression.apply_relic(rid)
			g.shield = 2
			g.ch.elite = 2
			g.ch.fill_sp()
			for k in ["wisadel", "eyjafjalla", "suzuran"]:
				var op = g.squad.add(k)
				if op != null:
					op.advance()
					op.advance()
			g.t = 149.0
			g.next_horde = g.t + 60.0
			g.merchant = {"pos": g.ppos + Vector2(900, -300), "life": 60.0, "near": false}
		if g.at_frames == 150 and not g.tray_cells.is_empty():
			Input.warp_mouse(g.tray_cells[0][0].get_center())
		if g.at_frames == 60:
			g.pickups.drop(g.ppos + Vector2(120, 40), "magnet", 1.0)
			g.pickups.drop(g.ppos + Vector2(-120, 40), "heal", 1.0)
		for f in [64, 72, 100, 125, 160, 200]:
			if g.at_frames == f and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_%d.png" % f)
	for a in Cfg.dev_args():
		if a.begins_with("--spawntest="):
			# 小怪 / 精英招式截图（docs/36 §5）：第 20 帧把逗号分隔的敌人刷在主控右侧（跳过登场保护），时间照常走（--bosstest 的 g.t 不动，
			# 远程蓄力 shot_wind_until 永远到不了），之后每 6 帧截一张 shot_spawn_<id>_<帧>.png 到第 320 帧，第 330 帧退出
			if g.at_frames == 20:
				g.ppos = Vector2(1500, 900)
				g.max_hp = 900.0
				g.hp = 900.0
				for st in a.substr(12).split(","):
					var se: Dictionary = g.spawner.spawn_enemy(st, g.ppos + Vector2(230, -40))
					se.age = 5.0
			if g.at_frames > 20 and g.at_frames % 6 == 0 and g.at_frames <= 320 and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_spawn_%s_%03d.png" % [a.substr(12).replace(",", "_"), g.at_frames])
			if g.at_frames > 330:
				g.get_tree().quit()
		if a.begins_with("--bosstest="):
			# Boss 招式测试：在水月旁刷出指定 Boss，定时截图
			bosstest = true
			if g.at_frames == 20:
				g.ppos = Vector2(1500, 900)
				g.max_hp = 900.0
				g.hp = 900.0
				g.t = 150.0
				for bt in a.substr(11).split(","):
					var b := g.spawner.spawn_enemy(bt.trim_suffix("2"), g.ppos + Vector2(230, -40))
					b.age = 5.0
					if bt.ends_with("2"):
						g.bai.setup_preview_phase2(b)   # 与演练 / 图鉴使用同一阵营、形态和技能初始化。
					# 只有 role == boss 的进 bosses（HUD 大血条、Boss 在场判定）；参数里列的小怪（碎片、之泪等）照常刷出来当靶子
					if not b.boss:
						continue
					g.bosses.append(b)
					g.boss = b
					# 结局 Boss 也设「最终 Boss」标记，走终局音乐 / 终局藏品倍率（docs/38 B0 第 9 项）
					if g.final_boss == null and g.spawner.is_final_boss_type(b.type):
						g.final_boss = b
				if g.bosses.size() == 2:
					g.bosses[0].partner = g.bosses[1]
					g.bosses[1].partner = g.bosses[0]
			if g.at_frames > 20 and g.at_frames % 30 == 0 and g.at_frames <= 600 and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_boss_%s_%03d.png" % [a.substr(11).replace(",", "_"), g.at_frames])
		if a.begins_with("--bossmoves="):
			bosstest = true
			_bossmoves_step(a.substr(12))
		if a.begins_with("--bossacts="):
			bosstest = true
			_bossacts_step(a.substr(11))
		if a.begins_with("--bossintro="):
			# Boss 登场演出测试（docs/36 §5）：第 20 帧在主控旁刷出指定 Boss（逗号分隔 = 同组登场）并走一遍登场，
			# 登场进行到 0.35 / 0.6 / 0.85 / 1.1 秒各截一张；演完后把 Boss 击杀，击破一拍 0.12 / 0.35 秒再各截一张，然后退出
			bosstest = true   # 别让自测每帧扣 Boss 血
			var tag: String = a.substr(12).replace(",", "_")
			if g.at_frames == 20:
				g.ppos = Vector2(1500, 900)
				g.t = 150.0
				var grp: Array = []
				for bt in a.substr(12).split(","):
					var b := g.spawner.spawn_enemy(bt, g.ppos + Vector2(230 + 90 * grp.size(), -40))
					b.age = 5.0
					if not b.boss:
						continue
					g.bosses.append(b)
					g.boss = b
					grp.append(b)
				if grp.size() == 2:
					grp[0].partner = grp[1]
					grp[1].partner = grp[0]
				g.boss_intro.on_spawn(grp, true)
				g.boss_intro._test_shots = [0.35, 0.6, 0.85, 1.1]
			if g.at_frames > 20 and DisplayServer.get_name() != "headless":
				var bi = g.boss_intro
				if bi.active() and not bi._test_shots.is_empty() and bi.cur.t >= float(bi._test_shots[0]):
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossintro_%s_%03d.png" % [tag, int(bi.cur.t * 100.0)])
					bi._test_shots.pop_front()
				if not bi.active() and bi.outro.is_empty() and g.at_frames > 40 and bossintro_kill_at < 0 and g.bosses.any(func(b): return not b.dead):
					for b in g.bosses:
						if not b.dead:
							g.combat.kill(b)
					bossintro_kill_at = g.at_frames
					bi._test_shots = [0.12, 0.35]
				if not bi.outro.is_empty() and not bi._test_shots.is_empty() and bi.outro.t >= float(bi._test_shots[0]):
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossout_%s_%03d.png" % [tag, int(bi.outro.t * 100.0)])
					bi._test_shots.pop_front()
				if bossintro_kill_at >= 0 and g.at_frames > bossintro_kill_at + 90:
					g.get_tree().quit()
		if a.begins_with("--bossdeath=") and D.ENDINGS.has(a.substr(12)):
			# 最终 Boss 击破演出测试（docs/36 §5，docs/38 §1.8）：第 20 帧把该结局的最终 Boss 刷在主控旁、走登场演出，
			# 登场演完再过 30 帧击杀它 → victory_flow 慢动作 + boss_intro 击破演出；演出 0.2 / 0.5 / 0.9 / 1.4 / 1.8 秒各截一张
			# shot_bossdeath_<结局>_<百分秒>.png，进结算面板 45 帧后退出。开着窗口的 --balance 也演（录片用），无头不演
			bosstest = true
			var eid: String = a.substr(12)
			if g.at_frames == 20:
				g.ppos = Vector2(1500, 900)
				g.t = 600.0
				g.ending = eid
				g.endg.cur = eid
				var b := g.spawner.spawn_enemy(str(D.ENDINGS[eid].boss), g.ppos + Vector2(230, -40))
				b.age = 5.0
				g.bosses.append(b)
				g.boss = b
				g.final_boss = b
				g.boss_intro.on_spawn([b], true)
				g.boss_intro._test_shots = [0.2, 0.5, 0.9, 1.4, 1.8]
			if g.at_frames > 20:
				var bi = g.boss_intro
				if not bi.active() and g.at_frames > 40 and bossintro_kill_at < 0 and g.final_boss != null and not g.final_boss.dead:
					bossintro_kill_at = g.at_frames   # 登场演完的帧号：再过 30 帧击杀
				if bossintro_kill_at > 0 and g.at_frames == bossintro_kill_at + 30 and g.final_boss != null and not g.final_boss.dead:
					g.combat.kill(g.final_boss)
				if DisplayServer.get_name() != "headless" and not bi.finale.is_empty() and not bi._test_shots.is_empty() and float(bi.finale.t) >= float(bi._test_shots[0]):
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossdeath_%s_%03d.png" % [eid, int(float(bi.finale.t) * 100.0)])
					bi._test_shots.pop_front()
				if g.state == g.S.WIN and g.state_age > 1.5:
					g.get_tree().quit()
	if Cfg.dev_args().has("--fastlevel") and g.state == g.S.PLAY and (g.at_frames == 30 or g.at_frames == 400):
		g.level = 9 if g.at_frames == 30 else 19
		g.pickups.gain_xp(g.xp_need + 0.1)
	if g.state == g.S.SHOW:
		if g.mode == g.Mode.BALANCE:
			g.show_t = 2.0
			g.show_screen.close()
			return
		if g.show_t > 1.4 and not g.show_shot and DisplayServer.get_name() != "headless":
			g.show_shot = true
			# 按演出的干员和阶段命名（编队里别的干员精英化时，主控的 elite 对不上）
			var sc: Dictionary = g.show_screen.show_cur
			var tag: String = "%s_%d" % [sc.op.id, int(sc.get("elite", 0))] if sc.has("op") and sc.op != null else str(g.ch.elite)
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_show_%s.png" % tag)
		if g.show_t > 1.6:
			g.show_screen.close()
		return
	if g.at_frames == 30 and g.state == g.S.PLAY:
		for a in Cfg.dev_args():
			if a.begins_with("--grant="):
				for rid in a.substr(8).split(","):
					g.progression.gain_relic(rid)
	# --lampat=<秒>:<灯火>：到这一秒把灯火设成这个值一次（截暗处画面用，docs/50 §16 怪物体型的暗处可读性；会改之后的对局）
	if not _lampat_done and g.state == g.S.PLAY:
		for a in Cfg.dev_args():
			if a.begins_with("--lampat=") and g.t >= float(a.substr(9).split(":")[0]):
				_lampat_done = true
				g.lamp = float(a.substr(9).split(":")[1])
	if Cfg.dev_args().has("--materialmovie") and not g.has_node("MaterialMovie"):
		var movie = load("res://tests/material_movie.gd").new()
		movie.name = "MaterialMovie"
		movie.g = g
		g.add_child(movie)
	# 短时人工验收：同一场景左原版、右材质颗粒，沿用实际光照后处理。
	if Cfg.dev_args().has("--materialshots") and g.at_frames in [40, 65, 90] and g.optical.grains != null:
		var names := ["fx_flam_hit", "fx_water_splash", "fx_corrode_hit"]
		var index: int = int((g.at_frames - 40) / 25)
		var pool = g.optical.grains
		g.fx.clear()   # 仅验收模式：隔离上一组帧条，避免实时模拟步长造成混图
		pool.step(2.0)
		var previous: bool = pool.off
		pool.off = true
		g.vfx.fx_sprite(names[index], g.ppos + Vector2(-90, -50), g.PX)
		pool.off = false
		g.vfx.fx_sprite(names[index], g.ppos + Vector2(90, -50), g.PX)
		pool.off = previous
		print("MATERIALSHOT %s particles=%d optical=%s" % [names[index], pool.pos.size(), g.optical_on])
	# --shots 在平衡模式下也生效（平衡分支会提前 return）：特效连拍用 --balance --nodeath 跳过精英化演出
	if g.mode == g.Mode.BALANCE and g.shot_at.has(g.at_frames) and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_%d.png" % g.at_frames)
		if Cfg.dev_args().has("--clutterlog"):
			_clutter_log()
	# 机器人的手动技能（契约 v2.3：只有主控有手动技能）：就绪且干员自己想放时替玩家按下。
	# 时机由干员的 bot_wants_manual 决定：缺省保命型（主控生命 < bot/manual_hp），乌尔比安 S3 就绪即放
	if g.state == g.S.PLAY:
		for o in g.squad.ops:
			var mi: int = o.manual_index()
			if o.manual_ready(mi) and o.bot_wants_manual(mi):
				o.cast_manual(mi)
				break
	# --relics=id,id… 或 --relics=all（仅 --balance）：开局第 20 帧直接获得这些藏品，冒烟测试藏品效果（docs/35 / docs/36）
	# --maxprog（仅 --balance）：同一帧把编队里每名干员推到成长线末端（精二 + 全部节点），让所有技能与成长钩子都跑一遍
	if g.mode == g.Mode.BALANCE and g.at_frames == 20:
		for a in Cfg.dev_args():
			if a.begins_with("--relics="):
				var want: String = a.substr(9)
				var ids: Array = g.RL.keys() if want == "all" else Array(want.split(","))
				for rid in ids:
					if g.RL.has(rid):
						g.progression.gain_relic(rid)
		if Cfg.dev_args().has("--maxprog"):
			for o in g.squad.ops:
				var guard := 0
				while not o.next_node().is_empty() and guard < 12:
					o.advance("")
					guard += 1
	if Cfg.dev_args().has("--tierdemo") and g.at_frames % 30 == 10 and g.ch != null and g.ch.pos != Vector2.INF:
		# 特效第 2 步对照图：主控面前从左到右同时放一次轻 / 中 / 重命中 + 同档刀光（纯画面，不扣血、不碰随机数）
		for t in [1, 2, 3]:
			var hp: Vector2 = g.ppos + Vector2(-150.0 + 150.0 * (t - 1), -70.0)
			g.vfx.melee_arc(g.ch, hp + Vector2(0, 30), -PI / 2.0, 0.7, 46.0)
			if not g.fx.is_empty() and g.fx[-1].get("kind", "") == "marc":
				g.fx[-1].tier = t
				g.fx[-1].t = -1.0   # 不让同帧命中再改它
				g.fx[-1].op = ""   # 演示刀光固定在原处，不跟主控
			g.vfx._tier_fx({"pos": hp, "r": 14.0}, {"op": g.ch.id}, t)
	if g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--elite2") and g.at_frames == 20:
		# 特效连拍（docs/50 §25 特效处理）：队友直接精二（三个技能都解锁）
		for o in g.squad.ops:
			if o != g.ch:
				var guard := 0
				while not o.next_node().is_empty() and guard < 12:
					o.advance("")
					guard += 1
	if g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--sptest") and g.at_frames % 45 == 0:
		var only := -1
		for a in Cfg.dev_args():
			if a.begins_with("--onlyskill="):
				only = int(a.substr(12))   # 特效连拍：只给队友充第 only 个技能（队长不充）
		for o in g.squad.ops:
			if only < 0:
				o.fill_sp()
			elif o != g.ch and o.skill_unlocked(only):
				o.sp[only] = o.sp_need(only)
	if g.mode == g.Mode.BALANCE:
		if g.trace_every > 0.0 and g.state == g.S.PLAY and int(g.t / g.trace_every) != trace_last:
			trace_last = int(g.t / g.trace_every)
			var hsum := 0.0
			for e in g.enemies:
				hsum += e.pos.x * 0.37 + e.pos.y * 0.11 + e.hp * 0.01
			print("TRACE t=%.2f lv=%d k=%d hp=%.2f n=%d rng=%d/%d/%d/%d/%d pos=%.2f,%.2f h=%.3f" % [g.t, g.level, g.kills, g.hp, g.enemies.size(), g.rng.state,
				g.rng_spawn.state, g.rng_enemy.state, g.rng_drop.state, g.rng_op.state, g.ppos.x, g.ppos.y, hsum])   # 五条玩法流：主 / 刷怪 / 敌人 / 掉落 / 积木（docs/101 B7）
		if g.bot != null and g.state == g.S.PLAY:
			g.telemetry.tick(g.bal_dt)   # 整局指标（原 bot.tick，挪到 run/telemetry.gd）；步长同批跑 --dt
		if false:
			print("dbg t=%d state=%d lv=%d hp=%d en=%d" % [g.t, g.state, g.level, g.hp, g.enemies.size()])
		if g.state == g.S.CHOICE:
			if g.choice_kind == "cross" and g.endg.flipped >= 0:
				return   # 翻面中（有画面时等计时器兑现）
			var pi := bot_pick()
			for a in Cfg.dev_args():
				# --evpick=1 或 --evpick=madness:0,knight_stay:0,default:1
				if a.begins_with("--evpick=") and g.choice_kind == "event":
					var spec: String = a.substr(9)
					if spec.is_valid_int():
						pi = mini(int(spec), g.choices.size() - 1)
					else:
						var evid: String = String(g.choices[0].id).split(":")[0]
						for part in spec.split(","):
							var kv: PackedStringArray = part.split(":")
							if kv.size() == 2 and (kv[0] == evid or kv[0] == "default") and (kv[0] != "default" or not spec.contains(evid + ":")):
								pi = mini(int(kv[1]), g.choices.size() - 1)
			g.progression.pick(pi)
		# 10:00 最终 Boss 登场后给 3 分钟打完（之前 620 秒截断只留 20 秒，胜负基本看不出来）
		if (g.state == g.S.DEAD or g.state == g.S.WIN or g.t > g.bal_maxt) and not bal_done:
			bal_done = true
			if perf_on:
				print("PERF ", JSON.stringify(_perf_summary()))
			if perf_dump != null:
				perf_dump.close()
				perf_dump = null
			print("BALANCE ", JSON.stringify(g.telemetry.record(lv_marks)))   # 整局记录的格式在 run/telemetry.gd（与玩家本地记录同一份）
			print("SPAWNQ ", JSON.stringify(g.spawner.queue_report()))   # 同屏普通怪存活上限的刷怪队列统计（docs/50 §15 B）
			g.get_tree().quit()
		return
	if not (Cfg.dev_args().has("--fxtest") and g.at_frames >= 90 and g.at_frames < 100):
		g.hp = g.max_hp
	if g.lvup_show > 1.05 and g.lvup_show < 1.12 and g.level == 3 and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_lvup.png")
	for a in Cfg.dev_args():
		# --eventtest=<事件 id>：第 30 帧直接弹这件事件（截图 / 文案检查）；--eventtest=cross1 / cross2：直接发路口一 / 二的牌
		if a.begins_with("--eventtest=") and g.at_frames == 30 and g.state == g.S.PLAY:
			var want: String = a.substr(12)
			if want.begins_with("cross"):
				g.endg.enabled = true
				g.endg._checked = true
				g.endg._deal(int(want.substr(5)))
			elif g.endg.ev_by_id.has(want):
				g.endg.open(want)
	if Cfg.dev_args().has("--touchtest") and g.state == g.S.PLAY:
		# 模拟：第 60 帧按下左半屏，拖到右上，第 120 帧松开；第 90 帧截图
		if g.at_frames == 60:
			var tp := InputEventScreenTouch.new()
			tp.index = 0
			tp.pressed = true
			tp.position = Vector2(200, 500)
			Input.parse_input_event(tp)
			touchtest_p0 = g.ppos
		elif g.at_frames > 60 and g.at_frames < 120:
			var td := InputEventScreenDrag.new()
			td.index = 0
			td.position = Vector2(200, 500) + Vector2(1.2, -0.7) * float(g.at_frames - 60)
			Input.parse_input_event(td)
		elif g.at_frames == 120:
			var tr := InputEventScreenTouch.new()
			tr.index = 0
			tr.pressed = false
			tr.position = Vector2(272, 458)
			Input.parse_input_event(tr)
			print("TOUCHTEST moved=%s" % str((g.ppos - touchtest_p0).round()))
		if g.at_frames == 90 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_touch.png")
		if g.at_frames == 130:
			g.get_tree().quit()
	# --killshot（docs/130 C5 击杀观感对比）：第 360 帧在队长下方排一行 8 只怪（开场横幅已退）、同帧击杀，之后按 KILL_SHOTS 帧截 shot_kill_<帧>.png 并退出
	if Cfg.dev_args().has("--killshot"):
		if g.at_frames >= 300:
			g.speed = 0.0   # 队长定住，镜头不动
		if g.at_frames == 360:
			for o in g.enemies:
				o.pos += Vector2(4000, 0)   # 其余怪挪出画面（截图摆拍）
			var row: Array = []
			for i in KILL_TYPES.size():
				var e: Dictionary = g.spawner.spawn_enemy(KILL_TYPES[i], g.ppos + Vector2(-224 + i * 64, 70))
				e.hidden = false
				row.append(e)
			_kill_row = row
		if g.at_frames == 366:
			for e in _kill_row:
				if not e.get("dead", false):
					g.combat.kill(e)
		if g.at_frames - 366 in KILL_SHOTS and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_kill_%02d.png" % (g.at_frames - 366))
		if g.at_frames - 366 > KILL_SHOTS[-1]:
			g.get_tree().quit()
	# --fgshot（docs/130 A3 前景剪影对照）：第 60 帧起每 20 帧把队长挪到下一处取景点并截 shot_fg_<n>.png，8 处后退出
	if Cfg.dev_args().has("--fgshot"):
		if g.at_frames >= 60 and (g.at_frames - 60) % 20 == 0:
			var n: int = (g.at_frames - 60) / 20
			if n > 0 and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fg_%d.png" % n)
			if n >= 8:
				g.get_tree().quit()
			else:
				g.ppos = g.map.push_out(Vector2(1500 + n * 430, 900 + (n % 3) * 380), 12.0)
				g.cam.position = g.ppos
	# --worldspec（world_spec_1024 接入验收）：第 60 帧在队长周围摆 溟痕 ×3（大中小）、商人、经验结晶大小各几颗、无人机、黑潮圈边，
	# 第 100 帧截 shot_ws_scene.png；第 101 帧让两块溟痕播退散，第 104 / 110 帧截 shot_ws_dissolve_<帧>.png，之后退出
	if Cfg.dev_args().has("--worldspec"):
		if g.at_frames >= 60:
			g.speed = 0.0
			g.hp = g.max_hp
			g.pickup = 0.0   # 结晶留在地上（不吸、不升级）
		if g.at_frames == 60:
			g.ppos = g.map.push_out(Vector2(1500, 900), 12.0)
			g.cam.position = g.ppos
			for o in g.enemies:
				o.pos += Vector2(4000, 0)
			g.mires.clear()
			for q in [[Vector2(-330, -120), 110.0], [Vector2(-170, 150), 70.0], [Vector2(230, -170), 40.0]]:
				g.mires.append({"pos": g.ppos + q[0], "r": q[1], "maxr": q[1], "life": 999.0, "seed": 1.7})
			g.merchant = {"pos": g.ppos + Vector2(150, 70), "life": 60.0, "near": false}
			for k in 10:
				g.pickups.drop(g.ppos + Vector2(-60 + (k % 5) * 26, 120 + (k / 5) * 26), "xp", 8.0 if k % 3 == 0 else 1.0)
			g.drones.append({"pos": g.ppos + Vector2(70, -60), "cd": 99.0, "ang": 0.0, "beam": 0.0, "face": 1.0})
			g.zone_c = g.ppos + Vector2(-200, 0)
			g.zone_r = 560.0   # 队长在安全区内，圈边从画面右侧穿过
			g.zone_state = 3
			g.zone_t = -999.0
		if g.at_frames == 100 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_ws_scene.png")
		if g.at_frames == 101:
			var pts: Array = []
			for mm in g.mires.slice(0, 2):
				pts.append([mm.pos, mm.r])
			g.mires = g.mires.slice(2)
			g.fx.append({"kind": "mire_recoil", "pts": pts, "from": g.ppos, "life": 0.75, "max": 0.75, "tex": true})
		if g.at_frames in [104, 110] and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_ws_dissolve_%d.png" % g.at_frames)
		if g.at_frames > 112:
			g.get_tree().quit()
	# --gpuprobe（docs/136 §2 排查，10-24）：第 360 帧（低分辨率层早已打开）才往世界节点下挂两个持续发射的 GPUParticles2D
	# （红：game 直接子节点；绿：再套一层 Node2D），第 400 帧截 shot_gpu.png 并列出世界子树里各画布的可见层后退出
	if Cfg.dev_args().has("--gpuprobe"):
		g.pickup = 0.0   # 不拾取、不升级（升级面板会暂停并盖住画面）
		if g.at_frames >= 340:
			g.speed = 0.0
		g.hp = g.max_hp
		if g.at_frames == 360:
			var holder := Node2D.new()
			holder.name = "probe_holder"
			g.add_child(holder)
			for k in 2:
				var p := GPUParticles2D.new()
				p.name = "probe_gpu_%d" % k
				p.amount = 64
				p.lifetime = 2.0
				p.local_coords = false
				var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
				img.fill(Color.WHITE)
				p.texture = ImageTexture.create_from_image(img)
				var m := ParticleProcessMaterial.new()
				m.gravity = Vector3.ZERO
				m.spread = 180.0
				m.initial_velocity_min = 10.0
				m.initial_velocity_max = 30.0
				m.scale_min = 3.0
				m.scale_max = 3.0
				p.process_material = m
				p.modulate = Color(2.0, 0.2, 0.2) if k == 0 else Color(0.2, 2.0, 0.2)
				(g if k == 0 else holder).add_child(p)
				p.global_position = g.ppos + Vector2(-90 if k == 0 else 90, -60)
				p.process_mode = Node.PROCESS_MODE_ALWAYS
				p.emitting = true
		if g.at_frames == 400:
			var rows: Array = []
			var stack: Array = [[g, 0]]
			while not stack.is_empty():
				var it: Array = stack.pop_back()
				for c in (it[0] as Node).get_children():
					if c is CanvasLayer:
						continue
					if c is CanvasItem and int(it[1]) >= 1:
						rows.append("%s:%s:L%d" % [c.get_parent().name, c.name, (c as CanvasItem).visibility_layer])
					stack.append([c, int(it[1]) + 1])
			print("GPUPROBE lo=%s nested=%s" % [str(g.get("optical_lo")), str(rows)])
			for pn in ["probe_gpu_0", "probe_holder/probe_gpu_1"]:
				var pp: GPUParticles2D = g.get_node_or_null(pn)
				if pp != null:
					print("GPUPROBE %s emit=%s vis=%s gpos=%s ppos=%s cam=%s layer=%d g_layer=%d" % [pn, pp.emitting, pp.is_visible_in_tree(), pp.global_position.round(), g.ppos.round(), g.cam.get_screen_center_position().round(), pp.visibility_layer, g.visibility_layer])
			if DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_gpu.png")
			g.get_tree().quit()
	if Cfg.dev_args().has("--gemshot"):
		if g.at_frames == 60:
			for k in 14:
				g.pickups.drop(g.ppos + Vector2.from_angle(TAU * k / 14.0) * 150.0, "xp", 8.0 if k % 4 == 0 else 1.0)
			g.pickups.drop(g.ppos + Vector2(60, -40), "xp", 1.0)
		if g.at_frames in [72, 100] and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_gem_%d.png" % g.at_frames)
			if g.at_frames == 100:
				g.get_tree().quit()
	if Cfg.dev_args().has("--relicshot"):
		if g.at_frames == 30:
			g.pending_chests = 1
			g.ingots = 40
		if g.at_frames == 400:
			g.merchant = {"pos": g.ppos, "life": 60.0, "near": false}
			g.shop_sys.open()
		if g.at_frames == 440 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_shop.png")
			g.get_tree().quit()
	if g.state == g.S.CHOICE:
		choice_wait += 1
		var cshots: bool = Cfg.dev_args().has("--choiceshots")   # 等卡片全部翻面再截，选卡也相应推迟
		if choice_wait == 90 and cshots and DisplayServer.get_name() != "headless":
			choice_n += 1
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_choice_%d.png" % choice_n)
		if choice_wait == 40 and not choice_shot and DisplayServer.get_name() != "headless" and (g.choice_kind == "relic" or not Cfg.dev_args().has("--relicshot")):
			choice_shot = true
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_choice.png")
		if choice_wait > (95 if cshots else 45):
			choice_wait = 0
			# 机器人像真人一样偏好干员深度 / 精英化卡（70%），其余均匀随机（满员招募卡按 bot/swap，缺省不选；更换画面选「不替换」）
			var ok_i: Array = g.progression.auto_choices()
			var deep: Array = []
			for ci in ok_i:
				if g.choices[ci].kind == "prog":
					deep.append(ci)
			if g.choice_kind == "cross" and g.endg.flipped >= 0:
				pass   # 翻面中：等计时器兑现
			elif g.choice_kind == "cross" or g.choice_kind == "event":
				g.progression.pick(g.endg.bot_choice())   # 翻节点卡与事件：按路线选（docs/154，--route）
			elif g.choice_kind == "swap":
				g.progression.pick(g.progression.auto_swap_pick())
			elif not deep.is_empty() and g.rng.randf() < 0.7:
				g.progression.pick(deep[g.rng.randi() % deep.size()])
			else:
				g.progression.pick(ok_i[g.rng.randi() % ok_i.size()])
	if g.at_frames % 1200 == 0:
		print("t=%d lv=%d E%d hp=%d enemies=%d mires=%d kills=%d lamp=%d growth=%s relics=%s squad=%s fps=%d" % [g.t, g.level, g.ch.elite, g.hp, g.enemies.size(), g.mires.size(), g.kills, g.lamp, g.growth, g.relics, g.squad.ops.map(func(o): return "%s%d/%d" % [o.id, o.elite, o.prog]), Engine.get_frames_per_second()])
	for bb in g.bosses:
		if not bb.dead and not bb.invuln and not bosstest and _fr_spawn == "":
			bb.hp -= 4.0 if bosstest else 40.0
			if bb.hp <= 0.0:
				g.combat.kill(bb)
	for a in Cfg.dev_args():
		# --winshot=deep：第 60 帧直接进入胜利结算并截图
		if a.begins_with("--winshot=") and g.at_frames == 60:
			winshot = true
			g.ending = a.substr(10)
			g.endg.cur = g.ending
			g.ending_new = true
			g.state = g.S.WIN
		if a.begins_with("--winshot=") and g.at_frames == 130 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_win.png")
			g.get_tree().quit()
	# --huntshot（docs/109 §12、docs/124 寻访演出截图）：配 --roster=start5 --rostertickets=1,1,1。第 60 帧进胜利结算，
	# 之后依次截 入口 → 定向选职业 → 指定干员 → 拉包 → 揭示 → 本次寻访 → 回入口，存 shot_hunt_<n>.png；无头只走流程。
	# 演出按帧计时（headhunt.clock_frames）。另加 --huntrec：从入口起每 2 帧存一张 rec_<n>.png（30 fps 录屏），到本次寻访约 1.3 秒后退出
	if Cfg.dev_args().has("--huntshot"):
		if g.at_frames == 60:
			winshot = true
			preload("res://scripts/screens/headhunt.gd").clock_frames = true
			g.ending = "standard"
			g.endg.cur = g.ending
			g.state = g.S.WIN
			g.meta_result = preload("res://scripts/core/meta.gd").run_reward(g, true)   # 结算面板的「生机细胞」行（截图用）
		if Cfg.dev_args().has("--rostertickets=0,0,0") and g.at_frames == 100 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_result_meta.png")   # 没有券：直接截结算面板
			g.get_tree().quit()
		var shoot := DisplayServer.get_name() != "headless"
		# 新流程（10-22，单一寻访凭证）：入口 → 定向寻访 → 选职业 → 指定干员 → 拉包 → 揭示 → 本次寻访；[帧, 动作]，动作在截图之后执行
		var acts := {120: "directed", 170: "ok", 220: "ok"}
		if Cfg.dev_args().has("--huntrec"):
			if g.at_frames >= 56 and (g.at_frames - 56) % 2 == 0:
				if shoot:
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/rec_%04d.png" % ((g.at_frames - 56) / 2))
				if g.headhunt.mode == "summary":
					hunt_rec_end += 1
					if hunt_rec_end > 40:
						print("HUNTREC frames=%d" % ((g.at_frames - 56) / 2))
						g.get_tree().quit()
			if acts.has(g.at_frames):
				if g.at_frames == 170 and Cfg.dev_args().has("--huntgold"):   # 金档录屏：定向选一个还没有人的职业（近卫）
					g.headhunt.sel = g.headhunt.CLASS_ORDER.find("近卫")
				g.headhunt._act(acts[g.at_frames])
		else:
			var steps := [[110, "directed"], [160, "ok"], [210, "ok"], [270, null], [480, "skip"], [510, "ok"], [540, ""]]
			for k in steps.size():
				if g.at_frames == steps[k][0]:
					if shoot:
						g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_hunt_%d.png" % k)
					print("HUNTSHOT %d mode=%s reveal=%s open=%s vouchers=%d" % [k, g.headhunt.mode, g.headhunt.reveal_id, g.headhunt.open, int(Cfg.roster_tickets.get("hunt", 0))])
					var act = steps[k][1]
					if act is String and act == "":
						g.get_tree().quit()
					elif act != null:
						g.headhunt._act(act)
	# --akmock=<屏>（docs/125 结算 / 寻访静态样张）：第 20 帧盖一层样张画布，第 60 帧截 shot_akmock.png 退出
	for da in Cfg.dev_args():
		if str(da).begins_with("--akmock="):
			if g.at_frames == 20:
				var mk = preload("res://scripts/screens/ak_mock.gd").new()
				mk.g = g
				mk.which = str(da).substr(9)
				mk.size = g.hud.size
				g.hud.add_child(mk)
			if g.at_frames == 60:
				if DisplayServer.get_name() != "headless":
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_akmock.png")
				g.get_tree().quit()
	# --sptest：每 2 秒把全队技力充满（截图 / 观察技能特效用）
	if Cfg.dev_args().has("--sptest") and g.at_frames % 120 == 0:
		for o in g.squad.ops:
			o.fill_sp()
	if g.shot_at.has(g.at_frames) and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_%d.png" % g.at_frames)
	if bosstest and g.at_frames > 610 and bm_boss.is_empty() and ba_boss.is_empty():   # --bossmoves / --bossacts 自己数、放完才退
		g.get_tree().quit()
	if (g.state == g.S.WIN and not winshot) or g.at_frames > 14000:
		print("AUTOTEST END state=%d t=%d" % [g.state, g.t])
		g.get_tree().quit()


## --bossacts=<type>[+<搭档>]（docs/142b §9 逐幕演示，tools/probes/boss_act_gifs.py 拼 gif）：第 20 帧在队长右侧刷出 Boss（伊莎玛拉直接变身、
## 伊祖米克直接扎根），按自己的 AI 出招；每 boss/acts_demo_len（7）秒把血放到下一道刻度并过卡点，最后一幕放满后退出。
## 队长不死、绕圈慢走，Boss 血不低于当前刻度（自动攻击照打，打不进下一幕）；第 30 帧起每 3 帧截一张 shot_acts_<tag>_<帧>.png
func _bossacts_step(spec: String) -> void:
	var act_len: float = Bal.v("boss/acts_demo_len", 7.0)
	if g.at_frames == 20:
		var parts: PackedStringArray = spec.split("+")
		g.ppos = Vector2(1500, 900)
		g.max_hp = 900.0
		g.hp = 900.0
		g.t = 150.0
		g.hunt.state = 3   # 「围猎」（约 1:30）不在演示里触发：时间直接跳到 2:30 会让包围圈和 Boss 同场（正式局 Boss 最早 3:30，碰不到）
		var b := g.spawner.spawn_enemy(parts[0], g.ppos + Vector2(260, -40))
		b.age = 5.0
		g.bosses.append(b)
		g.boss = b
		if g.final_boss == null and g.spawner.is_final_boss_type(b.type):
			g.final_boss = b
		if parts.size() > 1:
			var m := g.spawner.spawn_enemy(parts[1], g.ppos + Vector2(-260, -60))
			m.age = 5.0
			b.partner = m
			m.partner = b
			g.bosses.append(m)
			ba_mate = m
		if b.type in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(b)
			b.invuln = false
		ba_boss = b
		ba_next = g.t + act_len
		print("BOSSACTS %s gates=%s" % [spec, str(b.get("gates", []))])
		return
	if g.at_frames < 20 or ba_boss.is_empty():
		return
	g.hp = g.max_hp
	# 队长绕 (1500, 900) 半径 230 慢走（约 100 像素 / 秒）：站着不动时 Boss 会贴脸近战，远程招和主轴画面（火线、路线）都看不到
	g.ppos = Vector2(1500, 900) + Vector2.from_angle((g.t - 150.0) * 0.45) * 230.0
	# 演示只看 Boss 自己：普通波次的杂兵每帧清掉（不掉经验、不计击杀）；机制小怪（部件、连线海嗣、幻影、子代、分形、骑士重生波）留着
	for o in g.enemies:
		if not o.dead and not o.boss and not o.chest and not o.get("part", false) and not o.has("web_of") and not o.has("decoy_of") and not o.feed and not o.get("song_eye", false) and not o.has("izu_dir") and o.type != "fractal" and o.age > 0.05 and not o.has("ba_keep"):
			o.dead = true
	for e in [ba_boss, ba_mate]:
		if e.is_empty() or e.dead:
			continue
		var gl: Array = e.get("gates", [])
		e.hp = maxf(e.hp, e.maxhp * ((float(gl[0]) + 0.02) if not gl.is_empty() else 0.12))
	if g.t >= ba_next:
		ba_next = g.t + act_len
		var passed := false
		for e in [ba_boss, ba_mate]:
			if e.is_empty() or e.dead or e.get("gates", []).is_empty():
				continue
			e.hp = e.maxhp * float(e.gates[0])
			g.combat.gate_pass(e)
			passed = true
		print("BOSSACTS gate t=%.1f passed=%s phase=%d" % [g.t, str(passed), int(ba_boss.phase)])
		if not passed:
			for k in ["a", "b"]:
				var v: Array = ba_ft[k]
				if v.size() > 10:
					v.sort()
					print("BOSSACTS PERF %s n=%d p50=%.2f p95=%.2f ms" % [k, v.size(), v[v.size() / 2] / 1000.0, v[int(v.size() * 0.95)] / 1000.0])
			print("BOSSACTS END %s" % spec)
			g.get_tree().quit()
			return
	if g.at_frames % 60 == 0:
		print("BOSSACTS state t=%.1f %s" % [g.t, _ba_state(ba_boss)])
	_ba_perf()
	if g.at_frames >= 30 and g.at_frames % 3 == 0 and DisplayServer.get_name() != "headless" and not Cfg.dev_args().has("--noshots"):
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_acts_%s_%04d.png" % [spec.replace("+", "_"), g.at_frames])


## --bossacts 帧时（协调人 10-25：每只 Boss 改完同局轮换量 P50 / P95）：记上一帧到这一帧的真实用时，按上一帧所用画法分桶；
## 轮换（--perfab=N，每 N 帧切 g.perf_alt）后的头 2 帧不记（切换那一帧混着两种画法）
var ba_sw := 0
func _ba_perf() -> void:
	var ab: int = 0
	for a in Cfg.dev_args():
		if a.begins_with("--perfab="):
			ab = int(a.substr(9))
	if ab <= 0:
		return
	var now: int = Time.get_ticks_usec()
	if ba_us > 0 and g.at_frames - ba_sw > 2 and g.at_frames > 80:
		ba_ft["b" if g.perf_alt else "a"].append(now - ba_us)
	ba_us = now
	if g.at_frames % ab == 0:
		g.perf_alt = not g.perf_alt
		ba_sw = g.at_frames


## 演示日志：主轴状态的个数（火线 / 路线 / 幻影 / 网 / 泪 / 子代 / 强化层 / 冰柱 / 同步护盾），核对 gif 里该出现的东西有没有出现
func _ba_state(e: Dictionary) -> String:
	var out: Array = ["act=%d" % int(e.get("gates_passed", 0)), "phase=%d" % int(e.phase)]
	for k in ["fire_lines", "paths", "stakes", "batch", "eyes"]:
		if e.has(k):
			out.append("%s=%d" % [k, e[k].size()])
	for k in ["web_n", "izu_stacks", "absorb_n", "pair_shield", "drop_until", "aura_off_until", "kcold", "brk_label"]:
		if e.has(k):
			out.append("%s=%s" % [k, str(e[k])])
	if g.has_meta("boss_decoys"):
		out.append("decoys=%d" % g.get_meta("boss_decoys").size())
	return " ".join(out)


## --bossmoves=<type>[2]：逐招验收（docs/95 §12）。主控不动（autotest 模式没有移动输入），每招：force_move → 预警 60% 截图 → 结算后 8 帧截图
func _bossmoves_step(spec: String) -> void:
	var headless: bool = DisplayServer.get_name() == "headless"
	if g.at_frames == 20:
		bm_tag = spec
		var parts: PackedStringArray = spec.split("+")
		var type: String = parts[0].trim_suffix("2")
		g.ppos = Vector2(1500, 900)
		g.max_hp = 900.0
		g.hp = 900.0
		g.t = 150.0
		var b := g.spawner.spawn_enemy(type, g.ppos + Vector2(230, -40))
		b.age = 5.0
		if parts[0].ends_with("2"):
			g.bai.setup_preview_phase2(b)
			b.invuln = false
			b.channel = 0.0
		g.bosses.append(b)
		g.boss = b
		if g.final_boss == null and g.spawner.is_final_boss_type(b.type):
			g.final_boss = b
		bm_boss = b
		if parts.size() > 1:
			var m := g.spawner.spawn_enemy(parts[1], g.ppos + Vector2(-200, -60))
			m.age = 5.0
			b.partner = m
			m.partner = b
			g.bosses.append(m)
			bm_mate = m
		var h = g.bai.boss(type)
		bm_list = h.demo_moves(b) if h != null else []
		bm_next_t = g.t + 1.0
		print("BOSSMOVES %s moves=%s" % [spec, str(bm_list)])
		return
	if g.at_frames < 20 or bm_boss.is_empty():
		return
	var e: Dictionary = bm_boss
	e.hp = e.maxhp if e.phase == 1 or e.type != "knight_boss" else e.maxhp * 0.5   # 别让它死；骑士二阶段保持重生血量
	if not bm_mate.is_empty():
		bm_mate.hp = bm_mate.maxhp
		bm_mate.wind = maxf(bm_mate.get("wind", 0.0), 0.5)   # 搭档只当「统一」的另一端，不出招
		if bm_state == "idle":
			bm_mate.pos = g.ppos + Vector2(-200, -60)
	var mine: Array = g.warns.filter(func(w): return is_same(w.owner, e))
	match bm_state:
		"idle":
			if bm_i >= bm_list.size():
				if g.at_frames % 10 == 0:
					print("BOSSMOVES END %s shots=%d" % [bm_tag, bm_i])
					g.get_tree().quit()
				return
			if g.t < bm_next_t or not mine.is_empty():
				return
			e.wind = 0.0
			e.cdt = 0.0
			e.stun = 0.0
			e.break_t = 0.0
			e.dash_t = 0.0
			e.kb = Vector2.ZERO
			e.kb_self = false
			e.pos = g.ppos + Vector2(230, -40)   # 每招都从主控右上 230 处放，截图里本体和预警都在画面内（冲锋 / 迫近会把它带远）
			var name: String = str(bm_list[bm_i])
			var dir: Vector2 = (g.ppos - e.pos).normalized()
			if g.bai.boss(e.type).force_move(e, name, dir, e.pos.distance_to(g.ppos)):
				bm_state = "warn"
				bm_shot = false
				print("BOSSMOVES fire %s" % name)
			else:
				print("BOSSMOVES skip %s" % name)
				bm_i += 1
		"warn":
			var prog := 0.0
			var any_done := false
			for w in mine:
				prog = maxf(prog, w.t / w.dur)
				any_done = any_done or w.done
			if mine.is_empty():
				any_done = true
			if prog >= 0.6 and not bm_shot and not any_done:
				bm_shot = true
				if not headless:
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossmove_%s_%s.png" % [bm_tag, str(bm_list[bm_i])])
			if any_done:
				bm_state = "hit"
				bm_hit_at = g.at_frames + 8
		"hit":
			if g.at_frames >= bm_hit_at:
				if not headless:
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossmove_%s_%s_hit.png" % [bm_tag, str(bm_list[bm_i])])
				bm_i += 1
				bm_state = "idle"
				bm_next_t = g.t + 2.5   # 等连发 / 冲刺 / 冲击环都收完再放下一招


## 平衡测试用的简单 AI：躲开贴身的敌人、保持在挥伞距离、捡掉落物
func bot_move() -> Vector2:
	var push := Vector2.ZERO
	var nearest_d := 99999.0
	var nearest_p := g.ppos
	for j in g.enemies_sys.query(g.ppos, 220.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var d: Vector2 = g.ppos - e.pos
		var l := d.length()
		if l < nearest_d:
			nearest_d = l
			nearest_p = e.pos
		var danger: float = 48.0 + e.r
		if l < danger and l > 0.01:
			push += d / l * (danger - l) / danger * (3.0 if (e.elite or e.boss) else 1.0)
		# 远程怪：像真人一样不站在它射程里干等（保持在它射程外沿）
		if e.ai == "ranged" and not e.boss and l > 0.01 and l < e.range + 20.0:
			push += d / l * 0.6
	# 低血量：远离敌群重心，先活下来再打
	if g.hp < g.max_hp * 0.5:
		var cen := Vector2.ZERO
		var cn := 0
		for j in g.enemies_sys.query(g.ppos, 320.0):
			var e2: Dictionary = g.enemies[j]
			if not e2.dead:
				cen += e2.pos
				cn += 1
		if cn > 0:
			var away: Vector2 = g.ppos - cen / cn
			if away.length() > 1.0:
				push += away.normalized() * (1.6 if g.hp < g.max_hp * 0.3 else 0.9)
	# 躲开招式预警、溟痕与敌方弹幕（让自测更接近真人）
	for w in g.warns:
		if w.done:
			continue
		var dv: Vector2 = g.ppos - w.pos
		if w.shape == "circle" and dv.length() < w.r + 30.0:
			push += (dv.normalized() if dv.length() > 1.0 else Vector2.RIGHT) * 1.4
		elif w.shape == "line":
			var b2: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			var cp: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos, w.pos, b2)
			if cp.distance_to(g.ppos) < w.wid + 40.0:
				var away: Vector2 = g.ppos - cp
				push += (away.normalized() if away.length() > 1.0 else Vector2.from_angle(w.ang).orthogonal()) * 1.4
		elif w.shape == "cone" and dv.length() < w.r + 30.0:
			push += dv.normalized() * 1.4
	for m in g.mires:
		var dm: Vector2 = g.ppos - m.pos
		if dm.length() < m.r + 24.0:
			push += dm.normalized() * 2.0
	for bl in g.ebullets:
		if bl.life <= 0.0 or bl.pos.distance_to(g.ppos) > 170.0:
			continue
		var toward: Vector2 = (g.ppos - bl.pos)
		if bl.vel.dot(toward) <= 0.0:
			continue
		# 只躲会打到自己的子弹：算它的直线路径离自己多近，往远离路径的一侧闪
		var vdir: Vector2 = bl.vel.normalized()
		var along: float = toward.dot(vdir)
		var side: Vector2 = toward - vdir * along
		var miss: float = side.length()
		if miss < bl.r + 40.0:
			var sdir: Vector2 = side.normalized() if miss > 1.0 else vdir.orthogonal()
			var urgency: float = clampf(1.0 - along / 170.0, 0.3, 1.0)
			push += sdir * 1.6 * urgency
	var pull := Vector2.ZERO
	var best := 260.0
	for g_item in g.gems:
		if g_item.kind == "pack" and g.hp > g.max_hp * Bal.v("crate/bot_below", 0.75):
			continue   # 应急补给：残血才去捡（docs/133 §6）
		var gd: float = g_item.pos.distance_to(g.ppos)
		var w: float = gd * (0.4 if (g_item.kind == "oil" and g.lamp < 60.0) or g_item.kind == "chest" or g_item.kind == "pack" else 1.0)
		if w < best:
			best = w
			pull = (g_item.pos - g.ppos).normalized() * 0.7
	if g.hp > g.max_hp * 0.5:
		for bb in g.bosses:
			if not bb.dead and not bb.invuln and bb.pos.distance_to(g.ppos) > 90.0:
				pull = (bb.pos - g.ppos).normalized() * 0.8
				break
	if not g.merchant.is_empty() and g.merchant.pos.distance_to(g.ppos) < 500.0 and not g.merchant.near:
		pull = (g.merchant.pos - g.ppos).normalized() * 0.9
	for e in g.enemies:
		if e.chest and not e.dead and e.pos.distance_to(g.ppos) < 400.0:
			pull = (e.pos - g.ppos).normalized() * 0.8
			break
	# 引航灯标：没点燃、血量还行就过去站着（光圈半径 70，站到离中心 40 以内就不再拉，免得来回抖）
	for b in g.beacons:
		if not b.lit and g.hp > g.max_hp * 0.45 and b.pos.distance_to(g.ppos) < 700.0:
			pull = (b.pos - g.ppos).normalized() * 0.9 if b.pos.distance_to(g.ppos) > 40.0 else Vector2.ZERO
			break
	if pull == Vector2.ZERO and nearest_d > 100.0 and nearest_d < 99999.0 and g.hp > g.max_hp * 0.4:
		pull = (nearest_p - g.ppos).normalized() * 0.5
	var mv := push * 2.2 + pull
	# 缩圈：靠近圈边时往圈内走
	if g.zone_state != 0:
		var zc: float = g.ppos.distance_to(g.zone_c)
		var target_c: Vector2 = g.zone_next_c if g.zone_state == 1 else g.zone_c
		var target_r: float = g.zone_next_r if g.zone_state == 1 else g.zone_r
		var od: float = zc - g.zone_r
		if od > -30.0:
			# 已贴圈边 / 出圈：真人会先回圈。敌群的「往外推」只留侧向分量（侧身绕过去；溟痕在后面单独加，照样绕开），经验 / 商人等拉力朝外的不跟，
			# 回圈拉力随出圈距离加大；出圈超过 0.5 秒且冲刺好了就朝圈心冲（2026-09-27：v11-ab 黑潮死亡多是普通机器人被怪群推在圈外，
			# 实测圈外 165–196 像素、怪群推力 −2.6…−4.8 压过固定的 3.0 回圈拉力）
			var toc: Vector2 = (g.zone_c - g.ppos).normalized()
			var rad: float = mv.dot(toc)
			if rad < 0.0:
				mv -= toc * rad
			mv += toc * (3.0 + clampf(od / 50.0, 0.0, 4.0))
			if od > 0.0:
				if zone_out_since < 0.0:
					zone_out_since = g.t
				elif g.t - zone_out_since > 0.5 and g.dash_ready():
					want_dash = true
			else:
				zone_out_since = -1.0
		else:
			zone_out_since = -1.0
			if g.ppos.distance_to(target_c) > target_r - 160.0 or zc > g.zone_r - 160.0:
				mv += (target_c - g.ppos).normalized() * 3.0
	# 溟痕：像真人玩家一样绕开（在里面时全力往外走）；放在回圈之后，回圈时也照样绕开（2026-09-27：放在前面时外推被回圈一起削掉，机器人直穿圈边溟痕，溟痕 / 侵蚀死亡变多）
	for m in g.mires:
		var md: Vector2 = g.ppos - m.pos
		var ml := md.length()
		if ml < m.r + 50.0 and ml > 0.01:
			mv += md / ml * (2.5 if ml < m.r else 1.2)
	if mv.length() < 0.15:
		mv = Vector2.from_angle(g.t * 0.3) * 0.3
	return mv


func _sfx_win() -> void:
	sfx_win_t = floorf(g.t / 30.0) * 30.0
	var d := {}   # 音名 -> [请求, 实播]
	for n in Sfx.sfx_by:
		var pr: Array = sfx_win_prev.get(n, [0, 0])
		var k: int = int(Sfx.sfx_by[n][0]) - int(pr[0])
		if k > 0:
			d[n] = [k, int(Sfx.sfx_by[n][1]) - int(pr[1])]
		sfx_win_prev[n] = [int(Sfx.sfx_by[n][0]), int(Sfx.sfx_by[n][1])]
	print("SFXWIN t=%d %s" % [int(sfx_win_t), JSON.stringify(d)])
	print("SFXOP t=%d %s" % [int(sfx_win_t), JSON.stringify(Sfx.sfx_op)])   # 累计：干员动作 -> 实际文件 / 音量 / 音高


func _perf_sample() -> void:
	var rid: RID = g.get_viewport().get_viewport_rid()
	if not perf_on:
		perf_on = true
		RenderingServer.viewport_set_measure_render_time(rid, true)
		for a in Cfg.dev_args():
			if a == "--perfmin":
				perf_min = true
			elif a.begins_with("--perfab="):
				perf_ab = int(a.substr(9))
			elif a == "--perfline":
				perf_line = true
			elif a.begins_with("--perfdump="):
				perf_dump = FileAccess.open(a.substr(11), FileAccess.WRITE)
				if perf_dump != null:
					perf_dump.store_line("frame,t,ft,rcpu,gpu,alt,steps,en,bul,ebul,fx,texts,gems,warns,mires,boss,final,dcalls,objs," + ",".join(PERF_DUMP_KEYS))
	var now := Time.get_ticks_usec()
	if perf_last > 0 and g.state == g.S.PLAY and not A_.late_log:
		A_.late_log = true
	if perf_last > 0 and g.state == g.S.PLAY and (g.rt_from < 0.0 or g.realtime):   # --rtfrom：快进段不记
		var w := "0-8" if g.t < 480.0 else ("8-10" if g.t < 600.0 else "10+")
		if perf_min:
			w = "m%02d" % int(g.t / 60.0) + ("F" if g.final_boss != null and not g.final_boss.dead else "")   # --perfmin：按游戏分钟分段，F = 最终 Boss 在场
		if partab > 0:
			w += "/p1" if g.optical.particles.active else "/p0"
		if matab > 0:
			w += "/m0" if g.optical.grains.mat_off else "/m1"
		if grainab > 0:
			w += "/g0" if g.optical.grains.off else "/g1"
		if stackab > 0:
			w += "/sx" if g.at_frames - stack_sw <= 3 else "/s%d" % (g.optical.ab_mask | (128 if Cfg.render_scaled else 0))   # 采样在轮换之前：记的是上一帧所用掩码
		if tierab > 0:
			w += "/t0" if g.vfx.tier_off else "/t1"   # --tierab：上一帧的命中三档开关
		if fx1ab > 0:
			w += "/fx1" if g.optical.fx1 else "/fx0"   # --fx1ab：上一帧的特效处理开关（轮换在采样之后）
		if opticalab > 0:
			w += "/opt" if g.optical_on else "/base"   # --opticalab：上一帧是否在光学观感下画的（轮换在采样之后）
		if vfxab > 0:
			w += "/on" if g.vfx.p2 else "/off"   # --vfxab：上一帧是在哪个模式下画的（轮换在采样之后）
		if Dc.ab_every > 0:
			w += "/d0" if Dc.ab_alt else "/dN"   # --clutterab：上一帧按哪一档画的（轮换在采样之后）
		if _optab > 0:
			w += "/old" if g.opt_old != 0 else "/new"   # --optab：这一帧（上一帧的模拟与绘制）走的是旧 / 新实现
		if perf_ab > 0:
			w += "/b" if g.perf_alt else "/a"   # --perfab：上一帧是在哪个实现下跑的（轮换在采样之后）
		if not perf.has(w):
			perf[w] = {"ft": PackedFloat32Array(), "rcpu": PackedFloat32Array(), "gpu": PackedFloat32Array(), "en": PackedInt32Array(), "dc": PackedInt32Array(), "stage": {}, "slow_stage": {}, "slow_n": 0,
				"sfx0": _sfx_snap(), "fps40": 0}
		var d: Dictionary = perf[w]
		d.ft.append((now - perf_last) / 1000.0)
		d.rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		d.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		d.en.append(g.enemies.size())
		d.dc.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))   # 上一帧的绘制调用数
		if (now - perf_last) > 25000:
			d.fps40 += 1   # 帧时间 > 25 毫秒（低于 40 fps）
		var ft: float = (now - perf_last) / 1000.0
		var br := {}
		if g.prof_on:
			for k in g.prof:
				var v: int = int(g.prof[k]) - int(perf_prev.get(k, 0))
				if v > 0:
					br[k] = v / 1000.0
					d.stage[k] = float(d.stage.get(k, 0.0)) + v / 1000.0
					if ft >= 33.3:
						d.slow_stage[k] = float(d.slow_stage.get(k, 0.0)) + v / 1000.0
		if perf_dump != null:
			var row := PackedStringArray([str(g.at_frames), str(snappedf(g.t, 0.01)), str(snappedf(ft, 0.01)),
				str(snappedf(RenderingServer.viewport_get_measured_render_time_cpu(rid), 0.01)), str(snappedf(RenderingServer.viewport_get_measured_render_time_gpu(rid), 0.01)),
				str(int(g.perf_alt) + 2 * int(g.opt_old != 0)), str(g.upd_n - perf_upd), str(g.enemies.size()), str(g.bullets.size()), str(g.ebullets.size()), str(g.fx.size()), str(g.texts.size()),
				str(g.gems.size()), str(g.warns.size()), str(g.mires.size()), str(g.bosses.size()), str(int(g.final_boss != null and not g.final_boss.dead)),
				str(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))), str(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))])
			for k in PERF_DUMP_KEYS:
				row.append(str(snappedf(float(br.get(k, 0.0)), 0.01)))
			perf_dump.store_line(",".join(row))
		if perf_line:
			# --perfline：逐帧「帧号,游戏秒,帧时,敌人数,最终 Boss 在场,绘制调用,掩码」，攒 60 帧打一行 PF（网页没有 --perfdump 的文件，走控制台；每帧一次 print 在网页上本身就贵）
			perf_line_buf.append("%d,%.1f,%.2f,%d,%d,%d,%d" % [g.at_frames, g.t, ft, g.enemies.size(), int(g.final_boss != null and not g.final_boss.dead), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), g.optical.ab_mask if g.optical != null else 0])
			if perf_line_buf.size() >= 60:
				print("PF " + " ".join(perf_line_buf))
				perf_line_buf.clear()
		if ft >= 33.3:
			d.slow_n += 1
			perf_slow.append({"t": snappedf(g.t, 0.1), "ft": snappedf(ft, 0.1), "en": g.enemies.size(), "kills": g.kills - perf_kills,
				"ebul": g.ebullets.size(), "warns": g.warns.size(), "fx": g.fx.size(), "gems": g.gems.size(), "mires": g.mires.size(), "boss": g.bosses.size(), "btypes": g.bosses.filter(func(b): return not b.dead).map(func(b): return str(b.type)), "stage": _top_stages(br, 8)})
			if perf_slow.size() > 400:
				perf_slow.sort_custom(func(a, b): return a.ft > b.ft)
				perf_slow.resize(100)
	if g.prof_on:
		perf_prev = g.prof.duplicate()
	perf_kills = g.kills
	perf_upd = g.upd_n
	perf_last = now
	if perf_ab > 0 and g.at_frames % perf_ab == 0:
		g.perf_alt = not g.perf_alt
		PlayClockT.test_legacy = g.perf_alt   # --perfab=N：每 N 帧轮换 g.perf_alt（/b = 旧的 PlayClock 切步与顿帧规则，同局对照，docs/50 §10）


## 各段：帧数、帧时间中位 / 最差 1%（P99）/ 最大、渲染 CPU 中位 / P99、GPU 中位 / P99（毫秒）、敌人数中位 / 峰值
func _perf_summary() -> Dictionary:
	var out := {}
	for w in perf:
		var d: Dictionary = perf[w]
		var fsum := 0.0
		var over := 0
		for x in d.ft:
			fsum += x
			if x > 16.7:
				over += 1
		out[w] = {"n": d.ft.size(), "ft_mean": snappedf(fsum / maxf(1.0, d.ft.size()), 0.01), "ft_med": _pct(d.ft, 0.5), "ft_p95": _pct(d.ft, 0.95), "ft_p99": _pct(d.ft, 0.99), "ft_max": _pct(d.ft, 1.0),
			"over16_pct": snappedf(100.0 * over / maxf(1.0, d.ft.size()), 0.1),
			"rcpu_med": _pct(d.rcpu, 0.5), "rcpu_p99": _pct(d.rcpu, 0.99), "gpu_med": _pct(d.gpu, 0.5), "gpu_p99": _pct(d.gpu, 0.99),
			"en_med": _pct(d.en, 0.5), "en_peak": _pct(d.en, 1.0), "dc_med": _pct(d.dc, 0.5), "slow_n": d.slow_n,
			"stage_ms": _per_frame(d.stage, d.ft.size()), "slow_stage_ms": _per_frame(d.slow_stage, d.slow_n),
			"below40_pct": snappedf(100.0 * d.fps40 / maxf(1.0, d.ft.size()), 0.1), "sfx": _sfx_delta(d.sfx0)}
	perf_slow.sort_custom(func(a, b): return a.ft > b.ft)
	out["slow_top"] = perf_slow.slice(0, 25)
	out["realtime"] = g.realtime
	out["hitstop"] = g.vfx.stop_stat   # 顿帧：kind -> [请求, 实给, 实给秒数]（docs/50 §10）
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx != null and "sfx_by" in sfx and not sfx.sfx_by.is_empty():
		out["sfx_by_cat"] = _sfx_cats(sfx.sfx_by)
		var names: Array = sfx.sfx_by.keys()
		names.sort_custom(func(x, y): return sfx.sfx_by[x][0] > sfx.sfx_by[y][0])
		var top := {}
		for n in names.slice(0, 20):
			top[n] = sfx.sfx_by[n]
		out["sfx_by_top"] = top   # 音名 -> [请求, 实播, 合并, 丢弃, 降音量]
	out["video"] = {"bloom": Cfg.bloom, "dof": Cfg.dof, "normal_maps": Cfg.normal_maps, "water_filter": Cfg.water_filter,
		"size": str(g.get_viewport().get_visible_rect().size), "window": str(DisplayServer.window_get_size())}
	return out


func _pct(a, q: float) -> float:
	if a.size() == 0:
		return 0.0
	var b: Array = Array(a)
	b.sort()
	return snappedf(float(b[mini(b.size() - 1, int(q * (b.size() - 1) + 0.5))]), 0.01)


## 分段耗时按帧平均（毫秒 / 帧），从大到小
func _per_frame(tot: Dictionary, n: int) -> Dictionary:
	var out := {}
	var ks: Array = tot.keys()
	ks.sort_custom(func(a, b): return tot[a] > tot[b])
	for k in ks:
		out[k] = snappedf(float(tot[k]) / maxf(1.0, float(n)), 0.01)
	return out


func _top_stages(br: Dictionary, n: int) -> Dictionary:
	var ks: Array = br.keys()
	ks.sort_custom(func(a, b): return br[a] > br[b])
	var out := {}
	for k in ks.slice(0, n):
		out[k] = snappedf(br[k], 0.1)
	return out


## 音效计数（sfx.gd 的 sfx_stat：实际播放 / 同名合并 / 满槽丢弃 / 抢占 / 降音量 / 同时发声峰值）；--perf 按段给增量
func _sfx_snap() -> Dictionary:
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx == null or not ("sfx_stat" in sfx):
		return {}
	return sfx.sfx_stat.duplicate()


func _sfx_delta(s0: Dictionary) -> Dictionary:
	var s1 := _sfx_snap()
	var out := {}
	for k in s1:
		if k == "voices_max":
			out[k] = s1[k]
		else:
			out[k] = int(s1[k]) - int(s0.get(k, 0))
	return out


## 音效按类别汇总：命中 / 击杀 / 拾取 / 受击 / 干员普攻 / 干员技能 / 敌人 / Boss 与演出 / 其他；每类 [请求, 实播, 合并, 丢弃, 降音量]
func _sfx_cats(by: Dictionary) -> Dictionary:
	var out := {}
	for n in by:
		var c := "其他"
		if n == "hit" or n.ends_with("_hit"):
			c = "命中"
		elif n == "kill":
			c = "击杀"
		elif n == "pickup":
			c = "拾取"
		elif n == "hurt" or n == "heartbeat":
			c = "受击"
		elif n.begins_with("op_") and (n.ends_with("_s1") or n.ends_with("_s2") or n.ends_with("_s3") or n.ends_with("_big")):
			c = "干员技能"
		elif n.begins_with("op_") or n == "swing":
			c = "干员普攻"
		elif n.begins_with("enemy_"):
			c = "敌人"
		elif n.begins_with("boss_") or n.begins_with("cue_") or n.ends_with("_break") or n == "roar":
			c = "Boss 与演出"
		if not out.has(c):
			out[c] = [0, 0, 0, 0, 0]
		for i in 5:
			out[c][i] += int(by[n][i])
	return out


## --clutterlog（配 --shots）：截图的同一帧写 shot_<帧>.json——画面上各类东西的数量与拥挤度（tools/late_clutter.py 量后期画面杂乱）。
## 只读状态，不改对局
func _clutter_log() -> void:
	var ct: Transform2D = g.get_viewport().get_canvas_transform()
	var vs: Vector2 = g.get_viewport_rect().size
	var scr := Rect2(Vector2.ZERO, vs)
	var on := func(p: Vector2) -> bool: return scr.has_point(ct * p)
	var en := 0
	var en_on := 0
	var el_on := 0
	var dash_full := 0
	var dash_dim := 0
	for e in g.enemies:
		if e.dead:
			continue
		en += 1
		if on.call(e.pos):
			en_on += 1
			if e.elite or e.boss:
				el_on += 1
		if e.get("dash_w", 0.0) > 0.0 and e.has("dash_dir"):
			if e.get("tell_dim", false):
				dash_dim += 1
			else:
				dash_full += 1
	var kinds := {}
	var fx_friend := 0
	var fx_foe := 0
	for f in g.fx:
		var foe: bool = f.get("enemy", false) or g.world.FOE_KINDS.has(f.kind)
		var key: String = ("foe:" if foe else "") + str(f.kind)
		kinds[key] = int(kinds.get(key, 0)) + 1
		if foe:
			fx_foe += 1
		else:
			fx_friend += 1
	var ops := []
	for o in g.squad.ops:
		var pk := {}
		for f in o.pfx:
			pk[str(f.kind)] = int(pk.get(str(f.kind), 0)) + 1
		ops.append({"id": o.id, "leader": o.is_leader, "pfx": o.pfx.size(), "kinds": pk})
	var wfull := 0
	var wdim := 0
	for w in g.warns:
		if w.get("dim", false):
			wdim += 1
		else:
			wfull += 1
	var eb_on := 0
	for b in g.ebullets:
		if on.call(b.pos):
			eb_on += 1
	var gems_on := 0
	for gm in g.gems:
		if on.call(gm.pos):
			gems_on += 1
	var lp: Vector2 = ct * g.ppos
	var d := {"frame": g.at_frames, "t": snappedf(g.t, 0.01), "enemies": en, "enemies_on": en_on, "elite_boss_on": el_on,
		"bosses": g.bosses.filter(func(b): return not b.dead).map(func(b): return str(b.type)),
		"fx": g.fx.size(), "fx_friend": fx_friend, "fx_foe": fx_foe, "fx_kinds": kinds, "ops": ops,
		"bullets": g.bullets.size(), "ebullets": g.ebullets.size(), "ebullets_on": eb_on, "lobs": g.lobs.size(), "shocks": g.shocks.size(),
		"warns_full": wfull, "warns_dim": wdim, "dash_full": dash_full, "dash_dim": dash_dim, "texts": g.texts.size(),
		"gems_on": gems_on, "mires": g.mires.size(), "snow": g.map.snow.size(),
		"crowd": snappedf(g.world.crowd, 0.001), "ecrowd": snappedf(g.world.ecrowd, 0.001), "dcrowd": snappedf(g.world.dcrowd, 0.001),
		"fx_dim": snappedf(g.world.fx_dim, 0.001), "declutter": Dc.level(), "leader_scr": [lp.x, lp.y], "lamp": g.lamp,
		"lamp_r": g.lamp_light.texture_scale * 64.0}
	var f := FileAccess.open(g.shot_dir + "/shot_%d.json" % g.at_frames, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
