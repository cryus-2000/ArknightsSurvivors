extends Control
## 启动页「声呐测绘」（用户 10-25 定：对照图方向 C 第一张；10-25 追加「启动中要有百分比，并说明在读什么」）。
## 主场景是 boot.tscn（本脚本），只依赖字体、标志与提示表，几十毫秒就能画出来；然后按 data/boot_order.json
## （tools/gen_boot_order.py 生成，叶子在前）逐个 load() 标题页带出的脚本与资源——每个只编译它自己，进度是真实的，
## 同时显示正在读哪一类（干员积木 / 海嗣 / 战场渲染 …）和文件名。桌面交给后台线程逐个编译，主线程照常出帧（大脚本以前一卡几秒）。
## 全部读完再读 main.tscn（此时都在缓存里），把标题页建在本页下面（本页挪进最上层盖层），离屏画一遍对局 / 图鉴的着色器（render/shader_warm.gd），
## 等连续 GOOD_N 帧稳在一帧预算内再淡出，标题开场从头播（10-25 用户「等能渲染到稳定 60 帧之后再正式进入游戏主界面」，docs/50 §27）。
## 以前这一段（桌面调试版 8–12 秒、网页十几秒）全在 Godot 静态启动图下面，没有进度。
## 桌面引擎初始化只显示同色背景，不再先放一张静态加载图。
## 网页：前面还有 HTML 加载页（tools/web/loader.js，下载占 0–60%、引擎启动 60–80%），这里接着它的百分比走、不倒退；
## 网页只保留 HTML 加载页；本页不另绘制，实际进度经 __syBootProgress 回传，主菜单就绪才 __syBootDone。
## 测试（带命令行参数、无界面）直接切标题页，不走本页；--bootshot / --loadprof / --bootrec 才走（--bootshot 在读到一半时截图退出）。
## 10-30 用户「更加有 PRTS 的感觉，但是保留点深海的特色」：balance ui/boot_v 1–3 是三个新方向的原型（画法在 boot_views.gd），0 = 本页原样。
##   三个方向的系统日志按真实加载状态排（启动引擎 → 每个编译类别 n / 总数 → 标题页 → 着色器 → 稳帧），不是预录的动画。
##   --bootrec=<目录>：逐帧存 rec_<帧>.png 直到标题页出现后 2 秒（录对照片）；--bootslow=<毫秒>：每读完一个文件多等这么久（只给录像拉长，调试参数）

const Tips = preload("res://scripts/screens/loading_tips.gd")
const Views = preload("res://scripts/screens/boot_views.gd")
const Bal = preload("res://scripts/core/balance.gd")
const FR = preload("res://scripts/core/frame_rec.gd")
const ORDER := "res://data/boot_order.json"
const MAIN := "res://main.tscn"
const BUDGET_USEC := 30000   # 每帧最多读多久（单个脚本超过也只读这一个）
const CYAN := Color(0.369, 0.902, 0.902)
const TEXT := Color(0.949, 0.957, 0.961)
const DIM := Color(0.5, 0.6, 0.65)
const OUT_LEN := 0.3
const WAIT_USEC := 4000      # 桌面后台编译时主线程每帧最多等多久（小脚本一帧能过一两个；留够画面的时间，稳 60）
const GOOD_N := 30           # 稳帧门：连续多少帧在预算内
const GATE_MIN := 0.4
const GATE_SLOW := 2.0
const GATE_MAX := 6.0
const GATE_MAX_WEB := 8.0

var font: Font
var tex_logo: Texture2D
var bg: GradientTexture2D
var items: Array = []         # [[路径, 类别], …]
var idx := 0
var cur_label := "启动引擎"
var cur_file := ""
var main_scene: PackedScene
var base := 0.0               # 网页从 HTML 加载页的 80% 接着走
var t := 0.0
var out_t := -1.0
var tip_i := 0
var tip_t := 0.0
var shot := false
var cur_path := ""
var _threads := false         # 桌面后台线程编译（网页导出没有线程）
var _req := ""                # 正在后台编译的路径
var _announced := -1
var _req_t := 0
var title: Node               # 建在本页下面的标题页
var _opened := false
var warm: Node                # 着色器预热视口
var _gate_t0 := 0
var _good := 0
var _good_slow := 0
var _last_us := 0
var _budget_ms := 16.7
var _web_overlay := false
var _web_last := ""
var _v := 0                   # ui/boot_v：0 = 现行，1–3 = boot_views 的三个方向
var views: Views
var lines: Array = []         # 方向 1–3 的系统日志：{"t", "s", "ok"}（_log_track 每帧重排）
var _cat_tot := {}            # 编译类别 → 文件数
var _seen_t := {}             # 日志行 → 第一次出现的时刻
var _slow_ms := 0


## 录对照片：挂在根节点上，启动页释放后接着录 2 秒标题页
class Rec extends Node:
	var dir := ""
	var f := 0
	var tail := -1
	func _process(_d: float) -> void:
		get_viewport().get_texture().get_image().save_png(dir + "/rec_%04d.png" % f)
		f += 1
		if tail < 0 and get_tree().root.get_node_or_null("BootDone") != null:
			tail = f + 60
		if (tail >= 0 and f >= tail) or f > 1800:
			get_tree().quit()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := Cfg.dev_args()
	shot = args.has("--bootshot")
	var rec_dir := ""
	for a in args:
		if a.begins_with("--bootrec="):
			rec_dir = a.substr(10)
		elif a.begins_with("--bootslow="):
			_slow_ms = int(a.substr(11))
	if DisplayServer.get_name() == "headless" or (not args.is_empty() and not shot and not args.has("--loadprof") and not args.has("--ftrec") and rec_dir == ""):
		if OS.has_feature("web"):
			_skip_web_boot.call_deferred(get_tree())
		else:
			get_tree().change_scene_to_file.call_deferred(MAIN)   # 测试直接进标题页
		set_process(false)
		return
	if args.has("--loadprof"):
		print("BOOTPROF boot_ready=%d" % Time.get_ticks_msec())
	FR.mark("boot")
	if OS.has_feature("web"):
		_web_overlay = bool(JavaScriptBridge.eval("typeof window.__syBootProgress === 'function' && !!document.getElementById('sy-load')", true))
		if _web_overlay:
			base = clampf(float(JavaScriptBridge.eval("window.__syPct || 0.6", true)), 0.0, 0.95)
			visible = false
			JavaScriptBridge.eval("window.__syBootUp()", true)
	if not _web_overlay:
		font = load("res://fonts/ui.ttf")
		var img: Image = load("res://art/ui/title_deep/logo_mark.png").get_image()
		img.generate_mipmaps()
		tex_logo = ImageTexture.create_from_image(img)
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 标志缩小显示；其余都是矢量图形
		bg = GradientTexture2D.new()
		bg.fill = GradientTexture2D.FILL_RADIAL
		bg.fill_from = Vector2(0.5, 0.5)
		bg.fill_to = Vector2(1.1, 1.1)
		var g := Gradient.new()
		g.set_color(0, Color8(13, 24, 32))
		g.set_color(1, Color8(4, 7, 10))
		g.add_point(0.7, Color8(7, 12, 17))
		bg.gradient = g
	var f := FileAccess.open(ORDER, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			items = d.get("items", [])
	tip_i = randi() % Tips.TIPS.size()
	_threads = OS.has_feature("threads") and not OS.has_feature("web")
	_v = clampi(Bal.vi("ui/boot_v", 0), 0, 3)
	if font != null:
		views = Views.new(self, font)
	if rec_dir != "":
		DirAccess.make_dir_recursive_absolute(rec_dir)
		var r := Rec.new()
		r.dir = rec_dir
		r.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child.call_deferred(r)
	_budget_ms = _frame_budget_ms()


## 静态协程不依附即将释放的启动节点；测试跳过预热时也要在新场景画出后关闭 HTML 遮罩。
static func _skip_web_boot(tree: SceneTree) -> void:
	if tree.change_scene_to_file(MAIN) != OK:
		return
	await tree.scene_changed
	await RenderingServer.frame_post_draw
	JavaScriptBridge.eval("window.__syBootDone && window.__syBootDone()", true)


func _process(delta: float) -> void:
	_web_progress()
	if _v > 0:
		_log_track()   # 放在最前：后面打开标题页 / 稳帧阶段会提前 return
	var now := Time.get_ticks_usec()
	var dt_ms := (now - _last_us) / 1000.0 if _last_us > 0 else 0.0
	_last_us = now
	t += delta
	tip_t += delta
	if tip_t >= 4.0:
		tip_t = 0.0
		tip_i = (tip_i + 1) % Tips.TIPS.size()
	if out_t >= 0.0:
		# 淡出：标题页已在下面画稳了，本页渐隐露出它（标题开场从头播）
		out_t += delta
		modulate.a = 1.0 - clampf(out_t / OUT_LEN, 0.0, 1.0)
		if out_t >= OUT_LEN:
			set_process(false)
			var mark := Node.new()
			mark.name = "BootDone"   # 录像（--bootrec）据此再录 2 秒标题页
			get_tree().root.add_child(mark)
			get_parent().queue_free()   # 连同盖层一起释放
		queue_redraw()
		return
	if _opened:   # 不用 title != null：标题页被测试切走释放后，那个引用按 null 算，会再建一个标题页（实测死循环）
		_gate(dt_ms)
		queue_redraw()
		return
	if t > 0.05:   # 先让第一帧画出来
		if idx < items.size():
			if _threads:
				_step_threaded()
			else:
				_step_sync()
		elif main_scene == null:
			cur_label = "标题页"
			cur_file = MAIN.get_file()
			main_scene = load(MAIN)
		else:
			_open_title()
	queue_redraw()


## 网页（无线程）：主线程逐个 load，每帧最多 BUDGET_USEC（单个超过也只读这一个）
func _step_sync() -> void:
	var t0 := Time.get_ticks_usec()
	while idx < items.size() and (Time.get_ticks_usec() - t0 < BUDGET_USEC or Time.get_ticks_usec() == t0):
		if (items[idx] as Array).size() > 2 and _announced != idx:
			_begin_item()
			_announced = idx   # 整圈编译的大项（gen_boot_order 标 heavy）：先把「正在读什么」画出来，下一帧再读
			return
		_begin_item()
		if ResourceLoader.exists(cur_path):
			var l0 := Time.get_ticks_usec()
			load(cur_path)
			if FR.enabled() and Time.get_ticks_usec() - l0 > 40000:
				print("PF FTLOAD %s %.0f ms" % [cur_path, (Time.get_ticks_usec() - l0) / 1000.0])
		idx += 1
		if _slow_ms > 0:
			OS.delay_msec(_slow_ms)
			return
		if shot and idx == items.size() / 2:
			_shot()
			return


## 桌面：一个接一个交给后台线程编译（game.gd 这类大脚本单个就要几秒，以前整段卡在一帧里、进度不动）；
## 主线程每帧最多等 WAIT_USEC，大脚本编译时照常出帧。一次只交一个（按依赖顺序，不让两个线程同时编译互相引用的脚本）
func _step_threaded() -> void:
	var t0 := Time.get_ticks_usec()
	while idx < items.size():
		if cur_path == "" or _req == "":
			_begin_item()
			if not ResourceLoader.exists(cur_path) or ResourceLoader.load_threaded_request(cur_path) != OK:
				_end_item()
				continue
			_req = cur_path
			_req_t = Time.get_ticks_usec()
		var st := ResourceLoader.load_threaded_get_status(_req)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if Time.get_ticks_usec() - t0 > WAIT_USEC:
				return
			OS.delay_usec(200)
			continue
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(_req)
		if FR.enabled() and Time.get_ticks_usec() - _req_t > 40000:
			print("PF FTLOAD %s %.0f ms（后台）" % [_req, (Time.get_ticks_usec() - _req_t) / 1000.0])
		_end_item()
		if shot and idx == items.size() / 2:
			_shot()
			return
		if Time.get_ticks_usec() - t0 > WAIT_USEC:
			return


func _begin_item() -> void:
	var it: Array = items[idx]
	cur_path = str(it[0])
	cur_file = cur_path.get_file()
	cur_label = str(it[1])


func _end_item() -> void:
	if _slow_ms > 0:
		OS.delay_msec(_slow_ms)
	idx += 1
	cur_path = ""
	_req = ""


## 脚本读完：标题页在本页下面建好、开始画（本页挪进最上层的盖层），同时离屏画一遍对局会用的着色器（render/shader_warm.gd）
func _open_title() -> void:
	cur_label = "预热画面"
	cur_file = ""
	var layer := CanvasLayer.new()
	layer.layer = 128   # 盖过标题页自己的各层（背景 -1、载入页 80、转场 90）
	get_tree().root.add_child(layer)
	reparent(layer, false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_opened = true
	title = main_scene.instantiate()
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	if title.has_method("boot_cover"):
		title.boot_cover()
	warm = preload("res://scripts/render/shader_warm.gd").new()
	warm.parts = warm.PARTS_UI if OS.has_feature("web") else warm.PARTS_ALL   # 网页的粒子那批放到出发后的载入页（一种就编译 5–9 秒）
	layer.add_child(warm)
	_gate_t0 = Time.get_ticks_usec()
	_good = 0
	_good_slow = 0
	_last_us = 0   # 建标题页这一帧不算


## 稳帧门：着色器画完后，连续 GOOD_N 帧的真实帧间隔都在一帧预算内（60 帧；显示器更低或设了帧率上限就按那个），才淡出、标题开场从头播。
## 到不了 60 的设备：盖满 GATE_SLOW 秒后连续 GOOD_N 帧都在两帧预算内也放行；最多等 GATE_MAX 秒（被别的程序占满时照样进），至少盖 GATE_MIN 秒。标题页中途切走（测试直接进局）就立刻撤掉盖层。
func _gate(dt_ms: float) -> void:
	if not is_instance_valid(title) or get_tree().current_scene != title:
		_web_progress(true)
		set_process(false)
		get_parent().queue_free()
		return
	if is_instance_valid(warm):
		cur_file = "着色器 %d / %d" % [warm.total - warm.steps.size(), warm.total]
		return
	if dt_ms > 0.0:
		_good = _good + 1 if dt_ms <= _budget_ms * 1.12 else 0
		_good_slow = _good_slow + 1 if dt_ms <= _budget_ms * 2.2 else 0
	cur_file = "帧时稳定 %d / %d" % [mini(_good, GOOD_N), GOOD_N]
	var held := (Time.get_ticks_usec() - _gate_t0) / 1e6
	var timeout := held >= (GATE_MAX_WEB if OS.has_feature("web") else GATE_MAX)
	# 慢设备到不了 60：盖满 GATE_SLOW 秒后，只要连续 GOOD_N 帧都在两帧预算内（没有尖峰、稳在 30 帧以上）也放行，不白等到超时
	var slow_ok := held >= GATE_SLOW and _good_slow >= GOOD_N
	if (_good >= GOOD_N and held >= GATE_MIN) or slow_ok or timeout:
		if FR.enabled():
			print("PF FTGATE held=%.2f good=%d slow=%d timeout=%s budget=%.1f" % [held, _good, _good_slow, timeout, _budget_ms])
		if Cfg.dev_args().has("--loadprof"):
			print("BOOTPROF boot_done=%d" % Time.get_ticks_msec())
		if title.has_method("boot_reveal"):
			title.boot_reveal()
		FR.mark("reveal")
		out_t = 0.0
		_web_progress(true)



## HTML 页从下载一直保留到主菜单可用；只在百分比或阶段变化时跨桥更新。
func _web_progress(done := false) -> void:
	if not _web_overlay:
		return
	var label := "准备主菜单" if _opened else "读取 · " + cur_label
	var value := _progress()
	var key := str(int(value * 100.0)) + label
	if key != _web_last or done:
		_web_last = key
		JavaScriptBridge.eval("window.__syBootProgress && window.__syBootProgress(%s,%s)" % [value, JSON.stringify(label)], true)
	if done:
		JavaScriptBridge.eval("window.__syBootDone && window.__syBootDone()", true)

## 一帧预算（毫秒）：60 帧，显示器刷新率更低或设了帧率上限时取更长的那个
func _frame_budget_ms() -> float:
	var fps := 60.0
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz > 1.0:
		fps = minf(fps, hz)
	if Engine.max_fps > 0:
		fps = minf(fps, float(Engine.max_fps))
	return 1000.0 / fps


func _shot() -> void:
	var dir := "/tmp/claude-0"
	for a in Cfg.dev_args():
		if a.begins_with("--shotdir="):
			dir = a.substr(10)
	set_process(false)
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/shot_boot.png")
	get_tree().quit()


## 进度 0–1：脚本占 88%，标题页场景 4%，预热画面（着色器 + 稳帧）8%
func _progress() -> float:
	var f := 0.0
	if not items.is_empty():
		f = 0.88 * float(idx) / float(items.size())
	if main_scene != null:
		f = 0.92
	if _opened:
		var w := 0.5 + 0.5 * minf(_good, GOOD_N) / float(GOOD_N)
		if is_instance_valid(warm):
			w = 0.5 * warm.progress()
		f = 0.92 + 0.08 * w
	if out_t >= 0.0:
		f = 1.0
	return base + (1.0 - base) * f


## 系统日志（方向 1–3），每帧按真实状态重排（不预录）：终端唤醒 → 每个编译类别一行（按第一次读到的先后，「n / 总数」，读满标 OK；
## boot_order 是叶子在前、类别穿插着读，所以不按「换类别就换行」，否则同一类会刷很多行）→ 展开标题页 → 着色器 → 稳帧 → 接入完成。
## 每行的时间是它第一次出现的时刻
func _log_track() -> void:
	if _cat_tot.is_empty():
		for it in items:
			var k: String = str(it[1])
			_cat_tot[k] = int(_cat_tot.get(k, 0)) + 1
	var cnt := {}
	var order: Array = []
	for i in mini(idx + 1, items.size()):
		var k2: String = str(items[i][1])
		if not cnt.has(k2):
			order.append(k2)
			cnt[k2] = 0
		if i < idx:
			cnt[k2] += 1
	lines.clear()
	_log_line("boot", "终端唤醒 · 启动引擎", true)
	var cur_cat: String = str(items[idx][1]) if idx < items.size() else ""
	for k3 in order:
		_log_line("c" + k3, "编译 · %s  %d / %d" % [k3, cnt[k3], _cat_tot[k3]], cnt[k3] >= _cat_tot[k3], k3 == cur_cat)
	var scripts_done: bool = idx >= items.size()
	if scripts_done:
		_log_line("title", "展开标题页", _opened, not _opened)
	if _opened:
		_log_line("warm", "渲染预热 · 着色器", not is_instance_valid(warm), is_instance_valid(warm))
		if not is_instance_valid(warm):
			_log_line("gate", "神经连接校准 · 帧时稳定", out_t >= 0.0, out_t < 0.0)
	if out_t >= 0.0:
		_log_line("done", "接入完成", true)


## cur = 正在读的这一行（光标闪）；其余没读完的写「..」
func _log_line(key: String, s: String, ok: bool, cur := false) -> void:
	if not _seen_t.has(key):
		_seen_t[key] = t
	lines.append({"k": key, "t": _seen_t[key], "s": s, "ok": ok, "cur": cur})


func _view_state() -> Dictionary:
	var ta := 1.0 if Cfg.reduce_motion else clampf(tip_t / 0.22, 0.0, 1.0) * clampf((4.0 - tip_t) / 0.22, 0.0, 1.0)
	var label: String = "进入标题页" if out_t >= 0.0 else (cur_label if _opened else "编译 · " + cur_label)
	var file: String = cur_file if out_t < 0.0 else ""
	return {"p": _progress(), "label": label, "file": file, "n": mini(idx, items.size()), "total": items.size(),
		"lines": lines, "t": t, "tip": Tips.TIPS[tip_i], "tip_a": ta}


func _txt(pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, pos, s, align, w, sz, col)


func _en_w(s: String, sz: int, sp: float) -> float:
	var w := 0.0
	for ch in s:
		w += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp
	return w - sp


## 拉丁小字加字距（同标题页英文标签的写法）
func _en(pos: Vector2, s: String, sz: int, col: Color, sp := 3.0, center := false) -> void:
	var w := _en_w(s, sz, sp)
	var x := pos.x - (w / 2.0 if center else 0.0)
	for ch in s:
		draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x + sp


func _draw() -> void:
	if font == null:
		return
	var vs := size
	if _v > 0 and views != null:
		match _v:
			1:
				views.draw_v1(vs, _view_state())
			2:
				views.draw_v2(vs, _view_state())
			3:
				views.draw_v3(vs, _view_state())
		return
	draw_texture_rect(bg, Rect2(Vector2.ZERO, vs), false)
	var gc := Color(0.47, 0.67, 0.75, 0.05)
	var gx := 0.0
	while gx < vs.x:
		draw_line(Vector2(gx, 0), Vector2(gx, vs.y), gc, 1.0)
		gx += 24.0
	var gy := 0.0
	while gy < vs.y:
		draw_line(Vector2(0, gy), Vector2(vs.x, gy), gc, 1.0)
		gy += 24.0
	var compact := vs.y <= 520.0
	# 标志、页眉
	var lw := minf(300.0 if not compact else 200.0, vs.x * 0.38)
	draw_texture_rect(tex_logo, Rect2(Vector2(40, 36) if not compact else Vector2(20, 16), Vector2(lw, lw * 86.0 / 482.0)), false)
	if vs.x > 700:
		var fan := "ARKNIGHTS FAN GAME"
		var fw := _en_w(fan, 11, 4.0)
		_en(Vector2(vs.x - (40 if not compact else 20) - fw, 54 if not compact else 30), fan, 11, Color(0.5, 0.6, 0.64), 4.0)
	_draw_sonar(vs)
	_draw_panels(vs, compact)
	_txt(Vector2(0, vs.y - (16 if not compact else 8)), "明日方舟同人作品 · 非商业 · 与鹰角网络无关", 11, Color(0.44, 0.52, 0.56), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_sonar(vs: Vector2) -> void:
	var w := minf(400.0, minf(vs.y * 0.52, vs.x * 0.6))
	var u := w / 420.0
	var c := Vector2(vs.x / 2.0, vs.y * 0.45)
	for r in [180.0, 120.0, 60.0]:
		draw_arc(c, r * u, 0.0, TAU, 96, Color8(42, 60, 70) if r == 180.0 else Color8(31, 46, 54), 1.0, true)
	draw_line(c + Vector2(-190, 0) * u, c + Vector2(190, 0) * u, Color8(26, 39, 46), 1.0)
	draw_line(c + Vector2(0, -190) * u, c + Vector2(0, 190) * u, Color8(26, 39, 46), 1.0)
	# 扫描扇面：3.2 秒一圈，前沿亮、往后淡（减少动态：停在固定角度）
	var ang := -0.35 if Cfg.reduce_motion else fmod(t / 3.2, 1.0) * TAU
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([Color(CYAN, 0.0)])
	for i in 13:
		var a := ang - PI / 4.0 + (PI / 4.0) * i / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * 180.0 * u)
		cols.append(Color(CYAN, 0.32 * i / 12.0))
	draw_polygon(pts, cols)
	# 回波点：扇面扫过时亮起再淡出
	for b in [Vector2(70, -96), Vector2(-110, 40), Vector2(30, 130), Vector2(-60, -120)]:
		var ba := atan2(b.y, b.x)
		var since := fposmod(ang - ba, TAU) / TAU
		var al := 0.6 if Cfg.reduce_motion else clampf(1.0 - since * 1.6, 0.0, 1.0)
		draw_circle(c + b * u, 3.0 * u, Color(CYAN, al))
	# 进度环
	var p := _progress()
	draw_arc(c, 192.0 * u, 0.0, TAU, 128, Color8(29, 42, 50), 6.0 * u, true)
	if p > 0.0:
		draw_arc(c, 192.0 * u, -PI / 2.0, -PI / 2.0 + TAU * p, maxi(8, int(128 * p)), CYAN, 6.0 * u, true)
	for k in 4:
		var d := Vector2.from_angle(k * PI / 2.0)
		draw_line(c + d * 200.0 * u, c + d * 210.0 * u, Color8(59, 79, 90), 1.5)
	# 圈心：百分比 + SONAR · BOOT
	var big := int(maxf(28.0, 64.0 * u))
	var num := str(int(floor(p * 100.0)))
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	var pw := font.get_string_size("%", HORIZONTAL_ALIGNMENT_LEFT, -1, int(big * 0.38)).x
	var nx := c.x - (nw + pw + 2.0) / 2.0
	_txt(Vector2(nx, c.y + big * 0.32), num, big, TEXT)
	_txt(Vector2(nx + nw + 2.0, c.y + big * 0.32), "%", int(big * 0.38), CYAN)
	_en(Vector2(c.x, c.y + big * 0.32 + 26.0 * u + 6.0), "SONAR · BOOT", 11, CYAN, 3.0, true)
	# 圈下：正在读什么
	var ty := c.y + 210.0 * u + 30.0
	var what := "打开标题页" if out_t >= 0.0 else (cur_label if _opened else "读取 · " + cur_label)
	_txt(Vector2(0, ty), what, 15, TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if out_t < 0.0 and _opened:
		_txt(Vector2(0, ty + 20.0), cur_file, 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	elif out_t < 0.0 and not items.is_empty():
		_txt(Vector2(0, ty + 20.0), "%s　%d / %d" % [cur_file, mini(idx + 1, items.size()), items.size()], 11, DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_panels(vs: Vector2, compact: bool) -> void:
	var pw := minf(330.0 if not compact else 260.0, vs.x * (0.3 if not compact else 0.27))
	var ph := 190.0 if not compact else 120.0
	var by := vs.y - (50.0 if not compact else 30.0) - ph
	var mx := 40.0 if not compact else 20.0
	var lh := 22.0 if not compact else 17.0
	var fs := 13 if not compact else 11
	for r in [Rect2(mx, by, pw, ph), Rect2(vs.x - mx - pw, by, pw, ph)]:
		draw_rect(r, Color(0.055, 0.086, 0.11, 0.82))
		draw_rect(r, Color8(38, 53, 64), false, 1.0)
		draw_line(r.position + Vector2(0, 26), r.position + Vector2(r.size.x, 26), Color8(38, 53, 64), 1.0)
	_en(Vector2(mx + 12, by + 18), "TERMINAL LOG", 11, Color(0.56, 0.65, 0.69), 3.0)
	_en(Vector2(vs.x - mx - pw + 12, by + 18), "TIPS", 11, Color(0.56, 0.65, 0.69), 3.0)
	# 日志：网页先列 HTML 加载页做完的三步
	var lines: Array = []
	if OS.has_feature("web"):
		lines.append([1, "下载资源"])
		lines.append([1, "解压校验"])
	lines.append([1, "启动引擎"])
	var scripts_done := idx >= items.size()
	lines.append([1 if scripts_done else 0, "编译脚本　%d / %d" % [mini(idx, items.size()), items.size()]])
	lines.append([1 if _opened else (0 if scripts_done else -1), "打开标题页"])
	lines.append([1 if out_t >= 0.0 else (0 if _opened else -1), "预热画面"])
	var y := by + 26 + lh
	for ln in lines:
		var st: int = ln[0]
		var tag: String = "[ OK ]" if st == 1 else ("[ .. ]" if st == 0 else "[ -- ]")
		var col: Color = Color(0.62, 0.7, 0.73) if st == 1 else (TEXT if st == 0 else Color(0.27, 0.33, 0.36))
		_txt(Vector2(mx + 12, y), tag, fs, CYAN if st == 1 else col)
		_txt(Vector2(mx + 12 + (48 if not compact else 40), y), str(ln[1]), fs, col)
		y += lh
	# 提示：自动换行
	var ta := 1.0 if Cfg.reduce_motion else clampf(tip_t / 0.22, 0.0, 1.0) * clampf((4.0 - tip_t) / 0.22, 0.0, 1.0)
	# 网页包没有中文断词数据（只按空格断，整句不换行冲出面板）：允许按字断（ADAPTIVE：放得下的词不拆）
	var brk := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE
	draw_multiline_string(font, Vector2(vs.x - mx - pw + 12, by + 26 + lh), Tips.TIPS[tip_i], HORIZONTAL_ALIGNMENT_LEFT, pw - 24, fs, -1, Color(0.71, 0.78, 0.8, ta), brk)
