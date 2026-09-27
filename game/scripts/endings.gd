## 结局与事件箱（docs/19）：事件箱按时间窗口必定刷新，打开后弹 2–3 个选项；选项给藏品 / 灯火 / 计数；
## 结局由已获得的藏品重算（后做的决定覆盖先做的）；最终 Boss 与结算按结局走。
## 数据：data/waves.json 的 events / endings；进度：Cfg.endings_cleared（通关过结局一才出现结局事件）。
extends RefCounted

const D = preload("res://scripts/data.gd")

var g
var events: Array = []          # 事件表（waves.json）
var endings: Dictionary = {}    # 结局表
var done: Array = []            # 已经触发过（刷过箱子）的事件 id
var next_allowed := 0.0         # 下一个事件箱最早刷新时间（避免同时两个）
var ending_at: Dictionary = {}  # 结局 id -> 触发时刻（用于"后覆盖先"）
var cur := "standard"           # 当前结局
var opened_id := ""             # 正在弹选项的事件
var warned_final := false
var all_unlocked := false       # --allend：无视通关进度
var frozen := false             # 最终 Boss 已刷出：结局冻结，不再刷事件箱、不再改写结局（EA 验收 P0-1）
var box_t := 0.0                # 当前事件箱刷出的时刻（超时消散，P1-2）
const BOX_LIFE := 60.0          # 事件箱多久没打开就沉入海底


func _init(game) -> void:
	g = game
	var w: Dictionary = D.Loader.load_waves()
	events = w.get("events", [])
	endings = w.get("endings", {})
	all_unlocked = Cfg.dev_args().has("--allend")


## ---------- 事件箱刷新 ----------
func update(dt: float) -> void:
	if frozen:
		return
	if g.final_boss != null:
		# 最终 Boss 登场：结局就此冻结（结算与解锁都按这时的结局），场上没开的祭坛沉入海底
		frozen = true
		_log("frozen")
		_sink_box("")
		return
	if _box_alive():
		for e in g.enemies:
			if e.chest and not e.dead and e.get("event", "") != "":
				e.pos = g.spawner.safe_event_pos(e.pos, 110.0)
		# 事件箱 BOX_LIFE 秒没打开就消散，不再堵住后面的事件（原来一个不开，后面全停）
		if g.t - box_t > BOX_LIFE:
			_sink_box("海嗣祭坛沉入了海底")
			next_allowed = g.t + 5.0
		return
	if g.t < next_allowed:
		return
	for ev in events:
		if done.has(ev.id):
			continue
		var win: Array = ev.window
		if g.t < win[0]:
			continue
		# 过了窗口还没轮到（条件不满足，或前面的祭坛占着）就作废，不在窗口外补刷（EA 验收 P0-1：补刷到终局前会改写结局）
		if g.t > win[1]:
			done.append(ev.id)
			continue
		if not _event_ok(ev):
			continue
		_spawn_box(ev)
		done.append(ev.id)
		box_t = g.t
		_log("spawn " + str(ev.id))
		next_allowed = g.t + 20.0
		return


## 自动测试日志：ENDEV <动作> ...
func _log(what: String) -> void:
	if g.autotest:
		print("ENDEV %s t=%.1f cur=%s relics=%s" % [what, g.t, cur, str(g.relics.filter(func(r): return int(r) >= 221))])


## 场上的事件箱消散（不打开、不掉落）；msg 为空时不弹横幅
func _sink_box(msg: String) -> void:
	for e in g.enemies:
		if e.chest and not e.dead and e.get("event", "") != "":
			e.dead = true
			_log("sink " + str(e.event))
			g.vfx.sparks(e.pos, Vector2.DOWN, Color(0.5, 0.8, 1.0), 10, 120.0)
			if msg != "":
				g.vfx.show_banner(msg)


func _event_ok(ev: Dictionary) -> bool:
	if ev.has("requires_cleared") and not all_unlocked and not g.autotest:
		if not Cfg.endings_cleared.has(ev.requires_cleared):
			return false
	if ev.has("requires_relic") and not g.relics.has(str(ev.requires_relic)):
		return false
	if ev.has("forbids_relic") and g.relics.has(str(ev.forbids_relic)):
		return false
	if ev.has("requires_flag") and not g.get(ev.requires_flag):
		return false
	return true


func _box_alive() -> bool:
	for e in g.enemies:
		if e.chest and not e.dead and e.get("event", "") != "":
			return true
	return false


func _spawn_box(ev: Dictionary) -> void:
	var p: Vector2 = g.spawner.event_pos(520.0, 650.0, 110.0)
	g.spawner.spawn_chest(p, ev.id)
	g.vfx.show_banner("海嗣祭坛「%s」出现了 —— 打开它做出选择" % ev.name)
	Sfx.play("relic", -2.0, 0.7, 0.0)


## 事件箱被打开（chest 被击碎）
func open(ev_id: String) -> void:
	for ev in events:
		if ev.id != ev_id:
			continue
		opened_id = ev_id
		_log("open " + ev_id)
		var opts: Array = []
		var still_ok := _event_ok(ev)   # 打开时再查一次：刷箱之后骑士可能已经阵亡（EA 验收 P1-4）
		for i in ev.options.size():
			var op: Dictionary = ev.options[i]
			if not _option_ok(op, still_ok):
				continue
			var icon: String = "e_event"
			# 选项条上的效果小牌（C 版式）：概率 / 灯火 / 得到藏品 / 改为三选一 / 源石锭
			var chips: Array = []
			for o in op.get("ops", []):
				if o.has("chance"):
					chips.append(["%d%%" % int(round(float(o.chance) * 100.0)), Color(0.18, 0.72, 1.0)])
				if o.has("light"):
					chips.append(["灯火 %+d" % int(o.light), Color(0.95, 0.89, 0.76)])
				if o.has("relic"):
					icon = "relic_" + str(o.relic)
					chips.append(["得到藏品", Color(0.18, 0.72, 1.0)])
				if o.has("relic_choice"):
					if icon == "e_event":
						icon = "exit"
					chips.append(["藏品三选一", Color(0.62, 0.6, 0.57)])
				if o.has("ingots"):
					chips.append(["源石锭 %+d" % int(o.ingots), Color(0.18, 0.83, 0.63)])
			opts.append({"kind": "event", "id": "%s:%d" % [ev_id, i], "name": op.label, "desc": op.desc, "icon": icon, "chips": chips,
				"cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)})
		# 抉择是可放弃的事件；观望/犹疑满级被过滤后仍能退出，不强迫拿决心。
		if ev_id.begins_with("resolve"):
			opts.append({"kind": "event", "id": "%s:-2" % ev_id, "name": "离开", "desc": "不领取藏品，保持当前结局路线。", "icon": "exit",
				"chips": [], "cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)})
		if opts.is_empty():
			# 所有选项都作废了（极少见）：给一次普通的藏品选择
			opts.append({"kind": "event", "id": "%s:-1" % ev_id, "name": "离开", "desc": "改为普通的藏品选择", "icon": "exit",
				"chips": [["藏品三选一", Color(0.62, 0.6, 0.57)]], "cat": "事件  " + ev.name, "col": Color(0.55, 0.75, 1.0)})
		g.panel_ui.show_choices(ev.name, opts, "event", str(ev.get("text", "")))
		return


## 选项还能不能给：
## - 事件条件在打开时已不满足（如骑士已阵亡），给藏品的选项不再出现（P1-4）；
## - 给的藏品已经拥有且满级（观望 / 犹疑只有 1 级），选了等于空选，不再出现（P1-3）
func _option_ok(op: Dictionary, still_ok: bool) -> bool:
	for o in op.get("ops", []):
		if not o.has("relic"):
			continue
		var rid := str(o.relic)
		if not still_ok:
			return false
		if not g.progression.can_gain_relic(rid):
			return false
	return true


## 选项生效
func pick(o: Dictionary) -> void:
	var parts: PackedStringArray = o.id.split(":")
	for ev in events:
		if ev.id != parts[0]:
			continue
		opened_id = ""
		if int(parts[1]) == -2:
			return
		if int(parts[1]) < 0:
			g.pending_chests += 1
			return
		var op: Dictionary = ev.options[int(parts[1])]
		for x in op.get("ops", []):
			if x.has("chance") and g.rng.randf() >= float(x.chance):
				g.vfx.add_text(g.ppos + Vector2(0, -90), "什么都没有发生", Color(0.7, 0.75, 0.8), 16)
				continue
			if x.has("light"):
				# 付灯火最低降到 10；原本就低于 10 时不变（不能因为付代价反而加灯火，P2-6）
				g.lamp = minf(g.lamp, maxf(10.0, g.lamp + float(x.light))) if float(x.light) < 0.0 else minf(g.lamp_cap, g.lamp + float(x.light))
				g.vfx.add_text(g.ppos + Vector2(0, -90), "灯火 %+d" % int(x.light), Color(1.0, 0.8, 0.45), 16)
			if x.has("relic"):
				g.progression.gain_relic(str(x.relic))
			if x.has("relic_choice"):
				g.pending_chests += int(x.relic_choice)
			if x.has("ingots"):
				g.ingots += int(x.ingots)
			if x.has("flag"):
				g.set(x.flag, true)
		return


## 只为决定结局的信物保留槽位：其他事件加成与普通藏品共用空间。
## 决心升级沿用同一槽，因此最多预留 4 槽；窗口结束/已得到后释放。
const ROUTE_RELICS := ["221", "222", "223", "238"]


func is_route_relic(id: String) -> bool:
	return ROUTE_RELICS.has(id)


func reserved_relic_slots() -> int:
	if frozen:
		return 1 if g.knight.alive and not g.relics.has("223") else 0
	var active: Array = []
	for e in g.enemies:
		if e.chest and not e.dead and e.get("event", "") != "":
			active.append(str(e.event))
	var future: Array = []
	for ev in events:
		if ev.has("requires_cleared") and not all_unlocked and not g.autotest and not Cfg.endings_cleared.has(ev.requires_cleared):
			continue
		if g.t > float(ev.window[1]) and not active.has(ev.id) and opened_id != ev.id:
			continue
		if done.has(ev.id) and not active.has(ev.id) and opened_id != ev.id:
			continue
		for op in ev.options:
			for effect in op.get("ops", []):
				var rid: String = str(effect.get("relic", ""))
				if is_route_relic(rid) and not g.relics.has(rid) and not future.has(rid):
					future.append(rid)
	if (g.knight.alive or future.has("222")) and not g.relics.has("223"):
		future.append("223")
	return future.size()


## ---------- 结局 ----------
## 记下这件藏品触发结局的时刻（不重算）：gain_relic 在骑士登场 / 离队之前调用，保证中途的重算已经知道新结局
func note_relic(id: String) -> void:
	for eid in endings:
		var req: Dictionary = endings[eid].get("requires", {})
		if (req.has("relic") and str(req.relic) == id) or (req.has("relic_lv") and str(req.relic_lv[0]) == id):
			ending_at[eid] = g.t


## 获得藏品后重算：满足条件的结局里，取最近一次触发的
func on_relic(id: String) -> void:
	for eid in endings:
		var e: Dictionary = endings[eid]
		if not e.has("requires"):
			continue
		var req: Dictionary = e.requires
		if (req.has("relic") and str(req.relic) == id) or (req.has("relic_lv") and str(req.relic_lv[0]) == id):
			if _satisfied(e):
				ending_at[eid] = g.t
	recalc()


func _satisfied(e: Dictionary) -> bool:
	if e.has("requires"):
		var req: Dictionary = e.requires
		if req.has("relic") and not g.relics.has(str(req.relic)):
			return false
		if req.has("relic_lv") and int(g.rfx.lv.get(str(req.relic_lv[0]), 0)) < int(req.relic_lv[1]):
			return false
		if req.has("flag") and not g.get(req.flag):
			return false
	for f in e.get("forbids", []):
		if g.relics.has(str(f)):
			return false
	return true


func recalc() -> void:
	var best := "standard"
	var best_t := -1.0
	for eid in endings:
		if eid == "standard":
			continue
		if not _satisfied(endings[eid]):
			continue
		# sticky（骑士线）：只要骑士还在队中，抉择事件不会把结局改走；只有他离队 / 阵亡（223）才回退
		var at: float = ending_at.get(eid, -1.0) + (1.0e6 if endings[eid].get("sticky", false) else 0.0)
		if at > best_t:
			best = eid
			best_t = at
	if frozen:
		return   # 最终 Boss 登场后结局不再改写
	if best != cur:
		cur = best
		g.ending = cur
		g.vfx.show_banner("探索的走向改变了：%s" % endings[cur].name)
		Sfx.play("roar", -6.0, 0.5, 0.0)
		# 9:00 预告之后结局又变了（回忆 / 抉择·其三的窗口跨过 9:00）：按新结局再预告一次（P2-7）
		if warned_final:
			g.vfx.show_banner(endings[cur].get("omen", "终局将至"))


## 9:00 终局预告
func tick_final_warning() -> void:
	if not warned_final and g.t >= 540.0:
		warned_final = true
		g.vfx.show_banner(endings.get(cur, {}).get("omen", "终局将至"))
		Sfx.play("roar", -4.0, 0.6, 0.0)


func cur_name() -> String:
	return endings.get(cur, {}).get("name", "结局一")


func cur_col() -> Color:
	var c = endings.get(cur, {}).get("col", [0.8, 0.6, 1.0])
	return Color(c[0], c[1], c[2])


## 通关：记录已达成结局（解锁其它结局的事件）
func on_win() -> void:
	if g.autotest:
		return
	if not Cfg.endings_cleared.has(cur):
		Cfg.endings_cleared.append(cur)
		g.ending_new = true
		Cfg.save()
