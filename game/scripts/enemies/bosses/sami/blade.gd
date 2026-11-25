## “邪魔的利刃”（3:30）/ “邪魔的利刃”，游荡者（7:00）：招式按 docs/393 §11.2（11-25 差异化定稿：黑雾地毯 + 从雾里竖起的刃）。
## 主轴「裂国度」不变：它一路在身边铺国度（利刃 r 70、游荡者 r 90，每 4 秒一块；国度里的队员攻速 −50%、挨它的招 ×1.5——mech_foes.player_hit_mult）；
## 二幕起每 12 秒召 3 只染污躯壳；在国度里 / 边缘击杀让裂纹长，6 秒内碎 3 块 → 踉跄 2.5 秒、受伤 ×1.5。游荡者国度连片 220、碎一块相连的裂纹 +50%（mech_kingdom）。
## 招：一幕 A 斩击·竖刃 ③ / B 投刃·切雾 ② / C 国度爆发 ① / D 黑毯 ④；二幕加 E 追猎·卷毯 ② / F 国度刃雨 ①；游荡者再加 G 皇帝的猎杀 ①链，整体冷却 ×0.9。
## 持续压力「呼吸」：它的国度每 3 秒（二幕 2.4）往外胀一圈薄雾，胀出的边扫到队长 6%。
## 出招组（每幕 2）：一幕「斩投」A→B→A、「黑毯」C→D；二幕「追猎」E→F→A、「刃雨」F→C→B（游荡者换「猎杀」G→F→E）。
## 瞄准一律对队长当前位置或预判位置（协调人 11-25：用户嫌落点不追人）；大刃片、竖刃是脚本自己的场上实体（e.ents），碎刃走 mid_cards 中 / 大弹（不用小弹）。
## 画面全是占位（draw），最终特效交 fx-declutter。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const LEAD := 0.35        # 预判秒数（落点类）
const RISE_R := 16.0      # 竖刃判定半径
const THROW_R := 24.0     # 投刃大刃片半宽（§11.2 半宽 24）


func _wand(e: Dictionary) -> bool:
	return e.type == "wanderer"


func _kr(e: Dictionary) -> float:
	return 90.0 if _wand(e) else 70.0


## 队长 s 秒后的位置（冲刺速度按步行 1.5 倍封顶，同 telegraph 的 lead）
func _pred(s: float) -> Vector2:
	return g.combat.arena_clamp(g.ppos + g.pvel.limit_length(float(g.speed) * 1.5) * s, 60.0)


func _fwd(e: Dictionary) -> Vector2:
	if g.pvel.length() > 20.0:
		return g.pvel.normalized()
	var d: Vector2 = g.ppos - e.pos
	return d.normalized() if d.length() > 1.0 else Vector2.RIGHT


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = 0.9 if _wand(e) else 1.0
	var km = kingdoms()
	if km != null and g.t >= float(e.get("lay_t", 0.0)):
		e.lay_t = g.t + 4.0
		km.add(e.pos + Vector2.from_angle(float(int(g.t * 7.0) % 628) / 100.0) * _kr(e) * 0.5, _kr(e), "boss", e, 40.0)
	if act_i(e) >= 1 and g.t >= float(e.get("call_t", 0.0)):
		e.call_t = g.t + 12.0
		summon(e, "husk", 3, 70.0)
	_breath(e, km)
	_ents(e, dt, km)
	_carpets(e, km)
	_group_pick(e, ready, dir, dist)


## ---- 招式表 [名, 冷却, 最近, 最远, 函数]
func _a() -> Array:
	return ["斩击·竖刃", 4.0, 0.0, 200.0, _a_cleave]


func _b() -> Array:
	return ["投刃·切雾", 5.0, 90.0, 620.0, _b_throw]


func _c() -> Array:
	return ["国度爆发", 9.0, 0.0, 9999.0, _c_burst]


func _d() -> Array:
	return ["黑毯", 7.0, 0.0, 420.0, _d_carpet]


func _e() -> Array:
	return ["追猎·卷毯", 8.0, 100.0, 560.0, _e_chase]


func _f() -> Array:
	return ["国度刃雨", 10.0, 0.0, 9999.0, _f_rain]


func _g() -> Array:
	return ["皇帝的猎杀", 12.0, 0.0, 9999.0, _g_hunt]


func moves(e: Dictionary) -> Array:
	var a: Array = [_a(), _b(), _c(), _d()]
	if act_i(e) >= 1:
		a = [_e(), _f()] + a
		if _wand(e):
			a.push_front(_g())
	return a


func all_moves(e: Dictionary) -> Array:
	var a: Array = [_a(), _b(), _c(), _d(), _e(), _f()]
	if _wand(e):
		a.append(_g())
	return a.map(func(m): return [m[0], m[1], 0.0, 9999.0, m[4]])


## 出招组：每 9 秒（游荡者 ×0.9）起一组，组里按顺序放（跳过放不出的），组外照常按表挑
func _groups(e: Dictionary) -> Array:
	if act_i(e) < 1:
		return [[_a(), _b(), _a()], [_c(), _d()]]
	return [[_e(), _f(), _a()], [_g(), _f(), _e()] if _wand(e) else [_f(), _c(), _b()]]


func _group_pick(e: Dictionary, ready: bool, dir: Vector2, dist: float) -> void:
	if not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false):
		return
	if not e.has("grp_t"):
		e.grp_t = g.t + 5.0
	var q: Array = e.get("grp", [])
	if q.is_empty() and g.t >= float(e.grp_t):
		var gs: Array = _groups(e)
		var gi: int = int(e.get("grp_i", 0))
		e.grp_i = gi + 1
		q = gs[gi % gs.size()].duplicate()
		e.grp_t = g.t + 9.0 * float(e.get("cd_k", 1.0))
	while not q.is_empty():
		var m: Array = q.pop_front()
		e.grp = q
		var busy: float = float((m[4] as Callable).call(e, dir, dist))
		if busy >= 0.0:
			_cd(e, str(m[0]), float(m[1]) * float(e.get("cd_k", 1.0)))
			e.busy_t = g.t + busy + MC.REC1
			return
	e.grp = []
	pick(e, ready, dir, dist)


## ---- 场上实体：大刃片（thrown）、竖刃（rise）；判定一次、画面占位
## {k, pos, vel, r, pct, t, hold, life, hit, ...}
func _ent(e: Dictionary, d: Dictionary) -> void:
	if not e.has("ents"):
		e["ents"] = []
	d.merge({"t": 0.0, "hold": 0.0, "hit": false, "vel": Vector2.ZERO}, false)
	e.ents.append(d)


func _hit_at(e: Dictionary, pos: Vector2, r: float, pct: float) -> void:
	g.tele.warn_damage({"shape": "circle", "pos": pos, "r": r + 10.0, "owner": e, "dmg": pd(e, pct), "act": "lob", "corrode": 0.0})


func _ents(e: Dictionary, dt: float, km) -> void:
	if not e.has("ents") or e.ents.is_empty():
		return
	var keep: Array = []
	for x in e.ents:
		x.t = float(x.t) + dt
		if x.t >= float(x.hold):
			x.pos += x.vel * dt
		if x.k == "thrown":
			_throw_step(e, x, km)
		if not x.hit and g.combat.ground_d(g.ppos, x.pos) < float(x.r) + 10.0:
			x.hit = true
			_hit_at(e, x.pos, float(x.r), float(x.pct))
		if x.t < float(x.hold) + float(x.life):
			keep.append(x)
	e.ents = keep


## 投刃穿过国度：切口跟着刃走（1.5 秒内这条线不算国度）；每次进出国度边界，切口两侧各弹 1 片碎刃（中弹）
func _throw_step(e: Dictionary, x: Dictionary, km) -> void:
	if km == null:
		return
	var inside := false
	for k in km.list:
		if k.kind != "carpet" and k.kind != "nursery" and x.pos.distance_to(k.pos) < float(k.r):
			inside = true
			break
	if inside:
		if x.get("cut") == null:
			x.cut = km.add_cut(x.pos, x.pos, THROW_R, 1.5)
		x.cut.b = x.pos
		x.cut.until = g.t + 1.5
	if inside != bool(x.get("was_in", false)) and int(x.get("chips", 0)) < 6:
		x.chips = int(x.get("chips", 0)) + 2
		var a: float = x.vel.angle()
		for s in [-1.0, 1.0]:
			shot(e, x.pos, a + s * PI * 0.5, 170.0, 1, 0.08, {"life": 1.6})
	x.was_in = inside


## ---- 黑毯（D / E 共用）：{a, dir, len, spd, hw, t0, front, k, hit, roll_t, risen}
func _carpets(e: Dictionary, km) -> void:
	if not e.has("cps") or e.cps.is_empty():
		return
	var keep: Array = []
	for c in e.cps:
		var el: float = g.t - float(c.t0)
		c.front = clampf(el * float(c.spd), 0.0, float(c.len))
		var b: Vector2 = c.a + c.dir * float(c.front)
		if not c.hit and c.front > 0.0 and float(c.pct) > 0.0:
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos, c.a, b)
			if g.combat.ground_d(g.ppos, q) < float(c.hw) + 8.0 and q.distance_to(b) < 40.0:
				c.hit = true
				_hit_at(e, q, float(c.hw), float(c.pct))
		if c.front >= float(c.len) and c.get("k") == null and km != null:
			c.k = km.add_strip(c.a, c.a + c.dir * float(c.len), float(c.hw), e, float(c.stay))   # 铺完当临时国度
			c.done_t = g.t
		# 卷毯（E）：铺完 0.3 秒后从尾端往回卷，卷到哪里竖刃竖到哪里
		if c.get("roll", false) and c.has("done_t") and g.t >= float(c.done_t) + 0.3:
			var rl: float = (g.t - float(c.done_t) - 0.3) * 300.0
			while float(c.risen) * 30.0 <= minf(rl, float(c.len)):
				var p: Vector2 = c.a + c.dir * (float(c.risen) * 30.0)
				_ent(e, {"k": "rise", "pos": p, "r": RISE_R, "pct": 0.08, "life": 0.35})
				c.risen = int(c.risen) + 1
			if c.get("k") != null:
				c.k.pos = c.a + c.dir * minf(rl, float(c.len))
			if rl >= float(c.len):
				if c.get("k") != null and km != null and c.k in km.list:
					km.list.erase(c.k)
				continue
		if c.has("done_t") and g.t >= float(c.done_t) + float(c.stay):
			continue
		keep.append(c)
	e.cps = keep


func _lay(e: Dictionary, a: Vector2, dir: Vector2, ln: float, spd: float, hw: float, pct: float, stay: float, roll := false) -> void:
	if not e.has("cps"):
		e["cps"] = []
	e.cps.append({"a": a, "dir": dir, "len": ln, "spd": spd, "hw": hw, "pct": pct, "t0": g.t, "front": 0.0, "k": null, "hit": false, "stay": stay, "roll": roll, "risen": 0})


## ---- 持续压力「呼吸」：它的国度每 3 秒（二幕 2.4）往外胀一圈（利刃 +20、游荡者 +35），0.6 秒后缩回；胀出的边扫到队长 6%
func _breath(e: Dictionary, km) -> void:
	if km == null:
		return
	if not e.has("br_t"):
		e.br_t = g.t + 3.0
	if g.t >= float(e.br_t):
		e.br_t = g.t + (2.4 if act_i(e) >= 1 else 3.0)
		e.br_until = g.t + 0.6
		e.br_hit = false
	if float(e.get("br_until", 0.0)) > g.t and not e.get("br_hit", false):
		var sw: float = (35.0 if _wand(e) else 20.0) * sin(PI * (1.0 - (float(e.br_until) - g.t) / 0.6))
		for k in km.list:
			if int(k.owner_id) != int(e.id) or k.kind != "boss":
				continue
			var d: float = g.combat.ground_d(g.ppos, k.pos)
			if d >= float(k.r) and d < float(k.r) + sw and not km.inside(g.ppos):
				e.br_hit = true
				_hit_at(e, g.ppos, 1.0, 0.06)
				break


## ---- A 斩击·竖刃（③）：120° 扇形 r 130（§11.2 r 100 起），预警 1.4 = 追踪 0.3 + 锁定 1.1；
## 挥刃结算后扇区腾起黑雾，5 片竖刃从雾里竖起（立 0.4 秒）再向外倒伏滑出 40
func _a_cleave(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_cone(e, dir.angle(), PI / 3.0, 130.0, 1.4, 0.20, "斩击·竖刃", {"track": 0.3})
	w.cb = func(ww):
		_fx("slash", e.pos, float(ww.ang))
		for i in 5:
			var a: float = float(ww.ang) + lerpf(-PI / 3.0 + 0.15, PI / 3.0 - 0.15, float(i) / 4.0)
			var rr: float = 95.0 if i % 2 == 0 else 120.0
			_ent(e, {"k": "rise", "pos": e.pos + Vector2.from_angle(a) * rr, "vel": Vector2.from_angle(a) * 100.0, "r": RISE_R, "pct": 0.08, "hold": 0.4, "life": 0.4, "ang": a})
	return 1.6


## ---- B 投刃·切雾（②）：瞄队长预判位置，0.8 秒（锁定 0.6，半宽 24）后掷出一片慢速大刃（260/秒，不是光束）；
## 穿过国度时切开一道口子（1.5 秒内不减攻速、不吃 ×1.5），每次进出国度边界两侧各弹 1 片碎刃
func _b_throw(e: Dictionary, _dir: Vector2, dist: float) -> float:
	var a: float = (_pred(LEAD) - e.pos).angle()
	var ln: float = clampf(dist + 260.0, 420.0, 760.0)
	var w := w_line(e, a, ln, THROW_R, 0.8, 0.0, "投刃·切雾", {"track": 0.2, "lead": LEAD})
	w.cb = func(ww):
		var v: Vector2 = Vector2.from_angle(float(ww.ang)) * 260.0
		_ent(e, {"k": "thrown", "pos": e.pos + v.normalized() * float(e.r), "vel": v, "r": THROW_R, "pct": 0.18, "life": float(ww.len) / 260.0, "ang": float(ww.ang)})
	return 1.0


## ---- C 国度爆发（①）：离队长最近的 6 块它的国度依次（0.15 秒）腾起刃林，圈 = 国度本身（利刃 0.9、游荡者 1.1）；
## 爆完每块 4 片刃沿圈的切线贴地滑出（大弹）
func _c_burst(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var mine: Array = km.list.filter(func(k): return int(k.owner_id) == int(e.id) and k.kind == "boss")
	if mine.is_empty():
		return -1.0
	mine.sort_custom(func(x, y): return x.pos.distance_to(g.ppos) < y.pos.distance_to(g.ppos))
	var dur: float = 1.1 if _wand(e) else 0.9
	var i := 0
	for k in mine.slice(0, 6):
		var kp: Vector2 = k.pos
		var kr: float = k.r
		var nm: String = "国度爆发" if i == 0 else ""
		later(e, 0.15 * i, _burst_one.bind(e, kp, kr, dur, nm))
		i += 1
	return 1.2 + 0.15 * i


func _burst_one(e: Dictionary, kp: Vector2, kr: float, dur: float, nm: String) -> void:
	var w := w_circle(e, kp, kr, dur, 0.15, nm)
	w.cb = func(_ww): _burst_slide(e, kp, kr)
	_fx("erupt", kp, kr, dur)


func _burst_slide(e: Dictionary, kp: Vector2, kr: float) -> void:
	var a0: float = (g.ppos - kp).angle()
	for j in 4:
		var a: float = a0 + TAU * float(j) / 4.0 + PI / 4.0
		shot(e, kp + Vector2.from_angle(a) * kr, a + PI * 0.5, 150.0, 2, 0.08, {"life": 1.8})


## ---- D 黑毯（④）：以自身为心，四条黑雾地毯（宽 70）呈十字向外铺（150/秒、长 330），一条正对队长；
## 毯与毯之间的楔形空地 = 出口，先标 0.9 秒；毯头扫到 12%，铺完的毯当 4 秒临时国度
func _d_carpet(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (_pred(0.6) - e.pos).angle()
	var c: Vector2 = e.pos
	for j in 4:
		w_line(e, a0 + PI * 0.5 * j, 330.0, 35.0, 0.9, 0.0, "黑毯" if j == 0 else "", {"lock": j == 0, "fx_carpet": true})
	later(e, 0.9, _cross.bind(e, c, a0))
	return 1.4


func _cross(e: Dictionary, c: Vector2, a0: float) -> void:
	for j in 4:
		_lay(e, c, Vector2.from_angle(a0 + PI * 0.5 * j), 330.0, 150.0, 35.0, 0.12, 4.0)


## ---- E 追猎·卷毯（②）：朝队长预判位置冲 300（半宽 30，0.8 / 锁定 0.6），身后拖一条黑毯；
## 冲完黑毯从尾端往回卷（300/秒），卷到哪里竖刃竖到哪里（侧走一步就躲开）
func _e_chase(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (_pred(LEAD) - e.pos).angle()
	var w := w_stab(e, a, 300.0, 60.0, 0.8, 0.22, "追猎·卷毯", {"track": 0.2, "lead": LEAD})
	w.cb = func(ww):
		var dv: Vector2 = Vector2.from_angle(float(ww.ang))
		_lay(e, e.pos, dv, 300.0, 2000.0, 30.0, 0.0, 3.0, true)
	return 1.8


## ---- F 国度刃雨（① 小圈群）：刃只落在国度里——离队长最近的 5 块（含黑毯不算），每块 6 个落点 r 24，0.15 秒错开；
## 队长站在某块国度里时，那块的第一个落点就落在队长脚下（预判 0.3 秒）
func _f_rain(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var ks: Array = km.list.filter(func(k): return k.kind == "boss" or k.kind == "chaos")
	if ks.is_empty():
		return -1.0
	ks.sort_custom(func(x, y): return x.pos.distance_to(g.ppos) < y.pos.distance_to(g.ppos))
	var n := 0
	var first := true
	for k in ks.slice(0, 5):
		var kp: Vector2 = k.pos
		var kr: float = k.r
		for j in 6:
			var p: Vector2 = kp + Vector2.from_angle(TAU * float(j) / 6.0 + float(n) * 0.7) * kr * (0.35 if j % 2 == 0 else 0.7)
			if j == 0 and g.ppos.distance_to(kp) < kr:
				p = _pred(0.3)
			var nm: String = "国度刃雨" if first else ""
			first = false
			later(e, 0.15 * j + 0.05 * n, func():
				w_circle(e, p, 24.0, 0.7, 0.10, nm, {"lock": false})
				_fx("rain", p, 24.0, 0.7))
		n += 1
	return 1.3 + 0.05 * n


## ---- G 皇帝的猎杀（游荡者，① 链）：在队长前进方向依次铺 3 块国度（自动连片）；游荡者「呼吸」一次，整条国度链同时喷刃
func _g_hunt(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var f: Vector2 = _fwd(e)
	var base: Vector2 = g.ppos
	var pts: Array = []
	for k in 3:
		pts.append(g.combat.arena_clamp(base + f * (70.0 + 120.0 * k), 60.0))
	for k in 3:
		var p: Vector2 = pts[k]
		later(e, 0.25 * k, func(): km.add(p, _kr(e), "boss", e, 40.0))
	later(e, 0.75, _hunt_burst.bind(e, pts))
	return 2.0


func _hunt_burst(e: Dictionary, pts: Array) -> void:
	for k in pts.size():
		w_circle(e, pts[k], _kr(e), 0.9, 0.15, "皇帝的猎杀" if k == 0 else "", {"lock": k == 0})
		_fx("erupt", pts[k], _kr(e), 0.9)


## 主轴：它的国度碎掉（mech_kingdom._break 通知）；6 秒内碎 3 块 → 踉跄 2.5 秒、受伤 ×1.5
func on_kingdom_break(e: Dictionary) -> void:
	var hist: Array = e.get("kb_hist", [])
	hist.append(g.t)
	hist = hist.filter(func(t): return g.t - float(t) <= 6.0)
	e["kb_hist"] = hist
	if hist.size() >= 3:
		e.kb_hist = []
		g.combat.start_break(e, 2.5)
		vuln(e, 2.5, 1.5 / maxf(0.01, Bal.v("boss/break_mult", 1.4)))


## ---- 占位画面（fx-declutter 换正式特效）：竖刃 = 竖立的白芯黑刃，大刃片 = 旋转的黑菱形，黑毯 = 铺开的暗带，呼吸 = 国度外一圈薄雾
func draw(e: Dictionary, cv) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.blade_draw(e)   # 正式特效（themes/sami/mech/mech_fx.gd，docs/401 §11）；没有 fx 机制时画下面的占位
		return
	var cb: Color = col(e)
	for c in e.get("cps", []):
		if float(c.front) > 0.0 and c.get("k") == null:
			var b: Vector2 = c.a + c.dir * float(c.front)
			cv.draw_line(c.a, b, Color(0.06, 0.06, 0.08, 0.55), float(c.hw) * 2.0)
			cv.draw_circle(b, float(c.hw), Color(0.1, 0.1, 0.13, 0.7))
	for x in e.get("ents", []):
		var up: float = clampf(float(x.t) / maxf(0.05, float(x.hold)), 0.0, 1.0) if float(x.hold) > 0.0 else 1.0
		if x.k == "rise":
			var hgt: float = 30.0 * up
			var p: Vector2 = x.pos
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(0, -hgt - 6), p + Vector2(7, 0)]), Color(cb.r, cb.g, cb.b, 0.95))
			cv.draw_line(p + Vector2(0, -2), p + Vector2(0, -hgt), Color(0.95, 0.97, 1.0, 0.9), 2.0)
			cv.draw_arc(p, float(x.r), 0.0, TAU, 16, Color(0.86, 0.88, 0.92, 0.5), 1.5)
		else:
			var rot: float = float(x.t) * 14.0
			var r: float = float(x.r)
			var pts := PackedVector2Array()
			for j in 4:
				pts.append(x.pos + Vector2.from_angle(rot + PI * 0.5 * j) * (r * (1.3 if j % 2 == 0 else 0.45)))
			cv.draw_colored_polygon(pts, Color(cb.r, cb.g, cb.b, 0.95))
			cv.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.86, 0.88, 0.92, 0.9), 2.0)
			cv.draw_circle(x.pos, 4.0, Color(0.96, 0.97, 1.0))
	if float(e.get("br_until", 0.0)) > g.t:
		var km = kingdoms()
		if km != null:
			var sw: float = (35.0 if _wand(e) else 20.0) * sin(PI * (1.0 - (float(e.br_until) - g.t) / 0.6))
			for k in km.list:
				if int(k.owner_id) == int(e.id) and k.kind == "boss":
					cv.draw_arc(k.pos, float(k.r) + sw, 0.0, TAU, 40, Color(0.2, 0.2, 0.25, 0.45), maxf(2.0, sw * 0.5))


## 预警画法：有 fx 机制时挂 skin sami_blade，通用描边 / 填充跳过（telegraph_draw.quiet），由 mech_fx 画裂缝 + 渗雾 + 刃尖（docs/401 §12）
func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	if g.mech("fx") != null:
		d["skin"] = "sami_blade"
	return super(e, shape, dur, d)


## 特效挂钩：只画，不改玩法状态
func _fx(kind: String, p: Vector2, a := 0.0, b := 0.0) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.blade_event(kind, p, a, b)


## 机器人主轴（同前）：没有 axis_do 覆写 = 走 mech_kingdom.bot_score（不站国度）+ 通用躲招
