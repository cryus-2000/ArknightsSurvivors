## “邪魔的利刃”（3:30）/ “邪魔的利刃”，游荡者（7:00）：招式按 docs/393 §11.2（11-26 改写：伤人的都是 Boss 本体，国度只做场地）+ §12.4 威慑改数。
## 原作（PRTS）：远程、攻击范围 2.4 / 2.0 格；对国度里的单位攻击倍率 250%；国度本身只让我方攻速 −50。B 站 BV1ru41157cJ 166.6–167.2 秒：本体聚暗红漩涡 → 红色斩光。
## 主轴「裂国度」不变：它一路在身边铺国度（利刃 r 70、游荡者 r 90，每 4 秒一块；国度里的队员攻速 −50%、挨它的招 ×1.5——mech_foes.player_hit_mult）；
## 二幕起每 12 秒召 3 只染污躯壳；在国度里 / 边缘击杀让裂纹长，6 秒内碎 3 块 → 踉跄 2.5 秒、受伤 ×1.5。游荡者国度连片 220、碎一块相连的裂纹 +50%（mech_kingdom）。
## 国度里不冒刃、不爆、不扫边：所有伤害都从本体（挥刃、投刃、冲斩、从雾里钻出来斩、红漩斩光）出来。
## 招：一幕 A 斩击·横扫 ③ / B 投刃·切雾 ② / C 雾中突袭 ① / D 黑毯·回旋 ④；二幕加 E 追猎·折返 ② ×2 / F 国度猎斩 ② ×3；游荡者再加 G 皇帝的猎杀 ② 折线，整体冷却 ×0.9。
## 持续压力「呼吸」：它的国度每 3 秒（二幕 2.4）往外胀一圈（利刃 +40、游荡者 +60），0.6 秒后缩回，不伤人——胀进来就是站进了国度。
## 11-28 表现改版（docs/393 §14.4）：主要表现 = 国度 + 斩击；常驻「碎刃」与各招的月牙弹扇 / 弹圈全部删掉，只在刀口 / 斩光尽头溅 2–3 片短程碎屑（chips）。
## A 大横斩按概念图 fm_b1 放大到 r 300，出招前先沉进国度、从黑雾里冲出来再斩（国度是出招起点）；E 改三段突进斩；D 改旋身斩 r 200。
## 位移「雾行」：每 9 秒沉进国度、雾下黑影滑到另一处（离队长 ≥250、跨度 ≥300）钻出，原地旋斩 r 90。
## 出招组（每幕 2）：一幕「斩投」A→B→A、「突袭」C→D；二幕「追猎」E→F→A、「猎斩」F→C→B（游荡者换「猎杀」G→F→E）。
## 画面全是占位（draw）：沉入 = 本体位置画黑影椭圆 + 露出雾面的刃尖；最终特效交 fx-declutter。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const LEAD := 0.35        # 预判秒数（落点类）
const THROW_R := 24.0     # 投刃大刃片半宽（§11.2 半宽 24，§12.4 可见半径 24）
const SWEEP_R := 300.0    # A 大横斩半径（11-28 协调人：按概念图 fm_b1 一刀扫过小半个屏幕；120° r 300 ≈ 10% 屏）
const SWEEP_T := 2.8      # A 预警总长：120° r 300 → 半宽 260，锁定 ≥ (260 + 12) / 105 + 0.1 = 2.69（95 §0.2 / 359 §2.3）；沉入 + 滑行 + 冲出 + 举刃都算在里面
const CHIP_SPD := 190.0   # 刀口碎屑：短程（约 200 px）、低伤，只是余波
const GLIDE := 700.0      # 雾下黑影滑行速度


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


func _sunk(e: Dictionary) -> bool:
	return float(e.get("sunk_until", 0.0)) > g.t


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	e.cd_k = (0.9 if _wand(e) else 1.0) * Bal.v("boss/cd_x_" + str(e.type), 1.0)   # 11-26 中期加强：出招间隔倍率
	var km = kingdoms()
	if km != null and g.t >= float(e.get("lay_t", 0.0)) and not _sunk(e):
		e.lay_t = g.t + 4.0
		km.add(e.pos + Vector2.from_angle(float(int(g.t * 7.0) % 628) / 100.0) * _kr(e) * 0.5, _kr(e), "boss", e, 40.0)
	if act_i(e) >= 1 and g.t >= float(e.get("call_t", 0.0)):
		e.call_t = g.t + 12.0
		summon(e, "husk", 3, 70.0)
	_glide(e, dt)
	_breath(e, km)
	_ents(e, dt, km)
	_carpets(e, km)
	_mistwalk(e, ready, km)
	_group_pick(e, ready, dir, dist)


## ---- 招式表 [名, 冷却, 最近, 最远, 函数]
func _a() -> Array:
	return ["斩击·横扫", 4.0, 0.0, 700.0, _a_sweep]   # 11-28：会先潜进离队长最近的国度再冲出来，射程放到 700


func _b() -> Array:
	return ["投刃·切雾", 5.0, 90.0, 900.0, _b_throw]


func _c() -> Array:
	return ["雾中突袭", 9.0, 180.0, 900.0, _c_ambush]


func _d() -> Array:
	return ["黑毯·回旋", 7.0, 0.0, 9999.0, _d_carpet]


func _e() -> Array:
	return ["追猎·折返", 8.0, 100.0, 700.0, _e_chase]


func _f() -> Array:
	return ["国度猎斩", 10.0, 0.0, 9999.0, _f_hunt]


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
	if not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false) or _sunk(e):
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


## ---- 余波碎屑（11-28，docs/393 §14.1）：刀口 / 斩光尽头溅出 n 片短程碎刃，沿 ang 两侧 ±spread 散开；不瞄队长，飞约 200 就消失
func _chips(e: Dictionary, p: Vector2, ang: float, n: int, spread := 0.5) -> void:
	for i in n:
		var u: float = 0.0 if n == 1 else (float(i) / float(n - 1) * 2.0 - 1.0)
		shot(e, p, ang + u * spread, CHIP_SPD, 1, 0.05, {"life": 1.05})


## 离点 p 最近的一块国度（它自己的优先，其次混沌国度）；没有就返回 {}
func _near_kingdom(e: Dictionary, p: Vector2, km) -> Dictionary:
	if km == null:
		return {}
	var best: Dictionary = {}
	var bd := INF
	for k in km.list:
		if k.kind != "boss" and k.kind != "chaos":
			continue
		var d: float = (k.pos as Vector2).distance_to(p) - (60.0 if int(k.owner_id) == int(e.id) else 0.0)
		if d < bd:
			bd = d
			best = k
	return best


## ---- 沉入 / 雾下滑行 / 钻出：e.glide = {pts: [途经点…], spd}；滑行期间每帧直接改 e.pos（同克雷松闪现的写法），
## 本体在 sunk_until 前画成黑影（draw），出招表不选新招
func _sink(e: Dictionary, dur: float) -> void:
	e.sunk_until = maxf(float(e.get("sunk_until", 0.0)), g.t + dur)


func _glide_to(e: Dictionary, pts: Array, spd: float) -> void:
	e.glide = {"pts": pts.duplicate(), "spd": spd}


func _glide(e: Dictionary, dt: float) -> void:
	var gl = e.get("glide")
	if gl == null:
		return
	var pts: Array = gl.pts
	var mv: float = float(gl.spd) * dt
	while mv > 0.0 and not pts.is_empty():
		var q: Vector2 = pts[0]
		var d: float = e.pos.distance_to(q)
		if d <= mv:
			e.pos = q
			mv -= d
			pts.pop_front()
		else:
			e.pos = e.pos.move_toward(q, mv)
			mv = 0.0
	e.kb = Vector2.ZERO
	if pts.is_empty():
		e.erase("glide")


func _mine(e: Dictionary, km) -> Array:
	if km == null:
		return []
	return km.list.filter(func(k): return int(k.owner_id) == int(e.id) and k.kind == "boss")


## ---- 场上实体：大刃片（thrown）、刀光（slash / upslash / spin / redslash，纯画面）、红漩（vortex，纯画面）；判定一次、画面占位
## {k, pos, vel, r, pct, t, hold, life, hit, ...}
func _ent(e: Dictionary, d: Dictionary) -> void:
	if not e.has("ents"):
		e["ents"] = []
	d.merge({"t": 0.0, "hold": 0.0, "hit": false, "vel": Vector2.ZERO, "pct": 0.0}, false)
	e.ents.append(d)


func _hit_at(e: Dictionary, pos: Vector2, r: float, pct: float, src := "") -> void:
	var hp0: float = g.hp
	g.tele.warn_damage({"shape": "circle", "pos": pos, "r": r + 10.0, "owner": e, "dmg": pd(e, pct), "act": "lob", "corrode": 0.0, "mv": src})
	if src != "" and g.hp < hp0:
		var hl: Dictionary = e.get("hit_log", {})
		hl[src] = float(hl.get(src, 0.0)) + (hp0 - g.hp) / maxf(1.0, g.max_hp)   # 测试台对账：脚本自己判定的几种伤害各吃了多少（占最大生命）
		e["hit_log"] = hl


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
		if float(x.pct) > 0.0 and not x.hit and g.combat.ground_d(g.ppos, x.pos) < float(x.r) + 10.0:
			x.hit = true
			_hit_at(e, x.pos, float(x.r), float(x.pct), str(x.k))
		if x.t < float(x.hold) + float(x.life):
			keep.append(x)
	e.ents = keep


## 投刃穿过国度：切口跟着刃走（1.5 秒内这条线不算国度）；每次进出国度边界，切口两侧各崩 1 片碎刃（中弹）
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


## 场上实体生效期间挂一条只画不判的预警线（大刃片飞行路线）：玩家本来看得见实体，
## 测试机器人只读 g.warns / 弹，不挂它会无视这些实体，承伤被高估（11-25 测试台）
func _live(e: Dictionary, a: Vector2, ang: float, ln: float, hw: float, dur: float) -> void:
	var w := w_line(e, ang, ln, hw, dur, 0.0, "", {"lock": false})
	w.pos = a


## ---- 黑毯（D / E 共用，11-26 起只是场地）：{a, dir, len, spd, hw, t0, front, k}；铺完当临时国度
func _carpets(e: Dictionary, km) -> void:
	if not e.has("cps") or e.cps.is_empty():
		return
	var keep: Array = []
	for c in e.cps:
		var el: float = g.t - float(c.t0)
		c.front = clampf(el * float(c.spd), 0.0, float(c.len))
		if c.front >= float(c.len) and c.get("k") == null and km != null:
			c.k = km.add_strip(c.a, c.a + c.dir * float(c.len), float(c.hw), e, float(c.stay))
			c.done_t = g.t
		if c.has("done_t") and g.t >= float(c.done_t) + float(c.stay):
			continue
		keep.append(c)
	e.cps = keep


func _lay(e: Dictionary, a: Vector2, dir: Vector2, ln: float, spd: float, hw: float, stay: float) -> void:
	if not e.has("cps"):
		e["cps"] = []
	e.cps.append({"a": a, "dir": dir, "len": ln, "spd": spd, "hw": hw, "t0": g.t, "front": 0.0, "k": null, "stay": stay})


## ---- 持续压力「呼吸」：它的国度每 3 秒（二幕 2.4）往外胀一圈（利刃 +40、游荡者 +60），0.6 秒后缩回；不伤人，
## 胀的时候真的把国度半径加大（攻速惩罚、×1.5 跟着变），缩回原半径 r0
func _breath(e: Dictionary, km) -> void:
	if km == null:
		return
	if not e.has("br_t"):
		e.br_t = g.t + 3.0
	if g.t >= float(e.br_t):
		e.br_t = g.t + (2.4 if act_i(e) >= 1 else 3.0)
		e.br_until = g.t + 0.6
	var sw := 0.0
	if float(e.get("br_until", 0.0)) > g.t:
		sw = (60.0 if _wand(e) else 40.0) * sin(PI * (1.0 - (float(e.br_until) - g.t) / 0.6))
	for k in _mine(e, km):
		if not k.has("r0"):
			k.r0 = k.r
		k.r = float(k.r0) + sw


## ---- 位移「雾行」（不算招，§12.4）：每 9 秒沉进国度 0.4 秒，黑影滑到另一处（离队长 ≥250、离自己 ≥300；优先它自己的国度），
## 钻出时原地旋斩 r 90（0.8 / 0.7，12%）
func _mistwalk(e: Dictionary, ready: bool, km) -> void:
	if not e.has("mw_t"):
		e.mw_t = g.t + 9.0
	if g.t < float(e.mw_t) or not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false) or _sunk(e):
		return
	e.mw_t = g.t + 9.0
	var to := Vector2.INF
	for k in _mine(e, km):
		if k.pos.distance_to(g.ppos) >= 250.0 and k.pos.distance_to(e.pos) >= 300.0:
			to = k.pos
			break
	if to == Vector2.INF:
		var side: Vector2 = (e.pos - g.ppos).normalized().rotated(PI * 0.5 * (1.0 if int(g.t) % 2 == 0 else -1.0))
		to = g.combat.arena_clamp(g.ppos + side * 320.0, 80.0)
	var d: float = e.pos.distance_to(to)
	var travel: float = d / GLIDE
	_sink(e, 0.4 + travel)
	later(e, 0.4, func(): _glide_to(e, [to], GLIDE))
	later(e, 0.4 + travel, func():
		var w := w_self(e, 90.0, 0.8, 0.12, "")
		w.cb = func(_ww): _ent(e, {"k": "spin", "pos": e.pos, "r": 90.0, "life": 0.3}))
	e.busy_t = g.t + 0.4 + travel + 1.0


## ---- A 斩击·横扫（③，11-28 改大横斩）：先沉进脚下的雾（0.4 秒），黑影滑到离队长最近的那块国度（≤1.4 秒），
## 再从黑雾里**冲出来**（0.3 秒冲到斩点 O，O = 从那块国度朝队长方向、离队长 200 处），举刃，一刀横扫 120° r 300。
## 扇形一开始就画在 O 上（不跟本体），总长 2.8 秒（锁定 2.7）；滑行太远（国度离队长 >700）就不滑，原地沉下去直接冲。
## 结算后刀口两端各溅 1–2 片碎屑
func _a_sweep(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	var k: Dictionary = _near_kingdom(e, g.ppos, km)
	var fog: Vector2 = e.pos
	if not k.is_empty() and (k.pos as Vector2).distance_to(g.ppos) <= 700.0:
		fog = k.pos
	var to_p: Vector2 = g.ppos - fog
	var o: Vector2 = fog if to_p.length() <= 200.0 else g.combat.arena_clamp(g.ppos - to_p.normalized() * 200.0, 60.0)
	var ang: float = (g.ppos - o).angle()
	var w := w_cone(e, ang, PI / 3.0, SWEEP_R, SWEEP_T, 0.24, "斩击·横扫", {"track": 0.1, "follow": false, "pos": o})
	_sink(e, 1.8)
	later(e, 0.4, func(): _glide_to(e, [fog], maxf(GLIDE, e.pos.distance_to(fog) / 1.4)))
	later(e, 1.8, func():
		e.erase("glide")
		e.pos = fog
		e.sunk_until = g.t
		_ent(e, {"k": "burst", "pos": fog, "ang": (o - fog).angle(), "r": 40.0, "life": 0.35})
		_glide_to(e, [o], maxf(600.0, fog.distance_to(o) / 0.3)))
	w.cb = func(ww):
		e.erase("glide")
		e.pos = o
		_ent(e, {"k": "slash", "pos": o, "ang": float(ww.ang), "r": SWEEP_R, "life": 0.35})
		for sd in [-1.0, 1.0]:
			var tip: Vector2 = o + Vector2.from_angle(float(ww.ang) + sd * PI / 3.0) * SWEEP_R
			_chips(e, tip, float(ww.ang) + sd * PI / 3.0 + sd * PI * 0.5, 2 if sd > 0.0 else 1, 0.35)
	return SWEEP_T + 0.2


## ---- B 投刃·切雾（②）：瞄队长预判位置，0.8 秒（锁定 0.6，半宽 24）后掷出一片慢速大刃（260/秒，飞到 900）；
## 穿过国度时切开一道口子（1.5 秒内不减攻速、不吃 ×1.5），每次进出国度边界两侧各崩 1 片碎刃
func _b_throw(e: Dictionary, _dir: Vector2, _dist: float) -> float:
	var a: float = (_pred(LEAD) - e.pos).angle()
	var ln := 900.0
	var w := w_line(e, a, ln, THROW_R, 0.8, 0.0, "投刃·切雾", {"track": 0.2, "lead": LEAD})
	w.cb = func(ww):
		var v: Vector2 = Vector2.from_angle(float(ww.ang)) * 260.0
		_ent(e, {"k": "thrown", "pos": e.pos + v.normalized() * float(e.r), "vel": v, "r": THROW_R, "pct": 0.18, "life": float(ww.len) / 260.0, "ang": float(ww.ang)})
		_live(e, e.pos, float(ww.ang), float(ww.len), THROW_R, float(ww.len) / 260.0)
	return 1.0


## ---- C 雾中突袭（①）：本体沉进国度 0.4 秒 → 雾下黑影朝预警圈滑（≥700/秒）→ 从地下钻出上撩一刀。
## 圈 r 110 画在队长 1.0 秒后的预判位置，预警 1.3（锁定 ≥1.26）；滑行距离封顶 620。11-28：删钻出时的 16 发弹圈，改成钻出后接一记横斩 120° r 180
func _c_ambush(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var p: Vector2 = _pred(1.0)
	var off: Vector2 = p - e.pos
	if off.length() > 620.0:
		p = e.pos + off.normalized() * 620.0
	var w := w_circle(e, p, 110.0, 1.3, 0.18, "雾中突袭", {"lock": false})
	_sink(e, 1.3)
	later(e, 0.4, func(): _glide_to(e, [p], maxf(GLIDE, e.pos.distance_to(p) / 0.85)))
	w.cb = func(_ww):
		e.pos = p
		e.erase("glide")
		e.sunk_until = g.t
		_ent(e, {"k": "upslash", "pos": p, "r": 110.0, "life": 0.35})
		var w2 := w_cone(e, (g.ppos - p).angle(), PI / 3.0, 180.0, 1.7, 0.18, "", {"track": 0.15})   # 钻出后接横斩（120° r 180，锁定 ≥1.7）
		w2.cb = func(ww2):
			_ent(e, {"k": "slash", "pos": e.pos, "ang": float(ww2.ang), "r": 180.0, "life": 0.3})
			_chips(e, e.pos + Vector2.from_angle(float(ww2.ang) + PI / 3.0) * 180.0, float(ww2.ang) + PI * 0.8, 2, 0.3)
	return 3.4


## ---- D 黑毯·回旋（11-28 改）：删掉两圈斩波弹。本体把刃插进地里原地旋身一圈：旋身斩 r 200（本体圈，预警 2.2，锁定 ≥ 212 / 105 + 0.1 = 2.12）；
## 同时四条黑毯（宽 90、长 330）十字铺开，只当场地（铺完 4 秒国度）；斩完四条黑毯末端各溅 2 片碎屑
func _d_carpet(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (_pred(0.6) - e.pos).angle()
	var c: Vector2 = e.pos
	for j in 4:
		w_line(e, a0 + PI * 0.5 * j, 330.0, 45.0, 0.9, 0.0, "", {"lock": false})
	var w := w_self(e, 200.0, 2.2, 0.16, "黑毯·回旋")
	later(e, 0.9, func():
		for j in 4:
			_lay(e, c, Vector2.from_angle(a0 + PI * 0.5 * j), 330.0, 150.0, 45.0, 4.0))
	w.cb = func(_ww):
		_ent(e, {"k": "spin", "pos": e.pos, "r": 200.0, "life": 0.4})
		for j in 4:
			var dv: Vector2 = Vector2.from_angle(a0 + PI * 0.5 * j)
			_chips(e, c + dv * 330.0, dv.angle(), 2, 0.4)
	return 2.4


## ---- E 追猎·折返（11-28 改三段突进斩）：连冲三段，每段都重新瞄队长预判位置，长 300–420（半宽 36；第一段 0.8 / 锁定 0.6，后两段 0.6 / 0.6；
## 冲速 sqrt(1800 × 长) ≈ 735–870 px/秒），段间停 0.35 秒；每段身后拖一条黑毯（场地 3 秒）；第三段冲完收尾横斩 120° r 180（锁定 ≥1.7），刀口溅 3 片
func _e_chase(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_dash_seg(e, 0)
	return 0.8 + 0.6 * 2 + 0.35 * 2 + 1.8


func _dash_seg(e: Dictionary, i: int) -> void:
	if e.get("dead", false):
		return
	var tgt: Vector2 = _pred(LEAD)
	var a: float = (tgt - e.pos).angle()
	var ln: float = clampf(e.pos.distance_to(tgt) + 60.0, 300.0, 420.0)
	var w := w_stab(e, a, ln, 72.0, 0.8 if i == 0 else 0.6, 0.22 if i == 0 else 0.16, "追猎·折返" if i == 0 else "", {"track": 0.2 if i == 0 else 0.0, "lead": LEAD})
	var from: Vector2 = e.pos
	w.cb = func(ww):
		_lay(e, from, Vector2.from_angle(float(ww.ang)), float(ww.len), 1600.0, 36.0, 3.0)
		if i < 2:
			later(e, 0.35, func(): _dash_seg(e, i + 1))
		else:
			later(e, 0.35, func():
				var w2 := w_cone(e, (g.ppos - e.pos).angle(), PI / 3.0, 180.0, 1.7, 0.18, "", {"track": 0.15})
				w2.cb = func(ww2):
					_ent(e, {"k": "slash", "pos": e.pos, "ang": float(ww2.ang), "r": 180.0, "life": 0.3})
					_chips(e, e.pos + Vector2.from_angle(float(ww2.ang)) * 180.0, float(ww2.ang), 3, 0.5))


## ---- F 国度猎斩（② ×3）：沉进国度，依次从离队长最近的 3 块国度里钻出（每块 1.3 秒）：钻出时刃尖聚一团暗红漩涡（0.7 秒预警，
## 锁定 0.5，半宽 26，长 900——11-28 从 700 提到 900、删掉斩光后的 7 发月牙扇），然后朝队长打出一道红色斩光，尽头溅 2 片碎屑；再沉下去，黑影滑到下一块
func _f_hunt(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var ks: Array = km.list.filter(func(k): return (k.kind == "boss" or k.kind == "chaos") and k.pos.distance_to(g.ppos) > 140.0)
	if ks.is_empty():
		return -1.0
	ks.sort_custom(func(x, y): return x.pos.distance_to(g.ppos) < y.pos.distance_to(g.ppos))
	var pts: Array = ks.slice(0, 3).map(func(k): return k.pos)
	var n: int = pts.size()
	for i in n:
		var p: Vector2 = pts[i]
		var t0: float = 0.3 + 1.3 * i
		later(e, t0 - 0.3, func():
			_sink(e, 0.3)
			_glide_to(e, [p], maxf(GLIDE, e.pos.distance_to(p) / 0.28)))
		later(e, t0, func():
			e.pos = p
			e.erase("glide")
			e.sunk_until = g.t
			_ent(e, {"k": "vortex", "pos": p, "r": 22.0, "life": 0.7})
			var w := w_line(e, (g.ppos - p).angle(), 900.0, 52.0, 0.7, 0.14, "国度猎斩" if i == 0 else "", {"track": 0.2, "pos": p})
			w.cb = func(ww):
				_ent(e, {"k": "redslash", "pos": p, "ang": float(ww.ang), "r": 900.0, "life": 0.25})
				_chips(e, p + Vector2.from_angle(float(ww.ang)) * 900.0, float(ww.ang) + PI, 2, 0.6))
	_sink(e, 0.3)
	return 0.3 + 1.3 * n


## ---- G 皇帝的猎杀（游荡者，② 折线）：「呼吸」一次，在队长前进方向铺 4 块国度（r 140，场地）；然后本体沿 4 块中心一路冲斩过去
## （800/秒，整条折线一起预警，半宽 40；每段的结算时刻 = 本体走到这段末端的时刻，锁定 ≥0.6）
func _g_hunt(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var km = kingdoms()
	if km == null:
		return -1.0
	var f: Vector2 = _fwd(e)
	var pts: Array = []
	for k in 4:
		pts.append(g.combat.arena_clamp(g.ppos + f * (-150.0 + 170.0 * k), 60.0))
	for k in 4:
		var p: Vector2 = pts[k]
		later(e, 0.15 * k, func(): km.add(p, 140.0, "boss", e, 12.0))
	e.br_t = g.t
	var prev: Vector2 = e.pos
	var acc := 0.0
	for k in 4:
		var q: Vector2 = pts[k]
		var ln: float = maxf(40.0, prev.distance_to(q))
		acc += ln / 800.0
		var w := w_line(e, (q - prev).angle(), ln, 80.0, 0.9 + acc, 0.20, "皇帝的猎杀" if k == 0 else "", {"pos": prev, "lock": k == 0})
		var qq: Vector2 = q
		w.cb = func(_ww):
			_ent(e, {"k": "spin", "pos": qq, "r": 50.0, "life": 0.25})
			_chips(e, qq, (qq - g.ppos).angle(), 2, 0.6)   # 11-28：每块国度中心的 10 发弹圈 → 2 片碎屑
		prev = q
	later(e, 0.9, func(): _glide_to(e, pts, 800.0))
	return 1.2 + acc


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


## ---- 占位画面（fx-declutter 换正式特效）：黑毯 = 铺开的暗带；大刃片 = 旋转的黑菱形；刀光 = 暗红月牙；红漩 = 暗红螺旋；
## 沉入 = 黑影椭圆 + 一截刃尖；呼吸 = 国度半径本身在胀缩（mech_kingdom 照常画）
func draw(e: Dictionary, cv) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.blade_draw(e)   # 正式特效（themes/sami/mech/mech_fx.gd，docs/401 §11）；没有 fx 机制时画下面的占位
		return
	var cb: Color = col(e)
	var red := Color(0.62, 0.08, 0.12)
	for c in e.get("cps", []):
		if float(c.front) > 0.0 and c.get("k") == null:
			var b: Vector2 = c.a + c.dir * float(c.front)
			cv.draw_line(c.a, b, Color(0.06, 0.06, 0.08, 0.45), float(c.hw) * 2.0)
	if _sunk(e):
		cv.draw_set_transform(e.pos, 0.0, Vector2(1.0, 0.45))
		cv.draw_circle(Vector2.ZERO, float(e.r) * 1.3, Color(0.03, 0.03, 0.05, 0.85))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		cv.draw_line(e.pos + Vector2(4, -2), e.pos + Vector2(10, -20), Color(0.9, 0.92, 0.96, 0.9), 2.0)
	for x in e.get("ents", []):
		var fade: float = clampf(1.0 - float(x.t) / maxf(0.05, float(x.life)), 0.0, 1.0)
		match str(x.k):
			"thrown":
				var rot: float = float(x.t) * 14.0
				var r: float = float(x.r)
				var pts := PackedVector2Array()
				for j in 4:
					pts.append(x.pos + Vector2.from_angle(rot + PI * 0.5 * j) * (r * (1.3 if j % 2 == 0 else 0.45)))
				cv.draw_colored_polygon(pts, Color(cb.r, cb.g, cb.b, 0.95))
				cv.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.86, 0.88, 0.92, 0.9), 2.0)
			"slash":
				cv.draw_arc(x.pos, float(x.r) * 0.85, float(x.ang) - PI / 3.0, float(x.ang) + PI / 3.0, 24, Color(red.r, red.g, red.b, 0.8 * fade), 10.0)
			"upslash", "spin":
				cv.draw_arc(x.pos, float(x.r) * 0.7, 0.0, TAU, 32, Color(red.r, red.g, red.b, 0.75 * fade), 8.0)
			"vortex":
				for j in 3:
					var a0: float = float(x.t) * 9.0 + TAU * j / 3.0
					cv.draw_arc(x.pos + Vector2(0, -24), 6.0 + 5.0 * j, a0, a0 + 2.2, 10, Color(0.75, 0.1, 0.15, 0.9), 2.5)
			"burst":   # 从黑雾里冲出来：一团向冲出方向喷开的黑雾（占位）
				for j in 5:
					var q: Vector2 = x.pos + Vector2.from_angle(float(x.ang) + (j - 2) * 0.35) * (20.0 + 50.0 * (1.0 - fade))
					cv.draw_circle(q, 14.0 * fade + 4.0, Color(0.04, 0.04, 0.06, 0.7 * fade))
			"redslash":
				cv.draw_line(x.pos, x.pos + Vector2.from_angle(float(x.ang)) * float(x.r), Color(0.9, 0.12, 0.15, 0.85 * fade), 6.0)


## 机器人主轴（同前）：没有 axis_do 覆写 = 走 mech_kingdom.bot_score（不站国度）+ 通用躲招


## 测试台逐招对账：没有名字的后续段（第 2、3 发、回程、碎片圈…）记到最近一次有名字的招下（boss_trial.move_tag 读 mv）
func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	if str(d.get("name", "")) != "":
		e["cur_mv"] = str(d.name)
	elif not d.has("mv"):
		d["mv"] = str(e.get("cur_mv", ""))
	return super(e, shape, dur, d)


## 中期 Boss 的弹按自己写的 life 消失，不吃场地续飞（shot_pool._arena_fly 会给出界前的弹续 6 秒；11-26 雪祀慢雪片因此叠满 150 上限）
func shot(e: Dictionary, pos: Vector2, ang: float, spd: float, tier: int, pct: float, o := {}) -> void:
	var n0: int = g.ebullets.size()
	super(e, pos, ang, spd, tier, pct, o)
	if g.ebullets.size() > n0:
		g.ebullets[g.ebullets.size() - 1]["no_extend"] = true
