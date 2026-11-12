## 德克萨斯（docs/257，照 docs/246 斯卡蒂 / docs/254 星熊的做法）
## 普攻「拔刀」= 腰高琥珀刀痕，两头针尖（精一刀头甩碎晶 + 钉剑，精二白刃内侧冷青刃光）；骤雨 / 回马剑 = 整道约 300° 旋斩；
## S1「剑雨」= 源石剑从天而降、插地、刃光沿刃走一趟、碎成碎晶（精一更多更大，精二再大一号 + 收尾中心巨剑 + 地面剑阵）；
## S2「冲锋号令·γ型」= 起手琥珀光柱，之后所有冲刺的直线刀光加粗（精二带冷青刃光点）；
## S3「剑雨滂沱」= 起手身边一圈落剑 + 剑阵；次元斩每刀一道腰高细长直线刀痕 + 目标处落一柄大剑；
## 精二余像 = 地上两道残像边线，消散时沿路落剑；后期剑气 = 飞出去的源石剑（同一次出手合成一柄），沿路落小剑；
## 连携（追击 / 冲刺斩）= 冲刺直线刀光 + 目标处十字斩。
## 帧条键前缀 tx_（data/pxp_texas.json，tools/pxplane_bake.py --op texas）；直线刀光按美术像素格运行时逐格画（方向任意，不旋转贴图）。
## docs/286 §4 第三批从 render/fx_pxplane.gd 原样拆出，行为不变：全部 static func，第一个参数 pv = fx_pxplane 实例（成员经 pv.、常量经 P.）；本节状态变量仍在 fx_pxplane 上。
extends RefCounted

const P = preload("res://scripts/render/fx_pxplane.gd")
const Bal = preload("res://scripts/core/balance.gd")
const TX_C: Array[Color] = [Color("#120804"), Color("#2c1406"), Color("#5a2808"), Color("#9c4610"), Color("#e2781c"), Color("#ffac3c"), Color("#ffdc9c"), Color("#ffffff")]
const TX_AC := Color("#9fe3ff")
const TX_RAIN_CAP := [10, 13, 16]        # 剑雨同一次至多画几柄（三档）；其余照常结算，只是不画
const TX_SW := [[16, 0], [19, 1], [22, 2]]   # 剑雨三档的剑：[剑长, 档]


static func _ev_tx(pv: P, o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var g = pv.g
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG tx %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			var es: Array = d.get("es", [])
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 100.0))
				match src:
					"骤雨", "回马剑":   # 360° 旋斩（骤雨连斩 4 下左右交替）
						pv._tx_spin += 1
						var sk: String = "tx_spin_r%d_e%d" % [pv._bucket(r * 0.5, [50, 56, 63]), t]
						if raw:
							pv._push({"k": "tx_raw_spin_e%d" % t, "t0": g.t, "gp": c + Vector2(0, -10), "ly": "raw", "rot": float(pv._tx_spin) * 1.3, "sc": g.PX * (r * 0.5) / 50.0, "oid": str(o.id)})
						else:
							var fl: bool = (pv._tx_spin % 2) == 1
							pv._push({"k": sk + "_up", "t0": g.t, "gp": pv._snap(c), "flip": fl, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
							pv._push({"k": sk + "_gd", "t0": g.t, "gp": pv._snap(c), "flip": fl, "ly": "gd", "oid": str(o.id), "fo": Vector2.ZERO})
						_tx_cuts(pv, o, es, t, 2)
						_tx_hit(pv, o, R, c + Vector2(0, -16), c.y + 2.0, es, 2 + t, 120.0, 0.5)   # docs/270：同拔刀，灯强度提到 0.5
					_:
						pass   # 剑雨 / 余像·剑雨的判定圈：画面由落剑（tx_rain 事件）画，不逐圈画
				return
			# 锥形：拔刀（普攻）
			var ang: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 112.0))
			var dv := Vector2.from_angle(ang)
			pv._add(o, "tx_slash_r%d_e%d" % [pv._bucket(r2 * 0.5, [56, 63, 70]), t], o.pos, ang, r2, raw, "tx_raw_slash_e%d" % t, 56.0)
			_tx_cuts(pv, o, es, t, 2)
			_tx_hit(pv, o, R, o.pos + dv * r2 * 0.6 + Vector2(0, -14), o.pos.y + dv.y * r2 * 0.6 * 0.72, es, 2 + t, 110.0, 0.5)   # docs/270：普攻灯强度 0.3（全员最暗）→ 0.5
			if t >= 1 and not raw and pv.mode() == 1:   # 精一钉剑：命中里离她最近的 2 名（非 Boss）各插一柄源石剑，跟着敌人，0.7 秒后碎掉
				var lst: Array = es.filter(func(x): return not x.boss and not x.dead)
				lst.sort_custom(func(x1, x2): return x1.pos.distance_squared_to(o.pos) < x2.pos.distance_squared_to(o.pos))
				for i in mini(2, lst.size()):
					var pe: Dictionary = lst[i]
					pv._push({"k": "tx_pin_h%d_e%d_up" % [15 if float(pe.r) >= 22.0 else 9, mini(t, 2)], "t0": g.t, "gp": pv._snap(pe.pos), "fe": pe, "flip": (pe.pos.x < o.pos.x), "ly": "up", "oid": str(o.id)})
		"tx_rain":   # verb.fx_rain（剑雨 / 剑雨·连 / 剑雨·连绵 / 余像·剑雨）：落剑清单由玩法画面那份（g.vrng）给出
			var bl: Array = d.get("bl", [])
			if bl.is_empty():
				return
			var path: bool = d.get("path", false)
			var sw: Array = [14, 2] if path else TX_SW[t]
			var cap: int = 12 if path else TX_RAIN_CAP[t]
			var lst2: Array = bl.slice(0, cap)
			var ft: float = float(d.get("ft", 0.1))
			var cc: Vector2 = d.get("c", o.pos)
			_tx_rain(pv, o, lst2, "tx_sw_s%d_e%d" % [sw[0], sw[1]], raw, t)
			if not path:
				if t >= 2 and not d.get("echo", false):   # 精二收尾：中心一柄巨剑 + 地面剑阵（质变）
					var tm := 0.0
					for b in lst2:
						tm = maxf(tm, float(b.d))
					var fin_d: float = tm + 0.12
					_tx_rain(pv, o, [{"p": cc, "d": fin_d, "a": 0.0, "fl": false}], "tx_sw_s40_e2", raw, t)
					if not raw:
						pv._push({"k": "tx_array_r65_gd", "t0": _tx_beat(pv, g.t + fin_d, 2), "gp": pv._snap(cc), "flip": false, "ly": "gd", "oid": str(o.id)})   # 剑阵热白第一拍 = 巨剑插地那一拍 = 中心灯（docs/270：灯与辉光同帧）
					if pv.mode() == 1:
						pv._txq.append([_tx_beat(pv, g.t + fin_d, 2), "land", {"o": o, "p": cc, "n": 8, "lr": 220.0, "li": 0.8}])
				if pv.mode() == 1:   # 剑雨中心那盏灯跟第一柄剑插地同一拍亮（docs/270：灯与辉光同帧）
					pv._txq.append([_tx_beat(pv, g.t, 2), "lt", {"o": o, "p": cc + Vector2(0, -20), "lr": 180.0, "li": 0.6}])
		"tx_dash":   # 冲刺（拔刀冲刺 / 战术快递 / 突进 / 冲刺斩）：腰高直线刀光 + 地上焦痕；S2 永久生效后加粗
			var a0: Vector2 = d.get("from", o.pos)
			var b0: Vector2 = d.get("to", o.pos)
			var s2: bool = t >= 1 and o.perm.size() > 1 and o.perm[1]
			_tx_line(pv, o, a0, b0, 2 if s2 else 1, 1, 1 if s2 else 0, raw, true)
			if pv.mode() == 1:
				R._light(o, b0 + Vector2(0, -20), 120.0, 0.35, 0.1, p.light)
		"tx_trail":   # 精二余像：地上两道残像边线，life 秒内淡掉（消散时的落剑走 tx_rain path）
			if not raw:
				pv._push({"tr": true, "a": d.get("from", o.pos), "b": d.get("to", o.pos), "w": float(d.get("w", 44.0)), "t0": g.t, "life": float(d.get("life", 0.6)), "ly": "gd2", "oid": str(o.id), "k": ""})
		"tx_scar":   # 次元斩：一道腰高细长直线刀痕（判定线两端外延），scar 秒后碎开
			var hold: int = maxi(1, int(round(float(d.get("life", 0.22)) * 15.0)))
			if d.get("one", false):   # 一刀一道（fx/texas_s3_single_slash；11-06 用户「不要太粗，但是要亮」）：芯 2 格（末刀 3 格）近白 + 两侧一格淡琥珀，命中两拍过曝白 + 每格辉光，到点一拍断掉
				_tx_line(pv, o, d.get("a", o.pos), d.get("c", o.pos), 3 if float(d.get("wmax", 4.0)) >= 5.0 else 2, hold, 3, raw, false)
			else:
				_tx_line(pv, o, d.get("a", o.pos), d.get("c", o.pos), 2 if float(d.get("wmax", 2.0)) >= 3.0 else 1, hold, 2, raw, false)
		"tx_cut":   # 次元斩每一刀：目标处落一柄大剑（剑雨滂沱）
			var at: Vector2 = d.get("at", o.pos)
			if d.get("one", false):   # 一刀一道：不落剑（读起来像又一击），命中点一簇火星 + 沿刀线两头各几颗碎屑 + 照地光
				pv._burst_m(o, R, p, at + Vector2(0, -20), at.y + 2.0, [], 10 if d.get("last", false) else 7, "shard", 170.0, 0.7)
				if pv.mode() == 1:   # 命中两拍：刀线中段再一盏亮照地光（和白芯辉光同一帧挂）
					pv._txq.append([g.t, "lt", {"o": o, "p": at + Vector2(0, -P.TX_H), "lr": 200.0, "li": 0.9}])
				if pv.mode() == 1:
					var ca: Vector2 = d.get("a", at)
					var cc2: Vector2 = d.get("c", at)
					for q in [ca.lerp(cc2, 0.25), ca.lerp(cc2, 0.75)]:
						R._grains(o, q + Vector2(0, -P.TX_H), q.y + 2.0, "shard", 2, {"tier": 2}, (cc2 - ca).normalized())
				return
			_tx_rain(pv, o, [{"p": at, "d": 0.0, "a": 0.0, "fl": (int(g.t * 15.0) % 2) == 0}], "tx_sw_s26_e2", raw, 2)
			pv._burst_m(o, R, p, at + Vector2(0, -20), at.y + 2.0, [], 4, "shard", 130.0, 0.45)
		"tx_link":   # 连携（技能连携 v2「追击」/ combo「冲刺斩」）：粗直线刀光 + 目标处十字斩
			var fa: Vector2 = d.get("from", o.pos)
			var tb: Vector2 = d.get("to", o.pos)
			var mid: Vector2 = d.get("mid", tb)
			var dv2: Vector2 = (tb - fa).normalized() if tb != fa else Vector2.RIGHT
			_tx_line(pv, o, fa, tb, 2, 2, 1, raw, true)
			if raw:
				pv._push({"k": "tx_raw_xcut", "t0": g.t, "gp": mid + Vector2(0, -24), "ly": "raw", "rot": dv2.angle(), "sc": g.PX * 1.37, "oid": str(o.id)})
			else:
				var dk: Array = pv.pick_dir(dv2.angle())
				pv._push({"k": "tx_xcut_up_d%d" % dk[0], "t0": g.t, "gp": pv._snap(mid), "flip": dk[1], "ly": "up", "oid": str(o.id)})
				pv._push({"k": "tx_xcut_gd_d%d" % dk[0], "t0": g.t, "gp": pv._snap(mid), "flip": dk[1], "ly": "gd", "oid": str(o.id)})
			_tx_cuts(pv, o, d.get("es", []), 1, 3)
			pv._burst_m(o, R, p, mid + Vector2(0, -20), mid.y + 2.0, d.get("es", []), 8, "shard", 200.0, 0.8)
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1:   # 冲锋号令·γ型起手：琥珀光柱 + 脚下断续环
				var tt: int = maxi(t, 1)
				if raw:
					pv._push({"k": "tx_raw_spin_e%d" % tt, "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": 0.0, "sc": g.PX * 0.6, "oid": str(o.id)})
				else:
					pv._push({"k": "tx_order_e%d_up" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": float(o.face) < 0.0, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
					pv._push({"k": "tx_order_e%d_gd" % tt, "t0": g.t, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id), "fo": Vector2.ZERO})
				if pv.mode() == 1:
					R._grains(o, o.pos + Vector2(0, -30), o.pos.y, "shard", 5 + 2 * tt, {"tier": tt})
					R._light(o, o.pos + Vector2(0, -30), 140.0, 0.6, 0.15, p.light)
			elif i == 2:   # 剑雨滂沱起手：身边一圈 8 柄剑依次落下 + 剑阵
				var ring: Array = []
				for k in 8:
					var a: float = TAU * float(k) / 8.0 + 0.2
					ring.append({"p": o.pos + Vector2(cos(a), sin(a) * 0.72) * 104.0, "d": 0.035 * float(k), "a": 0.0, "fl": k % 2 == 1})
				_tx_rain(pv, o, ring, "tx_sw_s22_e2", raw, 2)
				if not raw:
					pv._push({"k": "tx_array_r56_gd", "t0": g.t + 0.1, "gp": pv._snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if pv.mode() == 1:
					R._light(o, o.pos + Vector2(0, -20), 180.0, 0.6, 0.15, p.light)


## 命中：碎晶当场生成；照地灯推迟到这一帧的绘制里再挂（docs/270：灯和斩痕白芯的辉光同一帧亮——emit 点在绘制时排进发光层、下一帧才显出，
## 灯在玩法更新里挂会比辉光早一帧，体检取的命中帧上就量不到辉光）
static func _tx_hit(pv: P, o, R, at: Vector2, gy: float, es: Array, n: int, lr: float, li: float) -> void:
	var g = pv.g
	if pv.mode() != 1:
		return
	var m := {"tier": pv.tier(o), "grain_spd": 1.0}
	var hp: Vector2 = at
	if not es.is_empty():
		var e: Dictionary = es[0]
		hp = e.pos + Vector2(0, -float(e.r) * 0.5)
		R._grains(o, hp, float(e.pos.y) + 2.0, "shard", mini(n, 2 + es.size()), m, (hp - o.pos).normalized())
	else:
		R._grains(o, at, gy, "shard", maxi(1, n / 2), m)
		lr *= 0.8
		li *= 0.6
	pv._txq.append([g.t, "lt", {"o": o, "p": hp, "lr": lr, "li": li}])


## 某一时刻起第 k 拍（15 fps 节拍）开始的时刻：帧条第 k 帧被画出来的那一拍
static func _tx_beat(pv: P, t0: float, k: int) -> float:
	return (floor(t0 * 15.0) + float(k)) / 15.0


## 斩痕（同斯卡蒂 _cuts，琥珀色）
static func _tx_cuts(pv: P, o, es: Array, t: int, n: int) -> void:
	var k0: int = pv.items.size()
	pv._cuts(o, es, t, n)
	for i in range(maxi(0, k0 - n), pv.items.size()):
		var it: Dictionary = pv.items[i]
		if it.get("cut", false) and str(it.oid) == str(o.id):
			it["emk"] = true
			it["c1"] = "#ffdc9c"
			it["c2"] = "#ffac3c"
			it["c3"] = "#e2781c"


## 一组落剑：bl = [{p 落点, d 延时, a 倾角, fl 翻转}]；一条组件（ly rain），画时按每柄的出手时刻展开（sort_items / 地面层）
static func _tx_rain(pv: P, o, bl: Array, key: String, raw: bool, t: int) -> void:
	var g = pv.g
	if bl.is_empty():
		return
	var lf: float = pv._life(key + "_l0_up", pv._life_fps())
	var tm := 0.0
	for b in bl:
		tm = maxf(tm, float(b.d))
	if raw:   # 旧做法：每柄一张旋转 + 小数缩放的整张贴图，盖在最上层
		for b in bl.slice(0, 10):
			pv._push({"k": "tx_raw_sword_e%d" % t, "t0": g.t + float(b.d), "gp": (b.p as Vector2) + Vector2(0, -24), "ly": "raw", "rot": float(b.a), "sc": g.PX * 1.37, "oid": str(o.id)})
		return
	pv._push({"rain": bl, "key": key, "t0": g.t, "life": tm + lf, "ly": "rain", "oid": str(o.id), "k": ""})
	if pv.mode() == 1:   # 前三柄落地那一下：几颗碎晶 + 一盏短照地光
		for b in bl.slice(0, 3):
			pv._txq.append([_tx_beat(pv, g.t + float(b.d), 2), "land", {"o": o, "p": b.p, "n": 3, "lr": 110.0, "li": 0.45}])


## 直线刀光（运行时逐格）：w 芯宽（格）、hold 保持几拍再碎、style 0 冲刺 / 1 加粗（号令 · 连携）/ 2 次元斩；gs = 地上留焦痕
static func _tx_line(pv: P, o, a: Vector2, b: Vector2, w: int, hold: int, style: int, raw: bool, gs: bool) -> void:
	var g = pv.g
	if a.distance_to(b) < 4.0:
		return
	if raw:
		pv._push({"rawln": true, "a": a, "b": b, "t0": g.t, "life": 0.34, "ly": "rawln", "oid": str(o.id), "k": ""})
		return
	pv._push({"ln": true, "a": a, "b": b, "w": w, "hold": hold, "st": style, "gs": gs, "cold": pv.tier(o) >= 2, "t0": g.t, "life": float(hold + 4) / 15.0, "gy": maxf(a.y, b.y) + 2.0, "ly": "up", "oid": str(o.id), "k": ""})


static func _tx_cell(pv: P, ci, p: Vector2, c: Color) -> void:
	var g = pv.g
	ci.draw_rect(Rect2(pv._snap(p), Vector2(g.PX, g.PX)), c)


## 直线刀光一帧：第 0 拍白芯 + 两侧亮琥珀；之后芯转淡琥珀、两侧暗一阶；hold 拍后两拍里逐格断开；两头收尖。ground = 地上的焦痕（只画暗琥珀，晚两拍断完）
static func _tx_draw_line(pv: P, ci, it: Dictionary, ground: bool) -> void:
	var g = pv.g
	var f: int = pv.frame_of(float(it.t0))
	var hold: int = int(it.hold)
	if f < 0:
		return
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	var L: float = a.distance_to(b)
	var dv: Vector2 = (b - a) / maxf(1.0, L)
	var nv := Vector2(-dv.y, dv.x)
	var n: int = maxi(2, int(L / px))
	if ground:
		if f > hold + 3:
			return
		var brk: float = clampf(float(f - hold + 1) / 4.0, 0.0, 1.0)
		for i in n + 1:
			if fposmod(float(i) * 0.618034 + float(int(absf(a.x)) % 13) * 0.07, 1.0) < brk:
				continue
			var u0: float = float(i) / float(n)
			if u0 < 0.06 or u0 > 0.96:
				continue
			_tx_cell(pv, ci, a + dv * float(i) * px + Vector2(0, 2), TX_C[3] if f <= 1 else (TX_C[2] if f <= hold + 1 else TX_C[1]))
		return
	if f > hold + 1:
		return
	var st: int = int(it.st)
	var w: int = int(it.w)
	var lift := Vector2(0, -P.TX_H)
	if st == 3:
		_tx_draw_line1(pv, ci, it, f, hold, a, b, dv, nv, n, w, lift)
		return
	var broke: bool = f >= hold
	var cold: bool = st == 1 and w >= 2 and it.get("cold", false)
	for i in n + 1:
		var u: float = float(i) / float(n)
		var prof: float = pow(sin(PI * clampf(u * 0.92 + 0.04, 0.0, 1.0)), 0.5)   # 两头收尖
		if broke and fposmod(float(i) * 0.618034 + float(f) * 0.31, 1.0) < (0.45 if f == hold else 0.75):
			continue
		var q: Vector2 = a + dv * float(i) * px + lift
		var cw: int = w if prof > 0.55 else 1
		var core: Color = Color(1, 1, 1) if f == 0 else (TX_C[6] if not broke else TX_C[5])
		var side: Color = TX_C[5] if f == 0 else (TX_C[4] if not broke else TX_C[3])
		for k in cw:
			_tx_cell(pv, ci, q + nv * float(k) * px, core)
		if prof > 0.3:
			_tx_cell(pv, ci, q - nv * px, TX_AC if (cold and (i % 7) == 3 and not broke) else side)   # 精二号令 / 连携：冷青刃光点
			_tx_cell(pv, ci, q + nv * float(cw) * px, side)
			if st >= 1 and prof > 0.7 and f <= 1:
				_tx_cell(pv, ci, q + nv * float(cw + 1) * px, TX_C[3])
		if f == 0 and (i & 1) == 0 and prof > 0.4:
			pv._glow(q, Color(1.0, 0.85, 0.6))


## 一刀一道（style 3，fx/texas_s3_single_slash）：一条细而亮的斩线——芯 2–3 格近白（第 0–1 拍过曝 + 每格辉光，命中那一拍停住）、两侧一格淡琥珀，没有暗外缘；
## hold 那一拍断一半，下一拍没了（干脆收掉，不拖碎尾）；两头收尖
static func _tx_draw_line1(pv: P, ci, it: Dictionary, f: int, hold: int, a: Vector2, b: Vector2, dv: Vector2, nv: Vector2, n: int, w: int, lift: Vector2) -> void:
	var g = pv.g
	if f > hold:
		return
	var px: float = g.PX
	var hot: bool = f <= 1
	var broke: bool = f == hold and f > 1
	var core: Color = Color(1.35, 1.3, 1.2) if hot else Color(1.0, 0.95, 0.86)   # 芯近白（命中两拍过曝），琥珀只在两侧
	var side: Color = TX_C[6] if hot else TX_C[5]
	for i in n + 1:
		var u: float = float(i) / float(n)
		var prof: float = pow(sin(PI * clampf(u * 0.94 + 0.03, 0.0, 1.0)), 0.6)
		if broke and fposmod(float(i) * 0.618034 + 0.2, 1.0) < 0.5:
			continue
		var cw: int = maxi(1, int(round(float(w) * prof)))
		var q: Vector2 = a + dv * float(i) * px + lift - nv * float(cw / 2) * px
		for k in cw:
			_tx_cell(pv, ci, q + nv * float(k) * px, core)
		if prof > 0.25:
			_tx_cell(pv, ci, q - nv * px, side)
			_tx_cell(pv, ci, q + nv * float(cw) * px, side)
		if hot and prof > 0.2:
			pv._glow(q + nv * float(cw / 2) * px, Color(1.0, 0.88, 0.66))
		elif (i & 1) == 0 and prof > 0.4 and not broke:
			pv._glow(q + nv * float(cw / 2) * px, Color(0.8, 0.6, 0.4))


## 精二余像：地上两道残像边线（断续、贴边一格暗内边），life 秒内淡掉；不铺满
static func _tx_draw_trail(pv: P, ci, it: Dictionary) -> void:
	var g = pv.g
	var age: float = g.t - float(it.t0)
	var life: float = float(it.life)
	if age < 0.0 or age >= life:
		return
	var k: float = age / life
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	var L: float = a.distance_to(b)
	var dv: Vector2 = (b - a) / maxf(1.0, L)
	var nv := Vector2(-dv.y, dv.x * 0.72).normalized()
	var hw: float = float(it.w) * 0.5
	var n: int = maxi(2, int(L / px))
	var tick: int = int(floor(g.t * 15.0))
	for side in [-1.0, 1.0]:
		for i in n + 1:
			if fposmod(float(i) * 0.618034 + side * 0.3 + float(tick) * 0.11, 1.0) < 0.25 + 0.6 * k:   # 越来越稀
				continue
			var q: Vector2 = a + dv * float(i) * px + nv * hw * side
			_tx_cell(pv, ci, q, TX_C[5] if k < 0.3 else (TX_C[4] if k < 0.65 else TX_C[3]))
			_tx_cell(pv, ci, q - nv * px * side, TX_C[1])


static func _tx_due(pv: P) -> void:
	var g = pv.g
	if pv._txq.is_empty():
		return
	var now: float = g.t
	var keep: Array = []
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	for q in pv._txq:
		if now < float(q[0]):
			keep.append(q)
			continue
		if pv.mode() != 1 or now - float(q[0]) > 0.2:
			continue
		var dd: Dictionary = q[2]
		var o = dd.o
		if not is_instance_valid(o):
			continue
		var at: Vector2 = dd.p
		if str(q[1]) == "lt":
			R._light(o, at, float(dd.lr), float(dd.li), 0.12, R.pal(o).get("light", TX_C[5]))
			continue
		R._grains(o, at + Vector2(0, -6), at.y + 1.0, "shard", int(dd.n), {"tier": pv.tier(o)})
		R._light(o, at + Vector2(0, -8), float(dd.lr), float(dd.li), 0.1, R.pal(o).get("light", TX_C[5]))
	pv._txq = keep


## 落剑组展开：每柄的立起件（出手前不画；按剑倾角挑 l0 / l1）
static func _tx_rain_items(pv: P, it: Dictionary, ground: bool) -> Array:
	var g = pv.g
	var out: Array = []
	var key: String = it.key
	var t0: float = float(it.t0)
	var lf: float = pv._life(key + "_l0_up", pv._life_fps())
	for b in it.rain:
		var ts: float = t0 + float(b.d)
		if g.t < ts or g.t > ts + lf:
			continue
		var gp: Vector2 = pv._snap(b.p)
		if ground:
			out.append({"k": key + "_gd", "t0": ts, "gp": gp, "flip": b.fl})
		else:
			out.append({"k": key + ("_l1_up" if absf(float(b.a)) > 0.03 else "_l0_up"), "t0": ts, "gp": gp, "flip": b.fl})
	return out


static func _tx_sort_items(pv: P, o, out: Array) -> void:
	var id: String = str(o.id)
	for it in pv.items_for(id):
		if str(it.ly) == "rain":
			out.append_array(_tx_rain_items(pv, it, false))
	for qv in _tx_qi(pv, o):
		out.append({"k": qv.k + "_up_d%d" % qv.d, "fi": qv.f, "gp": qv.gp, "flip": qv.flip})


## 地面层（德克萨斯）：贴地件、落剑的冲击 / 焦痕、余像边线、直线刀光的地上焦痕、剑气影子
static func _floor_tx(pv: P, o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	_tx_due(pv)
	for it in pv.items_for(id):
		match str(it.ly):
			"gd":
				pv._draw_strip(cv, str(it.k), pv.frame_of(float(it.t0)), pv._gp(it), it.flip, true)   # 挂在人身上的件（fo）按施放者当前位置
			"gd2":
				_tx_draw_trail(pv, cv, it)
			"rain":
				for s in _tx_rain_items(pv, it, true):
					pv._draw_strip(cv, str(s.k), pv.frame_of(float(s.t0)), s.gp, s.flip, true)
			"up":
				if it.has("ln") and it.gs:
					_tx_draw_line(pv, cv, it, true)
	for qv in _tx_qi(pv, o):
		pv._draw_strip(cv, qv.k + "_gd_d%d" % qv.d, int(qv.f), qv.gp, qv.flip, true)


## 后期剑气（growth/late_shape → vis_growth._fire_qi）：同一次出手的几道合成一柄飞剑（同星熊 _qi_volleys 的分组）；
## 飞行途中每 3 拍在身后落一柄小剑（剑雨意象，每组至多 3 柄；画面计时记在剑气字典的画面专用键 _pxd，玩法不读）
static func _tx_qi(pv: P, o) -> Array:
	var g = pv.g
	var out: Array = []
	if pv.mode() != 1 or o.vg.is_empty() or not o.vg.has("qi") or o.vg.qi.is_empty():
		return out
	var grp: Dictionary = {}
	for q in o.vg.qi:
		var key: int = int(round((g.t - float(q.t)) * 60.0))
		if not grp.has(key):
			grp[key] = {"p": Vector2.ZERO, "v": Vector2.ZERO, "n": 0, "t": float(q.t), "life": float(q.life), "q0": q}
		var e: Dictionary = grp[key]
		e.p += pv._qpos(q)
		e.v += (q.v as Vector2).normalized()
		e.n += 1
		e.life = minf(float(e.life), float(q.life))
	var t: int = pv.tier(o)
	var keys: Array = grp.keys()
	keys.sort()
	keys.reverse()
	var tick: int = int(floor(g.t * 15.0))
	for key in keys.slice(0, 2):   # 同屏至多两组（最新两次出手）
		var e: Dictionary = grp[key]
		var n: int = int(e.n)
		var S: int = 1 if n <= 1 else (2 if n == 2 else 3)
		var dk: Array = pv.pick_dir((e.v as Vector2).angle())
		var f: int = 0 if float(e.t) < 1.0 / 15.0 else (2 if float(e.life) < 0.07 else 1)
		var gp: Vector2 = pv._snap(e.p / float(n))
		out.append({"k": "tx_qi_s%d_e%d" % [S, t], "d": dk[0], "flip": dk[1], "gp": gp, "f": f})
		var q0: Dictionary = e.q0
		if not q0.has("_pxd"):
			q0["_pxd"] = [tick, 0]
			continue
		var dn: Array = q0._pxd
		if tick - int(dn[0]) < 3 or int(dn[1]) >= 3:
			continue
		q0["_pxd"] = [tick, int(dn[1]) + 1]
		var back: Vector2 = gp - (e.v as Vector2).normalized() * 30.0
		_tx_rain(pv, o, [{"p": back, "d": 0.0, "a": 0.0, "fl": (tick % 2) == 0}], "tx_sw_s14_e%d" % t, false, t)
	return out
