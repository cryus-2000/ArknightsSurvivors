extends Node2D
## 水月 · 深海幸存者 —— v0.8
## 敌人/掉落物/特效用数据数组管理，统一在 _draw 中以像素贴图绘制（美术像素 ×2）。
## 灯火是一个真实光源：场景整体偏暗，只有玩家周围被照亮。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const BossAI = preload("res://scripts/boss_ai.gd")
const RelicFx = preload("res://scripts/relic_fx.gd")
## 造成伤害的类型：out_src -> [近战/远程, 物理/法术/真实]。真实伤害不吃任何倍率与防御
const DMG_TYPE := {
	"伞击": ["近战", "物理"], "技能": ["近战", "物理"], "技能·法术": ["近战", "法术"],
	"触手": ["近战", "法术"], "触手桩": ["近战", "法术"], "触须阵": ["近战", "法术"], "巨触": ["近战", "法术"],
	"水刃": ["远程", "物理"], "潮汐弹": ["远程", "法术"],
	"无人机": ["远程", "物理"], "无人机激光": ["远程", "法术"],
	"援护": ["远程", "物理"], "法术援护": ["远程", "法术"],
	"藏品": ["远程", "法术"], "地雷": ["远程", "物理"], "真实": ["近战", "真实"],
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
const MERCHANT_TIMES := [100.0, 330.0, 520.0]
const CELL := 48.0
const MAX_ENEMIES := 450
const LAMP_EMPTY_SECONDS := 150.0
const AMBIENT := Color(0.16, 0.22, 0.32)

var state: int = S.PLAY
var rng := RandomNumberGenerator.new()
var t := 0.0

# ---------- 玩家 ----------
var ppos := Vector2.ZERO
var facing := 1.0
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
var elite_stage := 0             # 精英化阶段 0/1/2
var swing_cd := 0.0
var u_dmg_mult := 1.0
var u_area_mult := 1.0
var u_spd_mult := 1.0
var t_mult := 0.6                # 天赋一：触手追击倍率
var rib_bonus := 0.0
var extra_targets := 0
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
var rfx: RefCounted = null       # 藏品效果解释器
var sp_mult := 1.0
var s1_need := 7                 # 唤醒：充能所需挥伞次数
var skill_lv := {"s1": 0, "s2": 0, "s3": 0}   # 0 未解锁 / 1 解锁 / 2 进阶I / 3 进阶II
var delayed: Array = []          # 延时攻击（深层唤醒触手、倒影、连击）
var s2_combo := 0
var skill_cut := {}              # 技能发动时的横幅演出
var flash := 0.0                 # 全屏闪光
var afterimg: Array = []         # 镜花水月残影
var afterimg_t := 0.0
var s1_count := 0
var s1_charges := 0
var s2_sp := 10.0
var s2_active := 0.0
var s3_sp := 30.0
var s3_active := 0.0
var mirror_pos := Vector2.ZERO    # S3 镜像分身位置
var mirror_face := 1.0
var s3_pen_cd := 0.0
var heal_budget := 0.0           # 反移情击杀回复：每秒上限
var talent2_on := false

# ---------- 藏品带来的附加能力 ----------
var grip := false
var evo_age := 35.0
var evo_xp := 2.0
var horde_mult := 1.0
var horde_chest := false
var seed_heal := false
var flesh_heal := false
var backlight := false
var ember := false

var relics: Array = []

# ---------- 援护干员 ----------
var weapons := {}                # 武器 id -> 等级
var intro_page := 0
var intro_back := S.PLAY
var intro_t := 0.0
var evo1 := ""                   # 精英化一路线：blade 潮刃 / tendril 群触
var evo2 := ""                   # 精英化二质变
var evo_pending := false
var abyss_n := 0                 # 深渊巨斩计数
var giant_cd := 5.0              # 巨触吞噬冷却
var mother_cd := 0.0
var stakes: Array = []           # 触手桩 {pos, life, max, r, tick, dmg}
var giants: Array = []           # 巨触横扫 {pos, t, dur, ang0, dir, dmg, hit}
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
var drones: Array = []           # {pos, cd_shot, cd_laser, cd_missile, ang}
var fields: Array = []           # 触须阵 {pos, r, life, max, tick, bind}
var field_cd := 1.0
var tide_shot_cd := 1.0
var allies: Array = []           # {kind, lv, pos, cd}
var bullets: Array = []
var recruit_idx := 0

# ---------- 世界 ----------
var enemies: Array = []
var gems: Array = []
var fx: Array = []
var texts: Array = []
var snow: Array = []
var grid := {}
var next_id := 0
var orbit_a := 0.0
var spawn_acc := 0.0
var next_elite := 45.0
var threat := 0                  # 威胁等级（D.THREAT 下标）
var diff := 0                # 本局难度
var diff_new := false        # 本局通关解锁了新难度
var stinger_done := false
var next_horde := 90.0
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
var next_mire := 100.0
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
var sort_props: Array = []   # 2.5D：需要与人物前后遮挡的场景物（海草、珊瑚）
var draw_off := Vector2.ZERO
var foot_anchor := {}       # 美术交付的 Boss 图以脚底为锚点 # 2.5D：绘制时的高度偏移（击退腾空等）
var fg: Node2D               # 2.5D：前景视差层
var fg_tex: Array = []       # 前景虚化剪影（运行时由海草/珊瑚图模糊生成）
var dof_layer: CanvasLayer   # 2.5D：景深 / 远景水雾
var lvup_delay := 0.0     # 升级演出：延迟弹出选择面板
var lvup_show := 0.0      # 角色头顶 LEVEL UP 字样
var hud_lv_flash := 0.0   # 左上角等级闪光
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
var anim_t := 0.0

# ---------- 自测 ----------
var autotest := false
var balance := false
var bal_done := false
var elites_killed := 0
var shop_visits := 0
var dmg_log := {}
var dmg_out: Dictionary = {}     # 造成的伤害按来源统计（balance 输出）
var out_src := "伞击"
var dmg_src := ""
var lv_marks := {}
var at_frames := 0
var bosstest := false
var shot_at := [3400]
var choice_wait := 0
var choice_shot := false


func _ready() -> void:
	bai = BossAI.new(self)
	rfx = RelicFx.new(self)
	RL = rfx.table()
	rng.randomize()
	font = load("res://fonts/ui.ttf")
	for n in ["drifter", "dart", "crawler", "shell", "boss", "tiles", "seaweed", "coral", "shell_prop", "rock",
			"gem_small", "gem_big", "oil", "chest", "slash", "tentacle", "jelly", "light", "shadow", "player",
			"ally_sniper", "ally_caster", "ally_medic", "ally_support", "orb",
			"e_bone", "e_slider", "e_stone", "e_offspring", "e_brood", "e_pocket", "e_skimmer", "e_mother", "e_chest", "e_mimic",
			"e_path", "e_fractal", "e_izumik", "e_ishar", "e_tear", "e_iberia", "e_carmen", "e_bishop", "e_archon", "e_immortal", "e_paranoia", "e_paranoia2", "e_bishop_feign", "e_archon_feign", "e_immortal_feign", "ebullet", "ingot", "merchant", "pickup_magnet", "pickup_heal", "drone", "drone_bullet", "drone_laser", "drone_missile",
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
	for gid in D.GROWTH:
		optional.append("growth_" + gid)
	for wid in D.WEAPONS:
		optional.append("weapon_" + wid)
	for eid in D.EVO:
		optional.append("evo_" + eid)
	for n in optional:
		tex[n] = A.tex(n)
	# 美术 V5：援护攻击帧条（4 帧，72×48，脚底锚点 (24,45)）
	for k in D.ALLIES:
		tex["ally_%s_attack" % k] = A.tex("ally_%s_attack" % k)
		tex["ally_%s_move" % k] = A.tex("ally_%s_move" % k)
	# 美术 V6：投射物 / 命中 / 爆炸 / 激光三段（docs/10_art_v6_spec.md）
	for n in V6_FRAMES:
		tex[n] = A.tex(n)
	# 美术 V5：Boss 移动帧条（4 帧，与本体同尺寸同锚点）及其白色剪影
	for n in ["e_path", "e_izumik", "e_ishar", "e_iberia", "e_carmen", "e_bishop", "e_archon", "e_immortal", "e_paranoia", "e_paranoia2"]:
		var mn: String = n + "_move"
		tex[mn] = A.tex(mn)
		if tex[mn] != null:
			tex[mn + "_white"] = A.white_of(tex[mn])

	var cm := CanvasModulate.new()
	cm.color = AMBIENT
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
	fg.draw.connect(_draw_fg)
	add_child(fg)
	for n in ["seaweed", "coral"]:
		fg_tex.append(_blur_silhouette(tex[n], 2 if n == "seaweed" else 1))

	merchant_light = PointLight2D.new()
	merchant_light.texture = tex.light
	merchant_light.color = Color(1.0, 0.75, 0.45)
	merchant_light.energy = 1.0
	merchant_light.texture_scale = 2.2
	merchant_light.visible = false
	add_child(merchant_light)

	lamp_light = PointLight2D.new()
	lamp_light.texture = tex.light
	lamp_light.color = Color(1.0, 0.86, 0.62)
	lamp_light.energy = 1.15
	add_child(lamp_light)

	for i in 70:
		snow.append({"p": Vector2(rng.randf_range(-700, 700), rng.randf_range(-400, 400)), "v": rng.randf_range(4, 14), "s": rng.randf_range(0.0, TAU)})

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
	Sfx.cut_target = 20000.0
	Sfx.vol_target = -4.0
	_show_banner("深海的潮水正在涌来……")
	diff = clampi(Cfg.difficulty, 0, D.DIFFICULTY.size() - 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--diff="):
			diff = int(a.substr(7))
	if diff >= 3:
		lamp_decay *= 1.25
	if diff >= 9:
		max_hp = 80.0
		hp = max_hp
	hp_trail = hp
	autotest = OS.get_cmdline_user_args().has("--autotest") or OS.get_cmdline_user_args().has("--balance")
	if OS.get_cmdline_user_args().has("--introshot"):
		_open_intro.call_deferred(S.PLAY)
	elif not autotest or OS.get_cmdline_user_args().has("--openshot"):
		_start_opening.call_deferred()
	balance = OS.get_cmdline_user_args().has("--balance")
	for arg in OS.get_cmdline_user_args():
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


func _update_music(_dt: float) -> void:
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
	if final_boss != null and not final_boss.dead:
		Sfx.play_music("final")
		return
	if _boss_alive():
		Sfx.play_music("boss")
		return
	Sfx.play_music("explore")
	var n := enemies.size()
	var elite := false
	for e in enemies:
		if e.elite and not e.dead and not e.chest:
			elite = true
			break
	var pulse := t > 12.0 or n > 30
	var drive := n > 110 + int(t / 3.0) or horde_warn > 0.0 or horde_hit > 0.0 or elite or s2_active > 0.0 or s3_active > 0.0 or zone_state == 2
	var out_zone := zone_state != 0 and ppos.distance_to(zone_c) > zone_r
	var danger := hp < max_hp * 0.35 or lamp <= 0.0 or out_zone
	Sfx.set_layers([1.0, 1.0 if pulse else 0.0, 1.0 if drive else 0.0, 1.0 if danger else 0.0])


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
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_gallery.png")
		get_tree().quit()


## 仅用于开发自测：快速模拟一整局，自动选择升级，打印状态后退出
func _autotest_step() -> void:
	at_frames += 1
	if state == S.OPENING and OS.get_cmdline_user_args().has("--openshot"):
		if at_frames % 3 == 0 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_open_%03d.png" % at_frames)
		if at_frames > 240:
			get_tree().quit()
		return
	if state == S.INTRO:
		if intro_t > 0.5 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_intro_%d.png" % intro_page)
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
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_shop.png")
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
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_fx_hurt.png")
		if at_frames == 175:
			zone_c = ppos + Vector2(560, 60)
			zone_r = 480.0
			zone_state = 3
			zone_t = -999.0
		if at_frames == 188 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_fx_zone.png")
		if at_frames == 130:
			state = S.STATS
		if at_frames == 134 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_fx_stats.png")
			state = S.PLAY
		if at_frames == 20:
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--evo="):
					var ev := a.substr(6).split(",")
					evo1 = ev[0]
					evo2 = ev[1] if ev.size() > 1 else ""
					growth["b_count"] = 1
					growth["t_count"] = 1
			weapons = {"drone": 3}
			if evo1 == "blade":
				growth["b_echo"] = 2
			elif evo1 == "tendril":
				growth["t_field"] = 2
			for rid in ["118", "199", "100"]:
				relics.append(rid)
				_apply_relic(rid)
			shield = 2
			skill_lv["s3"] = maxi(skill_lv["s3"], 2)
			s3_active = 30.0
			mirror_pos = ppos
			for k in ["sniper", "caster", "support"]:
				allies.append({"kind": k, "lv": 2, "pos": ppos, "cd": 0.5})
			t = 149.0
			next_horde = t + 60.0
			merchant = {"pos": ppos + Vector2(900, -300), "life": 60.0, "near": false}
		if at_frames == 150 and not tray_cells.is_empty():
			Input.warp_mouse(tray_cells[0][0].get_center())
		if at_frames == 110 and evo2 == "tendril_giant":
			giants.append({"pos": ppos + Vector2(230, 20), "t": 0.0, "dur": 2.6, "ang0": PI, "dir": 1.0, "dmg": 50.0, "hit": {}, "ang": 0.0})
		if at_frames == 60:
			_drop(ppos + Vector2(120, 40), "magnet", 1.0)
			_drop(ppos + Vector2(-120, 40), "heal", 1.0)
		for f in [64, 72, 100, 125, 160, 200]:
			if at_frames == f and DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_fx_%d.png" % f)
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
				get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_boss_%s_%03d.png" % [a.substr(11).replace(",", "_"), at_frames])
	if OS.get_cmdline_user_args().has("--fastlevel") and state == S.PLAY and (at_frames == 30 or at_frames == 400):
		level = 9 if at_frames == 30 else 19
		if at_frames == 400:
			recruit_idx = 2
		_gain_xp(xp_need + 0.1)
	if state == S.SHOW:
		if balance:
			show_t = 2.0
			_close_show()
			return
		if show_t > 1.4 and not show_shot and DisplayServer.get_name() != "headless":
			show_shot = true
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_show_%d.png" % elite_stage)
		if show_t > 1.6:
			_close_show()
		return
	if balance:
		if false:
			print("dbg t=%d state=%d lv=%d hp=%d en=%d" % [t, state, level, hp, enemies.size()])
		if state == S.CHOICE:
			var pi := rng.randi() % choices.size()
			if choices[0].kind == "evo" and OS.get_cmdline_user_args().has("--evoblade"):
				pi = 0
			if choices[0].kind == "evo" and OS.get_cmdline_user_args().has("--evotendril"):
				pi = choices.size() - 1
			_pick(pi)
		if (state == S.DEAD or state == S.WIN or t > 620.0) and not bal_done:
			bal_done = true
			print("BALANCE ", JSON.stringify({"win": state == S.WIN, "t": int(t), "lv": level, "marks": lv_marks, "kills": kills,
				"elites": elites_killed, "relics": relics.size(), "ingots": ingots, "maxhp": max_hp, "bosses": bosses.map(func(b): return "%s:%s" % [b.type, "dead" if b.dead else "%d%%" % int(100 * b.hp / b.maxhp)]), "allies": allies.size(), "elite_stage": elite_stage,
				"boss_hp": (boss.hp / boss.maxhp) if boss != null else -1.0, "dmg": dmg_log, "out": dmg_out, "out_type": dmg_type_out, "evo": evo1 + "/" + evo2}))
			get_tree().quit()
		return
	if not (OS.get_cmdline_user_args().has("--fxtest") and at_frames >= 90 and at_frames < 100):
		hp = max_hp
	if lvup_show > 1.05 and lvup_show < 1.12 and level == 3 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_lvup.png")
	if OS.get_cmdline_user_args().has("--relicshot"):
		if at_frames == 30:
			pending_chests = 1
			ingots = 40
		if at_frames == 400:
			merchant = {"pos": ppos, "life": 60.0, "near": false}
			_open_shop()
		if at_frames == 440 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_shop.png")
			get_tree().quit()
	if state == S.CHOICE:
		choice_wait += 1
		if choice_wait == 40 and not choice_shot and DisplayServer.get_name() != "headless" and (choice_kind == "relic" or not OS.get_cmdline_user_args().has("--relicshot")):
			choice_shot = true
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_choice.png")
		if choice_wait > 45:
			choice_wait = 0
			_pick(rng.randi() % choices.size())
	if at_frames % 1200 == 0:
		print("t=%d lv=%d E%d evo=%s hp=%d enemies=%d kills=%d lamp=%d growth=%s relics=%s allies=%s fps=%d" % [t, level, elite_stage, evo1 + "/" + evo2, hp, enemies.size(), kills, lamp, growth, relics, allies.map(func(a): return "%s%d" % [a.kind, a.lv]), Engine.get_frames_per_second()])
	for bb in bosses:
		if not bb.dead and not bb.invuln and not bosstest:
			bb.hp -= 4.0 if bosstest else 40.0
			if bb.hp <= 0.0:
				_kill(bb)
	if shot_at.has(at_frames) and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_%d.png" % at_frames)
	if bosstest and at_frames > 610:
		get_tree().quit()
	if state == S.WIN or at_frames > 14000:
		print("AUTOTEST END state=%d t=%d" % [state, t])
		get_tree().quit()


# =====================================================================
# 主循环
# =====================================================================
func _process(delta: float) -> void:
	var dt: float = min(delta, 0.05)
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
	if state == S.SHOW:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			_close_show()
		return
	if state == S.INTRO:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_ESCAPE:
					_close_intro()
				KEY_LEFT, KEY_A:
					intro_page = maxi(0, intro_page - 1)
					intro_t = 0.0
					Sfx.play("ui_move")
				_:
					_intro_next()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				intro_page = maxi(0, intro_page - 1)
				intro_t = 0.0
			else:
				_intro_next()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
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


func _update(dt: float) -> void:
	t += dt
	var mv := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)))
	if balance:
		mv = _bot_move()
	elif autotest:
		mv = Vector2.from_angle(t * 0.4)
	moving = mv != Vector2.ZERO
	if pstun > 0.0:
		mv = Vector2.ZERO
	moving = mv != Vector2.ZERO
	if moving:
		mv = mv.normalized()
		walk_t += dt * 12.0
		if mv.x != 0.0 and swing_face <= 0.0:
			facing = sign(mv.x)
	# 溟痕：陷在里面移动速度 -45%
	var mspd: float = speed * (1.0 - 0.45 * in_mire)
	pvel = mv * mspd
	ppos += mv * mspd * dt
	if tex.get("prop_pillar") != null:
		ppos = _prop_push(ppos, 12.0)
	swing_face -= dt

	hp = min(max_hp, hp + (regen + regen_pct * max_hp) * dt)
	lamp = max(0.0, lamp - dt * (100.0 / LAMP_EMPTY_SECONDS) * lamp_decay)
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
	_spawn(dt)
	_build_grid()
	_update_enemies(dt)
	_mizuki(dt)
	_update_allies(dt)
	_update_bullets(dt)
	_update_ebullets(dt)
	bai._update_warns(dt)
	_update_status(dt)
	rfx.tick(dt)
	_update_merchant(dt)
	_update_gems(dt)
	_update_fx(dt)
	_cleanup()

	if balance and OS.get_cmdline_user_args().has("--nodeath"):
		hp = maxf(hp, max_hp * 0.5)
	if hp <= 0.0 and not rfx.on_death():
		hp = 0.0
		state = S.DEAD
		return
	if final_boss != null and final_boss.dead:
		state = S.WIN
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
		if bl.life > 0.0 and bl.pos.distance_to(ppos) < 90.0:
			var toward: Vector2 = (ppos - bl.pos)
			if bl.vel.dot(toward) > 0.0:
				push += bl.vel.normalized().orthogonal() * 0.5 * (1.0 if int(bl.pos.x) % 2 == 0 else -1.0)
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
	if state != S.PLAY:
		return
	if not show_queue.is_empty():
		_open_show(show_queue.pop_front())
		return
	if pending_levelups > 0 and lvup_delay <= 0.0 and level >= D.SKILL_UNLOCK.s1 and skill_lv.s1 == 0:
		skill_lv.s1 = 1
		_open_show({"head": "技能解锁", "en": "SKILL  UNLOCKED", "col": UI.GOLD, "demo": "s1", "items": [_skill_item("s1")]})
		return
	if pending_levelups > 0 and lvup_delay <= 0.0 and level >= D.SKILL_UNLOCK.s2 and elite_stage == 0:
		elite_stage = 1
		skill_lv.s2 = 1
		talent2_on = true
		show_queue.append({"head": "精英化一", "en": "ELITE  PROMOTION  I", "col": Color(0.5, 0.8, 1.0), "demo": "s2", "items": [
			_skill_item("s2"),
			{"tag": "天赋", "tag_en": "TALENT", "glyph": "反", "name": "反移情", "desc": "击杀敌人时回复生命（每秒有上限）", "col": Color(0.5, 1.0, 0.65)}]})
		evo_pending = true
		_open_show(show_queue.pop_front())
		return
	# 精英化一：选择进化路线（消耗这次升级）
	if evo_pending and pending_levelups > 0:
		evo_pending = false
		var eo: Array = []
		for k in ["blade", "tendril"]:
			eo.append({"kind": "evo", "id": k, "name": "进化 · " + D.EVO[k].name, "desc": D.EVO[k].desc})
		_show_choices("精英化一：选择进化方向", eo, "level")
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
	var pool := ["pocket"]
	if t > 120.0:
		pool.append("skimmer")
	if t > 300.0:
		pool.append("mother")
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
	var rate := 1.6 + t / 30.0
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
			if not ne.elite and ne.ai != "static" and rng.randf() < D.THREAT[threat].get("evo", 0.0):
				_evolve(ne)
	if t >= next_elite:
		next_elite += D.THREAT[threat].elite * (0.75 if diff >= 4 else 1.0)
		var et := _pick_elite()
		_spawn_enemy(et, _edge_pos())
		if threat >= 4:
			var et2 := _pick_elite()
			_spawn_enemy(et2, _edge_pos())
			_show_banner("精英「%s」与「%s」同时出现！" % [D.ENEMIES[et].name, D.ENEMIES[et2].name])
		else:
			_show_banner("精英「%s」出现！击败它获得藏品" % D.ENEMIES[et].name)
		Sfx.play("roar", -3.0)
	var horde_ok: bool = not _boss_alive() or diff >= 7
	if t >= next_horde - 3.0 and horde_warned != next_horde and horde_ok:
		horde_warned = next_horde
		horde_warn = 3.0
		Sfx.play("roar", -2.0, 0.55, 0.0)
	if t >= next_horde and horde_ok:
		next_horde += D.THREAT[threat].get("horde_every", 120.0)
		horde_warn = 0.0
		horde_hit = 1.2
		_shake(1.4)
		fx.append({"kind": "horde_ring", "pos": ppos, "r": 640.0, "life": 0.9, "max": 0.9, "col": Color(0.75, 0.3, 1.0)})
		Sfx.play("roar", 2.0, 0.8, 0.0)
		var n := int((22 + int(t / 7.0)) * horde_mult * (1.4 if diff >= 7 else 1.0))
		if horde_chest:
			_drop(ppos + Vector2(70, 0), "chest", 1.0)
		var base := rng.randf() * TAU
		for i in n:
			if enemies.size() >= MAX_ENEMIES + 60:
				break
			var p := ppos + Vector2.from_angle(base + TAU * i / n) * rng.randf_range(560.0, 620.0)
			var hp_: Array = D.THREAT[threat].horde
			_spawn_enemy(hp_[i % hp_.size()], p)
	# 补给箱
	if t >= next_chest:
		next_chest = t + rng.randf_range(35.0, 50.0)
		var nch := 0
		for e in enemies:
			if e.chest:
				nch += 1
		if nch < 3:
			_spawn_chest(ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(260.0, 420.0))
	# 溟痕
	if t >= next_mire:
		# 溟痕随时间越来越多、越来越大；缩圈后多出现在圈边
		next_mire = t + maxf(5.0, rng.randf_range(16.0, 24.0) - t / 30.0)
		var mp := ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 380.0)
		if zone_state != 0 and rng.randf() < 0.6:
			var ang := (ppos - zone_c).angle() + rng.randf_range(-0.8, 0.8)
			mp = zone_c + Vector2.from_angle(ang) * (zone_r - rng.randf_range(20.0, 120.0))
		if mires.size() < 24:
			var grow := 1.0 + t / 600.0
			mires.append({"pos": mp, "r": 16.0, "maxr": rng.randf_range(70.0, 110.0) * grow, "life": (45.0 + t / 20.0) if diff < 8 else 9999.0, "seed": rng.randf() * 100.0})
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
	var hpm := (1.0 + minf(t, 480.0) / 120.0 + maxf(t - 480.0, 0.0) / 300.0) * (1.0 + (0.15 if diff >= 1 else 0.0) + (0.2 if diff >= 10 else 0.0))
	var dmm := (1.0 + (0.15 if diff >= 2 else 0.0) + (0.2 if diff >= 10 else 0.0))
	next_id += 1
	var e := {
		"id": next_id, "type": type, "name": d.name, "tex": d.tex, "pos": pos,
		"hp": d.hp * hpm * enemy_hp_mult, "maxhp": d.hp * hpm * enemy_hp_mult,
		"spd": d.spd * rng.randf_range(0.9, 1.1) * D.THREAT[threat].get("spd", 1.0), "dmg": d.dmg * (1.0 + minf(t, 480.0) / 260.0) * dmm * enemy_dmg_mult,
		"r": d.r, "r0": d.r, "xp": d.xp, "age": 0.0,
		"evo": false, "elite": role == "elite", "boss": role == "boss", "stun": 0.0,
		"kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": d.ai, "range": d.get("range", 0.0), "cd": d.get("cd", 0.0) * enemy_cd_mult, "cdt": rng.randf() * d.get("cd", 1.0),
		"corrode": d.get("corrode", 0.0), "nerve": d.get("nerve", 0.0), "def": 1.0, "set_t": 0.0, "set_done": false,
		"chest": false, "hidden": false, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		# 状态字段统一在此初始化（Boss 招式 / 假死 / 冲刺 / 流血），避免各处 get() 默认值不一致
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		# 贴图变体在生成时查一次，绘制时不再每帧拼字符串
		"tex_move": tex.has(d.tex + "_move"), "tex_feign": tex.has(d.tex + "_feign"), "tex_attack": tex.has(d.tex + "_attack"),
		"weak": d.get("weak", ""),
	}
	if e.elite:
		e.hp *= 7.0
		e.maxhp = e.hp
		e.xp *= 10.0
		e.dmg *= 1.3
	if e.boss:
		e.hp = d.hp * (1.0 + t / 600.0) * (1.15 if diff >= 1 else 1.0) * enemy_hp_mult
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
func _spawn_chest(pos: Vector2) -> void:
	next_id += 1
	enemies.append({
		"id": next_id, "type": "chest", "name": "补给箱", "tex": "e_chest", "pos": pos, "hp": 22.0, "maxhp": 22.0,
		"spd": 0.0, "dmg": 0.0, "r": 13.0, "r0": 13.0, "xp": 0.0, "age": 0.0, "evo": false, "elite": false, "boss": false,
		"stun": 0.0, "kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": "static", "range": 0.0, "cd": 0.0, "cdt": 0.0, "corrode": 0.0, "nerve": 0.0, "def": 1.0, "set_t": 0.0, "set_done": true,
		"chest": true, "hidden": rng.randf() < 0.15, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
		"coma": false, "wind": 0.0, "pose": 0.0, "pose_max": 0.0, "haste": 0.0, "air": 0.0, "channel": 0.0,
		"dash_t": 0.0, "dash_w": 0.0, "nova_w": 0.0, "bleed": 0.0, "bleed_t": 0.0, "mv_until": 0.0, "dpos": pos,
		"tex_move": false, "tex_feign": false, "tex_attack": false,
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
		# 流血（狙击干员）：每 0.5 秒结算一次
		if e.get("bleed", 0.0) > 0.0:
			e.bleed -= dt
			e["bleed_t"] = e.get("bleed_t", 0.0) + dt
			if e.bleed_t >= 0.5:
				e.bleed_t = 0.0
				out_src = "援护"
				_damage(e, e.bleed_dps * 0.5)
				fx.append({"kind": "spark", "pos": e.pos + Vector2(randf_range(-6, 6), -4), "vel": Vector2(0, 60), "sz": 2.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.05, 0.1)})
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
		var ov := _minion_pattern(e, dir, dist, dt, spd) if e.stun <= 0.0 else Vector2.INF
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
						_enemy_shoot(e, dir)
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
							_heal(max_hp * 0.05)
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
			e.pos = _prop_push(e.pos, e.r * 0.8)

		# ---- 囊海爬行者：每失去 15% 生命爆发一次
		if e.has("burst_at") and e.hp <= e.burst_at:
			e.burst_at -= e.maxhp * 0.15
			fx.append({"kind": "ring", "pos": e.pos, "r": 95.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.45, 1.0)})
			Sfx.play("tentacle", -2.0, 0.7)
			if dist < 95.0:
				in_type = ["近战", "法术"]
				_enemy_hit(e.dmg * 0.8, {"corrode": 0.0, "nerve": 30.0}, true)

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


## 远程攻击
func _enemy_shoot(e: Dictionary, dir: Vector2) -> void:
	if e.type == "stone" or D.ENEMIES[e.type].get("spit", false):
		_enemy_lob(e)
		return
	var spd := 280.0 if e.boss else 200.0
	var n := 1
	var kind := "orb"
	var home := false
	if e.type == "skimmer":
		n = 3
	if e.type == "mother":
		kind = "acid"
		home = true
		spd = 150.0
	if e.type == "ishar" and e.phase == 2:
		n = 3
	if e.type == "paranoia":
		n = 3 if e.phase == 1 else 5
	if e.type == "iberia":
		n = 5
	if e.has("ammo"):
		e.ammo -= 1
		if e.ammo <= 0:
			e.ai = "melee"
			_add_text(e.pos + Vector2(0, -40), "弹药耗尽", Color(1.0, 0.8, 0.5), 14)
	for k in n:
		var d := dir.rotated((k - (n - 1) / 2.0) * 0.22)
		ebullets.append({"pos": e.pos, "vel": d * spd, "dmg": e.dmg * (0.7 if e.boss else 0.45) * (2.0 if e.has("ammo") else 1.0),
			"slow": e.type == "paranoia", "r": 7.0 if e.boss else 5.0, "life": 2.0 if not home else 3.5,
			"corrode": e.corrode, "nerve": 0.0, "true": e.type == "ishar" and e.phase == 2, "kind": kind, "home": home, "atk": D.ENEMIES[e.type].get("atk", "法术"),
			"mire": e.type == "paranoia" and e.phase == 2})
	# 投嗣育母：每次攻击在水月附近放下一只注亡拟嗣
	if e.type == "mother":
		var nb := 0
		for o in enemies:
			if o.type == "brood" and not o.dead:
				nb += 1
		if nb < 12:
			_spawn_enemy("brood", ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(45.0, 75.0))


## 小怪的攻击模式（返回额外速度；返回 INF 表示走常规 AI）
func _minion_pattern(e: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	match e.type:
		"burrower":
			# 潜海裂魔：潜行接近（半伤、不接触），近身后破土咬击，露头 3 秒再潜回
			if e.get("under", true):
				e.under = true
				e.def = 1.0
				if dist < 84.0 and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0:
					e.under = false
					e.def = 1.0
					e.up_t = 3.2
					bai._warn(e, "circle", 0.6, {"follow": true, "r": 50.0, "act": "bite", "col": Color(0.8, 0.5, 1.0), "dmg": e.dmg * 1.3})
					_sparks(e.pos, Vector2.UP, Color(0.5, 0.4, 0.7), 10, 200.0)
					return Vector2.ZERO
				return dir * spd
			e.up_t = e.get("up_t", 3.0) - dt
			if e.up_t <= 0.0 and dist > 120.0:
				e.under = true
				_sparks(e.pos, Vector2.DOWN, Color(0.5, 0.4, 0.7), 8, 160.0)
			return Vector2.INF
		"hulk":
			# 巨骸漂流体：近身时踏地震荡
			if dist < 170.0 and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and bai._cd(e, "stomp", 6.0):
				bai._warn(e, "circle", 0.9, {"follow": true, "r": 135.0, "act": "slam", "col": Color(1.0, 0.8, 0.5), "dmg": e.dmg * 1.2})
			return Vector2.INF
		"slider", "ripper":
			# 底海滑动者：蓄力 0.5 秒后高速冲刺；沉海撕裂者：近身短距猛扑
			var rip: bool = e.type == "ripper"
			e["dash_cd"] = e.get("dash_cd", rng.randf_range(1.5, 3.5)) - dt
			if e.get("dash_w", 0.0) > 0.0:
				e.dash_w -= dt
				if e.dash_w <= 0.0:
					e["dash_t"] = 0.35
				return Vector2.ZERO
			if e.get("dash_t", 0.0) > 0.0:
				e.dash_t -= dt
				return e.dash_dir * spd * (4.5 if rip else 3.8)
			if e.dash_cd <= 0.0 and dist < (150.0 if rip else 240.0) and dist > 40.0:
				e.dash_cd = rng.randf_range(3.0, 4.5)
				e["dash_w"] = 0.4 if rip else 0.5
				e["dash_dir"] = dir
				return Vector2.ZERO
		"brood":
			# 注亡拟嗣：站桩吐酸
			e.cdt -= dt
			if e.cdt <= 0.0 and dist < 300.0:
				e.cdt = 4.2
				ebullets.append({"pos": e.pos, "vel": dir * 150.0, "dmg": 5.0 * (1.0 + t / 300.0), "slow": false, "r": 5.0, "life": 2.6,
					"corrode": 0.3, "nerve": 0.0, "true": false, "kind": "acid", "home": false})
			return Vector2.INF
		"offspring":
			# 伊祖米克的子代：发光蓄力后环形弹幕
			e["nova_cd"] = e.get("nova_cd", rng.randf_range(2.0, 4.0)) - dt
			if e.get("nova_w", 0.0) > 0.0:
				e.nova_w -= dt
				if e.nova_w <= 0.0:
					var n := 8 if e.evo else 6
					for k in n:
						ebullets.append({"pos": e.pos, "vel": Vector2.from_angle(TAU * k / n + e.id) * 150.0, "dmg": e.dmg * 0.3, "slow": false,
							"r": 5.0, "life": 2.6, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "nova", "home": false})
					Sfx.play("tentacle", -12.0, 0.7, 0.05)
				return Vector2.ZERO
			if e.nova_cd <= 0.0 and dist < 320.0:
				e.nova_cd = rng.randf_range(4.0, 5.5)
				e["nova_w"] = 0.6
				return Vector2.ZERO
	return Vector2.INF


## 固海凿石者：抛射碎石，落点预警，落地范围伤害
func _enemy_lob(e: Dictionary) -> void:
	var to := ppos + Vector2(randf_range(-30, 30), randf_range(-30, 30)) + pvel * 0.6
	lobs.append({"from": e.pos, "to": to, "t": 0.0, "dur": 1.0, "r": 46.0, "dmg": e.dmg * 0.6, "mire": D.ENEMIES[e.type].get("spit", false)})


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
	if not no_dodge and in_type[1] != "真实" and rng.randf() < min(dodge + (dodge_arts if in_type[1] == "法术" else dodge_phys), 0.6):
		invuln = 0.3
		Sfx.play("dodge", -4.0)
		_add_text(ppos + Vector2(0, -80), "闪避", Color(0.6, 0.85, 1.0), 16)
		on_dodge()
		return
	if shield > 0:
		_shield_block()
		return
	_hurt(dmg * (1.15 if lamp < 30.0 else 1.0), ignore_armor)
	# 受击时灯火摇曳熄灭一截
	lamp = maxf(0.0, lamp - 2.0)
	if src.get("corrode", 0.0) > 0.0:
		corrode_pool += dmg * src.corrode * 2.0
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
	nerve = max(0.0, nerve - 6.0 * dt)
	if corrode_pool > 0.0:
		var tick: float = min(corrode_pool, (corrode_pool * 0.5 + 1.0) * dt)
		corrode_pool -= tick
		hp -= tick
		dmg_log["corrode"] = dmg_log.get("corrode", 0.0) + tick
	var mired := false
	for m in mires:
		m.life -= dt
		m.r = min(m.maxr, m.r + 5.0 * dt)
		if m.pos.distance_to(ppos) < m.r:
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
			if zone_t >= (0.0 if zone_phase < 0 else 45.0) and zone_phase < ZONE_RADII.size() - 1:
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
	if out > 0.0 and state == S.PLAY:
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
		_heal(max_hp * 0.03)
	if shield_burst:
		for j in _query(ppos, 140.0):
			var e: Dictionary = enemies[j]
			if not e.dead and e.pos.distance_to(ppos) < 140.0:
				_damage(e, 30.0 * dmg_mult)
				if not e.boss:
					e.kb += (e.pos - ppos).normalized() * 420.0
		fx.append({"kind": "explode", "pos": ppos, "r": 140.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.85, 1.0)})
		_shake(0.6)


## 灯火：灯光照亮范围（游戏判定用）
func _lamp_r() -> float:
	return lerpf(110.0, 360.0, lamp / 100.0)


func _lamp_sp() -> float:
	return (1.3 if lamp >= 70.0 else 1.0) * rfx.sp_extra()


func _damage(e: Dictionary, dmg: float) -> void:
	if e.dead:
		return
	# 灯火照亮：光中的敌人受到的伤害 +25%
	if e.pos.distance_squared_to(ppos) < _lamp_r() * _lamp_r():
		dmg *= 1.25
	if e.invuln:
		if texts.size() < 80 and rng.randf() < 0.2:
			_add_text(e.pos + Vector2(0, -e.r - 10), "无效", Color(0.6, 0.7, 0.8), 13)
		return
	if e.chest and e.hidden:
		e.hidden = false
		_reveal_mimic(e)
		return
	var ty: Array = DMG_TYPE.get(out_src, ["近战", "物理"])
	var weak_hit := false
	if ty[1] != "真实":
		dmg *= e.def * rfx.dmg_extra()
		# 弱点：对应类型伤害 +50%（藏品可加成 / 赋予双弱点）
		var wk: String = e.get("weak", "")
		if wk == ty[1] or (wk == "双" and ty[1] != "真实") or (rfx.rule("all_weak") > 0):
			dmg *= 1.5 + weak_bonus
			weak_hit = true
		dmg *= melee_mult if ty[0] == "近战" else ranged_mult
		dmg *= arts_mult if ty[1] == "法术" else phys_mult
		if low_hp_bonus > 0.0 and e.hp < e.maxhp * 0.5:
			dmg *= 1.0 + low_hp_bonus
	rfx.on_hit()
	e.hp -= dmg
	var eff: float = minf(dmg, maxf(e.hp + dmg, 0.0))
	dmg_out[out_src] = dmg_out.get(out_src, 0.0) + eff
	dmg_type_out[ty[1]] = dmg_type_out.get(ty[1], 0.0) + eff
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


func _shake(a: float) -> void:
	shake = max(shake, a * Cfg.shake)


func _sparks(pos: Vector2, dir: Vector2, col: Color, n: int, spd: float) -> void:
	if fx.size() > 400:
		return
	for i in n:
		var a := rng.randf() * TAU if dir == Vector2.ZERO else dir.angle() + rng.randf_range(-0.7, 0.7)
		fx.append({"kind": "spark", "pos": pos, "vel": Vector2.from_angle(a) * spd * rng.randf_range(0.4, 1.0),
			"life": rng.randf_range(0.18, 0.32), "max": 0.3, "col": col, "sz": 2.0 if rng.randf() < 0.6 else 4.0})


func _heal(v: float) -> void:
	hp = min(max_hp, hp + v)


func _kill(e: Dictionary) -> void:
	rfx.on_kill(e)
	if e.dead:
		return
	e.dead = true
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
	var col: Color = ECOL.get(e.type, Color(0.6, 0.9, 0.9))
	_sparks(e.pos, Vector2.ZERO, col, 7, 160.0)
	fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 1.2, "life": 0.18, "max": 0.18, "col": col})
	Sfx.play("kill", -8.0)
	_anim("fx_death", e.pos, 0.3, PX * max(1.0, e.r / 12.0))
	if e.elite:
		elites_killed += 1
	if e.elite or e.boss:
		Sfx.play("boom", 0.0, 1.0, 0.0)
		hitstop = max(hitstop, 0.12)
		_shake(1.0)
		_sparks(e.pos, Vector2.ZERO, UI.GOLD, 24, 320.0)
	# 天赋二「反移情」：击杀回复生命（每秒有上限）
	if talent2_on:
		var want := 0.01
		var got: float = min(want, heal_budget)
		heal_budget -= got
		_heal(max_hp * got)
	if flesh_heal and e.evo:
		_heal(max_hp * 0.03)
	if ember and e.elite:
		lamp = min(100.0, lamp + 20.0)
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
	gems.append({"pos": pos, "kind": kind, "val": val, "dead": false, "mag": false,
		"z": 6.0, "vz": rng.randf_range(260.0, 300.0) if special else rng.randf_range(150.0, 230.0), "vel": sp * (0.5 if special else 1.0),
		"special": special, "landed": false, "age": 0.0})


# =====================================================================
# 水月的攻击：伞击 + 天赋「创伤性癔症」+ 三个自动技能
# =====================================================================
func _nearest(n: int, max_dist: float) -> Array:
	var c: Array = []
	for j in _query(ppos, max_dist):
		var e: Dictionary = enemies[j]
		if e.dead:
			continue
		var d: float = e.pos.distance_squared_to(ppos)
		if d < max_dist * max_dist:
			c.append([d, e])
	c.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in min(n, c.size()):
		out.append(c[i][1])
	return out


func _swing_radius() -> float:
	var r := 95.0 * u_area_mult
	if s3_active > 0.0:
		r *= 1.4
	return r


func _dmg_bonus() -> float:
	var m := dmg_mult
	if talent2_on and _low_hp_enemy_near():
		m *= 1.22
	if backlight and lamp < 30.0:
		m *= 1.3
	return m


func _low_hp_enemy_near() -> bool:
	for j in _query(ppos, 160.0):
		var e: Dictionary = enemies[j]
		if not e.dead and e.hp < e.maxhp * 0.5 and e.pos.distance_to(ppos) < 160.0:
			return true
	return false


func _mizuki(dt: float) -> void:
	heal_budget = min(heal_budget + dt * 0.05, 0.05)
	# 技力：随时间回复；技能生效期间不回复
	var P: Dictionary = D.SKILL_P
	if skill_lv.s2 >= 1:
		if s2_active > 0.0:
			s2_active -= dt
		else:
			s2_sp += dt * sp_mult * _lamp_sp()
			if s2_sp >= P.s2_charge:
				s2_sp = 0.0
				s2_active = P.s2_dur
				_skill_cast("s2")
	if skill_lv.s3 >= 1:
		if s3_active > 0.0:
			s3_active -= dt
			mirror_pos = mirror_pos.lerp(ppos + Vector2(-facing * 80.0, -10.0), minf(1.0, dt * 8.0))
			# 深海幻境：周身敌人减速
			if skill_lv.s3 >= 3:
				for j in _query(ppos, P.s3_zone_r):
					var ze: Dictionary = enemies[j]
					if not ze.dead and ze.pos.distance_to(ppos) < P.s3_zone_r:
						ze.slow = maxf(ze.slow, 0.2)
			afterimg_t -= dt
			if afterimg_t <= 0.0:
				afterimg_t = 0.06
				afterimg.push_front({"pos": ppos, "frame": sprite.frame, "tex": sprite.texture, "hf": sprite.hframes, "flip": sprite.flip_h})
				if afterimg.size() > 5:
					afterimg.pop_back()
		else:
			afterimg.clear()
			s3_sp += dt * sp_mult * _lamp_sp()
			if s3_sp >= P.s3_charge:
				s3_sp = 0.0
				s3_active = P.s3_dur
				mirror_pos = ppos
				_skill_cast("s3")
	# 延时攻击
	for i in range(delayed.size() - 1, -1, -1):
		var dl: Dictionary = delayed[i]
		dl.at -= dt
		if dl.at <= 0.0:
			delayed.remove_at(i)
			_run_delayed(dl)
	s3_pen_cd -= dt

	swing_cd -= dt
	if swing_cd <= 0.0:
		var radius := _swing_radius()
		var targets := _nearest(1, radius + 60.0)
		if targets.size() > 0:
			var interval: float = 0.9 * u_spd_mult * (1.5 if atk_slow > 0.0 else 1.0) * rfx.umbrella_interval_mult()
			if s2_active > 0.0:
				interval *= D.SKILL_P.s2_interval
			swing_cd = max(0.18, interval)
			_umbrella(targets[0])
		else:
			swing_cd = 0.1

	_update_weapons(dt)


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


func _umbrella(target: Dictionary) -> void:
	var P: Dictionary = D.SKILL_P
	var radius := _swing_radius()
	var half := deg_to_rad(min(180.0, 75.0 + rib_bonus + 15.0 * growth.get("u_area", 0)))
	var ang: float = (target.pos - ppos).angle()
	facing = 1.0 if cos(ang) >= 0.0 else -1.0
	swing_face = 0.25
	var dmg := 18.0 * u_dmg_mult * _dmg_bonus()
	if s3_active > 0.0:
		dmg *= P.s3_mult
	# S1「唤醒」：挥伞充能，满层后强化下一击
	var empowered := false
	if skill_lv.s1 >= 1:
		s1_count += 1
		if s1_count >= s1_need:
			s1_count = 0
			s1_charges = min(3, s1_charges + 1)
		if s1_charges > 0:
			s1_charges -= 1
			empowered = true
			dmg *= P.s1_mult
			radius *= P.s1_radius
	# 攻击方向：常态单方向；镜花水月三方向；深海形态全方向
	var dirs: Array = [ang]
	if s3_active > 0.0:
		if skill_lv.s3 >= 3:
			half = PI
		else:
			dirs = [ang, ang + TAU / 3.0, ang - TAU / 3.0]
	var seen := {}
	var hit: Array = []
	for d in dirs:
		for e in _arc_hit(ppos, d, half, radius):
			if not seen.has(e.id):
				seen[e.id] = true
				hit.append(e)
	crit_hit = empowered
	dmg *= rfx.single_hit_mult(hit.size())
	for e in hit:
		out_src = "伞击"
		_damage(e, dmg)
		if not e.boss:
			e.kb += (e.pos - ppos).normalized() * (360.0 if empowered else 240.0)
		if s3_active > 0.0 and not e.dead:
			e.stun = maxf(e.stun, P.s3_stun)
	crit_hit = false
	Sfx.play("swing_heavy" if empowered else "swing", -3.0 if empowered else -7.0)
	if hit.size() > 0:
		Sfx.play("hit", -2.0 if empowered else -5.0, 0.85 if empowered else 1.0)
		hitstop = max(hitstop, 0.09 if empowered else 0.03)
		_shake(0.6 if empowered else 0.18)
		cam_kick = Vector2.from_angle(ang) * (10.0 if empowered else 4.0)
		for k in min(hit.size(), 6):
			var he: Dictionary = hit[k]
			_sparks(he.pos, he.pos - ppos, UI.GOLD if empowered else Color(0.85, 0.97, 1.0), 4 if empowered else 3, 260.0)

	# 天赋「创伤性癔症」：触手追击命中目标中生命最低的敌人
	var alive := hit.filter(func(e): return not e.dead)
	alive.sort_custom(func(a, b): return a.hp < b.hp)
	var n: int = 1 + extra_targets + rfx.tentacle_targets_extra()
	if s2_active > 0.0:
		n += 1
	if s3_active > 0.0:
		n += 2 if skill_lv.s3 >= 3 else 1
	var tdmg := dmg * t_mult
	var stun := 0.0
	if s3_active > 0.0:
		stun = 1.0
	elif s2_active > 0.0:
		stun = P.s2_bind
	for i in min(n, alive.size()):
		_spawn_tentacle(alive[i], tdmg, stun)
	if grip:
		for e in alive:
			if not e.dead and rng.randf() < 0.2:
				_spawn_tentacle(e, tdmg * 0.6, 0.0)

	# ---- S1 进阶
	if empowered and hit.size() > 0:
		var ip: Vector2 = hit[0].pos
		fx.append({"kind": "impact", "pos": ip, "ang": ang, "life": 0.35, "max": 0.35, "col": UI.GOLD})
		fx.append({"kind": "ring", "pos": ip, "r": 70.0, "life": 0.3, "max": 0.3, "col": UI.GOLD})
		flash = maxf(flash, 0.12)
		if skill_lv.s1 >= 2:
			for k in mini(hit.size(), P.s1_burst_max):
				delayed.append({"at": 0.06 * k, "kind": "burst", "pos": hit[k].pos, "dmg": dmg * P.s1_burst_mult, "r": P.s1_burst_r, "arts": true})
		if skill_lv.s1 >= 3:
			var tg := _nearest(P.s1_deep_n, P.s1_deep_range)
			for k in tg.size():
				delayed.append({"at": 0.12 + 0.07 * k, "kind": "deep", "target": tg[k], "dmg": dmg * P.s1_deep_mult})
	# ---- S2 进阶
	if s2_active > 0.0:
		if skill_lv.s2 >= 2:
			# 双重困境：斩向另一方向最近的敌人
			var best: Dictionary = {}
			var bd := INF
			for j in _query(ppos, radius + 60.0):
				var e2: Dictionary = enemies[j]
				if e2.dead or seen.has(e2.id):
					continue
				var o2: Vector2 = e2.pos - ppos
				if abs(angle_difference(ang, o2.angle())) < 1.05:
					continue
				var dd := o2.length()
				if dd < bd and dd < radius + 60.0:
					bd = dd
					best = e2
			if not best.is_empty():
				var a2: float = (best.pos - ppos).angle()
				for e in _arc_hit(ppos, a2, half * 0.8, radius):
					if not seen.has(e.id):
						out_src = "技能"
						_damage(e, dmg * P.s2_twin_mult)
						if not e.dead:
							e.stun = maxf(e.stun, 0.3)
				_slash_fx(ppos, a2, half * 0.8, radius, Color(0.8, 1.1, 1.4) if _slash_tex().begins_with("fx_") else Color(0.5, 0.85, 1.4), _slash_tex(), 0.18)
		if skill_lv.s2 >= 3:
			s2_combo += 1
			if s2_combo >= P.s2_combo_every:
				s2_combo = 0
				var tg2 := _nearest(8, 220.0)
				tg2.shuffle()
				for k in mini(P.s2_combo_n, tg2.size()):
					delayed.append({"at": 0.05 + 0.07 * k, "kind": "combo", "target": tg2[k], "dmg": tdmg * 0.8})
	# ---- S3 进阶：倒影
	if s3_active > 0.0 and skill_lv.s3 >= 2:
		delayed.append({"at": P.s3_echo_delay, "kind": "echo", "ang": ang, "dmg": dmg * P.s3_echo_mult,
			"half": half, "radius": radius, "dirs": dirs.size()})

	# ---- 斩击表现
	var slash_col := Color.WHITE
	if empowered:
		slash_col = Color(1.6, 1.3, 0.7)
	elif s3_active > 0.0:
		slash_col = Color(1.2, 0.85, 1.6)
	elif s2_active > 0.0:
		slash_col = Color(0.8, 1.1, 1.5)
	var slash_tex := _slash_tex("awaken" if empowered else ("mirage" if s3_active > 0.0 else "base"))
	if slash_tex.begins_with("fx_umbrella_slash"):
		slash_col = Color(1.15, 1.15, 1.15)
	if empowered and alive.size() > 0:
		_anim("fx_s1_burst", alive[0].pos, 0.35)
	for k in min(hit.size(), 3):
		_anim("fx_hit", hit[k].pos, 0.16)
	for d in dirs:
		_slash_fx(ppos, d, half, radius, slash_col, slash_tex, 0.26 if empowered else 0.22)
	if empowered and not slash_tex.begins_with("fx_umbrella_slash"):
		# 唤醒（旧素材）：外圈再叠一层更大的金色斩痕
		_slash_fx(ppos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)
	_evo_on_swing(ang, dmg)


## ---- 进化：潮刃（水刃）与群触（触手桩）
func _evo_on_swing(ang: float, dmg: float) -> void:
	if evo1 == "blade":
		var n := 1 + int(growth.get("b_count", 0)) + (1 if evo2 == "blade_moon" else 0)
		var size: float = (1.0 + 0.25 * growth.get("b_size", 0)) * (1.3 if evo2 == "blade_abyss" else 1.0)
		var wd: float = dmg * 0.8 * (1.0 + 0.3 * growth.get("b_dmg", 0))
		var rng_: float = 380.0 * (1.0 + 0.3 * growth.get("b_range", 0))
		for k in n:
			var a := ang + (k - (n - 1) / 2.0) * 0.28
			_fire_wave(a, wd, size, rng_, evo2 == "blade_moon", false)
		if evo2 == "blade_abyss":
			abyss_n += 1
			if abyss_n >= 4:
				abyss_n = 0
				_fire_wave(ang, wd * 3.0, size * 3.0, rng_ * 1.2, false, true)
				_shake(0.6)
				Sfx.play("swing_heavy", -2.0, 0.6, 0.0)
	elif evo1 == "tendril":
		var n := 1 + int(growth.get("t_count", 0)) + (2 if evo2 == "tendril_mother" else 0) + (1 if evo2 == "tendril_giant" else 0)
		var pool := _nearest(14, 270.0)
		pool.shuffle()
		for k in mini(n, pool.size()):
			delayed.append({"at": 0.05 + 0.06 * k, "kind": "summon", "target": pool[k], "dmg": dmg * 0.6 * (1.0 + 0.3 * growth.get("t_power", 0))})


func _fire_wave(ang: float, dmg: float, size: float, dist: float, moon: bool, giant: bool) -> void:
	var spd := 560.0 if not giant else 420.0
	var life := dist / spd
	bullets.append({"kind": "wave", "pos": ppos + Vector2(0, -18) + Vector2.from_angle(ang) * 20.0, "vel": Vector2.from_angle(ang) * spd,
		"dmg": dmg, "life": life * (2.0 if moon else 1.0), "max": life * (2.0 if moon else 1.0), "r": 20.0 * size, "size": size,
		"aoe": 0.0, "hit": {}, "moon": moon, "ret": false, "giant": giant})
	if not giant:
		Sfx.play("swing", -14.0, 1.6, 0.1)


## 触手桩：原地停留，定期鞭打范围内最近的敌人
func _add_stake(p: Vector2, dmg: float) -> void:
	if stakes.size() >= 16:
		stakes.pop_front()
	var life: float = 1.6 + 1.0 * growth.get("t_stake", 0)
	stakes.append({"pos": p, "life": life, "max": life, "r": 60.0 * (1.0 + 0.25 * growth.get("t_reach", 0)), "tick": 0.3,
		"dmg": dmg * 0.45, "flip": rng.randf() < 0.5, "whip": 0.0, "wt": Vector2.ZERO})


const GIANT_R := 185.0
const GIANT_RISE := 0.45
const GIANT_SINK := 2.1


## 巨触横扫：破土 0.45s → 顺 / 逆时针扫一整圈（1.65s）→ 沉回海床；扫到的敌人受重击、晕眩并被甩开
func _update_giants(dt: float) -> void:
	for gi in giants:
		gi.t += dt
		if gi.t < GIANT_RISE or gi.t > GIANT_SINK:
			continue
		var k: float = (gi.t - GIANT_RISE) / (GIANT_SINK - GIANT_RISE)
		gi.ang = gi.ang0 + gi.dir * TAU * k
		var sweep := Vector2.from_angle(gi.ang)
		for j in _query(gi.pos, GIANT_R + 30.0):
			var e: Dictionary = enemies[j]
			if e.dead or gi.hit.has(e.id):
				continue
			var rel: Vector2 = e.pos - gi.pos
			var dist := rel.length()
			if dist > GIANT_R + e.r or dist < 10.0:
				continue
			if absf(angle_difference(rel.angle(), gi.ang)) > 0.42:
				continue
			gi.hit[e.id] = true
			out_src = "巨触"
			_damage(e, gi.dmg)
			if not e.dead:
				e.stun = maxf(e.stun, 0.9)
				if not e.boss:
					e.kb += (sweep.orthogonal() * gi.dir + rel.normalized() * 0.6).normalized() * 420.0
			_sparks(e.pos, sweep.orthogonal() * gi.dir, Color(0.9, 0.6, 1.4), 4, 260.0)
		if int(gi.t * 12.0) != int((gi.t - dt) * 12.0):
			Sfx.play("tentacle", -12.0, 0.6, 0.1)
	giants = giants.filter(func(x): return x.t < x.dur)


func _draw_giant(gi: Dictionary) -> void:
	var tx: Texture2D = tex.get("tentacle")
	if tx == null:
		return
	# 地面阴影 + 扫过的弧
	draw_set_transform(gi.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 46.0, Color(0.6, 0.25, 1.0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var rise: float = clampf(gi.t / GIANT_RISE, 0.0, 1.0)
	var sink: float = clampf((gi.t - GIANT_SINK) / (gi.dur - GIANT_SINK), 0.0, 1.0)
	var len_k: float = (1.0 - (1.0 - rise) * (1.0 - rise)) * (1.0 - sink)
	var ang: float = gi.ang if gi.t >= GIANT_RISE else gi.ang0
	if gi.t >= GIANT_RISE and gi.t <= GIANT_SINK:
		for q in 6:
			var a0: float = ang - gi.dir * (0.12 + 0.11 * q)
			var a1: float = ang - gi.dir * (0.11 * q)
			draw_arc(gi.pos, GIANT_R * 0.92, minf(a0, a1), maxf(a0, a1), 10, Color(1.2, 0.6, 2.0, 0.55 - 0.08 * q), 26.0 - 3.0 * q)
	# 触手本体：沿扫掠方向平躺，从根部长出
	var fw: int = tx.get_width() / 5
	var fh: int = tx.get_height()
	var fr: int = clampi(int(rise * 4.99), 0, 4)
	var sc_len: float = GIANT_R / float(fh) * len_k * 1.05
	var sc_w: float = PX * 4.6
	draw_set_transform(gi.pos, ang + PI / 2.0, Vector2(sc_w, sc_len))
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh), Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), Color(1.4, 1.1, 1.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _update_stakes(dt: float) -> void:
	for st in stakes:
		st.life -= dt
		st.tick -= dt
		st.whip = maxf(0.0, st.whip - dt)
		if st.tick <= 0.0:
			st.tick = 0.45
			var best: Dictionary = {}
			var bd: float = st.r
			for j in _query(st.pos, st.r + 20.0):
				var e: Dictionary = enemies[j]
				if e.dead:
					continue
				var d: float = e.pos.distance_to(st.pos)
				if d < bd:
					bd = d
					best = e
			if not best.is_empty():
				out_src = "触手桩"
				_damage(best, st.dmg)
				st.whip = 0.18
				st.wt = best.pos
				if not best.boss:
					best.kb += (best.pos - st.pos).normalized() * 120.0
	stakes = stakes.filter(func(st): return st.life > 0.0)
	# 巨触吞噬：每 5 秒在敌群中心升起巨型触手
	if evo2 == "tendril_giant":
		giant_cd -= dt
		if giant_cd <= 0.0:
			var c := _densest_point(400.0)
			if c == Vector2.INF:
				giant_cd = 0.5
			else:
				giant_cd = 5.0
				fx.append({"kind": "rift", "pos": c, "r": 115.0, "life": 0.55, "max": 0.55})
				delayed.append({"at": 0.55, "kind": "giant", "pos": c, "dmg": (28.0 + level * 1.8) * dmg_mult * (1.0 + 0.3 * growth.get("t_power", 0))})
				Sfx.play("roar", -8.0, 1.6, 0.0)
	mother_cd -= dt


## 延时攻击的执行
func _run_delayed(dl: Dictionary) -> void:
	var P: Dictionary = D.SKILL_P
	match dl.kind:
		"burst":
			# 创伤扩散：目标处的范围冲击
			for j in _query(dl.pos, dl.r):
				var e: Dictionary = enemies[j]
				if not e.dead and e.pos.distance_to(dl.pos) < dl.r + e.r:
					out_src = "技能·法术"
					_damage(e, dl.dmg)
					if not e.boss:
						e.kb += (e.pos - dl.pos).normalized() * 200.0
			fx.append({"kind": "burst", "pos": dl.pos, "r": dl.r, "life": 0.4, "max": 0.4, "col": UI.GOLD})
			_sparks(dl.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 10, 280.0)
			Sfx.play("boom", -10.0, 1.4, 0.1)
		"deep", "combo":
			var tg: Dictionary = dl.target
			if tg.dead:
				return
			_spawn_tentacle(tg, dl.dmg, P.s2_bind if dl.kind == "combo" else 0.4)
			fx.append({"kind": "ring", "pos": tg.pos, "r": 30.0, "life": 0.3, "max": 0.3,
				"col": UI.GOLD if dl.kind == "deep" else Color(0.45, 0.8, 1.0)})
			fx.append({"kind": "pillar", "pos": tg.pos, "life": 0.35, "max": 0.35,
				"col": Color(1.0, 0.8, 0.4) if dl.kind == "deep" else Color(0.5, 0.85, 1.0)})
		"summon":
			# 群触：召唤触手（命中后化为触手桩）
			var tg: Dictionary = dl.target
			if tg.dead:
				return
			var sp: Vector2 = tg.pos
			_spawn_tentacle(tg, dl.dmg, 0.35)
			_add_stake(sp, dl.dmg)
		"giant":
			# 巨触吞噬：破土后横扫一圈（见 _update_giants），先把中心的敌人拖过来
			for j in _query(dl.pos, 135.0):
				var e: Dictionary = enemies[j]
				if not e.dead and not e.boss and e.pos.distance_to(dl.pos) < 115.0 + e.r:
					e.kb += (dl.pos - e.pos) * 2.0
			giants.append({"pos": dl.pos, "t": 0.0, "dur": 2.6, "ang0": rng.randf() * TAU, "dir": (1.0 if rng.randf() < 0.5 else -1.0), "dmg": dl.dmg, "hit": {}, "ang": 0.0})
			fx.append({"kind": "ring", "pos": dl.pos, "r": 130.0, "life": 0.5, "max": 0.5, "col": Color(0.8, 0.4, 1.0)})
			_sparks(dl.pos, Vector2.UP, Color(0.8, 0.5, 1.0), 24, 360.0)
			_shake(1.0)
			hitstop = maxf(hitstop, 0.06)
			Sfx.play("boom", -2.0, 0.6, 0.0)
		"echo":
			# 镜像：身后的镜像分身朝它身边的敌人同步挥伞（深海形态下三向）
			var mp: Vector2 = mirror_pos
			var ma: float = dl.ang
			var near_d: float = dl.radius * 1.4
			for e in enemies:
				if e.dead:
					continue
				var dd: float = mp.distance_to(e.pos)
				if dd < near_d:
					near_d = dd
					ma = (e.pos - mp).angle()
			var dirs: Array = [ma]
			if dl.dirs > 1:
				dirs = [ma, ma + TAU / 3.0, ma - TAU / 3.0]
			var seen := {}
			for d in dirs:
				for e in _arc_hit(mp, d, dl.half, dl.radius):
					if seen.has(e.id):
						continue
					seen[e.id] = true
					out_src = "技能"
					_damage(e, dl.dmg)
					if not e.dead:
						e.stun = maxf(e.stun, P.s3_stun * 0.5)
				_slash_fx(mp, d, dl.half, dl.radius, Color(1.0, 0.9, 1.2, 0.8) if _slash_tex("mirage").begins_with("fx_") else Color(0.9, 0.6, 1.6, 0.8), _slash_tex("mirage"), 0.3)
			mirror_face = -1.0 if cos(ma) < 0.0 else 1.0
			Sfx.play("swing", -9.0, 0.7, 0.05)


## 技能发动：横幅 + 光环爆发 + 震屏
func _skill_cast(sid: String) -> void:
	rfx.on_skill_start()
	var sk: Dictionary = D.SKILLS[sid]
	skill_cut = {"id": sid, "t": 0.0}
	Sfx.play("skill", -1.0, 1.0 if sid == "s2" else 0.8, 0.0)
	_anim("fx_cast", ppos, 0.5, PX * (1.3 if sid == "s3" else 1.0), true)
	_shake(0.5 if sid == "s2" else 0.8)
	flash = maxf(flash, 0.25)
	var c: Color = sk.col
	fx.append({"kind": "ring", "pos": ppos, "r": 160.0, "life": 0.5, "max": 0.5, "col": c})
	fx.append({"kind": "ring", "pos": ppos, "r": 260.0, "life": 0.7, "max": 0.7, "col": c})
	fx.append({"kind": "rays", "pos": ppos, "life": 0.6, "max": 0.6, "col": c})
	_sparks(ppos + Vector2(0, -20), Vector2.ZERO, c, 24, 360.0)
	# 发动冲击：推开身边小怪
	for j in _query(ppos, 140.0):
		var e: Dictionary = enemies[j]
		if not e.dead and not e.boss and not e.chest:
			e.kb += (e.pos - ppos).normalized() * 420.0


func _spawn_tentacle(target: Dictionary, dmg: float, stun: float) -> void:
	var p: Vector2 = target.pos
	out_src = "触手"
	_damage(target, dmg)
	rfx.on_tentacle_hit(target)
	if not target.dead:
		target.stun = max(target.stun, stun if stun > 0.0 else 0.25)
		# 无解困境：束缚有限传播给身边 1 名敌人（不会再次传播）
		if s2_active > 0.0 and skill_lv.s2 >= 3 and stun > 0.0:
			var P: Dictionary = D.SKILL_P
			for j in _query(p, P.s2_spread_r):
				var o: Dictionary = enemies[j]
				if o.dead or is_same(o, target) or o.boss or o.stun > 0.1:
					continue
				if o.pos.distance_to(p) < P.s2_spread_r:
					o.stun = P.s2_spread_bind
					fx.append({"kind": "chain", "a": p, "b": o.pos, "life": 0.3, "max": 0.3})
					break
	# 深海之母：被触手击杀的敌人会在附近唤出新的触手
	if target.dead and evo2 == "tendril_mother" and mother_cd <= 0.0:
		mother_cd = 0.15
		for j in _query(p, 180.0):
			var o: Dictionary = enemies[j]
			if not o.dead and not is_same(o, target) and o.pos.distance_to(p) < 180.0:
				delayed.append({"at": 0.12, "kind": "summon", "target": o, "dmg": dmg * 0.8})
				break
	# 触手表现：地面裂隙 → 放大的触手破土 → 冲击环；再从水月脚下连一道触须线到目标
	fx.append({"kind": "rift", "pos": p, "r": 26.0, "life": 0.25, "max": 0.25})
	fx.append({"kind": "tentacle", "pos": p, "life": 0.6, "max": 0.6, "flip": rng.randf() < 0.5})
	fx.append({"kind": "tendril", "a": ppos + Vector2(0, 6), "b": p + Vector2(0, 6), "life": 0.32, "max": 0.32, "seed": randf() * 10.0})
	fx.append({"kind": "ring", "pos": p + Vector2(0, 4), "r": 34.0, "life": 0.3, "max": 0.3, "col": Color(0.8, 0.45, 1.0)})
	Sfx.play("tentacle", -4.0)
	_sparks(p + Vector2(0, 8), Vector2.UP, Color(0.75, 0.5, 1.0), 7, 200.0)


# =====================================================================
# 商人与商店
# =====================================================================
func _update_merchant(dt: float) -> void:
	if merchant.is_empty():
		merchant_light.visible = false
		return
	merchant.life -= dt
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
	shop_items.append({"kind": "heal", "id": "heal", "name": "急救包", "desc": "回复 40% 最大生命", "price": _shop_price("heal"), "sold": false})
	shop_items.append({"kind": "oil", "id": "oil", "name": "灯油", "desc": "灯火 +50", "price": _shop_price("oil"), "sold": false})


func _open_shop() -> void:
	if shop_items.is_empty():
		_roll_shop()
	state = S.SHOP
	Sfx.play("relic", -4.0)
	_build_shop_ui()


func _build_shop_ui() -> void:
	for c in panel_box.get_children():
		c.queue_free()
	panel_title_text = "商人  ·  持有源石锭 %d" % ingots
	choice_kind = "shop"
	for i in shop_items.size():
		var it: Dictionary = shop_items[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(204, 276)
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
		desc.text = it.desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(16, 178)
		desc.size = Vector2(172, 78)
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.88))
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		card.set_meta("desc", desc)
		panel_box.add_child(card)
	panel.visible = true
	panel.queue_redraw()


func _draw_shop_card(card: Button, it: Dictionary, i: int) -> void:
	var hov: bool = card.is_hovered() and not it.sold
	var col: Color = UI.GOLD
	if it.kind == "relic":
		col = UI.CAT_COL.get(RL[it.id].cat, UI.GOLD)
	elif it.kind == "heal":
		col = Color(0.5, 1.0, 0.6)
	var afford: bool = ingots >= it.price
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	UI.frame(card, r, col, {"t": t, "vines": true, "seed": 40 + i, "vine_k": 0.9 if hov else 0.6, "glow": 1.0 if hov else 0.2, "cut": 10.0, "bracket": 10.0, "alpha": 0.5 if it.sold else 1.0})
	UI.text(card, font, r.position + Vector2(14, 28), str(i + 1), 14, Color(col.r, col.g, col.b, 0.7))
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
			if not relics.has(it.id):
				relics.append(it.id)
			_apply_relic(it.id)
		"heal":
			_heal(max_hp * 0.4)
		"oil":
			lamp = min(100.0, lamp + 50.0)
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
# 援护干员
# =====================================================================
const ALLY_SLOTS := [Vector2(-46, -8), Vector2(46, -8), Vector2(0, -52)]


func _update_allies(dt: float) -> void:
	for i in allies.size():
		var al: Dictionary = allies[i]
		var slot: Vector2 = ppos + ALLY_SLOTS[i]
		var prev: Vector2 = al.pos
		al.pos = al.pos.lerp(slot, clamp(dt * 5.0, 0.0, 1.0))
		# 美术 V6：移动速度（平滑）与朝向，用于移动循环
		var vel: Vector2 = (al.pos - prev) / maxf(dt, 0.0001)
		al["mv"] = lerpf(al.get("mv", 0.0), vel.length(), clampf(dt * 10.0, 0.0, 1.0))
		if absf(vel.x) > 20.0:
			al["mface"] = signf(vel.x)
		al["mt"] = al.get("mt", 0.0) + dt
		al.cd -= dt
		# 攻击动作计时：到出手帧时结算，播完回到待机
		if al.get("atk", -1.0) >= 0.0:
			al.atk += dt
			if not al.get("fired", true) and al.atk >= ALLY_EVENT_T:
				al.fired = true
				_ally_release(al)
			if al.atk >= ALLY_ANIM_T:
				al.atk = -1.0
		match al.kind:
			"sniper":
				if al.cd <= 0.0:
					var tgt := _sniper_target(al.pos, 460.0)
					if tgt.is_empty():
						al.cd = 0.2
					else:
						al.cd = 0.8 * pow(0.87, al.lv - 1)
						_ally_start(al, tgt.pos)
			"caster":
				if al.cd <= 0.0:
					var ts := _nearest(1, 360.0)
					if ts.is_empty():
						al.cd = 0.2
					else:
						al.cd = 1.25 * pow(0.9, al.lv - 1)
						_ally_start(al, ts[0].pos)
			"medic":
				if al.cd <= 0.0:
					al.cd = 3.5 / (1.0 + 0.2 * (al.lv - 1))
					if hp < max_hp:
						_ally_start(al, ppos)
			"support":
				# 辅助：光环只减速不造成伤害；另外向 2 名敌人发射紫色法术
				var rad: float = _support_radius(al.lv)
				for j in _query(ppos, rad + 20.0):
					var e: Dictionary = enemies[j]
					if e.dead or e.pos.distance_to(ppos) > rad:
						continue
					e.slow = maxf(e.slow, 0.2)
				if al.cd <= 0.0:
					var ts := _nearest(2, 380.0)
					if ts.is_empty():
						al.cd = 0.2
					else:
						al.cd = 1.2 * pow(0.88, al.lv - 1)
						_ally_start(al, ts[0].pos)


## 援护攻击动作：8fps × 4 帧，零基第 2 帧出手（美术 V5 约定）
const ALLY_EVENT_T := 0.25
const ALLY_ANIM_T := 0.5


func _ally_start(al: Dictionary, aim: Vector2) -> void:
	if absf(aim.x - al.pos.x) > 2.0:
		al.face = signf(aim.x - al.pos.x)
	if tex.get("ally_%s_attack" % al.kind) == null:
		_ally_release(al)
		return
	al.atk = 0.0
	al.fired = false


## 出手：重新找目标（动作期间原目标可能已死）
func _ally_release(al: Dictionary) -> void:
	var lvm: float = pow(1.35, al.lv - 1) * ally_mult
	match al.kind:
		"sniper":
			var tgt := _sniper_target(al.pos, 500.0)
			if tgt.is_empty():
				return
			var d: Vector2 = (tgt.pos - al.pos).normalized()
			bullets.append({"kind": "arrow", "pos": al.pos + Vector2(0, -12), "vel": d * 900.0, "dmg": 24.0 * lvm * dmg_mult, "life": 0.8, "r": 5.0, "aoe": 0.0})
			fx.append({"kind": "ring", "pos": al.pos + Vector2(0, -12) + d * 12.0, "r": 10.0, "life": 0.12, "max": 0.12, "col": Color(1.0, 0.9, 0.7)})
			Sfx.play("swing", -16.0, 1.8)
		"caster":
			var ts := _nearest(1, 400.0)
			if ts.is_empty():
				return
			var d: Vector2 = (ts[0].pos - al.pos).normalized()
			bullets.append({"kind": "fire", "pos": al.pos + Vector2(0, -14), "vel": d * 340.0, "dmg": 20.0 * lvm * dmg_mult, "life": 1.3, "r": 8.0, "aoe": 55.0 + 10.0 * al.lv})
			Sfx.play("oil", -12.0, 1.4, 0.05)
		"medic":
			if hp < max_hp:
				var h: float = max_hp * (0.035 + 0.01 * (al.lv - 1))
				_heal(h)
				_add_text(ppos + Vector2(0, -90), "+%d" % int(h), Color(0.5, 1.0, 0.6), 16)
				fx.append({"kind": "ring", "pos": ppos, "r": 26.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 1.0, 0.6)})
				# 回血：水月身上升起绿色十字 + 医疗干员到水月的治疗光线
				for k in 6:
					fx.append({"kind": "cross", "pos": ppos + Vector2(randf_range(-22, 22), randf_range(-50, -5)), "life": 0.9, "max": 0.9,
						"delay": k * 0.08, "sz": randf_range(3.0, 5.0)})
				fx.append({"kind": "beam", "a": al.pos + Vector2(0, -20), "b": ppos + Vector2(0, -24), "life": 0.3, "max": 0.3, "col": Color(0.5, 1.0, 0.6), "w": 3.0})
		"support":
			# 辅助：向 2 名敌人发射追踪的紫色法术
			var ts2 := _nearest(3 if al.lv >= 3 else 2, 400.0)
			for k in ts2.size():
				var d2: Vector2 = (ts2[k].pos - al.pos).normalized().rotated(0.6 * (1 if k == 0 else -1))
				bullets.append({"kind": "arcane", "pos": al.pos + Vector2(0, -16), "vel": d2 * 330.0, "dmg": 16.0 * lvm * dmg_mult,
					"life": 1.6, "r": 7.0, "aoe": 0.0, "home": ts2[k], "turn": 7.0})
			if not ts2.is_empty():
				Sfx.play("tentacle", -14.0, 1.6, 0.05)


# =====================================================================
# 武器：支援无人机；触须阵 / 潮汐弹由路线成长（群触·阵 / 潮刃·回响）驱动
# =====================================================================
func _update_weapons(dt: float) -> void:
	_update_stakes(dt)
	_update_giants(dt)
	var dl: int = weapons.get("drone", 0)
	if dl > 0:
		var want := 2 if dl >= 4 else 1
		while drones.size() < want:
			drones.append({"pos": ppos + Vector2(0, -60), "cd_shot": 0.3, "cd_laser": 1.0, "cd_missile": 1.5, "ang": drones.size() * PI})
		var haste := 1.25 if dl >= 5 else 1.0
		for i in drones.size():
			var dr: Dictionary = drones[i]
			dr["fire_t"] = dr.get("fire_t", 0.0) - dt
			dr.ang += dt * 1.6
			var slot := ppos + Vector2(cos(dr.ang) * 52.0, -96.0 + sin(dr.ang * 2.0) * 6.0)
			dr.pos = dr.pos.lerp(slot, clampf(dt * 6.0, 0.0, 1.0))
			if dl == 1:
				dr.cd_shot -= dt
				if dr.cd_shot <= 0.0:
					var ts := _nearest(1, 420.0)
					if ts.is_empty():
						dr.cd_shot = 0.15
					else:
						dr.cd_shot = 0.55
						var d: Vector2 = (ts[0].pos - dr.pos).normalized()
						bullets.append({"kind": "dbullet", "pos": dr.pos, "vel": d * 700.0, "dmg": 8.0 * dmg_mult, "life": 0.8, "r": 4.0, "aoe": 0.0})
						dr["fire_t"] = 0.25
						dr["face"] = signf(d.x)
						Sfx.play("swing", -20.0, 2.4, 0.1)
			else:
				dr.cd_laser -= dt * haste
				if dr.cd_laser <= 0.0:
					var ts2 := _nearest(1, 480.0)
					if ts2.is_empty():
						dr.cd_laser = 0.2
					else:
						dr.cd_laser = 1.9
						dr["beam"] = LASER_DUR
						dr["beam_ang"] = (ts2[0].pos - dr.pos).angle()
						dr["beam_tick"] = 0.0
						Sfx.play("skill", -16.0, 2.2, 0.05)
				# 照射中：光束从无人机射出，随最近的敌人平滑转向，每 0.1 秒结算一次
				if dr.get("beam", 0.0) > 0.0:
					dr.beam -= dt
					var tb := _nearest(1, LASER_LEN)
					if not tb.is_empty():
						dr.beam_ang = lerp_angle(dr.beam_ang, (tb[0].pos - dr.pos).angle(), clampf(dt * LASER_TURN, 0.0, 1.0))
					dr["fire_t"] = 0.2
					dr["face"] = signf(cos(dr.beam_ang)) if absf(cos(dr.beam_ang)) > 0.1 else dr.get("face", 1.0)
					dr.beam_tick -= dt
					if dr.beam_tick <= 0.0:
						dr.beam_tick = 0.1
						_drone_laser(dr.pos, dr.beam_ang)
			if dl >= 3:
				dr.cd_missile -= dt * haste
				if dr.cd_missile <= 0.0:
					var tm := _nearest(4, 520.0)
					if tm.is_empty():
						dr.cd_missile = 0.3
					else:
						dr.cd_missile = 2.2
						var n := 3 if dl >= 5 else 2
						for k in n:
							var tg: Dictionary = tm[k % tm.size()]
							var d0 := Vector2.from_angle(-PI / 2.0 + (k - (n - 1) / 2.0) * 0.7)
							bullets.append({"kind": "missile", "pos": dr.pos, "vel": d0 * 320.0, "dmg": 26.0 * dmg_mult, "life": 4.0, "r": 7.0,
								"aoe": 70.0, "home": tg, "turn": 9.0, "accel": 2400.0, "vmax": 820.0})
						Sfx.play("swing_heavy", -16.0, 1.8, 0.05)
						dr["fire_t"] = 0.25
	# 触须阵
	var fl: int = [0, 2, 4][int(growth.get("t_field", 0))] if evo1 == "tendril" else 0   # 群触·阵
	if fl > 0:
		field_cd -= dt
		if field_cd <= 0.0:
			field_cd = 3.5
			for k in (2 if fl >= 4 else 1):
				var c := _densest_point(380.0)
				if c != Vector2.INF:
					var fr := 70.0 * (1.3 if fl >= 2 else 1.0)
					var dur := 2.4 if fl >= 5 else 1.8
					fields.append({"pos": c + Vector2(randf_range(-30, 30), randf_range(-30, 30)) * k, "r": fr, "life": dur, "max": dur, "tick": 0.0,
						"bind": fl >= 3, "dmg": 9.0 * dmg_mult * (1.6 if fl >= 5 else 1.0)})
					Sfx.play("tentacle", -8.0, 0.7, 0.05)
	for f in fields:
		f.life -= dt
		f.tick -= dt
		if f.tick <= 0.0:
			f.tick = 0.3
			for j in _query(f.pos, f.r + 20.0):
				var e: Dictionary = enemies[j]
				if not e.dead and e.pos.distance_to(f.pos) < f.r + e.r * 0.5:
					out_src = "触须阵"
					_damage(e, f.dmg)
					if f.bind and not e.boss and not e.dead:
						e.stun = maxf(e.stun, 0.35)
	fields = fields.filter(func(f): return f.life > 0.0)
	# 潮汐弹
	var tl: int = [0, 2, 4][int(growth.get("b_echo", 0))] if evo1 == "blade" else 0   # 潮刃·回响
	if tl > 0:
		tide_shot_cd -= dt
		if tide_shot_cd <= 0.0:
			var ts3 := _nearest(2, 420.0)
			if ts3.is_empty():
				tide_shot_cd = 0.2
			else:
				tide_shot_cd = 2.2 * (0.7 if tl >= 5 else 1.0)
				var bounces := 3 + (2 if tl >= 2 else 0) + (3 if tl >= 5 else 0)
				for k in (2 if tl >= 3 else 1):
					var tg: Dictionary = ts3[k % ts3.size()]
					var d: Vector2 = (tg.pos - ppos).normalized()
					bullets.append({"kind": "tide", "pos": ppos + Vector2(0, -20), "vel": d * 520.0, "dmg": 16.0 * dmg_mult * (1.5 if tl >= 4 else 1.0),
						"life": 1.0, "r": 7.0, "aoe": 0.0, "bounces": bounces, "hit": {}, "push": tl >= 4})
				Sfx.play("pickup", -10.0, 0.8, 0.05)


## 无人机激光：照射 LASER_DUR 秒，每 0.1 秒对直线上的敌人结算一次（总伤害约为旧版单发的 1.6 倍，冷却 1.5→1.9 秒）
const LASER_DUR := 0.9
const LASER_LEN := 520.0
const LASER_TURN := 7.0


func _drone_laser(from: Vector2, ang: float) -> void:
	var dir := Vector2.from_angle(ang)
	var L := LASER_LEN
	var dmg := 3.4 * dmg_mult
	for j in _query(from + dir * L * 0.5, L * 0.5 + 30.0):
		var e: Dictionary = enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - from
		var along := rel.dot(dir)
		if along < 0.0 or along > L:
			continue
		if absf(rel.cross(dir)) < e.r + 8.0:
			out_src = "无人机激光"
			_damage(e, dmg)
			if randf() < 0.4:
				_sparks(e.pos, dir, Color(0.6, 1.0, 1.0), 2, 160.0)


## 敌人最密集的位置（在 radius 内采样）
func _densest_point(radius: float) -> Vector2:
	var best := Vector2.INF
	var bn := 0
	var cand := _nearest(12, radius)
	for c in cand:
		var n := 0
		for j in _query(c.pos, 90.0):
			if not enemies[j].dead and enemies[j].pos.distance_to(c.pos) < 90.0:
				n += 1
		if n > bn:
			bn = n
			best = c.pos
	return best


func _support_radius(lv: int) -> float:
	return 85.0 + 15.0 * lv


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
					var nt := _nearest(1, 300.0)
					b.home = nt[0] if nt.size() > 0 else null
			else:
				var want: Vector2 = (hm.pos - b.pos).normalized() * b.vel.length()
				b.vel = b.vel.lerp(want, clampf(dt * b.get("turn", 6.0), 0.0, 1.0))
		# 导弹：持续加速到最高速并保持（没有目标时直线飞行，不会减速）
		if b.has("accel"):
			var sp: float = minf(b.vel.length() + b.accel * dt, b.vmax)
			b.vel = b.vel.normalized() * sp
		b.pos += b.vel * dt
		b.life -= dt
		if b.kind == "wave":
			_update_wave(b, dt)
			continue
		if b.kind == "fire" or b.kind == "missile":
			b.trail = b.get("trail", 0.0) - dt
			if b.trail <= 0.0:
				b.trail = 0.03
				fx.append({"kind": "spark", "pos": b.pos - b.vel.normalized() * 6.0, "vel": -b.vel * 0.1 + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
					"sz": 3.0, "life": 0.3, "max": 0.3, "col": Color(1.0, 0.55, 0.2) if b.kind == "fire" else Color(0.9, 0.9, 1.0)})
		for j in _query(b.pos, 40.0):
			var e: Dictionary = enemies[j]
			if e.dead or b.pos.distance_to(e.pos) > e.r + b.r:
				continue
			if b.get("hit", {}).has(e.id):
				continue
			_bullet_hit(b, e)
			break


## 水刃：穿透，每个敌人只命中一次；月轮飞到一半折返（回程可再次命中）
func _update_wave(b: Dictionary, dt: float) -> void:
	if b.moon and not b.ret and b.life < b.max * 0.5:
		b.ret = true
		b.hit = {}
	if b.ret:
		var back: Vector2 = ppos + Vector2(0, -18) - b.pos
		b.vel = b.vel.lerp(back.normalized() * 620.0, clampf(dt * 6.0, 0.0, 1.0))
		if back.length() < 24.0:
			b.life = 0.0
			return
	for j in _query(b.pos, b.r + 30.0):
		var e: Dictionary = enemies[j]
		if e.dead or b.hit.has(e.id) or e.pos.distance_to(b.pos) > b.r + e.r:
			continue
		b.hit[e.id] = true
		out_src = "水刃"
		_damage(e, b.dmg)
		if not e.dead:
			e.slow = maxf(e.slow, 1.0)
		if b.giant and not e.dead:
			e.stun = maxf(e.stun, 1.0)
		if not e.boss and not e.dead:
			e.kb += b.vel.normalized() * (260.0 if b.giant else 120.0)
		_sparks(e.pos, b.vel, Color(0.7, 1.0, 1.0), 2, 180.0)
		# 默认不穿透：命中即碎（潮刃·贯 可穿透 2 名 / 无限；深渊巨斩总是穿透）
		var pn: int = [0, 2, 999][int(growth.get("b_pierce", 0))]
		if not b.giant and b.hit.size() > pn:
			b.life = 0.0
			fx.append({"kind": "ring", "pos": b.pos, "r": b.r * 0.8, "life": 0.2, "max": 0.2, "col": Color(0.6, 1.0, 1.0)})
			return


## 子弹命中：按种类结算伤害与特效
func _bullet_hit(b: Dictionary, e: Dictionary) -> void:
	out_src = "无人机" if b.kind in ["dbullet", "missile"] else ("潮汐弹" if b.kind == "tide" else ("法术援护" if b.kind in ["fire", "arcane"] else "援护"))
	match b.kind:
		"arrow":
			# 狙击：命中流血；扼喉之手处决
			_damage(e, b.dmg)
			if rfx.sniper_execute(e):
				_add_text(e.pos + Vector2(0, -e.r - 12), "处决", Color(1.0, 0.4, 0.4), 15)
				out_src = "真实"
				_damage(e, e.hp + 1.0)
			if not e.dead:
				e["bleed"] = 3.0
				e["bleed_dps"] = b.dmg * 0.2
			for k in 7:
				fx.append({"kind": "spark", "pos": e.pos, "vel": b.vel.normalized().rotated(randf_range(-0.7, 0.7)) * randf_range(80, 220),
					"sz": 3.0, "life": 0.4, "max": 0.4, "col": Color(0.85, 0.08, 0.12)})
			fx.append({"kind": "blood", "pos": e.pos + Vector2(0, e.r * 0.6), "life": 2.5, "max": 2.5, "seed": randf() * 10.0})
			_fx_sprite("fx_arrow_hit", e.pos, PX, b.vel.angle())
			b.life = 0.0
		"fire", "missile":
			# 火球 / 导弹：爆炸
			for k in _query(b.pos, b.aoe + 20.0):
				var o: Dictionary = enemies[k]
				if not o.dead and o.pos.distance_to(b.pos) < b.aoe + o.r:
					_damage(o, b.dmg)
			var fc := Color(1.0, 0.5, 0.15) if b.kind == "fire" else Color(1.0, 0.8, 0.4)
			# 美术 V6：爆炸帧条按伤害半径缩放（半径 / 26，限制 1.5–3.0），首帧叠判定圈
			var ename := "fx_fire_explode" if b.kind == "fire" else "fx_missile_explode"
			if _fx_sprite(ename, b.pos, clampf(b.aoe / EXPLODE_R_PX, 1.5, 3.0)):
				fx[-1]["ring"] = b.aoe
			else:
				fx.append({"kind": "explode", "pos": b.pos, "r": b.aoe, "life": 0.4, "max": 0.4, "col": fc})
			for k in 6:
				fx.append({"kind": "spark", "pos": b.pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(60, 240), "sz": 3.0, "life": 0.45, "max": 0.45,
					"col": fc.lerp(Color(1, 0.95, 0.6), randf())})
			Sfx.play("boom", -14.0 if b.kind == "fire" else -11.0, 1.5, 0.1)
			b.life = 0.0
		"arcane":
			_damage(e, b.dmg)
			if not e.dead:
				e.slow = maxf(e.slow, 1.0)
			if not _fx_sprite("fx_arcane_hit", e.pos):
				fx.append({"kind": "ring", "pos": e.pos, "r": 22.0, "life": 0.25, "max": 0.25, "col": Color(0.8, 0.45, 1.0)})
			_sparks(e.pos, b.vel, Color(0.85, 0.5, 1.0), 3, 160.0)
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
		if g.mag or d < pickup * (1.2 if lamp >= 70.0 else (0.7 if lamp < 30.0 else 1.0)):
			g.mag = true
			g.pos = g.pos.move_toward(ppos, 480.0 * dt)
		if d < 18.0:
			g.dead = true
			match g.kind:
				"xp":
					_gain_xp(g.val)
					Sfx.play("pickup", -14.0, 1.0 + min(xp / xp_need, 1.0) * 0.4, 0.03)
				"oil":
					var add: float = g.val * oil_mult
					lamp = min(100.0, lamp + add)
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
					_heal(hv)
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
	xp += v
	while xp >= xp_need:
		xp -= xp_need
		level += 1
		xp_need = 24.0 + level * 8.0 + floor(level * level * 0.8)
		pending_levelups += 1
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
	if not skill_cut.is_empty():
		skill_cut.t += dt
		if skill_cut.t > 1.1:
			skill_cut = {}
	horde_warn = maxf(0.0, horde_warn - dt)
	tab_hint = maxf(0.0, tab_hint - dt)
	horde_hit = maxf(0.0, horde_hit - dt)
	lvup_delay -= dt
	lvup_show -= dt
	hud_lv_flash = max(0.0, hud_lv_flash - dt * 1.5)
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
	var en_label := "RELIC" if choice_kind == "relic" else "LEVEL UP"
	if choice_kind == "shop":
		en_label = "MERCHANT"
	if choices.size() > 0 and choices[0].kind == "evo":
		en_label = "EVOLUTION"
	elif choices.size() > 0 and choices[0].kind == "recruit":
		en_label = "RECRUIT"
	var w := font.get_string_size(en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + en_label.length() * 4.0
	UI.en(panel, font, Vector2(vs.x / 2 - w / 2, 80), en_label, 12, title_col, 4.0)
	UI.heading(panel, font, Vector2(vs.x / 2, 106), panel_title_text, 26, title_col, 300.0)
	var hint := ("点击或按 1–5 购买 · " + ("已刷新过" if shop_refreshed else "F 刷新一次（%d 源石锭）" % _shop_price("refresh")) + " · Esc 离开") if choice_kind == "shop" else "点击卡片，或按 1 / 2 / 3 选择"
	UI.text(panel, font, Vector2(0, vs.y - 46), hint, 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _show_choices(title: String, opts: Array, kind: String) -> void:
	choices = opts
	choice_kind = kind
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
		desc.text = o.desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(26, 218)
		desc.size = Vector2(228, 92)
		desc.add_theme_font_size_override("font_size", 15)
		desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.88))
		desc.add_theme_constant_override("line_spacing", 4)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		card.set_meta("desc", desc)
		card.set_meta("dy", 218.0)
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
		var target := -10.0 if ((card as Button).is_hovered() and not sold) else 0.0
		var lift: float = lerpf(card.get_meta("lift"), target, clampf(dt * 18.0, 0.0, 1.0))
		card.set_meta("lift", lift)
		var oy := (1.0 - e) * 60.0 + lift
		card.set_meta("oy", oy)
		card.modulate.a = clampf(age / 0.2, 0.0, 1.0)
		var desc: Label = card.get_meta("desc", null)
		if desc != null:
			desc.position.y = float(card.get_meta("dy", 230.0)) + oy
		card.queue_redraw()


func _skill_item(sid: String) -> Dictionary:
	var sk: Dictionary = D.SKILLS[sid]
	return {"tag": "技能", "tag_en": "SKILL", "glyph": sk.glyph, "icon": "skill_" + sid, "name": sk.name, "desc": sk.desc, "col": sk.col}


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
	Sfx.play("relic", 0.0, 0.8, 0.0)
	Sfx.play("levelup", -4.0, 0.7, 0.0)


func _close_show() -> void:
	if state != S.SHOW or show_t < 1.0:
		return
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
	# 左侧：水月演示
	var cx := Vector2(330, vs.y * 0.58)
	var da := clampf((st - 0.35) / 0.35, 0.0, 1.0)
	for k in 3:
		var rp := fmod(st * 0.8 + k / 3.0, 1.0)
		hud.draw_arc(cx + Vector2(0, -10), 60.0 + rp * 130.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, (1.0 - rp) * 0.5 * da), 3.0)
	hud.draw_circle(cx + Vector2(0, 58), 70.0, Color(col.r, col.g, col.b, 0.08 * da))
	hud.draw_set_transform(cx + Vector2(0, 58), 0.0, Vector2(1.0, 0.3))
	hud.draw_circle(Vector2.ZERO, 60.0, Color(0, 0, 0, 0.5 * da))
	hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var at: Texture2D = tex.get("player_attack_48")
	if at != null:
		var n := at.get_width() / at.get_height()
		var fh := at.get_height()
		var spd := 12.0 if sc.demo == "s2" else 7.0
		var fr := int(st * spd) % n
		var S5 := 5.0
		var size := Vector2(fh, fh) * S5
		var dst := Rect2(cx - Vector2(size.x / 2.0, size.y - 60.0 + 2.0 * S5), size)
		if sc.demo == "s3":
			# 镜花水月：镜像残影
			var ghost := Rect2(dst.position + Vector2(-70, 0), dst.size)
			hud.draw_set_transform(ghost.position + Vector2(ghost.size.x, 0), 0.0, Vector2(-1, 1))
			hud.draw_texture_rect_region(at, Rect2(Vector2.ZERO, ghost.size), Rect2(fh * ((fr + 2) % n), 0, fh, fh), Color(0.8, 0.6, 1.0, 0.35 * da))
			hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		hud.draw_texture_rect_region(at, dst, Rect2(fh * fr, 0, fh, fh), Color(1, 1, 1, da))
		# 技能特效示意
		var sl: Texture2D = tex.get("slash")
		if sl != null and fr >= 1:
			var sfw := sl.get_width() / 4
			var sfr := clampi(fr - 1, 0, 3)
			var ssz := Vector2(sfw, sl.get_height()) * (7.0 if sc.demo == "s3" else 5.0)
			hud.draw_texture_rect_region(sl, Rect2(cx + Vector2(-ssz.x / 2.0 + 60.0, -ssz.y / 2.0 - 70.0), ssz), Rect2(sfw * sfr, 0, sfw, sl.get_height()), Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 0.9 * da))
		if sc.demo == "s2":
			# 囚徒困境：束缚锁链环
			for j in 6:
				var ang := st * 2.0 + TAU * j / 6.0
				var p := cx + Vector2(0, -80) + Vector2.from_angle(ang) * Vector2(150, 60)
				UI.diamond(hud, p, 7.0, Color(0.02, 0.06, 0.1, da), Color(col.r, col.g, col.b, da))
	# 右侧：说明卡
	var items: Array = sc["items"]
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
		hud.draw_multiline_string(font, r.position + Vector2(150, 106), it.desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 172, 15, 3, Color(0.78, 0.88, 0.9, e))
	if st > 1.0:
		var ba := 0.5 + 0.5 * sin(st * 4.0)
		UI.text(hud, font, Vector2(0, vs.y - 40), "点击或按任意键继续", 15, Color(0.75, 0.88, 0.92, 0.5 + 0.5 * ba), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


## 卡片图标：按种类取对应贴图（relic_ / growth_ / weapon_ / evo_ / skill_），没有则返回 null
func _card_icon(o: Dictionary) -> Texture2D:
	match o.kind:
		"relic":
			return tex.get("relic_" + o.id)
		"growth":
			return tex.get("growth_" + o.id)
		"weapon":
			return tex.get("weapon_" + o.id)
		"evo":
			return tex.get("evo_" + o.id)
		"skill":
			return tex.get("skill_" + o.id)
	return null


func _card_color(o: Dictionary) -> Color:
	match o.kind:
		"relic":
			return UI.CAT_COL.get(RL[o.id].cat, UI.GOLD)
		"recruit":
			return Color(0.55, 0.9, 0.55)
		"skill":
			return D.SKILLS[o.id].col
		"weapon":
			return D.WEAPONS[o.id].col
		"evo":
			return D.EVO[o.id].col
	return UI.CYAN


func _draw_card(card: Button, o: Dictionary, i: int) -> void:
	var hov := card.is_hovered()
	var col := _card_color(o)
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	UI.frame(card, r, col, {"t": t, "vines": true, "seed": 20 + i, "vine_k": 1.0 if hov else 0.75, "glow": 1.0 if hov else 0.25, "cut": 12.0, "bracket": 12.0})
	# 顶部分类标签
	var cat := "成长  GROWTH"
	if o.kind == "relic":
		cat = RL[o.id].cat + "  ·  " + RL[o.id].rarity
	elif o.kind == "recruit":
		cat = "招募  " + D.ALLIES[o.id].en
	elif o.kind == "skill":
		cat = "技能进阶  " + ("I" if o.stage == 1 else "II")
	elif o.kind == "weapon":
		cat = "武器  " + D.WEAPONS[o.id].en
	elif o.kind == "evo":
		cat = ("进化  " if not D.EVO[o.id].has("path") else "质变  ") + D.EVO[o.id].en
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
	elif o.kind == "evo":
		glyph = D.EVO[o.id].glyph
	var ic: Texture2D = _card_icon(o)
	var bob := sin(t * 2.0 + i) * 2.0
	if o.kind == "recruit":
		var at: Texture2D = tex["ally_" + o.id]
		var fw := at.get_width() / 2
		var ks: float = 2.0 if at.get_height() <= 48 else 72.0 / at.get_height()
		var asz := Vector2(fw, at.get_height()) * ks
		card.draw_texture_rect_region(at, Rect2(c - asz / 2.0 + Vector2(0, bob + 4), asz), Rect2(0, 0, fw, at.get_height()))
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


func _open_recruit() -> bool:
	var opts: Array = []
	for k in D.ALLIES:
		var a: Dictionary = D.ALLIES[k]
		var cur: Dictionary = {}
		for al in allies:
			if al.kind == k:
				cur = al
		if cur.is_empty() and allies.size() < 3:
			opts.append({"kind": "recruit", "id": k, "name": a.name, "desc": a.desc})
		elif not cur.is_empty() and cur.lv < 3:
			opts.append({"kind": "recruit", "id": k, "name": "%s  Lv.%d" % [a.name, cur.lv + 1], "desc": a.up})
	if opts.is_empty():
		return false
	opts.shuffle()
	_show_choices("招募援护干员", opts.slice(0, 3), "level")
	return true


func _open_levelup() -> void:
	if recruit_idx < D.RECRUIT_LEVELS.size() and level >= D.RECRUIT_LEVELS[recruit_idx]:
		recruit_idx += 1
		if _open_recruit():
			return
	# 精英化节点（精英化一在 _check_pending 中先播放解锁演出）
	if level >= 19 and elite_stage == 1:
		elite_stage = 2
		var mopts: Array = []
		for k in D.EVO:
			if D.EVO[k].get("path", "") == evo1 and evo1 != "":
				mopts.append({"kind": "evo", "id": k, "name": "质变 · " + D.EVO[k].name, "desc": D.EVO[k].desc})
		if mopts.is_empty():
			for k in D.EVO:
				if D.EVO[k].has("path"):
					mopts.append({"kind": "evo", "id": k, "name": "质变 · " + D.EVO[k].name, "desc": D.EVO[k].desc})
		_show_choices("精英化二：%s的质变（同时解锁「镜花水月」）" % D.EVO.get(evo1, {"name": ""}).name, mopts, "level")
		return
	# ---- 升级三选一：1 张「路线」卡（路线专属升级 / 技能进阶）+ 2 张通用成长；无人机卡按概率替换一张通用卡
	var route: Array = []
	var general: Array = []
	for gid in D.GROWTH:
		var g: Dictionary = D.GROWTH[gid]
		var n: int = growth.get(gid, 0)
		if n >= g.max or (g.has("path") and g.path != evo1):
			continue
		var nm: String = g.name if g.max > 90 else "%s  %d/%d" % [g.name, n + 1, g.max]
		var card := {"kind": "growth", "id": gid, "name": nm, "desc": g.desc + "\n" + _growth_preview(gid)}
		if g.has("path"):
			route.append(card)
		else:
			general.append(card)
	for sid in ["s1", "s2", "s3"]:
		var lv: int = skill_lv[sid]
		if lv >= 1 and lv < 3:
			var ad: Dictionary = D.SKILL_ADV[sid][lv - 1]
			if level >= ad.min_lv:
				route.append({"kind": "skill", "id": sid, "name": "%s · %s" % [D.SKILLS[sid].name, ad.name], "desc": ad.desc, "stage": lv})
	route.shuffle()
	general.shuffle()
	var picks: Array = []
	if not route.is_empty():
		picks.append(route[0])
	var want: int = 3 + rfx.rule("four_choices")
	for c in general:
		if picks.size() >= want:
			break
		picks.append(c)
	var ri := 1
	while picks.size() < want and ri < route.size():
		picks.append(route[ri])
		ri += 1
	# 无人机：首次在 Lv.2 后必出一张，之后约 35%
	var wl: int = weapons.get("drone", 0)
	if wl < 5 and level >= 2 and picks.size() >= 2 and (wl == 0 or rng.randf() < 0.35):
		var W: Dictionary = D.WEAPONS.drone
		var wcard := {"kind": "weapon", "id": "drone", "name": ("%s  Lv.%d" % [W.name, wl + 1]) if wl > 0 else "新武器 · " + W.name,
			"desc": W.lv[wl], "wlv": wl + 1}
		picks[picks.size() - 1] = wcard
	picks.shuffle()
	_show_choices("升级！ Lv.%d" % level, picks, "level")


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
		"growth":
			growth[o.id] = growth.get(o.id, 0) + 1
			_apply_growth(o.id)
		"recruit":
			var found := false
			for al in allies:
				if al.kind == o.id:
					al.lv += 1
					found = true
			if not found:
				allies.append({"kind": o.id, "lv": 1, "pos": ppos + Vector2(rng.randf_range(-40, 40), 30), "cd": 0.5})
				_show_banner("援护干员「%s」加入编队" % D.ALLIES[o.id].name)
		"relic":
			if not relics.has(o.id):
				relics.append(o.id)
			_apply_relic(o.id)
		"evo":
			var ev: Dictionary = D.EVO[o.id]
			if not ev.has("path"):
				evo1 = o.id
				_show_banner("进化方向：%s" % ev.name)
				fx.append({"kind": "rays", "pos": ppos, "life": 0.7, "max": 0.7, "col": ev.col})
				fx.append({"kind": "ring", "pos": ppos, "r": 160.0, "life": 0.6, "max": 0.6, "col": ev.col})
				_shake(0.6)
			else:
				evo2 = o.id
				skill_lv.s3 = 1
				s3_sp = 30.0
				show_queue.append({"head": "精英化二", "en": "ELITE  PROMOTION  II", "col": Color(0.8, 0.55, 1.0), "demo": "s3", "items": [
					_skill_item("s3"),
					{"tag": "质变", "tag_en": "EVOLUTION", "glyph": ev.glyph, "icon": "evo_" + o.id, "name": "%s · %s" % [D.EVO[evo1].name, ev.name], "desc": ev.desc, "col": ev.col}]})
		"weapon":
			weapons[o.id] = o.wlv
			var W: Dictionary = D.WEAPONS[o.id]
			_show_banner(("获得武器「%s」" if o.wlv == 1 else "「%s」升至 Lv.%d") % ([W.name] if o.wlv == 1 else [W.name, o.wlv]))
			fx.append({"kind": "ring", "pos": ppos, "r": 110.0, "life": 0.45, "max": 0.45, "col": W.col})
		"skill":
			skill_lv[o.id] += 1
			var sk: Dictionary = D.SKILLS[o.id]
			var ad: Dictionary = D.SKILL_ADV[o.id][o.stage - 1]
			_show_banner("技能进阶：%s · %s" % [sk.name, ad.name])
			fx.append({"kind": "rays", "pos": ppos, "life": 0.6, "max": 0.6, "col": sk.col})
			fx.append({"kind": "ring", "pos": ppos, "r": 120.0, "life": 0.5, "max": 0.5, "col": sk.col})
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


## 升级卡上的数值预览：「当前 → 升级后」
func _growth_preview(id: String) -> String:
	match id:
		"u_dmg": return "伞击伤害 %d → %d" % [int(18 * u_dmg_mult * dmg_mult), int(18 * u_dmg_mult * 1.15 * dmg_mult)]
		"u_area": return "挥砍半径 %d → %d" % [int(95 * u_area_mult), int(95 * u_area_mult * 1.12)]
		"u_spd": return "挥伞间隔 %.2f → %.2f 秒" % [0.9 * u_spd_mult, 0.9 * u_spd_mult * 0.9]
		"t_dmg": return "触手倍率 ×%.2f → ×%.2f" % [t_mult, t_mult * 1.2]
		"sp": return "技力回复 ×%.2f → ×%.2f" % [sp_mult, sp_mult * 1.15]
		"dodge": return "闪避 %d%% → %d%%" % [int(dodge * 100), int(dodge * 100) + 5]
		"hp": return "最大生命 %d → %d" % [int(max_hp), int(max_hp) + 20]
		"speed": return "移动速度 %d → %d" % [int(speed), int(speed * 1.1)]
		"pickup": return "拾取范围 %d → %d" % [int(pickup), int(pickup * 1.3)]
		"regen": return "生命回复 %.1f → %.1f / 秒" % [regen, regen + 0.6]
		"armor": return "减伤 %d → %d" % [int(armor), int(armor) + 1]
		"wick": return "灯火消耗 ×%.2f → ×%.2f" % [lamp_decay, lamp_decay * 0.85]
	return ""


func _apply_growth(id: String) -> void:
	match id:
		"u_dmg": u_dmg_mult *= 1.15
		"u_area": u_area_mult *= 1.1
		"u_spd": u_spd_mult *= 0.92
		"t_dmg": t_mult *= 1.2
		"sp":
			sp_mult *= 1.15
			s1_need = max(5, s1_need - 1)
		"dodge": dodge += 0.05
		"hp":
			max_hp += 20.0
			hp += 20.0
		"speed": speed *= 1.1
		"pickup": pickup *= 1.3
		"regen": regen += 0.6
		"armor": armor += 2.0
		"wick": lamp_decay *= 0.85


func _apply_relic(id: String) -> void:
	rfx.apply(id)


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
	cam.position = ppos.round()
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
	var s2 := shake * shake
	cam.offset = (Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 10.0 * s2 + cam_kick).round()
	# 灯火光源：半径随灯火变化，快熄灭时闪烁
	var radius: float = lerp(150.0, 520.0, lamp / 100.0)
	var flicker := 1.0 + sin(t * 13.0) * 0.02 + sin(t * 7.3) * 0.03
	if lamp < 30.0:
		flicker += sin(t * 23.0) * 0.06
	lamp_light.position = ppos + Vector2(0, -20)
	lamp_light.texture_scale = radius / 64.0 * flicker
	lamp_light.color = Color(1.0, 0.86, 0.62) if lamp >= 30.0 else Color(1.0, 0.6, 0.5)
	# 海中浮游颗粒
	var vs := get_viewport_rect().size
	for s in snow:
		s.p.y -= s.v * dt
		s.s += dt
		var rel: Vector2 = s.p - ppos
		if rel.y < -vs.y * 0.6:
			s.p.y += vs.y * 1.2
		elif rel.y > vs.y * 0.6:
			s.p.y -= vs.y * 1.2
		if rel.x < -vs.x * 0.6:
			s.p.x += vs.x * 1.2
		elif rel.x > vs.x * 0.6:
			s.p.x -= vs.x * 1.2


## 以美术像素为单位绘制横向帧条中的一帧，anchor 为贴图内的锚点（0~1）
## 美术 V6 帧条：名称 -> [帧数, fps]
const V6_FRAMES := {
	"proj_arrow": [1, 0.0], "proj_fireball": [4, 12.0], "proj_arcane": [4, 12.0], "proj_drone_bullet": [1, 0.0],
	"proj_missile": [2, 16.0], "proj_tide": [4, 10.0],
	"fx_fire_explode": [6, 15.0], "fx_missile_explode": [6, 15.0], "fx_arrow_hit": [4, 20.0], "fx_bullet_hit": [3, 24.0],
	"fx_arcane_hit": [4, 20.0], "fx_tide_hit": [4, 20.0], "fx_heal_cross": [4, 10.0],
	"fx_laser_start": [4, 20.0], "fx_laser_mid": [4, 20.0], "fx_laser_end": [4, 20.0],
}
const PROJ_TEX := {"arrow": "proj_arrow", "fire": "proj_fireball", "arcane": "proj_arcane", "dbullet": "proj_drone_bullet",
	"missile": "proj_missile", "tide": "proj_tide"}
const EXPLODE_R_PX := 26.0


## 激光三段：起点（枪口）+ 平铺中段（末段按长度裁切，不拉伸）+ 末端光斑
func _draw_laser_art(from: Vector2, ang: float, length: float, alpha: float) -> void:
	var fr := int(t * 20.0) % 4
	var mt: Texture2D = tex["fx_laser_mid"]
	var fw := mt.get_width() / 4
	var fh := mt.get_height()
	var col := Color(1, 1, 1, alpha)
	draw_set_transform(from, ang, Vector2(PX, PX))
	var L := length / PX
	var x := 0.0
	while x < L:
		var w := minf(float(fw), L - x)
		draw_texture_rect_region(mt, Rect2(Vector2(x, -fh / 2.0), Vector2(w, fh)), Rect2(fw * fr, 0, w, fh), col)
		x += fw
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_spr_rot("fx_laser_end", fr, from + Vector2.from_angle(ang) * length, ang, PX, col)
	_spr_rot("fx_laser_start", fr, from, ang, PX, col)


## 旋转绘制帧条（锚点为帧中心，朝右绘制的素材按 ang 旋转）
func _spr_rot(name: String, frame: int, pos: Vector2, ang: float, scale := PX, col := Color.WHITE, anchor_px := Vector2(-1, -1)) -> void:
	var tx: Texture2D = tex.get(name)
	if tx == null:
		return
	var frames: int = V6_FRAMES.get(name, [1, 0.0])[0]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var an := anchor_px if anchor_px.x >= 0.0 else Vector2(fw, fh) / 2.0
	draw_set_transform(pos + draw_off, ang, Vector2(scale, scale))
	draw_texture_rect_region(tx, Rect2(-an, Vector2(fw, fh)), Rect2(fw * (frame % frames), 0, fw, fh), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 一次性帧动画特效（命中 / 爆炸）；素材不存在时返回 false，调用方回退到程序特效
func _fx_sprite(name: String, pos: Vector2, scale := PX, ang := 0.0) -> bool:
	if tex.get(name) == null:
		return false
	var spec: Array = V6_FRAMES[name]
	var dur: float = spec[0] / spec[1]
	fx.append({"kind": "sprite", "name": name, "pos": pos, "ang": ang, "scale": scale, "life": dur, "max": dur})
	return true


func _spr(name: String, frames: int, frame: int, pos: Vector2, scale := PX, flip := false, col := Color.WHITE, anchor := Vector2(0.5, 0.5), sq := Vector2.ONE) -> void:
	var tx: Texture2D = tex[name]
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
	_draw_bg()
	for m in mires:
		_draw_mire(m)
	bai._draw_warns()
	rfx.draw()
	if not merchant.is_empty():
		_spr("shadow", 1, 0, merchant.pos + Vector2(0, 18), PX * 1.2)
		_spr("merchant", 2, int(t * 2.0) % 2, merchant.pos, PX)
		UI.text(self, font, merchant.pos + Vector2(-40, -34), "商人", 13, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
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
				_spr("gem_big" if g.val >= 5.0 else "gem_small", 1, 0, g.pos + Vector2(0, sin(t * 4.0 + g.pos.x) * 2.0 if gz <= 1.0 else 0.0))
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
	if s2_active > 0.0 and tex.get("fx_s2_aura") == null:
		draw_arc(ppos + Vector2(0, -10), 30.0 + sin(t * 6.0) * 2.0, 0.0, TAU, 20, Color(0.5, 0.8, 1.0, 0.6), 2.0)
	if s3_active > 0.0 and tex.get("fx_s3_aura") == null:
		draw_arc(ppos + Vector2(0, -10), 40.0 + sin(t * 4.0) * 3.0, 0.0, TAU, 24, Color(0.8, 0.55, 1.0, 0.7), 3.0)
		draw_circle(ppos + Vector2(0, -10), 36.0, Color(0.6, 0.4, 1.0, 0.08))
	for e in enemies:
		var sc: float = PX * e.r / 10.0
		var hop: float = minf(e.kb.length() * 0.03, 14.0)
		_spr("shadow", 1, 0, e.pos + Vector2(0, e.r * 0.8), sc * (1.0 - hop / 40.0))
	for al in allies:
		_spr("shadow", 1, 0, al.pos + Vector2(0, 16), PX)
	for f in fx:
		if f.kind == "tentacle":
			_draw_tentacle(f)
	_draw_skill_floor()
	for f in fields:
		_draw_field(f)
	for st in stakes:
		_draw_stake(st)
	for gi in giants:
		_draw_giant(gi)
	for i in range(afterimg.size() - 1, -1, -1):
		var ai: Dictionary = afterimg[i]
		var aa := 0.45 * (1.0 - float(i) / afterimg.size())
		_draw_player_at(ai.pos + Vector2(0, 6), ai.flip, Color(0.9, 0.55, 1.8, aa), ai.frame, ai.tex, ai.hf)
	if s3_active > 0.0 and skill_lv.s3 >= 2:
		var ma := minf(1.0, s3_active * 3.0) * (0.62 + 0.08 * sin(t * 6.0))
		_draw_player_at(mirror_pos + Vector2(0, 6), mirror_face < 0.0, Color(0.85, 0.6, 1.9, ma), sprite.frame, sprite.texture, sprite.hframes)
	# ---- 2.5D 前后遮挡：按脚底 y 排序后依次绘制 ----
	var dl: Array = []
	for e in enemies:
		dl.append([e.pos.y + e.r * 0.8, 0, e])
	for i in allies.size():
		dl.append([allies[i].pos.y + 16.0, 1, i])
	dl.append([ppos.y + 6.0, 2, null])
	for pr in sort_props:
		dl.append([pr[1].y, 3, pr])
	dl.sort_custom(func(a, b): return a[0] < b[0])
	for it in dl:
		match it[1]:
			0:
				_draw_enemy(it[2])
			1:
				var i: int = it[2]
				var al: Dictionary = allies[i]
				var atx: Texture2D = tex["ally_" + al.kind]
				var akey: String = "ally_%s_attack" % al.kind
				if al.get("atk", -1.0) >= 0.0 and tex.get(akey) != null:
					# 攻击动作：72×48 画布，脚底锚点 (24,45)，朝向目标
					_spr(akey, 4, mini(3, int(al.atk * 8.0)), al.pos + Vector2(0, 16), 1.4, al.get("face", 1.0) < 0.0, Color.WHITE, Vector2(24.0 / 72.0, 45.0 / 48.0))
				elif al.get("mv", 0.0) > 40.0 and tex.get("ally_%s_move" % al.kind) != null:
					# 美术 V6：移动循环（6 帧 10fps，朝移动方向）
					_spr("ally_%s_move" % al.kind, 6, int(al.mt * 10.0) % 6, al.pos + Vector2(0, 16), 1.4, al.get("mface", 1.0) < 0.0, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
				elif atx.get_height() >= 40:
					# 48px 援护（脚底锚点约 (24,45)）
					_spr("ally_" + al.kind, 2, int(t * 3.0 + i) % 2, al.pos + Vector2(0, 16), 1.4, al.pos.x > ppos.x, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
				else:
					_spr("ally_" + al.kind, 2, int(t * 3.0 + i) % 2, al.pos, PX, al.pos.x > ppos.x, Color.WHITE, Vector2(0.5, 0.5))
			2:
				_draw_player()
			3:
				var pr: Array = it[2]
				# 挡在水月身前的海草半透明，避免遮住角色
				var fade := 1.0
				var ptx: Texture2D = tex[pr[0]]
				var pw: float = ptx.get_width() * PX / (2.0 if pr[0] == "seaweed" else 1.0) * 0.5
				var ph: float = ptx.get_height() * PX
				if pr[1].y > ppos.y and absf(pr[1].x - ppos.x) < pw + 10.0 and pr[1].y - ppos.y < ph:
					fade = 0.4
				if pr[0] == "seaweed":
					_spr("seaweed", 2, int(t * 2.0 + pr[2]) % 2, pr[1], PX, false, Color(1, 1, 1, fade), Vector2(0.5, 1.0))
				else:
					_spr(pr[0], 1, 0, pr[1], PX, pr[2] % 2 == 0, Color(1, 1, 1, fade), Vector2(0.5, 1.0))
	_draw_skill_over()
	for dr in drones:
		draw_set_transform(dr.pos + Vector2(0, 96), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(dr.pos, 20.0, Color(0.4, 1.2, 1.6, 0.18))
		# Codex 美术 V5：子弹型 / 激光型 / 导弹型，4 帧（0-1 悬浮，2 发射，3 回稳）
		var dlv: int = weapons.get("drone", 1)
		var dkey: String = "drone_bullet" if dlv == 1 else ("drone_laser" if dlv == 2 else "drone_missile")
		if tex.get(dkey) != null:
			var dfr := int(t * 6.0) % 2
			var ft: float = dr.get("fire_t", 0.0)
			if ft > 0.0:
				dfr = 2 if ft > 0.12 else 3
			_spr(dkey, 4, dfr, dr.pos, 1.0, dr.get("face", 1.0) < 0.0)
		elif tex.get("drone") != null:
			_spr("drone", 2, int(t * 20.0) % 2, dr.pos, PX, false, Color(1.6, 1.6, 1.7))
		draw_circle(dr.pos + Vector2(0, 8), 3.0, Color(1.5, 2.6, 2.8, 0.6 + 0.3 * sin(t * 8.0)))
		if dr.get("beam", 0.0) > 0.0:
			var ba: float = clampf(dr.beam / 0.15, 0.0, 1.0) * clampf((LASER_DUR - dr.beam) / 0.08, 0.3, 1.0)
			var fl := 0.85 + 0.15 * sin(t * 60.0)
			var a0: Vector2 = dr.pos + Vector2(0, 4)
			var b0: Vector2 = a0 + Vector2.from_angle(dr.beam_ang) * LASER_LEN
			draw_line(a0, b0, Color(0.4, 1.6, 2.2, 0.28 * ba), 16.0 * fl)
			if tex.get("fx_laser_mid") != null:
				_draw_laser_art(a0, dr.beam_ang, LASER_LEN, ba)
			else:
				draw_line(a0, b0, Color(0.8, 2.4, 2.8, 0.8 * ba), 6.0 * fl)
				draw_line(a0, b0, Color(3.0, 3.0, 3.0, ba), 2.0)
				draw_circle(a0, 7.0 * fl, Color(2.0, 2.8, 3.0, ba))
	var jf := int(t * 6.0) % 2
	for al in allies:
		if al.kind == "support":
			var rad: float = _support_radius(al.lv)
			draw_arc(ppos, rad, 0.0, TAU, 40, Color(0.5, 0.8, 1.0, 0.18 + 0.06 * sin(t * 3.0)), 2.0)
	for b in bullets:
		if b.life <= 0.0:
			continue
		var n: Vector2 = b.vel.normalized()
		if b.kind == "wave":
			_draw_wave(b)
			continue
		# 美术 V6：投射物帧条（朝右绘制，按速度方向旋转）；程序只画拖尾
		var ptex: String = PROJ_TEX.get(b.kind, "")
		if ptex != "" and tex.get(ptex) != null:
			var pspec: Array = V6_FRAMES[ptex]
			var pfr: int = (int(t * pspec[1] + b.pos.x * 0.01) % int(pspec[0])) if pspec[1] > 0.0 else 0
			match b.kind:
				"arrow":
					draw_line(b.pos - n * 34.0, b.pos - n * 12.0, Color(1.6, 1.4, 1.0, 0.3), 2.0)
				"fire":
					draw_circle(b.pos, 14.0, Color(2.0, 0.8, 0.2, 0.2))
				"arcane":
					draw_line(b.pos - n * 20.0, b.pos, Color(1.4, 0.6, 2.2, 0.35), 4.0)
				"dbullet":
					draw_line(b.pos - n * 14.0, b.pos, Color(1.2, 2.4, 2.6, 0.4), 2.0)
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
			"dbullet":
				draw_line(b.pos - n * 10.0, b.pos + n * 3.0, Color(1.2, 2.4, 2.6), 2.5)
			"missile":
				draw_set_transform(b.pos, b.vel.angle(), Vector2.ONE)
				draw_rect(Rect2(-7, -2.5, 12, 5), Color(0.75, 0.8, 0.9))
				draw_colored_polygon(PackedVector2Array([Vector2(5, -2.5), Vector2(9, 0), Vector2(5, 2.5)]), Color(1.0, 0.4, 0.3))
				draw_circle(Vector2(-8, 0), 3.0 + sin(t * 50.0), Color(2.5, 1.6, 0.6))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"tide":
				draw_circle(b.pos, 10.0, Color(0.5, 1.2, 2.0, 0.25))
				draw_circle(b.pos, 6.0, Color(0.7, 1.5, 2.2, 0.9))
				draw_circle(b.pos + Vector2(-2, -2), 2.0, Color(2.5, 2.5, 2.5))
			_:
				_spr("orb", 1, 0, b.pos, PX)
	for f in fx:
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		match f.kind:
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
			"laser":
				# 无人机激光
				draw_line(f.a, f.b, Color(0.4, 1.6, 2.2, 0.3 * a), 18.0 * a + 2.0)
				draw_line(f.a, f.b, Color(0.8, 2.4, 2.8, 0.8 * a), 6.0 * a + 1.0)
				draw_line(f.a, f.b, Color(3.0, 3.0, 3.0, a), 2.0)
				draw_circle(f.a, 7.0 * a + 2.0, Color(2.0, 2.8, 3.0, a))
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
				_spr("tentacle", 5, fr, f.pos + Vector2(0, 16), PX * 4.2, false, Color(1.3, 1.1, 1.6), Vector2(0.5, 1.0))
				_spr("tentacle", 5, fr, f.pos + Vector2(-50, 20), PX * 2.6, true, Color(1.1, 1.0, 1.4), Vector2(0.5, 1.0))
				_spr("tentacle", 5, fr, f.pos + Vector2(48, 22), PX * 2.4, false, Color(1.1, 1.0, 1.4), Vector2(0.5, 1.0))
			"sprite":
				var spec: Array = V6_FRAMES[f.name]
				var fr := mini(int((f.max - f.life) * spec[1]), spec[0] - 1)
				_spr_rot(f.name, fr, f.pos, f.ang, f.scale)
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
	for s in snow:
		var c := Color(0.8, 0.9, 1.0, 0.25 + 0.15 * sin(s.s * 2.0))
		draw_rect(Rect2((s.p + Vector2(sin(s.s) * 6.0, 0)).round(), Vector2(2, 2)), c)


func _draw_fx_add() -> void:
	_draw_god_rays()
	var loop := int(t * 10.0)
	if s2_active > 0.0 and tex.get("fx_s2_aura") != null:
		_spr_on(fx_add, "fx_s2_aura", FXF.fx_s2_aura, loop, ppos + Vector2(0, 4))
	if s3_active > 0.0 and tex.get("fx_s3_aura") != null:
		_spr_on(fx_add, "fx_s3_aura", FXF.fx_s3_aura, loop, ppos + Vector2(0, 4))
	var mark := "fx_s2_bind" if s2_active > 0.0 else "fx_stun"
	if tex.get(mark) != null:
		for e in enemies:
			if e.stun > 0.3:
				_spr_on(fx_add, mark, FXF[mark], loop + e.id, e.pos + Vector2(0, -e.r - 10))
	for f in fx:
		if f.kind != "anim":
			continue
		var n: int = FXF.get(f.name, 1)
		var fr := clampi(int((1.0 - f.life / f.max) * n), 0, n - 1)
		var p: Vector2 = ppos if f.follow else f.pos
		_spr_on(fx_add, f.name, n, fr, p, f.scale)


## 2.5D 远景光束：从水面斜射下来的淡光柱，视差 0.5，缓慢漂移
func _draw_god_rays() -> void:
	var vs := get_viewport_rect().size
	var cp := cam.position
	var span := 1900.0
	for k in 6:
		var base := fposmod(k * 331.0 - cp.x * 0.5 + t * 6.0, span) - span / 2.0
		var x := cp.x + base
		var w := 50.0 + 40.0 * float(k % 3)
		var top := cp.y - vs.y / 2.0 - 40.0
		var bot := cp.y + vs.y / 2.0 + 40.0
		var sl := 260.0
		var a := 0.05 + 0.03 * sin(t * 0.4 + k * 1.7)
		var c0 := Color(1.8, 2.4, 2.8, a)
		var c1 := Color(1.8, 2.4, 2.8, 0.0)
		draw_off = Vector2.ZERO
		fx_add.draw_polygon(PackedVector2Array([Vector2(x, top), Vector2(x + w, top), Vector2(x + w - sl, bot), Vector2(x - sl, bot)]),
			PackedColorArray([c0, c0, c1, c1]))


## 2.5D 前景：镜头前的虚化海草/礁石剪影，视差 1.35；靠近画面中央时变淡，不挡视线
func _draw_fg() -> void:
	if not Cfg.dof:
		return
	var vs := get_viewport_rect().size
	var cp := cam.position
	var par := 1.35
	var cell := 520.0
	var fc := cp * par
	var x0 := floori((fc.x - vs.x) / cell)
	var y0 := floori((fc.y - vs.y) / cell)
	for cx in range(x0, x0 + int(vs.x * 2.0 / cell) + 2):
		for cy in range(y0, y0 + int(vs.y * 2.0 / cell) + 2):
			var h: int = abs(hash(Vector2i(cx, cy) * 7 + Vector2i(3, 11)))
			if h % 5 > 1:
				continue
			var fp := Vector2(cx * cell + float(h % 300), cy * cell + float((h / 300) % 300))
			var wp := fp - fc + cp
			var sp := wp - cp
			var dc := Vector2(sp.x / (vs.x * 0.5), sp.y / (vs.y * 0.5)).length()
			var a := clampf((dc - 0.45) / 0.5, 0.0, 1.0) * 0.8
			if a <= 0.01:
				continue
			var tx: Texture2D = fg_tex[0 if h % 3 != 0 else 1]
			var big := 0.8 + 0.25 * float(h % 3)
			var sway := sin(t * 0.7 + float(h % 10)) * 0.06
			var size := Vector2(tx.get_width(), tx.get_height()) * big
			fg.draw_set_transform(wp, sway, Vector2(-1.0 if h % 2 == 0 else 1.0, 1.0))
			fg.draw_texture_rect(tx, Rect2(Vector2(-size.x / 2.0, -size.y), size), false, Color(0.10, 0.30, 0.34, a))
			fg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 把像素图变成柔和的剪影（取第一帧 -> 放大 -> 缩小再放大模拟高斯模糊）
func _blur_silhouette(src: Texture2D, frames: int) -> Texture2D:
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var fw := img.get_width() / frames
	var fh := img.get_height()
	var pad := 4
	var out := Image.create(fw + pad * 2, fh + pad * 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in fh:
		for x in fw:
			var a := img.get_pixel(x, y).a
			if a > 0.0:
				out.set_pixel(x + pad, y + pad, Color(1, 1, 1, a))
	var w := out.get_width()
	var h := out.get_height()
	out.resize(w * 8, h * 8, Image.INTERPOLATE_BILINEAR)
	out.resize(w * 3, h * 3, Image.INTERPOLATE_BILINEAR)
	out.resize(w * 8, h * 8, Image.INTERPOLATE_CUBIC)
	return ImageTexture.create_from_image(out)


## 同 _spr，但画在指定节点上（用于叠加发光层）
func _spr_on(ci: CanvasItem, name: String, frames: int, frame: int, pos: Vector2, scale := PX) -> void:
	var tx: Texture2D = tex[name]
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var size := Vector2(fw, fh) * scale
	ci.draw_texture_rect_region(tx, Rect2((pos - size / 2.0).round(), size), Rect2(fw * (frame % frames), 0, fw, fh))


## 主角帧动画（美术交付 player_*.png 后自动启用；帧为正方形，帧数 = 宽 / 高）
func _update_player_anim(dt: float) -> void:
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


## 水月 48px 动画（Codex 交付：idle 4 帧 4fps、run 6 帧 10fps、hurt 2 帧 10fps 单次、
## death 4 帧 6fps 停末帧、attack 用 player_attack_48 4 帧）。脚底锚点 (24,46)。
## 若只有攻击条而没有 48px 的其他动作，则用攻击第 1 帧 + 代码起伏兜底。
const P48 := {"idle": [4.0, true], "run": [10.0, true], "hurt": [10.0, false], "death": [6.0, false]}


func _p48_tex(kind: String) -> Texture2D:
	if kind == "attack":
		return tex.get("player_attack_48")
	var tx: Texture2D = tex.get("player_" + kind)
	if tx != null and tx.get_height() == 48:
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
		sprite.offset = Vector2(0, -tx.get_height() / 2.0 + 2.0)
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

func _draw_mire(m: Dictionary) -> void:
	var a: float = clamp(m.life / 3.0, 0.0, 1.0)
	var mt: Texture2D = tex.get("terrain_mire")
	if mt != null:
		# 溟痕（Codex 美术，2 帧脉动）：按判定半径缩放，外圈画判定提示
		var fw := mt.get_width() / 2
		var sz := Vector2(m.r * 2.3, m.r * 2.3)
		draw_texture_rect_region(mt, Rect2(m.pos - sz / 2.0, sz), Rect2(fw * (int(t * 2.0 + m.seed) % 2), 0, fw, mt.get_height()), Color(1, 1, 1, a))
		draw_arc(m.pos, m.r, 0.0, TAU, 36, Color(0.7, 0.4, 1.2, 0.35 * a), 1.5)
		return
	for k in 7:
		var off: Vector2 = Vector2.from_angle(k * 0.9 + m.seed) * m.r * 0.45
		draw_circle(m.pos + off, m.r * (0.55 + 0.1 * sin(t + k)), Color(0.08, 0.03, 0.12, 0.55 * a))
	draw_circle(m.pos, m.r * 0.7, Color(0.12, 0.04, 0.16, 0.6 * a))
	for k in 10:
		var p: Vector2 = m.pos + Vector2.from_angle(k * 2.39 + m.seed) * m.r * (0.3 + 0.07 * k)
		var gl := 0.5 + 0.5 * sin(t * 2.0 + k)
		draw_rect(Rect2(p.round(), Vector2(2, 2)), Color(0.5, 0.9, 0.9, 0.6 * gl * a))


func _draw_tentacle(f: Dictionary) -> void:
	var a: float = 1.0 - f.life / f.max
	var fr := clampi(int(a * 5.0 / 0.75), 0, 4)
	var sc := PX * 1.7
	# 底部紫色辉光，让触手在暗处也能看清
	draw_set_transform(f.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 22.0, Color(0.9, 0.4, 1.6, 0.35 * (1.0 - a)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_spr("tentacle", 5, fr, f.pos + Vector2(0, 10), sc, f.flip, Color(1.5, 1.2, 1.9) if a < 0.3 else Color.WHITE, Vector2(0.5, 1.0))


func _draw_bg() -> void:
	var vs := get_viewport_rect().size
	var x0 := floori((ppos.x - vs.x / 2.0) / TILE) - 1
	var y0 := floori((ppos.y - vs.y / 2.0) / TILE) - 1
	var nx := int(vs.x / TILE) + 3
	var ny := int(vs.y / TILE) + 3
	var props: Array = []
	for cx in range(x0, x0 + nx):
		for cy in range(y0, y0 + ny):
			var h: int = abs(hash(Vector2i(cx, cy)))
			var v := h % 4
			var p := Vector2(cx * TILE, cy * TILE)
			draw_texture_rect_region(tex.tiles, Rect2(p, Vector2(TILE, TILE)), Rect2(v * 16, 0, 16, 16))
			var hh := h / 7
			if hh % 47 == 0:
				props.append(["seaweed", p + Vector2(16, 20), h])
			elif hh % 151 == 0:
				props.append(["coral", p + Vector2(16, 18), h])
			elif hh % 97 == 0:
				props.append(["rock", p + Vector2(16, 20), h])
			elif hh % 113 == 0:
				props.append(["shell_prop", p + Vector2(12, 22), h])
	_draw_terrain(vs)
	sort_props.clear()
	_collect_big_props(vs)
	for pr in props:
		if pr[0] == "seaweed" or pr[0] == "coral":
			sort_props.append(pr)
		else:
			_spr(pr[0], 1, 0, pr[1], PX, pr[2] % 2 == 0, Color.WHITE, Vector2(0.5, 1.0))


## 地形区域块：3×3 聚簇的同类区域，随机镜像，避免均匀混杂
const PATCH := 256.0
func _draw_terrain(vs: Vector2) -> void:
	var pt: Texture2D = tex.get("terrain_patches")
	if pt == null:
		return
	var x0 := floori((ppos.x - vs.x / 2.0) / PATCH) - 1
	var y0 := floori((ppos.y - vs.y / 2.0) / PATCH) - 1
	for cx in range(x0, x0 + int(vs.x / PATCH) + 3):
		for cy in range(y0, y0 + int(vs.y / PATCH) + 3):
			var cl: int = abs(hash(Vector2i(floori(cx / 3.0), floori(cy / 3.0)) + Vector2i(77, 13)))
			if cl % 3 == 2:
				continue
			var h: int = abs(hash(Vector2i(cx, cy) + Vector2i(5, 91)))
			if h % 100 > 78:
				continue
			var kind: int = (cl / 3) % 4
			var p := Vector2(cx * PATCH, cy * PATCH)
			var fx_: float = -1.0 if h % 2 == 0 else 1.0
			var fy_: float = -1.0 if (h / 2) % 2 == 0 else 1.0
			draw_set_transform(p + Vector2(PATCH, PATCH) / 2.0, 0.0, Vector2(fx_, fy_))
			draw_texture_rect_region(pt, Rect2(Vector2(-PATCH, -PATCH) / 2.0, Vector2(PATCH, PATCH)), Rect2(kind * 128, 0, 128, 128))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 大型景物：残柱 / 断墙 / 沉船 / 岩脊 / 海底山；按格子确定性生成并缓存，开局附近留空；会阻挡移动
const BIGCELL := 560.0
const BIG_PROPS := ["prop_pillar", "prop_wall", "prop_wreck", "terrain_ridge", "terrain_ridge", "terrain_peak", "terrain_peak"]
var big_cache := {}


func _big_prop(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	if big_cache.has(key):
		return big_cache[key]
	var out: Array = []
	var h: int = abs(hash(key + Vector2i(313, 7)))
	if h % 100 <= 55:
		var name: String = BIG_PROPS[(h / 100) % BIG_PROPS.size()]
		var tx: Texture2D = tex.get(name)
		if tx != null:
			var p := Vector2(cx * BIGCELL + float((h / 7) % 380) + 90.0, cy * BIGCELL + float((h / 3001) % 380) + 90.0)
			if p.length() > 420.0:
				var rx: float = tx.get_width() * PX * (0.36 if name.begins_with("terrain") else 0.3)
				out = [name, p, h, rx, rx * 0.38]
	big_cache[key] = out
	return out


func _collect_big_props(vs: Vector2) -> void:
	if tex.get("prop_pillar") == null:
		return
	var x0 := floori((ppos.x - vs.x / 2.0 - 260.0) / BIGCELL)
	var y0 := floori((ppos.y - vs.y / 2.0 - 60.0) / BIGCELL)
	for cx in range(x0, x0 + int(vs.x / BIGCELL) + 3):
		for cy in range(y0, y0 + int(vs.y / BIGCELL) + 3):
			var bp := _big_prop(cx, cy)
			if not bp.is_empty():
				sort_props.append([bp[0], bp[1], bp[2]])


## 把圆形实体推出景物底座（椭圆）
func _prop_push(pos: Vector2, r: float) -> Vector2:
	var cx := floori(pos.x / BIGCELL)
	var cy := floori(pos.y / BIGCELL)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var bp := _big_prop(cx + dx, cy + dy)
			if bp.is_empty():
				continue
			var c: Vector2 = bp[1] + Vector2(0, -bp[4] * 0.6)
			var rx: float = bp[3] + r
			var ry: float = bp[4] + r * 0.6
			var d := pos - c
			var q := Vector2(d.x / rx, d.y / ry)
			var ql := q.length()
			if ql < 1.0:
				if ql < 0.001:
					q = Vector2.RIGHT
					ql = 1.0
				var qn := q / ql
				pos = c + Vector2(qn.x * rx, qn.y * ry)
	return pos


func _draw_enemy(e: Dictionary) -> void:
	var name: String = e.tex
	# 形态切换：偏执泡影二阶段 / 接潮三件套昏迷时的假死造型
	if e.type == "paranoia" and e.phase == 2 and tex.get("e_paranoia2") != null:
		name = "e_paranoia2"
	elif e.coma and e.tex_feign:
		name = name + "_feign"
	var frames := 2
	var frame := int(t * (2.0 if e.boss else 5.0) + e.id * 0.37) % 2
	# 美术 V5：Boss 移动时播放 4 帧移动循环；停下、晕眩、假死时用本体
	if e.boss:
		if e.pos.distance_squared_to(e.get("dpos", e.pos)) > 0.04:
			e.mv_until = t + 0.2
		e.dpos = e.pos
		if t < e.mv_until and e.stun <= 0.0 and not e.coma and e.tex_move:
			name += "_move"
			frames = 4
			var fps := 6.0
			if e.type == "immortal":
				fps = 8.0
			elif e.type in ["paranoia", "izumik", "ishar"]:
				fps = 5.0
			frame = int(t * fps + e.id * 0.37) % 4
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
		_spr(name, 2, 0, e.pos + Vector2(wob, 0), PX, false, col)
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
		if e.elite or e.boss:
			UI.text(self, font, wp + Vector2(-20, 16), ("弱" + wk.substr(0, 1)) if wk != "双" else "双弱", 10, wc, HORIZONTAL_ALIGNMENT_CENTER, 40)
	if e.elite:
		var w: float = e.r * 2.0
		draw_rect(Rect2(e.pos + Vector2(-w / 2, -e.r - 14), Vector2(w, 4)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(e.pos + Vector2(-w / 2, -e.r - 14), Vector2(w * e.hp / e.maxhp, 4)), Color(1.0, 0.7, 0.3))
	draw_off = Vector2.ZERO


## 在任意位置绘制水月（残影、倒影用）
func _draw_player_at(pos: Vector2, flip: bool, col: Color, frame: int, tx: Texture2D = null, hf: int = 0) -> void:
	if tx == null:
		tx = sprite.texture
		hf = sprite.hframes
	if tx == null:
		return
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (frame % hf), 0, fw, fh)
	draw_set_transform(pos, 0.0, Vector2(-PX if flip else PX, PX))
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + sprite.offset, Vector2(fw, fh)), src, col)
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


## 水刃：月牙形水光（巨斩为金紫色）
func _draw_wave(b: Dictionary) -> void:
	var dir: Vector2 = b.vel.normalized()
	var R: float = 24.0 * b.size
	var c: Vector2 = b.pos - dir * R * 0.55
	var ang := dir.angle()
	var fade: float = clampf(b.life / 0.15, 0.0, 1.0)
	var core := Color(2.2, 2.6, 2.8, fade) if not b.giant else Color(2.8, 2.2, 2.8, fade)
	var glow := Color(0.5, 1.4, 2.2, 0.35 * fade) if not b.giant else Color(1.8, 0.8, 2.4, 0.4 * fade)
	draw_arc(c, R, ang - 1.15, ang + 1.15, 24, glow, 10.0 * b.size)
	draw_arc(c, R, ang - 1.0, ang + 1.0, 20, core, 3.0 * b.size)
	draw_arc(c, R * 0.82, ang - 0.8, ang + 0.8, 16, Color(core.r, core.g, core.b, 0.5 * fade), 1.5 * b.size)


## 触手桩：扎根的触手，鞭打时伸向目标
func _draw_stake(st: Dictionary) -> void:
	var a: float = clampf(st.life / 0.3, 0.0, 1.0)
	draw_set_transform(st.pos + Vector2(0, 10), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 16.0, Color(0.15, 0.03, 0.22, 0.6 * a))
	draw_arc(Vector2.ZERO, st.r, 0.0, TAU, 32, Color(1.3, 0.6, 2.0, 0.18 * a), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fr := 3 + int(t * 4.0 + st.pos.x) % 2
	_spr("tentacle", 5, fr, st.pos + Vector2(0, 10), PX * 1.3, st.flip, Color(1, 1, 1, a), Vector2(0.5, 1.0))
	if st.whip > 0.0:
		var k: float = st.whip / 0.18
		var tip: Vector2 = st.pos + Vector2(0, -20)
		draw_line(tip, st.wt, Color(0.6, 0.25, 0.9, k), 5.0)
		draw_line(tip, st.wt, Color(1.8, 1.0, 2.6, k), 1.5)


## 触须阵：地面符阵 + 触须
func _draw_field(f: Dictionary) -> void:
	var a := clampf(f.life / 0.3, 0.0, 1.0) * clampf((f.max - f.life) / 0.2, 0.0, 1.0)
	draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, f.r, Color(0.35, 0.1, 0.5, 0.3 * a))
	draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 40, Color(1.4, 0.8, 2.2, 0.8 * a), 2.5)
	draw_arc(Vector2.ZERO, f.r * 0.65, t * 2.0, t * 2.0 + PI * 1.4, 24, Color(1.4, 0.8, 2.2, 0.5 * a), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for q in 6:
		var an: float = q * TAU / 6.0 + f.r
		var p: Vector2 = f.pos + Vector2(cos(an) * f.r * 0.6, sin(an) * f.r * 0.3)
		var h := (14.0 + 10.0 * sin(t * 9.0 + q)) * a
		draw_line(p, p + Vector2(sin(t * 6.0 + q) * 5.0, -h), Color(0.5, 0.25, 0.7, a), 4.0)
		draw_circle(p + Vector2(sin(t * 6.0 + q) * 5.0, -h), 2.5, Color(1.4, 0.9, 2.0, a))


## 技能的地面表现（在角色之下）
func _draw_skill_floor() -> void:
	var P: Dictionary = D.SKILL_P
	var base := ppos + Vector2(0, 6)
	# 灯火照亮范围（光中敌人受伤 +25%）
	var lr := _lamp_r()
	draw_set_transform(base, 0.0, Vector2(1.0, 0.5))
	for q in 32:
		if q % 2 == 0:
			draw_arc(Vector2.ZERO, lr, TAU * q / 32.0 + t * 0.1, TAU * (q + 1) / 32.0 + t * 0.1, 3, Color(1.6, 1.3, 0.8, 0.22), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s3_active > 0.0:
		# 镜花水月：脚下的镜面水域 + 涟漪
		var r: float = P.s3_zone_r if skill_lv.s3 >= 3 else 110.0
		var fade := clampf(s3_active / 1.0, 0.0, 1.0) * clampf((D.SKILL_P.s3_dur - s3_active) / 0.4, 0.0, 1.0)
		draw_set_transform(base, 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, r, Color(0.5, 0.35, 1.0, 0.13 * fade))
		for q in 3:
			var rp := fmod(t * 0.6 + q / 3.0, 1.0)
			draw_arc(Vector2.ZERO, r * rp, 0.0, TAU, 48, Color(1.4, 1.0, 2.2, (1.0 - rp) * 0.55 * fade), 2.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.2, 0.9, 2.0, 0.7 * fade), 2.5)
		# 刻度符文
		for q in 12:
			var dv := Vector2.from_angle(q * TAU / 12.0 - t * 0.4)
			draw_line(dv * (r - 10.0), dv * r, Color(1.4, 1.1, 2.2, 0.8 * fade), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s2_active > 0.0:
		var fade2 := clampf(s2_active / 1.0, 0.0, 1.0)
		draw_set_transform(base, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, 58.0, 0.0, TAU, 40, Color(0.6, 1.1, 1.8, 0.6 * fade2), 2.0)
		draw_arc(Vector2.ZERO, 66.0, t * 3.0, t * 3.0 + PI, 24, Color(0.6, 1.1, 1.8, 0.4 * fade2), 3.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if skill_lv.s1 >= 1 and s1_charges > 0:
		# 唤醒蓄满：脚下金色光环
		draw_set_transform(base, 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, 34.0 + 3.0 * sin(t * 8.0), 0.0, TAU, 32, Color(2.0, 1.5, 0.6, 0.7), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## 技能的覆盖层表现（在角色之上）
func _draw_skill_over() -> void:
	_draw_shield()
	if s2_active > 0.0:
		# 囚徒困境：环绕的锁链
		var fade2 := clampf(s2_active / 1.0, 0.0, 1.0)
		for q in 10:
			var an := t * 2.6 + q * TAU / 10.0
			var p := ppos + Vector2(cos(an) * 46.0, sin(an) * 20.0 - 26.0)
			var front := sin(an) > 0.0
			UI.diamond(self, p, 4.5 if front else 3.5, Color(0.02, 0.05, 0.08, fade2), Color(0.7, 1.3, 2.0, fade2 * (1.0 if front else 0.5)))
		# 被束缚的敌人：锁环
		for j in _query(ppos, 320.0):
			var e: Dictionary = enemies[j]
			if e.dead or e.stun < 0.15:
				continue
			for q in 3:
				var an2: float = t * 4.0 + q * TAU / 3.0 + e.id
				UI.diamond(self, e.pos + Vector2(cos(an2) * (e.r + 6.0), sin(an2) * (e.r + 6.0) * 0.4 - 4.0), 3.0, Color(0.02, 0.05, 0.08, 0.9), Color(0.6, 1.2, 2.0, 0.9))
	if s3_active > 0.0:
		# 镜花水月：环绕的镜片
		for q in 6:
			var an := -t * 1.4 + q * TAU / 6.0
			var p := ppos + Vector2(cos(an) * 64.0, sin(an) * 26.0 - 30.0 + sin(t * 3.0 + q) * 4.0)
			var w := 5.0 + 3.0 * absf(cos(t * 2.0 + q))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -12), p + Vector2(w, 0), p + Vector2(0, 12), p + Vector2(-w, 0)]),
				Color(1.3, 1.0, 2.2, 0.75))
			draw_line(p + Vector2(0, -12), p + Vector2(0, 12), Color(2.5, 2.2, 3.0, 0.9), 1.0)


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
		UI.text(hud, font, Vector2(0, vs.y * 0.22 + 44), "水月  ·  深海探索", 34, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
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
	var sx := -PX if sprite.flip_h else PX
	# 以脚底为轴做挤压 / 前倾 / 后坐（帧动画之上的程序手感）
	draw_set_transform(sprite.position + p_off, sprite.rotation + p_lean, Vector2(sx * p_sq.x, PX * p_sq.y))
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
	# 技能发动横幅：斜切色带滑入，水月剪影 + 技能名
	if not skill_cut.is_empty():
		var sk: Dictionary = D.SKILLS[skill_cut.id]
		var ct2: float = skill_cut.t
		var c: Color = sk.col
		var enter := clampf(ct2 / 0.15, 0.0, 1.0)
		var leave := clampf((ct2 - 0.8) / 0.3, 0.0, 1.0)
		var ox := (1.0 - enter) * vs.x * 0.6 - leave * vs.x * 0.8
		var by := vs.y * 0.62
		var band := PackedVector2Array([Vector2(ox + 80, by - 58), Vector2(ox + vs.x, by - 58), Vector2(ox + vs.x - 60, by + 42), Vector2(ox + 20, by + 42)])
		hud.draw_colored_polygon(band, Color(0.02, 0.05, 0.08, 0.82))
		hud.draw_line(band[0], band[1], c, 3.0)
		hud.draw_line(band[3], band[2], Color(c.r, c.g, c.b, 0.5), 2.0)
		for q in 6:
			var lx := fmod(ct2 * 900.0 + q * 230.0, vs.x) + ox
			hud.draw_line(Vector2(lx, by - 40 + q * 12), Vector2(lx + 120, by - 40 + q * 12), Color(c.r, c.g, c.b, 0.25), 2.0)
		var at: Texture2D = tex.get("player_attack_48")
		if at != null:
			var fh := at.get_height()
			var fr := clampi(int(ct2 * 10.0), 0, 3)
			var S6 := 3.0
			hud.draw_texture_rect_region(at, Rect2(Vector2(ox + 180, by + 42 - fh * S6 + 6), Vector2(fh, fh) * S6), Rect2(fh * fr, 0, fh, fh), Color(1, 1, 1, 1.0 - leave))
		UI.en(hud, font, Vector2(ox + 360, by - 22), "SKILL  ·  " + sk.en, 12, c, 4.0)
		UI.text(hud, font, Vector2(ox + 356, by + 22), sk.name, 40, Color(1, 1, 1, 1.0 - leave), HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
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
			for j in 8:
				var ang := TAU * j / 8.0
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
	if hurt_vignette > 0.0:
		_edge_glow(vs, Color(0.9, 0.1, 0.15, hurt_vignette * 0.9), 90.0 + 50.0 * hurt_vignette)
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
	var bc := UI.GLOW.lerp(UI.GOLD, lf)
	UI.frame(hud, Rect2(o, Vector2(344, 100)), bc, {"t": t, "vines": true, "seed": 7, "glow": 0.5 + lf})
	# 等级环：环上进度 = 经验
	var lc0 := o + Vector2(44, 50)
	UI.ring(hud, lc0, 27.0 + 4.0 * lf, xp / xp_need, bc, lf > 0.2)
	var lvs := 24 if level < 10 else 20
	UI.text(hud, font, lc0 + Vector2(-30, 8 + (1 if level >= 10 else 0)), str(level), int(lvs * (1.0 + 0.3 * lf)), Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, 60, 4)
	# 名字、精英阶段
	UI.text(hud, font, o + Vector2(84, 32), "水月", 19, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	UI.en(hud, font, o + Vector2(130, 31), "MIZUKI", 10, UI.CYAN_DIM, 3.0)
	var stage_txt: String = ["精零", "精英一", "精英二"][elite_stage]
	UI.chip(hud, font, o + Vector2(280, 18), stage_txt, UI.GOLD if elite_stage > 0 else UI.SUB, 11)
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
			hud.draw_texture_rect_region(mt, Rect2(edge - Vector2(fw, mt.get_height()), Vector2(fw, mt.get_height()) * 2.0), Rect2(fw * mf, 0, fw, mt.get_height()))
			# 指向商人的箭头
			var tip: Vector2 = edge + d * (40.0 + 5.0 * pulse)
			var base: Vector2 = edge + d * 28.0
			var sd := d.orthogonal() * 10.0
			hud.draw_colored_polygon(PackedVector2Array([tip, base + sd, base - sd]), UI.GOLD)
			var dist := int(merchant.pos.distance_to(ppos) / 32.0)
			var lab_y := -34.0 if edge.y > vs.y / 2 else 44.0
			UI.text(hud, font, edge + Vector2(-60, lab_y), "商人  %dm · %ds" % [dist, int(merchant.life)], 13, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
		else:
			# 在画面内：头顶跳动的箭头
			var hp2 := sp + Vector2(0, -64 - bounce)
			hud.draw_colored_polygon(PackedVector2Array([hp2 + Vector2(0, 12), hp2 + Vector2(-10, -2), hp2 + Vector2(10, -2)]), UI.GOLD)
			UI.text(hud, font, hp2 + Vector2(-60, -8), "商人 %ds" % int(merchant.life), 13, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, 120, 3)
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

	# 右上：藏品
	_draw_relic_tray(Vector2(vs.x - 16, 16))

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
	_draw_skills(Vector2(vs.x - 16, vs.y - 16))
	_draw_allies_hud(Vector2(vs.x - 16, vs.y - 150))
	# 左下：精英化 / 模组
	if evo1 != "":
		UI.text(hud, font, Vector2(18, vs.y - 190), D.EVO[evo1].name + ((" · " + D.EVO[evo2].name) if evo2 != "" else ""), 14, D.EVO[evo1].col, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

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
			UI.text(hud, font, Vector2(0, vs.y - 60), "WASD 移动 · 攻击全自动 · Esc 暂停", 16, Color(0.7, 0.85, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
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
			UI.text(hud, font, kc.position + Vector2(0, 18), "Tab", 14, Color(1, 1, 1, ha), HORIZONTAL_ALIGNMENT_CENTER, kc.size.x)
			UI.text(hud, font, Vector2(cx - 72, y + 4), "查看水月的属性与技能", 15, Color(0.85, 0.95, 0.95, ha))

	_draw_relic_tooltip(vs)
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
			_draw_result(vs, "%s · 探索完成" % D.ENDINGS[ending].name, D.ENDINGS[ending].en, UI.GOLD, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])


## ---- 开局指南：6 页图文介绍（首次进入自动显示，暂停菜单按 G 可再看）
const INTRO_PAGES := [
	{"title": "欢迎来到深海", "en": "WELCOME", "icon": "mizuki", "lines": [
		"目标：在深海中存活 10 分钟，击败最终 Boss「偏执泡影」。",
		"水月的攻击全自动 —— 你只需要用 WASD 移动、走位、躲避弹幕。",
		"3:30 与 7:00 会有第三层 Boss 登场，击败后获得大量经验与藏品。"]},
	{"title": "生命与灯火", "en": "HP & LAMPLIGHT", "icon": "bars", "lines": [
		"生命（绿条）归零即探索失败；血量低于 30% 时会有心跳与红色警告。",
		"灯火（金条）会持续消耗，拾取灯油补充。灯光范围内的敌人受到的伤害 +25%。",
		"灯火 ≥70 充盈：技力回复与拾取范围提升；<30 昏暗：敌人更快更凶；熄灭后持续掉血。"]},
	{"title": "溟痕与黑潮", "en": "MIRE & BLACK TIDE", "icon": "mire", "lines": [
		"紫黑色的溟痕会越来越多：站在里面会减速、持续掉血，并积累神经损伤（满了会僵直）。",
		"2:30 起安全区开始收缩（小地图上的紫色圆圈）。圈外是「黑潮」，会快速掉血、流失灯火。",
		"看到「黑潮将至」提示时，提前往白色虚线圈里走。"]},
	{"title": "成长路线", "en": "GROWTH", "icon": "cards", "lines": [
		"击败敌人掉落经验，升级时三选一：一张路线卡（进化路线成长 / 技能进阶）+ 两张通用成长，偶尔出现支援无人机。",
		"Lv3 唤醒 → Lv10 精英化一（选择进化：潮刃 / 群触）→ Lv20 精英化二（质变 + 镜花水月）。",
		"Lv5 / 15 / 25 招募或升级援护干员（狙击、术师、医疗、辅助）。"]},
	{"title": "资源、宝箱与商人", "en": "LOOT & MERCHANT", "icon": "loot", "lines": [
		"精英与 Boss 掉落源石锭、补给箱（藏品）与磁铁 / 回复药剂。小心伪装成宝箱的箱形恐鱼！",
		"商人每局出现 3 次（屏幕边缘金色箭头指引），靠近即可用源石锭购买藏品与补给；交易后离开。",
		"大群来袭前 3 秒有紫色预警，准备好退路。"]},
	{"title": "操作", "en": "CONTROLS", "icon": "keys", "lines": [
		"WASD / 方向键：移动　　Tab 或 C：查看属性与技能　　Esc：暂停",
		"升级 / 宝箱 / 商人：按 1 2 3 或点击选择　　M：静音　　R：重来",
		"暂停菜单按 G 可以随时重看本指南。祝你好运，水月。"]},
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
	var r := Rect2(vs.x / 2 - 440, vs.y / 2 - 250, 880, 500)
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
	var y := r.position.y + 170
	for ln in pg.lines:
		UI.diamond(hud, Vector2(r.position.x + 340, y - 6), 4.0, UI.CYAN)
		hud.draw_multiline_string(font, Vector2(r.position.x + 356, y), ln, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 400, 16, 3, Color(0.85, 0.93, 0.95, ea))
		y += 78
	# 页码点
	for i in INTRO_PAGES.size():
		UI.diamond(hud, Vector2(vs.x / 2 - (INTRO_PAGES.size() - 1) * 11 + i * 22, r.end.y - 30), 5.0, UI.CYAN if i == intro_page else Color(0.15, 0.25, 0.28))
	UI.text(hud, font, Vector2(r.position.x, r.end.y + 30), "任意键 / 点击：下一页　　← / 右键：上一页　　Esc：跳过", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_intro_icon(kind: String, c: Vector2) -> void:
	match kind:
		"mizuki":
			var tx: Texture2D = tex.get("player_attack_48")
			if tx != null:
				var fr := int(intro_t * 8.0) % 4
				hud.draw_texture_rect_region(tx, Rect2(c - Vector2(96, 150), Vector2(192, 192)), Rect2(48 * fr, 0, 48, 48))
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
			for k in 3:
				var rc := Rect2(c + Vector2(-130 + k * 88, -90), Vector2(76, 110))
				var cc: Color = [UI.CYAN, Color(0.55, 0.95, 1.0), UI.GOLD][k]
				UI.panel(hud, rc, Color(0.03, 0.08, 0.1), cc, 6.0)
				UI.text(hud, font, rc.position + Vector2(0, 66), ["伞", "机", "唤"][k], 30, cc, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
			UI.text(hud, font, c + Vector2(-130, 60), "成长 / 武器 / 技能进阶", 14, UI.SUB)
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
	var pt: Texture2D = tex.get("player_idle")
	if pt != null:
		var fh := pt.get_height()
		var fr := int(t * 4.0) % maxi(1, pt.get_width() / fh)
		hud.draw_texture_rect_region(pt, Rect2(r.position + Vector2(26, 14), Vector2(fh, fh) * 1.5), Rect2(fr * fh, 0, fh, fh))
	UI.text(hud, font, r.position + Vector2(108, 50), "水月", 28, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	UI.en(hud, font, r.position + Vector2(176, 48), "MIZUKI  ·  STATUS", 12, UI.CYAN, 3.0)
	var cx0 := r.position.x + 350
	cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), "Lv.%d" % level, UI.GLOW, 12) + 8
	cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), ["精零", "精英化一", "精英化二"][elite_stage], UI.GOLD if elite_stage > 0 else UI.SUB, 12) + 8
	if evo1 != "":
		cx0 += UI.chip(hud, font, Vector2(cx0, r.position.y + 32), D.EVO[evo1].name + ((" · " + D.EVO[evo2].name) if evo2 != "" else ""), D.EVO[evo1].col, 12) + 8
	UI.chip(hud, font, Vector2(cx0, r.position.y + 32), "难度 %d「%s」" % [diff, D.DIFFICULTY[diff].name], UI.CYAN_DIM, 12)
	UI.rule(hud, r.position + Vector2(24, 82), Vector2(r.end.x - 24, r.position.y + 82), UI.EDGE_DIM)
	# 三个子面板
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
		["移动速度", "%d" % int(speed)], ["拾取范围", "%d" % int(pickup)], ["灯火消耗", "×%.2f" % lamp_decay],
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
	var interval := 0.9 * u_spd_mult
	var half: float = minf(180.0, 75.0 + rib_bonus + 15.0 * growth.get("u_area", 0))
	var rows1 := [
		["伞击伤害", "%d" % int(18.0 * u_dmg_mult * dmg_mult)], ["全局伤害", "×%.2f" % dmg_mult], ["挥伞间隔", "%.2f 秒" % max(0.18, interval)],
		["挥砍半径", "%d" % int(95.0 * u_area_mult)], ["挥砍角度", "%d°" % int(half * 2.0)], ["触手倍率", "×%.2f" % t_mult],
		["追击目标", "%d" % (1 + extra_targets)], ["技力回复", "×%.2f" % sp_mult],
		["近战 / 远程", "×%.2f / ×%.2f" % [melee_mult, ranged_mult]], ["物理 / 法术", "×%.2f / ×%.2f" % [phys_mult, arts_mult]],
	]
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
	for sid in ["s1", "s2", "s3"]:
		var sk: Dictionary = D.SKILLS[sid]
		var lv: int = skill_lv[sid]
		var col: Color = sk.col if lv >= 1 else Color(0.35, 0.42, 0.46)
		var sc := Vector2(b1.position.x + 34, y + 18)
		UI.ring(hud, sc, 17.0, 1.0 if lv >= 1 else 0.0, col, false, lv < 1)
		var sicon: Texture2D = tex.get("skill_" + sid)
		if sicon != null:
			hud.draw_texture_rect(sicon, Rect2(sc - Vector2(16, 16), Vector2(32, 32)), false, Color.WHITE if lv >= 1 else Color(0.3, 0.3, 0.35))
		UI.text(hud, font, Vector2(b1.position.x + 62, y + 14), sk.name if lv >= 1 else "%s（Lv.%d 解锁）" % [sk.name, D.SKILL_UNLOCK[sid]], 14, UI.TEXT if lv >= 1 else UI.SUB)
		var ax: float = b1.position.x + 62
		for k in 2:
			var ad: Dictionary = D.SKILL_ADV[sid][k]
			var got := lv >= k + 2
			UI.diamond(hud, Vector2(ax + 5, y + 28), 3.5, col if got else Color(0, 0, 0, 0), col if got else Color(0.35, 0.42, 0.46))
			UI.text(hud, font, Vector2(ax + 13, y + 32), ad.name, 11, col if got else Color(0.35, 0.42, 0.46))
			ax += 120
		y += 44
	# ---- 队伍与成长
	var b2: Rect2 = boxes[2]
	UI.text(hud, font, b2.position + Vector2(16, 26), "队伍与成长", 16, UI.CYAN)
	UI.en(hud, font, b2.position + Vector2(110, 25), "BUILD", 10, UI.CYAN_DIM, 3.0)
	y = b2.position.y + 44
	UI.text(hud, font, Vector2(b2.position.x + 16, y + 12), "援护干员", 13, UI.SUB)
	var ax2: float = b2.position.x + 90
	if allies.is_empty():
		UI.text(hud, font, Vector2(ax2, y + 12), "暂无", 13, UI.SUB)
	for al in allies:
		var at: Texture2D = tex["ally_" + al.kind]
		var fw := at.get_width() / 2
		var ks := 26.0 / at.get_height()
		hud.draw_texture_rect_region(at, Rect2(Vector2(ax2, y - 4), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
		UI.text(hud, font, Vector2(ax2 + fw * ks + 2, y + 16), "Lv.%d" % al.lv, 11, Color(0.55, 0.9, 0.55))
		ax2 += fw * ks + 40
	y += 34
	UI.text(hud, font, Vector2(b2.position.x + 16, y + 12), "武器", 13, UI.SUB)
	ax2 = b2.position.x + 90
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
			UI.text(hud, font, gc + Vector2(0, 26), D.GROWTH[gid].name.substr(0, 1), 16, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 38)
		UI.text(hud, font, gc + Vector2(20, 37), "×%d" % growth[gid], 10, UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 18, 2)
		gi += 1
	UI.text(hud, font, Vector2(r.position.x, r.end.y - 18), "藏品 %d 件  ·  击杀 %d  ·  源石锭 %d  ·  按 Tab / C / Esc 返回" % [relics.size(), kills, ingots], 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


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
			hud.draw_rect(Rect2(c + p - Vector2(2, 2), Vector2(4, 4)), UI.GOLD)
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
	for al in allies:
		hud.draw_circle(c + (al.pos - ppos) * k, 2.0, Color(0.5, 0.9, 1.0))
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


## 藏品悬停提示：名称、分类·稀有度、等级、效果
func _draw_relic_tooltip(vs: Vector2) -> void:
	if state != S.PLAY and state != S.PAUSE and state != S.STATS:
		return
	var mouse := hud.get_local_mouse_position()
	for cellinfo in tray_cells:
		var cr: Rect2 = cellinfo[0]
		if not cr.has_point(mouse):
			continue
		var id: String = cellinfo[1]
		var rd: Dictionary = RL[id]
		var col: Color = UI.CAT_COL.get(rd.cat, UI.GOLD)
		var lvn: int = rfx.lv.get(id, 1)
		var mx: int = rfx.max_lv(id)
		var lines: Array = []
		var desc: String = rd.desc
		# 按 26 字折行
		while desc.length() > 26:
			lines.append(desc.substr(0, 26))
			desc = desc.substr(26)
		lines.append(desc)
		var w := 320.0
		var h := 66.0 + lines.size() * 20.0
		var pos := Vector2(minf(cr.position.x, vs.x - w - 12), cr.end.y + 8)
		var r := Rect2(pos, Vector2(w, h))
		UI.frame(hud, r, col, {"cut": 6.0, "bracket": 6.0})
		hud.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4)), Color(0.01, 0.04, 0.08, 0.92))
		var ic: Texture2D = tex.get("relic_" + id)
		if ic != null:
			hud.draw_texture_rect(ic, Rect2(pos + Vector2(12, 12), Vector2(40, 40)), false)
		UI.text(hud, font, pos + Vector2(62, 28), rd.name + ((" Lv.%d/%d" % [lvn, mx]) if mx > 1 else ""), 16, Color.WHITE)
		UI.text(hud, font, pos + Vector2(62, 48), "%s · %s" % [rd.cat, rd.rarity], 12, col)
		for k in lines.size():
			UI.text(hud, font, pos + Vector2(14, 74 + k * 20), lines[k], 13, Color(0.85, 0.92, 0.95))
		return


## 人物状态栏：左上面板下方，列出当前生效的增益 / 减益（带剩余时间条）
func _draw_status_bar(vs: Vector2) -> void:
	if state == S.OPENING or state == S.INTRO or state == S.SHOW:
		return
	var items: Array = []   # [文字, 颜色, 进度 0..1 或 -1]
	if s1_charges > 0:
		items.append(["唤醒 ×%d" % s1_charges, UI.GOLD, -1.0])
	if s2_active > 0.0:
		items.append(["囚徒困境", Color(0.45, 0.8, 1.0), s2_active / D.SKILL_P.s2_dur])
	if s3_active > 0.0:
		items.append(["镜花水月", UI.PURPLE, s3_active / D.SKILL_P.s3_dur])
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


func _draw_allies_hud(br: Vector2) -> void:
	if allies.is_empty():
		return
	UI.en(hud, font, br + Vector2(-236, -60), "SUPPORT", 10, UI.SUB, 3.0)
	for i in allies.size():
		var al: Dictionary = allies[i]
		var c := br + Vector2(-(3 - i) * 76 + 40, -30)
		var acol := Color(0.55, 0.9, 0.55)
		UI.ring(hud, c, 21.0, float(al.lv) / 3.0, acol)
		var at: Texture2D = tex["ally_" + al.kind]
		var fw := at.get_width() / 2
		var ks: float = 30.0 / at.get_height()
		hud.draw_texture_rect_region(at, Rect2(c + Vector2(-fw * ks / 2.0, 14 - at.get_height() * ks), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
		UI.text(hud, font, c + Vector2(-30, 36), D.ALLIES[al.kind].name.substr(0, 2), 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 60, 2)
		UI.text(hud, font, c + Vector2(12, -14), str(al.lv), 11, acol, HORIZONTAL_ALIGNMENT_CENTER, 20, 2)


func _draw_skills(br: Vector2) -> void:
	var rad := 37.0
	var gap := 88.0
	var items := [
		["唤", "唤醒", skill_lv.s1 >= 1, 0.0, 1.0, float(s1_count) / float(s1_need), UI.GOLD],
		["囚", "囚徒困境", skill_lv.s2 >= 1, s2_active, D.SKILL_P.s2_dur, s2_sp / D.SKILL_P.s2_charge, Color(0.45, 0.8, 1.0)],
		["镜", "镜花水月", skill_lv.s3 >= 1, s3_active, D.SKILL_P.s3_dur, s3_sp / D.SKILL_P.s3_charge, UI.PURPLE],
	]
	UI.en(hud, font, br + Vector2(-3 * gap + 8, -rad * 2 - 34), "SKILL", 10, UI.SUB, 3.0)
	for i in 3:
		var it: Array = items[i]
		var c := br + Vector2(-(3 - i) * gap + gap / 2.0 + 8, -rad - 24)
		var col: Color = it[6]
		var unlocked: bool = it[2]
		var active: float = it[3]
		var frac: float = clamp(it[5], 0.0, 1.0)
		if active > 0.0:
			frac = active / it[4]
		UI.ring(hud, c, rad, frac if unlocked else 0.0, col, active > 0.0, not unlocked)
		var gcol: Color = col if unlocked else Color(0.3, 0.38, 0.42)
		if active > 0.0:
			gcol = Color(1, 1, 1)
		var icon: Texture2D = tex.get("skill_s%d" % (i + 1))
		if icon != null:
			hud.draw_texture_rect(icon, Rect2(c - Vector2(32, 32), Vector2(64, 64)), false, Color.WHITE if unlocked else Color(0.3, 0.3, 0.35))
		else:
			UI.text(hud, font, c + Vector2(-rad, 10), it[0], 26, gcol, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, 3)
		UI.text(hud, font, c + Vector2(-40, rad + 16), it[1] if unlocked else "未解锁", 11, col if unlocked else Color(0.35, 0.42, 0.46), HORIZONTAL_ALIGNMENT_CENTER, 80, 2)
		if active > 0.0:
			UI.text(hud, font, c + Vector2(rad - 14, -rad + 8), "%d" % int(ceil(active)), 12, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 24, 2)
		if i == 0 and unlocked:
			for k in 3:
				UI.diamond(hud, c + Vector2(-14 + k * 14, rad - 5), 4.0, UI.GOLD if k < s1_charges else Color(0.15, 0.18, 0.2), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.5))
		# 进阶等级：环外上方两颗小点
		var slv: int = skill_lv["s%d" % (i + 1)]
		if slv >= 1:
			for k in 2:
				UI.diamond(hud, c + Vector2(-6 + k * 12, -rad - 5), 3.0, col if slv >= k + 2 else Color(0.15, 0.18, 0.2))


func _draw_result(vs: Vector2, title: String, en_title: String, col: Color, opts: Array) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.72))
	var r := Rect2(vs.x / 2 - 300, vs.y / 2 - 190, 600, 380)
	UI.frame(hud, r, col, {"t": t, "vines": true, "seed": 61, "cut": 16.0, "bracket": 16.0, "glow": 0.8})
	UI.caustic(hud, Rect2(r.position + Vector2(24, 10), Vector2(r.size.x - 48, 24)), t, col)
	var ew := font.get_string_size(en_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + en_title.length() * 4.0
	UI.en(hud, font, Vector2(r.get_center().x - ew / 2.0, r.position.y + 50), en_title, 13, col, 4.0)
	UI.heading(hud, font, Vector2(r.get_center().x, r.position.y + 90), title, 36, col, 250.0)
	var mm := int(t) / 60
	var ss := int(t) % 60
	var stats := [["探索时间", "%02d:%02d" % [mm, ss]], ["等级", "Lv.%d  %s" % [level, ["精零", "精英化一", "精英化二"][elite_stage]]],
		["击杀", str(kills)], ["难度", "%d  %s" % [diff, D.DIFFICULTY[diff].name]]]
	if diff_new and state == S.WIN:
		UI.chip(hud, font, Vector2(r.get_center().x - 80, r.position.y + 118), "解锁难度 %d「%s」" % [diff + 1, D.DIFFICULTY[diff + 1].name], UI.GOLD, 13)
	for i in stats.size():
		var y := r.position.y + 156 + i * 34
		UI.diamond(hud, Vector2(r.position.x + 48, y - 6), 3.5, Color(col.r, col.g, col.b, 0.8))
		UI.text(hud, font, Vector2(r.position.x + 62, y), stats[i][0], 16, UI.SUB)
		UI.text(hud, font, Vector2(r.position.x + 200, y), stats[i][1], 18, UI.TEXT)
	var bx := r.position.x + 40
	var bw := (r.size.x - 80 - 12 * (opts.size() - 1)) / opts.size()
	result_btns.clear()
	var mouse := hud.get_local_mouse_position()
	for op in opts:
		var br := Rect2(bx, r.end.y - 70, bw, 40)
		result_btns.append([br, op[2]])
		var hov := br.has_point(mouse)
		UI.frame(hud, br, col, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov else 0.0, "alpha": 1.0 if hov else 0.7})
		UI.text(hud, font, br.position + Vector2(14, 27), op[0], 16, UI.TEXT)
		UI.text(hud, font, br.position + Vector2(br.size.x - 34, 27), op[1], 13, col)
		bx += bw + 12
