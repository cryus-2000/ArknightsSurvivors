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
}
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
const MAX_ENEMIES := 450

var state: int = S.PLAY
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
var horde_mult := 1.0
var horde_log: Array = []          # 平衡测试：每次大群的统计
var horde_chest := false
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
var drone_rescue_cd := 0.0       # Lv.3 急救冷却
var bullets: Array = []

# ---------- 世界 ----------
var enemies: Array = []
var gems: Array = []
var fx: Array = []
var texts: Array = []
var grid := {}
var next_id := 0
var orbit_a := 0.0
var spawn_acc := 0.0
var next_elite := 45.0
var threat := 0                  # 威胁等级（D.THREAT 下标）
var diff := 0                # 本局难度
var diff_new := false
var winshot := false
var touchtest_p0 := Vector2.ZERO
var ending_new := false            # 本局首次达成该结局（结算面板显示）        # 本局通关解锁了新难度
var stinger_done := false
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
var horde_warned := -1.0
var boss = null                 # 当前显示血条的 Boss
var bosses: Array = []
var boss_idx := 0
var final_boss = null
var ending := "standard"
var endg: RefCounted = null        # 结局与事件箱（scripts/endings.gd）
var knight: RefCounted = null      # 猎潮的骑士同伴（scripts/allies/knight.gd）
var touch: RefCounted = null       # 触屏操作（scripts/touch.gd）
var frost := 0.0                   # 冰霜：移速 -40%
var lamp_cap := 100.0              # 灯火上限（深蓝之心后 70）
var knight_alive := false          # 猎潮的骑士在队中（结局二）
var force_boss := -1
var mid_used: Array = []
var atk_slow := 0.0
var ebullets: Array = []
var shocks: Array = []
var warns: Array = []
var bai: RefCounted = null      # Boss AI / 招式预警（scripts/boss_ai.gd）            # Boss 招式预警 {shape, pos, ang, r, len, wid, half, t, dur, act, owner, dmg}
var mires: Array = []
var mire_tick := 0.0
var in_mire := 0.0               # 站在溟痕里的程度（0..1，平滑过渡，用于减速与屏幕变暗）
var next_chest := 20.0
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
var font: Font
var tex := {}
var panel_title_text := ""
# ---------- 打击感 ----------
var hitstop := 0.0
var shake := 0.0
var cam_kick := Vector2.ZERO
var hurt_vignette := 0.0
var tab_hint := 0.0          # 首次升级后再提醒一次 Tab
var tab_hinted := false
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
var bal_done := false
var bot = null                   # --balance 机器人（docs/29）；--bot=afk|bad|normal|expert
var elites_killed := 0
var shop_visits := 0
var dmg_log := {}
var dmg_out: Dictionary = {}     # 造成的伤害按来源统计（balance 输出）
var heal_log: Dictionary = {}    # 有效治疗按来源统计（balance 输出：无人机 / 医疗干员 / 藏品 是不是保底）
var hit_src: Dictionary = {}        # 合并后的伤害来源表（HIT_BASE + 角色 hit_sources）
var hit: Dictionary = {"src": "?", "emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []}
var dmg_tag_out: Dictionary = {}    # 造成伤害按 tag 统计（Tab 面板"本局构成"）
var dmg_src := ""
var lv_marks := {}
var at_frames := 0
var bosstest := false
var shot_at := [3400]
var shot_dir := "/tmp/claude-0"     # 自测截图目录（--shotdir= 覆盖，Windows 本地用）
var choice_wait := 0
var choice_shot := false
var floor_hits := 0            # --nodeath：生命归零被托住的次数
var floor_times: Array = []

# ---------- 图鉴演示（gallery.gd 把本场景放进 SubViewport，demo_op 为要演示的干员 id）----------
# 不刷怪、不掉落、不升级、没有 HUD 与音乐；按技能分段循环，每段重置干员与右侧怪海（见 _demo_step）
var demo_op := ""
var dbg_offer := {}              # 平衡输出：各干员深度卡被提供 / 被选中的次数
var dbg_pick := {}
var demo_elite := 0            # 演示时把干员直接推到这个精英化阶段（精英化演出用）
var demo_skill := -1           # 演示时只循环施放这个技能（-1 = 一 / 二 / 三技能分段轮流）
var show_vp: SubViewport = null  # 精英化演出里的实机演示画面
var show_game: Node = null


func _ready() -> void:
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
	# 博士动画条（data/doctor.json 的 sprites：idle / run / hurt / death）
	for kind in ["idle", "run", "hurt", "death"]:
		var dn = doctor.def.get("sprites", {}).get(kind, "")
		if dn is String and dn != "":
			tex[dn] = A.tex(dn)
	next_mire = float(map.mire_cfg().get("first_at", 100))
	A.normal_maps = Cfg.normal_maps
	rfx = RelicFx.new(self)
	endg = Endings.new(self)
	knight = Knight.new(self)
	touch = Touch.new(self)
	if D.ENEMIES.has("knight"):
		D.ENEMIES.knight.no_spawn = true  # 敌对骑士只在同伴骑士阵亡后进入精英池（每局重置）
	RL = rfx.table()
	rng.randomize()
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
		stats.add(&"max_hp", "override", 80.0, "difficulty")
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
		OS.low_processor_usage_mode = false
		OS.low_processor_usage_mode_sleep_usec = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--forceboss="):
			force_boss = int(a.substr(12))
		if a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
			seed(int(a.substr(7)))
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


func _update_music(_dt: float) -> void:
	if demo_op != "":
		return
	var target := 20000.0
	if state == S.PLAY and lamp < 30.0:
		target = lerp(700.0, 4000.0, lamp / 30.0)
	if state == S.PAUSE or state == S.CHOICE or state == S.SHOP or state == S.SHOW or state == S.STATS or state == S.INTRO or state == S.OPENING:
		target = 1800.0
	Sfx.cut_target = target
	Sfx.vol_target = -4.0
	# ---- 选曲与战斗分层（v0.9 配乐）
	if state == S.DEAD or state == S.WIN:
		if not stinger_done:
			stinger_done = true
			Sfx.play_stinger("win" if state == S.WIN else "lose")
		return
	if state == S.SHOP:
		Sfx.play_music("shop")
		return
	if state == S.OPENING or (state == S.INTRO and intro_back == S.PLAY and Sfx.track_playing("opening")):
		# 开场动画（及首次进入的指南）：播放开场引子《沉降》，动画结束后战斗曲淡入
		Sfx.play_music("opening")
		return
	if final_boss != null and not final_boss.dead:
		Sfx.play_music("final")
		return
	if _boss_alive():
		Sfx.play_music("boss")
		return
	# 战斗曲三段：按威胁等级推进（0–1 开局 / 2–3 中期 / 4+ 后期）
	Sfx.play_music("explore" if threat < 2 else ("explore2" if threat < 4 else "explore3"))
	var n := enemies.size()
	var elite := false
	for e in enemies:
		if e.elite and not e.dead and not e.chest:
			elite = true
			break
	var pulse := t > 12.0 or n > 30
	var drive = n > 110 + int(t / 3.0) or horde_warn > 0.0 or horde_hit > 0.0 or elite or squad.any_skill_active() or zone_state == 2
	var out_zone := zone_state != 0 and ppos.distance_to(zone_c) > zone_r
	var danger := hp < max_hp * 0.35 or lamp <= 0.0 or out_zone
	Sfx.set_layers([1.0, 1.0 if pulse else 0.0, 1.0 if drive else 0.0, 1.0 if danger else 0.0])


## 平衡机器人选卡（docs/27 §6）：像一个「懂玩」的玩家——优先干员深度 / 技能卡，早期见招募就招，
## 被动按 data/balance.json bot.growth_weights 加权，填充卡只在没得选时拿；--botrandom 退回纯随机
func _bot_pick() -> int:
	if choices.is_empty():
		return 0
	if bot != null:
		var bp: int = bot.pick(choices)
		if bp >= 0:
			return bp
	if OS.get_cmdline_user_args().has("--botrandom"):
		return rng.randi() % choices.size()
	var W: Dictionary = Bal.sec("bot/weights")
	var GW: Dictionary = Bal.sec("bot/growth_weights")
	var early_recruit: int = Bal.vi("bot/prefer_recruit_before", 8)
	var ws: Array = []
	var total := 0.0
	for c in choices:
		var w: float = float(W.get(c.get("kind", ""), 1.0))
		if c.kind == "recruit" and level < early_recruit:
			w = 100.0
		elif c.kind == "growth":
			w *= float(GW.get(c.get("id", ""), 1.0))
		elif c.kind == "prog" and int(c.get("elite", 0)) > 0:
			w *= 1.5   # 精英化卡：解锁技能与天赋，价值最高
		ws.append(w)
		total += w
	var r := rng.randf() * total
	for i in ws.size():
		r -= ws[i]
		if r <= 0.0:
			return i
	return ws.size() - 1


## 图鉴演示每帧：博士满状态站定；三个位置各维持一只不动、不伤人的假人海嗣，被打死 1.5 秒后原地重生。
## 假人会慢慢挪向开局干员并停在 70 以外，让近战干员也够得着；击退后自然回位
## 图鉴 / 精英化演出（2026-09-25 改版，用户要求）：按「一技能 → 二技能 → 三技能」分段循环，每段单独展示一招。
## 每段开始时重置：干员重新生成（永久型 / 叠层等状态不带到下一段）、博士与干员站左边、右边刷一片怪海慢慢推过来；
## 先普攻约 1 秒再充满这一段的技能（其余技能压住不充），技能放完、效果结束再停 1.5 秒进入下一段；怪清空了就在右边补一波。
## 精英化演出（demo_skill ≥ 0）只循环刚解锁的那一招。gallery.gd 读 demo_label 显示当前是哪一段。
const DEMO_HORDE := 16
const DEMO_FILL_AT := 1.0
const DEMO_HOLD := 1.5
const DEMO_MAX := 14.0
var demo_origin := Vector2.INF   # 场地中心（镜头固定在这里）
var demo_phases: Array = []
var demo_pi := -1
var demo_ph_t := 0.0
var demo_cast_t := -1.0          # 本段技能放出后经过的秒数（-1 = 还没放）
var demo_label := ""


func _demo_step(dt: float) -> void:
	lamp = 100.0
	hp = max_hp
	xp = 0.0
	gems.clear()
	if demo_origin == Vector2.INF:
		demo_origin = ppos
		demo_phases = [demo_skill] if demo_skill >= 0 else [0, 1, 2]
		_demo_next_phase()
	var si: int = demo_phases[demo_pi]
	demo_ph_t += dt
	# 只让本段的技能充能：其余压成 0
	for i in 3:
		if i != si and not ch.perm[i]:
			ch.sp[i] = 0.0
	if demo_cast_t < 0.0:
		if demo_ph_t >= DEMO_FILL_AT and ch.skill_unlocked(si):
			if ch.sp[si] < ch.sp_need(si) and demo_ph_t < DEMO_FILL_AT + dt * 1.5:
				ch.sp[si] = ch.sp_need(si)
			if ch.is_manual(si) and ch.sp[si] >= ch.sp_need(si):
				ch.cast_manual(si)   # 手动技能（幽灵鲨 S2）没人按键：替玩家放
			# 充满后被消费掉（或永久型已生效）= 放出去了
			if ch.sp[si] < ch.sp_need(si) * 0.5 or ch.perm[si] or ch.skill_active_left(si) > 0.0:
				demo_cast_t = 0.0
	else:
		demo_cast_t += dt
	var done: bool = demo_cast_t >= DEMO_HOLD and ch.skill_active_left(si) <= 0.0 and not ch.acting()
	if done or demo_ph_t >= DEMO_MAX:
		_demo_next_phase()
		return
	# 怪海清空了：右边补一波
	var alive := 0
	for e in enemies:
		if not e.dead:
			alive += 1
	if alive < 4:
		_demo_horde(10)


## 镜头看着的位置：平时跟博士；图鉴演示里固定在场地中心（map.gd 按它决定画哪些地块）
func view_center() -> Vector2:
	return demo_origin if demo_op != "" and demo_origin != Vector2.INF else ppos


func _demo_next_phase() -> void:
	demo_pi = (demo_pi + 1) % demo_phases.size()
	demo_ph_t = 0.0
	demo_cast_t = -1.0
	enemies.clear()
	bullets.clear()
	ppos = demo_origin + Vector2(-150, 10)
	_demo_new_op()
	_demo_horde(DEMO_HORDE)
	var si: int = demo_phases[demo_pi]
	demo_label = "%s技能「%s」" % [["一", "二", "三"][si], ch.skill_def(si).get("name", "")]


## 重新生成演示干员：清掉旧实例挂在 op:<id> 作用域上的全部修正，再按演示要求推到精英化阶段
func _demo_new_op() -> void:
	var id: String = demo_op
	if ch != null and squad.has(id):
		squad.remove(id)
	stats.remove_scope("op:" + id)
	_sync_stats()
	ch = squad.add(id)
	var want: int = demo_elite if demo_elite > 0 else 2
	var guard := 0
	while ch.elite < want and not ch.next_node().is_empty() and guard < 12 and demo_elite > 0:
		guard += 1
		var n: Dictionary = ch.next_node()
		var chs: Dictionary = ch.elite_choices(n) if n.get("type", "") == "elite" else {}
		ch.advance(chs.keys()[0] if not chs.is_empty() else "")
	if ch.elite < want:
		ch.elite = want
	show_queue.clear()
	facing = 1.0   # 博士面朝右侧怪海
	ch.pos = ppos + squad._slot_offset(0)   # 直接站在跟随位上，开场不再先走一步


## 右边刷一片怪海：椭圆区域里随机撒开，慢慢向博士推进（演示里敌人不造成伤害）
func _demo_horde(n: int) -> void:
	for k in n:
		var a: float = rng.randf() * TAU
		var r: float = sqrt(rng.randf())
		# 前排离博士约 160（近战干员的前压范围），一开场就能接敌
		var p: Vector2 = demo_origin + Vector2(105 + cos(a) * r * 90.0, sin(a) * r * 72.0)
		var ne := _spawn_enemy("bone", p)
		ne.spd = 16.0
		ne.dmg = 0.0
		ne.hp = 140.0
		ne.maxhp = 140.0
		ne.xp = 0.0


## 开发自测：把所有 Boss（含假死/二阶段形态）摆成一排截图，检查美术接入与 2.5D 遮挡
func _gallery_step() -> void:
	ppos = Vector2.ZERO
	hp = max_hp
	lamp = 100.0
	if at_frames == 20:
		for e in enemies:
			e.dead = true
		var types := ["path", "carmen", "iberia", "bishop", "archon", "immortal", "paranoia", "paranoia", "bishop", "archon", "immortal", "fractal"]
		for i in types.size():
			var p := Vector2(-520 + (i % 6) * 208, -170 + (i / 6) * 250)
			var e := _spawn_enemy(types[i], p)
			e.spd = 0.0
			e.dmg = 0.0
			e["gallery"] = true
			if i == 7:
				e.phase = 2
			if i >= 8 and i <= 10:
				e["gal_coma"] = true
	for e in enemies:
		if not e.get("gallery", false):
			e.dead = true
		else:
			e.hp = e.maxhp
			e.stun = 0.0
			if e.get("gal_coma", false):
				e["coma"] = true
				e.hp = e.maxhp * 0.5
			e.kb = Vector2.ZERO
	if at_frames == 90 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_gallery.png")
		get_tree().quit()


## 仅用于开发自测：快速模拟一整局，自动选择升级，打印状态后退出
func _autotest_step() -> void:
	at_frames += 1
	if state == S.OPENING and OS.get_cmdline_user_args().has("--openshot"):
		if at_frames % 3 == 0 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_open_%03d.png" % at_frames)
		if at_frames > 240:
			get_tree().quit()
		return
	if state == S.INTRO:
		if intro_t > 0.5 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_intro_%d.png" % intro_page)
			if intro_page >= INTRO_PAGES.size() - 1:
				get_tree().quit()
				return
			intro_page += 1
			intro_t = 0.0
		return
	if OS.get_cmdline_user_args().has("--gallery"):
		_gallery_step()
		return
	if state == S.SHOP:
		for i in shop_items.size():
			if not shop_items[i].sold and ingots >= shop_items[i].price:
				_buy(i)
				break
		if shop_visits == 1 and DisplayServer.get_name() != "headless" and not balance:
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_shop.png")
		shop_visits += 1
		if shop_visits % 3 == 0:
			_close_shop()
	for m in [120, 300, 480]:
		if t >= m and not lv_marks.has(m):
			lv_marks[m] = level
	if OS.get_cmdline_user_args().has("--fxtest"):
		ppos = Vector2(1500, 900)
		if at_frames == 90:
			hp = max_hp * 0.2
			_hurt(max_hp * 0.1)
		if at_frames == 96 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_fx_hurt.png")
		if at_frames == 175:
			zone_c = ppos + Vector2(560, 60)
			zone_r = 480.0
			zone_state = 3
			zone_t = -999.0
		if at_frames == 188 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_fx_zone.png")
		if at_frames == 130:
			state = S.STATS
		if at_frames == 132:
			for c in stats_cells:
				if c[1] == "relic":
					Input.warp_mouse(c[0].get_center())
					break
		if at_frames == 134 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_fx_stats.png")
			state = S.PLAY
		if at_frames == 20:
			weapons = {"drone": 4}
			for rid in ["118", "199", "100"]:
				relics.append(rid)
				_apply_relic(rid)
			shield = 2
			ch.elite = 2
			ch.fill_sp()
			for k in ["wisadel", "eyjafjalla", "suzuran"]:
				var op = squad.add(k)
				if op != null:
					op.advance()
					op.advance()
			t = 149.0
			next_horde = t + 60.0
			merchant = {"pos": ppos + Vector2(900, -300), "life": 60.0, "near": false}
		if at_frames == 150 and not tray_cells.is_empty():
			Input.warp_mouse(tray_cells[0][0].get_center())
		if at_frames == 60:
			_drop(ppos + Vector2(120, 40), "magnet", 1.0)
			_drop(ppos + Vector2(-120, 40), "heal", 1.0)
		for f in [64, 72, 100, 125, 160, 200]:
			if at_frames == f and DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_fx_%d.png" % f)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bosstest="):
			# Boss 招式测试：在水月旁刷出指定 Boss，定时截图
			bosstest = true
			if at_frames == 20:
				ppos = Vector2(1500, 900)
				max_hp = 900.0
				hp = 900.0
				t = 150.0
				for bt in a.substr(11).split(","):
					var b := _spawn_enemy(bt.trim_suffix("2"), ppos + Vector2(230, -40))
					b.age = 5.0
					if bt.ends_with("2"):
						b.phase = 2
						b.range = 400.0
					bosses.append(b)
					boss = b
				if bosses.size() == 2:
					bosses[0].partner = bosses[1]
					bosses[1].partner = bosses[0]
			if at_frames > 20 and at_frames % 30 == 0 and at_frames <= 600 and DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_boss_%s_%03d.png" % [a.substr(11).replace(",", "_"), at_frames])
	if OS.get_cmdline_user_args().has("--fastlevel") and state == S.PLAY and (at_frames == 30 or at_frames == 400):
		level = 9 if at_frames == 30 else 19
		_gain_xp(xp_need + 0.1)
	if state == S.SHOW:
		if balance:
			show_t = 2.0
			_close_show()
			return
		if show_t > 1.4 and not show_shot and DisplayServer.get_name() != "headless":
			show_shot = true
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_show_%d.png" % ch.elite)
		if show_t > 1.6:
			_close_show()
		return
	if at_frames == 30 and state == S.PLAY:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--grant="):
				for rid in a.substr(8).split(","):
					_gain_relic(rid)
	# --shots 在平衡模式下也生效（平衡分支会提前 return）：特效连拍用 --balance --nodeath 跳过精英化演出
	if balance and shot_at.has(at_frames) and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_%d.png" % at_frames)
	# 机器人的手动技能（幽灵鲨 S2 保命）：博士生命低于阈值时替玩家按下
	if state == S.PLAY and hp < max_hp * Bal.v("bot/manual_hp", 0.3):
		for o in squad.ops:
			if o.manual_ready(o.manual_index()):
				o.cast_manual(o.manual_index())
				break
	if balance and OS.get_cmdline_user_args().has("--sptest") and at_frames % 45 == 0:
		for o in squad.ops:
			o.fill_sp()
	if balance:
		if bot != null and state == S.PLAY:
			bot.tick(0.066)
		if false:
			print("dbg t=%d state=%d lv=%d hp=%d en=%d" % [t, state, level, hp, enemies.size()])
		if state == S.CHOICE:
			var pi := _bot_pick()
			for a in OS.get_cmdline_user_args():
				# --evpick=1 或 --evpick=madness:0,knight_stay:0,default:1
				if a.begins_with("--evpick=") and choice_kind == "event":
					var spec: String = a.substr(9)
					if spec.is_valid_int():
						pi = mini(int(spec), choices.size() - 1)
					else:
						var evid: String = String(choices[0].id).split(":")[0]
						for part in spec.split(","):
							var kv: PackedStringArray = part.split(":")
							if kv.size() == 2 and (kv[0] == evid or kv[0] == "default") and (kv[0] != "default" or not spec.contains(evid + ":")):
								pi = mini(int(kv[1]), choices.size() - 1)
			_pick(pi)
		# 10:00 最终 Boss 登场后给 3 分钟打完（之前 620 秒截断只留 20 秒，胜负基本看不出来）
		if (state == S.DEAD or state == S.WIN or t > 780.0) and not bal_done:
			bal_done = true
			print("BALANCE ", JSON.stringify({"win": state == S.WIN, "t": int(t), "lv": level, "marks": lv_marks, "lv_times": lv_times, "ops": squad.ops.map(func(o): return {"id": o.id, "elite": o.elite, "prog": o.prog}), "prog_offer": dbg_offer, "prog_pick": dbg_pick, "kills": kills,
				"elites": elites_killed, "relics": relics.size(), "ingots": ingots, "maxhp": max_hp, "bosses": bosses.map(func(b): return "%s:%s" % [b.type, "dead" if b.dead else "%d%%" % int(100 * b.hp / b.maxhp)]), "allies": squad.size() - 1, "squad": squad.ids(), "elite_stage": ch.elite,
				"boss_hp": (boss.hp / boss.maxhp) if boss != null else -1.0, "dmg": dmg_log, "out": dmg_out, "out_type": dmg_type_out, "out_tag": dmg_tag_out, "ending": ending, "lamp": int(lamp), "rej": doctor.rej(), "heal": heal_log, "drone": weapons.get("drone", 0), "floor_hits": floor_hits, "floor_times": floor_times, "hordes": horde_log.map(func(h): return {"t": h.t, "n": h.n, "hp": int(h.hp), "t80": h.t80, "hp0": int(h.hp0), "minhp": int(h.minhp), "comp": h.comp}), "final_out": dmg_out, "bot": bot.report() if bot != null else {}}))
			get_tree().quit()
		return
	if not (OS.get_cmdline_user_args().has("--fxtest") and at_frames >= 90 and at_frames < 100):
		hp = max_hp
	if lvup_show > 1.05 and lvup_show < 1.12 and level == 3 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_lvup.png")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--eventtest=") and at_frames == 30:
			for ev in endg.events:
				if ev.id == a.substr(12):
					endg._spawn_box(ev)
					endg.done.append(ev.id)
					for e in enemies:
						if e.chest and e.get("event", "") != "":
							e.pos = ppos + Vector2(120, 0)
	if OS.get_cmdline_user_args().has("--touchtest") and state == S.PLAY:
		# 模拟：第 60 帧按下左半屏，拖到右上，第 120 帧松开；第 90 帧截图
		if at_frames == 60:
			var tp := InputEventScreenTouch.new()
			tp.index = 0
			tp.pressed = true
			tp.position = Vector2(200, 500)
			Input.parse_input_event(tp)
			touchtest_p0 = ppos
		elif at_frames > 60 and at_frames < 120:
			var td := InputEventScreenDrag.new()
			td.index = 0
			td.position = Vector2(200, 500) + Vector2(1.2, -0.7) * float(at_frames - 60)
			Input.parse_input_event(td)
		elif at_frames == 120:
			var tr := InputEventScreenTouch.new()
			tr.index = 0
			tr.pressed = false
			tr.position = Vector2(272, 458)
			Input.parse_input_event(tr)
			print("TOUCHTEST moved=%s" % str((ppos - touchtest_p0).round()))
		if at_frames == 90 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_touch.png")
		if at_frames == 130:
			get_tree().quit()
	if OS.get_cmdline_user_args().has("--gemshot"):
		if at_frames == 60:
			for k in 14:
				_drop(ppos + Vector2.from_angle(TAU * k / 14.0) * 150.0, "xp", 8.0 if k % 4 == 0 else 1.0)
			_drop(ppos + Vector2(60, -40), "xp", 1.0)
		if at_frames in [72, 100] and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_gem_%d.png" % at_frames)
			if at_frames == 100:
				get_tree().quit()
	if OS.get_cmdline_user_args().has("--relicshot"):
		if at_frames == 30:
			pending_chests = 1
			ingots = 40
		if at_frames == 400:
			merchant = {"pos": ppos, "life": 60.0, "near": false}
			_open_shop()
		if at_frames == 440 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_shop.png")
			get_tree().quit()
	if state == S.CHOICE:
		choice_wait += 1
		if choice_wait == 40 and not choice_shot and DisplayServer.get_name() != "headless" and (choice_kind == "relic" or not OS.get_cmdline_user_args().has("--relicshot")):
			choice_shot = true
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_choice.png")
		if choice_wait > 45:
			choice_wait = 0
			# 机器人像真人一样偏好干员深度 / 精英化卡（70%），其余均匀随机
			var deep: Array = []
			for ci in choices.size():
				if choices[ci].kind == "prog":
					deep.append(ci)
			if not deep.is_empty() and rng.randf() < 0.7:
				_pick(deep[rng.randi() % deep.size()])
			else:
				_pick(rng.randi() % choices.size())
	if at_frames % 1200 == 0:
		print("t=%d lv=%d E%d hp=%d enemies=%d kills=%d lamp=%d growth=%s relics=%s squad=%s fps=%d" % [t, level, ch.elite, hp, enemies.size(), kills, lamp, growth, relics, squad.ops.map(func(o): return "%s%d/%d" % [o.id, o.elite, o.prog]), Engine.get_frames_per_second()])
	for bb in bosses:
		if not bb.dead and not bb.invuln and not bosstest:
			bb.hp -= 4.0 if bosstest else 40.0
			if bb.hp <= 0.0:
				_kill(bb)
	for a in OS.get_cmdline_user_args():
		# --winshot=deep：第 60 帧直接进入胜利结算并截图
		if a.begins_with("--winshot=") and at_frames == 60:
			winshot = true
			ending = a.substr(10)
			endg.cur = ending
			ending_new = true
			state = S.WIN
		if a.begins_with("--winshot=") and at_frames == 130 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_win.png")
			get_tree().quit()
	# --sptest：每 2 秒把全队技力充满（截图 / 观察技能特效用）
	if OS.get_cmdline_user_args().has("--sptest") and at_frames % 120 == 0:
		for o in squad.ops:
			o.fill_sp()
	if shot_at.has(at_frames) and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(shot_dir + "/shot_%d.png" % at_frames)
	if bosstest and at_frames > 610:
		get_tree().quit()
	if (state == S.WIN and not winshot) or at_frames > 14000:
		print("AUTOTEST END state=%d t=%d" % [state, t])
		get_tree().quit()


# =====================================================================
# 主循环
# =====================================================================
func _process(delta: float) -> void:
	var dt: float = min(delta, 0.05)
	if state != _last_state:
		_last_state = state
		state_age = 0.0
		res_sel = 0
	else:
		state_age += delta
	Pad.context = "play" if state == S.PLAY else "game_menu"
	if autotest:
		_autotest_step()
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
				_autotest_step()
				if state == S.PLAY:
					_update(dt)
	banner_t -= delta
	_update_visuals(dt if state == S.PLAY else 0.0)
	_update_music(delta)
	_animate_cards(delta)
	if state == S.SHOW:
		show_t += delta
	if state == S.INTRO:
		intro_t += delta
	queue_redraw()
	fx_add.queue_redraw()
	fg.queue_redraw()
	dof_layer.visible = Cfg.dof
	hud.queue_redraw()


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
	if (k == KEY_SPACE or k == KEY_J) and state == S.PLAY:
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
			_buy(k - KEY_1)
		elif k == KEY_F:
			_refresh_shop()
		elif k == KEY_ESCAPE or k == KEY_E:
			_close_shop()
	elif state == S.CHOICE and k >= KEY_1 and k <= KEY_3:
		var i: int = k - KEY_1
		if i < choices.size():
			_pick(i)


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
				_pick(nav_sel)
			else:
				_buy(nav_sel)
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


func _update(dt: float) -> void:
	t += dt
	_sync_stats()
	var mv := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if demo_op != "":
		mv = Vector2.ZERO
	elif balance:
		mv = bot.move(dt) if bot != null else _bot_move()
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
	if tex.get("prop_pillar") != null:
		ppos = map.push_out(ppos, 12.0)
	swing_face -= dt

	hp = min(max_hp, hp + (regen + regen_pct * max_hp) * dt)
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
	if demo_op != "":
		_demo_step(dt)
	else:
		_spawn(dt)
	_build_grid()
	_update_enemies(dt)
	squad.update(dt)
	_update_weapons(dt)   # 支援无人机：跟随博士，与编队里有谁无关
	knight.update(dt)
	touch.update(dt)
	_update_bullets(dt)
	_update_ebullets(dt)
	bai._update_warns(dt)
	_update_status(dt)
	rfx.tick(dt)
	endg.update(dt)
	endg.tick_final_warning()
	if ending == "knight" and knight.alive and t >= 585.0 and knight.state != "walk":
		knight.walk_to_center(zone_c if zone_state != 0 else ppos + Vector2(0, -220))
	if demo_op == "":
		_update_merchant(dt)
	_update_gems(dt)
	_update_fx(dt)
	_cleanup()

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


## 平衡测试用的简单 AI：躲开贴身的敌人、保持在挥伞距离、捡掉落物
func _bot_move() -> Vector2:
	var push := Vector2.ZERO
	var nearest_d := 99999.0
	var nearest_p := ppos
	for j in _query(ppos, 220.0):
		var e: Dictionary = enemies[j]
		if e.dead:
			continue
		var d: Vector2 = ppos - e.pos
		var l := d.length()
		if l < nearest_d:
			nearest_d = l
			nearest_p = e.pos
		var danger: float = 48.0 + e.r
		if l < danger and l > 0.01:
			push += d / l * (danger - l) / danger * (3.0 if (e.elite or e.boss) else 1.0)
		# 远程怪：像真人一样不站在它射程里干等（保持在它射程外沿）
		if e.ai == "ranged" and not e.boss and l > 0.01 and l < e.range + 20.0:
			push += d / l * 0.6
	# 低血量：远离敌群重心，先活下来再打
	if hp < max_hp * 0.5:
		var cen := Vector2.ZERO
		var cn := 0
		for j in _query(ppos, 320.0):
			var e2: Dictionary = enemies[j]
			if not e2.dead:
				cen += e2.pos
				cn += 1
		if cn > 0:
			var away: Vector2 = ppos - cen / cn
			if away.length() > 1.0:
				push += away.normalized() * (1.6 if hp < max_hp * 0.3 else 0.9)
	# 躲开招式预警、溟痕与敌方弹幕（让自测更接近真人）
	for w in warns:
		if w.done:
			continue
		var dv: Vector2 = ppos - w.pos
		if w.shape == "circle" and dv.length() < w.r + 30.0:
			push += (dv.normalized() if dv.length() > 1.0 else Vector2.RIGHT) * 1.4
		elif w.shape == "line":
			var b2: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			var cp: Vector2 = Geometry2D.get_closest_point_to_segment(ppos, w.pos, b2)
			if cp.distance_to(ppos) < w.wid + 40.0:
				var away: Vector2 = ppos - cp
				push += (away.normalized() if away.length() > 1.0 else Vector2.from_angle(w.ang).orthogonal()) * 1.4
		elif w.shape == "cone" and dv.length() < w.r + 30.0:
			push += dv.normalized() * 1.4
	for m in mires:
		var dm: Vector2 = ppos - m.pos
		if dm.length() < m.r + 24.0:
			push += dm.normalized() * 2.0
	for bl in ebullets:
		if bl.life <= 0.0 or bl.pos.distance_to(ppos) > 170.0:
			continue
		var toward: Vector2 = (ppos - bl.pos)
		if bl.vel.dot(toward) <= 0.0:
			continue
		# 只躲会打到自己的子弹：算它的直线路径离自己多近，往远离路径的一侧闪
		var vdir: Vector2 = bl.vel.normalized()
		var along: float = toward.dot(vdir)
		var side: Vector2 = toward - vdir * along
		var miss: float = side.length()
		if miss < bl.r + 40.0:
			var sdir: Vector2 = side.normalized() if miss > 1.0 else vdir.orthogonal()
			var urgency: float = clampf(1.0 - along / 170.0, 0.3, 1.0)
			push += sdir * 1.6 * urgency
	var pull := Vector2.ZERO
	var best := 260.0
	for g in gems:
		var gd: float = g.pos.distance_to(ppos)
		var w: float = gd * (0.4 if (g.kind == "oil" and lamp < 60.0) or g.kind == "chest" else 1.0)
		if w < best:
			best = w
			pull = (g.pos - ppos).normalized() * 0.7
	if hp > max_hp * 0.5:
		for bb in bosses:
			if not bb.dead and not bb.invuln and bb.pos.distance_to(ppos) > 90.0:
				pull = (bb.pos - ppos).normalized() * 0.8
				break
	if not merchant.is_empty() and merchant.pos.distance_to(ppos) < 500.0 and not merchant.near:
		pull = (merchant.pos - ppos).normalized() * 0.9
	for e in enemies:
		if e.chest and not e.dead and e.pos.distance_to(ppos) < 400.0:
			pull = (e.pos - ppos).normalized() * 0.8
			break
	if pull == Vector2.ZERO and nearest_d > 100.0 and nearest_d < 99999.0 and hp > max_hp * 0.4:
		pull = (nearest_p - ppos).normalized() * 0.5
	var mv := push * 2.2 + pull
	# 溟痕：像真人玩家一样绕开（在里面时全力往外走）
	for m in mires:
		var md: Vector2 = ppos - m.pos
		var ml := md.length()
		if ml < m.r + 50.0 and ml > 0.01:
			mv += md / ml * (2.5 if ml < m.r else 1.2)
	# 缩圈：靠近圈边时往圈内走
	if zone_state != 0:
		var zc: float = ppos.distance_to(zone_c)
		var target_c: Vector2 = zone_next_c if zone_state == 1 else zone_c
		var target_r: float = zone_next_r if zone_state == 1 else zone_r
		if ppos.distance_to(target_c) > target_r - 160.0 or zc > zone_r - 160.0:
			mv += (target_c - ppos).normalized() * 3.0
	if mv.length() < 0.15:
		mv = Vector2.from_angle(t * 0.3) * 0.3
	return mv


func _check_pending() -> void:
	if state != S.PLAY or demo_op != "":
		return
	if not show_queue.is_empty():
		_open_show(show_queue.pop_front())
		return
	if pending_chests > 0:
		_open_relic_choice()
	elif pending_levelups > 0 and lvup_delay <= 0.0:
		_open_levelup()


# =====================================================================
# 刷怪
# =====================================================================
func _edge_pos() -> Vector2:
	return ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(720.0, 820.0)


func _pick_type() -> String:
	var pool: Array = D.THREAT[threat].pool
	var pick: String = pool[rng.randi() % pool.size()]
	var caps := {"stone": (6 if t < 180.0 else (8 if t < 420.0 else 12)), "brood": 6, "offspring": 6 if t < 420.0 else 10, "spitter": 6, "burrower": 8, "hulk": 2, "ripper": 14}
	if caps.has(pick):
		var ns := 0
		for e in enemies:
			if e.type == pick and not e.dead:
				ns += 1
		if ns >= caps[pick]:
			pick = "slider" if threat >= 3 else "bone"
	return pick


func _pick_elite() -> String:
	var pool: Array = []
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if d.get("role", "") == "elite" and t >= float(d.get("elite_after", 0.0)) and not d.get("no_spawn", false):
			pool.append(k)
	if pool.is_empty():
		return "pocket"
	return pool[rng.randi() % pool.size()]


func _boss_alive() -> bool:
	for b in bosses:
		if not b.dead:
			return true
	return false


func _spawn(dt: float) -> void:
	# Boss 按时间登场
	if boss_idx < D.BOSS_TIMES.size() and t >= D.BOSS_TIMES[boss_idx]:
		boss_idx += 1
		var group: Array = []
		if boss_idx == D.BOSS_TIMES.size():
			group = [D.ENDINGS[ending].boss]
		else:
			var pool: Array = []
			for i in D.MID_POOL.size():
				if not mid_used.has(i):
					pool.append(i)
			var pick: int = pool[rng.randi() % pool.size()]
			if force_boss >= 0 and not mid_used.has(force_boss):
				pick = force_boss
			mid_used.append(pick)
			group = D.MID_POOL[pick]
		var base := _edge_pos()
		if zone_state != 0 and base.distance_to(zone_c) > zone_r - 90.0:
			base = zone_c + (base - zone_c).normalized() * maxf(60.0, zone_r - 110.0)
		if boss_idx == D.BOSS_TIMES.size() and group == ["knight_boss"]:
			# 结局二：骑士在原地重生为最终 Boss；若骑士已不在，则从边缘出现
			if knight.alive:
				base = knight.take_over()
			_show_banner("寒冰重生 —— 最后的骑士")
		var spawned: Array = []
		for k in group.size():
			var b := _spawn_enemy(group[k], base + Vector2(k * 90.0, 0))
			bosses.append(b)
			spawned.append(b)
			boss = b
		if spawned.size() == 2:
			spawned[0].partner = spawned[1]
			spawned[1].partner = spawned[0]
		if boss_idx == D.BOSS_TIMES.size():
			final_boss = spawned[0]
		var names: Array = []
		for g in group:
			names.append(D.ENEMIES[g].name)
		_show_banner("%s 出现了" % " 与 ".join(names))
		Sfx.play("roar", 2.0, 0.7, 0.0)
		Sfx.play_overlay("boss_in")
		_shake(1.2)
	# 威胁等级上升：横幅 + 刷一小波新种类
	if threat < D.THREAT.size() - 1 and t >= D.THREAT[threat + 1].t:
		threat += 1
		var tr: Dictionary = D.THREAT[threat]
		_show_banner("威胁上升 · %s —— 新的海嗣浮现" % tr.name)
		Sfx.play("roar", -1.0, 0.75, 0.0)
		_shake(0.8)
		var fresh: Array = tr.pool.filter(func(x): return not D.THREAT[threat - 1].pool.has(x))
		if not fresh.is_empty():
			for k in 6:
				_spawn_enemy(fresh[k % fresh.size()], _edge_pos())
	var rate := Bal.v("enemy/spawn_base", 1.6) + t / Bal.v("enemy/spawn_div", 30.0)
	if _boss_alive():
		rate *= 0.8
	if lamp < 30.0:
		rate *= 1.15
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < MAX_ENEMIES:
			var ne := _spawn_enemy(_pick_type(), _edge_pos())
			# 6 分钟后一部分海嗣直接以进化体出现（数量不变，质量提升）
			if not ne.elite and ne.ai != "static" and rng.randf() < D.THREAT[threat].get("evo", 0.0) * (2.0 if ending == "deep" else 1.0):
				_evolve(ne)
			if ending == "resolve" and t >= 520.0:
				ne.weak = ""
	if t >= next_elite:
		next_elite += D.THREAT[threat].elite * (0.75 if diff >= 4 else 1.0)
		var et := _pick_elite()
		_spawn_enemy(et, _edge_pos())
		if rfx.rule("resolve_elite") > 0:
			_spawn_enemy(_pick_elite(), _edge_pos())
		if threat >= 4:
			var et2 := _pick_elite()
			_spawn_enemy(et2, _edge_pos())
			_show_banner("精英「%s」与「%s」同时出现！" % [D.ENEMIES[et].name, D.ENEMIES[et2].name])
		else:
			_show_banner("精英「%s」出现！击败它获得藏品" % D.ENEMIES[et].name)
		Sfx.play("roar", -3.0)
	# 大群：Boss 在场时顺延（难度 7+ 不顺延）；9:30 之后不再刷（给最终 Boss 留空间）
	var horde_ok: bool = (not _boss_alive() or diff >= 7) and t < 570.0
	if t >= next_horde - 3.0 and horde_warned != next_horde and horde_ok:
		horde_warned = next_horde
		horde_warn = 3.0
		horde_gap = rng.randf() * TAU
		Sfx.play("roar", -2.0, 0.55, 0.0)
	if t >= next_horde and horde_ok:
		next_horde += D.THREAT[threat].get("horde_every", 120.0)
		horde_warn = 0.0
		horde_hit = 1.2
		_shake(1.4)
		fx.append({"kind": "horde_ring", "pos": ppos, "r": 640.0, "life": 0.9, "max": 0.9, "col": Color(0.75, 0.3, 1.0)})
		Sfx.play("roar", 2.0, 0.8, 0.0)
		# 数量：32 → 88（10 分钟），难度 7+ ×1.4；包围圈留 70° 缺口（预警时的箭头也留出这一侧），给玩家一条突围路线
		var n := int((Bal.v("enemy/horde_base", 24.0) + int(t / Bal.v("enemy/horde_div", 9.0))) * horde_mult * (1.4 if diff >= 7 else 1.0))
		if horde_chest:
			_drop(ppos + Vector2(70, 0), "chest", 1.0)
		var gap_half := deg_to_rad(35.0)
		var span: float = TAU - gap_half * 2.0
		var hl := {"t": int(t), "n": n, "hp": 0.0, "killed": 0, "t80": -1, "minhp": hp, "hp0": hp, "comp": D.THREAT[threat].horde.duplicate()}
		horde_log.append(hl)
		for i in n:
			if enemies.size() >= MAX_ENEMIES + 60:
				break
			var ang: float = horde_gap + gap_half + span * (i + 0.5) / n
			var p := ppos + Vector2.from_angle(ang) * rng.randf_range(560.0, 640.0)
			var hp_: Array = D.THREAT[threat].horde
			var he := _spawn_enemy(hp_[i % hp_.size()], p)
			he["horde"] = horde_log.size() - 1
			# 群体个体的接触伤害 ×0.7：被包围时不至于两下暴毙，压力来自数量而不是单体
			he.dmg *= 0.7
			hl.hp += he.maxhp
	# 补给箱
	if t >= next_chest:
		next_chest = t + rng.randf_range(35.0, 50.0)
		var nch := 0
		for e in enemies:
			if e.chest and e.get("event", "") == "":
				nch += 1
		if nch < 3:
			_spawn_chest(ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(260.0, 420.0))
	# 溟痕
	if t >= next_mire:
		# 溟痕随时间越来越多、越来越大；缩圈后多出现在圈边
		next_mire = t + map.mire_next_interval(t)
		var mp := ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 380.0)
		if zone_state != 0 and rng.randf() < 0.6:
			var ang := (ppos - zone_c).angle() + rng.randf_range(-0.8, 0.8)
			mp = zone_c + Vector2.from_angle(ang) * (zone_r - rng.randf_range(20.0, 120.0))
		if mires.size() < int(map.mire_cfg().get("max_count", 24)):
			mires.append(map.mire_new(mp, t, diff >= 8))
	# 商人
	if merchant.is_empty() and merchant_idx < MERCHANT_TIMES.size() and t >= MERCHANT_TIMES[merchant_idx]:
		merchant_idx += 1
		merchant = {"pos": ppos + Vector2.from_angle(rng.randf() * TAU) * 260.0, "life": 60.0, "near": false}
		shop_items.clear()
		shop_refreshed = false
		_show_banner("商人出现了 —— 去找他交易源石锭")
		Sfx.play("relic", -4.0)


func _new_enemy(type: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = D.ENEMIES[type]
	var role: String = d.get("role", "")
	# 生命曲线：前 8 分钟线性到 ×4.4，之后放缓（后期靠进化体与远程比例提升压力，而不是堆血）
	# 曲线参数见 data/balance.json enemy 段（docs/27 §4）
	var hk: float = Bal.v("enemy/hp_knee", 480.0)
	var hpm := (1.0 + minf(t, hk) / Bal.v("enemy/hp_div", 120.0) + maxf(t - hk, 0.0) / Bal.v("enemy/hp_late_div", 300.0)) * (1.0 + (0.15 if diff >= 1 else 0.0) + (0.2 if diff >= 10 else 0.0))
	var dmm := (1.0 + (0.15 if diff >= 2 else 0.0) + (0.2 if diff >= 10 else 0.0))
	var dmg_t := 1.0 + minf(t, Bal.v("enemy/dmg_knee", 480.0)) / Bal.v("enemy/dmg_div", 260.0)
	next_id += 1
	var e := {
		"id": next_id, "type": type, "name": d.name, "tex": d.tex, "pos": pos,
		"hp": d.hp * hpm * enemy_hp_mult, "maxhp": d.hp * hpm * enemy_hp_mult,
		"spd": d.spd * rng.randf_range(0.9, 1.1) * D.THREAT[threat].get("spd", 1.0), "dmg": d.dmg * dmg_t * dmm * enemy_dmg_mult,
		"r": d.r, "r0": d.r, "xp": d.xp, "age": 0.0,
		"evo": false, "elite": role == "elite", "boss": role == "boss", "stun": 0.0,
		"kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": d.ai, "range": d.get("range", 0.0), "cd": d.get("cd", 0.0) * enemy_cd_mult, "cdt": rng.randf() * d.get("cd", 1.0),
		"corrode": d.get("corrode", 0.0), "nerve": d.get("nerve", 0.0), "def": 1.0, "set_t": 0.0, "set_done": false,
		"chest": false, "hidden": false, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		# 状态字段统一在此初始化（Boss 招式 / 假死 / 冲刺 / 流血），避免各处 get() 默认值不一致
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "burst_w": 0.0, "burst_cd": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		# 贴图变体在生成时查一次，绘制时不再每帧拼字符串
		"tex_move": tex.get(d.tex + "_move") != null, "tex_feign": tex.get(d.tex + "_feign") != null, "tex_attack": tex.get(d.tex + "_attack") != null,
		"tex_charge": tex.get(d.tex + "_charge") != null, "tex_death": tex.get(d.tex + "_death") != null,
		"weak": d.get("weak", ""),
		"aggro": Vector2.INF, "corr_t": 0.0, "corr_dmg": 0.0,
	}
	if e.elite:
		e.hp *= Bal.v("enemy/elite_hp_mult", 7.0)
		e.maxhp = e.hp
		e.xp *= Bal.v("enemy/elite_xp_mult", 10.0)
		e.dmg *= Bal.v("enemy/elite_dmg_mult", 1.3)
	if e.boss:
		e.hp = d.hp * (1.0 + t / Bal.v("enemy/boss_hp_time_div", 600.0)) * (1.15 if diff >= 1 else 1.0) * enemy_hp_mult
		e.maxhp = e.hp
		e.spd = d.spd
		e.dmg = d.dmg * dmm * (1.25 if diff >= 10 else 1.0) * enemy_dmg_mult
	if type == "pocket":
		e.burst_at = e.maxhp * 0.85
	if type == "izumik":
		e.hp = e.maxhp * 0.35
		e.invuln = true
	if d.has("ammo"):
		e.ammo = d.ammo
		e.reload_t = 20.0
		e.channel = 0.0
	return e


func _spawn_enemy(type: String, pos: Vector2) -> Dictionary:
	var e := _new_enemy(type, pos)
	enemies.append(e)
	return e


## 补给箱；约 15% 是伪装的箱形恐鱼
func _spawn_chest(pos: Vector2, event_id := "") -> void:
	next_id += 1
	enemies.append({
		"id": next_id, "type": "chest", "name": "补给箱" if event_id == "" else "海嗣祭坛", "tex": "e_chest" if event_id == "" else "e_event", "pos": pos, "hp": 22.0, "maxhp": 22.0,
		"event": event_id,
		"spd": 0.0, "dmg": 0.0, "r": 13.0, "r0": 13.0, "xp": 0.0, "age": 0.0, "evo": false, "elite": false, "boss": false,
		"stun": 0.0, "kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": "static", "range": 0.0, "cd": 0.0, "cdt": 0.0, "corrode": 0.0, "nerve": 0.0, "def": 1.0, "set_t": 0.0, "set_done": true,
		"chest": true, "hidden": event_id == "" and rng.randf() < 0.15, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "burst_w": 0.0, "burst_cd": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		"tex_move": false, "tex_feign": false, "tex_attack": false, "tex_charge": false, "tex_death": false,
	})


## 箱形恐鱼现形
func _reveal_mimic(e: Dictionary) -> void:
	var m := _new_enemy("mimic", e.pos)
	for k in m.keys():
		if k != "id":
			e[k] = m[k]
	e.flash = 0.2
	_show_banner("箱形恐鱼！")
	_add_text(e.pos + Vector2(0, -30), "伪装！", UI.RED, 20)
	Sfx.play("roar", -2.0, 1.3)
	_shake(0.6)
	_sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 14, 260.0)


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
				e.pos = _edge_pos()
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
		_spawn_enemy(["bone", "slider", "stone"][rng.randi() % 3], e.pos + Vector2.from_angle(rng.randf() * TAU) * 20.0)


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
				_enemy_hit(l.dmg, {})
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
				_enemy_hit(b.dmg, b, b["true"])


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
		corrode_pool += dmg * src.corrode * Bal.v("enemy/corrode_mult", 2.0)
		_add_text(ppos + Vector2(14, -64), "侵蚀", Color(0.8, 0.5, 1.0), 13)
	if src.get("nerve", 0.0) > 0.0:
		_add_nerve(src.nerve)


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
		if texts.size() < 80 and rng.randf() < 0.2:
			_add_text(e.pos + Vector2(0, -e.r - 10), "无效", Color(0.6, 0.7, 0.8), 13)
		return
	if e.chest and e.hidden:
		e.hidden = false
		_reveal_mimic(e)
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
		var a := rng.randf() * TAU if dir == Vector2.ZERO else dir.angle() + rng.randf_range(-0.7, 0.7)
		fx.append({"kind": "spark", "pos": pos, "vel": Vector2.from_angle(a) * spd * rng.randf_range(0.4, 1.0),
			"life": rng.randf_range(0.18, 0.32), "max": 0.3, "col": col, "sz": 2.0 if rng.randf() < 0.6 else 4.0})


func _heal(v: float, src: String = "其他") -> void:
	var got: float = minf(v, maxf(0.0, max_hp - hp))
	heal_log[src] = float(heal_log.get(src, 0.0)) + got
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
			_drop(e.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, 18.0), "ingot", 1.0)
		if rng.randf() < 0.3:
			_drop(e.pos + Vector2(10, 6), "oil", 15.0)
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
		_drop(e.pos, "xp", e.xp * xp_mult)
	if rng.randf() < 0.012 * (0.5 if diff >= 3 else 1.0):
		_drop(e.pos + Vector2(8, 0), "oil", 15.0)
	# 特殊道具：磁铁 / 回复（小怪低概率，精英与 Boss 必掉其一）
	if e.elite or e.boss:
		_drop(e.pos + Vector2(-16, 8), "magnet" if rng.randf() < 0.5 else "heal", 1.0)
	elif _count_items() < 3:
		var r := rng.randf()
		if r < 0.0025:
			_drop(e.pos, "magnet", 1.0)
		elif r < 0.006:
			_drop(e.pos, "heal", 1.0)
	var ing: int = D.ENEMIES.get(e.type, {}).get("ingots", 0)
	if e.elite:
		ing = max(ing, rng.randi_range(3, 5))
		_drop(e.pos, "chest", 1.0)
		_drop(e.pos + Vector2(20, 10), "oil", 25.0)
	if e.boss:
		ing = 20
		if not is_same(e, final_boss) and not _boss_alive():
			Sfx.play_overlay("boss_down")   # 最终 Boss 走结算乐句；双 Boss 需全部倒下
		_drop(e.pos + Vector2(-20, 0), "chest", 1.0)
		for j in 12:
			_drop(e.pos + Vector2.from_angle(TAU * j / 12.0) * 30.0, "xp", 20.0)
		# Boss 倒下时清除它召唤的东西
		for o in enemies:
			if (o.type == "tear" and e.type == "ishar") or (o.feed and is_same(o.get("feed_to"), e)):
				o.dead = true
	if diff >= 5 and ing > 0:
		ing = int(floor(ing * 0.7 + rng.randf()))
	for k in ing:
		_drop(e.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(6.0, 26.0), "ingot", 1.0)


func _count_items() -> int:
	var n := 0
	for g in gems:
		if g.kind == "magnet" or g.kind == "heal":
			n += 1
	return n


func _drop(pos: Vector2, kind: String, val: float) -> void:
	if kind == "xp" and gems.size() > 350:
		_gain_xp(val)
		return
	# 2.5D：掉落物带高度，从敌人位置弹出并落地回弹
	var sp := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 70.0)
	var special := kind == "magnet" or kind == "heal" or kind == "chest"
	gems.append({"pos": pos, "kind": kind, "val": val, "dead": false, "mag": false, "mag_t": 0.0,
		"z": 6.0, "vz": rng.randf_range(260.0, 300.0) if special else rng.randf_range(190.0, 260.0), "vel": sp * (0.5 if special else 1.1),
		"special": special, "landed": false, "age": 0.0, "seed": rng.randf() * TAU})


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
func _update_merchant(dt: float) -> void:
	if merchant.is_empty():
		merchant_light.visible = false
		return
	merchant.life -= dt
	# 离开前 15 秒提醒一次（横幅 + 音效），之后倒计时变红闪烁
	if merchant.life <= 15.0 and not merchant.get("warned", false):
		merchant.warned = true
		_show_banner("商人 15 秒后离开 —— 还没交易就快去")
		Sfx.play("ui_move", -2.0, 0.8)
	merchant_light.visible = true
	merchant_light.position = merchant.pos + Vector2(10, -10)
	var d: float = merchant.pos.distance_to(ppos)
	if d < 46.0 and not merchant.near:
		merchant.near = true
		_open_shop()
	elif d > 90.0:
		merchant.near = false
	if merchant.life <= 0.0 and state == S.PLAY:
		merchant = {}
		_show_banner("商人离开了")


## 商人倒计时颜色：最后 15 秒红色闪烁
func _merchant_col() -> Color:
	if merchant.is_empty() or merchant.life > 15.0:
		return UI.GOLD
	return UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(t * 8.0))


func _shop_price(kind: String) -> int:
	match kind:
		"relic":
			return 14
		"heal":
			return int(ceil(6 * shop_price_mult))
		"oil":
			return int(ceil(5 * shop_price_mult))
		"refresh":
			return int(ceil(3 * shop_price_mult))
	return 0


func _roll_shop() -> void:
	shop_items.clear()
	var pool: Array = _relic_pool_ids(true)
	for i in min(3, pool.size()):
		var r: Dictionary = RL[pool[i]]
		shop_items.append({"kind": "relic", "id": pool[i], "name": ("【遭诅】" if r.rarity == "遭诅古物" else "") + rfx.display_name(pool[i]), "desc": rfx.display_desc(pool[i]), "price": rfx.db.price(pool[i], shop_price_mult), "sold": false})
	# 深蓝线：商店多一栏必为遭诅古物（深海的馈赠）
	if rfx.rule("deep_sea") > 0:
		var cursed: Array = pool.filter(func(id): return RL[id].rarity == "遭诅古物" and not shop_items.any(func(it): return it.id == id))
		if not cursed.is_empty():
			var cid: String = cursed[0]
			shop_items.append({"kind": "relic", "id": cid, "name": "【遭诅】" + rfx.display_name(cid), "desc": rfx.display_desc(cid), "price": rfx.db.price(cid, shop_price_mult), "sold": false, "deep": true})
	shop_items.append({"kind": "heal", "id": "heal", "name": "急救包", "desc": "回复 40% 最大生命", "price": _shop_price("heal"), "sold": false})
	shop_items.append({"kind": "oil", "id": "oil", "name": "灯油", "desc": "灯火 +50", "price": _shop_price("oil"), "sold": false})


func _open_shop() -> void:
	if shop_items.is_empty():
		_roll_shop()
	state = S.SHOP
	Sfx.play("relic", -4.0)
	if autotest:
		print("SHOP ", shop_items.map(func(it): return it.name))
	_build_shop_ui()


func _build_shop_ui() -> void:
	nav_sel = clampi(nav_sel, 0, maxi(0, shop_items.size() - 1))
	for c in panel_box.get_children():
		c.queue_free()
	panel_box.add_theme_constant_override("separation", 28 if shop_items.size() <= 5 else 14)
	panel_title_text = "商人  ·  持有源石锭 %d" % ingots
	choice_kind = "shop"
	for c in panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	var vs0: Vector2 = get_viewport_rect().size
	_panel_button("刷新一次  %d" % _shop_price("refresh") if not shop_refreshed else "已刷新过", Vector2(vs0.x / 2 - 250, vs0.y - 100), _refresh_shop, not shop_refreshed and ingots >= _shop_price("refresh"))
	_panel_button("离开  Esc", Vector2(vs0.x / 2 + 70, vs0.y - 100), _close_shop, true)
	for i in shop_items.size():
		var it: Dictionary = shop_items[i]
		var card := Button.new()
		var sep: float = 28.0 if shop_items.size() <= 5 else 14.0
		var cw: float = minf(204.0 if shop_items.size() <= 5 else 180.0, (get_viewport_rect().size.x - 60.0 - sep * (shop_items.size() - 1)) / shop_items.size())
		card.custom_minimum_size = Vector2(cw, 276)
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 50)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		card.set_meta("dy", 178.0)
		card.set_meta("item", it)
		card.modulate.a = 0.0
		card.draw.connect(_draw_shop_card.bind(card, it, i))
		card.mouse_entered.connect(func(): card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(_buy.bind(i))
		var desc := Label.new()
		desc.text = UI.soft(it.desc)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(14, 178)
		desc.size = Vector2(cw - 28, 80)
		desc.clip_text = true
		desc.max_lines_visible = 4
		desc.add_theme_constant_override("line_spacing", 0)
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.88))
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		card.set_meta("desc", desc)
		panel_box.add_child(card)
	panel.visible = true
	panel.queue_redraw()


## 面板底部的文字按钮（商店：刷新 / 离开），鼠标与触屏都能点
func _panel_button(text: String, pos: Vector2, cb: Callable, enabled: bool) -> void:
	var b := Button.new()
	b.set_meta("shopbtn", true)
	b.position = pos
	b.size = Vector2(180, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	b.draw.connect(func():
		var hov: bool = b.is_hovered() and enabled
		var col: Color = UI.GOLD if enabled else Color(0.4, 0.45, 0.5)
		UI.frame(b, Rect2(Vector2.ZERO, b.size), col, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov else 0.0, "alpha": 1.0 if hov else 0.7})
		UI.text(b, font, Vector2(0, 26), text, 15, UI.TEXT if enabled else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, b.size.x))
	b.mouse_entered.connect(b.queue_redraw)
	b.mouse_exited.connect(b.queue_redraw)
	b.pressed.connect(cb)
	panel.add_child(b)


func _draw_shop_card(card: Button, it: Dictionary, i: int) -> void:
	var hov: bool = _card_hot(card, i) and not it.sold
	var col: Color = UI.GOLD
	if it.kind == "relic":
		col = UI.CAT_COL.get(RL[it.id].cat, UI.GOLD)
	elif it.kind == "heal":
		col = Color(0.5, 1.0, 0.6)
	var afford: bool = ingots >= it.price
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	UI.frame(card, r, col, {"t": t, "vines": true, "seed": 40 + i, "vine_k": 0.9 if hov else 0.6, "glow": 1.0 if hov else 0.2, "cut": 10.0, "bracket": 10.0, "alpha": 0.5 if it.sold else 1.0})
	UI.text(card, font, r.position + Vector2(14, 28), str(i + 1), 14, Color(col.r, col.g, col.b, 0.7))
	if it.get("deep", false):
		UI.chip(card, font, r.position + Vector2(r.size.x - 66, 12), "深海馈赠", Color(0.6, 0.5, 1.0), 10)
	var c := r.position + Vector2(r.size.x / 2, 92)
	UI.pedestal(card, c, 38.0, col, t + i, hov)
	var ic: Texture2D = tex.get("relic_" + it.id) if it.kind == "relic" else null
	if ic != null:
		card.draw_texture_rect(ic, Rect2(c - Vector2(32, 32), Vector2(64, 64)), false)
	elif it.kind == "oil":
		card.draw_texture_rect(tex.oil, Rect2(c - Vector2(20, 20), Vector2(40, 40)), false)
	elif it.kind == "heal" and tex.get("pickup_heal") != null:
		card.draw_texture_rect(tex.pickup_heal, Rect2(c - Vector2(20, 20), Vector2(40, 40)), false)
	else:
		UI.text(card, font, c + Vector2(-30, 10), it.name.substr(0, 1), 28, col, HORIZONTAL_ALIGNMENT_CENTER, 60, 3)
	UI.text(card, font, r.position + Vector2(0, 158), it.name, 17, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
	UI.rule(card, r.position + Vector2(30, 166), r.position + Vector2(r.size.x - 30, 166), Color(col.r, col.g, col.b, 0.4))
	if it.sold:
		UI.chip(card, font, r.position + Vector2(r.size.x / 2 - 30, r.size.y - 34), "已售出", UI.SUB, 12)
	else:
		var price_col := Color(1.0, 0.65, 0.35) if afford else Color(0.6, 0.35, 0.35)
		var pr := Rect2(r.position + Vector2(r.size.x / 2 - 34, r.size.y - 36), Vector2(68, 24))
		card.draw_rect(pr, Color(price_col.r, price_col.g, price_col.b, 0.12))
		card.draw_rect(pr, Color(price_col.r, price_col.g, price_col.b, 0.6), false, 1.0)
		card.draw_texture_rect(tex.ingot, Rect2(pr.position + Vector2(8, 5), Vector2(18, 14)), false)
		UI.text(card, font, pr.position + Vector2(32, 18), str(it.price), 15, price_col)


func _buy(i: int) -> void:
	if state != S.SHOP or i >= shop_items.size():
		return
	var it: Dictionary = shop_items[i]
	if it.sold or ingots < it.price:
		Sfx.play("ui_move", -2.0, 0.6)
		return
	ingots -= it.price
	it.sold = true
	if not merchant.is_empty():
		merchant["bought"] = true
	match it.kind:
		"relic":
			_gain_relic(it.id)
		"heal":
			_heal(max_hp * 0.4, "拾取")
		"oil":
			lamp = min(lamp_cap, lamp + 50.0)
	Sfx.play("ui_ok")
	_build_shop_ui()


func _refresh_shop() -> void:
	if shop_refreshed or ingots < _shop_price("refresh"):
		return
	shop_refreshed = true
	ingots -= _shop_price("refresh")
	_roll_shop()
	Sfx.play("relic", -6.0)
	_build_shop_ui()


func _close_shop() -> void:
	for c in panel.get_children():
		if c.has_meta("shopbtn"):
			c.queue_free()
	panel.visible = false
	state = S.PLAY
	Sfx.play("ui_ok", -4.0)
	# 交易过就离开，避免走回去反复触发；等下一次出现
	if not merchant.is_empty() and merchant.get("bought", false):
		_sparks(merchant.pos, Vector2.UP, UI.GOLD, 12, 160.0)
		merchant = {}
		shop_items.clear()
		_show_banner("商人收好源石锭，离开了")


# =====================================================================
# 医疗无人机（保底治疗，2026-09-25）：开局 Lv.1，不占编队位；跟在博士头顶两侧，周期性治疗博士
# Lv.1 每 6 秒 2% → Lv.2 3% / 5 秒 → Lv.3 生命 < 40% 时急救 8%（冷却 20 秒）→ Lv.4 第二架 → Lv.5 4 秒 / 清神经损伤
# =====================================================================
# 上限压到一个精零凯尔希（约 1%/秒），保证带医疗仍然值得（docs/23 §17）
const DRONE_HEAL := [0.0, 0.02, 0.03, 0.03, 0.02, 0.025]
const DRONE_EVERY := [0.0, 6.0, 6.0, 6.0, 6.0, 5.0]


func _update_weapons(dt: float) -> void:
	var dl: int = weapons.get("drone", 0)
	if dl <= 0:
		return
	var want := 2 if dl >= 4 else 1
	while drones.size() < want:
		drones.append({"pos": ppos + Vector2(0, -60), "cd": 2.0 + drones.size() * 2.5, "ang": drones.size() * PI, "beam": 0.0, "face": 1.0})
	drone_rescue_cd = maxf(0.0, drone_rescue_cd - dt)
	for i in drones.size():
		var dr: Dictionary = drones[i]
		dr.ang += dt * 1.2
		var want_pos: Vector2 = ppos + Vector2(cos(dr.ang) * 46.0, -66.0 + sin(dr.ang * 2.0) * 6.0)
		var prev: Vector2 = dr.pos
		dr.pos = dr.pos.lerp(want_pos, clampf(dt * 4.0, 0.0, 1.0))
		if absf(dr.pos.x - prev.x) > 0.3:
			dr.face = signf(dr.pos.x - prev.x)
		dr.beam = maxf(0.0, dr.beam - dt)
		dr.cd -= dt * sp_mult
		if dr.cd <= 0.0:
			dr.cd = DRONE_EVERY[dl]
			if hp < max_hp:
				_drone_heal(dr, max_hp * DRONE_HEAL[dl], dl >= 5)
		# Lv.3：低血急救
		if dl >= 3 and drone_rescue_cd <= 0.0 and hp < max_hp * 0.4 and i == 0:
			drone_rescue_cd = 25.0
			_drone_heal(dr, max_hp * 0.06, dl >= 5)
			_add_text(ppos + Vector2(0, -110), "急救", Color(0.5, 1.0, 0.6), 16)


func _drone_heal(dr: Dictionary, amount: float, cure: bool) -> void:
	_heal(amount, "无人机")
	if cure:
		nerve = 0.0
	dr.beam = 0.35
	_add_text(ppos + Vector2(0, -90), "+%d" % int(amount), Color(0.5, 1.0, 0.6), 14)
	fx.append({"kind": "beam", "a": dr.pos + Vector2(0, 6), "b": ppos + Vector2(0, -24), "life": 0.3, "max": 0.3, "col": Color(0.5, 1.0, 0.6), "w": 2.5})
	if not _fx_sprite("fx_heal_aura_green", ppos + Vector2(0, 6), PX * 1.1, 0.0, false, true):
		for k in 4:
			fx.append({"kind": "cross", "pos": ppos + Vector2(randf_range(-18, 18), randf_range(-40, -8)), "life": 0.8, "max": 0.8, "delay": k * 0.08, "sz": randf_range(3.0, 4.5)})
	Sfx.play("pickup", -14.0, 1.4, 0.05)


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


func _sniper_target(from: Vector2, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var score := -1.0
	for j in _query(from, reach):
		var e: Dictionary = enemies[j]
		if e.dead or e.pos.distance_to(from) > reach:
			continue
		var sc: float = e.hp + (100000.0 if (e.elite or e.boss) else 0.0)
		if sc > score:
			score = sc
			best = e
	return best


func _update_bullets(dt: float) -> void:
	for b in bullets:
		if b.life <= 0.0:
			continue
		# 追踪：导弹 / 紫色法术
		var hm = b.get("home")
		if hm != null:
			if hm.dead:
				if b.has("accel"):
					# 导弹：目标没了就改追导弹附近最近的敌人
					var best = null
					var bd := 460.0
					for j in _query(b.pos, 460.0):
						var q: Dictionary = enemies[j]
						if not q.dead and not q.chest and q.pos.distance_to(b.pos) < bd:
							bd = q.pos.distance_to(b.pos)
							best = q
					b.home = best
				else:
					# 法术追踪弹：从弹体附近重新找目标（原来从博士身边找，常常找不到就直线飞走）
					var nt := _nearest(1, 360.0, b.pos)
					b.home = nt[0] if nt.size() > 0 else null
			else:
				# 匀速转向（2026-09-25）：原来 vel.lerp(want) 转弯时向量变短 → 越绕越慢、显得疲软。
				# 现在速度大小恒定、只转方向；转向角速度随飞行时间增大，保证一定追上、不会绕圈；目标还在就不会中途消失
				var spd: float = b.vel.length() if b.has("accel") else b.get("spd", b.vel.length())
				b["spd"] = spd
				b["age"] = b.get("age", 0.0) + dt
				var turn: float = b.get("turn", 6.0) * (1.0 + b.age * 2.5)
				var a0: float = b.vel.angle()
				var a1: float = rotate_toward(a0, (hm.pos - b.pos).angle(), turn * dt)
				b.vel = Vector2.from_angle(a1) * spd
				b.life = maxf(b.life, 0.2)
		# 导弹：持续加速到最高速并保持（没有目标时直线飞行，不会减速）
		if b.has("accel"):
			var sp: float = minf(b.vel.length() + b.accel * dt, b.vmax)
			b.vel = b.vel.normalized() * sp
		b.pos += b.vel * dt
		b.life -= dt
		if b.kind == "fire" and not b.get("hidden", false):
			b.trail = b.get("trail", 0.0) - dt
			if b.trail <= 0.0:
				b.trail = 0.03
				fx.append({"kind": "spark", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.1 + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
					"sz": 3.0, "life": 0.3, "max": 0.3, "col": Color(0.75, 0.35, 1.0)})
		for j in _query(b.pos, 40.0):
			var e: Dictionary = enemies[j]
			if e.dead or b.pos.distance_to(e.pos) > e.r + b.r:
				continue
			if b.get("hit", {}).has(e.id):
				continue
			_bullet_hit(b, e)
			break


## 子弹命中：按种类结算伤害与特效
func _bullet_hit(b: Dictionary, e: Dictionary) -> void:
	if b.has("src"):
		_hit(b.src, b.get("tags", []))
	else:
		_hit("潮汐弹" if b.kind == "tide" else ("法术援护" if b.kind in ["fire", "arcane"] else "援护"))
	match b.kind:
		"arrow":
			# 狙击：命中流血；扼喉之手处决
			_damage(e, b.dmg)
			if rfx.sniper_execute(e, hit):
				_add_text(e.pos + Vector2(0, -e.r - 12), "处决", Color(1.0, 0.4, 0.4), 15)
				_hit("真实")
				_damage(e, e.hp + 1.0)
			if not e.dead:
				e["bleed"] = 3.0
				e["bleed_dps"] = b.dmg * 0.2
			for k in 7:
				fx.append({"kind": "spark", "pos": e.pos, "vel": b.vel.normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(80, 220),
					"sz": 3.0, "life": 0.4, "max": 0.4, "col": Color(0.85, 0.08, 0.12)})
			fx.append({"kind": "blood", "pos": e.pos + Vector2(0, e.r * 0.6), "life": 2.5, "max": 2.5, "seed": randf() * 10.0})
			_fx_sprite("fx_arrow_hit", e.pos, PX, b.vel.angle())
			if b.get("pierce", false):
				if not b.has("hit_ids"):
					b["hit_ids"] = {}
				b.hit_ids[e.id] = true
			else:
				b.life = 0.0
		"fire":
			# 法术团：爆炸
			for k in _query(b.pos, b.aoe + 20.0):
				var o: Dictionary = enemies[k]
				if not o.dead and o.pos.distance_to(b.pos) < b.aoe + o.r:
					_damage(o, b.dmg)
					if b.get("slow", false):
						o.slow = maxf(o.slow, 1.2)
			# 术师法术团：紫色（对应重绘后的 fx_fire_explode）；导弹：暖黄
			var fc: Color = b.get("fx_col", Color(0.7, 0.3, 1.0) if b.kind == "fire" else Color(1.0, 0.8, 0.4))
			# 美术 V6：爆炸帧条按伤害半径缩放（半径 / 26，限制 1.5–3.0），首帧叠判定圈；干员配色（fx_col）走程序爆炸
			var ename := "fx_fire_explode" if b.kind == "fire" else "fx_missile_explode"
			if not b.has("fx_col") and _fx_sprite(ename, b.pos, clampf(b.aoe / EXPLODE_R_PX, 1.5, 3.0)):
				fx[-1]["ring"] = b.aoe
			else:
				fx.append({"kind": "explode", "pos": b.pos, "r": b.aoe, "life": 0.4, "max": 0.4, "col": fc})
			for k in 6:
				fx.append({"kind": "spark", "pos": b.pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(60, 240), "sz": 3.0, "life": 0.45, "max": 0.45,
					"col": fc.lerp(Color(0.95, 0.85, 1.0) if b.kind == "fire" else Color(1, 0.95, 0.6), randf())})
			if b.has("op"):
				Sfx.op(b.op, "hit", 0.0, 1.0, 0.1)   # 干员法术弹（艾雅法拉熔岩弹）
			else:
				Sfx.play("boom", -14.0 if b.kind == "fire" else -11.0, 1.5, 0.1)
			b.life = 0.0
			# 干员自带的命中后效果（点燃 / 分裂等）
			if b.get("on_hit") != null:
				b.on_hit.bullet_exploded(b)
		"arcane":
			_damage(e, b.dmg)
			if not e.dead:
				e.slow = maxf(e.slow, 1.0)
			# 溅射（铃兰狐火 base.aoe）：主目标之外、半径内的其他敌人吃同样伤害
			if b.get("aoe", 0.0) > 0.0:
				for k in _query(b.pos, b.aoe + 20.0):
					var o: Dictionary = enemies[k]
					if o.id != e.id and not o.dead and o.pos.distance_to(b.pos) < b.aoe + o.r:
						_damage(o, b.dmg)
			if b.has("fx_col") or not _fx_sprite("fx_arcane_hit", e.pos):
				fx.append({"kind": "ring", "pos": e.pos, "r": 22.0, "life": 0.25, "max": 0.25, "col": b.get("fx_col", Color(0.8, 0.45, 1.0))})
			_sparks(e.pos, b.vel, b.get("fx_col", Color(0.85, 0.5, 1.0)), 3, 160.0)
			if b.has("op"):
				Sfx.op(b.op, "hit")   # 铃兰狐火
			b.life = 0.0
		"tide":
			# 潮汐弹：在敌人之间反弹
			_damage(e, b.dmg)
			if b.get("push", false) and not e.boss and not e.dead:
				e.kb += b.vel.normalized() * 220.0
			if not _fx_sprite("fx_tide_hit", e.pos):
				fx.append({"kind": "ring", "pos": e.pos, "r": 20.0, "life": 0.25, "max": 0.25, "col": Color(0.45, 0.8, 1.0)})
			_sparks(e.pos, b.vel, Color(0.6, 0.9, 1.0), 2, 160.0)
			b.hit[e.id] = true
			b.bounces -= 1
			if b.bounces < 0:
				b.life = 0.0
				return
			var nxt: Dictionary = {}
			var bd := 260.0
			for k in _query(e.pos, 260.0):
				var o: Dictionary = enemies[k]
				if o.dead or b.hit.has(o.id):
					continue
				var dd: float = o.pos.distance_to(e.pos)
				if dd < bd:
					bd = dd
					nxt = o
			if nxt.is_empty():
				b.life = 0.0
				return
			b.vel = (nxt.pos - b.pos).normalized() * b.vel.length()
			b.life = 1.0
			Sfx.play("pickup", -16.0, 1.8, 0.1)
		_:
			_damage(e, b.dmg)
			if not _fx_sprite("fx_bullet_hit", b.pos, PX, b.vel.angle()):
				_sparks(b.pos, b.vel, Color(0.7, 1.0, 1.0), 3, 200.0)
			b.life = 0.0


# =====================================================================
# 掉落物、特效
# =====================================================================
func _update_gems(dt: float) -> void:
	for g in gems:
		if g.dead:
			continue
		if g.has("vz") and (g.z > 0.0 or g.vz != 0.0):
			g.vz -= 700.0 * dt
			g.z += g.vz * dt
			g.pos += g.vel * dt
			if g.z <= 0.0:
				g.z = 0.0
				g.vel *= 0.4
				if g.special and not g.landed:
					g.landed = true
					var lc := _item_col(g.kind)
					fx.append({"kind": "ring", "pos": g.pos, "r": 34.0, "life": 0.4, "max": 0.4, "col": lc})
					_sparks(g.pos, Vector2.ZERO, lc, 10, 160.0)
					if g.kind != "chest":
						_add_text(g.pos + Vector2(0, -34), _item_name(g.kind), lc, 15)
					Sfx.play("pickup", -8.0, 0.7, 0.0)
				g.vz = -g.vz * 0.35 if g.vz < -60.0 else 0.0
				if g.vz == 0.0:
					g.vel = Vector2.ZERO
		g.age = g.get("age", 0.0) + dt
		var d: float = g.pos.distance_to(ppos)
		if g.get("special", false) and g.kind != "chest" and d > 40.0 and not g.mag:
			continue
		# 掉落先弹出落地、停留一瞬（让玩家看见），再被吸向水月：越吸越快
		var settled: bool = g.get("z", 0.0) <= 0.0 and g.age > 0.4
		if g.mag or (settled and d < pickup * (1.2 if lamp >= 70.0 else (0.7 if lamp < 30.0 else 1.0))):
			g.mag = true
			g["mag_t"] = g.get("mag_t", 0.0) + dt
			g.z = 0.0
			g.pos = g.pos.move_toward(ppos + Vector2(0, -12), (240.0 + 1300.0 * g.mag_t) * dt)
			d = g.pos.distance_to(ppos + Vector2(0, -12))
		if d < 20.0:
			g.dead = true
			match g.kind:
				"xp":
					_gain_xp(g.val)
					xp_flash = 0.3
					_sparks(ppos + Vector2(0, -22), Vector2.ZERO, UI.CYAN if g.val < 5.0 else Color(0.85, 0.6, 1.0), 3 if g.val < 5.0 else 7, 150.0)
					Sfx.play("pickup", -14.0, 1.0 + min(xp / xp_need, 1.0) * 0.4, 0.03)
				"oil":
					var add: float = g.val * oil_mult
					lamp = min(lamp_cap, lamp + add)
					Sfx.play("oil", -4.0)
					_add_text(ppos + Vector2(0, -90), "灯火 +%d" % int(add), UI.GOLD, 16)
				"chest":
					pending_chests += 1
				"ingot":
					ingots += int(g.val)
					Sfx.play("pickup", -10.0, 1.6, 0.05)
				"magnet":
					# 磁铁：吸取全场的经验、灯油和源石锭
					for o in gems:
						if not o.dead and (o.kind == "xp" or o.kind == "oil" or o.kind == "ingot"):
							o.mag = true
					fx.append({"kind": "ring", "pos": ppos, "r": 420.0, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.45, 0.5)})
					_add_text(ppos + Vector2(0, -90), "磁铁：吸取全场掉落", Color(1.0, 0.55, 0.6), 17)
					Sfx.play("relic", -4.0, 1.2, 0.0)
				"heal":
					var hv := max_hp * 0.3
					_heal(hv, "事件")
					fx.append({"kind": "ring", "pos": ppos, "r": 90.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.65)})
					_sparks(ppos + Vector2(0, -20), Vector2.ZERO, Color(0.5, 1.0, 0.65), 16, 200.0)
					_add_text(ppos + Vector2(0, -90), "+%d 生命" % int(hv), Color(0.5, 1.0, 0.65), 18)
					Sfx.play("relic", -4.0, 1.5, 0.0)


func _item_col(kind: String) -> Color:
	match kind:
		"magnet":
			return Color(1.0, 0.5, 0.55)
		"heal":
			return Color(0.5, 1.0, 0.65)
		"chest":
			return UI.GOLD
	return UI.CYAN


func _item_name(kind: String) -> String:
	return {"magnet": "磁铁", "heal": "回复药剂"}.get(kind, "")


func _gain_xp(v: float) -> void:
	if demo_op != "":
		return
	xp += v
	while xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = Bal.v("xp/a", 24.0) + level * Bal.v("xp/b", 8.0) + floor(level * level * Bal.v("xp/c", 0.8))
		pending_levelups += 1
		lv_times.append(int(t))
		_levelup_fx()


## 升级演出：金色光环 + 冲击波推开周围敌人 + 头顶字样，0.5 秒后再弹出选项
func _levelup_fx() -> void:
	lvup_show = 1.3
	hud_lv_flash = 1.0
	if lvup_delay <= 0.0:
		lvup_delay = 0.5
	invuln = max(invuln, 0.9)
	fx.append({"kind": "ring", "pos": ppos, "r": 150.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4)})
	fx.append({"kind": "ring", "pos": ppos, "r": 80.0, "life": 0.35, "max": 0.35, "col": Color(0.6, 1.0, 0.95)})
	_sparks(ppos + Vector2(0, -20), Vector2.ZERO, Color(1.0, 0.85, 0.45), 18, 320.0)
	for e in _query(ppos, 170.0):
		var en: Dictionary = enemies[e]
		if en.boss or en.chest:
			continue
		var d: Vector2 = en.pos - ppos
		en.kb = d.normalized() * 480.0 if d.length() > 0.1 else Vector2.RIGHT * 480.0
	Sfx.play("levelup", -6.0, 1.3, 0.0)


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
	panel.draw.connect(_draw_panel_bg)
	parent.add_child(panel)
	panel_box = HBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 28)
	panel_box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_box.offset_top = 175
	panel_box.offset_bottom = -120
	panel.add_child(panel_box)


func _draw_panel_bg() -> void:
	var vs := panel.size
	panel.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.05, 0.8))
	var title_col := UI.GOLD if choice_kind in ["relic", "shop"] else UI.GLOW
	# 从上方斜射的光束
	for i in 4:
		var x := vs.x * 0.2 + i * vs.x * 0.2 + sin(t * 0.25 + i) * 30.0
		var w := 50.0 + 24.0 * sin(t * 0.4 + i * 1.7)
		panel.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + w, 0), Vector2(x + w * 2.4 - 160, vs.y), Vector2(x - 160, vs.y)]),
			Color(title_col.r, title_col.g, title_col.b, 0.025 + 0.012 * sin(t * 0.7 + i)))
	# 标题栏
	var band := Rect2(vs.x / 2 - 360, 56, 720, 72)
	UI.frame(panel, band, title_col, {"t": t, "vines": true, "seed": 11, "vine_k": 0.6, "cut": 10.0})
	UI.caustic(panel, Rect2(band.position + Vector2(20, 8), Vector2(band.size.x - 40, 18)), t, title_col)
	var en_label := "RELIC" if choice_kind == "relic" else ("EVENT" if choice_kind == "event" else "LEVEL UP")
	if choice_kind == "shop":
		en_label = "MERCHANT"
	if choices.size() > 0 and choices[0].kind == "recruit":
		en_label = "RECRUIT"
	var w := font.get_string_size(en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + en_label.length() * 4.0
	UI.en(panel, font, Vector2(vs.x / 2 - w / 2, 80), en_label, 12, title_col, 4.0)
	UI.heading(panel, font, Vector2(vs.x / 2, 106), panel_title_text, 26, title_col, 300.0)
	var hint := ("点击或按 1–5 购买 · " + ("已刷新过" if shop_refreshed else "F 刷新一次（%d 源石锭）" % _shop_price("refresh")) + " · Esc 离开") if choice_kind == "shop" else "点击卡片，或按 1 / 2 / 3 选择"
	if Pad.using:
		hint = ("←→ 选择 · Ⓐ 购买 · " + ("已刷新过" if shop_refreshed else "Ⓨ 刷新一次（%d 源石锭）" % _shop_price("refresh")) + " · Ⓑ 离开") if choice_kind == "shop" else "←→ 选择 · Ⓐ 确认"
	UI.text(panel, font, Vector2(0, vs.y - 46), hint, 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _show_choices(title: String, opts: Array, kind: String) -> void:
	choices = opts
	choice_kind = kind
	nav_sel = 0
	state = S.CHOICE
	panel_title_text = title
	Sfx.play("relic" if kind == "relic" else "levelup", -2.0, 1.0, 0.0)
	for c in panel_box.get_children():
		c.queue_free()
	for i in opts.size():
		var o: Dictionary = opts[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(280, 304)
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 70)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		card.modulate.a = 0.0
		card.draw.connect(_draw_card.bind(card, o, i))
		card.mouse_entered.connect(func(): Sfx.play("ui_move", -6.0); card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(_pick.bind(i))
		var desc := Label.new()
		desc.text = UI.soft(o.desc)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(28, 212)
		desc.size = Vector2(224, 84)
		desc.clip_text = true
		desc.max_lines_visible = 4
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.88))
		desc.add_theme_constant_override("line_spacing", 0)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		card.set_meta("desc", desc)
		card.set_meta("dy", 212.0)
		panel_box.add_child(card)
	panel.visible = true
	panel.queue_redraw()


## 卡片动画：入场（依次上浮淡入，轻微回弹）+ 悬停抬起；描述文字跟随卡框移动
func _animate_cards(dt: float) -> void:
	if not panel.visible:
		return
	var now := Time.get_ticks_msec()
	for card in panel_box.get_children():
		if not card.has_meta("born"):
			continue
		var age := (now - int(card.get_meta("born"))) / 1000.0
		var k := clampf(age / 0.32, 0.0, 1.0)
		# easeOutBack
		var c1 := 1.7
		var e := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3) + c1 * pow(k - 1.0, 2)
		var sold: bool = card.has_meta("item") and card.get_meta("item").get("sold", false)
		var target := -10.0 if (_card_hot(card as Button, card.get_index()) and not sold) else 0.0
		var lift: float = lerpf(card.get_meta("lift"), target, clampf(dt * 18.0, 0.0, 1.0))
		card.set_meta("lift", lift)
		var oy := (1.0 - e) * 60.0 + lift
		card.set_meta("oy", oy)
		card.modulate.a = clampf(age / 0.2, 0.0, 1.0)
		var desc: Label = card.get_meta("desc", null)
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


func _draw_card(card: Button, o: Dictionary, i: int) -> void:
	var hov := _card_hot(card, i)
	var col := _card_color(o)
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	UI.frame(card, r, col, {"t": t, "vines": true, "seed": 20 + i, "vine_k": 1.0 if hov else 0.75, "glow": 1.0 if hov else 0.25, "cut": 12.0, "bracket": 12.0})
	# 顶部分类标签
	var cat := "成长  GROWTH"
	if o.has("cat"):
		cat = o.cat
	elif o.kind == "relic":
		cat = RL[o.id].cat + "  ·  " + RL[o.id].rarity
	elif o.kind == "recruit":
		cat = "招募  " + o.get("cls", "")
	elif o.kind == "prog":
		cat = ("精英化  ELITE" if o.get("elite", 0) > 0 else "干员深度  OPERATOR")
	elif o.kind == "weapon":
		cat = "支援  " + D.WEAPONS[o.id].en
	UI.chip(card, font, r.position + Vector2(16, 16), cat, col, 11)
	UI.text(card, font, r.position + Vector2(r.size.x - 40, 34), str(i + 1), 16, Color(col.r, col.g, col.b, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 24)
	# 图标底座
	var c := r.position + Vector2(r.size.x / 2, 118)
	UI.pedestal(card, c, 44.0, col, t + i, hov)
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
		var ks: float = 2.0 if idle.fh <= 48 else 72.0 / idle.fh
		var asz := Vector2(idle.fw, idle.fh) * ks
		card.draw_texture_rect_region(idle.tex, Rect2(c - asz / 2.0 + Vector2(0, bob + 4), asz), Rect2(0, 0, idle.fw, idle.fh))
	elif ic != null:
		card.draw_texture_rect(ic, Rect2(c - Vector2(32, 32) + Vector2(0, bob), Vector2(64, 64)), false)
	else:
		UI.text(card, font, c + Vector2(-40, 13 + bob), glyph, 34, col, HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	# 名称 + 分隔
	var nm := name
	if o.kind == "relic":
		nm = RL[o.id].name
	UI.text(card, font, r.position + Vector2(0, 196), nm, 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3)
	UI.rule(card, r.position + Vector2(36, 206), r.position + Vector2(r.size.x - 36, 206), Color(col.r, col.g, col.b, 0.45))
	# 底部：暗色水印字 + 选择提示
	card.draw_string(font, r.position + Vector2(r.size.x - 70, r.size.y - 14), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color(col.r, col.g, col.b, 0.06))
	if hov:
		UI.en(card, font, r.position + Vector2(r.size.x / 2 - 30, r.size.y - 16), "SELECT", 11, col, 3.0)


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


## 招募卡：data/characters 里未在队、且允许招募（JSON 无 "recruitable": false）的干员
func _recruit_cards() -> Array:
	var opts: Array = []
	# --norecruit（仅 --balance）：单人打满全程，测单个干员的纯个人数值（docs/27 §6）
	if squad.is_full() or (balance and OS.get_cmdline_user_args().has("--norecruit")):
		return opts
	for cid in Character.list_ids():
		if squad.has(cid):
			continue
		var d: Dictionary = Character.load_def(cid)
		if not d.get("recruitable", true):
			continue
		opts.append({"kind": "recruit", "id": cid, "name": d.get("name", cid), "desc": d.get("gallery", {}).get("desc", d.get("attack", {}).get("desc", "")), "cls": d.get("class", "")})
	return opts


func _open_recruit() -> bool:
	var opts := _recruit_cards()
	if opts.is_empty():
		return false
	opts.shuffle()
	_show_choices("招募干员", opts.slice(0, 3), "level")
	return true


func _open_levelup() -> void:
	var want: int = 3 + rfx.rule("four_choices")
	var picks: Array = []
	# ---- 招募（docs/23 §6）：Lv.5 起进池；保底：Lv.6 仍只有 1 人 / Lv.12 仍不满 3 人 → 本次必出招募
	var recruit: Array = _recruit_cards()
	var must_recruit: bool = not recruit.is_empty() and ((level >= Bal.vi("levelup/force_recruit_level_1", 6) and squad.size() <= 1) or (level >= Bal.vi("levelup/force_recruit_level_3", 12) and squad.size() < Squad.REGULAR_MAX))
	if must_recruit:
		recruit.shuffle()
		_show_choices("招募干员", recruit.slice(0, want), "level")
		return
	# ---- 干员深度：Lv.2–4 只养开局干员；之后至少一张
	var deep: Array = []
	for o in squad.ops:
		if level <= 4 and o != ch:
			continue
		for c in o.deep_cards():
			if c.kind == "prog" and not c.get("avail", true):
				continue
			deep.append(c)
	deep.shuffle()
	if not deep.is_empty():
		picks.append(deep[0])
		# 编队 ≥ 2 人时约一半的升级给第二张深度卡（换一名干员）
		if squad.size() >= 2 and rng.randf() < Bal.v("levelup/second_deep_chance", 0.5):
			for rc in deep.slice(1):
				if rc.get("op", "") != deep[0].get("op", ""):
					picks.append(rc)
					break
	# ---- 招募卡：Lv.5 起、编队未满时约 45% 出一张
	if level >= Bal.vi("levelup/recruit_from_level", 5) and not recruit.is_empty() and rng.randf() < Bal.v("levelup/recruit_chance", 0.45):
		picks.append(recruit[rng.randi() % recruit.size()])
	# ---- 博士被动 / 全队被动：种类各上限 4
	var passives: Array = doctor.passive_cards("doctor") + doctor.passive_cards("squad")
	# 医疗无人机升级（保底治疗）：和被动卡同池的常规选项，没满级就一直在池里（用户决定，2026-09-25）
	var wl: int = weapons.get("drone", 0)
	if wl < 5:
		var W: Dictionary = D.WEAPONS.drone
		passives.append({"kind": "weapon", "id": "drone", "name": "%s  Lv.%d" % [W.name, wl + 1], "desc": W.lv[wl], "wlv": wl + 1})
	passives.shuffle()
	for c in passives:
		if picks.size() >= want:
			break
		picks.append(c)
	# ---- 深度卡补位，再不够用填充卡
	var di := 1
	while picks.size() < want and di < deep.size():
		if not picks.has(deep[di]):
			picks.append(deep[di])
		di += 1
	var fillers: Array = doctor.filler_cards()
	fillers.shuffle()
	var fi := 0
	while picks.size() < want and fi < fillers.size():
		picks.append(fillers[fi])
		fi += 1
	picks.shuffle()
	for c in picks.slice(0, want):
		if c.kind == "prog":
			dbg_offer[c.op] = dbg_offer.get(c.op, 0) + 1
	_show_choices("升级！ Lv.%d" % level, picks.slice(0, want), "level")


## 成长项定义：博士 / 全队被动（doctor.PASSIVES）
func _growth_def(gid: String) -> Dictionary:
	if doctor.PASSIVES.has(gid):
		return doctor.PASSIVES[gid]
	return {"name": gid, "desc": "", "max": 1}


## 全队的干员深度卡：每个干员的下一个成长节点（条件未满足的精英化卡不出）+ 子类追加卡
func _deep_cards() -> Array:
	var out: Array = []
	for o in squad.ops:
		for c in o.deep_cards():
			if c.kind == "prog" and not c.get("avail", true):
				continue
			out.append(c)
	return out


## 可选藏品：已实装、未拥有、满足前置；按稀有度加权排序（基础 60 / 稀有 26 / 核心 12 / 升华 3，升华 7:00 后才出）
func _relic_pool_ids(for_shop := false) -> Array:
	var cands: Array = rfx.db.implemented().filter(func(r): return rfx.can_offer(r, for_shop))
	var weighted: Array = []
	for r in cands:
		var w := 0.0
		match r.rarity:
			"基础": w = 60.0
			"稀有": w = 26.0
			"核心": w = 12.0
			"升华": w = 3.0 if t > 420.0 else 0.0
			"遭诅古物": w = 8.0 if for_shop else 0.0
		if w <= 0.0:
			continue
		# 7:00 前护盾系更容易出现
		if t < 420.0 and r.tags.has("shield"):
			w *= 1.6
		# 犹疑 (240)：稀有 / 核心 权重 +30%
		if rfx.rule("rare_weight") > 0 and r.rarity in ["稀有", "核心"]:
			w *= 1.3
		# 已拥有的藏品升级：出现率减半
		if relics.has(r.id):
			w *= 0.5
		weighted.append([-log(rng.randf() + 0.0001) / w, r.id])
	weighted.sort_custom(func(a, b): return a[0] < b[0])
	return weighted.map(func(x): return x[1])


func _open_relic_choice() -> void:
	var pool: Array = []
	for rid in _relic_pool_ids():
		var r: Dictionary = RL[rid]
		pool.append({"kind": "relic", "id": rid, "name": "【%s】%s" % [r.cat, rfx.display_name(rid)], "desc": rfx.display_desc(rid)})
	if pool.is_empty():
		pending_chests = 0
		ingots += 12
		_add_text(ppos + Vector2(0, -90), "藏品已集齐 · 源石锭 +12", UI.GOLD, 16)
		return
	_show_choices("获得藏品", pool.slice(0, 3 + rfx.rule("four_choices")), "relic")


func _pick(i: int) -> void:
	if state != S.CHOICE or i >= choices.size():
		return
	var o: Dictionary = choices[i]
	match o.kind:
		"event":
			endg.pick(o)
		"growth":
			growth[o.id] = growth.get(o.id, 0) + 1
			if not doctor.apply_passive(o.id):
				var gop = squad.get_op(o.get("op", ch.id))
				if gop != null:
					gop._apply_growth(o.id)
		"filler":
			doctor.apply_filler(o.id)
		"prog":
			dbg_pick[o.op] = dbg_pick.get(o.op, 0) + 1
			var pop = squad.get_op(o.op)
			if pop != null:
				pop.advance(o.get("choice", ""))
				fx.append({"kind": "ring", "pos": pop.pos, "r": 90.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.9, 1.0)})
				if o.get("elite", 0) > 0:
					_show_banner("%s 精英化%s" % [pop.display_name(), ["", "一", "二"][o.elite]])
		"recruit":
			var nop = squad.add(o.id)
			if nop != null:
				_show_banner("「%s」加入编队" % nop.display_name())
				fx.append({"kind": "ring", "pos": ppos, "r": 120.0, "life": 0.5, "max": 0.5, "col": Color(0.55, 0.9, 0.55)})
		"relic":
			_gain_relic(o.id)
		"weapon":
			weapons[o.id] = o.wlv
			var W: Dictionary = D.WEAPONS[o.id]
			_show_banner("「%s」升至 Lv.%d" % [W.name, o.wlv])
			fx.append({"kind": "ring", "pos": ppos, "r": 110.0, "life": 0.45, "max": 0.45, "col": W.col})
	if choice_kind == "relic":
		pending_chests -= 1
	else:
		pending_levelups -= 1
	panel.visible = false
	Sfx.play("ui_ok", -4.0)
	state = S.PLAY
	if not tab_hinted and not tab_used:
		tab_hinted = true
		tab_hint = 6.0
	_check_pending()


func _apply_relic(id: String) -> void:
	rfx.apply(id)
	if not Cfg.seen_relics.has(id):
		Cfg.seen_relics.append(id)
		Cfg.save()


## 获得藏品的唯一入口：登记、生效、重算结局
func _gain_relic(id: String) -> void:
	if not relics.has(id):
		relics.append(id)
	_apply_relic(id)
	if id == "222" and not knight.alive and not knight.fallen:
		knight.spawn()
	elif id == "221" and knight.alive:
		knight.leave()
	endg.on_relic(id)


# =====================================================================
# 绘制
# =====================================================================
func _update_visuals(dt: float) -> void:
	var bob: float = -abs(sin(walk_t)) * 2.0 if moving else 0.0
	sprite.position = (ppos + Vector2(0, bob + 6)).round()
	sprite.flip_h = facing < 0.0
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
const EXPLODE_R_PX := 26.0


## 激光三段：起点（枪口）+ 平铺中段（末段按长度裁切，不拉伸）+ 末端光斑
func _spr_rot(name: String, frame: int, pos: Vector2, ang: float, scale := PX, col := Color.WHITE, anchor_px := Vector2(-1, -1), flip := false) -> void:
	var tx: Texture2D = tex.get(name)
	if tx == null:
		return
	var frames: int = V6_FRAMES.get(name, [1, 0.0])[0]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var an := anchor_px if anchor_px.x >= 0.0 else Vector2(fw, fh) / 2.0
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
			var ic := _item_col(g.kind)
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
	_spr("shadow", 1, 0, ppos + Vector2(0, 6), PX * 1.3)
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
	dl.append([ppos.y + 6.0, 2, null])
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
	var want := "idle"
	if state == S.DEAD:
		want = "death"
	elif hurt_flash > 0.05:
		want = "hurt"
	elif moving:
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
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + sprite.offset, Vector2(fw, fh)), src, sprite.modulate)
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

	# 左上：干员卡（深海面板 + 藤蔓；等级环即经验环）
	var o := Vector2(16, 16)
	var lf := hud_lv_flash
	var bc := UI.GLOW.lerp(UI.GOLD, lf).lerp(Color(0.8, 1.6, 1.8), xp_flash * 0.7)
	UI.frame(hud, Rect2(o, Vector2(344, 100)), bc, {"t": t, "vines": true, "seed": 7, "glow": 0.5 + lf})
	# 等级环：环上进度 = 经验
	var lc0 := o + Vector2(44, 50)
	UI.ring(hud, lc0, 27.0 + 4.0 * lf, xp / xp_need, bc, lf > 0.2)
	var lvs := 24 if level < 10 else 20
	UI.text(hud, font, lc0 + Vector2(-30, 8 + (1 if level >= 10 else 0)), str(level), int(lvs * (1.0 + 0.3 * lf)), Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, 60, 4)
	# 名字、精英阶段
	UI.text(hud, font, o + Vector2(84, 32), doctor.name(), 19, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	UI.en(hud, font, o + Vector2(130, 31), doctor.def.get("en", "DOCTOR"), 10, UI.CYAN_DIM, 3.0)
	UI.chip(hud, font, o + Vector2(264, 18), "编队 %d/%d" % [squad.size(), squad.cap()], UI.CYAN_DIM, 11)
	# 生命
	var hs := Vector2(sin(t * 90.0), cos(t * 70.0)) * 3.0 * hp_shake / 0.35
	var hbr := Rect2(o + Vector2(84, 44) + hs, Vector2(196, 12))
	var low := hp / max_hp < 0.3
	var hpc: Color = UI.RED.lerp(Color(1, 0.8, 0.8), 0.5 + 0.5 * sin(t * 10.0)) if low else Color(0.35, 0.9, 0.75)
	UI.gbar(hud, hbr, hp / max_hp, hpc, 10, hp_trail / max_hp)
	UI.text(hud, font, o + Vector2(288, 55) + hs, "%d" % int(hp), 14, UI.RED if low else UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	# 护盾层：血条上方一排小菱形
	for q in shield_max:
		var sp := o + Vector2(90 + q * 12, 37)
		UI.diamond(hud, sp, 4.0, Color(0.5, 0.85, 1.0) if q < shield else Color(0.08, 0.14, 0.18), Color(0.6, 0.9, 1.0, 0.8))
	# 灯火：暖色分段条 + 30 / 70 刻度
	var lc := UI.GOLD if lamp >= 30.0 else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(t * 8.0))
	var lbr := Rect2(o + Vector2(84, 64), Vector2(196, 9))
	UI.gbar(hud, lbr, lamp / 100.0, lc, 10)
	for tv in [30.0, 70.0]:
		var tx: float = lbr.position.x + lbr.size.x * tv / 100.0
		hud.draw_rect(Rect2(tx, lbr.position.y - 2, 1, lbr.size.y + 4), Color(1, 1, 1, 0.8))
	# 灯火火苗小图标
	var fl := 0.5 + 0.5 * sin(t * 12.0)
	hud.draw_colored_polygon(PackedVector2Array([o + Vector2(74, 73), o + Vector2(70, 67), o + Vector2(74, 60 - 2 * fl), o + Vector2(78, 67)]), lc)
	hud.draw_colored_polygon(PackedVector2Array([o + Vector2(74, 72), o + Vector2(72, 68), o + Vector2(74, 65), o + Vector2(76, 68)]), Color(1, 1, 0.85))
	UI.text(hud, font, o + Vector2(288, 73), "%d" % int(lamp), 13, lc, HORIZONTAL_ALIGNMENT_LEFT, -1, 2)
	# 神经损伤 / 侵蚀
	if nerve > 1.0:
		UI.gbar(hud, Rect2(o + Vector2(84, 80), Vector2(196, 4)), nerve / 100.0, Color(1.0, 0.45, 0.85))
		UI.en(hud, font, o + Vector2(288, 86), "NERVE", 8, Color(1.0, 0.5, 0.9), 1.0)
	if corrode_pool > 0.5:
		UI.text(hud, font, o + Vector2(330, 86), "蚀", 11, Color(0.8, 0.5, 1.0))
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
			UI.text(hud, font, edge + Vector2(-60, lab_y), "商人  %dm · %ds" % [dist, int(merchant.life)], 13, _merchant_col(), HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
		else:
			# 在画面内：头顶跳动的箭头
			var big_m: bool = tex.merchant != null and tex.merchant.get_height() >= 40
			var head: float = (84.0 if big_m else 36.0) * ct.get_scale().y
			var hp2 := sp + Vector2(0, -head - 12.0 - bounce)
			hud.draw_colored_polygon(PackedVector2Array([hp2 + Vector2(0, 12), hp2 + Vector2(-10, -2), hp2 + Vector2(10, -2)]), UI.GOLD)
			UI.text(hud, font, hp2 + Vector2(-60, -8), ("商人 %ds" if merchant.life > 15.0 else "商人即将离开 %ds") % int(merchant.life), 13, _merchant_col(), HORIZONTAL_ALIGNMENT_CENTER, 140, 3)
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
	_draw_minimap(vs)
	var st_txt := ""
	var st_col := UI.GOLD
	if lamp <= 0.0:
		st_txt = "灯火熄灭 · 持续受伤"
		st_col = UI.RED
	elif lamp < 30.0:
		st_txt = "暗潮涌动 · 敌人更快更凶更多 · 拾取 -30%"
		st_col = Color(1, 0.55, 0.45)
	elif lamp >= 70.0:
		st_txt = "灯火充盈 · 技力 +30% · 拾取 +20%"
	else:
		st_txt = "灯火照亮 · 光中敌人受伤 +25%"
		st_col = Color(1.0, 0.85, 0.6)
	UI.chip(hud, font, o + Vector2(0, 108), st_txt, st_col, 12)
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
		elif zone_state == 1:
			UI.text(hud, font, Vector2(0, 92), "黑潮将至  %d" % int(ceil(20.0 - zone_t)), 15, Color(0.9, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
		elif zone_state == 2:
			UI.text(hud, font, Vector2(0, 92), "安全区收缩中", 15, Color(0.9, 0.6, 1.0, 0.6 + 0.4 * sin(t * 6.0)), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)

	# 顶部中央：计时框（水波光带 + 源石锭）
	var mm := int(t) / 60
	var ss := int(t) % 60
	var tf := Rect2(vs.x / 2 - 110, 10, 220, 66)
	UI.frame(hud, tf, UI.GLOW, {"t": t, "cut": 8.0, "bracket": 8.0})
	UI.caustic(hud, Rect2(tf.position + Vector2(8, 6), Vector2(tf.size.x - 16, 20)), t, UI.GLOW)
	UI.text(hud, font, Vector2(tf.position.x, 42), "%02d:%02d" % [mm, ss], 30, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, tf.size.x, 3)
	# 威胁等级：文字 + 进度条（到下一级的时间）
	var tr: Dictionary = D.THREAT[threat]
	var tfrac: float = 1.0
	if threat < D.THREAT.size() - 1:
		tfrac = clampf((t - tr.t) / (D.THREAT[threat + 1].t - tr.t), 0.0, 1.0)
	var tcol := Color(0.9, 0.45, 1.0).lerp(Color(1.0, 0.3, 0.4), float(threat) / (D.THREAT.size() - 1))
	UI.text(hud, font, Vector2(tf.position.x, 62), ("击杀 %d  ·  威胁 %s %s" % [kills, ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][threat], tr.name]) + (("  ·  难度 %d" % diff) if diff > 0 else ""), 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, tf.size.x, 2)
	UI.gbar(hud, Rect2(tf.position.x + 16, tf.position.y + 57, tf.size.x - 32, 4), tfrac, tcol, 6)
	# 源石锭标签
	var ir := Rect2(tf.end.x + 10, 18, 74, 26)
	UI.frame(hud, ir, Color(1.0, 0.65, 0.35), {"cut": 4.0, "bracket": 5.0})
	hud.draw_texture_rect(tex.ingot, Rect2(ir.position + Vector2(8, 6), Vector2(18, 14)), false)
	UI.text(hud, font, ir.position + Vector2(32, 19), str(ingots), 15, Color(1.0, 0.7, 0.4))

	# 右上：藏品 + 当前结局
	_draw_relic_tray(Vector2(vs.x - 16, 16))
	if ending != "standard" or Cfg.endings_cleared.size() > 0:
		UI.text(hud, font, Vector2(vs.x - 236, 92 + 38 * maxi(1, int(ceil(relics.size() / 8.0)))), endg.cur_name(), 12, endg.cur_col(), HORIZONTAL_ALIGNMENT_RIGHT, 220, 2)

	# Boss 血条
	var bby := 0.0
	for shown in bosses:
		if shown.dead:
			continue
		var bw := 620.0
		var bx := vs.x / 2 - bw / 2
		hud.draw_set_transform(Vector2(0, bby), 0.0, Vector2.ONE)
		bby += 54.0
		UI.frame(hud, Rect2(bx - 12, 80, bw + 24, 48), Color(1.0, 0.35, 0.5), {"cut": 8.0, "bracket": 8.0})
		UI.text(hud, font, Vector2(bx, 100), shown.name, 16, Color(1, 0.6, 0.7))
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
		UI.text(hud, font, Vector2(bx + bw - 400, 100), sub, 13, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 400)
		UI.bar(hud, Rect2(bx, 108, bw, 10), shown.hp / shown.maxhp, Color(0.45, 0.6, 0.7) if shown.invuln else Color(0.85, 0.2, 0.4), 20)
		if shown.type == "ishar" and shown.phase == 1:
			hud.draw_rect(Rect2(bx, 120, bw * shown.charge / 100.0, 3), UI.PURPLE)
		hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 右下：技能与援护干员
	_draw_squad_hud(Vector2(vs.x - 16, vs.y - 16))

	# 横幅通知
	if banner_t > 0.0:
		var a: float = clamp(banner_t, 0.0, 1.0)
		var by := vs.y * 0.24
		hud.draw_rect(Rect2(0, by - 30, vs.x, 46), Color(0.01, 0.04, 0.06, 0.8 * a))
		hud.draw_line(Vector2(vs.x * 0.2, by - 30), Vector2(vs.x * 0.8, by - 30), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6 * a), 1.0)
		hud.draw_line(Vector2(vs.x * 0.2, by + 16), Vector2(vs.x * 0.8, by + 16), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6 * a), 1.0)
		UI.text(hud, font, Vector2(0, by), banner, 22, Color(1, 0.93, 0.8, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
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
			UI.panel(hud, box, Color(0.02, 0.07, 0.1, 0.85 * ha), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, (0.4 + 0.5 * pulse) * ha), 8.0)
			var kc := Rect2(cx - 132, y - 14, 50, 24)
			hud.draw_rect(kc, Color(0.1, 0.25, 0.3, ha))
			hud.draw_rect(kc, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, ha), false, 1.5)
			UI.text(hud, font, kc.position + Vector2(0, 18), Pad.hint("Tab", "SELECT"), 14 if not Pad.using else 11, Color(1, 1, 1, ha), HORIZONTAL_ALIGNMENT_CENTER, kc.size.x)
			UI.text(hud, font, Vector2(cx - 72, y + 4), "查看博士与编队的属性", 15, Color(0.85, 0.95, 0.95, ha))

	_draw_relic_tooltip(vs)
	touch.draw_hud(vs)
	_draw_status_bar(vs)
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
		"你操控的是博士 —— 场上唯一会受伤的人。干员们跟在身边，普攻与三个技能全自动出手；你只需要用 WASD 移动：走位、拉怪、躲弹幕、抢掉落。站在灯光里打，敌人受到的伤害 +25%。",
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
	UI.en(hud, font, r.position + Vector2(176, 48), doctor.def.get("en", "DOCTOR") + "  ·  STATUS", 12, UI.CYAN, 3.0)
	var cx0 := r.position.x + 350
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
	UI.gbar(hud, Rect2(b0.position.x + 70, y, 180, 10), hp / max_hp, Color(0.35, 0.9, 0.75), 10)
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
			UI.text(hud, font, gc + Vector2(0, 26), _growth_def(gid).name.substr(0, 1), 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 38)
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
			var gd: Dictionary = _growth_def(cellinfo[2])
			_draw_tooltip(vs, cr2, "%s  ×%d" % [gd.name, growth[cellinfo[2]]], "成长 · 上限 %d" % gd.max, gd.desc, "growth_" + cellinfo[2], UI.GLOW)
		break


## 小地图（左下）：以水月为中心，显示约 1100 范围内的敌人、精英、Boss、宝箱、道具与商人
func _draw_minimap(vs: Vector2) -> void:
	var rad := 78.0
	var c := Vector2(16 + rad + 8, vs.y - rad - 24)
	UI.porthole(hud, c, rad, UI.GLOW)
	UI.en(hud, font, c + Vector2(-rad + 6, rad + 18), "SONAR", 9, UI.CYAN_DIM, 2.0)
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
	hud.draw_rect(Rect2(c - view * 0.5 * k, view * k), Color(0.4, 0.8, 0.9, 0.25), false, 1.0)
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
			hud.draw_rect(Rect2(c + p - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 0.35, 0.4, 0.8))
	for g in gems:
		if g.dead or not (g.kind == "magnet" or g.kind == "heal" or g.kind == "chest"):
			continue
		var p: Vector2 = ((g.pos - ppos) * k).limit_length(lim)
		hud.draw_circle(c + p, 3.0, _item_col(g.kind))
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
	var w: float = max(min(n, per_row) * cell + 16.0, 120.0)
	var rows: int = max(1, int(ceil(n / float(per_row))))
	var o := tr + Vector2(-w, 0)
	var r := Rect2(o, Vector2(w, rows * cell + 32))
	UI.frame(hud, r, UI.GOLD, {"t": t, "vines": true, "seed": 3, "vine_k": 0.7, "cut": 6.0, "bracket": 8.0})
	UI.en(hud, font, o + Vector2(10, 20), "RELICS", 10, UI.SUB, 3.0)
	UI.text(hud, font, o + Vector2(w - 30, 21), "%d" % n, 13, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 20)
	tray_cells.clear()
	var mouse := hud.get_local_mouse_position()
	for i in n:
		var rd: Dictionary = RL[relics[i]]
		var col: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var c := o + Vector2(8 + (i % per_row) * cell + cell / 2, 28 + (i / per_row) * cell + cell / 2)
		var cellr := Rect2(c - Vector2(17, 17), Vector2(34, 34))
		tray_cells.append([cellr, relics[i]])
		var hov: bool = cellr.has_point(mouse)
		hud.draw_rect(cellr, Color(0.01, 0.04, 0.08, 0.9) if not hov else Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.95))
		hud.draw_rect(cellr, Color(col.r, col.g, col.b, 0.7 if not hov else 1.0), false, 1.0 if not hov else 2.0)
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
	var x := 16.0
	var y := 150.0
	for it in items:
		var w: float = UI.chip(hud, font, Vector2(x, y), it[0], it[1], 12)
		if it[2] >= 0.0:
			hud.draw_rect(Rect2(x, y + 20, w * it[2], 2), it[1])
		x += w + 6.0
		if x > 360.0:
			x = 16.0
			y += 26.0


## 右下编队栏（2026-09-25 改版）：每名干员一列——底部头像（静态职业色框，技能生效时外圈发光；不画充能进度，
## 以免被当成干员经验条——干员没有等级，只有博士等级），上方三枚小技能图标
## （环 = 各自充能 / 生效倒计时；未解锁灰显；永久型打勾；海嗣化紫点）。开局干员在最左，第 4 位在最右。
const SQ_COL_W := 122.0
const SQ_ICON_R := 14.0

func _draw_squad_hud(br: Vector2) -> void:
	if knight.alive:
		knight.draw_hud(hud, br + Vector2(-squad.size() * SQ_COL_W - 120, -30))
	var n: int = squad.size()
	UI.en(hud, font, br + Vector2(-n * SQ_COL_W + 4, -118), "SQUAD", 10, UI.SUB, 3.0)
	for i in n:
		var o = squad.ops[i]
		var cx: float = br.x - (n - i) * SQ_COL_W + SQ_COL_W / 2.0
		var c := Vector2(cx, br.y - 34)
		var ocol: Color = o.col()
		# ---- 头像
		UI.ring(hud, c, 24.0, 0.0, ocol, o.skill_active())
		var pt: Dictionary = o.portrait()
		var at: Texture2D = tex.get(pt.tex)
		if at != null:
			var fw := at.get_width() / int(pt.frames)
			var ks: float = 34.0 / at.get_height()
			hud.draw_texture_rect_region(at, Rect2(c + Vector2(-fw * ks / 2.0, 16 - at.get_height() * ks), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
		UI.text(hud, font, c + Vector2(-SQ_COL_W / 2.0, 41), o.display_name().substr(0, 4), 11, UI.TEXT if o == ch else Color(0.75, 0.85, 0.9), HORIZONTAL_ALIGNMENT_CENTER, SQ_COL_W, 2)
		UI.text(hud, font, c + Vector2(14, -14), ["零", "一", "二"][o.elite], 11, ocol, HORIZONTAL_ALIGNMENT_CENTER, 20, 2)
		if o == ch:
			UI.diamond(hud, c + Vector2(-26, -20), 3.5, ocol)
		# ---- 三枚技能图标：横排在头像上方
		var items: Array = o.skill_hud()
		for k in 3:
			var it: Array = items[k]
			var sc := Vector2(cx + (k - 1) * (SQ_ICON_R * 2.0 + 6.0), br.y - 88)
			var col: Color = it[6]
			var unlocked: bool = it[2]
			var active: float = it[3]
			var frac: float = clamp(it[5], 0.0, 1.0)
			if active > 0.0:
				frac = active / it[4]
			UI.ring(hud, sc, SQ_ICON_R, frac if unlocked else 0.0, col, active > 0.0, not unlocked)
			var icon: Texture2D = tex.get(it[9]) if it.size() > 9 and it[9] != "" else null
			if icon != null:
				hud.draw_texture_rect(icon, Rect2(sc - Vector2(11, 11), Vector2(22, 22)), false, Color.WHITE if unlocked else Color(0.3, 0.3, 0.35))
			else:
				var gcol: Color = (Color(1, 1, 1) if active > 0.0 else col) if unlocked else Color(0.3, 0.38, 0.42)
				UI.text(hud, font, sc + Vector2(-SQ_ICON_R, 5), it[0], 12, gcol, HORIZONTAL_ALIGNMENT_CENTER, SQ_ICON_R * 2.0, 2)
			if active > 0.0:
				UI.text(hud, font, sc + Vector2(SQ_ICON_R - 8, -SQ_ICON_R + 2), "%d" % int(ceil(active)), 9, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 16, 2)
			if o.perm[k]:
				UI.diamond(hud, sc + Vector2(SQ_ICON_R - 3, SQ_ICON_R - 3), 3.0, col, Color(1, 1, 1, 0.6))
			if o.rej.has(k):
				UI.diamond(hud, sc + Vector2(0, -SQ_ICON_R - 3), 3.0, Color(0.85, 0.55, 1.0))
			# 手动技能（契约 v2.2）：图标上方标出按键；充满可放时外圈呼吸发光、标签变亮
			if o.is_manual(k) and unlocked:
				var rdy: bool = o.manual_ready(k)
				if rdy:
					var pulse: float = 0.5 + 0.5 * sin(t * 6.0)
					hud.draw_arc(sc, SQ_ICON_R + 4.0 + 2.0 * pulse, 0.0, TAU, 32, Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 0.45 + 0.4 * pulse), 2.5)
				UI.text(hud, font, sc + Vector2(-24, -SQ_ICON_R - 6), Pad.hint("空格", "Ⓐ"), 10, UI.TEXT if rdy else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 48, 2)
		# 悬停某枚图标：技能名 + 说明
		var mp := hud.get_local_mouse_position()
		for k in 3:
			var sc2 := Vector2(cx + (k - 1) * (SQ_ICON_R * 2.0 + 6.0), br.y - 88)
			if mp.distance_to(sc2) < SQ_ICON_R + 2.0:
				var sd: Dictionary = o.skill_def(k)
				var tip := "%s  ·  %s" % [sd.get("name", ""), ["招募", "精英化一", "精英化二"][k] + ("" if o.skill_unlocked(k) else "解锁")]
				var tw: float = font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
				var tr := Rect2(Vector2(minf(sc2.x - tw / 2.0, hud.size.x - tw - 8.0), br.y - 150), Vector2(tw, 28))
				UI.panel(hud, tr, UI.BG2, o.col(), 6.0)
				UI.text(hud, font, tr.position + Vector2(12, 19), tip, 12, UI.TEXT)


func _draw_result(vs: Vector2, title: String, en_title: String, col: Color, opts: Array, ending_panel := false) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.72))
	var r := Rect2(vs.x / 2 - 300, vs.y / 2 - 190, 600, 380)
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
	UI.frame(hud, r, col, {"t": t, "vines": true, "seed": 61, "cut": 16.0, "bracket": 16.0, "glow": 0.8})
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
		UI.frame(hud, br, col, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov else 0.0, "alpha": 1.0 if hov else 0.7})
		UI.text(hud, font, br.position + Vector2(14, 27), op[0], 16, UI.TEXT)
		UI.text(hud, font, br.position + Vector2(br.size.x - 34, 27), ("Ⓐ" if hov else "") if Pad.using else op[1], 13, col)
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
