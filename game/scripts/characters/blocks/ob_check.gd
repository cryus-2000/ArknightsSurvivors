## 干员积木 · ob_check（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_core.gd"


# ================================================================ 校验（docs/61 §8）

## 校验数据干员的 blocks 段；每条错误 push_error 一行（写明干员与字段路径）。返回是否通过
static func validate(cid: String, d: Dictionary) -> bool:
	var errs: Array = []
	var blocks = d.get("blocks", null)
	if not (blocks is Dictionary):
		errs.append("blocks 必须是对象")
		return _report(cid, errs)
	var base: Dictionary = d.get("base", {})
	var srcs: Dictionary = d.get("hit_sources", {})
	var ctx := {"base": base, "srcs": srcs, "errs": errs, "custom": 0, "summons": blocks.get("summons", {}), "sprites": d.get("sprites", {}), "stat_defs": d.get("stat_defs", {})}
	for k in blocks:
		if not k in ["zone", "attack", "trait", "skills", "talent", "progression", "summons", "follow", "hit_fx", "look", "dmg_bonus", "response", "_doc"]:
			errs.append("blocks.%s：不认识的段（只能是 zone / attack / trait / skills / talent / progression / summons / follow / hit_fx / look / dmg_bonus / response）" % k)
	if blocks.has("response"):   # 响应动作（docs/118）
		preload("res://scripts/characters/blocks/responses.gd").validate_section(blocks.response, ctx, _F())
	_F()._hw_top(blocks, ctx)   # 手写迁移段：follow / hit_fx / look
	if blocks.has("summons"):   # 召唤物种类（文件末尾「召唤 / 封印段」）
		_F()._sm_kinds(blocks, ctx)
	if blocks.has("zone"):
		var z = blocks.zone
		if not (z is Dictionary):
			errs.append("blocks.zone 必须是对象")
		else:
			if not str(z.get("center", "")) in ["leader", "self"]:
				errs.append("blocks.zone.center 只能是 leader / self")
			_num(z, "r", "blocks.zone", ctx, true)
			_num(z, "ring", "blocks.zone", ctx, false, 0.0, 2.0)   # 区域边线透明度倍率（10-14 加，纯画面）
	var atk = blocks.get("attack", null)
	if atk is Dictionary and str(atk.get("shape", "")) == "support":   # 召唤物扩展段：不造成伤害的普攻（凯尔希的治疗）
		_F()._mf_support(atk, ctx)
	elif not (atk is Dictionary) or not str(atk.get("shape", "")) in ATTACK_SHAPES:
		errs.append("blocks.attack 必须是一个伤害形状（%s）" % " / ".join(ATTACK_SHAPES.map(func(x): return "shape." + x)))
	else:
		_block(atk, "blocks.attack", "attack", ctx)
		_num(atk, "every", "blocks.attack", ctx, true, 0.1)
		_num(atk, "range", "blocks.attack", ctx, false)
		_F()._hw_attack(atk, ctx)   # 手写迁移段：first / idle / anim / turn / combo / armed
	var atk_shape: String = str(atk.get("shape", "")) if atk is Dictionary else ""
	var sk = blocks.get("skills", null)
	var skd: Array = d.get("skills", [])
	if not (sk is Array) or sk.size() != 3:
		errs.append("blocks.skills 必须恰好 3 条（与 skills 一一对应）")
	else:
		for i in 3:
			var p := "blocks.skills[%d]" % i
			var sb = sk[i]
			if not (sb is Dictionary):
				errs.append(p + " 必须是对象")
				continue
			var perm_json: bool = skd.size() > i and skd[i] is Dictionary and skd[i].get("permanent", false)
			var dv = sb.get("dur", 0)
			if dv is Dictionary and dv.has("ammo"):   # dur.ammo（能天使段：N 发子弹）
				_F()._exu_dur(dv, p, perm_json, i, ctx)
			elif dv is Dictionary and dv.has("pulses"):   # dur.pulses（手写迁移段：连续喷发，_hw_skill 查）
				pass
			elif dv is Dictionary:   # dur.next_n（安洁莉娜段：接下来 N 次普攻）
				_F()._v_next_n(sb, p, perm_json, ctx)
			elif dv is String and dv == "permanent":
				if not perm_json:
					errs.append("%s.dur 是 permanent，但 skills[%d] 没写 \"permanent\": true" % [p, i])
			else:
				if perm_json:
					errs.append("skills[%d] 是 permanent，%s.dur 也要写 \"permanent\"" % [i, p])
				var ev := eval_expr(dv, base)
				if not ev[0]:
					errs.append("%s.dur：%s" % [p, ev[2]])
				elif ev[1] < 0.0:
					errs.append("%s.dur 不能为负" % p)
			for k in sb:
				if not k in ["dur", "do", "fx", "aim", "status", "status_col", "attack_phases", "attack_effect"] + EXU_SKILL_KEYS + HW_SKILL_KEYS:
					errs.append("%s.%s：技能积木只有 dur / do / fx / aim / aim_r / status / status_col / attack_patch / end 这几个字段" % [p, k])
				elif k == "aim" and not (str(sb.aim) in ["leader", "nearest", "los", "range", "tether", "elite", "cluster"] or (str(sb.aim).begins_with("summon:") and ctx.summons is Dictionary and ctx.summons.has(str(sb.aim).substr(7)))):
					errs.append("%s.aim 只能是 leader / nearest / summon:<blocks.summons 里的种类>" % p)
				elif k == "attack_patch" and atk_shape == "point_aoe" and not (dv is Dictionary and dv.has("next_attacks")):
					errs.append("%s.attack_patch：落点弹普攻（shape.point_aoe）的 attack_patch 只能配 dur.next_n（{\"next_attacks\": N}）" % p)
			if sb.has("attack_phases"):
				preload("res://scripts/characters/blocks/attack_phases.gd").validate(sb, p, ctx, atk, i, eval_expr)
				_F().h4_phase_validate(sb, p, ctx, atk, i)
				if preload("res://scripts/characters/blocks/attack_phases.gd").has_swap(sb):   # 只查同一技能（docs/108 F9）：别的技能换普攻不影响本技能分阶段
					errs.append(p + ".attack_phases cannot combine swap_attack")
				for sw in preload("res://scripts/characters/blocks/attack_phases.gd").swap_attacks(blocks):   # 别的技能换上的普攻也会被分阶段接管，形状要同样合规
					if not sw is Dictionary or not str(sw.get("shape", "")) in ["circle", "cone"] or sw.has("armed") or sw.has("combo"):
						errs.append(p + ".attack_phases：本干员其他技能的 swap_attack 换上的普攻须是 circle / cone")
			_num(sb, "aim_r", p, ctx, false, 1.0, 2000.0)
			if sb.has("fx"):
				_F()._fx(sb.fx, p + ".fx", ctx, "cast")
			_list(sb.get("do", []), p + ".do", "skill", ctx)
			_F()._exu_skill(sb, p, ctx, atk_shape)   # 能天使段：attack_patch（落点弹的由 _v_next_n 查）/ end
			_F()._hw_skill(sb, p, ctx)   # 手写迁移段：cast: instant / dur.pulses + pulse
	for sec in ["trait", "talent"]:
		var arr = blocks.get(sec, [])
		if not (arr is Array):
			errs.append("blocks.%s 必须是数组" % sec)
			continue
		for i in arr.size():
			_trig(arr[i], "blocks.%s[%d]" % [sec, i], ctx)
	var pg = blocks.get("progression", {})
	if not (pg is Dictionary):
		errs.append("blocks.progression 必须是对象（节点 id → 积木）")
	else:
		var custom_ids: Array = []
		var branch_keys: Array = []   # 分支培养（docs/119 §4.1）：节点 4 branch 的路线 id；节点 5 routes 的键必须与之一致
		for n in d.get("progression", _EA):
			if n is Dictionary and n.get("type", "") == "custom":
				custom_ids.append(str(n.get("id", "")))
				if n.has("alt"):   # 开关开时替换的节点（docs/120 安洁莉娜）
					if not (n.alt is Dictionary) or not n.alt.has("id") or not n.alt.has("name") or not n.alt.has("desc"):
						errs.append("progression 节点「%s」的 alt 要有 id / name / desc" % str(n.get("id", "")))
					else:
						custom_ids.append(str(n.alt.id))
				for key in ["branch", "routes"]:
					if not n.has(key):
						continue
					var alts = n.get(key)
					if not (alts is Dictionary) or alts.size() < 2:
						errs.append("progression 节点「%s」的 %s 必须是 ≥ 2 条路线的对象 {路线 id: {id, name, desc, …}}" % [str(n.get("id", "")), key])
						continue
					if key == "branch":
						branch_keys = alts.keys()
					elif not branch_keys.is_empty() and alts.keys() != branch_keys:
						errs.append("progression 节点「%s」的 routes 键 %s 与分支节点的路线 %s 不一致" % [str(n.get("id", "")), str(alts.keys()), str(branch_keys)])
					for rk in alts:
						var rd = alts[rk]
						if not (rd is Dictionary) or not rd.has("id") or not rd.has("name") or not rd.has("desc"):
							errs.append("progression 节点「%s」的 %s.%s 要有 id / name / desc" % [str(n.get("id", "")), key, str(rk)])
						else:
							custom_ids.append(str(rd.id))
		for k in pg:
			if not (k in custom_ids or k in ["elite1", "elite2"]):
				errs.append("blocks.progression.%s：不是 progression 里的 custom 节点 id，也不是 elite1 / elite2" % k)
			else:
				_node(pg[k], "blocks.progression." + k, ctx)
		for cid2 in custom_ids:
			if not pg.has(cid2):
				errs.append("progression 的 custom 节点「%s」在 blocks.progression 里没有积木" % cid2)
	if ctx.custom > 2:
		errs.append("custom 逃生口用了 %d 个（每名干员至多 2 个，docs/61 §6）" % ctx.custom)
	return _report(cid, errs)


static func _report(cid: String, errs: Array) -> bool:
	for e in errs:
		push_error("干员 %s 的 %s" % [cid, e])
	return errs.is_empty()


## 成长节点：触发积木，或一块常驻效果积木
static func _node(b, p: String, ctx: Dictionary) -> void:
	if b is Array:   # 召唤物扩展段（§15.9）：一个节点可以写几块积木（数组，按顺序生效）
		if b.is_empty() or b.size() > 8:
			ctx.errs.append(p + "：积木数组要有 1–8 块")
		for i in b.size():
			_node(b[i], "%s[%d]" % [p, i], ctx)
		return
	if b is Dictionary and b.has("trig"):
		_trig(b, p, ctx)
	else:
		_block(b, p, "sustain", ctx)


static func _trig(b, p: String, ctx: Dictionary) -> void:
	if not (b is Dictionary) or not b.has("trig"):
		ctx.errs.append(p + "：这里要一个触发积木（{\"trig\": …, \"do\": […]}）")
		return
	_block(b, p, "trig", ctx)


static func _list(arr, p: String, kind: String, ctx: Dictionary) -> void:
	if not (arr is Array):
		ctx.errs.append(p + " 必须是数组")
		return
	for i in arr.size():
		_block(arr[i], "%s[%d]" % [p, i], kind, ctx)


## 一块积木。kind：attack（普攻形状）/ skill（技能 do：瞬时 + 常驻都行）/ sustain（常驻列表）/ instant（触发器的 do）/ on_hit（命中状态）/ trig
static func _block(b, p: String, kind: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	if not (b is Dictionary):
		errs.append(p + " 必须是对象")
		return
	var fams: Array = FAMILIES.filter(func(f): return b.has(f))
	if fams.size() != 1:
		errs.append("%s：每块积木恰好一个族键（shape / verb / aura / st / trig / custom），这里有 %d 个" % [p, fams.size()])
		return
	var fam: String = fams[0]
	if b.has("cond"):
		if not (b.cond is String):
			errs.append(p + ".cond 必须是字符串")
		else:
			var c := parse_cond(b.cond, ctx.base)
			if c.has("err"):
				errs.append("%s.cond：%s" % [p, c.err])
	# 所有 $ 表达式
	for k in b:
		if k != "cond" and b[k] is String and "$" in b[k]:
			var ev := eval_expr(b[k], ctx.base)
			if not ev[0]:
				errs.append("%s.%s：%s" % [p, k, ev[2]])
	if b.has("fx"):
		_F()._fx(b.fx, p + ".fx", ctx, "%s.%s" % [fam, str(b[fam])] if fam != "custom" else "custom")
	if fam == "st":   # 精英化段：命中状态的 first_only / cd（任何 st.* 都能写）
		_F()._el_st_common(b, p, ctx)
	if fam == "custom":
		ctx.custom += 1
		if not kind in ["skill", "instant"]:
			errs.append(p + "：custom 只能放在技能或触发器的 do 里（瞬时执行）")
		return
	var nm: String = str(b[fam])
	var tag := "%s.%s" % [fam, nm]
	if tag in SHARED_TAGS:   # 第三批多名干员共用、合并时统一的积木（verb.displace / verb.field / verb.buff_leader，文件末尾「共用积木」段）
		_v_shared(b, p, kind, ctx, tag)
		return
	var xk = _F().ext_kind(tag)   # 星熊段（文件末尾 EXT_BLOCKS）：放置与参数在 _ext_block 里查
	if xk != "":
		_F()._ext_block(b, p, kind, tag, xk, ctx)
		return
	if tag in ANGELINA_TAGS:   # 安洁莉娜段
		_F()._v_angelina(b, p, kind, ctx, tag)
		return
	if tag in ["trig.on_leader_skill", "trig.on_stance", "trig.on_leader_still"]:   # 响应动作（docs/118）
		if kind != "trig":
			errs.append("%s：「%s」只能放在 blocks.response" % [p, tag])
			return
		preload("res://scripts/characters/blocks/responses.gd").validate(b, p, tag, ctx, _F())
		return
	if nm in TX_IMPL.get(fam, []):   # 德克萨斯段
		_F()._tx_block(b, p, kind, tag, ctx)
		return
	if _F()._exu_block(b, p, kind, ctx, tag):   # 能天使段
		return
	if _F()._sm_block(b, p, kind, ctx, tag):   # 召唤 / 封印段
		return
	if _F()._mf_block(b, p, kind, ctx, tag):   # 召唤物扩展段（§15.9）
		return
	if _F()._el_block(b, p, kind, ctx, tag):   # 精英化段（docs/91 第 1 批）
		return
	if _F()._hw_block(b, p, kind, ctx, tag):   # 手写迁移段（精英化第 2 批：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安）
		return
	if nm in PLANNED.get(fam, []):
		errs.append("%s：积木「%s」已登记（docs/61 📝）但还没实现" % [p, tag])
		return
	if not nm in IMPL.get(fam, []):
		errs.append("%s：不认识的积木「%s」" % [p, tag])
		return
	# 放的位置
	var instant: bool = tag in ["shape.circle", "shape.cone", "verb.sp_team"] or (tag == "verb.heal" and not b.has("every")) or (tag == "verb.lamp" and b.has("add"))
	var sustained: bool = (not instant and fam != "trig" and fam != "st") or tag == "st.slow_soft"
	match kind:
		"attack":
			pass
		"trig":
			if fam != "trig":
				errs.append("%s：这里要触发积木，不是「%s」" % [p, tag])
				return
		"on_hit":
			if not tag in ["st.stun", "st.slow"]:
				errs.append("%s：on_hit 里只能放 st.stun / st.slow，不能放「%s」" % [p, tag])
				return
		"instant":
			if not instant:
				errs.append("%s：触发器的 do 只执行一次，「%s」是常驻积木，放这里不会生效" % [p, tag])
				return
		"sustain":
			if not sustained:
				errs.append("%s：常驻列表里只能放常驻积木，「%s」是瞬时的（放到技能 do 或 trig.every_n / tick 的 do 里）" % [p, tag])
				return
		"skill":
			if fam == "trig" or tag in ["st.stun", "st.slow"]:
				errs.append("%s：技能 do 里不能放「%s」" % [p, tag])
				return
	match tag:
		"shape.circle", "shape.cone":
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			if not (b.get("r", null) is String and b.r == "zone"):
				_num(b, "r", p, ctx, true)
			if tag == "shape.cone":
				if b.has("half"):   # 召唤物扩展段：half = 弧度（半角）
					_num(b, "half", p, ctx, true, 0.05, PI)
				else:
					_num(b, "half_deg", p, ctx, true)
				if str(b.get("center", "self")) != "self":
					errs.append(p + ".center：shape.cone 只能以自身为原点")
			elif str(b.get("center", "")).begins_with("summon:"):
				var sk2 := str(b.center).substr(7)
				if not (ctx.summons is Dictionary and ctx.summons.has(sk2)):
					errs.append("%s.center「%s」：summon: 后面应是 blocks.summons 里的种类" % [p, str(b.center)])
			elif str(b.get("center", "")) == "path":   # 精英化段：沿上一次冲刺 / 残像路径
				_num(b, "step", p, ctx, true, 8.0, 400.0)
				_num(b, "delay", p, ctx, false, 0.0, 5.0)
				_num(b, "stagger", p, ctx, false, 0.0, 1.0)
			elif not str(b.get("center", "zone")) in ["zone", "self", "leader", "target", "front"]:
				errs.append(p + ".center 只能是 zone / self / leader / target / path / front / summon:<种类>")
			_F()._e5_shape(b, p, ctx, tag)   # 精英化第 5 批段：band / among、center summon:<种类> + r: zone
			if b.has("only"):   # 精英化段：只打处于这些状态的敌人
				var ol = b.only
				if not (ol is Array) or ol.is_empty() or ol.any(func(x): return not str(x) in EL_ONLY):
					errs.append(p + ".only 必须是非空数组，取值 " + " / ".join(EL_ONLY))
				elif tag != "shape.circle":
					errs.append(p + ".only 只用于 shape.circle")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			_F()._hw_shape_params(b, p, ctx, tag)   # 手写迁移段：basis / origin_off / aim_pad / face / dir / r_mult / ring
		"shape.orbit":
			_num(b, "n", p, ctx, true, 1.0, 12.0)
			if not (b.get("r", null) is String and b.r == "zone"):
				_num(b, "r", p, ctx, true)
			for k in ["speed", "hit_r", "kb", "cd"]:
				_num(b, k, p, ctx, false)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			_src(b, p, ctx, _val(b.get("mult", 0.0), ctx.base) > 0.0)
		"verb.heal":
			_num(b, "pct", p, ctx, true, 0.0, 0.2)
			_num(b, "every", p, ctx, false, 0.1)
			# 召唤物扩展段（§15.9）：scale / knight / on_over / text / sfx
			_num(b, "knight", p, ctx, false, 0.0, 1.0)
			_num(b, "text", p, ctx, false, 8.0, 40.0)
			if b.has("full") and not (b.full is bool):
				errs.append(p + ".full 只能是 true / false")
			if b.has("scale") and str(b.scale) != "op":
				errs.append(p + ".scale 只能是 op（× op_atk × 同伴倍率 × heal_out）")
			if b.has("on_over"):
				_list(b.on_over, p + ".on_over", "instant", ctx)
		"verb.lamp":
			if not (b.has("add") or b.has("per_sec") or b.has("loss_mult") or b.has("decay_mult") or b.has("radius_mult")):   # decay_mult / radius_mult：第 3 批（流明「沛霖」）
				errs.append(p + "：verb.lamp 要写 add / per_sec / loss_mult / decay_mult / radius_mult 之一")
			if b.has("add") and (b.has("per_sec") or b.has("loss_mult")):
				errs.append(p + "：verb.lamp 的 add（瞬时）不能和 per_sec / loss_mult（常驻）写在同一块")
			for k in ["add", "per_sec", "loss_mult"]:
				_num(b, k, p, ctx, false)
		"verb.buff_self":
			var st := str(b.get("stat", ""))
			var own: bool = ctx.get("stat_defs", {}) is Dictionary and ctx.stat_defs.has(st)   # 第 3 批：干员 JSON stat_defs 里的专属属性（作用域 op:<id>）
			if not (st in LOCAL_STATS or st in OP_STATS or own):
				errs.append("%s.stat「%s」只能是 %s 或本干员 stat_defs 里的专属属性" % [p, st, " / ".join(LOCAL_STATS + OP_STATS)])
			if not str(b.get("op", "")) in ["add", "mult"] and not (own and str(b.get("op", "")) == "flat"):
				errs.append(p + ".op 只能是 add / mult（专属属性还可 flat）")
			_num(b, "value", p, ctx, true)
		"verb.mode":
			if not (b.has("dmg_mult") or b.has("zone_mult") or b.has("interval_mult") or b.has("no_attack")):
				errs.append(p + "：verb.mode 至少写 dmg_mult / zone_mult / interval_mult / no_attack 之一")
			_num(b, "dmg_mult", p, ctx, false, 0.0, 20.0)
			_num(b, "zone_mult", p, ctx, false, 0.0)
			_num(b, "interval_mult", p, ctx, false, 0.05)
		"verb.sp_team":
			_num(b, "pct", p, ctx, true, 0.0, 1.0)
			_num(b, "motes", p, ctx, false, 0.0, 6.0)   # 第 4 批：金色技力粒子飞向每名队友（画面）；power：× 技能强度
		"aura.atk", "aura.aspd", "aura.skill_power", "aura.range":
			_num(b, "value", p, ctx, true)
			var sc := str(b.get("scope", ""))
			if not (sc in ["squad", "others", "in_zone", "leader", "self"] or ((sc.begins_with("faction:") or sc.begins_with("class:")) and sc.find(":") < sc.length() - 1)):
				errs.append("%s.scope「%s」只能是 squad / others / in_zone / leader / self / faction:<阵营> / class:<职业>" % [p, sc])
			if b.has("per"):
				var pe := str(b.per)
				if not ((pe.begins_with("faction:") or pe.begins_with("class:") or pe.begins_with("stack:")) and pe.find(":") < pe.length() - 1):
					errs.append("%s.per「%s」只能是 faction:<阵营> / class:<职业> / stack:<层数 key>" % [p, pe])
				_num(b, "cap", p, ctx, true, 1.0)
		"st.stun", "st.slow":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
		"st.slow_soft":
			_num(b, "pct", p, ctx, true, 0.0, 0.9)
			if str(b.get("scope", "in_zone")) != "in_zone":
				errs.append(p + ".scope：st.slow_soft 目前只支持 in_zone")
		"trig.passive":
			_list(b.get("do", []), p + ".do", "sustain", ctx)
		"trig.every_n":
			_num(b, "n", p, ctx, true, 1.0)
			_num(b, "delay", p, ctx, false, 0.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
			# 精英化段：replace = 这一次普攻整个换成 do（不再出普攻形状）；anim = 这一次起手播的帧条（sprites 里的键，缺图退回 attack）
			if b.has("replace") and not (b.replace is bool):
				errs.append(p + ".replace 只能是 true / false")
			if b.has("anim"):
				if not b.get("replace", false):
					errs.append(p + ".anim 只配 replace: true（换掉的那一次普攻播别的帧条）")
				elif not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
					errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
			if b.get("replace", false) and b.has("delay") and _val(b.delay, ctx.base) > 0.0:
				errs.append(p + "：replace 的 every_n 不写 delay（就在这一次出手帧执行）")
			# vis_anim = 追加段（非 replace）触发时只播的画面帧条（play_vis_anim，不占动作窗口、不改出手）；要列进 extra_sprites
			if b.has("vis_anim"):
				if b.get("replace", false):
					errs.append(p + ".vis_anim 只配非 replace 的追加段（replace 用 anim）")
				elif not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.vis_anim))):
					errs.append("%s.vis_anim「%s」不是 sprites 里的帧条键" % [p, str(b.vis_anim)])
		"trig.tick":
			_num(b, "every", p, ctx, true, 0.1)
			_list(b.get("do", []), p + ".do", "instant", ctx)
			if b.has("countdown") and not (b.countdown is bool):   # 手写迁移段：倒计时写法（生效当帧起算，到点重置为 every）
				errs.append(p + ".countdown 只能是 true / false")
		"trig.on_kill":
			if not str(b.get("filter", "any")) in ["any", "elite", "boss"]:
				errs.append(p + ".filter 只能是 any / elite / boss")
			_list(b.get("do", []), p + ".do", "instant", ctx)


static func _val(v, base: Dictionary) -> float:
	var ev := eval_expr(v, base)
	return ev[1] if ev[0] else 0.0


## 数值参数：必填 / 可选，范围夹紧（docs/61 §8 第 8 条）
static func _num(b: Dictionary, k: String, p: String, ctx: Dictionary, required: bool, lo := -INF, hi := INF) -> void:
	if not b.has(k):
		if required:
			ctx.errs.append("%s 缺参数 %s" % [p, k])
		return
	if b[k] is bool:
		return
	var ev := eval_expr(b[k], ctx.base)
	if not ev[0]:
		if not (b[k] is String and "$" in b[k]):   # $ 表达式的错误已在上面报过
			ctx.errs.append("%s.%s：%s" % [p, k, ev[2]])
		return
	if ev[1] < lo or ev[1] > hi:
		ctx.errs.append("%s.%s = %s 超出范围 [%s, %s]" % [p, k, str(ev[1]), str(lo), str(hi)])


static func _src(b: Dictionary, p: String, ctx: Dictionary, required: bool) -> void:
	var s := str(b.get("src", ""))
	if s == "":
		if required:
			ctx.errs.append(p + " 缺 src（伤害来源名）")
	elif not ctx.srcs.has(s):
		ctx.errs.append("%s.src「%s」没在 hit_sources 里登记" % [p, s])
