## pixelfx「转平面」试验（docs/246，11-05 用户「把 pixelfx 的二维平面转移到我们这个平面上来，再结合 Noita 特效」）：斯卡蒂（docs/246）、星熊（docs/248，见文件末尾一节）。
## 开关 fx/px_plane（balance.json，缺省 0 = 关）：1 = 转平面版，2 = 旧做法原样贴（对照用，重现之前的问题）。
## 借配方系统（fx_recipe.gd）的接管：开着时 Fxr.owns(斯卡蒂) 为真，她原来的刀光 / 帧条 / pfx / 命中颗粒只跳过绘制（玩法照旧，TRACE 逐行一致）；
## 事件由 fx_recipe._ev 转到这里，颗粒（Noita 水滴）和照地光走 fx_recipe 的颗粒池与灯光预算。
## 转平面版的三条（对应协调人诊断的三个丑因）：
##   ① 视角：每招拆成贴地层（接触阴影、水痕、冲击环、积水；帧条生成时已按 GROUND_Y 压扁，地面层画、被单位挡）和立起层
##      （刀光幕、水柱、潮刃浪头；竖直，进 world 单位排序按脚底 y 排，脚下有接触阴影）；
##   ② 像素格：帧条按目标尺寸用 pixelfx 生成（tools/pxplane_bake.py），1 帧条像素 = 1 美术像素，游戏里只按 g.PX（2）整数放大、不旋转，
##      位置对齐 2 世界像素格；方向件按 5 个平面角预生成，另一半水平翻转；
##   ③ 吃光：色层当普通物体画（受 CanvasModulate 与光学层光照压暗 / 受光），最亮的热芯像素（emit 点表）进光学发光层；
##      命中 / 爆点挂一盏 ≤ 0.15 秒的照地点光（fx_recipe 灯光预算）。
##   ④ 帧率（协调人 11-05 补充）：统一一个动画时钟——帧条一律 15 fps 烘焙，选帧按全局节拍 floor(g.t × 15)（60 Hz 下每帧正好停 4 个游戏帧，
##      同屏所有件同一拍换帧）；潮刃 / 浪墙的位置也按同一 15 fps 节拍跳格、对齐美术像素格，不做 60 Hz 亚像素滑动；颗粒与光照旧平滑（颗粒位置取整到像素格）。
##      fx/px_plane_fps ≠ 15 时退回「各件自己的小数帧率 + 平滑位移」（帧率统一前后对照用）。
## 旧做法（2）：光晕烤进颜色的正俯视 / 正圆帧条，按判定半径小数缩放、按出手方向旋转，整张盖在所有单位上面（不排序、无阴影、无 emit），
##      帧率按旧帧条常见的小数帧率 fx/px_plane_raw_fps（缺省 12.8）播。
## 画面随机只用 g.vrng（颗粒）；本模块不抽随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const METAS := ["res://data/pxp_skadi.json", "res://data/pxp_hoshiguma.json"]   # 星熊（docs/248）的键带 hsg_ 前缀
const ART := "res://art/fx/pxp/pxp_%s.png"
const IDS := {"skadi": true, "hoshiguma": true}
## 接管时仍照画的原 pfx 帧条（状态提示，不属于攻击特效）：星熊格挡闪光、反击架势盾沿光
const KEEP_PFX := {"hoshiguma": {"fx_hoshiguma_block": true, "fx_hoshiguma_guard_glow": true}}
const DIRS := [-90, -45, 0, 45, 90]
const EMIT_CAP := 360     # 每帧送进发光层的 emit 点上限（整队）
const ITEM_MAX := 72

var g
var meta := {}
var tex := {}
var items: Array = []     # 一次性件：{k 帧条键, t0, gp 地面点, flip, ly up/gd, raw, rot, sc, oid}
var _mode := 0
var _mode_frame := -1
var _emit_n := 0
var _emit_frame := -1
var _ecol := {}


static func of(game):
	if game == null:
		return null
	if game.has_meta("fx_pxplane"):
		return game.get_meta("fx_pxplane")
	var r = new()
	r.g = game
	game.set_meta("fx_pxplane", r)
	return r


## 0 关 / 1 转平面 / 2 旧做法原样贴（每帧读一次）
func mode() -> int:
	var fr: int = Engine.get_process_frames()
	if fr != _mode_frame:
		_mode_frame = fr
		_mode = 0 if g.headless_batch else clampi(int(Bal.v("fx/px_plane", 0.0)), 0, 2)
	return _mode


static func owns_id(game, oid: String) -> bool:
	if game == null or not IDS.has(oid):
		return false
	return of(game).mode() > 0


func _meta(k: String) -> Dictionary:
	if meta.is_empty():
		for mp in METAS:
			var f := FileAccess.open(mp, FileAccess.READ)
			if f != null:
				var v = JSON.parse_string(f.get_as_text())
				if v is Dictionary:
					meta.merge(v)
	return meta.get(k, {})


func _tex(k: String) -> Texture2D:
	if not tex.has(k):
		var p: String = ART % k
		tex[k] = load(p) if ResourceLoader.exists(p) else null
	return tex[k]


## 动画时钟（fps）：15 = 统一节拍
func clock() -> float:
	return Bal.v("fx/px_plane_fps", 15.0)


## 帧号：统一节拍时按全局 15 fps 拍子数（同屏同拍换帧）；否则按自己的年龄 × 小数帧率
func frame_of(t0: float) -> int:
	var c: float = clock()
	if is_equal_approx(c, 15.0):
		return int(floor(g.t * 15.0)) - int(floor(t0 * 15.0))
	return int((g.t - t0) * c)


func tier(o) -> int:
	var f: float = Bal.v("fx/px_plane_tier", -1.0)   # 三档图用：强制某一档画面（只改画面）
	if f >= 0.0:
		return clampi(int(f), 0, 2)
	return clampi(int(o.elite), 0, 2)


## 平面角 → [预生成方向, 是否水平翻转]
static func pick_dir(ang: float) -> Array:
	var a: float = wrapf(rad_to_deg(ang), -180.0, 180.0)
	var flip := false
	if absf(a) > 90.0:
		a = wrapf(180.0 - a, -180.0, 180.0)
		flip = true
	var best: int = 0
	for d in DIRS:
		if absf(a - d) < absf(a - best):
			best = d
	return [best, flip]


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


# ================================================================ 事件（fx_recipe._ev 转来；只记画面）

func ev(o, kind: String, d: Dictionary) -> void:
	var raw: bool = mode() == 2
	var t: int = tier(o)
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var p: Dictionary = R.pal(o)
	if str(o.id) == "hoshiguma":
		_ev_hsg(o, kind, d, raw, t, R, p)
		return
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			if Bal.v("fx/recipe_log", 0.0) > 0.0:
				print("PXPLOG %s %s %d" % [src, "c" if d.get("circle", false) else "%.2f" % float(d.get("half", 0.0)), Engine.get_process_frames()])
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 60.0))
				if src == "大剑":   # 冲刺收尾的响应横扫（圆形）：按全向旋斩画
					_add(o, "spin_e%d" % t, c, 0.0, r, raw, "raw_spin_e%d" % t, 62.0)
				elif r >= 160.0:
					_add_gd(o, "s3cast", c, raw, "raw_ring_e2", r, 92.0)
				else:
					_add_gd(o, "pulse_e%d" % t, c, raw, "raw_ring_e%d" % t, r, 60.0)
				_burst(o, R, p, c + Vector2(0, -10), c.y + 4.0, d.get("es", []), 4 + 2 * t, 120.0, 0.45)
				return
			var ang: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 112.0))
			var dv := Vector2.from_angle(ang)
			var es: Array = d.get("es", [])
			match src:
				"大剑", "反手斩":
					if float(d.get("half", 1.4)) >= 3.1:
						var big: bool = r2 >= 160.0
						_add(o, "spin_s3" if big else "spin_e%d" % t, o.pos, 0.0, r2, raw, "raw_spin_e%d" % t, 62.0)
						_cuts(o, es, t, 3)
						_burst(o, R, p, o.pos + dv * r2 * 0.5 + Vector2(0, -12), o.pos.y + dv.y * r2 * 0.5 * 0.72, es, 3 + t, 110.0, 0.35)
					else:
						_add(o, "basic_e%d" % t, o.pos, ang, r2, raw, "raw_basic_e%d" % t, 56.0)
						_cuts(o, es, t, 2)
						_burst(o, R, p, o.pos + dv * r2 * 0.6 + Vector2(0, -12), o.pos.y + dv.y * r2 * 0.6 * 0.72, es, 2 + t, 90.0, 0.3)
				"迅捷打击·γ型":
					_add(o, "s1_e%d" % t, o.pos, ang, r2, raw, "raw_s1_e%d" % t, 73.0)
					_cuts(o, es, t, 4)
					_burst(o, R, p, o.pos + dv * r2 * 0.6 + Vector2(0, -14), o.pos.y + dv.y * r2 * 0.6 * 0.72, es, 4 + 2 * t, 140.0, 0.5)
				"跃浪击":
					# 跃浪击（11-05 用户「每个技能要做出视觉上的区别」）：不用月牙，前方立起一道弧形水墙、往前卷倒拍下
					var at: Vector2 = o.pos + Vector2(dv.x, dv.y * 0.72) * r2 * 0.56
					var tt: int = maxi(t, 1)
					if raw:
						_add_up(o, "s2_e%d" % tt, at, raw, "raw_splash_e%d" % tt, r2, 75.0, ang)
					else:
						_add_dir(o, "s2_e%d" % tt, o.pos, ang)
					_burst(o, R, p, at + Vector2(0, -30), at.y, es, 7 + 2 * tt, 170.0, 0.7)
				"破浪下劈":
					var at2: Vector2 = o.pos + Vector2(dv.x, dv.y * 0.72) * r2 * 0.5
					var t2: int = maxi(t, 1)
					_add_up(o, "leap_e%d" % t2, at2, raw, "raw_splash_e%d" % t2, r2, 65.0, ang)
					_add_gd(o, "leap_e%d" % t2, at2, raw, "", r2, 65.0)
					_burst(o, R, p, at2 + Vector2(0, -22), at2.y, es, 5 + t2, 140.0, 0.55)
		"skill":
			if int(d.get("i", -1)) == 2:   # 涌潮悲歌起手：身边冲起一柱大水 + 脚下一圈贴地水环
				_add_gd(o, "s3cast", o.pos, raw, "raw_ring_e2", 185.0, 92.0)
				_add_up(o, "s3cast", o.pos + Vector2(0, 2), raw, "raw_splash_e2", 185.0, 75.0, 0.0)
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -60), o.pos.y, "ink", 8, {"tier": 2})
				R._light(o, o.pos + Vector2(0, -10), 150.0, 0.6, 0.15, p.light)


## 命中：少量大颗水滴（Noita，有重量、落地成水点）+ 一盏照地短光。颗粒、光不随旧做法（2）出现
func _burst(o, R, p: Dictionary, at: Vector2, gy: float, es: Array, n: int, lr: float, li: float) -> void:
	if mode() != 1:
		return
	var m := {"tier": tier(o), "grain_spd": 1.0}
	if not es.is_empty():
		var e: Dictionary = es[0]
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
		R._grains(o, hp, float(e.pos.y) + 2.0, "ink", mini(n, 2 + es.size()), m, (hp - o.pos).normalized())
		R._light(o, hp, lr, li, 0.12, p.light)
	else:
		R._grains(o, at, gy, "ink", maxi(1, n / 2), m)
		R._light(o, at, lr * 0.8, li * 0.6, 0.1, p.light)


## 命中斩痕（刀剑感：被砍中的那只身上一道 1 美术像素白芯的斜线，3 拍收掉；精二交叉成 X）。只在转平面版；至多 n 只（离斯卡蒂由近到远）
func _cuts(o, es: Array, t: int, n: int) -> void:
	if mode() != 1 or es.is_empty():
		return
	var lst: Array = es.duplicate()
	lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
	for i in mini(n, lst.size()):
		var e: Dictionary = lst[i]
		var rd: Vector2 = (e.pos - o.pos)
		var tg: Vector2 = Vector2(-rd.y, rd.x).normalized() if rd.length() > 1.0 else Vector2.RIGHT
		tg = tg.rotated(-0.45 if tg.x * tg.y >= 0.0 else 0.45)   # 斜一点，不是正横正竖
		_push({"cut": true, "t0": g.t, "gp": e.pos + Vector2(0, -float(e.r) * 0.55), "gy": float(e.pos.y) + 1.0, "d": tg, "x": t >= 2, "L": 9.0 + 2.0 * t + minf(6.0, float(e.r) * 0.25), "ly": "up", "oid": str(o.id), "k": ""})


func _push(it: Dictionary) -> void:
	if items.size() >= ITEM_MAX:
		items.pop_front()
	items.append(it)


## 横扫 / 旋斩：立起层（刀光幕）+ 贴地层（接触阴影 + 水痕），同一个原点（脚底）
func _add(o, key: String, at: Vector2, ang: float, r: float, raw: bool, rawk: String, fit: float) -> void:
	if raw:
		_push({"k": rawk, "t0": g.t, "gp": at + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	# 11-05 用户「还有碎斩击」：同一名干员出新一刀时，只留上一刀（正在收）+ 这一刀，更早的刀痕立刻收掉
	var sl: Array = []
	for it in items:
		if str(it.oid) == str(o.id) and it.get("slash", false) and str(it.ly) == "up":
			sl.append(it.t0)
	if sl.size() >= 2:
		sl.sort()
		var keep_t: float = float(sl[sl.size() - 1])
		items = items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == str(o.id) and float(it.t0) < keep_t))
	var dk: Array = pick_dir(ang)
	var spin: bool = key.begins_with("spin")
	var ku: String = (key + "_up") if spin else "%s_up_d%d" % [key, dk[0]]
	var kg: String = (key + "_gd") if spin else "%s_gd_d%d" % [key, dk[0]]
	_push({"k": ku, "t0": g.t, "gp": _snap(at), "flip": dk[1] and not spin, "ly": "up", "oid": str(o.id), "slash": true})
	_push({"k": kg, "t0": g.t, "gp": _snap(at), "flip": dk[1] and not spin, "ly": "gd", "oid": str(o.id), "slash": true})


## 方向件（不是斩击：不参与「只留最近两刀」）
func _add_dir(o, key: String, at: Vector2, ang: float) -> void:
	var dk: Array = pick_dir(ang)
	_push({"k": "%s_up_d%d" % [key, dk[0]], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "up", "oid": str(o.id)})
	_push({"k": "%s_gd_d%d" % [key, dk[0]], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "gd", "oid": str(o.id)})


func _add_up(o, key: String, at: Vector2, raw: bool, rawk: String, r: float, fit: float, ang: float) -> void:
	if raw:
		_push({"k": rawk, "t0": g.t, "gp": at + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	_push({"k": key + "_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": str(o.id)})


func _add_gd(o, key: String, at: Vector2, raw: bool, rawk: String, r: float, fit: float) -> void:
	if raw:
		if rawk != "":
			_push({"k": rawk, "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	_push({"k": key + "_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})


func _step() -> void:
	var now: float = g.t
	items = items.filter(func(it): return now - float(it.t0) < _life(str(it.k)) + 0.02)


func _life(k: String) -> float:
	if k == "":
		return 3.0 / 15.0   # 斩痕 3 拍
	var m: Dictionary = _meta(k)
	if m.is_empty():
		return 0.0
	return float(m.n) / minf(minf(float(m.fps), Bal.v("fx/px_plane_raw_fps", 12.8)), clock()) + 0.07


# ================================================================ 绘制

## 地面层（data_operator.draw_entities_floor → fx_recipe.draw_floor 转来）：贴地件、潮刃 / 浪墙的地面尾迹
func draw_floor(o) -> void:
	_step()
	if mode() != 1:
		return
	var cv = o.cv
	var id: String = str(o.id)
	if id == "hoshiguma":
		_floor_hsg(o)
		return
	if o.skill_active_left(2) > 0.0:   # 涌潮悲歌持续期间：脚下一滩积水（循环，跟着人走）
		_draw_strip(cv, "pool_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), it.gp, it.flip, true)
	_wall_spawn(o)
	for w in _waves(o):
		_draw_strip(cv, w[0] + "_gd_d%d" % w[3], frame_of(0.0), w[1], w[2], false)


## 上层（_draw_skill_over → fx_recipe.draw_over 转来）：旧做法（2）的整张贴图都画在这里（盖在所有单位上）
func draw_over(o) -> void:
	if mode() != 2:
		return
	var cv = o.cv
	var id: String = str(o.id)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8)), it.gp, float(it.rot), float(it.sc))
	if id == "hoshiguma":   # 般若回旋的锯盾：旧做法整张贴（正圆、光晕烤进颜色、盖在上面）
		for bm in _booms(o):
			_draw_raw(cv, "hsg_raw_saw", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(_meta("hsg_raw_saw").get("n", 1))), o.pos + bm.dir * _boom_d(bm) + Vector2(0, -22), 0.0, g.PX)
		return
	for w in o.hw.get("waves", []):
		var b: Dictionary = w.b
		if not b.has("proj") and not b.has("tex"):
			continue
		var big: bool = not b.has("proj")
		_draw_raw(cv, "raw_blade", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(_meta("raw_blade").get("n", 1))), w.pos + Vector2(0, -16), (w.dir as Vector2).angle(), g.PX * (float(w.w) * 0.5) / 26.0 * (1.0 if not big else 1.0))


## world._sorted_fast 的排序项（kind 7）：立起件按脚底 y 排进单位层
static func sort_items(game) -> Array:
	if game == null or not game.has_meta("fx_pxplane"):
		return []
	var r = game.get_meta("fx_pxplane")
	if r.mode() != 1:
		return []
	var out: Array = []
	for it in r.items:
		if str(it.ly) == "up":
			out.append(it)
	for o in game.squad.ops:
		if IDS.has(str(o.id)) and o.pos != Vector2.INF:
			for w in r._waves(o):
				out.append({"wave": w})
			if str(o.id) == "hoshiguma":
				for bm in r._booms(o):
					out.append({"k": "hsg_saw_up", "t0": 0.0, "gp": r._boom_gp(o, bm), "flip": false, "loop": true})
	return out


static func draw_sorted(game, ci, it: Dictionary) -> void:
	var r = game.get_meta("fx_pxplane")
	if it.has("wave"):
		var w: Array = it.wave
		r._draw_strip(ci, w[0] + "_up_d%d" % w[3], r.frame_of(0.0), w[1], w[2], false)
		return
	if it.get("cut", false):
		r._draw_cut(ci, it)
		return
	r._draw_strip(ci, str(it.k), r.frame_of(float(it.t0)), it.gp, it.flip, not it.get("loop", false))


## 斩痕：沿方向逐美术像素画（2 世界像素格），第 0 拍白芯 + 两侧浅蓝、第 1 拍浅蓝变短、第 2 拍只剩两头几点
func _draw_cut(ci, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	if f < 0 or f > 2:
		return
	var px: float = g.PX
	var c0: Vector2 = _snap(it.gp)
	var dirs: Array = [it.d]
	if it.x:
		dirs.append((it.d as Vector2).rotated(1.25))
	var core := Color(1, 1, 1) if f == 0 else Color.html("#cddcfb")
	var side := Color.html("#93b4f7") if f == 0 else Color.html("#598cf2")
	var L: float = float(it.L) * [1.0, 0.8, 0.5][f]
	for d in dirs:
		var dv: Vector2 = d
		var nv := Vector2(-dv.y, dv.x)
		var m: int = int(L)
		for i in range(-m, m + 1):
			if f == 2 and absi(i) < m - 2:
				continue
			var w: float = 1.0 - absf(float(i)) / float(m + 1)   # 两头收尖
			var p: Vector2 = _snap(c0 + dv * float(i) * px)
			ci.draw_rect(Rect2(p, Vector2(px, px)), core if w > 0.25 else side)
			if f == 0 and w > 0.55:
				ci.draw_rect(Rect2(_snap(p + nv * px), Vector2(px, px)), side)
			if f == 0 and w > 0.4 and g.optical_on and _emit_n < EMIT_CAP and (i & 1) == 0:
				_emit_n += 1
				g.glow_next.append([p, px, Color(1, 1, 1, Bal.v("fx/px_plane_emit", 0.8))])


static func sort_key(it: Dictionary) -> float:
	if it.has("wave"):
		return float((it.wave[1] as Vector2).y) + 2.0
	if it.get("cut", false):
		return float(it.gy)
	return float((it.gp as Vector2).y) + 1.0 + float(it.get("sk", 0.0))   # sk：身后半圈的件往前排（星熊地刺）


## 「跃浪」浪墙：推进途中每两拍（15 fps）在浪头位置生成一道小碎浪（一次性件，原点放在浪头后方 36 美术像素，让碎浪的浪线落在浪头上）。
## 只读玩法状态，画面计时记在浪字典的 _pxs（玩法不读）
func _wall_spawn(o) -> void:
	if mode() != 1 or o.hw.is_empty() or not o.hw.has("waves"):
		return
	var tick: int = int(floor(g.t * 15.0))
	var t: int = clampi(tier(o), 1, 2)
	for w in o.hw.waves:
		if w.b.has("proj"):
			continue
		if w.has("_pxs") and tick - int(w._pxs) < 2:
			continue
		w["_pxs"] = tick
		var dv: Vector2 = w.dir
		var org: Vector2 = w.pos - Vector2(dv.x, dv.y * 0.72) * 36.0 * g.PX
		_add_dir(o, "wallbrk_e%d" % t, org, dv.angle())


## 潮刃（弹体式）：直接读玩法状态 o.hw.waves → [帧条前缀, 地面点, 翻转, 方向]（浪墙改由 _wall_spawn 生成碎浪，不在这里）
func _waves(o) -> Array:
	var out: Array = []
	if o.hw.is_empty() or not o.hw.has("waves"):
		return out
	for w in o.hw.waves:
		var b: Dictionary = w.b
		if not b.has("proj"):
			continue
		var dk: Array = pick_dir((w.dir as Vector2).angle())
		out.append(["blade" if b.has("proj") else "wall", _wpos(w), dk[1], dk[0]])
	return out


## 潮刃 / 浪墙的画面位置：统一节拍时每 1/15 秒才跳一次格（对齐 2 世界像素 = 1 美术像素）；对照档平滑跟随。
## 记在浪自己的字典里（画面专用键 _pxq，玩法不读）
func _wpos(w: Dictionary) -> Vector2:
	if not is_equal_approx(clock(), 15.0):
		return w.pos
	var tick: int = int(floor(g.t * 15.0))
	var q = w.get("_pxq")
	if q == null or int(q[0]) != tick:
		q = [tick, _snap(w.pos)]
		w["_pxq"] = q
	return q[1]


## 一张帧条的一帧：1 帧条像素 = g.PX 世界像素（整数倍），原点对齐 2 像素格；不旋转（方向靠预生成 + 水平翻转）
func _draw_strip(ci, k: String, fi: int, gp: Vector2, flip: bool, once: bool, mod := Color.WHITE) -> void:
	var m: Dictionary = _meta(k)
	var tx: Texture2D = _tex(k)
	if m.is_empty() or tx == null:
		return
	var n: int = int(m.n)
	if once and (fi < 0 or fi >= n):
		return
	fi = posmod(fi, n)
	var w: float = float(m.w)
	var h: float = float(m.h)
	var px: float = g.PX
	var top: float = gp.y - float(m.oy) * px
	var left: float = gp.x - (w - float(m.ox)) * px if flip else gp.x - float(m.ox) * px
	var src := Rect2(fi * w, 0.0, w, h)
	if flip:
		ci.draw_texture_rect_region(tx, Rect2(Vector2(left + w * px, top), Vector2(-w * px, h * px)), src, mod)
	else:
		ci.draw_texture_rect_region(tx, Rect2(Vector2(left, top), Vector2(w * px, h * px)), src, mod)
	_emit(m, fi, Vector2(left, top), w, flip)


## 热芯像素进光学发光层（同 world._glow_pts 的格式：[左上角, 边长, 颜色]）
func _emit(m: Dictionary, fi: int, tl: Vector2, w: float, flip: bool) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	var pts: Array = m.emit[fi] if fi < m.emit.size() else []
	var px: float = g.PX
	var k: float = Bal.v("fx/px_plane_emit", 0.8)
	for q in pts:
		if _emit_n >= EMIT_CAP:
			return
		_emit_n += 1
		var x: float = float(q[0])
		if flip:
			x = w - 1.0 - x
		var c: Color = _hexc(str(q[2]))
		g.glow_next.append([tl + Vector2(x, float(q[1])) * px, px, Color(c.r, c.g, c.b, k)])


func _hexc(s: String) -> Color:
	if not _ecol.has(s):
		_ecol[s] = Color.html(s)
	return _ecol[s]


## 旧做法：光晕烤进颜色的帧条，按判定半径小数缩放、旋转，中心对原点
func _draw_raw(cv, k: String, fi: int, at: Vector2, rot: float, sc: float) -> void:
	var m: Dictionary = _meta(k)
	var tx: Texture2D = _tex(k)
	if m.is_empty() or tx == null:
		return
	if fi < 0 or fi >= int(m.n):
		return
	var w: float = float(m.w)
	var h: float = float(m.h)
	cv.draw_set_transform(at, rot, Vector2(sc, sc))
	cv.draw_texture_rect_region(tx, Rect2(Vector2(-float(m.ox), -float(m.oy)), Vector2(w, h)), Rect2(fi * w, 0.0, w, h))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ================================================================ 星熊（docs/248，照 docs/246 斯卡蒂的做法）
## 普攻「盾斧斩」= 腰高钝头刀痕（精一盾缘崩钢屑、精二暖金副刃 + 金火星；精二另有「般若回旋」锯盾）；
## S1「战意」= 立起的下劈弧 + 裂网冲击环 + 碎石（精一尘墙、精二裂缝熔成暖金）；
## S2「荆棘」= 起手一圈地刺破土 + 每斩留的热砂（只画边 + 内边 + 几点热光）；
## S3「力之锯」= 起手腰高青绿弧旋起 + 直线撕裂（贴地撕裂沟 + 低处锯线 + 远端暖金火星），持续时脚下一圈转动的齿印。

func _ev_hsg(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			var es: Array = d.get("es", [])
			if d.get("line", false):   # 力之锯：直线斩（seg_hoshiguma.exec_line 的钩子）
				var ang: float = float(d.get("ang", 0.0))
				var L: float = float(d.get("len", 220.0))
				var dv := Vector2.from_angle(ang)
				if raw:
					_push({"k": "hsg_raw_rip", "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (L * 0.5) / 110.0, "oid": str(o.id)})
				else:
					_add_dir(o, "hsg_rip", o.pos, ang)
				_cuts(o, es, 2, 3)
				_burst_m(o, R, p, o.pos + dv * L * 0.9 + Vector2(0, -12), o.pos.y + dv.y * L * 0.9, es, 6, "shard", 130.0, 0.5)
				return
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 60.0))
				match src:
					"举盾反击":   # S1 战意：下劈 + 裂网冲击环（判定圈以星熊为心）
						var fl: bool = float(o.face) < 0.0
						if raw:
							_push({"k": "hsg_raw_slam_e%d" % t, "t0": g.t, "gp": c, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 75.0, "oid": str(o.id)})
						else:
							_push({"k": "hsg_slam_e%d_up" % t, "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "up", "oid": str(o.id)})
							_push({"k": "hsg_slam_e%d_gd" % t, "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "gd", "oid": str(o.id)})
						_cuts(o, es, t, 4)
						_burst_m(o, R, p, c + Vector2(-30.0 if fl else 30.0, -6), c.y + 2.0, es, 8 + 3 * t, "rock", 200.0, 0.8)
					"热砂", "热砂沸腾":
						pass   # 热砂每 0.5 秒结算一次：画面由区域本身（_floor_hsg 读 o.fields）表现，不逐跳画
					_:   # 般若之重 / 盾墙反震：贴地冲击环
						if not raw:
							_push({"k": "hsg_pulse_gd", "t0": g.t, "gp": _snap(c), "flip": false, "ly": "gd", "oid": str(o.id)})
						_burst_m(o, R, p, c + Vector2(0, -8), c.y + 2.0, es, 3, "rock", 110.0, 0.4)
				return
			# 锥形：盾斧斩（普攻）
			var ang2: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 94.0))
			var dv2 := Vector2.from_angle(ang2)
			_add(o, "hsg_sweep_e%d" % t, o.pos, ang2, r2, raw, "hsg_raw_sweep_e%d" % t, 47.0)
			_cuts(o, es, t, 2)
			_burst_m(o, R, p, o.pos + dv2 * r2 * 0.6 + Vector2(0, -12), o.pos.y + dv2.y * r2 * 0.6 * 0.72, es, 2 + t, "shard" if t >= 1 else "rock", 90.0, 0.35)
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1:   # 荆棘起手：一圈地刺破土（身后半圈排在她身后、身前半圈排在她身前）
				var tt: int = maxi(t, 1)
				if raw:
					_push({"k": "hsg_raw_thorns_e%d" % tt, "t0": g.t, "gp": o.pos + Vector2(0, -8), "ly": "raw", "rot": 0.0, "sc": g.PX, "oid": str(o.id)})
				else:
					_push({"k": "hsg_thorns_e%d_back_up" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "sk": -8.0})
					_push({"k": "hsg_thorns_e%d_front_up" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "sk": 4.0})
					_push({"k": "hsg_thorns_e%d_gd" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -20), o.pos.y, "shard", 6 + 3 * tt, {"tier": tt})
					R._light(o, o.pos + Vector2(0, -10), 120.0, 0.5, 0.15, p.accent)
			elif i == 2:   # 力之锯起手：腰高三道青绿弧旋起 + 脚下冲击环
				if raw:
					_push({"k": "hsg_raw_slam_e2", "t0": g.t, "gp": o.pos, "ly": "raw", "rot": 0.0, "sc": g.PX * 50.0 / 75.0, "oid": str(o.id)})
				else:
					_push({"k": "hsg_s3cast_up", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id)})
					_push({"k": "hsg_s3cast_gd", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if mode() == 1:
					R._light(o, o.pos + Vector2(0, -20), 140.0, 0.6, 0.15, p.light)


## 命中：少量颗粒（材质可选）+ 一盏照地短光；只在转平面版
func _burst_m(o, R, p: Dictionary, at: Vector2, gy: float, es: Array, n: int, mat: String, lr: float, li: float) -> void:
	if mode() != 1:
		return
	var m := {"tier": tier(o), "grain_spd": 1.0}
	if not es.is_empty():
		var e: Dictionary = es[0]
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
		R._grains(o, hp, float(e.pos.y) + 2.0, mat, mini(n, 2 + es.size()), m, (hp - o.pos).normalized())
		R._light(o, hp, lr, li, 0.12, p.light)
	else:
		R._grains(o, at, gy, mat, maxi(1, n / 2), m)
		R._light(o, at, lr * 0.8, li * 0.6, 0.1, p.light)


## 地面层（星熊）：贴地件、热砂（读 o.fields，循环 + 淡入淡出）、力之锯持续时脚下齿印、锯盾影子
func _floor_hsg(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var t: int = clampi(tier(o), 1, 2)
	for f in o.fields:
		if not f.get("sand", false):
			continue
		var fa: float = clampf((float(f.n) * float(f.every) - float(f.t)) / 0.4, 0.0, 1.0) * clampf(float(f.t) / 0.15, 0.0, 1.0)
		if fa <= 0.0:
			continue
		var rk: int = 40 if float(f.r) >= 70.0 else 30
		_draw_strip(cv, "hsg_sand%d_e%d_gd" % [rk, t], frame_of(0.0), _snap(f.pos), false, false, Color(1, 1, 1, fa))
	if o.skill_active_left(2) > 0.0:
		_draw_strip(cv, "hsg_s3aura_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), it.gp, it.flip, true)
	for bm in _booms(o):
		_draw_strip(cv, "hsg_saw_gd", frame_of(0.0), _boom_gp(o, bm), false, false)


## 般若回旋：读玩法状态 o.el.boom（往返弹体）
func _booms(o) -> Array:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or not el.has("boom"):
		return []
	return el.boom


## 弹体此刻离星熊的距离（同 ob_elite._el_boom_d，纯函数抄一份，只读）
static func _boom_d(bm: Dictionary) -> float:
	var t: float = float(bm.t)
	var to: float = float(bm.to)
	if t < to:
		var k: float = t / maxf(0.01, to)
		return float(bm.L) * (1.0 - (1.0 - k) * (1.0 - k))
	if t < to + float(bm.hold):
		return float(bm.L)
	var k2: float = clampf((t - to - float(bm.hold)) / maxf(0.01, float(bm.tb)), 0.0, 1.0)
	return float(bm.L) * (1.0 - k2 * k2)


## 锯盾的地面点：统一节拍时每 1/15 秒跳一格（记在弹体字典的画面专用键 _pxq，玩法不读）
func _boom_gp(o, bm: Dictionary) -> Vector2:
	var p: Vector2 = o.pos + bm.dir * _boom_d(bm)
	if not is_equal_approx(clock(), 15.0):
		return p
	var tick: int = int(floor(g.t * 15.0))
	var q = bm.get("_pxq")
	if q == null or int(q[0]) != tick:
		q = [tick, _snap(p)]
		bm["_pxq"] = q
	return q[1]
