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
# 黑雾：程序噪声烤出的柔边雾贴图（alpha 分 5 级台阶保持像素感，1 纹素 = 2 世界像素），不用实心方块
var fog_puff: Array = []     # 4 张 32×32 径向雾团
var fog_band: Texture2D      # 128×32 横向可平铺的雾带（上下边柔）
var puffs: Array = []        # 顶层雾团 [p0, v, 出生 t, 寿命, 尺寸 0, 尺寸 1, 图号, 不透明度]
var gpuffs: Array = []       # 地面雾团（黑毯 / 呼吸 / 预警渗雾，压在单位之下）
const PUFF_MAX := 160
var ice_puff: Array = []     # 冰雾团（冰爆 B）
var grey_puff: Array = []    # 国度中间的浅灰雾
var grey_band: Texture2D
var kdir := 1
var ice_ev: Array = []       # 冰爆 [位置, r, 出生 t, 冰块表, 霜点表]
# 结局 Boss（docs/401 §14）
const KHAN := [Color(0.16, 0.02, 0.02), Color(0.45, 0.05, 0.04), Color(0.72, 0.1, 0.06), Color(0.95, 0.32, 0.2)]   # 哈兰暗红 4°
const LUKA := Color(0.95, 1.0, 0.3)          # 路加弹环 / 日晷：金黄 64°（docs/393 §11.11）
const LUKA_D := Color(0.3, 0.2, 0.08)        # 路加暗边：深褐
const LUKA_O := Color(1.0, 0.62, 0.15)       # 路加本体 / 出手火光：金橙
const TEALC := [Color(0.0, 0.04, 0.025), Color(0.0, 0.15, 0.11), Color(0.04, 0.29, 0.21), Color(0.1, 0.44, 0.31), Color(0.29, 0.64, 0.48)]   # 木裂原作 smlead_buff 深青
const LIL := [Color(0.3, 0.16, 0.45), Color(0.54, 0.28, 0.8), Color(0.7, 0.46, 0.95), Color(0.85, 0.7, 1.0), Color(1.0, 0.96, 1.0)]   # 克雷松淡紫 270°
const WILLC := [Color(0.3, 0.22, 0.45), Color(0.62, 0.62, 0.8), Color(0.86, 0.86, 0.98), Color(1.0, 1.0, 1.0)]   # 意志冰白低饱和 + 暗紫边
var flakes: Array = []       # 木裂剥落片 [p0, v, t0, 寿命, 尺寸, 转速, 色]
var trails: Array = []       # 木裂冲刺地痕 [a, b, t0]
var teal_band: Texture2D
var lil_puff: Array = []
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
	for i in 4:
		fog_puff.append(_fog_tex(32, 32, 911 + i, true))
	fog_band = _fog_tex(128, 32, 977, false)
	for i in 3:
		ice_puff.append(_fog_tex(32, 32, 1301 + i, true, Color(0.5, 0.68, 0.9), Color(1.0, 1.0, 1.0)))   # 亮雪地上要读得出：浓处纯白（比雪亮）、稀处冰蓝
		grey_puff.append(_fog_tex(32, 32, 1401 + i, true, Color(0.5, 0.5, 0.54), Color(0.7, 0.7, 0.74)))
	teal_band = _fog_tex(128, 32, 1601, false, Color(0.04, 0.29, 0.21), Color(0.0, 0.06, 0.04))
	for i in 3:
		lil_puff.append(_fog_tex(32, 32, 1701 + i, true, Color(0.54, 0.28, 0.8), Color(0.85, 0.7, 1.0)))
	grey_band = _fog_tex(128, 32, 1501, false, Color(0.5, 0.5, 0.54), Color(0.68, 0.68, 0.72))
	var kd: PackedStringArray = OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()
	for a in kd:
		if a.begins_with("--kdir="):
			kdir = int(a.substr(7))   # 国度烟雾方向样张（docs/401 §13）：1 黑烟间隔 / 2 连续烟墙


## 雾贴图：分形噪声 × 边缘衰减（径向 / 上下），颜色在两档暗紫黑之间，alpha 量化 5 级
func _fog_tex(w: int, h: int, seed: int, radial: bool, c_lo := Color(0.2, 0.13, 0.18), c_hi := Color(0.05, 0.035, 0.06)) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.11 if radial else 0.05
	n.fractal_octaves = 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v: float
			var f: float
			if radial:
				v = n.get_noise_2d(x, y) * 0.5 + 0.5
				var dd: float = Vector2(x - w * 0.5 + 0.5, y - h * 0.5 + 0.5).length() / (w * 0.5)
				f = clampf(1.0 - dd, 0.0, 1.0)
			else:
				var ang: float = TAU * float(x) / float(w)   # 沿长度方向绕圆柱取样 → 首尾无缝
				v = n.get_noise_3d(cos(ang) * 20.0, sin(ang) * 20.0, float(y) * 1.4) * 0.5 + 0.5
				f = clampf(1.0 - absf(y - h * 0.5 + 0.5) / (h * 0.5), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			var a: float = clampf((v * 1.5 - 0.2) * f * 1.5, 0.0, 1.0)
			a = floorf(a * 5.0) / 5.0
			var c: Color = c_lo.lerp(c_hi, clampf(v * 1.3 - 0.1, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


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
## 冰爆源石虫死亡冰爆（用户 11-25 选方向 B 并要深化）：白闪 → 本体炸成三层碎冰（大块带白顶面 / 中块 / 细碎冰闪）抛射、
## 落地弹一次再滑、滑过留霜点；贴地寒雾往外滚着翻卷（冰白雾团两层）；地上留一片霜（冰白点阵，3 秒后按像素蚀掉）。本体不播粉红死亡帧条（mech_foes 标 no_body）
func icebug_blast(pos: Vector2, r: float) -> void:
	var ch: Array = []
	for i in 18:
		var tier: int = 0 if i < 6 else (1 if i < 12 else 2)
		var a: float = TAU * float(i) / 6.0 + rng.randf_range(-0.35, 0.35) + float(tier) * 0.5
		var sp: float = rng.randf_range(0.7, 1.0) * r * [1.15, 1.45, 1.8][tier]
		var vz: float = rng.randf_range(110.0, 170.0) * [0.85, 1.0, 1.15][tier]
		var sz: float = [rng.randf_range(7.0, 9.5), rng.randf_range(4.0, 5.5), 2.0][tier]
		ch.append([a, sp, vz, sz, tier, rng.randf_range(-6.0, 6.0)])
	var fr: Array = []
	for i in 110:
		var aa: float = rng.randf() * TAU
		var rr: float = sqrt(rng.randf()) * r * 0.85
		fr.append([Vector2(cos(aa), sin(aa) * 0.62) * rr, rng.randf(), rng.randi() % 3])
	ice_ev.append([pos, r, g.t, ch, fr])
	if ice_ev.size() > 10:
		ice_ev.pop_front()
	# 寒雾：两层冰白雾团贴地往外滚（外层快、内层慢），带切向分量 → 翻卷
	for i in 14:
		var a2: float = TAU * float(i) / 14.0 + rng.randf_range(-0.2, 0.2)
		var dv := Vector2(cos(a2), sin(a2) * 0.62)
		var tg := Vector2(-dv.y, dv.x) * rng.randf_range(-25.0, 25.0)
		_icefog(pos + dv * 8.0, dv * r * 1.25 + tg, 1.2, rng.randf_range(30.0, 40.0), 1.0)
		_icefog(pos + dv * 4.0, dv * r * 0.6 - tg, 1.6, rng.randf_range(36.0, 48.0), 0.9)
	sparks(pos + Vector2(0, -6), 0.0, PI, 12, 240.0, FROST, true, 0.3)


func _ice_chunk(w, x: Vector2, y: float, s: float, rot: float, al := 1.0) -> void:
	var pts := PackedVector2Array()
	var top := PackedVector2Array()
	for k in 5:
		var aa: float = rot + float(k) * 1.257 + (0.25 if k % 2 == 0 else -0.15)
		var rr: float = s * (1.0 if k % 2 == 0 else 0.75)
		pts.append(Vector2(x.x + cos(aa) * rr, y + sin(aa) * rr * 0.8))
	var c := Vector2(x.x, y)
	var big: PackedVector2Array = PackedVector2Array()
	for q in pts:
		big.append(c + (q - c) * (1.0 + 2.5 / maxf(s, 1.0)))
	w.tb_poly(big, Color(OLC, al))
	w.tb_poly(pts, Color(0.0, 0.34, 1.0, al))
	top.append(c + (pts[0] - c) * 0.9)
	top.append(c + (pts[1] - c) * 0.9)
	top.append(c + (pts[2] - c) * 0.5)
	top.append(c)
	w.tb_poly(top, Color(0.54, 0.89, 1.0, al))
	if s >= 6.0:
		w.tb_poly(PackedVector2Array([c + (pts[0] - c) * 0.75, c + (pts[1] - c) * 0.7, c + (pts[0] - c) * 0.2]), Color(0.95, 0.99, 1.0, al))


func _ice_pos(c: Array, t: float, pos: Vector2) -> Array:
	var a: float = c[0]
	var sp: float = c[1]
	var vz: float = c[2]
	var gg := 520.0
	var t1: float = 2.0 * vz / gg
	var z := 0.0
	var dist := 0.0
	var landed := false
	if t < t1:
		z = vz * t - 0.5 * gg * t * t
		dist = sp * t / t1 * 0.75
	else:
		landed = true
		var tb: float = t - t1
		var vz2: float = vz * 0.32
		var t2: float = 2.0 * vz2 / gg
		if tb < t2:
			z = vz2 * tb - 0.5 * gg * tb * tb
			dist = sp * 0.75 + sp * 0.15 * tb / t2
		else:
			dist = sp * 0.9 + sp * 0.1 * (1.0 - exp(-(tb - t2) * 5.0))
	var dv := Vector2(cos(a), sin(a) * 0.62)
	return [pos + dv * dist, z, landed]


func _draw_ice_ground(w, now: float) -> void:
	var keep: Array = []
	for ev in ice_ev:
		var age: float = now - float(ev[2])
		if age > 4.0:
			continue
		keep.append(ev)
		var pos: Vector2 = ev[0]
		var r: float = ev[1]
		# 地上留霜：先从中心铺开（0.2 秒），3 秒后按像素蚀掉
		var grow: float = clampf(age / 0.2, 0.0, 1.0)
		var er: float = clampf((age - 2.6) / 1.4, 0.0, 1.0)
		for f in ev[4]:
			var q: Vector2 = f[0]
			if q.length() > r * 0.85 * grow or float(f[1]) < er:
				continue
			var pp: Vector2 = _snap(pos + q + Vector2(0, 2))
			var cc: Color = [Color(0.97, 0.99, 1.0), Color(0.45, 0.68, 0.95), Color(0.3, 0.52, 0.85)][int(f[2])]
			var sz: float = 4.0 if int(f[2]) == 0 else 2.0
			if int(f[2]) == 0:
				w.tb_quad(pp + Vector2(0, 2), pp + Vector2(sz, 2), pp + Vector2(sz, 4), pp + Vector2(0, 4), Color(0.38, 0.6, 0.9))   # 白霜下沿一道冰蓝影，亮雪地上读得出
			w.tb_quad(pp, pp + Vector2(sz, 0), pp + Vector2(sz, 2), pp + Vector2(0, 2), cc)
		# 冰块滑过的霜点 + 落地的冰块阴影
		for c in ev[3]:
			if int(c[4]) == 2:
				continue
			for k in 5:
				var tk: float = age - 0.02 - float(k) * 0.06
				if tk <= 0.0:
					continue
				var st: Array = _ice_pos(c, tk, pos)
				if st[2] and age < 2.6 + float(k) * 0.2:
					var pp2: Vector2 = _snap(st[0])
					w.tb_quad(pp2, pp2 + Vector2(2, 0), pp2 + Vector2(2, 2), pp2 + Vector2(0, 2), Color(0.9, 0.96, 1.0))
	ice_ev = keep


func _draw_ice_front(w, now: float) -> void:
	for ev in ice_ev:
		var age: float = now - float(ev[2])
		var pos: Vector2 = ev[0]
		if age < 0.12:
			# 白闪：实心不规则核
			var u: float = age / 0.12
			var rr: float = 12.0 + 10.0 * u
			var pts := PackedVector2Array()
			for k in 8:
				var aa: float = float(k) * 0.785 + 0.3
				pts.append(pos + Vector2(0, -8) + Vector2(cos(aa) * rr * (1.0 if k % 2 else 0.6), sin(aa) * rr * (0.75 if k % 2 else 0.45)))
			w.tb_poly(pts, Color(0.0, 0.79, 1.0) if u > 0.6 else Color(0.95, 0.99, 1.0))
		for c in ev[3]:
			var tt: float = age - 0.02
			if tt <= 0.0 or tt > 1.9:
				continue
			var st: Array = _ice_pos(c, tt, pos + Vector2(0, -4))
			var p: Vector2 = st[0]
			var z: float = st[1]
			var melt: float = clampf((1.9 - tt) / 0.4, 0.0, 1.0)
			if int(c[4]) == 2:
				# 细碎冰闪：白 / 冰青两色 2 像素，空中闪
				if int(tt * 20.0) % 3 != 0:
					var pp: Vector2 = _snap(p - Vector2(0, z))
					w.tb_quad(pp, pp + Vector2(2, 0), pp + Vector2(2, 2), pp + Vector2(0, 2), Color(0.95, 0.99, 1.0) if int(c[5] * 10.0) % 2 == 0 else Color(0.54, 0.89, 1.0))
				continue
			if z > 1.0:
				var sh: Vector2 = _snap(p)
				w.tb_quad(sh - Vector2(3, 0), sh + Vector2(3, 0), sh + Vector2(3, 2), sh - Vector2(3, 2), Color(0.42, 0.48, 0.6, 0.7))
			var spin: float = float(c[5]) * minf(tt, 0.45) if not st[2] else float(c[5]) * 0.45
			_ice_chunk(w, p, p.y - z, float(c[3]) * (0.5 + 0.5 * melt), spin)
	w.tb_flush()



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
	_draw_ice_ground(w, g.t)
	_final_ground(w, g.t)
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
	puffs = _draw_puffs(cv, puffs, now)
	_blade_front(w, now)
	_draw_ice_front(w, now)
	_final_front(w, cv, now)
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
			# 碎刃（用户 11-25：旋转红月牙「太幽默」）：贴地滑行的竖刃，刃身朝前微倾，身后犁出黑雾 + 火星；显形期从雾里竖起。
			# 尺寸照水月中期 Boss 弹同档：高 = r × 3.4（中 24 / 大 34），宽 = r × 1.2
			var r0: float = float(b.get("r", 7.0))
			var hold_t: float = float(b.get("hold", 0.0))
			var ag: float = float(b.get("age", 1.0))
			var up: float = clampf(ag / maxf(0.12, hold_t), 0.0, 1.0) if hold_t > 0.0 else clampf(ag / 0.1, 0.0, 1.0)
			up = 1.0 - (1.0 - up) * (1.0 - up)
			var base: Vector2 = b.pos
			_stand_blade(cv, base, r0 * 3.4 * up, r0 * 1.2, d, 0.25)
			if now - float(b.get("sfx_tt", -9.0)) > 0.05:
				b["sfx_tt"] = now
				_fog(base - d * 10.0, 1, 0.45, 0.0, true, 0.55, -v * 0.15)
				if rng.randf() < 0.5:
					_add(base, -v * 0.2 + nrm * rng.randf_range(-30, 30), 0.25, BLOOD[rng.randi_range(2, 3)], 2.0, 2)



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
		"flake", "whip", "lash":
			bevents.append([kind, p, a, g.t, false, b])
		"dial":
			bevents.append([kind, p, a, g.t, false, b, -1])


## 雾团：柔边雾贴图往外翻卷、慢慢胀大淡出（ground = 压在单位之下）
func _fog(p: Vector2, n: int, life := 0.7, delay := 0.0, ground := false, sz := 1.0, v := Vector2.INF) -> void:
	var arr: Array = gpuffs if ground else puffs
	for i in n:
		if arr.size() >= PUFF_MAX:
			arr.pop_front()
		var vv: Vector2 = v if v != Vector2.INF else Vector2(rng.randf_range(-22, 22), -rng.randf_range(6, 22))
		vv += Vector2(rng.randf_range(-8, 8), rng.randf_range(-6, 6))
		var s0: float = rng.randf_range(22.0, 34.0) * sz
		arr.append([p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4)), vv, g.t + delay, life * rng.randf_range(0.8, 1.2), s0, s0 * rng.randf_range(1.6, 2.2), rng.randi() % 4, rng.randf_range(0.75, 0.95), 0])


## 冰雾团：同雾团，换冰白贴图（第 9 项 = 1）；画在顶层——地面层有受光封顶，比雪亮的白雾会被压平
func _icefog(p: Vector2, v: Vector2, life: float, sz: float, al := 0.85) -> void:
	if puffs.size() >= PUFF_MAX:
		puffs.pop_front()
	puffs.append([p, v, g.t, life, sz, sz * rng.randf_range(1.7, 2.3), rng.randi() % 3, al, 1])


func _draw_puffs(cv, arr: Array, now: float) -> Array:
	var live: Array = []
	for q in arr:
		var age: float = now - float(q[2])
		if age >= float(q[3]):
			continue
		live.append(q)
		if age < 0.0:
			continue
		var u: float = age / float(q[3])
		var pos: Vector2 = q[0] + q[1] * age * (1.0 - 0.45 * u)
		var sz: float = lerpf(float(q[4]), float(q[5]), 1.0 - (1.0 - u) * (1.0 - u))
		var al: float = float(q[7]) * pow(1.0 - u, 1.4) * minf(1.0, age * 12.0)
		var r := Rect2(((pos - Vector2(sz, sz) * 0.5) / PX).floor() * PX, Vector2(sz, sz * 0.8))
		var tx: Texture2D = ice_puff[int(q[6]) % 3] if int(q[8]) == 1 else fog_puff[int(q[6])]
		cv.draw_texture_rect(tx, r, false, Color(1, 1, 1, al))
		if int(q[8]) == 1:
			cv.draw_texture_rect(ice_puff[(int(q[6]) + 1) % 3], r.grow(-sz * 0.12), false, Color(1, 1, 1, al))   # 冰雾叠一层更浓
	return live


## 雾带：沿 a→b 铺平铺雾贴图（宽 2·hw，上下边柔），al 控浓淡
func _band(cv, a: Vector2, b: Vector2, hw: float, al: float) -> void:
	var L: float = a.distance_to(b)
	if L < 2.0:
		return
	cv.draw_set_transform(a, (b - a).angle(), Vector2.ONE)
	var H: float = hw * 2.6
	var x := 0.0
	var seg: float = 256.0
	while x < L:
		var ln: float = minf(seg, L - x)
		cv.draw_texture_rect_region(fog_band, Rect2(x, -H * 0.5, ln, H), Rect2(0, 0, 128.0 * ln / seg, 32), Color(1, 1, 1, al))
		x += seg
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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


## 刃尖冒头：地上一点黑刃尖（高 h），预警进度越后越高
func _tip(w, base: Vector2, h: float) -> void:
	if h < 1.5:
		return
	w.tb_poly(PackedVector2Array([base + Vector2(-6, 2), base + Vector2(0, -h - 3), base + Vector2(6, 2)]), OLC)
	w.tb_poly(PackedVector2Array([base + Vector2(-4, 0), base + Vector2(0, -h), base + Vector2(4, 0)]), BK)
	w.tb_poly(PackedVector2Array([base + Vector2(0, -h), base + Vector2(4, 0), base + Vector2(1, 0)]), BLOOD[2])


## 地面裂缝：从 a 往 ang 方向长 L 的折线（种子 sd 定形状），k 控长出多少；暗槽 + 深红芯
func _crack(w, a: Vector2, ang: float, L: float, k: float, sd: int, wd := 3.0) -> void:
	var n: int = maxi(2, int(L / 14.0))
	var prev: Vector2 = a
	var d := Vector2.from_angle(ang)
	var nv := d.orthogonal()
	var lim: float = L * k
	for i in range(1, n + 1):
		var x: float = L * float(i) / float(n)
		if x > lim + 0.01:
			x = lim
		var j: float = float(absi(hash(Vector2i(sd, i))) % 100 - 50) / 50.0 * 6.0
		var q: Vector2 = a + d * x + nv * j
		w.tb_line(_snap(prev), _snap(q), OLC, wd + 1.0)
		w.tb_line(_snap(prev), _snap(q), BLOOD[1], 1.0)
		prev = q
		if x >= lim:
			break


func _blade_ground(w, now: float) -> void:
	var cv = g.wcv
	gpuffs = _draw_puffs(cv, gpuffs, now)
	# 预警（通用画法已关：blade.gd 给这些预警挂 skin sami_blade，telegraph_draw.quiet 跳过）：裂缝 + 黑雾先渗出 + 刃尖先冒头，不画描边圈 / 半透明填充
	for t in g.warns:
		if t.done or str(t.get("skin", "")) != "sami_blade":
			continue
		var k: float = clampf(float(t.t) / maxf(0.01, float(t.dur)), 0.0, 1.0)
		var sd: int = absi(hash(Vector2i(int(t.pos.x), int(t.pos.y)))) % 9973
		match t.shape:
			"cone":
				# 斩击：扇区里 7 道裂缝从它脚下往外裂，外弧一排刃尖冒头（r130 的边就是这排刃尖）
				var r3: float = float(t.r)
				var a0: float = float(t.ang) - float(t.half)
				var a1: float = float(t.ang) + float(t.half)
				for i in 7:
					_crack(w, t.pos, lerpf(a0 + 0.08, a1 - 0.08, float(i) / 6.0), r3 - 8.0, k, sd + i * 17, 4.0)
				var n3: int = int((a1 - a0) * r3 / 12.0)
				for i in n3 + 1:
					var dl: float = float(absi(hash(Vector2i(sd, i + 300))) % 30) / 100.0
					_tip(w, t.pos + Vector2.from_angle(lerpf(a0, a1, float(i) / float(n3))) * r3, 18.0 * clampf((k - dl) / 0.5, 0.0, 1.0))
				if rng.randf() < 0.5 + k:
					var aa: float = rng.randf_range(a0, a1)
					_fog(t.pos + Vector2.from_angle(aa) * rng.randf_range(20.0, r3 * maxf(0.3, k)), 1, 0.7, 0.0, true, 0.8, Vector2.from_angle(aa) * 30.0)
			"line":
				var d := Vector2.from_angle(float(t.ang))
				var L: float = float(t.len)
				var hw: float = float(t.wid)
				if str(t.get("name", "")) == "黑毯" or (t.get("fx_carpet", false)):
					# 黑毯预警：雾先沿线渗出（窄、淡），铺到 k
					_band(cv, t.pos, t.pos + d * L * k, hw * 0.55, 0.55)
					continue
				# 投刃 / 追猎：中线一道裂缝往前裂到 k，两侧每 22 像素一道斜刻痕标出宽度，起点渗雾
				_crack(w, t.pos, float(t.ang), L, k, sd, 3.0)
				var nv := d.orthogonal()
				var x := 20.0
				while x < L * k:
					for sg in [-1.0, 1.0]:
						var q: Vector2 = t.pos + d * x + nv * hw * sg
						w.tb_line(_snap(q - d * 5.0 - nv * 3.0 * sg), _snap(q + d * 5.0), OLC, 3.0)
						w.tb_line(_snap(q - d * 3.0 - nv * 2.0 * sg), _snap(q + d * 3.0), BLOOD[1], 1.0)
					x += 22.0
				if rng.randf() < 0.4:
					_fog(t.pos + d * rng.randf_range(0.0, L * k), 1, 0.6, 0.0, true, 0.7)
			"circle":
				var r: float = float(t.r)
				var gy: float = g.combat.GROUND_Y
				if r <= 30.0:
					# 刃雨小圈：落点星形裂缝 + 一点渗雾（刃从天上落，见顶层）
					for i in 5:
						_crack(w, t.pos, TAU * float(i) / 5.0 + float(sd % 7), r, k, sd + i, 2.0)
					continue
				# 刃林圈（国度爆发 / 皇帝的猎杀）：圈边一圈刃尖冒头 + 圈里裂缝 + 黑雾渗出
				var nn: int = clampi(int(TAU * r / 16.0), 12, 40)
				for i in nn:
					var dl2: float = float(absi(hash(Vector2i(sd, i + 500))) % 35) / 100.0
					var aa2: float = TAU * float(i) / float(nn)
					_tip(w, t.pos + Vector2(cos(aa2) * r, sin(aa2) * r * gy), 11.0 * clampf((k - dl2) / 0.5, 0.0, 1.0))
				for i in 5:
					_crack(w, t.pos, TAU * float(i) / 5.0 + 0.3, r * 0.85, k, sd + i * 7)
				if rng.randf() < 0.4 + k * 0.6:
					var aa3: float = rng.randf() * TAU
					_fog(t.pos + Vector2(cos(aa3), sin(aa3) * gy) * rng.randf_range(0.0, r * 0.8), 1, 0.7, 0.0, true, 0.9)
	w.tb_flush()
	for id in blade_list.keys():
		var it: Array = blade_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			blade_list.erase(id)
			continue
		# 黑毯（铺开中；铺完由国度占位接手）：连续雾带（柔边贴图），毯头往前、往两侧翻卷雾团，偶尔崩出碎屑
		for c in e.get("cps", []):
			if float(c.front) <= 0.0 or c.get("k") != null:
				continue
			var dv: Vector2 = c.dir
			var nv2 := dv.orthogonal()
			var hw2: float = float(c.hw)
			var hd: Vector2 = c.a + dv * float(c.front)
			_band(cv, c.a, hd, hw2, 0.95)
			_band(cv, c.a + dv * 10.0, hd - dv * 6.0, hw2 * 0.55, 0.8)
			for sg in [-1.0, 1.0]:
				if rng.randf() < 0.55:
					_fog(hd - dv * rng.randf_range(0.0, 30.0) + nv2 * hw2 * 0.7 * sg, 1, 0.7, 0.0, true, 0.9, nv2 * sg * 45.0 + dv * 20.0)
			if rng.randf() < 0.7:
				_fog(hd + nv2 * rng.randf_range(-hw2, hw2) * 0.5, 1, 0.55, 0.0, true, 1.1, dv * 70.0)
			if rng.randf() < 0.15:
				embers(hd, 1, FOG[0], 140.0, 260.0, 0.4, 4.0)


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
				# 大刃片（不旋转，用户 11-25）：沿飞行方向的重刃贴地低飞（长 = 半宽 × 3），刃尖朝前，地上一道影子，身后犁出黑雾
				var dv: Vector2 = x.vel.normalized() if x.vel.length() > 1.0 else Vector2.from_angle(float(x.get("ang", 0.0)))
				var nv: Vector2 = dv.orthogonal()
				var R: float = float(x.r)
				var c: Vector2 = x.pos + Vector2(0, -10)
				var L: float = R * 1.6
				var Wb: float = R * 0.42
				w.tb_quad(_snap(x.pos - dv * L * 0.9 + nv * 4.0), _snap(x.pos + dv * L * 0.9 + nv * 4.0), _snap(x.pos + dv * L * 0.9 - nv * 4.0), _snap(x.pos - dv * L * 0.9 - nv * 4.0), Color(0.3, 0.3, 0.36, 0.5))
				var body := PackedVector2Array([c + dv * L, c + dv * L * 0.25 + nv * Wb, c - dv * L * 0.85 + nv * Wb * 0.7, c - dv * L, c - dv * L * 0.85 - nv * Wb * 0.5, c + dv * L * 0.25 - nv * Wb * 0.6])
				var big := PackedVector2Array()
				for q in body:
					big.append(c + (q - c) * 1.12)
				w.tb_poly(big, OLC)
				w.tb_poly(body, BK)
				w.tb_poly(PackedVector2Array([c + dv * L, c + dv * L * 0.25 + nv * Wb, c - dv * L * 0.85 + nv * Wb * 0.7, c - dv * L * 0.7 + nv * Wb * 0.35, c + dv * L * 0.2 + nv * Wb * 0.55]), BLOOD[2])
				w.tb_line(_snap(c - dv * L * 0.6 + nv * Wb * 0.2), _snap(c + dv * (L - 6.0)), Color(1.0, 0.95, 0.92), 2.0)
				if t >= hold:
					_fog(x.pos - dv * L, 1, 0.55, 0.0, true, 0.9, -x.vel * 0.15)
					if rng.randf() < 0.4:
						sparks(x.pos, x.vel.angle() + PI, 0.5, 1, 140.0, BLOOD)
		# 呼吸：它的国度往外胀时，边上一圈雾块往外涌（不画细环）
		if float(e.get("br_until", 0.0)) > now:
			var km = g.mech("kingdom")
			if km != null:
				var sw: float = (35.0 if e.type == "wanderer" else 20.0) * sin(PI * (1.0 - (float(e.br_until) - now) / 0.6))
				for k in km.list:
					if int(k.owner_id) == int(e.id) and k.kind == "boss":
						for j in 3:
							var aa: float = rng.randf() * TAU
							var q: Vector2 = k.pos + Vector2(cos(aa), sin(aa) * 0.8) * (float(k.r) + sw * 0.6)
							_fog(q, 1, 0.6, 0.0, true, 1.0, Vector2.from_angle(aa) * 45.0)
						if rng.randf() < 0.2:
							var ab: float = rng.randf() * TAU
							embers(k.pos + Vector2.from_angle(ab) * float(k.r), 1, FOG[0], 90.0, 200.0, 0.4, 4.0)
	# 刃林喷发（国度爆发 / 皇帝的猎杀）、刃雨
	var keep: Array = []
	for ev in bevents:
		var tf: float = ev[3]
		var age: float = now - tf
		var p: Vector2 = ev[1]
		if ev[0] == "flake":
			if age > 1.4:
				continue
			keep.append(ev)
			_draw_flake(w, p, age, float(ev[5]))
			continue
		if ev[0] == "whip":
			if age > 0.42:
				continue
			keep.append(ev)
			_draw_whip(w, ev, age)
			continue
		if ev[0] == "lash":
			if age > 0.5:
				continue
			keep.append(ev)
			_draw_lash(w, ev, age)
			continue
		if ev[0] == "dial":
			if age > float(ev[5]) + 0.12 * 20.0 + 0.5:
				continue
			keep.append(ev)
			_draw_dial(w, ev, age)
			continue
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



## 立着的刃（画布直接画，碎刃弹用）：底 base、高 h、宽 wd；lean 朝 d 前倾比例
func _stand_blade(cv, base: Vector2, h: float, wd: float, d: Vector2, lean: float) -> void:
	if h < 2.0:
		return
	var up := Vector2(0, -1).lerp(Vector2(d.x, d.y * 0.5).normalized(), lean).normalized()
	var n := up.orthogonal()
	var hw: float = wd * 0.5
	cv.draw_colored_polygon(PackedVector2Array([base - n * (hw + 4.0) + Vector2(0, 2), base + n * (hw + 4.0) + Vector2(0, 2), base + n * (hw + 2.0) + Vector2(0, -1), base - n * (hw + 2.0) + Vector2(0, -1)]), FOG[0])
	cv.draw_colored_polygon(PackedVector2Array([base - n * (hw + 2.0), base + up * h * 0.55 - n * (hw + 2.0), base + up * (h + 4.0), base + up * h * 0.55 + n * (hw + 2.0), base + n * (hw + 2.0)]), OLC)
	cv.draw_colored_polygon(PackedVector2Array([base - n * hw, base + up * h * 0.55 - n * hw, base + up * h, base + up * h * 0.55 + n * hw, base + n * hw]), BK)
	cv.draw_colored_polygon(PackedVector2Array([base + n * (hw - 2.5), base + up * h * 0.55 + n * (hw - 2.5), base + up * h, base + up * h * 0.55 + n * hw, base + n * hw]), BLOOD[2])
	cv.draw_line(base + up * 3.0, base + up * (h - 5.0), Color(1.0, 0.95, 0.92), 2.0)


## ---- 国度（用户 11-25：「用这个黑色烟雾来组成国度」；11-21 原话「黑烟间隔黑烟，中间浅灰，透明度低」）
## 方向一 黑烟间隔：边上一团团黑烟隔开排一圈（团与团之间有缝），中间浅灰雾，烟团慢慢呼吸、偶尔往外翻卷一团
## 方向二 连续烟墙：边上两排黑烟团交错叠成一道翻卷的烟墙，中间浅灰雾更浓
## 不画描边圈 / 平涂圆盘；苗圃（克雷松）仍用占位
func kingdom_draw(km) -> void:
	var cv = g.wcv
	var now: float = g.t
	var gy: float = g.combat.GROUND_Y
	for l in km.links:
		_band_tex(cv, grey_band, l[0].pos, l[1].pos, float(l[2]) * 0.9, 0.55)
	for k in km.list:
		if k.kind == "nursery":
			# 克雷松苗圃（原作淡紫带白闪）：几团淡紫雾 + 圈边淡紫雾团 + 一闪一闪的白点
			var rn: float = float(k.r)
			for i in 4:
				var an: float = float(i) * 2.399 + now * 0.2
				var qn: Vector2 = k.pos + Vector2(cos(an), sin(an) * gy) * rn * 0.35
				cv.draw_texture_rect(lil_puff[i % 3], Rect2(((qn - Vector2(rn, rn * 0.8) * 0.6) / PX).floor() * PX, Vector2(rn, rn * 0.8) * 1.2), false, Color(1, 1, 1, 0.55))
			var nn: int = maxi(6, int(TAU * rn / 30.0))
			for i in nn:
				var an2: float = TAU * float(i) / float(nn) + 0.1 * sin(now + float(i))
				var q3: Vector2 = k.pos + Vector2(cos(an2), sin(an2) * gy) * rn
				cv.draw_texture_rect(lil_puff[i % 3], Rect2(((q3 - Vector2(26, 21)) / PX).floor() * PX, Vector2(52, 42)), false, Color(1, 1, 1, 0.8))
			for i in 6:
				if int(now * 6.0 + float(i) * 3.7) % 5 == 0:
					var an3: float = float(i) * 1.9 + floorf(now * 1.2)
					var q4: Vector2 = _snap(k.pos + Vector2(cos(an3), sin(an3) * gy) * rn * 0.7)
					cv.draw_rect(Rect2(q4, Vector2(4, 4)), Color(1.0, 0.96, 1.0))
			continue
		if k.has("b"):
			_band(cv, k.pos, k.b, float(k.r), 0.85)
			continue
		var r: float = float(k.r)
		var sd: int = absi(hash(Vector2i(int(k.pos.x), int(k.pos.y)))) % 997
		# 中间浅灰：几团大浅灰雾，慢慢漂
		var ni: int = 4 if kdir == 1 else 6
		for i in ni:
			var aa: float = float(i) * 2.399 + float(sd)
			var rr: float = r * 0.42 * sqrt((float(i) + 0.5) / float(ni))
			var q: Vector2 = k.pos + Vector2(cos(aa + now * 0.15), sin(aa + now * 0.15) * gy) * rr
			var sz: float = r * (1.25 if kdir == 1 else 1.4)
			cv.draw_texture_rect(grey_puff[i % 3], Rect2(((q - Vector2(sz, sz * 0.8) * 0.5) / PX).floor() * PX, Vector2(sz, sz * 0.8)), false, Color(1, 1, 1, 0.65 if kdir == 1 else 0.7))
		# 边：黑烟团
		var circ: float = TAU * r
		var n: int = maxi(6, int(circ / (36.0 if kdir == 1 else 15.0)))
		var rows: int = 1 if kdir == 1 else 2
		for row in rows:
			for i in n:
				var ph: float = float(i) + float(row) * 0.5
				var aa2: float = TAU * ph / float(n) + 0.15 * sin(now * 0.6 + float(i + sd))
				var breath: float = 1.0 + 0.12 * sin(now * 1.3 + float(i) * 1.7 + float(sd))
				var rr2: float = r + (0.0 if row == 0 else -6.0) + 3.0 * sin(now * 0.9 + float(i))
				var q2: Vector2 = k.pos + Vector2(cos(aa2), sin(aa2) * gy) * rr2
				var sz2: float = (44.0 if kdir == 1 else 30.0 + 8.0 * float((i + row) % 2)) * breath
				var al2: float = 0.9 if kdir == 1 else (0.95 if (i + row) % 2 == 0 else 0.75)
				cv.draw_texture_rect(fog_puff[(i + row + sd) % 4], Rect2(((q2 - Vector2(sz2, sz2 * 0.8) * 0.5) / PX).floor() * PX, Vector2(sz2, sz2 * 0.8)), false, Color(1, 1, 1, al2))
		if rng.randf() < 0.05 * r / 70.0:
			var a3: float = rng.randf() * TAU
			_fog(k.pos + Vector2(cos(a3), sin(a3) * gy) * r, 1, 0.9, 0.0, true, 0.8, Vector2(cos(a3), sin(a3) * gy) * 25.0 + Vector2(0, -8))
		# 裂纹：从中心往外的亮裂缝，长度按裂纹进度
		if float(k.crack) > 0.0:
			for i in 4:
				_crack_cv(cv, k.pos, TAU * float(i) / 4.0 + float(sd % 5), r * minf(1.0, float(k.crack)), sd + i)
		for pid in k.props:
			var e = g.enemies_sys.by_id(int(pid))
			if e != null and not e.dead:
				cv.draw_line(k.pos, e.pos, Color(0.6, 0.8, 1.0, 0.35), 1.5)
	for c in km.cuts:
		_band_tex(cv, grey_band, c.a, c.b, float(c.w), 0.5 * clampf((float(c.until) - g.t) / 0.5, 0.0, 1.0))


func _band_tex(cv, tx: Texture2D, a: Vector2, b: Vector2, hw: float, al: float) -> void:
	var L: float = a.distance_to(b)
	if L < 2.0:
		return
	cv.draw_set_transform(a, (b - a).angle(), Vector2.ONE)
	var H: float = hw * 2.6
	var x := 0.0
	while x < L:
		var ln: float = minf(256.0, L - x)
		cv.draw_texture_rect_region(tx, Rect2(x, -H * 0.5, ln, H), Rect2(0, 0, 128.0 * ln / 256.0, 32), Color(1, 1, 1, al))
		x += 256.0
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _crack_cv(cv, a: Vector2, ang: float, L: float, sd: int) -> void:
	var n: int = maxi(2, int(L / 14.0))
	var prev: Vector2 = a
	var d := Vector2.from_angle(ang)
	var nv := d.orthogonal()
	for i in range(1, n + 1):
		var j: float = float(absi(hash(Vector2i(sd, i))) % 100 - 50) / 50.0 * 6.0
		var q: Vector2 = a + d * (L * float(i) / float(n)) + nv * j
		cv.draw_line(prev, q, OLC, 4.0)
		cv.draw_line(prev, q, Color(1.0, 0.92, 0.75), 2.0)
		prev = q



## ==== 结局 Boss 招牌招（用户 11-25 定方向，docs/401 §14）

## 意志【风雪环】：弹排好的 0.9 秒里，脚下一枚雪花印六臂长出（冰晶菱块 + 侧枝，冰白 + 暗紫边），到点迸散成冰屑
func _draw_flake(w, c: Vector2, age: float, hold: float) -> void:
	var grow: float = clampf(age / (hold * 0.6), 0.0, 1.0)
	grow = 1.0 - (1.0 - grow) * (1.0 - grow)
	var fade: float = clampf((1.4 - age) / 0.45, 0.0, 1.0)
	if age >= hold and age - 1.0 / 30.0 < hold:
		for k in 6:
			sparks(c + Vector2.from_angle(TAU * k / 6.0) * 60.0, TAU * k / 6.0, 0.5, 4, 220.0, [WILLC[3], WILLC[2], WILLC[1], WILLC[0]], true, 0.35)
	var L: float = 140.0 * grow   # 臂要伸出意志本体（本体约 70 宽）才看得见
	for k in 6:
		var a: float = TAU * float(k) / 6.0 + PI / 6.0
		var d := Vector2(cos(a), sin(a) * 0.62)
		var nv := Vector2(-d.y, d.x).normalized()
		var x := 10.0
		var i := 0
		while x < L:
			var q: Vector2 = c + d * x
			var s: float = (7.0 - x / 22.0) * fade
			if s > 1.0:
				var dia := PackedVector2Array([q + d * (s + 2.0), q + nv * (s * 0.6 + 2.0), q - d * (s + 2.0), q - nv * (s * 0.6 + 2.0)])
				w.tb_poly(dia, WILLC[0])
				w.tb_poly(PackedVector2Array([q + d * s, q + nv * s * 0.6, q - d * s, q - nv * s * 0.6]), WILLC[2])
				w.tb_poly(PackedVector2Array([q + d * s, q + nv * s * 0.6, q]), WILLC[3])
				if i % 2 == 1 and x > 24.0:
					for sg in [-1.0, 1.0]:
						var br: Vector2 = (d * 0.5 + nv * sg * 0.85).normalized()
						var bl: float = 14.0 * fade * grow
						w.tb_line(_snap(q), _snap(q + br * bl), WILLC[0], 4.0)
						w.tb_line(_snap(q), _snap(q + br * bl), WILLC[2], 2.0)
			x += 14.0
			i += 1


## 哈兰【鞭扫 / 鞭影】：鞭从手里甩出扫过扇形（0.16 秒），鞭身各段按离手远近滞后 → 弯出挥鞭弧；身后留两道变暗的残影，
## 扫到头鞭梢炸响（火星 + 沙尘），再往回收；粗 7 → 2 像素，暗红 + 亮脊 + 暗描边
func _whip_pts(hand: Vector2, a0: float, a1: float, age: float, L: float) -> PackedVector2Array:
	var pts := PackedVector2Array([hand])
	var n := 16
	var q: Vector2 = hand
	for i in range(1, n + 1):
		var tt: float = age - float(i) * 0.011
		var u: float = clampf(tt / 0.16, 0.0, 1.0)
		u = 1.0 - pow(1.0 - u, 2.2)
		var over: float = 0.18 * sin(clampf((tt - 0.16) / 0.2, 0.0, 1.0) * PI) if tt > 0.16 else 0.0
		var a: float = lerpf(a0, a1, u) + over * signf(a1 - a0)
		q += Vector2(cos(a), sin(a) * 0.8) * (L / float(n))
		pts.append(q)
	return pts


func _draw_whip_line(w, pts: PackedVector2Array, k: float, cols: Array) -> void:
	var n: int = pts.size() - 1
	for i in n:
		var f: float = float(i) / float(n)
		var wd: float = lerpf(10.0, 3.0, f) * k
		if wd < 1.0:
			continue
		w.tb_line(_snap(pts[i]), _snap(pts[i + 1]), cols[0], wd + 2.0)
	for i in n:
		var f2: float = float(i) / float(n)
		var wd2: float = lerpf(10.0, 3.0, f2) * k
		if wd2 < 1.0:
			continue
		w.tb_line(_snap(pts[i]), _snap(pts[i + 1]), cols[1], wd2)
		if wd2 >= 3.0:
			w.tb_line(_snap(pts[i] + Vector2(0, -1)), _snap(pts[i + 1] + Vector2(0, -1)), cols[2], 1.0)


func _draw_whip(w, ev: Array, age: float) -> void:
	var c: Vector2 = ev[1]
	var ca: float = ev[2]
	var half: float = ev[5]
	var hand: Vector2 = c + Vector2(0, -26)
	var L := 150.0
	var a0: float = ca - half - 0.25
	var a1: float = ca + half + 0.1
	var fade: float = clampf((0.42 - age) / 0.18, 0.0, 1.0)
	for gh in [2, 1]:
		var ta: float = age - 0.035 * float(gh)
		if ta > 0.0:
			_draw_whip_line(w, _whip_pts(hand, a0, a1, ta, L), (0.55 - 0.15 * float(gh)) * fade, [KHAN[0], KHAN[1], KHAN[1]])
	var pts := _whip_pts(hand, a0, a1, age, L)
	_draw_whip_line(w, pts, fade, [OLC, KHAN[2], KHAN[3]])
	if not ev[4] and age >= 0.16:
		ev[4] = true
		var tip: Vector2 = pts[pts.size() - 1]
		sparks(tip, ca + half, 0.9, 10, 320.0, [Color(1.0, 0.95, 0.9), KHAN[3], KHAN[2], KHAN[1]], true, 0.3)
		embers(tip + Vector2(0, 20), 6, Color(0.55, 0.42, 0.28), 120.0, 260.0, 0.5, 4.0)
		for i in 5:
			_fog(c + Vector2.from_angle(lerpf(a0, a1, float(i) / 4.0)) * 100.0 + Vector2(0, 18), 1, 0.6, 0.0, true, 0.7)


## 哈兰【鞭链】：鞭沿直线抽出去（0.18 秒），鞭身有往前推的波，抽到头鞭梢炸响，再收回
func _draw_lash(w, ev: Array, age: float) -> void:
	var c: Vector2 = ev[1]
	var d := Vector2.from_angle(float(ev[2]))
	var nv := d.orthogonal()
	var L: float = ev[5]
	var ext: float = clampf(age / 0.18, 0.0, 1.0)
	ext = 1.0 - pow(1.0 - ext, 2.0)
	if age > 0.3:
		ext *= clampf(1.0 - (age - 0.3) / 0.2, 0.0, 1.0)
	var hand: Vector2 = c + Vector2(0, -26)
	var n := 22
	var pts := PackedVector2Array()
	for i in n + 1:
		var f: float = float(i) / float(n)
		var amp: float = 14.0 * f * (1.0 - ext * 0.8)
		pts.append(hand + d * L * ext * f + nv * sin(f * 9.0 - age * 40.0) * amp)
	_draw_whip_line(w, pts, 1.0, [OLC, KHAN[2], KHAN[3]])
	if not ev[4] and age >= 0.18:
		ev[4] = true
		var tip: Vector2 = c + d * L
		sparks(tip, 0.0, PI, 14, 300.0, [Color(1.0, 0.95, 0.9), KHAN[3], KHAN[2], KHAN[1]], true, 0.32)
		embers(tip, 8, Color(0.55, 0.42, 0.28), 140.0, 260.0, 0.5, 4.0)
		_fog(tip + Vector2(0, 6), 3, 0.7, 0.0, true, 0.9)


## 路加【日晷】：地上 20 道金黄刻度依次长出（每 5 道一道长的），中间一根晷针投下暗影、按刻度顺时针扫；
## 扫到哪道刻度，那道刻度闪金橙、弹从那里射出（弹本身走 mid_cards，弹环金黄 64°）
func _draw_dial(w, ev: Array, age: float) -> void:
	var c: Vector2 = ev[1]
	var R: float = ev[2]
	var delay: float = ev[5]
	var gy := 0.62
	var fade: float = clampf((delay + 0.12 * 20.0 + 0.5 - age) / 0.4, 0.0, 1.0)
	var cur: int = int(floor((age - delay) / 0.12)) if age >= delay else -1
	for i in 20:
		var a: float = TAU * float(i) / 20.0 - PI * 0.5
		var d := Vector2(cos(a), sin(a) * gy)
		var grow: float = clampf((age - float(i) * 0.02) / 0.25, 0.0, 1.0) * fade
		if grow <= 0.0:
			continue
		var long: bool = i % 5 == 0
		var ln: float = (32.0 if long else 20.0) * grow
		var wd: float = 9.0 if long else 6.0
		var q0: Vector2 = c + d * (R - ln * 0.5)
		var q1: Vector2 = c + d * (R + ln * 0.5)
		var lit: bool = i <= cur and cur - i < 3
		w.tb_line(_snap(q0), _snap(q1), LUKA_D, wd + 2.0)
		w.tb_line(_snap(q0), _snap(q1), LUKA_O if lit else LUKA, wd)
		if lit and cur == i:
			w.tb_line(_snap(q0), _snap(q1), Color(1.0, 1.0, 0.9), maxf(2.0, wd - 3.0))
		if i == cur and int(ev[6]) != i:
			ev[6] = i
			sparks(c + d * R, a, 0.8, 6, 200.0, [Color(1.0, 1.0, 0.9), LUKA, LUKA_O, LUKA_D], true, 0.28)
	# 晷针影：暗褐三角，从圆心指向当前刻度（出弹前指向第 0 道、慢慢立起）
	var ga: float = TAU * float(maxi(cur, 0)) / 20.0 - PI * 0.5
	if cur >= 0:
		ga += TAU / 20.0 * clampf((age - delay - 0.12 * float(cur)) / 0.12, 0.0, 1.0)
	var gl: float = R * 0.85 * clampf(age / 0.5, 0.0, 1.0) * fade
	if gl > 2.0:
		var gd := Vector2(cos(ga), sin(ga) * gy)
		var gn := Vector2(-gd.y, gd.x).normalized()
		w.tb_poly(PackedVector2Array([c + gn * 7.0, c + gd * gl, c - gn * 7.0]), Color(0.18, 0.12, 0.05, 0.85))
		w.tb_poly(PackedVector2Array([c + gn * 4.0, c + gd * gl * 0.92, c]), LUKA_D)
	# 晷心：金橙小柱
	w.tb_poly(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(0, -22) * fade, c + Vector2(5, 0)]), LUKA_D)
	w.tb_poly(PackedVector2Array([c + Vector2(-3, 0), c + Vector2(0, -19) * fade, c + Vector2(1, 0)]), LUKA_O)


## 木裂【泯灭冲 / 自我泯灭】：冲刺时身上一片片墨绿（深青）甲片往后剥落、翻转飘走，脚下犁出一道深青雾痕；自我泯灭期间身上不停掉片
func lead_draw(e: Dictionary) -> void:
	var now: float = g.t
	var pp: Vector2 = e.get("fx_pp", e.pos)
	var tp: float = float(e.get("fx_pt", now))
	e["fx_pp"] = e.pos
	e["fx_pt"] = now
	var dt: float = now - tp
	if dt <= 0.0 or dt > 0.2:
		return
	var v: Vector2 = (e.pos - pp) / dt
	var dash: bool = v.length() > 260.0
	if dash:
		if trails.size() > 40:
			trails.pop_front()
		trails.append([pp, e.pos, now])
		for i in 3:
			_flake(e.pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-48, -8)), -v * rng.randf_range(0.15, 0.35) + Vector2(rng.randf_range(-40, 40), -rng.randf_range(20, 60)))
	elif float(e.get("annihil_t", 0.0)) > now and rng.randf() < 0.45:
		_flake(e.pos + Vector2(rng.randf_range(-16, 16), rng.randf_range(-52, -10)), Vector2(rng.randf_range(-50, 50), -rng.randf_range(30, 70)))


func _flake(p: Vector2, v: Vector2) -> void:
	if flakes.size() > 120:
		flakes.pop_front()
	flakes.append([p, v, g.t, rng.randf_range(0.6, 1.0), rng.randf_range(4.0, 7.0), rng.randf_range(-9.0, 9.0), rng.randi() % 3])


## 克雷松【稳定场】（方向 B 锚桩光柱）：稳定设施 = 暗石板锚桩 + 淡紫晶尖；充能时一根光柱从桩上长高；
## 场开着时圈边 6 根锚桩各立一根光柱，柱间升起淡紫光尘帘（不画细环）
var cres_list := {}


func cresson_draw(e: Dictionary) -> void:
	cres_list[int(e.id)] = [e, g.t]


func _pillar(cv, base: Vector2, h: float, wd: float, al: float) -> void:
	if h < 2.0 or al <= 0.0:
		return
	var hw: float = wd * 0.5
	var top: Vector2 = base + Vector2(0, -h)
	cv.draw_polygon(PackedVector2Array([base + Vector2(-hw - 4, 0), base + Vector2(hw + 4, 0), top + Vector2(hw + 2, 0), top + Vector2(-hw - 2, 0)]),
		PackedColorArray([Color(LIL[1], 0.55 * al), Color(LIL[1], 0.55 * al), Color(LIL[1], 0.0), Color(LIL[1], 0.0)]))
	cv.draw_polygon(PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(hw, 0), top + Vector2(hw * 0.6, 0), top + Vector2(-hw * 0.6, 0)]),
		PackedColorArray([Color(LIL[3], 0.95 * al), Color(LIL[3], 0.95 * al), Color(LIL[3], 0.0), Color(LIL[3], 0.0)]))
	cv.draw_polygon(PackedVector2Array([base + Vector2(-1.5, 0), base + Vector2(1.5, 0), top + Vector2(1, h * 0.25), top + Vector2(-1, h * 0.25)]),
		PackedColorArray([Color(LIL[4], al), Color(LIL[4], al), Color(LIL[4], 0.0), Color(LIL[4], 0.0)]))


func _anchor(w, p: Vector2, lit: float) -> void:
	w.tb_poly(PackedVector2Array([p + Vector2(-9, 2), p + Vector2(-6, -22), p + Vector2(6, -22), p + Vector2(9, 2)]), OLC)
	w.tb_poly(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(-5, -20), p + Vector2(5, -20), p + Vector2(7, 0)]), Color(0.18, 0.22, 0.3))
	w.tb_poly(PackedVector2Array([p + Vector2(-5, 0), p + Vector2(-4, -20), p + Vector2(-1, -20), p + Vector2(-2, 0)]), Color(0.35, 0.42, 0.54))
	var cc: Color = LIL[3].lerp(LIL[1], 1.0 - lit)
	w.tb_poly(PackedVector2Array([p + Vector2(-5, -20), p + Vector2(0, -34), p + Vector2(5, -20)]), OLC)
	w.tb_poly(PackedVector2Array([p + Vector2(-3, -21), p + Vector2(0, -31), p + Vector2(3, -21)]), cc)


func _final_ground(w, now: float) -> void:
	var cv = g.wcv
	var keep: Array = []
	for tr in trails:
		var age: float = now - float(tr[2])
		if age > 0.9:
			continue
		keep.append(tr)
		_band_tex(cv, teal_band, tr[0], tr[1], 16.0, 0.9 * (1.0 - age / 0.9))
	trails = keep


func _final_front(w, cv, now: float) -> void:
	# 意志【冰凌】坠冰：冰凌列的每个落点预警后段，一根冰凌从天上落下（冰白 + 暗紫边），落地碎开
	for t in g.warns:
		if str(t.get("skin", "")) != "ice_lance" or not (t.get("owner") is Dictionary) or str(t.owner.get("type", "")) != "will":
			continue
		var k: float = clampf(float(t.t) / maxf(0.01, float(t.dur)), 0.0, 1.0)
		var p: Vector2 = t.pos
		if t.done:
			if not t.get("fx_hit", false):
				t["fx_hit"] = true
				sparks(p + Vector2(0, -6), -PI * 0.5, 1.4, 10, 260.0, [WILLC[3], WILLC[2], WILLC[1], WILLC[0]], true, 0.32)
				embers(p, 6, WILLC[2], 130.0, 300.0, 0.5, 4.0)
				for j in 3:
					_icefog(p + Vector2(rng.randf_range(-10, 10), 0), Vector2(rng.randf_range(-40, 40), rng.randf_range(-10, 10)), 0.8, 22.0, 0.8)
			continue
		if k < 0.62:
			continue
		var f: float = (k - 0.62) / 0.38
		var y: float = -200.0 * (1.0 - f * f)
		var tip: Vector2 = p + Vector2(0, y)
		w.tb_poly(PackedVector2Array([tip + Vector2(0, 4), tip + Vector2(-14, -36), tip + Vector2(0, -92), tip + Vector2(14, -36)]), WILLC[0])
		w.tb_poly(PackedVector2Array([tip, tip + Vector2(-11, -36), tip + Vector2(0, -87), tip + Vector2(11, -36)]), WILLC[1])
		w.tb_poly(PackedVector2Array([tip, tip + Vector2(0, -87), tip + Vector2(11, -36)]), WILLC[2])
		w.tb_line(_snap(tip + Vector2(2, -12)), _snap(tip + Vector2(2, -70)), WILLC[3], 3.0)
		var sh: float = 6.0 + 10.0 * f
		w.tb_quad(_snap(p + Vector2(-sh, -1)), _snap(p + Vector2(sh, -1)), _snap(p + Vector2(sh * 0.7, 2)), _snap(p + Vector2(-sh * 0.7, 2)), Color(0.3, 0.32, 0.42, 0.55))
	# 木裂剥落片：翻转的深青甲片（暗描边），往后飘、慢慢落
	var keep: Array = []
	for fl in flakes:
		var age: float = now - float(fl[2])
		if age >= float(fl[3]):
			continue
		keep.append(fl)
		var u: float = age / float(fl[3])
		var pos: Vector2 = fl[0] + fl[1] * age * (1.0 - 0.5 * u) + Vector2(0, 60.0 * age * age)
		var s: float = float(fl[4]) * (1.0 - u * 0.5)
		var an: float = float(fl[5]) * age
		var sq: float = absf(cos(an * 1.7))   # 翻面：宽度随转角缩放
		var a := Vector2(cos(an), sin(an)) * s
		var b := Vector2(-sin(an), cos(an)) * s * maxf(0.25, sq)
		var pts := PackedVector2Array([pos + a, pos + b, pos - a * 0.7, pos - b])
		var big := PackedVector2Array()
		for q in pts:
			big.append(pos + (q - pos) * 1.35)
		w.tb_poly(big, OLC)
		w.tb_poly(pts, TEALC[2 + int(fl[6]) % 3] if sq > 0.5 else TEALC[1])
	flakes = keep
	w.tb_flush()
	# 克雷松锚桩 / 光柱 / 光尘帘
	for id in cres_list.keys():
		var it: Array = cres_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			cres_list.erase(id)
			continue
		for d in e.get("devs", []):
			var ready: bool = now >= float(d.cd)
			var on: bool = float(d.field) > now
			_anchor(w, d.pos, 1.0 if (ready or on) else 0.0)
			if float(d.charge) > 0.0:
				var ck: float = clampf(1.0 - (float(d.charge) - now), 0.0, 1.0)
				_pillar(cv, d.pos + Vector2(0, -30), 200.0 * ck, 20.0, 0.6 + 0.4 * ck)
			if on:
				var left: float = float(d.field) - now
				var al: float = clampf(left / 0.5, 0.0, 1.0)
				_pillar(cv, d.pos + Vector2(0, -30), 190.0, 18.0, al * (0.85 + 0.15 * sin(now * 9.0)))
				for k in 6:
					var aa: float = TAU * float(k) / 6.0 + 0.3
					var ap: Vector2 = d.pos + Vector2(cos(aa), sin(aa) * 0.62) * 170.0
					_anchor(w, ap, 1.0)
					_pillar(cv, ap + Vector2(0, -30), 120.0 + 12.0 * sin(now * 5.0 + float(k)), 14.0, al * 0.9)
					if rng.randf() < 0.3 * al:
						_fog(ap, 1, 0.6, 0.0, true, 0.6, Vector2(0, -10))
					if rng.randf() < 0.5 * al:
						var bb: float = aa + TAU / 6.0 * rng.randf()
						var mp: Vector2 = d.pos + Vector2(cos(bb), sin(bb) * 0.62) * 170.0
						_add(mp + Vector2(0, -rng.randf_range(0.0, 10.0)), Vector2(rng.randf_range(-6, 6), -rng.randf_range(40, 80)), 0.7, LIL[3] if rng.randf() < 0.6 else LIL[4], 2.0, 0)
		w.tb_flush()
