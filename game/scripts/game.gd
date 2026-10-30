extends Node2D
## 方舟幸存者 —— 对局场景（状态与调度；玩法 / 界面 / 绘制分在 run/、screens/、render/，见 docs/39）
## 敌人/掉落物/特效用数据数组管理，统一在 _draw 中以像素贴图绘制（美术像素 ×2）。
## 灯火是一个真实光源：场景整体偏暗，只有玩家周围被照亮。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")   # 界面动效时钟与缓动（docs/62 §2.7）
const A = preload("res://scripts/art.gd")
const BossAI = preload("res://scripts/boss_ai.gd")
const Telegraph = preload("res://scripts/enemies/telegraph.gd")
const ShotPool = preload("res://scripts/enemies/shot_pool.gd")
const RelicFx = preload("res://scripts/relic_fx.gd")
const Endings = preload("res://scripts/endings.gd")
const Knight = preload("res://scripts/allies/knight.gd")
const Touch = preload("res://scripts/touch.gd")
const Map = preload("res://scripts/world/map.gd")
const PostFx = preload("res://scripts/post_fx.gd")
const Look = preload("res://scripts/render/look.gd")   # 观感预设 render/look（角色受光封顶 / 后期曲线，scripts/render/look.gd）
const EnemyAI = preload("res://scripts/enemies/enemy_ai.gd")
const Character = preload("res://scripts/characters/character.gd")
const Squad = preload("res://scripts/characters/squad.gd")
const PlayKeys = preload("res://scripts/core/play_keys.gd")   # 局内按键表（动作 → 键盘 / 手柄 / 触屏，arch_review_1029 P0-2）
const Ult = preload("res://scripts/run/ult.gd")   # 终结技 / 连携技 / 连携终结技（docs/198；ult/on = 0 时为 null）
const Doctor = preload("res://scripts/characters/doctor.gd")
const StatBlock = preload("res://scripts/core/stat_block.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）
const RunSetup = preload("res://scripts/run/run_setup.gd")   # 开局：难度、批跑 / 测试参数（docs/126 C1）
const RunEnd = preload("res://scripts/run/run_end.gd")   # 局终：局外结算
const Bot = preload("res://scripts/core/bot.gd")       # --balance 四档机器人 + 指标采集（docs/29）
const Telemetry = preload("res://scripts/run/telemetry.gd")
const PerfReport = preload("res://scripts/core/perf_report.gd")
const WorldView = preload("res://scripts/render/world.gd")
const HudView = preload("res://scripts/screens/hud.gd")
const ShopScreen = preload("res://scripts/screens/shop_screen.gd")
const ChoicePanel = preload("res://scripts/screens/choice_panel.gd")
const ResultScreen = preload("res://scripts/screens/result.gd")
const RunStatsScreen = preload("res://scripts/screens/run_stats_screen.gd")
const HeadhuntScreen = preload("res://scripts/screens/headhunt.gd")
const Roster = preload("res://scripts/core/roster.gd")
const Meta = preload("res://scripts/core/meta.gd")
const StatsScreen = preload("res://scripts/screens/stats_panel.gd")
const EliteShowScreen = preload("res://scripts/screens/elite_show.gd")
const IntroScreen = preload("res://scripts/screens/intro.gd")
const BossIntro = preload("res://scripts/screens/boss_intro.gd")
const Vfx = preload("res://scripts/render/vfx.gd")
const Combat = preload("res://scripts/run/combat.gd")
const Afflict = preload("res://scripts/run/afflict.gd")
const EnemiesSys = preload("res://scripts/run/enemies.gd")
const MusicDirector = preload("res://scripts/run/music_director.gd")
const Progression = preload("res://scripts/run/progression.gd")
const BuildGuide = preload("res://scripts/run/build_guide.gd")
const Pickups = preload("res://scripts/run/pickups.gd")
const WeaponsSys = preload("res://scripts/run/weapons.gd")
const ShopSys = preload("res://scripts/run/shop.gd")
const Beacon = preload("res://scripts/run/beacon.gd")
const Spawner = preload("res://scripts/run/spawner.gd")
const PlayClock = preload("res://scripts/run/play_clock.gd")
const IsharEncounter = preload("res://scripts/run/ishar_encounter.gd")
const BossTrial = preload("res://scripts/run/boss_trial.gd")
const BossBench = preload("res://scripts/run/boss_bench.gd")
const VictoryFlow = preload("res://scripts/run/victory_flow.gd")
const EnemyDemo = preload("res://scripts/run/enemy_demo.gd")
const GalleryProgress = preload("res://scripts/run/gallery_progress.gd")
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

## 贴图名单 / 特效帧数 / V6 帧条表在 art.gd（纯数据；10-15 从这里搬去，docs/101 S5、docs/55 §6 ①）。
## 这里留同名别名，g.V6_FRAMES / Game.FXF / Game.BASE_TEX 等引用照旧
const BASE_TEX = A.BASE_TEX
const ENEMY_SUFFIXES = A.ENEMY_SUFFIXES
const FXF = A.FXF
const V6_FRAMES = A.V6_FRAMES

enum S { PLAY, CHOICE, PAUSE, DEAD, WIN, SHOP, SHOW, STATS, INTRO, OPENING }

const PX := 2.0                 # 1 个美术像素 = 2 个世界像素
const TILE := 32.0              # 地砖在世界中的尺寸
const MERCHANT_TIMES := [120.0, 300.0, 480.0]   # 每次都在 Boss（3:30 / 7:00 / 10:00）之前

var ishar = IsharEncounter.new(self)
var trial = BossTrial.new(self)
var bench = BossBench.new(self)   # Boss 单场测试台（--benchsnap 录制 / --bossbench 开打，docs/170；只在 --balance）
var victory = VictoryFlow.new(self)
var defeat_outro = preload("res://scripts/run/defeat_outro.gd").new(self)   # 失败退场演出（docs/62 §3.21c）
var vis_t := 0.0   # 只给画面用的时钟偏移：失败慢放里敌人走路帧照常走（g.t 已停）；平时恒为 0
var speed_btn := Rect2()
var state: int = S.PLAY
var autotest_sys = AutoTest.new(self)   # 自动测试 / 平衡机器人（docs/29、docs/36）
var demo_sys = DemoRun.new(self)   # 图鉴攻击演示 / 精英化演出（gallery.gd 把 game.tscn 以 demo_op 模式放进 SubViewport）
var spawner = Spawner.new(self)   # 刷怪
var shop_sys = ShopSys.new(self)   # 商人与商店（逻辑）
var beacon_sys = Beacon.new(self)  # 引航灯标：站桩点燃、驱散溟痕（run/beacon.gd，docs/49d §13.5 C）
var weapons_sys = WeaponsSys.new(self)   # 子弹与支援装置
var pickups = Pickups.new(self)   # 掉落与拾取
var progression = Progression.new(self)   # 升级与藏品发放（逻辑）
var guide: BuildGuide = BuildGuide.new(self)   # 构筑引导：保底与加权规则（run/build_guide.gd）
var music_dir = MusicDirector.new(self)   # 局内配乐调度
var enemies_sys = EnemiesSys.new(self)   # 敌人的逐帧更新
var combat = Combat.new(self)   # 战斗结算
var afflict = Afflict.new(self)   # 负面状态门面（神经损伤 / 侵蚀 / 创口，run/afflict.gd）
var vfx = Vfx.new(self)   # 特效与提示
var intro_screen = IntroScreen.new(self)   # 界面 · 开场与教程
var tour = preload("res://scripts/screens/tour.gd").new(self)   # 界面 · 首局聚光框引导 + 到点小提示（取代开局自动弹出的翻页指南）
var boss_intro = BossIntro.new(self)   # 界面 · Boss 登场 / 击破演出（纯覆盖层，不影响模拟；用户 10-10）
var show_screen = EliteShowScreen.new(self)   # 界面 · 精英化 / 解锁演出（state SHOW）
var stats_screen = StatsScreen.new(self)   # 界面 · 属性面板（Tab，state STATS）
var settlement = preload("res://scripts/screens/settlement_screen.gd").new(self)
var result_screen = ResultScreen.new(self)   # 界面 · 结算（state DEAD / WIN）
var run_stats = RunStatsScreen.new(self)   # 界面 · 作战记录（结算上的「作战记录」按钮 / Tab 打开，docs/77）
var run_log = preload("res://scripts/screens/run_log_screen.gd").new(self)   # 界面 · 对局记录（结算「对局记录」，对内包；点一局进它的作战记录）
var headhunt = HeadhuntScreen.new(self)   # 界面 · 寻访（结算上有待用的券时盖在上面，docs/109 §12）
var roster_new := {}                       # 本局结算发的券（Roster.on_run_end）
var meta_cells := 0                        # 本局带入的认知塑造（已点生机细胞数，core/meta.gd）
var meta_once_heal: Array = []             # 「为了生存」：[生命比例阈值, 回复比例]，用掉后清空
var meta_start_relic := 0                  # 「物由心生」：开局从 n 件基础藏品中选 1（触发后清 0）
var meta_result := {}                      # 本局结算的生机细胞（Meta.on_run_end；结算面板显示）
var meta_basic_pick := false               # 正在开「物由心生」的三选一：藏品池只出基础稀有度
var panel_ui = ChoicePanel.new(self)   # 界面 · 弹窗面板与选卡（state CHOICE）
var shop_ui = ShopScreen.new(self)   # 界面 · 商店（state SHOP）
var hud_view = HudView.new(self)   # 界面 · 局内 HUD（hud 画布节点的 draw 信号）
var world = WorldView.new(self)   # 世界绘制（2.5D）
var telemetry = Telemetry.new(self)   # 局内数据记录（docs/40）
var perf_rep = PerfReport.new(self)   # 性能报告（core/perf_report.gd；设置 → 画面 → 性能报告）
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
var dodge := 0.0
var invuln := 0.0
var panel_grace_until := -1.0   # 低频面板关闭后的保护截止时刻（g.t）：combat.panel_grace 写，world 画脚下淡金环
var invuln_move_until := -1.0   # 纯画面：技能位移给的短暂无敌截止时刻（g.t）；这段无敌不闪烁（world.gd，10-21 推进之王跃空锤「虚化」）
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
var phys_taken_mult := 1.0       # 队长受到的物理伤害倍率（生存卡「硬化」，docs/83）
var corrode_taken_mult := 1.0    # 受到的侵蚀
var nerve_taken_mult := 1.0      # 神经损伤累积
# ---- docs/57 新接的属性（原先只在 stat_defs 里有定义、没人读）
var boss_mult := 1.0             # 对 Boss 伤害
var elite_mult := 1.0            # 对精英伤害（认知塑造「攻击性」）
var lamp_loss_mult := 1.0        # 受击 / 黑潮 / 吞噬的灯火流失
var enemy_speed_mult := 1.0      # 非 Boss 敌人移速
var enemy_kb_mult := 1.0         # 非 Boss 敌人受到的击退
var enemy_ranged_cd_mult := 1.0  # 远程杂兵开火间隔
var elite_taken_mult := 1.0      # 精英来源对主控的伤害
var in_type: Array = ["近战", "物理"]   # 当前受到的伤害类型（受击前设置）
var dmg_type_out: Dictionary = {}     # 造成伤害按类型统计
var RL: Dictionary = {}          # 藏品表 id -> {name, cat, desc, rarity, ...}（由 relic_fx 从 data/ 读取）
var tray_cells: Array = []       # 藏品栏格子 [Rect2, id]，用于鼠标悬停提示
var stats_cells: Array = []      # Tab 面板里可悬停的格子 [Rect2, kind, id]
var stats_page := 0              # 触屏版属性面板当前页（属性 / 技能 / 编队，stats_panel.gd；桌面三栏不用）
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
## ④ 移动粘滞（开关 feel/move_sticky，缺省 0 = 关、同 seed 不变；用户 10-24 试）：队长普攻出手瞬间 feel/fire_slow_t 秒移速 −feel/fire_slow，
## 起步 / 停步按 feel/accel_t 秒线性加减速（_mv_s 是平滑后的移动向量，停步时沿原方向滑一小段）
var fire_slow_t := 0.0
var _mv_s := Vector2.ZERO
var sticky_on := false   # 对内包 / 调试版 F8 临时切换（不存档），给用户开 / 关对比试手感
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
var threat := 0                  # 威胁等级（D.THREAT 下标）
var diff := 0                # 本局难度（累计档位 0–10，D.DIFFICULTY）
var preset := 0              # 本局难度档（D.DIFF_PRESETS 下标；批跑 --tide / --tier / --diff 时为 -1，不推进解锁）
var tier := 0                # 本局潮位（0–10，D.DIFFICULTY_TIERS 下标；10-22 起由三档改为潮位阶梯，docs/109 §5）
var dmod: Dictionary = D.dmod_for_level(0)   # 本局难度修正表（D.DMOD_DEFAULT 的键）；局内难度效果一律读它
var diff_new := false
var ending_new := false            # 本局首次达成该结局（结算面板显示）        # 本局通关解锁了新难度
var next_horde := Bal.v("enemy/first_horde", 75.0)   # 第一次大群（balance.json，docs/46 §1.2）
var horde_gap := 0.0          # 本次大群包围圈的缺口方向（弧度），预警箭头会留出这一侧
var horde_streams: Array = []   # 分股合围原型（docs/116 §7.2）：本次大群各股的方向（弧度），空 = 普通整圈；HUD 预警箭头只画这些方向
var horde_hunt := false      # 本次大群是「围猎型」（docs/150，10-25 围猎并进大群）：四面合拢、缺口小，HUD 只在缺口方向画一个小箭头
var horde_stream_rel: Array = []   # 各股出发时刻（与 horde_streams 对应），HUD 出发前 0.8 秒屏边预警
var show_queue: Array = []   # 解锁演出队列
var shop_refreshed := false  # 本次商人只能刷新一次
var show_t := 0.0
var show_shot := false
var horde_warn := 0.0        # 大群预警倒计时（HUD 演出）
var horde_hit := 0.0         # 大群到达后的屏幕演出
var boss = null                 # 当前显示血条的 Boss
var bosses: Array = []
var final_boss = null
var mid_boss_down := false   # 本局已击败过中期 Boss（藏品核心延后，docs/191 §6）
var ending := "standard"
var endg: RefCounted = null        # 结局与事件箱（scripts/endings.gd）
var knight: RefCounted = null      # 猎潮的骑士同伴（scripts/allies/knight.gd）
var touch: RefCounted = null       # 触屏操作（scripts/touch.gd）
var pick = preload("res://scripts/screens/command_pick.gd").new(self)   # 指点选目标阶段（示意原型，docs/196；缺省关）
var wheel = preload("res://scripts/screens/command_wheel.gd").new(self)   # 指挥圆盘（docs/114 §13）
var cam_fx = preload("res://scripts/run/cam_fx.gd").new(self)   # 镜头演出组合口：基础缩放 × punch()（终结技推镜；arch_review_1029 P1-1）
var tdil = preload("res://scripts/run/time_dilation.gd").new(self)   # 局内时间缩放唯一所有者（圆盘 / 终结技慢动作；arch_review_1029 P0-1）
var frost := 0.0                   # 冰霜：移速 -40%
# 小怪控制（用户 9/29，combat.gd「小怪控制」段；玩法系统的净化按这些字段清除）
var cold := 0                      # 寒霜层数：每层移速 / 攻速减益，满层冻结
var cold_t := 0.0                  # 寒霜剩余秒数（层数整体到时清零）
var cold_immune := 0.0             # 满层冻结后免疫再叠的秒数
var root_t := 0.0                  # 冻结 / 束缚：不能移动（可以攻击，冲刺挣脱）
var root_immune := 0.0             # 硬控后免疫秒数
var wound := 0                     # 侵蚀创口层数：减受治疗 + 每秒掉血
var wound_t := 0.0
var nerve_lock := 0.0             # 神经损伤满格后不再累积的秒数（combat.update_nerve）
var nerve_aura_k := 1.0            # 神经光环累积倍率（箱形恐鱼尖叫每帧设，update_nerve 读后复位）
var nerve_aura_t := 0.0           # 站在巢涌者神经光环里（按溟痕累积）
var apop := 0.0                    # 凋亡损伤量表 0–100：满了技能充能暂停 apop_t 秒（combat.add_apop）
var apop_t := 0.0                  # 技能充能暂停剩余秒数
var apop_hold := 0.0               # 距上一次累积的秒数（离开来源后回落用）
var lamp_cap := 100.0              # 灯火上限（深蓝之心后 70）
var knight_alive := false          # 猎潮的骑士在队中（结局二）
var force_boss := -1
var atk_slow := 0.0
var ebullets: Array = []
var shocks: Array = []
var warns: Array = []
var shots: RefCounted = null    # 敌方投射物池：抛物 / 敌弹 / 冲击环的推进（scripts/enemies/shot_pool.gd，docs/101 B7 ④）
var tele: RefCounted = null     # 预警服务：g.warns 登记 / 推进 / 判定 / 结算（scripts/enemies/telegraph.gd，docs/101 B2）
var bai: RefCounted = null      # Boss AI（scripts/boss_ai.gd；预警经 tele）            # Boss 招式预警 {shape, pos, ang, r, len, wid, half, t, dur, act, owner, dmg}
var mires: Array = []
var beacons: Array = []          # 引航灯标（run/beacon.gd）：{pos, lit, prog, need, lit_t, count_end, count_max, dead}
var in_mire := 0.0               # 站在溟痕里的程度（0..1，平滑过渡，用于减速与屏幕变暗）
var next_mire := 100.0           # 首次溟痕时间；开局由 map 主题覆盖
# 缩圈（黑潮）
var zone_c := Vector2.ZERO
var zone_r := 99999.0
var zone_next_c := Vector2.ZERO
var zone_next_r := 0.0
var zone_state := 0          # 0 未开始 / 1 预告 / 2 收缩 / 3 稳定
var zone_frozen := false     # 最终 Boss 场地冻结（combat.freeze_zone，docs/38 §1.7）：不再缩圈，圈边画场地描边
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
var ult_bench = null           # --ultbench（run/ult_bench.gd，docs/198 §3.4）
var ult = null                 # 终结技框架（run/ult.gd）：balance ult/on 关时为 null，旧的响应 / 连携 / 手动技能照旧
var doctor: RefCounted         # 博士层专属逻辑（scripts/characters/doctor.gd）
var ch: RefCounted             # 开局干员（squad.ops[0]）：成长 / 精英化 / HUD 在 P2 之前仍绑定在它身上
var eai: RefCounted            # 小怪行为（scripts/enemies/enemy_ai.gd），按 data/enemies.json 的 pattern 字段分派
var map: RefCounted            # 地图（scripts/world/map.gd）：铺地 / 道具 / 景物 / 碰撞 / 氛围
var draw_off := Vector2.ZERO
var foot_anchor := {}       # 美术交付的 Boss 图以脚底为锚点 # 2.5D：绘制时的高度偏移（击退腾空等）
var fg: Node2D               # 2.5D：前景视差层
var post: CanvasLayer          # 全屏后期（辉光 / 水下滤镜 / 亮度 / 受伤红边）
var dof_layer: CanvasLayer   # 2.5D：景深 / 远景水雾
var optical                  # 光学观感原型（render/optical.gd，balance render/optical，缺省关）
var glow_next: Array = []    # 光学观感：这一帧世界绘制排进来的发光点 [位置, 边长, 颜色]（render/world._glow_pts）
var glow_cur: Array = []     # 上一帧排好的，发光层这一帧画
var glow_tex_next: Array = []   # 光学观感：这一帧排进来的发光贴图 [贴图, 目标矩形, 源矩形, 颜色]（_emit 层：溟痕、经验结晶、溟痕退散）
var glow_tex_cur: Array = []
var optical_ops_hi := false  # 光学观感：干员本体画在高清层（render/optical_ops_hi，缺省关 = 干员和怪物同在低分辨率层、按脚底 y 前后遮挡）
var optical_lo := false      # 光学观感的低分辨率世界层这一帧开着（干员本体改画在高清层）
var optical_on := false      # 光学观感这一帧开着（optical.gd 写）：world / look 据此开朝灯亮线、敌人发光点、荧光颗粒（纯画面）
var lvup_delay := 0.0     # 升级演出：延迟弹出选择面板
var lvup_show := 0.0      # 角色头顶 LEVEL UP 字样
var hud_lv_flash := 0.0   # 左上角等级闪光
var xp_flash := 0.0       # 吃到经验时经验环亮一下
var pending_chests := 0
var chest_src: Array = []   # 与 pending_chests 并行的来源队列（遥测 relic_offer / relic_take 第 4 项，docs/191）：elite / boss / squad / wish / event / meta
## 木桩表（tests/op_dummy_test，docs/79）：只由测试场景置位。为真时不刷怪（含 Boss / 溟痕 / 威胁上升）、不走事件 / 围猎 / 灯标 / 商人 / 拾取，
## 场上只有测试自己摆的目标。缺省 false，正常游戏与其他测试行为完全不变
var sandbox := false

# ---------- 节点与资源 ----------
var cam: Camera2D
var sprite: Sprite2D
var lamp_light: PointLight2D
var actor_mat: ShaderMaterial = null   # 白色保护（render/look_white_lift > 0，scripts/render/look.gd）：挂在本节点上，只作用于干员本体
var merchant_light: PointLight2D
var knight_light: PointLight2D   # 骑士入潮点临时暖光（纯画面）
var hud: Control
var panel: Control
var panel_box: HBoxContainer
var panel_col: VBoxContainer   # 事件选项条（C 版式）的竖排容器
var panel_fg: Control          # 标题、商人立绘、事件插画画在这层（压暗带之上、卡片之下）
var panel_tip: Control         # 面板最上层：截断说明的完整提示
var font: Font
var tex := {}
## 网页版（OS.has_feature("web")）推迟到首次刷出时才加载的敌人贴图名（本体 / 帧条 / 白色剪影一起），省开局内存与解码时间：
## 老手机（2–3 GB 内存）的标签页在开局就解码全部 Boss 帧条会被系统杀掉（docs/33 移动端）。桌面版永远为空（行为不变）。
## 名单：开局 WEB_EARLY_T 秒内会刷到的种类（威胁表、精英 elite_after、同伴骑士）照常预载，其余在 spawner.new_enemy 里经 ensure_enemy_tex 按需加载
var tex_deferred := {}
const WEB_EARLY_T := 180.0
var panel_title_text := ""
# ---------- 打击感 ----------
var hitstop := 0.0
var shake := 0.0
var hurt_vignette := 0.0
var hurt_duck := 0.0         # 重击后配乐低通保持的剩余秒数（combat.hurt 写，music_director 读，world.update_player_feel 衰减；docs/53）
var tab_hint := 0.0          # 首次升级后再提醒一次 Tab
var _aq_us := 0             # 上一帧的真实时刻（网页帧率自动 _fps_probe 用）
var quality_note := ""       # 自动降档后的提示（hud_banners.draw_open_hints 画）
var quality_note_t := 0.0
var tab_used := false
var hp_trail := 100.0        # 血条上的「被扣掉」残影
var hp_shake := 0.0
var head_bar_t := 0.0        # 头顶血条显示时长
var red_flash := 0.0
var crit_hit := false
var fx_add: Node2D
var settings: Control
var ui_layer: CanvasLayer   # 界面层（HUD / 面板 / 设置）：触屏时整体放大 Cfg.ui_k
var result_btns: Array = []   # [Rect2, action]
var pause_btn := Rect2()      # 右上角暂停按钮（仅游戏中可点）
# ---- 手柄 / 键盘焦点（docs/28）：选卡 / 商店的卡片焦点、暂停与结算按钮焦点
var nav_sel := 0               # 当前焦点卡片（选卡 / 商店共用 panel_box 的下标）
var res_sel := 0               # 暂停 / 结算按钮焦点
var kb_nav := false            # 键盘方向键导航过（显示焦点而不是鼠标悬停），鼠标一动就关
var ui_skip := false            # 本状态的界面动效（暂停表盘 / 失败结算打捞）已被输入跳到终态（docs/62 §2.5）；切状态时清掉
var _skip_frame := -1            # 跳过动效那一帧：同一帧里随之而来的模拟鼠标 / 手柄注入按键一并吞掉
var state_age := 0.0           # 进入当前状态的秒数（防止手柄连按把刚弹出的选卡 / 演出直接点掉）
var _last_state := -1

# ---------- 自测 ----------
## 运行模式（docs/55 §2.6，10-10）：PLAY 正式游玩 / AUTOTEST `--autotest` 自测 / BALANCE `--balance` 批跑（含自测的一切）。
## 各处分支一律比较 mode；下面两个布尔是过渡期的只读派生（hud / vfx / world 与 tools 仍读），赋值只给演练 / 测试把模式拨回 PLAY 用
enum Mode { PLAY, AUTOTEST, BALANCE }
var mode := Mode.PLAY
var autotest: bool:
	get:
		return mode != Mode.PLAY
	set(v):
		mode = (mode if mode != Mode.PLAY else Mode.AUTOTEST) if v else Mode.PLAY
var balance: bool:
	get:
		return mode == Mode.BALANCE
	set(v):
		mode = Mode.BALANCE if v else (Mode.AUTOTEST if mode == Mode.BALANCE else mode)
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
var demo_enemy := ""
var enemy_demo = EnemyDemo.new(self)
var demo_op := ""
var dbg_offer := {}              # 平衡输出：各干员深度卡被提供 / 被选中的次数
var dbg_pick := {}
var dbg_relic_offer: Array = []  # 平衡输出：藏品三选一 / 商店的候选（[t, 来源, [id...]]）
var dbg_relic_take: Array = []   # 平衡输出：获得的藏品（[t, id, 当时编队职业]）
var relic_out := 0.0             # 平衡输出：藏品直接造成的伤害（描述符 origin == relic）
var bal_maxt := 780.0            # --maxt=<秒>：平衡 / 冒烟测试提前结束（默认 780 = 终局 Boss 登场后再给 3 分钟）
var realtime := false            # --realtime（仅测试，配合 --balance --perf）：按真实帧间隔推进、不多跑模拟步，测真实游戏的帧时间
var playclock_test := false     # --playclock（仅测试，配合 --balance --realtime）：开垂直同步、按玩家局的 PlayClock 分步推进，测玩家实际帧时间（docs/50 §10）
var upd_n := 0                  # _update 调用次数（--perfdump 逐帧记模拟步数）
var perf_alt := false           # --perfab=N（仅测试）：autotest 每 N 帧轮换，同局对照两种实现（docs/50 §10）
## 2026-10-15（docs/101 S2）：下面 1–32768 这些位的旧实现都已删掉，只有 OPT_HUDB（128）的旧写法还在 HUD 里（归界面与美术）；
## 编号保留不复用，--optab / --optmask / --optold 框架照旧，给以后的对照位（如原生代码 OPT_CPP = 131072，docs/101 §4.7）用。
## 性能优化同局对照（docs/50 §11，仅测试）：--optab=N 每 N 帧在「新实现」与「旧实现」之间轮换；opt_old 是当前走旧实现的优化位（OPT_*），
## --optmask=<位> 只轮换其中几项（缺省全部）；--optold=<位> 整局固定走旧实现。正常游戏恒为 0（全走新实现）。各项新旧实现逐帧结果相同
var opt_old := 0
const OPT_GEM := 1        # 掉落物更新
const OPT_GEMDRAW := 2    # 掉落物绘制
const OPT_CLEANUP := 4    # 清理死亡实体
const OPT_ENEMY := 8      # 敌人更新
const OPT_DRAW := 16      # 其他绘制
const OPT_OUTLINE := 32   # 普通怪 / 精英描边（docs/50 §12 A：新 = 不画；旧 = 照 fx/outline_max 满屏降级画）——会改画面，只供同局量帧时间
const OPT_ATLAS := 64     # 普通怪 / 精英帧条图集（docs/50 §12 B：新 = 图集取帧；旧 = 各自的帧条贴图），画面相同
const OPT_HUDB := 128     # HUD 合批（docs/50 §13）：旧实现已删（docs/101 S2，10-15），位保留不再选路
const OPT_PICKB := 256    # 掉落物剩余断点合批（docs/50 §13：空中影子 / 特殊掉落的圈与光柱进三角形批、贴图成组），画面相同
## docs/50 §14 脚本热点（画面、玩法不变）：
const OPT_CV := 512       # 干员合批画布（characters/batch_canvas.gd）：圆 / 弧 / 线 / 矩形整组生成顶点（单位方向表 × 变换），无索引三角形
const OPT_ZONE := 1024    # 黑潮缩圈：圈外暗区的圆周点按方向表整组生成、一次提交；溟痕带的每段方向与溟痕块的大小 / 偏移 / 翻转按段数缓存
const OPT_SORT := 2048    # 排序实体：键进 PackedFloat64Array 原生排序（不走 sort_custom 闭包），不建每只三元数组
const OPT_EDRAW := 4096   # 敌人绘制：受光封顶逐只走轻量版、缓存路径判定的不变项记一次、词条先判再算头顶、预警 / 巢涌光环不建默认空数组
## （8192 试过「敌人模拟」：循环外取引用、无招式种类跳过 pattern、分离按距离平方粗筛——同局实测只省约 0.02 毫秒，没留，docs/50 §14）
## docs/50 §15 画面小改（用户 10-14 批准 D：几乎看不出的画面变化，玩法不变；同 seed TRACE 与 --optold 逐行相同）：
const OPT_BAND := 8192    # 黑潮溟痕带：带状三角剖分（缓存索引表）一次提交，不再 draw_polygon 当场耳切三角化
const OPT_LIGHT := 16384  # 敌人受光封顶：每帧按「到灯的距离」建一张表（整屏统一算一次），逐只只查表插值，不再逐只算衰减 / 软膝
const OPT_PCAP := 32768   # 干员粒子 / 帧条上层数量上限（render/pfx_cap）：同屏超过上限时最旧的不画（粒子照常走完寿命，不改列表）
const OPT_OPS := 65536    # 干员每帧分配（docs/101 S9）：stat 作用域键缓存、_trigs 按精英化 / 节点数缓存、_sustain 复用缓冲；玩法、画面不变
const OPT_VIS := 262144   # 世界层视野表（docs/101 B4 ①）：draw_world 开头剔除一次、影子 / 排序 / 精英登场 / 敌人预警共用；置位时各层照旧自己扫全表。画面相同
const OPT_CPP := 131072   # 原生代码对照位（docs/101 §4.7 / B8）：置位时走 GDScript 核心（enemies._motion_core 等）；原生库还没接入，现在恒走 GDScript
## docs/50 §21（10-21，网页为主基准）：
const OPT_HUDSQ := 524288   # HUD 编队栏：各干员 skill_hud() / portrait() 每帧取一次共用，每帧层不再算名字 / 精英标签；置位走旧写法（每帧取 2–3 次）。画面相同
const OPT_HUDNC := 2097152   # HUD 块缓存（docs/126 §9.2）：置位时所有 HUD 块每帧画（同 --hudnocache），供 --optab 同局轮换量缓存的净收益。画面相同
const OPT_PARA := 4194304   # 偏执狂二阶段「海嗣滴」弹：两个多边形进 TriBatch（Geometry2D 三角化后随批提交），不再每颗弹 tb_flush + 两次 draw_colored_polygon；置位走旧写法。画面相同（同一三角化）
const OPT_TOUCHB := 1048576  # 触屏按钮（touch.gd draw_hud）：圆 / 弧 / 线进 TriBatch、图标与字随后成组画；置位走旧写法（逐个 draw_*）。画面相同（按钮互不重叠时）
var bal_dt := 0.066             # --dt=<秒>（仅 --balance）：批跑每帧步长，缺省 0.066（9/30 起所有难度校准 / 云端基线的口径）；按位移判定的改动可用 --dt=0.016667 抽查（docs/36 §8.2）
var placebo_n := 0              # --placebo=N（仅测试）：开局多抽 N 次主 rng——机制不变、换一份随机实现，判「改动」还是「这组 seed 的运气」（docs/36 §8.2）
var rt_from := -1.0              # --rtfrom=<秒>（仅测试，配合 --realtime）：游戏时间到这一秒前按批跑步长快进，之后切成真实步长（量后期帧时间时省掉前面几分钟）
var prof_on := false             # --prof：模拟步分段计时，结果随 BALANCE 行输出（docs/36）
var prof := {}                   # 段名 -> 累计微秒
var _prof_t := 0
var trace_every := 0.0           # --trace=<秒>：每隔几秒打印一行状态摘要（排查同 seed 能否复现，docs/36）
## 视觉随机数：火花、飘字抖动等纯表现用它。对局随机数 rng 只给玩法用——表现层按真实帧率运行，
## 如果它们共用 rng，同一个 seed 在机器忙闲不同时就会跑出不同的局（2026-09-26 查明）
var vrng := RandomNumberGenerator.new()
## 按用途派生的玩法随机流（docs/101 B7 ①，10-15；rng_op 积木）：局种子 + 名字 hash 派生，同 seed 可复现；一处多抽 / 少抽只影响自己那条流，
## 原生段（EnemyCore）也不会碰到别处的序列。rng_spawn 刷怪；rng_enemy 敌人 AI、Boss 脚本、吞噬、形变；rng_drop 击杀 / 卡点 / 宝箱掉落。
## 其余玩法（暴击、闪避、藏品、选卡、变动区、地图）仍走 rng
var rng_spawn := RandomNumberGenerator.new()
var rng_enemy := RandomNumberGenerator.new()
var rng_drop := RandomNumberGenerator.new()
var rng_op := RandomNumberGenerator.new()   # 干员积木的玩法随机（docs/101 B7，干员 10-15 同意）


## 全部玩法随机流的状态（测试断言「某段代码不掷随机数」用）
func rng_states() -> Array:
	return [rng.state, rng_spawn.state, rng_enemy.state, rng_drop.state, rng_op.state]
var headless_batch := false      # --balance 且无界面：跳过所有重绘
var demo_elite := 0            # 演示时把干员直接推到这个精英化阶段（精英化演出用）
var demo_nodes := -1           # 成长节点验收（docs/202）：>= 0 时图鉴演示按这个数推成长节点（覆盖 demo_stage 的 2 / 5 / 6）；路线用 --route=<干员>:<路线>
var demo_stage := -1           # 三联对照（--compareshot）：0 = 精一前（N1 N2）/ 1 = 精二前（到 N5）/ 2 = 全部；-1 不用
var demo_basic := false        # 只普攻、不放技能（三联对照看普攻形态的成长）
var entry_voice_hold := true   # 开局编队的登场语音先不播：等第一帧局内画面画出来（开场演出则等编队着地）再放（release_entry_voices，用户 10-25）
var first_frame_ms := -1       # 第一帧局内画面画完的时刻（--loadprof 打语音相对它的时差）


## 进局接续层：对局最初几帧仍盖着载入页最后那一帧（压暗的「展开战场 100%」），画满 COVER_FRAMES 帧再撤，下面是开场演出的黑场。
## 网页第一帧之后还有一段十几秒的卡顿（10-25 实测，疑似首次用到的着色器在编译），以前这段停在一帧没盖住的战场上
const COVER_FRAMES := 4
var _cover: CanvasLayer
var _cover_n := 0

func _cover_begin() -> void:
	_cover = CanvasLayer.new()
	_cover.layer = 120
	add_child(_cover)
	var ls = preload("res://scripts/screens/loading_screen.gd").new()
	_cover.add_child(ls)
	ls.hold()
	RenderingServer.frame_post_draw.connect(_cover_tick)


func _cover_tick() -> void:
	_cover_n += 1
	if _cover_n >= COVER_FRAMES and _cover != null:
		RenderingServer.frame_post_draw.disconnect(_cover_tick)
		_cover.queue_free()
		_cover = null


## 放开开局编队的登场语音（每人一次，entry_started 自己去重）：开场演出里编队着地 / 跳过开场时，其余模式在第一帧画完后
func release_entry_voices() -> void:
	if not entry_voice_hold:
		return
	entry_voice_hold = false
	A.mark("entry_voice")
	if Cfg.dev_args().has("--loadprof"):
		print("LOADPROF_VOICE entry_voice=+%d after first_frame_drawn" % (Time.get_ticks_msec() - first_frame_ms) if first_frame_ms >= 0 else "LOADPROF_VOICE entry_voice before first_frame_drawn")
	for o in squad.ops:
		o.entry_started()


## 图鉴「演示」分帧预载的补充名单（10-21）：_ready 里 preload_tex_names 之外的小图——技能图标、特效帧条、
## 武器 / 成长图标、固定敌人的白色剪影贴图。漏了只是建局时当场读（--loadprof 下用 A.late_log 能看到）。
static func demo_warm_names() -> Array:
	var names: Array = ["player_attack_48", "player_idle", "player_run", "player_attack", "player_hurt", "player_death", "skill_s1", "skill_s2", "skill_s3"]
	names.append_array(FXF.keys())
	names.append_array(["fx_umbrella_slash", "fx_umbrella_slash_awaken", "fx_umbrella_slash_mirage"])
	names.append_array(Vfx.STRIPS)
	for pid in Doctor.PASSIVES:
		names.append("growth_" + pid)
	for wid in D.WEAPONS:
		names.append("weapon_" + wid)
	for n in BASE_TEX:
		if str(n).begins_with("e_"):
			names.append(str(n) + "_white")
	for cid in Character.list_ids():
		for sd in Character.load_def(cid).get("skills", []):
			if sd.get("icon", "") != "":
				names.append(sd.icon)
	return names


## 一局开始（_ready）会固定加载的贴图名单，只看静态数据，标题页用它预热法线图（art.gd prewarm_start）。
## 覆盖 _ready 里的固定表、博士与全部干员的帧条、V6 帧、data/enemies.json 的敌人及附加帧条、地图主题的道具与前景。
## 不做法线的前缀（fx_ / proj_ / relic_ …）由 art.gd 过滤，这里不用管；漏掉的名字只是回到当场算（--loadprof 的 sync_names 能看到）
## 开局要读帧条的干员：缺省全部可招募干员；手机网页只读队长（10-26 iPhone 进局即崩，按内存止血；中途入队的由 squad.add → load_op_tex 补读）
static func _op_tex_ids() -> Array:
	if Cfg.mobile_web() and Cfg.mobile_knob("mobile_lazy_ops", 1.0):
		return [Cfg.character_id]
	return Character.list_ids()


static func preload_tex_names() -> Array:
	var names: Array = []
	names.append_array(BASE_TEX)
	names.append_array(["player_attack_48", "player_idle", "player_run", "player_attack", "player_hurt", "player_death"])
	var dj = JSON.parse_string(FileAccess.get_file_as_string("res://data/doctor.json"))
	if dj is Dictionary:
		for kind in ["idle", "run", "hurt", "death"]:
			var dn = dj.get("sprites", {}).get(kind, "")
			if dn is String and dn != "":
				names.append(dn)
	for cid in _op_tex_ids():
		var cdef: Dictionary = Character.load_def(cid)
		var csp: Dictionary = cdef.get("sprites", {})
		for kind in ["idle", "run", "attack", "skill", "hurt", "death", "move_attack"] + cdef.get("extra_sprites", []):   # move_attack：移动攻击（docs/128，character._move_swap）
			if csp.has(kind):
				names.append(csp[kind] if csp[kind] is String else csp[kind].tex)
		if csp.has("base"):
			names.append(csp.base)
		var nsa = csp.get("noshield", {}).get("art", {}) if csp.get("noshield", {}) is Dictionary else {}
		for kind in nsa:   # 星熊无盾帧条（_ready 也加载）：以前漏在名单外，开局 / 演示时当场算法线 100–230 ms 一张
			names.append(str(nsa[kind]))
	names.append_array(V6_FRAMES.keys())
	var etex: Array = ["e_paranoia2", "e_ishar_t", "e_ishar_transform"]   # 伊莎玛拉变身形态（render/world.gd 原来首次画到才读：变身那一帧同步读图 + 算法线，卡 0.7–0.8 秒，docs/50 §10）
	for k in D.ENEMIES:
		var tn: String = D.ENEMIES[k].tex
		if not etex.has(tn):
			etex.append(tn)
	for n in etex:
		names.append(n)
		for suffix in ENEMY_SUFFIXES:
			names.append(n + suffix)
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/%s.json" % Cfg.map_id))
	if mj is Dictionary:
		for pr in mj.get("props", []):
			names.append(pr.tex)
		names.append_array(mj.get("big_props", {}).get("list", []))
		names.append_array(mj.get("foreground", {}).get("tex", []))
	return names


## 脚底锚点：enemies.json 写了 anchor = "foot" 的贴图（docs/94 重画的 17 种 + 共用 e_stone 的 spitter，帧条按规格脚底贴画布底边）一律脚底；
## 其余（Boss、骑士、事件 / 宝箱等）沿用原判断：美术交付的图、美术像素高度 ≥ 32（@2x 除以倍率）
func _wants_foot(n: String) -> bool:
	if tex.get(n) == null:
		return false
	for k in D.ENEMIES:
		if str(D.ENEMIES[k].get("anchor", "")) == "foot" and D.ENEMIES[k].get("tex", "") == n:
			return true
	return A.has_override(n) and tex[n].get_height() / A.hires_of(tex[n]) >= 32


## 一个敌人贴图名的整套加载：本体 + 白色剪影 + 脚底锚点 + ENEMY_SUFFIXES 帧条（_death 不要剪影）。_ready 的预载与网页版按需加载共用
var _enemy_loaded := {}   # 经 _load_enemy_tex 读进来的敌人帧条本体名（手机网页释放只动这些）

func _load_enemy_tex(n: String) -> void:
	if not BASE_TEX.has(n):
		_enemy_loaded[n] = true
	if tex.get(n) == null:
		tex[n] = A.tex(n)
		if tex[n] != null and not lazy_white:
			tex[n + "_white"] = A.white_of(tex[n])
	if _wants_foot(n):
		foot_anchor[n] = true
	for suffix in ENEMY_SUFFIXES:
		var mn: String = n + suffix
		if tex.get(mn) == null:
			tex[mn] = A.tex(mn)
			if tex[mn] != null and suffix != "_death" and not lazy_white:
				tex[mn + "_white"] = A.white_of(tex[mn])


## 本局是否给贴图生成法线图：无界面运行不画，光学观感开着时也不生成（docs/130 A4，用户 10-24 定：朝灯亮线已取代法线的立体感）。
## render/optical_normals 1 = 光学下也开（对照用）。标题页预热 / 载入页读图按同一判断（title_base._prewarm），缓存的贴图与局内一致
static func wants_normal_maps() -> bool:
	return Cfg.wants_normal_maps()   # 判断搬到 settings.gd（标题页用，不带出对局那一圈，docs/50 §29）


## 进局载入页分帧预读的贴图（title.gd → A.warm_begin）：[名字, 要白色剪影的名字]。和 _ready 读的同一批（preload_tex_names + 图鉴演示补充名单），
## 读进 A 的缓存后 _ready 直接命中，进局不再冻住一整段（10-25 实测网页 ~32 秒、桌面 ~9 秒）。网页推迟加载的敌人（Boss 等）照旧不读
static func loading_warm_lists() -> Array:
	var early: Dictionary = _web_early_enemy_tex() if OS.has_feature("web") else {}
	var skip := {}
	var whites: Array = []
	for k in D.ENEMIES:
		var tn: String = D.ENEMIES[k].tex
		if not early.is_empty() and not early.has(tn):
			skip[tn] = true
			continue
		if not whites.has(tn):
			whites.append(tn)
			for suffix in ENEMY_SUFFIXES:
				if suffix != "_death":
					whites.append(tn + suffix)
	for n in V6_FRAMES:
		if str(n).begins_with("e_") and not skip.has(str(n)):
			whites.append(n)   # V6 敌人附加帧条（休眠 / 唤醒 / 狂暴）的白色剪影，_ready 的 tex_v6 段也要
	var names: Array = []
	if Cfg.mobile_web() and Cfg.mobile_knob("mobile_lazy_white", 1.0):
		whites = []   # 手机网页白剪影按需建（ensure_white），载入页不预建
	for n in preload_tex_names() + ([] if Cfg.mobile_web() else demo_warm_names()):   # 手机网页不预读图鉴演示的补充名单（docs/50 §30）
		var base := str(n)
		for suffix in ENEMY_SUFFIXES:
			if base.ends_with(suffix):
				base = base.trim_suffix(suffix)
				break
		if not skip.has(base):
			names.append(n)
	return [names, whites]


## 网页版开局要预载的敌人贴图名：威胁表 WEB_EARLY_T 秒内各档的池子、elite_after ≤ WEB_EARLY_T 的精英（含拟态箱）、同伴骑士（开局就在场上画）
static func _web_early_enemy_tex() -> Dictionary:
	var early := {}
	for i in D.THREAT.size():
		if float(D.THREAT[i].get("t", 0.0)) <= WEB_EARLY_T:
			for k in D.THREAT[i].get("pool", []):
				if D.ENEMIES.has(k):
					early[D.ENEMIES[k].tex] = true
			for mix in D.THREAT[i].get("horde_mix", []):
				for k in mix:
					if D.ENEMIES.has(k):
						early[D.ENEMIES[k].tex] = true
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if d.get("role", "") == "elite" and float(d.get("elite_after", 0.0)) <= WEB_EARLY_T:
			early[d.tex] = true
	if D.ENEMIES.has("knight"):
		early[D.ENEMIES.knight.tex] = true
	# 普通怪 / 精英（Boss 除外）全部预载（docs/50 §12）：帧条合计约 0.2 M 像素，开局要拼进敌人图集；推迟加载留给 Boss 的大帧条。
	# 手机网页不拼图集（docs/50 §30.3），这些也按需读，不在场的种类再释放（_enemy_evict）
	if Cfg.mobile_web() and Cfg.mobile_knob("mobile_evict", 1.0):
		return early
	for k in D.ENEMIES:
		var dk: Dictionary = D.ENEMIES[k]
		if str(dk.get("role", "")) != "boss" and not dk.get("boss", false):
			early[dk.tex] = true
	return early


## 网页版按需加载（spawner.new_enemy 在生成字典前调用）：n 及其派生名（e_paranoia → e_paranoia2）若在推迟名单里就现在读。
## 桌面版名单为空，直接返回；不碰 g.rng，同 seed 不受影响
## 白剪影按需建、不在场就释放（10-26，手机网页；docs/50 §30.6）：受击闪白 / 轮廓光用的白剪影是本体帧条的整份拷贝，
## 原来开局给每种敌人（含全部变体帧条）都建一份，手机一局约 48 MB。现在某种怪刷出来时才建（spawner.new_enemy → ensure_white），
## 场上没有这种怪满 WHITE_KEEP 秒就把它的白剪影丢掉（g.tex 里的键也删，画白闪处按 has() 判断，场上没有就不会去画）。画面不变
var lazy_white: bool = (Cfg.mobile_web() and Cfg.mobile_knob("mobile_lazy_white", 1.0)) or Cfg.dev_args().has("--evicttest")   # --evicttest：桌面上试按需建 / 释放
var _white_alive := {}    # 帧条本体名 -> 最近一次在场的 g.t
var _white_t := 0.0
const WHITE_KEEP := 20.0
const ENEMY_KEEP := 60.0
var _evict_on: bool = (Cfg.mobile_web() and Cfg.mobile_knob("mobile_evict", 1.0)) or Cfg.dev_args().has("--evicttest")
var _font_t := 0.0


## 手机网页：场上没有这种怪满 ENEMY_KEEP 秒，把它的帧条（本体 + 移动 / 攻击 / 死亡等变体 + V6 附加帧条）从贴图表和 A 缓存里拿掉，
## 记回推迟名单——再刷出来时 spawner.new_enemy → ensure_enemy_tex 重新读（会卡一下，换内存不涨；docs/50 §30.7）。
## 只动经 _load_enemy_tex 读进来的敌人帧条（固定表 BASE_TEX、骑士等不动）
func _enemy_evict(n: String) -> void:
	if not _enemy_loaded.has(n):
		return
	perf_rep.tag("释放帧条")
	_enemy_loaded.erase(n)
	for nm in _white_names(n) + [n + "_death"]:
		if tex.has(nm):
			tex.erase(nm)
			A.uncache(nm)
	tex_deferred[n] = true

func ensure_white(n: String) -> void:
	if not lazy_white or n == "":
		return
	_white_alive[n] = t
	if tex.has(n + "_white"):
		return
	perf_rep.tag("建白剪影")
	for nm in _white_names(n):
		if tex.get(nm) != null and not tex.has(nm + "_white"):
			tex[nm + "_white"] = A.white_of(tex[nm])


func _white_names(n: String) -> Array:
	var out: Array = [n]
	for suffix in ENEMY_SUFFIXES:
		if suffix != "_death":
			out.append(n + suffix)
	for v in V6_FRAMES:
		if str(v).begins_with(n + "_") and not out.has(str(v)):
			out.append(str(v))
	return out


func _white_release(delta: float, now := false) -> void:
	if not lazy_white:
		return
	_white_t += delta
	if _white_t < 5.0 and not now:
		return
	_white_t = 0.0
	var keep_w: float = 0.0 if now else WHITE_KEEP   # now：内存护栏要立刻腾（不在场就放，不等 20 / 60 秒）
	var keep_e: float = 0.0 if now else ENEMY_KEEP
	for e in enemies:
		_white_alive[str(e.get("tex", ""))] = t
	for n in _white_alive.keys():
		if t - float(_white_alive[n]) > keep_w and tex.has(n + "_white"):
			for nm in _white_names(n):
				if tex.has(nm + "_white"):
					tex.erase(nm + "_white")
					if tex.get(nm) != null:
						A.white_drop(tex[nm])
		if t - float(_white_alive[n]) > keep_e and _evict_on:
			_enemy_evict(n)
			_white_alive.erase(n)
	_font_t += 5.0
	if _font_t >= 60.0 and Bal.v("web/font_clear_minutely", 0.0) > 0.0:
		_font_t = 0.0
		perf_rep.tag("清字形")
		Cfg.slim_fonts(true)   # （10-27 起缺省关，docs/50 §39）原来手机网页每分钟清一次字形缓存（10 分钟约 18 MB），清完全部界面字重新栅格化，
		# 网页仿真里 60 秒前后连着几帧 270–450 ms；内存护栏超线时第一步就清，平时不清


func ensure_enemy_tex(n: String) -> void:
	if not tex_deferred.has(n):
		return
	var t0 := Time.get_ticks_msec()
	var names: Array = []
	for k in tex_deferred:
		if k == n or (k as String).begins_with(n):
			names.append(k)
	for k in names:
		tex_deferred.erase(k)
		_load_enemy_tex(k)
	var ms: int = Time.get_ticks_msec() - t0
	perf_rep.tag("读帧条")   # 性能报告：这一秒里补读过推迟的敌人帧条（docs/50 §39 尖峰定位）
	if not Cfg.dev_args().is_empty():
		print("PF TEXLAZY t=%.1f %s ms=%d" % [t, ",".join(names), ms])


## 网页版推迟加载漏网的贴图（画到了还没读的敌人）：记一次日志，顺手把它读进来。正常跑不该出现，网页版测试在控制台里 grep TEXMISS
func tex_deferred_miss(n: String) -> void:
	for k in tex_deferred:
		if n == k or n.begins_with(k):
			print("TEXMISS %s（推迟名单 %s）" % [n, k])
			ensure_enemy_tex(k)
			return


func _ready() -> void:
	A.mark("ready_begin")
	trial.consume()
	# 随机数最先定：招募开局干员时就会用 rng（战斗台词计时等）。以前 --seed 在 _ready 后段才生效，
	# 开局干员的台词计时是随机的，第一句台词一出同 seed 的两局就分叉（2026-09-26 查明，docs/36）
	var seeded := false
	for a in Cfg.dev_args():
		if a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
			# --rngshift（快检「同 seed 复现」第 3 局）：画面随机流与全局随机流换种子；玩法只能用 g.rng 系，结果必须不变
			var shift: int = 1 if Cfg.dev_args().has("--rngshift") else 0
			vrng.seed = int(a.substr(7)) + 7919 + shift
			seed(int(a.substr(7)) + shift)
			seeded = true
		elif a.begins_with("--placebo="):
			placebo_n = maxi(0, int(a.substr(10)))
	if not seeded:
		rng.randomize()
		vrng.randomize()
	rng_spawn.seed = hash([rng.seed, "spawn"])
	rng_enemy.seed = hash([rng.seed, "enemy"])
	rng_drop.seed = hash([rng.seed, "drop"])
	rng_op.seed = hash([rng.seed, "op"])
	for _pk in placebo_n:
		rng.randf()   # 安慰剂实现：只推进主流，派生流已按种子定好；局面从第一次用主流起分叉
	if demo_op == "":
		Sfx.voice_reset()   # 上一局没播完的部署语音不带进新一局
	bai = BossAI.new(self)
	tele = Telegraph.new(self)
	shots = ShotPool.new(self)
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
	ult = Ult.new(self) if Ult.on() else null
	tdil.add("wheel", wheel.slow, "play")   # 圆盘打开：局内放慢（不全停），批跑里也生效
	tdil.add("pick", func() -> float: return Bal.v("command/wheel_slow", 0.2) if pick.active else 1.0, "play")   # 指点选点中：同圆盘放慢（integ-1029 合入）
	if ult != null:
		tdil.add("ult", ult.time_scale, "fx")   # 终结技瞄准慢动作（docs/198 §2.4）：演出性，批跑不缩
		cam_fx.add("ult", ult.cam_punch)   # 终结技推镜（§7.1）
	# 开局干员：标题页选人写入 Cfg.character_id；--op=<id> 测试覆盖；不存在时退回水月
	for a in Cfg.dev_args():
		if a.begins_with("--op="):
			Cfg.character_id = a.substr(5)
	if not Character.exists(Cfg.character_id):   # 正式名单 + 测试专用干员（docs/61 §测试，tests/data_ops）
		Cfg.character_id = "mizuki"
	A.mark("map+doctor")
	ch = squad.add(demo_op if demo_op != "" else (str(trial.config.operator) if trial.active else Cfg.character_id))
	# 主控干员的受击属性（2026-09-26 用户要求，按原作换算）：JSON leader 段的 生命 / 物理减伤 / 法抗 覆盖博士 JSON 的基础值；
	# 回复、移速、拾取仍由博士 JSON 统一给（闪避 10-27 起归零，见下方 squad/leader_dodge）
	# --noleader：平衡对照用，退回改动前「所有主控同一条血、无减伤」
	var lead: Dictionary = {} if Cfg.dev_args().has("--noleader") else ch.def.get("leader", {})
	for k in ["max_hp", "armor", "arts_res"]:
		if lead.has(k) and stats.has_stat(k):
			stats.set_base(k, float(lead[k]))
	# 基础砍（docs/109 §14 v4，用户 10-22「砍干员基础数值，把差值留给树」）：干员攻击倍率的基础值；1 = 不变
	# （队长最大生命的 ×0.9 已直接写进各干员 JSON 的 leader.max_hp 与 doctor.json，10-29 去掉 squad/leader_hp_mult）
	if stats.has_stat(&"op_atk"):
		stats.set_base(&"op_atk", Bal.v("squad/op_atk_base", 0.9))
	# 队长基础移速（用户 10-28：150 → 165，+10%）：基础值乘 squad/leader_speed_mult；冲刺距离 / 冷却不动；1 = 不变
	if stats.has_stat(&"move_speed"):
		stats.set_base(&"move_speed", float(stats._base[&"move_speed"]) * Bal.v("squad/leader_speed_mult", 1.1))
	# 闪避移进局外成长（用户 10-27，docs/109 §17）：队长基础闪避归零，少掉的有效生命用受到伤害 × dodge_comp_taken 补回（生命补偿 dodge_comp_hp 恒为 1，10-29 删掉）；部分补回（用户定只补受伤 ×0.9，有意削弱无成长）
	# 回退：squad/leader_dodge 0.25、两个补偿 1
	stats.set_base(&"dodge", Bal.v("squad/leader_dodge", 0.0))
	stats.set_base(&"dmg_taken", Bal.v("squad/dodge_comp_taken", 0.9))
	# 博士动画条（data/doctor.json 的 sprites：idle / run / hurt / death）
	for kind in ["idle", "run", "hurt", "death"]:
		var dn = doctor.def.get("sprites", {}).get(kind, "")
		if dn is String and dn != "":
			tex[dn] = A.tex(dn)
	A.mark("squad_add")
	next_mire = float(map.mire_cfg().get("first_at", 100))
	# 无界面运行（批跑 / 冒烟）不画任何东西，法线图纯属浪费：一局启动要多花十几秒
	# 光学观感开着时也不生成（docs/130 A4，用户 10-24 定）：朝灯亮线已取代法线的立体感，法线在半分辨率世界层里细节大多丢失
	A.normal_maps = wants_normal_maps()
	rfx = RelicFx.new(self)
	endg = Endings.new(self)
	knight = Knight.new(self)
	touch = Touch.new(self)
	if D.ENEMIES.has("knight"):
		D.ENEMIES.knight.no_spawn = true  # 敌对骑士只在同伴骑士阵亡后进入精英池（每局重置）
	RL = rfx.table()
	Meta.apply_run(self)   # 认知塑造（docs/109 §4）：已点节点写进属性块与开局资源；测试局缺省不带，--meta=N 才带
	A.mark("subsystems")
	font = load("res://fonts/ui.ttf")
	for n in BASE_TEX:
		tex[n] = A.tex(n)
		if n.begins_with("e_") and _wants_foot(n):
			foot_anchor[n] = true
		if n.begins_with("e_") and tex[n] != null:
			tex[n + "_white"] = A.white_of(tex[n]) if A.has_override(n) else A.tex(n + "_white")
	A.mark("tex_base")
	# 可选素材：有图就用，没有就用程序效果
	var optional := ["player_attack_48", "player_idle", "player_run", "player_attack", "player_hurt", "player_death", "skill_s1", "skill_s2", "skill_s3"]
	optional.append_array(FXF.keys())
	optional.append_array(["fx_umbrella_slash", "fx_umbrella_slash_awaken", "fx_umbrella_slash_mirage"])
	optional.append_array(Vfx.STRIPS)   # docs/54 §6 事件特效帧条
	for rid in RL:
		optional.append("relic_" + rid)
	for pid in doctor.PASSIVES:
		optional.append("growth_" + pid)
	for wid in D.WEAPONS:
		optional.append("weapon_" + wid)
	for n in optional:
		tex[n] = A.tex(n)
	A.mark("tex_optional")
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
	# 所有可招募干员的贴图集（待机 / 跑步 / 攻击）：招募卡与入队后绘制都用得到（手机网页只读队长的，入队时 squad.add 补读，docs/50 §30）
	for cid in _op_tex_ids():
		var cdef: Dictionary = Character.load_def(cid)
		var csp: Dictionary = cdef.get("sprites", {})
		for kind in ["idle", "run", "attack", "skill", "hurt", "death", "move_attack"] + cdef.get("extra_sprites", []):   # move_attack：移动攻击（docs/128，character._move_swap）
			if csp.has(kind):
				var tn: String = csp[kind] if csp[kind] is String else csp[kind].tex
				if not tex.has(tn):
					tex[tn] = A.tex(tn)
		var nsa = csp.get("noshield", {}).get("art", {}) if csp.get("noshield", {}) is Dictionary else {}
		for kind in nsa:   # 无盾帧条（星熊，docs/97 H 批）：缺图时为 null，走程序回退
			if not tex.has(nsa[kind]):
				tex[nsa[kind]] = A.tex(str(nsa[kind]))
	A.mark("tex_chars")
	# 美术 V6：投射物 / 命中 / 爆炸 / 激光三段（docs/10_art_v6_spec.md）
	for n in V6_FRAMES:
		tex[n] = A.tex(n)
		# 敌人的附加帧条（休眠 / 唤醒 / 狂暴）也要白色剪影：受击闪白与轮廓光用
		if n.begins_with("e_") and tex[n] != null and not lazy_white:
			tex[n + "_white"] = A.white_of(tex[n])
	A.mark("tex_v6")
	# 敌人贴图按 data/enemies.json 加载：本体 + 白色剪影 + 脚底锚点，以及 _move / _attack / _charge / _death 变体（有图就用）
	var etex: Array = ["e_paranoia2", "e_ishar_t", "e_ishar_transform"]   # 伊莎玛拉变身形态（render/world.gd 原来首次画到才读：变身那一帧同步读图 + 算法线，卡 0.7–0.8 秒，docs/50 §10）
	for k in D.ENEMIES:
		var tn: String = D.ENEMIES[k].tex
		if not etex.has(tn):
			etex.append(tn)
	# 网页版：开局 WEB_EARLY_T 秒内刷不到的种类（中后期小怪、全部 Boss）先不加载，首次刷出时再读（ensure_enemy_tex）
	var early := _web_early_enemy_tex() if OS.has_feature("web") and demo_op == "" else {}
	for n in etex:
		if not early.is_empty() and not early.has(n):
			tex_deferred[n] = true
			continue
		_load_enemy_tex(n)

	world.build_enemy_atlas()   # 普通怪 / 精英帧条图集（docs/50 §12 B）
	A.mark("tex_enemies")
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
	fx_add.draw.connect(func(): _timed("draw_fxadd", vfx.draw_add_layer))
	add_child(fx_add)

	# 2.5D 前景视差层（镜头前的虚化海草剪影）
	fg = Node2D.new()
	fg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	fg.draw.connect(func(): _timed("draw_fg", func(): if Cfg.dof: map.draw_foreground(fg, view_size(), cam.position)))
	add_child(fg)

	merchant_light = PointLight2D.new()
	merchant_light.texture = tex.light
	merchant_light.color = Color(1.0, 0.75, 0.45)
	merchant_light.energy = 1.0
	merchant_light.height = 80.0   # 法线光照：给光一个高度，否则平面法线接不到光
	merchant_light.texture_scale = 2.2
	merchant_light.visible = false
	add_child(merchant_light)

	# 骑士入潮点的临时暖光（制作人 10-14）：圈心离灯火远、一片黑，入潮演出期间照亮沉入处，随进度淡出；纯画面（render/world.update_visuals 摆位），不进模拟、不碰 lamp 数值
	knight_light = PointLight2D.new()
	knight_light.texture = tex.light
	knight_light.color = Color(1.0, 0.86, 0.62)
	knight_light.energy = 1.0
	knight_light.height = 80.0
	knight_light.texture_scale = 3.0   # 半径约 190（贴图半径 64）
	knight_light.visible = false
	add_child(knight_light)

	lamp_light = PointLight2D.new()
	# 可读灯圈（Codex 10-24 草稿，用户 10-24 定；旧开关 render/lamp_readable 与径向渐变旧灯光 10-29 已删）：70% 半径内固定光强，
	# 圈缘降到余光 render/lamp_readable_tail，余光再延到 world.LAMP_READ_EXT 倍半径才归零（用户 10-24：圈外别全黑）；贴图覆盖的是延长后的半径
	var tail: float = Bal.v("render/lamp_readable_tail", 0.22)
	var ext: float = WorldView.LAMP_READ_EXT
	var lamp_image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for ly in 128:
		for lx in 128:
			var ld := Vector2(lx - 63.5, ly - 63.5).length() / 64.0 * ext   # 以灯半径为 1
			var la: float = lerpf(0.65, tail, smoothstep(0.70, 1.0, ld)) if ld < 1.0 else tail * (1.0 - smoothstep(1.0, ext, ld))
			lamp_image.set_pixel(lx, ly, Color(1, 1, 1, la))
	lamp_light.texture = ImageTexture.create_from_image(lamp_image)
	lamp_light.color = Color(1.0, 0.86, 0.62)
	lamp_light.energy = 1.15
	lamp_light.height = 90.0
	lamp_light.enabled = Look.dbg("nolamp") == ""   # --lookdbg=nolamp：量灯火对画面的贡献（render/look.gd）
	add_child(lamp_light)
	actor_mat = Look.make_actor_mat()
	if actor_mat != null:
		material = actor_mat

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
	post.world = true   # 观感曲线只叠在对局画面（render/look.gd）
	add_child(post)
	optical = preload("res://scripts/render/optical.gd").new()
	optical.g = self
	add_child(optical)

	var ul := CanvasLayer.new()
	ul.layer = 10
	add_child(ul)
	ui_layer = ul
	# 触屏：整个界面层（HUD / 面板 / 设置）再放大 Cfg.ui_k（手机 1.3），世界层不动；根控件尺寸见 _ui_fit
	Cfg.ui_k = Cfg.ui_scale()
	if Cfg.ui_k != 1.0:
		ul.scale = Vector2(Cfg.ui_k, Cfg.ui_k)
	_font_k()
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ul.add_child(hud)
	hud.draw.connect(func(): _timed("draw_hud", hud_view.draw))
	A.mark("nodes")
	panel_ui.build(ul)
	settings = preload("res://scripts/settings_panel.gd").new()
	settings.game_ref = self   # 触屏按键布局编辑页按本次探索的普攻方式摆攻击键
	ul.add_child(settings)
	if Cfg.ui_k != 1.0:
		_ui_fit()
	get_viewport().size_changed.connect(_ui_fit)
	Cfg.view_changed.connect(_ui_fit)      # 设置里改「界面大小」实时生效
	Cfg.view_changed.connect(_apply_zoom)  # 设置里改「战斗画面缩放」实时生效
	get_viewport().size_changed.connect(_apply_zoom)
	_apply_zoom()
	if demo_op == "":
		Sfx.cut_target = 20000.0
		Sfx.vol_target = -4.0
		vfx.show_banner("深海的潮水正在涌来……")
	RunSetup.apply_difficulty(self)   # 难度预设 / 批跑难度参数（run/run_setup.gd）
	sync_stats()
	hp = max_hp
	hp_trail = hp
	xp_need = Bal.v("xp/first", 8.0)
	mode = Mode.BALANCE if Cfg.dev_args().has("--balance") else (Mode.AUTOTEST if Cfg.dev_args().has("--autotest") else Mode.PLAY)
	if demo_op != "":
		stats.add(&"sp_gain", "mult", 3.0, "demo")   # 演示：技能充能加快，几秒就能看到一次技能
		sync_stats()
		# 精英化演出：把干员直接推进到目标阶段（精英化节点有选项时取第一个）
		var guard := 0
		while ch.elite < demo_elite and not ch.next_node().is_empty() and guard < 12:
			guard += 1
			var n: Dictionary = ch.next_node()
			var chs: Dictionary = ch.elite_choices(n) if n.get("type", "") == "elite" else {}
			ch.advance(chs.keys()[0] if not chs.is_empty() else "")
	elif trial.active:
		pass
	elif tour.demo_active():
		pass   # --tourdemo / --tipdemo=<id>：跳过开场，screens/tour.gd 第 25 帧起接管（录片 / 截图）
	elif Cfg.dev_args().has("--introshot") or Cfg.dev_args().has("--guidepages"):
		# --guidepages：只截局内指南各页（不带标题页 --introshot 的开场分镜截图与 5 秒退出）
		intro_screen.open.call_deferred(S.PAUSE if Cfg.dev_args().has("--guidefull") else S.PLAY)   # --guidefull：截完整版（暂停菜单打开的 lines + more）
	elif mode == Mode.PLAY or Cfg.dev_args().has("--openshot"):
		intro_screen.start_opening.call_deferred()
	A.mark("ready_end")
	if Cfg.mobile_fonts_slim():
		Cfg.slim_fonts(true)   # 手机网页：进局清掉标题页 / 载入页用过的字号缓存（docs/50 §30）
	if Cfg.dev_args().has("--fpsosd") and demo_op == "":
		_fps_osd_add()
	if mobile_cap():
		spawner.auto_cap = AQ_CAP
	if Cfg.guard_lowered:
		Cfg.guard_lowered = false
		# 上局护栏临时降过：这局开局恢复（手选档恢复手选的；推荐档恢复降档前的）
		Cfg.set_quality(Cfg.quality_mode if Cfg.quality_mode != "auto" else (Cfg.guard_prev if Cfg.guard_prev != "" else Cfg.quality))
		Cfg.guard_prev = ""
		if not (Cfg.mobile_web() and Cfg.mobile_knob("mobile_rscale", 0.0)):
			Cfg.set_render_scale(false)
	if mode == Mode.PLAY and demo_op == "" and not trial.active:
		_cover_begin()
	RenderingServer.frame_post_draw.connect(func():
		first_frame_ms = Time.get_ticks_msec()
		if demo_op == "":
			preload("res://scripts/core/frame_rec.gd").mark("game")   # 帧时记录（--ftrec，docs/50 §27）：对局第一帧画完
		if state != S.OPENING:
			release_entry_voices()   # 没有开场演出（测试 / Boss 演练 / 指南截图）：第一帧画完就放；有开场演出的由 intro.gd 在编队着地时放
		, CONNECT_ONE_SHOT)
	if Cfg.dev_args().has("--loadprof"):
		RenderingServer.frame_pre_draw.connect(func(): A.mark("first_frame_pre_draw"), CONNECT_ONE_SHOT)
		RenderingServer.frame_post_draw.connect(func():
			A.mark("first_frame_drawn")
			var s := "LOADPROF"
			var prev: int = A.marks[0][1]
			for m in A.marks:
				s += " %s=+%d" % [m[0], m[1] - prev]
				prev = m[1]
			s += " total=%d %s" % [A.marks[-1][1] - A.marks[0][1], A.normal_stats()]
			print(s)
			, CONNECT_ONE_SHOT)
	RunSetup.apply_test_args(self)   # 批跑 / 测试的命令行参数（run/run_setup.gd）

	trial.setup()


var demo_origin := Vector2.INF   # 场地中心（镜头固定在这里）
var demo_phases: Array = []
var demo_pi := -1
var demo_label := ""


## 镜头看着的位置：平时跟主控；图鉴演示里固定在场地中心（map.gd 按它决定画哪些地块）
## 触屏界面层放大（Cfg.ui_k）：三个根控件撑满 UI 逻辑区（视口 / ui_k）
func _ui_fit() -> void:
	# 视口变了（竖屏进局再转横屏等）或设置里改了「界面大小」：放大倍数重算（Cfg.ui_scale），不然界面层一直按旧比例排
	if ui_layer == null:
		return
	_font_k()
	var k: float = Cfg.ui_scale()
	if k == 1.0 and ui_layer.scale == Vector2.ONE:
		Cfg.ui_k = 1.0
		return   # 桌面缺省：根控件仍是 FULL_RECT 锚点，排版与原来逐像素一致
	Cfg.ui_k = k
	ui_layer.scale = Vector2(k, k)
	for c in [hud, panel, settings]:
		Cfg.ui_fill(c)


## 手机横屏正文字号放大（用户 10-13，UI.fk / UI.fs）：局内界面层在 Cfg.phone_ui() 时乘 balance.json ui/phone_font_mult；
## 离开局内（_exit_tree）恢复 1，标题页不受影响。演示局（demo_op：图鉴、精英化演出的实机小窗）不改它（UI.fk 是全局静态量）
func _font_k() -> void:
	if demo_op != "":
		return
	UI.fk = Bal.v("ui/phone_font_mult", 1.18) if Cfg.phone_ui() else 1.0


## 战斗镜头缩放（设置「战斗画面缩放」，手机横屏缺省 1.2）：只改 Camera2D.zoom，刷怪 / 索敌 / 机器人都不读视口（pickups 用的是项目设置里的固定尺寸）。
## 图鉴演示（demo_op）的镜头固定为 balance.json gallery/demo_zoom（缺省 0.68：用户 10-24「图鉴里镜头缩小一点」、10-25 再 ×0.85），不跟设置走
func _apply_zoom() -> void:
	if cam == null:
		return
	if demo_op != "":
		var dz: float = Bal.v("gallery/demo_zoom", 0.68)
		cam.zoom = Vector2(dz, dz)
		return
	var z: float = Cfg.battle_zoom() if Cfg.cam_unified() else Cfg.cam_zoom()   # 三档同一个镜头（Cfg.battle_zoom，docs/50 §32）
	cam.zoom = Vector2(z, z)


## 镜头实际看得到的世界范围（视口 / 镜头 zoom）：地面、前景、雪、光柱、黑潮圈按它铺满。
## 战斗画面缩放 < 100%（拉远）时比视口大，按视口尺寸画会在四周漏出空底（用户 10-13 改下限到 80%）
func view_size() -> Vector2:
	var z: Vector2 = cam.zoom if cam != null else Vector2.ONE
	return get_viewport_rect().size / z


## 世界坐标 → HUD 坐标（界面层放大后 = 画布变换再除以 ui_k；桌面就是画布变换本身）
func hud_ct() -> Transform2D:
	var ct := get_viewport().get_canvas_transform()
	return ct if Cfg.ui_k == 1.0 else ct.scaled(Vector2(1.0 / Cfg.ui_k, 1.0 / Cfg.ui_k))


var view_override := Vector2.INF   # 仅测试截图（autotest --knightshots 等）：镜头临时看向这里，不影响模拟
func view_center() -> Vector2:
	if view_override != Vector2.INF:
		return view_override
	return demo_origin if demo_op != "" and demo_origin != Vector2.INF else ppos


## 镜头一瞥（用户 10-14 批准：骑士入潮、10:00 寒冰重生时镜头扫向黑潮中心约 1 秒再拉回，圈心通常在屏幕外 400–600）：
## 从队长平滑移到目标（ease 秒）→ 停 hold 秒 → 平滑回到队长（ease 秒），全程只动镜头：模拟、输入、拾取回收（pickups 读 view_center）
## 都不看它，回程回到队长当前位置。HUD 在界面层不动；暂停 / 面板时镜头冻结（_glance_step 只在 PLAY / DEAD / WIN 走）。
## 目标本来就在屏幕中央区（render/camera_glance_near × 半视野以内，缺省 0.6）时跳过：对已经看得见的点再摆一下镜头只会像误抖，入潮 / 重生环本身就把视线带过去了。
## 图鉴演示、无头批跑不做；开关 balance.json render/camera_glance（0 关，对照用）。
## 指定队长（squad.swap_leader）：镜头偏移，从「原来看的位置 − 新队长位置」缓动归零；只动镜头，模拟读 ppos
var swap_off := Vector2.ZERO
var swap_t := 0.0
var swap_ease := 0.25
var glance_pos := Vector2.INF
var glance_t := 0.0
var glance_hold := 0.6
var glance_ease := 0.35


func camera_glance(pos: Vector2, hold: float = 0.6, ease_t: float = 0.35) -> void:
	if demo_op != "" or headless_batch or cam == null or Bal.vi("render/camera_glance", 1) <= 0:
		return
	var d: Vector2 = (pos - view_center()).abs()
	var half: Vector2 = view_size() * 0.5 * Bal.v("render/camera_glance_near", 0.6)
	if d.x <= half.x and d.y <= half.y:
		return
	glance_pos = pos
	glance_t = 0.0
	glance_hold = maxf(hold, 0.0)
	glance_ease = maxf(ease_t, 0.01)


## 每渲染帧（render/world.update_visuals）：rd 为真实帧间隔；只在 PLAY / DEAD / WIN 推进，暂停 / 选卡 / 面板时镜头停在原处
func glance_step(rd: float) -> void:
	if swap_off != Vector2.ZERO and (state == S.PLAY or state == S.DEAD or state == S.WIN):
		swap_t += rd
		if swap_t >= swap_ease:
			swap_off = Vector2.ZERO
	if glance_pos == Vector2.INF:
		return
	if state != S.PLAY and state != S.DEAD and state != S.WIN:
		return
	glance_t += rd
	if glance_t >= glance_ease * 2.0 + glance_hold:
		glance_pos = Vector2.INF


## 镜头实际看着的位置 = view_center 加上一瞥的偏移；只给镜头与铺满视野的地面 / 地纹 / 大道具用，玩法一律读 view_center / ppos
func cam_center() -> Vector2:
	var c: Vector2 = view_center()
	if swap_off != Vector2.ZERO:
		c += swap_off * (1.0 - smoothstep(0.0, 1.0, clampf(swap_t / swap_ease, 0.0, 1.0)))   # 切队长：镜头从原位置缓动到新队长（0.25 秒，整数像素在 world.gd 取整）
	if glance_pos == Vector2.INF:
		return c
	var k: float
	if glance_t < glance_ease:
		k = glance_t / glance_ease
	elif glance_t < glance_ease + glance_hold:
		k = 1.0
	else:
		k = 1.0 - (glance_t - glance_ease - glance_hold) / glance_ease
	return c.lerp(glance_pos, smoothstep(0.0, 1.0, clampf(k, 0.0, 1.0)))


# =====================================================================
# 主循环
# =====================================================================
## 局中不再按帧率自动降画质（10-27 用户「自动降低特效之类的是不是可以关掉，一般游戏里面都不会这么做吧」，docs/50 §36）：
## 画质只在启动时按设备定一个推荐档（Cfg._guess_quality，设置里「推荐」），之后不变；玩家手选永远优先。原来的逐级降（10-25 docs/50 §28）已删。
## 帧率上限（手机 30、网页开局测一次定 60 / 30）不是降特效，照旧
## 网页内存护栏（10-26 用户「重点是要让所有机型和网页版都不会崩溃」，docs/50 §30）：手机网页每 MG_EVERY 秒估一次内存
## （引擎显存统计 + 网页音频样本解码估算），超线时按下面 10-27 的三步处理。
## 音频样本没法从脚本注销（引擎没开放 unregister），所以手机上战斗乐分轨不预先解码（sfx.warm_begin）。
## 局中后期新怪 / 新音效越积越多时兜底，不等 WebKit 杀页。纯画面 / 声音缓存，不碰对局
## 10-27 改（docs/50 §36 / §39）：只作防崩的最后手段——阈值 MG_BUDGET_MB 520（真机 iPhone 453–533 没崩、766 才崩）；超线先只做不改画面的事（清字形缓存、
## 立刻释放不在场的白剪影 / 敌人帧条），下一次（MG_EVERY 秒后）仍超才降画质「低」（提示玩家），超过 MG_RSCALE_MB 600 才分辨率缩放（会糊）。手选档与推荐档同一阈值
const MG_EVERY := 5.0
const MG_BUDGET_MB := 520.0   # 10-27 真机 iPhone：453 / 471–533 MB 都没崩、766 才崩（docs/50 §39）
const MG_RSCALE_MB := 600.0   # 分辨率缩放（会糊）只在超过这个数时才开
var _mg_t := 0.0
var _mg_stage := 0   # 本局连续超线的次数：1 只清缓存、2 降画质、3 分辨率缩放；回到线下清零

func _mem_guard(delta: float) -> void:
	if not (Cfg.mobile_web() or Cfg.dev_args().has("--memguard")):
		return
	_mg_t += delta
	if _mg_t < MG_EVERY:
		return
	_mg_t = 0.0
	var vid: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var aud: float = Sfx.sample_mem_mb()
	var budget: float = MG_BUDGET_MB
	for a in Cfg.dev_args():
		if a.begins_with("--memguard="):
			budget = float(a.substr(11))
	if vid + aud <= budget:
		_mg_stage = 0
		return
	_mg_stage += 1
	var step := "清缓存"
	Cfg.slim_fonts(true)   # 字形缓存清掉重建（按需栅格化，卡一下；docs/50 §30 字体缓存能到 60 MB）
	_white_release(0.0, true)   # 不在场的白剪影 / 敌人帧条立刻释放（平时要等 20 / 60 秒）
	if _mg_stage >= 2 and Cfg.quality != "low":
		Cfg.guard_prev = Cfg.quality
		Cfg.set_quality("low")
		Cfg.guard_lowered = true
		quality_note = "内存紧张，本局已临时降低画质"
		quality_note_t = 5.0
		step = "低画质"
	elif _mg_stage >= 3 and not Cfg.render_scaled and vid + aud > MG_RSCALE_MB + (budget - MG_BUDGET_MB):
		Cfg.set_render_scale(true)
		Cfg.guard_lowered = true
		step = "分辨率缩放"
	perf_rep.guard_hit = true   # 性能报告：任一阶段触发都记（core/perf_report.gd）
	perf_rep.guard_stage = maxi(perf_rep.guard_stage, 3 if step == "分辨率缩放" else (2 if step == "低画质" else 1))
	perf_rep.tag("护栏" + step)
	if step != "" and not Cfg.dev_args().is_empty():
		print("PF MEMGUARD vid=%.0fMB audio=%.0fMB -> %s t=%.0f" % [vid, aud, step, t])


const AQ_CAP := 65   # 手机网页开局就开的同屏上限（mobile_cap；帧率会话 10-26 定的低配档参数）

func _auto_quality(delta: float) -> void:
	quality_note_t = maxf(0.0, quality_note_t - delta)
	var now := Time.get_ticks_usec()
	var rd: float = (now - _aq_us) / 1e6 if _aq_us > 0 else 0.0   # 真实帧间隔（--fixed-fps 测量时 delta 是定值，看不出掉帧）
	_aq_us = now
	if demo_op != "" or state != S.PLAY or t < 1.0 or (rt_from >= 0.0 and not realtime) or rd > 0.25 or rd <= 0.0:   # 切窗口 / 读盘那种单次长停顿不算
		return
	if OS.has_feature("web") and Cfg.max_fps == 0 and not Cfg.fps_probed and ((mode == Mode.PLAY and Cfg.dev_args().is_empty()) or Cfg.dev_args().has("--autoq")):
		_fps_probe(rd)   # 网页帧率自动：开局测一次定 60 还是 30（帧率上限，不改画质）


## 网页帧率自动（10-25 用户定）：先按 60 帧跑，开局 AQ_FPS_T 秒的平均帧率 ≥ 50 就保持 60，否则本次启动锁 30（Engine.max_fps = 30）；
## 只测一次，不在两者之间来回跳。桌面不锁。逻辑按 PlayClock 固定步长，与渲染帧率无关
const AQ_FPS_T := 4.0
var _fps_win := Vector2.ZERO

func _fps_probe(rd: float) -> void:
	_fps_win += Vector2(rd, 1.0)
	if _fps_win.x < AQ_FPS_T:
		return
	var avg_ms: float = _fps_win.x / _fps_win.y * 1000.0
	Cfg.fps_probed = true
	if avg_ms > 1000.0 / 50.0:
		Cfg.fps_lock30 = true
		Engine.max_fps = Cfg.effective_max_fps()
	if not Cfg.dev_args().is_empty():
		print("AUTOFPS avg=%.1fms lock30=%s t=%.1f" % [avg_ms, Cfg.fps_lock30, t])


## --fpsosd（仅测试）：左上角显示实际帧率 / 帧率上限 / 自动降档级（录网页锁 30 的证明片用；独立一层，不走 HUD 缓存）
func _fps_osd_add() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	var lb := Label.new()
	lb.position = Vector2(8, 6)
	lb.add_theme_font_size_override("font_size", 18)
	lb.add_theme_color_override("font_color", Color(0.6, 1.0, 0.95))
	lb.add_theme_color_override("font_outline_color", Color.BLACK)
	lb.add_theme_constant_override("outline_size", 4)
	layer.add_child(lb)
	var tm := Timer.new()
	tm.wait_time = 0.25
	tm.autostart = true
	tm.timeout.connect(func(): lb.text = "FPS %.0f   上限 %d%s   画质 %s   %d:%02d" % [Engine.get_frames_per_second(), Engine.max_fps,
		"（自动锁 30）" if Cfg.fps_lock30 else ("（自动 · 测量中）" if Cfg.max_fps == 0 and not Cfg.fps_probed and OS.has_feature("web") else ""),
		Cfg.quality, int(t) / 60, int(t) % 60])
	layer.add_child(tm)


## 手机网页静止界面降帧（10-27 用户「手机发烫」，docs/50 §33）：暂停 / 选卡 / 商店 / 结算这些画面不跑模拟，照 30 帧整屏重画是空耗电。
## 进入这类画面 STATIC_DELAY 秒后（入场动效走完）降到 render/static_fps（缺省 20），回对局立刻恢复。只在帧率设置为「自动」时（手选 60 / 30 照玩家的）；
## 真人局才开（批跑不限帧，测试 --powerseq 照玩家）；--bal=web/mobile_static_fps=0 退回
var power_cap := false
const STATIC_DELAY := 0.5

func _static_fps() -> void:
	if not (Cfg.mobile_web() and Cfg.max_fps == 0 and (mode == Mode.PLAY or power_cap) and Cfg.mobile_knob("mobile_static_fps", 1.0)):
		return
	var still: bool = state != S.PLAY and state != S.INTRO and state != S.OPENING and state != S.SHOW and state_age > STATIC_DELAY and not wheel.is_open
	var want: int = int(Bal.v("render/static_fps", 20.0)) if still else Cfg.effective_max_fps()
	if Engine.max_fps != want:
		Engine.max_fps = want


## 手机网页开局就开同屏上限 65（10-26 晚：满屏帧时约 −21%，用户批过存活上限做软限制；合并补偿照 §26.13）。真人局才开，测试 / 机器人局不变
func mobile_cap() -> bool:
	return Cfg.mobile_web() and Cfg.mobile_knob("mobile_cap", 1.0) and (mode == Mode.PLAY or Cfg.dev_args().has("--mobilecap"))


func _process(delta: float) -> void:
	UM.advance(delta)   # 界面动效时钟（真实帧间隔，不乘对局倍速；scripts/ui_motion.gd）
	_pm("engine")   # 上一帧结束到这一帧开始：引擎自身、_draw 回调、其他节点（只在 --prof 下记）
	tour.update(delta)   # 聚光框引导 / 到点小提示：真实帧间隔（screens/tour.gd）
	pick.update(delta)
	wheel.update(delta)   # 指挥圆盘：真实帧间隔（悬停 / 松开判定 / 测试计划）
	var dt: float = min(delta, 0.05)
	var simulated_dt := 0.0
	if state != _last_state:
		_last_state = state
		if not trial.active:
			telemetry.on_state(state)   # 进入胜 / 负时把这一局写进本地记录（docs/40）
			if state == S.WIN or state == S.DEAD:
				RunEnd.settle(self)   # 局外结算：寻访凭证、生机细胞、最佳成绩、云存档（run/run_end.gd）
				perf_rep.finish("win" if state == S.WIN else "dead")
		state_age = 0.0
		ui_skip = false
		res_sel = 0
	else:
		state_age += delta
	if state == S.WIN or state == S.DEAD:
		settlement.tick(delta)   # Read-only result model; recruitment now opens explicitly from the footer.
	if demo_op == "":
		Pad.context = "play" if state == S.PLAY else "game_menu"   # 图鉴演示（SubViewport 里）不抢手柄映射：图鉴仍按标题页翻译 LB / RB / Ⓐ
	if mode != Mode.PLAY:
		_pm("")
		autotest_sys.step()
		_pm("autotest")
		dt = (minf(delta, 0.05) if realtime else bal_dt) if mode == Mode.BALANCE else 0.05
	if ult != null:
		ult.fx_tick()   # 终结技冲击帧：恢复速度那一刻的音效（真实时间）
	dt *= tdil.factor(mode == Mode.PLAY or realtime or playclock_test)   # 时间缩放只读这一处（run/time_dilation.gd：圆盘 play 类、终结技 fx 类，取最小）
	# 图鉴演示 / 精英化演出不顿帧：演示里攻击不停，每下重击都冻 0.05–0.1 秒，走路看起来一卡一卡（2026-09-26 用户反馈）
	_auto_quality(delta)
	_static_fps()
	if OS.has_feature("web") and state != S.PLAY and state != S.OPENING and state != S.INTRO and state_age > 0.3 and Sfx.warm_pending():
		Sfx.warm_step(20000)   # 静止界面里解码下一批配乐（sfx._queue_next，docs/50 §40）：一帧至少一句，对局画面里不解码
	if cam != null and not optical_lo and demo_op == "" and demo_enemy == "" and Cfg.cam_unified():
		var bz: float = Cfg.battle_zoom() * cam_fx.punch()
		if absf(cam.zoom.x - bz) > 0.0001:
			cam.zoom = Vector2(bz, bz)   # 低档也每帧对齐（中 / 高由光学 _lo_step 每帧算）：漏掉尺寸变化通知时不会停在旧镜头（10-27 用户「低中镜头还是不一样」）
	_mem_guard(delta)
	perf_rep.tick(delta)   # 性能报告：帧时分桶 / 最低 1 秒帧率 / 内存与敌人峰值（只加计数）
	_white_release(delta)
	if victory.active and state == S.PLAY:
		simulated_dt = victory.step(minf(delta, 0.05))   # 最终 Boss 击破演出按慢动作缩放画面步长（run/victory_flow.gd）
	elif hitstop > 0.0 and (mode == Mode.PLAY or playclock_test) and Cfg.hitstop and demo_op == "":
		hitstop -= delta
	elif state == S.PLAY:
		if (mode != Mode.PLAY and not playclock_test) or demo_op != "":
			_update(dt)
			simulated_dt += dt
		else:
			for step_dt in PlayClock.steps(dt):
				if state != S.PLAY or victory.active or (hitstop > 0.0 and Cfg.hitstop):
					break
				_update(step_dt)
				simulated_dt += step_dt
		if mode == Mode.BALANCE and not realtime:
			# 平衡测试：每帧多跑几步模拟，绕过无界面模式的帧率上限
			for i in 7:
				if state != S.PLAY:
					break
				_pm("")
				autotest_sys.step()
				_pm("autotest")
				if state == S.PLAY:
					_update(dt)
					simulated_dt += dt
	if not panel.visible and state != S.SHOW and state != S.PAUSE and state != S.INTRO:
		banner_t -= delta   # 选卡 / 商人面板 / 精英化演出 / 暂停 / 指南时横幅暂停，关掉后再显示（不然会透过压暗带叠在面板标题下）
	_pm("")
	world.update_visuals(simulated_dt if state == S.PLAY else 0.0)
	defeat_outro.step(delta)   # 倒下过渡里只推进画面：最后一击定格 + 慢放、队友化光尘（run/defeat_outro.gd）
	_pm("visuals")
	music_dir.update(delta)
	boss_intro.update(delta)
	panel_ui.animate_cards(delta)
	if state == S.SHOW:
		show_t += delta
	if state == S.INTRO:
		intro_t += delta
	# 无界面批跑什么都不显示：不重绘世界 / 特效 / 前景 / HUD（一局省三成多耗时；docs/36 验证过结果逐字节不变）
	if headless_batch and world.dc_check:
		queue_redraw()   # --dccheck（快检冒烟）：无头也画世界层，敌人画法缓存自检才跑得到（docs/50 §9.9）
	if not headless_batch:
		queue_redraw()
		fx_add.queue_redraw()
		fg.queue_redraw()
		dof_layer.visible = Cfg.dof and not optical_on   # 光学开时景深由光学 pass 取代（原来这里开、optical.gd 再关，一帧翻两次）
		fg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if optical_on else CanvasItem.TEXTURE_FILTER_LINEAR   # 前景剪影：光学下像素风（map.draw_foreground）
		hud.queue_redraw()
	world.present_step()   # 表现事件步骤（Boss 换幕 / 倒下演出；docs/101 B3）：每帧一次，在本帧绘制之前，无头也走
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
			if trial.active:
				trial.retry()
			get_tree().reload_current_scene()
		"title":
			get_tree().change_scene_to_file("res://main.tscn")
		"stats":
			run_stats.open_for_run()


## 指南页的输入放在 _input：先于 GUI 控件处理，左键（或面板右半 / 下一页按钮）下一页，右键 / 面板左半 / 上一页按钮上一页，页码点可直接点
func _input(event: InputEvent) -> void:
	if victory.active:
		# 胜利演出（慢动作 + 收尾）：任意按键 / 点击 / 触屏跳过，直接进结算；这一下不传给结算（docs/62 §3.21c）
		if mode == Mode.PLAY and ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)):
			victory.skip()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and event.relative.length() > 6.0:
		kb_nav = false
	if settings.visible:
		return
	# Result owns terminal input before stale combat touch regions can consume it.
	if settlement.active() and not run_stats.open and not run_log.open and not headhunt.open and (state == S.WIN or state_age >= HudView.DEATH_T + 0.35):
		settlement.input(event)
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	if _motion_skip(event):
		get_viewport().set_input_as_handled()
		return
	if pick.input(event):
		get_viewport().set_input_as_handled()
		return
	if wheel.input(event):   # 指挥圆盘打开时吞掉按键 / 点选（移动是轮询的，不受影响）
		get_viewport().set_input_as_handled()
		return
	if state == S.INTRO and tour.active:   # 聚光框引导：点击 / 按键翻步，Esc / 「跳过引导」结束
		if tour.input(event):
			get_viewport().set_input_as_handled()
		return
	if touch.handle(event):
		get_viewport().set_input_as_handled()
		return
	if state != S.INTRO:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match Pad.kc(event):
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


## 招牌动效进行中（docs/62 §2.5）：任意按键 / 点击 / 触屏 = 立即跳到终态，不算操作，下一次输入才算。
## 选卡（升级发牌翻面 / 藏品光柱 / 招募落地）任意键都跳；暂停表盘、失败结算只有点击 / 触屏 / 确认键跳，Esc 与字母快捷键照常（暂停里 Esc = 继续）。
## 商人不拦（从第一帧起就能买）。手柄的 Ⓐ 由 Pad 注入成 Enter，走按键这一支
func _motion_skip(event: InputEvent) -> bool:
	var press: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT))
	if not press:
		return false
	if _skip_frame == Engine.get_process_frames():
		return true
	if state == S.CHOICE and panel_ui.motion.running():
		panel_ui.motion.skip()
	elif (state == S.PAUSE or state == S.DEAD) and result_screen.motion_running():
		if event is InputEventKey and not (Pad.kc(event) in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
			return false
		ui_skip = true
	else:
		return false
	_skip_frame = Engine.get_process_frames()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if victory.active:
		return
	if settings.visible:
		return
	if state == S.OPENING:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			intro_screen.end_opening()
		return
	# 倒下过渡中（hud.DEATH_T 秒）：任意键 / 点击直接跳到结算，这次输入不传给结算按钮
	if state == S.DEAD and state_age < HudView.DEATH_T:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			state_age = HudView.DEATH_T
			get_viewport().set_input_as_handled()
		return
	# 跳过 / 播完过渡后 0.35 秒（结算面板淡入期间）再挡一下输入：倒下时习惯连按，第二下别落到还在淡入的结算按钮上（架构建议）
	if state == S.DEAD and state_age < HudView.DEATH_T + 0.35:
		return
	# 寻访面板打开时独占输入（docs/109 §12）
	if (state == S.DEAD or state == S.WIN) and headhunt.open and not run_stats.open:
		if headhunt.input(event):
			get_viewport().set_input_as_handled()
		return
	# 作战记录打开时独占输入（docs/77）：键盘 / 手柄（Pad 翻成按键）/ 鼠标与触屏点按 / 滚轮
	if (state == S.DEAD or state == S.WIN) and run_stats.open:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				run_stats.click(event.position / Cfg.ui_k)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				run_stats.wheel(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				run_stats.wheel(1)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			if run_stats.key(Pad.kc(event)) and is_inside_tree():
				get_viewport().set_input_as_handled()
		return
	# 对局记录（结算「对局记录」）打开时独占输入；从它进的作战记录走上面那段，关掉后回到这里
	if (state == S.DEAD or state == S.WIN) and run_log.open:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				run_log.click(event.position / Cfg.ui_k)
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				run_log.wheel(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				run_log.wheel(1)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			if run_log.key(Pad.kc(event)) and is_inside_tree():
				get_viewport().set_input_as_handled()
		return
	if settlement.active():
		settlement.input(event)
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp0: Vector2 = event.position / Cfg.ui_k   # 界面层放大：视口坐标 → UI 坐标（桌面 ui_k = 1）
		if state == S.PAUSE or state == S.DEAD or state == S.WIN:
			for b in result_btns:
				if b[0].has_point(mp0):
					Sfx.play("ui_ok")
					_do_action(b[1])
					return
		if state == S.PLAY and speed_btn.has_point(mp0):
			PlayClock.cycle()
			return
		if state == S.PLAY and pause_btn.has_area() and pause_btn.has_point(mp0):
			Sfx.play("ui_ok", -4.0)
			state = S.PAUSE
			return
		if state == S.PLAY and doctor.click_skill(event.position):   # 左键点场地放选落点技能（乌尔比安 S3，10-26）；放不了时点击照旧
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.device == Pad.SYNTH_DEVICE and state_age < 0.35 and state != S.PLAY:
		return
	if state == S.SHOW:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			show_screen.close()
		return
	if state == S.INTRO:
		return  # 指南的输入在 _input() 里处理（先于 GUI，不会被任何控件吞掉）
	if ult != null and event is InputEventKey and not event.pressed and PlayKeys.action_of(Pad.kc(event), true) == "ult":
		ult.release_q()   # 终结技：松开 Q 放出（按住最多再慢 1 秒）
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = Pad.kc(event)
	if _nav_key(k):
		if is_inside_tree():   # 重新开始 / 回到标题已经换了场景：本节点离开场景树，get_viewport() 为 null
			get_viewport().set_input_as_handled()
		return
	if (k == KEY_SPACE or k == KEY_SHIFT or k == KEY_K) and state == S.PLAY:
		_try_dash()
		get_viewport().set_input_as_handled()
		return
	# 终结技 Q / 连携技 E（docs/198 §2.4，ult/on）：取代下面的手动技能路由；J 只在手动普攻时是攻击
	var act: String = PlayKeys.action_of(k, true) if ult != null else ""
	if (act == "ult" or act == "combo" or act == "attack") and state == S.PLAY:
		if act != "attack" and (ult.press_q() if act == "ult" else ult.press_e()):
			get_viewport().set_input_as_handled()
		return
	# 手动技能：Q / E（手柄 Ⓐ / Ⓨ 注入 Q）；没开手动普攻时 J 仍兼作手动技能键，开了 J 让给攻击（契约 v2.5，攻击键由 doctor 每帧直接读）
	if (k == KEY_Q or k == KEY_E or (k == KEY_J and not doctor.get("manual_attack"))) and state == S.PLAY:
		# 唯一的手动技能入口：路由到角色已解锁的 manual 技能（三自动角色无动作）
		if doctor.try_manual_skill():
			get_viewport().set_input_as_handled()
		return
	if k == KEY_V and state == S.PLAY:
		PlayClock.cycle()
		return
	if k == KEY_F8 and state == S.PLAY and (OS.is_debug_build() or Cfg.build_audience() == "internal"):   # ④ 移动粘滞试手感（用户 10-24）：只在对内包 / 调试版
		sticky_on = not sticky_on
		_mv_s = Vector2.ZERO
		vfx.show_banner("移动粘滞（试验）：%s · F8 切换" % ("开" if sticky_on else "关"), 2)
		get_viewport().set_input_as_handled()
		return
	if k == KEY_F and state == S.PLAY:   # 指挥模式（docs/114 §13）：F / 手柄 LB / 触屏「指挥」键打开指挥圆盘（按住选、松开确认；轻点则点选）
		wheel.open(event)
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
		elif (state == S.DEAD or state == S.WIN) and not trial.active:
			Sfx.play("ui_ok", -6.0)
			run_stats.open_for_run()   # 结算 → 作战记录（docs/77）
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
		_do_action("title")
	elif k == KEY_R and (state == S.DEAD or state == S.WIN or state == S.PAUSE):
		_do_action("restart")
	elif state == S.SHOP:
		if k >= KEY_1 and k <= KEY_5:
			shop_sys.buy(k - KEY_1)
		elif k == KEY_F:
			shop_sys.refresh()
		elif k == KEY_ESCAPE or k == KEY_E:
			shop_sys.close()
	elif state == S.CHOICE and k >= KEY_1 and k <= KEY_9:
		# 数字键 1..n 对应第 n 张卡（藏品 / Boss 奖励可能多于 3 张，docs/38 B0 第 10 项）
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
## 0.18 秒冲出 dash/dist 像素（10-13 用户：默认距离缩短，126 → 107），全程无敌；冷却 dash/cd 秒。残影由干员的动态模糊（character.gd ghosts）自动产生。
## 机动卡（docs/83）：冷却 × 属性 dash_cd、距离 × 属性 dash_dist（冲刺时间不变、速度变快，无敌时间不变）、可储存次数 = 属性 dash_charges。
## dash_cd = 还欠的冷却秒数：每冲一次 + 一次冷却，随时间减少；dash_cd ≤ 冷却 × (次数 − 1) 时可以再冲。只有 1 次时等同旧的「冷却归零才能冲」
const DASH_TIME := 0.18
var dash_t := 0.0
var leader_still_t := 0.0   # 响应动作（docs/118）：队长连续站定的秒数（移动 / 冲刺 / 被定身清零）；条件 still >= 秒 读它
var leader_skill_n := 0     # 响应动作：队长自己的技能出手次数（trig.on_leader_skill 看它增长）
var leader_skill_i := -1    # 最近一次出手的技能序号
var dash_cd := 0.0
var dash_dir := Vector2.RIGHT
var last_mv := Vector2.ZERO
var move_in := Vector2.ZERO   # 这一帧的移动输入（僵直时也记）：冲刺方向用


## 一次冲刺的冷却（秒）
func dash_cd_full() -> float:
	return Bal.v("dash/cd", 1.2) * (stats.value(&"dash_cd") if stats != null and stats.has_stat(&"dash_cd") else 1.0)


## 一次冲刺的距离（像素）
func dash_dist() -> float:
	return Bal.v("dash/dist", 107.0) * (stats.value(&"dash_dist") if stats != null and stats.has_stat(&"dash_dist") else 1.0)


## 可储存的冲刺次数
func dash_max() -> int:
	return maxi(1, int(round(stats.value(&"dash_charges")))) if stats != null and stats.has_stat(&"dash_charges") else 1


## 现在能不能冲（不看是否正在冲刺）
func dash_ready() -> bool:
	return dash_cd <= dash_cd_full() * float(dash_max() - 1) + 0.0001 if dash_max() > 1 else dash_cd <= 0.0


## 现在可用的冲刺次数
func dash_left() -> int:
	return clampi(dash_max() - int(ceil(dash_cd / maxf(0.01, dash_cd_full()) - 0.0001)), 0, dash_max())


## 下一次冲刺的冷却进度 0–1（界面画冷却环 / 冷却条；可冲时为 1）
func dash_frac() -> float:
	if dash_ready():
		return 1.0
	var full: float = maxf(0.01, dash_cd_full())
	return clampf(1.0 - (dash_cd - full * float(dash_max() - 1)) / full, 0.0, 1.0)


## 冲刺任何时候都能按（docs/38 §1.11「永不硬控」）：只看冷却、是否正在冲刺、是否在局内；僵直时也能冲，方向取按住的方向
## 指挥键（键盘 / 手柄 / 触屏共用）
func toggle_command() -> void:
	if state != S.PLAY:
		return
	if squad.cycle_stance():
		Sfx.play("ui_ok", -8.0)
	elif Squad.cmd_on():
		vfx.add_text(ppos + Vector2(0, -70), "作战时限未恢复", UI.SUB, 14)   # 突击耐力（玩家可见名「作战时限」，10-22 定）没回到 command/min_start


## HUD 按「对局进行中」画的块（触屏按键、指挥状态）在聚光框引导期间（state INTRO、tour.active）也要画出来，让方框框得到
func hud_live() -> bool:
	return state == S.PLAY or tour.active


func _try_dash() -> void:
	if not dash_ready() or dash_t > 0.0 or state != S.PLAY or (ult != null and ult.playing()):
		return
	dash_dir = (move_in if move_in != Vector2.ZERO else Vector2(facing, 0)).normalized()
	dash_t = DASH_TIME
	dash_cd += dash_cd_full()
	rfx.on_dash(ppos, dash_dir, dash_dist())   # 舞者手链（docs/203）：冲刺后闪避 + 路线伤害
	dash_used = true
	telemetry.dashes += 1   # 作战记录（docs/77）
	combat.on_dash_break()   # 控制遥测：正在冻结就记一次冲刺挣脱
	root_t = 0.0   # 冲刺挣脱冻结 / 束缚
	apop = maxf(0.0, apop - Bal.v("enemy/apop_dash", 40.0))   # 冲刺清掉一部分凋亡损伤
	invuln = maxf(invuln, DASH_TIME + 0.05)
	fx.append({"kind": "ring", "pos": ppos, "r": 36.0, "life": 0.25, "max": 0.25, "col": ch.col() if ch != null else UI.CYAN})
	Sfx.play("dodge", -6.0, 1.2, 0.05)


func _update(dt: float) -> void:
	_pm("")
	upd_n += 1
	if int(t + dt) != int(t):
		GalleryProgress.observe(self)
	t += dt
	if demo_enemy != "":
		enemy_demo.step(dt)
		return
	if mode == Mode.PLAY and not trial.active:
		telemetry.tick(dt)   # 真实玩家局的整局指标；机器人局由 autotest 按原节奏驱动
	sync_stats()
	var mv := Vector2(
		float(Pad.key_down(KEY_D) or Pad.key_down(KEY_RIGHT)) - float(Pad.key_down(KEY_A) or Pad.key_down(KEY_LEFT)),
		float(Pad.key_down(KEY_S) or Pad.key_down(KEY_DOWN)) - float(Pad.key_down(KEY_W) or Pad.key_down(KEY_UP)))
	if demo_op != "":
		mv = demo_sys.wander()
	elif mode == Mode.BALANCE:
		mv = bot.move(dt) if bot != null else autotest_sys.bot_move()
	elif touch.active and touch.move_vec() != Vector2.ZERO:
		mv = touch.move_vec()
	elif Pad.move_vec() != Vector2.ZERO:
		mv = Pad.move_vec()   # 手柄左摇杆（模拟量）/ 十字键
	elif mode != Mode.PLAY:
		mv = Vector2.from_angle(t * 0.4)
	if ult_bench != null:
		mv = Vector2.ZERO   # 终结技对齐测试（run/ult_bench.gd）：队长站在场景中心不动
	move_in = mv
	if mode == Mode.BALANCE and autotest_sys.want_dash:
		autotest_sys.want_dash = false
		_try_dash()   # 普通机器人出圈回圈时冲刺（autotest.bot_move）
	if pstun > 0.0 or root_t > 0.0 or (ult != null and ult.playing()):
		mv = Vector2.ZERO   # 终结技播放中（ult.playing）：移动输入只给瞄准用（move_in 保留），队长原地不动
	moving = mv != Vector2.ZERO
	leader_still_t = 0.0 if moving or dash_t > 0.0 or pstun > 0.0 or root_t > 0.0 else leader_still_t + dt
	if moving:
		mv = mv.normalized() * minf(mv.length(), 1.0)   # 键盘斜向归一；手柄半推 = 慢走
		walk_t += dt * 12.0
		if mv.x != 0.0 and swing_face <= 0.0:
			facing = sign(mv.x)
	# 溟痕：陷在里面移动速度 -45%；Boss 战里僵直 / 攻速减缓换成的减速也乘在这里，Boss 存活期间合计不低于 0.7（combat.move_mult）
	var mspd: float = speed * combat.move_mult((1.0 - 0.45 * in_mire) * rej_slow * combat.ctrl_slow())
	if sticky_on or Bal.v("feel/move_sticky", 0.0) > 0.0:
		if fire_slow_t > 0.0:
			fire_slow_t -= dt
			mspd *= 1.0 - Bal.v("feel/fire_slow", 0.25)
		_mv_s = _mv_s.move_toward(mv, dt / maxf(0.01, Bal.v("feel/accel_t", 0.06)))
		if pstun > 0.0 or root_t > 0.0:
			_mv_s = Vector2.ZERO
		mv = _mv_s
	pvel = mv * mspd
	ppos += mv * mspd * dt
	# 冲刺：主控沿冲刺方向高速位移，期间无敌；僵直时也能冲，冲刺距离不受减速影响
	dash_cd = maxf(0.0, dash_cd - dt)
	var dash_end := false
	if dash_t > 0.0:
		dash_t -= dt
		var dsp: float = dash_dist() / DASH_TIME
		ppos += dash_dir * dsp * dt
		pvel = dash_dir * dsp
		invuln = maxf(invuln, 0.05)
		dash_end = dash_t <= 0.0
	last_mv = mv if moving else last_mv
	if tex.get("prop_pillar") != null:
		var pre := ppos
		ppos = map.push_out(ppos, 12.0)
		# 地形阻挡（terrain/dash_stop）：冲刺撞上景物底座即停（原来沿椭圆边滑过去，看着像穿过）；无敌照常走完剩下的冲刺时间
		if dash_t > 0.0 and map.tb_dash and pre.distance_squared_to(ppos) > map.tb_dash_px * map.tb_dash_px and map.blocks():
			invuln = maxf(invuln, dash_t + 0.05)
			dash_t = 0.0
			map.tb_log.dash += 1
			dash_end = true
	if dash_end:
		vfx.ground_dust(ppos, 20.0, 7)
		vfx.impact_pause(0.022)
	swing_face -= dt

	var rg: float = combat.regen_per_sec() * dt
	if rg > 0.0 and hp > 0.0:
		# 遥测（docs/74 §6）：主控自带回复 + 博士「自愈」+ regen_pct 藏品，只记实际回进去的量；走 heal()（补侵蚀创口减疗）
		combat.heal(rg, "自身回复", "", combat.HEAL_PRESCALED)
	if lamp <= 0.0:
		combat.lose_hp(3.0 * dt, "dark")
		hurt_flash = max(hurt_flash, 0.05)
	combat.update_zone(dt)
	if shield_max > 0 and shield < shield_max:
		shield_cd -= dt
		if shield_cd <= 0.0:
			shield += 1
			shield_cd = shield_every
			rfx.on_shield_gain()   # 嵌体甲片（docs/203）：生成护盾时冲击
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
	elif not trial.active and not sandbox:
		spawner.update(dt)
	_pm("spawn")
	enemies_sys.build_grid()
	_pm("grid")
	var nfx0: int = fx.size()
	enemies_sys.update(dt)
	vfx.mark_enemy_fx(nfx0)   # 这一段新加的特效都来自敌人：后期降噪不调淡它们（docs/48 全局 ③）
	_pm("enemies")
	squad.update(dt)
	_pm("squad")
	weapons_sys.update(dt)   # 支援无人机：跟随主控，与编队里有谁无关
	knight.update(dt)
	touch.update(dt)
	weapons_sys.update_bullets(dt)
	_pm("bullets")
	var nfx1: int = fx.size()
	shots.step(dt)   # 抛物 → 敌弹 → 冲击环（docs/101 B7 ④）
	tele.update_warns(dt)
	vfx.mark_enemy_fx(nfx1)
	_pm("ebullets")
	enemies_sys.update_status(dt)
	rfx.tick(dt)
	_pm("relic")
	if not trial.active and not sandbox:
		endg.update(dt)
		endg.tick_final_warning()
		beacon_sys.update(dt)
		knight.tick_final()   # 结局二：9:00 起走向黑潮中心、到达入潮消失（docs/18 §1）
		if demo_op == "":
			shop_sys.update(dt)
		pickups.update(dt)
	elif trial.active:
		trial.maintain()
	_pm("misc")
	vfx.update(dt)
	lvup_delay -= dt   # 升级演出延迟（模拟：决定选卡面板何时弹出；docs/101 B3 从 vfx.update 移来，顺序不变）
	_pm("fx")
	_cleanup()
	_pm("cleanup")

	if not horde_log.is_empty():
		var hl0: Dictionary = horde_log[horde_log.size() - 1]
		if t - hl0.t < 20.0:
			hl0.minhp = minf(hl0.minhp, hp)
	if mode == Mode.BALANCE and Cfg.dev_args().has("--nodeath"):
		if hp <= 0.0:
			floor_hits += 1   # 本该死掉的次数：不死模式下的生存压力指标（docs/27 §6）
			floor_times.append(int(t))
		hp = maxf(hp, max_hp * 0.5)
	if not meta_once_heal.is_empty() and hp > 0.0 and hp < max_hp * float(meta_once_heal[0]):
		# 认知塑造「为了生存」：每次探索一次，生命低于阈值时立即回复
		combat.heal(max_hp * float(meta_once_heal[1]), "认知塑造")
		meta_once_heal = []
		vfx.show_banner("为了生存 —— 队长回复 30% 最大生命")
	if hp <= 0.0 and squad.prevent_death():
		hp = 1.0   # 幽灵鲨「求生之渴」：主控生命不会低于 1
	if hp <= 0.0 and rfx.rule("last_stand") > 0:
		# 认知塑造「生存本能」末节：每局一次，致命伤后保留 1 点生命并 meta/last_stand_inv 秒不受伤害
		rfx.use_rule("last_stand")
		hp = 1.0
		invuln = maxf(invuln, Bal.v("meta/last_stand_inv", 1.5))
		fx.append({"kind": "rays", "pos": ppos, "life": 0.9, "max": 0.9, "col": Color(0.8, 0.95, 1.0)})
		vfx.show_banner("生存本能 —— 队长保留 1 点生命")
		Sfx.play("levelup", 0.0, 0.7)
	if hp <= 0.0 and rfx.rule("revive") > 0:
		# 认知塑造「绝处逢生」（调度线末节）：每局一次，倒下时以 meta/revive_hp 最大生命复活，meta/revive_inv 秒不受伤害
		rfx.use_rule("revive")
		hp = max_hp * Bal.v("meta/revive_hp", 0.5)
		invuln = maxf(invuln, Bal.v("meta/revive_inv", 3.0))
		fx.append({"kind": "rays", "pos": ppos, "life": 1.1, "max": 1.1, "col": Color(1.0, 0.9, 0.6)})
		vfx.show_banner("绝处逢生 —— 队长复活")
		Sfx.play("levelup", 0.0, 0.6)
	if hp <= 0.0 and not rfx.on_death():
		hp = 0.0
		state = S.DEAD
		Pad.rumble(0.6, 1.0, 0.6)
		return
	if trial.won() or (not trial.active and final_boss != null and final_boss.dead):
		victory.begin()
		return
	check_pending()


func check_pending() -> void:
	if state != S.PLAY or demo_op != "" or trial.active:
		return
	if ult != null and ult.playing():
		return   # 终结技播放中：升级 / 宝箱三选一、精英化演出、路线选择都等播完再弹（计数照攒，播完逐个按原顺序弹）
	if not show_queue.is_empty():
		show_screen.open(show_queue.pop_front())
		return
	if progression.open_branch_queued():   # 赠送推进（典训 / 博士银印）碰到分支节点：先选路线（docs/119 §4.1）
		return
	if meta_start_relic > 0 and t > 1.0:
		# 认知塑造「物由心生」：开局从基础藏品中选 1 件（build_guide.relic_pool_ids 看 meta_basic_pick）
		meta_start_relic = 0
		meta_basic_pick = true
		pending_chests += 1
		chest_src.append("meta")
	if pending_chests > 0:
		progression.open_relic_choice()
	elif pending_levelups > 0 and lvup_delay <= 0.0:
		progression.open_levelup()


# =====================================================================
# 属性同步与对局工具：sync_stats（stats → 缓存变量）、灯火半径 / 技力倍率、对局随机数洗牌、性能打点
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
	&"followup_dmg": "followup_mult", &"heal_mult": "heal_mult", &"phys_taken": "phys_taken_mult", &"corrode_taken": "corrode_taken_mult", &"nerve_taken": "nerve_taken_mult",
	# docs/57 P1–P5 / P7
	&"boss_dmg": "boss_mult", &"light_loss": "lamp_loss_mult", &"enemy_speed": "enemy_speed_mult", &"enemy_kb": "enemy_kb_mult",
	&"enemy_ranged_cd": "enemy_ranged_cd_mult", &"elite_dmg_taken": "elite_taken_mult", &"elite_dmg": "elite_mult",
}


## 属性同步：StatBlock（stats）有变化时，按 STAT_SYNC 回填缓存变量并调 ch.sync_stats()；模块 / 干员改了 stats 后直接调它（没变化时立即返回）
func sync_stats() -> void:
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
func lamp_r() -> float:
	return lerpf(110.0, 360.0, lamp / 100.0) * squad.light_radius_mult()


func _lamp_sp() -> float:
	return (1.3 if lamp >= 70.0 else 1.0) * rfx.sp_extra()


## 用对局随机数洗牌。Array.shuffle() 走全局随机流，全局流也被纯视觉效果按真实帧率消耗，会让同 seed 的局跑出不同结果
func shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## --prof：把上一次打点到现在的耗时记到 k 名下（k 为空只重置起点）
## --prof 细分计时：把 t0 起到现在的微秒记进 prof[k]，返回现在（下一段的起点）
func prof_add(k: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	prof[k] = int(prof.get(k, 0)) + (now - t0)
	return now


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
	enemies = enemies_sys.sweep_dead(enemies)   # 去掉已死的并回收槽位（docs/101 B5；顺序与原 filter 相同）
	# 掉落物只在 pickups.gd 里被标记 dead（拾取 / 回收，计数 dead_n）：这一帧没有就不重建（满地几百颗时逐帧 filter 是常驻开销，docs/50 §11）
	if pickups.dead_n > 0:
		gems = gems.filter(func(g): return not g.dead)
		pickups.dead_n = 0
	bullets = bullets.filter(func(b): return b.life > 0.0)
	ebullets = ebullets.filter(func(b): return b.life > 0.0)
	fx = fx.filter(func(f): return f.life > 0.0)
	texts = texts.filter(func(f): return f.life > 0.0)


# =====================================================================
# 博士挂件状态、引擎回调（_exit_tree / _draw 转发）；跟随逻辑在 characters/doctor.gd update_follow，开局指南文本在 data/guide.json（docs/101 S5）
# =====================================================================
## 博士挂件（docs/23 v0.7）的位置 / 跑停 / 朝向：绘制与排序要读，留在这里；每帧由 doctor.update_follow 更新
var doc_pos := Vector2.INF
var doc_moving := false
var doc_face := 1.0


## 离开对局（回标题 / 关游戏）：还没记过的这一局按「中途退出」写进本地记录
func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_cover_tick):
		RenderingServer.frame_post_draw.disconnect(_cover_tick)
	if demo_op == "":
		UI.fk = 1.0
	if trial.active:
		trial.leave()
	else:
		telemetry.on_exit()
		if demo_op == "":
			perf_rep.finish("quit")


## --prof：给某个绘制回调计时（HUD / 加色层 / 前景），不开 --prof 时直接调用
func _timed(k: String, f: Callable) -> void:
	if not prof_on:
		f.call()
		return
	var t0 := Time.get_ticks_usec()
	f.call()
	prof[k] = int(prof.get(k, 0)) + Time.get_ticks_usec() - t0


## 世界绘制（引擎回调）：转发到 render/world.gd
func _draw() -> void:
	if not prof_on:
		world.draw_world()
		return
	var t0 := Time.get_ticks_usec()
	world.draw_world()
	prof["draw_world"] = int(prof.get("draw_world", 0)) + Time.get_ticks_usec() - t0   # --prof：世界绘制单独计（它也算在下一帧的 engine 里）






## 冲刺提示（用户要求：不提示就不知道有冲刺）：
## ① 屏幕底部中间常驻一枚按键牌「空格 冲刺」，冷却时底色按进度走满，可冲时描边亮起；
## ② 开局前 25 秒（直到第一次冲刺为止）主控头顶浮一行「按 空格 冲刺」。触屏有自己的冲刺按钮，不画这两样
var dash_used := false


## 旧名转发（docs/101 S6，2026-10-15 改公开名）：tests/ 与未合入的分支还在调旧名，各分支合完后删
func _lamp_r() -> float:
	return lamp_r()

func _shuffle(a: Array) -> void:
	shuffle(a)

func _check_pending() -> void:
	check_pending()

func _glance_step(rd: float) -> void:
	glance_step(rd)
