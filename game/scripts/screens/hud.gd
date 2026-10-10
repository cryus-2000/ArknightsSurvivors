extends RefCounted
## 界面 · 局内 HUD（hud 画布节点的 draw 信号）：按 state 分派到各界面（intro / elite_show / stats_panel / result），HUD 本体按块分派到
## hud_bars（左上 / 顶栏 / Boss 血条 / 状态栏 / 声呐）、hud_relics（右上）、hud_squad（右下编队与手动技能）、hud_banners（提示 / 指示 / 横幅）；
## 本文件留：合批段与分层缓存、底层子画布（飘字 / 暗角）、倒下过渡、共用助手。界面层约定（docs/39 §3）。2026-09-26 从 game.gd 拆出，2026-10-10 拆分（docs/55 §6）。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
const Tris = preload("res://scripts/screens/hud_tris.gd")   # 无贴图图元批（原内部类）
const HudBars = preload("res://scripts/screens/hud_bars.gd")
const HudRelics = preload("res://scripts/screens/hud_relics.gd")
const HudSquad = preload("res://scripts/screens/hud_squad.gd")
const HudBanners = preload("res://scripts/screens/hud_banners.gd")
var bars: HudBars
var relics: HudRelics
var squad: HudSquad
var banners: HudBanners


func _init(game: Game) -> void:
	g = game
	bars = HudBars.new(self)
	relics = HudRelics.new(self)
	squad = HudSquad.new(self)
	banners = HudBanners.new(self)


## HUD 合批段：段内 UI 助手的色块进 Tris 批、文字延后，batch_end 时先一次提交色块再画字（段内各块互不重叠才能这样用）
var _hb: Tris = null

func batch_begin() -> void:
	_hb = Tris.new()
	UI.sink = _hb
	UI.tq = []


## mid：色块之后、文字之前要画的贴图（同贴图连续画才合批）
func batch_end(mid: Array = []) -> void:
	var q: Array = UI.tq
	UI.sink = null
	UI.tq = null
	_hb.flush(g.hud)
	_hb = null
	for f in mid:
		f.call()
	for f in q:
		f.call()


## HUD 分层（性能，docs/50 §9.10）：不每帧变的部分（藏品栏、编队卡的静态部分）和小地图画在 g.hud 下面的子画布上
## （全屏 Control、画在父节点之下 show_behind_parent）。子画布只在「签名」变了时重画，平时 Godot 保留它上次的绘制命令，
## 不再每帧跑 GDScript。重画时把 g.hud 临时指向子画布，原来的绘制函数不用改。本帧走到调用点的层才显示（暂停 / 结算等界面照旧）
var _layers := {}

func _layer(key: String, sig, fn: Callable) -> void:
	var L = _layers.get(key)
	if L == null:
		var node := Control.new()
		node.set_anchors_preset(Control.PRESET_FULL_RECT)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.show_behind_parent = true
		g.hud.add_child(node)
		L = {"node": node, "sig": null, "fn": fn, "used": false}
		_layers[key] = L
		node.draw.connect(func(): _layer_draw(key))
	L.used = true
	L.fn = fn
	if L.sig != sig:
		L.sig = sig
		L.node.queue_redraw()


func _layer_draw(key: String) -> void:
	var L: Dictionary = _layers[key]
	var keep: Control = g.hud
	g.hud = L.node
	L.fn.call()
	g.hud = keep


func draw() -> void:
	for k in _layers:
		_layers[k].used = false
	_draw_body()
	for k in _layers:
		_layers[k].node.visible = _layers[k].used


func _draw_body() -> void:
	var vs := g.hud.size
	g.speed_btn = Rect2()
	var ct := g.hud_ct()
	if g.state == Game.S.OPENING:
		g.intro_screen.draw_opening_hud(vs)
		return
	# 底层（每帧重画的子画布，最先建 → 画在藏品栏 / 编队栏缓存层之下，和原来「先画」的层次一致）：精英标记、飘字、全屏色调与暗角
	_layer("under", Engine.get_process_frames(), func(): _draw_under(vs, ct))
	if g.demo_op != "":
		return   # 图鉴演示：只要伤害数字，不画其余 HUD
	if g.state == Game.S.SHOW:
		# 精英化演出：不画其余 HUD（遮罩只有 86% 不透明，顶栏、编队卡的文字会隐约透出来），只画演出本身
		g.show_screen.draw(vs)
		return
	# 各块的顺序就是绘制层次（2026-10-10 拆分前 _draw_body 的原顺序），别调换
	bars.draw_top_left(vs)
	banners.draw_leader_hints(ct)
	banners.draw_merchant_pointer(vs, ct)
	banners.draw_altar_pointers(vs, ct)
	banners.draw_boss_pointers(vs, ct)
	banners.draw_field_wave(vs)
	banners.draw_beacon_pointers(vs, ct)
	banners.draw_hunt_ring(vs, ct)
	banners.draw_hunt_pointer(vs, ct)
	if not overlay_left():
		# 小地图每 3 帧重画一次（20 次 / 秒；红点 300 个时逐个画是 HUD 里最贵的一块）
		_layer("minimap", [Engine.get_process_frames() / 3, vs], func(): bars.draw_minimap(vs))
	bars.draw_lamp_strip(vs)
	banners.draw_zone_warning(vs)
	bars.draw_top_center(vs)   # 开合批段（顶部中央 + 右上暂停键共用一批）
	relics.draw_right_top(vs)   # 收合批段：这两行必须相邻
	bars.draw_boss_bars(vs)
	squad.draw(vs)
	banners.draw_banner(vs)
	banners.draw_notices(vs)
	banners.draw_open_hints(vs)
	relics.draw_relic_tooltip(vs)
	g.touch.draw_hud(vs)
	if not overlay_left():
		bars.draw_status_bar(vs)
	banners.draw_dash_hint(vs)
	banners.draw_zone_hint(vs)
	squad.draw_manual_aim()
	squad.draw_manual_hint()
	g.boss_intro.draw_hud(vs)   # Boss 登场 / 击破演出：黑边、暗角、名片，压在全部 HUD 之上（screens/boss_intro.gd）
	match g.state:
		Game.S.SHOW:
			g.show_screen.draw(vs)
		Game.S.INTRO:
			g.intro_screen.draw(vs)
		Game.S.STATS:
			g.stats_screen.draw(vs)
		Game.S.PAUSE:
			g.result_screen.draw(vs, "暂停", "PAUSED", UI.CYAN, [["继续", "Esc", "resume"], ["指南", "G", "guide"], ["设置", "O", "settings"], ["重新开始", "R", "restart"], ["回到标题", "T", "title"]])
		Game.S.DEAD:
			if g.state_age < DEATH_T:
				draw_death_transition(vs)
			else:
				if g.trial.active:
					draw_trial_result(vs, false)
				else:
					g.result_screen.draw(vs, "探索终止", "OPERATION FAILED", UI.RED, [["再次探索", "R", "restart"], ["回到标题", "T", "title"]])
				# 结算面板淡入：盖一层和过渡末尾同色的暗幕，0.35 秒退去
				var fa: float = 1.0 - clampf((g.state_age - DEATH_T) / 0.35, 0.0, 1.0)
				if fa > 0.0:
					g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 0.85 * fa))
		Game.S.WIN:
			if g.trial.active:
				draw_trial_result(vs, true)
			else:
				g.result_screen.draw(vs, "%s · 探索完成" % D.ENDINGS[g.ending].name, D.ENDINGS[g.ending].en, g.endg.cur_col().lerp(UI.GOLD, 0.35), [["再次探索", "R", "restart"], ["回到标题", "T", "title"]], true)


## 原 _draw_body 开头那段：精英标记、伤害数字（图鉴演示 / 精英化演出时也画），以及之后的升级字样、全屏闪光 / 溟痕 / 受伤红 / 低血 / 低灯暗角、
## 头顶小血条（演示 / 演出时不画）。挪到底层子画布里画，藏品栏、编队栏缓存层才能照原来的层次压在它们上面（docs/50 §9.10）
func _draw_under(vs: Vector2, ct: Transform2D) -> void:
	draw_elite_marks(ct)
	# 伤害数字（精英化演出期间不画：遮罩只有 86% 不透明，飘字会透出来压在横幅上）
	for f in (g.texts if (g.state != Game.S.SHOW and g.state != Game.S.DEAD) or g.demo_op != "" else []):   # 倒下后不画定格的飘字（会压在「探索终止」上）
		var a: float = clamp(f.life / f.max, 0.0, 1.0)
		# 图鉴演示：主控身上的飘字压淡（斯卡蒂潮汐时成串数字会整块盖住她）
		if g.demo_op != "" and g.ch != null and absf(f.pos.x - g.ch.pos.x) < 36.0 and f.pos.y > g.ch.pos.y - 80.0 and f.pos.y < g.ch.pos.y + 10.0:
			a *= 0.3
		var sp: Vector2 = ct * f.pos
		var pop: float = 1.0 + 0.7 * clamp((f.life - f.max + 0.12) / 0.12, 0.0, 1.0)
		var sz := int(f.size * pop)
		UI.text(g.hud, g.font, sp - Vector2(60, 0), f.text, sz, Color(f.col.r, f.col.g, f.col.b, a), HORIZONTAL_ALIGNMENT_CENTER, 120, 4)

	if g.demo_op != "" or g.state == Game.S.SHOW:
		return
	# 升级字样：弹出放大 -> 轻微上浮 -> 淡出
	if g.lvup_show > 0.0 and g.state == Game.S.PLAY:
		var age := 1.3 - g.lvup_show
		var pop := 1.0 + 0.6 * clampf(1.0 - age / 0.15, 0.0, 1.0)
		if age > 0.15 and age < 0.3:
			pop = 1.0 - 0.1 * sin((age - 0.15) / 0.15 * PI)
		var la := clampf(g.lvup_show / 0.35, 0.0, 1.0)
		var lp: Vector2 = ct * (g.ppos + Vector2(0, -92 - age * 14.0))
		var gold := Color(1.0, 0.86, 0.42, la)
		UI.text(g.hud, g.font, lp - Vector2(150, 0), "LEVEL UP!", int(30 * pop), gold, HORIZONTAL_ALIGNMENT_CENTER, 300, 6)
		UI.text(g.hud, g.font, lp + Vector2(-150, 26), "Lv.%d" % g.level, int(18 * pop), Color(0.85, 1.0, 0.98, la), HORIZONTAL_ALIGNMENT_CENTER, 300, 4)

	if g.flash > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.97, 0.9, g.flash * 0.5))
	# 大群预警与到达演出
	if (g.horde_warn > 0.0 or g.horde_hit > 0.0) and not g.panel.visible:   # 选卡 / 商人面板打开时不画（EA 1.1：升级面板压在「大群来袭」上）
		var hw := g.horde_warn > 0.0
		var pulse := 0.5 + 0.5 * sin(g.t * (10.0 if hw else 4.0))
		var ea := (0.25 + 0.3 * pulse) if hw else g.horde_hit / 1.2 * 0.6
		edge_glow(vs, Color(0.55, 0.15, 0.85, ea), 120.0)
		var age := (3.0 - g.horde_warn) if hw else 3.0 + (1.2 - g.horde_hit)
		var pop := 1.0 + 0.8 * clampf(1.0 - age / 0.2, 0.0, 1.0)
		var ta := 1.0 if hw else clampf(g.horde_hit / 0.6, 0.0, 1.0)
		var cy := vs.y * 0.3
		var jit := Vector2(sin(g.t * 53.0), cos(g.t * 47.0)) * (2.0 if hw else 0.0)
		g.hud.draw_rect(Rect2(0, cy - 62, vs.x, 92), Color(0.05, 0.0, 0.08, 0.55 * ta))
		g.hud.draw_rect(Rect2(0, cy - 62, vs.x, 2), Color(0.8, 0.4, 1.0, 0.8 * ta))
		g.hud.draw_rect(Rect2(0, cy + 28, vs.x, 2), Color(0.8, 0.4, 1.0, 0.8 * ta))
		UI.text(g.hud, g.font, Vector2(0, cy + 14) + jit, "大 群 来 袭" if hw else "海嗣大群 已抵达", int(38 * pop), Color(1.0, 0.75, 1.0, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		if hw:
			UI.en(g.hud, g.font, Vector2(vs.x / 2 - 130, cy - 40), "THE  SWARM  APPROACHES  ·  %d" % int(ceil(g.horde_warn)), 12, Color(0.85, 0.6, 1.0, ta), 3.0)
			# 四周方向警示箭头（向内）
			for j in 12:
				var ang := TAU * j / 12.0
				if absf(angle_difference(ang, g.horde_gap)) < deg_to_rad(40.0):
					continue  # 缺口方向不画箭头：那边没有敌人
				var dir := Vector2.from_angle(ang)
				var c := vs / 2.0
				var ed: Vector2 = c + dir * min(abs((vs.x / 2 - 40) / max(abs(dir.x), 0.01)), abs((vs.y / 2 - 40) / max(abs(dir.y), 0.01)))
				var tip: Vector2 = ed - dir * (10.0 + 8.0 * pulse)
				var sd := dir.orthogonal() * 12.0
				g.hud.draw_colored_polygon(PackedVector2Array([tip, ed + sd, ed - sd]), Color(0.9, 0.5, 1.0, 0.5 + 0.4 * pulse))

	# 屏幕边缘光只留最要紧的一种（EA 1.1：低血红暗角和圈外紫光叠在一起分不清）：生命垂危 > 圈外 > 溟痕 > 灯火低
	var low_hp: bool = g.state == Game.S.PLAY and g.hp < g.max_hp * 0.3 and g.hp > 0.0
	var zone_out: bool = g.zone_state != 0 and g.state == Game.S.PLAY and g.ppos.distance_to(g.zone_c) > g.zone_r
	# 溟痕：屏幕压暗 + 紫色边缘
	if g.in_mire > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.0, 0.06, 0.18 * g.in_mire))
		if not low_hp and not zone_out:
			edge_glow(vs, Color(0.45, 0.1, 0.7, 0.8 * g.in_mire), 130.0)
		if g.in_mire > 0.5 and g.state == Game.S.PLAY:
			UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 + 84), "陷入溟痕：减速、侵蚀", 16, Color(0.85, 0.55, 1.0, g.in_mire), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# Boss 换幕 / 倒下的全屏闪（world.watch_bosses）
	if g.world.scr_flash > 0.0:
		var fk: float = g.world.scr_flash / g.world.scr_flash_max
		var fc: Color = g.world.scr_flash_col
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(fc.r, fc.g, fc.b, 0.28 * fk * fk))
		edge_glow(vs, Color(fc.r, fc.g, fc.b, 0.8 * fk), 120.0)
	# 受击时屏幕边缘泛红
	if g.red_flash > 0.0:
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.05, 0.1, g.red_flash * 0.16))
		edge_glow(vs, Color(0.9, 0.08, 0.12, g.red_flash * 0.9), 70.0)
	g.post.hurt = g.hurt_vignette
	if g.state == Game.S.PLAY and g.hp < g.max_hp * 0.3 and g.hp > 0.0:
		var beat := pow(maxf(0.0, sin(g.t * (5.0 + 5.0 * (1.0 - g.hp / (g.max_hp * 0.3))))), 4.0)
		edge_glow(vs, Color(0.85, 0.05, 0.12, 0.3 + 0.35 * beat), 110.0)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.5 + 110), "生命垂危", 18, Color(1.0, 0.4, 0.45, 0.5 + 0.5 * beat), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
	# 头顶血条：受伤后或低血量时显示
	var pool: float = g.corrode_pool
	if g.state == Game.S.PLAY and (g.head_bar_t > 0.0 or g.hp < g.max_hp * 0.3 or pool > 0.5):
		var hpos: Vector2 = ct * g.ppos + Vector2(-24, -104)
		var ha := clampf(g.head_bar_t / 0.5, 0.0, 1.0) if g.hp >= g.max_hp * 0.3 and pool <= 0.5 else 1.0
		g.hud.draw_rect(Rect2(hpos - Vector2(1, 1), Vector2(50, 7)), Color(0, 0, 0, 0.7 * ha))
		g.hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(g.hp_trail / g.max_hp, 0.0, 1.0), 5)), Color(1, 0.95, 0.9, 0.9 * ha))
		g.hud.draw_rect(Rect2(hpos, Vector2(48 * clampf(g.hp / g.max_hp, 0.0, 1.0), 5)), Color(1.0, 0.3, 0.35, ha) if g.hp < g.max_hp * 0.3 else Color(0.35, 0.95, 0.75, ha))
		corrode_seg(Rect2(hpos, Vector2(48, 5)), ha)
	if g.lamp < 30.0 and g.state == Game.S.PLAY and not low_hp and not zone_out and g.in_mire <= 0.0:
		edge_glow(vs, Color(0.3, 0.0, 0.2, 0.25 + 0.1 * sin(g.t * 3.0)), 140.0)


func draw_trial_result(vs: Vector2, won: bool) -> void:
	g.result_screen.draw(vs, "演练完成" if won else "演练结束", "BOSS TRIAL COMPLETE" if won else "BOSS TRIAL ENDED", UI.CYAN if won else UI.RED,
		[["重新演练", "R", "restart"], ["返回主页", "T", "title"]], false, false)


func edge_glow(vs: Vector2, col: Color, w: float) -> void:
	var c0 := col
	var c1 := Color(col.r, col.g, col.b, 0.0)
	g.hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(vs.x, 0), Vector2(vs.x, w), Vector2(0, w)]), PackedColorArray([c0, c0, c1, c1]))
	g.hud.draw_polygon(PackedVector2Array([Vector2(0, vs.y - w), Vector2(vs.x, vs.y - w), vs, Vector2(0, vs.y)]), PackedColorArray([c1, c1, c0, c0]))
	g.hud.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, vs.y), Vector2(0, vs.y)]), PackedColorArray([c0, c1, c1, c0]))
	g.hud.draw_polygon(PackedVector2Array([Vector2(vs.x - w, 0), Vector2(vs.x, 0), vs, Vector2(vs.x - w, vs.y)]), PackedColorArray([c1, c0, c0, c1]))


## 通用提示卡：贴在格子下方（越界时贴上方 / 左移），图标 + 标题 + 副标题 + 折行说明
func draw_tooltip(vs: Vector2, cr: Rect2, title: String, sub: String, desc: String, icon: String, col: Color, on: CanvasItem = null) -> void:
	var ci: CanvasItem = g.hud if on == null else on
	var w := 340.0
	# 说明按像素宽度折行（旧版按 26 个字硬切，13 号字会超出框）；太长先缩字号，整屏都放不下才截断
	var fd := UI.fit(g.font, desc, w - 28.0, vs.y - 24.0 - 74.0, [13, 12, 11], 3.0)
	var h := 66.0 + float(fd.h) + 12.0
	var pos := Vector2(clampf(cr.position.x, 12.0, vs.x - w - 12.0), cr.end.y + 8)
	if pos.y + h > vs.y - 12.0:
		pos.y = cr.position.y - h - 8
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vs.y - h - 12.0))
	var r := Rect2(pos, Vector2(w, h))
	ci.draw_rect(Rect2(pos + Vector2(2, 2), Vector2(w - 4, h - 4)), Color(0.03, 0.035, 0.045, 0.96))
	UI.frame(ci, r, col)
	var tx0 := 14.0
	var ic: Texture2D = g.tex.get(icon) if icon != "" else null
	if ic != null:
		ci.draw_texture_rect(ic, Rect2(pos + Vector2(12, 12), Vector2(40, 40)), false)
		tx0 = 62.0
	UI.text_fit(ci, g.font, pos + Vector2(tx0, 28), title, 16, Color.WHITE, w - tx0 - 12.0, 12)
	UI.text_fit(ci, g.font, pos + Vector2(tx0, 48), sub, 12, col, w - tx0 - 12.0, 10)
	UI.draw_fit(ci, g.font, pos + Vector2(14, 62), fd, Color(0.85, 0.92, 0.95))


## 精英标识（docs/48 P1 / 全局 ⑤）：原来只靠金色描边和脚下 alpha 0.12 的光晕，被灯光压暗、和友方金色撞色，
## 关掉「怪物轮廓光」就完全认不出。改在 HUD 层（不受光照）画：头顶一个橙红下箭头 + 3px 血条，不受轮廓光开关影响
const ELITE_COL := Color(1.0, 0.42, 0.25)

func draw_elite_marks(ct: Transform2D) -> void:
	if g.demo_op != "" or g.state == Game.S.SHOW:
		return
	var vs := g.hud.size
	var tb := Tris.new()   # 血条 + 三角一批提交（原来每只 4 次绘制调用）
	for e in g.enemies:
		if e.dead or not e.elite or e.boss or e.get("under", false):
			continue
		var sp: Vector2 = ct * (e.pos + Vector2(0, -e.r - 14.0))
		if sp.x < -40 or sp.y < -40 or sp.x > vs.x + 40 or sp.y > vs.y + 40:
			continue
		var w: float = maxf(24.0, e.r * 1.4)
		tb.rect(Rect2(sp + Vector2(-w / 2.0 - 1.0, -1.0), Vector2(w + 2.0, 5)), Color(0, 0, 0, 0.7))
		tb.rect(Rect2(sp + Vector2(-w / 2.0, 0), Vector2(w * clampf(e.hp / e.maxhp, 0.0, 1.0), 3)), ELITE_COL)
		var tip: Vector2 = sp + Vector2(0, -4)
		var bob: float = 2.0 * sin(g.t * 5.0 + e.id)
		var tri := PackedVector2Array([tip + Vector2(-6, -10 + bob), tip + Vector2(6, -10 + bob), tip + Vector2(0, -3 + bob)])
		tb.poly(PackedVector2Array([tri[0] + Vector2(-2, -1), tri[1] + Vector2(2, -1), tri[2] + Vector2(0, 2)]), Color(0, 0, 0, 0.7))
		tb.poly(tri, ELITE_COL)
	tb.flush(g.hud)


## 主控倒下后的过渡（2026-09-27 用户：结算弹得太快）：画面定格在倒下那一刻，约 1.7 秒——
## 0–1.2 秒灯火熄灭（world 里灯光半径收到 0）、画面沉进深海色（整屏压暗 + 海水青黑暗角从四周合拢）；
## 0.7 秒起「探索终止」浮出（中文大字 + 英文 + 洋红细线从中间向两边展开）；1.7 秒后结算面板淡入。任意键 / 点击跳过（game.gd）
const DEATH_T := 1.7

func draw_death_transition(vs: Vector2) -> void:
	var k: float = clampf(g.state_age / DEATH_LAMP_T, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 2.0)
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 0.62 * e))
	# 海水色暗角：四条边往里渐隐的青黑带，越来越厚
	var band: float = lerpf(0.0, minf(vs.x, vs.y) * 0.42, e)
	for i in 10:
		var f: float = float(i) / 10.0
		var w: float = band * (1.0 - f)
		var c := Color(0.0, 0.07, 0.09, 0.09 * e)
		g.hud.draw_rect(Rect2(0, 0, vs.x, w), c)
		g.hud.draw_rect(Rect2(0, vs.y - w, vs.x, w), c)
		g.hud.draw_rect(Rect2(0, 0, w, vs.y), c)
		g.hud.draw_rect(Rect2(vs.x - w, 0, w, vs.y), c)
	# 标题
	var ta: float = clampf((g.state_age - 0.7) / 0.5, 0.0, 1.0)
	if ta > 0.0:
		var cy: float = vs.y * 0.42
		var lw: float = 260.0 * (1.0 - pow(1.0 - ta, 3.0))
		g.hud.draw_rect(Rect2(vs.x / 2.0 - lw, cy + 14, lw * 2.0, 1), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.8 * ta))
		UI.text(g.hud, g.font, Vector2(0, cy - 4.0 + 8.0 * (1.0 - ta)), "探索终止", 40, Color(1, 1, 1, ta), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 6)
		var en := "OPERATION  FAILED"
		UI.en(g.hud, g.font, Vector2(vs.x / 2.0 - g.font.get_string_size(en, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x / 2.0 - 20.0, cy + 40), en, 13, Color(UI.RED.r, UI.RED.g, UI.RED.b, ta), 4.0)
	# 右下角小字：可跳过
	if g.state_age > 0.3:
		UI.text(g.hud, g.font, Vector2(vs.x - 240, vs.y - 24), "点击跳过" if Pad.touch_ui() else "点击或按任意键跳过", 12, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_RIGHT, 220)


## 侵蚀待扣段（2026-09-27 协调人 / 数值）：侵蚀池 g.corrode_pool 里还没流出的量，画在血条当前值的末端往左、
## 长度 = min(侵蚀池, 当前生命)——这一截血「已经注定要掉」；暗紫底 + 洋红斜纹，斜纹缓缓右移、微微呼吸，随流出缩短，净化后消失
const CORRODE_COL := Color(0.62, 0.16, 0.72)
const CORRODE_HI := Color(1.0, 0.36, 0.86)

func corrode_seg(r: Rect2, a: float) -> void:
	var pool: float = minf(g.corrode_pool, g.hp)
	if pool <= 0.0 or g.max_hp <= 0.0:
		return
	var x1: float = r.position.x + r.size.x * clampf(g.hp / g.max_hp, 0.0, 1.0)
	var x0: float = maxf(r.position.x, x1 - r.size.x * pool / g.max_hp)
	if x1 - x0 < 1.0:
		x0 = x1 - 1.0   # 太少也留 1 像素，看得出「有」
	var y0: float = r.position.y
	var h: float = r.size.y
	var br: float = 0.8 + 0.2 * sin(g.t * 6.0)
	var tb: Tris = _hb if _hb != null else Tris.new()   # 左上面板里画时并进面板的批；头顶小条自己一批
	tb.rect(Rect2(x0, y0, x1 - x0, h), Color(CORRODE_COL.r, CORRODE_COL.g, CORRODE_COL.b, 0.95 * a))
	# 斜纹：每 4 像素一道，左下到右上；两端按段落裁切
	var ph: float = fmod(g.t * 6.0, 4.0)
	var sx: float = x0 - h - 4.0 + ph
	var hc := Color(CORRODE_HI.r, CORRODE_HI.g, CORRODE_HI.b, br * a)
	while sx < x1:
		var ax: float = sx
		var ay: float = y0 + h
		var bx: float = sx + h
		var by: float = y0
		if ax < x0:
			ay -= x0 - ax
			ax = x0
		if bx > x1:
			by += bx - x1
			bx = x1
		if bx > ax:
			tb.line(Vector2(ax, ay), Vector2(bx, by), hc, 1.2)
		sx += 4.0
	# 左端一道亮边：流失到这里为止
	tb.rect(Rect2(x0, y0 - 1, 1, h + 2), Color(CORRODE_HI.r, CORRODE_HI.g, CORRODE_HI.b, 0.9 * a))
	if tb != _hb:
		tb.flush(g.hud)


## 倒下过渡里灯火熄灭的时刻（灯光半径收到 0；音频 music_director 在这一刻播「灯灭」，引用本常量）
const DEATH_LAMP_T := 1.2


## 商人 / 事件界面把左半屏占满：这时不画声呐和状态小牌，免得从面板边上露出来
func overlay_left() -> bool:
	return g.state == Game.S.SHOP or (g.state == Game.S.CHOICE and g.choice_kind == "event")
