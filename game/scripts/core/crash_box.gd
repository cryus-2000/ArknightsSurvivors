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
const BOSS_WAVES := 3   # 三波登场前后各一份，另加估算峰值和最后一次采样，共八份
static var _peak_mb := -1.0
static var _context_dirty := false
static var _wave := 0    # 已记录实际出生的 Boss 所在波次

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
static var _rt := 0.0   # 开局后的真实秒数（选卡 / 暂停时局内时间不走，靠它分清同一局内时间的几条）

## ---- 11-11 闪退报告补采样（docs/332 §4，协调人：重编队终局闪退时可见读数解释不了）
## 高频环形缓冲：每 HF_EVERY 秒一行，留最后 HF_MAX 行（约 60 秒），单独写 sy_bb_hf（小记录，不重写整份曲线）；
## 事件日志：终结技、Boss 登场、换曲 / 最终 Boss 二阶段、≥ 512 KiB 的贴图读入 / 释放（含白剪影）、读帧条、护栏、掉帧档，留最后 EVL_MAX 条，同写 sy_bb_hf；
## 上传量：art.note_up 累计的新读入贴图字节，每行记这一段的量，另记整局「每秒上传」峰值与最大单张；
## 尖峰补采：终结技、Boss 登场、读帧条当下补一行，1.5 秒后再补一行（看读完 / 放完之后）。
## 只在手机网页的真玩家局开（或测试 --crashbox）；桌面不开高频
const HF_EVERY := 2.0
const HF_MAX := 30
const EVL_MAX := 30
const HF_KEY := "sy_bb_hf"
static var _hf_on := false
static var _hf: Array = []
static var _hf_t := 0.0
static var _hf_after := -1.0
static var _hf_cd := 0.0
static var _evl: Array = []
static var _evn := {}
static var _up_last := 0       # 上一行时 art.up_bytes
static var _up_sec_b := -1     # 上一秒时 art.up_bytes
static var _up_sec_t := 0.0
static var up_peak := {}       # 整局每秒上传峰值 {b, t}
static var _opened := {}       # 本页（整页重载后清零）开过的界面次数：寻访 / 图鉴
static var _mus_last := ""
static var _page_um := {}   # 进局前（局外）最大单张，正常结算报告也带


## 界面打开计数（headhunt._intro_go / gallery._ready 调）
static func opened(what: String) -> void:
	_opened[what] = int(_opened.get(what, 0)) + 1


## 事件日志一条（实时秒 + 局内秒）；spike = 当下补采一行，1.5 秒后再补一行
static func event(text: String, spike := false) -> void:
	if not on or not _hf_on:
		return
	_evl.append([int(_rt), _cur_t(), text])
	if _evl.size() > EVL_MAX:
		_evl.pop_front()
	if spike and is_instance_id_valid(_owner):
		if _hf_cd <= 0.0:
			_hf_cd = 0.5
			_hf_sample(instance_from_id(_owner))
		_hf_after = _rt + 1.5


## 终结技放出（ult._cast）：谁、本局第几次
static func ult_cast(who: String) -> void:
	if not on:
		return
	_evn[who] = int(_evn.get(who, 0)) + 1
	event("终结技 %s 第 %d 次" % [who, int(_evn[who])], true)


static func _cur_t() -> int:
	if is_instance_id_valid(_owner):
		var g = instance_from_id(_owner)
		if g != null and "t" in g:
			return int(g.t)
	return 0


static func _web() -> bool:
	return OS.has_feature("web")


## 网页：记下当前阶段（开机 / 标题 / 建局·各段 / 局内），engine_patch 的堆增长记录带上它，真机快照能看出 WASM 是在哪一段撑大的（docs/319 §13）
static func phase(n: String) -> void:
	if _web():
		JavaScriptBridge.eval("window.__syPhase=%s" % JSON.stringify(n), true)
		load("res://scripts/art.gd").memlive("phase:" + n, true)


## 配乐走哪条路：web = 浏览器解码（web_music.js）；engine = 引擎样本；后面带浏览器解码失败次数
static func _music_mode() -> String:
	if not _web():
		return "engine"
	return "web" if not Sfx._wm.is_empty() else "engine"


## 对局 _ready：开一份新的（上一份没 end 的话先挪到「上次」，免得重开 / 连开两局时盖掉崩溃记录——正常走不到，以防万一）
static var _owner := 0   # 正在记录的那一局（game 实例 id）

static func begin(g) -> void:
	var args := Cfg.dev_args()
	# 演示实例（精英化演出 / 图鉴演示 / Boss 演练）不记，也不许碰正在记的那一局：原来这里把静态 on 直接改成 false，
	# 局中精英化演出一开就把本局快照关了（11-09 真机：快照停在 0:41、局终 end 没写，被判成异常退出）
	if not ((args.is_empty() or args.has("--crashbox")) and g.demo_op == "" and not g.trial.active):
		return
	on = true
	_owner = g.get_instance_id()
	if _web():
		JavaScriptBridge.eval("try{localStorage.removeItem('sy_bb_hb');localStorage.removeItem('sy_bb_err')}catch(e){}", true)
	check_prev()
	_every = EVERY
	for a in args:
		if a.begins_with("--crashbox_every="):
			_every = maxf(1.0, float(a.substr(17)))
	_install_js()
	var A = load("res://scripts/art.gd")
	var b: Dictionary = load("res://scripts/core/perf_report.gd")._build()
	cur = {"v": 1, "start": Time.get_datetime_string_from_system(false, true), "ver": str(b.get("version", "dev")), "commit": str(b.get("commit", "dev")),
		"q": Cfg.quality, "dev": _dev_short(), "squad": "", "end": "", "s": [], "ev": [], "mus": _music_mode(), "wg": [], "sr": 0}
	cur["run_id"] = load("res://scripts/core/run_reload.gd").run_identity()
	cur["journey"] = load("res://scripts/core/run_reload.gd").journey_snapshot(cur.run_id)
	cur["context"] = g.perf_context.snapshot(g)
	cur["memory_snapshots"] = {}
	_peak_mb = -1.0
	_wave = 0
	_context_dirty = false
	var changed := _context_changed.bind(_owner)
	if not g.perf_context.changed.is_connected(changed):
		g.perf_context.changed.connect(changed)
	_t = _every - 3.0   # 开局 3 秒记第一条（建局读完的贴图）
	_mem_t = 0.0
	_last_mb = 0.0
	_last_write = 0.0
	_tags = {}
	_load0 = int(A.load_n)
	_rt = 0.0
	_hf_on = _web() and (Cfg.mobile_web() or args.has("--crashbox"))
	_hf = []
	_evl = []
	_evn = {}
	_hf_t = 0.0
	_hf_after = -1.0
	_up_last = int(A.up_bytes)
	_up_sec_b = -1
	_up_sec_t = 0.0
	up_peak = {}
	_mus_last = ""
	cur["open"] = _opened.duplicate()
	# 最大单张分两段（11-11 协调人：iPhone 报告「本页最大单张」是编队外干员的特效——局外图鉴 / 寻访演示读的，进局时 drop_outrun 已放掉）：
	# 进局前（标题 / 图鉴 / 寻访 / 载入页）那张存进 um_page，art.up_max 清零后只记本局
	cur["um_page"] = (A.up_max as Dictionary).duplicate()
	A.up_max = {}
	A.up_owner = {}
	_page_um = cur.um_page
	if _web():
		var w0 = JavaScriptBridge.eval("(function(){var w=window.__syWasm;return w&&w.buffer?w.buffer.byteLength:0})()", true)
		cur["wasm0"] = int(float(w0) / 1048576.0) if w0 != null else 0
		JavaScriptBridge.eval("try{localStorage.removeItem('%s')}catch(e){}" % HF_KEY, true)
	_write(true)


static func _context_changed(owner: int) -> void:
	if not on or owner != _owner or _context_dirty:
		return
	_context_dirty = true
	_flush_context.call_deferred(owner)


static func _flush_context(owner: int) -> void:
	if on and owner == _owner and is_instance_id_valid(owner) and _refresh_context(instance_from_id(owner)):
		_write()


## 同帧种子、设置、编队和双 Boss 事件合并。首次取得种子、每波首次登场各最多额外写一次；
## 若本帧本来就要采样 / 结束，由那次落盘捎带，已排队的延迟回调不再写。
static func _refresh_context(g) -> bool:
	if not _context_dirty:
		return false
	_context_dirty = false
	var context: Dictionary = g.perf_context.snapshot(g)
	var store_now: bool = not cur.context.has("seed") and context.has("seed")
	if context.get("bosses", []).size() > cur.context.get("bosses", []).size() and g.spawner != null:
		var wave := int(g.spawner.boss_idx)
		if wave > _wave and wave <= BOSS_WAVES:
			_wave = wave
			_mark_before(cur.memory_snapshots, wave)
			store_now = true
		var bl: Array = context.get("bosses", [])
		event(("Boss 登场 " + str(bl[-1])) if not bl.is_empty() else "Boss 登场", true)
	cur.context = context
	return store_now


static func _mark_before(points: Dictionary, wave: int) -> void:
	if wave < 1 or wave > BOSS_WAVES or not points.has("last"):
		return
	var key := "before%d" % wave
	if not points.has(key) and not points.has("after%d" % wave):
		points[key] = points.last


static func _keep_snapshot(points: Dictionary, row: Dictionary, wave: int, peak: bool) -> void:
	_mark_before(points, wave)
	if wave >= 1 and wave <= BOSS_WAVES and not points.has("after%d" % wave):
		points["after%d" % wave] = row
	if peak:
		points.peak = row
	points.last = row


## perf_report.finish 在 CrashBox.end 之前调用；只给同一局，正常报告不持有滚动曲线或大对象。
static func report_context(g) -> Dictionary:
	if cur.is_empty() or g.get_instance_id() != _owner:
		return {}
	return {"memory_snapshots": cur.get("memory_snapshots", {}).duplicate(true)}


static func snapshot_lines(record: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var points: Dictionary = record.get("memory_snapshots", {})
	if points.is_empty():
		return lines
	lines.append("关键内存快照 · 既有周期及尖峰采样，峰值取这些采样中的最高值；配乐计入音频")
	for wave in range(1, BOSS_WAVES + 1):
		for side in ["before", "after"]:
			var key := "%s%d" % [side, wave]
			if points.has(key):
				lines.append(_snapshot_line("第 %d 波 Boss 登场%s" % [wave, "前" if side == "before" else "后"], points[key]))
	if points.has("peak"):
		lines.append(_snapshot_line("采样峰值", points.peak))
	if points.has("last"):
		lines.append(_snapshot_line("最后采样", points.last))
	return lines


static func _snapshot_line(label: String, row: Dictionary) -> String:
	var sum_name := "显存＋音频" if row.has("aud") else "显存"
	var line := "%s %s · %s %d MiB · 贴图 %d / 缓冲区 %d MiB" % [
		label, _mmss(row.t), sum_name, row.total, row.tex, row.buf]
	if row.has("aud"):
		line += " · 音频 %d MiB" % int(row.aud)
	if row.has("mw"):
		line += "（配乐 %d MiB）" % int(row.mw)
	if row.has("wasm"):
		line += " · WASM 容量 %d MiB" % int(row.wasm)
	return line


static func _dev_short() -> String:
	if _web():
		var r = JavaScriptBridge.eval("(function(){var u=navigator.userAgent,m=u.match(/OS (\\d+[_\\d]*)/);return (/iPhone|iPad/.test(u)?'iOS '+(m?m[1].replace(/_/g,'.'):''):(/Android/.test(u)?'Android':'桌面'))+' '+screen.width+'x'+screen.height+'@'+(window.devicePixelRatio||1)+(/BiliApp|bili/i.test(u)?' B站':'')})()", true)
		return str(r) if r != null else ""
	return "%s %s" % [OS.get_name(), OS.get_model_name()]


## 事件标签（perf_report.tag 转过来：Boss 登场 / 读帧条 / 护栏…）：记进当前这一段
static func tag(name: String) -> void:
	if on:
		_tags[name] = int(_tags.get(name, 0)) + 1
		if name == "读帧条":
			event(name, true)
		elif name.begins_with("护栏") or name == "掉帧档" or name == "恢复" or name == "清字形":
			event(name)


## 每帧（game._process）：只累计时间；每秒取一次内存看尖峰，每 EVERY 秒写一条
static func tick(g, delta: float) -> void:
	if not on or cur.is_empty() or g.get_instance_id() != _owner:
		return
	if cur.squad == "" and g.squad != null:
		cur.squad = ",".join(PackedStringArray(g.squad.ids()))
	var rd := delta / maxf(0.01, Engine.time_scale)   # 按真实时间（快进 / 慢动作不改间隔）
	if _rt == 0.0:
		phase("局内")
	_rt += rd
	_t += rd
	_mem_t += rd
	_last_write += rd
	if _hf_on:
		_hf_tick(g, rd)
	if _t >= (minf(_every, 5.0) if g.spawner != null and g.spawner.mobs_stopped() else _every):   # 最终阶段每 5 秒一条（看得到被杀页前最后几秒）
		if _web():   # 心跳：先写一条小记录，再采样（采样中途脚本出错时心跳还在，看得出是哪一步断的）
			JavaScriptBridge.eval("try{localStorage.setItem('sy_bb_hb','%d / %d')}catch(e){}" % [int(_rt), int(g.t)], true)
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
	_refresh_context(g)
	_t = 0.0
	_last_write = 0.0
	var A = load("res://scripts/art.gd")
	var tex: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buf: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	var vid: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var aud: float = Sfx.sample_mem_mb() if _web() else 0.0
	var wasm := 0.0
	var js := 0.0
	var pck := 0.0
	var mw := 0.0
	var music_measured := false
	if _web():
		# g：堆增长记录（[页面秒, 原 MB, 请求 MB, 阶段]）；m：浏览器解码配乐状态；p：主包在 MEMFS 的字节（JS 堆估算，WebKit 没有 performance.memory）
		var r = JavaScriptBridge.eval("(function(){var w=window.__syWasm,r={w:w&&w.buffer?w.buffer.byteLength:0,g:window.__syWasmGrows||[],p:window.__syPckBytes||0};if(performance.memory){r.j=performance.memory.usedJSHeapSize}if(window.__syMusOn&&window.__syMus){try{r.m=JSON.parse(window.__syMus.state())}catch(e){}}return JSON.stringify(r)})()", true)
		var d = JSON.parse_string(str(r)) if r != null else null
		if d is Dictionary:
			wasm = float(d.get("w", 0)) / 1048576.0
			js = float(d.get("j", 0)) / 1048576.0
			var gl: Array = d.get("g", []) if d.get("g", []) is Array else []
			if gl.size() > _wg:
				_wg = gl.size()
				_tags["WASM 堆增长"] = 1   # 这一段里堆又涨过（engine_patch.py §3）
			cur.wg = gl.slice(-30)
			pck = float(d.get("p", 0)) / 1048576.0
			var m = d.get("m", null)
			if m is Dictionary:
				music_measured = m.has("mb")
				mw = float(m.get("mb", 0))
				cur.sr = int(m.get("sr", 0))
				cur.mdl = float(m.get("dl", 0))
				if int(m.get("fails", 0)) > 0:
					cur.mus = "web·解码失败 %d（%s）" % [int(m.fails), str(m.get("lf", ""))]
	else:
		wasm = OS.get_static_memory_usage() / 1048576.0   # 桌面：引擎静态内存放在同一列
	_last_mb = vid + aud
	var nfx: int = g.fx.size() + (g.ult.shapes.size() if g.ult != null else 0)
	var ln: int = int(A.load_n)
	if g.squad != null:
		cur.squad = ",".join(PackedStringArray(g.squad.ids()))   # 每条都更新：中途入队的干员也记上
	var s := {"t": int(g.t), "rt": int(_rt), "tex": int(tex), "buf": int(buf), "vid": int(vid), "aud": int(aud), "mw": int(mw), "wasm": int(wasm), "js": int(js), "pk": int(pck),
		"node": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "obj": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"e": g.enemies.size(), "fx": nfx, "b": g.bullets.size() + g.ebullets.size(), "lv": int(g.level),
		"tc": A._cache.size(), "ld": ln - _load0, "rl": ",".join(A.recent_loads.slice(-6)), "tag": ",".join(PackedStringArray(_tags.keys())), "q": Cfg.quality}
	var point := {"t": s.t, "tex": s.tex, "buf": s.buf, "total": int(_last_mb)}
	if _web():
		point["aud"] = s.aud
	if music_measured:
		point["mw"] = s.mw
	if _web() and wasm > 0:
		point["wasm"] = s.wasm
	_keep_snapshot(cur.memory_snapshots, point, _wave, _last_mb > _peak_mb)
	_peak_mb = maxf(_peak_mb, _last_mb)
	_load0 = ln
	_tags = {}
	if Cfg.dev_args().has("--crashbox"):
		print("PF CRASHBOX sample t=%d tex=%d buf=%d e=%d ld=%d tag=%s" % [s.t, s.tex, s.buf, s.e, s.ld, s.tag])
		if cur.s.size() == 2:   # 还没 append：这是第 3 条
			print("PF CRASHBOX report\n" + report_text(cur))   # 测试：第 3 条时把整份文本打出来，对照真机快照格式
	var a: Array = cur.s
	a.append(s)
	if a.size() > MAX_S:
		a.remove_at(4)   # 留开头 4 条（开局基线），丢中间最早的
	_write()
	if Cfg.dev_args().has("--crashbox") and _web():   # 测试：写完从本地存储读回，确认真的写进去了（11-09 真机快照 0:41 后不再更新）
		print("PF CRASHBOX stored rows=%s len=%s" % [str(JavaScriptBridge.eval("(function(){try{var o=JSON.parse(localStorage.getItem('sy_bb')||'{}');return (o.s||[]).length+'/'+(o.end||'-')}catch(e){return 'ERR '+e.message}})()", true)), str(JavaScriptBridge.eval("(localStorage.getItem('sy_bb')||'').length", true))])


static func _hf_tick(g, rd: float) -> void:
	var A = load("res://scripts/art.gd")
	_hf_cd = maxf(0.0, _hf_cd - rd)
	_up_sec_t += rd
	if _up_sec_t >= 1.0:   # 每秒上传：art.up_bytes 这一秒的增量，记整局峰值
		var ub: int = int(A.up_bytes)
		var d: int = ub - _up_sec_b if _up_sec_b >= 0 else 0
		_up_sec_b = ub
		_up_sec_t = 0.0
		if d > int(up_peak.get("b", 0)):
			up_peak = {"b": d, "t": int(g.t)}
	# 换曲 / 最终 Boss 二阶段
	var mk: String = Sfx.cur_track + ("·二阶段" if Sfx.final_p2 and Sfx.cur_track.begins_with("final") else "")
	if mk != _mus_last:
		if _mus_last != "":
			event("配乐 → " + (mk if mk != "" else "（淡出）"))
		_mus_last = mk
	if not A.big_ev.is_empty():
		for be in A.big_ev:
			event("%s %s %d×%d %.1f MiB" % ["读入" if be[4] else "释放", str(be[0]).get_file(), int(be[1]), int(be[2]), float(be[3]) / 1048576.0])
		A.big_ev.clear()
	_hf_t += rd
	if _hf_t >= HF_EVERY or (_hf_after > 0.0 and _rt >= _hf_after):
		if _hf_after > 0.0 and _rt >= _hf_after:
			_hf_after = -1.0
		_hf_sample(g)


## 高频一行：[实时秒, 局内秒, 贴图, 缓冲, 音频, 配乐, WASM, JS, 怪, 特效, 弹, 这一段上传 KiB, 驻留配乐首数, 配乐名, GL 编号计数器, GL 五张表总槽数]
## （GL 两列：engine_patch §9 之前计数器一局涨到两百多万、表槽同步撑大 JS 堆；回收后应基本不涨），写 sy_bb_hf（连同事件日志与上传峰值）
static func _hf_sample(g) -> void:
	_hf_t = 0.0
	var A = load("res://scripts/art.gd")
	var wasm := 0
	var js := 0
	var mw := 0
	var mn := ""
	var r = JavaScriptBridge.eval("(function(){var w=window.__syWasm,r={w:w&&w.buffer?w.buffer.byteLength:0};if(performance.memory){r.j=performance.memory.usedJSHeapSize}if(window.__syMusOn&&window.__syMus){try{var m=JSON.parse(window.__syMus.state());r.m=m.mb;r.n=m.nm}catch(e){}}if(window.__syGLN){r.gl=window.__syGLN()}return JSON.stringify(r)})()", true)
	var d = JSON.parse_string(str(r)) if r != null else null
	var gl := [0, 0]
	if d is Dictionary:
		if d.get("gl", null) is Array and (d.gl as Array).size() >= 2:
			gl = [int(d.gl[0]), int(d.gl[1])]
		wasm = int(float(d.get("w", 0)) / 1048576.0)
		js = int(float(d.get("j", 0)) / 1048576.0)
		mw = int(float(d.get("m", 0)))
		mn = str(d.get("n", ""))
	var ub: int = int(A.up_bytes)
	var row := [int(_rt), int(g.t), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0), int(Sfx.sample_mem_mb()), mw, wasm, js,
		g.enemies.size(), g.fx.size() + (g.ult.shapes.size() if g.ult != null else 0), g.bullets.size() + g.ebullets.size(),
		int((ub - _up_last) / 1024), (mn.count("+") + 1) if mn != "" else 0, mn, gl[0], gl[1]]
	_up_last = ub
	_hf.append(row)
	if _hf.size() > HF_MAX:
		_hf.pop_front()
	var j := JSON.stringify({"hf": _hf, "ev": _evl, "up": up_peak, "um": A.up_max, "uo": A.up_owner})
	JavaScriptBridge.eval("try{localStorage.setItem('%s',%s)}catch(e){}" % [HF_KEY, JSON.stringify(j)], true)
	if Cfg.dev_args().has("--crashbox"):
		print("PF CRASHHF " + JSON.stringify(row))


## 正常结算报告也带的上传读数（perf_report.finish）
static func up_summary() -> Dictionary:
	var A = load("res://scripts/art.gd")
	return {"up_peak": up_peak.duplicate(), "up_max": (A.up_max as Dictionary).duplicate(), "up_max_page": _page_um.duplicate(), "up_owner": (A.up_owner as Dictionary).duplicate(), "open": _opened.duplicate()}


static func up_lines(r: Dictionary) -> PackedStringArray:
	var o := PackedStringArray()
	var pk: Dictionary = r.get("up_peak", {})
	var mx: Dictionary = r.get("up_max", {})
	if not pk.is_empty() or not mx.is_empty():
		o.append("贴图上传：每秒峰值 %.1f MiB（局内 %s）· 本局最大单张 %s %d×%d（%.1f MiB）" % [float(pk.get("b", 0)) / 1048576.0, _mmss(float(pk.get("t", 0))),
			str(mx.get("n", "—")).get_file(), int(mx.get("w", 0)), int(mx.get("h", 0)), float(mx.get("b", 0)) / 1048576.0])
	var pm: Dictionary = r.get("up_max_page", {})
	if not pm.is_empty():
		o.append("进局前（标题 / 图鉴 / 寻访 / 载入页）最大单张 %s %d×%d（%.1f MiB；进局时局外读的图已放掉）" % [str(pm.get("n", "—")).get_file(), int(pm.get("w", 0)), int(pm.get("h", 0)), float(pm.get("b", 0)) / 1048576.0])
	var uo: Dictionary = r.get("up_owner", {})
	if not uo.is_empty():
		var ks: Array = uo.keys()
		ks.sort_custom(func(x, y): return int(uo[x]) > int(uo[y]))
		var parts := PackedStringArray()
		for k in ks:
			parts.append("%s %.1f" % [str(k), float(uo[k]) / 1048576.0])
		o.append("本局干员特效读入（MiB，核对是否都在编队 / 招募内）：" + "、".join(parts))
	var op: Dictionary = r.get("open", {})
	if not op.is_empty():
		var ps := PackedStringArray()
		for k in op:
			ps.append("%s %d 次" % [str(k), int(op[k])])
		o.append("本页开局前打开过：" + "、".join(ps))
	return o


## 正常离局（局终 / 回标题 / 重开）：记 end
static func end(why: String) -> void:
	if not on or cur.is_empty() or cur.end != "":
		return
	if _context_dirty and is_instance_id_valid(_owner):
		_refresh_context(instance_from_id(_owner))
	cur.end = why
	on = false
	_write()


static func _write(fresh := false) -> void:
	var j := JSON.stringify(cur)
	if _web():   # ev 由 JS 侧追加：写引擎这份时把已存的 ev 并进来（新开一份时不并上一份的）
		var src := "null" if fresh else "localStorage.getItem('%s')" % KEY
		# 写不进时把原因记进 sy_bb_err（11-09 真机：快照 0:41 后一行没写、局终 end 也没写进去；仿真复现不了，先把真机上的原因留下来，report_text 附上）
		JavaScriptBridge.eval("(function(){var s=%s;try{var o=JSON.parse(s),p=%s;if(p){try{o.ev=JSON.parse(p).ev||[]}catch(e){}}localStorage.setItem('%s',JSON.stringify(o))}catch(e){try{localStorage.setItem('sy_bb_err',JSON.stringify({t:new Date().toTimeString().slice(0,8),m:String(e&&e.name||'')+' '+String(e&&e.message||e).slice(0,100),n:s.length,used:JSON.stringify(localStorage).length}))}catch(e2){}}})()" % [JSON.stringify(j), src, KEY], true)
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
		var r = JavaScriptBridge.eval("""(function(){var S=localStorage,s=S.getItem('sy_bb');try{if(s){var o=JSON.parse(s);if(!o.end){var h=S.getItem('sy_bb_hf');if(h){try{o.hfx=JSON.parse(h)}catch(e){}}s=JSON.stringify(o);S.setItem('sy_bb_prev',s);S.removeItem('sy_bb')}}S.removeItem('sy_bb_hf')}catch(e){}
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
		print("PF CRASHBOX prev=%d\n%s" % [int(not prev.is_empty()), report_text(prev)])
	return prev


## 局间整页重载没完成（core/run_reload.gd 兜底）：把刚结束这一局的记录挂上原因，当作「上次」那份写下，标题页照常提示、能复制
static func note_reload_fail(why: String) -> void:
	var d: Dictionary = cur.duplicate(true) if not cur.is_empty() else {"start": Time.get_datetime_string_from_system(false, true), "s": [], "ev": []}
	d["rlfail"] = why
	d.erase("seen")
	prev = d
	_checked = true
	var j := JSON.stringify(d)
	if _web():
		JavaScriptBridge.eval("try{localStorage.setItem('%s',%s)}catch(e){}" % [PREV, JSON.stringify(j)], true)
	else:
		var f := FileAccess.open(PREV_FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(j)


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
	if p.has("rlfail"):
		return "上次局间重载没完成，已改走普通回标题（%s）· 点此查看 / 复制" % str(p.rlfail)
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
	if p.has("rlfail"):
		o.append("【局间重载失败】%s（docs/319 §17：盖上底色后页面没有被替换，已撤掉底色改走普通回标题）" % str(p.rlfail))
	o.append("【上次异常退出前的内存曲线】%s 开局  版本 %s（%s）  %s  编队 %s  画质 %s  配乐 %s%s" % [str(p.get("start", "")), str(p.get("ver", "")), str(p.get("commit", "")),
		str(p.get("dev", "")), str(p.get("squad", "")), str(p.get("q", "")), str(p.get("mus", "?")),
		("（%d Hz，已下 %.1f MB）" % [int(p.get("sr", 0)), float(p.get("mdl", 0))]) if int(p.get("sr", 0)) > 0 else ""])
	# JS 一栏：有 performance.memory（Chromium）就是实测；没有（iOS / WebKit）就是估算 ≈ 主包在 MEMFS 的字节 + 浏览器解码的配乐缓冲 + 引擎音频样本，带「~」
	o.append("局内 实时 | 贴图 缓冲 显存 音频(配乐) WASM JS | 节点 对象 怪 特效 弹 等级 | 缓存张 新读 | 事件")
	for s in p.get("s", []):
		var js_s := str(int(s.get("js", 0)))
		if int(s.get("js", 0)) == 0 and s.has("pk"):
			js_s = "~%d" % (int(s.get("pk", 0)) + int(s.get("aud", 0)))
		o.append("%s %s | %d %d %d %d(%d) %d %s | %d %d %d %d %d %d | %d %d | %s" % [_mmss(float(s.get("t", 0))), _mmss(float(s.get("rt", 0))), int(s.get("tex", 0)), int(s.get("buf", 0)), int(s.get("vid", 0)),
			int(s.get("aud", 0)), int(s.get("mw", 0)), int(s.get("wasm", 0)), js_s, int(s.get("node", 0)), int(s.get("obj", 0)), int(s.get("e", 0)), int(s.get("fx", 0)),
			int(s.get("b", 0)), int(s.get("lv", 0)), int(s.get("tc", 0)), int(s.get("ld", 0)), str(s.get("tag", ""))])
	var samples := snapshot_lines(p)
	if not samples.is_empty():
		o.append_array(samples)
	o.append_array(load("res://scripts/core/perf_context.gd").lines(p.get("context", {})))
	if not p.get("run_id", {}).is_empty():
		o.append_array(load("res://scripts/core/run_reload.gd").journey_lines(p.run_id, p.get("journey", {})))
	var wg: Array = p.get("wg", [])
	if not wg.is_empty():
		var ws := PackedStringArray()
		for w in wg:
			if w is Array and w.size() >= 3:
				# 引擎实际给到 max(请求, 原 × 1.2)（emscripten 的超额增长），记录里只有请求；这里写实得
				ws.append("%ds %d→%d%s" % [int(w[0]), int(w[1]), maxi(int(w[2]), int(float(w[1]) * 1.2)), (" " + str(w[3])) if w.size() > 3 and str(w[3]) != "" else " 开机"])
		o.append("WASM 堆增长（页面秒 原→实得 MB 阶段）：" + "；".join(ws))
	var a: Array = p.get("s", [])
	if not a.is_empty():
		o.append("最后一段新读的贴图：" + str(a[-1].get("rl", "")))
	if _web():
		var er = JavaScriptBridge.eval("localStorage.getItem('sy_bb_err')||''", true)
		if er != null and str(er) != "":
			o.append("快照写入失败（最近一次）：" + str(er))
		var hb = JavaScriptBridge.eval("localStorage.getItem('sy_bb_hb')||''", true)
		if hb != null and str(hb) != "":
			o.append("最后一次心跳（实时秒 / 局内秒）：" + str(hb))
	var ev: Array = p.get("ev", [])
	if not ev.is_empty():
		var es := PackedStringArray()
		for e in ev:
			if e is Array and e.size() >= 3:
				es.append("%s %s" % [str(e[2]), str(e[1])])
		o.append("页面事件：" + "；".join(es))
	o.append_array(_hf_lines(p))
	return "\n".join(o)


## 闪退报告下半屏（docs/332 §4）：开局信息、上传、最后 60 秒高频曲线、最后 20 条事件
static func _hf_lines(p: Dictionary) -> PackedStringArray:
	var o := PackedStringArray()
	var op: Dictionary = p.get("open", {})
	if p.has("wasm0") or not op.is_empty():
		var parts := PackedStringArray()
		for k in op:
			parts.append("%s %d 次" % [str(k), int(op[k])])
		o.append("【开局信息】进局时 WASM %d MiB · 本页开局前打开过：%s" % [int(p.get("wasm0", 0)), "、".join(parts) if not parts.is_empty() else "无"])
	var h: Dictionary = p.get("hfx", {})
	if h.is_empty():
		return o
	o.append_array(up_lines({"up_peak": h.get("up", {}), "up_max": h.get("um", {}), "up_max_page": p.get("um_page", {}), "up_owner": h.get("uo", {})}))
	var rows: Array = h.get("hf", [])
	if not rows.is_empty():
		o.append("【闪退前高频曲线】每 %d 秒一行 + 尖峰补采，最后 %d 行" % [int(HF_EVERY), rows.size()])
		o.append("实时 局内 | 贴图 缓冲 音频(配乐) WASM JS | 怪 特效 弹 | 上传KiB | 驻留配乐首数 名 | GL 编号 表槽（万）")
		for r in rows:
			if r is Array and r.size() >= 14:
				o.append("%s %s | %d %d %d(%d) %d %d | %d %d %d | %d | %d %s | %s" % [_mmss(float(r[0])), _mmss(float(r[1])), int(r[2]), int(r[3]), int(r[4]), int(r[5]), int(r[6]), int(r[7]),
					int(r[8]), int(r[9]), int(r[10]), int(r[11]), int(r[12]), str(r[13]),
					("%.1f %.1f" % [float(r[14]) / 10000.0, float(r[15]) / 10000.0]) if r.size() >= 16 else "—"])
	var ev: Array = h.get("ev", [])
	if not ev.is_empty():
		o.append("【事件日志】最后 %d 条（实时 / 局内）" % mini(20, ev.size()))
		for e in ev.slice(-20):
			if e is Array and e.size() >= 3:
				o.append("%s / %s %s" % [_mmss(float(e[0])), _mmss(float(e[1])), str(e[2])])
	return o


## 打开查看面板：网页 DOM（复制 / 保存文件 / 关闭，按钮本身是用户手势，iOS 剪贴板才放行）；桌面进剪贴板。on_close 在点「关闭」后调
static func open_panel(t: String) -> void:
	if _web():
		load("res://scripts/core/perf_hud.gd").dom_panel(t, "sy-crash-log")
		return
	DisplayServer.clipboard_set(t)
