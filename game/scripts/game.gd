extends Node2D
## 水月 · 深海幸存者 —— v0.8
## 敌人/掉落物/特效用数据数组管理，统一在 _draw 中以像素贴图绘制（美术像素 ×2）。
## 灯火是一个真实光源：场景整体偏暗，只有玩家周围被照亮。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const BossAI = preload("res://scripts/boss_ai.gd")
const RelicFx = preload("res://scripts/relic_fx.gd")
const Endings = preload("res://scripts/endings.gd")
const Knight = preload("res://scripts/allies/knight.gd")
const Touch = preload("res://scripts/touch.gd")
const Map = preload("res://scripts/world/map.gd")
const PostFx = preload("res://scripts/post_fx.gd")
const EnemyAI = preload("res://scripts/enemies/enemy_ai.gd")
const Character = preload("res://scripts/characters/character.gd")
const Squad = preload("res://scripts/characters/squad.gd")
const Doctor = preload("res://scripts/characters/doctor.gd")
const StatBlock = preload("res://scripts/core/stat_block.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）
const Bot = preload("res://scripts/core/bot.gd")       # --balance 四档机器人 + 指标采集（docs/29）
const MusicDirector = preload("res://scripts/run/music_director.gd")
const Progression = preload("res://scripts/run/progression.gd")
const Pickups = preload("res://scripts/run/pickups.gd")
const WeaponsSys = preload("res://scripts/run/weapons.gd")
const ShopSys = preload("res://scripts/run/shop.gd")
const Spawner = preload("res://scripts/run/spawner.gd")
const DemoRun = preload("res://scripts/run/demo.gd")
const AutoTest = preload("res://scripts/run/autotest.gd")
## 伤害描述符：每次造成伤害前用 _hit(src) 设置，_damage 与藏品规则只读它，不认角色。
##   src      来源名（统计与显示）        emitter  operator / summon / support / relic
##   origin   core / talent / skill / route / support / relic
##   range    近战 / 远程                 kind     物理 / 法术 / 真实（真实不吃任何倍率与防御）
##   tags     basic empowered follow_up skill aftershock area projectile beam pierce ricochet entity control dot detonation execute
## 这里只放共享来源（支援 / 藏品 / 真实）；角色专属来源由 data/characters/<id>.json 的 hit_sources 合并进来。
const HIT_BASE := {
	"援护": {"emitter": "support", "origin": "support", "range": "远程", "kind": "物理", "tags": ["projectile"]},
	"法术援护": {"emitter": "support", "origin": "support", "range": "远程", "kind": "法术", "tags": ["projectile", "area"]},
	"藏品": {"emitter": "relic", "origin": "relic", "range": "远程", "kind": "法术", "tags": ["dot"]},
	"地雷": {"emitter": "relic", "origin": "relic", "range": "远程", "kind": "物理", "tags": ["area", "detonation"]},
	"真实": {"emitter": "operator", "origin": "relic", "range": "近战", "kind": "真实", "tags": ["execute"]},
	"岁怒": {"emitter": "relic", "origin": "relic", "range": "远程", "kind": "法术", "tags": ["area"]},
	"净尘": {"emitter": "relic", "origin": "relic", "range": "远程", "kind": "法术", "tags": ["area", "dot"]},
	"食腐": {"emitter": "relic", "origin": "relic", "range": "远程", "kind": "法术", "tags": ["area"]},
}
## 「追击」（docs/35）：带这些标签的伤害吃 followup_dmg 与追击类藏品（追击、余震、殉爆、召唤物）
const FOLLOWUP_TAGS := ["follow_up", "aftershock", "detonation", "entity"]
## 美术交付的特效帧数（见 docs/05_art_handoff.md）
const FXF := {"fx_s1_burst": 6, "fx_s1_slash": 4, "fx_s2_aura": 4, "fx_s2_bind": 4, "fx_s3_aura": 6,
	"fx_s3_slash": 4, "fx_cast": 8, "fx_stun": 4, "fx_hit": 4, "fx_death": 5}
const ECOL := {"bone": Color(0.85, 0.9, 0.85), "slider": Color(0.45, 0.7, 1.0), "stone": Color(0.7, 0.7, 0.75), "offspring": Color(0.6, 0.9, 0.5),
	"brood": Color(0.9, 0.6, 0.8), "pocket": Color(0.8, 0.55, 1.0), "skimmer": Color(0.4, 0.9, 0.9), "mother": Color(0.9, 0.5, 0.7),
	"mimic": Color(1.0, 0.75, 0.4), "path": Color(0.6, 0.7, 1.0), "fractal": Color(0.6, 0.7, 1.0), "izumik": Color(0.5, 1.0, 0.7),
	"ishar": Color(0.75, 0.55, 1.0), "tear": Color(0.75, 0.55, 1.0), "iberia": Color(1.0, 0.6, 0.5), "carmen": Color(0.7, 0.7, 1.0),
	"ripper": Color(0.95, 0.55, 0.6), "burrower": Color(0.7, 0.5, 1.0), "spitter": Color(0.6, 1.0, 0.65), "hulk": Color(1.0, 0.95, 0.75),
	"bishop": Color(0.7, 1.0, 0.9), "archon": Color(0.5, 0.9, 0.9), "immortal": Color(0.6, 0.8, 1.0), "paranoia": Color(0.8, 0.6, 1.0)}

enum S { PLAY, CHOICE, PAUSE, DEAD, WIN, SHOP, SHOW, STATS, INTRO, OPENING }

const PX := 2.0                 # 1 个美术像素 = 2 个世界像素
const TILE := 32.0              # 地砖在世界中的尺寸
const MERCHANT_TIMES := [120.0, 300.0, 480.0]   # 每次都在 Boss（3:30 / 7:00 / 10:00）之前
const CELL := 48.0

var state: int = S.PLAY
var autotest_sys = AutoTest.new(self)   # 自动测试 / 平衡机器人（docs/29、docs/36）
var demo_sys = DemoRun.new(self)   # 图鉴攻击演示 / 精英化演出（gallery.gd 把 game.tscn 以 demo_op 模式放进 SubViewport）
var spawner = Spawner.new(self)   # 刷怪
var shop_sys = ShopSys.new(self)   # 商人与商店（逻辑）
var weapons_sys = WeaponsSys.new(self)   # 子弹与支援装置
var pickups = Pickups.new(self)   # 掉落与拾取
var progression = Progression.new(self)   # 升级与藏品发放（逻辑）
var music_dir = MusicDirector.new(self)   # 局内配乐调度
var rng := RandomNumberGenerator.new()
var t := 0.0

# ---------- 玩家 ----------
var ppos := Vector2.ZERO
var facing := 1.0
var rej_slow := 1.0         # 排异·深海幻境：幻境内自己也减速
var moving := false
var hp := 100.0
var max_hp := 100.0
var speed := 150.0
var pickup := 70.0
var armor := 0.0
var regen := 0.0
var dmg_mult := 1.0
var lamp_decay := 1.0
var xp_mult := 1.0
var oil_mult := 1.0
var dodge := 0.25
var invuln := 0.0
var hurt_flash := 0.0
var walk_t := 0.0
# ---- 角色动画手感（程序叠加在帧动画之上）
var p_sq := Vector2.ONE          # 当前挤压/拉伸
var p_lean := 0.0                # 前倾角
var p_off := Vector2.ZERO        # 受击后坐 / 开场位移
var p_turn := 0.0                # 转身瞬间
var p_was_moving := false
var p_last_facing := 1.0
var p_dust_t := 0.0
var p_swing_prev := 0.0
var p_hurt_prev := 0.0
var opening_t := 0.0             # 开场动画时间
const OPENING_DUR := 3.6
var swing_face := 0.0
var level := 1
var xp := 0.0
var xp_need := 8.0
var kills := 0
var lamp := 100.0

# ---------- 水月：伞击 / 天赋 / 技能 ----------
var growth := {}                 # 成长项 id -> 已选次数
var lv_times: Array = []         # 每次升级的时间点（秒），--balance 输出用（docs/23 §8）
# ---- 藏品驱动的通用倍率（scripts/relic_fx.gd 写入）
var ally_mult := 1.0             # 援护伤害
var arts_mult := 1.0             # 法术伤害（触手 / 技能 / 术师 / 辅助）
var enemy_dmg_mult := 1.0
var enemy_hp_mult := 1.0
var enemy_cd_mult := 1.0         # 敌人远程攻击间隔倍率（<1 更快）
var low_hp_bonus := 0.0          # 生命低于 50% 的敌人受伤加成
var weak_bonus := 0.0            # 弱点伤害额外加成（基础 +50%）
var regen_pct := 0.0             # 每秒回复最大生命百分比
var control_mult := 1.0          # 晕眩 / 减速持续时间倍率
var shop_price_mult := 1.0
var dmg_taken_mult := 1.0
var melee_mult := 1.0            # 近战伤害
var ranged_mult := 1.0           # 远程伤害
var phys_mult := 1.0             # 物理伤害
var arts_res := 0.0              # 法术抗性（受到的法术伤害 -x%）
var dodge_phys := 0.0            # 物理闪避（额外）
var dodge_arts := 0.0            # 法术闪避（额外）
var followup_mult := 1.0         # 追击与召唤物伤害（docs/35）
var heal_mult := 1.0             # 主控干员受到的回复效果
var corrode_taken_mult := 1.0    # 受到的侵蚀
var nerve_taken_mult := 1.0      # 神经损伤累积
var in_type: Array = ["近战", "物理"]   # 当前受到的伤害类型（受击前设置）
var dmg_type_out: Dictionary = {}     # 造成伤害按类型统计
var RL: Dictionary = {}          # 藏品表 id -> {name, cat, desc, rarity, ...}（由 relic_fx 从 data/ 读取）
var tray_cells: Array = []       # 藏品栏格子 [Rect2, id]，用于鼠标悬停提示
var stats_cells: Array = []      # Tab 面板里可悬停的格子 [Rect2, kind, id]
var rfx: RefCounted = null       # 藏品效果解释器
var sp_mult := 1.0
var flash := 0.0                 # 全屏闪光
# ---------- 藏品带来的附加能力 ----------
var grip := false
var evo_age := 35.0
var evo_xp := 2.0
var horde_log: Array = []          # 平衡测试：每次大群的统计
var seed_heal := false
var flesh_heal := false
var backlight := false
var ember := false

var relics: Array = []

# ---------- 援护干员 ----------
var weapons := {"drone": 1}      # 支援 id -> 等级（医疗无人机开局自带 Lv.1，docs/23 §17）
var intro_page := 0
var intro_dots: Array = []          # 指南页码点的点击区 [Rect2, page]
var intro_panel := Rect2()
var intro_btn_prev := Rect2()
var intro_btn_next := Rect2()
var intro_btn_skip := Rect2()
var intro_back := S.PLAY
var intro_t := 0.0
var shield := 0                  # 当前护盾层数
var shield_max := 0
var shield_every := 12.0
var shield_cd := 0.0
var shield_burst := false
var shield_heal := false
var shield_flash := 0.0          # 护盾受击闪光
var shield_pop := 0.0            # 新护盾生成动画
var pvel := Vector2.ZERO
var frame_n := 0
var lobs: Array = []             # 敌方抛射物 {from, to, t, dur, r, dmg}
var drones: Array = []           # 医疗无人机 {pos, cd, ang, beam, face}
var bullets: Array = []

# ---------- 世界 ----------
var enemies: Array = []
var gems: Array = []
var fx: Array = []
var texts: Array = []
var grid := {}
var orbit_a := 0.0
var threat := 0                  # 威胁等级（D.THREAT 下标）
var diff := 0                # 本局难度
var diff_new := false
var ending_new := false            # 本局首次达成该结局（结算面板显示）        # 本局通关解锁了新难度
var next_horde := 75.0
var horde_gap := 0.0          # 本次大群包围圈的缺口方向（弧度），预警箭头会留出这一侧
var show_queue: Array = []   # 解锁演出队列
var shop_refreshed := false  # 本次商人只能刷新一次
var seen_shows_run: Array = []  # 本局已完整播放过的解锁演出
var show_cur: Dictionary = {}
var show_t := 0.0
var show_shot := false
var horde_warn := 0.0        # 大群预警倒计时（HUD 演出）
var horde_hit := 0.0         # 大群到达后的屏幕演出
var boss = null                 # 当前显示血条的 Boss
var bosses: Array = []
var final_boss = null
var ending := "standard"
var endg: RefCounted = null        # 结局与事件箱（scripts/endings.gd）
var knight: RefCounted = null      # 猎潮的骑士同伴（scripts/allies/knight.gd）
var touch: RefCounted = null       # 触屏操作（scripts/touch.gd）
var frost := 0.0                   # 冰霜：移速 -40%
var lamp_cap := 100.0              # 灯火上限（深蓝之心后 70）
var knight_alive := false          # 猎潮的骑士在队中（结局二）
var force_boss := -1
var atk_slow := 0.0
var ebullets: Array = []
var shocks: Array = []
var warns: Array = []
var bai: RefCounted = null      # Boss AI / 招式预警（scripts/boss_ai.gd）            # Boss 招式预警 {shape, pos, ang, r, len, wid, half, t, dur, act, owner, dmg}
var mires: Array = []
var mire_tick := 0.0
var in_mire := 0.0               # 站在溟痕里的程度（0..1，平滑过渡，用于减速与屏幕变暗）
var next_mire := 100.0           # 首次溟痕时间；开局由 map 主题覆盖
# 缩圈（黑潮）
var zone_c := Vector2.ZERO
var zone_r := 99999.0
var zone_from_c := Vector2.ZERO
var zone_from_r := 99999.0
var zone_next_c := Vector2.ZERO
var zone_next_r := 0.0
var zone_phase := 0
var zone_state := 0          # 0 未开始 / 1 预告 / 2 收缩 / 3 稳定
var zone_t := 0.0
var zone_hurt_t := 0.0
const ZONE_START := 150.0
const ZONE_RADII := [1300.0, 1000.0, 780.0, 600.0, 480.0]
var merchant := {}
var merchant_idx := 0
var shop_items: Array = []
var ingots := 0
var nerve := 0.0
var pstun := 0.0
var corrode_pool := 0.0
var banner := ""
var banner_t := 0.0

# ---------- 选择面板 ----------
var choices: Array = []
var choice_kind := ""
var pending_levelups := 0
var stats: RefCounted          # 属性块（core/stat_block.gd）：藏品 / 成长 / 难度的所有数值修正都加在这里，下面的旧变量只是同步出来的缓存
var _stats_ver := -1
var squad: RefCounted          # 编队（scripts/characters/squad.gd）：博士身边的干员们
var doctor: RefCounted         # 博士层专属逻辑（scripts/characters/doctor.gd）
var ch: RefCounted             # 开局干员（squad.ops[0]）：成长 / 精英化 / HUD 在 P2 之前仍绑定在它身上
var eai: RefCounted            # 小怪行为（scripts/enemies/enemy_ai.gd），按 data/enemies.json 的 pattern 字段分派
var map: RefCounted            # 地图（scripts/world/map.gd）：铺地 / 道具 / 景物 / 碰撞 / 氛围
var draw_off := Vector2.ZERO
var foot_anchor := {}       # 美术交付的 Boss 图以脚底为锚点 # 2.5D：绘制时的高度偏移（击退腾空等）
var fg: Node2D               # 2.5D：前景视差层
var post: CanvasLayer          # 全屏后期（辉光 / 水下滤镜 / 亮度 / 受伤红边）
var dof_layer: CanvasLayer   # 2.5D：景深 / 远景水雾
var lvup_delay := 0.0     # 升级演出：延迟弹出选择面板
var lvup_show := 0.0      # 角色头顶 LEVEL UP 字样
var hud_lv_flash := 0.0   # 左上角等级闪光
var xp_flash := 0.0       # 吃到经验时经验环亮一下
var pending_chests := 0

# ---------- 节点与资源 ----------
var cam: Camera2D
var sprite: Sprite2D
var lamp_light: PointLight2D
var merchant_light: PointLight2D
var hud: Control
var panel: Control
var panel_box: HBoxContainer
var panel_col: VBoxContainer   # 事件选项条（C 版式）的竖排容器
var panel_band: ColorRect      # 选卡 / 商人 / 事件背后的灰阶压暗带（ui_band.gdshader）
var panel_fg: Control          # 标题、商人立绘、事件插画画在这层（压暗带之上、卡片之下）
var panel_sub_text := ""       # 面板标题下的一行说明（事件：剧情一句）
var serif: Font                # 事件标题用的衬线粗体（fonts/serif.ttf，缺失时退回 UI 字体）
var font: Font
var tex := {}
var panel_title_text := ""
# ---------- 打击感 ----------
var hitstop := 0.0
var shake := 0.0
var cam_kick := Vector2.ZERO
var hurt_vignette := 0.0
var tab_hint := 0.0          # 首次升级后再提醒一次 Tab
var tab_used := false
var hp_trail := 100.0        # 血条上的「被扣掉」残影
var hp_shake := 0.0
var head_bar_t := 0.0        # 头顶血条显示时长
var heart_cd := 0.0
var low_warned := false
var red_flash := 0.0
var crit_hit := false
var fx_add: Node2D
var anim_name := ""
var settings: Control
var result_btns: Array = []   # [Rect2, action]
var pause_btn := Rect2()      # 右上角暂停按钮（仅游戏中可点）
# ---- 手柄 / 键盘焦点（docs/28）：选卡 / 商店的卡片焦点、暂停与结算按钮焦点
var nav_sel := 0               # 当前焦点卡片（选卡 / 商店共用 panel_box 的下标）
var res_sel := 0               # 暂停 / 结算按钮焦点
var kb_nav := false            # 键盘方向键导航过（显示焦点而不是鼠标悬停），鼠标一动就关
var state_age := 0.0           # 进入当前状态的秒数（防止手柄连按把刚弹出的选卡 / 演出直接点掉）
var _last_state := -1
var anim_t := 0.0

# ---------- 自测 ----------
var autotest := false
var balance := false
var bot = null                   # --balance 机器人（docs/29）；--bot=afk|bad|normal|expert
var elites_killed := 0
var dmg_log := {}
var dmg_out: Dictionary = {}     # 造成的伤害按来源统计（balance 输出）
var heal_log: Dictionary = {}    # 有效治疗按来源统计（balance 输出：无人机 / 医疗干员 / 藏品 是不是保底）
var hit_src: Dictionary = {}        # 合并后的伤害来源表（HIT_BASE + 角色 hit_sources）
var hit: Dictionary = {"src": "?", "emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []}
var dmg_tag_out: Dictionary = {}    # 造成伤害按 tag 统计（Tab 面板"本局构成"）
var dmg_src := ""
var at_frames := 0
var shot_at := [3400]
var shot_dir := "/tmp/claude-0"     # 自测截图目录（--shotdir= 覆盖，Windows 本地用）
var floor_hits := 0            # --nodeath：生命归零被托住的次数
var floor_times: Array = []

# ---------- 图鉴演示（gallery.gd 把本场景放进 SubViewport，demo_op 为要演示的干员 id）----------
# 不刷怪、不掉落、不升级、没有 HUD 与音乐；按技能分段循环，每段重置干员与右侧怪海（见 _demo_step）
var demo_op := ""
var dbg_offer := {}              # 平衡输出：各干员深度卡被提供 / 被选中的次数
var dbg_pick := {}
var dbg_relic_offer: Array = []  # 平衡输出：藏品三选一 / 商店的候选（[t, 来源, [id...]]）
var dbg_relic_take: Array = []   # 平衡输出：获得的藏品（[t, id, 当时编队职业]）
var relic_out := 0.0             # 平衡输出：藏品直接造成的伤害（描述符 origin == relic）
var bal_maxt := 780.0            # --maxt=<秒>：平衡 / 冒烟测试提前结束（默认 780 = 终局 Boss 登场后再给 3 分钟）
var prof_on := false             # --prof：模拟步分段计时，结果随 BALANCE 行输出（docs/36）
var prof := {}                   # 段名 -> 累计微秒
var _prof_t := 0
var trace_every := 0.0           # --trace=<秒>：每隔几秒打印一行状态摘要（排查同 seed 能否复现，docs/36）
## 视觉随机数：火花、飘字抖动等纯表现用它。对局随机数 rng 只给玩法用——表现层按真实帧率运行，
## 如果它们共用 rng，同一个 seed 在机器忙闲不同时就会跑出不同的局（2026-09-26 查明）
var vrng := RandomNumberGenerator.new()
var headless_batch := false      # --balance 且无界面：跳过所有重绘
var demo_elite := 0            # 演示时把干员直接推到这个精英化阶段（精英化演出用）
var demo_stage := -1           # 三联对照（--compareshot）：0 = 精一前（N1 N2）/ 1 = 精二前（到 N5）/ 2 = 全部；-1 不用
var demo_basic := false        # 只普攻、不放技能（三联对照看普攻形态的成长）
var show_vp: SubViewport = null  # 精英化演出里的实机演示画面
var show_game: Node = null


func _ready() -> void:
	# 随机数最先定：招募开局干员时就会用 rng（战斗台词计时等）。以前 --seed 在 _ready 后段才生效，
	# 开局干员的台词计时是随机的，第一句台词一出同 seed 的两局就分叉（2026-09-26 查明，docs/36）
	var seeded := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
			vrng.seed = int(a.substr(7)) + 7919
			seed(int(a.substr(7)))
			seeded = true
	if not seeded:
		rng.randomize()
		vrng.randomize()
	if demo_op == "":
		Sfx.voice_reset()   # 上一局没播完的部署语音不带进新一局
	bai = BossAI.new(self)
	eai = EnemyAI.new(self)
	map = Map.new(self, Cfg.map_id)
	stats = StatBlock.new()
	stats.define_all(StatDefs.PLAYER)
	stats.define_all(StatDefs.ENEMY)
	hit_src = HIT_BASE.duplicate(true)
	doctor = Doctor.new(self)
	# 博士 JSON 的 stats 段覆盖公共属性的基础值（生命 / 回复 / 移速 / 闪避 / 拾取…）
	for k in doctor.def.get("stats", {}):
		if stats.has_stat(k):
			stats.set_base(k, float(doctor.def.stats[k]))
	squad = Squad.new(self)
	# 开局干员：标题页选人写入 Cfg.character_id；--op=<id> 测试覆盖；不存在时退回水月
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--op="):
			Cfg.character_id = a.substr(5)
	if not Character.list_ids().has(Cfg.character_id):
		Cfg.character_id = "mizuki"
	ch = squad.add(demo_op if demo_op != "" else Cfg.character_id)
	# 主控干员的受击属性（2026-09-26 用户要求，按原作换算）：JSON leader 段的 生命 / 物理减伤 / 法抗 覆盖博士 JSON 的基础值；
	# 回复、移速、闪避、拾取仍由博士 JSON 统一给
	# --noleader：平衡对照用，退回改动前「所有主控同一条血、无减伤」
	var lead: Dictionary = {} if OS.get_cmdline_user_args().has("--noleader") else ch.def.get("leader", {})
	for k in ["max_hp", "armor", "arts_res"]:
		if lead.has(k) and stats.has_stat(k):
			stats.set_base(k, float(lead[k]))
	# 博士动画条（data/doctor.json 的 sprites：idle / run / hurt / death）
	for kind in ["idle", "run", "hurt", "death"]:
		var dn = doctor.def.get("sprites", {}).get(kind, "")
		if dn is String and dn != "":
			tex[dn] = A.tex(dn)
	next_mire = float(map.mire_cfg().get("first_at", 100))
	# 无界面运行（批跑 / 冒烟）不画任何东西，法线图纯属浪费：一局启动要多花十几秒
	A.normal_maps = Cfg.normal_maps and DisplayServer.get_name() != "headless"
	rfx = RelicFx.new(self)
	endg = Endings.new(self)
	knight = Knight.new(self)
	touch = Touch.new(self)
	if D.ENEMIES.has("knight"):
		D.ENEMIES.knight.no_spawn = true  # 敌对骑士只在同伴骑士阵亡后进入精英池（每局重置）
	RL = rfx.table()
	font = load("res://fonts/ui.ttf")
	for n in ["drifter", "dart", "crawler", "shell", "boss", "tiles", "seaweed", "coral", "shell_prop", "rock",
			"gem_small", "gem_big", "oil", "chest", "slash", "tentacle", "jelly", "light", "shadow", "player",
			"ally_sniper", "ally_caster", "ally_medic", "ally_support", "orb", "doctor",
			"e_bone", "e_slider", "e_stone", "e_offspring", "e_brood", "e_pocket", "e_skimmer", "e_mother", "e_chest", "e_mimic", "e_event",
			"e_path", "e_fractal", "e_izumik", "e_ishar", "e_tear", "e_iberia", "e_carmen", "e_bishop", "e_archon", "e_immortal", "e_paranoia", "e_paranoia2", "e_bishop_feign", "e_archon_feign", "e_immortal_feign", "ebullet", "ingot", "merchant", "pickup_magnet", "pickup_heal", "drone", "drone_laser",
			"terrain_patches", "prop_pillar", "prop_wall", "prop_wreck", "terrain_ridge", "terrain_peak", "terrain_mire"]:
		tex[n] = A.tex(n)
		if n.begins_with("e_") and A.has_override(n) and tex[n] != null and tex[n].get_height() >= 32:
			foot_anchor[n] = true
		if n.begins_with("e_") and tex[n] != null:
			tex[n + "_white"] = A.white_of(tex[n]) if A.has_override(n) else A.tex(n + "_white")
	# 可选素材：有图就用，没有就用程序效果
	var optional := ["player_attack_48", "player_idle", "player_run", "player_attack", "player_hurt", "player_death", "skill_s1", "skill_s2", "skill_s3"]
	optional.append_array(FXF.keys())
	optional.append_array(["fx_umbrella_slash", "fx_umbrella_slash_awaken", "fx_umbrella_slash_mirage"])
	for rid in RL:
		optional.append("relic_" + rid)
	for pid in doctor.PASSIVES:
		optional.append("growth_" + pid)
	for wid in D.WEAPONS:
		optional.append("weapon_" + wid)
	for n in optional:
		tex[n] = A.tex(n)
	# 角色贴图集：按 data/characters/<id>.json 的 sprites / icons 覆盖 player_* / skill_s* 槽位
	for o in squad.ops:
		var sp: Dictionary = o.def.get("sprites", {})
		for kind in ["idle", "run", "attack", "skill", "hurt", "death"]:
			if sp.has(kind) and sp[kind] is String and not tex.has(sp[kind]):
				tex[sp[kind]] = A.tex(sp[kind])
		if sp.has("base"):
			tex["player"] = A.tex(sp.base)
	# 干员技能图标（skills[i].icon，可选）
	for o in squad.ops:
		for sd in o.skills_def():
			if sd.get("icon", "") != "" and tex.get(sd.icon) == null:
				tex[sd.icon] = A.tex(sd.icon)
	# 所有可招募干员的贴图集（待机 / 跑步 / 攻击）：招募卡与入队后绘制都用得到
	for cid in Character.list_ids():
		var cdef: Dictionary = Character.load_def(cid)
		var csp: Dictionary = cdef.get("sprites", {})
		for kind in ["idle", "run", "attack", "skill", "hurt", "death"] + cdef.get("extra_sprites", []):
			if csp.has(kind):
				var tn: String = csp[kind] if csp[kind] is String else csp[kind].tex
				if not tex.has(tn):
					tex[tn] = A.tex(tn)
	# 美术 V6：投射物 / 命中 / 爆炸 / 激光三段（docs/10_art_v6_spec.md）
	for n in V6_FRAMES:
		tex[n] = A.tex(n)
	# 敌人贴图按 data/enemies.json 加载：本体 + 白色剪影 + 脚底锚点，以及 _move / _attack / _charge / _death 变体（有图就用）
	var etex: Array = ["e_paranoia2"]
	for k in D.ENEMIES:
		var tn: String = D.ENEMIES[k].tex
		if not etex.has(tn):
			etex.append(tn)
	for n in etex:
		if tex.get(n) == null:
			tex[n] = A.tex(n)
			if tex[n] != null:
				tex[n + "_white"] = A.white_of(tex[n])
		if tex.get(n) != null and A.has_override(n) and tex[n].get_height() >= 32:
			foot_anchor[n] = true
		for suffix in ["_move", "_attack", "_charge", "_death"]:
			var mn: String = n + suffix
			if tex.get(mn) == null:
				tex[mn] = A.tex(mn)
				if tex[mn] != null and suffix != "_death":
					tex[mn + "_white"] = A.white_of(tex[mn])

	var cm := CanvasModulate.new()
	cm.color = map.ambient
	add_child(cm)

	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

	sprite = Sprite2D.new()
	sprite.texture = tex.player
	sprite.scale = Vector2(PX, PX)
	sprite.offset = Vector2(0, -tex.player.get_height() / 2.0)
	add_child(sprite)
	sprite.visible = false   # 2.5D：水月改由 _draw_player 在排序后绘制，节点只负责动画状态

	fx_add = Node2D.new()
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx_add.material = am
	fx_add.draw.connect(_draw_fx_add)
	add_child(fx_add)

	# 2.5D 前景视差层（镜头前的虚化海草剪影）
	fg = Node2D.new()
	fg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fg.draw.connect(func(): if Cfg.dof: map.draw_foreground(fg, get_viewport_rect().size, cam.position))
	add_child(fg)

	merchant_light = PointLight2D.new()
	merchant_light.texture = tex.light
	merchant_light.color = Color(1.0, 0.75, 0.45)
	merchant_light.energy = 1.0
	merchant_light.height = 80.0   # 法线光照：给光一个高度，否则平面法线接不到光
	merchant_light.texture_scale = 2.2
	merchant_light.visible = false
	add_child(merchant_light)

	lamp_light = PointLight2D.new()
	lamp_light.texture = tex.light
	lamp_light.color = Color(1.0, 0.86, 0.62)
	lamp_light.energy = 1.15
	lamp_light.height = 90.0
	add_child(lamp_light)

	# 2.5D 景深 / 远景水雾（在 HUD 之下）
	dof_layer = CanvasLayer.new()
	dof_layer.layer = 5
	add_child(dof_layer)
	var dof := ColorRect.new()
	dof.set_anchors_preset(Control.PRESET_FULL_RECT)
	dof.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/dof.gdshader")
	dof.material = dm
	dof_layer.add_child(dof)
	dof_layer.visible = Cfg.dof
	post = PostFx.new()
	add_child(post)

	var ul := CanvasLayer.new()
	ul.layer = 10
	add_child(ul)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ul.add_child(hud)
	hud.draw.connect(_draw_hud)
	_build_panel(ul)
	settings = preload("res://scripts/settings_panel.gd").new()
	ul.add_child(settings)
	if demo_op == "":
		Sfx.cut_target = 20000.0
		Sfx.vol_target = -4.0
		_show_banner("深海的潮水正在涌来……")
	diff = clampi(Cfg.difficulty, 0, D.DIFFICULTY.size() - 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--diff="):
			diff = int(a.substr(7))
	if diff >= 3:
		stats.add(&"light_decay", "mult", 1.25, "difficulty")
	if diff >= 9:
		stats.add(&"max_hp", "mult", 0.67, "difficulty")   # 原为定值 80（= 120 的 2/3）；主控生命因人而异后改成倍率
	_sync_stats()
	hp = max_hp
	hp_trail = hp
	xp_need = Bal.v("xp/first", 8.0)
	autotest = OS.get_cmdline_user_args().has("--autotest") or OS.get_cmdline_user_args().has("--balance")
	if demo_op != "":
		stats.add(&"sp_gain", "mult", 3.0, "demo")   # 演示：技能充能加快，几秒就能看到一次技能
		_sync_stats()
		# 精英化演出：把干员直接推进到目标阶段（精英化节点有选项时取第一个）
		var guard := 0
		while ch.elite < demo_elite and not ch.next_node().is_empty() and guard < 12:
			guard += 1
			var n: Dictionary = ch.next_node()
			var chs: Dictionary = ch.elite_choices(n) if n.get("type", "") == "elite" else {}
			ch.advance(chs.keys()[0] if not chs.is_empty() else "")
	elif OS.get_cmdline_user_args().has("--introshot"):
		_open_intro.call_deferred(S.PLAY)
	elif not autotest or OS.get_cmdline_user_args().has("--openshot"):
		_start_opening.call_deferred()
	balance = OS.get_cmdline_user_args().has("--balance")
	if balance:
		var bot_p := "normal"
		var bot_seed := 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--bot="):
				bot_p = a.substr(6)
			elif a.begins_with("--seed="):
				bot_seed = int(a.substr(7))
		bot = Bot.new(self, bot_p, bot_seed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="):
			shot_dir = arg.substr(10)
		if arg.begins_with("--shots="):
			shot_at = []
			for v in arg.substr(8).split(","):
				shot_at.append(int(v))
	if balance:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--maxt="):
				bal_maxt = float(a.substr(7))
		prof_on = OS.get_cmdline_user_args().has("--prof")
		headless_batch = DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--drawtest")
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--trace="):
				trace_every = float(a.substr(8))
			# --bosstimes=30,60,90：冒烟测试把 Boss 提前（中期 Boss × 2 + 最终 Boss），一局两分钟内跑完所有 Boss 代码
			if a.begins_with("--bosstimes="):
				D.BOSS_TIMES = Array(a.substr(12).split(",")).map(func(x): return float(x))
		OS.low_processor_usage_mode = false
		OS.low_processor_usage_mode_sleep_usec = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--forceboss="):
			force_boss = int(a.substr(12))
		# 测试：开局直接编入干员（逗号分隔 id，跟在开局干员之后）
		if a.begins_with("--squad="):
			for cid in a.substr(8).split(","):
				if squad.add(cid) != null:
					_load_op_tex(cid)
	# 测试：全队直接推进 N 个成长节点（看精英化后的技能 / 特效）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--prog="):
			for o in squad.ops:
				for k in int(a.substr(7)):
					o.advance()


var demo_origin := Vector2.INF   # 场地中心（镜头固定在这里）
var demo_phases: Array = []
var demo_pi := -1
var demo_label := ""


## 镜头看着的位置：平时跟博士；图鉴演示里固定在场地中心（map.gd 按它决定画哪些地块）
func view_center() -> Vector2:
	return demo_origin if demo_op != "" and demo_origin != Vector2.INF else ppos


# =====================================================================
# 主循环
# =====================================================================
func _process(delta: float) -> void:
	_pm("engine")   # 上一帧结束到这一帧开始：引擎自身、_draw 回调、其他节点（只在 --prof 下记）
	var dt: float = min(delta, 0.05)
	if state != _last_state:
		_last_state = state
		state_age = 0.0
		res_sel = 0
	else:
		state_age += delta
	Pad.context = "play" if state == S.PLAY else "game_menu"
	if autotest:
		_pm("")
		autotest_sys.step()
		_pm("autotest")
		dt = 0.066 if balance else 0.05
	if hitstop > 0.0 and not autotest and Cfg.hitstop:
		hitstop -= delta
	elif state == S.PLAY:
		_update(dt)
		if balance:
			# 平衡测试：每帧多跑几步模拟，绕过无界面模式的帧率上限
			for i in 7:
				if state != S.PLAY:
					break
				_pm("")
				autotest_sys.step()
				_pm("autotest")
				if state == S.PLAY:
					_update(dt)
	banner_t -= delta
	_pm("")
	_update_visuals(dt if state == S.PLAY else 0.0)
	_pm("visuals")
	music_dir.update(delta)
	_animate_cards(delta)
	if state == S.SHOW:
		show_t += delta
	if state == S.INTRO:
		intro_t += delta
	# 无界面批跑什么都不显示：不重绘世界 / 特效 / 前景 / HUD（一局省三成多耗时；docs/36 验证过结果逐字节不变）
	if not headless_batch:
		queue_redraw()
		fx_add.queue_redraw()
		fg.queue_redraw()
		dof_layer.visible = Cfg.dof
		hud.queue_redraw()
	_pm("tail")


func _do_action(act: String) -> void:
	match act:
		"resume":
			state = S.PLAY
		"settings":
			settings.open()
		"guide":
			_open_intro(S.PAUSE)
		"restart":
			get_tree().reload_current_scene()
		"title":
			get_tree().change_scene_to_file("res://main.tscn")


## 指南页的输入放在 _input：先于 GUI 控件处理，左键（或面板右半 / 下一页按钮）下一页，右键 / 面板左半 / 上一页按钮上一页，页码点可直接点
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.relative.length() > 6.0:
		kb_nav = false
	if settings.visible:
		return
	if touch.handle(event):
		get_viewport().set_input_as_handled()
		return
	if state != S.INTRO:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_close_intro()
			KEY_LEFT, KEY_A, KEY_PAGEUP, KEY_BACKSPACE:
				_intro_prev()
			_:
				_intro_next()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = hud.get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_intro_prev()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_intro_next()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var hit := false
			for d in intro_dots:
				if d[0].has_point(mp):
					intro_page = d[1]
					intro_t = 0.0
					Sfx.play("ui_move")
					hit = true
					break
			if not hit:
				if intro_btn_prev.has_point(mp):
					_intro_prev()
				elif intro_btn_skip.has_point(mp):
					_close_intro()
				elif intro_btn_next.has_point(mp):
					_intro_next()
				elif intro_panel.has_point(mp) and mp.x < intro_panel.position.x + intro_panel.size.x * 0.3:
					_intro_prev()
				else:
					_intro_next()
		get_viewport().set_input_as_handled()


func _intro_prev() -> void:
	if intro_page > 0:
		intro_page -= 1
		intro_t = 0.0
		Sfx.play("ui_move")


func _unhandled_input(event: InputEvent) -> void:
	if settings.visible:
		return
	if state == S.OPENING:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			_end_opening()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == S.PAUSE or state == S.DEAD or state == S.WIN:
			for b in result_btns:
				if b[0].has_point(event.position):
					Sfx.play("ui_ok")
					_do_action(b[1])
					return
		if state == S.PLAY and pause_btn.has_area() and pause_btn.has_point(event.position):
			Sfx.play("ui_ok", -4.0)
			state = S.PAUSE
			return
	if event is InputEventKey and event.device == Pad.SYNTH_DEVICE and state_age < 0.35 and state != S.PLAY:
		return
	if state == S.SHOW:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			_close_show()
		return
	if state == S.INTRO:
		return  # 指南的输入在 _input() 里处理（先于 GUI，不会被任何控件吞掉）
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if _nav_key(k):
		get_viewport().set_input_as_handled()
		return
	if (k == KEY_SPACE or k == KEY_SHIFT or k == KEY_K) and state == S.PLAY:
		_try_dash()
		get_viewport().set_input_as_handled()
		return
	if (k == KEY_Q or k == KEY_J) and state == S.PLAY:
		# 唯一的手动技能入口：路由到角色已解锁的 manual 技能（三自动角色无动作）
		if doctor.try_manual_skill():
			get_viewport().set_input_as_handled()
		return
	if k == KEY_TAB or k == KEY_C:
		if state == S.PLAY:
			state = S.STATS
			tab_used = true
			tab_hint = 0.0
			Sfx.play("ui_ok", -6.0)
		elif state == S.STATS:
			state = S.PLAY
		return
	if state == S.STATS:
		if k == KEY_ESCAPE:
			state = S.PLAY
		return
	if k == KEY_ESCAPE and state != S.SHOP:
		if state == S.PLAY:
			state = S.PAUSE
		elif state == S.PAUSE:
			state = S.PLAY
	elif k == KEY_O and state == S.PAUSE:
		settings.open()
	elif k == KEY_G and state == S.PAUSE:
		_open_intro(S.PAUSE)
	elif k == KEY_M:
		_show_banner("音乐：关" if Sfx.toggle_music() else "音乐：开")
	elif k == KEY_T and (state == S.DEAD or state == S.WIN or state == S.PAUSE):
		get_tree().change_scene_to_file("res://main.tscn")
	elif k == KEY_R and (state == S.DEAD or state == S.WIN or state == S.PAUSE):
		get_tree().reload_current_scene()
	elif state == S.SHOP:
		if k >= KEY_1 and k <= KEY_5:
			shop_sys.buy(k - KEY_1)
		elif k == KEY_F:
			shop_sys.refresh()
		elif k == KEY_ESCAPE or k == KEY_E:
			shop_sys.close()
	elif state == S.CHOICE and k >= KEY_1 and k <= KEY_3:
		var i: int = k - KEY_1
		if i < choices.size():
			progression.pick(i)


## 方向键 / 手柄导航：选卡与商店左右切换焦点、Enter 确认；暂停 / 结算按钮左右（上下）切换、Enter 执行。返回是否已处理
func _nav_key(k: int) -> bool:
	var dx := 0
	if k == KEY_LEFT or k == KEY_UP:
		dx = -1
	elif k == KEY_RIGHT or k == KEY_DOWN:
		dx = 1
	var enter: bool = k == KEY_ENTER or k == KEY_KP_ENTER
	if state == S.CHOICE or state == S.SHOP:
		var n: int = choices.size() if state == S.CHOICE else shop_items.size()
		if n <= 0:
			return false
		if dx != 0:
			nav_sel = (nav_sel + dx + n) % n
			kb_nav = true
			Sfx.play("ui_move")
			return true
		if enter:
			nav_sel = clampi(nav_sel, 0, n - 1)
			if state == S.CHOICE:
				progression.pick(nav_sel)
			else:
				shop_sys.buy(nav_sel)
			return true
	elif state == S.PAUSE or state == S.DEAD or state == S.WIN:
		var m: int = result_btns.size()
		if m <= 0:
			return false
		if dx != 0:
			res_sel = (res_sel + dx + m) % m
			kb_nav = true
			Sfx.play("ui_move")
			return true
		if enter:
			Sfx.play("ui_ok")
			_do_action(result_btns[clampi(res_sel, 0, m - 1)][1])
			return true
	return false


## 卡片是否"被选中"：用手柄 / 方向键时看焦点，否则看鼠标悬停
func _card_hot(card: Button, i: int) -> bool:
	if Pad.using or kb_nav:
		return i == nav_sel
	return card.is_hovered()


## 主控冲刺（2026-09-26 用户要求）：空格 / Shift / K / 手柄 B·RB / 触屏「冲刺」按钮。沿移动方向（站着不动时沿朝向）
## 0.18 秒冲出约 126 像素，全程无敌；冷却 1.2 秒。残影由干员的动态模糊（character.gd ghosts）自动产生
const DASH_TIME := 0.18
const DASH_SPEED := 700.0
const DASH_CD := 1.2
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var last_mv := Vector2.ZERO


func _try_dash() -> void:
	if dash_cd > 0.0 or dash_t > 0.0 or pstun > 0.0 or state != S.PLAY:
		return
	dash_dir = (last_mv if moving and last_mv != Vector2.ZERO else Vector2(facing, 0)).normalized()
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	dash_used = true
	invuln = maxf(invuln, DASH_TIME + 0.05)
	fx.append({"kind": "ring", "pos": ppos, "r": 36.0, "life": 0.25, "max": 0.25, "col": ch.col() if ch != null else UI.CYAN})
	Sfx.play("dodge", -6.0, 1.2, 0.05)


func _update(dt: float) -> void:
	_pm("")
	t += dt
	_sync_stats()
	var mv := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if demo_op != "":
		mv = demo_sys.wander()
	elif balance:
		mv = bot.move(dt) if bot != null else autotest_sys.bot_move()
	elif touch.active and touch.move_vec() != Vector2.ZERO:
		mv = touch.move_vec()
	elif Pad.move_vec() != Vector2.ZERO:
		mv = Pad.move_vec()   # 手柄左摇杆（模拟量）/ 十字键
	elif autotest:
		mv = Vector2.from_angle(t * 0.4)
	moving = mv != Vector2.ZERO
	if pstun > 0.0:
		mv = Vector2.ZERO
	moving = mv != Vector2.ZERO
	if moving:
		mv = mv.normalized() * minf(mv.length(), 1.0)   # 键盘斜向归一；手柄半推 = 慢走
		walk_t += dt * 12.0
		if mv.x != 0.0 and swing_face <= 0.0:
			facing = sign(mv.x)
	# 溟痕：陷在里面移动速度 -45%
	var mspd: float = speed * (1.0 - 0.45 * in_mire) * rej_slow * (0.6 if frost > 0.0 else 1.0)
	pvel = mv * mspd
	ppos += mv * mspd * dt
	# 冲刺：主控沿冲刺方向高速位移，期间无敌（被僵直时不能冲刺，已在 _try_dash 里拦）
	dash_cd = maxf(0.0, dash_cd - dt)
	if dash_t > 0.0:
		dash_t -= dt
		ppos += dash_dir * DASH_SPEED * dt
		pvel = dash_dir * DASH_SPEED
		invuln = maxf(invuln, 0.05)
	last_mv = mv if moving else last_mv
	if tex.get("prop_pillar") != null:
		ppos = map.push_out(ppos, 12.0)
	swing_face -= dt

	var rg: float = (regen + regen_pct * max_hp) * heal_mult * dt
	if hp + rg > max_hp:
		rfx.on_overheal(hp + rg - maxf(hp, max_hp))
	hp = min(max_hp, hp + rg)
	if lamp <= 0.0:
		hp -= 3.0 * dt
		hurt_flash = max(hurt_flash, 0.05)
	_update_zone(dt)
	if shield_max > 0 and shield < shield_max:
		shield_cd -= dt
		if shield_cd <= 0.0:
			shield += 1
			shield_cd = shield_every
			shield_pop = 0.4
			Sfx.play("relic", -12.0, 1.6, 0.0)
	shield_flash = maxf(0.0, shield_flash - dt)
	shield_pop = maxf(0.0, shield_pop - dt)
	invuln -= dt
	hurt_flash -= dt

	frame_n += 1
	_pm("pre")
	if demo_op != "":
		demo_sys.step(dt)
	else:
		spawner.update(dt)
	_pm("spawn")
	_build_grid()
	_pm("grid")
	_update_enemies(dt)
	_pm("enemies")
	squad.update(dt)
	_pm("squad")
	weapons_sys.update(dt)   # 支援无人机：跟随博士，与编队里有谁无关
	knight.update(dt)
	touch.update(dt)
	weapons_sys.update_bullets(dt)
	_pm("bullets")
	_update_ebullets(dt)
	bai._update_warns(dt)
	_pm("ebullets")
	_update_status(dt)
	rfx.tick(dt)
	_pm("relic")
	endg.update(dt)
	endg.tick_final_warning()
	if ending == "knight" and knight.alive and t >= 585.0 and knight.state != "walk":
		knight.walk_to_center(zone_c if zone_state != 0 else ppos + Vector2(0, -220))
	if demo_op == "":
		shop_sys.update(dt)
	pickups.update(dt)
	_pm("misc")
	_update_fx(dt)
	_pm("fx")
	_cleanup()
	_pm("cleanup")

	if not horde_log.is_empty():
		var hl0: Dictionary = horde_log[horde_log.size() - 1]
		if t - hl0.t < 20.0:
			hl0.minhp = minf(hl0.minhp, hp)
	if balance and OS.get_cmdline_user_args().has("--nodeath"):
		if hp <= 0.0:
			floor_hits += 1   # 本该死掉的次数：不死模式下的生存压力指标（docs/27 §6）
			floor_times.append(int(t))
		hp = maxf(hp, max_hp * 0.5)
	if hp <= 0.0 and squad.prevent_death():
		hp = 1.0   # 幽灵鲨「求生之渴」：博士生命不会低于 1
	if hp <= 0.0 and not rfx.on_death():
		hp = 0.0
		state = S.DEAD
		Pad.rumble(0.6, 1.0, 0.6)
		return
	if final_boss != null and final_boss.dead:
		state = S.WIN
		endg.on_win()
		if not balance and diff >= Cfg.diff_unlocked and Cfg.diff_unlocked < D.DIFFICULTY.size() - 1:
			Cfg.diff_unlocked = diff + 1
			Cfg.save()
			diff_new = true
		return
	_check_pending()


func _check_pending() -> void:
	if state != S.PLAY or demo_op != "":
		return
	if not show_queue.is_empty():
		_open_show(show_queue.pop_front())
		return
	if pending_chests > 0:
		progression.open_relic_choice()
	elif pending_levelups > 0 and lvup_delay <= 0.0:
		progression.open_levelup()


# =====================================================================
# 刷怪
# =====================================================================


# =====================================================================
# 敌人
# =====================================================================
func _build_grid() -> void:
	grid.clear()
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if e.dead:
			continue
		var k := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		if grid.has(k):
			grid[k].append(i)
		else:
			grid[k] = [i]


func _query(pos: Vector2, radius: float) -> Array:
	var out: Array = []
	var x0 := floori((pos.x - radius) / CELL)
	var x1 := floori((pos.x + radius) / CELL)
	var y0 := floori((pos.y - radius) / CELL)
	var y1 := floori((pos.y + radius) / CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var k := Vector2i(cx, cy)
			if grid.has(k):
				out.append_array(grid[k])
	if out.size() > 0 and out.max() >= enemies.size():
		out = out.filter(func(j): return j < enemies.size())
	return out


func _update_enemies(dt: float) -> void:
	var dark_mod := 1.2 if lamp < 30.0 else 1.0
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		if e.dead:
			continue
		e.age += dt
		e.flash -= dt
		e.jhit -= dt
		e.stun -= dt / control_mult
		e.squash -= dt
		e.slow -= dt / control_mult
		if e.get("wind", 0.0) > 0.0:
			e.wind -= dt
		if e.get("pose", 0.0) > 0.0:
			e.pose -= dt
		if e.get("haste", 0.0) > 0.0:
			e.haste -= dt
		if e.get("aura_weak", 0.0) > 0.0:
			e.aura_weak -= dt
		if e.get("lit", 0.0) > 0.0:
			e.lit -= dt
		if e.get("requiem", 0.0) > 0.0:
			e.requiem -= dt
		# 流血（狙击干员）：每 0.5 秒结算一次
		if e.get("bleed", 0.0) > 0.0:
			e.bleed -= dt
			e["bleed_t"] = e.get("bleed_t", 0.0) + dt
			if e.bleed_t >= 0.5:
				e.bleed_t = 0.0
				_hit("援护")
				_damage(e, e.bleed_dps * 0.5)
				fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-6, 6), -4), "vel": Vector2(0, 60), "sz": 2.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.05, 0.1)})
				if e.dead:
					continue
		# 侵蚀（排异·无解困境）：受控敌人每 0.5 秒受一次触手法术伤害
		if e.get("corr_t", 0.0) > 0.0:
			e.corr_t -= dt
			e["corr_tick"] = e.get("corr_tick", 0.0) + dt
			if e.corr_tick >= 0.5:
				e.corr_tick = 0.0
				_hit("触手", ["corrode"])
				_damage(e, e.corr_dmg)
				fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-8, 8), -6), "vel": Vector2(0, -40), "sz": 2.5, "life": 0.45, "max": 0.45, "col": Color(1.2, 0.6, 1.6)})
				if e.dead:
					continue
		var to: Vector2 = ppos - e.pos
		var dist := to.length()
		var dir: Vector2 = to / max(dist, 0.001)
		if abs(dir.x) > 0.1 and e.ai != "static":
			e.fx = sign(dir.x)

		if e.chest:
			if dist > 1500.0:
				e.dead = true
			continue
		if dist > 1300.0 and not e.boss:
			if e.ai == "static":
				e.dead = true
			else:
				e.pos = spawner.edge_pos()
			continue

		if not e.evo and not e.elite and not e.boss and e.ai != "static" and e.age > evo_age * maxf(0.55, 1.0 - t / 900.0):
			_evolve(e)

		# 注亡拟嗣：生命持续流失
		if e.type == "brood":
			e.hp -= e.maxhp * 0.08 * dt
			if e.hp <= 0.0:
				e.dead = true
				continue
		if e.boss:
			bai._boss_ai(e, dt, dir, dist)
		if e.dead:
			continue

		# ---- 移动
		var v: Vector2 = e.kb * (0.3 if D.ENEMIES[e.type].get("heavy", false) else 1.0)
		var spd: float = e.spd * dark_mod * (0.65 if e.slow > 0.0 else 1.0)
		if e.get("channel", 0.0) > 0.0 or e.get("coma", false) or e.get("wind", 0.0) > 0.0:
			spd = 0.0
		if e.get("haste", 0.0) > 0.0:
			spd *= 1.4
		var move_dir := dir
		if e.feed and final_target_valid(e):
			move_dir = (e.feed_to.pos - e.pos).normalized()
		elif e.get("aggro", Vector2.INF) != Vector2.INF:
			# 海嗣分身吸引仇恨：本帧朝分身走（每帧由分身重新标记）
			move_dir = (e.aggro - e.pos).normalized()
			e.aggro = Vector2.INF
		var ov: Vector2 = eai.pattern(e, dir, dist, dt, spd) if e.stun <= 0.0 else Vector2.INF
		if ov != Vector2.INF:
			v += ov
		elif e.stun <= 0.0:
			match e.ai:
				"melee":
					v += move_dir * spd
				"ranged":
					e.set_t -= dt
					if e.get("hover", false) == false and D.ENEMIES[e.type].get("entrench", false) and not e.set_done and dist < e.range:
						# 固海凿石者：首次接敌时原地架起，大幅提高防御
						e.set_done = true
						e.set_t = 20.0
						e.weak = "法术"
						_add_text(e.pos + Vector2(0, -24), "架起 · 法术弱点", Color(0.75, 0.8, 0.9), 14)
					if e.set_t > 0.0:
						pass
					elif dist > e.range * 0.85:
						v += dir * spd
					if e.set_t <= 0.0 and e.set_done:
						e.weak = D.ENEMIES[e.type].get("weak", "")
					e.cdt -= dt
					if spd > 0.0 and dist < e.range and e.cdt <= 0.0:
						e.cdt = e.cd
						eai.shoot(e, dir)
		e.kb = e.kb.move_toward(Vector2.ZERO, 900.0 * dt)

		# ---- 分离 + 吞噬
		if e.ai != "static":
			for j in _query(e.pos, e.r + 20.0):
				if j == i:
					continue
				var o: Dictionary = enemies[j]
				if o.dead:
					continue
				var diff: Vector2 = e.pos - o.pos
				var d := diff.length()
				var min_d: float = e.r + o.r
				if d < min_d and d > 0.01:
					if e.evo and not o.evo and not o.elite and not o.boss and not o.chest and o.ai != "static" and d < e.r and rng.randf() < 0.015:
						e.hp += o.hp
						e.maxhp += o.maxhp
						e.r = min(e.r + 1.5, 32.0)
						e.xp += o.xp
						o.dead = true
						_add_text(e.pos, "吞噬", Color(1.0, 0.4, 0.5))
						if seed_heal:
							_heal(max_hp * 0.05, "藏品")
						continue
					# 伊祖米克的子代被 Boss 吸收
					if e.feed and o.type == "izumik" and o.phase == 1:
						e.dead = true
						o.hp = min(o.maxhp, o.hp + o.maxhp * 0.08)
						_add_text(o.pos + Vector2(0, -50), "吸收", Color(0.5, 1.0, 0.6), 16)
						break
					if not e.boss:
						e.pos += diff / d * (min_d - d) * 0.3
			if e.dead:
				continue
		e.pos += v * dt
		if not e.boss and e.ai != "static" and (i + frame_n) % 2 == 0:
			e.pos = map.push_out(e.pos, e.r * 0.8)

		# ---- 囊海爬行者：每失去 15% 生命爆发一次。有 0.4 秒鼓胀预警，爆发之间至少隔 1.2 秒（高输出下不会连爆秒人）
		if e.has("burst_at"):
			e.burst_cd = maxf(0.0, e.get("burst_cd", 0.0) - dt)
			if e.get("burst_w", 0.0) > 0.0:
				e.burst_w -= dt
				if e.burst_w <= 0.0:
					fx.append({"kind": "ring", "pos": e.pos, "r": 80.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.45, 1.0)})
					Sfx.play("tentacle", -2.0, 0.7)
					if dist < 80.0:
						in_type = ["近战", "法术"]
						_enemy_hit(e.dmg * 0.5, {"corrode": 0.0, "nerve": 12.0}, true)
			elif e.hp <= e.burst_at and e.burst_cd <= 0.0:
				e.burst_at -= e.maxhp * 0.15
				e.burst_w = 0.4
				e.burst_cd = 1.2

		# ---- 接触伤害
		if e.dmg > 0.0 and (e.ai == "melee" or e.type == "brood") and dist < e.r + 12.0 and not e.get("coma", false) and e.get("air", 0.0) <= 0.0 and not e.get("under", false):
			if D.ENEMIES[e.type].get("morph", false):
				_morph(e)
				continue
			if invuln <= 0.0:
				dmg_src = "contact_" + e.type
				in_type = ["近战", "物理"]
				# 底海滑动者冲刺撞击：熄灭灯火
				if e.type == "slider" and e.get("dash_t", 0.0) > 0.0:
					lamp = maxf(0.0, lamp - 8.0)
					_add_text(ppos + Vector2(20, -60), "灯火 -8", Color(1.0, 0.6, 0.4), 14)
				if e.type in ["knight", "knight_boss"] and e.get("dash_t", 0.0) > 0.0:
					frost = maxf(frost, 2.0)
					_add_text(ppos + Vector2(20, -60), "冰霜", Color(0.7, 0.9, 1.4), 14)
				_enemy_hit(e.dmg * dark_mod, e)
		# 伊莎玛拉之泪：站在上面持续受到真实伤害
		if e.type == "tear" and dist < e.r + 14.0:
			hp -= 6.0 * dt
			hurt_flash = max(hurt_flash, 0.05)


func final_target_valid(e: Dictionary) -> bool:
	return e.has("feed_to") and e.feed_to != null and not e.feed_to.dead


## 伊祖米克的子代：碰到水月就蜕变成其他敌人
func _morph(e: Dictionary) -> void:
	e.dead = true
	fx.append({"kind": "ring", "pos": e.pos, "r": 40.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 1.0, 0.6)})
	_add_text(e.pos + Vector2(0, -24), "蜕变", Color(0.6, 1.0, 0.6), 16)
	for k in 2:
		spawner.spawn_enemy(["bone", "slider", "stone"][rng.randi() % 3], e.pos + Vector2.from_angle(rng.randf() * TAU) * 20.0)


func _update_lobs(dt: float) -> void:
	for l in lobs:
		l.t += dt
		if l.t >= l.dur:
			fx.append({"kind": "explode", "pos": l.to, "r": l.r, "life": 0.35, "max": 0.35, "col": Color(0.5, 0.9, 0.5) if l.get("mire", false) else Color(0.8, 0.7, 0.55)})
			if l.get("mire", false) and mires.size() < 32:
				mires.append({"pos": l.to, "r": 12.0, "maxr": 44.0, "life": 7.0, "seed": rng.randf() * 100.0})
			_sparks(l.to, Vector2.ZERO, Color(0.75, 0.7, 0.6), 8, 200.0)
			Sfx.play("boom", -14.0, 1.6, 0.1)
			if l.to.distance_to(ppos) < l.r + 8.0 and invuln <= 0.0:
				dmg_src = "bullet"
				in_type = ["远程", "法术"]
				_enemy_hit(l.dmg * Bal.v("enemy/bullet_dmg_mult", 1.0), {})
	lobs = lobs.filter(func(l): return l.t < l.dur)


func _update_ebullets(dt: float) -> void:
	_update_lobs(dt)
	for b in ebullets:
		if b.life <= 0.0:
			continue
		if b.get("home", false):
			var want: Vector2 = (ppos + Vector2(0, -14) - b.pos).normalized() * b.vel.length()
			b.vel = b.vel.lerp(want, clampf(dt * 1.6, 0.0, 1.0))
		b.pos += b.vel * dt
		b.life -= dt
		var hitp: bool = b.pos.distance_to(ppos + Vector2(0, -14)) < b.r + 12.0
		if b.get("mire", false) and (hitp or b.life <= 0.0) and mires.size() < 32:
			mires.append({"pos": b.pos + Vector2(0, 10), "r": 10.0, "maxr": 52.0, "life": 10.0, "seed": rng.randf() * 100.0})
		if hitp:
			b.life = 0.0
			if b.get("slow", false):
				atk_slow = 3.0
			dmg_src = "bullet"
			in_type = ["远程", "真实" if b["true"] else b.get("atk", "法术")]
			if invuln <= 0.0:
				_enemy_hit(b.dmg * Bal.v("enemy/bullet_dmg_mult", 1.0), b, b["true"])


## 敌人命中水月：闪避判定、侵蚀、神经损伤
func _enemy_hit(dmg: float, src: Dictionary, ignore_armor := false, no_dodge := false) -> void:
	if demo_op != "":
		return
	if not no_dodge and in_type[1] != "真实" and rng.randf() < min(dodge + (dodge_arts if in_type[1] == "法术" else dodge_phys), 0.6):
		invuln = 0.3
		Sfx.play("dodge", -4.0)
		_add_text(ppos + Vector2(0, -80), "闪避", Color(0.6, 0.85, 1.0), 16)
		on_dodge()
		return
	if shield > 0:
		_shield_block()
		return
	for o in squad.ops:
		if o.has_method("dmg_taken_mult"):
			dmg *= o.dmg_taken_mult()
	_hurt(dmg * (1.15 if lamp < 30.0 else 1.0), ignore_armor)
	# 灯火只在受击时熄灭：基础 4 + 伤害占最大生命的比例 × 30（10% 血的一击 -7），受「灯火消耗」修正
	var lamp_loss: float = (Bal.v("lamp/hit_base", 4.0) + Bal.v("lamp/hit_scale", 30.0) * dmg / max_hp) * lamp_decay
	lamp = maxf(0.0, lamp - lamp_loss)
	if lamp_loss >= 6.0:
		_add_text(ppos + Vector2(20, -60), "灯火 -%d" % int(lamp_loss), Color(1.0, 0.6, 0.4), 13)
	if src.get("corrode", 0.0) > 0.0:
		corrode_pool += dmg * src.corrode * Bal.v("enemy/corrode_mult", 2.0) * corrode_taken_mult
		_add_text(ppos + Vector2(14, -64), "侵蚀", Color(0.8, 0.5, 1.0), 13)
	if src.get("nerve", 0.0) > 0.0:
		_add_nerve(src.nerve * nerve_taken_mult)


func on_dodge() -> void:
	rfx.on_dodge()


func _add_nerve(v: float) -> void:
	nerve += v
	if nerve >= 100.0:
		nerve = 0.0
		pstun = 0.4
		atk_slow = maxf(atk_slow, 2.5)
		dmg_src = "nerve"
		in_type = ["近战", "真实"]
		_hurt(max_hp * 0.08, true)
		_add_text(ppos + Vector2(0, -100), "神经损伤！", Color(1.0, 0.5, 0.9), 20)
		Sfx.play("skill", -4.0, 1.6)


## 玩家身上的持续状态：侵蚀掉血、神经损伤衰减、溟痕
func _update_status(dt: float) -> void:
	pstun -= dt
	atk_slow -= dt
	frost = maxf(0.0, frost - dt)
	nerve = max(0.0, nerve - 6.0 * dt)
	if corrode_pool > 0.0:
		var tick: float = min(corrode_pool, (corrode_pool * 0.5 + 1.0) * dt)
		corrode_pool -= tick
		hp -= tick
		dmg_log["corrode"] = dmg_log.get("corrode", 0.0) + tick
	var mired := false
	var sanct: bool = squad.in_sanctuary(ppos)   # 流明灯塔：区内溟痕失效
	for m in mires:
		m.life -= dt
		m.r = min(m.maxr, m.r + 5.0 * dt)
		if m.pos.distance_to(ppos) < m.r and not sanct:
			mired = true
	# 溟痕：减速 + 屏幕变暗 + 持续掉血（2.5/秒）+ 神经损伤
	in_mire = move_toward(in_mire, 1.0 if mired else 0.0, dt * (4.0 if mired else 2.5))
	if mired:
		# 溟痕侵蚀：每 0.5 秒结算一次（3 + 1.5% 最大生命），带飘字与轻微红闪
		mire_tick -= dt
		if mire_tick <= 0.0:
			mire_tick = 0.5
			var md: float = 3.0 + max_hp * 0.015
			hp -= md
			dmg_log["mire"] = dmg_log.get("mire", 0.0) + md
			red_flash = maxf(red_flash, 0.08)
			hp_shake = 0.2
			hurt_flash = maxf(hurt_flash, 0.06)
			_add_text(ppos + Vector2(randf_range(-10, 10), -80), "-%d 溟痕" % int(md), Color(0.85, 0.45, 1.0), 15)
		head_bar_t = maxf(head_bar_t, 0.6)
	else:
		mire_tick = 0.0
	mires = mires.filter(func(m): return m.life > 0.0)
	for s in shocks:
		s.r += 320.0 * dt
		if not s.hit and abs(s.pos.distance_to(ppos) - s.r) < 22.0:
			s.hit = true
			if invuln <= 0.0:
				pstun = max(pstun, 0.5)
				dmg_src = "shock"
				in_type = ["近战", "物理"]
				_enemy_hit(s.dmg, {}, true, true)
	shocks = shocks.filter(func(s): return s.r < s.maxr)


func _evolve(e: Dictionary) -> void:
	e.evo = true
	e.maxhp *= 1.8
	e.hp = e.maxhp
	e.r *= 1.3
	e.spd *= 1.15
	e.dmg *= 1.5
	e.xp *= evo_xp
	fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.0, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.3, 0.4)})


func _hurt(amount: float, ignore_armor := false) -> void:
	if in_type[1] != "真实":
		amount *= rfx.taken_mult()
	if not ignore_armor and in_type[1] == "物理":
		amount = max(1.0, amount - armor)
	elif in_type[1] == "法术":
		amount = max(1.0, amount * (1.0 - minf(arts_res, 0.7)))
	hp -= amount
	rfx.on_hurt(dmg_src == "nerve")
	dmg_log[dmg_src] = dmg_log.get(dmg_src, 0.0) + amount
	invuln = 0.45
	hurt_flash = 0.2
	# 受击反馈按伤害占最大生命的比例分级
	var sev := clampf(amount / max_hp / 0.12, 0.0, 1.0)
	hurt_vignette = 0.6 + 0.4 * sev
	red_flash = maxf(red_flash, 0.12 + 0.25 * sev)
	hp_shake = 0.35
	head_bar_t = 2.5
	_shake(0.55 + 0.8 * sev)
	hitstop = max(hitstop, 0.045 + 0.06 * sev)
	Sfx.play("hurt", -1.0 + 3.0 * sev, 1.0 - 0.2 * sev, 0.05)
	Pad.rumble(0.25 + 0.35 * sev, 0.1 + 0.6 * sev, 0.12 + 0.12 * sev)
	_sparks(ppos + Vector2(0, -24), Vector2.UP, Color(1.0, 0.3, 0.35), 6 + int(8 * sev), 220.0)
	fx.append({"kind": "ring", "pos": ppos + Vector2(0, -10), "r": 40.0 + 30.0 * sev, "life": 0.25, "max": 0.25, "col": Color(1.0, 0.3, 0.35)})
	_add_text(ppos + Vector2(randf_range(-14, 14), -84), "-%d" % int(amount), Color(1.0, 0.3, 0.3), int(20 + 10 * sev))
	# 首次跌破 30%：时间短暂变慢 + 警告
	if hp > 0.0 and hp < max_hp * 0.3 and not low_warned:
		low_warned = true
		hitstop = max(hitstop, 0.35)
		_show_banner("生命垂危！")
	elif hp > max_hp * 0.45:
		low_warned = false


## 缩圈：预告 20 秒 → 收缩 25 秒 → 稳定，直到下一轮；圈外为「黑潮」
func _update_zone(dt: float) -> void:
	if zone_state == 0:
		if t < ZONE_START:
			return
		zone_c = ppos
		zone_r = ZONE_RADII[0] + 400.0
		zone_phase = -1
		zone_state = 3
		zone_t = 0.0
	zone_t += dt
	match zone_state:
		3:
			if zone_t >= (0.0 if zone_phase < 0 else 45.0) and zone_phase < ZONE_RADII.size() - (2 if ending == "resolve" else 1):
				zone_phase += 1
				zone_next_r = ZONE_RADII[zone_phase]
				var off := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, (zone_r - zone_next_r) * 0.7)
				zone_next_c = zone_c + off
				zone_state = 1
				zone_t = 0.0
				_show_banner("黑潮将至：%d 秒后安全区缩小" % 20)
				Sfx.play("roar", -6.0, 0.5, 0.0)
		1:
			if zone_t >= 20.0:
				zone_state = 2
				zone_t = 0.0
				zone_from_c = zone_c
				zone_from_r = zone_r
				_show_banner("黑潮正在逼近！")
		2:
			var k := clampf(zone_t / 25.0, 0.0, 1.0)
			zone_c = zone_from_c.lerp(zone_next_c, k)
			zone_r = lerpf(zone_from_r, zone_next_r, k)
			if k >= 1.0:
				zone_state = 3
				zone_t = 0.0
	# 圈外：黑潮伤害 + 灯火流失 + 神经损伤
	var out := ppos.distance_to(zone_c) - zone_r
	if out > 0.0 and state == S.PLAY and not squad.in_sanctuary(ppos):
		var dps: float = (2.5 + 1.5 * max(zone_phase, 0)) * (1.0 + minf(out / 300.0, 1.0))
		hp -= dps * dt
		dmg_log["zone"] = dmg_log.get("zone", 0.0) + dps * dt
		lamp = maxf(0.0, lamp - 6.0 * dt)
		zone_hurt_t -= dt
		if zone_hurt_t <= 0.0:
			zone_hurt_t = 0.8
			hurt_flash = maxf(hurt_flash, 0.08)
			head_bar_t = 2.0
			_add_text(ppos + Vector2(0, -84), "黑潮", Color(0.8, 0.4, 1.0), 16)


func _in_zone(p: Vector2, margin := 0.0) -> bool:
	return zone_state == 0 or p.distance_to(zone_c) < zone_r - margin


## 护盾抵挡一次伤害：碎裂特效，可选冲击波与回复
func _shield_block() -> void:
	shield -= 1
	shield_flash = 0.3
	invuln = 0.5
	if shield < shield_max and shield_cd <= 0.0:
		shield_cd = shield_every
	Sfx.play("dodge", -2.0, 1.4, 0.0)
	_add_text(ppos + Vector2(0, -84), "护盾抵挡", Color(0.6, 0.9, 1.0), 16)
	# 碎片
	for k in 14:
		fx.append({"kind": "shard", "pos": ppos + Vector2(0, -24), "vel": Vector2.from_angle(randf() * TAU) * randf_range(120, 260),
			"life": 0.5, "max": 0.5, "rot": randf() * TAU})
	fx.append({"kind": "ring", "pos": ppos + Vector2(0, -20), "r": 50.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 0.9, 1.0)})
	if shield_heal:
		_heal(max_hp * 0.03, "藏品")
	if shield_burst:
		for j in _query(ppos, 140.0):
			var e: Dictionary = enemies[j]
			if not e.dead and e.pos.distance_to(ppos) < 140.0:
				_damage(e, 30.0 * dmg_mult)
				if not e.boss:
					e.kb += (e.pos - ppos).normalized() * 420.0
		fx.append({"kind": "explode", "pos": ppos, "r": 140.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.85, 1.0)})
		_shake(0.6)


## 属性块 → 旧变量缓存。stat 名见 core/stat_defs.gd；战斗代码继续读旧变量，所有修改都走 stats.add()
const STAT_SYNC := {
	&"dmg": "dmg_mult", &"physical_dmg": "phys_mult", &"arts_dmg": "arts_mult", &"melee_dmg": "melee_mult", &"ranged_dmg": "ranged_mult",
	&"regen": "regen", &"regen_pct": "regen_pct", &"armor": "armor", &"dodge": "dodge", &"dodge_phys": "dodge_phys", &"dodge_arts": "dodge_arts",
	&"arts_res": "arts_res", &"weak_bonus": "weak_bonus", &"move_speed": "speed", &"pickup": "pickup", &"dmg_taken": "dmg_taken_mult",
	&"sp_gain": "sp_mult", &"control_dur": "control_mult", &"light_decay": "lamp_decay", &"oil_gain": "oil_mult", &"xp_gain": "xp_mult",
	&"shop_price": "shop_price_mult", &"ally_dmg": "ally_mult", &"shield_interval": "shield_every",
	&"enemy_hp": "enemy_hp_mult", &"enemy_dmg": "enemy_dmg_mult",
	&"followup_dmg": "followup_mult", &"heal_mult": "heal_mult", &"corrode_taken": "corrode_taken_mult", &"nerve_taken": "nerve_taken_mult",
}


func _sync_stats() -> void:
	if stats == null or stats.version == _stats_ver:
		return
	_stats_ver = stats.version
	for k in STAT_SYNC:
		set(STAT_SYNC[k], stats.value(k))
	# 有换算的几项
	enemy_cd_mult = 1.0 / maxf(0.1, stats.value(&"enemy_atk_speed"))
	low_hp_bonus = stats.value(&"enemy_low_hp_dmg_taken") - 1.0
	var new_max: float = maxf(20.0, stats.value(&"max_hp"))
	if new_max != max_hp:
		hp = clampf(hp + maxf(new_max - max_hp, 0.0), 0.0, new_max)
		max_hp = new_max
	var new_shield: int = int(stats.value(&"shield_max"))
	if new_shield != shield_max:
		if shield_max == 0 and new_shield > 0:
			shield_cd = 1.0
		shield_max = new_shield
	squad.sync_stats(stats)


## 灯火：灯光照亮范围（游戏判定用）
func _lamp_r() -> float:
	return lerpf(110.0, 360.0, lamp / 100.0) * squad.light_radius_mult()


func _lamp_sp() -> float:
	return (1.3 if lamp >= 70.0 else 1.0) * rfx.sp_extra()


## 用对局随机数洗牌。Array.shuffle() 走全局随机流，全局流也被纯视觉效果按真实帧率消耗，会让同 seed 的局跑出不同结果
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## --prof：把上一次打点到现在的耗时记到 k 名下（k 为空只重置起点）
func _pm(k: String) -> void:
	if not prof_on:
		return
	var now := Time.get_ticks_usec()
	if k != "":
		prof[k] = int(prof.get(k, 0)) + (now - _prof_t)
	_prof_t = now


## 这次伤害是否算「追击」（docs/35）
func is_followup(h: Dictionary) -> bool:
	for tg in h.tags:
		if tg in FOLLOWUP_TAGS:
			return true
	return false


## 敌人生命的时间倍率（不含难度）：藏品的直接伤害按它缩放，保证各时段同样「有感」
func enemy_hp_time_mult() -> float:
	var hk: float = Bal.v("enemy/hp_knee", 480.0)
	return 1.0 + minf(t, hk) / Bal.v("enemy/hp_div", 120.0) + maxf(t - hk, 0.0) / Bal.v("enemy/hp_late_div", 300.0)


## 设置当前伤害描述符（extra_tags 追加本次特有标签，如 empowered）
func _hit(src: String, extra_tags: Array = []) -> void:
	var base: Dictionary = hit_src.get(src, {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []})
	hit = {"src": src, "emitter": base.emitter, "origin": base.origin, "range": base.range, "kind": base.kind, "tags": base.tags + extra_tags,
		"class": base.get("class", ""), "op": base.get("op", "")}


## 本局造成伤害的构成（按来源前三，占比），Tab 面板与结算用
func _dmg_mix_text() -> String:
	var total := 0.0
	for k in dmg_out:
		total += dmg_out[k]
	if total <= 0.0:
		return "—"
	var ks: Array = dmg_out.keys()
	ks.sort_custom(func(a, b): return dmg_out[a] > dmg_out[b])
	var parts: Array = []
	for i in mini(3, ks.size()):
		parts.append("%s %d%%" % [ks[i], int(round(dmg_out[ks[i]] / total * 100.0))])
	return " · ".join(parts)


func _damage(e: Dictionary, dmg: float) -> void:
	if e.dead:
		return
	# 灯火照亮：光中的敌人受到的伤害 +25%（流明光弹的「照亮」e.lit 同样视为在灯光内）
	if e.pos.distance_squared_to(ppos) < _lamp_r() * _lamp_r() or e.get("lit", 0.0) > 0.0:
		dmg *= 1.25
	if e.invuln:
		if texts.size() < 80 and vrng.randf() < 0.2:
			_add_text(e.pos + Vector2(0, -e.r - 10), "无效", Color(0.6, 0.7, 0.8), 13)
		return
	if e.chest and e.hidden:
		e.hidden = false
		spawner.reveal_mimic(e)
		return
	var ty: Array = [hit.range, hit.kind]
	var weak_hit := false
	if ty[1] != "真实":
		dmg *= e.def * rfx.dmg_extra()
		# 弱点：对应类型伤害 +50%（藏品可加成 / 赋予双弱点）
		var wk: String = e.get("weak", "")
		if wk == ty[1] or (wk == "双" and ty[1] != "真实") or (rfx.rule("all_weak") > 0):
			dmg *= 1.5 + weak_bonus
			weak_hit = true
		dmg *= melee_mult if ty[0] == "近战" else ranged_mult
		if e.get("aura_weak", 0.0) > 0.0:
			dmg *= 1.1
		dmg *= arts_mult if ty[1] == "法术" else phys_mult
		if is_followup(hit):
			dmg *= followup_mult * rfx.followup_extra()
		dmg *= rfx.hit_mult(hit)
		# Logos「安魂」：受到的法术伤害 +15%
		if ty[1] == "法术" and e.get("requiem", 0.0) > 0.0:
			dmg *= 1.15
		if low_hp_bonus > 0.0 and e.hp < e.maxhp * 0.5:
			dmg *= 1.0 + low_hp_bonus
		if e.boss and final_boss != null and is_same(e, final_boss):
			dmg *= 1.0 + 0.01 * rfx.rule("final_taken") + (0.8 if rfx.rule("bone_blood") > 0 else 0.0)
	rfx.on_hit(e, hit)
	e.hp -= dmg
	var eff: float = minf(dmg, maxf(e.hp + dmg, 0.0))
	dmg_out[hit.src] = dmg_out.get(hit.src, 0.0) + eff
	if hit.origin == "relic":
		relic_out += eff
	dmg_type_out[ty[1]] = dmg_type_out.get(ty[1], 0.0) + eff
	for tg in hit.tags:
		dmg_tag_out[tg] = dmg_tag_out.get(tg, 0.0) + eff
	e.hits += 1
	e.flash = 0.08
	e.squash = 0.14
	if texts.size() < 80 and Cfg.dmg_numbers:
		if crit_hit:
			_add_text(e.pos + Vector2(rng.randf_range(-6, 6), -e.r - 10), str(int(round(dmg))), UI.GOLD, 22)
		elif weak_hit:
			_add_text(e.pos + Vector2(rng.randf_range(-6, 6), -e.r - 12), "弱点 " + str(int(round(dmg))), Color(1.0, 0.85, 0.35), 18)
		else:
			_add_text(e.pos + Vector2(rng.randf_range(-6, 6), -e.r - 8), str(int(round(dmg))), Color(1, 1, 1, 0.95), 14)
	# 圣徒装填时被打断
	if e.get("channel", 0.0) > 0.0:
		e.channel = 0.0
		e.stun = 6.0
		e.ammo = 0
		e.ai = "melee"
		_add_text(e.pos + Vector2(0, -50), "装填被打断！", UI.GOLD, 20)
		_shake(0.5)
	# "偏执泡影"：首次被控制后失去悬浮，进入第二形态
	if e.type == "paranoia" and e.phase == 1 and e.stun > 0.3:
		e.phase = 2
		e.range = 400.0
		e.weak = "物理"
		e.dmg *= 1.2
		_show_banner("\"偏执泡影\" 失去悬浮 —— 第二形态")
		Sfx.play("roar", 0.0, 1.2, 0.0)
	# 掠海漂移体被控制后落地，改为近战
	if e.get("hover_lost", false) == false and D.ENEMIES.has(e.type) and D.ENEMIES[e.type].get("hover", false) and e.stun > 0.3:
		e.hover_lost = true
		e.ai = "melee"
		e.spd = 70.0
		_add_text(e.pos + Vector2(0, -30), "坠落", Color(0.6, 0.9, 1.0), 16)
	if e.hp <= 0.0:
		# 最后的骑士：第一次归零不死，寒冰重生（二阶段）
		if e.type == "knight_boss" and e.phase == 1:
			e.phase = 2
			e.hp = e.maxhp * 0.5
			e.spd *= 1.2
			e.invuln = true
			e.channel = 1.5
			e.stun = 0.0
			e.kb = Vector2.ZERO
			if not _fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), PX * 1.4, 0.0):
				fx.append({"kind": "ring", "pos": e.pos, "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.9, 1.4)})
			_show_banner("寒冰重生 —— 最后的骑士 第二阶段")
			Sfx.play("roar", 0.0, 0.9, 0.0)
			_shake(1.2)
			return
		if D.ENEMIES.get(e.type, {}).get("pair", false) and e.get("partner") != null and not e.partner.dead:
			e.hp = 1.0
			e.coma = true
			e.invuln = true
			e.stun = 0.0
			_add_text(e.pos + Vector2(0, -50), "昏迷（同时击倒另一体）", Color(0.6, 1.0, 0.9), 16)
			return
		_kill(e)


## 播放美术交付的帧动画特效；素材不存在时返回 false，由调用方使用程序效果
func _anim(name: String, pos: Vector2, dur: float, scale := PX, follow := false) -> bool:
	if tex.get(name) == null:
		return false
	fx.append({"kind": "anim", "name": name, "pos": pos, "life": dur, "max": dur, "scale": scale, "follow": follow})
	return true


## 镜头震动已整体移除（看着头疼）：保留入口以免各处调用改动，一律不震
func _shake(_a: float) -> void:
	pass


func _sparks(pos: Vector2, dir: Vector2, col: Color, n: int, spd: float) -> void:
	if fx.size() > 400:
		return
	for i in n:
		var a := vrng.randf() * TAU if dir == Vector2.ZERO else dir.angle() + vrng.randf_range(-0.7, 0.7)
		fx.append({"kind": "spark", "pos": pos, "vel": Vector2.from_angle(a) * spd * vrng.randf_range(0.4, 1.0),
			"life": vrng.randf_range(0.18, 0.32), "max": 0.3, "col": col, "sz": 2.0 if vrng.randf() < 0.6 else 4.0})


func _heal(v: float, src: String = "其他") -> void:
	v *= heal_mult
	var got: float = minf(v, maxf(0.0, max_hp - hp))
	heal_log[src] = float(heal_log.get(src, 0.0)) + got
	if v > got:
		rfx.on_overheal(v - got)
	hp = min(max_hp, hp + v)


func _kill(e: Dictionary) -> void:
	rfx.on_kill(e)
	if e.dead:
		return
	e.dead = true
	# 海嗣祭坛：打开事件选项
	if e.chest and e.get("event", "") != "":
		Sfx.play("relic", -2.0, 0.8)
		_sparks(e.pos, Vector2.UP, Color(0.5, 0.8, 1.4), 18, 260.0)
		fx.append({"kind": "rays", "pos": e.pos, "life": 0.7, "max": 0.7, "col": Color(0.5, 0.8, 1.0)})
		endg.open(e.event)
		return
	# 补给箱被打碎
	if e.chest:
		Sfx.play("relic", -6.0, 1.3)
		_sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 12, 220.0)
		for k in rng.randi_range(3, 6):
			pickups.drop(e.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 18.0), "ingot", 1.0)
		if rng.randf() < 0.3:
			pickups.drop(e.pos + Vector2(10, 6), "oil", 15.0)
		return
	if e.type != "tear":
		kills += 1
	if e.has("horde") and e.horde < horde_log.size():
		var hl: Dictionary = horde_log[e.horde]
		hl.killed += 1
		if hl.t80 < 0 and hl.killed >= int(hl.n * 0.8):
			hl.t80 = int(t) - hl.t
	var col: Color = ECOL.get(e.type, Color(0.6, 0.9, 0.9))
	_sparks(e.pos, Vector2.ZERO, col, 7, 160.0)
	fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 1.2, "life": 0.18, "max": 0.18, "col": col})
	Sfx.play("kill", -8.0)
	if e.get("tex_death", false) and V6_FRAMES.has(e.tex + "_death"):
		var dtx: Texture2D = tex[e.tex + "_death"]
		var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * PX)
		_fx_sprite(e.tex + "_death", foot + Vector2(0, -(dtx.get_height() - 3) * PX * 0.5), PX, 0.0)
	elif not _fx_sprite("fx_death_dissolve", e.pos, PX * max(1.0, e.r / 12.0)):
		_anim("fx_death", e.pos, 0.3, PX * max(1.0, e.r / 12.0))
	if e.elite:
		elites_killed += 1
	if e.elite or e.boss:
		Sfx.play("boom", 0.0, 1.0, 0.0)
		hitstop = max(hitstop, 0.12)
		_shake(1.0)
		_sparks(e.pos, Vector2.ZERO, UI.GOLD, 24, 320.0)
	squad.on_kill(e)
	if flesh_heal and e.evo:
		_heal(max_hp * 0.03, "藏品")
	if ember and e.elite:
		lamp = min(lamp_cap, lamp + 20.0)
	if e.xp > 0.0:
		pickups.drop(e.pos, "xp", e.xp * xp_mult)
	if rng.randf() < 0.012 * (0.5 if diff >= 3 else 1.0):
		pickups.drop(e.pos + Vector2(8, 0), "oil", 15.0)
	# 特殊道具：磁铁 / 回复（小怪低概率，精英与 Boss 必掉其一）
	if e.elite or e.boss:
		pickups.drop(e.pos + Vector2(-16, 8), "magnet" if rng.randf() < 0.5 else "heal", 1.0)
	elif pickups.count_items() < 3:
		var r := rng.randf()
		if r < 0.0025:
			pickups.drop(e.pos, "magnet", 1.0)
		elif r < 0.006:
			pickups.drop(e.pos, "heal", 1.0)
	var ing: int = D.ENEMIES.get(e.type, {}).get("ingots", 0)
	if e.elite:
		ing = max(ing, rng.randi_range(3, 5))
		pickups.drop(e.pos, "chest", 1.0)
		pickups.drop(e.pos + Vector2(20, 10), "oil", 25.0)
	if e.boss:
		ing = 20
		if not is_same(e, final_boss) and not spawner.boss_alive():
			Sfx.play_overlay("boss_down")   # 最终 Boss 走结算乐句；双 Boss 需全部倒下
		pickups.drop(e.pos + Vector2(-20, 0), "chest", 1.0)
		for j in 12:
			pickups.drop(e.pos + Vector2.from_angle(TAU * j / 12.0) * 30.0, "xp", 20.0)
		# Boss 倒下时清除它召唤的东西
		for o in enemies:
			if (o.type == "tear" and e.type == "ishar") or (o.feed and is_same(o.get("feed_to"), e)):
				o.dead = true
	if diff >= 5 and ing > 0:
		ing = int(floor(ing * 0.7 + rng.randf()))
	for k in ing:
		pickups.drop(e.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 26.0), "ingot", 1.0)


# =====================================================================
# 水月的攻击：伞击 + 天赋「创伤性癔症」+ 三个自动技能
# =====================================================================
func facing_angle() -> float:
	return 0.0 if facing >= 0.0 else PI


func _nearest(n: int, max_dist: float, origin: Vector2 = Vector2.INF) -> Array:
	if origin == Vector2.INF:
		origin = ppos
	var c: Array = []
	for j in _query(origin, max_dist):
		var e: Dictionary = enemies[j]
		if e.dead:
			continue
		var d: float = e.pos.distance_squared_to(origin)
		if d < max_dist * max_dist:
			c.append([d, e])
	c.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in min(n, c.size()):
		out.append(c[i][1])
	return out


## 扇形判定：返回 origin 周围 radius 内、与 ang 夹角不超过 half 的敌人
func _arc_hit(origin: Vector2, ang: float, half: float, radius: float) -> Array:
	var out: Array = []
	for j in _query(origin, radius + 40.0):
		var e: Dictionary = enemies[j]
		if e.dead:
			continue
		var off: Vector2 = e.pos - origin
		if off.length() > radius + e.r:
			continue
		if half < PI and abs(angle_difference(ang, off.angle())) > half + 0.15:
			continue
		out.append(e)
	return out


## 斩击 / 爪痕帧的统一缩放（2026-09-25）：帧条本身只有 28–56 像素，各干员按「命中半径 ÷ 帧宽」放大后
## 常到 4–6 倍，像素颗粒比人物（PX = 2 倍）粗一倍多，又大又糙。统一 ×0.7 再封顶 3 倍：弧光比判定略小，
## 判定范围由地面环 / 裂纹表达。_fx_sprite（fx_slash_* / fx_claw_*）与 _slash_fx 都走这里
const BLADE_SCALE_K := 0.7
const BLADE_SCALE_MAX := 3.0
const FX_SCALE_MAX := 3.2        # 所有帧条特效（碎石 / 水花 / 法阵…）的放大上限，避免颗粒比人物粗太多

func _blade_scale(sc: float) -> float:
	return minf(sc * BLADE_SCALE_K, BLADE_SCALE_MAX)


## 斩击贴图（覆盖约 126°，更宽的角度用多段拼接）
func _slash_fx(origin: Vector2, ang: float, half: float, radius: float, col: Color, tex_name := "slash", life := 0.22) -> void:
	var span := 2.2
	var segs := int(ceil(half * 2.0 / span))
	var sc := radius / 22.0
	var frames := 4
	var anchor := Vector2(0.5, 0.5)
	if tex_name.begins_with("fx_umbrella_slash"):
		# V7 伞击帧条：6 帧，锚点 (4, h/2) 在伞柄，弧半径 = 帧宽 × 0.80，弧展开约 150°
		frames = 6
		var tx: Texture2D = tex[tex_name]
		var fw := float(tx.get_width()) / 6.0
		sc = radius / (fw * 0.80)
		anchor = Vector2(4.0 / fw, 0.5)
		span = 2.5
		segs = int(ceil(half * 2.0 / span))
	sc = _blade_scale(sc)
	for k in segs:
		var a := ang
		if segs > 1:
			a = ang - half + span * 0.5 + (half * 2.0 - span) * float(k) / float(segs - 1)
		fx.append({"kind": "slash", "tex": tex_name, "pos": origin, "ang": a, "scale": sc, "life": life, "max": life, "col": col,
			"frames": frames, "anchor": anchor})


## 伞击贴图选择：有 V7 帧条就用，没有就退回旧 slash
func _slash_tex(kind := "base") -> String:
	var n := "fx_umbrella_slash"
	if kind == "awaken":
		n += "_awaken"
	elif kind == "mirage":
		n += "_mirage"
	if tex.get(n) != null:
		return n
	if kind == "awaken" and tex.get("fx_s1_slash") != null:
		return "fx_s1_slash"
	if kind == "mirage" and tex.get("fx_s3_slash") != null:
		return "fx_s3_slash"
	return "slash"


# =====================================================================
# 商人与商店
# =====================================================================


func _build_shop_ui() -> void:
	nav_sel = clampi(nav_sel, 0, maxi(0, shop_items.size() - 1))
	for c in panel_box.get_children():
		c.queue_free()
	choice_kind = "shop"
	_layout_panel("shop")
	var n := shop_items.size()
	var sep: float = 14.0 if n <= 5 else 10.0
	panel_box.add_theme_constant_override("separation", int(sep))
	var cw: float = minf(160.0, (868.0 - sep * (n - 1)) / maxf(1.0, n))
	panel_title_text = "流浪商人"
	for c in panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	var vs0: Vector2 = get_viewport_rect().size
	var cx := vs0.x / 2.0
	_panel_button("刷新货架", Rect2(cx - 280, 546, 214, 40), shop_sys.refresh, not shop_refreshed and ingots >= shop_sys.price("refresh"), "refresh", "仅一次" if not shop_refreshed else "已刷新过", -1 if shop_refreshed else shop_sys.price("refresh"))
	_panel_button("离开", Rect2(cx - 52, 546, 150, 40), shop_sys.close, true, "", "", -1, "ESC")
	for i in n:
		var it: Dictionary = shop_items[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(cw, 296)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 50)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		card.set_meta("dy", 174.0)
		card.set_meta("item", it)
		card.modulate.a = 0.0
		card.draw.connect(_draw_shop_card.bind(card, it, i))
		card.mouse_entered.connect(func(): card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(shop_sys.buy.bind(i))
		var desc := Label.new()
		desc.text = UI.soft(it.desc)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(10, 174)
		desc.size = Vector2(cw - 20, 56)
		desc.clip_text = true
		desc.max_lines_visible = 3
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.add_theme_constant_override("line_spacing", 0)
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.655, 0.69, 0.725))
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		card.set_meta("desc", desc)
		panel_box.add_child(card)
	panel.visible = true
	panel_fg.queue_redraw()


## 面板底部的按钮（商店：刷新 / 离开）：A 风格暗底细边；可带线性图标、源石锭价格、备注、按键牌。鼠标与触屏都能点
func _panel_button(text: String, r: Rect2, cb: Callable, enabled: bool, icon := "", note := "", price := -1, key := "") -> void:
	var b := Button.new()
	b.set_meta("shopbtn", true)
	b.position = r.position
	b.size = r.size
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.draw.connect(func():
		var hov: bool = b.is_hovered() and enabled
		var br := Rect2(Vector2.ZERO, b.size)
		var fg: Color = UI.TEXT if enabled else UI.SUB
		b.draw_rect(br, Color(0.03, 0.035, 0.045, 0.82))
		b.draw_rect(br, Color(1, 1, 1, 0.6 if hov else (0.3 if enabled else 0.12)), false, 1.0)
		if hov:
			b.draw_rect(br.grow(2.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), false, 1.0)
		var x := 16.0
		if icon != "":
			UI.icon(b, icon, Vector2(x + 9, b.size.y / 2.0), 18.0, fg)
			x += 26.0
		UI.text(b, font, Vector2(x, b.size.y / 2.0 + 5), text, 14, fg)
		x += font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10.0
		if price >= 0:
			b.draw_texture_rect(tex.ingot, Rect2(Vector2(x, b.size.y / 2.0 - 7), Vector2(18, 14)), false, Color(1, 1, 1, 1.0 if enabled else 0.5))
			UI.ctext(b, font, Vector2(x + 22, b.size.y / 2.0 + 7), str(price), 18, fg)
			x += 22.0 + UI.cwidth(font, str(price), 18) + 8.0
		if note != "":
			UI.text(b, font, Vector2(x, b.size.y / 2.0 + 5), note, 11, UI.SUB)
		if key != "":
			UI.keycap(b, font, Vector2(b.size.x - UI.cwidth(font, key, 11) - 28, b.size.y / 2.0 - 9), key, fg, 11))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(cb)
	panel.add_child(b)


## 货品卡（A4）：炭灰卡 + 节点标签条 + 序号 + 图标光环 + 名称 + 说明 + 底部价格条
## （可买：钢蓝，悬停青底；买不起：洋红细边 +「不足」；已售出：整卡变暗、图标去色）
func _draw_shop_card(card: Button, it: Dictionary, i: int) -> void:
	var hov: bool = _card_hot(card, i) and not it.sold
	var afford: bool = ingots >= it.price
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	var a := 0.55 if it.sold else 1.0
	if hov:
		for k in 3:
			card.draw_rect(r.grow(2.0 + k * 3.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12 - k * 0.035), false, 3.0)
	var top := Color(0.118, 0.129, 0.153, 0.95 * a)
	var bot := Color(0.059, 0.067, 0.082, 0.95 * a)
	card.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	card.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.14 * a))
	card.draw_rect(r, UI.CYAN if hov else Color(1, 1, 1, 0.11 * a), false, 1.0)
	var en_s := "SUPPLY"
	var cn_s := "补给"
	if it.kind == "relic":
		var rd: Dictionary = RL[it.id]
		en_s = UI.CAT_EN.get(rd.cat, "RELIC")
		cn_s = rd.cat
	elif it.kind == "oil":
		en_s = "LIGHT"
		cn_s = "灯火"
	var sc: Color = UI.CYAN if hov else Color(1, 1, 1, 0.88 * a)
	# 序号在底部价格条里（[ 1 ]）；标签条放不下就只留英文
	if UI.strip_width(font, en_s, cn_s, 11) > r.size.x - 20.0:
		cn_s = ""
	UI.strip(card, font, r.position + Vector2(10, 10), en_s, cn_s, sc, UI.TEXT, 11)
	if it.get("deep", false):
		UI.chip(card, font, r.position + Vector2(10, 36), "深海馈赠", Color(UI.PURPLE.r, UI.PURPLE.g, UI.PURPLE.b, a), 10)
	var c := r.position + Vector2(r.size.x / 2.0, 94)
	UI.halo(card, c, 32.0, UI.CYAN, hov, a)
	var mod := Color(1, 1, 1, a) if not it.sold else Color(0.45, 0.45, 0.45, a)
	var ic: Texture2D = tex.get("relic_" + it.id) if it.kind == "relic" else null
	if ic != null:
		_draw_icon_fit(card, ic, c, 64.0, mod)
	elif it.kind == "oil" and tex.get("oil") != null:
		_draw_icon_fit(card, tex.oil, c, 52.0, mod)
	elif it.kind == "heal" and tex.get("pickup_heal") != null:
		_draw_icon_fit(card, tex.pickup_heal, c, 56.0, mod)
	else:
		UI.text(card, font, c + Vector2(-30, 10), it.name.substr(0, 1), 28, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a), HORIZONTAL_ALIGNMENT_CENTER, 60, 3)
	var fs := 15 if font.get_string_size(it.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x <= r.size.x - 14.0 else 12
	UI.text(card, font, r.position + Vector2(0, 164), it.name, fs, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	var pb := Rect2(r.position + Vector2(10, r.size.y - 44), Vector2(r.size.x - 20, 32))
	if it.sold:
		card.draw_rect(pb, Color(1, 1, 1, 0.06))
		UI.text(card, font, Vector2(pb.position.x, pb.position.y + 21), "已售出", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, pb.size.x)
		return
	var pc := Color.WHITE
	var kc := Color(1, 1, 1, 0.7)
	if hov and afford:
		card.draw_rect(pb, UI.CYAN)
		pc = Color(0.04, 0.07, 0.09)
		kc = pc
	elif not afford:
		card.draw_rect(pb, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.12))
		card.draw_rect(pb, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.55), false, 1.0)
		pc = Color(1.0, 0.48, 0.66)
		kc = Color(1.0, 0.48, 0.66, 0.8)
	else:
		card.draw_rect(pb, Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	card.draw_texture_rect(tex.ingot, Rect2(pb.position + Vector2(10, 9), Vector2(18, 14)), false)
	UI.ctext(card, font, pb.position + Vector2(34, 24), str(it.price), 21, pc)
	if not afford:
		UI.text(card, font, pb.position + Vector2(40 + UI.cwidth(font, str(it.price), 21), 21), "不足", 11, pc)
	UI.ctext(card, font, Vector2(pb.end.x - 40, pb.position.y + 21), "[ %d ]" % (i + 1), 12, kc, HORIZONTAL_ALIGNMENT_RIGHT, 32)


# =====================================================================
# 医疗无人机（保底治疗，2026-09-25）：开局 Lv.1，不占编队位；跟在博士头顶两侧，周期性治疗博士
# Lv.1 每 6 秒 2% → Lv.2 3% / 5 秒 → Lv.3 生命 < 40% 时急救 8%（冷却 20 秒）→ Lv.4 第二架 → Lv.5 4 秒 / 清神经损伤
# =====================================================================
# 上限压到一个精零凯尔希（约 1%/秒），保证带医疗仍然值得（docs/23 §17）


## 敌人最密集的位置（在 radius 内采样）
func _densest_point(radius: float, origin: Vector2 = Vector2.INF) -> Vector2:
	var best := Vector2.INF
	var bn := 0
	var cand := _nearest(12, radius, origin)
	for c in cand:
		var n := 0
		for j in _query(c.pos, 90.0):
			if not enemies[j].dead and enemies[j].pos.distance_to(c.pos) < 90.0:
				n += 1
		if n > bn:
			bn = n
			best = c.pos
	return best


# =====================================================================
# 掉落物、特效
# =====================================================================


func _add_text(pos: Vector2, text: String, col: Color, size := 14) -> void:
	texts.append({"pos": pos, "text": text, "col": col, "life": 0.65, "max": 0.65, "size": size})


func _update_fx(dt: float) -> void:
	flash = maxf(0.0, flash - dt * 2.0)
	horde_warn = maxf(0.0, horde_warn - dt)
	tab_hint = maxf(0.0, tab_hint - dt)
	horde_hit = maxf(0.0, horde_hit - dt)
	lvup_delay -= dt
	lvup_show -= dt
	hud_lv_flash = max(0.0, hud_lv_flash - dt * 1.5)
	xp_flash = maxf(0.0, xp_flash - dt * 3.0)
	for f in fx:
		f.life -= dt
		if f.kind == "spark" or f.kind == "shard":
			f.pos += f.vel * dt
			f.vel *= 0.9
	for f in texts:
		f.life -= dt
		f.pos.y -= 30.0 * dt


func _cleanup() -> void:
	enemies = enemies.filter(func(e): return not e.dead)
	gems = gems.filter(func(g): return not g.dead)
	bullets = bullets.filter(func(b): return b.life > 0.0)
	ebullets = ebullets.filter(func(b): return b.life > 0.0)
	fx = fx.filter(func(f): return f.life > 0.0)
	texts = texts.filter(func(f): return f.life > 0.0)


func _show_banner(text: String) -> void:
	banner = text
	banner_t = 3.0


# =====================================================================
# 升级 / 藏品选择
# =====================================================================
func _build_panel(parent: Node) -> void:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 18
	panel = Control.new()
	panel.theme = theme
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	parent.add_child(panel)
	# 灰阶压暗带（方案 A，仿原作局内弹窗）：读屏幕纹理，把背后的战场变灰变暗；位置按界面类型在 _layout_panel 里设
	panel_band = ColorRect.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/ui_band.gdshader")
	panel_band.material = sm
	panel_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(panel_band)
	# 标题 / 商人立绘 / 事件插画画在这一层：在压暗带之上、卡片之下
	panel_fg = Control.new()
	panel_fg.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_fg.draw.connect(_draw_panel_bg)
	panel.add_child(panel_fg)
	panel_box = HBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 36)
	panel_box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_box.offset_top = 184
	panel_box.offset_bottom = -100
	panel.add_child(panel_box)
	# 事件选项（C 版式）：右半屏竖排的选项条
	panel_col = VBoxContainer.new()
	panel_col.add_theme_constant_override("separation", 14)
	panel_col.anchor_left = 0.5
	panel_col.anchor_right = 0.5
	panel_col.offset_left = 12
	panel_col.offset_right = 608
	panel_col.offset_top = 196
	panel_col.offset_bottom = 560
	panel_col.visible = false
	panel.add_child(panel_col)
	# 事件标题的衬线字；没导入（别的工作区的 .godot 缓存里还没有）就用 UI 字体
	var sf: Font = load("res://fonts/serif.ttf") if ResourceLoader.exists("res://fonts/serif.ttf") else null
	if sf != null:
		sf.fallbacks = [font]
		serif = sf
	else:
		serif = font


## 压暗带与卡片容器的布局：选卡在顶栏与底栏之间；商人压暗到底部；事件整屏灰阶（C 版式）
func _layout_panel(kind: String) -> void:
	var vs: Vector2 = get_viewport_rect().size
	var sm: ShaderMaterial = panel_band.material
	var top := 64.0
	var bot := vs.y - 108.0
	var fade := 34.0
	var desat := 0.85
	var dim := 0.5
	if kind == "shop":
		bot = vs.y - 56.0
	elif kind == "event":
		top = 0.0
		bot = vs.y
		fade = 0.0
		desat = 1.0
		dim = 0.46
	panel_band.position = Vector2(0, top)
	panel_band.size = Vector2(vs.x, bot - top)
	sm.set_shader_parameter("rect_size", panel_band.size)
	sm.set_shader_parameter("fade_px", fade)
	sm.set_shader_parameter("desat", desat)
	sm.set_shader_parameter("dim", dim)
	if kind == "shop":
		panel_box.anchor_left = 0.5
		panel_box.anchor_right = 0.5
		panel_box.offset_left = -280.0
		panel_box.offset_right = 588.0
		panel_box.offset_top = 234.0
	else:
		panel_box.anchor_left = 0.0
		panel_box.anchor_right = 1.0
		panel_box.offset_left = 0.0
		panel_box.offset_right = 0.0
		panel_box.offset_top = 196.0
	panel_box.visible = kind != "event"
	panel_col.visible = kind == "event"


func _draw_panel_bg() -> void:
	var vs := panel_fg.size
	match choice_kind:
		"shop":
			_draw_shop_bg(vs)
		"event":
			_draw_event_bg(vs)
		_:
			var en_label := "RELIC" if choice_kind == "relic" else "LEVEL UP"
			if choices.size() > 0 and choices[0].kind == "recruit":
				en_label = "RECRUIT"
			_panel_header(vs, en_label + "  ·  CHOOSE ONE", panel_title_text, panel_sub_text)
			var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else "点击卡片，或按 1–%d 选择" % choices.size()
			UI.text(panel_fg, font, Vector2(0, 196 + CARD_H + 30), hint, 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## 面板标题（原作「选择支援」）：英文小标签 + 大标题（两侧渐隐细线 + 靠近文字的短粗线）+ 一行说明
func _panel_header(vs: Vector2, micro: String, title: String, sub: String, y0 := 104.0) -> void:
	var c := vs.x / 2.0
	var mw := UI.en_width(font, micro, 12, 4.0)
	UI.en(panel_fg, font, Vector2(c - mw / 2.0, y0 + 12), micro, 12, UI.SUB, 4.0)
	UI.heading(panel_fg, font, Vector2(c, y0 + 36), title, 30, UI.TEXT, 290.0)
	if sub != "":
		UI.text(panel_fg, font, Vector2(0, y0 + 70), sub, 13, Color(0.67, 0.7, 0.74), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## 商人（A4）：左侧商人立绘框（暖色提灯光）+ 右上「货架」与持有源石锭 + 底部提示；五张货品卡在 panel_box
const MERCHANT_LINES := ["灯火暗下来之前，把源石锭花掉吧。", "深海里什么都能换，只要你出得起价。", "别盯着我看，看货。", "都是从沉船里捞上来的，保真。"]

func _draw_shop_bg(vs: Vector2) -> void:
	var cx := vs.x / 2.0
	_panel_header(vs, "SHOP  ·  WANDERING TRADER", "流浪商人", "在灯火熄灭之前，用源石锭换些能活下去的东西")
	var mr := Rect2(Vector2(cx - 580, 192), Vector2(280, 388))
	var mt := Color(0.125, 0.11, 0.094, 0.95)
	var mb := Color(0.055, 0.051, 0.047, 0.95)
	panel_fg.draw_polygon(PackedVector2Array([mr.position, Vector2(mr.end.x, mr.position.y), mr.end, Vector2(mr.position.x, mr.end.y)]), PackedColorArray([mt, mt, mb, mb]))
	var gc := mr.position + Vector2(mr.size.x / 2.0, 236)
	for k in 6:
		panel_fg.draw_circle(gc, 150.0 - k * 22.0, Color(1.0, 0.66, 0.31, 0.035))
	panel_fg.draw_set_transform(mr.position + Vector2(mr.size.x / 2.0, 330), 0.0, Vector2(1.0, 0.16))
	panel_fg.draw_circle(Vector2.ZERO, 76.0, Color(0, 0, 0, 0.5))
	panel_fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var mtx: Texture2D = tex.get("merchant")
	if mtx != null:
		var fw := mtx.get_width() / 2
		var fh := mtx.get_height()
		var ks: float = 5.0 / A.hires_of(mtx)
		var sz := Vector2(fw, fh) * ks
		var fr := int(t * 2.0) % 2
		panel_fg.draw_texture_rect_region(mtx, Rect2((mr.position + Vector2(mr.size.x / 2.0 - sz.x / 2.0, 334 - sz.y)).round(), sz), Rect2(fw * fr, 0, fw, fh))
	panel_fg.draw_rect(mr, Color(1, 1, 1, 0.11), false, 1.0)
	panel_fg.draw_rect(Rect2(mr.position, Vector2(14, 2)), UI.GOLD)
	UI.strip(panel_fg, font, mr.position + Vector2(12, 12), "STAY", "还会停留 %d 秒" % int(merchant.get("life", 0.0)), UI.GOLD, Color(0.95, 0.87, 0.68))
	UI.tab(panel_fg, font, mr.position + Vector2(16, 340), "流浪商人", UI.TAB_LAMP)
	UI.en(panel_fg, font, mr.position + Vector2(90, 353), "WANDERING TRADER", 10, UI.SUB, 2.0)
	UI.text(panel_fg, font, mr.position + Vector2(16, 378), "「%s」" % MERCHANT_LINES[maxi(0, merchant_idx - 1) % MERCHANT_LINES.size()], 13, Color(0.85, 0.87, 0.89))
	# 右上：货架 + 持有源石锭（明日方舟费用框）
	UI.text(panel_fg, font, Vector2(cx - 280, 216), "货架", 20, UI.TEXT)
	UI.en(panel_fg, font, Vector2(cx - 232, 214), "GOODS  ·  %d" % shop_items.size(), 12, UI.SUB, 3.0)
	var dp := Rect2(Vector2(cx + 460, 188), Vector2(128, 34))
	panel_fg.draw_rect(dp, Color(0.03, 0.035, 0.045, 0.86))
	panel_fg.draw_rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
	panel_fg.draw_texture_rect(tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false)
	UI.ctext(panel_fg, font, dp.position + Vector2(38, 27), str(ingots), 26, UI.TEXT)
	UI.text(panel_fg, font, dp.position + Vector2(84, 22), "源石锭", 10, UI.SUB)
	UI.text(panel_fg, font, Vector2(dp.position.x - 110, dp.position.y + 22), "持有", 12, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 100)
	var hint := ("←→ 选择 · Ⓐ 购买 · Ⓨ 刷新 · Ⓑ 离开" if Pad.using else "点击或按 1–%d 购买  ·  F 刷新  ·  Esc 离开" % shop_items.size())
	UI.text(panel_fg, font, Vector2(cx + 116, 571), hint, 12, UI.SUB)


## 事件（C 版式，原作「不期而遇」）：左边撕纸边灰阶墨色插画——画面里唯一的彩色物件是海嗣祭坛；
## 下方事件名（衬线粗体）+ 剧情一句；右边竖排选项条在 panel_col。插画的随机形状按事件名缓存
var ev_art := {}
var ink_tex: GradientTexture2D

func _event_art(key: String) -> Dictionary:
	if ev_art.get("key", "") == key:
		return ev_art
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var a := {"key": key, "blobs": [], "streaks": [], "dots": [], "bars": [], "ensos": []}
	a.panel = UI.jag_rect(Rect2(0, 0, 560, 500), 8.0, 12.0, rng)
	for k in 9:
		var y: float = rng.randf_range(-30.0, 60.0) if rng.randf() < 0.5 else rng.randf_range(430.0, 530.0)
		a.blobs.append(UI.blob(Vector2(rng.randf_range(-20.0, 580.0), y), rng.randf_range(40.0, 110.0), rng))
	for k in 5:
		var bp := UI.brush_poly(Vector2(rng.randf_range(-80.0, 200.0), rng.randf_range(60.0, 380.0)), rng.randf_range(260.0, 460.0), rng.randf_range(6.0, 16.0), rng)
		var rot := Transform2D(deg_to_rad(rng.randf_range(-30.0, -18.0)), Vector2.ZERO)
		var out := PackedVector2Array()
		for q in bp:
			out.append(Vector2(280, 250) + rot * (q - Vector2(280, 250)))
		a.streaks.append(out)
	for k in 18:
		a.dots.append([Vector2(rng.randf_range(20.0, 540.0), rng.randf_range(20.0, 480.0)), rng.randf_range(0.8, 3.2)])
	for k in 4:
		var bar := UI.jag_rect(Rect2(0, 0, 596, 100), 1.5, 9.0, rng, "tbl")
		for j in bar.size():
			if bar[j].x < 20.0:
				bar[j].x += rng.randf_range(-4.0, 10.0)
		a.bars.append(bar)
		a.ensos.append(UI.enso(Vector2(56, 50), 36.0, 3.0, rng))
	a.emblem = UI.curly_lines(Vector2.ZERO, 24.0 * 0.38, 24.0, 16, 24.0 * 0.14, rng)
	a.emblem_small = UI.curly_lines(Vector2.ZERO, 9.0 * 0.38, 9.0, 12, 9.0 * 0.16, rng)
	ev_art = a
	return a


func _ink_grad() -> GradientTexture2D:
	if ink_tex == null:
		var gr := Gradient.new()
		gr.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 0.88, 1.0])
		gr.colors = PackedColorArray([Color("dcd7ce"), Color("aca79e"), Color("5f5c57"), Color("1c1c1d"), Color("1c1c1d")])
		ink_tex = GradientTexture2D.new()
		ink_tex.gradient = gr
		ink_tex.fill = GradientTexture2D.FILL_RADIAL
		ink_tex.fill_from = Vector2(0.5, 0.42)
		ink_tex.fill_to = Vector2(1.08, 0.42)
		ink_tex.width = 256
		ink_tex.height = 256
	return ink_tex


func _draw_event_bg(vs: Vector2) -> void:
	var art := _event_art(panel_title_text)
	var cx := vs.x / 2.0
	var p0 := Vector2(cx - 576.0, 120.0)
	var pts: PackedVector2Array = art.panel
	var tp := PackedVector2Array()
	var uv := PackedVector2Array()
	for q in pts:
		tp.append(p0 + q)
		uv.append(Vector2(clampf(q.x / 560.0, 0.0, 1.0), clampf(q.y / 500.0, 0.0, 1.0)))
	panel_fg.draw_colored_polygon(tp, Color.WHITE, uv, _ink_grad())
	for b in art.blobs:
		panel_fg.draw_colored_polygon(_offset_poly(b, p0, tp), Color(0.047, 0.047, 0.05, 0.5))
	for s in art.streaks:
		panel_fg.draw_colored_polygon(_offset_poly(s, p0, tp), Color(0.08, 0.08, 0.085, 0.35))
	for d in art.dots:
		panel_fg.draw_circle(p0 + d[0], d[1], Color(0.047, 0.047, 0.05, 0.55))
	# 蓝色微光 + 海嗣祭坛（彩色）
	var ac := p0 + Vector2(280, 158)
	for k in 5:
		panel_fg.draw_circle(ac, 120.0 - k * 20.0, Color(0.18, 0.72, 1.0, 0.05))
	var etx: Texture2D = tex.get("e_event")
	if etx != null:
		var fw := etx.get_width() / 2
		var fh := etx.get_height()
		var ks: float = 8.0 / A.hires_of(etx)
		var sz := Vector2(fw, fh) * ks
		var fr := int(t * 2.0) % 2
		panel_fg.draw_texture_rect_region(etx, Rect2((ac - sz / 2.0).round(), sz), Rect2(fw * fr, 0, fw, fh))
	# 底部压暗，放事件名与剧情
	var g0 := Color(0.04, 0.04, 0.043, 0.0)
	var g1 := Color(0.04, 0.04, 0.043, 0.95)
	panel_fg.draw_polygon(PackedVector2Array([p0 + Vector2(6, 300), p0 + Vector2(554, 300), p0 + Vector2(554, 492), p0 + Vector2(6, 492)]), PackedColorArray([g0, g0, g1, g1]))
	var ew0 := UI.en(panel_fg, font, p0 + Vector2(92, 366), "EVENT", 12, Color(0.6, 0.59, 0.56), 3.0)
	UI.text(panel_fg, font, p0 + Vector2(92 + ew0 + 6, 366), "·  海嗣祭坛", 12, Color(0.6, 0.59, 0.56))
	var em := p0 + Vector2(54, 400)
	var emb: Array = []
	for pl in art.emblem:
		var o2 := PackedVector2Array()
		for q in pl:
			o2.append(em + q)
		emb.append(o2)
	UI.curly_emblem(panel_fg, emb, em, 24.0, Color(0.18, 0.72, 1.0))
	panel_fg.draw_string(serif, p0 + Vector2(92, 408), panel_title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	if panel_sub_text != "":
		panel_fg.draw_multiline_string(font, p0 + Vector2(92, 440), UI.soft(panel_sub_text), HORIZONTAL_ALIGNMENT_LEFT, 430, 13, 3, Color(0.81, 0.79, 0.76), UI.BRK)
	# 右侧标题
	UI.en(panel_fg, font, Vector2(cx + 20, 142), "EVENT  ·  CHOOSE ONE", 12, Color(0.6, 0.59, 0.56), 4.0)
	panel_fg.draw_string(serif, Vector2(cx + 20, 178), "做出你的选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.925, 0.91, 0.882))
	var hint := "←→ 选择 · Ⓐ 确认" if Pad.using else "点击选项，或按 1–%d" % choices.size()
	UI.text(panel_fg, font, Vector2(cx + 20, 196 + choices.size() * 114 + 20), hint, 12, Color(0.55, 0.54, 0.52))


## 墨点 / 笔触多边形平移到插画框里；超出框的部分交给撕纸边外的暗底盖住（这里只做平移）
func _offset_poly(p: PackedVector2Array, o: Vector2, _clip: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in p:
		out.append(o + Vector2(clampf(q.x, 2.0, 558.0), clampf(q.y, 2.0, 498.0)))
	return out


func _show_choices(title: String, opts: Array, kind: String, sub := "") -> void:
	choices = opts
	choice_kind = kind
	nav_sel = 0
	state = S.CHOICE
	panel_title_text = title
	panel_sub_text = sub
	if sub == "":
		if kind == "relic":
			panel_sub_text = "精英倒下后留下一只宝箱 —— 挑选一件带走"
		elif opts.size() > 0 and opts[0].kind == "recruit":
			panel_sub_text = "挑选一名干员加入编队"
		elif kind != "event":
			panel_sub_text = "选择一项强化"
	Sfx.play("relic" if kind == "relic" else "levelup", -2.0, 1.0, 0.0)
	for c in panel_box.get_children():
		c.queue_free()
	for c in panel_col.get_children():
		c.queue_free()
	_layout_panel(kind)
	var ev := kind == "event"
	for i in opts.size():
		var o: Dictionary = opts[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(596, 100) if ev else Vector2(CARD_W, CARD_H)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 70)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		if ev:
			card.set_meta("bar", true)
		card.modulate.a = 0.0
		card.draw.connect((_draw_event_bar if ev else _draw_card).bind(card, o, i))
		card.mouse_entered.connect(func(): Sfx.play("ui_move", -6.0); card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(progression.pick.bind(i))
		var desc := Label.new()
		desc.text = UI.soft(o.desc)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.clip_text = true
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_constant_override("line_spacing", 0)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ev:
			desc.position = Vector2(112, 50)
			desc.size = Vector2(420, 44)
			desc.max_lines_visible = 2
			desc.add_theme_color_override("font_color", Color(0.81, 0.79, 0.76))
			card.set_meta("dx", 112.0)
		else:
			desc.position = Vector2(20, 258)
			desc.size = Vector2(CARD_W - 40, 58)
			desc.max_lines_visible = 3
			desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			desc.add_theme_color_override("font_color", Color(0.655, 0.69, 0.725))
		card.add_child(desc)
		card.set_meta("desc", desc)
		card.set_meta("dy", 50.0 if ev else 258.0)
		(panel_col if ev else panel_box).add_child(card)
	panel.visible = true
	panel_fg.queue_redraw()


func _animate_cards(dt: float) -> void:
	if not panel.visible:
		return
	panel_fg.queue_redraw()
	var now := Time.get_ticks_msec()
	var box: BoxContainer = panel_col if (choice_kind == "event" and state == S.CHOICE) else panel_box
	for card in box.get_children():
		if not card.has_meta("born"):
			continue
		var age := (now - int(card.get_meta("born"))) / 1000.0
		var k := clampf(age / 0.32, 0.0, 1.0)
		# easeOutBack
		var c1 := 1.7
		var e := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)
		var sold: bool = card.has_meta("item") and card.get_meta("item").get("sold", false)
		var hot := _card_hot(card as Button, card.get_index()) and not sold
		var desc: Label = card.get_meta("desc", null)
		card.modulate.a = clampf(age / 0.2, 0.0, 1.0)
		if card.has_meta("bar"):
			# 事件选项条：从右侧滑入，悬停时向左探出一点
			var lift: float = lerpf(card.get_meta("lift"), -8.0 if hot else 0.0, clampf(dt * 18.0, 0.0, 1.0))
			card.set_meta("lift", lift)
			var ox := (1.0 - e) * 80.0 + lift
			card.set_meta("ox", ox)
			if desc != null:
				desc.position.x = float(card.get_meta("dx", 112.0)) + ox
		else:
			var lift2: float = lerpf(card.get_meta("lift"), -10.0 if hot else 0.0, clampf(dt * 18.0, 0.0, 1.0))
			card.set_meta("lift", lift2)
			var oy := (1.0 - e) * 60.0 + lift2
			card.set_meta("oy", oy)
			if desc != null:
				desc.position.y = float(card.get_meta("dy", 230.0)) + oy
		card.queue_redraw()


## 解锁演出的技能卡：干员 op 的第 i 个技能
func _skill_item(op, i: int) -> Dictionary:
	var sk: Dictionary = op.skill_def(i)
	return {"tag": "技能", "tag_en": "SKILL %d" % (i + 1), "glyph": sk.get("name", "技").substr(0, 1), "icon": sk.get("icon", ""), "name": sk.get("name", ""), "desc": sk.get("desc", ""), "col": op.col()}


func _open_show(sc: Dictionary) -> void:
	# 解锁演出只在第一次出现时完整播放，之后改为横幅提示
	var key: String = sc.get("head", "")
	if seen_shows_run.has(key) and not OS.get_cmdline_user_args().has("--fastlevel"):
		var names: Array = []
		for it in sc["items"]:
			names.append(it.name)
		_show_banner("%s：%s" % [key, "、".join(names)])
		fx.append({"kind": "rays", "pos": ppos, "life": 0.6, "max": 0.6, "col": sc.col})
		Sfx.play("relic", -4.0, 0.9, 0.0)
		_check_pending.call_deferred()
		return
	seen_shows_run.append(key)
	show_shot = false
	show_cur = sc
	show_t = 0.0
	state = S.SHOW
	# 精英化演出：左侧放一个实机演示（demo 模式的 game.tscn），干员已在新阶段并循环施放新解锁的技能
	_show_demo_stop()
	if sc.has("op") and int(sc.get("elite", 0)) > 0 and not balance and DisplayServer.get_name() != "headless":
		show_vp = SubViewport.new()
		show_vp.size = Vector2i(540, 300)
		show_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		show_vp.handle_input_locally = false
		add_child(show_vp)
		show_game = load("res://game.tscn").instantiate()
		show_game.demo_op = sc.op.id
		show_game.demo_elite = int(sc.elite)
		show_game.demo_skill = int(sc.elite)   # 精一 → S2（序号 1），精二 → S3（序号 2）
		show_vp.add_child(show_game)
	Sfx.play("relic", 0.0, 0.8, 0.0)
	Sfx.play("levelup", -4.0, 0.7, 0.0)


func _show_demo_stop() -> void:
	if show_vp != null:
		show_vp.queue_free()
	show_vp = null
	show_game = null


func _close_show() -> void:
	if state != S.SHOW or show_t < 1.0:
		return
	_show_demo_stop()
	show_cur = {}
	state = S.PLAY
	Sfx.play("ui_ok", -4.0)
	_check_pending()


## 解锁演出：暗场 -> 标题横幅 -> 水月演示 -> 说明卡依次滑入
func _draw_show(vs: Vector2) -> void:
	var sc := show_cur
	var st := show_t
	var col: Color = sc.col
	var fade := clampf(st / 0.3, 0.0, 1.0)
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.86 * fade))
	# 扫光带
	var sweep := clampf((st - 0.1) / 0.5, 0.0, 1.0)
	hud.draw_rect(Rect2(0, 70, vs.x * sweep, 64), Color(col.r, col.g, col.b, 0.14))
	hud.draw_rect(Rect2(0, 70, vs.x * sweep, 2), col)
	hud.draw_rect(Rect2(0, 132, vs.x * sweep, 2), Color(col.r, col.g, col.b, 0.5))
	var ha := clampf((st - 0.25) / 0.3, 0.0, 1.0)
	var hx := lerpf(-60.0, 0.0, ha)
	UI.en(hud, font, Vector2(90 + hx, 94), sc.en, 13, Color(col.r, col.g, col.b, ha), 5.0)
	UI.text(hud, font, Vector2(88 + hx, 126), sc.head + "  ·  新能力解锁", 28, Color(1, 1, 1, ha))
	# 左侧：干员演示。有实机演示画面就画它（新阶段的干员在假人堆里循环放新技能），否则退回静态挥击示意
	var cx := Vector2(330, vs.y * 0.58)
	var da := clampf((st - 0.35) / 0.35, 0.0, 1.0)
	if show_vp != null:
		var dr := Rect2(Vector2(60, 180), Vector2(540, 300))
		hud.draw_texture_rect(show_vp.get_texture(), dr, false, Color(1, 1, 1, da))
		hud.draw_rect(dr, Color(col.r, col.g, col.b, 0.6 * da), false, 2.0)
		var sop0 = sc.get("op", ch)
		var skn: String = sop0.skill_def(int(sc.get("elite", 0))).get("name", "") if sop0.has_method("skill_def") else ""
		if skn != "":
			UI.chip(hud, font, dr.position + Vector2(14, 14), "实机演示 · %s" % skn, Color(col.r, col.g, col.b, da), 11)
		var items0: Array = sc["items"]
		_draw_show_cards(items0, st)
		if st > 1.0:
			var ba0 := 0.5 + 0.5 * sin(st * 4.0)
			UI.text(hud, font, Vector2(0, vs.y - 40), "点击或按任意键继续", 15, Color(0.75, 0.88, 0.92, 0.5 + 0.5 * ba0), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		return
	for k in 3:
		var rp := fmod(st * 0.8 + k / 3.0, 1.0)
		hud.draw_arc(cx + Vector2(0, -10), 60.0 + rp * 130.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, (1.0 - rp) * 0.5 * da), 3.0)
	hud.draw_circle(cx + Vector2(0, 58), 70.0, Color(col.r, col.g, col.b, 0.08 * da))
	hud.draw_set_transform(cx + Vector2(0, 58), 0.0, Vector2(1.0, 0.3))
	hud.draw_circle(Vector2.ZERO, 60.0, Color(0, 0, 0, 0.5 * da))
	hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sop = sc.get("op", ch)
	var at: Texture2D = sop.anim_tex("attack")
	if at != null:
		var n := at.get_width() / at.get_height()
		var fh := at.get_height()
		var spd := 9.0
		var fr := int(st * spd) % n
		var S5: float = 5.0 / A.hires_of(at)
		var size := Vector2(fh, fh) * S5
		var dst := Rect2(cx - Vector2(size.x / 2.0, size.y - 60.0 + 2.0 * S5), size)
		hud.draw_texture_rect_region(at, dst, Rect2(fh * fr, 0, fh, fh), Color(1, 1, 1, da))
		# 技能特效示意
		var sl: Texture2D = tex.get("slash")
		if sl != null and fr >= 1:
			var sfw := sl.get_width() / 4
			var sfr := clampi(fr - 1, 0, 3)
			var ssz := Vector2(sfw, sl.get_height()) * 5.0
			hud.draw_texture_rect_region(sl, Rect2(cx + Vector2(-ssz.x / 2.0 + 60.0, -ssz.y / 2.0 - 70.0), ssz), Rect2(sfw * sfr, 0, sfw, sl.get_height()), Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 0.9 * da))
	# 右侧：说明卡
	_draw_show_cards(sc["items"], st)
	if st > 1.0:
		var ba := 0.5 + 0.5 * sin(st * 4.0)
		UI.text(hud, font, Vector2(0, vs.y - 40), "点击或按任意键继续", 15, Color(0.75, 0.88, 0.92, 0.5 + 0.5 * ba), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _draw_show_cards(items: Array, st: float) -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var ia := clampf((st - 0.55 - i * 0.25) / 0.3, 0.0, 1.0)
		if ia <= 0.0:
			continue
		var e := 1.0 - pow(1.0 - ia, 3)
		var r := Rect2(Vector2(620 + (1.0 - e) * 120.0, 190 + i * 190), Vector2(580, 168))
		var ic: Color = it.col
		UI.frame(hud, r, Color(ic.r, ic.g, ic.b, e), {"t": t, "vines": true, "seed": 50 + i, "vine_k": 0.6, "cut": 12.0, "bracket": 12.0, "alpha": e, "glow": 0.6 * e})
		var gc := r.position + Vector2(70, 84)
		UI.pedestal(hud, gc, 40.0, Color(ic.r, ic.g, ic.b, e), t, true)
		var itex: Texture2D = tex.get(it.get("icon", "")) if it.has("icon") else null
		if itex != null:
			hud.draw_texture_rect(itex, Rect2(gc - Vector2(32, 32), Vector2(64, 64)), false, Color(1, 1, 1, e))
		else:
			UI.text(hud, font, gc + Vector2(-40, 12), it.glyph, 30, Color(ic.r, ic.g, ic.b, e), HORIZONTAL_ALIGNMENT_CENTER, 80)
		UI.chip(hud, font, r.position + Vector2(140, 22), "新%s  ·  NEW %s" % [it.tag, it.tag_en], Color(ic.r, ic.g, ic.b, e), 11)
		UI.text(hud, font, r.position + Vector2(150, 76), it.name, 26, Color(1, 1, 1, e))
		hud.draw_multiline_string(font, r.position + Vector2(150, 106), UI.soft(it.desc), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 172, 15, 3, Color(0.78, 0.88, 0.9, e), UI.BRK)


## 卡片图标：按种类取对应贴图（relic_ / growth_ / weapon_ / evo_ / skill_），没有则返回 null
func _card_icon(o: Dictionary) -> Texture2D:
	if o.has("icon"):
		return tex.get(o.icon)
	match o.kind:
		"relic":
			return tex.get("relic_" + o.id)
		"growth":
			return tex.get("growth_" + o.id)
		"weapon":
			return tex.get("weapon_" + o.id)
		"prog":
			return tex.get(o.get("icon", ""), null) if o.get("icon", "") != "" else null
		"recruit":
			var pt: Texture2D = tex.get("ally_" + o.id)
			return pt
	return null


func _card_color(o: Dictionary) -> Color:
	if o.has("col"):
		return o.col
	match o.kind:
		"relic":
			return UI.CAT_COL.get(RL[o.id].cat, UI.GOLD)
		"recruit":
			return Color(0.55, 0.9, 0.55)
		"prog":
			if o.get("col", null) != null:
				return o.col
			return Color(0.8, 0.55, 1.0) if o.get("elite", 0) > 0 else Color(0.55, 0.85, 1.0)
		"weapon":
			return D.WEAPONS[o.id].col
	return UI.CYAN


## 选卡卡片（A3，仿原作「选择支援」）：炭灰卡 + 左上节点标签条（英文分类 + 中文）+ 右上序号 + 图标光环 + 名称 + 说明 + 底部操作条。
## 悬停 / 焦点：青色细边与外晕，标签条与操作条变青
const CARD_W := 272.0
const CARD_H := 368.0

func _draw_card(card: Button, o: Dictionary, i: int) -> void:
	var hov := _card_hot(card, i)
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	if hov:
		for k in 3:
			card.draw_rect(r.grow(2.0 + k * 3.0), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.12 - k * 0.035), false, 3.0)
	var top := Color(0.118, 0.129, 0.153, 0.95)
	var bot := Color(0.059, 0.067, 0.082, 0.95)
	card.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bot, bot]))
	card.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Color(1, 1, 1, 0.14))
	card.draw_rect(r, UI.CYAN if hov else Color(1, 1, 1, 0.11), false, 1.0)
	var tag := _card_tag(o)
	UI.strip(card, font, r.position + Vector2(14, 14), tag[0], tag[1], UI.CYAN if hov else Color(1, 1, 1, 0.88), UI.TEXT, 12)
	UI.ctext(card, font, r.position + Vector2(r.size.x - 40, 32), str(i + 1), 17, UI.TEXT if hov else Color(0.43, 0.47, 0.51), HORIZONTAL_ALIGNMENT_RIGHT, 24)
	if tag[2] != "":
		var rw := UI.cwidth(font, tag[2], 10) + 10.0
		card.draw_rect(Rect2(r.position + Vector2(14, 40), Vector2(rw, 15)), tag[3])
		UI.ctext(card, font, r.position + Vector2(19, 52), tag[2], 10, Color(0.08, 0.06, 0.02))
	# 图标 + 光环
	var c := r.position + Vector2(r.size.x / 2.0, 128)
	UI.halo(card, c, 58.0, UI.CYAN, hov)
	var name: String = o.name
	var glyph := name.substr(0, 1)
	if o.kind == "relic":
		glyph = RL[o.id].name.substr(0, 1)
	elif o.kind == "weapon":
		glyph = D.WEAPONS[o.id].glyph
	var ic: Texture2D = _card_icon(o)
	var bob := sin(t * 2.0 + i) * 2.0
	# 干员相关的卡（招募 / 成长 / 精英化 / 技能进阶）没有专属图标时，画该干员的待机第一帧
	var opid: String = o.id if o.kind == "recruit" else o.get("op", "")
	var idle: Dictionary = _op_idle(opid) if ic == null and opid != "" else {}
	if not idle.is_empty():
		var ks: float = 2.0 if idle.fh <= 48 else 96.0 / idle.fh
		var asz := Vector2(idle.fw, idle.fh) * ks
		card.draw_texture_rect_region(idle.tex, Rect2(c - asz / 2.0 + Vector2(0, bob + 4), asz), Rect2(0, 0, idle.fw, idle.fh))
	elif ic != null:
		_draw_icon_fit(card, ic, c + Vector2(0, bob), 96.0)
	else:
		UI.text(card, font, c + Vector2(-40, 13 + bob), glyph, 34, _card_color(o), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	var nm := name
	if o.kind == "relic":
		nm = RL[o.id].name
	UI.text(card, font, r.position + Vector2(0, 244), nm, 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
	# 底部操作条：普通钢蓝；悬停青底深字
	var ab := Rect2(r.position + Vector2(16, r.size.y - 44), Vector2(r.size.x - 32, 30))
	card.draw_rect(ab, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	var ink := Color(0.04, 0.07, 0.09) if hov else Color.WHITE
	var kl := "[ %d ]" % (i + 1)
	var w1 := font.get_string_size("选择", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var w2 := UI.cwidth(font, kl, 12)
	var sx := ab.get_center().x - (w1 + 8.0 + w2) / 2.0
	UI.text(card, font, Vector2(sx, ab.position.y + 20), "选择", 14, ink)
	UI.ctext(card, font, Vector2(sx + w1 + 8.0, ab.position.y + 20), kl, 12, ink if hov else Color(1, 1, 1, 0.7))


## 卡片左上角标签：[英文, 中文, 稀有度小牌, 小牌底色]
func _card_tag(o: Dictionary) -> Array:
	if o.kind == "relic" and not o.has("cat"):
		var rd: Dictionary = RL[o.id]
		var rar: String = rd.rarity
		var chip: Array = {"稀有": ["RARE", Color(0.62, 0.72, 0.85)], "核心": ["CORE", UI.GOLD], "升华": ["ASCEND", Color(0.72, 0.64, 1.0)], "遭诅古物": ["CURSED", UI.RED]}.get(rar, ["", Color.WHITE])
		return [UI.CAT_EN.get(rd.cat, "RELIC"), "%s · %s" % [rd.cat, rar], chip[0], chip[1]]
	var cat := "成长  GROWTH"
	if o.has("cat"):
		cat = o.cat
	elif o.kind == "recruit":
		cat = "招募 · " + o.get("cls", "") + "  RECRUIT"
	elif o.kind == "prog":
		cat = ("精英化  ELITE" if o.get("elite", 0) > 0 else "干员深度  OPERATOR")
	elif o.kind == "weapon":
		cat = "支援  " + D.WEAPONS[o.id].en
	# 「中文  ENGLISH」拆成两段；没有英文的整段当中文
	var parts := cat.split("  ", false)
	if parts.size() >= 2 and parts[parts.size() - 1].to_upper() == parts[parts.size() - 1]:
		var cn_s := "  ".join(parts.slice(0, parts.size() - 1))
		return [parts[parts.size() - 1], cn_s, "", Color.WHITE]
	return ["", cat, "", Color.WHITE]


## 按整数倍把像素图标放大到不超过 target 像素，居中画在 c
func _draw_icon_fit(ci: CanvasItem, tx: Texture2D, c: Vector2, target: float, mod := Color.WHITE) -> void:
	var w := float(tx.get_width())
	var h := float(tx.get_height())
	var k: float = maxf(1.0, floorf(target / maxf(w, h)))
	if maxf(w, h) > target:
		k = target / maxf(w, h)
	var sz := Vector2(w, h) * k
	ci.draw_texture_rect(tx, Rect2((c - sz / 2.0).round(), sz), false, mod)


## 事件选项条（C 版式）：左端撕边的暗条 + 墨圈里的图标 + 衬线标题 + 效果小牌 + 说明（Label）+ 右侧序号；
## 选中：浅色底 + 左侧蓝色竖条 + 蓝色序号
func _draw_event_bar(card: Button, o: Dictionary, i: int) -> void:
	var hov := _card_hot(card, i)
	var art := _event_art(panel_title_text)
	var ox: float = card.get_meta("ox", 0.0)
	var w := card.size.x
	var base := Vector2(ox, 0)
	var shape: PackedVector2Array = art.bars[i % art.bars.size()]
	var sp := PackedVector2Array()
	for q in shape:
		sp.append(base + Vector2(q.x * w / 596.0, q.y))
	card.draw_colored_polygon(sp, Color(0.925, 0.91, 0.882, 0.14) if hov else Color(0.07, 0.07, 0.075, 0.9))
	var en_ring: PackedVector2Array = art.ensos[i % art.ensos.size()]
	var er := PackedVector2Array()
	for q in en_ring:
		er.append(base + q)
	card.draw_colored_polygon(er, Color(0.925, 0.91, 0.882, 0.55 if hov else 0.22))
	var ink := Color(0.925, 0.91, 0.882)
	var icn: String = o.get("icon", "")
	var itx: Texture2D = tex.get(icn) if icn != "" and icn != "exit" else null
	if itx != null:
		_draw_icon_fit(card, itx, base + Vector2(56, 50), 64.0)
	else:
		UI.icon(card, "exit", base + Vector2(56, 50), 32.0, ink)
	card.draw_string(serif, base + Vector2(112, 38), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE if hov else ink)
	var x := 112.0 + serif.get_string_size(o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 14.0
	for chp in o.get("chips", []):
		var cw := font.get_string_size(chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
		var cr := Rect2(base + Vector2(x, 20), Vector2(cw, 18))
		card.draw_rect(cr, Color(chp[1].r, chp[1].g, chp[1].b, 0.9), false, 1.0)
		card.draw_string(font, cr.position + Vector2(6, 13), chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, chp[1])
		x += cw + 6.0
	UI.ctext(card, font, base + Vector2(w - 46, 60), str(i + 1), 24, Color(0.18, 0.72, 1.0) if hov else Color(0.37, 0.36, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 24)
	if hov:
		card.draw_rect(Rect2(base + Vector2(8, 20), Vector2(8, 60)), Color(0.18, 0.72, 1.0, 0.25))
		card.draw_rect(Rect2(base + Vector2(10, 22), Vector2(4, 56)), Color(0.18, 0.72, 1.0))


## 干员待机条的第一帧：{tex, fw, fh}（按 data/characters/<id>.json 的 sprites.idle；没有返回空）
func _op_idle(cid: String) -> Dictionary:
	if cid == "" or not Character.list_ids().has(cid):
		return {}
	var sp = Character.load_def(cid).get("sprites", {}).get("idle", null)
	if sp == null:
		return {}
	var tn: String = sp if sp is String else sp.get("tex", "")
	var tx: Texture2D = tex.get(tn)
	if tx == null:
		tx = A.tex(tn)
		tex[tn] = tx
	if tx == null:
		return {}
	var frames: int = int(sp.get("frames", 0)) if sp is Dictionary else 0
	if frames <= 0:
		frames = maxi(1, tx.get_width() / tx.get_height())
	return {"tex": tx, "fw": tx.get_width() / frames, "fh": tx.get_height()}


## 干员贴图集（运行中招募 / 测试编入时补加载）
func _load_op_tex(cid: String) -> void:
	var cdef: Dictionary = Character.load_def(cid)
	var csp: Dictionary = cdef.get("sprites", {})
	for kind in ["idle", "run", "attack", "skill"] + cdef.get("extra_sprites", []):
		if csp.has(kind):
			var tn: String = csp[kind] if csp[kind] is String else csp[kind].tex
			if tex.get(tn) == null:
				tex[tn] = A.tex(tn)


# =====================================================================
# 绘制
# =====================================================================
## 博士挂件（docs/23 v0.7）：不受击、不攻击，慢慢跑着跟在主控身后；离太远（传送 / 开局）才直接归位
const DOC_SPEED := 175.0        # 略快于主控基础移速 150，追得上但不会贴身
const DOC_BEHIND := Vector2(-40, 30)
var doc_pos := Vector2.INF
var doc_moving := false
var doc_face := 1.0


func _update_doc_follow(dt: float) -> void:
	var want: Vector2 = ppos + Vector2(DOC_BEHIND.x * facing, DOC_BEHIND.y)
	if doc_pos == Vector2.INF or doc_pos.distance_to(want) > 600.0:
		doc_pos = want
	var d: Vector2 = want - doc_pos
	var step: float = minf(d.length(), DOC_SPEED * dt * clampf(d.length() / 60.0, 0.35, 1.0))
	var mv: Vector2 = d.normalized() * step if d.length() > 1.0 else Vector2.ZERO
	doc_pos += mv
	doc_moving = mv.length() > 20.0 * dt
	if absf(mv.x) > 6.0 * dt:
		doc_face = signf(mv.x)
	elif not doc_moving:
		doc_face = facing


func _update_visuals(dt: float) -> void:
	_update_doc_follow(dt)
	var bob: float = -abs(sin(walk_t)) * 2.0 if doc_moving else 0.0
	sprite.position = (doc_pos + Vector2(0, bob + 6)).round()
	sprite.flip_h = doc_face < 0.0
	_update_player_anim(get_process_delta_time())
	_update_player_feel(get_process_delta_time())
	if state == S.DEAD:
		sprite.modulate = Color(0.5, 0.5, 0.6, 0.6)
	elif hurt_flash > 0.12:
		sprite.modulate = Color(3.0, 3.0, 3.0)
	elif hurt_flash > 0.0:
		sprite.modulate = Color(1.0, 0.4, 0.4)
	elif invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		sprite.modulate = Color(1, 1, 1, 0.6)
	else:
		sprite.modulate = Color.WHITE
	cam.position = view_center().round()
	var rd := get_process_delta_time()
	shake = move_toward(shake, 0.0, rd * 2.5)
	cam_kick = cam_kick.move_toward(Vector2.ZERO, rd * 60.0)
	hurt_vignette = move_toward(hurt_vignette, 0.0, rd * 1.5)
	red_flash = move_toward(red_flash, 0.0, rd * 2.0)
	hp_shake = move_toward(hp_shake, 0.0, rd)
	head_bar_t = move_toward(head_bar_t, 0.0, rd)
	hp_trail = move_toward(hp_trail, hp, rd * max_hp * (0.15 if hp_shake > 0.0 else 0.6))
	if hp_trail < hp:
		hp_trail = hp
	# 低血量心跳
	if state == S.PLAY and hp < max_hp * 0.3 and hp > 0.0:
		heart_cd -= rd
		if heart_cd <= 0.0:
			heart_cd = 0.55 + 0.6 * hp / (max_hp * 0.3)
			Sfx.play("heartbeat", -2.0, 1.0, 0.0)
	# 镜头震动已整体移除（见 _shake）。干员脚本里还有直接写 g.shake 的（2.5–5，按 10·shake² 就是 ±250 像素），
	# 在这里统一不用它，图鉴演示 / 精英化演出 / 实战都不再震；shake 变量只留给以后可能的非镜头用途
	cam.offset = cam_kick.round()
	# 灯火光源：半径随灯火变化，快熄灭时闪烁
	var radius: float = lerp(150.0, 520.0, lamp / 100.0) * squad.light_radius_mult()
	var flicker := 1.0 + sin(t * 13.0) * 0.02 + sin(t * 7.3) * 0.03
	if lamp < 30.0:
		flicker += sin(t * 23.0) * 0.06
	lamp_light.position = ppos + Vector2(0, -20)
	lamp_light.texture_scale = radius / 64.0 * flicker
	lamp_light.color = Color(1.0, 0.86, 0.62) if lamp >= 30.0 else Color(1.0, 0.6, 0.5)
	# 海中浮游颗粒
	map.update_snow(dt, get_viewport_rect().size)


## 以美术像素为单位绘制横向帧条中的一帧，anchor 为贴图内的锚点（0~1）
## 美术 V6 帧条：名称 -> [帧数, fps]
const V6_FRAMES := {
	"proj_arrow": [1, 0.0], "proj_fireball": [4, 12.0], "proj_arcane": [4, 12.0], "proj_drone_bullet": [1, 0.0],
	"proj_missile": [2, 16.0], "proj_tide": [4, 10.0],
	"fx_fire_explode": [6, 15.0], "fx_missile_explode": [6, 15.0], "fx_arrow_hit": [4, 20.0], "fx_bullet_hit": [3, 24.0],
	"fx_arcane_hit": [4, 20.0], "fx_tide_hit": [4, 20.0], "fx_heal_cross": [4, 10.0],
	"fx_laser_start": [4, 20.0], "fx_laser_mid": [4, 20.0], "fx_laser_end": [4, 20.0],
	# 美术 V7（docs/13_art_v7_spec.md）：触手 / 水刃 / 触手桩 / 巨触 / 受击 / 击杀
	"fx_tentacle_strike": [6, 16.0], "fx_tentacle_grab": [4, 20.0],
	"proj_tide_blade": [4, 12.0], "proj_tide_blade_moon": [4, 12.0], "proj_tide_blade_abyss": [4, 12.0], "fx_tide_blade_hit": [4, 20.0],
	"fx_tendril_stake": [4, 8.0], "fx_tendril_stake_whip": [4, 16.0], "fx_kraken_rise": [6, 12.0],
	"fx_hit_flesh": [4, 20.0], "fx_hit_shell": [4, 20.0], "fx_hit_spirit": [4, 20.0], "fx_death_dissolve": [6, 14.0],
	# 美术 V9：最后的骑士
	"e_knight_death": [4, 6.0], "fx_knight_impact": [4, 12.0], "fx_knight_rebirth": [4, 10.0],
	# 第三方开放许可素材魔改（tools/fx_import.py，docs/25 §3）：圣光 / 治疗 / 火 / 爪 / 斩 / 碎石 / 弹道
	"fx_holy_pillar": [16, 14.0], "fx_holy_pillar_amber": [16, 14.0], "fx_holy_impact": [7, 16.0],
	"fx_heal_aura_green": [5, 10.0], "fx_heal_aura_amber": [5, 10.0], "fx_circle_gold": [4, 8.0], "fx_circle_amber": [4, 8.0], "fx_shield_amber": [6, 12.0],
	"fx_flam_hit": [8, 14.0], "fx_sunburst": [16, 16.0], "proj_lavaball": [6, 12.0],
	"fx_claw_green": [4, 16.0], "fx_claw_double_green": [5, 16.0], "fx_felspell": [17, 16.0],
	"fx_slash_arc_deep": [6, 18.0], "fx_slash_heavy_deep": [5, 16.0], "fx_slash_circle_deep": [6, 16.0], "fx_water_splash": [11, 14.0],
	"fx_rock_burst": [14, 14.0], "fx_rock_spike": [10, 14.0], "proj_foxfire": [6, 12.0],
	# 第二批干员的重调色变体（tools/fx_recolor.py，帧数 / fps 与源相同）
	"fx_slash_arc_rose": [6, 18.0], "fx_slash_heavy_rose": [5, 16.0], "fx_slash_circle_rose": [6, 16.0],
	"fx_slash_heavy_steel": [5, 16.0], "fx_circle_steel": [4, 8.0],
	"fx_slash_circle_ghost": [6, 16.0], "fx_slash_circle_blood": [6, 16.0], "fx_circle_ghost": [4, 8.0],
	"fx_ink_hit": [8, 14.0], "fx_holy_pillar_ink": [16, 14.0], "fx_circle_ink": [4, 8.0],
	"proj_lumen_bolt": [6, 12.0], "fx_holy_impact_lantern": [7, 16.0],
	# ansimuz 爆炸与魔法合集（tools/fx_import.py 'dir' 模式，2026-09-26）
	"fx_flames": [7, 12.0], "fx_fire_aura": [13, 18.0], "fx_splash_blue": [9, 18.0],
	"fx_thrust_hit_rose": [5, 20.0], "fx_star_hit_rose": [7, 20.0], "fx_cannon_burst": [10, 20.0], "fx_muzzle_flash": [7, 28.0],
	# Codex fx30（docs/30，双密度 @2x）：帧数 / fps 按 art/incoming/fx30_handoff.md；钙质晶体放慢到 10fps 以延长停留
	"proj_ulpianus_anchor": [2, 10.0], "fx_irene_thrust": [5, 25.0], "fx_specter_saw": [6, 24.0], "fx_specter_saw_blood": [6, 24.0],
	"fx_mizuki_tentacle": [6, 15.0], "fx_mizuki_tentacle_mass": [6, 15.0], "fx_suzuran_foxfire_gather": [6, 24.0],
	"fx_logos_glyph": [6, 18.0], "fx_logos_script": [4, 12.0], "fx_saria_shield_bash": [5, 20.0], "fx_saria_calcite": [8, 10.0],
	# Codex 逻各斯实机参考特效（art/incoming/logos_fx_handoff.md）
	"fx_logos_s3_orbit": [6, 10.0], "fx_logos_s3_back": [6, 10.0], "fx_logos_s3_front": [6, 10.0],
	"fx_logos_s1_link": [4, 12.0], "proj_logos_ink": [4, 12.0],
	# 艾雅法拉 S2 点燃：彗星火球 + 大团熔岩爆炸（ansimuz，fx_import）
	"proj_eyja_ignite": [5, 14.0], "fx_eyja_ignite_boom": [11, 18.0],
}
## 受击材质：甲壳 / 灵体，其余为血肉
const HIT_SHELL := ["stone", "spitter", "pocket", "mimic", "path", "fractal", "iberia", "carmen"]
const HIT_SPIRIT := ["skimmer", "paranoia", "tear", "brood", "bishop", "ishar"]


## 按敌人材质播放命中效果（V7 缺图时退回 fx_hit）
func _hit_fx(e: Dictionary, dir := Vector2.ZERO) -> void:
	var n := "fx_hit_flesh"
	if HIT_SHELL.has(e.type):
		n = "fx_hit_shell"
	elif HIT_SPIRIT.has(e.type) or e.get("hover", false):
		n = "fx_hit_spirit"
	var sc: float = PX * clampf(e.r / 12.0, 0.9, 2.2)
	if not _fx_sprite(n, e.pos + Vector2(0, -e.r * 0.5), sc, dir.angle() if dir != Vector2.ZERO else rng.randf() * TAU):
		_anim("fx_hit", e.pos, 0.16)
const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane", "tide": "proj_tide"}


## 激光三段：起点（枪口）+ 平铺中段（末段按长度裁切，不拉伸）+ 末端光斑
func _spr_rot(name: String, frame: int, pos: Vector2, ang: float, scale := PX, col := Color.WHITE, anchor_px := Vector2(-1, -1), flip := false) -> void:
	var tx: Texture2D = tex.get(name)
	if tx == null:
		return
	var frames: int = V6_FRAMES.get(name, [1, 0.0])[0]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var an := anchor_px if anchor_px.x >= 0.0 else Vector2(fw, fh) / 2.0
	scale /= A.hires_of(tx)   # @2x 高清帧条（Codex fx30）：同一逻辑尺寸，像素密度加倍
	draw_set_transform(pos + draw_off, ang, Vector2(-scale if flip else scale, scale))
	draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 一次性帧动画特效（命中 / 爆炸）；素材不存在时返回 false，调用方回退到程序特效
## 播放一条帧条特效：flip 镜像；bottom=true 时 pos 为脚底（帧条底部对齐）
func _fx_sprite(name: String, pos: Vector2, scale := PX, ang := 0.0, flip := false, bottom := false, col := Color.WHITE) -> bool:
	if tex.get(name) == null:
		return false
	if name.begins_with("fx_slash") or name.begins_with("fx_claw"):
		scale = _blade_scale(scale)
	scale = minf(scale, FX_SCALE_MAX)
	var spec: Array = V6_FRAMES[name]
	var dur: float = spec[0] / spec[1]
	var f := {"kind": "sprite", "name": name, "pos": pos, "ang": ang, "scale": scale, "life": dur, "max": dur, "flip": flip, "col": col}
	if bottom:
		var tx: Texture2D = tex[name]
		f["anchor"] = Vector2(tx.get_width() / spec[0] / 2.0, tx.get_height() - 1.0)
	fx.append(f)
	return true


func _spr(name: String, frames: int, frame: int, pos: Vector2, scale := PX, flip := false, col := Color.WHITE, anchor := Vector2(0.5, 0.5), sq := Vector2.ONE) -> void:
	var tx: Texture2D = tex.get(name)
	if tx == null:
		return
	pos += draw_off
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var src := Rect2(fw * (frame % frames), 0, fw, fh)
	var size := Vector2(fw, fh) * scale * sq
	if flip:
		# 以锚点为中心水平镜像
		draw_set_transform(pos.round(), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(tx, Rect2(-size * anchor, size), src, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tx, Rect2((pos - size * anchor).round(), size), src, col)


func _draw() -> void:
	map.draw_ground(get_viewport_rect().size)
	for m in mires:
		map.draw_mire(m)
	bai._draw_warns()
	rfx.draw()
	if not merchant.is_empty():
		var mtx: Texture2D = tex.merchant
		var big_m: bool = mtx != null and mtx.get_height() >= 40
		_spr("shadow", 1, 0, merchant.pos + Vector2(0, 18), PX * (1.6 if big_m else 1.2))
		if big_m:
			_spr("merchant", 2, int(t * 2.0) % 2, merchant.pos + Vector2(0, 18), PX, ppos.x < merchant.pos.x, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
		else:
			_spr("merchant", 2, int(t * 2.0) % 2, merchant.pos, PX)
		# 「商人 %ds」标签由 HUD 层在头顶绘制（_draw_hud 商人方向指示），这里不再重复画一份
	for g in gems:
		var gz: float = g.get("z", 0.0)
		if gz > 1.0:
			draw_set_transform(g.pos + Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 7.0 * (1.0 - clampf(gz / 80.0, 0.0, 0.6)), Color(0, 0, 0, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if g.get("special", false):
			var ic := pickups.item_col(g.kind)
			var age: float = g.get("age", 0.0)
			# 掉落光柱（0.9 秒淡出）+ 常驻脉动光圈
			if age < 0.9:
				var ba := (1.0 - age / 0.9) * 0.55
				draw_rect(Rect2(g.pos + Vector2(-5, -140), Vector2(10, 140)), Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, ba * 0.5))
				draw_rect(Rect2(g.pos + Vector2(-2, -140), Vector2(4, 140)), Color(2.5, 2.5, 2.5, ba))
			if g.kind != "chest":
				var pr := 11.0 + 2.0 * sin(t * 5.0)
				draw_circle(g.pos + Vector2(0, -gz - 2), pr + 5.0, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.12))
				draw_arc(g.pos + Vector2(0, -gz - 2), pr, 0.0, TAU, 20, Color(ic.r * 2.0, ic.g * 2.0, ic.b * 2.0, 0.5), 1.5)
		draw_off = Vector2(0, -gz)
		match g.kind:
			"xp":
				# 经验结晶：放大 + 常驻辉光 + 闪烁；被吸时拖尾
				var big: bool = g.val >= 5.0
				var gc: Color = Color(0.85, 0.6, 1.0) if big else UI.CYAN
				var tw: float = 0.75 + 0.25 * sin(t * 6.0 + g.get("seed", 0.0))
				var gp: Vector2 = g.pos + Vector2(0, (sin(t * 4.0 + g.pos.x) * 2.0 if gz <= 1.0 else 0.0) - gz)
				if g.mag:
					var dv: Vector2 = (gp - (ppos + Vector2(0, -12))).normalized()
					var tl: float = 10.0 + 24.0 * minf(1.0, g.get("mag_t", 0.0) * 2.0)
					draw_line(gp, gp + dv * tl, Color(gc.r * 1.8, gc.g * 1.8, gc.b * 1.8, 0.55), 5.0 if big else 3.0)
					draw_line(gp, gp + dv * tl * 0.6, Color(2.5, 2.5, 2.5, 0.7), 1.5)
				draw_circle(gp, (13.0 if big else 9.0) * tw, Color(gc.r * 1.6, gc.g * 1.6, gc.b * 1.6, 0.16))
				draw_circle(gp, (7.0 if big else 4.5) * tw, Color(gc.r * 2.0, gc.g * 2.0, gc.b * 2.0, 0.22))
				draw_off = Vector2.ZERO
				_spr("gem_big" if big else "gem_small", 1, 0, gp, PX * (1.9 if big else 1.45), false, Color(1.25, 1.25, 1.3) if not big else Color(1.35, 1.2, 1.5))
				var sp2: float = 2.0 + 1.5 * tw
				draw_line(gp + Vector2(-sp2, -8), gp + Vector2(sp2, -8), Color(2.5, 2.5, 2.5, 0.5 * tw), 1.0)
				draw_line(gp + Vector2(0, -8 - sp2), gp + Vector2(0, -8 + sp2), Color(2.5, 2.5, 2.5, 0.5 * tw), 1.0)
			"oil":
				_spr("oil", 1, 0, g.pos)
			"chest":
				_spr("chest", 1, 0, g.pos)
			"ingot":
				_spr("ingot", 1, 0, g.pos + Vector2(0, sin(t * 3.0 + g.pos.y) * 1.5 if gz <= 1.0 else 0.0))
			"magnet", "heal":
				_spr("pickup_" + g.kind, 1, 0, g.pos + Vector2(0, -2 + (sin(t * 3.5) * 2.0 if gz <= 1.0 else 0.0)))
		draw_off = Vector2.ZERO
	_spr("shadow", 1, 0, doc_pos + Vector2(0, 6), PX * 1.3)
	squad.draw_auras()
	for e in enemies:
		var sc: float = PX * e.r / 10.0
		var hop: float = minf(e.kb.length() * 0.03, 14.0)
		_spr("shadow", 1, 0, e.pos + Vector2(0, e.r * 0.8), sc * (1.0 - hop / 40.0))
	squad.draw_shadows()
	if knight.alive:
		_spr("shadow", 1, 0, knight.pos + Vector2(0, 18), PX * 1.6)
	squad.draw_entities_floor()
	# ---- 2.5D 前后遮挡：按脚底 y 排序后依次绘制 ----
	var dl: Array = []
	for e in enemies:
		dl.append([e.pos.y + e.r * 0.8, 0, e])
	dl.append([doc_pos.y + 6.0, 2, null])
	for o in squad.ops:
		if o.pos != Vector2.INF:
			dl.append([o.pos.y + 4.0, 5, o])
		for xb in o.extra_bodies():
			dl.append([xb.y, 6, [o, xb]])
	if knight.alive:
		dl.append([knight.pos.y + 18.0, 4, null])
	for pr in map.sort_props:
		dl.append([pr[1].y, 3, pr])
	dl.sort_custom(func(a, b): return a[0] < b[0])
	for it in dl:
		match it[1]:
			5:
				it[2].draw_body()
			6:
				it[2][0].draw_extra(it[2][1])
			4:
				knight.draw()
			0:
				_draw_enemy(it[2])
			2:
				_draw_player()
			3:
				map.draw_sort_prop(it[2])
	squad.draw_skill_over()
	_draw_shield()
	for dr in drones:
		draw_set_transform(dr.pos + Vector2(0, 96), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(dr.pos, 20.0, Color(0.5, 1.4, 0.8, 0.16))
		# Codex 美术 V5 的激光型机体（4 帧：0-1 悬浮，2-3 发射）染成医疗绿；治疗瞬间用发射帧
		var dfr := int(t * 6.0) % 2
		if dr.get("beam", 0.0) > 0.2:
			dfr = 2
		elif dr.get("beam", 0.0) > 0.0:
			dfr = 3
		if tex.get("drone_laser") != null:
			_spr("drone_laser", 4, dfr, dr.pos, 1.0, dr.get("face", 1.0) < 0.0, Color(0.85, 1.25, 0.95))
		elif tex.get("drone") != null:
			_spr("drone", 2, int(t * 20.0) % 2, dr.pos, PX, false, Color(1.2, 1.7, 1.4))
		draw_circle(dr.pos + Vector2(0, 8), 3.0, Color(1.2, 2.6, 1.6, 0.6 + 0.3 * sin(t * 8.0)))
	var jf := int(t * 6.0) % 2
	for b in bullets:
		if b.life <= 0.0 or b.get("hidden", false):
			continue
		var n: Vector2 = b.vel.normalized()
		# 美术 V6：投射物帧条（朝右绘制，按速度方向旋转）；程序只画拖尾
		var ptex: String = PROJ_TEX.get(b.kind, "")
		if ptex != "" and tex.get(ptex) != null:
			var pspec: Array = V6_FRAMES[ptex]
			var pfr: int = (int(t * pspec[1] + b.pos.x * 0.01) % int(pspec[0])) if pspec[1] > 0.0 else 0
			match b.kind:
				"arrow":
					draw_line(b.pos - n * 34.0, b.pos - n * 12.0, Color(1.6, 1.4, 1.0, 0.3), 2.0)
				"fire":
					draw_circle(b.pos, 14.0, Color(1.4, 0.6, 2.2, 0.2))
				"arcane":
					draw_line(b.pos - n * 20.0, b.pos, Color(1.4, 0.6, 2.2, 0.35), 4.0)
				"tide":
					draw_circle(b.pos, 11.0, Color(0.5, 1.2, 2.0, 0.2))
			_spr_rot(ptex, pfr, b.pos, b.vel.angle(), PX)
			continue
		match b.kind:
			"arrow":
				draw_line(b.pos - n * 26.0, b.pos - n * 10.0, Color(1.6, 1.4, 1.0, 0.35), 2.0)
				draw_line(b.pos - n * 14.0, b.pos + n * 4.0, Color(2.2, 2.0, 1.6), 3.0)
			"fire":
				var fl := 1.0 + 0.2 * sin(t * 40.0 + b.pos.x)
				draw_circle(b.pos, 13.0 * fl, Color(2.0, 0.8, 0.2, 0.25))
				draw_circle(b.pos, 8.0 * fl, Color(2.4, 1.1, 0.3, 0.8))
				draw_circle(b.pos, 4.0, Color(2.8, 2.4, 1.4))
			"arcane":
				draw_line(b.pos - n * 18.0, b.pos, Color(1.4, 0.6, 2.2, 0.4), 4.0)
				draw_circle(b.pos, 8.0, Color(1.2, 0.5, 2.0, 0.35))
				UI.diamond(self, b.pos, 5.0, Color(1.8, 1.0, 2.6), Color(2.2, 1.6, 2.8))
			"tide":
				draw_circle(b.pos, 10.0, Color(0.5, 1.2, 2.0, 0.25))
				draw_circle(b.pos, 6.0, Color(0.7, 1.5, 2.2, 0.9))
				draw_circle(b.pos + Vector2(-2, -2), 2.0, Color(2.5, 2.5, 2.5))
			_:
				_spr("orb", 1, 0, b.pos, PX)
	for f in fx:
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		match f.kind:
			"frost":
				# 寒冰领域：淡蓝地面 + 旋转冰纹
				var fa: float = minf(1.0, f.life / 0.6) * 0.9
				draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
				draw_circle(Vector2.ZERO, f.r, Color(0.5, 0.8, 1.2, 0.14 * fa))
				draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 48, Color(0.8, 1.2, 1.8, 0.6 * fa), 2.0)
				for q in 6:
					var qa: float = t * 0.6 + TAU * q / 6.0
					draw_line(Vector2.from_angle(qa) * f.r * 0.2, Vector2.from_angle(qa) * f.r * 0.95, Color(0.9, 1.3, 1.9, 0.25 * fa), 2.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"ring":
				var rr: float = f.r * (1.15 - a * 0.3)
				draw_arc(f.pos, rr, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.9), 4.0)
				draw_arc(f.pos, rr - 6.0, 0.0, TAU, 28, Color(f.col.r, f.col.g, f.col.b, a * 0.35), 2.0)
			"spark":
				draw_rect(Rect2(f.pos.round(), Vector2(f.sz, f.sz)), Color(f.col.r, f.col.g, f.col.b, a))
			"shard":
				var sv: Vector2 = Vector2.from_angle(f.rot + t * 8.0) * 5.0
				draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.5, f.pos + sv]), Color(1.2, 1.9, 2.4, a))
			"blood":
				# 流血：地面血迹
				for q in 5:
					var off := Vector2(sin(f.seed + q * 1.7), cos(f.seed * 1.3 + q)) * 7.0
					draw_set_transform(f.pos + off, 0.0, Vector2(1.0, 0.5))
					draw_circle(Vector2.ZERO, 3.0 + (q % 3), Color(0.5, 0.02, 0.05, 0.6 * a))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"explode":
				# 爆炸：火光 + 冲击环
				var k := 1.0 - a
				var c: Color = f.col
				draw_circle(f.pos, f.r * (0.3 + 0.7 * k), Color(c.r * 2.2, c.g * 1.8, c.b * 1.2, 0.45 * a))
				draw_circle(f.pos, f.r * 0.45 * a, Color(2.8, 2.4, 1.6, a))
				draw_arc(f.pos, f.r * (0.5 + 0.7 * k), 0.0, TAU, 32, Color(c.r * 2.4, c.g * 2.0, c.b * 1.4, a), 4.0)
			"cross":
				# 治疗：上升的绿色十字
				var age: float = f.max - f.life
				if age >= f.get("delay", 0.0):
					var p: Vector2 = f.pos + Vector2(0, -40.0 * (age - f.delay))
					if tex.get("fx_heal_cross") != null:
						_spr_rot("fx_heal_cross", mini(3, int((age - f.delay) * 10.0)), p, 0.0, PX * f.sz / 4.5, Color(1, 1, 1, a))
					else:
						var sz: float = f.sz
						var ca := Color(0.7, 2.2, 1.0, a)
						draw_rect(Rect2(p - Vector2(sz * 0.35, sz), Vector2(sz * 0.7, sz * 2.0)), ca)
						draw_rect(Rect2(p - Vector2(sz, sz * 0.35), Vector2(sz * 2.0, sz * 0.7)), ca)
			"beam":
				var c: Color = f.col
				draw_line(f.a, f.b, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.35 * a), f.w * 3.0)
				draw_line(f.a, f.b, Color(2.5, 2.5, 2.5, a), f.w * 0.6)
			"rift":
				# 地面裂隙（触手 / 巨触出现前的预警）
				var k := 1.0 - a
				draw_set_transform(f.pos + Vector2(0, 8), 0.0, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, f.r * (0.5 + 0.5 * k), Color(0.12, 0.02, 0.18, 0.6))
				draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 36, Color(1.6, 0.7, 2.4, 0.4 + 0.5 * k), 2.0)
				for q in 5:
					var dv := Vector2.from_angle(q * TAU / 5.0 + f.r)
					draw_line(dv * f.r * 0.15, dv * f.r * (0.4 + 0.5 * k), Color(1.8, 0.9, 2.6, 0.8), 2.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tendril":
				# 从水月脚下伸向目标的触须线
				var pts := PackedVector2Array()
				var nrm: Vector2 = (f.b - f.a).orthogonal().normalized()
				for q in 13:
					var u := q / 12.0
					pts.append(f.a.lerp(f.b, u) + nrm * sin(u * PI * 2.0 + f.seed + t * 10.0) * 10.0 * (1.0 - u))
				draw_polyline(pts, Color(0.5, 0.2, 0.8, 0.55 * a), 5.0)
				draw_polyline(pts, Color(1.6, 0.9, 2.4, 0.8 * a), 1.5)
			"giant_t":
				# 巨型触手破土
				var k := 1.0 - a
				var fr := clampi(int(k * 6.0), 0, 4)
				var tc: Color = ch.tentacle_col(1.15) if ch.has_method("tentacle_col") else Color(1.3, 1.1, 1.6)
				_spr("tentacle", 5, fr, f.pos + Vector2(0, 16), PX * 4.2, false, tc, Vector2(0.5, 1.0))
				_spr("tentacle", 5, fr, f.pos + Vector2(-50, 20), PX * 2.6, true, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
				_spr("tentacle", 5, fr, f.pos + Vector2(48, 22), PX * 2.4, false, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
			"sprite":
				var spec: Array = V6_FRAMES[f.name]
				var fr := mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
				_spr_rot(f.name, fr, f.pos, f.ang, f.scale, f.get("col", Color.WHITE), f.get("anchor", Vector2(-1, -1)), f.get("flip", false))
				if f.get("ring", 0.0) > 0.0 and fr == 0:
					draw_arc(f.pos, f.ring, 0.0, TAU, 40, Color(2.2, 2.0, 1.6, 0.6), 1.5)
			"impact":
				# 唤醒命中：十字闪光
				var k := 1.0 - a
				var L := 30.0 + 70.0 * k
				var c: Color = f.col
				var gc := Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, a)
				for q in 4:
					var dv := Vector2.from_angle(f.ang + q * PI / 2.0 + PI / 4.0)
					draw_line(f.pos - dv * L * (0.6 if q % 2 else 1.0), f.pos + dv * L * (0.6 if q % 2 else 1.0), gc, 5.0 * a + 1.0)
				draw_circle(f.pos, 18.0 * a + 4.0, Color(3.0, 2.6, 1.8, a * 0.8))
			"burst":
				# 创伤扩散：水花冲击
				var k := 1.0 - a
				var rr: float = f.r * (0.4 + 0.7 * k)
				var c: Color = f.col
				draw_circle(f.pos, rr, Color(c.r * 1.8, c.g * 1.6, c.b * 1.2, 0.25 * a))
				draw_arc(f.pos, rr, 0.0, TAU, 32, Color(c.r * 2.2, c.g * 2.0, c.b * 1.6, a), 5.0)
				draw_arc(f.pos, rr * 0.7, 0.0, TAU, 32, Color(0.6, 1.6, 2.0, a * 0.6), 2.0)
				for q in 10:
					var dv := Vector2.from_angle(q * TAU / 10.0 + f.r)
					draw_line(f.pos + dv * rr * 0.8, f.pos + dv * (rr + 14.0 * a), Color(2.0, 1.8, 1.2, a), 2.0)
			"wpillar":
				# 潮汐柱：升起的水柱 + 水花
				var k := 1.0 - a
				var c: Color = f.col
				var hgt: float = f.r * 2.4 * minf(1.0, k * 3.0)
				var wd: float = f.r * 0.8 * a
				draw_rect(Rect2(f.pos + Vector2(-wd / 2.0, -hgt), Vector2(wd, hgt)), Color(c.r * 1.4, c.g * 1.4, c.b * 1.6, 0.35 * a))
				draw_rect(Rect2(f.pos + Vector2(-wd / 5.0, -hgt), Vector2(wd / 2.5, hgt)), Color(2.2, 2.6, 2.8, 0.6 * a))
				draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
				draw_arc(Vector2.ZERO, f.r * (0.6 + 0.6 * k), 0.0, TAU, 32, Color(c.r * 1.6, c.g * 1.6, c.b * 1.8, a), 3.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"quake":
				# 震地 / 跳砸：地面裂纹放射
				var k := 1.0 - a
				var c: Color = f.col
				for q in 9:
					var dv := Vector2.from_angle(q * TAU / 9.0 + f.pos.x * 0.01)
					var l: float = f.r * (0.4 + 0.6 * minf(1.0, k * 2.5))
					draw_line(f.pos + dv * 8.0, f.pos + dv * l, Color(0.05, 0.03, 0.02, 0.8 * a), 3.0)
					draw_line(f.pos + dv * 8.0, f.pos + dv * l * 0.7, Color(c.r * 1.6, c.g * 1.4, c.b, a), 1.5)
				draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
				draw_arc(Vector2.ZERO, f.r * (0.3 + 0.7 * k), 0.0, TAU, 32, Color(c.r * 1.8, c.g * 1.6, c.b * 1.2, a * 0.8), 4.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tracer":
				# 狙击 / 裁决弹道
				var c: Color = f.col
				draw_line(f.a, f.b, Color(c.r * 1.5, c.g * 1.5, c.b * 1.2, 0.35 * a), f.wid * 2.0 * a + 2.0)
				draw_line(f.a, f.b, Color(2.6, 2.4, 2.0, a), 2.0)
			"bbeam":
				# 偏执凝视：粗光束
				var c: Color = f.col
				var k := 1.0 - a
				var wd: float = f.wid * 2.0 * (0.4 + 0.6 * a) + 6.0 * sin(t * 40.0)
				draw_line(f.a, f.b, Color(c.r * 1.2, c.g * 0.8, c.b * 1.6, 0.45 * a), wd * 1.6)
				draw_line(f.a, f.b, Color(c.r * 2.0, c.g * 1.4, c.b * 2.4, 0.8 * a), wd)
				draw_line(f.a, f.b, Color(2.6, 2.2, 2.8, a), wd * 0.3)
				for q in 6:
					var pp: Vector2 = f.a.lerp(f.b, (q + 0.5) / 6.0 + k * 0.1)
					draw_circle(pp, 5.0 + 4.0 * sin(t * 30.0 + q), Color(2.0, 1.6, 2.6, 0.6 * a))
			"bslash":
				# 横扫：宽弧刀光
				var c: Color = f.col
				var k := 1.0 - a
				var a0: float = f.ang - f.half + f.half * 2.0 * minf(1.0, k * 1.6)
				var a1: float = f.ang - f.half
				draw_arc(f.pos, f.r * 0.9, a1, a0, 24, Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, a), 14.0)
				draw_arc(f.pos, f.r * 0.75, a1, a0, 24, Color(2.4, 2.6, 2.6, a), 4.0)
				draw_arc(f.pos, f.r * 0.5, a1, a0, 24, Color(c.r * 1.2, c.g * 1.2, c.b * 1.2, 0.5 * a), 8.0)
			"pillar":
				# 触手破土：光柱
				var c: Color = f.col
				var hgt := 90.0 * (1.0 - a * 0.3)
				draw_rect(Rect2(f.pos + Vector2(-7 * a, -hgt), Vector2(14 * a, hgt)), Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.35 * a))
				draw_rect(Rect2(f.pos + Vector2(-2, -hgt), Vector2(4, hgt)), Color(2.5, 2.5, 2.5, 0.6 * a))
			"ghost":
				# 倒影：半透明的水月残像
				_draw_player_at(f.pos, f.flip, Color(1.2, 0.8, 2.0, 0.55 * a), sprite.frame)
			"chain":
				# 束缚传播：锁链
				var n := 8
				for q in n:
					var p0: Vector2 = f.a.lerp(f.b, float(q) / n)
					UI.diamond(self, p0 + Vector2(0, -8), 4.0, Color(0.02, 0.05, 0.08, a), Color(0.7, 1.4, 2.0, a))
			"rays":
				# 技能发动：放射光束
				var k := 1.0 - a
				var c: Color = f.col
				for q in 16:
					var dv := Vector2.from_angle(q * TAU / 16.0 + k * 0.6)
					var r0 := 30.0 + 200.0 * k
					draw_line(f.pos + dv * r0, f.pos + dv * (r0 + 60.0 * a + 20.0), Color(c.r * 2.2, c.g * 2.2, c.b * 2.2, a), 3.0)
			"horde_ring":
				# 大群压迫波：从视野外向水月收缩
				var k := 1.0 - a
				var rr: float = lerpf(f.r, 170.0, k * k)
				var c: Color = f.col
				draw_arc(f.pos, rr, 0.0, TAU, 64, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.8 * a), 10.0)
				draw_arc(f.pos, rr + 18.0, 0.0, TAU, 64, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.3 * a), 5.0)
				for j in 24:
					var ang := TAU * j / 24.0 + t * 0.5
					var p0: Vector2 = f.pos + Vector2.from_angle(ang) * rr
					draw_line(p0, p0 + Vector2.from_angle(ang) * 40.0 * a, Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 0.5 * a), 2.0)
			"slash":
				var nf: int = f.get("frames", 4)
				var fr := clampi(int((1.0 - a) * float(nf)), 0, nf - 1)
				var tn: String = f.get("tex", "slash")
				draw_set_transform(f.pos, f.ang, Vector2.ONE)
				var sc_col: Color = f.col if (tn == "slash" or tn.begins_with("fx_umbrella_slash")) else Color.WHITE
				_spr(tn, nf, fr, Vector2.ZERO, f.scale, false, sc_col, f.get("anchor", Vector2(0.5, 0.5)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in ebullets:
		# 2.5D：子弹在离地约 16px 的高度飞行，影子落在判定位置
		draw_set_transform(b.pos + Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, b.r + 1.0, Color(0, 0, 0, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bp: Vector2 = b.pos + Vector2(0, -16)
		match b.get("kind", "orb"):
			"acid":
				draw_circle(bp, b.r + 5.0, Color(0.5, 1.4, 0.3, 0.3))
				draw_circle(bp, b.r, Color(0.6, 1.8, 0.4))
				draw_circle(bp + Vector2(-1.5, -1.5), 1.5, Color(2.2, 2.4, 1.6))
			"nova":
				draw_circle(bp, b.r + 5.0, Color(1.2, 0.4, 1.8, 0.3))
				draw_circle(bp, b.r, Color(1.5, 0.6, 2.0))
			_:
				draw_circle(bp, b.r + 4.0, Color(1.0, 0.3, 0.6, 0.25))
				_spr("ebullet", 1, 0, bp, PX * b.r / 5.0)
	# 抛射碎石：落点预警 + 空中石块
	for l in lobs:
		var k: float = l.t / l.dur
		draw_set_transform(l.to, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, l.r * k, Color(1.0, 0.2, 0.15, 0.22))
		draw_arc(Vector2.ZERO, l.r, 0.0, TAU, 32, Color(1.4, 0.3, 0.25, 0.5 + 0.4 * sin(t * 20.0)), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var gp: Vector2 = l.from.lerp(l.to, k)
		var hgt := sin(k * PI) * 120.0
		draw_set_transform(gp, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var rp := gp + Vector2(0, -hgt - 8.0)
		draw_circle(rp, 7.0, Color(0.45, 0.42, 0.4))
		draw_circle(rp + Vector2(-2, -2), 3.0, Color(0.7, 0.66, 0.6))
	for sh in shocks:
		var a: float = 1.0 - sh.r / sh.maxr
		draw_arc(sh.pos, sh.r, 0.0, TAU, 48, Color(0.6, 1.0, 0.7, a), 6.0)
		draw_arc(sh.pos, sh.r - 10.0, 0.0, TAU, 48, Color(0.6, 1.0, 0.7, a * 0.3), 3.0)
	_draw_zone()
	map.draw_snow()


func _draw_fx_add() -> void:
	draw_off = Vector2.ZERO
	map.draw_god_rays(fx_add, get_viewport_rect().size, cam.position)
	var loop := int(t * 10.0)
	squad.draw_fx_add(fx_add, loop)
	for f in fx:
		if f.kind != "anim":
			continue
		var n: int = FXF.get(f.name, 1)
		var fr := clampi(int((1.0 - f.life / f.max) * n), 0, n - 1)
		var p: Vector2 = ppos if f.follow else f.pos
		_spr_on(fx_add, f.name, n, fr, p, f.scale)


## 同 _spr，但画在指定节点上（用于叠加发光层）
func _spr_on(ci: CanvasItem, name: String, frames: int, frame: int, pos: Vector2, scale := PX) -> void:
	var tx: Texture2D = tex[name]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var size := Vector2(fw, fh) * scale
	ci.draw_texture_rect_region(tx, Rect2((pos - size / 2.0).round(), size), Rect2(fw * (frame % frames), 0, fw, fh))


## 主角帧动画（美术交付 player_*.png 后自动启用；帧为正方形，帧数 = 宽 / 高）
func _update_player_anim(dt: float) -> void:
	if tex.get("doctor") != null:
		_update_doctor_anim(dt)
		return
	if tex.get("player_attack_48") != null:
		_update_player_anim48(dt)
		return
	var want := "player_idle"
	if state == S.DEAD:
		want = "player_death"
	elif hurt_flash > 0.05:
		want = "player_hurt"
	elif swing_face > 0.0:
		want = "player_attack"
	elif moving:
		want = "player_run"
	if tex.get(want) == null:
		want = "player_idle" if tex.get("player_idle") != null else ""
	if want == "":
		return
	if want != anim_name:
		anim_name = want
		anim_t = 0.0
		var tx: Texture2D = tex[want]
		sprite.texture = tx
		sprite.hframes = max(1, tx.get_width() / tx.get_height())
		sprite.offset = Vector2(0, -tx.get_height() / 2.0)
	anim_t += dt
	var n := sprite.hframes
	match anim_name:
		"player_attack":
			sprite.frame = clampi(int(anim_t / 0.25 * n), 0, n - 1)
		"player_death":
			sprite.frame = clampi(int(anim_t * 6.0), 0, n - 1)
		_:
			sprite.frame = int(anim_t * (12.0 if anim_name == "player_run" else 6.0)) % n


## 博士动画：data/doctor.json 的 sprites（编队美术第一批：idle 4 / run 6 / hurt 2 / death 4 帧，脚底 46）；
## 某个动作没有贴图时退回旧 2 帧待机条（doctor）：跑步 = 加快切帧 + 颠簸，倒下 = 侧倒
func _update_doctor_anim(dt: float) -> void:
	# 博士是挂件：不受击，只有待机 / 跑步；主控倒下时一起倒下
	var want := "idle"
	if state == S.DEAD:
		want = "death"
	elif doc_moving:
		want = "run"
	var sp: Dictionary = doctor.def.get("sprites", {})
	var tx: Texture2D = tex.get(sp.get(want, ""), null) if sp.has(want) else null
	var fallback := tx == null
	if fallback:
		tx = tex["doctor"]
	var key := want + ("_fb" if fallback else "")
	if key != anim_name:
		anim_name = key
		anim_t = 0.0
		sprite.texture = tx
		sprite.hframes = max(1, tx.get_width() / tx.get_height())
		# 脚底锚点：data/doctor.json 的 sprites.foot（旧 2 帧待机条为 45，编队美术第一批为 46）
		var foot_y: float = float(sp.get("foot", [24, 45])[1])
		sprite.offset = Vector2(0, -tx.get_height() / 2.0 + (48.0 - foot_y) * A.hires_of(tx))
	anim_t += dt
	var n := sprite.hframes
	sprite.rotation = 0.0
	if fallback:
		match want:
			"death":
				sprite.frame = 0
				sprite.rotation = lerpf(0.0, -1.45 * (1.0 if facing >= 0.0 else -1.0), clampf(anim_t / 0.35, 0.0, 1.0))
			"run":
				sprite.frame = int(anim_t * 7.0) % n
				sprite.position.y -= PX * absf(sin(anim_t * 11.0)) * 1.5
			_:
				sprite.frame = int(anim_t * 2.0) % n
	else:
		var spec: Array = P48.get(want, [4.0, true])
		var f := int(anim_t * spec[0])
		sprite.frame = f % n if spec[1] else mini(f, n - 1)


## 水月 48px 动画（Codex 交付：idle 4 帧 4fps、run 6 帧 10fps、hurt 2 帧 10fps 单次、
## death 4 帧 6fps 停末帧、attack 用 player_attack_48 4 帧）。脚底锚点 (24,46)。
## 若只有攻击条而没有 48px 的其他动作，则用攻击第 1 帧 + 代码起伏兜底。
const P48 := {"idle": [4.0, true], "run": [10.0, true], "hurt": [10.0, false], "death": [6.0, false]}


func _p48_tex(kind: String) -> Texture2D:
	if kind == "attack":
		return tex.get("player_attack_48")
	var tx: Texture2D = tex.get("player_" + kind)
	if tx != null and tx.get_height() == int(48.0 * A.hires_of(tx)):
		return tx
	return null


func _update_player_anim48(dt: float) -> void:
	var want := "idle"
	if state == S.DEAD:
		want = "death"
	elif hurt_flash > 0.05:
		want = "hurt"
	elif swing_face > 0.0:
		want = "attack"
	elif moving:
		want = "run"
	var tx := _p48_tex(want)
	var fallback := tx == null
	if fallback:
		tx = tex["player_attack_48"]
	var key := want + ("_fb" if fallback else "")
	if key != anim_name:
		anim_name = key
		anim_t = 0.0
		sprite.texture = tx
		sprite.hframes = max(1, tx.get_width() / tx.get_height())
		sprite.offset = Vector2(0, -tx.get_height() / 2.0 + 2.0 * A.hires_of(tx))
	anim_t += dt
	var n := sprite.hframes
	sprite.rotation = 0.0
	if want == "attack" and not fallback:
		sprite.frame = clampi(int((0.25 - swing_face) / 0.25 * n), 0, n - 1)
	elif fallback:
		sprite.frame = 0
		if want == "death":
			sprite.rotation = lerpf(0.0, -1.45 * (1.0 if facing >= 0.0 else -1.0), clampf(anim_t / 0.35, 0.0, 1.0))
		elif want == "idle":
			sprite.position.y -= PX * float(int(t / 0.8) % 2)
	else:
		var spec: Array = P48[want]
		var f := int(anim_t * spec[0])
		sprite.frame = f % n if spec[1] else mini(f, n - 1)

func _draw_enemy(e: Dictionary) -> void:
	var name: String = e.tex
	# 形态切换：偏执泡影二阶段 / 接潮三件套昏迷时的假死造型
	if e.type == "paranoia" and e.phase == 2 and tex.get("e_paranoia2") != null:
		name = "e_paranoia2"
	elif e.coma and e.tex_feign:
		name = name + "_feign"
	var frames := 2
	var frame := int(t * (2.0 if e.boss else 5.0) + e.id * 0.37) % 2
	# 移动帧条（美术 V5 / V8 / V9）：移动中播放 4 帧循环；停下、晕眩、假死时用本体
	if e.tex_move:
		if e.pos.distance_squared_to(e.get("dpos", e.pos)) > 0.04:
			e.mv_until = t + 0.2
		e.dpos = e.pos
		if t < e.mv_until and e.stun <= 0.0 and not e.coma:
			name += "_move"
			frames = 4
			var fps: float = float(D.ENEMIES.get(e.type, {}).get("move_fps", 6.0))
			if e.type == "immortal":
				fps = 8.0
			elif e.type in ["paranoia", "izumik", "ishar"]:
				fps = 5.0
			frame = int(t * fps + e.id * 0.37) % 4
	# 冲刺帧条（V9 骑士）：蓄力用前 2 帧，冲出去用后 2 帧
	if e.get("tex_charge", false) and (e.get("dash_w", 0.0) > 0.0 or e.get("dash_t", 0.0) > 0.0):
		name = e.tex + "_charge"
		frames = 4
		if e.dash_w > 0.0:
			frame = 0 if e.dash_w > 0.25 else 1
		else:
			frame = 2 if e.dash_t > 0.12 else 3
	var sc: float = PX * e.r / e.r0
	var col: Color = D.ENEMIES.get(e.type, {}).get("tint", Color.WHITE)
	if e.evo:
		col = col * Color(1.0, 0.62, 0.68)
	if e.get("under", false):
		# 潜行中：只画地面波纹与影子
		draw_set_transform(e.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, e.r + 6.0, Color(0.05, 0.02, 0.1, 0.6))
		draw_arc(Vector2.ZERO, e.r + 10.0 + 6.0 * sin(t * 9.0 + e.id), 0.0, TAU, 20, Color(0.7, 0.5, 1.0, 0.5), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if e.invuln:
		col = Color(0.7, 0.85, 1.0, 0.75)
	if e.elite:
		draw_circle(e.pos + Vector2(0, 2), e.r + 6.0, Color(1.0, 0.75, 0.3, 0.12 + 0.06 * sin(t * 4.0)))
	if e.chest:
		frame = 0
		var wob := 0.0
		if e.hidden and fmod(t + e.id, 3.0) < 0.25:
			wob = sin(t * 60.0) * 1.5
		if e.get("event", "") != "":
			frame = int(t * 2.0) % 2
			draw_set_transform(e.pos + Vector2(0, 14), 0.0, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 34.0 + 4.0 * sin(t * 3.0), Color(0.3, 0.6, 1.4, 0.18))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_spr(name, 2, frame, e.pos + Vector2(wob, 0), PX, false, col)
		if e.flash > 0.0:
			_spr(name + "_white", 2, 0, e.pos, PX, false, Color(1, 1, 1, 0.9))
		return
	if e.stun > 0.0:
		col = col * Color(0.65, 0.75, 1.0)
	# 攻击预警：滑动者冲刺线 / 子代蓄力光
	if e.get("dash_w", 0.0) > 0.0:
		var dd: Vector2 = e.dash_dir
		var wk: float = 1.0 - e.dash_w / 0.5
		draw_line(e.pos, e.pos + dd * 230.0, Color(1.4, 0.25, 0.2, 0.25 + 0.4 * wk), 10.0 * wk + 2.0)
		draw_line(e.pos, e.pos + dd * 230.0 * wk, Color(2.0, 0.5, 0.4, 0.8), 2.0)
	if e.get("dash_t", 0.0) > 0.0:
		_sparks(e.pos, -e.dash_dir, Color(0.8, 0.9, 1.0), 1, 80.0)
	if e.get("nova_w", 0.0) > 0.0:
		var nk: float = 1.0 - e.nova_w / 0.6
		draw_circle(e.pos, e.r + 6.0 + 10.0 * nk, Color(1.4, 0.5, 2.0, 0.2 + 0.3 * nk))
		col = col.lerp(Color(2.0, 1.2, 2.4), nk * 0.6)
	if e.get("burst_w", 0.0) > 0.0:
		# 囊海爬行者鼓胀：爆发范围预警圈从小到大，本体变亮
		var bk: float = 1.0 - e.burst_w / 0.4
		draw_arc(e.pos, 80.0 * bk, 0.0, TAU, 32, Color(1.6, 0.6, 2.2, 0.35 + 0.4 * bk), 2.0)
		draw_circle(e.pos, 80.0 * bk, Color(0.8, 0.4, 1.2, 0.08))
		col = col.lerp(Color(2.2, 1.4, 2.6), bk * 0.7)
	draw_off = Vector2(0, -minf(e.kb.length() * 0.03, 14.0))
	var flip: bool = e.fx < 0.0
	var anc := Vector2(0.5, 0.5)
	var bpos: Vector2 = e.pos
	if foot_anchor.has(e.tex):
		anc = Vector2(0.5, 1.0)
		bpos = e.pos + Vector2(0, e.r * 0.8 + 3.0 * PX)
	var k: float = clamp(e.squash / 0.14, 0.0, 1.0)
	var sq := Vector2(1.0 + 0.3 * k, 1.0 - 0.25 * k)
	# Boss 攻击姿态：蓄力时后仰变亮，出手瞬间前倾拉伸；有 _attack 帧条时改用帧条
	if e.boss and e.get("pose", 0.0) > 0.0 and e.get("pose_max", 0.0) > 0.0:
		var pk: float = e.pose / e.pose_max
		if e.tex_attack and not e.coma:
			name = e.tex + "_attack"
			frames = 4
			frame = clampi(int((1.0 - pk) * 4.0), 0, 3)
		elif e.pose > 0.3:
			var wk: float = minf(1.0, (1.0 - pk) * 2.0)
			sq *= Vector2(1.0 - 0.06 * wk, 1.0 + 0.08 * wk)
			bpos.x -= e.fx * 4.0 * wk
			col = col.lerp(Color(1.8, 1.5, 1.4), 0.35 * wk + 0.25 * wk * sin(t * 30.0))
		else:
			var rk: float = e.pose / 0.3
			sq *= Vector2(1.0 + 0.22 * rk, 1.0 - 0.14 * rk)
			bpos.x += e.fx * 12.0 * rk
	if e.get("air", 0.0) > 0.0:
		draw_set_transform(e.pos + Vector2(0, e.r * 0.8), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, e.r * 0.9, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_off.y -= e.air
	# 轮廓光：深色怪物在灯光外也能看清（颜色 >1，抵消环境暗色）
	if Cfg.outline and tex.has(name + "_white"):
		var oc := Color(1.6, 2.4, 3.2, 0.55) if not e.elite else Color(3.2, 2.2, 1.0, 0.7)
		for d in [Vector2(PX, 0), Vector2(-PX, 0), Vector2(0, PX), Vector2(0, -PX)]:
			_spr(name + "_white", frames, frame, bpos + d, sc, flip, oc, anc, sq)
	_spr(name, frames, frame, bpos, sc, flip, col, anc, sq)
	if e.flash > 0.0:
		_spr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9), anc, sq)
	var wk: String = e.get("weak", "")
	if wk != "" and not e.get("under", false):
		var wc := Color(1.0, 0.75, 0.3) if wk == "物理" else (Color(0.7, 0.55, 1.0) if wk == "法术" else Color(1.0, 0.5, 0.8))
		var wp: Vector2 = e.pos + Vector2(e.r * 0.8 + 6.0, -e.r - 4.0)
		UI.diamond(self, wp, 4.5, Color(0.02, 0.04, 0.08), wc)
		if e.boss:
			UI.text(self, font, wp + Vector2(-20, 16), ("弱" + wk.substr(0, 1)) if wk != "双" else "双弱", 10, wc, HORIZONTAL_ALIGNMENT_CENTER, 40)
	if e.elite:
		# 精英血条：窄一些（1.3 倍半径、3 px），少占画面
		var w: float = maxf(22.0, e.r * 1.3)
		draw_rect(Rect2(e.pos + Vector2(-w / 2, -e.r - 12), Vector2(w, 3)), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(e.pos + Vector2(-w / 2, -e.r - 12), Vector2(w * e.hp / e.maxhp, 3)), Color(1.0, 0.7, 0.3, 0.9))
	draw_off = Vector2.ZERO


## 在任意位置绘制水月（残影、倒影用）
## 以脚底为锚点画一帧（干员本体 / 分身 / 残影）：foot_off = 帧内脚底距底边的像素（贴图像素）
func _draw_sprite_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D, hf: int, foot_off: float) -> void:
	if tx == null:
		return
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (frame % hf), 0, fw, fh)
	var pk: float = PX / A.hires_of(tx)
	draw_set_transform((pos + draw_off).round(), 0.0, Vector2(-pk if flip else pk, pk))
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + foot_off), Vector2(fw, fh)), src, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_player_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D = null, hf: int = 0) -> void:
	if tx == null:
		tx = sprite.texture
		hf = sprite.hframes
	if tx == null:
		return
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (frame % hf), 0, fw, fh)
	var pk: float = PX / A.hires_of(tx)
	draw_set_transform(pos, 0.0, Vector2(-pk if flip else pk, pk))
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + Vector2(0, -fh / 2.0 + 2.0 * A.hires_of(tx)), Vector2(fw, fh)), src, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 黑潮：圈外暗紫雾 + 圈边脉动溟痕 + 下一圈预告
func _draw_zone() -> void:
	if zone_state == 0:
		return
	var vs := get_viewport_rect().size
	var far := vs.length() + 200.0
	var seg := 96
	var outer := zone_r + far + ppos.distance_to(zone_c)
	var pulse := 0.5 + 0.5 * sin(t * 2.5)
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := zone_c + Vector2.from_angle(a0) * zone_r
		var p1 := zone_c + Vector2.from_angle(a1) * zone_r
		# 只画视野附近的部分
		if p0.distance_to(ppos) > far + 400.0 and p1.distance_to(ppos) > far + 400.0 and ppos.distance_to(zone_c) < zone_r:
			continue
		var q0 := zone_c + Vector2.from_angle(a0) * outer
		var q1 := zone_c + Vector2.from_angle(a1) * outer
		draw_colored_polygon(PackedVector2Array([p0, p1, q1, q0]), Color(0.16, 0.03, 0.22, 0.55))
		var m0 := zone_c + Vector2.from_angle(a0) * (zone_r + 40.0)
		var m1 := zone_c + Vector2.from_angle(a1) * (zone_r + 40.0)
		draw_colored_polygon(PackedVector2Array([p0, p1, m1, m0]), Color(0.5, 0.15, 0.7, 0.25 + 0.15 * pulse))
		draw_line(p0, p1, Color(1.6, 0.6, 2.2, 0.7 + 0.3 * pulse), 3.0)
	# 圈边溟痕
	var mt: Texture2D = tex.get("terrain_mire")
	if mt != null:
		var fw := mt.get_width() / 2
		var n := int(TAU * zone_r / 90.0)
		for i in n:
			var an := TAU * i / n
			var p := zone_c + Vector2.from_angle(an) * (zone_r + 14.0)
			if p.distance_to(ppos) > vs.length() * 0.6:
				continue
			var sz := Vector2(70, 70) * (0.8 + 0.25 * sin(t * 2.0 + i))
			draw_texture_rect_region(mt, Rect2(p - sz / 2.0, sz), Rect2(fw * ((i + int(t * 2.0)) % 2), 0, fw, mt.get_height()), Color(1, 1, 1, 0.8))
	# 下一圈预告（虚线）
	if zone_state == 1:
		var n2 := 72
		for i in n2:
			if i % 2 == 0:
				continue
			var a0 := TAU * i / n2
			var a1 := TAU * (i + 1) / n2
			draw_line(zone_next_c + Vector2.from_angle(a0) * zone_next_r, zone_next_c + Vector2.from_angle(a1) * zone_next_r, Color(2.2, 2.2, 2.4, 0.6), 2.0)


## 护盾：淡蓝色六边形能量泡，层数越多越厚
func _draw_shield() -> void:
	if shield <= 0:
		return
	var c := ppos + Vector2(0, -26)
	var pop := 1.0 + 0.3 * (shield_pop / 0.4)
	var r := (38.0 + 2.0 * sin(t * 3.0)) * pop
	var fl := shield_flash / 0.3
	draw_circle(c, r, Color(0.35, 0.7, 1.0, 0.10 + 0.05 * shield + 0.3 * fl))
	# 外圈 + 内圈（多层时叠加）
	for q in shield:
		draw_arc(c, r - q * 4.0, 0.0, TAU, 48, Color(0.8, 1.6, 2.4, 0.55 - q * 0.1 + 0.4 * fl), 2.0)
	# 六边形网格高光
	for q in 6:
		var an := TAU * q / 6.0 + t * 0.4
		var p0 := c + Vector2.from_angle(an) * r * 0.62
		var p1 := c + Vector2.from_angle(an + TAU / 6.0) * r * 0.62
		draw_line(p0, p1, Color(0.9, 1.6, 2.2, 0.22), 1.0)
		draw_line(p0, c + Vector2.from_angle(an) * r, Color(0.9, 1.6, 2.2, 0.15), 1.0)
	# 流光
	var sw := fmod(t * 1.2, 1.0)
	draw_arc(c, r, -PI * 0.9 + sw * TAU, -PI * 0.6 + sw * TAU, 12, Color(2.4, 2.8, 3.0, 0.8), 3.0)
	draw_circle(c + Vector2(-r * 0.4, -r * 0.45), 4.0, Color(2.4, 2.6, 3.0, 0.5))


## 用 Sprite2D 的动画状态手动绘制水月，以便和怪物、海草按前后排序
## 角色手感：起步拉伸、停步压扁、转身缩身、奔跑起伏与前倾、挥伞前倾、受击后坐、待机呼吸；脚下扬尘
func _update_player_feel(dt: float) -> void:
	if dt <= 0.0:
		return
	var target_sq := Vector2.ONE
	var target_lean := 0.0
	var alive: bool = state != S.DEAD
	if state == S.OPENING:
		_update_opening(dt)
		return
	# 转身
	if facing != p_last_facing:
		p_turn = 1.0
		p_last_facing = facing
	p_turn = maxf(0.0, p_turn - dt * 9.0)
	# 起步 / 停步冲量
	if moving and not p_was_moving:
		p_sq = Vector2(0.84, 1.16)
		p_dust_t = 0.0
	elif not moving and p_was_moving:
		p_sq = Vector2(1.18, 0.84)
		_feet_dust(4, 90.0)
	p_was_moving = moving
	if alive and moving and pstun <= 0.0:
		var ph: float = absf(sin(walk_t))
		target_sq = Vector2(1.0 + 0.05 * ph, 1.0 - 0.06 * ph)
		target_lean = 0.09 * facing
		p_dust_t -= dt
		if p_dust_t <= 0.0:
			p_dust_t = 0.2
			_feet_dust(2, 60.0)
	elif alive:
		target_sq = Vector2(1.0 - 0.012 * sin(t * 2.2), 1.0 + 0.022 * sin(t * 2.2))
	# 挥伞：出手瞬间前倾 + 拉伸，随后回弹
	if swing_face > 0.0 and p_swing_prev <= 0.0:
		p_sq = Vector2(1.12, 0.92)
	if swing_face > 0.0:
		target_lean += 0.13 * facing * (swing_face / 0.25)
	p_swing_prev = swing_face
	# 受击：向后坐一下，微微后仰
	if hurt_flash > 0.12 and p_hurt_prev <= 0.12:
		var away := Vector2(-facing, 0.0)
		var nn := _nearest(1, 160.0)
		if not nn.is_empty():
			away = (ppos - nn[0].pos).normalized()
		p_off = away * 9.0
		p_sq = Vector2(1.1, 0.9)
	p_hurt_prev = hurt_flash
	if hurt_flash > 0.05:
		target_lean -= 0.12 * facing
	# 定身：轻微颤抖
	if pstun > 0.0:
		p_off.x += sin(t * 60.0) * 1.2
	var k := 1.0 - exp(-dt * 16.0)
	p_sq = p_sq.lerp(target_sq, k)
	p_sq.x *= 1.0 - 0.3 * p_turn
	p_lean = lerpf(p_lean, target_lean, k)
	p_off = p_off.lerp(Vector2.ZERO, 1.0 - exp(-dt * 12.0))


func _feet_dust(n: int, spd: float) -> void:
	for k in n:
		var v := Vector2(-facing * randf_range(20.0, spd), -randf_range(10.0, 40.0))
		fx.append({"kind": "spark", "pos": ppos + Vector2(randf_range(-6, 6), 4), "vel": v, "sz": 2.0, "life": 0.35, "max": 0.35, "col": Color(0.55, 0.65, 0.7, 0.8)})


## 开场动画：水月自海面沉降落地 → 灯火点亮 → 标题卡；任意键跳过，之后进入指南
func _start_opening() -> void:
	state = S.OPENING
	opening_t = 0.0
	p_off = Vector2(0, -320)
	lamp_light.energy = 0.0
	Sfx.play("start", -4.0)


func _update_opening(dt: float) -> void:
	opening_t += dt
	var k1 := clampf(opening_t / 1.7, 0.0, 1.0)
	var ease_in := 1.0 - pow(1.0 - k1, 2.2)
	p_off = Vector2(sin(opening_t * 3.0) * 6.0 * (1.0 - k1), -320.0 * (1.0 - ease_in))
	p_lean = sin(opening_t * 2.0) * 0.08 * (1.0 - k1)
	p_sq = Vector2(1.0 - 0.06 * (1.0 - k1), 1.0 + 0.1 * (1.0 - k1))
	# 上升的气泡
	if k1 < 1.0 and randf() < 0.6:
		fx.append({"kind": "spark", "pos": ppos + p_off + Vector2(randf_range(-22, 22), randf_range(-40, 10)), "vel": Vector2(randf_range(-8, 8), -randf_range(40, 90)), "sz": randf_range(2.0, 3.5), "life": 1.1, "max": 1.1, "col": Color(0.8, 0.95, 1.0, 0.7)})
	# 落地
	if opening_t >= 1.7 and opening_t - dt < 1.7:
		p_sq = Vector2(1.3, 0.72)
		_feet_dust(14, 150.0)
		fx.append({"kind": "ring", "pos": ppos + Vector2(0, 6), "r": 60.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.85, 1.0)})
		_shake(0.7)
		Sfx.play("boom", -14.0, 1.4, 0.0)
	if opening_t >= 1.7:
		p_sq = p_sq.lerp(Vector2.ONE, 1.0 - exp(-dt * 10.0))
		p_lean = lerpf(p_lean, 0.0, 1.0 - exp(-dt * 10.0))
	# 灯火点亮：2.1s 起，先闪两下再稳定
	if opening_t >= 2.1:
		var k2 := clampf((opening_t - 2.1) / 0.8, 0.0, 1.0)
		var fl := 1.0 if k2 > 0.5 else (1.0 if fmod(k2, 0.2) < 0.1 else 0.25)
		lamp_light.energy = 1.15 * k2 * fl
		if opening_t - dt < 2.1:
			Sfx.play("oil", -8.0, 1.2, 0.0)
			fx.append({"kind": "rays", "pos": ppos + Vector2(0, -20), "life": 0.8, "max": 0.8, "col": Color(1.0, 0.85, 0.5)})
	_update_fx(dt)
	if opening_t >= OPENING_DUR:
		_end_opening()


func _end_opening() -> void:
	if state != S.OPENING:
		return
	p_off = Vector2.ZERO
	p_sq = Vector2.ONE
	p_lean = 0.0
	lamp_light.energy = 1.15
	state = S.PLAY
	_open_intro(S.PLAY)


func _draw_opening_hud(vs: Vector2) -> void:
	# 黑场渐亮 + 上下黑边 + 标题卡
	var dark: float = clampf(1.0 - opening_t / 1.2, 0.0, 1.0) * 0.9 + 0.1
	if opening_t > 2.9:
		dark = lerpf(0.1, 0.0, clampf((opening_t - 2.9) / 0.7, 0.0, 1.0))
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.03, dark))
	var bar: float = 70.0 * (1.0 - clampf((opening_t - 2.9) / 0.7, 0.0, 1.0))
	hud.draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0, 0, 0.95))
	hud.draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0, 0, 0.95))
	if opening_t > 0.4 and opening_t < 3.3:
		var a: float = clampf((opening_t - 0.4) / 0.6, 0.0, 1.0) * clampf((3.3 - opening_t) / 0.5, 0.0, 1.0)
		UI.en(hud, font, Vector2(vs.x / 2 - 200, vs.y * 0.22), "OPERATION  MIZUKI", 13, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), 5.0)
		UI.text(hud, font, Vector2(0, vs.y * 0.22 + 44), "%s  ·  深海探索" % ch.display_name(), 34, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
		UI.text(hud, font, Vector2(0, vs.y * 0.22 + 74), "灯火未熄，便还能走下去", 14, Color(0.7, 0.85, 0.9, a * 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	UI.text(hud, font, Vector2(0, vs.y - 26), "任意键跳过", 12, Color(0.5, 0.6, 0.65, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 2)


func _draw_player() -> void:
	var tx: Texture2D = sprite.texture
	if tx == null:
		return
	var hf := sprite.hframes
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (sprite.frame % hf), 0, fw, fh)
	var pk: float = PX / A.hires_of(tx)   # @2x 高清贴图按半倍画
	var sx := -pk if sprite.flip_h else pk
	# 以脚底为轴做挤压 / 前倾 / 后坐（帧动画之上的程序手感）
	draw_set_transform(sprite.position + p_off, sprite.rotation + p_lean, Vector2(sx * p_sq.x, pk * p_sq.y))
	# 博士挂件不受击：不吃主控的受击闪白 / 无敌闪烁（那些现在画在主控干员身上）
	var dmod: Color = Color(0.5, 0.5, 0.6, 0.6) if state == S.DEAD else Color.WHITE
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + sprite.offset, Vector2(fw, fh)), src, dmod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hud() -> void:
	var vs := hud.size
	var ct := get_viewport().get_canvas_transform()
	if state == S.OPENING:
		_draw_opening_hud(vs)
		return
	# 伤害数字
	for f in texts:
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		var sp: Vector2 = ct * f.pos
		var pop: float = 1.0 + 0.7 * clamp((f.life - f.max + 0.12) / 0.12, 0.0, 1.0)
		var sz := int(f.size * pop)
		UI.text(hud, font, sp - Vector2(60, 0), f.text, sz, Color(f.col.r, f.col.g, f.col.b, a), HORIZONTAL_ALIGNMENT_CENTER, 120, 4)

	if demo_op != "":
		return   # 图鉴演示：只要伤害数字，不画其余 HUD
	# 升级字样：弹出放大 -> 轻微上浮 -> 淡出
	if lvup_show > 0.0 and state == S.PLAY:
		var age := 1.3 - lvup_show
		var pop := 1.0 + 0.6 * clampf(1.0 - age / 0.15, 0.0, 1.0)
		if age > 0.15 and age < 0.3:
			pop = 1.0 - 0.1 * sin((age - 0.15) / 0.15 * PI)
		var la := clampf(lvup_show / 0.35, 0.0, 1.0)
		var lp: Vector2 = ct * (ppos + Vector2(0, -92 - age * 14.0))
		var gold := Color(1.0, 0.86, 0.42, la)
		UI.text(hud, font, lp - Vector2(150, 0), "LEVEL UP!", int(30 * pop), gold, HORIZONTAL_ALIGNMENT_CENTER, 300, 6)
		UI.text(hud, font, lp + Vector2(-150, 26), "Lv.%d" % level, int(18 * pop), Color(0.85, 1.0, 0.98, la), HORIZONTAL_ALIGNMENT_CENTER, 300, 4)

	if flash > 0.0:
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.97, 0.9, flash * 0.5))
	# 大群预警与到达演出
	if horde_warn > 0.0 or horde_hit > 0.0:
		var hw := horde_warn > 0.0
		var pulse := 0.5 + 0.5 * sin(t * (10.0 if hw else 4.0))
		var ea := (0.25 + 0.3 * pulse) if hw else horde_hit / 1.2 * 0.6
		_edge_glow(vs, Color(0.55, 0.15, 0.85, ea), 120.0)
		var age := (3.0 - horde_warn) if hw else 3.0 + (1.2 - horde_hit)
		var pop := 1.0 + 0.8 * clampf(1.0 - age / 0.2, 0.0, 1.0)
		var ta := 1.0 if hw else clampf(horde_hit / 0.6, 0.0, 1.0)
		var cy := vs.y * 0.3
		var jit := Vector2(sin(t * 53.0), cos(t * 47.0)) * (2.0 if hw else 0.0)
		hud.draw_rect(Rect2(0, cy - 62, vs.x, 92), Color(0.05, 0.0, 0.08, 0.55 * ta))
		hud.draw_rect(Rect2(0, cy - 62, vs.x, 2), Color(0.8, 0.4, 1.0, 0.8 * ta))
		hud.draw_rect(Rect2(0, cy + 28, vs.x, 2), Color(0.8, 0.4, 1.0, 0.8 * ta))
		UI.text(hud, font, Vector2(0, cy + 14) + jit, "大 群 来 袭" if hw else "海嗣大群 已抵达", int(38 * pop), Color(1.0, 0.75, 1.0, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		if hw:
			UI.en(hud, font, Vector2(vs.x / 2 - 130, cy - 40), "THE  SWARM  APPROACHES  ·  %d" % int(ceil(horde_warn)), 12, Color(0.85, 0.6, 1.0, ta), 3.0)
			# 四周方向警示箭头（向内）
			for j in 12:
				var ang := TAU * j / 12.0
				if absf(angle_difference(ang, horde_gap)) < deg_to_rad(40.0):
					continue  # 缺口方向不画箭头：那边没有敌人
				var dir := Vector2.from_angle(ang)
				var c := vs / 2.0
				var ed: Vector2 = c + dir * min(abs((vs.x / 2 - 40) / max(abs(dir.x), 0.01)), abs((vs.y / 2 - 40) / max(abs(dir.y), 0.01)))
				var tip: Vector2 = ed - dir * (10.0 + 8.0 * pulse)
				var sd := dir.orthogonal() * 12.0
				hud.draw_colored_polygon(PackedVector2Array([tip, ed + sd, ed - sd]), Color(0.9, 0.5, 1.0, 0.5 + 0.4 * pulse))

	# 溟痕：屏幕压暗 + 紫色边缘
	if in_mire > 0.0:
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.0, 0.06, 0.18 * in_mire))
		_edge_glow(vs, Color(0.45, 0.1, 0.7, 0.8 * in_mire), 130.0)
		if in_mire > 0.5 and state == S.PLAY:
			UI.text(hud, font, Vector2(0, vs.y * 0.5 + 84), "陷入溟痕：减速、侵蚀", 16, Color(0.85, 0.55, 1.0, in_mire), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# 受击时屏幕边缘泛红
	if red_flash > 0.0:
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.05, 0.1, red_flash * 0.16))
		_edge_glow(vs, Color(0.9, 0.08, 0.12, red_flash * 0.9), 70.0)
	post.hurt = hurt_vignette
	if state == S.PLAY and hp < max_hp * 0.3 and hp > 0.0:
		var beat := pow(maxf(0.0, sin(t * (5.0 + 5.0 * (1.0 - hp / (max_hp * 0.3))))), 4.0)
		_edge_glow(vs, Color(0.85, 0.05, 0.12, 0.3 + 0.35 * beat), 110.0)
		UI.text(hud, font, Vector2(0, vs.y * 0.5 + 110), "生命垂危", 18, Color(1.0, 0.4, 0.45, 0.5 + 0.5 * beat), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# 头顶血条：受伤后或低血量时显示
	if state == S.PLAY and (head_bar_t > 0.0 or hp < max_hp * 0.3):
		var hpos: Vector2 = ct * ppos + Vector2(-24, -104)
		var ha := clampf(head_bar_t / 0.5, 0.0, 1.0) if hp >= max_hp * 0.3 else 1.0
		hud.draw_rect(Rect2(hpos - Vector2(1, 1), Vector2(50, 7)), Color(0, 0, 0, 0.7 * ha))
		hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(hp_trail / max_hp, 0.0, 1.0), 5)), Color(1, 0.95, 0.9, 0.9 * ha))
		hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(hp / max_hp, 0.0, 1.0), 5)), Color(1.0, 0.3, 0.35, ha) if hp < max_hp * 0.3 else Color(0.35, 0.95, 0.75, ha))
	if lamp < 30.0 and state == S.PLAY:
		_edge_glow(vs, Color(0.3, 0.0, 0.2, 0.25 + 0.1 * sin(t * 3.0)), 140.0)

	# 左上（方案 A · 原作顶栏）：等级圆（外圈 = 经验）+「生命值」「灯火」彩色小标签头 + 数值 + 细条；
	# 名字与编队人数移到右下编队卡；下面一条灯火状态标签条在后面画（和状态效果一起）
	var o := Vector2(16, 12)
	var lf := hud_lv_flash
	var bc := UI.CYAN.lerp(UI.GOLD, lf).lerp(Color(0.8, 1.6, 1.8), xp_flash * 0.7)
	var lc0 := o + Vector2(26, 30)
	UI.ring(hud, lc0, 22.0 + 3.0 * lf, xp / xp_need, bc, lf > 0.2)
	UI.ctext(hud, font, lc0 + Vector2(-20, -6), "LV", 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 40)
	UI.ctext(hud, font, lc0 + Vector2(-26, 13), str(level), int(20 * (1.0 + 0.3 * lf)), Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, 52)
	# 生命值
	var hs := Vector2(sin(t * 90.0), cos(t * 70.0)) * 3.0 * hp_shake / 0.35
	var low := hp / max_hp < 0.3
	var hx := o.x + 64.0
	var tw0 := UI.tab(hud, font, Vector2(hx, o.y), "生命值", UI.RED if low else UI.TAB_HP)
	# 护盾层：小标签头右边一排小菱形
	for q in shield_max:
		UI.diamond(hud, Vector2(hx + tw0 + 10 + q * 11, o.y + 8.5), 4.0, Color(0.5, 0.85, 1.0) if q < shield else Color(1, 1, 1, 0.12), Color(0.6, 0.9, 1.0, 0.8))
	var hpc: Color = UI.RED.lerp(Color(1, 0.8, 0.85), 0.5 + 0.5 * sin(t * 10.0)) if low else UI.CYAN
	var hps := "%d" % int(hp)
	UI.ctext(hud, font, Vector2(hx, o.y + 40) + hs, hps, 21, UI.RED if low else UI.TEXT)
	UI.ctext(hud, font, Vector2(hx + UI.cwidth(font, hps, 21) + 4, o.y + 40) + hs, "/ %d" % int(max_hp), 13, UI.SUB)
	UI.gbar(hud, Rect2(Vector2(hx, o.y + 47) + hs, Vector2(150, 4)), hp / max_hp, hpc, 0, hp_trail / max_hp)
	# 灯火：30 / 70 两道刻度
	var lx := hx + 172.0
	var lamp_low := lamp < 30.0
	var lc := UI.GOLD if not lamp_low else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(t * 8.0))
	UI.tab(hud, font, Vector2(lx, o.y), "灯火", UI.TAB_LAMP if not lamp_low else UI.RED)
	var lps := "%d" % int(lamp)
	UI.ctext(hud, font, Vector2(lx, o.y + 40), lps, 21, lc if lamp_low else UI.TEXT)
	UI.ctext(hud, font, Vector2(lx + UI.cwidth(font, lps, 21) + 4, o.y + 40), "/ %d" % int(lamp_cap), 13, UI.SUB)
	var lbr := Rect2(Vector2(lx, o.y + 47), Vector2(120, 4))
	UI.gbar(hud, lbr, lamp / 100.0, lc)
	for tv in [30.0, 70.0]:
		var tx: float = lbr.position.x + lbr.size.x * tv / 100.0
		hud.draw_rect(Rect2(tx, lbr.position.y - 2, 1, lbr.size.y + 4), Color(1, 1, 1, 0.7))
	# 神经损伤 / 侵蚀：生命条下方一道洋红细条
	if nerve > 1.0:
		UI.gbar(hud, Rect2(Vector2(hx, o.y + 54), Vector2(150, 2)), nerve / 100.0, Color(1.0, 0.45, 0.85))
		UI.en(hud, font, Vector2(hx + 156, o.y + 58), "NERVE", 8, Color(1.0, 0.5, 0.9), 1.0)
	if corrode_pool > 0.5:
		UI.text(hud, font, Vector2(hx + 190, o.y + 60), "蚀", 11, Color(0.8, 0.5, 1.0))
	if pstun > 0.0:
		UI.text(hud, font, ct * ppos + Vector2(-40, -110), "僵直", 16, Color(1.0, 0.5, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	# 商人方向指示
	if not merchant.is_empty():
		var sp: Vector2 = ct * merchant.pos
		var bounce := absf(sin(t * 5.0)) * 8.0
		var mf := int(t * 2.0) % 2
		if not Rect2(Vector2(60, 60), vs - Vector2(120, 120)).has_point(sp):
			var c := vs / 2.0
			var d := (sp - c).normalized()
			var edge: Vector2 = c + d * min(abs((vs.x / 2 - 64) / max(abs(d.x), 0.01)), abs((vs.y / 2 - 64) / max(abs(d.y), 0.01)))
			var pulse := 0.5 + 0.5 * sin(t * 6.0)
			hud.draw_circle(edge, 30.0 + 4.0 * pulse, Color(1.0, 0.7, 0.3, 0.12))
			hud.draw_circle(edge, 24.0, Color(0.06, 0.05, 0.03, 0.85))
			hud.draw_arc(edge, 24.0, 0.0, TAU, 28, UI.GOLD, 2.0)
			var mt: Texture2D = tex.merchant
			var fw := mt.get_width() / 2
			# 头像整体缩放到直径 40 的圆圈里居中（高清 48px 图缩到 0.8，像素 20px 图放大 2 倍）
			var msc: float = minf(40.0 / float(fw), 40.0 / float(mt.get_height()))
			msc = floorf(msc) if msc >= 1.0 else msc
			var msz := Vector2(fw, mt.get_height()) * msc
			hud.draw_texture_rect_region(mt, Rect2((edge - msz * 0.5).round(), msz), Rect2(fw * mf, 0, fw, mt.get_height()))
			# 指向商人的箭头
			var tip: Vector2 = edge + d * (40.0 + 5.0 * pulse)
			var base: Vector2 = edge + d * 28.0
			var sd := d.orthogonal() * 10.0
			hud.draw_colored_polygon(PackedVector2Array([tip, base + sd, base - sd]), UI.GOLD)
			var dist := int(merchant.pos.distance_to(ppos) / 32.0)
			# 文字放在圆圈（半径 24 + 光晕）之外：下半屏放上方，上半屏放下方
			var lab_y := -40.0 if edge.y > vs.y / 2 else 54.0
			UI.text(hud, font, edge + Vector2(-60, lab_y), "商人  %dm · %ds" % [dist, int(merchant.life)], 13, shop_sys.merchant_col(), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
		else:
			# 在画面内：头顶跳动的箭头
			var big_m: bool = tex.merchant != null and tex.merchant.get_height() >= 40
			var head: float = (84.0 if big_m else 36.0) * ct.get_scale().y
			var hp2 := sp + Vector2(0, -head - 12.0 - bounce)
			hud.draw_colored_polygon(PackedVector2Array([hp2 + Vector2(0, 12), hp2 + Vector2(-10, -2), hp2 + Vector2(10, -2)]), UI.GOLD)
			UI.text(hud, font, hp2 + Vector2(-60, -8), ("商人 %ds" if merchant.life > 15.0 else "商人即将离开 %ds") % int(merchant.life), 13, shop_sys.merchant_col(), HORIZONTAL_ALIGNMENT_CENTER, 140, 3)
	# 海嗣祭坛方位指示（屏幕外）
	for e in enemies:
		if not e.chest or e.dead or e.get("event", "") == "":
			continue
		var spb: Vector2 = ct * e.pos
		if Rect2(Vector2(60, 60), vs - Vector2(120, 120)).has_point(spb):
			var hb := spb + Vector2(0, -60 - absf(sin(t * 5.0)) * 8.0)
			hud.draw_colored_polygon(PackedVector2Array([hb + Vector2(0, 12), hb + Vector2(-10, -2), hb + Vector2(10, -2)]), Color(0.55, 0.8, 1.0))
			UI.text(hud, font, hb + Vector2(-60, -8), "海嗣祭坛", 13, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
		else:
			var cc := vs / 2.0
			var dd := (spb - cc).normalized()
			var edge2: Vector2 = cc + dd * min(abs((vs.x / 2 - 64) / max(abs(dd.x), 0.01)), abs((vs.y / 2 - 64) / max(abs(dd.y), 0.01)))
			var pl := 0.5 + 0.5 * sin(t * 6.0)
			hud.draw_circle(edge2, 24.0, Color(0.03, 0.05, 0.1, 0.85))
			hud.draw_arc(edge2, 24.0, 0.0, TAU, 28, Color(0.55, 0.8, 1.0), 2.0)
			var et2: Texture2D = tex.e_event
			hud.draw_texture_rect_region(et2, Rect2(edge2 - Vector2(13, 15), Vector2(26, 30)), Rect2(0, 0, 26, 30))
			var tip2: Vector2 = edge2 + dd * (40.0 + 5.0 * pl)
			var base2: Vector2 = edge2 + dd * 28.0
			var sd2 := dd.orthogonal() * 10.0
			hud.draw_colored_polygon(PackedVector2Array([tip2, base2 + sd2, base2 - sd2]), Color(0.55, 0.8, 1.0))
			UI.text(hud, font, edge2 + Vector2(-60, -34.0 if edge2.y > vs.y / 2 else 44.0), "海嗣祭坛 %dm" % int(e.pos.distance_to(ppos) / 32.0), 13, Color(0.55, 0.8, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
	if not _overlay_left():
		_draw_minimap(vs)
	var st_txt := ""
	var st_en := "LIGHT"
	var st_col := UI.GOLD
	if lamp <= 0.0:
		st_txt = "灯火熄灭 · 持续受伤"
		st_en = "OUT"
		st_col = UI.RED
	elif lamp < 30.0:
		st_txt = "暗潮涌动 · 敌人更快更凶更多 · 拾取 -30%"
		st_en = "DARK"
		st_col = Color(1, 0.5, 0.5)
	elif lamp >= 70.0:
		st_txt = "灯火充盈 · 技力 +30% · 拾取 +20%"
	else:
		st_txt = "灯火照亮 · 光中敌人受伤 +25%"
		st_en = "LIT"
		st_col = Color(1.0, 0.85, 0.6)
	UI.strip(hud, font, o + Vector2(2, 66), st_en, st_txt, st_col, st_col.lerp(UI.TEXT, 0.45))
	# 黑潮：圈外警告 + 指向安全区
	if zone_state != 0 and state == S.PLAY:
		var out := ppos.distance_to(zone_c) - zone_r
		if out > 0.0:
			var pz := 0.5 + 0.5 * sin(t * 8.0)
			_edge_glow(vs, Color(0.55, 0.1, 0.8, 0.4 + 0.3 * pz), 140.0)
			var dirz := (zone_c - ppos).normalized()
			var cp: Vector2 = ct * ppos + Vector2(0, -30) + dirz * 80.0
			var sd := dirz.orthogonal() * 12.0
			hud.draw_colored_polygon(PackedVector2Array([cp + dirz * 22.0, cp + sd, cp - sd]), Color(1.0, 0.8, 1.0, 0.7 + 0.3 * pz))
			UI.text(hud, font, Vector2(0, vs.y * 0.5 - 130), "身处黑潮！返回安全区", 20, Color(1.0, 0.7, 1.0, 0.7 + 0.3 * pz), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 5)
		else:
			# 顶栏楼层条下方；有 Boss 血条时再往下让出位置
			var zy := 116.0 + 54.0 * bosses.filter(func(b): return not b.dead).size()
			if zone_state == 1:
				UI.text(hud, font, Vector2(0, zy), "黑潮将至  %d" % int(ceil(20.0 - zone_t)), 15, Color(0.9, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
			elif zone_state == 2:
				UI.text(hud, font, Vector2(0, zy), "安全区收缩中", 15, Color(0.9, 0.6, 1.0, 0.6 + 0.4 * sin(t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)

	# 顶部中央（方案 A · 明日方舟战斗顶栏）：[敌人] 击杀 | [时钟] 时间；
	# 下面一行「◆ 楼层 + 英文」（背后淡金四叶环，原作地图顶部楼层名的样子）、威胁进度细线、威胁 / 难度
	var mm := int(t) / 60
	var ss := int(t) % 60
	var cx0 := vs.x / 2.0
	UI.fade_band(hud, Rect2(cx0 - 160, 8, 320, 40), Color(0.03, 0.035, 0.045, 0.8), 56.0)
	var ks := str(kills)
	var kw := UI.cwidth(font, ks, 23)
	var lx0 := cx0 - 16.0 - (20.0 + 6.0 + kw + 4.0 + 24.0)
	UI.icon(hud, "enemy", Vector2(lx0 + 10, 28), 20.0, Color.WHITE)
	UI.ctext(hud, font, Vector2(lx0 + 26, 37), ks, 23, UI.TEXT)
	UI.text(hud, font, Vector2(lx0 + 30 + kw, 36), "击杀", 11, UI.SUB)
	hud.draw_rect(Rect2(cx0 - 0.5, 18, 1, 20), Color(1, 1, 1, 0.28))
	UI.icon(hud, "clock", Vector2(cx0 + 25, 28), 18.0, Color.WHITE)
	UI.ctext(hud, font, Vector2(cx0 + 38, 38), "%02d:%02d" % [mm, ss], 25, UI.TEXT)
	var tr: Dictionary = D.THREAT[threat]
	var tfrac: float = 1.0
	if threat < D.THREAT.size() - 1:
		tfrac = clampf((t - tr.t) / (D.THREAT[threat + 1].t - tr.t), 0.0, 1.0)
	var tcol := Color(0.9, 0.45, 1.0).lerp(UI.RED, float(threat) / (D.THREAT.size() - 1))
	UI.quatrefoil(hud, Vector2(cx0, 64), 34.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.28), 1.6)
	var fname: String = tr.name
	var fen: String = String(tr.get("en", ""))
	var fw0 := font.get_string_size(fname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var few := UI.en_width(font, fen, 10, 3.0)
	var fx0 := cx0 - (14.0 + fw0 + 10.0 + few) / 2.0
	UI.diamond(hud, Vector2(fx0 + 4, 61), 3.5, UI.GOLD)
	UI.text(hud, font, Vector2(fx0 + 14, 66), fname, 14, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	UI.en(hud, font, Vector2(fx0 + 24 + fw0, 65), fen, 10, UI.SUB, 3.0)
	UI.gbar(hud, Rect2(cx0 - 70, 73, 140, 2), tfrac, tcol)
	UI.text(hud, font, Vector2(cx0 - 150, 90), ("威胁 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][threat]) + (("  ·  难度 %d" % diff) if diff > 0 else ""), 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 300, 2)

	# 右上：暂停按钮（鼠标可点；触屏有自己的按钮）+ 收藏品栏 + 当前结局走向
	var tray_x := vs.x - 16.0
	pause_btn = Rect2()
	if not touch.active:
		var pr := Rect2(vs.x - 56, 12, 40, 40)
		var ph: bool = state == S.PLAY and pr.has_point(hud.get_local_mouse_position())
		hud.draw_rect(pr, Color(0.03, 0.035, 0.045, 0.78))
		hud.draw_rect(pr, UI.CYAN if state == S.PAUSE else Color(1, 1, 1, 0.55 if ph else 0.22), false, 1.0)
		UI.icon(hud, "pause", pr.get_center(), 20.0, UI.TEXT)
		UI.ctext(hud, font, pr.position + Vector2(0, 52), "ESC", 9, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 40)
		if state == S.PLAY:
			pause_btn = pr
		tray_x -= 50.0
	_draw_relic_tray(Vector2(tray_x, 12))
	if ending != "standard" or Cfg.endings_cleared.size() > 0:
		UI.text(hud, font, Vector2(tray_x - 220, 60 + 38 * maxi(1, int(ceil(relics.size() / 8.0)))), endg.cur_name(), 12, endg.cur_col(), HORIZONTAL_ALIGNMENT_RIGHT, 220, 2)

	# Boss 血条
	var bby := 0.0
	for shown in bosses:
		if shown.dead:
			continue
		var bw := 620.0
		var bx := vs.x / 2 - bw / 2
		hud.draw_set_transform(Vector2(0, bby), 0.0, Vector2.ONE)
		bby += 54.0
		# 洋红 = 危险（原作「险路恶敌」）：暗底 + 顶部洋红细线 + BOSS 节点标签条
		var bbr := Rect2(bx - 12, 100, bw + 24, 46)
		hud.draw_rect(bbr, Color(0.03, 0.035, 0.045, 0.8))
		hud.draw_rect(Rect2(bbr.position, Vector2(bbr.size.x, 1)), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.7))
		UI.strip(hud, font, Vector2(bx, 106), "BOSS", shown.name, UI.RED, Color(1, 0.82, 0.88), 12)
		var sub := ""
		if shown.type == "izumik":
			sub = "学习阶段 · 无敌（击杀子代阻止它成长）" if shown.phase == 1 else "解读阶段"
		elif shown.type == "ishar":
			sub = "转化进度 %d%%（清除伊莎玛拉之泪）" % int(shown.charge) if shown.phase == 1 else "已完成转化"
		elif shown.has("ammo"):
			sub = "装填中 —— 攻击以打断！" if shown.channel > 0.0 else ("弹药 %d / 3" % shown.ammo if shown.ammo > 0 else "近战中")
		elif shown.get("coma", false):
			sub = "昏迷中 —— 趁现在击倒另一体！"
		elif D.ENEMIES[shown.type].get("pair", false):
			sub = "两体需同时击倒"
		elif shown.type == "paranoia":
			sub = "悬浮形态（控制它以击落）" if shown.phase == 1 else "第二形态"
		UI.text(hud, font, Vector2(bx + bw - 400, 122), sub, 12, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 400)
		UI.gbar(hud, Rect2(bx, 131, bw, 6), shown.hp / shown.maxhp, Color(0.45, 0.6, 0.7) if shown.invuln else UI.RED, 20)
		if shown.type == "ishar" and shown.phase == 1:
			hud.draw_rect(Rect2(bx, 139, bw * shown.charge / 100.0, 2), UI.PURPLE)
		hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 右下：技能与援护干员
	_draw_squad_hud(Vector2(vs.x - 16, vs.y - 16))

	# 横幅通知
	if banner_t > 0.0:
		var a: float = clamp(banner_t, 0.0, 1.0)
		var by := vs.y * 0.24
		# 两端渐隐的暗带 + 上下从中间向两边淡出的细线（原作提示横幅）
		UI.fade_band(hud, Rect2(vs.x * 0.12, by - 30, vs.x * 0.76, 46), Color(0.03, 0.035, 0.045, 0.84 * a), 160.0)
		for yy in [by - 30.0, by + 16.0]:
			UI.hairline(hud, Vector2(vs.x / 2.0, yy), Vector2(vs.x * 0.16, yy), Color(1, 1, 1), 0.4 * a, 0.0)
			UI.hairline(hud, Vector2(vs.x / 2.0, yy), Vector2(vs.x * 0.84, yy), Color(1, 1, 1), 0.4 * a, 0.0)
		UI.text(hud, font, Vector2(0, by), banner, 21, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	# 开局提示：先移动，再提醒 Tab 属性面板；首次升级后再提醒一次
	if state == S.PLAY:
		if t < 6.0:
			UI.text(hud, font, Vector2(0, vs.y - 60), ("按住左半屏拖动移动 · 攻击全自动" if touch.active else Pad.hint("WASD 移动 · 攻击全自动 · Esc 暂停", "左摇杆移动 · 攻击全自动 · START 暂停")), 16, Color(0.7, 0.85, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		elif (t < 16.0 and not tab_used) or tab_hint > 0.0:
			var ha := clampf(minf(t - 6.0, 16.0 - t) / 0.5, 0.0, 1.0) if tab_hint <= 0.0 else clampf(tab_hint / 0.5, 0.0, 1.0)
			var pulse := 0.5 + 0.5 * sin(t * 5.0)
			var cx := vs.x / 2.0
			var y := vs.y - 78.0
			var box := Rect2(cx - 150, y - 22, 300, 40)
			hud.draw_rect(box, Color(0.03, 0.035, 0.045, 0.82 * ha))
			hud.draw_rect(box, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.3 + 0.5 * pulse) * ha), false, 1.0)
			UI.keycap(hud, font, Vector2(cx - 134, y - 12), Pad.hint("TAB", "SELECT"), Color(1, 1, 1, ha), 12)
			UI.text(hud, font, Vector2(cx - 72, y + 4), "查看博士与编队的属性", 15, Color(0.85, 0.95, 0.95, ha))

	_draw_relic_tooltip(vs)
	touch.draw_hud(vs)
	if not _overlay_left():
		_draw_status_bar(vs)
	_draw_dash_hint(vs)
	match state:
		S.SHOW:
			_draw_show(vs)
		S.INTRO:
			_draw_intro(vs)
		S.STATS:
			_draw_stats(vs)
		S.PAUSE:
			_draw_result(vs, "暂停", "PAUSED", UI.CYAN, [["继续", "Esc", "resume"], ["指南", "G", "guide"], ["设置", "O", "settings"], ["重新开始", "R", "restart"], ["回到标题", "T", "title"]])
		S.DEAD:
			_draw_result(vs, "探索终止", "OPERATION FAILED", UI.RED, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])
		S.WIN:
			_draw_result(vs, "%s · 探索完成" % D.ENDINGS[ending].name, D.ENDINGS[ending].en, endg.cur_col().lerp(UI.GOLD, 0.35), [["再次探索", "R", "restart"], ["回到标题", "T", "title"]], true)


## ---- 开局指南：6 页图文介绍（首次进入自动显示，暂停菜单按 G 可再看）
const INTRO_PAGES := [
	{"title": "欢迎来到深海", "en": "WELCOME", "icon": "mizuki", "lines": [
		"目标：在深海中存活 10 分钟，击败 10:00 登场的最终 Boss。第一次探索的终点是「偏执泡影」；之后的探索里，你的选择会把故事引向另外三个结局。",
		"你操控的是开局干员 —— 她是场上唯一会受伤的人，博士跟在身后指挥，招募来的干员跟随作战。所有人的普攻与三个技能全自动出手；你只需要用 WASD 移动、空格冲刺（冲刺中无敌）：走位、拉怪、躲弹幕、抢掉落。站在灯光里打，敌人受到的伤害 +25%。",
		"3:30 与 7:00 各有一次中期 Boss（从三组圣徒 / 海嗣里随机），击败后获得大量经验、源石锭与一件藏品。"]},
	{"title": "生命与灯火", "en": "HP & LAMPLIGHT", "icon": "bars", "lines": [
		"生命（绿条）归零即探索失败；血量低于 30% 时会有心跳与红色警告。医疗干员、回复药剂与部分藏品可以回血。",
		"灯火（金条）不会自己燃尽，只在受击时熄灭一截：伤害越重熄得越多，黑潮里也会持续流失。拾取敌人掉落的灯油、或向商人购买灯油补充。灯光范围内的敌人受到的伤害 +25%，灯越亮范围越大。",
		"灯火分四档 —— ≥70 充盈：技力回复 +30%、拾取范围 +20%；30–69 照亮：无加成也无惩罚。",
		"<30 昏暗：受到伤害 +15%，海嗣移速与接触伤害 +20%、刷新 +15%，拾取范围 -30%，灯光转红；0 熄灭：每秒失去 3 点生命。深海底部的抉择也会以灯火为代价。"]},
	{"title": "威胁等级与大群", "en": "THREAT & HORDE", "icon": "threat", "lines": [
		"计时器下方的进度条是威胁等级 Ⅰ→Ⅵ：浅滩 → 暗流(1:15) → 深潜(2:50) → 裂隙(4:40) → 深渊(6:40) → 深蓝之树(8:40)。每升一级会出现新的海嗣种类，旧种类逐渐退场。",
		"「大群来袭」：每隔一段时间（浅滩 90 秒一次，越深越频繁，最后 60 秒一次）会从四周涌来一整群海嗣。来袭前 3 秒有紫色预警和屏幕边缘的箭头 —— 包围圈总留有一个缺口，没有箭头的那一侧就是突围方向。",
		"精英海嗣定期出现（带金色光环与血条），击败必掉源石锭和补给箱；进化体（红色）更强，越到后期比例越高。敌人头顶的菱形是弱点：物理 / 法术对应类型伤害 +50%。"]},
	{"title": "溟痕与黑潮", "en": "MIRE & BLACK TIDE", "icon": "mire", "lines": [
		"紫黑色的溟痕会越来越多：站在里面会减速、持续掉血，并积累神经损伤（满了会僵直）。远程海嗣的弹幕落地也会留下溟痕。",
		"2:30 起安全区开始收缩（小地图上的紫色圆圈）。圈外是「黑潮」，会快速掉血、流失灯火。",
		"看到「黑潮将至」提示时，提前往白色虚线圈里走。收缩共 4 轮，越到后期战场越小，大群来袭时更要注意走位。"]},
	{"title": "成长路线", "en": "GROWTH", "icon": "cards", "lines": [
		"击败敌人掉落经验，升级时三选一：干员深度卡（数值 / 精英化）、博士被动、全队被动，Lv.5 起会出现招募卡；医疗无人机升级也是常规选项（最高 Lv.5）。第一次拿到新技能或进阶时会有演示。",
		"每名干员招募即有一技能，精英化一解锁二技能与天赋，精英化二解锁三技能。三个技能全部自动释放，先练谁、练到几精是这一局的核心取舍。",
		"编队最多 3 名常规干员（开局 1 名 + 局内招募 2 名）。开局自带一架医疗无人机，全输出编队也有保底回复。按 Tab 随时查看博士属性、编队与藏品效果。"]},
	{"title": "资源与宝箱", "en": "LOOT", "icon": "loot", "lines": [
		"精英与 Boss 掉落源石锭、补给箱（打开得藏品）与磁铁 / 回复药剂。补给箱也会定期在地图上出现（屏幕边缘有指示）。",
		"小心伪装成宝箱的箱形恐鱼 —— 它现形扑来时会造成伤害，但击败后掉落大量源石锭。",
		"藏品分基础 / 稀有 / 核心 / 升华，同一件再次拿到会升级；商店里偶尔有「遭诅古物」：效果强但带代价。"]},
	{"title": "商人只停留 60 秒", "en": "MERCHANT", "icon": "merchant", "lines": [
		"商人每局出现 3 次：2:00、5:00、8:00，都在 Boss 登场之前。出现时有横幅提示，屏幕边缘的金色箭头会一直指向他，小地图上也有标记。",
		"他只停留 60 秒：头顶显示倒计时，最后 15 秒会有横幅提醒并变红闪烁 —— 还没交易就先放下手里的怪去找他，错过就要等下一次。",
		"靠近即可用源石锭购买藏品、急救包与灯油；每次到访只能花钱刷新一次货架（按 F）。交易完成后他会自行离开。"]},
	{"title": "海嗣祭坛与结局", "en": "ALTAR & ENDINGS", "icon": "altar", "lines": [
		"通关一次之后，深海里会出现「海嗣祭坛」：打碎它做出选择，选项会给你藏品、灯火或代价。每个祭坛都在固定的时间段必定出现，可以规划。",
		"结局由你做出的决定决定，后做的决定覆盖先做的；右上角藏品栏下方与 Tab 面板会一直显示当前走向，9:00 有终局预告。",
		"四个结局各有不同的最终 Boss 与后半程规则，达成后会收录进标题页的图鉴「结局」分页。"]},
	{"title": "操作", "en": "CONTROLS", "icon": "keys", "lines": [
		"WASD / 方向键：移动　　Tab 或 C：查看属性与技能　　Esc：暂停",
		"升级 / 宝箱 / 商人 / 祭坛：按 1 2 3 或点击选择　　M：静音　　R：重来",
		"手柄：左摇杆移动 · Ⓐ 确认 · Ⓑ 返回 · START 暂停 · SELECT 属性面板 · LB / RB 翻页。暂停菜单按 G 可随时重看本指南。祝你好运，博士。"]},
]


func _open_intro(back: int) -> void:
	intro_back = back
	intro_page = 0
	intro_t = 0.0
	state = S.INTRO


func _intro_next() -> void:
	Sfx.play("ui_move")
	if intro_page < INTRO_PAGES.size() - 1:
		intro_page += 1
		intro_t = 0.0
	else:
		_close_intro()


func _close_intro() -> void:
	Cfg.seen_intro = true
	Cfg.save()
	state = intro_back
	Sfx.play("ui_ok", -4.0)


func _draw_intro(vs: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.88))
	var pg: Dictionary = INTRO_PAGES[intro_page]
	var rh: float = minf(570.0, vs.y - 16.0)
	var r := Rect2(vs.x / 2 - 450, vs.y / 2 - rh / 2.0, 900, rh)
	var ea := clampf(intro_t / 0.25, 0.0, 1.0)
	r.position.y += (1.0 - ea) * 20.0
	UI.panel(hud, r, UI.BG2, UI.LINE, 16.0, UI.CYAN)
	UI.en(hud, font, r.position + Vector2(40, 46), "GUIDE  %d / %d  ·  %s" % [intro_page + 1, INTRO_PAGES.size(), pg.en], 12, UI.CYAN, 3.0)
	UI.text(hud, font, r.position + Vector2(40, 90), pg.title, 30, UI.TEXT)
	hud.draw_line(r.position + Vector2(40, 108), r.position + Vector2(r.size.x - 40, 108), UI.CYAN_DIM, 1.0)
	# 插图区
	var ic := r.position + Vector2(170, 270)
	_draw_intro_icon(pg.icon, ic)
	# 文字
	var y := r.position.y + 156
	for ln in pg.lines:
		UI.diamond(hud, Vector2(r.position.x + 340, y - 6), 4.0, UI.CYAN)
		hud.draw_multiline_string(font, Vector2(r.position.x + 356, y), UI.soft(ln), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 392, 15, 4, Color(0.85, 0.93, 0.95, ea), UI.BRK)
		y += 100
	# 页码点（可点击）
	intro_panel = r
	intro_dots.clear()
	var mp: Vector2 = hud.get_local_mouse_position()
	for i in INTRO_PAGES.size():
		var dp := Vector2(vs.x / 2 - (INTRO_PAGES.size() - 1) * 13 + i * 26, r.end.y - 30)
		var dr := Rect2(dp - Vector2(12, 12), Vector2(24, 24))
		intro_dots.append([dr, i])
		var hov: bool = dr.has_point(mp)
		UI.diamond(hud, dp, 6.0 if hov else 5.0, UI.CYAN if i == intro_page else (Color(0.3, 0.5, 0.55) if hov else Color(0.15, 0.25, 0.28)))
	# 上一页 / 跳过 / 下一页 按钮
	var btns: Array = [["‹ 上一页", "prev"], [Pad.hint("跳过  Esc", "跳过  Ⓑ"), "skip"], ["下一页 ›", "next"]]
	for k in 3:
		var bw := 118.0
		var bx: float = [r.position.x + 40, vs.x / 2 - bw / 2.0, r.end.x - 40 - bw][k]
		var br := Rect2(bx, r.end.y - 52, bw, 34)
		match k:
			0: intro_btn_prev = br
			1: intro_btn_skip = br
			2: intro_btn_next = br
		var hov2: bool = br.has_point(mp)
		var dim: bool = k == 0 and intro_page == 0
		if k == 1:
			br.position.y = r.end.y + 16
			intro_btn_skip = br
			UI.text(hud, font, br.position + Vector2(0, 22), btns[k][0], 13, UI.CYAN if hov2 else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
			continue
		UI.frame(hud, br, UI.CYAN, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov2 else 0.0, "alpha": 0.3 if dim else (1.0 if hov2 else 0.7)})
		UI.text(hud, font, br.position + Vector2(0, 23), btns[k][0] if k != 2 or intro_page < INTRO_PAGES.size() - 1 else "开始探索 ›", 14, UI.TEXT if not dim else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	UI.text(hud, font, Vector2(r.position.x, r.end.y + 60), Pad.hint("左键 / 任意键：下一页　　右键 / ←：上一页　　点面板左侧也可回退", "Ⓐ / → / RB：下一页　　← / LB：上一页　　Ⓑ：跳过"), 12, Color(0.45, 0.55, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_intro_icon(kind: String, c: Vector2) -> void:
	match kind:
		"mizuki":
			# 开局干员的攻击动作（水月沿用 48px 挥伞条）
			var tx: Texture2D = tex.get("player_attack_48") if ch.id == "mizuki" else ch.anim_tex("attack")
			if tx != null:
				var fh0 := tx.get_height()
				var fr := int(intro_t * 8.0) % maxi(1, tx.get_width() / fh0)
				hud.draw_texture_rect_region(tx, Rect2(c - Vector2(96, 150), Vector2(192, 192)), Rect2(fh0 * fr, 0, fh0, fh0))
			for k in 3:
				var et: Texture2D = tex.get(["e_bone", "e_slider", "e_stone"][k])
				if et != null:
					var fw := et.get_width() / 2
					hud.draw_texture_rect_region(et, Rect2(c + Vector2(-110 + k * 90, 70), Vector2(fw, et.get_height()) * 2.0), Rect2(0, 0, fw, et.get_height()))
		"bars":
			UI.en(hud, font, c + Vector2(-110, -60), "HP", 12, UI.SUB, 2.0)
			UI.bar(hud, Rect2(c + Vector2(-80, -72), Vector2(180, 14)), 0.7, Color(0.35, 0.9, 0.75), 10)
			UI.en(hud, font, c + Vector2(-110, -10), "LIGHT", 12, UI.GOLD, 1.0)
			UI.bar(hud, Rect2(c + Vector2(-50, -22), Vector2(150, 14)), 0.55, UI.GOLD, 5)
			for tv in [30.0, 70.0]:
				var tx2: float = c.x - 50 + 150 * tv / 100.0
				hud.draw_line(Vector2(tx2, c.y - 26), Vector2(tx2, c.y - 4), Color(1, 1, 1, 0.8), 1.5)
			var ot: Texture2D = tex.get("oil")
			if ot != null:
				hud.draw_texture_rect(ot, Rect2(c + Vector2(-20, 30), Vector2(36, 48)), false)
			UI.text(hud, font, c + Vector2(26, 64), "灯油", 14, UI.GOLD)
		"mire":
			var mt: Texture2D = tex.get("terrain_mire")
			if mt != null:
				var fw := mt.get_width() / 2
				hud.draw_texture_rect_region(mt, Rect2(c - Vector2(80, 110), Vector2(160, 160)), Rect2(fw * (int(intro_t * 2.0) % 2), 0, fw, mt.get_height()))
			hud.draw_arc(c + Vector2(0, 40), 140.0, PI * 1.1, PI * 1.9, 32, Color(0.85, 0.4, 1.0), 3.0)
			UI.text(hud, font, c + Vector2(-60, 110), "黑潮边界", 14, Color(0.85, 0.5, 1.0))
		"cards":
			# 三张示意卡：开局干员的待机帧（成长）/ 另一名干员的待机帧（招募）/ 被动图标
			var other_id := ""
			for cid0 in Character.list_ids():
				if cid0 != ch.id and Character.load_def(cid0).get("recruitable", true):
					other_id = cid0
					break
			for k in 3:
				var rc := Rect2(c + Vector2(-130 + k * 88, -90), Vector2(76, 110))
				var cc: Color = [UI.CYAN, Color(0.55, 0.95, 1.0), UI.GOLD][k]
				UI.panel(hud, rc, Color(0.03, 0.08, 0.1), cc, 6.0)
				var cc0 := rc.position + Vector2(rc.size.x / 2.0, 48)
				if k < 2:
					var idl: Dictionary = _op_idle(ch.id if k == 0 else other_id)
					if not idl.is_empty():
						var ks: float = 1.5 if idl.fh <= 48 else 72.0 / idl.fh
						var asz := Vector2(idl.fw, idl.fh) * ks
						hud.draw_texture_rect_region(idl.tex, Rect2(cc0 - asz / 2.0 + Vector2(0, 4), asz), Rect2(0, 0, idl.fw, idl.fh))
				else:
					var gt: Texture2D = tex.get("growth_hp")
					if gt != null:
						hud.draw_texture_rect(gt, Rect2(cc0 - Vector2(24, 24), Vector2(48, 48)), false)
				UI.text(hud, font, rc.position + Vector2(0, 100), ["成长", "招募", "被动"][k], 12, cc, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
			UI.text(hud, font, c + Vector2(-130, 60), "干员成长 / 招募 / 博士被动", 14, UI.SUB)
		"loot":
			var items := ["ingot", "e_chest", "pickup_magnet", "pickup_heal", "merchant"]
			for k in items.size():
				var tx3: Texture2D = tex.get(items[k])
				if tx3 == null:
					continue
				var frames := 2 if items[k] == "e_chest" or items[k] == "merchant" else 1
				var fw := tx3.get_width() / frames
				var sc: float = 3.0 if tx3.get_height() < 20 else 2.0
				var sz := Vector2(fw, tx3.get_height()) * sc
				var p := c + Vector2(-120 + (k % 3) * 100, -70 + (k / 3) * 100)
				hud.draw_texture_rect_region(tx3, Rect2(p - sz / 2.0, sz), Rect2(0, 0, fw, tx3.get_height()))
		"threat":
			# 威胁等级条 Ⅰ–Ⅵ + 大群预警环
			var names := ["浅滩", "暗流", "深潜", "裂隙", "深渊", "深蓝之树"]
			var lit: int = int(intro_t * 1.2) % 7
			for k in 6:
				var rc := Rect2(c + Vector2(-138 + k * 46, -96), Vector2(40, 14))
				var on: bool = k < lit
				hud.draw_rect(rc, Color(0.6, 0.35, 1.0, 0.9) if on else Color(0.08, 0.12, 0.16))
				hud.draw_rect(rc, Color(0.7, 0.5, 1.0, 0.8), false, 1.0)
				UI.text(hud, font, rc.position + Vector2(0, -6), ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][k], 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
				UI.text(hud, font, rc.position + Vector2(-8, 30), names[k], 10, UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x + 16)
			var hk: float = fmod(intro_t, 2.4) / 2.4
			hud.draw_arc(c + Vector2(0, 30), 30.0 + hk * 90.0, 0.0, TAU, 48, Color(0.75, 0.3, 1.0, 0.7 * (1.0 - hk)), 3.0)
			hud.draw_arc(c + Vector2(0, 30), 36.0, 0.0, TAU, 32, Color(0.75, 0.3, 1.0, 0.5), 2.0)
			var etx: Texture2D = tex.get("e_bone")
			if etx != null:
				for k in 8:
					var an: float = TAU * k / 8.0 + intro_t * 0.4
					var fw2: int = etx.get_width() / 2
					var pp: Vector2 = c + Vector2(0, 30) + Vector2.from_angle(an) * (78.0 - 30.0 * hk)
					hud.draw_texture_rect_region(etx, Rect2(pp - Vector2(fw2, etx.get_height()), Vector2(fw2, etx.get_height()) * 2.0), Rect2(0, 0, fw2, etx.get_height()))
			UI.text(hud, font, c + Vector2(-60, 116), "大群来袭", 14, Color(0.85, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120)
		"merchant":
			var mtx: Texture2D = tex.get("merchant")
			if mtx != null:
				var fw3: int = mtx.get_width() / 2
				var fr3: int = int(intro_t * 2.0) % 2
				var sz3 := Vector2(fw3, mtx.get_height()) * 3.0
				hud.draw_texture_rect_region(mtx, Rect2(c - Vector2(sz3.x / 2.0, sz3.y - 40), sz3), Rect2(fw3 * fr3, 0, fw3, mtx.get_height()))
			var left: int = 60 - int(fmod(intro_t * 6.0, 60.0))
			var mc: Color = UI.GOLD if left > 15 else UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(intro_t * 8.0))
			UI.ring(hud, c + Vector2(0, -120), 22.0, left / 60.0, mc)
			UI.text(hud, font, c + Vector2(-30, -114), "%ds" % left, 15, mc, HORIZONTAL_ALIGNMENT_CENTER, 60)
			UI.text(hud, font, c + Vector2(-80, 74), "商人  ·  停留 60 秒", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 160)
			for k in 3:
				UI.chip(hud, font, c + Vector2(-118 + k * 84, 90), ["2:00", "5:00", "8:00"][k], UI.GOLD, 12)
		"altar":
			var atx: Texture2D = tex.get("e_event")
			if atx != null:
				var fw4: int = atx.get_width() / 2
				var fr4: int = int(intro_t * 2.0) % 2
				var sz4 := Vector2(fw4, atx.get_height()) * 4.0
				hud.draw_set_transform(c + Vector2(0, 46), 0.0, Vector2(1.0, 0.45))
				hud.draw_circle(Vector2.ZERO, 70.0 + 6.0 * sin(intro_t * 3.0), Color(0.3, 0.6, 1.4, 0.18))
				hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				hud.draw_texture_rect_region(atx, Rect2(c - Vector2(sz4.x / 2.0, sz4.y - 50), sz4), Rect2(fw4 * fr4, 0, fw4, atx.get_height()))
			var ends := [["Ⅰ", Color(0.8, 0.6, 1.0)], ["Ⅱ", Color(0.6, 0.85, 1.0)], ["Ⅲ", UI.GOLD], ["Ⅳ", Color(0.35, 0.55, 1.0)]]
			for k in 4:
				var ec: Color = ends[k][1]
				UI.diamond(hud, c + Vector2(-66 + k * 44, 92), 9.0, Color(ec.r, ec.g, ec.b, 0.35), ec)
				UI.text(hud, font, c + Vector2(-86 + k * 44, 122), ends[k][0], 13, ec, HORIZONTAL_ALIGNMENT_CENTER, 40)
		"keys":
			var keys := [["W", Vector2(0, -60)], ["A", Vector2(-48, -12)], ["S", Vector2(0, -12)], ["D", Vector2(48, -12)], ["Tab", Vector2(-40, 60)], ["Esc", Vector2(40, 60)]]
			for kk in keys:
				var kr := Rect2(c + kk[1] - Vector2(20, 20), Vector2(40 if kk[0].length() == 1 else 56, 40))
				hud.draw_rect(kr, Color(0.08, 0.2, 0.24))
				hud.draw_rect(kr, UI.CYAN, false, 1.5)
				UI.text(hud, font, kr.position + Vector2(0, 27), kk[0], 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)


## 属性面板（Tab / C 打开，游戏暂停）
func _draw_stats(vs: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.05, 0.82))
	var r := Rect2(60, 44, vs.x - 120, vs.y - 88)
	UI.frame(hud, r, UI.GLOW, {"t": t, "vines": true, "seed": 31, "cut": 14.0, "bracket": 14.0, "glow": 0.3})
	UI.caustic(hud, Rect2(r.position + Vector2(20, 8), Vector2(r.size.x - 40, 22)), t, UI.GLOW)
	# 标题行
	var pt: Texture2D = tex.get("doctor", tex.get("player_idle"))
	if pt != null:
		var fh := pt.get_height()
		var fr := int(t * 2.0) % maxi(1, pt.get_width() / fh)
		hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(26, 14), Vector2(fh, fh) * 1.5 / A.hires_of(pt)), Rect2(fr * fh, 0, fh, fh))
	UI.text(hud, font, r.position + Vector2(108, 50), doctor.name(), 28, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	var dn_w := font.get_string_size(doctor.name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var en_w := UI.en(hud, font, r.position + Vector2(118 + dn_w, 48), doctor.def.get("en", "DOCTOR") + "  ·  STATUS", 12, UI.CYAN, 3.0)
	var cx0 := maxf(r.position.x + 350, r.position.x + 118 + dn_w + en_w + 18)
	cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), "Lv.%d" % level, UI.GLOW, 12) + 8
	cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), "编队 %d/%d" % [squad.size(), squad.cap()], UI.CYAN_DIM, 12) + 8
	cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), "难度 %d「%s」" % [diff, D.DIFFICULTY[diff].name], UI.CYAN_DIM, 12) + 14
	cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), endg.cur_name(), endg.cur_col(), 11) + 14
	# 角色能力标签（来自角色 JSON）
	for tg in ch.display_tags():
		cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), tg, UI.PURPLE, 11) + 6
	UI.rule(hud, r.position + Vector2(24, 82), Vector2(r.end.x - 24, r.position.y + 82), UI.EDGE_DIM)
	# 三个子面板
	stats_cells.clear()
	var top := r.position.y + 98
	var h := r.end.y - 44 - top
	var boxes: Array = [Rect2(r.position.x + 22, top, 330, h), Rect2(r.position.x + 366, top, 330, h), Rect2(r.position.x + 710, top, r.size.x - 732, h)]
	for b in boxes:
		UI.frame(hud, b, UI.EDGE, {"cut": 8.0, "bracket": 8.0, "alpha": 0.6})
	# ---- 生存
	var b0: Rect2 = boxes[0]
	UI.text(hud, font, b0.position + Vector2(16, 26), "生存", 16, UI.CYAN)
	UI.en(hud, font, b0.position + Vector2(60, 25), "SURVIVAL", 10, UI.CYAN_DIM, 3.0)
	var y: float = b0.position.y + 48
	UI.text(hud, font, b0.position + Vector2(16, y - b0.position.y + 12), "生命", 13, UI.SUB)
	UI.gbar(hud, Rect2(b0.position.x + 70, y, 180, 10), hp / max_hp, UI.CYAN, 10)
	UI.text(hud, font, Vector2(b0.position.x + 258, y + 11), "%d / %d" % [int(hp), int(max_hp)], 13, UI.TEXT)
	y += 26
	UI.text(hud, font, Vector2(b0.position.x + 16, y + 12), "灯火", 13, UI.SUB)
	UI.gbar(hud, Rect2(b0.position.x + 70, y, 180, 10), lamp / 100.0, UI.GOLD, 10)
	UI.text(hud, font, Vector2(b0.position.x + 258, y + 11), "%d" % int(lamp), 13, UI.TEXT)
	y += 30
	var rows0 := [
		["生命回复", "%.1f / 秒" % (regen + regen_pct * max_hp)], ["物理减伤 / 法抗", "%d / %d%%" % [int(armor), int(arts_res * 100.0)]], ["闪避 物 / 法", "%d%% / %d%%" % [int(minf(dodge + dodge_phys, 0.6) * 100.0), int(minf(dodge + dodge_arts, 0.6) * 100.0)]],
		["移动速度", "%d" % int(speed)], ["拾取范围", "%d" % int(pickup)], ["受击灯火损失", "×%.2f" % lamp_decay],
		["照亮范围", "%d" % int(_lamp_r())],
		["护盾", ("%d / %d · 每 %.1f 秒" % [shield, shield_max, shield_every]) if shield_max > 0 else "无"],
	]
	for row in rows0:
		UI.text(hud, font, Vector2(b0.position.x + 16, y + 12), row[0], 14, UI.SUB)
		UI.text(hud, font, Vector2(b0.position.x + 130, y + 12), row[1], 14, UI.TEXT)
		hud.draw_rect(Rect2(b0.position.x + 16, y + 19, b0.size.x - 32, 1), Color(1, 1, 1, 0.05))
		y += 25
	# ---- 攻击
	var b1: Rect2 = boxes[1]
	UI.text(hud, font, b1.position + Vector2(16, 26), "攻击", 16, UI.CYAN)
	UI.en(hud, font, b1.position + Vector2(60, 25), "OFFENSE", 10, UI.CYAN_DIM, 3.0)
	var rows1: Array = ch.stats_rows()
	rows1.append_array([
		["近战 / 远程", "×%.2f / ×%.2f" % [melee_mult, ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [phys_mult, arts_mult]],
		["本局构成", _dmg_mix_text()],
	])
	y = b1.position.y + 48
	for row in rows1:
		UI.text(hud, font, Vector2(b1.position.x + 16, y + 12), row[0], 14, UI.SUB)
		UI.text(hud, font, Vector2(b1.position.x + 130, y + 12), row[1], 14, UI.TEXT)
		hud.draw_rect(Rect2(b1.position.x + 16, y + 19, b1.size.x - 32, 1), Color(1, 1, 1, 0.05))
		y += 25
	# 技能（攻击面板下半）
	y += 8
	UI.rule(hud, Vector2(b1.position.x + 16, y), Vector2(b1.end.x - 16, y), UI.EDGE_DIM)
	y += 10
	y = _draw_generic_skill_rows(b1, y)
	# ---- 队伍与成长
	var b2: Rect2 = boxes[2]
	UI.text(hud, font, b2.position + Vector2(16, 26), "队伍与成长", 16, UI.CYAN)
	UI.en(hud, font, b2.position + Vector2(110, 25), "BUILD", 10, UI.CYAN_DIM, 3.0)
	y = b2.position.y + 44
	UI.text(hud, font, Vector2(b2.position.x + 16, y + 12), "编队 %d/%d" % [squad.size(), squad.cap()], 13, UI.SUB)
	y += 22
	for o in squad.ops:
		var ax2: float = b2.position.x + 16
		var opt: Dictionary = o.portrait()
		var at: Texture2D = tex.get(opt.tex)
		if at != null:
			var fw := at.get_width() / int(opt.frames)
			var ks := 26.0 / at.get_height()
			hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 6), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
			ax2 += fw * ks + 6
		UI.text(hud, font, Vector2(ax2, y + 12), "%s · %s" % [o.display_name(), o.cls], 13, UI.TEXT)
		ax2 += 116
		ax2 += UI.chip(hud, font, Vector2(ax2, y), ["精零", "精一", "精二"][o.elite], UI.GOLD if o.elite > 0 else UI.SUB, 10) + 6
		# 成长线进度点
		var pg: Array = o.progression()
		for k in pg.size():
			var dc := Vector2(ax2 + k * 12, y + 8)
			var done: bool = k < o.prog
			var is_elite: bool = pg[k].get("type", "") == "elite"
			if is_elite:
				UI.diamond(hud, dc, 4.0, UI.GOLD if done else Color(0.08, 0.14, 0.18), Color(1.0, 0.85, 0.5, 0.8))
			else:
				hud.draw_circle(dc, 3.0, Color(0.55, 0.9, 0.55) if done else Color(0.1, 0.18, 0.22))
		ax2 += pg.size() * 12 + 8
		var nn: Dictionary = o.next_node()
		if not nn.is_empty():
			var rq: String = o.node_requires_text(nn)
			var ok_rq: bool = o.node_available(nn)
			UI.text(hud, font, Vector2(ax2, y + 12), ("下一步：%s" % nn.get("name", "")) + (("（需%s）" % rq) if rq != "" and not ok_rq else ""), 11, UI.SUB if ok_rq else Color(1.0, 0.7, 0.5), HORIZONTAL_ALIGNMENT_LEFT, b2.end.x - ax2 - 12)
		else:
			UI.text(hud, font, Vector2(ax2, y + 12), "已满", 11, UI.GOLD)
		y += 30
	y += 6
	UI.text(hud, font, Vector2(b2.position.x + 16, y + 12), "支援", 13, UI.SUB)
	var ax2: float = b2.position.x + 90
	if weapons.is_empty():
		UI.text(hud, font, Vector2(ax2, y + 12), "暂无", 13, UI.SUB)
	for wid in weapons:
		var wt: Texture2D = tex.get("weapon_" + wid)
		if wt != null:
			hud.draw_texture_rect(wt, Rect2(Vector2(ax2, y - 6), Vector2(32, 32)), false)
		UI.text(hud, font, Vector2(ax2 + 36, y + 14), "%s  Lv.%d" % [D.WEAPONS[wid].name, weapons[wid]], 13, D.WEAPONS[wid].col)
		ax2 += 150
	y += 36
	UI.rule(hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(hud, font, Vector2(b2.position.x + 16, y + 12), "成长", 13, UI.SUB)
	y += 22
	# 成长：图标网格，右下角次数
	var gx: float = b2.position.x + 16
	var gy: float = y
	var per := int((b2.size.x - 32) / 44.0)
	var gi := 0
	for gid in growth:
		var gc := Vector2(gx + (gi % per) * 44, gy + (gi / per) * 46)
		if gc.y + 40 > b2.end.y - 8:
			break
		hud.draw_rect(Rect2(gc, Vector2(38, 38)), Color(0.01, 0.04, 0.08, 0.9))
		hud.draw_rect(Rect2(gc, Vector2(38, 38)), UI.EDGE_DIM, false, 1.0)
		var gt: Texture2D = tex.get("growth_" + gid)
		if gt != null:
			hud.draw_texture_rect(gt, Rect2(gc + Vector2(3, 3), Vector2(32, 32)), false)
		else:
			UI.text(hud, font, gc + Vector2(0, 26), progression.growth_def(gid).name.substr(0, 1), 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 38)
		UI.text(hud, font, gc + Vector2(20, 37), "×%d" % growth[gid], 10, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		stats_cells.append([Rect2(gc, Vector2(38, 38)), "growth", gid])
		gi += 1
	# 藏品：图标网格（悬停看效果）
	y = gy + (maxi(0, gi - 1) / per + 1) * 46 + 6
	UI.rule(hud, Vector2(b2.position.x + 16, y), Vector2(b2.end.x - 16, y), UI.EDGE_DIM)
	y += 8
	UI.text(hud, font, Vector2(b2.position.x + 16, y + 12), "藏品  %d 件" % relics.size(), 13, UI.SUB)
	UI.text(hud, font, Vector2(b2.position.x + 120, y + 12), "鼠标移到图标上查看效果", 11, UI.CYAN_DIM)
	y += 22
	var mouse2 := hud.get_local_mouse_position()
	for i in relics.size():
		var rc := Vector2(gx + (i % per) * 44, y + (i / per) * 46)
		if rc.y + 40 > b2.end.y - 8:
			break
		var rd: Dictionary = RL[relics[i]]
		var rcol: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var cr := Rect2(rc, Vector2(38, 38))
		var hov: bool = cr.has_point(mouse2)
		hud.draw_rect(cr, Color(0.01, 0.04, 0.08, 0.9) if not hov else Color(rcol.r * 0.25, rcol.g * 0.25, rcol.b * 0.25, 0.95))
		hud.draw_rect(cr, Color(rcol.r, rcol.g, rcol.b, 0.7 if not hov else 1.0), false, 1.0 if not hov else 2.0)
		var rt: Texture2D = tex.get("relic_" + relics[i])
		if rt != null:
			hud.draw_texture_rect(rt, Rect2(rc + Vector2(3, 3), Vector2(32, 32)), false)
		else:
			UI.text(hud, font, rc + Vector2(0, 26), rd.name.substr(0, 1), 16, rcol, HORIZONTAL_ALIGNMENT_CENTER, 38)
		var rl: int = rfx.lv.get(relics[i], 1)
		if rl > 1:
			UI.text(hud, font, rc + Vector2(20, 37), "L%d" % rl, 10, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		stats_cells.append([cr, "relic", relics[i]])
	UI.text(hud, font, Vector2(r.position.x, r.end.y - 18), ("藏品 %d 件  ·  击杀 %d  ·  源石锭 %d  ·  " % [relics.size(), kills, ingots]) + Pad.hint("按 Tab / C / Esc 返回", "按 SELECT / Ⓑ 返回"), 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	# 悬停提示（藏品 / 成长）
	for cellinfo in stats_cells:
		var cr2: Rect2 = cellinfo[0]
		if not cr2.has_point(mouse2):
			continue
		if cellinfo[1] == "relic":
			var rd2: Dictionary = RL[cellinfo[2]]
			_draw_tooltip(vs, cr2, rd2.name + ((" Lv.%d/%d" % [rfx.lv.get(cellinfo[2], 1), rfx.max_lv(cellinfo[2])]) if rfx.max_lv(cellinfo[2]) > 1 else ""), "%s · %s" % [rd2.cat, rd2.rarity], rd2.desc, "relic_" + cellinfo[2], UI.CAT_COL.get(rd2.cat, UI.GOLD))
		else:
			var gd: Dictionary = progression.growth_def(cellinfo[2])
			_draw_tooltip(vs, cr2, "%s  ×%d" % [gd.name, growth[cellinfo[2]]], "成长 · 上限 %d" % gd.max, gd.desc, "growth_" + cellinfo[2], UI.GLOW)
		break


## 小地图（左下）：以水月为中心，显示约 1100 范围内的敌人、精英、Boss、宝箱、道具与商人
func _draw_minimap(vs: Vector2) -> void:
	var rad := 78.0
	var c := Vector2(16 + rad + 8, vs.y - rad - 24)
	UI.porthole(hud, c, rad, UI.GLOW)
	var slr := Rect2(Vector2(c.x - rad + 2, c.y - rad - 8), Vector2(UI.en_width(font, "SONAR", 9, 2.0) + 10.0, 14))
	hud.draw_rect(slr, Color(1, 1, 1, 0.14))
	UI.en(hud, font, slr.position + Vector2(5, 11), "SONAR", 9, Color(0.81, 0.84, 0.86), 2.0)
	var world := 1100.0
	var k := (rad - 8.0) / world
	var lim := rad - 6.0
	# 声呐扫描线
	var sweep := fmod(t * 0.9, TAU)
	hud.draw_line(c, c + Vector2.from_angle(sweep) * lim, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.35), 1.0)
	for q in 6:
		var a := sweep - q * 0.06
		hud.draw_line(c, c + Vector2.from_angle(a) * lim, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.06 * (6 - q) / 6.0), 3.0)
	hud.draw_arc(c, lim * 0.5, 0.0, TAU, 40, Color(UI.GLOW.r, UI.GLOW.g, UI.GLOW.b, 0.12), 1.0)
	# 视野框
	var view := get_viewport_rect().size
	hud.draw_rect(Rect2(c - view * 0.5 * k, view * k), Color(1, 1, 1, 0.2), false, 1.0)
	for e in enemies:
		if e.dead:
			continue
		var p: Vector2 = (e.pos - ppos) * k
		if p.length() > lim:
			if e.boss:
				p = p.limit_length(lim)
			else:
				continue
		if e.boss:
			var bp := 0.5 + 0.5 * sin(t * 6.0)
			hud.draw_circle(c + p, 5.0 + bp, Color(0.8, 0.3, 1.0))
		elif e.chest:
			hud.draw_rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), Color(0.55, 0.8, 1.0) if e.get("event", "") != "" else UI.GOLD)
		elif e.elite:
			hud.draw_rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.6, 0.25))
		else:
			hud.draw_rect(Rect2(c + p - Vector2(1, 1), Vector2(2, 2)), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.85))
	for g in gems:
		if g.dead or not (g.kind == "magnet" or g.kind == "heal" or g.kind == "chest"):
			continue
		var p: Vector2 = ((g.pos - ppos) * k).limit_length(lim)
		hud.draw_circle(c + p, 3.0, pickups.item_col(g.kind))
	if not merchant.is_empty():
		var mp: Vector2 = ((merchant.pos - ppos) * k)
		var clipped := mp.length() > lim
		mp = mp.limit_length(lim)
		UI.diamond(hud, c + mp, 5.0 + (1.5 * sin(t * 6.0) if clipped else 0.0), UI.GOLD)
	for o in squad.ops:
		if o.pos != Vector2.INF:
			hud.draw_circle(c + (o.pos - ppos) * k, 2.0, Color(0.5, 0.9, 1.0))
	if zone_state != 0:
		_mini_circle(c + (zone_c - ppos) * k, zone_r * k, lim, Color(0.85, 0.4, 1.0, 0.9), c)
		if zone_state == 1:
			_mini_circle(c + (zone_next_c - ppos) * k, zone_next_r * k, lim, Color(1, 1, 1, 0.6), c)
	UI.diamond(hud, c, 4.0, Color(1, 1, 1))


func _mini_circle(cc: Vector2, r: float, lim: float, col: Color, c: Vector2) -> void:
	var n := 48
	for i in n:
		var p0 := cc + Vector2.from_angle(TAU * i / n) * r
		var p1 := cc + Vector2.from_angle(TAU * (i + 1) / n) * r
		if (p0 - c).length() > lim or (p1 - c).length() > lim:
			continue
		hud.draw_line(p0, p1, col, 1.5)


func _edge_glow(vs: Vector2, col: Color, w: float) -> void:
	var c0 := col
	var c1 := Color(col.r, col.g, col.b, 0.0)
	hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, w), Vector2(0, w)]), PackedColorArray([c0, c0, c1, c1]))
	hud.draw_polygon(PackedVector2Array([Vector2(0, vs.y - w), Vector2(vs.x, vs.y - w), vs, Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
	hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
	hud.draw_polygon(PackedVector2Array([Vector2(vs.x - w, 0), Vector2(vs.x, 0), vs, Vector2(vs.x - w, vs.y)]), PackedColorArray([c1, c0, c0, c1]))


func _draw_relic_tray(tr: Vector2) -> void:
	var n := relics.size()
	var per_row := 8
	var cell := 38.0
	var w: float = max(min(n, per_row) * cell + 12.0, 132.0)
	var rows: int = max(1, int(ceil(n / float(per_row))))
	var o := tr + Vector2(-w, 0)
	var r := Rect2(o, Vector2(w, rows * cell + 30))
	# 原作底栏「收藏品 N」：暗底 + 图标 + 数量，下面一排藏品格（左上角一小段分类色）
	hud.draw_rect(r, Color(0.03, 0.035, 0.045, 0.74))
	hud.draw_rect(Rect2(o, Vector2(w, 1)), Color(1, 1, 1, 0.14))
	UI.icon(hud, "box", o + Vector2(15, 14), 14.0, Color(0.81, 0.84, 0.86))
	UI.text(hud, font, o + Vector2(28, 19), "收藏品", 12, Color(0.81, 0.84, 0.86))
	if w >= 180.0:
		UI.en(hud, font, o + Vector2(70, 18), "RELICS", 9, UI.SUB, 2.0)
	UI.ctext(hud, font, o + Vector2(w - 34, 20), "%d" % n, 17, UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 24)
	tray_cells.clear()
	var mouse := hud.get_local_mouse_position()
	for i in n:
		var rd: Dictionary = RL[relics[i]]
		var col: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var c := o + Vector2(6 + (i % per_row) * cell + cell / 2, 26 + (i / per_row) * cell + cell / 2)
		var cellr := Rect2(c - Vector2(17, 17), Vector2(34, 34))
		tray_cells.append([cellr, relics[i]])
		var hov: bool = cellr.has_point(mouse)
		hud.draw_rect(cellr, Color(1, 1, 1, 0.05) if not hov else Color(col.r, col.g, col.b, 0.22))
		hud.draw_rect(cellr, Color(1, 1, 1, 0.13) if not hov else col, false, 1.0)
		hud.draw_rect(Rect2(cellr.position, Vector2(8, 2)), Color(col.r, col.g, col.b, 0.85))
		var ic: Texture2D = tex.get("relic_" + relics[i])
		if ic != null:
			hud.draw_texture_rect(ic, Rect2(c - Vector2(16, 16), Vector2(32, 32)), false)
		else:
			UI.diamond(hud, c, 11.0, Color(0.03, 0.08, 0.1), col)
			UI.text(hud, font, c + Vector2(-15, 5), rd.name.substr(0, 1), 12, col, HORIZONTAL_ALIGNMENT_CENTER, 30)
		var rl: int = rfx.lv.get(relics[i], 1)
		if rl > 1:
			for q in rl:
				hud.draw_rect(Rect2(c + Vector2(-16 + q * 6, 12), Vector2(4, 3)), Color(col.r * 1.5, col.g * 1.5, col.b * 1.5))
	var cy := r.end.y + 16


## 藏品栏悬停提示（游戏中 / 暂停）
func _draw_relic_tooltip(vs: Vector2) -> void:
	if state != S.PLAY and state != S.PAUSE:
		return
	var mouse := hud.get_local_mouse_position()
	for cellinfo in tray_cells:
		var cr: Rect2 = cellinfo[0]
		if not cr.has_point(mouse):
			continue
		var id: String = cellinfo[1]
		var rd: Dictionary = RL[id]
		var mx: int = rfx.max_lv(id)
		_draw_tooltip(vs, cr, rd.name + ((" Lv.%d/%d" % [rfx.lv.get(id, 1), mx]) if mx > 1 else ""), "%s · %s" % [rd.cat, rd.rarity], rd.desc, "relic_" + id, UI.CAT_COL.get(rd.cat, UI.GOLD))
		return


## 通用提示卡：贴在格子下方（越界时贴上方 / 左移），图标 + 标题 + 副标题 + 折行说明
func _draw_tooltip(vs: Vector2, cr: Rect2, title: String, sub: String, desc: String, icon: String, col: Color) -> void:
	var lines: Array = []
	for para in desc.split("\n"):
		var d: String = para
		while d.length() > 26:
			lines.append(d.substr(0, 26))
			d = d.substr(26)
		lines.append(d)
	var w := 330.0
	var h := 66.0 + lines.size() * 20.0
	var pos := Vector2(clampf(cr.position.x, 12.0, vs.x - w - 12.0), cr.end.y + 8)
	if pos.y + h > vs.y - 12.0:
		pos.y = cr.position.y - h - 8
	var r := Rect2(pos, Vector2(w, h))
	hud.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4)), Color(0.01, 0.04, 0.08, 0.95))
	UI.frame(hud, r, col, {"cut": 6.0, "bracket": 6.0})
	var ic: Texture2D = tex.get(icon)
	if ic != null:
		hud.draw_texture_rect(ic, Rect2(pos + Vector2(12, 12), Vector2(40, 40)), false)
	UI.text(hud, font, pos + Vector2(62, 28), title, 16, Color.WHITE)
	UI.text(hud, font, pos + Vector2(62, 48), sub, 12, col)
	for k in lines.size():
		UI.text(hud, font, pos + Vector2(14, 74 + k * 20), lines[k], 13, Color(0.85, 0.92, 0.95))


## 人物状态栏：左上面板下方，列出当前生效的增益 / 减益（带剩余时间条）
## 冲刺提示（用户要求：不提示就不知道有冲刺）：
## ① 屏幕底部中间常驻一枚按键牌「空格 冲刺」，冷却时底色按进度走满，可冲时描边亮起；
## ② 开局前 25 秒（直到第一次冲刺为止）主控头顶浮一行「按 空格 冲刺」。触屏有自己的冲刺按钮，不画这两样
var dash_used := false


func _draw_dash_hint(vs: Vector2) -> void:
	if state != S.PLAY or touch.active or demo_op != "":
		return
	var key: String = Pad.hint("空格", "Ⓑ")
	var ready: bool = dash_cd <= 0.0
	# 暗底 + 按键牌 + 「冲刺」，底边一道青色冷却条（满 = 可冲）
	var cap_s: String = Pad.hint("SPACE", "Ⓑ")
	var kw := UI.cwidth(font, cap_s, 11) + 12.0
	var w := 8.0 + kw + 8.0 + 28.0 + 12.0
	var r := Rect2(Vector2(vs.x / 2.0 - w / 2.0, vs.y - 44), Vector2(w, 28))
	hud.draw_rect(r, Color(0.03, 0.035, 0.045, 0.74))
	var k: float = 1.0 - dash_cd / DASH_CD
	UI.keycap(hud, font, r.position + Vector2(8, 5), cap_s, UI.CYAN if ready else UI.SUB, 11)
	UI.text(hud, font, r.position + Vector2(16 + kw, 19), "冲刺", 13, UI.TEXT if ready else UI.SUB)
	hud.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x * k, 2)), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.95 if ready else 0.5))
	if not dash_used and t < 25.0:
		var a: float = 0.6 + 0.4 * sin(t * 4.0)
		var sp: Vector2 = get_viewport().get_canvas_transform() * (ppos + Vector2(0, -92))
		UI.text(hud, font, sp - Vector2(100, 0), "按 %s 冲刺（无敌）" % key, 15, Color(0.85, 1.0, 1.0, a), HORIZONTAL_ALIGNMENT_CENTER, 200, 4)


## 商人 / 事件界面把左半屏占满：这时不画声呐和状态小牌，免得从面板边上露出来
func _overlay_left() -> bool:
	return state == S.SHOP or (state == S.CHOICE and choice_kind == "event")


func _draw_status_bar(vs: Vector2) -> void:
	if state == S.OPENING or state == S.INTRO or state == S.SHOW:
		return
	var items: Array = []   # [文字, 颜色, 进度 0..1 或 -1]
	for it in ch.status_items():
		items.append(it if it.size() >= 3 else [it[0], it[1], -1.0])
	if shield > 0:
		items.append(["护盾 ×%d" % shield, Color(0.6, 0.9, 1.0), -1.0])
	for x in rfx.temps:
		if x.stat == "dmg":
			items.append(["增伤 +%d%%" % int(x.value * 100.0), Color(1.0, 0.75, 0.4), clampf((x.until - t) / 6.0, 0.0, 1.0)])
	if rfx.rule("black_tulip") > 0 and rfx.tulip_t > 1.0:
		items.append(["郁金香 +%d%%" % int(60.0 * rfx.tulip_t / 60.0), Color(1.0, 0.6, 0.7), rfx.tulip_t / 60.0])
	if rfx.perm_dmg > 0.0:
		items.append(["刻勋 +%.1f%%" % (rfx.perm_dmg * 100.0), Color(1.0, 0.85, 0.5), -1.0])
	if hp < max_hp * 0.3 and (rfx.rule("king_crown") + rfx.rule("king_gun") + rfx.rule("king_cake") + rfx.rule("king_branch")) > 0:
		items.append(["国王之势", Color(1.0, 0.8, 0.3), -1.0])
	if corrode_pool > 0.5:
		items.append(["侵蚀 %d" % int(corrode_pool), Color(0.8, 0.5, 1.0), -1.0])
	if nerve > 5.0:
		items.append(["神经损伤", Color(1.0, 0.5, 0.9), nerve / 100.0])
	if atk_slow > 0.0:
		items.append(["攻速减缓", Color(0.6, 0.7, 0.9), clampf(atk_slow / 3.0, 0.0, 1.0)])
	if pstun > 0.0:
		items.append(["定身", UI.RED, -1.0])
	if in_mire > 0.5:
		items.append(["溟痕 · 减速", Color(0.85, 0.45, 1.0), -1.0])
	if zone_state != 0 and ppos.distance_to(zone_c) > zone_r:
		items.append(["黑潮", Color(0.9, 0.4, 1.0), -1.0])
	if lamp < 30.0:
		items.append(["灯火低微", Color(1.0, 0.55, 0.45), -1.0])
	if items.is_empty():
		return
	var x := 18.0
	var y := 104.0
	for it in items:
		var w: float = UI.chip(hud, font, Vector2(x, y), it[0], it[1], 12)
		if it[2] >= 0.0:
			hud.draw_rect(Rect2(x, y + 20, w * it[2], 2), it[1])
		x += w + 6.0
		if x > 360.0:
			x = 18.0
			y += 26.0


## 右下编队栏（2026-09-26 方案 A）：明日方舟部署卡——每名干员一张立绘卡（左上职业、右上精英阶段、底部名字），
## 卡上方三枚方形技能格（底部充能条 / 生效时白框 + 倒计时；未解锁灰显；永久型小菱形；海嗣化紫点；手动技能标 Q）。
## 队长卡顶上紫色「队长」标签（紫 = 当前）；技能生效中的干员卡加青色外晕。卡组上方右侧是源石锭费用框 + 编队人数。
## 干员没有等级，卡上不画经验类进度（只有博士等级）。开局干员在最左，第 4 位在最右。
const SQ_COL_W := 94.0
const SQ_CARD := Vector2(84, 96)
const SQ_SK := 24.0

func _draw_squad_hud(br: Vector2) -> void:
	var n: int = squad.size()
	var x_left: float = br.x - n * SQ_COL_W + (SQ_COL_W - SQ_CARD.x)
	if knight.alive:
		knight.draw_hud(hud, Vector2(x_left - 130, br.y - 30))
	var card_y: float = br.y - SQ_CARD.y
	var sk_y: float = card_y - SQ_SK - 14.0
	# 源石锭费用框（明日方舟部署费用的位置与样子）+ 编队人数
	var dp := Rect2(Vector2(br.x - 116, sk_y - 46), Vector2(116, 34))
	hud.draw_rect(dp, Color(0.03, 0.035, 0.045, 0.82))
	hud.draw_rect(Rect2(dp.position, Vector2(3, dp.size.y)), UI.GREEN)
	hud.draw_texture_rect(tex.ingot, Rect2(dp.position + Vector2(12, 10), Vector2(18, 14)), false)
	UI.ctext(hud, font, dp.position + Vector2(38, 27), str(ingots), 26, UI.TEXT)
	UI.text(hud, font, dp.position + Vector2(76, 22), "源石锭", 10, UI.SUB)
	UI.text(hud, font, Vector2(dp.position.x - 160, dp.position.y + 22), "编队 %d / %d" % [n, squad.cap()], 12, Color(0.81, 0.84, 0.86), HORIZONTAL_ALIGNMENT_RIGHT, 150)
	var mp := hud.get_local_mouse_position()
	for i in n:
		var o = squad.ops[i]
		var x: float = br.x - (n - i) * SQ_COL_W + (SQ_COL_W - SQ_CARD.x)
		var cr := Rect2(Vector2(x, card_y), SQ_CARD)
		var ocol: Color = o.col()
		var act: bool = o.skill_active()
		# ---- 立绘卡：上亮下暗的底 + 待机帧上半身（48 帧放大 2 倍、96 高清帧原样，都画成 96 像素）
		var ctop := Color(0.17, 0.2, 0.23, 0.95)
		var cbot := Color(0.07, 0.08, 0.1, 0.95)
		hud.draw_polygon(PackedVector2Array([cr.position, Vector2(cr.end.x, cr.position.y), cr.end, Vector2(cr.position.x, cr.end.y)]), PackedColorArray([ctop, ctop, cbot, cbot]))
		var pt: Dictionary = o.portrait()
		var at: Texture2D = tex.get(pt.tex)
		if at != null:
			var fw := float(at.get_width()) / int(pt.frames)
			var fh := float(at.get_height())
			var ks: float = 2.0 / A.hires_of(at)
			var dst_h := minf(fh * ks - 8.0, cr.size.y - 8.0)
			var src := Rect2(maxf(0.0, (fw * ks - cr.size.x) / 2.0) / ks, 8.0 / ks, minf(cr.size.x / ks, fw), dst_h / ks)
			hud.draw_texture_rect_region(at, Rect2(cr.position, Vector2(minf(cr.size.x, fw * ks), dst_h)), src)
		var clear := Color(0, 0, 0, 0)
		var shade := Color(0, 0, 0, 0.88)
		hud.draw_polygon(PackedVector2Array([Vector2(cr.position.x, cr.end.y - 28), Vector2(cr.end.x, cr.end.y - 28), cr.end, Vector2(cr.position.x, cr.end.y)]), PackedColorArray([clear, clear, shade, shade]))
		UI.text(hud, font, Vector2(cr.position.x, cr.end.y - 8), o.display_name().substr(0, 5), 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x, 2)
		var cls: String = String(o.cls).substr(0, 1)
		if cls != "":
			hud.draw_rect(Rect2(cr.position, Vector2(18, 18)), Color(0, 0, 0, 0.72))
			UI.text(hud, font, cr.position + Vector2(0, 14), cls, 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 18)
		var el: String = ["精零", "精一", "精二"][o.elite]
		var ew := font.get_string_size(el, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 8.0
		hud.draw_rect(Rect2(Vector2(cr.end.x - ew, cr.position.y), Vector2(ew, 16)), Color(0, 0, 0, 0.66))
		UI.text(hud, font, Vector2(cr.end.x - ew + 4, cr.position.y + 12), el, 10, ocol.lerp(UI.TEXT, 0.4))
		if act:
			for k in 3:
				hud.draw_rect(cr.grow(2.0 + k * 2.5), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.16 - k * 0.045), false, 2.0)
			hud.draw_rect(cr, UI.CYAN, false, 1.0)
		else:
			hud.draw_rect(cr, Color(1, 1, 1, 0.16), false, 1.0)
		hud.draw_rect(Rect2(cr.position + Vector2(0, cr.size.y - 2), Vector2(cr.size.x, 2)), Color(ocol.r, ocol.g, ocol.b, 0.9))
		if o == ch:
			var lt := Rect2(Vector2(cr.position.x + 18, card_y - 11), Vector2(cr.size.x - 36, 14))
			hud.draw_rect(lt, UI.VIOLET)
			UI.text(hud, font, lt.position + Vector2(0, 11), "队长", 10, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lt.size.x)
		# ---- 三枚技能格
		var items: Array = o.skill_hud()
		for k in 3:
			var it: Array = items[k]
			var sr := Rect2(Vector2(x + k * (SQ_SK + 6.0), sk_y), Vector2(SQ_SK, SQ_SK))
			var col: Color = it[6]
			var unlocked: bool = it[2]
			var active: float = it[3]
			var frac: float = clamp(it[5], 0.0, 1.0)
			if active > 0.0:
				frac = active / it[4]
			hud.draw_rect(sr, Color(0.04, 0.047, 0.059, 0.9))
			if unlocked and frac > 0.0:
				hud.draw_rect(Rect2(Vector2(sr.position.x, sr.end.y - sr.size.y * frac), Vector2(sr.size.x, sr.size.y * frac)), Color(col.r, col.g, col.b, 0.22 if active <= 0.0 else 0.35))
			var icon: Texture2D = tex.get(it[9]) if it.size() > 9 and it[9] != "" else null
			var c := sr.get_center()
			if icon != null:
				hud.draw_texture_rect(icon, Rect2(c - Vector2(10, 10), Vector2(20, 20)), false, Color.WHITE if unlocked else Color(0.3, 0.3, 0.35))
			else:
				var gcol: Color = (Color(1, 1, 1) if active > 0.0 else col) if unlocked else Color(0.3, 0.35, 0.4)
				UI.text(hud, font, Vector2(sr.position.x, c.y + 5), it[0], 12, gcol, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 2)
			if unlocked:
				hud.draw_rect(Rect2(Vector2(sr.position.x, sr.end.y - 2), Vector2(sr.size.x * frac, 2)), col if active <= 0.0 else Color.WHITE)
			hud.draw_rect(sr, Color.WHITE if active > 0.0 else Color(1, 1, 1, 0.14 if unlocked else 0.06), false, 1.0)
			if active > 0.0:
				UI.ctext(hud, font, Vector2(sr.end.x - 12, sr.position.y + 10), "%d" % int(ceil(active)), 10, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 12)
			if o.perm[k]:
				UI.diamond(hud, sr.end - Vector2(3, 3), 3.0, col, Color(1, 1, 1, 0.6))
			if o.rej.has(k):
				UI.diamond(hud, Vector2(c.x, sr.position.y - 2), 3.0, Color(0.85, 0.55, 1.0))
			# 手动技能（契约 v2.2）：格子上方标按键；充满可放时青色呼吸框
			if o.is_manual(k) and unlocked:
				var rdy: bool = o.manual_ready(k)
				if rdy:
					var pulse: float = 0.5 + 0.5 * sin(t * 6.0)
					hud.draw_rect(sr.grow(2.0 + 1.5 * pulse), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.45 + 0.4 * pulse), false, 2.0)
				UI.ctext(hud, font, Vector2(sr.position.x - 8, sr.position.y - 4), Pad.hint("Q", "Ⓐ"), 10, UI.TEXT if rdy else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x + 16)
			# 悬停：技能名 + 解锁阶段
			if sr.has_point(mp):
				var sd: Dictionary = o.skill_def(k)
				var tip := "%s  ·  %s" % [sd.get("name", ""), ["招募", "精英化一", "精英化二"][k] + ("" if o.skill_unlocked(k) else "解锁")]
				var tw: float = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
				var tipr := Rect2(Vector2(minf(c.x - tw / 2.0, hud.size.x - tw - 8.0), sk_y - 70), Vector2(tw, 28))
				UI.panel(hud, tipr, UI.BG2, o.col(), 6.0)
				UI.text(hud, font, tipr.position + Vector2(12, 19), tip, 12, UI.TEXT)


func _draw_result(vs: Vector2, title: String, en_title: String, col: Color, opts: Array, ending_panel := false) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.72))
	var pw := 600.0 if opts.size() <= 3 else 700.0   # 暂停菜单五个按钮：加宽，按键牌才放得下
	var r := Rect2(vs.x / 2 - pw / 2.0, vs.y / 2 - 190, pw, 380)
	if ending_panel:
		# 结局结算：面板右侧浮现最终 Boss 剪影 + 结局色光晕 + 一句尾声
		var en: Dictionary = D.ENDINGS.get(ending, {})
		var bd: Dictionary = D.ENEMIES.get(en.get("boss", ""), {})
		var btx: Texture2D = tex.get(bd.get("tex", ""))
		var gc: Vector2 = Vector2(r.end.x + 120, r.get_center().y - 20)
		for k in 4:
			hud.draw_circle(gc, 150.0 - k * 28.0 + 6.0 * sin(t * 1.3 + k), Color(col.r, col.g, col.b, 0.05 + 0.03 * k))
		if btx != null:
			var fw: int = btx.get_width() / 2
			var fh: int = btx.get_height()
			var k2: float = minf(220.0 / fw, 240.0 / fh)
			k2 = floorf(k2) if k2 >= 1.0 else k2
			var sz := Vector2(fw, fh) * k2
			var fr: int = int(t * 2.0) % 2
			var bob: float = 4.0 * sin(t * 1.6)
			hud.draw_texture_rect_region(btx, Rect2((gc - sz / 2.0 + Vector2(0, bob)).round(), sz), Rect2(fw * fr, 0, fw, fh), Color(0.55, 0.6, 0.7, 0.9))
			hud.draw_texture_rect_region(btx, Rect2((gc - sz / 2.0 + Vector2(0, bob)).round(), sz), Rect2(fw * fr, 0, fw, fh), Color(col.r, col.g, col.b, 0.25 + 0.1 * sin(t * 2.0)))
		var idx: int = ["standard", "knight", "resolve", "deep"].find(ending)
		UI.text(hud, font, Vector2(gc.x - 90, gc.y + 150), "结局 %s" % ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"][maxi(idx, 0)], 14, Color(col.r, col.g, col.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 180)
		UI.text(hud, font, Vector2(gc.x - 110, gc.y + 172), "已达成 %d / 4" % Cfg.endings_cleared.size(), 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 220)
	UI.frame(hud, r, col, {"t": t})
	hud.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	UI.caustic(hud, Rect2(r.position + Vector2(24, 10), Vector2(r.size.x - 48, 24)), t, col)
	var ew := font.get_string_size(en_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + en_title.length() * 4.0
	UI.en(hud, font, Vector2(r.get_center().x - ew / 2.0, r.position.y + 50), en_title, 13, col, 4.0)
	UI.heading(hud, font, Vector2(r.get_center().x, r.position.y + 90), title, 36, col, 250.0)
	var mm := int(t) / 60
	var ss := int(t) % 60
	var stats := [["探索时间", "%02d:%02d" % [mm, ss]], ["等级", "Lv.%d  %s" % [level, ["精零", "精英化一", "精英化二"][ch.elite]]],
		["击杀", str(kills)], ["难度", "%d  %s" % [diff, D.DIFFICULTY[diff].name]]]
	if ending_panel:
		var ep: String = D.ENDINGS.get(ending, {}).get("gallery", {}).get("epilogue", "")
		UI.text(hud, font, Vector2(r.position.x + 40, r.position.y + 124), ep, 14, Color(col.r * 0.9 + 0.1, col.g * 0.9 + 0.1, col.b * 0.9 + 0.1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 80)
		if ending_new:
			UI.chip(hud, font, Vector2(r.position.x + 30, r.position.y + 30), "新结局达成", col, 12)
	if diff_new and state == S.WIN:
		UI.chip(hud, font, Vector2(r.get_center().x - 80, r.position.y + (142 if ending_panel else 118)), "解锁难度 %d「%s」" % [diff + 1, D.DIFFICULTY[diff + 1].name], UI.GOLD, 13)
	for i in stats.size():
		var y := r.position.y + (166 if ending_panel else 156) + i * 32
		UI.diamond(hud, Vector2(r.position.x + 48, y - 6), 3.5, Color(col.r, col.g, col.b, 0.8))
		UI.text(hud, font, Vector2(r.position.x + 62, y), stats[i][0], 16, UI.SUB)
		UI.text(hud, font, Vector2(r.position.x + 200, y), stats[i][1], 18, UI.TEXT)
	var bx := r.position.x + 40
	var bw := (r.size.x - 80 - 12 * (opts.size() - 1)) / opts.size()
	result_btns.clear()
	var mouse := hud.get_local_mouse_position()
	for op in opts:
		var br := Rect2(bx, r.end.y - 70, bw, 40)
		var bi: int = result_btns.size()
		result_btns.append([br, op[2]])
		var hov: bool = (bi == res_sel) if (Pad.using or kb_nav) else br.has_point(mouse)
		hud.draw_rect(br, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
		var bink := Color(0.04, 0.07, 0.09) if hov else UI.TEXT
		UI.text(hud, font, br.position + Vector2(14, 26), op[0], 15, bink)
		var kst: String = ("Ⓐ" if hov else "") if Pad.using else op[1]
		if kst != "":
			UI.keycap(hud, font, Vector2(br.end.x - UI.cwidth(font, kst, 10) - 20, br.position.y + 11), kst, bink, 10)
		bx += bw + 12


## Tab 面板攻击栏下半：开局干员的三个技能（招募 / 精一 / 精二解锁）+ 天赋
func _draw_generic_skill_rows(b1: Rect2, y: float) -> float:
	var c: Color = ch.col()
	var rows: Array = []
	for i in 3:
		var sd: Dictionary = ch.skill_def(i)
		var on: bool = ch.skill_unlocked(i)
		var need: float = ch.sp_need(i)
		var extra: String = ""
		if on and ch.perm[i]:
			extra = "（已永久生效）"
		elif on and need > 0.0:
			extra = "（充能 %d · %d%%）" % [int(need), int(100.0 * ch.sp[i] / need)]
		elif not on:
			extra = "（%s解锁）" % ["招募", "精英化一", "精英化二"][i]
		rows.append(["%d" % (i + 1), sd.get("name", "技能 %d" % (i + 1)) + extra, sd.get("desc", ""), on, ch.rej.has(i)])
	var td: Dictionary = ch.talent_def()
	if not td.is_empty():
		rows.append(["赋", td.get("name", "天赋") + ("" if ch.elite >= 1 else "（精英化一解锁）"), td.get("desc", ""), ch.elite >= 1, false])
	for row in rows:
		var on: bool = row[3]
		var col: Color = (Color(0.85, 0.55, 1.0) if row[4] else c) if on else Color(0.35, 0.42, 0.46)
		var sc := Vector2(b1.position.x + 34, y + 18)
		UI.ring(hud, sc, 17.0, 1.0 if on else 0.0, col, false, not on)
		UI.text(hud, font, sc + Vector2(-12, 7), row[0], 15, col, HORIZONTAL_ALIGNMENT_CENTER, 24)
		UI.text(hud, font, Vector2(b1.position.x + 62, y + 14), row[1] + ("  ·排异" if row[4] else ""), 14, UI.TEXT if on else UI.SUB)
		UI.text(hud, font, Vector2(b1.position.x + 62, y + 32), UI.soft(row[2]).substr(0, 34), 11, col if on else Color(0.35, 0.42, 0.46))
		y += 44
	return y
