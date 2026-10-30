## 编队（docs/23 §3）：持有编队位上的干员实例，负责招募 / 替换、编队校验、跟随队形与统一的 update / draw 分发。
## 常规上限 3 人，第 4 位由事件 / 藏品 / 商店解锁（extra_slot）。干员没有生命值，敌人只追主控。
extends RefCounted

const BossBench = preload("res://scripts/run/boss_bench.gd")   # 录制钩子（docs/170）
const Character = preload("res://scripts/characters/character.gd")
const BatchCanvas = preload("res://scripts/characters/batch_canvas.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")

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
## 索敌优先级（指挥圆盘，docs/114 §13）：0 Boss 优先 / 1 清杂优先；只影响队友（op_api.prio_mode），队长恒为 0。
## 缺省 = command/priority_default（10-27 用户定改为 1 清杂优先，机器人也跟缺省；Boss 优先只在玩家圆盘里主动选时生效 = 全队集火，docs/114 §15）
## （10-24 用户定：去掉「就近」——它和 Boss 优先在有 Boss 时几乎一样）
const PRIO_NAMES := ["Boss 优先", "清杂优先"]
const PRIO_SHORT := ["Boss", "清杂"]
var priority: int = default_priority()
static func default_priority() -> int:
	return clampi(int(Bal.v("command/priority_default", 1.0)), 0, 1)
var stance := GUARD
var recall_t := 0.0
var gather_t := -1.0          # 归队：全员到位后站定的剩余秒数（-1 = 还在往回跑）
## 突击耐力（10-21 用户定）：全队共用 0–1。突击时按时间消耗（满 command/stamina_secs 秒），耗尽自动归队并进冷却；
## 不突击时慢慢回满（command/regen_secs 秒从空到满）；低于 command/min_start 不能发起突击。只按时间，不受敌人影响
var stamina := 1.0
var exhausted := false         # 耗尽后的冷却：回到 min_start 以上才解除（HUD 灰显）
var stance_log: Array = []     # [[g.t, 新站位], …]：玩家切换记录（同 seed 复现 / 机器人对照）
## 突击三件套（10-22 原型，docs/114 §7）：仇恨（突击队友引走一部分怪）、队友生命 + 倒地、耐力，各自开关 command/aggro、command/hp、command/stamina
const HP_K_DEF := {"重装": 1.2, "近卫": 0.9, "先锋": 0.8, "特种": 0.75, "辅助": 0.65, "医疗": 0.65, "术师": 0.5, "狙击": 0.5}
var lead_dir := Vector2.ZERO    # 队长移动方向（平滑后的单位向量，几乎不动时为 ZERO）：突击断后站位用（character.roam_target）
var _lead_v := Vector2.ZERO
var _lead_p := Vector2.INF
var roam_secs := 0.0           # 统计（cmd_stats）：突击累计秒数 / 倒地次数 / 掷中仇恨的怪数
var downs_n := 0
var sorties_n := 0             # 进入突击的次数；sortie_downs_n = 其中至少有一人倒地的次数（调血目标 10–20%）
var sortie_downs_n := 0
var _sortie_down := false
var aggro_n := 0
var gathered_n := 0            # 归队集合完毕（全员到位、开始站定）的次数：响应动作 on_stance to: gathered 的触发源（docs/118）


func _init(game) -> void:
	g = game
	cv = BatchCanvas.new(game)


func size() -> int:
	return ops.size()


## 编队位分配：队长恒为 0 号位（站在玩家位置），其余按入队顺序占 1.. 号位（切队长后不再等于数组下标，10-23）
func assign_slots() -> void:
	var k := 1
	for o in ops:
		if o.is_leader:
			o.slot = 0
		else:
			o.slot = k
			k += 1


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
	BossBench.rb("add", [cid, recruit_event])   # Boss 单场测试台录制（docs/170）：只记最外层
	var op = _add(cid, recruit_event)
	BossBench.re()
	return op


func _add(cid: String, recruit_event: bool):
	if has(cid) or is_full():
		return null
	if g.panel_ui != null:
		g.panel_ui.load_op_tex(cid)   # 手机网页开局只读队长的帧条（docs/50 §30），中途入队的这时补读；其余平台已读过，这里不做事
	var op = Character.create(g, cid)
	if op == null:
		return null
	op.slot = ops.size()
	op.is_leader = ops.is_empty()   # 开局干员 = 主控
	if op.is_leader:
		_apply_leader_regen(op)
	op.voice_t = g.vrng.randf_range(20.0, 40.0)   # 语音计时只影响声音（docs/101 §3.4 ④）
	if g.get("entry_voice_hold") != true:
		op.entry_started()   # 尚无独立 Start 动画：即时请求登场语音，后续动画通知不会重复；开局编队等画面出来再播（game.release_entry_voices）
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
	if recruit_event and not op.is_leader and g.state == g.S.PLAY and g.demo_op == "":
		op.arrive_t = op.ARRIVE_WAIT   # 局中招募：从屏幕上方落到编队位（不等，纯画面；换人在 replace 里从 0 起等被换下的跳出）
		op.play_entry(op.ARRIVE_FALL)   # 着地接入场条
	return op


## 移除（事件替换用）：被替换的干员成长清零
func remove(cid: String) -> void:
	for i in ops.size():
		if ops[i].id == cid:
			if g.get("telemetry") != null:
				g.telemetry.on_leave(cid)
			_leave_fx(ops[i])
			if ops[i].has_method("on_leave"):
				ops[i].on_leave()
			ops.remove_at(i)
			break
	if not ops.is_empty() and not ops.any(func(o): return o.is_leader):
		ops[0].is_leader = true
		_apply_leader_regen(ops[0])
	assign_slots()
	if not _hold_size:
		_apply_size_hp()
	if g.get("rfx") != null:
		g.rfx.refresh_squad()


## 队友离队 / 换人（10-22 用户定）：定格当前帧原地起跳，向上跳出屏幕（纯画面 g.fx kind "leave_jump"，world._draw_fx 画）
const LEAVE_JUMP := 0.5

func _leave_fx(o) -> void:
	if o.pos == Vector2.INF or g.get("fx") == null or g.demo_op != "":
		return   # 图鉴演示每段重建干员：旧实例直接消失，不播跳出屏幕（用户 10-24：切换会出现离场效果）
	var st: Dictionary = o.anim_state()
	if st.is_empty():
		return
	g.fx.append({"kind": "leave_jump", "pos": o.pos + Vector2(o.foot_dx(st), 0), "st": st, "foot_off": o.foot_off(st.tex, st.get("kind", "")), "life": LEAVE_JUMP, "max": LEAVE_JUMP})


var _hold_size := false   # replace 中途：人数先减后加，不重算入队加成（人数不变，台阶不变）


## 中途更换队友（用户 10-13 批准）：old_id 离队、new_id 接替它的编队位，继承 old 的成长节点数（精英化阶段 + 技能 / 成长节点），
## 继承的节点不看条件、不重播精英化演出。队长不能被替换。被换下的干员清掉它挂在 op:<id> 作用域上的修正，回到招募池。
## 人数不变 → 入队加成（最大生命 / 回复台阶）不重算，也不触发「招募」类藏品。失败返回 null
## route：分支培养（docs/119 §4.1）——换入会继承到节点 4 及以上时，在换人流程里选好的路线 id（progression.open_branch），继承按它一次性重建
func replace(old_id: String, new_id: String, route := ""):
	BossBench.rb("replace", [old_id, new_id, route])   # Boss 单场测试台录制（docs/170）
	var op = _replace(old_id, new_id, route)
	BossBench.re()
	return op


func _replace(old_id: String, new_id: String, route: String):
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
	assign_slots()
	op.pos = g.ppos + _slot_offset(op.slot)
	op.arrive_t = 0.0   # 等被换下的跳出屏幕后从上方落下（纯画面，character.arrive_dy）
	op.play_entry(op.ARRIVE_WAIT + op.ARRIVE_FALL)   # 着地接入场条
	var sq0: int = g.show_queue.size()
	if route != "":
		op.route = route
	for k in inherit:
		var n: Dictionary = op.next_node()
		if n.is_empty():
			break
		var chs: Dictionary = op.elite_choices(n) if n.get("type", "") == "elite" else {}
		var p0: int = op.prog
		op.advance(chs.keys()[0] if not chs.is_empty() else "")
		if op.prog == p0:
			break   # 没推进（分支节点在等玩家选路线）：不空转
	if g.show_queue.size() > sq0:
		g.show_queue.resize(sq0)   # 继承来的精英化不弹演出
	g.sync_stats()
	return op


## 入队加成（docs/83，用户 10-13 定：每入队一名干员，编队生命与自动回复各上一个台阶；招募时写明）。
## 每多 1 名干员（开局干员不算，最多算 squad/hp_member_cap 人）：
##   主控最大生命 ×(1 + squad/hp_per_member × 人数)（2026-09-27 用户定每人 +15%），对 max_hp 加来源 "squad" 的 mult（只乘基础值与百分比加成，固定加成「坚韧」等放在倍率之后不被放大，docs/199）；
##   主控生命回复 + squad/regen_per_member × 人数（生命 / 秒），对 regen 加来源 "squad" 的 flat，和干员 leader 段 regen、「自愈」同一个池，吃 heal_mult。
## 人数变化时当前生命按同比例缩放（入队不显示掉血，离队反向）
func _apply_size_hp() -> void:
	if g.stats == null or not g.stats.has_stat(&"max_hp"):
		return
	var per: float = Bal.v("squad/hp_per_member", 0.15)
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
	var rper: float = Bal.v("squad/regen_per_member", 0.15)
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
	var per: float = Bal.v("squad/hp_per_member", 0.15)
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
	# 主控自带的冲刺（10-29 用户「德克萨斯自带两个冲刺，距离略短」）：leader.dash {charges 额外次数, dist_mult 距离倍率}；换主控时一起换，冲刺卡的加层 / 加距离照常叠在上面
	var dh: Dictionary = op.def.get("leader", {}).get("dash", {})
	if g.stats.has_stat(&"dash_charges"):
		g.stats.set_base(&"dash_charges", 1.0 + float(dh.get("charges", 0)))
	if g.stats.has_stat(&"dash_dist"):
		g.stats.set_base(&"dash_dist", float(dh.get("dist_mult", 1.0)))
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

## ---- 连携技（docs/160）：状态在 syn（冷却 / 进行中的合击），逻辑在 synergy.gd；synergy/on = 0 时两个入口都直接返回
const Synergy = preload("res://scripts/characters/synergy.gd")
var syn := {"cd": {}, "acts": [], "n": 0}


func syn_skill(o, i: int) -> void:
	if g.ult != null:
		g.ult.on_skill(o, i)   # 技能连携（combo/skill_link，关时直接返回）
	if g.ult == null:   # ult/on：隐藏连携由连携技取代（docs/198 §10.3）
		Synergy.on_skill(self, o, i)


func update(dt: float) -> void:
	var pf: bool = g.prof_on   # --prof：编队段细分（sq_follow / sq_ticks / sq_op_<编号> / sq_pfx，docs/50 §35）
	var t0 := Time.get_ticks_usec() if pf else 0
	g.doctor.tick_input(dt)   # 按住瞄准 / 选落点蓄距离（契约 v2.5）
	side = move_toward(side, g.facing, dt * 2.5)
	if g.ult != null:
		g.ult.tick(dt)   # 终结技 / 连携技（docs/198）：在 follow 之前，连携位移当帧生效
	else:
		Synergy.tick(self, dt)
	var bl: bool = _blink_on()
	if bl:
		_blink_pre()
	for o in ops:
		o.follow(dt, g.ppos if o.is_leader else g.ppos + _slot_offset(o.slot))
	if bl:
		_blink_check(dt, "")
	if pf:
		t0 = g.prof_add("sq_follow", t0)
	if stance == RECALL:
		_tick_recall(dt)
	_tick_lead(dt)
	_tick_stamina(dt)
	_tick_order(dt)
	_tick_hp(dt)
	_tick_rush_buff()
	if pf:
		t0 = g.prof_add("sq_ticks", t0)
	for o in ops:
		if o.cmd_down > 0.0:
			continue   # 倒地：不充技力、不出手（docs/114 §7）
		o.tick_sp(dt)
		_battle_voice(o, dt)
		g.vfx.spawn_lead = o.is_leader   # 这段里生成的帧条特效记为队长的（docs/139 §11 突出队长；纯画面标记）
		o.update(dt)
		g.vfx.spawn_lead = false
		# 主控的技能位移（推进之王跃空锤）带着玩家一起走，位移中短暂无敌
		if o.is_leader and o.pos != Vector2.INF and o.pos.distance_to(g.ppos) > 0.5:
			g.ppos = o.pos
			g.invuln = maxf(g.invuln, 0.12)
			g.invuln_move_until = g.t + 0.12
		if pf:
			t0 = g.prof_add("sq_op_" + str(o.id), t0)
		o._tick_pfx(dt)
		if pf:
			t0 = g.prof_add("sq_pfx", t0)
	if bl:
		_blink_check(dt, "update")


## ---- 闪现遥测（10-28 用户「队友攻击时常常一下子闪现」，--blinklog，缺省关）：队友单帧位移超过「队长移速 × dt × 3」记一行 BLINK
## （src = follow 分支 / update 段的技能位移 / 外部改位；ext 由 _recall_blink / _revive 标）。只读位置，不改玩法
static var _blink_flag := -1
var _bl_ext := {}


static func _blink_on() -> bool:
	if _blink_flag < 0:
		_blink_flag = 1 if Cfg.dev_args().has("--blinklog") else 0
	return _blink_flag == 1


func _blink_pre() -> void:
	for o in ops:
		o.mv_src = ""   # bl_p 留着上一帧末的位置：输入里按归队的瞬回也算进本帧


func _blink_check(dt: float, phase: String) -> void:
	var lim: float = maxf(g.speed, 1.0) * dt * 3.0
	for o in ops:
		var p0: Vector2 = o.get_meta("bl_p", Vector2.INF)
		o.set_meta("bl_p", o.pos)
		if o.is_leader or p0 == Vector2.INF or o.pos == Vector2.INF:
			continue
		var d: float = p0.distance_to(o.pos)
		if d <= lim:
			continue
		var src: String = str(_bl_ext.get(o.id, ""))
		if src == "":
			src = o.mv_src if phase == "" else "update:" + str(o.get("act_kind")) + ("/sq" if o.get("sq_ph") != null and int(o.sq_ph) > 0 else "")
		print("BLINK t=%.2f id=%s st=%d src=%s d=%.0f lim=%.0f lead=%.0f dash=%d" % [g.t, o.id, stance, src, d, lim, o.pos.distance_to(g.ppos), 1 if g.dash_t > 0.0 else 0])
	_bl_ext.clear()


## ---------------------------------------------------------------- 指定队长（10-23 docs/128 的切换队长；玩家入口 10-27 关、10-29 删，docs/197 清理）
## 只剩内部接口：Boss 测试台 / 测试直接指定谁当队长。被指定的干员原地成为队长（玩家位置 = 他的位置），原队长原地变回队友；
## 镜头 0.25 秒缓动过去（game.swap_off）；队长生命整局共用；倒地的队友不能被指定
var swap_n := 0


func can_swap_to(o) -> bool:
	return o != null and not o.is_leader and o.cmd_down <= 0.0 and o.pos != Vector2.INF and g.state == g.S.PLAY and g.demo_op == ""


func swap_leader(o) -> bool:
	if not can_swap_to(o):
		return false
	var old = leader()
	if old == null or old == o:
		return false
	var old_p: Vector2 = g.ppos
	old.is_leader = false
	o.is_leader = true
	g.ch = o
	assign_slots()
	g.ppos = o.pos
	g.facing = o.face if o.face != 0.0 else g.facing
	g.swap_off = old_p - g.ppos   # 镜头从原来的位置缓动到新队长（game.cam_center）
	g.swap_t = 0.0
	old.roam_tgt = null
	old.cmd_hp = 1.0
	old.cmd_inv = 0.0
	o.roam_tgt = null
	o.cmd_hp = 1.0
	o.fp_moving = true
	if g.get("doctor") != null:
		g.doctor.charge = {}
		Sfx.loop_stop("ulp_charge_loop")
	swap_n += 1
	if g.get("rfx") != null:
		g.rfx.refresh_squad()
	if g.has_method("sync_stats"):
		g.sync_stats()
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 40.0, "life": 0.3, "max": 0.3, "col": o.col()})
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.voice(o.id, "command", false, true)   # 出击语音（指挥语音同一套，不受节流）
	if g.get("trace_every") != null and g.trace_every > 0.0:
		print("SWAP t=%.2f %s -> %s" % [g.t, old.id, o.id])
	return true


## 指挥模式总开关（balance command/on）
static func cmd_on() -> bool:
	return Bal.v("command/on", 1.0) > 0.0


## 指挥圆盘选中一项（command_wheel.confirm）：队形三项直接设，优先级三项设 priority；重复选当前项只出提示音，不换语音
func apply_command(id: String) -> void:
	if not cmd_on():
		return
	match id:
		"guard":
			if stance != GUARD:
				set_stance(GUARD)
		"roam":
			if stance != ROAM:
				if can_roam():
					set_stance(ROAM)
				elif g.get("vfx") != null:
					g.vfx.add_text(g.ppos + Vector2(0, -70), "作战时限未恢复", UI.SUB, 14)
		"recall":
			if stance != RECALL:
				set_stance(RECALL)
		"mob":
			set_priority(1)
		"boss":
			set_priority(0)
		"point", "clear", "focus":
			g.pick.begin(id)   # 原型：进入选点阶段（command_pick.gd）


## ---------------------------------------------------------------- 指点（示意原型，docs/196；command/target_proto = 0 时永远不会有指令）
## order_kind：""（无，原来的自动突击）/ "point"（移动：队友走到 order_pos 驻扎，10-30 起不再是作战圈）/ "clear"（肃清）/ "focus"（集火：全队打 order_target）
var order_kind := ""
var order_pos := Vector2.INF
var order_target = null
var _order_idle := 0.0


func apply_order(mode: String, pt: Vector2, target) -> bool:
	if not cmd_on():
		return false
	if stance != ROAM:
		if not can_roam():
			if g.get("vfx") != null:
				g.vfx.add_text(g.ppos + Vector2(0, -70), "作战时限未恢复", UI.SUB, 14)
			return false
		set_stance(ROAM)
	order_kind = mode
	order_pos = pt
	order_target = target if mode == "focus" else null
	order_beacon = null
	if mode == "point":
		# 移动指到未点燃的灯标附近（beacon/order_snap 60 内）：落点吸附到灯标中心，队友站进光圈读条（beacon.gd 的队友读条）
		var bl: Array = g.beacons if g.get("beacons") != null else []
		for b in bl:
			if not b.lit and not b.dead and b.pos.distance_to(pt) <= Bal.v("beacon/order_snap", 60.0):
				order_pos = b.pos
				order_beacon = b
				break
	_order_idle = 0.0
	_order_age = 0.0
	for o in ops:
		o.roam_tgt = null
	stance_log.append([g.t, {"point": 20, "focus": 21, "clear": 22}.get(mode, 20)])
	_stance_voice(ROAM, false)
	if g.get("trace_every") != null and g.trace_every > 0.0:
		print("CMD t=%.2f order=%s" % [g.t, mode])
	return true


var order_beacon = null   # 移动指到的灯标（吸附后）：点燃 / 熄灭前队友守在光圈里，不按「圈里没怪」归队

func clear_order() -> void:
	order_kind = ""
	order_pos = Vector2.INF
	order_target = null
	order_beacon = null
	_order_idle = 0.0


## 移动（驻扎）：只在队长走远（> order_break）时归队，其余等玩家下别的指令。
## 肃清（10-30 用户加）：圈（command/clear_r）里没有敌人超过 command/clear_idle 秒、或下令后 command/clear_secs 秒、或队长走远 → 回到随行（不空耗作战时限）。
## 集火目标死了 = 指令结束（继续自动突击）
func _tick_order(dt: float) -> void:
	_order_cd = maxf(0.0, _order_cd - dt)
	if order_kind == "":
		return
	if order_kind == "focus":
		if order_target == null or order_target.dead:
			clear_order()
		return
	var clr: bool = order_kind == "clear"
	_order_age += dt
	if order_beacon != null:
		if order_beacon.lit or order_beacon.dead:
			set_stance(GUARD)   # 灯标点燃 / 熄灭：回随行
		elif g.ppos.distance_to(order_pos) > Bal.v("command/order_break", 1400.0):
			set_stance(RECALL)
		return
	if not clr:
		# 移动 = 驻扎（10-30 用户「移动的范围是不是可以小很多？变成一个小点，并且干员会直接走过去驻扎」）：
		# 走到点上站定、自动攻击射程内的敌人，不再「圈空就归队」；只有玩家下别的指令、作战时限耗尽、或队长走出 order_break 才结束
		if g.ppos.distance_to(order_pos) > Bal.v("command/order_break", 1400.0):
			set_stance(RECALL)
		return
	var back: int = GUARD
	if g.ppos.distance_to(order_pos) > Bal.v("command/order_break", 1400.0) or _order_age >= Bal.v("command/clear_secs", 9.0):
		set_stance(back)
		return
	var any := false
	for e in g.enemies_sys.nearest(1, order_radius(), order_pos):
		any = not e.dead
	if any:
		_order_idle = 0.0
	else:
		_order_idle += dt
		if _order_idle >= Bal.v("command/clear_idle", 1.0):
			set_stance(back)


## 当前地面指令的作战圈半径：肃清 command/clear_r；移动是一个点（驻扎），返回 0
func order_radius() -> float:
	return Bal.v("command/clear_r", 220.0) if order_kind == "clear" else 0.0


## 机器人用指点（10-30 协调人：「机器人也要会用」，否则云端测的数不准；command/bot_point 0 = 关）：每 command/bot_point_every 秒看一次，
## 没有指令、冷却已过、作战时限够突击时：Boss（可受击、离队长 order_r × 1.6 内）在场 → 集火最近的 Boss；
## 否则有未点燃的灯标（离队长 order_r × 1.6 内、队长不在 bot/beacon_seek_r 内）→ 移动到灯标让队友去点；
## 否则队长 command/bot_surround_r 内敌人 ≥ command/bot_surround_n（被包围）→ 对 order_r 内最密的一块下「肃清」（clear_r 圈）。不抽随机数
var _order_cd := 0.0
var _order_age := 0.0
var _bot_pt_t := 0.0

func bot_point(dt: float) -> void:
	if Bal.v("command/bot_point", 1.0) <= 0.0 or not cmd_on() or g.demo_op != "":
		return
	_bot_pt_t -= dt
	if _bot_pt_t > 0.0:
		return
	_bot_pt_t = Bal.v("command/bot_point_every", 1.0)
	if order_kind != "" or _order_cd > 0.0 or stance == RECALL or not (stance == ROAM or can_roam()):
		return
	var orr: float = Bal.v("command/order_r", 560.0)
	var boss = null
	var bd: float = orr * 1.6
	for e in g.bosses:
		if e.dead or not e.boss or e.get("friendly", false) or not g.ch.focusable_boss(e):
			continue
		var d: float = e.pos.distance_to(g.ppos)
		if d < bd:
			bd = d
			boss = e
	if boss != null:
		if apply_order("focus", boss.pos, boss):
			_order_cd = Bal.v("command/order_cd", 3.0)
		return
	# 灯标：未点燃、离队长 order_r × 1.6 内、队长不在 bot/beacon_seek_r（300）内（没在去点）→ 移动到灯标，队友站圈读条（10-30 协调人）
	if g.get("beacons") != null:
		for b in g.beacons:
			if b.lit or b.dead:
				continue
			var dl: float = b.pos.distance_to(g.ppos)
			if dl <= orr * 1.6 and dl > Bal.v("bot/beacon_seek_r", 300.0):
				if apply_order("point", b.pos, null):
					_order_cd = Bal.v("command/order_cd", 3.0)
				return
	var near: Array = g.enemies_sys.nearest(Bal.v("command/bot_surround_n", 6.0), Bal.v("command/bot_surround_r", 240.0), g.ppos)
	if near.size() < int(Bal.v("command/bot_surround_n", 6.0)):
		return
	var pr: float = Bal.v("command/clear_r", 220.0)
	var pool: Array = g.enemies_sys.nearest(40, orr, g.ppos)
	var best := Vector2.INF
	var bc := -1
	for e in pool:
		if e.dead or e.boss:
			continue
		var c := 0
		for f in pool:
			if not f.dead and f.pos.distance_squared_to(e.pos) <= pr * pr:
				c += 1
		if c > bc:
			bc = c
			best = e.pos
	if best != Vector2.INF and apply_order("clear", best, null):
		_order_cd = Bal.v("command/order_cd", 3.0)


func set_priority(p: int) -> void:
	if p == priority:
		return
	priority = p
	stance_log.append([g.t, 10 + p])   # 与队形切换同表记录（>= 10 = 优先级），回放 / 对照用
	_stance_voice(ROAM)   # 复用指挥语音轮换（同一套「出击」回应，仍受 command/voice_gap 节流）
	if g.get("trace_every") != null and g.trace_every > 0.0:
		print("CMD t=%.2f priority=%d" % [g.t, p])


## 玩家按「指挥」键：随行 → 突击 → 归队；归队途中再按 = 突击。返回是否切换了（圆盘上线后键盘不再走这条，保留给测试钩子 --cmdat）
func cycle_stance() -> bool:
	if not cmd_on():
		return false
	if stance != ROAM and not can_roam():
		return false   # 耐力不足（game.toggle_command 提示）
	set_stance(ROAM if stance != ROAM else RECALL)
	return true


func can_roam() -> bool:
	return not stamina_on() or (stamina >= Bal.v("command/min_start", 0.3) and not exhausted)


static func stamina_on() -> bool:
	return Bal.v("command/stamina", 1.0) > 0.0


static func aggro_on() -> bool:
	return Bal.v("command/aggro", 1.0) > 0.0


static func hp_on() -> bool:
	return Bal.v("command/hp", 1.0) > 0.0


## 队友生命上限：队长当前生命上限 × 职业系数（json command.hp_k 可单独覆盖；缺省按 HP_K_DEF，balance command/hp_k_<职业> 可调）
func op_maxhp(o) -> float:
	var k: float = float(o.def.get("command", {}).get("hp_k", Bal.v("command/hp_k_" + str(o.cls), HP_K_DEF.get(o.cls, 0.7))))
	return maxf(1.0, g.max_hp * k * Bal.v("command/hp_mul", 4.0))


## 能吸引仇恨 / 会受伤的队友：突击中、肯出击、没倒地
func roaming_op(o) -> bool:
	return stance == ROAM and not o.is_leader and o.cmd_down <= 0.0 and o.pos != Vector2.INF and o.cmd_roam()


## 仇恨（A 段逐只调用，enemies.gd）：突击中半径 command/aggro_r 内最近的突击队友；本只第一次进圈时用 rng_enemy 掷一次，
## 小于 command/aggro_share 的改追这名队友（之后一直按这次结果）。不在突击 / 关着时返回 null，且不抽随机数
func aggro_target(e: Dictionary):
	if stance != ROAM or not aggro_on() or e.boss or e.chest:
		return null
	var best = null
	var bd: float = Bal.v("command/aggro_r", 240.0)
	bd *= bd
	for o in ops:
		if not roaming_op(o):
			continue
		var d: float = o.pos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = o
	if best == null:
		return null
	if not e.has("cmd_roll"):
		e["cmd_roll"] = g.rng_enemy.randf()
		if float(e.cmd_roll) < Bal.v("command/aggro_share", 0.4):
			aggro_n += 1
	return best if float(e.cmd_roll) < Bal.v("command/aggro_share", 0.4) else null


## 队友生命：突击中被近战怪碰到掉血（每人 command/op_inv 秒无敌间隔）；不突击时回血（command/hp_regen_secs 空到满）；
## 血空倒地 command/revive_secs 秒，到时原地复活；归队集合完毕时倒地的人在队长身边复活。复活给 command/revive_inv 秒无敌
func _tick_hp(dt: float) -> void:
	_tick_low()
	if stance == ROAM:
		roam_secs += dt
	for o in ops:
		if o.is_leader:
			continue
		o.cmd_inv = maxf(0.0, o.cmd_inv - dt)
		o.cmd_show = maxf(0.0, o.cmd_show - dt)
		if o.cmd_down > 0.0:
			o.cmd_down_age += dt
			# 队长站到身边（command/revive_near 内）复活计时加速 command/revive_near_k 倍（10-23）
			var nk: float = Bal.v("command/revive_near_k", 4.0) if o.pos.distance_to(g.ppos) <= Bal.v("command/revive_near", 64.0) else 1.0
			o.cmd_down -= dt * nk
			if o.cmd_down <= 0.0:
				_revive(o, o.pos)
			continue
		if not hp_on():
			continue
		if stance != ROAM:
			o.cmd_hp = minf(1.0, o.cmd_hp + dt / maxf(0.1, Bal.v("command/hp_regen_secs", 30.0)))
			continue
		if not roaming_op(o) or o.cmd_inv > 0.0:
			continue
		for e in g.enemies_sys.nearest(4, 60.0, o.pos):
			if e.dmg > 0.0 and e.ai == "melee" and not e.get("coma", false) and not e.get("dormant", false) and o.pos.distance_to(e.pos) < e.r + 12.0:
				o.cmd_hp -= e.dmg * Bal.v("command/op_dmg_k", 1.0) / op_maxhp(o)
				o.cmd_inv = Bal.v("command/op_inv", 0.5)
				o.cmd_show = 3.0
				o.cmd_hit_t = g.t
				if o.cmd_hp <= 0.0:
					o.cmd_hp = 0.0
					o.cmd_down = Bal.v("command/revive_secs", 25.0)
					o.cmd_down_age = 0.0
					o.roam_tgt = null
					downs_n += 1
					if not _sortie_down:
						_sortie_down = true
						sortie_downs_n += 1
					if g.get("trace_every") != null and g.trace_every > 0.0:
						print("CMD t=%.2f down %s" % [g.t, o.id])
				break


## 队友残血提醒（10-31 用户，docs/114 §21）：血量跌破 command/low_hp 进入提醒（头顶条 / 编队卡 / 屏外箭头红色慢闪，hud_allyhp），
## 回到 command/low_hp_off 以上解除（两条线防止在线上反复闪）；倒地时清掉（倒地另有显示）。
## 每次进入时该队友说一句 lowhp 语音：同一人 sfx.VOICE_CD.lowhp 秒冷却、占线就放弃（不打断别人）；没有 <干员>_lowhp 素材就不放
var _low_banner_t := {}   # 干员 id → 上次残血横幅的 g.t

func _tick_low() -> void:
	var on: bool = hp_on() and cmd_on()
	var lo: float = Bal.v("command/low_hp", 0.3)
	var hi: float = Bal.v("command/low_hp_off", 0.4)
	for o in ops:
		if o.is_leader or not on or o.cmd_down > 0.0:
			o.cmd_low = false
			continue
		if o.cmd_low:
			if o.cmd_hp >= hi:
				o.cmd_low = false
		elif o.cmd_hp < lo:
			o.cmd_low = true
			if g.get("trace_every") != null and g.trace_every > 0.0:
				print("CMD t=%.2f low %s" % [g.t, o.id])
			var sfx: Node = g.get_node_or_null("/root/Sfx")
			if sfx != null and g.demo_op == "":
				sfx.voice(o.id, "lowhp")
			# 弹字（10-31 用户「这些都不太行，不明显，我觉得不如弹文字提醒」）：屏幕中间横幅，同「生命垂危」一级（prio 2，不受横幅间隔）；同一人 command/low_banner_cd 秒内只弹一次
			if g.t - float(_low_banner_t.get(o.id, -999.0)) >= Bal.v("command/low_banner_cd", 20.0):
				_low_banner_t[o.id] = g.t
				g.vfx.show_banner("%s 生命垂危" % o.display_name(), 2)


## 归队瞬回（10-22 用户定）：按下归队，离站位远的队友原地放共用退场闪光、直接出现在队长身边（落点一圈光），1 秒无敌；
## 倒地的人也一起回位，继续复活计时。之后照常集合站定再回随行
func _recall_blink() -> void:
	var lim: float = Bal.v("command/recall_done", 28.0)
	for o in ops:
		if o.is_leader or o.pos == Vector2.INF:
			continue
		if o.cmd_down > 0.0:
			continue   # 倒地的留在倒地点，复活计时照走（10-23 用户实测：不跟着漂）
		var dst: Vector2 = g.ppos + _slot_offset(o.slot)
		o.cmd_inv = maxf(o.cmd_inv, Bal.v("command/recall_inv", 1.0))
		o.roam_tgt = null
		if o.pos.distance_to(dst) <= lim:
			continue
		_bl_ext[o.id] = "recall_blink"
		blink_fx(o, dst)
		o.pos = dst


## 瞬移的出现 / 消失特效（归队瞬回、超出 leash 的掉队归位共用）：原地放退场闪光，落点一圈光；清残影免得拖一道线
func blink_fx(o, dst: Vector2) -> void:
	_leave_fx(o)
	o.ghosts.clear()
	if g.get("fx") != null:
		g.fx.append({"kind": "ring", "pos": dst, "r": 34.0, "life": 0.35, "max": 0.35, "col": Color(0.85, 0.95, 1.0)})


## 突击 / 归队语音（10-22 用户确认）：队长优先、按编队轮换；非突击型随从与倒地干员不回应。
## 突击播已确认的 *_command 短回应，归队仍播 *_entry；队长不受职业是否突击的限制。
## 走 Sfx 语音通道（占线放弃、每人 15 秒间隔、整体 3 秒间隔照旧），另按 command/voice_gap 节流，连按不刷屏。纯声音，不碰玩法状态
## 10-28 起走合唱：出击队友各自开口、错开 voice_stagger 秒，见 sfx.voice_chorus、docs/114 §20.3
var _vo_i := 0
var _vo_t := -999.0

func _stance_voice(s: int, shout := false) -> void:
	if s != ROAM:
		return   # 10-29 用户「归队的时候不要语音了」：只有突击开口，归队 / 随行静默（也不占 voice_gap 节流）
	if g.demo_op != "" or g.t - _vo_t < Bal.v("command/voice_gap", 6.0):
		return
	var eligible: Array = ops.filter(func(o): return o.cmd_down <= 0.0 and (o.is_leader or o.cmd_roam()))
	var order: Array = eligible.filter(func(o): return o.is_leader) + eligible.filter(func(o): return not o.is_leader)
	# 10-26 用户「切突击放这名队友自己的语音，别放成队长的」：出击的是队友，按编队序轮换放他们各自的「出击」；没有可出击的队友才轮到队长
	var mates: Array = eligible.filter(func(o): return not o.is_leader)
	if not mates.is_empty():
		order = mates
	if order.is_empty():
		return
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	var key := "command"
	# 合唱（10-28 用户「两名队友的台词可以交替或一起喊」）：交替——轮换谁先开口，其余依次晚 voice_stagger 秒（0.4），
	# 允许尾部重叠；重叠时每条压 voice_duck_db
	var first: int = _vo_i % order.size()
	var who: Array = order.slice(first) + order.slice(0, first)
	_vo_i += 1
	_vo_t = g.t
	var fallback := false
	for i in who.size():
		var o = who[i]
		if sfx != null:
			sfx.voice_chorus(o.id, key, i * Bal.v("command/voice_stagger", 0.4), Bal.v("command/voice_duck_db", -3.0))
		if shout and o.pos != Vector2.INF:
			# 爆发窗口喊话（10-24）：头顶短字「出击」；这名干员没有对应语音素材就补一声通用音效（一次喊话只补一声）
			if g.get("vfx") != null:
				g.vfx.add_text(o.pos + Vector2(0, -78), "出击", Color(1.0, 0.82, 0.3), 16)
			if sfx != null and not sfx.has_voice(o.id, key):
				fallback = true
	if fallback:
		sfx.play("swing_heavy", -4.0)


func _tick_lead(dt: float) -> void:
	if _lead_p != Vector2.INF and dt > 0.0:
		_lead_v = _lead_v.lerp((g.ppos - _lead_p) / dt, clampf(dt * 4.0, 0.0, 1.0))
	_lead_p = g.ppos
	lead_dir = _lead_v.normalized() if _lead_v.length() > 30.0 else Vector2.ZERO


func cmd_stats() -> Dictionary:
	return {"roam": snappedf(roam_secs, 0.1), "downs": downs_n, "aggro": aggro_n, "switch": stance_log.size(), "sorties": sorties_n, "sortie_downs": sortie_downs_n}


func _revive(o, p: Vector2) -> void:
	if g.get("trace_every") != null and g.trace_every > 0.0:
		print("CMD t=%.2f revive %s at %.0f,%.0f" % [g.t, o.id, p.x, p.y])
	o.cmd_down = 0.0
	o.cmd_hp = maxf(o.cmd_hp, Bal.v("command/revive_hp", 0.5))
	o.cmd_inv = Bal.v("command/revive_inv", 1.0)
	o.cmd_show = 3.0
	_bl_ext[o.id] = "revive"
	o.pos = p


## ---- 爆发窗口（10-24 用户定：突击 = 队友出击时攻速和技力回复明显加成 + 第一下冲锋带击退，耐力照旧限时）
static func rush_on() -> bool:
	return Bal.v("command/rush", 1.0) > 0.0


var _rush_buffed: Array = []   # 当前挂着「command」加成的干员 id

## 每帧对账：突击中、肯出击、没倒地的队友挂攻速 / 技力回复 mult（来源 command，作用域 op:<id>），其余撤掉；退出突击立即全撤
func _tick_rush_buff() -> void:
	var want: Array = []
	if stance == ROAM and rush_on() and cmd_on():
		for o in ops:
			if roaming_op(o):
				want.append(o.id)
	if want == _rush_buffed:
		return
	_rush_buffed = want
	g.stats.remove_source("command")
	for cid in want:
		if g.stats.has_stat(&"op_aspd"):
			g.stats.add(&"op_aspd", "mult", 1.0 + Bal.v("command/rush_aspd", 0.25), "command", "op:" + cid)
		if g.stats.has_stat(&"op_skill_sp"):
			g.stats.add(&"op_skill_sp", "mult", Bal.v("command/rush_sp", 1.5), "command", "op:" + cid)


## 加成说明（状态栏 / 属性面板）：不在爆发窗口里返回空串
func rush_text() -> String:
	if _rush_buffed.is_empty():
		return ""
	return "攻速 +%d%% · 技力回复 ×%s" % [roundi(Bal.v("command/rush_aspd", 0.25) * 100.0), _num(Bal.v("command/rush_sp", 1.5))]


## 切到突击那一刻：每名出击的队友朝自己的目标冲一段（character.begin_rush）
func _rush_start() -> void:
	if not rush_on() or g.demo_op != "":
		return
	for o in ops:
		if roaming_op(o):
			o.begin_rush()


## 耐力：突击扣、其余回；耗尽 → 自动归队（走集合那套）+ 冷却。机器人突击常开（command/bot_roam）时随行中耐力够了就再突击
func _tick_stamina(dt: float) -> void:
	if stance == ROAM and stamina_on():
		stamina -= dt / maxf(0.1, Bal.v("command/stamina_secs", 25.0))
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
			set_stance(RECALL)
		return
	stamina = minf(1.0, stamina + dt / maxf(0.1, Bal.v("command/regen_secs", 50.0)))
	if exhausted and stamina >= Bal.v("command/min_start", 0.3):
		exhausted = false
	# 机器人等耐力回满（command/bot_roam_at，缺省 1.0）才再出击：每次都是完整的作战时限，倒地率按「每次出击」统计才有意义
	if stance == GUARD and g.get("bot") != null and Bal.v("command/bot_roam", 0.0) > 0.0 and cmd_on() and can_roam() and (not stamina_on() or stamina >= Bal.v("command/bot_roam_at", 1.0)):
		set_stance(ROAM)


func set_stance(s: int) -> void:
	if s == stance:
		return
	stance = s
	if s != ROAM:
		clear_order()   # 指点（原型，docs/196）：不在突击就没有指令
	if s == ROAM:
		sorties_n += 1
		_sortie_down = false
	elif s == RECALL:
		_recall_blink()
	if s == ROAM:
		_rush_start()
	if s == ROAM or s == RECALL:
		_stance_voice(s, s == ROAM)
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
			if not o.is_leader and o.cmd_down <= 0.0 and o.cmd_d > lim:
				done = false
				break
	if done:
		gather_t = Bal.v("command/gather", 0.4)
		gathered_n += 1


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
		var alt = o.def.get("voice_alt", {}).get("battle", null)   # voice_alt：干员 json（维什戴尔四成换成 W 的笑声）
		sfx.voice(o.id, str(alt[0]) if alt != null and g.vrng.randf() < float(alt[1]) else "battle")


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
	if g.ult != null and g.t < float(g.ult.ev.get("undying_until", -1.0)):
		g.hp = 1.0   # 归溟幽灵鲨连携（docs/198 §5.2）：这段时间里队长生命不会低于 1
		return true
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

## 干员特效绘制顺序（docs/139 §11，render/lead_top 1）：队长排最后 = 画在队友特效上面；0 = 原顺序
func _fx_order() -> Array:
	if Bal.v("render/lead_top", 0.0) <= 0.0:
		return ops
	var out: Array = []
	var ld = null
	for o in ops:
		if o.is_leader:
			ld = o
		else:
			out.append(o)
	if ld != null:
		out.append(ld)
	return out


func draw_auras() -> void:
	cv.begin()
	var d0: float = g.world.fx_dim
	for o in _fx_order():
		_op_dim(o, d0)
		o.draw_auras()
	g.world.fx_dim = d0
	cv.mute = false
	cv.set_mod(1.0, 0.0)
	cv.end()


## 紧贴地砖的常驻帧条（docs/61 §5.6 layer = ground，10-12 加）：world.draw_world 画完地砖就调，在溟痕 / 地面预警 / 掉落之下
func draw_ground_fx() -> void:
	cv.begin()
	var d0: float = g.world.fx_dim
	for o in _fx_order():
		if o.has_method("draw_ground_fx"):
			_op_dim(o, d0)
			o.draw_ground_fx()
	g.world.fx_dim = d0
	cv.mute = false
	cv.set_mod(1.0, 0.0)
	cv.end()


func draw_entities_floor() -> void:
	cv.begin()   # 合批（性能 9/30）：几何图形攒成一批，画贴图前自动提交
	var d0: float = g.world.fx_dim
	for o in _fx_order():
		_op_dim(o, d0)
		o.draw_entities_floor()
		o.draw_pfx(true)
	g.world.fx_dim = d0
	cv.mute = false
	cv.set_mod(1.0, 0.0)
	cv.end()


func draw_shadows() -> void:
	cv.begin()
	for o in _fx_order():
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
	# 出手方向弧（docs/139 §11，render/lead_dir 1）：脚下椭圆外沿一段 36° 暖白短弧指向当前出手方向——按住瞄准 = 瞄准方向，
	# 自动攻击 = 最近 0.8 秒内一次命中的方向（没有就不画）；常亮不闪
	if Bal.v("render/lead_dir", 0.0) > 0.0 or g.world.lead_lv >= 2:
		var adir := Vector2.ZERO
		if g.doctor != null and g.doctor.aim_held():
			adir = g.doctor.attack_dir()
		elif g.t - g.vfx.lead_hit_t < 0.8:
			adir = g.vfx.lead_hit_dir
		if adir != Vector2.ZERO:
			var aa: float = adir.angle()
			cv.draw_set_transform(o.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
			cv.draw_arc(Vector2.ZERO, 38.0, aa - 0.32, aa + 0.32, 10, dark, 5.0)
			cv.draw_arc(Vector2.ZERO, 38.0, aa - 0.32, aa + 0.32, 10, Color(1.0, 0.82, 0.5, 0.95), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	cv.end()


func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	var d0: float = g.world.fx_dim
	for o in _fx_order():
		_op_dim(o, d0)
		g.world.fx_dim = d0 * cv.amul   # 加色层直接画在 ci（不经 cv）：读 fx_dim 的干员特效按同一系数降
		o.draw_fx_add(ci, loop)
	g.world.fx_dim = d0
	cv.mute = false
	cv.set_mod(1.0, 0.0)


func draw_skill_over() -> void:
	cv.begin()
	var d0: float = g.world.fx_dim
	_pfx_cap_plan()
	for o in _fx_order():
		_op_dim(o, d0)
		o._draw_skill_over()
		o.draw_pfx(false)
		o.pfx_skip = 0
	g.world.fx_dim = d0
	cv.mute = false
	cv.set_mod(1.0, 0.0)
	cv.end()


## 干员粒子上层数量上限（docs/50 §15 D3，用户 10-14 批准；OPT_PCAP）：全队上层「可封顶的小粒子」（character.pfx_cappable）合计超过
## render/pfx_cap 时，超出的部分按各干员这类粒子的多少分摊，每人跳过自己最旧的那几个不画（最旧 = 寿命快到、透明度已降到最低的那批）。
## 常驻 / 循环帧条、加色层、keep 的提示环、剑雨等技能编排不计也不跳。只改绘制，粒子列表与寿命不变；0 = 不封顶
var _pcap := -1

func _pfx_cap_plan() -> void:
	if _pcap < 0:
		_pcap = int(Bal.v("render/pfx_cap", 30.0))
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
	# 经 cv 的绘制统一乘（自定义干员脚本不读 fx_dim 的特效也算上）：透明度（拥挤降噪）、队友去饱和（docs/139 §10，缺省关）、
	# 队长提亮 / 暖色（docs/139 §11 render/lead_emph，缺省关）
	if o.is_leader:
		cv.set_mod(g.world.lead_dim, 0.0, g.world.lead_boost, g.world.lead_tint)
	else:
		cv.set_mod(g.world.mate_dim, g.world.mate_desat)
	cv.mute = g.world._dbg_friend   # --clutterdbg=nofriend（量测）：这些阶段只有特效，整段不显示
