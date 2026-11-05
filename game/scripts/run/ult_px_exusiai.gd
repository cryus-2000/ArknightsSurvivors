## 能天使终结技转平面画面（docs/262 §11，开关 ult/px_plane，缺省 0 = 原画面）：只改画面，判定 / 时长 / 伤害 / 发数一律照 ult_moves 原样。
## 画面件都是 ult 的图形（u.shape），kind = "pxfn"、px = 画法；ult.gd 的 draw_world / draw_world_back / 冲击帧见到 pxfn 就交给 draw()。
## 帧条（举枪大闪光、光柱、头顶大光环、爆点、焦痕、枪口火）用 fx_pxplane 的 pxp_ex_* 帧条（tools/pxplane_bake_exusiai.py 烤，图形 tools/pxplane_exu_ult_art.py），
## 1 特效像素 = 1 美术像素、按 15 fps 节拍选帧；锁定框、锁定范围环、连锁闪线运行时逐格画（同 pxplane_exu_ult_art.reticle_px / ring_px）；子弹用 fx_pxplane_exu 的肉鸽式光弹。
## 冲击帧（整屏白 + 黑剪影，用户认可）照原样：原来那一下的爆点帧条 + 碎环仍由 ult_moves 画并进剪影，新爆点帧条也一起进剪影。
## Noita 颗粒走 fx_recipe 的颗粒池（她被 fx/px_plane 接管时才画）。画面随机不用（全部按序号 / 坐标哈希）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Pxp = preload("res://scripts/render/fx_pxplane.gd")
const Fxr = preload("res://scripts/render/fx_recipe.gd")

const GOLD := [Color("#2a1c06"), Color("#5c3e0a"), Color("#a8741a"), Color("#e8b030"), Color("#ffd86a"), Color("#fff2c0"), Color("#ffffff")]
const VERM := [Color("#2a100c"), Color("#5c2418"), Color("#a8402a"), Color("#f07048"), Color("#ffa880"), Color("#ffe0cc"), Color("#ffffff")]
const SQ := 0.72
const HALO_Y := -80.0


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


# ================================================================ 生成（ult_moves 的能天使段在 on() 时调这些，代替原来的图形）

static func strip(u, key: String, c: Vector2, life: float, opt := {}) -> Dictionary:
	var s := {"kind": "pxfn", "px": "strip", "key": key, "c": c, "life": life}
	s.merge(opt, true)
	u.shape(s)
	return s


## 起手：两把枪朝斜上举起的大闪光 + 脚下光柱 + 头顶大光环（持续到扫射结束，跟着她）+ 锁定范围环从脚下推开 + 照地光 + 少量碎晶往上溅
static func raise(u, o, c: Vector2, R: float, dur: float, mz: Array, gold: Color) -> void:
	for k in 2:
		var p: Vector2 = c + mz[k]
		strip(u, "ex_ult_raise", p, 3.0 / 15.0 + 0.02, {"flip": k == 0})
		u.light(p, 150.0, gold, 0.4)
	strip(u, "ex_ult_pillar", c, 4.0 / 15.0 + 0.02)
	strip(u, "ex_ult_halo", c, dur + 0.3, {"loop": true, "o": o, "off": Vector2(0, HALO_Y)})
	u.shape({"kind": "pxfn", "px": "ring", "c": c, "r": R, "grow": true, "life": 4.0 / 15.0, "layer": "back"})
	grains(u, o, c + Vector2(0, -60), c.y + 2.0, "shard", 6, Vector2.UP)


static func reticle(u, e: Dictionary, h: float, life: float) -> Dictionary:
	var s := {"kind": "pxfn", "px": "reticle", "c": e.pos, "f": 0, "h": h, "elite": bool(e.elite or e.boss), "life": life}
	u.shape(s)
	return s


## 锁定框碎（目标被打到 / 倒下 / 扫射结束）：框自己播 6–7 帧往外弹开；这里只加几颗碎晶
static func lock_break(u, o, p: Vector2) -> void:
	grains(u, o, p + Vector2(0, -12), p.y + 2.0, "shard", 2, Vector2.UP)


## 扫射结束时还挂着的框：原地补一个只播碎裂两帧的框
static func reticle_break(u, p: Vector2, h: float, elite: bool) -> void:
	u.shape({"kind": "pxfn", "px": "reticle", "c": p, "brk": true, "h": h, "elite": elite, "life": 2.0 / 15.0})


static func glow(u, c: Vector2, life: float) -> Dictionary:
	var s := {"kind": "pxfn", "px": "glow", "c": c, "r": 16.0, "life": life}
	u.shape(s)
	return s


## 开枪：枪口火（倾泻金硬星形，两种变体交替），挂 2 拍
static func muzzle(u, mz: Vector2, d: Vector2, n: int) -> void:
	var dp: Array = Pxp.pick_dir(d.angle())
	strip(u, "ex_mz_g_e2_v%d_d%d" % [n % 2, int(dp[0])], mz, 2.0 / 15.0 + 0.02, {"flip": bool(dp[1])})


## 子弹：一个 pxfn 件（ult_moves._ex_fly 每帧写 a = 尾、b = 头），左枪朱橙、右枪金
static func bullet(u, p0: Vector2, k: int) -> Dictionary:
	var s := {"kind": "pxfn", "px": "bul", "a": p0, "b": p0, "gun": k, "life": 2.0}
	u.shape(s)
	return s


## 爆裂弹爆点：立起爆团（两种变体交替）+ 地上焦痕 + Noita 碎屑（每个爆点 2–3 颗，第一轮一片爆点合起来 6–16）+ 照地光每 2 个一盏
static func burst(u, a: Dictionary, p: Vector2, sc: float, i: int, red: Color, gold: Color) -> void:
	strip(u, "ex_ult_burst_v%d" % (i % 2), p + Vector2(0, -12), 5.0 / 15.0 + 0.02, {"burst": true})
	strip(u, "ex_ult_scorch_gd", p, 4.0 / 15.0 + 0.02, {"layer": "back"})
	grains(u, a.o, p + Vector2(0, -12), p.y + 2.0, "rock", 2 + (i % 2), Vector2.ZERO)
	if i % 2 == 0:
		u.light(p, 160.0 * sc, red.lerp(gold, 0.5), 0.15)


static func chain(u, p0: Vector2, p1: Vector2, life: float) -> void:
	u.shape({"kind": "pxfn", "px": "line", "a": p0, "b": p1, "life": life})


static func ring_pulse(u, c: Vector2, R: float) -> void:
	u.shape({"kind": "pxfn", "px": "ring", "c": c, "r": R, "life": 4.0 / 15.0, "layer": "back"})


## 冲击帧那一刻：同屏还在炸的新爆点也进剪影
static func hf_mark(u) -> void:
	for s in u.shapes:
		if str(s.get("kind", "")) == "pxfn" and s.get("burst", false):
			s["hf"] = true


static func grains(u, o, at: Vector2, gy: float, mat: String, n: int, dir: Vector2) -> void:
	if o == null or not Fxr.owns(o):
		return
	Fxr.of(u.g)._grains(o, at, gy, mat, n, {"tier": 2}, dir)


# ================================================================ 绘制（ult.gd 调；sil = 冲击帧剪影色，null = 正常）

static func draw(g, s: Dictionary, dim: float, sil = null) -> void:
	var beat: int = int(floor(maxf(0.0, float(s.age)) * 15.0))
	match str(s.px):
		"strip":
			var c: Vector2 = s.c
			if s.has("o") and s.o != null and s.o.pos != Vector2.INF:
				c = s.o.pos + Vector2(s.get("off", Vector2.ZERO))
			var mod: Color = Color(sil.r, sil.g, sil.b, 1.0) if sil != null else Color(1, 1, 1, dim)
			Pxp.of(g)._draw_strip(g, str(s.key), beat, _snap(c), bool(s.get("flip", false)), not s.get("loop", false), mod)
		"bul":
			if sil != null:
				return
			var a: Vector2 = s.a
			var b: Vector2 = s.b
			if a.distance_squared_to(b) < 1.0:
				return
			Pxp.of(g)._ex()._bullet(g, b, b - a, "n" if int(s.gun) == 0 else "g", 2, false, false)
		"ring":
			var r: float = float(s.r)
			if s.get("grow", false):
				r *= [0.45, 0.8, 1.0, 1.0][mini(beat, 3)]
			_ring(g, s.c, r, beat, sil, dim)
		"reticle":
			var f: int = mini(7, 6 + int(floor(float(s.age) * 24.0))) if s.get("brk", false) else int(s.get("f", 0))
			_reticle(g, s.c, float(s.h), f, bool(s.elite), sil, dim)
		"glow":
			var p: Vector2 = _snap(s.c)
			var big: bool = float(s.r) > 22.0
			var col: Color = GOLD[6] if big else GOLD[5]
			if sil != null:
				col = sil
			for q in [Vector2.ZERO, Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				g.draw_rect(Rect2(p + q, Vector2(2, 2)), Color(col, dim))
			if big:
				for q2 in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
					g.draw_rect(Rect2(p + q2, Vector2(2, 2)), Color(GOLD[5] if sil == null else sil, dim))
			Pxp.of(g)._glow(p, GOLD[6])
		"line":   # 连锁闪线：1 美术像素，朱橙 / 金交替，后一半时间只剩靠落点一半
			var a2: Vector2 = s.a
			var b2: Vector2 = s.b
			var n: int = maxi(1, int(a2.distance_to(b2) / 2.0))
			var late: bool = float(s.age) > float(s.max) * 0.5
			for i in n + 1:
				var u2: float = float(i) / float(n)
				if late and u2 < 0.5:
					continue
				var col2: Color = (VERM[5] if i % 2 == 0 else GOLD[5]) if sil == null else sil
				g.draw_rect(Rect2(_snap(a2.lerp(b2, u2)), Vector2(2, 2)), Color(col2, dim))


## 锁定范围环（同 pxplane_exu_ult_art.ring_px）：断续（每 7 点缺 1）、按拍由亮到暗，4 拍后不画
static func _ring(g, c: Vector2, r: float, beat: int, sil, dim: float) -> void:
	if beat < 0 or beat > 3:
		return
	var col: Color = [GOLD[6], GOLD[5], VERM[4], VERM[2]][beat]
	if sil != null:
		col = sil
	var n: int = maxi(24, int(TAU * r / 2.0))
	var cs: Vector2 = _snap(c)
	for i in n:
		if (i + beat * 3) % 7 == 0:
			continue
		var t: float = float(i) / float(n) * TAU
		g.draw_rect(Rect2(cs + Vector2(round(cos(t) * r / 2.0) * 2.0, round(sin(t) * r * SQ / 2.0) * 2.0), Vector2(2, 2)), Color(col, dim))


## 锁定框（同 pxplane_exu_ult_art.reticle_px）：四角括号；f 0–3 锁上（1.6h → h）、4–5 保持（5 胀 1 格）、6–7 碎（往外弹开、变暗）
static func _reticle(g, c: Vector2, hw: float, f: int, elite: bool, sil, dim: float) -> void:
	var h: float
	if f <= 3:
		h = hw * (1.6 - 0.6 * float(f) / 3.0)
	elif f <= 5:
		h = hw + (2.0 if f == 5 else 0.0)
	else:
		h = hw * (1.3 if f == 6 else 1.7)
	var arm: int = 4 if elite else 3
	var th: int = 2 if elite else 1
	var col: Color = GOLD[6] if f in [3, 6] else (GOLD[5] if f < 6 else GOLD[3])
	if sil != null:
		col = sil
	col.a = dim
	var cs: Vector2 = _snap(c)
	var hp: int = int(round(h / 2.0))
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for j in arm:
				for w in th:
					g.draw_rect(Rect2(cs + Vector2(float(sx * hp - sx * j), float(sy * hp - sy * w)) * 2.0, Vector2(2, 2)), col)
					g.draw_rect(Rect2(cs + Vector2(float(sx * hp - sx * w), float(sy * hp - sy * j)) * 2.0, Vector2(2, 2)), col)
	if f < 6:
		var dc: Color = VERM[4] if sil == null else sil
		dc.a = dim
		g.draw_rect(Rect2(cs, Vector2(4, 4) if elite else Vector2(2, 2)), dc)
