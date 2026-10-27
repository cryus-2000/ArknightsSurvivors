extends RefCounted
## 偏执泡影的连携攻势（docs/170，10-27）：每幕两组有限连段轮流出，连段里穿插本作改编的弹幕图案（对称环、正反旋、自机狙、缝隙墙、停滞再瞄准）。
## 节奏：一组连段（≤4 段，每段按当时队长位置重新瞄准，段间收势）→ 收招（不出招不走动，悬浮幕正好冲刺打落）→ 下一组。
## 打断：坠地、打散光环、被控 / 破绽、转幕、结茧都会清掉没放完的段和队列；已在飞的弹照旧。
## 状态全部在敌人字典 e（pc_*）；玩法时序只读 g.t，不用随机数（同 seed 可复现）；颗粒走 g.vrng（纯画面）。
## boss/paranoia_combos 0 = 关，回到旧的独立轮换（paranoia.gd step 后半）
const Bal = preload("res://scripts/core/balance.gd")
const BossBeam = preload("res://scripts/render/boss_beam.gd")

## 连段表（名字只在文档与回归里用，不上屏）
const COMBOS := {
	"千目凝望": {"seq": ["千目注视", "凝视", "叠影"]},
	"泡影环流": {"seq": ["泡影环", "环流狙击", "追猎泡"]},
	"镜中众影": {"seq": ["镜影齐射", "凝视", "泡影收束"]},
	"偏执双旋": {"seq": ["偏执双旋", "溟泡迸裂", "叠影"]},
	"无声呼号": {"seq": ["呼号", "无声波环", "追猎泡"]},
	"侵蚀帘幕": {"seq": ["侵蚀帘幕", "凝视", "呼号"]},
	"群愿回响": {"seq": ["群愿回响", "无声波环", "凝视", "呼号"]},
}
## 每幕两组，轮流：0 凝望（悬浮）/ 1 狂望（幻影）/ 2 失声（落地）/ 3 破茧后
const ACT_COMBOS := [["千目凝望", "泡影环流"], ["镜中众影", "偏执双旋"], ["无声呼号", "侵蚀帘幕"], ["群愿回响", "侵蚀帘幕"]]
## 弹幕段：发数 n、间隔 iv（秒）；起手前 WINDUP 秒聚光
const EMITTERS := {
	"千目注视": {"n": 7, "iv": 0.24}, "环流狙击": {"n": 3, "iv": 0.7}, "镜影齐射": {"n": 2, "iv": 0.8},
	"偏执双旋": {"n": 6, "iv": 0.42}, "无声波环": {"n": 2, "iv": 1.1}, "侵蚀帘幕": {"n": 2, "iv": 1.5}, "群愿回响": {"n": 2, "iv": 1.3}}
const WINDUP := 0.55
## 收招窗口：悬浮幕 / 落地后秒数；开始前要求本 Boss 同屏弹 < LOW_BULLETS；期间以 REST_SPD 靠近队长，停在 REST_NEAR（地面距离）内
const REST_P1 := 2.5
const REST_P2 := 3.0
const LOW_BULLETS := 20
const REST_SPD := 90.0
const REST_NEAR := 110.0
const BUL_CAP := 200
## 弹体分级：r 判定半径、伤害倍率（× e.dmg）
const TIER := {"s": [6.0, 0.34], "m": [9.0, 0.42], "l": [12.0, 0.5]}
const CORE := Color(0.95, 0.88, 1.0)

var g
var bs   # paranoia.gd 实例


func _init(game, boss_script) -> void:
	g = game
	bs = boss_script


static func on(e: Dictionary) -> bool:
	return Bal.v("boss/paranoia_combos", 1.0) > 0.0 and e.type == "paranoia"


## 幕：0 / 1 悬浮两幕，2 落地，3 破茧后
func act(e: Dictionary) -> int:
	if e.phase == 2:
		return 3 if e.get("cocoon_done", false) else 2
	return mini(1, int(e.get("gates_passed", 0)))


## 每帧（paranoia.step 在主轴机制之后调用）；返回 true = 出招由连段接管
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool) -> bool:
	_update_bullets(e, dt)
	if float(e.get("stun", 0.0)) > 0.0 or float(e.get("break_t", 0.0)) > 0.0:
		interrupt(e)
	_update_emitters(e)
	# 独立轮换（finals / patterns）由连段接管
	e.final_next = INF
	e.pattern_next = INF
	if g.t < float(e.get("pc_rest_until", 0.0)) and float(e.get("break_t", 0.0)) <= 0.0:
		_rest_approach(e, dt)
	var a: int = act(e)
	if a != int(e.get("pc_act", -1)):
		start_act(e, a)
		return true
	if not ready or g.t < float(e.get("pc_next", 0.0)) or not (e.get("pc_emit", []) as Array).is_empty():
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
			var rec: float = REST_P1 if e.phase == 1 else REST_P2
			e.pc_rested = true
			e.pc_idx = int(e.get("pc_idx", 0)) + 1
			e.wind = maxf(float(e.get("wind", 0.0)), rec)
			e.pc_next = g.t + rec
			e.pc_rest_until = g.t + rec
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
	e.pc_next = g.t + (0.25 if e.phase == 1 else 0.15)
	return true


## 进入新的一幕：清队列，从该幕第一组开始；起手前聚光 1 秒（只是画面上的收拢环 + 颗粒）
func start_act(e: Dictionary, a: int) -> void:
	interrupt(e)
	e.pc_act = a
	e.pc_idx = 0
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
	var had: bool = not (e.get("pc_queue", []) as Array).is_empty() or not (e.get("pc_emit", []) as Array).is_empty()
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
	var spec: Dictionary = EMITTERS[seg]
	var t0: float = g.t + WINDUP
	var em := {"name": seg, "t0": t0, "next": t0, "k": 0, "n": int(spec.n), "iv": float(spec.iv), "a0": dir.angle(),
		"flip": 1.0 if int(e.get("pc_flip", 0)) % 2 == 0 else -1.0}
	e.pc_flip = int(e.get("pc_flip", 0)) + 1
	if seg == "千目注视":
		# 7 只眼在你身边 280 处睁开（缺口在她那一侧，那里是冲进去的路），睁眼 0.8 秒后顺时针依次朝你开一枪，转一圈
		var c: Vector2 = g.combat.arena_clamp(g.ppos, 60.0) if g.zone_frozen else g.ppos
		var to_boss: float = (e.pos - c).angle()
		var eyes: Array = []
		for i in 7:
			var ang: float = to_boss + TAU * (i + 0.5) / 8.0 + TAU / 16.0
			eyes.append({"pos": c + Vector2.from_angle(ang) * 280.0, "open": g.t + 0.25, "close": g.t + WINDUP + 0.8 + 0.24 * 7 + 0.3})
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
	return (g.ppos + Vector2(0, -14) - from).angle()


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
			# 自机狙：每轮重新瞄准的 3 向扇，中间一发打你当时的位置；一直横移就不会中
			var a: float = _aim(o)
			for i in 3:
				_shot(e, o, a + (i - 1) * 0.32, 165.0, "m")
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
			# 正反两组 10 发环交替，转角相反，交织成菱形格
			var sgn: float = 1.0 if k % 2 == 0 else -1.0
			for i in 10:
				_shot(e, o, float(em.a0) + TAU * i / 10.0 + sgn * 0.3 * floorf(k / 2.0) + (0.15 if k % 2 else 0.0), 115.0, "s")
		"无声波环":
			# 两道 18 发减速泡环，缺口约 1.2 弧度且错位：第一道缺口朝你，第二道偏 0.95
			var gap_c: float = _aim(o) + (0.0 if k == 0 else 0.95 * float(em.flip))
			for i in 18:
				var a2: float = TAU * i / 18.0
				if absf(angle_difference(a2, gap_c)) < 0.6:
					continue
				var b: Dictionary = _shot(e, o, a2, 190.0, "m")
				if not b.is_empty():
					b.p_acc = -130.0
					b.p_vmin = 75.0
		"侵蚀帘幕":
			# 一排向前推进的弹墙（间距 40），留一道 150 宽的缝；第二排的缝向侧面错开 170
			var d: Vector2 = Vector2.from_angle(float(em.a0))
			var side: Vector2 = d.orthogonal()
			var gc: float = float(em.gap) if k == 0 else float(em.gap2)
			var s0: float = -450.0
			while s0 <= 450.0:
				if absf(s0 - gc) >= 75.0:
					_shot(e, o + d * 30.0 + side * s0, float(em.a0), 120.0, "s")
				s0 += 40.0
		"群愿回响":
			# 五瓣花：先按花瓣速度散开，1 秒后全部停住 0.5 秒，再各自对准你当时的位置射出
			for i in 20:
				var a3: float = TAU * i / 20.0 + 0.16 * k
				var spd: float = 70.0 + 70.0 * absf(cos(2.5 * (a3 - float(em.a0))))
				var b2: Dictionary = _shot(e, o, a3, spd, "m")
				if not b2.is_empty():
					b2.p_stop_at = g.t + 1.0
					b2.p_go_at = g.t + 1.5
					b2.p_v2 = 150.0
					b2.life = 8.0


## 一发实弹（进 g.ebullets，判定 / 机器人躲避 / 干员消弹都走公共管线）；超上限返回 {}
func _shot(e: Dictionary, from: Vector2, ang: float, spd: float, tier: String) -> Dictionary:
	var buls: Array = e.get("pc_buls", [])
	if buls.size() >= BUL_CAP:
		return {}
	var t: Array = TIER[tier]
	var b := {"pos": from, "vel": Vector2.from_angle(ang) * spd, "dmg": e.dmg * float(t[1]), "slow": false, "r": float(t[0]),
		"life": 6.5, "corrode": 0.15, "nerve": 0.0, "true": false, "kind": "orb", "home": false, "boss": true, "src_type": e.type,
		"no_rock": true, "atk": "法术", "pc_tier": tier}
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


func _update_bullets(e: Dictionary, dt: float) -> void:
	var buls: Array = e.get("pc_buls", [])
	if not buls.is_empty():
		var live: Array = []
		var gr = BossBeam.grains(g)
		for b in buls:
			if b.life <= 0.0:
				# 泡破：到期 / 命中 / 被消掉时散几颗淡紫颗粒（纯画面，走预算）
				if gr != null and BossBeam.take(g, 3) == 3:
					for q in 3:
						gr.push("mote_burst", b.pos + Vector2(0, -16), Vector2.from_angle(TAU * q / 3.0 + b.pos.x * 0.01), CORE)
				continue
			if b.has("p_acc"):
				var sp: float = maxf(float(b.p_vmin), b.vel.length() + float(b.p_acc) * dt)
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
