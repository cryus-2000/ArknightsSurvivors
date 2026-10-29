extends RefCounted
## 性能报告（10-27 用户：真机采集用，重点手机网页）：每局自动记一份性能摘要，本地只留最近 KEEP 局，不上传。
## 设置 → 画面 →「性能报告」查看最近一局摘要、「复制报告」得到一段纯文本（screens/perf_view.gd）。
## 采集只做计数和分桶，不逐帧存数组：
## - 帧时：对局进行中（state = PLAY，面板 / 暂停不算；开局前 WARM 秒不算）每帧的真实间隔进 0.5 ms 一格的直方图，
##   P50 / P95 / P99 从直方图读（格中点）；超过 1 秒的间隔（切后台、断点）不算
## - 最低 1 秒帧率：按真实时间每满 1 秒结算一次帧数，取最小；7 分钟（对局时间）以后另记一组直方图和最低值
## - 内存峰值：每 MEM_EVERY 秒取一次。网页 = 引擎显存统计 + 网页音频样本解码估算（同 game._mem_guard / --memlog 口径）；
##   桌面 = 引擎静态内存 + 显存
## - 同屏敌人峰值、是否触发过内存护栏（game._mem_guard 置 guard_hit）、局长、画质档、帧率上限、版本、设备
## - 10-27 加（真机 iPhone 报告定位用，docs/50 §39）：开局画质档（局末的档可能已被护栏降过）、护栏走到第几步、敌人峰值那一刻的构成
##   （普通 / 精英 / Boss / 补给箱 / 事件与召唤）、内存峰值那一刻的构成（贴图 / 缓冲区 / 其余显存 / 音频）、最慢的 SLOW_N 个 1 秒（对局时间、
##   帧数、最长一帧、那一秒里发生了什么：Boss 登场 / 大群 / 精英 / 读贴图 N 张 / 升级 / 刷怪 N 只 / 护栏…）
## 存档：user://perf_reports.json（网页落在浏览器本地存储里）。测试运行（带命令行参数）只有加 --perfreport 才记，且写到 _test 文件，不碰玩家的
const Game = preload("res://scripts/game.gd")

const KEEP := 5
const BUCKET_MS := 0.5
const NB := 200          # 0–100 ms；更长的进最后一格
const LATE_T := 420.0    # 「后期」：对局时间 7 分钟以后
const WARM := 3.0        # 开局前 3 秒（建局、预热）不算
const MEM_EVERY := 5.0

var g: Game
var on := false
var h_all := PackedInt32Array()
var h_late := PackedInt32Array()
var min_all := 0.0       # 最低 1 秒帧率（0 = 还没满过 1 秒）
var min_late := 0.0
var enemy_peak := 0
var mem_peak := 0.0
var guard_hit := false
var guard_stage := 0     # 护栏这局走到第几步（game._mem_guard：1 清缓存 / 2 降画质 / 3 分辨率缩放）
var q0 := ""             # 开局画质档
var enemy_mix := {}      # 敌人峰值那一刻的构成
var mem_mix := {}        # 内存峰值那一刻的构成
const SLOW_N := 5
var slow: Array = []     # 最慢的 1 秒：[fps, 对局时间, 最长一帧 ms, 标签数组]，按 fps 升序
var _sec_max := 0.0
var _sec_tags := {}      # 这一秒里打上的事件标签（tag()）
var _snap := {}          # 这一秒开头的计数快照（自动标签用）
var done := false
var _last_us := 0
var _sec_t0 := 0
var _sec_n := 0
var _sec_late := false
var _mem_t := MEM_EVERY


func _init(game: Game) -> void:
	g = game
	on = Cfg.dev_args().is_empty() or Cfg.dev_args().has("--perfreport")
	h_all.resize(NB + 1)
	h_late.resize(NB + 1)


## 每帧（game._process）：只加计数
func tick(delta: float) -> void:
	if not on or done or g.demo_op != "" or g.trial.active:
		return   # 图鉴演示 / Boss 演练不算
	var now := Time.get_ticks_usec()
	var last := _last_us
	_last_us = now
	if q0 == "":
		q0 = Cfg.quality
	if g.state != Game.S.PLAY or g.t < WARM or last == 0:
		_sec_t0 = 0
		return
	var ms := (now - last) / 1000.0
	if ms > 1000.0:
		_sec_t0 = 0
		return
	var late: bool = g.t >= LATE_T
	var b := mini(int(ms / BUCKET_MS), NB)
	h_all[b] += 1
	if late:
		h_late[b] += 1
	# 最低 1 秒帧率（真实时间）
	if _sec_t0 == 0:
		_sec_begin(now, late)
	_sec_n += 1
	_sec_max = maxf(_sec_max, ms)
	if now - _sec_t0 >= 1000000:
		var fps := _sec_n * 1000000.0 / float(now - _sec_t0)
		min_all = fps if min_all <= 0.0 else minf(min_all, fps)
		if _sec_late:
			min_late = fps if min_late <= 0.0 else minf(min_late, fps)
		_sec_end(fps)
		_sec_begin(now, late)
	if g.enemies.size() > enemy_peak:
		enemy_peak = g.enemies.size()
		enemy_mix = _enemy_mix()
	_mem_t += delta
	if _mem_t >= MEM_EVERY:
		_mem_t = 0.0
		var m := mem_mb()
		if m > mem_peak:
			mem_peak = m
			mem_mix = _mem_mix()


## 事件标签（Boss 登场、护栏动作等调用方主动打的）：记进这一秒
func tag(name: String) -> void:
	if on and not done:
		_sec_tags[name] = int(_sec_tags.get(name, 0)) + 1


func _counts() -> Dictionary:
	var A = load("res://scripts/art.gd")
	var el := 0
	for e in g.enemies:
		if e.get("elite", false) and not e.dead:
			el += 1
	return {"tex": A._cache.size(), "boss": g.bosses.size(), "horde": g.horde_log.size(), "lv": g.level, "elite": el, "mob": int(g.spawner.n_mob)}


func _sec_begin(now: int, late: bool) -> void:
	_sec_t0 = now
	_sec_n = 0
	_sec_late = late
	_sec_max = 0.0
	_sec_tags = {}
	_snap = _counts()


func _sec_end(fps: float) -> void:
	if slow.size() >= SLOW_N and fps >= float(slow[-1][0]):
		return
	var c := _counts()
	var tags: Array = []
	if g.boss_intro != null and g.boss_intro.active():
		tags.append("Boss 演出")
	if int(c.boss) > int(_snap.get("boss", 0)):
		tags.append("Boss 登场")
	if int(c.horde) > int(_snap.get("horde", 0)):
		tags.append("大群")
	if int(c.elite) > int(_snap.get("elite", 0)):
		tags.append("精英 +%d" % (int(c.elite) - int(_snap.get("elite", 0))))
	if int(c.tex) > int(_snap.get("tex", 0)):
		tags.append("读贴图 %d 张" % (int(c.tex) - int(_snap.get("tex", 0))))
	if int(c.lv) > int(_snap.get("lv", 0)):
		tags.append("升级")
	var mob: int = int(c.mob) - int(_snap.get("mob", 0))
	if mob >= 8:
		tags.append("刷怪 %d 只" % mob)
	for k in _sec_tags:
		tags.append(str(k) if int(_sec_tags[k]) == 1 else "%s ×%d" % [k, int(_sec_tags[k])])
	slow.append([snappedf(fps, 0.1), snappedf(g.t, 1.0), snappedf(_sec_max, 1.0), tags])
	slow.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if slow.size() > SLOW_N:
		slow.resize(SLOW_N)


func _enemy_mix() -> Dictionary:
	var m := {"普通": 0, "精英": 0, "Boss": 0, "补给箱": 0, "事件 / 召唤": 0}
	for e in g.enemies:
		if e.dead:
			continue
		if e.boss:
			m["Boss"] += 1
		elif e.get("elite", false):
			m["精英"] += 1
		elif e.get("chest", false):
			m["补给箱"] += 1
		elif e.get("friendly", false) or str(e.get("event", "")) != "" or e.has("owner") or e.has("feed_to_id"):
			m["事件 / 召唤"] += 1
		else:
			m["普通"] += 1
	return m


static func _mem_mix() -> Dictionary:
	var tex: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buf: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	var vid: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	return {"贴图": snappedf(tex, 1.0), "缓冲区": snappedf(buf, 1.0), "其余显存": snappedf(maxf(0.0, vid - tex - buf), 1.0),
		"音频": snappedf(Sfx.sample_mem_mb() if OS.has_feature("web") else 0.0, 1.0)}


static func mem_mb() -> float:
	var vid: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	if OS.has_feature("web"):
		return vid + Sfx.sample_mem_mb()
	return vid + OS.get_static_memory_usage() / 1048576.0


## 直方图的 p 分位（毫秒，格中点）；没有样本返回 0
static func pct(h: PackedInt32Array, p: float) -> float:
	var n := 0
	for c in h:
		n += c
	if n == 0:
		return 0.0
	var want := ceili(p * n)
	var acc := 0
	for i in h.size():
		acc += h[i]
		if acc >= want:
			return (i + 0.5) * BUCKET_MS
	return h.size() * BUCKET_MS


static func _count(h: PackedInt32Array) -> int:
	var n := 0
	for c in h:
		n += c
	return n


## 局终（胜 / 负，或中途退出）：整理成一条记录存下。中途退出且对局不到 30 秒的不记
func finish(result: String) -> void:
	if Cfg.dev_args().has("--perfreport"):
		print("PERFREPORT finish result=%s on=%s done=%s frames=%d t=%.1f" % [result, str(on), str(done), _count(h_all), g.t])
	if not on or done or g.demo_op != "" or g.trial.active:
		return
	done = true
	if (result == "quit" and g.t < 30.0) or _count(h_all) == 0:
		return
	var rec := {
		"time": Time.get_datetime_string_from_system(false, true),
		"version": _build().get("version", ""),
		"commit": _build().get("commit", ""),
		"result": result,
		"len": snappedf(g.t, 1.0),
		"device": device(),
		"quality": Cfg.quality, "quality_mode": Cfg.quality_mode, "fps_cap": Cfg.max_fps, "lock30": Cfg.fps_lock30,
		"render_scaled": Cfg.render_scaled,
		"frames": _count(h_all), "p50": pct(h_all, 0.5), "p95": pct(h_all, 0.95), "p99": pct(h_all, 0.99), "min1s": snappedf(min_all, 0.1),
		"late": {} if _count(h_late) == 0 else {"frames": _count(h_late), "p50": pct(h_late, 0.5), "p95": pct(h_late, 0.95), "p99": pct(h_late, 0.99), "min1s": snappedf(min_late, 0.1)},
		"mem_peak": snappedf(mem_peak, 1.0), "mem_src": "显存 + 音频估算" if OS.has_feature("web") else "引擎内存 + 显存",
		"enemy_peak": enemy_peak, "guard": guard_hit or Cfg.guard_lowered,
		"q0": q0, "guard_stage": guard_stage, "enemy_mix": enemy_mix, "mem_mix": mem_mix, "slow": slow,
	}
	if Cfg.dev_args().has("--perfreport"):
		print("PF PERFREPORT " + report_text(rec).replace("
", " | "))   # 测试：网页测量副本只回传 PF 开头的行
	var all := load_all().duplicate()
	all.push_front(rec)
	save_all(all.slice(0, KEEP))


## 设备信息：网页取 UA、屏幕、devicePixelRatio、deviceMemory、CPU 核数；桌面取系统、型号、处理器、显卡、屏幕、内存
static func device() -> Dictionary:
	var vp: Vector2 = Engine.get_main_loop().root.get_visible_rect().size if Engine.get_main_loop() is SceneTree else Vector2.ZERO
	if OS.has_feature("web"):
		var js = JavaScriptBridge.eval("JSON.stringify({ua:navigator.userAgent,w:screen.width,h:screen.height,dpr:window.devicePixelRatio||1,mem:navigator.deviceMemory||0,cores:navigator.hardwareConcurrency||0,iw:window.innerWidth,ih:window.innerHeight})", true)
		var d = JSON.parse_string(str(js)) if js != null else null
		if d is Dictionary:
			d["view"] = "%dx%d" % [vp.x, vp.y]
			return d
		return {"ua": "", "view": "%dx%d" % [vp.x, vp.y]}
	var scr: Vector2i = DisplayServer.screen_get_size()
	var mi: Dictionary = OS.get_memory_info()
	return {"os": "%s %s" % [OS.get_name(), OS.get_version()], "model": OS.get_model_name(), "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "w": scr.x, "h": scr.y, "dpr": DisplayServer.screen_get_scale(),
		"ram_gb": snappedf(float(mi.get("physical", 0)) / 1073741824.0, 0.1), "view": "%dx%d" % [vp.x, vp.y]}


## 版本与提交号（data/build.json；源码运行时 commit 为 dev，tools/export_build.py 打包写真实提交号）
static func _build() -> Dictionary:
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
	return info if info is Dictionary else {}


## 测试：--perfout=<文件> 读写这个文件（godot_runner 每次启动给临时用户目录，截图验收要先跑一局写进去再开设置页读）
static func path() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--perfout="):
			return a.substr(10)
	return "user://perf_reports.json" if Cfg.dev_args().is_empty() else "user://perf_reports_test.json"


## 读过一次就缓存（设置页每帧画「性能报告」行要读最近一局）；save_all 时更新
static var _cache = null


static func load_all() -> Array:
	if _cache is Array:
		return _cache
	_cache = []
	if FileAccess.file_exists(path()):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
		if d is Array:
			_cache = d
	return _cache


static func save_all(a: Array) -> void:
	_cache = a
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(a))


# ---------------------------------------------------------------- 文本

const RESULT_NAME := {"win": "探索完成", "dead": "探索终止", "quit": "中途退出"}


static func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


## 一行设备说明：网页「浏览器 UA 摘要 · 屏幕 宽×高 @倍率 · 内存约 N GB」；桌面「系统 · 处理器 · 显卡 · 屏幕 · 内存」
static func device_line(d: Dictionary) -> String:
	if d.has("ua"):
		var ua: String = str(d.get("ua", ""))
		var m := RegEx.create_from_string("\\(([^)]*)\\)").search(ua)
		var plat: String = m.get_string(1) if m != null else ""
		var br := "Safari"
		for k in ["CriOS", "EdgiOS", "FxiOS", "Edg/", "Chrome/", "Firefox/", "Version/"]:
			if ua.contains(k):
				br = {"CriOS": "Chrome", "EdgiOS": "Edge", "FxiOS": "Firefox", "Edg/": "Edge", "Chrome/": "Chrome", "Firefox/": "Firefox", "Version/": "Safari"}[k]
				break
		var mem: String = "" if float(d.get("mem", 0)) <= 0.0 else " · 内存约 %s GB" % str(d.mem)
		return "%s（%s）· 屏幕 %d×%d @%s · 画布 %s%s" % [br, plat, int(d.get("w", 0)), int(d.get("h", 0)), str(snappedf(float(d.get("dpr", 1)), 0.01)), str(d.get("view", "")), mem]
	return "%s · %s · %s · 屏幕 %d×%d · 内存 %s GB" % [str(d.get("os", "")), str(d.get("cpu", "")), str(d.get("gpu", "")), int(d.get("w", 0)), int(d.get("h", 0)), str(d.get("ram_gb", "?"))]


static func frame_line(r: Dictionary) -> String:
	return "P50 %.1f / P95 %.1f / P99 %.1f 毫秒 · 最低 1 秒 %s 帧" % [float(r.get("p50", 0)), float(r.get("p95", 0)), float(r.get("p99", 0)),
		("%.0f" % float(r.get("min1s", 0))) if float(r.get("min1s", 0)) > 0.0 else "—"]


## 复制用的精简纯文本（贴进聊天）
static func report_text(r: Dictionary) -> String:
	var q: String = Cfg.QUALITY_NAME.get(str(r.get("quality", "")), str(r.get("quality", "")))
	var qm: String = "自动" if str(r.get("quality_mode", "")) == "auto" else "手选"
	var cap: int = int(r.get("fps_cap", 0))
	var cap_s: String = ("自动（已锁 30）" if r.get("lock30", false) else "自动") if cap == 0 else str(cap)
	var lines := [
		"方舟幸存者 · 性能报告",
		"版本 %s（%s）· %s" % [str(r.get("version", "")), str(r.get("commit", "")), str(r.get("time", "")).replace("T", " ")],
		"设备 " + device_line(r.get("device", {})),
		"画质 %s（%s）· 帧率上限 %s%s" % [q, qm, cap_s, " · 分辨率缩放" if r.get("render_scaled", false) else ""],
		"本局 %s · %s" % [_mmss(float(r.get("len", 0))), RESULT_NAME.get(str(r.get("result", "")), str(r.get("result", "")))],
		"帧时 " + frame_line(r),
	]
	var late: Dictionary = r.get("late", {})
	lines.append(("7 分钟后 " + frame_line(late)) if not late.is_empty() else "7 分钟后 —（本局未到 7 分钟）")
	lines.append("内存峰值 %d MB（%s）· 同屏敌人峰值 %d · 内存护栏 %s" % [int(r.get("mem_peak", 0)), str(r.get("mem_src", "")), int(r.get("enemy_peak", 0)), "已触发" if r.get("guard", false) else "未触发"])
	if r.has("q0"):   # 10-27 加的字段（旧记录没有）
		var gs: int = int(r.get("guard_stage", 0))
		lines.append("开局画质 %s · 护栏 %s" % [Cfg.QUALITY_NAME.get(str(r.q0), str(r.q0)), ["未触发", "只清缓存", "降画质", "分辨率缩放"][clampi(gs, 0, 3)]])
		lines.append("敌人峰值构成 " + _mix_text(r.get("enemy_mix", {}), "") + " · 内存峰值构成 " + _mix_text(r.get("mem_mix", {}), " MB"))
		var sl: Array = r.get("slow", [])
		if not sl.is_empty():
			var parts: Array = []
			for s in sl:
				var tg: Array = s[3] if s.size() > 3 else []
				parts.append("%s %d 帧（最长 %d 毫秒%s）" % [_mmss(float(s[1])), int(round(float(s[0]))), int(s[2]), ("：" + "、".join(PackedStringArray(tg.map(func(x): return str(x))))) if not tg.is_empty() else ""])
			lines.append("最慢 %d 秒 " % sl.size() + "；".join(PackedStringArray(parts)))
	return "\n".join(PackedStringArray(lines))


static func _mix_text(m: Dictionary, unit: String) -> String:
	var parts: Array = []
	for k in m:
		parts.append("%s %s%s" % [k, str(m[k]), unit])
	return " / ".join(PackedStringArray(parts)) if not parts.is_empty() else "—"


## 一局一行（设置页「更早的记录」）
static func short_line(r: Dictionary) -> String:
	return "%s  %s  %s  P95 %.1f 毫秒  最低 %s 帧" % [str(r.get("time", "")).replace("T", " ").substr(5, 11), _mmss(float(r.get("len", 0))),
		RESULT_NAME.get(str(r.get("result", "")), ""), float(r.get("p95", 0)), ("%.0f" % float(r.get("min1s", 0))) if float(r.get("min1s", 0)) > 0.0 else "—"]
