extends RefCounted
## 美术资源加载：优先读取项目外的 art/incoming/（美术新交付的图），没有再用游戏内置的占位图。
## 这样新图放进文件夹后，重新打开游戏就能看到，不需要重新导出。

static var _cache := {}
static var enemy_pixels: Dictionary = {}
static var _enemy_pixels_loaded := false
static var _enemy_pixel_tops: Dictionary = {}

static func enemy_pixel_spec(name: String) -> Dictionary:
	if not _enemy_pixels_loaded:
		_enemy_pixels_loaded = true
		var path := "res://data/enemy_pixels.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				enemy_pixels = parsed
	return _by_file(enemy_pixels, name)

## 10-23 怪物重画（tools/install_enemy_redraw.py 生成 data/enemy_redraw.json）：帧条真实帧数、攻击出手帧 event_frames、循环时长。
## 没登记的帧条（图鉴旧图、特效）返回 {}，调用方按旧口径
static var _redraw: Dictionary = {}
static var _redraw_loaded := false

static func enemy_redraw(name: String) -> Dictionary:
	if not _redraw_loaded:
		_redraw_loaded = true
		var path := "res://data/enemy_redraw.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_redraw = parsed
	return _by_file(_redraw, name)


## 按贴图名查重画表；名字是别名（ALIAS，例如 e_paranoia2 → 文件 e_paranoia_phase2）时按文件名查。
## 10-24 修（docs/137 §7）：原来别名查不到，偏执泡影二阶段 6 帧条按缺省 2 帧切，一「帧」里并排画出 3 只泡影（挨打时的「重影」）
static func _by_file(table: Dictionary, name: String) -> Dictionary:
	var k := name.trim_suffix("_white")
	if table.has(k):
		return table[k]
	return table.get(ALIAS.get(k, ""), {})

## 帧条真实帧数（重画帧条读 enemy_redraw.json，其余用 fallback）
static func enemy_frames(name: String, fallback: int) -> int:
	return int(enemy_redraw(name).get("frames", fallback))

## 循环帧条的每秒帧数 = 帧数 / 原作动画时长；没登记用 fallback
static func enemy_loop_fps(name: String, fallback: float) -> float:
	var r := enemy_redraw(name)
	var d: float = float(r.get("duration", 0.0))
	return float(r.get("frames", 0)) / d if d > 0.0 and int(r.get("frames", 0)) > 0 else fallback

## 旧口径（攻击帧条 4 帧：0、1 = 蓄力，2、3 = 出手后）→ 重画帧条（N 帧，出手帧 event_frames[0]）：蓄力段摊到 0..ev-1，出手后摊到 ev..N-1；
## 非攻击类按比例。旧帧数 = 新帧数时原样返回（骑士冲锋 / 突刺等本来就同帧数的不动）
static func enemy_remap_frame(name: String, legacy: int, f: int) -> int:
	var r := enemy_redraw(name)
	var n := int(r.get("frames", 0))
	if n <= 0 or n == legacy or legacy <= 0:
		return f
	var ev := -1
	var evs: Array = r.get("event_frames", [])
	if not evs.is_empty():
		ev = int(evs[0])
	elif r.get("release_frame") != null:
		ev = int(r.release_frame)
	if ev > 0 and legacy >= 2:
		var w: int = maxi(1, legacy / 2)
		if f < w:
			return clampi(int(float(f) * ev / w), 0, ev - 1)
		return clampi(ev + int(float(f - w) * (n - ev) / maxf(1.0, float(legacy - w))), ev, n - 1)
	return clampi(int(float(f) * n / legacy), 0, n - 1)

static func enemy_pixel_anchor(name: String, fallback: Vector2) -> Vector2:
	var spec := enemy_pixel_spec(name)
	var a = spec.get("anchor")
	return Vector2(float(a[0]), float(a[1])) if a is Array and a.size() == 2 else fallback

static func enemy_pixel_scale(name: String) -> float:
	return float(enemy_pixel_spec(name).get("scale", 1.0))

## Native strips retain transparent skeleton space; labels belong above visible pixels.
static func enemy_pixel_top(name: String, texture: Texture2D) -> float:
	var key := str(texture.get_rid())
	if not _enemy_pixel_tops.has(key):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		_enemy_pixel_tops[key] = image.get_used_rect().position.y
	return texture.get_height() * enemy_pixel_anchor(name, Vector2(0.5, 1.0)).y - float(_enemy_pixel_tops[key])

static var late_log := false   # --perf：开局后才读的贴图逐张打印 TEXLATE（docs/50 §10）

## 载入计时（--loadprof）：标题页离开 / game.gd _ready 各阶段 / 首帧画完打点，首帧后打印 LOADPROF（docs/36 §5）。
## 这里不能用 Cfg：核心契约测试与 --script 工具不带自动加载
static var marks: Array = []
static func mark(n: String) -> void:
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--loadprof"):
		marks.append([n, Time.get_ticks_msec()])
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--memlog"):
		print("PF MEMSTAGE %s tex=%.1fMB vid=%.1fMB" % [n, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])   # docs/50 §30：建局各段的贴图增量

## 美术交付用旧文件名时的对应关系（新名 -> incoming 里的文件名）
const ALIAS := {
	"e_bone": "drifter", "e_slider": "dart", "e_stone": "crawler", "e_pocket": "shell",
	"e_paranoia2": "e_paranoia_phase2", "e_paranoia2_move": "e_paranoia_phase2_move",
	# 藏品图标按原作编号命名（docs/11）；代码里仍用旧 id 的护盾藏品先做对照
	"relic_sh_base": "relic_118", "relic_sh_count": "relic_199", "relic_sh_fast": "relic_15",
	"relic_sh_burst": "relic_100", "relic_sh_plate": "relic_200", "relic_sh_ring": "relic_202",
}


## 别名对应的文件名，带 @1x / @2x 后缀也认（10-24：被 @2x 遮蔽的 1x 基础条删掉后，e_paranoia2 只剩 e_paranoia_phase2@2x，
## 原来只按基础名查别名，tex 先试的 e_paranoia2@2x 落空 → 泡影二阶段整只画不出、加密包校验 alias 失败）
static func _alias_file(name: String) -> String:
	if ALIAS.has(name):
		return ALIAS[name]
	for suf in ["@2x", "@1x"]:
		if name.ends_with(suf) and ALIAS.has(name.trim_suffix(suf)):
			return ALIAS[name.trim_suffix(suf)] + suf
	return ""


## 运行时贴图索引（docs/189 §6.1）：game/art/index.json 由 tools/asset_index.py 生成，贴图名（含 @1x / @2x、
## "portraits/" / "optical_fx/" 前缀）→ res:// 路径。运行时贴图全在 game/art 里、由 Godot 导入，按索引读导入后的贴图；
## 10-28 迁移完成后不再读项目外的 art/incoming（那里只是收货区）
const INDEX_PATH := "res://art/index.json"
static var _index = null


static func _indexed(name: String) -> String:
	if _index == null:
		_index = {}
		var f := FileAccess.open(INDEX_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_index = d
	var p: String = _index.get(name, "")
	if p == "":
		var al := _alias_file(name)
		if al != "":
			p = _index.get(al, "")
	return p


## 名字（含别名）→ 索引里的导入贴图路径；没有返回 ""。包里只有 .import 与导入后的贴图、没有原始 PNG，
## 一律用 ResourceLoader 读（2026-09-26 网页版查到：Image.load_from_file 读不到包内原图）
static func _packed_path(name: String) -> String:
	var ix := _indexed(name)
	return ix if ix != "" and ResourceLoader.exists(ix) else ""


## 编辑器里直接跑（tools/godot_runner、快检）时导入贴图的源 PNG 还在磁盘上：法线预热线程读它（线程里不碰 RenderingServer），
## 法线缓存键按它的大小 + 修改时间算（改了图就失效）。导出包里没有源 PNG，返回 ""
static func _disk_source(path: String) -> String:
	if not path.begins_with("res://") or not OS.has_feature("editor"):
		return ""
	var g := ProjectSettings.globalize_path(path)
	return g if FileAccess.file_exists(g) else ""


## 有没有交付的图（基础名或 @2x，game/art 索引里）。10-24 起被 @2x 遮蔽的 1x 基础帧条已删（docs/131 §1.3），
## 只查基础名会让敌人白闪 / _emit 发光层 / 落脚锚点误判为「没有新图」
static func has_override(name: String) -> bool:
	for n in [name, name + "@2x"]:
		if _packed_path(n) != "":
			return true
	return false


## 是否为贴图生成法线图（2D 法线光照）；由 game.gd 按 Cfg.normal_maps 在加载前设置
static var normal_maps := false
## 高清贴图：art/incoming/<name>@2x.png 存在时优先使用，像素密度 2 倍（96px 画 48px 的内容），
## 绘制时倍率减半，锚点 / 判定 / 帧数都不变。_hires 按名字记倍数，_hires_rid 按贴图记倍数。
## 是否启用 @2x 高清贴图。人物以 96px 为标准（art/incoming/squad_2x_handoff.md）：
## 水月、博士与具名编队全员都有 @2x；没有 @2x 的贴图（旧预备干员、敌人）继续用原图。
const USE_HIRES := true
static var _hires := {}
static var _hires_rid := {}
## 干员 1 倍帧条（10-23 用户定「1 倍，整套替换」，docs/128）：art/incoming/<name>@1x.png 存在且 render/op_1x 开着时优先于 @2x，
## 像素密度 1（1 美术像素 = 1 贴图像素，与怪物同密度），锚点 / 帧数 / 判定与 @2x 版相同。由 tools/op_1x/make_op_1x.py 生成：
## 待机 / 跑步 / 普攻 / 移动攻击从原作 Spine 逐部件 1 倍像素化，其余帧条由 @2x 2×2 合并 + 本人调色板
static var _op1x := -1
## 界面立绘读 @2x 精细版（10-23 用户「选人和图鉴放之前的精细版，演示用粗糙版」）：选人 / 图鉴立绘 / 招募卡等界面位
## 用 tex_hi / hi_of 取同名 @2x（op_1x 关或没有 @2x 时同 tex）；局内战斗与图鉴动作演示照旧走 tex（1 倍）
static var _name_rid := {}
static func tex_hi(name: String) -> Texture2D:
	var key := "#hi:" + name
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	if op_1x_on() and _packed_path(name + "@1x") != "":
		var q2 := _packed_path(name + "@2x")
		if q2 != "":
			t = load(q2)
		if t != null:
			_hires_rid[t.get_rid()] = 2.0
	if t == null:
		t = tex(name)
	_cache[key] = t
	return t


## 已载入贴图（tex 取到的）换成同名的界面精细版；不认识的原样返回
static func hi_of(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	var n: String = _name_rid.get(t.get_rid(), "")
	return tex_hi(n) if n != "" else t


static func op_1x_on() -> bool:
	if _op1x < 0:
		var Bal = load("res://scripts/core/balance.gd")
		_op1x = 1 if Bal == null or Bal.v("render/op_1x", 1.0) > 0.0 else 0
	return _op1x == 1
## 不做法线的贴图前缀（地面 / 特效 / UI 图标：做了反而奇怪）
const NO_NORMAL_PREFIX := ["tiles", "terrain_", "fx_", "proj_", "relic_", "growth_", "skill_", "evo_", "weapon_", "light", "shadow", "slash", "title_", "ebullet", "drone_bullet", "drone_laser", "portraits/"]

# ------------------------------------------------------------------ 普通 / 精英怪「祛雾」（用户 10-14「别的几个怪物可以祛雾拉高一点，不要显得雾蒙蒙的」）
## 量过（build/enemy_pop/，tools 口径同 art_lint tone）：Codex 重画的 18 种普通 / 精英怪色板最暗一阶都在 luma 46–59/255（描边除外），
## 近黑 0%、HSL 饱和 0.13–0.49，没有暗部锚点，在暗地面 / 图鉴暗卡上整体发闷；图鉴格子只是原图直贴再乘后期亮度 ×1.05，不是渲染层压暗。
## 所以在**载入贴图时**把漫反射像素烘一遍：黑位下压 black（减掉再拉伸）→ 以中灰 0.5 为轴拉对比 contrast → 饱和度增量 sat，
## 等价于 Image.adjust_bcs(B, C, S)：B = 1/(1+black)，C = contrast×(1+black)/(1−black)，S = 1+sat（原生循环，18 种约 70 条帧条几毫秒）。
## 图鉴格子 / 展示台 / 实机演示 / 局内（图集与原路径）拿到的是同一份像素，逐帧零开销，不进画法缓存签名（docs/50 §9.9）；
## 受击白闪（白剪影只看 alpha）、法线图（只看 alpha）、描边 #080E18（近黑，黑位下压后仍近黑）、精英暖橙标识（高饱和，只更饱和）不受影响。
## 名单 = D.ENEMIES 里非 Boss、非骑士（e_knight）的帧条本体（同 world.build_enemy_atlas 的入集规则），后缀同图集 + Game.ENEMY_SUFFIXES；
## 干员 / 召唤物 / Boss / 特效 / 弹道不在名单。旋钮（balance.json，--bal= 可覆盖）：
##   常开（总开关 render/enemy_pop 10-29 已删；要关就把下面三个旋钮设成 0 / 1 / 0）
##   render/enemy_pop_black  黑位（缺省 0.10）     render/enemy_pop_contrast  对比（缺省 1.35）     render/enemy_pop_sat  饱和度增量（缺省 0.3）
##   档位对照（build/enemy_pop/levels_*.png）：轻 0.06/1.2/0.2 差别太轻；中 0.10/1.35/0.30（缺省）明显去雾、最暗一阶 luma≈12 仍与描边分得开；
##   强 0.14/1.5/0.4 最暗一阶压到 luma≈2 和描边合成一团（塑路者分形 / 奠基者成黑块）
const POP_SUFFIXES := ["", "_feign", "_dormant", "_awaken", "_enraged", "_swell", "_move", "_attack", "_charge", "_death", "_slash", "_reload", "_rooting", "_melee"]
static var _pop_ready := false
static var _pop_names: Dictionary = {}
static var _pop_bcs := Vector3.ZERO   # adjust_bcs 的 (brightness, contrast, saturation)；ZERO = 关
static var pop_ms := 0.0              # 本进程烘像素累计毫秒（--atlasinfo / --loadprof 打印）
static var pop_n := 0


static func _pop_setup() -> void:
	_pop_ready = true
	var Bal = load("res://scripts/core/balance.gd")
	if Bal == null:
		return
	var b: float = clampf(Bal.v("render/enemy_pop_black", 0.08), 0.0, 0.5)
	var k: float = maxf(Bal.v("render/enemy_pop_contrast", 1.28), 0.0)
	var s: float = maxf(Bal.v("render/enemy_pop_sat", 0.25), -1.0)
	if b == 0.0 and k == 1.0 and s == 0.0:
		return
	var D = load("res://scripts/data.gd")
	if D == null:
		return
	for key in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[key]
		if str(d.get("role", "")) == "boss" or d.get("boss", false) or str(d.get("tex", "")) in ["", "e_knight"]:
			continue
		for sfx in POP_SUFFIXES:
			_pop_names[str(d.tex) + sfx] = true
	if _pop_names.is_empty():
		return
	_pop_bcs = Vector3(1.0 / (1.0 + b), k * (1.0 + b) / (1.0 - b), 1.0 + s)


static func pop_wanted(name: String) -> bool:
	if enemy_pixel_spec(name).get("preserve_palette", false):
		return false
	if not _pop_ready:
		_pop_setup()
	return _pop_bcs != Vector3.ZERO and _pop_names.has(name)


## 就地烘：img 会被改（调用方保证是自己的副本）
static func pop_image(img: Image) -> void:
	if img == null or img.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(_pop_bcs.x, _pop_bcs.y, _pop_bcs.z)
	pop_ms += (Time.get_ticks_usec() - t0) / 1000.0
	pop_n += 1


## 包内 / 内置贴图（读回像素再烘）；读不到像素（无头空驱动）原样返回
static func _pop_tex(t: Texture2D) -> Texture2D:
	var img: Image = t.get_image() if t != null else null
	if img == null or img.is_empty():
		return t
	img = img.duplicate()
	pop_image(img)
	return ImageTexture.create_from_image(img)


## 手机网页敌人帧条减半读（10-26，docs/50 §30.8）：e_* 的 @2x 几乎全是 1 倍图整 2 倍放大（401 条里 398 条逐 2×2 块同色，占 208 / 210 MB），
## 读进来缩回 1 倍、密度记 1，屏幕上的大小 / 锚点 / 帧数不变（绘制处都按 hires_of 除），帧条与由它派生的白剪影 / 轮廓显存约省四分之三。
## 缩回再放大和原图对不上的（卡门 / 伊比利亚几条真 2 倍细节）照旧用 @2x。--halfenemy 桌面试；--bal=web/mobile_half_enemy=0 退回
static var _half_e := -1
static var half_n := 0      # 减半读了几条 / 对不上保留 @2x 几条（--memlog 打印）
static var half_keep := 0

static func half_enemy_on() -> bool:
	if _half_e < 0:
		var ml = Engine.get_main_loop()
		var cfg = ml.root.get_node_or_null("/root/Cfg") if ml is SceneTree else null
		if cfg == null:
			return false   # 自动加载还没起（更早的自动加载里取贴图）：先不记结果，等 Cfg 在了再判
		var on: bool = cfg.mobile_web() and cfg.mobile_knob("mobile_half_enemy", 1.0)
		if (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--halfenemy"):
			on = true
		_half_e = 1 if on else 0
	return _half_e == 1


## 整 2 倍放大的图缩回 1 倍（img 会被转成 RGBA8）；不是整 2 倍放大返回 null
static func _halve(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w % 2 != 0 or h % 2 != 0:
		return null
	var half: Image = img.duplicate()
	half.resize(w / 2, h / 2, Image.INTERPOLATE_NEAREST)
	var back: Image = half.duplicate()
	back.resize(w, h, Image.INTERPOLATE_NEAREST)
	if back.get_data() != img.get_data():
		# 包内贴图导入时 fix_alpha_border 会改全透明像素的 RGB（往外渗邻色），逐字节比会全部落空：预乘后再比（全透明像素归零，只比看得见的）
		var pa: Image = img.duplicate()
		pa.premultiply_alpha()
		back.premultiply_alpha()
		if back.get_data() != pa.get_data():
			half_keep += 1
			return null
	half_n += 1
	return half


## 取贴图；找不到返回 null
static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	if late_log:
		var lt0 := Time.get_ticks_usec()
		late_log = false
		var lt: Texture2D = tex(name)
		late_log = true
		print("TEXLATE %s %.1fms" % [name, (Time.get_ticks_usec() - lt0) / 1000.0])
		return lt
	var t: Texture2D = null
	var density := 1.0
	var src_path := ""   # 法线缓存键用：包内资源路径
	var pop := pop_wanted(name)   # 普通 / 精英怪祛雾：贴图读回像素再烘（法线仍按原图 alpha 算）
	if op_1x_on():
		var q1 := _packed_path(name + "@1x")
		if q1 != "":
			t = load(q1)
			if t != null:
				src_path = q1
	var halve := half_enemy_on() and name.begins_with("e_") and not normal_maps
	if USE_HIRES and t == null:
		var q2 := _packed_path(name + "@2x")
		if q2 != "":
			t = load(q2)
			if t != null:
				density = 2.0
				var hi: Image = t.get_image() if halve else null
				var h2: Image = _halve(hi.duplicate()) if hi != null and not hi.is_empty() else null
				if h2 != null:
					if pop:
						pop_image(h2)
					t = ImageTexture.create_from_image(h2)
					density = 1.0
				elif pop:
					t = _pop_tex(t)
				src_path = q2
	if t == null:
		var q := _packed_path(name)
		if q != "":
			t = load(q)
			if t != null and pop:
				t = _pop_tex(t)
			src_path = q
	if t == null and ResourceLoader.exists("res://art/px/%s.png" % name):
		src_path = "res://art/px/%s.png" % name
		t = load(src_path)
		if t != null and pop:
			t = _pop_tex(t)
	if t == null:
		var ph := _placeholder(name)
		if not ph.is_empty():
			t = ph[0]
			density = ph[1]
	if t != null and normal_maps and _wants_normal(name) and src_path != "":
		t = _with_normal(t, name, src_path)
	if t != null:
		_hires[name] = density
		_hires_rid[t.get_rid()] = density
		_name_rid[t.get_rid()] = name
	_cache[name] = t
	return t


## 占位美术（明确标注，等正式帧条交付后删条目）：名字以 key 开头、又找不到正式文件的贴图，取 from 前缀的同名帧条，
## 按 ramp 色阶重新上色（按亮度映射，保留明暗）。只在载入时做一次。
## 目前没有条目（留空备用）。写法：{"op_<id>_": {"from": "op_<借谁>_", "ramp": [[亮度, Color], …]}}；
## 浊心斯卡蒂曾借斯卡蒂帧条改「浊心红」，Codex 正式帧条交付后删掉（docs/64 §5.1）
const PLACEHOLDER := {}


static func _placeholder(name: String) -> Array:
	for pre in PLACEHOLDER:
		if not name.begins_with(pre):
			continue
		var spec: Dictionary = PLACEHOLDER[pre]
		var src: String = spec.from + name.substr(pre.length())
		var st: Texture2D = tex(src)
		if st == null:
			return []
		var img: Image = st.get_image()
		if img == null or img.is_empty():
			return []
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var lut := PackedByteArray()
		lut.resize(256 * 3)
		var ramp: Array = spec.ramp
		for i in 256:
			var l: float = i / 255.0
			var c: Color = ramp[-1][1]
			for k in range(1, ramp.size()):
				if l <= ramp[k][0]:
					c = ramp[k - 1][1].lerp(ramp[k][1], (l - ramp[k - 1][0]) / (ramp[k][0] - ramp[k - 1][0]))
					break
			lut[i * 3] = int(c.r * 255.0)
			lut[i * 3 + 1] = int(c.g * 255.0)
			lut[i * 3 + 2] = int(c.b * 255.0)
		var data: PackedByteArray = img.get_data()
		for i in range(0, data.size(), 4):
			if data[i + 3] == 0:
				continue
			var li: int = (data[i] * 77 + data[i + 1] * 150 + data[i + 2] * 29) >> 8
			data[i] = lut[li * 3]
			data[i + 1] = lut[li * 3 + 1]
			data[i + 2] = lut[li * 3 + 2]
		var out := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
		return [ImageTexture.create_from_image(out), hires(src)]
	return []


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
	var disk := _disk_source(path)
	if disk != "":
		path = disk   # 编辑器里：读源 PNG，键与主线程 _with_normal 算的一致（_normal_key 同样换成源 PNG）
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


## 法线图的原图路径：与 tex() 选图的顺序一致（@1x > @2x > 基础名 > 占位）
static func _normal_source(name: String) -> String:
	var path := ""
	if op_1x_on():
		path = _packed_path(name + "@1x")
	if USE_HIRES and path == "":
		path = _packed_path(name + "@2x")
	if path == "":
		path = _packed_path(name)
	if path == "" and ResourceLoader.exists("res://art/px/%s.png" % name):
		path = "res://art/px/%s.png" % name
	return path


## 缓存键：有源 PNG（编辑器里）按 文件大小_改动时间（图换了就失效）；导出包按尺寸（包是整体替换的）
static func _normal_key(path: String, w: int, h: int) -> String:
	if path == "":
		return ""
	if _disk_source(path) != "":
		path = _disk_source(path)
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
## 降饱和副本（docs/139 §6.6 只给环境去色：地面 / 场景道具；干员、怪物、特效不走这里）：Image.adjust_bcs 原生实现，
## CanvasTexture（带法线）只换漫反射、法线照用；bright = 亮度倍率（去色后补亮）；s = 1 且 bright = 1 时原样返回
static func desat_of(src: Texture2D, s: float, bright := 1.0) -> Texture2D:
	if src == null or (s >= 0.999 and absf(bright - 1.0) < 0.001):
		return src
	var base: Texture2D = src.diffuse_texture if src is CanvasTexture else src
	if base == null:
		return src
	var img := base.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(bright, 1.0, clampf(s, 0.0, 1.0))
	var t := ImageTexture.create_from_image(img)
	_hires_rid[t.get_rid()] = hires_of(base)
	if src is CanvasTexture:
		var ct := CanvasTexture.new()
		ct.diffuse_texture = t
		ct.normal_texture = (src as CanvasTexture).normal_texture
		ct.texture_filter = (src as CanvasTexture).texture_filter
		_hires_rid[ct.get_rid()] = hires_of(src)
		return ct
	return t


## 换色相副本（docs/139 §6.7 敌弹改蓝）：色相落在 [lo, hi]（度，可跨 360）且饱和 > 0.15 的像素改成 hue（度），饱和 / 明度不变，
## 深色描边（色相不在区间）原样；CanvasTexture 只换漫反射
static func hue_to(src: Texture2D, hue: float, lo: float, hi: float) -> Texture2D:
	if src == null:
		return src
	var base: Texture2D = src.diffuse_texture if src is CanvasTexture else src
	var img := base.get_image() if base != null else null
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0 or c.s <= 0.15:
				continue
			var h := c.h * 360.0
			var inside := (h >= lo and h <= hi) if lo <= hi else (h >= lo or h <= hi)
			if inside:
				img.set_pixel(x, y, Color.from_hsv(hue / 360.0, c.s, c.v, c.a))
	var t := ImageTexture.create_from_image(img)
	_hires_rid[t.get_rid()] = hires_of(base)
	if src is CanvasTexture:
		var ct := CanvasTexture.new()
		ct.diffuse_texture = t
		ct.normal_texture = (src as CanvasTexture).normal_texture
		ct.texture_filter = (src as CanvasTexture).texture_filter
		_hires_rid[ct.get_rid()] = hires_of(src)
		return ct
	return t


static var _white_cache := {}   # 原贴图 instance id → 白色剪影（10-21：每建一局都从显存读回重算，图鉴演示每点一次卡 1–2 秒）


## 帧条释放（手机网页 game._enemy_evict）：从缓存里拿掉，贴图在没人引用后释放；再要时 tex() 重新读
static func uncache(name: String) -> void:
	var t = _cache.get(name)
	if t is Texture2D:
		_white_cache.erase(t.get_instance_id())
	_cache.erase(name)


## 白剪影释放（game._white_release）：从缓存里拿掉，贴图在没人引用后释放
static func white_drop(src: Texture2D) -> void:
	if src != null:
		_white_cache.erase(src.get_instance_id())


static func white_of(src: Texture2D) -> Texture2D:
	if src == null:
		return null
	var wk := src.get_instance_id()
	if _white_cache.has(wk):
		return _white_cache[wk]
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	# 按字节直接改（2026-10-11）：以前逐像素 get_pixel / set_pixel，网页版按需加载时一张 Boss 帧条要几十毫秒；
	# 结果与原来逐字节相同（alpha > 0 的像素 RGB 置 255，alpha 不变）
	var data := img.get_data()
	var n := data.size()
	var i := 3
	while i < n:
		if data[i] != 0:
			data[i - 3] = 255
			data[i - 2] = 255
			data[i - 1] = 255
		i += 4
	img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	var w := ImageTexture.create_from_image(img)
	_hires_rid[w.get_rid()] = hires_of(src)
	_white_cache[wk] = w
	return w


## 分帧预载（10-21，图鉴 / 选人 / 封面「演示」首点卡顿）：进界面后每帧按时间预算把一局要用的贴图读进 tex() 缓存、
## 敌人的白色剪影一并算好；法线预热线程没做完时不读（否则主线程当场算法线）。不在标题页启动时跑。
static var _warm_q: Array = []
static var _warm_white := {}
static var _warm_n := 0   # 本轮入队总数（warm_progress）


static func warm_begin(names: Array, white_names: Array) -> void:
	if _warm_q.is_empty():
		_warm_n = 0
	var seen := {}
	for n in _warm_q:
		seen[n] = true
	for n in names + white_names:
		if n is String and n != "" and not seen.has(n) and not _cache.has(n):
			seen[n] = true
			_warm_q.append(n)
			_warm_n += 1
	for n in white_names:
		_warm_white[n] = true


## 分帧预读的进度（进局载入页用）：(已读, 入队总数)；队列读空后再入队时重新计数
static func warm_progress() -> Vector2i:
	return Vector2i(_warm_n - _warm_q.size(), _warm_n)


## 每帧调一次：budget_usec 微秒内尽量多读；返回是否还有剩
static func warm_step(budget_usec: int) -> bool:
	if _warm_q.is_empty():
		return false
	if prewarm_busy():
		return true
	var t0 := Time.get_ticks_usec()
	while not _warm_q.is_empty() and Time.get_ticks_usec() - t0 < budget_usec:
		var n: String = _warm_q.pop_front()
		var w0 := Time.get_ticks_usec()
		var t := tex(n)
		if late_log and Time.get_ticks_usec() - w0 > 20000:
			print("WARMSLOW %s %.1fms" % [n, (Time.get_ticks_usec() - w0) / 1000.0])
		if t != null and _warm_white.has(n) and not n.ends_with("_death"):
			white_of(t)
	return not _warm_q.is_empty()


## 帧条逐帧水平镜像（2026-10-13，docs/84）：干员 json 的 sprites.<kind>.mirror = true 表示这条帧条画反了（朝左），
## 界面（选人 / 图鉴 / 编队像 / HUD 头像 / 标题陪伴）直接贴图、不走翻转变换，用这张镜像过的副本；战斗绘制在翻转标志上处理，不用它。
## 每帧在自己的格子里翻（帧序不变）；按源贴图缓存；读不到像素（无头空驱动）就返回原图
static var _mirror_cache := {}

static func mirror_strip(src: Texture2D, frames: int) -> Texture2D:
	if src == null:
		return null
	var key := "%d:%d" % [src.get_rid().get_id(), frames]
	if _mirror_cache.has(key):
		return _mirror_cache[key]
	var base: Texture2D = src.diffuse_texture if src is CanvasTexture else src
	var img: Image = base.get_image() if base != null else null
	if img == null or img.is_empty():
		return src
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var n: int = maxi(1, frames)
	var fw: int = img.get_width() / n
	var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
	for f in n:
		var fr := img.get_region(Rect2i(f * fw, 0, fw, img.get_height()))
		fr.flip_x()
		out.blit_rect(fr, Rect2i(Vector2i.ZERO, fr.get_size()), Vector2i(f * fw, 0))
	var t := ImageTexture.create_from_image(out)
	_hires_rid[t.get_rid()] = hires_of(src)
	_mirror_cache[key] = t
	return t


# ---------------------------------------------------------------- 数据表（10-15 从 game.gd 搬来，docs/101 S5；game.gd 留同名别名）
## 开局固定预载的贴图（_ready；标题页预热法线图也按这份名单 + preload_tex_names）
const BASE_TEX := ["e_knight_walk", "e_knight_walk_move", "e_knight_walk_attack", "e_knight_walk_charge", "e_knight_walk_death", "drifter", "dart", "crawler", "shell", "boss", "tiles", "seaweed", "coral", "shell_prop", "rock",
			"gem_small", "gem_big", "oil", "chest", "slash", "tentacle", "jelly", "light", "shadow", "player",
			"ally_sniper", "ally_caster", "ally_medic", "ally_support", "orb",
			"e_bone", "e_slider", "e_stone", "e_offspring", "e_brood", "e_pocket", "e_skimmer", "e_mother", "e_chest", "e_mimic", "e_event",
			"e_path", "e_fractal", "e_izumik", "e_ishar", "e_tear", "e_iberia", "e_carmen", "e_bishop", "e_archon", "e_immortal", "e_paranoia", "e_paranoia2", "e_bishop_feign", "e_archon_feign", "e_immortal_feign", "ebullet", "ingot", "merchant", "pickup_magnet", "pickup_heal", "drone", "drone_laser",
			"terrain_patches", "prop_pillar", "prop_wall", "prop_wreck", "terrain_ridge", "terrain_peak", "terrain_mire"]
## 敌人贴图的附加帧条后缀（_ready 按 data/enemies.json 逐个尝试；_slash / _reload / _rooting：Codex V13（卡门 / 伊比利亚 / 伊祖米克））
const ENEMY_SUFFIXES := ["_move", "_attack", "_charge", "_death", "_slash", "_reload", "_rooting", "_melee", "_wound", "_revive", "_skill", "_spin", "_reveal", "_change"]
## 美术交付的特效帧数（见 docs/05_art_handoff.md）
const FXF := {"fx_s1_burst": 6, "fx_s1_slash": 4, "fx_s2_aura": 4, "fx_s2_bind": 4, "fx_s3_aura": 6,
	"fx_s3_slash": 4, "fx_cast": 8, "fx_stun": 4, "fx_hit": 4, "fx_death": 5}

## 美术 V6 帧条：名称 -> [帧数, fps]
const V6_FRAMES := {
	"prop_knight_frost_stake": [4, 4.0], "prop_knight_frost_stake_rise": [3, 12.0], "prop_knight_frost_stake_break": [6, 14.0],
	"fx_knight_ice_wall": [36, 30.0],
	"fx_knight_crystal_rise": [7, 28.0], "fx_knight_crystal_hold": [3, 8.0], "fx_knight_crystal_break": [10, 32.0],
	"fx_knight_ice_crest": [11, 30.0], "proj_knight_ice": [10, 18.0], "fx_knight_ice_hit": [12, 24.0],
	"fx_wisadel_cannon": [4, 12.0],
	"fx_mon3tr_claw": [4, 16.0], "fx_mon3tr_melt_slash": [4, 16.0],
	"proj_arrow": [1, 0.0], "proj_fireball": [4, 12.0], "proj_arcane": [4, 12.0],
	"fx_fire_explode": [6, 15.0], "fx_missile_explode": [6, 15.0], "fx_bullet_hit": [3, 24.0],
	"fx_arcane_hit": [4, 20.0], "fx_heal_cross": [4, 10.0],
	# 美术 V7（docs/13_art_v7_spec.md）：触手 / 水刃 / 触手桩 / 巨触 / 受击 / 击杀
	"fx_tentacle_strike": [6, 16.0],
	"proj_tide_blade_abyss": [4, 12.0],
	"fx_hit_flesh": [4, 20.0], "fx_hit_shell": [4, 20.0], "fx_hit_spirit": [4, 20.0], "fx_death_dissolve": [6, 14.0],
	# 美术 V9：最后的骑士
	"fx_knight_impact": [4, 12.0], "fx_knight_rebirth": [4, 10.0],
	# Boss 招式改版第 1 批特效（docs/95 §13，Codex 单；缺图时 fx_sprite 返回 false、各处走程序版回退）
	"fx_paranoia_gaze_hit": [4, 16.0], "fx_paranoia_stack": [6, 14.0], "fx_paranoia_howl": [6, 12.0], "fx_paranoia_aura_rune": [2, 2.0],
	"fx_ishar_song_ring": [4, 12.0], "fx_ishar_maw_red": [4, 14.0], "fx_ishar_line_muzzle": [3, 16.0],
	"fx_izumik_share": [6, 12.0], "fx_izumik_wave_rim": [4, 12.0], "fx_izumik_lamp_safe": [2, 4.0],
	"fx_knight_frost_burst": [5, 14.0], "fx_knight_frost_floor": [2, 2.0], "fx_knight_thrust": [3, 16.0],
	"fx_saint_shell_burst": [6, 14.0],
	# 第 2 批（docs/95 §5.4 / §6.4 / §7.4；帧条 e_path_slam / e_saint_dark_lob / e_carmen_spin 由 world.boss_strip_animation 按帧数取，不在这里登记）
	"fx_path_fractal_rise": [5, 12.0], "fx_path_correct_ring": [4, 12.0], "fx_path_reflow": [3, 12.0],
	"proj_saint_shell": [2, 8.0], "fx_saint_scatter": [3, 16.0], "fx_saint_clear_ring": [4, 12.0], "fx_carmen_smash": [4, 14.0],
	# 第 3 批（docs/95 §8.4 / §9.4 / §10.4；帧条 e_bishop_attack / e_archon_attack / e_immortal_attack 在 world.boss_strip_animation）
	"fx_bishop_wave": [6, 12.0], "fx_tide_link_tile": [4, 12.0], "fx_archon_breath": [5, 14.0], "fx_immortal_burst": [5, 16.0],
	# 第三方开放许可素材魔改（tools/fx_import.py，docs/25 §3）：圣光 / 治疗 / 火 / 爪 / 斩 / 碎石 / 弹道
	"fx_holy_pillar": [16, 14.0], "fx_holy_pillar_amber": [16, 14.0], "fx_holy_impact": [7, 16.0],
	"fx_heal_aura_green": [5, 10.0], "fx_heal_aura_amber": [5, 10.0], "fx_circle_gold": [4, 8.0], "fx_circle_amber": [4, 8.0], "fx_shield_amber": [6, 12.0],
	"fx_flam_hit": [8, 14.0], "fx_sunburst": [16, 16.0], "proj_lavaball": [6, 12.0],
	"fx_claw_double_green": [5, 16.0], "fx_felspell": [17, 16.0], "fx_logos_s2": [17, 16.0],
	"fx_slash_arc_deep": [6, 18.0], "fx_slash_heavy_deep": [5, 16.0], "fx_water_splash": [11, 14.0],
	"fx_rock_burst": [14, 14.0], "fx_rock_spike": [10, 14.0], "proj_foxfire": [6, 12.0],
	# 第二批干员的重调色变体（tools/fx_recolor.py，帧数 / fps 与源相同）
	"fx_slash_arc_rose": [6, 18.0], "fx_slash_heavy_rose": [5, 16.0],
	"fx_slash_heavy_steel": [5, 16.0], "fx_circle_steel": [4, 8.0],
	"fx_circle_ghost": [4, 8.0],
	"fx_ink_hit": [8, 14.0], "fx_holy_pillar_ink": [16, 14.0], "fx_circle_ink": [4, 8.0],
	"proj_lumen_bolt": [6, 12.0], "fx_holy_impact_lantern": [7, 16.0],
	# ansimuz 爆炸与魔法合集（tools/fx_import.py 'dir' 模式，2026-09-26）
	# docs/54 §6 事件特效帧条（tools/gen_fx_strips.py，程序生成；有图用图、没图走原程序画法）
	"fx_beacon_ignite": [8, 16.0], "fx_ember": [4, 8.0], "fx_mire_dissolve": [6, 8.0], "fx_levelup_pillar": [6, 12.0], "fx_elite_spawn": [6, 6.7],
	"fx_splash_blue": [9, 18.0],
	"fx_thrust_hit_rose": [5, 20.0], "fx_star_hit_rose": [7, 20.0], "fx_cannon_burst": [10, 20.0], "fx_muzzle_flash": [7, 28.0],
	# Codex fx30（docs/30，双密度 @2x）：帧数 / fps 按 art/incoming/fx30_handoff.md；钙质晶体放慢到 10fps 以延长停留
	"proj_ulpianus_anchor": [2, 10.0], "fx_irene_thrust": [5, 25.0], "fx_specter_saw": [6, 24.0], "fx_specter_saw_blood": [6, 24.0],
	"fx_mizuki_s3_field": [6, 20.0], "fx_mizuki_tentacle": [6, 15.0], "fx_mizuki_tentacle_mass": [6, 15.0], "fx_suzuran_foxfire_gather": [6, 24.0],
	"fx_logos_glyph": [6, 18.0], "fx_logos_script": [4, 12.0], "fx_saria_shield_bash": [5, 20.0], "fx_saria_calcite": [8, 10.0],
	# Codex 逻各斯实机参考特效（art/incoming/logos_fx_handoff.md）
	"fx_logos_s3_orbit": [6, 10.0], "fx_logos_s3_back": [6, 10.0], "fx_logos_s3_front": [6, 10.0],
	"fx_logos_s1_link": [4, 12.0], "proj_logos_ink": [4, 12.0],
	"fx_logos_s1_chain": [4, 12.0],
	"fx_logos_s3_fan_ground": [4, 6.0], "fx_logos_s3_fan_open": [8, 16.0], "fx_logos_s3_fan_close": [6, 16.0], "fx_logos_s3_ribbon": [8, 8.0], "fx_logos_s3_slow": [4, 12.0],   # 延异视阈扇形咒域（docs/192，缺图回退程序画法）
	"proj_logos_ink_a": [4, 16.0], "proj_logos_ink_b": [4, 16.0],
	# 艾雅法拉 S2 点燃：彗星火球 + 大团熔岩爆炸（ansimuz，fx_import）
	"proj_eyja_ignite": [5, 14.0], "fx_eyja_ignite_boom": [11, 18.0], "fx_eyja_ignite_hit": [9, 21.0],
	# 第三批干员（docs/59）弹体 / 特效帧条（tools/gen_fx_batch3.py，程序生成 + @2x；锚点见 docs/25 §6）。暂未接玩法，数据干员实现时取用
	"proj_exusiai_bullet": [2, 20.0], "proj_exusiai_bullet_power": [2, 20.0], "fx_exusiai_muzzle": [3, 30.0], "fx_exusiai_muzzle_gold": [3, 30.0], "fx_exusiai_hit": [3, 24.0],
	# 能天使技能弹药换色（docs/25 §6.1，gen_fx_batch3.py EXU_VARIANTS）：S1 冰青 / S2 琥珀橙 / S3 过热白；倾泻补金色命中
	"proj_exusiai_bullet_s1": [2, 20.0], "proj_exusiai_bullet_s2": [2, 20.0], "proj_exusiai_bullet_s3": [2, 20.0],
	"fx_exusiai_muzzle_s1": [3, 30.0], "fx_exusiai_muzzle_s2": [3, 30.0], "fx_exusiai_muzzle_s3": [3, 30.0],
	"fx_exusiai_hit_s1": [3, 24.0], "fx_exusiai_hit_s2": [3, 24.0], "fx_exusiai_hit_s3": [3, 24.0], "fx_exusiai_hit_gold": [3, 24.0],
	"proj_angelina_orb": [4, 12.0], "fx_angelina_pull": [6, 15.0], "fx_angelina_levitate": [6, 10.0],
	"fx_skalter_wave": [6, 12.0], "fx_skalter_wave_dim": [6, 12.0], "fx_skalter_note": [4, 8.0],
	# 预留：Codex 原尺寸大声浪（docs/61 §5.6 扩散缓动、§10 第 17 条；还没交图，缺图时 skalter.json 回退到上面的小帧条 + 程序余波环）：
	# 8 帧 12fps（≈ 扩散 0.65 秒），1x 帧 208×120、圈心 = 帧中心，末帧外圈半径约 95（= 歌域 190 / 2 世界像素）；明 / 暗两套共用规格
	"fx_skalter_wave_big": [8, 12.0], "fx_skalter_wave_big_dim": [8, 12.0],
	# Codex 浊心斯卡蒂 S3 重绘（art/incoming/skalter_s3_handoff.md，ec06672e）：贴身绕行潮流，back / front 分层夹住本体，原点脚下 (48, 84)；orbit 是不分层预览 / 回退，不接
	# Codex 浊心斯卡蒂 S3 地面大漩涡（docs/66，art/incoming/skalter_vortex_handoff.md，b49d0047）：320×176 × 8 帧 10fps 循环，原点 (160, 88) = 帧中心；
	# 1x 像素 = 歌域外半径 / 160（fit 160），地面 ground 层、整体透明度 0.5、进出 0.45 秒淡入淡出（skalter.json S3 verb.mode 的 hold 条目）
	"fx_skalter_vortex_floor": [8, 10.0],
	"fx_hoshiguma_block": [5, 20.0], "fx_hoshiguma_sand": [4, 8.0], "fx_hoshiguma_demon_slash": [5, 20.0],
	"fx_texas_dash": [4, 20.0],
	# 德克萨斯剑雨（10-12 重做，docs/70，verb.fx_rain docs/61 §13.5）：剑 16×40（0–1 下落循环 / 2–5 插地按停留时间铺开，锚 (8, 38)）、冲击 32×24（锚 (16, 20)）、地面标记 24×12（0–2 预兆 / 3–5 焦痕，锚帧中心）
	# 终结技第一批 5 人（Codex 交付 codex/art 9d57cf262，art/incoming/ult_batch1_1029/manifest.json；docs/198 §8 / docs/199）
	"fx_ult_texas_slash_front": [8, 24.0], "fx_ult_texas_scar_back": [4, 10.0], "fx_ult_texas_sword_front": [6, 20.0],
	"fx_ult_exusiai_burst_front": [6, 30.0], "fx_ult_exusiai_lock_orbit": [8, 24.0],
	"fx_ult_skalter_seaborn_front": [10, 12.0], "fx_ult_skalter_seaborn_back": [6, 12.0], "fx_ult_skalter_beam_front": [6, 24.0], "fx_ult_skalter_domain_back": [6, 10.0],
	"fx_ult_kaltsit_melt_front": [8, 24.0], "fx_ult_kaltsit_crack_back": [6, 20.0], "fx_ult_kaltsit_rebuild_orbit": [12, 16.0],
	"fx_ult_ulpianus_anchor_front": [4, 0.0], "fx_ult_ulpianus_chain_front": [2, 12.0], "fx_ult_ulpianus_crack_back": [6, 20.0], "fx_ult_ulpianus_burst_front": [8, 20.0],
	"fx_ul_crack_line": [1, 0.0], "fx_ul_rock": [4, 0.0], "fx_ul_dust_ring": [1, 0.0], "fx_ul_crack_fork": [1, 0.0], "fx_ul_dust_wall": [1, 0.0], "fx_sk_beam": [1, 0.0], "fx_sk_blast": [1, 0.0], "fx_sk_flash": [1, 0.0], "fx_sg_shock": [1, 0.0], "fx_gl_vortex": [1, 0.0], "fx_px_burst1": [8, 9.0], "fx_px_burst2": [8, 9.0], "fx_px_burst_s": [8, 9.0], "fx_mz_tent": [1, 0.0], "fx_hs_crack": [1, 0.0], "fx_hs_ring": [1, 0.0], "fx_ws_crater": [4, 0.0], "fx_wd_cannon": [4, 12.0], "fx_ey_rock": [2, 0.0], "fx_ey_pool": [1, 0.0], "fx_ey_steam": [1, 0.0], "fx_ey_bomb": [1, 0.0], "fx_ey_pumice": [4, 0.0], "fx_ey_fount": [1, 0.0], "fx_sa_funnel1": [1, 0.0], "fx_sa_funnel2": [1, 0.0], "fx_sa_air": [1, 0.0], "fx_dust_seq": [7, 10.0], "fx_ey_fork1": [1, 0.0], "fx_ey_fork2": [1, 0.0], "fx_ey_fork3": [1, 0.0], "fx_ey_fork4": [1, 0.0], "fx_an_core": [1, 0.0], "fx_an_crater": [1, 0.0], "fx_ul_crack_fork2": [1, 0.0], "fx_ul_crack_fork3": [1, 0.0], "fx_ul_crack_fork4": [1, 0.0], "fx_ul_rock2": [4, 0.0], "fx_sg_shock2": [1, 0.0], "fx_sg_shock3": [1, 0.0], "fx_sg_fork1": [1, 0.0], "fx_sg_fork2": [1, 0.0], "fx_sg_fork3": [1, 0.0], "fx_sg_fork4": [1, 0.0],   # pixfx 大贴图：乌尔比安裂地 / 浊心斯卡蒂吐息 / 凯尔希爆点（docs/199 §7.6–7.7）
	# 终结技第二批 15 人 + 忍冬（Codex 单 art/incoming/ult_batch2_1029/codex_order.md；素材未到，先登记帧数 / fps：PNG 放进 game/art/fx/ 即可被 u.strip / u.fx_ready 取到，
	# 到货时以 manifest 为准改这里；接入步骤见 docs/199「待合入清单」）
	"fx_ult_skadi_wave_front": [8, 16.0], "fx_ult_skadi_foam_front": [6, 20.0], "fx_ult_skadi_wet_back": [4, 10.0],
	"fx_ult_gladiia_vortex_back": [6, 16.0], "fx_ult_gladiia_burst_front": [8, 20.0],
	"fx_ult_angelina_core_front": [8, 16.0], "fx_ult_angelina_dust_back": [6, 20.0],
	"fx_ult_eyja_pillar_front": [8, 16.0], "fx_ult_eyja_rock_front": [6, 20.0], "fx_ult_eyja_lava_back": [4, 8.0],
	"fx_ult_wisadel_blast_front": [8, 20.0], "fx_ult_wisadel_quake_back": [6, 20.0],
	"fx_ult_specter_saw_orbit": [4, 24.0], "fx_ult_specter_spark_front": [6, 30.0],
	"fx_ult_mizuki_burrow_back": [6, 16.0], "fx_ult_mizuki_limb_front": [4, 12.0], "fx_ult_mizuki_tip_front": [6, 16.0], "fx_ult_mizuki_small_front": [8, 16.0],
	"fx_ult_saria_punch_front": [6, 24.0], "fx_ult_saria_shock_front": [6, 20.0], "fx_ult_saria_amber_front": [8, 16.0],
	"op_vulpis_appear_front": [6, 16.0], "fx_ult_vulpis_light_front": [4, 24.0], "fx_ult_vulpis_slash_front": [8, 20.0],
	"op_vulpis_walk": [8, 10.0], "op_vulpis_slash": [8, 0.0],   # 忍冬本体（Spine 自产，docs/207 §6.3）：铃兰终结技走路进场 + 拔刀斩（斩帧由 ult_fx_c 逐帧指定）
	"fx_ult_logos_field_back": [6, 12.0], "fx_ult_logos_glyph_orbit": [8, 20.0], "fx_ult_logos_ash_front": [6, 16.0],
	"fx_ult_hoshiguma_shield_front": [10, 16.0], "fx_ult_hoshiguma_crack_back": [6, 20.0],
	"fx_ult_siege_impact_front": [8, 20.0], "fx_ult_siege_rubble_front": [8, 20.0], "fx_ult_siege_shock_back": [6, 20.0],
	"fx_ult_irene_gale_back": [6, 20.0], "fx_ult_irene_slash_front": [6, 24.0], "fx_ult_irene_shell_front": [8, 20.0],
	"fx_ult_lappland_blade_front": [6, 24.0], "fx_ult_lappland_silence_orbit": [6, 12.0],
	"fx_ult_lumen_beam_front": [8, 16.0], "fx_ult_lumen_ring_back": [6, 20.0],
	"fx_texas_blade": [6, 20.0], "fx_texas_rain_mark": [6, 12.0],
	# Codex 精英化第 1 批（docs/93 §1，art/incoming/elite_art_1_manifest.json；接入见 docs/91 第 1 批）：帧数 / fps 按 manifest，原点写在各干员 JSON 的 anchor。
	# fx_hoshiguma_slash_rose / fx_exusiai_pierce_gold 是 Codex 这批交来时覆盖了已有的 fx_slash_heavy_rose（艾丽妮用）/ fx_exusiai_hit_gold（倾泻用），
	# 规格不同（4 帧 35×34 / 5 帧 24×24），改名成本批专用，原文件恢复原样
	"fx_angelina_halt": [5, 14.0], "fx_angelina_well_back": [8, 10.0], "fx_angelina_well_front": [8, 10.0], "fx_angelina_well_open": [5, 14.0],
	"fx_angelina_well_close": [5, 14.0], "fx_angelina_float_dust": [4, 8.0],
	"proj_exusiai_bullet_t1": [2, 20.0], "proj_exusiai_bullet_t2": [2, 20.0], "proj_exusiai_bullet_t3": [2, 20.0], "fx_exusiai_pierce_gold": [5, 20.0],
	"fx_exusiai_halo": [8, 10.0], "fx_exusiai_blessed_flash": [4, 20.0],
	"fx_hoshiguma_slash_rose": [4, 20.0], "fx_hoshiguma_guard_glow": [6, 10.0], "proj_hoshiguma_sawshield": [8, 24.0], "fx_hoshiguma_saw_spark": [4, 20.0],
	"fx_mon3tr_slam_ring": [6, 16.0],
	"fx_texas_pin_sword": [4, 12.0], "fx_texas_pin_shatter": [5, 18.0], "fx_texas_sword_drop": [5, 20.0],
	# 手写干员迁积木（docs/61 §17）：斯卡蒂成长线帧条原来由 skadi.gd 自己按帧切，积木的 fx 条目要登记在这里（帧数 / fps 同原脚本）
	"fx_skadi_surge": [6, 14.0], "fx_skadi_wave": [6, 14.0],
	# Codex 精英化第 2 批（docs/93 §2，art/incoming/elite_art_2_manifest.json；接入见 docs/91 §24）：帧数 / fps 按 manifest，原点写在各干员 JSON 的 anchor（缺省帧中心）。
	# 人物帧条 op_skadi_leap_strike / op_ulpianus_throw 登记在各干员 JSON 的 sprites（leap_strike / throw）
	"fx_logos_soul_rune_1": [4, 8.0], "fx_logos_soul_rune_2": [4, 8.0], "fx_logos_soul_rune_3": [4, 8.0],
	"fx_logos_chain_tile": [6, 12.0], "fx_logos_chain_pulse": [4, 20.0], "fx_logos_chain_anchor": [6, 12.0],
	"fx_eyja_melt_crack": [6, 8.0], "proj_eyja_lava_lob": [4, 16.0], "fx_eyja_lava_pool": [8, 10.0], "fx_eyja_lava_splash": [6, 18.0],
	"fx_skadi_leap_splash": [6, 18.0], "proj_skadi_surge_blade": [4, 16.0], "fx_skadi_surge_hit": [5, 18.0], "fx_skadi_surge_release": [4, 18.0],
	# 拉普兰德 / 歌蕾蒂娅（Codex 199d7b73 + skill_completion，docs/122 / 123 §6）：刀光、剑气弹体、倒钩头、到位冲击、牵引水带、水龙卷 open / loop / close
	"fx_lappland_slash": [4, 10.0], "proj_lappland_sword": [4, 16.0], "proj_gladiia_hook": [4, 16.0], "fx_gladiia_ram": [6, 18.0], "fx_gladiia_pull": [4, 10.0],
	"fx_gladiia_tornado_open": [6, 20.0], "fx_gladiia_tornado_loop": [6, 12.0], "fx_gladiia_tornado_close": [6, 15.0], "fx_gladiia_water_glide": [4, 10.0],
	"fx_ulpianus_chain_tile": [2, 12.0],
	"fx_ulpianus_drag_dust": [4, 14.0],
	# Codex 精英化第 3 批（docs/93 §3，art/incoming/elite_art_3_manifest.json；接入见 docs/91 §25）：帧数 / fps 按 manifest。
	# 人物帧条 op_specter_unchained_doll_spin / op_irene_finisher 登记在各干员 JSON 的 sprites（doll_spin / finisher）
	"fx_specter_inward_ripple": [6, 18.0], "fx_specter_doll_appear": [5, 18.0], "fx_specter_doll_burst": [6, 18.0],
	"fx_mizuki_tentacle_curl": [4, 14.0], "fx_mizuki_jelly_dart": [6, 14.0], "fx_mizuki_jelly_sting": [5, 18.0], "fx_mizuki_bind_ring": [6, 10.0],
	"fx_irene_lift_arc": [4, 20.0], "fx_irene_crescent_wide": [5, 20.0], "fx_irene_gun_burst": [3, 24.0],
	"fx_lumen_refract_hit": [4, 20.0], "fx_lumen_beam": [4, 20.0], "fx_lumen_beam_flare": [5, 20.0], "fx_lumen_beam_hit": [4, 20.0],
	# Codex 精英化第 4 批（docs/93 §4，art/incoming/elite_art_4_manifest.json；接入见 docs/91 §26）：帧数 / fps 按 manifest。
	# 重画的 fx_wisadel_soul / fx_wisadel_mark（9140fe7b，尺寸帧数同原文件）照原规格切帧，不在这里登记
	"fx_siege_pebbles": [6, 16.0], "fx_siege_rock_spike": [7, 18.0], "fx_siege_fissure_tile": [4, 12.0],
	"fx_suzuran_seal": [6, 10.0], "fx_suzuran_bigfox_trail": [5, 12.0],
	"fx_wisadel_gift_mark": [6, 10.0], "op_wisadel_soul_native_die": [12, 12.0], "proj_wisadel_soul_shell": [2, 20.0],
	"fx_saria_amber_spot": [4, 8.0], "fx_saria_pillar_rise": [5, 20.0], "fx_saria_pillar_idle": [4, 6.0], "fx_saria_pillar_break": [6, 18.0],
	# Codex 精英化第 5 批（docs/93 §5，art/incoming/elite_art_5_manifest.json；接入见 docs/91 §27）：浊心斯卡蒂余音回声环、海嗣小歌域。
	# 海嗣本体帧条 op_skalter_ishar_* 是人物帧条，登记在 skalter.json sprites（extra_sprites）
	"fx_skalter_echo_ring": [5, 14.0], "fx_skalter_seaborn_zone": [8, 10.0],
	# 美术 V8 新敌人（art/incoming/enemy_v8_handoff.md）：本体 / 移动 / 攻击按 enemies.json 的 tex 自动加载，这里登记附加帧条
	"e_reaper_dormant": [4, 3.0], "e_reaper_awaken": [6, 10.0], "e_tracer_enraged": [2, 5.0], "proj_floater_nerve": [4, 12.0], "proj_knight_spear": [2, 12.0], "prop_ice_stake": [2, 4.0], "prop_ice_stake_break": [4, 12.0], "prop_ice_pillar": [4, 4.0], "prop_ice_pillar_rise": [3, 12.0], "prop_ice_pillar_break": [6, 14.0], "prop_lamp_post": [3, 4.0], "proj_rock_shard": [4, 12.0], "proj_acid": [2, 8.0], "proj_nova": [4, 10.0], "fx_acid_splash": [4, 12.0],
	# Codex 怪物攻击特效第 1 批（docs/96 §1.1）投嗣育母：投出的拟嗣弹体（缺图时用 e_brood 帧缩小旋转）/ 出手（缺图时无）/ 落地孵化（缺图时 fx_acid_splash + 拟嗣直接出现）
	"proj_mother_brood": [4, 12.0], "fx_mother_throw": [4, 16.0], "fx_brood_land": [6, 14.0],
	# Codex 怪物攻击特效第 1 批（docs/96 §1.2–1.4，art/incoming/enemy_fx_1_manifest.json）：帧数 / fps 按 manifest；
	# 漂移体侵蚀弹 + 发射口 + 命中（蓝）/ 侵蚀变体（紫蓝，喷吐者酸弹命中用）；囊海爬行者鼓胀帧条（10fps 不循环、停末帧）+ 破膜 back / front（同原点 (24,28)）+ 地面残留；
	# 喷吐者酸团（沿 lob 轨迹）+ 落点溅射（地面层）。enemies.json 的 shot_tex / muzzle_fx / hit_fx / lob_tex / land_fx 引用；缺图回退原程序画法
	"proj_skimmer_corrode": [4, 16.0], "fx_skimmer_muzzle": [3, 20.0], "fx_corrode_hit": [5, 18.0], "fx_corrode_hit_acid": [5, 18.0],
	"e_pocket_swell": [4, 10.0], "fx_pocket_burst_back": [6, 16.0], "fx_pocket_burst_front": [6, 16.0], "fx_pocket_puddle": [4, 8.0],
	"proj_spitter_acid": [4, 12.0], "fx_spitter_land": [6, 14.0],
	# 第 2 批（docs/96 §2，Codex 未交，先登记）：飘航者神经弹命中；收割者镰肢 / 引痕者触须刺击（含狂暴版）/ 巢涌者触须横扫（enemies.json atk_fx，boss_ai._atk_fx 挂点）
	"fx_nerve_hit": [4, 18.0], "fx_reaper_scythe": [4, 18.0], "fx_tracer_thrust": [4, 20.0], "fx_tracer_thrust_enraged": [4, 24.0], "fx_nest_sweep": [5, 16.0],
	# 第 3 批（docs/96 §3，Codex 未交，先登记；fps 本单没写的按同类取）：凿石者碎石命中、箱形恐鱼咬合（enemies.json atk_fx，telegraph._atk_fx）、子代孢子弹（shot_tex）、狂奔者自爆（blast_fx）、滑动者冲刺水痕（dash_fx，地面层）
	"fx_rock_hit": [4, 16.0], "fx_mimic_bite": [4, 20.0], "proj_offspring_spore": [4, 12.0], "fx_runner_blast": [6, 16.0], "fx_slider_dash": [4, 12.0],
	# >>> enemy_redraw 死亡帧条（tools/install_enemy_redraw.py 生成，别手改）
	"e_archon_death": [8, 8.0], "e_bishop_death": [8, 5.7], "e_bone_death": [6, 6.0], "e_brood_death": [6, 10.0],
	"e_floater_death": [6, 5.0], "e_founder_death": [6, 6.0], "e_fractal_death": [6, 4.5], "e_immortal_death": [8, 8.0],
	"e_ishar_death": [8, 8.0], "e_ishar_t_death": [8, 8.0], "e_izumik_death": [8, 3.7], "e_knight_death": [4, 3.1],
	"e_knight_walk_death": [4, 6.0], "e_mimic_death": [8, 8.0], "e_mother_death": [8, 7.1], "e_nest_death": [6, 5.1],
	"e_offspring_death": [6, 6.0], "e_paranoia_death": [8, 8.0], "e_paranoia_phase2_death": [8, 8.0], "e_path_death": [8, 4.4],
	"e_pocket_death": [8, 8.0], "e_reaper_death": [6, 6.0], "e_runner_death": [6, 6.0], "e_saint_dark_death": [8, 3.4],
	"e_saint_death": [8, 3.4], "e_skimmer_death": [8, 8.0], "e_slider_death": [6, 3.6], "e_spitter_death": [6, 4.7],
	"e_stone_death": [6, 6.0], "e_tear_death": [6, 7.5], "e_tracer_death": [6, 6.0],
	# <<< enemy_redraw
}
