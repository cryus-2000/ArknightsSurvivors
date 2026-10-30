extends RefCounted
## 偏执泡影的连携攻势（docs/170，10-27）：每幕两组有限连段轮流出，连段里穿插本作改编的弹幕图案（对称环、正反旋、自机狙、缝隙墙、停滞再瞄准）。
## 节奏：一组连段（≤4 段，每段按当时队长位置重新瞄准，段间收势）→ 收招（不出招不走动，悬浮幕正好冲刺打落）→ 下一组。
## 打断：坠地、打散光环、被控 / 破绽、转幕、结茧都会清掉没放完的段和队列；已在飞的弹照旧。
## 状态全部在敌人字典 e（pc_*）；玩法时序只读 g.t，不用随机数（同 seed 可复现）；颗粒走 g.vrng（纯画面）。
## boss/paranoia_combos 0 = 关，回到旧的独立轮换（paranoia.gd step 后半）
const Bal = preload("res://scripts/core/balance.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")

## 连段表（名字只在文档与回归里用，不上屏）。用户 10-28「每个阶段重复少、有自己的特色、攻击招式不一样」：
## 每幕一个躲法主题，招式不跨幕复用（MOVES_BY_ACT 由 paranoia_combos_test 检查）
const COMBOS := {
	# 一 · 凝望：横移躲直线（光束、自机狙、眼圈）
	"千目凝望": {"seq": ["千目注视", "凝视", "环流狙击"]},
	"凝视环流": {"seq": ["凝视", "环流狙击", "千目注视"]},
	# 二 · 狂望：认真身、走菱形格（幻影、正反旋、冲撞、叠影）
	"镜中众影": {"seq": ["镜影齐射", "幻象冲撞", "叠影"]},
	"偏执双旋": {"seq": ["偏执双旋", "叠影", "镜影齐射"]},
	# 三 · 侵染：找缝（缝隙墙、错位缺口环、泡影环、追猎泡）
	"侵蚀帘幕": {"seq": ["侵蚀帘幕", "泡影环", "追猎泡"]},
	"错位回廊": {"seq": ["无声波环", "侵蚀帘幕", "泡影环"]},
	# 二阶段 · 失声（海嗣青蓝，「她被拖向海嗣」）：用户 10-28 定二阶段只一段、原失声 / 破茧后两段的 6 招合成一个池子，
	# 四组轮流（呼号扇区、潮涌环、沉浮双层 + 侵蚀泡沼、群愿回响、泡影收束、溟泡迸裂）；结茧保留，破茧后只收紧不换招（DENS 第 5 行等）
	"无声呼号": {"seq": ["呼号", "潮涌环", "群愿回响"]},
	"沉浮之潮": {"seq": ["沉浮双层", "泡影收束", "潮涌环+沉浮双层"]},
	"群愿回响": {"seq": ["群愿回响", "溟泡迸裂", "呼号"]},
	"破茧群潮": {"seq": ["溟泡迸裂", "沉浮双层", "群愿回响+泡影收束"]},
}
## 每幕轮流：0 凝望 / 1 狂望 / 2 侵染（悬浮，卡点 enemies.json gates [0.84, 0.67, 0.5]）/ 3 失声（落地二阶段）/ 4 破茧后（同一池子，收紧）
const P2_COMBOS := ["无声呼号", "沉浮之潮", "群愿回响", "破茧群潮"]
const ACT_COMBOS := [["千目凝望", "凝视环流"], ["镜中众影", "偏执双旋"], ["侵蚀帘幕", "错位回廊"], P2_COMBOS, P2_COMBOS]
## 弹幕段：发数 n、间隔 iv（秒）；起手前 WINDUP 秒聚光
const EMITTERS := {
	"千目注视": {"n": 7, "iv": 0.24}, "环流狙击": {"n": 3, "iv": 0.7}, "镜影齐射": {"n": 2, "iv": 0.8},
	"偏执双旋": {"n": 6, "iv": 0.42}, "无声波环": {"n": 2, "iv": 1.1}, "侵蚀帘幕": {"n": 2, "iv": 1.5}, "群愿回响": {"n": 2, "iv": 1.3},
	"沉浮双层": {"n": 3, "iv": 0.95}, "潮涌环": {"n": 3, "iv": 0.9, "wind": 1.0}}   # wind：起手提示秒数（缺省 WINDUP；潮涌环用户 10-28 要更明显）
const WINDUP := 0.55
## 幻象冲撞（非弹幕，泡影独有）：两只幻象在队长两侧现形，沿穿过队长的两条交叉通道冲过去；1.1 秒预告、第二只晚 0.6 秒
const RUSH_TELL := 1.1
const RUSH_STAGGER := 0.6
const RUSH_SPD := 900.0
const RUSH_LEN := 780.0
const RUSH_R := 34.0
## 收招窗口：悬浮幕 / 落地后秒数；开始前要求本 Boss 同屏弹 < LOW_BULLETS；期间以 REST_SPD 靠近队长，停在 REST_NEAR（地面距离）内
const REST_P1 := 2.5
const REST_P2 := 3.3   # r10 试过 3.5（破绽期输出 35%）；r11 用 3.0 + 抗性为 31%，r12 协调人定 3.3（docs/170 §3v）
## 力竭（用户 10-28「突然给出破绽有点奇怪」）：破绽前先 TIRE 秒泄气——不出招、泡沫从身上往下掉、身周光环收瘪，再进破绽
const TIRE := 0.6
const LOW_BULLETS := 20
const REST_SPD := 90.0
const REST_NEAR := 110.0
const MIRE_LIFE := 3.0
const MIRE_MAX := 8
const BUL_CAP := 120   # 同屏上限（协调人 10-28：二阶段峰值约 120）
## 密度与缺口按幕递进（用户 10-28「三幕区别不大、挺好躲」）：按 act 取一行
## [眼数, 眼圈轮数, 眼开枪间隔, 狙击向数, 狙击轮数, 双旋每环发数, 双旋轮数, 波环每圈发数, 波环缺口半角, 帘幕间距, 帘幕缝半宽, 群愿每朵发数]
const DENS := [
	[7, 2, 0.22, 3, 4, 10, 6, 16, 0.65, 44.0, 80.0, 18],
	[8, 1, 0.22, 3, 3, 10, 6, 18, 0.6, 40.0, 75.0, 20],
	[9, 1, 0.2, 5, 3, 12, 7, 20, 0.55, 36.0, 68.0, 22],
	[10, 1, 0.18, 5, 3, 11, 7, 20, 0.52, 36.0, 64.0, 22],
	[11, 1, 0.17, 5, 3, 12, 7, 22, 0.5, 34.0, 60.0, 22]]
## 弹体分级：r 判定半径、伤害倍率（× e.dmg）
const TIER := {"s": [6.0, 0.34], "m": [9.0, 0.42], "l": [12.0, 0.5]}
const CORE := Color(0.85, 0.55, 1.0)   # 颗粒（泡破 / 聚光）同泡泡的紫
## 二阶段主色：海嗣青蓝（与一阶段紫色对比；她的档案「被那股力量拖着，一点点变成自己最痛恨的模样」）
const SEA := Color(0.35, 0.9, 1.0)


func core(e: Dictionary) -> Color:
	return SEA if e.phase == 2 else CORE

var g
var bs   # paranoia.gd 实例


func _init(game, boss_script) -> void:
	g = game
	bs = boss_script


static func on(e: Dictionary) -> bool:
	return Bal.v("boss/paranoia_combos", 1.0) > 0.0 and e.type == "paranoia"


## 幕：0 / 1 / 2 悬浮三幕（卡点 enemies.json gates [0.84, 0.67, 0.5]，过 50% 落地），3 落地，4 破茧后
func act(e: Dictionary) -> int:
	if e.phase == 2:
		return 4 if e.get("cocoon_done", false) else 3
	return mini(2, int(e.get("gates_passed", 0)))


func _dn(e: Dictionary, i: int):
	var v = DENS[clampi(act(e), 0, DENS.size() - 1)][i]
	# 10-29 docs/201 §7（用户「弹幕频率、数量还是低」）：每波发数（眼数 / 狙击向数 / 双旋每环 / 波环每圈 / 群愿每朵）× boss/count_k_paranoia，眼开枪间隔 × boss/tempo_k_paranoia；缺口半角、帘幕缝宽不动
	# 按招式分工（10-29 用户「分配到不同的招式上」，docs/201 §8）：密度招 偏执双旋（双旋每环 5）/ 群愿回响（每朵 11）再 × paranoia_dense_k；
	# 快节奏招 千目注视（眼开枪间隔 2）再 × paranoia_fast_k、环流狙击（轮数 4）+1 轮；其余照旧当喘息段
	if i in [0, 3, 5, 7, 11]:
		var ck: float = Bal.v("boss/count_k_paranoia", 1.0) * (Bal.v("boss/paranoia_dense_k", 1.0) if i in [5, 11] else 1.0)
		return int(round(float(v) * ck))
	if i == 2:
		return float(v) * Bal.v("boss/tempo_k_paranoia", 1.0) * Bal.v("boss/paranoia_fast_k", 1.0)
	if i == 4:
		return int(v) + int(Bal.v("boss/paranoia_snipe_extra", 0.0))
	return v


## 每帧（paranoia.step 在主轴机制之后调用）；返回 true = 出招由连段接管
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool) -> bool:
	_update_bullets(e, dt)
	if float(e.get("stun", 0.0)) > 0.0 or float(e.get("break_t", 0.0)) > 0.0:
		interrupt(e)   # 收招破绽时队列本来就空，不会误清
	_update_emitters(e)
	# 独立轮换（finals / patterns）由连段接管
	e.final_next = INF
	e.pattern_next = INF
	if g.t < float(e.get("pc_rest_until", 0.0)) and float(e.get("drop_until", 0.0)) <= g.t:
		_rest_approach(e, dt)
	var a: int = act(e)
	if a != int(e.get("pc_act", -1)):
		start_act(e, a)
		return true
	_update_rush(e, dt)
	if not ready or g.t < float(e.get("pc_next", 0.0)) or not (e.get("pc_emit", []) as Array).is_empty() 			or not (e.get("pc_rush", []) as Array).is_empty():
		return true
	if g.warns.any(func(w): return is_same(w.owner, e) and not w.done and float(w.dmg) > 0.0):
		return true
	var queue: Array = e.get("pc_queue", [])
	if queue.is_empty():
		if not e.get("pc_rested", true):
			# 收招（输出窗口，协调人 10-27「给干员输出的机会」）：等上一组的弹散到 < LOW_BULLETS 才开始，不和密集段叠；
			# 收招期间不出招，慢慢靠近队长（停在 REST_NEAR 内，近战够得着）；悬浮幕正好冲刺打落
			if live_bullets(e) >= LOW_BULLETS:
				return true
			if float(e.get("pc_tire_at", 0.0)) <= 0.0:
				e.pc_tire_at = g.t + TIRE
				e.wind = maxf(float(e.get("wind", 0.0)), TIRE)
				e["move_name"] = "力竭"
				e["move_t"] = g.t
				var gt = BossBeam.grains(g)
				if gt != null:
					for q in BossBeam.take(g, 18):
						gt.push("mote_shed", e.pos + Vector2((q - 8.5) * 4.0, -30.0 - (q % 3) * 10.0), Vector2((q - 8.5) * 0.08, 1.0), core(e))
				return true
			if g.t < float(e.pc_tire_at):
				return true
			e.pc_tire_at = 0.0
			var rec: float = REST_P1 if e.phase == 1 else REST_P2
			# 收招 = 真破绽（10-28 测试台：破绽期输出只有 10%，目标 ≥35%）：break_t 期间受伤合计 paranoia_rest_taken，头顶写「破绽」读秒
			bs.brk(e, rec)
			e.pc_rested = true
			e.pc_idx = int(e.get("pc_idx", 0)) + 1
			e.wind = maxf(float(e.get("wind", 0.0)), rec)
			e.pc_next = g.t + rec
			e.pc_rest_until = g.t + rec
			e.pc_rest_len = rec
			e["move_name"] = "收招"
			e["move_t"] = g.t
			return true
		# 一幕悬浮离得远：先漂近（机制，不占连段）
		if e.phase == 1 and bs._close_in(e, dir, dist, "paranoia", "泡影漂近", Color(0.85, 0.45, 1.0)) >= 0.0:
			return true
		var combos: Array = ACT_COMBOS[a]
		e.pc_combo = combos[int(e.get("pc_idx", 0)) % combos.size()]
		queue = (COMBOS[e.pc_combo].seq as Array).duplicate()
		e.pc_queue = queue
		e.pc_rested = false
		e.pc_start_t = g.t
	var seg: String = str(queue.pop_front())
	_cast(e, seg, dir, dist)
	# 段间收势：悬浮 0.25、落地 0.15、破茧后 0.1（收紧）
	e.pc_next = g.t + (0.25 if e.phase == 1 else (0.1 if a == 4 else 0.15))
	return true


## 进入新的一幕：清队列，从该幕第一组开始；起手前聚光 1 秒（只是画面上的收拢环 + 颗粒）
func start_act(e: Dictionary, a: int) -> void:
	var was: int = int(e.get("pc_act", -1))
	interrupt(e)
	if a >= 3 and was >= 0 and was < 3:
		# 进入二阶段：一圈紫色泡沫向外迸开 + 震屏（「她认真了」；落地着色 / 地面压暗见 paranoia._paranoia_p2 与 paranoia_combo_draw）
		g.vfx.shake_screen(0.8)
		Sfx.play("roar", -3.0, 0.9, 0.0)
		var gr0 = BossBeam.grains(g)
		if gr0 != null:
			for k in BossBeam.take(g, 60):
				gr0.push("mote_burst", e.pos + Vector2(0, -20), Vector2.from_angle(TAU * k / 60.0), CORE)
	e.pc_act = a
	# 破茧后与失声同一池子：接着轮下一组，不从头再来
	e.pc_idx = int(e.get("pc_idx", 0)) if a == 4 and was == 3 else 0
	e.pc_rested = true
	e.pc_next = g.t + 1.0
	e.pc_gather_t = g.t
	e.wind = maxf(float(e.get("wind", 0.0)), 1.0)
	var gr = BossBeam.grains(g)
	if gr != null:
		for k in BossBeam.take(g, 36):
			var p: Vector2 = e.pos + Vector2.from_angle(TAU * k / 36.0) * 120.0
			gr.push("mote_in", p, e.pos - p, CORE)


## 打断（坠地 / 打散光环 / 被控 / 转幕）：没放完的弹幕段、队列、未结算的有伤预警与移动泡撤掉；已在飞的弹照旧。下一组从收招开始
func interrupt(e: Dictionary) -> void:
	var had: bool = not (e.get("pc_queue", []) as Array).is_empty() or not (e.get("pc_emit", []) as Array).is_empty() 		or not (e.get("pc_rush", []) as Array).is_empty()
	e.pc_rush = []   # 没冲完的幻象一并散掉
	e.pc_tire_at = 0.0
	if not (e.get("pc_emit", []) as Array).is_empty():
		e.pc_eyes = []   # 没开完枪的眼一起闭上
	e.pc_emit = []
	e.pc_queue = []
	if had:
		e.pc_rested = true
		e.pc_idx = int(e.get("pc_idx", 0)) + 1
		g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done or float(w.dmg) <= 0.0)
		for h in g.bai.finals.hazards:
			if is_same(h.owner, e):
				g.bai.finals._pop(h)
		g.bai.finals.hazards = g.bai.finals.hazards.filter(func(h): return not is_same(h.owner, e))


func live_bullets(e: Dictionary) -> int:
	var n := 0
	for b in e.get("pc_buls", []):
		if b.life > 0.0:
			n += 1
	return n


func _rest_approach(e: Dictionary, dt: float) -> void:
	if g.combat.ground_d(g.ppos, e.pos) <= REST_NEAR:
		return
	var to: Vector2 = e.pos.move_toward(g.ppos, REST_SPD * dt)
	e.pos = g.combat.arena_clamp(to, 80.0) if g.zone_frozen else to


## 结茧 / 死亡
func reset(e: Dictionary) -> void:
	interrupt(e)
	e.pc_fakes = []
	e.pc_eyes = []
	e.pc_act = -1


func _cast(e: Dictionary, seg: String, dir: Vector2, dist: float) -> void:
	if EMITTERS.has(seg):
		_emit(e, seg, dir)
		return
	if seg.contains("+"):
		# 叠放：两种弹幕同一段起手（二阶段）；各自独立计时，连段等两个都放完
		for part in seg.split("+"):
			_cast(e, part, dir, dist)
		e["move_name"] = seg.replace("+", " · ")
		return
	if seg == "幻象冲撞":
		rush(e, dir)
		return
	match seg:
		"凝视":
			bs._gaze(e, dir)
		"呼号":
			# 光环散开的 5 秒里不放（docs/142b §8.2）；离得远就跳过这一段
			if e.phase == 2 and not bs._aura_off(e) and dist < 300.0:
				bs._howl(e, dir)
		"叠影", "泡影环":
			e.pattern_force = seg
			g.bai.patterns.try_attack(e, dir, dist)
		_:
			g.bai.finals.force_move(e, seg, dir, dist)


## ---- 弹幕段
func _emit(e: Dictionary, seg: String, dir: Vector2) -> void:
	var spec: Dictionary = EMITTERS[seg].duplicate()
	if seg == "千目注视":
		spec.n = int(_dn(e, 0)) * int(_dn(e, 1))
		spec.iv = float(_dn(e, 2))
	elif seg == "环流狙击":
		spec.n = int(_dn(e, 4))
	elif seg == "偏执双旋":
		spec.n = int(_dn(e, 6))
	elif seg in ["侵蚀帘幕", "无声波环"] and act(e) >= 2:
		spec.n = 3   # 三幕起多一道：缝 / 缺口来回错位，要读
	if seg != "千目注视":
		spec.iv = float(spec.iv) * Bal.v("boss/tempo_k_paranoia", 1.0) * (Bal.v("boss/paranoia_fast_k", 1.0) if seg == "环流狙击" else 1.0)
	var wind: float = float(spec.get("wind", WINDUP))
	var t0: float = g.t + wind
	var em := {"name": seg, "t0": t0, "next": t0, "k": 0, "n": int(spec.n), "iv": float(spec.iv), "a0": dir.angle(), "wind": wind,
		"flip": 1.0 if int(e.get("pc_flip", 0)) % 2 == 0 else -1.0}
	e.pc_flip = int(e.get("pc_flip", 0)) + 1
	if seg == "千目注视":
		# 眼在你身边 280 处睁开（缺口在她那一侧，那里是冲进去的路），睁眼 0.8 秒后顺时针依次朝你开一枪；眼数 / 圈数按幕（DENS）
		var c: Vector2 = g.combat.arena_clamp(g.ppos, 60.0) if g.zone_frozen else g.ppos
		var to_boss: float = (e.pos - c).angle()
		var eyes: Array = []
		var ne: int = int(_dn(e, 0))
		for i in ne:
			var ang: float = to_boss + TAU * (i + 1) / float(ne + 1)
			eyes.append({"pos": c + Vector2.from_angle(ang) * 280.0, "open": g.t + 0.25, "close": g.t + WINDUP + 0.8 + float(spec.iv) * int(spec.n) + 0.3})
		e.pc_eyes = eyes
		em.t0 = g.t + WINDUP + 0.8
		em.next = em.t0
	if seg == "侵蚀帘幕":
		# 缝隙：第一道开在你当前的横向位置，第二道向场地更宽的一侧错开 170
		var side: Vector2 = dir.orthogonal()
		var off: float = clampf((g.ppos - e.pos).dot(side), -300.0, 300.0)
		em.gap = off
		em.gap2 = off + (170.0 if off <= 0.0 else -170.0)
	var emit: Array = e.get("pc_emit", [])
	emit.append(em)
	e.pc_emit = emit
	var cast_t: float = float(em.t0) - g.t + float(spec.iv) * (int(spec.n) - 1) + 0.1
	e.wind = maxf(float(e.get("wind", 0.0)), cast_t)
	g.bai.claim_token(e, g.t + cast_t + 0.4)
	e["move_name"] = seg
	e["move_t"] = g.t
	Sfx.play("skill", -12.0, 1.4)
	Sfx.play_cue("land", e.type, "start")
	var gr = BossBeam.grains(g)
	if gr != null:
		for k in BossBeam.take(g, 20):
			var p: Vector2 = e.pos + Vector2(0, -16) + Vector2.from_angle(TAU * k / 20.0) * 70.0
			gr.push("mote_in", p, e.pos + Vector2(0, -16) - p, CORE)


func _update_emitters(e: Dictionary) -> void:
	var emit: Array = e.get("pc_emit", [])
	if emit.is_empty():
		return
	var live: Array = []
	for em in emit:
		while int(em.k) < int(em.n) and g.t >= float(em.next):
			_fire(e, em, int(em.k))
			em.k = int(em.k) + 1
			em.next = float(em.next) + float(em.iv)
		if int(em.k) < int(em.n):
			live.append(em)
	e.pc_emit = live


func _aim(from: Vector2) -> float:
	return (g.shots.aim_pt() - from).angle()


func _fire(e: Dictionary, em: Dictionary, k: int) -> void:
	var o: Vector2 = e.pos
	match str(em.name):
		"千目注视":
			# 被注视：眼按顺时针轮流朝你当时的位置开一枪（一圈 7 枪），一直走动就落在身后
			var eyes: Array = e.get("pc_eyes", [])
			if not eyes.is_empty():
				var ey: Dictionary = eyes[k % eyes.size()]
				ey.fired = g.t
				_shot(e, ey.pos, _aim(ey.pos), 150.0, "m")
		"环流狙击":
			# 自机狙：每轮重新瞄准的扇（3 / 5 向按幕），中间一发打你当时的位置；一直横移就不会中
			var a: float = _aim(o)
			var nw: int = int(_dn(e, 3))
			for i in nw:
				_shot(e, o, a + (i - (nw - 1) * 0.5) * 0.3, 165.0, "m")
		"镜影齐射":
			# 真身与幻影各放 3 向自机狙；只有真身的弹是实心、有伤害，幻影放的是空心泡
			var srcs: Array = [e]
			for sl in e.get("decoys", []):
				if sl.o != null and not sl.o.dead:
					srcs.append(sl.o)
			for s in srcs:
				var aa: float = _aim(s.pos)
				for i in 3:
					if is_same(s, e):
						_shot(e, s.pos, aa + (i - 1) * 0.26, 150.0, "m")
					else:
						_fake(e, s.pos, aa + (i - 1) * 0.26, 150.0, 8.0)
		"偏执双旋":
			# 正反两组环交替（每环发数按幕），转角相反，交织成菱形格
			var sgn: float = 1.0 if k % 2 == 0 else -1.0
			var nr: int = int(_dn(e, 5))
			for i in nr:
				_shot(e, o, float(em.a0) + TAU * i / float(nr) + sgn * 0.3 * floorf(k / 2.0) + (PI / nr if k % 2 else 0.0), 115.0, "s")
		"无声波环":
			# 两道 18 发泡环，先慢后加速，缺口约 1.2 弧度且错位：第一道缺口朝你，第二道偏 0.95
			# 第三道（三幕起）错到另一侧
			var gap_c: float = _aim(o) + (0.0 if k == 0 else (0.95 if k == 1 else -0.95) * float(em.flip))
			var nwr: int = int(_dn(e, 7))
			for i in nwr:
				var a2: float = TAU * i / float(nwr)
				if absf(angle_difference(a2, gap_c)) < float(_dn(e, 8)):
					continue
				# 10-27 用户「打出去以后弹幕可以加速」：先以 80 慢慢鼓出（看清缺口），0.45 秒后每秒 +260 加速到 280
				var b: Dictionary = _shot(e, o, a2, 80.0, "m")
				if not b.is_empty():
					b.p_acc = 260.0
					b.p_vmin = 80.0
					b.p_vmax = 280.0
					b.p_acc_at = g.t + 0.45
		"侵蚀帘幕":
			# 一排向前推进的弹墙（间距 40），留一道 150 宽的缝；第二排的缝向侧面错开 170
			var d: Vector2 = Vector2.from_angle(float(em.a0))
			var side: Vector2 = d.orthogonal()
			var gc: float = float(em.gap2) if k == 1 else float(em.gap)   # 第三排（三幕起）缝回到第一道的位置
			var s0: float = -450.0
			while s0 <= 450.0:
				if absf(s0 - gc) >= float(_dn(e, 10)):
					_shot(e, o + d * 30.0 + side * s0, float(em.a0), 120.0, "s")
				s0 += float(_dn(e, 9))
		"群愿回响":
			# 五瓣花：先按花瓣速度散开，1 秒后全部停住 0.5 秒，再各自对准你当时的位置射出
			var nf: int = int(_dn(e, 11))
			for i in nf:
				var a3: float = TAU * i / float(nf) + 0.16 * k
				var spd: float = 70.0 + 70.0 * absf(cos(2.5 * (a3 - float(em.a0))))
				var b2: Dictionary = _shot(e, o, a3, spd, "m")
				if not b2.is_empty():
					b2.p_stop_at = g.t + 1.0
					b2.p_go_at = g.t + 1.5
					b2.p_v2 = 150.0
					b2.life = 8.0
		"沉浮双层":
			# 快慢分层（二阶段）：一圈 10 颗慢大泡缓缓漂开，同时一圈 18 发快小弹，快弹缺口 0.7 弧度朝你当时的位置；
			# 先穿快弹的缺口，再在慢泡之间绕
			var ga: float = _aim(o)
			for i in 10:
				var bl: Dictionary = _shot(e, o, float(em.a0) + TAU * i / 10.0 + 0.3 * k, 70.0, "l")
				if not bl.is_empty() and i % (2 if act(e) == 4 else 3) == 0:
					bl.p_mire = true   # 侵蚀泡沼：每 3 颗慢大泡里 1 颗（破茧后每 2 颗 1 颗）破开时留一小块 Boss 溟痕
			for i in 18:
				var a4: float = TAU * i / 18.0 + 0.17 * k
				if absf(angle_difference(a4, ga)) < 0.35:
					continue
				_shot(e, o, a4, 210.0, "s")
		"潮涌环":
			# 二阶段专属：从她脚下扩出一道水环（≤ 200 像素 / 秒），环上一个缺口，三道缺口依次转开 1.1 弧度；
			# 抓环靠近的时机，从缺口穿过（判定走公共冲击环：地面椭圆、环带宽 22、命中一次、站在缺口里不算）
			var gap: float = _aim(o) + 1.1 * k * float(em.flip)
			g.shocks.append({"pos": o, "r": 40.0, "maxr": 640.0, "spd": 190.0, "hit": false, "boss": true, "src_type": e.type,
				"dmg": e.dmg * 0.6 * Bal.v("boss/paranoia_bullet_mult_p2", 1.3), "gaps": [gap], "gap_half": 0.42, "true": false,
				"col": SEA, "owner": e})
			g.fx.append({"kind": "ring", "pos": o, "r": 60.0, "life": 0.35, "max": 0.35, "col": SEA, "enemy": true})


## 一发实弹（进 g.ebullets，判定 / 机器人躲避 / 干员消弹都走公共管线）；超上限返回 {}
func _shot(e: Dictionary, from: Vector2, ang: float, spd: float, tier: String) -> Dictionary:
	var buls: Array = e.get("pc_buls", [])
	if buls.size() >= BUL_CAP:
		return {}
	var t: Array = TIER[tier]
	var b := {"pos": from, "vel": Vector2.from_angle(ang) * spd, "dmg": e.dmg * float(t[1]) * (Bal.v("boss/paranoia_bullet_mult_p2", 1.3) if e.phase == 2 else Bal.v("boss/paranoia_bullet_mult", 1.0)), "slow": false, "r": float(t[0]),
		"life": 6.5, "corrode": 0.15, "nerve": 0.0, "true": false, "kind": "orb", "home": false, "boss": true, "src_type": e.type,
		"no_rock": true, "atk": "法术", "pc_tier": tier, "own_draw": e.phase == 2}   # 二阶段海嗣滴由 paranoia_combo_draw 整颗画
	g.ebullets.append(b)
	buls.append(b)
	e.pc_buls = buls
	return b


## 幻影的空心泡：只画不判定（render/paranoia_card_draw.gd）
func _fake(e: Dictionary, from: Vector2, ang: float, spd: float, r: float) -> void:
	var fakes: Array = e.get("pc_fakes", [])
	if fakes.size() < 60:
		fakes.append({"pos": from, "vel": Vector2.from_angle(ang) * spd, "r": r, "life": 4.5})
	e.pc_fakes = fakes


## 侵蚀泡沼（10-28 方案：二阶段加压迫，不靠加血）：Boss 溟痕（减速 45%、每秒 2% 最大生命、累积神经损伤，enemies.gd），
## 半径 30→40、存在 MIRE_LIFE 秒；场上本 Boss 留的泡沼最多 MIRE_MAX 块
func _mire(pos: Vector2) -> void:
	var n := 0
	for m in g.mires:
		if m.get("pc_mire", false) and m.life > 0.0:
			n += 1
	if n >= MIRE_MAX:
		return
	if g.zone_frozen and pos.distance_to(g.zone_next_c) > g.zone_next_r - 60.0:
		return
	g.mires.append({"pos": pos + Vector2(0, 10), "r": 30.0, "maxr": 40.0, "life": MIRE_LIFE, "seed": g.vrng.randf() * 100.0, "boss": true, "pc_mire": true})


func _update_bullets(e: Dictionary, dt: float) -> void:
	var buls: Array = e.get("pc_buls", [])
	if not buls.is_empty():
		var live: Array = []
		var gr = BossBeam.grains(g)
		for b in buls:
			if b.life <= 0.0:
				if b.get("p_mire", false):
					_mire(b.pos)
				# 泡破：到期 / 命中 / 被消掉时散几颗颗粒（一阶段紫、二阶段青蓝；纯画面，走预算）
				if gr != null and BossBeam.take(g, 3) == 3:
					for q in 3:
						gr.push("mote_burst", b.pos + Vector2(0, -16), Vector2.from_angle(TAU * q / 3.0 + b.pos.x * 0.01), core(e))
				continue
			if b.has("p_acc") and g.t >= float(b.get("p_acc_at", 0.0)):
				var sp: float = clampf(b.vel.length() + float(b.p_acc) * dt, float(b.p_vmin), float(b.get("p_vmax", INF)))
				b.vel = b.vel.normalized() * sp
			if b.has("p_stop_at") and g.t >= float(b.p_stop_at):
				b.erase("p_stop_at")
				b.vel = b.vel * 0.001   # 停住（保留方向给画面）
			if b.has("p_go_at") and g.t >= float(b.p_go_at):
				b.erase("p_go_at")
				b.vel = Vector2.from_angle(_aim(b.pos)) * float(b.p_v2)
			live.append(b)
		e.pc_buls = live
	var fakes: Array = e.get("pc_fakes", [])
	if not fakes.is_empty():
		var lf: Array = []
		for f in fakes:
			f.pos += f.vel * dt
			f.life -= dt
			if f.life > 0.0:
				lf.append(f)
		e.pc_fakes = lf


## ---- 幻象冲撞（docs/170 §3e）：第一只的通道沿「她 → 你」的横向穿过你，第二只与之垂直；通道只按出手时的你定位，之后不追
func rush(e: Dictionary, dir: Vector2) -> void:
	var c: Vector2 = g.ppos
	var lanes: Array = []
	for k in 2:
		var d: Vector2 = dir.orthogonal() if k == 0 else dir
		if k == 1 and int(e.get("pc_flip", 0)) % 2 == 1:
			d = -d
		var a: Vector2 = c - d * RUSH_LEN * 0.5
		if g.zone_frozen:
			a = g.combat.arena_clamp(a, 40.0)
		var t_go: float = g.t + RUSH_TELL + RUSH_STAGGER * k
		lanes.append({"a": a, "d": d, "t0": g.t + RUSH_STAGGER * k, "t_go": t_go, "pos": a, "hit": false, "end": t_go + RUSH_LEN / RUSH_SPD})
	e.pc_flip = int(e.get("pc_flip", 0)) + 1
	e.pc_rush = lanes
	var cast_t: float = RUSH_TELL + RUSH_STAGGER + RUSH_LEN / RUSH_SPD
	e.wind = maxf(float(e.get("wind", 0.0)), cast_t)
	g.bai.claim_token(e, g.t + cast_t + 0.3)
	e["move_name"] = "幻象冲撞"
	e["move_t"] = g.t
	Sfx.play("skill", -12.0, 1.4)
	Sfx.play_cue("charge", e.type, "start")


func _update_rush(e: Dictionary, dt: float) -> void:
	var lanes: Array = e.get("pc_rush", [])
	if lanes.is_empty():
		return
	var live: Array = []
	var gr = BossBeam.grains(g)
	for ln in lanes:
		if g.t < float(ln.t_go):
			live.append(ln)
			continue
		if not ln.get("launched", false):
			# 起冲：身后一圈泡沫迸开（纯画面）
			ln.launched = true
			if gr != null:
				for q in BossBeam.take(g, 16):
					gr.push("mote_burst", ln.a + Vector2(0, -24), -ln.d.rotated((q - 7.5) * 0.18), CORE)
			Sfx.play("swing", -10.0, 0.8, 0.05)
		var el: float = minf(g.t, float(ln.end)) - float(ln.t_go)
		var prev: Vector2 = ln.pos
		ln.pos = ln.a + ln.d * RUSH_SPD * el
		# 扫掠判定：本帧走过的线段离队长 < 冲撞半径 + 12 算中一次
		if not ln.hit and Geometry2D.get_closest_point_to_segment(g.ppos, prev, ln.pos).distance_to(g.ppos) < RUSH_R + 12.0:
			ln.hit = true
			if g.invuln <= 0.0:
				g.combat.enemy_hit(e.dmg * Bal.v("boss/paranoia_rush_mult", 1.3), {"boss": true, "src_type": e.type, "corrode": 0.3}, false, true, ["近战", "法术"], "boss_" + e.type)
		if gr != null and BossBeam.take(g, 4) == 4:
			# 尾流：身后两侧各一串泡沫，向外散开
			for sd in [-1.0, 1.0]:
				gr.push("mote_shed", ln.pos + Vector2(0, -20) + ln.d.orthogonal() * 18.0 * sd, -ln.d + ln.d.orthogonal() * 0.6 * sd, CORE)
				gr.push("mote_burst", ln.pos + Vector2(0, -36) - ln.d * 20.0, -ln.d + ln.d.orthogonal() * 0.3 * sd, CORE)
		if g.t >= float(ln.end):
			# 冲到头碎成泡
			if gr != null:
				for q in BossBeam.take(g, 14):
					gr.push("mote_burst", ln.pos + Vector2(0, -24), Vector2.from_angle(TAU * q / 14.0), CORE)
			Sfx.play("shell_break", -10.0, 1.5, 0.0)
			continue
		live.append(ln)
	e.pc_rush = live
