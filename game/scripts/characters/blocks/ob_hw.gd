## 干员积木 · ob_hw（docs/101 §7.3 B6 ①，10-15：由 op_blocks.gd 按段拆出，内容与注释照搬；继承链与门面见 op_blocks.gd）
extends "res://scripts/characters/blocks/ob_elite.gd"


# ================================================================ 手写迁移段（精英化第 2 批：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安，docs/91 §19 批 2；docs/61 §17）
# 只往后加。四名手写干员迁到积木时缺的积木 / 参数都在这里；手写参照在 tests/data_ops/<id>_legacy.gd（check.py blocks_eq 同 seed 逐行对照）。
# 运行时状态在干员的 hw 字典（data_operator.gd var hw）：没用到本段的数据干员 hw 为空，本段的分支一个都不走（同 seed 逐行不变）。
# 确定性：玩法随机只在手写版也取 g.rng 的地方取（同样的次数、同样的顺序）；画面一律 g.vrng。
#
# 基础（任何数据干员都能用）：
#  blocks.follow {leash, gap}     近战前压：队友时站到队长 leash 内最近敌人的身前 gap 处（character.melee_spot）
#  blocks.hit_fx [fx…]            本干员每打中一名敌人（melee_hit / area_hit）在它身上播的画面
#  attack.first / idle            首击冷却 / 没目标时的重试间隔（缺省 0.5 / 0.2）
#  attack.anim / turn             普攻播的帧条（sprites 键）/ false = 起手不转身（swap_attack 换上的形状也能写）
#  attack.combo [{cond, delay, do}]  连斩：普攻出手后第 1 段 cond 成立就 delay 秒后执行它的 do，执行完再看下一段；最后一段执行完（或第 1 段不成立）触发 trig.on_combo_end
#  trig.on_combo_end              一轮连斩收尾（basis attack = 这一轮普攻的伤害）
#  形状参数 basis                 attack（本轮普攻这一下的伤害）/ prev（上一个伤害形状这一下的伤害）/ hit（触发事件的伤害：弹体命中、爆炸）× mult
#  shape.cone 参数                origin_off [x, y]（判定原点偏移）、aim_pad（找目标的半径 = r + aim_pad，缺省 30）、face（true / 条件串：朝目标转身）、
#                                 dir: back（本次普攻的反方向）、half（半角弧度）、ring: false
#  shape.circle / cone 参数       r_mult（半径 × op_range × r_mult）
#  trig.tick 参数 countdown       倒计时：生效当帧起算 every 秒，到点执行并重置为 every（手写干员的计时写法）
#  verb.buff_self 局部 mult + power   局部倍率也吃技能强度（例：潮汐期间普攻 ×1.5 × 技能强度）
#  技能积木 aim: nearest + aim_r   起手朝 aim_r（世界像素）内最近的敌人
#  fx 程序条目 blade / aura_ring / outline（见 hw_fx_spawn / hw_draw_rings / hw_draw_outline）
# 斯卡蒂：shape.wave（推进的浪墙）

const HW_TAGS := ["shape.wave", "trig.on_combo_end"]

const HW_FX_KINDS := ["blade", "aura_ring", "outline", "slam", "whirl"]

const HW_FX_COMMON := ["cond", "if_tex", "at", "off", "fade", "_doc"]

const HW_WAVE_MAX := 2           # 同时推进的浪墙上限（手写 skadi WAVE_MAX）


## 本段状态（data_operator.hw）；on = 本干员用到了本段
static func hw_st(o) -> Dictionary:
	if o.hw.is_empty():
		o.hw.merge({"on": true, "atk_dmg": 0.0, "atk_ang": 0.0, "atk_c": Vector2.INF, "prev_dmg": 0.0, "prev_ang": 0.0, "prev_r": 0.0, "prev_c": Vector2.INF,
			"hit_dmg": 0.0, "cc": {}, "waves": []})
	return o.hw


static func hw_on(o) -> bool:
	var h = o.get("hw")
	return h is Dictionary and not h.is_empty()


## data_operator._init：本干员 JSON 用到本段的积木 / 参数时打开 hw
static func hw_init(o) -> void:
	if not _hw_uses(o.B):
		return
	hw_st(o)
	var tags := {}
	_hw_tags(o.B, tags)
	for t in tags:   # 各段的状态一开始就建好（免得「第一次用到才建」时，之前的询问读不到）
		if t in HW2_TAGS:
			_F()._hw2(o)
		elif t in HW3_TAGS:
			_F()._hw3(o)
		elif t in HW4_TAGS:
			_F()._hw4(o)
		elif t in HW5_TAGS:
			_hw5(o)
	h3_init(o, tags)   # 手写迁移段第 3 批
	h4_init(o, tags)   # 手写迁移段第 4 批
	if o.B.get("attack", {}).has("lob"):
		_hw5(o)


static func _hw_tags(n, out: Dictionary) -> void:
	if n is Dictionary:
		if n.has("_tag"):
			out[str(n._tag)] = true
		for k in n:
			_hw_tags(n[k], out)
	elif n is Array:
		for x in n:
			_hw_tags(x, out)


static func _hw_uses(n) -> bool:
	if n is Dictionary:
		for k in n:
			if k in ["follow", "basis", "combo", "countdown", "origin_off", "aim_pad", "hit_fx", "cast", "pulses"]:
				return true
			if k == "_tag" and (str(n[k]) in HW_TAGS or str(n[k]) in HW2_TAGS or str(n[k]) in HW3_TAGS or str(n[k]) in HW4_TAGS or str(n[k]) in HW5_TAGS or str(n[k]) in H3_TAGS or str(n[k]) in H4_TAGS):
				return true
			if _hw_uses(n[k]):
				return true
	elif n is Array:
		for x in n:
			if _hw_uses(x):
				return true
	return false


## basis 的值：attack = 本轮普攻这一下的伤害；prev = 上一个伤害形状；hit = 触发事件的伤害
static func hw_basis(o, k: String) -> float:
	if not hw_on(o):
		return 0.0
	match k:
		"attack":
			return float(o.hw.atk_dmg)
		"prev":
			return float(o.hw.prev_dmg)
		"hit":
			return float(o.hw.hit_dmg)
		"atk":   # 逻各斯段：攻击值（base × 加成 × attack.atk_mults）
			return _F().hw_atk(o)
	return 0.0


## 伤害形状执行后记一笔（data_operator.atk_live = 普攻出手的那一下时同时记成 attack）
static func hw_record(o, dmg: float, ang: float, r: float, c: Vector2) -> void:
	if not hw_on(o):
		return
	var h: Dictionary = o.hw
	h.prev_dmg = dmg
	h.prev_ang = ang
	h.prev_r = r
	h.prev_c = c
	if o.get("atk_live") == true:
		h.atk_dmg = dmg
		h.atk_ang = ang
		h.atk_c = c


## 延迟执行（every_n delay / 连斩）要带着的 basis 快照
static func hw_snap(o) -> Dictionary:
	if not hw_on(o):
		return {}
	var h: Dictionary = o.hw
	return {"atk_dmg": h.atk_dmg, "atk_ang": h.atk_ang, "atk_c": h.atk_c, "prev_dmg": h.prev_dmg, "prev_ang": h.prev_ang, "prev_r": h.prev_r, "prev_c": h.prev_c, "hit_dmg": h.hit_dmg}


## 换上快照（返回原值，执行完 hw_pop 还原）
static func hw_push(o, snap: Dictionary) -> Dictionary:
	if snap.is_empty() or not hw_on(o):
		return {}
	var keep := hw_snap(o)
	o.hw.merge(snap, true)
	return keep


static func hw_pop(o, keep: Dictionary) -> void:
	if not keep.is_empty():
		o.hw.merge(keep, true)


static func hw_off(b: Dictionary) -> Vector2:
	var v = b.get("origin_off", null)
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO


## face：布尔，或条件串（缓存解析结果）
static func hw_face_ok(o, v) -> bool:
	if v is bool:
		return v
	if v is Dictionary:
		return cond_true(o, v)
	if not (v is String):
		return false
	var cc: Dictionary = hw_st(o).cc
	if not cc.has(v):
		cc[v] = parse_cond(v, o.def.get("base", {}))
	return cond_true(o, cc[v])


# ---------------------------------------------------------------- 连斩（attack.combo / trig.on_combo_end）

## 普攻出手后（data_operator._release 末尾）：第 1 段成立就排进延迟队列，否则这一击就是收尾
static func hw_combo_start(o) -> void:
	var a: Dictionary = o.B.get("attack", {})
	if not a.has("combo"):
		return
	_hw_combo_from(o, a.combo, 0)


static func _hw_combo_from(o, cb: Array, k: int) -> void:
	if k < cb.size() and cond_true(o, cb[k].get("cond", _ED)):
		o.pending.append({"t": float(cb[k].get("delay", 0.12)), "do": cb[k].get("do", []), "combo": k, "bs": hw_snap(o)})
	else:
		hw_combo_end(o)


## 第 k 段执行完（data_operator._tick_pending）：下一段 / 收尾
static func hw_combo_next(o, k: int) -> void:
	_hw_combo_from(o, o.B.get("attack", _ED).get("combo", []), k + 1)


static func hw_combo_end(o) -> void:
	for t in o._trigs():
		if str(t.get("_tag", "")) == "trig.on_combo_end" and cond_true(o, t.get("cond", _ED)):
			o._exec_list(t.get("do", []))


# ---------------------------------------------------------------- 每帧（data_operator.update：技能计时之后、延迟队列之前）

## 返回 true = 本帧不再起手（手写干员的「这件事没做完就 return」）
static func hw_tick(o, dt: float) -> bool:
	if not hw_on(o):
		return false
	var h: Dictionary = o.hw
	var b3 := false
	if h3_on(o):   # 手写迁移段第 3 批（各人手写 update 的先后；true = 本帧不起手：替身在场 / 倒下中）
		b3 = h3_tick(o, dt)
	if h4_on(o):   # 手写迁移段第 4 批（true = 本帧不起手：跃空锤在空中）
		b3 = h4_tick(o, dt) or b3
	if h.has("anchor"):   # 乌尔比安段：计时 → 锚 → 掀飞（手写 update 开头的先后）
		_F()._hw4_tick(o, dt)
	if not h.waves.is_empty():
		_F()._hw_waves(o, dt)
	if h.has("bolts"):   # 逻各斯段：锁定 → 咒域（手写 update 的先后：锁定、咒域、地面咒文、咒文弹）
		if not h.lock.is_empty():
			_F()._hw3_lock(o, dt)
		if not h.fan.is_empty():
			_F()._hw3_fan(o, dt)
	var busy := false
	if h.has("shells"):   # 艾雅法拉段：地面 / 点燃 / 抛射 / 后续弹 / 喷发；喷发序列期间不起手
		busy = _F()._hw2_tick(o, dt)
	if h.has("bolts"):
		_F()._hw3_bolts(o, dt)
	if h.has("links"):   # 精英化第 2 批段：咒文链、低弧抛射、掷锚
		_hw5_tick(o, dt)
	return busy or b3


## 延迟队列之后、起手之前再问一次：这件事没做完就不起手（锚在外面）
static func hw_busy(o) -> bool:
	return _F().hw4_busy(o)


## 技能上层（data_operator._draw_skill_over）
static func hw_draw_over(o) -> void:
	_F().hw_draw_shells(o)
	if o.hw.has("links"):   # 精英化第 2 批段
		_F().hw_draw_lobs(o)
		_F().hw_draw_links(o)
		_F().hw_draw_runes(o)
		_F().hw_draw_hooks(o)
	if o.hw.has("anchor"):
		_F().hw_draw_tether(o)
	if o.hw.has("bolts"):
		_F().hw_draw_logos_over(o)
	h3_draw_over(o)   # 手写迁移段第 3 批
	if h4_on(o):
		h4_draw_over(o)   # 手写迁移段第 4 批


## 区域层（data_operator.draw_auras）
static func hw_draw_auras(o) -> void:
	h3_draw_auras(o)   # 手写迁移段第 3 批
	if h4_on(o):
		h4_draw_auras(o)   # 手写迁移段第 4 批
	_F().hw_draw_pulse_ring(o)
	_F().hw_draw_look(o, "auras")
	if o.hw.has("fan"):
		_F().hw_draw_fan(o)


## 地面层（data_operator.draw_entities_floor）
static func hw_draw_floor(o) -> void:
	h3_draw_floor(o)   # 手写迁移段第 3 批
	if h4_on(o):
		h4_draw_floor(o)   # 手写迁移段第 4 批
	if o.hw.has("links"):
		_F().hw_draw_melt(o)
	_F().hw_draw_waves(o)
	_F().hw_draw_pools(o)
	_F().hw_draw_rune_floor(o)


## 本体前后（data_operator.draw_body）
static func hw_draw_body(o, front: bool) -> void:
	if not front:
		_F().hw_draw_look(o, "body")
		if o.hw.has("wd") and h4_on(o):
			_F().h4wd_draw_back(o)   # 维什戴尔：魂灵之影在本体身后
	if o.hw.has("fan"):
		_F().hw_draw_fan_body(o, front)


# ---------------------------------------------------------------- 瞬时（data_operator._exec_list 缺省分支）

static func hw_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.wave":
			_F().hw_wave_start(o, b)
		"shape.shell":
			_F().hw_shell_fire(o, b, false)
		"verb.lob":
			_F().hw_lob(o, b, at)
		"verb.affect":
			_F().hw_affect(o, b, at)
		"shape.pool":
			_F().hw_pool(o, b, at)
		"shape.bolt":
			_F().hw_bolt_fire(o, b, false)
		"shape.hit":
			_F().hw_shape_hit(o, b)
		"verb.execute":
			_F().hw_execute(o, b)
		"verb.lock":
			_F().hw_lock_start(o, b)
		"verb.fan":
			_F().hw_fan_start(o, b)
		"verb.tether":
			_F().hw_tether_start(o, b)
		"verb.stack":
			_F().hw_stack(o, b)
		"verb.arm":
			_F().hw_arm(o, b)
		"verb.timer":
			_F().hw_timer(o, b)
		"verb.link":
			_F().hw_link(o, b)
		"shape.hookshot":
			_F().hw_hook_start(o, b)
		_:
			h3_exec(o, b, at)   # 手写迁移段第 3 批
			if h4_on(o):
				h4_exec(o, b, at)   # 手写迁移段第 4 批


# ================================================================ 精英化第 2 批（docs/91 §19 批 2：逻各斯 / 艾雅法拉 / 斯卡蒂 / 乌尔比安的精一 / 精二形态，docs/61 §18，10-14）
# 只往后加，建在手写迁移段上（hw 状态）。新积木：
#  verb.requiem_stack  常驻：本干员挂的「安魂」可叠层——再挂一次 +1 层（至多 max），每层受到的法术伤害 + per（combat.gd 读 e.requiem_k；不叠层时照旧 +15%）；
#                      look：按层数分档的头顶符文帧条（[1 层, 2 层, 3 层]）。逻各斯精一「剜魂」
#  verb.link           瞬时（命中 then）：从命中的敌人向 r 内最近 n 名拉出链 dur 秒（同时 ≤ cap 组）；链上任一名受到本干员 kinds 类伤害（来源不在 exclude 里）时，
#                      同组其他人各受到这次伤害 × share（src；链内不再互相传递）。tile / anchor / pulse：链节平铺、两端咒文结、传递时亮起。逻各斯精二「连缀」
#  shape.shell 的 lob  法术弹改低弧抛射：n 发（第 k 发 × mults[k]、晚 gap × k 秒出手）在目标周围呈三角（相邻落点间距 spacing）落下，飞 flight 秒、顶点 apex，
#                      落地在 aoe 内爆炸（同 fire 子弹：伤害发射时定、不乘 vs_elite），再执行 on_explode；整组落完在三角中心执行 pool（target = 中心，basis hit = 第一发）。
#                      没有落点预示圈，只有地面小影子。艾雅法拉精二「三重咏唱·低抛」
#  shape.wave 的 from: self / aim: nearest / fan / proj / hit_fx / release_fx   从本干员脚底朝最近敌人（aim_r 内，没有朝面向）放出，fan = 几道的偏角（度）；
#                      proj = 旋转的弹体帧条；命中 / 出手画面。斯卡蒂精二「涌潮」潮刃
#  verb.displace 的 r: attack + r_mult、r_in: attack   半径按当前普攻半径；r_in 内（已被这一下打到的）不拉。乌尔比安精一「收链」
#  shape.hookshot      瞬时：把锚掷向 range（× op_range）内离本干员最远、且在 min_d 外的敌人（没有就最近的），飞 clamp(距离 / speed, 0.1, 0.24) 秒（低弧 apex），
#                      落地 r 内 basis × mult（src），锁链绷直 taut 秒后把本干员与锚之间宽 w 的一线非 Boss 敌人连同锚拖回身前 front 处（drag 秒），
#                      到了再受 basis × back_mult（back_src）；lock = 锚在外面时不普攻。乌尔比安精二「掷锚」
#                      at: leader = 掷向队长所在处（超出 range 掷到 range 处），不找敌人（响应动作 docs/118，冲刺落点）
# 确定性：本段不取 g.rng；画面只用 g.vrng 与 g.t。

const HW5_TAGS := ["verb.requiem_stack", "verb.link", "shape.hookshot"]

const HW_LINK_CAP := 8

const HW_HOOK_MAX := 2


static func _hw5(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("links"):
		h.merge({"links": [], "rq": {}, "rq_list": [], "melt_list": [], "lobvol": [], "hooks": [], "link_busy": false, "vid": 0})
	return h


# ---------------------------------------------------------------- 常驻（data_operator._sustain 末尾转来）：本帧生效的叠层安魂
static func hw_sustain(o, act: Array) -> void:
	if not o.hw.has("links"):
		return
	o.hw.rq = {}
	for b in act:
		if str(b.get("_tag", "")) == "verb.requiem_stack":
			o.hw.rq = b
			break


## st.requiem 叠层（hw_status 转来）：返回 true = 已按叠层处理
static func hw_requiem_stack(o, e: Dictionary, s: Dictionary) -> bool:
	var h: Dictionary = o.hw
	var rq: Dictionary = h.get("rq", {})
	if rq.is_empty():
		return false
	var n: int = mini(int(e.get("requiem_n", 0)) + 1, int(rq.get("max", 3))) if float(e.get("requiem", 0.0)) > 0.0 else 1
	e["requiem_n"] = n
	e["requiem_k"] = float(rq.get("per", 0.06)) * n
	e["requiem"] = float(s.dur)
	var lst: Array = h.rq_list
	if not lst.any(func(x): return is_same(x, e)):
		lst.append(e)
		if lst.size() > 96:
			lst.pop_front()
	return true


# ---------------------------------------------------------------- 每帧（hw_tick 末尾转来）

static func _hw5_tick(o, dt: float) -> void:
	var h: Dictionary = o.hw
	if not h.links.is_empty():
		_F()._hw5_links(o, dt)
	if not h.lobvol.is_empty():
		_F()._hw5_lobs(o, dt)
	if not h.hooks.is_empty():
		_F()._hw5_hooks(o, dt)


# ---------------------------------------------------------------- 本段的校验

static func _hw5_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in HW5_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"verb.requiem_stack": ["sustain", "skill"],
		"verb.link": ["instant"],
		"shape.hookshot": ["skill", "instant"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"verb.requiem_stack":
			_num(b, "per", p, ctx, true, 0.0, 1.0)
			_num(b, "max", p, ctx, true, 1.0, 10.0)
			var lk = b.get("look", [])
			if not (lk is Array) or lk.any(func(x): return not str(x).begins_with("fx_")):
				errs.append(p + ".look 必须是 fx_* 帧条名的数组（按层数分档）")
		"verb.link":
			_num(b, "n", p, ctx, true, 1.0, 6.0)
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "dur", p, ctx, true, 0.1, 10.0)
			_num(b, "share", p, ctx, true, 0.0, 2.0)
			_num(b, "cap", p, ctx, false, 1.0, float(HW_LINK_CAP))
			for k in ["tile", "pulse", "anchor"]:
				if b.has(k) and not str(b[k]).begins_with("fx_"):
					errs.append("%s.%s 必须是 fx_* 帧条名" % [p, k])
			_src(b, p, ctx, true)
		"shape.hookshot":
			_num(b, "range", p, ctx, true, 10.0, 1000.0)
			if b.has("at") and str(b.at) != "leader":
				errs.append(p + ".at 只能是 leader")
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_num(b, "back_mult", p, ctx, false, 0.0, 20.0)
			_num(b, "w", p, ctx, false, 1.0, 200.0)
			_num(b, "taut", p, ctx, false, 0.0, 2.0)
			_num(b, "drag", p, ctx, false, 0.02, 2.0)
			if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
				errs.append(p + ".basis 只能是 attack / prev / hit / atk")
			if b.has("chain") and not str(b.chain).begins_with("fx_"):
				errs.append(p + ".chain 必须是 fx_* 帧条名")
			_src(b, p, ctx, true)
			if b.has("back_src") and not ctx.srcs.has(str(b.back_src)):
				errs.append("%s.back_src「%s」没在 hit_sources 里登记" % [p, str(b.back_src)])
			for k in ["fx", "impact_fx", "arrive_fx", "dust_fx"]:
				if b.has(k) and k != "fx":
					_fx(b[k], p + "." + k, ctx, "shape.circle")
	return true


# ================================================================ 手写迁移段（第 3 批：归溟幽灵鲨 / 水月 / 艾丽妮 / 流明，docs/91 §19 批 3；docs/61 §19）
# 只往后加，建在手写迁移段上（o.hw 状态、hw_tick / hw_exec / hw_draw_* 挂钩），前缀 h3_ / _h3。各人一个子字典：
#   ir（刺击 / 浮空 / 手炮连射 / 二次斩）、sp（锯环 / 替身 / 血痕）、mz（伞击 / 触手 / 水母）、lm（光弹 / 发光单元 / 灯塔）。
# 确定性：玩法随机只在手写版也取 g.rng 的地方取（同样的次数、同样的顺序）；画面一律 g.vrng。
#
# 艾丽妮段（IR_TAGS）：
#  shape.thrust     直线穿刺（普攻）：长 len × op_range（× len_mults）、宽 w（× w_mults），判定原点 = 脚底 + (0, y)，按离原点远近逐个命中、穿透；
#                   stages = 剑豪多段：出手后每隔 gap（按 attack 帧条 second − fire 帧）再刺一段（第 k 段 cond 成立才有，mult 乘在这一轮倍率上）；
#                   次数型技能补丁（dur.next_n 的 attack_patch：mult / power / src / on_first / then_first）只作用于第一段；
#                   ctrl = 吃 verb.ctrl_bonus（对受控敌人增伤）；pursue {cond, cd, mult[], r, src}：刺中浮空 / 被控住的敌人时追加一发手炮
#  shape.cleave     扇形 / 环形斩（按手写的结算顺序：逐个 伤害 → 命中状态）：半径 r（× op_range，或 "attack" = 当前刺击长度）× r_mult，
#                   原点 = 脚底 + origin_off；aim: nearest + aim_r（世界像素）朝最近敌人（face 转身），没有 aim = 朝 ang（弧度）；
#                   order: near = 按离脚底远近、max_n 个；伤害 = atk × mult[] × 加成 [× 技能强度] × post[]
#  verb.barrage     手炮连射：n 发，第 i 发在 t0 + i × gap 秒；每发优先打本段浮空表里离发动点 r（× op_range）内的敌人，没有就打身边 r × near_k 内最近 near_n 个，
#                   g.rng_op 随机挑一个（同手写），转身开火，执行 cannon {mult[], power, r, src}
#  verb.followup    delay 秒后再执行 do：那一刻正在出手就直接执行，否则先起一个技能动作（不扣技力），出手帧执行
#  verb.ctrl_bonus  常驻（天赋）：写了 ctrl 的形状对浮空 / 眩晕 / 束缚中的敌人伤害 × (1 + value)
#  verb.lift_around 瞬时：以 target 为心、r 内（查询多给 pad）的敌人（不含刚才那个首中目标）浮空 dur 秒、高 h
#  st.launch        命中状态：浮空（同手写艾丽妮：精英时长减半、Boss 不受；已浮空的刷新时长，每帧清击退，sin 弧线抬高 h）

const H3_TAGS := ["shape.thrust", "shape.cleave", "verb.barrage", "verb.followup", "verb.ctrl_bonus", "verb.lift_around", "st.launch",
	"shape.saw", "verb.undying", "verb.substitute",
	"shape.lantern", "verb.mend", "verb.purge", "verb.light_rain", "verb.beam_window", "verb.tower", "verb.beam", "verb.heal_lamp",
	"shape.umbrella", "verb.kill_heal", "verb.cast_push"]

const H3_ATTACKS := ["thrust", "saw", "lantern", "umbrella"]   # 第 3 批的普攻形状（起手 / 出手由本段接管）

const H3_PINK := Color(0.95, 0.6, 0.8)

const H3_SILVER := Color(0.9, 0.92, 1.0)

const H3_LAMP := Color(1.0, 0.85, 0.5)


static func h3_on(o) -> bool:
	return hw_on(o) and (o.hw.has("ir") or o.hw.has("sp") or o.hw.has("mz") or o.hw.has("lm"))


## hw_init 转来：本段的状态一开始就建好
static func h3_init(o, tags: Dictionary) -> void:
	for t in tags:
		if t in SP_TAGS:
			_F()._h3sp(o)
		elif t in LM_TAGS:
			_F()._h3lm(o)
		elif t in MZ_TAGS:
			_F()._h3mz(o)
		elif t in H3_TAGS:
			_h3ir(o)


static func _h3ir(o) -> Dictionary:
	var h := hw_st(o)
	if not h.has("ir"):
		h["ir"] = {"air": [], "strikes": [], "jc": Vector2.INF, "st_t": -1.0, "st_ang": 0.0, "st_mult": 1.0, "st_i": 0, "tn": 0, "pcd": 0.0,
			"fu_t": -1.0, "fu": {}, "swing": {}, "spin_t": 0.0, "first": {}, "judge": 0.0}
	return h.ir


static func _h3_sfx(o, kind: String, db := 0.0, pitch := 1.0, vary := 0.0) -> void:
	var g = o.g
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(o.id, kind, db, pitch, vary)


## 条件成立的倍率依次乘（[{cond, mult}]）
static func _h3_mults(o, v: float, arr) -> float:
	if arr is Array:
		for m in arr:
			if m is Dictionary and cond_true(o, m.get("cond", _ED)):
				v *= float(m.get("mult", 1.0))
	return v


# ---------------------------------------------------------------- 每帧（hw_tick 开头转来，手写 update 的先后：浮空 → 连射 → 追诉冷却 → 后续段 → 后续斩）

static func h3_tick(o, dt: float) -> bool:
	var h: Dictionary = o.hw
	if h.has("sp"):
		return _F()._h3sp_tick(o, h.sp, dt)
	if h.has("lm"):
		_F()._h3lm_tick(o, h.lm, dt)
	if h.has("ir"):
		var ir: Dictionary = h.ir
		_F()._h3_air_tick(o, ir, dt)
		_F()._h3_strikes_tick(o, ir, dt)
		ir.pcd = maxf(0.0, float(ir.pcd) - dt)
		_F()._h3_stage_tick(o, ir, dt)
		_F()._h3_followup_tick(o, ir, dt)
		_F()._e3_ir_tick(o, ir, dt)
	return false


## hw_exec 转来
static func h3_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.thrust":
			pass
		"shape.cleave":
			_F().h3_cleave(o, b, at)
		"verb.barrage":
			_F().h3_barrage(o, b)
		"verb.followup":
			_F().h3_followup(o, b)
		"verb.lift_around":
			_F().h3_lift_around(o, b, at)
		"verb.mend":
			_F().h3_mend(o, b)
		"verb.purge":
			_F().h3_purge(o, b)
		"verb.light_rain":
			_F().h3_light_rain(o, b)
		"verb.beam_window":
			_F()._h3lm(o).beam_t = float(b.get("dur", 3.0))
		"verb.tower":
			_F().h3_tower_start(o, b)
		"verb.cast_push":
			_F().h3_cast_push(o, b)
		"verb.kill_heal":
			_F().h3_kill_heal(o, b)
		"verb.heal_lamp":
			_F()._h3_heal_lamp(o)
		"verb.doll_flash":
			_F().h3_doll_flash(o, b)


# ---------------------------------------------------------------- 画面

## 技能上层（hw_draw_over 转来）
static func h3_draw_over(o) -> void:
	if o.hw.has("ir"):
		_h3ir_draw_over(o)
	if o.hw.has("sp"):
		_F()._h3sp_draw_over(o)
	if o.hw.has("lm"):
		_F()._h3lm_draw_over(o)
	if o.hw.has("mz"):
		_F()._h3mz_draw_over(o)


## 地面层（hw_draw_floor 转来）
static func h3_draw_floor(o) -> void:
	if o.hw.has("sp"):
		_F()._h3sp_draw_floor(o)
	if o.hw.has("mz"):
		_F()._h3mz_draw_floor(o)


## 区域层（hw_draw_auras 转来）
static func h3_draw_auras(o) -> void:
	if o.hw.has("sp"):
		_F()._h3sp_draw_auras(o)
	if o.hw.has("lm"):
		_F()._h3lm_draw_auras(o)
	if o.hw.has("mz"):
		_F()._h3mz_draw_auras(o)


## 加色层（data_operator.draw_fx_add 转来）
static func h3_draw_add_all(o, ci, loop: int) -> void:
	if not hw_on(o):
		return
	if o.hw.has("lm"):
		_F().h3_draw_add(o, ci)
	if o.hw.has("mz"):
		_F()._h3mz_draw_add(o, ci, loop)


## 附属实体（替身 / 灯塔）参与 2.5D 排序
static func h3_extra_bodies(o) -> Array:
	if not hw_on(o):
		return []
	if o.hw.has("sp"):
		return _F().h3_bodies(o)
	if o.hw.has("lm"):
		return _F()._h3lm_bodies(o)
	return []


static func h3_draw_body_extra(o, it: Dictionary) -> void:
	if str(it.get("h3", "")) == "tower":
		_F()._h3lm_draw_tower(o)
	else:
		_F().h3_draw_extra(o, it)


static func h3_shadows(o) -> void:
	if not hw_on(o):
		return
	if o.hw.has("sp"):
		_F().h3_draw_shadows(o)
	if o.hw.has("lm"):
		_F()._h3lm_shadow(o)


static func h3_rows(o) -> Array:
	if hw_on(o) and o.hw.has("mz"):
		return _F()._h3mz_rows(o)
	return []


static func _h3ir_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	var ir: Dictionary = o.hw.ir
	if o.pos == Vector2.INF:
		return
	var lk: Dictionary = o.B.get("attack", _ED).get("look", {})
	var lamp_on: bool = o.skill_active_left(2) > 0.0 or (o.acting() and o.act_kind == "skill")
	if lamp_on and lk.get("lantern", true):
		var raised: bool = o.acting() and o.act_kind == "skill"
		var p: Vector2 = o.pos + (Vector2(20.0 * o.face, -56.0) if raised else Vector2(16.0 * o.face, -15.0))
		cv.draw_circle(p, 5.0 + sin(g.t * 20.0), Color(1.6, 1.3, 0.7, 0.8))
		cv.draw_circle(p, 12.0, Color(1.0, 0.85, 0.5, 0.2))
	if float(ir.spin_t) > 0.0:
		var k: float = float(ir.spin_t) / 0.12
		var c: Vector2 = o.pos + Vector2(0, -24)
		var a0: float = PI * 0.5 if o.face > 0.0 else -PI * 0.5
		cv.draw_arc(c, 22.0, a0, a0 + PI, 16, Color(H3_PINK.r * 1.5, H3_PINK.g * 1.4, H3_PINK.b * 1.4, 0.7 * k), 4.0)
		o.draw_body_at(o.pos, o.face > 0.0, Color(H3_PINK.r * 1.3, H3_PINK.g * 1.2, H3_PINK.b * 1.3, 0.45 * k))
	for a in ir.air:
		if not a.e.dead:
			cv.draw_set_transform(a.e.pos + Vector2(0, a.e.r * 0.8), 0.0, Vector2(1.0, 0.5))
			cv.draw_arc(Vector2.ZERO, a.e.r * 0.9, 0.0, TAU, 20, Color(H3_PINK.r, H3_PINK.g, H3_PINK.b, 0.5), 1.5)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 程序粒子（hw_draw_pfx 转来）：h3_thrust（刺击光束）/ h3_gale（卷风旋风弧）
static func h3_draw_pfx(o, f: Dictionary, a: float) -> bool:
	match str(f.kind):
		"h3_saw":
			_F()._h3_draw_saw(o, f, a)
			return true
		"h3_beam":
			_F()._e3_draw_beam(o, f, a)
			return true
		"h3_thrust":
			_h3_draw_thrust(o, f, a)
			return true
		"h3_gale":
			var cv = o.cv
			var u0: float = 1.0 - a
			cv.draw_set_transform(f.pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
			if Dc.hit_rings():
				cv.draw_arc(Vector2.ZERO, f.r, 0.0, TAU, 32, Color(H3_PINK.r, H3_PINK.g, H3_PINK.b, 0.35 * a), 1.5)
			for q in 3:
				var rr: float = f.r * (1.0 - 0.6 * u0) * (1.0 - q * 0.22)
				var a0: float = u0 * 9.0 + q * TAU / 3.0
				cv.draw_arc(Vector2.ZERO, rr, a0, a0 + 2.0, 12, Color(H3_PINK.r * 1.5, H3_PINK.g * 1.4, H3_PINK.b * 1.5, 0.8 * a), 3.0 - q * 0.6)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return true
	return false


static func _h3_quad(cv, q: PackedVector2Array, c: Color) -> void:
	if q[1].distance_to(q[3]) < 2.0:
		cv.draw_line(q[0], q[2], c, 2.0)
	else:
		cv.draw_colored_polygon(q, c)


## 刺击光束：前 30% 伸到最长（缓出），之后宽度收细、淡出；顶点对齐 2 像素网格
static func _h3_draw_thrust(o, f: Dictionary, a: float) -> void:
	var cv = o.cv
	var u: float = 1.0 - a
	var ext: float = 1.0 - pow(1.0 - minf(1.0, u / 0.3), 3.0)
	var d: Vector2 = f.dir
	var n: Vector2 = d.orthogonal()
	var L: float = f.len * ext
	var org: Vector2 = f.pos + d * 14.0 * u
	var tip: Vector2 = org + d * L
	var wide: float = f.w * (1.0 - 0.7 * maxf(0.0, (u - 0.3) / 0.7))
	var c: Color = f.col
	var P := func(v: Vector2) -> Vector2: return (v / 2.0).round() * 2.0
	if L < 12.0:
		return
	_h3_quad(cv, PackedVector2Array([P.call(org + d * 6.0), P.call(org + d * L * 0.7 + n * wide * 0.5), P.call(tip), P.call(org + d * L * 0.7 - n * wide * 0.5)]), Color(c.r, c.g, c.b, 0.55 * a))
	_h3_quad(cv, PackedVector2Array([P.call(org + d * L * 0.25), P.call(org + d * L * 0.72 + n * wide * 0.18), P.call(tip + d * 2.0), P.call(org + d * L * 0.72 - n * wide * 0.18)]), Color(2.2, 2.1, 2.2, 0.95 * a))
	for s in [-1.0, 1.0]:
		var off: Vector2 = n * s * (wide * 0.5 + 5.0)
		cv.draw_line(P.call(org + d * L * 0.35 + off), P.call(org + d * L * 0.85 + off), Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, 0.45 * a), 1.0)
	if u > 0.2 and u < 0.75 and o.g.tex.get(str(f.get("star", "fx_star_hit_rose"))) == null:
		var k: float = 1.0 - absf(u - 0.35) / 0.4
		var sz: float = 7.0 * k
		cv.draw_line(P.call(tip - d * sz), P.call(tip + d * sz), Color(2.4, 2.2, 2.4, k), 2.0)
		cv.draw_line(P.call(tip - n * sz * 0.6), P.call(tip + n * sz * 0.6), Color(2.4, 2.2, 2.4, k), 2.0)


## 状态条（hw_status_items 转来）：次数型技能（没写 %d 的 status 也显示）、技能剩余（审判）
static func h3_status_items(o) -> Array:
	var out: Array = []
	if o.hw.has("sp"):
		out += _F()._h3sp_status(o)
	if o.hw.has("lm"):
		out += _F()._h3lm_status(o)
	if o.hw.has("mz"):
		return _F()._h3mz_status(o)
	var sk: Array = o.B.get("skills", [])
	for i in mini(3, sk.size()):
		var st: String = str(sk[i].get("status", ""))
		if st == "" or "%d" in st:
			continue
		if o.ammo[i] > 0 or (sk[i].get("status_active", false) and o.s_t[i] > 0.0):
			out.append([st, _mf_col(sk[i].get("status_col", []), o.col())])
	return out


# ---------------------------------------------------------------- 本段的校验

static func _h3_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in H3_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.thrust": ["attack"],
		"shape.cleave": ["skill", "instant"],
		"verb.barrage": ["skill", "instant"],
		"verb.followup": ["skill", "instant"],
		"verb.ctrl_bonus": ["sustain"],
		"verb.lift_around": ["skill", "instant"],
		"st.launch": ["on_hit"],
		"shape.saw": ["attack"],
		"verb.undying": ["skill"],
		"verb.substitute": ["skill"],
		"shape.lantern": ["attack"],
		"verb.mend": ["skill", "instant"],
		"verb.purge": ["skill", "instant"],
		"verb.light_rain": ["skill", "instant"],
		"verb.beam_window": ["skill", "instant"],
		"verb.tower": ["skill"],
		"verb.beam": ["sustain"],
		"verb.heal_lamp": ["sustain", "skill", "instant"],
		"shape.umbrella": ["attack"],
		"verb.kill_heal": ["instant"],
		"verb.cast_push": ["skill", "instant"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"shape.thrust":
			_num(b, "len", p, ctx, true, 10.0, 800.0)
			_num(b, "w", p, ctx, true, 1.0, 200.0)
			_num(b, "y", p, ctx, false, -100.0, 100.0)
			_num(b, "aim_pad", p, ctx, false, 0.0, 400.0)
			_num(b, "fire_pad", p, ctx, false, 0.0, 400.0)
			for k in ["len_mults", "w_mults"]:
				_h3_cond_mults(b, k, p, ctx)
			var stg = b.get("stages", [])
			if not (stg is Array) or stg.size() > 4:
				errs.append(p + ".stages 必须是 0–4 段的数组")
			else:
				for i in stg.size():
					var q := "%s.stages[%d]" % [p, i]
					if not (stg[i] is Dictionary):
						errs.append(q + " 必须是对象 {cond, mult}")
						continue
					for k in stg[i]:
						if not k in ["cond", "mult", "on_first", "_doc"]:
							errs.append("%s.%s：一段只有 cond / mult / on_first" % [q, k])
					_list(stg[i].get("on_first", []), q + ".on_first", "on_hit", ctx)
					if stg[i].has("cond") and (not (stg[i].cond is String) or parse_cond(stg[i].cond, ctx.base).has("err")):
						errs.append(q + ".cond 看不懂")
					_num(stg[i], "mult", q, ctx, false, 0.0, 10.0)
			if b.has("pursue"):
				var pu = b.pursue
				if not (pu is Dictionary):
					errs.append(p + ".pursue 必须是对象 {cond, cd, mult, r, src}")
				else:
					_num(pu, "cd", p + ".pursue", ctx, true, 0.0, 10.0)
					_num(pu, "r", p + ".pursue", ctx, false, 1.0, 200.0)
					_src(pu, p + ".pursue", ctx, true)
			if b.has("finisher"):   # 精英化第 3 批：收尾换斩
				var fn = b.finisher
				if not (fn is Dictionary):
					errs.append(p + ".finisher 必须是对象 {cond, every, anim, do, volley}")
				else:
					_num(fn, "every", p + ".finisher", ctx, true, 1.0, 20.0)
					if fn.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(fn.anim))):
						errs.append("%s.finisher.anim「%s」不是 sprites 里的帧条键" % [p, str(fn.anim)])
					_list(fn.get("do", []), p + ".finisher.do", "instant", ctx)
					if fn.get("volley", null) is Dictionary:
						_num(fn.volley, "n", p + ".finisher.volley", ctx, true, 1.0, 12.0)
						_src(fn.volley, p + ".finisher.volley", ctx, true)
			_src(b, p, ctx, true)
		"shape.cleave":
			if str(b.get("r", "")) != "attack":
				_num(b, "r", p, ctx, true, 1.0, 1000.0)
			_num(b, "half", p, ctx, false, 0.05, 3.2)   # ≥ PI = 整圈（不看角度）
			_num(b, "aim_r", p, ctx, false, 1.0, 2000.0)
			_num(b, "max_n", p, ctx, false, 1.0, 99.0)
			if b.has("aim") and not str(b.aim) in ["nearest", "thrust"]:
				errs.append(p + ".aim 只能是 nearest / thrust")
			if b.has("order") and str(b.order) != "near":
				errs.append(p + ".order 只能是 near")
			if b.has("origin_off") and not (b.origin_off is Array and b.origin_off.size() == 2):
				errs.append(p + ".origin_off 必须是 [x, y]")
			_list(b.get("on_hit", []), p + ".on_hit", "on_hit", ctx)
			_src(b, p, ctx, true)
		"verb.barrage":
			_num(b, "n", p, ctx, true, 1.0, 40.0)
			_num(b, "gap", p, ctx, true, 0.02, 5.0)
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			var cb = b.get("cannon", null)
			if not (cb is Dictionary):
				errs.append(p + ".cannon 必须是对象 {mult, power, r, src}")
			else:
				_src(cb, p + ".cannon", ctx, true)
		"verb.followup":
			_num(b, "delay", p, ctx, true, 0.0, 5.0)
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"verb.ctrl_bonus":
			_num(b, "value", p, ctx, true, 0.0, 5.0)
		"verb.lift_around":
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
			if b.has("center") and not str(b.center) in ["self", "leader"]:
				errs.append(p + ".center 只能是 self / leader（响应动作：没有命中点时的中心）")
		"st.launch":
			_num(b, "dur", p, ctx, true, 0.0, 10.0)
			_num(b, "h", p, ctx, false, 0.0, 100.0)
		"shape.saw":
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_num(b, "kb", p, ctx, false, 0.0, 1000.0)
			_h3_cond_mults(b, "r_mults", p, ctx)
			for k in ["spin2", "trail", "whirl", "low_hp"]:
				if b.has(k) and not (b[k] is Dictionary):
					errs.append("%s.%s 必须是对象" % [p, k])
			if b.get("trail", null) is Dictionary:
				_src(b.trail, p + ".trail", ctx, true)
			_src(b, p, ctx, true)
		"verb.substitute":
			_num(b, "life", p, ctx, true, 0.1, 60.0)
			if b.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
				errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
			if b.get("doll_aura", null) is Dictionary:
				_src(b.doll_aura, p + ".doll_aura", ctx, true)
		"shape.lantern":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			if not (b.get("heal", null) is Dictionary) or not (b.get("bolt", null) is Dictionary):
				errs.append(p + "：shape.lantern 要写 heal {every, pct} 与 bolt {atk_key, speed, src}")
			else:
				_num(b.heal, "every", p + ".heal", ctx, true, 0.1, 60.0)
				_num(b.heal, "pct", p + ".heal", ctx, true, 0.0, 0.2)
				_src(b.bolt, p + ".bolt", ctx, true)
			if b.get("units", null) is Dictionary:
				_src(b.units, p + ".units", ctx, true)
			if b.get("bolt", null) is Dictionary and b.bolt.get("refract", null) is Dictionary:   # 精英化第 3 批：折光
				_num(b.bolt.refract, "r", p + ".bolt.refract", ctx, true, 1.0, 600.0)
				_src(b.bolt.refract, p + ".bolt.refract", ctx, true)
			if b.has("beam"):   # 精英化第 3 批：灯塔光柱
				if not (b.beam is Dictionary):
					errs.append(p + ".beam 必须是对象")
				else:
					_num(b.beam, "need", p + ".beam", ctx, true, 1.0, 50.0)
					_num(b.beam, "len", p + ".beam", ctx, true, 10.0, 800.0)
					_src(b.beam, p + ".beam", ctx, true)
		"verb.mend":
			_num(b, "pct", p, ctx, true, 0.0, 0.5)
		"verb.purge":
			_num(b, "immune", p, ctx, false, 0.0, 30.0)
		"verb.light_rain":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_src(b, p, ctx, true)
		"verb.beam_window":
			_num(b, "dur", p, ctx, true, 0.1, 30.0)
		"verb.tower":
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			if b.get("burst", null) is Dictionary:
				_src(b.burst, p + ".burst", ctx, true)
		"verb.beam":
			_num(b, "len", p, ctx, true, 1.0, 1000.0)
			_num(b, "tick", p, ctx, true, 0.02, 5.0)
			_src(b, p, ctx, true)
		"verb.heal_lamp":
			_num(b, "add", p, ctx, kind == "sustain", 0.0, 100.0)
		"shape.umbrella":
			_num(b, "r", p, ctx, true, 1.0, 800.0)
			_h3_cond_mults(b, "r_mults", p, ctx)
			_h3_cond_mults(b, "dmg_mults", p, ctx)
			_h3_cond_mults(b, "interval_mults", p, ctx)
			if not (b.get("tentacle", null) is Dictionary):
				errs.append(p + ".tentacle 必须是对象")
			else:
				_src(b.tentacle, p + ".tentacle", ctx, true)
			if b.has("full_circle"):
				var area = b.full_circle
				if not area is Dictionary or not area.get("cond") is String or parse_cond(area.cond, ctx.base).has("err"):
					errs.append(p + ".full_circle 必须有合法 cond 条件")
			if b.has("jelly"):   # 精英化第 3 批：深蓝之籽
				if not (b.jelly is Dictionary):
					errs.append(p + ".jelly 必须是对象")
				else:
					_num(b.jelly, "every", p + ".jelly", ctx, true, 0.1, 10.0)
					_num(b.jelly, "r", p + ".jelly", ctx, true, 1.0, 800.0)
					_src(b.jelly, p + ".jelly", ctx, true)
			_src(b, p, ctx, true)
		"verb.kill_heal":
			_num(b, "pct", p, ctx, true, 0.0, 0.2)
		"verb.cast_push":
			_num(b, "r", p, ctx, true, 1.0, 800.0)
	return true


static func _h3_cond_mults(b: Dictionary, k: String, p: String, ctx: Dictionary) -> void:
	if not b.has(k):
		return
	var arr = b[k]
	if not (arr is Array):
		ctx.errs.append("%s.%s 必须是 [{cond, mult}] 数组" % [p, k])
		return
	for i in arr.size():
		var q := "%s.%s[%d]" % [p, k, i]
		if not (arr[i] is Dictionary):
			ctx.errs.append(q + " 必须是对象 {cond, mult}")
			continue
		if arr[i].has("cond") and (not (arr[i].cond is String) or parse_cond(arr[i].cond, ctx.base).has("err")):
			ctx.errs.append(q + ".cond 看不懂")
		_num(arr[i], "mult", q, ctx, true, 0.0, 20.0)


# ================================================================ 精英化第 3 批（docs/91 §5 / §8 / §9 / §14、§25；docs/61 §20，10-14）
# 只往后加，建在第 3 批手写迁移段上（o.hw 的 ir / sp / lm / mz）。新积木 / 新参数：
#  trig.on_windup     普攻起手时（第 3 批的普攻形状）执行 do。幽灵鲨精一「卷刃」：起手把外圈敌人吸近（verb.displace，环斩在出手帧）
#  verb.doll_flash    瞬时（trig.every_n 的 do）：替身人偶在 range（× op_range）内敌群最密处从水花里现身 appear 秒 → 旋身斩一圈
#                     （r × op_range，basis × mult，src）→ 碎成泡沫 burst 秒；同时最多 1 个，本体离场（替身跟随）时不出。幽灵鲨精二「替身闪现」
#  shape.thrust 的 stages[k].on_first           第 k 段命中的第一个敌人吃的状态（艾丽妮精一「挑刺」：第 2 段挑起，cd 门）
#  shape.thrust 的 finisher {cond, every, anim, do, volley}  每第 every 次刺击，最后一段换成 do（艾丽妮精二「裂潮余波」：新月斩 + 浮空），
#                     volley {delay, n, mult[], r, src}：收尾 delay 秒后手炮补射这一斩里浮空的至多 n 名
#  shape.cleave 的 aim: thrust（沿这一轮刺击的方向，不转身）、look: crescent
#  shape.lantern 的 bolt.refract {cond, r, mult, src}  光弹打中已被照亮的敌人时折向 r 内最近的未照亮敌人（流明精一「折光」）
#  shape.lantern 的 beam {cond, need, shots, len, w, mult, heal, src}  流明与发光单元每射满 need 发，接下来 shots 发变为直线光柱（流明精二「灯塔光柱」）
#  shape.umbrella 的 tentacle.pull {cond, dist, elite_mult}  触手命中把目标拖向自己（水月精一「拖拽」）
#  shape.umbrella 的 jelly {cond, every, s3, r, speed, back, mult, stun, src}  身后小水母离身游猎蜇刺（水月精二「深蓝之籽」）
# 确定性：本段不取 g.rng（选目标都按距离 / 次序）；画面只用 g.vrng 与 g.t。

const E3_TAGS := ["trig.on_windup", "verb.doll_flash"]

const H3_COLD := Color(0.6, 0.8, 1.05)


## 起手（h3_attack_start 转来）：trig.on_windup
static func _e3_windup(o) -> void:
	for t in o._trigs():
		if str(t.get("_tag", "")) == "trig.on_windup" and cond_true(o, t.get("cond", _ED)):
			o._exec_list(t.get("do", []), o.pos)


## 当前普攻的判定半径（verb.displace r_in: attack 用；第 3 批的形状按各自的长度 / 半径）
static func h3_attack_r(o, a: Dictionary) -> float:
	match str(a.get("shape", "")):
		"thrust":
			return _F().h3_thrust_len(o, a)
		"saw":
			return _F().h3_saw_r(o, a)
		"umbrella":
			return _F().h3_umb_radius(o, a)
	return shape_radius(o, a)


# ---------------------------------------------------------------- 本段的校验

static func _e3_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in E3_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {"trig.on_windup": ["trig"], "verb.doll_flash": ["skill", "instant"]}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"trig.on_windup":
			_list(b.get("do", []), p + ".do", "instant", ctx)
		"verb.doll_flash":
			_num(b, "range", p, ctx, true, 10.0, 1000.0)
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "mult", p, ctx, true, 0.0, 10.0)
			for k in ["appear", "spin", "burst", "spin_gap"]:
				_num(b, k, p, ctx, false, 0.0, 3.0)
			_num(b, "spins", p, ctx, false, 1.0, 6.0)
			if b.has("basis") and not str(b.basis) in ["attack", "prev", "hit", "atk"]:
				errs.append(p + ".basis 只能是 attack / prev / hit / atk")
			if b.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.anim))):
				errs.append("%s.anim「%s」不是 sprites 里的帧条键" % [p, str(b.anim)])
			_src(b, p, ctx, true)
	return true


# ================================================================ 手写迁移段（第 4 批：推进之王 / 铃兰 / 维什戴尔 / 塞雷娅，docs/91 §19 批 4；docs/61 §21）
# 只往后加，建在手写迁移段上（o.hw 状态、hw_tick / hw_exec / hw_draw_* 挂钩），前缀 h4_ / _h4。各人一个子字典：
#   sg（锤击 / 跃空锤 / 号令波 / 地裂）、sz（狐火 / 光域 / 大狐火 / 金印）、wd（炮弹 / 余震 / 残影 / 标记 / 魂灵之影）、sa（拳击 / 阻挡圈 / 钙晶 / 投射物 / 护服 / 钙质化）。
# 确定性：玩法随机只在手写版也取 g.rng 的地方取（推进之王碎颅的 50% 眩晕、塞雷娅钙质化晶柱的落点与碎晶挑哪根），次数与顺序同手写；画面一律 g.vrng。
# 常驻的「系统积木」（光域、阻挡圈、钙晶、魂灵之影……）写在 trait / talent / 成长节点的 passive do 里，每帧按 _h4_live 现查（不缓存，精英化 / 选节点当帧生效，同手写）。
#
# 推进之王段（SG_TAGS）：
#  shape.hammer     扇形锤击（普攻）：半径 r × op_range、半角 half、kb、判定原点 脚底 + (0, y)；次数型补丁（dur.next_n 的 attack_patch：mult / power）乘在这一锤上；
#                   heavy {cond, mult, power, interval, stun_chance, stun, anim}：cond 成立时（碎颅）每一锤 × mult [× 技能强度]、间隔 × interval、用 anim 帧条起手（出手走技能出手帧）、
#                   命中的非 Boss 敌人 stun_chance 概率（g.rng，同手写）眩晕 stun 秒（精英减半）；hit_sp + hit_sp_mults：命中时其他干员技力 + 秒数（第一条 cond 成立的倍率）；
#                   quake {cond, r, mult, src, roar {cond, r_mult, kb}}：落点一圈贴地冲击环；breach {cond, len, w, mult, life, max, src}：沿锤击方向的直线地裂
#  verb.leap_slam   跃空锤：朝 aim_r 内最近的敌人跃过去（至多 dist，落在它面前 24 处），t 秒、高 h 的空中翻转，落地 r × op_range 内 × mult × 技能强度、kb、stun，
#                   其他干员技力 + sp × 技能强度；again {cond, range, dist, mult, near}：落地后再跃向身边敌人最密处砸第二下（× mult，不回技力）；
#                   响应动作（docs/118）：from: leader = 找队长 aim_r 内离队长最近的敌人（本人是队长时原地砸）、power: false = 不吃技能强度、
#                   sp_secs = 改为砸中敌人时其他干员技力 + 秒数（取代 sp）；已在空中时不另跳
#  verb.cmd_wave    号令波：以自身为心向外扩张到 r（dur 秒，先快后慢），扫到的敌人 × mult × 技能强度、非精英击退 kb；同时至多 max 道
#  verb.sp_team 的 power / motes（第 4 批追加）：技力 × 技能强度；金色技力粒子飞向每名队友

const H4_TAGS := ["shape.hammer", "verb.leap_slam", "verb.cmd_wave",
	"shape.foxfire", "verb.foxlight", "verb.fox_cast",
	"shape.cannon", "verb.cannon_exec", "verb.cannon_load", "verb.souls",
	"shape.bash", "verb.guard_ring", "verb.calc_orbs", "verb.saria_heal", "verb.calc_field", "verb.suit", "verb.amber_ring"]

const H4_ATTACKS := ["hammer", "foxfire", "cannon", "bash"]   # 第 4 批的普攻形状（起手 / 出手由本段接管）

const SG_TAGS := ["shape.hammer", "verb.leap_slam", "verb.cmd_wave"]

const SZ_TAGS := ["shape.foxfire", "verb.foxlight", "verb.fox_cast"]

const WD_TAGS := ["shape.cannon", "verb.cannon_exec", "verb.cannon_load", "verb.souls"]

const SA_TAGS := ["shape.bash", "verb.guard_ring", "verb.calc_orbs", "verb.saria_heal", "verb.calc_field", "verb.suit", "verb.amber_ring"]

const H4_GOLD := Color(1.0, 0.78, 0.35)

const H4_FLAME := Color(1.0, 0.55, 0.15)

const H4_FOX := Color(1.0, 0.82, 0.45)

const H4_RED := Color(0.95, 0.22, 0.2)

const H4_BOLT := Color(0.9, 0.08, 0.1)

const H4_EMBER := Color(1.0, 0.55, 0.3)

const H4_DARK := Color(0.1, 0.06, 0.08)

const H4_AMBER := Color(1.0, 0.72, 0.38)


static func h4_on(o) -> bool:
	return hw_on(o) and (o.hw.has("sg") or o.hw.has("sz") or o.hw.has("wd") or o.hw.has("sa"))


## hw_init 转来：本段的状态一开始就建好
static func h4_init(o, tags: Dictionary) -> void:
	for t in tags:
		if t in SG_TAGS:
			_F()._h4sg(o)
		elif t in SZ_TAGS:
			_F()._h4sz(o)
		elif t in WD_TAGS:
			_F()._h4wd(o)
		elif t in SA_TAGS:
			_F()._h4sa(o)


## 本帧生效的某块积木（trait → talent → 已选节点 → elite1 / elite2；passive 的 do 里找，各自的 cond 都成立）；没有 = {}
static func _h4_live(o, tag: String) -> Dictionary:
	for t in o._trigs():
		if not cond_true(o, t.get("cond", _ED)):
			continue
		var tg: String = str(t.get("_tag", ""))
		if tg == tag:
			return t
		if tg == "trig.passive":
			for b in t.get("do", _EA):
				if str(b.get("_tag", "")) == tag and cond_true(o, b.get("cond", _ED)):
					return b
	return {}


## 条件成立的第一条 [{cond, mult}] 的倍率；没有 = 1.0
static func _h4_first_mult(o, arr, key := "mult") -> float:
	if arr is Array:
		for m in arr:
			if m is Dictionary and cond_true(o, m.get("cond", _ED)):
				return float(m.get(key, 1.0))
	return 1.0


## 子参数块 {cond, …} 成立时返回它，否则 {}
static func _h4_sub(o, v) -> Dictionary:
	if v is Dictionary and not v.is_empty() and cond_true(o, v.get("cond", _ED)):
		return v
	return {}


## 次数型技能的补丁（dur.next_n 的 attack_patch）：先到先用，用掉一次
static func _h4_take_patch(o) -> Dictionary:
	var sk: Array = o.B.get("skills", [])
	for i in 3:
		if o.ammo[i] > 0 and i < sk.size():
			o.ammo[i] -= 1
			return sk[i].get("attack_patch", {})
	return {}


static func _h4_patch_pending(o) -> bool:
	return o.ammo[0] > 0 or o.ammo[1] > 0 or o.ammo[2] > 0


## 普攻起手（data_operator.update：技能判定之后）
static func h4_attack_start(o, a: Dictionary, _dt: float) -> void:
	match str(a.get("shape", "")):
		"hammer":
			_F()._h4_hammer_start(o, a)
		"foxfire":
			_F()._h4_fox_start(o, a)
		"cannon":
			_F()._h4_cannon_start(o, a)
		"bash":
			_F()._h4_bash_start(o, a)


## 普攻出手（data_operator._release）；音效由各形状自己播（同手写）
static func h4_attack_fire(o, a: Dictionary) -> void:
	match str(a.get("shape", "")):
		"hammer":
			_F()._h4_hammer_release(o, a)
		"foxfire":
			_F()._h4_fox_release(o, a)
		"cannon":
			_F()._h4_cannon_release(o, a)
		"bash":
			_F()._h4_bash_release(o, a)


## data_operator._release_skill 开头：碎颅期间用技能动作起手的那一锤（出手走技能出手帧）。返回 true = 已处理
static func h4_release_skill(o) -> bool:
	if not o.hw.has("sg") or not o.hw.sg.heavy_swing:
		return false
	o.hw.sg.heavy_swing = false
	o._release()
	return true


## 每帧（hw_tick 转来，手写 update 的先后）。返回 true = 本帧不起手（跃空锤在空中）
static func h4_tick(o, dt: float) -> bool:
	var h: Dictionary = o.hw
	if h.has("sg"):
		return _F()._h4sg_tick(o, h.sg, dt)
	if h.has("sz"):
		_F()._h4sz_tick(o, h.sz, dt)
	if h.has("wd"):
		_F()._h4wd_tick(o, h.wd, dt)
	if h.has("sa"):
		_F()._h4sa_tick(o, h.sa, dt)
	return false


## hw_exec 转来
static func h4_exec(o, b: Dictionary, _at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.leap_slam":
			_F().h4_leap(o, b)
		"verb.cmd_wave":
			_F().h4_cmd_wave(o, b)
		"verb.fox_cast":
			_F().h4_fox_cast(o, b)
		"verb.cannon_exec":
			_F().h4_cannon_exec(o, b)
		"verb.cannon_load":
			_F().h4_cannon_load(o, b)
		"verb.saria_heal":
			_F().h4_saria_heal(o, b)
		"verb.calc_field":
			_F().h4_calc_start(o, b)
		"verb.amber_ring":
			_F().h4_amber_ring(o, b)


## 起手朝向（mf_skill_aim 转来）：elite = 精英 / Boss 优先（血最多）；cluster = 离队长最近、相仿时挑落点最密
static func h4_skill_aim(o, i: int, aim: String) -> Vector2:
	var sk: Array = o.B.get("skills", [])
	var a: Dictionary = o.B.get("attack", {})
	var reach: float = _F()._h4_wd_reach(o, a, float(sk[i].get("aim_r", 520.0)))
	var tg: Dictionary = _F()._h4_exec_target(o, a, reach) if aim == "elite" else _F()._h4_wd_target(o, a, reach)
	return tg.pos if not tg.is_empty() else Vector2.INF


## 击杀（data_operator.on_kill 转来）：维什戴尔带残影标记的敌人殉爆
static func h4_on_kill(o, e: Dictionary) -> void:
	if o.hw.has("wd"):
		_F()._h4wd_on_kill(o, e)


## 受击询问（data_operator.dmg_taken_mult 转来）：verb.dr 按本刻生效的积木现算（精英化当帧就生效，同手写；不等下一帧 _sustain）
static func h4_live_dr(o) -> float:
	var dr := 1.0
	for t in o._trigs():
		if not cond_true(o, t.get("cond", _ED)) or str(t.get("_tag", "")) != "trig.passive":
			continue
		for b in t.get("do", _EA):
			if str(b.get("_tag", "")) == "verb.dr" and cond_true(o, b.get("cond", _ED)):
				dr *= 1.0 - float(b.value)
	return dr


## 状态条（hw_status_items 转来）
static func h4_status_items(o) -> Array:
	var out: Array = []
	if o.hw.has("wd") and int(o.hw.wd.ammo) > 0:
		out.append([str(o.hw.wd.get("status", "×%d")) % int(o.hw.wd.ammo), Color(1.0, 0.55, 0.45)])
	if o.hw.has("sa"):
		var sa: Dictionary = o.hw.sa
		if float(sa.hot_t) > 0.0:
			out.append([str(sa.get("hot_name", "")), H4_AMBER])
		if float(sa.calc) > 0.0:
			out.append([str(sa.get("calc_name", "")), H4_AMBER])
		var su: Dictionary = _h4_live(o, "verb.suit")
		if not su.is_empty():
			var segs: int = int(su.get("segs", 4))
			out.append([str(su.get("name", "")) + " %d/%d" % [int(sa.seg), segs], H4_AMBER, float(sa.seg) / float(segs)])
	return out


# ---------------------------------------------------------------- 画面分发（hw_draw_* 转来）

static func h4_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if not h4_on(o):
		return false
	if o.hw.has("sg") and _F()._h4sg_draw_pfx(o, f, a):
		return true
	if o.hw.has("wd") and _F()._h4wd_draw_pfx(o, f, a):
		return true
	if o.hw.has("sa") and _F()._h4sa_draw_pfx(o, f, a):
		return true
	return _h4e_draw_pfx(o, f, a)


## 精英化第 4 批的程序粒子：h4_spike（岩刺缺图回退：拔起 → 停 → 缩回的金色尖刺）
static func _h4e_draw_pfx(o, f: Dictionary, a: float) -> bool:
	if str(f.kind) != "h4_spike":
		return false
	var cv = o.cv
	var u: float = 1.0 - a
	var k: float = minf(1.0, u / 0.25) if u < 0.6 else maxf(0.0, 1.0 - (u - 0.6) / 0.4)
	var h: float = float(f.h) * k
	if h < 2.0:
		return true
	var p: Vector2 = f.pos
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 0), p + Vector2(0, -h), p + Vector2(6, 0)]), Color(1.1, 0.8, 0.4, 0.95))
	cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-2, 0), p + Vector2(0, -h * 0.85), p + Vector2(2, 0)]), Color(2.2, 1.8, 0.9, 0.9))
	return true


static func h4_draw_over(o) -> void:
	if o.hw.has("sz"):
		_F()._h4sz_draw_over(o)
	if o.hw.has("wd"):
		_F()._h4wd_draw_over(o)
	if o.hw.has("sa"):
		_F()._h4sa_draw_over(o)
	_h4e_draw_over(o)


## 精英化第 4 批的上层画面：铃兰狐火拖尾、塞雷娅钙化拳的琥珀斑
static func _h4e_draw_over(o) -> void:
	var g = o.g
	var cv = o.cv
	if o.hw.has("sz") and not o.hw.sz.trails.is_empty():
		var tr: Dictionary = o.B.get("attack", _ED).get("merge", {}).get("trail", {})
		var tn: String = str(tr.get("tex", "fx_suzuran_bigfox_trail"))
		var life: float = float(tr.get("life", 1.0))
		var spec: Array = g.V6_FRAMES.get(tn, [5, 12.0])
		var has_tex: bool = g.tex.get(tn) != null
		for tg in o.hw.sz.trails:
			var i := 0
			for q in tg.pts:
				var u: float = clampf(1.0 - float(q.t) / life, 0.0, 1.0)
				if has_tex:
					fx_frame(cv, g, tn, int(spec[0]), mini(int(spec[0]) - 1, int(u * int(spec[0]))), q.pos + Vector2(0, -4), g.PX, Color(1, 1, 1, 0.95))
				elif not o._fx_strip("fx_suzuran_wisp", 4, int(g.t * 8.0) + i, q.pos + Vector2(0, -6), Vector2(0.5, 0.5), 0.0, Color(1, 1, 1, 1.0 - u)):
					_F()._h4_flame(o, q.pos + Vector2(0, 4), 12.0 * (1.0 - 0.5 * u), 1.0 - u)
				i += 1
	if o.hw.has("sa") and not o.hw.sa.slowed.is_empty():
		var cf: Dictionary = o.B.get("attack", _ED).get("calcify", {})
		var tn2: String = str(cf.get("tex", "fx_saria_amber_spot"))
		var spec2: Array = g.V6_FRAMES.get(tn2, [4, 8.0])
		var has2: bool = g.tex.get(tn2) != null
		for s in o.hw.sa.slowed:
			var e: Dictionary = s.e
			var left: float = float(s.until) - g.t
			var age: float = g.t - float(s.t0)
			var fr: int = 0 if age < 0.12 else (1 if left > 0.4 else (2 if left > 0.2 else 3))   # 出现 → 停在中间帧 → 最后 0.4 秒淡出
			for q in 2:
				var sd: float = float(s.seed) + q * 2.1
				var off := Vector2(sin(sd) * float(e.r) * 0.55, -float(e.r) * (0.35 + 0.4 * fmod(sd * 0.7, 1.0)))
				if has2:
					fx_frame(cv, g, tn2, int(spec2[0]), fr, e.pos + off, g.PX * 0.8, Color(1, 1, 1, clampf(left / 0.4, 0.0, 1.0)))
				else:
					cv.draw_circle(e.pos + off, 2.5, Color(H4_AMBER.r * 1.5, H4_AMBER.g * 1.3, H4_AMBER.b, 0.85 * clampf(left / 0.4, 0.0, 1.0)))


static func h4_draw_floor(o) -> void:
	if o.hw.has("sg"):
		_F()._h4sg_draw_floor(o)
	if o.hw.has("sz"):
		_F()._h4sz_draw_floor(o)
	if o.hw.has("wd"):
		_F()._h4wd_draw_floor(o)
	_h4e_draw_floor(o)


## 精英化第 4 批的地面画面：塞雷娅晶柱之间一圈淡琥珀墙脚（看得出哪里挡路）
static func _h4e_draw_floor(o) -> void:
	if not o.hw.has("sa") or o.hw.sa.crystals.is_empty():
		return
	var g = o.g
	var cv = o.cv
	var cr: Dictionary = o.hw.sa.crystals
	var t: float = float(cr.t)
	var al: float = clampf(t / 0.15, 0.0, 1.0) * clampf((float(cr.life) - t) / 0.2, 0.0, 1.0)
	var posts: Array = cr.posts
	var n: int = posts.size()
	if float(cr.b.get("wall", 6.0)) < 0.0:
		return
	for k in n:
		var a2: Vector2 = posts[k]
		var b2: Vector2 = posts[(k + 1) % n]
		cv.draw_line(a2, b2, Color(H4_AMBER.r, H4_AMBER.g, H4_AMBER.b, 0.16 * al), 7.0)
		cv.draw_line(a2, b2, Color(1.6, 1.25, 0.7, (0.32 + 0.08 * sin(g.t * 8.0 + k)) * al), 1.5)


static func h4_draw_auras(o) -> void:
	if o.hw.has("sg"):
		_F()._h4sg_draw_auras(o)
	if o.hw.has("sz"):
		_F()._h4sz_draw_auras(o)
	if o.hw.has("sa"):
		_F()._h4sa_draw_auras(o)


# ---------------------------------------------------------------- 本段的校验

static func _h4_block(b: Dictionary, p: String, kind: String, ctx: Dictionary, tag: String) -> bool:
	if not tag in H4_TAGS:
		return false
	var errs: Array = ctx.errs
	var where_ok := {
		"shape.hammer": ["attack"], "shape.foxfire": ["attack"], "shape.cannon": ["attack"], "shape.bash": ["attack"],
		"verb.leap_slam": ["skill", "instant"], "verb.cmd_wave": ["skill", "instant"], "verb.fox_cast": ["skill", "instant"],
		"verb.cannon_exec": ["skill", "instant"], "verb.cannon_load": ["skill", "instant"], "verb.saria_heal": ["skill", "instant"], "verb.calc_field": ["skill", "instant"], "verb.amber_ring": ["skill", "instant"],
		"verb.foxlight": ["sustain"], "verb.souls": ["sustain"], "verb.guard_ring": ["sustain"], "verb.calc_orbs": ["sustain"], "verb.suit": ["sustain"],
	}
	if not kind in where_ok[tag]:
		errs.append("%s：「%s」不能放在这里（%s；只能在 %s）" % [p, tag, kind, " / ".join(where_ok[tag])])
		return true
	match tag:
		"shape.hammer":
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_num(b, "half", p, ctx, true, 0.05, PI)
			_num(b, "hit_sp", p, ctx, false, 0.0, 10.0)
			_src(b, p, ctx, true)
			for k in ["quake", "breach"]:
				if b.has(k):
					if not (b[k] is Dictionary):
						errs.append("%s.%s 必须是对象" % [p, k])
					else:
						_src(b[k], p + "." + k, ctx, true)
						_num(b[k], "mult", p + "." + k, ctx, true, 0.0, 20.0)
			if b.has("heavy") and not (b.heavy is Dictionary and b.heavy.has("cond")):
				errs.append(p + ".heavy 必须是带 cond 的对象")
			if b.has("heavy") and b.heavy is Dictionary and b.heavy.has("anim") and not (ctx.sprites is Dictionary and ctx.sprites.has(str(b.heavy.anim))):
				errs.append("%s.heavy.anim「%s」不是 sprites 里的帧条键" % [p, str(b.heavy.anim)])
			_h4e_check(b, p, ctx, tag)
		"verb.leap_slam":
			for k in ["r", "mult", "t", "dist"]:
				_num(b, k, p, ctx, true, 0.0, 1000.0)
			if not str(b.get("from", "self")) in ["self", "leader"]:
				errs.append(p + ".from 只能是 self / leader")
			_src(b, p, ctx, true)
		"verb.cmd_wave":
			for k in ["r", "dur", "mult"]:
				_num(b, k, p, ctx, true, 0.0, 1000.0)
			_src(b, p, ctx, true)
		"shape.foxfire":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			_num(b, "shots", p, ctx, true, 1.0, 12.0)
			_num(b, "speed", p, ctx, true, 10.0, 3000.0)
			_src(b, p, ctx, true)
			if b.has("merge") and not (b.merge is Dictionary and b.merge.has("mult")):
				errs.append(p + ".merge 必须是对象 {cond, every, all, mult, spd, life, r}")
			if b.has("tip") and not (b.tip is Array and b.tip.size() == 2):
				errs.append(p + ".tip 必须是 [x, y]")
			_h4e_check(b, p, ctx, tag)
		"verb.foxlight":
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			for k in ["slow", "heal"]:
				if b.has(k) and not (b[k] is Array):
					errs.append("%s.%s 必须是数组" % [p, k])
			if b.has("hearth") and b.hearth is Dictionary:
				_src(b.hearth, p + ".hearth", ctx, true)
		"verb.fox_cast":
			_num(b, "buff", p, ctx, true, 0.0, 5.0)
			_num(b, "haze", p, ctx, false, 0.1, 60.0)
		"shape.cannon":
			_num(b, "range", p, ctx, true, 10.0, 2000.0)
			_num(b, "aoe", p, ctx, true, 1.0, 400.0)
			_src(b, p, ctx, true)
			for k in ["quake_src"]:
				if not ctx.srcs.has(str(b.get(k, ""))):
					errs.append("%s.%s「%s」没在 hit_sources 里登记" % [p, k, str(b.get(k, ""))])
			if b.has("shade") and b.shade is Dictionary:
				_src(b.shade, p + ".shade", ctx, true)
			if b.has("giant") and b.giant is Dictionary:
				_src(b.giant, p + ".giant", ctx, true)
			_h4e_check(b, p, ctx, tag)
		"verb.cannon_exec":
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
		"verb.cannon_load":
			_num(b, "n", p, ctx, true, 1.0, 60.0)
		"verb.souls":
			_num(b, "n", p, ctx, true, 1.0, 6.0)
			_num(b, "cd", p, ctx, not b.get("follow", false), 0.1, 60.0)
			_h4e_check(b, p, ctx, tag)
		"shape.bash":
			_num(b, "r", p, ctx, true, 1.0, 600.0)
			_src(b, p, ctx, true)
			_h4e_check(b, p, ctx, tag)
		"verb.guard_ring":
			_num(b, "r", p, ctx, true, 1.0, 400.0)
			_num(b, "every", p, ctx, true, 0.05, 10.0)
		"verb.calc_orbs":
			if not (b.get("n_by", null) is Array):
				errs.append(p + ".n_by 必须是数组 [{cond, n}]")
			_src(b, p, ctx, true)
		"verb.saria_heal":
			_num(b, "pct", p, ctx, true, 0.0, 1.0)
			if b.has("syringe") and b.syringe is Dictionary:
				_src(b.syringe, p + ".syringe", ctx, true)
		"verb.calc_field":
			_num(b, "dur", p, ctx, true, 0.1, 60.0)
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			if b.has("shatter") and b.shatter is Dictionary:
				_src(b.shatter, p + ".shatter", ctx, true)
		"verb.amber_ring":
			_num(b, "n", p, ctx, true, 2.0, 16.0)
			_num(b, "r", p, ctx, true, 10.0, 400.0)
			_num(b, "life", p, ctx, true, 0.1, 20.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_src(b, p, ctx, true)
		"verb.suit":
			_num(b, "seg_t", p, ctx, true, 0.1, 60.0)
			_num(b, "r", p, ctx, true, 1.0, 1000.0)
			_num(b, "mult", p, ctx, true, 0.0, 20.0)
			_h4e_check(b, p, ctx, tag)
	return true


## 精英化第 4 批的参数校验（迁移时没有）
static func _h4e_check(b: Dictionary, p: String, ctx: Dictionary, tag: String) -> void:
	var errs: Array = ctx.errs
	var subs := {"shape.hammer": ["crush"], "shape.foxfire": ["brand"], "shape.cannon": ["gift"], "shape.bash": ["calcify"], "verb.souls": ["fire"], "verb.suit": ["pillars"]}
	for k in subs.get(tag, []):
		if b.has(k) and not (b[k] is Dictionary and b[k].has("cond")):
			errs.append("%s.%s 必须是带 cond 的对象" % [p, k])
	match tag:
		"shape.hammer":
			if b.get("crush", null) is Dictionary:
				_src(b.crush, p + ".crush", ctx, true)
				_num(b.crush, "r", p + ".crush", ctx, true, 1.0, 400.0)
				_num(b.crush, "mult", p + ".crush", ctx, true, 0.0, 10.0)
				_num(b.crush, "cap", p + ".crush", ctx, false, 1.0, 12.0)
			var br = b.get("breach", null)
			if br is Dictionary and br.get("spikes", null) is Dictionary:
				_num(br.spikes, "step", p + ".breach.spikes", ctx, true, 8.0, 400.0)
		"shape.foxfire":
			if b.get("brand", null) is Dictionary:
				_num(b.brand, "value", p + ".brand", ctx, true, 0.0, 1.0)
				_num(b.brand, "dur", p + ".brand", ctx, true, 0.1, 10.0)
			var mg = b.get("merge", null)
			if mg is Dictionary and mg.has("trail"):
				if not (mg.trail is Dictionary and mg.trail.has("cond")):
					errs.append(p + ".merge.trail 必须是带 cond 的对象")
				else:
					_src(mg.trail, p + ".merge.trail", ctx, true)
					for k in ["life", "every", "mult", "r", "step"]:
						_num(mg.trail, k, p + ".merge.trail", ctx, true, 0.0, 100.0)
		"shape.cannon":
			if b.get("gift", null) is Dictionary:
				_num(b.gift, "mult", p + ".gift", ctx, true, 0.0, 10.0)
		"verb.souls":
			if b.get("fire", null) is Dictionary:
				_src(b.fire, p + ".fire", ctx, true)
				_num(b.fire, "every", p + ".fire", ctx, not b.get("follow", false), 0.1, 60.0)
				_num(b.fire, "mult", p + ".fire", ctx, true, 0.0, 10.0)
				_num(b.fire, "gap", p + ".fire", ctx, false, 0.0, 2.0)
				_num(b.fire, "spread", p + ".fire", ctx, false, 0.0, 600.0)
		"shape.bash":
			if b.get("calcify", null) is Dictionary:
				_num(b.calcify, "pct", p + ".calcify", ctx, true, 0.0, 0.9)
				_num(b.calcify, "dur", p + ".calcify", ctx, true, 0.1, 10.0)
		"verb.suit":
			if b.get("pillars", null) is Dictionary:
				var pc: Dictionary = b.pillars
				_src(pc, p + ".pillars", ctx, true)
				_num(pc, "n", p + ".pillars", ctx, true, 3.0, 16.0)
				_num(pc, "r", p + ".pillars", ctx, true, 20.0, 400.0)
				_num(pc, "life", p + ".pillars", ctx, true, 0.1, 10.0)
				_num(pc, "mult", p + ".pillars", ctx, true, 0.0, 10.0)
				_num(pc, "elite_push", p + ".pillars", ctx, false, 0.0, 1.0)
