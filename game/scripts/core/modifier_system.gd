extends RefCounted
## 修正系统（框架第 29 节）：把藏品 / 技能分支 / 排异反应 / 难度的「效果数据」落实到游戏里。
## 五类效果（effects 数组里的每一项）：
##   stat    {"type":"stat", "stat":"dmg", "op":"add", "value":0.15}
##           stat 以 enemy_ 开头时作用于敌人属性块
##   trigger {"type":"trigger", "event":"Dodge", "if":{...}, "do":"temp_stat", "args":{...}, "cooldown":0}
##   status  {"type":"status", "status":"bind", "args":{"dot":0.6}}   —— 游戏查询 status_args("bind") 决定受控敌人的额外效果
##   spawn   {"type":"spawn", "every":20, "do":"spawn_mine", "args":{...}} —— 周期生成
##   rule    {"type":"rule", "rule":"shield_burst"}                     —— 开关 / 计数型规则，游戏查询 rule("shield_burst")
##   on_gain {"type":"on_gain", "do":"light", "args":{"amount":10}}      —— 获得时立即执行一次（灯火 +10、源石锭 +10 等）
## 条件 "if"（全部满足才触发）：
##   chance, light_below, light_above, hp_below, hp_above,
##   target_boss, target_elite, target_hp_below, src_is, tags_any, no_allies, hit_count_max
## 内置动作："temp_stat"（限时修正，可叠层）、"add_stat"（永久累加，有上限）
## 其他动作由游戏注册：register_action("heal", func(args, ev): ...)

const SB = preload("res://scripts/core/stat_block.gd")

var stats          # 玩家 StatBlock
var enemy          # 敌人 StatBlock
var bus            # EventBus
var ctx_provider: Callable   # 返回 {light, hp_ratio, allies, ...}，用于条件判断
## 条件里的概率（"chance"）用的随机数（2026-09-26）：玩法随机不能用全局 randf()（docs/36 §3、AGENTS.md）。
## 缺省自带一个固定种子的 RNG（核心测试可复现）；接进对局时由持有方注入对局随机数：mods.rng = g.rng
var rng := RandomNumberGenerator.new()
var t := 0.0

var _actions := {}           # name -> Callable(args: Dictionary, ev: Dictionary)
var _owners := {}            # owner_id -> {effects, tags}
var _rules := {}             # rule -> 计数
var _status := {}            # status -> Array[args]
var _temps: Array = []       # {source, until}
var _timers: Array = []      # {owner, every, left, do, args}
var _cool := {}              # key -> 可再次触发的时间
var _accum := {}             # key -> 已累加的永久值（add_stat 上限用）
var _temp_seq := 0
var fired := {}              # owner_id -> 触发次数（统计）


func _init(p_stats, p_enemy, p_bus) -> void:
	rng.seed = 1
	stats = p_stats
	enemy = p_enemy
	bus = p_bus


func register_action(name: String, cb: Callable) -> void:
	_actions[name] = cb


func has_owner(owner_id: String) -> bool:
	return _owners.has(owner_id)


## 应用一组效果。owner_id 例如 "relic:54"、"branch:s1_b"、"rejection:blur"、"diff:3"
func apply(owner_id: String, effects: Array) -> void:
	if _owners.has(owner_id):
		remove(owner_id)
	_owners[owner_id] = {"effects": effects}
	for i in effects.size():
		var ef: Dictionary = effects[i]
		match ef.get("type", "stat"):
			"stat":
				_block(ef.stat).add(ef.stat, ef.get("op", "add"), float(ef.value), owner_id)
			"trigger":
				var key := "%s#%d" % [owner_id, i]
				bus.on(StringName(ef.event), func(ev: Dictionary): _on_trigger(owner_id, key, ef, ev), owner_id, int(ef.get("priority", 0)))
			"status":
				if not _status.has(ef.status):
					_status[ef.status] = []
				var a: Dictionary = ef.get("args", {}).duplicate()
				a["_owner"] = owner_id
				_status[ef.status].append(a)
			"spawn":
				_timers.append({"owner": owner_id, "every": float(ef.every), "left": float(ef.get("first", ef.every)), "do": ef.do, "args": ef.get("args", {})})
			"rule":
				_rules[ef.rule] = _rules.get(ef.rule, 0) + int(ef.get("value", 1))
			"on_gain":
				_run(ef.do, ef.get("args", {}), {}, owner_id)
			_:
				push_warning("未知效果类型: %s" % ef)


func remove(owner_id: String) -> void:
	if not _owners.has(owner_id):
		return
	for ef in _owners[owner_id].effects:
		if ef.get("type", "stat") == "rule":
			_rules[ef.rule] = _rules.get(ef.rule, 0) - int(ef.get("value", 1))
			if _rules[ef.rule] <= 0:
				_rules.erase(ef.rule)
	stats.remove_source(owner_id)
	enemy.remove_source(owner_id)
	bus.off_owner(owner_id)
	for st in _status:
		_status[st] = _status[st].filter(func(a): return a._owner != owner_id)
	_timers = _timers.filter(func(tm): return tm.owner != owner_id)
	_owners.erase(owner_id)


func rule(name: String) -> int:
	return _rules.get(name, 0)


func status_args(status: String) -> Array:
	return _status.get(status, [])


## 每帧调用：清理过期的临时修正、推进周期生成
func tick(dt: float) -> void:
	t += dt
	if not _temps.is_empty():
		var keep: Array = []
		for tp in _temps:
			if t >= tp.until:
				stats.remove_source(tp.source)
				enemy.remove_source(tp.source)
			else:
				keep.append(tp)
		_temps = keep
	for tm in _timers:
		tm.left -= dt
		var guard := 0
		while tm.left <= 0.0 and guard < 8:
			guard += 1
			tm.left += tm.every
			_run(tm.do, tm.args, {}, tm.owner)


## 条件判断（公开给游戏用，例如 UI 预览）
func check(cond: Dictionary, ev: Dictionary) -> bool:
	if cond.is_empty():
		return true
	var c: Dictionary = ctx_provider.call() if ctx_provider.is_valid() else {}
	if cond.has("chance") and rng.randf() >= float(cond.chance):
		return false
	if cond.has("light_below") and c.get("light", 100.0) >= float(cond.light_below):
		return false
	if cond.has("light_above") and c.get("light", 0.0) <= float(cond.light_above):
		return false
	if cond.has("hp_below") and c.get("hp_ratio", 1.0) >= float(cond.hp_below):
		return false
	if cond.has("hp_above") and c.get("hp_ratio", 0.0) <= float(cond.hp_above):
		return false
	if cond.has("no_allies") and c.get("allies", 0) > 0:
		return false
	var tg = ev.get("target")
	if cond.get("target_boss", false) and not (tg is Dictionary and tg.get("boss", false)):
		return false
	if cond.get("target_elite", false) and not (tg is Dictionary and (tg.get("elite", false) or tg.get("boss", false))):
		return false
	if cond.has("target_hp_below") and not (tg is Dictionary and tg.get("hp", 1.0) < tg.get("maxhp", 1.0) * float(cond.target_hp_below)):
		return false
	if cond.has("src_is") and ev.get("src", "") != cond.src_is and not (cond.src_is is Array and ev.get("src", "") in cond.src_is):
		return false
	if cond.has("hit_count_max") and int(ev.get("hit_count", 1)) > int(cond.hit_count_max):
		return false
	if cond.has("tags_any"):
		var ok := false
		for tag in ev.get("tags", []):
			if tag in cond.tags_any:
				ok = true
				break
		if not ok:
			return false
	return true


func _on_trigger(owner_id: String, key: String, ef: Dictionary, ev: Dictionary) -> void:
	if t < _cool.get(key, -1.0):
		return
	if not check(ef.get("if", {}), ev):
		return
	if ef.has("cooldown"):
		_cool[key] = t + float(ef.cooldown)
	_run(ef.do, ef.get("args", {}), ev, owner_id, key)


func _run(action: String, args: Dictionary, ev: Dictionary, owner_id: String, key: String = "") -> void:
	fired[owner_id] = fired.get(owner_id, 0) + 1
	match action:
		"temp_stat":
			# args: stat, op, value, dur, max_stacks(默认 1：刷新而不叠加)
			var base_src := "temp:%s" % (key if key != "" else owner_id)
			var max_st: int = int(args.get("max_stacks", 1))
			var cur := 0
			for tp in _temps:
				if tp.base == base_src:
					cur += 1
			if cur >= max_st:
				# 刷新最早的一层
				for tp in _temps:
					if tp.base == base_src:
						tp.until = t + float(args.dur)
						break
				return
			_temp_seq += 1
			var src := "%s#%d" % [base_src, _temp_seq]
			_block(args.stat).add(args.stat, args.get("op", "add"), float(args.value), src)
			_temps.append({"source": src, "base": base_src, "until": t + float(args.dur)})
		"add_stat":
			# args: stat, op, value, cap（累加总量上限）
			var k := key if key != "" else owner_id
			var got: float = _accum.get(k, 0.0)
			var cap: float = float(args.get("cap", INF))
			var v: float = minf(float(args.value), cap - got)
			if v <= 0.0:
				return
			_accum[k] = got + v
			_block(args.stat).add(args.stat, args.get("op", "add"), v, owner_id)
		_:
			if _actions.has(action):
				_actions[action].call(args, ev)
			else:
				push_warning("未注册的动作: %s" % action)


func _block(stat: String):
	return enemy if String(stat).begins_with("enemy_") else stats
