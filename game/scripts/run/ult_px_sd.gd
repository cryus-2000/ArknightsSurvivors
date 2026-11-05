## 斯卡蒂终结技「斩浪」转平面画面（docs/246 §16，开关 ult/px_plane，缺省 0 = 原画面；同开关见 docs/275）：只改画面，
## 招式时间轴 / 判定 / 伤害 / 顿帧 / 冲击帧逻辑全照 ult_moves_b._sd_*（docs/199 §7.16）。
## 画面由 pixelfx 效果 tools/pixelfx_fx/water/ak-skadi-ult-pp.js 烤成帧图集（tools/ult_px_skadi_bake.py）：
##   平面角 -90…90 每 22.5° 一张（另一半水平翻转），每张含招式 up（立起）/ gd（贴地）两层逐帧 + 冲击帧剪影；起手蓄力一张（朝左翻转）。
## 1 特效像素 = 1 美术像素（g.PX = 2 世界像素），15 fps 节拍（出招后第几拍按全局拍子数），贴地层压扁 0.72（烤的时候已压扁）。
## 劈浪那一下（用户 11-05「爆炸是冲击力最为关键的部分」）：预备 2 拍收 → 爆点亮核 2 拍 + 满亮照地灯 → 冲击水环 0.25 秒推到判定边 + 环边甩水团 → 落水水爆与浪的两半跟着环往外。
## 图集只在这次终结技起手时按方向加载一张（约 20 MB 显存），招式结束 2 秒后放掉。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol（崩解喷散取怪物自身颜色）
const META := "res://data/ult_px_skadi.json"
const ART := "res://art/fx/pxp/ult_sd/%s.png"
const ICE := Color(0.77, 0.86, 1.0)
const FPS := 15.0
const UM = preload("res://scripts/ui_motion.gd")
const SPLIT := 0.25     # 劈开慢动作那段的游戏秒（同 ak-skadi-ult-pp.js SPLIT）：冲击帧后剑光劈进浪、两半分开，之后才起爆

var g
var meta := {}
var st := {}            # 这一次：{o0, dk 方向键, flip, t0 出招, tex, rects, crash_t}
var _chg_tex = null
var _cache := {}        # 起手时按瞄准方向先载入的图集（出招时直接用，免得出招那一帧卡）
var _emit_n := 0
var _emit_frame := -1


static func on() -> bool:
	return (Bal.v("ult/px_plane", 0.0) > 0.0 or Bal.v("ult/px_plane_skadi", 0.0) > 0.0) and ResourceLoader.exists(META)   # 总开关或斯卡蒂一人（11-05 拆成按干员开）


static func of(game):
	if game.has_meta("ult_px_sd"):
		return game.get_meta("ult_px_sd")
	var r = new()
	r.g = game
	game.set_meta("ult_px_sd", r)
	return r


func _meta() -> Dictionary:
	if meta.is_empty():
		var f := FileAccess.open(META, FileAccess.READ)
		if f != null:
			var v = JSON.parse_string(f.get_as_text())
			meta = v if v is Dictionary else {}
	return meta


## 出手方向 → [方向键, 是否翻转]：平面角折到 -90…90（朝左的水平翻转），取最近的 22.5° 档
static func dir_key(d: Vector2) -> Array:
	var a: float = rad_to_deg(atan2(d.y, d.x))
	var flip := false
	if a > 90.0:
		a = 180.0 - a
		flip = true
	elif a < -90.0:
		a = -180.0 - a
		flip = true
	var q: float = clampf(roundf(a / 22.5) * 22.5, -90.0, 90.0)
	return [str(int(q)) if is_equal_approx(q, roundf(q)) else str(q), flip]   # 同烤图脚本的 "%g"（GDScript 没有 %g）：-90 / -67.5 / 0 / 22.5


# ================================================================ 事件（ult_moves_b._sd_* 发；只记画面）

static func ev(u, kind: String, d: Dictionary) -> void:
	if not on():
		return
	of(u.g)._ev(u, kind, d)


func _ev(u, kind: String, d: Dictionary) -> void:
	match kind:
		"start":
			var m: Dictionary = _meta()
			var kf: Array = dir_key(d.d)
			var dirs: Dictionary = m.get("dirs", {})
			if not dirs.has(kf[0]):
				st = {}
				return
			var nm: String = "sd_d" + str(kf[0]).replace("-", "m").replace(".", "_")
			var p: String = ART % nm
			var tex = _cache.get(p, null)
			if tex == null:
				tex = load(p) if ResourceLoader.exists(p) else null
			_cache = {}
			st = {"o0": d.o0, "d": d.d, "dk": kf[0], "flip": kf[1], "t0": g.t, "tex": tex,
				"rects": dirs[kf[0]], "crash_t": -1.0, "end_t": -1.0, "hits": [], "sprays": []}
		"cleave":   # 下劈落地：落点一盏照地光（冰蓝）
			if not st.is_empty():
				u.light(_plane(150.0, 0.0), 160.0, ICE, 0.35)
		"crash":   # 劈浪：冲击帧 / 顿帧由招式照旧打；之后劈开慢动作（slow_scale），起爆时（boom_t）点满亮照地灯
			if not st.is_empty():
				st.crash_t = g.t
				st["crash_rt"] = UM.now()
				st["lit"] = false
				var sx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
				if sx != null:
					sx.play("boom", -6.0, 0.5, 0.0)   # 慢放时一声低沉的余音（复用现有 boom，降八度）
		"hit":   # 被下劈 / 浪头打中的怪：冲击环扫到它那一拍补崩解（同一只只记一次）
			if not st.is_empty() and st.hits.size() < HIT_MAX:
				var e: Dictionary = d.e
				for h in st.hits:
					if is_same(h.e, e):
						return
				st.hits.append({"e": e, "p": e.pos, "done": false})
		"surge":   # 涌潮路线终点再炸一次：同一爆点画法不另烤，只补一盏光
			if not st.is_empty():
				u.light(d.c, 220.0, ICE, 0.4)


## 平面坐标（沿出手方向 a、侧向 l，世界像素）→ 世界点：侧向不压扁、纵向按 0.72 压扁（同烤图）
func _plane(a: float, l: float) -> Vector2:
	var dv: Vector2 = st.d
	var nv := Vector2(-dv.y, dv.x)
	var v: Vector2 = dv * a + nv * l
	return (st.o0 as Vector2) + Vector2(v.x, v.y * 0.72)


func _beat() -> int:
	return int(floor(g.t * FPS + 0.0001)) - int(floor(float(st.t0) * FPS + 0.0001))


func _live() -> bool:
	if st.is_empty():
		return false
	if g.t - float(st.t0) > 3.5:   # 招式最长约 1.6 秒画完；放掉图集（约 20 MB 显存）
		st = {}
		return false
	return true


## 画一帧：rect = [x, y, w, h, ox, oy]（图集内位置 + 脚底原点在帧内的位置），原点对齐 2 像素格，翻转时以脚底为轴
func _blit(tex: Texture2D, r: Array, o0: Vector2, flip: bool, mod := Color.WHITE) -> void:
	if tex == null or int(r[2]) <= 0:
		return
	var px: float = g.PX
	var base: Vector2 = (o0 / 2.0).round() * 2.0
	var sz := Vector2(float(r[2]), float(r[3])) * px
	var off := Vector2(-float(r[4]), -float(r[5])) * px
	var src := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	if flip:
		g.draw_set_transform(base, 0.0, Vector2(-1, 1))
		g.draw_texture_rect_region(tex, Rect2(off, sz), src, mod)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		g.draw_texture_rect_region(tex, Rect2(base + off, sz), src, mod)


func _layer(ly: String, mod := Color.WHITE) -> void:
	var lst: Array = st.rects.get(ly, [])
	var f: int = _beat()
	if f < 0 or f >= lst.size():
		return
	_blit(st.tex, lst[f], st.o0, st.flip, mod)


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	if _emit_n >= 160:
		return
	_emit_n += 1
	g.glow_next.append([p, g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


## 发光层：下劈裂痕芯 + 爆点亮核（这几处是白芯 / 冰蓝芯，进光学发光层）
func _emits() -> void:
	var f: int = _beat()
	if f >= 2 and f <= 9:   # 下劈后裂痕芯
		for i in 12:
			_glow(_plane(60.0 + 30.0 * i, 0.0), ICE)
	if float(st.crash_t) >= 0.0:
		var b: int = int(floor(g.t * FPS + 0.0001)) - int(floor(_boom_t() * FPS + 0.0001))
		if b >= 0 and b <= 2:
			var c: Vector2 = _plane(540.0, 0.0) + Vector2(0, -36)
			for i in 40:
				var a: float = float(i) * 2.39996
				var r: float = 120.0 * sqrt(float(i) / 40.0) * (1.0 if b < 2 else 0.8)
				_glow(c + Vector2(cos(a) * r, sin(a) * r * 0.7), Color.WHITE if r < 70.0 else ICE)


func _prefetch(d: Vector2) -> void:
	if d == Vector2.ZERO:
		return
	var kf: Array = dir_key(d)
	var p: String = ART % ("sd_d" + str(kf[0]).replace("-", "m").replace(".", "_"))
	if not _cache.has(p) and ResourceLoader.exists(p):
		_cache = {p: load(p)}


# ================================================================ 怪物崩解（用户 11-05「我说的崩解是原版那个粒子特效，就是怪物炸开的这个特效」；做法同艾丽妮 docs/275 §1.0）
## 冲击环（爆心起 0.25 秒推到判定边，同烤图 shockR）扫到被这一招打中 / 打死的怪那一拍：
##   ① 补一次引擎原有的击杀碎屑（optical_particles.kill_burst，按怪物贴图像素碎开；原有的击杀碎屑照常、时机不动）；
##   ② 一圈怪物本色（enemies.json ecol 亮 / 本色 / 暗三阶，头两拍白芯）的像素喷散，初速顺着冲击方向往外，有重量、落地、停一下熄灭。
## 劈浪之后才打中的怪（环已扫过）当拍就炸；环外的怪在环推到边那一拍炸、弱一号。只画，散布按哈希，不抽随机数。
const HIT_MAX := 120
const SPRAY_N := 22
const SPRAY_MAX := 80
const SHOCK_T := 0.25


func _shock_r(ac: float) -> float:   # 世界像素（烤图 26 → 230 美术像素）
	var k: float = clampf(ac / SHOCK_T, 0.0, 1.0)
	return 52.0 + (460.0 - 52.0) * (1.0 - pow(1.0 - k, 3.0))


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


## 劈开慢动作（用户 11-05「斯卡蒂终结技应该是最后浪被劈开的时候这时候应该慢动作」）：按真实时间算，冲击帧顿帧（ult/sd_crash_stop）过后
## ult/sd_px_slow_t（0.5）秒 ult/sd_px_slow（0.3）倍速，再 ult/sd_px_slow_ease（0.15）秒加速回原速。挂在 ult.time_scale（演出类，批跑 / TRACE 不缩，同起手慢放）
static func slow_scale(game) -> float:
	if not on() or not game.has_meta("ult_px_sd"):
		return 1.0
	var r = game.get_meta("ult_px_sd")
	if r.st.is_empty() or not r.st.has("crash_rt"):
		return 1.0
	if float(r.st.crash_t) < Bal.v("ult/sd_px_slow_from", 0.0):   # 录像对照用（缺省 0）：只让某局时之后的终结技慢放，前面的不改时间线，开 / 关两段才同一时刻
		return 1.0
	var t: float = UM.now() - float(r.st.crash_rt) - Bal.v("ult/sd_crash_stop", 0.08)
	var lo: float = Bal.v("ult/sd_px_slow", 0.3)
	var hold: float = Bal.v("ult/sd_px_slow_t", 0.5)
	var ez: float = Bal.v("ult/sd_px_slow_ease", 0.15)
	if t < 0.0 or t >= hold + ez:
		return 1.0
	if t < hold:
		return lo
	var k: float = (t - hold) / ez
	return lerpf(lo, 1.0, k * k)


func _boom_t() -> float:
	return float(st.crash_t) + SPLIT if float(st.crash_t) >= 0.0 else -1.0


func _shatter_tick() -> void:
	if float(st.crash_t) < 0.0:
		return
	var ac: float = g.t - _boom_t()
	if ac < 0.0:
		return
	if not st.get("lit", true):
		st.lit = true
		g.ult.light(_plane(540.0, 0.0), 460.0, Color(0.85, 0.92, 1.0), 0.6)   # 起爆：满亮照地灯（接近 docs/270 爆发档上限）
		g.ult.shake(Bal.v("ult/sd_px_shake", 3.0), Bal.v("ult/sd_px_shake_t", 0.12))   # 用户 11-05：起爆轻震 3px / 0.12 秒（原画面劈浪时 6 / 0.2）
	if st.hits.is_empty():
		return
	var bc: Vector2 = _plane(540.0, 0.0)
	var rr: float = _shock_r(ac)
	for h in st.hits:
		if h.done:
			continue
		var p: Vector2 = h.e.pos if not h.e.get("dead", false) else h.p
		var rel: Vector2 = p - bc
		var dist: float = Vector2(rel.x, rel.y / 0.72).length()
		if dist <= rr or ac >= SHOCK_T:
			h.done = true
			_monster_burst(h.e, p, rel, 1.0 if dist <= 460.0 else 0.7)


func _monster_burst(e: Dictionary, p: Vector2, rel: Vector2, k: float) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null and not e.get("boss", false):
		g.optical.particles.kill_burst(e)
	var col: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9))
	var out: Vector2 = Vector2(rel.x, rel.y / 0.72).normalized() if rel.length() > 1.0 else (st.d as Vector2)
	st.sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": col, "out": out, "k": k, "sd": int(e.get("id", 0)) * 13 + 5})
	if st.sprays.size() > SPRAY_MAX:
		st.sprays.pop_front()


func _draw_sprays() -> void:
	var px: float = g.PX
	for sp in st.sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.3 or age < 0.0:
			continue
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var k: float = float(sp.k)
		var base: Vector2 = ((sp.p as Vector2) / 2.0).round() * 2.0
		var sd: int = int(sp.sd)
		for q in int(SPRAY_N * k):
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 1.8
			var spd: float = (40.0 + 90.0 * _hf(q, sd, 72)) * k
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var hgt: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if t < t_land else 0.0
			var off := Vector2(cos(ang) * spd * tt, sin(ang) * spd * tt * 0.72 - hgt)
			var c: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				c = Color.WHITE
			c.a = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			var sz: float = px * (2.0 if q % 3 != 2 else 1.0)
			g.draw_rect(Rect2(base + (off / 2.0).round() * 2.0, Vector2(sz, sz)), c)
			if hot:
				_glow(base + off, Color.WHITE)


# ================================================================ 绘制（ult.gd 四处转来）

func draw_back(_u, w) -> void:
	if not _live():
		return
	w.tb_flush()
	_layer("gd")


func draw_front(_u, w) -> void:
	if not _live():
		return
	w.tb_flush()
	_layer("up")
	_emits()
	_shatter_tick()
	_draw_sprays()


## 冲击帧剪影：爆点那一拍的立起层（浪的两半 + 剑光 + 亮核）按 fg 纯色重画（烤好的白色剪影 × fg）
func draw_hf(_u, w, fg: Color) -> void:
	if not _live() or float(st.crash_t) < 0.0:
		return
	var lst: Array = st.rects.get("hf", [])
	if lst.is_empty():
		return
	w.tb_flush()
	_blit(st.tex, lst[0], st.o0, st.flip, Color(fg.r, fg.g, fg.b, 1.0))


## 起手慢放（ult._draw_windup 对斯卡蒂转来）：头顶冰蓝细光长到星芒、水珠往里收、脚下一圈水往里收
func draw_windup(u, w, caster, wk: float) -> void:
	var m: Dictionary = _meta()
	var ch: Dictionary = m.get("charge", {})
	if ch.is_empty():
		return
	if _chg_tex == null:
		var p: String = ART % "sd_charge"
		_chg_tex = load(p) if ResourceLoader.exists(p) else false
	if not (_chg_tex is Texture2D):
		return
	var flip: bool = (u.aim_dir as Vector2).x < 0.0   # 朝左出手：翻转
	_prefetch(u.aim_dir)
	var n: int = (ch.get("up", []) as Array).size()
	var f: int = clampi(int(wk * float(n)), 0, n - 1)
	w.tb_flush()
	_blit(_chg_tex, ch.gd[f], caster.pos, flip)
	_blit(_chg_tex, ch.up[f], caster.pos, flip)
