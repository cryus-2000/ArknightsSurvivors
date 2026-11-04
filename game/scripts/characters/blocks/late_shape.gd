extends RefCounted
## 后期攻击形状随成长变化（docs/248，数值原型，开关 growth/late_shape，缺省 0 = 关，关时不做任何事、不读写随机数）。
## P1：每名干员按「档」拿形状加成。档 = 达到的门槛权重之和（balance.json shape_lv 段）：
##   精一 w_e1、精二 w_e2（精英化节点的强度跃升）；队伍等级 ≥ lv1 / lv2 各 w_lv1 / w_lv2。
## 加成按干员的形状流派（lane）分四条，参数同在 shape_lv 段，每档：
##   melee   近战扩域：范围 +melee_range；剑气 +melee_qi 道（伤害 = 普攻 × qi_mult，穿 qi_hits 名）
##   multi   多弹火力：额外弹 +multi_shots 发（每发 = 普攻 × multi_eps，射向另一名敌人）；范围 +multi_range；能穿透的普攻子弹每档 +multi_pierce（取整）
##   summon  召唤驻场：范围（召唤物攻击覆盖）+summon_range；追击与召唤物伤害 +summon_dmg
##   control 控场引爆：范围 +control_range；控制时长 +control_dur
## 流派取干员 lanes 里第一个属于这四条的；都不属于的（治疗 / 弱点）查例外表 shape_lv/x_lane（{干员: 流派}），表里写 "none" = 不给。
## P2：升级卡「扩散」（命中溅射，op_splash）与「连锁」（命中弹射，op_chain）在这里结算，见 on_hit。
## 实现：属性来源 "lshape:<id>"（作用域 op:<id>）每帧比对档位，变了才重挂；额外弹 / 剑气复用可见成长（vis_growth.gd）的弹体与剑气。

const Bal = preload("res://scripts/core/balance.gd")
const LANES := ["melee", "multi", "summon", "control"]
const VisNodesL = preload("res://scripts/characters/blocks/vis_nodes.gd")   # docs/249：节点弹数走 op_summary
const _FXR = preload("res://scripts/render/fx_recipe.gd")   # 转平面（docs/255）：流明的连锁弹射改画流明折光细光，只画


static func on(g) -> bool:
	return g != null and Bal.v("growth/late_shape", 0.0) > 0.0


static func kn(k: String, d: float) -> float:
	return Bal.v("shape_lv/" + k, d)


## 形状流派（四条之一，或 ""）
static func lane(o) -> String:
	var x = Bal.sec("shape_lv").get("x_lane", {})
	if x is Dictionary and x.has(str(o.id)):
		var l := str(x[str(o.id)])
		return "" if l == "none" else l
	if o.has_method("lanes"):
		for l in o.lanes():
			if str(l) in LANES:
				return str(l)
	return ""


## 档位（门槛权重之和）
static func tier(o) -> float:
	var t := 0.0
	var el: int = int(o.get("elite")) if o.get("elite") != null else 0
	if el >= 1:
		t += kn("w_e1", 1.0)
	if el >= 2:
		t += kn("w_e2", 1.0)
	var lv: int = int(o.g.level)
	if lv >= int(kn("lv1", 16.0)):
		t += kn("w_lv1", 0.5)
	if lv >= int(kn("lv2", 22.0)):
		t += kn("w_lv2", 0.5)
	return t


## 每帧（data_operator.update）：档位变了才重挂属性
static func tick(o) -> void:
	var t := tier(o)
	if o.has_meta("ls_t") and is_equal_approx(float(o.get_meta("ls_t")), t):
		return
	o.set_meta("ls_t", t)
	var g = o.g
	var src := "lshape:" + str(o.id)
	var sc := "op:" + str(o.id)
	g.stats.remove_source(src)
	if t > 0.0:
		match lane(o):
			"melee":
				g.stats.add(&"op_range", "add", kn("melee_range", 0.12) * t, src, sc)
			"multi":
				g.stats.add(&"op_range", "add", kn("multi_range", 0.06) * t, src, sc)
				var pc := int(floor(kn("multi_pierce", 0.8) * t + 1e-6))
				if pc > 0 and o.get("pierce_atk") == true:
					g.stats.add(&"op_pierce", "flat", float(pc), src, sc)
			"summon":
				g.stats.add(&"op_range", "add", kn("summon_range", 0.12) * t, src, sc)
				g.stats.add(&"followup_dmg", "add", kn("summon_dmg", 0.15) * t, src, sc)
			"control":
				g.stats.add(&"op_range", "add", kn("control_range", 0.15) * t, src, sc)
				g.stats.add(&"control_dur", "add", kn("control_dur", 0.08) * t, src, sc)
	g.sync_stats()


## 精英化卡面追加的一行（「；形状：……」）：这一档（w_e1 / w_e2）带来的加成
static func elite_text(o, level: int) -> String:
	var w: float = kn("w_e2", 1.0) if level >= 2 else kn("w_e1", 0.5)
	if w <= 0.0:
		return ""
	var parts: Array = []
	match lane(o):
		"melee":
			parts.append("攻击范围 +%d%%" % int(round(kn("melee_range", 0.12) * w * 100.0)))
			parts.append("每 %s 次普攻多放 1 道剑气（%d%% 普攻伤害）" % [_n(1.0 / maxf(0.01, kn("melee_qi", 0.6) * w)), int(round(kn("qi_mult", 0.4) * 100.0))])
		"multi":
			parts.append("每 %s 次普攻多射 1 发（%d%% 普攻伤害，射向另一名敌人）" % [_n(1.0 / maxf(0.01, kn("multi_shots", 0.6) * w)), int(round(kn("multi_eps", 0.4) * 100.0))])
			parts.append("攻击范围 +%d%%" % int(round(kn("multi_range", 0.06) * w * 100.0)))
		"summon":
			parts.append("攻击范围 +%d%%" % int(round(kn("summon_range", 0.12) * w * 100.0)))
			parts.append("追击与召唤物伤害 +%d%%" % int(round(kn("summon_dmg", 0.15) * w * 100.0)))
		"control":
			parts.append("攻击范围 +%d%%" % int(round(kn("control_range", 0.15) * w * 100.0)))
			parts.append("控制时长 +%d%%" % int(round(kn("control_dur", 0.08) * w * 100.0)))
		_:
			return ""
	return "\n形状：" + "，".join(parts)


static func _n(v: float) -> String:
	var t := "%.1f" % v
	while t.ends_with("0"):
		t = t.substr(0, t.length() - 1)
	return t.trim_suffix(".")


## 本干员这一次出手的额外弹 / 剑气（并进可见成长汇总 s 的副本；relic_shots / relic_qi = 藏品那部分对本干员是否生效）
static func op_summary(o, s: Dictionary, relic_shots: bool, relic_qi: bool, ranged_ok: bool, melee_ok: bool) -> Dictionary:
	var r := {"e_scatter": 0.0, "e_burst": 0.0, "e_shots": 0.0, "t_shots": 1.0, "e_qi": 0.0, "qi_mult": 0.0, "qi_hits": 1}
	if not s.is_empty():
		if relic_shots:
			for k in ["e_scatter", "e_burst", "e_shots", "t_shots"]:
				r[k] = float(s[k])
		if relic_qi:
			r.e_qi = float(s.e_qi)
			r.qi_mult = float(s.qi_mult)
			r.qi_hits = int(s.qi_hits)
	var t := tier(o) if on(o.g) else 0.0   # 只开 growth/visible_nodes 时没有档位部分
	var l := lane(o)
	var vn: float = VisNodesL.extra_shots(o) if VisNodesL.on(o.g) and ranged_ok else 0.0   # 看得见的节点（docs/249）：普通节点的弹数并进同一个累计器
	if vn > 0.0:
		r.e_scatter += vn
		r.e_shots += vn
		r.t_shots += VisNodesL.kn("shot_mult", 0.5) * vn
	if t > 0.0 and l == "multi" and ranged_ok:
		var n: float = kn("multi_shots", 0.6) * t
		r.e_scatter += n
		r.e_shots += n
		r.t_shots += kn("multi_eps", 0.4) * n
	if t > 0.0 and l == "melee" and melee_ok:
		r.e_qi += kn("melee_qi", 0.6) * t
		r.qi_mult = maxf(float(r.qi_mult), kn("qi_mult", 0.4))
		r.qi_hits = maxi(int(r.qi_hits), int(kn("qi_hits", 3.0)))
	return r


# ---------------------------------------------------------------- P2：扩散 / 连锁（升级卡）

## 吃「扩散」：形状流派是近战 / 召唤 / 控场；吃「连锁」：多弹
static func splash_eater(o) -> bool:
	return lane(o) in ["melee", "summon", "control"]


static func chain_eater(o) -> bool:
	return lane(o) == "multi"


## data_operator.deal_damage 之后：本干员普攻（origin core，非成长弹）命中时溅射 / 弹射。
## 同一干员同一帧只触发一次（范围普攻一下打中十几名时不按人头翻倍）；扩散 / 连锁自身的伤害不再触发
static func on_hit(o, e: Dictionary, dmg: float, h) -> void:
	if not (h is Dictionary) or dmg <= 0.0 or str(h.get("origin", "")) != "core" or str(h.get("emitter", "")) != "operator":
		return
	var tags: Array = h.get("tags", [])
	if "growth" in tags or "lshape" in tags:
		return
	var g = o.g
	var sp: float = o.stat(&"op_splash") if splash_eater(o) else 0.0
	var ch: int = int(round(o.stat(&"op_chain"))) if chain_eater(o) else 0
	if sp <= 0.0 and ch <= 0:
		return
	if is_equal_approx(float(o.get_meta("ls_hf", -1.0)), float(g.t)):
		return
	o.set_meta("ls_hf", float(g.t))
	if sp > 0.0:
		var r: float = kn("splash_r", 60.0)
		for j in o.query_ids(e.pos, r + 20.0):
			var x: Dictionary = g.enemies[j]
			if x.dead or x.id == e.id or x.pos.distance_to(e.pos) > r + float(x.r):
				continue
			o.log_hit(_src(o, "扩散"), ["lshape"])
			o.deal_damage(x, dmg * sp * (kn("boss_k", 1.0) if x.boss else 1.0))
		o.fx({"kind": "ring", "pos": e.pos, "r": r, "r0": 8.0, "life": 0.22, "col": o.col(), "floor": true, "w": 2.0})
	if ch > 0:
		var cur: Dictionary = e
		var done := {e.id: true}
		var d: float = dmg * kn("chain_mult", 0.5)
		var cr: float = kn("chain_r", 170.0)
		for _k in ch:
			var nx = null
			var best := INF
			for j in o.query_ids(cur.pos, cr):
				var x: Dictionary = g.enemies[j]
				if x.dead or done.has(x.id):
					continue
				var dd: float = x.pos.distance_squared_to(cur.pos)
				if dd < best:
					best = dd
					nx = x
			if nx == null:
				break
			done[nx.id] = true
			o.fx({"kind": "line", "pos": cur.pos + Vector2(0, -16), "to": nx.pos + Vector2(0, -16), "life": 0.14, "col": o.col().lerp(Color.WHITE, 0.4), "w": 2.0})
			if str(o.id) == "lumen":
				_FXR.ev(o, "lm_chain", {"a": cur.pos + Vector2(0, -16), "b": nx.pos + Vector2(0, -16), "gy": float(nx.pos.y) + 1.0, "e": nx})   # 转平面（docs/255）：只画
			o.log_hit(_src(o, "连锁"), ["lshape"])
			o.deal_damage(nx, d * (kn("boss_k", 1.0) if nx.boss else 1.0))
			cur = nx


static func _src(o, key: String) -> String:
	## 同 vis_growth._src：来源名就是卡名（作战记录按 op 归到该干员），每次结算前写成当前干员
	var rng: String = o.range_cls() if o.has_method("range_cls") else "近战"
	o.g.hit_src[key] = {"emitter": "operator", "origin": "core", "range": rng, "kind": "物理" if rng == "近战" else "法术", "tags": ["growth", "lshape"], "class": o.cls, "op": o.id}
	return key
