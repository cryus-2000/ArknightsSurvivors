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
var max_fps := 0           # 帧率上限 0 = 自动 / 60 / 30（10-22 加 60 / 30；10-25 用户定加「自动」并作缺省，设置「画面」）：只限渲染帧（Engine.max_fps；
                          # 网页端 Godot 在 requestAnimationFrame 回调里按它跳帧），逻辑仍按 PlayClock 固定步长。
                          # 自动：桌面 60；网页先按 60 跑，开局前几秒稳不住 50 帧就锁 30（fps_lock30，本次启动有效，不来回跳；game._auto_quality）
const MAX_FPS_OPTS := [0, 60, 30]
var fps_lock30 := false   # 自动档在网页上测出稳不住 50 帧：本次启动锁 30
var fps_probed := false   # 自动档本次启动已测过（测过就不再改）


## 实际生效的帧率上限（Engine.max_fps）
func effective_max_fps() -> int:
	if max_fps > 0:
		return max_fps
	if mobile_web():
		return 30   # 10-26 晚用户定：手机网页自动档直接锁 30（稳 30 比 40 上下抖好），不测；手选 60 照旧
	return 30 if fps_lock30 else 60
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
var quality_probed := false  # （旧）自动档首局前 2 秒测帧时，保留键兼容存档；10-27 起局中不再降档
var guard_prev := ""   # 护栏降档前的画质（推荐档时下局恢复它）
var guard_lowered := false   # 内存护栏本局临时降过画质（手动档也会，提示玩家；下局开局恢复手选的档）
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
const ZOOM_PCT_MAX := 150
const ZOOM_PHONE_DEF := 120
const ZOOM_DESK_DEF := 115   # 桌面战斗镜头缺省（用户 10-24「镜头稍微拉近一点」；100 = 原镜头，docs/134）；玩家在设置里自选的值优先
## 手机横屏的界面放大缺省（原 1.3 → 1.15，界面整体收到约 88%）；平板 / 16:9 触屏仍按宽度 1.0–1.3
const UI_K_PHONE := 1.15
## 界面逻辑高度下限：界面大小调到 120% 时也不低于手机版式设计高度（原手机 481）
const UI_MIN_H := 470.0
## 触屏按键布局（设置 → 游戏 → 触屏按键布局，用户 10-13）：{键: {ax, ay, x, y, s}}，空 = 全部缺省（touch_layout.gd）
var touch_layout := {}
## 自动连携 / 自动终结技（docs/198 §1.4、§11-7；run/ult.gd 每帧读）：缺省桌面两个都关、触屏「自动连携」开（_ready 里按设备定，读档覆盖）。
## 缺省跟设备走，不上云（同一份云档在电脑和手机上各用各的缺省）
var auto_combo := false
var auto_ult := false
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
var event_log := {}           # 事件图鉴（core/event_book.gd）：{seen: {事件: 遇到次数}, opt: {"事件:编号": 见过}, pick: {"事件:编号": 选过次数}}；老存档没有，从空开始
var seen_intro := false      # 已看过开局引导（聚光框，screens/tour.gd；旧版翻页指南也用它）
var title_tour := 0          # 主界面引导（screens/title_tour.gd）：0 没有 / 1 新手十连做完待引导 / 2 已引导（老存档恒为 0，不弹）
var seen_tips: Array = []    # 已弹过的到点小提示 id（tour.gd TIPS；每样只弹一次）
const TIP_IDS := ["elite", "boss", "lamp", "levelup"]
var endings_cleared: Array = []   # 已达成的结局 id（通关结局一后才出现其余结局的事件）
# 干员解锁（局外成长 P1，docs/109 §12，core/roster.gd）：存档 [roster] 段。10-26 起新玩家开局为空（新手十连），名册全部存在这里
var roster_unlocked: Array = []   # 解锁过的干员 id（roster_v ≥ 2：全部；旧版存档不含开局 5 人，读档时补上）
var roster_v := 0                 # 名册存档版本：2 = 开局 5 人已写进 roster_unlocked（10-26 新手十连起）
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
var meta_bought := {}             # 用生机细胞兑换寻访凭证花掉的细胞 {设备号: 数量}（云存档同 meta_earned 逐设备取大再求和；余额 = 累计获得 − 认知塑造 − 兑换）
var meta_bounty: Array = []       # 已领首通赏金的潮位
var roster_fresh: Array = []      # 刚解锁、还没在名册里看过的干员（选人页 / 图鉴高亮一次；只存本机，不上云）
var roster_int_grant := false     # 对内包的测试寻访凭证已发过（INTERNAL_TICKETS，每份存档一次）
var medals := {}                  # 已获得的蚀刻章 {key: 获得时刻 Unix 秒}（core/medals.gd；存档 [medals] 段；获得后永久保留）
var medal_best := {}              # 蚀刻章的历史最好进度 {key: 数}（协同晋升：一次探索里同时精英二的人数）
## 对内包（用户 10-22：要在对内包里测寻访；10-24 开局 10 人 + 20 张；10-26 改：与新玩家同一流程——名册为空 + 新手 10 张、
## 先做新手十连），每份存档首次启动再多发这么多张寻访凭证，十连之后用来测单抽 / 定向 / 补满名册
const INTERNAL_TICKETS := 20
## 对内包存档目录带提交号（ArknightsSurvivors_Internal_<短 sha>，tools/export_build.py 打包时改 project.godot）：每个新的对内包从干净存档开始，
## 不读旧包、也不读开发目录的存档（用户 10-24；旧的一次性迁移已删）；同一个包里的进度照常保存
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
	"brightness", "pad_rumble", "ui_size_pct", "cam_zoom_pct", "play_speed", "cover_character_id", "difficulty", "touch_layout"]


## ui.ttf（Noto Sans CJK SC 子集）缺的几十个字（娅 / 鲨 / 砥 / 琥珀 / Ⓐ 等）：桌面版靠系统字体补，网页版没有系统字体会显示方块。
## 给 ui.ttf 挂上 ui_fallback.otf（Noto Sans SC Bold 只取缺的字，tools/make_ui_fallback.py 生成）；load 有缓存，主题字体与各处 load 的是同一份
var _ui_font: FontFile = null


## 触屏设备（全项目唯一判定：touch.gd / Pad / 标题页都问这里）：有触屏、网页 Android / iOS、或 --touch。
## iPad Safari 默认报桌面 UA（Macintosh），web_ios 认不出：网页版再看 navigator.maxTouchPoints（触屏验收 10-01，架构报）
var _touch := -1


## 手机 / 平板上的网页（10-26 iPhone Safari 进局即「网页崩溃」：WebKit 按内存杀页，docs/50 §30）：开局就封渲染分辨率、自动档从「低」起、音乐分轨不预先解码
func mobile_web() -> bool:
	return OS.has_feature("web") and touch_device()


## 手机网页止血开关（balance.json 没写 = 缺省值；--bal=web/<键>=0 可退回 10-25 线上版行为做对照）
func mobile_knob(key: String, dflt: float) -> bool:
	return load("res://scripts/core/balance.gd").v("web/" + key, dflt) > 0.0


## 字形缓存瘦身（docs/50 §30.4：桌面低画质一局下来字体缓存 173 个字号、161 张页、62 MB——引擎显存里最大的一块没对上的就是它）：
## 关掉亚像素定位（每个字形不再按 1/4 像素存 4 份；像素风的界面字看不出差别），并清掉已有缓存。手机网页开局做、进局再清一次标题页用过的字号
const FONT_PATHS := ["res://fonts/ui.ttf", "res://fonts/ui_fallback.otf", "res://fonts/serif.ttf"]

func slim_fonts(clear_only := false) -> void:
	for fp in FONT_PATHS:
		var ff = load(fp)
		if ff is FontFile:
			if not clear_only:
				ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			ff.clear_cache()


func mobile_fonts_slim() -> bool:
	return (mobile_web() and mobile_knob("mobile_font_slim", 1.0)) or dev_args().has("--fontslim")


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
	return clampi(cam_zoom_pct if cam_zoom_pct > 0 else zoom_default_pct(), ZOOM_PCT_MIN, ZOOM_PCT_MAX) / 100.0


## 本设备的战斗镜头缺省百分比（手机横屏 ZOOM_PHONE_DEF、桌面 ZOOM_DESK_DEF2 / 退回时 ZOOM_DESK_DEF；镜头实际 zoom 见 battle_zoom）
func zoom_default_pct() -> int:
	if phone_ui():
		return ZOOM_PHONE_DEF
	return ZOOM_DESK_DEF2 if cam_unified() else ZOOM_DESK_DEF


## 三档画质同一个镜头（10-27 用户实机，docs/50 §32）。原来低档不开光学，镜头直接是 cam_zoom（手机 1.2 / 桌面 1.15）；中 / 高走光学的整数像素镜头
## （1 美术像素占整数 k 个物理像素，再乘设置里的缩放），两者在高像素密度屏上差很多：iPhone 横屏低 522 / 中 780 世界像素高，1080p 桌面低 626 / 中 939。
## 现在三档都用 battle_zoom()：低档 cam.zoom 与光学 _lo_step 同一个值。
##   手机：「低和中之间取个偏向低画质下的镜头距离」——k 按可见高约 render/phone_view_h（300）美术像素取整：iPhone 横屏（1170 物理像素高）k = 4、可见 585
##        （低 522 → 中 780 的 0.24 处），像素宽也整齐；
##   桌面：「稍微放大一点」——缺省缩放 115 → ZOOM_DESK_DEF2 126（可见范围 −9%，相对原来中 / 高档的镜头）。
## --bal=render/cam_unify=0 退回（低档照旧 cam_zoom、桌面缺省 115、手机 k 按 360 取）
const ZOOM_DESK_DEF2 := 126

func cam_unified() -> bool:
	return load("res://scripts/core/balance.gd").v("render/cam_unify", 1.0) > 0.0


## 整数像素镜头的 k：按窗口物理像素高 / 目标可见高（美术像素）取整，至少 2
func view_k() -> int:
	var vp := get_viewport()
	var ph: float = vp.get_visible_rect().size.y * maxf(0.01, vp.get_final_transform().x.x)
	var Bal = load("res://scripts/core/balance.gd")
	var target: float = Bal.v("render/optical_view_h", 450.0)
	if phone_ui():
		target = Bal.v("render/phone_view_h", 300.0) if cam_unified() else Bal.v("render/optical_view_h_phone", 360.0)
	return maxi(2, roundi(ph / target))


## 战斗镜头 zoom：可见世界高固定（10-27 用户「调整分辨率之后会出现缩放镜头视角的问题」，docs/50 §38）——原来按整数像素 k = round(物理像素高 / 目标)
## 定，换分辨率 / 拖窗口 / 全屏 / 手机浏览器地址栏收放时 k 在整数间跳，可见范围跟着跳（1080p → 1440p 少 11%）。现在可见高只看设置：
##   桌面 render/view_h_desk（1080）÷ 缺省缩放 1.26 = 857（与 1080p 上原来一样）；触屏设备 render/view_h_phone（585）
##   （iPhone 横屏 1 美术像素正好 4 物理像素，同原来）；设置里的战斗画面缩放相对本设备缺省再乘。zoom = 视口设计高 ÷ 可见高；--bal=render/cam_unify=0 退回旧的按 k 算
func battle_zoom() -> float:
	var Bal = load("res://scripts/core/balance.gd")
	if not cam_unified():
		var sx: float = maxf(0.01, get_viewport().get_final_transform().x.x)
		return view_k() / (2.0 * sx) * cam_zoom() / (ZOOM_PHONE_DEF / 100.0 if phone_ui() else 1.0)
	var vy: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
	# 触屏设备一律按手机的可见高（16:9 的小屏手机 / 平板不算手机版式，原来落到桌面算法会拉得很远）；缩放相对本设备缺省
	var h: float = Bal.v("render/view_h_phone", 585.0) if touch_device() else Bal.v("render/view_h_desk", 1080.0) / (ZOOM_DESK_DEF2 / 100.0)
	return vy / h * cam_zoom() / (zoom_default_pct() / 100.0)


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
	for a in dev_args():
		if a.begins_with("--winsize=") and DisplayServer.get_name() != "headless":
			# 截图自测（分辨率矩阵 tools/ui_matrix.py）：无边框窗口设成任意尺寸，可以比本机屏幕大（--resolution 会被标题栏 / 屏幕裁掉）
			var wp := a.substr(10).split("x")
			get_window().borderless = true
			get_window().size = Vector2i(int(wp[0]), int(wp[1]))
	if dev_args().has("--ftrec"):
		get_tree().root.add_child.call_deferred(preload("res://scripts/core/frame_rec.gd").new())   # 界面帧时记录（docs/50 §27），只在测试参数下
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
	auto_combo = touch_device()   # 手机缺省自动连携（§11-7）；存档里有就用存档的
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		_read_cfg(c)
	else:
		_roster_fresh()   # 全新安装（没有存档文件）：新手开局
	if _set_sig == "":
		_set_sig = _settings_sig()   # 旧存档 / 首次启动：以现在的设置为基准，没改过就不算「新」（cloud_set_t 保持 0，换设备时让云端的设置生效）
	_apply_unlock_all()
	load("res://scripts/core/medals.gd").sync()   # 蚀刻章补录：旧存档里已有的结局 / 藏品 / 认知记录，读档时按真实记录补上（下次存档写盘）
	for a in dev_args():
		# 截图 / 测试：--medals=all / none / key,key 预置已得蚀刻章，--medalbest=key:n 预置进度（只在内存，测试局不写存档）
		if a.begins_with("--medals="):
			var v := a.substr(9)
			medals = {}
			for m in load("res://scripts/core/medals.gd").defs():
				if v == "all" or v.split(",").has(str(m.key)):
					medals[m.key] = 1793000000
		elif a.begins_with("--medalbest="):
			for kv in a.substr(12).split(",", false):
				var pr := kv.split(":")
				if pr.size() == 2:
					medal_best[pr[0]] = int(pr[1])
	for a in dev_args():
		# 截图 / 测试名册（只在内存，测试局不写存档）：--roster=start5 = 旧版开局 5 人（Roster.STARTERS，现有单测按它写）；
		# --roster=new = 10-26 新手开局（名册为空 + 新手 10 张，要先做新手十连）；--rostertickets=寻访,招募,调度 预置待用的券
		if a == "--roster=start5" or a == "--roster=new":
			var R0 = preload("res://scripts/core/roster.gd")
			roster_unlocked = [] if a == "--roster=new" else R0.STARTERS.duplicate()
			roster_tickets = {"hunt": R0.FIRST_TICKETS} if a == "--roster=new" else {}
			roster_v = 2
			roster_tiers = []
			roster_wish = ""
			roster_pity = 0
			roster_draws = 0
			roster_seed = 12345
			roster_fresh = []
			meta_shape = {}
			meta_earned = {}
			meta_bought = {}
			meta_bounty = []
		elif a == "--roster=full":   # 截图：名册全满（寻访「全员已入职」页），只在内存
			roster_unlocked = preload("res://scripts/core/roster.gd").all_ids()
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
	if mobile_fonts_slim():
		slim_fonts()
	if mobile_web() and mobile_knob("mobile_rscale", 0.0):
		# 手机网页开局按逻辑分辨率（约 1113×626）画再放大：显存省，但整屏线性放大约 2.27 倍，像素边和文字都糊（10-27 用户 iPhone「好糊」）。
		# 10-27 起缺省关（docs/50 §34）：按设备像素画，美术像素落整数倍（光学 k = 4）、文字原生分辨率；内存护栏超线时仍会开它兜底
		set_render_scale.call_deferred(true)
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
	# 10-25 起存 fps_mode（0 自动 / 60 / 30）；旧存档只有 max_fps（缺省 60，没法分辨是否手选过）：旧值 30 视为手选 30，其余按「自动」
	if c.has_section_key("video", "fps_mode"):
		max_fps = int(c.get_value("video", "fps_mode", 0))
	else:
		max_fps = 30 if int(c.get_value("video", "max_fps", 60)) == 30 else 0
	if not MAX_FPS_OPTS.has(max_fps):
		max_fps = 0
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
	auto_combo = bool(c.get_value("input", "auto_combo", auto_combo))
	auto_ult = bool(c.get_value("input", "auto_ult", auto_ult))
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
	var evl = c.get_value("progress", "event_log", {})
	event_log = evl if evl is Dictionary else {}
	seen_intro = c.get_value("progress", "seen_intro", seen_intro)
	seen_tips = c.get_value("progress", "seen_tips", seen_tips)
	title_tour = int(c.get_value("progress", "title_tour", title_tour))
	if not c.has_section_key("progress", "seen_tips") and seen_intro:
		seen_tips = TIP_IDS.duplicate()   # 老存档（已看过旧指南）：到点小提示按「都看过」处理，不再打扰
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
	roster_v = int(c.get_value("roster", "v", 0))
	load("res://scripts/core/roster.gd").migrate_tickets()   # 三种券 → 单一寻访凭证（1:1 / 1:1 / 1:2）
	meta_shape = c.get_value("meta", "shape", meta_shape)
	meta_shape_t = int(c.get_value("meta", "shape_t", meta_shape_t))
	meta_earned = c.get_value("meta", "earned", meta_earned)
	meta_bought = c.get_value("meta", "bought", meta_bought)
	meta_dev = str(c.get_value("meta", "dev", meta_dev))
	meta_bounty = c.get_value("meta", "bounty", meta_bounty)
	var md = c.get_value("medals", "got", medals)
	medals = md if md is Dictionary else {}
	var mb = c.get_value("medals", "best", medal_best)
	medal_best = mb if mb is Dictionary else {}
	if not c.has_section("roster"):
		_migrate_roster()
	elif roster_v < 2:
		_roster_add_starters()
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
		Engine.max_fps = effective_max_fps()   # 无头 / 测试局不走到这里：批跑仍不限帧


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
## 判定「打过」：通关过任何难度、达成过结局、或获得过藏品。没打过的按新玩家开局（10-26：名册为空 + 新手 10 张，先做新手十连）。
func _migrate_roster() -> void:
	if diff_unlocked >= 1 or not endings_cleared.is_empty() or not seen_relics.is_empty():
		roster_unlocked = load("res://scripts/core/roster.gd").all_ids()
		roster_v = 2
	else:
		_roster_fresh()


## 新手开局（10-26 用户）：名册为空、送 Roster.FIRST_TICKETS 张寻访凭证；主界面引导去做新手十连。只改内存，随下一次存档写盘
## （没写盘前退出，下次启动还是全新存档，结果相同）
func _roster_fresh() -> void:
	roster_unlocked = []
	roster_tickets = {"hunt": load("res://scripts/core/roster.gd").FIRST_TICKETS}
	roster_v = 2


## 旧版名册存档（有 [roster] 段、版本 < 2）：开局 5 人当时不写进存档，现在补进 roster_unlocked，老玩家名册不变
func _roster_add_starters() -> void:
	for cid in load("res://scripts/core/roster.gd").STARTERS:
		if not roster_unlocked.has(cid):
			roster_unlocked.append(cid)
	roster_v = 2


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
	# 对内发布包：名册不全开（roster_all_open() 为假），与新玩家同一流程（新手十连），首次启动另发测试用寻访凭证，写进存档（真实进度，寻访结果也照常存）
	if internal_roster() and not roster_int_grant:
		roster_int_grant = true
		roster_tickets["hunt"] = int(roster_tickets.get("hunt", 0)) + INTERNAL_TICKETS
		save()


## 对内发布包（非调试版、audience = internal）：图鉴 / 难度 / 结局照旧全开，名册按开局 10 人 + 寻访（10-22、10-24）
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


## 分辨率缩放（画质自动档第 3 级，docs/50 §28）：高像素密度屏（手机网页按设备像素画，2400×1080 级）改成先按逻辑分辨率（约 1280×720）
## 画好整屏再放大，全屏着色器 / 后期的像素量降到约四分之一；字会软一点。窗口像素和逻辑分辨率差不多时（普通桌面）没有收益，自动档不用这一级
var render_scaled := false

func set_render_scale(on: bool) -> void:
	if on == render_scaled:
		return
	render_scaled = on
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if on else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS


## 窗口实际像素比逻辑分辨率（720 高）多出三成以上：分辨率缩放才有用
func hidpi_render() -> bool:
	return get_tree().root.size.y > 720.0 * 1.3


## 这一局要不要法线光照：设置开着、有显卡，且光学观感没开（光学下不画法线，除非 render/optical_normals）。
## 标题页预热与对局同一判断（10-25 从 game.gd 搬来：标题页不再为它 preload game.gd，docs/50 §29）
func wants_normal_maps() -> bool:
	var Bal = load("res://scripts/core/balance.gd")
	return normal_maps and DisplayServer.get_name() != "headless" and (Bal.v("render/optical_normals", 0.0) > 0.0 or not (Bal.v("render/optical", 1.0) > 0.0 and quality != "low"))


func fx_density() -> float:
	return 0.5 if quality == "low" else 1.0


## 自动档的检测（每次启动）：软件渲染 → 低；触屏 / 网页移动端 / 移动 GPU / 桌面核显 → 中；网页其余 → 中（封顶）；桌面其余 → 高。
## 10-25 起手机也从「中」起（用户「网页不默认低画质」「高配机观感不能变差，只在测出掉帧时才降」）：掉帧时由对局里的逐级降（game._auto_quality）往下收，
## 原来手机直接「低」（10-22）
func _guess_quality() -> String:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	for k in ["llvmpipe", "swiftshader", "microsoft basic"]:
		if gpu.contains(k):
			return "low"
	if DisplayServer.is_touchscreen_available() or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		# 10-26 改回「低」（10-25 曾改「中」）：iPhone 网页进局即崩，光学层 / 发光层 / GPU 粒子的渲染目标与着色器在 WebKit 上吃内存；
		# 掉帧时的逐级降档来不及救内存。手选「中 / 高」照旧可用
		return "low" if mobile_knob("mobile_low", 0.0) or not OS.has_feature("web") else "mid"   # 10-26 晚用户定手机标准「30 帧 + 中档特效」：改回从中起（内存靠其余止血项与护栏兜）
	for k in ["mali", "adreno", "powervr"]:
		if gpu.contains(k):
			return "mid"
	for k in ["intel(r) uhd", "intel(r) hd", "intel(r) iris"]:
		if gpu.contains(k):
			return "mid"
	if OS.has_feature("web"):
		return "mid"   # 网页端自动档封顶「中」（10-22 用户网页实测：高卡、中不卡）；手选「高」照旧可用，桌面原生不变
	return "high"


## 设置里选档：自动 = 立刻按本机检测；手选 = 用那一档（之后不再自动降）
func set_quality_mode(m: String) -> void:
	quality_mode = m if QUALITY_MODES.has(m) else "auto"
	guard_lowered = false   # 手动换档压过护栏这一局的临时降档
	set_quality(_guess_quality() if quality_mode == "auto" else quality_mode)
	quality_probed = quality_mode != "auto"


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
	c.set_value("video", "fps_mode", max_fps)
	c.set_value("video", "max_fps", effective_max_fps())   # 旧键：老版本读到的仍是 60 / 30
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
	c.set_value("input", "auto_combo", auto_combo)
	c.set_value("input", "auto_ult", auto_ult)
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
	c.set_value("progress", "event_log", event_log)
	c.set_value("progress", "seen_intro", seen_intro)
	c.set_value("progress", "seen_tips", seen_tips)
	c.set_value("progress", "title_tour", title_tour)
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
	c.set_value("roster", "v", roster_v)
	c.set_value("meta", "shape", meta_shape)
	c.set_value("meta", "shape_t", meta_shape_t)
	c.set_value("meta", "earned", meta_earned)
	c.set_value("meta", "bought", meta_bought)
	c.set_value("meta", "dev", meta_dev)
	c.set_value("meta", "bounty", meta_bounty)
	load("res://scripts/core/medals.gd").sync()   # 结局 / 藏品 / 认知塑造的记录都经这里落盘：先补判蚀刻章，同一次写进存档
	c.set_value("medals", "got", medals)
	c.set_value("medals", "best", medal_best)
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
## 云存档正文里的局外成长段；兑换记账 bought 只在有记录时才写，没兑换过的存档往返与旧版本逐字相同
func _cloud_meta() -> Dictionary:
	var m := {"earned": meta_earned.duplicate(), "bounty": meta_bounty.duplicate(), "shape": meta_shape.duplicate(), "t": meta_shape_t}
	if not meta_bought.is_empty():
		m["bought"] = meta_bought.duplicate()
	return m


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
		"meta": _cloud_meta(),
		"med": {"got": medals.duplicate(), "best": medal_best.duplicate()},
		"opst": {"tk": roster_tickets.duplicate(), "sp": roster_spare.duplicate(), "wish": roster_wish, "pity": roster_pity, "draws": roster_draws, "seed": roster_seed},
		"rv": roster_v}, true)
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
	for k in ["dmg_numbers", "hitstop", "boss_intro", "reduce_motion", "outline", "pad_rumble"]:   # 旧档 / 云档里的 manual_attack（10-31 取消手动普攻）不读，忽略
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
		if mt.get("bought") is Dictionary:
			meta_bought = (mt.bought as Dictionary).duplicate()
		if mt.get("bounty") is Array:
			meta_bounty = mt.bounty.map(func(x): return int(x))
		if mt.get("shape") is Dictionary:
			meta_shape = (mt.shape as Dictionary).duplicate()
		if mt.get("t") is float or mt.get("t") is int:
			meta_shape_t = int(mt.t)
		var M = load("res://scripts/core/meta.gd")
		if M.spent(meta_shape) > M.budget():
			meta_shape = {}   # 采用的认知塑造超出余额（另一台设备的进度还没同步过来）：整组重置，重置免费
	if p.get("dbest") is Dictionary:
		diff_best = (p.dbest as Dictionary).duplicate(true)
	if p.get("med") is Dictionary:
		# 蚀刻章：合并后的正文已是两边并集（CloudPack.merge_med）；这里只收类型对的项。本版不认识的章 key 也留着（新版本加的章不丢）
		var mg = p.med.get("got", {})
		if mg is Dictionary:
			var got := {}
			for k in mg:
				if mg[k] is int or mg[k] is float:
					got[str(k)] = int(mg[k])
			medals = got
		var mb = p.med.get("best", {})
		if mb is Dictionary:
			var best := {}
			for k in mb:
				if mb[k] is int or mb[k] is float:
					best[str(k)] = int(mb[k])
			medal_best = best
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
	# 旧版本写的云档（没有 rv ≥ 2、但有名册段 opst）：当时开局 5 人不进 ops，这里补上，免得新设备读旧云档丢了开局 5 人
	if p.has("opst") and int(p.get("rv", 0)) < 2:
		_roster_add_starters()
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


## 全部解锁（调试 / 对内包）时：界面用的那份是全开的演示数据，真实进度在 _real_progress。
## 新达成的结局 / 新获得的藏品也记进真实进度（蚀刻章按它判，docs/134）；没开全部解锁时什么都不做（调用方已经记过）
func note_real(list_name: String, id: String) -> void:
	if not unlock_all or not (_real_progress.get(list_name) is Array):
		return
	var a: Array = _real_progress[list_name]
	if not a.has(id):
		a.append(id)
		save()


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

