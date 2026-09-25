## 乌尔比安（近卫·撼地者，契约 v2.1，docs/26 第二批）：精英猎手。锚击砸身前一片（全部命中）；掷出带锁链的锚，自己顺着锁链弹射过去砸下。
## S1 必须接触：向最近精英（无则敌群最密处）掷锚，锚咬住后顺锁链弹射到锚点，落地砸击半径 90 内 ×1.7 并眩晕；
## S2 必须坚守（永久）：攻击 +40%、锚击范围 +30%、天赋层数上限 10 → 15；
## S3 必须开辟：掷锚到敌群最密处，弹射过去落地 r140 ×3 并眩晕 3 秒（精英 1.5、Boss 0.8），之后 8 秒锚击间隔 -30%。
## 天赋 血脉滋养：击杀精英 +1 层、Boss +3 层，每层攻击 +4%；编队里其他深海猎人（斯卡蒂、幽灵鲨）获得一半。
## 全部走现成挂点，不改 game.gd：弹射 = 在 update 里覆盖自身 pos（follow 之后执行），眩晕 = e.stun，层数走 stats.add(op:<id>)。
## 表现（2026-09-25 重做）：锚画成他手里那把深色钩锚（黑蓝锚身 + 一只大弯钩 + 蓝色刃光），锁链绷直；
## 掷出 → 咬地（顿帧、蓝色水花）→ 人沿锁链弹射（残影 + 速度线）→ 落地砸击。
## 可见成长（docs/25 §5.2）：N1 定点爆破：锚击 0.2 秒后第二道冲击环；N2 锁链回旋：每第 3 击锁链甩一整圈；
## N4 不容挣脱：必须接触落地时用锁链拽来 3 名敌人；N5 通路洞开：必须开辟从起点到锚点裂开一道通路，掀飞沿途敌人；
## 精二「血脉沸腾」：身上常亮血脉红纹，击杀精英后下一次锚击变为大爆破（红纹脉动提示）。
extends "res://scripts/characters/character.gd"

const STEEL := Color(0.55, 0.75, 0.95)
const CHAIN := Color(0.62, 0.68, 0.78)
const ABYSS := Color(0.1, 0.12, 0.2)        # 锚身：黑蓝
const EDGE := Color(0.4, 0.62, 1.1)         # 刃光：深海蓝
const WATER := Color(0.45, 0.78, 1.0)
const BLOOD := Color(1.0, 0.25, 0.3)        # 血脉红纹
const LEASH := 170.0
const HUNTERS := ["skadi", "specter_unchained"]

var cd := 0.5
var stacks := 0
var kept := false             # S2 必须坚守（永久）
var haste_t := 0.0            # S3 之后 8 秒锚击加速
## 锚：{kind, phase: "throw" / "zip", t, dur, from, to, start, trail}
## throw：锚从手里飞向 to；zip：锚咬在 to，人从 start 弹射到落点
var anchor: Dictionary = {}
# ---- 可见成长
var blast2_on := false        # N1 定点爆破
var whirl_on := false         # N2 锁链回旋
var drag_on := false          # N4 不容挣脱
var rift_on := false          # N5 通路洞开
var blood_on := false         # 精二 血脉沸腾
var blood_ready := false      # 已击杀精英：下一次锚击大爆破
var slam_n := 0               # 锚击计数（每第 3 击锁链回旋）
var delayed: Array = []       # 延时冲击 {t, c}
var launched: Array = []      # 通路洞开掀飞的敌人 {e, t, dur, h}


func _reach() -> float:
	return base("reach", 70.0) * stat(&"op_range") * (1.3 if kept else 1.0)


func _stack_cap() -> int:
	return int(base("stack_cap", 10.0)) + (5 if kept else 0)


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 28.0)
	return p if p != Vector2.INF else slot_pos


## 成长节点（data/characters/ulpianus.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"blast2":
			blast2_on = true
		"whirl":
			whirl_on = true
		"drag":
			drag_on = true
		"rift":
			rift_on = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		blood_on = true


func _slam_dmg() -> float:
	return base("atk", 42.0) * _dmg_bonus()


func update(dt: float) -> void:
	cd -= dt
	haste_t = maxf(0.0, haste_t - dt)
	_update_anchor(dt)
	_update_launched(dt)
	# 定点爆破：锚击后 0.2 秒的第二道冲击环
	for i in range(delayed.size() - 1, -1, -1):
		delayed[i].t -= dt
		if delayed[i].t <= 0.0:
			var dl: Dictionary = delayed[i]
			delayed.remove_at(i)
			_blast2(dl.c)
	if acting() or not anchor.is_empty():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		var aim := _skill_target(ready)
		start_skill(aim if aim != Vector2.INF else Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 40.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 1.5) / stat(&"op_aspd") * (0.7 if haste_t > 0.0 else 1.0)
			start_attack(ts[0].pos)


## 锚击：身前半径内全部敌人
func _release() -> void:
	var ts: Array = g._nearest(1, _reach() + 60.0, pos)
	var ang: float = facing_angle()
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var c: Vector2 = pos + Vector2.from_angle(ang) * _reach() * 0.55
	# 精二 血脉沸腾：击杀精英后的这一击变为大爆破（半径 160、×2.5）
	if blood_ready:
		blood_ready = false
		_blood_blast(c)
		return
	melee_hit("锚击", c, 0.0, PI, _reach(), _slam_dmg(), 90.0)
	# 抡锚弧光（Ninja Slash01 钢蓝重调色）+ 落地
	g._fx_sprite("fx_slash_heavy_steel", pos + Vector2(0, -16) + Vector2.from_angle(ang) * _reach() * 0.45, _reach() * 1.3 / 28.0, ang)
	_slam_fx(c, _reach(), 1.0)
	Sfx.op(id, "atk", 0.0, 1.0, 0.06)
	# 定点爆破：0.2 秒后同一落点再炸一道更大的冲击环
	if blast2_on:
		delayed.append({"t": base("blast2_delay", 0.2), "c": c})
	# 锁链回旋：每第 3 击抡着锁链甩一整圈
	slam_n += 1
	if whirl_on and slam_n % 3 == 0:
		_whirl()


## 定点爆破（档案：四爪巨锚「定点爆破」）：半径 100、锚击 50% 伤害
func _blast2(c: Vector2) -> void:
	var r: float = base("blast2_r", 100.0) * stat(&"op_range")
	area_hit("定点爆破", c, r, _slam_dmg() * base("blast2_mult", 0.5), 60.0)
	fx({"kind": "ring", "pos": c, "r": r, "r0": r * 0.4, "life": 0.3, "col": EDGE, "floor": true, "w": 4.0})
	fx({"kind": "ring", "pos": c, "r": r * 0.7, "r0": 6.0, "life": 0.22, "col": Color(1.3, 1.6, 2.2), "floor": true, "w": 2.0})
	fx({"kind": "glow", "pos": c + Vector2(0, -8), "r": 16.0, "life": 0.18, "col": Color(1.2, 1.5, 2.2), "alpha": 0.7})
	_splash(c, 5, 0.8)
	Sfx.play("boom", -12.0, 1.3, 0.1)


## 锁链回旋：以自身为中心半径 130、锚击 60% 伤害；锁链带着锚在腰高甩一整圈（whirl 粒子）
func _whirl() -> void:
	var r: float = base("whirl_r", 130.0) * stat(&"op_range")
	area_hit("锁链回旋", pos, r, _slam_dmg() * base("whirl_mult", 0.6), 140.0)
	fx({"kind": "whirl", "pos": pos, "r": r, "life": 0.32, "a0": g.rng.randf() * TAU, "dir": face})
	fx({"kind": "ring", "pos": pos, "r": r, "r0": r * 0.6, "life": 0.3, "col": CHAIN, "floor": true, "w": 2.0, "alpha": 0.6})


## 血脉沸腾：大爆破（半径 160、锚击 ×2.5），红色冲击 + 地裂
func _blood_blast(c: Vector2) -> void:
	var r: float = base("blood_r", 160.0) * stat(&"op_range")
	melee_hit("锚击", c, 0.0, PI, r, _slam_dmg() * base("blood_mult", 2.5), 220.0, 0.4, ["empowered"])
	g._fx_sprite("fx_slash_heavy_steel", pos + Vector2(0, -16) + (c - pos) * 0.8, _reach() * 1.5 / 28.0, (c - pos).angle(), false, false, Color(1.6, 0.6, 0.6))
	fx({"kind": "crack", "pos": c, "r": r * 0.8, "life": 0.6, "col": BLOOD, "floor": true, "n": 9})
	fx({"kind": "ring", "pos": c, "r": r, "r0": 20.0, "life": 0.4, "col": BLOOD, "floor": true, "w": 5.0})
	fx({"kind": "ring", "pos": c, "r": r * 0.65, "r0": 10.0, "life": 0.5, "col": STEEL, "floor": true, "w": 2.5})
	fx({"kind": "glow", "pos": c + Vector2(0, -12), "r": 34.0, "life": 0.3, "col": BLOOD, "alpha": 0.7})
	_splash(c, 10, 1.3)
	fx_sparks(c + Vector2(0, -10), BLOOD, 12, 260.0, 0.45, 3.0, 200.0)
	g.hitstop = maxf(g.hitstop, 0.08)
	Sfx.op(id, "big")


## 砸地：地裂 + 冲击环 + 深海蓝水珠（不用帧条水花：它前几帧是米黄色的尘团，和深海不搭）
func _slam_fx(c: Vector2, r: float, k: float) -> void:
	fx({"kind": "crack", "pos": c, "r": r * 0.9, "life": 0.4 * k, "col": STEEL, "floor": true, "n": 7})
	fx({"kind": "ring", "pos": c, "r": r, "r0": 10.0, "life": 0.3 * k, "col": STEEL, "floor": true, "w": 3.0})
	_splash(c, int(8 * k), 1.0 * k)
	fx_sparks(c + Vector2(0, -8), CHAIN, 6, 150.0, 0.35, 2.5, 220.0)


## 深海蓝水珠：向上迸开、带重力落回；落点一团蓝色水花（ansimuz water splash）
func _splash(c: Vector2, n: int, k: float) -> void:
	g._fx_sprite("fx_splash_blue", c + Vector2(0, 6), g.PX * clampf(0.8 * k, 0.8, 1.6), 0.0, false, true)
	for i in n:
		var a: float = -PI / 2.0 + g.rng.randf_range(-1.1, 1.1)
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-10, 10), -4), "vel": Vector2.from_angle(a) * g.rng.randf_range(90, 190) * k,
			"life": g.rng.randf_range(0.35, 0.5), "col": WATER, "sz": 2.0 if i % 2 == 0 else 1.5, "grav": 420.0})


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.15, "col": STEEL, "alpha": 0.5})


# ---------------------------------------------------------------- 技能

func _skill_target(i: int) -> Vector2:
	if i == 0:
		# 最近的精英；没有就敌群最密处
		var best: Dictionary = {}
		var bd := INF
		for j in g._query(pos, 420.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or not (e.elite or e.boss):
				continue
			var d: float = e.pos.distance_to(pos)
			if d < bd:
				bd = d
				best = e
		if not best.is_empty():
			return best.pos
	var c: Vector2 = g._densest_point(400.0, pos)
	if c == Vector2.INF:
		var ts: Array = g._nearest(1, 400.0, pos)
		return ts[0].pos if not ts.is_empty() else Vector2.INF
	return c


func _release_skill() -> void:
	match cur_skill:
		0, 2:
			var to := _skill_target(cur_skill)
			if to == Vector2.INF:
				sp[cur_skill] = sp_need(cur_skill) * 0.6   # 没目标：退回大半充能
				return
			anchor = {"kind": cur_skill, "phase": "throw", "t": 0.0, "dur": base("s1_throw" if cur_skill == 0 else "s3_throw", 0.16 if cur_skill == 0 else 0.22),
				"from": _hand(), "to": to, "trail": []}
		1:
			kept = true
			g.stats.add(&"op_atk", "add", 0.4, "ulpianus_kept", "op:" + id)
			g._sync_stats()
			_apply_stacks()
			g._show_banner("必须坚守：攻击与范围永久提升")
			fx({"kind": "ring", "pos": pos, "r": 90.0, "r0": 8.0, "life": 0.5, "col": STEEL, "floor": true})
			g._fx_sprite("fx_shield_amber", pos + Vector2(0, -20), g.PX * 1.4, 0.0, false, false, Color(0.7, 0.9, 1.2))


func skill_active_left(i: int) -> float:
	return haste_t if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return base("s3_haste", 8.0) if i == 2 else 1.0


func _hand() -> Vector2:
	return pos + Vector2(8.0 * face, -22)


func _update_anchor(dt: float) -> void:
	if anchor.is_empty():
		return
	anchor.t += dt
	var k: float = clampf(anchor.t / anchor.dur, 0.0, 1.0)
	if anchor.phase == "throw":
		anchor.trail.push_front(_anchor_pos(k))
		if anchor.trail.size() > 4:
			anchor.trail.pop_back()
		if k >= 1.0:
			_anchor_bite()
	else:
		# 弹射：先慢后快（k²），人沿锁链飞向锚点；途中留残影
		var kk: float = k * k
		pos = (anchor.start as Vector2).lerp(anchor.land, kk)
		face = signf(anchor.land.x - anchor.start.x) if absf(anchor.land.x - anchor.start.x) > 1.0 else face
		anchor.trail.push_front(pos)
		if anchor.trail.size() > 5:
			anchor.trail.pop_back()
		if k >= 1.0:
			_zip_land()
			anchor = {}


## 锚在飞行中的位置：近乎平直（10 像素弧度）
func _anchor_pos(k: float) -> Vector2:
	return (anchor.from as Vector2).lerp(anchor.to, k) + Vector2(0, -sin(k * PI) * 10.0)


## 锚咬地：顿帧 + 冲击环 + 水珠，转入弹射
func _anchor_bite() -> void:
	var to: Vector2 = anchor.to
	var dir: Vector2 = (to - pos).normalized() if to.distance_to(pos) > 1.0 else Vector2(face, 0)
	var big: bool = anchor.kind == 2
	g.hitstop = maxf(g.hitstop, 0.07 if big else 0.05)
	fx({"kind": "glow", "pos": to + Vector2(0, -6), "r": 18.0 if big else 14.0, "life": 0.12, "col": Color(1.4, 1.7, 2.3), "alpha": 0.8})
	fx({"kind": "ring", "pos": to, "r": 48.0 if big else 36.0, "r0": 6.0, "life": 0.22, "col": STEEL, "floor": true, "w": 3.0})
	_splash(to, 6, 0.8)
	for i in 6:
		var a: float = dir.angle() + g.rng.randf_range(-0.9, 0.9)
		fx({"kind": "spark", "pos": to + Vector2(0, -6), "vel": Vector2.from_angle(a) * g.rng.randf_range(160, 300), "life": 0.22, "col": CHAIN, "sz": 2.5})
	# 落点停在锚前一点（锚咬在敌人身上，人砸在它面前）
	var land: Vector2 = to - dir * 18.0
	anchor.phase = "zip"
	anchor.t = 0.0
	anchor.dur = clampf(pos.distance_to(land) / 1400.0, 0.08, 0.2)
	anchor.start = pos
	anchor.land = land
	anchor.trail = []
	melee_tgt = null


## 弹射落地：砸击
func _zip_land() -> void:
	var c: Vector2 = anchor.land
	if anchor.kind == 0:
		var r: float = base("s1_r", 90.0) * stat(&"op_range")
		var dmg: float = base("atk", 42.0) * base("s1_mult", 1.7) * _dmg_bonus() * skill_power()
		for j in g._query(c, r + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(c) > r + e.r:
				continue
			g._hit("掷锚")
			g._damage(e, dmg)
			if not e.dead:
				e.stun = maxf(e.stun, base("s1_stun", 0.6) * (0.5 if e.elite or e.boss else 1.0))
				if not e.boss:
					e.kb += (e.pos - c).normalized() * 50.0
		_slam_fx(c, r, 1.0)
		g.hitstop = maxf(g.hitstop, 0.06)
		Sfx.op(id, "atk", 2.0, 0.85)
		# 不容挣脱（原作 S1 把敌人拖过来）：锁链甩出去拽来附近至多 3 名敌人，拖到落点并造成掷锚 60% 伤害
		if drag_on:
			_drag_in(c, dmg * base("drag_mult", 0.6))
	else:
		# 必须开辟：落点 r140 ×3 + 眩晕
		var r3: float = base("s3_r", 140.0) * stat(&"op_range")
		var dmg3: float = base("atk", 42.0) * base("s3_mult", 3.0) * _dmg_bonus() * skill_power()
		for j in g._query(c, r3 + 30.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or e.pos.distance_to(c) > r3 + e.r:
				continue
			g._hit("必须开辟")
			g._damage(e, dmg3)
			if not e.dead:
				var st: float = base("s3_stun", 3.0) * (0.27 if e.boss else (0.5 if e.elite else 1.0))
				e.stun = maxf(e.stun, st)
				e.kb += (e.pos - c).normalized() * 60.0
		_slam_fx(c, r3, 1.6)
		_splash(c, 10, 1.3)
		haste_t = base("s3_haste", 8.0)
		g._fx_sprite("fx_circle_steel", c + Vector2(0, 4), g.PX * (r3 / 40.0))
		g._add_text(c + Vector2(0, -70), "必须开辟", STEEL, 18)
		g.hitstop = maxf(g.hitstop, 0.1)
		Sfx.op(id, "big")
		# 通路洞开：从起跳点到锚点裂开一道直线裂隙，沿途敌人被掀飞 0.8 秒并受到锚击 80% 伤害
		if rift_on:
			_open_rift(anchor.start, c)


## 不容挣脱：落点 200 内最近的至多 3 名（不含已在落点身边的）敌人被锁链拽过来
func _drag_in(c: Vector2, dmg: float) -> void:
	var cands: Array = g._nearest(12, base("drag_r", 200.0), c).filter(func(e): return e.pos.distance_to(c) > 36.0)
	for k in mini(int(base("drag_n", 3.0)), cands.size()):
		var e: Dictionary = cands[k]
		g._hit("不容挣脱")
		g._damage(e, dmg)
		fx({"kind": "chain", "pos": c + Vector2(0, -12), "to": e.pos + Vector2(0, -e.r * 0.5), "life": 0.3})
		fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 10.0, "life": 0.2, "col": STEEL, "alpha": 0.6})
		if e.dead or e.boss:
			continue
		# 击退速度按拖拽距离换算（kb 以 900/s² 衰减：位移 = v² / 1800），拖到落点身前 24 处
		var dist: float = maxf(0.0, e.pos.distance_to(c) - 24.0)
		var v: float = minf(sqrt(1800.0 * dist), 620.0) * (0.5 if e.elite else 1.0)
		e.kb += (c - e.pos).normalized() * v
		e.stun = maxf(e.stun, 0.3)


## 通路洞开：裂隙贴地停留 0.8 秒（地面残留），沿线敌人掀飞
func _open_rift(a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < 8.0:
		return
	var dmg: float = _slam_dmg() * base("rift_mult", 0.8) * skill_power()
	var w: float = base("rift_w", 26.0)
	var d: Vector2 = (b - a).normalized()
	var L: float = a.distance_to(b)
	for j in g._query((a + b) * 0.5, L * 0.5 + w + 30.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var rel: Vector2 = e.pos - a
		var along: float = rel.dot(d)
		if along < -e.r or along > L + e.r or absf(rel.cross(d)) > w + e.r:
			continue
		g._hit("通路洞开")
		g._damage(e, dmg)
		_launch(e, base("rift_air", 0.8), 30.0)
	fx({"kind": "rift", "pos": a, "to": b, "life": 0.8, "floor": true, "seed": g.rng.randf() * 100.0})
	for k in 5:
		var p: Vector2 = a.lerp(b, (k + 0.5) / 5.0)
		fx_sparks(p + Vector2(0, -4), EDGE, 3, 160.0, 0.35, 2.5, 260.0)


## 掀飞：眩晕 + 一条 sin 弧线的 air 高度（game.gd 按 e.air 抬高绘制；与艾丽妮浮空同法）
func _launch(e: Dictionary, dur: float, h: float) -> void:
	if e.dead or e.boss:
		return
	if e.elite:
		dur *= 0.5
	e.stun = maxf(e.stun, dur)
	for l in launched:
		if is_same(l.e, e):
			l.t = 0.0
			l.dur = maxf(l.dur, dur)
			return
	launched.append({"e": e, "t": 0.0, "dur": dur, "h": h})


func _update_launched(dt: float) -> void:
	if launched.is_empty():
		return
	for l in launched:
		l.t += dt
		var e: Dictionary = l.e
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		e.air = 0.0 if e.dead or k >= 1.0 else sin(k * PI) * l.h
		if not e.dead:
			e.kb = Vector2.ZERO
	launched = launched.filter(func(l): return l.t < l.dur and not l.e.dead)


# ---------------------------------------------------------------- 天赋：血脉滋养

func on_kill(e: Dictionary) -> void:
	if elite < 1:
		return
	var add := 0
	if e.boss:
		add = 3
	elif e.elite:
		add = 1
	# 精二 血脉沸腾：击杀精英 / Boss 后下一次锚击大爆破
	if add > 0 and blood_on and not blood_ready:
		blood_ready = true
		g._add_text(pos + Vector2(0, -78), "血脉沸腾", BLOOD, 14)
		fx({"kind": "ring", "pos": pos, "r": 50.0, "r0": 10.0, "life": 0.35, "col": BLOOD, "floor": true, "w": 3.0})
	if add <= 0 or stacks >= _stack_cap():
		return
	stacks = mini(_stack_cap(), stacks + add)
	_apply_stacks()
	g._add_text(pos + Vector2(0, -60), "血脉 ×%d" % stacks, STEEL, 13)
	fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 16.0, "life": 0.3, "col": Color(0.9, 0.3, 0.35), "alpha": 0.5})


func _apply_stacks() -> void:
	g.stats.remove_source("ulpianus_blood")
	var v: float = stacks * base("stack_atk", 0.04)
	if v > 0.0:
		g.stats.add(&"op_atk", "add", v, "ulpianus_blood", "op:" + id)
		for o in g.squad.ops:
			if o != self and o.id in HUNTERS:
				g.stats.add(&"op_atk", "add", v * 0.5, "ulpianus_blood", "op:" + o.id)
	g._sync_stats()


# ---------------------------------------------------------------- 绘制

## 锁链：暗描边 + 链节交替（掷锚、回旋、拽敌共用）
func _draw_chain(a: Vector2, b: Vector2, al: float) -> void:
	g.draw_line(a, b, Color(0.04, 0.05, 0.08, 0.75 * al), 5.0)
	g.draw_line(a, b, Color(CHAIN.r, CHAIN.g, CHAIN.b, 0.95 * al), 2.5)
	var links: int = clampi(int(a.distance_to(b) / 10.0), 1, 50)
	for i in links:
		var q: Vector2 = a.lerp(b, float(i) / links)
		if i % 2 == 0:
			g.draw_circle(q, 2.6, Color(CHAIN.r * 0.7, CHAIN.g * 0.7, CHAIN.b * 0.75, al))
		else:
			g.draw_circle(q, 1.3, Color(1.1, 1.2, 1.35, al))


## 自定义粒子：whirl 锁链回旋 / chain 拽敌锁链 / rift 通路裂隙
func _draw_pfx(f: Dictionary, a: float) -> bool:
	match f.kind:
		"whirl":
			# 锁链带着锚在腰高甩一整圈（贴地椭圆），锚头后拖一段渐隐的回旋轨迹
			var u: float = 1.0 - a
			var head: float = f.a0 + f.dir * TAU * (1.0 - (1.0 - u) * (1.0 - u))
			var c: Vector2 = f.pos + Vector2(0, -14)
			var R: float = f.r * 0.85
			var trail := PackedVector2Array()
			for i in 16:
				var an: float = head - f.dir * 2.2 * float(i) / 15.0
				trail.append(c + Vector2(cos(an) * R, sin(an) * R * 0.55))
			for i in 15:
				var al: float = (1.0 - float(i) / 15.0) * minf(1.0, a * 2.0)
				g.draw_line(trail[i], trail[i + 1], Color(EDGE.r * 1.4, EDGE.g * 1.4, EDGE.b * 1.4, 0.7 * al), 6.0 * (1.0 - float(i) / 15.0) + 1.0)
			var hp: Vector2 = trail[0]
			_draw_chain(f.pos + Vector2(0, -22), hp, minf(1.0, a * 2.0))
			_draw_anchor(hp, Vector2.from_angle(head + f.dir * PI * 0.5), minf(1.0, a * 2.0))
			return true
		"chain":
			# 前 40% 锁链甩出去，之后收回（链头从敌人处拉回落点）
			var u2: float = 1.0 - a
			var tip: Vector2 = (f.pos as Vector2).lerp(f.to, minf(1.0, u2 / 0.4)) if u2 < 0.4 else (f.to as Vector2).lerp(f.pos, (u2 - 0.4) / 0.6)
			_draw_chain(f.pos, tip, 1.0)
			g.draw_circle(tip, 4.0, Color(EDGE.r * 1.5, EDGE.g * 1.5, EDGE.b * 1.5, 0.9))
			return true
		"rift":
			# 通路裂隙：锯齿状深色裂缝（两头细、中间宽），裂缝芯一道深海蓝光，后半程淡出
			var A: Vector2 = f.pos
			var B: Vector2 = f.to
			var L: float = A.distance_to(B)
			var d: Vector2 = (B - A) / maxf(1.0, L)
			var n: Vector2 = d.orthogonal()
			var m: int = clampi(int(L / 14.0), 3, 40)
			var al2: float = minf(1.0, a * 2.0)
			var prev: Vector2 = A
			for i in range(1, m + 1):
				var t: float = float(i) / m
				var p: Vector2 = A + d * L * t + n * (sin(f.seed + i * 1.7) * 5.0 if i < m else 0.0)
				var w: float = 2.0 + 5.0 * sin(t * PI)
				g.draw_line(prev, p, Color(0.04, 0.03, 0.05, 0.9 * al2), w)
				g.draw_line(prev, p, Color(EDGE.r * 1.6, EDGE.g * 1.6, EDGE.b * 1.8, 0.8 * clampf((a - 0.3) * 2.0, 0.0, 1.0)), maxf(1.0, w * 0.35))
				prev = p
			return true
	return false


## 精二 血脉沸腾：身上常亮的血脉红纹（躯干几道分叉红线，缓慢呼吸）；大爆破就绪时脉动加快、加亮并带一圈红光
func _draw_veins() -> void:
	var ready: bool = blood_ready
	var pul: float = 0.5 + 0.5 * sin(g.t * (9.0 if ready else 2.5))
	var al: float = (0.55 + 0.45 * pul) if ready else (0.35 + 0.25 * pul)
	var c := Color(BLOOD.r * 1.8, BLOOD.g * 1.4, BLOOD.b * 1.4, al)
	var o: Vector2 = pos + Vector2(0, -44)
	var sx: float = face
	var veins := [
		[Vector2(0, 0), Vector2(-3, 8), Vector2(-7, 14), Vector2(-9, 22)],
		[Vector2(0, 0), Vector2(4, 7), Vector2(6, 15), Vector2(10, 20)],
		[Vector2(0, 0), Vector2(2, -6), Vector2(-2, -12), Vector2(1, -17)],
		[Vector2(-3, 8), Vector2(-10, 6), Vector2(-14, 9)],
		[Vector2(4, 7), Vector2(11, 3), Vector2(15, 5)],
	]
	for v in veins:
		var pts := PackedVector2Array()
		for q in v:
			pts.append(o + Vector2(q.x * sx, q.y))
		g.draw_polyline(pts, Color(0.2, 0.0, 0.02, al * 0.6), 3.0)
		g.draw_polyline(pts, c, 1.5)
	g.draw_circle(o, 3.0 + pul, Color(BLOOD.r * 2.0, BLOOD.g * 1.5, BLOOD.b * 1.5, al))
	if ready:
		g.draw_arc(pos + Vector2(0, -34), 28.0 + 4.0 * pul, 0.0, TAU, 32, Color(BLOOD.r * 1.6, BLOOD.g, BLOOD.b, 0.5 * pul + 0.2), 2.5)
		g.draw_circle(pos + Vector2(0, -34), 30.0, Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.08 + 0.08 * pul))


## 脚下：精二常驻的淡红血脉光环（就绪时更亮）
func draw_auras() -> void:
	if not blood_on or pos == Vector2.INF:
		return
	var pul: float = 0.5 + 0.5 * sin(g.t * (9.0 if blood_ready else 2.5))
	g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
	g.draw_circle(Vector2.ZERO, 30.0, Color(BLOOD.r, BLOOD.g, BLOOD.b, (0.12 if blood_ready else 0.06) + 0.05 * pul))
	g.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(BLOOD.r * 1.5, BLOOD.g, BLOOD.b, (0.6 if blood_ready else 0.3) * (0.6 + 0.4 * pul)), 2.0)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	if blood_on and pos != Vector2.INF:
		_draw_veins()
	if anchor.is_empty():
		return
	var k: float = clampf(anchor.t / anchor.dur, 0.0, 1.0)
	var hand: Vector2 = _hand()
	var throwing: bool = anchor.phase == "throw"
	var p: Vector2 = _anchor_pos(k) if throwing else (anchor.to as Vector2) + Vector2(0, -6)
	var d: Vector2 = ((anchor.to as Vector2) - (anchor.from as Vector2)).normalized()
	# 弹射中：人身后的残影与速度线
	if not throwing:
		var tr: Array = anchor.trail
		var mv_d: Vector2 = ((anchor.land as Vector2) - (anchor.start as Vector2)).normalized()
		for i in range(tr.size() - 1, 0, -1):
			draw_body_at(tr[i], face < 0.0, Color(EDGE.r, EDGE.g, EDGE.b, 0.35 * (1.0 - float(i) / tr.size())))
		for s in 3:
			var off: Vector2 = mv_d.orthogonal() * (s - 1) * 10.0 + Vector2(0, -20)
			g.draw_line(pos - mv_d * 16.0 + off, pos - mv_d * (56.0 + s * 14.0) + off, Color(1.3, 1.5, 1.8, 0.4), 1.5)
	# 锁链：绷直，暗描边 + 链节交替
	g.draw_line(hand, p, Color(0.04, 0.05, 0.08, 0.75), 5.0)
	g.draw_line(hand, p, Color(CHAIN.r, CHAIN.g, CHAIN.b, 0.95), 2.5)
	var links: int = clampi(int(hand.distance_to(p) / 10.0), 1, 50)
	for i in links:
		var q: Vector2 = hand.lerp(p, float(i) / links)
		if i % 2 == 0:
			g.draw_circle(q, 2.6, Color(CHAIN.r * 0.7, CHAIN.g * 0.7, CHAIN.b * 0.75))
		else:
			g.draw_circle(q, 1.3, Color(1.1, 1.2, 1.35))
	# 飞行中：锚的残影 + 速度线
	if throwing:
		var tr2: Array = anchor.trail
		for i in range(tr2.size() - 1, 0, -1):
			_draw_anchor(tr2[i], d, 0.3 * (1.0 - float(i) / tr2.size()))
		for s in 3:
			var off2: Vector2 = d.orthogonal() * (s - 1) * 9.0
			g.draw_line(p - d * 24.0 + off2, p - d * (58.0 + s * 12.0) + off2, Color(1.3, 1.5, 1.8, 0.35), 1.5)
	_draw_anchor(p, d, 1.0)


## 他手里那把钩锚：黑蓝锚身（长杆）+ 一只大弯钩向后弯 + 一根短倒刺；刃口一道深海蓝光
## （程序画的过渡版；Codex 出 proj_ulpianus_anchor 帧条后换成贴图，见 docs/30）
func _draw_anchor(p: Vector2, d: Vector2, a: float) -> void:
	if g.tex.get("proj_ulpianus_anchor") != null:
		# Codex 四爪锚（朝右、左端小环接链，两帧刃光）
		g._spr_rot("proj_ulpianus_anchor", int(g.t * 10.0) % 2, p, d.angle(), g.PX * 0.8, Color(1, 1, 1, a))
		return
	var n: Vector2 = d.orthogonal()
	var outline := Color(0.02, 0.03, 0.06, 0.85 * a)
	var body := Color(ABYSS.r * 1.6, ABYSS.g * 1.6, ABYSS.b * 1.6, a)
	var edge := Color(EDGE.r * 1.3, EDGE.g * 1.3, EDGE.b * 1.3, a)
	var head: Vector2 = p + d * 12.0
	var tail: Vector2 = p - d * 18.0
	# 锚杆
	g.draw_line(tail, head, outline, 8.0)
	g.draw_line(tail, head, body, 5.0)
	# 大弯钩：从锚头朝一侧向后弯出
	var hook := PackedVector2Array()
	for i in 8:
		var u: float = float(i) / 7.0
		var ang: float = lerpf(0.0, 2.4, u)
		hook.append(head + n * sin(ang) * 15.0 - d * (1.0 - cos(ang)) * 11.0)
	g.draw_polyline(hook, outline, 9.0)
	g.draw_polyline(hook, body, 5.5)
	g.draw_polyline(hook.slice(0, 7), edge, 1.5)
	g.draw_circle(hook[hook.size() - 1], 2.5, edge)
	# 另一侧的短倒刺
	g.draw_line(head - d * 2.0, head - d * 9.0 - n * 7.0, outline, 6.0)
	g.draw_line(head - d * 2.0, head - d * 9.0 - n * 7.0, body, 3.0)
	# 锚头尖 + 尾环
	g.draw_colored_polygon(PackedVector2Array([head + d * 7.0, head + n * 3.0, head - n * 3.0]), body)
	g.draw_line(head, head + d * 6.0, edge, 1.5)
	g.draw_arc(tail - d * 3.0, 3.5, 0.0, TAU, 12, Color(CHAIN.r, CHAIN.g, CHAIN.b, a), 2.0)


func status_items() -> Array:
	var out: Array = []
	if stacks > 0:
		out.append(["血脉 ×%d" % stacks, Color(0.9, 0.4, 0.45)])
	if haste_t > 0.0:
		out.append(["开辟", STEEL])
	if blood_ready:
		out.append(["血脉沸腾", BLOOD])
	return out


func stats_rows() -> Array:
	return [["血脉层数", "%d / %d" % [stacks, _stack_cap()]]]
