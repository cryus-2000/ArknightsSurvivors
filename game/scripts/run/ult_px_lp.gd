## 拉普兰德终结技「狂舞乱砍」转平面画面（docs/273 §8，开关 ult/px_plane 或 ult/px_plane_lappland，缺省 0 = 原画面）。只改画面：
## 招式时间轴 / 判定 / 伤害 / 沉默 / 顿帧 / 冲击帧逻辑全照 ult_moves_c._la_*（docs/199 §7.11）。11-05 晚范围收窄（ult_brief 第 9 条）：
##   ① 配色对齐：原画面的银灰 / 冷蓝按亮度换成普攻 / 技能定稿的紫白色阶（tint，ult_moves_c._lc 调），造型、节奏、体量不动；
##   ② 最大那一下（收尾横斩，冲击帧照旧）之后的空气爆破改成收尾大爆：2 拍预备（光点往中心收 + 圈内压暗）→ 实心亮核 2 拍（尖芒星形，不是平涂大圆）
##      + 打满的照地灯 + 轻震 3px / 0.12 秒 → 厚压扁冲击环 4 拍推到爆破半径、环后地面一闪 → 闪烁的紫白粒子云往外喷；
##      末圈打中的怪在冲击环扫到时崩解（引擎原有击杀碎屑补一次 + 一圈怪物本色像素顺着冲击喷开）；
##   ③ 慢动作：冲击帧过后 ult/la_px_slow_t（0.5）秒 ult/la_px_slow（0.3）倍速，再 0.15 秒加速回原速。挂在 ult.time_scale（演出类，批跑 / TRACE 不缩）。
## 1 特效像素 = 1 美术像素（g.PX = 2 世界像素），15 fps 节拍，贴地层压扁 0.72；散布按坐标哈希，不抽随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol（崩解喷散取怪物自身颜色）
const UM = preload("res://scripts/ui_motion.gd")
const LP := [Color("#15121f"), Color("#2b2542"), Color("#4a4274"), Color("#7b70b4"), Color("#b3aae4"), Color("#e4e0ff"), Color("#ffffff")]   # 同 fx_pxplane_lp.LP
const LIGHT := Color(0.78, 0.74, 1.0)
const FPS := 15.0
const SQ := 0.72
const PRE := 2.0 / 15.0      # 预备 2 拍
const CORE := 2.0 / 15.0     # 亮核 2 拍
const RING := 4.0 / 15.0     # 冲击环 4 拍推到边
const CLOUD_N := 56          # 粒子云颗数（docs/270 爆发档：成片的闪烁光点不算 Noita 颗粒）
const HIT_MAX := 120
const SPRAY_N := 18
const SPRAY_MAX := 60
const EMIT_CAP := 240

var g
var st := {}          # 这一次：{c, dv, br, t0 (横斩游戏时刻), rt0 (横斩真实时刻), lit, hits: [{e, p, done}], sprays: []}
var _emit_n := 0
var _emit_frame := -1
var _lum := []


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0 or Bal.v("ult/px_plane_lappland", 0.0) > 0.0   # 总开关或拉普兰德一人


static func of(game):
	if game.has_meta("ult_px_lp"):
		return game.get_meta("ult_px_lp")
	var r = new()
	r.g = game
	game.set_meta("ult_px_lp", r)
	return r


## 配色对齐：按亮度落到紫白色阶上（相邻两阶插值），透明度照旧；> 1 的提亮色（原来压冷蓝贴图用的 1.25 / 1.0 / 0.85）改成提亮偏紫
static func tint(c: Color) -> Color:
	if c.r > 1.0 or c.g > 1.0 or c.b > 1.0:
		return Color(1.05, 1.0, 1.2, c.a)
	var l: float = clampf(0.3 * c.r + 0.59 * c.g + 0.11 * c.b, 0.0, 1.0)
	var prev: Color = LP[0]
	var pl: float = _l(prev)
	for k in range(1, LP.size()):
		var cur: Color = LP[k]
		var cl: float = _l(cur)
		if l <= cl:
			var u: float = 0.0 if cl - pl < 0.0001 else clampf((l - pl) / (cl - pl), 0.0, 1.0)
			var o: Color = prev.lerp(cur, u)
			return Color(o.r, o.g, o.b, c.a)
		prev = cur
		pl = cl
	return Color(1, 1, 1, c.a)


static func _l(c: Color) -> float:
	return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


# ================================================================ 事件（ult_moves_c._la_* 发；只记画面）

static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	of(u.g)._ev(u, kind, d)


func _ev(_u, kind: String, d: Dictionary) -> void:
	match kind:
		"hit":   # 末圈打中的怪（同一只只记一次；收尾大爆还没起时先存着）
			if st.get("pend", []).size() >= HIT_MAX:
				return
			var e: Dictionary = d.e
			if not st.has("pend"):
				st["pend"] = []
			for h in st.pend:
				if is_same(h.e, e):
					return
			st.pend.append({"e": e, "p": e.pos, "done": false})
		"final":   # 收尾横斩那一刻（冲击帧 / 顿帧由招式照旧打）；末圈命中在这之后才陆续记进来（同一个数组）
			var pend: Array = []
			st = {"c": d.c, "dv": d.dv, "br": float(d.br), "t0": g.t, "rt0": UM.now(), "lit": false, "hits": pend, "pend": pend, "sprays": []}


## 慢动作（ult.time_scale 调）：冲击帧顿帧（ult/la_hitstop）过后 hold 秒 lo 倍速，再 ez 秒加速回原速；按真实时间算
static func slow_scale(game) -> float:
	if not on() or not game.has_meta("ult_px_lp"):
		return 1.0
	var r = game.get_meta("ult_px_lp")
	if r.st.is_empty() or not r.st.has("rt0"):
		return 1.0
	if float(r.st.t0) < Bal.v("ult/la_px_slow_from", 0.0):   # 录像对照用（缺省 0）：只让某局时之后的终结技慢放，开 / 关两段才同一时刻
		return 1.0
	var t: float = UM.now() - float(r.st.rt0) - Bal.v("ult/la_hitstop", 0.1)
	var lo: float = Bal.v("ult/la_px_slow", 0.3)
	var hold: float = Bal.v("ult/la_px_slow_t", 0.5)
	var ez: float = Bal.v("ult/la_px_slow_ease", 0.15)
	if t < 0.0 or t >= hold + ez:
		return 1.0
	if t < hold:
		return lo
	var k: float = (t - hold) / ez
	return lerpf(lo, 1.0, k * k)


func _live() -> bool:
	if st.is_empty() or not st.has("t0"):
		return false
	if g.t - float(st.t0) > 2.2:
		st = {}
		return false
	return true


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	if _emit_n >= EMIT_CAP:
		return
	_emit_n += 1
	g.glow_next.append([p, g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


func _px(w, p: Vector2, c: Color, sz := 1.0) -> void:
	var q: Vector2 = (p / 2.0).round() * 2.0
	var s: float = g.PX * sz
	w.tb_quad(q, q + Vector2(s, 0), q + Vector2(s, s), q + Vector2(0, s), c)


## 拍子（出爆后第几拍，按全局 15 fps 节拍）
func _beat(t0: float) -> int:
	return int(floor(g.t * FPS + 0.0001)) - int(floor(t0 * FPS + 0.0001))


## 冲击环半径（世界像素）：亮核起后 RING 秒内从 0.25 br 推到 br，先快后慢
func _ring_r(ac: float) -> float:
	var br: float = st.br
	var k: float = clampf(ac / RING, 0.0, 1.0)
	return br * (0.25 + 0.75 * (1.0 - pow(1.0 - k, 3.0)))


# ================================================================ 绘制（ult.gd 转来）

## 地面层：预备时圈内压暗；冲击环（压扁厚环）+ 环后地面一闪
func draw_back(_u, w) -> void:
	if not _live():
		return
	var c: Vector2 = st.c
	var br: float = st.br
	var age: float = g.t - float(st.t0)
	var px: float = g.PX
	if age < PRE + CORE:   # 预备：判定圈内压暗（暗紫椭圆，按行铺像素条）
		var a: float = 0.28 * clampf(age / PRE, 0.0, 1.0) * (1.0 if age < PRE else clampf(1.0 - (age - PRE) / CORE, 0.0, 1.0))
		var rr: float = br * 0.9
		var ry: float = rr * SQ
		var y := -ry
		while y <= ry:
			var hw: float = rr * sqrt(maxf(0.0, 1.0 - (y * y) / (ry * ry)))
			var p0: Vector2 = ((c + Vector2(-hw, y)) / 2.0).round() * 2.0
			w.tb_quad(p0, p0 + Vector2(hw * 2.0, 0), p0 + Vector2(hw * 2.0, px), p0 + Vector2(0, px), Color(LP[0].r, LP[0].g, LP[0].b, a))
			y += px
	var ac: float = age - PRE
	if ac >= 0.0 and ac < RING + 2.0 / FPS:
		var rr2: float = _ring_r(ac)
		var fade: float = 1.0 if ac < RING else clampf(1.0 - (ac - RING) / (2.0 / FPS), 0.0, 1.0)
		var th: int = 5
		var n: int = int(rr2 * TAU / px)
		for q in n:   # 厚环 5 格：外两格白 → 淡紫 → 紫；断口按哈希（不是整齐的圆）
			var a2: float = float(q) / float(n) * TAU
			if _hf(int(q / 3.0), 7, 11) < 0.12:
				continue
			var dv := Vector2(cos(a2), sin(a2) * SQ)
			for k in th:
				var col: Color = [LP[6], LP[6], LP[5], LP[4], LP[3]][k]
				col.a = fade
				_px(w, c + dv * (rr2 - k * px), col)
			if ac < RING:   # 环后 6–14 格地面一闪
				var cf: Color = LP[3]
				cf.a = 0.45 * fade
				_px(w, c + dv * (rr2 - (6 + (q % 3) * 3) * px), cf)
			if q % 6 == 0 and fade > 0.6:
				_glow(c + dv * rr2, LP[6])
	w.tb_flush()


## 上层：预备收拢的光点、亮核、粒子云、怪物崩解喷散
func draw_front(_u, w) -> void:
	if not _live():
		return
	var c: Vector2 = st.c
	var br: float = st.br
	var age: float = g.t - float(st.t0)
	var px: float = g.PX
	var core_c: Vector2 = c + Vector2(0, -12)
	if age < PRE:   # 预备 2 拍：24 粒紫白光点从 0.6–0.9 br 往中心吸，越近越亮
		var k: float = clampf(age / PRE, 0.0, 1.0)
		for q in 24:
			var a: float = float(q) / 24.0 * TAU + _hf(q, 1, 3) * 0.4
			var r0: float = br * (0.6 + 0.3 * _hf(q, 2, 3))
			var r: float = lerpf(r0, br * 0.06, k * k)
			var p: Vector2 = core_c + Vector2(cos(a), sin(a) * SQ) * r
			var col: Color = LP[6] if k > 0.5 else LP[4]
			_px(w, p, col)
			_px(w, p - Vector2(cos(a), sin(a) * SQ) * px, LP[3])
	var ac: float = age - PRE
	if ac >= 0.0:
		if not st.lit:
			st.lit = true
			g.ult.light(c, 240.0, LIGHT, 0.6)   # 打满的照地灯（docs/270 爆发档上限 240）
			g.ult.shake(Bal.v("ult/la_px_shake", 3.0), Bal.v("ult/la_px_shake_t", 0.12))
		if ac < CORE:   # 亮核 2 拍：尖芒星形（白芯 → 淡紫 → 紫边），不平涂大圆
			var b: int = _beat(float(st.t0) + PRE)
			var R0: float = br * (0.1 if b == 0 else 0.13)
			for y in range(-int(R0 * 1.6 / px), int(R0 * 1.6 / px) + 1):
				for x in range(-int(R0 * 1.6 / px), int(R0 * 1.6 / px) + 1):
					var v := Vector2(x, y / SQ) * px
					var ang: float = v.angle()
					var spike: float = pow(absf(cos(ang * 4.0 + 0.3)), 6.0)   # 8 道尖芒
					var lim: float = R0 * (0.55 + 1.0 * spike) * (1.0 + 0.12 * (_hf(x, y, 5) - 0.5))
					var d: float = v.length()
					if d > lim:
						continue
					var u2: float = d / lim
					var col: Color = LP[6] if u2 < 0.45 else (LP[5] if u2 < 0.75 else LP[3])
					var p: Vector2 = core_c + Vector2(x, y) * px
					_px(w, p, col)
					if u2 < 0.3 and (x + y) % 3 == 0:
						_glow(p, LP[6])
		_cloud(w, core_c, ac)
		_shatter_tick(ac)
		_draw_sprays(w)
	w.tb_flush()


## 粒子云：亮核起往外喷的紫白光点，逐拍闪烁（原版那种闪的粒子云，换成紫白），0.9 秒散完
func _cloud(w, c: Vector2, ac: float) -> void:
	var br: float = st.br
	var dv: Vector2 = st.dv
	var bt: int = _beat(float(st.t0) + PRE)
	for q in CLOUD_N:
		var life: float = 0.6 + 0.3 * _hf(q, 4, 9)
		if ac > life:
			continue
		var a: float = _hf(q, 1, 9) * TAU
		var side: float = absf(Vector2.from_angle(a).dot(dv.orthogonal()))   # 顺着斩线两侧（垂直斩向）多一些、远一些
		var spd: float = br * (0.5 + 0.9 * _hf(q, 2, 9)) * (0.7 + 0.5 * side)
		var k: float = 1.0 - pow(1.0 - clampf(ac / life, 0.0, 1.0), 2.0)
		var p: Vector2 = c + Vector2(cos(a), sin(a) * SQ) * spd * k * 0.9 + Vector2(0, 30.0 * k * k)
		if (bt + q) % 3 == 0 and ac > 0.15:
			continue   # 闪烁：逐拍轮流灭
		var col: Color = LP[6] if ac < 0.12 else (LP[5] if q % 3 == 0 else (LP[4] if q % 3 == 1 else LP[3]))
		col.a = 1.0 if ac < life * 0.7 else clampf((life - ac) / (life * 0.3), 0.0, 1.0)
		_px(w, p, col, 2.0 if q % 4 == 0 else 1.0)
		if ac < 0.12 and q % 3 == 0:
			_glow(p, LP[6])


## 冲击环扫到的那一拍，末圈打中的怪崩解：引擎原有击杀碎屑补一次（非 Boss）+ 一圈本色像素顺着冲击喷开。只画
func _shatter_tick(ac: float) -> void:
	var c: Vector2 = st.c
	var rr: float = _ring_r(ac)
	for h in st.hits:
		if h.done:
			continue
		var p: Vector2 = h.e.pos if not h.e.get("dead", false) else h.p
		var rel: Vector2 = p - c
		var dist: float = Vector2(rel.x, rel.y / SQ).length()
		if dist <= rr or ac >= RING:
			h.done = true
			var e: Dictionary = h.e
			if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
				g.optical.particles.kill_burst(e)
			var col: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.6, 0.7))
			var out: Vector2 = Vector2(rel.x, rel.y / SQ).normalized() if rel.length() > 1.0 else (st.dv as Vector2)
			st.sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": col, "out": out, "k": 1.0 if dist <= float(st.br) else 0.7, "sd": int(e.get("id", 0)) * 13 + 5})
			if st.sprays.size() > SPRAY_MAX:
				st.sprays.pop_front()


func _draw_sprays(w) -> void:
	var px: float = g.PX
	for sp in st.sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.2 or age < 0.0:
			continue
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var k: float = float(sp.k)
		var sd: int = int(sp.sd)
		for q in int(SPRAY_N * k):
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 1.8
			var spd: float = (40.0 + 90.0 * _hf(q, sd, 72)) * k
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var hgt: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if t < t_land else 0.0
			var off := Vector2(cos(ang) * spd * tt, sin(ang) * spd * tt * SQ - hgt)
			var cc: Color = cols[q % 4]
			var hot: bool = age < 2.0 / FPS and q % 3 == 0
			if hot:
				cc = LP[6]
			cc.a = 1.0 if age < 0.8 else maxf(0.0, (1.2 - age) / 0.4)
			_px(w, (sp.p as Vector2) + off, cc, 2.0 if q % 3 != 2 else 1.0)
			if hot:
				_glow((sp.p as Vector2) + off, LP[6])
