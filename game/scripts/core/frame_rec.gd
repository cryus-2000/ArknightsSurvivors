extends Node
## 界面帧时记录（--ftrec，docs/50 §27；只在测试参数下挂上，正常游戏不存在这个节点）。
## 每帧记真实帧间隔（墙钟，含渲染与等垂直同步），按「标记」分段：启动页 / 标题页首帧 / 打开寻访 / 切图鉴 / 结算 …
## 调用方 FR.mark("名字") 开新段（没挂上时什么也不做）。每段结束打印 PF FTSEG（帧数 / 平均 / P50 / P95 / P99 / 最长 / 超线帧数）；
## 超过 LONG_MS 的帧另打 PF FTLONG（段内秒数、帧长、这一帧全部 _process 的耗时 proc / 渲染 CPU / GPU / 贴图显存增量 / 绘制调用），
## 用来认长帧的来历：proc 大 = 脚本（含 load / 建节点）；rcpu 大 = 提交 / 着色器编译；都小 = _draw、场景切换、等待等其余部分。
## 行首都带「PF 」：网页测量副本（tools/perf_web.py）只回传 PF / PERF 开头的控制台行。
##   --ftquit=<标记>:<秒>        该标记之后 <秒> 退出（打印汇总）
##   --ftdo=<标记>:<秒>:<动作>   该标记之后 <秒> 让当前场景做一个动作（当前场景的 _ft_action(动作)，如标题页 hunt / gallery / gal_next）；可多个
## 工具：tools/probes/ui_frametimes.py（跑桌面 / 网页、汇总成表）。

const LONG_MS := 33.0
static var _inst: Node = null

var _segs: Array = []        # [{name, t0, dts: PackedFloat32Array}]
var _last := 0
var _vp: RID
var _tex_prev := 0.0
var _quit: Array = []        # [标记, 秒]
var _dos: Array = []         # [标记, 秒, 动作, 已做]
var _marks := {}             # 标记 -> 打下时的 usec
var _proc_start := 0
var _proc_end := 0
var _proc_ms := 0.0          # 上一帧全部 _process 的耗时（含场景切换后的 _ready 不算在内）


static func mark(name: String) -> void:
	if _inst != null:
		_inst._mark(name)


## 段内计时：距上一次 lap 超过 20 ms 时打印 PF FTLAP（找 _ready 之类一帧里的大块）
static var _lap_t := 0
static func lap(name: String) -> void:
	if _inst == null:
		return
	var now := Time.get_ticks_usec()
	if _lap_t > 0 and now - _lap_t > 20000:
		print("PF FTLAP %s %.0f ms" % [name, (now - _lap_t) / 1000.0])
	_lap_t = now


static func enabled() -> bool:
	return _inst != null


class _End extends Node:
	var rec
	func _process(_d: float) -> void:
		rec._proc_end = Time.get_ticks_usec()


func _init() -> void:
	_inst = self   # 挂上前（启动页 _ready 时）就能打标记


func _ready() -> void:
	process_priority = -100000
	var e := _End.new()
	e.rec = self
	e.process_priority = 100000   # 最后一个跑：两者之差 ≈ 这一帧全部 _process 的耗时
	e.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(e)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vp = get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ftquit="):
			var p := a.substr(9).split(":")
			_quit = [p[0], float(p[1]) if p.size() > 1 else 10.0]
		elif a.begins_with("--ftdo="):
			var p := a.substr(7).split(":")
			if p.size() >= 3:
				_dos.append([p[0], float(p[1]), p[2], false])
	_mark("start")


func _mark(name: String) -> void:
	_close_seg()
	var now := Time.get_ticks_usec()
	_marks[name] = now
	_segs.append({"name": name, "t0": now, "dts": PackedFloat32Array()})
	print("PF FTMARK %s t=%.3f" % [name, now / 1e6])


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_proc_ms = (_proc_end - _proc_start) / 1000.0 if _proc_end > _proc_start else -1.0
	_proc_start = now
	if _last > 0 and not _segs.is_empty():
		var dt := (now - _last) / 1000.0
		var s: Dictionary = _segs[-1]
		s.dts.append(dt)
		var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		if dt > LONG_MS:
			print("PF FTLONG seg=%s t=%.3f ms=%.1f proc=%.1f rcpu=%.1f gpu=%.1f tex=%+.2fMB draws=%d" % [s.name, (now - s.t0) / 1e6, dt,
				_proc_ms,
				RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu(),
				RenderingServer.viewport_get_measured_render_time_gpu(_vp),
				(tex - _tex_prev) / 1048576.0,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
		_tex_prev = tex
	_last = now
	for d in _dos:
		if not d[3] and _marks.has(d[0]) and now - int(_marks[d[0]]) >= int(float(d[1]) * 1e6):
			d[3] = true
			var sc := get_tree().current_scene
			if sc != null and sc.has_method("_ft_action"):
				sc._ft_action(str(d[2]))
			else:
				print("PF FTWARN no _ft_action for %s" % d[2])
	if not _quit.is_empty() and _marks.has(_quit[0]) and now - int(_marks[_quit[0]]) >= int(float(_quit[1]) * 1e6):
		_quit = []
		_close_seg()
		print("PF FTDONE")
		get_tree().quit()


func _exit_tree() -> void:
	_close_seg()


func _close_seg() -> void:
	if _segs.is_empty():
		return
	var s: Dictionary = _segs[-1]
	if s.get("closed", false):
		return
	s.closed = true
	var d: PackedFloat32Array = s.dts.duplicate()
	if d.is_empty():
		return
	d.sort()
	var n := d.size()
	var sum := 0.0
	var over := 0
	var over2 := 0
	for v in d:
		sum += v
		if v > 16.9:
			over += 1
		if v > LONG_MS:
			over2 += 1
	print("PF FTSEG %s n=%d mean=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.1f over16=%d over33=%d" % [s.name, n, sum / n,
		d[int(n * 0.5)], d[mini(n - 1, int(n * 0.95))], d[mini(n - 1, int(n * 0.99))], d[n - 1], over, over2])
