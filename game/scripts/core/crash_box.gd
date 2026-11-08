extends RefCounted
## 崩溃前快照（11-08 协调人：iPhone 局中白屏后强制刷新，崩掉的局没留下性能报告——报告只在局终写）。
## 对局中每 EVERY 秒把内存构成写进浏览器本地存储（同步写，页面被杀也留得住；桌面写 user://crash_box.json）：
##   贴图 / 缓冲区 / 显存 / 音频样本 / WASM 容量 / JS 堆 / 节点数 / 同屏怪 / 特效 / 弹 / 贴图缓存张数 / 这一段新读的贴图（张数 + 最近几张名字）/ 这一段的事件标签。
## 内存比上次写入涨了 SPIKE_MB 以上就立刻多写一条（抓尖峰，最快 3 秒一次）。网页另由 JS 记 WebGL 上下文丢失 / 切后台 / 回前台 / 页面隐藏 / 脚本错误。
## 正常离局（局终、回标题、重开）记 end；下次启动标题页时还没有 end = 上次异常退出 → 挪到「上次」那一份，
## 标题页左上角提示一行（core/crash_note.gd，点开看曲线、能复制），设置 → 画面 → 性能报告的「复制报告」也带上这一份。
## 只记真玩家局（无命令行参数）；测试加 --crashbox 记；图鉴演示 / Boss 演练不记。--crashbox_every=<秒> 改间隔（测试用）
const KEY := "sy_bb"
const PREV := "sy_bb_prev"
const FILE := "user://crash_box.json"
const PREV_FILE := "user://crash_box_prev.json"
const EVERY := 15.0
const SPIKE_MB := 24.0
const MAX_S := 80

static var on := false
static var cur := {}
static var _t := 0.0
static var _mem_t := 0.0
static var _last_mb := 0.0
static var _last_write := 0.0
static var _tags := {}
static var _load0 := 0
static var _every := EVERY
static var _js_ok := false
static var _checked := false
static var prev := {}     # 上次异常退出那一份（标题页 / 性能报告页读）
static var _wg := 0     # 已见过的 WASM 堆增长次数


static func _web() -> bool:
	return OS.has_feature("web")


## 对局 _ready：开一份新的（上一份没 end 的话先挪到「上次」，免得重开 / 连开两局时盖掉崩溃记录——正常走不到，以防万一）
static func begin(g) -> void:
	var args := Cfg.dev_args()
	on = (args.is_empty() or args.has("--crashbox")) and g.demo_op == "" and not g.trial.active
	if not on:
		return
	check_prev()
	_every = EVERY
	for a in args:
		if a.begins_with("--crashbox_every="):
			_every = maxf(1.0, float(a.substr(17)))
	_install_js()
	var A = load("res://scripts/art.gd")
	var b: Dictionary = load("res://scripts/core/perf_report.gd")._build()
	cur = {"v": 1, "start": Time.get_datetime_string_from_system(false, true), "ver": str(b.get("version", "dev")), "commit": str(b.get("commit", "dev")),
		"q": Cfg.quality, "dev": _dev_short(), "squad": "", "end": "", "s": [], "ev": []}
	_t = _every - 3.0   # 开局 3 秒记第一条（建局读完的贴图）
	_mem_t = 0.0
	_last_mb = 0.0
	_last_write = 0.0
	_tags = {}
	_load0 = int(A.load_n)
	_write(true)


static func _dev_short() -> String:
	if _web():
		var r = JavaScriptBridge.eval("(function(){var u=navigator.userAgent,m=u.match(/OS (\\d+[_\\d]*)/);return (/iPhone|iPad/.test(u)?'iOS '+(m?m[1].replace(/_/g,'.'):''):(/Android/.test(u)?'Android':'桌面'))+' '+screen.width+'x'+screen.height+'@'+(window.devicePixelRatio||1)+(/BiliApp|bili/i.test(u)?' B站':'')})()", true)
		return str(r) if r != null else ""
	return "%s %s" % [OS.get_name(), OS.get_model_name()]


## 事件标签（perf_report.tag 转过来：Boss 登场 / 读帧条 / 护栏…）：记进当前这一段
static func tag(name: String) -> void:
	if on:
		_tags[name] = int(_tags.get(name, 0)) + 1


## 每帧（game._process）：只累计时间；每秒取一次内存看尖峰，每 EVERY 秒写一条
static func tick(g, delta: float) -> void:
	if not on or cur.is_empty():
		return
	if cur.squad == "" and g.squad != null:
		cur.squad = ",".join(PackedStringArray(g.squad.ids()))
	var rd := delta / maxf(0.01, Engine.time_scale)   # 按真实时间（快进 / 慢动作不改间隔）
	_t += rd
	_mem_t += rd
	_last_write += rd
	if _t >= _every:
		sample(g)
		return
	if _mem_t >= 1.0:
		_mem_t = 0.0
		if _mem_mb() - _last_mb >= SPIKE_MB and _last_write >= 3.0:
			_tags["尖峰"] = 1
			sample(g)


static func _mem_mb() -> float:
	var vid: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	return vid + (Sfx.sample_mem_mb() if _web() else 0.0)


static func sample(g) -> void:
	_t = 0.0
	_last_write = 0.0
	var A = load("res://scripts/art.gd")
	var tex: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buf: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	var vid: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var aud: float = Sfx.sample_mem_mb() if _web() else 0.0
	var wasm := 0.0
	var js := 0.0
	if _web():
		var r = JavaScriptBridge.eval("(function(){var w=window.__syWasm,r={w:w&&w.buffer?w.buffer.byteLength:0,g:(window.__syWasmGrows||[]).length};if(performance.memory){r.j=performance.memory.usedJSHeapSize}return JSON.stringify(r)})()", true)
		var d = JSON.parse_string(str(r)) if r != null else null
		if d is Dictionary:
			wasm = float(d.get("w", 0)) / 1048576.0
			js = float(d.get("j", 0)) / 1048576.0
			if int(d.get("g", 0)) > _wg:
				_wg = int(d.get("g", 0))
				_tags["WASM 堆增长"] = 1   # 这一段里堆又涨过（engine_patch.py §3）
	else:
		wasm = OS.get_static_memory_usage() / 1048576.0   # 桌面：引擎静态内存放在同一列
	_last_mb = vid + aud
	var nfx: int = g.fx.size() + (g.ult.shapes.size() if g.ult != null else 0)
	var ln: int = int(A.load_n)
	var s := {"t": int(g.t), "tex": int(tex), "buf": int(buf), "vid": int(vid), "aud": int(aud), "wasm": int(wasm), "js": int(js),
		"node": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "obj": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"e": g.enemies.size(), "fx": nfx, "b": g.bullets.size() + g.ebullets.size(), "lv": int(g.level),
		"tc": A._cache.size(), "ld": ln - _load0, "rl": ",".join(A.recent_loads.slice(-6)), "tag": ",".join(PackedStringArray(_tags.keys())), "q": Cfg.quality}
	_load0 = ln
	_tags = {}
	if Cfg.dev_args().has("--crashbox"):
		print("PF CRASHBOX sample t=%d tex=%d buf=%d e=%d ld=%d tag=%s" % [s.t, s.tex, s.buf, s.e, s.ld, s.tag])
	var a: Array = cur.s
	a.append(s)
	if a.size() > MAX_S:
		a.remove_at(4)   # 留开头 4 条（开局基线），丢中间最早的
	_write()


## 正常离局（局终 / 回标题 / 重开）：记 end
static func end(why: String) -> void:
	if not on or cur.is_empty() or cur.end != "":
		return
	cur.end = why
	_write()


static func _write(fresh := false) -> void:
	var j := JSON.stringify(cur)
	if _web():   # ev 由 JS 侧追加：写引擎这份时把已存的 ev 并进来（新开一份时不并上一份的）
		var src := "null" if fresh else "localStorage.getItem('%s')" % KEY
		JavaScriptBridge.eval("try{var o=JSON.parse(%s),p=%s;if(p){try{o.ev=JSON.parse(p).ev||[]}catch(e){}}localStorage.setItem('%s',JSON.stringify(o))}catch(e){}" % [JSON.stringify(j), src, KEY], true)
	else:
		var f := FileAccess.open(FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(j)


## 网页：JS 侧事件（WebGL 上下文丢失 / 恢复、切后台 / 回前台、页面隐藏、脚本错误）直接追加进同一份记录的 ev（不经引擎，主循环卡死时也写得进）
static func _install_js() -> void:
	if not _web() or _js_ok:
		return
	_js_ok = true
	JavaScriptBridge.eval("""(function(){if(window.__syBB)return;window.__syBB=1;var t0=Date.now();
function ev(n){try{var s=localStorage.getItem('sy_bb');if(!s)return;var o=JSON.parse(s);if(o.end)return;(o.ev=o.ev||[]).push([Math.round((Date.now()-t0)/1000),n,new Date().toTimeString().slice(0,8)]);if(o.ev.length>40)o.ev=o.ev.slice(-40);localStorage.setItem('sy_bb',JSON.stringify(o))}catch(e){}}
window.__syBBev=ev;
var c=document.querySelector('canvas');if(c){c.addEventListener('webglcontextlost',function(){ev('WebGL上下文丢失')});c.addEventListener('webglcontextrestored',function(){ev('WebGL上下文恢复')})}
document.addEventListener('visibilitychange',function(){ev(document.hidden?'切后台':'回前台')});
addEventListener('pagehide',function(){ev('页面隐藏')});
addEventListener('error',function(e){ev('脚本错误 '+String(e.message||'').slice(0,60))});
addEventListener('unhandledrejection',function(e){ev('未处理拒绝 '+String(e.reason&&e.reason.message||e.reason||'').slice(0,60))});})()""", true)


## 启动后第一次进标题 / 对局时查：上一份没 end = 异常退出，挪到「上次」。返回「上次」那份（没有就空）
static func check_prev() -> Dictionary:
	if _checked:
		return prev
	_checked = true
	var raw := ""
	var praw := ""
	if _web():
		var r = JavaScriptBridge.eval("""(function(){var S=localStorage,s=S.getItem('sy_bb');try{if(s){var o=JSON.parse(s);if(!o.end){S.setItem('sy_bb_prev',s);S.removeItem('sy_bb')}}}catch(e){}
return S.getItem('sy_bb_prev')||''})()""", true)
		praw = str(r) if r != null else ""
	else:
		if FileAccess.file_exists(FILE):
			raw = FileAccess.get_file_as_string(FILE)
			var o = JSON.parse_string(raw)
			if o is Dictionary and str(o.get("end", "")) == "":
				var f := FileAccess.open(PREV_FILE, FileAccess.WRITE)
				if f != null:
					f.store_string(raw)
				DirAccess.remove_absolute(FILE)
		if FileAccess.file_exists(PREV_FILE):
			praw = FileAccess.get_file_as_string(PREV_FILE)
	var d = JSON.parse_string(praw) if praw != "" else null
	prev = d if d is Dictionary else {}
	if Cfg.dev_args().has("--crashbox"):
		print("PF CRASHBOX prev=%d
%s" % [int(not prev.is_empty()), report_text(prev)])
	return prev


## 「上次」那份看过、点了「关闭」：标题页不再提示（性能报告页仍带着，直到下一次异常退出覆盖）
static func ack() -> void:
	if prev.is_empty():
		return
	prev["seen"] = 1
	var j := JSON.stringify(prev)
	if _web():
		JavaScriptBridge.eval("try{localStorage.setItem('%s',%s)}catch(e){}" % [PREV, JSON.stringify(j)], true)
	else:
		var f := FileAccess.open(PREV_FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(j)


static func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


## 标题页一行提示
static func short_line(p: Dictionary) -> String:
	var a: Array = p.get("s", [])
	if a.is_empty():
		return "上次对局异常退出（开局前就停了）· 点此查看"
	var last: Dictionary = a[-1]
	var pk := 0
	for s in a:
		pk = maxi(pk, int(s.get("vid", 0)) + int(s.get("aud", 0)))
	return "上次对局异常退出（局内 %s，显存 + 音频峰值 %d MB）· 点此查看 / 复制" % [_mmss(float(last.get("t", 0))), pk]


## 曲线纯文本（复制发回给我们）
static func report_text(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	var o := PackedStringArray()
	o.append("【上次异常退出前的内存曲线】%s 开局  版本 %s（%s）  %s  编队 %s  画质 %s" % [str(p.get("start", "")), str(p.get("ver", "")), str(p.get("commit", "")),
		str(p.get("dev", "")), str(p.get("squad", "")), str(p.get("q", ""))])
	o.append("局内 贴图 缓冲 显存 音频 WASM JS | 节点 对象 怪 特效 弹 等级 | 缓存张 新读 | 事件")
	for s in p.get("s", []):
		o.append("%s %d %d %d %d %d %d | %d %d %d %d %d %d | %d %d | %s" % [_mmss(float(s.get("t", 0))), int(s.get("tex", 0)), int(s.get("buf", 0)), int(s.get("vid", 0)),
			int(s.get("aud", 0)), int(s.get("wasm", 0)), int(s.get("js", 0)), int(s.get("node", 0)), int(s.get("obj", 0)), int(s.get("e", 0)), int(s.get("fx", 0)),
			int(s.get("b", 0)), int(s.get("lv", 0)), int(s.get("tc", 0)), int(s.get("ld", 0)), str(s.get("tag", ""))])
	var a: Array = p.get("s", [])
	if not a.is_empty():
		o.append("最后一段新读的贴图：" + str(a[-1].get("rl", "")))
	var ev: Array = p.get("ev", [])
	if not ev.is_empty():
		var es := PackedStringArray()
		for e in ev:
			if e is Array and e.size() >= 3:
				es.append("%s %s" % [str(e[2]), str(e[1])])
		o.append("页面事件：" + "；".join(es))
	return "\n".join(o)


## 打开查看面板：网页 DOM（复制 / 保存文件 / 关闭，按钮本身是用户手势，iOS 剪贴板才放行）；桌面进剪贴板。on_close 在点「关闭」后调
static func open_panel(t: String) -> void:
	if _web():
		load("res://scripts/core/perf_hud.gd").dom_panel(t, "sy-crash-log")
		return
	DisplayServer.clipboard_set(t)
