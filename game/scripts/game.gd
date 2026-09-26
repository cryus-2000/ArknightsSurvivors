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
var ev_bars_h := 0.0           # 事件选项条的总高度（选项条按说明行数加高，提示文字跟在后面）
var panel_tip: Control         # 面板最上层：截断说明的完整提示
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
	hud.draw.connect(_draw_hud)
	_build_panel(ul)
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
	if not panel.visible:
		banner_t -= delta   # 选卡 / 商人面板开着时横幅暂停，关掉后再显示（不然会透过压暗带叠在面板标题下）
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
	weapons_sys.update(dt)   # 支援无人机：跟随博士，与编队里有谁无关
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
		show_screen.open(show_queue.pop_front())
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
# 水月的攻击：伞击 + 天赋「创伤性癔症」+ 三个自动技能
# =====================================================================
func facing_angle() -> float:
	return 0.0 if facing >= 0.0 else PI


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
		var fs0 := UI.fit(font, it.desc, cw - 20.0, 64.0, [12, 11])
		var sc_compact: bool = not fs0.fit
		if sc_compact:
			fs0 = UI.fit(font, it.desc, cw - 20.0, 80.0, [12, 11])
		card.set_meta("fit", fs0)
		card.set_meta("compact", sc_compact)
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
	var sc_compact: bool = card.get_meta("compact", false)
	var c := r.position + Vector2(r.size.x / 2.0, 80.0 if sc_compact else 94.0)
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
	UI.text(card, font, r.position + Vector2(0, 150.0 if sc_compact else 164.0), it.name, fs, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	var fd: Dictionary = card.get_meta("fit", {})
	if not fd.is_empty():
		UI.draw_fit(card, font, r.position + Vector2(10, 158.0 if sc_compact else 172.0), fd, Color(0.655, 0.69, 0.725, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 20.0)
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


# =====================================================================
# 掉落物、特效
# =====================================================================


func _cleanup() -> void:
	enemies = enemies.filter(func(e): return not e.dead)
	gems = gems.filter(func(g): return not g.dead)
	bullets = bullets.filter(func(b): return b.life > 0.0)
	ebullets = ebullets.filter(func(b): return b.life > 0.0)
	fx = fx.filter(func(f): return f.life > 0.0)
	texts = texts.filter(func(f): return f.life > 0.0)


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
	# 最上层：说明被截断（排不下末行带「…」）的卡片，悬停 / 焦点时在这里画完整说明
	panel_tip = Control.new()
	panel_tip.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_tip.z_index = 10
	panel_tip.draw.connect(_draw_panel_tip)
	panel.add_child(panel_tip)
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
	UI.text(panel_fg, font, Vector2(cx + 20, 196 + ev_bars_h + 6), hint, 12, Color(0.55, 0.54, 0.52))


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
	ev_bars_h = 0.0
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
		# 说明文字：创建时按宽度排好版（放不下先缩字号）。选卡卡片三行还放不下就切紧凑布局——
		# 图标缩小、名字上移，把位置让给说明；事件选项条则按行数加高
		if ev:
			var fe := UI.fit(font, o.desc, 420.0, 4.0 * font.get_height(13), [13, 12])
			card.set_meta("fit", fe)
			card.custom_minimum_size.y = 100.0 + maxf(0.0, fe.lines.size() - 2) * float(fe.lh)
			ev_bars_h += card.custom_minimum_size.y + 14.0
		else:
			var f0 := UI.fit(font, o.desc, CARD_W - 40.0, 60.0, [13, 12])
			var compact: bool = not f0.fit
			if compact:
				f0 = UI.fit(font, o.desc, CARD_W - 40.0, 108.0, [13, 12, 11])
			card.set_meta("fit", f0)
			card.set_meta("compact", compact)
		(panel_col if ev else panel_box).add_child(card)
	panel.visible = true
	panel_fg.queue_redraw()


## 选卡 / 商店 / 事件：焦点卡片的说明被截断时，在面板最上层画完整说明（卡片下方，放不下放上方）
func _draw_panel_tip() -> void:
	var box: BoxContainer = panel_col if (choice_kind == "event" and state == S.CHOICE) else panel_box
	var vs := panel_tip.size
	for card in box.get_children():
		if not (card is Button) or card.is_queued_for_deletion():
			continue
		var fd: Dictionary = card.get_meta("fit", {})
		if fd.is_empty() or fd.get("fit", true) or not _card_hot(card, card.get_index()):
			continue
		var gr: Rect2 = card.get_global_rect()
		var it: Dictionary = card.get_meta("item", {})
		var title: String = it.get("name", "") if not it.is_empty() else (choices[card.get_index()].get("name", "") if card.get_index() < choices.size() else "")
		var desc: String = it.get("desc", "") if not it.is_empty() else (choices[card.get_index()].get("desc", "") if card.get_index() < choices.size() else "")
		_draw_tooltip(vs, Rect2(gr.position - panel_tip.get_global_rect().position, gr.size), title, "完整说明", desc, "", UI.CYAN, panel_tip)
		return


func _animate_cards(dt: float) -> void:
	if not panel.visible:
		return
	panel_fg.queue_redraw()
	panel_tip.queue_redraw()
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
	var compact: bool = card.get_meta("compact", false)
	var c := r.position + Vector2(r.size.x / 2.0, 104.0 if compact else 128.0)
	UI.halo(card, c, 40.0 if compact else 58.0, UI.CYAN, hov)
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
		var ks: float = ((1.0 if compact else 2.0) if idle.fh <= 48 else (64.0 if compact else 96.0) / idle.fh)
		var asz := Vector2(idle.fw, idle.fh) * ks
		card.draw_texture_rect_region(idle.tex, Rect2(c - asz / 2.0 + Vector2(0, bob + 4), asz), Rect2(0, 0, idle.fw, idle.fh))
	elif ic != null:
		_draw_icon_fit(card, ic, c + Vector2(0, bob), 64.0 if compact else 96.0)
	else:
		UI.text(card, font, c + Vector2(-40, 13 + bob), glyph, 34, _card_color(o), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	var nm := name
	if o.kind == "relic":
		nm = RL[o.id].name
	UI.text(card, font, r.position + Vector2(0, 196.0 if compact else 244.0), nm, 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
	var fd: Dictionary = card.get_meta("fit", {})
	if not fd.is_empty():
		UI.draw_fit(card, font, r.position + Vector2(20, 210.0 if compact else 258.0), fd, Color(0.655, 0.69, 0.725), HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 40.0)
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
		sp.append(base + Vector2(q.x * w / 596.0, q.y * card.size.y / 100.0))
	card.draw_colored_polygon(sp, Color(0.925, 0.91, 0.882, 0.14) if hov else Color(0.07, 0.07, 0.075, 0.9))
	var en_ring: PackedVector2Array = art.ensos[i % art.ensos.size()]
	var er := PackedVector2Array()
	for q in en_ring:
		er.append(base + q + Vector2(0, card.size.y / 2.0 - 50.0))
	card.draw_colored_polygon(er, Color(0.925, 0.91, 0.882, 0.55 if hov else 0.22))
	var ink := Color(0.925, 0.91, 0.882)
	var icn: String = o.get("icon", "")
	var itx: Texture2D = tex.get(icn) if icn != "" and icn != "exit" else null
	if itx != null:
		_draw_icon_fit(card, itx, base + Vector2(56, card.size.y / 2.0), 64.0)
	else:
		UI.icon(card, "exit", base + Vector2(56, card.size.y / 2.0), 32.0, ink)
	card.draw_string(serif, base + Vector2(112, 38), o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE if hov else ink)
	var x := 112.0 + serif.get_string_size(o.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 14.0
	for chp in o.get("chips", []):
		var cw := font.get_string_size(chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
		var cr := Rect2(base + Vector2(x, 20), Vector2(cw, 18))
		card.draw_rect(cr, Color(chp[1].r, chp[1].g, chp[1].b, 0.9), false, 1.0)
		card.draw_string(font, cr.position + Vector2(6, 13), chp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, chp[1])
		x += cw + 6.0
	var fb: Dictionary = card.get_meta("fit", {})
	if not fb.is_empty():
		UI.draw_fit(card, font, base + Vector2(112, 50), fb, Color(0.81, 0.79, 0.76))
	UI.ctext(card, font, base + Vector2(w - 46, card.size.y / 2.0 + 10.0), str(i + 1), 24, Color(0.18, 0.72, 1.0) if hov else Color(0.37, 0.36, 0.35), HORIZONTAL_ALIGNMENT_CENTER, 24)
	if hov:
		card.draw_rect(Rect2(base + Vector2(8, 20), Vector2(8, card.size.y - 40.0)), Color(0.18, 0.72, 1.0, 0.25))
		card.draw_rect(Rect2(base + Vector2(10, 22), Vector2(4, card.size.y - 44.0)), Color(0.18, 0.72, 1.0))


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


const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane", "tide": "proj_tide"}


func _draw() -> void:
	map.draw_ground(get_viewport_rect().size)
	for m in mires:
		map.draw_mire(m)
	bai._draw_warns()
	rfx.draw()
	if not merchant.is_empty():
		var mtx: Texture2D = tex.merchant
		var big_m: bool = mtx != null and mtx.get_height() >= 40
		vfx.spr("shadow", 1, 0, merchant.pos + Vector2(0, 18), PX * (1.6 if big_m else 1.2))
		if big_m:
			vfx.spr("merchant", 2, int(t * 2.0) % 2, merchant.pos + Vector2(0, 18), PX, ppos.x < merchant.pos.x, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
		else:
			vfx.spr("merchant", 2, int(t * 2.0) % 2, merchant.pos, PX)
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
				vfx.spr("gem_big" if big else "gem_small", 1, 0, gp, PX * (1.9 if big else 1.45), false, Color(1.25, 1.25, 1.3) if not big else Color(1.35, 1.2, 1.5))
				var sp2: float = 2.0 + 1.5 * tw
				draw_line(gp + Vector2(-sp2, -8), gp + Vector2(sp2, -8), Color(2.5, 2.5, 2.5, 0.5 * tw), 1.0)
				draw_line(gp + Vector2(0, -8 - sp2), gp + Vector2(0, -8 + sp2), Color(2.5, 2.5, 2.5, 0.5 * tw), 1.0)
			"oil":
				vfx.spr("oil", 1, 0, g.pos)
			"chest":
				vfx.spr("chest", 1, 0, g.pos)
			"ingot":
				vfx.spr("ingot", 1, 0, g.pos + Vector2(0, sin(t * 3.0 + g.pos.y) * 1.5 if gz <= 1.0 else 0.0))
			"magnet", "heal":
				vfx.spr("pickup_" + g.kind, 1, 0, g.pos + Vector2(0, -2 + (sin(t * 3.5) * 2.0 if gz <= 1.0 else 0.0)))
		draw_off = Vector2.ZERO
	vfx.spr("shadow", 1, 0, doc_pos + Vector2(0, 6), PX * 1.3)
	squad.draw_auras()
	for e in enemies:
		var sc: float = PX * e.r / 10.0
		var hop: float = minf(e.kb.length() * 0.03, 14.0)
		vfx.spr("shadow", 1, 0, e.pos + Vector2(0, e.r * 0.8), sc * (1.0 - hop / 40.0))
	squad.draw_shadows()
	if knight.alive:
		vfx.spr("shadow", 1, 0, knight.pos + Vector2(0, 18), PX * 1.6)
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
			vfx.spr("drone_laser", 4, dfr, dr.pos, 1.0, dr.get("face", 1.0) < 0.0, Color(0.85, 1.25, 0.95))
		elif tex.get("drone") != null:
			vfx.spr("drone", 2, int(t * 20.0) % 2, dr.pos, PX, false, Color(1.2, 1.7, 1.4))
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
			vfx.spr_rot(ptex, pfr, b.pos, b.vel.angle(), PX)
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
				vfx.spr("orb", 1, 0, b.pos, PX)
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
						vfx.spr_rot("fx_heal_cross", mini(3, int((age - f.delay) * 10.0)), p, 0.0, PX * f.sz / 4.5, Color(1, 1, 1, a))
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
				vfx.spr("tentacle", 5, fr, f.pos + Vector2(0, 16), PX * 4.2, false, tc, Vector2(0.5, 1.0))
				vfx.spr("tentacle", 5, fr, f.pos + Vector2(-50, 20), PX * 2.6, true, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
				vfx.spr("tentacle", 5, fr, f.pos + Vector2(48, 22), PX * 2.4, false, tc * Color(0.9, 0.9, 0.9, 1.0), Vector2(0.5, 1.0))
			"sprite":
				var spec: Array = V6_FRAMES[f.name]
				var fr := mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
				vfx.spr_rot(f.name, fr, f.pos, f.ang, f.scale, f.get("col", Color.WHITE), f.get("anchor", Vector2(-1, -1)), f.get("flip", false))
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
				vfx.spr(tn, nf, fr, Vector2.ZERO, f.scale, false, sc_col, f.get("anchor", Vector2(0.5, 0.5)))
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
				vfx.spr("ebullet", 1, 0, bp, PX * b.r / 5.0)
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
		vfx.spr(name, 2, frame, e.pos + Vector2(wob, 0), PX, false, col)
		if e.flash > 0.0:
			vfx.spr(name + "_white", 2, 0, e.pos, PX, false, Color(1, 1, 1, 0.9))
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
		vfx.sparks(e.pos, -e.dash_dir, Color(0.8, 0.9, 1.0), 1, 80.0)
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
			vfx.spr(name + "_white", frames, frame, bpos + d, sc, flip, oc, anc, sq)
	vfx.spr(name, frames, frame, bpos, sc, flip, col, anc, sq)
	if e.flash > 0.0:
		vfx.spr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9), anc, sq)
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
		intro_screen.update_opening(dt)
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
		var nn := enemies_sys.nearest(1, 160.0)
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
		intro_screen.draw_opening_hud(vs)
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
	if banner_t > 0.0 and not panel.visible:
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
			show_screen.draw(vs)
		S.INTRO:
			intro_screen.draw(vs)
		S.STATS:
			stats_screen.draw(vs)
		S.PAUSE:
			result_screen.draw(vs, "暂停", "PAUSED", UI.CYAN, [["继续", "Esc", "resume"], ["指南", "G", "guide"], ["设置", "O", "settings"], ["重新开始", "R", "restart"], ["回到标题", "T", "title"]])
		S.DEAD:
			result_screen.draw(vs, "探索终止", "OPERATION FAILED", UI.RED, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])
		S.WIN:
			result_screen.draw(vs, "%s · 探索完成" % D.ENDINGS[ending].name, D.ENDINGS[ending].en, endg.cur_col().lerp(UI.GOLD, 0.35), [["再次探索", "R", "restart"], ["回到标题", "T", "title"]], true)


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
func _draw_tooltip(vs: Vector2, cr: Rect2, title: String, sub: String, desc: String, icon: String, col: Color, on: CanvasItem = null) -> void:
	var ci: CanvasItem = hud if on == null else on
	var w := 340.0
	# 说明按像素宽度折行（旧版按 26 个字硬切，13 号字会超出框）；太长先缩字号，整屏都放不下才截断
	var fd := UI.fit(font, desc, w - 28.0, vs.y - 24.0 - 74.0, [13, 12, 11], 3.0)
	var h := 66.0 + float(fd.h) + 12.0
	var pos := Vector2(clampf(cr.position.x, 12.0, vs.x - w - 12.0), cr.end.y + 8)
	if pos.y + h > vs.y - 12.0:
		pos.y = cr.position.y - h - 8
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vs.y - h - 12.0))
	var r := Rect2(pos, Vector2(w, h))
	ci.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4)), Color(0.03, 0.035, 0.045, 0.96))
	UI.frame(ci, r, col)
	var tx0 := 14.0
	var ic: Texture2D = tex.get(icon) if icon != "" else null
	if ic != null:
		ci.draw_texture_rect(ic, Rect2(pos + Vector2(12, 12), Vector2(40, 40)), false)
		tx0 = 62.0
	UI.text_fit(ci, font, pos + Vector2(tx0, 28), title, 16, Color.WHITE, w - tx0 - 12.0, 12)
	UI.text_fit(ci, font, pos + Vector2(tx0, 48), sub, 12, col, w - tx0 - 12.0, 10)
	UI.draw_fit(ci, font, pos + Vector2(14, 62), fd, Color(0.85, 0.92, 0.95))


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


## Tab 面板攻击栏下半：开局干员的三个技能（招募 / 精一 / 精二解锁）+ 天赋
func _skill_rows_data() -> Array:
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
	return rows


