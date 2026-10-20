## 干员帧条 / 动画数据契约（docs/108 §10 V1–V9；validate_operator 调用，test_core 用坏样例逐条覆盖）。
## 只读 json，不读贴图（读图的尺寸核对 V3 在 tools/art_lint.py）。每条错误以「V<n> 」开头，便于测试断言。
extends RefCounted

const MAIN_SLOTS := ["idle", "run", "attack", "skill", "hurt", "death"]
## 槽里这些键不是逐帧定位点（V5）
const NOT_POINTS := ["foot", "pt_foot", "frame_durations", "frame_size", "anchor"]
## 主画布：48 = 未换新美术的旧口径；64 = 现行；超界动作用 64 口径 foot + (16,16) / (32,32) 透明加边
const SIZES := [48, 64]
const PADS := [0.0, 16.0, 32.0]


static func errors(d: Dictionary) -> Array:
	var out: Array = []
	var sp = d.get("sprites", {})
	if not (sp is Dictionary) or sp.is_empty():
		return out   # 没有帧条的最小定义（契约反例 / 测试干员）只走 validate_operator 其余校验
	var extras: Array = d.get("extra_sprites", [])
	var targets := {}
	for key in sp:
		var v = sp[key]
		if v is Dictionary and v.get("visual") is Dictionary:
			targets[str(v.visual.get("anim", ""))] = true
	for key in sp:
		var v = sp[key]
		if not (v is Dictionary) or not v.has("tex"):
			continue
		var p := "sprites.%s" % key
		if v.has("attack_timing") and not valid_attack_timing(v):
			out.append("V1 %s.attack_timing 无效（duration / fire_time / active_ratio / windup_ratio 为正、fire_time < duration、0 < fire < frames）" % p)
		if v.has("logic"):   # docs/108 §4：[旧帧数, 旧 fps, 旧出手帧]，与画面的 frame_durations / fire_time 对得上（1e-6 内）
			var lg = v.logic
			if not (lg is Array) or lg.size() != 3 or not lg.all(func(x): return _num(x)) or float(lg[0]) <= 0.0 or float(lg[1]) <= 0.0 or float(lg[2]) < 0.0 or float(lg[2]) >= float(lg[0]):
				out.append("V7 %s.logic 须是 [旧帧数, 旧 fps, 旧出手帧]" % p)
			elif v.has("frame_durations") and v.frame_durations is Array:
				var tot := 0.0
				for x in v.frame_durations: tot += float(x)
				if absf(tot - float(lg[0]) / float(lg[1])) > 0.000001 or (v.has("fire_time") and absf(float(v.fire_time) - (float(lg[2]) + 0.5) / float(lg[1])) > 0.000001):
					out.append("V7 %s.logic 与 frame_durations 总长 / fire_time 不一致" % p)
		if v.has("frame_durations") and not valid_frame_durations(v):
			out.append("V7 %s.frame_durations 无效（长度 = frames、每帧正秒数、fire_time 在总时长内）" % p)
		elif v.has("frame_durations") and v.has("fire_time") and v.has("fire"):
			var ds: Array = v.frame_durations
			var fi := int(v.fire)
			var a := 0.0
			for k in mini(fi, ds.size()):
				a += float(ds[k])
			var b: float = a + (float(ds[fi]) if fi >= 0 and fi < ds.size() else 0.0)
			if float(v.fire_time) < a - 0.000001 or float(v.fire_time) >= b - 0.000001:
				out.append("V7 %s.fire_time %.4f 不在出手帧 fire=%d 的区间 [%.4f, %.4f)" % [p, float(v.fire_time), fi, a, b])
		var n := int(v.get("frames", 0))
		for pk in v:
			var pv = v[pk]
			if pk in NOT_POINTS or not _is_track(pv):
				continue
			if pv.size() != n:
				out.append("V5 %s.%s 逐帧点有 %d 个，帧条 %d 帧" % [p, pk, pv.size(), n])
			if pk == "muzzles":
				for fr in pv:
					if not (fr is Array) or fr.is_empty() or fr.any(func(q): return not _xy(q)):
						out.append("V6 %s.muzzles 每帧须是 [[x, y], …]" % p)
						break
		if _has_track(v) and float(sp.get("draw_scale", 1.0)) != 1.0:
			out.append("V9 %s 有逐帧定位点，但 sprites.draw_scale ≠ 1（定位点换算按整体缩放，先确认再豁免）" % p)
	_foot(sp, targets, out)
	_native(d, sp, extras, out)
	# V8：运行时会播的槽都要在 sprites 里、非主槽要列进 extra_sprites（不列不加载）
	var refs := {}
	var seqs = sp.get("skills", {})
	if seqs is Dictionary:
		for sk in seqs:
			var q = seqs[sk]
			if q is Dictionary and q.get("phases") is Array:
				for ph in q.phases:
					if ph is Dictionary:
						for slot in ph.values():
							refs[str(slot)] = "sprites.skills.%s.phases" % sk
	var sks = d.get("skills", [])
	if sks is Array:
		for i in sks.size():
			if sks[i] is Dictionary and sks[i].has("anim"):
				refs[str(sks[i].anim)] = "skills[%d].anim" % i
	var nm = d.get("native_motion", {})
	if nm is Dictionary:
		for slot in nm.get("clips", {}):
			refs[str(slot)] = "native_motion.clips"
		for list in ["states", "exits"]:
			for r in nm.get(list, []):
				if r is Dictionary and r.has("slot"):
					refs[str(r.slot)] = "native_motion." + list
		for r in nm.get("variants", []):
			if r is Dictionary and r.has("use"):
				refs[str(r.use)] = "native_motion.variants"
	for slot in refs:
		if not (sp.get(slot) is Dictionary) or not sp[slot].has("tex"):
			out.append("V8 %s 引用的帧条「%s」不在 sprites（须是带 tex 的槽）" % [refs[slot], slot])
		elif not slot in MAIN_SLOTS and not slot in extras:
			out.append("V8 %s 引用的帧条「%s」没列进 extra_sprites" % [refs[slot], slot])
	return out


## V2：画布与脚底口径（docs/108 §5）。小数 foot / 非 48·64 画布 / 不对称加边要在 json 写 foot_exempt 说明原因
static func _foot(sp: Dictionary, targets: Dictionary, out: Array) -> void:
	var size = sp.get("size", null)
	var base = sp.get("foot", null)
	var exempt: bool = sp.get("foot_exempt", "") is String and str(sp.get("foot_exempt", "")) != ""
	if not _xy(base):
		out.append("V2 sprites.foot 须是 [x, y]")
		return
	if not (size is int or size is float) or (not int(size) in SIZES and not exempt):
		out.append("V2 sprites.size 须是 64（现行）或 48（旧口径），其他画布写 sprites.foot_exempt 说明")
		return
	if int(size) == 48:
		if not exempt and float(base[1]) != 46.0:
			out.append("V2 48 画布的 sprites.foot 脚底行须是 46")
		return
	if int(size) == 64 and not exempt and (float(base[0]) != 32.0 or float(base[1]) != 60.0):
		out.append("V2 64 画布的 sprites.foot 须是 [32, 60]（小数原点写 sprites.foot_exempt 说明）")
	if int(size) != 64:
		return
	for key in sp:
		var v = sp[key]
		if not (v is Dictionary) or not v.has("tex") or not v.has("foot") or targets.has(key) or v.has("visual") or v.has("frame_size"):
			continue
		if v.get("foot_exempt", "") is String and str(v.get("foot_exempt", "")) != "":
			continue
		if not _xy(v.foot):
			out.append("V2 sprites.%s.foot 须是 [x, y]" % key)
			continue
		var dx: float = float(v.foot[0]) - float(base[0])
		var dy: float = float(v.foot[1]) - float(base[1])
		var pad_ok := false
		for pad in PADS:
			if absf(dx - pad) < 0.000001 and absf(dy - pad) < 0.000001:
				pad_ok = true
		if not pad_ok:
			out.append("V2 sprites.%s.foot %s 不是顶层 foot + (0|16|32) 透明加边（不对称裁窗写 foot_exempt 说明）" % [key, str(v.foot)])


## V4：native_motion（native_motion.gd 的数据口径）
static func _native(d: Dictionary, sp: Dictionary, _extras: Array, out: Array) -> void:
	if not d.has("native_motion"):
		return
	var nm = d.native_motion
	if not (nm is Dictionary):
		out.append("V4 native_motion 须是字典")
		return
	for k in nm:
		if not str(k) in ["_doc", "clips", "variants", "states", "exits", "yield"]:
			out.append("V4 native_motion.%s 不认识（只有 clips / variants / states / exits / yield）" % k)
	var yl = nm.get("yield", [])
	if not (yl is Array) or not yl.all(func(x): return x is String):
		out.append("V4 native_motion.yield 须是帧条名数组")
	var clips = nm.get("clips", {})
	if not (clips is Dictionary):
		out.append("V4 native_motion.clips 须是 {槽: 秒}")
	else:
		for slot in clips:
			if not _num(clips[slot]) or float(clips[slot]) <= 0.0:
				out.append("V4 native_motion.clips.%s 须是正秒数" % slot)
	for v in nm.get("variants", []):
		var by_perm: bool = v is Dictionary and (v.get("perm") is int or v.get("perm") is float) and int(v.perm) >= 0 and int(v.perm) <= 2
		var by_node: bool = v is Dictionary and v.get("node") is String and str(v.node) != ""
		if not (v is Dictionary) or not v.get("slot") is String or not v.get("use") is String or by_perm == by_node:
			out.append("V4 native_motion.variants 每条须是 {slot, use} 加 perm: 0–2 或 node: 成长节点 id（二选一）")
	for r in nm.get("states", []):
		if not (r is Dictionary) or not r.get("on") is String or str(r.get("on", "")) == "" or not r.get("slot") is String:
			out.append("V4 native_motion.states 每条须有 on 与 slot")
			continue
		if r.get("loop", false):
			continue
		var nf := int(sp.get(r.slot, {}).get("frames", 0)) if sp.get(r.slot) is Dictionary else 0
		var a = r.get("from", null)
		var b = r.get("to", a)
		if not _num(a) or not _num(b) or int(a) < 0 or int(b) < int(a) or int(b) >= nf or (r.has("rate") and (not _num(r.rate) or float(r.rate) < 0.0)):
			out.append("V4 native_motion.states「%s」须 0 ≤ from ≤ to < 帧数 %d、rate ≥ 0（或写 loop: true）" % [r.on, nf])
	for x in nm.get("exits", []):
		var nf := int(sp.get(x.get("slot", ""), {}).get("frames", 0)) if x is Dictionary and sp.get(x.get("slot", "")) is Dictionary else 0
		if not (x is Dictionary) or not x.get("on") is String or not _num(x.get("from")) or int(x.from) < 0 or int(x.from) >= nf or not _num(x.get("tail")) or float(x.tail) <= 0.0:
			out.append("V4 native_motion.exits 每条须是 {on, slot, from < 帧数, tail > 0}")


static func valid_attack_timing(spec: Dictionary) -> bool:
	if not spec.has("attack_timing"):
		return true
	var t = spec.attack_timing
	if not t is Dictionary:
		return false
	for key in ["duration", "fire_time", "active_ratio", "windup_ratio"]:
		if not typeof(t.get(key)) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(t[key])) or float(t[key]) <= 0.0:
			return false
	for key in ["min_duration", "min_rest"]:
		if t.has(key) and (not typeof(t[key]) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(t[key])) or float(t[key]) <= 0.0):
			return false
	if float(t.get("min_duration", 0.0)) > float(t.duration):
		return false
	return float(t.fire_time) < float(t.duration) and float(t.active_ratio) < 1.0 and float(t.windup_ratio) < 1.0 and int(spec.get("fire", 0)) > 0 and int(spec.get("fire", 0)) < int(spec.get("frames", 0))


static func valid_frame_durations(spec: Dictionary) -> bool:
	var ds = spec.get("frame_durations")
	if not ds is Array or ds.size() != int(spec.get("frames", 0)) or ds.is_empty():
		return false
	var total := 0.0
	for v in ds:
		if not typeof(v) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(v)) or float(v) <= 0.0:
			return false
		total += float(v)
	if spec.has("fire_time"):
		var t = spec.fire_time
		if not typeof(t) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(t)) or float(t) < 0.0 or float(t) >= total:
			return false
	return true


static func _num(v) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func _xy(v) -> bool:
	return v is Array and v.size() == 2 and _num(v[0]) and _num(v[1])

## 逐帧点：非空数组、每个元素是 null 或数组（[x, y] 或一组 [x, y]）
static func _is_track(v) -> bool:
	return v is Array and not v.is_empty() and v.all(func(x): return x == null or x is Array)

static func _has_track(v: Dictionary) -> bool:
	for pk in v:
		if not pk in NOT_POINTS and _is_track(v[pk]):
			return true
	return false
