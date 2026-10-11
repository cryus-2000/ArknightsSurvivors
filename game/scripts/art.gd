extends RefCounted
## 美术资源加载：优先读取项目外的 art/incoming/（美术新交付的图），没有再用游戏内置的占位图。
## 这样新图放进文件夹后，重新打开游戏就能看到，不需要重新导出。

static var _cache := {}

## 载入计时（--loadprof）：标题页离开 / game.gd _ready 各阶段 / 首帧画完打点，首帧后打印 LOADPROF（docs/36 §5）。
## 这里不能用 Cfg：核心契约测试与 --script 工具不带自动加载
static var marks: Array = []
static func mark(n: String) -> void:
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--loadprof"):
		marks.append([n, Time.get_ticks_msec()])

## 美术交付用旧文件名时的对应关系（新名 -> incoming 里的文件名）
const ALIAS := {
	"e_bone": "drifter", "e_slider": "dart", "e_stone": "crawler", "e_pocket": "shell",
	"e_paranoia2": "e_paranoia_phase2", "e_paranoia2_move": "e_paranoia_phase2_move",
	# 藏品图标按原作编号命名（docs/11）；代码里仍用旧 id 的护盾藏品先做对照
	"relic_sh_base": "relic_118", "relic_sh_count": "relic_199", "relic_sh_fast": "relic_15",
	"relic_sh_burst": "relic_100", "relic_sh_plate": "relic_200", "relic_sh_ring": "relic_202",
}


static func _incoming_path(name: String) -> String:
	var p := incoming_dir().path_join(name + ".png")
	if FileAccess.file_exists(p):
		return p
	if ALIAS.has(name):
		var a := incoming_dir().path_join(ALIAS[name] + ".png")
		if FileAccess.file_exists(a):
			return a
	return ""


static func incoming_dir() -> String:
	if OS.has_feature("web"):
		return "res://art/incoming"  # 网页版：导出时把 art/incoming 打进包里，但包里是导入后的贴图（原图读不到，见 _packed_path）
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join("../art/incoming").simplify_path()
	return OS.get_executable_path().get_base_dir().path_join("../art/incoming").simplify_path()


## 网页版的 art/incoming：导出时被导入进 pck，包里只有 .import 与导入后的贴图，没有原始 PNG——
## FileAccess / Image.load_from_file 读不到，要用 ResourceLoader 读导入后的贴图（2026-09-26 查到：网页版选人页没有头像、
## 技能 / 藏品图标全空，都是这个原因）。编辑器与桌面版读 art/incoming 原图，走不到这里
static func _packed_path(name: String) -> String:
	var p := "res://art/incoming/%s.png" % name
	if ResourceLoader.exists(p):
		return p
	if ALIAS.has(name):
		var a := "res://art/incoming/%s.png" % ALIAS[name]
		if ResourceLoader.exists(a):
			return a
	return ""


static func has_override(name: String) -> bool:
	return _incoming_path(name) != "" or _packed_path(name) != ""


## 是否为贴图生成法线图（2D 法线光照）；由 game.gd 按 Cfg.normal_maps 在加载前设置
static var normal_maps := false
## 高清贴图：art/incoming/<name>@2x.png 存在时优先使用，像素密度 2 倍（96px 画 48px 的内容），
## 绘制时倍率减半，锚点 / 判定 / 帧数都不变。_hires 按名字记倍数，_hires_rid 按贴图记倍数。
## 是否启用 @2x 高清贴图。人物以 96px 为标准（art/incoming/squad_2x_handoff.md）：
## 水月、博士与具名编队全员都有 @2x；没有 @2x 的贴图（旧预备干员、敌人）继续用原图。
const USE_HIRES := true
static var _hires := {}
static var _hires_rid := {}
## 不做法线的贴图前缀（地面 / 特效 / UI 图标：做了反而奇怪）
const NO_NORMAL_PREFIX := ["tiles", "terrain_", "fx_", "proj_", "relic_", "growth_", "skill_", "evo_", "weapon_", "light", "shadow", "slash", "title_", "ebullet", "drone_bullet", "drone_laser", "portraits/"]


## 取贴图；找不到返回 null
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var t: Texture2D = null
	var density := 1.0
	var src_path := ""   # 法线缓存键用：原图路径（磁盘 PNG 或包内资源）
	var p2 := _incoming_path(name + "@2x") if USE_HIRES else ""
	if p2 != "":
		var img2 := Image.load_from_file(p2)
		if img2 != null and not img2.is_empty():
			t = ImageTexture.create_from_image(img2)
			density = 2.0
			src_path = p2
	elif USE_HIRES:
		var q2 := _packed_path(name + "@2x")
		if q2 != "":
			t = load(q2)
			if t != null:
				density = 2.0
				src_path = q2
	if t == null:
		var p := _incoming_path(name)
		if p != "":
			var img := Image.load_from_file(p)
			if img != null and not img.is_empty():
				t = ImageTexture.create_from_image(img)
				src_path = p
		else:
			var q := _packed_path(name)
			if q != "":
				t = load(q)
				src_path = q
	if t == null and ResourceLoader.exists("res://art/px/%s.png" % name):
		src_path = "res://art/px/%s.png" % name
		t = load(src_path)
	if t != null and normal_maps and _wants_normal(name):
		t = _with_normal(t, name, src_path)
	if t != null:
		_hires[name] = density
		_hires_rid[t.get_rid()] = density
	_cache[name] = t
	return t


## 贴图的像素密度（1 = 普通，2 = @2x 高清），绘制倍率应除以它
static func hires(name: String) -> float:
	return float(_hires.get(name, 1.0))


static func hires_of(t: Texture2D) -> float:
	if t == null:
		return 1.0
	return float(_hires_rid.get(t.get_rid(), 1.0))


static func _wants_normal(name: String) -> bool:
	for pre in NO_NORMAL_PREFIX:
		if name.begins_with(pre):
			return false
	return true


# ------------------------------------------------------------------ 法线图
## 2026-10-06 之前每局开始都在 GDScript 里逐像素生成 173 张法线图（get_pixel / set_pixel，约 10 秒），
## 这就是选完干员后那段黑屏。现在：
## 1. 生成改走 PackedByteArray（normal_image），快 5 倍以上；
## 2. 生成结果存到 user://normal_cache/<名>_<尺寸>_<原图大小>_<改动时间>.png，下次启动直接读；
## 3. 标题页一打开就起后台线程把本局要用的法线图算好 / 读好（prewarm_start，名单见 game.gd preload_tex_names），
##    玩家还在选干员时就已完成；没完成就在标题页画「载入中…」等它（title.gd），不再黑屏。
## 法线图纯画面，不碰 g.rng；同 seed 的结果不受影响。
const NORMAL_CACHE_DIR := "user://normal_cache"
const NORMAL_MAX_PX := 400000

static var _nm_mutex := Mutex.new()
static var _nm_ready := {}          # name -> Image（预热算好 / 读好，等主线程做成贴图；null = 这张不做法线）
static var _nm_queue: Array = []    # 待预热的名字（线程共享）
static var _nm_total := 0
static var _nm_done := 0
static var _nm_threads: Array = []
static var _nm_started := false
static var _nm_t0 := 0
static var _nm_stats := {"thread": 0, "disk": 0, "sync": 0}   # --loadprof：法线图各来自哪里
static var _nm_sync_names: Array = []                           # --loadprof：当场同步算的（预热名单漏掉的）


## 预热：把 names 里需要法线的贴图在后台线程算好（有缓存就读缓存）。幂等；无界面 / 不开法线 / 已开始都直接返回。
## 网页版没有线程支持（export_presets variant/thread_support=false）：退回主线程逐帧算（prewarm_step 由标题页每帧调一次）
static func prewarm_start(names: Array) -> void:
	if _nm_started or not normal_maps or DisplayServer.get_name() == "headless":
		return
	_nm_started = true
	_nm_queue.clear()
	var seen := {}
	for n in names:
		if n is String and n != "" and not seen.has(n) and _wants_normal(n) and not _cache.has(n):
			seen[n] = true
			_nm_queue.append(n)
	_nm_total = _nm_queue.size()
	_nm_done = 0
	_nm_t0 = Time.get_ticks_msec()
	if _nm_total == 0:
		return
	if not OS.has_feature("threads"):
		return
	var workers := clampi(OS.get_processor_count() - 2, 1, 4)
	for i in mini(workers, _nm_total):
		var th := Thread.new()
		th.start(_prewarm_worker)
		_nm_threads.append(th)


static func _prewarm_worker() -> void:
	while prewarm_step():
		pass


## 处理队列里的一个名字；队列空了返回 false。线程与主线程都可调用（主线程模式一帧一张）
static func prewarm_step() -> bool:
	_nm_mutex.lock()
	if _nm_queue.is_empty():
		_nm_mutex.unlock()
		return false
	var name: String = _nm_queue.pop_front()
	_nm_mutex.unlock()
	var path := _normal_source(name)
	var packed := path.begins_with("res://")
	if path == "" or (packed and OS.has_feature("threads")):
		# 没图，或包内 / 占位贴图（线程里不碰 RenderingServer）：留给主线程 tex() 自己处理
		_nm_mutex.lock()
		_nm_done += 1
		_nm_mutex.unlock()
		return true
	var img: Image = null
	var key := ""
	if packed:
		var t: Texture2D = load(path)
		img = t.get_image() if t != null else null
		if img != null:
			key = _normal_key(path, img.get_width(), img.get_height())
	else:
		key = _normal_key(path, 0, 0)
	var nimg: Image = _normal_cache_load(name, key) if key != "" else null
	if nimg == null and key != "":
		if img == null:
			img = Image.load_from_file(path)
		if img != null and not img.is_empty():
			nimg = normal_image(img)
			if nimg != null:
				_normal_cache_save(name, key, nimg)
	_nm_mutex.lock()
	if key != "":
		_nm_ready[name] = nimg   # null 也记：这张超尺寸不做法线，主线程不用再算
	_nm_done += 1
	_nm_mutex.unlock()
	return true


## 网页版（无线程）：标题页每帧调一次，主线程算一张
static func prewarm_tick() -> void:
	if _nm_started and _nm_threads.is_empty():
		prewarm_step()


## 预热还没做完（标题页据此画「载入中…」并等待）。做完时顺便回收线程
static func prewarm_busy() -> bool:
	if not _nm_started:
		return false
	_nm_mutex.lock()
	var left := _nm_queue.size()
	_nm_mutex.unlock()
	if left > 0:
		return true
	if not _nm_threads.is_empty():
		for th in _nm_threads:
			if th.is_alive():
				return true
		prewarm_join()
		if OS.is_debug_build() and OS.get_cmdline_user_args().has("--loadprof"):
			print("PRELOAD normals=%d ms=%d" % [_nm_total, Time.get_ticks_msec() - _nm_t0])
	return false


static func prewarm_progress() -> Vector2i:
	_nm_mutex.lock()
	var v := Vector2i(_nm_done, _nm_total)
	_nm_mutex.unlock()
	return v


## 等全部线程结束（退出游戏前 / 预热完成后回收）
static func prewarm_join() -> void:
	for th in _nm_threads:
		th.wait_to_finish()
	_nm_threads.clear()


## 法线图的原图路径：与 tex() 选图的顺序一致（@2x 原图 > @2x 包内 > 原图 > 包内 > 占位）
static func _normal_source(name: String) -> String:
	var path := ""
	if USE_HIRES:
		path = _incoming_path(name + "@2x")
		if path == "":
			path = _packed_path(name + "@2x")
	if path == "":
		path = _incoming_path(name)
	if path == "":
		path = _packed_path(name)
	if path == "" and ResourceLoader.exists("res://art/px/%s.png" % name):
		path = "res://art/px/%s.png" % name
	return path


## 缓存键：磁盘原图按 文件大小_改动时间（图换了就失效）；包内贴图按尺寸（包是整体替换的）
static func _normal_key(path: String, w: int, h: int) -> String:
	if path == "":
		return ""
	if path.begins_with("res://"):
		return "pck%dx%d" % [w, h]
	var f := FileAccess.open(path, FileAccess.READ)
	var ln: int = f.get_length() if f != null else 0
	return "%d_%d" % [ln, FileAccess.get_modified_time(path)]


static func _normal_cache_path(name: String, key: String) -> String:
	return NORMAL_CACHE_DIR.path_join("%s_%s.png" % [name, key])


static func _normal_cache_load(name: String, key: String) -> Image:
	var path := _normal_cache_path(name, key)
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK:
		return null
	return img


static func _normal_cache_save(name: String, key: String, nimg: Image) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NORMAL_CACHE_DIR))
	var dir := DirAccess.open(NORMAL_CACHE_DIR)
	if dir == null:
		return
	# 同一张图的旧缓存（原图改过）删掉，别越攒越多；只匹配「名字_数字_数字.png / 名字_pck宽x高.png」，不误删同前缀的别的贴图
	var re := RegEx.create_from_string("^%s_(\\d+_\\d+|pck\\d+x\\d+)\\.png$" % name)
	for f in dir.get_files():
		if re.search(f) != null:
			dir.remove(f)
	var f := FileAccess.open(_normal_cache_path(name, key), FileAccess.WRITE)
	if f != null:
		f.store_buffer(nimg.save_png_to_buffer())


## 用 alpha 轮廓生成粗糙的法线图（边缘向外倾斜、中间朝向镜头），再打包成 CanvasTexture 供 Light2D 使用。
## 先用预热结果，再查磁盘缓存，最后当场算
static func _with_normal(src: Texture2D, name: String, src_path: String) -> Texture2D:
	var w := src.get_width()
	var h := src.get_height()
	if w * h > NORMAL_MAX_PX:
		return src
	var nimg: Image = null
	_nm_mutex.lock()
	var pre: bool = _nm_ready.has(name)
	if pre:
		nimg = _nm_ready[name]
		_nm_ready.erase(name)
	_nm_mutex.unlock()
	if pre:
		_nm_stats.thread += 1
		if nimg == null:
			return src
	else:
		var key := _normal_key(src_path, w, h)
		nimg = _normal_cache_load(name, key)
		if nimg != null:
			_nm_stats.disk += 1
		else:
			var img := src.get_image()
			if img == null:
				return src
			nimg = normal_image(img)
			if nimg == null:
				return src
			_nm_stats.sync += 1
			_nm_sync_names.append(name)
			_normal_cache_save(name, key, nimg)
	var ct := CanvasTexture.new()
	ct.diffuse_texture = src
	ct.normal_texture = ImageTexture.create_from_image(nimg)
	ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return ct


## 由 alpha 轮廓算法线图（纯函数，可在线程里跑）：高度场 = alpha > 0.5 的 3×3 均值再取两次（圆润的「充气」高度），
## 法线取中心差分。超过 NORMAL_MAX_PX 返回 null。算法与 2026-10-06 前逐像素版相同，只是改成了分离卷积 + 整数和 +
## 直接写字节（对照过 6 张图逐字节相同或仅边缘个别像素差 1/255）
static func normal_image(img: Image) -> Image:
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w * h > NORMAL_MAX_PX:
		return null
	var data := img.get_data()
	var n := w * h
	var hg := PackedInt32Array()
	hg.resize(n)
	for i in n:
		hg[i] = 1 if data[i * 4 + 3] > 127 else 0
	# 两遍 3×3 盒式均值，用分离卷积（横向 3 点和 → 纵向 3 点和），边缘夹紧；最后再除 81
	var tmp := PackedInt32Array()
	tmp.resize(n)
	for _pass in 2:
		for y in h:
			var row := y * w
			for x in w:
				var l := row + maxi(x - 1, 0)
				var r := row + mini(x + 1, w - 1)
				tmp[row + x] = hg[l] + hg[row + x] + hg[r]
		for y in h:
			var row := y * w
			var up := maxi(y - 1, 0) * w
			var dn := mini(y + 1, h - 1) * w
			for x in w:
				hg[row + x] = tmp[up + x] + tmp[row + x] + tmp[dn + x]
	# hg 现在是 81 倍的高度；法线 = normalize((l - r) * 2, (d - u) * 2, 1)
	var out := PackedByteArray()
	out.resize(n * 4)
	out.fill(0)
	for y in h:
		var row := y * w
		var up := maxi(y - 1, 0) * w
		var dn := mini(y + 1, h - 1) * w
		for x in w:
			var i := row + x
			var dx: int = hg[row + maxi(x - 1, 0)] - hg[row + mini(x + 1, w - 1)]
			var dy: int = hg[dn + x] - hg[up + x]
			var o := i * 4
			# 与旧版 set_pixel(Color) 一致：Image 把 0–1 转成字节是截断不是四舍五入（平坦处 0.5 → 127）
			if dx == 0 and dy == 0:
				out[o] = 127
				out[o + 1] = 127
				out[o + 2] = 255
			else:
				var v := Vector3(dx * 2.0 / 81.0, dy * 2.0 / 81.0, 1.0).normalized()
				out[o] = clampi(int((v.x * 0.5 + 0.5) * 255.0), 0, 255)
				out[o + 1] = clampi(int((v.y * 0.5 + 0.5) * 255.0), 0, 255)
				out[o + 2] = clampi(int((v.z * 0.5 + 0.5) * 255.0), 0, 255)
			out[o + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## --loadprof 用：法线图来源统计与预热名单漏掉的名字
static func normal_stats() -> String:
	return "normals=%s sync_names=%s" % [str(_nm_stats), str(_nm_sync_names)]


## 由任意贴图生成白色剪影（受击闪白用）
static func white_of(src: Texture2D) -> Texture2D:
	if src == null:
		return null
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, c.a))
	var w := ImageTexture.create_from_image(img)
	_hires_rid[w.get_rid()] = hires_of(src)
	return w
