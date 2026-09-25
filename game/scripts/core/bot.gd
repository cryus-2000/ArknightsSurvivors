extends RefCounted
## 平衡测试机器人（docs/29）：四档玩家画像 + 统一的局内指标采集。
## 只在 `--balance` 下由 game.gd 创建；`--bot=afk|bad|normal|expert` 选档，缺省 normal（= 原有机器人，便于和旧基线对比）。
##
##   afk     挂机：原地不动，只靠干员自动攻击；选卡随机。            → 下限：什么都不做能活多久
##   bad     手残：随机乱走，看到危险只有 30% 概率、延迟 0.4 秒才躲；选卡随机。
##   normal  普通：躲预警 / 溟痕 / 弹幕、保持距离、捡东西（原 _bot_move）；选卡按 balance.json bot 权重。
##   expert  高手：每帧对 16 个方向打分找空地、持续绕圈风筝、提前躲预警；选卡按编队缺口与局势打分。
##
## 所有随机都走自己的 RandomNumberGenerator（按 --seed 派生），不碰全局随机流，同 seed 可复现性不变差。

const PROFILES := ["afk", "bad", "normal", "expert"]
const SAMPLE_EVERY := 30.0      # 曲线采样间隔（秒）

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

# ---- 指标
var sample_next := 0.0          # 下一个采样时间点（按局内时间对齐到 0 / 30 / 60 …）
var curve: Array = []           # 每 30 秒：{t, hp, lamp, lv, kills, squad, taken}
var low_hp_s := 0.0             # 生命 < 35% 的累计秒数
var dark_s := 0.0               # 灯火熄灭的累计秒数
var dark_dmg := 0.0             # 熄灯每秒 3 点的持续掉血（不进 dmg_log，单独记）
var hits := 0                   # 受击次数
var taken_last := 0.0
var taken_window := 0.0         # 当前采样窗口内的承伤
var last_src := ""              # 最近一次掉血的来源（死因）
var last_log: Dictionary = {}
var boss_seen: Dictionary = {}  # instance_id -> {type, t0, t1}
var elite_t: Dictionary = {}    # "<op>:<elite>" -> 秒
var recruit_t: Array = []       # 每名干员入队时间
var squad_n := 0
var dist_moved := 0.0
var last_pos := Vector2.ZERO
var still_s := 0.0              # 站着不动的累计秒数


func _init(game, p: String, seed_v: int) -> void:
	g = game
	profile = p if p in PROFILES else "normal"
	rng.seed = hash("bot:%s:%d" % [profile, seed_v])


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
	return g._bot_move()


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
		return g._bot_move()
	# 缩圈外会被烧死：手残玩家也知道往圈里走，但慢半拍
	if g.zone_state != 0 and g.ppos.distance_to(g.zone_c) > g.zone_r - 40.0:
		return (g.zone_c - g.ppos).normalized()
	return wander_dir


## 高手：16 个方向 × 两个步长打分，挑最安全又有收益的方向；弹幕按 0.15/0.3/0.45 秒后的位置预判；
## 带动量，自然形成绕圈风筝；附近危险时降低捡东西 / 贴 Boss 的欲望
func _move_expert() -> Vector2:
	var p: Vector2 = g.ppos
	var near: Array = []
	for j in g._query(p, 380.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.get("chest", false) or float(e.get("dmg", 1.0)) <= 0.0:
			continue
		near.append(e)
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


## 一个位置的安全分（越高越安全）：敌人距离、预警、溟痕、弹幕、缩圈
func _score_point(q: Vector2, near: Array) -> float:
	var s := 0.0
	for e in near:
		var dd: float = q.distance_to(e.pos) - float(e.r)
		var w: float = 3.0 if (e.elite or e.boss) else 1.0
		if e.get("ai", "") == "ranged" and not e.boss:
			# 远程怪：待在射程外沿
			if dd < float(e.get("range", 200.0)) + 10.0:
				s -= 0.6
		var fast: float = 1.0 + clampf((float(e.get("spd", 50.0)) - 50.0) / 60.0, 0.0, 1.0)   # 快的怪要留更大余量
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
		if q.distance_to(m.pos) < float(m.r) + 26.0:
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
		if e.get("chest", false) and not e.dead and e.pos.distance_to(p) < 450.0:
			return (e.pos - p).normalized()
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
	return q.distance_to(w.pos) < float(w.get("r", 60.0)) + pad


func _in_danger(q: Vector2, pad: float) -> bool:
	for wv in g.warns:
		if not wv.done and _in_warn(wv, q, pad):
			return true
	for m in g.mires:
		if q.distance_to(m.pos) < float(m.r) + pad:
			return true
	for j in g._query(q, 60.0):
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
	match profile:
		"afk", "bad":
			return rng.randi() % choices.size()
		"expert":
			return _pick_expert(choices)
	return -1


## 高手选卡：精英化 > 补齐编队（缺治疗 / 保护优先）> 技能 / 成长 > 全队被动（按局势）> 藏品稀有度
func _pick_expert(choices: Array) -> int:
	var classes: Array = g.squad.ops.map(func(o): return o.def.get("class", "") if "def" in o else "")
	var has_sustain := classes.has("医疗") or classes.has("重装")
	var hurting: bool = g.hp < g.max_hp * 0.6 or low_hp_s > 20.0
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
			_:
				s = 1.0
		s += rng.randf() * 0.2
		if s > best_s:
			best_s = s
			best = i
	return best


# =====================================================================
# 指标采集（每个模拟步调用一次）
# =====================================================================
func tick(dt: float) -> void:
	var t: float = g.t
	if last_pos == Vector2.ZERO:
		last_pos = g.ppos
	var step: float = g.ppos.distance_to(last_pos)
	dist_moved += step
	if step < 0.5:
		still_s += dt
	last_pos = g.ppos
	if g.hp < g.max_hp * 0.35:
		low_hp_s += dt
	if g.lamp <= 0.0:
		dark_s += dt
		dark_dmg += 3.0 * dt
		if g.hp <= 3.0 * dt * 2.0:
			last_src = "dark"
	# 承伤：比较 dmg_log 的增量，记录受击次数与最近的来源
	var tot := 0.0
	var inc_best := 0.0
	for k in g.dmg_log:
		var v: float = g.dmg_log[k]
		tot += v
		var inc: float = v - float(last_log.get(k, 0.0))
		if inc > inc_best:
			inc_best = inc
			last_src = k
		last_log[k] = v
	if tot > taken_last + 0.01:
		hits += 1
		taken_window += tot - taken_last
	taken_last = tot
	# Boss 出现 / 击杀时间
	for b in g.bosses:
		var key := str(b.get("id", b.type))
		if not boss_seen.has(key):
			boss_seen[key] = {"type": b.type, "t0": int(t), "t1": -1}
		elif b.dead and boss_seen[key].t1 < 0:
			boss_seen[key].t1 = int(t)
	# 精英化 / 入队时间
	for o in g.squad.ops:
		var ek := "%s:%d" % [o.id, o.elite]
		if o.elite > 0 and not elite_t.has(ek):
			elite_t[ek] = int(t)
	if g.squad.size() > squad_n:
		if squad_n > 0:
			recruit_t.append(int(t))
		squad_n = g.squad.size()
	if t >= sample_next:
		sample_next += SAMPLE_EVERY
		curve.append({"t": int(t), "hp": int(100.0 * g.hp / maxf(1.0, g.max_hp)), "lamp": int(g.lamp), "lv": g.level,
			"kills": g.kills, "squad": g.squad.size(), "taken": int(taken_window), "enemies": g.enemies.size()})
		taken_window = 0.0


func report() -> Dictionary:
	var t: float = maxf(1.0, g.t)
	return {"profile": profile, "hits": hits, "hits_pm": snappedf(hits / t * 60.0, 0.1), "taken": int(taken_last),
		"taken_pm": int(taken_last / t * 60.0), "low_hp_s": int(low_hp_s), "dark_s": int(dark_s), "dark_dmg": int(dark_dmg), "death_src": last_src,
		"moved_pm": int(dist_moved / t * 60.0), "still_pct": int(100.0 * still_s / t),
		"bosses": boss_seen.values(), "elite_t": elite_t, "recruit_t": recruit_t, "curve": curve}
