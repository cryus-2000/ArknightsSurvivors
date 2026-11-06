## Boss 弹幕东方化第二版（docs/302 §6–§8；用户 11-07：东方感圆弹、pixelfx + Noita 粒子感；骑士不改）。
## 只画面：判定半径 / 速度 / 弹数不动，不读写模拟状态，不用玩法随机数（自带 RandomNumberGenerator），同 seed TRACE 不变。
## 开关 render/danmaku_v2（缺省 1；0 = 旧画法）。
##
## 弹体：运行时用代码逐格生成（tools/danmaku_v2.py 同一套解析形状，2×2 超采样落回美术像素格，5 阶色带 + 交界抖动、暗边、柔光晕、高光），
##   每个 Boss 一张图集贴图（按需生成、每帧限量），弹体一律 draw_texture_rect_region 同一贴图 → 一批画完；包体 0。
##   有方向的弹形（菱晶 / 泪滴 / 炮弹 / 月牙）按 16 向各一格，不旋转贴图；圆形弹两帧脉动（pixelfx 逐格感）。
## 粒子（Noita 式，1 美术像素 = 2×2 世界像素方块，走 world.tb_quad 合批，HDR 色给光学辉光）：
##   沿途掉光、各 Boss 环境粒子（AMB）、发射火星 / 消弹碎屑（重力、落地停住再熄）、弹脚下地面光（tb_circle 椭圆）。
##   粒子上限 PART_CAP（手机网页减半），超了不发新粒子。
## 发射 / 消弹 / 命中瞬间：bullet_fx 的出现 / 消失钩子（set_spawn_hook / set_hook）接管这几个 Boss 的弹，画本模块的逐格闪光帧 + 粒子。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const PX := 2.0
const LIFT := Vector2(0, -16)     # 弹飞行高度（world._ebp）
const PART_CAP := 700
const DIRS := 16
const GRAV := 320.0

## 用这套画法的 Boss（最后的骑士不改；接潮蔑死体没有弹幕）
const TYPES := ["path", "bishop", "immortal", "iberia", "carmen", "izumik", "ishar", "paranoia"]

## 色带：白 → 淡 → 亮 → 主 → 深 + 暗边（tools/danmaku_v2.py STYLE）
const RAMP := {
	"path": [Color8(255, 255, 255), Color8(222, 230, 246), Color8(194, 208, 238), Color8(150, 178, 230), Color8(76, 95, 143), Color8(27, 36, 51)],
	"bishop": [Color8(255, 255, 255), Color8(212, 216, 253), Color8(157, 169, 251), Color8(92, 112, 250), Color8(38, 59, 155), Color8(12, 15, 55)],
	"immortal": [Color8(255, 255, 255), Color8(238, 232, 255), Color8(206, 196, 248), Color8(160, 146, 226), Color8(98, 84, 168), Color8(34, 26, 66)],
	"iberia": [Color8(255, 246, 214), Color8(255, 214, 140), Color8(250, 160, 80), Color8(226, 110, 48), Color8(168, 58, 24), Color8(64, 18, 8)],
	"carmen": [Color8(255, 255, 250), Color8(255, 250, 232), Color8(250, 236, 200), Color8(232, 208, 158), Color8(190, 152, 96), Color8(87, 62, 30)],
	"izumik": [Color8(255, 255, 255), Color8(222, 242, 255), Color8(172, 220, 255), Color8(112, 178, 250), Color8(52, 104, 200), Color8(14, 32, 78)],
	"ishar": [Color8(255, 255, 255), Color8(199, 251, 227), Color8(140, 246, 197), Color8(64, 240, 160), Color8(8, 148, 94), Color8(4, 52, 33)],
	"paranoia": [Color8(255, 255, 255), Color8(234, 216, 255), Color8(209, 160, 255), Color8(178, 96, 255), Color8(99, 33, 158), Color8(39, 13, 56)],
}
## [小弹弹形, 中大弹弹形]
const SHAPE := {"path": ["diamond", "diamond"], "bishop": ["orb", "bubble_ring"], "immortal": ["orb", "crescent"], "iberia": ["shell", "shell"],
	"carmen": ["shell", "shell"], "izumik": ["orb", "orb"], "ishar": ["orb", "drop"], "paranoia": ["bubble", "bubble"]}
## 环境粒子：[种类, 每颗弹每帧发射率, 寿命下限, 寿命上限]
const AMB := {"path": ["glint", 0.08, 0.15, 0.35], "bishop": ["foam", 0.2, 0.3, 0.6], "immortal": ["mote", 0.3, 0.3, 0.7], "iberia": ["ember", 0.7, 0.4, 0.9],
	"carmen": ["glint", 0.25, 0.2, 0.45], "izumik": ["biolum", 0.2, 0.6, 1.2], "ishar": ["drip", 0.25, 0.5, 0.9], "paranoia": ["bubble", 0.1, 0.5, 1.0]}
const DRAG := {"trail": 2.5, "foam": 4.0, "mote": 1.5, "glint": 6.0, "biolum": 0.6, "ember": 1.2, "bubble": 0.8, "drip": 0.3, "spark": 1.6, "debris": 1.2}
const BAYER := [[0.0, 0.5], [0.75, 0.25]]

var g
var rng := RandomNumberGenerator.new()
var _atlas := {}      # type -> {img: Image, tex: ImageTexture, x, y, row_h, cells: {key: Rect2}, dirty}
var _queue := []      # 待生成 [type, key]
var parts := []       # [pos(地面) Vector2, z, vel Vector2, vz, age, life, kind(int), ph, type]
var flashes := []     # [type, kind, pos(屏上，已含高度), frame 计时]
var _last_t := -1.0
var _dt := 0.0
var _hooked := false
var _flash_n := 0
var _on := true
var _mobile := false
const KINDS := ["trail", "foam", "mote", "glint", "biolum", "ember", "bubble", "drip", "spark", "debris"]


func _init(game) -> void:
	g = game
	rng.seed = 20261107


func on() -> bool:
	return _on


## 每帧一次（world.draw_world 开头，bullet_fx.frame 之前）：推进时钟、注册钩子
func frame(bulfx) -> void:
	_on = Bal.v("render/danmaku_v2", 1.0) > 0.0
	if not _hooked and bulfx != null:
		_hooked = true
		for t in TYPES:
			bulfx.set_spawn_hook(t, func(b, p): return _on_spawn(b, p))
			bulfx.set_hook(t, func(b, reason, p): return _on_die(b, reason, p))
	_mobile = g.mobile_cap()
	var t: float = float(g.t)
	_dt = clampf(t - _last_t, 0.0, 0.1) if _last_t >= 0.0 else 0.0
	_last_t = t
	_flash_n = 0
	if _on:
		for e in g.bosses:
			if not e.dead:
				warm(str(e.type))
		_pump(1 if _mobile else 3)


## 这颗弹归本模块画吗（world 各遍据此跳过旧画法）
func mine(b: Dictionary) -> bool:
	if not _on or not b.get("boss", false) or b.get("own_draw", false) or b.get("hidden", false):
		return false
	if not RAMP.has(str(b.get("src_type", ""))):
		return false
	if b.get("mc", false) and float(b.get("hold", 0.0)) > 0.0 and float(b.get("age", 0.0)) < float(b.get("hold", 0.0)):
		return false   # 中期 Boss 显形期（点环收缩 = 预警）仍走 mid_card_draw
	return true


## ---- 弹形映射（tools/danmaku_v2.py kind_for）：返回 [弹形, 半径（美术像素）]
func _kind(t: String, b: Dictionary) -> Array:
	var r: float = float(b.get("r", 6.0))
	if b.get("mc", false):
		r = [6.0, 7.0, 11.0][clampi(int(b.get("tier", 0)), 0, 2)]
	var sh: Array = SHAPE[t]
	if t == "immortal" or str(b.get("kind", "")) == "boss_blade":
		return ["crescent", 9.0 * maxf(0.75, r / 12.0)]
	if r <= 6.0:
		return [sh[0], 5.0 if sh[0] == "diamond" else 4.5]
	var big := Vector2(6.0, 9.0)
	if sh[1] == "drop":
		big = Vector2(5.0, 7.0)
	elif sh[1] == "shell":
		big = Vector2(6.5, 9.0)
	if t == "izumik":
		big = Vector2(6.5, 7.5)
	return [sh[1], big.x if r < 10.0 else big.y]


static func _directional(sh: String) -> bool:
	return sh in ["diamond", "drop", "shell", "crescent"]


## ---- 形状（解析 SDF，与 tools/danmaku_v2.py 一致）：返回 [sdf, e, spec, alpha]
static func _shape(sh: String, u: float, v: float, R: float, x: float, y: float, ph: int) -> Array:
	match sh:
		"orb":
			var r := sqrt(u * u + v * v)
			var e := 1.0 - pow(minf(1.0, r / maxf(1.0, R - 1.0)), 1.5)
			var sp := 1.0 if R >= 5.0 and Vector2(x + R * 0.36, y + R * 0.36).length() < maxf(0.7, R * 0.16) else 0.0
			return [r - R, e, sp, 1.0]
		"bubble":
			var r := sqrt(u * u + v * v)
			var t := (R - 1.0) - r
			var e := 0.0
			var a := 1.0
			if t < 1.6:
				e = 0.55 - 0.3 * maxf(0.0, t) / 1.6
			else:
				e = 0.45 + 0.3 * (1.0 - r / R)
				a = 0.55
			var ang := atan2(y, x)
			var sp := 0.0
			if r > 0.42 * R and r < 0.74 * R and ang > -2.85 and ang < -1.45:
				sp = 1.0
			if R >= 6.0 and Vector2(x - R * 0.38, y - R * 0.38).length() < 0.75:
				sp = 0.6
			if R < 6.0 and Vector2(x + R * 0.3, y + R * 0.3).length() < 0.8:
				sp = 1.0
			return [r - R, e, sp, a]
		"bubble_ring":
			var r := sqrt(u * u + v * v)
			var inner := R * 0.42
			var mid := (R + inner) * 0.5
			var e := 0.9 - minf(1.0, absf(r - mid) / ((R - inner) * 0.5)) * 0.75
			var sp := 1.0 if R >= 6.0 and Vector2(x + R * 0.5, y + R * 0.5).length() < 0.9 else 0.0
			return [maxf(r - R, inner - r), e, sp, 1.0]
		"drop":
			var tip := -2.1 * R
			var sdf := 0.0
			if u >= 0.0:
				sdf = sqrt(u * u + v * v) - R
			else:
				var k := (u - tip) / (0.0 - tip)
				if k > 0.0:
					sdf = maxf(absf(v) - R * pow(k, 1.15), tip - u)
				else:
					sdf = Vector2(u - tip, v).length()
				sdf = minf(sdf, sqrt(u * u + v * v) - R)
			var e := 1.0 - pow(minf(1.0, Vector2(u - R * 0.1, v).length() / (R * 1.1)), 1.3)
			if u < 0.0:
				e = minf(e, maxf(0.0, 0.5 * (u - tip) / (0.0 - tip)))
			var sp := 1.0 if Vector2(x + R * 0.3, y + R * 0.3).length() < maxf(0.75, R * 0.15) else 0.0
			return [sdf, e, sp, 1.0]
		"diamond":
			var a := R
			var bb := R * 0.62
			var sdf := (absf(u) / a + absf(v) / bb - 1.0) * minf(a, bb) * 0.8
			var e := 0.22
			if u >= 0.0 and v < 0.0:
				e = 0.8
			elif u < 0.0 and v < 0.0:
				e = 0.6
			elif u >= 0.0:
				e = 0.42
			if absf(v) < 0.55 and u > -a * 0.2:
				e = 1.0
			return [sdf, e, 0.0, 1.0]
		"shell":
			var r := sqrt(u * u + v * v)
			var sdf := r - R
			if sdf >= 0.0 and u < 0.0:
				var L := R * 2.2
				if u > -R - L and u < -R + 1.0 and absf(v) <= 0.5:
					var t := (-u - R) / L
					if t < 1.0:
						return [-0.5, 0.9 - 0.35 * t, 0.0, maxf(0.05, 0.8 - 0.8 * t)]
			var e := 1.0 - pow(minf(1.0, Vector2(u - R * 0.28, v).length() / (R * 1.05)), 1.35)
			var sp := 1.0 if R >= 5.0 and Vector2(x + R * 0.34, y + R * 0.34).length() < maxf(0.7, R * 0.14) else 0.0
			return [sdf, e, sp, 1.0]
		"crescent":
			var ro := sqrt(u * u + v * v)
			var ri := Vector2(u + R * 0.42, v).length()
			var sdf := maxf(ro - R, R * 0.93 - ri)
			var t := R - ro
			var e := 1.0 - 0.6 * minf(1.0, t / (R * 0.32))
			if sdf >= 0.0:
				var pts := [Vector2(-0.75, -0.55), Vector2(-0.95, 0.25), Vector2(-1.25, -0.15), Vector2(-1.5, 0.5)]
				for k in pts.size():
					var q: Vector2 = pts[k] * R
					if absf(u - q.x) < 0.5 and absf(v - q.y) < 0.5 and (k + ph) % 3 != 0:
						return [-0.5, 0.9, 0.0, 0.7]
			return [sdf, e, 0.0, 1.0]
	var r0 := sqrt(u * u + v * v)
	return [r0 - R, 1.0 - r0 / R, 0.0, 1.0]


## 生成一颗弹的像素图（body：弹体 + 柔光晕；core：只有白 / 淡色像素，叠弹时补在最上层）
func _make(t: String, sh: String, R: float, di: int, ph: int) -> Array:
	var ramp: Array = RAMP[t]
	var ang := TAU * di / DIRS
	var ca := cos(ang)
	var sa := sin(ang)
	var glow := 2 if R >= 5.0 else 1
	var ext := R * (3.7 if sh == "shell" else (2.3 if sh == "drop" else (1.7 if sh == "crescent" else 1.0))) + glow + 1.5
	var n := int(ceil(ext)) * 2 + 1
	var c := (n - 1) * 0.5
	var inside := PackedByteArray()
	inside.resize(n * n)
	var info := []
	info.resize(n * n)
	for py in n:
		for px in n:
			var x := px - c
			var y := py - c
			var s: Array = _shape(sh, x * ca + y * sa, -x * sa + y * ca, R, x, y, ph)
			info[py * n + px] = s
			var sd: float = s[0]
			var cov := 0.0
			if sd < -1.0:
				cov = 1.0
			elif sd < 1.0:
				for o in [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)]:
					var xx: float = x + o.x
					var yy: float = y + o.y
					if float(_shape(sh, xx * ca + yy * sa, -xx * sa + yy * ca, R, xx, yy, ph)[0]) < 0.0:
						cov += 0.25
			inside[py * n + px] = 1 if cov >= 0.5 else 0
	var body := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var core := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var solid := PackedByteArray()
	solid.resize(n * n)
	for py in n:
		for px in n:
			var i := py * n + px
			if inside[i] == 0:
				continue
			var s: Array = info[i]
			var a: float = s[3]
			var edge := false
			if a >= 0.999:
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var qx: int = px + d.x
					var qy: int = py + d.y
					if qx < 0 or qy < 0 or qx >= n or qy >= n or inside[qy * n + qx] == 0:
						edge = true
						break
			var col: Color
			var is_core := false
			if edge and sh == "crescent":
				var x := px - c
				var y := py - c
				col = ramp[0] if Vector2(x * ca + y * sa, -x * sa + y * ca).length() > R - 1.3 else ramp[4]
			elif edge:
				col = ramp[5]
			else:
				var f := (1.0 - clampf(float(s[1]), 0.0, 1.0)) * 4.0
				var idx := mini(4, int(floor(f + 0.32 + 0.36 * BAYER[py % 2][px % 2])))
				col = ramp[idx]
				if float(s[2]) > 0.8:
					col = ramp[0]
				elif float(s[2]) > 0.3:
					col = ramp[1]
				is_core = col == ramp[0] or col == ramp[1]
			col.a = a
			body.set_pixel(px, py, col)
			if is_core and a >= 0.999:
				core.set_pixel(px, py, col)
			if a >= 0.999 and float(s[0]) != -0.5:
				solid[i] = 1
	# 柔光晕：从实心弹体往外 glow 格，3 档透明度（曳光尾 / 碎光不长光晕）
	var cur := solid
	var lv := [0.5, 0.26, 0.12]
	var main: Color = ramp[3]
	for gi in glow:
		var grow := cur.duplicate()
		for py in n:
			for px in n:
				if cur[py * n + px] == 1:
					continue
				if (px > 0 and cur[py * n + px - 1] == 1) or (px < n - 1 and cur[py * n + px + 1] == 1) or (py > 0 and cur[(py - 1) * n + px] == 1) or (py < n - 1 and cur[(py + 1) * n + px] == 1):
					grow[py * n + px] = 1
					if inside[py * n + px] == 0:
						body.set_pixel(px, py, Color(main.r, main.g, main.b, lv[gi]))
		cur = grow
	return [body, core]


## ---- 图集（每个 Boss 一张；行式装箱，满了翻倍）
func _key(sh: String, R: float, di: int, ph: int, core: bool) -> String:
	return "%s|%.1f|%d|%d|%d" % [sh, R, di, ph, 1 if core else 0]


func _cell(t: String, sh: String, R: float, di: int, ph: int, core: bool, now: bool) -> Rect2:
	var A: Dictionary = _atlas.get(t, {})
	if A.is_empty():
		A = {"img": Image.create(512, 512, false, Image.FORMAT_RGBA8), "tex": null, "x": 0, "y": 0, "row": 0, "cells": {}, "dirty": false}
		_atlas[t] = A
	var k := _key(sh, R, di, ph, core)
	if A.cells.has(k):
		return A.cells[k]
	if not now:
		_queue.append([t, sh, R, di, ph])
		return Rect2()
	_build(t, sh, R, di, ph)
	return A.cells.get(k, Rect2())


func _has(t: String, k: String) -> bool:
	var A: Dictionary = _atlas.get(t, {})
	return not A.is_empty() and A.cells.has(k)


func _build(t: String, sh: String, R: float, di: int, ph: int) -> void:
	var A: Dictionary = _atlas[t]
	if A.cells.has(_key(sh, R, di, ph, false)):
		return
	var pair: Array = _make(t, sh, R, di, ph)
	for ci in 2:
		var im: Image = pair[ci]
		var w := im.get_width()
		if int(A.x) + w > A.img.get_width():
			A.x = 0
			A.y = int(A.y) + int(A.row)
			A.row = 0
		if int(A.y) + w > A.img.get_height():
			var big := Image.create(A.img.get_width(), A.img.get_height() * 2, false, Image.FORMAT_RGBA8)
			big.blit_rect(A.img, Rect2i(0, 0, A.img.get_width(), A.img.get_height()), Vector2i.ZERO)
			A.img = big
			A.tex = null
		A.img.blit_rect(im, Rect2i(0, 0, w, w), Vector2i(int(A.x), int(A.y)))
		A.cells[_key(sh, R, di, ph, ci == 1)] = Rect2(int(A.x), int(A.y), w, w)
		A.x = int(A.x) + w
		A.row = maxi(int(A.row), w)
	A.dirty = true


## 每帧最多生成 n 格（Boss 一出场就开始预生成，第一轮弹前基本就绪）
func _pump(n: int) -> void:
	var made := 0
	while made < n and not _queue.is_empty():
		var q: Array = _queue.pop_front()
		var A: Dictionary = _atlas.get(q[0], {})
		if not A.is_empty() and A.cells.has(_key(q[1], q[2], q[3], q[4], false)):
			continue
		_build(q[0], q[1], q[2], q[3], q[4])
		made += 1


## Boss 出场时预排这只 Boss 会用到的全部格（world 每帧对场上 Boss 调一次，已排过就跳过）
var _warmed := {}
func warm(t: String) -> void:
	if _warmed.has(t) or not RAMP.has(t):
		return
	_warmed[t] = true
	if not _atlas.has(t):
		_atlas[t] = {"img": Image.create(512, 512, false, Image.FORMAT_RGBA8), "tex": null, "x": 0, "y": 0, "row": 0, "cells": {}, "dirty": false}
	var sizes := []
	for r in [6.0, 7.0, 11.0, 13.0]:
		sizes.append(_kind(t, {"r": r}))
	if t == "immortal":
		sizes = [_kind(t, {"r": 12.0})]
	var seen := {}
	for s in sizes:
		var sh: String = s[0]
		var R: float = s[1]
		var dirs: int = DIRS if _directional(sh) else 1
		var phs: int = 3 if sh == "crescent" else 1
		var Rs := [R] if _directional(sh) or sh == "crescent" else [R, R + 0.4]
		for RR in Rs:
			for di in dirs:
				for ph in phs:
					var k := _key(sh, RR, di, ph, false)
					if not seen.has(k):
						seen[k] = true
						_queue.append([t, sh, RR, di, ph])


func _tex(t: String) -> Texture2D:
	var A: Dictionary = _atlas.get(t, {})
	if A.is_empty():
		return null
	if A.tex == null:
		A.tex = ImageTexture.create_from_image(A.img)
		A.dirty = false
	elif A.dirty:
		A.tex.update(A.img)
		A.dirty = false
	return A.tex


## ---- 绘制（world._draw_ebullets_lobs_shocks 开头调用）
func draw(w) -> void:
	if not _on:
		return
	# 光学观感下世界层受光照 / 暗角压暗：弹体按 HDR 提亮（旧画法的弹也是过曝色），弹在暗处照样亮（Noita 的自发光）
	var hk: float = Bal.v("render/danmaku_v2_hdr", 1.4) if g.optical_on else 1.0
	_mod = Color(hk, hk, hk, 1.0)
	var list := []
	for b in g.ebullets:
		if b.life > 0.0 and mine(b):
			list.append(b)
	_step_parts(list)
	var vr: Rect2 = w.view_rect(48.0)
	w.tb_flush()
	# ① 影子 + 地面光（弹脚下，椭圆；弹幕越密地面越亮）
	for b in list:
		var p: Vector2 = b.pos
		if not vr.has_point(p):
			continue
		var t: String = str(b.src_type)
		var m: Color = RAMP[t][3]
		var r: float = float(b.r)
		w.tb_circle(p + Vector2(0, 2), r + 1.0, Color(0, 0, 0, 0.35), 0.45, 10)
		w.tb_circle(p, r * 2.4, Color(m.r, m.g, m.b, 0.07), 0.5, 12)
		w.tb_circle(p, r * 1.3, Color(m.r * 1.2, m.g * 1.2, m.b * 1.2, 0.1), 0.5, 10)
	w.tb_flush()
	# ② 弹体（同一 Boss 同一图集贴图，按 Boss 分组连续提交 → 合批）
	var by_t := {}
	for b in list:
		var p: Vector2 = b.pos + LIFT
		if not vr.has_point(p):
			continue
		var t: String = str(b.src_type)
		if not by_t.has(t):
			by_t[t] = []
		by_t[t].append(b)
	for t in by_t:
		var items := []
		for b in by_t[t]:
			var kr: Array = _kind(t, b)
			var sh: String = kr[0]
			var R: float = kr[1]
			var di := 0
			var vel: Vector2 = b.get("vel", Vector2.ZERO)
			if _directional(sh):
				var va: float = vel.angle() if vel.length_squared() > 1.0 else float(b.get("_bv2a", 0.0))
				b["_bv2a"] = va
				di = posmod(int(round(va / (TAU / DIRS))), DIRS)
			var ph := 0
			var bid: int = int(b.get("_bid", 0))
			if sh == "crescent":
				ph = int(g.t * 6.0 + bid) % 3
			elif not _directional(sh) and (int(g.t * 10.0) + bid) % 4 < 2:
				R += 0.4   # 芯脉动（两帧交替，pixelfx 逐格感）
			items.append([b, sh, R, di, ph])
		var tex := _tex(t)
		# 缺格：当帧补生成（少见；预生成没赶上时）
		var missing := false
		for it in items:
			if not _has(t, _key(it[1], it[2], it[3], it[4], false)):
				missing = true
				_cell(t, it[1], it[2], it[3], it[4], false, true)
		if missing:
			tex = _tex(t)
		if tex == null:
			continue
		var need_core := false
		for it in items:
			var rc: Rect2 = _cell(t, it[1], it[2], it[3], it[4], false, true)
			_blit(tex, (it[0].pos as Vector2) + LIFT, rc)
			if it[1] != "shell" and it[1] != "crescent":
				need_core = true
		if need_core and items.size() > 1:
			for it in items:
				if it[1] == "shell" or it[1] == "crescent":
					continue
				_blit(tex, (it[0].pos as Vector2) + LIFT, _cell(t, it[1], it[2], it[3], it[4], true, true))
	# ③ 粒子 + 瞬间闪光帧（tb 合批）
	_draw_parts(w, vr)
	w.tb_flush()


var _mod := Color.WHITE
func _blit(tex: Texture2D, center: Vector2, rc: Rect2) -> void:
	var sz: Vector2 = rc.size * PX
	var tl: Vector2 = ((center - sz * 0.5) / PX).floor() * PX   # 吸附 2 世界像素格：1 特效像素 = 1 美术像素
	g.wcv.draw_texture_rect_region(tex, Rect2(tl + g.draw_off, sz), rc, _mod)


## ---- 粒子
func _emit(t: String, p: Vector2, z: float, v: Vector2, vz: float, life: float, kind: int) -> void:
	if parts.size() >= (PART_CAP / 2 if _mobile else PART_CAP):
		return
	parts.append([p, z, v, vz, 0.0, life, kind, rng.randf() * TAU, t])


func _step_parts(list: Array) -> void:
	var dt := _dt
	if dt <= 0.0:
		return
	for b in list:
		var t: String = str(b.src_type)
		var vel: Vector2 = b.get("vel", Vector2.ZERO)
		var sp := vel.length()
		var u: Vector2 = vel / sp if sp > 1.0 else Vector2.ZERO
		var r: float = float(b.r)
		var fk := dt / 0.05   # 发射率按 20 帧 / 秒标定
		var rate: float = (0.6 if r <= 6.0 else (1.2 if r < 10.0 else 2.0)) * fk * (0.5 if _mobile else 1.0)
		var n := int(rate) + (1 if rng.randf() < rate - int(rate) else 0)
		for i in n:
			var j := rng.randfn(0.0, r * 0.35)
			_emit(t, b.pos - u * r * 0.6 + u.orthogonal() * j, 16.0, -vel * 0.12 + Vector2(rng.randfn(0, 14), rng.randfn(0, 14)), rng.randfn(0, 6), rng.randf_range(0.18, 0.45), 0)
		var am: Array = AMB[t]
		if rng.randf() < float(am[1]) * fk * (1.6 if r >= 10.0 else 1.0) * (0.5 if _mobile else 1.0):
			var L := rng.randf_range(am[2], am[3])
			var kd: int = KINDS.find(am[0])
			var jp := Vector2(rng.randfn(0, r * 0.5), rng.randfn(0, r * 0.5))
			match str(am[0]):
				"ember":
					_emit(t, b.pos + jp, 16.0, -vel * 0.2 + Vector2(rng.randfn(0, 10), 0), rng.randf_range(25, 55), L, kd)
				"drip":
					_emit(t, b.pos + jp * 0.5, 14.0, vel * 0.1, rng.randf_range(-10, 10), L, kd)
				"bubble":
					_emit(t, b.pos + jp, 16.0, Vector2(rng.randfn(0, 6), 0), rng.randf_range(14, 30), L, kd)
				"foam":
					var side := 1.0 if rng.randf() < 0.5 else -1.0
					_emit(t, b.pos, 16.0, -vel * 0.15 + u.orthogonal() * side * rng.randf_range(40, 80), rng.randf_range(0, 20), L, kd)
				"biolum":
					_emit(t, b.pos + jp * 1.2, 16.0, Vector2(rng.randfn(0, 8), rng.randfn(0, 8)), rng.randf_range(4, 12), L, kd)
				_:
					_emit(t, b.pos + jp * 1.4, 16.0, -vel * (0.05 if am[0] == "glint" else 0.25), 0.0, L, kd)
	var keep := []
	for q in parts:
		q[4] = float(q[4]) + dt
		if float(q[4]) >= float(q[5]):
			continue
		var kd: String = KINDS[int(q[6])]
		var f := exp(-float(DRAG[kd]) * dt)
		var v: Vector2 = q[2] * f
		var gr := 0.0
		match kd:
			"spark", "debris":
				gr = GRAV
			"drip":
				gr = GRAV * 0.9
			"ember":
				gr = -20.0
			"bubble":
				gr = -8.0
				v.x = 10.0 * sin(float(q[4]) * 9.0 + float(q[7]))
		q[3] = float(q[3]) - gr * dt
		q[0] = (q[0] as Vector2) + v * dt
		q[1] = float(q[1]) + float(q[3]) * dt
		q[2] = v
		if float(q[1]) <= 0.0 and kd in ["spark", "debris", "drip"]:
			q[1] = 0.0
			q[3] = 0.0
			q[2] = v * 0.2   # 落地停住，在地上熄灭
			if kd == "drip" and float(q[4]) < float(q[5]) - 0.15:
				for s in [-1.0, 1.0]:
					keep.append([(q[0] as Vector2) + Vector2(s * 2.0, 0), 0.5, Vector2(s * 25.0, 0), 30.0, 0.0, 0.18, KINDS.find("spark"), 0.0, q[8]])
				continue
		keep.append(q)
	parts = keep
	var fk := []
	for fl in flashes:
		fl[3] = float(fl[3]) + dt
		if float(fl[3]) < 0.25:
			fk.append(fl)
	flashes = fk


func _rc(t: String, k: float) -> Color:
	var ramp: Array = RAMP[t]
	return ramp[mini(4, int(clampf(k, 0.0, 0.999) * 5.0))]


func _px(w, p: Vector2, c: Color) -> void:
	var a := (p / PX).floor() * PX
	w.tb_quad(a, a + Vector2(PX, 0), a + Vector2(PX, PX), a + Vector2(0, PX), c)


func _draw_parts(w, vr: Rect2) -> void:
	for q in parts:
		var p: Vector2 = (q[0] as Vector2) + Vector2(0, -float(q[1]))
		if not vr.has_point(p):
			continue
		var kd: String = KINDS[int(q[6])]
		var ka: float = float(q[4]) / float(q[5])
		if kd in ["trail", "spark", "debris", "mote"] and rng.randf() < 0.18:
			continue   # 闪烁
		var t: String = q[8]
		var ramp: Array = RAMP[t]
		var c: Color
		var hdr := 1.0
		match kd:
			"biolum":
				var a := 0.5 + 0.5 * sin(float(q[4]) * 7.0 + float(q[7]))
				c = ramp[1] if a > 0.6 else ramp[2]
				c.a = (0.4 + 0.6 * a) * (1.0 - ka)
				hdr = 1.3
			"ember":
				c = _rc(t, 0.25 + ka * 0.75)
				c.a = clampf(1.2 - ka, 0.0, 1.0)
				hdr = 2.0
			"bubble":
				c = ramp[1]
				c.a = 0.8 * (1.0 - ka)
			"glint":
				c = ramp[0] if ka < 0.4 else ramp[2]
				c.a = clampf(1.1 - ka, 0.0, 1.0)
				hdr = 2.2
			_:
				c = _rc(t, ka)
				c.a = clampf(1.15 - 0.6 * ka, 0.0, 1.0)
				hdr = 2.0
		c = Color(c.r * hdr, c.g * hdr, c.b * hdr, c.a)
		if kd == "bubble" and ka < 0.7:
			for d in [Vector2(PX, 0), Vector2(-PX, 0), Vector2(0, PX), Vector2(0, -PX)]:
				_px(w, p + d, Color(c.r, c.g, c.b, c.a * 0.7))
			continue
		_px(w, p, c)
		if kd == "glint" and ka < 0.35:
			for d in [Vector2(PX, 0), Vector2(-PX, 0), Vector2(0, PX), Vector2(0, -PX)]:
				_px(w, p + d, Color(c.r, c.g, c.b, c.a * 0.55))
	# 瞬间闪光帧（逐格，5 帧 0.25 秒）：发射四芒星 / 消弹六片碎光 / 命中破环
	for fl in flashes:
		var t: String = fl[0]
		var ramp: Array = RAMP[t]
		var fr: int = mini(4, int(float(fl[3]) / 0.05))
		var c0: Vector2 = fl[2]
		if not vr.has_point(c0):
			continue
		var kk := fr / 4.0
		match str(fl[1]):
			"fire":
				var L := int(9.0 * (1.0 - kk) + 2.0)
				if fr < 4:
					for i in range(-L, L + 1):
						var tone: Color = ramp[0] if absi(i) < L * 0.35 else (ramp[1] if absi(i) < L * 0.7 else ramp[3])
						tone = Color(tone.r * 1.5, tone.g * 1.5, tone.b * 1.5)
						_px(w, c0 + Vector2(i * PX, 0), tone)
						_px(w, c0 + Vector2(0, i * PX), tone)
				for j in 6:
					var a := j * TAU / 6.0 + 0.3
					_px(w, c0 + Vector2(cos(a), sin(a)) * (3.0 + fr * 2.6) * PX, ramp[1] if fr < 2 else ramp[3])
			"cancel":
				if fr == 0:
					for yy in range(-3, 4):
						for xx in range(-3, 4):
							if xx * xx + yy * yy <= 9:
								_px(w, c0 + Vector2(xx, yy) * PX, ramp[0] if xx * xx + yy * yy <= 4 else ramp[2])
				for j in 6:
					var a := j * TAU / 6.0 + fr * 0.35
					var pp := c0 + Vector2(cos(a), sin(a)) * (2.0 + fr * 2.4) * PX
					if fr < 4:
						_px(w, pp, Color(ramp[0].r * 1.4, ramp[0].g * 1.4, ramp[0].b * 1.4) if fr < 2 else ramp[1])
						_px(w, pp + Vector2(cos(a + 1.57), sin(a + 1.57)) * PX, ramp[2])
			"hit":
				var rr := 2.0 + fr * 2.2
				var segs := 16
				for j in segs:
					var a := j * TAU / segs
					if fr == 0:
						_px(w, c0 + Vector2(cos(a), sin(a) * 0.8) * 2.0 * PX, ramp[0])
					elif fr < 4:
						_px(w, c0 + Vector2(cos(a), sin(a) * 0.8) * rr * PX, ramp[2] if fr < 2 else ramp[3])


## ---- bullet_fx 钩子：这几个 Boss 的弹出现 / 消失由本模块画（返回 true = 旧的通用出现 / 消失画面不画）
func _on_spawn(b: Dictionary, p: Vector2) -> bool:
	if not _on:
		return false
	var t: String = str(b.get("src_type", ""))
	warm(t)
	var vel: Vector2 = b.get("vel", b.get("v0", Vector2.ZERO))
	var a := vel.angle()
	# 闪光帧：同一处 0.1 秒内只放一个（整圈齐射不叠成白团）
	var near := false
	for fl in flashes:
		if float(fl[3]) < 0.1 and (fl[2] as Vector2).distance_squared_to(p) < 24.0 * 24.0:
			near = true
			break
	if not near and _flash_n < 4:
		_flash_n += 1
		flashes.append([t, "fire", p, 0.0])
	for i in (1 if near else 3):
		var aa := a + rng.randfn(0.0, 0.5)
		var v := rng.randf_range(90.0, 200.0)
		_emit(t, b.pos, 16.0, Vector2(cos(aa), sin(aa) * 0.7) * v, rng.randf_range(20.0, 90.0), rng.randf_range(0.35, 0.7), KINDS.find("spark"))
	return true


func _on_die(b: Dictionary, reason: String, p: Vector2) -> bool:
	if not _on:
		return false
	var t: String = str(b.get("src_type", ""))
	if reason == "expire":
		for i in 2:
			_emit(t, b.pos, 16.0, Vector2(rng.randfn(0, 30), rng.randfn(0, 30)), 10.0, 0.4, KINDS.find("debris"))
		return true
	if _flash_n < 8:
		_flash_n += 1
		flashes.append([t, "hit" if reason == "hit" else "cancel", p, 0.0])
	var n := 6 if float(b.get("r", 6.0)) <= 6.0 else 10
	for i in n:
		var a := rng.randf() * TAU
		var v := rng.randf_range(40.0, 150.0)
		_emit(t, b.pos, 16.0, Vector2(cos(a), sin(a) * 0.7) * v, rng.randf_range(30.0, 120.0), rng.randf_range(0.4, 0.9), KINDS.find("debris"))
	return true
