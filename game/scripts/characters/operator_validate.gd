extends RefCounted
## 招募时的干员 / 积木校验（docs/126 C3，10-22 由 characters/character.gd 原样搬出；Character.create 调，只读、只报错）

const OpDefs = preload("res://scripts/characters/operator_defs.gd")
const OperatorContract = preload("res://scripts/characters/operator_contract.gd")   # 帧条 / 动画数据契约（docs/108 §10）
const ObCheck = preload("res://scripts/characters/blocks/seg_angelina.gd")   # 积木校验入口（同 character.gd 原 ObCheck）


## 招募时的干员 / 积木校验（约 2500 行，只读、只报错）：只在 debug 构建（编辑器、快检、批跑）跑，发布版每次招募不再跑（docs/101 S8）。
## --novalidate：debug 下也跳过，用来对照校验没有副作用（同 seed TRACE 逐行相同）。JSON 的正确性由快检 core / 各积木测试保证
static func validate_on() -> bool:
	return OS.is_debug_build() and not OS.get_cmdline_user_args().has("--novalidate")


## 干员契约 v2.1（docs/23 §4.2）：attack（普攻）+ 恰好 3 个自动技能 skills[0..2]（招募 / 精一 / 精二解锁）；talent 可选（精一）；
## 手动技能只属于博士；progression 若存在必须是数组，节点 type ∈ stat / elite / custom，elite 节点带 level
static func validate_operator(cid: String, d: Dictionary) -> bool:
	var ok := true
	if not d.has("attack") or not (d.attack is Dictionary):
		push_error("干员 %s 缺少 attack 定义" % cid)
		ok = false
	var sk = d.get("skills", null)
	if not (sk is Array) or sk.size() != 3:
		push_error("干员 %s 必须恰好定义 3 个技能（skills 数组）" % cid)
		ok = false
	else:
		for i in 3:
			if not (sk[i] is Dictionary) or not sk[i].has("name"):
				push_error("干员 %s 的技能 %d 缺 name" % [cid, i + 1])
				ok = false
			elif not sk[i].get("mode", "auto") in ["auto", "manual"]:
				push_error("干员 %s 的技能 %d 的 mode 只能是 auto / manual" % [cid, i + 1])
				ok = false
			elif sk[i].has("anim") and not d.get("sprites", {}).has(str(sk[i].anim)):
				push_error("干员 %s 的技能 %d 的 anim「%s」不是它的帧条（sprites 里没有）" % [cid, i + 1, sk[i].anim])
				ok = false
		if sk.filter(func(x): return x is Dictionary and x.get("mode", "auto") == "manual").size() > 1:
			push_error("干员 %s 最多只能有 1 个手动技能" % cid)
			ok = false
	if d.get("sprites", {}).has("skill_pose"):
		push_error("干员 %s 的 sprites.skill_pose 已移除，请按 docs/105 §4 迁移到 sprites.skills" % cid)
		ok = false
	# 帧条 / 动画数据契约 V1–V9（docs/108 §10：attack_timing、frame_durations、画布与 foot、native_motion、逐帧点、extra_sprites）
	for contract_error in OperatorContract.errors(d):
		push_error("干员 %s：%s" % [cid, contract_error])
		ok = false
	# 多条技能帧条（sprites.skills，docs/87 §3.5）：键 s1–s3，引用的帧条要在 sprites 里，非主动作的要列进 extra_sprites
	var sq_ = d.get("sprites", {}).get("skills", null)
	if sq_ != null:
		if not (sq_ is Dictionary):
			push_error("干员 %s 的 sprites.skills 须是字典" % cid)
			ok = false
		else:
			for sk_ in sq_:
				if str(sk_).begins_with("_"):
					continue   # _doc
				var q = sq_[sk_]
				if not str(sk_) in ["s1", "s2", "s3"] or not (q is Dictionary):
					push_error("干员 %s 的 sprites.skills 键「%s」须是 s1 / s2 / s3 且值为字典" % [cid, sk_])
					ok = false
					continue
				if not (q.has("anim") or q.has("hold") or q.has("start")):
					push_error("干员 %s 的 sprites.skills.%s 要有 anim、hold 或 start" % [cid, sk_])
					ok = false
				if q.has("hold") and not q.has("intro"):
					push_error("干员 %s 的 sprites.skills.%s 有 hold 就要有 intro" % [cid, sk_])
					ok = false
				if q.has("hold") and q.has("start"):
					push_error("干员 %s 的 sprites.skills.%s 不能同时写 hold 与 start" % [cid, sk_])
					ok = false
				if q.has("anim") and ["intro", "hold", "start", "enter", "loop", "run", "attack", "end"].any(func(key): return q.has(key)):
					push_error("干员 %s 的 sprites.skills.%s 单条 anim 不能混写序列字段" % [cid, sk_])
					ok = false
				if q.has("start") and not q.has("loop"):
					push_error("干员 %s 的 sprites.skills.%s 有 start 就要有 loop" % [cid, sk_])
					ok = false
				if (q.has("attack") or q.has("run") or q.has("enter")) and (not q.has("loop") or not q.has("start") or q.has("hold")):
					push_error("干员 %s 的 sprites.skills.%s 的 attack / run / enter 槽需要 start 与 loop，不能用于 hold" % [cid, sk_])
					ok = false
				for key in ["shadow", "shadow_a"]:
					if q.has(key) and (not (q[key] is float or q[key] is int) or not is_finite(float(q[key])) or float(q[key]) < 0.0 or float(q[key]) > 1.0):
						push_error("干员 %s 的 sprites.skills.%s.%s 须为 0–1 的数值" % [cid, sk_, key])
						ok = false
				for part in ["anim", "intro", "hold", "start", "enter", "loop", "run", "end", "attack"]:
					if not q.has(part):
						continue
					var seg = q[part]
					if part == "attack" and seg is Dictionary:
						push_error("干员 %s 的 sprites.skills.%s.attack 须是帧条名（出手帧按该条 fire）" % [cid, sk_])
						ok = false
						continue
					if seg is Dictionary and seg.has("reverse") and not (seg.reverse is bool):
						push_error("干员 %s 的 sprites.skills.%s.%s.reverse 须是布尔值" % [cid, sk_, part])
						ok = false
					var k := OpDefs.seq_anim(seg)
					if k == "" or not d.sprites.has(k) or not (d.sprites[k] is Dictionary) or not d.sprites[k].has("tex"):
						push_error("干员 %s 的 sprites.skills.%s.%s 帧条「%s」不在 sprites（须是带 tex 的槽）" % [cid, sk_, part, k])
						ok = false
					elif not k in ["idle", "run", "attack", "skill", "hurt", "death"] and not k in d.get("extra_sprites", []):
						push_error("干员 %s 的 sprites.skills.%s.%s 帧条「%s」没列进 extra_sprites" % [cid, sk_, part, k])
						ok = false
					elif seg is Dictionary and seg.has("frames"):
						var nf = d.sprites[k].get("frames", null)
						if not (seg.frames is Array) or seg.frames.is_empty() or seg.frames.any(func(x): return not (x is float or x is int) or float(x) != float(int(x)) or int(x) < 0 or (nf != null and int(x) >= int(nf))):
							push_error("干员 %s 的 sprites.skills.%s.%s.frames 须是帧条范围内的帧号数组" % [cid, sk_, part])
							ok = false
	for visual_error in preload("res://scripts/characters/summon_visual.gd").errors(d.get("sprites", {}), d.get("extra_sprites", [])):
		push_error("%s: %s" % [cid, visual_error])
		ok = false
	var prog = d.get("progression", [])
	if not (prog is Array):
		push_error("干员 %s 的 progression 必须是数组" % cid)
		return false
	for i in prog.size():
		var n = prog[i]
		if not (n is Dictionary) or not n.get("type", "") in ["stat", "elite", "custom"]:
			push_error("干员 %s 的成长节点 %d 类型非法" % [cid, i])
			ok = false
		elif n.type == "elite" and not n.has("level"):
			push_error("干员 %s 的精英化节点 %d 缺 level" % [cid, i])
			ok = false
	var fac = d.get("faction", [])
	if not (fac is Array) or fac.any(func(x): return not (x is String) or x == ""):
		push_error("干员 %s 的 faction 必须是字符串数组" % cid)
		ok = false
	# 数据干员（docs/61 §8）：积木名、参数、$ 引用、伤害来源、节点对应
	if d.has("blocks") and not ObCheck.validate(cid, d):
		ok = false
	return ok
