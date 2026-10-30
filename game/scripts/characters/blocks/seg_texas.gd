## 干员积木 · seg_texas（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/seg_angelina.gd"

const TX_AIMS := ["nearest", "densest", "leader_dir", "reverse"]

const TxArt = preload("res://scripts/art.gd")


## 校验（由 _block 转来；cond 与 $ 表达式已在 _block 里查过）
static func _tx_block(b: Dictionary, p: String, kind: String, tag: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	var instant: bool = tag in ["shape.dash_line", "verb.sp_secs", "verb.trail", "verb.fx_scatter", "verb.fx_rain", "verb.emit_path", "verb.rift_slash"]
	var is_trig: bool = tag.begins_with("trig.")
	match kind:
		"attack":
			if tag != "shape.dash_line":
				errs.append("%s：普攻只能是伤害形状，不能是「%s」" % [p, tag])
				return
		"trig":
			if not is_trig:
				errs.append("%s：这里要触发积木，不是「%s」" % [p, tag])
				return
		"on_hit":
			errs.append("%s：on_hit 里只能放 st.stun / st.slow，不能放「%s」" % [p, tag])
			return
		"instant":
			if not instant:
				errs.append("%s：触发器的 do 只执行一次，「%s」不是瞬时积木" % [p, tag])
				return
		"sustain":
			if instant or is_trig:
				errs.append("%s：常驻列表里只能放常驻积木，「%s」不是" % [p, tag])
				return
		"skill":
			if is_trig:
				errs.append("%s：技能 do 里不能放「%s」" % [p, tag])
				return
	match tag:
		"shape.dash_line":
			_num(b, "r", p, ctx, true, 10.0, 600.0)
			_num(b, "w", p, ctx, true, 4.0, 200.0)
			_num(b, "t", p, ctx, false, 0.02, 1.0)
			_num(b, "hold", p, ctx, false, 0.0, 1.0)
			_num(b, "mult", p, ctx, false, -INF, 20.0)
			if not str(b.get("aim", "nearest")) in TX_AIMS:
				errs.append("%s.aim 只能是 %s" % [p, " / ".join(TX_AIMS)])
			if b.has("strip") and not (b.strip is String and (b.strip.begins_with("fx_") or b.strip.begins_with("proj_"))):
				errs.append(p + ".strip 必须是帧条名（fx_* / proj_*）")
			if kind == "attack" and str(b.get("aim", "nearest")) != "nearest":
				errs.append(p + ".aim：普攻冲刺只能朝最近敌人（nearest）")
			_num(b, "aim_r", p, ctx, false, 10.0, 1200.0)   # 找目标的半径（缺省 冲刺长度 × 1.3）
			_num(b, "min_d", p, ctx, false, 0.0, 1200.0)    # aim nearest：最近的敌人比这近就不冲（够得着了）
			if b.has("need_target") and not b.need_target is bool:
				errs.append(p + ".need_target 应是 true / false（aim nearest：aim_r 内没有敌人就不冲）")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
		"verb.sp_secs":
			_num(b, "seconds", p, ctx, true, 0.0, 10.0)
		"verb.emit_path":
			_num(b, "len", p, ctx, true, 10.0, 600.0)
			_num(b, "w", p, ctx, false, 4.0, 200.0)
			_src(b, p, ctx, true)
		"verb.dash_mod":
			if not (b.has("len_add") or b.has("len_mult") or b.has("w_add") or b.has("w_mult") or b.has("on_hit")):
				errs.append(p + "：verb.dash_mod 至少写 len_add / len_mult / w_add / w_mult / on_hit 之一")
			for k in ["len_add", "w_add"]:
				_num(b, k, p, ctx, false, -0.9, 3.0)
			for k in ["len_mult", "w_mult"]:
				_num(b, k, p, ctx, false, 0.1, 4.0)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)   # 精英化段：生效期间每次冲刺扫到的敌人追加的状态（德克萨斯钉剑 first_only）
		"verb.trail":
			_num(b, "life", p, ctx, true, 0.05, 5.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "line_w", p, ctx, false, 0.0, 1.0)
			if b.has("line_col") and not (b.line_col is Array and b.line_col.size() in [3, 4]):
				errs.append(p + ".line_col 要写 [r, g, b] 或 [r, g, b, a]")
			_src(b, p, ctx, true)
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			if b.has("on_expire"):   # 精英化段：残像消散时执行（do 里的 center: path 沿这道残像）
				_list(b.on_expire, p + ".on_expire", "instant", ctx)
		"verb.fx_scatter":
			if str(b.get("strip", "")) == "":
				errs.append(p + " 缺 strip（帧条名）")
			_num(b, "n", p, ctx, true, 1.0, 32.0)
			_num(b, "r", p, ctx, true, 0.0, 600.0)
			_num(b, "stagger", p, ctx, false, 0.0, 2.0)
			if not str(b.get("center", "self")) in ["self", "target"]:
				errs.append(p + ".center 只能是 self / target")
		"verb.rift_slash":
			_num(b, "n", p, ctx, true, 1.0, 12.0)
			_num(b, "r", p, ctx, true, 30.0, 800.0)
			_num(b, "half", p, ctx, false, 0.2, 3.2)
			_num(b, "len", p, ctx, true, 20.0, 600.0)
			_num(b, "gap", p, ctx, true, 0.03, 1.0)
			_num(b, "w", p, ctx, false, 4.0, 200.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "stun", p, ctx, false, 0.0, 5.0)
			_num(b, "scar", p, ctx, false, 0.1, 5.0)
			_num(b, "lead", p, ctx, false, 0.0, 1.0)
			_num(b, "hold", p, ctx, false, 0.0, 1.0)
			_num(b, "pose", p, ctx, false, 0.0, 1.0)
			_num(b, "sweep", p, ctx, false, 0.01, 1.0)
			_num(b, "scar_ext", p, ctx, false, 0.0, 3.0)
			_num(b, "scar_extra", p, ctx, false, 0.0, 6.0)
			_src(b, p, ctx, true)
		"verb.fx_rain":
			_tx_rain_validate(b, p, ctx)
		"trig.on_dash_end":
			_num(b, "min_hits", p, ctx, false, 0.0, 99.0)
			_num(b, "delay", p, ctx, false, 0.0, 5.0)
			if b.has("src"):
				_src(b, p, ctx, true)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_leader_dash":
			_num(b, "cd", p, ctx, false, 0.0, 60.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"trig.on_skill_start", "trig.on_skill_end":
			_num(b, "skill", p, ctx, true, 0.0, 2.0)
			if b.has("at"):   # 召唤物扩展段（§15.9）：do 里 center: target 落在这个点；on_skill_end 带 at 时也能写 delay
				var atv := str(b.at)
				if not (atv in ["self", "leader"] or (atv.begins_with("summon:") and ctx.summons is Dictionary and ctx.summons.has(atv.substr(7)))):
					errs.append(p + ".at 只能是 self / leader / summon:<blocks.summons 里的种类>")
			if tag == "trig.on_skill_start" or b.has("at"):
				_num(b, "delay", p, ctx, false, 0.0, 5.0)
			elif b.has("delay"):
				errs.append(p + "：trig.on_skill_end 不写 at 时不支持 delay")
			_list(b.get("do", []), p + ".do", "instant", ctx)


## 冲刺长度（世界像素）：r × op_range × 本干员冲刺长度倍率
static func tx_len(o, b: Dictionary) -> float:
	return float(b.get("r", 0.0)) * o.stat(&"op_range") * float(o.tx.get("len", 1.0))


## 普攻起手点（data_operator.update 转来）：最近敌人在冲刺长度 × 1.3 内就起手（按住瞄准 A 方向类：沿瞄准方向照冲）
static func tx_attack_point(o, b: Dictionary) -> Vector2:
	var r: float = tx_len(o, b)
	return o.atk_point(o.nearest_enemies(1, r * 1.3, o.pos), r)


## 起冲（瞬时）：正在冲的那次先结算掉，再按 aim 定方向。dmg 已含 mult / 局部伤害倍率 / 技能强度（exec_shape 算好）
static func tx_dash_start(o, b: Dictionary, dmg: float) -> Array:
	var g = o.g
	if o.pos == Vector2.INF:
		return []
	var aim: String = str(b.get("aim", "nearest"))
	var len: float = tx_len(o, b)
	var pd := Vector2.INF
	if aim == "densest":
		# 朝敌群冲：附近没有敌人就不冲（德克萨斯天赋自动冲刺 / 剑雨滂沱；她当主控时不把主控带去空地）
		pd = _tx_densest(o, len * 1.6)
		if pd == Vector2.INF:
			return []
	var aim_r: float = float(b.aim_r) * o.stat(&"op_range") if b.has("aim_r") else len * 1.3
	if aim == "nearest" and (b.get("need_target", false) or b.has("min_d")):
		# 队友短突进（德克萨斯，10-23）：aim_r 内没有敌人、或最近的敌人已经比 min_d 近（够得着了）就不冲
		var ts0: Array = o.nearest_enemies(1, aim_r, o.pos)
		if ts0.is_empty() or ts0[0].pos.distance_to(o.pos) < float(b.get("min_d", 0.0)):
			return []
	if o.tx.has("dash"):
		_tx_dash_end(o)
	var dir := Vector2.ZERO
	match aim:
		"nearest":
			var ts: Array = o.nearest_enemies(1, aim_r, o.pos)
			var ang: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
			dir = Vector2.from_angle(o.atk_angle(ang))
		"densest":
			dir = (pd - o.pos).normalized() if pd.distance_to(o.pos) > 1.0 else Vector2(o.face, 0.0)
		"leader_dir":
			dir = g.dash_dir if g.dash_dir != Vector2.ZERO else Vector2(g.facing, 0.0)
		"reverse":
			dir = -Vector2(o.tx.get("last_dir", Vector2(o.face, 0.0)))
	if dir == Vector2.ZERO:
		dir = Vector2(o.face, 0.0)
	dir = dir.normalized()
	if absf(dir.x) > 0.1:
		o._set_face(signf(dir.x), true)
	var ride: bool = o.is_leader and aim == "leader_dir"   # 主控自己按的冲刺：位移交给主控，冲刺只负责扫
	var d := {"from": o.pos, "to": o.pos + dir * len, "dir": dir, "t": 0.0, "dur": float(b.get("t", 0.18)),
		"attack_pose": o.attack_phased and o.act_kind == "attack" and o.attack_t > 0.0,
		"hold": 0.0 if o.is_leader else float(b.get("hold", 0.0)), "ride": ride, "last": o.pos, "hit": {},
		"dmg": dmg, "w": float(b.get("w", 40.0)) * float(o.tx.get("w", 1.0)), "b": b, "src": str(b.get("src", ""))}
	o.tx["dash"] = d
	if b.has("sfx"):
		o._sfx_op(str(b.sfx))
	if b.has("strip"):
		var fr: Array = g.V6_FRAMES.get(str(b.strip), [4, 20.0])
		o.fx({"kind": "tx_strip", "strip": str(b.strip), "frames": int(fr[0]), "fps": float(fr[1]), "pos": d.to, "ang": dir.angle(), "sx": len / 128.0,
			"anchor": Vector2(63.0 / 64.0, 0.5), "life": float(fr[0]) / float(fr[1]) + d.dur * 0.5, "delay": d.dur * 0.5})
	return []


## 敌群最密处：半径 rr 内最近的 24 个敌人里，80 像素内邻居最多的那个（并列取近的）；没有敌人返回 INF。
## 队友在「清杂优先」（docs/114 §13）下只数杂兵（非 Boss / 精英 / 部件），没有杂兵时照旧数全部
static func _tx_densest(o, rr: float) -> Vector2:
	var cand: Array = o.g.enemies_sys.nearest(24, rr, o.pos)
	var hit: Array = cand.filter(func(e): return o.hittable(e))
	if not hit.is_empty():
		cand = hit   # 打不动的（无敌 Boss 等，op_api.hittable）不算进敌群，只剩它们时照旧
	if o.prio_mode() == 1:
		var mobs: Array = cand.filter(func(e): return o.prio_rank(e, 1) == 0)
		if not mobs.is_empty():
			cand = mobs
	var best := Vector2.INF
	var bn := -1
	for e in cand:
		var n := 0
		for f in cand:
			if e.pos.distance_squared_to(f.pos) <= 6400.0:
				n += 1
		if n > bn:
			bn = n
			best = e.pos
	return best


## 路径事件（10-23）：把一条有起点终点的路径当作「src 这次冲刺结束了、扫到 0 名」，触发匹配的 trig.on_dash_end（德克萨斯精二余像挂在短剑气上：
## 残像沿剑气路径、消散落剑；min_hits > 0 的块不触发）。ctx 同 _tx_dash_end
static func tx_emit_path(o, src: String, from: Vector2, to: Vector2, w: float) -> void:
	var tx: Dictionary = o.tx
	var dir: Vector2 = (to - from).normalized()
	var ctx := {"from": from, "to": to, "dir": dir, "n": 0, "src": src, "w": w}
	tx["last_to"] = to
	tx["last_dir"] = dir
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_dash_end" or not cond_true(o, t.get("cond", _ED)):
			continue
		if t.has("src") and str(t.src) != src:
			continue
		if int(t.get("min_hits", 0)) > 0:
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			var q: Array = tx.get("queue", [])
			q.append({"t": dl, "t0": dl, "do": t.get("do", []), "ctx": ctx})
			tx["queue"] = q
		else:
			tx["ctx"] = ctx
			o._exec_list(t.get("do", []), ctx.to)


## 每帧（data_operator.update 在常驻积木之后调）：主控冲刺 / 技能结束的触发、延迟队列、残像、冲刺推进与扫线。
## 返回 true = 正在冲刺（这一帧不起手普攻 / 技能）
static func tx_update(o, dt: float) -> bool:
	var g = o.g
	var tx: Dictionary = o.tx
	tx_rift_update(o, dt)   # 次元斩：闪现序列 / 刀痕消散（没有时立即返回）
	if tx.has("rift"):   # 一轮次元斩还没斩完：不起下一次手（一轮可能比普攻间隔长）
		return true
	# 主控冲刺上升沿
	var ld: float = float(g.dash_t)
	if ld > 0.0 and float(tx.get("prev_ld", 0.0)) <= 0.0 and g.demo_op == "":
		for t in o._trigs():
			if str(t.get("_tag", "")) != "trig.on_leader_dash" or not cond_true(o, t.get("cond", _ED)):
				continue
			var k: String = "ld%d" % int(t.get("_uid", 0))
			if g.t < float(tx.get(k, -99.0)):
				continue
			tx[k] = g.t + float(t.get("cd", 0.0))
			o._exec_list(t.get("do", []))
	tx["prev_ld"] = ld
	# 技能持续结束
	var prev: Array = tx.get("prev_s", [0.0, 0.0, 0.0])
	for i in 3:
		if prev[i] > 0.0 and o.s_t[i] <= 0.0 and not o.B.get("skills", [{}, {}, {}])[i].has("attack_phases") and not o.SkillLifecycle.owns(o, i):
			for t in o._trigs():
				if str(t.get("_tag", "")) == "trig.on_skill_end" and not t.has("at") and int(t.get("skill", -1)) == i and cond_true(o, t.get("cond", _ED)):   # 带 at 的在 mf_tick（帧开头）
					o._exec_list(t.get("do", []), tx.get("last_to", o.pos))
	tx["prev_s"] = o.s_t.duplicate()
	# 延迟队列（on_dash_end / on_skill_start 的 delay）
	var q: Array = tx.get("queue", [])
	if not q.is_empty():
		var due: Array = []
		for it in q:
			it.t -= dt
			if it.t <= 0.0:
				due.append(it)
		tx["queue"] = q.filter(func(it): return it.t > 0.0)
		for it in due:
			tx["ctx"] = it.ctx
			o._exec_list(it.do, it.ctx.get("to", Vector2.INF))
	# 残像
	var trails: Array = tx.get("trails", [])
	if not trails.is_empty():
		var gone: Array = []
		for tr in trails:
			tr.life -= dt
			_tx_sweep(o, tr.from, tr.to, tr.w, tr.hit, tr.dmg, tr.b)
			if tr.life <= 0.0 and tr.b.has("on_expire"):
				gone.append(tr)
		tx["trails"] = trails.filter(func(tr): return tr.life > 0.0)
		for tr in gone:   # 精英化段：残像消散 → on_expire（路径 = 这道残像）
			tx["ctx"] = {"from": tr.from, "to": tr.to, "dir": (tr.to - tr.from).normalized(), "w": tr.w, "n": 0, "src": ""}
			o._exec_list(tr.b.on_expire, tr.to)
	# 冲刺
	if not tx.has("dash") or o.pos == Vector2.INF:
		return false
	var d: Dictionary = tx.dash
	d.t += dt
	var k2: float = clampf(d.t / maxf(0.01, d.dur), 0.0, 1.0)
	if not d.ride:
		o.pos = (d.from as Vector2).lerp(d.to, 1.0 - (1.0 - k2) * (1.0 - k2))   # 先快后慢
	if d.t <= d.dur + dt * 0.5:
		_tx_sweep(o, d.last, o.pos, d.w, d.hit, d.dmg, d.b, true)
		d.last = o.pos
	if d.t >= d.dur + d.hold:
		_tx_dash_end(o)
		return false
	return true


## 扫一段线段：线段两侧 w/2（+ 敌人半径）内、hit 里没有的敌人各吃一次 dmg（对精英 / Boss 乘 vs_elite）与 on_hit 状态
static func _tx_sweep(o, a: Vector2, c: Vector2, w: float, hit: Dictionary, dmg: float, b: Dictionary, dash := false) -> void:
	var g = o.g
	var seg: Vector2 = c - a
	var L: float = seg.length()
	var mid: Vector2 = (a + c) * 0.5
	var src: String = str(b.get("src", ""))
	var tags: Array = b.get("tags", [])
	var ve: float = o.vs_elite()
	for j in o.query_ids(mid, L * 0.5 + w * 0.5 + 40.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or hit.has(e.id):
			continue
		var q: Vector2 = a if L < 0.5 else a + seg * clampf((e.pos - a).dot(seg) / (L * L), 0.0, 1.0)
		if e.pos.distance_to(q) > w * 0.5 + float(e.r):
			continue
		hit[e.id] = true
		o.log_hit(src, tags)
		o.deal_damage(e, dmg * (ve if e.elite or e.boss else 1.0))
		for s in b.get("on_hit", _EA):
			apply_status(o, e, s)
		if dash:   # 精英化段：verb.dash_mod 的 on_hit（idx = 这次冲刺扫到的第几个，first_only 只给第 0 个）
			for s in o.tx.get("on_hit", _EA):
				apply_status(o, e, s, Vector2.INF, -1.0, 0.0, hit.size() - 1)
		o.fx({"kind": "shard", "pos": e.pos + Vector2(0, -float(e.r) * 0.5), "ang": seg.angle() + 0.5, "sz": 7.0, "life": 0.16, "col": Color(1.0, 0.75, 0.4)})


## 一次冲刺结束：记下终点与方向，按 on_dash_end 触发
static func _tx_dash_end(o) -> void:
	var tx: Dictionary = o.tx
	var d: Dictionary = tx.dash
	tx.erase("dash")
	var n: int = d.hit.size()
	tx["last_to"] = o.pos if d.ride else d.to
	tx["last_dir"] = d.dir
	var ctx := {"from": d.from, "to": tx.last_to, "dir": d.dir, "n": n, "src": d.src, "w": d.w}
	if n > 0:
		o._sfx_op("hit")
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_dash_end" or not cond_true(o, t.get("cond", _ED)):
			continue
		if t.has("src") and str(t.src) != d.src:
			continue
		if n < int(t.get("min_hits", 0)):
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			var q: Array = tx.get("queue", [])
			q.append({"t": dl, "t0": dl, "do": t.get("do", []), "ctx": ctx})
			tx["queue"] = q
		else:
			tx["ctx"] = ctx
			o._exec_list(t.get("do", []), ctx.to)


## 原生动作覆盖层的信号（native_motion.gd，docs/108 §3.5；只读本段状态）：
##   dash.<种类>  正在冲刺，进度 = 已冲时间 /（冲刺 + 停顿）；reverse = 回马剑，skill = 技能冲刺，attack = 当前阶段普攻，其余 basic
##   wait.reverse 冲完到反冲之间的延迟（on_dash_end 的 delay），进度 0–1
static func tx_native_signals(o, out: Dictionary) -> void:
	var tx: Dictionary = o.tx
	if tx.has("dash"):
		var d: Dictionary = tx.dash
		var b: Dictionary = d.b
		var kind := "basic"
		if str(b.get("aim", "")) == "reverse":
			kind = "reverse"
		elif (b.get("tags", _EA) as Array).has("skill"):
			kind = "skill"
		elif d.get("attack_pose", false):
			kind = "attack"
		out["dash." + kind] = clampf(float(d.t) / maxf(0.01, float(d.dur) + float(d.hold)), 0.0, 1.0)
		return
	for it in tx.get("queue", _EA):
		for blk in it.do:
			if blk is Dictionary and str(blk.get("_tag", "")) == "shape.dash_line" and str(blk.get("aim", "")) == "reverse":
				out["wait.reverse"] = clampf(1.0 - float(it.t) / maxf(0.01, float(it.get("t0", it.t))), 0.0, 1.0)
				return


## 技能出手（data_operator._release_skill 转来）：trig.on_skill_start
static func tx_skill_start(o, i: int) -> void:
	for t in o._trigs():
		if str(t.get("_tag", "")) != "trig.on_skill_start" or int(t.get("skill", -1)) != i or not cond_true(o, t.get("cond", _ED)):
			continue
		if t.has("at"):   # 召唤物扩展段：点在触发这一刻取，delay 进本干员延迟队列
			mf_fire_at(o, t, mf_at_point(o, str(t.at)))
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			var q: Array = o.tx.get("queue", [])
			q.append({"t": dl, "do": t.get("do", []), "ctx": {}})
			o.tx["queue"] = q
		else:
			o._exec_list(t.get("do", []))


## 瞬时积木（data_operator._exec_list 的缺省分支转来）
static func tx_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.dash_line":
			exec_shape(o, b, at)
		"verb.sp_secs":
			var sec: float = float(b.seconds)
			for m in o.g.squad.ops:
				if m == o and b.get("exclude_self", true):
					continue
				for i in 3:
					if m.skill_unlocked(i) and m.sp_need(i) > 0.0 and not m.perm[i]:
						m.sp[i] = minf(m.sp_need(i), m.sp[i] + sec)
		"verb.trail":
			var c: Dictionary = o.tx.get("ctx", {})
			if c.has("from"):
				var tr := {"from": c.from, "to": c.to, "w": float(c.w), "life": float(b.life), "hit": {}, "b": b,
					"dmg": o.base(str(b.get("atk_key", "atk")), 0.0) * float(b.mult) * float(o.loc.dmg) * o._dmg_bonus()}
				var trails: Array = o.tx.get("trails", [])
				trails.append(tr)
				o.tx["trails"] = trails
				# 地面残像光带（纯画面）：line_w = 宽度占冲刺宽的比例（0 = 不画），line_col = [r, g, b, a]（缺省干员色）
				var lw: float = float(b.get("line_w", 0.35))
				if lw > 0.0:
					var lc = b.get("line_col", null)
					o.fx({"kind": "line", "pos": c.from, "to": c.to, "w": float(c.w) * lw, "life": float(b.life),
						"col": Color(float(lc[0]), float(lc[1]), float(lc[2]), float(lc[3]) if lc.size() > 3 else 1.0) if lc is Array and lc.size() >= 3 else o.col(), "floor": true})
		"verb.emit_path":   # 把「自身朝最近敌人（没有就朝向 / 手动指向）、长 len」的路径当作一次冲刺结束，触发 src 匹配的 trig.on_dash_end（精二余像挂在疾刃三连上，10-23）
			var elen: float = float(b.len) * o.stat(&"op_range")
			var ets: Array = o.nearest_enemies(1, elen + 30.0, o.pos)
			var eang: float = (ets[0].pos - o.pos).angle() if not ets.is_empty() else o.facing_angle()
			if o.held_aim() and o.atk_aim != Vector2.ZERO:
				eang = o.atk_aim.angle()
			tx_emit_path(o, str(b.get("src", "")), o.pos, o.pos + Vector2.from_angle(eang) * elen, float(b.get("w", 44.0)))
		"verb.fx_scatter":
			var cc: Vector2 = o.pos if str(b.get("center", "self")) == "self" or at == Vector2.INF else at
			var n: int = int(b.n)
			var r: float = float(b.r) * o.stat(&"op_range")
			var fr: Array = o.g.V6_FRAMES.get(str(b.strip), [6, 20.0])
			var life0: float = float(fr[0]) / float(fr[1])
			var st: float = float(b.get("stagger", 0.25))
			var sd: int = int(o.tx.get("fxn", 0))
			o.tx["fxn"] = sd + 1
			for k in n:
				# 画面用的低差异序列（黄金角），不碰 g.rng
				var u: float = fposmod((sd * n + k) * 0.618034, 1.0)
				var rad: float = r * sqrt((k + 0.5) / float(n))
				var p: Vector2 = cc + Vector2.from_angle(u * TAU + k * 2.39996) * rad * Vector2(1.0, 0.55)
				var dl: float = st * fposmod(k * 0.381966 + u, 1.0)
				o.fx({"kind": "tx_strip", "strip": str(b.strip), "frames": int(fr[0]), "fps": float(fr[1]), "pos": p, "anchor": Vector2(0.5, 30.0 / 32.0),
					"life": life0 + dl, "delay": dl})
		"verb.rift_slash":
			tx_rift_start(o, b)
		"verb.fx_rain":
			tx_rain(o, b, at)


## 常驻积木（data_operator._sustain 第二遍末尾转来）：冲刺长度 / 宽度倍率写进 tx，主控属性修正追加进 want（随 g.stats 整组重建）
static func tx_sustain(o, act: Array, want: Array) -> void:
	var la := 0.0
	var lm := 1.0
	var wa := 0.0
	var wm := 1.0
	var oh: Array = []
	for b in (act if has_tag(o, "verb.dash_mod") else _EA):   # B6 ④：没有 dash_mod 的干员不逐块匹配（下面的写回照旧）
		match str(b.get("_tag", "")):
			"verb.dash_mod":
				la += float(b.get("len_add", 0.0))
				lm *= float(b.get("len_mult", 1.0))
				wa += float(b.get("w_add", 0.0))
				wm *= float(b.get("w_mult", 1.0))
				oh.append_array(b.get("on_hit", []))
	o.tx["len"] = (1.0 + la) * lm
	o.tx["w"] = (1.0 + wa) * wm
	if not oh.is_empty() or o.tx.has("on_hit"):   # 精英化段：冲刺追加状态（没有时不写这个键）
		o.tx["on_hit"] = oh


## 帧条粒子（data_operator._draw_pfx 转来）：kind = tx_strip（与通用 fx 的 strip 粒子分开）；delay 秒后起播，sx 横向缩放（冲刺剑光拉到冲刺长度）
static func tx_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if str(f.get("kind", "")) != "tx_strip":
		return false
	var el: float = float(f.max) - float(f.life) - float(f.get("delay", 0.0))
	if el < 0.0:
		return true
	var tx: Texture2D = o._fx_tex(str(f.strip))
	if tx == null:
		return true
	var frames: int = int(f.frames)
	var fr: int = mini(frames - 1, int(el * float(f.fps)))
	var fw: float = float(tx.get_width() / frames)
	var fh: float = float(tx.get_height())
	var k: float = o.g.PX / TxArt.hires_of(tx)
	var al: float = o.g.world.fx_dim if a > 0.0 else 0.0
	o.cv.draw_set_transform((f.pos as Vector2).round(), float(f.get("ang", 0.0)), Vector2(k * float(f.get("sx", 1.0)), k))
	o.cv.draw_texture_rect_region(tx, Rect2(-Vector2(fw, fh) * (f.anchor as Vector2), Vector2(fw, fh)), Rect2(fw * fr, 0, fw, fh), Color(1, 1, 1, al))
	o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## ---------------------------------------------------------------- verb.fx_rain（10-12 加，docs/61 §13.5；德克萨斯剑雨首用，docs/70）
## 瞬时、只有画面：半径 r 内按面积密度撒 n 柄剑，错开 stagger 秒、各自从 fall 像素高处 fall_t 秒加速落下（带 streak 道残影），
## 落地前 lead 秒地面出现预兆标记（mark 帧条前 mark_frames 帧），落地播冲击帧条（hit）、剑身插地停留 stick 秒、地面焦痕（mark 后半）停留 scorch 秒；
## finale：最后一柄落地后在中心再来一次放大的冲击 + 一圈亮环。落点：on_enemies 比例先落在半径内的敌人身上（近的先、第一波），其余黄金角铺满透视椭圆。
## 随机只用 g.vrng（画面），敌人位置只读（query_ids），不碰 g.rng / 玩法状态；伤害照旧由同一 do 里的 shape 瞬时结算（第一波 fall_t ≈ 0.1 秒内落地）。
## 一次施放 = 两个 pfx 粒子（kind tx_rain：上层剑 + 冲击，地面层标记 + 焦痕 + 终结亮环），共享同一份剑列表；同一张贴图连着画（合批）。
const TX_RAIN_KEYS := ["verb", "cond", "_doc", "strip", "hit", "mark", "r", "center", "density", "n", "n_min", "n_max", "stagger", "fall", "fall_t", "lead",
	"stick", "scorch", "scale", "scale_j", "tilt", "slant", "streak", "on_enemies", "alpha", "fall_frames", "mark_frames", "hit_scale", "mark_scale",
	"anchor", "hit_anchor", "mark_anchor", "layer", "finale",
	"along", "step", "if_tex"]   # 精英化段：along: path = 沿上一次冲刺路径每 step 一柄、按顺序 stagger 间隔落下；if_tex 同 fx 条目（缺图回退）

const TX_RAIN_FIN_KEYS := ["scale", "ring", "t", "col"]


static func _tx_rain_validate(b: Dictionary, p: String, ctx: Dictionary) -> void:
	var errs: Array = ctx.errs
	for k in b:
		if not str(k).begins_with("_") and not str(k) in TX_RAIN_KEYS:
			errs.append("%s：verb.fx_rain 没有参数「%s」" % [p, str(k)])
	for k in ["strip", "hit", "mark"]:
		if b.has(k) or k == "strip":
			var s = b.get(k, "")
			if not (s is String and s.begins_with("fx_")):
				errs.append("%s.%s 必须是帧条名（fx_*）" % [p, k])
	var along := str(b.get("along", "")) == "path"
	if b.has("along") and not along:
		errs.append(p + ".along 只能是 path（沿上一次冲刺路径）")
	if along:
		_num(b, "step", p, ctx, true, 8.0, 400.0)
	elif not (b.has("density") or b.has("n")):
		errs.append(p + "：verb.fx_rain 要写 density（每 1 万平方像素几柄）或 n（固定柄数）")
	if b.has("if_tex"):
		var it := str(b.if_tex).trim_prefix("!")
		if not it.begins_with("fx_"):
			errs.append(p + ".if_tex 必须是帧条名（fx_*），前面加 ! 表示缺这条贴图时才画")
	_num(b, "r", p, ctx, not along, 0.0, 600.0)
	_num(b, "density", p, ctx, false, 0.05, 20.0)
	for k in ["n", "n_min", "n_max"]:
		_num(b, k, p, ctx, false, 1.0, 64.0)
	_num(b, "stagger", p, ctx, false, 0.0, 2.0)
	_num(b, "fall", p, ctx, false, 0.0, 600.0)
	_num(b, "fall_t", p, ctx, false, 0.02, 1.0)
	_num(b, "lead", p, ctx, false, 0.0, 1.0)
	_num(b, "stick", p, ctx, false, 0.0, 3.0)
	_num(b, "scorch", p, ctx, false, 0.0, 5.0)
	_num(b, "scale", p, ctx, false, 0.1, 4.0)
	_num(b, "scale_j", p, ctx, false, 0.0, 0.9)
	_num(b, "tilt", p, ctx, false, 0.0, 45.0)
	_num(b, "slant", p, ctx, false, -60.0, 60.0)
	_num(b, "streak", p, ctx, false, 0.0, 4.0)
	_num(b, "on_enemies", p, ctx, false, 0.0, 1.0)
	_num(b, "alpha", p, ctx, false, 0.05, 1.0)
	_num(b, "fall_frames", p, ctx, false, 1.0, 32.0)
	_num(b, "mark_frames", p, ctx, false, 0.0, 32.0)
	_num(b, "hit_scale", p, ctx, false, 0.1, 8.0)
	_num(b, "mark_scale", p, ctx, false, 0.1, 8.0)
	for k in ["anchor", "hit_anchor", "mark_anchor"]:
		if b.has(k) and not (b[k] is Array and b[k].size() == 2 and (b[k][0] is float or b[k][0] is int) and (b[k][1] is float or b[k][1] is int)):
			errs.append("%s.%s 要写 [x, y]（1x 帧内像素）" % [p, k])
	if not str(b.get("layer", "over")) in ["over", "add"]:
		errs.append(p + ".layer 只能是 over / add")
	if not str(b.get("center", "self")) in ["self", "target"]:
		errs.append(p + ".center 只能是 self / target")
	if b.has("n_min") and b.has("n_max") and b.n_min is float and b.n_max is float and float(b.n_min) > float(b.n_max):
		errs.append(p + "：n_min 大于 n_max")
	if b.has("finale"):
		if not b.finale is Dictionary:
			errs.append(p + ".finale 要写 {scale, ring, t, col}")
		else:
			for k in b.finale:
				if not str(k) in TX_RAIN_FIN_KEYS:
					errs.append("%s.finale 没有参数「%s」" % [p, str(k)])
			_num(b.finale, "scale", p + ".finale", ctx, false, 0.5, 3.0)
			_num(b.finale, "ring", p + ".finale", ctx, false, 0.0, 3.0)
			_num(b.finale, "t", p + ".finale", ctx, false, 0.0, 3.0)
			if b.finale.has("col") and not (b.finale.col is Array and b.finale.col.size() in [3, 4]):
				errs.append(p + ".finale.col 要写 [r, g, b] 或 [r, g, b, a]")


## 帧条规格：[贴图, 帧数, fps, 每帧宽（贴图像素）, 帧高, 锚点（贴图像素）, 1x 像素 → 贴图像素倍数]；缺图返回空
static func _tx_rain_spec(o, name: String, anchor, def_anchor: Vector2) -> Array:
	if name == "":
		return []
	var t: Texture2D = o._fx_tex(name)
	if t == null:
		return []
	var fr: Array = o.g.V6_FRAMES.get(name, [1, 12.0])
	var n: int = maxi(1, int(fr[0]))
	var hi: float = TxArt.hires_of(t)
	var fw: float = float(t.get_width() / n)
	var fh: float = float(t.get_height())
	var an: Vector2 = Vector2(float(anchor[0]), float(anchor[1])) * hi if anchor is Array else Vector2(fw * def_anchor.x, fh - def_anchor.y * hi)
	return [t, n, float(fr[1]), fw, fh, an, hi]


static func tx_rain(o, b: Dictionary, at: Vector2) -> void:
	var g = o.g
	if b.has("if_tex"):   # 精英化段：按贴图有无取舍（同 fx 条目的 if_tex）
		var it: String = str(b.if_tex)
		var neg: bool = it.begins_with("!")
		if (o._fx_tex(it.substr(1) if neg else it) != null) == neg:
			return
	if str(b.get("along", "")) == "path":
		_tx_rain_path(o, b)
		return
	var cc: Vector2 = o.pos if str(b.get("center", "self")) == "self" or at == Vector2.INF else at
	if cc == Vector2.INF:
		return
	var bs: Array = _tx_rain_spec(o, str(b.strip), b.get("anchor"), Vector2(0.5, 2.0))
	if bs.is_empty():
		return   # 缺剑的帧条：整条跳过（伤害形状自己的扩散环照旧）
	var r: float = float(b.r) * o.stat(&"op_range")
	var n: int
	if b.has("density"):
		n = clampi(int(round(float(b.density) * PI * r * r / 10000.0)), int(b.get("n_min", 6)), int(b.get("n_max", 48)))
	else:
		n = int(b.n)
	var cfg = g.get_node_or_null("/root/Cfg")   # 不直接写 Cfg：核心契约测试（-s 脚本模式）没有自动加载
	n = maxi(1, int(round(n * (float(cfg.fx_density()) if cfg != null else 1.0))))   # 低画质减半（同 vfx.sparks）
	var rng: RandomNumberGenerator = g.vrng
	var st: float = float(b.get("stagger", 0.4))
	var ft: float = float(b.get("fall_t", 0.1))
	var sc: float = float(b.get("scale", 1.0))
	var sj: float = float(b.get("scale_j", 0.15))
	var tilt: float = deg_to_rad(float(b.get("tilt", 5.0)))
	var slant: float = deg_to_rad(float(b.get("slant", 0.0)))
	# 第一波：半径内的敌人（含这一下刚打死的），近的先
	var pts: Array = []
	var ne: int = int(round(n * float(b.get("on_enemies", 0.0))))
	if ne > 0:
		var cand: Array = []
		for j in o.query_ids(cc, r):
			var ep: Vector2 = g.enemies[j].pos
			if ep.distance_squared_to(cc) <= r * r:
				cand.append(ep)
		cand.sort_custom(func(p1, p2): return p1.distance_squared_to(cc) < p2.distance_squared_to(cc))
		for k in mini(ne, cand.size()):
			pts.append(cand[k] + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-2.0, 2.0)))
	var first: int = pts.size()
	var m: int = n - first
	var u0: float = rng.randf()
	for k in m:
		var rad: float = r * sqrt((k + rng.randf_range(0.2, 0.8)) / float(m))
		var ang: float = u0 * TAU + k * 2.39996 + rng.randf_range(-0.3, 0.3)
		pts.append(cc + Vector2.from_angle(ang) * rad * Vector2(1.0, 0.55))
	var bl: Array = []
	var tmax := 0.0
	for k in pts.size():
		# 敌人身上的在前四分之一时间里落，其余在 stagger 里均匀铺开（抖动），第一柄贴着 0 秒
		var d: float = rng.randf_range(0.0, st * 0.25) if k < first else st * (float(k - first) + rng.randf()) / float(maxi(1, m))
		if k == 0:
			d = 0.0
		var a: float = slant + rng.randf_range(-tilt, tilt)
		bl.append({"p": pts[k], "d": d, "s": sc * (1.0 + rng.randf_range(-sj, sj)), "a": a, "fl": rng.randf() < 0.5})
		tmax = maxf(tmax, d)
	_tx_rain_emit(o, b, cc, r, bl, tmax, bs, ft)


## 精英化段：verb.fx_rain along: path——沿上一次冲刺（或残像）路径每 step 一柄（柄数 = ceil(路径长 / step)，均匀落在各段中点），
## 从起点到终点依次间隔 stagger 秒落下（缺省 0.03）；不撒随机落点、不先落在敌人身上。画面随机只用 g.vrng
static func _tx_rain_path(o, b: Dictionary) -> void:
	var g = o.g
	var c: Dictionary = o.tx.get("ctx", {})
	if not c.has("from"):
		return
	var bs: Array = _tx_rain_spec(o, str(b.strip), b.get("anchor"), Vector2(0.5, 2.0))
	if bs.is_empty():
		return
	var pts: Array = el_path_points(c.from, c.to, float(b.step))
	var rng: RandomNumberGenerator = g.vrng
	var st: float = float(b.get("stagger", 0.03))
	var sc: float = float(b.get("scale", 1.0))
	var sj: float = float(b.get("scale_j", 0.1))
	var tilt: float = deg_to_rad(float(b.get("tilt", 4.0)))
	var slant: float = deg_to_rad(float(b.get("slant", 0.0)))
	var bl: Array = []
	for k in pts.size():
		bl.append({"p": pts[k], "d": st * k, "s": sc * (1.0 + rng.randf_range(-sj, sj)), "a": slant + rng.randf_range(-tilt, tilt), "fl": rng.randf() < 0.5})
	var cc: Vector2 = ((c.from as Vector2) + (c.to as Vector2)) * 0.5
	_tx_rain_emit(o, b, cc, (c.from as Vector2).distance_to(c.to) * 0.5, bl, st * maxf(0.0, pts.size() - 1.0), bs, float(b.get("fall_t", 0.1)))


static func _tx_rain_emit(o, b: Dictionary, cc: Vector2, r: float, bl: Array, tmax: float, bs: Array, ft: float) -> void:
	var hs: Array = _tx_rain_spec(o, str(b.get("hit", "")), b.get("hit_anchor"), Vector2(0.5, 4.0))
	var ms: Array = _tx_rain_spec(o, str(b.get("mark", "")), b.get("mark_anchor"), Vector2(0.5, -1.0))
	if not ms.is_empty() and not b.has("mark_anchor"):
		ms[5] = Vector2(ms[3], ms[4]) * 0.5   # 地面标记缺省锚点 = 帧中心
	var q := {"bs": bs, "hs": hs, "ms": ms, "fall": float(b.get("fall", 90.0)), "ft": ft, "lead": float(b.get("lead", 0.12)),
		"stick": float(b.get("stick", 0.35)), "scorch": float(b.get("scorch", 0.45)), "streak": int(b.get("streak", 2)), "al": float(b.get("alpha", 1.0)),
		"ff": clampi(int(b.get("fall_frames", maxi(1, bs[1] / 2))), 1, bs[1]), "mf": int(b.get("mark_frames", 0 if ms.is_empty() else maxi(1, ms[1] / 2))),
		"hsc": float(b.get("hit_scale", 1.0)), "msc": float(b.get("mark_scale", 1.0)), "c": cc, "r": r}
	var hd: float = 0.0 if hs.is_empty() else float(hs[1]) / maxf(1.0, float(hs[2]))
	var life: float = tmax + ft + maxf(maxf(q.stick, hd), q.scorch) + 0.05
	if b.has("finale") and b.finale is Dictionary:
		var fin: Dictionary = b.finale
		var c4: Array = fin.get("col", [1.0, 0.72, 0.4, 0.9])
		q["fin"] = {"t": float(fin.get("t", tmax + ft)), "scale": float(fin.get("scale", 1.6)), "ring": float(fin.get("ring", 1.0)),
			"col": Color(float(c4[0]), float(c4[1]), float(c4[2]), float(c4[3]) if c4.size() > 3 else 0.9)}
		life = maxf(life, float(q.fin.t) + maxf(hd * 1.5, 0.45) + 0.05)
	var add: bool = str(b.get("layer", "over")) == "add"
	o.fx({"kind": "tx_rain", "pos": cc, "life": life, "bl": bl, "q": q, "add": add})
	if not ms.is_empty() or q.has("fin"):
		o.fx({"kind": "tx_rain", "pos": cc, "life": life, "bl": bl, "q": q, "floor": true})


## 画一次施放（data_operator._draw_pfx / draw_fx_add 调）：上层 = 残影 → 剑 → 冲击（同贴图连着画）；地面层 = 预兆 / 焦痕标记 → 终结亮环
static func tx_rain_draw(ci, o, f: Dictionary) -> void:   # ci：干员的 cv（batch_canvas）或加色层 CanvasItem
	var g = o.g
	if g.perf_alt:   # --perfab 同局轮换：/b 桶不画剑雨（量净成本用；正常游戏恒为 false）
		return
	var q: Dictionary = f.q
	var el: float = float(f.max) - float(f.life)
	var base: float = float(q.al) * float(g.world.fx_dim)
	var ft: float = q.ft
	var px: float = g.PX
	if f.get("floor", false):
		var ms: Array = q.ms
		if not ms.is_empty():
			var tx: Texture2D = ms[0]
			var nf: int = ms[1]
			var mf: int = mini(int(q.mf), nf)
			for bl in f.bl:
				var tl: float = float(bl.d) + ft
				var t0: float = maxf(0.0, tl - float(q.lead))
				var fr := -1
				var al := base
				if el >= t0 and el < tl and mf > 0:
					fr = mini(mf - 1, int((el - t0) / maxf(0.001, tl - t0) * mf))
					al *= 0.85
				elif el >= tl and el < tl + float(q.scorch) and nf > mf:
					var k: float = (el - tl) / maxf(0.001, float(q.scorch))
					fr = mf + mini(nf - mf - 1, int(k * (nf - mf)))
					al *= 1.0 if k < 0.6 else (1.0 - k) / 0.4
				if fr < 0:
					continue
				var kk: float = px * float(bl.s) * float(q.msc) / float(ms[6])
				var sz := Vector2(ms[3], ms[4]) * kk
				ci.draw_texture_rect_region(tx, Rect2((bl.p as Vector2).round() - (ms[5] as Vector2) * kk, sz), Rect2(float(ms[3]) * fr, 0, ms[3], ms[4]), Color(1, 1, 1, al))
		if q.has("fin"):
			var fin: Dictionary = q.fin
			var k2: float = (el - float(fin.t)) / 0.4
			if k2 >= 0.0 and k2 < 1.0 and float(fin.ring) > 0.0:
				var rr: float = float(q.r) * float(fin.ring) * lerpf(0.25, 1.0, 1.0 - (1.0 - k2) * (1.0 - k2))
				var c: Color = fin.col
				ci.draw_set_transform(q.c, 0.0, Vector2(1.0, 0.55))
				if k2 < 0.6:   # 地面闪光：一片热橙椭圆迅速淡掉（程序画，合批三角形；不把冲击帧条放大成粗方块）
					var kf: float = 1.0 - k2 / 0.6
					ci.draw_circle(Vector2.ZERO, rr * 0.85, Color(1.0, 0.62, 0.3, 0.22 * kf * kf * base))
					ci.draw_circle(Vector2.ZERO, rr * 0.4, Color(1.0, 0.9, 0.72, 0.3 * kf * kf * base))
				if Dc.hit_rings():   # 终结亮环属命中装饰圈（render/hit_rings 缺省不画），地面闪光照画
					ci.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(c.r, c.g, c.b, c.a * (1.0 - k2) * base), 4.0)
					ci.draw_arc(Vector2.ZERO, rr * 0.92, 0.0, TAU, 56, Color(1.0, 0.95, 0.85, 0.6 * (1.0 - k2) * base), 1.5)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# 上层：剑（下落 + 残影 / 插地），同一张贴图
	var bs: Array = q.bs
	var btx: Texture2D = bs[0]
	var nb: int = bs[1]
	var ff: int = q.ff
	var fw: float = bs[3]
	var fh: float = bs[4]
	var ban: Vector2 = bs[5]
	var stick: float = q.stick
	for bl in f.bl:
		var d: float = bl.d
		if el < d:
			continue
		var tl: float = d + ft
		var kk: float = px * float(bl.s) / float(bs[6])
		var sx: float = -kk if bl.fl else kk
		var a: float = bl.a
		var p: Vector2 = bl.p
		if el < tl:
			var kf: float = (el - d) / maxf(0.001, ft)
			var dirv := Vector2(-sin(a), cos(a))   # 剑尖朝向（落向）
			var off: float = float(q.fall) * (1.0 - kf * kf)   # 先慢后快地扎下来
			var fr: int = int(el * float(bs[2])) % ff
			var src := Rect2(fw * fr, 0, fw, fh)
			var al: float = base * minf(1.0, kf * 5.0 + 0.2)
			for i in range(int(q.streak), -1, -1):
				var pp: Vector2 = p - dirv * (off + float(q.fall) * 0.16 * i)
				ci.draw_set_transform(pp.round(), a, Vector2(sx, kk))
				ci.draw_texture_rect_region(btx, Rect2(-ban, Vector2(fw, fh)), src, Color(1, 1, 1, al * pow(0.42, i)))
		elif el < tl + stick and nb > ff:
			var k3: float = (el - tl) / maxf(0.001, stick)
			var fr2: int = ff + mini(nb - ff - 1, int(k3 * (nb - ff)))
			ci.draw_set_transform(p.round(), a, Vector2(sx, kk))
			ci.draw_texture_rect_region(btx, Rect2(-ban, Vector2(fw, fh)), Rect2(fw * fr2, 0, fw, fh), Color(1, 1, 1, base * (1.0 if k3 < 0.7 else (1.0 - k3) / 0.3)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 冲击帧条
	var hs: Array = q.hs
	if hs.is_empty():
		return
	var htx: Texture2D = hs[0]
	var hn: int = hs[1]
	var hfps: float = hs[2]
	var hw: float = hs[3]
	var hh: float = hs[4]
	for bl in f.bl:
		var e2: float = el - float(bl.d) - ft
		if e2 < 0.0:
			continue
		var fr3: int = int(e2 * hfps)
		if fr3 >= hn:
			continue
		var kh: float = px * float(bl.s) * float(q.hsc) / float(hs[6])
		ci.draw_texture_rect_region(htx, Rect2((bl.p as Vector2).round() - (hs[5] as Vector2) * kh, Vector2(hw, hh) * kh), Rect2(hw * fr3, 0, hw, hh), Color(1, 1, 1, base))
	if q.has("fin"):
		var fin2: Dictionary = q.fin
		var e3: float = el - float(fin2.t)
		var fr4: int = int(e3 * hfps * 0.75)   # 终结冲击放慢一点
		if e3 >= 0.0 and fr4 < hn:
			var kf2: float = px * float(fin2.scale) / float(hs[6])
			ci.draw_texture_rect_region(htx, Rect2((q.c as Vector2).round() - (hs[5] as Vector2) * kf2, Vector2(hw, hh) * kf2), Rect2(hw * fr4, 0, hw, hh), Color(1, 1, 1, base))


# ================================================================ 次元斩（剑雨滂沱，10-24 用户定，docs/129 §14）
# 技能期间普攻整个换成这一段：出手瞬间本体隐去，在前方扇形里依次闪现到 n 个敌人身边各斩一道直线（没有那么多敌人就斩空位补足），
# 每道线是一次线段判定（路径上的敌人各吃一次、可带短定身），留下像素刀痕 scar 秒后碎成颗粒。本体的逻辑位置（pos / g.ppos / 镜头 / 受击）全程不动，
# 闪现只是画面上的残影。纯画面部分只用 g.vrng；玩法部分不取随机数（落点、角度都由下标算出）

const RIFT_CELL := 2.0   # 刀痕像素格（世界像素；低分辨率层上 1 格）


## 出手（瞬时）：定方向、排好 n 个出手时刻；每一刀斩谁在到点那一刻再挑（追着活的敌人打，10-25 用户「追踪敌人去打，而不是打虚空」）
static func tx_rift_start(o, b: Dictionary) -> void:
	var r: float = float(b.r) * o.stat(&"op_range")
	var ts: Array = o.nearest_enemies(1, r + 30.0, o.pos)
	var dir_a: float = (ts[0].pos - o.pos).angle() if not ts.is_empty() else o.facing_angle()
	if o.held_aim() and o.atk_aim != Vector2.ZERO:
		dir_a = o.atk_aim.angle()
	var lead: float = float(b.get("lead", 0.12))
	var n: int = int(b.n)
	var dmg: float = o.base("atk", 0.0) * float(b.mult) * float(o.loc.dmg) * o._dmg_bonus() * o.skill_power()
	o.tx["rift"] = {"t": 0.0, "k": 0, "n": n, "lead": lead, "b": b, "dmg": dmg, "dir": dir_a, "r": r, "hit": {}, "from": o.pos,
		"end": _tx_rift_at(b, lead, n, n - 1) + maxf(0.16, float(b.get("pose", 0.12))), "flash": {}, "any": not ts.is_empty()}
	o._sfx_op("atk")


## 第 k 刀的出手时刻：首刀前停 lead（拔刀前一拍），中间每 gap 一刀，末刀前再停 hold（收刀前一拍）
static func _tx_rift_at(b: Dictionary, lead: float, n: int, k: int) -> float:
	return lead + float(k) * float(b.gap) + (float(b.get("hold", 0.0)) if k == n - 1 and n > 1 else 0.0)


## 这一刀斩谁：她 r 内、优先前方扇形（半角 half）里，离上一刀落点最近的、这一轮还没斩过的活敌人；都斩过就从头再轮；没有敌人返回 {}
static func _tx_rift_pick(o, rf: Dictionary) -> Dictionary:
	var half: float = float(rf.b.get("half", 1.1))
	var best: Dictionary = {}
	var bk := INF
	for e in o.nearest_enemies(24, float(rf.r), o.pos):
		if e.dead:
			continue
		var front: bool = absf(angle_difference((e.pos - o.pos).angle(), float(rf.dir))) <= half
		var key: float = (rf.from as Vector2).distance_squared_to(e.pos) + (0.0 if front else 1.0e7) + (1.0e8 if rf.hit.has(e.id) else 0.0)
		if key < bk:
			bk = key
			best = e
	return best


## 每帧：到点的那一刀挑目标、判定、留刀痕；斩完回原位；刀痕到期碎成颗粒
static func tx_rift_update(o, dt: float) -> void:
	var tx: Dictionary = o.tx
	var g = o.g
	if tx.has("rift"):
		var rf: Dictionary = tx.rift
		rf.t += dt
		var b: Dictionary = rf.b
		while int(rf.k) < int(rf.n) and rf.t >= _tx_rift_at(b, float(rf.lead), int(rf.n), int(rf.k)):
			var k: int = rf.k
			rf.k = k + 1
			var e: Dictionary = _tx_rift_pick(o, rf)
			var ctr: Vector2
			if e.is_empty():
				if k > 0 or rf.any:
					rf.k = rf.n   # 没有活敌人了：不斩空，直接收刀
					rf.end = minf(float(rf.end), rf.t + 0.12)
					break
				ctr = o.pos + Vector2.from_angle(float(rf.dir)) * float(rf.r) * 0.5   # 出手时一个敌人都没有（手动空挥）：朝指向斩一刀
			else:
				ctr = e.pos
				if rf.hit.size() >= 24:
					rf.hit.clear()
				rf.hit[e.id] = true
			var last: bool = k == int(rf.n) - 1 and int(rf.n) > 1
			var len: float = float(b.len) * (1.3 if last else 1.0)   # 末刀更长
			var sgn: float = 1.0 if k % 2 == 0 else -1.0
			var u: Vector2 = Vector2.from_angle(float(rf.dir) + sgn * (0.6 + 0.12 * float(k)))
			var p0: Vector2 = ctr - u * len * 0.5
			var p1: Vector2 = ctr + u * len * 0.5
			if k % 2 == 1:
				var sw: Vector2 = p0
				p0 = p1
				p1 = sw
			var sb := {"src": str(b.get("src", "")), "tags": b.get("tags", ["skill", "pierce"]),
				"on_hit": [{"st": "stun", "dur": float(b.get("stun", 0.0))}] if float(b.get("stun", 0.0)) > 0.0 else []}
			_tx_sweep(o, p0, p1, float(b.get("w", 40.0)), {}, rf.dmg, sb)
			var life: float = float(b.get("scar", 0.22))
			# 画面（10-29 用户「次元斩应是很多条笔直细长的斩线，乱刃一团」）：判定线 p0→p1 不变，刀痕向两端各延伸 ext（空间被整条切开）、一律直线；
			# 再叠 extra 条只画不判的细斩线，角度由下标 + g.vrng 错开，围着这一刀的落点交错成团。判定、伤害、出手时刻全不动
			var ud: Vector2 = (p1 - p0) / maxf(1.0, p0.distance_to(p1))
			var ext: float = len * float(b.get("scar_ext", 0.6))
			var sw: float = float(b.get("sweep", 0.03))
			var wm: float = 3.0 if last else 2.0
			_tx_rift_scar(o, p0 - ud * ext, p1 + ud * ext, life, sw, wm)
			var nx: int = int(b.get("scar_extra", 2)) + (1 if last else 0)
			for xi in nx:
				var xa: float = ud.angle() + (1.0 if (k + xi) % 2 == 0 else -1.0) * g.vrng.randf_range(0.35, 1.35)
				var xu: Vector2 = Vector2.from_angle(xa)
				var xc: Vector2 = ctr + Vector2(g.vrng.randf_range(-18.0, 18.0), g.vrng.randf_range(-12.0, 12.0))
				var xl: float = len * g.vrng.randf_range(0.7, 1.2) + ext
				_tx_rift_scar(o, xc - xu * xl * 0.5, xc + xu * xl * 0.5, life * g.vrng.randf_range(0.8, 1.0), sw + 0.012 * float(xi + 1), 2.0)
			var sc: Array = tx.get("scars", [])
			sc.append({"a": p0 - ud * ext, "c": p1 + ud * ext, "until": g.t + life})
			tx["scars"] = sc
			rf.flash = {"p": p1, "from": p0, "t": rf.t}
			_tx_rift_trail(o, rf.from, p1)   # 瞬移残影：上一处 → 这一刀落点
			rf.from = p1
			o._sfx_op("hit")
		if rf.t >= rf.end:
			_tx_rift_trail(o, rf.from, o.pos)   # 斩完回原位，同样留残影
			tx.erase("rift")
	var sc2: Array = tx.get("scars", [])
	if not sc2.is_empty():
		var keep: Array = []
		for s in sc2:
			if g.t >= float(s.until):
				_tx_rift_grains(o, s.a, s.c, 6.0)
			else:
				keep.append(s)
		tx["scars"] = keep


## 一条刀痕（画面）：直线、两端尖，bow 恒 0
static func _tx_rift_scar(o, a: Vector2, c: Vector2, life: float, sweep: float, wmax: float) -> void:
	o.fx({"kind": "tx_scar", "a": a, "c": c, "life": life, "col": o.col(), "sweep": sweep, "bow": 0.0, "wmax": wmax})
	_tx_rift_grains(o, a, c, 14.0)


## 沿线撒刀光颗粒（光学开 + 粒子开才有；缺则什么都不画）
static func _tx_rift_grains(o, a: Vector2, c: Vector2, step: float) -> void:
	var g = o.g
	if g == null or not g.get("optical_on") or g.optical == null or g.optical.grains == null:
		return
	var gr = g.optical.grains
	if not gr.on() or gr.off:
		return
	var seg: Vector2 = c - a
	var L: float = seg.length()
	if L < 1.0:
		return
	var d: Vector2 = seg / L
	var nv: Vector2 = d.orthogonal()
	var cols: Array = [Color(1.0, 1.0, 1.0), Color(1.0, 0.6, 0.22), Color(1.0, 0.82, 0.5)]
	var m: int = maxi(2, int(L / step))
	for i in m:
		var q: Vector2 = a.lerp(c, (float(i) + g.vrng.randf()) / float(m))
		var side: float = -1.0 if g.vrng.randf() < 0.5 else 1.0
		gr.push("slash", q, (nv * side + d * 0.3).normalized(), cols[int(g.vrng.randf() * 3.0) % 3])


## 画本体：闪现序列里本体隐去，只在斩出手后的 0.2 秒里在落点画一份（朝向 = 斩的方向）。返回 true = 已处理（不画原位的本体）
static func tx_rift_draw_body(o) -> bool:
	_tx_rift_draw_trails(o)
	var rf = o.tx.get("rift")
	if rf == null:
		return false
	var fl: Dictionary = rf.flash
	var pose: float = float(rf.b.get("pose", 0.12))   # 定格：每刀斩完在落点停住的时间（下一刀先到就换位），最后 30% 渐隐
	if not fl.is_empty() and float(rf.t) - float(fl.t) < pose:
		var dv: Vector2 = (fl.p as Vector2) - (fl.from as Vector2)
		var k: float = clampf((1.0 - (float(rf.t) - float(fl.t)) / pose) / 0.3, 0.0, 1.0)
		o.draw_body_at(fl.p, dv.x < 0.0, Color(1.0, 1.0, 1.0, 0.35 + 0.65 * k))
	return true


## 刀痕（kind = tx_scar）：像素刀口——2 px 格，两头尖、中间宽（宽度按 sin 起伏，最宽 wmax 格），一律直线（bow 缺省 0）；
## 中心一条白芯（只在够宽的那段）、外面主题色橙的阶梯硬边、边缘按下标错开一格做毛边；sweep 秒内（缺省 0.03，1–2 帧）从起点划到终点，刀尖一格更亮；最后 35% 寿命逐格碎掉
static func tx_scar_draw(o, f: Dictionary, a: float) -> bool:
	var cv = o.cv
	var p0: Vector2 = f.a
	var p1: Vector2 = f.c
	var seg: Vector2 = p1 - p0
	var L: float = seg.length()
	if L < 1.0:
		return true
	var d: Vector2 = seg / L
	var nv: Vector2 = d.orthogonal()
	var el: float = float(f.max) - float(f.life)
	var reach: float = clampf(el / float(f.get("sweep", 0.07)), 0.0, 1.0)
	var frac: float = float(f.life) / float(f.max)
	var melt: float = clampf((0.35 - frac) / 0.35, 0.0, 1.0)
	var edge: Color = f.col                         # 德克萨斯主题色橙（10-29 用户：白芯 + 橙色辉光，不用冷青蓝，不另画圆 / 环）
	edge = Color(maxf(edge.r, 1.0), edge.g * 0.95, edge.b * 0.9)
	var dark := Color(edge.r * 0.6, edge.g * 0.38, edge.b * 0.25)
	var cell: float = RIFT_CELL
	var bow: float = float(f.get("bow", 0.07)) * L
	var wmax: float = float(f.get("wmax", 2.0)) * (1.0 if frac < 0.85 else 1.25)
	var steps: int = int(L / cell)
	var lit: int = int(reach * float(steps))
	var al: float = a * (0.45 + 0.55 * clampf(frac * 3.0, 0.0, 1.0))
	var seed: float = float(int(absf(p0.x)) % 7) * 0.13
	var seen := {}
	for i in lit:
		if melt > 0.0 and fposmod(float(i) * 0.6180339 + seed, 1.0) < melt:
			continue
		var u: float = float(i) / float(maxi(1, steps))
		var prof: float = pow(sin(PI * u), 0.7)
		var q: Vector2 = p0 + d * (u * L) + nv * (bow * sin(PI * u))
		var hw: int = int(round(prof * wmax * 0.5 + (0.5 if (i * 7) % 5 == 0 else 0.0)))   # 毛边：每隔几格多出半格
		for w in range(-hw, hw + 1):
			var e: Vector2 = q + nv * (float(w) * cell)
			var key := Vector2i(int(floorf(e.x / cell)), int(floorf(e.y / cell)))
			if seen.has(key):
				continue
			seen[key] = true
			var c: Color
			var aw: int = absi(w)
			if aw == 0 and hw >= 1:
				c = Color(2.0, 2.0, 2.0, al)
			elif aw < hw:
				c = Color(edge.r * 1.3, edge.g * 1.3, edge.b * 1.3, al)
			else:
				c = Color(dark.r, dark.g, dark.b, 0.8 * al)
			cv.draw_rect(Rect2(Vector2(key) * cell, Vector2(cell, cell)), c)
	if reach < 1.0 and lit > 0:   # 刀尖：正在划的那一格更亮
		var ut: float = float(lit) / float(maxi(1, steps))
		var tip: Vector2 = p0 + d * (ut * L) + nv * (bow * sin(PI * ut))
		cv.draw_rect(Rect2(Vector2(floorf(tip.x / cell), floorf(tip.y / cell)) * cell - Vector2(cell, cell) * 0.5, Vector2(cell, cell) * 2.0), Color(2.4, 2.4, 2.4, a))
	return true

## 瞬移残影（10-25 用户「瞬移加上一点残影」）：一次闪现 a → b 记一条，画面上沿线均匀画 RIFT_TRAIL_N 个当前帧剪影（偏冷半透明、越靠起点越淡），
## RIFT_TRAIL_LIFE 秒内整体淡掉。纯画面：时间用 g.t，不进玩法
const RIFT_TRAIL_N := 4
const RIFT_TRAIL_LIFE := 0.26

static func _tx_rift_trail(o, a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 8.0:
		return
	var tr: Array = o.tx.get("rtrail", [])
	tr.append({"a": a, "b": b, "t0": float(o.g.t)})
	o.tx["rtrail"] = tr


static func _tx_rift_draw_trails(o) -> void:
	var tr: Array = o.tx.get("rtrail", [])
	if tr.is_empty():
		return
	var now: float = float(o.g.t)
	var keep: Array = []
	for it in tr:
		var age: float = now - float(it.t0)
		if age < 0.0 or age >= RIFT_TRAIL_LIFE:
			continue
		keep.append(it)
		var fade: float = 1.0 - age / RIFT_TRAIL_LIFE
		var a: Vector2 = it.a
		var b: Vector2 = it.b
		var flip: bool = b.x < a.x
		for i in RIFT_TRAIL_N:
			var u: float = float(i + 1) / float(RIFT_TRAIL_N + 1)
			var al: float = fade * (0.18 + 0.32 * u)
			o.draw_body_at(a.lerp(b, u).round(), flip, Color(0.55, 0.72, 1.0, al))
	o.tx["rtrail"] = keep


# ================================================================ docs/202 成长节点（10-29）：德克萨斯「居合」「破绽」
## 执行入口 gm_exec（data_operator._ext_exec 转来；tag 登记在 seg_hoshiguma EXT_BLOCKS 与 EXEC_SEG 0）。读 o.gm_hits（trig.on_hit_n 记下的这一次拔刀命中列表）。
## 确定性：不取随机数；画面只用 o.fx / float_text。

static func _tx_gm_validate(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	match tag:
		"verb.dash_cd_cut":
			_num(b, "per", p, ctx, true, 0.0, 5.0)
			_num(b, "max", p, ctx, true, 0.0, 10.0)
		"verb.break_windup":
			_num(b, "kb", p, ctx, false, 0.0, 300.0)


## 敌人正在前摇出招：wind（近战 / 远程起手）、dash_w / nova_w / blast_w（冲锋 / 环弹 / 自爆引信）> 0，或有以它为主的未结算预警（docs/182）
static func _tx_winding(o, e: Dictionary) -> bool:
	for k in ["wind", "dash_w", "nova_w", "blast_w"]:
		if float(e.get(k, 0.0)) > 0.0:
			return true
	for w in o.g.warns:
		if is_same(w.get("owner"), e) and not w.get("done", false):
			return true
	return false


static func gm_exec(o, b: Dictionary) -> void:
	var g = o.g
	match str(b.get("_tag", "")):
		"verb.dash_cd_cut":
			# 居合：这一次拔刀每命中一名敌人，队长冲刺冷却缩短 per 秒（至多 max 秒）；冷却已空则什么都不发生
			var n := 0
			for e in o.gm_hits:
				if not e.dead:
					n += 1
			var cut: float = minf(float(b.per) * float(n), float(b.max))
			var real: float = minf(cut, float(g.dash_cd))
			if real <= 0.0 or g.ppos == Vector2.INF:
				return
			g.dash_cd = maxf(0.0, float(g.dash_cd) - real)
			var gold := Color(1.0, 0.85, 0.35)
			o.fx({"kind": "ring", "pos": g.ppos + Vector2(0, 4), "r": 34.0, "r0": 10.0, "life": 0.3, "col": gold, "floor": true, "w": 3.0, "alpha": 0.95})
			for k in 4:   # 冲刺条刻度：四粒金色光点从她的位置飞向队长
				var from: Vector2 = o.pos + Vector2(0, -20)
				o.fx({"kind": "mote", "pos": from, "vel": (g.ppos + Vector2(0, -20) - from) * 3.0 + Vector2(0, -20), "life": 0.33, "col": gold, "sz": 2.4})
			o.float_text(g.ppos + Vector2(0, -104), "居合 -%.1f 秒" % real, gold, 13)
		"verb.break_windup":
			# 破绽：命中的普通敌人（非精英 / Boss）正在前摇 → 打断（作废预警、清蓄力 / 冲刺 / 环弹 / 引信）+ 小击退，不眩晕
			var kb: float = float(b.get("kb", 60.0))
			for e in o.gm_hits:
				if e.dead or e.boss or e.elite or not _tx_winding(o, e):
					continue
				g.enemies_sys.interrupt(e)
				var dv: Vector2 = e.pos - o.pos
				o.apply_kb(e, (dv.normalized() if dv.length() > 0.5 else Vector2.RIGHT) * kb)
				var red := Color(1.0, 0.35, 0.3)
				var hp0: Vector2 = e.pos + Vector2(0, -float(e.r) - 14.0)
				o.fx({"kind": "ring", "pos": hp0, "r": 20.0, "r0": 8.0, "life": 0.3, "col": red, "w": 3.0, "alpha": 0.95})   # 头顶红圈碎开
				for k in 6:
					o.sparks(hp0, Vector2.from_angle(TAU * float(k) / 6.0), red, 1, 90.0)
				o.float_text(hp0 + Vector2(0, -14), "破绽", red, 13)
