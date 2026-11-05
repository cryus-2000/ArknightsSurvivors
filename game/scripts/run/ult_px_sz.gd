## 铃兰终结技（忍冬瞬斩）转平面补强（docs/271 §7，开关 ult/px_plane，缺省 0 = 原画面）：只改画面。
## 原版造型 / 节奏 / 体量保留（ult_fx_c.sz_*），配色在那边换成米金狐火色系；这里只补「最大那一下」（刀痕绷开 + 连环爆裂）缺的两样：
##   ① 压扁冲击环：从斩痕中点往外 3.5 拍推到判定带边缘（带内切椭圆，不超判定），环后地面一闪，到边 2 拍淡掉；
##   ② 怪物本色崩解（docs/275 §1.0）：被斩的怪在绷开那一拍补一次引擎击杀碎屑（optical_particles.kill_burst）+ 怪物代表色像素往刀口两侧喷散。
## 冲击帧 / 顿帧 / 冲击慢放走框架（ult.impact，落在斩痕爆裂伤害那一拍），这里不另加。不抽随机数（散布按坐标哈希）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")

const F := [Color("#2e2618"), Color("#5e4e34"), Color("#9a8058"), Color("#ccae78"), Color("#e8d4a8"), Color("#fbf1d8"), Color("#ffffff")]   # 米金（docs/271 §1）
const SHOCK_T := 3.5 / 15.0
const SPRAY_N := 22
const SPRAY_MAX := 60
const EMIT_CAP := 200

var g
var st := {}
var _emit_n := 0
var _emit_frame := -1


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0


static func of(game):
	if game.has_meta("ult_px_sz"):
		return game.get_meta("ult_px_sz")
	var r = new()
	r.g = game
	game.set_meta("ult_px_sz", r)
	return r


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	var r = of(u.g)
	if kind == "rupt":
		r.st = {"a0": d.a0, "b0": d.b0, "hw": float(d.hw), "t0": r.g.t + float(d.TB), "es": d.get("es", []).slice(0, 40), "done": false, "sprays": []}


func _live() -> bool:
	if st.is_empty():
		return false
	if g.t - float(st.t0) > 1.6:
		st = {}
		return false
	return g.t >= float(st.t0)


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


## 一组美术像素点 [x, y, 颜色, 不透明度, 发光, 边长]，原点 o0 对齐 2 像素格
func _pts(w, o0: Vector2, lst: Array) -> void:
	var px: float = g.PX
	var base: Vector2 = (o0 / 2.0).round() * 2.0
	for q in lst:
		var p: Vector2 = base + Vector2(roundf(float(q[0])), roundf(float(q[1]))) * px
		var c: Color = q[2]
		var sz: float = px * float(q[5])
		w.tb_quad(p, p + Vector2(sz, 0), p + Vector2(sz, sz), p + Vector2(0, sz), Color(c.r, c.g, c.b, float(q[3])))
		if q[4]:
			_glow(p, c)


## 地面层（ult.draw_world_back）：冲击环 + 环后地面一闪
func draw_back(u, w) -> void:
	if not _live():
		return
	var tau: float = g.t - float(st.t0)
	if not st.done:   # 绷开那一拍：崩解 + 轻震（一次）
		st.done = true
		u.shake(3.0, 0.12)
		for e in st.es:
			_burst(e)
	if tau >= SHOCK_T + 2.0 / 15.0:
		return
	var a0: Vector2 = st.a0
	var b0: Vector2 = st.b0
	var mid: Vector2 = a0.lerp(b0, 0.5)
	var dv: Vector2 = (b0 - a0).normalized()
	var nv := Vector2(-dv.y, dv.x)
	var A: float = a0.distance_to(b0) * 0.5 / g.PX   # 美术像素：带内切椭圆（沿刀向半长 / 横向半宽）
	var B: float = float(st.hw) / g.PX
	var us: float = clampf(tau / SHOCK_T, 0.0, 1.0)
	var k: float = 0.3 + 0.7 * (1.0 - pow(1.0 - us, 2.0))   # 先快后慢
	var fade: float = 1.0 if tau < SHOCK_T else clampf(1.0 - (tau - SHOCK_T) / (2.0 / 15.0), 0.0, 1.0)
	var cols: Array = [F[6], F[5], F[5], F[4], F[3]] if tau < SHOCK_T else [F[5], F[4], F[4], F[3], F[2]]
	var n: int = int((A + B) * k * 3.3) + 24
	var lst: Array = []
	for q in n:
		var t: float = float(q) / float(n) * TAU
		var ct: float = cos(t)
		var s2: float = sin(t)
		for j in 5:
			var kk: float = k - float(j) / maxf(A, B)
			var v: Vector2 = (dv * ct * A + nv * s2 * B) * kk
			lst.append([v.x, v.y, cols[j], fade, j == 0 and q % 3 == 0, 1.0])
		if tau < SHOCK_T:   # 环后 7–15 格地面一闪（米金，越往里越淡）
			for j2 in range(7, 16, 2):
				if (q + j2) % 3 == 0:
					continue
				var kk2: float = k - float(j2) / maxf(A, B)
				if kk2 <= 0.05:
					continue
				var v2: Vector2 = (dv * ct * A + nv * s2 * B) * kk2
				lst.append([v2.x, v2.y, F[3], 0.42 * (1.0 - float(j2) / 16.0), false, 1.0])
	_pts(w, mid, lst)
	w.tb_flush()


## 上层（ult.draw_world）：怪物代表色像素喷散
func draw_front(_u, w) -> void:
	if not _live():
		return
	var a0: Vector2 = st.a0
	var b0: Vector2 = st.b0
	var dv: Vector2 = (b0 - a0).normalized()
	var nv := Vector2(-dv.y, dv.x)
	var age: float = g.t - float(st.t0)
	for sp in st.sprays:
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var side: float = float(sp.side)
		var out: Vector2 = (nv * side * 1.4 + dv * (_hf(int(sp.sd), 3, 70) - 0.5)).normalized()
		var lst: Array = []
		for q in SPRAY_N:
			var sd: int = int(sp.sd)
			var ang: float = out.angle() + (_hf(q, sd, 71) - 0.5) * 2.2
			var spd: float = (30.0 + 70.0 * _hf(q, sd, 72)) * 1.4
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var G := 260.0
			var t_land: float = 2.0 * vh / G
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var h: float = maxf(0.0, vh * tt - 0.5 * G * tt * tt) if t < t_land else 0.0
			var c: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				c = Color(1, 1, 1)
			var al: float = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			lst.append([cos(ang) * spd * tt, sin(ang) * spd * tt * 0.72 - h, c, al, hot, 2.0 if q % 3 != 2 else 1.0])
		_pts(w, sp.p, lst)
	w.tb_flush()


func _burst(e: Dictionary) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
		g.optical.particles.kill_burst(e)
	if st.sprays.size() >= SPRAY_MAX:
		return
	var a0: Vector2 = st.a0
	var b0: Vector2 = st.b0
	var dv: Vector2 = (b0 - a0).normalized()
	var nv := Vector2(-dv.y, dv.x)
	var p: Vector2 = e.pos
	st.sprays.append({"p": p + Vector2(0, -10), "col": D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9)),
		"side": 1.0 if (p - a0).dot(nv) >= 0.0 else -1.0, "sd": int(e.get("id", 0)) * 13 + 5})
