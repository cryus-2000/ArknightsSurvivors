extends RefCounted
## 属性系统（框架第 30 节）
## 统一计算顺序：Base → Flat → Additive% → Multiplicative → Override → 上下限
##   value = ((base + Σflat) × (1 + Σadd) × Πmult)，有 override 时取最后加入的 override
## 任何藏品、技能、成长都只能通过 add() 加修正，不能直接改最终值。
## 每条修正带 source，用 remove_source() 整体撤销（临时增益、藏品移除、排异反应消除）。

enum Op { FLAT, ADD, MULT, OVERRIDE }
const OP_NAMES := {"flat": Op.FLAT, "add": Op.ADD, "mult": Op.MULT, "override": Op.OVERRIDE}

var _base := {}      # stat -> float
var _limit := {}     # stat -> Vector2(min, max)
var _mods := {}      # stat -> Array[{op, value, source}]
var _cache := {}
var version := 0     # 任何修改都会 +1，外部可据此判断是否需要刷新


## 定义属性：基础值与上下限
func define(stat: StringName, base: float, lo: float = -INF, hi: float = INF) -> void:
	_base[stat] = base
	_limit[stat] = Vector2(lo, hi)
	_dirty(stat)


func define_all(defs: Dictionary) -> void:
	for k in defs:
		var d: Dictionary = defs[k]
		define(k, d.base, d.get("min", -INF), d.get("max", INF))


func has_stat(stat: StringName) -> bool:
	return _base.has(stat)


func set_base(stat: StringName, v: float) -> void:
	_base[stat] = v
	_dirty(stat)


func get_base(stat: StringName) -> float:
	return _base.get(stat, 0.0)


## 加一条修正。op 可以是 Op 枚举或字符串 "flat"/"add"/"mult"/"override"
func add(stat: StringName, op: Variant, value: float, source: String = "") -> void:
	assert(_base.has(stat), "未定义的属性: %s" % stat)
	var o: int = OP_NAMES[op] if op is String else int(op)
	if not _mods.has(stat):
		_mods[stat] = []
	_mods[stat].append({"op": o, "value": value, "source": source})
	_dirty(stat)


## 撤销某个来源的全部修正，返回撤销条数
func remove_source(source: String) -> int:
	var n := 0
	for stat in _mods:
		var before: int = _mods[stat].size()
		_mods[stat] = _mods[stat].filter(func(m): return m.source != source)
		if _mods[stat].size() != before:
			n += before - _mods[stat].size()
			_dirty(stat)
	return n


func count_source(source: String) -> int:
	var n := 0
	for stat in _mods:
		for m in _mods[stat]:
			if m.source == source:
				n += 1
	return n


func value(stat: StringName) -> float:
	if _cache.has(stat):
		return _cache[stat]
	var base: float = _base.get(stat, 0.0)
	var flat := 0.0
	var addp := 0.0
	var mult := 1.0
	var ov = null
	for m in _mods.get(stat, []):
		match m.op:
			Op.FLAT: flat += m.value
			Op.ADD: addp += m.value
			Op.MULT: mult *= m.value
			Op.OVERRIDE: ov = m.value
	var v: float = (base + flat) * (1.0 + addp) * mult
	if ov != null:
		v = ov
	var lim: Vector2 = _limit.get(stat, Vector2(-INF, INF))
	v = clampf(v, lim.x, lim.y)
	_cache[stat] = v
	return v


## 属性面板用：列出计算过程
func breakdown(stat: StringName) -> Dictionary:
	var out := {"base": _base.get(stat, 0.0), "flat": 0.0, "add": 0.0, "mult": 1.0, "override": null, "value": value(stat), "sources": []}
	for m in _mods.get(stat, []):
		match m.op:
			Op.FLAT: out.flat += m.value
			Op.ADD: out.add += m.value
			Op.MULT: out.mult *= m.value
			Op.OVERRIDE: out.override = m.value
		out.sources.append({"source": m.source, "op": m.op, "value": m.value})
	return out


func stats() -> Array:
	return _base.keys()


func _dirty(stat: StringName) -> void:
	_cache.erase(stat)
	version += 1
