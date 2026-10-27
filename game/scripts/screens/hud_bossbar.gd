extends RefCounted
## 界面 · Boss 血条（10-28 用户：「boss的血条的UI是不是也可以更有设计感一点」，三稿里选定 B「刻纹槽」）：
## 名字（· 称号，取数据里「名字，称号」，不另编，docs/76）居中，右侧一行状态小字；下面一根槽，槽里铺该 Boss 的纹样（暗），血量部分纹样亮起，
## 两端主色角括号。主色 = 该 Boss 的专属弹幕色（enemies.json bcol），纹样按 MOTIF（骑士冰棱 / 泡影泡 / 伊莎玛拉海浪 / 伊祖米克根须 / 圣徒火纹与十字 …）。
## 信息：阶段刻度（条上小菱形，阶段护盾时金色）；掉血白残影（BT_HOLD 后追上）+ 受击白闪；护盾层（shield_layers / shield_max）条右上小格，
## 破一层碎片飞散；无敌斜纹流动；破绽金框呼吸；假死闪；韧性（tough）条下细金线；伊祖米克吸收层菱形。双体（圣徒）一个括号里两根细条 + 连体标。
## 动效：入场条从中间展开 0.45 秒、转阶段刻度处炸开一圈 0.6 秒、击败条碎成数段落下 0.8 秒；都在条的范围里，不抢战斗视线。
## 每行几十个矩形 / 线 / 多边形，不建贴图，网页开销与旧条同级。--bbstyle=0（开发版）回旧细条；--bbdemo 画五只最终 Boss 的状态演示
const UI = preload("res://scripts/ui.gd")
const D = preload("res://scripts/data.gd")
var g
var h

const MOTIF := {"knight_boss": "ice", "paranoia": "bubble", "ishar": "wave", "izumik": "root", "iberia": "flame", "carmen": "cross",
	"path": "frac", "bishop": "wave", "archon": "wave", "immortal": "wave"}
const ROW_H := 40.0
const PAIR_H := 44.0
const BT_HOLD := 0.45
const BT_RATE := 0.6
const ENTER_T := 0.45
const PHASE_T := 0.6
const SHBRK_T := 0.5
const OUT_T := 0.8

var _st := {}     # id -> 动效状态
var _seen := {}   # 上一帧画过的 id -> 视图（消失时转击败动效）
var _out: Array = []   # [视图, 开始时刻]


func _init(hud) -> void:
	h = hud
	g = hud.g


static func theme_col(type: String) -> Color:
	var c = D.ENEMIES.get(type, {}).get("bcol", null)
	if c is Color:
		return c
	return Color(float(c[0]), float(c[1]), float(c[2])) if c is Array else UI.RED


## 「名字，称号」拆开（称号只取数据里已有的，不另编，docs/76）
static func split_name(nm: String) -> Array:
	var s := nm.replace("\"", "").replace("「", "").replace("」", "")
	var i := s.find("，")
	return [s, ""] if i < 0 else [s.substr(0, i), s.substr(i + 1)]


## 实战视图：从敌人字典取血条要的字段
func view_of(e: Dictionary) -> Dictionary:
	var nt: Array = split_name(str(e.name))
	return {"id": e.id, "type": str(e.type), "name": nt[0], "title": nt[1], "hp": clampf(e.hp / maxf(1.0, e.maxhp), 0.0, 1.0),
		"gates": e.get("gates", []), "gp": int(e.get("gates_passed", 0)), "sh": int(e.get("shield_layers", 0)), "sh_max": int(e.get("shield_max", 0)),
		"inv": bool(e.get("invuln", false)) or e.get("gate_hold", false), "hold": e.get("gate_hold", false), "brk": float(e.get("break_t", 0.0)),
		"coma": e.get("coma", false), "layers": int(e.get("izu_layers", -1)) if e.has("izu_layers") else -1,
		"tough": clampf(float(e.get("tough", 0.0)) / float(e.tough_need), 0.0, 1.0) if float(e.get("tough_need", 0.0)) > 0.0 and float(e.get("break_t", 0.0)) <= 0.0 else 0.0}


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## 画若干行（每项是一个视图，或成对的 [视图, 视图] = 双体同一行）；返回用掉的高度
func draw_views(rows: Array, x: float, y: float, w: float) -> float:
	var t := now()
	var hit := {}
	var yy := y
	for row in rows:
		var vs: Array = row if row is Array else [row]
		for v in vs:
			hit[v.id] = true
			_seen[v.id] = [v, yy - y]
		var rh: float = PAIR_H if vs.size() == 2 else ROW_H
		if vs.size() == 2:
			_row_pair(vs[0], vs[1], Rect2(x, yy, w, rh), t)
		else:
			_row(vs[0], Rect2(x, yy, w, rh), t)
		yy += rh
	for id in _seen.keys():
		if not hit.has(id):
			_out.append([_seen[id][0], t, float(_seen[id][1])])
			_seen.erase(id)
			_st.erase(id)
	var keep: Array = []
	for o in _out:
		var k: float = (t - float(o[1])) / OUT_T
		if k < 1.0:
			_draw_outro(o[0], Rect2(x, y + float(o[2]), w, ROW_H), k)
			keep.append(o)
	_out = keep
	return yy - y


func _state(v: Dictionary, t: float) -> Dictionary:
	var s: Dictionary = _st.get(v.id, {})
	if s.is_empty():
		s = {"enter": t, "gp": v.gp, "sh": v.sh, "phase_t": -9.0, "sh_t": -9.0, "trail": v.hp, "last": v.hp, "hold": 0.0, "flash": -9.0, "t": t, "inv": v.inv}
		_st[v.id] = s
	var dt: float = clampf(t - float(s.t), 0.0, 0.1)
	s.t = t
	if v.hp < float(s.last) - 0.0005:
		s.flash = t
		s.hold = BT_HOLD
	elif v.hp > float(s.trail):
		s.trail = v.hp
	s.last = v.hp
	if float(s.hold) > 0.0:
		s.hold = float(s.hold) - dt
	else:
		s.trail = maxf(v.hp, float(s.trail) - BT_RATE * dt)
	if int(v.gp) > int(s.gp):
		s.phase_t = t
	s.gp = v.gp
	s.inv = v.inv
	if int(v.sh) < int(s.sh):
		s.sh_t = t
		s.sh_lost = int(s.sh)
	s.sh = v.sh
	return s


# ---------------------------------------------------------------- 一行

func _anim(v: Dictionary, t: float) -> Array:
	var s := _state(v, t)
	var ek: float = clampf((t - float(s.enter)) / ENTER_T, 0.0, 1.0)
	ek = 1.0 - pow(1.0 - ek, 3.0)
	return [s, ek, clampf((t - float(s.phase_t)) / PHASE_T, 0.0, 1.0), clampf((t - float(s.sh_t)) / SHBRK_T, 0.0, 1.0), clampf(1.0 - (t - float(s.flash)) / 0.12, 0.0, 1.0)]


## 条区域按入场进度从中间展开
static func _expand(br: Rect2, ek: float) -> Rect2:
	var w: float = br.size.x * ek
	return Rect2(br.position.x + (br.size.x - w) / 2.0, br.position.y, w, br.size.y)


## 共用：底 → 残影 → 血量 → 受击闪 → 无敌斜纹 → 护盾格 → 阶段刻度 / 转阶段炸开 → 破绽金框
func _fill(v: Dictionary, br: Rect2, col: Color, s: Dictionary, pk: float, sk: float, fl: float, t: float, motif_track := false) -> void:
	var ci = g.hud
	var hp: float = v.hp
	ci.draw_rect(br.grow(1.0), Color(0.02, 0.02, 0.03, 0.88))
	if motif_track:
		motif(v.type, br, Color(col.r, col.g, col.b, 0.16), t)
	else:
		ci.draw_rect(br, Color(1, 1, 1, 0.07))
	ci.draw_rect(Rect2(br.position, Vector2(br.size.x * float(s.trail), br.size.y)), Color(1, 1, 1, 0.5))
	var fc: Color = col
	if v.brk > 0.0:
		fc = col.lerp(UI.GOLD, 0.65)
	elif v.inv:
		fc = col.lerp(Color(0.5, 0.56, 0.62), 0.7)
	elif v.coma:
		fc = col.lerp(Color.WHITE, 0.3 + 0.3 * sin(t * 12.0))
	var hr := Rect2(br.position, Vector2(br.size.x * hp, br.size.y))
	ci.draw_rect(hr, fc)
	if motif_track and hr.size.x > 2.0:
		motif(v.type, hr, Color(1, 1, 1, 0.28), t)
	if fl > 0.0:
		ci.draw_rect(hr, Color(1, 1, 1, 0.6 * fl))
	if v.inv:
		# 无敌：斜纹往右流，整条压灰
		var off: float = fmod(t * 24.0, 10.0)
		var x0: float = br.position.x - 10.0 + off
		while x0 < br.end.x:
			var a := Vector2(maxf(x0, br.position.x), br.end.y)
			var b := Vector2(minf(x0 + br.size.y, br.end.x), br.position.y)
			if b.x > a.x:
				ci.draw_line(a, b, Color(0.85, 0.92, 1.0, 0.35), 1.5)
			x0 += 10.0
	# 护盾层：条右端从右往左排小格，亮 = 剩余
	var smax: int = int(v.get("sh_max", 0))
	if smax > 0:
		var cw: float = 10.0
		for i in smax:
			var cr := Rect2(br.end.x - (i + 1) * (cw + 2.0), br.position.y - 5.0, cw, 3.0)
			var lit: bool = i < int(v.sh)
			ci.draw_rect(cr, Color(0.75, 0.95, 1.0, 0.95) if lit else Color(1, 1, 1, 0.12))
		if sk < 1.0 and s.has("sh_lost"):
			var i2: int = int(s.sh_lost) - 1
			var c0 := Vector2(br.end.x - (i2 + 1) * (cw + 2.0) + cw / 2.0, br.position.y - 4.0)
			for k in 6:
				var ang: float = -PI * 0.15 - k * PI * 0.14
				var p: Vector2 = c0 + Vector2.from_angle(ang) * (4.0 + 22.0 * sk) + Vector2(0, 14.0 * sk * sk)
				ci.draw_colored_polygon(PackedVector2Array([p, p + Vector2(3, 1), p + Vector2(1, 3)]), Color(0.8, 0.97, 1.0, 1.0 - sk))
	# 阶段刻度（剩余的门）+ 刚转阶段：刻度处一圈炸开
	var gl: Array = v.get("gates", [])
	for gi in gl.size():
		var gx: float = br.position.x + br.size.x * float(gl[gi])
		var lit2: bool = v.get("hold", false) and gi == 0
		ci.draw_rect(Rect2(gx - 0.5, br.position.y - 2.0, 1.0, br.size.y + 4.0), UI.GOLD if lit2 else Color(1, 1, 1, 0.9))
	if pk < 1.0:
		var px: float = br.position.x + br.size.x * clampf(float(v.get("last_gate", hp)), 0.0, 1.0)
		var c1 := Vector2(px, br.get_center().y)
		ci.draw_arc(c1, 4.0 + 26.0 * pk, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.9 * (1.0 - pk)), 2.0)
		ci.draw_rect(br.grow(2.0 + 3.0 * pk), Color(1, 1, 1, 0.35 * (1.0 - pk)), false, 1.0)
	# 破绽：金框呼吸
	if v.brk > 0.0:
		var pa: float = 0.55 + 0.35 * sin(t * 9.0)
		ci.draw_rect(br.grow(3.0), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, pa), false, 1.5)


## 状态小牌（无敌 / 破绽 n 秒 / 阶段护盾 / 假死），返回 [文字, 颜色]；没有为空
func _tag(v: Dictionary) -> Array:
	if v.brk > 0.0:
		return ["破绽 %.1f" % v.brk, UI.GOLD]
	if v.get("hold", false):
		return ["阶段护盾", UI.GOLD]
	if v.inv:
		return ["无敌", Color(0.75, 0.85, 0.95)]
	if v.coma:
		return ["假死", Color(1, 0.82, 0.88)]
	if int(v.get("sh", 0)) > 0:
		return ["护盾 ×%d" % int(v.sh), Color(0.75, 0.95, 1.0)]
	return []


func _row(v: Dictionary, r: Rect2, t: float) -> void:
	var an: Array = _anim(v, t)
	var a: float = an[1]
	var col: Color = theme_col(v.type)
	var label: String = v.name + ("  ·  " + v.title if v.title != "" else "")
	UI.text(g.hud, g.font, Vector2(r.position.x, r.position.y + 13.0), label, 14, Color(1, 0.94, 0.96, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	_status(v, r, a)
	var br := _expand(Rect2(r.position.x + 10.0, r.position.y + 20.0, r.size.x - 20.0, 9.0), a)
	_fill(v, br, col, an[0], an[2], an[3], an[4], t, true)
	_brackets(br, col, a)
	_extras(v, br, a)


## 双体（同生共死）：一个括号里上下两根 5 像素细条，左侧连体标；名字「甲 · 乙」
func _row_pair(v1: Dictionary, v2: Dictionary, r: Rect2, t: float) -> void:
	var ci = g.hud
	var a1: Array = _anim(v1, t)
	var a2: Array = _anim(v2, t)
	var a: float = minf(a1[1], a2[1])
	UI.text(ci, g.font, Vector2(r.position.x, r.position.y + 13.0), v1.name + "  ·  " + v2.name, 14, Color(1, 0.94, 0.96, a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)
	var s1: Array = v1.get("sub", [])
	_status(v1 if (not s1.is_empty() and str(s1[0]) != "") or not _tag(v1).is_empty() else v2, r, a)
	var b1 := _expand(Rect2(r.position.x + 22.0, r.position.y + 20.0, r.size.x - 32.0, 5.0), a)
	var b2 := _expand(Rect2(r.position.x + 22.0, r.position.y + 28.0, r.size.x - 32.0, 5.0), a)
	_fill(v1, b1, theme_col(v1.type), a1[0], a1[2], a1[3], a1[4], t, true)
	_fill(v2, b2, theme_col(v2.type), a2[0], a2[2], a2[3], a2[4], t, true)
	_brackets(Rect2(b1.position, Vector2(b1.size.x, b2.end.y - b1.position.y)), theme_col(v1.type).lerp(theme_col(v2.type), 0.5), a)
	var lc := Color(1, 0.86, 0.9, 0.95 * a)
	ci.draw_rect(Rect2(r.position.x + 6.0, b1.position.y + 0.5, 4.0, 4.0), lc)
	ci.draw_rect(Rect2(r.position.x + 6.0, b2.position.y + 0.5, 4.0, 4.0), lc)
	ci.draw_rect(Rect2(r.position.x + 7.5, b1.position.y + 2.0, 1.0, b2.position.y - b1.position.y), lc)


## 右侧状态小字：实战取 hud_bars._boss_sub（招式名 / 阶段说明 / 破绽…，v.sub），否则按状态生成
func _status(v: Dictionary, r: Rect2, a: float) -> void:
	var tg: Array = v.get("sub", [])
	if tg.is_empty() or str(tg[0]) == "":
		tg = _tag(v)
	if tg.is_empty():
		return
	var c: Color = tg[1]
	UI.text(g.hud, g.font, Vector2(r.end.x - 300.0, r.position.y + 13.0), str(tg[0]), 11, Color(c.r, c.g, c.b, c.a * a), HORIZONTAL_ALIGNMENT_RIGHT, 300, 2)


## 两端主色角括号
func _brackets(br: Rect2, col: Color, a: float) -> void:
	var ci = g.hud
	var bc := Color(col.r, col.g, col.b, 0.95 * a)
	for side in [-1.0, 1.0]:
		var x: float = br.position.x - 5.0 if side < 0.0 else br.end.x + 5.0
		ci.draw_line(Vector2(x, br.position.y - 4.0), Vector2(x, br.end.y + 4.0), bc, 2.0)
		ci.draw_line(Vector2(x, br.position.y - 4.0), Vector2(x - side * 6.0, br.position.y - 4.0), bc, 2.0)
		ci.draw_line(Vector2(x, br.end.y + 4.0), Vector2(x - side * 6.0, br.end.y + 4.0), bc, 2.0)


## 阶段菱形、韧性细金线、伊祖米克吸收层
func _extras(v: Dictionary, br: Rect2, a: float) -> void:
	var ci = g.hud
	for gi in v.gates.size():
		var gx: float = br.position.x + br.size.x * float(v.gates[gi])
		UI.diamond(ci, Vector2(gx, br.position.y - 4.0), 3.5, UI.GOLD if v.get("hold", false) and gi == 0 else Color(1, 1, 1, 0.9 * a))
	var tk: float = float(v.get("tough", 0.0))
	if tk > 0.0:
		ci.draw_rect(Rect2(br.position.x, br.end.y + 2.0, br.size.x * tk, 1.0), Color(0.95, 0.85, 0.55, a))
	var ly: int = int(v.get("layers", -1))
	if ly >= 0:
		for q in 5:
			var lit: bool = q < ly
			UI.diamond(ci, Vector2(br.position.x + 4.0 + q * 9.0, br.position.y - 8.0), 3.0, Color(0.55, 1.0, 0.95, a) if lit else Color(1, 1, 1, 0.08 * a), Color(0.6, 1.0, 1.0, (0.8 if lit else 0.3) * a))


## 击败：条碎成 8 段往下落、淡出；名字一起淡
func _draw_outro(v: Dictionary, r: Rect2, k: float) -> void:
	var ci = g.hud
	var col: Color = theme_col(v.type)
	var y: float = r.position.y + 20.0
	var x0: float = r.position.x + 10.0
	var w: float = r.end.x - 10.0 - x0
	var n := 8
	for i in n:
		var sw: float = w / n
		var dx: float = (float(i) - n / 2.0 + 0.5) * 6.0 * k
		var dy: float = 30.0 * k * k * (0.6 + 0.08 * i)
		var rot: float = (0.4 if i % 2 == 0 else -0.4) * k
		var c := Vector2(x0 + sw * (i + 0.5) + dx, y + 3.0 + dy)
		var hw := Vector2(sw / 2.0 - 1.0, 0).rotated(rot)
		var hh := Vector2(0, 3.0).rotated(rot)
		ci.draw_colored_polygon(PackedVector2Array([c - hw - hh, c + hw - hh, c + hw + hh, c - hw + hh]), Color(col.r, col.g, col.b, 1.0 - k))
	var fk: float = 1.0 - k
	UI.text(ci, g.font, Vector2(r.position.x, y - 6.0), v.name + "  ·  已击败", 13, Color(1, 1, 1, fk), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 2)


# ---------------------------------------------------------------- 纹样

## 各 Boss 的纹样（程序画，几十个图元）：ice 冰棱 / bubble 泡 / wave 海浪 / root 根须 / flame 火纹 / cross 十字 / frac 分形格；
## emblem = true 时画成单枚徽记（铭牌色块 / 细线样式的名字前）
func motif(type: String, r: Rect2, c: Color, t: float, emblem := false) -> void:
	var ci = g.hud
	var m: String = MOTIF.get(type, "frac")
	var cy: float = r.get_center().y
	if emblem:
		var cc: Vector2 = r.get_center()
		var s: float = minf(r.size.x, r.size.y) * 0.5
		match m:
			"ice":
				for k in 3:
					var ang: float = -PI / 2.0 + (k - 1) * 0.5
					var tip: Vector2 = cc + Vector2.from_angle(ang) * s
					var sd: Vector2 = Vector2.from_angle(ang + PI / 2.0) * s * 0.22
					ci.draw_colored_polygon(PackedVector2Array([cc + Vector2(0, s * 0.5) + sd, tip, cc + Vector2(0, s * 0.5) - sd]), c)
			"bubble":
				ci.draw_arc(cc, s * 0.7, 0.0, TAU, 20, c, 1.5)
				ci.draw_circle(cc + Vector2(s * 0.35, -s * 0.35), s * 0.22, c)
				ci.draw_arc(cc + Vector2(-s * 0.3, s * 0.4), s * 0.3, 0.0, TAU, 12, c, 1.0)
			"wave":
				for k in 3:
					var pts := PackedVector2Array()
					for i in 9:
						var x: float = cc.x - s + i * s / 4.0
						pts.append(Vector2(x, cc.y - s * 0.5 + k * s * 0.5 + sin(i * 1.1 + t * 2.0) * s * 0.18))
					ci.draw_polyline(pts, c, 1.5)
			"root":
				ci.draw_line(cc + Vector2(0, -s), cc + Vector2(0, s), c, 1.5)
				for k in 3:
					var yk: float = cc.y - s * 0.6 + k * s * 0.6
					ci.draw_line(Vector2(cc.x, yk), Vector2(cc.x + (s * 0.7 if k % 2 == 0 else -s * 0.7), yk + s * 0.35), c, 1.0)
					ci.draw_circle(Vector2(cc.x + (s * 0.7 if k % 2 == 0 else -s * 0.7), yk + s * 0.35), 1.8, c)
			"flame":
				ci.draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -s), cc + Vector2(s * 0.55, s * 0.3), cc + Vector2(0, s * 0.8), cc + Vector2(-s * 0.55, s * 0.3)]), c)
				ci.draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -s * 0.2), cc + Vector2(s * 0.25, s * 0.4), cc + Vector2(0, s * 0.6), cc + Vector2(-s * 0.25, s * 0.4)]), Color(0, 0, 0, 0.5 * c.a))
			"cross":
				ci.draw_rect(Rect2(cc + Vector2(-s * 0.14, -s), Vector2(s * 0.28, s * 2.0)), c)
				ci.draw_rect(Rect2(cc + Vector2(-s * 0.7, -s * 0.45), Vector2(s * 1.4, s * 0.28)), c)
			_:
				ci.draw_rect(Rect2(cc - Vector2(s, s) * 0.7, Vector2(s, s) * 1.4), c, false, 1.5)
				ci.draw_rect(Rect2(cc - Vector2(s, s) * 0.3, Vector2(s, s) * 0.6), c)
		return
	match m:
		"ice":
			var x: float = r.position.x
			var i := 0
			while x < r.end.x - 4.0:
				var hgt: float = r.size.y * (0.6 if i % 2 == 0 else 1.0)
				ci.draw_colored_polygon(PackedVector2Array([Vector2(x, r.end.y), Vector2(x + 3.0, r.end.y - hgt), Vector2(x + 6.0, r.end.y)]), c)
				x += 9.0
				i += 1
		"bubble":
			var x: float = r.position.x + 4.0
			var i := 0
			while x < r.end.x - 3.0:
				ci.draw_arc(Vector2(x, cy + (1.5 if i % 2 == 0 else -1.5)), 2.0 if i % 3 else 3.0, 0.0, TAU, 8, c, 1.0)
				x += 11.0
				i += 1
		"wave":
			var pts := PackedVector2Array()
			var x: float = r.position.x
			while x <= r.end.x:
				pts.append(Vector2(x, cy + sin(x * 0.35 + t * 3.0) * r.size.y * 0.35))
				x += 4.0
			if pts.size() > 1:
				ci.draw_polyline(pts, c, 1.0)
		"root":
			ci.draw_line(Vector2(r.position.x, cy), Vector2(r.end.x, cy), c, 1.0)
			var x: float = r.position.x + 6.0
			var i := 0
			while x < r.end.x - 4.0:
				var dy: float = r.size.y * 0.45 * (1.0 if i % 2 == 0 else -1.0)
				ci.draw_line(Vector2(x, cy), Vector2(x + 4.0, cy + dy), c, 1.0)
				x += 13.0
				i += 1
		"flame":
			var x: float = r.position.x
			while x < r.end.x - 6.0:
				ci.draw_polyline(PackedVector2Array([Vector2(x, r.end.y), Vector2(x + 3.0, r.position.y), Vector2(x + 6.0, r.end.y)]), c, 1.0)
				x += 10.0
		"cross":
			var x: float = r.position.x + 5.0
			while x < r.end.x - 3.0:
				ci.draw_line(Vector2(x - 2.0, cy), Vector2(x + 2.0, cy), c, 1.0)
				ci.draw_line(Vector2(x, cy - 2.0), Vector2(x, cy + 2.0), c, 1.0)
				x += 12.0
		_:
			var x: float = r.position.x
			while x < r.end.x - 4.0:
				ci.draw_rect(Rect2(Vector2(x, cy - 1.5), Vector2(3, 3)), c)
				x += 8.0


# ---------------------------------------------------------------- 演示（--bbdemo）

## [类型, 阶段刻度, 护盾层数, 学习期无敌]；圣徒两体合一行
const DEMO := [["knight_boss", [0.66, 0.33], 0, false], ["paranoia", [0.5], 0, false], ["ishar", [], 3, false], ["izumik", [], 0, true], ["iberia", [], 0, false], ["carmen", [], 0, false]]
const DEMO_CYCLE := 14.0
const DEMO_FROM := 14.0


## 五只最终 Boss 一起演：入场 → 挨打（残影）→ 过阶段刻度（炸开）→ 护盾一层层破（伊莎玛拉）→ 学习期无敌转阐释（伊祖米克）→ 破绽 → 击败；
## 每 DEMO_CYCLE 秒一轮，按局内时间走（录像 --start 对齐 DEMO_FROM）
func draw_demo(vs: Vector2) -> void:
	var tt: float = maxf(0.0, g.t - DEMO_FROM)
	var loop: int = int(tt / DEMO_CYCLE)
	var u: float = fmod(tt, DEMO_CYCLE)
	var w: float = minf(560.0, vs.x * 0.5)
	var x: float = round(vs.x / 2.0 - w / 2.0)
	var rows: Array = []
	var pair: Array = []
	for i in DEMO.size():
		var d: Array = DEMO[i]
		var uu: float = u - mini(i, 4) * 0.25
		if uu < 0.0 or uu > 12.0:
			continue
		var nt: Array = split_name(str(D.ENEMIES.get(d[0], {}).get("name", d[0])))
		var v := {"id": "demo_%d_%d" % [loop, i], "type": d[0], "name": nt[0], "title": nt[1], "gates": [], "gp": 0, "sh": 0, "sh_max": int(d[2]),
			"inv": false, "hold": false, "brk": 0.0, "coma": false}
		# 掉血：每 0.6 秒一下，0.8 秒前满血
		var dmg: float = 0.0 if uu < 0.8 else floorf((uu - 0.8) / 0.6) * 0.058 + 0.03 * float(i % 2)
		var hp: float = clampf(1.0 - dmg, 0.0, 1.0)
		if d[3]:   # 伊祖米克：前 3.5 秒学习期无敌，血从 35% 涨满；之后转阐释
			if uu < 3.5:
				hp = 0.35 + 0.65 * uu / 3.5
				v.inv = true
				v.sub = ["学习阶段 · 无敌（击杀子代阻止它成长）", Color(0.75, 0.85, 0.95)]
			else:
				hp = clampf(1.0 - floorf((uu - 3.5) / 0.5) * 0.07, 0.0, 1.0)
				v.gp = 1
				v.last_gate = 1.0
			v.layers = 2
		if int(d[2]) > 0:   # 伊莎玛拉：护盾 3 层，2.5 / 3.5 / 4.5 秒各破一层，破完才掉血
			var broke: int = clampi(int(floorf((uu - 1.5) / 1.0)), 0, 3)
			v.sh = 3 - broke
			if v.sh > 0:
				hp = 1.0
			else:
				hp = clampf(1.0 - floorf((uu - 4.5) / 0.5) * 0.08, 0.0, 1.0)
		var gl: Array = []
		for gq in d[1]:
			if hp > float(gq):
				gl.append(gq)
			else:
				v.gp += 1
				v.last_gate = gq
		v.gates = gl
		if uu > 7.0 and uu < 9.0:
			v.brk = 9.0 - uu
		v.hp = hp
		if hp <= 0.0:
			continue   # 击败：从列表里消失 → draw_views 转碎裂动效
		if d[0] == "iberia" or d[0] == "carmen":
			pair.append(v)
		else:
			rows.append(v)
	if pair.size() == 2:
		rows.append(pair)
	elif pair.size() == 1:
		rows.append(pair[0])
	draw_views(rows, x, 98.0, w)
