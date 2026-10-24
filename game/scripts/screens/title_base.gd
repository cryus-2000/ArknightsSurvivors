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
const Tiles = preload("res://scripts/screens/title_jelly_menu.gd")
## 选人页的职业顺序（docs/23 §11.1）
const CLASS_ORDER: Array = D.CLASS_ORDER

## 菜单项（深海水母版，docs/67 §13）：0 集结出发 / 1 图鉴 / 2 试炼 / 3 操作说明 / 4 设置 / 5 退出 / 6 认知塑造 / 7 寻访；
## 文字、图标、位置都在 screens/title_jelly_menu.gd 的 MENU 表（docs/126 A2），这里只管按 id 打开（_activate）
const ITEMS: Array = Tiles.MENU

var font: Font
var tex_player: Texture2D
var tex_light: Texture2D
var tex_logo: Texture2D
var player_frames := 1
var t := 0.0
var sel := 0
var item_rects: Array = []
var menu_lay := {}            # 菜单排版（title_jelly_menu.layout，_draw 里按当前尺寸 / 安全区算）
var menu_boss := true         # 有没有「Boss 演练」（_ready 按 Cfg.can_boss_trial()；测试可改）
var menu_exit := true         # 有没有「退出」（网页 / --simweb 没有；测试可改）
var menu_water := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # 各项选中底条展开度 0–1（选中展开、离开收起）
var guide := false
var credits := false
var credits_rect := Rect2()
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
var hunt_ui: Control             # 寻访（screens/hunt_host.gd 把结算页的寻访盖到标题上，10-22）
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
## 标题开场（10-24 深海水母版，docs/67 §13）：0.1–1.2 黑幕退去（场景已在动）；1.0 Logo 淡入；1.25 起四个入口依次从左滑入（间隔 0.08 秒）；
## 1.6 集结出发；2.0 底部一行与声明。第一次完整播放；看过以后（Cfg.opening_seen 写入存档）从 INTRO_SHORT 起播简短版；对局返回标题不播；任意键 / 点击 / 触屏跳过
const INTRO_LEN := 2.6
const INTRO_SHORT := 1.0
var intro := 0.0
var title_bg: Control
var logo_ci: Control       # Logo 层（线性取样，title.gd _draw_logo_layer）
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
