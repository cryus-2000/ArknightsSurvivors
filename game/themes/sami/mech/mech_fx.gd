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
# 邪魔的利刃 / 游荡者（docs/393 §11.2 新招，docs/401 §11）：黑刃 + 深红刃口 + 白芯；黑雾 = 实心暗紫黑像素块（不做半透明烟团）
const BK := Color(0.05, 0.03, 0.05)
const OLC := Color(0.02, 0.02, 0.04)
const FOG := [Color(0.05, 0.035, 0.06), Color(0.11, 0.07, 0.11), Color(0.2, 0.13, 0.18)]
var blade_list := {}         # id → [e, 最近一次 blade_draw 的 t]（blade.gd.draw 每帧登记，地面 / 顶层两处画）
var bevents: Array = []      # [种类, 位置, a, 触发 t, 已触发]
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
	_blade_ground(w, g.t)
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
	_blade_front(w, now)
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
			3:
				var q3 := _snap(pos)
				var s3: float = maxf(PX, floorf(float(p[5]) * (1.0 - u * 0.75) / PX) * PX)
				w.tb_quad(q3, q3 + Vector2(s3, 0), q3 + Vector2(s3, s3), q3 + Vector2(0, s3), col)
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
			var r0: float = float(b.get("r", 7.0))
			var L2: float = r0 * 1.9
			var W2: float = r0 * 1.0
			var hold: bool = float(b.get("age", 1.0)) < float(b.get("hold", 0.0))
			var tip: Vector2 = bp + d * L2
			var tail2: Vector2 = bp - d * L2
			var arc := nrm * W2
			# 弯刃：前凸后凹的月牙片，三层（暗边 / 深红刃身 / 白芯）
			var al: float = 1.0 if not hold else 0.55
			cv.draw_colored_polygon(_crescent(bp, d, nrm, L2 + 3.0, W2 + 2.5), Color(OLC, al))
			cv.draw_colored_polygon(_crescent(bp, d, nrm, L2, W2), Color(0.85, 0.08, 0.07, al))
			cv.draw_colored_polygon(_crescent(bp + nrm * W2 * 0.15, d, nrm, L2 * 0.62, W2 * 0.42), Color(1.0, 0.95, 0.92, al))
			if not hold and tier >= 1 and now - float(b.get("sfx_tt", -9.0)) > 0.06:
				b["sfx_tt"] = now
				_add(tail2, -v * 0.1 + nrm * rng.randf_range(-15, 15), 0.3, BLOOD[rng.randi_range(1, 3)], 2.0, 0)



## 月牙片：前凸后凹，d 朝前、nrm 朝凸面
func _crescent(c: Vector2, d: Vector2, nrm: Vector2, L: float, W: float) -> PackedVector2Array:
	return PackedVector2Array([c + d * L, c + nrm * W * 0.7 + d * L * 0.45, c + nrm * W, c + nrm * W * 0.6 - d * L * 0.6, c - d * L,
		c + nrm * W * 0.15 - d * L * 0.3, c + nrm * W * 0.25 + d * L * 0.2])


## ---- 邪魔的利刃 / 游荡者
func blade_draw(e: Dictionary) -> void:
	blade_list[int(e.id)] = [e, g.t]


func blade_event(kind: String, p: Vector2, a := 0.0, b := 0.0) -> void:
	match kind:
		"slash":
			# 斩击·竖刃挥刃：大月牙刀光（r130 扇形）+ 扇区腾起黑雾 + 深红火花
			bevents.append(["slash", p, a, g.t, false])
			for i in 30:
				var q: Vector2 = p + Vector2.from_angle(a + rng.randf_range(-PI / 3.0, PI / 3.0)) * rng.randf_range(40.0, 130.0)
				_fog(q, 1, 0.5, 0.15 * float(i % 5) / 5.0)
			sparks(p + Vector2.from_angle(a) * 80.0, a, 1.0, 16, 360.0, BLOOD)
		"erupt", "rain":
			bevents.append([kind, p, a, g.t + b, false])


## 雾块：实心暗色方块，往上飘、慢慢缩小
func _fog(p: Vector2, n: int, life := 0.7, delay := 0.0) -> void:
	for i in n:
		_add(p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4)), Vector2(rng.randf_range(-18, 18), -rng.randf_range(10, 30)),
			life * rng.randf_range(0.7, 1.2), FOG[rng.randi() % 3], rng.randf_range(6.0, 11.0), 3, 0.0, delay)


## 竖刃：底 base，高 h；lean 0 = 直立，1 = 朝 ld 倒伏；暗描边 → 黑刃身 → 一侧深红刃口 → 白芯线；脚下一道裂缝
func _rise_blade(w, base: Vector2, h: float, ld: Vector2, lean: float, wd := 11.0) -> void:
	if h < 2.0:
		return
	var up: Vector2 = Vector2(0, -1).lerp(ld * 0.8, lean)
	up = up.normalized()
	var n := up.orthogonal()
	var hw: float = wd * 0.5
	var m: float = 0.55
	w.tb_quad(_snap(base - n * (hw + 5.0) + Vector2(0, -1)), _snap(base + n * (hw + 5.0) + Vector2(0, -1)), _snap(base + n * (hw + 3.0) + Vector2(0, 3)), _snap(base - n * (hw + 3.0) + Vector2(0, 3)), FOG[0])
	w.tb_poly(PackedVector2Array([base - n * (hw + 2.0), base + up * h * m - n * (hw + 2.0), base + up * (h + 4.0), base + up * h * m + n * (hw + 2.0), base + n * (hw + 2.0)]), OLC)
	w.tb_poly(PackedVector2Array([base - n * hw, base + up * h * m - n * hw, base + up * h, base + up * h * m + n * hw, base + n * hw]), BK)
	w.tb_poly(PackedVector2Array([base + n * (hw - 3.0), base + up * h * m + n * (hw - 3.0), base + up * h, base + up * h * m + n * hw, base + n * hw]), BLOOD[2])
	w.tb_line(_snap(base + up * 4.0), _snap(base + up * (h - 6.0)), Color(1.0, 0.95, 0.92), 2.0)


func _blade_ground(w, now: float) -> void:
	# 斩击·竖刃预警：扇形边 = 实心暗块 + 深红块（6 像素，r130 一眼看出范围）；黑雾从它脚下按进度往外铺
	for t in g.warns:
		if t.done or t.shape != "cone" or str(t.get("name", "")) != "斩击·竖刃":
			continue
		var k: float = clampf(float(t.t) / maxf(0.01, float(t.dur)), 0.0, 1.0)
		var r3: float = float(t.r)
		var a0: float = float(t.ang) - float(t.half)
		var a1: float = float(t.ang) + float(t.half)
		var n3: int = int((a1 - a0) * r3 / 10.0)
		for i in n3 + 1:
			var q: Vector2 = _snap(t.pos + Vector2.from_angle(lerpf(a0, a1, float(i) / float(n3))) * r3)
			var cc: Color = BLOOD[1] if i % 3 == 0 else FOG[0]
			w.tb_quad(q, q + Vector2(6, 0), q + Vector2(6, 6), q + Vector2(0, 6), cc)
		for sa in [a0, a1]:
			var z := 18.0
			while z < r3:
				var q2: Vector2 = _snap(t.pos + Vector2.from_angle(sa) * z)
				w.tb_quad(q2, q2 + Vector2(4, 0), q2 + Vector2(4, 4), q2 + Vector2(0, 4), FOG[0])
				z += 10.0
		var rr := 24.0
		while rr < r3 * k:
			var na: int = maxi(3, int((a1 - a0) * rr / 12.0))
			for j in na:
				var hsh: int = absi(hash(Vector2i(int(rr), j)))
				if hsh % 100 < 38:
					var q3: Vector2 = _snap(t.pos + Vector2.from_angle(lerpf(a0, a1, (float(j) + 0.5) / float(na))) * rr)
					var sz: float = 6.0 + float(hsh % 2) * 2.0
					w.tb_quad(q3, q3 + Vector2(sz, 0), q3 + Vector2(sz, sz), q3 + Vector2(0, sz), FOG[hsh % 3])
			rr += 12.0
	for id in blade_list.keys():
		var it: Array = blade_list[id]
		var e: Dictionary = it[0]
		if e.dead or now - float(it[1]) > 0.2:
			blade_list.erase(id)
			continue
		# 黑毯（铺开中；铺完由国度占位接手）：带身 = 散布的实心雾块（按格子哈希，中线密、两侧疏），毯头 = 翻滚的大雾块
		for c in e.get("cps", []):
			if float(c.front) <= 0.0 or c.get("k") != null:
				continue
			var a0: Vector2 = c.a
			var dv: Vector2 = c.dir
			var nv := dv.orthogonal()
			var hw: float = float(c.hw)
			var fr: float = float(c.front)
			var si := 0.0
			while si < fr:
				var tj := -hw
				while tj <= hw:
					var hsh: int = absi(hash(Vector2i(int(si / 8.0), int(tj / 8.0)) + Vector2i(int(e.id) * 31, 0)))
					var dens: float = 1.0 - absf(tj) / hw * 0.7
					if float(hsh % 100) / 100.0 < dens * 0.75:
						var q: Vector2 = _snap(a0 + dv * si + nv * tj)
						var sz: float = 6.0 + float(hsh % 3) * 2.0
						w.tb_quad(q, q + Vector2(sz, 0), q + Vector2(sz, sz), q + Vector2(0, sz), FOG[hsh % 2])
					tj += 8.0
				si += 8.0
			var hd: Vector2 = a0 + dv * fr
			for k in 7:
				var ph: float = now * 9.0 + float(k) * 0.9
				var q2: Vector2 = _snap(hd + nv * sin(ph) * hw * 0.8 + dv * (cos(ph * 0.7) * 6.0 - 4.0))
				var s2: float = 10.0 + float(k % 3) * 3.0
				w.tb_quad(q2, q2 + Vector2(s2, 0), q2 + Vector2(s2, s2), q2 + Vector2(0, s2), FOG[k % 3])
			if rng.randf() < 0.6:
				_fog(hd + nv * rng.randf_range(-hw, hw), 1, 0.5)
			if rng.randf() < 0.25:
				sparks(hd, dv.angle(), 0.6, 1, 160.0, BLOOD)
	w.tb_flush()


func _blade_front(w, now: float) -> void:
	for id in blade_list:
		var e: Dictionary = blade_list[id][0]
		if e.dead:
			continue
		for x in e.get("ents", []):
			var t: float = float(x.t)
			var hold: float = float(x.hold)
			var life: float = float(x.life)
			if not x.get("fx_seen", false):
				x["fx_seen"] = true
				if x.k == "rise":
					_fog(x.pos, 5, 0.6)   # 竖刃先从地上冒一团黑雾
			if x.k == "rise":
				# 出现：前 0.06 秒只有雾，0.06–0.18 秒从雾里竖起；倒伏滑出；最后 0.12 秒沉回地里
				var tot: float = hold + life
				var hk: float = clampf((t - 0.06) / 0.12, 0.0, 1.0)
				hk = 1.0 - (1.0 - hk) * (1.0 - hk)
				var sink: float = clampf((tot - t) / 0.12, 0.0, 1.0)
				var lean: float = clampf((t - hold) / 0.12, 0.0, 1.0) * 0.85 if hold > 0.0 else 0.0
				var ld: Vector2 = Vector2.from_angle(float(x.get("ang", 0.0))) if x.has("ang") else Vector2.RIGHT
				_rise_blade(w, x.pos, 38.0 * hk * sink, ld, lean)
				if hold > 0.0 and t > hold and rng.randf() < 0.3:
					_fog(x.pos, 1, 0.4)
			else:
				# 大刃片：旋转的月牙大刃（半宽 24），身后拖黑雾 + 深红火花
				var c: Vector2 = x.pos + Vector2(0, -16)
				var rot: float = t * 14.0
				var d := Vector2.from_angle(rot)
				var R: float = float(x.r)
				w.tb_poly(_crescent(c, d, d.orthogonal(), R * 1.25 + 3.0, R * 0.75 + 3.0), OLC)
				w.tb_poly(_crescent(c, d, d.orthogonal(), R * 1.25, R * 0.75), BLOOD[1])
				w.tb_poly(_crescent(c + d.orthogonal() * R * 0.2, d, d.orthogonal(), R * 0.9, R * 0.35), BK)
				w.tb_poly(_crescent(c + d.orthogonal() * R * 0.45, d, d.orthogonal(), R * 0.7, R * 0.16), Color(1.0, 0.95, 0.92))
				var d2 := -d
				w.tb_poly(_crescent(c, d2, d2.orthogonal(), R * 0.8 + 2.0, R * 0.4 + 2.0), OLC)
				w.tb_poly(_crescent(c, d2, d2.orthogonal(), R * 0.8, R * 0.4), BLOOD[2])
				if t >= hold:
					_fog(x.pos - x.vel.normalized() * 14.0, 1, 0.5)
					if rng.randf() < 0.4:
						sparks(c, x.vel.angle() + PI, 0.5, 1, 140.0, BLOOD)
		# 呼吸：它的国度往外胀时，边上一圈雾块往外涌（不画细环）
		if float(e.get("br_until", 0.0)) > now:
			var km = g.mech("kingdom")
			if km != null:
				var sw: float = (35.0 if e.type == "wanderer" else 20.0) * sin(PI * (1.0 - (float(e.br_until) - now) / 0.6))
				for k in km.list:
					if int(k.owner_id) == int(e.id) and k.kind == "boss":
						for j in 12:
							var aa: float = rng.randf() * TAU
							var q: Vector2 = k.pos + Vector2.from_angle(aa) * (float(k.r) + sw)
							_add(q, Vector2.from_angle(aa) * 50.0 + Vector2(0, -10), 0.45, FOG[rng.randi() % 3], rng.randf_range(8.0, 13.0), 3)
	# 刃林喷发（国度爆发 / 皇帝的猎杀）、刃雨
	var keep: Array = []
	for ev in bevents:
		var tf: float = ev[3]
		var age: float = now - tf
		var p: Vector2 = ev[1]
		if ev[0] == "slash":
			# 挥刃：月牙刀带 0.1 秒从扇形一边扫到另一边（刀头白、刀身深红、尾巴黑），0.1–0.28 秒尾巴追上收掉
			if age > 0.28:
				continue
			keep.append(ev)
			var ca: float = ev[2]
			var e0: float = ca - PI / 3.0 - 0.1
			var e1: float = ca + PI / 3.0 + 0.1
			var hd: float = lerpf(e0, e1, 1.0 - pow(1.0 - clampf(age / 0.1, 0.0, 1.0), 2.0))
			var tl: float = maxf(e0, maxf(hd - 1.5, lerpf(e0, e1, clampf((age - 0.1) / 0.18, 0.0, 1.0))))
			var ns := 18
			for pass_i in 2:
				for j in ns:
					var f0: float = float(j) / float(ns)
					var f1: float = float(j + 1) / float(ns)
					var b0: float = lerpf(tl, hd, f0)
					var b1: float = lerpf(tl, hd, f1)
					var o: float = 3.0 if pass_i == 0 else 0.0
					var ro: float = 130.0 + o
					var ri0: float = 130.0 - (6.0 + 26.0 * f0) - o   # 尾细头粗
					var ri1: float = 130.0 - (6.0 + 26.0 * f1) - o
					var cc: Color = OLC
					if pass_i == 1:
						cc = Color(1.0, 0.95, 0.92) if f0 > 0.86 else (BLOOD[2] if f0 > 0.55 else (BLOOD[1] if f0 > 0.25 else BK))
					w.tb_quad(p + Vector2.from_angle(b0) * ro, p + Vector2.from_angle(b1) * ro, p + Vector2.from_angle(b1) * ri1, p + Vector2.from_angle(b0) * ri0, cc)
			continue
		if ev[0] == "erupt":
			if age > 0.6:
				continue
			keep.append(ev)
			if age < 0.0:
				continue
			var kr: float = ev[2]
			if not ev[4]:
				ev[4] = true
				for i in 18:
					_fog(p + Vector2.from_angle(TAU * i / 18.0) * kr * rng.randf_range(0.3, 0.95), 1, 0.7)
				sparks(p, 0.0, PI, 14, 300.0, BLOOD, true, 0.35)
			var nb: int = clampi(int(kr / 6.0), 8, 16)
			for i in nb:
				var dl: float = float(i) * 0.012
				var hk: float = clampf((age - dl) / 0.1, 0.0, 1.0)
				hk = 1.0 - (1.0 - hk) * (1.0 - hk)
				var sink: float = clampf((0.6 - age) / 0.2, 0.0, 1.0)
				var q: Vector2 = p + Vector2.from_angle(float(i) * 2.399) * kr * 0.85 * sqrt((float(i) + 0.5) / float(nb))
				_rise_blade(w, q, (30.0 + float(i % 3) * 6.0) * hk * sink, Vector2.RIGHT, 0.0, 9.0)
		else:
			if age > 0.5:
				continue
			keep.append(ev)
			if age < -0.28:
				continue
			if age < 0.0:
				# 从天上落下的刃：刃尖朝下，两层残影
				var k2: float = (age + 0.28) / 0.28
				for gh in 3:
					var kk: float = clampf(k2 - float(gh) * 0.12, 0.0, 1.0)
					var y: float = -170.0 * (1.0 - kk * kk)
					var tipp: Vector2 = p + Vector2(0, y)
					var col2: Color = BK if gh == 0 else FOG[1 + mini(gh, 1)]
					if gh == 0:
						w.tb_poly(PackedVector2Array([tipp + Vector2(0, 3), tipp + Vector2(-8, -18), tipp + Vector2(0, -44), tipp + Vector2(8, -18)]), OLC)
					w.tb_poly(PackedVector2Array([tipp, tipp + Vector2(-6, -18), tipp + Vector2(0, -40), tipp + Vector2(6, -18)]), col2)
					if gh == 0:
						w.tb_poly(PackedVector2Array([tipp + Vector2(1, -2), tipp + Vector2(6, -18), tipp + Vector2(0, -40), tipp + Vector2(3, -18)]), BLOOD[2])
						w.tb_line(_snap(tipp + Vector2(0, -6)), _snap(tipp + Vector2(0, -34)), Color(1.0, 0.95, 0.92), 2.0)
				continue
			if not ev[4]:
				ev[4] = true
				sparks(p + Vector2(0, -6), -PI * 0.5, 1.3, 10, 260.0, BLOOD, true, 0.3)
				_fog(p, 4, 0.6)
				embers(p, 5, FOG[2], 120.0, 280.0, 0.45, 4.0)
			# 插在地上，0.35 秒后沉下去
			_rise_blade(w, p, 30.0 * clampf((0.5 - age) / 0.15, 0.0, 1.0), Vector2.RIGHT, 0.0, 9.0)
	bevents = keep
	w.tb_flush()
