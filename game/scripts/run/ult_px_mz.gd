## 水月终结技 Q「水母群」转平面画面（docs/261 §8，开关 ult/px_plane_mizuki，缺省 1；只画）。
## 以原版为底（ult_moves_b._mz_* + ult_fx_c.mz_jelly_*，ult/mz_jelly 缺省开）：时间轴、水母位置、漂浮 / 压缩 / 一起炸开、全屏渐暗、
## 每只 600 粒闪烁粒子云（换本人配色，原调用不动）、灯、顿帧、冲击帧时机都照旧；原版的声音全保留（出声的图形照常生成、只设成全透明）。
## 往上加的：水母画成海月水母（用户 11-05）——扁碟形半透明伞、四个马蹄形生殖腺环（荧光紫，进发光层）、细缘须、褶边口腕，压缩按整格一档档缩；
## 压缩时每只一圈往里收的压扁断续细环 + 光点吸入；炸开那一拍伞盖一鼓白亮 + 中心小亮核 2 拍 + 每只一圈细青紫环 +
## 群心压扁厚冲击环 3–4 拍推到横扫半径（推过的地面一闪）；横扫打中的怪在炸开那一拍补一次引擎击杀碎屑 + 本色像素喷散（崩解）；
## 冲击帧剪影 = 9 只海月水母放大 1.45 倍；漏网缠绕改像素触手圈。
## 画法同 tools/ult_px_mizuki_gif.py（Python 送审版），1 特效像素 = 1 美术像素（g.PX）、15 fps 节拍、贴地压扁 0.72；不抽随机数（散布按坐标哈希）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol

const C8 := [Color("#070a22"), Color("#111a52"), Color("#1e2f8f"), Color("#3150c8"), Color("#5a7cf0"), Color("#9aa8ff"), Color("#cfd6ff"), Color("#ffffff")]   # OP.mizuki
const CY := Color("#6fe8ff")
const CYL := Color("#c4f7ff")
const AC := Color("#b98cff")
const SQ := 0.72
const EMIT_CAP := 240
const SHOCK_T := 3.5 / 15.0
const SPRAY_N := 22
const SPRAY_MAX := 60
const END_T := 1.35     # 炸开后粒子云 / 照地光 / 崩解的总寿命（游戏秒）
const FADE_T := 0.45    # 末尾渐隐（11-06 用户「末尾那个要不要加个渐变消失」：0.3–0.5 秒、真 alpha、按 15 fps 拍走）

var g
var a = null          # 这一次终结技的招式字典（ult_moves_b._mz_start 返回的 a；jl / jl_c1 / jl_burst / t 由原逻辑更新，这里只读）
var bursts_t := -1.0  # 一起炸开的游戏时间
var ctr := Vector2.ZERO
var sprays: Array = []
var binds: Array = []   # [{e, t0, life}]
var _emit_n := 0
var _emit_frame := -1
var _cache := {}


static func on() -> bool:
	return Bal.v("ult/px_plane_mizuki", 1.0) > 0.0   # 11-06 用户看过末尾渐隐后「过」：水月单独一个开关、缺省开（不跟艾丽妮的 ult/px_plane 绑）


static func of(game):
	if game.has_meta("ult_px_mz"):
		return game.get_meta("ult_px_mz")
	var r = new()
	r.g = game
	game.set_meta("ult_px_mz", r)
	return r


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


# ================================================================ 事件（ult_fx_c.mz_jelly_* / ult_moves_b._mz_step 发；只记画面）

static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	of(u.g)._ev(u, kind, d)


func _ev(_u, kind: String, d: Dictionary) -> void:
	match kind:
		"start":
			a = d.a
			bursts_t = -1.0
			sprays = []
			binds = []
			_cache = {}
		"burst":
			if a == null:
				return
			bursts_t = g.t
			ctr = d.c
			var c0: Vector2 = a.c
			for e in d.get("hits", []):   # 崩解：横扫打中的怪在炸开这一拍整只炸成自身像素（补一次引擎击杀碎屑 + 本色喷散）
				_monster_burst(e, c0)
		"bind":
			binds.append({"e": d.e, "t0": g.t, "life": float(d.get("life", 1.2))})
			if binds.size() > 12:
				binds.pop_front()


func _live() -> bool:
	if a == null:
		return false
	if bursts_t >= 0.0 and g.t - bursts_t > END_T + 0.7:
		a = null
		return false
	if not a.has("jl"):
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


## 一组美术像素点 [x, y, 颜色(可带 alpha), 发光 bool, 边长]，原点对齐 2 像素格；fg = 纯色剪影
func _pts(w, o0: Vector2, lst: Array, fg = null) -> void:
	var px: float = g.PX
	var base: Vector2 = (o0 / 2.0).round() * 2.0
	for q in lst:
		var p: Vector2 = base + Vector2(roundf(float(q[0])), roundf(float(q[1]))) * px
		var c: Color = q[2] if fg == null else fg
		var sz: float = px * (float(q[4]) if q.size() > 4 else 1.0)
		w.tb_quad(p, p + Vector2(sz, 0), p + Vector2(sz, sz), p + Vector2(0, sz), c)
		if fg == null and q[3]:
			_glow(p, c)


# ================================================================ 海月水母（同 ak-mizuki-pp.js / ult_px_mizuki_gif.py 的 aurelia）

func _aurelia(Rb: float, ph: float, al: float, bright: float, sil: bool) -> Array:
	var key := "%d_%d_%d_%d_%d" % [int(Rb), int(ph * 10.0) % 63, int(al * 8.0), int(bright * 4.0), int(sil)]
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	var hh: float = maxf(2.0, Rb * 0.46)
	var sag: float = Rb * 0.08
	var body: Color = CY.lerp(Color.WHITE, bright)
	var rim: Color = CYL if bright < 0.5 else Color.WHITE
	var Ri: int = int(Rb)
	for x in range(-Ri, Ri + 1):
		var u: float = float(x) / Rb
		var y0: int = int(roundf(-hh * pow(maxf(0.0, 1.0 - u * u), 0.6)))
		var y1: int = int(roundf(sag * (1.0 - u * u)))
		for y in range(y0, y1 + 1):
			var edge: bool = y == y0 or y == y1 or absi(x) >= Ri
			if sil:
				out.append([x, y, Color.WHITE, false])
			elif edge:
				out.append([x, y, Color(rim.r, rim.g, rim.b, al), y == y0 and x % 3 == 0])
			elif y <= y0 + 1 and u > -0.65 and u < -0.1:
				out.append([x, y, Color(1, 1, 1, al), true])
			else:
				out.append([x, y, Color(body.r, body.g, body.b, 0.55 * al), false])
	# 四个马蹄形生殖腺环（苜蓿形）
	var gy: float = -hh * 0.42
	var rgx: float = Rb * 0.3
	var rgy: float = hh * 0.42
	var rh: float = maxf(0.8, Rb * 0.16)
	for k in 4:
		var an: float = float(k) / 4.0 * TAU
		var gx: float = cos(an) * rgx
		var gyy: float = gy + sin(an) * rgy
		var b := 0.0
		while b < TAU:
			var rel: float = fposmod(b - (an + PI), TAU)
			if rel >= 0.6 and rel <= TAU - 0.6:
				out.append([gx + cos(b) * rh, gyy + sin(b) * rh * 0.7, Color.WHITE if sil else Color(AC.r, AC.g, AC.b, al), not sil])
			b += 0.35 / rh
	# 缘须
	for x in range(-Ri + 1, Ri):
		var u2: float = float(x) / Rb
		var y: int = int(roundf(sag * (1.0 - u2 * u2))) + 1
		var L: int = 1 + ((x + 9) % 2) + (1 if Rb >= 20.0 and x % 3 == 0 else 0)
		for s in L:
			var cc: Color = rim if s == 0 else C8[4]
			out.append([x, y + s, Color.WHITE if sil else Color(cc.r, cc.g, cc.b, al), false])
	# 口腕
	var La: float = maxf(2.0, Rb * 1.15)
	for i in 4:
		var x0: float = (float(i) / 3.0 - 0.5) * Rb * 0.5
		for s in range(1, int(La) + 1):
			var x: float = x0 + sin(s * 0.45 + i * 1.7 + ph) * (0.8 + 2.2 * s / La)
			var y: float = sag + s
			var wd: int = 2 if s < La * 0.6 else 1
			for dd in wd:
				var cc2: Color = CYL if dd == 0 else C8[5]
				out.append([x + dd, y, Color.WHITE if sil else Color(cc2.r, cc2.g, cc2.b, al), false])
			if s % 3 == 1 and not sil:
				out.append([x + (-1.0 if i < 2 else 2.0), y, Color(AC.r, AC.g, AC.b, al * 0.9), false])
	if _cache.size() > 400:
		_cache.clear()
	_cache[key] = out
	return out


func _jelly_rb(j: Dictionary) -> float:
	var s: Dictionary = j.s
	var k: float = float(s.get("sc", 1.0)) / maxf(0.001, float(j.sc))   # 原逻辑压缩时 sc 1 → 0.4
	return maxf(6.0, roundf(float(j.get("rb", 28.0)) * k / 2.0) * 2.0)   # 整格一档档缩


# ================================================================ 绘制（ult.draw_world 招式图形之后、冲击帧之前）

func draw_front(_u, w) -> void:
	if not _live():
		return
	var t: float = float(a.get("t", 0.0))
	var c1: float = float(a.get("jl_c1", 0.77))
	if bursts_t < 0.0:
		var kp: float = clampf((t - (c1 - 0.45)) / 0.45, 0.0, 1.0)
		var kq: float = kp * kp
		for i in a.jl.size():
			var j: Dictionary = a.jl[i]
			var s: Dictionary = j.s
			var k: float = clampf((t - float(j.d0)) / 0.55, 0.0, 1.0)
			if k <= 0.0:
				continue
			var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
			var Rb: float = _jelly_rb(j)
			var bc: Vector2 = Vector2(s.c) + Vector2(0, 6)
			_pts(w, bc, _aurelia(Rb, float(j.ph) + floorf(g.t * 15.0) * 0.4, 0.85 * ke, 0.6 * kq, false))
			if kp > 0.0:   # 压缩：往里收的压扁断续细环 + 光点吸入
				var r: float = 47.0 * (1.0 - kp) + 9.0
				var ring: Array = []
				var n: int = int(r * 6.4) + 8
				for q in n:
					if (q * 7) % 5 == 0:
						continue
					var th: float = float(q) / float(n) * TAU
					ring.append([cos(th) * r, sin(th) * r * SQ, Color(CYL.r, CYL.g, CYL.b, 0.8 * kp), false])
				for m in 6:
					var an: float = TAU * (m + _hf(m, i, 5)) / 6.0 + g.t * 2.0
					var rr: float = 40.0 * (1.0 - kp) * (0.6 + 0.4 * _hf(m, i, 6)) + 4.0
					ring.append([cos(an) * rr, sin(an) * rr * SQ, CYL, true])
				_pts(w, bc + Vector2(0, Rb * 0.6), ring)
	else:
		var tb: float = g.t - bursts_t
		var bf: int = int(floor(tb * 15.0 + 0.001))
		var Rw: float = float(a.R)
		for i in a.jl.size():
			var j2: Dictionary = a.jl[i]
			var p: Vector2 = Vector2(j2.s.c) + Vector2(0, 6)
			if bf == 0:   # 伞盖一鼓（同冲击帧剪影的 1.45 倍）：白亮一拍
				_pts(w, p, _aurelia(roundf(_jelly_rb(j2) * 1.45 / 2.0) * 2.0, float(j2.ph), 1.0, 1.0, false))
			if bf <= 1:
				_pts(w, p + Vector2(0, 12), _core(bf))
			_pts(w, p + Vector2(0, 30), _ring(8.0, 75.0 + 30.0 * _hf(i, 7, 8), tb, 2, false))
		_pts(w, a.c, _ring(Rw * 0.5 * 0.45, Rw * 0.5 * 1.02, tb - 1.0 / 15.0, 5, true))   # 厚冲击环从判定中心推到横扫半径（原版群心 R × 1.05 碎环 → 像素厚环，推到判定边缘）
	_draw_sprays(w)
	for bd in binds:
		var age: float = g.t - float(bd.t0)
		var e: Dictionary = bd.e
		if age > float(bd.life) or e.get("dead", false):
			continue
		_pts(w, e.pos, _coil(float(e.get("r", 14.0)) * 0.5 + 2.0, _fade_al(age, float(bd.life))))
	w.tb_flush()


## 冲击帧剪影（ult._draw_hit_frame 在整屏底色之后调）：9 只海月水母放大 1.45 倍
func draw_hf(_u, w, fg: Color) -> void:
	if not _live():
		return
	for j in a.jl:
		var Rb: float = roundf(_jelly_rb(j) * 1.45 / 2.0) * 2.0
		_pts(w, Vector2(j.s.c) + Vector2(0, 6), _aurelia(Rb, float(j.ph), 1.0, 0.0, true), fg)
	w.tb_flush()


func _core(bf: int) -> Array:
	var out: Array = []
	var r: float = 7.0 if bf == 0 else 5.0
	var ri: int = int(r)
	for y in range(-ri, ri + 1):
		for x in range(-ri, ri + 1):
			var dd: float = Vector2(x, y / SQ).length()
			if dd <= r * 0.45:
				out.append([x, y - 10, Color.WHITE if bf == 0 else CYL, true])
			elif dd <= r * 0.7 and (x == 0 or y == 0):
				out.append([x, y - 10, CYL, false])
	var L: int = int(r * 2.4)
	for s in range(int(r * 0.5), L):
		var k: float = 1.0 - float(s) / float(L)
		var col: Color = Color.WHITE if k > 0.5 else CYL
		for dv in [Vector2(s, 0), Vector2(-s, 0), Vector2(0, s * SQ), Vector2(0, -s * SQ)]:
			out.append([dv.x, dv.y - 10, col, k > 0.5])
	return out


## 压扁冲击环：r0 → r1（美术像素，先快后慢），厚 thick 格；main = 群心那圈（白 → 青 → 紫，环后地面一闪），否则每只那一圈（细、青紫）
func _ring(r0: float, r1: float, tau: float, thick: int, main: bool) -> Array:
	var out: Array = []
	if tau < 0.0 or tau > SHOCK_T + 2.0 / 15.0:
		return out
	var us: float = clampf(tau / SHOCK_T, 0.0, 1.0)
	var rr: float = r0 + (r1 - r0) * (1.0 - pow(1.0 - us, 2.0))
	var fade: float = 1.0 if tau < SHOCK_T else clampf(1.0 - (tau - SHOCK_T) / (2.0 / 15.0), 0.0, 1.0)
	var cols: Array
	if main:
		cols = [Color.WHITE, Color.WHITE, CYL, CY, AC] if tau < SHOCK_T else [CYL, CY, AC, C8[4], C8[3]]
	else:
		cols = [CYL, CY] if tau < SHOCK_T else [CY, AC]
	var n: int = int(rr * 6.6) + 16
	for q in n:
		if _hf(q, int(r1), 31) < 0.08 + 0.5 * (1.0 - fade):   # 断口，越到边越碎
			continue
		var th: float = float(q) / float(n) * TAU
		var ct := Vector2(cos(th), sin(th) * SQ)
		for jj in thick:
			var cj: Color = cols[jj]
			out.append([ct.x * (rr - jj), ct.y * (rr - jj), Color(cj.r, cj.g, cj.b, fade), jj == 0 and q % 3 == 0 and tau < SHOCK_T])
		if main and tau < SHOCK_T and q % 2 == 0:   # 推过的地面一闪
			for j2 in range(thick + 2, thick + 8, 2):
				out.append([ct.x * (rr - j2), ct.y * (rr - j2), Color(C8[3].r, C8[3].g, C8[3].b, 0.45 * (1.0 - float(j2) / float(thick + 8))), false])
	return out


## 漏网缠绕：同 S2 的像素触手圈（1.25 圈矮螺旋，一勒一松）
## 末尾渐隐：剩下不到 FADE_T 秒时透明度按 15 fps 一拍一拍降到 0（真 alpha，不抖动）
static func _fade_al(age: float, life: float) -> float:
	var left: float = ceilf((life - age) * 15.0) / 15.0
	return clampf(left / FADE_T, 0.0, 1.0)


func _coil(er: float, al := 1.0) -> Array:
	var out: Array = []
	var f: int = int(floor(g.t * 15.0)) % 6
	var sq_: float = [0.0, 1.0, 1.5, 1.0, 0.0, -0.5][f]
	var rx: float = er - sq_ * 0.6
	var ry: float = rx * SQ * 0.62
	var TURN: float = TAU * 1.25
	var an := 0.0
	while an < TURN:
		var z: float = 3.0 + an / TURN * 5.0
		var sn: float = sin(an)
		var x: float = cos(an) * rx
		var y: float = sn * ry - z
		var front: bool = sn > 0.0
		var wd: float = 3.0 - an / TURN * 1.2
		var dd := 0.0
		while dd < wd:
			var ci: int = 1 if dd < 0.8 else ((3 if front else 2) if dd < wd - 1.0 else (5 if front else 3))
			var cc: Color = C8[ci]
			out.append([x, y + dd - wd / 2.0, Color(cc.r, cc.g, cc.b, al), false])
			dd += 1.0
		if front and int(an * 3.0) % 4 == 0:
			out.append([x, y, Color(AC.r, AC.g, AC.b, al), al > 0.5])
		an += 0.5 / maxf(2.0, rx)
	return out


# ================================================================ 怪物崩解（同 ult_px_ir.gd：引擎击杀碎屑 + 本色像素喷散）

func _monster_burst(e: Dictionary, c0: Vector2) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
		g.optical.particles.kill_burst(e)
	var col: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9))
	var p: Vector2 = e.pos
	var out: Vector2 = (p - c0).normalized() if p != c0 else Vector2.RIGHT
	sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": col, "out": out, "k": 1.6, "sd": int(e.get("id", 0)) * 13 + 11})
	if sprays.size() > SPRAY_MAX:
		sprays.pop_front()


func _draw_sprays(w) -> void:
	for sp in sprays:
		var age: float = g.t - float(sp.t0)
		if age > END_T:
			continue
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var k: float = float(sp.k)
		var lst: Array = []
		var sd: int = int(sp.sd)
		for q in int(SPRAY_N * minf(1.4, k)):
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 2.2
			var spd: float = (30.0 + 70.0 * _hf(q, sd, 72)) * k
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var tt: float = minf(minf(age, 0.9), t_land)
			var h: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if minf(age, 0.9) < t_land else 0.0
			var cc: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				cc = Color(1, 1, 1)
			var al: float = _fade_al(age, END_T)
			lst.append([cos(ang) * spd * tt, sin(ang) * spd * tt * SQ - h, Color(cc.r, cc.g, cc.b, al), hot, 2.0 if q % 3 != 2 else 1.0])
		_pts(w, sp.p, lst)
