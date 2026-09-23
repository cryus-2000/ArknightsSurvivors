extends Node2D
## 水月 · 深海幸存者 —— v0.7
## 敌人/掉落物/特效用数据数组管理，统一在 _draw 中以像素贴图绘制（美术像素 ×2）。
## 灯火是一个真实光源：场景整体偏暗，只有玩家周围被照亮。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
## 美术交付的特效帧数（见 docs/05_art_handoff.md）
const FXF := {"fx_s1_burst": 6, "fx_s1_slash": 4, "fx_s2_aura": 4, "fx_s2_bind": 4, "fx_s3_aura": 6,
	"fx_s3_slash": 4, "fx_cast": 8, "fx_stun": 4, "fx_hit": 4, "fx_death": 5}
const ECOL := {"bone": Color(0.85, 0.9, 0.85), "slider": Color(0.45, 0.7, 1.0), "stone": Color(0.7, 0.7, 0.75), "offspring": Color(0.6, 0.9, 0.5),
	"brood": Color(0.9, 0.6, 0.8), "pocket": Color(0.8, 0.55, 1.0), "skimmer": Color(0.4, 0.9, 0.9), "mother": Color(0.9, 0.5, 0.7),
	"mimic": Color(1.0, 0.75, 0.4), "path": Color(0.6, 0.7, 1.0), "fractal": Color(0.6, 0.7, 1.0), "izumik": Color(0.5, 1.0, 0.7),
	"ishar": Color(0.75, 0.55, 1.0), "tear": Color(0.75, 0.55, 1.0), "iberia": Color(1.0, 0.6, 0.5), "carmen": Color(0.7, 0.7, 1.0),
	"bishop": Color(0.7, 1.0, 0.9), "archon": Color(0.5, 0.9, 0.9), "immortal": Color(0.6, 0.8, 1.0), "paranoia": Color(0.8, 0.6, 1.0)}

enum S { PLAY, CHOICE, PAUSE, DEAD, WIN, SHOP, SHOW, STATS }

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
var swing_face := 0.0
var level := 1
var xp := 0.0
var xp_need := 8.0
var kills := 0
var lamp := 100.0

# ---------- 水月：伞击 / 天赋 / 技能 ----------
var growth := {}                 # 成长项 id -> 已选次数
var elite_stage := 0             # 精英化阶段 0/1/2
var module := ""                 # 精二模组 x / y / a
var swing_cd := 0.0
var u_dmg_mult := 1.0
var u_area_mult := 1.0
var u_spd_mult := 1.0
var t_mult := 0.6                # 天赋一：触手追击倍率
var rib_bonus := 0.0
var extra_targets := 0
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
var s3_pen_cd := 0.0
var heal_budget := 0.0           # 反移情击杀回复：每秒上限
var talent2_on := false

# ---------- 藏品带来的附加能力 ----------
var jelly_count := 0
var jelly_lamp := 0.0
var tide_on := false
var tide_cd := 0.0
var tide_every := 3.0
var tide_mult := 1.0
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
var combos: Array = []

# ---------- 援护干员 ----------
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
var jelly_pos: Array = []
var next_id := 0
var orbit_a := 0.0
var spawn_acc := 0.0
var next_elite := 60.0
var diff := 0                # 本局难度
var diff_new := false        # 本局通关解锁了新难度
var next_horde := 120.0
var show_queue: Array = []   # 解锁演出队列
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
var mires: Array = []
var next_chest := 20.0
var next_mire := 150.0
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
var dmg_src := ""
var lv_marks := {}
var at_frames := 0
var shot_at := [3400]
var choice_wait := 0
var choice_shot := false


func _ready() -> void:
	rng.randomize()
	font = load("res://fonts/ui.ttf")
	for n in ["drifter", "dart", "crawler", "shell", "boss", "tiles", "seaweed", "coral", "shell_prop", "rock",
			"gem_small", "gem_big", "oil", "chest", "slash", "tentacle", "jelly", "light", "shadow", "player",
			"ally_sniper", "ally_caster", "ally_medic", "ally_support", "orb",
			"e_bone", "e_slider", "e_stone", "e_offspring", "e_brood", "e_pocket", "e_skimmer", "e_mother", "e_chest", "e_mimic",
			"e_path", "e_fractal", "e_izumik", "e_ishar", "e_tear", "e_iberia", "e_carmen", "e_bishop", "e_archon", "e_immortal", "e_paranoia", "e_paranoia2", "e_bishop_feign", "e_archon_feign", "e_immortal_feign", "ebullet", "ingot", "merchant", "pickup_magnet", "pickup_heal",
			"terrain_patches", "prop_pillar", "prop_wall", "prop_wreck", "terrain_ridge", "terrain_peak", "terrain_mire"]:
		tex[n] = A.tex(n)
		if n.begins_with("e_") and A.has_override(n) and tex[n] != null and tex[n].get_height() >= 32:
			foot_anchor[n] = true
		if n.begins_with("e_") and tex[n] != null:
			tex[n + "_white"] = A.white_of(tex[n]) if A.has_override(n) else A.tex(n + "_white")
	# 可选素材：有图就用，没有就用程序效果
	var optional := ["player_attack_48", "player_idle", "player_run", "player_attack", "player_hurt", "player_death", "skill_s1", "skill_s2", "skill_s3"]
	optional.append_array(FXF.keys())
	for rid in D.RELICS:
		optional.append("relic_" + rid)
	for n in optional:
		tex[n] = A.tex(n)

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
	if state == S.PAUSE or state == S.CHOICE or state == S.SHOP or state == S.SHOW or state == S.STATS:
		target = 1800.0
	Sfx.cut_target = target
	Sfx.vol_target = -12.0 if (state == S.DEAD or state == S.WIN) else -4.0


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
		if at_frames == 130:
			state = S.STATS
		if at_frames == 134 and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_fx_stats.png")
			state = S.PLAY
		if at_frames == 20:
			next_horde = t + 6.0
			merchant = {"pos": ppos + Vector2(900, -300), "life": 60.0, "near": false}
		if at_frames == 60:
			_drop(ppos + Vector2(120, 40), "magnet", 1.0)
			_drop(ppos + Vector2(-120, 40), "heal", 1.0)
		for f in [64, 72, 100, 125]:
			if at_frames == f and DisplayServer.get_name() != "headless":
				get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_fx_%d.png" % f)
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
			_pick(rng.randi() % choices.size())
		if (state == S.DEAD or state == S.WIN or t > 620.0) and not bal_done:
			bal_done = true
			print("BALANCE ", JSON.stringify({"win": state == S.WIN, "t": int(t), "lv": level, "marks": lv_marks, "kills": kills,
				"elites": elites_killed, "relics": relics.size(), "ingots": ingots, "maxhp": max_hp, "bosses": bosses.map(func(b): return "%s:%s" % [b.type, "dead" if b.dead else "%d%%" % int(100 * b.hp / b.maxhp)]), "allies": allies.size(), "elite_stage": elite_stage,
				"boss_hp": (boss.hp / boss.maxhp) if boss != null else -1.0}))
			get_tree().quit()
		return
	if not (OS.get_cmdline_user_args().has("--fxtest") and at_frames >= 90 and at_frames < 100):
		hp = max_hp
	if lvup_show > 1.05 and lvup_show < 1.12 and level == 3 and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_lvup.png")
	if state == S.CHOICE:
		choice_wait += 1
		if choice_wait == 40 and not choice_shot and DisplayServer.get_name() != "headless":
			choice_shot = true
			get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_choice.png")
		if choice_wait > 45:
			choice_wait = 0
			_pick(rng.randi() % choices.size())
	if at_frames % 1200 == 0:
		print("t=%d lv=%d E%d mod=%s hp=%d enemies=%d kills=%d lamp=%d growth=%s relics=%s allies=%s fps=%d" % [t, level, elite_stage, module, hp, enemies.size(), kills, lamp, growth, relics, allies.map(func(a): return "%s%d" % [a.kind, a.lv]), Engine.get_frames_per_second()])
	for bb in bosses:
		if not bb.dead and not bb.invuln:
			bb.hp -= 40.0
			if bb.hp <= 0.0:
				_kill(bb)
	if shot_at.has(at_frames) and DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shot_%d.png" % at_frames)
	if state == S.WIN or at_frames > 14000:
		print("AUTOTEST END state=%d t=%d combos=%s" % [state, t, combos])
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
		"restart":
			get_tree().reload_current_scene()
		"title":
			get_tree().change_scene_to_file("res://main.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if settings.visible:
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
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: int = event.keycode
	if k == KEY_TAB or k == KEY_C:
		if state == S.PLAY:
			state = S.STATS
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
	ppos += mv * speed * dt
	swing_face -= dt

	hp = min(max_hp, hp + regen * dt)
	lamp = max(0.0, lamp - dt * (100.0 / LAMP_EMPTY_SECONDS) * lamp_decay)
	if lamp <= 0.0:
		hp -= 3.0 * dt
		hurt_flash = max(hurt_flash, 0.05)
	invuln -= dt
	hurt_flash -= dt

	_spawn(dt)
	_build_grid()
	_update_enemies(dt)
	_mizuki(dt)
	_update_allies(dt)
	_update_bullets(dt)
	_update_ebullets(dt)
	_update_status(dt)
	_update_merchant(dt)
	_update_gems(dt)
	_update_fx(dt)
	_cleanup()

	if hp <= 0.0:
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
	var pool := ["bone", "bone", "bone", "bone", "bone", "slider", "slider"]
	if t > 120.0:
		pool += ["stone"]
	if t > 180.0:
		pool += ["slider", "bone"]
	if t > 300.0:
		pool += ["offspring"]
	if t > 420.0:
		pool += ["stone", "bone", "bone"]
	var pick: String = pool[rng.randi() % pool.size()]
	if pick == "stone":
		var ns := 0
		for e in enemies:
			if e.type == "stone" and not e.dead:
				ns += 1
		if ns >= 6:
			pick = "bone"
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
	var rate := 1.6 + t / 30.0
	if _boss_alive():
		rate *= 0.5
	spawn_acc += rate * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if enemies.size() < MAX_ENEMIES:
			_spawn_enemy(_pick_type(), _edge_pos())
	if t >= next_elite:
		next_elite += 45.0 if diff >= 4 else 60.0
		var et := _pick_elite()
		_spawn_enemy(et, _edge_pos())
		_show_banner("精英「%s」出现！击败它获得藏品" % D.ENEMIES[et].name)
		Sfx.play("roar", -3.0)
	if t >= next_horde - 3.0 and horde_warned != next_horde and not _boss_alive():
		horde_warned = next_horde
		horde_warn = 3.0
		Sfx.play("roar", -2.0, 0.55, 0.0)
	if t >= next_horde and not _boss_alive():
		next_horde += 120.0
		horde_warn = 0.0
		horde_hit = 1.2
		_shake(1.4)
		fx.append({"kind": "horde_ring", "pos": ppos, "r": 640.0, "life": 0.9, "max": 0.9, "col": Color(0.75, 0.3, 1.0)})
		Sfx.play("roar", 2.0, 0.8, 0.0)
		var n := int((30 + int(t / 8.0)) * horde_mult * (1.4 if diff >= 7 else 1.0))
		if horde_chest:
			_drop(ppos + Vector2(70, 0), "chest", 1.0)
		var base := rng.randf() * TAU
		for i in n:
			if enemies.size() >= MAX_ENEMIES + 60:
				break
			var p := ppos + Vector2.from_angle(base + TAU * i / n) * rng.randf_range(560.0, 620.0)
			_spawn_enemy("bone" if i % 4 else "slider", p)
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
		next_mire = t + rng.randf_range(40.0, 60.0)
		mires.append({"pos": ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 360.0), "r": 16.0, "maxr": rng.randf_range(70.0, 110.0), "life": 45.0, "seed": rng.randf() * 100.0})
	# 商人
	if merchant.is_empty() and merchant_idx < MERCHANT_TIMES.size() and t >= MERCHANT_TIMES[merchant_idx]:
		merchant_idx += 1
		merchant = {"pos": ppos + Vector2.from_angle(rng.randf() * TAU) * 260.0, "life": 60.0, "near": false}
		_show_banner("商人出现了 —— 去找他交易源石锭")
		Sfx.play("relic", -4.0)


func _new_enemy(type: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = D.ENEMIES[type]
	var role: String = d.get("role", "")
	var hpm := (1.0 + t / 110.0) * (1.0 + (0.15 if diff >= 1 else 0.0) + (0.2 if diff >= 10 else 0.0))
	var dmm := 1.0 + (0.15 if diff >= 2 else 0.0) + (0.2 if diff >= 10 else 0.0)
	next_id += 1
	var e := {
		"id": next_id, "type": type, "name": d.name, "tex": d.tex, "pos": pos,
		"hp": d.hp * hpm, "maxhp": d.hp * hpm,
		"spd": d.spd * rng.randf_range(0.9, 1.1) * (1.1 if diff >= 6 else 1.0), "dmg": d.dmg * (1.0 + t / 220.0) * dmm,
		"r": d.r, "r0": d.r, "xp": d.xp, "age": 0.0,
		"evo": false, "elite": role == "elite", "boss": role == "boss", "stun": 0.0,
		"kb": Vector2.ZERO, "flash": 0.0, "squash": 0.0, "slow": 0.0, "jhit": 0.0, "dead": false, "bt": 0.0, "fx": 1.0,
		"ai": d.ai, "range": d.get("range", 0.0), "cd": d.get("cd", 0.0), "cdt": rng.randf() * d.get("cd", 1.0),
		"corrode": d.get("corrode", 0.0), "nerve": d.get("nerve", 0.0), "def": 1.0, "set_t": 0.0, "set_done": false,
		"chest": false, "hidden": false, "invuln": false, "hits": 0, "phase": 1, "charge": 0.0, "feed": false,
	}
	if e.elite:
		e.hp *= 7.0
		e.maxhp = e.hp
		e.xp *= 10.0
		e.dmg *= 1.3
	if e.boss:
		e.hp = d.hp * (1.0 + t / 600.0) * (1.3 if diff >= 8 else 1.0) * (1.15 if diff >= 1 else 1.0)
		e.maxhp = e.hp
		e.spd = d.spd
		e.dmg = d.dmg * dmm * (1.25 if diff >= 10 else 1.0)
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
		e.stun -= dt
		e.squash -= dt
		e.slow -= dt
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

		if not e.evo and not e.elite and not e.boss and e.ai != "static" and e.age > evo_age:
			_evolve(e)

		# 注亡拟嗣：生命持续流失
		if e.type == "brood":
			e.hp -= e.maxhp * 0.08 * dt
			if e.hp <= 0.0:
				e.dead = true
				continue
		if e.boss:
			_boss_ai(e, dt, dir, dist)
		if e.dead:
			continue

		# ---- 移动
		var v: Vector2 = e.kb
		var spd: float = e.spd * dark_mod * (0.65 if e.slow > 0.0 else 1.0)
		if e.get("channel", 0.0) > 0.0 or e.get("coma", false):
			spd = 0.0
		var move_dir := dir
		if e.feed and final_target_valid(e):
			move_dir = (e.feed_to.pos - e.pos).normalized()
		if e.stun <= 0.0:
			match e.ai:
				"melee":
					v += move_dir * spd
				"ranged":
					e.set_t -= dt
					if e.get("hover", false) == false and D.ENEMIES[e.type].get("entrench", false) and not e.set_done and dist < e.range:
						# 固海凿石者：首次接敌时原地架起，大幅提高防御
						e.set_done = true
						e.set_t = 20.0
						e.def = 0.4
						_add_text(e.pos + Vector2(0, -24), "架起", Color(0.75, 0.8, 0.9), 14)
					if e.set_t > 0.0:
						pass
					elif dist > e.range * 0.85:
						v += dir * spd
					if e.set_t <= 0.0 and e.set_done:
						e.def = 1.0
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

		# ---- 囊海爬行者：每失去 15% 生命爆发一次
		if e.has("burst_at") and e.hp <= e.burst_at:
			e.burst_at -= e.maxhp * 0.15
			fx.append({"kind": "ring", "pos": e.pos, "r": 95.0, "life": 0.4, "max": 0.4, "col": Color(0.8, 0.45, 1.0)})
			Sfx.play("tentacle", -2.0, 0.7)
			if dist < 95.0:
				_enemy_hit(e.dmg * 0.8, {"corrode": 0.0, "nerve": 30.0}, true)

		# ---- 接触伤害
		if e.dmg > 0.0 and (e.ai == "melee" or e.type == "brood") and dist < e.r + 12.0 and not e.get("coma", false):
			if D.ENEMIES[e.type].get("morph", false):
				_morph(e)
				continue
			if invuln <= 0.0:
				dmg_src = "contact_" + e.type
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
	var spd := 280.0 if e.boss else 200.0
	var n := 1
	if e.type == "ishar" and e.phase == 2:
		n = 3
	if e.type == "paranoia":
		n = 3 if e.phase == 1 else 5
	if e.has("ammo"):
		e.ammo -= 1
		if e.ammo <= 0:
			e.ai = "melee"
			_add_text(e.pos + Vector2(0, -40), "弹药耗尽", Color(1.0, 0.8, 0.5), 14)
	for k in n:
		var d := dir.rotated((k - (n - 1) / 2.0) * 0.22)
		ebullets.append({"pos": e.pos, "vel": d * spd, "dmg": e.dmg * (0.7 if e.boss else 0.45) * (2.0 if e.has("ammo") else 1.0),
			"slow": e.type == "paranoia", "r": 7.0 if e.boss else 5.0, "life": 2.0,
			"corrode": e.corrode, "nerve": 0.0, "true": e.type == "ishar" and e.phase == 2})
	# 投嗣育母：每次攻击在水月附近放下一只注亡拟嗣
	if e.type == "mother":
		var nb := 0
		for o in enemies:
			if o.type == "brood" and not o.dead:
				nb += 1
		if nb < 12:
			_spawn_enemy("brood", ppos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(45.0, 75.0))


func _update_ebullets(dt: float) -> void:
	for b in ebullets:
		if b.life <= 0.0:
			continue
		b.pos += b.vel * dt
		b.life -= dt
		if b.pos.distance_to(ppos + Vector2(0, -14)) < b.r + 12.0:
			b.life = 0.0
			if b.get("slow", false):
				atk_slow = 3.0
			dmg_src = "bullet"
			if invuln <= 0.0:
				_enemy_hit(b.dmg, b, b["true"])


## 敌人命中水月：闪避判定、侵蚀、神经损伤
func _enemy_hit(dmg: float, src: Dictionary, ignore_armor := false) -> void:
	if rng.randf() < min(dodge, 0.6):
		invuln = 0.3
		Sfx.play("dodge", -4.0)
		_add_text(ppos + Vector2(0, -80), "闪避", Color(0.6, 0.85, 1.0), 16)
		on_dodge()
		return
	_hurt(dmg * (1.3 if lamp < 30.0 else 1.0), ignore_armor)
	if src.get("corrode", 0.0) > 0.0:
		corrode_pool += dmg * src.corrode * 2.0
		_add_text(ppos + Vector2(14, -64), "侵蚀", Color(0.8, 0.5, 1.0), 13)
	if src.get("nerve", 0.0) > 0.0:
		_add_nerve(src.nerve)


func on_dodge() -> void:
	pass


func _add_nerve(v: float) -> void:
	nerve += v
	if nerve >= 100.0:
		nerve = 0.0
		pstun = 1.0
		dmg_src = "nerve"
		_hurt(max_hp * 0.1, true)
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
	for m in mires:
		m.life -= dt
		m.r = min(m.maxr, m.r + 5.0 * dt)
		if m.pos.distance_to(ppos) < m.r:
			hp -= 1.5 * dt
			dmg_log["mire"] = dmg_log.get("mire", 0.0) + 1.5 * dt
			_add_nerve(18.0 * dt)
	mires = mires.filter(func(m): return m.life > 0.0)
	for s in shocks:
		s.r += 320.0 * dt
		if not s.hit and abs(s.pos.distance_to(ppos) - s.r) < 22.0:
			s.hit = true
			if invuln <= 0.0:
				pstun = max(pstun, 0.8)
				_enemy_hit(s.dmg, {}, true)
	shocks = shocks.filter(func(s): return s.r < s.maxr)


## Boss 行为
func _boss_ai(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	e.bt += dt
	# 接潮：昏迷后回复；两者同时昏迷则一起倒下
	if e.get("coma", false):
		e.hp = min(e.maxhp, e.hp + e.maxhp * 0.1 * dt)
		var p = e.get("partner")
		if p != null and not p.dead and p.get("coma", false):
			e.coma = false
			p.coma = false
			e.invuln = false
			p.invuln = false
			_kill(e)
			_kill(p)
			_show_banner("接潮双体 同时倒下")
			return
		if e.hp >= e.maxhp:
			e.coma = false
			e.invuln = false
			_add_text(e.pos + Vector2(0, -50), "苏醒", Color(0.6, 1.0, 0.9), 18)
		return
	match e.type:
		"iberia", "carmen":
			# 圣徒：3 发弹药，打空后近战；定期装填，装填中被攻击会被打断并晕眩
			if e.channel > 0.0:
				e.channel -= dt
				if e.channel <= 0.0:
					e.ammo = 3
					e.ai = "ranged"
					_add_text(e.pos + Vector2(0, -44), "装填完毕", Color(1.0, 0.8, 0.5), 14)
			else:
				e.reload_t -= dt
				if e.reload_t <= 0.0 and e.stun <= 0.0:
					e.reload_t = 20.0
					e.channel = 2.0
					_add_text(e.pos + Vector2(0, -44), "装填中……", Color(1.0, 0.8, 0.5), 16)
		"path":
			# 塑路者：周期冲锋；每受击 10 次召唤碎片
			if e.bt > 5.0:
				e.bt = 0.0
				e.kb = dir * 520.0
			if e.hits >= 10:
				e.hits = 0
				for k in 3:
					_spawn_enemy("fractal", e.pos + Vector2.from_angle(TAU * k / 3.0) * 50.0)
				_add_text(e.pos + Vector2(0, -60), "碎裂", Color(0.6, 0.7, 1.0), 16)
		"izumik":
			if e.phase == 1:
				# 学习阶段：无敌，放出子代，子代回到本体会被吸收
				e.hp = min(e.maxhp, e.hp + e.maxhp * 0.012 * dt)
				if e.bt > 4.0:
					e.bt = 0.0
					for k in 2:
						var o := _spawn_enemy("offspring", e.pos + Vector2.from_angle(rng.randf() * TAU) * 140.0)
						o.feed = true
						o.feed_to = e
						o.spd = 45.0
				if e.hp >= e.maxhp:
					e.phase = 2
					e.invuln = false
					e.bt = 0.0
					_show_banner("伊祖米克进入「解读阶段」！")
					Sfx.play("roar", 0.0, 0.8, 0.0)
					_shake(1.0)
			else:
				# 解读阶段：周期冲击波，被波及会晕眩
				if e.bt > 7.0:
					e.bt = 0.0
					shocks.append({"pos": e.pos, "r": e.r, "maxr": 420.0, "dmg": e.dmg * 1.2, "hit": false})
					Sfx.play("skill", -2.0, 0.6)
		"ishar":
			# 伊莎玛拉：召唤之泪；泪未被清除时持续充能，充满后变身
			if e.bt > 6.0:
				e.bt = 0.0
				_spawn_tears(e, 1)
			var ntear := 0
			for o in enemies:
				if o.type == "tear" and not o.dead:
					ntear += 1
			if e.phase == 1:
				e.charge += ntear * 3.0 * dt
				if e.charge >= 100.0:
					e.phase = 2
					e.dmg *= 1.6
					_show_banner("伊莎玛拉 完成了转化！")
					Sfx.play("roar", 2.0, 0.6, 0.0)
					_shake(1.2)
			if not e.get("half", false) and e.hp < e.maxhp * 0.5:
				e.half = true
				e.dmg *= 1.3
				_spawn_tears(e, 2)
				_show_banner("伊莎玛拉 愈发狂暴")
			# 治疗周围的海嗣
			e.heal_t = e.get("heal_t", 0.0) + dt
			if e.heal_t > 4.0:
				e.heal_t = 0.0
				var n := 0
				for j in _query(e.pos, 260.0):
					var o: Dictionary = enemies[j]
					if o.dead or o.boss or o.chest or n >= 3:
						continue
					o.hp = min(o.maxhp, o.hp + o.maxhp * 0.3)
					fx.append({"kind": "ring", "pos": o.pos, "r": 18.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 1.0, 0.7)})
					n += 1


func _spawn_tears(e: Dictionary, n: int) -> void:
	for k in n:
		var cnt := 0
		for o in enemies:
			if o.type == "tear" and not o.dead:
				cnt += 1
		if cnt >= 6:
			return
		_spawn_enemy("tear", e.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(140.0, 240.0))


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
	if not ignore_armor:
		amount = max(1.0, amount - armor)
	hp -= amount
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


func _damage(e: Dictionary, dmg: float) -> void:
	if e.dead:
		return
	if e.invuln:
		if texts.size() < 80 and rng.randf() < 0.2:
			_add_text(e.pos + Vector2(0, -e.r - 10), "无效", Color(0.6, 0.7, 0.8), 13)
		return
	if e.chest and e.hidden:
		e.hidden = false
		_reveal_mimic(e)
		return
	dmg *= e.def
	e.hp -= dmg
	e.hits += 1
	e.flash = 0.08
	e.squash = 0.14
	if texts.size() < 80 and Cfg.dmg_numbers:
		if crit_hit:
			_add_text(e.pos + Vector2(rng.randf_range(-6, 6), -e.r - 10), str(int(round(dmg))), UI.GOLD, 22)
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
		var want := (0.02 if module == "y" else 0.01)
		var got: float = min(want, heal_budget)
		heal_budget -= got
		_heal(max_hp * got)
	if flesh_heal and e.evo:
		_heal(max_hp * 0.03)
	if ember and e.elite:
		lamp = min(100.0, lamp + 20.0)
	if e.xp > 0.0:
		_drop(e.pos, "xp", e.xp * xp_mult)
	if rng.randf() < 0.02:
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
		_drop(e.pos + Vector2(20, 10), "oil", 40.0)
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
	var r := 70.0 * u_area_mult
	if s3_active > 0.0:
		r *= 1.4
	return r


func _dmg_bonus() -> float:
	var m := dmg_mult
	if talent2_on and _low_hp_enemy_near():
		m *= 1.35 if module == "y" else 1.22
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
			s2_sp += dt * sp_mult
			if s2_sp >= P.s2_charge:
				s2_sp = 0.0
				s2_active = P.s2_dur
				_skill_cast("s2")
	if skill_lv.s3 >= 1:
		if s3_active > 0.0:
			s3_active -= dt
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
			s3_sp += dt * sp_mult
			if s3_sp >= P.s3_charge:
				s3_sp = 0.0
				s3_active = P.s3_dur
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
			var interval := 0.9 * u_spd_mult * (1.5 if atk_slow > 0.0 else 1.0)
			if s2_active > 0.0:
				interval *= D.SKILL_P.s2_interval
			swing_cd = max(0.18, interval)
			_umbrella(targets[0])
		else:
			swing_cd = 0.1

	if tide_on:
		tide_cd -= dt
		if tide_cd <= 0.0:
			tide_cd = tide_every
			_tide()
	if jelly_count > 0:
		_jelly(dt)
	else:
		jelly_pos.clear()


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
	for k in segs:
		var a := ang
		if segs > 1:
			a = ang - half + span * 0.5 + (half * 2.0 - span) * float(k) / float(segs - 1)
		fx.append({"kind": "slash", "tex": tex_name, "pos": origin, "ang": a, "scale": sc, "life": life, "max": life, "col": col})


func _umbrella(target: Dictionary) -> void:
	var P: Dictionary = D.SKILL_P
	var radius := _swing_radius()
	var half := deg_to_rad(min(180.0, 65.0 + rib_bonus + 15.0 * growth.get("u_area", 0)))
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
	for e in hit:
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
	var n := 1 + extra_targets + (1 if module == "x" else 0)
	if s2_active > 0.0:
		n += 1
	if s3_active > 0.0:
		n += 2 if skill_lv.s3 >= 3 else 1
	if module == "a" and (s2_active > 0.0 or s3_active > 0.0):
		n += 2
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
				delayed.append({"at": 0.06 * k, "kind": "burst", "pos": hit[k].pos, "dmg": dmg * P.s1_burst_mult, "r": P.s1_burst_r})
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
						_damage(e, dmg * P.s2_twin_mult)
						if not e.dead:
							e.stun = maxf(e.stun, 0.3)
				_slash_fx(ppos, a2, half * 0.8, radius, Color(0.5, 0.85, 1.4), "slash", 0.18)
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
		delayed.append({"at": P.s3_echo_delay, "kind": "echo", "ang": ang + PI, "dmg": dmg * P.s3_echo_mult,
			"half": half, "radius": radius, "dirs": dirs.size()})

	# ---- 斩击表现
	var slash_col := Color.WHITE
	if empowered:
		slash_col = Color(1.6, 1.3, 0.7)
	elif s3_active > 0.0:
		slash_col = Color(1.2, 0.85, 1.6)
	elif s2_active > 0.0:
		slash_col = Color(0.8, 1.1, 1.5)
	var slash_tex := "slash"
	if empowered and tex.get("fx_s1_slash") != null:
		slash_tex = "fx_s1_slash"
	elif s3_active > 0.0 and tex.get("fx_s3_slash") != null:
		slash_tex = "fx_s3_slash"
	if empowered and alive.size() > 0:
		_anim("fx_s1_burst", alive[0].pos, 0.35)
	for k in min(hit.size(), 3):
		_anim("fx_hit", hit[k].pos, 0.16)
	for d in dirs:
		_slash_fx(ppos, d, half, radius, slash_col, slash_tex, 0.26 if empowered else 0.22)
	if empowered:
		# 唤醒：外圈再叠一层更大的金色斩痕
		_slash_fx(ppos, ang, half * 0.9, radius * 1.25, Color(2.0, 1.5, 0.6, 0.8), "slash", 0.3)


## 延时攻击的执行
func _run_delayed(dl: Dictionary) -> void:
	var P: Dictionary = D.SKILL_P
	match dl.kind:
		"burst":
			# 创伤扩散：目标处的范围冲击
			for j in _query(dl.pos, dl.r):
				var e: Dictionary = enemies[j]
				if not e.dead and e.pos.distance_to(dl.pos) < dl.r + e.r:
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
		"echo":
			# 倒影：在反方向复刻一次攻击（深海形态下全方向）
			var dirs: Array = [dl.ang]
			if dl.dirs > 1:
				dirs = [dl.ang, dl.ang + TAU / 3.0, dl.ang - TAU / 3.0]
			var seen := {}
			for d in dirs:
				for e in _arc_hit(ppos, d, dl.half, dl.radius):
					if seen.has(e.id):
						continue
					seen[e.id] = true
					_damage(e, dl.dmg)
					if not e.dead:
						e.stun = maxf(e.stun, P.s3_stun * 0.5)
				_slash_fx(ppos, d, dl.half, dl.radius, Color(0.9, 0.6, 1.6, 0.8), "slash", 0.3)
			fx.append({"kind": "ghost", "pos": ppos + Vector2.from_angle(dl.ang) * 26.0, "flip": cos(dl.ang) < 0.0, "life": 0.35, "max": 0.35})
			Sfx.play("swing", -9.0, 0.7, 0.05)


## 技能发动：横幅 + 光环爆发 + 震屏
func _skill_cast(sid: String) -> void:
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
	_damage(target, dmg)
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
		if module == "a" and not target.boss:
			target.kb += (ppos - p).normalized() * 260.0
	fx.append({"kind": "tentacle", "pos": p, "life": 0.45, "max": 0.45, "flip": rng.randf() < 0.5})
	Sfx.play("tentacle", -6.0)
	_sparks(p + Vector2(0, 8), Vector2.UP, Color(0.6, 0.45, 1.0), 4, 150.0)


func _tide() -> void:
	var radius := 110.0 * tide_mult
	var dmg := (14.0 + level * 1.2) * _dmg_bonus() * tide_mult
	for j in _query(ppos, radius + 40.0):
		var e: Dictionary = enemies[j]
		if e.dead:
			continue
		if e.pos.distance_to(ppos) < radius + e.r:
			_damage(e, dmg)
			e.kb += (e.pos - ppos).normalized() * (80.0 if e.boss else 280.0)
	fx.append({"kind": "ring", "pos": ppos, "r": radius, "life": 0.35, "max": 0.35, "col": Color(0.45, 0.85, 1.0)})


func _jelly(dt: float) -> void:
	orbit_a += dt * 2.6
	var R := 80.0
	jelly_pos.clear()
	for i in jelly_count:
		var p := ppos + Vector2.from_angle(orbit_a + TAU * i / jelly_count) * R
		jelly_pos.append(p)
		for j in _query(p, 40.0):
			var e: Dictionary = enemies[j]
			if e.dead or e.jhit > 0.0:
				continue
			if e.pos.distance_to(p) < e.r + 11.0:
				_damage(e, (6.0 + level * 0.8) * _dmg_bonus())
				e.jhit = 0.4
				if not e.boss:
					e.kb += (e.pos - ppos).normalized() * 120.0
				if jelly_lamp > 0.0:
					lamp = min(100.0, lamp + jelly_lamp)


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
			return 6
		"oil":
			return 5
		"refresh":
			return 3
	return 0


func _roll_shop() -> void:
	shop_items.clear()
	var pool: Array = []
	for rid in D.RELICS:
		if not relics.has(rid):
			pool.append(rid)
	pool.shuffle()
	for i in min(3, pool.size()):
		var r: Dictionary = D.RELICS[pool[i]]
		shop_items.append({"kind": "relic", "id": pool[i], "name": r.name, "desc": r.desc, "price": _shop_price("relic"), "sold": false})
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
		card.custom_minimum_size = Vector2(200, 300)
		card.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			card.add_theme_stylebox_override(st, empty)
		card.set_meta("born", Time.get_ticks_msec() + i * 50)
		card.set_meta("oy", 60.0)
		card.set_meta("lift", 0.0)
		card.set_meta("dy", 190.0)
		card.set_meta("item", it)
		card.modulate.a = 0.0
		card.draw.connect(_draw_shop_card.bind(card, it, i))
		card.mouse_entered.connect(func(): card.queue_redraw())
		card.mouse_exited.connect(card.queue_redraw)
		card.pressed.connect(_buy.bind(i))
		var desc := Label.new()
		desc.text = it.desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.position = Vector2(18, 190)
		desc.size = Vector2(164, 70)
		desc.add_theme_font_size_override("font_size", 14)
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
		col = UI.CAT_COL.get(D.RELICS[it.id].cat, UI.GOLD)
	elif it.kind == "heal":
		col = Color(0.5, 1.0, 0.6)
	var afford: bool = ingots >= it.price
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	UI.panel(card, r, Color(0.05, 0.12, 0.16, 0.97) if hov else UI.BG2, col if hov else Color(col.r, col.g, col.b, 0.4), 12.0, col)
	UI.text(card, font, r.position + Vector2(16, 30), str(i + 1), 16, Color(col.r, col.g, col.b, 0.7))
	var c := r.position + Vector2(r.size.x / 2, 96)
	UI.diamond(card, c, 34.0, Color(0.02, 0.06, 0.08), col)
	var ic: Texture2D = tex.get("relic_" + it.id) if it.kind == "relic" else null
	if ic != null:
		card.draw_texture_rect(ic, Rect2(c - Vector2(20, 20), Vector2(40, 40)), false)
	else:
		UI.text(card, font, c + Vector2(-30, 10), it.name.substr(0, 1), 28, col, HORIZONTAL_ALIGNMENT_CENTER, 60)
	UI.text(card, font, r.position + Vector2(0, 170), it.name, 18, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var price_col := Color(1.0, 0.6, 0.3) if afford else Color(0.6, 0.35, 0.35)
	if it.sold:
		UI.text(card, font, r.position + Vector2(0, r.size.y - 18), "已售出", 16, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		card.draw_rect(Rect2(r.position, r.size), Color(0, 0, 0, 0.5))
	else:
		card.draw_texture_rect(tex.ingot, Rect2(r.position + Vector2(r.size.x / 2 - 30, r.size.y - 34), Vector2(18, 14)), false)
		UI.text(card, font, r.position + Vector2(r.size.x / 2 - 6, r.size.y - 20), str(it.price), 18, price_col)


func _buy(i: int) -> void:
	if state != S.SHOP or i >= shop_items.size():
		return
	var it: Dictionary = shop_items[i]
	if it.sold or ingots < it.price:
		Sfx.play("ui_move", -2.0, 0.6)
		return
	ingots -= it.price
	it.sold = true
	match it.kind:
		"relic":
			relics.append(it.id)
			_apply_relic(it.id)
			_check_combos()
		"heal":
			_heal(max_hp * 0.4)
		"oil":
			lamp = min(100.0, lamp + 50.0)
	Sfx.play("ui_ok")
	_build_shop_ui()


func _refresh_shop() -> void:
	if ingots < _shop_price("refresh"):
		return
	ingots -= _shop_price("refresh")
	_roll_shop()
	Sfx.play("relic", -6.0)
	_build_shop_ui()


func _close_shop() -> void:
	panel.visible = false
	state = S.PLAY
	Sfx.play("ui_ok", -4.0)


# =====================================================================
# 援护干员
# =====================================================================
const ALLY_SLOTS := [Vector2(-46, -8), Vector2(46, -8), Vector2(0, -52)]


func _update_allies(dt: float) -> void:
	for i in allies.size():
		var al: Dictionary = allies[i]
		var slot: Vector2 = ppos + ALLY_SLOTS[i]
		al.pos = al.pos.lerp(slot, clamp(dt * 5.0, 0.0, 1.0))
		al.cd -= dt
		var lvm: float = pow(1.5, al.lv - 1)
		match al.kind:
			"sniper":
				if al.cd <= 0.0:
					var tgt := _sniper_target(al.pos, 460.0)
					if tgt.is_empty():
						al.cd = 0.2
					else:
						al.cd = 1.0 * pow(0.87, al.lv - 1)
						var d: Vector2 = (tgt.pos - al.pos).normalized()
						bullets.append({"kind": "arrow", "pos": al.pos + Vector2(0, -12), "vel": d * 760.0, "dmg": 20.0 * lvm * dmg_mult, "life": 0.8, "r": 5.0, "aoe": 0.0})
						Sfx.play("swing", -16.0, 1.8)
			"caster":
				if al.cd <= 0.0:
					var ts := _nearest(1, 360.0)
					if ts.is_empty():
						al.cd = 0.2
					else:
						al.cd = 1.5 * pow(0.9, al.lv - 1)
						var d: Vector2 = (ts[0].pos - al.pos).normalized()
						bullets.append({"kind": "orb", "pos": al.pos + Vector2(0, -12), "vel": d * 380.0, "dmg": 14.0 * lvm * dmg_mult, "life": 1.2, "r": 7.0, "aoe": 45.0 + 10.0 * al.lv})
			"medic":
				if al.cd <= 0.0:
					al.cd = 3.0 / (1.0 + 0.25 * (al.lv - 1))
					if hp < max_hp:
						var h: float = max_hp * (0.03 + 0.01 * (al.lv - 1))
						_heal(h)
						_add_text(ppos + Vector2(0, -90), "+%d" % int(h), Color(0.5, 1.0, 0.6), 16)
						fx.append({"kind": "ring", "pos": ppos, "r": 26.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 1.0, 0.6)})
			"support":
				# 辅助：以减速控场为主，伤害只是点缀（每秒一次，最多 12 名）
				var rad: float = _support_radius(al.lv)
				var tick: bool = al.cd <= 0.0
				if tick:
					al.cd = 1.0
				var hits := 0
				for j in _query(ppos, rad + 20.0):
					var e: Dictionary = enemies[j]
					if e.dead or e.pos.distance_to(ppos) > rad:
						continue
					e.slow = 0.2
					if tick and hits < 12:
						hits += 1
						_damage(e, (1.5 + 1.0 * al.lv) * dmg_mult)


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
		b.pos += b.vel * dt
		b.life -= dt
		for j in _query(b.pos, 40.0):
			var e: Dictionary = enemies[j]
			if e.dead or b.pos.distance_to(e.pos) > e.r + b.r:
				continue
			if b.aoe > 0.0:
				for k in _query(b.pos, b.aoe + 20.0):
					var o: Dictionary = enemies[k]
					if not o.dead and o.pos.distance_to(b.pos) < b.aoe + o.r:
						_damage(o, b.dmg)
				fx.append({"kind": "ring", "pos": b.pos, "r": b.aoe, "life": 0.25, "max": 0.25, "col": Color(0.7, 0.55, 1.0)})
				_sparks(b.pos, Vector2.ZERO, Color(0.75, 0.6, 1.0), 6, 180.0)
				Sfx.play("hit", -10.0, 1.3)
			else:
				_damage(e, b.dmg)
				_sparks(b.pos, b.vel, Color(0.9, 1.0, 0.85), 3, 200.0)
			b.life = 0.0
			break


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
		if g.mag or d < pickup:
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
		xp_need = 8.0 + level * 3.0 + floor(level * level * 0.6)
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
	horde_hit = maxf(0.0, horde_hit - dt)
	lvup_delay -= dt
	lvup_show -= dt
	hud_lv_flash = max(0.0, hud_lv_flash - dt * 1.5)
	for f in fx:
		f.life -= dt
		if f.kind == "spark":
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
	panel.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.78))
	var title_col := UI.GOLD if choice_kind in ["relic", "shop"] else UI.CYAN
	panel.draw_rect(Rect2(0, 62, vs.x, 64), Color(0.02, 0.06, 0.09, 0.9))
	panel.draw_line(Vector2(0, 62), Vector2(vs.x, 62), Color(title_col.r, title_col.g, title_col.b, 0.5), 1.0)
	panel.draw_line(Vector2(0, 126), Vector2(vs.x, 126), Color(title_col.r, title_col.g, title_col.b, 0.5), 1.0)
	UI.text(panel, font, Vector2(0, 115), panel_title_text, 28, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var en_label := "RELIC" if choice_kind == "relic" else "LEVEL UP"
	if choice_kind == "shop":
		en_label = "MERCHANT"
	if choices.size() > 0 and choices[0].kind == "module":
		en_label = "MODULE"
	elif choices.size() > 0 and choices[0].kind == "recruit":
		en_label = "RECRUIT"
	var w := font.get_string_size(en_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + en_label.length() * 4.0
	UI.en(panel, font, Vector2(vs.x / 2 - w / 2, 80), en_label, 13, title_col, 4.0)
	if choice_kind == "shop":
		UI.text(panel, font, Vector2(0, vs.y - 50), "点击或按 1–5 购买 · F 刷新（3 源石锭） · Esc 离开", 15, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	else:
		UI.text(panel, font, Vector2(0, vs.y - 50), "点击卡片，或按 1 / 2 / 3 选择", 15, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


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
		card.custom_minimum_size = Vector2(290, 330)
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
		desc.position = Vector2(28, 230)
		desc.size = Vector2(234, 120)
		desc.add_theme_font_size_override("font_size", 16)
		desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.88))
		desc.add_theme_constant_override("line_spacing", 4)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(desc)
		card.set_meta("desc", desc)
		card.set_meta("dy", 230.0)
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
	return {"tag": "技能", "tag_en": "SKILL", "glyph": sk.glyph, "name": sk.name, "desc": sk.desc, "col": sk.col}


func _open_show(sc: Dictionary) -> void:
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
		UI.panel(hud, r, Color(0.03, 0.08, 0.11, 0.95 * e), Color(ic.r, ic.g, ic.b, 0.7 * e), 14.0, ic)
		var gc := r.position + Vector2(70, 84)
		UI.diamond(hud, gc, 46.0, Color(ic.r, ic.g, ic.b, 0.12 * e))
		UI.diamond(hud, gc, 36.0, Color(0.02, 0.06, 0.08, e), Color(ic.r, ic.g, ic.b, e))
		UI.text(hud, font, gc + Vector2(-40, 12), it.glyph, 30, Color(ic.r, ic.g, ic.b, e), HORIZONTAL_ALIGNMENT_CENTER, 80)
		hud.draw_rect(Rect2(r.position + Vector2(140, 24), Vector2(4, 16)), Color(ic.r, ic.g, ic.b, e))
		UI.text(hud, font, r.position + Vector2(152, 38), "新%s" % it.tag, 14, Color(ic.r, ic.g, ic.b, e))
		UI.en(hud, font, r.position + Vector2(206, 37), "NEW  " + it.tag_en, 11, Color(ic.r, ic.g, ic.b, 0.7 * e), 3.0)
		UI.text(hud, font, r.position + Vector2(150, 76), it.name, 26, Color(1, 1, 1, e))
		hud.draw_multiline_string(font, r.position + Vector2(150, 106), it.desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 172, 15, 3, Color(0.78, 0.88, 0.9, e))
	if st > 1.0:
		var ba := 0.5 + 0.5 * sin(st * 4.0)
		UI.text(hud, font, Vector2(0, vs.y - 40), "点击或按任意键继续", 15, Color(0.75, 0.88, 0.92, 0.5 + 0.5 * ba), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func _card_color(o: Dictionary) -> Color:
	match o.kind:
		"relic":
			return UI.CAT_COL.get(D.RELICS[o.id].cat, UI.GOLD)
		"module":
			return UI.PURPLE
		"recruit":
			return Color(0.55, 0.9, 0.55)
		"skill":
			return D.SKILLS[o.id].col
	return UI.CYAN


func _draw_card(card: Button, o: Dictionary, i: int) -> void:
	var hov := card.is_hovered()
	var col := _card_color(o)
	var r := Rect2(Vector2(0, card.get_meta("oy", 0.0)), card.size)
	UI.panel(card, r, Color(0.05, 0.12, 0.16, 0.97) if hov else UI.BG2, col if hov else Color(col.r, col.g, col.b, 0.45), 16.0, col)
	# 顶部分类条
	var cat := "成长  GROWTH"
	if o.kind == "relic":
		cat = D.RELICS[o.id].cat + "  RELIC"
	elif o.kind == "module":
		cat = "模组  MODULE"
	elif o.kind == "recruit":
		cat = "招募  " + D.ALLIES[o.id].en
	elif o.kind == "skill":
		cat = "技能进阶  " + ("I" if o.stage == 1 else "II")
	card.draw_rect(Rect2(r.position + Vector2(16, 22), Vector2(4, 16)), col)
	UI.text(card, font, r.position + Vector2(28, 36), cat, 13, col)
	UI.text(card, font, r.position + Vector2(r.size.x - 44, 38), str(i + 1), 18, Color(col.r, col.g, col.b, 0.6))
	# 图标：菱形 + 名称首字
	var c := r.position + Vector2(r.size.x / 2, 118)
	var pulse := 0.5 + 0.5 * sin(t * 3.0 + i)
	UI.diamond(card, c, 52.0 + (4.0 * pulse if hov else 0.0), Color(col.r, col.g, col.b, 0.12))
	UI.diamond(card, c, 40.0, Color(0.02, 0.06, 0.08), col)
	var name: String = o.name
	var glyph := name.substr(0, 1)
	if o.kind == "relic" or o.kind == "module":
		glyph = D.RELICS[o.id].name.substr(0, 1) if o.kind == "relic" else "模"
	var ic: Texture2D = tex.get("relic_" + o.id) if o.kind == "relic" else null
	if o.kind == "recruit":
		var at: Texture2D = tex["ally_" + o.id]
		var fw := at.get_width() / 2
		var ks: float = floorf(76.0 / at.get_height()) if at.get_height() <= 76 else 76.0 / at.get_height()
		var asz := Vector2(fw, at.get_height()) * ks
		card.draw_texture_rect_region(at, Rect2(c - asz / 2.0, asz), Rect2(0, 0, fw, at.get_height()))
	elif ic != null:
		card.draw_texture_rect(ic, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false)
	else:
		UI.text(card, font, c + Vector2(-40, 13), glyph, 34, col, HORIZONTAL_ALIGNMENT_CENTER, 80)
	# 名称
	var nm := name
	if o.kind == "relic":
		nm = D.RELICS[o.id].name
	UI.text(card, font, r.position + Vector2(0, 208), nm, 21, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	card.draw_line(r.position + Vector2(40, 220), r.position + Vector2(r.size.x - 40, 220), Color(col.r, col.g, col.b, 0.35), 1.0)
	if hov:
		UI.en(card, font, r.position + Vector2(r.size.x / 2 - 30, r.size.y - 18), "SELECT", 12, col, 3.0)


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
	if level >= 20 and elite_stage == 1:
		elite_stage = 2
		var mopts: Array = []
		for mid in D.MODULES:
			mopts.append({"kind": "module", "id": mid, "name": D.MODULES[mid].name, "desc": D.MODULES[mid].desc})
		_show_choices("精英化二：选择模组（同时解锁「镜花水月」）", mopts, "level")
		return
	var pool: Array = []
	for gid in D.GROWTH:
		var g: Dictionary = D.GROWTH[gid]
		var n: int = growth.get(gid, 0)
		if n >= g.max:
			continue
		var nm: String = g.name if g.max > 90 else "%s  %d/%d" % [g.name, n + 1, g.max]
		pool.append({"kind": "growth", "id": gid, "name": nm, "desc": g.desc})
	pool.shuffle()
	var picks := pool.slice(0, 3)
	# 技能进阶卡：每次至多一张，按概率混入
	var adv: Array = []
	for sid in ["s1", "s2", "s3"]:
		var lv: int = skill_lv[sid]
		if lv >= 1 and lv < 3:
			var ad: Dictionary = D.SKILL_ADV[sid][lv - 1]
			if level >= ad.min_lv:
				adv.append({"kind": "skill", "id": sid, "name": "%s · %s" % [D.SKILLS[sid].name, ad.name], "desc": ad.desc, "stage": lv})
	if not adv.is_empty() and rng.randf() < D.SKILL_ADV_CHANCE and picks.size() > 0:
		picks[rng.randi() % picks.size()] = adv[rng.randi() % adv.size()]
	_show_choices("升级！ Lv.%d" % level, picks, "level")


func _open_relic_choice() -> void:
	var pool: Array = []
	for rid in D.RELICS:
		if not relics.has(rid):
			var r: Dictionary = D.RELICS[rid]
			pool.append({"kind": "relic", "id": rid, "name": "【%s】%s" % [r.cat, r.name], "desc": r.desc})
	if pool.is_empty():
		pending_chests = 0
		hp = max_hp
		lamp = 100.0
		_show_banner("藏品已收集齐全：生命与灯火回满")
		return
	pool.shuffle()
	_show_choices("获得藏品", pool.slice(0, 3), "relic")


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
		"module":
			module = o.id
			s3_sp = 30.0
			var gl: String = {"x": "X", "y": "Y", "a": "α"}.get(o.id, "模")
			skill_lv.s3 = 1
			show_queue.append({"head": "精英化二", "en": "ELITE  PROMOTION  II", "col": Color(0.8, 0.55, 1.0), "demo": "s3", "items": [
				_skill_item("s3"),
				{"tag": "模组", "tag_en": "MODULE", "glyph": gl, "name": D.MODULES[o.id].name, "desc": D.MODULES[o.id].desc, "col": UI.GOLD}]})
		"relic":
			relics.append(o.id)
			_apply_relic(o.id)
			_check_combos()
		"skill":
			skill_lv[o.id] += 1
			var sk: Dictionary = D.SKILLS[o.id]
			var ad: Dictionary = D.SKILL_ADV[o.id][o.stage - 1]
			show_queue.append({"head": "技能进阶", "en": "SKILL  ADVANCE  " + ("I" if o.stage == 1 else "II"), "col": sk.col, "demo": o.id, "items": [
				{"tag": "进阶", "tag_en": "ADVANCE " + ("I" if o.stage == 1 else "II"), "glyph": sk.glyph, "name": "%s · %s" % [sk.name, ad.name], "desc": ad.desc, "col": sk.col}]})
	if choice_kind == "relic":
		pending_chests -= 1
	else:
		pending_levelups -= 1
	panel.visible = false
	Sfx.play("ui_ok", -4.0)
	state = S.PLAY
	_check_pending()


func _apply_growth(id: String) -> void:
	match id:
		"u_dmg": u_dmg_mult *= 1.15
		"u_area": u_area_mult *= 1.1
		"u_spd": u_spd_mult *= 0.92
		"t_dmg": t_mult += 0.12
		"sp":
			sp_mult *= 1.15
			s1_need = max(4, s1_need - 1)
		"dodge": dodge += 0.05
		"hp":
			max_hp += 20.0
			hp += 20.0
		"speed": speed *= 1.1
		"pickup": pickup *= 1.3
		"regen": regen += 0.6
		"armor": armor += 1.0
		"wick": lamp_decay *= 0.85


func _apply_relic(id: String) -> void:
	match id:
		"wick_shield": lamp_decay *= 0.75
		"oil_jar":
			lamp = 100.0
			oil_mult *= 1.5
		"backlight": backlight = true
		"ember": ember = true
		"umbrella_rib": rib_bonus += 40.0
		"deep_limb": extra_targets += 1
		"watch": sp_mult *= 1.25
		"scale": dmg_mult *= 1.15
		"jelly_spec": jelly_count = 2
		"conch":
			tide_on = true
			tide_cd = 1.0
		"coral":
			max_hp += 30.0
			hp += 30.0
			regen += 0.5
		"scarf": armor += 2.0
		"bottle":
			pickup *= 1.5
			xp_mult *= 1.15
		"cloak": dodge += 0.1
		"symbiote":
			evo_age = 20.0
			evo_xp = 3.0
		"whisper":
			horde_mult = 1.5
			horde_chest = true
		"seed": seed_heal = true


func _check_combos() -> void:
	for cid in D.COMBOS:
		if combos.has(cid):
			continue
		var c: Dictionary = D.COMBOS[cid]
		var ok := true
		for r in c.req:
			if not relics.has(r):
				ok = false
		if not ok:
			continue
		combos.append(cid)
		_show_banner("组合激活：" + c.name + " —— " + c.desc)
		match cid:
			"deep_light": jelly_lamp = 0.6
			"high_tide":
				tide_every = 2.0
				tide_mult = 1.3
			"drifter":
				speed *= 1.15
				pickup *= 1.3
			"abyss_grip": grip = true
			"tide_of_flesh": flesh_heal = true


# =====================================================================
# 绘制
# =====================================================================
func _update_visuals(dt: float) -> void:
	var bob: float = -abs(sin(walk_t)) * 2.0 if moving else 0.0
	sprite.position = (ppos + Vector2(0, bob + 6)).round()
	sprite.flip_h = facing < 0.0
	_update_player_anim(get_process_delta_time())
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
		draw_texture_rect_region(tx, Rect2(-size * Vector2(1.0 - anchor.x, anchor.y), size), src, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(tx, Rect2((pos - size * anchor).round(), size), src, col)


func _draw() -> void:
	_draw_bg()
	for m in mires:
		_draw_mire(m)
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
	for i in range(afterimg.size() - 1, -1, -1):
		var ai: Dictionary = afterimg[i]
		var aa := 0.45 * (1.0 - float(i) / afterimg.size())
		_draw_player_at(ai.pos + Vector2(0, 6), ai.flip, Color(0.9, 0.55, 1.8, aa), ai.frame, ai.tex, ai.hf)
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
				if atx.get_height() >= 40:
					# 48px 援护（脚底锚点约 (24,45)）
					_spr("ally_" + al.kind, 2, int(t * 3.0 + i) % 2, al.pos + Vector2(0, 16), PX, al.pos.x > ppos.x, Color.WHITE, Vector2(0.5, 45.0 / 48.0))
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
	var jf := int(t * 6.0) % 2
	for p in jelly_pos:
		_spr("jelly", 2, jf, p + Vector2(0, -10))
	for al in allies:
		if al.kind == "support":
			var rad: float = _support_radius(al.lv)
			draw_arc(ppos, rad, 0.0, TAU, 40, Color(0.5, 0.8, 1.0, 0.18 + 0.06 * sin(t * 3.0)), 2.0)
	for b in bullets:
		if b.kind == "arrow":
			var n: Vector2 = b.vel.normalized()
			draw_line(b.pos - n * 14.0, b.pos + n * 4.0, Color(0.95, 1.0, 0.85), 3.0)
			draw_line(b.pos - n * 22.0, b.pos - n * 14.0, Color(0.6, 0.9, 0.6, 0.5), 2.0)
		else:
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
				var fr := clampi(int((1.0 - a) * 4.0), 0, 3)
				draw_set_transform(f.pos, f.ang, Vector2.ONE)
				_spr(f.get("tex", "slash"), 4, fr, Vector2.ZERO, f.scale, false, Color.WHITE if f.get("tex", "slash") != "slash" else f.col)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in ebullets:
		# 2.5D：子弹在离地约 16px 的高度飞行，影子落在判定位置
		draw_set_transform(b.pos + Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, b.r + 1.0, Color(0, 0, 0, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var bp: Vector2 = b.pos + Vector2(0, -16)
		draw_circle(bp, b.r + 4.0, Color(1.0, 0.3, 0.6, 0.25))
		_spr("ebullet", 1, 0, bp, PX * b.r / 5.0)
	for sh in shocks:
		var a: float = 1.0 - sh.r / sh.maxr
		draw_arc(sh.pos, sh.r, 0.0, TAU, 48, Color(0.6, 1.0, 0.7, a), 6.0)
		draw_arc(sh.pos, sh.r - 10.0, 0.0, TAU, 48, Color(0.6, 1.0, 0.7, a * 0.3), 3.0)
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
	var fr := clampi(int(a * 5.0), 0, 4)
	_spr("tentacle", 5, fr, f.pos + Vector2(0, 10), PX, f.flip, Color.WHITE, Vector2(0.5, 1.0))


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


## 大型景物：残柱 / 断墙 / 沉船 / 岩脊 / 海底山，稀疏分布，开局附近留空
const BIGCELL := 700.0
const BIG_PROPS := ["prop_pillar", "prop_pillar", "prop_wall", "prop_wall", "prop_wreck", "terrain_ridge", "terrain_peak"]
func _collect_big_props(vs: Vector2) -> void:
	if tex.get("prop_pillar") == null:
		return
	var x0 := floori((ppos.x - vs.x / 2.0 - 200.0) / BIGCELL)
	var y0 := floori((ppos.y - vs.y / 2.0 - 100.0) / BIGCELL)
	for cx in range(x0, x0 + int(vs.x / BIGCELL) + 3):
		for cy in range(y0, y0 + int(vs.y / BIGCELL) + 3):
			var h: int = abs(hash(Vector2i(cx, cy) + Vector2i(313, 7)))
			if h % 100 > 45:
				continue
			var name: String = BIG_PROPS[(h / 100) % BIG_PROPS.size()]
			if tex.get(name) == null:
				continue
			var p := Vector2(cx * BIGCELL + float((h / 7) % 500) + 100.0, cy * BIGCELL + float((h / 3001) % 500) + 100.0)
			if p.length() < 420.0:
				continue
			sort_props.append([name, p, h])


func _draw_enemy(e: Dictionary) -> void:
	var name: String = e.tex
	# 形态切换：偏执泡影二阶段 / 接潮三件套昏迷时的假死造型
	if e.type == "paranoia" and e.phase == 2 and tex.get("e_paranoia2") != null:
		name = "e_paranoia2"
	elif e.get("coma", false) and tex.get(name + "_feign") != null:
		name = name + "_feign"
	var frame := int(t * (2.0 if e.boss else 5.0) + e.id * 0.37) % 2
	var sc: float = PX * e.r / e.r0
	var col := Color.WHITE
	if e.evo:
		col = Color(1.0, 0.62, 0.68)
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
	draw_off = Vector2(0, -minf(e.kb.length() * 0.03, 14.0))
	var flip: bool = e.fx < 0.0
	var anc := Vector2(0.5, 0.5)
	var bpos: Vector2 = e.pos
	if foot_anchor.has(e.tex):
		anc = Vector2(0.5, 1.0)
		bpos = e.pos + Vector2(0, e.r * 0.8 + 3.0 * PX)
	var k: float = clamp(e.squash / 0.14, 0.0, 1.0)
	var sq := Vector2(1.0 + 0.3 * k, 1.0 - 0.25 * k)
	# 轮廓光：深色怪物在灯光外也能看清（颜色 >1，抵消环境暗色）
	if Cfg.outline and tex.has(name + "_white"):
		var oc := Color(1.6, 2.4, 3.2, 0.55) if not e.elite else Color(3.2, 2.2, 1.0, 0.7)
		for d in [Vector2(PX, 0), Vector2(-PX, 0), Vector2(0, PX), Vector2(0, -PX)]:
			_spr(name + "_white", 2, frame, bpos + d, sc, flip, oc, anc, sq)
	_spr(name, 2, frame, bpos, sc, flip, col, anc, sq)
	if e.flash > 0.0:
		_spr(name + "_white", 2, frame, bpos, sc, flip, Color(1, 1, 1, 0.9), anc, sq)
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


## 技能的地面表现（在角色之下）
func _draw_skill_floor() -> void:
	var P: Dictionary = D.SKILL_P
	var base := ppos + Vector2(0, 6)
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


## 技能的覆盖层表现（在角色之上）
func _draw_skill_over() -> void:
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
func _draw_player() -> void:
	var tx: Texture2D = sprite.texture
	if tx == null:
		return
	var hf := sprite.hframes
	var fw := tx.get_width() / hf
	var fh := tx.get_height()
	var src := Rect2(fw * (sprite.frame % hf), 0, fw, fh)
	var sx := -PX if sprite.flip_h else PX
	draw_set_transform(sprite.position, sprite.rotation, Vector2(sx, PX))
	draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh / 2.0) + sprite.offset, Vector2(fw, fh)), src, sprite.modulate)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_hud() -> void:
	var vs := hud.size
	var ct := get_viewport().get_canvas_transform()
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

	# 受击时屏幕边缘泛红
	if red_flash > 0.0:
		hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.05, 0.1, red_flash * 0.45))
	if hurt_vignette > 0.0:
		_edge_glow(vs, Color(0.9, 0.1, 0.15, hurt_vignette * 0.9), 90.0 + 50.0 * hurt_vignette)
	if state == S.PLAY and hp < max_hp * 0.3 and hp > 0.0:
		var beat := pow(maxf(0.0, sin(t * (5.0 + 5.0 * (1.0 - hp / (max_hp * 0.3))))), 4.0)
		_edge_glow(vs, Color(0.85, 0.05, 0.12, 0.35 + 0.4 * beat), 150.0)
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

	# 顶部经验条
	hud.draw_rect(Rect2(0, 0, vs.x, 4), Color(0, 0, 0, 0.7))
	hud.draw_rect(Rect2(0, 0, vs.x * clamp(xp / xp_need, 0.0, 1.0), 4), UI.CYAN)
	hud.draw_rect(Rect2(0, 4, vs.x * clamp(xp / xp_need, 0.0, 1.0), 2), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.25))

	# 左上：干员信息
	var o := Vector2(16, 16)
	UI.panel(hud, Rect2(o, Vector2(330, 96)), UI.BG, UI.LINE, 12.0, UI.CYAN)
	var lf := hud_lv_flash
	var bc := UI.CYAN.lerp(UI.GOLD, lf)
	UI.diamond(hud, o + Vector2(36, 42), 30.0 + 6.0 * lf, Color(bc.r, bc.g, bc.b, 0.12 + 0.3 * lf))
	UI.diamond(hud, o + Vector2(36, 42), 25.0 + 3.0 * lf, Color(0.03, 0.1, 0.13), bc)
	UI.diamond(hud, o + Vector2(36, 42), 21.0, Color(0, 0, 0, 0), Color(bc.r, bc.g, bc.b, 0.35))
	var lvs := 26 if level < 10 else 22
	UI.text(hud, font, o + Vector2(6, 51 + (1 if level >= 10 else 0)), str(level), int(lvs * (1.0 + 0.35 * lf)), Color(1, 1, 1).lerp(UI.GOLD, lf), HORIZONTAL_ALIGNMENT_CENTER, 60, 4)
	# 菱形下方的 LV 小标签
	hud.draw_rect(Rect2(o + Vector2(23, 62), Vector2(26, 13)), Color(0.02, 0.06, 0.08))
	hud.draw_rect(Rect2(o + Vector2(23, 62), Vector2(26, 13)), bc, false, 1.0)
	UI.en(hud, font, o + Vector2(28, 73), "LV", 9, bc, 2.0)
	UI.text(hud, font, o + Vector2(66, 30), "水月", 18, UI.TEXT)
	UI.en(hud, font, o + Vector2(112, 29), "MIZUKI", 11, UI.CYAN_DIM, 3.0)
	UI.text(hud, font, o + Vector2(250, 29), ["精零", "精英一", "精英二"][elite_stage], 13, UI.GOLD if elite_stage > 0 else UI.SUB)
	UI.en(hud, font, o + Vector2(66, 52), "HP", 10, UI.SUB, 2.0)
	var hs := Vector2(sin(t * 90.0), cos(t * 70.0)) * 3.0 * hp_shake / 0.35
	var hbr := Rect2(o + Vector2(90, 42) + hs, Vector2(170, 10))
	var low := hp / max_hp < 0.3
	hud.draw_rect(Rect2(hbr.position, Vector2(hbr.size.x * clampf(hp_trail / max_hp, 0.0, 1.0), hbr.size.y)), Color(1.0, 0.95, 0.9, 0.85))
	UI.bar(hud, hbr, hp / max_hp, UI.RED.lerp(Color(1, 0.8, 0.8), 0.5 + 0.5 * sin(t * 10.0)) if low else Color(0.35, 0.9, 0.75), 10)
	UI.text(hud, font, o + Vector2(266, 53) + hs, "%d" % int(hp), 14, UI.RED if low else UI.TEXT)
	var lc := UI.GOLD if lamp >= 30.0 else UI.RED.lerp(UI.GOLD, 0.5 + 0.5 * sin(t * 8.0))
	UI.en(hud, font, o + Vector2(66, 78), "LIGHT", 10, lc, 1.0)
	UI.bar(hud, Rect2(o + Vector2(110, 68), Vector2(150, 10)), lamp / 100.0, lc, 5)
	UI.text(hud, font, o + Vector2(266, 79), "灯火 %d" % int(lamp), 13, lc)
	# 神经损伤 / 侵蚀
	if nerve > 1.0:
		UI.en(hud, font, o + Vector2(66, 108), "NERVE", 10, Color(1.0, 0.5, 0.9), 1.0)
		UI.bar(hud, Rect2(o + Vector2(110, 99), Vector2(150, 6)), nerve / 100.0, Color(1.0, 0.45, 0.85))
	if corrode_pool > 0.5:
		UI.text(hud, font, o + Vector2(266, 108), "侵蚀", 12, Color(0.8, 0.5, 1.0))
	if pstun > 0.0:
		UI.text(hud, font, ct * ppos + Vector2(-40, -110), "僵直", 16, Color(1.0, 0.5, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	# 源石锭
	hud.draw_texture_rect(tex.ingot, Rect2(Vector2(vs.x / 2 + 170, 12), Vector2(18, 14)), false)
	UI.text(hud, font, Vector2(vs.x / 2 + 194, 25), str(ingots), 16, Color(1.0, 0.65, 0.35))
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
	if lamp <= 0.0:
		UI.text(hud, font, o + Vector2(4, 132), "灯火熄灭 —— 持续受到伤害", 15, UI.RED, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)
	elif lamp < 30.0:
		UI.text(hud, font, o + Vector2(4, 132), "暗潮涌动 —— 敌人更快、更凶", 15, Color(1, 0.55, 0.45), HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

	# 顶部中央：时间与击杀
	var mm := int(t) / 60
	var ss := int(t) % 60
	UI.rule(hud, Vector2(vs.x / 2 - 150, 22), Vector2(vs.x / 2 - 70, 22), UI.CYAN_DIM)
	UI.rule(hud, Vector2(vs.x / 2 + 70, 22), Vector2(vs.x / 2 + 150, 22), UI.CYAN_DIM)
	UI.text(hud, font, Vector2(vs.x / 2 - 100, 38), "%02d:%02d" % [mm, ss], 30, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 200, 3)
	UI.text(hud, font, Vector2(vs.x / 2 - 100, 62), ("击杀  %d" % kills) + (("  ·  难度 %d" % diff) if diff > 0 else ""), 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 200, 3)

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
		UI.panel(hud, Rect2(bx - 12, 80, bw + 24, 48), UI.BG, Color(0.7, 0.2, 0.4, 0.8), 8.0)
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
	if module != "":
		UI.text(hud, font, Vector2(18, vs.y - 190), D.MODULES[module].name, 14, UI.PURPLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 3)

	# 横幅通知
	if banner_t > 0.0:
		var a: float = clamp(banner_t, 0.0, 1.0)
		var by := vs.y * 0.24
		hud.draw_rect(Rect2(0, by - 30, vs.x, 46), Color(0.01, 0.04, 0.06, 0.8 * a))
		hud.draw_line(Vector2(vs.x * 0.2, by - 30), Vector2(vs.x * 0.8, by - 30), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6 * a), 1.0)
		hud.draw_line(Vector2(vs.x * 0.2, by + 16), Vector2(vs.x * 0.8, by + 16), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6 * a), 1.0)
		UI.text(hud, font, Vector2(0, by), banner, 22, Color(1, 0.93, 0.8, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if t < 8.0 and state == S.PLAY:
		UI.text(hud, font, Vector2(0, vs.y - 60), "WASD 移动 · 攻击全自动 · Tab 属性 · Esc 暂停", 16, Color(0.7, 0.85, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)

	match state:
		S.SHOW:
			_draw_show(vs)
		S.STATS:
			_draw_stats(vs)
		S.PAUSE:
			_draw_result(vs, "暂停", "PAUSED", UI.CYAN, [["继续", "Esc", "resume"], ["设置", "O", "settings"], ["重新开始", "R", "restart"], ["回到标题", "T", "title"]])
		S.DEAD:
			_draw_result(vs, "探索终止", "OPERATION FAILED", UI.RED, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])
		S.WIN:
			_draw_result(vs, "%s · 探索完成" % D.ENDINGS[ending].name, D.ENDINGS[ending].en, UI.GOLD, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])


## 属性面板（Tab / C 打开，游戏暂停）
func _draw_stats(vs: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.8))
	var r := Rect2(70, 50, vs.x - 140, vs.y - 100)
	UI.panel(hud, r, UI.BG2, UI.LINE, 16.0, UI.CYAN)
	UI.text(hud, font, r.position + Vector2(32, 46), "水月", 28, UI.TEXT)
	UI.en(hud, font, r.position + Vector2(100, 44), "MIZUKI  ·  STATUS", 12, UI.CYAN, 3.0)
	UI.text(hud, font, r.position + Vector2(300, 44), "Lv.%d  ·  %s%s  ·  难度 %d「%s」" % [level, ["精零", "精英化一", "精英化二"][elite_stage],
		("  ·  " + D.MODULES[module].name) if module != "" else "", diff, D.DIFFICULTY[diff].name], 15, UI.SUB)
	hud.draw_line(r.position + Vector2(30, 62), Vector2(r.end.x - 30, r.position.y + 62), UI.CYAN_DIM, 1.0)
	var interval := 0.9 * u_spd_mult
	var half: float = minf(180.0, 65.0 + rib_bonus + 15.0 * growth.get("u_area", 0))
	var cols := [
		["生存", [
			["生命", "%d / %d" % [int(hp), int(max_hp)]],
			["生命回复", "%.1f / 秒" % regen],
			["减伤", "%d" % int(armor)],
			["闪避", "%d%%" % int(dodge * 100.0)],
			["移动速度", "%d" % int(speed)],
			["拾取范围", "%d" % int(pickup)],
			["灯火", "%d  ·  消耗 ×%.2f" % [int(lamp), lamp_decay]],
		]],
		["攻击", [
			["伞击伤害", "%d" % int(18.0 * u_dmg_mult * dmg_mult)],
			["全局伤害", "×%.2f" % dmg_mult],
			["挥伞间隔", "%.2f 秒" % max(0.18, interval)],
			["挥砍半径", "%d" % int(70.0 * u_area_mult)],
			["挥砍角度", "%d°" % int(half * 2.0)],
			["触手倍率", "×%.2f" % t_mult],
			["追击目标", "%d" % (1 + extra_targets + (1 if module == "x" else 0))],
			["技力回复", "×%.2f" % sp_mult],
		]],
	]
	for c in cols.size():
		var x := r.position.x + 36 + c * 280
		var y := r.position.y + 100
		UI.text(hud, font, Vector2(x, y), cols[c][0], 17, UI.CYAN)
		y += 32
		for row in cols[c][1]:
			UI.text(hud, font, Vector2(x, y), row[0], 15, UI.SUB)
			UI.text(hud, font, Vector2(x + 110, y), row[1], 15, UI.TEXT)
			y += 28
	# 技能
	var sx := r.position.x + 600
	var sy := r.position.y + 100
	UI.text(hud, font, Vector2(sx, sy), "技能", 17, UI.CYAN)
	sy += 30
	for sid in ["s1", "s2", "s3"]:
		var sk: Dictionary = D.SKILLS[sid]
		var lv: int = skill_lv[sid]
		var col: Color = sk.col if lv >= 1 else Color(0.35, 0.42, 0.46)
		UI.diamond(hud, Vector2(sx + 12, sy - 6), 11.0, Color(0.02, 0.06, 0.08), col)
		UI.text(hud, font, Vector2(sx - 8, sy + 1), sk.glyph, 13, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
		UI.text(hud, font, Vector2(sx + 32, sy), sk.name if lv >= 1 else "%s（Lv.%d 解锁）" % [sk.name, D.SKILL_UNLOCK[sid]], 15, UI.TEXT if lv >= 1 else UI.SUB)
		sy += 24
		for k in 2:
			var ad: Dictionary = D.SKILL_ADV[sid][k]
			var got := lv >= k + 2
			UI.text(hud, font, Vector2(sx + 32, sy), ("◆ " if got else "◇ ") + ad.name, 13, col if got else Color(0.35, 0.42, 0.46))
			sy += 20
		sy += 10
	# 援护 / 成长 / 藏品
	var bx := r.position.x + 880
	var by := r.position.y + 100
	UI.text(hud, font, Vector2(bx, by), "援护干员", 17, UI.CYAN)
	by += 28
	if allies.is_empty():
		UI.text(hud, font, Vector2(bx, by), "暂无", 14, UI.SUB)
		by += 24
	for al in allies:
		UI.text(hud, font, Vector2(bx, by), "%s  Lv.%d" % [D.ALLIES[al.kind].name, al.lv], 14, Color(0.55, 0.9, 0.55))
		by += 22
	by += 14
	UI.text(hud, font, Vector2(bx, by), "成长", 17, UI.CYAN)
	by += 28
	for gid in growth:
		UI.text(hud, font, Vector2(bx, by), "%s  ×%d" % [D.GROWTH[gid].name, growth[gid]], 13, UI.TEXT)
		by += 20
		if by > r.end.y - 70:
			break
	UI.text(hud, font, Vector2(r.position.x, r.end.y - 22), "藏品 %d 件  ·  击杀 %d  ·  源石锭 %d  ·  按 Tab / C / Esc 返回" % [relics.size(), kills, ingots], 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 小地图（左下）：以水月为中心，显示约 1100 范围内的敌人、精英、Boss、宝箱、道具与商人
func _draw_minimap(vs: Vector2) -> void:
	var sz := 164.0
	var o := Vector2(16, vs.y - sz - 16)
	var r := Rect2(o, Vector2(sz, sz))
	UI.panel(hud, r, Color(0.02, 0.06, 0.08, 0.72), UI.LINE, 10.0, UI.CYAN)
	UI.en(hud, font, o + Vector2(10, 16), "MAP", 9, UI.CYAN_DIM, 2.0)
	var c := r.get_center() + Vector2(0, 4)
	var world := 1100.0
	var k := (sz * 0.5 - 12.0) / world
	# 视野框
	var view := get_viewport_rect().size
	hud.draw_rect(Rect2(c - view * 0.5 * k, view * k), Color(0.4, 0.8, 0.9, 0.25), false, 1.0)
	var lim := sz * 0.5 - 8.0
	for e in enemies:
		if e.dead:
			continue
		var p: Vector2 = (e.pos - ppos) * k
		if absf(p.x) > lim or absf(p.y) > lim:
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
		var clipped := absf(mp.x) > lim or absf(mp.y) > lim
		mp = mp.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
		UI.diamond(hud, c + mp, 5.0 + (1.5 * sin(t * 6.0) if clipped else 0.0), UI.GOLD)
	for al in allies:
		hud.draw_circle(c + (al.pos - ppos) * k, 2.0, Color(0.5, 0.9, 1.0))
	UI.diamond(hud, c, 4.0, Color(1, 1, 1))


func _edge_glow(vs: Vector2, col: Color, w: float) -> void:
	var c0 := col
	var c1 := Color(col.r, col.g, col.b, 0.0)
	hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, w), Vector2(0, w)]), PackedColorArray([c0, c0, c1, c1]))
	hud.draw_polygon(PackedVector2Array([Vector2(0, vs.y - w), Vector2(vs.x, vs.y - w), vs, Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
	hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
	hud.draw_polygon(PackedVector2Array([Vector2(vs.x - w, 0), Vector2(vs.x, 0), vs, Vector2(vs.x - w, vs.y)]), PackedColorArray([c1, c0, c0, c1]))


func _draw_relic_tray(tr: Vector2) -> void:
	var n := relics.size()
	var per_row := 9
	var cell := 30.0
	var w: float = min(n, per_row) * cell + 16.0
	var rows := int(ceil(n / float(per_row)))
	UI.en(hud, font, tr + Vector2(-86, 12), "RELICS", 11, UI.SUB, 3.0)
	UI.text(hud, font, tr + Vector2(-126, 13), "%d" % n, 13, UI.GOLD)
	if n == 0:
		return
	var o := tr + Vector2(-w, 20)
	UI.panel(hud, Rect2(o, Vector2(w, rows * cell + 10)), UI.BG, UI.LINE, 6.0)
	for i in n:
		var r: Dictionary = D.RELICS[relics[i]]
		var col: Color = UI.CAT_COL.get(r.cat, UI.GOLD)
		var c := o + Vector2(8 + (i % per_row) * cell + cell / 2, 5 + (i / per_row) * cell + cell / 2)
		var ic: Texture2D = tex.get("relic_" + relics[i])
		if ic != null:
			hud.draw_texture_rect(ic, Rect2(c - Vector2(12, 12), Vector2(24, 24)), false)
		else:
			UI.diamond(hud, c, 12.0, Color(0.03, 0.08, 0.1), col)
			UI.text(hud, font, c + Vector2(-15, 5), r.name.substr(0, 1), 12, col, HORIZONTAL_ALIGNMENT_CENTER, 30)
	var cy := o.y + rows * cell + 28
	for cid in combos:
		UI.text(hud, font, Vector2(tr.x - 300, cy), "◆ " + D.COMBOS[cid].name, 13, Color(1, 0.6, 0.85), HORIZONTAL_ALIGNMENT_RIGHT, 300, 3)
		cy += 20


func _draw_allies_hud(br: Vector2) -> void:
	if allies.is_empty():
		return
	UI.en(hud, font, br + Vector2(-220, -52), "SUPPORT", 11, UI.SUB, 3.0)
	for i in allies.size():
		var al: Dictionary = allies[i]
		var r := Rect2(br + Vector2(-(3 - i) * 76 + 12, -44), Vector2(64, 44))
		UI.panel(hud, r, UI.BG, Color(0.55, 0.9, 0.55, 0.45), 6.0)
		var at: Texture2D = tex["ally_" + al.kind]
		var fw := at.get_width() / 2
		var ks: float = 28.0 / at.get_height() * (1.0 if at.get_height() >= 40 else 1.0)
		ks = 2.0 if at.get_height() < 20 else ks
		hud.draw_texture_rect_region(at, Rect2(r.position + Vector2(18 - fw * ks / 2.0, 34 - at.get_height() * ks), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
		UI.text(hud, font, r.position + Vector2(34, 20), D.ALLIES[al.kind].name.substr(0, 2), 12, UI.TEXT)
		UI.text(hud, font, r.position + Vector2(34, 37), "Lv.%d" % al.lv, 12, Color(0.55, 0.9, 0.55))


func _draw_skills(br: Vector2) -> void:
	var sz := 64.0
	var gap := 12.0
	var items := [
		["唤", "唤醒", skill_lv.s1 >= 1, 0.0, 1.0, float(s1_count) / float(s1_need), UI.GOLD],
		["囚", "囚徒困境", skill_lv.s2 >= 1, s2_active, D.SKILL_P.s2_dur, s2_sp / D.SKILL_P.s2_charge, Color(0.45, 0.8, 1.0)],
		["镜", "镜花水月", skill_lv.s3 >= 1, s3_active, D.SKILL_P.s3_dur, s3_sp / D.SKILL_P.s3_charge, UI.PURPLE],
	]
	for i in 3:
		var it: Array = items[i]
		var pos := br + Vector2(-(3 - i) * (sz + gap) + gap, -sz - 22)
		var r := Rect2(pos, Vector2(sz, sz))
		var col: Color = it[6]
		var unlocked: bool = it[2]
		var active: float = it[3]
		UI.panel(hud, r, UI.BG, col if active > 0.0 else Color(col.r, col.g, col.b, 0.35 if unlocked else 0.15), 8.0)
		if unlocked:
			var frac: float = clamp(it[5], 0.0, 1.0)
			if active > 0.0:
				frac = active / it[4]
			var fh := (sz - 4) * frac
			hud.draw_rect(Rect2(r.position.x + 2, r.end.y - 2 - fh, sz - 4, fh), Color(col.r, col.g, col.b, 0.35 if active > 0.0 else 0.18))
		var gcol: Color = col if unlocked else Color(0.3, 0.38, 0.42)
		if active > 0.0:
			gcol = Color(1, 1, 1)
		var icon: Texture2D = tex.get("skill_s%d" % (i + 1))
		if icon != null:
			hud.draw_texture_rect(icon, Rect2(r.position + Vector2(8, 8), Vector2(sz - 16, sz - 16)), false, Color.WHITE if unlocked else Color(0.3, 0.3, 0.35))
		else:
			UI.text(hud, font, r.position + Vector2(0, 42), it[0], 28, gcol, HORIZONTAL_ALIGNMENT_CENTER, sz)
		UI.text(hud, font, r.position + Vector2(-10, sz + 17), it[1] if unlocked else "未解锁", 12, col if unlocked else Color(0.35, 0.42, 0.46), HORIZONTAL_ALIGNMENT_CENTER, sz + 20)
		if active > 0.0:
			UI.text(hud, font, r.position + Vector2(sz - 26, 16), "%d" % int(ceil(active)), 12, UI.TEXT)
		if i == 0 and unlocked:
			for k in 3:
				UI.diamond(hud, r.position + Vector2(14 + k * 18, sz - 8), 5.0, UI.GOLD if k < s1_charges else Color(0.15, 0.18, 0.2))
		# 进阶等级（右上角两颗小菱形）
		var slv: int = skill_lv["s%d" % (i + 1)]
		if slv >= 1:
			for k in 2:
				UI.diamond(hud, r.position + Vector2(10 + k * 11, 10), 3.5, col if slv >= k + 2 else Color(0.15, 0.18, 0.2))
	UI.en(hud, font, br + Vector2(-3 * (sz + gap) + gap, -sz - 32), "SKILL", 11, UI.SUB, 3.0)


func _draw_result(vs: Vector2, title: String, en_title: String, col: Color, opts: Array) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.72))
	var r := Rect2(vs.x / 2 - 300, vs.y / 2 - 190, 600, 380)
	UI.panel(hud, r, UI.BG2, Color(col.r, col.g, col.b, 0.6), 18.0, col)
	UI.en(hud, font, r.position + Vector2(40, 48), en_title, 13, col, 4.0)
	UI.text(hud, font, r.position + Vector2(40, 96), title, 36, UI.TEXT)
	hud.draw_line(r.position + Vector2(40, 116), r.position + Vector2(r.size.x - 40, 116), Color(col.r, col.g, col.b, 0.4), 1.0)
	var mm := int(t) / 60
	var ss := int(t) % 60
	var stats := [["探索时间", "%02d:%02d" % [mm, ss]], ["等级", "Lv.%d  %s" % [level, ["精零", "精英化一", "精英化二"][elite_stage]]],
		["击杀", str(kills)], ["难度", "%d  %s" % [diff, D.DIFFICULTY[diff].name]]]
	if diff_new and state == S.WIN:
		UI.text(hud, font, Vector2(r.position.x + 300, r.position.y + 96), "解锁难度 %d「%s」" % [diff + 1, D.DIFFICULTY[diff + 1].name], 16, UI.GOLD)
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
		UI.panel(hud, br, Color(0.06, 0.2, 0.24, 0.95) if hov else Color(0.03, 0.1, 0.13, 0.9), col if hov else Color(col.r, col.g, col.b, 0.5), 8.0)
		UI.text(hud, font, br.position + Vector2(14, 27), op[0], 16, UI.TEXT)
		UI.text(hud, font, br.position + Vector2(br.size.x - 34, 27), op[1], 13, col)
		bx += bw + 12
