## 数据驱动干员（docs/61）：读干员 JSON 的 blocks 段，把普攻 / 技能 / 特性 / 天赋 / 成长节点都交给积木（characters/op_blocks.gd）执行。
## 和手写干员一样继承 character.gd、只走 op_api；同一份数值写成手写脚本（tests/data_ops/eqtest_hand.gd）同 seed 逐字节相同（check.py blocks_eq）。
## 每帧顺序（docs/61 §7）：技能计时 → 延迟队列 → 常驻积木（局部倍率 → 属性重建 → 治疗 / 灯火 / tick / 软减速 / 绕行体）→ 技能起手 → 普攻起手。
extends "res://scripts/characters/character.gd"

## B6 ②（docs/101 §7.3.6）：积木按定义所在的 blocks 文件直连（原 const OB = preload(op_blocks.gd) 门面）；ObCheck、SegAngelina 已在父类 character.gd 声明，这里不重复（GDScript 不许子类重名）
## 发版排查（10-16，bisect 到 dada5e32）：这 20 个名字原来各自单开一次 preload，其实全在同一条单继承链上
## （ob_core → ob_elite → … → seg_ulpianus → … → seg_skalter，见 character.gd 顶部注释）；链上最靠后的 SegSkalter
## 早就 transitively 带出其余全部 19 个，21 条并行路径（含 character.gd 的 2 条）同时解析同一条链，是 Godot 退出报
## resources still in use 的根（verbose 指向 enemy_db / balance / data / art / look）。真正 preload 只留 SegSkalter 一个，
## 其余全改成别名（GDScript 继承链上不加前缀就能互相访问，和原来逐个 preload 时的调用结果完全一样，不是功能改动）
const AttackPhases = preload("res://scripts/characters/blocks/attack_phases.gd")
var phases: Dictionary = {}
const SkillLifecycle = preload("res://scripts/characters/blocks/skill_lifecycle.gd")
var lifecycle: Dictionary = {}
var effect_skill := -1  # Only skill do execution may bind skill-owned effects.
const NativeMotion = preload("res://scripts/characters/native_motion.gd")
const M3Hp = preload("res://scripts/characters/blocks/m3_hp.gd")   # Mon3tr 血条与治疗分配（10-29）
const Responses = preload("res://scripts/characters/blocks/responses.gd")
var rsp: Dictionary = {}   # 响应动作（docs/118）：触发沿 / 冷却记录
var native_motion: Dictionary = {}

const VisGrowth = preload("res://scripts/characters/blocks/vis_growth.gd")   # 可见成长藏品（docs/163）
const SegSkalter = preload("res://scripts/characters/blocks/seg_skalter.gd")
const ObCore = SegSkalter
const ObElite = SegSkalter
const ObFx = SegSkalter
const ObHw = SegSkalter
const ObSummon = SegSkalter
const ObVortex = SegSkalter
const SegExusiai = SegSkalter
const SegEyjafjalla = SegSkalter
const SegHoshiguma = SegSkalter
const SegIrene = SegSkalter
const SegLogos = SegSkalter
const SegLumen = SegSkalter
const SegMizuki = SegSkalter
const SegSaria = SegSkalter
const SegSiege = SegSkalter
const SegSkadi = SegSkalter
const SegSpecter = SegSkalter
const SegTexas = SegSkalter
const SegUlpianus = SegSkalter

var B: Dictionary = {}                 # 编译后的 blocks（$ 已解析成数字、cond 已解析）
var tags_all: Dictionary = {}          # B 里出现过的全部 tag（B6 ④：常驻段没有对应 tag 时跳过逐块匹配）
var cd := 0.5                          # 普攻冷却
var s_t: Array = [0.0, 0.0, 0.0]       # 持续型技能剩余秒数
var s_dur: Array = [0.0, 0.0, 0.0]     # 持续型技能总时长（HUD）
var perm_on: Array = [false, false, false]   # 永久型技能已放出（出手帧起生效）
var taken: Array = []                  # 已选的 custom 节点 id（按选下顺序）
var nodes_taken := ""                  # 同上的字符串（成长节点测试看「当场有变化」）
var far_n := 0                         # 远程形态（attack.far count:false）出手次数，不进 every_n；测试数「出招」时与 atk_n 相加
var atk_n := 0                         # 普攻出手次数（trig.every_n）
var pending: Array = []                # 延迟执行：[{t, do}]
var loc := {"zone": 1.0, "dmg": 1.0, "heal": 1.0, "interval": 1.0, "area": 1.0, "force": 1.0, "force_lit": 1.0, "atk": 1.0}   # 本干员局部倍率（docs/61 §5.1；area / force / force_lit 见安洁莉娜段；atk 只乘普攻，精英化段）
var no_attack := false
var zr := 0.0                          # 本帧区域半径（上一帧的值给 in_zone 条件用）
var _mods: Array = []                  # 已写进 g.stats 的修正 [stat, op, value, scope]
var _acc: Dictionary = {}              # 常驻积木的累计器（_uid → 秒）
var _state: Dictionary = {}            # 常驻积木的状态（软减速的位置记忆、绕行体角度）
var _warned := {}
var _fxt: Dictionary = {}              # 画面帧条（docs/61 §5.6）：常驻积木上 every 条目的计时（_uid → [秒…]），纯画面
var _fxb: Dictionary = {}              # 贴身层（behind / front）：_uid → {b, el, fade}；fade < 0 = 生效中，≥ 0 = 退出后淡出剩余秒数
var tx: Dictionary = {}                # 德克萨斯段（op_blocks.gd 末尾）：冲刺 / 残像 / 延迟队列等状态
var ext := {}                          # 积木扩展段的运行时状态（能天使：弹体 / 计数器 / 次数型技能，op_blocks.gd 末尾）
var kill_w := 1.0                      # trig.on_kill 执行期间这次击杀的权重：怪物密度缩放过的普通怪 = e.dk（1/k），其余 1（docs/50 §16.8）
var sm := {}                           # 召唤 / 封印段（op_blocks.gd 末尾，docs/61 §15）：召唤物、封印标记、护盾、治疗光环计时；空 = 用不到
var mf := {}                           # 召唤物扩展段（docs/61 §15.9）：限时减伤、召唤物倍率表、已执行的 on_deploy；空 = 用不到
var mhook_cd := {}                     # 联动段（docs/123 §2.7）：trig.on_mate_hook 每块的上次触发时刻（不放 el：el 非空会被精英化段当成「用得到」）
var gn := {}                           # 成长节点（docs/202）的扩展状态：浊心斯卡蒂的潮声层数 / 共振列表 / 击杀节流；其余干员恒空
var el := {}                           # 精英化段（docs/91 第 1 批，op_blocks.gd 末尾）：限时增益、叠层、往返弹体、状态冷却；空 = 用不到


## 往返弹体（shape.boomerang，星熊「般若回旋」）还在外面：本体画无盾（character._noshield）
func prop_out() -> bool:
	return not el.is_empty() and not el.get("boom", []).is_empty()
var hw := {}                           # 手写迁移段（docs/91 第 2 批，op_blocks.gd 末尾）：basis、连斩、浪墙、弹体、锚……；空 = 用不到
var atk_live := false                  # 正在结算普攻的那一下（局部倍率 atk 只乘这时的伤害）
var e5 := {}                           # 精英化第 5 批段（op_blocks.gd 末尾）：ah = 上一次普攻命中的敌人 id 表（shape.circle among: attack）；空 = 用不到
var zmode := 1.0                       # 本帧 verb.mode 的 zone_mult 乘积（召唤物区域 zone.mode: false 时除掉，精英化第 5 批段）


func _init(game, def_: Dictionary) -> void:
	super(game, def_)
	B = ObCore.compile(def)
	pierce_atk = _scan_pierce_atk(B)
	tags_all = ObCore.tag_set(B, {})
	# 召唤物扩展段（§15.9）：普攻 shape.support 的 when 条件、首拍；有没有 trig.on_deploy（每帧只在有时才查）
	var a: Dictionary = B.get("attack", {})
	if str(a.get("shape", "")) == "support":
		if a.get("when", null) is String:
			a.when = ObCore.parse_cond(str(a.when), def.get("base", {}))
		cd = float(a.get("first", cd))
	elif a.has("first"):   # 手写迁移段：首击冷却（手写干员各自的 var cd 初值）
		cd = float(a.first)
	ObHw.hw_init(self)
	var dep := false
	var mate := false
	var mhook := false
	for sec in ["trait", "talent"]:
		for t in B.get(sec, []):
			dep = dep or str(t.get("_tag", "")) == "trig.on_deploy"
			mate = mate or str(t.get("_tag", "")) == "trig.on_mate_attack"
			mhook = mhook or str(t.get("_tag", "")) == "trig.on_mate_hook"
	for k in B.get("progression", {}):
		for t in _node_list(B.progression[k]):
			dep = dep or str(t.get("_tag", "")) == "trig.on_deploy"
			mate = mate or str(t.get("_tag", "")) == "trig.on_mate_attack"
			mhook = mhook or str(t.get("_tag", "")) == "trig.on_mate_hook"
	B["_mf_deploy"] = dep
	B["_el_mate"] = mate   # 精英化段：有没有 trig.on_mate_attack（队友出手时才查）
	B["_el_mate_hook"] = mhook   # 联动段（docs/123 §2.7）：有没有 trig.on_mate_hook（队友钩索拖回到位时才查）
	B["_e5_among"] = SegSkalter.e5_scan(B)   # 精英化第 5 批段：有 among 的积木才记普攻命中表


## 成长节点的积木：一块，或数组（§15.9）
static func _node_list(v) -> Array:
	return v if v is Array else [v]


func _src_tag() -> String:
	return "blk:" + id


# ---------------------------------------------------------------- 区域 / 技能状态（op_blocks 回调）

## 区域中心（docs/61 §3.1）：leader = 主控（图鉴演示以自己为中心）
func zone_c() -> Vector2:
	var z: Dictionary = B.get("zone", {})
	if str(z.get("center", "self")) == "leader" and g.demo_op == "":
		return g.ppos
	return pos


func zone_r() -> float:
	return zr


func _zone_r_now() -> float:
	return float(B.get("zone", _ED).get("r", 0.0)) * stat(&"op_range") * float(loc.zone)


func in_zone(p: Vector2) -> bool:
	var c := zone_c()
	if c != Vector2.INF and p != Vector2.INF and p.distance_to(c) <= zr:
		return true
	return not sm.is_empty() and p != Vector2.INF and SegSkalter.e5_in_zone(self, p)   # 精英化第 5 批段：召唤物自带的区域（并集，不叠加）


func skill_on(i: int) -> bool:
	return s_t[i] > 0.0 or perm_on[i] or ammo[i] > 0 or SkillLifecycle.left(self, i) > 0.0 or (not hw.is_empty() and SegEyjafjalla.hw_active_left(self, i) > 0.0)


func skill_active_left(i: int) -> float:
	var effect_left := SkillLifecycle.left(self, i)
	if effect_left >= 0.0:
		return maxf(effect_left, attack_t) if hw.has("mz") and sq_i == i and act_kind == "attack" else effect_left
	var left := AttackPhases.active_left(self, i)
	if left >= 0.0:
		return left
	if not hw.is_empty():
		var hl: float = SegEyjafjalla.hw_active_left(self, i)   # 手写迁移段：连续喷发 / 锁定 / 咒域按自己的计时
		if hl >= 0.0:
			return hl
	return maxf(s_t[i], SegExusiai.exu_ammo_left(self, i))   # 次数型（dur.ammo）返回剩余发数


func skill_effect_status(i: int) -> Array:
	var out := SkillLifecycle.status(self, i)
	if not phases.is_empty() and phases.skill == i:
		out.append({"effect": "attack_phases", "active": AttackPhases.active_left(self, i) > 0.0,
			"background": false, "remaining": AttackPhases.active_left(self, i), "total": s_dur[i], "unit": "seconds"})
	if out.is_empty() and s_t[i] > 0.0:
		out.append({"effect": "duration", "active": true, "background": false, "remaining": s_t[i], "total": s_dur[i], "unit": "seconds"})
	if out.is_empty():
		out.append({"effect": "instant", "active": false, "background": false, "remaining": 0.0, "total": 0.0, "unit": "instant"})
	return out


func skill_active_dur(i: int) -> float:
	return maxf(SkillLifecycle.duration(self, i), s_dur[i]) if s_dur[i] > 0.0 or SkillLifecycle.duration(self, i) > 0.0 else 1.0


func _swing_radius() -> float:
	var a: Dictionary = B.get("attack", {})
	return ObCore.shape_radius(self, a) if a.has("shape") and str(a.shape) != "support" else 90.0


# ---------------------------------------------------------------- 成长

func on_custom_node(nid: String, _choice: String = "") -> void:
	taken.append(nid)
	nodes_taken = ",".join(taken)


func cancel_skill_action() -> void:
	attack_t = 0.0
	fire_t = -1.0
	attack_phased = false
	native_motion.clear()
	vis_anim = ""
	manual_buf = 0.0
	manual_buf_dir = Vector2.ZERO
	manual_buf_pt = Vector2.INF
	manual_dir = Vector2.ZERO
	manual_pt = Vector2.INF
	atk_aim = Vector2.ZERO
	act_kind = "attack"
	act_anim = "attack"
	_sq_clear()


func on_leave() -> void:
	AttackPhases.cancel(self)
	cancel_skill_action()
	for i in 3:
		if SkillLifecycle.owns(self, i):
			perm[i] = false
	SkillLifecycle.cancel(self)
	if hw.has("mz"):
		SegMizuki.h3_cancel(self)
	SegAngelina.airborne_clear(self)
	SegSkalter.h4_souls_leave(self)   # 魂灵之影离场画面（seg_wisadel，纯画面；积木链末端 SegSkalter 可调全链静态函数）
	ObSummon.sm_clear(self)   # 召唤 / 封印段
	g.stats.remove_source(_src_tag())
	_mods = []
	refresh_stats()


## 当前生效的触发积木（docs/61 §5.5 的固定顺序：trait → talent → 已选节点 → elite1 / elite2）
const _EA: Array = []
const _ED: Dictionary = {}
const _ELITE_KEYS := [["elite1", 1], ["elite2", 2]]


## 生效中的触发积木（特性 + 精一后天赋 + 已选节点 + 精英化节点）。只随精英化与节点数变，按两者缓存（docs/101 S9；调用方只遍历、不改）
var _tg_key := -1
var _tg: Array = []

func _trigs() -> Array:
	if g.opt_old & 65536:
		return _trigs_build()
	var k: int = elite * 4096 + taken.size()
	if k != _tg_key:
		_tg = _trigs_build()
		_tg_key = k
	return _tg


func _trigs_build() -> Array:
	var out: Array = []
	out.append_array(B.get("trait", []))
	if elite >= 1:
		out.append_array(B.get("talent", []))
	var pg: Dictionary = B.get("progression", {})
	for nid in taken:
		if pg.has(nid):
			out.append_array(_node_list(pg[nid]))
	for k in _ELITE_KEYS:
		if elite >= k[1] and pg.has(k[0]):
			out.append_array(_node_list(pg[k[0]]))
	return out


# ---------------------------------------------------------------- 每帧

func update(dt: float) -> void:
	cd -= dt
	var prev_s: Array = s_t.duplicate()
	for i in 3:
		if s_t[i] > 0.0:
			s_t[i] = maxf(0.0, s_t[i] - dt)
	AttackPhases.tick(self, dt)
	var hw_busy: bool = ObHw.hw_tick(self, dt) if not hw.is_empty() else false   # 手写迁移段：浪墙 / 弹体 / 地面 / 锚（按手写干员 update 的先后）；true = 本帧不起手
	NativeMotion.tick(self, dt)
	SkillLifecycle.tick(self)
	Responses.tick(self)   # 响应动作：队长冲刺 / 开技能 / 指挥切换（docs/118）
	ObSummon.mf_tick(self, dt, prev_s)   # 召唤物扩展段（§15.9）：限时减伤计时、trig.on_deploy、带 at 的 trig.on_skill_end
	_tick_pending(dt)
	_sustain(dt)
	_run_fx(dt)
	if hw.has("mz"):
		SegMizuki.h3_tick_effects(self, dt)
	_tick_shots(dt)
	VisGrowth.tick(self, dt)   # 可见成长：额外弹 / 连发队列 / 剑气（vg 为空时直接返回）
	SegExusiai.exu_tick(self, dt)   # 能天使段：技能 end、普攻锁、连射队列、弹体
	ObSummon.sm_tick(self, dt)    # 召唤 / 封印段：召唤物、护盾计时、封印标记（sm 为空时直接返回）
	ObElite.el_tick(self, dt)    # 精英化段：往返弹体（el 为空时直接返回）
	SegSkalter.sk_gn_tick(self, dt)   # 成长节点（docs/202）：浊心斯卡蒂的潮声层数（其余干员第一行就返回）
	if SegTexas.tx_update(self, dt):   # 德克萨斯段：冲刺中不起手
		return
	if hw_busy or (not hw.is_empty() and ObHw.hw_busy(self)):   # 手写迁移段：喷发序列 / 锚在外面时不起手（同手写的 return）
		return
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		if not hw.is_empty() and SegEyjafjalla.hw_instant(self, ready):   # 手写迁移段：cast: instant（充满当帧生效、不播技能动作）
			return
		start_skill(ObSummon.mf_skill_aim(self, ready), ready)   # blocks.skills[i].aim（§15.9）；没写 = INF 不转身
		return
	if AttackPhases.attack_locked(self):
		return
	if str(cur_attack().get("shape", "")) in ObHw.H3_ATTACKS:   # 手写迁移段第 3 批：刺击 / 环斩 / 荧光的起手（荧光要先累计治疗计时）
		SegIrene.h3_attack_start(self, cur_attack(), dt)
		return
	if str(cur_attack().get("shape", "")) in ObHw.H4_ATTACKS:   # 手写迁移段第 4 批：锤击 / 狐火 / 炮击 / 拳击的起手
		ObHw.h4_attack_start(self, cur_attack(), dt)
		return
	if no_attack or cd > 0.0 or ObElite.el_attack_locked(self) or (not hw.is_empty() and SegUlpianus.hw_attack_locked(self)):   # 精英化段：往返弹体 / 掷锚（lock）在外面时不普攻
		return
	var a: Dictionary = cur_attack()
	var at := Vector2.INF
	match str(a.get("shape", "")):
		"support":   # 召唤物扩展段（§15.9）：不造成伤害的普攻，every 一拍，when 成立才朝主控起手（手动普攻不管它）
			cd = float(a.get("every", 1.0)) / stat(&"op_aspd") * float(loc.interval)
			if ObCore.cond_true(self, a.get("when", {})):
				start_attack(g.ppos)
			return
		"circle":
			if str(a.get("center", "")) == "front":   # 手写迁移段：锚击砸在身前（手动普攻 A 类）
				at = SegUlpianus.hw_front_aim(self, a)
			else:
				var c: Vector2 = ObCore.shape_center(self, a)
				if not phases.is_empty() and str(a.get("center", "")) == "target":
					c = pos
				var r: float = float(a.get("range", 0.0)) * stat(&"op_range") if a.has("range") else ObCore.shape_radius(self, a)
				if c != Vector2.INF:
					at = atk_point(nearest_enemies(1, r, c), r)   # 手动普攻（v2.5）：不分方向，只受闸门
		"cone":
			var r2: float = ObCore.shape_radius(self, a)
			var sr = a.get("skill_reach")   # 技能期间起手距离换成 r（德克萨斯剑雨滂沱·次元斩：前方 rift_r 内有敌人就出手）
			if sr is Dictionary and s_t[int(sr.skill)] > 0.0:
				r2 = float(sr.r) * stat(&"op_range")
			var fp0: Dictionary = _far_pick(a)
			if fp0.is_empty():
				at = atk_point(nearest_enemies(1, r2 + 30.0, pos), r2)   # 手动普攻 A 类
			else:
				at = _far_aim(a, fp0, r2)   # attack.far：按距离（手动 = 按指向）选近战 / 远程
		"line":
			var rl: float = float(a.get("len", 0.0)) * stat(&"op_range")
			at = atk_point(nearest_enemies(1, rl, pos), rl)   # 手动普攻 A 类
		"point_aoe":
			var tp: Vector2 = SegAngelina.point_aoe_target(self, a)
			atk_to = tp
			at = atk_point([{"pos": tp}] if tp != Vector2.INF else [], float(a.get("range", 300.0)) * stat(&"op_range"))   # 手动普攻 A 类（落点 aim_land）
		"dash_line":
			at = SegTexas.tx_attack_point(self, a)   # 德克萨斯段
		"projectile":   # 能天使段：手动普攻 B 类
			at = SegExusiai.exu_aim(self, a)
		"shell":   # 手写迁移段：法术弹（手动普攻 A 类，落点 aim_land）
			at = SegEyjafjalla.hw_shell_aim(self, a)
		"bolt":   # 手写迁移段：飘飞咒文弹（手动普攻 B 类）
			at = SegLogos.hw_bolt_aim(self, a)
	if at == Vector2.INF:
		atk_far = -1
		cd = idle_cd(float(B.get("attack", _ED).get("idle", 0.2)))   # 手写迁移段：attack.idle（缺省 0.2）
	else:
		var fp1: Dictionary = _far_pick(a) if atk_far == 1 else {}
		cd = float(fp1.get("every", B.get("attack", _ED).get("every", 1.0))) / stat(&"op_aspd") * float(loc.interval)
		var rp := _replace_trig(atk_n + 1) if fp1.is_empty() else {}   # 精英化段：这一次普攻被 trig.every_n replace 换掉时播它的帧条（远程形态不换）
		var an: String = str(rp.get("anim", ""))
		if an == "" and a.has("anim"):   # 手写迁移段：普攻（含 swap_attack 换上的形状）自己的帧条
			an = str(a.anim)
		if not fp1.is_empty() and fp1.has("anim"):
			an = str(fp1.anim)   # 远程形态自己的帧条（拉普兰德 throw）
		start_attack(at if a.get("turn", true) else Vector2.INF, 0.5, 0.25, an)


func _tick_pending(dt: float) -> void:
	if pending.is_empty():
		return
	var due: Array = []
	for p in pending:
		p.t -= dt
		if p.t <= 0.0:
			due.append(p)
	pending = pending.filter(func(p): return p.t > 0.0)
	for p in due:
		var keep: Dictionary = ObHw.hw_push(self, p.get("bs", {}))   # 手写迁移段：延迟执行带着排队时的 basis
		var ah = e5.get("ah", {})
		if p.has("ah"):   # 精英化第 5 批段：延迟执行用排队那一刻的普攻命中表
			e5["ah"] = p.ah
		_exec_list(p.do, p.get("at", Vector2.INF))
		if p.has("ah"):
			e5["ah"] = ah
		if p.has("combo"):
			ObHw.hw_combo_next(self, int(p.combo))
		ObHw.hw_pop(self, keep)


## 手写迁移段：常驻积木的局部倍率与属性立刻重算（层数变了、永久技能出手当下，同手写的 refresh_stats；不跑治疗 / 计时等副作用）
func _restat() -> void:
	_sustain(0.0, true)


## 常驻积木：先收集本帧生效的（条件在这里各求值一次），再按 局部倍率 → 属性 → 副作用 三遍执行
func _sustain(dt: float, stats_only := false) -> void:
	var act: Array = []   # 常驻效果积木与 trig.tick，按固定顺序
	for t in B.get("trait", _EA):   # _EA / _ED：只读的空缺省值，不每帧新建空容器（docs/101 S9）
		_collect_trig(t, act)
	var sk: Array = B.get("skills", _EA)
	for i in mini(3, sk.size()):
		if skill_on(i):
			for b in sk[i].get("do", _EA):
				if ObCore.cond_true(self, b.get("cond", _ED)):
					act.append(b)
	if elite >= 1:
		for t in B.get("talent", _EA):
			_collect_trig(t, act)
	var pg: Dictionary = B.get("progression", _ED)
	for nid in taken:
		if pg.has(nid):
			for t in _node_list(pg[nid]):
				_collect_trig(t, act)
	for k in _ELITE_KEYS:
		if elite >= k[1] and pg.has(k[0]):
			for t in _node_list(pg[k[0]]):
				_collect_trig(t, act)
	if B.has("response") and Responses.on():   # 响应动作的站定类（trig.passive + still 条件，docs/118）
		for t in B.response:
			if str(t.get("_tag", "")) == "trig.passive":
				_collect_trig(t, act)
	ObElite.el_sustain_collect(self, act)   # 精英化段：生效中的限时增益（verb.buff_timed）排在最后；记下 st.stack
	# 一：局部倍率
	var add := {}
	var mul := {}
	for k in loc:
		add[k] = 0.0
		mul[k] = 1.0
	no_attack = false
	var zm := 1.0
	for b in act:
		match str(b.get("_tag", "")):
			"verb.buff_self", "verb.buff_timed":   # buff_timed（精英化段）生效期间等同 buff_self，op 缺省 add
				var st: String = str(b.stat)
				if loc.has(st):
					if str(b.get("op", "add")) == "add":
						add[st] += float(b.value)
					elif b.get("power", false):   # 手写迁移段：局部倍率也吃技能强度（value × skill_power，先乘好再乘进去，同手写的 (k × 技能强度)）
						mul[st] *= float(b.value) * skill_power()
					else:
						mul[st] *= float(b.value)
			"verb.mode":
				if b.has("dmg_mult"):
					mul.dmg *= float(b.dmg_mult) * (skill_power() if b.get("power", false) else 1.0)
				if b.has("zone_mult"):
					mul.zone *= float(b.zone_mult)
					zm *= float(b.zone_mult)
				if b.has("interval_mult"):
					mul.interval *= float(b.interval_mult)
				if b.get("no_attack", false):
					no_attack = true
	for k in loc:
		loc[k] = (1.0 + add[k]) * mul[k]
	zmode = zm
	zr = _zone_r_now()
	# 二：g.stats 修正（与上一帧相同就不动；不同就整组重建，顺序固定）
	var want: Array = []
	for b in act:
		match str(b.get("_tag", "")):
			"verb.buff_self", "verb.buff_timed":
				if not loc.has(str(b.stat)):
					want.append([str(b.stat), str(b.get("op", "add")), float(b.value) * (skill_power() if b.get("power", false) else 1.0), op_key])
			"verb.lamp":
				if b.has("loss_mult"):
					want.append(["light_loss", "mult", float(b.loss_mult), ""])
				if b.has("decay_mult"):   # 手写迁移段第 3 批：受击灯火损失倍率（流明「沛霖」）
					want.append(["light_decay", "mult", float(b.decay_mult), ""])
			"verb.buff_leader":
				want.append([str(b.stat), str(b.op), float(b.value), ""])
			"aura.atk", "aura.aspd", "aura.skill_power", "aura.range":
				var v: float = float(b.value)
				if b.get("power", false):
					v *= skill_power()
				if b.has("per"):
					v *= float(mini(ObCore.count_others(self, str(b.per)), int(b.get("cap", 99))))
				if v != 0.0:
					for m in ObCore.aura_members(self, str(b.scope)):
						if b.get("exclude_self", false) and m == self:
							continue
						want.append([ObCore.AURA_STAT[str(b.aura)], "add", v, m.op_key])
	SegTexas.tx_sustain(self, act, want)   # 德克萨斯段：冲刺长度 / 宽度、主控属性
	if want != _mods:
		g.stats.remove_source(_src_tag())
		for m in want:
			g.stats.add(StringName(m[0]), m[1], m[2], _src_tag(), m[3])
		_mods = want
		refresh_stats()
	if stats_only:
		return
	# 三：副作用（治疗、灯火、tick、软减速、绕行体）
	var seen := {}
	for b in act:
		var u: int = int(b.get("_uid", 0))
		match str(b.get("_tag", "")):
			"verb.heal":
				if b.has("every"):
					seen[u] = true
					_acc[u] = float(_acc.get(u, 0.0)) + dt
					if _acc[u] >= float(b.every):
						_acc[u] -= float(b.every)
						_heal(b)
			"verb.lamp":
				if b.has("per_sec"):
					g.lamp = clampf(g.lamp + float(b.per_sec) * dt, 0.0, g.lamp_cap)
			"trig.tick":
				seen[u] = true
				if b.get("countdown", false):   # 手写迁移段：倒计时写法（生效当帧起算 every，到点执行并重置为 every）
					_acc[u] = float(_acc.get(u, float(b.every))) - dt
					if _acc[u] <= 0.0:
						_acc[u] = float(b.every)
						_exec_list(b.get("do", []))
					continue
				_acc[u] = float(_acc.get(u, 0.0)) + dt
				if _acc[u] >= float(b.every):
					_acc[u] -= float(b.every)
					_exec_list(b.get("do", []))
			"st.slow_soft":
				seen[u] = true
				_state[u] = ObCore.slow_soft(self, b, _state.get(u, {}))
			"shape.orbit":
				seen[u] = true
				if not _state.has(u):
					_state[u] = {"ang": 0.0, "hit": {}}
				ObCore.orbit_tick(self, b, _state[u], dt)
			"verb.field":
				if not b.has("tick"):   # 瞬时留场（星熊）不是常驻的，在 _exec_list 里生成
					continue
				seen[u] = true
				if not _state.has(u):
					_state[u] = {}
				SegAngelina.field_tick(self, b, _state[u], dt)
	# 这一帧没生效的累计器 / 状态清零（技能结束、条件不成立时重新计时）
	for u in _acc.keys():
		if not seen.has(u):
			_acc.erase(u)
	for u in _state.keys():
		if not seen.has(u):
			_state.erase(u)
	_ext_sustain(act, dt)
	if not hw.is_empty():
		ObHw.hw_sustain(self, act)   # 精英化第 2 批段：叠层安魂
	ObSummon.sm_sustain(self, act, dt)   # 召唤 / 封印段：aura.heal
	ObSummon.mf_sustain(self, act)       # 召唤物扩展段：verb.summon_mod 的倍率表
	# 四：画面帧条（docs/61 §5.6）：常驻积木上带 every 的 fx 条目定时播；只动 pfx / g.vrng，不影响玩法
	var fseen := {}
	for b in act:
		if b.has("fx"):
			var u: int = int(b.get("_uid", 0))
			fseen[u] = true
			_fxt[u] = ObFx.fx_tick(self, b.fx, zone_c(), zr, _fxt.get(u, []), dt)
			if ObFx.fx_has_body(b.fx):
				if not _fxb.has(u) or float(_fxb[u].fade) >= 0.0:
					_fxb[u] = {"b": b, "el": 0.0, "fade": -1.0, "fl": ObFx.fx_hold_out(b.fx)}
				else:
					_fxb[u].el += dt
	for u in _fxt.keys():
		if not fseen.has(u):
			_fxt.erase(u)
	for u in _fxb.keys():
		if not fseen.has(u):
			var e: Dictionary = _fxb[u]
			e.el += dt
			e.fade = float(e.fl) if float(e.fade) < 0.0 else float(e.fade) - dt
			if e.fade <= 0.0:
				_fxb.erase(u)


## 触发积木进本帧列表：passive → 它的 do（各自再看 cond）；tick → 它本身；裸效果积木（成长节点）→ 它本身
func _collect_trig(t: Dictionary, act: Array) -> void:
	if not ObCore.cond_true(self, t.get("cond", _ED)):
		return
	match str(t.get("_tag", "")):
		"trig.passive":
			for b in t.get("do", _EA):
				if ObCore.cond_true(self, b.get("cond", _ED)):
					act.append(b)
		"trig.tick":
			act.append(t)
		"trig.every_n", "trig.on_kill", "trig.on_mate_attack", "trig.on_mate_hook":
			pass
		_:
			act.append(t)


func _heal(b: Dictionary) -> void:
	if b.has("knight") and g.knight.alive:   # 召唤物扩展段（§15.9）：同时治骑士同伴（按骑士最大生命）
		g.knight.heal(g.knight.maxhp * float(b.knight))
	if b.get("split", false):   # split: true = 这一拍在队长与 Mon3tr 间分配（m3_hp.gd heal_pick；开关关 / 没有 Mon3tr / 队长危险 → 仍给队长）
		var m3 = M3Hp.heal_pick(self)
		if m3 != null:
			var over_m: float = M3Hp.heal_apply(self, m3, b)
			if b.has("sfx"):
				_sfx_op(str(b.sfx))
			if over_m > 0.0 and b.has("on_over"):
				_exec_list(b.on_over)   # 庇护算 Mon3tr 身上的溢出（用户 10-29）
			return
	if g.hp >= g.max_hp and not b.get("full", false):   # full: true = 满血也照常结算（溢出治疗类藏品 / on_over 照常触发，同手写凯尔希 S1）
		return
	var h: float
	if str(b.get("scale", "")) == "op":   # × op_atk × 同伴倍率 × heal_out × 局部 heal 倍率（同手写治疗干员的写法）
		h = g.max_hp * float(b.pct) * (stat(&"op_atk") * g.ally_mult * stat(&"heal_out") * float(loc.heal))
	else:
		h = g.max_hp * float(b.pct) * float(loc.heal)
	if b.get("power", false):
		h *= skill_power()
	var over: float = maxf(0.0, g.hp + h - g.max_hp)
	heal_leader(h, str(b.get("src", display_name())), "技能" if b.get("power", false) else "常驻")   # 子项只进 docs/88 遥测
	if b.has("sfx"):
		_sfx_op(str(b.sfx))
	if over > 0.0 and b.has("on_over"):
		_exec_list(b.on_over)
	if b.has("text"):
		float_text(g.ppos + Vector2(0, -90), "+%d" % int(h), col(), int(b.text))
	if b.has("fx"):
		ObFx.fx_play(self, b.fx, g.ppos, 30.0)


## 瞬时积木列表（技能出手、触发器触发、延迟到点）
## B6 ③（docs/101 §7.3.7）：缺省分支按 tag 单播给一个瞬时执行器（原来依次广播给全部 9 个，各执行器只认自己 match 里的 tag、没命中什么都不做）。
## 下标 = 原广播顺序：0 _ext_exec、1 tx、2 exu、3 sm、4 mf、5 el、6 hw、7 h3（原经 hw_exec 的 _: 转）、8 h4（同上，且 h4_on）。
## 表与各执行器的分支由快检 ob_tag（tools/ob_tag_audit.py）核对：tag 两两不重叠、表不多不少；加 tag 后用 --table 重出。
const EXEC_SEG := {
	"shape.line": 0,   # _ext_exec
	"verb.field": 0,   # _ext_exec
	"verb.negate_next": 0,   # _ext_exec
	"verb.taunt_guard": 0,   # _ext_exec
	"verb.block_mark": 0,   # _ext_exec（docs/202）
	"verb.force_block": 0,   # _ext_exec
	"verb.boil_sand": 0,   # _ext_exec
	"verb.dash_cd_cut": 0,   # _ext_exec
	"verb.break_windup": 0,   # _ext_exec
	"verb.ll_dial_arm": 0,   # _ext_exec → seg_lappland（docs/202 拉普兰德成长节点）
	"verb.ll_dial_swing": 0,   # _ext_exec → seg_lappland
	"verb.ll_riposte": 0,   # _ext_exec → seg_lappland
	"verb.ll_seal_spread": 0,   # _ext_exec → seg_lappland
	"shape.dash_line": 1,   # tx_exec
	"verb.fx_rain": 1,   # tx_exec
	"verb.emit_path": 1,   # tx_exec
	"verb.rift_slash": 1,   # tx_exec
	"verb.fx_scatter": 1,   # tx_exec
	"verb.sp_secs": 1,   # tx_exec
	"verb.trail": 1,   # tx_exec
	"shape.projectile": 2,   # exu_exec
	"verb.attack_lock": 2,   # exu_exec
	"verb.counter": 2,   # exu_exec
	"verb.shield": 3,   # sm_exec
	"verb.summon": 3,   # sm_exec
	"verb.cleanse": 4,   # mf_exec
	"verb.guard": 4,   # mf_exec
	"shape.boomerang": 5,   # el_exec
	"verb.buff_timed": 5,   # el_exec
	"verb.summon_cmd": 5,   # el_exec
	"shape.bolt": 6,   # hw_exec
	"shape.hit": 6,   # hw_exec
	"shape.hookshot": 6,   # hw_exec
	"shape.pool": 6,   # hw_exec
	"shape.shell": 6,   # hw_exec
	"shape.wave": 6,   # hw_exec
	"verb.affect": 6,   # hw_exec
	"verb.arm": 6,   # hw_exec
	"verb.execute": 6,   # hw_exec
	"verb.fan": 6,   # hw_exec
	"verb.link": 6,   # hw_exec
	"verb.lob": 6,   # hw_exec
	"verb.lock": 6,   # hw_exec
	"verb.stack": 6,   # hw_exec
	"verb.tether": 6,   # hw_exec
	"verb.timer": 6,   # hw_exec
	"shape.cleave": 7,   # h3_exec
	"shape.thrust": 7,   # h3_exec
	"verb.barrage": 7,   # h3_exec
	"verb.beam_window": 7,   # h3_exec
	"verb.cast_push": 7,   # h3_exec
	"verb.doll_flash": 7,   # h3_exec
	"verb.saw_echo": 7,   # h3_exec
	"verb.followup": 7,   # h3_exec
	"verb.heal_lamp": 7,   # h3_exec
	"verb.kill_heal": 7,   # h3_exec
	"verb.lift_around": 7,   # h3_exec
	"verb.light_rain": 7,   # h3_exec
	"verb.mend": 7,   # h3_exec
	"verb.purge": 7,   # h3_exec
	"verb.tower": 7,   # h3_exec
	"verb.calc_field": 8,   # h4_exec
	"verb.cannon_exec": 8,   # h4_exec
	"verb.cannon_load": 8,   # h4_exec
	"verb.cmd_wave": 8,   # h4_exec
	"verb.fox_cast": 8,   # h4_exec
	"verb.leap_slam": 8,   # h4_exec
	"verb.saria_heal": 8,   # h4_exec
	"verb.amber_ring": 8,   # h4_exec（响应动作，塞雷娅）
}


func _exec_list(arr: Array, at: Vector2 = Vector2.INF) -> void:
	for b in arr:
		if not ObCore.cond_true(self, b.get("cond", _ED)):
			continue
		match str(b.get("_tag", "")):
			"shape.circle", "shape.cone":
				ObCore.exec_shape(self, b, at)
			"verb.heal":
				if not b.has("every"):
					_heal(b)
			"verb.lamp":
				if b.has("add"):
					g.lamp = clampf(g.lamp + float(b.add), 0.0, g.lamp_cap)
			"verb.sp_team":
				var sp_pct: float = float(b.pct) * (skill_power() if b.get("power", false) else 1.0)   # power：第 4 批（× 技能强度）
				g.squad.gain_sp(sp_pct, self)
				if not b.get("exclude_self", true):
					gain_sp(sp_pct, effect_skill)   # 含自身（推进之王 S1，用户 10-29）：自己刚放的技能不回充，其余技能照加
				if b.has("motes"):
					SegSiege.h4_sp_motes(self, int(b.motes))   # 第 4 批：金色技力粒子飞向每名队友（画面）
			"verb.displace":
				ObCore.displace_at(self, b, at)
			"custom":
				var fn: String = str(b.custom)
				if has_method(fn):
					call(fn, b)
				elif not _warned.has(fn):
					_warned[fn] = true
					push_warning("数据干员 %s：custom 函数「%s」不存在，已忽略" % [id, fn])
			var tg:
				match int(EXEC_SEG.get(tg, -1)):
					0:
						_ext_exec(b, at)       # 星熊段
					1:
						SegTexas.tx_exec(self, b, at)   # 德克萨斯段
					2:
						SegExusiai.exu_exec(self, b, at)  # 能天使段
					3:
						ObSummon.sm_exec(self, b, at)   # 召唤 / 封印段
					4:
						ObSummon.mf_exec(self, b, at)   # 召唤物扩展段
					5:
						ObElite.el_exec(self, b, at)   # 精英化段
					6:
						if not hw.is_empty():
							ObHw.hw_exec(self, b, at)   # 手写迁移段
					7:
						if not hw.is_empty():
							ObHw.h3_exec(self, b, at)   # 手写迁移段第 3 批
					8:
						if not hw.is_empty() and ObHw.h4_on(self):
							ObHw.h4_exec(self, b, at)   # 手写迁移段第 4 批
		if b.has("fx") and not str(b.get("_tag", "")) in ObFx.FX_SELF_PLAY:   # 伤害形状 / 位移 / 区域等的 fx 由执行器按自己的位置播
			ObFx.fx_play(self, b.fx, zone_c(), zr)


# ---------------------------------------------------------------- 出手

var in_release := false                # 正在执行普攻出手（_release 整段，含 replace / far / 连斩排队 / every_n 追加）：手动普攻时剑气 / 钩索按玩家指向（10-23）
var vg := {}                           # 可见成长藏品（docs/163，blocks/vis_growth.gd）：额外弹 / 剑气 / 累加器；空 = 用不到
var pierce_atk := false                # 普攻子弹能穿透（能天使弹道 / 流明光弹 / 带 max_hits 的普攻剑气）：升级卡「贯穿」只在编队有这样的人时进池（10-23）


## 载入后扫一遍积木：普攻形状是弹道 / 光弹，或普攻段 / 特性 / 成长里有写了 max_hits 的剑气
static func _scan_pierce_atk(B: Dictionary) -> bool:
	if str(B.get("attack", {}).get("shape", "")) in ["projectile", "lantern"]:
		return true
	return _has_max_hits(B.get("attack", {})) or _has_max_hits(B.get("trait", [])) or _has_max_hits(B.get("progression", {}))


static func _has_max_hits(n) -> bool:
	if n is Dictionary:
		if str(n.get("shape", "")) == "wave" and n.has("max_hits"):
			return true
		for k in n:
			if _has_max_hits(n[k]):
				return true
	elif n is Array:
		for x in n:
			if _has_max_hits(x):
				return true
	return false


func _release() -> void:
	in_release = true
	_release_body()
	in_release = false


func _release_body() -> void:
	var a: Dictionary = cur_attack()
	if str(a.get("shape", "")) == "support":   # 召唤物扩展段（§15.9）：出手帧执行 do（音效由 do 里的积木自己播）
		_exec_list(a.get("do", []), g.ppos)
		return
	if not hw.is_empty() and SegUlpianus.hw_armed_release(self, a):   # 手写迁移段：蓄势（attack.armed）的这一下整个换掉，不计普攻次数、不走 every_n
		_sfx_op("atk")
		return
	var far_fp: Dictionary = _far_pick(a) if a.get("far", null) != null and atk_far != 0 else {}
	if not far_fp.is_empty() and atk_far == -1 and not _far_wanted(a, far_fp):
		far_fp = {}
	var rp := _replace_trig(atk_n + 1) if far_fp.is_empty() else {}   # 精英化段：trig.every_n replace = 这一次普攻整个换成它的 do
	atk_live = true
	if not el.is_empty() or not rp.is_empty():
		ObElite.el_st(self).fire_t = g.t
	if not rp.is_empty():
		if not phases.is_empty():
			phases.queue = []
		_exec_list(rp.get("do", []))   # last_hit_pos 沿用上一次普攻的（热砂这类 last_hit 区域照常落在那里）
	elif not phases.is_empty() and not phases.round.is_empty():
		AttackPhases.release(self)
	elif str(a.get("shape", "")) == "point_aoe":
		_fire_point_aoe(a)
	elif str(a.get("shape", "")) == "shell":   # 手写迁移段：法术弹
		SegEyjafjalla.hw_shell_fire(self, a, true)
	elif str(a.get("shape", "")) == "bolt":   # 手写迁移段：飘飞咒文弹；没有目标 = 这一下没出手（不算次数、不走 every_n，同手写的 return）
		if not SegLogos.hw_bolt_fire(self, a, true):
			atk_live = false
			return
	elif str(a.get("shape", "")) == "umbrella":
		if not SegMizuki.h3_umbrella_release(self, a):
			atk_live = false
			return
	elif str(a.get("shape", "")) in ObHw.H3_ATTACKS:   # 手写迁移段第 3 批：刺击……
		SegIrene.h3_attack_fire(self, a)
	elif str(a.get("shape", "")) in ObHw.H4_ATTACKS:   # 手写迁移段第 4 批：锤击 / 狐火 / 炮击 / 拳击（音效由形状自己播）
		ObHw.h4_attack_fire(self, a)
	elif not far_fp.is_empty():   # attack.far（docs/61 §21.3，拉普兰德「领主」）：远处这一下改用远程形状
		_exec_list([far_fp])
		last_hit_pos = Vector2.INF
	else:
		var _pt0 := Time.get_ticks_usec() if g.prof_on else 0
		exec_any_shape(a, Vector2.INF, true)
		if g.prof_on:
			g.prof_add("rel_shape_" + str(id), _pt0)
	if far_fp.is_empty():
		VisGrowth.on_release(self)   # 可见成长（docs/163）：散射 / 连发 / 剑气；没有这些藏品时不做事
	var _pt1 := Time.get_ticks_usec() if g.prof_on else 0
	atk_live = false
	atk_far = -1
	if not str(a.get("shape", "")) in ObHw.H4_ATTACKS + ["umbrella", "projectile"]:   # projectile（能天使）：枪声在 _exu_volley 出弹那一帧逐轮播
		_sfx_op("atk")
	if not far_fp.is_empty() and not far_fp.get("count", true):
		far_n += 1
		return   # count: false = 远程这一下不算近战的次数（every_n / 精英化替换 / 连斩都只数近战）
	atk_n += 1
	for t in _trigs():
		if str(t.get("_tag", "")) == "trig.every_n" and not t.get("replace", false) and ObCore.cond_true(self, t.get("cond", _ED)):
			if t.get("skip_replaced", false) and not rp.is_empty():
				continue   # 精英化第 2 批段：这一下被 replace 换掉了（掷锚）——跟着锚击中心走的追加（定点爆破 / 收链……）不走
			var n: int = maxi(1, int(t.n))
			if atk_n % n == 0:
				if t.has("vis_anim"):
					play_vis_anim(str(t.vis_anim))   # 纯画面：追加段的帧条（斯卡蒂反手斩），不占动作窗口、不改出手
				var dl: float = float(t.get("delay", 0.0))
				if dl > 0.0:
					if hw.is_empty():
						pending.append({"t": dl, "do": t.get("do", [])} if not B.get("_e5_among", false) else {"t": dl, "do": t.get("do", []), "ah": e5.get("ah", {})})
					else:   # 手写迁移段：带上 basis 快照；at: attack = 落在这一次普攻的判定中心
						pending.append({"t": dl, "do": t.get("do", []), "bs": ObHw.hw_snap(self), "at": hw.atk_c if str(t.get("at", "")) == "attack" else Vector2.INF})
				else:
					_exec_list(t.get("do", []), hw.atk_c if not hw.is_empty() and str(t.get("at", "")) == "attack" else Vector2.INF)
	if g.prof_on:
		g.prof_add("rel_trigs_" + str(id), _pt1)
	if not hw.is_empty():
		if not rp.is_empty() and rp.get("no_combo", false):
			ObHw.hw_combo_end(self)   # replace 的 every_n 带 no_combo（德克萨斯疾刃三连）：这一次出手自己连斩，不再接 attack.combo 的第二斩
		else:
			ObHw.hw_combo_start(self)   # 手写迁移段：attack.combo 连斩 / trig.on_combo_end


## 精英化段：第 n 次普攻是否被 trig.every_n replace 换掉（第一块成立的；没有 = {}）
func _replace_trig(n: int) -> Dictionary:
	if not B.has("_el_rep"):
		var any := false
		for k in B.get("progression", {}):
			for t in _node_list(B.progression[k]):
				any = any or (str(t.get("_tag", "")) == "trig.every_n" and t.get("replace", false))
		for sec in ["trait", "talent"]:
			for t in B.get(sec, []):
				any = any or (str(t.get("_tag", "")) == "trig.every_n" and t.get("replace", false))
		B["_el_rep"] = any
	if not B._el_rep:
		return {}
	for t in _trigs():
		if str(t.get("_tag", "")) == "trig.every_n" and t.get("replace", false) and n % maxi(1, int(t.n)) == 0 and ObCore.cond_true(self, t.get("cond", _ED)):
			return t
	return {}


## 精英化段：队友 m 普攻出手（character.gd 广播）→ trig.on_mate_attack 的画面
func on_mate_attack(m) -> void:
	if B.get("_el_mate", false):
		ObElite.el_mate_attack(self, m)


## 跑动拖尾（blocks.run_fx {every, fx}，10-22 歌蕾蒂娅水滑行）：动作为 run 时每 every 秒在脚底播一次 fx（朝左时 rot 条目转 180°）；
## 只动 pfx / g.vrng，不碰玩法
var _run_fx_t := 0.0
func _run_fx(dt: float) -> void:
	var rf = B.get("run_fx", null)
	if not (rf is Dictionary) or pos == Vector2.INF:
		return
	if str(anim_state().get("kind", "")) != "run":
		_run_fx_t = float(rf.get("every", 0.15))   # 下次起步立刻播一份
		return
	_run_fx_t += dt
	if _run_fx_t >= float(rf.get("every", 0.15)):
		_run_fx_t = 0.0
		ObFx.fx_play(self, rf.fx, pos, 0.0, [], PI if face < 0.0 else 0.0)


## 联动段（docs/123 §2.7「钩与锚」）：本干员的钩索（shape.hookshot）把敌人拖回到位 → 告诉编队里的其他干员
func notify_mate_hook(at: Vector2, hits: Array) -> void:
	var sq = g.get("squad") if g != null else null
	if sq == null:
		return
	for m in sq.ops:
		if m != self and m.has_method("on_mate_hook"):
			m.on_mate_hook(self, at, hits)


## 队友 m 的钩索把敌人拖回到 at（hits = 被拖回的敌人）：本干员生效中的 trig.on_mate_hook —— op 只认这名队友（缺省任何）、
## knob = balance.json 开关路径（缺省开）、range = 本干员到落点的距离上限（× op_range）、cd = 两次之间至少隔几秒（按触发块计）；
## 命中后以落点为 target 执行 do。确定性：只读队长 / 队友状态与 g.t，不取随机数
func on_mate_hook(m, at: Vector2, hits: Array) -> void:
	if not B.get("_el_mate_hook", false) or pos == Vector2.INF or hits.is_empty() or BranchBal.vi("ult/on", 1) > 0:   # ult/on：钩与锚并进深海猎人组合（docs/198 §10.3）
		return
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_mate_hook" or not ObCore.cond_true(self, t.get("cond", _ED)):
			continue
		if str(t.get("op", "")) != "" and str(t.get("op", "")) != str(m.id):
			continue
		if str(t.get("knob", "")) != "" and BranchBal.vi(str(t.knob), 1) == 0:
			continue
		if t.has("range") and pos.distance_to(at) > float(t.range) * stat(&"op_range"):
			continue
		var key := "mhook:%d" % int(t.get("_uid", 0))
		var cd: float = float(t.get("cd", 0.0))
		if cd > 0.0 and mhook_cd.has(key) and g.t - float(mhook_cd[key]) < cd:
			continue
		mhook_cd[key] = g.t
		_exec_list(t.get("do", []), at)


## 图鉴演示（run/demo.gd 每 3 秒把队长生命压到 70% 时调）：演示里怪不伤人，模拟一次「队长受到攻击」的询问，
## 让 trig.on_hurt / 格挡类效果（凯尔希回防、星熊反击架势）也能演出来；只在 g.demo_op 时有效
func demo_hurt() -> void:
	if g.demo_op == "" or g.combat == null:
		return
	dmg_taken_mult({}, 0.0)


func _release_skill() -> void:
	if not hw.is_empty() and SegIrene.h3_release_skill(self):   # 手写迁移段第 3 批：verb.followup 起的那一下（不走技能本体）
		return
	if not hw.is_empty() and ObHw.h4_release_skill(self):   # 手写迁移段第 4 批：碎颅期间用技能动作起手的那一锤
		return
	var i := cur_skill
	var sk: Array = B.get("skills", [])
	if i < 0 or i >= sk.size():
		return
	if is_leader:   # 响应动作：队长开技能（trig.on_leader_skill，docs/118）
		g.leader_skill_n += 1
		g.leader_skill_i = i
	var sb: Dictionary = sk[i]
	var dv = sb.get("dur", 0.0)
	if dv is String and dv == "permanent":
		perm_on[i] = true
	elif dv is Dictionary and dv.has("ammo"):   # 能天使段：dur.ammo（N 发子弹）
		SegExusiai.exu_skill_shell(self, i, dv)
	elif dv is Dictionary and dv.has("pulses"):   # 手写迁移段：连续喷发（dur.pulses）
		SegEyjafjalla.hw_pulse_start(self, i, sb)
	elif dv is Dictionary:
		load_skill_attacks(i, int(dv.get("next_attacks", 0)))   # 安洁莉娜段：dur.next_n，接下来 N 次普攻带 attack_patch
	elif float(dv) > 0.0:
		s_t[i] = float(dv)
		s_dur[i] = float(dv)
	if sb.has("attack_phases"):
		AttackPhases.start(self, i)
	effect_skill = i
	_exec_list(sb.get("do", []))
	effect_skill = -1
	bind_skill_duration(i)
	SegTexas.tx_skill_start(self, i)   # 德克萨斯段：trig.on_skill_start
	if not hw.is_empty() and perm_on[i]:
		_restat()   # 手写迁移段：永久技能出手当下就改属性（同手写，不等下一帧）
	fx({"kind": "ring", "pos": pos, "r": 70.0, "r0": 10.0, "life": 0.5, "col": col(), "floor": true})
	if sb.has("fx"):
		ObFx.fx_play(self, sb.fx, zone_c(), _zone_r_now())


func load_skill_attacks(i: int, amount: int) -> void:
	var sb: Dictionary = B.skills[i]
	ammo[i] = mini(int(sb.stack_max), ammo[i] + amount) if sb.has("stack_max") else amount


func bind_skill_duration(i: int) -> void:
	var sb: Dictionary = B.skills[i]
	if hw.has("mz") and s_t[i] > 0.0:
		SkillLifecycle.bind(self, "skill:%d" % i, i, s_t, i, true, false)
	if not SkillLifecycle.owns(self, i, "skill:%d" % i) and not sb.has("attack_phases"):
		if perm_on[i]:
			SkillLifecycle.bind(self, "skill:%d" % i, i, perm_on, i, false, false, Callable(), "permanent")
		elif ammo[i] > 0:
			SkillLifecycle.bind(self, "skill:%d" % i, i, ammo, i, false, false, Callable(), "attacks")


func on_kill(e: Dictionary) -> void:
	if not hw.is_empty():
		hw["kill_e"] = e   # 手写迁移段：verb.stack 看是不是 Boss
		ObHw.h4_on_kill(self, e)   # 手写迁移段第 4 批：残影标记殉爆
	kill_w = SegExusiai.kill_weight(g, e)
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_kill" or not ObCore.cond_true(self, t.get("cond", _ED)):
			continue
		var f: String = str(t.get("filter", "any"))
		if f == "any" or (f == "elite" and (e.elite or e.boss)) or (f == "boss" and e.boss) or (f == "zone_ally" and SegSkalter.gn_zone_ally_kill(self, e)) or (f == "marked" and float(e.get("tr_t", 0.0)) > g.t and str(e.get("tr_op", "")) == id):   # marked：被本干员曳光弹标记的敌人（docs/202 能天使）
			_exec_list(t.get("do", []), e.pos)
	kill_w = 1.0


func _sfx_op(kind: String, db := 0.0, pitch := 1.0) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(id, kind, db, pitch)


# ---------------------------------------------------------------- 绘制

## 手写迁移段：近战前压（blocks.follow {leash, gap}）；没写 = 编队位
func follow_target(slot_pos: Vector2) -> Vector2:
	var ta := taunt_anchor()
	if ta != Vector2.INF:
		return ta
	var fw: Dictionary = B.get("follow", {})
	if fw.is_empty() or (not hw.is_empty() and SegSpecter.h3_away(self)):   # 手写迁移段第 3 批：本体离场（替身在场）时回编队位
		return slot_pos
	if fw.has("side"):   # 手写迁移段第 4 批：护卫站位（队长朝向一侧的固定偏移，不前压）
		return g.ppos + Vector2(float(fw.side[0]) * g.facing, float(fw.side[1]))
	var p := melee_spot(float(fw.get("leash", 200.0)), float(fw.get("gap", 30.0)))
	return p if p != Vector2.INF else slot_pos


## 指挥走位按攻击方式分近远程；医疗 / 辅助的 command.roam:false 仍保持随行。
func cmd_role() -> String:
	return "ranged" if str(cur_attack().get("shape", "")) in ["projectile", "shell", "bolt", "cannon", "point_aoe", "foxfire", "lantern"] else "melee"


func cmd_attack_range() -> float:
	var a: Dictionary = cur_attack()
	if str(a.get("shape", "")) == "circle" and str(a.get("center", "")) == "front":
		return ObCore.shape_radius(self, a)
	if a.has("range"):
		return float(a.range) * stat(&"op_range")
	if a.has("len"):
		return float(a.len) * stat(&"op_range")
	if a.has("r"):
		return ObCore.shape_radius(self, a)
	return super()


func cmd_reach() -> float:
	var fw: Dictionary = B.get("follow", {})
	if fw.has("gap"):
		return float(fw.gap)
	var a: Dictionary = cur_attack()
	if a.has("range"):
		return float(a.range) * stat(&"op_range") * CmdBal.v("command/range_k", 0.6)
	return 30.0


## 手写迁移段：每打中一名敌人的画面（blocks.hit_fx）
func _hit_fx(e: Dictionary, origin: Vector2) -> void:
	if B.has("hit_fx"):
		ObFx.fx_play(self, B.hit_fx, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.r), [e], (e.pos - origin).angle())


## 区域：地面椭圆，灯火充盈 / 昏暗 / 其他三种色；shape.orbit 的判定点画成小菱形
func draw_auras() -> void:
	_draw_fields()
	if not hw.is_empty():
		SegSkadi.hw_draw_rings(self)   # 手写迁移段：常驻程序圈（aura_ring）、喷发热浪环……
		ObHw.hw_draw_auras(self)
	if pos == Vector2.INF or not B.has("zone"):
		return
	var c := zone_c()
	var cc: Color = col()
	if g.lamp >= 70.0:
		cc = cc.lerp(Color(1.0, 0.92, 0.8), 0.12)   # 灯火充盈只微微偏暖，不把设定色冲成灰白（10-29）
	elif g.lamp < 30.0:
		cc = cc.lerp(Color(0.45, 0.2, 0.75), 0.6)
	var on := skill_active()
	var rm := 1.0   # 程序漩涡（§5.6 vortex.ring）可把区域硬边压淡
	for u in _fxb:
		rm = minf(rm, ObVortex.vortex_ring_mul(self, _fxb[u]))
	if str(B.zone.get("look", "")) == "particles":   # 10-29 浊心斯卡蒂：领域改粒子勾边、内部稀疏，不画实心圆；画面半径缓动 + 波纹（seg_skalter）
		SegSkalter.sk_draw_domain(self, c, SegSkalter.sk_vis_r(self, "self", c, zr, SegSkalter.SK_DOM), SegSkalter.SK_DOM, on, 0.0)
		SegSkalter.sk_gn_draw(self)   # 成长节点（docs/202）：潮声音符 / 共振层
		if not sm.is_empty():
			SegSkalter.e5_draw_zones(self, cc, on)
		_draw_hold_strips(cv, "floor")
		_draw_vortex(cv, "floor")
		return
	cv.draw_set_transform(c + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
	# 10-29 特效审查：去掉整片半透明填充圆盘（会把战场糊成灰白、遮敌人和弹幕），只留边线
	var zring: float = float(B.zone.get("ring", 1.0))   # blocks.zone.ring：区域边线透明度倍率（0 = 不画边线；10-14 浊心斯卡蒂去掉歌域外圈红线，纯画面）
	var zf: float = ring_flash("zone") if on else 0.0   # 10-31 TA H1：边线只在技能开启那一瞬出现，不常驻
	if zring > 0.0 and zf > 0.0:
		cv.draw_arc(Vector2.ZERO, zr, 0.0, TAU, 48, Color(cc.r, cc.g, cc.b, 0.5 * zf * rm * zring), 2.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not sm.is_empty():
		SegSkalter.e5_draw_zones(self, cc, on)   # 精英化第 5 批段：召唤物自带的区域椭圆
	_draw_hold_strips(cv, "floor")
	_draw_vortex(cv, "floor")
	for u in _state:
		var st = _state[u]
		if st is Dictionary and st.has("ang"):
			var b := _find_uid(u)
			var pts: Array = ObCore.orbit_points(self, b, st.ang)
			if b.has("fx") and ObVortex.fx_orbit(cv, self, b, pts, g.world.fx_dim):   # 帧条代替菱形（docs/61 §5.6 at = orbit）
				continue
			for p in pts:
				draw_diamond(p + Vector2(0, -6), 5.0, Color(cc.r * 1.4, cc.g * 1.4, cc.b * 1.4, 0.85), Color(0.05, 0.05, 0.1, 0.7))


## 贴身层（docs/61 §5.6 layer = behind / front）：本体前后各画一遍
func draw_body() -> void:
	if SegTexas.tx_rift_draw_body(self):   # 德克萨斯次元斩：闪现序列里本体隐去
		return
	if not hw.is_empty() and SegSpecter.h3_away(self):   # 手写迁移段第 3 批：本体离场（替身在场）不画
		return
	if not hw.is_empty() and SegSiege.h4_draw_body(self):   # 手写迁移段第 4 批：跃空锤在空中（翻转的本体 + 扫光）
		return
	_draw_body_fx(false)
	if not hw.is_empty():
		ObHw.hw_draw_body(self, false)   # 手写迁移段：咒域绕身符咒（后层）、血脉轮廓光……
	super()
	if not hw.is_empty():
		ObHw.hw_draw_body(self, true)
	_draw_body_fx(true)


func _draw_body_fx(front: bool) -> void:
	for u in _fxb:
		ObVortex.fx_body(cv, self, _fxb[u], front)


## 程序漩涡（docs/61 §5.6 vortex）：floor 层在 draw_auras（人物下面）、add 层在 draw_fx_add；进出淡入淡出按条目 fade（缺省 0.5 秒淡入、FX_VORTEX_FADE 秒淡出）
func _draw_vortex(sink, layer: String) -> void:
	if pos == Vector2.INF or g.perf_alt:   # g.perf_alt：--perfab 同局轮换量漩涡开 / 关的净成本（/b 桶不画；正常游戏恒为 false）
		return
	var rz: float = _zone_vis_r()
	for u in _fxb:
		var e: Dictionary = _fxb[u]
		if not ObFx.fx_has_vortex(e.b.fx):
			continue
		ObVortex.fx_vortex(sink, self, e, layer, 1.0, zone_c(), rz)


## 常驻跟随帧条（docs/61 §5.6 hold: true，10-12 加）：ground 层在 draw_ground_fx（地砖之上、溟痕 / 地面预警之下）、floor 层在 draw_auras、add 层在 draw_fx_add
func _draw_hold_strips(ci, layer: String) -> void:
	if pos == Vector2.INF:
		return
	var rz: float = _zone_vis_r()
	for u in _fxb:
		ObFx.fx_hold_strips(ci, self, _fxb[u], layer, zone_c(), rz)


## 区域的画面半径：浊心粒子领域（blocks.zone.look = particles）用 sk_vis_r 缓动后的值，漩涡贴图 / 程序漩涡与粒子边界同步扩缩（10-29 用户
## 「漩涡的纹理没有和圆圈大小对上」）；其余干员就是判定半径 zr
func _zone_vis_r() -> float:
	if B.has("zone") and str(B.zone.get("look", "")) == "particles" and has_meta("sk_dom"):
		return float(get_meta("sk_dom").get("self", [zr])[0])
	return zr


## squad.draw_ground_fx → 这里（world.draw_world 画完地砖紧接着调；没有 ground 层条目时什么都不画）
func draw_ground_fx() -> void:
	_draw_hold_strips(cv, "ground")
	if not sm.is_empty():
		SegSkalter.e5_draw_zone_ground(self)   # 精英化第 5 批段：召唤物区域的地面帧条


## 画面帧条粒子（docs/61 §5.6）：地面 / 上层在这里画，加色层（add）留给 draw_fx_add
## 德克萨斯段的冲刺剑光 / 旧剑雨（kind = tx_strip：横向拉伸、延迟起播）交给 SegTexas.tx_draw_pfx；剑雨编排（kind = tx_rain，verb.fx_rain）交给 SegTexas.tx_rain_draw
func _draw_pfx(f: Dictionary, a: float) -> bool:
	if str(f.kind) == "tx_strip":
		return SegTexas.tx_draw_pfx(self, f, a)
	if str(f.kind) == "tx_scar":
		return SegTexas.tx_scar_draw(self, f, a)
	if str(f.kind) == "tx_rain":   # verb.fx_rain（docs/61 §13.5）：加色层的在 draw_fx_add 画
		if not f.get("add", false):
			SegTexas.tx_rain_draw(cv, self, f)
		return true
	if str(f.kind) != "strip":
		return ObSummon.mf_draw_pfx(self, f, a) or SegEyjafjalla.hw_draw_pfx(self, f, a)   # 召唤物扩展段的程序粒子（crescent / impact / core / qshard / beamray）；手写迁移段（熔岩柱……）
	if not f.get("add", false):
		ObFx.fx_draw(cv, g, f, g.world.fx_dim)
	return true


func draw_fx_add(ci: CanvasItem, loop: int) -> void:
	super(ci, loop)
	if not hw.is_empty():
		ObHw.h3_draw_add_all(self, ci, loop)   # 手写迁移段第 3 批：提灯光 / 灯塔光 / 光束、技能光环帧条
	_draw_hold_strips(ci, "add")
	_draw_vortex(ci, "add")
	for f in pfx:
		if str(f.kind) == "strip" and f.get("add", false):
			ObFx.fx_draw(ci, g, f, g.world.fx_dim)
		elif str(f.kind) == "tx_rain" and f.get("add", false):
			SegTexas.tx_rain_draw(ci, self, f)


func _find_uid(u: int) -> Dictionary:
	for t in _trigs():
		if int(t.get("_uid", -1)) == u:
			return t
		for b in t.get("do", _EA):
			if int(b.get("_uid", -1)) == u:
				return b
	return {}


func stats_rows() -> Array:
	if not hw.is_empty():
		return SegUlpianus.hw_stats_rows(self)   # 手写迁移段：没有区域的干员不显示区域半径
	var rows: Array = [["区域半径", "%d" % int(zr)]] if zr > 0.0 else []   # 没有区域的干员（凯尔希、能天使等）不显示「区域半径 0」
	rows.append(["伤害倍率", "×%.2f" % float(loc.dmg)])
	return rows


# ---------------------------------------------------------------- 手写迁移段：手动技能（掷锚落点）、动作停帧

func manual_ready(i: int, dir: Vector2 = Vector2.ZERO) -> bool:
	return not skills_occupied() and super(i, dir) and (hw.is_empty() or SegUlpianus.hw_manual_ready(self, i, dir))


func manual_block_reason(i: int, dir: Vector2 = Vector2.ZERO) -> String:
	return SegUlpianus.hw_manual_block_reason(self, i, dir) if not hw.is_empty() else ""


func manual_aim_point(i: int, dir: Vector2 = Vector2.ZERO) -> Vector2:
	return SegUlpianus.hw_manual_aim_point(self, i, dir) if not hw.is_empty() else Vector2.INF


func bot_wants_manual(i: int) -> bool:
	if not hw.is_empty() and not SegUlpianus.hw_tether_of(self, i).is_empty():
		return true   # 进攻型手动技能：就绪即放（同手写乌尔比安）
	return super(i)


## 手写段给原生动作覆盖层的信号（native_motion.gd；名 → 进度 0–1，按优先级先后写入）
func native_signals() -> Dictionary:
	var out := {}
	if prop_out():
		out["prop"] = 1.0   # 往返弹体（星熊盾）在外面；结束 = 盾回手（json native_motion.exits 播接盾）
	if not tx.is_empty():
		SegTexas.tx_native_signals(self, out)   # 德克萨斯段：冲刺 / 回马剑等待
	if not hw.is_empty():
		SegSiege.h4_native_signals(self, out)
		SegUlpianus.hw_native_signals(self, out)
	return out


func anim_state() -> Dictionary:
	var st := super()
	if hw.has("bolts"):
		st = SegLogos.hw_native_body_state(self, st)
	if not hw.is_empty() and hw.has("ir") and not seq_locked():
		st = SegIrene.e3_ir_anim(self, st)   # 精英化第 3 批：收尾斩的帧条
	st = SegUlpianus.hw_anim_state(self, st) if not hw.is_empty() else st
	st = NativeMotion.state(self, st)
	if not hw.is_empty() and hw.has("sp"):
		st = SegSpecter.h3_anim_state(self, st)   # 手写迁移段第 3 批：倒下帧条；S3 重锯 / 反向第二圈换条（在原生动作覆盖之后，10-20）
	return _noshield(st)   # 原生覆盖层换了槽，盾在外面时照样换无盾画面


# ---------------------------------------------------------------- 手写迁移段第 3 批：干员侧询问（squad / game 按 has_method 询问；没用到的数据干员返回中性值）

## 本体离场（替身在场）：不出手、不放技能、不画本体
func away() -> bool:
	return not hw.is_empty() and SegSpecter.h3_away(self)


## 主控本该倒下时阻止（verb.undying 所在技能生效中）
func prevent_death() -> bool:
	return not hw.is_empty() and SegSpecter.h3_prevent_death(self)


## 圣域 {pos, r}（verb.tower 灯塔在场）
func sanctuary() -> Dictionary:
	return SegLumen.h3_sanctuary(self) if not hw.is_empty() else {}


## 主控照亮半径倍率（verb.lamp radius_mult）
func light_radius_mult() -> float:
	return SegLumen.h3_light_mult(self) if not hw.is_empty() else 1.0


## 触手颜色（world.gd 巨型触手破土）
func tentacle_col(bright := 1.0) -> Color:
	return SegMizuki.h3_tentacle_col(self, bright) if not hw.is_empty() else Color(1.3, 1.1, 1.6)


## 专属属性定义（JSON stat_defs：{属性名: {base, min, max, name}}）
func stat_defs() -> Dictionary:
	var out := {}
	var sd = def.get("stat_defs", {})
	if sd is Dictionary:
		for k in sd:
			if str(k) != "_doc":
				out[StringName(str(k))] = sd[k]
	return out


func sync_stats(st) -> void:
	if not hw.is_empty():
		SegMizuki.h3_sync_stats(self, st)


## 伤害加成：写了 blocks.dmg_bonus 时按它算（水月：不吃同伴倍率、附近有半血敌人时 ×1.22），否则同 character.gd
func _dmg_bonus() -> float:
	if B.has("dmg_bonus"):
		return SegMizuki.h3_dmg_bonus(self)
	return super()


# ================================================================ 星熊 hoshiguma（docs/59 §3，docs/61「星熊」节）：新积木的执行（op_blocks.gd 末尾同名段落）
## shape.line / verb.field（瞬时留场；verb.displace 与常驻力场在共用段 / 安洁莉娜段）/ verb.negate_next / verb.dr / verb.negate_chance / verb.swap_attack / trig.on_hurt / trig.on_negate。
## 受击询问走 character 的 dmg_taken_mult 挂点（combat.gd enemy_hit 在闪避 / 护盾之后、扣血之前逐个干员询问）：返回 0 = 这一下被格挡，
## combat.gd 整下作废（不扣血、不掉灯火、不吃控制 / 侵蚀，同闪避给 0.3 秒无敌）。

const FIELD_CAP := 16                   # 每名干员同时存在的地面区域上限（超出时最早的先消失）

var last_hit_pos := Vector2.INF        # 上一次普攻命中的第一个敌人（verb.field center: last_hit）
var gm: Dictionary = {}                # docs/202 成长节点的运行时状态（星熊阻挡 / 般若之重；seg_hoshiguma 末尾）；空 = 用不到
var gm_hits: Array = []                # docs/202：上一次普攻的命中列表（trig.on_hit_n 的 do 读它）
var neg_armed: Dictionary = {}         # 待命的 verb.negate_next：技能序号 → 积木
var taunt: Dictionary = {}             # 进行中的 verb.taunt_guard：{i 技能序号, b 积木, anchor 站定点（队长时 INF）, ids 拉到过的敌人}
var fields: Array = []                 # 地面区域：{pos, r, t, dur, every, n, done, do, fx}
var ext_dr := 1.0                      # 本帧 verb.dr 的乘积
var neg_add := 0.0                     # 本帧 verb.negate_chance 的 Σadd
var neg_mul := 1.0                     # 本帧 verb.negate_chance 的 Πmult
var swap_atk: Dictionary = {}          # 本帧生效的 verb.swap_attack（空 = 用 blocks.attack）
var negate_n := 0                      # 本局格挡次数（图鉴 / 测试看）
var _hurt_cd: Dictionary = {}          # trig.on_hurt 的冷却（_uid → 下次可触发的 g.t）


## attack.far（通用积木）：这一下普攻的触及范围（形状半径 × op_range）内没有敌人、而远程形状的瞄准范围（aim_r，缺省 dist）内有 → 改掷远程形状
## 当前生效的 far 形态：attack.far 是一个形状对象，或一组带 cond 的形状对象（第一块 cond 成立的；缺省恒成立）；没有 = {}
func _far_pick(a: Dictionary) -> Dictionary:
	var f = a.get("far", null)
	if f is Dictionary:
		return f if ObCore.cond_true(self, f.get("cond", _ED)) else {}
	if f is Array:
		for x in f:
			if ObCore.cond_true(self, x.get("cond", _ED)):
				return x
	return {}


## 这一下普攻的形态（0 近战 / 1 远程 / -1 未判），起手时按目标距离定、出手帧沿用
var atk_far := -1


## 带 attack.far 的近战锥普攻起手：近战触及（半径 + 30）内有敌人 → 近战；否则远程瞄准范围内有 → 远程。
## 手动普攻：看玩家指向的锥（半角 half）里近战触及内有没有敌人，有 = 近战，没有 = 朝指向掷远程（周围没敌人也照出手）
func _far_aim(a: Dictionary, fp: Dictionary, r2: float) -> Vector2:
	var fr: float = float(fp.get("aim_r", fp.get("dist", 0.0))) * stat(&"op_range")
	atk_far = -1
	if manual_attack():
		if not g.doctor.attack_want():
			return atk_point([], r2)
		var d: Vector2 = g.doctor.attack_dir()
		var c: float = cos(float(a.get("half", 1.3))) - 0.0001
		var near := false
		for e in nearest_raw(48, r2 + 30.0, pos):
			var off: Vector2 = e.pos - pos
			if off.length() < 1.0 or off.normalized().dot(d) >= c:
				near = true
				break
		atk_far = 0 if near else 1
		return atk_point([], r2 if near else fr)
	var nt: Array = nearest_enemies(1, r2 + 30.0, pos)
	if not nt.is_empty():
		atk_far = 0
		return atk_point(nt, r2)
	var ft: Array = nearest_enemies(1, fr, pos) if fr > 0.0 else []
	if ft.is_empty():
		return Vector2.INF
	atk_far = 1
	return atk_point(ft, fr)


func _far_wanted(a: Dictionary, far: Dictionary) -> bool:
	if not nearest_enemies(1, ObCore.shape_radius(self, a), pos).is_empty():
		return false
	var fr: float = float(far.get("aim_r", far.get("dist", 0.0))) * stat(&"op_range")
	return fr > 0.0 and not nearest_enemies(1, fr, pos).is_empty()


## 自动技能放出门槛（10-25 用户「范围内没有敌人就不开技能」）：pos 周围 ObCore.skill_gate_base（技能 need_enemy → 伤害积木作用半径 → 普攻射程）× op_range 内要有敌人，
## 没有就先不放（技力保留满格，有敌人那一帧再放）。手动技能不走这里（charge_skills 先判 is_manual）。
## 无敌暂缓（10-28 用户：「面对无敌的敌人可以继续普通攻击，但是可以不放技能，等不无敌了再放」）：combat/hold_skill_on_invuln（缺省 1）开时，
## 范围里得有打得动的（op_api.hittable）——只剩无敌 Boss / 阶段护盾 / 无敌部件时技力保持满格，解除无敌或有能打的小怪进来那一帧就放
func skill_gate_ok(i: int) -> bool:
	var d: float = _gate_dist(i)
	if d <= 0.0:
		return true
	if CmdBal.v("combat/hold_skill_on_invuln", 1.0) > 0.0:
		return has_hittable(d, pos)
	return not nearest_enemies(1, d, pos).is_empty()


## 技能 i 的范围里有敌人、但全是打不动的（hud_squad / touch 的手动技能锁标；只提示，不拦玩家强制放）
func invuln_only(i: int) -> bool:
	if pos == Vector2.INF or CmdBal.v("combat/hold_skill_on_invuln", 1.0) <= 0.0:
		return false
	var d: float = _gate_dist(i)
	return d > 0.0 and not nearest_enemies(1, d, pos).is_empty() and not has_hittable(d, pos)


## 自动技能门槛半径（已乘 op_range；≤ 0 = 不设门槛）
func _gate_dist(i: int) -> float:
	var sk: Array = B.get("skills", _EA)
	if i >= sk.size():
		return 0.0
	var atk: Dictionary = B.get("attack", _ED)
	var fb: float = ObCore.GATE_DEFAULT
	if str(atk.get("r", "")) == "zone":   # 普攻是区域圈（斯卡蒂等）：推不出别的时用区域半径
		fb = zone_r() / maxf(0.01, stat(&"op_range"))
	return ObCore.skill_gate_base(sk[i], atk, {}, fb) * stat(&"op_range")


## 当前普攻形状：verb.swap_attack 生效时用它，否则 blocks.attack
func cur_attack() -> Dictionary:
	return swap_atk if not swap_atk.is_empty() else B.get("attack", {})


## 执行一个伤害形状（circle / cone 走 op_blocks.exec_shape，line 走 exec_line）；is_attack = 普攻出手，记下第一个命中点
func exec_any_shape(b: Dictionary, at: Vector2 = Vector2.INF, is_attack := false) -> Array:
	var hits: Array = SegHoshiguma.exec_line(self, b) if str(b.get("shape", "")) == "line" else ObCore.exec_shape(self, b, at)
	if is_attack:
		last_hit_pos = hits[0].pos if not hits.is_empty() else Vector2.INF
		if not hits.is_empty() and tags_all.has("trig.on_hit_n"):   # docs/202：命中 ≥ n 触发（星熊 / 德克萨斯成长节点）
			SegHoshiguma.gm_hit_n(self, hits)
		if B.get("_e5_among", false):   # 精英化第 5 批段：记下这一次普攻命中的敌人（shape.circle among: attack）
			e5["ah"] = SegSkalter.e5_ids(hits)
		if b.get("slash", false) and not hits.is_empty() and str(b.get("shape", "")) == "cone":
			slash_fx(pos, (hits[0].pos - pos).angle(), deg_to_rad(float(b.get("half_deg", 45.0))), ObCore.shape_radius(self, b), col())
	return hits


## 常驻部分（_sustain 末尾调用；act 是本帧生效的常驻积木，条件已求值）
func _ext_sustain(act: Array, dt: float) -> void:
	var dr := 1.0
	var add := 0.0
	var mul := 1.0
	var sw: Dictionary = {}
	for b in (act if tags_all.has("verb.dr") or tags_all.has("verb.negate_chance") or tags_all.has("verb.swap_attack") else _EA):   # B6 ④
		match str(b.get("_tag", "")):
			"verb.dr":
				dr *= 1.0 - float(b.value)
			"verb.negate_chance":
				add += float(b.get("add", 0.0))
				mul *= float(b.get("mult", 1.0))
			"verb.swap_attack":
				if sw.is_empty():
					sw = b.attack
	ext_dr = dr
	neg_add = add
	neg_mul = mul
	swap_atk = sw
	if not taunt.is_empty():
		_taunt_tick()
	if not gm.is_empty():
		SegHoshiguma.gm_tick(self)   # docs/202：阻挡标记到期 / 近战杂兵改追她
	# 技能结束仍没挨打：negate_next 执行 on_miss（不白放）
	if not neg_armed.is_empty():
		var ks: Array = neg_armed.keys()
		ks.sort()
		for i in ks:
			if not skill_on(int(i)):
				var nb: Dictionary = neg_armed[i]
				neg_armed.erase(i)
				_exec_list(nb.get("on_miss", []))
	# 地面区域：按 tick 计数（第 k 次在 k × every 秒），不靠浮点累加，次数 = round(dur / every)
	if not fields.is_empty():
		for f in fields:
			if f.has("visual_end") and skill_active_left(int(f.visual_end.skill)) <= 0.0:
				_end_field_visual(f)
			f.t += dt
			while f.done < f.n and f.t >= (f.done + 1) * f.every - 0.0001:
				f.done += 1
				_exec_list(f.do, f.pos)
			if f.done >= f.n:
				_end_field_visual(f)
		fields = fields.filter(func(f): return f.done < f.n)


## 区域画面的收尾只读原场快照，不修改区域伤害、tick 数或最后命中点。
func _end_field_visual(f: Dictionary) -> void:
	if not f.has("visual_end") or f.get("visual_done", false): return
	f["visual_done"] = true
	for px in f.get("visual_particles", []):
		px.life = 0.0
		pfx.erase(px)
	ObFx.fx_play(self, f.visual_end.fx, f.pos, float(f.r))


## 瞬时部分（_exec_list 认不出的族.名转到这里）
func _ext_exec(b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"shape.line":
			SegHoshiguma.exec_line(self, b)
		"verb.ll_dial_arm", "verb.ll_dial_swing", "verb.ll_riposte", "verb.ll_seal_spread":   # docs/202 拉普兰德成长节点（blocks/seg_lappland.gd）
			ObCore._F().ll_exec(self, b)
		"verb.field":
			if b.has("tick"):   # 常驻力场（安洁莉娜）在 _sustain 里，这里只管瞬时留场
				return
			var c: Vector2 = SegHoshiguma.field_center(self, b, at)
			if c == Vector2.INF:
				return
			var ev: float = float(b.every)
			var fr: float = float(b.r) * stat(&"op_range") * float(loc.area)
			var u: int = int(b.get("_uid", 0))
			fields.append({"pos": c, "r": fr, "t": 0.0, "dur": float(b.dur), "every": ev,
				"n": maxi(1, roundi(float(b.dur) / ev)), "done": 0, "do": b.get("do", []), "fx": b.get("fx", []), "u": u})
			var field: Dictionary = fields.back()
			if b.get("sand", false):
				field["sand"] = true   # docs/202：热砂（verb.boil_sand 能引爆）
				gm["on"] = true
			if b.has("visual_end"):
				field["visual_end"] = b.visual_end
			if b.has("cap"):   # 精英化段：这块积木同时最多 cap 处，最早的先消失
				var same: Array = fields.filter(func(q): return int(q.get("u", -1)) == u)
				if same.size() > int(b.cap):
					_end_field_visual(same[0])
					fields.erase(same[0])
			if fields.size() > FIELD_CAP:
				_end_field_visual(fields[0])
				fields.pop_front()
			if b.has("fx"):   # 通用 fx（§5.6）：中心 = 区域中心、半径 = 区域半径；没写 life 的条目循环到区域结束（once：只播一遍，精英化段）
				var fl: Array = []
				for f in b.fx:
					fl.append(f if not (f is Dictionary) or f.has("life") or f.get("once", false) else f.merged({"life": float(b.dur)}))
				var fx_start: int = pfx.size()
				ObFx.fx_play(self, fl, c, fr)
				if b.has("visual_end"):
					field["visual_particles"] = pfx.slice(fx_start)
		"verb.block_mark":   # docs/202 成长节点（执行在各干员段：seg_hoshiguma / seg_texas）
			SegHoshiguma.gm_block_mark(self, b)
		"verb.force_block":
			SegHoshiguma.gm_force_block(self, b)
		"verb.boil_sand":
			SegHoshiguma.gm_boil_sand(self, b)
		"verb.dash_cd_cut", "verb.break_windup":
			SegTexas.gm_exec(self, b)
		"verb.negate_next":
			if cur_skill >= 0:
				neg_armed[cur_skill] = b
		"verb.taunt_guard":
			if cur_skill >= 0 and float(base("s1_pull", 1.0)) > 0.0:   # base.s1_pull = 0：关闭拉怪（10-30 改版开关）
				taunt = {"i": cur_skill, "b": b, "anchor": Vector2.INF if is_leader or not bool(b.get("stand", true)) else pos, "ids": {}, "t0": g.t}
				var stop: float = float(b.get("stop", 0.0))
				if stop > 0.0 and not query_ids(pos, float(b.r) * stat(&"op_range")).is_empty():
					g.hitstop = maxf(g.hitstop, stop)   # 命中顿帧
				if b.has("fx"):
					ObFx.fx_play(self, b.fx, pos, 30.0)
				float_text(pos + Vector2(0, -88), str(b.get("text", "嘲讽")), Color(1.0, 0.85, 0.4), 16)
				_sfx_op("big")


## verb.taunt_guard 每帧：技能还在 → 半径内近战杂兵（非 Boss / 宝箱）本帧改追本干员（同召唤物诱饵的 e.aggro，每帧重标），记下拉到过的敌人；
## 技能结束 → on_end，伤害形状倍率 + per × min(拉到的敌人数, cap)（cap 缺省不限；10-24 协调人定星熊设上限）
func _taunt_tick() -> void:
	var b: Dictionary = taunt.b
	if skill_on(int(taunt.i)):
		var r: float = float(b.r) * stat(&"op_range")
		for j in query_ids(pos, r):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.chest or e.boss or e.ai != "melee" or e.pos.distance_to(pos) > r:
				continue
			if e.elite and b.has("dur") and g.t - float(taunt.get("t0", g.t)) > float(b.dur) * float(b.get("elite_x", 1.0)):
				continue   # 精英只被拉 dur × elite_x 秒
			set_aggro(e, pos)
			taunt.ids[e.id] = true
		return
	var n: int = taunt.ids.size()
	taunt = {}
	var per: float = float(b.get("per", 0.0))
	var nk: int = mini(n, int(b.cap)) if b.has("cap") else n
	var lst: Array = []
	for x in b.get("on_end", []):
		var y: Dictionary = x
		if per > 0.0 and y.has("mult") and str(y.get("_tag", "")).begins_with("shape."):
			y = y.duplicate()
			y.mult = float(y.mult) + per * nk
		lst.append(y)
	if n > 0 and not lst.is_empty():
		float_text(pos + Vector2(0, -96), "反击 ×%d" % n, Color(1.0, 0.85, 0.4), 14)
	_exec_list(lst)


## 站定（verb.taunt_guard，队员时）：技能期间跟随目标钉在起手处
func taunt_anchor() -> Vector2:
	if taunt.is_empty() or is_leader or taunt.anchor == Vector2.INF or not skill_on(int(taunt.i)):
		return Vector2.INF
	return taunt.anchor


## 主控受击询问（combat.gd enemy_hit）：先用待命的 negate_next，再按固定顺序过 trig.on_hurt；格挡了返回 0，否则返回 verb.dr 的乘积。
## src = 这一下的来源（读 boss），dmg = 这一下（已乘前面干员减伤）的伤害（护盾按它算吸收量）
func dmg_taken_mult(src: Dictionary, dmg: float) -> float:
	var boss: bool = src.get("boss", false)
	var negated := false
	if not gm.is_empty() and SegHoshiguma.gm_force_take(self):   # docs/202 星熊「般若之重」：武装后队长的下一次受击必定格挡
		negated = true
		_negate_fx({"text": "般若之重"})
	if not neg_armed.is_empty():
		var ks: Array = neg_armed.keys()
		ks.sort()
		var i: int = int(ks[0])
		var nb: Dictionary = neg_armed[i]
		neg_armed.erase(i)
		s_t[i] = 0.0   # 「下一次」用掉了，技能随即结束
		negated = true
		_negate_fx(nb)
		_defer(nb.get("on_block", []))
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_hurt" or not ObCore.cond_true(self, t.get("cond", _ED)):
			continue
		var neg: bool = t.get("negate", false)
		if neg and negated:
			continue
		var u: int = int(t.get("_uid", 0))
		if float(_hurt_cd.get(u, -INF)) > g.t:
			continue
		if not SegHoshiguma.roll(g, SegHoshiguma.hurt_chance(t, boss, neg_add, neg_mul)):
			continue
		if t.has("cd"):
			_hurt_cd[u] = g.t + float(t.cd)
		if neg:
			negated = true
			_negate_fx(t)
		_defer(t.get("do", []))
	if not negated:
		var dr0: float = ObHw.h4_live_dr(self) if not hw.is_empty() and ObHw.h4_on(self) else ext_dr   # 手写迁移段第 4 批：verb.dr 当刻现算（精英化当帧生效，同手写）
		return ObSummon.shield_mult(self, ObSummon.mf_guard_mult(self, dr0), dmg)   # 召唤物扩展段 verb.guard 的限时减伤；召唤 / 封印段：verb.shield 在减伤之后吸收（没有护盾时原样返回）
	negate_n += 1
	for t in _trigs():
		if str(t.get("_tag", "")) == "trig.on_negate" and ObCore.cond_true(self, t.get("cond", _ED)):
			_defer(t.get("do", []))
	return 0.0


## 受击询问里触发的积木推迟到本干员下一次 update 开头执行（延迟队列，t = 0）：enemy_hit 常在敌人遍历中途被调用，
## 不在那里造成伤害 / 击杀，免得遍历中改敌人列表；顺序仍固定（同 seed 可复现）
func _defer(arr: Array) -> void:
	if not arr.is_empty():
		pending.append({"t": 0.0, "do": arr})


## 格挡的画面 / 声音（不碰 g.rng）：通用 fx（§5.6，中心 = 主控）、text = 飘字（缺省「格挡」）
func _negate_fx(b: Dictionary) -> void:
	if b.has("fx"):
		ObFx.fx_play(self, b.fx, g.ppos, 30.0)
	float_text(g.ppos + Vector2(0, -88), str(b.get("text", "格挡")), Color(1.0, 0.85, 0.4), 16)
	_sfx_op("big")


## 地面层：区域帧条由通用 fx 在生成时播（pfx，循环到区域结束）；没写 fx / 缺图时画程序椭圆；negate_next 待命时主控脚下一圈金色盾环
func draw_entities_floor() -> void:
	if not hw.is_empty():
		ObHw.hw_draw_floor(self)   # 手写迁移段：浪墙 / 熔岩池 / 咒文……
	for f in fields:
		if ObFx.fx_any_tex(self, f.fx):
			continue
		var a: float = clampf((f.n * f.every - f.t) / 0.4, 0.0, 1.0) * clampf(f.t / 0.15, 0.0, 1.0)
		var cc: Color = col()
		cv.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.5))
		cv.draw_circle(Vector2.ZERO, float(f.r), Color(cc.r, cc.g, cc.b, 0.16 * a))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not taunt.is_empty() and skill_on(int(taunt.i)):   # 嘲讽圈：本干员脚下一圈金色虚环（范围 = 拉仇恨半径）
		var tr: float = float(taunt.b.r) * stat(&"op_range")
		var ka: float = 0.6 * ring_flash("taunt")   # 10-31 TA H1：开启那一瞬亮一下，不常驻
		if ka > 0.0:
			cv.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
			cv.draw_arc(Vector2.ZERO, tr, 0.0, TAU, 48, Color(1.0, 0.82, 0.35, ka), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not gm.is_empty():
		SegHoshiguma.gm_draw(self)   # docs/202：阻挡盾印 / 般若之重金环
	if not neg_armed.is_empty() and g.ppos != Vector2.INF:
		var k: float = 0.8 * ring_flash("negate")   # 10-31 TA H1：待命开始那一瞬亮一下
		cv.draw_set_transform(g.ppos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(1.0, 0.82, 0.35, k), 2.5)
# ================================================================ 安洁莉娜 angelina（docs/59 §5；docs/61 §12）—— 第三批追加段，只往后加
# shape.point_aoe 的飞行弹、dur.next_n 的次数、st.airborne 的悬浮表、verb.field 的画法；积木本身在 op_blocks.gd 的同名段

const GRAV := Color(0.7, 0.5, 0.95)   # 重力紫（docs/59 §5 特效主色）
var ammo: Array = [0, 0, 0]            # dur.next_n：技能 i 还剩几次强化普攻
var shots: Array = []                  # shape.point_aoe 飞行中的弹：[{p0, p1, t, dur, patch}]
var shot: Dictionary = {}              # 正在结算的这一弹的 attack_patch（verb.displace 读 force_mult）
var air_list: Array = []               # st.airborne：[{e, t, dur, h}]
var atk_to := Vector2.INF              # point_aoe 起手时选的落点（出手帧找不到新落点时用）


func skill_pending(i: int) -> bool:
	return ammo[i] > 0


## 出手帧：手动给了方向用 aim_land，否则重新选最密处（起手到出手之间敌人会动），都没有用起手时的落点；接下来 N 次的强化按技能序号先到先用
func _fire_point_aoe(a: Dictionary) -> void:
	var reach: float = float(a.get("range", 300.0)) * stat(&"op_range")
	var to := Vector2.INF
	var lp: Dictionary = aim_land(reach)
	if not lp.is_empty():
		to = lp.pos
	else:
		to = SegAngelina.point_aoe_target(self, a)
	if to == Vector2.INF:
		to = atk_to
	if to == Vector2.INF:
		return
	face = signf(to.x - pos.x) if absf(to.x - pos.x) > 2.0 else face
	var patch := {}
	var sk: Array = B.get("skills", [])
	for i in 3:
		if ammo[i] > 0 and i < sk.size():
			ammo[i] -= 1
			patch = sk[i].get("attack_patch", {})
			break
	SegAngelina.point_aoe_fire(self, a, to, patch)


func _tick_shots(dt: float) -> void:
	SegAngelina.airborne_tick(self, dt)
	if shots.is_empty():
		return
	var a: Dictionary = B.get("attack", {})
	var landed: Array = []
	for s in shots:
		s.t += dt
		if s.t >= s.dur:
			landed.append(s)
	shots = shots.filter(func(s): return s.t < s.dur)
	for s in landed:
		SegAngelina.point_aoe_land(self, a, s)
		_sfx_op("hit")
		fx({"kind": "ring", "pos": s.p1, "r": float(a.get("r", 60.0)) * float(loc.area), "r0": 6.0, "life": 0.3, "col": GRAV, "floor": true, "w": 2.0, "alpha": 0.7})


## 落点触发（trig.on_impact）：c = 落点；delay > 0 进延迟队列（带落点）
func impact(c: Vector2) -> void:
	for t in _trigs():
		if str(t.get("_tag", "")) != "trig.on_impact" or not ObCore.cond_true(self, t.get("cond", _ED)):
			continue
		var dl: float = float(t.get("delay", 0.0))
		if dl > 0.0:
			pending.append({"t": dl, "do": t.get("do", []), "at": c})
		else:
			_exec_list(t.get("do", []), c)


## 力场（verb.field look）：ring = 地面环带虚线缓慢旋转 + 内外两圈相向的光点（S2 重力场）；lift = 大圆 + 上升光点（S3 悬浮场）。
## 悬浮中的敌人脚下挂 fx_angelina_levitate。全部只读 g.t，不碰随机数
func _draw_fields() -> void:
	for u in _state:
		var st = _state[u]
		if not (st is Dictionary) or not st.has("look") or st.look == "none" or st.c == Vector2.INF:
			continue
		var c: Vector2 = st.c
		var r: float = st.r
		var gt: float = g.t
		cv.draw_set_transform(c + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		if st.look == "ring":
			var rr: float = st.ring if st.ring > 0.0 else r * 0.7
			var rf: float = ring_flash("field%s" % str(u))   # 10-31 TA H1：两道环只在展开那一瞬，之后靠往里吸的光点读范围
			cv.draw_circle(Vector2.ZERO, r, Color(GRAV.r, GRAV.g, GRAV.b, 0.035))
			if rf > 0.0:
				cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(GRAV.r, GRAV.g, GRAV.b, 0.16 * rf), 1.0)
				var n := 24
				for q in n:
					var a0: float = TAU * q / n + gt * 0.35
					cv.draw_arc(Vector2.ZERO, rr, a0, a0 + TAU / n * 0.55, 4, Color(GRAV.r * 1.3, GRAV.g * 1.3, GRAV.b * 1.3, 0.55 * rf), 2.0)
			for q in 10:
				var k: float = fmod(gt * 0.6 + q * 0.1, 1.0)
				var ang: float = TAU * q / 10.0 + 0.4 * q
				var po: Vector2 = Vector2.from_angle(ang) * lerpf(r, rr, k)          # 外圈往里
				var pin: Vector2 = Vector2.from_angle(ang + 0.3) * lerpf(rr * 0.35, rr, k)   # 内圈往外
				var al: float = sin(k * PI) * 0.8
				cv.draw_circle(po, 2.2, Color(GRAV.r * 1.6, GRAV.g * 1.6, GRAV.b * 1.6, al))
				cv.draw_circle(pin, 1.8, Color(1.2, 1.0, 1.5, al * 0.7))
		else:
			var pulse: float = 0.5 + 0.5 * sin(gt * 2.4)
			var lf: float = ring_flash("lift%s" % str(u))   # 10-31 TA H1：虚线外圈 + 内圈只在展开那一瞬
			cv.draw_circle(Vector2.ZERO, r, Color(GRAV.r, GRAV.g, GRAV.b, 0.06 + 0.02 * pulse))
			if lf > 0.0:
				for q in 32:
					var a1: float = TAU * q / 32 - gt * 0.25
					cv.draw_arc(Vector2.ZERO, r, a1, a1 + TAU / 64.0, 3, Color(GRAV.r * 1.4, GRAV.g * 1.4, GRAV.b * 1.4, 0.6 * lf), 2.0)
				cv.draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 40, Color(GRAV.r, GRAV.g, GRAV.b, (0.12 + 0.1 * pulse) * lf), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if st.look == "lift":
			for q in 14:
				var k2: float = fmod(gt * 0.45 + q * 0.071, 1.0)
				var ang2: float = TAU * q / 14.0 + q * 1.7
				var rad: float = r * (0.25 + 0.7 * fmod(q * 0.37, 1.0))
				var p2: Vector2 = c + Vector2(cos(ang2) * rad, sin(ang2) * rad * 0.55) + Vector2(0, -60.0 * k2)
				cv.draw_circle(p2, 1.8, Color(1.3, 1.0, 1.6, sin(k2 * PI) * 0.7))
	var lt: Texture2D = _fx_tex("fx_angelina_levitate") if not air_list.is_empty() else null
	for a in air_list:
		var e: Dictionary = a.e
		if e.dead:
			continue
		var fr: int = int((g.t + float(e.id) * 0.13) * 10.0) % 6
		if lt == null or not _fx_strip("fx_angelina_levitate", 6, fr, e.pos + Vector2(0, float(e.r) * 0.8), Vector2(0.5, 27.0 / 32.0)):
			cv.draw_set_transform(e.pos + Vector2(0, float(e.r) * 0.8), 0.0, Vector2(1.0, 0.45))
			cv.draw_arc(Vector2.ZERO, float(e.r) + 4.0, 0.0, TAU, 20, Color(GRAV.r * 1.4, GRAV.g * 1.4, GRAV.b * 1.4, 0.7), 2.0)
			cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 重力弹：杖头飞向落点，略带弧线；proj_angelina_orb 循环帧条（docs/25 §6，锚点居中）+ 落点地面预示圈
func _draw_shots() -> void:
	if shots.is_empty():
		return
	var a: Dictionary = B.get("attack", {})
	for s in shots:
		var k: float = clampf(s.t / maxf(0.01, s.dur), 0.0, 1.0)
		var p: Vector2 = s.p0.lerp(s.p1, k) + Vector2(0, -sin(k * PI) * 26.0)
		var big: bool = not s.patch.is_empty()
		SegAngelina.lens_draw(self, s, p)   # docs/202 重力透镜：弹道亮线（没选节点直接返回）
		cv.draw_circle(p, 11.0 if big else 8.0, Color(GRAV.r, GRAV.g, GRAV.b, 0.25))
		if _fx_tex("proj_angelina_orb") != null:
			draw_spr_rot("proj_angelina_orb", int(g.t * 12.0) % 4, p, 0.0, g.PX * (1.35 if big else 1.0))
		else:
			cv.draw_circle(p, 5.0, Color(GRAV.r * 1.6, GRAV.g * 1.6, GRAV.b * 1.6))
		var lr: float = float(a.get("r", 60.0)) * float(loc.area) * float(s.patch.get("r_mult", 1.0))
		cv.draw_set_transform(s.p1 + Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
		cv.draw_arc(Vector2.ZERO, lr * (1.0 - 0.6 * k), 0.0, TAU, 28, Color(GRAV.r, GRAV.g, GRAV.b, 0.35 * k), 1.5)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
# ---------------------------------------------------------------- 能天使（docs/61 §14）：弹体与状态条（实现在 op_blocks.gd 末尾）

func _draw_skill_over() -> void:
	_draw_shots()      # 安洁莉娜段：重力弹
	SegExusiai.exu_draw(self)  # 能天使段：弹体
	VisGrowth.draw(self)       # 可见成长：额外弹 / 剑气
	ObSummon.sm_draw_over(self)   # 召唤 / 封印段：封印标记、护盾
	ObSummon.mf_draw_guards(self)  # 召唤物扩展段：限时减伤护壳
	ObElite.el_draw_over(self)    # 精英化段：往返弹体
	if not hw.is_empty():
		ObHw.hw_draw_over(self)   # 手写迁移段：法术弹 / 抛射火团 / 咒文 / 锚……（第 3 批：浮空影环、锯弧、光弹、水母……）
	_draw_hold_strips(cv, "over")   # 常驻跟随帧条的 over 层（精英化段：能天使祝福光环挂在队友头顶）


func status_items() -> Array:
	return ObSummon.mf_status_items(self) + SegExusiai.exu_status_items(self) + ObSummon.sm_status_items(self) + (SegEyjafjalla.hw_status_items(self) if not hw.is_empty() else [])


## 手写迁移段：自己的法术弹（shape.shell，game 的 fire 子弹）爆炸后由 weapons.gd 回调
func bullet_exploded(b: Dictionary) -> void:
	SegEyjafjalla.hw_shell_boom(self, b)


## 精英化第 2 批段：本干员造成伤害之后（咒文链上的传递）
func deal_damage(e: Dictionary, dmg: float) -> void:
	super(e, dmg)
	if not sm.is_empty() and not sm.get("mark_b", _ED).is_empty():
		ObSummon.mark_hit(self, e)   # 召唤 / 封印段：verb.mark 叠层（拉普兰德 S3）
	if not hw.is_empty():
		SegLogos.hw_dealt(self, e, dmg)


# ---------------------------------------------------------------- 召唤 / 封印段（docs/61 §15）：召唤物参与 2.5D 排序（同凯尔希 Mon3tr 的 extra_bodies）

func extra_bodies() -> Array:
	return ObSummon.sm_bodies(self) + (ObHw.h3_extra_bodies(self) + SegSaria.h4_extra_bodies(self) if not hw.is_empty() else [])   # 手写迁移段第 3 批：替身 / 灯塔；第 4 批：晶柱


func draw_extra(it: Dictionary) -> void:
	if it.has("h4"):   # 手写迁移段第 4 批：晶柱
		SegSaria.h4_draw_extra(self, it)
		return
	if it.has("h3"):
		ObHw.h3_draw_body_extra(self, it)
		return
	ObSummon.sm_draw(self, it.s)


func draw_extra_shadows() -> void:
	ObSummon.sm_shadows(self)
	if not hw.is_empty():
		ObHw.h3_shadows(self)


## Shared occupancy covers automatic, manual and buffered casts; charging stays independent.
func skills_occupied() -> bool:
	return (acting() and act_kind == "skill") or (hw.has("mz") and sq_ph == 3) or AttackPhases.locked(self) or SkillLifecycle.occupied(self)

func charge_skills(dt: float) -> int:
	return -1 if skills_occupied() else super(dt)

func start_skill(aim: Vector2, idx: int = -1, dur: float = 0.6, fire_at: float = 0.3, anim := "") -> void:
	if not skills_occupied():
		super(aim, idx, dur, fire_at, anim)

func _start_action(kind: String, aim: Vector2, dur: float, fire_at: float, anim := "", interval := 0.0) -> void:
	if kind == "attack":
		anim = NativeMotion.timed_attack_slot(self, anim if anim != "" else "attack")
	super(kind, aim, dur, fire_at, anim, interval)
	NativeMotion.started(self)

func start_attack(aim: Vector2, dur: float = 0.5, fire_at: float = 0.25, anim := "", interval := 0.0) -> void:
	if AttackPhases.attack_locked(self):
		return
	if hw.has("bolts"):
		hw.body_variant = int(hw.get("bolt_variant", 0))
	AttackPhases.begin_round(self)
	# 普攻各形状都在起手前设置 cd；让无显式 interval 的近战 / 治疗也使用攻速压缩。
	super(aim, dur, fire_at, "" if not phases.is_empty() else anim, cd if interval <= 0.0 or not phases.is_empty() else interval)
	var timing: Dictionary = sprite_spec(act_anim).get("attack_timing", {})
	if timing.has("min_rest") and BranchBal.v("atkspeed/legacy_floor", 0.0) > 0.0:   # 旧：间隔不低于动作窗口 + min_rest；整条缩放后窗口 ≤ 间隔 × active_ratio，不再需要
		cd = maxf(cd, attack_dur + float(timing.min_rest))

func phase_shot(round_: Dictionary, shot: int) -> void:
	var a: Dictionary = round_.attack
	if str(a.shape) == "cannon":
		SegSkalter.h4_phase_shot(self, a, round_, shot)
		return
	var at := Vector2.INF
	if round_.target == "random" or str(a.get("center", "")) == "target":
		var radius: float = float(a.get("range", ObCore.shape_radius(self, a))) * (stat(&"op_range") if a.has("range") else 1.0)
		if round_.target == "inherit" and atk_aim != Vector2.ZERO:
			var target := aim_land(radius)
			if target.is_empty():
				return
			at = target.pos
		else:
			var target: Dictionary = {}
			if round_.target == "random":
				target = random_enemy(radius, pos)
			else:
				var near_: Array = nearest_enemies(1, radius, pos)
				target = near_[0] if not near_.is_empty() else {}
			if target.is_empty():
				return
			at = target.pos
	var previous_aim := atk_aim
	if str(a.shape) == "cone" and at != Vector2.INF:
		atk_aim = (at - pos).normalized()
	var previous: float = loc.atk
	var was_live := atk_live
	atk_live = true
	loc.atk *= float(round_.damage_mult)
	exec_any_shape(a, at, true)
	loc.atk = previous
	atk_aim = previous_aim
	atk_live = was_live

func phase_skill_end(i: int) -> void:
	for t in _trigs():
		if str(t.get("_tag", "")) == "trig.on_skill_end" and int(t.get("skill", -1)) == i and ObCore.cond_true(self, t.get("cond", _ED)):
			if t.has("at"):
				ObSummon.mf_fire_at(self, t, ObSummon.mf_at_point(self, str(t.at)))
			else:
				_exec_list(t.get("do", []), tx.get("last_to", pos))
