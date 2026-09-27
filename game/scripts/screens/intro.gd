extends RefCounted
## 界面 · 开场与教程：开局镜头演出（state OPENING）与其 HUD、新手教程分页（state INTRO）的打开 / 翻页 / 关闭 / 绘制。
## 界面层约定（docs/39 §3）：只读 game.gd 状态、只画自己的界面；改状态走 game.gd / run/ 的函数。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var opening_t := 0.0             # 开场动画时间
const OPENING_DUR := 3.6


func _init(game: Game) -> void:
	g = game


func prev_page() -> void:
	if g.intro_page > 0:
		g.intro_page -= 1
		g.intro_t = 0.0
		Sfx.play("ui_move")


## 开场动画：水月自海面沉降落地 → 灯火点亮 → 标题卡；任意键跳过，之后进入指南
func start_opening() -> void:
	g.state = Game.S.OPENING
	opening_t = 0.0
	g.p_off = Vector2(0, -320)
	g.lamp_light.energy = 0.0
	Sfx.play("start", -14.0)   # 音量巡检：开场引子开头近乎无声，-4 dB 时比音乐响 29 dB；现在只托住开头，和 1.7 秒后的引子齐平


func update_opening(dt: float) -> void:
	opening_t += dt
	var k1 := clampf(opening_t / 1.7, 0.0, 1.0)
	var ease_in := 1.0 - pow(1.0 - k1, 2.2)
	g.p_off = Vector2(sin(opening_t * 3.0) * 6.0 * (1.0 - k1), -320.0 * (1.0 - ease_in))
	g.p_lean = sin(opening_t * 2.0) * 0.08 * (1.0 - k1)
	g.p_sq = Vector2(1.0 - 0.06 * (1.0 - k1), 1.0 + 0.1 * (1.0 - k1))
	# 上升的气泡
	if k1 < 1.0 and randf() < 0.6:
		g.fx.append({"kind": "spark", "pos": g.ppos + g.p_off + Vector2(randf_range(-22, 22), randf_range(-40, 10)), "vel": Vector2(randf_range(-8, 8), -randf_range(40, 90)), "sz": randf_range(2.0, 3.5), "life": 1.1, "max": 1.1, "col": Color(0.8, 0.95, 1.0, 0.7)})
	# 落地
	if opening_t >= 1.7 and opening_t - dt < 1.7:
		g.p_sq = Vector2(1.3, 0.72)
		g.world.feet_dust(14, 150.0)
		g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, 6), "r": 60.0, "life": 0.45, "max": 0.45, "col": Color(0.6, 0.85, 1.0)})
		g.vfx.shake_screen(0.7)
		Sfx.play("boom", -14.0, 1.4, 0.0)
	if opening_t >= 1.7:
		g.p_sq = g.p_sq.lerp(Vector2.ONE, 1.0 - exp(-dt * 10.0))
		g.p_lean = lerpf(g.p_lean, 0.0, 1.0 - exp(-dt * 10.0))
	# 灯火点亮：2.1s 起，先闪两下再稳定
	if opening_t >= 2.1:
		var k2 := clampf((opening_t - 2.1) / 0.8, 0.0, 1.0)
		var fl := 1.0 if k2 > 0.5 else (1.0 if fmod(k2, 0.2) < 0.1 else 0.25)
		g.lamp_light.energy = 1.15 * k2 * fl
		if opening_t - dt < 2.1:
			Sfx.play("oil", -8.0, 1.2, 0.0)
			g.fx.append({"kind": "rays", "pos": g.ppos + Vector2(0, -20), "life": 0.8, "max": 0.8, "col": Color(1.0, 0.85, 0.5)})
	g.vfx.update(dt)
	if opening_t >= OPENING_DUR:
		end_opening()


func end_opening() -> void:
	if g.state != Game.S.OPENING:
		return
	g.p_off = Vector2.ZERO
	g.p_sq = Vector2.ONE
	g.p_lean = 0.0
	g.lamp_light.energy = 1.15
	g.state = Game.S.PLAY
	open(Game.S.PLAY)


func draw_opening_hud(vs: Vector2) -> void:
	# 黑场渐亮 + 上下黑边 + 标题卡
	var dark: float = clampf(1.0 - opening_t / 1.2, 0.0, 1.0) * 0.9 + 0.1
	if opening_t > 2.9:
		dark = lerpf(0.1, 0.0, clampf((opening_t - 2.9) / 0.7, 0.0, 1.0))
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.03, dark))
	var bar: float = 70.0 * (1.0 - clampf((opening_t - 2.9) / 0.7, 0.0, 1.0))
	g.hud.draw_rect(Rect2(0, 0, vs.x, bar), Color(0, 0, 0, 0.95))
	g.hud.draw_rect(Rect2(0, vs.y - bar, vs.x, bar), Color(0, 0, 0, 0.95))
	if opening_t > 0.4 and opening_t < 3.3:
		var a: float = clampf((opening_t - 0.4) / 0.6, 0.0, 1.0) * clampf((3.3 - opening_t) / 0.5, 0.0, 1.0)
		# 英文行按开局干员（data/characters 的 en），按字宽 + 字距居中
		var ens: String = "OPERATION  %s" % String(g.ch.def.get("en", "MIZUKI")).to_upper()
		var enw := -5.0
		for ch in ens:
			enw += UI.cond(g.font).get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 5.0   # 同 UI.en 的逐字排法
		UI.en(g.hud, g.font, Vector2(vs.x / 2 - enw / 2.0, vs.y * 0.22), ens, 13, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, a), 5.0)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.22 + 44), "%s  ·  深海探索" % g.ch.display_name(), 34, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 4)
		UI.text(g.hud, g.font, Vector2(0, vs.y * 0.22 + 74), "灯火未熄，便还能走下去", 14, Color(0.7, 0.85, 0.9, a * 0.9), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 3)
	UI.text(g.hud, g.font, Vector2(0, vs.y - 26), "任意键跳过", 12, Color(0.5, 0.6, 0.65, 0.7), HORIZONTAL_ALIGNMENT_CENTER, vs.x, 2)


func open(back: int) -> void:
	g.intro_back = back
	g.intro_page = 0
	g.intro_t = 0.0
	g.state = Game.S.INTRO


func next_page() -> void:
	Sfx.play("ui_move")
	if g.intro_page < Game.INTRO_PAGES.size() - 1:
		g.intro_page += 1
		g.intro_t = 0.0
	else:
		close()


func close() -> void:
	Cfg.seen_intro = true
	Cfg.save()
	g.state = g.intro_back
	Sfx.play("ui_ok", -4.0)


func draw(vs: Vector2) -> void:
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.88))
	var pg: Dictionary = Game.INTRO_PAGES[g.intro_page]
	var rh: float = minf(570.0, vs.y - 16.0)
	var r := Rect2(vs.x / 2 - 450, vs.y / 2 - rh / 2.0, 900, rh)
	var ea := clampf(g.intro_t / 0.25, 0.0, 1.0)
	r.position.y += (1.0 - ea) * 20.0
	UI.panel(g.hud, r, UI.BG2, UI.LINE, 16.0, UI.CYAN)
	UI.en(g.hud, g.font, r.position + Vector2(40, 46), "GUIDE  %d / %d  ·  %s" % [g.intro_page + 1, Game.INTRO_PAGES.size(), pg.en], 12, UI.CYAN, 3.0)
	UI.text(g.hud, g.font, r.position + Vector2(40, 90), pg.title, 30, UI.TEXT)
	g.hud.draw_line(r.position + Vector2(40, 108), r.position + Vector2(r.size.x - 40, 108), UI.CYAN_DIM, 1.0)
	# 插图区
	var ic := r.position + Vector2(170, 270)
	draw_icon(pg.icon, ic)
	# 文字：按实际折行高度一段接一段排（旧版每段固定 100 像素、最多 4 行，一页 4 段时会压到按钮）；
	# 整页放不下先缩字号（15 → 12）
	var tx := r.position.x + 356
	var tw := r.size.x - 392
	var top := r.position.y + 142
	var avail := r.end.y - 62.0 - top
	var fsz := 15
	var paras: Array = []
	while true:
		paras.clear()
		var tot := 0.0
		for ln in pg.lines:
			var ls: PackedStringArray = UI.wrap_lines(g.font, ln, fsz, tw)
			paras.append(ls)
			tot += ls.size() * (g.font.get_height(fsz) + 1.0) + 14.0
		if tot - 14.0 <= avail or fsz <= 12:
			break
		fsz -= 1
	var lhh: float = g.font.get_height(fsz) + 1.0
	var asc: float = g.font.get_ascent(fsz)
	var y := top
	for ls in paras:
		UI.diamond(g.hud, Vector2(r.position.x + 340, y + asc - 6), 4.0, UI.CYAN)
		for ln2 in ls:
			if y + lhh > r.end.y - 58.0:
				break
			g.hud.draw_string(g.font, Vector2(tx, y + asc), ln2, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, Color(0.85, 0.93, 0.95, ea))
			y += lhh
		y += 14.0
	# 页码点（可点击）
	g.intro_panel = r
	g.intro_dots.clear()
	var mp: Vector2 = g.hud.get_local_mouse_position()
	for i in Game.INTRO_PAGES.size():
		var dp := Vector2(vs.x / 2 - (Game.INTRO_PAGES.size() - 1) * 13 + i * 26, r.end.y - 30)
		var dr := Rect2(dp - Vector2(12, 12), Vector2(24, 24))
		g.intro_dots.append([dr, i])
		var hov: bool = dr.has_point(mp)
		UI.diamond(g.hud, dp, 6.0 if hov else 5.0, UI.CYAN if i == g.intro_page else (Color(0.3, 0.5, 0.55) if hov else Color(0.15, 0.25, 0.28)))
	# 上一页 / 跳过 / 下一页 按钮
	var btns: Array = [["‹ 上一页", "prev"], [Pad.hint("跳过  Esc", "跳过  Ⓑ"), "skip"], ["下一页 ›", "next"]]
	for k in 3:
		var bw := 118.0
		var bx: float = [r.position.x + 40, vs.x / 2 - bw / 2.0, r.end.x - 40 - bw][k]
		var br := Rect2(bx, r.end.y - 52, bw, 34)
		match k:
			0: g.intro_btn_prev = br
			1: g.intro_btn_skip = br
			2: g.intro_btn_next = br
		var hov2: bool = br.has_point(mp)
		var dim: bool = k == 0 and g.intro_page == 0
		if k == 1:
			br.position.y = r.end.y + 16
			g.intro_btn_skip = br
			UI.text(g.hud, g.font, br.position + Vector2(0, 22), btns[k][0], 13, UI.CYAN if hov2 else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
			continue
		UI.frame(g.hud, br, UI.CYAN, {"cut": 6.0, "bracket": 6.0, "glow": 1.0 if hov2 else 0.0, "alpha": 0.3 if dim else (1.0 if hov2 else 0.7)})
		UI.text(g.hud, g.font, br.position + Vector2(0, 23), btns[k][0] if k != 2 or g.intro_page < Game.INTRO_PAGES.size() - 1 else "开始探索 ›", 14, UI.TEXT if not dim else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, br.size.x)
	UI.text(g.hud, g.font, Vector2(r.position.x, r.end.y + 60), Pad.hint("左键 / 任意键：下一页　　右键 / ←：上一页　　点面板左侧也可回退", "Ⓐ / → / RB：下一页　　← / LB：上一页　　Ⓑ：跳过"), 12, Color(0.45, 0.55, 0.6), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func draw_icon(kind: String, c: Vector2) -> void:
	match kind:
		"mizuki":
			# 开局干员的攻击动作（水月沿用 48px 挥伞条）
			var tx: Texture2D = g.tex.get("player_attack_48") if g.ch.id == "mizuki" else g.ch.anim_tex("attack")
			if tx != null:
				var fh0 := tx.get_height()
				var fr := int(g.intro_t * 8.0) % maxi(1, tx.get_width() / fh0)
				g.hud.draw_texture_rect_region(tx, Rect2(c - Vector2(96, 150), Vector2(192, 192)), Rect2(fh0 * fr, 0, fh0, fh0))
			for k in 3:
				var et: Texture2D = g.tex.get(["e_bone", "e_slider", "e_stone"][k])
				if et != null:
					var fw := et.get_width() / 2
					g.hud.draw_texture_rect_region(et, Rect2(c + Vector2(-110 + k * 90, 70), Vector2(fw, et.get_height()) * 2.0), Rect2(0, 0, fw, et.get_height()))
		"bars":
			UI.en(g.hud, g.font, c + Vector2(-110, -60), "HP", 12, UI.SUB, 2.0)
			UI.bar(g.hud, Rect2(c + Vector2(-80, -72), Vector2(180, 14)), 0.7, Color(0.35, 0.9, 0.75), 10)
			UI.en(g.hud, g.font, c + Vector2(-110, -10), "LIGHT", 12, UI.GOLD, 1.0)
			UI.bar(g.hud, Rect2(c + Vector2(-50, -22), Vector2(150, 14)), 0.55, UI.GOLD, 5)
			for tv in [30.0, 70.0]:
				var tx2: float = c.x - 50 + 150 * tv / 100.0
				g.hud.draw_line(Vector2(tx2, c.y - 26), Vector2(tx2, c.y - 4), Color(1, 1, 1, 0.8), 1.5)
			var ot: Texture2D = g.tex.get("oil")
			if ot != null:
				g.hud.draw_texture_rect(ot, Rect2(c + Vector2(-20, 30), Vector2(36, 48)), false)
			UI.text(g.hud, g.font, c + Vector2(26, 64), "灯油", 14, UI.GOLD)
		"mire":
			var mt: Texture2D = g.tex.get("terrain_mire")
			if mt != null:
				var fw := mt.get_width() / 2
				g.hud.draw_texture_rect_region(mt, Rect2(c - Vector2(80, 110), Vector2(160, 160)), Rect2(fw * (int(g.intro_t * 2.0) % 2), 0, fw, mt.get_height()))
			g.hud.draw_arc(c + Vector2(0, 40), 140.0, PI * 1.1, PI * 1.9, 32, Color(0.85, 0.4, 1.0), 3.0)
			UI.text(g.hud, g.font, c + Vector2(-60, 110), "黑潮边界", 14, Color(0.85, 0.5, 1.0))
		"cards":
			# 三张示意卡：开局干员的待机帧（成长）/ 另一名干员的待机帧（招募）/ 被动图标
			var other_id := ""
			for cid0 in Character.list_ids():
				if cid0 != g.ch.id and Character.load_def(cid0).get("recruitable", true):
					other_id = cid0
					break
			for k in 3:
				var rc := Rect2(c + Vector2(-130 + k * 88, -90), Vector2(76, 110))
				var cc: Color = [UI.CYAN, Color(0.55, 0.95, 1.0), UI.GOLD][k]
				UI.panel(g.hud, rc, Color(0.03, 0.08, 0.1), cc, 6.0)
				var cc0 := rc.position + Vector2(rc.size.x / 2.0, 48)
				if k < 2:
					var idl: Dictionary = g.panel_ui.op_idle(g.ch.id if k == 0 else other_id)
					if not idl.is_empty():
						var ks: float = 1.5 if idl.fh <= 48 else 72.0 / idl.fh
						var asz := Vector2(idl.fw, idl.fh) * ks
						g.hud.draw_texture_rect_region(idl.tex, Rect2(cc0 - asz / 2.0 + Vector2(0, 4), asz), Rect2(0, 0, idl.fw, idl.fh))
				else:
					var gt: Texture2D = g.tex.get("growth_hp")
					if gt != null:
						g.hud.draw_texture_rect(gt, Rect2(cc0 - Vector2(24, 24), Vector2(48, 48)), false)
				UI.text(g.hud, g.font, rc.position + Vector2(0, 100), ["成长", "招募", "被动"][k], 12, cc, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
			UI.text(g.hud, g.font, c + Vector2(-130, 60), "干员成长 / 招募 / 博士被动", 14, UI.SUB)
		"loot":
			var items := ["ingot", "e_chest", "pickup_magnet", "pickup_heal", "merchant"]
			for k in items.size():
				var tx3: Texture2D = g.tex.get(items[k])
				if tx3 == null:
					continue
				var frames := 2 if items[k] == "e_chest" or items[k] == "merchant" else 1
				var fw := tx3.get_width() / frames
				var sc: float = 3.0 if tx3.get_height() < 20 else 2.0
				var sz := Vector2(fw, tx3.get_height()) * sc
				var p := c + Vector2(-120 + (k % 3) * 100, -70 + (k / 3) * 100)
				g.hud.draw_texture_rect_region(tx3, Rect2(p - sz / 2.0, sz), Rect2(0, 0, fw, tx3.get_height()))
		"threat":
			# 威胁等级条 Ⅰ–Ⅵ + 大群预警环
			var names := ["浅滩", "暗流", "深潜", "裂隙", "深渊", "深蓝之树"]
			var lit: int = int(g.intro_t * 1.2) % 7
			for k in 6:
				var rc := Rect2(c + Vector2(-138 + k * 46, -96), Vector2(40, 14))
				var on: bool = k < lit
				g.hud.draw_rect(rc, Color(0.6, 0.35, 1.0, 0.9) if on else Color(0.08, 0.12, 0.16))
				g.hud.draw_rect(rc, Color(0.7, 0.5, 1.0, 0.8), false, 1.0)
				UI.text(g.hud, g.font, rc.position + Vector2(0, -6), ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ"][k], 11, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x)
				UI.text(g.hud, g.font, rc.position + Vector2(-8, 30), names[k], 10, UI.TEXT if on else UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, rc.size.x + 16)
			var hk: float = fmod(g.intro_t, 2.4) / 2.4
			g.hud.draw_arc(c + Vector2(0, 30), 30.0 + hk * 90.0, 0.0, TAU, 48, Color(0.75, 0.3, 1.0, 0.7 * (1.0 - hk)), 3.0)
			g.hud.draw_arc(c + Vector2(0, 30), 36.0, 0.0, TAU, 32, Color(0.75, 0.3, 1.0, 0.5), 2.0)
			var etx: Texture2D = g.tex.get("e_bone")
			if etx != null:
				for k in 8:
					var an: float = TAU * k / 8.0 + g.intro_t * 0.4
					var fw2: int = etx.get_width() / 2
					var pp: Vector2 = c + Vector2(0, 30) + Vector2.from_angle(an) * (78.0 - 30.0 * hk)
					g.hud.draw_texture_rect_region(etx, Rect2(pp - Vector2(fw2, etx.get_height()), Vector2(fw2, etx.get_height()) * 2.0), Rect2(0, 0, fw2, etx.get_height()))
			UI.text(g.hud, g.font, c + Vector2(-60, 116), "大群来袭", 14, Color(0.85, 0.6, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 120)
		"merchant":
			var mtx: Texture2D = g.tex.get("merchant")
			if mtx != null:
				var fw3: int = mtx.get_width() / 2
				var fr3: int = int(g.intro_t * 2.0) % 2
				var sz3 := Vector2(fw3, mtx.get_height()) * 3.0
				g.hud.draw_texture_rect_region(mtx, Rect2(c - Vector2(sz3.x / 2.0, sz3.y - 40), sz3), Rect2(fw3 * fr3, 0, fw3, mtx.get_height()))
			var left: int = 60 - int(fmod(g.intro_t * 6.0, 60.0))
			var mc: Color = UI.GOLD if left > 15 else UI.GOLD.lerp(UI.RED, 0.5 + 0.5 * sin(g.intro_t * 8.0))
			UI.ring(g.hud, c + Vector2(0, -120), 22.0, left / 60.0, mc)
			UI.text(g.hud, g.font, c + Vector2(-30, -114), "%ds" % left, 15, mc, HORIZONTAL_ALIGNMENT_CENTER, 60)
			UI.text(g.hud, g.font, c + Vector2(-80, 74), "商人  ·  停留 60 秒", 14, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, 160)
			for k in 3:
				UI.chip(g.hud, g.font, c + Vector2(-118 + k * 84, 90), ["2:00", "5:00", "8:00"][k], UI.GOLD, 12)
		"altar":
			var atx: Texture2D = g.tex.get("e_event")
			if atx != null:
				var fw4: int = atx.get_width() / 2
				var fr4: int = int(g.intro_t * 2.0) % 2
				var sz4 := Vector2(fw4, atx.get_height()) * 4.0
				g.hud.draw_set_transform(c + Vector2(0, 46), 0.0, Vector2(1.0, 0.45))
				g.hud.draw_circle(Vector2.ZERO, 70.0 + 6.0 * sin(g.intro_t * 3.0), Color(0.3, 0.6, 1.4, 0.18))
				g.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				g.hud.draw_texture_rect_region(atx, Rect2(c - Vector2(sz4.x / 2.0, sz4.y - 50), sz4), Rect2(fw4 * fr4, 0, fw4, atx.get_height()))
			var ends := [["Ⅰ", Color(0.8, 0.6, 1.0)], ["Ⅱ", Color(0.6, 0.85, 1.0)], ["Ⅲ", UI.GOLD], ["Ⅳ", Color(0.35, 0.55, 1.0)]]
			for k in 4:
				var ec: Color = ends[k][1]
				UI.diamond(g.hud, c + Vector2(-66 + k * 44, 92), 9.0, Color(ec.r, ec.g, ec.b, 0.35), ec)
				UI.text(g.hud, g.font, c + Vector2(-86 + k * 44, 122), ends[k][0], 13, ec, HORIZONTAL_ALIGNMENT_CENTER, 40)
		"keys":
			var keys := [["W", Vector2(0, -60)], ["A", Vector2(-48, -12)], ["S", Vector2(0, -12)], ["D", Vector2(48, -12)], ["Tab", Vector2(-40, 60)], ["Esc", Vector2(40, 60)]]
			for kk in keys:
				var kr := Rect2(c + kk[1] - Vector2(20, 20), Vector2(40 if kk[0].length() == 1 else 56, 40))
				g.hud.draw_rect(kr, Color(0.08, 0.2, 0.24))
				g.hud.draw_rect(kr, UI.CYAN, false, 1.5)
				UI.text(g.hud, g.font, kr.position + Vector2(0, 27), kk[0], 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)
