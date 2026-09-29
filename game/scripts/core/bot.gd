extends RefCounted
## 平衡测试机器人（docs/29）：四档玩家画像（走位 + 选卡）。局内指标采集在 run/telemetry.gd（docs/40，玩家局共用）。
## 只在 `--balance` 下由 game.gd 创建；`--bot=afk|bad|normal|expert` 选档，缺省 normal（= 原有机器人，便于和旧基线对比）。
##
##   afk     挂机：原地不动，只靠干员自动攻击；选卡随机。            → 下限：什么都不做能活多久
##   bad     手残：随机乱走，看到危险只有 30% 概率、延迟 0.4 秒才躲；选卡随机。
##   normal  普通：躲预警 / 溟痕 / 弹幕、保持距离、捡东西（原 _bot_move）；选卡按 balance.json bot 权重。
##   expert  高手：每帧对 16 个方向打分找空地、持续绕圈风筝、提前躲预警；选卡按编队缺口与局势打分。
##   master  熟练真人（2026-09-29，校准新难度用）：在 expert 上加敌人 / 弹幕外推预判、冲刺无敌躲招（含必须冲刺的解读冲击）、
##           防包围（找最大缺口）、按编队射程拉开输出、Boss 环形弹幕钻缺口；选卡认流派凑套、按藏品强度档、受伤优先回复，商店同规则。
##
## 所有随机都走自己的 RandomNumberGenerator（按 --seed 派生），不碰全局随机流，同 seed 可复现性不变差。

const PROFILES := ["afk", "bad", "normal", "expert", "master"]

var g                           # game.gd
var profile := "normal"
var rng := RandomNumberGenerator.new()

# ---- bad：随机走位状态
var wander_dir := Vector2.ZERO
var wander_t := 0.0
var dodge_t := 0.0              # >0：正在躲（延迟后才开始）
var dodge_delay := 0.0
var react_t := 0.0

# ---- expert：动量（让它绕圈而不是原地抖）
var last_dir := Vector2.RIGHT
var keep := 100.0               # 与敌人保持的距离：近战编队要贴近些让干员打得到
const MELEE := ["近卫", "重装", "先锋", "特种"]

# 整局指标（受击 / 低血 / 死因 / 曲线……）2026-09-26 挪到 run/telemetry.gd，所有对局共用

# ---- 流派专精（--lane=A…H，docs/35 流派平衡）：藏品三选一与商店优先拿该流派，测「认准一条流派」的体验；
# 该流派拿了几件由 tools/balance_run.py 从记录的 relic_take 推算
var lane := ""
const RARITY_RANK := {"升华": 4, "核心": 3, "稀有": 2, "基础": 1}


func _init(game, p: String, seed_v: int) -> void:
	g = game
	profile = p if p in PROFILES else "normal"
	rng.seed = hash("bot:%s:%d" % [profile, seed_v])
	for a in Cfg.dev_args():
		if a.begins_with("--lane="):
			lane = a.substr(7)
		elif a.begins_with("--mt_") and a.contains("="):
			var kv: PackedStringArray = a.substr(5).split("=")
			if m_tune.has(kv[0]):
				m_tune[kv[0]] = float(kv[1])


# =====================================================================
# 移动
# =====================================================================
func move(dt: float) -> Vector2:
	match profile:
		"afk":
			return Vector2.ZERO
		"bad":
			return _move_bad(dt)
		"expert":
			return _move_expert()
		"master":
			return _move_master(dt)
	return g.autotest_sys.bot_move()


## 手残：随机方向走 0.8–2.2 秒再换；每 0.5 秒检查一次危险，30% 概率在 0.4 秒后躲 0.5 秒（用普通机器人的躲法）
func _move_bad(dt: float) -> Vector2:
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = rng.randf_range(0.8, 2.2)
		wander_dir = Vector2.ZERO if rng.randf() < 0.25 else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.5, 1.0)
	react_t -= dt
	if react_t <= 0.0 and dodge_t <= 0.0 and dodge_delay <= 0.0:
		react_t = 0.5
		if _in_danger(g.ppos, 30.0) and rng.randf() < 0.3:
			dodge_delay = 0.4
	if dodge_delay > 0.0:
		dodge_delay -= dt
		if dodge_delay <= 0.0:
			dodge_t = 0.5
	if dodge_t > 0.0:
		dodge_t -= dt
		return g.autotest_sys.bot_move()
	# 缩圈外会被烧死：手残玩家也知道往圈里走，但慢半拍
	if g.zone_state != 0 and g.ppos.distance_to(g.zone_c) > g.zone_r - 40.0:
		return (g.zone_c - g.ppos).normalized()
	return wander_dir


## 高手：16 个方向 × 两个步长打分，挑最安全又有收益的方向；弹幕按 0.15/0.3/0.45 秒后的位置预判；
## 带动量，自然形成绕圈风筝；附近危险时降低捡东西 / 贴 Boss 的欲望
func _move_expert() -> Vector2:
	var p: Vector2 = g.ppos
	var near: Array = []
	for j in g.enemies_sys.query(p, 380.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.get("chest", false) or float(e.get("dmg", 1.0)) <= 0.0:
			continue
		near.append(e)
	_prep_near(near)
	var bullets: Array = []
	for bl in g.ebullets:
		if bl.life > 0.0 and bl.pos.distance_to(p) < 320.0:
			bullets.append(bl)
	var melee := 0
	for o in g.squad.ops:
		if MELEE.has(o.def.get("class", "")):
			melee += 1
	keep = lerpf(100.0, 50.0, float(melee) / maxf(1.0, g.squad.size()))
	var goal := _expert_goal(p, near)
	var spd: float = g.speed
	var here := _score_point(p, near) + _bullet_risk(p, Vector2.ZERO, 0.0, bullets)
	var best_dir := Vector2.ZERO
	var best := here - (0.8 if here > -1.0 else 0.0)   # 安全时也保持移动；危险时静止不额外扣分
	for k in 16:
		var d := Vector2.from_angle(TAU * k / 16.0)
		var s1 := _score_point(p + d * 70.0, near)
		var s := 0.55 * s1 + 0.45 * _score_point(p + d * 150.0, near) + _bullet_risk(p, d, spd, bullets)
		if goal != Vector2.ZERO:
			s += 2.0 * d.dot(goal) * (1.0 if s1 > -1.5 else 0.35)
		s += 0.6 * d.dot(last_dir)
		if s > best:
			best = s
			best_dir = d
	if best_dir != Vector2.ZERO:
		last_dir = best_dir
	return best_dir


## 沿 d 方向走 0.15 / 0.3 / 0.45 秒后，会不会和弹幕重叠
func _bullet_risk(p: Vector2, d: Vector2, spd: float, bullets: Array) -> float:
	var s := 0.0
	for bl in bullets:
		for tau in [0.15, 0.3, 0.45]:
			var q: Vector2 = p + d * spd * tau
			var b: Vector2 = bl.pos + bl.vel * tau
			if q.distance_to(b) < float(bl.get("r", 6.0)) + 20.0:
				s -= 9.0
				break
	return s


## 每步把附近敌人的打分参数先算好（位置、半径、权重、速度余量、远程射程），33 个候选点共用，
## 不再每个点都去字典里取一遍（机器人原来占一局耗时的四分之一；算式与原来逐项相同，行为不变）
var _np := PackedVector2Array()
var _nr := PackedFloat64Array()
var _nw := PackedFloat64Array()
var _nf := PackedFloat64Array()
var _nrg := PackedFloat64Array()   # 远程怪（非 Boss）的「射程 + 10」；不是远程为 -1


func _prep_near(near: Array) -> void:
	var n := near.size()
	_np.resize(n)
	_nr.resize(n)
	_nw.resize(n)
	_nf.resize(n)
	_nrg.resize(n)
	for i in n:
		var e: Dictionary = near[i]
		_np[i] = e.pos
		_nr[i] = float(e.r)
		_nw[i] = 3.0 if (e.elite or e.boss) else 1.0
		_nf[i] = 1.0 + clampf((float(e.get("spd", 50.0)) - 50.0) / 60.0, 0.0, 1.0)   # 快的怪要留更大余量
		_nrg[i] = float(e.get("range", 200.0)) + 10.0 if (e.get("ai", "") == "ranged" and not e.boss) else -1.0


## 一个位置的安全分（越高越安全）：敌人距离、预警、溟痕、弹幕、缩圈。敌人部分读 _prep_near 的缓存
func _score_point(q: Vector2, _near: Array) -> float:
	var s := 0.0
	for i in _np.size():
		var dd: float = q.distance_to(_np[i]) - _nr[i]
		var w: float = _nw[i]
		# 远程怪：待在射程外沿
		if _nrg[i] >= 0.0 and dd < _nrg[i]:
			s -= 0.6
		var fast: float = _nf[i]
		if dd < 30.0 * fast:
			s -= 12.0 * w
		elif dd < keep * fast:
			s -= (keep * fast - dd) / (keep * fast) * 3.0 * w
		elif dd < 220.0:
			s -= (220.0 - dd) / 220.0 * 0.35 * w
	for wv in g.warns:
		if wv.done:
			continue
		if _in_warn(wv, q, 36.0):
			s -= 25.0
	for m in g.mires:
		if g.combat.ground_d(q, m.pos) < float(m.r) + 26.0:
			s -= 18.0
	if g.zone_state != 0:
		var tc: Vector2 = g.zone_next_c if g.zone_state == 1 else g.zone_c
		var tr: float = g.zone_next_r if g.zone_state == 1 else g.zone_r
		var over: float = q.distance_to(tc) - (tr - 120.0)
		if over > 0.0:
			s -= over * 0.12
		if q.distance_to(g.zone_c) > g.zone_r:
			s -= 30.0
	return s


## 高手的目标方向：灯火低先找灯油，其次宝箱 / 商人 / 经验；满血时贴近 Boss 让干员输出（但不贴身）
func _expert_goal(p: Vector2, near: Array) -> Vector2:
	var best_v := Vector2.ZERO
	var best_w := 999999.0
	for gm in g.gems:
		var d: float = gm.pos.distance_to(p)
		if d > 420.0:
			continue
		var w := d
		if gm.kind == "oil":
			w *= 0.25 if g.lamp < 60.0 else 0.8
		elif gm.kind == "chest" or gm.kind == "heal":
			w *= 0.4
		if w < best_w:
			best_w = w
			best_v = (gm.pos - p).normalized()
	for e in g.enemies:
		# 海嗣祭坛只有主控走近才打开（事件验收 P2-10），刷在 520–650 外：机器人像真人一样看方位指示走过去
		var reach: float = 1600.0 if e.get("event", "") != "" else 450.0
		if e.get("chest", false) and not e.dead and e.pos.distance_to(p) < reach:
			return (e.pos - p).normalized()
	for b in g.beacons:
		# 血量门槛 45% → 25%（协调人 9/30：Ⅷ 主控常年低血，45% 时几乎不去点灯；真人低血反而更想进安全区）；高手 / master 共用，普通在 autotest 里另算
		if not b.lit and g.hp > g.max_hp * 0.25 and b.pos.distance_to(p) < 700.0:
			return (b.pos - p).normalized() if b.pos.distance_to(p) > 40.0 else Vector2.ZERO   # 引航灯标：去光圈里站着
	if not g.merchant.is_empty() and g.merchant.pos.distance_to(p) < 600.0 and not g.merchant.near:
		return (g.merchant.pos - p).normalized()
	if g.hp > g.max_hp * 0.55:
		for bb in g.bosses:
			if not bb.dead and not bb.get("invuln", false):
				var bd: float = bb.pos.distance_to(p)
				if bd > 320.0:
					return (bb.pos - p).normalized() * 0.6
				elif bd < 200.0:
					return (p - bb.pos).normalized() * 0.8
				break
	if best_v == Vector2.ZERO and not near.is_empty() and g.hp > g.max_hp * 0.5:
		# 附近没东西捡：朝稀疏一侧的敌人靠一点，保持干员有目标
		var c := Vector2.ZERO
		for e in near:
			c += e.pos
		c /= near.size()
		if c.distance_to(p) > keep + 80.0:
			best_v = (c - p).normalized() * (0.4 if keep > 80.0 else 0.8)
	return best_v


func _in_warn(w: Dictionary, q: Vector2, pad: float) -> bool:
	match w.shape:
		"circle":
			return q.distance_to(w.pos) < float(w.r) + pad
		"line":
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * float(w.len)
			return Geometry2D.get_closest_point_to_segment(q, w.pos, b).distance_to(q) < float(w.wid) + pad
		"cone":
			var dv: Vector2 = q - w.pos
			if dv.length() > float(w.r) + pad:
				return false
			return absf(angle_difference(dv.angle(), float(w.ang))) < float(w.get("half", 0.8)) + 0.15
	return g.combat.ground_d(q, w.pos) < float(w.get("r", 60.0)) + pad   # 与游戏判定共用地面椭圆（§1.9）


func _in_danger(q: Vector2, pad: float) -> bool:
	for wv in g.warns:
		if not wv.done and _in_warn(wv, q, pad):
			return true
	for m in g.mires:
		if g.combat.ground_d(q, m.pos) < float(m.r) + pad:
			return true
	for j in g.enemies_sys.query(q, 60.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.get("chest", false) and q.distance_to(e.pos) < float(e.r) + 30.0:
			return true
	for bl in g.ebullets:
		if bl.life > 0.0 and bl.pos.distance_to(q) < 80.0:
			return true
	return false


# =====================================================================
# 选卡
# =====================================================================
## 返回 -1 表示交给 game.gd 原有的加权选卡（normal）
func pick(choices: Array) -> int:
	if choices.is_empty():
		return 0
	if lane != "":
		var li := _lane_best(choices)
		if li >= 0:
			return li
	match profile:
		"afk", "bad":
			return rng.randi() % choices.size()
		"expert":
			return _pick_expert(choices)
		"master":
			return _pick_expert(choices, true)
	return -1


## 流派专精：候选里属于该流派的藏品，取稀有度最高的一张（同稀有度取靠前的，确定性）；没有则返回 -1（交给原有选法）
func _lane_best(items: Array, ingots := -1) -> int:
	var best := -1
	var best_r := -1
	for i in items.size():
		var c: Dictionary = items[i]
		if c.get("kind", "") != "relic" or c.get("sold", false):
			continue
		if ingots >= 0 and not g.shop_sys.can_buy(c):
			continue
		var r: Dictionary = g.RL.get(c.get("id", ""), {})
		if not r.get("lanes", []).has(lane):
			continue
		var rk: int = RARITY_RANK.get(r.get("rarity", ""), 0)
		if rk > best_r:
			best_r = rk
			best = i
	return best


## 商店：流派专精时先买买得起的该流派藏品；返回 -1 交给原有买法（从上往下买第一件买得起的）
func shop_pick() -> int:
	if lane == "" and profile == "master":
		return _shop_master()
	if lane == "":
		return -1
	return _lane_best(g.shop_items, g.ingots)


## 高手选卡：精英化 > 补齐编队（缺治疗 / 保护优先）> 技能 / 成长 > 全队被动（按局势）> 藏品稀有度
func _pick_expert(choices: Array, master := false) -> int:
	var classes: Array = g.squad.ops.map(func(o): return o.def.get("class", "") if "def" in o else "")
	var has_sustain := classes.has("医疗") or classes.has("重装")
	var hurting: bool = g.hp < g.max_hp * 0.6 or g.telemetry.low_hp_s > 20.0
	if master:
		m_lane = _master_lane(classes)
	var best := 0
	var best_s := -999.0
	for i in choices.size():
		var c: Dictionary = choices[i]
		var s := 1.0
		match c.get("kind", ""):
			"prog":
				s = 12.0 if int(c.get("elite", 0)) > 0 else 7.0
				if c.get("op", "") == g.ch.id:
					s += 0.5
			"skill":
				s = 6.5
			"recruit":
				s = 10.0 if g.squad.size() < 3 else 4.0
				var cls: String = c.get("cls", "")
				if not has_sustain and (cls == "医疗" or cls == "重装"):
					s += 3.0
				elif classes.has(cls):
					s -= 1.5
				var tier: String = g.Bal.sec("operators").get(c.get("id", ""), {}).get("tier", "A")
				s += {"S+": 1.0, "S": 0.6, "A+": 0.3}.get(tier, 0.0)
			"growth":
				var id: String = c.get("id", "")
				var early := {"squad_atk": 6.0, "sp": 5.8, "squad_aspd": 5.2, "squad_crit": 4.5, "squad_range": 3.5,
					"hp": 4.0, "regen": 3.5, "armor": 4.0, "dodge": 3.8, "wick": 3.0, "speed": 3.0, "pickup": 2.5}
				s = float(early.get(id, 3.0))
				if hurting and id in ["hp", "regen", "armor", "dodge", "wick"]:
					s += 2.5
				if master and g.hp < g.max_hp * 0.4 and id in ["hp", "regen"]:
					s += 3.0   # 熟练玩家：残血先拿回复
				if g.lamp < 40.0 and id == "wick":
					s += 2.0
			"weapon":
				s = 2.0 if has_sustain else 5.0
			"filler":
				s = 0.3
			"relic":
				var r: Dictionary = g.RL.get(c.get("id", ""), {})
				s = {"升华": 6.0, "核心": 5.0, "稀有": 4.0, "基础": 3.0, "遭诅古物": 0.5}.get(r.get("rarity", "基础"), 3.0)
				if g.t < 420.0 and r.get("tags", []).has("shield"):
					s += 1.0
				if master:
					s += _master_relic_bonus(r, hurting)
			_:
				s = 1.0
		s += rng.randf() * 0.2
		if s > best_s:
			best_s = s
			best = i
	return best


# =====================================================================
# master：熟练真人（2026-09-29，用来校准新难度）
# =====================================================================
const M_DIRS := 24
const DASH_LEN := 126.0          # game.gd：700 × 0.18 秒
var m_lane := ""                 # 当前认定的藏品流派
var m_zone_out := -1.0
var m_bins := PackedInt32Array()
var m_dbg: bool = Cfg.dev_args().has("--mdbg")   # 每 10 秒打印一行 MDBG：缺口 / 围猎占比、附近掉落物、冲刺次数
## 调参旋钮（仅测试）：--mt_<名>=<值> 覆盖，例如 --mt_keep=110
var m_tune := {"keep": 100.0, "keep_melee": 50.0, "gem": 0.35, "gem_cap": 5.0, "gem_r": 80.0, "pred": 0.1, "hunt_goal": 1.0, "boss_lo": 170.0, "boss_hi": 260.0, "boss_hp": 0.35}
var m_stat := {"frames": 0, "gap": 0, "hunt": 0, "gems": 0, "dash": 0, "next": 10.0}


## 走位：24 方向 × 3 步长打分（近战怪按速度外推 0.25 秒、弹幕外推到 0.6 秒）；被围时往最大缺口走；
## 躲不开时用冲刺无敌（0.18 秒冲刺 + 0.05 秒余量）：预警快结算、弹幕马上命中、贴身精英 / Boss、出圈都会冲
func _move_master(_dt: float) -> Vector2:
	var p: Vector2 = g.ppos
	var near: Array = []
	for j in g.enemies_sys.query(p, 400.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.get("chest", false) or float(e.get("dmg", 1.0)) <= 0.0:
			continue
		near.append(e)
	_prep_near(near)
	for i in near.size():
		var e2: Dictionary = near[i]
		var ai: String = str(e2.get("ai", ""))
		if ai != "ranged" and ai != "static":
			var to: Vector2 = p - e2.pos
			var l := to.length()
			if l > 1.0:
				_np[i] = e2.pos + to / l * minf(l * 0.5, float(e2.get("spd", 50.0)) * m_tune.pred)
	var bullets: Array = []
	for bl in g.ebullets:
		if bl.life > 0.0 and bl.pos.distance_to(p) < 380.0:
			bullets.append(bl)
	var melee := 0
	for o in g.squad.ops:
		if MELEE.has(o.def.get("class", "")):
			melee += 1
	keep = lerpf(m_tune.keep, m_tune.keep_melee, float(melee) / maxf(1.0, g.squad.size()))
	var goal := _expert_goal(p, near)
	var bg := _master_boss_goal(p)
	if bg != Vector2.INF:
		goal = bg
	var in_hunt: bool = g.hunt.active() and g.hunt.inside
	var gap_dir := Vector2.ZERO if in_hunt else _master_gap(p, near)
	if gap_dir != Vector2.ZERO:
		goal = gap_dir if goal == Vector2.ZERO else (goal * 0.4 + gap_dir).normalized()
	if in_hunt and m_tune.hunt_goal > 0.0:
		goal = _master_hunt_goal(p)
	# 经验 / 灯油 / 回复：候选点附近的掉落物加分（真人会顺路吸经验，不会只追最近的一颗）
	var gems := PackedVector2Array()
	for gm in g.gems:
		if gm.pos.distance_to(p) < 330.0:
			gems.append(gm.pos)
	var spd: float = g.speed
	var rings: Array = []
	for w in g.warns:
		if not w.done and str(w.get("act", "")) in ["pattern_ring", "pattern_fan"]:
			rings.append(w)
	var here := _score_point(p, near) + _master_bullets(p, Vector2.ZERO, 0.0, bullets) + _master_pattern(p, rings)
	var best_dir := Vector2.ZERO
	var best := here - (0.8 if here > -1.0 else 0.0)
	for k in M_DIRS:
		var d := Vector2.from_angle(TAU * k / M_DIRS)
		var s1 := _score_point(p + d * 60.0, near)
		var s := 0.45 * s1 + 0.35 * _score_point(p + d * 130.0, near) + 0.2 * _score_point(p + d * 200.0, near)
		s += _master_bullets(p, d, spd, bullets) + _master_pattern(p + d * 90.0, rings)
		if s1 > -1.5 and not gems.is_empty():
			var q := p + d * 100.0
			var nq := 0
			for gp in gems:
				if gp.distance_to(q) < m_tune.gem_r:
					nq += 1
			s += m_tune.gem * minf(float(nq), m_tune.gem_cap)
		if goal != Vector2.ZERO:
			s += 2.0 * d.dot(goal) * (1.0 if s1 > -1.5 else 0.35)
		s += 0.6 * d.dot(last_dir)
		if s > best:
			best = s
			best_dir = d
	if best_dir != Vector2.ZERO:
		last_dir = best_dir
	if m_dbg:
		m_stat.frames += 1
		m_stat.gap += int(gap_dir != Vector2.ZERO)
		m_stat.hunt += int(in_hunt)
		m_stat.gems += gems.size()
		if g.t >= m_stat.next:
			m_stat.next += 10.0
			print("MDBG t=%d lv=%d hp=%d gap=%.2f hunt=%.2f gems_near=%.0f dash=%d near=%d" % [g.t, g.level, g.hp, float(m_stat.gap) / m_stat.frames, float(m_stat.hunt) / m_stat.frames, float(m_stat.gems) / m_stat.frames, m_stat.dash, near.size()])
			m_stat.frames = 0; m_stat.gap = 0; m_stat.hunt = 0; m_stat.gems = 0; m_stat.dash = 0
	if g.dash_cd <= 0.0 and g.dash_t <= 0.0:
		var dd := _master_dash_dir(p, best_dir, spd, bullets, near, gap_dir)
		if dd != Vector2.ZERO:
			g.autotest_sys.want_dash = true
			if m_dbg:
				m_stat.dash += 1
			return dd
	return best_dir


## 弹幕：沿 d 走 0.1–0.6 秒后会不会和弹幕重叠；越早撞上扣得越多
func _master_bullets(p: Vector2, d: Vector2, spd: float, bullets: Array) -> float:
	var s := 0.0
	for bl in bullets:
		var r: float = float(bl.get("r", 6.0)) + 18.0
		for tau in [0.1, 0.2, 0.3, 0.45, 0.6]:
			if (p + d * spd * tau).distance_to(bl.pos + bl.vel * tau) < r:
				s -= 11.0 - tau * 8.0
				break
	return s


## Boss 环形弹幕：站到留缺口的方向；扇形弹幕：离开扇面（子弹飞得比预警画出的 140 像素远）
func _master_pattern(q: Vector2, rings: Array) -> float:
	var s := 0.0
	for w in rings:
		var dv: Vector2 = q - w.pos
		if dv.length() < 40.0:
			continue
		if w.act == "pattern_ring":
			if absf(angle_difference(dv.angle(), float(w.gap_ang))) < float(w.gap_half) * 0.8:
				s += 5.0
		elif dv.length() < 700.0 and absf(angle_difference(dv.angle(), float(w.ang))) < float(w.half) + 0.12:
			s -= 6.0
	return s


## 被围：190 像素内敌人按 16 个方位统计，占满 11 格以上就返回最长空缺的中间方向（没有空缺时返回敌人最少的方位）
func _master_gap(p: Vector2, near: Array) -> Vector2:
	m_bins.resize(16)
	m_bins.fill(0)
	for i in near.size():
		var dv: Vector2 = _np[i] - p
		if dv.length() - _nr[i] > 190.0:
			continue
		m_bins[posmod(floori(dv.angle() / TAU * 16.0), 16)] += 1
	var tight := false
	for i in near.size():
		if _np[i].distance_to(p) - _nr[i] < 70.0:
			tight = true
			break
	if not tight:
		return Vector2.ZERO
	var covered := 0
	for b in m_bins:
		if b > 0:
			covered += 1
	if covered < 11:
		return Vector2.ZERO
	var best_len := 0
	var best_mid := -1.0
	for st in 16:
		if m_bins[st] != 0 or m_bins[posmod(st - 1, 16)] == 0:
			continue
		var ln := 0
		while ln < 16 and m_bins[posmod(st + ln, 16)] == 0:
			ln += 1
		if ln > best_len:
			best_len = ln
			best_mid = st + ln * 0.5
	if best_mid < 0.0:
		var lo := 0
		for k in 16:
			if m_bins[k] < m_bins[lo]:
				lo = k
		best_mid = lo + 0.5
	return Vector2.from_angle(best_mid / 16.0 * TAU)


## 该不该冲刺：返回冲刺方向，零向量 = 不冲。落点在溟痕里、或往圈外更远处就不冲
func _master_dash_dir(p: Vector2, best_dir: Vector2, spd: float, bullets: Array, near: Array, gap_dir: Vector2) -> Vector2:
	var dir := best_dir if best_dir != Vector2.ZERO else (gap_dir if gap_dir != Vector2.ZERO else last_dir)
	var need := false
	# ① 预警 0.2 秒内结算且走不出去（必须冲刺的解读冲击也在这里）
	for w in g.warns:
		if w.done:
			continue
		var rem: float = float(w.dur) - float(w.t)
		if rem > 0.2 or not _in_warn(w, p, 12.0):
			continue
		if w.get("must_dash", false) or _in_warn(w, p + best_dir * spd * rem, 12.0):
			need = true
			break
	# ② 弹幕 0.12 秒内命中，沿选定方向走也躲不开
	if not need:
		for bl in bullets:
			var r: float = float(bl.get("r", 6.0)) + 14.0
			for tau in [0.04, 0.08, 0.12]:
				if (p + best_dir * spd * tau).distance_to(bl.pos + bl.vel * tau) < r:
					need = true
					break
			if need:
				break
	# ③ 精英 / Boss 贴身，或被围住且已有敌人贴身（朝缺口冲）
	if not need:
		for i in near.size():
			var gap: float = p.distance_to(near[i].pos) - _nr[i]
			if gap < 16.0 and (_nw[i] > 1.0 or gap_dir != Vector2.ZERO):
				need = true
				if gap_dir != Vector2.ZERO:
					dir = gap_dir
				break
	# ④ 出圈 0.3 秒以上：朝圈心冲
	if g.zone_state != 0 and p.distance_to(g.zone_c) > g.zone_r:
		if m_zone_out < 0.0:
			m_zone_out = g.t
		elif g.t - m_zone_out > 0.3:
			need = true
			dir = (g.zone_c - p).normalized()
	else:
		m_zone_out = -1.0
	if not need or dir == Vector2.ZERO:
		return Vector2.ZERO
	var land: Vector2 = p + dir.normalized() * DASH_LEN
	for m in g.mires:
		if g.combat.ground_d(land, m.pos) < float(m.r):
			return Vector2.ZERO
	if g.zone_state != 0 and land.distance_to(g.zone_c) > g.zone_r and land.distance_to(g.zone_c) > p.distance_to(g.zone_c):
		return Vector2.ZERO
	return dir.normalized()


## 认定流派：已拿藏品按流派计数 × 2，再加编队适配（近战干员算 A、远程算 E，G / H 通用各 +1）
func _master_lane(classes: Array) -> String:
	var sc := {"A": 0.0, "B": 0.0, "C": 0.0, "D": 0.0, "E": 0.0, "F": 0.0, "G": 1.0, "H": 1.0}
	for cls in classes:
		if MELEE.has(cls):
			sc.A += 1.5
		else:
			sc.E += 1.5
	for rid in g.relics:
		for ln in g.RL.get(str(rid), {}).get("lanes", []):
			if sc.has(ln):
				sc[ln] += 2.0
	var best := "G"
	for k in sc:
		if sc[k] > sc[best]:
			best = k
	return best


## 藏品加分：强度档（A +1.5 / C −0.5 / D −1）、认定流派 +2、受伤时生存类 +1.5
func _master_relic_bonus(r: Dictionary, hurting: bool) -> float:
	var s: float = {"A": 1.5, "B": 0.0, "C": -0.5, "D": -1.0}.get(r.get("tier", "B"), 0.0)
	if r.get("lanes", []).has(m_lane):
		s += 2.0
	if hurting and r.get("tags", []).has("survival"):
		s += 1.5
	return s


## 商店：买得起的藏品里挑分最高的一件（与三选一同一套分）；没有值得买的返回 -1 交给原有买法
func _shop_master() -> int:
	var classes: Array = g.squad.ops.map(func(o): return o.def.get("class", "") if "def" in o else "")
	m_lane = _master_lane(classes)
	var hurting: bool = g.hp < g.max_hp * 0.6
	var best := -1
	var best_s := 3.5
	for i in g.shop_items.size():
		var c: Dictionary = g.shop_items[i]
		if c.get("kind", "") != "relic" or c.get("sold", false) or not g.shop_sys.can_buy(c):
			continue
		var r: Dictionary = g.RL.get(c.get("id", ""), {})
		var s: float = {"升华": 6.0, "核心": 5.0, "稀有": 4.0, "基础": 3.0, "遭诅古物": 0.5}.get(r.get("rarity", "基础"), 3.0)
		s += _master_relic_bonus(r, hurting)
		if s > best_s:
			best_s = s
			best = i
	return best


## 围猎：圈上有倒下的海嗣就从那个缺口走出去（突围回血 + 灯火）；还没有缺口就贴近最近的圈上海嗣让干员打穿
func _master_hunt_goal(p: Vector2) -> Vector2:
	var h = g.hunt
	var best := INF
	var tgt := Vector2.INF
	for i in h.ring.size():
		var e: Dictionary = h.ring[i]
		var ap: Vector2 = h.anchors[i] if i < h.anchors.size() else e.pos
		if e.dead and p.distance_to(ap) < best:
			best = p.distance_to(ap)
			tgt = ap + (ap - h.c).normalized() * 80.0
	if tgt != Vector2.INF:
		return (tgt - p).normalized()
	best = INF
	for e in h.ring:
		if not e.dead and p.distance_to(e.pos) < best:
			best = p.distance_to(e.pos)
			tgt = e.pos
	if tgt == Vector2.INF or best < keep + 20.0:
		return Vector2.ZERO
	return (tgt - p).normalized()


## Boss 战站位：生命 35% 以上就按主控射程贴上去（近战主控 60–120，远程 170–260），不像 expert 那样一律站 200–320 外；
## 返回 Vector2.INF = 不管（没有 Boss / 残血 / 无敌）
func _master_boss_goal(p: Vector2) -> Vector2:
	if g.hp < g.max_hp * m_tune.boss_hp:
		return Vector2.INF
	var melee_lead: bool = MELEE.has(g.ch.cls) if g.ch != null else false
	var lo: float = 60.0 if melee_lead else m_tune.boss_lo
	var hi: float = 120.0 if melee_lead else m_tune.boss_hi
	for bb in g.bosses:
		if bb.dead or bb.get("invuln", false):
			continue
		var bd: float = bb.pos.distance_to(p) - float(bb.get("r", 30.0))
		if bd > hi:
			return (bb.pos - p).normalized()
		if bd < lo:
			return (p - bb.pos).normalized() * 0.8
		return Vector2.ZERO
	return Vector2.INF
