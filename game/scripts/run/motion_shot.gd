extends RefCounted
## 界面动效自测（docs/62 §2.7，第一批）：只在 --autotest 下由 autotest.step() 每帧调用；返回 true 时本帧不再跑自测的其余逻辑。
##   --motionshot=<界面>,<秒,秒,…>  第 30 帧打开该界面，按界面时钟在指定时刻各截一张 shot_motion_<界面>_<full|rm>_<毫秒>.png，截完退出。
##                                   界面：levelup / relic / recruit / shop / pause / banner / fail（fail 的时刻从倒下算，结算动效从 1.7 秒起）
##   --reducemotion                   同时打开「减少动态效果」（Cfg.reduce_motion，不写存档）
##   --motionpress=<key|mouse|touch|pad>@<秒>  在该时刻注入一次按下 + 松开（键盘 1 / Enter、鼠标左键、触屏、手柄 Ⓐ），
##                                   2 帧后打印 MOTIONPRESS（动效是否被跳过、有没有误选）；0.4 秒后再按一次，打印 MOTIONPRESS2（这次应该生效）
##   --motionrec                      按固定脚本依次演示各界面（全动效 → 减少动态 → 失败结算），每帧存 rec_<帧>.png，并打印 MOTIONREC 分段；
##                                   配合 --fixed-fps 30 录片（界面时钟按固定步长走）
##   --motionperf=<界面>[,<秒>]       同局轮换测开销（docs/50 §9.9 的办法）：界面开着，每 0.9 秒重放一次动效并在全动效 / 减少动态之间轮换，
##                                   关垂直同步不限帧，按两桶记帧时间与渲染 CPU，结束打印 MOTIONPERF {json}
## 不碰对局随机数以外的东西没有意义——这里是测试钩子：打开升级面板会照常消耗 g.rng（与正式升级相同），只用于截图 / 录片 / 量帧时间，不用于复现检查。

const UM = preload("res://scripts/ui_motion.gd")
const Game = preload("res://scripts/game.gd")
var g: Game

var mode := ""              # shot / rec / perf
var screen := ""
var times: Array = []
var t0 := -1.0              # 本界面打开的界面时刻
var press_kind := ""
var press_at := -1.0
var press_state := 0        # 0 未按 / 1 已按等结果 / 2 已打印第一次 / 3 已按第二次 / 4 完成
var press_frame := 0
var press_info := {}
var rec_segs: Array = []
var rec_i := -1
var rec_frame := 0
var perf_dur := 12.0
var perf_last := 0
var perf_cycle := -1
var perf := {"full": [], "rm": []}
var perf_rcpu := {"full": [], "rm": []}


func _init(game: Game) -> void:
	g = game
	for a in Cfg.dev_args():
		if a.begins_with("--motionshot="):
			var parts: PackedStringArray = a.substr(13).split(",")
			mode = "shot"
			screen = parts[0]
			for k in range(1, parts.size()):
				times.append(float(parts[k]))
		elif a == "--motionrec":
			mode = "rec"
		elif a.begins_with("--motionperf="):
			var pp: PackedStringArray = a.substr(13).split(",")
			mode = "perf"
			screen = pp[0]
			if pp.size() > 1:
				perf_dur = float(pp[1])
		elif a.begins_with("--motionpress="):
			var q: PackedStringArray = a.substr(14).split("@")
			press_kind = q[0]
			press_at = float(q[1]) if q.size() > 1 else 0.2
		elif a == "--reducemotion":
			Cfg.reduce_motion = true


func active() -> bool:
	return mode != ""


func step() -> bool:
	if mode == "":
		return false
	if g.state == Game.S.PLAY or g.state == Game.S.CHOICE or g.state == Game.S.SHOP or g.state == Game.S.PAUSE:
		g.hp = g.max_hp
		g.xp = 0.0   # 测试期间不让自然升级的面板插进来
	match mode:
		"shot":
			_step_shot()
		"rec":
			_step_rec()
		"perf":
			_step_perf()
	return true


func _el() -> float:
	return UM.now() - t0


func _save(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/" + name)


# ----------------------------------------------------------------- 打开各界面

func open(s: String) -> void:
	t0 = UM.now()
	# relic4 / relic5 / recruit5 …：同一界面多张卡（选卡一排宽度自适应的截图验收）
	var n := 3
	var m := RegEx.create_from_string("^(relic|recruit)([0-9]+)$").search(s)
	if m != null:
		s = m.get_string(1)
		n = int(m.get_string(2))
	match s:
		"levelup":
			g.progression.open_levelup()
		"relic":
			g.panel_ui.show_choices("获得藏品", _relic_opts(n), "relic")
		"recruit":
			var rc: Array = g.progression.recruit_cards()
			g.panel_ui.show_choices("招募干员", rc.slice(0, n), "level")
		"shop":
			g.ingots = maxi(g.ingots, 60)
			g.merchant = {"pos": g.ppos, "life": 60.0, "near": false, "purchases": 0}
			g.shop_items.clear()
			g.shop_sys.open()
		"pause":
			g.state = Game.S.PAUSE
		"banner":
			g.vfx.banner_seen.erase("海嗣大群正在逼近 · 稳住阵线")
			g.banner_t = 0.0
			g.vfx.show_banner("海嗣大群正在逼近 · 稳住阵线", 3)
		"fail":
			g.state = Game.S.DEAD


## 藏品示意：基础 / 稀有 / 核心各一张（三种光柱颜色都看得到；藏品是现成的，不新造数据）；n > 3 时依次补别的藏品
func _relic_opts(n := 3) -> Array:
	var want := ["基础", "稀有", "核心"]
	var ids: Array = []
	for rar in want:
		for rid in g.RL.keys():
			if g.RL[rid].get("rarity", "") == rar and g.tex.get("relic_" + str(rid)) != null:
				ids.append(rid)
				break
	for rid in g.RL.keys():
		if ids.size() >= n:
			break
		if rid not in ids and g.tex.get("relic_" + str(rid)) != null:
			ids.append(rid)
	var out: Array = []
	for rid in ids.slice(0, n):
		var r: Dictionary = g.RL[rid]
		out.append({"kind": "relic", "id": rid, "name": "【%s】%s" % [r.cat, g.rfx.display_name(rid)], "desc": g.rfx.display_desc(rid)})
	return out


func close(s: String) -> void:
	match s:
		"levelup", "relic", "recruit":
			if g.state == Game.S.CHOICE:
				g.panel.visible = false
				g.state = Game.S.PLAY
		"shop":
			g.shop_sys.close()
			g.merchant = {}   # 商人就站在主控脚下，不清掉会马上自动再打开商店
		"pause":
			g.state = Game.S.PLAY
		"banner":
			g.banner_t = 0.0


# ----------------------------------------------------------------- --motionshot / --motionpress

func _step_shot() -> void:
	if t0 < 0.0:
		if g.at_frames >= 30 and g.state == Game.S.PLAY:
			open(screen)
		return
	var tag := "rm" if Cfg.reduce_motion else "full"
	while not times.is_empty() and _el() >= float(times[0]):
		_save("shot_motion_%s_%s_%04d.png" % [screen, tag, int(roundf(_el() * 1000.0))])
		times.pop_front()
	if press_kind != "":
		_step_press()
	if times.is_empty() and (press_kind == "" or press_state >= 4):
		print("MOTIONSHOT done screen=%s rm=%s" % [screen, str(Cfg.reduce_motion)])
		g.get_tree().quit()


func _snapshot() -> Dictionary:
	return {"state": g.state, "panel_running": g.panel_ui.motion.running(), "skipped": g.panel_ui.motion.skipped,
		"result_running": g.result_screen.motion_running(), "ui_skip": g.ui_skip, "level": g.level, "squad": g.squad.size(), "ingots": g.ingots}


func _step_press() -> void:
	match press_state:
		0:
			if _el() >= press_at:
				press_info = _snapshot()
				_inject(press_kind, true)
				press_frame = g.at_frames
				press_state = 1
		1:
			if g.at_frames == press_frame + 1:
				_inject(press_kind, false)
			if g.at_frames >= press_frame + 3:
				print("MOTIONPRESS kind=%s screen=%s rm=%s before=%s after=%s" % [press_kind, screen, str(Cfg.reduce_motion), JSON.stringify(press_info), JSON.stringify(_snapshot())])
				press_state = 4 if screen == "fail" else 2   # 失败结算的第二下会「再次探索」重开场景，只验第一下
				press_at = _el() + 0.4
		2:
			if _el() >= press_at:
				press_info = _snapshot()
				_inject(press_kind, true)
				press_frame = g.at_frames
				press_state = 3
		3:
			if g.at_frames == press_frame + 1:
				_inject(press_kind, false)
			if g.at_frames >= press_frame + 3:
				print("MOTIONPRESS2 kind=%s screen=%s before=%s after=%s" % [press_kind, screen, JSON.stringify(press_info), JSON.stringify(_snapshot())])
				press_state = 4


## 第一张卡（或暂停 / 结算的第一个按钮）的中心，视口坐标
func _target() -> Vector2:
	var p := Vector2(640, 360)
	if g.state == Game.S.CHOICE or g.state == Game.S.SHOP:
		if g.panel_box.get_child_count() > 0:
			p = (g.panel_box.get_child(0) as Control).get_global_rect().get_center()
	elif not g.result_btns.is_empty():
		p = (g.result_btns[0][0] as Rect2).get_center() * Cfg.ui_k
	return p


func _inject(kind: String, down: bool) -> void:
	match kind:
		"key":
			var ev := InputEventKey.new()
			ev.keycode = KEY_1 if g.state == Game.S.CHOICE or g.state == Game.S.SHOP else KEY_ENTER
			ev.physical_keycode = ev.keycode
			ev.pressed = down
			Input.parse_input_event(ev)
		"mouse":
			var p := _target()
			Input.warp_mouse(p)
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.position = p
			mb.global_position = p
			mb.pressed = down
			Input.parse_input_event(mb)
		"touch":
			var st := InputEventScreenTouch.new()
			st.index = 0
			st.position = _target()
			st.pressed = down
			Input.parse_input_event(st)
		"pad":
			var jb := InputEventJoypadButton.new()
			jb.device = 0
			jb.button_index = JOY_BUTTON_A
			jb.pressed = down
			Input.parse_input_event(jb)


# ----------------------------------------------------------------- --motionrec

## 录片脚本：[界面, 时长秒, 减少动态, 跳过时刻（-1 = 不跳）, 说明]
const REC := [
	["levelup", 1.5, false, -1.0, "升级选卡 · 发牌翻面"],
	["levelup", 1.0, false, 0.22, "升级选卡 · 翻面途中点一下 = 跳到终态"],
	["relic", 1.7, false, -1.0, "藏品选择 · 光柱托起（基础 / 稀有 / 核心）"],
	["recruit", 1.5, false, -1.0, "招募干员 · 部署落地"],
	["shop", 2.2, false, -1.0, "流浪商人 · 灯笼明暗，货架逐格亮起"],
	["banner", 2.2, false, -1.0, "HUD 横幅 · 字距收拢"],
	["pause", 1.7, false, -1.0, "暂停 · 秒针停摆，菜单嘀嗒步进"],
	["levelup", 0.8, true, -1.0, "减少动态效果 · 升级选卡"],
	["relic", 0.8, true, -1.0, "减少动态效果 · 藏品选择"],
	["shop", 0.8, true, -1.0, "减少动态效果 · 商人"],
	["pause", 0.8, true, -1.0, "减少动态效果 · 暂停"],
	["fail", 3.2, false, -1.0, "失败结算 · 打捞记录"],
]


func _step_rec() -> void:
	if rec_i < 0:
		if g.at_frames >= 30 and g.state == Game.S.PLAY:
			rec_i = 0
			_rec_open()
		return
	_save("rec_%05d.png" % rec_frame)
	rec_frame += 1
	var seg: Array = REC[rec_i]
	if float(seg[3]) >= 0.0 and press_state == 0 and _el() >= float(seg[3]):
		press_state = 1
		_inject("mouse", true)
		press_frame = g.at_frames
	if press_state == 1 and g.at_frames == press_frame + 1:
		_inject("mouse", false)
		press_state = 2
	if _el() >= float(seg[1]):
		close(seg[0])
		rec_i += 1
		if rec_i >= REC.size():
			print("MOTIONREC end frames=%d" % rec_frame)
			g.get_tree().quit()
			return
		_rec_open()


func _rec_open() -> void:
	var seg: Array = REC[rec_i]
	Cfg.reduce_motion = bool(seg[2])
	press_state = 0
	if g.state != Game.S.PLAY:
		g.panel.visible = false
		g.state = Game.S.PLAY
	open(seg[0])
	print("MOTIONREC seg=%d frame=%d screen=%s rm=%s label=%s" % [rec_i, rec_frame, seg[0], str(seg[2]), seg[4]])


# ----------------------------------------------------------------- --motionperf

func _step_perf() -> void:
	if t0 < 0.0:
		if g.at_frames >= 30 and g.state == Game.S.PLAY:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			RenderingServer.viewport_set_measure_render_time(g.get_viewport().get_viewport_rid(), true)
			open(screen)
			perf_cycle = 0
		return
	var now := Time.get_ticks_usec()
	var cyc := int(floorf(_el() / 0.9))
	if perf_last > 0 and _el() > 1.0:
		var b := "rm" if Cfg.reduce_motion else "full"
		perf[b].append((now - perf_last) / 1000.0)
		perf_rcpu[b].append(RenderingServer.viewport_get_measured_render_time_cpu(g.get_viewport().get_viewport_rid()))
	perf_last = now
	if cyc != perf_cycle:
		perf_cycle = cyc
		Cfg.reduce_motion = cyc % 2 == 1
		_restart()
	if _el() >= perf_dur:
		var out := {"screen": screen}
		for b in perf:
			out[b] = {"n": perf[b].size(), "ft_med": _pct(perf[b], 0.5), "ft_mean": _mean(perf[b]), "ft_p90": _pct(perf[b], 0.9), "rcpu_med": _pct(perf_rcpu[b], 0.5)}
		out["delta_med_ms"] = snappedf(float(out.full.ft_med) - float(out.rm.ft_med), 0.001)
		out["delta_mean_ms"] = snappedf(float(out.full.ft_mean) - float(out.rm.ft_mean), 0.001)
		print("MOTIONPERF ", JSON.stringify(out))
		g.get_tree().quit()


## 重放当前界面的动效（不重开面板，不再消耗随机数）
func _restart() -> void:
	match screen:
		"levelup", "relic", "recruit":
			g.panel_ui.motion.t0 = UM.now()
			g.panel_ui.motion.skipped = false
		"shop":
			g.panel_ui.motion.start_shop()
		"pause":
			g.state_age = 0.0
			g.ui_skip = false
		"fail":
			g.state_age = 1.7
			g.ui_skip = false
		"banner":
			g.banner_t = 3.0
			g.vfx.banner_serial += 1


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return snappedf(float(s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]), 0.001)


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return snappedf(t / a.size(), 0.001)
