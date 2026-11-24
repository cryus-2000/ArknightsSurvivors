extends "res://scripts/core/theme_mechanic.gd"
## 萨米主题 · 敌人攻击特效（docs/401）。只画、不改玩法状态、不抽 g.rng（颗粒随机走自己的 rng）。
## 主形：pixelfx 烘焙帧条 themes/sami/fx/sfx_<键>.png（tools/sami_fx_bake.py，1 纹素 = 2 世界像素）；
## 质感：运行时像素颗粒（2×2 世界像素对齐的方块：火花、碎屑、余烬；暗烟用半透明圆）——Noita 式，颗粒位置按出生时刻解析计算，不逐帧积分。
## 配色照原作 enemy_sm* 预制体（F:/sami_enemy_fx_ref/prefabs/summary.txt）：坍缩系 白 → 钢蓝灰 → 黑；施法者黑针 + 冰蓝；冰爆虫青蓝；利刃黑 + 深红。
## 入口：
##   play(键, 位置, 角度, 缩放)     一次性帧条（其他模块 / Boss 脚本调，g.mech("fx") 判空）
##   sparks / smoke / embers         颗粒
##   on_player_hit                   命中件（躯壳爪击、法术弹迸散、利刃刃片迸散）
##   draw_front(w)                   敌弹之上：帧条 + 颗粒 + 专属弹体（施法者黑针、利刃刃片；设 own_draw 让通用弹体不画）
##   rush(e)                         染污躯壳受击暴冲开始（mech_foes 调）：暴冲期间身后留暗影拖烟 + 上升细线

const Game = preload("res://scripts/game.gd")
const FX_DIR := "res://themes/sami/fx/"
const PX := 2.0
const P_MAX := 420           # 同屏颗粒上限（网页预算，docs/401 §5）
const S_MAX := 48            # 同屏帧条上限

# 原作色
# 浅色雪地（昧明冻土）上颗粒取原作曲线里的中深段：白 / 淡色会混进雪里（docs/401 §9）
const STEEL := [Color(0.02, 0.024, 0.03), Color(0.06, 0.08, 0.1), Color(0.2, 0.25, 0.31), Color(0.34, 0.4, 0.48)]
const ICE := [Color(0.0, 0.05, 0.16), Color(0.0, 0.14, 0.43), Color(0.12, 0.36, 0.7), Color(0.32, 0.58, 0.83)]
const FROST := [Color(0.0, 0.13, 0.42), Color(0.0, 0.2, 0.55), Color(0.0, 0.38, 0.8), Color(0.1, 0.55, 0.95)]
const BLOOD := [Color(0.04, 0.0, 0.0), Color(0.62, 0.0, 0.0), Color(1.0, 0.17, 0.11), Color(1.0, 0.58, 0.26)]

var g: Game
var tex := {}
var meta := {}
var strips: Array = []       # [键, 位置, 角度, 出生 t, 缩放]
var parts: Array = []        # [p0, v, 出生 t, 寿命, 颜色, 尺寸, 种类(0 方块 1 暗烟 2 拉伸火花), 重力]
var rushers: Array = []
var rng := RandomNumberGenerator.new()
var hits := {}               # 遥测 / 演示：命中件按来源计数
var marks: Array = []        # 地面受击痕 [位置, 角度, 出生 t, 种类(0 爪痕 1 压痕)]
var own_hurt := true         # combat.hurt 读：本主题不画通用细红受击环
const M_MAX := 12
const GOUGE := [Color(0.1, 0.13, 0.2), Color(0.26, 0.32, 0.42), Color(0.93, 0.96, 1.0)]   # 爪痕：深槽 / 槽壁 / 翻起的雪唇
const OWN := {"caster": "needle", "blade": "blade", "wanderer": "blade"}


func _init(game: Game) -> void:
	g = game
	rng.seed = 40121
	var f := FileAccess.open(FX_DIR + "sami_fx.json", FileAccess.READ)
	if f != null:
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			meta = j
	for k in meta:
		if k.begins_with("_"):
			continue
		var t = load(FX_DIR + "sfx_%s.png" % k)
		if t != null:
			tex[k] = t


## ---- 入口
func play(key: String, pos: Vector2, ang := 0.0, k := 1.0) -> void:
	if not tex.has(key):
		return
	if strips.size() >= S_MAX:
		strips.pop_front()
	strips.append([key, pos, ang, g.t, k])


func _add(p0: Vector2, v: Vector2, life: float, col: Color, sz: float, kind := 0, grav := 0.0, delay := 0.0) -> void:
	if parts.size() >= P_MAX:
		parts.pop_front()
	parts.append([p0, v, g.t + delay, life, col, sz, kind, grav])


## 火花：pal 4 阶色（暗 → 亮），stretch = 拉伸成短线（原作 Sparks / suduxian 拉伸粒子）
func sparks(pos: Vector2, ang: float, spread: float, n: int, spd: float, pal: Array, stretch := true, life := 0.3) -> void:
	for i in n:
		var a: float = ang + rng.randf_range(-spread, spread)
		var s: float = spd * rng.randf_range(0.45, 1.0)
		_add(pos, Vector2.from_angle(a) * s, life * rng.randf_range(0.5, 1.0), pal[rng.randi_range(1, 3)], 4.0, 2 if stretch else 0, 0.0)


## 暗烟：原作 smoke（黑 / 深钢蓝，alpha 0.24–0.5，慢慢上浮变大）
func smoke(pos: Vector2, n: int, col: Color, r: float, rise := 18.0, life := 0.9) -> void:
	for i in n:
		var o := Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r) * 0.6)
		_add(pos + o, Vector2(o.x * 0.4, -rise * rng.randf_range(0.6, 1.2)), life * rng.randf_range(0.7, 1.1), col, r * rng.randf_range(0.5, 0.9), 1, 0.0, rng.randf_range(0.0, 0.08))


## 余烬 / 碎屑：2 像素方块，抛起后落下（grav > 0）
func embers(pos: Vector2, n: int, col: Color, spd: float, grav := 120.0, life := 0.7, sz := 2.0) -> void:
	for i in n:
		var a: float = rng.randf_range(-PI, 0.0)
		_add(pos, Vector2.from_angle(a) * spd * rng.randf_range(0.3, 1.0), life * rng.randf_range(0.6, 1.0), col, sz, 0, grav)


## ---- 事件
func on_player_hit(dmg: float, src: Dictionary) -> void:
	if dmg <= 0.0:
		return
	var t: String = str(src.get("src_type", src.get("type", "")))
	var sp: Vector2 = src.get("pos", g.ppos)
	var ang: float = (g.ppos - sp).angle() if sp.distance_to(g.ppos) > 1.0 else -PI * 0.5
	var hp: Vector2 = g.ppos + Vector2(0, -14)
	hits[t] = int(hits.get(t, 0)) + 1
	_mark(g.ppos + Vector2(0, 8) - Vector2.from_angle(ang) * 26.0, ang, 0 if t == "husk" else 1)   # 落在队长和来袭方之间，别被队长身子挡住
	match t:
		"husk":
			play("husk_hit", hp - Vector2.from_angle(ang) * 14.0, ang, 1.8)
			sparks(hp, ang, 0.8, 8, 300.0, STEEL)
		"caster":
			play("caster_pop", hp, ang, 1.7)
			sparks(hp, ang, 0.7, 10, 260.0, ICE)
			embers(hp, 6, Color(0.85, 0.93, 1.0), 170.0, 260.0, 0.5, 4.0)
		"blade", "wanderer":
			play("blade_pop", hp, ang)
			sparks(hp, ang, 0.6, 9, 320.0, BLOOD)
			smoke(hp, 3, Color(0.0, 0.0, 0.0, 0.4), 9.0, 14.0, 0.6)


## 冰爆源石虫（mech_foes._blast 调，替掉占位圈）：白闪 → 冰蓝冲击环（主形）+ 雪块碎屑 + 青色火花 + 灰白烟
func icebug_blast(pos: Vector2, r: float) -> void:
	play("icebug_nova", pos, 0.0, r / 55.0)
	sparks(pos, 0.0, PI, 14, 260.0, FROST, true, 0.35)
	embers(pos, 6, Color(0.0, 0.3, 0.7), 150.0, 260.0, 0.55, 4.0)
	embers(pos, 5, Color(0.06, 0.12, 0.22), 120.0, 200.0, 0.45, 4.0)


## 染污躯壳受击暴冲（mech_foes.enemy_spd 调）
func rush(e: Dictionary) -> void:
	if not rushers.has(e):
		rushers.append(e)
	smoke(e.pos, 3, Color(0.02, 0.05, 0.08, 0.45), 8.0, 20.0, 0.6)


## 受击地面痕：爪痕（躯壳）= 三道斜划深槽 + 翻起的雪唇；其他 = 一圈被踩碎的雪块压痕（不画细环，docs/401 §10）
func _mark(pos: Vector2, ang: float, kind: int) -> void:
	if marks.size() >= M_MAX:
		marks.pop_front()
	marks.append([pos, ang, g.t, kind])
	# 踢起的雪块：暗面 + 亮面两色，亮雪地上靠暗面读出来
	embers(pos, 5, GOUGE[1], 130.0, 300.0, 0.45, 4.0)
	embers(pos, 4, GOUGE[2], 110.0, 300.0, 0.45, 4.0)


func draw_ground(w) -> void:
	if marks.is_empty():
		return
	var now: float = g.t
	var keep: Array = []
	for m in marks:
		var age: float = now - float(m[2])
		if age >= 1.4 or age < 0.0:
			continue
		keep.append(m)
		var fade: float = 1.0 - clampf((age - 0.7) / 0.7, 0.0, 1.0)
		var grow: float = clampf(age / 0.09, 0.0, 1.0)   # 划开的过程：前 0.09 秒从起点拉到全长
		var p0: Vector2 = m[0]
		if int(m[3]) == 0:
			var d := Vector2.from_angle(float(m[1]) + 1.05)
			var n := d.orthogonal()
			for i in 3:
				var off: float = (float(i) - 1.0) * 13.0
				var L: float = (58.0 - absf(off) * 0.9) * grow
				var a: Vector2 = p0 + n * off - d * 29.0 + d * 4.0 * float(i)
				var b: Vector2 = a + d * L
				var mid: Vector2 = (a + b) * 0.5
				var wd: float = 6.0 - absf(off) * 0.12
				_gouge(w, a, b, mid + n * wd, mid - n * wd, fade, n)
		else:
			var rr: float = 14.0 + 6.0 * grow
			for i in 7:
				var aa: float = float(i) * TAU / 7.0 + float(m[1])
				var q: Vector2 = p0 + Vector2(cos(aa), sin(aa) * 0.55) * rr
				var s := 4.0 + float(i % 3) * 2.0
				var c1 := GOUGE[0]
				c1.a = 0.85 * fade
				var c2 := GOUGE[2]
				c2.a = fade
				w.tb_quad(_snap(q), _snap(q) + Vector2(s, 0), _snap(q) + Vector2(s, s * 0.6), _snap(q) + Vector2(0, s * 0.6), c1)
				w.tb_quad(_snap(q) + Vector2(0, -2), _snap(q) + Vector2(s, -2), _snap(q) + Vector2(s, 0), _snap(q), c2)
	marks = keep
	w.tb_flush()


func _gouge(w, a: Vector2, b: Vector2, l: Vector2, r: Vector2, fade: float, n: Vector2) -> void:
	var lip := GOUGE[2]
	lip.a = fade
	var wall := GOUGE[1]
	wall.a = 0.9 * fade
	var deep := GOUGE[0]
	deep.a = 0.95 * fade
	w.tb_poly(PackedVector2Array([a, l + n * 2.0, b, r - n * 2.0]), lip)    # 翻起的雪唇（亮，压在槽外沿）
	w.tb_poly(PackedVector2Array([a, l, b, r]), wall)
	w.tb_poly(PackedVector2Array([a.lerp(b, 0.08), l.lerp(r, 0.25), b.lerp(a, 0.1), r.lerp(l, 0.25)]), deep)


## ---- 绘制
func draw_front(w) -> void:
	var cv = g.wcv
	var now: float = g.t
	_tick_rush(now)
	_own_bullets(cv, now)
	# 帧条（旋转要换画布变换，画完复位，后面的合批三角形要求单位矩阵）
	var keep: Array = []
	for s in strips:
		var m: Dictionary = meta[s[0]]
		var fi: int = int((now - float(s[3])) * float(m.fps))
		if fi >= int(m.frames) or fi < 0:
			continue
		keep.append(s)
		var sz := Vector2(float(m.size[0]), float(m.size[1]))
		var org := Vector2(float(m.origin[0]), float(m.origin[1]))
		var k: float = float(s[4]) * PX
		cv.draw_set_transform(s[1], float(s[2]), Vector2(k, k))
		cv.draw_texture_rect_region(tex[s[0]], Rect2(-org, sz), Rect2(Vector2(sz.x * fi, 0), sz))
	strips = keep
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 颗粒
	var live: Array = []
	for p in parts:
		var age: float = now - float(p[2])
		var life: float = p[3]
		if age >= life:
			continue
		live.append(p)
		if age < 0.0:
			continue
		var u: float = age / life
		var pos: Vector2 = p[0] + p[1] * age + Vector2(0, 0.5 * float(p[7]) * age * age)
		var col: Color = p[4]
		match int(p[6]):
			1:
				var c := Color(col.r, col.g, col.b, col.a * (1.0 - u) * minf(1.0, age * 8.0))
				w.tb_circle(pos, float(p[5]) * (0.7 + 0.6 * u), c, 0.8, 10)
			2:
				var v: Vector2 = p[1] * (1.0 - u * 0.6)
				var tail: Vector2 = pos - v * 0.05
				var c2 := col.lerp(Color(col.r * 0.3, col.g * 0.3, col.b * 0.35), u)
				c2.a = 1.0 - u * u
				w.tb_line(_snap(tail), _snap(pos), c2, float(p[5]) * 0.75)
			_:
				var c3 := col
				c3.a = 1.0 - u * u
				var q := _snap(pos)
				var sz: float = maxf(PX, floorf(float(p[5]) / PX) * PX)
				w.tb_quad(q, q + Vector2(sz, 0), q + Vector2(sz, sz), q + Vector2(0, sz), c3)
	parts = live
	w.tb_flush()


func _snap(p: Vector2) -> Vector2:
	return (p / PX).floor() * PX


## 暴冲中的躯壳：每 0.07 秒在身后留一团暗烟 + 偶尔一根上升细线（原作 smsbr_buff_01：Line01 上升线 + smoke 暗烟 0.02,0.05,0.08）
func _tick_rush(now: float) -> void:
	if rushers.is_empty():
		return
	var keep: Array = []
	for e in rushers:
		if e.dead or now >= float(e.get("hr_until", 0.0)):
			continue
		keep.append(e)
		if now - float(e.get("sfx_rt", -9.0)) >= 0.07:
			e["sfx_rt"] = now
			var back: Vector2 = e.pos + Vector2(rng.randf_range(-5, 5), rng.randf_range(-12, 0))
			_add(back, Vector2(0, -10), 0.5, Color(0.02, 0.05, 0.08, 0.5), 7.0, 1)
			if rng.randf() < 0.5:
				_add(e.pos + Vector2(rng.randf_range(-10, 10), -rng.randf_range(4, 24)), Vector2(0, -60), 0.35, Color(0.75, 0.8, 0.86), 2.0, 2)
	rushers = keep


## 专属弹体：施法者黑针（原作 smwiz bullet：黑菱形 0.02 + 冰蓝白淡晕 0.87,0.91,0.99 α0.22 + 身后白 → 钢蓝 → 黑火花）；
## 利刃刃片（原作 smgrd bullet01 黑 + bullet02 红 1,0.1,0.1：黑刃身、红刃口、白芯线，沿飞行方向）
func _own_bullets(cv, now: float) -> void:
	for b in g.ebullets:
		if b.life <= 0.0:
			continue
		var st: String = str(b.get("src_type", ""))
		var kind: String = OWN.get(st, "")
		if kind == "":
			continue
		if kind == "blade" and not b.get("mc", false):
			continue
		if not b.get("sfx_seen", false):
			b["sfx_seen"] = true
			b["own_draw"] = true
			b["sfx_own"] = true   # 光学拖尾 / 照地光 / Boss 弹拖尾也跳过（optical_particles、optical、bullet_fx）
			if kind == "needle":
				play("caster_star", b.pos + Vector2(0, -16), 0.0, 1.7)
			elif int(b.get("tier", 0)) >= 2:
				play("blade_star", b.pos, 0.0, 0.7)
		var v: Vector2 = b.vel
		var a: float = v.angle() if v.length_squared() > 1.0 else float(b.get("ang", 0.0))
		var d := Vector2.from_angle(a)
		var nrm := d.orthogonal()
		var bp: Vector2 = b.pos + Vector2(0, -16)
		if kind == "needle":
			# 敌弹规格（docs/392 §6）：白芯 + 冰蓝色环 + 黑靛暗边（原作黑针收成暗边），沿飞行方向拉长的米粒；
			# 身后一条由冰蓝到透明的锥形拖尾 + 白芯短尾 + 碎冰颗粒。1 倍全景（镜头缩小）在亮雪地上也要一眼看到（11-25 协调人退回）
			var L := 22.0
			var W := 9.0
			var TL := 64.0
			var ice := Color(0.3, 0.6, 1.0)
			cv.draw_polygon(PackedVector2Array([bp + nrm * W * 0.85, bp - d * TL, bp - nrm * W * 0.85]),
				PackedColorArray([Color(ice, 0.8), Color(ice, 0.0), Color(ice, 0.8)]))
			cv.draw_polygon(PackedVector2Array([bp + nrm * 3.0, bp - d * TL * 0.55, bp - nrm * 3.0]),
				PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9)]))
			var dk := Color(0.03, 0.04, 0.12)
			cv.draw_colored_polygon(PackedVector2Array([bp + d * (L + 3.0), bp + nrm * (W + 2.5), bp - d * (L * 0.75 + 3.0), bp - nrm * (W + 2.5)]), dk)
			cv.draw_colored_polygon(PackedVector2Array([bp + d * L, bp + nrm * W, bp - d * L * 0.75, bp - nrm * W]), Color(0.36, 0.66, 1.0))
			cv.draw_colored_polygon(PackedVector2Array([bp + d * L * 0.7, bp + nrm * W * 0.45, bp - d * L * 0.45, bp - nrm * W * 0.45]), Color(1, 1, 1))
			if now - float(b.get("sfx_tt", -9.0)) > 0.04:
				b["sfx_tt"] = now
				_add(bp - d * 14.0 + nrm * rng.randf_range(-6, 6), -v * 0.12 + nrm * rng.randf_range(-25, 25), 0.4, [Color(1, 1, 1), Color(0.2, 0.45, 0.9), dk][rng.randi() % 3], 4.0, 0)
		else:
			var tier: int = int(b.get("tier", 0))
			var L2: float = [9.0, 12.0, 20.0][clampi(tier, 0, 2)]
			var W2: float = [3.0, 4.0, 7.0][clampi(tier, 0, 2)]
			var hold: bool = float(b.get("age", 1.0)) < float(b.get("hold", 0.0))
			var tip: Vector2 = bp + d * L2
			var tail2: Vector2 = bp - d * L2
			var arc := nrm * W2
			# 弯刃：前凸后凹的月牙片
			var body := PackedVector2Array([tip, bp + arc * 1.1 + d * L2 * 0.2, tail2 + arc * 0.4, bp + arc * 0.35, tail2 - arc * 0.2, bp - arc * 0.5])
			cv.draw_colored_polygon(body, Color(0.06, 0.02, 0.02, 0.95 if not hold else 0.6))
			cv.draw_polyline(PackedVector2Array([tip, bp + arc * 1.1 + d * L2 * 0.2, tail2 + arc * 0.4]), Color(1.0, 0.12, 0.08), 2.0)
			cv.draw_line(bp - d * L2 * 0.4 + arc * 0.3, tip - d * 2.0, Color(1, 0.9, 0.85, 0.9), 1.0)
			if not hold and tier >= 1 and now - float(b.get("sfx_tt", -9.0)) > 0.06:
				b["sfx_tt"] = now
				_add(tail2, -v * 0.1 + nrm * rng.randf_range(-15, 15), 0.3, BLOOD[rng.randi_range(1, 3)], 2.0, 0)
