extends RefCounted
## 卡片的「作用对象」：升级 / 藏品 / 商品会影响当前编队里的哪些干员（选卡与商店卡片底部的干员标签，docs/37）。
## 按效果数据（data/relic_effects.json、博士被动、干员深度卡）和干员的伤害来源（data/characters/<id>.json 的 hit_sources）推算；
## 只读，不改游戏状态。2026-09-26 用户要求：选升级时让玩家知道选项影响哪个角色（追击类 → 水月），按当前编队算。
##
## of_choice(g, o) 返回 {ops: {干员 id: 好/坏}, all, leader, global, miss}
##   ops     受益的干员；值 = 该干员只有坏处（诅咒 / 代价）时为 true
##   all     全队干员（全伤害、攻速、技力……）；leader 主控干员（唯一受击体：生命、减伤、闪避、回复、移速、拾取）
##           两者的值为 null（不涉及）/ false（有好处）/ true（只有坏处）
##   global  与干员无关（源石锭、灯火、商店、编队规模……）
##   miss    有职业 / 特征条件、但编队里没人满足时的说明（「编队无近卫」）
## chips(g, o) 把结果排成标签：[[文字, 颜色, 只有坏处]…]；只和干员无关的卡返回空数组（不画标签）

const UI = preload("res://scripts/ui.gd")
const Character = preload("res://scripts/characters/character.gd")
const Combat = preload("res://scripts/run/combat.gd")

## 只作用于主控干员的属性（唯一受击体）；敌人伤害 / 攻速也只落在主控身上
const LEADER_STATS := ["max_hp", "regen", "regen_pct", "armor", "dmg_taken", "dodge", "dodge_phys", "dodge_arts", "arts_res", "heal_mult",
	"corrode_taken", "nerve_taken", "shield_max", "shield_interval", "move_speed", "pickup", "enemy_dmg", "enemy_atk_speed"]
## 与干员无关的属性（资源 / 商店 / 灯火）
const GLOBAL_STATS := ["shop_price", "light_decay", "light_loss", "oil_gain", "xp_gain"]
## 越小越好的属性（判断「只有坏处」用）
const LOWER_BETTER := ["dmg_taken", "corrode_taken", "nerve_taken", "shield_interval", "enemy_dmg", "enemy_atk_speed", "enemy_hp", "enemy_speed",
	"shop_price", "light_decay", "light_loss"]
## 按伤害特征生效的属性 → 特征（见 traits）
const TRAIT_STATS := {"melee_dmg": "近战", "ranged_dmg": "远程", "physical_dmg": "物理", "arts_dmg": "法术", "followup_dmg": "追击", "control_dur": "控制"}
const LEADER_RULES := ["shield_burst", "shield_heal", "king_cake", "revive_once"]
const GLOBAL_RULES := ["four_choices", "rare_weight", "deep_sea", "tree_light", "resolve_elite"]
const LEADER_GAINS := ["heal", "shield_fill"]


## 干员的伤害特征 {近战, 远程, 物理, 法术, 追击, 单体, 控制}：常驻来源（core / talent）一直算；
## 技能与分支来源（skill / route）本局打出过伤害才算——没学的分支、还没放过的技能、废弃的旧来源都不算。
## live = false（招募卡：干员还不在队里）时只看常驻来源。
## 控制例外：看整套技能里有没有标 control / stun 的来源（晕眩不一定走带标签的来源，如水月 S3 的伞击晕眩）
static func traits(g, def: Dictionary, live := true) -> Dictionary:
	var t := {}
	var hs: Dictionary = def.get("hit_sources", {})
	for k in hs:
		var s: Dictionary = hs[k]
		var tags: Array = s.get("tags", [])
		if tags.has("control") or tags.has("stun"):
			t["控制"] = true
		if not (s.get("origin", "") in ["core", "talent"] or (live and float(g.dmg_out.get(k, 0.0)) > 0.0)):
			continue
		t[s.get("range", "近战")] = true
		if s.get("kind", "") in ["物理", "法术"]:
			t[s.kind] = true
		for tg in tags:
			if tg in Combat.FOLLOWUP_TAGS:
				t["追击"] = true
		if not tags.has("area"):
			t["单体"] = true
	return t


static func of_choice(g, o: Dictionary) -> Dictionary:
	var res := {"ops": {}, "all": null, "leader": null, "global": false, "miss": ""}
	match o.get("kind", ""):
		"relic":
			var r: Dictionary = g.rfx.db.get_relic(o.id)
			for ef in r.get("effects", []):
				_effect(g, res, ef)
		"prog":
			_mark(res, "op:" + str(o.op), false)
		"growth":
			var cat: String = g.doctor.PASSIVES.get(o.id, {}).get("cat", "")
			if o.has("op"):
				_mark(res, "op:" + str(o.op), false)
			elif cat == "doctor":
				_mark(res, "global" if o.id == "wick" else "leader", false)
			else:
				_mark(res, "all", false)
		"weapon":
			_mark(res, "leader", false)   # 医疗无人机：治疗主控
		"filler", "heal", "oil":
			var fid: String = o.get("id", o.kind)
			_mark(res, {"heal": "leader", "atk": "all"}.get(fid, "global"), false)
	return res


## 一条藏品效果落到哪些对象上
static func _effect(g, res: Dictionary, ef: Dictionary) -> void:
	var a: Dictionary = ef.get("args", {})
	match ef.get("type", "stat"):
		"stat":
			var bad := _is_bad(str(ef.stat), str(ef.get("op", "add")), float(ef.get("value", 0.0)))
			var scope: String = ef.get("scope", "")
			if scope.begins_with("class:"):
				_by_class(g, res, [scope.substr(6)], bad)
			elif scope.begins_with("range:"):
				_by_range(g, res, scope.substr(6), bad)
			else:
				_by_stat(g, res, str(ef.stat), bad)
		"trigger":
			var cond: Dictionary = ef.get("if", {})
			if a.has("class"):
				_by_class(g, res, [a["class"]], false)
			elif cond.has("tags_any"):
				_by_trait(g, res, "追击", false)
			elif a.has("stat"):
				_by_stat(g, res, str(a.stat), _is_bad(str(a.stat), str(a.get("op", "add")), float(a.get("value", 0.0))))
			elif ef.get("event", "") == "Healed":
				_mark(res, "leader", false)   # 食腐者手杖：主控的溢出回复
			elif cond.has("hit_count_max"):
				_by_trait(g, res, "单体", false)   # 荣耀绶带：不带范围效果的单体攻击
			else:
				_mark(res, "all", false)
		"rule":
			match str(ef.rule):
				"squad_scale":
					_squad_scale(g, res, a)
				"home_zone":
					_mark(res, "leader", false)
					_mark(res, "all", false)
				"bone_blood":
					_mark(res, "all", false)
					_mark(res, "leader", true)
				var rn:
					if rn in LEADER_RULES:
						_mark(res, "leader", false)
					elif rn in GLOBAL_RULES:
						_mark(res, "global", false)
					else:
						_mark(res, "all", false)   # 攻速 / 全伤害 / 技力 / 全体弱点 / 最终 Boss 增伤
		"on_gain":
			var what: String = str(ef.get("do", ""))
			if what == "advance_class":
				var cls: String = str(a.get("class", ""))
				var tgt = _advance_target(g, cls)
				if tgt != null:
					_mark(res, "op:" + str(tgt.id), false)
				else:
					_miss(res, ("%s无可推进" if _has_class(g, cls) else "编队无%s") % cls + " → 成长三选一")
			elif what == "contract":
				_mark(res, "random", false)
			elif what == "silver_seal":
				_mark(res, "all" if g.squad.is_full() else "recruit", false)
			elif what in LEADER_GAINS:
				_mark(res, "leader", false)
			else:
				_mark(res, "global", false)
		"status":
			_by_trait(g, res, "控制", false)   # 受控敌人每秒受法术伤害：要有人控场
		_:
			_mark(res, "global", false)


static func _is_bad(stat: String, op: String, v: float) -> bool:
	var up: bool = v > 1.0 if op == "mult" else v > 0.0
	return up if stat in LOWER_BETTER else not up


static func _by_stat(g, res: Dictionary, stat: String, bad: bool) -> void:
	if TRAIT_STATS.has(stat):
		_by_trait(g, res, TRAIT_STATS[stat], bad)
	elif stat == "heal_out":
		_by_class(g, res, ["医疗"], bad)
	elif stat in LEADER_STATS:
		_mark(res, "leader", bad)
	elif stat in GLOBAL_STATS:
		_mark(res, "global", bad)
	else:
		_mark(res, "all", bad)   # 全伤害、攻速、射程、技力、敌人生命、弱点加成……


static func _by_class(g, res: Dictionary, classes: Array, bad: bool) -> void:
	var n := 0
	for op in g.squad.ops:
		if op.cls in classes:
			_mark(res, "op:" + str(op.id), bad)
			n += 1
	if n == 0:
		_miss(res, "编队无" + " / ".join(PackedStringArray(classes)))


## 「近战干员 / 远程干员」按职业判定（character.range_cls，与 stat 作用域一致）
static func _by_range(g, res: Dictionary, rc: String, bad: bool) -> void:
	var n := 0
	for op in g.squad.ops:
		if op.range_cls() == rc:
			_mark(res, "op:" + str(op.id), bad)
			n += 1
	if n == 0:
		_miss(res, "编队无%s干员" % rc)


static func _by_trait(g, res: Dictionary, tr: String, bad: bool) -> void:
	var n := 0
	for op in g.squad.ops:
		if traits(g, op.def).get(tr, false):
			_mark(res, "op:" + str(op.id), bad)
			n += 1
	if n == 0:
		# 除控制外都按「本局打出过的伤害」判断，学了分支 / 放了技能以后可能就有了，所以说「暂无」
		_miss(res, {"追击": "编队暂无追击 / 召唤", "控制": "编队无控制", "单体": "编队暂无单体攻击"}.get(tr, "编队暂无%s伤害" % tr))


## 协议 / 老蒲扇 / 断杖-破解 / 支柱-援护（relic_fx.refresh_squad）：计数职业没人时不生效；给了 classes 只加到这些职业
static func _squad_scale(g, res: Dictionary, a: Dictionary) -> void:
	var cnt = a.get("count", [])
	if cnt is Array:
		if not g.squad.ops.any(func(op): return op.cls in cnt):
			_miss(res, "编队无" + " / ".join(PackedStringArray(cnt)))
			return
	var scs: Array = a.get("classes", [])
	if not scs.is_empty():
		_by_class(g, res, scs, false)
	else:
		_by_stat(g, res, str(a.get("stat", "dmg")), false)


static func _has_class(g, cls: String) -> bool:
	return g.squad.ops.any(func(op): return op.cls == cls)


## 典训的推进对象（同 relic_fx._advance_target）：该职业里下一个节点可用、进度最少的干员
static func _advance_target(g, cls: String):
	var best = null
	for op in g.squad.ops:
		if op.cls != cls:
			continue
		var n: Dictionary = op.next_node()
		if n.is_empty() or not op.node_available(n):
			continue
		if best == null or op.prog < best.prog:
			best = op
	return best


## 登记一个对象；同一对象既有好处又有坏处时按「有好处」算
static func _mark(res: Dictionary, key: String, bad: bool) -> void:
	if key.begins_with("op:"):
		var id := key.substr(3)
		res.ops[id] = bad and res.ops.get(id, true)
	elif key == "global":
		res.global = true
	else:
		var cur = res.get(key, null)
		res[key] = bad and (cur == null or cur == true)


static func _miss(res: Dictionary, s: String) -> void:
	if res.miss == "":
		res.miss = s


## 标签：点名的干员（干员色）→ 全队（青）→ 主控 · 名字 → 随机 / 新干员；只有坏处的对象用洋红并加「↓」。
## 缺条件说明（暗洋红）只在没人受益、或只剩坏处时出现，放最前。编队只有一人时全队 / 主控 / 干员都是同一个人，合成一个写名字的标签
static func chips(g, o: Dictionary) -> Array:
	if o.get("kind", "") == "recruit":
		return trait_chips(g, o.id)
	var res := of_choice(g, o)
	var out: Array = []
	var ld = g.squad.leader()
	if g.squad.size() <= 1:
		var marks: Array = res.ops.values()
		for k in ["all", "leader"]:
			if res[k] != null:
				marks.append(res[k])
		if ld != null and not marks.is_empty():
			out.append(_chip(g, ld.display_name(), ld.col(), not marks.has(false)))
	else:
		for op in g.squad.ops:
			if res.ops.has(op.id):
				out.append(_chip(g, op.display_name(), op.col(), res.ops[op.id]))
		if res.all != null:
			out.append(_chip(g, "全队", UI.CYAN, res.all))
		if res.leader != null and ld != null:
			out.append(_chip(g, "主控 · " + ld.display_name(), ld.col(), res.leader))
	if res.has("random"):
		out.append(_chip(g, "随机一名干员", UI.CYAN, false))
	if res.has("recruit"):
		out.append(_chip(g, "新干员 · 精英一", UI.GREEN, false))
	# 缺条件：没人受益、或者落到编队上的只有坏处时（如编队无近卫时的折戟-破釜沉舟），放在最前面说明原因
	if res.miss != "" and out.all(func(c): return c[2]):
		out.push_front([res.miss, Color(UI.RED.r, UI.RED.g, UI.RED.b, 0.7), true])
	return out


static func _chip(g, s: String, col: Color, bad: bool) -> Array:
	if bad:
		return [s + ("↓" if g.font.has_char(0x2193) else " -"), UI.RED, true]
	return [s, col, false]


## 招募卡：列出这名干员的常驻伤害特征（近战 / 远程、物理 / 法术、追击、控制），灰色，方便对照已有藏品。
## 近战远程两样都有时（如艾丽妮的远程追诉）只写职业对应的那个，免得标签太多
static func trait_chips(g, cid: String) -> Array:
	var def: Dictionary = Character.load_def(cid)
	var t := traits(g, def, false)
	if t.has("近战") and t.has("远程"):
		t.erase("远程" if def.get("class", "") in Character.MELEE_CLASSES else "近战")
	var out: Array = []
	for k in ["近战", "远程", "物理", "法术", "追击", "控制"]:
		if t.get(k, false):
			out.append([k, Color(0.62, 0.66, 0.7), false])
	return out
