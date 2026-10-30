extends RefCounted

const PlayKeys = preload("res://scripts/core/play_keys.gd")   # 按键提示查局内按键表
## 界面 · 终结技 / 连携技 HUD（docs/198 §2.3 / §2.4 / §2.5 / §7.1 / §7.2 / §7.3；原型 claude/ult-proto，10-29）。g.ult 为 null（balance ult/on = 0）时 hud.gd 不调本文件。
## 桌面（底部中央、冲刺提示上方）：左边连携亮起的队友头像（队首带从亮到暗的倒计时环、后面排队的静止亮着），中间终结技徽记（队长头像），
## 右边终结技能量条（满条呼吸光、不弹字）+ 协同格（ult/cells）+ 按键提示；Q 升级态（能量满 + 协同满）= 金色描边 + 全队头像环。
## 触屏：右下大圆「终结技」键（外圈能量、上方协同格弧）与它左上的小圆「连携」键，位置 / 点按在 touch.gd（ult_btn / combo_btn），这里只画。
## 立绘切入（draw_cutins）：屏边斜切条带宽 1/3 屏、底色干员色、只写干员名，立绘用图鉴同款待机帧 @2x（A.tex_hi）；队长在左半屏从右边切入；
## 连携终结技多条按 i 叠成阶梯；按界面时钟 UM.now() − t0 与 dur 滑入 → 停留 → 滑出；Boss 战透明度 × 0.7。每帧重画（签名 null）。
## 合批：色块 / 圆 / 环进 Tris，头像是贴图多边形（圆形裁切，每个一次绘制，最多十来个），字最后按字号成组（hud.text_flush）
const A = preload("res://scripts/art.gd")
const UI = preload("res://scripts/ui.gd")
const Game = preload("res://scripts/game.gd")
const Tris = preload("res://scripts/screens/hud_tris.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UM = preload("res://scripts/ui_motion.gd")
const HudUltV = preload("res://scripts/screens/hud_ult_v.gd")   # 并进左上生命块的三个原型（ui/hud_ult_v 1–3，10-30）
var g: Game
var h   # screens/hud.gd
var v: HudUltV

const DARK := Color(0.03, 0.035, 0.045, 0.82)


func _init(hud) -> void:
	h = hud
	g = hud.g
	v = HudUltV.new(self)


func _on() -> bool:
	return g.ult != null and g.demo_op == "" and g.squad != null


## 截图自测 --ulthud=demo（只认调试参数 Cfg.dev_args，对外包无效）：连携 / 协同还没有真实来源时看界面用——只改 HUD 读到的显示值，
## 不改 g.ult 的状态（排队 = 全体队友轮流亮起、协同按 g.t 每 8 秒 +1 格）；另外每 5 秒（界面时钟）往 cutins 里塞一组连携终结技条带（cutins 只有 HUD 读）
static var _demo: int = -1
var _demo_q: Array = []
var _demo_t := -99.0


func _demo_on() -> bool:
	if _demo < 0:
		_demo = 1 if Cfg.dev_args().has("--ulthud=demo") else 0
	return _demo == 1


func _q() -> Array:
	if not _demo_on():
		return g.ult.queue
	_demo_q.clear()
	var lt: float = _lit_t()
	var k := 0
	for o in g.squad.ops:
		if o.is_leader or o.pos == Vector2.INF:
			continue
		_demo_q.append({"o": o, "info": {}, "t0": 0.0, "left": lt - fmod(g.t, lt) if k == 0 else lt})
		k += 1
	return _demo_q


## 协同格数（balance ult/cells）
func _n() -> int:
	return int(g.ult.CELLS)


func _cells() -> int:
	return mini(_n(), int(g.t / 8.0)) if _demo_on() else int(g.ult.cells)


func _up() -> bool:
	return g.ult.full() and _cells() >= _n()


func _demo_tick() -> void:
	var now: float = UM.now()
	if now - _demo_t < 5.0:
		return
	_demo_t = now
	var i := 0
	for o in g.squad.ops:
		if o.pos == Vector2.INF or i >= 4:
			continue
		g.ult.cutins.append({"id": str(o.id), "name": o.display_name(), "col": o.col(), "t0": now + 0.12 * i, "dur": 1.1, "i": i, "cult": true})
		i += 1


# ================================================================ 头像（圆形裁切的待机帧头部）

var _bb := {}   # 贴图名 → 待机帧并集区（UI.idle_bb，读一次图像，之后缓存）


static func _base(t: Texture2D) -> Texture2D:
	return t.diffuse_texture if t is CanvasTexture and (t as CanvasTexture).diffuse_texture != null else t


func _bb_of(key: String, t: Texture2D, frames: int) -> Rect2:
	if not _bb.has(key):
		_bb[key] = UI.idle_bb(_base(t), frames)
	return _bb[key]


## 头像的贴图与源矩形（帧 0 头部的正方形）：[贴图, Rect2]；没有立绘返回 []
func _head(o) -> Array:
	var pt: Dictionary = o.portrait()
	var t: Texture2D = g.tex.get(pt.tex)
	if t == null:
		return []
	t = _base(t)
	var bb: Rect2 = _bb_of(str(pt.tex), t, int(pt.frames))
	var s: float = clampf(bb.size.y * 0.42, 4.0, bb.size.x if bb.size.x > 0.0 else 4.0)
	s = maxf(s, minf(bb.size.x, bb.size.y) * 0.5)
	var cx: float = bb.position.x + bb.size.x * 0.5
	var src := Rect2(cx - s * 0.5, bb.position.y - s * 0.04, s, s)
	return [t, src]


## 圆形头像：贴图多边形（uv 取头部正方形的内切圆）；tint 调暗 / 透明
func _avatar(o, c: Vector2, r: float, tint := Color.WHITE) -> void:
	var hd: Array = _head(o)
	if hd.is_empty():
		return
	var t: Texture2D = hd[0]
	var src: Rect2 = hd[1]
	var ts: Vector2 = t.get_size()
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var n := 20
	for i in n:
		var d := Vector2.from_angle(TAU * i / n)
		pts.append(c + d * r)
		uvs.append((src.get_center() + d * src.size.x * 0.5) / ts)
	g.hud.draw_colored_polygon(pts, tint, uvs, t)


func _lit_t() -> float:
	return Bal.v("ult/lit_t", 2.5)


func _boss_on() -> bool:
	return (g.final_boss != null and not g.final_boss.dead) or not g.bosses.is_empty()


## 开局提示（hud_banners.draw_open_hints）占着底部中央时，桌面版让开
func _hint_busy() -> bool:
	return g.t < 6.0 or (g.t < 16.0 and not g.tab_used) or g.tab_hint > 0.0


# ================================================================ HUD 本体

func draw(vs: Vector2) -> void:
	if not _on():
		return
	if HudUltV.ver() > 0 or HudUltV.link_cue() > 0:
		if g.state == Game.S.PLAY or g.state == Game.S.PAUSE or (g.touch.active and g.hud_live()):
			v.draw(vs)
		if HudUltV.ver() > 0:
			return
	if g.touch.active:
		if g.hud_live():
			_draw_touch(vs)
		return
	if g.state != Game.S.PLAY and g.state != Game.S.PAUSE:
		return
	if _hint_busy():
		return
	_draw_desk(vs)


## 桌面：底部中央（冲刺提示 vs.y − 44 之上）
func _draw_desk(vs: Vector2) -> void:
	var u = g.ult
	var ld = g.squad.leader()
	var bg := Tris.new()
	var fg := Tris.new()
	var txt: Array[Callable] = []
	var cx: float = vs.x / 2.0
	var cy: float = vs.y - 86.0
	var full: bool = u.full()
	var up: bool = _up()
	var pulse: float = 0.5 + 0.5 * sin(g.t * 4.0)
	var acc: Color = UI.GOLD if up else UI.CYAN
	# ---- 徽记：队长头像 + 外圈
	var ec := Vector2(cx - 64.0, cy)
	var er := 25.0
	bg.circle(ec, er + 2.0, DARK, 28)
	# ---- 能量条 + 协同格 + 标题 / 按键
	var x0: float = cx - 30.0
	var bw := 190.0
	var bar := Rect2(x0, vs.y - 96.0, bw, 8.0)
	bg.rect(Rect2(x0 - 6.0, vs.y - 120.0, bw + 12.0, 46.0), Color(0.03, 0.035, 0.045, 0.6))
	bg.rect(bar, Color(0.1, 0.12, 0.14, 0.95))
	var ek: float = clampf(u.energy / 100.0, 0.0, 1.0)
	var ecol: Color = acc if full else Color(0.55, 0.85, 0.9)
	bg.rect(Rect2(bar.position, Vector2(bw * ek, bar.size.y)), ecol)
	if full:
		# 满条呼吸光（不弹字）：条外一圈随呼吸亮暗的光晕
		for k in 3:
			fg.frame(bar.grow(1.5 + k * 2.0), Color(acc.r, acc.g, acc.b, (0.38 - k * 0.11) * (0.35 + 0.65 * pulse)), 2.0)
	var cw: float = (bw - float(_n() - 1) * 4.0) / float(_n())
	for i in _n():
		var cr := Rect2(x0 + i * (cw + 4.0), vs.y - 82.0, cw, 5.0)
		bg.rect(cr, UI.GOLD if i < _cells() else Color(0.16, 0.18, 0.2, 0.95))
	var title: String = "连携终结技" if up else "终结技"
	var key: String = Pad.hint(PlayKeys.hint("ult", true, false), PlayKeys.hint("ult", true, true))
	var tcol: Color = (UI.GOLD if up else UI.TEXT) if full else UI.SUB
	txt.append(func():
		UI.text(g.hud, g.font, Vector2(x0, vs.y - 103.0), title, 12, tcol)
		UI.text(g.hud, g.font, Vector2(x0, vs.y - 103.0), key, 12, UI.TEXT if full else UI.SUB, HORIZONTAL_ALIGNMENT_RIGHT, bw))
	# ---- 连携排队（徽记左边）
	# 连携亮起（10-29 用户「根本看不出来」）：队首大头像弹在底部中间、能量条上方（半径 34），后面排队的小头像往左排
	var heads: Array = _queue_slots(Vector2(cx + 30.0, vs.y - 174.0), 34.0, 16.0, -1.0)
	bg.flush(g.hud)
	# 贴图：队长头像、排队头像、Q 升级态的全队头像环
	if ld != null:
		_avatar(ld, ec, er - 3.0, Color.WHITE if full else Color(0.55, 0.58, 0.62))
	_queue_avatars(heads)
	if up:
		_squad_ring(ec, er + 15.0, 8.0)
	# ---- 徽记外圈
	if full:
		fg.arc(ec, er + 1.0, 0.0, TAU, 2.5 if not up else 3.0, Color(acc.r, acc.g, acc.b, 0.95), 32)
		fg.arc(ec, er + 5.0 + 2.0 * pulse, 0.0, TAU, 2.0, Color(acc.r, acc.g, acc.b, 0.25 + 0.45 * pulse), 32)
		if up:
			fg.arc(ec, er + 4.0, 0.0, TAU, 1.5, Color(1.0, 0.95, 0.75, 0.9), 32)   # 金色双描边
	else:
		fg.arc(ec, er + 1.0, 0.0, TAU, 1.5, Color(1, 1, 1, 0.18), 32)
		fg.arc(ec, er + 1.0, -PI / 2.0, -PI / 2.0 + TAU * ek, 2.5, Color(0.55, 0.85, 0.9, 0.85), 32)
	_queue_rings(fg, txt, heads, Pad.hint(PlayKeys.hint("combo", true, false), PlayKeys.hint("combo", true, true)))
	fg.flush(g.hud)
	h.text_flush(txt)


## 排队头像的位置：队首在 c0（半径 r0），其后依次往 dir 方向（-1 = 左）排开（半径 r1）；返回 [{"q", "c", "r", "head"}]
func _queue_slots(c0: Vector2, r0: float, r1: float, dir: float) -> Array:
	var out: Array = []
	var x: float = c0.x
	for i in _q().size():
		var q: Dictionary = _q()[i]
		if q.o == null:
			continue
		var r: float = r0 if i == 0 else r1
		if i == 0 and q.info.has("link"):
			r *= 1.15   # 技能连携：就绪提示略大一号（10-29 返工：要轻）
		if i == 0:
			var pk: float = clampf((_lit_t() - float(q.left)) / 0.15, 0.0, 1.0)
			r *= 0.55 + 0.45 * (1.0 - (1.0 - pk) * (1.0 - pk))   # 弹出：0.15 秒从 55% 放大到整
		if i > 0:
			x += dir * ((r0 if i == 1 else r1) + r1 + 8.0)
		var c := Vector2(x, c0.y)
		if i == 0:
			# 亮起时头像轻跳一次（§7.2）：亮起后 0.25 秒内上下一跳
			var since: float = _lit_t() - float(q.left)
			c.y -= 5.0 * sin(PI * clampf(since / 0.25, 0.0, 1.0))
		out.append({"q": q, "c": c, "r": r, "head": i == 0})
		if out.size() >= 4:
			break
	return out


func _queue_avatars(slots: Array) -> void:
	for s in slots:
		var cc: Color = s.q.o.col()
		g.hud.draw_circle(s.c, s.r + 1.0, Color(cc.r * 0.3, cc.g * 0.3, cc.b * 0.3, 0.9))
		_avatar(s.q.o, s.c, s.r - 2.0)


## 倒计时环：队首从亮到暗（弧长 = 剩余 / 2.5 秒，颜色随剩余变暗）；后面排队的整圈静止亮着
func _queue_rings(fg: Tris, txt: Array[Callable], slots: Array, key: String) -> void:
	for s in slots:
		var cc: Color = s.q.o.col().lerp(Color.WHITE, 0.35)
		if s.head:
			var k: float = clampf(float(s.q.left) / _lit_t(), 0.0, 1.0)
			fg.arc(s.c, s.r + 3.0, 0.0, TAU, 3.0, Color(0.02, 0.03, 0.04, 0.7), 32)
			fg.arc(s.c, s.r + 3.0, -PI / 2.0, -PI / 2.0 + TAU * k, 3.0, Color(cc.r, cc.g, cc.b, 0.35 + 0.65 * k), 32)
			var kc: Vector2 = s.c + Vector2(0, -s.r - 16.0)
			if s.q.info.has("link"):
				var lc: Vector2 = s.c + Vector2(0, s.r + 18.0)
				txt.append(func(): UI.text(g.hud, g.font, lc + Vector2(-80.0, 6.0), "技能连携", 16, Color(1.0, 0.8, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 4))
			if key != "":
				var kw: float = g.font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.fs(11)).x + 10.0
				fg.rect(Rect2(kc - Vector2(kw / 2.0, 8.0), Vector2(kw, 16.0)), Color(0.03, 0.035, 0.045, 0.85))
				fg.frame(Rect2(kc - Vector2(kw / 2.0, 8.0), Vector2(kw, 16.0)), Color(cc.r, cc.g, cc.b, 0.8), 1.0)
				txt.append(func(): UI.text(g.hud, g.font, kc + Vector2(-30.0, 4.0), key, 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 60.0))
		else:
			fg.arc(s.c, s.r + 2.0, 0.0, TAU, 2.0, Color(cc.r, cc.g, cc.b, 0.85), 24)


## Q 升级态的全队头像环：在场干员的小头像沿 c 外圈从正上方排开
func _squad_ring(c: Vector2, rr: float, ar: float) -> void:
	var ops: Array = []
	for o in g.squad.ops:
		if o.pos != Vector2.INF:
			ops.append(o)
	var n: int = ops.size()
	if n == 0:
		return
	var span: float = minf(TAU, n * (ar * 2.4) / rr)
	for i in n:
		var a: float = -PI / 2.0 - span / 2.0 + span * (i + 0.5) / n
		var p: Vector2 = c + Vector2.from_angle(a) * rr
		g.hud.draw_circle(p, ar + 1.5, UI.GOLD)
		_avatar(ops[i], p, ar)


## 触屏：终结技大圆键 + 连携小圆键（位置同 touch.ult_btn / combo_btn）
func _draw_touch(vs: Vector2) -> void:
	var u = g.ult
	var ld = g.squad.leader()
	var ub: Dictionary = g.touch.ult_btn(vs)
	var cb: Dictionary = g.touch.combo_btn(vs)
	var c: Vector2 = ub.c
	var r: float = ub.r
	var full: bool = u.full()
	var up: bool = _up()
	var held: bool = g.touch.skill_id >= 0 or g.touch.flash.get("skill", 0.0) > 0.0
	var pulse: float = 0.5 + 0.5 * sin(g.t * 4.0)
	var acc: Color = UI.GOLD if up else UI.CYAN
	var ek: float = clampf(u.energy / 100.0, 0.0, 1.0)
	var bg := Tris.new()
	var fg := Tris.new()
	var txt: Array[Callable] = []
	bg.circle(c, r, Color(0.05, 0.12, 0.16, 0.82 if full or held else 0.55), 32)
	var cc: Vector2 = cb.c
	var cr: float = cb.r
	var qn: int = _q().size()
	var clit: bool = qn > 0
	bg.circle(cc, cr, Color(0.05, 0.12, 0.16, 0.82 if clit else 0.5), 24)
	# 后面排队的：连携键左边一列小头像（静止亮着）
	var rest: Array = []
	for i in range(1, mini(qn, 4)):
		rest.append({"q": _q()[i], "c": cc + Vector2(-cr - 14.0 - (i - 1) * 24.0, 0.0), "r": 9.0, "head": false})
	bg.flush(g.hud)
	if ld != null:
		_avatar(ld, c, r - 5.0, Color.WHITE if full else Color(0.5, 0.53, 0.57))
	if clit:
		var q: Dictionary = _q()[0]
		var since: float = _lit_t() - float(q.left)
		_avatar(q.o, cc + Vector2(0, -4.0 * sin(PI * clampf(since / 0.25, 0.0, 1.0))), cr - 3.0)
	_queue_avatars(rest)
	if up:
		_squad_ring(c, r + 17.0, 9.0)
	# ---- 终结技键：外圈能量 / 满了呼吸光；协同格弧（键上方）；升级态金色描边
	fg.arc(c, r + 4.0, 0.0, TAU, 4.0, Color(0.02, 0.03, 0.04, 0.6), 40)
	fg.arc(c, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU * ek, 4.0, Color(acc.r, acc.g, acc.b, 0.95) if full else Color(0.55, 0.85, 0.9, 0.8), 40)
	if full:
		fg.arc(c, r + 9.0 + 2.0 * pulse, 0.0, TAU, 2.0, Color(acc.r, acc.g, acc.b, 0.25 + 0.45 * pulse), 40)
	if up:
		fg.arc(c, r, 0.0, TAU, 2.5, Color(1.0, 0.95, 0.75, 0.95), 40)
	elif _cells() > 0 or full:
		var a0: float = -PI / 2.0 - 1.15
		var seg: float = 2.3 / float(_n())
		for i in _n():
			var sa: float = a0 + i * seg + 0.03
			fg.arc(c, r + 11.0, sa, sa + seg - 0.06, 3.0, UI.GOLD if i < _cells() else Color(0.2, 0.22, 0.25, 0.8), 4)
	# 按住拖动：键上画小摇杆（同手动技能键）
	if g.touch.skill_id >= 0 and u.phase == "aim" and u.aim_kind != "none":
		var reach: float = r + 30.0
		fg.arc(c, reach, 0.0, TAU, 1.5, Color(acc.r, acc.g, acc.b, 0.35), 40)
		var kn: Vector2 = g.touch.skill_aim.limit_length(reach)
		fg.circle(c + kn, 13.0, Color(acc.r, acc.g, acc.b, 0.45), 16)
		fg.arc(c + kn, 13.0, 0.0, TAU, 2.0, Color(1, 1, 1, 0.9), 20)
	var lab: String = "连携终结技" if up else "终结技"
	var lcol: Color = (UI.GOLD if up else UI.TEXT) if full else UI.SUB
	txt.append(func(): UI.text(g.hud, g.font, c + Vector2(-50.0, r + 19.0), lab, 13, lcol, HORIZONTAL_ALIGNMENT_CENTER, 100.0))
	# ---- 连携键
	if clit:
		var q: Dictionary = _q()[0]
		var oc: Color = q.o.col().lerp(Color.WHITE, 0.35)
		var k: float = clampf(float(q.left) / _lit_t(), 0.0, 1.0)
		fg.arc(cc, cr + 3.0, 0.0, TAU, 3.0, Color(0.02, 0.03, 0.04, 0.7), 32)
		fg.arc(cc, cr + 3.0, -PI / 2.0, -PI / 2.0 + TAU * k, 3.0, Color(oc.r, oc.g, oc.b, 0.35 + 0.65 * k), 32)
	else:
		fg.arc(cc, cr, 0.0, TAU, 1.5, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), 24)
		txt.append(func(): UI.text(g.hud, g.font, cc + Vector2(-30.0, 5.0), "连携", 13, Color(1, 1, 1, 0.45), HORIZONTAL_ALIGNMENT_CENTER, 60.0))
	if g.touch.flash.get("combo", 0.0) > 0.0:
		fg.arc(cc, cr + 6.0, 0.0, TAU, 2.0, Color(1, 1, 1, 0.6), 24)
	_queue_rings(fg, txt, rest, "")
	fg.flush(g.hud)
	h.text_flush(txt)


# ================================================================ 立绘切入（§7.1 / §7.3）

var _art := {}   # 干员 id → {"tex", "bb", "hi"}（图鉴同款待机帧 @2x）


func _art_of(o) -> Dictionary:
	var oid := str(o.id)
	if _art.has(oid):
		return _art[oid]
	var out := {}
	var spec: Dictionary = o.sprite_spec("idle")
	var tn: String = str(spec.get("tex", ""))
	var tx: Texture2D = A.tex_hi(tn) if tn != "" else null
	if tx != null:
		var frames: int = int(o.portrait().frames)
		if o.sprite_mirror("idle"):
			tx = A.mirror_strip(tx, frames)
		var hi: float = A.hires_of(tx)
		tx = _base(tx)
		out = {"tex": tx, "bb": UI.idle_bb(tx, frames), "hi": hi}
	_art[oid] = out
	return out


func _op_by_id(oid: String):
	for o in g.squad.ops:
		if str(o.id) == oid:
			return o
	return null


const CUT_IN := 0.14    # 滑入（界面秒）
const CUT_OUT := 0.16   # 滑出
const CUT_SLANT := 30.0


func draw_cutins(vs: Vector2) -> void:
	if not _on() or (g.state != Game.S.PLAY and g.state != Game.S.PAUSE):
		return
	if _demo_on() and g.state == Game.S.PLAY and g.t > 20.0:
		_demo_tick()
	# 终结技冲击帧闪白（10-29）：0.22 秒淡出；减少动态效果开时不闪（世界层另画暗色描边扩散），Boss 战减半
	var ft: float = UM.now() - float(g.ult.flash_rt)
	if ft >= 0.0 and ft < 0.22 and not Cfg.reduce_motion:
		var fcol: Color = g.ult._col(g.ult.caster).lerp(Color(0.9, 0.88, 0.82), 0.55) if g.ult.caster != null else Color(0.9, 0.88, 0.82)
		g.hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(fcol, 0.26 * (1.0 - ft / 0.22) * (0.5 if _boss_on() else 1.0)))   # 闪光：干员色偏暖、封顶不发白（10-30 美术口径）
	var cs: Array = g.ult.cutins
	if cs.is_empty():
		return
	var now: float = UM.now()
	var dim: float = 0.7 if _boss_on() else 1.0
	var rm: bool = Cfg.reduce_motion
	var W: float = vs.x / 3.0
	var H: float = clampf(vs.y * 0.15, 72.0, 112.0)
	var step: float = H * 0.72
	var y0: float = vs.y * 0.26
	var ld = g.squad.leader()
	for ci in cs:
		var tt: float = now - float(ci.t0)
		var dur: float = float(ci.dur)
		if tt < 0.0 or tt > dur:
			continue
		if not ci.has("side"):
			# 队长在左半屏 → 条带从右边切入（同一次连携终结技的几条跟队首同侧）。
			# 触屏：右侧是终结技 / 连携 / 冲刺键（按住瞄准时不能被盖住），队长不在左侧 35% 以内就一律从左边切入
			var right: bool = true
			if ld != null and ld.pos != Vector2.INF:
				right = (g.hud_ct() * ld.pos).x < vs.x * (0.35 if g.touch.active else 0.5)
			for cj in cs:
				if absf(float(cj.t0) - float(ci.t0) + 0.12 * int(ci.i) - 0.12 * int(cj.i)) < 0.01 and cj.has("side"):
					right = bool(cj.side)
			ci["side"] = right
		var right2: bool = ci.side
		var i: int = int(ci.i)
		var a: float = dim
		var off: float = 0.0   # 0 = 停留位，1 = 完全在屏外
		if tt < CUT_IN:
			var k: float = tt / CUT_IN
			off = 0.0 if rm else pow(1.0 - k, 3.0)
			a *= k if rm else 1.0
		elif tt > dur - CUT_OUT:
			var k2: float = (tt - (dur - CUT_OUT)) / CUT_OUT
			off = 0.0 if rm else k2 * k2
			a *= (1.0 - k2) if rm else (1.0 - 0.5 * k2)
		if ci.get("small", false):   # 连携：小号条带，压在屏幕中下
			_strip(ci, vs, right2, vs.y * 0.60, W * 0.62, H * 0.6, off, a)
		else:
			_strip(ci, vs, right2, y0 + i * step, W - i * 22.0, H, off, a)


## 一条斜切条带：贴着 right（右边缘 / 左边缘），内侧斜切；立绘在靠屏边那头，名字在内侧
func _strip(ci: Dictionary, vs: Vector2, right: bool, y: float, w: float, hh: float, off: float, a: float) -> void:
	var col: Color = ci.col
	var sx: float = (w + CUT_SLANT + 20.0) * off * (1.0 if right else -1.0)
	var e: float = vs.x if right else 0.0   # 屏边
	var inner: float = (vs.x - w) if right else w
	var sg: float = -1.0 if right else 1.0   # 朝屏内的方向
	# 平行四边形：屏边一侧伸出屏外 30（滑动时不露边），内侧上沿比下沿多出 CUT_SLANT
	var p := PackedVector2Array([
		Vector2(e - sg * 30.0 + sx, y), Vector2(inner + sg * CUT_SLANT + sx, y),
		Vector2(inner + sx, y + hh), Vector2(e - sg * 30.0 + sx, y + hh)])
	var tb := Tris.new()
	tb.poly(p, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.92 * a))
	# 内侧亮边 + 上下细线
	tb.line(p[1], p[2], Color(col.lerp(Color.WHITE, 0.55), 0.95 * a), 4.0)
	tb.line(p[0], p[1], Color(col.lerp(Color.WHITE, 0.3), 0.7 * a), 2.0)
	tb.line(p[3], p[2], Color(col.lerp(Color.WHITE, 0.3), 0.7 * a), 2.0)
	# 斜纹（干员色亮一档），沿条带走
	var nstr: int = int(w / 26.0)
	for k in nstr:
		var x: float = minf(inner, e) + (k + 0.5) * w / nstr + sx
		var mid := Color(col.lerp(Color.WHITE, 0.2), 0.10 * a)
		tb.line(Vector2(x + 10.0, y + 3.0), Vector2(x - 10.0, y + hh - 3.0), mid, 6.0)
	tb.flush(g.hud)
	# 立绘：图鉴同款待机帧（@2x），取上半身，按条带高放大；裁在条带框内（不出框）
	var box := Rect2(minf(e, inner) + sx, y + 3.0, w, hh - 6.0)
	var ids: Array = [str(ci.id)]
	if ci.has("id2"):
		ids.append(str(ci.id2))   # 组合升级：两人同框
	var push := 0.0
	for oid in ids:
		push = _strip_art(_op_by_id(oid), e, sg, sx, y, hh, box, a, push)
	# 名字：内侧，大号白字
	var nm: String = str(ci.name)
	var fs: int = 28 if hh >= 90.0 else (24 if hh >= 60.0 else 18)
	var tw := 260.0
	var tx0: float = (inner + 40.0 - tw * 0.0) if not right else (inner + 46.0)
	if not right:
		tx0 = inner - 46.0 - tw
	UI.text(g.hud, g.font, Vector2(tx0 + sx, y + hh * 0.5 + fs * 0.38), nm, fs, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_LEFT if right else HORIZONTAL_ALIGNMENT_RIGHT, tw, 5)


## 条带上的一张立绘（push = 已画立绘占去的宽度，第二张往屏内挪）；返回新的 push
func _strip_art(o, e: float, sg: float, sx: float, y: float, hh: float, box: Rect2, a: float, push: float) -> float:
	if o != null:
		var art: Dictionary = _art_of(o)
		if not art.is_empty() and art.bb.size.y > 0.0:
			var bb: Rect2 = art.bb
			var src_h: float = bb.size.y * 0.62
			var k: float = (hh - 6.0) / src_h
			var dw: float = bb.size.x * k
			var px: float = (e + sg * (dw * 0.5 + 34.0 + push)) + sx   # 中心离屏边 34 + 半宽（第二张再往里挪）
			push += dw * 0.8
			var dst := Rect2(px - dw * 0.5, y + 3.0, dw, hh - 6.0)
			var src := Rect2(bb.position, Vector2(bb.size.x, src_h))
			var cl: Rect2 = dst.intersection(box)
			if cl.has_area():
				var s0: Vector2 = src.position + (cl.position - dst.position) / k
				var t: Texture2D = art.tex
				g.hud.draw_texture_rect_region(t, Rect2(cl.position + Vector2(4, 4), cl.size), Rect2(s0, cl.size / k), Color(0, 0, 0, 0.35 * a))
				g.hud.draw_texture_rect_region(t, cl, Rect2(s0, cl.size / k), Color(1, 1, 1, a))
	return push
