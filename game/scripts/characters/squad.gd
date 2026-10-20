## 编队（docs/23 §3）：持有编队位上的干员实例，负责招募 / 替换、编队校验、跟随队形与统一的 update / draw 分发。
## 常规上限 3 人，第 4 位由事件 / 藏品 / 商店解锁（extra_slot）。干员没有生命值，敌人只追主控。
extends RefCounted

const Character = preload("res://scripts/characters/character.gd")
const BatchCanvas = preload("res://scripts/characters/batch_canvas.gd")
const Bal = preload("res://scripts/core/balance.gd")

const REGULAR_MAX := 3
## 编队位相对主控的偏移（主控朝右时；朝左镜像 x）。0 号位是主控本人（不用），跟随者从 1 号位起，拉开到能分清谁是谁；
## 博士挂件在主控左下后方（characters/doctor.gd DOC_BEHIND），这里避开那个位置
const SLOTS := [Vector2.ZERO, Vector2(-74, -26), Vector2(70, -20), Vector2(4, -72), Vector2(-80, 44)]
const DEMO_SLOT := Vector2(44, -6)

var g
var cv                           # 干员绘制合批画布（batch_canvas.gd，性能 9/30）
var ops: Array = []            # Character 实例，按入队顺序
var extra_slot := false        # 第 4 位是否已解锁
var side := 1.0                # 编队站位的左右（-1..1），主控转身时约 0.8 秒平滑换边（2026-09-27 跑步审查）
## 指挥模式（docs/114）：全队站位。一个键循环 随行 → 突击 → 归队；归队归位完自动回随行（下一次按键进突击）
enum { GUARD, ROAM, RECALL }
const STANCE_NAMES := ["随行", "突击", "归队"]
var stance := GUARD
var recall_t := 0.0
var gather_t := -1.0          # 归队：全员到位后站定的剩余秒数（-1 = 还在往回跑）
var stance_log: Array = []     # [[g.t, 新站位], …]：玩家切换记录（同 seed 复现 / 机器人对照）


func _init(game) -> void:
	g = game
	cv = BatchCanvas.new(game)


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


## 招募：实例化干员、登记专属属性与伤害来源、放到主控身边。满员返回 null。
## recruit_event = false：中途换人（replace）时不触发「招募」类藏品（否则换一次人就能刷一次源石锭 / 成长三选一）
func add(cid: String, recruit_event := true):
	if has(cid) or is_full():
		return null
	var op = Character.create(g, cid)
	if op == null:
		return null
	op.slot = ops.size()
	op.is_leader = ops.is_empty()   # 开局干员 = 主控
	if op.is_leader:
		_apply_leader_regen(op)
	op.voice_t = g.vrng.randf_range(20.0, 40.0)   # 语音计时只影响声音（docs/101 §3.4 ④）
	# 部署语音：排队播，多名干员不会同帧抢话（图鉴演示不播）
	var sfx0: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx0 != null and g.demo_op == "":
		sfx0.voice(cid, "entry", true)
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
	if g.get("telemetry") != null:
		g.telemetry.on_join(op)   # 作战记录：入队时间、名字、颜色（docs/77）
	if op.has_method("on_join"):
		op.on_join()
	validate_squad()
	if not _hold_size:
		_apply_size_hp()
	if g.get("rfx") != null:
		g.rfx.refresh_squad()
		if not op.is_leader and recruit_event:
			g.rfx.on_recruit(op)   # 招募事件（docs/57 P10）：开局干员不算
	return op


## 移除（事件替换用）：被替换的干员成长清零
func remove(cid: String) -> void:
	for i in ops.size():
		if ops[i].id == cid:
			if g.get("telemetry") != null:
				g.telemetry.on_leave(cid)
			if ops[i].has_method("on_leave"):
				ops[i].on_leave()
			ops.remove_at(i)
			break
	for i in ops.size():
		ops[i].slot = i
	if not _hold_size:
		_apply_size_hp()
	if not ops.is_empty() and not ops.any(func(o): return o.is_leader):
		ops[0].is_leader = true
		_apply_leader_regen(ops[0])
	if g.get("rfx") != null:
		g.rfx.refresh_squad()


var _hold_size := false   # replace 中途：人数先减后加，不重算入队加成（人数不变，台阶不变）


## 中途更换队友（用户 10-13 批准）：old_id 离队、new_id 接替它的编队位，继承 old 的成长节点数（精英化阶段 + 技能 / 成长节点），
## 继承的节点不看条件、不重播精英化演出。队长不能被替换。被换下的干员清掉它挂在 op:<id> 作用域上的修正，回到招募池。
## 人数不变 → 入队加成（最大生命 / 回复台阶）不重算，也不触发「招募」类藏品。失败返回 null
func replace(old_id: String, new_id: String):
	var old = get_op(old_id)
	if old == null or old.is_leader or has(new_id):
		return null
	var idx: int = ops.find(old)
	var inherit: int = old.prog
	_hold_size = true
	remove(old_id)
	g.stats.remove_scope("op:" + old_id)
	var op = add(new_id, false)
	_hold_size = false
	if op == null:
		return null
	ops.erase(op)
	ops.insert(mini(idx, ops.size()), op)
	for i in ops.size():
		ops[i].slot = i
	op.pos = g.ppos + _slot_offset(op.slot)
	var sq0: int = g.show_queue.size()
	for k in inherit:
		var n: Dictionary = op.next_node()
		if n.is_empty():
			break
		var chs: Dictionary = op.elite_choices(n) if n.get("type", "") == "elite" else {}
		op.advance(chs.keys()[0] if not chs.is_empty() else "")
	if g.show_queue.size() > sq0:
		g.show_queue.resize(sq0)   # 继承来的精英化不弹演出
	g.sync_stats()
	return op


## 入队加成（docs/83，用户 10-13 定：每入队一名干员，编队生命与自动回复各上一个台阶；招募时写明）。
## 每多 1 名干员（开局干员不算，最多算 squad/hp_member_cap 人）：
##   主控最大生命 ×(1 + squad/hp_per_member × 人数)（2026-09-27 用户定每人 +15%），对 max_hp 加来源 "squad" 的 mult，叠在成长卡生命之上一起放大；
##   主控生命回复 + squad/regen_per_member × 人数（生命 / 秒），对 regen 加来源 "squad" 的 flat，和干员 leader 段 regen、「自愈」同一个池，吃 heal_mult。
## 人数变化时当前生命按同比例缩放（入队不显示掉血，离队反向）
func _apply_size_hp() -> void:
	if g.stats == null or not g.stats.has_stat(&"max_hp"):
		return
	var per: float = Bal.v("squad/hp_per_member", 0.0)
	var old_max: float = g.max_hp
	g.stats.remove_source("squad")
	var n: int = member_steps(ops.size())
	if per != 0.0 and n > 0:
		g.stats.add(&"max_hp", "mult", 1.0 + per * n, "squad")
	var rb: float = regen_bonus(n)
	if rb != 0.0 and n > 0 and g.stats.has_stat(&"regen"):
		g.stats.add(&"regen", "flat", rb, "squad")
	var new_max: float = maxf(20.0, g.stats.value(&"max_hp"))
	if old_max > 0.0 and new_max != old_max and g.hp > 0.0:
		g.hp = clampf(g.hp * new_max / old_max, 1.0, new_max)
		g.max_hp = new_max   # 先同步，game.sync_stats 看到没变化，不会再按差值补一次


## 编队 size 人时算几个入队台阶（开局干员不算，封顶 squad/hp_member_cap）
static func member_steps(size: int) -> int:
	return mini(maxi(size - 1, 0), Bal.vi("squad/hp_member_cap", 3))


## 前 steps 个入队台阶合计加多少生命回复（生命 / 秒，未乘 heal_mult）。分档旋钮（协调人 10-13，云端测前期回复用）：
## 第 1 / 第 2 名队友各加 squad/regen_t1 / regen_t2，< 0（缺省 -1）= 沿用 regen_per_member；第 3 名起（编队上限 +1 的藏品）一律 regen_per_member。
## 两档都没设时仍按原式 regen_per_member × 台阶数算（缺省结果逐位不变）
static func regen_bonus(steps: int) -> float:
	var rper: float = Bal.v("squad/regen_per_member", 0.0)
	var t1: float = Bal.v("squad/regen_t1", -1.0)
	var t2: float = Bal.v("squad/regen_t2", -1.0)
	if t1 < 0.0 and t2 < 0.0:
		return rper * steps
	var tot := 0.0
	for k in steps:
		var tk: float = [t1, t2][k] if k < 2 else -1.0
		tot += tk if tk >= 0.0 else rper
	return tot


## 第 k 名队友（k 从 1 起）入队时这一档加的生命回复
static func regen_step(k: int) -> float:
	return regen_bonus(k) - regen_bonus(k - 1)


## 指南里「生命回复 +{regen_per_member} / 秒」的数：两档相同写一个数（缺省 0.9）；分档时写「0.5 / 1.3」（第 1 / 第 2 名）
static func regen_steps_text() -> String:
	var a: float = regen_step(1)
	var b: float = regen_step(2)
	return _num(a) if is_equal_approx(a, b) else "%s / %s" % [_num(a), _num(b)]


## 入队加成说明（数字读 balance.json squad 段；这名干员入队后台阶已封顶 = 空串）。
## 用户 10-13：不再写在每张招募卡上，改在招募三选一 / 混有招募卡的升级三选一的标题说明行写一次（choice_panel.show_choices）
func join_bonus_text() -> String:
	if member_steps(ops.size() + 1) <= member_steps(ops.size()):
		return ""
	var parts: Array = []
	var per: float = Bal.v("squad/hp_per_member", 0.0)
	var rper: float = regen_step(member_steps(ops.size() + 1))
	if per > 0.0:
		parts.append("队长最大生命 +%d%%" % int(round(per * 100.0)))
	if rper > 0.0:
		parts.append("生命回复 +%s / 秒" % _num(rper * g.heal_mult))
	return ("入队加成：" + "，".join(parts)) if not parts.is_empty() else ""


## 0.9 → "0.9"，1.0 → "1"，1.25 → "1.25"（去掉多余的 0）
static func _num(v: float) -> String:
	var s := "%.2f" % v
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	return s.trim_suffix(".")


## 主控的自然回复（每秒回复生命）：JSON leader 段的 regen，没写就沿用博士的基础值（doctor.json 1.0）。
## 生命 / 物理减伤 / 法抗在 game.gd 开局处按同一个 leader 段覆盖；回复放这里，是因为主控换人（事件替换）时也要跟着换。
## --noleader：平衡对照用，全部退回博士的统一值
func _apply_leader_regen(op) -> void:
	if g.stats == null or not g.stats.has_stat(&"regen") or Cfg.dev_args().has("--noleader"):
		return
	var base: float = float(g.doctor.def.get("stats", {}).get("regen", 1.0)) if g.get("doctor") != null else 1.0
	# sustain/base_regen_mult（缺省 1）：只缩放队长自带的基础回复，入队台阶、「自愈」、藏品不受影响（协调人 10-13 云端测试用旋钮）
	g.stats.set_base(&"regen", float(op.def.get("leader", {}).get("regen", base)) * Bal.v("sustain/base_regen_mult", 1.0))
	g.sync_stats()


func _slot_offset(i: int) -> Vector2:
	if g.demo_op != "":
		return DEMO_SLOT   # 图鉴演示：站在主控前方（朝右侧怪海），重置后不用先走回身后
	var o: Vector2 = SLOTS[mini(i, SLOTS.size() - 1)]
	return Vector2(o.x * side, o.y)


## 编队契约：常规人数 ≤ 3（解锁后 ≤ 4）；每名干员至多 1 个手动技能（契约 v2.2，按 Q / J 由 doctor.try_manual_skill 路由）
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
	g.doctor.tick_input(dt)   # 手动普攻按键 / 选落点蓄距离（契约 v2.5）
	side = move_toward(side, g.facing, dt * 2.5)
	for o in ops:
		o.follow(dt, g.ppos if o.is_leader else g.ppos + _slot_offset(o.slot))
	if stance == RECALL:
		_tick_recall(dt)
	for o in ops:
		o.tick_sp(dt)
		_battle_voice(o, dt)
		o.update(dt)
		# 主控的技能位移（推进之王跃空锤、乌尔比安顺锁链弹射）带着玩家一起走，位移中短暂无敌
		if o.is_leader and o.pos != Vector2.INF and o.pos.distance_to(g.ppos) > 0.5:
			g.ppos = o.pos
			g.invuln = maxf(g.invuln, 0.12)
			g.invuln_move_until = g.t + 0.12
		o._tick_pfx(dt)


## 指挥模式总开关（balance command/on）
static func cmd_on() -> bool:
	return Bal.v("command/on", 1.0) > 0.0


## 玩家按「指挥」键：随行 → 突击 → 归队；归队途中再按 = 突击。返回是否切换了
func cycle_stance() -> bool:
	if not cmd_on():
		return false
	set_stance(ROAM if stance != ROAM else RECALL)
	return true


func set_stance(s: int) -> void:
	if s == stance:
		return
	stance = s
	recall_t = 0.0
	gather_t = -1.0
	stance_log.append([g.t, s])
	if g.get("trace_every") != null and g.trace_every > 0.0:
		print("CMD t=%.2f stance=%d" % [g.t, s])   # 不进 TRACE 行（trace_base 只比 TRACE / BALANCE），随行局同 seed 逐行不变


## 归队：全员离随行站位都在 command/recall_done 以内（或超过 command/recall_max 秒）就站定 command/gather 秒（集合完毕），再回随行
func _tick_recall(dt: float) -> void:
	if gather_t >= 0.0:
		gather_t -= dt
		if gather_t <= 0.0:
			set_stance(GUARD)
		return
	recall_t += dt
	var done := recall_t >= Bal.v("command/recall_max", 3.0)
	if not done:
		done = true
		var lim: float = Bal.v("command/recall_done", 28.0)
		for o in ops:
			if not o.is_leader and o.cmd_d > lim:
				done = false
				break
	if done:
		gather_t = Bal.v("command/gather", 0.4)


## 战斗台词：每人 30–55 秒一次，身边 300 内有敌人才说；维什戴尔四成概率换成 W 的笑声
func _battle_voice(o, dt: float) -> void:
	o.voice_t -= dt
	if o.voice_t > 0.0:
		return
	o.voice_t = g.vrng.randf_range(30.0, 55.0)
	if g.demo_op != "" or g.enemies_sys.nearest(1, 300.0, o.pos).is_empty():
		return
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.voice(o.id, "w_laugh" if o.id == "wisadel" and g.vrng.randf() < 0.4 else "battle")


## 主控干员（docs/23 v0.7：玩家操控的干员，唯一受击体）
func leader():
	for o in ops:
		if o.is_leader:
			return o
	return ops[0] if not ops.is_empty() else null


## 干员侧挂点（同 dmg_taken_mult 询问模式，docs/26 第二批）
## 圣域：任一干员的 sanctuary() 覆盖到 p（流明的灯塔）→ 溟痕、黑潮圈外惩罚失效
func in_sanctuary(p: Vector2) -> bool:
	for o in ops:
		if o.has_method("sanctuary"):
			var sc: Dictionary = o.sanctuary()
			if not sc.is_empty() and p.distance_to(sc.pos) < sc.r:
				return true
	return false


## 主控本该倒下时，任一干员阻止（幽灵鲨 S2）
func prevent_death() -> bool:
	for o in ops:
		if o.has_method("prevent_death") and o.prevent_death():
			return true
	return false


## 主控光照半径倍率（流明 S2）
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
	cv.begin()
	var d0: float = g.world.fx_dim
	for o in ops:
		_op_dim(o, d0)
		o.draw_auras()
	g.world.fx_dim = d0
	cv.mute = false
	cv.amul = 1.0
	cv.end()


## 紧贴地砖的常驻帧条（docs/61 §5.6 layer = ground，10-12 加）：world.draw_world 画完地砖就调，在溟痕 / 地面预警 / 掉落之下
func draw_ground_fx() -> void:
	cv.begin()
	var d0: float = g.world.fx_dim
	for o in ops:
		if o.has_method("draw_ground_fx"):
			_op_dim(o, d0)
			o.draw_ground_fx()
	g.world.fx_dim = d0
	cv.mute = false
	cv.amul = 1.0
	cv.end()


func draw_entities_floor() -> void:
	cv.begin()   # 合批（性能 9/30）：几何图形攒成一批，画贴图前自动提交
	var d0: float = g.world.fx_dim
	for o in ops:
		_op_dim(o, d0)
		o.draw_entities_floor()
		o.draw_pfx(true)
	g.world.fx_dim = d0
	cv.mute = false
	cv.amul = 1.0
	cv.end()


func draw_shadows() -> void:
	cv.begin()
	for o in ops:
		if o.pos != Vector2.INF:
			cv.sync()
			cv.touch()
			var sk: Vector2 = o.shadow_k()   # 技能换动作组离地（docs/92 安洁莉娜浮空）：缩小变淡；判定仍按地面位置
			g.vfx.spr("shadow", 1, 0, o.pos + Vector2(0, 4), g.PX * sk.x, false, Color(1, 1, 1, sk.y))
		o.draw_extra_shadows()
	cv.end()


## 主控标记：脚下一圈职业色细环 + 冲刺冷却白弧，前方一枚小三角指示朝向。原来在 draw_shadows 里、会被敌方预警盖住（真机验收 9:04），
## 改成单独函数由 world.gd 在敌方预警（draw_enemy_tells）之后调用一次（界面与美术 9/30）
func draw_leader_mark() -> void:
	var o = leader()
	if o == null or not o.is_leader or o.pos == Vector2.INF:
		return
	cv.begin()
	# 主控标记：脚下一圈职业色细环，前方一枚小三角指示朝向
	var c: Color = o.col()
	# 可见度（界面与美术 9/30：几十条冲刺预警线交叉压在主控身上时细环认不出）：按预警轮廓的「深边 + 色 + 白芯」画法，任何底色上都跳出来
	var dark := Color(0.02, 0.02, 0.05, 0.75)
	cv.draw_set_transform(o.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
	cv.draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 40, dark, 5.0)
	cv.draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 40, Color(c.r, c.g, c.b, 0.9), 2.5)
	cv.draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 40, Color(1, 1, 1, 0.6), 1.0)
	# 冲刺冷却：外圈一道白弧随冷却走满，满了整圈亮一下
	var dk: float = g.dash_frac()
	if dk < 1.0:
		cv.draw_arc(Vector2.ZERO, 30.0, -PI / 2.0, -PI / 2.0 + TAU * dk, 32, Color(1, 1, 1, 0.35), 1.5)
	else:
		cv.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(1, 1, 1, 0.18), 1.0)
	# 连冲（可储存 2 次以上）：外圈右侧一排小点 = 现在能冲几次
	var dm: int = g.dash_max()
	if dm > 1:
		var dl: int = g.dash_left()
		for di in dm:
			var dp := Vector2(36.0 + 6.0 * di, 0.0)
			cv.draw_circle(dp, 2.2, dark)
			cv.draw_circle(dp, 1.5, Color(1, 1, 1, 0.85 if di < dl else 0.2))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fc: float = g.facing
	var tip: Vector2 = o.pos + Vector2(30.0 * fc, 4)
	# 朝向小三角：先垫一个每边大 2 像素的深色三角
	cv.draw_colored_polygon(PackedVector2Array([tip + Vector2(2.5 * fc, 0), tip + Vector2(-7.5 * fc, -6), tip + Vector2(-7.5 * fc, 6)]), dark)
	cv.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6.0 * fc, -4), tip + Vector2(-6.0 * fc, 4)]), Color(c.r, c.g, c.b, 0.9))
	g.world.draw_attack_dir(cv)   # 手动普攻方向指示（界面与美术 1.1.1，协调人定并进这一批）
	cv.end()


func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	var d0: float = g.world.fx_dim
	for o in ops:
		_op_dim(o, d0)
		g.world.fx_dim = d0 * cv.amul   # 加色层直接画在 ci（不经 cv）：读 fx_dim 的干员特效按同一系数降
		o.draw_fx_add(ci, loop)
	g.world.fx_dim = d0
	cv.mute = false
	cv.amul = 1.0


func draw_skill_over() -> void:
	cv.begin()
	var d0: float = g.world.fx_dim
	_pfx_cap_plan()
	for o in ops:
		_op_dim(o, d0)
		o._draw_skill_over()
		o.draw_pfx(false)
		o.pfx_skip = 0
	g.world.fx_dim = d0
	cv.mute = false
	cv.amul = 1.0
	cv.end()


## 干员粒子上层数量上限（docs/50 §15 D3，用户 10-14 批准；OPT_PCAP）：全队上层「可封顶的小粒子」（character.pfx_cappable）合计超过
## render/pfx_cap 时，超出的部分按各干员这类粒子的多少分摊，每人跳过自己最旧的那几个不画（最旧 = 寿命快到、透明度已降到最低的那批）。
## 常驻 / 循环帧条、加色层、keep 的提示环、剑雨等技能编排不计也不跳。只改绘制，粒子列表与寿命不变；0 = 不封顶
var _pcap := -1

func _pfx_cap_plan() -> void:
	if _pcap < 0:
		_pcap = int(Bal.v("render/pfx_cap", 0.0))
	if _pcap <= 0:
		return
	var ns: Array = []
	var tot := 0
	for o in ops:
		var n := 0
		for f in o.pfx:
			if not f.get("floor", false) and Character.pfx_cappable(f):
				n += 1
		ns.append(n)
		tot += n
	if tot <= _pcap:
		return
	var over: int = tot - _pcap
	var left: int = over
	for i in ops.size():
		var k: int = mini(left, ceili(float(over) * float(ns[i]) / float(tot)))
		ops[i].pfx_skip = k
		left -= k


## 后期降噪（render/declutter mate_k / lead_k）：画某名干员的特效阶段时，合批画布 cv 的每次绘制乘上队友 / 主控系数（cv.amul）；
## 加色层不经 cv，改乘 fx_dim。画完由调用方恢复。缺省两个系数恒 1 = 不变
func _op_dim(o, d0: float) -> void:
	g.world.fx_dim = d0
	cv.amul = g.world.lead_dim if o.is_leader else g.world.mate_dim   # 经 cv 的绘制统一乘（自定义干员脚本不读 fx_dim 的特效也算上）
	cv.mute = g.world._dbg_friend   # --clutterdbg=nofriend（量测）：这些阶段只有特效，整段不显示
