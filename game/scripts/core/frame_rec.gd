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
var _acc := {}               # 分项计时（FR.tic / toc）：名字 -> 本段累计微秒
var _proc_ms := 0.0          # 上一帧全部 _process 的耗时（含场景切换后的 _ready 不算在内）


var _memlog := false
var _mem5 := false
var _mem_tick := -1

## --memlog（docs/50 §30）：引擎堆 / 贴图显存 / 显存合计（Godot 自己的统计），加网页音频样本解码后的估算（Web Audio 缓冲在 JS 里，引擎看不到）
func _print_mem(tag: String) -> void:
	print("PF MEM %s heap=%.1fMB tex=%.1fMB buf=%.1fMB vid=%.1fMB audio=%.1fMB win=%s scaled=%s q=%s" % [tag,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Sfx.sample_mem_mb(), get_tree().root.size, Cfg.render_scaled, Cfg.quality])
	if OS.has_feature("web"):
		print("PF MEMAUD %s %s" % [tag, Sfx.sample_report()])
		print("PF WEBMUSIC %s %s" % [tag, str(JavaScriptBridge.eval("window.__syMus?window.__syMus.state():'none'", true))])   # 出包配乐（docs/319 §12）
		var r = JavaScriptBridge.eval("(function(){var w=window.__syWasm,r={w:w&&w.buffer?w.buffer.byteLength:0};if(performance.memory){r.j=performance.memory.usedJSHeapSize}return JSON.stringify(r)})()", true)
		var d = JSON.parse_string(str(r)) if r != null else null
		if d is Dictionary:
			print("PF MEMJS %s wasm=%.0fMB js=%.0fMB" % [tag, float(d.get("w", 0)) / 1048576.0, float(d.get("j", 0)) / 1048576.0])
		# WASM 摸过的页（真正驻留）与堆增长记录（tools/web/perf_probe.js、engine_patch.py §3；docs/319 §10）
		var tw = JavaScriptBridge.eval("window.__syWasmTouched?window.__syWasmTouched():-1", true)
		var gr = JavaScriptBridge.eval("JSON.stringify((window.__syWasmGrows||[]).splice(0))", true)
		var rg = JavaScriptBridge.eval("JSON.stringify((window.__syAudioRegs||[]).filter(function(x){return x[1]>=10}).splice(0))", true)
		JavaScriptBridge.eval("window.__syAudioRegs=[]", true)
		print("PF WASMTOUCH %s touched=%.0fMB grows=%s longregs=%s" % [tag, float(tw) if tw != null else -1.0, str(gr), str(rg)])   # WASM 容量（只涨不缩）与 JS 堆：引擎显存统计看不到的那部分（docs/319 §7）   # 网页样本按来源分组（docs/287 §3 ③）
	var sc = get_tree().current_scene
	if sc != null and sc.has_method("view_size") and "cam" in sc and sc.cam != null:
		var vp := get_viewport()
		# 镜头：可见世界高（世界像素，2 世界像素 = 1 美术像素）、zoom、1 美术像素占几个物理像素（手机三档统一镜头用，docs/50 §32）
		print("PF VIEW %s view_h=%.0f zoom=%.3f art_px=%.2f phys_h=%.0f" % [tag, sc.view_size().y, sc.cam.zoom.x,
			2.0 * sc.cam.zoom.x * vp.get_final_transform().x.x, vp.get_visible_rect().size.y * vp.get_final_transform().x.x])
	if tag == "game+5s" or tag.begins_with("t="):
		_print_tex_breakdown()
		if (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--texdump"):
			_tex_dump(tag)
		if (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--texwalk"):
			_tex_walk(tag)


var _memnew_prev := {}
## 贴图缓存（art.gd A._cache）按前缀分组的估算（宽 × 高 × 4 字节）与最大的 12 张
## --texdump（测量用，docs/319 §18）：本时刻能找到的每张贴图一行 JSON（来源 / 名字 / 宽高 / MB），外加场景树里每个 SubViewport 的渲染目标；
## 和 RENDER_TEXTURE_MEM_USED 的差额是没登记在这些缓存里的（直接 load() 的图、引擎内部缓冲等）
func _tex_dump(tag: String) -> void:
	var A = load("res://scripts/art.gd")
	var rows: Array = []
	var seen := {}
	var add := func(src: String, name: String, t) -> void:
		if not (t is Texture2D):
			return
		var id: int = t.get_instance_id()
		if seen.has(id):
			return
		seen[id] = true
		rows.append([src, name, t.get_width(), t.get_height()])
	for n in A._cache:
		add.call("A", str(n), A._cache[n])
	for cname in ["_white_cache", "_mirror_cache"]:
		var cd: Dictionary = A.get(cname)
		for k in cd:
			add.call(cname, str(k), cd[k])
	var sc = get_tree().current_scene
	if sc != null and "tex" in sc and sc.tex is Dictionary:
		for n in sc.tex:
			add.call("g.tex", str(n), sc.tex[n])
		if "world" in sc and sc.world != null:
			for k in sc.world._ol_cache:
				add.call("outline", str(k), sc.world._ol_cache[k])
			if sc.world.atlas != null:
				add.call("atlas", "atlas_white", sc.world.atlas.tex_white)
		if "map" in sc and sc.map != null:
			for k in sc.map.ground_cache:
				add.call("ground", str(k), sc.map.ground_cache[k][0])
		for mname in ["ult_px_sd"]:
			if sc.has_meta(mname):
				var m = sc.get_meta(mname)
				if m != null and "_cache" in m:
					for k in m._cache:
						add.call("ult", str(k), m._cache[k])
	var vps: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is SubViewport:
			var vp: SubViewport = nd
			vps.append([str(nd.get_path()).substr(0, 80), vp.size.x, vp.size.y, int(vp.use_hdr_2d), int(vp.render_target_update_mode)])
		for c in nd.get_children():
			stack.append(c)
	var tot: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	var buf: float = Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0
	var rv: Vector2 = get_viewport().get_visible_rect().size
	print("PF TEXDUMP " + JSON.stringify({"tag": tag, "tex": tot, "buf": buf, "root": [rv.x, rv.y], "win": DisplayServer.window_get_size(), "rows": rows, "vps": vps}))


## --texwalk（测量用，docs/319 §23）：从场景树每个节点出发，沿脚本变量（字典 / 数组 / 对象，最多 6 层）找所有还被引用的贴图，
## 按「最先找到它的顶层模块」归类（同一张只算一次），另外单列 Art 静态缓存与节点自带贴图（TextureRect / Sprite 等）。
## 打 PF TEXWALK 一行 JSON：各模块 MB / 张数 + 前 40 张最大的（路径、尺寸）；和引擎贴图总量的差就是找不到引用的（引擎内部 / 字体等）
var _tw_seen := {}
var _tw_mod := {}
var _tw_top: Array = []

func _tw_add(t: Texture2D, mod: String, path: String) -> void:
	var id := t.get_instance_id()
	if _tw_seen.has(id):
		return
	_tw_seen[id] = true
	var mb: float = t.get_width() * t.get_height() * 4.0 / 1048576.0
	var m: Array = _tw_mod.get(mod, [0.0, 0])
	m[0] += mb
	m[1] += 1
	_tw_mod[mod] = m
	_tw_top.append([mb, path.substr(0, 90), t.get_width(), t.get_height()])


func _tw_val(v, mod: String, path: String, depth: int, budget: Array) -> void:
	if budget[0] <= 0:
		return
	budget[0] -= 1
	if v is Texture2D:
		_tw_add(v, mod, path)
	elif v is Dictionary:
		if depth <= 0:
			return
		for k in v:
			_tw_val(v[k], mod, path + "[" + str(k).substr(0, 40) + "]", depth - 1, budget)
	elif v is Array:
		if depth <= 0:
			return
		var i := 0
		for x in v:
			_tw_val(x, mod, path + "[" + str(i) + "]", depth - 1, budget)
			i += 1
			if i > 4000:
				break
	elif v is Object and is_instance_valid(v) and not (v is Node):
		if depth <= 0 or _tw_seen.has(v.get_instance_id()):
			return
		_tw_seen[v.get_instance_id()] = true
		_tw_obj(v, mod, path, depth - 1, budget)


func _tw_obj(o: Object, mod: String, path: String, depth: int, budget: Array) -> void:
	for p in o.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var v = o.get(p.name)
		if v == null or v is Node:
			continue
		var sub: String = mod if mod != "" else str(p.name)
		_tw_val(v, sub, path + "." + str(p.name), depth, budget)


func _tex_walk(tag: String) -> void:
	_tw_seen = {}
	_tw_mod = {}
	_tw_top = []
	var budget := [3000000]
	var A = load("res://scripts/art.gd")
	for n in A._cache:
		if A._cache[n] is Texture2D:
			_tw_add(A._cache[n], "Art 缓存", "A._cache[" + str(n) + "]")
	for cname in ["_white_cache", "_mirror_cache"]:
		var cd: Dictionary = A.get(cname)
		for k in cd:
			if cd[k] is Texture2D:
				_tw_add(cd[k], "Art " + cname, "A." + cname)
	var sc = get_tree().current_scene
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for pn in ["texture", "texture_normal", "icon"]:
			var tv = nd.get(pn) if pn in nd else null
			if tv is Texture2D:
				_tw_add(tv, "节点自带", str(nd.get_path()).substr(0, 70))
		if nd.get_script() != null:
			var base: String = "g" if nd == sc else str(nd.name)
			if nd == sc:
				_tw_obj(nd, "", "g", 6, budget)   # 对局：每个顶层变量算一个模块
			else:
				_tw_obj(nd, base, base, 6, budget)
		for c in nd.get_children():
			stack.append(c)
	var tot := 0.0
	var mods := {}
	for k in _tw_mod:
		tot += float(_tw_mod[k][0])
		mods[k] = [snappedf(_tw_mod[k][0], 0.1), _tw_mod[k][1]]
	_tw_top.sort_custom(func(a, b): return a[0] > b[0])
	var top: Array = []
	for r in _tw_top.slice(0, 40):
		top.append([snappedf(r[0], 0.01), r[1], r[2], r[3]])
	var eng: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	# 资源缓存：所有从文件读进来、现在还活着的图（不管谁拿着），按目录归类（docs/319 §23）
	var files := {}
	var ftop: Array = []
	var fsum := 0.0
	var dirs: Array = ["res://art", "res://fonts", "res://ui", "res://textures", "res://assets"]
	var guard := 0
	while not dirs.is_empty() and guard < 20000:
		guard += 1
		var d: String = dirs.pop_back()
		if not DirAccess.dir_exists_absolute(d):
			continue
		for f in ResourceLoader.list_directory(d):
			var p: String = d + "/" + str(f)
			if str(f).ends_with("/"):
				dirs.append(p.trim_suffix("/"))
				continue
			if not (p.ends_with(".png") or p.ends_with(".webp") or p.ends_with(".jpg")):
				continue
			if not ResourceLoader.has_cached(p):
				continue
			var r = ResourceLoader.get_cached_ref(p)
			if not (r is Texture2D):
				continue
			var mb2: float = r.get_width() * r.get_height() * 4.0 / 1048576.0
			fsum += mb2
			var parts: PackedStringArray = p.trim_prefix("res://").split("/")
			var key: String = "/".join(parts.slice(0, mini(3, parts.size() - 1)))
			var fv: Array = files.get(key, [0.0, 0])
			fv[0] += mb2
			fv[1] += 1
			files[key] = fv
			ftop.append([snappedf(mb2, 0.01), p.trim_prefix("res://art/"), r.get_width(), r.get_height()])
	ftop.sort_custom(func(a, b): return a[0] > b[0])
	var fout := {}
	for k in files:
		fout[k] = [snappedf(files[k][0], 0.1), files[k][1]]
	print("PF TEXFILES " + JSON.stringify({"tag": tag, "engine_tex": snappedf(eng, 0.1), "files_mb": snappedf(fsum, 0.1), "dirs": fout, "top": ftop.slice(0, 40)}))
	print("PF TEXWALK " + JSON.stringify({"tag": tag, "t": sc.t if sc != null and "t" in sc else 0, "engine_tex": snappedf(eng, 0.1), "found": snappedf(tot, 0.1), "budget_left": budget[0], "mods": mods, "top": top}))


func _print_tex_breakdown() -> void:
	var A = load("res://scripts/art.gd")
	var groups := {}
	var tops: Array = []
	for n in A._cache:
		var t = A._cache[n]
		if not (t is Texture2D):
			continue
		var mb: float = t.get_width() * t.get_height() * 4.0 / 1048576.0
		var pre: String = str(n).split("_")[0]
		groups[pre] = groups.get(pre, 0.0) + mb
		tops.append([mb, str(n), "%dx%d" % [t.get_width(), t.get_height()]])
	for cname in ["_hires", "_white_cache", "_mirror_cache"]:
		var cd: Dictionary = A.get(cname)
		var sum := 0.0
		for k in cd:
			var t2 = cd[k]
			if t2 is Texture2D:
				sum += t2.get_width() * t2.get_height() * 4.0 / 1048576.0
		groups[cname] = sum
	var sc = get_tree().current_scene
	if sc != null and "tex" in sc and sc.tex is Dictionary:
		var seen := {}
		var tot := 0.0
		var in_a := {}
		for n in A._cache:
			if A._cache[n] is Texture2D:
				in_a[A._cache[n].get_instance_id()] = true
		var extra := 0.0
		for n in sc.tex:
			var t3 = sc.tex[n]
			if t3 is Texture2D and not seen.has(t3.get_instance_id()):
				seen[t3.get_instance_id()] = true
				var mb3: float = t3.get_width() * t3.get_height() * 4.0 / 1048576.0
				tot += mb3
				if not in_a.has(t3.get_instance_id()):
					extra += mb3
		groups["g.tex"] = tot
		groups["g.tex_not_in_A"] = extra
		if "world" in sc and sc.world != null:
			var ol := 0.0
			for k in sc.world._ol_cache:
				var t4 = sc.world._ol_cache[k]
				if t4 is Texture2D:
					ol += t4.get_width() * t4.get_height() * 4.0 / 1048576.0
			groups["outline"] = ol
			if sc.world.atlas != null:
				var at := 0.0
				for t5 in [sc.world.atlas.tex_white]:
					if t5 is Texture2D:
						at += t5.get_width() * t5.get_height() * 4.0 / 1048576.0
				groups["atlas_white"] = at
		if "map" in sc and sc.map != null:
			var gm := 0.0
			for k in sc.map.ground_cache:
				var t6 = sc.map.ground_cache[k][0]
				if t6 is Texture2D:
					gm += t6.get_width() * t6.get_height() * 4.0 / 1048576.0
			groups["ground"] = gm
	var fmb := 0.0
	var fpages := 0
	var fsizes := 0
	for fp in ["res://fonts/ui.ttf", "res://fonts/ui_fallback.otf", "res://fonts/serif.ttf"]:
		var ff = load(fp)
		if not (ff is FontFile):
			continue
		for ci in ff.get_cache_count():
			for sz in ff.get_size_cache_list(ci):
				fsizes += 1
				for ti in ff.get_texture_count(ci, sz):
					var fimg: Image = ff.get_texture_image(ci, sz, ti)
					if fimg != null:
						fpages += 1
						fmb += fimg.get_data_size() / 1048576.0
	groups["font_cache(%d sizes, %d pages)" % [fsizes, fpages]] = fmb
	var fl: Array = []
	var f0 = load("res://fonts/ui.ttf")
	if f0 is FontFile:
		for ci in f0.get_cache_count():
			for sz in f0.get_size_cache_list(ci):
				fl.append(sz)
	fl.sort()
	print("PF MEMFONT ui sizes: " + " ".join(fl.map(func(v): return "%d/%d" % [v.x, v.y])))
	tops.sort_custom(func(a, b): return a[0] > b[0])
	var gs: Array = groups.keys()
	gs.sort_custom(func(a, b): return groups[a] > groups[b])
	print("PF MEMHALF on=%s halved=%d kept2x=%d" % [A.half_enemy_on(), A.half_n, A.half_keep])
	print("PF MEMTEX groups " + "  ".join(gs.slice(0, 12).map(func(k): return "%s=%.0fMB" % [k, groups[k]])))
	print("PF MEMTEX top " + "  ".join(tops.slice(0, 12).map(func(x): return "%s(%s)=%.1f" % [x[1], x[2], x[0]])))
	# 局内增长定位（11-08，docs/319 §9）：贴图缓存去重合计、与上一行比新进缓存的贴图（按大小）
	var seen_a := {}
	var sum_a := 0.0
	var now_keys := {}
	for n in A._cache:
		var ta = A._cache[n]
		if ta is Texture2D:
			now_keys[n] = ta.get_width() * ta.get_height() * 4.0 / 1048576.0
			if not seen_a.has(ta.get_instance_id()):
				seen_a[ta.get_instance_id()] = true
				sum_a += now_keys[n]
	var news: Array = []
	var new_mb := 0.0
	for n in now_keys:
		if not _memnew_prev.has(n):
			news.append([now_keys[n], str(n)])
			new_mb += now_keys[n]
	news.sort_custom(func(x, y): return x[0] > y[0])
	print("PF MEMSUM A=%.1fMB n=%d  new=%d (%.1fMB): %s" % [sum_a, now_keys.size(), news.size(), new_mb, "  ".join(news.slice(0, 24).map(func(x): return "%s=%.1f" % [x[1], x[0]]))])
	_memnew_prev = now_keys


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


## 段内分项计时：t0 = FR.tic()，做完 FR.toc("名字", t0)；段结束时打印 PF FTACC（每帧平均毫秒）。没挂上时 tic() 返回 0、toc 什么也不做
static func tic() -> int:
	return Time.get_ticks_usec() if _inst != null else 0


static func toc(name: String, t0: int) -> void:
	if _inst != null and t0 > 0:
		_inst._acc[name] = _inst._acc.get(name, 0) + Time.get_ticks_usec() - t0


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
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_memlog = (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--memlog")
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):   # 发布版不读命令行（check_release）；不依赖 Cfg 加载顺序，同 balance.gd 写法
		if a.begins_with("--ftquit="):
			var p := a.substr(9).split(":")
			_quit = [p[0], float(p[1]) if p.size() > 1 else 10.0]
		elif a.begins_with("--ftdo="):
			var p := a.substr(7).split(":")
			if p.size() >= 3:
				_dos.append([p[0], float(p[1]), p[2], false])
	if _segs.is_empty():
		_mark("start")   # 启动页没打标记（测试直接进标题页）时从这里算


func _mark(name: String) -> void:
	_close_seg()
	var now := Time.get_ticks_usec()
	_marks[name] = now
	_segs.append({"name": name, "t0": now, "dts": PackedFloat32Array()})
	print("PF FTMARK %s t=%.3f" % [name, now / 1e6])
	if _memlog:
		_print_mem(name)


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
	if _memlog and _marks.has("game") and not _mem5 and now - int(_marks["game"]) >= 5000000:
		_mem5 = true
		_print_mem("game+5s")
	if _memlog and _marks.has("game"):   # 内存曲线：对局时间每 30 秒一行（含分组），快进段也记（docs/50 §30.7）
		var sc = get_tree().current_scene
		if sc != null and "t" in sc:
			var gt := int(float(sc.t) / 30.0)
			if gt != _mem_tick:
				_mem_tick = gt
				_print_mem("t=%d" % (gt * 30))
	if not _quit.is_empty() and _marks.has(_quit[0]) and now - int(_marks[_quit[0]]) >= int(float(_quit[1]) * 1e6):
		_quit = []
		_close_seg()
		print("PF FTDONE")
		get_tree().quit()


## 每帧忙碌时间（docs/50 §33 发烫代理指标）：本帧第一个 _process 起到渲染提交完（frame_post_draw）——含脚本、_draw、渲染 CPU，
## 不含帧率上限 / 垂直同步的等待。段末打 PF FTBUSY：每秒忙多少毫秒（= 帧率 × 每帧忙碌），越低越省电
func _on_post_draw() -> void:
	if _proc_start > 0 and not _segs.is_empty():
		var s: Dictionary = _segs[-1]
		s["busy"] = float(s.get("busy", 0.0)) + (Time.get_ticks_usec() - _proc_start) / 1000.0
		s["bn"] = int(s.get("bn", 0)) + 1


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
	if not _acc.is_empty():
		var parts: Array = []
		for k in _acc:
			parts.append("%s=%.2f" % [k, _acc[k] / 1000.0 / n])
		print("PF FTACC %s %s" % [s.name, " ".join(parts)])
		_acc.clear()
	var wall: float = (Time.get_ticks_usec() - int(s.t0)) / 1e6
	if int(s.get("bn", 0)) > 0 and wall > 0.0:
		print("PF FTBUSY %s secs=%.1f fps=%.1f busy_per_frame=%.2fms busy_per_s=%.0fms" % [s.name, wall, int(s.bn) / wall, float(s.busy) / int(s.bn), float(s.busy) / wall])
	print("PF FTSEG %s n=%d mean=%.2f p50=%.2f p95=%.2f p99=%.2f max=%.1f over16=%d over33=%d" % [s.name, n, sum / n,
		d[int(n * 0.5)], d[mini(n - 1, int(n * 0.95))], d[mini(n - 1, int(n * 0.99))], d[n - 1], over, over2])
