## Native body presentation reads gameplay phases; it never schedules hits or movement.
## 数据驱动（docs/108 §3.5）：json 顶层 native_motion 声明
##   clips    {槽: 秒}            起手（_start_action）后按秒数整条播一遍的原生动作
##   variants [{slot, perm | node, use}] 起手槽 slot 在技能 perm（零基）永久生效、或已选成长节点 node 时换播 use
##   yield    [槽]              这些帧条（手写段的收尾动作等）正在播时不覆盖
##   states   [{on, slot, from, to, rate | loop}]  按顺序取第一条命中的：
##              on = "act:<槽>"：该动作窗口内；否则匹配手写段 native_signals() 的信号名（等于 on 或以 on + "." 开头）
##              帧 = from + min(to - from, int(k × rate))，k 为信号进度 0–1；loop = true 按该槽帧时长循环播
##              attack_clock = true：属于本轮普攻的信号延续动作末帧，直到信号结束
##   exits    [{on, slot, from, tail}]  信号族 on 上一帧有、本帧没有 → 从 from 帧起用 tail 秒播到末帧
## 本模块不认识具体干员，也不读手写段私有字段；信号由手写段的 *_native_signals 提供。
extends RefCounted

static func enabled(o) -> bool:
	return o.def.has("native_motion")

static func _nm(o) -> Dictionary:
	return o.def.native_motion

static func started(o) -> void:
	if not enabled(o): return
	var slot: String = o.act_anim
	if o.act_kind == "attack":
		for v in _nm(o).get("variants", []):
			var tk = o.get("taken")
			if str(v.slot) == slot and (o.perm[int(v.perm)] if v.has("perm") else (tk is Array and str(v.node) in tk)):
				slot = str(v.use)
				break
	o.native_motion["clip"] = slot if _nm(o).get("clips", {}).has(slot) else ""
	o.native_motion["t"] = 0.0
	o.native_motion["from"] = 0


## 明确配置阶段时钟的强化普攻，在起手时连逻辑一起换槽。
static func timed_attack_slot(o, slot: String) -> String:
	if not enabled(o): return slot
	for v in _nm(o).get("variants", []):
		if str(v.slot) != slot: continue
		var active: bool = o.perm[int(v.perm)] if v.has("perm") else str(v.node) in o.taken
		if active and o.sprite_spec(str(v.use)).has("attack_timing"): return str(v.use)
	return slot

static func _family(name: String) -> String:
	var dot := name.find(".")
	return name if dot < 0 else name.substr(0, dot)

static func _has(signals: Dictionary, on: String) -> bool:
	for key in signals:
		if key == on or key.begins_with(on + "."):
			return true
	return false

static func tick(o, dt: float) -> void:
	if not enabled(o): return
	var n: Dictionary = o.native_motion
	n["t"] = float(n.get("t", 0.0)) + dt
	var signals: Dictionary = o.native_signals()
	var prev: Dictionary = n.get("active", {})
	var now := {}
	for key in signals:
		now[_family(key)] = true
	for x in _nm(o).get("exits", []):
		var fam: String = str(x.on)
		if prev.has(fam) and not now.has(fam):
			n.merge({"clip": str(x.slot), "from": int(x.from), "t": 0.0, "tail": float(x.tail)}, true)
	n["active"] = now

static func pose(o, slot: String, frame: int, fallback: Dictionary) -> Dictionary:
	var tx: Texture2D = o.anim_tex(slot)
	if tx == null: return fallback
	var hf: int = o.anim_hframes(tx, slot)
	return {"tex": tx, "kind": slot, "frame": clampi(frame, 0, hf - 1), "hf": hf, "flip": (o.face < 0.0) != o.sprite_mirror(slot)}

static func _signal_k(signals: Dictionary, on: String) -> float:
	for key in signals:
		if key == on or key.begins_with(on + "."):
			return float(signals[key])
	return 0.0

static func state(o, st: Dictionary) -> Dictionary:
	if not enabled(o) or st.is_empty() or st.kind in ["death", "hurt", "entry"] or st.kind in _nm(o).get("yield", []): return st
	var signals: Dictionary = o.native_signals()
	for r in _nm(o).get("states", []):
		var on: String = str(r.on)
		var slot: String = str(r.slot)
		if on.begins_with("act:"):
			if o.act_anim != on.substr(4) or o.attack_t <= 0.0:
				continue
		elif not _has(signals, on):
			continue
		if o.attack_phased and o.act_kind == "attack" and (o.attack_t > 0.0 or r.get("attack_clock", false)) and slot == o.act_anim:
			# 普攻冲刺的位移仍读信号，身体姿势读本轮时钟，结束冲刺不倒播。
			var spec: Dictionary = o.sprite_spec(slot)
			return pose(o, slot, o.attack_phase_frame(int(spec.frames), int(spec.fire), o.attack_dur-o.attack_t, slot), st)
		if r.get("loop", false):
			var nf := int(o.sprite_spec(slot).get("frames", 1))
			return pose(o, slot, o.timed_frame(slot, range(nf), o.g.t, true), st)
		var from: int = int(r.get("from", 0))
		var to: int = int(r.get("to", from))
		return pose(o, slot, from + mini(to - from, int(_signal_k(signals, on) * float(r.get("rate", 0.0)))), st)
	var n: Dictionary = o.native_motion
	var slot: String = str(n.get("clip", ""))
	if slot == "" or int(o.get("sq_ph")) != 0: return st   # 技能序列（不经 _start_action 起手）期间不让上一个 clip 盖住
	if o.anim_kind == "run" and float(n.get("t", 0.0)) >= float(o.attack_fire_at): return st   # 出手后在跑：整条动作让给跑步，不再卡末帧滑步（10-22 用户）
	var start: int = int(n.get("from", 0))
	if start == 0 and o.attack_phased and o.act_kind == "attack":
		# 普攻只认逻辑阶段时钟；技能变体可换姿势，不能另起固定秒数覆盖。
		if o.attack_t <= 0.0 or o.act_anim_yield() or slot == o.act_anim: return st
		var count: int = int(o.sprite_spec(slot).get("frames", 8))
		return pose(o, slot, o.attack_phase_frame(count, int(o.sprite_spec(slot).get("fire", 0)), o.attack_dur-o.attack_t, slot), st)
	var duration: float = float(n.get("tail", .16)) if start > 0 else float(_nm(o).get("clips", {}).get(slot, 0.0))
	if float(n.get("t", 0.0)) >= duration: return st
	var hf: int = int(o.sprite_spec(slot).get("frames", 8))
	if start == 0 and o.sprite_spec(slot).has("frame_durations") and absf(o.frames_seconds(slot, range(hf)) - duration) < 0.000001:
		return pose(o, slot, o.timed_frame(slot, range(hf), float(n.t)), st)   # clip 秒数 = 逐帧时长总和时按逐帧播（艾丽妮三段刺：刺出帧对准各段命中）；否则均匀播
	var fr: int = start + int(float(n.t) / maxf(duration, .001) * (hf - start))
	return pose(o, slot, fr, st)
