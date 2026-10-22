extends Control
## 标题界面 · 共用部分（docs/126 C2，10-22 由 title.gd 原样拆出）：常量、成员状态与几个共用小函数。
## 继承链：title_base → title_op_pick（选人页）→ title_diff_pick（难度页）→ title.gd（标题主体、菜单、操作说明、致谢）。
## 各段之间按成员 / 函数名直接互调；选人页调难度页的 _diff_step 走下面的占位（title_diff_pick 覆盖）

const UI = preload("res://scripts/ui.gd")
const Affects = preload("res://scripts/run/affects.gd")
const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Character = preload("res://scripts/characters/character.gd")
const Roster = preload("res://scripts/core/roster.gd")   # 干员解锁（docs/109 §12）：选人页只列已解锁的干员（选封面干员时列全部）
const Game = preload("res://scripts/game.gd")
const InitialStats = preload("res://scripts/screens/initial_stats.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const DifficultyScreen = preload("res://scripts/screens/difficulty_screen.gd")
const Tiles = preload("res://scripts/screens/title_tiles.gd")
## 选人页的职业顺序（docs/23 §11.1）
const CLASS_ORDER: Array = D.CLASS_ORDER

## 菜单项（T5s 磁贴群，docs/67 §12）：0 集结出发 / 1 图鉴 / 2 Boss 演练 / 3 操作说明 / 4 设置 / 5 退出 / 6 认知塑造；
## 文字、图标、分行都在 screens/title_tiles.gd 的 MENU 表（docs/126 A2），这里只管按 id 打开（_activate）
const ITEMS: Array = Tiles.MENU

var font: Font
var tex_player: Texture2D
var tex_light: Texture2D
var tex_tiles: Texture2D
var tex_bg: Texture2D
var tex_logo: Texture2D
var player_frames := 1
var t := 0.0
var sel := 0
var item_rects: Array = []
var menu_lay := {}            # 磁贴群排版（title_tiles.layout，_draw 里按当前尺寸算）
var menu_boss := true         # 有没有「Boss 演练」（_ready 按 Cfg.can_boss_trial()；测试可改）
var menu_exit := true         # 有没有「退出」（网页 / --simweb 没有；测试可改）
var menu_water := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # 各磁贴水位 0–1（选中涨潮、离开退潮，T2）
var menu_rip_t := -10.0       # 选中变化的时刻（标题页时间 t）：涟漪扩散
var menu_mem_x := -1.0        # 二维导航记住的列（磁贴中心 x）
var cover_hover := false
var branches: Array = []   # [a, b, width, depth]
var nodes: Array = []      # 发光节点 [pos, phase]
var motes: Array = []
var guide := false
var credits := false
var credits_rect := Rect2()
var deploy_rect := Rect2()   # 右下「更换封面干员」
var credits_data: Dictionary = {}
var cr_scroll := 0.0         # 致谢与声明：正文滚动（目标，像素）
var cr_scroll_f := 0.0       # 显示用，逐帧逼近（拖动时相等）
var cr_max := 0.0            # 可滚动的最大量（排版时算）
var cr_view: Control         # 正文裁剪子控件：条目画在它里面，按 cr_scroll_f 平移
var cr_vr := Rect2()         # 正文可视区（标题页坐标）
var cr_bar := Rect2()        # 滚动条轨道（命中区左右各放宽）
var cr_back := Rect2()       # 钉在底部的「返回」按钮
var cr_panel := Rect2()
var cr_lay: Dictionary = {}  # 排版缓存（按正文列宽）
var cr_lay_w := -1.0
var cr_drag := 0             # 0 没按 / 1 按在正文（拖动滚动）/ 2 按在滚动条
var cr_moved := false        # 本次按下已拖过 CR_SLOP
var cr_vel := 0.0            # 松手惯性（像素 / 秒）
var cr_press := Vector2.ZERO
var leaving := -1.0
var auto_go := false        # --autotest 开窗口：等法线预热完再进局
var wait_t := 0.0           # 出发后等预热的时间（载入中…）
var settings: Control
var gallery: Control
var boss_trial: Control
var meta_ui: Control             # 认知塑造页（局外成长 P2，docs/109 §4）
var transition: Control
var overlay_was_open := false
var cover_pick := false
var diff_pick := false
var diff_sel := 0
var diff_rects := {}
var difficulty_screen = DifficultyScreen.new()
## 选开局干员（docs/23 §14 P4）：开始探索 → 选人 → 选难度；B+ 版式的其余状态在文件后部「选开局干员」一节
var op_pick := false
var op_sel := 0
var op_defs: Array = []        # [{id, def, tex, frames, lore, numbers, name, en, cls, col, vals, …}]
var op_lore: Dictionary = {}
## 开场动画：从黑暗中浮出海滩 → 标题浮现 → 菜单依次滑入；任意按键 / 点击跳过
## 标题开场（2026-09-27 用户选方案 A「潮声点灯」，要求节奏快一点，约 5 秒）：
## 0–1.2 黑场里沙滩上一粒蓝眼泪亮起、荡开涟漪；0.5 起黑幕退去、上下黑边收起，镜头从高处整像素下摇到海滩（不再非整数放大）；
## 1.6–2.5 发光脚印一枚枚亮到博士脚边，2.4 远方海嗣齐齐睁眼一瞬；2.6–3.2 青色扫光从左往右「刷」出 Logo；3.0 起副标题、菜单、页脚依次滑入。
## 第一次完整播放；看过以后（Cfg.opening_seen 写入存档）从 INTRO_SHORT 起播简短版；对局返回标题不播；任意键 / 点击 / 触屏跳过
const INTRO_LEN := 4.8
const INTRO_SHORT := 2.5
var intro := 0.0
var title_bg: Control
var map_title := ""        # 地图副标题（data/maps/<id>.json 的 title / title_en）
var map_title_en := ""


## 难度页换档（title_diff_pick 覆盖；选人页「返回」时调）
func _diff_step(_d: int) -> void:
	pass


func _prewarm() -> void:
	A.normal_maps = Cfg.normal_maps and DisplayServer.get_name() != "headless"
	A.prewarm_start(Game.preload_tex_names())


func _fa(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


func _shot_dir() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--shotdir="):
			return a.substr(10)
	return "/tmp/claude-0"
