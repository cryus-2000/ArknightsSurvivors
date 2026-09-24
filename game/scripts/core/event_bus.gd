extends RefCounted
## 战斗事件总线（框架第 28 节）
## 用法：
##   bus.on(E.HIT, _on_hit, self)            # 订阅；owner 用于整体退订
##   var p := bus.emit(E.HIT, {"amount": 10}) # 广播；返回（可能被监听者改过的）负载
##   bus.off_owner(self)
## 监听者按 priority 从高到低调用；同优先级按订阅顺序。
## 防止藏品互相触发无限循环：同一事件嵌套深度超过 MAX_DEPTH 时丢弃。

const MAX_DEPTH := 6

var _subs := {}          # event -> Array[{cb, owner, prio, seq}]
var _depth := {}         # event -> 当前嵌套深度
var _seq := 0
var dropped := 0         # 因嵌套过深被丢弃的次数（调试用）
var counts := {}         # event -> 广播次数（统计用）


func on(event: StringName, cb: Callable, owner: Variant = null, priority: int = 0) -> void:
	if not _subs.has(event):
		_subs[event] = []
	_seq += 1
	_subs[event].append({"cb": cb, "owner": owner, "prio": priority, "seq": _seq})
	_subs[event].sort_custom(func(a, b): return a.prio > b.prio or (a.prio == b.prio and a.seq < b.seq))


func off(event: StringName, cb: Callable) -> void:
	if _subs.has(event):
		_subs[event] = _subs[event].filter(func(s): return s.cb != cb)


## 退订某个 owner 的全部监听（藏品被移除、干员离场时用）
func off_owner(owner: Variant) -> void:
	for ev in _subs:
		_subs[ev] = _subs[ev].filter(func(s): return not is_same(s.owner, owner))


func has_listeners(event: StringName) -> bool:
	return _subs.has(event) and not _subs[event].is_empty()


func emit(event: StringName, data: Dictionary = {}) -> Dictionary:
	counts[event] = counts.get(event, 0) + 1
	if not _subs.has(event):
		return data
	var d: int = _depth.get(event, 0)
	if d >= MAX_DEPTH:
		dropped += 1
		return data
	_depth[event] = d + 1
	# 复制一份列表：监听者在回调里订阅 / 退订不影响本次广播
	for s in _subs[event].duplicate():
		if s.cb.is_valid():
			s.cb.call(data)
		if data.get("cancel", false):
			break
	_depth[event] = d
	return data


func clear() -> void:
	_subs.clear()
	_depth.clear()
	counts.clear()
	dropped = 0
