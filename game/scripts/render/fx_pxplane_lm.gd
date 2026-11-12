## 流明（docs/255，照斯卡蒂 docs/246 的做法）
## 帧条件（tools/pxplane_bake_lumen.py，键前缀 lm_）：光弹命中 / 折光落点 / 荧光治疗 / 出光点 / 沐雨 v3 / 光雨雨区（循环）/ 沛霖水柱 / 灯火不灭起手 · 光圈（循环）· 光爆；
## 线状件在运行时按美术像素格逐格画（光弹、折光、灯塔光柱 + 地面光痕、治疗连线、灯塔守望光扇）：方向任意，不旋转贴图，2 世界像素一格、15 fps 节拍换形。
## 光弹位置每帧走（380 像素 / 秒，按 15 fps 跳格一次跳 25 像素会一卡一卡），只取整到美术像素格；弹头形状按 15 fps 节拍换。
## 旧做法（2）：旧放开版帧条（tools/pixelfx_fx/lumen_ul_ref）光晕烤进颜色，小数缩放 + 旋转，盖在所有单位上。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const LM_C := [Color("#121a2a"), Color("#1d3150"), Color("#2a5282"), Color("#4285ad"), Color("#7fb2d6"), Color("#c4e0f2"), Color("#ffffff")]   # house.js OP.lumen 钢蓝 7 阶
const LM_AC := Color("#ff9640")   # 精二点缀灯火橙


static func _lm_up(pv: P, o, k: String, at: Vector2, gy: float, fol := false, e = null) -> void:
	var g = pv.g
	if k.begins_with("hit"):   # 命中水花同屏上限（同一名干员）：主弹至多 5 团、小水花（发光单元 / 额外弹 / 折光 / 连锁 / 光柱穿透）至多 3 团——后期弹多也不叠成一片白
		var small: bool = k.begins_with("hits")
		var n := 0
		for it in pv.items:
			if str(it.oid) == str(o.id) and str(it.k).begins_with("lm_hits" if small else "lm_hit_") and str(it.ly) == "up":
				n += 1
		if n >= (3 if small else 5):
			return
	# 跟人（框架 11-05，docs/246 §10）：fol = 挂在队长身上（治疗、沐雨、沛霖、S3 起手、连携落点），按 15 fps 节拍跟着队长跳格；e = 跟着被打的那只（命中水花）
	var it := {"k": "lm_" + k, "t0": g.t, "gp": pv._snap(at), "gyo": gy - pv._snap(at).y, "flip": false, "ly": "up", "oid": str(o.id)}
	if fol and g.ppos != Vector2.INF:
		it["fol"] = pv._snap(at) - g.ppos
	if e != null:
		it["e"] = e
	pv._push(it)


static func _lm_gd(pv: P, o, k: String, at: Vector2, fol := false) -> void:
	var g = pv.g
	var it := {"k": "lm_" + k, "t0": g.t, "gp": pv._snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	if fol and g.ppos != Vector2.INF:
		it["fol"] = pv._snap(at) - g.ppos
	pv._push(it)


static func _lm_raw(pv: P, o, k: String, at: Vector2, rot: float, sc: float) -> void:
	var g = pv.g
	pv._push({"k": "lm_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


## 技能起手的照地光晚一拍（1/15 秒）亮：沐雨 / 沛霖 / 灯火不灭的帧条第 0 拍几乎是空的、主形第 1 拍才出来，发光层又晚一帧显示；
## 光若在施放那一帧就最亮，会比主形先到（光感体检 docs/270 量到的就是「有光没芯」那一帧）。走 fx_recipe 同一个灯表，只是起点挪后
static func _lm_light_beat(pv: P, R, o, at: Vector2, r: float, inten: float, col: Color) -> void:
	var g = pv.g
	R.lights.append([at, r, col, g.t + 1.0 / 15.0, 0.15, inten, str(o.id)])
	if R.lights.size() > 32:
		R.lights.pop_front()


static func _ev_lumen(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	var px: float = g.PX
	match kind:
		"lm_hit":   # 光弹命中：立起水花（原点 = 命中点，按敌人脚底排序）+ 地上湿痕；发光单元的弹小一号、不留湿痕
			var e: Dictionary = d.e
			var at: Vector2 = d.at
			var small: bool = d.get("unit", false)
			if raw:
				_lm_raw(pv, o, "raw_hit_e%d" % t, at, 0.0, px * (0.75 if small else 1.15))
				return
			_lm_up(pv, o, ("hits_e%d_up" if small else "hit_e%d_up") % t, at, float(e.pos.y) + 1.0, false, e)
			if not small:
				_lm_gd(pv, o, "hit_e%d_gd" % t, e.pos + Vector2(0, 2))
				# 命中亮芯（光感体检 docs/270：普攻命中帧发光核心只有 14 < 30）：水花的白芯只在第 0 拍，这里在命中点另挂 3 拍亮芯进发光层，跟着被打的那只
				pv._push({"rt": "hcore", "e": e, "a": at, "t": t, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(e.pos.y) + 1.5, "oid": str(o.id), "k": ""})
			pv._burst(o, R, p, at, float(e.pos.y) + 2.0, [e], (1 if small else 2) + t, 60.0 + 15.0 * t, 0.3 + 0.1 * t)
		"lm_refract":   # 精一折光：命中点到下一只之间一道 1 美术像素白芯细光，落点小水花
			var a: Vector2 = d.a
			var b: Vector2 = d.b
			if raw:
				pv._push({"rt": "rawline", "a": a, "b": b, "t0": g.t, "life": 0.12, "ly": "raw", "oid": str(o.id), "k": ""})
				_lm_raw(pv, o, "raw_hit_e1", b, 0.0, px * 0.6)
				return
			pv._push({"rt": "line", "a": a, "b": b, "t0": g.t, "life": 5.0 / 15.0, "ly": "up", "gy": float(d.get("gy", b.y + 10.0)), "oid": str(o.id), "k": ""})
			_lm_up(pv, o, "hits_e%d_up" % t, b, float(d.get("gy", b.y + 10.0)))
			R._light(o, b, 60.0, 0.35, 0.1, p.light)
		"lm_pillar":   # 精二灯塔光柱：出光点一颗四芒星 + 一道实心光柱（任意方向逐格画）+ 地上一道光痕；命中的前 4 只各一团水花
			var from: Vector2 = d.from
			var dv: Vector2 = d.d
			var L: float = float(d.L)
			var foot: Vector2 = d.get("foot", from)
			var es: Array = d.get("es", [])
			if raw:
				_lm_raw(pv, o, "raw_pillar", from, dv.angle(), px * L / 200.0 * 1.13)
				for e in es.slice(0, 4):
					_lm_raw(pv, o, "raw_hit_e2", e.pos + Vector2(0, -float(e.r) * 0.5), 0.0, px * 1.15)
				return
			pv._push({"rt": "beam", "a": pv._snap(from), "d": dv, "L": L, "W": float(d.get("W", 10.0)), "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": foot.y + 1.0, "oid": str(o.id), "k": ""})
			pv._push({"rt": "streak", "a": pv._snap(foot), "d": dv, "L": L, "t0": g.t, "life": 3.0 / 15.0, "ly": "gd", "oid": str(o.id), "k": ""})
			_lm_up(pv, o, "flare_up", from, foot.y + 2.0)
			pv.items[pv.items.size() - 1]["fo"] = pv._snap(from) - o.pos   # 出光点跟着流明走
			R._light(o, from, 90.0, 0.55, 0.12, p.light)
			R._light(o, foot + dv * L * 0.6, 110.0, 0.35, 0.12, p.light)
			for e in es.slice(0, 3):   # 一线穿透：每只一团小水花（至多 3 团），不叠成一片白
				var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
				_lm_up(pv, o, "hits_e2_up", hp, float(e.pos.y) + 1.0, false, e)
			if not es.is_empty():
				pv._burst(o, R, p, from, foot.y, [es[0]], 3, 70.0, 0.4)
		"lm_mend":   # 荧光治疗：队长身前一侧卷上去一缕水流
			var at2: Vector2 = d.at
			for it in pv.items:   # 沐雨同一拍也会回血：只画沐雨，不再叠一缕水流（同一招元素 ≤ 3）
				if str(it.k).begins_with("lm_drizzle") or str(it.k).begins_with("lm_raw_drizzle"):
					if is_equal_approx(float(it.t0), g.t):
						return
			if raw:
				_lm_raw(pv, o, "raw_mend_e%d" % t, at2, 0.0, px * 1.15)
				return
			_lm_up(pv, o, "mend_e%d_up" % t, at2, at2.y + 1.0, true)
			R._light(o, at2 + Vector2(0, -30), 70.0, 0.35, 0.12, p.light)
		"lm_link":   # 提灯到治疗落点的细光（2 拍）
			if raw:
				pv._push({"rt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": 0.25, "ly": "raw", "oid": str(o.id), "k": ""})
				return
			pv._push({"rt": "link", "a": d.a, "b": d.b, "t0": g.t, "life": 2.0 / 15.0, "ly": "up", "gy": (d.b as Vector2).y + 24.0, "oid": str(o.id), "k": ""})
		"shape":   # 灯塔守望·回光（watch2：沐雨时与灯火不灭期间每秒一圈，玩法是 ob_core 圆形判定）：判定半径上边弧原地闪一下 + 一盏照地光
			if not d.get("circle", false):
				return
			var pc: Vector2 = d.get("c", g.ppos)
			if raw:
				_lm_raw(pv, o, "raw_burst", pc, 0.0, px * float(d.get("r", 120.0)) / 220.0 * 1.13)
				return
			_lm_gd(pv, o, "pulse_gd", pc)
			R._light(o, pc + Vector2(0, -10), float(d.get("r", 120.0)), 0.4, 0.12, p.light)
		"lm_xhit":   # 后期额外弹命中：小一号水花；同一拍至多 3 团（弹数随档位增加，画面不跟着碎）
			var xe: Dictionary = d.e
			if pv._lm_beat_n(o, "xh") >= 3:
				return
			if raw:
				_lm_raw(pv, o, "raw_hit_e%d" % t, d.at, 0.0, px * 0.75)
				return
			_lm_up(pv, o, "hits_e%d_up" % t, d.at, float(xe.pos.y) + 1.0, false, xe)
		"lm_chain":   # 「连锁」弹射：同折光一套 1 美术像素细光；同一拍至多 3 道
			if pv._lm_beat_n(o, "ch") >= 3:
				return
			if raw:
				pv._push({"rt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": 0.14, "ly": "raw", "oid": str(o.id), "k": ""})
				return
			pv._push({"rt": "line", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
			_lm_up(pv, o, "hits_e%d_up" % t, d.b, float(d.get("gy", 0.0)))
		"lm_cshot":   # 连携技「清创光弹」出手：一颗大光弹飞向队长
			if raw:
				pv._push({"rt": "rawcbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "raw", "oid": str(o.id), "k": ""})
				return
			pv._push({"rt": "cbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "up", "gy": (d.b as Vector2).y + 31.0, "oid": str(o.id), "k": ""})
			R._light(o, d.a, 70.0, 0.4, 0.1, p.light)
		"lm_lfire":   # 连携 v2「清创光弹」（skill_link l_lumen）：提灯一颗大光弹 0.13 秒飞到队长胸口 → 炸开（同 lm_cleanse）；连携区域 1.2 秒内光尘往上飘
			var la: Vector2 = d.a
			var lt: Vector2 = d.at
			var lc: Vector2 = d.c
			if raw:
				pv._push({"rt": "rawcbolt", "a": la, "b": lt + Vector2(0, -30), "t0": g.t, "life": 0.13, "ly": "raw", "oid": str(o.id), "k": ""})
				_lm_raw(pv, o, "raw_hit_e2", lt + Vector2(0, -30), 0.0, px * 1.7)
				return
			pv._push({"rt": "cbolt", "a": la, "b": lt + Vector2(0, -30), "t0": g.t, "life": 0.13, "ly": "up", "gy": lt.y + 1.0, "oid": str(o.id), "k": ""})
			var t1: float = g.t + 0.13
			pv._push({"k": "lm_cleanse_up", "t0": t1, "gp": pv._snap(lt + Vector2(0, -30)), "gyo": 31.0, "fol": pv._snap(lt + Vector2(0, -30)) - g.ppos, "flip": false, "ly": "up", "oid": str(o.id)})
			pv._push({"k": "lm_cleanse_gd", "t0": t1, "gp": pv._snap(lc), "flip": false, "ly": "gd", "oid": str(o.id)})
			pv._push({"k": "lm_lmotes_up", "t0": t1, "gp": pv._snap(lc), "gy": lc.y + 1.0, "flip": false, "ly": "up", "oid": str(o.id)})
			R._light(o, lt + Vector2(0, -20), 170.0, 0.8, 0.15, p.light)
			R._grains(o, lt + Vector2(0, -30), lt.y, "ink", 4, {"tier": 1})
		"lm_cleanse":   # 连携技落点：队长胸口一团大水花 + 灯火橙光尘上飘；地上照亮范围边弧原地闪一下
			var ct: Vector2 = d.at
			if raw:
				_lm_raw(pv, o, "raw_hit_e2", ct + Vector2(0, -30), 0.0, px * 1.7)
				return
			_lm_up(pv, o, "cleanse_up", ct + Vector2(0, -30), ct.y + 1.0, true)
			_lm_gd(pv, o, "cleanse_gd", ct, true)
			R._light(o, ct + Vector2(0, -20), 170.0, 0.8, 0.15, p.light)
			R._grains(o, ct + Vector2(0, -30), ct.y, "ink", 4, {"tier": 1})
		"lm_burst":   # 灯火不灭结束光爆：短粗双层星芒 + 竖光柱；地上判定半径边弧原地闪一下
			var at3: Vector2 = d.at
			if raw:
				_lm_raw(pv, o, "raw_burst", at3, 0.0, px * float(d.get("r", 220.0)) / 220.0 * 1.13)
				return
			_lm_up(pv, o, "burst_up", at3, at3.y + 1.0)
			_lm_gd(pv, o, "burst_gd", at3)
			R._light(o, at3 + Vector2(0, -60), 240.0, 0.9, 0.15, p.light)
			R._grains(o, at3 + Vector2(0, -60), at3.y, "ink", 8, {"tier": 2})
		"skill":
			var i: int = int(d.get("i", -1))
			var lp: Vector2 = g.ppos
			if i == 0:   # 沐雨 v3：脚下涟漪弧法阵（贴地）+ 斜细雨 / 十字星 / 精二灯塔光柱（立起）
				pv.items = pv.items.filter(func(it): return not ((str(it.k).begins_with("lm_mend") or str(it.k).begins_with("lm_raw_mend")) and is_equal_approx(float(it.t0), g.t)))
				if raw:
					_lm_raw(pv, o, "raw_drizzle_e%d" % t, lp, 0.0, px * 1.07)
					return
				_lm_gd(pv, o, "drizzle_e%d_gd" % t, lp, true)
				_lm_up(pv, o, "drizzle_e%d_up" % t, lp, lp.y + 1.0, true)
				_lm_light_beat(pv, R, o, lp + Vector2(0, -20), 150.0, 0.45 + 0.1 * t, p.light)
			elif i == 1:   # 沛霖：头顶水柱砸下（精二三道）+ 落点湿痕
				var tt: int = maxi(t, 1)
				if raw:
					_lm_raw(pv, o, "raw_downpour_e%d" % tt, lp, 0.0, px * 1.13)
					return
				_lm_up(pv, o, "downpour_e%d_up" % tt, lp, lp.y + 1.0, true)
				_lm_gd(pv, o, "downpour_e%d_gd" % tt, lp, true)
				_lm_light_beat(pv, R, o, lp + Vector2(0, -20), 130.0, 0.6, p.light)
				R._grains(o, lp + Vector2(0, -24), lp.y, "ink", 3 + 2 * tt, {"tier": tt})
			elif i == 2:   # 灯火不灭起手：头顶四芒灯光 + 水流卷上去；光圈原地亮起
				if raw:
					_lm_raw(pv, o, "raw_lamp", lp, 0.0, px * 1.13)
					return
				_lm_up(pv, o, "s3open_up", lp, lp.y + 1.0, true)
				_lm_gd(pv, o, "s3open_gd", lp, true)
				_lm_light_beat(pv, R, o, lp + Vector2(0, -96), 160.0, 0.7, p.light)


## 贴地层：一次性件 + 运行时线状贴地件 + 状态件（光雨雨区、灯塔光圈、灯塔守望光扇）
static func _lm_draw_floor(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var id: String = str(o.id)
	for it in pv.items_for(id):
		if str(it.ly) != "gd":
			continue
		if it.has("rt"):
			_lm_draw_rt(pv, cv, it)
		else:
			pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), pv._gp(it), it.flip, true)
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	if float(lm.get("rain_t", 0.0)) > 0.0:
		pv._draw_strip(cv, "lm_rain_gd", pv.frame_of(0.0), pv._snap(g.ppos), false, false)
	var S = pv._sl()
	if S._h3_tower_on(o):
		pv._draw_strip(cv, "lm_tower_gd", pv.frame_of(0.0), pv._snap(lm.tower_pos), false, false)
	var bb: Dictionary = S._h3_beam_block(o)
	if S._h3_beam_on(o, bb):
		_lm_beam_trace(pv, cv, o, lm, bb)


## 立起层的状态件：光弹（运行时）、光雨雨点（循环帧条）、灯塔光尘（循环帧条）
static func _lm_sort_items(pv: P, o, out: Array) -> void:
	var g = pv.g
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
		out.append({"loopk": "lm_rain_up", "gp": pv._snap(g.ppos), "gy": g.ppos.y + 1.0})
	if pv._sl()._h3_tower_on(o):
		var tp: Vector2 = lm.tower_pos
		out.append({"loopk": "lm_tower_up", "gp": pv._snap(tp), "gy": tp.y + 1.0})
	var bb: Dictionary = pv._sl()._h3_beam_block(o)
	if pv._sl()._h3_beam_on(o, bb):   # 灯塔守望光束（立起层，和队长 / 灯塔一起按脚底 y 排）
		var gb: Vector2 = lm.tower_pos if pv._sl()._h3_tower_on(o) else g.ppos
		out.append({"rt": "wbeam", "o": o, "bb": bb, "gy": gb.y + 1.0})


## 运行时线状件：line 折光 / link 治疗连线 / beam 灯塔光柱 / streak 光柱地面光痕 / bolt 光弹
static func _lm_draw_rt(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var px: float = g.PX
	var C: Array = LM_C
	match str(it.rt):
		"line", "link":
			var f: int = pv.frame_of(float(it.t0))
			var link: bool = str(it.rt) == "link"
			var nb: int = 2 if link else 5   # 折光 docs/310 §4.2：3 → 5 拍（0.33 秒）、2 像素宽、尾光往落点收
			if f < 0 or f >= nb:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / px))
			var nrm: Vector2 = (b - a).normalized().orthogonal() * px
			var cut: float = [0.0, 0.0, 0.45, 0.7, 0.88][f] if not link else (0.5 if f == 2 else 0.0)
			for i in n + 1:
				var u: float = float(i) / float(n)
				if u < cut:
					continue   # 后几拍只剩靠落点的一段（尾光）
				var q: Vector2 = a.lerp(b, u)
				var core: Color = (C[6] if f == 0 else C[5]) if not link else (C[5] if f == 0 else C[4])
				pv._px(ci, q, core)
				if not link:
					pv._px(ci, q + nrm, C[4] if f < 2 else C[3])
				if f == 0 and not link and i % 3 == 0:
					pv._glow(q, C[6])
		"beam":   # 光柱：第 0 拍满宽白芯 → 往中线收 → 从出光端熄；最远端 15% 收尖
			var f2: int = pv.frame_of(float(it.t0))
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
					pv._px(ci, c0 + nv * float(q) * px, col)
				if f2 <= 1 and k % 3 == 0:
					pv._glow(c0, C[6])
				s += px
				k += 1
		"streak":   # 光柱在地上的光痕（照亮的地面）：1 美术像素钢蓝线，3 拍里从出光端往外熄
			var f3: int = pv.frame_of(float(it.t0))
			if f3 < 0 or f3 > 2:
				return
			var a3: Vector2 = it.a
			var L3: float = float(it.L)
			var s3: float = L3 * [0.0, 0.3, 0.6][f3]
			while s3 <= L3:
				pv._px(ci, a3 + (it.d as Vector2) * s3, C[3] if f3 == 0 else C[2])
				s3 += px
		"bolt":   # 光弹（普攻 / 发光单元）
			var b: Dictionary = it.b
			_lm_bolt(pv, ci, b.pos, b.vel, pv.tier(it.o), b.get("big", false), str(b.get("src", "")) == "发光单元")
		"xbolt":   # 后期额外弹（growth/late_shape 等的 vis_growth 弹体）：同一套光弹，小一号（同发光单元）
			var xb: Dictionary = it.b
			_lm_bolt(pv, ci, (xb.p as Vector2) + Vector2(0, -18.0), xb.v, pv.tier(it.o), false, true)
		"wbeam":
			_lm_draw_wbeam(pv, ci, it.o, it.bb)
		"hcore":   # 命中亮芯：第 0 拍 3×3 + 十字臂、第 1 拍 3×3、第 2 拍中心 + 四点；每点 1 美术像素白芯并进 emit（精二中心一点灯火橙）
			var fh: int = pv.frame_of(float(it.t0))
			if fh < 0 or fh > 2:
				return
			var e: Dictionary = it.e
			var c: Vector2 = (e.pos + Vector2(0, -float(e.r) * 0.5)) if not e.get("dead", false) else (it.a as Vector2)
			var pts: Array = []
			if fh <= 1:
				for yy in [-1, 0, 1]:
					for xx in [-1, 0, 1]:
						pts.append(Vector2(xx, yy))
				if fh == 0:
					pts.append_array([Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2), Vector2(3, 0), Vector2(-3, 0)])
			else:
				pts = [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
			for q in pts:
				var pp: Vector2 = c + q * px
				var col: Color = C[6] if (fh == 0 or (q as Vector2).length() < 1.5) else C[5]
				if int(it.t) >= 2 and q == Vector2.ZERO and fh <= 1:
					col = LM_AC
				pv._px(ci, pp, col)
				pv._glow(pp, C[6] if col != LM_AC else LM_AC)
		"cbolt":   # 连携技「清创光弹」：提灯到队长胸口飞 travel 秒，大一号、不分档（尾 18 格 + 两格宽芯 + 灯火橙芯）
			var u: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.life)), 0.0, 1.0)
			var ca: Vector2 = it.a
			var cb: Vector2 = it.b
			_lm_bolt(pv, ci, ca.lerp(cb, u), cb - ca, 2, true, false, true)


## 一颗光弹：雨滴形弹头（白芯 + 冰蓝）+ 钢蓝尾，尾长分档；精一弹头前缘四芒折光星（按拍闪），精二尾更长、尾根一点灯火橙。位置每帧走、取整到美术像素格
static func _lm_bolt(pv: P, ci, pos: Vector2, vel: Vector2, t: int, big: bool, unit: bool, link := false) -> void:
	var g = pv.g
	var px: float = g.PX
	var C: Array = LM_C
	var dv2: Vector2 = vel.normalized()
	var nv2 := Vector2(-dv2.y, dv2.x)
	var head: Vector2 = pv._snap(pos)
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
		pv._px(ci, q, col)
		for side in range(1, w + 1):
			pv._px(ci, q + nv2 * px * side, C[4] if i < 3 else C[3])
			pv._px(ci, q - nv2 * px * side, C[4] if i < 3 else C[3])
	pv._px(ci, head + dv2 * px, C[5])
	if t >= 2:
		pv._px(ci, head - dv2 * px * 2.0, LM_AC)
	if t >= 1 and beat % 2 == 0:   # 折光星
		for dd in [1, 2]:
			var cc: Color = C[6] if dd == 1 else C[5]
			pv._px(ci, head + dv2 * px * float(dd + 1), cc)
			pv._px(ci, head + nv2 * px * float(dd), cc)
			pv._px(ci, head - nv2 * px * float(dd), cc)
	if unit:
		pv._glow(head, C[6])
		pv._glow(head - dv2 * px, C[5])
	else:   # 主弹弹头一团 3×3 亮芯进发光层（光感体检 docs/270：发光层晚一帧显示，命中那一帧亮的是弹头上一帧留下的辉光，2 点太弱）
		for yy in [-1, 0, 1]:
			for xx in [-1, 0, 1]:
				pv._glow(head + Vector2(xx, yy) * px, C[6] if absi(xx) + absi(yy) <= 1 else C[5])


## 灯塔守望光束（11-05 用户「流明那个光束得重新做一下」；原来是贴地光扇、两道边带缺口——又碎又平、不亮）。
## 重做：一道实心光束从队长胸口（灯塔在场时从灯塔灯口）射出，由高到低斜落到判定线末端（立起、有高度差），窄 → 宽、整道连续；
## 白只给芯的前 35%，身子冰蓝 / 钢蓝，远端降一阶；出光点一颗小四芒星（精二芯一点灯火橙）；沿光束两盏照地光（亮度靠光，不靠大片白）；
## 地上一道 1 美术像素暗钢蓝光痕把光束「落」在地面上。方向取玩法的连续角度（每帧转，不按 15 fps 跳格：2 秒一圈、按拍跳一次就是 12°，末端一跳 50 多像素），形状逐格画、对齐像素格。
## 三档：光束末端半宽 5 / 6.5 / 8 美术像素，精一起芯加宽一格，精二出光点灯火橙。淡入淡出只收宽度、降色阶，不用半透明。
static func _lm_wbeam_geo(pv: P, o, lm: Dictionary, bb: Dictionary) -> Dictionary:
	var g = pv.g
	var S = pv._sl()
	var twr: bool = S._h3_tower_on(o)
	var gorg: Vector2 = lm.tower_pos if twr else g.ppos
	var dv: Vector2 = S._h3_beam_dir(o, bb)
	var L: float = float(bb.get("len", 260.0))
	var src: Vector2 = S._h3_tower_lamp(o) if twr else g.ppos + Vector2(0, -34)
	var fade: float = clampf((float(lm.get("tower_t", 0.0)) if twr else float(lm.get("beam_t", 0.0))) / 0.5, 0.0, 1.0)
	return {"gorg": gorg, "dv": dv, "L": L, "src": src, "tip": gorg + dv * L + Vector2(0, -6), "fade": fade}


static func _lm_beam_trace(pv: P, cv, o, lm: Dictionary, bb: Dictionary) -> void:
	var g = pv.g
	var ge: Dictionary = _lm_wbeam_geo(pv, o, lm, bb)
	if float(ge.fade) <= 0.05:
		return
	var L: float = float(ge.L)
	var s: float = L * 0.2
	while s <= L:
		pv._px(cv, (ge.gorg as Vector2) + (ge.dv as Vector2) * s, LM_C[3] if s > L * 0.45 else LM_C[2])
		s += g.PX


static func _lm_draw_wbeam(pv: P, ci, o, bb: Dictionary) -> void:
	var g = pv.g
	var lm: Dictionary = o.hw.lm
	var ge: Dictionary = _lm_wbeam_geo(pv, o, lm, bb)
	var fade: float = float(ge.fade)
	if fade <= 0.05:
		return
	var px: float = g.PX
	var C: Array = LM_C
	var t: int = pv.tier(o)
	var src: Vector2 = ge.src
	var tip: Vector2 = ge.tip
	var span: Vector2 = tip - src
	var Ls: float = span.length()
	if Ls < 4.0:
		return
	var du: Vector2 = span / Ls
	var nv := Vector2(-du.y, du.x)
	var w1: float = [5.0, 6.5, 8.0][t] * (0.35 + 0.65 * fade)
	var dim: int = 1 if fade < 0.5 else 0
	var core_w: int = 0 if t == 0 else 1
	var s: float = 0.0
	var k := 0
	while s <= Ls:
		var u: float = s / Ls
		var w: float = 1.0 + (w1 - 1.0) * u
		if u > 0.88:
			w *= 1.0 - (u - 0.88) / 0.12 * 0.6   # 远端收一点，不是方头
		var m: int = int(round(w))
		var far: int = (1 if u > 0.75 else 0) + dim
		var c0: Vector2 = src + du * s
		for q in range(-m, m + 1):
			var aq: int = absi(q)
			var ci_: int
			if aq <= core_w:
				ci_ = 6 if u < 0.35 else 5
			elif aq < maxi(1, int(m * 0.5)):
				ci_ = 5
			elif aq < m:
				ci_ = 4
			else:
				ci_ = 3
			pv._px(ci, c0 + nv * float(q) * px, C[clampi(ci_ - far, 2, 6)])
		if u < 0.6 and k % 3 == 0:
			pv._glow(c0, C[6] if u < 0.35 else C[5])
		s += px
		k += 1
	# 出光点：小四芒星（精二芯一点灯火橙）
	var arm: int = 3 + t
	for dd in range(1, arm + 1):
		var cc: Color = C[6] if dd <= 1 else C[5]
		for v in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			pv._px(ci, src + v * px * float(dd), cc)
	pv._px(ci, src, LM_AC if t >= 2 else C[6])
	pv._glow(src, C[6])
	# 照地光：光束中段与末端各一盏（每帧跟着光束走，走配方灯光预算）
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var p: Dictionary = R.pal(o)
	R._light_follow(o, (ge.gorg as Vector2) + (ge.dv as Vector2) * float(ge.L) * 0.5, 80.0 + 10.0 * t, 0.45 * fade, p.light)
	R._light_follow(o, (ge.gorg as Vector2) + (ge.dv as Vector2) * float(ge.L) * 0.9, 70.0 + 10.0 * t, 0.35 * fade, p.light)


## 旧做法（2）：旧放开版帧条整张贴（光晕烤进颜色、小数缩放、旋转），盖在所有单位上
static func _lm_draw_raw(pv: P, o) -> void:
	var g = pv.g
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	for it in pv.items_for(id):
		if str(it.ly) != "raw":
			continue
		if str(it.get("rt", "")) == "rawcbolt":
			var cu: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.life)), 0.0, 1.0)
			pv._draw_raw(cv, "lm_raw_bolt_e2", posmod(int(g.t * rf), maxi(1, int(pv._meta("lm_raw_bolt_e2").get("n", 1)))), (it.a as Vector2).lerp(it.b, cu), ((it.b as Vector2) - (it.a as Vector2)).angle(), g.PX * 1.6)
			continue
		if str(it.get("rt", "")) == "rawline":
			var kk: float = 1.0 - (g.t - float(it.t0)) / maxf(0.01, float(it.life))
			cv.draw_line(it.a, it.b, Color(0.77, 0.88, 0.95, 0.9 * kk), 2.0)
			continue
		pv._draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	var t: int = pv.tier(o)
	var lf: int = int(g.t * rf)
	for b in lm.bolts:
		var mk: Dictionary = pv._meta("lm_raw_bolt_e%d" % t)
		pv._draw_raw(cv, "lm_raw_bolt_e%d" % t, posmod(lf, maxi(1, int(mk.get("n", 1)))), b.pos, (b.vel as Vector2).angle(), g.PX * (1.4 if b.get("big", false) else 1.13))
	if not o.vg.is_empty():
		var mx: Dictionary = pv._meta("lm_raw_bolt_e%d" % t)
		for xb in o.vg.bul:
			pv._draw_raw(cv, "lm_raw_bolt_e%d" % t, posmod(lf, maxi(1, int(mx.get("n", 1)))), (xb.p as Vector2) + Vector2(0, -18.0), (xb.v as Vector2).angle(), g.PX * 0.9)
	if float(lm.get("rain_t", 0.0)) > 0.0:
		pv._draw_raw(cv, "lm_raw_rain", posmod(lf, maxi(1, int(pv._meta("lm_raw_rain").get("n", 1)))), g.ppos, 0.0, g.PX * 1.07)
	var S = pv._sl()
	if S._h3_tower_on(o):
		pv._draw_raw(cv, "lm_raw_tower", posmod(lf, maxi(1, int(pv._meta("lm_raw_tower").get("n", 1)))), lm.tower_pos, 0.0, g.PX * 1.07)
	var bb: Dictionary = S._h3_beam_block(o)
	if S._h3_beam_on(o, bb):
		var dv: Vector2 = S._h3_beam_dir(o, bb)
		pv._draw_raw(cv, "lm_raw_sweep", posmod(lf, maxi(1, int(pv._meta("lm_raw_sweep").get("n", 1)))), S._h3_beam_origin(o), dv.angle(), g.PX * float(bb.get("len", 260.0)) / 260.0 * 1.13)
