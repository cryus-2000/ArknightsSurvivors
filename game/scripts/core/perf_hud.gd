extends CanvasLayer
## 性能自检浮层（11-07，协调人转用户「先把稳定搞定」：iPhone 网页「顶不住」，要真机数据）。缺省关；打开后挂在场景树根上，跨标题 / 对局常驻。
## 打开：网址带 ?perf=1（?perf=0 关），或 设置 → 画面 → 性能报告 页里连点标题 5 次（开关存在本机，下次启动照旧）。公开版也能开。
## 关着时零开销：只在标题 / 对局 _ready 时调一次 ensure()（本次启动只判断一次开关）。
## 浮层（左上角小字，每秒刷新）：帧率 当前 / 最近 10 秒最低、帧时 P50 / P95；内存（网页：WASM 堆 / JS 堆（浏览器给才有）/ 显存 / 贴图 / 音频样本；
## 桌面：引擎静态内存 / 显存 / 贴图）；同屏怪 / 弹 / 特效条目；画质档、帧率上限、护栏降档与时刻；局内时间、编队。
## 日志：每 10 秒一行 + 事件行（进出对局、画质变化、护栏），最多 LOG_MAX 行；网页同步写 localStorage（闪退也留得住），桌面写 user://。
## 上次没正常退出（网页：页面在前台时被杀，localStorage 里「在跑」标记没清）→ 浮层提示「上次异常退出」，点开日志看上次的记录。
## 点一下浮层：打开日志面板（网页是 DOM 面板，「复制」「保存文件」按钮本身就是用户手势，iOS 剪贴板才放行）
const PerfReport = preload("res://scripts/core/perf_report.gd")

const FLAG := "user://perf_hud.on"
const LOG_FILE := "user://perf_hud_log.txt"
const PREV_FILE := "user://perf_hud_prev.txt"
const ALIVE_FILE := "user://perf_hud.alive"
const LOG_EVERY := 10.0
const LOG_MAX := 400
const WIN_S := 10.0

static var _checked := false
static var _on := false

var lb: Label
var bg: ColorRect
var ft := PackedFloat32Array()   # 最近 10 秒的帧间隔（毫秒）
var ft_at := PackedFloat64Array()
var _last_us := 0
var _log_t := 0.0
var lines: PackedStringArray = []
var prev := ""            # 上次（异常退出那次）的日志
var crashed := false
var events: PackedStringArray = []
var _q := ""
var _guard := 0
var _lock30 := false
var _gid := 0
var _min10 := PackedFloat32Array()   # 最近 10 个整秒的帧率
var _fsec := 0
var _fsec_t := 0.0


## 本次启动开着没有（只算一次）：网址 ?perf=1 / ?perf=0 写开关，其余看本机开关文件
static func enabled() -> bool:
	if _checked:
		return _on
	_checked = true
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("(location.search.match(/[?&]perf=([01])/)||[])[1]||''", true)
		if str(q) == "1":
			_set_flag(true)
		elif str(q) == "0":
			_set_flag(false)
	_on = FileAccess.file_exists(FLAG) or Cfg.dev_args().has("--perfhud")   # 测试：--perfhud 只开本次，不写开关文件
	return _on


static func _set_flag(v: bool) -> void:
	if v:
		var f := FileAccess.open(FLAG, FileAccess.WRITE)
		if f != null:
			f.store_string("1")
	elif FileAccess.file_exists(FLAG):
		DirAccess.remove_absolute(FLAG)


## 标题 / 对局 _ready 调：开着就挂一个到场景树根上（已有就不再挂）
static func ensure(tree: SceneTree) -> void:
	if tree == null or not enabled():
		return
	if tree.root.get_node_or_null("PerfHud") != null:
		return
	var h = load("res://scripts/core/perf_hud.gd").new()
	h.name = "PerfHud"
	tree.root.call_deferred("add_child", h)


## 性能报告页连点 5 次：切换开关，立刻挂上 / 拿掉；返回新状态
static func toggle(tree: SceneTree) -> bool:
	_checked = true
	_on = not FileAccess.file_exists(FLAG)
	_set_flag(_on)
	if _on:
		ensure(tree)
	else:
		var n := tree.root.get_node_or_null("PerfHud")
		if n != null:
			n.queue_free()
	return _on


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_tap)
	add_child(bg)
	lb = Label.new()
	lb.add_theme_font_override("font", load("res://fonts/ui.ttf"))
	lb.add_theme_color_override("font_color", Color(0.62, 1.0, 0.92))
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 3)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
	_start_session()
	_log(PerfReport.device_line(PerfReport.device()))
	var b := PerfReport._build()
	_log("版本 %s（%s）%s" % [str(b.get("version", "dev")), str(b.get("commit", "dev")), str(b.get("audience", ""))])
	_tick_sec()


## 「在跑」标记：上次没清掉 = 异常退出，把上次日志挪到 prev。网页切后台时清标记（被系统回收后台页不算闪退），回前台再置上
func _start_session() -> void:
	if OS.has_feature("web"):
		var r = JavaScriptBridge.eval("""(function(){var S=localStorage,a=S.getItem('sy_perf_alive')==='1';
if(a){S.setItem('sy_perf_prev',S.getItem('sy_perf_log')||'')}
S.setItem('sy_perf_alive','1');S.setItem('sy_perf_log','');
if(!window.__syPerfVis){window.__syPerfVis=1;
document.addEventListener('visibilitychange',function(){S.setItem('sy_perf_alive',document.hidden?'0':'1')});
addEventListener('pagehide',function(){S.setItem('sy_perf_alive','0')})}
return JSON.stringify({a:a,p:a?(S.getItem('sy_perf_prev')||''):''})})()""", true)
		var d = JSON.parse_string(str(r)) if r != null else null
		if d is Dictionary:
			crashed = bool(d.get("a", false))
			prev = str(d.get("p", ""))
	else:
		crashed = FileAccess.file_exists(ALIVE_FILE)
		if crashed and FileAccess.file_exists(LOG_FILE):
			prev = FileAccess.get_file_as_string(LOG_FILE)
			var f := FileAccess.open(PREV_FILE, FileAccess.WRITE)
			if f != null:
				f.store_string(prev)
		var fa := FileAccess.open(ALIVE_FILE, FileAccess.WRITE)
		if fa != null:
			fa.store_string("1")
	if crashed:
		_event("上次异常退出（点浮层查看上次日志）")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if not OS.has_feature("web") and FileAccess.file_exists(ALIVE_FILE):
			DirAccess.remove_absolute(ALIVE_FILE)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		var ms := (now - _last_us) / 1000.0
		if ms < 1000.0:
			ft.append(ms)
			ft_at.append(now / 1e6)
	_last_us = now
	# 整秒帧数与每秒刷新都按真实时间（delta 在 --fixed-fps / 慢动作 / 倍速下不是真实间隔）
	var ts := now / 1e6
	_fsec += 1
	if _fsec_t <= 0.0:
		_fsec_t = ts
	elif ts - _fsec_t >= 1.0:
		_min10.append(_fsec / (ts - _fsec_t))
		if _min10.size() > int(WIN_S):
			_min10.remove_at(0)
		_fsec = 0
		_fsec_t = ts
		_tick_sec()


func _game():
	var cs = get_tree().current_scene
	return cs if cs != null and "enemies" in cs and "squad" in cs else null


func _mem() -> Dictionary:
	var m := {"vid": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"tex": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		"stat": OS.get_static_memory_usage() / 1048576.0}
	if OS.has_feature("web"):
		m["aud"] = Sfx.sample_mem_mb()
		var r = JavaScriptBridge.eval("(function(){var w=window.__syWasm,r={w:w&&w.buffer?w.buffer.byteLength:0};if(performance.memory){r.j=performance.memory.usedJSHeapSize;r.jl=performance.memory.jsHeapSizeLimit}return JSON.stringify(r)})()", true)
		var d = JSON.parse_string(str(r)) if r != null else null
		if d is Dictionary:
			m["wasm"] = float(d.get("w", 0)) / 1048576.0
			if d.has("j"):
				m["js"] = float(d.j) / 1048576.0
	return m


func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[mini(s.size() - 1, int(p * s.size()))]


func _tick_sec() -> void:
	var tnow := Time.get_ticks_usec() / 1e6
	while not ft_at.is_empty() and tnow - ft_at[0] > WIN_S:
		ft_at.remove_at(0)
		ft.remove_at(0)
	var g = _game()
	var gid: int = g.get_instance_id() if g != null else 0
	if gid != _gid:
		_event("进入对局" if g != null else "离开对局")
		_gid = gid
	# 画质 / 帧率上限 / 护栏：变化就记事件
	var stage: int = int(g.perf_rep.guard_stage) if g != null and "perf_rep" in g else 0
	if Cfg.quality != _q and _q != "":
		_event("画质 %s → %s%s" % [_q, Cfg.quality, "（护栏降档）" if Cfg.guard_lowered else ""])
	_q = Cfg.quality
	if stage > _guard:
		_event("内存护栏 第 %d 步（%s）" % [stage, ["", "清缓存", "降低画质", "分辨率缩放"][mini(stage, 3)]])
	_guard = stage
	if Cfg.fps_lock30 != _lock30:
		_event("帧率自动锁 30" if Cfg.fps_lock30 else "帧率解除锁 30")
	_lock30 = Cfg.fps_lock30
	var fps := Engine.get_frames_per_second()
	var mn: float = 0.0
	for v in _min10:
		mn = v if mn <= 0.0 else minf(mn, v)
	var m := _mem()
	var l1 := "FPS %.0f  最低 %.0f  帧时 P50 %.1f / P95 %.1f ms" % [fps, mn, _pct(ft, 0.5), _pct(ft, 0.95)]
	var l2 := ""
	if OS.has_feature("web"):
		l2 = "内存 WASM %.0f%s  显存 %.0f  贴图 %.0f  音频 %.0f MB" % [float(m.get("wasm", 0.0)), ("  JS %.0f" % float(m.js)) if m.has("js") else "", m.vid, m.tex, float(m.get("aud", 0.0))]
	else:
		l2 = "内存 引擎 %.0f  显存 %.0f  贴图 %.0f MB" % [m.stat, m.vid, m.tex]
	var l3 := ""
	var l4 := "画质 %s%s  帧率上限 %s%s%s" % [Cfg.quality, "（自动）" if Cfg.quality_mode == "auto" else "", str(Engine.max_fps) if Engine.max_fps > 0 else "不限",
		"  锁30" if Cfg.fps_lock30 else "", ("  护栏 %d" % stage) if stage > 0 else ""]
	var l5 := ""
	if g != null:
		var nfx: int = g.fx.size() + (g.ult.shapes.size() if g.ult != null else 0)
		l3 = "怪 %d  弹 %d  敌弹 %d  特效 %d" % [g.enemies.size(), g.bullets.size(), g.ebullets.size(), nfx]
		l5 = "局内 %d:%02d  编队 %s" % [int(g.t) / 60, int(g.t) % 60, ",".join(PackedStringArray(g.squad.ids()))]
	var tail := events[events.size() - 1] if not events.is_empty() else ""
	var txt := "\n".join(_nz([l1, l2, l3, l4, l5, tail, "点此查看 / 复制日志"]))
	lb.text = txt
	var k: float = 1.0 if not Pad.touch_ui() else 1.25
	lb.add_theme_font_size_override("font_size", int(11 * k))
	lb.position = Vector2(6, 26)
	var sz: Vector2 = lb.get_combined_minimum_size()
	lb.size = sz
	bg.position = lb.position - Vector2(4, 2)
	bg.size = sz + Vector2(8, 4)
	_log_t += 1.0
	if _log_t >= LOG_EVERY:
		_log_t = 0.0
		_log(" | ".join(_nz([l1, l2, l3, l4, l5])))


func _nz(a: Array) -> PackedStringArray:
	var o := PackedStringArray()
	for x in a:
		if str(x) != "":
			o.append(str(x))
	return o


func _event(s: String) -> void:
	events.append("%s %s" % [_clock(), s])
	if events.size() > 20:
		events.remove_at(0)
	_log("★ " + s)


func _clock() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%02d:%02d:%02d" % [d.hour, d.minute, d.second]


func _log(s: String) -> void:
	lines.append("%s %s" % [_clock(), s])
	if lines.size() > LOG_MAX:
		lines.remove_at(0)
	var all := "\n".join(lines)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{localStorage.setItem('sy_perf_log',%s)}catch(e){}" % JSON.stringify(all), true)
	else:
		var f := FileAccess.open(LOG_FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(all)


func log_text() -> String:
	var s := "【方舟幸存者 性能自检日志】\n" + "\n".join(lines)
	if crashed and prev != "":
		s += "\n\n【上次（异常退出那次）的日志】\n" + prev
	return s


## 点浮层：在 _input 里先截（标题 / 启动页 / 对局会在 _input 里吃掉点击，等不到 GUI 事件）；浮层挂在根的最后，最先收到
func _input(ev: InputEvent) -> void:
	var p := Vector2.INF
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		p = ev.position
	elif ev is InputEventScreenTouch and ev.pressed:
		p = ev.position
	if p != Vector2.INF and bg.get_global_rect().has_point(p):
		get_viewport().set_input_as_handled()
		open_log()


func _on_tap(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		bg.accept_event()


## 日志面板：网页用 DOM（复制 / 保存文件 / 关闭三个按钮，点按钮本身就是用户手势）；桌面直接进剪贴板 + 存文件
func open_log() -> void:
	var t := log_text()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""(function(t){var o=document.getElementById('sy-perf-log');if(o)o.remove();
o=document.createElement('div');o.id='sy-perf-log';
o.style.cssText='position:fixed;left:4%;top:5%;width:92%;height:86%;z-index:99999;background:#0d1419;border:1px solid #3fd2e6;padding:10px;box-sizing:border-box;display:flex;flex-direction:column;gap:8px;font-family:sans-serif';
var a=document.createElement('textarea');a.value=t;a.readOnly=true;
a.style.cssText='flex:1;width:100%;font-size:13px;line-height:1.45;color:#e6eef2;background:#05090c;border:1px solid #2a3a44;padding:6px;box-sizing:border-box';
var n=document.createElement('div');n.style.cssText='color:#f2c94c;font-size:14px;min-height:18px';
var row=document.createElement('div');row.style.cssText='display:flex;gap:8px';
function B(s,f){var b=document.createElement('button');b.textContent=s;b.style.cssText='flex:1;height:46px;font-size:17px;color:#0d1419;background:#3fd2e6;border:0;border-radius:4px';b.onclick=f;row.appendChild(b);return b}
B('复制',function(){var ok=function(){n.textContent='已复制，可以直接粘贴发给我们'};
try{navigator.clipboard.writeText(t).then(ok,function(){a.focus();a.select();try{document.execCommand('copy');ok()}catch(e){n.textContent='没能复制：请长按文字全选后复制'}})}
catch(e){a.focus();a.select();try{document.execCommand('copy');ok()}catch(e2){n.textContent='没能复制：请长按文字全选后复制'}}});
B('保存文件',function(){try{var u=URL.createObjectURL(new Blob([t],{type:'text/plain'}));var l=document.createElement('a');l.href=u;l.download='perf_log.txt';document.body.appendChild(l);l.click();l.remove();setTimeout(function(){URL.revokeObjectURL(u)},4000);n.textContent='已保存（在「文件」或下载里）'}catch(e){n.textContent='这里不能存文件：请用「复制」'}});
B('关闭',function(){o.remove()});
o.appendChild(a);o.appendChild(n);o.appendChild(row);document.body.appendChild(o)})(%s)""" % JSON.stringify(t), true)
		return
	DisplayServer.clipboard_set(t)
	var p := "user://perf_log_%d.txt" % int(Time.get_unix_time_from_system())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(t)
	_event("日志已复制到剪贴板，并存到 %s" % ProjectSettings.globalize_path(p))
