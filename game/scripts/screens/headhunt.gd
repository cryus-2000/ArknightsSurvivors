extends RefCounted
## 界面 · 寻访（局外成长 P1，docs/109 §12）：结算面板出来后，有待用的券就盖一层寻访面板，逐张用掉。
## 寻访凭证 = 翻牌揭晓随机干员；招募券 = 先选职业再揭晓；人事调度函 = 直接点名。全部用完才回到结算按钮。
## 只是界面与名册（Cfg.roster_*）：抽取在 core/roster.gd，用独立随机数，不碰局内 g.rng。
## 动效用真实时间；「减少动态效果」/ 无头截图直接到终态。

const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const A = preload("res://scripts/art.gd")
const Character = preload("res://scripts/characters/character.gd")
const Roster = preload("res://scripts/core/roster.gd")
const Game = preload("res://scripts/game.gd")

const FLIP0 := 0.25      # 牌背停留
const FLIP := 0.22       # 翻牌
const CLASS_ORDER := ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]

var g: Game
var open := false
var step := ""            # 当前券：Roster.T_HUNT / T_CLASS / T_PICK；"wish" = 正在选意向干员
var mode := "reveal"      # reveal 揭晓 / choose 选择
var back_step := ""       # 选意向前的那一步（选完回到揭晓）
var reveal_id := ""
var reveal_new_cls := false
var reveal_t0 := 0.0
var choices: Array = []
var sel := 0
var rects: Array = []     # [Rect2, 动作]：动作 = "ok" / "wish" / int（选项下标）
var _od := {}


func _init(game: Game) -> void:
	g = game


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 结算画出来时调（hud.gd）：有待用的券就打开
func maybe_open() -> void:
	if open or not Roster.active() or Roster.pending_total() <= 0:
		return
	if Roster.locked_ids().is_empty():
		Roster.spill_to_spare()
		return
	open = true
	_next()


func _next() -> void:
	if Roster.locked_ids().is_empty():
		Roster.spill_to_spare()
		open = false
		return
	for k in [Roster.T_HUNT, Roster.T_CLASS, Roster.T_PICK]:
		if int(Cfg.roster_tickets.get(k, 0)) > 0:
			_start(k)
			return
	open = false


func _start(k: String) -> void:
	step = k
	sel = 0
	if k == Roster.T_HUNT:
		_reveal(k, Roster.choose_hunt())
	elif k == Roster.T_CLASS:
		var lc := Roster.locked_classes()
		choices = CLASS_ORDER.filter(func(c): return lc.has(c))
		mode = "choose"
	else:
		choices = _sorted(Roster.locked_ids())
		mode = "choose"


func _sorted(ids: Array) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a, b):
		var ca := CLASS_ORDER.find(Roster.class_of(a))
		var cb := CLASS_ORDER.find(Roster.class_of(b))
		return ca < cb if ca != cb else a < b)
	return out


func _reveal(kind: String, cid: String) -> void:
	if cid == "":
		_next()
		return
	reveal_new_cls = not Roster.owned_classes().has(Roster.class_of(cid))
	Roster.redeem(kind, cid)
	Sfx.play("relic", -4.0)
	reveal_id = cid
	mode = "reveal"
	reveal_t0 = _now()


func _act(a) -> void:
	if a is int:
		if mode != "choose" or a < 0 or a >= choices.size():
			return
		Sfx.play("ui_ok")
		if step == Roster.T_CLASS:
			_reveal(Roster.T_CLASS, Roster.choose_class(choices[a]))
		elif step == Roster.T_PICK:
			_reveal(Roster.T_PICK, choices[a])
		elif step == "wish":
			Roster.set_wish(choices[a])
			step = back_step
			mode = "reveal"
		return
	if a == "ok" and mode == "reveal":
		Sfx.play("ui_ok")
		_next()
	elif a == "wish" and mode == "reveal" and not Roster.locked_ids().is_empty():
		Sfx.play("ui_ok")
		back_step = step
		step = "wish"
		choices = _sorted(Roster.locked_ids())
		sel = maxi(0, choices.find(Cfg.roster_wish))
		mode = "choose"
	elif a == "back" and step == "wish":
		step = back_step
		mode = "reveal"


## 输入（game.gd _unhandled_input 在寻访面板打开时整段交给这里）；返回是否用掉了这次输入
func input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position / Cfg.ui_k
		for r in rects:
			if (r[0] as Rect2).has_point(p):
				_act(r[1])
				return true
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = Pad.kc(event)
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_act(sel if mode == "choose" else "ok")
		elif k == KEY_W:
			_act("wish")
		elif k == KEY_ESCAPE:
			_act("back")
		elif mode == "choose" and k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D]:
			var cols := _cols()
			var d: int = {KEY_LEFT: -1, KEY_A: -1, KEY_RIGHT: 1, KEY_D: 1, KEY_UP: -cols, KEY_DOWN: cols}[k]
			sel = clampi(sel + d, 0, maxi(0, choices.size() - 1))
			g.kb_nav = true
			Sfx.play("ui_move")
		return true
	return event is InputEventMouseButton or event is InputEventScreenTouch


func _cols() -> int:
	return 4 if step == Roster.T_CLASS else 7


## 名册卡用的干员资料（同选人页 title.gd _open_op_pick 的取法，缓存）
func _card(cid: String) -> Dictionary:
	if _od.has(cid):
		return _od[cid]
	var d: Dictionary = Character.load_def(cid)
	var idle = d.get("sprites", {}).get("idle", "")
	var tn: String = idle if idle is String else idle.get("tex", "")
	var tx: Texture2D = A.tex(tn) if tn != "" else null
	var frames := 1
	if idle is Dictionary and idle.has("frames"):
		frames = int(idle.frames)
	elif tx != null:
		frames = maxi(1, tx.get_width() / tx.get_height())
	if Character.strip_mirror(d, "idle"):
		tx = A.mirror_strip(tx, frames)
	var cls: String = d.get("class", "")
	var col: Color = Character.CLASS_COL.get(cls, UI.CYAN)
	var cc = d.get("col", null)
	if cc is Array and cc.size() >= 3:
		col = Color(float(cc[0]), float(cc[1]), float(cc[2]))
	var od := {"id": cid, "tex": tx, "frames": frames, "hires": A.hires_of(tx), "ds": UI.op_scale(d), "name": d.get("name", cid), "cls": cls, "col": col}
	_od[cid] = od
	return od


func _title() -> Array:
	match step:
		Roster.T_HUNT:
			return ["寻访", "HEADHUNTING"]
		Roster.T_CLASS:
			return ["招募券 · 选择职业" if mode == "choose" else "招募券", "RECRUITMENT PERMIT"]
		Roster.T_PICK:
			return ["人事调度函 · 指定干员" if mode == "choose" else "人事调度函", "PERSONNEL TRANSFER"]
		"wish":
			return ["设定意向干员", "PREFERRED OPERATOR"]
	return ["寻访", "HEADHUNTING"]


func _button(r: Rect2, label: String, key: String, act, hot: bool) -> void:
	rects.append([r, act])
	var hov: bool = hot if (Pad.using or g.kb_nav) else r.has_point(g.hud.get_local_mouse_position())
	g.hud.draw_rect(r, UI.CYAN if hov else Color(UI.STEEL.r, UI.STEEL.g, UI.STEEL.b, 0.4))
	var ink := Color(0.04, 0.07, 0.09) if hov else UI.TEXT
	UI.text(g.hud, g.font, r.position + Vector2(14, r.size.y / 2.0 + 6.0), label, 15, ink)
	var kst: String = "" if Pad.touch else key
	if kst != "":
		UI.keycap(g.hud, g.font, Vector2(r.end.x - UI.cwidth(g.font, kst, 10) - 20, r.position.y + r.size.y / 2.0 - 9.0), kst, ink, 10)


func draw(vs: Vector2) -> void:
	rects.clear()
	var ci: CanvasItem = g.hud
	ci.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.9))
	var pw := minf(vs.x - 48.0, 700.0)
	var ph := 430.0
	var r := Rect2(vs.x / 2.0 - pw / 2.0, vs.y / 2.0 - ph / 2.0, pw, ph)
	var col := UI.CYAN
	if mode == "reveal" and reveal_id != "":
		col = _card(reveal_id).col
	UI.frame(ci, r, col, {"t": g.t})
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), Color(col.r, col.g, col.b, 0.85))
	var tt := _title()
	var ew: float = g.font.get_string_size(tt[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + tt[1].length() * 4.0
	UI.en(ci, g.font, Vector2(r.get_center().x - ew / 2.0, r.position.y + 40), tt[1], 13, col, 4.0)
	UI.heading(ci, g.font, Vector2(r.get_center().x, r.position.y + 74), tt[0], 26, col, minf(240.0, pw / 2.0 - 24.0))
	# 剩余的券
	var left: Array = []
	for k in [Roster.T_HUNT, Roster.T_CLASS, Roster.T_PICK]:
		var n := int(Cfg.roster_tickets.get(k, 0))
		if n > 0:
			left.append("%s ×%d" % [Roster.TICKET_NAME[k], n])
	UI.text(ci, g.font, Vector2(r.position.x + 24, r.end.y - 18), ("待用：" + " · ".join(left)) if not left.is_empty() else "待用：无", 12, UI.SUB)
	UI.text(ci, g.font, Vector2(r.end.x - 224, r.end.y - 18), "名册 %d / %d" % [Roster.all_ids().size() - Roster.locked_ids().size(), Roster.all_ids().size()], 12, UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, 200)
	if mode == "reveal":
		_draw_reveal(r)
	else:
		_draw_choose(r)


func _draw_reveal(r: Rect2) -> void:
	var ci: CanvasItem = g.hud
	var od := _card(reveal_id)
	var t := 99.0 if (UM.rm() or UM.skip_all()) else _now() - reveal_t0
	var c := Vector2(r.get_center().x, r.position.y + 178)
	var cr := Rect2(c - Vector2(66, 88), Vector2(132, 176))
	# 光圈（职业色）
	var ga := clampf((t - FLIP0 - FLIP) / 0.3, 0.0, 1.0)
	for k in 3:
		ci.draw_circle(c, 112.0 - k * 22.0, Color(od.col.r, od.col.g, od.col.b, (0.04 + 0.03 * k) * ga))
	var fk := clampf((t - FLIP0) / FLIP, 0.0, 1.0)
	var sx := absf(cos(fk * PI))
	var face := fk >= 0.5
	var rr := Rect2(Vector2(c.x - cr.size.x * sx / 2.0, cr.position.y), Vector2(maxf(2.0, cr.size.x * sx), cr.size.y))
	if not face:
		UI.rbox(ci, rr, 5, Color(0.04, 0.07, 0.11, 0.95), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6), 1)
		if sx > 0.3:
			UI.diamond(ci, rr.get_center(), 14.0 * sx, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5))
	elif sx >= 0.98:
		UI.roster_card(ci, g.font, cr, od, 0.0, 0.0, 0, int(g.t * 4.0) % int(od.frames), 1.0, 14)
	else:
		UI.rbox(ci, rr, 5, Color(0.086, 0.102, 0.204, 0.92), od.col, 1)
	if not face:
		return
	var ta := clampf((t - FLIP0 - FLIP) / 0.25, 0.0, 1.0)
	var line := "干员 %s 已加入名册" % od.name
	UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 306), line, 18, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, ta), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var sub: String = od.cls
	if reveal_new_cls:
		var cw := g.font.get_string_size("新职业 · " + sub, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(12)).x + 20.0
		UI.chip(ci, g.font, Vector2(r.get_center().x - cw / 2.0, r.position.y + 318), "新职业 · " + sub, UI.GOLD, 12)
	var locked := Roster.locked_ids()
	var wl: String
	if locked.is_empty():
		wl = "名册已满"
	elif Cfg.roster_wish != "" and locked.has(Cfg.roster_wish):
		wl = "意向干员：%s（寻访保底 %d / %d）" % [Character.load_def(Cfg.roster_wish).get("name", Cfg.roster_wish), mini(Cfg.roster_pity + 1, Roster.PITY), Roster.PITY]
	else:
		wl = "未设定意向干员：设定后 %d 张寻访凭证内必出" % Roster.PITY
	UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 352), wl, 12, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var bw := 180.0
	var by := r.end.y - 62.0
	if locked.is_empty():
		_button(Rect2(r.get_center().x - bw / 2.0, by, bw, 36), "完成", "Enter", "ok", true)
	else:
		_button(Rect2(r.get_center().x - bw - 6.0, by, bw, 36), "继续", "Enter", "ok", sel == 0)
		_button(Rect2(r.get_center().x + 6.0, by, bw, 36), "设定意向", "W", "wish", false)


func _draw_choose(r: Rect2) -> void:
	var ci: CanvasItem = g.hud
	var mouse := ci.get_local_mouse_position()
	if step == Roster.T_CLASS:
		UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 112), "从所选职业的未解锁干员里随机解锁 1 名", 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var cols := _cols()
		var bw := (r.size.x - 64.0 - 12.0 * (cols - 1)) / cols
		for i in choices.size():
			var cls: String = choices[i]
			var br := Rect2(r.position.x + 32 + (i % cols) * (bw + 12), r.position.y + 140 + int(i / cols) * 70, bw, 58)
			rects.append([br, i])
			var hov: bool = (i == sel) if (Pad.using or g.kb_nav) else br.has_point(mouse)
			var cc: Color = Character.CLASS_COL.get(cls, UI.CYAN)
			UI.rbox(ci, br, 5, Color(0.086, 0.102, 0.204, 0.92) if hov else Color(0.039, 0.078, 0.118, 0.86), cc if hov else Color(cc.r, cc.g, cc.b, 0.45), 2 if hov else 1)
			UI.class_glyph(ci, cls, br.position + Vector2(22, 29), 7.0, cc, 1.8)
			UI.text(ci, g.font, br.position + Vector2(40, 26), cls, 16, UI.TEXT)
			var n := Roster.locked_ids().filter(func(c): return Roster.class_of(c) == cls).size()
			UI.text(ci, g.font, br.position + Vector2(40, 46), "未解锁 %d 名" % n, 11, UI.SUB)
		return
	var hint := "选择 1 名干员直接解锁" if step == Roster.T_PICK else "意向干员 %d 张寻访凭证内必出；之后可以随时更换" % Roster.PITY
	UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 112), hint, 13, UI.SUB, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var cols := _cols()
	var cw := minf(78.0, (r.size.x - 48.0 - 8.0 * (cols - 1)) / cols)
	var chh := cw * 1.3
	var x0 := r.get_center().x - (cols * cw + (cols - 1) * 8.0) / 2.0
	for i in choices.size():
		var cr := Rect2(x0 + (i % cols) * (cw + 8.0), r.position.y + 132 + int(i / cols) * (chh + 14.0), cw, chh)
		rects.append([cr, i])
		var hov: bool = (i == sel) if (Pad.using or g.kb_nav) else cr.has_point(mouse)
		UI.roster_card(ci, g.font, cr, _card(choices[i]), 1.0 if hov else 0.0, 0.0, 0, int(g.t * 4.0 + i) % int(_card(choices[i]).frames), 1.0, 11)
		if choices[i] == Cfg.roster_wish:
			UI.chip(ci, g.font, cr.position + Vector2(2, cr.size.y + 4), "意向", UI.GOLD, 10)
	if step == "wish":
		_button(Rect2(r.get_center().x - 90.0, r.end.y - 62.0, 180, 36), "返回", "Esc", "back", false)
