## 干员积木 · seg_lappland（docs/202 成长节点：拉普兰德 追猎 / 日晷·反斩 / 断喝·传染 / 日晷·回敬）
## 接入方式：四个瞬时积木 verb.ll_*（登记在 seg_hoshiguma.EXT_BLOCKS、data_operator.EXEC_SEG → _ext_exec → ll_exec）+ shape.wave 的几个可选参数
## （aim: low_hp、homing、ll、sword、big；seg_skadi 的 hw_wave_start / _hw_waves 里各一行钩子）。没带这些参数的剑气 / 干员一律不走本文件。
## 确定性：玩法不取随机数（目标、排序全按生命比例 / 距离 / id）；画面只用 g.vrng。
extends "res://scripts/characters/blocks/seg_skalter.gd"

const LL_COL := Color(0.72, 0.6, 1.0)


## data_operator._ext_exec 转来（EXEC_SEG 登记在第 0 段）：本文件的四个瞬时积木
static func ll_exec(o, b: Dictionary) -> void:
	match str(b.get("_tag", "")):
		"verb.ll_dial_arm":
			_ll_dial_arm(o)
		"verb.ll_dial_swing":
			_ll_dial_swing(o, b)
		"verb.ll_riposte":
			_ll_riposte(o, b)
		"verb.ll_seal_spread":
			_ll_seal_spread(o, b)


# ---------------------------------------------------------------- 节点 2 追猎：目标 = 生命比例最低；剑气轻微追踪

## origin 缺省 = 本干员；r 内生命比例最低的敌人（同比例按 id）。没有返回 {}
static func ll_pick_low(o, r: float, origin := Vector2.INF) -> Dictionary:
	var from: Vector2 = o.pos if origin == Vector2.INF else origin
	var best: Dictionary = {}
	var bf := 9.0
	for e in o.nearest_enemies(24, r, from):
		if e.dead or int(e.get("id", 0)) < 0:
			continue
		var f: float = float(e.hp) / maxf(1.0, float(e.maxhp))
		if f < bf - 0.000001 or (absf(f - bf) <= 0.000001 and int(e.id) < int(best.get("id", 0))):
			bf = f
			best = e
	return best


## hw_wave_start 刚放出一道带 ll 的剑气：追猎 → 记转向速度和目标；待命的反斩 → 变大剑气。tl = aim: low_hp 挑出的目标（没有 = {}）
static func ll_wave_post(o, w: Dictionary, b: Dictionary, tl: Dictionary) -> void:
	var h := hw_st(o)
	if b.has("homing") and not tl.is_empty():
		w["hm"] = float(b.homing)
		w["tg"] = tl
		o.fx({"kind": "ring", "pos": tl.pos, "r": float(tl.r) + 14.0, "r0": float(tl.r) + 30.0, "life": 0.4, "col": LL_COL, "floor": true, "w": 2.0, "alpha": 0.8})
	if b.get("big", false):
		w["big"] = true
	elif b.get("sword", false) and h.get("ll_dial", false):
		h["ll_dial"] = false
		var b2: Dictionary = (w.b as Dictionary).duplicate()
		b2.erase("max_hits")   # 穿透全部
		b2["proj_scale"] = float(b.get("proj_scale", 1.0)) * 1.6
		w["b"] = b2
		w["w"] = float(w.w) * o.base("dial_w_mult", 2.0)
		w["big"] = true
	w["ll"] = true


## 每帧（_hw_waves 里带 ll 的剑气）：追踪转向 + 画面
static func ll_wave_tick(o, w: Dictionary, dt: float) -> void:
	var g = o.g
	if w.has("hm"):
		var tg = w.get("tg", {})
		if not (tg is Dictionary) or tg.is_empty() or tg.get("dead", true):
			tg = ll_pick_low(o, 180.0, w.pos)
			w["tg"] = tg
		if not tg.is_empty():
			var d: float = angle_difference(w.dir.angle(), (tg.pos - w.pos).angle())
			var st: float = clampf(d, -float(w.hm) * dt, float(w.hm) * dt)
			if st != 0.0:
				w.dir = w.dir.rotated(st)
				if w.has("ez"):
					w.p0 = w.pos - w.dir * float(w.dist)   # 非线性路径：从当前位置接着沿新方向走
		o.fx({"kind": "mote", "pos": w.pos + Vector2(g.vrng.randf_range(-3, 3), -16.0 + g.vrng.randf_range(-3, 3)), "vel": Vector2.ZERO, "life": 0.3, "col": LL_COL, "sz": 1.8})
	if w.get("big", false):
		var nrm: Vector2 = w.dir.orthogonal()
		for sgn in [-1.0, 1.0]:
			o.fx({"kind": "mote", "pos": w.pos + nrm * sgn * float(w.w) * 0.5 + Vector2(0, -16), "vel": w.dir * 30.0, "life": 0.32, "col": LL_COL, "sz": 2.2})


# ---------------------------------------------------------------- 节点 4B 日晷·反斩

static func _ll_dial_arm(o) -> void:
	var h := hw_st(o)
	h["ll_dial"] = true
	o.fx({"kind": "ring", "pos": o.pos, "r": 46.0, "r0": 12.0, "life": 0.4, "col": LL_COL, "floor": true, "w": 3.0, "alpha": 0.9})
	o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -26), "r": 26.0, "life": 0.4, "col": LL_COL, "alpha": 0.5})
	o.float_text(o.pos + Vector2(0, -70), "反斩", LL_COL, 14)


## 每次横扫之后：反斩还待命（这一下没有剑气把它用掉）→ 额外掷出一道大剑气
static func _ll_dial_swing(o, b: Dictionary) -> void:
	var h := hw_st(o)
	if not h.get("ll_dial", false):
		return
	h["ll_dial"] = false
	o._exec_list(b.get("do", []))


# ---------------------------------------------------------------- 节点 5B 日晷·回敬

static func _ll_riposte(o, b: Dictionary) -> void:
	var g = o.g
	if o.pos == Vector2.INF:
		return
	var h := hw_st(o)
	if float(h.get("ll_rip_t", -9.0)) > g.t:
		return
	var r: float = float(b.get("r", 130.0))
	var ts: Array = o.nearest_enemies(1, r + 30.0, o.pos)
	if ts.is_empty():
		return
	h["ll_rip_t"] = g.t + float(b.get("cd", 0.8))
	var e: Dictionary = ts[0]
	var ang: float = (e.pos - o.pos).angle()
	o.face_to(ang)
	var half: float = deg_to_rad(float(b.get("half", 70.0)))
	var dmg: float = hw_basis(o, "atk") * float(b.get("mult", 1.5))
	var org: Vector2 = o.pos + Vector2(0, -10)
	var hits: Array = o.melee_hit(str(b.get("src", "回敬")), org, ang, half, r, dmg, float(b.get("kb", 0.0)), 0.0, ["follow_up", "area"])
	fx_play(o, b.get("slash_fx", []), org, r, hits, ang)
	o.fx({"kind": "glow", "pos": o.pos + Vector2(0, -26), "r": 22.0, "life": 0.3, "col": LL_COL, "alpha": 0.5})
	o.float_text(o.pos + Vector2(0, -70), "回敬", LL_COL, 14)
	o._sfx_op("atk")


# ---------------------------------------------------------------- 节点 5A 断喝·传染

static func _ll_seal_spread(o, b: Dictionary) -> void:
	var g = o.g
	var e: Dictionary = o.hw.get("kill_e", {}) if hw_on(o) else {}
	if e.is_empty() or float(e.get("seal_t", 0.0)) <= g.t or str(e.get("seal_by", "")) != str(o.id):
		return
	var r: float = float(b.get("r", 120.0))
	o.fx({"kind": "ring", "pos": e.pos, "r": r, "r0": r * 0.2, "life": 0.45, "col": LL_COL, "floor": true, "w": 3.0, "alpha": 0.85})
	o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -8), "r": 18.0, "life": 0.3, "col": LL_COL, "alpha": 0.5})
	var cand: Array = []
	for j in o.query_ids(e.pos, r + 40.0):
		var t: Dictionary = g.enemies[j]
		if t.dead or t.boss or t.chest or is_same(t, e) or t.pos.distance_to(e.pos) > r + float(t.r) * 0.5:
			continue
		cand.append(t)
	var sel: Array = o.cap_targets(cand, e.pos, int(b.get("n", 6)))
	var s := {"st": "seal", "dur": float(b.get("dur", 2.0)), "elite_mult": 0.5, "boss": false, "look": "cross"}
	for t in sel:
		apply_status(o, t, s, t.pos)
		o.fx({"kind": "line", "pos": e.pos + Vector2(0, -12), "to": t.pos + Vector2(0, -12), "life": 0.25, "col": LL_COL, "w": 1.5})
