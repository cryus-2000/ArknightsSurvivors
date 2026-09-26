extends Node2D
## 方舟幸存者 —— 对局场景（状态与调度；玩法 / 界面 / 绘制分在 run/、screens/、render/，见 docs/39）
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
const Telemetry = preload("res://scripts/run/telemetry.gd")
const WorldView = preload("res://scripts/render/world.gd")
const HudView = preload("res://scripts/screens/hud.gd")
const ShopScreen = preload("res://scripts/screens/shop_screen.gd")
const ChoicePanel = preload("res://scripts/screens/choice_panel.gd")
const ResultScreen = preload("res://scripts/screens/result.gd")
const StatsScreen = preload("res://scripts/screens/stats_panel.gd")
const EliteShowScreen = preload("res://scripts/screens/elite_show.gd")
const IntroScreen = preload("res://scripts/screens/intro.gd")
const Vfx = preload("res://scripts/render/vfx.gd")
const Combat = preload("res://scripts/run/combat.gd")
const EnemiesSys = preload("res://scripts/run/enemies.gd")
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
## 美术交付的特效帧数（见 docs/05_art_handoff.md）
const FXF := {"fx_s1_burst": 6, "fx_s1_slash": 4, "fx_s2_aura": 4, "fx_s2_bind": 4, "fx_s3_aura": 6,
	"fx_s3_slash": 4, "fx_cast": 8, "fx_stun": 4, "fx_hit": 4, "fx_death": 5}

enum S { PLAY, CHOICE, PAUSE, DEAD, WIN, SHOP, SHOW, STATS, INTRO, OPENING }

const PX := 2.0                 # 1 个美术像素 = 2 个世界像素
const TILE := 32.0              # 地砖在世界中的尺寸
const MERCHANT_TIMES := [120.0, 300.0, 480.0]   # 每次都在 Boss（3:30 / 7:00 / 10:00）之前

var state: int = S.PLAY
var autotest_sys = AutoTest.new(self)   # 自动测试 / 平衡机器人（docs/29、docs/36）
var demo_sys = DemoRun.new(self)   # 图鉴攻击演示 / 精英化演出（gallery.gd 把 game.tscn 以 demo_op 模式放进 SubViewport）
var spawner = Spawner.new(self)   # 刷怪
var shop_sys = ShopSys.new(self)   # 商人与商店（逻辑）
var weapons_sys = WeaponsSys.new(self)   # 子弹与支援装置
var pickups = Pickups.new(self)   # 掉落与拾取
var progression = Progression.new(self)   # 升级与藏品发放（逻辑）
var music_dir = MusicDirector.new(self)   # 局内配乐调度
var enemies_sys = EnemiesSys.new(self)   # 敌人的逐帧更新
var combat = Combat.new(self)   # 战斗结算
var vfx = Vfx.new(self)   # 特效与提示
var intro_screen = IntroScreen.new(self)   # 界面 · 开场与教程
var show_screen = EliteShowScreen.new(self)   # 界面 · 精英化 / 解锁演出（state SHOW）
var stats_screen = StatsScreen.new(self)   # 界面 · 属性面板（Tab，state STATS）
var result_screen = ResultScreen.new(self)   # 界面 · 结算（state DEAD / WIN）
var panel_ui = ChoicePanel.new(self)   # 界面 · 弹窗面板与选卡（state CHOICE）
var shop_ui = ShopScreen.new(self)   # 界面 · 商店（state SHOP）
var hud_view = HudView.new(self)   # 界面 · 局内 HUD（hud 画布节点的 draw 信号）
var world = WorldView.new(self)   # 世界绘制（2.5D）
var telemetry = Telemetry.new(self)   # 局内数据记录（docs/40）
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
var horde_log: Array = []          # 平衡测试：每次大群的统计
var backlight := false

var relics: Array = []

# ---------- 援护干员 ----------
var weapons := {}               # 支援 id -> 等级。医疗无人机改为可选（2026-09-26 用户决定）：开局不带，升级卡池里的常规选项（docs/23 §17）
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
var in_mire := 0.0               # 站在溟痕里的程度（0..1，平滑过渡，用于减速与屏幕变暗）
var next_mire := 100.0           # 首次溟痕时间；开局由 map 主题覆盖
# 缩圈（黑潮）
var zone_c := Vector2.ZERO
var zone_r := 99999.0
var zone_next_c := Vector2.ZERO
var zone_next_r := 0.0
var zone_state := 0          # 0 未开始 / 1 预告 / 2 收缩 / 3 稳定
var zone_t := 0.0
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
var squad: RefCounted          # 编队（scripts/characters/squad.gd）：主控与跟随的干员们
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
var panel_fg: Control          # 标题、商人立绘、事件插画画在这层（压暗带之上、卡片之下）
var panel_tip: Control         # 面板最上层：截断说明的完整提示
var font: Font
var tex := {}
var panel_title_text := ""
# ---------- 打击感 ----------
var hitstop := 0.0
var shake := 0.0
var hurt_vignette := 0.0
var tab_hint := 0.0          # 首次升级后再提醒一次 Tab
var tab_used := false
var hp_trail := 100.0        # 血条上的「被扣掉」残影
var hp_shake := 0.0
var head_bar_t := 0.0        # 头顶血条显示时长
var red_flash := 0.0
var crit_hit := false
var fx_add: Node2D
var settings: Control
var result_btns: Array = []   # [Rect2, action]
var pause_btn := Rect2()      # 右上角暂停按钮（仅游戏中可点）
# ---- 手柄 / 键盘焦点（docs/28）：选卡 / 商店的卡片焦点、暂停与结算按钮焦点
var nav_sel := 0               # 当前焦点卡片（选卡 / 商店共用 panel_box 的下标）
var res_sel := 0               # 暂停 / 结算按钮焦点
var kb_nav := false            # 键盘方向键导航过（显示焦点而不是鼠标悬停），鼠标一动就关
var state_age := 0.0           # 进入当前状态的秒数（防止手柄连按把刚弹出的选卡 / 演出直接点掉）
var _last_state := -1

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
	# 干员技能图标（skills[i].icon，可选）：所有干员都加载——中途招募的干员 HUD 技能格、技能强化卡也要用
	for cid in Character.list_ids():
		for sd in Character.load_def(cid).get("skills", []):
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
	fx_add.draw.connect(vfx.draw_add_layer)
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
	hud.draw.connect(hud_view.draw)
	panel_ui.build(ul)
	settings = preload("res://scripts/settings_panel.gd").new()
	ul.add_child(settings)
	if demo_op == "":
		Sfx.cut_target = 20000.0
		Sfx.vol_target = -4.0
		vfx.show_banner("深海的潮水正在涌来……")
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
		intro_screen.open.call_deferred(S.PLAY)
	elif not autotest or OS.get_cmdline_user_args().has("--openshot"):
		intro_screen.start_opening.call_deferred()
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
					panel_ui.load_op_tex(cid)
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


## 镜头看着的位置：平时跟主控；图鉴演示里固定在场地中心（map.gd 按它决定画哪些地块）
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
		telemetry.on_state(state)   # 进入胜 / 负时把这一局写进本地记录（docs/40）
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
	# 图鉴演示 / 精英化演出不顿帧：演示里攻击不停，每下重击都冻 0.05–0.1 秒，走路看起来一卡一卡（2026-09-26 用户反馈）
	if hitstop > 0.0 and not autotest and Cfg.hitstop and demo_op == "":
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
	if not panel.visible and state != S.SHOW:
		banner_t -= delta   # 选卡 / 商人面板 / 精英化演出时横幅暂停，关掉后再显示（不然会透过压暗带叠在面板标题下）
	_pm("")
	world.update_visuals(dt if state == S.PLAY else 0.0)
	_pm("visuals")
	music_dir.update(delta)
	panel_ui.animate_cards(delta)
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
			intro_screen.open(S.PAUSE)
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
				intro_screen.close()
			KEY_LEFT, KEY_A, KEY_PAGEUP, KEY_BACKSPACE:
				intro_screen.prev_page()
			_:
				intro_screen.next_page()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = hud.get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_WHEEL_UP:
			intro_screen.prev_page()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			intro_screen.next_page()
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
					intro_screen.prev_page()
				elif intro_btn_skip.has_point(mp):
					intro_screen.close()
				elif intro_btn_next.has_point(mp):
					intro_screen.next_page()
				elif intro_panel.has_point(mp) and mp.x < intro_panel.position.x + intro_panel.size.x * 0.3:
					intro_screen.prev_page()
				else:
					intro_screen.next_page()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if settings.visible:
		return
	if state == S.OPENING:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			intro_screen.end_opening()
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
			show_screen.close()
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
		intro_screen.open(S.PAUSE)
	elif k == KEY_M:
		vfx.show_banner("音乐：关" if Sfx.toggle_music() else "音乐：开")
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


## 主控冲刺（2026-09-26 用户要求）：空格 / Shift / K / 手柄 B·RB / 触屏「冲刺」按钮。沿移动方向（站着不动时沿朝向）
## 0.18 秒冲出约 126 像素，全程无敌；冷却 1.2 秒。残影由干员的动态模糊（character.gd ghosts）自动产生
const DASH_TIME := 0.18
const DASH_SPEED := 700.0
const DASH_CD := 1.2
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var last_mv := Vector2.ZERO
var move_in := Vector2.ZERO   # 这一帧的移动输入（僵直时也记）：冲刺方向用


## 冲刺任何时候都能按（docs/38 §1.11「永不硬控」）：只看冷却、是否正在冲刺、是否在局内；僵直时也能冲，方向取按住的方向
func _try_dash() -> void:
	if dash_cd > 0.0 or dash_t > 0.0 or state != S.PLAY:
		return
	dash_dir = (move_in if move_in != Vector2.ZERO else Vector2(facing, 0)).normalized()
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	dash_used = true
	invuln = maxf(invuln, DASH_TIME + 0.05)
	fx.append({"kind": "ring", "pos": ppos, "r": 36.0, "life": 0.25, "max": 0.25, "col": ch.col() if ch != null else UI.CYAN})
	Sfx.play("dodge", -6.0, 1.2, 0.05)


func _update(dt: float) -> void:
	_pm("")
	t += dt
	if not autotest:
		telemetry.tick(dt)   # 真实玩家局的整局指标；机器人局由 autotest 按原节奏驱动
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
	move_in = mv
	if pstun > 0.0:
		mv = Vector2.ZERO
	moving = mv != Vector2.ZERO
	if moving:
		mv = mv.normalized() * minf(mv.length(), 1.0)   # 键盘斜向归一；手柄半推 = 慢走
		walk_t += dt * 12.0
		if mv.x != 0.0 and swing_face <= 0.0:
			facing = sign(mv.x)
	# 溟痕：陷在里面移动速度 -45%；Boss 战里僵直 / 攻速减缓换成的减速也乘在这里，Boss 存活期间合计不低于 0.7（combat.move_mult）
	var mspd: float = speed * combat.move_mult((1.0 - 0.45 * in_mire) * rej_slow * (0.6 if frost > 0.0 else 1.0))
	pvel = mv * mspd
	ppos += mv * mspd * dt
	# 冲刺：主控沿冲刺方向高速位移，期间无敌；僵直时也能冲，冲刺距离不受减速影响
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
		combat.lose_hp(3.0 * dt, "dark")
		hurt_flash = max(hurt_flash, 0.05)
	combat.update_zone(dt)
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
	enemies_sys.build_grid()
	_pm("grid")
	enemies_sys.update(dt)
	_pm("enemies")
	squad.update(dt)
	_pm("squad")
	weapons_sys.update(dt)   # 支援无人机：跟随主控，与编队里有谁无关
	knight.update(dt)
	touch.update(dt)
	weapons_sys.update_bullets(dt)
	_pm("bullets")
	enemies_sys.update_ebullets(dt)
	bai._update_warns(dt)
	_pm("ebullets")
	enemies_sys.update_status(dt)
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
	vfx.update(dt)
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
		hp = 1.0   # 幽灵鲨「求生之渴」：主控生命不会低于 1
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
		show_screen.open(show_queue.pop_front())
		return
	if pending_chests > 0:
		progression.open_relic_choice()
	elif pending_levelups > 0 and lvup_delay <= 0.0:
		progression.open_levelup()


# =====================================================================
# 属性同步与对局工具：_sync_stats（stats → 缓存变量）、灯火半径 / 技力倍率、对局随机数洗牌、性能打点
# 刷怪 / 敌人 / 战斗 / 商店 / 无人机 / 掉落 / 升级选卡已拆到 scripts/run/，界面在 screens/，绘制在 render/（docs/39 §1）
# =====================================================================


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


# =====================================================================
# 主控朝向与实体清理
# =====================================================================
func facing_angle() -> float:
	return 0.0 if facing >= 0.0 else PI


func _cleanup() -> void:
	enemies = enemies.filter(func(e): return not e.dead)
	gems = gems.filter(func(g): return not g.dead)
	bullets = bullets.filter(func(b): return b.life > 0.0)
	ebullets = ebullets.filter(func(b): return b.life > 0.0)
	fx = fx.filter(func(f): return f.life > 0.0)
	texts = texts.filter(func(f): return f.life > 0.0)


# =====================================================================
# 博士挂件跟随、引擎回调（_exit_tree / _draw 转发）与数据表（V6_FRAMES 帧条登记、开局指南文本）
# =====================================================================
## 博士挂件（docs/23 v0.7）：不受击、不攻击，慢慢跑着跟在主控身后；离太远（传送 / 开局）才直接归位
const DOC_SPEED := 175.0        # 略快于主控基础移速 150，追得上但不会贴身
const DOC_BEHIND := Vector2(-40, 30)
var doc_pos := Vector2.INF
var doc_moving := false
var doc_still_t := 0.0           # 博士连续「几乎没动」的时间：超过 DOC_STOP_T 才切站立（走停滞后，免得跑 / 站帧条一闪一闪）
const DOC_STOP_T := 0.15
var doc_face := 1.0


## 离开对局（回标题 / 关游戏）：还没记过的这一局按「中途退出」写进本地记录
func _exit_tree() -> void:
	telemetry.on_exit()


## 世界绘制（引擎回调）：转发到 render/world.gd
func _draw() -> void:
	world.draw_world()


func _update_doc_follow(dt: float) -> void:
	var want: Vector2 = ppos + Vector2(DOC_BEHIND.x * facing, DOC_BEHIND.y)
	if doc_pos == Vector2.INF or doc_pos.distance_to(want) > 600.0:
		doc_pos = want
	var d: Vector2 = want - doc_pos
	var step: float = minf(d.length(), DOC_SPEED * dt * clampf(d.length() / 60.0, 0.35, 1.0))
	var mv: Vector2 = d.normalized() * step if d.length() > 1.0 else Vector2.ZERO
	doc_pos += mv
	# 走停滞后：起步要够快（> 30 像素 / 秒）；停下要连续慢（< 20）DOC_STOP_T 秒
	var spd: float = mv.length() / maxf(dt, 0.0001)
	if doc_moving:
		doc_still_t = doc_still_t + dt if spd < 20.0 else 0.0
		doc_moving = doc_still_t < DOC_STOP_T
	else:
		doc_moving = spd > 30.0
		doc_still_t = 0.0
	if absf(mv.x) > 6.0 * dt:
		doc_face = signf(mv.x)
	elif not doc_moving:
		doc_face = facing


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
	"fx_claw_green": [4, 16.0], "fx_claw_double_green": [5, 16.0], "fx_felspell": [17, 16.0], "fx_logos_s2": [17, 16.0],
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


## ---- 开局指南：6 页图文介绍（首次进入自动显示，暂停菜单按 G 可再看）
const INTRO_PAGES := [
	{"title": "欢迎来到深海", "en": "WELCOME", "icon": "mizuki", "lines": [
		"海风吹向深处。罗德岛的小分队随水月潜入海嗣的深海，灯火是唯一的光。",
		"你是博士。带着你的小队撑过 10 分钟，直面 10:00 醒来的最终 Boss。你的抉择，会决定故事走向哪一个结局。3:30 与 7:00 各有强敌拦路。",
		"主控走在最前面，也是唯一会受伤的人。技能都会自动释放，你只管走位（WASD）与冲刺（空格，冲刺中无敌）。灯光里的敌人更脆弱。"]},
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
		"击败敌人掉落经验，升级时三选一：干员深度卡（数值 / 精英化）、博士被动、全队被动，Lv.5 起会出现招募卡；医疗无人机也是常规选项：选到即加入，之后可继续升级（最高 Lv.5）。第一次拿到新技能或进阶时会有演示。",
		"每名干员招募即有一技能，精英化一解锁二技能与天赋，精英化二解锁三技能。三个技能全部自动释放，先练谁、练到几精是这一局的核心取舍。",
		"编队最多 3 名常规干员（开局 1 名 + 局内招募 2 名）。没有医疗干员时，可以在升级时选医疗无人机补回复。按 Tab 随时查看主控属性、编队与藏品效果。"]},
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


## 冲刺提示（用户要求：不提示就不知道有冲刺）：
## ① 屏幕底部中间常驻一枚按键牌「空格 冲刺」，冷却时底色按进度走满，可冲时描边亮起；
## ② 开局前 25 秒（直到第一次冲刺为止）主控头顶浮一行「按 空格 冲刺」。触屏有自己的冲刺按钮，不画这两样
var dash_used := false


