extends RefCounted
## 界面 · 精英化 / 解锁演出（state SHOW）：精英化后的技能解锁展示，内嵌一段实机演示（run/demo.gd）与技能卡。
## 界面层约定（docs/37）。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")
const A = preload("res://scripts/art.gd")

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var seen_shows_run: Array = []  # 本局已完整播放过的解锁演出
var show_cur: Dictionary = {}
var show_vp: SubViewport = null  # 精英化演出里的实机演示画面
var show_game: Node = null


func _init(game: Game) -> void:
	g = game


## 解锁演出的技能卡：干员 op 的第 i 个技能
func skill_item(op, i: int) -> Dictionary:
	var sk: Dictionary = op.skill_def(i)
	return {"tag": "技能", "tag_en": "SKILL %d" % (i + 1), "glyph": sk.get("name", "技").substr(0, 1), "icon": sk.get("icon", ""), "name": sk.get("name", ""), "desc": sk.get("desc", ""), "col": op.col()}


func open(sc: Dictionary) -> void:
	# 解锁演出只在第一次出现时完整播放，之后改为横幅提示
	var key: String = sc.get("head", "")
	if seen_shows_run.has(key) and not OS.get_cmdline_user_args().has("--fastlevel"):
		var names: Array = []
		for it in sc["items"]:
			names.append(it.name)
		g.vfx.show_banner("%s：%s" % [key, "、".join(names)])
		g.fx.append({"kind": "rays", "pos": g.ppos, "life": 0.6, "max": 0.6, "col": sc.col})
		Sfx.play("relic", -4.0, 0.9, 0.0)
		g._check_pending.call_deferred()
		return
	seen_shows_run.append(key)
	g.show_shot = false
	show_cur = sc
	g.show_t = 0.0
	g.state = Game.S.SHOW
	# 精英化演出：左侧放一个实机演示（demo 模式的 game.tscn），干员已在新阶段并循环施放新解锁的技能
	demo_stop()
	if sc.has("op") and int(sc.get("elite", 0)) > 0 and not g.balance and DisplayServer.get_name() != "headless":
		show_vp = SubViewport.new()
		show_vp.size = Vector2i(540, 300)
		show_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		show_vp.handle_input_locally = false
		g.add_child(show_vp)
		show_game = load("res://game.tscn").instantiate()
		show_game.demo_op = sc.op.id
		show_game.demo_elite = int(sc.elite)
		show_game.demo_skill = int(sc.elite)   # 精一 → S2（序号 1），精二 → S3（序号 2）
		show_vp.add_child(show_game)
	Sfx.play("relic", 0.0, 0.8, 0.0)
	Sfx.play("levelup", -4.0, 0.7, 0.0)


func demo_stop() -> void:
	if show_vp != null:
		show_vp.queue_free()
	show_vp = null
	show_game = null


func close() -> void:
	if g.state != Game.S.SHOW or g.show_t < 1.0:
		return
	demo_stop()
	show_cur = {}
	g.state = Game.S.PLAY
	Sfx.play("ui_ok", -4.0)
	g._check_pending()


## 解锁演出：暗场 -> 标题横幅 -> 水月演示 -> 说明卡依次滑入
func draw(vs: Vector2) -> void:
	var sc := show_cur
	var st := g.show_t
	var col: Color = sc.col
	var fade := clampf(st / 0.3, 0.0, 1.0)
	g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.86 * fade))
	# 扫光带
	var sweep := clampf((st - 0.1) / 0.5, 0.0, 1.0)
	g.hud.draw_rect(Rect2(0, 70, vs.x * sweep, 64), Color(col.r, col.g, col.b, 0.14))
	g.hud.draw_rect(Rect2(0, 70, vs.x * sweep, 2), col)
	g.hud.draw_rect(Rect2(0, 132, vs.x * sweep, 2), Color(col.r, col.g, col.b, 0.5))
	var ha := clampf((st - 0.25) / 0.3, 0.0, 1.0)
	var hx := lerpf(-60.0, 0.0, ha)
	UI.en(g.hud, g.font, Vector2(90 + hx, 94), sc.en, 13, Color(col.r, col.g, col.b, ha), 5.0)
	UI.text(g.hud, g.font, Vector2(88 + hx, 126), sc.head + "  ·  新能力解锁", 28, Color(1, 1, 1, ha))
	# 左侧：干员演示。有实机演示画面就画它（新阶段的干员在假人堆里循环放新技能），否则退回静态挥击示意
	var cx := Vector2(330, vs.y * 0.58)
	var da := clampf((st - 0.35) / 0.35, 0.0, 1.0)
	if show_vp != null:
		var dr := Rect2(Vector2(60, 180), Vector2(540, 300))
		g.hud.draw_texture_rect(show_vp.get_texture(), dr, false, Color(1, 1, 1, da))
		g.hud.draw_rect(dr, Color(col.r, col.g, col.b, 0.6 * da), false, 2.0)
		var sop0 = sc.get("op", g.ch)
		var skn: String = sop0.skill_def(int(sc.get("elite", 0))).get("name", "") if sop0.has_method("skill_def") else ""
		if skn != "":
			UI.chip(g.hud, g.font, dr.position + Vector2(14, 14), "实机演示 · %s" % skn, Color(col.r, col.g, col.b, da), 11)
		var items0: Array = sc["items"]
		draw_cards(items0, st)
		if st > 1.0:
			var ba0 := 0.5 + 0.5 * sin(st * 4.0)
			UI.text(g.hud, g.font, Vector2(0, vs.y - 40), "点击或按任意键继续", 15, Color(0.75, 0.88, 0.92, 0.5 + 0.5 * ba0), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
		return
	for k in 3:
		var rp := fmod(st * 0.8 + k / 3.0, 1.0)
		g.hud.draw_arc(cx + Vector2(0, -10), 60.0 + rp * 130.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, (1.0 - rp) * 0.5 * da), 3.0)
	g.hud.draw_circle(cx + Vector2(0, 58), 70.0, Color(col.r, col.g, col.b, 0.08 * da))
	g.hud.draw_set_transform(cx + Vector2(0, 58), 0.0, Vector2(1.0, 0.3))
	g.hud.draw_circle(Vector2.ZERO, 60.0, Color(0, 0, 0, 0.5 * da))
	g.hud.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sop = sc.get("op", g.ch)
	var at: Texture2D = sop.anim_tex("attack")
	if at != null:
		var n := at.get_width() / at.get_height()
		var fh := at.get_height()
		var spd := 9.0
		var fr := int(st * spd) % n
		var S5: float = 5.0 / A.hires_of(at)
		var size := Vector2(fh, fh) * S5
		var dst := Rect2(cx - Vector2(size.x / 2.0, size.y - 60.0 + 2.0 * S5), size)
		g.hud.draw_texture_rect_region(at, dst, Rect2(fh * fr, 0, fh, fh), Color(1, 1, 1, da))
		# 技能特效示意
		var sl: Texture2D = g.tex.get("slash")
		if sl != null and fr >= 1:
			var sfw := sl.get_width() / 4
			var sfr := clampi(fr - 1, 0, 3)
			var ssz := Vector2(sfw, sl.get_height()) * 5.0
			g.hud.draw_texture_rect_region(sl, Rect2(cx + Vector2(-ssz.x / 2.0 + 60.0, -ssz.y / 2.0 - 70.0), ssz), Rect2(sfw * sfr, 0, sfw, sl.get_height()), Color(col.r * 1.3, col.g * 1.3, col.b * 1.3, 0.9 * da))
	# 右侧：说明卡
	draw_cards(sc["items"], st)
	if st > 1.0:
		var ba := 0.5 + 0.5 * sin(st * 4.0)
		UI.text(g.hud, g.font, Vector2(0, vs.y - 40), "点击或按任意键继续", 15, Color(0.75, 0.88, 0.92, 0.5 + 0.5 * ba), HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func draw_cards(items: Array, st: float) -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var ia := clampf((st - 0.55 - i * 0.25) / 0.3, 0.0, 1.0)
		if ia <= 0.0:
			continue
		var e := 1.0 - pow(1.0 - ia, 3)
		var r := Rect2(Vector2(620 + (1.0 - e) * 120.0, 190 + i * 190), Vector2(580, 168))
		var ic: Color = it.col
		UI.frame(g.hud, r, Color(ic.r, ic.g, ic.b, e), {"t": g.t, "vines": true, "seed": 50 + i, "vine_k": 0.6, "cut": 12.0, "bracket": 12.0, "alpha": e, "glow": 0.6 * e})
		var gc := r.position + Vector2(70, 84)
		UI.pedestal(g.hud, gc, 40.0, Color(ic.r, ic.g, ic.b, e), g.t, true)
		var itex: Texture2D = g.tex.get(it.get("icon", "")) if it.has("icon") else null
		if itex != null:
			g.hud.draw_texture_rect(itex, Rect2(gc - Vector2(32, 32), Vector2(64, 64)), false, Color(1, 1, 1, e))
		else:
			UI.text(g.hud, g.font, gc + Vector2(-40, 12), it.glyph, 30, Color(ic.r, ic.g, ic.b, e), HORIZONTAL_ALIGNMENT_CENTER, 80)
		UI.chip(g.hud, g.font, r.position + Vector2(140, 22), "新%s  ·  NEW %s" % [it.tag, it.tag_en], Color(ic.r, ic.g, ic.b, e), 11)
		UI.text(g.hud, g.font, r.position + Vector2(150, 76), it.name, 26, Color(1, 1, 1, e))
		UI.draw_fit(g.hud, g.font, r.position + Vector2(150, 91), UI.fit(g.font, it.desc, r.size.x - 172, 72.0, [15, 14, 13, 12]), Color(0.78, 0.88, 0.9, e))
