## pixelfx「转平面」试验（docs/246，11-05 用户「把 pixelfx 的二维平面转移到我们这个平面上来，再结合 Noita 特效」）：斯卡蒂（docs/246）、星熊（docs/254）、流明（docs/255）、艾雅法拉（docs/259），各自一节在文件后部。
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
const METAS := {"res://data/pxp_skadi.json": "", "res://data/pxp_hoshiguma.json": "", "res://data/pxp_lumen.json": "lm_", "res://data/pxp_eyjafjalla.json": "ey_"}   # 帧条表 → 键前缀（星熊表里的键自带 hsg_；流明帧条 art/fx/pxp/pxp_lm_<键>.png）
const ART := "res://art/fx/pxp/pxp_%s.png"
const IDS := {"skadi": true, "hoshiguma": true, "lumen": true, "eyjafjalla": true}
## 接管时仍照画的原 pfx 帧条（状态提示，不属于攻击特效）：星熊格挡闪光、反击架势盾沿光
const KEEP_PFX := {"hoshiguma": {"fx_hoshiguma_block": true, "fx_hoshiguma_guard_glow": true}}
const LM_C := [Color("#121a2a"), Color("#1d3150"), Color("#2a5282"), Color("#4285ad"), Color("#7fb2d6"), Color("#c4e0f2"), Color("#ffffff")]   # house.js OP.lumen 钢蓝 7 阶
const LM_AC := Color("#ff9640")   # 精二点缀灯火橙
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
var _fol_tick := -1


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
		for path in METAS:
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				for kk in v:
					if str(kk) != "_doc":
						meta[str(METAS[path]) + str(kk)] = v[kk]
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
	if str(o.id) == "lumen":
		_ev_lumen(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "eyjafjalla":
		_ev_ey(o, kind, d, raw, t, R, p)
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
	items = items.filter(func(it): return now - float(it.t0) < (float(it.life) if it.has("life") else _life(str(it.k))) + 0.02)
	var tk: int = int(floor(g.t * 15.0))
	if g.ppos != Vector2.INF and tk != _fol_tick:   # 跟着队长走的件（举盾）：位置每拍（15 fps）跳一格，对齐美术像素格
		_fol_tick = tk
		for it in items:
			if it.has("fol"):
				it.gp = _snap(g.ppos + (it.fol as Vector2))


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
	if id == "lumen":
		_lm_draw_floor(o)
		return
	if id == "eyjafjalla":
		_ey_floor(o)
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
	if str(o.id) == "lumen" and o.hw.has("lm"):
		_sl()._h3lm_draw_units(o)   # 发光单元是本体附属物（不是攻击特效），接管时照画
	if mode() != 2:
		return
	var cv = o.cv
	var id: String = str(o.id)
	if id == "lumen":
		_lm_draw_raw(o)
		return
	if id == "eyjafjalla":
		_ey_draw_raw(o)
		return
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
			if str(o.id) == "lumen":
				r._lm_sort_items(o, out)
				continue
			if str(o.id) == "eyjafjalla":
				r._ey_sort_items(o, out)
				continue
			for w in r._waves(o):
				out.append({"wave": w})
			if str(o.id) == "hoshiguma":
				for bm in r._booms(o):
					out.append({"k": "hsg_saw_up", "t0": 0.0, "gp": r._boom_gp(o, bm), "flip": false, "loop": true})
				for qv in r._qi_volleys(o):
					out.append({"k": qv.k + "_up_d%d" % qv.d, "fi": qv.f, "gp": qv.gp, "flip": qv.flip})
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
	if it.has("fi"):   # 星熊剑气：帧号按剑气年龄 / 剩余寿命挑
		r._draw_strip(ci, str(it.k), int(it.fi), it.gp, it.flip, true)
		return
	if it.has("ert"):   # 艾雅法拉运行时件（docs/259）
		r._ey_draw_rt(ci, it)
		return
	if it.has("rt"):
		r._lm_draw_rt(ci, it)
		return
	if it.has("loopk"):
		r._draw_strip(ci, str(it.loopk), r.frame_of(0.0), it.gp, false, false, it.get("mod", Color.WHITE))
		return
	if it.get("loop", false) and it.has("life"):   # 循环一次性件（艾雅法拉连携熔岩泡）：带淡入淡出
		r._draw_strip(ci, str(it.k), r.frame_of(0.0), it.gp, false, false, Color(1, 1, 1, r._ey_loop_a(it)))
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
	if it.get("cut", false) or it.has("gy"):
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


# ================================================================ 星熊（docs/254，照 docs/246 斯卡蒂的做法）
## 普攻「盾斧斩」= 腰高钝头刀痕（精一盾缘崩钢屑、精二暖金副刃 + 金火星；精二另有「般若回旋」锯盾）；
## S1「战意」= 立起的下劈弧 + 裂网冲击环 + 碎石（精一尘墙、精二裂缝熔成暖金）；
## S2「荆棘」= 起手一圈地刺破土 + 每斩留的热砂（只画边 + 内边 + 几点热光）；
## S3「力之锯」= 起手腰高青绿弧旋起 + 直线撕裂（贴地撕裂沟 + 低处锯线 + 远端暖金火星），持续时脚下一圈转动的齿印。

func _ev_hsg(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG hsg %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
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
					_add_dir(o, "hsg_rip_l%d" % _bucket(L * 0.5, [110, 140]), o.pos, ang)
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
							var sk: String = "hsg_slam_r%d_e%d" % [_bucket(r * 0.5, [75, 95]), t]
							_push({"k": sk + "_up", "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "up", "oid": str(o.id)})
							_push({"k": sk + "_gd", "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "gd", "oid": str(o.id)})
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
			_add(o, "hsg_sweep_r%d_e%d" % [_bucket(r2 * 0.5, [47, 56, 66]), t], o.pos, ang2, r2, raw, "hsg_raw_sweep_e%d" % t, 47.0)
			_cuts(o, es, t, 2)
			_burst_m(o, R, p, o.pos + dv2 * r2 * 0.6 + Vector2(0, -12), o.pos.y + dv2.y * r2 * 0.6 * 0.72, es, 2 + t, "shard" if t >= 1 else "rock", 90.0, 0.35)
		"cover":   # 技能连携 v2「举盾」：队长身侧立起鬼面大盾 1.5 秒（盾跟着队长走：fol = 相对队长的偏移）
			var sd2: Vector2 = d.get("side", Vector2.RIGHT)
			var off: Vector2 = sd2 * 46.0
			if raw:
				_push({"k": "hsg_raw_slam_e0", "t0": g.t, "gp": g.ppos + off, "ly": "raw", "rot": 0.0, "sc": g.PX * 30.0 / 75.0, "oid": str(o.id)})
			else:
				_push({"k": "hsg_cover_up", "t0": g.t, "gp": _snap(g.ppos + off), "fol": off, "flip": sd2.x < 0.0, "ly": "up", "oid": str(o.id)})
				_push({"k": "hsg_cover_gd", "t0": g.t, "gp": _snap(g.ppos + off), "fol": off, "flip": sd2.x < 0.0, "ly": "gd", "oid": str(o.id)})
			_burst_m(o, R, p, g.ppos + off + Vector2(0, -20), g.ppos.y + off.y + 2.0, [], 6, "shard", 140.0, 0.6)
		"combo_dash":   # 连携技冲刺：沿途几颗碎石（代替通用干员色拖影）
			if mode() == 1:
				var a0: Vector2 = d.get("from", o.pos)
				var b0: Vector2 = d.get("to", o.pos)
				for k in 3:
					var q: Vector2 = a0.lerp(b0, 0.25 + 0.3 * k)
					R._grains(o, q + Vector2(0, -4), q.y + 2.0, "rock", 2, {"tier": 1})
		"combo":   # 连携技「举盾推挡」：盾落点立起大盾往外推 + 队长脚下冲击环与放射推痕
			var cc: Vector2 = d.get("c", o.pos)
			var at: Vector2 = d.get("at", o.pos)
			var sd: Vector2 = d.get("side", Vector2.RIGHT)
			if raw:
				_push({"k": "hsg_raw_slam_e1", "t0": g.t, "gp": cc, "ly": "raw", "rot": 0.0, "sc": g.PX * 70.0 / 75.0, "oid": str(o.id)})
			else:
				var dk: Array = pick_dir(sd.angle() if sd.length() > 0.5 else 0.0)
				_push({"k": "hsg_shove_up_d%d" % dk[0], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "up", "oid": str(o.id)})
				_push({"k": "hsg_shove_gd", "t0": g.t, "gp": _snap(cc), "flip": false, "ly": "gd", "oid": str(o.id)})
			_burst_m(o, R, p, cc + Vector2(0, -10), cc.y + 2.0, d.get("es", []), 8, "rock", 200.0, 0.8)
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
	for qv in _qi_volleys(o):
		_draw_strip(cv, qv.k + "_gd_d%d" % qv.d, int(qv.f), qv.gp, qv.flip, true)


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


## 尺寸档：判定半径（美术像素）挑最近的一档（帧条按几档预生成，游戏只整数放大）
static func _bucket(v: float, opts: Array) -> int:
	var best: int = int(opts[0])
	for x in opts:
		if absf(v - float(x)) < absf(v - float(best)):
			best = int(x)
	return best


## 后期剑气（growth/late_shape → vis_growth._fire_qi）：同一次出手的几道剑气合成一道盾击冲击波（不碎）。
## 只读玩法状态 o.vg.qi；按出手时刻分组：位置 / 方向取平均，横向宽度按道数取 1 / 2 / 3+ 三档。
## 帧：出手第一拍热白（0）→ 常态（1）→ 剩余寿命 < 0.07 秒碎开（2）。位置按 15 fps 节拍跳格（记在剑气字典的画面专用键 _pxq，玩法不读）
func _qi_volleys(o) -> Array:
	var out: Array = []
	if mode() != 1 or o.vg.is_empty() or not o.vg.has("qi") or o.vg.qi.is_empty():
		return out
	var grp: Dictionary = {}
	for q in o.vg.qi:
		var key: int = int(round((g.t - float(q.t)) * 60.0))
		if not grp.has(key):
			grp[key] = {"p": Vector2.ZERO, "v": Vector2.ZERO, "n": 0, "t": float(q.t), "life": float(q.life), "qs": []}
		var e: Dictionary = grp[key]
		e.p += _qpos(q)
		e.v += (q.v as Vector2).normalized()
		e.n += 1
		e.life = minf(float(e.life), float(q.life))
		e.qs.append(q)
	var t: int = tier(o)
	var keys: Array = grp.keys()
	keys.sort()
	keys.reverse()
	for key in keys.slice(0, 2):   # 同屏至多两组（最新两次出手）
		var e: Dictionary = grp[key]
		var n: int = int(e.n)
		var S: int = 10 if n <= 1 else (16 if n == 2 else 22)
		var dk: Array = pick_dir((e.v as Vector2).angle())
		var f: int = 0 if float(e.t) < 1.0 / 15.0 else (2 if float(e.life) < 0.07 else 1)
		out.append({"k": "hsg_qi_s%d_e%d" % [S, t], "d": dk[0], "flip": dk[1], "gp": _snap(e.p / float(n)), "f": f})
	return out


func _qpos(q: Dictionary) -> Vector2:
	if not is_equal_approx(clock(), 15.0):
		return q.p
	var tick: int = int(floor(g.t * 15.0))
	var c = q.get("_pxq")
	if c == null or int(c[0]) != tick:
		c = [tick, q.p]
		q["_pxq"] = c
	return c[1]
# ================================================================ 流明（docs/255，照斯卡蒂 docs/246 的做法）
## 帧条件（tools/pxplane_bake_lumen.py，键前缀 lm_）：光弹命中 / 折光落点 / 荧光治疗 / 出光点 / 沐雨 v3 / 光雨雨区（循环）/ 沛霖水柱 / 灯火不灭起手 · 光圈（循环）· 光爆；
## 线状件在运行时按美术像素格逐格画（光弹、折光、灯塔光柱 + 地面光痕、治疗连线、灯塔守望光扇）：方向任意，不旋转贴图，2 世界像素一格、15 fps 节拍换形。
## 光弹位置每帧走（380 像素 / 秒，按 15 fps 跳格一次跳 25 像素会一卡一卡），只取整到美术像素格；弹头形状按 15 fps 节拍换。
## 旧做法（2）：旧放开版帧条（tools/pixelfx_fx/lumen_ul_ref）光晕烤进颜色，小数缩放 + 旋转，盖在所有单位上。

var _slm = null

func _sl():
	if _slm == null:
		_slm = load("res://scripts/characters/blocks/seg_lumen.gd")   # 运行时取（避免和积木链循环 preload）
	return _slm


func _lm_up(o, k: String, at: Vector2, gy: float) -> void:
	if k.begins_with("hit"):   # 命中水花同屏上限（同一名干员）：主弹至多 5 团、小水花（发光单元 / 额外弹 / 折光 / 连锁 / 光柱穿透）至多 3 团——后期弹多也不叠成一片白
		var small: bool = k.begins_with("hits")
		var n := 0
		for it in items:
			if str(it.oid) == str(o.id) and str(it.k).begins_with("lm_hits" if small else "lm_hit_") and str(it.ly) == "up":
				n += 1
		if n >= (3 if small else 5):
			return
	_push({"k": "lm_" + k, "t0": g.t, "gp": _snap(at), "gy": gy, "flip": false, "ly": "up", "oid": str(o.id)})


func _lm_gd(o, k: String, at: Vector2) -> void:
	_push({"k": "lm_" + k, "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})


func _lm_raw(o, k: String, at: Vector2, rot: float, sc: float) -> void:
	_push({"k": "lm_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


func _ev_lumen(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var px: float = g.PX
	match kind:
		"lm_hit":   # 光弹命中：立起水花（原点 = 命中点，按敌人脚底排序）+ 地上湿痕；发光单元的弹小一号、不留湿痕
			var e: Dictionary = d.e
			var at: Vector2 = d.at
			var small: bool = d.get("unit", false)
			if raw:
				_lm_raw(o, "raw_hit_e%d" % t, at, 0.0, px * (0.75 if small else 1.15))
				return
			_lm_up(o, ("hits_e%d_up" if small else "hit_e%d_up") % t, at, float(e.pos.y) + 1.0)
			if not small:
				_lm_gd(o, "hit_e%d_gd" % t, e.pos + Vector2(0, 2))
			_burst(o, R, p, at, float(e.pos.y) + 2.0, [e], (1 if small else 2) + t, 60.0 + 15.0 * t, 0.3 + 0.1 * t)
		"lm_refract":   # 精一折光：命中点到下一只之间一道 1 美术像素白芯细光，落点小水花
			var a: Vector2 = d.a
			var b: Vector2 = d.b
			if raw:
				_push({"rt": "rawline", "a": a, "b": b, "t0": g.t, "life": 0.12, "ly": "raw", "oid": str(o.id), "k": ""})
				_lm_raw(o, "raw_hit_e1", b, 0.0, px * 0.6)
				return
			_push({"rt": "line", "a": a, "b": b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", b.y + 10.0)), "oid": str(o.id), "k": ""})
			_lm_up(o, "hits_e%d_up" % t, b, float(d.get("gy", b.y + 10.0)))
			R._light(o, b, 60.0, 0.35, 0.1, p.light)
		"lm_pillar":   # 精二灯塔光柱：出光点一颗四芒星 + 一道实心光柱（任意方向逐格画）+ 地上一道光痕；命中的前 4 只各一团水花
			var from: Vector2 = d.from
			var dv: Vector2 = d.d
			var L: float = float(d.L)
			var foot: Vector2 = d.get("foot", from)
			var es: Array = d.get("es", [])
			if raw:
				_lm_raw(o, "raw_pillar", from, dv.angle(), px * L / 200.0 * 1.13)
				for e in es.slice(0, 4):
					_lm_raw(o, "raw_hit_e2", e.pos + Vector2(0, -float(e.r) * 0.5), 0.0, px * 1.15)
				return
			_push({"rt": "beam", "a": _snap(from), "d": dv, "L": L, "W": float(d.get("W", 10.0)), "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": foot.y + 1.0, "oid": str(o.id), "k": ""})
			_push({"rt": "streak", "a": _snap(foot), "d": dv, "L": L, "t0": g.t, "life": 3.0 / 15.0, "ly": "gd", "oid": str(o.id), "k": ""})
			_lm_up(o, "flare_up", from, foot.y + 2.0)
			R._light(o, from, 90.0, 0.55, 0.12, p.light)
			R._light(o, foot + dv * L * 0.6, 110.0, 0.35, 0.12, p.light)
			for e in es.slice(0, 3):   # 一线穿透：每只一团小水花（至多 3 团），不叠成一片白
				var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
				_lm_up(o, "hits_e2_up", hp, float(e.pos.y) + 1.0)
			if not es.is_empty():
				_burst(o, R, p, from, foot.y, [es[0]], 3, 70.0, 0.4)
		"lm_mend":   # 荧光治疗：队长身前一侧卷上去一缕水流
			var at2: Vector2 = d.at
			for it in items:   # 沐雨同一拍也会回血：只画沐雨，不再叠一缕水流（同一招元素 ≤ 3）
				if str(it.k).begins_with("lm_drizzle") or str(it.k).begins_with("lm_raw_drizzle"):
					if is_equal_approx(float(it.t0), g.t):
						return
			if raw:
				_lm_raw(o, "raw_mend_e%d" % t, at2, 0.0, px * 1.15)
				return
			_lm_up(o, "mend_e%d_up" % t, at2, at2.y + 1.0)
			R._light(o, at2 + Vector2(0, -30), 70.0, 0.35, 0.12, p.light)
		"lm_link":   # 提灯到治疗落点的细光（2 拍）
			if raw:
				_push({"rt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": 0.25, "ly": "raw", "oid": str(o.id), "k": ""})
				return
			_push({"rt": "link", "a": d.a, "b": d.b, "t0": g.t, "life": 2.0 / 15.0, "ly": "up", "gy": (d.b as Vector2).y + 24.0, "oid": str(o.id), "k": ""})
		"lm_xhit":   # 后期额外弹命中：小一号水花；同一拍至多 3 团（弹数随档位增加，画面不跟着碎）
			var xe: Dictionary = d.e
			if _lm_beat_n(o, "xh") >= 3:
				return
			if raw:
				_lm_raw(o, "raw_hit_e%d" % t, d.at, 0.0, px * 0.75)
				return
			_lm_up(o, "hits_e%d_up" % t, d.at, float(xe.pos.y) + 1.0)
		"lm_chain":   # 「连锁」弹射：同折光一套 1 美术像素细光；同一拍至多 3 道
			if _lm_beat_n(o, "ch") >= 3:
				return
			if raw:
				_push({"rt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": 0.14, "ly": "raw", "oid": str(o.id), "k": ""})
				return
			_push({"rt": "line", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
			_lm_up(o, "hits_e%d_up" % t, d.b, float(d.get("gy", 0.0)))
		"lm_cshot":   # 连携技「清创光弹」出手：一颗大光弹飞向队长
			if raw:
				_push({"rt": "rawcbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "raw", "oid": str(o.id), "k": ""})
				return
			_push({"rt": "cbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "up", "gy": (d.b as Vector2).y + 31.0, "oid": str(o.id), "k": ""})
			R._light(o, d.a, 70.0, 0.4, 0.1, p.light)
		"lm_lfire":   # 连携 v2「清创光弹」（skill_link l_lumen）：提灯一颗大光弹 0.13 秒飞到队长胸口 → 炸开（同 lm_cleanse）；连携区域 1.2 秒内光尘往上飘
			var la: Vector2 = d.a
			var lt: Vector2 = d.at
			var lc: Vector2 = d.c
			if raw:
				_push({"rt": "rawcbolt", "a": la, "b": lt + Vector2(0, -30), "t0": g.t, "life": 0.13, "ly": "raw", "oid": str(o.id), "k": ""})
				_lm_raw(o, "raw_hit_e2", lt + Vector2(0, -30), 0.0, px * 1.7)
				return
			_push({"rt": "cbolt", "a": la, "b": lt + Vector2(0, -30), "t0": g.t, "life": 0.13, "ly": "up", "gy": lt.y + 1.0, "oid": str(o.id), "k": ""})
			var t1: float = g.t + 0.13
			_push({"k": "lm_cleanse_up", "t0": t1, "gp": _snap(lt + Vector2(0, -30)), "gy": lt.y + 1.0, "flip": false, "ly": "up", "oid": str(o.id)})
			_push({"k": "lm_cleanse_gd", "t0": t1, "gp": _snap(lc), "flip": false, "ly": "gd", "oid": str(o.id)})
			_push({"k": "lm_lmotes_up", "t0": t1, "gp": _snap(lc), "gy": lc.y + 1.0, "flip": false, "ly": "up", "oid": str(o.id)})
			R._light(o, lt + Vector2(0, -20), 170.0, 0.8, 0.15, p.light)
			R._grains(o, lt + Vector2(0, -30), lt.y, "ink", 4, {"tier": 1})
		"lm_cleanse":   # 连携技落点：队长胸口一团大水花 + 灯火橙光尘上飘；地上照亮范围边弧原地闪一下
			var ct: Vector2 = d.at
			if raw:
				_lm_raw(o, "raw_hit_e2", ct + Vector2(0, -30), 0.0, px * 1.7)
				return
			_lm_up(o, "cleanse_up", ct + Vector2(0, -30), ct.y + 1.0)
			_lm_gd(o, "cleanse_gd", ct)
			R._light(o, ct + Vector2(0, -20), 170.0, 0.8, 0.15, p.light)
			R._grains(o, ct + Vector2(0, -30), ct.y, "ink", 4, {"tier": 1})
		"lm_burst":   # 灯火不灭结束光爆：短粗双层星芒 + 竖光柱；地上判定半径边弧原地闪一下
			var at3: Vector2 = d.at
			if raw:
				_lm_raw(o, "raw_burst", at3, 0.0, px * float(d.get("r", 220.0)) / 220.0 * 1.13)
				return
			_lm_up(o, "burst_up", at3, at3.y + 1.0)
			_lm_gd(o, "burst_gd", at3)
			R._light(o, at3 + Vector2(0, -60), 240.0, 0.9, 0.15, p.light)
			R._grains(o, at3 + Vector2(0, -60), at3.y, "ink", 8, {"tier": 2})
		"skill":
			var i: int = int(d.get("i", -1))
			var lp: Vector2 = g.ppos
			if i == 0:   # 沐雨 v3：脚下涟漪弧法阵（贴地）+ 斜细雨 / 十字星 / 精二灯塔光柱（立起）
				items = items.filter(func(it): return not ((str(it.k).begins_with("lm_mend") or str(it.k).begins_with("lm_raw_mend")) and is_equal_approx(float(it.t0), g.t)))
				if raw:
					_lm_raw(o, "raw_drizzle_e%d" % t, lp, 0.0, px * 1.07)
					return
				_lm_gd(o, "drizzle_e%d_gd" % t, lp)
				_lm_up(o, "drizzle_e%d_up" % t, lp, lp.y + 1.0)
				R._light(o, lp + Vector2(0, -20), 150.0, 0.45 + 0.1 * t, 0.15, p.light)
			elif i == 1:   # 沛霖：头顶水柱砸下（精二三道）+ 落点湿痕
				var tt: int = maxi(t, 1)
				if raw:
					_lm_raw(o, "raw_downpour_e%d" % tt, lp, 0.0, px * 1.13)
					return
				_lm_up(o, "downpour_e%d_up" % tt, lp, lp.y + 1.0)
				_lm_gd(o, "downpour_e%d_gd" % tt, lp)
				R._light(o, lp + Vector2(0, -20), 130.0, 0.6, 0.15, p.light)
				R._grains(o, lp + Vector2(0, -24), lp.y, "ink", 3 + 2 * tt, {"tier": tt})
			elif i == 2:   # 灯火不灭起手：头顶四芒灯光 + 水流卷上去；光圈原地亮起
				if raw:
					_lm_raw(o, "raw_lamp", lp, 0.0, px * 1.13)
					return
				_lm_up(o, "s3open_up", lp, lp.y + 1.0)
				_lm_gd(o, "s3open_gd", lp)
				R._light(o, lp + Vector2(0, -96), 160.0, 0.7, 0.15, p.light)


## 同一名干员这一拍（1/15 秒）已出的某类件数（额外弹命中 / 连锁），超过上限就不再加画面
var _beat_cnt := {}

func _lm_beat_n(o, k: String) -> int:
	var key: String = str(o.id) + k
	var beat: int = int(floor(g.t * 15.0))
	var c: Array = _beat_cnt.get(key, [beat, 0])
	if int(c[0]) != beat:
		c = [beat, 0]
	c[1] = int(c[1]) + 1
	_beat_cnt[key] = c
	return int(c[1]) - 1


## 贴地层：一次性件 + 运行时线状贴地件 + 状态件（光雨雨区、灯塔光圈、灯塔守望光扇）
func _lm_draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	for it in items:
		if str(it.ly) != "gd" or str(it.oid) != id:
			continue
		if it.has("rt"):
			_lm_draw_rt(cv, it)
		else:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), it.gp, it.flip, true)
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	if float(lm.get("rain_t", 0.0)) > 0.0:
		_draw_strip(cv, "lm_rain_gd", frame_of(0.0), _snap(g.ppos), false, false)
	var S = _sl()
	if S._h3_tower_on(o):
		_draw_strip(cv, "lm_tower_gd", frame_of(0.0), _snap(lm.tower_pos), false, false)
	var bb: Dictionary = S._h3_beam_block(o)
	if S._h3_beam_on(o, bb):
		_lm_draw_fan(cv, o, lm, bb)


## 立起层的状态件：光弹（运行时）、光雨雨点（循环帧条）、灯塔光尘（循环帧条）
func _lm_sort_items(o, out: Array) -> void:
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	for b in lm.bolts:
		out.append({"rt": "bolt", "b": b, "o": o, "gy": (b.pos as Vector2).y + 30.0})
	if not o.vg.is_empty():   # 后期额外弹：同时最多画最新的 6 颗（更早的照常结算伤害，只是不画；弹数随档位增加，画面不变碎）
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"rt": "xbolt", "b": xb, "o": o, "gy": (xb.p as Vector2).y + 1.0})
	if float(lm.get("rain_t", 0.0)) > 0.0:
		out.append({"loopk": "lm_rain_up", "gp": _snap(g.ppos), "gy": g.ppos.y + 1.0})
	if _sl()._h3_tower_on(o):
		var tp: Vector2 = lm.tower_pos
		out.append({"loopk": "lm_tower_up", "gp": _snap(tp), "gy": tp.y + 1.0})


func _px(ci, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(_snap(p), Vector2(g.PX, g.PX)), c)


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
	g.glow_next.append([_snap(p), g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8))])


## 运行时线状件：line 折光 / link 治疗连线 / beam 灯塔光柱 / streak 光柱地面光痕 / bolt 光弹
func _lm_draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	var C: Array = LM_C
	match str(it.rt):
		"line", "link":
			var f: int = frame_of(float(it.t0))
			var link: bool = str(it.rt) == "link"
			var nb: int = 2 if link else 3
			if f < 0 or f >= nb:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / px))
			for i in n + 1:
				var u: float = float(i) / float(n)
				if f == 2 and u < 0.5:
					continue   # 最后一拍只剩靠落点的一半
				var q: Vector2 = a.lerp(b, u)
				var core: Color = (C[6] if f == 0 else C[5]) if not link else (C[5] if f == 0 else C[4])
				_px(ci, q, core)
				if f == 0 and not link and i % 3 == 0:
					_glow(q, C[6])
		"beam":   # 光柱：第 0 拍满宽白芯 → 往中线收 → 从出光端熄；最远端 15% 收尖
			var f2: int = frame_of(float(it.t0))
			if f2 < 0 or f2 > 3:
				return
			var a2: Vector2 = it.a
			var dv: Vector2 = it.d
			var nv := Vector2(-dv.y, dv.x)
			var L: float = float(it.L)
			var hw: float = float(it.W) / px * 0.5 * [1.0, 0.75, 0.45, 0.25][f2]   # 半宽（美术像素）
			var s: float = L * [0.0, 0.0, 0.25, 0.55][f2]
			var k := 0
			while s <= L:
				var u: float = s / L
				var w: float = hw * (1.0 if u < 0.85 else (1.0 - u) / 0.15)
				var c0: Vector2 = a2 + dv * s
				var m: int = int(round(w))
				for q in range(-m, m + 1):
					var edge: bool = absi(q) == m and m > 0
					var col: Color = C[3] if edge else (C[6] if (f2 <= 1 and absi(q) <= maxi(0, m - 2)) else (C[5] if absi(q) <= 1 else C[4]))
					_px(ci, c0 + nv * float(q) * px, col)
				if f2 <= 1 and k % 3 == 0:
					_glow(c0, C[6])
				s += px
				k += 1
		"streak":   # 光柱在地上的光痕（照亮的地面）：1 美术像素钢蓝线，3 拍里从出光端往外熄
			var f3: int = frame_of(float(it.t0))
			if f3 < 0 or f3 > 2:
				return
			var a3: Vector2 = it.a
			var L3: float = float(it.L)
			var s3: float = L3 * [0.0, 0.3, 0.6][f3]
			while s3 <= L3:
				_px(ci, a3 + (it.d as Vector2) * s3, C[3] if f3 == 0 else C[2])
				s3 += px
		"bolt":   # 光弹（普攻 / 发光单元）
			var b: Dictionary = it.b
			_lm_bolt(ci, b.pos, b.vel, tier(it.o), b.get("big", false), str(b.get("src", "")) == "发光单元")
		"xbolt":   # 后期额外弹（growth/late_shape 等的 vis_growth 弹体）：同一套光弹，小一号（同发光单元）
			var xb: Dictionary = it.b
			_lm_bolt(ci, (xb.p as Vector2) + Vector2(0, -18.0), xb.v, tier(it.o), false, true)
		"cbolt":   # 连携技「清创光弹」：提灯到队长胸口飞 travel 秒，大一号、不分档（尾 18 格 + 两格宽芯 + 灯火橙芯）
			var u: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.life)), 0.0, 1.0)
			var ca: Vector2 = it.a
			var cb: Vector2 = it.b
			_lm_bolt(ci, ca.lerp(cb, u), cb - ca, 2, true, false, true)


## 一颗光弹：雨滴形弹头（白芯 + 冰蓝）+ 钢蓝尾，尾长分档；精一弹头前缘四芒折光星（按拍闪），精二尾更长、尾根一点灯火橙。位置每帧走、取整到美术像素格
func _lm_bolt(ci, pos: Vector2, vel: Vector2, t: int, big: bool, unit: bool, link := false) -> void:
	var px: float = g.PX
	var C: Array = LM_C
	var dv2: Vector2 = vel.normalized()
	var nv2 := Vector2(-dv2.y, dv2.x)
	var head: Vector2 = _snap(pos)
	var tl: int = [9, 12, 16][t] + (4 if big else 0) - (3 if unit else 0) + (2 if link else 0)
	var beat: int = int(floor(g.t * 15.0))
	for i in tl:
		var u: float = float(i) / float(tl)
		var w: int = 1 if i < 3 else 0
		if link and i < tl * 0.6:
			w = 1
		elif t >= 1 and i * 2 < tl and i >= 3:
			w = 1 if (i + beat) % 3 != 0 else 0
		var col: Color = C[6] if i == 0 else (C[5] if i < 3 else (C[4] if u < 0.55 else C[3]))
		var q: Vector2 = head - dv2 * float(i) * px
		_px(ci, q, col)
		for side in range(1, w + 1):
			_px(ci, q + nv2 * px * side, C[4] if i < 3 else C[3])
			_px(ci, q - nv2 * px * side, C[4] if i < 3 else C[3])
	_px(ci, head + dv2 * px, C[5])
	if t >= 2:
		_px(ci, head - dv2 * px * 2.0, LM_AC)
	if t >= 1 and beat % 2 == 0:   # 折光星
		for dd in [1, 2]:
			var cc: Color = C[6] if dd == 1 else C[5]
			_px(ci, head + dv2 * px * float(dd + 1), cc)
			_px(ci, head + nv2 * px * float(dd), cc)
			_px(ci, head - nv2 * px * float(dd), cc)
	_glow(head, C[6])
	_glow(head - dv2 * px, C[5])


## 灯塔守望光扇（贴地，按 15 fps 节拍转）：只画两道边 + 中线，不平涂
func _lm_draw_fan(cv, o, lm: Dictionary, bb: Dictionary) -> void:
	var S = _sl()
	var px: float = g.PX
	var tq: float = floor(g.t * 15.0) / 15.0
	var a: float = tq * TAU / float(bb.get("period", 2.0))
	var dv := Vector2(cos(a), sin(a) * 0.55)
	var org: Vector2 = S._h3_beam_origin(o)
	var L: float = float(bb.get("len", 260.0))
	var twr: bool = S._h3_tower_on(o)
	var fade: float = clampf((float(lm.get("tower_t", 0.0)) if twr else float(lm.get("beam_t", 0.0))) / 0.5, 0.0, 1.0)
	if fade <= 0.05:
		return
	var nv := Vector2(-dv.y, dv.x).normalized()
	var t: int = tier(o)
	var half: float = 13.0 * [1.0, 1.25, 1.5][t]   # 扇口半宽（美术像素），精一 ×1.25、精二 ×1.5
	var s: float = 8.0
	var k := 0
	while s <= L:
		var u: float = s / L
		var w: float = 1.5 + (half - 1.5) * u
		var c0: Vector2 = org + dv * s
		_px(cv, c0, LM_C[5] if u < 0.7 else LM_C[4])
		if t >= 1:
			_px(cv, c0 + nv * px, LM_C[4])
		for sd in [-1.0, 1.0]:
			if (k + int(u * 7.0)) % 5 != 4:   # 边线有缺口，不是两条死线
				_px(cv, c0 + nv * w * px * sd, LM_C[3] if u > 0.3 else LM_C[4])
		if k % 4 == 0:
			_glow(c0, LM_C[5])
		s += px
		k += 1
	if t >= 2:
		_px(cv, org, LM_AC)


## 旧做法（2）：旧放开版帧条整张贴（光晕烤进颜色、小数缩放、旋转），盖在所有单位上
func _lm_draw_raw(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		if str(it.get("rt", "")) == "rawcbolt":
			var cu: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.life)), 0.0, 1.0)
			_draw_raw(cv, "lm_raw_bolt_e2", posmod(int(g.t * rf), maxi(1, int(_meta("lm_raw_bolt_e2").get("n", 1)))), (it.a as Vector2).lerp(it.b, cu), ((it.b as Vector2) - (it.a as Vector2)).angle(), g.PX * 1.6)
			continue
		if str(it.get("rt", "")) == "rawline":
			var kk: float = 1.0 - (g.t - float(it.t0)) / maxf(0.01, float(it.life))
			cv.draw_line(it.a, it.b, Color(0.77, 0.88, 0.95, 0.9 * kk), 2.0)
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	var t: int = tier(o)
	var lf: int = int(g.t * rf)
	for b in lm.bolts:
		var mk: Dictionary = _meta("lm_raw_bolt_e%d" % t)
		_draw_raw(cv, "lm_raw_bolt_e%d" % t, posmod(lf, maxi(1, int(mk.get("n", 1)))), b.pos, (b.vel as Vector2).angle(), g.PX * (1.4 if b.get("big", false) else 1.13))
	if not o.vg.is_empty():
		var mx: Dictionary = _meta("lm_raw_bolt_e%d" % t)
		for xb in o.vg.bul:
			_draw_raw(cv, "lm_raw_bolt_e%d" % t, posmod(lf, maxi(1, int(mx.get("n", 1)))), (xb.p as Vector2) + Vector2(0, -18.0), (xb.v as Vector2).angle(), g.PX * 0.9)
	if float(lm.get("rain_t", 0.0)) > 0.0:
		_draw_raw(cv, "lm_raw_rain", posmod(lf, maxi(1, int(_meta("lm_raw_rain").get("n", 1)))), g.ppos, 0.0, g.PX * 1.07)
	var S = _sl()
	if S._h3_tower_on(o):
		_draw_raw(cv, "lm_raw_tower", posmod(lf, maxi(1, int(_meta("lm_raw_tower").get("n", 1)))), lm.tower_pos, 0.0, g.PX * 1.07)
	var bb: Dictionary = S._h3_beam_block(o)
	if S._h3_beam_on(o, bb):
		var dv: Vector2 = S._h3_beam_dir(o, bb)
		_draw_raw(cv, "lm_raw_sweep", posmod(lf, maxi(1, int(_meta("lm_raw_sweep").get("n", 1)))), S._h3_beam_origin(o), dv.angle(), g.PX * float(bb.get("len", 260.0)) / 260.0 * 1.13)


# ================================================================ 艾雅法拉（docs/259，照斯卡蒂 docs/246 的做法；11-05 用户「火山和熔岩的感觉要做出来，火球也是，参考 pixelfx 的做法」）
## 帧条件（tools/pxplane_bake_eyja.py，键前缀 ey_）：爆团 / 火柱 / 火山爆团 / 喷柱都用 pixelfx 库的粒子做法（火团冷却、火星、余烬、熔岩块），
## 火球 / 熔岩块用库里 fire/fireball（按 5 个平面角生成、另一半翻转、循环），熔岩池 / 熔池只画边 + 淡渐变 + 循环的熔岩泡（立起层）。
## 弹体、熔池、熔蚀裂纹、灼烧火苗直接读玩法状态（g.bullets 里本人的 fire 弹、o.hw 的 lobs / lobvol / erupts / pools / melt_list / burns、o.vg.bul），只读；
## 画面位置按帧走、取整到美术像素格（弹体快，按 15 fps 跳格会一卡一卡，同流明光弹）；帧条形状按 15 fps 节拍换。
## 原画面（MagmaProjectile 的弹体 / 落点 / 材质颗粒、hw_draw_*、o.fx 粒子、连携的岩块 / 冲击）接管时一律不画 / 不生成，玩法照旧。

const EY_C := [Color("#1a0705"), Color("#4a110a"), Color("#8f1d0d"), Color("#d2330f"), Color("#f6561a"), Color("#ff8a3d"), Color("#fff0e0"), Color("#ffaa45")]
const EY_BOOM_R := [26, 34, 44, 56]
const EY_S1_R := [40, 52, 66]
const EY_IG_R := [44, 56]
const EY_S3_R := [38, 46]
const EY_POOL_R := [25, 30]
const EY_LAVA_R := [30, 36]
const EY_SPL_R := [15, 22]
const EY_BURN_MAX := 16
const EY_MELT_MAX := 32

var _sey = null

func _se():
	if _sey == null:
		_sey = load("res://scripts/characters/blocks/seg_eyjafjalla.gd")   # 运行时取（避免和积木链循环 preload）
	return _sey


func _ey_push(o, k: String, at: Vector2, ly: String, extra := {}) -> void:
	var it := {"k": "ey_" + k, "t0": g.t, "gp": _snap(at), "flip": false, "ly": ly, "oid": str(o.id)}
	it.merge(extra, true)
	_push(it)


func _ey_rawi(o, k: String, at: Vector2, rot: float, sc: float) -> void:
	_push({"k": "ey_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


## 同一名干员正在画的某类立起件数（同屏封顶：后期弹多时爆团不叠成一片）
func _ey_cnt(o, pre: String) -> int:
	var n := 0
	for it in items:
		if str(it.oid) == str(o.id) and str(it.ly) == "up" and str(it.k).begins_with(pre):
			n += 1
	return n


func _ev_ey(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG ey %s %s %.3f" % [kind, str(d.get("k", d.get("i", ""))), g.t])
	var px: float = g.PX
	match kind:
		"ey_boom":   # 熔岩弹爆炸：普攻（atk）/ 三重咏唱每落一发（tri）/ 二重咏唱强化弹（s1）/ 点燃弹（s2）
			var at: Vector2 = d.at
			var r: float = float(d.r)
			match str(d.get("k", "atk")):
				"s2":
					var tt: int = maxi(t, 1)
					if raw:
						_ey_rawi(o, "raw_ignite", at, 0.0, px * r * 0.5 / 47.0)
						return
					var b2: int = _bucket(r * 0.5, EY_IG_R)
					_ey_push(o, "ignite_r%d_e%d_up" % [b2, tt], at, "up")
					_ey_push(o, "ignite_r%d_e%d_gd" % [b2, tt], at, "gd")
					if mode() == 1:
						R._grains(o, at + Vector2(0, -50), at.y, "streak", 5 + 3 * tt, {"tier": tt})
					R._light(o, at + Vector2(0, -40), r * 1.8, 0.9, 0.15, p.light)
				"s1":
					if raw:
						_ey_rawi(o, "raw_s1boom", at, 0.0, px * r * 0.5 / 44.0)
						return
					var b1: int = _bucket(r * 0.5, EY_S1_R)
					_ey_push(o, "s1boom_r%d_e%d_up" % [b1, t], at, "up")
					_ey_push(o, "s1boom_r%d_e%d_gd" % [b1, t], at, "gd")
					if mode() == 1:
						R._grains(o, at + Vector2(0, -30), at.y, "ember", 4 + 2 * t, {"tier": t})
					R._light(o, at + Vector2(0, -24), r * 1.6, 0.8, 0.15, p.light)
				_:
					R._light(o, at + Vector2(0, -20), r * 1.3, 0.55, 0.12, p.light)
					if _ey_cnt(o, "ey_boom") >= 6:
						return
					if raw:
						_ey_rawi(o, "raw_boom_e%d" % t, at, 0.0, px * r * 0.5 / 30.0)
						return
					var b0: int = _bucket(r * 0.5, EY_BOOM_R)
					_ey_push(o, "boom_r%d_e%d_up" % [b0, t], at, "up")
					_ey_push(o, "boom_r%d_e%d_gd" % [b0, t], at, "gd")
					if mode() == 1:
						R._grains(o, at + Vector2(0, -20), at.y, "ember", 2 + t, {"tier": t})
		"ey_splash", "ey_xhit":   # 抛射熔岩落地（火星迸溅 / 星火燎原 / 熔岩天降）、后期额外弹命中：小一号
			var at2: Vector2 = d.at
			var r2: float = float(d.get("r", 30.0))
			if kind == "ey_xhit" and _lm_beat_n(o, "eyx") >= 3:
				return
			if _ey_cnt(o, "ey_splash") >= 5:
				return
			if raw:
				_ey_rawi(o, "raw_splash", at2, 0.0, px * r2 * 0.5 / 18.0)
				return
			var bs: int = _bucket(r2 * 0.5, EY_SPL_R)
			_ey_push(o, "splash_r%d_up" % bs, at2, "up")
			if kind == "ey_splash":
				_ey_push(o, "splash_r%d_gd" % bs, at2, "gd")
				if mode() == 1:
					R._grains(o, at2 + Vector2(0, -10), at2.y, "rock", 2, {"tier": t})
			R._light(o, at2 + Vector2(0, -10), r2 * 1.6, 0.4, 0.1, p.light)
		"ey_s3":   # 火山落点：实心大爆团（火团 + 往上冲的火 + 熔岩块 + 花瓣状暗红碎片 + 火星线）
			var at3: Vector2 = d.at
			var r3: float = float(d.r)
			R._light(o, at3 + Vector2(0, -30), r3 * 2.2, 1.0, 0.15, p.light)
			if raw:
				_ey_rawi(o, "raw_s3boom", at3, 0.0, px * r3 * 0.5 / 38.0)
				return
			var b3: int = _bucket(r3 * 0.5, EY_S3_R)
			_ey_push(o, "s3boom_r%d_up" % b3, at3, "up")
			_ey_push(o, "s3boom_r%d_gd" % b3, at3, "gd")
			if mode() == 1:
				R._grains(o, at3 + Vector2(0, -40), at3.y, "streak", 6, {"tier": 2})
				R._grains(o, at3 + Vector2(0, -20), at3.y, "rock", 3, {"tier": 2})
		"ey_fire":   # 出手：杖头两拍火光
			if raw:
				return
			_push({"ert": "muz", "at": _snap(d.at), "big": d.get("big", false), "t0": g.t, "life": 2.0 / 15.0, "ly": "up", "gy": o.pos.y + 1.0, "oid": str(o.id), "k": ""})
			R._light(o, d.at, 60.0, 0.35, 0.08, p.light)
		"ey_chain":   # 「连锁」弹射：一道 1 美术像素的火线（3 拍）
			if _lm_beat_n(o, "eych") >= 3 or raw:
				return
			_push({"ert": "chain", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
		"ey_link":   # 连携 v2「熔岩」：杖头抛出一块大熔岩块（库里火球 + 岩壳），T 秒高抛砸进区域；地上影子跟着
			var la: Vector2 = d.a
			var lc: Vector2 = d.c
			var T: float = float(d.T)
			_push({"ert": "lrock", "a": la, "c": lc, "T": T, "t0": g.t, "life": T, "ly": "up", "gy": lc.y + 2.0, "oid": str(o.id), "k": "", "raw": raw})
			_push({"ert": "lshadow", "a": Vector2(la.x, (d.get("foot", la) as Vector2).y), "c": lc, "T": T, "t0": g.t, "life": T, "ly": "gd", "oid": str(o.id), "k": ""})
			R._light(o, la, 120.0, 0.5, 0.12, p.light)
		"ey_link_hit", "ey_combo":   # 连携熔岩块砸地 / 旧连携技「放大熔岩弹」落点：火山爆团 + 一摊熔岩（只画边 + 熔岩泡）
			var c: Vector2 = d.get("c", d.get("at", o.pos))
			var lr: float = float(d.get("r", 105.0))
			var dur: float = 2.0 if kind == "ey_combo" else 0.9
			R._light(o, c + Vector2(0, -30), maxf(240.0, lr * 2.0), 1.0, 0.15, p.light)
			if raw:
				_ey_rawi(o, "raw_s3boom", c, 0.0, px * lr * 0.5 / 38.0)
				return
			_ey_push(o, "s3boom_r46_up", c, "up")
			_ey_push(o, "s3boom_r46_gd", c, "gd")
			_ey_push(o, "lava_r36_gd", c, "gd", {"loop": true, "life": dur})
			_ey_push(o, "lavaup_l36_up", c, "up", {"loop": true, "life": dur})
			if mode() == 1:
				R._grains(o, c + Vector2(0, -40), c.y, "streak", 10, {"tier": 2})
				R._grains(o, c + Vector2(0, -20), c.y, "rock", 6, {"tier": 2})
		"ey_link_burn":   # 连携两跳点燃：被烧的那几只身上冒火星
			if mode() != 1:
				return
			var n := 0
			for e in d.get("es", []):
				if e.dead or n >= 6:
					continue
				n += 1
				R._grains(o, e.pos + Vector2(0, -float(e.r) * 0.6), float(e.pos.y), "ember", 2, {"tier": 1})
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 0:   # 二重咏唱起手：火缕绕身旋上杖头
				if raw:
					_ey_rawi(o, "raw_s1cast", o.pos, 0.0, px * 1.13)
					return
				_ey_push(o, "s1cast_e%d_up" % t, o.pos, "up")
				if t >= 2:
					_ey_push(o, "s1cast_e2_gd", o.pos, "gd")
				R._light(o, o.pos + Vector2(0, -100), 100.0, 0.5, 0.15, p.light)
			elif i == 2:   # 火山起手：身后熔岩喷柱 + 脚下裂缝圈
				var fl: bool = float(o.face) < 0.0
				if raw:
					_ey_rawi(o, "raw_s3cast", o.pos, 0.0, px * 1.13)
					return
				_ey_push(o, "s3cast_up", o.pos, "up", {"flip": fl, "sk": -6.0})
				_ey_push(o, "s3cast_gd", o.pos, "gd", {"flip": fl})
				R._light(o, o.pos + Vector2(0, -60), 170.0, 0.7, 0.15, p.light)
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -40), o.pos.y, "rock", 5, {"tier": 2})


## 地面层：一次性贴地件、循环熔岩（连携 / 旧连携技）、熔岩池 / 熔池（读 o.hw.pools）、熔蚀裂纹、抛射物影子、火山期间脚下热圈
func _ey_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var px: float = g.PX
	if not o.hw.is_empty() and o.hw.has("pulse") and not (o.hw.pulse as Dictionary).is_empty():
		_draw_strip(cv, "ey_aura_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for l in o.hw.get("pools", []):
		var key: String = _ey_pool_key(l, "gd")
		if key == "":
			continue
		_draw_strip(cv, key, frame_of(0.0) + int(l.get("pat", 0)) % 7, _snap(l.pos), false, false, Color(1, 1, 1, _ey_pool_a(l)))
	for it in items:
		if str(it.ly) != "gd" or str(it.oid) != id:
			continue
		if it.has("ert"):
			_ey_draw_rt(cv, it)
		elif it.get("loop", false):
			_draw_strip(cv, str(it.k), frame_of(0.0), it.gp, false, false, Color(1, 1, 1, _ey_loop_a(it)))
		else:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), it.gp, it.flip, true)
	# 熔蚀（精一普攻）：被熔岩弹命中的敌人脚下三小段暗红裂纹（状态提示）
	var nm := 0
	for m in o.hw.get("melt_list", []):
		var e: Dictionary = m.e
		var left: float = float(m.until) - g.t
		if e.dead or left <= 0.0 or nm >= EY_MELT_MAX:
			continue
		nm += 1
		var base: Vector2 = _snap(e.pos + Vector2(0, 2))
		var rr: float = clampf(float(e.r) * 0.5, 5.0, 12.0)
		for q in 3:
			var a0: float = q * TAU / 3.0 + float(e.id) * 0.7
			for s in 5:
				if left < 0.3 and s >= 2:
					continue
				var an: float = a0 + s * 0.13
				_px(cv, base + Vector2(cos(an) * rr, sin(an) * rr * 0.72) * px, EY_C[3] if (s + q) % 2 == 0 else EY_C[2])
	# 抛射物（熔岩块 / 三重咏唱低抛弹）的地面影子：暗色小椭圆，越高越小
	for l in o.hw.get("lobs", []):
		var k: float = clampf(float(l.t) / maxf(0.01, float(l.dur)), 0.0, 1.0)
		_ey_shadow(cv, (l.from as Vector2).lerp(l.to, k) + Vector2(0, (1.0 - k) * 6.0), 2.0 + 2.0 * float(l.sz), k)
	for v in o.hw.get("lobvol", []):
		for s in v.shots:
			if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
				continue
			var k2: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
			_ey_shadow(cv, (s.from as Vector2).lerp(s.to, k2) + Vector2(0, (1.0 - k2) * 40.0), 3.0, k2)


func _ey_shadow(cv, gp: Vector2, r: float, k: float) -> void:
	var px: float = g.PX
	var c := Color(0.05, 0.02, 0.02, 0.45)
	var rr: int = int(round(r * (0.6 + 0.4 * k)))
	var base: Vector2 = _snap(gp)
	for y in range(-1, 2):
		for x in range(-rr, rr + 1):
			if absi(y) == 1 and absi(x) >= rr:
				continue
			cv.draw_rect(Rect2(base + Vector2(x, y) * px, Vector2(px, px)), c)


## 熔岩池 / 熔池帧条键：S3 熔岩（look lava）或三重咏唱熔池（look pool / weighted）
func _ey_pool_key(l: Dictionary, ly: String) -> String:
	var b: Dictionary = l.b
	var look: String = str(b.get("look", ""))
	if look == "lava":
		return ("ey_lava_r%d_gd" if ly == "gd" else "ey_lavaup_l%d_up") % _bucket(float(l.r) * 0.5, EY_LAVA_R)
	if look == "pool" or b.get("weighted", false):
		return ("ey_pool_r%d_gd" if ly == "gd" else "ey_lavaup_p%d_up") % _bucket(float(l.r) * 0.5, EY_POOL_R)
	return ""


func _ey_pool_a(l: Dictionary) -> float:
	return clampf((float(l.dur) - float(l.t)) / 0.15, 0.0, 1.0) * clampf(float(l.t) / 0.3, 0.0, 1.0)


func _ey_loop_a(it: Dictionary) -> float:
	return clampf((g.t - float(it.t0)) / 0.12, 0.0, 1.0) * clampf((float(it.t0) + float(it.life) - g.t) / 0.3, 0.0, 1.0)


## 立起层的状态件：弹体（火球 / 熔岩块）、熔岩泡（循环）、灼烧火苗
func _ey_sort_items(o, out: Array) -> void:
	var S = _se()
	var oid: String = str(o.id)
	for bl in g.bullets:   # 本人的法术弹（普攻 / 二重咏唱强化 / 点燃弹）
		if bl.life <= 0.0 or str(bl.get("op", "")) != oid or str(bl.kind) != "fire" or not bl.has("hw_b"):
			continue
		var lk: Dictionary = bl.hw_b.get("look", {})
		var st: String = "ign" if lk.has("big_tex") else ("pow" if bl.get("pxs", false) else ("fire" if bl.get("hw_fireball", false) else "lava"))
		out.append({"ert": "ball", "st": st, "pos": bl.pos, "dir": bl.vel, "gy": (bl.pos as Vector2).y + 40.0, "ph": int(absf(bl.pos.x)) % 7})
	if not o.hw.is_empty():
		for l in o.hw.get("lobs", []):   # 火星迸溅 / 星火燎原 / 熔岩天降的熔岩块
			if float(l.t) >= float(l.dur):
				continue
			var lp: Vector2 = S._hw_lob_pos(l)
			var lp0: Vector2 = S._hw_lob_pos_at(l, maxf(0.0, float(l.t) - 0.03))
			var k: float = clampf(float(l.t) / maxf(0.01, float(l.dur)), 0.0, 1.0)
			var big: bool = float(l.sz) >= 1.1 or str(l.src) == "熔岩天降"
			out.append({"ert": "ball", "st": "rock" if big else "chip", "pos": lp, "dir": lp - lp0 if lp.distance_squared_to(lp0) > 0.01 else Vector2.DOWN, "gy": (l.from as Vector2).lerp(l.to, k).y + 2.0, "ph": int(absf(l.to.x)) % 7})
		for v in o.hw.get("lobvol", []):   # 三重咏唱低抛弹
			var apex: float = float(v.vol.b.lob.get("apex", 20.0))
			for s in v.shots:
				if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
					continue
				var k2: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
				var sp: Vector2 = _ey_arc(s.from, s.to, k2, apex) + Vector2(0, -8)
				var sp0: Vector2 = _ey_arc(s.from, s.to, maxf(0.0, k2 - 0.05), apex) + Vector2(0, -8)
				out.append({"ert": "ball", "st": "lava", "pos": sp, "dir": sp - sp0 if sp.distance_squared_to(sp0) > 0.01 else Vector2.RIGHT, "gy": (s.from as Vector2).lerp(s.to, k2).y + 30.0, "ph": int(absf(s.to.x)) % 7})
		for ev in o.hw.get("erupts", []):   # 火山弹
			if not ev.has("shot") or float(ev.t) <= 0.0:
				continue
			var shot: Dictionary = ev.shot
			var k3: float = clampf(1.0 - float(ev.t) / float(shot.dur), 0.0, 1.0)
			var ap: float = float(shot.get("apex", 24.0))
			var ep: Vector2 = _ey_arc(shot.from, ev.pos, k3, ap)
			var ep0: Vector2 = _ey_arc(shot.from, ev.pos, maxf(0.0, k3 - 0.05), ap)
			out.append({"ert": "ball", "st": "rock", "pos": ep, "dir": ep - ep0 if ep.distance_squared_to(ep0) > 0.01 else Vector2.DOWN, "gy": (shot.from as Vector2).lerp(ev.pos, k3).y + 54.0 * (1.0 - k3), "ph": int(absf(ev.pos.x)) % 7})
		for l in o.hw.get("pools", []):   # 熔岩泡（循环，立起）
			var key: String = _ey_pool_key(l, "up")
			if key != "":
				out.append({"loopk": key, "gp": _snap(l.pos), "gy": (l.pos as Vector2).y + 1.0, "mod": Color(1, 1, 1, _ey_pool_a(l))})
		var nb := 0
		for bu in o.hw.get("burns", []):   # 灼烧：敌人身上两小簇火苗（状态提示）
			if nb >= EY_BURN_MAX:
				break
			if float(bu.t) <= 0.0 or bu.e.dead:
				continue
			nb += 1
			out.append({"ert": "burn", "e": bu.e, "gy": float(bu.e.pos.y) + 1.0})
	if not o.vg.is_empty():   # 后期额外弹：小熔岩块，同时最多画最新 6 颗
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"ert": "ball", "st": "chip", "pos": (xb.p as Vector2) + Vector2(0, -18.0), "dir": xb.v, "gy": (xb.p as Vector2).y + 1.0, "ph": i % 7})


## MagmaProjectile.position_at 的同一条弧（纯函数抄一份，只读）
static func _ey_arc(from: Vector2, to: Vector2, k: float, height: float) -> Vector2:
	return from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k) * (1.18 - 0.36 * k))


## 运行时件：ball 弹体（帧条按方向挑）/ muz 出手火光 / chain 连锁火线 / lrock 连携熔岩块 / lshadow 它的影子 / burn 灼烧火苗
func _ey_draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	match str(it.ert):
		"ball":
			_ey_ball(ci, str(it.st), it.pos, it.dir, int(it.get("ph", 0)))
		"muz":
			var f: int = frame_of(float(it.t0))
			if f < 0 or f > 1:
				return
			var c0: Vector2 = it.at
			var m: int = 3 if it.get("big", false) else 2
			_px(ci, c0, EY_C[6] if f == 0 else EY_C[7])
			for dv in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				for s in range(1, m + (1 if f == 0 else 0)):
					_px(ci, c0 + dv * float(s) * px, EY_C[7] if s == 1 else EY_C[5])
			if f == 0:
				_glow(c0, EY_C[7])
		"chain":
			var f2: int = frame_of(float(it.t0))
			if f2 < 0 or f2 > 2:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / px))
			for i in n + 1:
				var u: float = float(i) / float(n)
				if f2 == 2 and u < 0.5:
					continue
				_px(ci, a.lerp(b, u), EY_C[7] if f2 == 0 else EY_C[5])
				if f2 == 0 and i % 3 == 0:
					_glow(a.lerp(b, u), EY_C[7])
		"lrock":
			var u2: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.T)), 0.0, 1.0)
			var pos: Vector2 = _ey_lrock_pos(it, u2)
			var pos0: Vector2 = _ey_lrock_pos(it, maxf(0.0, u2 - 0.05))
			if it.get("raw", false):
				_draw_raw(ci, "ey_ball_boulder_d0", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), 18), pos, (pos - pos0).angle(), g.PX * 1.3)
			else:
				_ey_ball(ci, "boulder", pos, pos - pos0 if pos.distance_squared_to(pos0) > 0.01 else Vector2.DOWN, 0)
		"lshadow":
			var u3: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.T)), 0.0, 1.0)
			_ey_shadow(ci, (it.a as Vector2).lerp(it.c, u3) + Vector2(0, 10), 6.0 + 8.0 * u3, u3)
		"burn":
			var e: Dictionary = it.e
			if e.dead:
				return
			var beat: int = int(floor(g.t * 15.0))
			var base: Vector2 = _snap(e.pos + Vector2(0, -float(e.r) * 0.55))
			var off: int = maxi(2, int(float(e.r) * 0.15))
			for j in 2:
				var x: int = -off if j == 0 else off
				var h: int = 2 + int(_hn(int(e.id) * 3 + j + beat) * 3.0)
				for s in h:
					_px(ci, base + Vector2(x, -s) * px, EY_C[5] if s == 0 else (EY_C[4] if s < h - 1 else EY_C[3]))
				if j == 0:
					_glow(base + Vector2(x, 0) * px, EY_C[5])


static func _hn(i: int) -> float:
	var x: int = (i * 1103515245 + 12345) & 0x7fffffff
	return float(x % 1000) / 1000.0


func _ey_lrock_pos(it: Dictionary, u: float) -> Vector2:
	var gp: Vector2 = (it.a as Vector2).lerp(it.c, u)
	return gp + Vector2(0, -140.0 * sin(PI * u))


## 一颗弹体：帧条 ey_ball_<样式>_d<方向>（按飞行方向挑最近的平面角 + 水平翻转），循环；原点 = 弹头，位置每帧走、取整到美术像素格
func _ey_ball(ci, st: String, pos: Vector2, dir: Vector2, ph: int) -> void:
	var dk: Array = pick_dir(dir.angle() if dir.length_squared() > 0.0001 else 0.0)
	_draw_strip(ci, "ey_ball_%s_d%d" % [st, dk[0]], frame_of(0.0) + ph, _snap(pos), dk[1], false)


## 旧做法（2）：同一形状光晕烤进颜色、小数缩放、旋转，盖在所有单位上；弹体用 0° 帧条按飞行方向旋转 1.3 倍贴
func _ey_draw_raw(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	var lf: int = int(g.t * rf)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
	for l in o.hw.get("pools", []):
		if _ey_pool_key(l, "gd") != "":
			_draw_raw(cv, "ey_raw_lava", posmod(lf, 18), l.pos, 0.0, g.PX * float(l.r) * 0.5 / 30.0)
	var tmp: Array = []
	_ey_sort_items(o, tmp)
	for it in tmp:
		if str(it.get("ert", "")) == "ball":
			_draw_raw(cv, "ey_ball_%s_d0" % str(it.st), posmod(lf, 18), it.pos, (it.dir as Vector2).angle(), g.PX * 1.3)
		elif str(it.get("ert", "")) == "burn":
			_ey_draw_rt(cv, it)
	for it in items:
		if str(it.oid) == id and str(it.get("ert", "")) == "lrock" and it.get("raw", false):
			_ey_draw_rt(cv, it)
