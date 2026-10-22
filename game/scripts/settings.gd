extends Node

## 界面大小 / 战斗画面缩放改了（设置页实时生效）：game.gd / title.gd / 设置面板重排界面层、改镜头
signal view_changed
## 全局设置（自动加载为 Cfg），保存在 user://settings.cfg

const PATH := "user://settings.cfg"
const D = preload("res://scripts/data.gd")
const Look = preload("res://scripts/render/look.gd")
const TouchLayout = preload("res://scripts/touch_layout.gd")
const CloudPack = preload("res://scripts/core/cloud_pack.gd")
## 存档里难度字段的含义：1 = 旧版累计档位 0–10；2 = 1.1 起的三档下标；3 = 10-22 的潮位 0–15（只在内部包短暂存在）；
## 4 = 10-22 起的三档预设下标（D.DIFF_PRESETS：常规 / 高压 / 深潮 = 潮位 0 / 5 / 10）
const DIFF_VER := 4
## 存档里亮度字段的口径：0 = 旧缺省 110%；1 = 缺省随观感预设 render/look（10-12 起 100%）
const LOOK_VER := 1

var master := 1.0
var music := 0.8
var sfx := 0.9
var voice := 0.8        # 干员语音（Voice 总线）
var fullscreen := false
var max_fps := 60          # 最高帧率 60 / 30（10-22，设置「画面」）：只限渲染帧（Engine.max_fps；网页端 Godot 在 requestAnimationFrame 回调里按它跳帧），逻辑仍按 PlayClock 固定步长
const MAX_FPS_OPTS := [60, 30]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]   # 都是 1280×720 的整数倍，像素对齐
var res_index := 0        # 窗口分辨率（RESOLUTIONS 下标；全屏时按屏幕）
var dmg_numbers := true
var hitstop := true
var boss_intro := true   # Boss 登场演出（黑边 + 名片，纯画面；screens/boss_intro.gd，用户 10-10）
var reduce_motion := false   # 减少动态效果（docs/58 §9 / §11）：界面位移 / 缩放 / 扫入 / 浪幕直接到终态，只留 ≤ 120 ms 淡入淡出
var outline := true      # Boss 轮廓光（10-13 起普通怪 / 精英不画描边，docs/50 §12 A；部件另有自己的描边）
var dof := true          # 2.5D 景深与前景
var bloom := true        # 辉光
var water_filter := true # 水下滤镜：色差 + 暗角 + 焦散
var normal_maps := true  # 2D 法线光照（贴图加载时生成，改动下局生效）
var brightness := 1.1    # 画面亮度 0.8 ~ 1.4（缺省值随观感预设 render/look，_ready 里设）
var pad_rumble := true   # 手柄震动
var quality := ""        # 生效中的画质档 "high" / "mid" / "low"（由 quality_mode 决定）：中 = 关法线光照 / 辉光；低 = 四项后期全关（再关景深 / 水下滤镜）+ 粒子减半、真人局同屏敌人上限 300、演出简化
var quality_mode := "auto"   # 玩家选的画质档：auto / low / mid / high（10-22 用户：设置精简 + 画质自动档，Codex 界面单 §4）
var quality_probed := false  # 自动档：本次启动的首局已测过前 2 秒帧时（每次启动只测一次）
const QUALITY_NAME := {"low": "低", "mid": "中", "high": "高"}
const QUALITY_MODES := ["auto", "low", "mid", "high"]
## 界面大小（设置 → 画面，用户 10-13「手机横屏太拥挤」）：在设备缺省的界面放大倍数（ui_scale）上再乘 ui_size_pct / 100，80–120，步长 5
var ui_size_pct := 100
const UI_PCT_MIN := 80
const UI_PCT_MAX := 120
## 战斗画面缩放（设置 → 画面，用户 10-13「手机横屏战斗画面放大一点」；同日「只能放大不能缩小」→ 下限 100 改 80）：
## 镜头 zoom 百分比 80–140（< 100 = 拉远、看得更多）；-1 = 按设备缺省（手机横屏 120，其余 100）
var cam_zoom_pct := -1
const ZOOM_PCT_MIN := 80
const ZOOM_PCT_MAX := 140
const ZOOM_PHONE_DEF := 120
## 手机横屏的界面放大缺省（原 1.3 → 1.15，界面整体收到约 88%）；平板 / 16:9 触屏仍按宽度 1.0–1.3
const UI_K_PHONE := 1.15
## 界面逻辑高度下限：界面大小调到 120% 时也不低于手机版式设计高度（原手机 481）
const UI_MIN_H := 470.0
## 触屏按键布局（设置 → 游戏 → 触屏按键布局，用户 10-13）：{键: {ax, ay, x, y, s}}，空 = 全部缺省（touch_layout.gd）
var touch_layout := {}
var manual_attack := false   # 主控普通攻击手动（契约 v2.5，docs/26）：开局读一次；机器人 / 自动测试 / 图鉴演示一律自动
var difficulty := 0      # 上次选的难度档（D.DIFF_PRESETS 下标）
var character_id := "mizuki"  # 本局角色（data/characters/<id>.json）
var cover_character_id := "mizuki"
var play_speed := 1.0
var boss_trial_request := {} # transient, never saved
var practice_active := false
var map_id := "deep_sea"  # 本局地图主题（data/maps/<id>.json）
var diff_unlocked := 0   # 已解锁的最高难度档（D.DIFF_PRESETS 下标）
var diff_best := {}      # 各档最佳成绩 {"0": {"wins": 通关次数, "best_t": 最长探索秒数, "fast_t": 最快通关秒数}}（docs/109 §15）
var seen_shows: Array = []   # 已看过的解锁演出
var gallery_seen: Array = []
var seen_relics: Array = []  # 获得过的藏品 id（图鉴用）
var seen_intro := false      # 已看过开局指南
var endings_cleared: Array = []   # 已达成的结局 id（通关结局一后才出现其余结局的事件）
# 干员解锁（局外成长 P1，docs/109 §12，core/roster.gd）：存档 [roster] 段。开局 5 人不存（Roster.STARTERS）
var roster_unlocked: Array = []   # 解锁过的干员 id（不含开局 5 人）
var roster_tickets := {}          # 待用的券 {"hunt": 寻访凭证, "cls": 招募券, "pick": 人事调度函}
var roster_spare := {}            # 名册已满后多出来的券（P2 换生机细胞）
var roster_tiers: Array = []      # 已首通的难度档（发过人事调度函的）
var roster_wish := ""             # 意向干员（寻访保底对象）
var roster_pity := 0              # 意向保底计数：连续没出意向的寻访次数
var roster_draws := 0             # 已用券总数（抽取随机数的种子之一）
var roster_seed := 0              # 名册抽取的种子（第一次抽取时生成，不碰局内 g.rng）
var meta_shape := {}              # 认知塑造已点的节点 {id: true}（core/meta.gd，docs/109 §4；存档 [meta] 段）
var meta_shape_t := 0             # 认知塑造最后修改时刻（云存档合并：较新的一份为准）
var meta_earned := {}             # 累计获得的生机细胞 {设备号: 数量}（云存档逐设备取大再求和）
var meta_dev := ""                # 本机设备号（第一次记生机细胞时生成）
var meta_bounty: Array = []       # 已领首通赏金的潮位
var roster_fresh: Array = []      # 刚解锁、还没在名册里看过的干员（选人页 / 图鉴高亮一次；只存本机，不上云）
var roster_int_grant := false     # 对内包的测试寻访凭证已发过（INTERNAL_TICKETS，每份存档一次）
## 对内包（用户 10-22：要在对内包里测寻访）：名册不全部解锁，按新玩家开局 5 人；每份存档首次启动发这么多张寻访凭证
const INTERNAL_TICKETS := 20
var unlock_all := false      # 本次运行全部解锁（只在内存里，见 _apply_unlock_all）：调试版与对内打包版为 true，对外包恒为 false
var _real_progress := {}      # 全部解锁时存档里真实的进度字段，save() 原样写回
var title_seen := false      # 本次运行已播过标题开场动画（仅内存；对局返回标题不重播）
var opening_seen := false    # 看过完整的标题开场（写入存档）：之后启动只播简短版（2026-09-27 用户定，开场方案 A）
## B站 Toy 云存档（docs/89，cloud_save.gd）：设置最后修改时刻（Unix 秒，合并时设置取较新的一份）、上次与云端一致时的正文签名、
## 设置部分的签名（save() 时比对，变了才更新 cloud_set_t）。存在 settings.cfg 的 [cloud]
var cloud_set_t := 0
var cloud_sig := ""
var _set_sig := ""
## 云端存档里本版不认识的字段（新版本加的），{"top", "set", "d", "prog"} 各一份；回写云端时原样带上。cloud_v / cloud_minv：
## 见过的云端格式版本最大值，回写时头里的版本只升不降（docs/89 §3.1）
var cloud_extra := {}
var cloud_v := 0
var cloud_minv := 0
## 上云的设置项（Cfg 属性名）。画质 / 全屏 / 分辨率 / 辉光 / 景深 / 法线光照 / 水下滤镜跟设备性能走，不上云
const CLOUD_SET_KEYS := ["master", "music", "sfx", "voice", "dmg_numbers", "hitstop", "boss_intro", "reduce_motion", "outline",
	"brightness", "pad_rumble", "manual_attack", "ui_size_pct", "cam_zoom_pct", "play_speed", "cover_character_id", "difficulty", "touch_layout"]


## ui.ttf（Noto Sans CJK SC 子集）缺的几十个字（娅 / 鲨 / 砥 / 琥珀 / Ⓐ 等）：桌面版靠系统字体补，网页版没有系统字体会显示方块。
## 给 ui.ttf 挂上 ui_fallback.otf（Noto Sans SC Bold 只取缺的字，tools/make_ui_fallback.py 生成）；load 有缓存，主题字体与各处 load 的是同一份
var _ui_font: FontFile = null


## 触屏设备（全项目唯一判定：touch.gd / Pad / 标题页都问这里）：有触屏、网页 Android / iOS、或 --touch。
## iPad Safari 默认报桌面 UA（Macintosh），web_ios 认不出：网页版再看 navigator.maxTouchPoints（触屏验收 10-01，架构报）
var _touch := -1


func touch_device() -> bool:
	if _touch < 0:
		var t: bool = DisplayServer.is_touchscreen_available() or dev_args().has("--touch") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		if not t and OS.has_feature("web"):
			t = bool(JavaScriptBridge.eval("navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent)", true))
		_touch = 1 if t else 0
	return _touch == 1


## 界面里能否在一帧中途读屏幕（BackBufferCopy / hint_screen_texture 之后还要接着画东西）。图鉴磨砂玻璃（gallery.gd）与它打开时的
## 后期层（post_fx.gd）都问这里。10-14 用户报：iPhone 上 itch 网页版图鉴只剩左侧舞台，右侧终端面板、名册、顶栏全不见——
## 画面正好是图鉴 BackBufferCopy 那一刻的内容：中途拷屏之后画的东西（玻璃面板、正文、再一次拷屏的后期层）在 iOS WebKit 上丢了。
## 网页版的触屏设备（iOS / Android / iPad）与苹果 WebKit（iOS 上所有浏览器、macOS Safari）一律不中途读屏，桌面版与桌面 Chrome 网页版照旧。
## --noscreencopy：桌面上强制走这条路（截图验收用）
var _scr_copy := -1


func screen_copy_ok() -> bool:
	if _scr_copy < 0:
		var ok := not dev_args().has("--noscreencopy")
		if ok and OS.has_feature("web"):
			ok = not touch_device() and not bool(JavaScriptBridge.eval("(function(){var u=navigator.userAgent;return /AppleWebKit/.test(u)&&!/Chrome|Chromium|Edg|OPR|Android/.test(u);})()", true))
		_scr_copy = 1 if ok else 0
	return _scr_copy == 1


## 触屏界面层放大倍数（手机端 UI 优化 r2，10-06）：在 1.15 全局缩放之上只放大 HUD / 面板 / 标题页，世界（相机）不动。
## 按逻辑宽度算：手机 19.5:9（逻辑 1357 宽）→ 1.3（UI 逻辑约 1044×481）、16:9（1113）→ 1.11、平板 4:3 → 1。
## game.gd / title.gd 启动时算好存进 ui_k；各界面的 vs（g.hud.size / 标题页 size）就是 UI 逻辑尺寸。桌面恒为 1，排版不变
var ui_k := 1.0


func ui_scale() -> float:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var base := 1.0
	if touch_device():
		base = UI_K_PHONE if phone_ui() else clampf(vs.x / 1000.0, 1.0, 1.3)
	var k: float = base * ui_size_pct / 100.0
	return clampf(k, 0.75, maxf(0.75, vs.y / UI_MIN_H)) if ui_size_pct != 100 else base


## 界面平台档（docs/126 C6）：0 桌面 / 1 触屏（平板、16:9 触屏）/ 2 手机横屏（phone_ui）。各界面用它从自己的三档布局参数表里取一套
func ui_form() -> int:
	return 0 if not touch_device() else (2 if phone_ui() else 1)


## 手机横屏版式（触屏 + 画面比例 ≥ 1.9，19.5:9 手机是 2.17）：不再按界面逻辑高度（< 520）判，界面放大倍数调小后手机仍走手机版式
func phone_ui() -> bool:
	if not touch_device():
		return false
	if toy_device() == "phone":
		return true
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return vs.y > 0.0 and vs.x / vs.y >= 1.9


## 战斗镜头缩放（Camera2D.zoom）：玩家设过用玩家的，否则手机横屏 1.2、其余 1.0。只改画面，玩法不读视口
func cam_zoom() -> float:
	var pct: int = cam_zoom_pct if cam_zoom_pct > 0 else (ZOOM_PHONE_DEF if phone_ui() else 100)
	return clampi(pct, ZOOM_PCT_MIN, ZOOM_PCT_MAX) / 100.0


## 系统安全边距（UI 逻辑像素，[左, 上, 右, 下]）：刘海 / 灵动岛 / 圆角 / 底部横条。
## 原生移动端读 DisplayServer 的安全区；网页读 CSS env(safe-area-inset-*)（页面没声明 viewport-fit=cover 时浏览器自己留黑边，读到 0，
## 嵌在 itch 的 iframe 里也是 0）；B站 Toy 容器里 tools/web/container.js 已把画布缩进安全区（window.__sySafe），这里按 0 算，
## 只有沉浸模式下压在画布上的顶栏胶囊（__sySafe.capsule，容器状态里有才有）把它的下沿当成额外的顶部边距（docs/22「Toy 接入」）。
## 桌面恒为 0。按视口尺寸缓存；Toy 环境变化（_on_toy_change）时清缓存
var _ins_key := Vector3(-1, -1, -1)
var _ins: Array = [0.0, 0.0, 0.0, 0.0]

## B站 Toy 环境（tools/web/container.js 的 window.__syToy 桥，docs/22「Toy 接入」）：deviceType（phone / tablet / desktop / unknown，
## 只在 B站 App 内拿到容器状态后才有）、是否在容器里。手机版式 phone_ui 在画面比例之外也认 deviceType == phone
var _toy_js: JavaScriptObject = null
var _toy_cb: JavaScriptObject = null
var toy_env: Dictionary = {}


func _toy_init() -> void:
	if not OS.has_feature("web"):
		return
	_toy_js = JavaScriptBridge.get_interface("__syToy")
	if _toy_js == null:
		return
	_toy_cb = JavaScriptBridge.create_callback(_on_toy_change)
	_toy_js.onchange(_toy_cb)


func _on_toy_change(args: Array) -> void:
	if args.is_empty() or not (args[0] is String):
		return
	var d = JSON.parse_string(args[0])
	if not (d is Dictionary):
		return
	toy_env = d
	_ins_key = Vector3(-1, -1, -1)
	view_changed.emit()


func toy_device() -> String:
	return str(toy_env.get("deviceType", "")) if bool(toy_env.get("container", false)) else ""


func safe_insets() -> Array:
	if not touch_device():
		return [0.0, 0.0, 0.0, 0.0]
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var key := Vector3(vis.x, vis.y, ui_k)
	if key == _ins_key:
		return _ins
	_ins_key = key
	_ins = [0.0, 0.0, 0.0, 0.0]
	var px := [0.0, 0.0, 0.0, 0.0]
	var per_px := 0.0   # 1 个物理 / CSS 像素 = 多少视口逻辑像素
	if OS.has_feature("web"):
		var js = JavaScriptBridge.eval("(function(){var S=window.__sySafe;if(S){var c=S.capsule,t=0;if(c&&c.y<innerHeight*0.5)t=Math.max(0,c.y+c.h);return '0,'+t+',0,0,'+innerWidth;}var d=document.createElement('div');d.style.cssText='position:fixed;visibility:hidden;padding:env(safe-area-inset-left) env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom)';document.body.appendChild(d);var s=getComputedStyle(d);var r=[s.paddingLeft,s.paddingTop,s.paddingRight,s.paddingBottom].map(parseFloat).join(',');d.remove();return r+','+innerWidth;})()", true)
		if js is String:
			var parts: PackedStringArray = js.split(",")
			if parts.size() == 5 and float(parts[4]) > 0.0:
				for i in 4:
					px[i] = float(parts[i])
				per_px = vis.x / float(parts[4])
	elif OS.has_feature("mobile"):
		var sa: Rect2i = DisplayServer.get_display_safe_area()
		var ws: Vector2i = DisplayServer.window_get_size()
		if sa.size.x > 0 and ws.x > 0:
			px = [sa.position.x, sa.position.y, ws.x - sa.end.x, ws.y - sa.end.y]
			per_px = vis.x / float(ws.x)
	if per_px > 0.0:
		for i in 4:
			_ins[i] = maxf(0.0, float(px[i]) * per_px / ui_k)
	return _ins


## 触屏控件的安全区（UI 坐标）：touch.gd 与触屏按键布局编辑页共用
func touch_safe_rect(vs: Vector2) -> Rect2:
	return TouchLayout.safe_rect(vs, safe_insets())


func ui_size() -> Vector2:
	return get_viewport().get_visible_rect().size / ui_k


## 界面根控件撑满 UI 逻辑区：放大层里 FULL_RECT 锚点按视口算会溢出 ui_k 倍，改成固定尺寸（桌面 ui_k = 1 时调用方不走这里）
func ui_fill(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2.ZERO
	c.size = ui_size()


func _ready() -> void:
	if OS.get_environment("ARK_NO_FOCUS") == "1" and DisplayServer.get_name() != "headless":
		# 测试局（godot_runner 设的环境变量 + game/override.cfg no_focus）：窗口不抢焦点；位置由 runner 用 Win32 挪到屏幕外
		# （用户 10-06：别让弹窗打扰）。不能最小化——最小化后画布不渲染，截图全黑
		get_window().unfocusable = true
	_ui_font = load("res://fonts/ui.ttf")
	if _ui_font != null and _ui_font.fallbacks.is_empty():
		_ui_font.fallbacks = [load("res://fonts/ui_fallback.otf")]
	# 触屏设备：整体放大 1.15（逻辑分辨率 1113×626），字和按钮在手机上更好点；各面板按 vs.y < 680 做紧凑排版
	if touch_device():
		get_tree().root.content_scale_factor = 1.15
	# 网页版 / 移动端：默认关掉最吃性能的后期（玩家仍可在设置里打开）
	if OS.has_feature("web"):
		bloom = false
		water_filter = false
		normal_maps = false
		dof = DisplayServer.is_touchscreen_available() == false
	_toy_init()
	brightness = Look.p("bright_def")
	_migrate_internal_save()
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		_read_cfg(c)
	if _set_sig == "":
		_set_sig = _settings_sig()   # 旧存档 / 首次启动：以现在的设置为基准，没改过就不算「新」（cloud_set_t 保持 0，换设备时让云端的设置生效）
	_apply_unlock_all()
	for a in dev_args():
		# 截图 / 测试新玩家名册：--roster=start5 只留开局 5 人（只在内存，测试局不写存档）；--rostertickets=寻访,招募,调度 预置待用的券
		if a == "--roster=start5":
			roster_unlocked = []
			roster_tickets = {}
			roster_tiers = []
			roster_wish = ""
			roster_pity = 0
			roster_draws = 0
			roster_seed = 12345
			roster_fresh = []
			meta_shape = {}
			meta_earned = {}
			meta_bounty = []
		elif a.begins_with("--metacells="):
			meta_earned = {"test": int(a.substr(12))}   # 截图 / 测试：预置累计生机细胞（只在内存）
		elif a.begins_with("--rostertickets="):
			# 单一寻访凭证（10-22 晚）：--rostertickets=N；旧写法 a,b,c 按 a + b + 2c 折算
			var tk := a.substr(16).split(",")
			roster_tickets = {"hunt": (int(tk[0]) if tk.size() > 0 else 0) + (int(tk[1]) if tk.size() > 1 else 0) + 2 * (int(tk[2]) if tk.size() > 2 else 0)}
		elif a.begins_with("--rosterwish="):
			roster_wish = a.substr(13)
	for a in dev_args():
		# 截图 / 对照用：--uisize=80（界面大小 %）、--camzoom=140（战斗画面缩放 %）
		if a.begins_with("--uisize="):
			ui_size_pct = clampi(int(a.substr(9)), UI_PCT_MIN, UI_PCT_MAX)
		elif a.begins_with("--camzoom="):
			cam_zoom_pct = clampi(int(a.substr(10)), ZOOM_PCT_MIN, ZOOM_PCT_MAX)
	set_quality(_guess_quality() if quality_mode == "auto" else quality_mode)   # 自动档：每次启动按本机检测；手选档：按档位统一开关后期
	for a in dev_args():
		if a.begins_with("--quality="):
			set_quality(a.substr(10))   # 截图自测：强制画质档（测试模式不写存档）
	# 观感量测（render/look.gd --lookdbg）：逐层关掉后期 / 法线光照，或固定亮度
	if Look.dbg("nonormal") != "":
		normal_maps = false
	if Look.dbg("nobloom") != "":
		bloom = false
	if Look.dbg("nofilter") != "":
		water_filter = false
	if Look.dbg("nodof") != "":
		dof = false
	if Look.dbg("nooutline") != "":
		outline = false
	if Look.dbg("bright") != "":
		brightness = float(Look.dbg("bright"))
	apply.call_deferred()


## 读档主体（_ready 读 user://settings.cfg 后调；tests/save_migrate_test.gd 拿旧存档样本直接调它，docs/126 R1）。
## 没写的键沿用当前值；版本迁移都在这里：难度 diff_ver（_migrate_progress）、观感 look_ver、旧倍速、旧券、没有 [roster] 段的老存档
func _read_cfg(c: ConfigFile) -> void:
	cover_character_id = str(c.get_value("display", "cover_character", "mizuki"))
	play_speed = float(c.get_value("game", "play_speed", 1.0))
	if play_speed == 2.0:   # 10-22 删 2× 倍速：旧存档回落到最接近的 1.5×
		play_speed = 1.5
	if play_speed not in [1.0, 1.5]:
		play_speed = 1.0
	master = c.get_value("audio", "master", master)
	music = c.get_value("audio", "music", music)
	sfx = c.get_value("audio", "sfx", sfx)
	voice = c.get_value("audio", "voice", voice)
	fullscreen = c.get_value("video", "fullscreen", fullscreen)
	max_fps = int(c.get_value("video", "max_fps", 60))
	if not MAX_FPS_OPTS.has(max_fps):
		max_fps = 60
	res_index = clampi(int(c.get_value("video", "res_index", res_index)), 0, RESOLUTIONS.size() - 1)
	dmg_numbers = c.get_value("game", "dmg_numbers", dmg_numbers)
	hitstop = c.get_value("game", "hitstop", hitstop)
	boss_intro = c.get_value("game", "boss_intro", boss_intro)
	reduce_motion = c.get_value("game", "reduce_motion", reduce_motion)
	outline = c.get_value("game", "outline", outline)
	dof = c.get_value("video", "dof", dof)
	bloom = c.get_value("video", "bloom", bloom)
	water_filter = c.get_value("video", "water_filter", water_filter)
	normal_maps = c.get_value("video", "normal_maps", normal_maps)
	brightness = clampf(float(c.get_value("video", "brightness", brightness)), 0.8, 1.4)
	brightness = migrate_brightness(brightness, int(c.get_value("video", "look_ver", 0)))
	pad_rumble = c.get_value("input", "pad_rumble", pad_rumble)
	manual_attack = c.get_value("input", "manual_attack", manual_attack)
	touch_layout = TouchLayout.load_from(c)
	ui_size_pct = clampi(int(c.get_value("video", "ui_size", 100)) / 5 * 5, UI_PCT_MIN, UI_PCT_MAX)
	cam_zoom_pct = int(c.get_value("video", "cam_zoom", -1))
	if cam_zoom_pct > 0:
		cam_zoom_pct = clampi(cam_zoom_pct / 5 * 5, ZOOM_PCT_MIN, ZOOM_PCT_MAX)
	quality = str(c.get_value("video", "quality", ""))
	# 旧存档只有 quality（高 / 低）：当作手选那一档；没有（首次启动）就是自动
	quality_mode = str(c.get_value("video", "quality_mode", quality if quality in ["low", "high"] else "auto"))
	if not QUALITY_MODES.has(quality_mode):
		quality_mode = "auto"
	difficulty = c.get_value("progress", "difficulty", difficulty)
	diff_unlocked = c.get_value("progress", "diff_unlocked", diff_unlocked)
	seen_shows = c.get_value("progress", "seen_shows", seen_shows)
	gallery_seen = c.get_value("progress", "gallery_seen", [])
	seen_relics = c.get_value("progress", "seen_relics", seen_relics)
	seen_intro = c.get_value("progress", "seen_intro", seen_intro)
	opening_seen = c.get_value("progress", "opening_seen", opening_seen)
	endings_cleared = c.get_value("progress", "endings_cleared", endings_cleared)
	roster_unlocked = c.get_value("roster", "unlocked", roster_unlocked)
	roster_tickets = c.get_value("roster", "tickets", roster_tickets)
	roster_spare = c.get_value("roster", "spare", roster_spare)
	roster_tiers = c.get_value("roster", "tiers", roster_tiers)
	roster_wish = str(c.get_value("roster", "wish", roster_wish))
	roster_pity = int(c.get_value("roster", "pity", roster_pity))
	roster_draws = int(c.get_value("roster", "draws", roster_draws))
	roster_seed = int(c.get_value("roster", "seed", roster_seed))
	roster_fresh = c.get_value("roster", "fresh", roster_fresh)
	roster_int_grant = bool(c.get_value("roster", "int_grant", roster_int_grant))
	load("res://scripts/core/roster.gd").migrate_tickets()   # 三种券 → 单一寻访凭证（1:1 / 1:1 / 1:2）
	meta_shape = c.get_value("meta", "shape", meta_shape)
	meta_shape_t = int(c.get_value("meta", "shape_t", meta_shape_t))
	meta_earned = c.get_value("meta", "earned", meta_earned)
	meta_dev = str(c.get_value("meta", "dev", meta_dev))
	meta_bounty = c.get_value("meta", "bounty", meta_bounty)
	if not c.has_section("roster"):
		_migrate_roster()
	diff_best = c.get_value("progress", "diff_best", diff_best)
	_migrate_progress(int(c.get_value("progress", "diff_ver", 1)))
	cloud_set_t = int(c.get_value("cloud", "set_t", 0))
	cloud_sig = str(c.get_value("cloud", "sig", ""))
	_set_sig = str(c.get_value("cloud", "set_sig", ""))
	var ex = CloudPack.parse(str(c.get_value("cloud", "extra", "{}")))
	cloud_extra = ex if ex is Dictionary else {}
	cloud_v = int(c.get_value("cloud", "v", 0))
	cloud_minv = int(c.get_value("cloud", "minv", 0))


func apply() -> void:
	view_changed.emit()
	_bus("Master", master)
	_bus("Music", music)
	_bus("SFX", sfx)
	_bus("Voice", voice)
	if DisplayServer.get_name() != "headless":
		if OS.get_environment("ARK_NO_FOCUS") == "1":
			return   # 测试局（不限帧，由测试自己管 max_fps）：窗口由 _ready 里的最小化循环管，不居中、不改模式
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		if not fullscreen:
			var sz: Vector2i = RESOLUTIONS[clampi(res_index, 0, RESOLUTIONS.size() - 1)]
			var scr: Vector2i = DisplayServer.screen_get_size()
			# 比屏幕还大的档位就退到能放下的最大一档
			while (sz.x > scr.x or sz.y > scr.y) and res_index > 0:
				res_index -= 1
				sz = RESOLUTIONS[res_index]
			if DisplayServer.window_get_size() != sz:
				DisplayServer.window_set_size(sz)
				DisplayServer.window_set_position((scr - sz) / 2 + DisplayServer.screen_get_position())
		Engine.max_fps = max_fps   # 无头 / 测试局不走到这里：批跑仍不限帧


const WEB_MASTER_TRIM := -7.0


func _bus(name: String, v: float) -> void:
	var b := AudioServer.get_bus_index(name)
	if b != -1:
		# 网页版没有总线效果（样本播放），Master 的限幅器不起作用：整体让出 WEB_MASTER_TRIM 的余量防削波（音频 9/30 实测：
		# 标准 · 水月 · 高手一局不截断录音，Master 输入峰值 +6.6 dBFS，400ms 最响 -2.8）。桌面版靠限幅器，不降
		var trim: float = WEB_MASTER_TRIM if name == "Master" and OS.has_feature("web") else 0.0
		AudioServer.set_bus_volume_db(b, linear_to_db(max(v, 0.0001)) + trim)


## 观感预设换了亮度缺省（render/look，10-12）：旧存档里还是旧缺省 110% 的（没动过滑杆）跟到新缺省，自己调过的不动
static func migrate_brightness(saved: float, ver: int) -> float:
	if ver < LOOK_VER and is_equal_approx(saved, 1.1):
		return Look.p("bright_def")
	return saved


## 难度存档版本 diff_ver → 现在的 DIFF_VER（4 = 三档预设下标 0 常规 / 1 高压 / 2 深潮）。逐个版本写明，新版本在这里加一支：
##   1（或没写）：11 级累计难度 → _migrate_diff 一步换成三档下标
##   2：三档下标，与 4 同义（潮位试验之前），不用动
##   3：潮位 0–15（内部包短暂存在）→ _migrate_tide_to_preset
##   4：当前；更大的版本号 = 新版本写的存档，原样读
func _migrate_progress(dv: int) -> void:
	match dv:
		0, 1:
			_migrate_diff()   # 旧累计档 → 三档下标，已是 DIFF_VER 4 的含义
		3:
			_migrate_tide_to_preset()


## 旧存档（11 级累计难度）→ 3 档：通关过某档对应的累计档位（旧 diff_unlocked = 通关的最高档 + 1）就解锁下一档，
## 只多不少——例如旧存档解锁到 5（通关过 4 = 第 1 档「波涛迭起·Ⅳ」的档位）→ 解锁第 2 档；只解锁到 1–4（通关过第 0 档）→ 解锁第 1 档。
## 上次选的难度落到它所在的档，且不超过已解锁的档
func _migrate_diff() -> void:
	var old_unlocked := diff_unlocked
	var old_diff := difficulty
	diff_unlocked = 0
	for i in range(1, D.LEGACY_TIERS.size()):
		if old_unlocked >= int(D.LEGACY_TIERS[i - 1].level) + 1:
			diff_unlocked = i
	difficulty = mini(D._tier_of_level_old(old_diff), diff_unlocked)


## 潮位 0–15（DIFF_VER 3，内部包短暂存在）→ 三档预设：潮位 < 5 常规、< 10 高压、其余深潮；解锁同样换算
func _migrate_tide_to_preset() -> void:
	var to_p := func(t: int) -> int: return 0 if t < 5 else (1 if t < 10 else 2)
	difficulty = to_p.call(difficulty)
	diff_unlocked = to_p.call(diff_unlocked)
	difficulty = mini(difficulty, diff_unlocked)


## 各档最佳成绩（victory_flow / 失败时由 game 记）：通关次数、最长探索时间、最快通关时间
func note_diff_best(preset: int, won: bool, t: float) -> void:
	var k := str(preset)
	var b: Dictionary = diff_best.get(k, {"wins": 0, "best_t": 0, "fast_t": 0})
	b.best_t = maxi(int(b.get("best_t", 0)), int(t))
	if won:
		b.wins = int(b.get("wins", 0)) + 1
		b.fast_t = int(t) if int(b.get("fast_t", 0)) <= 0 else mini(int(b.fast_t), int(t))
	diff_best[k] = b
	save()


## 老存档（没有 [roster] 段）：EA 期间所有干员都开局可用，打过的玩家一律直接全部解锁，不收回已有内容（docs/109 §12.5）。
## 判定「打过」：通关过任何难度、达成过结局、或获得过藏品。全新存档保持开局 5 人。
func _migrate_roster() -> void:
	if diff_unlocked >= 1 or not endings_cleared.is_empty() or not seen_relics.is_empty():
		var Roster = load("res://scripts/core/roster.gd")
		roster_unlocked = Roster.all_ids().filter(func(cid): return not Roster.STARTERS.has(cid))


## 开发测试用「全部解锁」（用户 2026-09-27 要求）：难度三档、图鉴（藏品 / 敌人 / 结局）、结局事件线全部解锁。
## debug 构建（编辑器运行、debug 导出）：不带启动参数直接运行时自动打开，带测试参数时要显式加 --unlockall
## （自动测试不受影响），--nounlock 可关掉。发布版（--export-release）只有对内包（build.json audience = internal）
## 启动即打开（1.1.1，用户 09-30）；对外包恒不打开（tools/check_release.py 与 verify_encrypted_game.py 都断言）。
## 只改内存：存档里的真实进度先存进 _real_progress，save() 写回它们，本次运行的解锁与进度不会写进存档。
func _apply_unlock_all() -> void:
	if OS.is_debug_build():
		if dev_args().has("--nounlock") or not (dev_args().is_empty() or dev_args().has("--unlockall")):
			return
	elif build_audience() != "internal":
		return   # 对外包（public / diagnostic）恒不解锁；对内包（1.1.1，用户 09-30）启动即全部解锁，同样只在内存
	unlock_all = true
	_real_progress = {"diff_unlocked": diff_unlocked, "seen_relics": seen_relics.duplicate(), "endings_cleared": endings_cleared.duplicate()}
	diff_unlocked = D.DIFF_PRESETS.size() - 1
	endings_cleared = D.ENDINGS.keys()
	var db = preload("res://scripts/core/relic_db.gd").new()
	db.load_files()
	seen_relics = db.implemented().map(func(r): return r.id)
	# 对内发布包：名册照新玩家走（roster_all_open() 为假），首次启动发测试用寻访凭证，写进存档（真实进度，寻访结果也照常存）
	if internal_roster() and not roster_int_grant:
		roster_int_grant = true
		roster_tickets["hunt"] = int(roster_tickets.get("hunt", 0)) + INTERNAL_TICKETS
		save()


## 对内发布包（非调试版、audience = internal）：图鉴 / 难度 / 结局照旧全开，名册按开局 5 人 + 寻访（10-22）
func internal_roster() -> bool:
	return not OS.is_debug_build() and build_audience() == "internal"


## 名册是否视为全部解锁：调试版的「全部解锁」开着时是；对内发布包不是（要测寻访）
func roster_all_open() -> bool:
	return unlock_all and not internal_roster()


## 画质档位（10-22 改三档 + 自动）：高 = 全开；中 = 只关法线光照 + 辉光（docs/50 量测：法线最贵、辉光次之，景深 / 水下滤镜几乎免费，10-22 协调人定保留）；
## 低 = 四项后期全关 + 粒子减半（fx_density）+ 真人局同屏敌人上限 300（spawner.max_alive；机器人 / 自动测试一律 450）+ 演出简化。
## 这四项后期开关在设置里不再单独露出（键保留、旧存档兼容），一律跟档位走
func set_quality(q: String) -> void:
	quality = q if QUALITY_NAME.has(q) else "high"
	var hi := quality == "high"
	bloom = hi
	normal_maps = hi
	dof = quality != "low"
	water_filter = quality != "low"


func fx_density() -> float:
	return 0.5 if quality == "low" else 1.0


## 自动档的检测（每次启动）：触屏 / 网页移动端 / 移动 GPU 与软件渲染 → 低；桌面核显 → 中；网页其余 → 中（封顶）；桌面其余 → 高
func _guess_quality() -> String:
	if DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return "low"
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	for k in ["mali", "adreno", "powervr", "llvmpipe", "swiftshader", "microsoft basic"]:
		if gpu.contains(k):
			return "low"
	for k in ["intel(r) uhd", "intel(r) hd", "intel(r) iris"]:
		if gpu.contains(k):
			return "mid"
	if OS.has_feature("web"):
		return "mid"   # 网页端自动档封顶「中」（10-22 用户网页实测：高卡、中不卡）；手选「高」照旧可用，桌面原生不变
	return "high"


## 设置里选档：自动 = 立刻按本机检测；手选 = 用那一档（之后不再自动降）
func set_quality_mode(m: String) -> void:
	quality_mode = m if QUALITY_MODES.has(m) else "auto"
	set_quality(_guess_quality() if quality_mode == "auto" else quality_mode)
	quality_probed = quality_mode != "auto"


## 自动档：首局前 2 秒平均帧时 > 25 ms 时降一档（game.gd 调）；返回降到的档（没降返回空）
func auto_downgrade() -> String:
	quality_probed = true
	if quality_mode != "auto":
		return ""
	var nxt: String = {"high": "mid", "mid": "low"}.get(quality, "")
	if nxt != "":
		set_quality(nxt)
	return nxt


## 开发用参数（--allend / --allrelics 这类解锁开关）：只在 debug 构建（编辑器、测试、debug 导出）里读命令行；
## 发布版（--export-release）一律返回空，玩家首次打开一定是未解锁的初始状态（tools/check_release.py 检查）
func dev_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()


func save() -> void:
	if practice_active:
		return
	# 自动测试（任何 --xxx 启动参数，与 sfx.gd 静音同一判定）不写玩家的存档：
	# 否则批跑 / 冒烟里机器人拿到的藏品、解锁的难度都会记进玩家的图鉴与进度（docs/36）
	for a in dev_args():
		if a.begins_with("--"):
			return
	# 先读回原文件再逐项覆盖：本版不认识的键（更新的版本写的）原样留着，不因为整份重写而丢掉（docs/89 §3.1）
	var c := ConfigFile.new()
	c.load(PATH)
	c.set_value("display", "cover_character", cover_character_id)
	c.set_value("game", "play_speed", play_speed)
	c.set_value("audio", "master", master)
	c.set_value("audio", "music", music)
	c.set_value("audio", "sfx", sfx)
	c.set_value("audio", "voice", voice)
	c.set_value("video", "fullscreen", fullscreen)
	c.set_value("video", "max_fps", max_fps)
	c.set_value("video", "res_index", res_index)
	c.set_value("game", "dmg_numbers", dmg_numbers)
	c.set_value("game", "hitstop", hitstop)
	c.set_value("game", "boss_intro", boss_intro)
	c.set_value("game", "reduce_motion", reduce_motion)
	c.set_value("game", "outline", outline)
	c.set_value("video", "dof", dof)
	c.set_value("video", "bloom", bloom)
	c.set_value("video", "water_filter", water_filter)
	c.set_value("video", "normal_maps", normal_maps)
	c.set_value("video", "brightness", brightness)
	c.set_value("video", "look_ver", LOOK_VER)
	c.set_value("input", "pad_rumble", pad_rumble)
	c.set_value("input", "manual_attack", manual_attack)
	TouchLayout.save_to(c, touch_layout)
	c.set_value("video", "ui_size", ui_size_pct)
	c.set_value("video", "cam_zoom", cam_zoom_pct)
	c.set_value("video", "quality", quality)
	c.set_value("video", "quality_mode", quality_mode)
	c.set_value("progress", "difficulty", difficulty)
	c.set_value("progress", "diff_unlocked", _real_progress.get("diff_unlocked", diff_unlocked))
	c.set_value("progress", "diff_ver", DIFF_VER)
	c.set_value("progress", "diff_best", diff_best)
	c.set_value("progress", "gallery_seen", gallery_seen)
	c.set_value("progress", "seen_shows", seen_shows)
	c.set_value("progress", "seen_relics", _real_progress.get("seen_relics", seen_relics))
	c.set_value("progress", "seen_intro", seen_intro)
	c.set_value("progress", "opening_seen", opening_seen)
	c.set_value("progress", "endings_cleared", _real_progress.get("endings_cleared", endings_cleared))
	c.set_value("roster", "unlocked", roster_unlocked)
	c.set_value("roster", "tickets", roster_tickets)
	c.set_value("roster", "spare", roster_spare)
	c.set_value("roster", "tiers", roster_tiers)
	c.set_value("roster", "wish", roster_wish)
	c.set_value("roster", "pity", roster_pity)
	c.set_value("roster", "draws", roster_draws)
	c.set_value("roster", "seed", roster_seed)
	c.set_value("roster", "fresh", roster_fresh)
	c.set_value("roster", "int_grant", roster_int_grant)
	c.set_value("meta", "shape", meta_shape)
	c.set_value("meta", "shape_t", meta_shape_t)
	c.set_value("meta", "earned", meta_earned)
	c.set_value("meta", "dev", meta_dev)
	c.set_value("meta", "bounty", meta_bounty)
	var ss := _settings_sig()
	if ss != _set_sig:
		_set_sig = ss
		cloud_set_t = int(Time.get_unix_time_from_system())
	c.set_value("cloud", "set_t", cloud_set_t)
	c.set_value("cloud", "sig", cloud_sig)
	c.set_value("cloud", "set_sig", _set_sig)
	c.set_value("cloud", "extra", JSON.stringify(cloud_extra))
	c.set_value("cloud", "v", cloud_v)
	c.set_value("cloud", "minv", cloud_minv)
	c.save(PATH)
	var cloud := get_node_or_null("/root/Cloud")
	if cloud != null:
		cloud.local_saved()   # 云存档：只记「待上传」并把最新内容交给网页（页面隐藏时上传），不在这里联网


## ---- 云存档（docs/89）：存档正文与 Cfg 字段互转。合并 / 打包规则在 core/cloud_pack.gd ----

func _settings_sig() -> String:
	var d := {}
	for k in CLOUD_SET_KEYS:
		d[k] = get(k)
	return CloudPack.canon(d).md5_text()


## 当前本地存档的正文（全部解锁时用存档里的真实进度，同 save()）。
## 云端带来的、本版不认识的字段（新版本加的）存在 cloud_extra 里，这里原样放回去：回写云端时不丢（docs/89 §3.1）
func cloud_body() -> Dictionary:
	var d: Dictionary = (cloud_extra.get("d", {}) as Dictionary).duplicate(true)
	for k in CLOUD_SET_KEYS:
		d[k] = TouchLayout.sanitize(touch_layout) if k == "touch_layout" else get(k)
	var st: Dictionary = (cloud_extra.get("set", {}) as Dictionary).duplicate(true)
	st["t"] = cloud_set_t
	st["d"] = d
	var pr: Dictionary = (cloud_extra.get("prog", {}) as Dictionary).duplicate(true)
	pr.merge({"diff": int(_real_progress.get("diff_unlocked", diff_unlocked)), "gal": gallery_seen.duplicate(),
		"rel": (_real_progress.get("seen_relics", seen_relics) as Array).duplicate(), "end": (_real_progress.get("endings_cleared", endings_cleared) as Array).duplicate(),
		"shows": seen_shows.duplicate(), "intro": seen_intro, "open": opening_seen,
		"ops": roster_unlocked.duplicate(), "optier": roster_tiers.duplicate(),
		"dbest": diff_best.duplicate(true),
		"meta": {"earned": meta_earned.duplicate(), "bounty": meta_bounty.duplicate(), "shape": meta_shape.duplicate(), "t": meta_shape_t},
		"opst": {"tk": roster_tickets.duplicate(), "sp": roster_spare.duplicate(), "wish": roster_wish, "pity": roster_pity, "draws": roster_draws, "seed": roster_seed}}, true)
	var out: Dictionary = (cloud_extra.get("top", {}) as Dictionary).duplicate(true)
	out["set"] = st
	out["prog"] = pr
	return out


## 把正文写回 Cfg 字段（逐项校验 / 夹取），不落盘。之后调用方 save()。
## 正文里没有的字段（旧版本写的云档）、类型不对的字段都保持本地值，不清空；本版不认识的字段记进 cloud_extra。
## 设置签名同步更新，cloud_set_t 取正文里的时刻：采用云端设置不算本机的新修改
func cloud_apply(body: Dictionary) -> void:
	var st: Dictionary = body.get("set", {}) if body.get("set") is Dictionary else {}
	var d: Dictionary = st.get("d", {}) if st.get("d") is Dictionary else {}
	var p: Dictionary = body.get("prog", {}) if body.get("prog") is Dictionary else {}
	for k in ["master", "music", "sfx", "voice"]:
		if d.get(k) is float or d.get(k) is int:
			set(k, clampf(float(d[k]), 0.0, 1.0))
	for k in ["dmg_numbers", "hitstop", "boss_intro", "reduce_motion", "outline", "pad_rumble", "manual_attack"]:
		if d.get(k) is bool:
			set(k, d[k])
	if d.get("brightness") is float or d.get("brightness") is int:
		brightness = clampf(float(d.brightness), 0.8, 1.4)
	if d.get("ui_size_pct") is float or d.get("ui_size_pct") is int:
		ui_size_pct = clampi(int(d.ui_size_pct) / 5 * 5, UI_PCT_MIN, UI_PCT_MAX)
	if d.get("cam_zoom_pct") is float or d.get("cam_zoom_pct") is int:
		var z := int(d.cam_zoom_pct)
		cam_zoom_pct = -1 if z <= 0 else clampi(z / 5 * 5, ZOOM_PCT_MIN, ZOOM_PCT_MAX)
	if (d.get("play_speed") is float or d.get("play_speed") is int) and float(d.play_speed) in [1.0, 1.5, 2.0]:
		play_speed = 1.5 if float(d.play_speed) == 2.0 else float(d.play_speed)   # 旧云存档的 2.0 回落 1.5（10-22 删 2×）
	if d.get("cover_character_id") is String and FileAccess.file_exists("res://data/characters/%s.json" % d.cover_character_id):
		cover_character_id = d.cover_character_id
	if d.get("touch_layout") is Dictionary:
		touch_layout = TouchLayout.sanitize(d.touch_layout)
	var lists := {"gal": "gallery_seen", "rel": "seen_relics", "end": "endings_cleared", "shows": "seen_shows", "ops": "roster_unlocked"}
	if p.get("meta") is Dictionary:
		var mt: Dictionary = p.meta
		if mt.get("earned") is Dictionary:
			meta_earned = (mt.earned as Dictionary).duplicate()
		if mt.get("bounty") is Array:
			meta_bounty = mt.bounty.map(func(x): return int(x))
		if mt.get("shape") is Dictionary:
			meta_shape = (mt.shape as Dictionary).duplicate()
		if mt.get("t") is float or mt.get("t") is int:
			meta_shape_t = int(mt.t)
		var M = load("res://scripts/core/meta.gd")
		if M.spent(meta_shape) > M.earned_total():
			meta_shape = {}   # 采用的认知塑造超出余额（另一台设备的进度还没同步过来）：整组重置，重置免费
	if p.get("dbest") is Dictionary:
		diff_best = (p.dbest as Dictionary).duplicate(true)
	if p.get("optier") is Array:
		roster_tiers = p.optier.map(func(x): return int(x))
	if p.get("opst") is Dictionary:
		var st0: Dictionary = p.opst
		if st0.get("tk") is Dictionary:
			roster_tickets = (st0.tk as Dictionary).duplicate()
			load("res://scripts/core/roster.gd").migrate_tickets()   # 旧云档的三种券折成寻访凭证
		if st0.get("sp") is Dictionary:
			roster_spare = (st0.sp as Dictionary).duplicate()
		if st0.get("wish") is String:
			roster_wish = st0.wish
		for k in ["pity", "draws", "seed"]:
			if st0.get(k) is float or st0.get(k) is int:
				set("roster_" + k, int(st0[k]))
	if p.get("diff") is float or p.get("diff") is int:
		var unlocked: int = clampi(int(p.diff), 0, D.DIFF_PRESETS.size() - 1)
		if unlock_all:
			_real_progress["diff_unlocked"] = unlocked
		else:
			diff_unlocked = unlocked
	for k in lists:
		if not (p.get(k) is Array):
			continue
		var arr: Array = p[k].map(func(x): return str(x))
		if unlock_all and k in ["rel", "end"]:
			_real_progress[{"rel": "seen_relics", "end": "endings_cleared"}[k]] = arr
		else:
			set(lists[k], arr)
	if p.get("intro") is bool:
		seen_intro = p.intro
	if p.get("open") is bool:
		opening_seen = p.open
	if d.get("difficulty") is float or d.get("difficulty") is int:
		difficulty = int(d.difficulty)
	difficulty = clampi(difficulty, 0, int(_real_progress.get("diff_unlocked", diff_unlocked)))
	if st.get("t") is float or st.get("t") is int:
		cloud_set_t = int(st.t)
	# 不认识的字段：记下来，回写云端时原样带上
	var ex := {"top": {}, "set": {}, "d": {}, "prog": {}}
	for k in body:
		if not (k in ["set", "prog"]):
			ex.top[k] = body[k]
	for k in st:
		if not (k in ["t", "d"]):
			ex.set[k] = st[k]
	for k in d:
		if not (k in CLOUD_SET_KEYS):
			ex.d[k] = d[k]
	for k in p:
		if not (k in CloudPack.PROG_KEYS):
			ex.prog[k] = p[k]
	cloud_extra = ex
	_set_sig = _settings_sig()


## 打包时写进 build.json 的发布对象：public / internal / diagnostic；源码运行（没打包）为 ""
func build_audience() -> String:
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
	return str(info.get("audience", "")) if info is Dictionary else ""


## 本地对局记录（docs/40，run/telemetry.gd 的 save_local）：调试版（编辑器 / 源码运行）写；发布版只有对内包
## （build.json audience = internal）写（用户 2026-10-10：对内包给自己和几位测试者玩，用真实对局判断难度）；
## 对外包恒不写（用户 2026-09-26 的「暂不收集任何数据」不变）。只写本地 user://runs/runs.jsonl，不联网上传。
## tools/check_release.py 静态断言对外分支，verify_encrypted_game.py 在打包后实测与 audience 一致。
func runs_log_enabled() -> bool:
	if OS.is_debug_build():
		return true
	return build_audience() == "internal"


## 对局记录所在文件夹的绝对路径（Windows 对内包：%APPDATA% 下 ArknightsSurvivors_Internal 的 runs 子目录）
func runs_dir() -> String:
	return ProjectSettings.globalize_path("user://runs")


## 设置页「打开记录文件夹」：在系统文件管理器里选中 runs.jsonl（还没有记录时建好文件夹并打开它），方便测试者把文件发过来
func show_runs_folder() -> void:
	var dir := runs_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var file := dir.path_join("runs.jsonl")
	OS.shell_show_in_file_manager(file if FileAccess.file_exists(file) else dir, true)


## Boss 演练入口：开发（调试版）一律开；发布版只有对内包（build.json audience = internal）开。
## 按 audience 判断而不是 EA 标记——EA 只是开发阶段标记，对外包也可能带 EA，不能因此开放演练（docs/33 §双版本）
## 调试版可用 --audience=public 模拟对外包的入口（标题页磁贴群截图 / 测试用；发布版 dev_args 恒为空，不受影响）
func can_boss_trial() -> bool:
	if OS.is_debug_build():
		return not dev_args().has("--audience=public")
	return build_audience() == "internal"


## 对内包存档一次性迁移（2026-09-30，docs/33 §双版本）：对内包的存档目录从 ArknightsSurvivors 改成
## ArknightsSurvivors_Internal（tools/export_build.py 打包时改）后，已经在玩旧内测包的人进度会「消失」。
## 对内包启动时：新目录还没有存档、旧目录（同级的 ArknightsSurvivors）有，就把 settings.cfg 复制过来——
## 只复制，不移动、不删旧的；新目录已有存档就不动。对外包 / 调试版不迁移。
const LEGACY_USER_DIR := "ArknightsSurvivors"
const INTERNAL_USER_DIR := "ArknightsSurvivors_Internal"

func _migrate_internal_save() -> void:
	if OS.is_debug_build() or build_audience() != "internal":
		return
	var cur := OS.get_user_data_dir()
	if cur.get_file() != INTERNAL_USER_DIR or FileAccess.file_exists(PATH):
		return
	var old := cur.get_base_dir().path_join(LEGACY_USER_DIR).path_join(PATH.get_file())
	if not FileAccess.file_exists(old):
		return
	DirAccess.make_dir_recursive_absolute(cur)
	var err := DirAccess.copy_absolute(old, cur.path_join(PATH.get_file()))
	print("[Cfg] 对内包存档迁移：%s -> %s（%s）" % [old, cur.path_join(PATH.get_file()), error_string(err)])
