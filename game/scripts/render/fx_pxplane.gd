## pixelfx「转平面」试验（docs/246，11-05 用户「把 pixelfx 的二维平面转移到我们这个平面上来，再结合 Noita 特效」）：斯卡蒂（docs/246）、星熊（docs/254）、流明（docs/255）、浊心斯卡蒂（docs/260），各自一节在文件后部。
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
const METAS := {"res://data/pxp_skadi.json": "", "res://data/pxp_hoshiguma.json": "", "res://data/pxp_lumen.json": "lm_", "res://data/pxp_skalter.json": "sk_"}   # 帧条表 → 键前缀（星熊表内键已带 hsg_；流明 / 浊心斯卡蒂帧条 art/fx/pxp/pxp_lm_ / pxp_sk_<键>.png）
const ART := "res://art/fx/pxp/pxp_%s.png"
const IDS := {"skadi": true, "hoshiguma": true, "lumen": true, "skalter": true}
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
	if str(o.id) == "skalter":
		_ev_skalter(o, kind, d, raw, t, R, p)
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
				_add_up(o, "s3cast", o.pos + Vector2(0, 2), raw, "raw_splash_e2", 185.0, 75.0, 0.0, true)
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
		_push({"cut": true, "e": e, "t0": g.t, "gp": e.pos + Vector2(0, -float(e.r) * 0.55), "gy": float(e.pos.y) + 1.0, "d": tg, "x": t >= 2, "L": 9.0 + 2.0 * t + minf(6.0, float(e.r) * 0.25), "ly": "up", "oid": str(o.id), "k": ""})


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
	_push({"k": ku, "t0": g.t, "gp": _snap(at), "flip": dk[1] and not spin, "ly": "up", "oid": str(o.id), "slash": true, "fo": at - o.pos})
	_push({"k": kg, "t0": g.t, "gp": _snap(at), "flip": dk[1] and not spin, "ly": "gd", "oid": str(o.id), "slash": true, "fo": at - o.pos})


## 以脚底为原点的一对件（立起 + 贴地）
func _add_pair(o, key: String, at: Vector2, follow := false) -> void:
	var a := {"k": key + "_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	var b := {"k": key + "_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	if follow:
		a["fo"] = at - o.pos
		b["fo"] = at - o.pos
	_push(a)
	_push(b)


## 方向件（不是斩击：不参与「只留最近两刀」）
func _add_dir(o, key: String, at: Vector2, ang: float) -> void:
	var dk: Array = pick_dir(ang)
	_push({"k": "%s_up_d%d" % [key, dk[0]], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "up", "oid": str(o.id)})
	_push({"k": "%s_gd_d%d" % [key, dk[0]], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "gd", "oid": str(o.id)})


func _add_up(o, key: String, at: Vector2, raw: bool, rawk: String, r: float, fit: float, ang: float, follow := false) -> void:
	if raw:
		_push({"k": rawk, "t0": g.t, "gp": at + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	var it := {"k": key + "_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	if follow:
		it["fo"] = at - o.pos
	_push(it)


func _add_gd(o, key: String, at: Vector2, raw: bool, rawk: String, r: float, fit: float) -> void:
	if raw:
		if rawk != "":
			_push({"k": rawk, "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	_push({"k": key + "_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})


## 件的当前地面点（docs/246 §10，11-05 用户「斩击没有绑定人，会在别的地方出现」）：
## 挂在人身上的件（fo = 出手时相对施放者脚底的偏移）每次绘制按施放者当前位置重算，朝向保持出手时的方向；
## 斩痕（e）跟着被砍的那只；其余（落地类：冲击环、碎浪、碎沫、积水、湿痕）留在出手时的世界坐标
func _gp(it: Dictionary) -> Vector2:
	if it.has("fo"):
		var op = _op(str(it.oid))
		if op != null and op.pos != Vector2.INF:
			return _snap(op.pos + (it.fo as Vector2))
	elif it.has("e"):
		var e: Dictionary = it.e
		if not e.get("dead", false):
			return e.pos + Vector2(0, -float(e.r) * 0.55)
	return it.gp


func _op(oid: String):
	for o in g.squad.ops:
		if str(o.id) == oid:
			return o
	return null


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
	if id == "skalter":
		_sk_draw_floor(o)
		return
	if o.skill_active_left(2) > 0.0:   # 涌潮悲歌持续期间：脚下一滩积水（循环，跟着人走）
		_draw_strip(cv, "pool_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)
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
	if id == "skalter":
		_sk_draw_raw(o)
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
			if it.has("fo") or it.has("e"):   # 跟人 / 跟怪的件按当前位置排序（键名 _skn：星熊的 sk 是排序偏移，别撞）
				var gp: Vector2 = r._gp(it)
				it["_skn"] = gp.y + ((float(it.e.r) * 0.55 + 1.0) if it.has("e") else 1.0 + float(it.get("sk", 0.0)))
			out.append(it)
	for o in game.squad.ops:
		if IDS.has(str(o.id)) and o.pos != Vector2.INF:
			if str(o.id) == "lumen":
				r._lm_sort_items(o, out)
				continue
			if str(o.id) == "skalter":
				r._sk_sort_items(o, out)
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
	if it.has("skr"):   # 浊心斯卡蒂（docs/260）：运行时立起件
		r._sk_draw_up(ci, it)
		return
	if it.has("skr_s"):
		r._sk_draw_state_up(ci, it)
		return
	if it.has("wave"):
		var w: Array = it.wave
		r._draw_strip(ci, w[0] + "_up_d%d" % w[3], r.frame_of(0.0), w[1], w[2], false)
		return
	if it.get("cut", false):
		r._draw_cut(ci, it)
		return
	if it.has("rt"):
		r._lm_draw_rt(ci, it)
		return
	if it.has("loopk"):
		r._draw_strip(ci, str(it.loopk), r.frame_of(0.0), it.gp, false, false)
		return
	if it.has("fi"):   # 星熊剑气：帧号按剑气年龄 / 剩余寿命挑
		r._draw_strip(ci, str(it.k), int(it.fi), r._gp(it), it.flip, true)
		return
	r._draw_strip(ci, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, not it.get("loop", false))


## 斩痕：沿方向逐美术像素画（2 世界像素格），第 0 拍白芯 + 两侧浅蓝、第 1 拍浅蓝变短、第 2 拍只剩两头几点
func _draw_cut(ci, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	if f < 0 or f > 2:
		return
	var px: float = g.PX
	var c0: Vector2 = _snap(_gp(it))
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
	if it.has("_skn"):   # 跟人 / 跟怪的件（docs/246 §10）按当前位置排
		return float(it._skn)
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


# ================================================================ 浊心斯卡蒂（docs/260，照 docs/246 斯卡蒂的做法）
## 她是召唤 + 控场的歌手，特效全是「圈」：判定半径随技能 / 精英化 / 成长连续变化，烤成帧条只能按整数倍放大对不上半径，
## 所以主形全部运行时画：笔触弧 = 三角形带（顶点对齐 2 世界像素格，进低分辨率层后正好 1 美术像素一格，硬边、无抗锯齿），
## 形状按 15 fps 全局节拍换（旋转角、扩散半径都按拍取值）。贴地件按 combat.GROUND_Y（0.72）压扁；音符、气泡、红光柱、小鱼是立起件，按脚底 y 和单位一起排序。
## 色层吃场景光（画在世界层），白热 / 红光柱芯出 emit 点进发光层，爆发与命中挂照地点光（fx_recipe 灯光预算）；颗粒只用 twinkle / drop 少量。
## 招式：普攻声浪 = 一圈断口笔触浪从 0.6 扩到判定边 + 命中处音符（E1 加厚 + 第二道浪 + 余音外环；E2 浪里夹一道酒红暗流 + 双音符）；
## 歌域（常驻地面区域）= 边上 3–5 段粗笔触 + 贴边淡渐变 + 内侧 2–4 道反向细笔触线；S1 = 身周气泡（E1 双层膜、E2 三团）+ 脚下酒红细环；
## S2 = 起手脚下旋涡 + 酒红小鱼（之后小鱼常驻绕歌域游，E1 3 条 / E2 5 条；E2 涡眼冲起一道水柱）；
## S3 = 起手与之后每 3 秒一次「潮涌」：粗笔触亮蓝环（深蓝内影）扩到歌域边 + 内部实心渐变（不透明度 0.5 → 0.35）+ 8 道旋转笔触线 + 5 根粗亮红竖光柱；持续期间歌域加粗加快。
## 伊莎玛拉（精二海嗣）的小歌域 = 酒红细笔触；连携 v2「歌声」= 区域笔触圈 + 酒红内圈 3 秒 + 音符；旧连携声浪 = 大一号声浪。
## 成长 / 后期：共鸣小声浪、潮汐和声回声（酒红细浪）、深海的回响爆点、late_shape「扩散」溅射环（同屏每拍至多 3 个）。

const SK_SY := 0.72
const SK_B := [Color("#070d22"), Color("#0e1d4a"), Color("#183486"), Color("#2752c4"), Color("#4f80ec"), Color("#9dbcff"), Color("#ffffff")]   # 深海蓝 7 阶（原作歌域蓝，避开敌弹青 #33ceff）
const SK_R := [Color("#3a0d1b"), Color("#5e1424"), Color("#86202d"), Color("#a8323c"), Color("#dc4048"), Color("#ffb4bc"), Color("#ffffff")]   # 酒红（house.js OP.skalter，亮段色相 357°，避开危险红 331–353°）
const SK_T := [Color("#06141c"), Color("#0b2a35"), Color("#124552"), Color("#1b6466"), Color("#3b8e89"), Color("#86c6bd"), Color("#e8f5f0")]   # 海嗣青（house.js OP.skalter_sea，原作海嗣色，偏灰、避开敌弹青）：伊莎玛拉小歌域与同步声浪
const SK_NOTE := ["....####", "....#..#", "....#..#", "....#...", "....#...", "....#...", ".####...", "#####...", "#####...", ".###...."]
const SK_NOTE2 := ["...########", "...#......#", "...#......#", "...#......#", "...#......#", ".###....###", "####...####", "####...####", ".##.....##."]
const SK_FISH := ["#...####..", "##.######.", ".#########", "##.######.", "#...####.."]
var _sk_st := {}          # 干员 id → 画面状态（缓动半径、潮涌下次时刻、上一拍去重），玩法不读


func _sk_beat() -> int:
	return int(floor(g.t * 15.0))


func _sk_h(i: int, s: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + s * 78.233) * 43758.5453, 1.0)


func _sk_state(o) -> Dictionary:
	var id: String = str(o.id)
	if not _sk_st.has(id):
		_sk_st[id] = {"r": {}, "s3_next": -1.0, "s3_on": false, "dd": {}}
	return _sk_st[id]


## 画面半径：向判定半径缓动（约 0.4 秒到位），按美术像素取整；判定半径立即生效
func _sk_r(o, key: String, zr: float) -> float:
	var st: Dictionary = _sk_state(o)
	var e: Array = st.r.get(key, [zr, g.t])
	var dt: float = clampf(g.t - float(e[1]), 0.0, 0.1)
	var v: float = lerpf(float(e[0]), zr, 1.0 - exp(-dt * 7.0))
	st.r[key] = [v, g.t]
	return round(v / g.PX) * g.PX


## 椭圆上一点（贴地：纵向 × GROUND_Y）
func _sk_ep(c: Vector2, rr: float, a: float) -> Vector2:
	return c + Vector2(cos(a) * rr, sin(a) * rr * SK_SY)


## 一笔贴地笔触弧：c 圆心（世界）、R 半径（世界）、a0 → a1 弧度、w 宽（美术像素）、taper 两头收尖、seed 粗细起伏；
## 主色一条带 + 外缘 1 美术像素迎光边（中段）+ 内缘 1 美术像素暗边；顶点对齐 2 世界像素格
func _sk_arc(cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	if R <= 2.0 or w <= 0.0 or col.a <= 0.003:
		return
	var px: float = g.PX
	var span: float = a1 - a0
	var n: int = clampi(int(absf(span) * R / (px * 3.0)), 3, 72)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var ths: Array = []
	for i in n + 1:
		var u: float = float(i) / float(n)
		var a: float = a0 + span * u
		var th: float = w * px * (pow(maxf(0.0, sin(PI * u)), 0.55) if taper else 1.0) * (0.82 + 0.36 * _sk_h(i / 3, seed))
		th = maxf(th, px * 0.5) if taper else th
		ths.append(th)
		outer.append(_snap(_sk_ep(c, R + th * 0.5, a)))
		inner.append(_snap(_sk_ep(c, R - th * 0.5, a)))
	_sk_band(cv, outer, inner, col)
	if w >= 2.0 and hi.a > 0.003:   # 迎光边：外缘中段 1 美术像素
		var o2 := PackedVector2Array()
		var i2 := PackedVector2Array()
		var lo_i: int = n / 5
		var hi_i: int = n - n / 5
		for i in range(lo_i, hi_i + 1):
			var a: float = a0 + span * float(i) / float(n)
			var th: float = float(ths[i])
			o2.append(_snap(_sk_ep(c, R + th * 0.5, a)))
			i2.append(_snap(_sk_ep(c, R + th * 0.5 - px, a)))
		_sk_band(cv, o2, i2, hi)
	if w >= 3.0 and lo.a > 0.003:   # 内缘暗边
		var o3 := PackedVector2Array()
		var i3 := PackedVector2Array()
		for i in n + 1:
			var a: float = a0 + span * float(i) / float(n)
			var th: float = float(ths[i])
			o3.append(_snap(_sk_ep(c, R - th * 0.5 + px, a)))
			i3.append(_snap(_sk_ep(c, R - th * 0.5, a)))
		_sk_band(cv, o3, i3, lo)


func _sk_band(cv, outer: PackedVector2Array, inner: PackedVector2Array, col: Color) -> void:
	var m: int = mini(outer.size(), inner.size())
	if m < 2:
		return
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in m:
		pts.append(outer[i])
		pts.append(inner[i])
	for i in m - 1:
		var k: int = i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	cv.add_tris(pts, cols, idx)


## 贴边淡渐变 / 实心渐变：r0 → r1 两圈之间，透明度 a0（内）→ a1（外）
func _sk_grad(cv, c: Vector2, r0: float, r1: float, col: Color, a0: float, a1: float) -> void:
	if r1 <= 2.0 or (a0 <= 0.003 and a1 <= 0.003):
		return
	var n: int = clampi(int(r1 / 6.0), 20, 64)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var ci := Color(col.r, col.g, col.b, a0)
	var co := Color(col.r, col.g, col.b, a1)
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(_snap(_sk_ep(c, r1, a)))
		cols.append(co)
		pts.append(_snap(_sk_ep(c, maxf(0.0, r0), a)))
		cols.append(ci)
	for i in n:
		var k: int = i * 2
		var k2: int = ((i + 1) % n) * 2
		idx.append_array([k, k + 1, k2, k + 1, k2 + 1, k2])
	cv.add_tris(pts, cols, idx)


## 逐美术像素的小图案（立起件：音符、小鱼）；左上角 tl（世界），fl 水平翻转
func _sk_pat(ci, pat: Array, tl: Vector2, col: Color, head: Color, fl := false, sh := Color(0, 0, 0, 0)) -> void:
	var px: float = g.PX
	var p0: Vector2 = _snap(tl)
	var hh: int = pat.size()
	if sh.a > 0.0:   # 1 美术像素暗描边（右下投影）：压在白色敌人 / 伤害数字上也读得出
		for y in hh:
			var row0: String = pat[y]
			var w0: int = row0.length()
			for x in w0:
				if row0[x] == "#":
					var x0: int = (w0 - 1 - x) if fl else x
					ci.draw_rect(Rect2(p0 + Vector2(x0 + 1, y + 1) * px, Vector2(px, px)), sh)
	for y in hh:
		var row: String = pat[y]
		var ww: int = row.length()
		for x in ww:
			if row[x] != "#":
				continue
			var xx: int = (ww - 1 - x) if fl else x
			ci.draw_rect(Rect2(p0 + Vector2(xx, y) * px, Vector2(px, px)), head if y >= hh - 2 else col)


## 一圈断口笔触浪（普攻声浪 / 回声 / 海嗣同步 / 小声浪）：k 断成几段，w 宽，rot 起始角
func _sk_ring(cv, c: Vector2, R: float, k: int, w: float, col: Color, hi: Color, lo: Color, seed: float, rot: float, fill := 0.82) -> void:
	for j in k:
		var a0: float = rot + TAU * (float(j) + 0.06 * _sk_h(j, seed)) / float(k)
		var a1: float = a0 + TAU / float(k) * (fill - 0.12 * _sk_h(j + 7, seed))
		_sk_arc(cv, c, R * (0.98 + 0.04 * _sk_h(j + 13, seed)), a0, a1, w * (0.8 + 0.4 * _sk_h(j + 3, seed)), col, hi, lo, seed + float(j))


func _sk_push(o, it: Dictionary) -> void:
	it["oid"] = str(o.id)
	it["k"] = ""
	if not it.has("t0"):
		it["t0"] = g.t
	_push(it)


## 同屏件数（同一名干员、同一类）
func _sk_count(o, kind: String) -> int:
	var n := 0
	var id: String = str(o.id)
	for it in items:
		if str(it.get("skr", "")) == kind and str(it.oid) == id:
			n += 1
	return n


func _ev_skalter(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var px: float = g.PX
	var st: Dictionary = _sk_state(o)
	if Bal.v("fx/recipe_log", 0.0) > 0.0:
		print("PXPLOG sk %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var c: Vector2 = d.get("c", o.pos)
			var r: float = float(d.get("r", 190.0))
			var es: Array = d.get("es", [])
			var key: String = "%s|%d|%d" % [src, int(c.x), int(c.y)]
			if st.dd.get(key, -1.0) == g.t:
				return   # 她当队长时「领唱」与普攻同一帧同一圈：只画一次
			st.dd[key] = g.t
			if raw:
				var rk: String = "sk_raw_wave_e%d" % t
				if src == "共鸣" or src == "深海的回响":
					rk = "sk_raw_wave_e0"
				_push({"k": rk, "t0": g.t, "gp": c, "ly": "raw", "rot": 0.0, "sc": px * (r * 0.5) / 95.0, "oid": str(o.id)})
				return
			match src:
				"声浪":
					_sk_push(o, {"skr": "wave", "c": c, "r": r, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
					_sk_notes(o, es, t, R, p)
					R._light(o, c + Vector2(0, -6), r * 0.7, 0.25 + 0.08 * t, 0.12, p.light)
				"余音":   # 精一：外圈回声
					_sk_push(o, {"skr": "echo_ring", "c": c, "r": r, "tier": t, "ly": "gd", "life": 4.0 / 15.0, "o": o, "fz": true})
				"潮汐和声":
					_sk_push(o, {"skr": "wave", "c": c, "r": r, "tier": t, "rose": true, "thin": true, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
				"海嗣":   # 精二伊莎玛拉同步声浪（酒红）
					_sk_push(o, {"skr": "wave", "c": c, "r": r, "tier": t, "sea": true, "ly": "gd", "life": 6.0 / 15.0})
					_sk_notes(o, es.slice(0, 2), t, R, p, true)
				"共鸣":   # 歌域内击杀处的小声浪
					if _sk_count(o, "mini") < 6:
						_sk_push(o, {"skr": "mini", "c": c, "r": r, "ly": "gd", "life": 4.0 / 15.0})
				_:
					if _sk_count(o, "mini") < 6:
						_sk_push(o, {"skr": "mini", "c": c, "r": r, "ly": "gd", "life": 4.0 / 15.0})
		"sk_burst":   # 深海的回响：满层爆开（酒红小爆环 + 几颗碎光）
			var at: Vector2 = d.at
			if raw:
				_push({"k": "sk_raw_wave_e0", "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": px * (float(d.r) * 0.5) / 95.0, "oid": str(o.id)})
				return
			if _sk_count(o, "burst") < 4:
				_sk_push(o, {"skr": "burst", "c": at, "r": float(d.r), "ly": "gd", "life": 5.0 / 15.0})
				if mode() == 1:
					R._grains(o, at + Vector2(0, -10), at.y + 2.0, "twinkle", 4, {"tier": t})
					R._light(o, at + Vector2(0, -8), 60.0, 0.35, 0.1, SK_R[4])
		"splash":   # late_shape「扩散」：命中溅射（同一拍至多 3 个）
			var at2: Vector2 = d.at
			if raw:
				_push({"k": "sk_raw_wave_e0", "t0": g.t, "gp": at2, "ly": "raw", "rot": 0.0, "sc": px * (float(d.r) * 0.5) / 95.0, "oid": str(o.id)})
				return
			if _lm_beat_n(o, "sk_splash") < 3:
				_sk_push(o, {"skr": "splash", "c": at2, "r": float(d.r), "ly": "gd", "life": 3.0 / 15.0})
		"skill":
			var i: int = int(d.get("i", -1))
			var zc: Vector2 = o.zone_c()
			var zr: float = float(o.zr)
			if raw:
				var rk2: String = ["sk_raw_s1_e%d" % t, "sk_raw_s2_e%d" % maxi(t, 1), "sk_raw_s3_e2"][clampi(i, 0, 2)]
				_push({"k": rk2, "t0": g.t, "gp": o.pos, "ly": "raw", "rot": 0.0, "sc": px * (zr * 0.5) / 95.0, "oid": str(o.id)})
				return
			match i:
				0:   # S1 同归殊途之吟：身周气泡（循环到技能结束，读 skill_active_left）+ 脚下酒红细环；歌域扩张一道浪
					_sk_push(o, {"skr": "wave", "c": zc, "r": zr, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
					R._light(o, o.pos + Vector2(0, -24), 90.0, 0.5, 0.15, SK_B[5])
					if mode() == 1:
						R._grains(o, o.pos + Vector2(0, -30), o.pos.y, "twinkle", 3 + 2 * t, {"tier": t})
				1:   # S2 同葬无光之愿：脚下旋涡 + 小鱼散开
					var tt: int = maxi(t, 1)
					_sk_push(o, {"skr": "vortex", "c": o.pos, "tier": tt, "ly": "gd", "life": 12.0 / 15.0, "o": o, "fs": true})
					_sk_push(o, {"skr": "fishburst", "c": o.pos, "tier": tt, "ly": "up", "gy": o.pos.y + 1.0, "life": 12.0 / 15.0, "o": o, "fs": true})
					if tt >= 2:
						_sk_push(o, {"skr": "spout", "c": o.pos, "ly": "up", "gy": o.pos.y + 2.0, "life": 8.0 / 15.0, "o": o, "fs": true})
					R._light(o, o.pos + Vector2(0, -12), 110.0, 0.5, 0.15, SK_B[4])
				2:   # S3 潮涌，潮枯：起手就是第一次潮涌，之后每 3 秒一次（draw_floor 里按技能剩余时间续）
					st.s3_next = g.t
		"sk_link":   # 连携 v2「歌声」：区域笔触圈 3 秒 + 起手一道大浪 + 音符
			var lc: Vector2 = d.c
			var lr: float = float(d.r)
			if raw:
				_push({"k": "sk_raw_s1_e2", "t0": g.t, "gp": lc, "ly": "raw", "rot": 0.0, "sc": px * (lr * 0.5) / 95.0, "oid": str(o.id)})
				return
			_sk_push(o, {"skr": "song", "c": lc, "r": lr, "ly": "gd", "life": 3.0})
			_sk_push(o, {"skr": "wave", "c": lc, "r": lr, "tier": 2, "ly": "gd", "life": 6.0 / 15.0})
			_sk_push(o, {"skr": "songnotes", "c": lc, "r": lr, "ly": "up", "gy": lc.y, "life": 3.0})
			R._light(o, lc + Vector2(0, -10), lr, 0.6, 0.15, SK_B[4])
		"sk_combo":   # 旧连携（link/v2 关）：落点大一号声浪 + 命中音符
			var cc: Vector2 = d.at
			var cr: float = float(d.r)
			if raw:
				_push({"k": "sk_raw_wave_e2", "t0": g.t, "gp": cc, "ly": "raw", "rot": 0.0, "sc": px * (cr * 0.5) / 95.0, "oid": str(o.id)})
				return
			_sk_push(o, {"skr": "wave", "c": cc, "r": cr, "tier": 2, "big": true, "ly": "gd", "life": 6.0 / 15.0})
			_sk_notes(o, d.get("es", []), 2, R, p)
			R._light(o, cc + Vector2(0, -10), cr, 0.6, 0.15, SK_B[4])


## 命中音符：每下至多 2 / 3 / 4 个（E0 / E1 / E2），同屏至多 12 个
func _sk_notes(o, es: Array, t: int, R, p: Dictionary, rose := false) -> void:
	var nmax: int = [2, 3, 4][t]
	var n := 0
	for e in es:
		if n >= nmax or _sk_count(o, "note") >= 12:
			break
		if not (e is Dictionary) or e.get("dead", false):
			continue
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) - 6.0)
		_sk_push(o, {"skr": "note", "c": hp, "tier": t, "rose": rose, "fl": (n % 2) == 1, "ly": "up", "gy": float(e.pos.y) + 1.0, "life": 9.0 / 15.0})
		if n == 0 and mode() == 1:
			R._grains(o, hp, float(e.pos.y) + 2.0, "twinkle", 1 + t, {"tier": t})
		n += 1


## 地面层：歌域（常驻）、伊莎玛拉小歌域、S3 持续加粗 / 潮涌、一次性贴地件
func _sk_draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var t: int = tier(o)
	var st: Dictionary = _sk_state(o)
	var bt: float = float(_sk_beat()) / 15.0
	var s3: float = o.skill_active_left(2)
	if s3 > 0.0 and float(st.s3_next) >= 0.0 and g.t >= float(st.s3_next):   # 潮涌：起手一次，之后每 3 秒
		st.s3_next = g.t + 3.0
		_sk_push(o, {"skr": "surge", "c": o.zone_c(), "r": float(o.zr), "ly": "gd", "life": 7.0 / 15.0, "o": o, "fz": true})
		_sk_push(o, {"skr": "pillars", "c": o.zone_c(), "r": float(o.zr), "ly": "up", "gy": o.zone_c().y + 2.0, "life": 7.0 / 15.0, "o": o, "fz": true})
		var R = load("res://scripts/render/fx_recipe.gd").of(g)
		R._light(o, o.zone_c() + Vector2(0, -20), float(o.zr), 0.8, 0.15, SK_B[4])
		R._light(o, o.zone_c() + Vector2(0, -60), 120.0, 0.6, 0.15, SK_R[4])
		R._grains(o, o.zone_c() + Vector2(0, -30), o.zone_c().y, "twinkle", 6, {"tier": 2})
	elif s3 <= 0.0:
		st.s3_next = -1.0
	if o.pos != Vector2.INF and o.B.has("zone"):
		var zc: Vector2 = o.zone_c()
		var zv: float = _sk_r(o, "self", float(o.zr))
		var s1: bool = o.skill_active_left(0) > 0.0
		_sk_domain(cv, zc, zv, t, s1, s3 > 0.0, bt, 0.0, false)
	for s in (o.sm.list if not o.sm.is_empty() else []):
		var szr: float = float(s.get("zr", 0.0))
		if szr <= 0.0 or s.gone:
			continue
		var fa: float = clampf(float(s.t) / 0.5, 0.0, 1.0)
		_sk_domain(cv, s.pos, _sk_r(o, "sm", szr) * fa, t, false, false, bt, 3.7, true)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id and it.has("skr"):
			_sk_draw_gd(cv, o, it)


## 一个歌域：边上 3–5 段粗笔触（慢转）+ 贴边淡渐变 + 内侧反向细笔触线；rose = 伊莎玛拉小歌域（酒红、细）
func _sk_domain(cv, c: Vector2, R: float, t: int, s1: bool, s3: bool, bt: float, seed: float, rose: bool) -> void:
	if R <= 8.0:
		return
	var dim: float = clampf(float(g.world.fx_dim), 0.5, 1.0)
	var C: Array = SK_T if rose else SK_B
	var n: int = (3 + t) if not s3 else 6
	if s1 and not s3:
		n += 1
	var w: float = (3.0 if t < 2 else 4.0) if not s3 else 5.0
	if rose:
		n = 3
		w = 2.0
	var spin: float = (0.10 if not s3 else 0.28) * (1.0 if not rose else -1.3)
	var rot: float = bt * spin + seed
	var main: Color = C[3] if not (s1 or s3) else C[4]
	main.a = 0.92 * dim
	var hi: Color = C[5]
	hi.a = 0.9 * dim
	var lo: Color = C[1]
	lo.a = 0.8 * dim
	var cover: float = 0.62 if not s3 else 0.72
	for j in n:
		var a0: float = rot + TAU * (float(j) + 0.15 * _sk_h(j, seed + 1.0)) / float(n)
		var a1: float = a0 + TAU / float(n) * cover * (0.75 + 0.5 * _sk_h(j + 5, seed + 1.0))
		_sk_arc(cv, c, R * (0.985 + 0.03 * _sk_h(j + 11, seed)), a0, a1, w, main, hi, lo, seed + float(j) * 1.7)
	# 贴边淡渐变（不平涂中心）
	var ga: float = (0.10 if not s3 else 0.16) * dim * (0.7 if rose else 1.0)
	_sk_grad(cv, c, R - g.PX * (10.0 if not s3 else 18.0), R, C[3], 0.0, ga)
	# 内侧细笔触线（11-05 用户「内部可以稍微实一点，或者加点线条」）：2–4 道，反向慢转，1 美术像素
	if not rose:
		var nl: int = 2 + t if not s3 else 5
		var lc: Color = C[4]
		lc.a = (0.45 if not s3 else 0.6) * dim
		for j in nl:
			var rr: float = R * (0.62 + 0.22 * _sk_h(j + 31, seed))
			var a0: float = -bt * (0.18 if not s3 else 0.45) + TAU * float(j) / float(nl) + _sk_h(j + 41, seed)
			_sk_arc(cv, c, rr, a0, a0 + 0.9 + 0.5 * _sk_h(j + 51, seed), 1.0, lc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), seed + 9.0 + j)


## 挂在人身上的件（歌域圆心 fz / 本人脚下 fs）：持续期间跟着施放者当前位置走（按 15 fps 拍跳格）；落在地上的件留在原地
func _sk_c(it: Dictionary) -> Vector2:
	var o = it.get("o", null)
	if o != null and is_instance_valid(o) and o.pos != Vector2.INF:
		if it.get("fz", false):
			return _snap(o.zone_c())
		if it.get("fs", false):
			return _snap(o.pos)
	return it.c


func _sk_draw_gd(cv, o, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	var px: float = g.PX
	var c: Vector2 = _sk_c(it)
	match str(it.skr):
		"wave":   # 声浪：断口笔触浪 0.6R → R（4 拍扩到边、第 5 拍淡），E1 第二道、E2 夹酒红暗流
			if f < 0 or f > 5:
				return
			var t: int = int(it.tier)
			var rose: bool = it.get("rose", false)
			var thin: bool = it.get("thin", false)
			var sea: bool = it.get("sea", false)
			var C: Array = SK_T if sea else (SK_R if rose else SK_B)
			var R: float = float(it.r) * [0.6, 0.78, 0.9, 0.97, 1.0, 1.02][f]
			var w: float = ([4.0, 5.0, 6.0][t] if not thin else 2.0) * [1.0, 1.0, 0.85, 0.7, 0.5, 0.35][f]
			if it.get("big", false):
				w += 2.0
			var col: Color = C[6] if f == 0 else (C[5] if f == 1 else C[4])
			if f >= 4:
				col = C[3]
				col.a = 0.6 if f == 4 else 0.35
			var hi: Color = C[6] if f <= 2 else C[5]
			var lo: Color = C[2]
			var seed: float = float(int(it.t0 * 7.0) % 97)
			_sk_ring(cv, c, R, 7 if t < 2 else 8, w, col, hi, lo, seed, seed * 0.37)
			if t >= 1 and not thin and f >= 1:   # 精一：晚一拍的第二道细浪
				var c2: Color = C[4]
				c2.a = 0.7 if f < 4 else 0.3
				_sk_ring(cv, c, R * 0.86, 6, 2.0, c2, Color(0, 0, 0, 0), Color(0, 0, 0, 0), seed + 3.0, seed * 0.37 + 0.4, 0.7)
			if t >= 2 and not rose and not sea and f <= 4:   # 精二：浪里一道酒红暗流（专属色），紧贴浪内侧
				var rc: Color = SK_R[3] if f < 3 else SK_R[2]
				_sk_ring(cv, c, R - (w * 0.5 + 1.5) * px, 7, 2.0, rc, SK_R[4], Color(0, 0, 0, 0), seed + 5.0, seed * 0.37 + 0.2, 0.7)
			if f <= 1:
				for j in 6:   # 浪头热白点进发光层
					_glow(_sk_ep(c, R, seed + TAU * float(j) / 6.0), C[6])
		"echo_ring":   # 余音：歌域外圈一道酒红细环闪 3 拍
			if f < 0 or f > 3:
				return
			var col2: Color = SK_R[4] if f < 2 else SK_R[3]
			col2.a = [0.9, 0.8, 0.5, 0.25][f]
			_sk_ring(cv, c, float(it.r) * 0.95, 9, 2.0, col2, SK_R[5] if f == 0 else Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(int(it.t0 * 5.0) % 31), 0.3)
		"mini", "splash":   # 小声浪 / 溅射环
			var nb: int = 4 if str(it.skr) == "mini" else 3
			if f < 0 or f >= nb:
				return
			var R2: float = float(it.r) * [0.5, 0.8, 1.0, 1.05][f]
			var col3: Color = SK_B[5] if f == 0 else SK_B[4]
			col3.a = [1.0, 0.85, 0.5, 0.3][f]
			_sk_ring(cv, c, R2, 5, 2.0 if f < 2 else 1.0, col3, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(int(it.t0 * 9.0) % 41), 0.0, 0.75)
		"burst":   # 深海的回响：酒红小爆环 + 实心亮芯一拍
			if f < 0 or f > 4:
				return
			var R3: float = float(it.r) * [0.35, 0.7, 0.9, 1.0, 1.05][f]
			var col4: Color = SK_R[5] if f == 0 else SK_R[4]
			col4.a = [1.0, 1.0, 0.8, 0.5, 0.25][f]
			_sk_ring(cv, c, R3, 6, 3.0 if f < 2 else 2.0, col4, SK_R[6] if f < 2 else Color(0, 0, 0, 0), SK_R[2], float(int(it.t0 * 3.0) % 23), 0.5)
			if f <= 1:
				_sk_grad(cv, c, 0.0, R3 * 0.6, SK_R[4], 0.55, 0.2)
		"vortex":   # S2 起手旋涡：3 / 5 条旋臂笔触从脚下卷开再淡
			if f < 0 or f > 11:
				return
			var t2: int = int(it.tier)
			var arms: int = 3 if t2 < 2 else 5
			var Rv: float = 130.0 * [0.4, 0.6, 0.75, 0.85, 0.92, 0.97, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][f]
			var al: float = 1.0 if f < 7 else (1.0 - float(f - 6) / 6.0)
			for j in arms:
				var base: float = TAU * float(j) / float(arms) + float(f) * 0.35
				for s in 3:   # 每条旋臂三节，越往外越靠后（旋）
					var rr: float = Rv * (0.35 + 0.25 * float(s))
					var cl: Color = [SK_B[5], SK_B[4], SK_B[3]][s]
					cl.a = al * [1.0, 0.9, 0.75][s]
					_sk_arc(cv, c, rr, base + 0.55 * float(s), base + 0.55 * float(s) + 1.0, [4.0, 4.0, 3.0][s] + (1.0 if t2 >= 2 else 0.0), cl, SK_B[6] if s == 0 and f < 4 else Color(0, 0, 0, 0), SK_B[1], float(j) * 3.0 + float(s))
			_sk_grad(cv, c, 0.0, Rv * 0.5, SK_B[2], 0.35 * al, 0.0)
		"surge":   # S3 潮涌：粗笔触亮蓝环扩到歌域边 + 深蓝内影 + 内部实心渐变 + 8 道旋转笔触线
			if f < 0 or f > 6:
				return
			var Rs: float = float(it.r) * [0.6, 0.78, 0.9, 0.97, 1.0, 1.0, 1.0][f]
			var fa2: float = [1.0, 1.0, 1.0, 0.9, 0.75, 0.5, 0.25][f]
			var fill_k: float = [1.0, 0.9, 0.7, 0.45, 0.2, 0.0, 0.0][f]
			_sk_grad(cv, c, 0.0, Rs * 0.98, SK_B[2], 0.35 * fill_k, 0.5 * fill_k)   # 内部实心：中心 0.35（站人处清楚）→ 边 0.5，5 拍内收掉
			var nl: int = 8
			for j in nl:   # 旋转向心笔触线
				var a0: float = TAU * float(j) / float(nl) + float(f) * 0.32
				var lc: Color = SK_B[5] if f < 3 else SK_B[4]
				lc.a = fa2 * 0.9
				for s in 2:
					var rr2: float = Rs * (0.42 + 0.26 * float(s))
					_sk_arc(cv, c, rr2, a0 + 0.35 * float(s), a0 + 0.35 * float(s) + 0.55, 2.0, lc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j) + float(s) * 5.0)
			var mc: Color = SK_B[6] if f == 0 else (SK_B[5] if f <= 2 else SK_B[4])
			mc.a = fa2
			var w8: float = 8.0 * [1.0, 1.0, 0.95, 0.85, 0.7, 0.55, 0.4][f]
			_sk_ring(cv, c, Rs, 6, w8, mc, SK_B[6], Color(SK_B[1].r, SK_B[1].g, SK_B[1].b, fa2), 17.0, float(f) * 0.12, 0.9)
			if f <= 2:
				for j in 10:
					_glow(_sk_ep(c, Rs, TAU * float(j) / 10.0 + 0.3), SK_B[6])
		"song":   # 连携 v2「歌声」区域：4 段粗笔触 + 3 段酒红内圈（反向）+ 贴边渐变，3 秒，最后 0.4 秒淡
			var age: float = g.t - float(it.t0)
			var fa3: float = 1.0 if age < 2.6 else clampf((3.0 - age) / 0.4, 0.0, 1.0)
			var bt: float = float(_sk_beat()) / 15.0
			var Rg: float = float(it.r)
			var mcol: Color = SK_B[4]
			mcol.a = 0.95 * fa3
			for j in 4:
				var a0: float = bt * 0.35 + TAU * float(j) / 4.0
				_sk_arc(cv, c, Rg, a0, a0 + 1.05, 5.0, mcol, Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, fa3), Color(SK_B[1].r, SK_B[1].g, SK_B[1].b, fa3), 21.0 + float(j))
			var rcol: Color = SK_R[3]
			rcol.a = 0.9 * fa3
			for j in 3:
				var a0: float = -bt * 0.5 + TAU * float(j) / 3.0
				_sk_arc(cv, c, Rg * 0.82, a0, a0 + 1.2, 2.0, rcol, Color(SK_R[4].r, SK_R[4].g, SK_R[4].b, fa3), Color(0, 0, 0, 0), 31.0 + float(j))
			_sk_grad(cv, c, Rg - px * 14.0, Rg, SK_B[3], 0.0, 0.16 * fa3)


## 立起层（排序项 kind 7）
func _sk_draw_up(ci, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	var px: float = g.PX
	var c: Vector2 = _sk_c(it)
	match str(it.skr):
		"note":   # 命中音符：第 0 拍白头，往上飘 9 拍，最后两拍只剩符头
			if f < 0 or f > 8:
				return
			var t: int = int(it.tier)
			var rose: bool = it.get("rose", false)
			var pat: Array = SK_NOTE2 if t >= 2 else SK_NOTE
			var C: Array = SK_T if rose else SK_R   # 酒红音符：敌人多是白 / 蓝，压在上面读得出来；海嗣的音符用海嗣青
			var col: Color = C[5] if f < 3 else C[4]
			var head: Color = C[6] if f == 0 else (C[5] if f < 4 else C[4])
			if f >= 7:
				col.a = 0.0
				head.a = 0.6
			var up: float = float(f) * px * (1.0 if f < 5 else 0.6)
			var w: float = float((pat[0] as String).length()) * px
			var shc: Color = C[0]
			shc.a = 0.85 if f < 7 else 0.0
			_sk_pat(ci, pat, c + Vector2(-w * 0.5 + (10.0 if it.get("fl", false) else -10.0), -float(pat.size()) * px - up - 8.0), col, head, it.get("fl", false), shc)
			if f <= 1:
				_glow(c + Vector2(0, -up - px), C[6])
		"pillars":   # S3 潮涌：5 根粗亮红竖光柱从歌域里冲起又回落（原作 skill_03_buff_02 的红光柱）；白热芯、亮红身、暗酒红边，顶端淡出
			if f < 0 or f > 6:
				return
			var Rr: float = float(it.r)
			var H: float = 66.0 * px * [0.55, 1.0, 1.0, 0.95, 0.85, 0.7, 0.5][f]
			var W: int = [7, 9, 9, 8, 7, 5, 3][f]
			for j in 5:
				var a: float = TAU * float(j) / 5.0 + 0.6 + 0.2 * _sk_h(j, float(it.t0))
				var foot: Vector2 = _snap(_sk_ep(c, Rr * (0.55 + 0.25 * _sk_h(j + 3, 1.0)), a))
				var hj: float = H * (0.8 + 0.35 * _sk_h(j + 9, 2.0))
				_sk_pillar(ci, foot, W, hj, f)
		"fishburst":   # S2 起手：小鱼从脚下沿旋涡散开
			if f < 0 or f > 11:
				return
			var t2: int = int(it.tier)
			var n: int = 3 if t2 < 2 else 5
			for j in n:
				var a: float = TAU * float(j) / float(n) + float(f) * 0.3
				var rr: float = (12.0 + 7.0 * float(f)) * px
				var q: Vector2 = _sk_ep(c, rr, a) + Vector2(0, -10.0 - 1.5 * float(f))
				var fl: bool = cos(a + PI * 0.5) < 0.0
				_sk_pat(ci, SK_FISH, q, SK_R[3], SK_R[4], fl, Color(SK_R[0].r, SK_R[0].g, SK_R[0].b, 0.8))
		"spout":   # S2 精二：涡眼冲起一道水柱
			if f < 0 or f > 7:
				return
			var Hs: float = 52.0 * px * [0.4, 0.8, 1.0, 1.0, 0.9, 0.75, 0.55, 0.35][f]
			_sk_column(ci, _snap(c), [4, 5, 5, 5, 4, 4, 3, 2][f], Hs, SK_B, f)
		"songnotes":   # 连携 v2：区域里每 0.5 秒冒 3 个音符往上飘
			var age: float = g.t - float(it.t0)
			if age > 3.0:
				return
			var Rg: float = float(it.r)
			for k in 3:
				var wave: int = int(age * 2.0)
				var u: float = fposmod(age * 2.0, 1.0)
				var a: float = TAU * (float(k) / 3.0 + 0.37 * float(wave))
				var q: Vector2 = _sk_ep(c, Rg * (0.35 + 0.4 * _sk_h(k + wave * 3, 4.0)), a)
				var fb: int = int(u * 7.5)
				var colN: Color = (SK_R if k == 1 else SK_B)[5]
				var headN: Color = (SK_R if k == 1 else SK_B)[6 if fb == 0 else 5]
				if fb >= 6:
					colN.a = 0.0
				_sk_pat(ci, SK_NOTE, q + Vector2(-8.0, -30.0 - float(fb) * px), colN, headN, k == 2, Color(SK_B[0].r, SK_B[0].g, SK_B[0].b, 0.0 if fb >= 6 else 0.8))


## 红光柱：宽 W 美术像素、高 H 世界像素；脚下一小片亮红地光
func _sk_pillar(ci, foot: Vector2, W: int, H: float, f: int) -> void:
	var px: float = g.PX
	var x0: float = foot.x - float(W / 2) * px
	var steps: int = maxi(1, int(H / (px * 4.0)))
	for s in steps:   # 自下而上 4 美术像素一段，顶端三段淡出
		var y: float = foot.y - float(s + 1) * px * 4.0
		var top_k: float = 1.0 - clampf(float(s - (steps - 3)) / 3.0, 0.0, 1.0) * 0.85 if steps > 3 else 1.0
		for x in W:
			var edge: bool = x == 0 or x == W - 1
			var core: bool = W >= 5 and absi(x - W / 2) <= (1 if W >= 7 else 0)
			var col: Color = SK_R[2] if edge else (SK_R[6] if core and f <= 2 else (SK_R[5] if core else SK_R[4]))
			col.a = top_k * (0.85 if edge else 1.0)
			ci.draw_rect(Rect2(Vector2(x0 + float(x) * px, y), Vector2(px, px * 4.0)), col)
		if s % 2 == 0 and f <= 3:
			_glow(Vector2(foot.x, y), SK_R[5])
	var fc: Color = SK_R[4]
	fc.a = 0.6
	ci.draw_rect(Rect2(_snap(foot + Vector2(-float(W) * px, -px)), Vector2(float(W) * 2.0 * px, px * 2.0)), fc)


## 水柱（S2 涡眼）：同红光柱的画法，蓝色
func _sk_column(ci, foot: Vector2, W: int, H: float, C: Array, f: int) -> void:
	var px: float = g.PX
	var x0: float = foot.x - float(W / 2) * px
	var steps: int = maxi(1, int(H / (px * 3.0)))
	for s in steps:
		var y: float = foot.y - float(s + 1) * px * 3.0
		var top_k: float = 1.0 if s < steps - 2 else 0.55
		for x in W:
			var edge: bool = x == 0 or x == W - 1
			var col: Color = C[3] if edge else (C[6] if f <= 1 and x == W / 2 else C[5])
			col.a = top_k
			ci.draw_rect(Rect2(Vector2(x0 + float(x) * px, y), Vector2(px, px * 3.0)), col)


## 立起层的状态件：S1 身周气泡、S2 常驻小鱼
func _sk_sort_items(o, out: Array) -> void:
	var t: int = tier(o)
	if o.skill_active_left(0) > 0.0:
		out.append({"skr_s": "bubble", "o": o, "gy": o.pos.y + 3.0})
	var s2on: bool = o.get("perm_on") != null and bool(o.perm_on[1])
	if s2on and o.B.has("zone"):
		out.append({"skr_s": "fish", "o": o, "gy": o.zone_c().y + 1.0})


func _sk_draw_state_up(ci, it: Dictionary) -> void:
	var o = it.o
	var t: int = tier(o)
	var px: float = g.PX
	var bt: int = _sk_beat()
	match str(it.skr_s):
		"bubble":   # S1：身周一团气泡（细膜 + 左上高光 + 淡淡的水 0.16）；E1 双层膜、E2 三团（主泡两侧各连一个小泡）
			var c: Vector2 = _snap(o.pos + Vector2(0, -26))
			var wob: float = [0.0, 1.0, 0.0, -1.0][bt % 4] * px
			var Rb: float = (23.0 if t == 0 else 26.0) * px
			var bubs: Array = [[c, Rb + wob]]
			if t >= 2:
				bubs.append([_snap(c + Vector2(-Rb * 1.05, Rb * 0.45)), Rb * 0.42 - wob * 0.5])
				bubs.append([_snap(c + Vector2(Rb * 1.0, Rb * 0.55)), Rb * 0.36 + wob * 0.5])
			for b in bubs:
				var bc: Vector2 = b[0]
				var br: float = b[1]
				ci.draw_circle(bc, br, Color(SK_B[3].r, SK_B[3].g, SK_B[3].b, 0.16))
				ci.draw_arc(bc, br, 0.0, TAU, clampi(int(br / 2.0), 12, 40), Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, 0.9), px)
				ci.draw_arc(bc, br - px * 2.0, PI * 1.05, PI * 1.45, 8, SK_B[6], px)   # 左上高光
				if t >= 1 and br > Rb * 0.6:
					ci.draw_arc(bc, br - px * 3.0, PI * 0.1, PI * 0.9, 14, Color(SK_B[4].r, SK_B[4].g, SK_B[4].b, 0.6), px)   # 精一：第二层膜（下半）
			_glow(c + Vector2(-Rb * 0.55, -Rb * 0.6), SK_B[6])
			# 脚下酒红细环（贴地，跟在立起件里画：它跟着气泡走、本来就在她脚下）
			var fr := PackedVector2Array()
			for k in 25:
				fr.append(_snap(_sk_ep(o.pos + Vector2(0, 2), 20.0 * px, TAU * float(k) / 24.0)))
			ci.draw_polyline(fr, Color(SK_R[3].r, SK_R[3].g, SK_R[3].b, 0.85), px)
			if t >= 1:   # 精一：外面再一圈酒红细环
				var fr2 := PackedVector2Array()
				for k in 25:
					fr2.append(_snap(_sk_ep(o.pos + Vector2(0, 2), 26.0 * px, TAU * float(k) / 24.0 + 0.1)))
				ci.draw_polyline(fr2, Color(SK_R[2].r, SK_R[2].g, SK_R[2].b, 0.7), px)
			# 上浮小泡：每拍错落 3–5 个
			var nb: int = 3 + t
			for k in nb:
				var ph: int = (bt + k * 5) % 15
				var bx: float = (_sk_h(k, 3.0) - 0.5) * Rb * 1.6
				var q: Vector2 = _snap(c + Vector2(bx, Rb * 0.6 - float(ph) * px * 2.0))
				ci.draw_rect(Rect2(q, Vector2(px, px)), Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, 0.9 if ph < 10 else 0.4))
		"fish":   # S2 常驻：酒红小鱼绕歌域边慢慢游（E1 3 条 / E2 5 条）
			var zc: Vector2 = o.zone_c()
			var zv: float = _sk_r(o, "self", float(o.zr))
			var n: int = 3 if t < 2 else 5
			for j in n:
				var a: float = TAU * float(j) / float(n) + float(bt) / 15.0 * 0.22 * (1.0 if j % 2 == 0 else 0.8)
				var q: Vector2 = _sk_ep(zc, zv * (0.9 + 0.06 * _sk_h(j, 6.0)), a) + Vector2(-7.0, -16.0 - px * float((bt + j * 4) % 6 / 3))
				var fl: bool = sin(a) > 0.0   # 顺时针游：上半圈朝右、下半圈朝左
				_sk_pat(ci, SK_FISH, q, Color(SK_R[3].r, SK_R[3].g, SK_R[3].b, 0.9), SK_R[4], fl, Color(SK_R[0].r, SK_R[0].g, SK_R[0].b, 0.7))


## 旧做法（2）：整张贴（光晕烤进颜色，按歌域半径小数缩放、盖在所有单位上）；S1 / S3 期间按技能剩余时间循环
func _sk_draw_raw(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
