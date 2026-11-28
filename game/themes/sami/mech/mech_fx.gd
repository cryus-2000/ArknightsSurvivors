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
const D = preload("res://scripts/data.gd")
const FX_DIR := "res://themes/sami/fx/"
const PX := 2.0
const P_MAX := 420           # 同屏颗粒上限（网页预算，docs/401 §5）
const S_MAX := 48            # 同屏帧条上限

# 原作色
# 浅色雪地（昧明冻土）上颗粒取原作曲线里的中深段：白 / 淡色会混进雪里（docs/401 §9）
const STEEL := [Color(0.02, 0.024, 0.03), Color(0.06, 0.08, 0.1), Color(0.2, 0.25, 0.31), Color(0.34, 0.4, 0.48)]
const ICE := [Color(0.0, 0.05, 0.16), Color(0.0, 0.14, 0.43), Color(0.12, 0.36, 0.7), Color(0.32, 0.58, 0.83)]
const FROST := [Color(0.0, 0.13, 0.42), Color(0.0, 0.2, 0.55), Color(0.0, 0.38, 0.8), Color(0.1, 0.55, 0.95)]
const ICEL := [Color(0.97, 0.99, 1.0), Color(0.78, 0.93, 1.0), Color(0.58, 0.82, 0.96), Color(0.35, 0.6, 0.85)]   # 冰爆火花：白 → 浅青 → 一点蓝（用户 11-25：别读成蓝色碎块）
const BLOOD := [Color(0.04, 0.0, 0.0), Color(0.62, 0.0, 0.0), Color(1.0, 0.17, 0.11), Color(1.0, 0.58, 0.26)]

var g: Game
var bul = preload("res://themes/sami/mech/sami_bul.gd").new()   # 萨米 Boss 弹体贴图（样板 v3，docs/401 §19）
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
var bscars: Array = []       # 地上斩痕 [起点, 终点, 出生 t, 宽, 种子]
# 黑雾：程序噪声烤出的柔边雾贴图（alpha 分 5 级台阶保持像素感，1 纹素 = 2 世界像素），不用实心方块
var fog_puff: Array = []     # 4 张 32×32 径向雾团
var fog_band: Texture2D      # 128×32 横向可平铺的雾带（上下边柔）
var puffs: Array = []        # 顶层雾团 [p0, v, 出生 t, 寿命, 尺寸 0, 尺寸 1, 图号, 不透明度]
var gpuffs: Array = []       # 地面雾团（黑毯 / 呼吸 / 预警渗雾，压在单位之下）
const PUFF_MAX := 160
var ice_puff: Array = []     # 冰雾团（冰爆 B）
var grey_puff: Array = []    # 国度中间的浅灰雾
var grey_band: Texture2D
var kdir := 0               # 国度画法：0 = 场地 A 按格铺（11-26 定）；1 / 2 = 旧黑烟圈样张
# 国度 = 场地（攻速减半、本身不伤人）→ 低亮度、低对比的常驻地面纹理，压在弹幕 / 预警下面，不能比白芯弹抢眼
const KD_EDGE := 0.34        # 边上黑烟团不透明度（原 0.9）
const KD_IN := 0.26          # 中间浅灰不透明度（原 0.65）
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
var lil_band: Texture2D
var sand_floor := false      # 演示夹具开：结局四 Boss 场地「时光之沙」地图还没做，临时铺程序沙地
var sand_tex: Texture2D
const GOUGE := [Color(0.1, 0.13, 0.2), Color(0.26, 0.32, 0.42), Color(0.93, 0.96, 1.0)]   # 爪痕：深槽 / 槽壁 / 翻起的雪唇
const OWN := {"caster": "needle", "blade": "blade", "wanderer": "blade", "khan": "kbul", "lion": "lbul", "will": "wbul", "lead": "tbul", "cresson": "pbul"}


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
		ice_puff.append(_fog_tex(32, 32, 1301 + i, true, Color(0.78, 0.92, 0.98), Color(1.0, 1.0, 1.0)))   # 浓处白、稀处浅青   # 亮雪地上要读得出：浓处纯白（比雪亮）、稀处冰蓝
		grey_puff.append(_fog_tex(32, 32, 1401 + i, true, Color(0.5, 0.5, 0.54), Color(0.7, 0.7, 0.74)))
	teal_band = _fog_tex(128, 32, 1601, false, Color(0.04, 0.29, 0.21), Color(0.0, 0.06, 0.04))
	for i in 3:
		lil_puff.append(_fog_tex(32, 32, 1701 + i, true, Color(0.54, 0.28, 0.8), Color(0.85, 0.7, 1.0)))
	grey_band = _fog_tex(128, 32, 1501, false, Color(0.5, 0.5, 0.54), Color(0.68, 0.68, 0.72))
	lil_band = _fog_tex(128, 32, 1801, false, Color(0.54, 0.28, 0.8), Color(0.78, 0.6, 1.0))
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
	sparks(pos + Vector2(0, -6), 0.0, PI, 12, 240.0, ICEL, true, 0.3)


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
	w.tb_poly(big, Color(0.14, 0.24, 0.4, al))                       # 暗边：深蓝灰（不用纯黑）
	w.tb_poly(pts, Color(0.62, 0.86, 0.97, al))                     # 本体：浅青
	w.tb_poly(PackedVector2Array([c, pts[2], pts[3]]), Color(0.3, 0.55, 0.85, al))   # 暗面：只留一小块深一点的蓝
	top.append(c + (pts[0] - c) * 0.9)
	top.append(c + (pts[1] - c) * 0.9)
	top.append(c + (pts[2] - c) * 0.5)
	top.append(c)
	w.tb_poly(top, Color(0.97, 0.99, 1.0, al))
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
			var cc: Color = [Color(0.97, 0.99, 1.0), Color(0.75, 0.9, 0.98), Color(0.6, 0.82, 0.95)][int(f[2])]
			var sz: float = 4.0 if int(f[2]) == 0 else 2.0
			if int(f[2]) == 0:
				w.tb_quad(pp + Vector2(0, 2), pp + Vector2(sz, 2), pp + Vector2(sz, 4), pp + Vector2(0, 4), Color(0.55, 0.72, 0.88))   # 白霜下沿一道冰蓝影，亮雪地上读得出
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
			w.tb_poly(pts, Color(0.72, 0.93, 1.0) if u > 0.6 else Color(0.97, 0.99, 1.0))
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
					w.tb_quad(pp, pp + Vector2(2, 0), pp + Vector2(2, 2), pp + Vector2(0, 2), Color(0.97, 0.99, 1.0) if int(c[5] * 10.0) % 2 == 0 else Color(0.75, 0.92, 1.0))
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
	if sand_floor:
		_draw_sand_floor(w)
	_draw_ice_ground(w, g.t)
	_final_ground(w, g.t)
	_fin_ground(w, g.wcv, g.t)
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
	bul.tick()
	_own_bullets(cv, now)
	puffs = _draw_puffs(cv, puffs, now)
	_blade_front(w, now)
	_draw_ice_front(w, now)
	_final_front(w, cv, now)
	_fin_front(w, cv, now)
	_obj_front(w, now)
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
		if b.get("mc", false) and bul.has_type(st):
			_sami_bullet(cv, b, st)
			continue
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
		if kind == "wbul" or kind == "tbul" or kind == "pbul":
			_fin_bullet(cv, b, kind, now)
			continue
		if kind == "kbul":
			# 哈兰弹（协调人 11-25：按水月最终 Boss 同档放大）：白芯 + 暗红环 + 暗边，半径 11（判定不变），身后暗红锥尾
			var R := 14.0
			cv.draw_polygon(PackedVector2Array([bp + nrm * R * 0.8, bp - d * 44.0, bp - nrm * R * 0.8]),
				PackedColorArray([Color(KHAN[2], 0.8), Color(KHAN[1], 0.0), Color(KHAN[2], 0.8)]))
			cv.draw_circle(bp, R + 3.5, Color(0.1, 0.01, 0.01))
			cv.draw_circle(bp, R, KHAN[2])
			cv.draw_circle(bp, R * 0.78, KHAN[3])
			cv.draw_circle(bp, R * 0.5, Color(1.0, 0.96, 0.92))
			continue
		if kind == "lbul":
			# 路加弹（协调人 11-25：别是一圈小点）：同哈兰弹档，白芯 + 金黄 64° 环 + 深褐暗边 + 金黄锥尾，可见半径 12（判定不变）
			var RL := 12.0
			cv.draw_polygon(PackedVector2Array([bp + nrm * RL * 0.8, bp - d * 38.0, bp - nrm * RL * 0.8]),
				PackedColorArray([Color(LUKA, 0.75), Color(LUKA_O, 0.0), Color(LUKA, 0.75)]))
			cv.draw_circle(bp, RL + 3.0, LUKA_D)
			cv.draw_circle(bp, RL, LUKA_O)
			cv.draw_circle(bp, RL * 0.8, LUKA)
			cv.draw_circle(bp, RL * 0.48, Color(1.0, 1.0, 0.94))
			continue
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
			_stand_blade(cv, base, maxf(r0 * 3.4, 32.0) * up, maxf(r0 * 1.2, 13.0), d, 0.25)
			if now - float(b.get("sfx_tt", -9.0)) > 0.05:
				b["sfx_tt"] = now
				_fog(base - d * 10.0, 1, 0.45, 0.0, true, 0.55, -v * 0.15)
				if rng.randf() < 0.5:
					_add(base, -v * 0.2 + nrm * rng.randf_range(-30, 30), 0.25, BLOOD[rng.randi_range(2, 3)], 2.0, 2)



## 萨米 Boss 弹（用户 11-26 通过样板 v3）：白芯 + 原作意象形状 + 霜气贴图，按飞行方向取 16 向之一；
## 尺寸：主力 24 / 米弹叶形 24×13 / 月牙 22；成片铺满的招（b.sfx_small，sami_boss.shot 的 small）和 tier 0 用 19；显形期（hold）淡入 + 由小变大
func _sami_bullet(cv, b: Dictionary, st: String) -> void:
	if not b.get("sfx_seen", false):
		b["sfx_seen"] = true
		b["own_draw"] = true
		b["sfx_own"] = true
		bul.warm(st)
	var v: Vector2 = b.vel
	if v.length_squared() < 1.0:
		v = b.get("v0", Vector2.RIGHT)
	var a: float = v.angle()
	var crescent: bool = st == "blade" or st == "wanderer"
	var sz: int = 22 if crescent else (19 if (b.get("sfx_small", false) or int(b.get("tier", 1)) == 0) else 24)
	var tx: ImageTexture = bul.tex(st, sz, a)
	var k: float = 1.0
	var al: float = 1.0
	var hold: float = float(b.get("hold", 0.0))
	if hold > 0.0 and float(b.get("age", 0.0)) < hold:
		var u: float = clampf(float(b.age) / hold, 0.0, 1.0)
		k = 0.6 + 0.4 * u
		al = 0.35 + 0.65 * u
	var sz2: Vector2 = Vector2(tx.get_width(), tx.get_height()) * PX * k
	var bp: Vector2 = b.pos + Vector2(0, -16)
	cv.draw_texture_rect(tx, Rect2(_snap(bp - sz2 * 0.5), sz2), false, Color(1, 1, 1, al))


## 月牙片：前凸后凹，d 朝前、nrm 朝凸面
func _crescent(c: Vector2, d: Vector2, nrm: Vector2, L: float, W: float) -> PackedVector2Array:
	return PackedVector2Array([c + d * L, c + nrm * W * 0.7 + d * L * 0.45, c + nrm * W, c + nrm * W * 0.6 - d * L * 0.6, c - d * L,
		c + nrm * W * 0.15 - d * L * 0.3, c + nrm * W * 0.25 + d * L * 0.2])


## ---- 邪魔的利刃 / 游荡者
func blade_draw(e: Dictionary) -> void:
	blade_list[int(e.id)] = [e, g.t]
	# 沉进国度 / 钻出（§11.2 C、雾行、国度猎斩）：e.sfx_sink 0–1 给 world.gd 画本体时往下沉、变淡（纯画面）；
	# 沉下 0.3 秒、钻出 0.15 秒；沉下去翻起黑雾，钻出时黑雾往上冲 + 深红火花 + 碎屑
	var now: float = g.t
	if float(e.get("sunk_until", 0.0)) > now:
		if float(e.get("fx_sk0", -1.0)) < 0.0:
			e["fx_sk0"] = now
			_fog(e.pos, 6, 0.7, 0.0, true, 1.0)
		e["sfx_sink"] = clampf((now - float(e.fx_sk0)) / 0.3, 0.0, 1.0)
	else:
		if float(e.get("fx_sk0", -1.0)) >= 0.0:
			e["fx_sk0"] = -1.0
			e["fx_up0"] = now
			_fog(e.pos, 7, 0.6, 0.0, false, 1.1, Vector2(0, -50))
			sparks(e.pos + Vector2(0, -20), -PI * 0.5, 0.9, 12, 340.0, BLOOD, true, 0.35)
			embers(e.pos, 7, FOG[2], 150.0, 320.0, 0.5, 4.0)
		e["sfx_sink"] = clampf(1.0 - (now - float(e.get("fx_up0", -9.0))) / 0.15, 0.0, 1.0)


func blade_event(kind: String, p: Vector2, a := 0.0, b := 0.0) -> void:
	match kind:
		"slash":
			# 斩击·横扫挥刃（§11.2 A，r170）：大月牙刀光 + 扇区腾起黑雾 + 深红火花；b = 半径（缺省 170）
			var sr: float = b if b > 0.0 else 170.0
			bevents.append(["slash", p, a, g.t, false, sr])
			for i in 30:
				var q: Vector2 = p + Vector2.from_angle(a + rng.randf_range(-PI / 3.0, PI / 3.0)) * rng.randf_range(40.0, sr)
				_fog(q, 1, 0.5, 0.15 * float(i % 5) / 5.0)
			sparks(p + Vector2.from_angle(a) * sr * 0.6, a, 1.0, 16, 360.0, BLOOD)
		"spin", "dash":
			bevents.append([kind, p, a, g.t, false, b])
		"erupt", "rain":
			bevents.append([kind, p, a, g.t + b, false])
		"flake", "lash":
			bevents.append([kind, p, a, g.t, false, b])
		"whip", "shade":
			# 鞭长按扇形半径：鞭扫 120°/r260、鞭影 90°/r200、战意鞭笞 50°/r220；shade = 片影跟着抽（暗一档 + 片影身形）
			var wl: float = 260.0 if b > 0.9 else (200.0 if b > 0.6 else 220.0)
			bevents.append(["whip", p, a, g.t, false, b, wl, kind == "shade"])
		"rider":
			runners.append(["rider", p, a, b, g.t, b / 1600.0])   # 可汗片影冲过（1600 px/秒）
		"beast":
			runners.append(["beast", p, a, b, g.t, 0.35])          # 王者友伴扑击
		"rewind":
			sparks(p + Vector2(0, -16), 0.0, PI, 5, 160.0, [Color(1, 1, 0.9), LUKA, LUKA_O, LUKA_D], true, 0.25)
		"dial":
			bevents.append([kind, p, a, g.t, false, b, -1])
		"flash":
			# 路加出手火光（王令 / 历法环 / 逆历 / 瞬身）：手边一团金橙火花往外溅 + 金黄余烬
			sparks(p + Vector2(0, -34), a, b if b > 0.0 else PI, 14, 280.0, [Color(1, 1, 0.92), LUKA, LUKA_O, LUKA_D], true, 0.35)
			embers(p + Vector2(0, -30), 6, LUKA_O, 120.0, 200.0, 0.5, 4.0)


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
		var tx: Texture2D = ice_puff[int(q[6]) % 3] if int(q[8]) == 1 else (lil_puff[int(q[6]) % 3] if int(q[8]) == 2 else fog_puff[int(q[6])])
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


## 刃林大刃的数量 / 位置 / 倒向（预警和结算共用，按国度圆心哈希定形，两边对得上）
func _kb_n(r: float) -> int:
	return clampi(int(r / 22.0), 3, 5)


func _kb_pos(c: Vector2, r: float, j: int, n: int, sd: int, gy: float) -> Vector2:
	if n >= 4 and j == 0:
		return c + Vector2(0, 4)
	var m: int = n - 1 if n >= 4 else n
	var jj: int = j - 1 if n >= 4 else j
	var a: float = float(sd % 628) / 100.0 + TAU * float(jj) / float(m)
	return c + Vector2(cos(a), sin(a) * gy) * r * 0.55


func _kb_dir(c: Vector2, q: Vector2, sd: int) -> Vector2:
	var d: Vector2 = q - c
	if d.length() < 8.0:
		return Vector2.from_angle(float(sd % 628) / 100.0 + PI / 5.0)
	return d.normalized()


## 大刃（刃林）：底 base、高 h、宽 wd；lean 0 直立 → 1 朝 ld 倒地。刃身两面明暗（背光面黑钢、受光面钢灰）、
## 一侧深红刃口、中脊白高光、暗描边；脚下落影 + 黑烟环（刃从烟里长出来）
func _big_blade(w, base: Vector2, h: float, wd: float, ld: Vector2, lean: float) -> void:
	if h < 2.0:
		return
	var gd := Vector2(ld.x, ld.y * 0.55).normalized()
	var up: Vector2 = Vector2(0, -1).lerp(gd, lean).normalized()
	var n := up.orthogonal()
	var hw: float = wd * 0.5
	var sl: float = h * (0.3 + 0.7 * lean)
	var gn := gd.orthogonal()
	w.tb_poly(PackedVector2Array([base - gn * (hw + 4.0), base + gd * sl - gn * 3.0, base + gd * (sl + 4.0), base + gd * sl + gn * 3.0, base + gn * (hw + 4.0)]), Color(0.05, 0.03, 0.06, 0.5))
	var sh: float = h * 0.62
	var tip: Vector2 = base + up * h
	var L0: Vector2 = base - n * hw
	var R0: Vector2 = base + n * hw
	var L1: Vector2 = base + up * sh - n * hw
	var R1: Vector2 = base + up * sh + n * hw * 0.9
	var o: float = 2.5
	w.tb_poly(PackedVector2Array([L0 - n * o + up * -1.0, L1 - n * o, tip + up * (o + 1.5), R1 + n * o, R0 + n * o + up * -1.0]), OLC)
	w.tb_poly(PackedVector2Array([L0, L1, tip, base + up * sh * 0.95, base]), BK)
	w.tb_poly(PackedVector2Array([base, base + up * sh * 0.95, tip, R1, R0]), STEEL[2])
	w.tb_poly(PackedVector2Array([R0 - n * 3.0, R1 - n * 3.0, tip, R1, R0]), BLOOD[2])
	w.tb_line(_snap(base + up * 6.0), _snap(base + up * (h - 8.0)), Color(1.0, 0.95, 0.92), 2.0)
	w.tb_quad(_snap(base - n * (hw + 7.0) + Vector2(0, -2)), _snap(base + n * (hw + 7.0) + Vector2(0, -2)), _snap(base + n * (hw + 5.0) + Vector2(0, 4)), _snap(base - n * (hw + 5.0) + Vector2(0, 4)), FOG[0])


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
	_draw_bscars(w, cv, now)
	_draw_barcs(w, now)
	# 预警（通用画法已关：blade.gd 给这些预警挂 skin sami_blade，telegraph_draw.quiet 跳过）：裂缝 + 黑雾先渗出 + 刃尖先冒头，不画描边圈 / 半透明填充
	for t in g.warns:
		if t.done or str(t.get("skin", "")) != "sami_blade":
			continue
		var k: float = clampf(float(t.t) / maxf(0.01, float(t.dur)), 0.0, 1.0)
		var sd: int = absi(hash(Vector2i(int(t.pos.x), int(t.pos.y)))) % 9973
		var ot: String = str(t.owner.get("type", "")) if t.get("owner") is Dictionary else ""
		if ot != "" and ot != "blade" and ot != "wanderer":
			_warn_final(w, cv, t, k, sd, ot)
			continue
		match t.shape:
			"cone":
				# 斩击：扇区里 7 道裂缝从它脚下往外裂，外弧一排刃尖冒头（r130 的边就是这排刃尖）
				var r3: float = float(t.r)
				var a0: float = float(t.ang) - float(t.half)
				var a1: float = float(t.ang) + float(t.half)
				for i in 7:
					_crack(w, t.pos, lerpf(a0 + 0.08, a1 - 0.08, float(i) / 6.0), r3 - 8.0, k, sd + i * 17, 4.0)
				_scar_arc(w, t.pos, r3 - 6.0, a0, a1, k)
				if k > 0.7 and t.get("owner") is Dictionary:
					var oe: Dictionary = t.owner
					var gl: Vector2 = oe.pos + Vector2(0, -40) + Vector2.from_angle(float(t.ang) - PI * 0.6) * 18.0
					w.tb_poly(PackedVector2Array([gl + Vector2(0, -9), gl + Vector2(3, 0), gl + Vector2(0, 9), gl + Vector2(-3, 0)]), Color(1, 0.95, 0.92))   # 举刃：刃尖一点白光
					w.tb_poly(PackedVector2Array([gl + Vector2(-9, 0), gl + Vector2(0, -2), gl + Vector2(9, 0), gl + Vector2(0, 2)]), Color(1, 0.95, 0.92))
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
				# 投刃 / 追猎 / 猎斩：沿线一条连续黑雾带往前铺到 k（宽 = 判定宽，不画两侧刻痕——会读成虚线），中线一道暗红裂缝
				_band(cv, t.pos, t.pos + d * L * k, hw * 0.75, 0.35 + 0.4 * k)
				_crack(w, t.pos, float(t.ang), L, k, sd, 4.0)
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
				# 雾中突袭 / 雾行旋斩（§11.2，11-26：伤人的只有本体，地上不冒刃）：圈里星形裂缝往外爬、圈边一圈低亮度黑雾慢慢加浓；
				# 本体沉在雾下滑过来时，后 40% 圆心先顶出它自己的一截刃尖（黑刃 + 红刃口），读成「它要从这里钻出来」
				var sdk: int = absi(hash(Vector2i(int(t.pos.x), int(t.pos.y)))) % 997
				for i in 6:
					_crack(w, t.pos, TAU * float(i) / 6.0 + float(sdk % 7) * 0.3, r * 0.92, k, sdk + i, 4.0)
				var ne: int = clampi(int(TAU * r / 40.0), 8, 20)
				for i in ne:
					var aa2: float = TAU * float(i) / float(ne) + 0.2 * sin(now * 0.7 + float(i))
					var q2: Vector2 = t.pos + Vector2(cos(aa2), sin(aa2) * gy) * r * 0.95
					var sz2: float = 40.0 * (0.8 + 0.4 * k)
					cv.draw_texture_rect(fog_puff[(i + sdk) % 4], Rect2(((q2 - Vector2(sz2, sz2 * 0.8) * 0.5) / PX).floor() * PX, Vector2(sz2, sz2 * 0.8)), false, Color(1, 1, 1, 0.15 + 0.45 * k))
				var ow = t.get("owner")
				if k > 0.6 and ow is Dictionary and float(ow.get("sunk_until", 0.0)) > now:
					_tip(w, t.pos + Vector2(4, 2), 34.0 * (k - 0.6) / 0.4)
				if rng.randf() < 0.3 + k * 0.5:
					var aa3: float = rng.randf() * TAU
					_fog(t.pos + Vector2(cos(aa3), sin(aa3) * gy) * rng.randf_range(r * 0.6, r), 1, 0.7, 0.0, true, 0.8, Vector2(cos(aa3), sin(aa3) * gy) * -20.0)
	w.tb_flush()
	for id in blade_list.keys():
		var it: Array = blade_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			blade_list.erase(id)
			continue
		var snk: float = float(e.get("sfx_sink", 0.0))
		if snk > 0.05:
			# 雾下黑影（§11.2 画面要求：黑影是实心椭圆 + 露出雾面的刃尖，穿过非国度地面也看得见）
			var rr: float = float(e.r) * 1.5
			var sp: Vector2 = e.pos
			w.tb_flush()
			cv.draw_set_transform(sp, 0.0, Vector2(1.0, 0.42))
			cv.draw_circle(Vector2.ZERO, rr + 6.0, Color(0.03, 0.02, 0.04, 0.45 * snk))
			cv.draw_circle(Vector2.ZERO, rr, Color(0.02, 0.01, 0.03, 0.88 * snk))
			cv.draw_circle(Vector2(-rr * 0.25, -rr * 0.2), rr * 0.45, Color(0.16, 0.04, 0.05, 0.6 * snk))
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if rng.randf() < 0.5:
				var gl = e.get("glide")
				var mvv: Vector2 = Vector2.ZERO
				if gl is Dictionary and not (gl.pts as Array).is_empty():
					mvv = ((gl.pts[0] as Vector2) - sp).normalized()
				_fog(sp - mvv * rr + Vector2(rng.randf_range(-rr, rr) * 0.6, 0), 1, 0.7, 0.0, true, 0.9, -mvv * 60.0 + Vector2(0, -8))
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
		if float(e.get("sfx_sink", 0.0)) > 0.6:
			_tip(w, e.pos + Vector2(6, 0), 22.0 + 3.0 * sin(now * 9.0))   # 露出雾面的一截刃尖
		for x in e.get("ents", []):
			var t: float = float(x.t)
			var hold: float = float(x.hold)
			var life: float = float(x.life)
			var first: bool = not x.get("fx_seen", false)
			x["fx_seen"] = true
			var u: float = clampf((t - hold) / maxf(0.05, life), 0.0, 1.0)
			match str(x.k):
				"rise":
					if first:
						_fog(x.pos, 5, 0.6)
					var tot: float = hold + life
					var hk: float = clampf((t - 0.06) / 0.12, 0.0, 1.0)
					hk = 1.0 - (1.0 - hk) * (1.0 - hk)
					var sink: float = clampf((tot - t) / 0.12, 0.0, 1.0)
					var lean: float = clampf((t - hold) / 0.12, 0.0, 1.0) * 0.85 if hold > 0.0 else 0.0
					var ld: Vector2 = Vector2.from_angle(float(x.get("ang", 0.0))) if x.has("ang") else Vector2.RIGHT
					_rise_blade(w, x.pos, 38.0 * hk * sink, ld, lean)
				"slash":
					if first:
						blade_event("slash", x.pos, float(x.ang), float(x.r))   # 大横斩刀带（11-28 新判定 r300 / 收尾斩 r180）：刀带本身就是读法，不再另画暗红斩痕
				"burst":
					if first:
						# 从国度黑雾里冲出（大横斩第 1.8 秒）：脚下黑雾整团往冲出方向翻涌 + 暗红火星，地上压一圈黑雾
						var bd := Vector2.from_angle(float(x.get("ang", 0.0)))
						for j in 14:
							_fog(x.pos + Vector2(rng.randf_range(-30, 30), rng.randf_range(-16, 16)), 1, 0.9, 0.02 * float(j % 4), false, 2.0, bd * rng.randf_range(80.0, 200.0) + Vector2(0, -rng.randf_range(10, 50)))
						_fog(x.pos, 8, 1.2, 0.0, true, 1.8)
						sparks(x.pos + Vector2(0, -20), float(x.get("ang", 0.0)), 0.8, 12, 320.0, BLOOD, true, 0.35)
				"upslash":
					_upslash(w, x, u, first)
				"spin":
					if first:
						var gy2: float = g.combat.GROUND_Y
						var Rs: float = maxf(60.0, float(x.r))
						for i in 16:
							var aa: float = TAU * float(i) / 16.0
							_fog(x.pos + Vector2(cos(aa), sin(aa) * gy2) * Rs * 0.85, 1, 0.8, 0.0, true, 1.5, Vector2(cos(aa), sin(aa) * gy2) * 110.0)   # 一圈翻起的黑雾
						sparks(x.pos + Vector2(0, -10), 0.0, PI, 14, 320.0, BLOOD, true, 0.3)
						blade_event("spin", x.pos, (g.ppos - (x.pos as Vector2)).angle(), Rs)   # 旋身斩 = 一整圈刀带
				"vortex":
					_vortex(w, x, t, life, first)
				"redslash":
					_redslash2(w, x, u, first)   # 11-28：贴地飞行的窄斩波（原红光柱像激光）
				_:
					_thrown(w, x, t, hold)
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
			if age > 0.5:
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
		if ev[0] == "slash" or ev[0] == "spin":
			# 国度 + 横斩（fm_b1）：刀带扫过后残留 0.35 秒再碎散，地上留弧形斩痕；spin = 旋身斩一整圈
			var spin: bool = ev[0] == "spin"
			if age > 0.95:
				continue
			keep.append(ev)
			var sr: float = float(ev[5]) if ev.size() > 5 else 170.0
			var hf: float = PI if spin else PI / 3.0
			if not ev[4]:
				ev[4] = true
				barcs.append([p, float(ev[2]) - hf - 0.12, float(ev[2]) + hf + 0.12, sr, now])
			_big_slash2(w, g.wcv, p, float(ev[2]), sr, age, hf, 0.2 if spin else 0.12)
			continue
		if ev[0] == "dash":
			if age > 0.5:
				continue
			keep.append(ev)
			if not ev[4]:
				ev[4] = true
				var dd := Vector2.from_angle(float(ev[2]))
				bscars.append([p, p + dd * float(ev[5]), now, 30.0, rng.randi() % 997])
				for j in 6:
					_fog(p + dd * float(ev[5]) * (float(j) + 0.5) / 6.0, 1, 0.7, 0.03 * float(j), true, 1.4, dd * 40.0)
			_dash_ghost(w, ev, age)
			continue
		if ev[0] == "erupt":
			# 刃林（用户 11-25 第二次退回：成片、有体积、少而大）：预警后段已冒头的 3–5 把大刃，结算时 0.14 秒从黑烟里竖到全高，
			# 停一拍，0.3–0.46 秒一起朝外倒下砸地（落地扬黑烟 + 火星），之后沉进烟里
			if age > 0.85:
				continue
			keep.append(ev)
			if age < 0.0:
				continue
			var kr: float = ev[2]
			var gy2: float = g.combat.GROUND_Y
			var sdk2: int = absi(hash(Vector2i(int(p.x), int(p.y)))) % 997
			var nb: int = _kb_n(kr)
			if not ev[4]:
				ev[4] = true
				for i in 12:
					_fog(p + Vector2.from_angle(TAU * i / 12.0) * kr * rng.randf_range(0.3, 0.95), 1, 0.8, 0.0, false, 1.2)
				for j in nb:
					var bq: Vector2 = _kb_pos(p, kr, j, nb, sdk2, gy2)
					_fog(bq, 3, 0.7, 0.0, false, 1.1, Vector2(0, -30))
					sparks(bq + Vector2(0, -20), -PI * 0.5, 0.7, 6, 300.0, BLOOD, true, 0.35)
			var landed: bool = ev.size() > 5
			for j in nb:
				var bq2: Vector2 = _kb_pos(p, kr, j, nb, sdk2, gy2)
				var od2: Vector2 = _kb_dir(p, bq2, sdk2)
				var H: float = 78.0 + 12.0 * float(j % 2)
				var hk: float = clampf(age / 0.14, 0.0, 1.0)
				hk = 1.0 - (1.0 - hk) * (1.0 - hk)
				var hh: float = lerpf(30.0, H, hk)
				var fall: float = clampf((age - 0.3) / 0.16, 0.0, 1.0)
				fall = fall * fall
				var sink: float = clampf((0.85 - age) / 0.3, 0.0, 1.0)
				var trem: float = sin(age * 90.0 + float(j)) * 1.5 if age > 0.14 and age < 0.3 else 0.0
				_big_blade(w, bq2 + Vector2(trem, 0), hh * (0.35 + 0.65 * sink), 22.0 + 4.0 * float(j % 2), od2, fall * 0.92)
				if fall >= 1.0 and not landed:
					var gd2 := Vector2(od2.x, od2.y * 0.55).normalized()
					for s in 4:
						_fog(bq2 + gd2 * H * (0.2 + 0.25 * float(s)), 1, 0.7, 0.0, true, 1.0, gd2.orthogonal() * (40.0 if s % 2 == 0 else -40.0))
					sparks(bq2 + gd2 * H * 0.9, od2.angle(), 1.2, 8, 260.0, BLOOD, true, 0.3)
					embers(bq2 + gd2 * H * 0.5, 5, FOG[2], 120.0, 260.0, 0.45, 4.0)
			if age >= 0.46 and not landed:
				ev.append(true)
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



## ---- 利刃 / 游荡者 11-26 新招画面（docs/393 §11.2：伤人的都是本体或它手里的刃）
## 大刃片（投刃·切雾）：沿飞行方向的重刃贴地低飞，刃尖朝前，地上一道影子，身后犁出黑雾
func _thrown(w, x: Dictionary, t: float, hold: float) -> void:
	# 投刃大刃片（用户 11-26 样板 v3）：月牙刃 32 贴图（白刃口 + 暗红刃身 + 身后黑烟 + 霜点），朝飞行方向
	var dv: Vector2 = x.vel.normalized() if x.vel.length() > 1.0 else Vector2.from_angle(float(x.get("ang", 0.0)))
	var tx: ImageTexture = bul.tex("blade", 32, dv.angle())
	var sz2 := Vector2(tx.get_width(), tx.get_height()) * PX
	w.tb_flush()
	g.wcv.draw_texture_rect(tx, Rect2(_snap(x.pos + Vector2(0, -12) - sz2 * 0.5), sz2), false)
	if t >= hold:
		_fog(x.pos - dv * 30.0, 1, 0.55, 0.0, true, 0.9, -x.vel * 0.15)


## 预警外弧：一道连续的暗红斩痕弧（暗边 + 深红芯，中间厚两头尖），k 0→1 从中间往两头长
func _scar_arc(w, c: Vector2, r: float, a0: float, a1: float, k: float) -> void:
	var m: float = (a0 + a1) * 0.5
	var h: float = (a1 - a0) * 0.5 * clampf(k * 1.3, 0.0, 1.0)
	if h < 0.02:
		return
	var n := 16
	for pass_i in 2:
		for j in n:
			var f0: float = float(j) / float(n)
			var f1: float = float(j + 1) / float(n)
			var b0: float = lerpf(m - h, m + h, f0)
			var b1: float = lerpf(m - h, m + h, f1)
			var t0: float = 2.0 + 6.0 * sin(PI * f0) + (2.0 if pass_i == 0 else 0.0)
			var t1: float = 2.0 + 6.0 * sin(PI * f1) + (2.0 if pass_i == 0 else 0.0)
			w.tb_quad(c + Vector2.from_angle(b0) * (r + t0), c + Vector2.from_angle(b1) * (r + t1), c + Vector2.from_angle(b1) * (r - t1), c + Vector2.from_angle(b0) * (r - t0), OLC if pass_i == 0 else BLOOD[1])


## 斩痕：扇形外沿一道暗红月牙（地上），u 0→1 淡掉
func _slash_scar(w, c: Vector2, ang: float, r: float, u: float) -> void:
	var a0: float = ang - PI / 3.0
	var a1: float = ang + PI / 3.0
	var n := 16
	var al: float = 1.0 - u
	for j in n:
		var f0: float = float(j) / float(n)
		var f1: float = float(j + 1) / float(n)
		var th0: float = 10.0 * sin(PI * f0) + 2.0
		var th1: float = 10.0 * sin(PI * f1) + 2.0
		var b0: float = lerpf(a0, a1, f0)
		var b1: float = lerpf(a0, a1, f1)
		var ro: float = r * 0.9
		w.tb_quad(c + Vector2.from_angle(b0) * (ro + 2.0), c + Vector2.from_angle(b1) * (ro + 2.0), c + Vector2.from_angle(b1) * (ro - th1 - 2.0), c + Vector2.from_angle(b0) * (ro - th0 - 2.0), Color(OLC, 0.8 * al))
		w.tb_quad(c + Vector2.from_angle(b0) * ro, c + Vector2.from_angle(b1) * ro, c + Vector2.from_angle(b1) * (ro - th1), c + Vector2.from_angle(b0) * (ro - th0), Color(BLOOD[1], al))


## 大横斩：刀带 0.12 秒从扇形一边扫到另一边，尾巴 0.12–0.45 秒追上收掉；刀头厚 70、尾细；外沿白热刃口 + 暗红带 + 黑刀身 + 深色描边；
## 扫过时刀背后翻出黑雾（从国度里冲出来的读法）、刃尖甩白橙火星；照地红光只在刀头下一小团（红光不铺满屏）
func _big_slash(w, cv, p: Vector2, ca: float, SR: float, age: float) -> void:
	var e0: float = ca - PI / 3.0 - 0.12
	var e1: float = ca + PI / 3.0 + 0.12
	var hd: float = lerpf(e0, e1, 1.0 - pow(1.0 - clampf(age / 0.12, 0.0, 1.0), 2.0))
	var tl: float = maxf(e0, maxf(hd - 1.7, lerpf(e0, e1, clampf((age - 0.12) / 0.33, 0.0, 1.0))))
	if hd - tl < 0.03:
		return
	var R: float = SR
	var fade: float = clampf((age - 0.3) / 0.2, 0.0, 1.0)
	var hp: Vector2 = p + Vector2.from_angle(hd) * (R - 20.0)
	var gt: Texture2D = _glow_tex()
	cv.draw_texture_rect(gt, Rect2(((hp - Vector2(80, 46)) / PX).floor() * PX, Vector2(160, 92)), false, Color(1.0, 0.32, 0.26, 0.24 * (1.0 - fade)))
	var ns := 26
	for pass_i in 4:
		for j in ns:
			var f0: float = float(j) / float(ns)
			var f1: float = float(j + 1) / float(ns)
			var b0: float = lerpf(tl, hd, f0)
			var b1: float = lerpf(tl, hd, f1)
			var tm: float = 0.42 * R / 0.47   # 最厚 ≈ 0.42R（静态对照 r300 过审）
			var t0: float = (4.0 + tm * pow(f0, 1.2) * pow(1.0 - f0, 0.3)) * (1.0 - 0.6 * fade)   # 两头尖的月牙：最厚处在刀头后一点
			var t1: float = (4.0 + tm * pow(f1, 1.2) * pow(1.0 - f1, 0.3)) * (1.0 - 0.6 * fade)
			var ro: float = R
			var r0i: float = R - t0
			var r1i: float = R - t1
			var cc: Color
			match pass_i:
				0:
					ro = R + 3.0
					r0i -= 3.0
					r1i -= 3.0
					cc = OLC
				1:
					cc = BK
				2:
					r0i = R - t0 * 0.3   # 暗红带收到刀身 30%，黑刀身为主
					r1i = R - t1 * 0.3
					cc = BLOOD[1].lerp(BLOOD[2], f0)
				_:
					r0i = R - 4.0 - 5.0 * f0
					r1i = R - 4.0 - 5.0 * f1
					cc = Color(1.0, 1.0, 0.97) if f0 > 0.3 else BLOOD[3]
			if fade > 0.0:
				cc.a = 1.0 - fade
			w.tb_quad(p + Vector2.from_angle(b0) * ro, p + Vector2.from_angle(b1) * ro, p + Vector2.from_angle(b1) * r1i, p + Vector2.from_angle(b0) * r0i, cc)
	if age < 0.3:
		for i in 3:
			var bq: float = lerpf(tl, hd, rng.randf() * 0.8)
			var q: Vector2 = p + Vector2.from_angle(bq) * (R - 30.0)
			_fog(q, 1, 0.8, 0.0, false, 2.2, Vector2.from_angle(bq) * 60.0 + Vector2.from_angle(bq - PI * 0.5) * 40.0)
		sparks(hp, hd + PI * 0.5, 0.6, 3, 320.0, [Color(1, 0.96, 0.9), Color(1.0, 0.62, 0.3), BLOOD[3], BLOOD[2]], true, 0.3)


## 地上斩痕（国度猎斩，fm_b2）：锯齿黑痕 + 暗红芯，1.4 秒淡掉，芯里零星火星；只一条窄带，不铺红光
func _draw_bscars(w, cv, now: float) -> void:
	if bscars.is_empty():
		return
	var keep: Array = []
	for sc in bscars:
		var age: float = now - float(sc[2])
		if age > 1.4:
			continue
		keep.append(sc)
		var a: Vector2 = sc[0]
		var b: Vector2 = sc[1]
		var d: Vector2 = (b - a)
		var L: float = d.length()
		if L < 2.0:
			continue
		d /= L
		var nv := d.orthogonal()
		var al: float = clampf((1.4 - age) / 0.5, 0.0, 1.0)
		var grow: float = clampf(age / 0.08, 0.0, 1.0)
		var Wd: float = float(sc[3])
		var sd: int = int(sc[4])
		var n: int = maxi(4, int(L / 22.0))
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		var core_t := PackedVector2Array()
		var core_b := PackedVector2Array()
		for i in n + 1:
			var f: float = float(i) / float(n)
			var q: Vector2 = a + d * L * f * grow
			var taper: float = sin(PI * clampf(f, 0.02, 0.98))
			var jg: float = (float(absi(hash(Vector2i(sd, i))) % 100) / 100.0) * 0.6 + 0.4
			top.append(_snap(q + nv * Wd * 0.5 * taper * jg))
			bot.append(_snap(q - nv * Wd * 0.5 * taper * (1.4 - jg)))
			core_t.append(_snap(q + nv * Wd * 0.14 * taper))
			core_b.append(_snap(q - nv * Wd * 0.14 * taper))
		var poly := PackedVector2Array(top)
		var cpoly := PackedVector2Array(core_t)
		for i in range(n, -1, -1):
			poly.append(bot[i])
			cpoly.append(core_b[i])
		w.tb_polygon(poly, Color(BK, 0.9 * al))
		w.tb_polygon(cpoly, Color(BLOOD[2], al * (0.6 + 0.4 * sin(now * 18.0 + float(sd)))))
		if rng.randf() < 0.3 * al:
			embers(a + d * L * rng.randf(), 1, BLOOD[3], 60.0, 120.0, 0.5, 3.0)
	bscars = keep
	w.tb_flush()


## 刀光带：以 c 为心、从 tl 到 hd 角的一段月牙（白头 + 深红身 + 黑尾，暗描边），sy = 纵向压扁，th = 头部最大厚度
func _arc_band(w, c: Vector2, R: float, tl: float, hd: float, sy: float, th: float) -> void:
	if absf(hd - tl) < 0.03:
		return
	var ns := 18
	for pass_i in 2:
		for j in ns:
			var f0: float = float(j) / float(ns)
			var f1: float = float(j + 1) / float(ns)
			var b0: float = lerpf(tl, hd, f0)
			var b1: float = lerpf(tl, hd, f1)
			var o: float = 3.0 if pass_i == 0 else 0.0
			var cc: Color = OLC
			if pass_i == 1:
				cc = Color(1.0, 0.95, 0.92) if f0 > 0.86 else (BLOOD[2] if f0 > 0.5 else (BLOOD[1] if f0 > 0.2 else BK))
			var t0: float = 5.0 + th * f0 + o
			var t1: float = 5.0 + th * f1 + o
			w.tb_quad(c + Vector2(cos(b0), sin(b0) * sy) * (R + o), c + Vector2(cos(b1), sin(b1) * sy) * (R + o),
				c + Vector2(cos(b1), sin(b1) * sy) * (R - t1), c + Vector2(cos(b0), sin(b0) * sy) * (R - t0), cc)


## 上撩（雾中突袭钻出）：本体从地下钻出、刃往上撩——一道竖起的大月牙刀光从地面往上划，
## 脚下星形裂缝 + 黑雾往四周翻 + 碎石
func _upslash(w, x: Dictionary, u: float, first: bool) -> void:
	var p: Vector2 = x.pos
	var R: float = float(x.r)
	if first:
		for i in 10:
			var aa: float = TAU * float(i) / 10.0
			_fog(p + Vector2(cos(aa), sin(aa) * 0.6) * R * 0.5, 1, 0.6, 0.0, true, 1.1, Vector2(cos(aa), sin(aa) * 0.6) * 120.0)
		sparks(p + Vector2(0, -30), -PI * 0.5, 0.5, 14, 420.0, BLOOD, true, 0.35)
		embers(p, 8, FOG[2], 170.0, 320.0, 0.55, 4.0)
		embers(p, 4, BLOOD[1], 140.0, 320.0, 0.5, 4.0)
	for i in 6:
		_crack(w, p, TAU * float(i) / 6.0 + 0.4, R * 0.9 * minf(1.0, u * 4.0), 1.0, 77 + i, 4.0)
	# 刀光：以腰为心、从右下往左上划过约 140°，前 35% 划完，之后尾巴追上收掉
	var hd: float = lerpf(0.5, -2.0, 1.0 - pow(1.0 - clampf(u / 0.35, 0.0, 1.0), 2.0))
	var tl: float = lerpf(0.5, hd, clampf((u - 0.3) / 0.7, 0.0, 1.0))
	tl = maxf(tl, hd)
	_arc_band(w, p + Vector2(0, -30), R * 0.85, tl, hd, 1.15, 24.0)


## 旋斩（黑毯·回旋 / 雾行钻出 / 皇帝的猎杀途经）：刃贴地旋一整圈——斩环带头扫过 360°，扬起一圈黑雾
func _spin(w, x: Dictionary, u: float, first: bool) -> void:
	var p: Vector2 = x.pos
	var R: float = maxf(60.0, float(x.r))
	var gy: float = g.combat.GROUND_Y
	if first:
		for i in 12:
			var aa: float = TAU * float(i) / 12.0
			_fog(p + Vector2(cos(aa), sin(aa) * gy) * R * 0.8, 1, 0.55, 0.0, true, 0.9, Vector2(cos(aa), sin(aa) * gy) * 90.0)
		sparks(p + Vector2(0, -10), 0.0, PI, 14, 320.0, BLOOD, true, 0.3)
	var hd: float = TAU * clampf(u / 0.55, 0.0, 1.0)
	var tl: float = minf(hd, maxf(0.0, hd - 2.4) + TAU * clampf((u - 0.55) / 0.45, 0.0, 1.0))
	_arc_band(w, p, R, tl, hd, gy, 18.0)


## 红漩（国度猎斩起手，原作 BV1ru41157cJ 166.6–166.9 秒：本体身边聚起一团暗红漩涡，变成黑红的洞）：
## 刃尖高度四条旋臂往里卷、越卷越紧，中心黑洞越来越大，暗红颗粒被吸进去
func _vortex(w, x: Dictionary, t: float, life: float, first: bool) -> void:
	var c: Vector2 = x.pos + Vector2(0, -34)
	var k: float = clampf(t / maxf(0.05, life), 0.0, 1.0)
	var R: float = 14.0 + 22.0 * k
	for arm in 4:
		var prev := Vector2.INF
		for i in 12:
			var f: float = float(i) / 11.0
			var aa: float = float(arm) * TAU / 4.0 + t * 11.0 + f * 3.2
			var q: Vector2 = c + Vector2(cos(aa), sin(aa) * 0.8) * R * (1.0 - f * 0.8)
			if prev != Vector2.INF:
				w.tb_line(_snap(prev), _snap(q), OLC, 7.0)
				w.tb_line(_snap(prev), _snap(q), BLOOD[1] if f < 0.6 else BLOOD[2], 4.0)
			prev = q
	w.tb_circle(c, 6.0 + 9.0 * k, Color(0.02, 0.0, 0.01), 1.0, 14)
	w.tb_circle(c, 2.0 + 4.0 * k, Color(0.3, 0.0, 0.02), 1.0, 10)
	if rng.randf() < 0.8:
		var aq: float = rng.randf() * TAU
		_add(c + Vector2.from_angle(aq) * (R + 26.0), -Vector2.from_angle(aq) * (R + 26.0) / 0.25, 0.25, BLOOD[rng.randi_range(1, 3)], 2.0, 2)


## 红色斩光（国度猎斩，原作 167.2 秒）：一道细长的红色刀光沿线劈出（白芯 + 红身 + 暗边，前粗后尖），
## 0.25 秒内变细淡掉；沿线溅深红火花，起点一团红十字闪光
func _redslash(w, x: Dictionary, u: float, first: bool) -> void:
	var p: Vector2 = x.pos + Vector2(0, -24)
	var d := Vector2.from_angle(float(x.ang))
	var nv := d.orthogonal()
	var L: float = float(x.r)
	if first:
		for i in 8:
			sparks(p + d * L * float(i) / 8.0, float(x.ang) + PI * 0.5 * (1.0 if i % 2 == 0 else -1.0), 0.6, 2, 220.0, BLOOD, true, 0.3)
		sparks(p, float(x.ang), 0.5, 10, 380.0, [Color(1, 0.95, 0.92), BLOOD[3], BLOOD[2], BLOOD[1]], true, 0.3)
	if first:
		bscars.append([x.pos + d * 10.0, x.pos + d * L, g.t, 26.0, rng.randi() % 997])   # 斩光过后地上留一道锯齿斩痕（fm_b2）
	var a: float = 1.0 - u
	var W: float = 26.0 * (1.0 - 0.6 * u)
	w.tb_poly(PackedVector2Array([p - nv * (W + 3.0), p + d * L * 0.35 - nv * (W * 0.7 + 3.0), p + d * (L + 6.0), p + d * L * 0.35 + nv * (W * 0.7 + 3.0), p + nv * (W + 3.0)]), Color(OLC, a))
	w.tb_poly(PackedVector2Array([p - nv * W, p + d * L * 0.35 - nv * W * 0.7, p + d * L, p + d * L * 0.35 + nv * W * 0.7, p + nv * W]), Color(BLOOD[2], a))
	w.tb_poly(PackedVector2Array([p - nv * W * 0.35, p + d * L * 0.4 - nv * W * 0.2, p + d * (L - 10.0), p + d * L * 0.4 + nv * W * 0.2, p + nv * W * 0.35]), Color(1.0, 0.95, 0.92, a))
	if u < 0.4:
		var cs: float = 26.0 * (1.0 - u / 0.4)
		w.tb_poly(PackedVector2Array([p + Vector2(0, -cs), p + Vector2(4, 0), p + Vector2(0, cs), p + Vector2(-4, 0)]), BLOOD[3])
		w.tb_poly(PackedVector2Array([p + Vector2(-cs, 0), p + Vector2(0, -4), p + Vector2(cs, 0), p + Vector2(0, 4)]), BLOOD[3])


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
	if kdir == 0:
		_kd_ink(cv, km, now)   # 11-28：成团墨状黑雾（原按格竖烟丝 _kd_grid 读成影线 / 草）
	else:
		for l in km.links:
			_band_tex(cv, grey_band, l[0].pos, l[1].pos, float(l[2]) * 0.9, 0.55)
	for k in km.list:
		if k.kind == "nursery":
			_void_draw(cv, g.world, k, now, gy)   # 苗圃吞地（11-28，fm_c3）
			continue
		if kdir == 0:
			continue
		if k.has("b"):
			_band(cv, k.pos, k.b, float(k.r), 0.4)
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
			cv.draw_texture_rect(grey_puff[i % 3], Rect2(((q - Vector2(sz, sz * 0.8) * 0.5) / PX).floor() * PX, Vector2(sz, sz * 0.8)), false, Color(1, 1, 1, KD_IN))
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
				var al2: float = KD_EDGE if kdir == 1 else (KD_EDGE if (i + row) % 2 == 0 else KD_EDGE * 0.8)
				cv.draw_texture_rect(fog_puff[(i + row + sd) % 4], Rect2(((q2 - Vector2(sz2, sz2 * 0.8) * 0.5) / PX).floor() * PX, Vector2(sz2, sz2 * 0.8)), false, Color(1, 1, 1, al2))
		if rng.randf() < 0.02 * r / 70.0:
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
	if kdir != 0:
		for c in km.cuts:
			_band_tex(cv, grey_band, c.a, c.b, float(c.w), 0.5 * clampf((float(c.until) - g.t) / 0.5, 0.0, 1.0))


## ==== 国度场地 A「按格铺」（协调人 11-26 定；原作 BV1ru41157cJ 3:10–3:32，docs/401 §18）：国度 = 按地块铺的竖向黑烟丝，
## 每格地面一层浅灰、格里 2 道黑烟丝往上飘（底浓顶淡、轻轻左右摆），丝与丝、格与格之间透出地面；整体低透明度，
## 画在地面层（单位 / 弹 / 预警之下）。只表示「站在里面攻速 −50%、挨本体招 ×1.5」，不画边线 / 描边圈 / 平涂圆盘，
## 不冒刃、不发光。新铺的国度从圆心往外一格格冒出来（0.35 秒一圈），到期 0.6 秒淡掉；投刃切开的口子里烟丝压下去
const KC_W := 64.0
const KC_H := 48.0
const KD_FLOOR := 0.28       # 每格浅灰地面（11-28 协调人：演示里国度黑雾看不见 → 0.17 提到 0.28）
const KD_WISP := 0.8         # 黑烟丝（同上，0.62 → 0.8）
var wisp_tex: Array = []


func _wisp_bake(seed: int) -> Texture2D:
	var w := 12
	var h := 36
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = 0.16
	n.fractal_octaves = 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ph: float = float(seed % 7)
	for y in h:
		for x in w:
			var fy: float = float(h - 1 - y) / float(h - 1)   # 0 底 → 1 顶
			var cx: float = float(w) * 0.5 + sin(fy * 3.4 + ph) * 1.6 * fy
			var hw: float = float(w) * 0.42 * (1.0 - 0.6 * fy)
			var f: float = clampf(1.0 - absf(float(x) + 0.5 - cx) / maxf(0.8, hw), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			var nv: float = n.get_noise_2d(float(x) * 1.3, float(y) * 0.6) * 0.5 + 0.5
			var a: float = f * pow(1.0 - fy, 0.9) * (0.45 + 0.8 * nv) * clampf(fy * 9.0 + 0.35, 0.0, 1.0)
			a = floorf(clampf(a, 0.0, 1.0) * 5.0) / 5.0
			var c: Color = Color(0.05, 0.035, 0.06).lerp(Color(0.13, 0.1, 0.14), fy)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _kd_put(cells: Dictionary, key: Vector2i, al: float, edge: float) -> void:
	var o = cells.get(key)
	if o == null:
		cells[key] = [al, edge]
	else:
		o[0] = maxf(float(o[0]), al)
		o[1] = minf(float(o[1]), edge)


## 一段条带（黑毯 / 连接带）里的格子：t0 = 铺开起点时刻，spd = 每秒铺多远（<0 = 一次铺满）
func _kd_seg(cells: Dictionary, a: Vector2, b: Vector2, hw: float, age: float, fade: float, spd: float) -> void:
	var lo: Vector2 = Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(hw, hw)
	var hi: Vector2 = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(hw, hw)
	for iy in range(int(floorf(lo.y / KC_H)), int(floorf(hi.y / KC_H)) + 1):
		for ix in range(int(floorf(lo.x / KC_W)), int(floorf(hi.x / KC_W)) + 1):
			var c := Vector2((float(ix) + 0.5) * KC_W, (float(iy) + 0.5) * KC_H)
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(c, a, b)
			var d: float = q.distance_to(c)
			if d >= hw:
				continue
			var rev: float = 1.0 if spd < 0.0 else clampf((age - q.distance_to(a) / spd) / 0.35, 0.0, 1.0)
			_kd_put(cells, Vector2i(ix, iy), rev * fade, d / hw)


func _kd_grid(cv, km, now: float) -> void:
	if wisp_tex.is_empty():
		for i in 4:
			wisp_tex.append(_wisp_bake(2101 + i * 13))
	var cells := {}
	for k in km.list:
		if k.kind == "nursery":
			continue
		var age: float = now - float(k.born)
		var fade: float = 1.0
		if float(k.life) > 0.0:
			fade = clampf((float(k.born) + float(k.life) - now) / 0.6, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var r: float = float(k.r)
		if k.has("b"):
			_kd_seg(cells, k.pos, k.b, r, age, fade, 900.0)
			continue
		for iy in range(int(floorf((k.pos.y - r) / KC_H)), int(floorf((k.pos.y + r) / KC_H)) + 1):
			for ix in range(int(floorf((k.pos.x - r) / KC_W)), int(floorf((k.pos.x + r) / KC_W)) + 1):
				var c := Vector2((float(ix) + 0.5) * KC_W, (float(iy) + 0.5) * KC_H)
				var d: float = c.distance_to(k.pos)
				if d >= r:
					continue
				var rev: float = clampf((age - d / 200.0) / 0.35, 0.0, 1.0)   # 从圆心往外一格格冒（200 px/秒）
				_kd_put(cells, Vector2i(ix, iy), rev * fade, d / r)
	for l in km.links:
		_kd_seg(cells, l[0].pos, l[1].pos, float(l[2]), 9.0, 1.0, -1.0)
	if cells.is_empty():
		return
	var vr: Rect2 = Rect2(g.cam.position - get_viewport_half() - Vector2(80, 120), get_viewport_half() * 2.0 + Vector2(160, 200))
	for key in cells.keys():
		var it: Array = cells[key]
		var al: float = float(it[0])
		if al <= 0.01:
			continue
		var o := Vector2(float(key.x) * KC_W, float(key.y) * KC_H)
		if not vr.has_point(o):
			continue
		if not km.cuts.is_empty() and km._in_cut(o + Vector2(KC_W, KC_H) * 0.5):
			al *= 0.2   # 投刃切开的口子：烟丝压下去，露出地面
		var edge: float = float(it[1])
		var hs: int = absi(hash(key))
		cv.draw_rect(Rect2(o + Vector2(4, 4), Vector2(KC_W - 8.0, KC_H - 8.0)), Color(0.6, 0.6, 0.64, KD_FLOOR * al * (1.0 - 0.4 * edge)))
		for j in 2:
			var hj: int = (hs >> (j * 5)) & 1023
			var ph: float = fmod(now * 0.3 + float(hj) / 1023.0, 1.0)   # 每道烟丝 3.3 秒一个循环：慢慢升起、淡出、底下再冒
			var env: float = 0.55 + 0.45 * sin(ph * PI)
			var s: float = (0.8 + 0.4 * float(hj % 37) / 36.0) * (1.0 - 0.45 * edge)
			var bx: float = o.x + 16.0 + 30.0 * float(j) + float(hj % 9) - 4.0 + sin(now * 0.8 + float(hj)) * 2.0
			var by: float = o.y + KC_H - 4.0 - ph * 10.0
			var sz := Vector2(24.0, 72.0 * s)
			cv.draw_texture_rect(wisp_tex[(hj + j) % 4], Rect2(_snap(Vector2(bx - sz.x * 0.5, by - sz.y)), sz), false, Color(1, 1, 1, KD_WISP * al * env * (1.0 - 0.35 * edge)))


func get_viewport_half() -> Vector2:
	return g.get_viewport_rect().size * 0.5 / g.cam.zoom


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
		var wd: float = lerpf(24.0, 7.0, f) * k
		if wd < 1.0:
			continue
		w.tb_line(_snap(pts[i]), _snap(pts[i + 1]), cols[0], wd + 4.0)
	for i in n:
		var f2: float = float(i) / float(n)
		var wd2: float = lerpf(24.0, 7.0, f2) * k
		if wd2 < 1.0:
			continue
		w.tb_line(_snap(pts[i]), _snap(pts[i + 1]), cols[1], wd2)
		if wd2 >= 5.0:
			w.tb_line(_snap(pts[i] + Vector2(0, -wd2 * 0.22)), _snap(pts[i + 1] + Vector2(0, -wd2 * 0.22)), cols[2], maxf(2.0, wd2 * 0.3))


func _draw_whip(w, ev: Array, age: float) -> void:
	var c: Vector2 = ev[1]
	var ca: float = ev[2]
	var half: float = ev[5]
	var hand: Vector2 = c + Vector2(0, -26)
	var L: float = float(ev[6]) if ev.size() > 6 else 150.0
	var shade: bool = ev.size() > 7 and ev[7]
	if shade and age < 0.45:
		_runner_pose(w, "rider", c, Vector2.from_angle(ca), age, 0.85 * clampf((0.45 - age) / 0.15, 0.0, 1.0))
	var a0: float = ca - half - 0.25
	var a1: float = ca + half + 0.1
	var fade: float = clampf((0.5 - age) / 0.2, 0.0, 1.0)
	# 挥动弧：鞭身扫过的区域一层层暗红拖影（相邻时刻鞭身之间填成带子，越旧越暗越淡）
	var prev := _whip_pts(hand, a0, a1, maxf(0.0, age - 0.1), L)
	for gh in [3, 2, 1]:
		var ta: float = age - 0.03 * float(gh)
		if ta <= 0.0:
			continue
		var cur := _whip_pts(hand, a0, a1, ta, L)
		var cc: Color = Color(KHAN[1 if gh > 1 else 2], (0.75 - 0.18 * float(gh)) * fade)
		for i in range(2, cur.size() - 1):
			w.tb_quad(_snap(prev[i]), _snap(prev[i + 1]), _snap(cur[i + 1]), _snap(cur[i]), cc)
		prev = cur
	for gh in [2, 1]:
		var ta2: float = age - 0.035 * float(gh)
		if ta2 > 0.0:
			_draw_whip_line(w, _whip_pts(hand, a0, a1, ta2, L), (0.6 - 0.15 * float(gh)) * fade, [KHAN[0], KHAN[1], KHAN[2]])
	var pts := _whip_pts(hand, a0, a1, age, L)
	_draw_whip_line(w, pts, fade, [OLC, KHAN[2], KHAN[3]])
	var tip: Vector2 = pts[pts.size() - 1]
	if age >= 0.16 and age < 0.26:
		_crack_star(w, tip, 1.0 - (age - 0.16) / 0.1)
	if not ev[4] and age >= 0.16:
		ev[4] = true
		sparks(tip, ca + half, 1.2, 16, 360.0, [Color(1.0, 0.95, 0.9), KHAN[3], KHAN[2], KHAN[1]], true, 0.32)
		embers(tip + Vector2(0, 20), 8, Color(0.55, 0.42, 0.28), 140.0, 260.0, 0.5, 4.0)
		_fog(tip + Vector2(0, 10), 3, 0.6, 0.0, true, 1.0)
		for i in 5:
			_fog(c + Vector2.from_angle(lerpf(a0, a1, float(i) / 4.0)) * 100.0 + Vector2(0, 18), 1, 0.6, 0.0, true, 0.7)


## 鞭梢炸响：0.1 秒的八角爆星（白芯 + 暗红外圈 + 暗边），k 1 → 0 收掉
func _crack_star(w, p: Vector2, k: float) -> void:
	var R: float = 30.0 * (0.6 + 0.4 * k)
	for layer in 3:
		var rr: float = R * [1.15, 1.0, 0.55][layer]
		var cc: Color = [OLC, KHAN[3], Color(1.0, 0.96, 0.9)][layer]
		var pts := PackedVector2Array()
		for i in 16:
			var a: float = TAU * float(i) / 16.0 + 0.2
			pts.append(p + Vector2(cos(a), sin(a) * 0.8) * (rr if i % 2 == 0 else rr * 0.42))
		w.tb_poly(pts, cc)


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
	if age >= 0.18 and age < 0.28:
		_crack_star(w, c + d * L, 1.0 - (age - 0.18) / 0.1)
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


## 锚桩轮廓（金色描边用）：s = 缩放
func _anchor_shape(p: Vector2, s: float) -> PackedVector2Array:
	return PackedVector2Array([p + Vector2(-22, 4) * s, p + Vector2(-20, -6) * s, p + Vector2(-9, -9) * s, p + Vector2(-8, -38) * s, p + Vector2(-14, -48) * s, p + Vector2(0, -66) * s,
		p + Vector2(14, -48) * s, p + Vector2(8, -38) * s, p + Vector2(9, -9) * s, p + Vector2(20, -6) * s, p + Vector2(22, 4) * s])


## 克雷松锚桩（协调人 11-25 退回：别像散落的子弹，要做成「设施」）：暗石底座（八角台） + 两面明暗的石柱 + 顶上淡紫晶尖，
## 和停驻点 / 银凇同一档体量（高约 60）；lit 0 = 熄（晶尖暗紫）→ 1 = 亮（晶尖淡紫白 + 柱身紫纹）
## 稳定设施晶簇花苞（用户 11-26：锚桩像子弹 → 晶体 / 花苞形，样板 v3）：贴图 34×44，原点在底座；熄 = 压暗
func _bud(w, p: Vector2, lit: float, s := 1.0, gold := false) -> void:
	w.tb_flush()
	var tx: ImageTexture = bul.bud()
	var sz2 := Vector2(34, 44) * PX * s
	if gold:
		# 金色描边 + 心跳（docs/142b §1 第 2 条）：同一张贴图染金、按心跳放大一圈垫在下面，轮廓跟花苞走
		var hb: float = _beat(g.t)
		var gs: Vector2 = sz2 * (1.1 + 0.06 * hb)
		g.wcv.draw_texture_rect(bul.bud_sil(), Rect2(_snap(p - Vector2(gs.x * 0.5, gs.y - 6.0 * s * 1.1)), gs), false, Color(GOLD.r * (1.0 + 0.3 * hb), GOLD.g * (1.0 + 0.3 * hb), GOLD.b * (1.0 + 0.2 * hb)))
	var c: Color = Color(0.55, 0.52, 0.62).lerp(Color.WHITE, clampf(lit, 0.0, 1.0))
	g.wcv.draw_texture_rect(tx, Rect2(_snap(p - Vector2(sz2.x * 0.5, sz2.y - 6.0 * s)), sz2), false, c)


func _anchor(w, p: Vector2, lit: float, s := 1.0) -> void:
	w.tb_poly(_anchor_shape(p, s * 1.06), OLC)
	w.tb_poly(PackedVector2Array([p + Vector2(-20, 3) * s, p + Vector2(-18, -6) * s, p + Vector2(18, -6) * s, p + Vector2(20, 3) * s]), Color(0.14, 0.15, 0.2))
	w.tb_poly(PackedVector2Array([p + Vector2(-18, -6) * s, p + Vector2(-10, -9) * s, p + Vector2(10, -9) * s, p + Vector2(18, -6) * s]), Color(0.3, 0.33, 0.42))
	w.tb_poly(PackedVector2Array([p + Vector2(-8, -7) * s, p + Vector2(-7, -36) * s, p + Vector2(0, -38) * s, p + Vector2(0, -7) * s]), Color(0.36, 0.4, 0.5))
	w.tb_poly(PackedVector2Array([p + Vector2(0, -7) * s, p + Vector2(0, -38) * s, p + Vector2(7, -36) * s, p + Vector2(8, -7) * s]), Color(0.17, 0.19, 0.26))
	if lit > 0.0:
		w.tb_line(_snap(p + Vector2(-3, -12) * s), _snap(p + Vector2(-3, -32) * s), LIL[2].lerp(LIL[3], lit), 2.0)
	var c0: Color = LIL[1].lerp(LIL[3], lit)
	var c1: Color = LIL[0].lerp(LIL[4], lit)
	w.tb_poly(PackedVector2Array([p + Vector2(0, -36) * s, p + Vector2(-6, -38) * s, p + Vector2(-12, -48) * s, p + Vector2(0, -64) * s]), c1)
	w.tb_poly(PackedVector2Array([p + Vector2(0, -36) * s, p + Vector2(0, -64) * s, p + Vector2(12, -48) * s, p + Vector2(6, -38) * s]), c0)
	if lit > 0.5:
		w.tb_line(_snap(p + Vector2(-3, -42) * s), _snap(p + Vector2(-1, -54) * s), Color(1, 1, 1), 2.0)


func _cres_ring(c: Vector2, k: int, gy: float) -> Vector2:
	var aa: float = TAU * float(k) / 6.0 + 0.3
	return c + Vector2(cos(aa), sin(aa) * gy) * 170.0


## 起光：锚桩脚下一圈淡紫光尘往外翻 + 往上溅白紫火花
func _cres_flash(p: Vector2) -> void:
	sparks(p + Vector2(0, -40), -PI * 0.5, 0.9, 8, 260.0, [Color(1, 1, 1), LIL[4], LIL[3], LIL[2]], true, 0.4)
	for i in 3:
		puffs.append([p + Vector2(rng.randf_range(-10, 10), 0), Vector2(rng.randf_range(-40, 40), -rng.randf_range(5, 20)), g.t, 0.7, 30.0, 60.0, i, 0.7, 2])


## 克雷松稳定场开着时的地面（142b §1 第 2 条「低亮度纹理 = 场地」）：圈内铺满淡紫雾纹（低亮度、低对比），
## 中心到 6 根锚桩、锚桩之间连淡紫光带，读成「一片场」；压在单位 / 弹 / 预警之下
func _cres_field(cv, now: float) -> void:
	var gy: float = g.combat.GROUND_Y
	for id in cres_list.keys():
		var e: Dictionary = cres_list[id][0]
		if e.dead:
			continue
		for d in e.get("devs", []):
			if float(d.field) <= now:
				continue
			var al: float = clampf((float(d.field) - now) / 0.5, 0.0, 1.0)
			var t0: float = float(d.get("fx_t0", now))
			var sp: float = clampf((now - t0) / 0.5, 0.0, 1.0)
			var c: Vector2 = d.pos
			var R: float = 170.0 * sp
			for i in 7:
				var an: float = float(i) * 2.399 + now * 0.12
				var q: Vector2 = c if i == 0 else c + Vector2(cos(an), sin(an) * gy) * R * 0.6
				var sz: float = R * (1.3 if i == 0 else 0.9)
				cv.draw_texture_rect(lil_puff[i % 3], Rect2(((q - Vector2(sz, sz * gy) * 0.5) / PX).floor() * PX, Vector2(sz, sz * gy)), false, Color(1, 1, 1, 0.42 * al))
			for k in 6:
				var a: Vector2 = c + (_cres_ring(c, k, gy) - c) * sp
				var b: Vector2 = c + (_cres_ring(c, (k + 1) % 6, gy) - c) * sp
				_band_tex(cv, lil_band, c, a, 26.0, 0.28 * al)   # 宽而淡，读成场地纹理不读成细线（协调人 11-26：淡紫细弧线）
				_band_tex(cv, lil_band, a, b, 28.0, 0.32 * al)
			var pulse: float = fmod(now - t0, 1.2) / 1.2
			for k in 6:
				var a2: Vector2 = c + (_cres_ring(c, k, gy) - c) * pulse * sp
				cv.draw_texture_rect(lil_puff[k % 3], Rect2(((a2 - Vector2(18, 14)) / PX).floor() * PX, Vector2(36, 28)), false, Color(1, 1, 1, 0.55 * al * (1.0 - pulse)))


func _final_ground(w, now: float) -> void:
	var cv = g.wcv
	_cres_field(cv, now)
	_fin_tex()
	var kf: Array = []
	for fr in snow_furrows:
		var agf: float = now - float(fr[2])
		if agf > 2.5:
			continue
		kf.append(fr)
		_band_tex(cv, ice_band, fr[0], fr[1], 22.0, 0.65 * (1.0 - agf / 2.5))
	snow_furrows = kf
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
		if str(t.get("skin0", t.get("skin", ""))) != "ice_lance" or not (t.get("owner") is Dictionary) or str(t.owner.get("type", "")) != "will":
			continue
		var k: float = clampf(float(t.t) / maxf(0.01, float(t.dur)), 0.0, 1.0)
		var p: Vector2 = t.pos
		if t.done:
			if not t.get("fx_hit", false):
				t["fx_hit"] = true
				_shatter("icicle", p + Vector2(0, 2), 1.0, 220.0)
				_glints(p, 6, 20.0)
				glows.append([p, g.t, 90.0])
				for j in 2:
					_icefog(p + Vector2(rng.randf_range(-10, 10), 0), Vector2(rng.randf_range(-50, 50), rng.randf_range(-12, 4)), 0.8, 34.0, 0.8)
			continue
		if k < 0.62:
			continue
		var f: float = (k - 0.62) / 0.38
		var y: float = -200.0 * (1.0 - f * f)
		var tip: Vector2 = p + Vector2(0, y)
		w.tb_flush()
		# 像素冰凌（pixgen 像素化 14×46，尖朝下）从天上坠落：上方两道残影 + 落点影子由小变大
		for gh in [2, 1]:
			_wdraw("icicle", tip + Vector2(0, -22.0 * float(gh) * f), 1.0, Color(0.8, 0.92, 1.0, 0.22 / float(gh)))
		_wdraw("icicle", tip)
		if rng.randf() < 0.35:
			_add(tip + Vector2(rng.randf_range(-8, 8), -rng.randf_range(20, 80)), Vector2(0, -40), 0.3, Color(1.3, 1.4, 1.5), 2.0, 3)
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
		var gy: float = g.combat.GROUND_Y
		for d in e.get("devs", []):
			var ready: bool = now >= float(d.cd)
			var on: bool = float(d.field) > now
			if on and float(d.get("fx_t0", -1.0)) < 0.0:
				d["fx_t0"] = now
				_cres_flash(d.pos)
				for k in 6:
					_cres_flash(_cres_ring(d.pos, k, gy))
			elif not on:
				d["fx_t0"] = -1.0
			if ready and not on and float(d.charge) < 0.0:
				d["fx_gold"] = true   # 能启动：花苞轮廓金色描边 + 心跳（_bud 里按贴图本身放大垫底）
			var lit: float = 1.0 if (ready or on) else 0.0
			if float(d.charge) > 0.0:
				lit = clampf(1.0 - (float(d.charge) - now), 0.3, 1.0)
			_bud(w, d.pos, lit, 1.0, d.get("fx_gold", false))
			d["fx_gold"] = false
			if float(d.charge) > 0.0:
				# 充能 1 秒：晶尖上方一道光柱慢慢往上长、越来越粗
				var ck: float = clampf(1.0 - (float(d.charge) - now), 0.0, 1.0)
				_pillar(cv, d.pos + Vector2(0, -80), 260.0 * ck * ck, 14.0 + 26.0 * ck, 0.5 + 0.5 * ck)
				if rng.randf() < 0.6:
					var aq: float = rng.randf() * TAU
					_add(d.pos + Vector2(cos(aq), sin(aq) * gy) * 50.0, (Vector2(0, -60) - Vector2(cos(aq), sin(aq) * gy) * 40.0), 0.6, LIL[3], 2.0, 0)
			if on:
				var left: float = float(d.field) - now
				var al: float = clampf(left / 0.5, 0.0, 1.0)
				var up: float = clampf((now - float(d.fx_t0)) / 0.35, 0.0, 1.0)
				up = 1.0 - (1.0 - up) * (1.0 - up)
				_pillar(cv, d.pos + Vector2(0, -80), 260.0 * up, 40.0, al * (0.85 + 0.15 * sin(now * 9.0)))
				for k in 6:
					var ap: Vector2 = _cres_ring(d.pos, k, gy)
					var uk: float = clampf((now - float(d.fx_t0) - 0.05 * float(k)) / 0.35, 0.0, 1.0)
					uk = 1.0 - (1.0 - uk) * (1.0 - uk)
					_bud(w, ap, al, 0.8)
					_pillar(cv, ap + Vector2(0, -64), (170.0 + 14.0 * sin(now * 5.0 + float(k))) * uk, 28.0, al * 0.9)
					if rng.randf() < 0.3 * al:
						_fog(ap, 1, 0.6, 0.0, true, 0.6, Vector2(0, -10))
				if rng.randf() < 0.7 * al:
					var bb: float = rng.randf() * TAU
					var mp: Vector2 = d.pos + Vector2(cos(bb), sin(bb) * gy) * 170.0 * sqrt(rng.randf())
					_add(mp, Vector2(rng.randf_range(-6, 6), -rng.randf_range(30, 60)), 0.8, LIL[3] if rng.randf() < 0.6 else LIL[4], 2.0, 0)
		w.tb_flush()



## ==== 结局 Boss 有体积的预警（协调人 11-25 退回：和利刃同一套——裂缝 / 渗雾 / 实物先冒头，各按自己的元素）
const SANDC := [Color(0.24, 0.16, 0.08), Color(0.45, 0.33, 0.2), Color(0.66, 0.53, 0.37), Color(0.82, 0.7, 0.52)]


func _gpoly_ring(c: Vector2, r: float, gy: float, a: float) -> Vector2:
	return c + Vector2(cos(a) * r, sin(a) * r * gy)


func _crack_col(w, a: Vector2, ang: float, L: float, k: float, sd: int, core: Color, edge: Color, wd := 3.0) -> void:
	var n: int = maxi(2, int(L / 14.0))
	var prev: Vector2 = a
	var d := Vector2.from_angle(ang)
	var nv := d.orthogonal()
	var lim: float = L * k
	for i in range(1, n + 1):
		var x: float = minf(L * float(i) / float(n), lim)
		var j: float = float(absi(hash(Vector2i(sd, i))) % 100 - 50) / 50.0 * 6.0
		var q: Vector2 = a + d * x + nv * j
		w.tb_line(_snap(prev), _snap(q), edge, wd + 2.0)
		w.tb_line(_snap(prev), _snap(q), core, maxf(1.0, wd - 1.0))
		prev = q
		if x >= lim:
			break


## 冰晶菱块（意志）
func _crystal(w, q: Vector2, s: float) -> void:
	if s < 1.0:
		return
	w.tb_poly(PackedVector2Array([q + Vector2(0, -s * 1.6 - 2), q + Vector2(s + 2, 0), q + Vector2(0, s * 0.6 + 2), q + Vector2(-s - 2, 0)]), WILLC[0])
	w.tb_poly(PackedVector2Array([q + Vector2(0, -s * 1.6), q + Vector2(s, 0), q + Vector2(0, s * 0.6), q + Vector2(-s, 0)]), WILLC[2])
	w.tb_poly(PackedVector2Array([q + Vector2(0, -s * 1.6), q + Vector2(s, 0), q]), WILLC[3])


## 刻痕（木裂）：一道斜划深槽 + 翻起的亮唇
func _gash(w, q: Vector2, ang: float, L: float) -> void:
	if L < 2.0:
		return
	var d := Vector2.from_angle(ang)
	var n := d.orthogonal()
	var a: Vector2 = q - d * L * 0.5
	var b: Vector2 = q + d * L * 0.5
	var m: Vector2 = q
	w.tb_poly(PackedVector2Array([a, m + n * 5.0, b, m - n * 5.0]), OLC)
	w.tb_poly(PackedVector2Array([a, m + n * 3.5, b, m - n * 1.0]), TEALC[1])
	w.tb_poly(PackedVector2Array([a.lerp(b, 0.15), m + n * 2.0, b.lerp(a, 0.15), m + n * 0.5]), TEALC[0])
	w.tb_line(_snap(a.lerp(b, 0.2) - n * 3.0), _snap(b.lerp(a, 0.2) - n * 3.0), TEALC[4], 2.0)


## 花瓣（克雷松）：根在 q、尖朝 ang，长 L
func _petal(w, q: Vector2, ang: float, L: float) -> void:
	if L < 2.0:
		return
	var d := Vector2.from_angle(ang)
	var n := d.orthogonal()
	var wd: float = L * 0.38
	var pts := PackedVector2Array([q, q + d * L * 0.4 + n * wd, q + d * L, q + d * L * 0.4 - n * wd])
	var big := PackedVector2Array([q - d * 2.0, q + d * L * 0.4 + n * (wd + 2.5), q + d * (L + 3.0), q + d * L * 0.4 - n * (wd + 2.5)])
	w.tb_poly(big, LIL[0])
	w.tb_poly(pts, LIL[2])
	w.tb_poly(PackedVector2Array([q + d * 2.0, q + d * L * 0.45 + n * wd * 0.45, q + d * (L - 3.0)]), LIL[3])


## 暗花瓣（克雷松场地花纹）：贴地压扁、暗紫半透（低亮度纹理，不平涂高亮），中间一道稍亮的叶脉
func _petal_dim(w, q: Vector2, ang: float, L: float, gy: float, al: float) -> void:
	if L < 4.0:
		return
	var d := Vector2(cos(ang), sin(ang) * gy)
	var n := Vector2(-sin(ang), cos(ang) * gy)
	var wd: float = L * 0.3
	w.tb_poly(PackedVector2Array([q, q + d * L * 0.45 + n * wd, q + d * L, q + d * L * 0.45 - n * wd]), Color(0.22, 0.12, 0.32, al))
	w.tb_poly(PackedVector2Array([q + d * L * 0.1, q + d * L * 0.45 + n * wd * 0.55, q + d * L * 0.9, q + d * L * 0.45 - n * wd * 0.55]), Color(0.36, 0.22, 0.5, al))
	w.tb_line(_snap(q + d * L * 0.12), _snap(q + d * L * 0.85), Color(0.55, 0.4, 0.72, al), 2.0)


## 眼纹（克雷松）：杏仁形眼眶 + 虹膜 + 瞳孔，open 0–1 = 睁开程度
func _eye(w, c: Vector2, rw: float, open: float) -> void:
	var rh: float = rw * 0.42 * open
	if rh < 1.5:
		w.tb_line(_snap(c - Vector2(rw, 0)), _snap(c + Vector2(rw, 0)), LIL[0], 4.0)
		return
	var up := PackedVector2Array()
	for i in 13:
		var u: float = float(i) / 12.0
		up.append(c + Vector2(lerpf(-rw, rw, u), -sin(u * PI) * rh))
	for i in range(11, 0, -1):
		var u2: float = float(i) / 12.0
		up.append(c + Vector2(lerpf(-rw, rw, u2), sin(u2 * PI) * rh))
	var big := PackedVector2Array()
	for q in up:
		big.append(c + (q - c) * Vector2(1.08, 1.25))
	w.tb_poly(big, LIL[0])
	w.tb_poly(up, LIL[3])
	var ir: float = minf(rh * 0.95, rw * 0.36)
	w.tb_circle(c, ir, LIL[1], 1.0, 14)
	w.tb_circle(c, ir * 0.45, Color(0.08, 0.02, 0.14), 1.0, 10)
	w.tb_quad(_snap(c + Vector2(-ir * 0.5, -ir * 0.6)), _snap(c + Vector2(-ir * 0.2, -ir * 0.6)), _snap(c + Vector2(-ir * 0.2, -ir * 0.3)), _snap(c + Vector2(-ir * 0.5, -ir * 0.3)), LIL[4])


## 沙丘 / 沙陷（哈兰）：一团沙丘（暗底 + 亮顶）
func _dune(w, q: Vector2, s: float) -> void:
	if s < 1.0:
		return
	w.tb_poly(PackedVector2Array([q + Vector2(-s * 1.6, 1), q + Vector2(-s * 0.6, -s * 0.7), q + Vector2(s * 0.7, -s * 0.6), q + Vector2(s * 1.6, 1)]), SANDC[0])
	w.tb_poly(PackedVector2Array([q + Vector2(-s * 1.2, 0), q + Vector2(-s * 0.4, -s * 0.55), q + Vector2(s * 0.5, -s * 0.45), q + Vector2(s * 1.2, 0)]), SANDC[2])
	w.tb_poly(PackedVector2Array([q + Vector2(-s * 0.4, -s * 0.55), q + Vector2(s * 0.5, -s * 0.45), q + Vector2(0, -s * 0.2)]), SANDC[3])


## 刻度（路加）：一道金黄刻线（暗褐边），沿 d 方向长 L
func _tick(w, q: Vector2, d: Vector2, L: float, wd: float) -> void:
	if L < 1.0:
		return
	w.tb_line(_snap(q - d * L * 0.5), _snap(q + d * L * 0.5), LUKA_D, wd + 2.0)
	w.tb_line(_snap(q - d * L * 0.5), _snap(q + d * L * 0.5), LUKA, wd)


func _warn_final(w, cv, t: Dictionary, k: float, sd: int, ot: String) -> void:
	if str(t.get("skin0", "")) == "vine_burrow":
		_vine_warn(w, cv, t, k, sd)   # 藤蔓根须钻地拱痕（11-28，fm_v1）
		return
	if ot.begins_with("shaman"):
		_sham_warn(w, cv, t, k, sd)   # 雪祀冰链系预警（11-28）
		return
	if ot.begins_with("vine"):
		_vine_warn2(w, cv, t, k, sd)   # 藤蔓破土 / 根线 / 熔岩口预警（11-28 新判定）
		return
	var gy: float = g.combat.GROUND_Y
	var c: Vector2 = t.pos
	match t.shape:
		"circle":
			var r: float = float(t.r)
			match ot:
				"will":
					if str(t.get("skin0", "")) == "will_pillar":
						_pillar_warn(w, cv, t, k, sd)
						return
					# 落影 + 冰雾（11-26：细裂纹读成平面矢量 → 去掉）：中间一团落影越来越浓，大圈再加圈边冰带（冰凌另画在顶层）
					if rng.randf() < 0.15 + 0.3 * k:
						_icefog(c + Vector2(rng.randf_range(-r, r) * 0.6, rng.randf_range(-r, r) * 0.3), Vector2(0, -12), 0.6, 26.0, 0.5)
					_fin_tex()
					var nn: int = clampi(int(TAU * r / 40.0), 8, 40) if r > 60.0 else 0   # 小落点（冰凌 r40、塌雪 r20…）只用冰裂纹（协调人 11-26：白细圆）
					var hk: float = PI * clampf(k * 1.3, 0.0, 1.0)
					for i in nn:
						var a0w: float = -PI * 0.5 - hk + 2.0 * hk * float(i) / float(nn)
						var a1w: float = -PI * 0.5 - hk + 2.0 * hk * float(i + 1) / float(nn)
						_band_tex(cv, ice_band, _gpoly_ring(c, r - 4.0, gy, a0w), _gpoly_ring(c, r - 4.0, gy, a1w), 10.0, 0.6 + 0.35 * k)
					var sz: float = r * 1.6 * (0.4 + 0.6 * k)
					cv.draw_texture_rect(fog_puff[sd % 4], Rect2(((c - Vector2(sz, sz * 0.6) * 0.5) / PX).floor() * PX, Vector2(sz, sz * 0.6)), false, Color(1, 1, 1, 0.25 + 0.5 * k))
				"lead":
					# 地面刻痕：圈边一道道深青斜刻痕按进度划开，圈里三道裂缝
					var nn2: int = clampi(int(TAU * r / 26.0), 6, 24)
					for i in nn2:
						var dl2: float = float(absi(hash(Vector2i(sd, i + 60))) % 45) / 100.0
						var aa: float = TAU * float(i) / float(nn2)
						var hj: int = absi(hash(Vector2i(sd, i + 90)))
						var rj: float = r * (0.92 + float(hj % 16) / 100.0)
						_gash(w, _gpoly_ring(c, rj, gy, aa + float(hj % 9 - 4) * 0.03), aa + PI * 0.5 + 0.3 + float(hj % 7) * 0.12, (16.0 + float(hj % 18)) * clampf((k - dl2) / 0.4, 0.0, 1.0))   # 长短 / 角度 / 半径都错开，不排成虚线圈
					for i in 3:
						_crack_col(w, c, TAU * float(i) / 3.0 + 0.4, r * 0.85, k, sd + i, TEALC[3], OLC, 3.0)
				"cresson":
					# 11-28 苗圃吞地：播种类落点 = 地面先发裂、往下塌（洞的张开过程就是预警，不立光柱 / 花瓣 / 眼纹）；
					# 闪现落地 r250 = 圈边几道暗裂缝往落点收 + 落点一小团地面下陷（不铺平涂圆盘）
					var nc2: int = 6 if r < 120.0 else 10
					for i in nc2:
						var ac: float = TAU * float(i) / float(nc2) + float(sd % 7) * 0.3
						var dv2 := Vector2(cos(ac), sin(ac) * gy)
						if r < 120.0:
							_crack_col(w, c, dv2.angle(), r * dv2.length() * (0.8 + 0.25 * float(i % 2)), clampf(k * 1.3, 0.0, 1.0), sd + i * 7, Color(0.3, 0.22, 0.42), A1_SH, 4.0)
						else:
							var q0: Vector2 = c + dv2 * r
							_crack_col(w, q0, (c - q0).angle(), r * dv2.length() * 0.55, k, sd + i * 7, Color(0.3, 0.22, 0.42), A1_SH, 4.0)
					var sg: float = (r if r < 120.0 else 60.0) * (0.5 + 0.5 * k)
					var sag := PackedVector2Array()
					for i in 12:
						var aa2: float = TAU * float(i) / 12.0
						sag.append(_snap(c + Vector2(cos(aa2), sin(aa2) * gy) * sg * (0.85 + 0.15 * float(absi(hash(Vector2i(sd, i))) % 10) / 10.0)))
					w.tb_polygon(sag, Color(A1_BACK, 0.25 + 0.35 * k))
					if rng.randf() < 0.3 + 0.5 * k:
						_add(c + Vector2(rng.randf_range(-sg, sg), rng.randf_range(-sg, sg) * gy) * 0.7, Vector2(0, rng.randf_range(10, 30)), 0.4, A1_LIT, 4.0, 3, 0.0)
					return
				"khan", "lion":
					# 沙雾从外往里收（协调人 11-26：敕令粉圆盘 / 路加刻度短划圈退回）：圈边一道连续沙带（路加金沙），
					# 一圈沙雾墙从圈边往圆心收拢，墙外到圈边铺满沙雾；圆心三道地裂往外爬，沙粒往里流
					_sand_close(w, cv, c, r, k, sd, ot == "lion")
		"line":
			# 沿线一条连续元素纹理带（宽 = 判定宽）往前铺到 k + 中线裂缝；两侧不再每 22 摆一个物件（读成虚线，协调人清单）
			var L: float = float(t.len)
			var hw: float = float(t.wid)
			_fin_tex()
			var btx: Texture2D = {"will": ice_band, "lead": teal_band, "cresson": lil_band, "khan": sand_band, "lion": gold_band}.get(ot, fog_band)
			var d0 := Vector2.from_angle(float(t.ang))
			var harm: bool = float(t.get("dmg", 0.0)) > 0.0
			if not (ot == "cresson" and harm):
				_band_tex(cv, btx, c, c + d0 * L * k, hw * 0.8, (0.35 + 0.4 * k) if harm else 0.3)
			if not harm:
				return   # 不伤人的出口 / 标记线：只铺一条淡纹理带，不画裂缝
			var cc: Color = {"will": WILLC[2], "lead": TEALC[3], "cresson": LIL[2], "khan": KHAN[2], "lion": LUKA}.get(ot, BLOOD[1])
			var ce: Color = {"will": WILLC[0], "lead": OLC, "cresson": LIL[0], "khan": SANDC[0], "lion": LUKA_D}.get(ot, OLC)
			if ot == "cresson":
				_rift_warn(w, t, k, sd)   # 11-28：双击 / 裂隙 = 空间被切开（暗缝撕开、品红亮边）
				return
			else:
				_crack_col(w, c, float(t.ang), L, k, sd, cc, ce, 5.0)
		"cone":
			var r3: float = float(t.r)
			var a0: float = float(t.ang) - float(t.half)
			var a1: float = float(t.ang) + float(t.half)
			var cc2: Color = {"will": WILLC[2], "lead": TEALC[3], "cresson": LIL[2], "khan": KHAN[2], "lion": LUKA}.get(ot, BLOOD[1])
			var ce2: Color = {"will": WILLC[0], "lead": OLC, "cresson": LIL[0], "khan": SANDC[0], "lion": LUKA_D}.get(ot, OLC)
			if r3 > 300.0 and (ot == "lion" or ot == "khan"):
				_fin_tex()
				_band_tex(cv, gold_band if ot == "lion" else sand_band, c, c + Vector2.from_angle(float(t.ang)) * (r3 - 8.0) * k, 14.0, 0.75)
			if ot == "cresson":
				# 11-28 无之花：扇区里地面从中心往外发裂（结算后整片被吃成洞，cres_petal_void），不画半透明花瓣
				for i in 3:
					_crack_col(w, c, lerpf(a0 + 0.05, a1 - 0.05, float(i) / 2.0), r3 * 0.95, clampf(k * 1.2, 0.0, 1.0), sd + i * 11, Color(0.5, 0.38, 0.7), A1_SH, 4.0)
				return
			var ncr: int = 0 if r3 > 300.0 and (ot == "lion" or ot == "khan") else (1 if r3 > 300.0 else 5)
			for i in ncr:
				var ai: float = float(t.ang) if ncr == 1 else lerpf(a0 + 0.08, a1 - 0.08, float(i) / 4.0)
				_crack_col(w, c, ai, r3 - 8.0, k, sd + i * 13, cc2, ce2, 5.0 if ncr == 1 else 4.0)
			# 外弧一道连续元素纹理弧带（从中间往两头长），不再一排物件（读成虚线）
			_fin_tex()
			var btx2: Texture2D = {"will": ice_band, "lead": teal_band, "cresson": lil_band, "khan": sand_band, "lion": gold_band}.get(ot, fog_band)
			var na: int = maxi(3, int((a1 - a0) * r3 / 50.0))
			var hk: float = (a1 - a0) * 0.5 * clampf(k * 1.3, 0.0, 1.0)
			var am: float = (a0 + a1) * 0.5
			for i in na:
				var q0: Vector2 = c + Vector2.from_angle(lerpf(am - hk, am + hk, float(i) / float(na))) * (r3 - 12.0)
				var q1: Vector2 = c + Vector2.from_angle(lerpf(am - hk, am + hk, float(i + 1) / float(na))) * (r3 - 12.0)
				_band_tex(cv, btx2, q0, q1, 16.0, 0.5 + 0.4 * k)
	if rng.randf() < 0.35 and ot != "lion" and ot != "khan":
		var seep: Vector2 = c + (Vector2.from_angle(float(t.get("ang", 0.0))) * float(t.get("len", 0.0)) * k * rng.randf() if t.shape == "line" else Vector2.ZERO)
		if ot == "will":
			_icefog(seep, Vector2(rng.randf_range(-20, 20), -8), 0.7, 20.0, 0.6)
		elif ot == "cresson":
			if gpuffs.size() < PUFF_MAX:
				gpuffs.append([seep, Vector2(rng.randf_range(-20, 20), -8), g.t, 0.7, 22.0, 40.0, rng.randi() % 3, 0.6, 2])
		else:
			_fog(seep, 1, 0.7, 0.0, true, 0.7)


func _sand_close(w, cv, c: Vector2, r: float, k: float, sd: int, gold: bool) -> void:
	_fin_tex()
	var gy: float = g.combat.GROUND_Y
	var band: Texture2D = gold_band if gold else sand_band
	var puff: Texture2D = gold_puff if gold else sand_puff
	var ns: int = clampi(int(TAU * r / 40.0), 12, 48)
	for i in ns:
		var q0: Vector2 = _gpoly_ring(c, r - 6.0, gy, TAU * float(i) / float(ns))
		var q1: Vector2 = _gpoly_ring(c, r - 6.0, gy, TAU * float(i + 1) / float(ns))
		_band_tex(cv, band, q0, q1, 12.0, 0.55 + 0.4 * k)
	var rw: float = r * (1.0 - 0.85 * k)   # 沙雾墙半径
	var nf: int = clampi(int(TAU * r / 36.0), 10, 40)
	for i in nf:
		var hj: int = absi(hash(Vector2i(sd, i)))
		var a: float = TAU * (float(i) + float(hj % 10) / 10.0) / float(nf)
		var rr: float = lerpf(rw, r, float((hj >> 4) % 100) / 100.0)
		var sz: float = 44.0 + float((hj >> 8) % 30)
		cv.draw_texture_rect(puff, Rect2(_snap(_gpoly_ring(c, rr, gy, a) - Vector2(sz, sz * 0.7) * 0.5), Vector2(sz, sz * 0.7)), false, Color(1, 1, 1, 0.3 + 0.3 * k))
		var sw: float = 56.0 + float((hj >> 12) % 20)
		cv.draw_texture_rect(puff, Rect2(_snap(_gpoly_ring(c, rw, gy, a) - Vector2(sw, sw * 0.7) * 0.5), Vector2(sw, sw * 0.7)), false, Color(1, 1, 1, 0.7))
	var cc: Color = LUKA if gold else KHAN[2]
	var ce: Color = LUKA_D if gold else SANDC[0]
	for i in 3:
		_crack_col(w, c, TAU * float(i) / 3.0 + 1.0 + float(sd % 5), r * 0.7 * k, 1.0, sd + i, cc, ce, 5.0)
	if rng.randf() < 0.8:
		var a6: float = rng.randf() * TAU
		var q6: Vector2 = _gpoly_ring(c, r, gy, a6)
		_add(q6, (c - q6) * 1.2, 0.6, (SANDC[rng.randi_range(1, 3)] if not gold else [LUKA, LUKA_O, SANDC[2]][rng.randi() % 3]), 3.0, 0)


## 破绽（render/break_ring 调，萨米结局 Boss）：脚下一圈连续金沙带慢呼吸 + 剩余时间那段加粗加亮（不画细描边环）
func break_ring(e: Dictionary, frac: float) -> void:
	_fin_tex()
	var cv = g.wcv
	var gy: float = g.combat.GROUND_Y
	var r: float = float(e.r) * 1.5 + 3.0 * sin(g.t * 3.0)
	var n := 24
	for i in n:
		var a0: float = -PI * 0.5 + TAU * float(i) / float(n)
		var a1: float = -PI * 0.5 + TAU * float(i + 1) / float(n)
		var lit: bool = float(i) / float(n) < frac
		_band_tex(cv, gold_band, _gpoly_ring(e.pos, r, gy, a0), _gpoly_ring(e.pos, r, gy, a1), 9.0 if lit else 6.0, 0.95 if lit else 0.35)


## 演示用沙地：米黄沙底 + 斜向黑色风沙条（原作时光之沙，实机 BV1Ds421A7E3 3615 s），128² 程序贴图按 2 倍平铺
func _draw_sand_floor(w) -> void:
	if sand_tex == null:
		var n := FastNoiseLite.new()
		n.seed = 77
		n.frequency = 0.06
		var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var a: float = TAU * float(x) / 128.0
				var b: float = TAU * float(y) / 128.0
				var v: float = n.get_noise_4d(cos(a) * 12.0, sin(a) * 12.0, cos(b) * 12.0, sin(b) * 12.0) if n.has_method("get_noise_4d") else n.get_noise_3d(cos(a) * 12.0, sin(a) * 12.0, float(y) * 0.5)
				var cc: Color = Color(0.78, 0.67, 0.52).lerp(Color(0.66, 0.55, 0.4), clampf(v * 0.8 + 0.5, 0.0, 1.0))
				var streak: float = fmod(float(x) * 0.18 + float(y), 32.0)
				var hs: int = absi(hash(Vector2i(int(x / 7), int((float(y) + float(x) * 0.18) / 32.0))))
				if streak < 1.5 and hs % 5 < 2:   # 风沙条断断续续、长短不一
					cc = Color(0.36, 0.27, 0.18)
				img.set_pixel(x, y, cc)
		sand_tex = ImageTexture.create_from_image(img)
	var vr: Rect2 = w.view_rect(16.0)
	var x0: float = floorf(vr.position.x / 256.0) * 256.0
	var y0: float = floorf(vr.position.y / 256.0) * 256.0
	var y := y0
	while y < vr.end.y:
		var x := x0
		while x < vr.end.x:
			g.wcv.draw_texture_rect(sand_tex, Rect2(x, y, 256.0, 256.0), false)
			x += 256.0
		y += 256.0



## ==== 要去碰的东西（docs/142b §1 第 2 条「金色描边 + 心跳」，docs/401 §16）：停驻点、稳定设施、银凇
var obj_list := {}
const GOLD := Color(0.957, 0.753, 0.306)


func obj_draw(e: Dictionary) -> void:
	obj_list[int(e.id)] = [e, g.t]


## 心跳：每 1.1 秒「咚咚」两下（第二下弱），描边随之加粗变亮
func _beat(now: float) -> float:
	var ph: float = fmod(now, 1.1)
	return maxf(exp(-pow(ph / 0.06, 2.0)), 0.6 * exp(-pow((ph - 0.2) / 0.06, 2.0)))


func _gold_beat(w, poly: PackedVector2Array, c: Vector2, now: float) -> void:
	var hb: float = _beat(now)
	var grow: float = 3.0 + 3.0 * hb
	var big := PackedVector2Array()
	for q in poly:
		var d: Vector2 = q - c
		big.append(c + d + d.normalized() * grow)
	w.tb_poly(big, Color(GOLD.r * (1.0 + 0.4 * hb), GOLD.g * (1.0 + 0.4 * hb), GOLD.b * (1.0 + 0.3 * hb)))


func _obj_front(w, now: float) -> void:
	for id in obj_list.keys():
		var it: Array = obj_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			obj_list.erase(id)
			continue
		# 木裂停驻点：冰石路标（暗石桩 + 冰顶）；能点亮时金色描边 + 心跳，冷却中暗下去
		var ai: int = 0
		var sc = g.bai.boss(e.type)
		if sc != null and sc.has_method("act_i"):
			ai = sc.act_i(e)
		for st in e.get("stops", []):
			if st.gone:
				continue
			var on: bool = now >= float(st.next) and (ai == 0 or float(st.lit) > now)
			var p: Vector2 = st.pos
			var body := PackedVector2Array([p + Vector2(-10, 2), p + Vector2(-8, -20), p + Vector2(-3, -30), p + Vector2(4, -28), p + Vector2(9, -18), p + Vector2(10, 2)])
			if on:
				_gold_beat(w, body, p + Vector2(0, -14), now)
			var big := PackedVector2Array()
			for q in body:
				big.append(p + Vector2(0, -14) + (q - p - Vector2(0, -14)) * 1.12)
			w.tb_poly(big, OLC)
			w.tb_poly(body, Color(0.22, 0.26, 0.32) if on else Color(0.16, 0.18, 0.22))
			w.tb_poly(PackedVector2Array([p + Vector2(-8, -20), p + Vector2(-3, -30), p + Vector2(4, -28), p + Vector2(2, -22)]), WILLC[2] if on else WILLC[1])
		# 意志银凇（用户 11-26：程序三角松是占位 → pixgen 出图像素化 23×42，同萨米地图景物画风）：完好时金色描边 + 心跳
		for t in e.get("trees", []):
			if float(t.dead_t) > 0.0:
				continue
			_rime_tree(w, t.pos, now, int(t.hits) > 0)
	w.tb_flush()


	w.tb_flush()


func _will_lightpass(w, cv, now: float) -> void:
	if sfx_flat:
		return
	for id in fin_list.keys():
		var e: Dictionary = fin_list[id][0]
		if e.dead or str(e.type) != "will":
			continue
		for t in e.get("trees", []):
			if float(t.dead_t) <= 0.0:
				_ground_shadow(t.pos + Vector2(4, 2), 22.0)
		for o in e.get("obst", []):
			if float(o.r) <= 18.0 and o.has("fx_t0"):
				_ground_shadow(o.pos + Vector2(5, 3), 11.0 * clampf((now - float(o.fx_t0)) / 0.15, 0.0, 1.0))
	for t in g.warns:
		if t.done or str(t.get("skin0", t.get("skin", ""))) != "ice_lance":
			continue
		var k: float = clampf(float(t.t) / maxf(0.01, float(t.dur)), 0.0, 1.0)
		if k >= 0.62:
			var f: float = (k - 0.62) / 0.38
			_ground_shadow(t.pos + Vector2(2, 2), 3.0 + 7.0 * f, 0.4 + 0.6 * f)   # 冰凌越落越近，影子越实越大
	for d in shards:
		var q: Vector2 = _shard_pos(d, now)
		_ground_shadow(Vector2(q.x + 2, float(d[6]) + 2), 3.5, 0.7)
	_bullet_glows(cv)


func _shard_pos(d: Array, now: float) -> Vector2:
	var ta: float = minf(now - float(d[3]), float(d[4]))
	var q: Vector2 = d[1] + d[2] * ta + Vector2(0, 0.5 * 900.0 * ta * ta)
	if q.y > float(d[6]):
		q.y = float(d[6])
	return q


## ---- 意志的像素贴图（themes/sami/fx/will/，pixgen 出图 + 像素化，docs/401 §21）：银凇、冰凌，各带 Voronoi 碎块
var wtex := {}
var wsil := {}
var wchunks := {}
var shards: Array = []   # 碎块 [贴图, 位置, 速度, 出生 t, 寿命, 转速, 落地 y, 缩放]


## 打光（用户 11-27：新东西没有打光和阴影，和画面割裂）：贴图用重打光版 *_lit（左上主光、深冷色描边、背光面冷暗），
## 立在地上的东西画接地影子（同干员 / 怪物的 shadow 贴图与比例），子弹在雪地上投一小团冷色柔光。--sfx_flat = 旧画法（对照用）
var sfx_flat: bool = (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--sfx_flat")


func _wt(nm: String) -> Texture2D:
	var key: String = nm if sfx_flat else nm + "_lit"
	if not wtex.has(key):
		wtex[key] = load("res://themes/sami/fx/will/%s.png" % key)
	return wtex[key]


## 接地影子：同 world._draw_shadows（shadow 贴图，缩放 = PX × 半宽 / 10）
func _ground_shadow(p: Vector2, half_w: float, al := 1.0) -> void:
	if sfx_flat:
		return
	var stx: Texture2D = g.tex.get("shadow")
	if stx == null:
		return
	var sz: Vector2 = stx.get_size() * PX * half_w / 10.0
	g.wcv.draw_texture_rect(stx, Rect2((p - sz * 0.5).round(), sz), false, Color(1, 1, 1, al))


## 子弹照地冷光：一团柔边径向光（无硬边、无环），低亮度，只照弹下一小圈
var cold_glow: Texture2D


func _glow_tex() -> Texture2D:
	if cold_glow == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for j in n:
			for i in n:
				var d: float = Vector2(float(i) + 0.5 - n * 0.5, float(j) + 0.5 - n * 0.5).length() / (n * 0.5)
				var a: float = clampf(1.0 - d, 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
				img.set_pixel(i, j, Color(1, 1, 1, a))
		cold_glow = ImageTexture.create_from_image(img)
	return cold_glow


func _bullet_glows(cv) -> void:
	if sfx_flat:
		return
	var tx: Texture2D = _glow_tex()
	for b in g.ebullets:
		if b.life <= 0.0 or str(b.get("src_type", "")) != "will" or not b.get("mc", false):
			continue
		var sz := Vector2(60, 36)
		cv.draw_texture_rect(tx, Rect2((b.pos + Vector2(0, 2) - sz * 0.5).round(), sz), false, Color(0.7, 0.88, 1.0, 0.22))


func _wsil(nm: String) -> ImageTexture:
	if not wsil.has(nm):
		var img: Image = _wt(nm).get_image()
		img.decompress()
		for j in img.get_height():
			for i in img.get_width():
				img.set_pixel(i, j, Color.WHITE if img.get_pixel(i, j).a > 0.5 else Color(0, 0, 0, 0))
		wsil[nm] = ImageTexture.create_from_image(img)
	return wsil[nm]


func _wchunks(nm: String) -> Dictionary:
	if not wchunks.has(nm):
		var f := FileAccess.open("res://themes/sami/fx/will/%s_chunks.json" % nm, FileAccess.READ)
		wchunks[nm] = JSON.parse_string(f.get_as_text()) if f != null else {"tree": [1, 1], "chunks": []}
	return wchunks[nm]


## 贴图以「脚底中心」对齐 base 画（PX 倍 × s）；flip = 上下翻（冰桩尖朝上）
func _wdraw(nm: String, base: Vector2, s := 1.0, col := Color.WHITE, sil := false) -> void:
	var tx: Texture2D = _wsil(nm) if sil else _wt(nm)
	var sz := Vector2(tx.get_width(), tx.get_height()) * PX * s
	g.wcv.draw_texture_rect(tx, Rect2(_snap(base - Vector2(sz.x * 0.5, sz.y - 2.0 * s)), sz), false, col)


func _rime_tree(w, tp: Vector2, now: float, cracked: bool) -> void:
	w.tb_flush()
	var hb: float = _beat(now)
	var gs: float = 1.08 + 0.05 * hb
	_wdraw("rime_tree", tp + Vector2(0, 2.0 * gs), gs, Color(GOLD.r * (1.0 + 0.3 * hb), GOLD.g * (1.0 + 0.3 * hb), GOLD.b * (1.0 + 0.2 * hb)), true)
	_wdraw("rime_tree_cracked" if cracked else "rime_tree", tp)


## 整体碎成 Voronoi 碎块：每块带重力往外翻滚飞，落到脚底高度停住、0.4 秒淡掉
func _shatter(nm: String, base: Vector2, s: float, power: float) -> void:
	if nm == "icicle":
		_ice_bits(base + Vector2(0, -14.0 * s), int(10.0 * s) + 4, power / 220.0)   # 冰凌碎块贴图在 A1 雪上缩小读成暗点（协调人退回），全换浅冰色碎屑
		return
	var meta: Dictionary = _wchunks(nm)
	var TW: float = float(meta.tree[0])
	var TH: float = float(meta.tree[1])
	var c0: Vector2 = Vector2(TW * 0.5, TH * 0.55)
	for c in meta.chunks:
		var tx: Texture2D = _wt(str(c.file).get_basename())
		var mid := Vector2(float(c.x) + tx.get_width() * 0.5, float(c.y) + tx.get_height() * 0.5)
		var wp: Vector2 = base + (mid - Vector2(TW * 0.5, TH)) * PX * s
		var dv: Vector2 = (mid - c0).normalized() if mid.distance_to(c0) > 0.5 else Vector2.UP
		var v: Vector2 = Vector2(dv.x * 1.2, dv.y * 0.7 - 0.6) * power * rng.randf_range(0.7, 1.2)
		if shards.size() > 260:
			shards.pop_front()
		shards.append([tx, wp, v, g.t, rng.randf_range(0.7, 1.0), rng.randf_range(-7.0, 7.0), base.y + rng.randf_range(-4, 10), s])


func _draw_shards(w, now: float) -> void:
	if shards.is_empty():
		return
	w.tb_flush()
	var cv = g.wcv
	var keep: Array = []
	for d in shards:
		var age: float = now - float(d[3])
		var life: float = float(d[4])
		if age > life + 0.4:
			continue
		keep.append(d)
		var ta: float = minf(age, life)
		var q: Vector2 = d[1] + d[2] * ta + Vector2(0, 0.5 * 900.0 * ta * ta)
		var landed: bool = q.y >= float(d[6])
		if landed:
			q.y = float(d[6])
		var rot: float = 0.0 if landed else float(d[5]) * ta
		var al: float = clampf((life + 0.4 - age) / 0.4, 0.0, 1.0)
		var tx: Texture2D = d[0]
		var sz := Vector2(tx.get_width(), tx.get_height()) * PX * float(d[7])
		cv.draw_set_transform(_snap(q), rot, Vector2.ONE)
		cv.draw_texture_rect(tx, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, al))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	shards = keep


## 落地短促光照：一团冰白柔光 0.15 秒（Noita 式照地，不是圆盘：柔边贴图、很快淡）
var glows: Array = []


func _draw_glows(now: float) -> void:
	var keep: Array = []
	for gl in glows:
		var age: float = now - float(gl[1])
		if age > 0.18:
			continue
		keep.append(gl)
		var k: float = 1.0 - age / 0.18
		var sz: float = float(gl[2]) * (0.8 + 0.4 * (1.0 - k))
		g.wcv.draw_texture_rect(ice_puff[0], Rect2(_snap(gl[0] - Vector2(sz, sz * 0.6) * 0.5), Vector2(sz, sz * 0.6)), false, Color(1, 1, 1, 0.75 * k))
	glows = keep


## 亮点闪烁（Noita）：1–2 格冰白亮点，随机闪
func _glints(p: Vector2, n: int, r: float) -> void:
	for i in n:
		var a: float = rng.randf_range(PI * 0.9, PI * 1.6) if not sfx_flat else rng.randf() * TAU   # 亮点朝光（左上）
		_add(p + Vector2(cos(a), sin(a) * 0.6) * rng.randf_range(0.0, r), Vector2(cos(a), sin(a) * 0.5) * rng.randf_range(20.0, 90.0) + Vector2(0, -rng.randf_range(10, 60)), rng.randf_range(0.3, 0.7), Color(1.4, 1.5, 1.6), 2.0, 3, 120.0)


## ==== 结局四 Boss 11-26 新招（docs/393 §11.5–11.8 / §13，ee004b14c）：场上物件、专属弹体、结算爆点（docs/401 §18）
## 各 Boss 的 draw() 调 final_draw(e) 登记；地面层画场地 / 冰面 / 河道，顶层画物件 / 骑影 / 爆点。判定都不动
var fin_list := {}
var spikes: Array = []       # 结算爆点 [位置, 出生 t, 高, 宽, 色组(暗边, 本体, 亮面), 倾角]
var runners: Array = []      # 骑影 / 兽亲冲过 [种类, 起点, 方向角, 长, 出生 t, 时长]
const SP_MAX := 320
var ice_band: Texture2D
var sand_band: Texture2D
var sand_puff: Texture2D
var snow_puff: Texture2D
var gold_band: Texture2D
var gold_puff: Texture2D
const PAL := {
	"will": [Color(0.12, 0.16, 0.28), Color(0.6, 0.74, 0.92), Color(1.0, 1.0, 1.0)],
	"lead": [Color(0.02, 0.06, 0.05), Color(0.1, 0.44, 0.31), Color(0.55, 0.85, 0.72)],
	"cresson": [Color(0.3, 0.16, 0.45), Color(0.7, 0.46, 0.95), Color(0.95, 0.88, 1.0)],
	"khan": [Color(0.24, 0.16, 0.08), Color(0.66, 0.53, 0.37), Color(0.9, 0.8, 0.62)],
	"lion": [Color(0.3, 0.2, 0.08), Color(1.0, 0.62, 0.15), Color(1.0, 1.0, 0.75)],
	"shaman": [Color(0.094, 0.11, 0.44), Color(0.28, 0.32, 0.87), Color(0.82, 0.85, 1.0)],
	"shaman2": [Color(0.094, 0.11, 0.44), Color(0.28, 0.32, 0.87), Color(0.82, 0.85, 1.0)],
	"vine": [Color(0.13, 0.085, 0.06), Color(0.3, 0.2, 0.13), Color(0.45, 0.31, 0.2)],
	"vine2": [Color(0.13, 0.085, 0.06), Color(0.3, 0.2, 0.13), Color(0.45, 0.31, 0.2)],
}


func final_draw(e: Dictionary) -> void:
	if not fin_list.has(int(e.id)):
		bul.warm(str(e.type))
	fin_list[int(e.id)] = [e, g.t]


func _fin_tex() -> void:
	if ice_band == null:
		ice_band = _fog_tex(128, 32, 1901, false, Color(0.55, 0.72, 0.88), Color(0.86, 0.95, 1.0))
		sand_band = _fog_tex(128, 32, 1951, false, Color(0.5, 0.38, 0.22), Color(0.8, 0.68, 0.5))
		sand_puff = _fog_tex(32, 32, 1971, true, Color(0.42, 0.3, 0.16), Color(0.22, 0.14, 0.07))
		snow_puff = _fog_tex(32, 32, 1981, true, Color(0.62, 0.66, 0.8), Color(0.97, 0.98, 1.0))
		gold_band = _fog_tex(128, 32, 1991, false, Color(0.62, 0.42, 0.12), Color(1.0, 0.85, 0.35))
		gold_puff = _fog_tex(32, 32, 1993, true, Color(0.7, 0.5, 0.18), Color(0.98, 0.82, 0.4))


## 爆点：从地上猛地顶出一根元素尖刺（0.08 秒顶到全高，停 0.15，0.25 秒缩回），暗边 + 本体 + 受光面
func _spike(p: Vector2, h: float, wd: float, ot: String, lean := 0.0) -> void:
	if spikes.size() >= SP_MAX:
		spikes.pop_front()
	spikes.append([p, g.t, h, wd, PAL.get(ot, PAL.will), lean])


func _draw_spikes(w, now: float) -> void:
	var keep: Array = []
	for s in spikes:
		var age: float = now - float(s[1])
		if age > 0.48 or age < 0.0:
			continue
		keep.append(s)
		var k: float = clampf(age / 0.08, 0.0, 1.0)
		k = 1.0 - (1.0 - k) * (1.0 - k)
		if age > 0.23:
			k *= clampf(1.0 - (age - 0.23) / 0.25, 0.0, 1.0)
		var h: float = float(s[2]) * k
		if h < 2.0:
			continue
		var p: Vector2 = s[0]
		var hw: float = float(s[3]) * 0.5
		var pal: Array = s[4]
		var tip: Vector2 = p + Vector2(float(s[5]) * h, -h)
		w.tb_poly(PackedVector2Array([p + Vector2(-hw - 2.5, 1.5), tip + Vector2(0, -3), p + Vector2(hw + 2.5, 1.5)]), pal[0])
		w.tb_poly(PackedVector2Array([p + Vector2(-hw, 0), tip, p + Vector2(hw, 0)]), pal[1])
		w.tb_poly(PackedVector2Array([p + Vector2(hw * 0.1, 0), tip, p + Vector2(hw, 0)]), pal[2])
	spikes = keep


## 预警结算爆点（各 Boss 通用，按元素）：圈 = 圈里一圈 + 中心尖刺；线 = 沿线每 34 一根；扇 = 沿外弧 + 中间一排
func _warn_burst(t: Dictionary, ot: String) -> void:
	var c: Vector2 = t.pos
	if ot == "cresson" and t.shape == "circle" and absf(float(t.r) - 250.0) < 1.0:
		cres_implode(c, float(t.r))   # 克雷松闪现落地内爆（11-28，fm_c4）
		return
	if ot.begins_with("shaman"):
		_sham_wburst(t)
		return
	if ot.begins_with("vine"):
		_vine_wburst(t)
		return
	if ot == "cresson" and t.shape == "line":
		cres_rift(t)   # 双击 / 裂隙：空间被切开
		return
	if ot == "cresson" and t.shape == "cone":
		cres_petal_void(c, float(t.ang), float(t.half), float(t.r))   # 无之花：扇区被吃成洞
		return
	var gy: float = g.combat.GROUND_Y
	var pal: Array = PAL.get(ot, PAL.will)
	if ot == "will":
		_will_burst(t)   # 意志：像素冰凌碎块 + 冰雾 + 亮点（用户 11-26：平面矢量尖刺 → pixelfx 主形 + Noita 粒子）
		return
	match t.shape:
		"circle":
			var r: float = float(t.r)
			var n: int = clampi(int(r / 12.0), 4, 18)
			for i in n:
				var a: float = TAU * float(i) / float(n) + float(i % 3) * 0.2
				var rr: float = r * (0.45 + 0.4 * float((i * 7) % 5) / 4.0)
				_spike(c + Vector2(cos(a), sin(a) * gy) * rr, clampf(r * 0.5, 34.0, 60.0) * (0.7 + 0.3 * float(i % 3) / 2.0), clampf(r * 0.16, 14.0, 20.0), ot, cos(a) * 0.25)
			_spike(c, clampf(r * 0.75, 44.0, 76.0), clampf(r * 0.24, 18.0, 26.0), ot)
			sparks(c + Vector2(0, -16), -PI * 0.5, 1.4, clampi(int(r / 6.0), 6, 18), 300.0, [pal[2], pal[1], pal[1], pal[0]], true, 0.32)
		"line":
			var d := Vector2.from_angle(float(t.ang))
			var L: float = float(t.len)
			var hw: float = float(t.wid)
			var x := 20.0
			var i := 0
			while x < L:
				var off: float = (float((i * 5) % 3) - 1.0) * hw * 0.4
				_spike(c + d * x + d.orthogonal() * off, clampf(hw * 1.6, 22.0, 52.0), clampf(hw * 0.7, 10.0, 22.0), ot, d.x * 0.3)
				x += 34.0
				i += 1
			sparks(c + d * L * 0.5, float(t.ang), 0.6, 10, 260.0, [pal[2], pal[1], pal[1], pal[0]], true, 0.3)
		"cone":
			var r3: float = float(t.r)
			var a0: float = float(t.ang) - float(t.half)
			var a1: float = float(t.ang) + float(t.half)
			var inner: float = float(t.get("inner_r", 0.0))
			var n3: int = 2 if (ot == "khan" or ot == "lion") else clampi(int((a1 - a0) * r3 / 30.0), 3, 16)
			if ot == "khan" or ot == "lion":
				for i in 9:
					var as0: float = lerpf(a0, a1, float(i) / 8.0)
					if gpuffs.size() < PUFF_MAX:
						gpuffs.append([c + Vector2.from_angle(as0) * r3 * 0.9, Vector2.from_angle(as0) * 60.0 + Vector2(0, -10), g.t, 0.7, 40.0, 70.0, rng.randi() % 4, 0.55, 0])
					embers(c + Vector2.from_angle(as0) * r3 * 0.9, 2, SANDC[2], 120.0, 260.0, 0.5, 4.0)
			for i in n3 + 1:
				var aa: float = lerpf(a0, a1, float(i) / float(n3))
				_spike(c + Vector2.from_angle(aa) * r3 * 0.92, 34.0, 14.0, ot, cos(aa) * 0.3)
				if inner <= 0.0 and i % 2 == 0:
					_spike(c + Vector2.from_angle(aa) * r3 * 0.55, 26.0, 12.0, ot, cos(aa) * 0.3)
			sparks(c + Vector2.from_angle(float(t.ang)) * r3 * 0.7, float(t.ang), 0.8, 12, 280.0, [pal[2], pal[1], pal[1], pal[0]], true, 0.3)
	match ot:
		"will":
			_icefog(c, Vector2(0, -10), 0.7, 34.0, 0.7)
		"cresson":
			if gpuffs.size() < PUFF_MAX:
				gpuffs.append([c, Vector2(0, -10), g.t, 0.7, 30.0, 60.0, rng.randi() % 3, 0.7, 2])
		"khan", "lion":
			embers(c, 6, SANDC[2], 140.0, 280.0, 0.5, 4.0)
		_:
			_fog(c, 2, 0.6, 0.0, true, 0.8)


func _will_burst(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	var gy: float = g.combat.GROUND_Y
	var pts: Array = []
	match t.shape:
		"circle":
			var r: float = float(t.r)
			if r <= 30.0:
				return   # 冰凌林 / 小落点：冰桩自己从地里顶出，不再另爆
			pts.append(c)
			var n: int = clampi(int(r / 60.0), 0, 6)
			for i in n:
				var a: float = TAU * float(i) / float(maxi(n, 1)) + 0.4
				pts.append(c + Vector2(cos(a), sin(a) * gy) * r * 0.6)
		"line":
			var d := Vector2.from_angle(float(t.ang))
			var x := 30.0
			while x < float(t.len) and pts.size() < 8:
				pts.append(c + d * x)
				x += 70.0
		"cone":
			for i in 4:
				pts.append(c + Vector2.from_angle(lerpf(float(t.ang) - float(t.half), float(t.ang) + float(t.half), (float(i) + 0.5) / 4.0)) * float(t.r) * 0.8)
	for q in pts:
		_shatter("icicle", q, 0.7, 180.0)
		_glints(q, 3, 16.0)
		_icefog(q, Vector2(rng.randf_range(-30, 30), -10), 0.7, 40.0, 0.75)
	if not pts.is_empty():
		glows.append([pts[0], g.t, 120.0])


## 骑影 / 兽亲：可汗片影 = 暗红骑影（马身 + 骑者 + 长鬃旗，拖沙尘）；王者友伴 = 金橙兽影（伏身扑击）
func _runner_pose(w, kind: String, p: Vector2, d: Vector2, k: float, al: float) -> void:
	var fx: float = signf(d.x) if absf(d.x) > 0.1 else 1.0
	var bob: float = sin(k * 40.0) * 2.0
	if kind == "rider":
		var c: Vector2 = p + Vector2(0, -22 + bob)
		var o := PackedVector2Array([c + Vector2(-30 * fx, 4), c + Vector2(-22 * fx, -10), c + Vector2(10 * fx, -12), c + Vector2(26 * fx, -24), c + Vector2(34 * fx, -18), c + Vector2(28 * fx, -6),
			c + Vector2(18 * fx, 2), c + Vector2(20 * fx, 22), c + Vector2(12 * fx, 22), c + Vector2(6 * fx, 6), c + Vector2(-14 * fx, 6), c + Vector2(-18 * fx, 22), c + Vector2(-26 * fx, 22)])
		var big := PackedVector2Array()
		for q in o:
			big.append(c + (q - c) * 1.1)
		w.tb_poly(big, Color(0.06, 0.0, 0.0, al))
		w.tb_poly(o, Color(KHAN[1], al))
		w.tb_poly(PackedVector2Array([c + Vector2(-10 * fx, -10), c + Vector2(-4 * fx, -40), c + Vector2(6 * fx, -40), c + Vector2(8 * fx, -12)]), Color(KHAN[0], al))   # 骑者
		w.tb_poly(PackedVector2Array([c + Vector2(-2 * fx, -40), c + Vector2(-26 * fx, -54 + bob), c + Vector2(-30 * fx, -44 + bob)]), Color(KHAN[2], al))   # 长鬃旗
		w.tb_line(_snap(c + Vector2(-20 * fx, -8)), _snap(c + Vector2(24 * fx, -18)), Color(KHAN[3], al), 2.0)
	else:
		var c2: Vector2 = p + Vector2(0, -16 + bob * 0.5)
		var o2 := PackedVector2Array([c2 + Vector2(-26 * fx, 2), c2 + Vector2(-18 * fx, -10), c2 + Vector2(8 * fx, -12), c2 + Vector2(18 * fx, -22), c2 + Vector2(30 * fx, -14), c2 + Vector2(26 * fx, -2),
			c2 + Vector2(16 * fx, 14), c2 + Vector2(6 * fx, 6), c2 + Vector2(-12 * fx, 8), c2 + Vector2(-24 * fx, 14)])
		var big2 := PackedVector2Array()
		for q in o2:
			big2.append(c2 + (q - c2) * 1.12)
		w.tb_poly(big2, Color(LUKA_D, al))
		w.tb_poly(o2, Color(LUKA_O, al))
		w.tb_poly(PackedVector2Array([c2 + Vector2(10 * fx, -12), c2 + Vector2(18 * fx, -22), c2 + Vector2(30 * fx, -14), c2 + Vector2(20 * fx, -8)]), Color(LUKA, al))   # 鬃
		w.tb_line(_snap(c2 + Vector2(-26 * fx, 2)), _snap(c2 + Vector2(-38 * fx, -6)), Color(LUKA_O, al), 4.0)   # 尾


func _draw_runners(w, now: float) -> void:
	var keep: Array = []
	for r in runners:
		var age: float = now - float(r[4])
		var dur: float = float(r[5])
		if age > dur + 0.25:
			continue
		keep.append(r)
		if age < 0.0:
			continue
		var k: float = clampf(age / dur, 0.0, 1.0)
		var d := Vector2.from_angle(float(r[2]))
		var p: Vector2 = (r[1] as Vector2) + d * float(r[3]) * k
		var al: float = clampf(age / 0.08, 0.0, 1.0) * clampf((dur + 0.25 - age) / 0.25, 0.0, 1.0)
		for gh in [2, 1]:
			_runner_pose(w, str(r[0]), p - d * 26.0 * float(gh), d, k, al * (0.35 - 0.1 * float(gh)))
		_runner_pose(w, str(r[0]), p, d, k, al)
		if rng.randf() < 0.7:
			embers(p + Vector2(0, -2), 1, SANDC[rng.randi_range(1, 2)], 90.0, 200.0, 0.45, 4.0)
			if gpuffs.size() < PUFF_MAX and rng.randf() < 0.5:
				gpuffs.append([p - d * 20.0, -d * 40.0 + Vector2(0, -6), now, 0.6, 24.0, 44.0, rng.randi() % 4, 0.45, 0])
	runners = keep


## 结局 Boss 专属弹体（意志 雪晶 / 木裂 冰屑 / 克雷松 花瓣）：可见直径 ≥24，暗边 + 本体 + 亮芯，在亮雪地、沙地上都读得出
func _fin_bullet(cv, b: Dictionary, kind: String, now: float) -> void:
	var v: Vector2 = b.vel
	var a: float = v.angle() if v.length_squared() > 1.0 else float(b.get("ang", 0.0))
	var d := Vector2.from_angle(a)
	var n := d.orthogonal()
	var bp: Vector2 = b.pos + Vector2(0, -16)
	match kind:
		"wbul":
			# 雪晶：六角冰晶星（冰白 + 暗紫边 + 白芯），慢转
			# 雪晶（协调人 11-26 退回：亮雪地上看不见）：深蓝灰描边 + 白芯圆 + 冰蓝六芒线，可见直径 ≥28
			var R: float = 12.0
			var rot: float = now * 1.6 + float(int(b.get("id", 0)) % 7)
			cv.draw_circle(bp, R + 3.0, Color(0.12, 0.16, 0.28))
			cv.draw_circle(bp, R, Color(1, 1, 1))
			for i in 3:
				var dv: Vector2 = Vector2.from_angle(rot + PI * float(i) / 3.0) * (R - 2.0)
				cv.draw_line(bp - dv, bp + dv, Color(0.45, 0.62, 0.9), 2.0)
		"tbul":
			# 冰屑：沿飞行方向的深青冰片（暗边 + 深青 + 冰白高光），身后一截冰雾尾
			var L: float = 17.0
			var W: float = 10.0
			cv.draw_polygon(PackedVector2Array([bp + n * W * 0.7, bp - d * 34.0, bp - n * W * 0.7]), PackedColorArray([Color(TEALC[3], 0.6), Color(TEALC[3], 0.0), Color(TEALC[3], 0.6)]))
			cv.draw_colored_polygon(PackedVector2Array([bp + d * (L + 3.0), bp + n * (W + 3.0), bp - d * (L * 0.7 + 3.0), bp - n * (W + 3.0)]), OLC)
			cv.draw_colored_polygon(PackedVector2Array([bp + d * L, bp + n * W, bp - d * L * 0.7, bp - n * W]), TEALC[3])
			cv.draw_colored_polygon(PackedVector2Array([bp + d * L, bp + n * W, bp + d * L * 0.1]), TEALC[4])
			cv.draw_line(bp - d * L * 0.3, bp + d * (L - 4.0), Color(0.9, 1.0, 0.96), 2.0)
		"pbul":
			# 花瓣：一片淡紫花瓣边飞边翻（宽度随翻转缩放），暗紫边 + 淡紫 + 白尖
			var rot2: float = now * 7.0 + float(int(b.get("id", 0)) % 9)
			var pd: Vector2 = Vector2.from_angle(a + 0.6 * sin(rot2 * 0.5))
			var pn: Vector2 = pd.orthogonal() * maxf(0.35, absf(cos(rot2)))
			var Lp: float = 15.0
			var Wp: float = 9.0
			var body := PackedVector2Array([bp + pd * Lp, bp + pn * Wp + pd * 2.0, bp - pd * Lp, bp - pn * Wp + pd * 2.0])
			var ed := PackedVector2Array()
			for q in body:
				ed.append(bp + (q - bp) * 1.25)
			cv.draw_colored_polygon(ed, LIL[0])
			cv.draw_colored_polygon(body, LIL[2])
			cv.draw_colored_polygon(PackedVector2Array([bp + pd * Lp, bp + pn * Wp * 0.5 + pd * 4.0, bp + pd * 2.0]), LIL[4])
			if now - float(b.get("sfx_tt", -9.0)) > 0.08:
				b["sfx_tt"] = now
				_add(bp, -v * 0.1 + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15)), 0.35, LIL[3], 2.0, 0)


## 地面层：冰面 / 冻原 / 河道 / 沙河 / 沙痕 / 苗圃标记 / 花墓 / 场地标记
func _fin_ground(w, cv, now: float) -> void:
	_fin_tex()
	_will_lightpass(w, cv, now)
	_draw_wcracks(w, cv, now)
	_cimp_ground(cv, w, now)
	for it in cres_list.values():
		if not it[0].dead:
			_band_draw(w, cv, it[0], now, g.combat.GROUND_Y)   # 苗圃环（回荡新判定）
	_cvoids_draw(w, cv, now, g.combat.GROUND_Y)
	_vine_ground(w, cv, now)
	_crifts_draw(w, cv, now)
	_sham_ground(cv, now)
	_vtrench_draw(w, cv, now)
	var gy: float = g.combat.GROUND_Y
	for id in fin_list.keys():
		var it: Array = fin_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			continue
		match str(e.type):
			"will":
				var bz0 = e.get("blizz")
				if bz0 is Dictionary and e.has("blizz_y") and now >= float(bz0.t0):
					_will_storm_ground(w, cv, e, bz0, float(e.blizz_y), now)   # 暴风雪：压暗 + 横向飞雪条纹（11-28）
				_will_curtain_ground(w, cv, e, now)   # 三幕北侧雪幕
				var tu = e.get("tundra")
				if tu is Dictionary and now >= float(tu.t0):
					# 冻原：意志脚下的冻结地面往南推（冰面 = 低亮度冰蓝纹理；推进前沿另画在顶层）
					var y: float = float(tu.y0) + (now - float(tu.t0)) * float(tu.spd)
					var cx: float = e.pos.x
					var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
					var yy: float = float(tu.y0)
					while yy < y:
						_band_tex(cv, ice_band, Vector2(cx - ar, yy), Vector2(cx + ar, yy), 18.0, 0.45)
						yy += 30.0
				var rv = e.get("river")
				if rv is Dictionary:
					var pts: Array = rv.pts
					var al: float = clampf((now - (float(rv.t0) - 1.2)) / 0.6, 0.0, 1.0) * clampf((float(rv.until) + 0.5 - now) / 0.5, 0.0, 1.0)
					for i in pts.size() - 1:
						_band_tex(cv, ice_band, pts[i], pts[i + 1], 40.0, 0.7 * al)
				for t in e.get("trees", []):
					if float(t.dead_t) > 0.0:
						# 银凇原址：地上一团冰白微光（叹息段安全列就是这些遗址）
						var q: Vector2 = t.orig
						cv.draw_texture_rect(ice_puff[0], Rect2(_snap(q - Vector2(30, 18)), Vector2(60, 36)), false, Color(1, 1, 1, 0.55 + 0.2 * sin(now * 3.0)))
			"lead":
				for x in e.get("ice", []):
					# 冻土冰面（减速 = 场地，低亮度冰纹）：不规则冰片 + 几道裂纹，到期 0.4 秒淡掉
					var al2: float = clampf((float(x.until) - now) / 0.4, 0.0, 1.0)
					var r: float = float(x.r)
					var sd: int = absi(hash(Vector2i(int(x.pos.x), int(x.pos.y)))) % 997
					var pts2 := PackedVector2Array()
					for i in 12:
						var aa: float = TAU * float(i) / 12.0
						var jr: float = 0.82 + float(absi(hash(Vector2i(sd, i))) % 30) / 100.0
						pts2.append(x.pos + Vector2(cos(aa), sin(aa) * gy) * r * jr)
					w.tb_poly(pts2, Color(0.42, 0.62, 0.72, 0.42 * al2))
					var inner := PackedVector2Array()
					for q2 in pts2:
						inner.append(x.pos + (q2 - x.pos) * 0.7 + Vector2(0, -3))
					w.tb_poly(inner, Color(0.6, 0.8, 0.86, 0.38 * al2))
					for i in 3:
						_crack_col(w, x.pos, TAU * float(i) / 3.0 + float(sd % 5), r * 0.8, 1.0, sd + i, Color(0.9, 1.0, 1.0, al2), Color(0.2, 0.4, 0.5, al2), 2.0)
			"cresson":
				# 检查点：地上一枚淡紫四瓣符印（低亮度）
				for p in e.get("cps", []):
					for k in 4:
						var ap: float = PI * 0.5 * float(k) + PI * 0.25
						var q3: Vector2 = p + Vector2(cos(ap), sin(ap) * gy) * 10.0
						w.tb_poly(PackedVector2Array([p, q3 + Vector2(cos(ap - 0.6), sin(ap - 0.6) * gy) * 8.0, p + Vector2(cos(ap), sin(ap) * gy) * 22.0, q3 + Vector2(cos(ap + 0.6), sin(ap + 0.6) * gy) * 8.0]), Color(LIL[1], 0.35))
				var tb = e.get("tomb")
				if tb is Dictionary:
					# 花墓：r180 一片淡紫花海（低亮度），中间巨花另画在顶层
					for i in 7:
						var an: float = float(i) * 2.399 + now * 0.1
						var qn: Vector2 = tb.pos + (Vector2.ZERO if i == 0 else Vector2(cos(an), sin(an) * gy) * 100.0)
						var sz: float = 150.0 if i == 0 else 110.0
						cv.draw_texture_rect(lil_puff[i % 3], Rect2(_snap(qn - Vector2(sz, sz * gy) * 0.5), Vector2(sz, sz * gy)), false, Color(1, 1, 1, 0.35))
			"khan":
				var cc = g.get_meta("twin_ctl") if g.has_meta("twin_ctl") else null
				var rv2 = cc.get("river", {}) if cc is Dictionary else {}
				if rv2 is Dictionary and not rv2.is_empty() and now <= float(rv2.until) + 0.5:
					# 流沙河：两王之间一条弯曲沙河（流动的沙纹贴图 + 往下游走的沙粒）
					var al3: float = clampf((now - (float(rv2.t0) - 1.0)) / 0.6, 0.0, 1.0) * clampf((float(rv2.until) + 0.5 - now) / 0.5, 0.0, 1.0)
					var pts3: Array = rv2.pts
					for i in pts3.size() - 1:
						_band_tex(cv, sand_band, pts3[i], pts3[i + 1], 50.0, 0.8 * al3)
					if rng.randf() < 0.9 * al3:
						var si: int = rng.randi() % (pts3.size() - 1)
						var dd: Vector2 = ((pts3[si + 1] as Vector2) - (pts3[si] as Vector2))
						_add((pts3[si] as Vector2).lerp(pts3[si + 1], rng.randf()) + dd.orthogonal().normalized() * rng.randf_range(-40, 40), dd.normalized() * 120.0, 0.8, SANDC[rng.randi_range(0, 2)], 2.0, 0)
		var tr = e.get("trail")
		if tr is Dictionary:
			# 瞬身沙痕：下陷的暗沙带 + 两侧翻起的沙唇
			var al4: float = clampf((float(tr.until) - now) / 0.4, 0.0, 1.0)
			_band_tex(cv, sand_band, tr.a, tr.b, 26.0, 0.9 * al4)
			var dv: Vector2 = ((tr.b as Vector2) - (tr.a as Vector2))
			var L4: float = dv.length()
			if L4 > 1.0:
				var nv: Vector2 = dv.orthogonal() / L4
				var x := 12.0
				while x < L4:
					for sg in [-1.0, 1.0]:
						_dune(w, (tr.a as Vector2) + dv / L4 * x + nv * 30.0 * sg, 6.0 * al4)
					x += 26.0


## 顶层：物件 / 前沿 / 骑影 / 爆点
func _fin_front(w, cv, now: float) -> void:
	var gy: float = g.combat.GROUND_Y
	# 预警结算爆点（ice_lance 冰凌另有坠冰；不伤人的出口 / 标记线不爆）
	for t in g.warns:
		if not t.done or t.get("fx_burst", false) or str(t.get("skin", "")) != "sami_blade":
			continue
		t["fx_burst"] = true
		var ow = t.get("owner")
		if not (ow is Dictionary):
			continue
		var ot: String = str(ow.get("type", ""))
		if str(t.get("skin0", "")) == "vine_burrow":
			_vine_burst(t)
			continue
		if not PAL.has(ot) or str(t.get("skin0", "")) in ["ice_lance", "will_pillar"] or float(t.get("dmg", 0.0)) <= 0.0:
			continue
		_warn_burst(t, ot)
	for id in fin_list.keys():
		var it: Array = fin_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			fin_list.erase(id)
			continue
		# 障碍：冰凌林冰桩（r≤18）/ 冰峰（意志）/ 长冬冰柱（木裂）——从地里顶出 0.15 秒、到期碎掉
		for o in e.get("obst", []):
			if str(o.get("kind", "")) == "pillar":
				_will_pillar(w, o, now)
				continue
			if not o.has("fx_t0"):
				o["fx_t0"] = now
				for i in 3:
					_icefog(o.pos + Vector2(rng.randf_range(-12, 12), 0), Vector2(rng.randf_range(-30, 30), -10), 0.6, 26.0, 0.7)
				sparks(o.pos + Vector2(0, -20), -PI * 0.5, 1.0, 8, 260.0, [WILLC[3], WILLC[2], ICEL[2], WILLC[0]], true, 0.3)
			var up: float = clampf((now - float(o.fx_t0)) / 0.15, 0.0, 1.0)
			var left: float = float(o.until) - now
			if left < 0.12 and not o.get("fx_brk", false):
				o["fx_brk"] = true
				embers(o.pos + Vector2(0, -20), 8, ICEL[1], 150.0, 300.0, 0.5, 5.0)
				embers(o.pos + Vector2(0, -20), 4, ICEL[3], 120.0, 300.0, 0.5, 5.0)
			var r: float = float(o.r)
			if r <= 18.0:
				_icicle_stake(w, o.pos, up)
				if left < 0.12 and not o.get("fx_shat", false):
					o["fx_shat"] = true
					_shatter("icicle", o.pos, 1.0, 160.0)
			elif str(e.type) == "lead":
				_ice_pillar(w, o.pos, 86.0 * up, r * 1.6)
			else:
				_ice_peak(w, o.pos, 64.0 * up, r * 2.2)
		match str(e.type):
			"will":
				_will_quake(w, cv, e, now)
				_will_wave(w, cv, e, now)            # 雪浪积雪墙（11-28）
				_will_curtain_front(w, cv, e, now)   # 北侧雪幕边界
				var tu = e.get("tundra")
				if tu is Dictionary and now >= float(tu.t0):
					# 冻原前沿：一整排冰晶从地里顶出往南推，银凇阴影里断开（出口），前沿冒冰雾
					var y: float = float(tu.y0) + (now - float(tu.t0)) * float(tu.spd)
					var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
					var x: float = e.pos.x - ar
					var idx := 0
					while x <= e.pos.x + ar:
						var shade := false
						for t2 in e.get("trees", []):
							if float(t2.dead_t) <= 0.0 and absf(x - (t2.pos as Vector2).x) < 46.0 and y > (t2.pos as Vector2).y:
								shade = true
						if not shade:
							_crystal(w, Vector2(x, y + float(idx % 2) * 6.0), 9.0 + 3.0 * float(idx % 3))
							if rng.randf() < 0.05:
								_icefog(Vector2(x, y), Vector2(0, 20), 0.6, 26.0, 0.6)
						x += 20.0
						idx += 1
				var bz = e.get("blizz")
				if bz is Dictionary and e.has("blizz_y") and now >= float(bz.t0):
					_blizzard(w, cv, e, bz, float(e.blizz_y), now)
				var rv = e.get("river")
				if rv is Dictionary:
					for b in rv.blocks:
						if b.has("pos"):
							_ice_chunk(w, b.pos, (b.pos as Vector2).y - 8.0, 18.0, float(b.s) * 0.7, 1.0)
							if rng.randf() < 0.15:
								_icefog(b.pos, Vector2(0, -8), 0.5, 22.0, 0.6)
				var br = e.get("breath")
				if br is Dictionary and now >= float(br.t0) and now < float(br.t0) + 3.0:
					# 寒息：白雾锥从北往南慢慢张大（雾团顺着锥飘出去，锥边冒雪粒）
					var kb: float = (now - float(br.t0)) / 3.0
					var half: float = deg_to_rad(lerpf(30.0, 50.0, kb))
					for i in 3:
						var aa: float = float(br.a) + rng.randf_range(-half, half)
						_icefog(e.pos + Vector2.from_angle(aa) * rng.randf_range(40.0, 140.0), Vector2.from_angle(aa) * rng.randf_range(160.0, 220.0), 2.0, 40.0, 0.55)
					_add(e.pos + Vector2.from_angle(float(br.a) + rng.randf_range(-half, half)) * 60.0, Vector2.from_angle(float(br.a)) * 240.0, 1.6, WILLC[2], 4.0, 0)
				var so: String = str(e.get("surge_op", ""))
				if so != "":
					var op = g.squad.get_op(so)
					if op != null and op.pos != Vector2.INF:
						_ice_shell(w, op.pos, now)
			"lead":
				var wi = e.get("winter")
				if wi is Dictionary and wi.has("r"):
					_winter_front(w, wi, now)
				var pl = e.get("pull")
				if pl is Dictionary:
					for p in pl.pts:
						_collapse_hole(w, cv, p, now - float(pl.t0), float(pl.t1) - float(pl.t0))
				if float(e.get("helm_until", 0.0)) > now:
					for i in 5:
						var aa2: float = now * 2.0 + TAU * float(i) / 5.0
						var q4: Vector2 = e.pos + Vector2(cos(aa2) * 26.0, -70.0 + sin(aa2) * 8.0)
						w.tb_poly(PackedVector2Array([q4 + Vector2(0, -10), q4 + Vector2(5, 0), q4 + Vector2(0, 6), q4 + Vector2(-5, 0)]), OLC)
						w.tb_poly(PackedVector2Array([q4 + Vector2(0, -8), q4 + Vector2(3, 0), q4 + Vector2(0, 4), q4 + Vector2(-3, 0)]), TEALC[4])
			"cresson":
				var j = e.get("jump")
				if j is Dictionary:
					var kj: float = (now - float(j.t0) - 0.4) / 0.5
					if kj < 0.0 and rng.randf() < 0.5:
						_add(e.pos + Vector2(rng.randf_range(-20, 20), 0), Vector2(0, -90), 0.5, LIL[3], 2.0, 0)   # 起跳前脚下花粉往上冒
					if kj >= 0.0 and kj <= 1.0:
						if gpuffs.size() < PUFF_MAX:
							puffs.append([e.pos + Vector2(0, -float(e.get("air_h", 0.0)) - 20.0), Vector2(0, 10), now, 0.6, 26.0, 46.0, rng.randi() % 3, 0.6, 2])
						var sh: float = 18.0 + 16.0 * kj
						w.tb_flush()
						cv.draw_set_transform(j.to, 0.0, Vector2(1.0, 0.4))
						cv.draw_circle(Vector2.ZERO, sh, Color(0.12, 0.05, 0.2, 0.45))
						cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				for f in e.get("flowers", []):
					_flower(w, f.pos, 1.0, now, float(f.cd) - now)
				var sc = e.get("scissor")
				if sc is Dictionary and sc.has("half"):
					for s in [-1.0, 1.0]:
						_shear(w, sc.pivot, float(sc.a0) + s * float(sc.half), 640.0)
					w.tb_circle(sc.pivot, 12.0, OLC, 1.0, 12)
					w.tb_circle(sc.pivot, 9.0, LIL[3], 1.0, 12)
					w.tb_circle(sc.pivot, 4.0, LIL[4], 1.0, 8)
				var hx = e.get("hex")
				if hx is Dictionary:
					for r2 in hx.runners:
						if r2.has("pos"):
							for k in 3:
								var aa3: float = now * 5.0 + TAU * float(k) / 3.0
								_petal(w, r2.pos + Vector2(0, -12), aa3, 18.0)
							if rng.randf() < 0.5:
								_add(r2.pos + Vector2(0, -12), Vector2(rng.randf_range(-30, 30), -30), 0.5, LIL[3], 2.0, 0)
				var tb = e.get("tomb")
				if tb is Dictionary:
					_flower(w, tb.pos, 2.4, now, float(tb.get("next", 0.0)) - now)
			"khan":
				# 西营马鬃旗（哈兰）与东营刻度石（路加）：双王营地的标志物
				var sc0 = g.bai.boss(e.type)
				if sc0 != null and sc0.has_method("center"):
					var cp: Vector2 = sc0.center(e)
					_standard(w, cp + Vector2(-380.0, 0.0), now)
					_scale_stone(w, cp + Vector2(380.0, 0.0))
			"lion":
				var sd = e.get("sundial")
				if sd is Dictionary and sd.has("a"):
					_sundial(w, cv, sd, now)
				var hg = e.get("hourglass")
				if hg is Dictionary:
					_hourglass(w, hg, now)
		var ar2 = e.get("armies")
		if ar2 is Dictionary and now < float(ar2.t1) + 0.3:
			var k2: float = clampf((now - float(ar2.t0)) / 1.0, 0.0, 1.0)
			var cp2: Vector2 = e.get("fx_c", e.pos)
			if g.bai.boss(e.type) != null and g.bai.boss(e.type).has_method("center"):
				cp2 = g.bai.boss(e.type).center(e)
			for i in 6:
				var yy: float = cp2.y - 300.0 + 120.0 * float(i)
				_runner_pose(w, "rider", Vector2(lerpf(cp2.x - 600.0, float(ar2.x) - 20.0, k2), yy), Vector2.RIGHT, now, 1.0)
				_runner_pose(w, "beast", Vector2(lerpf(cp2.x + 600.0, float(ar2.x) + 20.0, k2), yy + 10.0), Vector2.LEFT, now, 1.0)
	_draw_runners(w, now)
	_draw_spikes(w, now)
	_draw_shards(w, now)
	_cimp_front(w, now)
	_sham_front(w, now)
	_vroots_draw(w, now)
	_vine_front(w, now)
	_draw_glows(now)
	_frozen_front(w)
	w.tb_flush()


## ---- 意志「震落」（docs/392 §18，82480c2e8）：银凇被击碎 → 意志被震下山滑到碎树北边跪 8 秒（冰甲裂开、受伤 ×2.2、每 1.2 秒甩一圈冰甲碎片）→ 滑回北边；
## 平时本体外一层冰壳（读成「现在打不动」）。全部纯画面
var ice_debris: Array = []   # 碎冰块 [p0, v, t0, 寿命, 尺寸, 转速]


func _will_quake(w, cv, e: Dictionary, now: float) -> void:
	# 银凇被击碎：整棵树炸成大块碎冰往外飞（带重力、翻滚、落地停住）+ 树上积雪塌下一团冰雾 + 冰白火花
	for t in e.get("trees", []):
		var dt0: float = float(t.dead_t)
		if dt0 > 0.0 and float(t.get("fx_dead", -1.0)) != dt0:
			t["fx_dead"] = dt0
			var tp: Vector2 = t.pos
			_shatter("rime_tree", tp, 1.0, 300.0)   # 银凇贴图按 Voronoi 碎块炸开（pixgen 像素贴图，docs/401 §21）
			_glints(tp + Vector2(0, -40), 10, 40.0)
			glows.append([tp + Vector2(0, -30), now, 140.0])
			for i in 6:
				_icefog(tp + Vector2(rng.randf_range(-30, 30), -rng.randf_range(0, 60)), Vector2(rng.randf_range(-70, 70), -rng.randf_range(10, 50)), 1.0, 88.0, 0.9)
			white_flash.append([tp + Vector2(0, -40), now])
			sparks(tp + Vector2(0, -30), -PI * 0.5, 1.6, 16, 360.0, [Color.WHITE, WILLC[3], ICEL[1], Color(0.45, 0.62, 0.9)], true, 0.4)
	var keep: Array = []
	for d in ice_debris:
		var age: float = now - float(d[2])
		if age >= float(d[3]) + 0.4:
			continue
		keep.append(d)
		var ta: float = minf(age, float(d[3]))
		var q: Vector2 = d[0] + d[1] * ta + Vector2(0, 0.5 * 700.0 * ta * ta)
		var gy0: float = (d[0] as Vector2).y + 40.0
		if q.y > gy0:
			q.y = gy0
		var al: float = clampf((float(d[3]) + 0.4 - age) / 0.4, 0.0, 1.0)
		_ice_chunk(w, q, q.y, float(d[4]), float(d[5]) * ta, al)
	ice_debris = keep
	_draw_white_flash(w, now)
	var home_y: float = e.pos.y
	var kneel: bool = float(e.get("kneel_until", 0.0)) > now
	var kp = e.get("kneel_pos")
	# 滑行（震下山 / 滑回）：本体在动就在身后犁出一道雪沟 + 雪雾往两侧翻、雪粒往后溅
	var last: Vector2 = e.get("fx_qp", e.pos)
	e["fx_qp"] = e.pos
	var mv: Vector2 = e.pos - last
	if mv.length() > 3.0:
		var dv: Vector2 = mv.normalized()
		if trails.size() > 60:
			trails.pop_front()
		for k in 2:
			var nside: Vector2 = dv.orthogonal() * (10.0 if k == 0 else -10.0)
			_icefog(e.pos - dv * 30.0 + nside, -dv * 60.0 + nside * 4.0 + Vector2(0, -10), 0.7, 36.0, 0.8)
		_add(e.pos - dv * 20.0 + Vector2(rng.randf_range(-12, 12), 0), -dv * 140.0 + Vector2(rng.randf_range(-40, 40), -rng.randf_range(40, 100)), 0.5, WILLC[3], 3.0, 0, 300.0)
		snow_furrows.append([last, e.pos, now])
	# 平时冰甲 / 跪地破甲：本体外一层冰壳（多面冰晶、白棱高光），平时完整读成「打不动」；
	# 跪地时冰壳裂成几块往外歪、裂缝发白，块间露出本体（受伤 ×2.2），8 秒里碎块慢慢掉光
	var vuln: bool = float(e.get("tree_vuln", 0.0)) > now
	var c: Vector2 = e.pos + Vector2(0, -float(e.r) * 1.35)   # 意志本体帧条约 160×110（e.r 40），冰壳要罩住整只
	var R: float = float(e.r) * 2.4
	var gyk := 0.85
	var n := 8
	if not vuln:
		var pts := PackedVector2Array()
		for i in n:
			var a: float = TAU * float(i) / float(n) + 0.2
			pts.append(c + Vector2(cos(a), sin(a) * gyk) * R * (1.0 if i % 2 == 0 else 0.9))
		w.tb_flush()
		cv.draw_colored_polygon(pts, Color(0.72, 0.86, 1.0, 0.24))
		for i in n:
			var a0: Vector2 = pts[i]
			var a1: Vector2 = pts[(i + 1) % n]
			w.tb_line(_snap(a0), _snap(a1), Color(0.14, 0.2, 0.34, 0.9), 6.0)
			w.tb_line(_snap(a0), _snap(a1), Color(0.86, 0.95, 1.0, 0.95), 3.0)
			if i % 2 == 0:
				w.tb_line(_snap(a0), _snap(c + (a0 - c) * 0.35), Color(0.86, 0.95, 1.0, 0.35), 2.0)   # 冰面棱线
		var gl: float = fmod(now * 0.7, 1.0)
		var gp: Vector2 = pts[int(gl * float(n)) % n].lerp(pts[(int(gl * float(n)) + 1) % n], fmod(gl * float(n), 1.0))
		w.tb_poly(PackedVector2Array([gp + Vector2(0, -6), gp + Vector2(2, 0), gp + Vector2(0, 6), gp + Vector2(-2, 0)]), Color.WHITE)   # 沿冰壳绕行的一点白闪
		w.tb_poly(PackedVector2Array([gp + Vector2(-6, 0), gp + Vector2(0, -2), gp + Vector2(6, 0), gp + Vector2(0, 2)]), Color.WHITE)
	elif kneel:
		var left: float = float(e.kneel_until) - now
		var shown: int = clampi(int(ceil(left / 8.0 * float(n - 4))), 0, n - 4)   # 破甲瞬间先崩 4 块，剩下的按剩余时间掉
		# 金色描边 + 心跳（docs/142b §1.2「要去打的目标」）：剩余时间越少描边越暗、心跳越快
		var hb: float = _beat(now * (1.0 + (8.0 - left) / 8.0))
		var gk: float = 0.55 + 0.45 * clampf(left / 8.0, 0.0, 1.0)
		e["sfx_rim"] = Color(GOLD.r * (1.4 + 1.2 * hb) * gk, GOLD.g * (1.4 + 1.2 * hb) * gk, GOLD.b * (1.3 + 0.8 * hb) * gk, 0.9)
		if not e.get("fx_crack", false):
			e["fx_crack"] = true
			e["fx_shown"] = n - 4
			for i in range(n - 4, n):
				var ai2: float = TAU * (float(i) + 0.5) / float(n) + 0.2
				ice_debris.append([c + Vector2(cos(ai2), sin(ai2) * gyk) * R, Vector2(cos(ai2), sin(ai2)) * rng.randf_range(160.0, 260.0) + Vector2(0, -120), now, 0.9, 16.0, rng.randf_range(-7.0, 7.0)])
			sparks(c, -PI * 0.5, PI, 18, 300.0, [Color.WHITE, ICEL[0], ICEL[2], Color(0.45, 0.62, 0.9)], true, 0.4)
			for i in 6:
				_icefog(c + Vector2.from_angle(TAU * float(i) / 6.0) * R * 0.7, Vector2.from_angle(TAU * float(i) / 6.0) * 60.0, 0.7, 34.0, 0.8)
		for i in shown:
			var a0: float = TAU * float(i) / float(n) + 0.2
			var a1: float = TAU * float(i + 1) / float(n) + 0.2
			var push: Vector2 = Vector2(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5) * gyk) * (8.0 + 4.0 * sin(now * 3.0 + float(i)))
			var q0: Vector2 = c + push + Vector2(cos(a0), sin(a0) * gyk) * R
			var q1: Vector2 = c + push + Vector2(cos(a1), sin(a1) * gyk) * R
			var q2: Vector2 = c + push + Vector2(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5) * gyk) * R * 0.62
			w.tb_poly(PackedVector2Array([q0, q1, q2]), Color(0.7, 0.84, 0.98, 0.55))
			w.tb_line(_snap(q0), _snap(q1), Color(0.14, 0.2, 0.34, 0.9), 4.0)
			w.tb_line(_snap(q0), _snap(q1), Color(0.86, 0.95, 1.0), 2.0)
			w.tb_line(_snap(q0), _snap(q2), Color(1, 1, 1, 0.9), 2.0)   # 发白的裂缝
		if e.get("fx_shown", n) != shown:
			if shown < int(e.get("fx_shown", n)):
				var ai: float = TAU * (float(shown) + 0.5) / float(n) + 0.2
				ice_debris.append([c + Vector2(cos(ai), sin(ai) * gyk) * R, Vector2(cos(ai), sin(ai)) * 120.0 + Vector2(0, -80), now, 0.7, 10.0, 6.0])
			e["fx_shown"] = shown
	else:
		e["fx_crack"] = false
		e["fx_shown"] = n
	if not kneel:
		e.erase("sfx_rim")
	if kneel and kp is Dictionary:
		pass


var snow_furrows: Array = []   # 意志滑行犁出的雪沟 [a, b, t0]（地面层）
var white_flash: Array = []    # 银凇碎裂的短促冰白闪 [位置, t0]（0.15 秒四芒星 + 白圆）


func _draw_white_flash(w, now: float) -> void:
	var keep: Array = []
	for f in white_flash:
		var age: float = now - float(f[1])
		if age > 0.15:
			continue
		keep.append(f)
		var k: float = 1.0 - age / 0.15
		var p: Vector2 = f[0]
		var L: float = 70.0 * (0.6 + 0.4 * k)
		w.tb_circle(p, 26.0 * k + 6.0, Color(1, 1, 1, 0.85 * k), 1.0, 16)
		w.tb_poly(PackedVector2Array([p + Vector2(0, -L), p + Vector2(6, 0), p + Vector2(0, L), p + Vector2(-6, 0)]), Color(1, 1, 1, k))
		w.tb_poly(PackedVector2Array([p + Vector2(-L, 0), p + Vector2(0, -6), p + Vector2(L, 0), p + Vector2(0, 6)]), Color(1, 1, 1, k))
	white_flash = keep


## 冰凌林冰桩：像素冰凌上下翻（尖朝上）插在地里，按 up 从地里顶出（只露出尖那一段），脚下一圈碎雪
func _icicle_stake(w, p: Vector2, up: float) -> void:
	w.tb_flush()
	var tx: Texture2D = _wt("icicle")
	var TW: float = float(tx.get_width())
	var TH: float = float(tx.get_height())
	var vis: float = clampf(up, 0.0, 1.0) * TH * 0.85
	if vis < 1.0:
		return
	var src := Rect2(0, TH - vis, TW, vis)   # 贴图下段 = 尖
	var dst := Rect2(_snap(p - Vector2(TW * PX * 0.5, -2.0)), Vector2(TW * PX, -vis * PX))   # 高度取负 = 上下翻，尖朝上
	g.wcv.draw_texture_rect_region(tx, dst, src)
	w.tb_quad(_snap(p + Vector2(-16, 0)), _snap(p + Vector2(16, 0)), _snap(p + Vector2(12, 5)), _snap(p + Vector2(-12, 5)), Color(0.82, 0.9, 1.0, 0.85 if sfx_flat else 0.4))   # 打光版雪堆压淡，让接地影子透出来


func _ice_stake(w, p: Vector2, h: float, wd: float) -> void:
	if h < 2.0:
		return
	var hw: float = wd * 0.5
	w.tb_poly(PackedVector2Array([p + Vector2(-hw - 3, 2), p + Vector2(-hw * 0.6 - 2, -h * 0.7), p + Vector2(0, -h - 4), p + Vector2(hw * 0.6 + 2, -h * 0.7), p + Vector2(hw + 3, 2)]), Color(0.12, 0.16, 0.28))
	w.tb_poly(PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(-hw * 0.6, -h * 0.7), p + Vector2(0, -h), p + Vector2(0, 0)]), Color(0.5, 0.64, 0.86))
	w.tb_poly(PackedVector2Array([p, p + Vector2(0, -h), p + Vector2(hw * 0.6, -h * 0.7), p + Vector2(hw, 0)]), WILLC[2])
	w.tb_line(_snap(p + Vector2(2, -6)), _snap(p + Vector2(1, -h * 0.8)), WILLC[3], 2.0)


## ==== 意志「冰柱破土」（11-28 用户：每只 Boss 一种主表现，概念图 fm_w4）：冰面裂纹从意志往队长分叉推进，
## 冰柱沿裂纹依次顶出、雪块飞溅；还没顶出的那段 = 发光隆起的裂缝（就是预警）。判定照旧挂在「冰峰」（r40 / 0.9 秒 / 障碍 3 秒）
const A1_OL := Color(0.173, 0.227, 0.298)     # 深冷描边 #2C3A4C（docs/396 §14.1）
const A1_SH := Color(0.118, 0.204, 0.275)     # 接地影 / 裂缝深槽 #1E3446
const A1_LIT := Color(0.902, 0.949, 0.973)    # 积雪受光 #E6F2F8
const A1_MID := Color(0.569, 0.702, 0.761)    # 雪面中间调 #91B3C2
const A1_BACK := Color(0.369, 0.525, 0.635)   # 背光冷面 #5E86A2
const CRK_HOT := Color(0.86, 0.97, 1.0)       # 裂缝里透出的冰光（未顶出段）
const CRK_COOL := Color(0.3, 0.46, 0.6)       # 顶出后裂缝冷下来
var wcracks: Array = []      # {pts, cum, br, t0, n, step, until}
var ptex := {}


func will_crack(a: Vector2, b: Vector2, n: int, step: float, hold: float, lead := 1.0, wk := 1.0) -> void:
	var d: Vector2 = b - a
	var L: float = d.length()
	if L < 10.0:
		return
	var u: Vector2 = d / L
	var nv: Vector2 = u.orthogonal()
	var pts := PackedVector2Array([a])
	var cum: Array = [0.0]
	var x := 0.0
	var off := 0.0
	while x < L:
		x = minf(L, x + rng.randf_range(18.0, 30.0))
		off = clampf(off + rng.randf_range(-12.0, 12.0), -24.0, 24.0)
		if x >= L:
			off *= 0.3
		var q: Vector2 = a + u * x + nv * off
		cum.append(float(cum.back()) + q.distance_to(pts[pts.size() - 1]))
		pts.append(q)
	# 分叉：沿主裂缝每隔一段往两侧斜出一道（2–4 段折线），偶尔再分一次
	var br: Array = []
	var i := 2
	while i < pts.size() - 1:
		var sg: float = 1.0 if rng.randf() < 0.5 else -1.0
		for rep in (2 if rng.randf() < 0.3 else 1):
			var ang: float = u.angle() + sg * rng.randf_range(0.5, 1.1)
			var bp := PackedVector2Array([pts[i]])
			var segs: int = rng.randi_range(2, 4)
			for j in segs:
				ang += rng.randf_range(-0.35, 0.35)
				bp.append(bp[bp.size() - 1] + Vector2.from_angle(ang) * rng.randf_range(18.0, 30.0))
			br.append([float(cum[i]), bp])
			sg = -sg
		i += rng.randi_range(2, 4)
	wcracks.append({"pts": pts, "cum": cum, "br": br, "t0": g.t, "n": n, "step": step, "L": float(cum.back()), "until": g.t + step * float(n) + hold, "lead": lead, "wk": wk})


func _crack_seg(w, a: Vector2, b: Vector2, core: Color, wd: float, al: float) -> void:
	w.tb_line(_snap(a), _snap(b), Color(A1_SH, 0.92 * al), wd + 6.0)
	w.tb_line(_snap(a + Vector2(2, 0.5 * wd + 3.0)), _snap(b + Vector2(2, 0.5 * wd + 3.0)), Color(A1_LIT, 0.9 * al), 4.0)   # 背光侧槽壁受光（光从左上来，照亮裂缝的右下壁）
	w.tb_line(_snap(a), _snap(b), Color(core, al), maxf(4.0, wd - 4.0))


func _draw_wcracks(w, cv, now: float) -> void:
	if wcracks.is_empty():
		return
	var gt: Texture2D = _glow_tex()
	var keep: Array = []
	for c in wcracks:
		if now > float(c.until):
			continue
		keep.append(c)
		var age: float = now - float(c.t0)
		var step: float = float(c.step)
		var n: int = int(c.n)
		var L: float = float(c.L)
		var al: float = clampf((float(c.until) - now) / 0.6, 0.0, 1.0)
		var lead: float = float(c.get("lead", 1.0))
		var f: float = clampf((age + step * lead) / (step * float(n)), 0.0, 1.0) * (clampf(age / 0.15, 0.0, 1.0) if lead > 0.0 else 1.0)
		var head: float = f * L
		var pts: PackedVector2Array = c.pts
		var cum: Array = c.cum
		var seg_len: float = L / float(n)
		var hp: Vector2 = pts[0]
		for i in range(1, pts.size()):
			var x0: float = float(cum[i - 1])
			if x0 >= head:
				break
			var x1: float = float(cum[i])
			var b: Vector2 = pts[i]
			if x1 > head:
				b = pts[i - 1].lerp(pts[i], (head - x0) / maxf(0.01, x1 - x0))
			# 这一段对应第几根冰柱：顶出前发冰光（越靠近顶出越亮），顶出后冷下来
			var kk: int = clampi(int(x1 / seg_len), 0, n - 1)
			var erupt: float = step * float(kk) + 0.9
			var hot: float = clampf(1.0 - (age - erupt) / 0.4, 0.0, 1.0)
			var pulse: float = 0.85 + 0.15 * sin(now * 14.0 + x1 * 0.05)
			var core: Color = CRK_COOL.lerp(CRK_HOT, hot * pulse)
			var wd: float = (16.0 if x1 < head - 40.0 else 11.0) * float(c.get("wk", 1.0))
			_crack_seg(w, pts[i - 1], b, core, wd, al)
			if hot > 0.3 and i % 3 == 0:
				cv.draw_texture_rect(gt, Rect2(((b - Vector2(50, 28)) / PX).floor() * PX, Vector2(100, 56)), false, Color(0.75, 0.92, 1.0, 0.3 * hot * al))
			hp = b
		for bb in c.br:
			var s0: float = float(bb[0])
			if s0 >= head:
				continue
			var bp: PackedVector2Array = bb[1]
			var grow: float = clampf((head - s0) / 60.0, 0.0, 1.0)
			var kk2: int = clampi(int(s0 / seg_len), 0, n - 1)
			var hot2: float = clampf(1.0 - (age - step * float(kk2) - 0.9) / 0.4, 0.0, 1.0)
			var nseg: float = float(bp.size() - 1) * grow
			for j in range(1, bp.size()):
				if float(j - 1) >= nseg:
					break
				var e2: Vector2 = bp[j] if float(j) <= nseg else bp[j - 1].lerp(bp[j], nseg - float(j - 1))
				_crack_seg(w, bp[j - 1], e2, CRK_COOL.lerp(CRK_HOT, hot2 * 0.8), 6.0 if j > 1 else 9.0, al)
		# 裂缝前端：一团冰光照在雪上 + 往前蹦的冰屑
		if f < 1.0:
			cv.draw_texture_rect(gt, Rect2(((hp - Vector2(80, 45)) / PX).floor() * PX, Vector2(160, 90)), false, Color(0.75, 0.92, 1.0, 0.5))
			if rng.randf() < 0.7:
				_add(hp + Vector2(rng.randf_range(-6, 6), 0), Vector2(rng.randf_range(-50, 50), -rng.randf_range(60, 140)), 0.45, A1_LIT if rng.randf() < 0.6 else ICEL[1], 8.0, 3, 600.0)
	wcracks = keep
	w.tb_flush()


## 冰屑：浅冰色方块（白 / 浅青 / 中蓝），往上往外飞、带重力落地（碎块贴图在 A1 雪上缩小后读成暗点，不用）
func _ice_bits(p: Vector2, n: int, power: float) -> void:
	var cols := [Color.WHITE, Color(0.84, 0.93, 0.98), Color(0.59, 0.84, 0.95), Color(0.25, 0.59, 0.81)]
	for i in n:
		var a: float = rng.randf_range(-PI, 0.0)
		var sp: float = rng.randf_range(120.0, 340.0) * power
		_add(p + Vector2(rng.randf_range(-20, 20), rng.randf_range(-30, 10)), Vector2(cos(a) * sp, sin(a) * sp * 0.8 - 80.0 * power), rng.randf_range(0.5, 0.8), cols[i % 4], rng.randf_range(6.0, 12.0), 3, 1000.0)


func _ptex2(v: int, li: int) -> Texture2D:
	var nm: String = "pillar2_%d_%d" % [v, li]
	if not ptex.has(nm):
		ptex[nm] = load("res://themes/sami/fx/will/%s.png" % nm)
	return ptex[nm]


func _pvar(p: Vector2) -> int:
	return absi(hash(Vector2i(int(p.x), int(p.y)))) % 2


## 冰柱簇 v2（静态对照 11-28 过审）：一大簇 + 小晶、三档明暗 + 白热棱、顶上压雪、根部翻土碎冰；2 种高度 × 5 档斜度，
## 按裂纹走向挑斜度（ang = 这一节裂纹的方向），ps = 支干小一档；贴图从地里往上顶：只露出上段 vis（底边贴地，贴图底下 8 格在地面以下）
func _pillar_draw(p: Vector2, ang: float, ps: float, vis_k: float, ys := 1.0, jit := 0.0, col := Color.WHITE) -> void:
	var li: int = clampi(int(roundf((cos(ang) * 0.3 + 0.3) / 0.15)), 0, 4)
	var tx: Texture2D = _ptex2(_pvar(p), li)
	var TW: float = float(tx.get_width())
	var TH: float = float(tx.get_height())
	var vis: float = floorf(clampf(vis_k, 0.0, 1.0) * TH)
	if vis < 1.0:
		return
	var hh: int = absi(hash(Vector2i(int(p.x) * 3, int(p.y) * 7)))
	var sc: float = ps * (0.66 + float(hh % 17) / 100.0)   # 节距 60–90，贴图原尺寸会挤成一堵墙；缩到 0.66–0.82
	var hgt: float = vis * PX * ys * sc
	var wd: float = roundf(TW * sc) * PX
	var dst := Rect2(_snap(Vector2(p.x - wd * 0.5 + jit, p.y + 8.0 * PX * sc - hgt)), Vector2(wd, roundf(hgt / PX) * PX))
	g.wcv.draw_texture_rect_region(tx, dst, Rect2(0, 0, TW, vis), col)


## 预警：发光隆起的裂缝。地上一团冰光、几道发光裂缝从中心往外爬到判定边、雪面拱起，最后 0.25 秒冰尖先冒头
func _pillar_warn(w, cv, t: Dictionary, k: float, sd: int) -> void:
	var c: Vector2 = t.pos
	var r: float = float(t.r)
	var gy: float = g.combat.GROUND_Y
	var gt: Texture2D = _glow_tex()
	var gsz := Vector2(r * 2.8, r * 2.8 * gy)
	cv.draw_texture_rect(gt, Rect2(((c - gsz * 0.5) / PX).floor() * PX, gsz), false, Color(0.75, 0.92, 1.0, 0.2 + 0.35 * k))
	var nc := 6
	for i in nc:
		var a: float = TAU * float(i) / float(nc) + float(sd % 7) * 0.3 + float(absi(hash(Vector2i(sd, i))) % 40) / 100.0
		var dv := Vector2(cos(a), sin(a) * gy)
		_crack_col(w, c, dv.angle(), r * dv.length() * (0.95 + 0.1 * float(i % 2)), clampf(k * 1.4, 0.0, 1.0), sd + i * 7, CRK_HOT.lerp(Color.WHITE, k * 0.5), A1_SH, 8.0)
	# 中心一团冰光越来越亮（发光隆起的裂缝），0.55 之后冰尖从缝里往上顶、抖
	var hs := Vector2(r * 1.1, r * 0.6) * (0.6 + 0.4 * k)
	cv.draw_texture_rect(gt, Rect2(((c - hs * 0.5) / PX).floor() * PX, hs), false, Color(0.9, 0.98, 1.0, 0.25 + 0.5 * k))
	w.tb_flush()
	if k > 0.55:
		_pillar_draw(c, float(t.get("pang", PI * 0.5)), float(t.get("ps", 1.0)), (k - 0.55) / 0.45 * 0.28, 1.0, (1.0 if int(g.t * 30.0) % 2 == 0 else -1.0) * 2.0)
	if rng.randf() < 0.25 + 0.6 * k:
		var aq: float = rng.randf() * TAU
		_add(c + Vector2(cos(aq), sin(aq) * 0.5) * r * 0.5 * rng.randf(), Vector2(rng.randf_range(-20, 20), -rng.randf_range(40, 110)), 0.45, A1_LIT if rng.randf() < 0.7 else A1_MID, 8.0, 3, 500.0)


## 冰柱：0.14 秒顶到全高（纵向过冲后回弹）+ 雪块往外飞 + 冰屑 + 冰雾 + 一下冷光；立着时有右下接地影、照地冷光；到期碎掉
func _will_pillar(w, o: Dictionary, now: float) -> void:
	var p: Vector2 = o.pos
	var pa: float = float(o.get("ang", PI * 0.5))
	var ps: float = float(o.get("ps", 1.0))
	if not o.has("fx_t0"):
		o["fx_t0"] = now
		var gy: float = g.combat.GROUND_Y
		for i in 18:
			var a: float = rng.randf() * TAU
			var sp: float = rng.randf_range(60.0, 220.0)
			var col: Color = [A1_LIT, A1_LIT, Color(0.78, 0.87, 0.92), A1_MID][rng.randi() % 4]
			_add(p + Vector2(cos(a) * 30.0, sin(a) * 30.0 * gy), Vector2(cos(a) * sp * 1.4, sin(a) * sp * 1.4 * gy - rng.randf_range(220.0, 420.0)), rng.randf_range(0.6, 0.9), col, rng.randf_range(8.0, 16.0), 3, 1100.0)
		_ice_bits(p + Vector2(0, -30), 14, 1.0)
		for i in 4:
			_icefog(p + Vector2(rng.randf_range(-24, 24), rng.randf_range(-4, 6)), Vector2(rng.randf_range(-60, 60), rng.randf_range(-20, 0)), 0.8, 34.0, 0.75)
		_glints(p + Vector2(0, -50), 6, 30.0)
		glows.append([p + Vector2(0, -20), now, 160.0])
	var age: float = now - float(o.fx_t0)
	var left: float = float(o.until) - now
	if left < 0.14:
		if not o.get("fx_shat", false):
			o["fx_shat"] = true
			_ice_bits(p + Vector2(0, -50), 26, 1.0)
			_ice_bits(p + Vector2(0, -16), 14, 0.7)
			embers(p + Vector2(0, -40), 8, ICEL[1], 160.0, 320.0, 0.5, 5.0)
			for i in 2:
				_icefog(p + Vector2(rng.randf_range(-16, 16), 0), Vector2(rng.randf_range(-40, 40), -10), 0.7, 30.0, 0.7)
		return
	var s: float = clampf(age / 0.14, 0.0, 1.0)
	var hk: float = 1.0 - pow(1.0 - s, 3.0)
	var ys: float = 1.0 + 0.12 * clampf(1.0 - (age - 0.14) / 0.16, 0.0, 1.0) * (1.0 if age > 0.1 else 0.0)
	var jit: float = (sin(age * 70.0) * 2.0) if age < 0.3 else 0.0
	# 接地影（光从左上来 → 影子落右下）+ 冰柱自己的低亮度冷光照地
	_ground_shadow(p + Vector2(18, 7) * ps, 30.0 * hk * ps, 0.95)
	var gt: Texture2D = _glow_tex()
	# 顶出那一下雪地被冷光照亮（大团、亮），0.8 秒退到常亮的一小团
	var fl: float = clampf(1.0 - age / 0.8, 0.0, 1.0)
	var gs := Vector2(160, 70) + Vector2(220, 96) * fl
	g.wcv.draw_texture_rect(gt, Rect2(((p - gs * 0.5) / PX).floor() * PX, gs), false, Color(0.88, 0.97, 1.0, 0.16 + 0.6 * fl * fl))
	_pillar_draw(p, pa, ps, hk, ys, jit)
	if age < 0.12:
		_pillar_draw(p, pa, ps, hk, ys, jit, Color(1.6, 1.7, 1.8, 0.5 * (1.0 - age / 0.12)))   # 顶出那一下爆亮再冷却


## ==== 克雷松「苗圃吞地」（11-28 用户：每只 Boss 一种主表现，概念图 fm_c3 / fm_c4）：苗圃 = 地面一块块被「无」吃掉，
## 露出淡紫 270° 星空；边缘不规则崩塌、雪块往里飘落；稳定设施周围一圈地面保持完好（洞边绕开设施）。判定照旧（国度 nursery）
const VOID_D := Color(0.07, 0.035, 0.13)     # 洞壁 / 最深处
const VOID_M := Color(0.3, 0.2, 0.48)       # 星空暗处
const VOID_L := Color(0.58, 0.46, 0.8)      # 星云
const VOID_RIM := Color(0.86, 0.62, 1.0)     # 洞边淡紫光
const DEV_SAFE := 120.0                      # 设施周围保持完好的半径


## 洞 v3（协调人 11-28 克雷松 v2 意见）：洞里不是黑——中等明度淡紫 270° 发光星空（仍比雪地暗），内沿一圈柔和淡紫辉光、星点更亮、
## 地面投一圈淡紫光；外形是有机崩口（大弧线 + 小锯齿，48 点，不出长直边）；北侧远壁雪层四层、北雪唇受光、崩口挂雪块、雪块落进洞。
## 同一套画法给：苗圃（_void_draw）、苗圃环沟（_band_draw）、无之花被吃掉的扇区（cvoids）。画面半径 = 判定 × 1.2，判定不动
const WALL := [Color(0.81, 0.87, 0.92), Color(0.62, 0.69, 0.78), Color(0.44, 0.45, 0.6), Color(0.3, 0.24, 0.44)]
const SKY := Color(0.36, 0.27, 0.56)       # 中等明度淡紫（比雪面 L≈68 暗一截，不黑）
const SKY_IN := Color(0.27, 0.19, 0.45)    # 洞心略深，内沿辉光往里渐暗
const SKY_GLOW := Color(0.66, 0.5, 0.92)   # 内沿淡紫辉光
const NEB := Color(0.86, 0.74, 1.0)
const VIS_K := 1.2
var cvoids: Array = []   # 无之花被吃掉的扇区 [外形点, 中心, 出生 t, 寿命, 种子]


func _void_shape(k: Dictionary) -> void:
	var sd: int = absi(hash(Vector2i(int(k.pos.x), int(k.pos.y)))) % 9973
	k["fx_rs"] = _organic_rs(sd, 48)
	k["fx_sd"] = sd


## 有机外形：两三条低频正弦叠出大弧线，再加一点高频小锯齿（相邻点交替 + 哈希）
func _organic_rs(sd: int, n: int) -> Array:
	var p1: float = float(sd % 628) / 100.0
	var p2: float = float((sd / 7) % 628) / 100.0
	var p3: float = float((sd / 49) % 628) / 100.0
	var rs: Array = []
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var big: float = 0.13 * sin(2.0 * a + p1) + 0.09 * sin(3.0 * a + p2) + 0.05 * sin(5.0 * a + p3)
		var jag: float = (float(absi(hash(Vector2i(sd, i))) % 100) / 100.0 - 0.5) * 0.09 + (0.025 if i % 2 == 0 else -0.025)
		rs.append(0.92 + big + jag)
	return rs


func _void_pts(k: Dictionary, open: float, gy: float, devs: Array, scale := 1.0) -> PackedVector2Array:
	var rs: Array = k.fx_rs
	var n: int = rs.size()
	var c: Vector2 = k.pos
	var r: float = float(k.r) * open * scale
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var q: Vector2 = c + Vector2(cos(a), sin(a) * gy) * r * float(rs[i])
		for d in devs:
			var dp: Vector2 = d.pos
			if c.distance_to(dp) < DEV_SAFE * 0.9:
				continue
			var s2 := 1.0
			while s2 > 0.1 and c.lerp(q, s2).distance_to(dp) < DEV_SAFE:
				s2 -= 0.1
			q = c.lerp(q, s2)
		pts.append(q)
	return pts


func _shift(pts: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var o := PackedVector2Array()
	for q in pts:
		o.append(q + d)
	return o


func _shrink(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for q in pts:
		o.append(c + (q - c) * k)
	return o


func _clip_fill(w, a: PackedVector2Array, b: PackedVector2Array, col: Color) -> Array:
	var res: Array = Geometry2D.intersect_polygons(a, b)
	for poly in res:
		if (poly as PackedVector2Array).size() >= 3:
			w.tb_polygon(poly, col)
	return res


## 通用「被吃掉的地」：outer = 外形（世界坐标），c = 中心，R = 大致半径，D = 远壁可见厚度
func _void_render(w, cv, outer: PackedVector2Array, c: Vector2, R: float, sd: int, now: float, gy: float, chunks := true) -> void:
	if outer.size() < 3:
		return
	var D: float = clampf(R * 0.3, 8.0, 30.0)
	var gt: Texture2D = _glow_tex()
	var gsz := Vector2(R * 3.0, R * 3.0 * gy)
	cv.draw_texture_rect(gt, Rect2(((c - gsz * 0.5) / PX).floor() * PX, gsz), false, Color(VOID_RIM.r, VOID_RIM.g, VOID_RIM.b, 0.32))   # 地面投一圈淡紫光
	w.tb_polygon(_shift(outer, Vector2(2, 4)), Color(A1_BACK, 0.45))   # 南外沿冷影
	w.tb_polygon(outer, WALL[0])
	for i in range(1, 4):
		_clip_fill(w, outer, _shift(outer, Vector2(0, D * float(i) / 4.0)), WALL[i])
	var skies: Array = _clip_fill(w, outer, _shift(outer, Vector2(0, D)), SKY_GLOW)
	w.tb_flush()
	if skies.is_empty():
		return
	var sky: PackedVector2Array = skies[0]
	var sc: Vector2 = c + Vector2(0, D * 0.6)
	# 内沿辉光：星空先铺辉光色，往里两层缩小的多边形依次变成星空底色 / 洞心
	_clip_fill(w, sky, _shrink(sky, sc, 0.86), SKY)
	_clip_fill(w, sky, _shrink(sky, sc, 0.55), SKY_IN)
	# 星云：1–2 段弯曲斜向月牙云（浓淡两层）
	for ni in (2 if R > 80.0 else 1):
		var a0: float = float((sd * 7 + ni * 131) % 628) / 100.0 + now * 0.05
		var tilt: float = -0.5 + float((sd + ni * 3) % 10) / 10.0
		var ln: float = R * 0.95
		var th: float = R * 0.2
		var o1 := PackedVector2Array()
		var o2 := PackedVector2Array()
		for j in 9:
			var f: float = float(j) / 8.0
			var x: float = (f - 0.5) * ln
			var y: float = sin(f * PI * 1.2 + a0) * R * 0.2 + x * tilt * 0.4
			var wdt: float = th * sin(PI * f) * (0.7 + 0.3 * sin(f * 9.0 + a0 * 3.0))
			o1.append(sc + Vector2(x, y * gy - wdt))
			o2.append(sc + Vector2(x, y * gy + wdt))
		var cloud := PackedVector2Array(o1)
		for j in range(8, -1, -1):
			cloud.append(o2[j])
		_clip_fill(w, sky, cloud, Color(NEB, 0.3))
		_clip_fill(w, sky, _shrink(cloud, sc + Vector2(0, (cloud[4] - sc).y), 0.55), Color(NEB, 0.42))
	w.tb_flush()
	# 星点：按面积，三档大小，亮
	var ns: int = int(clampf(R * R / 70.0, 16.0, 220.0))
	for i in ns:
		var hs: int = absi(hash(Vector2i(sd + 77, i)))
		var q: Vector2 = sc + Vector2(float(hs % 200) / 100.0 - 1.0, (float((hs / 200) % 200) / 100.0 - 1.0) * gy) * R
		if not Geometry2D.is_point_in_polygon(q, sky):
			continue
		var tw: float = 0.5 + 0.5 * sin(now * (3.0 + float(hs % 5)) + float(hs % 97))
		var sz: int = [1, 1, 1, 2, 2, 3][hs % 6]
		var col: Color = Color(1.0, 0.98, 1.0) if hs % 3 else Color(0.95, 0.85, 1.0)
		col.a = 0.55 + 0.45 * tw
		var qq: Vector2 = _snap(q)
		if sz == 3 and tw > 0.55:
			cv.draw_rect(Rect2(qq + Vector2(-4, 0), Vector2(10, 2)), col)
			cv.draw_rect(Rect2(qq + Vector2(0, -4), Vector2(2, 10)), col)
		else:
			cv.draw_rect(Rect2(qq, Vector2(2 * sz, 2 * sz)), col)
	# 北雪唇受光
	var n: int = outer.size()
	for i in n:
		var a0p: Vector2 = outer[i]
		var a1p: Vector2 = outer[(i + 1) % n]
		if a0p.y < c.y + R * 0.1 * gy and a1p.y < c.y + R * 0.1 * gy and (a0p.x - c.x) * (a1p.x - c.x) > -R * R:
			var nn: Vector2 = Vector2(0, -1)
			w.tb_line(_snap(a0p + nn * 3.0), _snap(a1p + nn * 3.0), A1_LIT, 4.0)
	if chunks:
		for i in 5:
			var hs2: int = absi(hash(Vector2i(sd + 5, i)))
			var q2: Vector2 = outer[hs2 % n]
			if q2.y > c.y:
				continue
			var s2: float = 5.0 + float(hs2 % 5)
			var qd: Vector2 = q2 + (c - q2).normalized() * 3.0 + Vector2(sin(now * 7.0 + float(i)), 0)
			w.tb_poly(PackedVector2Array([_snap(qd + Vector2(-s2 - 2, -2)), _snap(qd + Vector2(s2 + 2, -3)), _snap(qd + Vector2(s2, s2 * 0.7 + 2)), _snap(qd + Vector2(-s2, s2 * 0.6 + 2))]), A1_OL)
			w.tb_poly(PackedVector2Array([_snap(qd + Vector2(-s2, 0)), _snap(qd + Vector2(s2, -1)), _snap(qd + Vector2(s2 - 1, s2 * 0.7)), _snap(qd + Vector2(-s2 + 1, s2 * 0.6))]), Color(0.69, 0.8, 0.86))
			w.tb_line(_snap(qd + Vector2(-s2, 0)), _snap(qd + Vector2(s2, -1)), A1_LIT, 2.0)
	w.tb_flush()
	if rng.randf() < 0.25 * clampf(R / 60.0, 0.6, 3.0):
		var q3: Vector2 = outer[rng.randi() % n]
		if q3.y < c.y:
			_add(q3, Vector2(rng.randf_range(-10, 10), rng.randf_range(30, 70)), rng.randf_range(0.5, 0.8), A1_LIT if rng.randf() < 0.6 else Color(0.69, 0.8, 0.86), rng.randf_range(6.0, 10.0), 3, 120.0)


func _void_draw(cv, w, k: Dictionary, now: float, gy: float) -> void:
	if not k.has("fx_rs") or (k.fx_rs as Array).size() != 48:
		_void_shape(k)
	var age: float = now - float(k.born)
	var c: Vector2 = k.pos
	var r: float = float(k.r)
	var sd: int = int(k.fx_sd)
	if age < 0.35:
		var kc: float = age / 0.35
		for i in 5:
			var a: float = TAU * float(i) / 5.0 + float(sd % 7) * 0.4
			var dv := Vector2(cos(a), sin(a) * gy)
			_crack_col(w, c, dv.angle(), r * VIS_K * dv.length() * 0.9, kc, sd + i * 5, Color(0.5, 0.38, 0.7), A1_SH, 4.0)
		w.tb_flush()
		return
	var open: float = clampf((age - 0.35) / 0.65, 0.0, 1.0)
	open = 1.0 - (1.0 - open) * (1.0 - open)
	if float(k.life) > 0.0:
		open *= clampf((float(k.born) + float(k.life) - now) / 0.6, 0.0, 1.0)
	if open <= 0.02:
		return
	var devs: Array = []
	for it in cres_list.values():
		if not it[0].dead:
			devs.append_array(it[0].get("devs", []))
	_void_render(w, cv, _void_pts(k, open, gy, devs, VIS_K), c, r * VIS_K * open, sd, now, gy)
	for d in devs:
		if c.distance_to(d.pos) < DEV_SAFE * 0.9:
			_void_island(w, d.pos, open, gy, clampf(r * open * 0.62, 18.0, DEV_SAFE * 0.6))


## 苗圃环沟（回荡）：同一套洞的画法，按缺口分成几段弧形沟，沟宽沿弧不均（48–72）
func _band_draw(w, cv, e: Dictionary, now: float, gy: float) -> void:
	for b in e.get("bands", []):
		if now < float(b.t0):
			continue
		var fr: float = 60.0 + (now - float(b.t0)) * 150.0
		if fr > 660.0:
			continue
		var c: Vector2 = b.c
		var gapk: float = maxf(0.25, 50.0 / maxf(1.0, fr))
		var sd: int = absi(hash(Vector2i(int(c.x), int(c.y)))) % 9973
		var gaps: Array = (b.gaps as Array).duplicate()
		gaps.sort()
		# 把圆周按缺口切成几段 [a0, a1]
		var segs: Array = []
		if gaps.is_empty():
			segs.append([0.0, TAU])
		else:
			for i in gaps.size():
				var a0: float = float(gaps[i]) + gapk
				var a1: float = float(gaps[(i + 1) % gaps.size()]) - gapk
				if i == gaps.size() - 1:
					a1 += TAU
				if a1 > a0 + 0.05:
					segs.append([a0, a1])
		for s in segs:
			var a0: float = s[0]
			var a1: float = s[1]
			var ns: int = clampi(int((a1 - a0) * fr / 14.0), 6, 120)
			var op := PackedVector2Array()
			var ip := PackedVector2Array()
			for j in ns + 1:
				var a: float = lerpf(a0, a1, float(j) / float(ns))
				var hw: float = 24.0 + 12.0 * sin(a * 5.0 + float(sd)) + 4.0 * sin(a * 17.0 + float(sd) * 0.3)
				var taper: float = clampf(minf(float(j), float(ns - j)) / 3.0, 0.35, 1.0)   # 两头收成崩口
				op.append(c + Vector2(cos(a), sin(a) * gy) * (fr + hw * taper))
				ip.append(c + Vector2(cos(a), sin(a) * gy) * (fr - hw * taper * 0.8))
			var poly := PackedVector2Array(op)
			for j in range(ns, -1, -1):
				poly.append(ip[j])
			var am: float = (a0 + a1) * 0.5
			var mid: Vector2 = c + Vector2(cos(am), sin(am) * gy) * fr
			_void_render(w, cv, poly, mid, 40.0, sd + int(a0 * 100.0), now, gy, false)


## 无之花：扇区先发裂（预警），结算后扇区被吃成洞 0.9 秒再合上
func cres_petal_void(c: Vector2, ang: float, half: float, r: float) -> void:
	cvoids.append([c, ang, half, r, g.t, absi(hash(Vector2i(int(c.x * 3.0 + ang * 100.0), int(c.y)))) % 9973])


func _cvoids_draw(w, cv, now: float, gy: float) -> void:
	var keep: Array = []
	for v in cvoids:
		var age: float = now - float(v[4])
		if age > 1.1:
			continue
		keep.append(v)
		var open: float = clampf(age / 0.18, 0.0, 1.0) * clampf((1.1 - age) / 0.4, 0.0, 1.0)
		if open <= 0.02:
			continue
		var c: Vector2 = v[0]
		var ang: float = v[1]
		var half: float = float(v[2]) * 1.15
		var r: float = float(v[3])
		var sd: int = v[5]
		var poly := PackedVector2Array()
		var ns := 16
		var r0: float = 36.0
		for j in ns + 1:
			var a: float = lerpf(ang - half, ang + half, float(j) / float(ns))
			var jag: float = (float(absi(hash(Vector2i(sd, j))) % 100) / 100.0 - 0.5) * 18.0
			poly.append(c + Vector2(cos(a), sin(a) * gy) * (r0 + (r - r0) * open + jag))
		for j in range(ns, -1, -1):
			var a: float = lerpf(ang - half * 0.6, ang + half * 0.6, float(j) / float(ns))
			poly.append(c + Vector2(cos(a), sin(a) * gy) * r0)
		var mid: Vector2 = c + Vector2(cos(ang), sin(ang) * gy) * r * 0.55
		_void_render(w, cv, poly, mid, r * 0.3, sd, now, gy, false)
	cvoids = keep


## 双击 / 回荡·双击 / 裂隙：「空间被切开」（参照 bs_c1）。预警 = 一道暗色缝沿线撕开（品红细亮边，越来越宽）；
## 结算 = 整条裂口张开（黑紫裂口 + 品红亮边 + 里面星点），0.45 秒后合上；张开时两侧崩出碎屑
var crifts: Array = []   # [起点, 方向角, 长, 半宽, 出生 t, 种子]
const RIFT_EDGE := Color(1.0, 0.42, 0.86)
const RIFT_IN := Color(0.12, 0.05, 0.2)


func _rift_pts(a: Vector2, d: Vector2, L: float, hw: float, sd: int) -> PackedVector2Array:
	var nv := d.orthogonal()
	var n: int = maxi(6, int(L / 26.0))
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in n + 1:
		var f: float = float(i) / float(n)
		var tp: float = pow(sin(PI * clampf(f, 0.0, 1.0)), 0.6)
		var j1: float = 0.6 + float(absi(hash(Vector2i(sd, i))) % 60) / 100.0
		var j2: float = 0.6 + float(absi(hash(Vector2i(sd + 9, i))) % 60) / 100.0
		var zig: float = (float(absi(hash(Vector2i(sd + 3, i))) % 100) / 100.0 - 0.5) * hw * 0.8
		var q: Vector2 = a + d * L * f + nv * zig
		top.append(q + nv * hw * tp * j1)
		bot.append(q - nv * hw * tp * j2)
	var poly := PackedVector2Array(top)
	for i in range(n, -1, -1):
		poly.append(bot[i])
	return poly


func _rift_warn(w, t: Dictionary, k: float, sd: int) -> void:
	var a: Vector2 = t.pos
	var d := Vector2.from_angle(float(t.ang))
	var L: float = float(t.len) * clampf(k * 1.4, 0.0, 1.0)
	if L < 4.0:
		return
	var hw: float = float(t.wid) * (0.12 + 0.3 * k)
	var poly: PackedVector2Array = _rift_pts(a, d, L, hw, sd)
	w.tb_polygon(poly, RIFT_EDGE.lerp(Color.WHITE, 0.2))
	w.tb_polygon(_rift_pts(a, d, L, hw * 0.55, sd), RIFT_IN)
	w.tb_flush()
	if rng.randf() < 0.5:
		_add(a + d * L, Vector2(rng.randf_range(-40, 40), rng.randf_range(-60, -10)), 0.3, RIFT_EDGE, 4.0, 3, 0.0)


func cres_rift(t: Dictionary) -> void:
	crifts.append([t.pos, float(t.ang), float(t.len), float(t.wid), g.t, absi(hash(Vector2i(int(t.pos.x), int(t.pos.y)))) % 9973])
	var d := Vector2.from_angle(float(t.ang))
	for i in 10:
		var q: Vector2 = (t.pos as Vector2) + d * float(t.len) * rng.randf()
		_add(q, d.orthogonal() * rng.randf_range(-160, 160) + Vector2(0, -rng.randf_range(40, 120)), rng.randf_range(0.4, 0.6), [A1_LIT, RIFT_EDGE, Color(0.3, 0.22, 0.42)][i % 3], rng.randf_range(5.0, 9.0), 3, 700.0)


func _crifts_draw(w, cv, now: float) -> void:
	var keep: Array = []
	for r in crifts:
		var age: float = now - float(r[4])
		if age > 0.6:
			continue
		keep.append(r)
		var open: float = clampf(age / 0.06, 0.0, 1.0) * clampf((0.6 - age) / 0.25, 0.0, 1.0)
		var a: Vector2 = r[0]
		var d := Vector2.from_angle(float(r[1]))
		var L: float = r[2]
		var hw: float = float(r[3]) * (0.4 + 0.9 * open)
		var sd: int = r[5]
		var outer: PackedVector2Array = _rift_pts(a, d, L, hw, sd)
		var inner: PackedVector2Array = _rift_pts(a, d, L, hw * 0.72, sd)
		var gt: Texture2D = _glow_tex()
		var m: Vector2 = a + d * L * 0.5
		w.tb_polygon(outer, RIFT_EDGE)
		w.tb_polygon(inner, RIFT_IN)
		w.tb_flush()
		var ns: int = int(L / 14.0)
		for i in ns:
			var hs: int = absi(hash(Vector2i(sd + 41, i)))
			var q: Vector2 = a + d * L * (float(hs % 1000) / 1000.0) + d.orthogonal() * (float((hs / 1000) % 100) / 100.0 - 0.5) * hw * 0.8
			if Geometry2D.is_point_in_polygon(q, inner):
				var tw: float = 0.5 + 0.5 * sin(now * 9.0 + float(hs % 31))
				cv.draw_rect(Rect2(_snap(q), Vector2(2, 2) * (2.0 if hs % 5 == 0 else 1.0)), Color(1, 0.95, 1, 0.5 + 0.5 * tw))
	crifts = keep


## 设施脚下一座没被吃掉的雪岛：不规则雪面 + 北侧受光雪唇 + 洞边淡紫亮线（设施画在它上面）
func _void_island(w, p: Vector2, open: float, gy: float, rr: float) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		var j: float = 0.88 + float(absi(hash(Vector2i(int(p.x) + i, int(p.y)))) % 24) / 100.0
		pts.append(_snap(p + Vector2(cos(a), sin(a) * gy) * rr * j))
	var sh := PackedVector2Array()
	for q in pts:
		sh.append(q + Vector2(0, 8))
	w.tb_polygon(sh, A1_SH)   # 雪岛侧壁（往下露一截）
	w.tb_polygon(pts, Color(0.76, 0.85, 0.9))
	for i in pts.size():
		var a0: Vector2 = pts[i]
		var a1: Vector2 = pts[(i + 1) % pts.size()]
		w.tb_line(a0 + Vector2(0, 8), a1 + Vector2(0, 8), Color(VOID_RIM, 0.8 * open), 4.0)
		if a0.y < p.y:
			w.tb_line(a0, a1, A1_LIT, 4.0)
	w.tb_flush()


## ---- 闪现落地内爆（fm_c4）：0.16 秒暗紫碎晶往落点收拢 → 落点炸出一簇黑紫晶刺（品红棱），
## 地上一层淡紫放射光只画在地面层（压在队伍之下，不遮人）+ 雪 / 岩块抛出
var cimps: Array = []   # [位置, 出生 t, r, 刺表]


func cres_implode(c: Vector2, r: float) -> void:
	var sp: Array = []
	for i in 15:
		var a: float = TAU * float(i) / 15.0 + rng.randf_range(-0.2, 0.2)
		sp.append([a, rng.randf_range(10.0, 34.0), rng.randf_range(50.0, 120.0), rng.randf_range(40.0, 120.0), rng.randf_range(14.0, 26.0)])
	cimps.append([c, g.t, r, sp])
	for i in 18:
		var a2: float = rng.randf() * TAU
		var q: Vector2 = c + Vector2(cos(a2), sin(a2) * 0.5) * rng.randf_range(90.0, 160.0)
		_add(q, (c - q) * 5.5, 0.18, Color(0.3, 0.12, 0.45) if i % 3 else VOID_RIM, 6.0, 3, 0.0)   # 往里吸的暗紫碎屑


func _cimp_ground(cv, w, now: float) -> void:
	var gt: Texture2D = _glow_tex()
	var gy: float = g.combat.GROUND_Y
	for ci in cimps:
		var age: float = now - float(ci[1]) - 0.16
		if age < 0.0 or age > 0.6:
			continue
		var c: Vector2 = ci[0]
		var k: float = 1.0 - age / 0.6
		var L: float = float(ci[2]) * (0.5 + 0.5 * clampf(age / 0.12, 0.0, 1.0))
		var gsz := Vector2(L * 1.6, L * 1.6 * gy)
		cv.draw_texture_rect(gt, Rect2(((c - gsz * 0.5) / PX).floor() * PX, gsz), false, Color(0.86, 0.75, 1.0, 0.32 * k))
		for s in ci[3]:
			var a: float = float(s[0])
			var d := Vector2(cos(a), sin(a) * gy)
			var ln: float = L * (0.55 + 0.45 * float(s[3]) / 120.0)
			var nv := Vector2(-d.y, d.x).normalized()
			w.tb_poly(PackedVector2Array([c + nv * 10.0, c + d * ln, c - nv * 10.0]), Color(0.93, 0.85, 1.0, 0.3 * k))   # 地面放射光：低透明度，压在单位之下
	w.tb_flush()


func _cimp_front(w, now: float) -> void:
	var keep: Array = []
	for ci in cimps:
		var age: float = now - float(ci[1])
		if age > 0.95:
			continue
		keep.append(ci)
		var c: Vector2 = ci[0]
		if age < 0.16:
			continue
		var u: float = age - 0.16
		if not ci.size() > 4:
			ci.append(true)
			for i in 16:
				var a: float = rng.randf_range(-PI, 0.0)
				var sp: float = rng.randf_range(160.0, 360.0)
				_add(c + Vector2(rng.randf_range(-20, 20), -10), Vector2(cos(a) * sp, sin(a) * sp * 0.7 - 120.0), rng.randf_range(0.5, 0.8), [A1_LIT, A1_MID, Color(0.24, 0.2, 0.3), Color(0.36, 0.3, 0.42)][i % 4], rng.randf_range(7.0, 13.0), 3, 1000.0)
			glows.append([c + Vector2(0, -20), now, 120.0])
		var grow: float = clampf(u / 0.08, 0.0, 1.0)
		grow = 1.0 - (1.0 - grow) * (1.0 - grow)
		var sink: float = clampf((u - 0.35) / 0.4, 0.0, 1.0)
		var hk: float = grow * (1.0 - sink)
		if hk <= 0.02:
			continue
		# 后面的刺先画（北侧 = sin<0 先），近的盖远的
		var arr: Array = (ci[3] as Array).duplicate()
		arr.sort_custom(func(x, y): return sin(float(x[0])) < sin(float(y[0])))
		for s in arr:
			var a: float = float(s[0])
			var d := Vector2(cos(a), sin(a) * 0.5)
			var base: Vector2 = c + d * float(s[1])
			var tip: Vector2 = base + d * float(s[2]) * 0.55 * hk + Vector2(0, -float(s[3]) * hk)
			var hw: float = float(s[4]) * 0.5
			var nv := Vector2(-(tip - base).y, (tip - base).x).normalized()
			w.tb_poly(PackedVector2Array([base + nv * (hw + 3.0), tip + (tip - base).normalized() * 4.0, base - nv * (hw + 3.0)]), Color(0.05, 0.02, 0.08))
			w.tb_poly(PackedVector2Array([base + nv * hw, tip, base - nv * hw]), Color(0.2, 0.08, 0.3))
			var lit_side: float = 1.0 if nv.x + nv.y < 0.0 else -1.0   # 受光面朝左上
			w.tb_poly(PackedVector2Array([base, tip, base + nv * hw * lit_side]), Color(0.42, 0.2, 0.58))
			w.tb_line(_snap(base.lerp(tip, 0.15)), _snap(base.lerp(tip, 0.85)), Color(0.95, 0.4, 0.9, 0.9), 2.0)   # 品红棱
	cimps = keep
	w.tb_flush()


## ==== 雪祀「冰链弹跳」（11-28 用户：每只 Boss 一种主表现，概念图 fm_s1）：馈赠沿链在小怪之间折线跳 = 一道靛色冰链
## 从上一个落点拱起一道弧连到链头（链身暗靛描边 + 靛色 + 冰白芯，带轻微电弧抖动），链头一团冰白靛光；
## 每跳到一只小怪脚下炸出一簇靛色冰晶，沿途地上冒小冰晶；被跳过（拿到馈赠）的小怪身上泛靛光、往上飘靛色光点。判定 / 数值不动
const IND := [Color(0.094, 0.11, 0.44), Color(0.28, 0.32, 0.87), Color(0.67, 0.71, 1.0), Color(0.93, 0.95, 1.0)]
var sham_list := {}
var ctrails: Array = []   # 已跳过的链段 [a, b, 出生 t, 种子]


func shaman_draw(e: Dictionary) -> void:
	sham_list[int(e.id)] = [e, g.t]


func _arc_pts(a: Vector2, b: Vector2, h: float, sd: int, jit: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 12
	var nv: Vector2 = (b - a).orthogonal().normalized()
	var fr: int = int(g.t * 20.0)
	for i in n + 1:
		var f: float = float(i) / float(n)
		var j: float = 0.0
		if i > 0 and i < n:
			j = (float(absi(hash(Vector2i(sd + fr, i))) % 100) / 50.0 - 1.0) * jit
		pts.append(_snap(a.lerp(b, f) + Vector2(0, -h * sin(PI * f)) + nv * j))
	return pts


func _chain_draw(w, pts: PackedVector2Array, al: float) -> void:
	for pass_i in 3:
		var wd: float = [19.0, 11.0, 4.0][pass_i]
		var c: Color = [IND[0], IND[1], IND[3]][pass_i]
		c.a = al
		for i in pts.size() - 1:
			w.tb_line(pts[i], pts[i + 1], c, wd)


func _sham_burst(p: Vector2) -> void:
	for i in 5:
		var a: float = TAU * float(i) / 5.0 + rng.randf_range(-0.3, 0.3)
		_spike(p + Vector2(cos(a), sin(a) * 0.5) * rng.randf_range(10.0, 22.0), rng.randf_range(30.0, 50.0), rng.randf_range(12.0, 18.0), "shaman", cos(a) * 0.35)
	_spike(p, 62.0, 20.0, "shaman")
	sparks(p + Vector2(0, -20), -PI * 0.5, 1.2, 10, 300.0, [IND[3], IND[2], IND[1], IND[0]], true, 0.3)
	glows.append([p, g.t, 110.0])


func _sham_ground(cv, now: float) -> void:
	if sham_list.is_empty():
		return
	var gt: Texture2D = _glow_tex()
	# 拿到馈赠的小怪：脚下一团靛光
	for m in g.enemies:
		if m.dead or float(m.get("gift_until", 0.0)) <= now:
			continue
		var pul: float = 0.75 + 0.25 * sin(now * 6.0 + float(m.id))
		cv.draw_texture_rect(gt, Rect2(((m.pos - Vector2(56, 32)) / PX).floor() * PX, Vector2(112, 64)), false, Color(0.4, 0.45, 1.0, 0.8 * pul))
	for id in sham_list.keys():
		var e: Dictionary = sham_list[id][0]
		for b in e.get("balls", []):
			if b.dead or now >= float(b.t0):
				continue
			# 链路预画 0.8 秒：沿将要跳的路线地上亮起一串靛色柔光（越来越亮），让队长看清往哪拦
			var k: float = clampf(1.0 - (float(b.t0) - now) / 0.8, 0.0, 1.0)
			var path: Array = b.path
			for i in path.size() - 1:
				var a: Vector2 = path[i]
				var c: Vector2 = path[i + 1]
				var n: int = maxi(2, int(a.distance_to(c) / 30.0))
				for j in n:
					var q: Vector2 = a.lerp(c, (float(j) + 0.5) / float(n))
					cv.draw_texture_rect(gt, Rect2(((q - Vector2(22, 12)) / PX).floor() * PX, Vector2(44, 24)), false, Color(0.45, 0.5, 1.0, 0.45 * k))


func _sham_front(w, now: float) -> void:
	var keep: Array = []
	for tr in ctrails:
		var age: float = now - float(tr[2])
		if age > 0.6:
			continue
		keep.append(tr)
		_chain_draw(w, _arc_pts(tr[0], tr[1], 62.0 * (1.0 - age / 0.6), int(tr[3]), 4.0), 1.0 - age / 0.6)
	ctrails = keep
	for id in sham_list.keys():
		var it: Array = sham_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			sham_list.erase(id)
			continue
		_sham_moves(w, g.wcv, e, now)
		for b in e.get("balls", []):
			var path: Array = b.path
			var seg: int = int(b.seg)
			if int(b.get("fx_seg", 0)) != seg:
				# 跳到一个落点：冰晶炸开 + 刚走完的一段留成余链
				for s2 in range(int(b.get("fx_seg", 0)) + 1, seg + 1):
					if s2 < path.size():
						_sham_burst(path[s2])
						ctrails.append([path[s2 - 1], path[s2], now, rng.randi() % 997])
				b["fx_seg"] = seg
			if b.dead or now < float(b.t0) or seg + 1 >= path.size():
				continue
			var a: Vector2 = path[seg]
			var p: Vector2 = b.p
			var to: Vector2 = path[seg + 1]
			var L: float = a.distance_to(to)
			var f: float = clampf(a.distance_to(p) / maxf(1.0, L), 0.0, 1.0)
			var h: float = 62.0
			var head: Vector2 = p + Vector2(0, -h * sin(PI * f))
			# 链身：从上一个落点拱到链头（只画走过的那段弧）
			var pts := PackedVector2Array()
			var n := maxi(2, int(12.0 * f))
			var nv: Vector2 = (to - a).orthogonal().normalized()
			for i in n + 1:
				var ff: float = f * float(i) / float(n)
				var j: float = 0.0 if i == 0 or i == n else (float(absi(hash(Vector2i(int(now * 20.0), i))) % 100) / 50.0 - 1.0) * 4.0
				pts.append(_snap(a.lerp(to, ff) + Vector2(0, -h * sin(PI * ff)) + nv * j))
			_chain_draw(w, pts, 1.0)
			# 沿途地上冒小冰晶（间距 20–56 随机）
			var dl: float = a.distance_to(p)
			if dl - float(b.get("fx_d", 0.0)) > float(b.get("fx_gap", 30.0)) or dl < float(b.get("fx_d", 0.0)):
				b["fx_d"] = dl
				b["fx_gap"] = rng.randf_range(20.0, 56.0)   # 间距 / 大小 / 偏移都随机（vreview：等距冰晶像贴纸）
				_spike(p + nv * rng.randf_range(-16, 16), rng.randf_range(12.0, 32.0), rng.randf_range(8.0, 14.0), "shaman", rng.randf_range(-0.45, 0.45))
			# 链头：冰白靛光团
			w.tb_flush()
			var gt: Texture2D = _glow_tex()
			g.wcv.draw_texture_rect(gt, Rect2(((head - Vector2(30, 30)) / PX).floor() * PX, Vector2(60, 60)), false, Color(0.55, 0.6, 1.0, 0.7))
			w.tb_poly(PackedVector2Array([head + Vector2(0, -10), head + Vector2(7, 0), head + Vector2(0, 10), head + Vector2(-7, 0)]), IND[0])
			w.tb_poly(PackedVector2Array([head + Vector2(0, -7), head + Vector2(4, 0), head + Vector2(0, 7), head + Vector2(-4, 0)]), IND[3])
			if rng.randf() < 0.6:
				_add(head, Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 20)), 0.3, IND[2], 4.0, 3, 0.0)
	# 拿到馈赠的小怪：往上飘靛色光点
	for m in g.enemies:
		if not m.dead and float(m.get("gift_until", 0.0)) > now and rng.randf() < 0.25:
			_add(m.pos + Vector2(rng.randf_range(-14, 14), -rng.randf_range(0, 30)), Vector2(0, -rng.randf_range(30, 60)), 0.6, IND[2] if rng.randf() < 0.6 else IND[3], 4.0, 3, 0.0)
	w.tb_flush()


## ==== 藤蔓「根须钻地」（11-28 用户：每只 Boss 一种主表现，概念图 fm_v1）：致幻缠绕的 S 形路线 = 雪下一道隆起的拱痕
## 从藤蔓脚下往队长追过去（拱顶受光雪 + 背光冷面 + 顶上裂开露出土和熔红缝），结算时整条拱痕破土：根须一根根顶出来，
## 土块 / 冰块 / 木屑往外飞，地上留一道翻开的土沟（边上熔红余烬），最前端那一下最大。判定照旧（6 段直线，一条只挨一下）
const SOIL := [Color(0.13, 0.085, 0.06), Color(0.3, 0.2, 0.13), Color(0.45, 0.31, 0.2)]
const ROOT := [Color(0.1, 0.065, 0.05), Color(0.33, 0.22, 0.15), Color(0.52, 0.37, 0.24)]
const EMBER := Color(1.0, 0.5, 0.18)
var vroots: Array = []    # [位置, 出生 t, 高, 弯, 粗]
var vtrench: Array = []   # [a, b, 出生 t, 宽]


func _vine_warn(w, cv, t: Dictionary, k: float, sd: int) -> void:
	var vi: int = int(t.get("vi", 1))
	var f: float = clampf(k * 1.3 * 6.0 - float(vi - 1), 0.0, 1.0)   # 拱痕从藤蔓脚下往队长推进：第 vi 段在 0.9 秒里依次隆起
	if f <= 0.0:
		return
	var a: Vector2 = t.pos
	var d := Vector2.from_angle(float(t.ang))
	var L: float = float(t.len) * f
	var b: Vector2 = a + d * L
	var nv := d.orthogonal()
	var hw: float = float(t.wid) * 0.45
	var lift: float = 6.0 + 6.0 * k
	# 背光冷面（右下）→ 拱身 → 拱顶受光雪 → 顶上裂开的土缝；按 14 像素一小段走，宽窄 / 拱顶起伏按哈希抖（vreview：整段矩形像贴纸），段首补一个圆头接住拐角
	var top: Vector2 = Vector2(0, -lift)
	var ns: int = maxi(2, int(L / 14.0))
	var prev_c: Vector2 = a
	var prev_w: float = hw
	for i in range(1, ns + 1):
		var c2: Vector2 = a + d * L * float(i) / float(ns)
		var hh: int = absi(hash(Vector2i(sd + vi * 31, i)))
		var w2: float = hw * (0.78 + float(hh % 40) / 100.0)
		var bump: Vector2 = top * (0.75 + float((hh / 40) % 50) / 100.0)
		w.tb_poly(PackedVector2Array([_snap(prev_c + nv * prev_w + Vector2(3, 4)), _snap(c2 + nv * w2 + Vector2(3, 4)), _snap(c2 - nv * w2 + Vector2(3, 4)), _snap(prev_c - nv * prev_w + Vector2(3, 4))]), Color(A1_SH, 0.5))
		w.tb_poly(PackedVector2Array([_snap(prev_c + nv * prev_w), _snap(c2 + nv * w2), _snap(c2 - nv * w2), _snap(prev_c - nv * prev_w)]), A1_BACK)
		w.tb_poly(PackedVector2Array([_snap(prev_c + nv * prev_w * 0.55 + bump), _snap(c2 + nv * w2 * 0.55 + bump), _snap(c2 - nv * w2 * 0.45 + bump), _snap(prev_c - nv * prev_w * 0.45 + bump)]), A1_LIT)
		prev_c = c2
		prev_w = w2
	var cap := PackedVector2Array()
	for i in 10:
		var aa: float = TAU * float(i) / 10.0
		cap.append(_snap(a + Vector2(cos(aa), sin(aa) * 0.6) * hw + top * 0.8))
	w.tb_poly(cap, A1_LIT)
	if k > 0.35:
		var cw: float = 4.0 + 6.0 * (k - 0.35)
		var q0: Vector2 = a + top
		for i in range(1, ns + 1):
			var q1: Vector2 = a + d * L * float(i) / float(ns) + top + nv * (float(absi(hash(Vector2i(sd, i + 70))) % 7) - 3.0)
			w.tb_line(_snap(q0), _snap(q1), SOIL[0], cw + 2.0)
			w.tb_line(_snap(q0), _snap(q1), EMBER.lerp(SOIL[2], 0.35 + 0.35 * sin(g.t * 9.0 + float(i) * 0.7)), maxf(2.0, cw - 4.0))   # 连续熔红缝，亮度沿缝慢慢流动（不交替成虚线）
			q0 = q1
	w.tb_flush()
	# 拱痕前端：雪和土往上蹦（只有正在推进的那一段）
	if f < 1.0 and rng.randf() < 0.9:
		_add(b + nv * rng.randf_range(-hw, hw), Vector2(rng.randf_range(-60, 60), -rng.randf_range(100, 200)), 0.45, A1_LIT if rng.randf() < 0.5 else SOIL[1], rng.randf_range(5.0, 9.0), 3, 700.0)


func _vine_burst(t: Dictionary) -> void:
	var a: Vector2 = t.pos
	var d := Vector2.from_angle(float(t.ang))
	var L: float = float(t.len)
	var nv := d.orthogonal()
	var front: bool = int(t.get("vi", 1)) == 6
	vtrench.append([a, a + d * L, g.t, float(t.wid) * 0.8])
	var n: int = 2 if not front else 3
	for i in n:
		var q: Vector2 = a + d * L * (float(i) + rng.randf_range(0.3, 0.8)) / float(n) + nv * rng.randf_range(-12, 12)
		vroots.append([q, g.t + rng.randf_range(0.0, 0.08), rng.randf_range(54.0, 84.0) * (1.4 if front and i == n - 1 else 1.0), rng.randf_range(-0.6, 0.6), rng.randf_range(16.0, 24.0)])
	# 土块 / 冰块 / 木屑
	var cnt: int = 10 if not front else 22
	for i in cnt:
		var q2: Vector2 = a + d * L * rng.randf()
		var ang: float = rng.randf_range(-PI, 0.0)
		var sp: float = rng.randf_range(140.0, 340.0) * (1.3 if front else 1.0)
		var kind: int = i % 3
		var col: Color = [SOIL[1], Color(0.78, 0.9, 0.97), Color(0.62, 0.42, 0.24)][kind]
		var sz: float = [rng.randf_range(8.0, 14.0), rng.randf_range(6.0, 11.0), 6.0][kind]
		if kind == 2:
			_add(q2, Vector2(cos(ang) * sp, sin(ang) * sp * 0.8 - 100.0), rng.randf_range(0.5, 0.8), col, 6.0, 2, 900.0)   # 木屑：拉伸细条
		else:
			_add(q2, Vector2(cos(ang) * sp, sin(ang) * sp * 0.8 - 100.0), rng.randf_range(0.55, 0.85), col, sz, 3, 1000.0)
	if front:
		embers(a + d * L, 10, EMBER, 160.0, 300.0, 0.6, 4.0)
		glows.append([a + d * L, g.t, 120.0])


func _vtrench_draw(w, cv, now: float) -> void:
	if vtrench.is_empty():
		return
	var gt: Texture2D = _glow_tex()
	var keep: Array = []
	for tr in vtrench:
		var age: float = now - float(tr[2])
		if age > 1.6:
			continue
		keep.append(tr)
		var al: float = clampf((1.6 - age) / 0.6, 0.0, 1.0)
		var a: Vector2 = tr[0]
		var b: Vector2 = tr[1]
		var nv: Vector2 = (b - a).orthogonal().normalized()
		var hw: float = float(tr[3]) * 0.5
		w.tb_poly(PackedVector2Array([_snap(a + nv * (hw + 4.0)), _snap(b + nv * (hw + 4.0)), _snap(b - nv * (hw + 4.0)), _snap(a - nv * (hw + 4.0))]), Color(A1_LIT, 0.8 * al))   # 翻起的雪唇
		w.tb_poly(PackedVector2Array([_snap(a + nv * hw), _snap(b + nv * hw), _snap(b - nv * hw), _snap(a - nv * hw)]), Color(SOIL[1], al))
		w.tb_poly(PackedVector2Array([_snap(a + nv * hw * 0.4), _snap(b + nv * hw * 0.4), _snap(b - nv * hw * 0.4), _snap(a - nv * hw * 0.4)]), Color(SOIL[0], al))
		w.tb_line(_snap(a), _snap(b), Color(EMBER, al * (0.5 + 0.5 * sin(now * 14.0 + a.x))), 2.0)   # 土沟底熔红缝
		if age < 0.5:
			var m: Vector2 = (a + b) * 0.5
			cv.draw_texture_rect(gt, Rect2(((m - Vector2(50, 28)) / PX).floor() * PX, Vector2(100, 56)), false, Color(1.0, 0.55, 0.3, 0.22 * (1.0 - age / 0.5)))
	vtrench = keep
	w.tb_flush()


## 根须：0.1 秒从土里顶出（弯着往上长），停 0.35 秒，0.4 秒缩回土里；深色描边 + 木身 + 受光面（左上）+ 熔红节
func _vroots_draw(w, now: float) -> void:
	var keep: Array = []
	for r in vroots:
		var age: float = now - float(r[1])
		if age > 0.9:
			continue
		keep.append(r)
		if age < 0.0:
			continue
		var up: float = clampf(age / 0.1, 0.0, 1.0)
		up = 1.0 - (1.0 - up) * (1.0 - up)
		if age > 0.45:
			up *= clampf(1.0 - (age - 0.45) / 0.4, 0.0, 1.0)
		var H: float = float(r[2]) * up
		if H < 3.0:
			continue
		var p: Vector2 = r[0]
		var bend: float = float(r[3])
		var W: float = float(r[4])
		var n := 6
		var lp := PackedVector2Array()
		var rp := PackedVector2Array()
		for i in n + 1:
			var f: float = float(i) / float(n)
			var c: Vector2 = p + Vector2(bend * H * f * f, -H * f)
			var hw: float = W * 0.5 * (1.0 - f * 0.85)
			lp.append(c + Vector2(-hw, 0))
			rp.append(c + Vector2(hw, 0))
		var outl := PackedVector2Array()
		var body := PackedVector2Array()
		var lit := PackedVector2Array()
		for i in n + 1:
			outl.append(lp[i] + Vector2(-3, 0))
			body.append(lp[i])
			lit.append(lp[i])
		for i in range(n, -1, -1):
			outl.append(rp[i] + Vector2(3, 0))
			body.append(rp[i])
			lit.append(lp[i].lerp(rp[i], 0.4))
		w.tb_polygon(outl, ROOT[0])
		w.tb_polygon(body, ROOT[1])
		w.tb_polygon(lit, ROOT[2])
		for i in [2, 4]:
			w.tb_line(_snap(lp[i].lerp(rp[i], 0.3)), _snap(lp[i].lerp(rp[i], 0.7)), EMBER, 2.0)
		w.tb_quad(_snap(p + Vector2(-W, -2)), _snap(p + Vector2(W, -2)), _snap(p + Vector2(W * 0.8, 4)), _snap(p + Vector2(-W * 0.8, 4)), SOIL[0])   # 根脚翻开的土
	vroots = keep
	w.tb_flush()


## ==== 雪祀 v2（11-28 新判定：冰链是主表现，跳距 240 / 300 按 fm_s1 放大）：粗冰链通用画法 + 寒链弹跳 / 冰链围笼 / 链扫 / 踏雪连链 / 道标围笼
## 冰链 = 暗靛描边 + 靛色链身 + 冰白芯（宽 18 / 11 / 4），轻微电弧抖动，链下雪地投一串靛光；链节上零星结冰晶
func _ichain(w, cv, a: Vector2, b: Vector2, h: float, wid: float, al: float, sd: int, grow := 1.0, bow := Vector2(0, -1)) -> void:
	var L: float = a.distance_to(b)
	if L < 4.0 or grow <= 0.0:
		return
	var n: int = clampi(int(L / 22.0), 4, 40)
	var nv: Vector2 = (b - a).orthogonal().normalized()
	var fr: int = int(g.t * 20.0)
	var pts := PackedVector2Array()
	var m: int = maxi(1, int(ceilf(float(n) * grow)))
	for i in m + 1:
		var f: float = minf(float(i) / float(n), grow)
		var j: float = 0.0 if i == 0 or f >= 1.0 else (float(absi(hash(Vector2i(sd + fr, i))) % 100) / 50.0 - 1.0) * 7.0   # 电弧抖动（1× 下看得见）
		pts.append(_snap(a.lerp(b, f) + bow * h * sin(PI * f) + nv * j))
	var gt: Texture2D = _glow_tex()
	for i in range(0, m + 1, 3):
		var q: Vector2 = a.lerp(b, minf(float(i) / float(n), grow))
		cv.draw_texture_rect(gt, Rect2(((q - Vector2(30, 16)) / PX).floor() * PX, Vector2(60, 32)), false, Color(0.45, 0.5, 1.0, 0.35 * al))
	# 链节：一节亮一节暗（亮节带冰白芯），读得出是一节节的链
	for i in pts.size() - 1:
		w.tb_line(pts[i], pts[i + 1], Color(IND[0], al), wid + 8.0)
	for i in pts.size() - 1:
		var lit: bool = i % 2 == 0
		var mid: Vector2 = pts[i].lerp(pts[i + 1], 0.5)
		var hl: Vector2 = (pts[i + 1] - pts[i]) * 0.42
		w.tb_line(mid - hl, mid + hl, Color(IND[2] if lit else IND[1], al), wid if lit else wid * 0.7)
		if lit:
			w.tb_line(mid - hl * 0.6, mid + hl * 0.6, Color(IND[3], al), maxf(2.0, wid * 0.35))
	if rng.randf() < 0.5 * al:
		var ri: int = rng.randi() % maxi(1, pts.size() - 1)
		_add(pts[ri], Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 20)), 0.18, IND[3], 3.0, 2, 0.0)   # 电火花
	# 冰结：每三节一颗菱晶
	for i in range(2, pts.size() - 1, 3):
		var q2: Vector2 = pts[i]
		var s: float = wid * 0.7
		w.tb_poly(PackedVector2Array([q2 + Vector2(0, -s * 1.6 - 2), q2 + Vector2(s + 2, 0), q2 + Vector2(0, s * 0.7 + 2), q2 + Vector2(-s - 2, 0)]), Color(IND[0], al))
		w.tb_poly(PackedVector2Array([q2 + Vector2(0, -s * 1.6), q2 + Vector2(s, 0), q2 + Vector2(0, s * 0.7), q2 + Vector2(-s, 0)]), Color(IND[2], al))
		w.tb_poly(PackedVector2Array([q2 + Vector2(0, -s * 1.6), q2 + Vector2(-s, 0), q2]), Color(IND[3], al))


## 靛色冰柱（围笼 / 链扫 / 道标的桩）：意志冰柱簇贴图缩小、染靛
func _ipost(p: Vector2, s: float, up := 1.0) -> void:
	_ground_shadow(p + Vector2(10, 4) * s, 18.0 * s, 0.8)
	_pillar_draw(p, PI * 0.5, s, up, 1.0, 0.0, Color(0.72, 0.78, 1.0))


func _sham_moves(w, cv, e: Dictionary, now: float) -> void:
	var sd0: int = int(e.id) * 31
	# A 寒链·弹射：链从雪祀一节节拱到每只小怪、最后到队长（每节 0.3 秒，0.25 秒长满）
	for l in e.get("links", []):
		if now > float(l.until):
			continue
		var pts: Array = l.path
		var t0: float = float(l.t0)
		var al: float = clampf((float(l.until) - now) / 0.4, 0.0, 1.0)
		for i in range(pts.size() - 1):
			var ts: float = t0 + 0.3 * float(i)
			if now < ts:
				break
			var gr: float = clampf((now - ts) / 0.25, 0.0, 1.0)
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			_ichain(w, cv, a, b, minf(110.0, a.distance_to(b) * 0.38), 11.0, al, sd0 + i * 7, gr)
	# D 冰链围笼：6 根靛色冰柱 + 柱间冰链（断口不连），收拢
	var cg = e.get("cage")
	if cg is Dictionary:
		var r: float = 220.0 if now < float(cg.t0) else lerpf(220.0, 120.0, clampf((now - float(cg.t0)) / 1.2, 0.0, 1.0))
		var up: float = clampf((now - (float(cg.t0) - 0.9)) / 0.3, 0.0, 1.0)
		var vs: Array = []
		for k in 6:
			vs.append((cg.c as Vector2) + Vector2.from_angle(float(cg.a0) + TAU * k / 6.0) * r)
		for k in 6:
			var mid: float = float(cg.a0) + TAU * (float(k) + 0.5) / 6.0
			var broken := false
			for ga in cg.gaps:
				if absf(angle_difference(mid, float(ga))) < PI / 6.0:
					broken = true
			if not broken and now >= float(cg.t0) - 0.3:
				_ichain(w, cv, vs[k] + Vector2(0, -20), vs[(k + 1) % 6] + Vector2(0, -20), 10.0, 11.0, 1.0, sd0 + k, clampf((now - (float(cg.t0) - 0.3)) / 0.3, 0.0, 1.0))
		w.tb_flush()
		for k in 6:
			_ipost(vs[k], 0.5, up)
	# E 链扫：两头冰柱 + 横贯的冰链顺风扫过，断口不连
	for sw in e.get("sweeps", []):
		if now < float(sw.t0):
			continue
		var ctr: Vector2 = (sw.p0 as Vector2) + (sw.w as Vector2) * (now - float(sw.t0)) * 90.0
		var nn: Vector2 = sw.n
		var g0: float = float(sw.gap)
		var sway: float = sin(now * 3.0 + float(sd0)) * 18.0
		var lift := Vector2(0, -22)
		# 链身两段，各自下垂成弧（h 取负 = 往下垂）并随风摆；断口两头各立一根冰柱拴住链
		var back: Vector2 = -(sw.w as Vector2)   # 链被风拖着扫：中段往后（逆风）弯成弧，随风摆
		_ichain(w, cv, ctr - nn * 700.0 + lift, ctr + nn * (g0 - 60.0) + lift, 70.0 + sway, 12.0, 1.0, sd0 + 3, 1.0, back)
		_ichain(w, cv, ctr + nn * (g0 + 60.0) + lift, ctr + nn * 700.0 + lift, 70.0 - sway, 12.0, 1.0, sd0 + 5, 1.0, back)
		w.tb_flush()
		_ipost(ctr - nn * 700.0, 0.6)
		_ipost(ctr + nn * 700.0, 0.6)
		_ipost(ctr + nn * (g0 - 60.0), 0.6)
		_ipost(ctr + nn * (g0 + 60.0), 0.6)
		for s2 in [-1.0, 1.0]:
			if rng.randf() < 0.5:
				_add(ctr + nn * (g0 + s2 * 60.0), Vector2(rng.randf_range(-30, 30), -rng.randf_range(30, 80)), 0.4, IND[2], 4.0, 3, 200.0)
	# F 踏雪：冰脚印之间连成冰链
	var pr = e.get("prints")
	if pr is Dictionary and float(pr.until) > now:
		var pp: Array = pr.pts
		var al2: float = clampf((float(pr.until) - now) / 0.3, 0.0, 1.0)
		for i in range(pp.size() - 1):
			_ichain(w, cv, pp[i], pp[i + 1], 14.0, 9.0, al2, sd0 + 40 + i)
	# G 道标围笼：4 根冰柱 + 方形冰链
	var bc = e.get("beacons")
	if bc is Dictionary and float(bc.until) > now:
		var vs2: Array = bc.pts
		for k in 4:
			_ichain(w, cv, vs2[k] + Vector2(0, -20), vs2[(k + 1) % 4] + Vector2(0, -20), 12.0, 10.0, 1.0, sd0 + 60 + k)
		w.tb_flush()
		for p in vs2:
			_ipost(p, 0.55)
	w.tb_flush()


## 预警（雪祀，11-28 起挂 sami_blade）：落点 = 地上一团靛光 + 冰裂纹往外爬到判定边 + 中心冰晶冒头；线 = 一条冰霜带；不伤人的出口线只铺淡带
func _sham_warn(w, cv, t: Dictionary, k: float, sd: int) -> void:
	var c: Vector2 = t.pos
	var gy: float = g.combat.GROUND_Y
	var gt: Texture2D = _glow_tex()
	var harm: bool = float(t.get("dmg", 0.0)) > 0.0
	match t.shape:
		"circle":
			var r: float = float(t.r)
			if not harm:
				return   # 围笼的外圈只是提示（链本身就是读法）
			var gsz := Vector2(r * 2.6, r * 2.6 * gy)
			cv.draw_texture_rect(gt, Rect2(((c - gsz * 0.5) / PX).floor() * PX, gsz), false, Color(0.45, 0.5, 1.0, 0.2 + 0.35 * k))
			for i in 6:
				var a: float = TAU * float(i) / 6.0 + float(sd % 7) * 0.3
				var dv := Vector2(cos(a), sin(a) * gy)
				_crack_col(w, c, dv.angle(), r * dv.length(), clampf(k * 1.3, 0.0, 1.0), sd + i * 7, IND[2].lerp(Color.WHITE, k * 0.4), IND[0], 4.0)
			if k > 0.6:
				_crystal(w, c, 6.0 + 10.0 * (k - 0.6) / 0.4)
		"line":
			var d0 := Vector2.from_angle(float(t.ang))
			var L: float = float(t.len)
			_band_tex(cv, ice_band, c, c + d0 * L * (1.0 if not harm else k), float(t.wid) * 0.8, (0.4 + 0.4 * k) if harm else 0.3)
			if harm:
				_crack_col(w, c, float(t.ang), L, k, sd, IND[2], IND[0], 4.0)


func _sham_wburst(t: Dictionary) -> void:
	if t.shape == "circle":
		_sham_crystal_burst(t.pos, float(t.r))
	elif t.shape == "line":
		var d := Vector2.from_angle(float(t.ang))
		for i in 4:
			var q: Vector2 = (t.pos as Vector2) + d * float(t.len) * (float(i) + 0.5) / 4.0
			_spike(q, 26.0, 12.0, "shaman", d.x * 0.3)


func _sham_crystal_burst(p: Vector2, r: float) -> void:
	var k: float = clampf(r / 70.0, 0.6, 1.4)
	for i in 7:
		var a: float = TAU * float(i) / 7.0 + rng.randf_range(-0.3, 0.3)
		_spike(p + Vector2(cos(a), sin(a) * 0.5) * rng.randf_range(14.0, 34.0) * k, rng.randf_range(34.0, 60.0) * k, rng.randf_range(14.0, 22.0) * k, "shaman", cos(a) * 0.35)
	_spike(p, 80.0 * k, 26.0 * k, "shaman")
	sparks(p + Vector2(0, -24), -PI * 0.5, 1.2, 14, 340.0, [IND[3], IND[2], IND[1], IND[0]], true, 0.35)
	_ice_bits(p + Vector2(0, -20), 10, 0.9)
	glows.append([p, g.t, 150.0])


## ==== 藤蔓 v2（11-28 新判定：根须钻地破土为主、熔岩口喷发为辅）——静态对照意见：翻土大块少碎屑多、无逐块描边、雪唇连成一条；
## 根须主根粗过土沟一半宽、树皮纹 + 疙瘩、尖头压暗、带分叉，成簇粗细差 2–3 倍、前端最大；破土土块爆团有体积
var vroots2: Array = []    # [根脚, 出生 t, 高, 粗, 弯, 扭, 种子]
var vcraters: Array = []   # [中心, 出生 t, 半径, 种子]
var vents_fx := {}         # 熔岩口喷发 t（按坐标键）


func vine_draw(e: Dictionary) -> void:
	vine_list[int(e.id)] = [e, g.t]


var vine_list := {}


## 地下根拱起的土脊（B 致幻缠绕的 mounds 点串）：相邻点之间一段雪下拱痕，后段裂开露土和熔红缝，前端雪土往上蹦
func _mound_ridge(w, a: Vector2, b: Vector2, al: float, sd: int, crack: float) -> void:
	var d: Vector2 = b - a
	var L: float = d.length()
	if L < 2.0:
		return
	d /= L
	var nv := d.orthogonal()
	var ns: int = maxi(2, int(L / 12.0))
	var prev_c: Vector2 = a
	var prev_w: float = 16.0
	for i in range(1, ns + 1):
		var c2: Vector2 = a + d * L * float(i) / float(ns)
		var hh: int = absi(hash(Vector2i(sd, i)))
		var w2: float = 16.0 * (0.75 + float(hh % 45) / 100.0)
		var lift := Vector2(0, -(8.0 + float((hh / 45) % 6)))
		w.tb_poly(PackedVector2Array([_snap(prev_c + nv * prev_w + Vector2(3, 4)), _snap(c2 + nv * w2 + Vector2(3, 4)), _snap(c2 - nv * w2 + Vector2(3, 4)), _snap(prev_c - nv * prev_w + Vector2(3, 4))]), Color(A1_SH, 0.45 * al))
		w.tb_poly(PackedVector2Array([_snap(prev_c + nv * prev_w), _snap(c2 + nv * w2), _snap(c2 - nv * w2), _snap(prev_c - nv * prev_w)]), Color(A1_BACK, al))
		w.tb_poly(PackedVector2Array([_snap(prev_c + nv * prev_w * 0.55 + lift), _snap(c2 + nv * w2 * 0.55 + lift), _snap(c2 - nv * w2 * 0.45 + lift), _snap(prev_c - nv * prev_w * 0.45 + lift)]), Color(A1_LIT, al))
		if crack > 0.0:
			w.tb_line(_snap(prev_c + lift), _snap(c2 + lift), Color(SOIL[0], al * crack), 6.0)
			w.tb_line(_snap(prev_c + lift), _snap(c2 + lift), Color(EMBER.lerp(SOIL[2], 0.4 + 0.3 * sin(g.t * 9.0 + float(i))), al * crack), 2.0)
		prev_c = c2
		prev_w = w2


## 破土坑：不规则翻土（有机外形）——深土芯 + 土面受光（左上）+ 一条连续翻起的雪唇（北半边亮）+ 坑边几块大土块、一圈碎屑（无逐块描边，明暗分前后）
func _crater_draw(w, cv, cr: Array, now: float) -> void:
	var age: float = now - float(cr[1])
	var al: float = clampf((2.6 - age) / 0.6, 0.0, 1.0)
	var c: Vector2 = cr[0]
	var r: float = float(cr[2]) * clampf(age / 0.1, 0.3, 1.0)
	var sd: int = cr[3]
	var gy: float = g.combat.GROUND_Y
	var rs: Array = _organic_rs(sd, 32)
	var outer := PackedVector2Array()
	var lip := PackedVector2Array()
	var core := PackedVector2Array()
	for i in 32:
		var a: float = TAU * float(i) / 32.0
		var q := Vector2(cos(a), sin(a) * gy) * r * float(rs[i])
		outer.append(c + q)   # 不取整：小坑取整后相邻点重合，三角化失败整块不画
		lip.append(c + q * 1.22 + Vector2(0, -2))
		core.append(c + q * 0.55 + Vector2(2, 3))
	w.tb_polygon(lip, Color(A1_LIT, 0.95 * al))   # 连续雪唇（整圈翻起；南半边被土面压住只剩北侧露亮）
	w.tb_polygon(outer, Color(SOIL[1], al))
	w.tb_polygon(core, Color(SOIL[0], al))
	# 受光土面：左上一片亮
	var litp := PackedVector2Array()
	for i in range(18, 30):
		litp.append(outer[i])
	litp.append(c + Vector2(-r * 0.2, -r * 0.15 * gy))
	w.tb_polygon(litp, Color(SOIL[2], al))
	# 坑边大土块（少，2–3 块）+ 碎屑（多）
	for i in 3:
		var hs: int = absi(hash(Vector2i(sd + 11, i)))
		var a2: float = float(hs % 628) / 100.0
		var q2: Vector2 = c + Vector2(cos(a2), sin(a2) * gy) * r * 1.15
		var s: float = r * (0.22 + float((hs / 628) % 10) / 100.0)
		w.tb_poly(PackedVector2Array([_snap(q2 + Vector2(-s, s * 0.3)), _snap(q2 + Vector2(-s * 0.6, -s * 0.6)), _snap(q2 + Vector2(s * 0.5, -s * 0.7)), _snap(q2 + Vector2(s, s * 0.2)), _snap(q2 + Vector2(s * 0.3, s * 0.6))]), Color(SOIL[1], al))
		w.tb_poly(PackedVector2Array([_snap(q2 + Vector2(-s * 0.6, -s * 0.6)), _snap(q2 + Vector2(s * 0.5, -s * 0.7)), _snap(q2 + Vector2(s * 0.2, -s * 0.1)), _snap(q2 + Vector2(-s * 0.4, -s * 0.05))]), Color(SOIL[2], al))
	for i in 18:
		var hs2: int = absi(hash(Vector2i(sd + 23, i)))
		var a3: float = float(hs2 % 628) / 100.0
		var q3: Vector2 = c + Vector2(cos(a3), sin(a3) * gy) * r * (1.1 + float((hs2 / 628) % 60) / 100.0)
		var s3: float = 2.0 + float(hs2 % 3) * 2.0
		cv.draw_rect(Rect2(_snap(q3), Vector2(s3, s3 * 0.8)), Color(SOIL[(hs2 / 7) % 3], al))


## 根须：0.12 秒顶出、停 0.6、0.4 秒缩回；粗身 + 树皮纹 + 疙瘩 + 尖头压暗 + 一根分叉；扭转 = 受光条左右来回
func _root2_draw(w, rt: Array, now: float) -> void:
	var age: float = now - float(rt[1])
	if age < 0.0 or age > 1.12:
		return
	var up: float = clampf(age / 0.12, 0.0, 1.0)
	up = 1.0 - (1.0 - up) * (1.0 - up)
	if age > 0.72:
		up *= clampf(1.0 - (age - 0.72) / 0.4, 0.0, 1.0)
	var H: float = float(rt[2]) * up
	if H < 3.0:
		return
	var p: Vector2 = rt[0]
	var W: float = rt[3]
	var bend: float = rt[4]
	var tw: float = rt[5]
	var n := 10
	var L := PackedVector2Array()
	var R := PackedVector2Array()
	var C := PackedVector2Array()
	for i in n + 1:
		var f: float = float(i) / float(n)
		var c: Vector2 = p + Vector2(bend * H * f * f + sin(f * 4.0 + tw) * W * 0.6 * f, -H * f * (1.0 - 0.12 * f))
		var hw: float = W * 0.5 * (1.0 - f * 0.72) * (1.0 + 0.14 * sin(f * 11.0 + tw))
		C.append(c)
		L.append(c + Vector2(-hw, 0))
		R.append(c + Vector2(hw, 0))
	var outl := PackedVector2Array()
	for q in L:
		outl.append(q + Vector2(-2, 0))
	outl.append(C[n] + Vector2(0, -3))
	for i in range(n, -1, -1):
		outl.append(R[i] + Vector2(2, 0))
	w.tb_polygon(outl, ROOT[0])
	var body := PackedVector2Array(L)
	for i in range(n, -1, -1):
		body.append(R[i])
	w.tb_polygon(body, ROOT[1])
	# 扭转受光条
	var lit := PackedVector2Array()
	var lit2 := PackedVector2Array()
	for i in n + 1:
		var s: float = 0.5 + 0.4 * sin(float(i) / float(n) * 7.0 + tw)
		lit.append(L[i].lerp(R[i], maxf(0.0, s - 0.22)))
		lit2.append(L[i].lerp(R[i], minf(1.0, s + 0.05)))
	var lp := PackedVector2Array(lit)
	for i in range(n, -1, -1):
		lp.append(lit2[i])
	w.tb_polygon(lp, ROOT[2])
	# 树皮纹（横向短纹）+ 尖头压暗
	for i in range(1, n - 1):
		if i % 2 == 0:
			w.tb_line(_snap(L[i].lerp(R[i], 0.2)), _snap(L[i].lerp(R[i], 0.75)), ROOT[0], 2.0)
	var tip := PackedVector2Array([L[n - 2], L[n], C[n] + Vector2(0, -3), R[n], R[n - 2]])
	w.tb_polygon(tip, ROOT[0])
	# 分叉：从 0.55 处斜出一根细根
	if W > 14.0:
		var bp: Vector2 = C[5]
		var sgn: float = 1.0 if int(rt[6]) % 2 == 0 else -1.0
		var bt: Vector2 = bp + Vector2(sgn * W * 1.4, -H * 0.28)
		w.tb_poly(PackedVector2Array([bp + Vector2(-W * 0.18, 2), bt, bp + Vector2(W * 0.18, -2)]), ROOT[0])
		w.tb_poly(PackedVector2Array([bp + Vector2(-W * 0.1, 1), bt + Vector2(-sgn, 1), bp + Vector2(W * 0.1, -1)]), ROOT[1])
	# 熔红节：两处疙瘩里透一点火光
	for i in [3, 6]:
		w.tb_line(_snap(L[i].lerp(R[i], 0.35)), _snap(L[i].lerp(R[i], 0.6)), EMBER, 2.0)


## 破土：坑 + 一簇根（主根最粗、前端最大）+ 土块爆团（大块少、碎屑多）+ 冰块 / 木屑
func vine_surface(p: Vector2, r: float, big: bool) -> void:
	var sd: int = absi(hash(Vector2i(int(p.x), int(p.y)))) % 9973
	var k: float = r / 60.0 * (1.35 if big else 1.0)
	vcraters.append([p, g.t, r * 0.75, sd])
	var nroot: int = 5 if big else 3
	for i in nroot:
		var main: bool = i == 0
		vroots2.append([p + Vector2(rng.randf_range(-16, 16), rng.randf_range(-4, 6)) * k, g.t + rng.randf_range(0.0, 0.06),
			(92.0 if main else rng.randf_range(40.0, 60.0)) * k, (30.0 if main else rng.randf_range(10.0, 15.0)) * k,
			rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 6.0), sd + i])
	for i in int(26.0 * k):
		var a: float = rng.randf_range(-PI, 0.0)
		var sp: float = rng.randf_range(120.0, 360.0) * k
		var bigc: bool = i < 3
		_add(p + Vector2(rng.randf_range(-20, 20), -6) * k, Vector2(cos(a) * sp, sin(a) * sp * 0.8 - 120.0), rng.randf_range(0.6, 0.95), SOIL[rng.randi() % 3], (rng.randf_range(12.0, 18.0) if bigc else rng.randf_range(4.0, 8.0)) * minf(k, 1.4), 3, 1100.0)
	for i in 6:
		var a2: float = rng.randf_range(-PI, 0.0)
		_add(p, Vector2(cos(a2), sin(a2)) * rng.randf_range(160, 300), 0.6, Color(0.78, 0.9, 0.97), rng.randf_range(5.0, 9.0), 3, 1000.0)
		_add(p, Vector2(cos(a2 + 0.4), sin(a2 + 0.4)) * rng.randf_range(160, 300), 0.6, Color(0.62, 0.42, 0.24), 6.0, 2, 900.0)
	embers(p, 6, EMBER, 150.0, 280.0, 0.6, 4.0)
	glows.append([p, g.t, 110.0 * k])


## 地面根线（缠绕 / 根网的线）：预警时一条褐色根沿线往前爬（越来越粗，节上冒刺），结算时根线整条一绷、崩土
func _rootline_warn(w, t: Dictionary, k: float, sd: int) -> void:
	var a: Vector2 = t.pos
	var d := Vector2.from_angle(float(t.ang))
	var L: float = float(t.len) * clampf(k * 1.25, 0.0, 1.0)
	if L < 3.0:
		return
	var nv := d.orthogonal()
	var n: int = maxi(3, int(L / 16.0))
	var wid0: float = float(t.wid) * (0.3 + 0.35 * k)
	var prev: Vector2 = a - d * 8.0   # 和上一段搭接，不留缝
	var pw: float = wid0
	for i in range(1, n + 1):
		var f: float = float(i) / float(n)
		var q: Vector2 = a + d * L * f + nv * sin(f * 6.0 + float(sd)) * 6.0
		var wid: float = wid0 * (0.85 + 0.25 * sin(f * 9.0 + float(sd % 7)))
		w.tb_circle(prev, (pw + 4.0) * 0.5, ROOT[0], 1.0, 8)   # 圆节盖住折角（不读成木板拼接）
		w.tb_line(prev, q, ROOT[0], wid + 4.0)
		w.tb_circle(prev, pw * 0.5, ROOT[1], 1.0, 8)
		w.tb_line(prev, q, ROOT[1], wid)
		w.tb_line(prev + Vector2(-1, -wid * 0.25), q + Vector2(-1, -wid * 0.25), ROOT[2], maxf(2.0, wid * 0.3))
		pw = wid
		if i % 3 == 0 and k > 0.4:
			var sgn: float = 1.0 if i % 2 == 0 else -1.0
			w.tb_poly(PackedVector2Array([q + nv * wid * 0.4 * sgn, q + nv * (wid + 10.0) * sgn + d * 4.0, q + nv * wid * 0.4 * sgn + d * 6.0]), ROOT[0])
		prev = q
	w.tb_flush()


## 熔岩口：暗色岩环 + 中间熔红光（脉动）+ 偶尔冒火星；喷发预警 = 熔光变亮、裂缝往外爬、冒泡
func _vent_draw(w, cv, p: Vector2, now: float, hot: float) -> void:
	var gt: Texture2D = _glow_tex()
	var pul: float = 0.75 + 0.25 * sin(now * 4.0 + p.x * 0.01)
	var gsz := Vector2(120, 64) * (1.0 + hot)
	cv.draw_texture_rect(gt, Rect2(((p - gsz * 0.5) / PX).floor() * PX, gsz), false, Color(1.0, 0.5, 0.2, (0.35 + 0.4 * hot) * pul))
	var rs: Array = _organic_rs(absi(int(p.x * 7.0 + p.y)) % 997, 16)
	var ring := PackedVector2Array()
	var core := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		ring.append(_snap(p + Vector2(cos(a), sin(a) * 0.6) * 28.0 * float(rs[i])))
		core.append(_snap(p + Vector2(cos(a), sin(a) * 0.6) * 15.0 * float(rs[i]) + Vector2(1, 1)))
	w.tb_polygon(ring, Color(0.18, 0.13, 0.13))
	w.tb_polygon(core, Color(1.0, 0.45 + 0.25 * hot, 0.15).lerp(Color(1, 0.9, 0.6), hot * 0.6))
	w.tb_flush()
	if rng.randf() < 0.06 + 0.5 * hot:
		_add(p + Vector2(rng.randf_range(-8, 8), -4), Vector2(rng.randf_range(-40, 40), -rng.randf_range(60, 160)), 0.6, EMBER, 4.0, 3, 300.0)


func _vine_moves(w, cv, now: float) -> void:
	for id in vine_list.keys():
		var it: Array = vine_list[id]
		var e: Dictionary = it[0]
		if e.dead or absf(now - float(it[1])) > 0.2:
			vine_list.erase(id)
			continue
		for v in e.get("vents", []):
			_vent_draw(w, cv, v, now, 0.0)
		var ms: Array = e.get("mounds", [])
		for i in range(1, ms.size()):
			var a: Dictionary = ms[i - 1]
			var b: Dictionary = ms[i]
			if (a.pos as Vector2).distance_to(b.pos) > 80.0:
				continue   # 另一条根 / 新一轮
			var al: float = clampf((float(b.until) - now) / 0.4, 0.0, 1.0)
			var age_b: float = 1.6 - (float(b.until) - now)
			_mound_ridge(w, a.pos, b.pos, al, int(id) * 13 + i, clampf((age_b - 0.25) / 0.3, 0.0, 1.0))
			if age_b < 0.12 and rng.randf() < 0.8:
				_add(b.pos, Vector2(rng.randf_range(-60, 60), -rng.randf_range(100, 200)), 0.45, A1_LIT if rng.randf() < 0.5 else SOIL[1], rng.randf_range(5.0, 9.0), 3, 700.0)
	w.tb_flush()


func _vine_ground(w, cv, now: float) -> void:
	var keep: Array = []
	for cr in vcraters:
		if now - float(cr[1]) > 2.6:
			continue
		keep.append(cr)
		_crater_draw(w, cv, cr, now)
	vcraters = keep
	w.tb_flush()
	_vine_moves(w, cv, now)


func _vine_front(w, now: float) -> void:
	var keep: Array = []
	for rt in vroots2:
		if now - float(rt[1]) > 1.12:
			continue
		keep.append(rt)
	keep.sort_custom(func(x, y): return (x[0] as Vector2).y < (y[0] as Vector2).y)
	for rt in keep:
		_root2_draw(w, rt, now)
	vroots2 = keep
	w.tb_flush()


## 藤蔓预警（11-28 起挂 sami_blade 自画）：熔岩口 = 熔光变亮 + 熔红裂缝往外爬；破土圈 = 地面拱起、土缝透火光；不伤人的小圈 = 根头土包；线 = 根线往前爬
func _vine_warn2(w, cv, t: Dictionary, k: float, sd: int) -> void:
	var c: Vector2 = t.pos
	var gy: float = g.combat.GROUND_Y
	var ow = t.get("owner")
	var is_vent := false
	if ow is Dictionary:
		for v in ow.get("vents", []):
			if (v as Vector2).distance_to(c) < 4.0:
				is_vent = true
	match t.shape:
		"circle":
			var r: float = float(t.r)
			if is_vent:
				_vent_draw(w, cv, c, g.t, k)
				for i in 7:
					var a: float = TAU * float(i) / 7.0 + float(sd % 5)
					var dv := Vector2(cos(a), sin(a) * gy)
					_crack_col(w, c, dv.angle(), r * dv.length(), clampf(k * 1.2, 0.0, 1.0), sd + i * 3, EMBER, SOIL[0], 4.0)
				return
			if float(t.get("dmg", 0.0)) <= 0.0:
				_mound_ridge(w, c - Vector2(14, 0), c + Vector2(14, 0), 1.0, sd, 0.0)   # 根头土包
				return
			# 破土：地面拱起（背光冷面 + 受光雪顶）、土缝里透火光、雪土往上蹦
			var hv: float = 4.0 + 12.0 * k
			var bump := PackedVector2Array()
			var top := PackedVector2Array()
			for i in 14:
				var a2: float = TAU * float(i) / 14.0
				var q := Vector2(cos(a2), sin(a2) * gy) * r * (0.55 + 0.25 * k)
				bump.append(_snap(c + q))
				top.append(_snap(c + q * 0.7 + Vector2(-q.x * 0.1, -hv)))
			w.tb_polygon(_shift(bump, Vector2(3, 4)), Color(A1_SH, 0.5))
			w.tb_polygon(bump, A1_BACK)
			w.tb_polygon(top, A1_LIT)
			for i in 4:
				var a3: float = float(sd % 6) + TAU * float(i) / 4.0
				var q0: Vector2 = c + Vector2(0, -hv)
				var q1: Vector2 = q0 + Vector2(cos(a3), sin(a3) * gy) * r * 0.5 * k
				w.tb_line(_snap(q0), _snap(q1), SOIL[0], 6.0)
				w.tb_line(_snap(q0), _snap(q1), EMBER, 2.0)
			w.tb_flush()
			if rng.randf() < 0.3 + 0.6 * k:
				_add(c + Vector2(rng.randf_range(-r, r) * 0.4, -hv), Vector2(rng.randf_range(-30, 30), -rng.randf_range(60, 140)), 0.4, A1_LIT if rng.randf() < 0.5 else SOIL[1], 5.0, 3, 600.0)
		"line":
			if float(t.get("dmg", 0.0)) > 0.0:
				_rootline_warn(w, t, k, sd)


func _vine_wburst(t: Dictionary) -> void:
	var c: Vector2 = t.pos
	var ow = t.get("owner")
	if t.shape == "circle":
		var is_vent := false
		if ow is Dictionary:
			for v in ow.get("vents", []):
				if (v as Vector2).distance_to(c) < 4.0:
					is_vent = true
		if is_vent:
			# 熔岩喷发：熔红火柱一冲（火星 + 熔块 + 一下亮光）
			embers(c, 18, EMBER, 260.0, 360.0, 0.8, 5.0)
			embers(c, 8, Color(1.0, 0.85, 0.5), 200.0, 300.0, 0.6, 4.0)
			sparks(c + Vector2(0, -20), -PI * 0.5, 0.7, 16, 420.0, [Color(1, 0.95, 0.7), EMBER, Color(0.85, 0.3, 0.1), SOIL[0]], true, 0.4)
			glows.append([c, g.t, 160.0])
			return
		vine_surface(c, float(t.r), float(t.r) >= 55.0)
	elif t.shape == "line":
		var d := Vector2.from_angle(float(t.ang))
		for i in 6:
			var q: Vector2 = c + d * float(t.len) * rng.randf()
			_add(q, Vector2(rng.randf_range(-80, 80), -rng.randf_range(80, 180)), 0.5, SOIL[rng.randi() % 3], rng.randf_range(4.0, 9.0), 3, 900.0)


## ==== 意志新判定三项（11-28 协调人，fm_w3 / fm_w4）：雪浪 = 整块往前滚的积雪墙；暴风雪 = 横向狂风雪带（压暗 + 飞雪条纹 + 冰屑，半场边界一眼看清）；
## 三幕北侧雪幕 = 持续雪墙 / 白雾，边界清楚。银凇阴影里断开（安全）
func _will_arena(e: Dictionary) -> Dictionary:
	var sc = g.bai.boss("will")
	return {"n": float(sc._north(e)), "s": float(sc._south(e)), "c": sc.center(e) as Vector2, "ar": float(sc._ar(e))}


func _tree_shade(e: Dictionary, x: float, y: float) -> bool:
	for t2 in e.get("trees", []):
		if float(t2.dead_t) <= 0.0 and absf(x - (t2.pos as Vector2).x) < 46.0 and y > (t2.pos as Vector2).y:
			return true
	return false


## 雪浪：楔形 60°，前沿半径 fr（40 → 600，150 px/秒）。前沿 = 一堵往前滚的积雪墙（背光正面 + 受光翻卷顶 + 顶上卷起的雪团），
## 墙后是被推平的雪面（淡），墙前 20–70 地面先裂开，前沿往前抛雪块
func _will_wave(w, cv, e: Dictionary, now: float) -> void:
	var sw = e.get("swave")
	if not (sw is Dictionary):
		return
	var fr: float = 40.0 + (now - float(sw.t0)) * 150.0
	if fr > 600.0:
		return
	var o: Vector2 = sw.o
	var a: float = float(sw.a)
	var gy: float = g.combat.GROUND_Y
	var half: float = PI / 6.0
	var n: int = clampi(int(2.0 * half * fr / 22.0), 6, 60)
	_fin_tex()
	# 墙后推平的雪面：一条淡雪带
	for i in n:
		var b0: float = a - half + 2.0 * half * float(i) / float(n)
		var b1: float = a - half + 2.0 * half * float(i + 1) / float(n)
		var q0: Vector2 = o + Vector2(cos(b0), sin(b0) * gy) * fr
		if _tree_shade(e, q0.x, q0.y):
			continue
		var q1: Vector2 = o + Vector2(cos(b1), sin(b1) * gy) * fr
		var p0: Vector2 = o + Vector2(cos(b0), sin(b0) * gy) * maxf(30.0, fr - 140.0)
		var p1: Vector2 = o + Vector2(cos(b1), sin(b1) * gy) * maxf(30.0, fr - 140.0)
		w.tb_quad(p0, p1, q1, q0, Color(A1_LIT, 0.35))
	w.tb_flush()
	# 墙前地面裂开（短裂缝往前爬）
	for i in range(0, n, 2):
		var b: float = a - half + 2.0 * half * (float(i) + 0.5) / float(n)
		var q: Vector2 = o + Vector2(cos(b), sin(b) * gy) * (fr + 14.0)
		if _tree_shade(e, q.x, q.y):
			continue
		var dv := Vector2(cos(b), sin(b) * gy)
		_crack_col(w, q, dv.angle() + float((i * 7) % 5 - 2) * 0.12, 40.0 + float((i * 13) % 4) * 10.0, clampf((fr - 40.0) / 60.0, 0.0, 1.0), i * 17 + int(fr / 60.0), A1_BACK, A1_SH, 4.0)
	w.tb_flush()
	# 积雪墙：每格一段——背光正面（冷暗）+ 受光顶（亮）+ 顶上卷起的雪团（雪雾贴图），起伏
	for i in n:
		var b: float = a - half + 2.0 * half * (float(i) + 0.5) / float(n)
		var q: Vector2 = o + Vector2(cos(b), sin(b) * gy) * fr
		if _tree_shade(e, q.x, q.y):
			continue
		var hh: float = 58.0 + 14.0 * sin(float(i) * 1.7 + now * 6.0) + 8.0 * sin(float(i) * 0.6 - now * 3.0)
		var wd: float = 2.0 * half * fr / float(n) * 0.62 + 4.0
		var tng := Vector2(-sin(b), cos(b) * gy).normalized()
		w.tb_quad(_snap(q - tng * wd + Vector2(0, 4)), _snap(q + tng * wd + Vector2(0, 4)), _snap(q + tng * wd + Vector2(0, -hh * 0.55)), _snap(q - tng * wd + Vector2(0, -hh * 0.55)), A1_BACK)
		w.tb_quad(_snap(q - tng * wd + Vector2(0, -hh * 0.5)), _snap(q + tng * wd + Vector2(0, -hh * 0.5)), _snap(q + tng * wd * 0.8 + Vector2(0, -hh)), _snap(q - tng * wd * 0.8 + Vector2(0, -hh)), A1_LIT)
	w.tb_flush()
	for i in n:
		var b: float = a - half + 2.0 * half * (float(i) + 0.5) / float(n)
		var q: Vector2 = o + Vector2(cos(b), sin(b) * gy) * fr
		if _tree_shade(e, q.x, q.y):
			continue
		var hh: float = 58.0 + 14.0 * sin(float(i) * 1.7 + now * 6.0)
		var sz: float = 80.0 + float((i * 37) % 40)
		cv.draw_texture_rect(snow_puff, Rect2(_snap(q + Vector2(-sz * 0.5, -hh - sz * 0.5)), Vector2(sz, sz * 0.7)), false, Color(1, 1, 1, 0.95))   # 翻卷顶
		var sz2: float = sz * 0.7
		var curl: float = fposmod(now * 2.5 + float(i) * 0.37, 1.0)   # 卷起的雪团从顶往前翻落
		cv.draw_texture_rect(snow_puff, Rect2(_snap(q + Vector2(cos(b), sin(b) * gy) * 20.0 * curl + Vector2(-sz2 * 0.5, -hh * (1.0 - curl * 0.6) - sz2 * 0.4)), Vector2(sz2, sz2 * 0.7)), false, Color(1, 1, 1, 0.8 * (1.0 - curl)))
		if rng.randf() < 0.18:
			var dv2 := Vector2(cos(b), sin(b) * gy)
			_add(q + Vector2(0, -hh), dv2 * rng.randf_range(80, 200) + Vector2(0, -rng.randf_range(80, 200)), rng.randf_range(0.5, 0.8), A1_LIT if rng.randf() < 0.6 else Color(0.78, 0.87, 0.92), rng.randf_range(6.0, 12.0), 3, 800.0)


## 暴风雪地面层（单位之下）：风雪带范围（北 → 前沿 y）整片压暗 + 横向飞雪条纹往风向刮；3 条缝和银凇阴影里不压（安全道一眼看清）
func _will_storm_ground(w, cv, e: Dictionary, bz: Dictionary, y: float, now: float) -> void:
	var ar_d: Dictionary = _will_arena(e)
	var x0: float = (ar_d.c as Vector2).x - float(ar_d.ar) * 3.0   # 左右 / 北边都铺出画面外，不露矩形边
	var x1: float = (ar_d.c as Vector2).x + float(ar_d.ar) * 3.0
	var yn: float = float(ar_d.n) - 900.0
	# 按 16 宽一列压暗；缝 / 银凇阴影附近按距离渐淡（软边），缝中心完全不压
	var x: float = x0
	while x < x1:
		var xm: float = x + 8.0
		var ga: float = 1.0
		for gx in bz.gaps:
			ga = minf(ga, clampf((absf(xm - float(gx)) - 40.0) / 24.0, 0.0, 1.0))
		var y_cut: float = y + 9.0 * sin(xm * 0.025 + now * 2.1) + 6.0 * sin(xm * 0.061 - now * 3.3)   # 前沿起伏（和雪墙同相）
		for t2 in e.get("trees", []):
			if float(t2.dead_t) <= 0.0 and absf(xm - (t2.pos as Vector2).x) < 46.0:
				y_cut = minf(y_cut, (t2.pos as Vector2).y)
		if ga > 0.0:
			w.tb_quad(Vector2(x, yn), Vector2(x + 16.0, yn), Vector2(x + 16.0, y_cut), Vector2(x, y_cut), Color(0.2, 0.28, 0.4, 0.38 * ga))
		x += 16.0
	w.tb_flush()
	# 横向飞雪条纹：一批按哈希定位的短粗条，往东南刮（风 (+1, 0.12)），循环
	var area_h: float = maxf(0.0, y - yn)
	var ns: int = clampi(int(area_h * (x1 - x0) / 2600.0), 0, 260)
	for i in ns:
		var hs: int = absi(hash(Vector2i(i, 4417)))
		var spd: float = 520.0 + float(hs % 300)
		var px: float = x0 + fposmod(float(hs % 2000) / 2000.0 * (x1 - x0) + now * spd, x1 - x0)
		var py: float = yn + float((hs / 2000) % 1000) / 1000.0 * area_h + (px - x0) * 0.12 * 0.15
		var gap2 := false
		for gx in bz.gaps:
			if absf(px - float(gx)) < 45.0:
				gap2 = true
		if gap2 or py > y or _tree_shade(e, px, py):
			continue
		var ln: float = 18.0 + float(hs % 30)
		var col: Color = Color(0.92, 0.96, 1.0, 0.55 + 0.35 * float((hs / 7) % 3) / 2.0)
		w.tb_line(_snap(Vector2(px, py)), _snap(Vector2(px + ln, py + ln * 0.12)), col, 2.0 if hs % 3 else 4.0)
		if hs % 11 == 0:
			cv.draw_rect(Rect2(_snap(Vector2(px + ln, py)), Vector2(4, 4)), Color(0.75, 0.88, 1.0))   # 冰屑
	w.tb_flush()


## 三幕北侧雪幕：北 1/3 一直是白雾雪墙——范围内提白（冷白雾）+ 斜飘雪条，边界一排翻滚的密雪团 + 受光雪檐（清楚的边）；银凇阴影列不罩
func _will_curtain_ground(w, cv, e: Dictionary, now: float) -> void:
	if int(e.get("gates_passed", 0)) < 2:
		return
	var ar_d: Dictionary = _will_arena(e)
	var cy: float = float(ar_d.n) + (float(ar_d.s) - float(ar_d.n)) / 3.0
	var x0: float = (ar_d.c as Vector2).x - float(ar_d.ar) * 3.0
	var x1: float = (ar_d.c as Vector2).x + float(ar_d.ar) * 3.0
	var yn: float = float(ar_d.n) - 900.0
	var x: float = x0
	while x < x1:
		var xm: float = x + 12.0
		var y_cut: float = cy + 6.0 * sin(xm * 0.03 + now * 1.4)
		for t2 in e.get("trees", []):
			if float(t2.dead_t) <= 0.0 and absf(xm - (t2.pos as Vector2).x) < 46.0:
				y_cut = minf(y_cut, (t2.pos as Vector2).y)
		w.tb_quad(Vector2(x, yn), Vector2(x + 24.0, yn), Vector2(x + 24.0, y_cut), Vector2(x, y_cut), Color(0.88, 0.94, 1.0, 0.42))
		x += 24.0
	w.tb_flush()
	var area_h: float = cy - yn
	for i in 420:
		var hs: int = absi(hash(Vector2i(i, 6113)))
		var px: float = x0 + fposmod(float(hs % 2000) / 2000.0 * (x1 - x0) + now * (120.0 + float(hs % 80)), x1 - x0)
		var py: float = yn + fposmod(float((hs / 2000) % 1000) / 1000.0 * area_h + now * (60.0 + float(hs % 40)), area_h)
		if _tree_shade(e, px, py):
			continue
		w.tb_line(_snap(Vector2(px, py)), _snap(Vector2(px + 10.0, py + 6.0)), Color(1, 1, 1, 0.7), 2.0)
	w.tb_flush()


func _will_curtain_front(w, cv, e: Dictionary, now: float) -> void:
	if int(e.get("gates_passed", 0)) < 2:
		return
	_fin_tex()
	var ar_d: Dictionary = _will_arena(e)
	var cy: float = float(ar_d.n) + (float(ar_d.s) - float(ar_d.n)) / 3.0
	var x: float = (ar_d.c as Vector2).x - float(ar_d.ar) * 3.0
	var x1: float = (ar_d.c as Vector2).x + float(ar_d.ar) * 3.0
	# 雪檐下沿一道连续冷影（边界清楚，不断成虚线）
	var xs: float = x
	var prev := Vector2.INF
	while xs <= x1:
		var ys: float = cy + 6.0 * sin(xs * 0.03 + now * 1.4) + 4.0 * sin(xs * 0.07 - now * 2.2)
		var q := Vector2(xs, ys + 2.0)
		if prev != Vector2.INF and not _tree_shade(e, xs, ys - 1.0):
			w.tb_line(_snap(prev), _snap(q), Color(A1_BACK, 0.75), 5.0)
		prev = q
		xs += 12.0
	w.tb_flush()
	var col := 0
	while x <= x1:
		var hj: int = absi(hash(Vector2i(col, 733)))
		var yy: float = cy + 6.0 * sin(x * 0.03 + now * 1.4) + 4.0 * sin(x * 0.07 - now * 2.2)
		if not _tree_shade(e, x, yy - 1.0):
			var sz: float = 70.0 + float(hj % 40)
			cv.draw_texture_rect(snow_puff, Rect2(_snap(Vector2(x - sz * 0.5, yy - sz * 0.75)), Vector2(sz, sz * 0.75)), false, Color(1, 1, 1, 0.95))
			if rng.randf() < 0.04:
				_icefog(Vector2(x, yy), Vector2(rng.randf_range(-20, 20), 20), 0.8, 50.0, 0.7)
		x += 36.0 + float(hj % 14)
		col += 1
	w.tb_flush()


## ==== 利刃 v3（协调人 11-28）：大横斩刀带扫过后残留 0.35 秒再碎散、地上留弧形斩痕 1.5 秒；旋身斩 = 一整圈刀带；三段突进留黑色残影 + 斩痕；
## 猎斩 = 贴地飞行的窄斩波；国度 = 成团墨状黑雾（大团缓慢翻涌、边缘烟丝），不再格子短线
var barcs: Array = []   # 地上弧形斩痕 [圆心, a0, a1, R, 出生 t]


## 刀带（大横斩 / 收尾斩 / 旋身斩共用）：half = 半张角（旋身斩 PI = 一整圈），sweep = 扫过用时
func _big_slash2(w, cv, p: Vector2, ca: float, SR: float, age: float, half: float, sweep: float) -> void:
	var e0: float = ca - half - 0.12
	var e1: float = ca + half + 0.12
	var hd: float = lerpf(e0, e1, 1.0 - pow(1.0 - clampf(age / sweep, 0.0, 1.0), 2.0))
	var hold_end: float = sweep + 0.35
	var tl: float = lerpf(e0, e1, clampf((age - hold_end) / 0.25, 0.0, 1.0))
	if hd - tl < 0.03:
		return
	var R: float = SR
	var fade: float = clampf((age - hold_end) / 0.3, 0.0, 1.0)
	var hp: Vector2 = p + Vector2.from_angle(hd) * (R - 20.0)
	var gt: Texture2D = _glow_tex()
	if age < hold_end:
		cv.draw_texture_rect(gt, Rect2(((hp - Vector2(80, 46)) / PX).floor() * PX, Vector2(160, 92)), false, Color(1.0, 0.32, 0.26, 0.24))
	var ns: int = clampi(int((e1 - e0) * 14.0), 26, 90)
	var tm: float = 0.42 * R / 0.47
	for pass_i in 4:
		for j in ns:
			var f0: float = float(j) / float(ns)
			var f1: float = float(j + 1) / float(ns)
			var b0: float = lerpf(e0, e1, f0)
			var b1: float = lerpf(e0, e1, f1)
			if b1 < tl or b0 > hd:
				continue
			b0 = maxf(b0, tl)
			b1 = minf(b1, hd)
			var t0: float = (4.0 + tm * pow(f0, 1.2) * pow(1.0 - f0, 0.3)) if half < 3.0 else (tm * 0.55)
			var t1: float = (4.0 + tm * pow(f1, 1.2) * pow(1.0 - f1, 0.3)) if half < 3.0 else (tm * 0.55)
			if half >= 3.0:   # 一整圈：刀头附近厚、往后渐薄
				var dh0: float = clampf((hd - b0) / 2.2, 0.0, 1.0)
				var dh1: float = clampf((hd - b1) / 2.2, 0.0, 1.0)
				t0 = 4.0 + tm * 0.6 * (1.0 - dh0)
				t1 = 4.0 + tm * 0.6 * (1.0 - dh1)
			t0 *= 1.0 - 0.6 * fade
			t1 *= 1.0 - 0.6 * fade
			var ro: float = R
			var r0i: float = R - t0
			var r1i: float = R - t1
			var cc: Color
			match pass_i:
				0:
					ro = R + 3.0
					r0i -= 3.0
					r1i -= 3.0
					cc = OLC
				1:
					cc = BK
				2:
					r0i = R - t0 * 0.3
					r1i = R - t1 * 0.3
					cc = BLOOD[1].lerp(BLOOD[2], f0)
				_:
					r0i = R - 4.0 - 5.0 * f0
					r1i = R - 4.0 - 5.0 * f1
					cc = Color(1.0, 1.0, 0.97)
			if fade > 0.0:
				cc.a = 1.0 - fade
			w.tb_quad(p + Vector2.from_angle(b0) * ro, p + Vector2.from_angle(b1) * ro, p + Vector2.from_angle(b1) * r1i, p + Vector2.from_angle(b0) * r0i, cc)
	if age < sweep + 0.1:
		for i in 3:
			var bq: float = lerpf(tl, hd, rng.randf() * 0.8)
			_fog(p + Vector2.from_angle(bq) * (R - 30.0), 1, 0.8, 0.0, false, 2.2, Vector2.from_angle(bq) * 60.0 + Vector2.from_angle(bq - PI * 0.5) * 40.0)
		sparks(hp, hd + PI * 0.5, 0.6, 3, 320.0, [Color(1, 0.96, 0.9), Color(1.0, 0.62, 0.3), BLOOD[3], BLOOD[2]], true, 0.3)
	elif age > hold_end and age < hold_end + 0.25:
		# 碎散：尾巴追上时刀带一段段崩成黑红碎片往外落
		for i in 4:
			var bq2: float = tl + rng.randf_range(-0.05, 0.15)
			var q: Vector2 = p + Vector2.from_angle(bq2) * (R - rng.randf_range(4.0, tm * 0.4))
			_add(q, Vector2.from_angle(bq2) * rng.randf_range(40, 140) + Vector2(0, -rng.randf_range(20, 80)), rng.randf_range(0.4, 0.7), [BK, BK, BLOOD[1], BLOOD[2]][i], rng.randf_range(5.0, 10.0), 3, 500.0)


## 地上弧形斩痕：黑底 + 暗红芯，锯齿边，1.5 秒淡掉
func _draw_barcs(w, now: float) -> void:
	if barcs.is_empty():
		return
	var keep: Array = []
	for b in barcs:
		var age: float = now - float(b[4])
		if age > 1.5:
			continue
		keep.append(b)
		var al: float = clampf((1.5 - age) / 0.6, 0.0, 1.0)
		var c: Vector2 = b[0]
		var a0: float = b[1]
		var a1: float = b[2]
		var R: float = float(b[3]) * 0.9
		var ns: int = clampi(int((a1 - a0) * R / 18.0), 8, 90)
		for j in ns:
			var f0: float = float(j) / float(ns)
			var f1: float = float(j + 1) / float(ns)
			var b0: float = lerpf(a0, a1, f0)
			var b1: float = lerpf(a0, a1, f1)
			var th0: float = (6.0 + 12.0 * sin(PI * f0)) * (0.7 + 0.3 * float(absi(hash(Vector2i(j, int(c.x)))) % 10) / 10.0)
			var th1: float = (6.0 + 12.0 * sin(PI * f1)) * (0.7 + 0.3 * float(absi(hash(Vector2i(j + 1, int(c.x)))) % 10) / 10.0)
			if a1 - a0 > 5.0:
				th0 = 12.0
				th1 = 12.0
			w.tb_quad(c + Vector2.from_angle(b0) * (R + th0 * 0.5), c + Vector2.from_angle(b1) * (R + th1 * 0.5), c + Vector2.from_angle(b1) * (R - th1 * 0.5), c + Vector2.from_angle(b0) * (R - th0 * 0.5), Color(BK, 0.9 * al))
			w.tb_quad(c + Vector2.from_angle(b0) * (R + th0 * 0.12), c + Vector2.from_angle(b1) * (R + th1 * 0.12), c + Vector2.from_angle(b1) * (R - th1 * 0.12), c + Vector2.from_angle(b0) * (R - th0 * 0.12), Color(BLOOD[2], al * (0.6 + 0.4 * sin(now * 16.0 + float(j)))))
	barcs = keep
	w.tb_flush()


## 三段突进的残影：沿冲刺路线一条从后往前变宽的黑影（像刀身拖过去），0.5 秒淡掉，路上翻黑雾
func _dash_ghost(w, ev: Array, age: float) -> void:
	var a: Vector2 = ev[1]
	var d := Vector2.from_angle(float(ev[2]))
	var L: float = float(ev[5])
	var nv := d.orthogonal()
	var al: float = clampf(1.0 - age / 0.5, 0.0, 1.0)
	for k in 3:
		var sh: float = float(k) * 0.33
		var b: Vector2 = a + d * L * (0.35 + 0.65 * (1.0 - sh))
		var a2: Vector2 = a + d * L * (0.05 + 0.2 * sh)
		var wd: float = 26.0 * (1.0 - sh * 0.4)
		w.tb_poly(PackedVector2Array([a2 + Vector2(0, -28), b + nv * wd + Vector2(0, -30), b + d * 18.0 + Vector2(0, -34), b - nv * wd + Vector2(0, -30)]), Color(BK, (0.45 - 0.12 * float(k)) * al))
	w.tb_line(_snap(a + Vector2(0, -30)), _snap(a + d * L + Vector2(0, -32)), Color(BLOOD[2], 0.7 * al), 3.0)


## 猎斩斩波：贴地飞的一道窄月牙（黑刃 + 暗红芯 + 白刃口朝前），后面拖一条渐淡黑痕
func _redslash2(w, x: Dictionary, u: float, first: bool) -> void:
	var p: Vector2 = x.pos
	var d := Vector2.from_angle(float(x.ang))
	var nv := d.orthogonal()
	var L: float = float(x.r)
	if first:
		bscars.append([p + d * 10.0, p + d * L, g.t, 26.0, rng.randi() % 997])
		sparks(p, float(x.ang), 0.5, 10, 380.0, [Color(1, 0.95, 0.92), BLOOD[3], BLOOD[2], BLOOD[1]], true, 0.3)
	var hu: float = clampf(u * 1.15, 0.0, 1.0)
	var h: Vector2 = p + d * L * hu
	var tail: Vector2 = p + d * L * maxf(0.0, hu - 0.35)
	var al: float = clampf((1.0 - u) / 0.3, 0.0, 1.0)
	w.tb_poly(PackedVector2Array([tail, h + nv * 10.0, h - nv * 10.0]), Color(BK, 0.6 * al))
	var W := 38.0
	var back: float = 16.0
	var pts_o := PackedVector2Array([h + nv * (W + 3.0) - d * (back + 3.0), h + d * 6.0, h - nv * (W + 3.0) - d * (back + 3.0), h - d * 4.0])
	var pts := PackedVector2Array([h + nv * W - d * back, h + d * 3.0, h - nv * W - d * back, h - d * 1.0])
	w.tb_poly(pts_o, Color(OLC, al))
	w.tb_poly(pts, Color(BK, al))
	w.tb_poly(PackedVector2Array([h + nv * W * 0.6 - d * back * 0.6, h + d * 2.0, h - nv * W * 0.6 - d * back * 0.6, h]), Color(BLOOD[2], al))
	w.tb_line(_snap(h + nv * W * 0.8 - d * back * 0.55), _snap(h + d * 3.0), Color(1, 1, 0.97, al), 2.0)
	w.tb_line(_snap(h - nv * W * 0.8 - d * back * 0.55), _snap(h + d * 3.0), Color(1, 1, 0.97, al), 2.0)


## 国度：成团墨状黑雾（fm_b1）——每块国度几团大雾缓慢翻涌（位置转、大小呼吸），边缘烟丝往外飘散；黑毯 / 连片沿线铺雾团
func _kd_ink(cv, km, now: float) -> void:
	var vr: Rect2 = Rect2(g.cam.position - get_viewport_half() - Vector2(200, 200), get_viewport_half() * 2.0 + Vector2(400, 400))
	for k in km.list:
		if k.kind == "nursery":
			continue
		var age: float = now - float(k.born)
		var fade: float = 1.0
		if float(k.life) > 0.0:
			fade = clampf((float(k.born) + float(k.life) - now) / 0.6, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var rev: float = clampf(age / 0.6, 0.0, 1.0)
		var al: float = fade * rev
		var r: float = float(k.r)
		var sd: int = absi(hash(Vector2i(int(k.pos.x), int(k.pos.y)))) % 9973
		if k.has("b"):
			var L: float = (k.pos as Vector2).distance_to(k.b)
			var n2: int = maxi(2, int(L / 40.0))
			for i in n2 + 1:
				var q: Vector2 = (k.pos as Vector2).lerp(k.b, float(i) / float(n2))
				if not vr.has_point(q):
					continue
				var s2: float = r * 2.2 * (0.85 + 0.25 * sin(now * 0.7 + float(i)))
				cv.draw_texture_rect(fog_puff[(i + sd) % 4], Rect2(_snap(q - Vector2(s2, s2 * 0.75) * 0.5), Vector2(s2, s2 * 0.75)), false, Color(1, 1, 1, 0.55 * KD_WISP * al))
			continue
		if not vr.grow(r).has_point(k.pos):
			continue
		var n: int = clampi(int(r * r / 1600.0), 3, 14)
		for i in n:
			var hs: int = absi(hash(Vector2i(sd, i)))
			var a: float = float(hs % 628) / 100.0 + now * (0.1 + 0.05 * float(hs % 3)) * (1.0 if hs % 2 == 0 else -1.0)
			var rr: float = r * 0.62 * sqrt(float((hs / 628) % 100) / 100.0) * rev
			var q2: Vector2 = (k.pos as Vector2) + Vector2(cos(a), sin(a) * 0.75) * rr
			var s: float = r * (1.15 + 0.45 * float((hs / 62800) % 100) / 100.0) * (0.92 + 0.12 * sin(now * 0.9 + float(i) * 1.3))
			if km._in_cut(q2):
				continue
			cv.draw_texture_rect(fog_puff[hs % 4], Rect2(_snap(q2 - Vector2(s, s * 0.75) * 0.5), Vector2(s, s * 0.75)), false, Color(1, 1, 1, 0.85 * KD_WISP * al))
		# 边缘烟丝：小雾团从边上往外飘、变淡（循环）
		var m: int = clampi(int(TAU * r / 22.0), 8, 40)
		for i in m:
			var hs2: int = absi(hash(Vector2i(sd + 9, i)))
			var ph: float = fmod(now * (0.35 + float(hs2 % 20) / 100.0) + float(hs2 % 100) / 100.0, 1.0)
			var a2: float = TAU * float(i) / float(m) + float(hs2 % 50) / 100.0
			var q3: Vector2 = (k.pos as Vector2) + Vector2(cos(a2), sin(a2) * 0.75) * r * (0.8 + 0.35 * ph) * rev + Vector2(0, -16.0 * ph)
			var s3: float = (26.0 + float(hs2 % 20)) * (1.0 - 0.4 * ph)
			cv.draw_texture_rect(fog_puff[(hs2 / 3) % 4], Rect2(_snap(q3 - Vector2(s3, s3 * 0.8) * 0.5), Vector2(s3, s3 * 0.8)), false, Color(1, 1, 1, 0.55 * KD_WISP * al * (1.0 - ph)))
	for l in km.links:
		var a3: Vector2 = l[0].pos
		var b3: Vector2 = l[1].pos
		var n3: int = maxi(2, int(a3.distance_to(b3) / 50.0))
		for i in n3:
			var q4: Vector2 = a3.lerp(b3, (float(i) + 0.5) / float(n3))
			var s4: float = float(l[2]) * 2.0
			cv.draw_texture_rect(fog_puff[i % 4], Rect2(_snap(q4 - Vector2(s4, s4 * 0.75) * 0.5), Vector2(s4, s4 * 0.75)), false, Color(1, 1, 1, 0.45 * KD_WISP))


func _ice_peak(w, p: Vector2, h: float, wd: float) -> void:
	if h < 2.0:
		return
	var hw: float = wd * 0.5
	w.tb_poly(PackedVector2Array([p + Vector2(-hw - 3, 3), p + Vector2(-hw * 0.4, -h * 0.75), p + Vector2(0, -h - 4), p + Vector2(hw * 0.3, -h * 0.6), p + Vector2(hw * 0.7, -h * 0.4), p + Vector2(hw + 3, 3)]), WILLC[0])
	w.tb_poly(PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(-hw * 0.4, -h * 0.75), p + Vector2(0, -h), p + Vector2(-hw * 0.05, 0)]), WILLC[1])
	w.tb_poly(PackedVector2Array([p + Vector2(-hw * 0.05, 0), p + Vector2(0, -h), p + Vector2(hw * 0.3, -h * 0.6), p + Vector2(hw * 0.7, -h * 0.4), p + Vector2(hw, 0)]), WILLC[2])
	w.tb_poly(PackedVector2Array([p + Vector2(hw * 0.3, -h * 0.6), p + Vector2(hw * 0.7, -h * 0.4), p + Vector2(hw * 0.45, -h * 0.3)]), WILLC[3])
	w.tb_line(_snap(p + Vector2(-2, -h * 0.2)), _snap(p + Vector2(0, -h * 0.85)), WILLC[3], 2.0)


## 长冬冰柱（木裂）：深青冰柱（六棱，两面明暗 + 冰白棱线），顶上积雪
func _ice_pillar(w, p: Vector2, h: float, wd: float) -> void:
	if h < 2.0:
		return
	var hw: float = wd * 0.5
	var sd: int = absi(hash(Vector2i(int(p.x), int(p.y)))) % 97
	# 落影 + 底部碎冰
	w.tb_quad(_snap(p + Vector2(-hw - 10, -2)), _snap(p + Vector2(hw + 14, -2)), _snap(p + Vector2(hw + 10, 5)), _snap(p + Vector2(-hw - 6, 5)), Color(0.1, 0.16, 0.2, 0.45))
	# 暗描边（略收的上端 + 不齐的冰凌顶）
	var top := [Vector2(-hw, -h + 2), Vector2(-hw * 0.5, -h - 8), Vector2(0, -h - 2), Vector2(hw * 0.45, -h - 12), Vector2(hw, -h)]
	var outl := PackedVector2Array([p + Vector2(-hw - 4, 3)])
	for q in top:
		outl.append(p + q * Vector2(1.12, 1.0) + Vector2(0, -3))
	outl.append(p + Vector2(hw + 4, 3))
	w.tb_poly(outl, OLC)
	# 木芯暗面（左）/ 冰壳亮面（右）
	w.tb_poly(PackedVector2Array([p + Vector2(-hw, 0), p + Vector2(-hw, -h + 2), p + Vector2(-hw * 0.5, -h - 8), p + Vector2(-hw * 0.05, -h - 3), p + Vector2(-hw * 0.05, 0)]), Color(0.16, 0.2, 0.2))
	w.tb_poly(PackedVector2Array([p + Vector2(-hw * 0.05, 0), p + Vector2(-hw * 0.05, -h - 3), p + Vector2(hw * 0.45, -h - 12), p + Vector2(hw, -h), p + Vector2(hw, 0)]), TEALC[3])
	w.tb_poly(PackedVector2Array([p + Vector2(hw * 0.45, -2), p + Vector2(hw * 0.45, -h - 10), p + Vector2(hw, -h), p + Vector2(hw, -2)]), Color(0.55, 0.85, 0.78))
	# 木纹竖线（暗面）
	for i in 2:
		var xx: float = -hw * (0.75 - 0.35 * float(i))
		w.tb_line(_snap(p + Vector2(xx, -4)), _snap(p + Vector2(xx + 1.0, -h + 6)), Color(0.08, 0.1, 0.1), 2.0)
	# 横向冰裂（按种子错开高度）
	for i in 3:
		var yy: float = -h * (0.25 + 0.22 * float(i)) - float((sd + i * 13) % 7)
		var x0: float = -hw * 0.05
		_crack_col(w, p + Vector2(x0, yy), -0.15 + 0.3 * float((sd + i) % 2), hw * 0.95, 1.0, sd + i * 5, Color(0.9, 1.0, 0.98), OLC, 2.0)
	# 顶上积雪 + 冰凌
	w.tb_poly(PackedVector2Array([p + Vector2(-hw * 1.05, -h + 3), p + Vector2(-hw * 0.5, -h - 9), p + Vector2(0, -h - 4), p + Vector2(hw * 0.45, -h - 13), p + Vector2(hw * 1.05, -h + 1), p + Vector2(0, -h + 4)]), ICEL[0])
	for i in 3:
		var ix: float = -hw * 0.6 + hw * 0.6 * float(i)
		w.tb_poly(PackedVector2Array([p + Vector2(ix - 3, -h + 3), p + Vector2(ix + 3, -h + 3), p + Vector2(ix, -h + 12 + float((sd + i) % 3) * 3.0)]), ICEL[1])
	# 底部一圈碎冰块
	for i in 3:
		_ice_chunk(w, p + Vector2(-hw - 4 + (hw + 4) * float(i), 2), p.y + 2.0, 5.0, float(sd + i), 1.0)


## 寒冷条 / 冻结（themes/sami/mech/mech_cold.draw_ground 调，协调人 11-26：脚下细弧 / 冻结细圈读成白细圆）：
## 寒冷值 = 脚下一段连续霜带弧（冰带贴图，宽 6）；冻结 = 队长身上罩一块冰壳（冰晶块 + 霜点，不画圈）
func cold_draw(cold: float, frozen: float) -> void:
	_fin_tex()
	var cv = g.wcv
	var gy: float = g.combat.GROUND_Y
	var p: Vector2 = g.ppos + Vector2(0, 6)
	var k: float = clampf(cold / 100.0, 0.0, 1.0)
	var n: int = int(24.0 * k)
	for i in n:
		var a0: float = -PI * 0.5 + TAU * float(i) / 24.0
		var a1: float = -PI * 0.5 + TAU * float(i + 1) / 24.0
		_band_tex(cv, ice_band, _gpoly_ring(p, 26.0, gy, a0), _gpoly_ring(p, 26.0, gy, a1), 6.0, 0.95)
	if frozen > 0.0:
		frozen_shell = frozen


var frozen_shell := 0.0


func _frozen_front(w) -> void:
	if frozen_shell <= 0.0 or g.frozen_t <= 0.0:
		frozen_shell = 0.0
		return
	var p: Vector2 = g.ppos
	for q in [[Vector2(-14, -6), 13.0, 0.3], [Vector2(12, -12), 15.0, 1.4], [Vector2(-4, -34), 14.0, 2.2], [Vector2(10, -42), 10.0, 0.9], [Vector2(-12, -52), 9.0, 2.8]]:
		_ice_chunk(w, p + q[0], p.y + q[0].y, float(q[1]), float(q[2]), 0.85)
	if rng.randf() < 0.3:
		_icefog(p + Vector2(rng.randf_range(-16, 16), -10), Vector2(0, -12), 0.6, 24.0, 0.6)


## 自然涌动：被冻住的队友罩在一块冰壳里（冰白半透 + 暗紫边），金色描边 + 心跳 = 冲过去救
func _ice_shell(w, p: Vector2, now: float) -> void:
	var shell := PackedVector2Array([p + Vector2(-22, 4), p + Vector2(-26, -30), p + Vector2(-10, -56), p + Vector2(8, -60), p + Vector2(24, -36), p + Vector2(22, 4)])
	_gold_beat(w, shell, p + Vector2(0, -28), now)
	var big := PackedVector2Array()
	for q in shell:
		big.append(p + Vector2(0, -28) + (q - p - Vector2(0, -28)) * 1.06)
	w.tb_poly(big, WILLC[0])
	w.tb_poly(shell, Color(WILLC[2], 0.72))
	w.tb_poly(PackedVector2Array([p + Vector2(-10, -56), p + Vector2(8, -60), p + Vector2(-4, -20), p + Vector2(-16, -24)]), Color(1, 1, 1, 0.7))


## 暴风雪：北边整片风雪往南压到 y（前沿一道翻滚的雪墙 + 后面白茫茫的雪雾 + 斜飘的雪粒）；三条缝和银凇阴影里不画
func _blizzard(w, cv, e: Dictionary, bz: Dictionary, y: float, now: float) -> void:
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	var y0: float = e.pos.y - 60.0
	# 不规则雪幕（协调人 11-26：仍是一块块方格）：按哈希撒雪雾团（位置 / 大小 / 浓淡都不齐，慢慢漂），
	# 前沿是一条起伏的雪墙（相位不同的两层正弦），三条缝和银凇阴影里不画
	var area: float = (2.0 * ar) * maxf(0.0, y - y0)
	var n: int = clampi(int(area / 14000.0), 0, 24)   # 11-28：风雪带改压暗 + 飞雪条纹（_will_storm_ground），雪团只留少量
	for i in n:
		var hj: int = absi(hash(Vector2i(i, 7193)))
		var x: float = e.pos.x - ar + float(hj % 1000) / 1000.0 * 2.0 * ar + 14.0 * sin(now * 0.9 + float(i))
		var yy: float = y0 + float((hj >> 10) % 1000) / 1000.0 * (y - y0 - 20.0)
		if _bz_gap(e, bz, x, y):
			continue
		var sz: float = 60.0 + float((hj >> 20) % 70)
		cv.draw_texture_rect(snow_puff, Rect2(_snap(Vector2(x - sz * 0.5, yy - sz * 0.4)), Vector2(sz, sz * 0.8)), false, Color(1, 1, 1, 0.35 + 0.3 * float((hj >> 3) % 3) / 2.0))
	var x2: float = e.pos.x - ar
	var col := 0
	while x2 <= e.pos.x + ar:
		var hj2: int = absi(hash(Vector2i(col, 911)))
		var xx: float = x2 + float(hj2 % 24) - 12.0
		if not _bz_gap(e, bz, xx, y):
			var fy: float = y + 10.0 * sin(xx * 0.021 + now * 2.1) + 7.0 * sin(xx * 0.053 - now * 3.3)
			var fz: float = 80.0 + float((hj2 >> 6) % 50)
			cv.draw_texture_rect(snow_puff, Rect2(_snap(Vector2(xx - fz * 0.5, fy - fz * 0.7)), Vector2(fz, fz * 0.8)), false, Color(1, 1, 1, 0.95))
			cv.draw_texture_rect(ice_puff[col % 3], Rect2(_snap(Vector2(xx - fz * 0.3, fy - fz * 0.6)), Vector2(fz * 0.6, fz * 0.5)), false, Color(1, 1, 1, 0.9))
			if rng.randf() < 0.1:
				_icefog(Vector2(xx, fy), Vector2(rng.randf_range(-20, 20), 40), 0.6, 40.0, 0.8)
			if rng.randf() < 0.25:
				_add(Vector2(xx + rng.randf_range(-20, 20), rng.randf_range(y0, y)), Vector2(60, 220), 0.5, Color(0.5, 0.6, 0.8), 3.0, 0)
		x2 += 34.0 + float(hj2 % 20)
		col += 1


func _bz_gap(e: Dictionary, bz: Dictionary, x: float, y: float) -> bool:
	for gx in bz.gaps:
		if absf(x - float(gx)) < 50.0:
			return true
	for t2 in e.get("trees", []):
		if float(t2.dead_t) <= 0.0 and absf(x - (t2.pos as Vector2).x) < 46.0 and y > (t2.pos as Vector2).y:
			return true
	return false


## 冬夜：寒冷光环外扩成冰雾前沿（一圈翻卷的冰雾团 + 两排冰晶从地里顶出），停驻点方向留出口
func _winter_front(w, wi: Dictionary, now: float) -> void:
	var c: Vector2 = wi.c
	var r: float = float(wi.r)
	var gy: float = g.combat.GROUND_Y
	var n: int = maxi(12, int(TAU * r / 28.0))
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var gap := false
		for ga in wi.gaps:
			if absf(angle_difference(a, float(ga))) < atan2(50.0, maxf(40.0, r)):
				gap = true
		if gap:
			continue
		var q: Vector2 = c + Vector2(cos(a), sin(a) * gy) * r
		_crystal(w, q, 8.0 + 3.0 * float(i % 3))
		_crystal(w, c + Vector2(cos(a + 0.05), sin(a + 0.05) * gy) * (r - 14.0), 5.0)
		if rng.randf() < 0.08:
			_icefog(q, Vector2(cos(a), sin(a) * gy) * 60.0, 0.6, 34.0, 0.75)


## 坍缩点：地上一个暗紫黑的洞，深青旋臂往里卷，周围的雪粒 / 冰屑被吸进去（读成「往这里拉」）
func _collapse_hole(w, cv, p: Vector2, el: float, dur: float) -> void:
	var k: float = clampf(el / 0.4, 0.0, 1.0) * clampf((dur - el) / 0.3, 0.0, 1.0)
	if k <= 0.0:
		return
	var gy: float = g.combat.GROUND_Y
	w.tb_flush()
	cv.draw_set_transform(p, 0.0, Vector2(1.0, gy))
	cv.draw_circle(Vector2.ZERO, 46.0 * k, Color(0.1, 0.06, 0.16, 0.8))
	cv.draw_circle(Vector2.ZERO, 30.0 * k, Color(0.03, 0.01, 0.06, 0.95))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for arm in 3:
		var prev := Vector2.INF
		for i in 10:
			var f: float = float(i) / 9.0
			var aa: float = float(arm) * TAU / 3.0 - el * 5.0 + f * 3.0
			var q: Vector2 = p + Vector2(cos(aa), sin(aa) * gy) * 60.0 * k * (1.0 - f * 0.75)
			if prev != Vector2.INF:
				w.tb_line(_snap(prev), _snap(q), OLC, 6.0)
				w.tb_line(_snap(prev), _snap(q), TEALC[3] if f < 0.5 else Color(0.5, 0.35, 0.7), 3.0)
			prev = q
	for i in 2:
		var aq: float = rng.randf() * TAU
		var from: Vector2 = p + Vector2(cos(aq), sin(aq) * gy) * rng.randf_range(90.0, 170.0)
		_add(from, (p - from) / 0.5, 0.5, TEALC[4] if i == 0 else WILLC[2], 3.0, 2)


## 紫花（萌发 / 花墓）：五瓣淡紫花 + 花心；快要喷花粉时抖动（s = 缩放）
func _flower(w, p: Vector2, s: float, now: float, cd_left: float) -> void:
	var shake: float = 0.0
	if cd_left > 0.0 and cd_left < 0.6:
		shake = sin(now * 60.0) * 2.0 * s
	var c: Vector2 = p + Vector2(shake, -14.0 * s)
	w.tb_line(_snap(p), _snap(c), TEALC[1], maxf(2.0, 3.0 * s))
	for k in 5:
		var a: float = TAU * float(k) / 5.0 - PI * 0.5 + now * 0.3
		_petal(w, c, a, 16.0 * s)
	if s > 1.5:
		for k in 5:
			var a2: float = TAU * (float(k) + 0.5) / 5.0 - PI * 0.5 + now * 0.3
			_petal(w, c, a2, 11.0 * s)
	w.tb_circle(c, 5.0 * s, LIL[0], 1.0, 10)
	w.tb_circle(c, 3.5 * s, Color(1.0, 0.9, 0.55), 1.0, 10)


## 剪枝长刃：淡紫晶刃（根宽 34 → 尖，暗边 + 本体 + 亮刃口），从支点伸出 L
func _shear(w, piv: Vector2, a: float, L: float) -> void:
	var d := Vector2.from_angle(a)
	var n := d.orthogonal()
	var p0: Vector2 = piv + Vector2(0, -10)
	# 暗紫晶刃（协调人 11-26：亮紫平涂长三角 → 降一档）：暗紫两面明暗 + 一道白芯中线 + 刃口淡紫细亮边，刃面随长度分段错色（晶体感）
	w.tb_poly(PackedVector2Array([p0 - n * 18.0, p0 + d * L * 0.7 - n * 11.0, p0 + d * (L + 6.0), p0 + d * L * 0.7 + n * 11.0, p0 + n * 18.0]), Color(0.1, 0.04, 0.16))
	w.tb_poly(PackedVector2Array([p0 - n * 15.0, p0 + d * L * 0.7 - n * 8.0, p0 + d * L, p0]), Color(0.24, 0.13, 0.36))
	w.tb_poly(PackedVector2Array([p0, p0 + d * L, p0 + d * L * 0.7 + n * 8.0, p0 + n * 15.0]), Color(0.36, 0.22, 0.52))
	for i in 4:
		var f0: float = 0.12 + 0.2 * float(i)
		w.tb_line(_snap(p0 + d * L * f0 - n * (15.0 - 9.0 * f0)), _snap(p0 + d * L * (f0 + 0.06)), Color(0.16, 0.08, 0.26), 2.0)
	w.tb_line(_snap(p0 + n * 13.0 + d * 10.0), _snap(p0 + d * (L - 10.0) + n * 2.0), LIL[1], 2.0)
	w.tb_line(_snap(p0 + d * 8.0), _snap(p0 + d * (L - 14.0)), Color(1, 1, 1), 2.0)


## 日晷：场中一根金橙晷针（光柱从针顶往上淡出），针影 = 暗褐楔形贴地转动，针脚一圈金黄刻度
func _sundial(w, cv, sd: Dictionary, now: float) -> void:
	var pin: Vector2 = sd.pin
	var a: float = float(sd.a)
	var gy: float = g.combat.GROUND_Y
	for i in 24:
		var aa: float = TAU * float(i) / 24.0
		var dd := Vector2(cos(aa), sin(aa) * gy)
		_tick(w, pin + dd * 46.0, dd.normalized(), 12.0 if i % 6 == 0 else 7.0, 5.0 if i % 6 == 0 else 3.0)
	var d := Vector2.from_angle(a)
	var n := d.orthogonal()
	w.tb_poly(PackedVector2Array([pin - n * 22.0, pin + d * 400.0 - n * 6.0, pin + d * 410.0, pin + d * 400.0 + n * 6.0, pin + n * 22.0]), Color(0.2, 0.12, 0.05, 0.72))
	w.tb_poly(PackedVector2Array([pin - n * 12.0, pin + d * 380.0, pin + n * 12.0]), Color(0.12, 0.07, 0.02, 0.8))
	w.tb_poly(PackedVector2Array([pin + Vector2(-8, 2), pin + Vector2(-5, -70), pin + Vector2(0, -78), pin + Vector2(5, -70), pin + Vector2(8, 2)]), LUKA_D)
	w.tb_poly(PackedVector2Array([pin + Vector2(-5, 0), pin + Vector2(-3, -68), pin + Vector2(0, -74), pin + Vector2(0, 0)]), LUKA_O)
	w.tb_poly(PackedVector2Array([pin, pin + Vector2(0, -74), pin + Vector2(3, -68), pin + Vector2(5, 0)]), LUKA)
	w.tb_flush()
	cv.draw_polygon(PackedVector2Array([pin + Vector2(-10, -76), pin + Vector2(10, -76), pin + Vector2(5, -240), pin + Vector2(-5, -240)]),
		PackedColorArray([Color(LUKA, 0.6), Color(LUKA, 0.6), Color(LUKA, 0.0), Color(LUKA, 0.0)]))
	if rng.randf() < 0.4:
		_add(pin + Vector2(rng.randf_range(-6, 6), -80), Vector2(0, -80), 0.6, LUKA, 2.0, 0)


## 沙漏：上下两个三角的边沿一圈沙丘（不平涂），先上半落沙（沙流从高处往下坠），再流到下半
func _hourglass(w, hg: Dictionary, now: float) -> void:
	for i in 2:
		if hg.done[i]:
			continue
		var tri: PackedVector2Array = hg.tris[i]
		var k: float = clampf(1.0 - (float(hg.t[i]) - now) / (1.2 if i == 0 else 2.2), 0.0, 1.0)
		for e2 in 3:
			var a: Vector2 = tri[e2]
			var b: Vector2 = tri[(e2 + 1) % 3]
			_fin_tex()
			_band_tex(g.wcv, sand_band, a, b, 10.0 + 6.0 * k, (0.55 + 0.4 * k) if i == 0 or k > 0.3 else 0.35)
		if rng.randf() < 0.9 * (1.0 if i == 0 else k):
			var u: float = rng.randf()
			var v: float = rng.randf()
			if u + v > 1.0:
				u = 1.0 - u
				v = 1.0 - v
			var q: Vector2 = tri[0] + (tri[1] - tri[0]) * u + (tri[2] - tri[0]) * v
			_add(q + Vector2(0, -60), Vector2(rng.randf_range(-10, 10), 160), 0.38, SANDC[rng.randi_range(1, 3)], 3.0, 0)
		if not hg.get("fx%d" % i, false) and now >= float(hg.t[i]) - 0.02:
			hg["fx%d" % i] = true
			var cc: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
			for j in 8:
				_spike(tri[0].lerp(cc, 0.3 + 0.1 * float(j % 4)) + (tri[1] - tri[2]) * (float(j) / 8.0 - 0.45) * 0.6, 34.0, 18.0, "khan")


## 马鬃旗：木杆 + 顶上一束暗红长鬃（随风摆）
func _standard(w, p: Vector2, now: float) -> void:
	w.tb_line(_snap(p), _snap(p + Vector2(0, -96)), OLC, 6.0)
	w.tb_line(_snap(p), _snap(p + Vector2(0, -94)), Color(0.36, 0.24, 0.14), 3.0)
	var top: Vector2 = p + Vector2(0, -94)
	for k in 3:
		var sw: float = sin(now * 3.0 + float(k)) * 8.0
		var tail := PackedVector2Array([top + Vector2(-3, 0), top + Vector2(-14 - 8 * k + sw, 26 + 8 * k), top + Vector2(-6 - 6 * k + sw, 34 + 10 * k), top + Vector2(3, 4)])
		w.tb_poly(tail, KHAN[0] if k == 0 else (KHAN[1] if k == 1 else KHAN[2]))
	w.tb_poly(PackedVector2Array([top + Vector2(-5, 0), top + Vector2(0, -10), top + Vector2(5, 0)]), LUKA_D)


## 刻度石：暗石碑 + 金黄刻线
func _scale_stone(w, p: Vector2) -> void:
	w.tb_poly(PackedVector2Array([p + Vector2(-18, 3), p + Vector2(-16, -44), p + Vector2(-6, -54), p + Vector2(12, -50), p + Vector2(18, -40), p + Vector2(18, 3)]), OLC)
	w.tb_poly(PackedVector2Array([p + Vector2(-15, 0), p + Vector2(-13, -42), p + Vector2(-5, -50), p + Vector2(0, -48), p + Vector2(0, 0)]), Color(0.36, 0.3, 0.24))
	w.tb_poly(PackedVector2Array([p, p + Vector2(0, -48), p + Vector2(10, -47), p + Vector2(15, -38), p + Vector2(15, 0)]), Color(0.22, 0.18, 0.14))
	for i in 5:
		_tick(w, p + Vector2(-6, -10 - 7.0 * float(i)), Vector2.RIGHT, 10.0 if i % 2 == 0 else 6.0, 3.0)
