extends RefCounted
## 界面 · 队友血条原型（10-28 用户「队友的血条显示需要优化」，docs/114 §19）：command/hpbar_style 切换，挑定前缺省 0 不变。
## 0 = §17 原版（编队卡下 6 像素细条，hud_squad._card_hp；头顶小条 / 屏外头像照旧）
## 1 = A 编队卡加强：卡下 9 像素分段条 + 受击残影；低血卡框红色呼吸；倒地整卡压灰、卡中央复活环 + 读秒，队长在旁写「加速」
## 2 = B 跟人走：编队卡不画血条；头顶条放大（44×6，分段 + 残影）、突击中常显，倒地头顶写读秒
## 3 = C 左侧生命列：屏幕左侧中段竖排「头像 + 名字 + 血条」，倒地行压灰写读秒；编队卡不画血条
## 4 = 队长血条下（10-28 用户「队友的血条能不能挪到我们的血条下面」）：左上队长生命条正下方，每名队友一行「职业色小块 + 名字 + 分段条」，
##     与队长条左对齐、同宽；倒地条换复活进度、条右写「倒地 N」；下面的灯火行与状态胶囊整体下移 top_shift()
## 1–4 共用：屏外边缘头像外圈 = 血量弧（倒地 = 灰色复活进度弧 + 读秒），低血外圈红色呼吸；多个标记挤在一起时沿边错开。
## 全部每帧画在 hud 的 front 块（不进编队栏缓存层），原型阶段不追求合批
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
const Character = preload("res://scripts/characters/character.gd")   # CLASS_COL
const A = preload("res://scripts/art.gd")
const M3 = preload("res://scripts/characters/blocks/m3_hp.gd")   # Mon3tr 血条（10-29 起；10-31 改头顶条 _draw_m3_overhead）：不依赖指挥模式
var g: Game
var h

const LOW := 0.3            # 低于它算低血（红色呼吸）
const LAG_HOLD := 0.35      # 受击后残影停留秒数，之后按 LAG_SPD / 秒缩到当前血量
const LAG_SPD := 0.6
const DOWN_COL := Color(0.55, 0.57, 0.6)
var _lag := {}              # 干员 id → 残影血量（0–1）
var _lt := -1.0


func _init(hud) -> void:
	h = hud
	g = hud.g


## 当前样式：指挥或队友生命关时 -1（什么都不画）
func style() -> int:
	if not g.squad.cmd_on() or not g.squad.hp_on():
		return -1
	return int(Bal.v("command/hpbar_style", 4.0))


func _mates() -> Array:
	return g.squad.ops.filter(func(o): return not o.is_leader and o.pos != Vector2.INF)


static func hp_col(hp: float) -> Color:
	return UI.GREEN if hp > 0.5 else (UI.GOLD if hp > LOW else UI.RED)


## 残血慢闪（10-31 用户：约 1.2 秒一次，docs/114 §21）
const LOW_PERIOD := 1.2

func pulse() -> float:
	return 0.5 + 0.5 * sin(g.t * TAU / LOW_PERIOD)


## 残血提醒中（squad._tick_low 维护，进 30% 出 40%）
static func low(o) -> bool:
	return o.cmd_low and o.cmd_down <= 0.0


func lag_of(o) -> float:
	return maxf(float(_lag.get(o.id, o.cmd_hp)), o.cmd_hp)


## 倒地时队长在 revive_near 内（复活 × revive_near_k）
func boosted(o) -> bool:
	return o.cmd_down > 0.0 and o.pos.distance_to(g.ppos) <= Bal.v("command/revive_near", 64.0)


func revive_k(o) -> float:
	return 1.0 - clampf(o.cmd_down / maxf(0.1, Bal.v("command/revive_secs", 25.0)), 0.0, 1.0)


func _tick_lag() -> void:
	var dt: float = clampf(g.t - _lt, 0.0, 0.1) if _lt >= 0.0 else 0.0
	_lt = g.t
	for o in _mates():
		var l: float = float(_lag.get(o.id, o.cmd_hp))
		if o.cmd_down > 0.0 or l < o.cmd_hp:
			l = o.cmd_hp
		elif g.t - o.cmd_hit_t > LAG_HOLD:
			l = move_toward(l, o.cmd_hp, LAG_SPD * dt)
		_lag[o.id] = l


## 一条队友血条（A / B / C 共用）：底 + 残影 + 填充 + 4 段刻度；倒地换灰色复活进度
func bar(r: Rect2, o, a := 1.0) -> void:
	g.hud.draw_rect(r.grow(1.0), Color(0.02, 0.03, 0.04, 0.88 * a))
	if o.cmd_down > 0.0:
		g.hud.draw_rect(r, Color(1, 1, 1, 0.08 * a))
		var c: Color = UI.GOLD if boosted(o) else DOWN_COL
		g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * revive_k(o), r.size.y)), Color(c.r, c.g, c.b, a))
		return
	var hc: Color = hp_col(o.cmd_hp)
	UI.gbar(g.hud, r, o.cmd_hp, Color(hc.r, hc.g, hc.b, a), 4, lag_of(o))
	var f: float = clampf(1.0 - (g.t - o.cmd_hit_t) / 0.35, 0.0, 1.0)
	if f > 0.0:
		g.hud.draw_rect(r, Color(1, 1, 1, 0.6 * f))


## front 块入口：样式 1 画编队卡、3 画左侧生命列；2 的头顶条由 banners._draw_op_hp 调 overhead()
func draw(vs: Vector2) -> void:
	var s := style()
	if s > 0:
		_tick_lag()
		if s == 1 and not h.phone_quiet():
			_draw_cards(vs)
		elif s == 3:
			_draw_column(vs)
		elif s == 4:
			_draw_under_leader()
		if s != 1 and not h.phone_quiet():
			_draw_card_low(vs)
	_draw_m3_overhead(vs)


# ---------------------------------------------------------------- A：编队卡

func _draw_cards(vs: Vector2) -> void:
	var sq = h.squad
	var br := Vector2(vs.x - 16, vs.y - 16)
	var n: int = g.squad.size()
	var roam: bool = g.squad.stance == g.squad.ROAM
	for i in n:
		var o = g.squad.ops[i]
		if o.is_leader or o.pos == Vector2.INF:
			continue
		var cr := Rect2(Vector2(br.x - (n - i) * sq.SQ_COL_W + (sq.SQ_COL_W - sq.SQ_CARD.x), br.y - sq.SQ_CARD.y), sq.SQ_CARD)
		var r := Rect2(Vector2(cr.position.x, cr.end.y + 3.0), Vector2(cr.size.x, 9.0))
		var down: bool = o.cmd_down > 0.0
		bar(r, o, 1.0 if roam or down or o.cmd_hp < 0.999 else 0.45)
		if down:
			g.hud.draw_rect(cr, Color(0.06, 0.07, 0.08, 0.6))
			var c: Vector2 = cr.position + Vector2(cr.size.x / 2.0, 52.0)
			var rc: Color = UI.GOLD if boosted(o) else Color(0.85, 0.87, 0.9)
			g.hud.draw_circle(c, 22.0, Color(0.02, 0.03, 0.04, 0.85))
			g.hud.draw_arc(c, 20.0, 0.0, TAU, 32, Color(1, 1, 1, 0.12), 3.0)
			g.hud.draw_arc(c, 20.0, -PI / 2.0, -PI / 2.0 + TAU * revive_k(o), 32, rc, 3.0)
			UI.ctext(g.hud, g.font, c + Vector2(-22, 8), str(int(ceil(o.cmd_down))), 20, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 44)
			UI.tab(g.hud, g.font, cr.position + Vector2(cr.size.x / 2.0 - 19.0, 16.0), "倒地", UI.RED)
			if boosted(o):
				UI.text(g.hud, g.font, Vector2(cr.position.x, c.y + 38.0), "加速", 11, UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
			continue
		if low(o):
			var p := pulse()
			g.hud.draw_rect(cr, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.1 + 0.12 * p))
			g.hud.draw_rect(cr.grow(1.0), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.55 + 0.4 * p), false, 2.0)
		var f: float = clampf(1.0 - (g.t - o.cmd_hit_t) / 0.35, 0.0, 1.0)
		if f > 0.0:
			g.hud.draw_rect(cr, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.22 * f))
			g.hud.draw_rect(cr.grow(1.0), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.95 * f), false, 2.0)


## 残血队友的编队卡头像框红色慢闪（样式 1 在 _draw_cards 里自己画）
func _draw_card_low(vs: Vector2) -> void:
	var sq = h.squad
	var br := Vector2(vs.x - 16, vs.y - 16)
	var n: int = g.squad.size()
	for i in n:
		var o = g.squad.ops[i]
		if o.is_leader or not low(o):
			continue
		var cr := Rect2(Vector2(br.x - (n - i) * sq.SQ_COL_W + (sq.SQ_COL_W - sq.SQ_CARD.x), br.y - sq.SQ_CARD.y), sq.SQ_CARD)
		var p := pulse()
		g.hud.draw_rect(cr, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.08 + 0.14 * p))
		g.hud.draw_rect(cr.grow(1.0), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.35 + 0.6 * p), false, 2.5)


# ---------------------------------------------------------------- B：头顶条（banners._draw_op_hp 在屏内时调）

func overhead(o, ct: Transform2D) -> void:
	_tick_lag()
	var roam: bool = g.squad.stance == g.squad.ROAM
	if not (roam or o.cmd_show > 0.0 or o.cmd_down > 0.0 or o.cmd_hp < 0.999):
		return
	var c: Vector2 = ct * (o.pos + Vector2(0, -62))
	var r := Rect2(c - Vector2(22, 0), Vector2(44, 6))
	var oc: Color = Character.CLASS_COL.get(o.cls, UI.CYAN)
	g.hud.draw_rect(Rect2(r.position - Vector2(5, 1), Vector2(3, r.size.y + 2)), oc)   # 左端职业色小块：和队长、敌人血条区分
	bar(r, o)
	if o.cmd_down > 0.0:
		UI.text(g.hud, g.font, c + Vector2(-40, -4), "倒地 %d" % int(ceil(o.cmd_down)), 13, UI.GOLD if boosted(o) else UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 80, 3)
	elif low(o):
		g.hud.draw_rect(r.grow(2.0), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.4 + 0.5 * pulse()), false, 1.5)


# ---------------------------------------------------------------- C：左侧生命列

const COL_ROW := 42.0

func _draw_column(vs: Vector2) -> void:
	var ms: Array = _mates()
	if ms.is_empty():
		return
	var touch: bool = g.touch.active
	var x0 := 16.0
	var y0: float = 150.0 if not touch else 118.0
	var w := 178.0
	var roam: bool = g.squad.stance == g.squad.ROAM
	var a: float = 1.0 if roam or ms.any(func(o): return o.cmd_down > 0.0 or o.cmd_hp < 0.999) else 0.5
	for i in ms.size():
		var o = ms[i]
		var row := Rect2(Vector2(x0, y0 + i * COL_ROW), Vector2(w, COL_ROW - 6.0))
		var down: bool = o.cmd_down > 0.0
		var oc: Color = Character.CLASS_COL.get(o.cls, UI.CYAN)
		var bgc := Color(0.03, 0.035, 0.045, 0.78 * a)
		if not down and low(o):
			bgc = bgc.lerp(Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.5 * a), 0.25 + 0.3 * pulse())
		g.hud.draw_rect(row, bgc)
		g.hud.draw_rect(Rect2(row.position, Vector2(3, row.size.y)), Color(oc.r, oc.g, oc.b, a))
		var hc := Vector2(row.position.x + 22.0, row.position.y + row.size.y / 2.0)
		var pt: Dictionary = o.portrait()
		var tx: Texture2D = g.tex.get(pt.tex)
		if tx != null:
			var src: Rect2 = h.banners._head_src(pt.tex, tx, int(pt.frames))
			g.hud.draw_texture_rect_region(tx, Rect2(hc - Vector2(14, 14), Vector2(28, 28)), src, Color(0.45, 0.45, 0.48, a) if down else Color(1, 1, 1, a))
		var bx: float = row.position.x + 42.0
		var nm: String = o.display_name().substr(0, 5)
		UI.text(g.hud, g.font, Vector2(bx, row.position.y + 15.0), nm, 12, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, a))
		if down:
			UI.text(g.hud, g.font, Vector2(bx, row.position.y + 15.0), "倒地 %d" % int(ceil(o.cmd_down)), 12, UI.GOLD if boosted(o) else UI.RED, HORIZONTAL_ALIGNMENT_RIGHT, w - 50.0)
		bar(Rect2(Vector2(bx, row.position.y + 22.0), Vector2(w - 50.0, 7.0)), o, a)
		var f: float = clampf(1.0 - (g.t - o.cmd_hit_t) / 0.35, 0.0, 1.0)
		if f > 0.0:
			g.hud.draw_rect(row, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.25 * f))


## 「队友血条」所在的矩形（开局指引框选用；没有队友时空矩形）。样式 0 / 1 = 编队卡下血条（连同队友卡），2 = 编队卡（头顶条跟人走，框卡说明是谁），3 = 左侧生命列
func guide_rect(vs: Vector2) -> Rect2:
	var n: int = g.squad.size()
	var ms: Array = _mates()
	if ms.is_empty():
		return Rect2()
	if int(Bal.v("command/hpbar_style", 4.0)) == 4:
		return Rect2(Vector2(UL_X - 8.0, UL_Y - 4.0), Vector2(UL_W + 52.0, ms.size() * UL_ROW + 6.0))
	if int(Bal.v("command/hpbar_style", 4.0)) == 3:
		var y0: float = 150.0 if not g.touch.active else 118.0
		return Rect2(Vector2(10.0, y0 - 6.0), Vector2(190.0, ms.size() * COL_ROW + 6.0))
	var sq = h.squad
	var br := Vector2(vs.x - 16, vs.y - 16)
	var x_first := INF
	var x_last := -INF
	for i in n:
		if g.squad.ops[i].is_leader:
			continue
		var x: float = br.x - (n - i) * sq.SQ_COL_W + (sq.SQ_COL_W - sq.SQ_CARD.x)
		x_first = minf(x_first, x)
		x_last = maxf(x_last, x + sq.SQ_CARD.x)
	return Rect2(Vector2(x_first - 6.0, br.y - sq.SQ_CARD.y - 6.0), Vector2(x_last - x_first + 12.0, sq.SQ_CARD.y + 20.0))


# ---------------------------------------------------------------- 4：队长血条下

const UL_X := 80.0          # = hud_bars.draw_top_left 的生命条 hx（o.x 16 + 64）
const UL_Y := 74.0          # 生命条底 63、神经细条底 68 之下
const UL_ROW := 15.0
const UL_W := 150.0         # 与队长生命条同宽

## 样式 4 时左上灯火行 / 状态胶囊要下移的像素（没有队友或不是样式 4 = 0）
func top_shift() -> float:
	if h.phone_quiet():
		return 0.0
	var n: int = _mates().size() if style() == 4 else 0   # Mon3tr 10-31 起改头顶条，不再占行
	return n * UL_ROW + 4.0 if n > 0 else 0.0


func _draw_under_leader() -> void:
	if top_shift() <= 0.0:
		return
	var ms: Array = _mates()
	var roam: bool = g.squad.stance == g.squad.ROAM
	var a: float = 1.0 if roam or ms.any(func(o): return o.cmd_down > 0.0 or o.cmd_hp < 0.999) else 0.6
	for i in ms.size():
		var o = ms[i]
		var y: float = UL_Y + i * UL_ROW
		var oc: Color = Character.CLASS_COL.get(o.cls, UI.CYAN)
		var down: bool = o.cmd_down > 0.0
		g.hud.draw_rect(Rect2(UL_X - 4.0, y - 1.0, 2.0, 11.0), Color(oc.r, oc.g, oc.b, a))   # 职业色小块（同编队卡底条 / 屏外头像外圈）
		var nm: String = o.display_name().substr(0, 4)
		UI.text(g.hud, g.font, Vector2(UL_X + 1.0, y + 9.0), nm, 10, Color(0.81, 0.84, 0.86, a) if not down else Color(0.6, 0.62, 0.65, a), HORIZONTAL_ALIGNMENT_LEFT, 48.0, 2)
		var r := Rect2(Vector2(UL_X + 52.0, y + 3.0), Vector2(UL_W - 52.0, 5.0))
		if not down and low(o):
			g.hud.draw_rect(r.grow(2.5), Color(UI.RED.r, UI.RED.g, UI.RED.b, (0.3 + 0.5 * pulse()) * a), false, 1.5)
		bar(r, o, a)
		if down:
			UI.text(g.hud, g.font, Vector2(r.end.x + 6.0, y + 9.0), "倒地 %d" % int(ceil(o.cmd_down)), 10, UI.GOLD if boosted(o) else UI.RED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 2)


## Mon3tr 头顶血条（10-31 用户「Mon3tr 的血条移到它的头顶上方，样式和队友头顶血条一致」，docs/114 §21）：
## 同 banners._draw_op_hp（32×4、绿 / 金 / 红，倒地灰条 = 复活进度）；受击后 3 秒、未满血、倒地或残血时显示。
## 残血提醒同队友：跌破 command/low_hp 进、回到 command/low_hp_off 以上出，红框 + 整条提亮 1.2 秒一次慢闪（不说话）
const M3_HEAD := 70.0     # 还没画过本体（没有 draw_top）时的退路
var _m3_low := {}   # 召唤物 id → 残血提醒中
var _top_rows := {}  # 贴图 → 第 0 帧第一行不透明像素（帧条像素）


## Mon3tr 头顶在脚底上方多高（世界单位）：按本帧贴图第 0 帧的不透明上沿算（ob_summon 画本体时记下 draw_top），每张贴图只扫一次
func _m3_head(s: Dictionary) -> float:
	var dt = s.get("draw_top")
	if not (dt is Array) or dt[0] == null:
		return M3_HEAD
	var tx: Texture2D = dt[0]
	var hf: int = maxi(1, int(dt[1]))
	if not _top_rows.has(tx):
		var top := 0
		var im: Image = tx.get_image()
		if im != null:
			if im.is_compressed():
				im.decompress()
			var fw: int = im.get_width() / hf
			var found := false
			for y in im.get_height():
				for x in fw:
					if im.get_pixel(x, y).a > 0.5:
						found = true
						break
				if found:
					top = y
					break
		_top_rows[tx] = top
	var pk: float = Game.PX / A.hires_of(tx) * float(dt[3])
	return (float(tx.get_height()) - float(dt[2]) - float(_top_rows[tx])) * pk - float(dt[4])


func m3_low(s: Dictionary) -> bool:
	return bool(_m3_low.get(int(s.id), false))


func _draw_m3_overhead(vs: Vector2) -> void:
	var es: Array = M3.entries(g)
	if es.is_empty():
		return
	var ct: Transform2D = g.hud_ct()
	var lo: float = Bal.v("command/low_hp", 0.3)
	var hi: float = Bal.v("command/low_hp_off", 0.4)
	for e in es:
		var o = e[0]
		var s: Dictionary = e[1]
		var sid: int = int(s.id)
		var down: bool = M3.is_down(s)
		var f: float = clampf(float(s.hp) / maxf(1.0, float(s.max_hp)), 0.0, 1.0)
		var lw: bool = bool(_m3_low.get(sid, false))
		if down:
			lw = false
		elif lw:
			lw = f < hi
		else:
			lw = f < lo
		_m3_low[sid] = lw
		if not (down or lw or f < 0.999 or float(s.m3.show) > 0.0):
			continue
		var c: Vector2 = ct * (s.pos + Vector2(0, -_m3_head(s) - 6.0))   # 头顶上方 6 世界单位（10-31 用户「m3 的血条不在头顶」）
		if not Rect2(Vector2(-20, -20), vs + Vector2(40, 40)).has_point(c):
			continue
		var r := Rect2(c - Vector2(16, 0), Vector2(32, 4))
		g.hud.draw_rect(r.grow(1.0), Color(0.02, 0.03, 0.04, 0.85))
		if down:
			var total: float = maxf(0.1, M3.k(o, "m3_revive_secs", 18.0))
			g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(1.0 - float(s.down) / total, 0.0, 1.0), r.size.y)), DOWN_COL)
			continue
		var hc: Color = UI.RED if lw else (UI.GREEN if f > 0.5 else (UI.GOLD if f > 0.25 else UI.RED))
		g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), hc)
		if lw:
			var p := pulse()
			g.hud.draw_rect(r.grow(2.5), Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.35 + 0.6 * p), false, 1.5)
			g.hud.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color(1, 0.6, 0.6, 0.45 * p))


# ---------------------------------------------------------------- 屏外边缘头像（1–3 共用，banners.draw_command 调）

## 外圈血量弧 / 倒地复活弧 + 读秒；低血外圈红色呼吸
func edge_ring(o, edge: Vector2) -> void:
	if o.cmd_down > 0.0:
		g.hud.draw_arc(edge, 26.0, -PI / 2.0, -PI / 2.0 + TAU * revive_k(o), 32, UI.GOLD if boosted(o) else Color(0.85, 0.87, 0.9), 3.0)
		UI.text(g.hud, g.font, edge + Vector2(-20, 7), str(int(ceil(o.cmd_down))), 15, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 40, 3)
		return
	g.hud.draw_arc(edge, 26.0, 0.0, TAU, 32, Color(0.02, 0.03, 0.04, 0.85), 4.0)
	var hc: Color = hp_col(o.cmd_hp)
	if low(o):
		hc = hc.lerp(Color.WHITE, 0.35 * pulse())
	if o.cmd_hp > 0.0:
		g.hud.draw_arc(edge, 26.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(o.cmd_hp, 0.0, 1.0), 32, hc, 3.0)


## 屏外标记挤在一起时沿框边错开（两两距离 < 52 就各往切向推开）
static func spread(pts: Array, box: Rect2) -> Array:
	for _it in 3:
		for i in pts.size():
			for j in range(i + 1, pts.size()):
				var dd: Vector2 = pts[j] - pts[i]
				if dd.length() < 52.0:
					var push: Vector2 = (dd.normalized() if dd.length() > 0.5 else Vector2(0, 1)) * (52.0 - dd.length()) / 2.0
					pts[i] = (pts[i] - push).clamp(box.position, box.end)
					pts[j] = (pts[j] + push).clamp(box.position, box.end)
	return pts
