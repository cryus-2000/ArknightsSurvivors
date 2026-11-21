## 干员积木 · seg_ling（docs/367 令：三种龙的召唤上限、天赋「随付笺咏醉屠苏」、精一「点灯」、S2「笑鸣瑟」、S3「宁作吾」合龙、节点「泼墨」）
## 11-18 改版（docs/367 §9 A 版「调随技能」）：当前调 o.gn.tune（qp / xy / xj，缺省 qp）由技能切换；龙每 spawn_cd 秒随时间化出一条（verb.lg_grow，满员时换掉最早一条异调龙）；
## 普攻按调换形（条件 lg_qp / lg_xy / lg_xj + verb.swap_attack）。画面事件见 lg_ev / _lg_fx（只画，特效会话接）。
## 接入方式：瞬时积木 verb.lg_*（登记在 seg_hoshiguma.EXT_BLOCKS、data_operator.EXEC_SEG → _ext_exec → lg_exec）。
## 召唤物本身全用 docs/61 §15 的 blocks.summons（chase / follow、decoy、anim）；本文件只管「谁算龙、满了顶掉谁、龙散去时给什么」。
## 天赋层数放 o.gn（docs/202 的扩展状态，光环 per: gn:drink 直接读）。没带 verb.lg_* 的干员一律不走本文件。
## 确定性：玩法不取随机数（目标按距离 / Boss 优先 / id）；画面只用 g.vrng。
extends "res://scripts/characters/blocks/seg_gladiia.gd"

## 计入「挑灯问梦」上限的龙（精二「落笔成龙」的墨龙 mo 不计、也不触发天赋）
const LG_KINDS := ["qp", "xy", "xy2", "xj", "xj2"]
const LG_INK := Color(0.42, 0.86, 0.95)     # 龙身青（PRTS 召唤物贴图主色）
const LG_LAMP := Color(1.0, 0.72, 0.36)     # 提灯暖橙（点灯标记、酒意）
const LG_TUNE0 := "xy"   # 开局的调（11-18 用户定：逍遥调，墨弹先手；清平调要放 S1 才进）


## data_operator._ext_exec 转来（EXEC_SEG 第 0 段）
static func lg_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.lg_summon":
			lg_summon(o, b, at)
		"verb.lg_drink":
			_lg_drink(o, b, at)
		"verb.lg_decay":
			_lg_decay(o)
		"verb.lg_lit":
			_lg_lit(o, b, at)
		"verb.lg_ming":
			_lg_ming(o, b)
		"verb.lg_merge":
			_lg_merge(o, b)
		"verb.lg_split":
			_lg_split(o, b, at)
		"verb.lg_ink":
			_lg_ink(o, b)
		"verb.lg_tune":
			_lg_tune(o, b)
		"verb.lg_grow":
			_lg_grow(o, b)
		"verb.lg_ev":
			_lg_fx(o, str(b.get("ev", "lg_ev")), {"p": at})
		"verb.lg_lure":
			_lg_lure(o, b)


## 清平诱敌（11-18 用户定：只在重进酒期间）：trait tick（cond skill_active:0）调；对每条 kind 召唤物按 decoy 规则引怪 + 挨贴身打（同 §15.1 decoy），平时常驻的清平只打不引怪、也不挨打
static func _lg_lure(o, b: Dictionary) -> void:
	var kind: String = str(b.get("kind", "qp"))
	var kd: Dictionary = sm_kind(o, kind).duplicate()
	kd["decoy_r"] = float(b.get("r", 180.0))
	kd["hurt_mult"] = float(b.get("hurt", 0.2))
	for s in lg_dragons(o, [kind]):
		_sm_decoy(o, s, kd)


## 画面事件（只画）：转平面接管令以后由 fx_pxplane 的令一节画；没接管时 fx_recipe 忽略。d 里统一带 tune（当前调）
static func _lg_fx(o, ev: String, d: Dictionary) -> void:
	d["tune"] = lg_tune_of(o)
	_FXR.ev(o, ev, d)


static func lg_tune_of(o) -> String:
	return str(o.gn.get("tune", LG_TUNE0))


## 龙种所属的调：qp → qp；xy / xy2 → xy；xj / xj2 → xj；墨龙按后缀
static func lg_group(kind: String) -> String:
	if kind.begins_with("mo_"):
		return kind.substr(3)
	if kind.begins_with("xy"):
		return "xy"
	if kind.begins_with("xj"):
		return "xj"
	return "qp"


## 当前调对应的龙种（逍遥游节点换 xy2）
static func lg_tune_kind(o, b: Dictionary) -> String:
	var t := lg_tune_of(o)
	if t == "xy" and b.has("alt_node") and o.taken.has(str(b.alt_node)):
		return str(b.get("alt_kind", "xy2"))
	return {"qp": "qp", "xy": "xy", "xj": "xj"}.get(t, "qp")


## 技能起手：切调（tune = qp / xy / xj）
static func _lg_tune(o, b: Dictionary) -> void:
	var t: String = str(b.get("tune", "qp"))
	var old := lg_tune_of(o)
	if o.skill_on(2) and t != "xj":
		return   # 宁作吾生效期间锁定弦惊调（S1 技力短，不锁的话会在 S3 中途把调切走）；结束后下一个技能再切
	o.gn["tune"] = t
	if t != old:
		_lg_fx(o, "lg_tune", {"from": old, "p": o.pos})


## 化龙节拍（trait 的 trig.tick 每 every 秒调，force = 技能起手立刻化一条）：计时满 cd0 / cd1 / cd2 秒 →
## 没满员：化出当前调的龙；满员：换掉最早一条异调龙（走 on_expire：天赋照算）；全是同调就停表等空位。S3（宁作吾）生效期间暂停
static func _lg_grow(o, b: Dictionary) -> void:
	if o.pos == Vector2.INF or o.skill_on(2):
		return
	var force: bool = b.get("force", false)
	if not force:
		var e: int = clampi(int(o.elite), 0, 2)
		var cd: float = float(b.get("cd%d" % e, b.get("cd0", 10.0)))
		o.gn["grow_t"] = minf(cd, float(o.gn.get("grow_t", cd)) + float(b.get("every", 0.5)))   # 开局即满：第一条马上出
		if float(o.gn.grow_t) < cd:
			return
	var kind := lg_tune_kind(o, b)
	var mine := lg_dragons(o)
	var cap := lg_cap(o, b)
	if mine.size() >= cap:
		var off = null
		for s in mine:
			if lg_group(str(s.kind)) != lg_tune_of(o) or (str(s.kind) != kind and lg_group(kind) == lg_group(str(s.kind)) and str(s.kind) != "xj2"):
				off = s
				break
		if off == null:
			return   # 全是同调：停表（grow_t 留在满值，空出位置的下一拍就补）
		_lg_fx(o, "lg_swap", {"p": off.pos, "from": str(off.kind), "kind": kind})
		_sm_end(o, off, "swap")
	o.gn["grow_t"] = 0.0
	sm_spawn(o, {"kind": kind, "n": 1, "at": "self", "spread": 34.0}, o.pos)
	var last = o.sm.list.back() if not o.sm.is_empty() and not o.sm.list.is_empty() else null
	if last != null:
		_lg_fx(o, "lg_spawn", {"p": last.pos, "kind": kind, "s": last})


## 本干员在场的龙（按召唤先后）
static func lg_dragons(o, kinds: Array = LG_KINDS) -> Array:
	if o.sm.is_empty():
		return []
	return o.sm.list.filter(func(q): return not q.gone and str(q.kind) in kinds)


## 「挑灯问梦」：龙合计上限 cap0 / cap1 / cap2（按精英阶段）
static func lg_cap(o, b: Dictionary) -> int:
	var e: int = clampi(int(o.elite), 0, 2)
	return maxi(1, int(b.get("cap%d" % e, b.get("cap0", 3))))


## 召唤一条龙：kind（节点 alt_node 已选下时换成 alt_kind）、at（self / leader / target / hit = 上一次普攻命中处）、life（覆盖种类）。
## 计入上限的龙满了先让最早的一条散去（走 on_expire：天赋照样给技力 / 酒意）
static func lg_summon(o, b: Dictionary, at: Vector2) -> void:
	var kind: String = str(b.get("kind", ""))
	if b.has("alt_node") and o.taken.has(str(b.alt_node)):
		kind = str(b.get("alt_kind", kind))
	if b.get("by_tune", false):   # 精二落笔成龙 / 连携：kind 是前缀，按当前调取（mo → mo_qp / mo_xy / mo_xj）
		kind = kind + "_" + lg_tune_of(o)
	if sm_kind(o, kind).is_empty():
		return
	var where: String = str(b.get("at", "self"))
	var p: Vector2 = at
	if where == "hit":
		p = o.last_hit_pos if o.last_hit_pos != Vector2.INF else at
		where = "target"
	if where == "target" and p == Vector2.INF:
		where = "self"
	if kind in LG_KINDS:
		var mine := lg_dragons(o)
		var cap := lg_cap(o, b)
		while mine.size() >= cap and not mine.is_empty():
			_sm_end(o, mine[0], "cap")
			mine.remove_at(0)
	var sb := {"kind": kind, "n": int(b.get("n", 1)), "at": where, "spread": float(b.get("spread", 28.0))}
	if b.has("life"):
		sb["life"] = b.life
	sm_spawn(o, sb, p)


# ---------------------------------------------------------------- 天赋「随付笺咏醉屠苏」：龙散去 → 技力 + 酒意

## 龙的 on_expire：精一起生效。其余没在生效的技能各 + sp 秒；酒意 +1（上限 cap，dur 秒不再得到就清空）。
## 节点「浮白」（burst_node）：酒意已满时这一条龙散去改为「醉卧」——原地炸开（r / mult），酒意清空
static func _lg_drink(o, b: Dictionary, at: Vector2) -> void:
	if int(o.elite) < 1:
		return
	var g = o.g
	var secs: float = float(b.get("sp", 2.0))
	var win: float = float(b.get("sp_win", 10.0))   # 防刷（docs/367 §9.0）：技力加成 sp_win 秒内至多 sp_max 次
	var ts: Array = o.gn.get("sp_ts", []).filter(func(x): return float(g.t) - float(x) < win)
	if ts.size() >= int(b.get("sp_max", 3)):
		secs = 0.0
	else:
		ts.append(float(g.t))
	o.gn["sp_ts"] = ts
	for i in 3:
		if o.skill_unlocked(i) and not o.perm[i] and not o.skill_on(i) and o.sp_need(i) > 0.0:
			o.sp[i] = minf(o.sp_need(i), float(o.sp[i]) + secs)
	var cap: int = int(b.get("cap", 5))
	var n: int = int(o.gn.get("drink", 0))
	var p: Vector2 = at if at != Vector2.INF else o.pos
	if n >= cap and b.has("burst_node") and o.taken.has(str(b.burst_node)):
		var r: float = float(b.get("burst_r", 120.0)) * o.stat(&"op_range")
		var dmg: float = o.base("atk", 0.0) * float(b.get("burst_mult", 1.5)) * float(o.loc.dmg) * o._dmg_bonus()
		o.area_hit(str(b.get("burst_src", "醉卧")), p, r, dmg, float(b.get("burst_kb", 80.0)), 0.0, ["follow_up", "area"], 0)
		o.fx({"kind": "ring", "pos": p, "r": r, "r0": r * 0.2, "life": 0.4, "col": LG_LAMP, "floor": true, "w": 3.0, "alpha": 0.8, "keep": true})
		o.fx({"kind": "glow", "pos": p + Vector2(0, -16), "r": r * 0.5, "life": 0.3, "col": LG_LAMP, "alpha": 0.5})
		o.gn["drink"] = 0
		o._restat()
		return
	o.gn["drink"] = mini(cap, n + 1)
	o.gn["drink_t"] = float(g.t) + float(b.get("dur", 15.0))
	if int(o.gn.drink) != n:
		o._restat()
	_lg_fx(o, "lg_drink", {"p": p, "n": int(o.gn.drink), "sp": secs})
	if o.pos != Vector2.INF:
		o.float_text(o.pos + Vector2(0, -62), "酒意 ×%d" % int(o.gn.drink), LG_LAMP, 12)
	if p != Vector2.INF and o.pos != Vector2.INF:   # 散去的龙化作一缕青光回到令身边（只画）
		o.fx({"kind": "line", "pos": p + Vector2(0, -14), "to": o.pos + Vector2(0, -30), "life": 0.3, "col": LG_INK, "w": 1.5})


## 酒意到时清空（talent 里 trig.tick 每 0.5 秒调）
static func _lg_decay(o) -> void:
	if int(o.gn.get("drink", 0)) > 0 and float(o.g.t) > float(o.gn.get("drink_t", 0.0)):
		o.gn["drink"] = 0
		o._restat()


# ---------------------------------------------------------------- 精一「点灯」：灯影落点最近的敌人挂灯，身边的龙改扑它

## 放在 point_aoe 的 then（at = 落点）
static func _lg_lit(o, b: Dictionary, at: Vector2) -> void:
	if at == Vector2.INF:
		return
	var near: Array = o.nearest_enemies(1, 48.0, at)
	if near.is_empty() or near[0].dead:
		return
	var e: Dictionary = near[0]
	var g = o.g
	e["lg_lit"] = float(g.t) + float(b.get("dur", 3.0))
	var r: float = float(b.get("r", 260.0))
	for s in lg_dragons(o, LG_KINDS + ["mo"]):
		var mv: Dictionary = sm_kind(o, str(s.kind)).get("move", _ED)
		if str(mv.get("mode", "")) != "chase" or s.pos.distance_to(e.pos) > r:
			continue
		s.tgt = e
		s.rt = 0.0
	_lg_fx(o, "lg_lit", {"e": e, "dur": float(b.get("dur", 3.0))})
	o.fx({"kind": "glow", "pos": e.pos + Vector2(0, -float(e.r) * 2.0 - 6.0), "r": 6.0, "life": 0.5, "col": LG_LAMP, "alpha": 0.8})


# ---------------------------------------------------------------- S2「笑鸣瑟」：令与每条逍遥各对 n 名敌人鸣瑟（法伤 + 束缚）

static func _lg_ming(o, b: Dictionary) -> void:
	var g = o.g
	var srcs: Array = []
	if o.pos != Vector2.INF:
		srcs.append([o.pos + Vector2(0, -30), str(b.get("src", "笑鸣瑟")), false])
	for s in lg_dragons(o, ["xy", "xy2"]):
		srcs.append([s.pos + Vector2(0, -14), str(b.get("src_summon", "逍遥·鸣瑟")), true])
	var n: int = int(b.get("n", 2))
	var rng: float = float(b.get("range", 320.0)) * o.stat(&"op_range")
	var dmg: float = o.base("atk", 0.0) * float(b.get("mult", 2.0)) * float(o.loc.dmg) * o._dmg_bonus() * o.skill_power()
	var bind: float = float(b.get("bind", 1.5))
	var chain: bool = b.has("chain_node") and o.taken.has(str(b.chain_node))
	var ve: float = o.vs_elite()
	var hit := {}
	for sr in srcs:
		var from: Vector2 = sr[0]
		var got := 0
		for e in o.nearest_enemies(n + 6, rng, from):
			if got >= n:
				break
			if e.dead or hit.has(int(e.id)):
				continue
			hit[int(e.id)] = true
			got += 1
			_lg_ming_hit(o, e, dmg, bind, ve, str(sr[1]), bool(sr[2]))
			_lg_fx(o, "lg_ming", {"from": from, "e": e, "bind": bind, "summon": bool(sr[2])})
			o.fx({"kind": "line", "pos": from, "to": e.pos + Vector2(0, -float(e.r)), "life": 0.25, "col": LG_INK, "w": 2.0})
			if chain and not e.dead:   # 节点「鸣瑟·连」：再跳向近旁一名没被鸣瑟打中的敌人
				for e2 in o.nearest_enemies(4, float(b.get("chain_r", 120.0)), e.pos):
					if e2.dead or hit.has(int(e2.id)):
						continue
					hit[int(e2.id)] = true
					_lg_ming_hit(o, e2, dmg * float(b.get("chain_mult", 0.6)), bind, ve, str(sr[1]), bool(sr[2]))
					o.fx({"kind": "line", "pos": e.pos + Vector2(0, -float(e.r)), "to": e2.pos + Vector2(0, -float(e2.r)), "life": 0.25, "col": LG_INK, "w": 1.5})
					break


static func _lg_ming_hit(o, e: Dictionary, dmg: float, bind: float, ve: float, src: String, summon: bool) -> void:
	var tags: Array = ["skill", "control"]
	if summon:
		tags.append("summon")
	o.log_hit(src, tags)
	o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
	if not e.dead and not e.boss and bind > 0.0:
		o.add_cc(e, bind * (0.5 if e.elite else 1.0))
	o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 8.0, "r0": float(e.r), "life": 0.35, "col": LG_INK, "floor": true, "w": 2.0, "alpha": 0.8})


# ---------------------------------------------------------------- S3「宁作吾」：弦惊吞下在场的龙，合成第二形态

## 在场的龙（含墨龙）全部被吸收（走 on_expire：天赋按条给技力 / 酒意）；吸收 ≥ 1 条 → 召唤 big（第二形态），否则 basic
static func _lg_merge(o, b: Dictionary) -> void:
	var g = o.g
	var c: Vector2 = o.lead_pos() if o.lead_pos() != Vector2.INF else o.pos
	var n := 0
	for s in lg_dragons(o, LG_KINDS + ["mo"]):
		if c != Vector2.INF:
			o.fx({"kind": "line", "pos": s.pos + Vector2(0, -14), "to": c + Vector2(0, -20), "life": 0.35, "col": LG_INK, "w": 2.0})
		_sm_end(o, s, "merge")
		n += 1
	o.gn["merged"] = n
	var kind: String = str(b.get("big", "xj2")) if n >= 1 else str(b.get("basic", "xj"))
	lg_summon(o, {"kind": kind, "at": "leader", "cap0": 9, "cap1": 9, "cap2": 9}, c)
	_lg_fx(o, "lg_merge", {"p": c, "n": n, "kind": kind})
	if n >= 1 and c != Vector2.INF:
		o.float_text(c + Vector2(0, -80), "弦惊 · 合", LG_INK, 14)


## 弦惊的 on_expire：S3 已结束（不是被新一轮吸收 / 顶掉）时，原地留下一条清平 life 秒
static func _lg_split(o, b: Dictionary, at: Vector2) -> void:
	if o.skill_on(2):
		return
	var sb := {"kind": str(b.get("kind", "qp")), "at": "target", "n": int(b.get("n", 1)), "cap0": 9, "cap1": 9, "cap2": 9}
	if float(b.get("life", 0.0)) > 0.0:
		sb["life"] = float(b.life)
	lg_summon(o, sb, at)
	_lg_fx(o, "lg_split", {"p": at, "n": int(b.get("n", 1))})


# ---------------------------------------------------------------- 节点「泼墨」：这一下灯影改为同时落在 n 名敌人身上

static func _lg_ink(o, b: Dictionary) -> void:
	if o.pos == Vector2.INF:
		return
	var rng: float = float(b.get("range", 300.0)) * o.stat(&"op_range")
	var r: float = float(b.get("r", 30.0)) * o.stat(&"op_range")
	var dmg: float = o.base("atk", 0.0) * float(b.get("mult", 0.7)) * float(o.loc.dmg) * o._dmg_bonus()
	var got := 0
	var first := true
	for e in o.nearest_enemies(int(b.get("n", 3)) + 4, rng, o.pos):
		if got >= int(b.get("n", 3)):
			break
		if e.dead:
			continue
		got += 1
		var hits: Array = o.area_hit(str(b.get("src", "泼墨")), e.pos, r, dmg, 0.0, 0.0, ["basic", "area"], 0)
		if first:
			o.last_hit_pos = e.pos
			first = false
		o.fx({"kind": "ring", "pos": e.pos, "r": r, "r0": 4.0, "life": 0.25, "col": LG_INK, "floor": true, "w": 2.0, "alpha": 0.8})
		o.fx({"kind": "line", "pos": o.pos + Vector2(0, -30), "to": e.pos + Vector2(0, -float(e.r)), "life": 0.18, "col": LG_INK, "w": 1.0})
