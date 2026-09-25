## 编队（docs/23 §3）：持有编队位上的干员实例，负责招募 / 替换、编队校验、跟随队形与统一的 update / draw 分发。
## 常规上限 3 人，第 4 位由事件 / 藏品 / 商店解锁（extra_slot）。干员没有生命值，敌人只追博士。
extends RefCounted

const Character = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")

const REGULAR_MAX := 3
## 编队位相对博士的偏移（博士朝右时；朝左镜像 x）：1 号位侧后、2 号位另一侧、3 号位正后、4 号位更后
const SLOTS := [Vector2(-34, -14), Vector2(38, 10), Vector2(22, -46), Vector2(-44, 26)]
const DEMO_SLOT := Vector2(44, -6)

var g
var ops: Array = []            # Character 实例，按入队顺序
var extra_slot := false        # 第 4 位是否已解锁


func _init(game) -> void:
	g = game


func size() -> int:
	return ops.size()


func cap() -> int:
	return REGULAR_MAX + (1 if extra_slot else 0)


func is_full() -> bool:
	return ops.size() >= cap()


func has(cid: String) -> bool:
	for o in ops:
		if o.id == cid:
			return true
	return false


func get_op(cid: String):
	for o in ops:
		if o.id == cid:
			return o
	return null


func ids() -> Array:
	return ops.map(func(o): return o.id)


## 招募：实例化干员、登记专属属性与伤害来源、放到博士身边。满员返回 null
func add(cid: String):
	if has(cid) or is_full():
		return null
	var op = Character.create(g, cid)
	if op == null:
		return null
	op.slot = ops.size()
	ops.append(op)
	g.stats.define_all(op.stat_defs())
	# 干员档位系数（data/balance.json operators 段，docs/27 §3）：写入本干员作用域
	var bal: Dictionary = Bal.op(cid)
	for k in ["atk", "aspd", "range", "skill_power"]:
		var v: float = float(bal.get(k, 0.0))
		if v != 0.0:
			g.stats.add(StringName("op_" + k), "add", v, "balance:" + cid, "op:" + cid)
	for k in op.def.get("hit_sources", {}):
		var hs: Dictionary = op.def.hit_sources[k].duplicate(true)
		hs["class"] = op.cls
		hs["op"] = op.id
		g.hit_src[k] = hs
	op.pos = g.ppos + _slot_offset(op.slot)
	if op.has_method("on_join"):
		op.on_join()
	validate_squad()
	return op


## 移除（事件替换用）：被替换的干员成长清零
func remove(cid: String) -> void:
	for i in ops.size():
		if ops[i].id == cid:
			if ops[i].has_method("on_leave"):
				ops[i].on_leave()
			ops.remove_at(i)
			break
	for i in ops.size():
		ops[i].slot = i


func _slot_offset(i: int) -> Vector2:
	if g.demo_op != "":
		return DEMO_SLOT   # 图鉴演示：站在博士前方（朝右侧怪海），重置后不用先走回身后
	var o: Vector2 = SLOTS[mini(i, SLOTS.size() - 1)]
	return Vector2(o.x * g.facing, o.y)


## 编队契约：常规人数 ≤ 3（解锁后 ≤ 4）；每名干员至多 1 个手动技能（契约 v2.2，按 Space / J 由 doctor.try_manual_skill 路由）
func validate_squad() -> bool:
	var ok := true
	if ops.size() > cap():
		push_error("编队超员：%d / %d" % [ops.size(), cap()])
		ok = false
	for o in ops:
		var n := 0
		for i in o.skills_def().size():
			if o.skills_def()[i].get("mode", "auto") == "manual":
				n += 1
		if n > 1:
			push_error("干员 %s 有 %d 个手动技能：至多 1 个" % [o.id, n])
			ok = false
	return ok


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	for o in ops:
		o.follow(dt, g.ppos + _slot_offset(o.slot))
	for o in ops:
		o.update(dt)
		o._tick_pfx(dt)


## 干员侧挂点（同 dmg_taken_mult 询问模式，docs/26 第二批）
## 圣域：任一干员的 sanctuary() 覆盖到 p（流明的灯塔）→ 溟痕、黑潮圈外惩罚失效
func in_sanctuary(p: Vector2) -> bool:
	for o in ops:
		if o.has_method("sanctuary"):
			var sc: Dictionary = o.sanctuary()
			if not sc.is_empty() and p.distance_to(sc.pos) < sc.r:
				return true
	return false


## 博士本该倒下时，任一干员阻止（幽灵鲨 S2）
func prevent_death() -> bool:
	for o in ops:
		if o.has_method("prevent_death") and o.prevent_death():
			return true
	return false


## 博士光照半径倍率（流明 S2）
func light_radius_mult() -> float:
	var m := 1.0
	for o in ops:
		if o.has_method("light_radius_mult"):
			m *= o.light_radius_mult()
	return m


## 任一干员的持续型技能生效中
func any_skill_active() -> bool:
	for o in ops:
		if o.skill_active():
			return true
	return false


## 全队技力（按各自需求的百分比）；exclude 为不充能的干员（先锋自己）
func gain_sp(pct: float, exclude = null) -> void:
	for o in ops:
		if o != exclude:
			o.gain_sp(pct)


func sync_stats(st) -> void:
	for o in ops:
		o.sync_stats(st)


func on_kill(e: Dictionary) -> void:
	for o in ops:
		o.on_kill(e)


# ---------------------------------------------------------------- 绘制分发（world 坐标）

func draw_auras() -> void:
	for o in ops:
		o.draw_auras()


func draw_entities_floor() -> void:
	for o in ops:
		o.draw_entities_floor()
		o.draw_pfx(true)


func draw_shadows() -> void:
	for o in ops:
		if o.pos != Vector2.INF:
			g._spr("shadow", 1, 0, o.pos + Vector2(0, 4), g.PX)
		o.draw_extra_shadows()


func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	for o in ops:
		o.draw_fx_add(ci, loop)


func draw_skill_floor() -> void:
	for o in ops:
		o._draw_skill_floor()


func draw_skill_over() -> void:
	for o in ops:
		o._draw_skill_over()
		o.draw_pfx(false)
