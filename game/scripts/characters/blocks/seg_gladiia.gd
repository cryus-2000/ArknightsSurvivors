## 干员积木 · seg_gladiia（docs/202 成长节点：歌蕾蒂娅 倒钩 / 回收斩 / 怒海 / 深海的庇护·反震 / 怒海·暗涌）
## 接入方式：blocks.attack.hook_nodes（每项 node = 对应成长节点 id，o.taken 里有才生效；参数全部 $ 引 base）+ 钩索（seg_ulpianus 的 shape.hookshot）
## 里带 gl 标记时的三处钩子（拖拽中 / 到位 / 每帧），以及 verb.shield 的 pop（ob_summon，护盾破裂或到期时执行的积木列表，5A 反震）。
## 新实体：沉没的锁链 o.hw.glc（至多 chain_cap 条，到期 / 暗涌喷完即清）。没带 hook_nodes 的干员（乌尔比安）一律不走本文件。
## 控制统一走 o.add_cc_growth（同一敌人 3 秒内第二次受控时长减半，docs/202）；减速（lite_slow）不递减。
## 确定性：不取随机数；画面只用 g.vrng。
extends "res://scripts/characters/blocks/seg_lappland.gd"

const GL_COL := Color(0.6, 0.55, 1.0)
const GL_BLUE := Color(0.35, 0.65, 0.95)


## hook_nodes[key] 且其 node 已选下 → 返回那一项，否则 {}
static func _gl_on(o, key: String) -> Dictionary:
	var hn = o.B.get("attack", {}).get("hook_nodes", null)
	if not (hn is Dictionary) or not hn.has(key):
		return {}
	var n: Dictionary = hn[key]
	return n if o.taken.has(str(n.get("node", ""))) else {}


# ---------------------------------------------------------------- 倒钩（节点 1）：拖拽路径迸火星

static func gl_drag_tick(o, hk: Dictionary, dg: Dictionary, dt: float) -> void:
	if _gl_on(o, "barb").is_empty():
		return
	dg["spk"] = float(dg.get("spk", 0.0)) - dt
	if float(dg.spk) > 0.0:
		return
	dg["spk"] = 0.045
	var g = o.g
	var e: Dictionary = dg.e
	for k in 2:
		o.fx({"kind": "spark", "pos": e.pos + Vector2(g.vrng.randf_range(-6, 6), -float(e.r) * 0.4 + g.vrng.randf_range(-4, 4)),
			"vel": Vector2.from_angle(g.vrng.randf() * TAU) * g.vrng.randf_range(30.0, 90.0), "life": 0.35, "col": GL_COL, "sz": 3.0, "drag": 2.0})


# ---------------------------------------------------------------- 到位（hook 拖拽结束的同一帧）：倒钩结算 → 回收斩 → 锁链沉底

static func gl_arrive(o, hk: Dictionary) -> void:
	var g = o.g
	var ve: float = o.vs_elite()
	var barb := _gl_on(o, "barb")
	if not barb.is_empty():
		var per: float = maxf(1.0, float(barb.get("per", 50.0)))
		for dg in hk.drag:
			var e: Dictionary = dg.e
			if e.dead:
				continue
			var layers: int = mini(int(((dg.from as Vector2).distance_to(dg.spot)) / per), int(barb.get("max", 5)))
			if layers <= 0:
				continue
			o.log_hit(str(barb.get("src", "倒钩")), ["follow_up", "control"])
			o.deal_damage(e, float(hk.dmg) * float(barb.get("pct", 0.08)) * layers * (ve if e.elite or e.boss else 1.0))
			if not e.dead:
				o.float_text(e.pos + Vector2(0, -float(e.r) * 2.0 - 8.0), "倒钩 ×%d" % layers, GL_COL, 12)
	var sl := _gl_on(o, "slash")
	if not sl.is_empty() and o.pos != Vector2.INF:
		var ang: float = (hk.front - o.pos).angle()
		var r: float = float(sl.get("r", 160.0))
		var org: Vector2 = o.pos + Vector2(0, -10)
		var hits: Array = o.melee_hit(str(sl.get("src", "回收斩")), org, ang, deg_to_rad(float(sl.get("half", 65.0))), r, float(hk.dmg) * float(sl.get("mult", 1.0)),
			float(sl.get("kb", 0.0)), 0.0, ["follow_up", "area"])
		fx_play(o, sl.get("fx", []), org, r, hits, ang)
		o.screen_shake(0.06)
	var ch := _gl_on(o, "chain")
	if not ch.is_empty() and o.pos != Vector2.INF:
		var alive := false
		for dg in hk.drag:
			alive = alive or not dg.e.dead
		if alive:
			var h := hw_st(o)
			if not h.has("glc"):
				h["glc"] = []
			var lst: Array = h.glc
			if lst.size() >= int(ch.get("cap", 3)):
				lst.pop_front()
			lst.append({"a": o.pos, "c": hk.to, "t": 0.0, "life": float(ch.get("dur", 2.0)), "acc": 0.0, "dmg": float(hk.dmg) * float(ch.get("mult", 0.2)),
				"src": str(ch.get("src", "怒海")), "w": float(ch.get("w", 28.0)), "slow": float(ch.get("slow", 0.4)), "every": float(ch.get("every", 0.5)),
				"phase": "live", "gt": 0.0, "gi": 0})


# ---------------------------------------------------------------- 沉没的锁链（怒海）/ 暗涌（怒海·暗涌）

static func gl_tick(o, dt: float) -> void:
	var g = o.g
	var h: Dictionary = o.hw
	var lst: Array = h.glc
	if lst.is_empty():
		return
	for ch in lst:
		var a: Vector2 = ch.a
		var c: Vector2 = ch.c
		var L: float = maxf(1.0, a.distance_to(c))
		var d: Vector2 = (c - a) / L
		if str(ch.phase) == "live":
			ch.t = float(ch.t) + dt
			ch.acc = float(ch.acc) + dt
			var pay: bool = float(ch.acc) >= float(ch.every)
			if pay:
				ch.acc = float(ch.acc) - float(ch.every)
			for j in o.query_ids((a + c) * 0.5, L * 0.5 + float(ch.w) + 30.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or not line_contains(a, d, L, float(ch.w), e.pos, float(e.r)):
					continue
				g.enemies_sys.lite_slow(e, float(ch.slow), 0.3)
				if pay:
					o.log_hit(str(ch.src), ["dot", "control"])
					o.deal_damage(e, float(ch.dmg) * (o.vs_elite() if e.elite or e.boss else 1.0))
			if float(ch.t) >= float(ch.life):
				var gz := _gl_on(o, "geyser")
				if gz.is_empty():
					ch.phase = "done"
				else:
					ch.phase = "burst"
					ch["gz"] = gz
		elif str(ch.phase) == "burst":
			ch.gt = float(ch.gt) + dt
			var gz2: Dictionary = ch.gz
			var gap: float = maxf(8.0, float(gz2.get("gap", 40.0)))
			while float(ch.gt) >= 0.05 * float(int(ch.gi)) and (int(ch.gi) + 1) * gap <= L + 1.0:
				ch.gi = int(ch.gi) + 1
				_gl_geyser(o, gz2, a + d * (float(ch.gi) * gap))
			if (int(ch.gi) + 1) * gap > L + 1.0:
				ch.phase = "done"
	h["glc"] = lst.filter(func(q): return str(q.phase) != "done")


static func _gl_geyser(o, gz: Dictionary, p: Vector2) -> void:
	var g = o.g
	var r: float = float(gz.get("r", 30.0))
	fx_play(o, gz.get("fx", []), p, r)
	o.fx({"kind": "line", "pos": p, "to": p + Vector2(0, -44.0), "life": 0.35, "col": GL_BLUE, "w": 5.0})
	o.fx({"kind": "ring", "pos": p, "r": r + 8.0, "r0": 6.0, "life": 0.3, "col": GL_BLUE, "floor": true, "w": 2.0, "alpha": 0.8})
	for j in o.query_ids(p, r + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.pos.distance_to(p) > r + float(e.r):
			continue
		_gl_lift(o, e, float(gz.get("air", 0.5)))


## 浮空：同 seg_angelina.lift（精英减半、Boss / 部件 / 箱子不动），但控制时长走 add_cc_growth（3 秒内第二次减半）
static func _gl_lift(o, e: Dictionary, dur: float) -> void:
	if not _movable(e) or dur <= 0.0:
		return
	if e.elite:
		dur *= 0.5
	for a in o.air_list:
		if is_same(a.e, e):
			a.dur = maxf(a.dur, a.t + dur)
			o.add_cc_growth(e, a.dur - a.t, -INF, "airborne")
			return
	o.air_list.append({"e": e, "t": 0.0, "dur": dur, "h": 26.0})
	o.add_cc_growth(e, dur, -INF, "airborne")


static func gl_draw_floor(o) -> void:
	var cv = o.cv
	var g = o.g
	for ch in o.hw.glc:
		var al: float = 0.9
		if str(ch.phase) == "live":
			al = clampf((float(ch.life) - float(ch.t)) / 0.4, 0.0, 1.0) * 0.5 + 0.4
		else:
			al = 0.4
		var a: Vector2 = (ch.a as Vector2) + Vector2(0, 2)
		var c: Vector2 = (ch.c as Vector2) + Vector2(0, 2)
		cv.draw_line(a, c, Color(GL_BLUE.r, GL_BLUE.g, GL_BLUE.b, 0.16 * al), float(ch.w))
		_hw_draw_chain(o, a, c, al, true)
		cv.draw_circle(c, 3.5, Color(0.58, 0.65, 0.68, 0.9 * al))
