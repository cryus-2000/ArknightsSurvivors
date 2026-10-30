## 终结技 第二组（斯卡蒂 / 歌蕾蒂娅 / 安洁莉娜 / 艾雅法拉 / 维什戴尔 / 归溟幽灵鲨 / 水月）（docs/198 §4，用户 10-29「20 个干员的都做好、先用粒子特效」）。接口同 run/ult_moves.gd：
## handles(id) 本文件管哪些人；aim_kind / aim_r 瞄准；start(u, o, aim, dir) 返回动作字典（ult_moves 会写入 a.k / a.o / a.t）；step(u, a, dt) true = 结束。
## 形态（用户 10-29 定）：斯卡蒂 海浪带 / 歌蕾蒂娅 海渊漩涡 / 安洁莉娜 重力奇点（吸起再砸下）/ 艾雅法拉 火柱 + 熔岩落满 / 维什戴尔 地毯式炮击带 /
## 归溟幽灵鲨 环绕巨锯 3 秒（跟着队长走）/ 水月 巨型触手横扫半圆。
## 伤害一律走 u.hit（按目标生命定的预算，§3.3）；每段一张已命中表（e.id），同一敌人同一段只打一次；外缘 15% 宽的衰减带传 edge。
## 铺垫段（漩涡旋转、奇点吸起、熔岩弹预热）标 pre，冲击帧落在主打击那一下。
## 画面：程序占位图形（u.shape）+ 现有帧条（u.strip，game/art/fx）；持续跟着动的图形放 a.fx，每帧改位置、把 age 拨回 0 保持不透明，收尾时统一淡出。
## 范围（§3.2 草案）在实测后略放大了几处（对齐表口径：屏内小怪倒下 40–55%，外缘带打不死普通小怪，见各人注释）。不抽随机数，散布按序号算。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const PF = preload("res://scripts/run/ult_pixfx.gd")
const A = preload("res://scripts/art.gd")   # pixfx 大贴图画法（docs/199 §7.8）
const IDS: Array = ["skadi", "gladiia", "angelina", "eyjafjalla", "wisadel", "specter_unchained", "mizuki"]
const DIR_OPS: Array = ["skadi", "wisadel", "mizuki"]
const POINT_OPS: Array = ["gladiia", "angelina", "eyjafjalla"]

const GA := 2.39996   # 黄金角：按序号散布


static func handles(id: String) -> bool:
	return id in IDS


static func aim_kind(id: String) -> String:
	if id in DIR_OPS:
		return "dir"
	if id in POINT_OPS:
		return "point"
	return "none"


## 瞄准指示的半径（选落点：落点圆；不瞄：以自身为中心的圈）
static func aim_r(id: String) -> float:
	match id:
		"gladiia":
			return Bal.v("ult/gl_r", 470.0)
		"angelina":
			return Bal.v("ult/an_r", 520.0)   # 10-30 对齐表 470 → 520（屏内小怪 43.8% → 约 50%，朝上瞄时 350 处精英也罩得到）
		"eyjafjalla":
			return Bal.v("ult/ey_r", 590.0)   # 10-30 对齐表 520 → 590（外缘带打不死普通小怪，屏内小怪 40.4% → 约 50%）
		"specter_unchained":
			return Bal.v("ult/su_r", 505.0)   # 10-30 对齐表 340 → 505（罩住 500 处精英与 420 处 Boss，吸力同时关掉；屏内小怪 44%：再大聚怪档就过 75% 上限）
	return 460.0


static func start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var c: Vector2 = aim if aim != Vector2.INF else o.pos + d * 260.0
	var a: Dictionary
	match str(o.id):
		"skadi":
			a = _sd_start(u, o, d)
		"gladiia":
			a = _gl_start(u, o, c)
		"angelina":
			a = _an_start(u, o, c)
		"eyjafjalla":
			a = _ey_start(u, o, c)
		"wisadel":
			a = _wd_start(u, o, d)
		"specter_unchained":
			a = _su_start(u, o)
		"mizuki":
			a = _mz_start(u, o, d)
		_:
			return {}
	a["id"] = str(o.id)
	if not a.has("fx"):
		a["fx"] = []
	return a


static func step(u, a: Dictionary, dt: float) -> bool:
	if a.is_empty():
		return true
	var o = a.o
	var done := true
	match str(a.get("id", "")):
		"skadi":
			done = _sd_step(u, a, o)
		"gladiia":
			done = _gl_step(u, a, o, dt)
		"angelina":
			done = _an_step(u, a, o)
		"eyjafjalla":
			done = _ey_step(u, a, o)
		"wisadel":
			done = _wd_step(u, a, o)
		"specter_unchained":
			done = _su_step(u, a, o, dt)
		"mizuki":
			done = _mz_step(u, a, o)
	if done:
		_fade(u, a, 0.25)
	return done


# ================================================================ 公用

## 一段伤害：连携终结技里（ult_moves._cult_generic_start 给队长动作挂了 cap / fr）每名敌人合计不超过 cap 份预算，同 ult_moves._hit
static func _hit(u, a: Dictionary, o, e: Dictionary, frac: float, opt: Dictionary = {}) -> float:
	if a.has("cap"):
		var k: int = int(e.id)
		var done: float = float(a.fr.get(k, 0.0))
		frac = minf(frac, float(a.cap) - done)
		if frac <= 0.0001:
			return 0.0
		a.fr[k] = done + frac
	return u.hit(o, e, frac, opt)


static func _edge_w() -> float:
	return Bal.v("ult/edge_w", 0.15)


static func _route(o) -> String:
	var r = o.get("route")
	return str(r) if r != null else ""


## 击退距离 → 冲量（敌人 kb 每秒衰减 900）
static func _kb_v(dist: float) -> float:
	return sqrt(1800.0 * maxf(0.0, dist))


## 精英 u.hit 会把冲量减半：要精英也退 dist，就按目标预先翻倍
static func _kb_for(e: Dictionary, dir: Vector2, d_minion: float, d_elite: float) -> Vector2:
	if e.elite or e.get("part", false):
		return dir * _kb_v(d_elite) * 2.0
	return dir * _kb_v(d_minion)


## 持续图形：挂进 a.fx，step 里每帧改位置并 _hold（age 拨回 0，保持不透明）；结束 / 中途被清时统一收
static func _keep(u, a: Dictionary, s: Dictionary) -> Dictionary:
	if not a.has("fx"):
		a["fx"] = []
	u.shape(s)
	a.fx.append(s)
	return s


static func _hold(s: Dictionary) -> void:
	if str(s.kind) != "strip":
		s.age = 0.0


## 收尾：程序图形 t 秒内淡出，帧条直接收
static func _fade(u, a: Dictionary, t: float) -> void:
	if not (a.get("fx") is Array):
		return
	for s in a.fx:
		if str(s.kind) == "strip":
			u.shapes.erase(s)
		else:
			s.age = 0.0
			s.max = t
	a.fx.clear()


static func _ring(u, c: Vector2, r: float, r1: float, col: Color, life: float, w := 6.0, delay := 0.0) -> void:
	u.shape({"kind": "ring", "c": c, "r": r, "r1": r1, "w": w, "col": col, "life": life, "delay": delay})


## 向外飞散的碎点（n 簇，每簇一个 dots 图形带速度）
static func _spray(u, c: Vector2, n: int, r0: float, spd: float, col: Color, life: float, a0 := 0.0, delay := 0.0) -> void:
	for i in n:
		var ang: float = a0 + TAU * float(i) / float(n)
		var dv: Vector2 = Vector2.from_angle(ang)
		u.shape({"kind": "dots", "c": c + dv * r0, "r": 26.0, "n": 6, "col": col, "life": life, "delay": delay, "v": dv * spd})


## 圆内按黄金角均匀散布的第 i 个点（共 n 个）
static func _spiral(c: Vector2, r: float, i: int, n: int, a0 := 0.0) -> Vector2:
	return c + Vector2.from_angle(a0 + float(i) * GA) * r * sqrt((float(i) + 0.5) / float(n))


# ================================================================ 斯卡蒂（§4.6）：下劈 → 劈开处立起大浪，0.8 秒推过屏幕

## 带宽 920，从身后 200 起推到屏外（§3.2 草案 820 / 60；10-30 对齐表：判定改成与画面一致的矩形后放宽，
## 屏内小怪 / 朝上瞄时 500 处精英都罩得到，见 docs/199 §7）
static func _sd_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var hw: float = Bal.v("ult/sd_w", 920.0) * 0.5
	var waves: Array = [[Bal.v("ult/sd_t0", 0.15), 1.0]]
	if rt == "wave":   # 跃浪：浪分两道（第二道 0.3 秒后、各 55%），宽为缺省的 380 / 410（原 760 对 820）
		hw *= 380.0 / 410.0
		waves = [[0.15, 0.55], [0.45, 0.55]]
	o.face_to(d.angle())
	o.play_vis_anim("attack")
	var col: Color = u._col(o)
	# 举剑：剑锋一道蓄光
	u.shape({"kind": "blade", "a": o.pos - d * 30.0, "b": o.pos + d * 120.0, "w": 6.0, "col": Color.WHITE, "glow": col, "grow": 0.1, "life": 0.14})
	var ws: Array = []
	for w in waves:
		ws.append({"t0": float(w[0]), "frac": float(w[1]), "seg": {}, "fx": [], "spr": [], "done": false, "spray_t": 0.0})
	return {"o0": o.pos, "d": d, "n": d.orthogonal(), "hw": hw, "back": Bal.v("ult/sd_back", 200.0), "L": Bal.v("ult/sd_len", 1500.0),
		"T": Bal.v("ult/sd_push", 0.8) * (0.8 if waves.size() > 1 else 1.0), "slash": false, "sseg": {}, "waves": ws,
		"surge": rt == "surge", "surged": false, "no_ring": true}


static func _sd_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var o0: Vector2 = a.o0
	var d: Vector2 = a.d
	var n: Vector2 = a.n
	var hw: float = a.hw
	var back: float = a.back
	var L: float = a.L
	var T: float = a.T
	var col: Color = u._col(o)
	var foam: Color = col.lerp(Color.WHITE, 0.65)
	if not a.slash and t >= 0.12:
		a.slash = true   # 下劈：前方 200 内 30%（劈中的人浪头只再吃 70%）
		var sc: Vector2 = o0 + d * 110.0
		for e in u.in_circle(sc, 210.0):
			a.sseg[int(e.id)] = true
			_hit(u, a, o, e, Bal.v("ult/sd_slash", 0.3), {"src": "下劈", "edge": e.pos.distance_to(sc) > 210.0 * (1.0 - _edge_w())})
		u.shape({"kind": "blade", "a": o0 - d * 40.0, "b": o0 + d * 320.0, "w": 16.0, "col": Color(0.78, 0.86, 0.94) if _sd_v2(u) else Color.WHITE, "glow": col, "grow": 0.04, "life": 0.3 if not _sd_v2(u) else 0.2})
		if _sd_v4(u):
			_sd_cleave_v4(u, a, o0, d, a.n, col)
		elif _sd_v2(u):   # 劈开处溅起水色像素粒子（不用卡通水花帧条）
			PF.particles(u, o0 + d * 120.0, 300, "ult_burst", [col, col.darkened(0.3)], 0.0, PF.vseed(u, o0), 220.0)
		else:
			u.strip("fx_skadi_surge", o0 + d * 120.0, {"sc": 2.4})
		_ring(u, sc, 210.0, 30.0, foam, 0.35, 8.0)
		_spray(u, sc, 10, 40.0, 520.0, foam, 0.35, d.angle())
		o.screen_shake(0.6)
	var all_done := true
	for w in a.waves:
		if bool(w.done):
			continue
		all_done = false
		var t0: float = w.t0
		if t < t0:
			continue
		var k: float = clampf((t - t0) / T, 0.0, 1.0)
		var F: float = -back + (L + back) * k * (1.35 - 0.35 * k)   # 先快后略缓
		if w.fx.is_empty():   # 水体 + 浪头白沫 + 前沿线 + 浪头帧条一排
			var v2: bool = _sd_v2(u)
			w.fx.append(_keep(u, a, {"kind": "band", "a": o0 - d * back, "b": o0, "w": hw * 2.0, "col": col, "fill": 0.2, "life": 2.0}))
			w.fx.append(_keep(u, a, {"kind": "band", "a": o0, "b": o0, "w": hw * 2.0, "col": foam, "fill": 0.1 if v2 else 0.42, "life": 2.0}))
			w.fx.append(_keep(u, a, {"kind": "nop" if v2 else "line", "a": o0, "b": o0, "w": 5.0, "col": Color.WHITE, "life": 2.0}))
			if v2 and _sd_v4(u):
				_sd_walls_v4(u, a, w, o0, d, T)
			elif v2:
				_sd_face_v2(u, a, w, o0, d, hw, T)
			var ns: int = 0 if v2 else int(Bal.v("ult/sd_crest_fx", 7.0))
			for i in ns:
				var lat: float = -hw + (float(i) + 0.5) * 2.0 * hw / float(ns)
				var s: Dictionary = u.strip("fx_skadi_wave", o0 + n * lat, {"sc": 1.25, "seg": [1, 3], "loop": true, "fps": 12.0,
					"sx": -1.0 if d.x < -0.2 else 1.0, "o": Vector2(64, 56), "life": T + 0.2})
				a.fx.append(s)
				w.spr.append([s, lat])
		var fp: Vector2 = o0 + d * F
		w.fx[0].b = fp - d * 40.0
		w.fx[1].a = fp - d * 46.0
		w.fx[1].b = fp + d * 8.0
		w.fx[2].a = fp + d * 8.0 + n * hw
		w.fx[2].b = fp + d * 8.0 - n * hw
		for s in w.fx:
			_hold(s)
		for sp in w.spr:
			sp[0].c = fp + n * float(sp[1]) - d * 10.0
		if w.has("walls"):   # 劈开：两堵浪墙从裂口往两侧推开（画面；判定照旧是往前推的矩形）
			_sd_walls_tick(u, a, w, o0, d, n, hw, t, k, col, foam)
		var v3: bool = _sd_v3(u) and w.has("face")
		var rise: float = clampf((t - t0) / 0.18, 0.0, 1.0) if v3 else 1.0   # 立浪：浪面从她身前 0.18 秒内立起
		for wv in w.get("face", []):   # 浪面跟着浪头走
			wv[0].c = fp + n * (-hw) - d * float(wv[1])
			wv[0].sy = -lerpf(0.2, 1.0, rise * rise * (3.0 - 2.0 * rise)) * float(wv[2]) if wv.size() > 2 else wv[0].sy
		if v3 and not w.get("blasted", false) and F >= minf(L, Bal.v("ult/sd_blast_x", 480.0)):
			w["blasted"] = true   # 浪推到尽头（屏边）：浪体炸开成水柱 + 水雾 + 飞溅水珠，浪面 / 水体收掉（只有画面；判定照旧推到 L）
			_sd_blast_v3(u, o0, d, n, hw, fp, PF.vseed(u, o0) + float(w.t0) * 17.0, col)
			for wv in w.face:
				wv[0].max = wv[0].age + 0.12
			w.fx[0].fill = 0.0
			w.fx[1].fill = 0.0
			w["wet_x"] = F
		if v3:
			if not w.get("blasted", false) and t >= float(w.spray_t):   # 浪冠飞沫：像素水珠（不画圆点）
				w.spray_t = t + 0.1
				var j2: int = int(t * 100.0)
				for i in 2:
					var lat4: float = -hw + hw * 2.0 * fposmod(0.23 + 0.41 * float(i) + 0.37 * float(j2), 1.0)
					PF.particles(u, fp + n * lat4 + d * 10.0, 60, "ult_burst_s", [foam, col], 0.0, float(j2) + i * 3.0, 70.0)
		elif not w.has("walls") and t >= float(w.spray_t):   # 浪头飞沫（往前溅）
			w.spray_t = t + 0.07
			var j: int = int(t * 100.0)
			for i in 4:
				var lat2: float = -hw + hw * 2.0 * fposmod(0.17 + 0.29 * float(i) + 0.37 * float(j), 1.0)
				u.shape({"kind": "dots", "c": fp + n * lat2, "r": 40.0, "n": 7, "col": foam, "life": 0.3, "v": d * 520.0 + n * (float(i) - 1.5) * 60.0})
		# 浪头：前沿扫过的敌人各吃一次（下劈打过的只吃 70%，其余吃满这一道）；小怪推 400、精英 240
		# 判定按画面的矩形水体（身后 back 到浪头前沿 +20）：in_band 两端是半圆，原来身后多罩一个半径 hw 的半圆、浪头前方 hw 内也提前挨打
		var full: float = float(w.frac)
		for e in u.in_band(o0 - d * back, fp, hw):
			if w.seg.has(int(e.id)):
				continue
			var rel: Vector2 = e.pos - o0
			var al: float = rel.dot(d)
			if al < -back - 1.0 or al > F + 20.0:
				continue
			w.seg[int(e.id)] = true
			var fr: float = full - (Bal.v("ult/sd_slash", 0.3) if a.sseg.has(int(e.id)) and a.waves.size() == 1 else 0.0)
			_hit(u, a, o, e, fr, {"src": "浪头", "edge": absf(rel.dot(n)) > hw * (1.0 - _edge_w()), "kb": _kb_for(e, d, 400.0, 240.0)})
		if k >= 1.0:
			w.done = true
			for s in w.fx:   # 浪过：水痕 1.5 秒（只有画面）
				u.shapes.erase(s)
				a.fx.erase(s)
			for sp in w.spr:
				u.shapes.erase(sp[0])
				a.fx.erase(sp[0])
			if w.has("walls"):
				_sd_walls_end(u, a, w, o0, d, n, hw, col)
			u.shape({"kind": "band", "a": o0 - d * back, "b": o0 + d * float(w.get("wet_x", L)), "w": hw * 2.0, "col": col.darkened(0.3) if w.has("wet_x") else col,
				"fill": 0.16 if w.has("wet_x") else 0.12, "life": 1.8 if w.has("wet_x") else 1.5, "layer": "back" if w.has("wet_x") else "front"})   # 湿痕
			for i in (0 if w.has("face") or w.has("walls") else 5):
				var lat3: float = -hw * 0.8 + hw * 1.6 * float(i) / 4.0
				u.shape({"kind": "line", "a": o0 + n * lat3 - d * back, "b": o0 + n * lat3 + d * L, "w": 2.0, "col": foam, "life": 1.2})
	if a.surge and not a.surged and all_done:
		a.surged = true   # 涌潮：浪推到终点（屏边）卷成水环再炸一次（打所有浪打过的人里在水环内的，额外 25%）
		var ec: Vector2 = o0 + d * minf(L, 640.0)
		for e in u.in_circle(ec, 200.0):
			_hit(u, a, o, e, 0.25, {"src": "涌潮", "edge": e.pos.distance_to(ec) > 170.0})
		if _sd_v3(u):
			_sd_blast_v3(u, ec, d, n, 180.0, ec, PF.vseed(u, ec) + 77.0, col, 3)
		else:
			u.strip("fx_skadi_surge", ec, {"sc": 2.6})
			_ring(u, ec, 200.0, 40.0, foam, 0.4, 10.0)
	return all_done and (not a.surge or a.surged)


## ---- 斯卡蒂 pixfx（docs/199 §7.10，开关 ult/sd_fx_v2 缺省 1；0 = 程序白沫带 + 浪头帧条一排版）
## 审阅 10-30「浪面连续，浪冠错落」：fx_sd_wave 是三条浪面（浪冠白沫在上、深蓝水体在下）横向拼成一张，整道浪宽从一条里截出（连续不断），
## 前后两层错开（后层换一段、略暗、退后 34），浪冠高低错落；每次按 vseed 挑截取起点 + 镜像。浪推完的水痕不再画 5 条直线
const SD_WAVE := "fx_sd_wave"


static func _sd_v2(u) -> bool:
	return Bal.v("ult/sd_fx_v2", 1.0) > 0.0 and u.fx_ready(SD_WAVE)


## ---- 斯卡蒂新设计（docs/199 §7.12，开关 ult/sd_fx_v3 缺省 1；0 = §7.10 版）。用户 10-30 定：一剑劈出巨浪（身前立起、向前推进横扫，浪冠错落、浪唇连续、带泡沫）
## → 浪推到尽头紧接水爆（浪体在前方炸开成水柱 + 水雾 + 飞溅水珠，先亮后散，地面留湿痕）。水爆 = fx_sd_blast1–4（按 vseed 挑变体 / 镜像 / 错开），
## 水珠 / 水雾 = PF.particles 预烘焙粒子帧条着水色；浪推到 ult/sd_blast_x（480，屏内）就炸、浪面收掉，判定照旧推到 L（1500）
const SD_BLAST := ["fx_sd_blast1", "fx_sd_blast2", "fx_sd_blast3", "fx_sd_blast4"]


## ---- 斯卡蒂「劈开浪潮」（docs/199 §7.13，开关 ult/sd_fx_v4 缺省 1；0 = §7.12 推浪 + 水爆版）。用户 10-30：「我要那种劈开浪潮的感觉」
## 下劈 → 海面沿前方被劈开一道裂口 fx_sd_cleave（近端宽、远端尖，0.22 秒从脚下往前裂出，裂口沿线依次炸起水柱）→
## 两堵水墙（fx_sd_wall1–2）跟着裂口一路立起、拔高、分到两侧停住（摩西分海）→ 最后两墙合拢砸下：沿中线一排大水柱 + 水雾 + 湿痕。
## 只改画面；判定仍是往前推的矩形浪（时序 / 扫向改法列给协调人）
const SD_CLEAVE := "fx_sd_cleave"


static func _sd_v4(u) -> bool:
	return Bal.v("ult/sd_fx_v4", 1.0) > 0.0 and _sd_v3(u) and u.fx_ready(SD_CLEAVE) and u.fx_ready("fx_sd_wall1")


static func _sd_clen(a: Dictionary) -> float:
	return minf(float(a.L), Bal.v("ult/sd_cleave_len", 820.0))


## 一处水柱（水爆贴图从小鼓到位、白亮冷成水蓝）+ 水珠；w1 世界宽，dl 延迟
static func _sd_spout(u, p: Vector2, w1: float, dl: float, sd: float, col: Color, mist := false) -> void:
	var foam: Color = col.lerp(Color.WHITE, 0.6)
	var nm := PF.pick(u, SD_BLAST, sd * 0.29)
	var t: Texture2D = u._strip_tex(nm)
	var tw: float = PF.tex_w(u, nm)
	u.strip(nm, p, {"o": Vector2(t.get_width() * 0.5, t.get_height() * 0.95), "sc": w1 * 0.4 / tw, "sc1": w1 / tw, "scd": 0.22, "sx": -1.0 if PF.h(sd * 7.0) < 0.5 else 1.0,
		"life": 0.8, "fade": 0.45, "delay": dl, "col": Color(0.96, 0.99, 1.03), "col1": Color(col.r * 0.85, col.g * 0.9, col.b, 0.9), "cold": 0.25})   # 起始压暗、快冷（预审报合拢水柱发白）
	PF.particles(u, p - Vector2(0, 30.0), 100, "ult_burst_s", [foam, col], dl + 0.02, sd, w1 * 0.6)
	if mist:
		PF.particles(u, p - Vector2(0, 50.0), 100, "ult_ember", [Color(foam, 0.7)], dl + 0.12, sd + 5.0, w1 * 0.5)


## 劈开：裂口从脚下往前裂出（rev），沿线依次炸起 6 处水柱；冷光一闪
static func _sd_cleave_v4(u, a: Dictionary, o0: Vector2, d: Vector2, n: Vector2, col: Color) -> void:
	var vs: float = PF.vseed(u, o0)
	var Lc: float = _sd_clen(a)
	var t: Texture2D = u._strip_tex(SD_CLEAVE)
	var sx: float = Lc / PF.tex_w(u, SD_CLEAVE)
	var rv: float = 0.22
	u.strip(SD_CLEAVE, o0 + d * 20.0, {"layer": "back", "ang": d.angle(), "o": Vector2(0.0, t.get_height() * 0.47), "sx": sx, "sy": (1.0 if PF.h(vs) < 0.5 else -1.0) * 0.75,
		"rev": rv, "rev0": 0.05, "life": 1.5, "fade": 0.8, "col": Color(1.05, 1.05, 1.1), "col1": Color(0.6, 0.68, 0.78), "cold": 0.35})   # 窄一点、快冷：横向泡沫纹放大后像条纹
	u.g.vfx.stop(Bal.v("ult/sd_part_stop", 0.1), "ult", true)   # 劈下那一下顿住
	u.light(o0 + d * Lc * 0.4, Lc * 0.6, col.lerp(Color.WHITE, 0.4), 0.25)
	for k in 6:
		var x: float = Lc * (k + 0.4 + 0.3 * PF.h(vs + k)) / 6.0
		var sg: float = 1.0 if k % 2 == 0 else -1.0
		_sd_spout(u, o0 + d * x + n * sg * (18.0 + 30.0 * PF.h(vs + k * 3.0)), 120.0 + 70.0 * PF.h(vs + k * 5.0) * (1.0 - 0.5 * x / Lc), rv * x / Lc, vs + k * 2.3, col, k % 2 == 0)


## 两堵水墙（摩西分海，用户 10-31「要有那种摩西劈开大海的力量感」）：fx_sd_wall1–2（一整条浪唇，中间最高、两端收细成水沫）沿裂口方向铺 Lc 长，
## sy 正 = 浪冠朝 +n、负 = 朝 −n；跟着裂口从脚下往前一路立起（rev 0.3 秒），0.25 秒内拔到 2 倍高、分到 ±0.55 hw 停住（墙顶冒水雾、微微起伏），
## 0.85 T 起两墙往中间合拢砸下 → 沿中线一排大水柱 + 水雾 + 顿帧。每侧一堵，变体按哈希
const SD_WALL := ["fx_sd_wall1", "fx_sd_wall2"]


static func _sd_walls_v4(u, a: Dictionary, w: Dictionary, o0: Vector2, d: Vector2, T: float) -> void:
	var Lc: float = _sd_clen(a)
	var vs: float = PF.vseed(u, o0) + float(w.t0) * 31.0
	w["walls"] = []
	if a.get("walled", false):   # 跃浪第二道：只劈开一次（两组水墙叠成一条条横纹）
		return
	a["walled"] = true
	for side in [1.0, -1.0]:
		var nm := PF.pick(u, SD_WALL, vs * 0.4 + side * 1.3)
		var t: Texture2D = u._strip_tex(nm)
		var s: Dictionary = u.strip(nm, o0, {"ang": d.angle(), "o": Vector2(0.0, t.get_height() * 0.3), "sc": Lc * 1.05 / PF.tex_w(u, nm),
			"sy": side * 0.3, "rev": 0.3, "rev0": 0.05, "life": T + 0.3, "fade": 0.15, "col": Color(0.86, 0.9, 0.95, 1.0)})
		a.fx.append(s)
		w.walls.append([s, side, 0.0, -30.0, 1.0])


static func _sd_walls_tick(u, a: Dictionary, w: Dictionary, o0: Vector2, d: Vector2, n: Vector2, hw: float, t: float, k: float, col: Color, foam: Color) -> void:
	if w.walls.is_empty():
		w.fx[0].fill = 0.0
		w.fx[1].fill = 0.0
		return
	var Lc: float = _sd_clen(a)
	var op: float = clampf(k / 0.25, 0.0, 1.0)
	var hold: float = hw * 0.55 * (1.0 - pow(1.0 - op, 3.0))   # 分开：前 25% 猛地分到两侧
	var cl: float = clampf((k - 0.85) / 0.15, 0.0, 1.0)   # 合拢：最后 15% 砸回中间
	var off: float = lerpf(hold, 20.0, cl * cl) + sin(t * 9.0) * 5.0 * (1.0 - cl)
	var rise: float = clampf((t - float(w.t0)) / 0.25, 0.0, 1.0)
	var hk: float = lerpf(0.3, 2.0, rise * rise * (3.0 - 2.0 * rise)) * lerpf(1.0, 0.6, cl)
	for wl in w.walls:
		var side: float = wl[1]
		wl[0].c = o0 + d * float(wl[3]) + n * side * off
		wl[0].sy = side * hk
	w.fx[0].fill = 0.0
	w.fx[1].fill = 0.0   # 不画矩形湿底（像素扫描线画出来是一条条横纹，预审报拼接）；中间露出的海底交给裂口贴图
	if t >= float(w.get("wspray_t", 0.0)) and cl < 1.0:   # 墙顶水雾往上冒 + 飞沫
		w["wspray_t"] = t + 0.08
		var j: int = int(t * 100.0)
		for side in [1.0, -1.0]:
			var x: float = Lc * fposmod(0.21 + 0.37 * float(j) + 0.5 * side, 1.0) * minf(1.0, (t - float(w.t0)) / 0.3)
			var p: Vector2 = o0 + d * x + n * side * (off + 6.0)
			PF.particles(u, p, 60, "ult_ember", [Color(foam, 0.75)], 0.0, float(j) + side * 3.0, 90.0)
			if j % 2 == 0:
				PF.particles(u, p, 60, "ult_burst_s", [foam, col], 0.0, float(j) + side * 5.0, 60.0)


## 两墙合拢砸下：沿中线一排大水柱（6 处，变体 / 大小 / 时刻错开）+ 水雾 + 冷光 + 顿帧
static func _sd_walls_end(u, a: Dictionary, w: Dictionary, o0: Vector2, d: Vector2, n: Vector2, hw: float, col: Color) -> void:
	var vs: float = PF.vseed(u, o0) + float(w.t0) * 13.0
	var Lc: float = _sd_clen(a)
	w["wet_x"] = Lc   # 湿痕只留在劈开的那一段
	if w.walls.is_empty():
		return
	u.g.vfx.stop(Bal.v("ult/sd_crash_stop", 0.08), "ult", true)
	u.light(o0 + d * Lc * 0.5, Lc * 0.6, col.lerp(Color.WHITE, 0.5), 0.3)
	for q in 6:
		var hh: float = PF.h(vs + q * 2.1)
		_sd_spout(u, o0 + d * Lc * (q + 0.2 + 0.6 * hh) / 6.0 + n * (hh - 0.5) * 60.0, 220.0 + 90.0 * PF.h(hh * 3.0), 0.03 * q, vs + q * 1.7, col, q % 2 == 0)


static func _sd_v3(u) -> bool:
	return Bal.v("ult/sd_fx_v3", 1.0) > 0.0 and _sd_v2(u) and u.fx_ready(SD_BLAST[0])


## 水爆：沿浪线 m 处水柱（变体 / 镜像 / 大小 / 时刻按哈希错开）从小鼓到大、白亮冷成水蓝、淡出；每处水珠 + 上飘水雾 + 湿痕；整排一下冷光 + 短顿帧
static func _sd_blast_v3(u, c0: Vector2, d: Vector2, n: Vector2, hw: float, fp: Vector2, vs: float, col: Color, m := 5) -> void:
	u.g.vfx.stop(Bal.v("ult/sd_hitstop", 0.06), "ult", true)
	var foam: Color = col.lerp(Color.WHITE, 0.6)
	u.light(fp, hw * 1.3, foam, 0.3)
	for i in m:
		var hh: float = PF.h(vs + i * 2.7)
		var lat: float = -hw * 0.85 + hw * 1.7 * (i + 0.2 + 0.6 * hh) / m if m > 1 else 0.0
		var p: Vector2 = fp + n * lat + d * (20.0 + 50.0 * PF.h(hh * 9.0))
		var nm := PF.pick(u, SD_BLAST, vs * 0.29 + i * 1.7)
		var t: Texture2D = u._strip_tex(nm)
		var tw: float = PF.tex_w(u, nm)
		var w1: float = (180.0 + 80.0 * PF.h(hh * 5.0)) * (hw * 2.0 / 920.0 if m < 5 else 1.0)
		var dl: float = 0.05 * PF.h(hh * 3.0) + 0.03 * i
		u.strip(nm, p, {"o": Vector2(t.get_width() * 0.5, t.get_height() * 0.95), "sc": w1 * 0.45 / tw, "sc1": w1 / tw, "scd": 0.28, "sx": -1.0 if PF.h(hh * 7.0) < 0.5 else 1.0,
			"life": 0.95, "fade": 0.55, "delay": dl, "col": Color(1.12, 1.12, 1.16), "col1": Color(col.r * 0.9, col.g * 0.95, col.b, 0.9), "cold": 0.4})
		PF.particles(u, p - Vector2(0, 40.0), 200, "ult_burst_s" if i % 2 == 1 else "ult_burst", [foam, col], dl + 0.02, vs + i * 3.0, 150.0 if i % 2 == 1 else 240.0)
		if i % 2 == 0:
			PF.particles(u, p - Vector2(0, 60.0), 100, "ult_ember", [Color(foam, 0.7)], dl + 0.15, vs + i * 5.0, 120.0)   # 水雾：慢、上飘
		u.shape({"kind": "circle", "c": p, "r": w1 * 0.4, "col": col.darkened(0.45), "fill": 0.28, "life": 1.8, "delay": dl + 0.1, "layer": "back"})   # 湿痕


static func _sd_face_v2(u, a: Dictionary, w: Dictionary, o0: Vector2, d: Vector2, hw: float, T: float) -> void:
	var t: Texture2D = u._strip_tex(SD_WAVE)
	var kk: float = PF.tex_w(u, SD_WAVE) / t.get_width()
	var bw: float = t.get_width() / 3.0   # 三条浪面横向拼在一张里，每条 bw 宽，截取不跨条
	var uw: float = 2.0 * hw / kk
	var sc: float = 1.0
	if uw > bw:   # 浪比一条贴图宽：整体放大铺满
		sc = uw / bw
		uw = bw
	var vs: float = PF.vseed(u, o0) + float(w.t0) * 31.0
	var fh: float = t.get_height()
	w["face"] = []
	var nl: int = 3 if _sd_v3(u) else 2
	for l in nl:   # l 0 = 后层（略暗、退后），1 = 前层；v3 多一层中层（再退后、更淡、高度 0.8），浪冠三层错落
		var lay: int = [0, 1, 2][l] if nl == 3 else l
		var hk: float = [1.0, 1.0, 0.8][lay]
		var s: Dictionary = u.strip(SD_WAVE, o0, {"ang": d.orthogonal().angle(), "o": Vector2(0.0, fh * 0.12), "sc": sc, "sx": 1.0, "sy": -hk,
			"ux": floorf(int(PF.h(vs * 0.7 + l * 3.1) * 3.0) % 3 * bw + PF.h(vs + l * 5.3) * maxf(0.0, bw - uw)), "uw": uw, "life": T + 0.2, "fade": 0.18,
			"col": [Color(0.66, 0.74, 0.84, 0.85), Color(0.84, 0.88, 0.93, 1.0), Color(0.6, 0.7, 0.82, 0.6)][lay]})   # 白沫压暗（预审 10-30 报浪冠发白）
		a.fx.append(s)
		w.face.append([s, [34.0, 0.0, 70.0][lay], hk])


# ================================================================ 歌蕾蒂娅（§4.7）：海渊漩涡把半径 560 的敌人拖向中心 → 收拢一砸 → 停住 → 潮水从中心爆开
## 10-30 用户「顿挫感不够」返工：三拍节奏——
##   ① 旋转收拢 ult/gl_spin（0.65 秒，越转越快，伤害全标 pre）；
##   ② 收拢到中心那一刻 = 冲击帧（这次终结技第一下真正掉血：ult/gl_crush 30%）+ 轻震，之后 ult/gl_hold（0.2 秒）一瞬静止：漩涡停转、整团收成中心一个亮点，敌人钉在原地；
##   ③ 爆开：剩下的 52% + 加大的击飞（小怪 ult/gl_kb 520、精英 260），水柱 / 水环向四周放射。
## 瞬发型时长上限 1.2 秒（含瞄准慢放 0.125）：0.65 + 0.2 = 0.85 秒处最后一下伤害
static func _gl_start(u, o, c: Vector2) -> Dictionary:
	var rt := _route(o)
	var col: Color = u._col(o)
	var R: float = aim_r("gladiia")
	var DR: float = Bal.v("ult/gl_drag_r", 520.0) + (60.0 if rt == "brute" else 0.0)   # 10-30 对齐表 560 → 520（屏内小怪 55.6% → 约 50%）；怒海仍比缺省大 60（原 620 对 560）
	var pulled: Array = []
	for e in u.in_circle(c, DR):
		if e.boss:
			continue
		var off: Vector2 = e.pos - c
		var d0: float = off.length()
		# 小怪拖到中心附近（按原距离留一圈，不叠成一点）；精英只拖 160（怒海：拉力更强 +25%）
		var dt0: float = maxf(36.0, d0 * 0.16 + 30.0) if not (e.elite or e.get("part", false)) else maxf(60.0, d0 - 160.0 * (1.25 if rt == "brute" else 1.0))
		pulled.append({"e": e, "d0": d0, "d1": minf(d0, dt0), "a0": off.angle(), "sw": 0.0})
	o.play_vis_anim("attack")
	var a := {"c": c, "R": R, "DR": DR, "T": Bal.v("ult/gl_spin", 0.65), "H": Bal.v("ult/gl_hold", 0.2), "pulled": pulled, "tick": 0, "rot": 0.0,
		"crushed": false, "burst": false, "cseg": {}, "arms": [], "shelter": rt == "shield", "ring_t": 0.0, "fx": [], "no_ring": true}
	_keep(u, a, {"kind": "circle", "c": c, "r": DR, "col": col.darkened(0.5), "fill": 0.16, "life": 3.0})
	_keep(u, a, {"kind": "ring", "c": c, "r": R, "w": 3.0, "col": col.lerp(Color.WHITE, 0.3), "life": 3.0})
	for j in 4:   # 四条旋臂，每条 10 节（外细内粗、越往里越亮）
		var arm: Array = []
		for i in 10:
			arm.append(_keep(u, a, {"kind": "line", "a": c, "b": c, "w": 3.0 + 0.9 * float(i), "col": col.lerp(Color.WHITE, 0.25 + 0.06 * float(i)), "life": 3.0}))
		a.arms.append(arm)
	if _gl_v2(u):   # 漩涡 v2：程序画的四条旋臂换成整张漩涡贴图，外层 + 内层（内圈转得更快）
		for arm in a.arms:
			for s in arm:
				u.shapes.erase(s)
		var rr: float = PF.tex_w(u, GL_VORTEX) * 0.5
		a["vo"] = u.strip(GL_VORTEX, c, {"layer": "back", "sc": DR / rr, "life": 3.0, "col": Color(1, 1, 1, 0.55)})
		a["vi"] = u.strip(GL_VORTEX, c, {"layer": "back", "sc": DR * 0.5 / rr, "ang": 1.3, "life": 3.0, "col": Color(1.1, 1.15, 1.15, 0.7)})
		a["rr"] = rr
	a.fx.append(u.strip("fx_gladiia_tornado_open", c, {"sc": 2.6, "o": Vector2(64, 118)}))
	a.fx.append(u.strip("fx_gladiia_tornado_loop", c, {"sc": 2.6, "o": Vector2(64, 118), "loop": true, "delay": 0.3, "life": 2.0}))
	return a


static func _gl_step(u, a: Dictionary, o, dt: float) -> bool:
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	var DR: float = a.DR
	var T: float = a.T
	var H: float = a.H
	var col: Color = u._col(o)
	var er: float = R * (1.0 - _edge_w())
	if not a.crushed:
		var k: float = clampf(t / T, 0.0, 1.0)
		var w: float = lerpf(2.5, 13.0, k * k)   # 越转越快
		a.rot = float(a.rot) + w * dt
		# 拖拽：半径按 ease 收拢，同时绕中心转（越靠里转得越快）
		var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
		for p in a.pulled:
			var e: Dictionary = p.e
			if e.dead:
				continue
			var dd: float = lerpf(float(p.d0), float(p.d1), ke)
			p.sw = float(p.sw) + w * dt * clampf(1.2 - dd / DR, 0.25, 1.0) * (0.35 if e.elite else 1.0)
			u.g.enemies_sys.nudge(e, c + Vector2.from_angle(float(p.a0) + float(p.sw)) * dd - e.pos)
		var shrink: float = lerpf(1.0, 0.55, k * k)   # 旋臂跟着往里收
		for j in a.arms.size():
			var arm: Array = a.arms[j]
			for i in arm.size():
				var r0: float = DR * shrink * (1.0 - float(i) / 10.0)
				var r1: float = DR * shrink * (1.0 - float(i + 1) / 10.0)
				var base: float = float(a.rot) + TAU * float(j) / 4.0
				arm[i].a = c + Vector2.from_angle(base + 0.36 * float(i)) * maxf(20.0, r0)
				arm[i].b = c + Vector2.from_angle(base + 0.36 * float(i + 1)) * maxf(20.0, r1)
		for s in a.fx:
			_hold(s)
		if a.has("vo"):   # 凝聚：越转越快、整团往中心收到 0.2，越收越亮越实；内层再快 0.8 倍
			var kc: float = k * k * (3.0 - 2.0 * k)
			var sk: float = lerpf(1.0, 0.2, kc)
			a.vo.ang = -float(a.rot)
			a.vo.sc = DR * sk / float(a.rr)
			a.vo.col = Color(1.0 + 0.4 * kc, 1.0 + 0.4 * kc, 1.0 + 0.4 * kc, lerpf(0.55, 0.95, kc))
			a.vi.ang = 1.3 - float(a.rot) * 1.8
			a.vi.sc = DR * 0.5 * sk / float(a.rr)
			a.vi.col = Color(1.1 + 0.5 * kc, 1.15 + 0.5 * kc, 1.15 + 0.5 * kc, lerpf(0.7, 1.0, kc))
			if int(t * 60.0) % 3 == 0:   # 外圈的水沫往里吸
				var dq := Vector2.from_angle(float(a.rot) * 1.7 + t * 9.0)
				u.grain("mote_in", c + dq * DR * 0.9, -dq, Color(0.8, 1.0, 1.0), 3)
		var foam: Color = col.lerp(Color.WHITE, 0.45)
		for j in a.arms.size():   # 旋臂上甩出的水沫（沿切向）+ 中心越转越亮
			var arm2: Array = a.arms[j]
			var sg: Dictionary = arm2[(int(t * 60.0) + j * 3) % arm2.size()]
			u.grain("water", sg.b, (sg.b - sg.a).normalized(), foam, 2)
		if int(t * 60.0) % 8 == 0:
			u.light(c, lerpf(120.0, 300.0, k), col, 0.14)
		if t >= float(a.ring_t):   # 向内收的水环
			a.ring_t = t + 0.13
			_ring(u, c, 40.0, DR, col.lerp(Color.WHITE, 0.45), 0.26, 4.0)
			u.shape({"kind": "dots", "c": c, "r": DR * 0.9, "n": 18, "col": col.lerp(Color.WHITE, 0.6), "life": 0.26})
		# 旋转期：分 ult/gl_ticks 跳，合计 ult/gl_spin_frac（18%），全是铺垫（pre），冲击帧留给收拢那一下
		var nt: int = int(Bal.v("ult/gl_ticks", 5.0))
		while int(a.tick) < nt and t >= T * float(int(a.tick) + 1) / float(nt + 1):
			a.tick = int(a.tick) + 1
			for e in u.in_circle(c, R):
				_hit(u, a, o, e, Bal.v("ult/gl_spin_frac", 0.18) / float(nt), {"src": "漩涡", "pre": true, "edge": e.pos.distance_to(c) > er})
		if t >= T:
			# ② 收拢一砸：冲击帧（第一下非 pre 的掉血）+ 轻震；漩涡停转，整团收成中心一个亮点
			a.crushed = true
			_fade(u, a, 0.08)
			for e in u.in_circle(c, R):
				a.cseg[int(e.id)] = true
				_hit(u, a, o, e, Bal.v("ult/gl_crush", 0.3), {"src": "收拢", "edge": e.pos.distance_to(c) > er, "stun": H + 0.1, "pre": true})   # pre：冲击帧（顿帧 + 慢放）留给爆开那一刻（用户 10-30）
			u.shake(Bal.v("ult/gl_shake", 7.0), 0.3)
			_ring(u, c, 30.0, 220.0, col.lerp(Color.WHITE, 0.5), 0.12, 10.0)
			u.light(c, 260.0, col, H + 0.1)
			for i in 10:   # 收进来的最后一圈水沫
				var dq := Vector2.from_angle(float(i) * TAU / 10.0)
				u.grain("water", c + dq * 150.0, -dq, col.lerp(Color.WHITE, 0.5), 3)
			a["pt"] = _keep(u, a, {"kind": "circle", "c": c, "r": 30.0, "col": col.lerp(Color.WHITE, 0.6), "fill": 0.95, "life": H + 0.3})
			a["pg"] = _keep(u, a, {"kind": "circle", "c": c, "r": 70.0, "col": col.lerp(Color.WHITE, 0.5), "fill": 0.55, "life": H + 0.3})
			a["pr"] = _keep(u, a, {"kind": "ring", "c": c, "r": 120.0, "w": 4.0, "col": col.lerp(Color.WHITE, 0.6), "life": H + 0.3})
			o.play_vis_anim("attack")
		return false
	if not a.burst:
		# 一瞬静止：亮点往里收、越收越亮；敌人钉在原地（收拢那下给了 stun）
		var kh: float = clampf((t - T) / maxf(0.01, H), 0.0, 1.0)
		if a.has("vo"):   # 凝住：整团再收一点、越来越亮（爆开前一拍）
			a.vo.sc = DR * lerpf(0.2, 0.14, kh) / float(a.rr)
			a.vi.sc = DR * 0.5 * lerpf(0.2, 0.14, kh) / float(a.rr)
			a.vo.col = Color(1.4 + 0.3 * kh, 1.4 + 0.3 * kh, 1.4 + 0.3 * kh, 1.0)
		a.pt.r = lerpf(30.0, 12.0, kh)
		a.pg.r = lerpf(70.0, 26.0, kh)
		a.pr.r = lerpf(120.0, 30.0, kh)
		for s in [a.pt, a.pg, a.pr]:
			s.age = 0.0
		if t < T + H:
			return false
		# ③ 爆开：剩下的份额 + 加大的击飞，水柱 / 水环放射
		a.burst = true
		_fade(u, a, 0.05)
		if a.has("vo"):   # 凝住的漩涡被潮水冲开：从当前大小放大淡出 + 更华丽的爆开（用户 10-30）
			for key in ["vo", "vi"]:
				var s: Dictionary = a[key]
				u.shapes.erase(s)
				u.strip(GL_VORTEX, c, {"layer": "back", "sc": float(s.sc), "sc1": float(s.sc) * 1.6, "scd": 0.25, "ang": float(s.ang), "life": 0.3, "fade": 0.3, "col": s.col})
			_gl_burst_v2(u, c, R, col)
		var bf: float = maxf(0.0, Bal.v("ult/gl_burst", 0.52))
		var kb: float = Bal.v("ult/gl_kb", 520.0)
		for e in u.in_circle(c, R):
			var off: Vector2 = e.pos - c
			var dv: Vector2 = off.normalized() if off.length() > 1.0 else Vector2.from_angle(float(int(e.id)) * GA)
			var fr: float = bf + (0.0 if a.cseg.has(int(e.id)) else Bal.v("ult/gl_crush", 0.3))   # 收拢那下没罩到的（后进圈）这下补上
			_hit(u, a, o, e, fr, {"src": "潮涌", "edge": off.length() > er, "kb": _kb_for(e, dv, kb, kb * 0.5)})
		u.shake(5.0, 0.3)
		var v2: bool = a.has("vo")   # v2：不画卡通水花 / 浪涌帧条和整片淡圆，交给 2 px 水色颗粒（用户 10-30「对齐 Noita 精细像素粒子风」）
		u.strip("fx_gladiia_tornado_close", c, {"sc": 2.6, "o": Vector2(64, 118)})
		if not v2:
			u.strip("fx_skadi_surge", c, {"sc": 5.2})
			u.shape({"kind": "circle", "c": c, "r": R, "col": col.lerp(Color.WHITE, 0.3), "fill": 0.28, "life": 0.28})
		u.shape({"kind": "circle", "c": c, "r": 90.0, "col": col.lerp(Color.WHITE, 0.6), "fill": 0.95, "life": 0.1})
		_ring(u, c, R, 40.0, col.lerp(Color.WHITE, 0.5), 0.45, 18.0)
		u.light(c, R, col, 0.45)
		u.debris(c, col, 3)
		_ring(u, c, R * 0.85, 30.0, col.lerp(Color.WHITE, 0.5), 0.45, 10.0, 0.05)
		_ring(u, c, R * 0.6, 20.0, col.lerp(Color.WHITE, 0.3), 0.4, 6.0, 0.1)
		# 水柱：12 道放射的水刃往外冲 + 两圈水花
		var foam: Color = col.lerp(Color.WHITE, 0.7)
		for i in 12:
			var dv2 := Vector2.from_angle(float(i) * TAU / 12.0 + 0.13)
			if not v2:
				u.shape({"kind": "blade", "a": c + dv2 * 50.0, "b": c + dv2 * 230.0, "w": 14.0, "col": foam, "glow": col, "grow": 0.05, "life": 0.34, "v": dv2 * 820.0})
			for m in 3:   # 水柱沿线的水沫（颗粒拼出放射的水柱）
				u.grain("water", c + dv2 * R * (0.25 + 0.3 * float(m)), dv2, foam, 4)
			if i % 3 == 0:
				u.debris(c + dv2 * R * 0.6, col, 1)
		_spray(u, c, 16, 60.0, 1000.0, foam, 0.45)
		for i in (0 if v2 else 10):
			u.strip("fx_water_splash", c + Vector2.from_angle(float(i) * TAU / 10.0 + 0.3) * R * 0.62, {"sc": 1.8, "delay": 0.03 * float(i % 3)})
		for i in (0 if v2 else 8):
			u.strip("fx_water_splash", c + Vector2.from_angle(float(i) * TAU / 8.0) * R * 0.32, {"sc": 1.4, "delay": 0.02 * float(i % 2)})
		if a.shelter:   # 深海的庇护：队长获得 10% 最大生命的护盾（护盾层 API 只有格数，这里先折成回复 10%）
			u.g.combat.heal(u.g.max_hp * 0.1, "终结技", "gladiia")
		o.play_vis_anim("attack")
		return false
	return t >= T + H + 0.15


## ---------------- 歌蕾蒂娅 v2（ult/gl_fx_v2，缺省 1；0 = 程序画四条旋臂版。pixfx，docs/199 §7.8）
## pixgen 整张漩涡（fx_gl_vortex，中心暗）两层：外层按 a.rot 转、内层 1.8 倍更快，跟着收拢缩小；收拢一砸后停顿那一拍不再更新 = 凝住；
## 爆开时从当前大小放大淡出。拖拽 / 判定 / 时序不动
const GL_VORTEX := "fx_gl_vortex"


## 爆开：白芯三连闪 → 两波水色像素粒子（白沫 / 浅青 / 青 / 深青）迸开扩散 + 一圈 9 团水花爆 + 碎裂水环三道 + 大灯
static func _gl_burst_v2(u, c: Vector2, R: float, col: Color) -> void:
	var vs: float = PF.vseed(u, c)
	var cols := [Color(0.85, 1.0, 1.0), Color(0.5, 0.9, 0.95), Color(0.3, 0.75, 0.85), Color(0.7, 0.95, 1.0)]
	for m in 3:
		u.shape({"kind": "circle", "c": c, "r": 60.0 + 40.0 * m, "col": Color(0.9, 1.0, 1.0), "fill": 0.9 - 0.25 * m, "life": 0.06, "delay": 0.05 * m})
	PF.particles(u, c, 420, "ult_burst", cols, 0.0, vs)   # 2 px 水色颗粒迸开扩散
	PF.particles(u, c, 200, "ult_burst_s", cols, 0.08, vs + 3.0)
	PF.particles(u, c, 80, "ult_ember", [Color(0.7, 0.95, 1.0)], 0.12, vs + 5.0)
	for q in 9:
		var hq: float = PF.h(q + vs)
		var p: Vector2 = c + Vector2.from_angle(TAU * (q + hq) / 9.0) * R * (0.45 + 0.3 * hq)
		u.shape({"kind": "circle", "c": p, "r": 26.0, "col": Color(0.9, 1.0, 1.0), "fill": 0.9, "life": 0.06, "delay": 0.06 + 0.03 * (q % 3)})
		PF.particles(u, p, 34, "ult_burst_s", cols, 0.06 + 0.03 * (q % 3), vs + q * 5.0)
		u.grain("water", p, Vector2.UP, Color(0.85, 1.0, 1.0), 6)
	for m in 3:
		u.shape({"kind": "ring", "c": c, "r": R * (1.0 - 0.18 * m), "r1": 40.0, "w": 12.0 - 3.0 * m, "col": Color(0.85, 1.0, 1.0).lerp(col, 0.3 * m), "life": 0.55, "delay": 0.04 * m})
	u.light(c, R * 1.1, Color(0.5, 0.95, 1.0), 0.6)


static func _gl_v2(u) -> bool:
	return Bal.v("ult/gl_fx_v2", 1.0) > 0.0 and u.fx_ready(GL_VORTEX)


# ================================================================ 安洁莉娜（§4.8）：重力奇点把圈内小怪吸起悬空 → 停半拍 → 全部砸向地面

## 吸起时往奇点收拢（ult/an_pull 0.3：距离 × 0.7），砸地按砸下那一刻的位置判外缘
static func _an_start(u, o, c: Vector2) -> Dictionary:
	var rt := _route(o)
	var R: float = aim_r("angelina")
	var col: Color = u._col(o)
	var lift: Array = []
	var bosses: Array = []
	for e in u.in_circle(c, R):
		var off: Vector2 = e.pos - c
		if e.boss:
			u.g.enemies_sys.add_cc(e, -INF, 1.5)   # Boss 不吸起，只减速 1.5 秒（吸起 / 砸地照打）
			bosses.append(e)
			continue
		lift.append({"e": e, "d0": off.length(), "a0": off.angle(), "el": e.elite or e.get("part", false)})
		u.g.enemies_sys.add_cc(e, 1.5 if (e.elite or e.get("part", false)) else 1.2, -INF, "airborne")
	o.play_vis_anim("attack")
	var a := {"c": c, "R": R, "lift": lift, "bosses": bosses, "TL": Bal.v("ult/an_lift", 0.6), "TH": Bal.v("ult/an_hold", 0.3), "lifted": false, "slams": 0,
		"nslam": 2 if rt == "pull" else 1, "tide": rt == "lock", "tide_t": 0.0, "ring_t": 0.0, "streak_t": 0.0, "fx": []}
	a["core"] = _keep(u, a, {"kind": "circle", "c": c, "r": 30.0, "col": Color(0.1, 0.02, 0.16), "fill": 0.9, "life": 3.0})
	a["halo"] = _keep(u, a, {"kind": "ring", "c": c, "r": 60.0, "w": 5.0, "col": col.lerp(Color.WHITE, 0.4), "life": 3.0})
	_keep(u, a, {"kind": "circle", "c": c, "r": R, "col": Color(0.25, 0.08, 0.35), "fill": 0.14, "life": 3.0})
	_keep(u, a, {"kind": "ring", "c": c, "r": R, "w": 2.5, "col": col, "life": 3.0})
	var ks: float = R / 470.0   # 帧条按 470 时的比例跟着半径缩放
	if _an_v2(u):   # 奇点：Codex 第二批重力核心关键帧（fx_an_core），代码持续旋转、吸起期间缩小变亮
		a["core"] = u.strip("fx_an_core", c, {"sc": 0.8 * ks, "life": 3.0, "col": Color(1.0, 1.0, 1.0, 0.9)})
		a.fx.append(a.core)
	a.fx.append(u.strip("fx_angelina_well_back", c, {"sc": 3.2 * ks, "layer": "back", "loop": true, "life": 3.0}))
	a.fx.append(u.strip("fx_angelina_well_front", c, {"sc": 1.6 * ks, "loop": true, "life": 3.0}))
	return a


static func _an_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var c: Vector2 = a.c
	_an_core_tick(a, float(a.t), 0.45)
	var R: float = a.R
	var TL: float = a.TL
	var TH: float = a.TH
	var col: Color = u._col(o)
	var g = u.g
	var ts: float = TL + TH   # 第一次砸地的时刻
	var tb: float = 0.32      # 三重引力：弹起再砸的间隔
	var nslam: int = int(a.nslam)
	if not a.lifted and t >= 0.08:
		a.lifted = true   # 吸起：10%（铺垫）
		for p in a.lift:
			_hit(u, a, o, p.e, Bal.v("ult/an_lift_frac", 0.1), {"src": "奇点", "pre": true, "edge": float(p.d0) > R * (1.0 - _edge_w())})
		for e in a.bosses:
			_hit(u, a, o, e, Bal.v("ult/an_lift_frac", 0.1), {"src": "奇点", "pre": true})
	# 悬浮：收拢 + 缓慢绕奇点转 + 抬高（精英一直悬到 1.5 秒）
	var pull: float = Bal.v("ult/an_pull", 0.3)
	for p in a.lift:
		var e: Dictionary = p.e
		if e.dead:
			continue
		var el: bool = p.el
		var k: float = clampf(t / TL, 0.0, 1.0)
		var ke: float = 1.0 - (1.0 - k) * (1.0 - k)
		var dd: float = float(p.d0) * (1.0 - pull * ke)
		var h := 0.0
		if el:
			h = (40.0 * ke + 4.0 * sin(t * 9.0)) if t < 1.5 else 0.0
		else:
			var sl: int = int(a.slams)
			if sl == 0:
				h = 70.0 * ke + 5.0 * sin(t * 10.0 + float(p.a0))
			elif sl < nslam:
				var kb2: float = clampf((t - ts - tb * float(sl - 1)) / tb, 0.0, 1.0)
				h = sin(kb2 * PI) * 45.0   # 弹起
		g.enemies_sys.nudge(e, c + Vector2.from_angle(float(p.a0) + 0.8 * ke) * dd - e.pos)
		g.enemies_sys.set_air(e, h, true)
	# 奇点：核心变大、引力环往里收、碎屑往里拉
	var kc: float = clampf(t / ts, 0.0, 1.0)
	if int(a.slams) == 0:
		a.core.r = lerpf(30.0, 90.0, kc)
		a.halo.r = lerpf(60.0, 120.0, kc) + 6.0 * sin(t * 30.0)
		if t >= float(a.ring_t):
			a.ring_t = t + 0.14
			_ring(u, c, 60.0, R, col.lerp(Color.WHITE, 0.3), 0.36, 3.0)
		if t >= float(a.streak_t):
			a.streak_t = t + 0.05
			var j: int = int(t * 60.0)
			for i in 4:
				var ang: float = float(j * 4 + i) * GA
				var p0: Vector2 = c + Vector2.from_angle(ang) * R * 0.95
				var dv: Vector2 = (c - p0).normalized()
				u.shape({"kind": "line", "a": p0, "b": p0 + dv * 46.0, "w": 2.0, "col": col.lerp(Color.WHITE, 0.5), "life": 0.3, "v": dv * 900.0})
	for s in a.fx:
		_hold(s)
	# 砸地：90%（三重引力：60% + 弹起再砸 50%，按 §4.8 草案）；砸下那一刻的位置判外缘
	while int(a.slams) < nslam and t >= ts + tb * float(int(a.slams)):
		var si: int = int(a.slams)
		a.slams = si + 1
		var fr: float = Bal.v("ult/an_slam", 0.9) if nslam == 1 else (0.6 if si == 0 else 0.5)
		for p in a.lift:
			var e: Dictionary = p.e
			if e.dead:
				continue
			if not p.el:
				g.enemies_sys.set_air(e, 0.0, true)
			var de: float = e.pos.distance_to(c)
			_hit(u, a, o, e, fr, {"src": "砸地", "edge": de > R * (1.0 - _edge_w()), "stun": 0.5 if not p.el else 0.0})
			if not e.dead:
				e["wl_t"] = g.t + 3.0   # 砸地后 3 秒击退 +50%（延续天赋「加速力场」，enemies.kb_taken 读）
				e["wl_kb"] = maxf(float(e.get("wl_kb", 1.0)) if float(e.get("wl_t", 0.0)) > g.t else 1.0, 1.5)
		for e in a.bosses:
			_hit(u, a, o, e, fr, {"src": "砸地", "stun": 0.3})
		var dust := Color(0.6, 0.5, 0.68)
		if not _an_v2(u):   # v2 不画旧的亮白收拢帧条（预审报砸地发白）
			u.strip("fx_angelina_well_close", c, {"sc": 3.6 * R / 470.0})
		if _an_v2(u):   # v2 砸地：顿帧 + 砸坑（fx_an_crater）+ 紫灰尘环（fx_an_ring）推到 R + 紫色粒子 + 两拍隆起
			var vs3: float = PF.vseed(u, c) + float(si)
			u.g.vfx.stop(Bal.v("ult/an_hitstop", 0.1), "ult", true)
			if u.fx_ready("fx_an_crater"):
				var cr: float = PF.tex_w(u, "fx_an_crater") * 0.5
				u.strip("fx_an_crater", c, {"layer": "back", "sc": R * 0.3 / cr, "sc1": R * 0.42 / cr, "scd": 0.1, "ang": PF.h(vs3) * TAU, "sx": -1.0 if PF.h(vs3 + 1.0) < 0.5 else 1.0,
					"life": 1.8, "fade": 0.7, "col": Color(0.95, 0.9, 1.0), "col1": Color(0.55, 0.5, 0.6), "cold": 0.6})
			PF.particles(u, c, 300, "ult_burst", [Color(0.6, 0.45, 0.85)], 0.0, vs3, R * 0.85)   # 尘环贴图预审报重复拼接，改两层紫灰粒子
			PF.particles(u, c, 300, "ult_burst", [Color(0.62, 0.58, 0.7)], 0.06, vs3 + 5.0, R * 0.6)
			PF.heave(u, c, R * 0.45, vs3 + 2.0)
			PF.heave(u, c, R * 0.85, vs3 + 3.0, 0.18)
			if a.has("core"):
				u.shapes.erase(a.core)
		else:
			_ring(u, c, R, 50.0, dust, 0.55, 20.0)
			_ring(u, c, R * 0.6, 40.0, col.lerp(Color.WHITE, 0.6), 0.35, 8.0)
			u.shape({"kind": "circle", "c": c, "r": R, "col": col.lerp(Color.WHITE, 0.5), "fill": 0.3, "life": 0.22})
		_spray(u, c, 16, R * 0.35, 700.0, dust.lerp(Color.WHITE, 0.3), 0.45, 0.2 * float(si))
		var nd := 0
		for p in a.lift:   # 每只砸下的敌人脚下一圈尘
			if nd >= 36:
				break
			var e2: Dictionary = p.e
			if not p.el:
				_ring(u, e2.pos, 34.0, 6.0, dust, 0.3, 4.0)
				nd += 1
		if si == 0:
			_fade(u, a, 0.2)
		o.screen_shake(0.8)
		o.play_vis_anim("attack")
	if a.tide and int(a.slams) > 0 and t < 1.5 and t >= float(a.tide_t):
		a.tide_t = t + 0.3   # 潮汐锁：精英悬浮期间每 0.3 秒 3%
		for p in a.lift:
			if p.el and not p.e.dead:
				_hit(u, a, o, p.e, 0.03, {"src": "潮汐锁"})
	if t >= 1.5:   # 精英落地
		for p in a.lift:
			if p.el and not p.e.dead:
				g.enemies_sys.set_air(p.e, 0.0, true)
	var end_t: float = ts + tb * float(nslam - 1) + 0.12
	if bool(a.tide):
		end_t = maxf(end_t, 1.5)
	var has_el := false
	for p in a.lift:
		has_el = has_el or bool(p.el)
	if has_el:
		end_t = maxf(end_t, 1.5)
	return t >= end_t


## 安洁莉娜 v2（ult/an_fx_v2，缺省 1；pixfx，docs/199 §7.8 第一批）：奇点 = Codex 重力核心关键帧持续旋转、越吸越小越亮；
## 砸地 = 顿帧 + 砸坑 + 两层紫 / 紫灰粒子 + 两拍隆起（尘环贴图预审报重复拼接，已去掉）。吸起 / 砸地判定与时序不动
static func _an_v2(u) -> bool:
	return Bal.v("ult/an_fx_v2", 1.0) > 0.0 and u.fx_ready("fx_an_core")


static func _an_core_tick(a: Dictionary, t: float, ks_end: float) -> void:
	if not a.has("core"):
		return
	var k: float = clampf(t / maxf(0.01, float(a.TL) + float(a.TH)), 0.0, 1.0)
	a.core.ang = -t * lerpf(4.0, 14.0, k)
	a.core.sc = lerpf(0.8, ks_end, k * k)
	a.core.col = Color(1.0 + 0.5 * k, 1.0 + 0.4 * k, 1.0 + 0.6 * k, 0.9)


# ================================================================ 艾雅法拉（§4.9）：地面龟裂 → 火柱 → 熔岩块落满一圈 → 中间留熔岩地面

## 熔岩落点半径：§3.2 草案 460；实测外缘带打不死普通小怪时屏内只倒 30%，这里放到 ult/ey_r（520，10-30 对齐表再放到 590）。
## 熔岩地面草案 4 秒；短持续型上限 3.5 秒，缩到 2.2 秒（5 跳各 3%，合计 15%）。
## 火柱 25% 只打中心 140；喷发同时一圈热浪把同样 25% 给 140 外的人（草案里外圈只有 60% + 地面，精英只掉 30%，这里补齐到每人合计约 1）
static func _ey_start(u, o, c: Vector2) -> Dictionary:
	var rt := _route(o)
	var R: float = aim_r("eyjafjalla")
	var col: Color = u._col(o)
	var t_col: float = Bal.v("ult/ey_crack", 0.4)
	var blobs: Array = []   # [落点, 落地时刻]
	var nb: int = int(Bal.v("ult/ey_blobs", 38.0))   # 半径 520 → 590 时 30 → 38，熔岩块密度不变
	var t_fall: float = t_col + 0.15
	var span: float = Bal.v("ult/ey_fall", 0.45)
	for i in nb:   # 从里往外落满（按黄金角散布，序号小的先落）
		blobs.append([_spiral(c, R * 0.97, i, nb, 0.4), t_fall + span * float(i) / float(nb)])
	if rt == "ignite":   # 星火燎原：再向外抛 8 团（落在 460–560 环带）
		for i in 8:
			blobs.append([c + Vector2.from_angle(TAU * float(i) / 8.0 + 0.2) * lerpf(R * 0.9, R * 1.08, float(i % 2)), t_fall + span + 0.05 * float(i % 3)])
	var pre: Array = []
	if rt == "meteor":   # 熔岩天降：喷发前先落一轮 6 发熔岩弹预热（各 3%）
		for i in 6:
			pre.append([_spiral(c, R * 0.8, i, 6, 1.1), 0.05 + 0.05 * float(i)])
	# 龟裂：8 道裂纹从落点往外爬（0.4 秒）
	for i in 8:
		var ang: float = TAU * float(i) / 8.0 + 0.3 * float(i % 3)
		var pa: Vector2 = c
		for kq in 4:
			var pb: Vector2 = c + Vector2.from_angle(ang + 0.18 * float((kq * 5 + i) % 3 - 1)) * (40.0 + 45.0 * float(kq + 1))
			u.shape({"kind": "line", "a": pa, "b": pb, "w": 5.0 - float(kq), "col": col.lerp(Color(1, 0.9, 0.5), 0.3), "life": t_col + 0.3 - 0.08 * float(kq), "delay": 0.08 * float(kq)})
			pa = pb
	u.shape({"kind": "circle", "c": c, "r": 140.0, "col": Color(1.0, 0.35, 0.05), "fill": 0.3, "life": t_col + 0.05})
	_ring(u, c, 140.0, 20.0, col.lerp(Color.WHITE, 0.4), t_col, 4.0)
	# 熔岩块：从火柱顶上落下（下落小球带速度）+ 落地溅射帧条
	var top: Vector2 = c + Vector2(0.0, -620.0)
	for bi in blobs.size():
		var p: Vector2 = blobs[bi][0]
		var tl: float = blobs[bi][1]
		var fl: float = 0.16
		u.shape({"kind": "circle", "c": top.lerp(p, 0.55), "r": 12.0, "col": Color(1.0, 0.55, 0.15), "fill": 0.95, "life": fl, "delay": tl - fl,
			"v": (p - top.lerp(p, 0.55)) / fl})
		u.strip("fx_eyja_lava_splash", p, {"sc": 2.0, "delay": tl, "o": Vector2(40, 50)})
		_ring(u, p, 120.0, 20.0, Color(1.0, 0.5, 0.15), 0.3, 5.0, tl)
	for pi in pre.size():
		var pp: Vector2 = pre[pi][0]
		var tp: float = pre[pi][1]
		u.shape({"kind": "circle", "c": pp + Vector2(-40, -360), "r": 14.0, "col": Color(1.0, 0.5, 0.1), "fill": 0.95, "life": 0.18, "delay": tp - 0.18 + 0.05,
			"v": Vector2(40, 360) / 0.18})
		u.strip("fx_fire_explode", pp, {"sc": 1.4, "delay": tp + 0.05})
	o.play_vis_anim("attack")
	return {"c": c, "R": R, "t_col": t_col, "col_done": false, "blobs": blobs, "bi": 0, "fseg": {}, "fall_end": t_fall + span + (0.2 if rt == "ignite" else 0.0),
		"filled": false, "pre": pre, "pi": 0, "pseg": {}, "lava_r": Bal.v("ult/ey_lava_r", 300.0), "lava_t": Bal.v("ult/ey_lava_t", 2.2),
		"lava_n": int(Bal.v("ult/ey_lava_n", 5.0)), "tick": 0, "t_lava": t_fall + span + 0.05, "fall_frac": 0.5 if rt == "ignite" else Bal.v("ult/ey_fall_frac", 0.6),
		"pool": false, "fx": []}


static func _ey_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	var col: Color = u._col(o)
	var er: float = R * (1.0 - _edge_w())
	while int(a.pi) < a.pre.size() and t >= float(a.pre[int(a.pi)][1]) + 0.05:
		var pp: Vector2 = a.pre[int(a.pi)][0]
		a.pi = int(a.pi) + 1
		for e in u.in_circle(pp, 110.0):
			_hit(u, a, o, e, 0.03, {"src": "熔岩弹", "pre": true, "edge": e.pos.distance_to(c) > er})
	if not a.col_done and t >= float(a.t_col):
		a.col_done = true   # 火柱：25%，只打中心半径 140
		var top: Vector2 = c + Vector2(0.0, -640.0)
		u.shape({"kind": "band", "a": c + Vector2(0, 20), "b": top, "w": 290.0, "col": Color(1.0, 0.42, 0.08), "fill": 0.5, "life": 0.6})
		u.shape({"kind": "band", "a": c + Vector2(0, 10), "b": top + Vector2(0, 60), "w": 120.0, "col": Color(1.0, 0.92, 0.6), "fill": 0.85, "life": 0.45})
		u.shape({"kind": "circle", "c": c, "r": 150.0, "col": Color(1.0, 0.8, 0.4), "fill": 0.6, "life": 0.3})
		u.strip("fx_eyja_ignite_boom", top, {"sc": 3.2})
		u.strip("fx_missile_explode", c, {"sc": 2.4})
		_ring(u, c, 160.0, 30.0, Color(1.0, 0.85, 0.5), 0.35, 10.0)
		for i in 8:   # 火柱两侧往上喷的火星
			u.shape({"kind": "dots", "c": c + Vector2(-110.0 + 220.0 * float(i) / 7.0, -20.0), "r": 22.0, "n": 5, "col": Color(1.0, 0.7, 0.3), "life": 0.5,
				"v": Vector2((float(i) - 3.5) * 40.0, -900.0 - 80.0 * float(i % 3))})
		for e in u.in_circle(c, R):
			var de: float = e.pos.distance_to(c)
			_hit(u, a, o, e, Bal.v("ult/ey_col_frac", 0.25), {"src": "火柱" if de <= 140.0 else "热浪", "edge": de > er})
		_ring(u, c, R, 140.0, Color(1.0, 0.6, 0.25), 0.4, 12.0)
		u.shape({"kind": "circle", "c": c, "r": R, "col": Color(1.0, 0.45, 0.1), "fill": 0.16, "life": 0.3})
		o.screen_shake(0.8)
	# 熔岩落下：每块打落点 120 内；全部落完时圈内没被砸到的补一下（落满）
	var ff: float = a.fall_frac
	while int(a.bi) < a.blobs.size() and t >= float(a.blobs[int(a.bi)][1]):
		var p: Vector2 = a.blobs[int(a.bi)][0]
		a.bi = int(a.bi) + 1
		for e in u.in_circle(p, 120.0):
			if a.fseg.has(int(e.id)):
				continue
			a.fseg[int(e.id)] = true
			_hit(u, a, o, e, ff + _ey_out(a, e), {"src": "熔岩", "edge": e.pos.distance_to(c) > er})
	if not a.filled and t >= float(a.fall_end):
		a.filled = true
		for e in u.in_circle(c, R):
			if a.fseg.has(int(e.id)):
				continue
			a.fseg[int(e.id)] = true
			_hit(u, a, o, e, ff + _ey_out(a, e), {"src": "熔岩", "edge": e.pos.distance_to(c) > er})
	# 熔岩地面：半径 300，2.5 秒，每 0.5 秒一跳（合计 15%）
	var lr: float = a.lava_r
	if not a.pool and t >= float(a.t_lava):
		a.pool = true
		var lt: float = float(a.lava_t) + 0.2
		u.shape({"kind": "circle", "c": c, "r": lr, "col": Color(0.55, 0.1, 0.02), "fill": 0.45, "life": lt})
		u.shape({"kind": "ring", "c": c, "r": lr, "w": 4.0, "col": Color(1.0, 0.45, 0.1), "life": lt})
		for i in 12:
			u.strip("fx_eyja_lava_pool", _spiral(c, lr * 0.82, i, 12, 0.7), {"sc": 1.7, "layer": "back", "loop": true, "life": lt, "fps": 8.0 + float(i % 3)})
	var n_t: int = a.lava_n
	while bool(a.pool) and int(a.tick) < n_t and t >= float(a.t_lava) + float(a.lava_t) * float(int(a.tick) + 1) / float(n_t):
		a.tick = int(a.tick) + 1
		for e in u.in_circle(c, lr):
			_hit(u, a, o, e, Bal.v("ult/ey_lava_frac", 0.15) / float(n_t), {"src": "熔岩地面", "edge": false})
		u.shape({"kind": "dots", "c": c, "r": lr * 0.9, "n": 20, "col": Color(1.0, 0.6, 0.2), "life": 0.4, "v": Vector2(0, -60)})
	return bool(a.pool) and int(a.tick) >= n_t


## 熔岩地面（半径 lava_r）外的人吃不到地面那 15%：落熔岩时直接补上，圈内每人合计都是 1（10-30 对齐表：原来外圈精英 / Boss 只掉 85%）
static func _ey_out(a: Dictionary, e: Dictionary) -> float:
	return Bal.v("ult/ey_lava_frac", 0.15) if e.pos.distance_to(a.c) > float(a.lava_r) else 0.0


# ================================================================ 维什戴尔（§4.10）：架炮后仰，向指定方向一排排地毯式炮击（6 排 × 3 发），每处 0.35 秒后余震

## 排间隔 / 余震延迟：草案 0.12 / 0.45 秒；瞬发型时长上限 1.2 秒，缩到 0.1 / 0.35。带宽 840、第一排落在她脚边稍后（与斯卡蒂同理放大一点）
static func _wd_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var n: Vector2 = d.orthogonal()
	var rows: int = int(Bal.v("ult/wd_rows", 6.0))
	var rr: float = Bal.v("ult/wd_shell_r", 175.0)
	var hw: float = Bal.v("ult/wd_w", 840.0) * 0.5
	var shells: Array = []   # 每排 3 发：{p, t}
	var t0: float = Bal.v("ult/wd_t0", 0.15)
	var gap: float = Bal.v("ult/wd_gap", 0.1)
	for k in rows:
		var row: Array = []
		var along: float = -40.0 + 170.0 * float(k)
		for j in 3:
			var lat: float = (float(j) - 1.0) * (hw - rr * 0.82) + (18.0 if k % 2 == 1 else -18.0)
			row.append(o.pos + d * along + n * lat)
		shells.append({"ps": row, "t": t0 + gap * float(k), "done": false, "after": false})
	o.face_to(d.angle())
	o.play_vis_anim("attack")
	var col: Color = u._col(o)
	# 落点预兆：每发一圈细红环 + 天上落下的炮弹拖线
	for k in shells.size():
		var sh: Dictionary = shells[k]
		for p in sh.ps:
			_ring(u, p, rr * 0.5, rr * 0.5, col, float(sh.t) + 0.05, 2.0)
			u.shape({"kind": "line", "a": p + Vector2(-90, -520), "b": p + Vector2(-60, -350), "w": 6.0, "col": Color(1.0, 0.85, 0.6), "life": 0.1,
				"delay": float(sh.t) - 0.1, "v": Vector2(60, 350) / 0.1})
	# 炮口：她身前一团火光
	u.strip("fx_cannon_burst", o.pos + d * 40.0 + Vector2(0, -20), {"sc": 2.0})
	return {"d": d, "n": n, "o0": o.pos, "hw": hw, "rr": rr, "shells": shells, "mseg": {}, "aseg": {}, "delay": Bal.v("ult/wd_after_t", 0.35),
		"ember": rt == "ash", "main": 0.6 if rt == "mark" else Bal.v("ult/wd_main", 0.7), "no_ring": true}


static func _wd_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var d: Vector2 = a.d
	var n: Vector2 = a.n
	var o0: Vector2 = a.o0
	var hw: float = a.hw
	var rr: float = a.rr
	var col: Color = u._col(o)
	var dl: float = a.delay
	var all_done := true
	for k in a.shells.size():
		var sh: Dictionary = a.shells[k]
		var ts: float = sh.t
		if not sh.done and t >= ts:
			sh.done = true   # 主爆 70%（每人一次）
			for p in sh.ps:
				if _wd_v2(u):   # v2：Codex 爆炸关键帧（fx_wd_blast）鼓出冷却 + 弹坑（fx_ws_crater 4 种）留在地上 + 橙色粒子
					var hp2: float = PF.h(p.x * 0.013 + p.y * 0.029 + float(k))
					# 用户 10-30「弹坑的分布和大小可以没那么规则」：画面位置按哈希偏 ≤ 0.4 rr、大小 0.65–1.45 倍（判定仍在 p）
					var rk: float = 0.65 + 0.8 * PF.h(hp2 * 31.0)
					var pv: Vector2 = p + Vector2.from_angle(PF.h(hp2 * 17.0) * TAU) * rr * 0.4 * PF.h(hp2 * 23.0)
					var bdl: float = 0.07 * PF.h(hp2 * 41.0)   # 画面起爆错开一点（判定不变），预审报网格齐爆重复
					u.strip("fx_wd_blast" if hp2 < 0.5 else "fx_wd_blast2", pv, {"delay": bdl, "sc": rr * 0.5 * rk / 128.0, "sc1": rr * 1.15 * rk / 128.0, "scd": 0.18, "ang": hp2 * TAU, "sx": -1.0 if hp2 < 0.5 else 1.0,
						"life": 0.36, "fade": 0.2, "col": Color(0.95, 0.88, 0.85), "col1": Color(0.4, 0.33, 0.3), "cold": 0.18})   # 预审：原 1.2 倍亮、0.55 秒太白太久
					u.strip("fx_ws_crater", pv, {"layer": "back", "f": int(hp2 * 97.0) % 4, "sc": rr * 1.1 * rk / 120.0, "ang": hp2 * 5.0, "life": dl + 1.6, "fade": 0.6,
						"col": Color(1.2, 1.1, 1.0), "col1": Color(0.75, 0.7, 0.68), "cold": 0.8})
					PF.particles(u, pv, 60, "ult_burst_s", [Color(1.0, 0.6, 0.35)], 0.0, hp2 * 50.0, rr * 1.1 * rk)
				else:
					u.strip("fx_wisadel_cannon", p, {"sc": 1.9})
					u.shape({"kind": "circle", "c": p, "r": rr, "col": Color(1.0, 0.55, 0.3), "fill": 0.35, "life": 0.22})
					_ring(u, p, rr, 30.0, Color(1.0, 0.75, 0.55), 0.28, 9.0)
				_spray(u, p, 6, 30.0, 520.0, Color(1.0, 0.6, 0.3), 0.3, 0.5 * float(k))
				for e in u.in_circle(p, rr):
					if a.mseg.has(int(e.id)):
						continue
					a.mseg[int(e.id)] = true
					var lat: float = absf((e.pos - o0).dot(n))
					_hit(u, a, o, e, float(a.main), {"src": "炮击", "edge": lat > hw * (1.0 - _edge_w()), "kb": _kb_for(e, (e.pos - p).normalized(), 60.0, 30.0)})
				# 地面焦痕
				u.shape({"kind": "circle", "c": p, "r": rr * 0.7, "col": Color(0.2, 0.04, 0.04), "fill": 0.4, "life": dl + 0.6})
			o.screen_shake(0.35 + 0.05 * float(k))
		if sh.done and not sh.after and t >= ts + dl:
			sh.after = true   # 余震 30%，眩晕 0.8（精英 0.4）；余烬未冷：余震 3 圈、眩晕 1 秒
			var rings: int = 3 if a.ember else 1
			for p in sh.ps:
				if _wd_v2(u):   # 余震：一下震 + 弹坑周围碎石掀起 + 尘，不画余震圆环
					u.shake(3.0, 0.12)
					PF.heave(u, p, rr * 0.9, p.x * 0.01 + float(k), 0.0, Color.WHITE, 70.0)
				else:
					u.strip("fx_missile_explode", p, {"sc": 2.4})
					for ri in rings:
						_ring(u, p, rr * (1.0 + 0.12 * float(ri)), 40.0, col.lerp(Color(0.3, 0.0, 0.0), 0.3), 0.3, 6.0, 0.08 * float(ri))
				for e in u.in_circle(p, rr + 40.0):   # 主爆的小击退（小怪 60 / 精英 30）会把圈边的人推出圈：主爆打过的放宽 40 再判
					if a.aseg.has(int(e.id)) or (e.pos.distance_to(p) > rr and not a.mseg.has(int(e.id))):
						continue
					a.aseg[int(e.id)] = true
					var el: bool = e.elite or e.get("part", false)
					var st: float = (1.0 if a.ember else 0.8) * (0.5 if el else 1.0)
					var lat2: float = absf((e.pos - o0).dot(n))
					_hit(u, a, o, e, 1.0 - float(a.main), {"src": "余震", "edge": lat2 > hw * (1.0 - _edge_w()), "stun": st})
		if not sh.after:
			all_done = false
	return all_done


## 维什戴尔 v2（ult/wd_fx_v2，缺省 1；pixfx，docs/199 §7.8 第一批）：每发炮弹 = Codex 第二批爆炸关键帧（fx_wd_blast，单帧，代码放大冷却）
## + 弹坑（fx_ws_crater 4 种按落点哈希挑）留地上 + 橙色粒子帧条；余震 = 一下震 + 碎石掀起。判定 / 时序不动
static func _wd_v2(u) -> bool:
	return Bal.v("ult/wd_fx_v2", 1.0) > 0.0 and u.fx_ready("fx_wd_blast") and u.fx_ready("fx_ws_crater")


# ================================================================ 归溟幽灵鲨（§4.11）：巨锯放大、围着她转 3 秒，跟着队长走；期间不倒、受到的伤害 −50%

## 每 0.25 秒一圈（12 次），每次 8%；队长生命低于 50% 时每次 × (1 + 已损失生命 × 0.5)（精英 / Boss 封顶由 u.hit 管）。
## 对齐表里队长不动（§3.2 按 3 秒移动 400 算 46%），静止只罩住约 26%；原来加了一股往锯刃卷的吸力（ult/su_pull 每秒 90，锯外 200 内），
## 10-30 对齐表改成锯放大到 505（500 处精英、420 处 Boss 都在锯里），吸力缺省关掉
static func _su_start(u, o) -> Dictionary:
	var rt := _route(o)
	var g = u.g
	var dur: float = Bal.v("ult/su_t", 3.0)
	u.ev["undying_until"] = g.t + dur   # 期间不会倒下（squad.prevent_death 读）
	u.team_buff("ult:specter_saw", dur, [[&"dmg_taken", "mult", Bal.v("ult/su_taken", 0.5)]])
	o.play_vis_anim("attack")
	var col: Color = u._col(o)
	var steel: Color = col.lerp(Color.WHITE, 0.25)
	var a := {"dur": dur, "tick": 0, "n": int(Bal.v("ult/su_ticks", 12.0)), "beast": rt == "beast", "elegy": rt == "elegy", "teeth": [], "fx": [], "spin": 0.0}
	a["rim"] = _keep(u, a, {"kind": "ring", "c": o.pos, "r": 60.0, "w": 14.0, "col": steel, "life": dur + 1.0})
	a["rim2"] = _keep(u, a, {"kind": "ring", "c": o.pos, "r": 40.0, "w": 4.0, "col": Color(0.75, 0.12, 0.16), "life": dur + 1.0})
	a["disk"] = _keep(u, a, {"kind": "circle", "c": o.pos, "r": 60.0, "col": col.darkened(0.4), "fill": 0.12, "life": dur + 1.0})
	for i in int(Bal.v("ult/su_teeth", 30.0)):   # 半径 340 → 505 时 20 → 30，齿距不变
		a.teeth.append(_keep(u, a, {"kind": "blade", "a": o.pos, "b": o.pos, "w": 9.0, "col": Color.WHITE, "glow": steel, "life": dur + 1.0}))
	if a.elegy:
		a["slowr"] = _keep(u, a, {"kind": "ring", "c": o.pos, "r": 60.0, "w": 3.0, "col": Color(0.4, 0.6, 0.9), "life": dur + 1.0})
	return a


static func _su_r(u, a: Dictionary) -> float:
	var R: float = aim_r("specter_unchained")
	if a.beast:   # 困兽：基础 310，随已损失生命放大（最多 +15%）
		var lost: float = 1.0 - clampf(u.g.hp / maxf(1.0, u.g.max_hp), 0.0, 1.0)
		R *= (310.0 / 340.0) * (1.0 + minf(0.15, lost * 0.3))   # 比缺省小同样比例（原 310 对 340）
	return R


static func _su_step(u, a: Dictionary, o, dt: float) -> bool:
	var g = u.g
	var t: float = a.t
	var c: Vector2 = o.pos
	var full_r: float = _su_r(u, a)
	var R: float = full_r * clampf(t / 0.2, 0.3, 1.0)   # 锯刃 0.2 秒放大到位
	var dur: float = a.dur
	a.spin = float(a.spin) + dt * 11.0
	var sp: float = a.spin
	a.rim.c = c
	a.rim.r = R
	a.rim2.c = c
	a.rim2.r = R - 30.0
	a.disk.c = c
	a.disk.r = R
	var nt: int = a.teeth.size()
	for i in nt:   # 锯齿：外缘一圈斜向的刃，跟着转
		var ang: float = sp + TAU * float(i) / float(nt)
		var s: Dictionary = a.teeth[i]
		s.a = c + Vector2.from_angle(ang) * (R - 22.0)
		s.b = c + Vector2.from_angle(ang + 0.16) * (R + 26.0)
	if a.has("slowr"):
		a.slowr.c = c
		a.slowr.r = R + 120.0
	for s in a.fx:
		_hold(s)
	# 吸力：锯外 200 以内的敌人往锯刃卷（Boss 不吸），已进锯的不再拉
	var pull: float = Bal.v("ult/su_pull", 0.0)   # 10-30 对齐表：锯放大到 505 后不再需要（原 90）
	if pull > 0.0 and t < dur:
		for e in u.in_circle(c, R + 200.0):
			if e.boss:
				continue
			var off: Vector2 = c - e.pos
			var dd: float = off.length()
			if dd > R * 0.7:
				g.enemies_sys.nudge(e, off / maxf(1.0, dd) * pull * dt)
	if a.elegy and t < dur:   # 阿戈尔挽歌：锯外 120 一圈减速场
		for e in u.in_circle(c, R + 120.0):
			if e.pos.distance_to(c) > R:
				g.enemies_sys.add_cc(e, -INF, 0.3)
	var n: int = a.n
	while int(a.tick) < n and t >= dur * float(int(a.tick) + 1) / float(n):
		a.tick = int(a.tick) + 1
		var hpk: float = clampf(g.hp / maxf(1.0, g.max_hp), 0.0, 1.0)
		var mul: float = (1.0 + (1.0 - hpk) * 0.5) if hpk < 0.5 else 1.0
		var fr: float = Bal.v("ult/su_frac", 1.0 / 12.0) * mul   # 12 次合计 1（原 0.08 × 12 = 0.96）
		var nb := 0
		for e in u.in_circle(c, full_r):
			var de: float = e.pos.distance_to(c)
			_hit(u, a, o, e, fr, {"src": "巨锯", "edge": de > full_r * (1.0 - _edge_w())})
			if nb < 6 and de > full_r * 0.4:   # 锯过的地方飞血 / 火星（每圈最多 6 处）
				nb += 1
				var tg: Vector2 = (e.pos - c).orthogonal().normalized()
				u.shape({"kind": "dots", "c": e.pos, "r": 18.0, "n": 5, "col": Color(0.85, 0.15, 0.2), "life": 0.25, "v": tg * 380.0})
				u.shape({"kind": "line", "a": e.pos, "b": e.pos + tg * 30.0, "w": 2.0, "col": Color(1.0, 0.9, 0.7), "life": 0.15, "v": tg * 600.0})
		_ring(u, c, full_r + 6.0, full_r + 6.0, Color(1, 1, 1), 0.12, 6.0)
		if int(a.tick) % 4 == 1:
			u.strip("fx_specter_saw_blood", c + Vector2(0, -6), {"sc": full_r / 70.0, "sy": 1.8})
			o.play_vis_anim("attack")
		o.screen_shake(0.25)
	return int(a.tick) >= n


# ================================================================ 水月（§4.12）：身后破土一条巨型触手，0.5 秒横扫指定方向的半圆 → 小触手抓漏网

## 半圆半径：§3.2 草案 640（屏内实测只覆盖约 40%），放到 ult/mz_r（700）、扫 200°（两侧各多 10°，免得正侧面漏）；10-30 对齐表扫角再放到 232°
static func _mz_start(u, o, d: Vector2) -> Dictionary:
	var rt := _route(o)
	var col: Color = u._col(o)
	var R: float = Bal.v("ult/mz_r", 700.0)
	var half: float = deg_to_rad(Bal.v("ult/mz_arc", 232.0)) * 0.5   # 10-30 对齐表 200 → 232°（朝上瞄时右下 350 处精英也扫得到，屏内小怪 43% → 约 50%）
	var base: Vector2 = o.pos - d * 90.0
	o.face_to(d.angle())
	o.play_vis_anim("attack")
	# 破土：身后地面炸开
	u.strip("fx_rock_burst", base, {"sc": 2.6})
	_ring(u, base, 110.0, 20.0, col.lerp(Color.WHITE, 0.3), 0.35, 8.0)
	u.shape({"kind": "circle", "c": base, "r": 70.0, "col": Color(0.08, 0.04, 0.12), "fill": 0.8, "life": 1.2})
	var a := {"d": d, "c": o.pos, "base": base, "R": R, "a0": d.angle() - half, "span": half * 2.0, "T0": Bal.v("ult/mz_rise", 0.15),
		"T": Bal.v("ult/mz_sweep", 0.5), "seg": {}, "kills": 0, "grab": false, "n_grab": 9 if rt == "awaken" else int(Bal.v("ult/mz_grab_n", 6.0)),
		"attach": rt == "bind", "bound": [], "trail_t": 0.0, "fx": [], "chain": [], "no_ring": true, "heal": 0.0}
	for i in 28:   # 触手：28 节圆，由粗到细
		var w: float = lerpf(60.0, 10.0, float(i) / 27.0)
		a.chain.append(_keep(u, a, {"kind": "circle", "c": base, "r": w * 0.5, "col": col.darkened(0.35).lerp(Color(0.25, 0.1, 0.4), 0.3), "fill": 0.95, "life": 2.0}))
	for i in 8:   # 吸盘高光
		a.chain.append(_keep(u, a, {"kind": "circle", "c": base, "r": 5.0, "col": col.lerp(Color.WHITE, 0.6), "fill": 0.9, "life": 2.0}))
	if _mz_v2(u):   # 触手 v2：pixgen 整条触手贴图（fx_mz_tent，左粗右细带吸盘）沿贝塞尔切成 MZ_SEGS 段贴，程序圆链不画
		for s in a.chain:
			u.shapes.erase(s)
		var tt: Texture2D = u._strip_tex(MZ_TENT)
		a["tsegs"] = []
		for i in MZ_SEGS:
			var sg: Dictionary = u.strip(MZ_TENT, base, {"ux": floorf(tt.get_width() * float(i) / MZ_SEGS), "uw": ceilf(tt.get_width() / float(MZ_SEGS)) + 2.0,
				"o": Vector2(0.0, tt.get_height() * 0.5), "life": 2.0})
			a.tsegs.append(sg)
			a.fx.append(sg)
	return a


## 水月 v2（ult/mz_fx_v2，缺省 1；用户 10-30「水月的触手需要重新生成」）：pixgen 整条触手（fx_mz_tent）沿 _mz_pose 的贝塞尔切段贴，
## 每段按切线转角、按段长拉伸，粗细跟贴图本身（根部粗、尖端卷曲）
const MZ_TENT := "fx_mz_tent"
const MZ_SEGS := 20   # 段越多弯处接缝越小（预审报 10 段拼接感明显）


static func _mz_v2(u) -> bool:
	return Bal.v("ult/mz_fx_v2", 1.0) > 0.0 and u.fx_ready(MZ_TENT)


static func _mz_tent_pose(u, a: Dictionary, ctrl: Vector2, tip: Vector2) -> void:
	if not a.has("tsegs"):
		return
	var base: Vector2 = a.base
	var tt: Texture2D = u._strip_tex(MZ_TENT)
	var seg_w: float = tt.get_width() / float(MZ_SEGS)   # 纹素
	var k0: float = u.g.PX / A.hires_of(tt)
	for i in MZ_SEGS:
		var ka: float = float(i) / MZ_SEGS
		var kb: float = float(i + 1) / MZ_SEGS
		var pa: Vector2 = base.lerp(ctrl, ka).lerp(ctrl.lerp(tip, ka), ka)
		var pb: Vector2 = base.lerp(ctrl, kb).lerp(ctrl.lerp(tip, kb), kb)
		var s: Dictionary = a.tsegs[i]
		s.c = pa
		s.ang = (pb - pa).angle()
		s.sx = pa.distance_to(pb) / (seg_w * k0) * 1.12   # 段间多叠一点，弯处不露缝
		s.sy = 0.9
		s.age = 0.0


## 触手形状：从身后根部出发，弯一道弧到当前角度的尖端（二次贝塞尔，控制点偏向扫动的来向）
static func _mz_pose(a: Dictionary, ang: float, reach: float) -> void:
	var base: Vector2 = a.base
	var c: Vector2 = a.c
	var tip: Vector2 = c + Vector2.from_angle(ang) * reach
	var ctrl: Vector2 = c + Vector2.from_angle(ang - 0.45) * reach * 0.55
	if a.has("tsegs"):
		a["_ctrl"] = ctrl
		a["_tip"] = tip
	var ch: Array = a.chain
	for i in 28:
		var k: float = float(i) / 27.0
		ch[i].c = base.lerp(ctrl, k).lerp(ctrl.lerp(tip, k), k)
	for j in 8:
		var k2: float = (float(j) + 0.5) / 9.0
		var p: Vector2 = base.lerp(ctrl, k2).lerp(ctrl.lerp(tip, k2), k2)
		var nrm: Vector2 = (ctrl.lerp(tip, k2) - base.lerp(ctrl, k2)).normalized().orthogonal()
		ch[28 + j].c = p + nrm * lerpf(16.0, 3.0, k2)


static func _mz_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var c: Vector2 = a.c
	var R: float = a.R
	var T0: float = a.T0
	var T: float = a.T
	var col: Color = u._col(o)
	var a0: float = a.a0
	var span: float = a.span
	if t < T0 + T + 0.12:
		var reach: float
		var ang: float
		if t < T0:   # 破土升起：朝起扫角伸长
			reach = R * clampf(t / T0, 0.15, 1.0)
			ang = a0
		else:
			var k: float = clampf((t - T0) / T, 0.0, 1.0)
			var ke: float = k * k * (3.0 - 2.0 * k)   # 起扫慢、中段最快、收尾慢
			reach = R
			ang = a0 + span * ke
			# 扫过的敌人各吃一次 100%（10-30 对齐表 80% → 100%：原来精英 / Boss 只掉 32% / 6.4%）；被打倒的每只给队长回 0.2% 最大生命（至多 5%）
			for e in u.in_circle(c, R):
				if a.seg.has(int(e.id)):
					continue
				var off: Vector2 = e.pos - c
				var rel: float = fposmod(off.angle() - a0, TAU)
				if rel > span * ke + 0.05 and off.length() >= 60.0:
					continue
				a.seg[int(e.id)] = true
				var tg: Vector2 = Vector2.from_angle(off.angle() + PI / 2.0)
				_hit(u, a, o, e, Bal.v("ult/mz_sweep_frac", 1.0), {"src": "横扫", "edge": off.length() > R * (1.0 - _edge_w()), "kb": _kb_for(e, tg, 140.0, 60.0)})
				if e.dead and float(a.heal) < 0.05:
					a.heal = float(a.heal) + 0.002
					g.combat.heal(g.max_hp * 0.002, "终结技", "mizuki")
			if t >= float(a.trail_t):   # 扫过的残影
				a.trail_t = t + 0.03
				u.shape({"kind": "sector", "c": c, "r": R, "a": ang - 0.12, "half": 0.12, "col": col, "fill": 0.18, "life": 0.3})
				u.shape({"kind": "line", "a": c + Vector2.from_angle(ang) * R * 0.95, "b": c + Vector2.from_angle(ang - 0.08) * R, "w": 6.0, "col": col.lerp(Color.WHITE, 0.6), "life": 0.2})
		_mz_pose(a, ang, reach)
		if a.has("tsegs"):
			_mz_tent_pose(u, a, a._ctrl, a._tip)
		for s in a.fx:
			_hold(s)
		return false
	if not a.grab:
		a.grab = true
		_fade(u, a, 0.3)
		u.strip("fx_mizuki_tentacle_mass", a.base, {"sc": 1.6, "o": Vector2(96, 90)})
		# 小触手：从扫过区域与他身边 300 内，抓生命最低的漏网（每根 20%，束缚 1.5 秒）
		var cand: Array = []
		for e in u.in_circle(c, R):
			var off2: Vector2 = e.pos - c
			var rel2: float = fposmod(off2.angle() - a0, TAU)
			if rel2 <= span + 0.05 or off2.length() <= 300.0:
				cand.append(e)
		cand.sort_custom(func(x, y): return float(x.hp) / maxf(1.0, float(x.maxhp)) < float(y.hp) / maxf(1.0, float(y.maxhp)) if not is_equal_approx(float(x.hp) / maxf(1.0, float(x.maxhp)), float(y.hp) / maxf(1.0, float(y.maxhp))) else int(x.id) < int(y.id))
		var ng: int = mini(int(a.n_grab), cand.size())
		for i in ng:
			var e: Dictionary = cand[i]
			u.strip("fx_mizuki_tentacle", e.pos + Vector2(0, 8), {"sc": 1.7, "o": Vector2(24, 108), "delay": 0.03 * float(i)})
			u.strip("fx_mizuki_bind_ring", e.pos, {"sc": 2.2, "loop": true, "life": 1.2})
			_hit(u, a, o, e, Bal.v("ult/mz_grab_frac", 0.2), {"src": "小触手", "stun": 1.5})
			if not e.dead:
				a.bound.append(e)
		for i in 8:   # 他身边钻出的小触手（画面）
			var p: Vector2 = c + Vector2.from_angle(TAU * float(i) / 8.0 + 0.2) * 300.0 * (0.55 + 0.45 * float(i % 2))
			u.strip("fx_mizuki_tentacle", p + Vector2(0, 8), {"sc": 1.2, "o": Vector2(24, 108), "delay": 0.02 * float(i)})
		_ring(u, c, 300.0, 40.0, col.lerp(Color.WHITE, 0.4), 0.35, 5.0)
		a["grab_t"] = t
	if a.attach and t < float(a.grab_t) + 0.5:   # 病理性依恋：被束缚的敌人拖到水月身边
		for e in a.bound:
			if not e.dead and not e.boss:
				var tp: Vector2 = o.pos + (e.pos - o.pos).normalized() * 70.0
				g.enemies_sys.nudge(e, (tp - e.pos) * 0.2)
	return t >= float(a.grab_t) + (0.5 if a.attach else 0.1)
