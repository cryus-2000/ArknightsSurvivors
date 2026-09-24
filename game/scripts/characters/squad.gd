## 编队（docs/23 §3）：持有编队位上的干员实例，负责招募 / 替换、编队校验、跟随队形与统一的 update / draw 分发。
## 常规上限 3 人，第 4 位由事件 / 藏品 / 商店解锁（extra_slot）。干员没有生命值，敌人只追博士。
extends RefCounted

const Character = preload("res://scripts/characters/character.gd")

const REGULAR_MAX := 3
## 编队位相对博士的偏移（博士朝右时；朝左镜像 x）：1 号位侧后、2 号位另一侧、3 号位正后、4 号位更后
const SLOTS := [Vector2(-34, -14), Vector2(38, 10), Vector2(-6, -44), Vector2(-44, 26)]

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
	for k in op.def.get("hit_sources", {}):
		g.hit_src[k] = op.def.hit_sources[k]
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
	var o: Vector2 = SLOTS[mini(i, SLOTS.size() - 1)]
	return Vector2(o.x * g.facing, o.y)


## 编队契约：常规人数 ≤ 3（解锁后 ≤ 4）；全队手动技能恰好 1 个且属于博士（干员一律 auto）
func validate_squad() -> bool:
	var ok := true
	if ops.size() > cap():
		push_error("编队超员：%d / %d" % [ops.size(), cap()])
		ok = false
	for o in ops:
		for sid in o.skills():
			if o.skills()[sid].get("mode", "auto") == "manual":
				push_error("干员 %s 的技能 %s 是 manual：手动技能只能属于博士" % [o.id, sid])
				ok = false
	return ok


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	for o in ops:
		o.follow(dt, g.ppos + _slot_offset(o.slot))
	for o in ops:
		o.update(dt)


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


func draw_shadows() -> void:
	for o in ops:
		if o.pos != Vector2.INF:
			g._spr("shadow", 1, 0, o.pos + Vector2(0, 4), g.PX)


func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	for o in ops:
		o.draw_fx_add(ci, loop)


func draw_skill_floor() -> void:
	for o in ops:
		o._draw_skill_floor()


func draw_skill_over() -> void:
	for o in ops:
		o._draw_skill_over()
