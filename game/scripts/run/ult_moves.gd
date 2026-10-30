## 终结技形态（docs/198 §4.1–4.5，第一批 5 人）+ 连携终结技通用版（§7.3）。框架在 run/ult.gd（u），本文件只写各人怎么出招。
## 约定：start 返回动作状态字典，step 每帧推进、返回 true = 结束；伤害一律走 u.hit（按目标生命定的预算，frac = 这段占预算的比例）；
## 画面：5 人专属终结技走 Codex 第一批帧条（u.strip / tiles_line / tiles_arc，规格 art/incoming/ult_batch1_1029/manifest.json），
## 帧条接上的部分占位图形已删或减淡；瞄准指示、冲击环、其余 15 人通用版、连携终结技里队友那几下仍是 u.shape 程序占位。
## 每段命中各记一张已命中表（e.id），同一敌人同一段只打一次；外缘 15% 宽的衰减带传 edge（§3.3）。不抽随机数，散布按序号算。
## 其余 15 人暂无专属终结技：以自身为中心半径 460 的冲击环（0.3 秒扩满，100% 预算）。
## 连携终结技：start_cult 按 ult/cult_style 分派（0 = 通用版：队长终结技形态 + 队友冲到敌群打放大冲击，同时落地时屏内敌人一次补满预算）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const A = preload("res://scripts/art.gd")
## 其余 15 人（用户 10-29「20 个干员的都做好」）：分两个文件写，接口同本文件（handles / aim_kind / aim_r / start / step）
const MB = preload("res://scripts/run/ult_moves_b.gd")   # 斯卡蒂 / 歌蕾蒂娅 / 安洁莉娜 / 艾雅法拉 / 维什戴尔 / 归溟幽灵鲨 / 水月
const MC = preload("res://scripts/run/ult_moves_c.gd")   # 塞雷娅 / 铃兰 / 逻各斯 / 星熊 / 推进之王 / 艾丽妮 / 拉普兰德 / 流明

const POINT_OPS := ["texas", "kaltsit", "ulpianus"]
const AUTO_OPS := ["exusiai", "skalter"]
const COL_SK_RED := Color(0.78, 0.06, 0.14)
const COL_SK_TEAL := Color(0.25, 0.95, 0.82)
const COL_STEEL := Color(0.72, 0.8, 0.9)


static func aim_kind(id: String) -> String:
	if MB.handles(id):
		return MB.aim_kind(id)
	if MC.handles(id):
		return MC.aim_kind(id)
	return "point" if id in POINT_OPS else "none"


## 瞄准指示的半径（选落点：落点圆；不瞄：以自身为中心的圈）
static func aim_r(id: String) -> float:
	if MB.handles(id):
		return MB.aim_r(id)
	if MC.handles(id):
		return MC.aim_r(id)
	match id:
		"exusiai":
			return Bal.v("ult/ex_r", 545.0)
		"skalter":
			return Bal.v("ult/sk_r", 515.0)
		"texas":
			return Bal.v("ult/tx_r", 605.0)
		"kaltsit":
			return Bal.v("ult/ka_r", 580.0)
		"ulpianus":
			return Bal.v("ult/ul_r", 615.0)
	return 460.0


static func start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	_m3_watch(u)
	if o == null or o.pos == Vector2.INF:
		return {}
	var a: Dictionary
	match str(o.id):
		"texas":
			a = _tx_start(u, o, aim, dir)
		"exusiai":
			a = _ex_start(u, o)
		"skalter":
			a = _sk_start(u, o, dir)
		"kaltsit":
			a = _ka_start(u, o, aim)
		"ulpianus":
			a = _ul_start(u, o, aim)
		_:
			if MB.handles(str(o.id)):
				a = MB.start(u, o, aim, dir)
				a["k"] = "mb"
			elif MC.handles(str(o.id)):
				a = MC.start(u, o, aim, dir)
				a["k"] = "mc"
			else:
				a = _gen_start(u, o)
	a["o"] = o
	a["t"] = 0.0
	return a


static func step(u, a: Dictionary, dt: float) -> bool:
	if a.is_empty():
		return true
	var o = a.o
	if o == null or o.pos == Vector2.INF:
		_abort(u, a)
		return true
	a.t = float(a.t) + dt
	match str(a.k):
		"texas":
			return _tx_step(u, a, o)
		"exusiai":
			return _ex_step(u, a, o)
		"skalter":
			return _sk_step(u, a, o, dt)
		"kaltsit":
			return _ka_step(u, a, o)
		"ulpianus":
			return _ul_step(u, a, o)
		"mb":
			return MB.step(u, a, dt)
		"mc":
			return MC.step(u, a, dt)
	return _gen_step(u, a, o)


static func start_cult(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	match int(Bal.v("ult/cult_style", 0)):
		_:
			return _cult_generic_start(u, o, aim, dir)


static func step_cult(u, a: Dictionary, dt: float) -> bool:
	if a.is_empty():
		return true
	match str(a.get("style", "generic")):
		_:
			return _cult_generic_step(u, a, dt)


# ================================================================ 公用

## 一段伤害：带 cap 的动作（连携终结技）每名敌人合计不超过 cap（份预算）
static func _hit(u, a: Dictionary, o, e: Dictionary, frac: float, opt: Dictionary = {}) -> float:
	if a.has("cap"):
		var k: int = int(e.id)
		var done: float = float(a.fr.get(k, 0.0))
		frac = minf(frac, float(a.cap) - done)
		if frac <= 0.0001:
			return 0.0
		a.fr[k] = done + frac
	return u.hit(o, e, frac, opt)


## 圆形区：一次性打这一段（seg = 已命中表），外缘 15% 宽算衰减带；opt.big = 精英 / Boss 在这一段吃的份额（缺省同 frac）
static func _hit_circle(u, a: Dictionary, o, c: Vector2, r: float, frac: float, seg: Dictionary, opt: Dictionary = {}, edge_r := -1.0) -> int:
	var n := 0
	var er: float = (edge_r if edge_r > 0.0 else r) * (1.0 - _edge_w())
	for e in u.in_circle(c, r):
		if seg.has(int(e.id)):
			continue
		seg[int(e.id)] = true
		var op: Dictionary = opt.duplicate()
		op.erase("big")
		op["edge"] = e.pos.distance_to(c) > er
		_hit(u, a, o, e, float(opt.big) if (opt.has("big") and (e.elite or e.boss or e.get("part", false))) else frac, op)
		n += 1
	return n


static func _edge_w() -> float:
	return Bal.v("ult/edge_w", 0.15)


static func _route(o) -> String:
	var r = o.get("route")
	return str(r) if r != null else ""


## 击退距离 → 冲量（敌人 kb 每秒衰减 900）
static func _kb_v(dist: float) -> float:
	return sqrt(1800.0 * maxf(0.0, dist))


static func _ring(u, c: Vector2, r: float, r1: float, col: Color, life: float, w := 6.0, delay := 0.0) -> void:
	u.shape({"kind": "ring", "c": c, "r": r, "r1": r1, "w": w, "col": col, "life": life, "delay": delay})


static func _abort(u, a: Dictionary) -> void:
	_fx_end(u, a)
	if str(a.get("k", "")) == "kaltsit":
		_m3_back(u, a.o, false)


# ================================================================ 帧条公用

## 弧状拼接段的参考半径（1x 像素，manifest arc_reference_radius_logical）：素材按这个半径画弧
const ARC_R0 := {"fx_ult_skalter_domain_back": 123.6385, "fx_ult_kaltsit_crack_back": 185.4578, "fx_ult_ulpianus_crack_back": 185.4578}


## 弧状拼接段铺到半径 r：沿切向缩放 k = √(r / 参考半径)、径向反缩 1 / k —— 弧的曲率正好变成 r（小角度近似），
## 厚度保持素材原样，段与段的两端切线对齐、不露缝（直接等比缩放会让小圈细得看不见、大圈粗过伤害区）
static func _arc(u, name: String, c: Vector2, r: float, opt: Dictionary = {}) -> Array:
	var r0: float = float(ARC_R0.get(name, r / u.g.PX)) * u.g.PX
	var k: float = sqrt(maxf(1.0, r) / r0)
	var op: Dictionary = opt.duplicate()
	op["sc"] = k * float(opt.get("sc", 1.0))
	op["sy"] = float(opt.get("sy", 1.0)) / k
	return u.tiles_arc(name, c, r, op)


## 拿掉一组帧条实例（每帧重铺的光束 / 锁链、提前收掉的锁定标记）：直接从 u.shapes 移除，当帧就不画
static func _kill(u, arr: Array) -> void:
	for s in arr:
		u.shapes.erase(s)
	arr.clear()


## 动作里挂着的长寿命帧条（a.fx 列表；锁定标记、海嗣、巨锚、光束、锁链）：动作结束 / 中途被清掉时一起收
static func _fx_end(u, a: Dictionary) -> void:
	for key in ["fx", "beam", "chain"]:
		if a.get(key) is Array:
			_kill(u, a[key])
	if a.get("locks") is Array:
		for lk in a.locks:
			u.shapes.erase(lk.s)
			for s in lk.get("fr", []):
				u.shapes.erase(s)
		a.locks.clear()


# ================================================================ 通用占位（无专属终结技）

static func _gen_start(u, o) -> Dictionary:
	var c: Vector2 = o.pos
	var col: Color = u._col(o)
	_ring(u, c, 460.0, 40.0, col.lerp(Color.WHITE, 0.3), 0.6, 10.0)
	u.shape({"kind": "circle", "c": c, "r": 460.0, "col": col, "fill": 0.18, "life": 0.5})
	u.shape({"kind": "dots", "c": c, "r": 440.0, "n": 28, "col": col.lerp(Color.WHITE, 0.5), "life": 0.6})
	o.screen_shake(0.5)
	return {"k": "gen", "c": c, "seg": {}}


static func _gen_step(u, a: Dictionary, o) -> bool:
	var T := 0.3
	var r: float = lerpf(40.0, 460.0, clampf(float(a.t) / T, 0.0, 1.0))
	_hit_circle(u, a, o, a.c, r, 1.0, a.seg, {"src": "冲击"}, 460.0)
	return float(a.t) >= T


# ================================================================ 德克萨斯（§4.1）：落点圆内连闪刀痕 → 同时斩开（10-31 起剑雨缺省去掉，ult/tx_rain）

static func _tx_start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	var rt := _route(o)
	var R: float = Bal.v("ult/tx_r", 605.0) * (430.0 / 460.0 if rt == "back" else 1.0)
	var c: Vector2 = aim if aim != Vector2.INF else o.pos
	var n: int = 5 + int(u.serial) % 3
	var base: float = dir.angle() + 0.35
	var lines: Array = []
	for i in n:
		var ang: float = base + PI * float(i) / float(n) + 0.12 * float((i * 5) % 3 - 1)
		var d: Vector2 = Vector2.from_angle(ang)
		var off: float = (float((i * 37) % 9) - 4.0) / 4.0 * R * 0.4
		var ln: float = 2.0 * sqrt(maxf(0.0, R * R - off * off)) * 0.98   # 圆内的一条弦（用户 10-29：斩线收回刀网范围内，两端尖细收在圆边；圆本身不画）
		var mid: Vector2 = c + d.orthogonal() * off
		lines.append([mid - d * ln * 0.5, mid + d * ln * 0.5])
	# 剑雨落点：沿刀痕每 40 一把，只落在落点圆内；按序号交错，各刀痕同时往外铺
	var per: Array = []
	var most := 0
	for ln in lines:
		var pts: Array = []
		var L: float = ln[0].distance_to(ln[1])
		var k := 0
		while k * 40.0 <= L:
			var p: Vector2 = ln[0].lerp(ln[1], k * 40.0 / L)
			if p.distance_to(c) <= R:
				pts.append(p)
			k += 1
		per.append(pts)
		most = maxi(most, pts.size())
	var swords: Array = []
	for j in most:
		for pts in per:
			if j < pts.size():
				swords.append(pts[j])
	# 用户 10-31「剑雨可以去掉了，留下斩击就行」：ult/tx_rain 缺省 0 = 不落剑雨（输出按范围统一 ult/dmgk_texas，docs/199 §5.10）；
	# 剑雨分支（route rain，原两轮各 0.15）改成斩开 0.7 后隔 0.35 秒换角度再斩一次 0.3。1 = 旧版斩开 + 剑雨
	var rain_on: bool = Bal.v("ult/tx_rain", 0.0) > 0.0
	var lines2: Array = []
	if not rain_on:
		swords = []
		if rt == "rain":
			for ln in lines:
				var mid2: Vector2 = (ln[0] + ln[1]) * 0.5
				var d2: Vector2 = (ln[1] - ln[0]).rotated(PI / float(2 * n))
				var mid3: Vector2 = c + (mid2 - c).rotated(PI / float(2 * n))
				var L2: float = d2.length() * 0.5
				lines2.append([mid3 - d2.normalized() * L2, mid3 + d2.normalized() * L2])
	for e in u.in_circle(c, R):
		if not e.boss:
			u.g.enemies_sys.add_cc(e, Bal.v("ult/tx_hold", 0.6))   # 定住，暂不受伤
	# 用户 10-29：松手斩开后不画任何圆 / 环，范围由斩线本身表达（瞄准时的落点提示由框架画，淡）
	var rounds: Array = [[0.75, 0.3]]
	if rt == "rain":
		rounds = [[0.75, 0.15], [1.05, 0.15]]
	if not rain_on:
		rounds = []
	# 剑雨帧条：一把 0.3 秒、一轮 0.8 秒铺完，同时在场约 剑数 × 0.375 × 轮数；超过 ult/tx_sword_fx（56）就隔把画（伤害照打每一把）
	var stride: int = maxi(1, ceili(float(swords.size()) * 0.375 * float(rounds.size()) / Bal.v("ult/tx_sword_fx", 56.0)))
	# cap / fr：每名敌人本次合计至多 1 份预算（斩开 0.7 + 剑雨 0.3；精英 / Boss 斩开直接吃满 1 份，剑雨不再加）
	var cut_d: float = Bal.v("ult/tx_cut", 0.7)   # 剑雨去掉后的输出由范围统一的 ult/dmgk_texas 一并管（协调人 10-31，docs/199 §5.10）
	return {"k": "texas", "cap": 1.0, "fr": {}, "no_ring": true, "c": c, "R": R, "lines": lines, "drawn": 0, "cut": false, "cut_seg": {}, "swords": swords,
		"cut_d": cut_d, "lines2": lines2, "cut2": false, "cut2_seg": {},
		"rounds": rounds, "rain": [], "sv": [], "stride": stride, "back": rt == "back", "back_done": false, "end": 0.0}


## 斩线（用户 10-29：次元斩式「乱刃」——笔直、细长、贯穿，白芯 + 冷青蓝辉光、两端尖细，1–2 帧出现、停 ult/tx_blade_hold 秒后碎裂）。
## Codex 的 fx_ult_texas_slash_front 偏宽偏弧，这里改程序画（地面残痕帧条照用）
const TX_GLOW := Color(1.0, 0.55, 0.2)   # 她的主题色（texas.json col）：白芯 + 橙色辉光（用户 10-29，和青蓝环境拉开）


## 乌尔比安打击感试点（10-31，pixfx §6.6）：冲击帧剪影 + 冲锋拖影 + 团块尘；0 = 10-30 用户认可版
static func _ul_v3() -> bool:
	return Bal.v("ult/ul_fx_v3", 1.0) > 0.0


static func _tx_blade(u, ln: Array, v2 := false) -> void:
	var hold: float = Bal.v("ult/tx_blade_hold", 0.2)
	# v2（打击感试点，pixfx §6.6）：出手 1 帧到位（不长出来）、斩痕进冲击帧剪影
	u.shape({"kind": "blade", "a": ln[0], "b": ln[1], "w": Bal.v("ult/tx_blade_w", 10.0), "col": Color.WHITE, "glow": TX_GLOW, "grow": 0.0 if v2 else 0.035, "life": hold + (Bal.v("ult/tx_fade", 0.7) if v2 else 0.035), "fo": Bal.v("ult/tx_fade", 0.7) if v2 else 0.08, "hf": v2})


## 斩开 v2 的余部：沿刀痕的拖影（smear）+ 逐帧烟尘（五团、大小 / 延迟错开、往刀痕两侧散）；不飞碎石（用户 10-31）
static func _tx_cut_v2(u, ln: Array) -> void:
	var a: Vector2 = ln[0]
	var b: Vector2 = ln[1]
	var d: Vector2 = (b - a).normalized()
	var vs: float = PF.h(a.x * 0.013 + b.y * 0.029)
	# smear：冲击帧过后（0.13 秒）沿刀痕一条又宽又亮、两头拉出去的拖影带，0.1 秒
	var hf2: float = 2.0 * Bal.v("ult/hit_frame_t", 0.067)
	u.shape({"kind": "band", "a": a - d * 90.0, "b": b + d * 90.0, "w": 56.0, "col": Color(1.0, 0.95, 0.85), "fill": 0.7, "life": 0.1, "delay": hf2})
	u.shape({"kind": "band", "a": a - d * 140.0, "b": b + d * 140.0, "w": 22.0, "col": Color(1.0, 0.85, 0.6), "fill": 0.9, "life": 0.14, "delay": hf2})
	var nrm: Vector2 = d.orthogonal()
	for k in 3:   # 烟尘团（生成大贴图）：沿刀痕三处、大小 / 延迟错开，往刀痕两侧飘开
		var hk: float = PF.h(vs + k * 1.7)
		var p: Vector2 = a.lerp(b, 0.2 + 0.3 * k + 0.12 * (hk - 0.5))
		var side: float = 1.0 if hk < 0.5 else -1.0
		PF.dust(u, p, 170.0 + 90.0 * hk, hf2 + 0.03 * k, vs + k * 3.0, nrm * side * (40.0 + 30.0 * hk))
	for k in 2:   # 碎石去掉（用户 10-31「这里是烟雾比较好」）→ 刀痕上再补两团小烟，贴着刀痕往两侧散开、晚一拍
		var hk: float = PF.h(vs * 3.0 + k)
		var p2: Vector2 = a.lerp(b, 0.35 + 0.3 * k + 0.1 * (hk - 0.5))
		PF.dust(u, p2, 110.0 + 40.0 * hk, hf2 + 0.08 + 0.04 * k, vs + 11.0 + k, nrm * (1.0 if k == 0 else -1.0) * (60.0 + 30.0 * hk))


## 碎裂：每条斩线断成 8 段，各段往两侧飞散、略转一点角度、0.25 秒淡出
static func _tx_shatter(u, ln: Array, i0: int) -> void:
	var a: Vector2 = ln[0]
	var b: Vector2 = ln[1]
	var d: Vector2 = (b - a).normalized()
	var nrm: Vector2 = d.orthogonal()
	for k in 8:
		var p0: Vector2 = a.lerp(b, (k + 0.12) / 8.0)
		var p1: Vector2 = a.lerp(b, (k + 0.88) / 8.0)
		var m: Vector2 = (p0 + p1) * 0.5
		var tw: float = 0.18 * (1.0 if (k + i0) % 2 == 0 else -1.0)
		var h: Vector2 = (p1 - p0).rotated(tw) * 0.5
		var sgn: float = 1.0 if (k * 3 + i0) % 2 == 0 else -1.0
		u.shape({"kind": "blade", "a": m - h, "b": m + h, "w": 5.0, "col": Color(1.0, 0.88, 0.72), "glow": TX_GLOW, "life": 0.25,
			"v": nrm * sgn * (70.0 + 25.0 * float((k * 7 + i0) % 4)) + d * 30.0 * float((k % 3) - 1)})


static func _tx_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var col: Color = u._col(o)
	var hi: Color = col.lerp(Color.WHITE, 0.6)
	var lines: Array = a.lines
	var n: int = lines.size()
	while int(a.drawn) < n and t >= float(a.drawn) * 0.5 / float(n):
		# 画网：一道道橙色发丝线显现（斩开前的预兆）
		var pl: Array = lines[int(a.drawn)]
		u.shape({"kind": "line", "a": pl[0], "b": pl[1], "w": 1.5, "col": TX_GLOW, "life": maxf(0.05, 0.75 - t)})
		a.drawn = int(a.drawn) + 1
	if not a.cut and t >= 0.75:
		a.cut = true
		var v2: bool = Bal.v("ult/tx_fx_v2", 1.0) > 0.0
		if v2:
			a["hf"] = true   # 冲击帧（ult.gd _draw_hit_frame）
			u.act["hf"] = true
			u.g.vfx.stop(Bal.v("ult/tx_hitstop", 0.12), "ult", true)
		for ln in lines:   # 斩开：5–7 条直线斩痕同时出现、停一下再碎；地面残痕沿刀痕拼接，0.8 秒走完 4 帧淡出
			_tx_blade(u, ln, v2)
			u.tiles_line("fx_ult_texas_scar_back", ln[0], ln[1], {"layer": "back", "fps": 5.0, "life": 1.8 if v2 else 0.8})
			if v2:
				_tx_cut_v2(u, ln)
		_hit_circle(u, a, o, a.c, a.R, float(a.cut_d), a.cut_seg, {"src": "斩开", "big": 1.0})
		o.screen_shake(0.6)
		o.play_vis_anim("attack")
	if a.cut and not a.get("shattered", false) and t >= 0.75 + Bal.v("ult/tx_blade_hold", 0.2) and Bal.v("ult/tx_fx_v2", 1.0) <= 0.0:   # v2：斩线不碎，停住后慢慢淡出（用户 10-31）
		a["shattered"] = true
		for li in lines.size():
			_tx_shatter(u, lines[li], li)
	var t2: float = 0.75 + Bal.v("ult/tx_blade_hold", 0.2) + 0.15   # 剑雨分支的第二斩（无剑雨时）：第一斩碎掉后再来一轮
	if not a.lines2.is_empty() and not a.cut2 and t >= t2:
		a.cut2 = true
		u.g.vfx.stop(Bal.v("ult/tx_hitstop", 0.12) * 0.6, "ult", true)
		for ln in a.lines2:
			_tx_blade(u, ln, true)
			u.tiles_line("fx_ult_texas_scar_back", ln[0], ln[1], {"layer": "back", "fps": 5.0, "life": 1.8})
			_tx_cut_v2(u, ln)
		_hit_circle(u, a, o, a.c, a.R, Bal.v("ult/tx_cut2", 0.3), a.cut2_seg, {"src": "斩开", "big": 0.3})
		o.screen_shake(0.4)
	var sw: Array = a.swords
	var last := 0.0
	if a.rounds.is_empty():   # 无剑雨：最后一道斩线碎完再收
		last = (t2 if not a.lines2.is_empty() else 0.75) + Bal.v("ult/tx_blade_hold", 0.2) + 0.3
	for ri in a.rounds.size():
		var rd: Array = a.rounds[ri]
		var t0: float = rd[0]
		last = maxf(last, t0 + 0.8)
		# 剑帧条比伤害早 3 帧（落 0–2）放下去，插地那一帧（f3）正好是这把剑打到的时刻；伤害时序不动
		var lead: float = 3.0 / 20.0
		if t >= t0 - lead:
			if a.sv.size() <= ri:
				a.sv.append(0)
			var due_v: int = mini(sw.size(), int(ceil((t + lead - t0) / 0.8 * float(sw.size()))))
			while int(a.sv[ri]) < due_v:
				var j: int = int(a.sv[ri])
				if j % int(a.stride) == 0:
					u.strip("fx_ult_texas_sword_front", sw[j], {"o": Vector2(32, 224)})
				a.sv[ri] = j + 1
		if t < t0:
			continue
		if a.rain.size() <= ri:
			a.rain.append({"i": 0, "seg": {}})
		var st: Dictionary = a.rain[ri]
		var due: int = mini(sw.size(), int(ceil((t - t0) / 0.8 * float(sw.size()))))
		while int(st.i) < due:
			var p: Vector2 = sw[int(st.i)]
			for e in u.in_circle(p, 30.0 + 8.0):
				if st.seg.has(int(e.id)):
					continue
				st.seg[int(e.id)] = true
				_hit(u, a, o, e, float(rd[1]), {"stun": Bal.v("ult/tx_rain_stun", 0.4), "src": "剑雨",
					"edge": e.pos.distance_to(a.c) > float(a.R) * (1.0 - _edge_w())})
			st.i = int(st.i) + 1
	if a.back and not a.back_done and t >= last:
		a.back_done = true   # 回马剑：收刀时在她身后再斩一圈（斩开打过的不再打）
		var br: float = 240.0 * float(a.R) / 430.0
		if Bal.v("ult/tx_fx_v2", 1.0) > 0.0:
			# 10-31 用户「为什么还有六芒星」：三道交于她脚下、各差 60° 的旧画法叠成六芒星 → 三道弦各自错开（偏离圆心 ±0.2–0.45 r）、
			# 角度按 hash 打乱、长短不一，和主斩同一画法（一帧到位、慢慢淡出 + 烟尘碎石）
			var vs: float = PF.h(o.pos.x * 0.011 + o.pos.y * 0.017 + float(u.serial))
			for bi in 3:
				var hb: float = PF.h(vs * 5.0 + bi * 1.3)
				var ang: float = vs * TAU + bi * 1.15 + (hb - 0.5) * 0.5
				var bd: Vector2 = Vector2.from_angle(ang)
				var off: float = (0.2 + 0.25 * hb) * br * (1.0 if bi % 2 == 0 else -1.0)
				var half: float = sqrt(maxf(0.0, br * br - off * off)) * (0.75 + 0.2 * PF.h(hb * 7.0))
				var mid: Vector2 = o.pos + bd.orthogonal() * off
				var ln: Array = [mid - bd * half, mid + bd * half]
				_tx_blade(u, ln, true)
				_tx_cut_v2(u, ln)
		else:
			for bi in 3:   # 回马剑：身后三道短斩线（不画圈）
				var bd: Vector2 = Vector2.from_angle(bi * PI / 3.0 + 0.4)
				_tx_blade(u, [o.pos - bd * br, o.pos + bd * br])
		_hit_circle(u, a, o, o.pos, 220.0 * float(a.R) / 430.0, Bal.v("ult/tx_cut", 0.7), a.cut_seg, {"src": "回马剑", "big": 1.0})
	if t >= last + 0.05:
		_tx_sp(u, o)
		return true
	return false


## 放完：队友技力 +2 秒（各技能按自然充能的秒数加，已满 / 常驻的不动）
static func _tx_sp(u, o) -> void:
	var add: float = Bal.v("ult/tx_sp", 2.0)
	for m in u.g.squad.ops:
		if m == o or m.pos == Vector2.INF or not m.has_method("skill_unlocked"):
			continue
		for i in 3:
			if m.skill_unlocked(i) and m.sp_need(i) > 0.0 and not m.perm[i]:
				m.sp[i] = minf(m.sp_need(i), float(m.sp[i]) + add)


# ================================================================ 能天使（§4.2）：自动锁定半径 ult/ex_r，2.5 秒 24 发 / 秒爆裂弹
## 10-30 用户「现在看不出来」返工：她本人双枪举起、左右两侧枪口火光常亮、每发在枪口闪；锁定目标套红金锁定框（菱形框 + 金环，跟着目标走）；
## 爆裂弹爆点加大加亮，同一发的溅射之间有短连锁闪线（10-30 第二轮：相邻两发之间的长连线、整条长曳光已删，改成一颗颗在飞的子弹，见 _ex_bullet）；曳光加粗、红金两色交替；锁定的都打完后剩余发数打圈内空地（只有画面），
## 持续期间满屏都是她的弹道与爆炸。锁定半径 480 → ult/ex_r（505 → 545，10-30 §3.4 对齐：均匀场景小怪倒下 44 → 51%；聚怪由 ult/ex_tgt 目标上限压在 75% 内）：参考场景 500 处那只精英原来锁不上（精英只到 27%）
const EX_RED := Color(0.95, 0.16, 0.2)
const EX_GOLD := Color(1.0, 0.8, 0.28)
const EX_MZ := [Vector2(-30.0, -30.0), Vector2(30.0, -30.0)]   # 左右两把枪的枪口（脚底为原点）


static func _ex_start(u, o) -> Dictionary:
	var rt := _route(o)
	var R: float = Bal.v("ult/ex_r", 545.0) * (1.1 if rt == "range" else 1.0)
	var elites: Array = []
	var normals: Array = []
	for e in u.in_circle(o.pos, R):
		if e.elite or e.boss or e.get("part", false):
			elites.append(e)
		else:
			normals.append(e)
	var c: Vector2 = o.pos
	elites.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
	normals.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
	var ne: int = int(Bal.v("ult/ex_elite_shots", 7.0))
	var cap: int = int(Bal.v("ult/ex_cap", 60.0))
	var eq: Array = []
	for e in elites:
		for k in ne:
			if eq.size() < cap - 12:   # 至少留 12 发给普通目标
				eq.append(e)
	var dur: float = Bal.v("ult/ex_dur", 2.5)
	# 锁定标记（fx_ult_exusiai_lock_orbit 放大 1.5 倍、调成红金 + 程序菱形框 + 金环）：精英 / Boss 先、再按距离挑普通目标，至多 ult/ex_lock_fx（24）个
	var locks: Array = []
	var lk_cap: int = int(Bal.v("ult/ex_lock_fx", 24.0))
	for e in elites + normals:
		if locks.size() >= lk_cap:
			break
		var sc: float = clampf((float(e.get("r", 14.0)) + 10.0) / 24.0, 0.8, 3.0) * 1.5
		var s: Dictionary = u.strip("fx_ult_exusiai_lock_orbit", e.pos, {"o": Vector2(48, 48), "f": 0, "sc": sc, "life": dur + 0.5, "col": Color(1.0, 0.72, 0.55)})
		var fr: Array = []
		for j in 4:
			fr.append(_ex_keep(u, {"kind": "line", "a": e.pos, "b": e.pos, "w": 4.0 if not (e.elite or e.boss) else 6.0, "col": EX_RED, "life": dur + 0.5}))
		fr.append(_ex_keep(u, {"kind": "ring", "c": e.pos, "r": 20.0, "w": 3.0, "col": EX_GOLD, "life": dur + 0.5, "solid": true}))
		locks.append({"e": e, "out": -1.0, "s": s, "fr": fr, "h": float(e.get("r", 14.0)) + (26.0 if (e.elite or e.boss) else 16.0), "i": locks.size()})
	# 出手：双枪举起（两侧往上斜举的白芯金光 + 枪口火光亮起）、脚下一道红金光柱、锁定圈从她身上扩出去
	o.play_vis_anim("attack")
	for k in 2:
		var mz: Vector2 = c + EX_MZ[k]
		var up: Vector2 = Vector2(-0.55 if k == 0 else 0.55, -1.0).normalized()
		u.shape({"kind": "blade", "a": mz - up * 10.0, "b": mz + up * 120.0, "w": 10.0, "col": EX_GOLD.lerp(Color.WHITE, 0.3), "glow": EX_RED, "grow": 0.08, "life": 0.4})
		u.shape({"kind": "circle", "c": mz, "r": 30.0, "col": EX_GOLD, "fill": 0.9, "life": 0.25})
		u.grain("bul_spawn", mz, up, EX_GOLD, 10)
		u.light(mz, 150.0, EX_GOLD, 0.4)
	u.shape({"kind": "band", "a": c + Vector2(0, 10), "b": c + Vector2(0, -300), "w": 60.0, "col": EX_RED, "fill": 0.35, "life": 0.35})
	u.shape({"kind": "band", "a": c + Vector2(0, 10), "b": c + Vector2(0, -300), "w": 24.0, "col": EX_GOLD, "fill": 0.7, "life": 0.25})
	u.grain("mote_up", c, Vector2.UP, EX_GOLD, 14)
	_ring(u, c, R, 40.0, EX_RED, 0.5, 8.0)
	_ring(u, c, R, 60.0, EX_GOLD, 0.6, 4.0, 0.06)
	u.shake(4.0, 0.2)
	# 枪口火光（持续期间常亮，每发闪一下）
	var mzf: Array = []
	for k in 2:
		mzf.append(_ex_keep(u, {"kind": "circle", "c": c + EX_MZ[k], "r": 16.0, "col": EX_GOLD, "fill": 0.75, "life": dur + 0.2}))
	return {"k": "exusiai", "R": R, "mult": 0.9 if rt == "range" else 1.0, "rico": rt == "ricochet", "eq": eq, "ne": ne,
		"normals": normals, "done": {}, "fired": 0, "ncap": cap, "nhit": 0, "tcap": int(Bal.v("ult/ex_tgt", 100.0)), "dur": dur, "rate": Bal.v("ult/ex_rate", 24.0), "ring_t": 0.5,
		"locks": locks, "lk_done": {}, "bt": [], "mzf": mzf, "fx": mzf.duplicate(), "no_ring": true, "bul": [], "hitd": {}, "pt": 0.0}


## 跟着动的程序图形（锁定框、枪口火光）：每帧改位置、age 拨回 0 保持不透明；收掉时改成短寿命自然淡出
static func _ex_keep(u, s: Dictionary) -> Dictionary:
	u.shape(s)
	return s


static func _ex_drop(s: Dictionary, fade: float) -> void:
	s.age = 0.0
	s.max = fade


## 锁定框一帧：菱形四条边绕目标慢转、金环呼吸；精英 / Boss 框更大更粗
static func _ex_frame(lk: Dictionary, t: float) -> void:
	var p: Vector2 = lk.s.c
	var h: float = float(lk.h) * (1.0 + 0.08 * sin(t * 14.0 + float(lk.i)))
	var rot: float = t * 1.6 + float(lk.i) * 0.4
	var fr: Array = lk.fr
	for j in 4:
		var s: Dictionary = fr[j]
		s.a = p + Vector2.from_angle(rot + TAU * j / 4.0) * h
		s.b = p + Vector2.from_angle(rot + TAU * (j + 1) / 4.0) * h
		s.age = 0.0
	var rg: Dictionary = fr[4]
	rg.c = p
	rg.r = h * 0.62
	rg.age = 0.0


## 锁定标记推进：start 0–3 锁上 → loop 4–5 保持（跟着目标走）→ 被打到（精英：最后一发打完）/ 目标倒下 / 扫射结束 → out 6–7 碎掉（框同时闪白散开）
static func _ex_locks(u, a: Dictionary) -> void:
	var t: float = a.t
	for k in range(a.locks.size() - 1, -1, -1):
		var lk: Dictionary = a.locks[k]
		var e: Dictionary = lk.e
		var s: Dictionary = lk.s
		if not e.dead:
			s.c = e.pos
		if float(lk.out) < 0.0 and (e.dead or a.hitd.has(int(e.id)) or a.lk_done.has(int(e.id)) or t >= float(a.dur)):
			lk.out = t
			_ex_break(u, lk)
		if float(lk.out) >= 0.0:
			var j: int = int((t - float(lk.out)) * 24.0)
			if j >= 2:
				u.shapes.erase(s)
				a.locks.remove_at(k)
				continue
			s.f = 6 + j
		else:
			var j2: int = int(t * 24.0)
			s.f = j2 if j2 < 4 else 4 + (j2 - 4) % 2
			_ex_frame(lk, t)


## 框碎：四条边往外飞散淡出 + 金环闪白
static func _ex_break(u, lk: Dictionary) -> void:
	var p: Vector2 = lk.s.c
	for j in 4:
		var s: Dictionary = lk.fr[j]
		_ex_drop(s, 0.16)
		s["v"] = ((s.a + s.b) * 0.5 - p).normalized() * 260.0
		s.col = EX_GOLD
	_ex_drop(lk.fr[4], 0.12)
	lk.fr[4].col = EX_GOLD.lerp(Color.WHITE, 0.3)
	u.grain("sh_shard", p, Vector2.UP, EX_RED, 5)
	lk.fr = []


## 爆裂弹爆点（fx_ult_exusiai_burst_front 放大 + 金色闪光 + 红色冲击环）：同一时刻在场超过 ult/ex_burst_fx（48）个就跳过这一个（只少画、不少打）
static func _ex_burst(u, a: Dictionary, p: Vector2, sc: float) -> void:
	var t: float = a.t
	var bt: Array = a.bt
	while not bt.is_empty() and t - float(bt[0]) >= 0.2:
		bt.pop_front()
	if bt.size() >= int(Bal.v("ult/ex_burst_fx", 48.0)):
		return
	bt.append(t)
	u.strip("fx_ult_exusiai_burst_front", p, {"o": Vector2(64, 64), "sc": sc * 1.5})
	u.shape({"kind": "circle", "c": p, "r": 46.0 * sc, "col": EX_GOLD, "fill": 0.7, "life": 0.1})
	u.shape({"kind": "ring", "c": p, "r": 92.0 * sc, "r1": 20.0, "w": 6.0, "col": EX_RED, "life": 0.24})   # 缺省碎裂：一圈红色碎块往外崩
	var i: int = bt.size()
	u.grain("bul_pop", p, Vector2.from_angle(float(int(a.fired)) * 2.39996), EX_GOLD if i % 2 == 0 else EX_RED, 7)
	if int(a.fired) % 3 == 0:   # 灯只有 16 盏：每 3 发一盏，火星 / 碎屑同样抽稀
		u.light(p, 150.0 * sc, EX_RED.lerp(EX_GOLD, 0.5), 0.18)
		u.spark(p, EX_GOLD, 3, 20.0)
	if int(a.fired) % 5 == 0:
		u.debris(p, EX_RED, 1)


## 连锁闪线：红色外层 + 金白芯
static func _ex_chain(u, p0: Vector2, p1: Vector2, life: float) -> void:
	u.shape({"kind": "line", "a": p0, "b": p1, "w": 6.0, "col": EX_RED, "life": life})
	u.shape({"kind": "line", "a": p0, "b": p1, "w": 2.0, "col": EX_GOLD.lerp(Color.WHITE, 0.5), "life": life * 0.8})


## 子弹（10-30 用户「到后面变成了光束」返工）：原来每发画一整条枪口 → 落点的长曳光（0.09 秒、24 发 / 秒、两层），几发叠在一起就连成光束，
## 发与发之间的爆点连锁线又把落点连成网。现在每发是一颗真的在飞的子弹：短曳光 ult/ex_tr_len（40）+ 白芯 + 弹头亮点，
## 以 ult/ex_bspd（2600 / 秒）飞向目标（跟着目标走），飞到才结算伤害、开爆点；相邻两发间隔约 100（同一把枪约 200），飞行中同时在场约 4–6 颗，各自分得开。
## 一发分打多个框 / 跳弹同样从爆点飞出一颗子弹（不再画长连线）；只保留爆点到溅射目标（≤ 60）的短连锁闪线
static func _ex_bullet(u, a: Dictionary, p0: Vector2, dest: Vector2, tg, k: int, info: Dictionary) -> void:
	var cc: Color = EX_RED if k % 2 == 0 else EX_GOLD
	var sh: Array = [
		_ex_keep(u, {"kind": "line", "a": p0, "b": p0, "w": 6.0, "col": cc, "life": 2.0}),
		_ex_keep(u, {"kind": "line", "a": p0, "b": p0, "w": 3.0, "col": Color(1.0, 0.95, 0.75), "life": 2.0}),
		_ex_keep(u, {"kind": "circle", "c": p0, "r": 5.0, "col": Color(1.0, 0.97, 0.85), "fill": 1.0, "life": 2.0}),
	]
	a.fx.append_array(sh)
	a.bul.append({"p": p0, "tg": tg, "dest": dest, "sh": sh, "info": info, "age": 0.0})


static func _ex_fly(u, a: Dictionary, o, dt: float) -> void:
	var spd: float = Bal.v("ult/ex_bspd", 2600.0)
	var ln: float = Bal.v("ult/ex_tr_len", 40.0)
	var arrived: Array = []
	for b in a.bul:
		var tg = b.tg
		if tg != null and not tg.dead:
			b.dest = tg.pos
		var p: Vector2 = b.p
		var dv: Vector2 = Vector2(b.dest) - p
		var dl: float = dv.length()
		b.age = float(b.age) + dt
		var step: float = spd * dt
		if dl <= step or float(b.age) > 0.6:
			arrived.append(b)
			continue
		var d: Vector2 = dv / dl
		p += d * step
		b.p = p
		var tl: float = minf(ln, Vector2(p).distance_to(Vector2(b.info.get("from", p))))
		var s0: Dictionary = b.sh[0]
		s0.a = p - d * tl
		s0.b = p
		var s1: Dictionary = b.sh[1]
		s1.a = p - d * tl * 0.45
		s1.b = p
		var s2: Dictionary = b.sh[2]
		s2.c = p
		for s in b.sh:
			s.age = 0.0
	for b in arrived:
		a.bul.erase(b)
		for s in b.sh:
			u.shapes.erase(s)
		_ex_land(u, a, o, b)


## 子弹到了：结算这一发（主弹：主目标 + 半径 60 溅射 + 分发 + 跳弹；分发 / 跳弹：只打自己那一名；打空地：只有爆点）
static func _ex_land(u, a: Dictionary, o, b: Dictionary) -> void:
	var info: Dictionary = b.info
	var tg = b.tg
	var imp: Vector2 = b.dest
	var R: float = a.R
	var er: float = R * (1.0 - _edge_w())
	var kind: String = str(info.get("kind", "ground"))
	if kind == "ground":
		_ex_burst(u, a, imp, 0.8)
		return
	if tg != null and not tg.dead:
		_ex_hit(u, a, o, tg, float(info.frac), {"src": str(info.get("src", "爆裂弹")), "edge": imp.distance_to(o.pos) > er})
	if tg != null:
		if not (tg.elite or tg.boss or tg.get("part", false)):
			a.hitd[int(tg.id)] = true
		if info.get("last", false):
			a.lk_done[int(tg.id)] = true   # 打它的最后一发到了：锁定标记收
	if kind != "main":
		_ex_burst(u, a, imp, 0.75)
		return
	# 爆裂：半径 60 内锁定圈里还没打过的普通目标各吃整份（溅射计入预算），爆点到它们的短连锁闪线
	var n_sp := 0
	for e in u.in_circle(imp, 60.0):
		if e == tg or e.elite or e.boss or e.get("part", false) or a.done.has(int(e.id)) or e.pos.distance_to(o.pos) > R or _ex_full(a):
			continue
		_ex_mark(a, e)
		a.hitd[int(e.id)] = true
		_ex_hit(u, a, o, e, float(a.mult), {"src": "爆裂弹", "edge": e.pos.distance_to(o.pos) > er})
		_ex_chain(u, imp, e.pos, 0.1)
		n_sp += 1
	_ex_burst(u, a, imp, 1.0 if n_sp > 0 else 0.85)   # 爆裂半径 60 ≈ 帧条峰值帧 120 宽
	# 目标多于剩余发数：一发打多个框（就近再分几名，各飞一颗分弹）
	var left: int = maxi(1, int(a.ncap) - int(a.fired))
	var und: Array = _ex_undone(a)
	var kk: int = int(ceil(float(und.size()) / float(left)))
	if kk > 1:
		und.sort_custom(func(x, y): return x.pos.distance_squared_to(imp) < y.pos.distance_squared_to(imp))
		for j in mini(kk - 1, und.size()):
			var e: Dictionary = und[j]
			if _ex_full(a):
				break
			_ex_mark(a, e)
			_ex_bullet(u, a, imp, e.pos, e, j + 1, {"kind": "split", "frac": float(a.mult), "from": imp})
	# 跳弹路线：每 5 发里 2 发（按序号，不抽随机数）弹向圈内另一个还没锁上的敌人
	if a.rico and (int(info.get("n", 0)) * 2) % 5 < 2 and not _ex_full(a):
		var best = null
		var bd := 220.0 * 220.0
		for e in u.in_circle(imp, 220.0):
			if e == tg or a.done.has(int(e.id)) or e.elite or e.boss or e.pos.distance_to(o.pos) > R:
				continue
			var d2: float = e.pos.distance_squared_to(imp)
			if d2 < bd:
				bd = d2
				best = e
		if best != null:
			_ex_mark(a, best)
			_ex_bullet(u, a, imp, best.pos, best, 1, {"kind": "split", "frac": float(a.mult), "src": "跳弹", "from": imp})


## 开枪：枪口短火舌 + 火光闪一下，射出一颗子弹（两把枪交替）
static func _ex_shoot(u, a: Dictionary, o, dest: Vector2, tg, info: Dictionary) -> void:
	var k: int = int(a.fired) % 2
	var mz: Vector2 = o.pos + EX_MZ[k]
	var d: Vector2 = (dest - mz).normalized() if dest.distance_to(mz) > 1.0 else Vector2.RIGHT
	u.shape({"kind": "blade", "a": mz - d * 4.0, "b": mz + d * 30.0, "w": 8.0, "col": EX_GOLD.lerp(Color.WHITE, 0.3), "glow": EX_RED, "life": 0.05})
	u.grain("bul_spawn", mz + d * 14.0, d, EX_GOLD, 2)
	var mf: Dictionary = a.mzf[k]
	mf.r = 30.0
	info["n"] = int(a.fired)
	info["from"] = mz + d * 16.0
	_ex_bullet(u, a, mz + d * 16.0, dest, tg, k, info)


static func _ex_step(u, a: Dictionary, o) -> bool:
	var t: float = a.t
	var dur: float = a.dur
	var due: int = mini(int(a.ncap), int(t * float(a.rate)) + 1)
	while int(a.fired) < due and t < dur:
		_ex_fire(u, a, o)
		a.fired = int(a.fired) + 1
	var dt: float = maxf(0.0, t - float(a.pt))
	a.pt = t
	_ex_fly(u, a, o, dt)
	if t >= float(a.ring_t) and t < dur:
		a.ring_t = float(a.ring_t) + 0.5
		u.shape({"kind": "ring", "c": o.pos, "r": a.R, "w": 3.0, "col": EX_RED.lerp(EX_GOLD, 0.5), "life": 0.5})
	for k in a.mzf.size():   # 枪口火光跟着她，闪过之后缩回常亮大小
		var mf: Dictionary = a.mzf[k]
		mf.c = o.pos + EX_MZ[k]
		mf.r = maxf(16.0 + 2.0 * sin(t * 40.0 + k), float(mf.r) - 6.0)
		mf.age = 0.0
	_ex_locks(u, a)
	if t >= dur and a.bul.is_empty():
		for lk in a.locks:   # 还挂着的锁定标记就地碎掉（独立实例，动作照常结束）
			u.shapes.erase(lk.s)
			if not lk.fr.is_empty():
				_ex_break(u, lk)
			u.strip("fx_ult_exusiai_lock_orbit", lk.s.c, {"o": Vector2(48, 48), "sc": lk.s.sc, "seg": [6, 7], "col": Color(1.0, 0.72, 0.55)})
		a.locks.clear()
		for mf in a.mzf:
			_ex_drop(mf, 0.2)
		a.mzf = []
		a.fx = []
		var ext = o.get("ext")   # 天赋「快速弹匣」：弹匣直接装满（天赋没解锁 / 计数器没建立就跳过）
		if ext is Dictionary and ext.has("cap") and ext.has("cnt") and ext.cap.has("mag"):
			ext.cnt["mag"] = float(ext.cap["mag"])
		return true
	return false


## 能天使的伤害：连携终结技时份额上限在 a.share（_hit 读 cap，这里换名避免和总发数冲突）
static func _ex_hit(u, a: Dictionary, o, e: Dictionary, frac: float, opt: Dictionary) -> void:
	if a.has("share"):
		var k: int = int(e.id)
		var done: float = float(a.fr.get(k, 0.0))
		frac = minf(frac, float(a.share) - done)
		if frac <= 0.0001:
			return
		a.fr[k] = done + frac
	u.hit(o, e, frac, opt)


## 普通目标（含重型）一次终结技至多打 ult/ex_tgt（100）只：锁定数有上限，聚怪时不会整屏清空（docs/198 §3.4 聚怪 ≤ 75%）；打满后剩余发数打空地
static func _ex_full(a: Dictionary) -> bool:
	return int(a.nhit) >= int(a.tcap)


static func _ex_mark(a: Dictionary, e: Dictionary) -> void:
	a.done[int(e.id)] = true
	a.nhit = int(a.nhit) + 1


static func _ex_undone(a: Dictionary) -> Array:
	var out: Array = []
	if _ex_full(a):
		return out
	for e in a.normals:
		if not e.dead and not a.done.has(int(e.id)):
			out.append(e)
	return out


## 选这一发的目标（开枪时就记「已打」，后面的发数不再挑它；伤害等子弹飞到再结算）
static func _ex_fire(u, a: Dictionary, o) -> void:
	var R: float = a.R
	var tg = null
	var frac := 0.0
	var last := false
	while not a.eq.is_empty():
		var e: Dictionary = a.eq.pop_front()
		if not e.dead:
			tg = e
			frac = 1.0 / float(a.ne)
			last = a.eq.is_empty() or int(a.eq[0].id) != int(e.id)
			break
	var und: Array = []
	if tg == null:
		und = _ex_undone(a)
		if und.is_empty() and not _ex_full(a):   # 锁定的都打完了：重新锁圈内新进来的
			for e in u.in_circle(o.pos, R):
				if not (e.elite or e.boss or e.get("part", false)) and not a.done.has(int(e.id)):
					a.normals.append(e)
			und = _ex_undone(a)
		if und.is_empty():   # 圈里没东西可打：这一发打向圈内空地（按发数黄金角散布，只有画面），弹幕不断
			var i: int = int(a.fired)
			var p: Vector2 = o.pos + Vector2.from_angle(float(i) * 2.39996) * R * (0.35 + 0.6 * fposmod(float(i) * 0.618, 1.0))
			_ex_shoot(u, a, o, p, null, {"kind": "ground"})
			return
		tg = und[0]
		frac = 1.0
	if not (tg.elite or tg.boss or tg.get("part", false)):
		_ex_mark(a, tg)
	_ex_shoot(u, a, o, tg.pos, tg, {"kind": "main", "frac": frac * float(a.mult), "last": last})
	if int(a.fired) % 4 == 0:
		o.face_to((tg.pos - o.pos).angle())
		o.play_vis_anim("attack")


# ================================================================ 浊心斯卡蒂（§4.3）：海嗣张口聚光 → 粗吐息追着敌群烧、经过处接连爆炸 → 收尾大爆 + 领域
## 10-30 用户「激光扫得太快，没有力量感，像随便扫过去；扫过的地方应该爆炸」返工：
## 蓄力 ult/sk_charge（0.35 秒，海嗣升起张口、口中聚光）→ 吐息 ult/sk_sweep（3.4 秒，整段约 4.3 秒）→ 收尾一次大爆（第二个强调点：短顿帧 + 大一点的震屏）。
## 10-30 第二轮（用户「固定扫一圈 → 改成追着打」「吐息力量感不够」「爆炸像好几个小素材拼接」）：
## 吐息不再匀速扫圈，改为锁定目标追着转：每次挑「当前最密的一团没被烧过的敌人」（按角度分 32 格加权、精英 / Boss × 4，离当前朝向越远越扣分），
## 光束以最大角速度 ult/sk_turn（3.2 弧度 / 秒，加速度 ult/sk_turn_acc 14）转过去跟住它；烧到后再停 ult/sk_dwell（0.2 秒）换下一团，目标倒下立刻换；
## 圈里没剩没烧过的就跟着最密的一团烧（只有画面 + 轨迹爆点）。判定：光束（她本人为起点、长 ult/sk_r、半宽 ult/sk_beam_hw 56）或本帧转过的扇面扫到即算烧到。
## 光束画成一整条连续的吐息（不再用 fx_ult_skalter_beam_front 拼接段）：口部往外张开的辉光锥 + 深红主体带 + 青白芯带 + 白芯线 + 口部根焰 + 命中点冲击闪 + 沿线颗粒 / 灯。
## 轨迹爆点由「每 0.055 秒 3 个小爆点」改为每 ult/sk_trail_dt（0.16 秒）把这段时间新烧到的敌人按 70 合并成团、至多 3 团各炸一个大爆点（碎岩团 + 冲击环 + 灼地 + 碎屑 + 灯），
## 没有新烧到的就在命中点炸一个；判定半径仍 ult/sk_trail_r（85）。
## 伤害（份额合计 1）：激光烧到 ult/sk_laser（0.6）+ 轨迹爆点每人一次 ult/sk_trail（0.15）+ 收尾大爆（剩下的 0.25；深海的回响 0.55 / 0.15 / 0.3，领域 9 秒；潮汐和声份额同缺省、每个爆点留 2 秒共鸣地带，见 _sk_zone）；
## 收尾大爆时圈内还没被光束烧到的（追不过来 / 后进圈的）补上激光那一份（单程份额不变：每人至多 激光 + 轨迹 + 大爆 = 1）。判定以她本人为圆心、半径 ult/sk_r（515），外缘 15% 半径为衰减带。
## 领域不再每秒掉血（整段要压在约 4 秒内）：收尾大爆时全队攻击 +20%、队长每秒回复 1.5% 最大生命，持续领域时长（缺省 6 秒，画面同时长）


static func _sk_start(u, o, dir: Vector2) -> Dictionary:
	var rt := _route(o)
	var laps := 1   # 用户 10-30：所有路线都只一程，不来回、不多圈
	var lfrac: float = 0.55 if rt == "resonance" else Bal.v("ult/sk_laser", 0.6)
	var tfrac: float = Bal.v("ult/sk_trail", 0.15)
	var bfrac: float = maxf(0.0, 1.0 - float(laps) * lfrac - tfrac)
	var dd: float = 4.0 if rt == "echo" else (9.0 if rt == "resonance" else Bal.v("ult/sk_dom_t", 6.0))
	# 海嗣（fx_ult_skalter_seaborn_front / _back，同一世界脚底）站在她身后；激光原点 = 海嗣张口处（f6 口在脚底 +8, −99）
	var fs: float = 1.0 if float(u.g.facing) >= 0.0 else -1.0
	var foot := Vector2(-56.0 * fs, -4.0)
	var soff: Vector2 = foot + Vector2(8.0 * fs, -99.0)
	var T: float = Bal.v("ult/sk_sweep", 3.4)
	var ch: float = Bal.v("ult/sk_charge", 0.35)
	var life: float = ch + float(laps) * T + 0.8
	var sf: Dictionary = u.strip("fx_ult_skalter_seaborn_front", o.pos + foot, {"o": Vector2(160, 316), "f": 0, "sx": fs, "life": life})
	var sb: Dictionary = u.strip("fx_ult_skalter_seaborn_back", o.pos + foot, {"o": Vector2(160, 48), "f": 0, "sx": fs, "layer": "back", "life": life})
	var a := {"k": "skalter", "soff": soff, "foot": foot, "sf": sf, "sb": sb, "fx": [sf, sb], "beam": [], "close_t": -1.0,
		"a0": dir.angle(), "cur": dir.angle(), "w": 0.0, "tgt": null, "tgt_hit": -1.0, "laps": laps, "lap": 0, "lfrac": lfrac, "tfrac": tfrac, "bfrac": bfrac, "lseg": {}, "tseg": {},
		"T": T, "L": Bal.v("ult/sk_r", 515.0), "ch": ch, "dd": dd, "pend": [], "newp": [], "trail_t": ch, "nb": 0, "ci_t": 0.0, "blast_t": -1.0, "blasted": false, "fr2": 0,
		"echo": rt == "echo", "col": u._col(o)}
	# 口中聚光（蓄力期间长大，吐息期间成根焰）+ 吐息本体各层（每帧改位置）
	var org: Vector2 = o.pos + soff
	a["cone"] = _sk_keep(u, a, {"kind": "sector", "c": org, "r": 1.0, "a": 0.0, "half": 0.1, "col": COL_SK_RED, "fill": 0.0, "life": life})
	a["halo"] = _sk_keep(u, a, {"kind": "band", "a": org, "b": org, "w": 1.0, "col": COL_SK_RED, "fill": 0.0, "life": life})
	a["body"] = _sk_keep(u, a, {"kind": "band", "a": org, "b": org, "w": 1.0, "col": COL_SK_RED.lerp(Color(1.0, 0.3, 0.35), 0.35), "fill": 0.0, "life": life})
	a["inner"] = _sk_keep(u, a, {"kind": "band", "a": org, "b": org, "w": 1.0, "col": COL_SK_TEAL.lerp(Color.WHITE, 0.35), "fill": 0.0, "life": life})
	a["wire"] = _sk_keep(u, a, {"kind": "line", "a": org, "b": org, "w": 1.0, "col": Color(1.0, 0.95, 0.97), "life": life})
	a["glow"] = _sk_keep(u, a, {"kind": "circle", "c": org, "r": 6.0, "col": COL_SK_TEAL, "fill": 0.85, "life": life})
	a["core"] = _sk_keep(u, a, {"kind": "circle", "c": org, "r": 3.0, "col": Color.WHITE, "fill": 0.95, "life": life})
	a["tipc"] = _sk_keep(u, a, {"kind": "circle", "c": org, "r": 1.0, "col": COL_SK_TEAL, "fill": 0.0, "life": life})
	a["tipw"] = _sk_keep(u, a, {"kind": "circle", "c": org, "r": 1.0, "col": Color(1.0, 0.95, 0.97), "fill": 0.0, "life": life})
	if _sk_v2(u):   # 吐息 v2：程序画的各层带子换成 pixgen 整条光束贴图（两层错开滚动）+ 根部 / 命中点爆闪贴图
		a["v2"] = true
		u.shapes.erase(a.body)   # 只换暗红主体带；外辉光 / 青白芯 / 白芯线 / 命中点亮核照旧（用户 10-30「亮度我喜欢左边的」）
		var bh: float = float(u._strip_tex(SK_BEAM).get_height())
		for key in ["bm", "bm2"]:
			a[key] = u.strip(SK_BEAM, org, {"o": Vector2(0.0, bh * 0.5), "uw": 1.0, "life": life, "col": Color(1, 1, 1, 0.0)})
			a.fx.append(a[key])
		for key in ["rf", "tf"]:
			a[key] = u.strip(SK_FLASH, org, {"sc": 0.1, "life": life, "col": Color(1, 1, 1, 0.0)})
			a.fx.append(a[key])
		for key in ["inner", "wire", "tipw"]:   # 亮芯画在贴图上面
			u.shapes.erase(a[key])
			u.shapes.append(a[key])
	o.play_vis_anim("attack")
	return a


static func _sk_keep(u, a: Dictionary, s: Dictionary) -> Dictionary:
	u.shape(s)
	a.fx.append(s)
	return s


## 海嗣帧号（自己按时间算，写进两个实例的 f）：front 起 0–5（24 fps 快升，0.25 秒）
## → 张口 6–7 乒乓循环（12 fps，蓄力末段到激光结束）→ 激光结束沉下 8–9（12 fps）后收；back 按 manifest front_to_back_frame_mapping 跟 front
const SK_F2B := [0, 0, 1, 1, 2, 2, 3, 4, 5, 5]


static func _sk_sea(u, a: Dictionary, o) -> void:
	if not a.fx.has(a.sf):
		return
	var t: float = a.t
	var ff: int
	if float(a.close_t) >= 0.0:
		ff = 8 + int((t - float(a.close_t)) * 12.0)
		if ff > 9:
			u.shapes.erase(a.sf)
			u.shapes.erase(a.sb)
			a.fx.erase(a.sf)
			a.fx.erase(a.sb)
			return
	elif t < 0.25:
		ff = mini(5, int(t * 24.0))
	else:
		ff = 6 + int((t - 0.25) * 12.0) % 2
	a.sf.f = ff
	a.sb.f = SK_F2B[ff]
	if float(a.close_t) < 0.0:   # 激光期间跟着她走（激光原点同样每帧按她的位置算）
		a.sf.c = o.pos + Vector2(a.foot)
		a.sb.c = a.sf.c


## 轨迹爆点：到点结算（半径 ult/sk_trail_r 85，每人只吃一次轨迹份额）——一团一个大爆点：碎岩炸团 + 白芯闪 + 冲击环 + 灼地 + 掀起的碎岩 + 碎屑 / 灯
static func _sk_trail(u, a: Dictionary, o, p: Vector2, c: Vector2) -> void:
	var rb: float = Bal.v("ult/sk_trail_r", 85.0)
	var er: float = float(a.L) * (1.0 - _edge_w())
	for e in u.in_circle(p, rb):
		if a.tseg.has(int(e.id)):
			continue
		a.tseg[int(e.id)] = true
		_hit(u, a, o, e, float(a.tfrac), {"src": "爆裂", "edge": e.pos.distance_to(c) > er})
	var i: int = int(a.nb)
	a.nb = i + 1
	if not a.has("tp"):
		a["tp"] = []
	a.tp.append(p)   # 轨迹爆点位置：收尾大爆沿这条吐息走过的路裂地（用户 10-31）
	if a.echo:
		_sk_zone(u, a, p)
	if a.get("v2", false):
		_sk_blast_v2(u, p, 1.0, float(i))
	else:
		u.shape({"kind": "circle", "c": p, "r": 40.0, "col": Color(1.0, 0.9, 0.92), "fill": 0.9, "life": 0.07})
		u.shape({"kind": "rock", "c": p, "r": 58.0, "col": COL_SK_RED, "glow": COL_SK_RED.lerp(COL_SK_TEAL, 0.5), "core": COL_SK_TEAL, "seed": float(i), "rot": float(i) * 0.7, "fill": 0.9, "hold": false, "life": 0.22})
		u.shape({"kind": "ring", "c": p, "r": 96.0, "r1": 24.0, "w": 6.0, "col": COL_SK_RED.lerp(Color.WHITE, 0.3), "solid": true, "life": 0.2})
	u.shape({"kind": "ring", "c": p, "r": 130.0, "r1": 30.0, "w": 8.0, "col": COL_SK_TEAL, "life": 0.34})   # 缺省碎裂
	u.shape({"kind": "ellipse", "c": p + Vector2(0, 8), "rx": 70.0, "ry": 32.0, "col": COL_SK_RED.darkened(0.7), "fill": 0.4, "life": 1.1, "layer": "back"})   # 灼地
	for m in 4:   # 掀起的碎岩（带重力）
		var h: float = fposmod(float(i * 5 + m) * 0.618, 1.0)
		var dv := Vector2.from_angle(TAU * (float(m) + h) / 4.0 + float(i) * 0.9)
		u.shape({"kind": "rock", "c": p + dv * 20.0, "r": 8.0 + 7.0 * h, "col": Color(0.2, 0.12, 0.14), "glow": COL_SK_RED, "seed": float(i * 4 + m), "rot": h * TAU, "spin": (h - 0.5) * 10.0,
			"v": dv * (140.0 + 120.0 * h) + Vector2(0, -330.0 - 160.0 * h), "grav": 1500.0, "hold": true, "life": 0.55 + 0.15 * h})
	u.grain("bfx_burst", p, Vector2.from_angle(float(i) * 2.39996), COL_SK_RED if i % 2 == 0 else COL_SK_TEAL, 10)
	u.grain("lava", p, Vector2.UP, COL_SK_RED, 4)
	u.grain("bfx_dust", p, Vector2.UP, Color(0.5, 0.42, 0.45), 4)
	u.light(p, 190.0, COL_SK_RED.lerp(COL_SK_TEAL, 0.25 if i % 2 == 0 else 0.0), 0.26)
	u.debris(p, COL_SK_RED if i % 2 == 0 else COL_SK_TEAL, 2)
	u.shake(4.0, 0.14)


## ---------------- 吐息 v2（ult/sk_beam_v2，缺省 1；0 = 程序画的各层带子版。pixfx 技能，docs/199 §7.7）
## 光束 = pixgen 整条光束贴图（fx_sk_beam，原点左端中心）从口部铺到末端，两层错开往外滚动 + 粗细随脉动；口部 / 命中点 = 爆闪贴图（fx_sk_flash）转着闪；
## 轨迹爆点 = 爆炸贴图（fx_sk_blast）先白亮后冷成暗红、缓出放大；收尾大爆 = 中心大爆 + 一圈错开的爆 + 裂网 + 地块隆起。只画画面
const SK_BEAM := "fx_sk_beam"
const SK_FLASH := "fx_sk_flash"
const SK_BLAST := "fx_sk_blast"
const SK_COLD := Color(0.45, 0.22, 0.26)


static func _sk_v2(u) -> bool:
	return Bal.v("ult/sk_beam_v2", 1.0) > 0.0 and u.fx_ready(SK_BEAM) and u.fx_ready(SK_FLASH) and u.fx_ready(SK_BLAST)


static func _sk_beam_v2(u, a: Dictionary, org: Vector2, tip: Vector2, imp: Vector2, wk: float, t: float) -> void:
	var tex: Texture2D = u._strip_tex(SK_BEAM)
	var k: float = u.g.PX / A.hires_of(tex)
	var tw: float = float(tex.get_width())
	var uw: float = minf(tw, org.distance_to(tip) / k)
	var room: float = maxf(0.0, tw - uw)
	var ang: float = (tip - org).angle()
	var hk: float = 112.0 * wk / (tex.get_height() * k)   # 光束总宽约 112 × 粗细倍率
	var i := 0
	for key in ["bm", "bm2"]:
		var s: Dictionary = a[key]
		s.c = org
		s.ang = ang
		s.uw = uw
		s.ux = floorf(pingpong(t * (520.0 + 170.0 * i) + 130.0 * i, room)) if room > 0.0 else 0.0   # 往外流
		s.sy = hk * (1.0 if i == 0 else -0.78)
		s.col = Color(1.45, 1.3, 1.3, 1.0) if i == 0 else Color(1.3, 1.2, 1.2, 0.6)   # 提亮到接近程序画版（用户 10-30 喜欢原亮度）
		i += 1
	a.rf.c = org
	a.rf.sc = 0.75 * wk
	a.rf.ang = t * 7.0
	a.rf.col = Color(1, 1, 1, 1)
	a.tf.c = imp
	a.tf.sc = (0.9 + 0.25 * sin(t * 41.0)) * wk
	a.tf.ang = -t * 9.0
	a.tf.col = Color(1, 1, 1, 1)


## 一个爆点：爆闪 + 爆炸贴图（缓出放大，白亮 → 暗红余烬）；k = 大小倍率
static func _sk_blast_v2(u, p: Vector2, k: float, seed0: float, delay := 0.0) -> void:
	var bt: Texture2D = u._strip_tex(SK_BLAST)
	var br: float = bt.get_width() * 0.5 * u.g.PX / A.hires_of(bt)
	u.strip(SK_FLASH, p, {"sc": 1.1 * k, "ang": seed0 * 0.9, "life": 0.07, "delay": delay})
	u.strip(SK_BLAST, p, {"sc": 40.0 * k / br, "sc1": 95.0 * k / br, "scd": 0.16, "ang": seed0 * 1.7, "life": 0.38, "fade": 0.22,
		"col": Color.WHITE, "col1": SK_COLD, "cold": 0.22, "delay": delay})


## 收尾大爆 v3（用户 10-31「最后的爆炸应该是在攻击方式内裂地」）：不再以她为圆心放一圈放射裂网，改沿吐息烧过的轨迹——
## 相邻轨迹爆点之间撕开一道暗红裂缝（分叉裂缝贴图顺着路径铺、从吐息起点往末端依次裂开），每个轨迹点（至多 10 个）再炸一团 + 碎岩 + 逐帧烟尘。判定不动
static func _sk_final_v3(u, tp: Array, c: Vector2) -> void:
	var pts: Array = []
	var step: int = maxi(1, ceili(float(tp.size()) / 10.0))
	for i in range(0, tp.size(), step):
		pts.append(tp[i])
	var t: Texture2D = u._strip_tex(UL_FORK) if u.fx_ready(UL_FORK) else null
	var tw: float = t.get_width() / A.hires_of(t) * u.g.PX if t != null else 1.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var dl: float = 0.04 * i   # 从吐息起点往末端依次炸开
		var h: float = _ulh(i * 3.7 + 600.0)
		_sk_blast_v2(u, p, 0.9 + 0.5 * h, float(i), dl)
		if t != null and i + 1 < pts.size():   # 裂缝顺着这一段轨迹撕开
			var q: Vector2 = pts[i + 1]
			var seg: Vector2 = q - p
			if seg.length() > 30.0:
				u.strip(UL_FORK, p, {"layer": "back", "ang": seg.angle(), "o": Vector2(0.0, t.get_height() * 0.5),
					"sx": seg.length() * 1.15 / tw, "sy": (0.7 if i % 2 == 0 else 0.5) * (1.0 if h < 0.5 else -1.0),
					"rev": 0.12, "rev0": 0.15, "delay": dl, "life": 1.9, "fade": 0.7, "col": Color(1.0, 0.75, 0.8), "col1": Color(0.4, 0.22, 0.26), "cold": 0.7})
		if t != null and h < 0.5:   # 轨迹点上再往旁边岔一条短裂缝
			u.strip(UL_FORK, p, {"layer": "back", "ang": (p - c).angle() + (h - 0.25) * 2.4, "o": Vector2(0.0, t.get_height() * 0.5),
				"sx": (90.0 + 80.0 * h) / tw, "sy": 0.4, "rev": 0.12, "rev0": 0.15, "delay": dl + 0.04, "life": 1.6, "fade": 0.6,
				"col": Color(1.0, 0.75, 0.8), "col1": Color(0.4, 0.22, 0.26), "cold": 0.6})
		for m in 2:
			var hm: float = _ulh(i * 5.0 + m + 700.0)
			var dv := Vector2.from_angle(hm * TAU)
			_ul_rock(u, p + dv * 20.0, dv * 50.0, 160.0 + 160.0 * hm, hm, 0.45, dl + 0.02 * m)
		if i % 2 == 0:
			PF.dust(u, p, 170.0 + 60.0 * h, dl + 0.06, h * 40.0 + i, (p - c).normalized() * 40.0, Color(1.0, 0.82, 0.84))


## 收尾大爆：中心大爆 + 外围一圈错开的爆 + 裂网（借乌尔比安分叉裂缝，调成暗红）+ 地块隆起
static func _sk_final_v2(u, c: Vector2, L: float) -> void:
	_sk_blast_v2(u, c, 1.8, 3.0)
	for m in 7:
		var h: float = _ulh(m + 70.0)
		_sk_blast_v2(u, c + Vector2.from_angle(TAU * (m + h) / 7.0) * L * (0.45 + 0.25 * h), 0.9, float(m), 0.04 + 0.04 * (m % 4))
	if u.fx_ready(UL_FORK):
		var t: Texture2D = u._strip_tex(UL_FORK)
		var tw: float = t.get_width() / A.hires_of(t) * u.g.PX
		for j in 11:
			var h1: float = _ulh(j + 80.0)
			u.strip(UL_FORK, c, {"layer": "back", "ang": TAU * (j + (h1 - 0.5) * 0.7) / 11.0, "o": Vector2(0.0, t.get_height() * 0.5),
				"sx": L * (0.6 + 0.4 * _ulh(j + 90.0)) / tw, "sy": (0.8 if j % 3 == 0 else 0.5) * (1.0 if j % 2 == 0 else -1.0),
				"rev": 0.28, "rev0": 0.15, "life": 1.9, "fade": 0.7, "col": Color(1.0, 0.75, 0.8), "col1": Color(0.4, 0.22, 0.26), "cold": 0.7})
	for q in 18:
		var hh: float = _ulh(q * 7.0 + 300.0)
		var dv := Vector2.from_angle(TAU * (q + 0.6 * hh) / 18.0)
		_ul_rock(u, c + dv * L * (0.3 + 0.6 * hh), dv * 40.0, (120.0 + 60.0 * hh) if q % 3 else (300.0 + 120.0 * hh), hh, 0.5, 0.03 * (q % 4))


## 挑下一个追的目标：圈内（没烧过的优先）敌人按角度分 32 格加权（精英 / Boss × 4），相邻格平滑后除以 (1 + 0.6 × 与当前朝向的角差)，
## 取最高那格里的精英 / Boss，否则取离格中心角最近的一只；圈里没人 → null
static func _sk_pick(u, a: Dictionary, c: Vector2):
	var L: float = a.L
	var all: Array = u.in_circle(c, L)
	var cand: Array = []
	for e in all:
		if not a.lseg.has(int(e.id)):
			cand.append(e)
	if cand.is_empty():
		cand = all
	if cand.is_empty():
		return null
	var NB := 32
	var bins: Array = []
	bins.resize(NB)
	bins.fill(0.0)
	for e in cand:
		var b: int = int(floor(fposmod((e.pos - c).angle(), TAU) / TAU * NB)) % NB
		bins[b] = float(bins[b]) + (4.0 if (e.elite or e.boss or e.get("part", false)) else 1.0)
	var cur: float = a.cur
	var best := -1
	var bs := -1.0
	for b in NB:
		var s: float = float(bins[b]) + 0.5 * (float(bins[(b + 1) % NB]) + float(bins[(b + NB - 1) % NB]))
		if s <= 0.0:
			continue
		var ang: float = (float(b) + 0.5) * TAU / NB
		s /= 1.0 + 0.6 * absf(wrapf(ang - cur, -PI, PI))
		if s > bs:
			bs = s
			best = b
	var mid: float = (float(best) + 0.5) * TAU / NB
	var pick = null
	var pd := INF
	for e in cand:
		var ea: float = (e.pos - c).angle()
		var dA: float = absf(wrapf(ea - mid, -PI, PI))
		if dA > 1.5 * TAU / NB:
			continue
		var sc: float = dA - (1.0 if (e.elite or e.boss or e.get("part", false)) else 0.0)
		if sc < pd:
			pd = sc
			pick = e
	return pick


static func _sk_step(u, a: Dictionary, o, dt: float) -> bool:
	var L: float = a.L
	var T: float = a.T
	var ch: float = a.ch
	var t: float = a.t
	var org: Vector2 = o.pos + Vector2(a.soff)
	var c: Vector2 = o.pos
	# 到点的轨迹爆点
	for k in range(a.pend.size() - 1, -1, -1):
		var pd: Array = a.pend[k]
		if t >= float(pd[0]):
			_sk_trail(u, a, o, pd[1], pd[2])
			a.pend.remove_at(k)
	_sk_sea(u, a, o)
	if t < ch:   # 蓄力：海嗣张口，口中聚光（深红 / 青绿光往口里收）；同时先挑好第一个目标、光束朝向它
		var kc: float = t / ch
		a.glow.c = org
		a.glow.r = lerpf(6.0, 38.0, kc * kc)
		a.core.c = org
		a.core.r = lerpf(3.0, 18.0, kc)
		a.glow.age = 0.0
		a.core.age = 0.0
		if a.tgt == null:
			a.tgt = _sk_pick(u, a, c)
			if a.tgt != null:
				a.cur = (a.tgt.pos - c).angle()
		if t >= float(a.ci_t):
			a.ci_t = t + 0.08
			var j: int = int(t * 100.0)
			_ring(u, org, 12.0, 150.0, COL_SK_RED if j % 2 == 0 else COL_SK_TEAL, 0.16, 4.0)
			for m in 6:   # 光点往口里收
				var dv := Vector2.from_angle(float(m) * TAU / 6.0 + float(j) * 0.7)
				u.grain("mote_in", org + dv * 110.0, -dv, COL_SK_TEAL if m % 2 == 0 else COL_SK_RED, 2)
			u.light(org, lerpf(60.0, 200.0, kc), COL_SK_TEAL, 0.1)
		if a.get("v2", false):   # 口中爆闪贴图跟着长大
			a.rf.c = org
			a.rf.sc = lerpf(0.15, 0.6, kc * kc)
			a.rf.ang = t * 6.0
			a.rf.col = Color(1, 1, 1, kc)
		u.shake(2.0, 0.15)
		return false
	if int(a.lap) < int(a.laps):
		var tb: float = t - ch
		# 追目标：目标倒下 / 烧到后停留 ult/sk_dwell 秒 → 换下一团
		var tg = a.tgt
		if tg != null and (tg.dead or tg.pos.distance_to(c) > L + 40.0):
			tg = null
		if tg != null and float(a.tgt_hit) >= 0.0 and t - float(a.tgt_hit) >= Bal.v("ult/sk_dwell", 0.2):
			tg = null
		if tg == null:
			tg = _sk_pick(u, a, c)
			a.tgt = tg
			a.tgt_hit = -1.0
		var prev: float = a.cur
		var wmax: float = Bal.v("ult/sk_turn", 3.2)
		var wd := 0.0
		if tg != null:
			wd = clampf(wrapf((tg.pos - c).angle() - prev, -PI, PI) * 7.0, -wmax, wmax)
		else:
			wd = 0.6   # 圈里没人：慢慢转着烧
		a.w = move_toward(float(a.w), wd, Bal.v("ult/sk_turn_acc", 14.0) * dt)
		a.cur = prev + float(a.w) * dt
		var cur: float = a.cur
		var dir: Vector2 = Vector2.from_angle(cur)
		var tip: Vector2 = c + dir * L
		# 判定：光束（她为起点、半宽 ult/sk_beam_hw）或本帧转过的扇面
		var hw: float = Bal.v("ult/sk_beam_hw", 56.0)
		var er: float = L * (1.0 - _edge_w())
		var dA: float = wrapf(cur - prev, -PI, PI)
		for e in u.in_circle(c, L):
			if a.lseg.has(int(e.id)):
				continue
			var d: Vector2 = e.pos - c
			var along: float = d.dot(dir)
			var hit: bool = d.length() < 24.0 or (along > 0.0 and absf(d.cross(dir)) <= hw + float(e.get("r", 10.0)) * 0.5)
			if not hit and absf(dA) > 0.0001:
				var rel: float = wrapf(d.angle() - prev, -PI, PI)
				hit = (rel * signf(dA) >= 0.0) and absf(rel) <= absf(dA)
			if hit:
				a.lseg[int(e.id)] = true
				a.newp.append(e.pos)
				_hit(u, a, o, e, float(a.lfrac), {"src": "激光", "edge": d.length() > er})
				if e == tg and float(a.tgt_hit) < 0.0:
					a.tgt_hit = t
		# 命中点：追着的目标在光束上就是它，否则光束末端
		var imp: Vector2 = tip
		if tg != null and not tg.dead:
			var dq: Vector2 = tg.pos - c
			if dq.dot(dir) > 0.0 and absf(dq.cross(dir)) <= hw * 1.5:
				imp = c + dir * clampf(dq.dot(dir), 60.0, L)
		# 吐息本体（一整条连续的程序画，不拼帧条）：口部往外张开的辉光锥 → 深红主体带 → 青白芯带 → 白芯线；口部根焰 + 命中点冲击闪
		var bw: float = Bal.v("ult/sk_beam_w", 1.6)
		var pul: float = 1.0 + 0.1 * sin(t * 37.0) + 0.05 * sin(t * 61.0)
		var ramp: float = clampf(tb / 0.12, 0.25, 1.0)   # 起喷 0.12 秒内从细到满
		var blen: float = org.distance_to(tip)
		var bang: float = (tip - org).angle()
		a.cone.c = org
		a.cone.r = blen
		a.cone.a = bang
		a.cone.half = atan2(110.0 * bw * ramp * pul * 0.5, maxf(1.0, blen))
		a.cone.fill = 0.2
		a.halo.a = org
		a.halo.b = tip
		a.halo.w = 104.0 * bw * ramp * pul
		a.halo.fill = 0.3
		a.body.a = org
		a.body.b = tip
		a.body.w = 62.0 * bw * ramp * pul
		a.body.fill = 0.85
		a.inner.a = org
		a.inner.b = tip
		a.inner.w = 24.0 * bw * ramp * (1.0 + 0.2 * sin(t * 53.0))
		a.inner.fill = 0.95
		a.wire.a = org
		a.wire.b = tip
		a.wire.w = 7.0 * pul
		a.glow.c = org
		a.glow.r = 48.0 * pul
		a.core.c = org
		a.core.r = 24.0 * pul
		a.tipc.c = imp
		a.tipc.r = 62.0 * pul
		a.tipc.fill = 0.6
		a.tipw.c = imp
		a.tipw.r = 26.0 * pul
		a.tipw.fill = 0.95
		for s in [a.cone, a.halo, a.body, a.inner, a.wire, a.glow, a.core, a.tipc, a.tipw]:
			s.age = 0.0
		if a.get("v2", false):
			_sk_beam_v2(u, a, org, tip, imp, bw * ramp * pul, t)
		u.shake(3.5, 0.2)   # 吐息全程小幅持续震
		var fr2: int = int(a.fr2)
		var side: Vector2 = dir.orthogonal()
		for m in 3:   # 沿线颗粒：往两侧迸 + 顺着光束冲出去
			var bp: Vector2 = org.lerp(tip, 0.2 + 0.27 * float(m) + 0.08 * float(fr2 % 3))
			u.grain("bfx_flash", bp, side * (1.0 if (fr2 + m) % 2 == 0 else -1.0), COL_SK_TEAL if m == 1 else COL_SK_RED, 2)
		u.grain("lava", imp, -dir, COL_SK_RED, 2)
		u.grain("bfx_burst", imp, Vector2.from_angle(cur + PI + 0.6 * sin(t * 23.0)), COL_SK_TEAL if fr2 % 2 == 0 else COL_SK_RED, 2)
		if fr2 % 4 == 0:
			u.light(imp, 200.0, COL_SK_RED, 0.1)
			u.light(org.lerp(tip, 0.45), 220.0, COL_SK_TEAL, 0.1)
			u.light(org, 140.0, COL_SK_TEAL, 0.1)
		if fr2 % 3 == 0:   # 光束根部往外喷的气浪
			u.shape({"kind": "ring", "c": org, "r": 56.0, "r1": 20.0, "w": 6.0, "col": COL_SK_TEAL.lerp(Color.WHITE, 0.3), "solid": true, "life": 0.12})
		# 轨迹爆点：每 ult/sk_trail_dt 秒把新烧到的敌人按 70 合并成团，至多 3 团各炸一个（延迟 0.08 秒）；没有新烧到就在命中点炸一个
		if t >= float(a.trail_t):
			a.trail_t = t + Bal.v("ult/sk_trail_dt", 0.16)
			var pts: Array = a.newp
			var made := 0
			while not pts.is_empty() and made < 3:
				var p0: Vector2 = pts[0]
				var sum := Vector2.ZERO
				var n := 0
				for k in range(pts.size() - 1, -1, -1):
					if Vector2(pts[k]).distance_to(p0) <= 70.0:
						sum += Vector2(pts[k])
						n += 1
						pts.remove_at(k)
				a.pend.append([t + 0.08 + 0.04 * float(made), sum / float(n), c])
				made += 1
			if made == 0:
				a.pend.append([t + 0.06, imp, c])
			a.newp = []   # 一拍排不完的不再另炸（没吃到轨迹份额的由收尾大爆补上）
		a.fr2 = fr2 + 1
		if tb >= T:
			a.lap = int(a.lap) + 1
			if int(a.lap) >= int(a.laps):
				for s in [a.cone, a.halo, a.body, a.inner, a.wire, a.tipc, a.tipw]:
					u.shapes.erase(s)
					a.fx.erase(s)
				for key in ["bm", "bm2", "tf"]:
					if a.has(key):
						u.shapes.erase(a[key])
						a.fx.erase(a[key])
				a.newp = []
				a.close_t = t   # 海嗣沉下
				a.blast_t = t + Bal.v("ult/sk_blast_delay", 0.12)
				_ring(u, org, 10.0, 160.0, COL_SK_TEAL, 0.12, 8.0)   # 口中的光往回一收
		return false
	# 收尾大爆（第二个强调点）：她周围半径 L 一次炸开，短顿帧 + 大一点的震屏；之后留下领域（画面 + 增益）
	if not a.blasted and t >= float(a.blast_t):
		a.blasted = true
		for s in [a.glow, a.core]:
			u.shapes.erase(s)
			a.fx.erase(s)
		if a.has("rf"):
			u.shapes.erase(a.rf)
			a.fx.erase(a.rf)
		var er2: float = L * (1.0 - _edge_w())
		for e in u.in_circle(c, L):   # 收尾大爆份额 + 光束没烧到 / 轨迹没炸到的补上那一份（每人单程合计至多 1）
			var bf: float = float(a.bfrac) + (0.0 if a.lseg.has(int(e.id)) else float(a.lfrac)) + (0.0 if a.tseg.has(int(e.id)) else float(a.tfrac))
			a.lseg[int(e.id)] = true
			a.tseg[int(e.id)] = true   # 之后才到点的轨迹爆点不再打它
			if bf > 0.0:
				_hit(u, a, o, e, bf, {"src": "爆裂", "edge": e.pos.distance_to(c) > er2, "kb": (e.pos - c).normalized() * _kb_v(160.0)})
		u.g.vfx.stop(Bal.v("ult/sk_blast_freeze", 0.08), "ult", true)
		u.shake(9.0, 0.45)
		# 收尾大爆：不铺满屏实心红圆（10-30 美术口径），中心一团碎块炸开 + 一圈圈碎裂冲击 + 大量颗粒 / 碎屑
		if a.get("v2", false):
			var n0: int = u.shapes.size()
			var v3: bool = Bal.v("ult/sk_fx_v3", 1.0) > 0.0 and a.get("tp", []).size() >= 2
			if v3:
				_sk_final_v3(u, a.tp, c)
				PF.hf_since(u, n0, [SK_BLAST])   # 打击感（10-31）：收尾大爆冲击帧（爆团剪影）+ 顿帧
				PF.hf_on(u, a)
				u.g.vfx.stop(Bal.v("ult/sk_hitstop", 0.1), "ult", true)
			else:
				_sk_final_v2(u, c, L)
		else:
			u.shape({"kind": "rock", "c": c, "r": 90.0, "col": COL_SK_RED, "glow": COL_SK_RED.lerp(COL_SK_TEAL, 0.4), "core": COL_SK_TEAL, "seed": 5.0, "fill": 0.9, "hold": false, "life": 0.22})
		for m2 in 16:
			var dm: Vector2 = Vector2.from_angle(TAU * float(m2) / 16.0 + 0.2)
			u.grain("bfx_burst", c + dm * L * 0.3, dm, COL_SK_RED if m2 % 2 == 0 else COL_SK_TEAL, 6)
			u.grain("lava", c + dm * L * 0.6, dm, COL_SK_RED, 3)
		u.debris(c, COL_SK_RED, 3)
		_ring(u, c, L, 40.0, COL_SK_RED.lerp(Color.WHITE, 0.3), 0.5, 18.0)
		u.light(c, L, COL_SK_RED, 0.5)
		u.debris(c, COL_SK_RED, 3)
		for m in 8:
			var dq := Vector2.from_angle(float(m) * TAU / 8.0 + 0.3)
			u.debris(c + dq * L * 0.6, COL_SK_TEAL if m % 2 == 0 else COL_SK_RED, 2)
			u.grain("bfx_burst", c + dq * L * 0.35, dq, COL_SK_RED, 8)
		_ring(u, c, L * 0.92, 30.0, COL_SK_TEAL, 0.55, 10.0, 0.04)
		_ring(u, c, L * 0.7, 20.0, COL_SK_RED.lerp(Color.WHITE, 0.3), 0.5, 6.0, 0.08)
		for m in (0 if a.get("v2", false) else 16):
			var dv := Vector2.from_angle(float(m) * TAU / 16.0 + 0.1)
			u.shape({"kind": "blade", "a": c + dv * 60.0, "b": c + dv * 200.0, "w": 10.0, "col": COL_SK_TEAL.lerp(Color.WHITE, 0.3), "glow": COL_SK_TEAL if m % 2 == 0 else COL_SK_RED,
				"life": 0.32, "v": dv * 900.0})
		u.shape({"kind": "dots", "c": c, "r": L * 0.9, "n": 40, "col": COL_SK_TEAL.lerp(Color.WHITE, 0.3), "life": 0.6})
		var dd: float = a.dd
		u.shape({"kind": "ring", "c": c, "r": L, "w": 6.0, "col": COL_SK_RED, "life": dd, "layer": "back"})   # 领域边：碎裂像素环（原实心淡红圆）
		# 领域花纹（fx_ult_skalter_domain_back 弧状拼接段，地面层循环）：铺在领域边上往里 20，外缘不出伤害圈
		_arc(u, "fx_ult_skalter_domain_back", c, L - 20.0, {"layer": "back", "loop": true, "life": dd})
		u.team_buff("ult:skalter_dom", dd, [[&"dmg", "mult", Bal.v("ult/sk_atk", 1.2)], [&"regen_pct", "flat", Bal.v("ult/sk_heal", 0.015)]], c, L)   # 只在领域里生效（协调人 10-30）
		o.play_vis_anim("attack")
	return a.blasted and a.pend.is_empty() and not a.fx.has(a.sf)


# ================================================================ 凯尔希（§4.4）：Mon3tr 冲到落点 → 熔毁三圈 → 8 秒后重构

static func _ka_m3(o):
	var sm = o.get("sm")
	if sm is Dictionary and sm.has("list"):
		for s in sm.list:
			if str(s.kind) == "mon3tr" and not s.get("gone", false):
				return s
	return null


## 10-30 用户「太快了，突然就炸了，不知道发生了什么」返工：Mon3tr 本体（真召唤物，leap 帧条 + 残影）跃到落点 ult/ka_leap（0.28–0.5 秒，按距离）→
## 落地蓄力 ult/ka_wind（0.6 秒，不伤害）：地面预警圈（实线外圈 + 由外往里收的光圈 + 往中心聚的光点 + 淡色危险区）、Mon3tr 身上聚能光团越长越大、震屏渐强 →
## 爆点（「Mon3tr，就在这」）：Mon3tr 身上白芯爆闪 → 从它脚下扩出整圈冲击环 + 放射斩光 + 掀起的地块（带重力）+ 碎屑 / 大灯，同时它解体（8 秒后照旧重构）；
## 三圈熔毁伤害与原来一致（每圈 ult/ka_ring 份、合计 cap 1），只是整体推后到蓄力之后；冲击帧（顿帧 + 慢放）由第一圈命中自动触发，碎裂冲击波改由这里在落点画（no_ring）
const KA_COL := Color(0.35, 0.95, 0.85)
const KA_HOT := Color(1.0, 0.35, 0.2)


static func _ka_start(u, o, aim: Vector2) -> Dictionary:
	var rt := _route(o)
	var sc: float = Bal.v("ult/ka_r", 580.0) / 460.0 * (400.0 / 460.0 if rt == "melt" else 1.0)
	var m3 = _ka_m3(o)
	var p0: Vector2 = m3.pos if m3 != null else o.pos
	var c: Vector2 = aim if aim != Vector2.INF else o.pos
	var cd: float = clampf(p0.distance_to(c) / Bal.v("ult/ka_leap_v", 1400.0), Bal.v("ult/ka_leap", 0.28), 0.5)
	var wind: float = Bal.v("ult/ka_wind", 0.6)
	if m3 != null:
		_ka_leap(o, m3, c, cd, cd + wind + 0.2)   # 跃过去后原地蓄力（不出手、不跟人），爆点时解体
	o.play_vis_anim("attack")
	o.face_to((c - o.pos).angle())
	# 三圈都是实心圆、由内往外依次炸：每圈对圈内敌人打 ult/ka_ring（0.6）份预算，每名敌人合计至多 1 份（cap / fr）——
	# 小怪在它所在的最内一圈就倒（不再只有内两圈打得死）；精英 / Boss 第一下就吃满 1 份（docs/198 §3.4 对齐，10-30）
	var kf: float = Bal.v("ult/ka_ring", 0.6)
	var rs: Array = [180.0 * sc, 320.0 * sc, 460.0 * sc]
	var a := {"k": "kaltsit", "cap": 1.0, "fr": {}, "p0": p0, "c": c, "cd": cd, "wind": wind, "rs": rs, "fs": [kf, kf, kf], "sc": sc,
		"ring": 0, "segs": [{}, {}, {}], "push": {}, "prev": p0, "had": m3 != null, "m3": m3, "shell": rt == "shell", "no_ring": true,
		"rebuild_t": 0.0 if rt == "melt" else Bal.v("ult/ka_gone", 8.0), "melt_t": -1.0, "back": false, "ci_t": 0.0, "fx": []}
	return a


## Mon3tr 跃到落点：直接写召唤物的 dash 状态（同精英化段的跃回，ob_elite._el_dash_start 的字段）——位移 / leap 帧条 / 残影都由召唤物自己画；
## dash 期间召唤物不选目标、不出手（end = 蓄力结束后再留 0.2 秒兜底，正常在爆点就解体了）
static func _ka_leap(o, s: Dictionary, to: Vector2, dur: float, hold: float) -> void:
	if not s.has("ak"):
		return
	s["dash"] = {"k": "leap", "from": s.pos, "to": to, "t": 0.0, "t0": 0.0, "dur": dur, "end": hold, "h": 80.0, "h_now": 0.0, "land": {}, "done": false, "hist": []}
	s.act = hold
	s.fire = -1.0
	s.pend = []
	if absf(to.x - s.pos.x) > 2.0:
		s.face = signf(to.x - s.pos.x)
		s.flip_t = o.g.t
	s.ak = "leap"
	s.at = 0.0


static func _ka_alive(a: Dictionary) -> bool:
	var m3 = a.m3
	return m3 != null and not m3.get("gone", false)


static func _ka_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var cd: float = a.cd
	var c: Vector2 = a.c
	var rs: Array = a.rs
	var R: float = float(rs[2])
	if t < cd:   # 跃过去：Mon3tr 本体在飞（召唤物自己画），这里补一道青绿能量拖尾；冲锋路径撞开小怪（不伤害）
		var k: float = t / cd
		var p: Vector2 = a.m3.pos if _ka_alive(a) else Vector2(a.p0).lerp(c, 1.0 - (1.0 - k) * (1.0 - k))
		for e in u.in_band(a.prev, p, 50.0):
			if e.elite or e.boss or a.push.has(int(e.id)):
				continue
			a.push[int(e.id)] = true
			var dv: Vector2 = (p - Vector2(a.prev)).normalized().orthogonal()
			if dv.dot(e.pos - p) < 0.0:
				dv = -dv
			g.enemies_sys.apply_kb(e, dv * _kb_v(90.0))
		var hy: Vector2 = Vector2(0, -40.0 - 80.0 * sin(k * PI)) if _ka_alive(a) else Vector2.ZERO
		u.shape({"kind": "line", "a": Vector2(a.prev) + Vector2(0, -40.0), "b": p + hy, "w": 9.0, "col": KA_COL, "life": 0.22})
		if not _ka_alive(a):
			u.shape({"kind": "circle", "c": p, "r": 20.0, "col": KA_COL, "fill": 0.9, "life": 0.05})
		u.grain("mote_up", p + hy, (Vector2(a.prev) - p).normalized(), KA_COL, 2)
		# 落点预警从起跳就开始淡淡亮起（让人先看见「要砸到哪」）
		if not a.has("warn"):
			a["warn"] = _ka_keep(u, a, {"kind": "ring", "c": c, "r": R, "w": 6.0, "col": KA_COL, "solid": true, "life": 9.0, "layer": "back"})
			a["zone"] = _ka_keep(u, a, {"kind": "circle", "c": c, "r": R, "col": KA_COL.darkened(0.55), "fill": 0.0, "life": 9.0, "layer": "back"})
			a["inner"] = _ka_keep(u, a, {"kind": "circle", "c": c, "r": float(rs[0]), "col": KA_HOT.darkened(0.3), "fill": 0.0, "life": 9.0, "layer": "back"})
		_ka_warn(a, k * 0.35, t)
		a.prev = p
		return false
	var wind: float = a.wind
	var t1: float = cd + wind
	if t < t1:   # 落地蓄力：不伤害；地面预警越来越亮、光往落点收、Mon3tr 身上聚能
		var kw: float = (t - cd) / wind
		var core: Vector2 = (a.m3.pos if _ka_alive(a) else c) + Vector2(0, -38.0)
		if not a.get("charged", false):
			a["charged"] = true
			# 落地：一圈尘、轻震，熔毁蓄力帧条（fx_ult_kaltsit_melt_front charge 0–2）铺满蓄力时长
			u.strip("fx_ult_kaltsit_melt_front", c, {"o": Vector2(192, 192), "seg": [0, 2], "fps": 3.0 / wind, "life": t1 - t, "sc": float(a.sc)})
			_ring(u, c, 150.0, 30.0, KA_COL.lerp(Color.WHITE, 0.4), 0.3, 8.0)
			u.grain("bfx_dust", c, Vector2.UP, Color(0.75, 0.8, 0.8), 10)
			u.shake(3.0, 0.15)
			a["aura"] = _ka_keep(u, a, {"kind": "ring", "c": core, "r": 40.0, "w": 4.0, "col": KA_COL.lerp(Color.WHITE, 0.3), "solid": true, "life": 9.0})   # 罩住 Mon3tr 本体的聚能圈（不盖住它）
			a["glow"] = _ka_keep(u, a, {"kind": "circle", "c": core, "r": 8.0, "col": KA_COL, "fill": 0.45, "life": 9.0})
			a["hot"] = _ka_keep(u, a, {"kind": "circle", "c": core, "r": 4.0, "col": Color(0.9, 1.0, 0.97), "fill": 0.95, "life": 9.0})
			if _ka_v2(u):   # 蓄力压暗：落点一大片地面渐暗
				a["v2"] = true
				a["dark"] = _ka_keep(u, a, {"kind": "circle", "c": c, "r": R * 1.12, "col": Color(0.0, 0.01, 0.02), "fill": 0.0, "life": 9.0, "layer": "back"})
		var pul: float = 1.0 + 0.15 * sin(t * (30.0 + 40.0 * kw))
		a.glow.c = core
		a.glow.r = lerpf(8.0, 36.0, kw * kw) * pul
		a.hot.c = core + Vector2(0, -6.0)
		a.hot.r = lerpf(4.0, 13.0, kw) * pul
		a.aura.c = core
		a.aura.r = lerpf(58.0, 42.0, kw) * (1.0 + 0.06 * sin(t * 45.0))
		a.aura.w = lerpf(3.0, 6.0, kw)
		for s in [a.glow, a.hot, a.aura]:
			s.age = 0.0
		_ka_warn(a, 0.35 + 0.65 * kw, t)
		if a.has("dark"):
			a.dark.fill = 0.65 * kw
			a.dark.age = 0.0
		# 收光：越到后面越密（0.14 → 0.06 秒一道），外圈往落点收的光圈 + 光点
		if t >= float(a.ci_t):
			a.ci_t = t + lerpf(0.14, 0.06, kw)
			var j: int = int(t * 100.0)
			u.shape({"kind": "ring", "c": c, "r": 24.0, "r1": R * lerpf(0.95, 0.6, kw), "w": 6.0, "col": KA_COL.lerp(Color.WHITE, 0.3 if j % 2 == 0 else 0.0), "solid": true, "life": 0.3, "layer": "back"})
			for m in 8:
				var dv := Vector2.from_angle(float(m) * TAU / 8.0 + float(j) * 0.37)
				u.grain("mote_in", c + dv * R * 0.8, -dv, KA_COL if m % 2 == 0 else Color(0.9, 1.0, 0.97), 2)
			u.light(core, lerpf(80.0, 260.0, kw), KA_COL, 0.16)
		u.shake(1.0 + 3.0 * kw, 0.12)
		return false
	while int(a.ring) < 3 and t >= t1 + 0.15 * float(a.ring):
		var i: int = int(a.ring)
		var r0: float = 0.0 if i == 0 else float(rs[i - 1])
		if i == 0:
			_ka_blast(u, a, o)
		var opt := {"src": "熔毁", "big": 1.0}
		if i == 0:
			opt["stun"] = Bal.v("ult/ka_stun", 1.0)
		_hit_circle(u, a, o, c, float(rs[i]), float(a.fs[i]), a.segs[i], opt, R)
		var col: Color = KA_HOT.lerp(Color.WHITE, 0.5 - 0.2 * i)
		_ring(u, c, float(rs[i]), maxf(30.0, r0), col, 0.35, 10.0 - 2.0 * i)
		if a.get("v2", false):   # v2：不再画同心炽热实线 + 弧段裂纹；沿圈地块隆起，最外圈尘土墙外推 + 余震
			_ka_ring_v2(u, c, float(rs[i]), i, R)
		else:
			# 每圈：沿圈一道连续的炽热实线（程序画，整圈不断）+ 一圈掀起的地块；裂纹帧条（fx_ult_kaltsit_crack_back，地面层）只作点缀
			u.shape({"kind": "ring", "c": c, "r": float(rs[i]), "w": 9.0 - 2.0 * i, "col": KA_HOT.lerp(Color(1.0, 0.85, 0.5), 0.4), "solid": true, "life": 0.55, "layer": "back"})
			_arc(u, "fx_ult_kaltsit_crack_back", c, float(rs[i]), {"layer": "back", "fps": 14.0, "life": 0.7})
			_ka_chunks(u, c, float(rs[i]), 6 + 2 * i, i)
		if i > 0:
			u.shake(5.0 - 1.0 * i, 0.2)
		if i == 0 and a.shell:
			u.team_buff("ult:kaltsit_shell", Bal.v("ult/ka_shell_t", 5.0), [[&"dmg_taken", "mult", Bal.v("ult/ka_shell", 0.7)]])
		a.ring = i + 1
		if a.ring == 3:
			a.melt_t = t
	if int(a.ring) < 3:
		return false
	_fx_end(u, a)
	if float(a.rebuild_t) <= 0.0:
		_m3_back(u, o, true)
	else:   # 动作到最后一圈就结束（下一次终结技不用等 8 秒）；重构由 tick_bg 每帧看点
		o.set_meta("ult_m3_back", u.g.t + float(a.rebuild_t))
		o.set_meta("ult_m3_heal", true)
	return true


static func _ka_keep(u, a: Dictionary, s: Dictionary) -> Dictionary:
	u.shape(s)
	a.fx.append(s)
	return s


## 地面预警（k 0..1 越来越亮；后段闪烁加快）
static func _ka_warn(a: Dictionary, k: float, t: float) -> void:
	if not a.has("warn"):
		return
	var fl: float = 0.75 + 0.25 * sin(t * lerpf(12.0, 40.0, k))
	a.warn.col = Color(KA_COL, 1.0)
	a.warn.w = lerpf(4.0, 9.0, k)
	a.zone.fill = lerpf(0.06, 0.22, k) * fl
	a.inner.fill = lerpf(0.0, 0.3, k * k) * fl
	for s in [a.warn, a.zone, a.inner]:
		s.age = 0.0


## 爆点：Mon3tr 身上白芯爆闪 → 它脚下扩出整圈冲击环 + 放射斩光 + 掀起的地块 + 碎屑 / 大灯；Mon3tr 解体（8 秒后照旧重构）
static func _ka_blast(u, a: Dictionary, o) -> void:
	var c: Vector2 = a.c
	var R: float = float(a.rs[2])
	var core: Vector2 = (a.m3.pos if _ka_alive(a) else c) + Vector2(0, -38.0)
	for key in ["glow", "hot", "aura", "dark"]:
		if a.has(key):
			u.shapes.erase(a[key])
			a.fx.erase(a[key])
	if a.has("warn"):   # 预警圈闪白后淡掉
		a.warn.col = Color.WHITE
		a.warn.age = 0.0
		a.warn.max = 0.18
		a.fx.erase(a.warn)
		for key in ["zone", "inner"]:
			u.shapes.erase(a[key])
			a.fx.erase(a[key])
	if _ka_alive(a):
		o.ObSummon._sm_end(o, a.m3, "leave")   # Mon3tr 炸开用掉：8 秒内不在场（不执行 on_expire）
		o.set_meta("ult_m3_back", u.g.t + 9.0)   # 兜底：动作被中途清掉时，下次任何人放终结技会补回 Mon3tr
	if a.get("v2", false):
		var n0: int = u.shapes.size()
		_ka_blast_v2(u, c, core, R)
		if Bal.v("ult/ka_fx_v3", 1.0) > 0.0:   # 打击感（10-31）：红色粒子爆炸进冲击帧剪影 + 顿帧；Mon3tr 不加烟团（用户 10-30）
			PF.hf_since(u, n0)
			PF.hf_on(u, a)
			u.g.vfx.stop(Bal.v("ult/ka_hitstop", 0.12), "ult", true)
		u.light(core, R * 0.9, KA_RED, 0.6)
		u.light(c, 300.0, Color(1.0, 0.55, 0.45), 0.25)
		u.shake(9.0, 0.4)
		return
	# 白芯爆闪（Mon3tr 身上）+ 青绿外焰
	u.shape({"kind": "circle", "c": core, "r": 150.0, "col": KA_COL, "fill": 0.55, "life": 0.18})
	u.shape({"kind": "circle", "c": core, "r": 78.0, "col": Color(0.95, 1.0, 0.98), "fill": 1.0, "life": 0.12})
	u.shape({"kind": "circle", "c": c, "r": float(a.rs[0]), "col": KA_HOT, "fill": 0.35, "life": 0.2, "layer": "back"})
	# 从落点扩出去的整圈冲击环（实线，0.25 秒扩到外圈）+ 紧跟一圈碎裂冲击
	u.shape({"kind": "ring", "c": c, "r": R, "r1": 40.0, "w": 15.0, "col": Color(0.9, 1.0, 0.97), "solid": true, "life": 0.5})
	u.shape({"kind": "ring", "c": c, "r": R * 1.08, "r1": 30.0, "w": 10.0, "col": KA_COL, "life": 0.7, "delay": 0.05})
	for m in 14:   # 放射斩光
		var dv := Vector2.from_angle(TAU * float(m) / 14.0 + 0.15)
		u.shape({"kind": "blade", "a": c + dv * 50.0, "b": c + dv * (180.0 + 40.0 * float(m % 3)), "w": 11.0, "col": Color(0.9, 1.0, 0.97), "glow": KA_COL if m % 2 == 0 else KA_HOT,
			"life": 0.3, "v": dv * 950.0})
	_ka_chunks(u, c, 60.0, 10, 7)
	u.debris(c, KA_COL, 3)
	u.debris(c, KA_HOT, 3)
	u.light(core, R * 0.8, KA_COL, 0.6)
	u.light(c, 260.0, Color(1.0, 0.95, 0.85), 0.25)
	for m in 12:
		var dq := Vector2.from_angle(TAU * float(m) / 12.0)
		u.grain("bfx_burst", c + dq * 40.0, dq, KA_COL if m % 2 == 0 else KA_HOT, 8)
		u.grain("bfx_dust", c + dq * 120.0, dq, Color(0.7, 0.75, 0.75), 4)
	u.shake(9.0, 0.4)


## ---------------- 爆点 v2（ult/ka_blast_v2，缺省 1；0 = 程序画白圈 + 放射斩光版。pixfx 技能，docs/199 §7.7）
## 蓄力时落点一片地面渐暗（压暗）+ 预兆细裂纹 → 爆点：压暗撤掉、pixgen 红色大爆炸（fx_ka_blast，白亮 → 暗色余烬、缓出放大）+ 细实线冲击环扩到外圈
## 用户 10-30 两轮：「m3 的爆炸用红色比较好」→「都改成全红色，不需要裂地，更突出红色的粒子爆炸感」：不画裂网 / 预兆裂纹 / 尘土墙，
## 每圈沿圈接连炸几团小红爆 + 红色颗粒 / 火星→ 每圈地块隆起、最外圈尘土墙外推 + 余震碎石。三圈判定 / 时序 / 伤害不动
const KA_RED := Color(0.9, 0.16, 0.12)


static func _ka_v2(u) -> bool:
	return Bal.v("ult/ka_blast_v2", 1.0) > 0.0


static func _ka_blast_v2(u, c: Vector2, core: Vector2, R: float) -> void:
	# 用户 10-30 第七轮：「Mon3tr 不是爆炸物也不是纯生物，做成粒子爆炸就可以」——不放烟团 / 血肉 / 散落小爆：
	# 红白爆闪 → 三层红色粒子帧条（fx_px_burst，预烘焙）错开 0.05 秒从核心叠着迸开、由大到小（外层先到外圈）+ 一层近爆密核 + 一道红环 + 落地余烬
	var vs: float = PF.vseed(u, core)
	u.shape({"kind": "circle", "c": core, "r": 80.0, "col": Color(1.0, 0.32, 0.28), "fill": 0.95, "life": 0.07})
	var reds := [Color(0.95, 0.07, 0.07), Color(1.0, 0.14, 0.12), Color(0.8, 0.04, 0.06)]   # 用户 10-30「更红一点，现在像橙色」：去掉橙调
	for l in 3:
		PF.particles(u, core, 300, "ult_burst", [reds[l]], 0.05 * l, vs + l * 11.0, R * (0.9 - 0.18 * l))
	PF.particles(u, core, 100, "ult_burst_s", [Color(1.0, 0.2, 0.16)], 0.02, vs + 40.0, 150.0)
	u.shape({"kind": "ring", "c": c, "r": R, "r1": 40.0, "w": 8.0, "col": Color(0.95, 0.3, 0.22), "life": 0.5})
	u.spark(core, Color(1.0, 0.18, 0.14), 14, 40.0)
	u.light(core, R * 0.9, KA_RED, 0.5)


## 每圈：v2 不再沿圈散小爆（像烟花），只在圈上扬一圈尘（尘土墙预审报拼接感，去掉）
static func _ka_ring_v2(u, c: Vector2, r: float, i: int, R: float) -> void:
	for q in 8:
		var dq := Vector2.from_angle(TAU * (q + PF.h(q + i)) / 8.0)
		u.grain("bfx_dust", c + dq * r, dq, Color(0.5, 0.42, 0.4), 3)
	if i == 0:
		u.light(c, R * 0.7, KA_RED, 0.4)


## 掀起的地块：沿半径 r 的圈抛出 n 块碎岩（带重力，往外上方飞、转着落下）
static func _ka_chunks(u, c: Vector2, r: float, n: int, seed0: int) -> void:
	for m in n:
		var h: float = fposmod(float(m * 7 + seed0 * 13) * 0.618, 1.0)
		var dv := Vector2.from_angle(TAU * (float(m) + h * 0.5) / float(n) + float(seed0) * 0.4)
		var p: Vector2 = c + dv * r
		u.shape({"kind": "rock", "c": p, "r": 9.0 + 9.0 * h, "col": Color(0.24, 0.27, 0.3), "glow": KA_HOT if seed0 % 2 == 0 else KA_COL, "seed": float(m + seed0 * 11),
			"rot": h * TAU, "spin": (h - 0.5) * 9.0, "v": dv * (160.0 + 160.0 * h) + Vector2(0, -360.0 - 200.0 * h), "grav": 1500.0, "hold": true, "life": 0.6 + 0.2 * h})
	u.grain("bfx_dust", c, Vector2.UP, Color(0.7, 0.72, 0.72), 3)


## Mon3tr 重构（heal = 队长回复 8% 最大生命）
static func _m3_back(u, o, heal: bool) -> void:
	if o.has_meta("ult_m3_back"):
		o.remove_meta("ult_m3_back")
	if o.has_meta("ult_m3_heal"):
		o.remove_meta("ult_m3_heal")
	if o.pos == Vector2.INF or _ka_m3(o) != null:
		return
	var kd: Dictionary = o.ObSummon.sm_kind(o, "mon3tr")
	if kd.is_empty():
		return
	o.ObSummon.sm_spawn(o, {"kind": "mon3tr", "at": "rest"}, Vector2.INF)
	var m3 = _ka_m3(o)
	if m3 != null:   # 重构（fx_ult_kaltsit_rebuild_orbit，底部中心 = 脚底，12 帧 0.75 秒）：只是结构线特效，本体就是这只真 Mon3tr；_m3_watch 让它跟着走
		o.set_meta("ult_m3_fx", u.strip("fx_ult_kaltsit_rebuild_orbit", m3.pos, {"o": Vector2(128, 253)}))
	if heal:
		u.g.combat.heal(u.g.max_hp * Bal.v("ult/ka_heal", 0.08), "终结技", "kaltsit")


## 每帧（ult.tick）：凯尔希熔毁后到点重构 Mon3tr（ult_m3_heal = 正常结束，重构时给队长回血；动作被中途清掉的兜底不回血）
static func tick_bg(u) -> void:
	_m3_watch(u)
	_sk_zones(u)


## 潮汐和声（skalter 路线 echo，协调人 10-30 定，取代原「扫两圈、第二圈反向」）：每个轨迹爆点留下一块共鸣地带 ult/sk_echo_t（2 秒）——
## 半径 ult/sk_echo_r（90）内的敌人减速（引擎统一减速档：移速 × 0.65，即 −35%）、受到的伤害 + ult/sk_echo_amp（15%，走 e.frag_t / frag_v 通用增伤，同名取最高）；
## 离已有地带不到 70 的爆点不另起一块（同一处不叠）。地带挂在 u 的 meta「sk_zones」上由 tick_bg 推进，终结技动作本身照常结束；地面层画干员色像素椭圆
static func _sk_zone(u, a: Dictionary, p: Vector2) -> void:
	var zs: Array = u.get_meta("sk_zones", [])
	for z in zs:
		if Vector2(z[0]).distance_squared_to(p) < 70.0 * 70.0:
			return
	var dur: float = Bal.v("ult/sk_echo_t", 2.0)
	var r: float = Bal.v("ult/sk_echo_r", 90.0)
	zs.append([p, u.g.t + dur, r, Bal.v("ult/sk_echo_amp", 0.15), 0.0])
	u.set_meta("sk_zones", zs)
	var col: Color = a.col
	u.shape({"kind": "ellipse", "c": p + Vector2(0, 4), "rx": r, "ry": r * 0.55, "col": col.darkened(0.25), "fill": 0.32, "life": dur, "layer": "back"})
	u.shape({"kind": "ring", "c": p + Vector2(0, 4), "r": r * 0.8, "w": 4.0, "col": col, "life": dur, "layer": "back"})   # 缺省碎裂：地带边上一圈碎光


static func _sk_zones(u) -> void:
	if not u.has_meta("sk_zones"):
		return
	var g = u.g
	var zs: Array = u.get_meta("sk_zones")
	for k in range(zs.size() - 1, -1, -1):
		var z: Array = zs[k]
		if g.t >= float(z[1]):
			zs.remove_at(k)
			continue
		if g.t < float(z[4]):
			continue
		z[4] = g.t + 0.1   # 每 0.1 秒刷一次（减速 / 增伤各给 0.25 秒，走出地带很快失效）
		var p: Vector2 = z[0]
		var r: float = z[2]
		for j in g.enemies_sys.query(p, r):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.get("friendly", false) or e.pos.distance_squared_to(p) > r * r:
				continue
			g.enemies_sys.add_cc(e, -INF, 0.25)
			var amp: float = float(z[3])
			if float(e.get("frag_t", 0.0)) <= g.t or float(e.get("frag_v", 0.0)) <= amp:
				e["frag_v"] = amp if float(e.get("frag_t", 0.0)) <= g.t else maxf(float(e.get("frag_v", 0.0)), amp)
				e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), g.t + 0.25)
		if int(g.t * 10.0) % 4 == 0:
			u.grain("mote_up", p, Vector2.UP, COL_SK_TEAL, 1)
	if zs.is_empty():
		u.remove_meta("sk_zones")


static func _m3_watch(u) -> void:
	if u.g.squad == null:
		return
	for m in u.g.squad.ops:
		if m.has_meta("ult_m3_back") and u.g.t >= float(m.get_meta("ult_m3_back")):
			_m3_back(u, m, m.has_meta("ult_m3_heal"))
		if m.has_meta("ult_m3_fx"):
			var s: Dictionary = m.get_meta("ult_m3_fx")
			var m3 = _ka_m3(m)
			if m3 == null or float(s.age) >= float(s.max):
				m.remove_meta("ult_m3_fx")
			else:
				s.c = m3.pos


# ================================================================ 乌尔比安（§4.5）：掷锚 → 沿锁链冲过去 → 落地 4 圈裂地

static func _ul_start(u, o, aim: Vector2) -> Dictionary:
	var rt := _route(o)
	var c: Vector2 = aim if aim != Vector2.INF else o.pos
	var sc: float = Bal.v("ult/ul_r", 615.0) / 440.0 * (410.0 / 440.0 if rt == "drag" else 1.0)
	# 四圈实心圆由内往外依次裂开：每圈对圈内敌人打 ult/ul_ring（0.6）份预算，锁链 ult/ul_path（0.2），每名敌人合计至多 1 份（cap / fr）——
	# 小怪在它所在的最内一圈就倒；精英 / Boss 裂地第一下补满 1 份（docs/198 §3.4 对齐，10-30）
	var uf: float = Bal.v("ult/ul_ring", 0.6)
	return {"k": "ulpianus", "cap": 1.0, "fr": {}, "sc": sc, "p0": o.pos, "c": c, "ta": Bal.v("ult/ul_throw", 0.18), "td": Bal.v("ult/ul_dash", 0.22),
		"hw": 110.0 if rt == "rift" else 80.0, "rift": rt == "rift", "drag": rt == "drag", "pseg": {}, "landed": false, "thrown": false,
		"rs": [110.0 * sc, 220.0 * sc, 330.0 * sc, 440.0 * sc], "fs": [uf, uf, uf, uf], "ring": 0, "segs": [{}, {}, {}, {}]}


static func _ul_step(u, a: Dictionary, o) -> bool:
	var g = u.g
	var t: float = a.t
	var p0: Vector2 = a.p0
	var c: Vector2 = a.c
	var ta: float = a.ta
	var td: float = a.td
	if t < ta:   # 锚飞出去
		var tip: Vector2 = p0.lerp(c, t / ta)
		_ul_anchor(u, a, tip, (c - p0).angle())
		_ul_chain(u, a, o.pos, tip, (c - p0).angle())
		return false
	if not a.thrown:
		a.thrown = true
		_ul_anchor(u, a, c, (c - p0).angle())   # 锚扎在落点，等他冲过来
		_ring(u, c, 90.0, 20.0, COL_STEEL, 0.25, 5.0)
		if Bal.v("ult/ul_crack_v2", 1.0) > 0.0 and u.fx_ready(UL_CRACK):
			_ul_pre(u, a, c)
		if a.drag:   # 不容挣脱：锚落地瞬间把半径 560 内的敌人往落点拖 120
			for e in u.in_circle(c, 560.0 * float(a.sc) / (410.0 / 440.0)):
				if not e.boss and e.pos.distance_to(c) > 30.0:
					g.enemies_sys.apply_kb(e, (c - e.pos).normalized() * _kb_v(120.0) * (0.5 if e.elite else 1.0))
	if not a.landed:   # 沿锁链冲过去：队长本人位移，期间无敌
		var k: float = clampf((t - ta) / td, 0.0, 1.0)
		var p: Vector2 = p0.lerp(c, k * k)
		g.ppos = p
		o.pos = p
		g.invuln = maxf(g.invuln, 0.15)
		g.invuln_move_until = g.t + 0.15
		var hw: float = a.hw
		for e in u.in_band(p0, p, hw * 0.5):
			if a.pseg.has(int(e.id)):
				continue
			a.pseg[int(e.id)] = true
			_hit(u, a, o, e, Bal.v("ult/ul_path", 0.2), {"src": "锁链", "stun": 0.8 if a.rift else 0.0, "pre": true})   # pre：冲击帧留给第一圈裂地
			if a.rift and not e.boss:
				g.enemies_sys.add_cc(e, 0.8, -INF, "airborne")
		u.shape({"kind": "band", "a": p0, "b": p, "w": hw, "col": COL_STEEL, "fill": 0.07, "life": 0.1})
		if _ul_v3() and k > 0.3 and int(t * 60.0) % 2 == 0:   # 冲锋拖影（smear）：身后一条拉长的淡带，代替补间（pixfx §6.6）
			u.shape({"kind": "band", "a": p.lerp(p0, 0.35), "b": p, "w": 46.0, "col": Color(0.75, 0.9, 1.0), "fill": 0.35, "life": 0.06})
		_ul_chain(u, a, o.pos, c, (c - p0).angle())
		if k >= 1.0 and not a.landed:
			a.landed = true
			a["land_t"] = t
			_fx_end(u, a)   # 落地：收锚、收锁链
			if g.get("map") != null and g.map.has_method("push_out"):
				g.ppos = g.map.push_out(g.ppos, 12.0)
				o.pos = g.ppos
			var hw4 = o.get("hw")   # 落地后 5 秒锚击间隔 −30%：沿用 S3 的 haste 计时（他的数据里没有这个计时就跳过）
			if hw4 is Dictionary and hw4.has("timers"):
				hw4.timers["haste"] = maxf(float(hw4.timers.get("haste", 0.0)), Bal.v("ult/ul_haste", 5.0))
			o.play_vis_anim("attack")
		return false
	var lt: float = a.land_t
	var rs: Array = a.rs
	var lc: Vector2 = c
	while int(a.ring) < 4 and t >= lt + 0.18 * float(a.ring):
		var i: int = int(a.ring)
		var opt := {"src": "裂地"}
		if i == 3:
			opt["stun"] = Bal.v("ult/ul_stun", 1.2)
		var r: float = rs[i]
		var r0: float = 0.0 if i == 0 else float(rs[i - 1])
		for e in u.in_circle(lc, r):
			if a.segs[i].has(int(e.id)):
				continue
			a.segs[i][int(e.id)] = true
			var op: Dictionary = opt.duplicate()
			op["edge"] = e.pos.distance_to(lc) > float(rs[3]) * (1.0 - _edge_w())
			if i == 3 and e.pos.distance_to(lc) > 1.0:
				op["kb"] = (e.pos - lc).normalized() * _kb_v(Bal.v("ult/ul_kb", 200.0))
			_hit(u, a, o, e, 1.0 if (e.elite or e.boss or e.get("part", false)) else float(a.fs[i]), op)
		var col: Color = COL_STEEL.lerp(Color(1.0, 0.55, 0.3), 0.25 * i)
		_ring(u, lc, r, maxf(30.0, r0), col, 0.35, 8.0 + 2.0 * i)
		# 裂地：v2 = pixgen 整条裂缝沿圈接成一圈 + 掀起地块 / 尘土（_ul_crack_v2）；0 = fx_ult_ulpianus_crack_back 弧状拼接段（地面层）
		if Bal.v("ult/ul_crack_v2", 1.0) > 0.0 and u.fx_ready(UL_CRACK):
			_ul_crack_v2(u, a, lc, i, r, r0)
		else:
			_arc(u, "fx_ult_ulpianus_crack_back", lc, r, {"layer": "back", "fps": 14.0, "life": 0.7, "a0": 0.21 * i})
		# 沿圈撒喷发单元（fx_ult_ulpianus_burst_front，底部中心；喷 0–3 / 落 4–7）
		var nb: int = clampi(roundi(TAU * r / 140.0), 5, int(Bal.v("ult/ul_burst_fx", 14.0)))
		var bsc: float = 0.6 + 0.07 * i   # 水柱是竖着的高度，外圈也压在 0.8 以内，免得顶上一圈高出伤害区太多
		for j in nb:
			var ang: float = 0.37 * i + TAU * (float(j) + 0.5 * float(i % 2)) / float(nb)
			u.strip("fx_ult_ulpianus_burst_front", lc + Vector2.from_angle(ang) * r, {"o": Vector2(64, 192), "sc": bsc,
				"delay": 0.02 * float((j * 3) % 4)})
		o.screen_shake(0.35 + 0.15 * i)
		a.ring = i + 1
	return int(a.ring) >= 4 and t >= lt + 0.18 * 3.0 + 0.1


## 裂地 v2（ult/ul_crack_v2，缺省 1；0 = 原弧状拼接段。pixgen 出的大贴图 + 代码动画，docs/199 §7.6）。用户 10-30 两轮反馈：
## 放射 6 条「像大海星」→ 沿圈粗裂缝「力量感不够」→ 本版按「不规整 + 明暗冷却 + 地面隆起 + 前后节奏」：
##   预兆：锚扎地时落点先冒几道细裂纹（_ul_pre）；
##   裂网：第一圈裂开时从落点放 UL_CRACKS 条分叉裂缝（fx_ul_crack_fork，左端粗、往右变细带分叉，原点左端中心），
##         长短 / 角度 / 起裂时刻都按哈希错开，跟着四圈的时序逐段往外长；先爆亮再冷成暗色余烬（col1）；
##   隆起：每圈沿圈地块（fx_ul_rock）被顶起一小跳落回，少数高飞；第一圈尘土环扩散，最外圈尘土墙（fx_ul_dust_wall 截段）往外推；
##   余震：最外圈 0.3 秒后再跳一批碎石。水柱、范围环照旧。只画画面：不调 u.hit、不抽模拟随机数（散布按 _ulh 哈希）
const UL_CRACK := "fx_ul_crack_line"
const UL_FORK := "fx_ul_crack_fork"
const UL_FORKS := ["fx_ul_crack_fork", "fx_ul_crack_fork2", "fx_ul_crack_fork3", "fx_ul_crack_fork4"]   # 变体（用户 10-30「多做几种」）
const PF = preload("res://scripts/run/ult_pixfx.gd")
const UL_CRACKS := 13
const UL_HOT := Color(1.0, 1.0, 1.0)
const UL_COLD := Color(0.42, 0.4, 0.48)


static func _ulh(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


static func _ul_tex(u) -> String:
	return UL_FORK if u.fx_ready(UL_FORK) else UL_CRACK


## 预兆：锚扎进落点那一刻，落点冒几道短而暗的细裂纹，等他冲过来（约 0.22 秒）
static func _ul_pre(u, a: Dictionary, c: Vector2) -> void:
	var name := _ul_tex(u)
	var t: Texture2D = u._strip_tex(name)
	var tw: float = t.get_width() / A.hires_of(t) * u.g.PX
	for j in 5:
		u.strip(name, c, {"layer": "back", "ang": TAU * (j + _ulh(j + 40.0)) / 5.0, "o": Vector2(0.0, t.get_height() * 0.5),
			"sx": (90.0 + 40.0 * _ulh(j + 50.0)) / tw, "sy": 0.35, "rev": float(a.td), "life": float(a.td) + 0.5, "fade": 0.3,
			"col": Color(0.55, 0.7, 0.8, 0.7)})


static func _ul_crack_v2(u, a: Dictionary, lc: Vector2, i: int, r: float, r0: float) -> void:
	var R: float = float(a.rs[3])
	var span: float = 0.18 * 3.0
	if i == 0:   # 裂网一次铺好，靠 delay / rev 跟着四圈往外长；每次出招按 vseed 挑变体、条数、角度、长短、镜像
		if _ul_v3():
			a["hf"] = true   # 冲击帧剪影（打击感试点，pixfx §6.6）
			u.act["hf"] = true
		var vs: float = PF.vseed(u, lc)
		a["vs"] = vs
		var base: float = (a.c - a.p0).angle() if a.c.distance_to(a.p0) > 1.0 else 0.0
		var nc: int = UL_CRACKS - 2 + int(_ulh(vs + 3.0) * 5.0)   # 11–15 条
		var turn: float = (_ulh(vs + 5.0) - 0.5) * 0.6   # 整体偏一点，第一条不再死对冲锋方向
		for j in nc:
			var name := PF.pick(u, UL_FORKS, vs * 0.37 + j * 1.7)
			if name == "":   # 变体都没导入（新拉的工作树没 ensure_imported）时别拿空贴图
				name = UL_CRACK
			var t: Texture2D = u._strip_tex(name)
			var tw: float = t.get_width() / A.hires_of(t) * u.g.PX
			var h1: float = _ulh(j + 1.0 + vs)
			var h2: float = _ulh(j + 21.0 + vs)
			var ang: float = base + turn + TAU * (float(j) + (h1 - 0.5) * 0.75) / nc
			var lk: float = 0.62 + 0.45 * h2   # 长短不一，长的伸出外圈一点
			var big: bool = _ulh(j + 9.0 + vs) < 0.33
			var dl: float = 0.06 * _ulh(j + 33.0 + vs)
			u.strip(name, lc, {"layer": "back", "ang": ang, "o": Vector2(0.0, t.get_height() * 0.5), "hf": true,
				"sx": R * lk / tw, "sy": (0.85 if big else 0.55) * (1.0 if _ulh(j + 17.0 + vs) < 0.5 else -1.0),
				"delay": dl, "rev": span * lk + 0.08, "rev0": 0.18, "life": span + 1.6, "fade": 0.7,
				"col": UL_HOT, "col1": UL_COLD, "cold": span + 0.45})
		u.light(lc, R * 0.8, Color(0.4, 0.9, 1.0), 0.35)
		if u.fx_ready("fx_ul_dust_ring"):   # 贴图半径约 210，只给第一圈，放到外圈像素格会糊成大块
			var dt: Texture2D = u._strip_tex("fx_ul_dust_ring")
			var dr: float = dt.get_width() * 0.5 / A.hires_of(dt) * u.g.PX
			u.strip("fx_ul_dust_ring", lc, {"layer": "back", "sc": r * 0.6 / dr, "sc1": r * 1.15 / dr, "scd": 0.35,
				"life": 0.55, "fade": 0.3, "col": Color(1, 1, 1, 0.7)})
	# 隆起：沿这一圈地块被顶起一小跳落回；每 4 块里 1 块高飞
	var nr: int = roundi(TAU * r / 120.0 * Bal.v("ult/ul_rock_fx", 1.0))
	for q in nr:
		var hh: float = _ulh(i * 31.0 + q * 7.0 + float(a.get("vs", 0.0)))
		var dirv: Vector2 = Vector2.from_angle(0.37 * i + float(a.get("vs", 0.0)) + TAU * (q + 0.6 * hh) / maxf(1.0, nr))
		var p: Vector2 = lc + dirv * r * (0.86 + 0.16 * hh)
		var high: bool = q % 4 == 0
		var vy: float = (260.0 + 160.0 * hh + 30.0 * i) if high else (110.0 + 60.0 * hh)
		_ul_rock(u, p, dirv * ((60.0 + 80.0 * hh) if high else 25.0), vy, hh, (0.55 if high else 0.45) + 0.06 * i, 0.02 * (q % 3))
		if q % 3 == 0:
			u.debris(p, Color(0.35, 0.8, 0.95), 2 if i < 3 else 3)
			u.grain("bfx_dust", p, dirv, Color(0.55, 0.6, 0.62), 3)
	if i == 3:
		# 尘土墙（同张截段排一圈）改逐帧烟尘：外圈 7 团、延迟错开、往外推（pixfx §6.6 烟尘；预审曾报尘土墙拼接）；ult/ul_fx_v3 0 = 旧尘土墙
		if not _ul_v3():
			_ul_wall(u, lc, r)
		for q in (7 if _ul_v3() else 0):
			var hq: float = _ulh(q * 4.1 + float(a.get("vs", 0.0)))
			var pq: Vector2 = lc + Vector2.from_angle(TAU * (q + hq) / 7.0) * r * (0.85 + 0.2 * hq)
			PF.dust(u, pq, 190.0 + 80.0 * hq, 0.03 * (q % 3), hq * 40.0 + q, (pq - lc).normalized() * (50.0 + 40.0 * hq), Color(0.85, 0.92, 0.95))   # 逐帧烟尘往外推（偏冷灰，配深海）
		for q in 10:   # 余震：0.3 秒后满圈再跳一批碎石
			var hh2: float = _ulh(q * 5.0 + 99.0 + float(a.get("vs", 0.0)))
			var p2: Vector2 = lc + Vector2.from_angle(TAU * (q + hh2) / 10.0) * R * (0.25 + 0.7 * hh2)
			_ul_rock(u, p2, Vector2.ZERO, 120.0 + 60.0 * hh2, hh2, 0.4, 0.3 + 0.05 * (q % 3))
	u.light(lc, r * 1.1, Color(0.3, 0.75, 0.95), 0.22)


static func _ul_rock(u, p: Vector2, v: Vector2, vy: float, hh: float, sc: float, delay: float) -> void:
	PF.rock(u, p, v, vy, hh, sc, delay)   # 两组地块按哈希挑、随机镜像


## 最外圈尘土墙：fx_ul_dust_wall 截成弦长段沿圈摆一圈，整圈往外推、淡出
static func _ul_wall(u, lc: Vector2, r: float) -> void:
	if not u.fx_ready("fx_ul_dust_wall"):
		return
	var t: Texture2D = u._strip_tex("fx_ul_dust_wall")
	var k: float = u.g.PX / A.hires_of(t)
	var n: int = maxi(12, roundi(TAU * r / 150.0))
	var chord: float = 2.0 * r * sin(PI / n)
	var uw: float = minf(t.get_width(), chord * 1.15 / k)
	for q in n:
		var a0: float = TAU * q / n
		var p0: Vector2 = lc + Vector2.from_angle(a0) * r
		var p1: Vector2 = lc + Vector2.from_angle(a0 + TAU / n) * r
		var d: Vector2 = (p1 - p0).normalized()
		var out: Vector2 = Vector2.from_angle(a0 + PI / n)
		u.strip("fx_ul_dust_wall", p0 - d * chord * 0.07, {"layer": "back", "ang": d.angle(), "o": Vector2(0.0, t.get_height() * 0.5),
			"ux": floorf(_ulh(q * 3.0 + 7.0) * (t.get_width() - uw)), "uw": uw, "v": out * 140.0,
			"life": 0.6, "fade": 0.4, "col": Color(1, 1, 1, 0.85)})


## 巨锚（fx_ult_ulpianus_anchor_front）：4 个角度帧 f0–f3 = 锚头朝下（+90°）起每帧顺时针 45°；
## 按飞行方向取最近的角度帧（超过 180° 的用对面那帧转半圈），剩下的差角用旋转补；不按 fps 播
static func _ul_anchor(u, a: Dictionary, p: Vector2, dir_ang: float) -> void:
	var rho: float = dir_ang - PI / 2.0
	var k: int = posmod(roundi(rho / (PI / 4.0)), 8)
	var f: int = k % 4
	if not a.has("anc"):
		a["anc"] = u.strip("fx_ult_ulpianus_anchor_front", p, {"o": Vector2(96, 96), "f": f, "life": float(a.ta) + float(a.td) + 0.3})
		if not a.has("fx"):
			a["fx"] = []
		a.fx.append(a.anc)
	var s: Dictionary = a.anc
	s.c = p
	s.f = f
	s.ang = rho - f * PI / 4.0


## 锁链（fx_ult_ulpianus_chain_front 拼接段，循环 0–1）：从他手边铺到锚尾（锚中心往回 60），每帧重铺
static func _ul_chain(u, a: Dictionary, from: Vector2, tip: Vector2, dir_ang: float) -> void:
	if not a.has("chain"):
		a["chain"] = []
	_kill(u, a.chain)
	var b: Vector2 = tip - Vector2.from_angle(dir_ang) * 60.0
	var p: Vector2 = from + Vector2(0, -20)
	if (b - p).dot(Vector2.from_angle(dir_ang)) < 8.0:
		return
	a.chain = u.tiles_line("fx_ult_ulpianus_chain_front", p, b, {"f": int(float(a.t) * 12.0) % 2, "life": 0.3})


# ================================================================ 连携终结技通用版（§7.3）

static func _cult_generic_start(u, o, aim: Vector2, dir: Vector2) -> Dictionary:
	var g = u.g
	var lead: Dictionary = start(u, o, aim, dir)
	var fr := {}
	if str(lead.get("k", "")) == "exusiai":
		lead["share"] = 1.0
	else:
		lead["cap"] = 1.0
	lead["fr"] = fr
	var mates: Array = []
	var others: Array = []
	for m in g.squad.ops:
		if m != o and not m.is_leader and m.pos != Vector2.INF and m.cmd_down <= 0.0:
			others.append(m)
	var hx: float = u.VIEW.x * 0.5 - 80.0
	var hy: float = u.VIEW.y * 0.5 - 80.0
	var land: float = Bal.v("ult/cult_land", 0.45)
	for i in others.size():
		var m = others[i]
		var org: Vector2 = g.ppos + Vector2.from_angle(dir.angle() + TAU * (float(i) + 0.5) / float(others.size())) * 320.0
		var tp: Vector2 = m.densest_point(260.0, org)
		if tp == Vector2.INF or tp.distance_to(org) > 360.0:
			tp = org
		tp = Vector2(clampf(tp.x, g.ppos.x - hx, g.ppos.x + hx), clampf(tp.y, g.ppos.y - hy, g.ppos.y + hy))
		var stop: Vector2 = tp - (tp - m.pos).normalized() * 30.0 if tp.distance_to(m.pos) > 30.0 else m.pos
		var dur: float = land * 0.8
		m.syn_mv = {"from": m.pos, "to": stop, "t": 0.0, "dur": dur}
		m.cmd_inv = maxf(m.cmd_inv, land + 0.4)
		m._set_face(1.0 if stop.x >= m.pos.x else -1.0, true)
		u.shape({"kind": "line", "a": m.pos, "b": stop, "w": 8.0, "col": u._col(m), "life": land + 0.15})
		mates.append({"m": m, "p": stop})
	_ring(u, g.ppos, 120.0, 20.0, u._col(o).lerp(Color.WHITE, 0.5), land, 6.0)
	return {"style": "generic", "o": o, "lead": lead, "lead_done": lead.is_empty(), "mates": mates, "t": 0.0, "land": land, "landed": false, "cleared": false}


static func _cult_generic_step(u, a: Dictionary, dt: float) -> bool:
	var g = u.g
	a.t = float(a.t) + dt
	var o = a.o
	if not a.lead_done:
		a.lead_done = step(u, a.lead, dt)
	var lead: Dictionary = a.lead
	var land: float = a.land
	if not a.landed and float(a.t) >= land:
		a.landed = true
		var mr: float = Bal.v("ult/cult_mate_r", 300.0)
		for mt in a.mates:   # 队友的放大冲击（打在各自落点；份额和队长共用，合计不超过 1）
			var m = mt.m
			var p: Vector2 = mt.p
			var col: Color = u._col(m)
			_ring(u, p, mr, 40.0, col.lerp(Color.WHITE, 0.4), 0.5, 12.0)
			u.shape({"kind": "circle", "c": p, "r": mr, "col": col, "fill": 0.3, "life": 0.4})
			u.shape({"kind": "dots", "c": p, "r": mr, "n": 18, "col": col.lerp(Color.WHITE, 0.5), "life": 0.5})
			if m.pos != Vector2.INF:
				m.play_vis_anim("attack")
			if not lead.is_empty():
				for e in u.in_circle(p, mr):
					_cult_hit(u, lead, m, e, {"src": "放大冲击"})
		# 屏内所有敌人按连携终结技档一次补满（u.tier = cult）
		var vr: float = u.VIEW.length() * 0.5
		var cc: Color = u._col(o).lerp(Color.WHITE, 0.5)
		_ring(u, g.ppos, vr, 100.0, cc, 0.8, 14.0)
		u.shape({"kind": "circle", "c": g.ppos, "r": vr, "col": u._col(o), "fill": 0.18, "life": 0.45})
		u.shape({"kind": "dots", "c": g.ppos, "r": vr * 0.9, "n": 48, "col": cc, "life": 0.7})
		for e in u.in_view(g.ppos):
			if lead.is_empty():
				u.hit(o, e, 1.0, {"src": "合围"})
			else:
				_cult_hit(u, lead, o, e, {"src": "合围"})
		o.screen_shake(1.0)
	if not a.cleared and float(a.t) >= land + 0.25:
		a.cleared = true
		for mt in a.mates:
			mt.m.syn_mv = {}   # 编队跟随把队友拉回队形
	return a.lead_done and a.cleared and float(a.t) >= land + 0.3


## 连携终结技补满：按队长动作里已打的份额补到 1
static func _cult_hit(u, lead: Dictionary, o, e: Dictionary, opt: Dictionary) -> void:
	if lead.has("share"):
		_ex_hit(u, lead, o, e, 1.0, opt)
	else:
		_hit(u, lead, o, e, 1.0, opt)
