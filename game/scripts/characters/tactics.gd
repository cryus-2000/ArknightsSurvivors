## 战术姿态 v2（docs/209 §1，总开关 balance command/v2；各项另有子开关，0 = 改动前的行为）：
##   随行 = 护卫阵型（command/escort）：按职业站位，重装挡在队长和怪群之间、近战前侧两翼、远程后排、医疗 / 辅助贴身；
##   突击 = 职业分工（command/roles）：roam_target 的候选得分按职业修正；
##   部署 = 落位阻挡（command/block）：站到驻扎点的重装 / 近卫 / 先锋 / 特种挡住接触到的近战敌人；
##   代价（command/expose）：突击 / 部署中吃敌弹与预警招式；残血自动撤回（command/retreat_hp）；医疗给队友回血（command/heal_mates）。
## 只读写编队 / 干员 / 敌人状态，不抽随机数（同 seed 可复现）。状态字段在 squad.gd（escort_dir）与 character.gd（cmd_retreat / cmd_blk）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")

const ROLE := {"重装": "heavy", "近卫": "melee", "先锋": "melee", "特种": "melee", "狙击": "ranged", "术师": "ranged", "医疗": "support", "辅助": "support"}
const BLOCK_DEF := {"重装": 3, "近卫": 2, "先锋": 2, "特种": 1, "狙击": 1, "术师": 1, "医疗": 0, "辅助": 0}


static func on() -> bool:
	return Bal.v("command/v2", 1.0) > 0.0


static func sub(k: String) -> bool:
	return on() and Bal.v("command/" + k, 1.0) > 0.0


static func role(o) -> String:
	return str(ROLE.get(str(o.cls), "melee"))


# ================================================================ 随行：护卫阵型

## 威胁方向：队长 escort_r 内最近 12 只敌人的质心方向；按 escort_turn 弧度 / 秒平滑转过去。没有敌人时转向队长朝向
static func threat_dir(g, cur: Vector2, dt: float) -> Vector2:
	var want := Vector2(float(g.facing), 0.0)
	var near: Array = g.enemies_sys.nearest(12, Bal.v("command/escort_r", 420.0), g.ppos)
	if not near.is_empty():
		var s := Vector2.ZERO
		var n := 0
		for e in near:
			if e.dead or e.get("friendly", false):
				continue
			s += e.pos
			n += 1
		if n > 0:
			var d: Vector2 = s / float(n) - g.ppos
			if d.length() > 1.0:
				want = d.normalized()
	if cur == Vector2.ZERO:
		return want
	var a: float = cur.angle()
	var diff: float = angle_difference(a, want.angle())
	var stp: float = Bal.v("command/escort_turn", 3.0) * dt
	return Vector2.from_angle(a + clampf(diff, -stp, stp))


## 各队友的护卫站位（相对队长）：{干员: 偏移}；同职业多人按编队序左右错开
static func escort_offsets(sq, f: Vector2) -> Dictionary:
	var s: Vector2 = f.orthogonal()
	var groups := {"heavy": [], "melee": [], "ranged": [], "support": []}
	for o in sq.ops:
		if not o.is_leader:
			groups[role(o)].append(o)
	var out := {}
	for k in groups:
		var arr: Array = groups[k]
		arr.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
		for i in arr.size():
			var sign: float = 1.0 if i % 2 == 0 else -1.0
			var mag: float = 1.0 + float(i / 2) * 0.7
			var off: Vector2
			match k:
				"heavy":
					off = f * 72.0 + s * (0.0 if arr.size() == 1 else sign * 36.0 * mag)
				"melee":
					off = f * 44.0 + s * sign * 70.0 * mag
				"ranged":
					off = -f * 78.0 + s * sign * 62.0 * mag
				_:
					off = -f * 40.0 + s * sign * 30.0 * mag
			out[arr[i]] = off
	return out


# ================================================================ 突击：职业分工

## roam_target 候选得分的职业修正（越小越优先）；cands 里的原得分 d 是「离断后点的距离」（重装再加离队长距离）
static func role_score(o, en: Dictionary, d: float) -> float:
	var g = o.g
	match str(o.cls):
		"狙击":
			if en.get("elite", false) or en.get("part", false) or float(en.get("air", 0.0)) > 0.0 or en.get("hover", false):
				return d - Bal.v("command/role_snipe", 600.0)
		"术师":
			var n := 0
			for j in g.enemies_sys.query(en.pos, 90.0):
				var e2: Dictionary = g.enemies[j]
				if not e2.dead and e2.pos.distance_squared_to(en.pos) < 8100.0:
					n += 1
			return d - Bal.v("command/role_dense", 45.0) * float(mini(n, 8))
		"先锋":
			var ld: Vector2 = g.squad.lead_dir
			if ld != Vector2.ZERO:
				var v: Vector2 = en.pos - g.ppos
				if v.length() > 1.0:
					return d - Bal.v("command/role_lead", 320.0) * maxf(0.0, v.normalized().dot(ld))
		"近卫", "特种":
			return en.pos.distance_to(g.ppos)
	return d


# ================================================================ 部署：阻挡

static func block_cap(o) -> int:
	var v = o.def.get("command", {}).get("block", null)
	if v != null:
		return int(v)
	return int(Bal.v("command/block_" + str(o.cls), float(BLOCK_DEF.get(str(o.cls), 1))))


## 每帧（squad.update）：部署中、站到位的阻挡者把接触到的近战敌人挡住（原地停步、改打她），没挡满时把 block_pull 内最近的近战敌人引过来；
## 不在部署 / 倒地 / 撤回时全部放开
static func tick_block(sq) -> void:
	var g = sq.g
	var deploying: bool = sub("block") and sq.stance == sq.ROAM and str(sq.order_kind) == "point"
	for o in sq.ops:
		if o.is_leader:
			continue
		var cap: int = block_cap(o)
		if not deploying or cap <= 0 or not sq.roaming_op(o) or o.pos == Vector2.INF:
			o.cmd_blk.clear()
			continue
		var st: Vector2 = sq.station_of(o)
		if st == Vector2.INF or o.pos.distance_to(st) > Bal.v("command/block_at", 40.0):
			o.cmd_blk.clear()
			continue
		var used := 0
		var keep: Array = []
		for e in o.cmd_blk:
			if e.dead or e.boss or o.pos.distance_to(e.pos) > 18.0 + float(e.r) + 38.0:
				continue
			keep.append(e)
			used += 2 if e.elite else 1
		o.cmd_blk = keep
		var pull: float = Bal.v("command/block_pull", 140.0)
		for e in g.enemies_sys.nearest(12, pull, o.pos):
			if used >= cap:
				break
			if e.dead or e.boss or e.get("chest", false) or e.get("part", false) or e.get("friendly", false) or str(e.get("ai", "")) != "melee" or o.cmd_blk.has(e):
				continue
			if _blocked_by_other(sq, o, e):
				continue
			var w: int = 2 if e.elite else 1
			if used + w > cap:
				continue
			if o.pos.distance_to(e.pos) <= 18.0 + float(e.r) + 8.0:
				o.cmd_blk.append(e)
				used += w
			else:
				g.enemies_sys.set_aggro(e, o.pos)   # 还没挡满：引过来
		for e in o.cmd_blk:
			g.enemies_sys.set_aggro(e, e.pos)   # 挡住：本帧原地停步（enemies.gd 朝 aggro 走，距离 0 = 不动）


static func _blocked_by_other(sq, me, e: Dictionary) -> bool:
	for o in sq.ops:
		if o != me and not o.is_leader and o.cmd_blk.has(e):
			return true
	return false


# ================================================================ 医疗：给队友回血

## 每帧：医疗干员（含队长是医疗时）给 medic_r 内生命最低的一名队友回 medic_heal × dt（生命比例）
static func tick_medic(sq, dt: float) -> void:
	if not sub("heal_mates"):
		return
	for m in sq.ops:
		if str(m.cls) != "医疗" or m.cmd_down > 0.0 or m.pos == Vector2.INF:
			continue
		var best = null
		var bh := 1.0
		for o in sq.ops:
			if o.is_leader or o == m or o.cmd_down > 0.0 or o.pos == Vector2.INF:
				continue
			if o.cmd_hp < bh and o.pos.distance_to(m.pos) <= Bal.v("command/medic_r", 320.0):
				bh = o.cmd_hp
				best = o
		if best != null:
			best.cmd_hp = minf(1.0, best.cmd_hp + Bal.v("command/medic_heal", 0.06) * dt)
			best.cmd_heal_t = sq.g.t
