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


func _init(game) -> void:
	g = game
	var w: Dictionary = D.Loader.load_waves()
	events = w.get("events", [])
	endings = w.get("endings", {})
	all_unlocked = Cfg.dev_args().has("--allend")


## ---------- 事件箱刷新 ----------
func update(dt: float) -> void:
	if g.t < next_allowed or _box_alive():
		return
	for ev in events:
		if done.has(ev.id):
			continue
		var win: Array = ev.window
		if g.t < win[0]:
			continue
		if not _event_ok(ev):
			if g.t > win[1] + 30.0:
				done.append(ev.id)  # 过窗且条件不满足，放弃
			continue
		_spawn_box(ev)
		done.append(ev.id)
		next_allowed = g.t + 20.0
		return


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
	var p: Vector2 = g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(300.0, 420.0)
	if g.zone_state != 0 and p.distance_to(g.zone_c) > g.zone_r - 80.0:
		p = g.zone_c + (p - g.zone_c).normalized() * maxf(60.0, g.zone_r - 120.0)
	g.spawner.spawn_chest(p, ev.id)
	g.vfx.show_banner("海嗣祭坛「%s」出现了 —— 打开它做出选择" % ev.name)
	Sfx.play("relic", -2.0, 0.7, 0.0)


## 事件箱被打开（chest 被击碎）
func open(ev_id: String) -> void:
	for ev in events:
		if ev.id != ev_id:
			continue
		opened_id = ev_id
		var opts: Array = []
		for i in ev.options.size():
			var op: Dictionary = ev.options[i]
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
		g.panel_ui.show_choices(ev.name, opts, "event", str(ev.get("text", "")))
		return


## 选项生效
func pick(o: Dictionary) -> void:
	var parts: PackedStringArray = o.id.split(":")
	for ev in events:
		if ev.id != parts[0]:
			continue
		var op: Dictionary = ev.options[int(parts[1])]
		for x in op.get("ops", []):
			if x.has("chance") and g.rng.randf() >= float(x.chance):
				g.vfx.add_text(g.ppos + Vector2(0, -90), "什么都没有发生", Color(0.7, 0.75, 0.8), 16)
				continue
			if x.has("light"):
				g.lamp = clampf(g.lamp + float(x.light), 10.0, g.lamp_cap) if float(x.light) < 0.0 else minf(g.lamp_cap, g.lamp + float(x.light))
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


## ---------- 结局 ----------
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
	if best != cur:
		cur = best
		g.ending = cur
		g.vfx.show_banner("探索的走向改变了：%s" % endings[cur].name)
		Sfx.play("roar", -6.0, 0.5, 0.0)


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
