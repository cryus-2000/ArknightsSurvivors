## 归溟幽灵鲨（特种·傀儡师，契约 v2.1，docs/26 第二批）：危机爆发 + 低灯火。贴身 360° 环斩，博士越危险她越狠。
## S1 求生之技：8 秒攻击 +（40% + 博士已损失生命%）；
## S2 求生之渴：10 秒攻速 +60%、攻击 +40%，期间博士生命不会低于 1；结束时本体倒下，原地留下替身 12 秒后归队；
## S3 求生之压：12 秒环斩间隔 ×1.6，但每斩 ×3.2、范围 +50%，对生命 <50% 的敌人再 ×1.5。
## 天赋 拥抱自我：替身每秒对周围 120 内敌人法伤并减速；灯火 <30「昏暗」时她的伤害 +25%。
## 博士不死通过 prevent_death() 供 game.gd 询问（同 dmg_taken_mult 模式）；替身是不动的附属实体（extra_bodies）。
extends "res://scripts/characters/character.gd"

const GHOST := Color(0.75, 0.85, 0.95)
const RED := Color(0.9, 0.3, 0.4)
const LEASH := 150.0

var cd := 0.4
var s1_t := 0.0
var s2_t := 0.0
var s3_t := 0.0
var doll_t := 0.0             # 替身剩余（本体离场）
var doll_pos := Vector2.INF
var doll_tick := 0.0
var doll_at := 0.0
var aegir := false            # 自定义节点「艾格尼之深」已选
var hunters_applied := 0      # 已计入的深海猎人数


func _reach() -> float:
	return base("reach", 75.0) * stat(&"op_range") * (base("s3_reach", 1.5) if s3_t > 0.0 else 1.0)


func away() -> bool:
	return doll_t > 0.0


func follow_target(slot_pos: Vector2) -> Vector2:
	if away():
		return slot_pos
	var p := melee_spot(LEASH, 26.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	s1_t = maxf(0.0, s1_t - dt)
	s3_t = maxf(0.0, s3_t - dt)
	if s2_t > 0.0:
		s2_t -= dt
		if s2_t <= 0.0:
			_fall()
	_update_doll(dt)
	_update_aegir()
	if away() or acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		start_skill(Vector2.INF, ready)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 1.2) / stat(&"op_aspd") / (1.0 + base("s2_aspd", 0.6) if s2_t > 0.0 else 1.0) * (base("s3_cd_mult", 1.6) if s3_t > 0.0 else 1.0)
			start_attack(ts[0].pos)


func _atk_mult() -> float:
	var m := 1.0
	if s1_t > 0.0:
		m *= 1.0 + base("s1_atk", 0.4) + clampf(1.0 - g.hp / g.max_hp, 0.0, 1.0)
	if s2_t > 0.0:
		m *= 1.0 + base("s2_atk", 0.4)
	if s3_t > 0.0:
		m *= base("s3_mult", 3.2)
	if elite >= 1 and g.lamp < 30.0:
		m *= 1.0 + base("dark_bonus", 0.25)
	return m


## 环斩：贴身 360°
func _release() -> void:
	var r := _reach()
	var dmg: float = base("atk", 30.0) * _dmg_bonus() * _atk_mult() * (skill_power() if (s1_t > 0.0 or s2_t > 0.0 or s3_t > 0.0) else 1.0)
	var hits: Array = g._arc_hit(pos + Vector2(0, -10), 0.0, PI, r)
	for e in hits:
		var d: float = dmg
		if s3_t > 0.0 and e.hp < e.maxhp * 0.5:
			d *= base("s3_low_mult", 1.5)
		g._hit("锯刃")
		g._damage(e, d)
		if not e.dead and not e.boss:
			e.kb += (e.pos - pos).normalized() * 70.0
		_hit_fx(e, pos)
	if not g._fx_sprite("fx_slash_circle_blood" if s3_t > 0.0 else "fx_slash_circle_ghost", pos + Vector2(0, -14), r * 2.0 / 56.0, 0.0):
		g._slash_fx(pos + Vector2(0, -14), 0.0, PI, r, GHOST, "slash", 0.22)
	for k in 6:
		var a: float = g.rng.randf() * TAU
		fx({"kind": "shard", "pos": pos + Vector2(cos(a), sin(a) * 0.6) * r * 0.7 + Vector2(0, -10), "vel": Vector2(cos(a), sin(a)) * 90.0, "life": 0.3, "col": GHOST, "sz": 5.0, "ang": a, "spin": 12.0})
	# 求生之压期间：更响、更低沉
	Sfx.op(id, "atk", 4.0 if s3_t > 0.0 else 0.0, 0.8 if s3_t > 0.0 else 1.0, 0.06)


func _hit_fx(e: Dictionary, _origin: Vector2) -> void:
	fx({"kind": "glow", "pos": e.pos + Vector2(0, -e.r * 0.5), "r": 9.0, "life": 0.15, "col": GHOST if s3_t <= 0.0 else RED, "alpha": 0.5})


# ---------------------------------------------------------------- 技能

func _release_skill() -> void:
	match cur_skill:
		0:
			s1_t = base("s1_dur", 8.0)
			g._add_text(pos + Vector2(0, -60), "求生之技", GHOST, 15)
		1:
			s2_t = base("s2_dur", 10.0)
			g._show_banner("求生之渴：博士暂不会倒下")
		2:
			s3_t = base("s3_dur", 12.0)
			g._show_banner("求生之压")
	fx({"kind": "ring", "pos": pos, "r": _reach(), "r0": 8.0, "life": 0.45, "col": GHOST if cur_skill < 2 else RED, "floor": true})
	g._fx_sprite("fx_circle_ghost", pos + Vector2(0, 4), g.PX * 1.8)
	g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -24), "life": 0.5, "max": 0.5, "col": GHOST if cur_skill < 2 else RED})


func skill_active_left(i: int) -> float:
	match i:
		0: return s1_t
		1: return s2_t
		2: return s3_t
	return 0.0


func skill_active_dur(i: int) -> float:
	return [base("s1_dur", 8.0), base("s2_dur", 10.0), base("s3_dur", 12.0)][i]


## game.gd 询问：S2 期间博士不会倒下
func prevent_death() -> bool:
	return s2_t > 0.0


## S2 结束：倒下，原地留下替身
func _fall() -> void:
	doll_pos = pos
	doll_t = base("doll_dur", 12.0)
	doll_tick = 0.0
	doll_at = 0.0
	melee_tgt = null
	g._add_text(pos + Vector2(0, -60), "替身", GHOST, 15)
	fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 30.0, "life": 0.5, "col": GHOST, "alpha": 0.6})
	fx_sparks(pos + Vector2(0, -20), GHOST, 10, 120.0, 0.5, 2.5)


func _update_doll(dt: float) -> void:
	if doll_t <= 0.0:
		return
	doll_t -= dt
	doll_at += dt
	# 天赋：替身光环每秒法伤 + 减速
	if elite >= 1:
		doll_tick += dt
		if doll_tick >= 1.0:
			doll_tick -= 1.0
			var r: float = base("doll_r", 120.0)
			for j in g._query(doll_pos, r + 20.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.pos.distance_to(doll_pos) > r:
					continue
				g._hit("替身")
				g._damage(e, base("doll_dps", 10.0) * _dmg_bonus())
				e.slow = maxf(e.slow, 1.0)
			if not g._fx_sprite("fx_circle_ghost", doll_pos + Vector2(0, 4), g.PX * (r / 40.0)):
				fx({"kind": "ring", "pos": doll_pos, "r": r, "r0": r * 0.6, "life": 0.5, "col": GHOST, "floor": true, "alpha": 0.5})
	if doll_t <= 0.0:
		# 归队：从替身处回到编队位
		pos = doll_pos
		doll_pos = Vector2.INF
		g._add_text(pos + Vector2(0, -60), "归队", GHOST, 14)
		fx({"kind": "glow", "pos": pos + Vector2(0, -24), "r": 24.0, "life": 0.4, "col": GHOST, "alpha": 0.5})


# ---------------------------------------------------------------- 自定义节点：艾格尼之深（每名深海猎人博士最大生命 +5%）

func on_custom_node(nid: String, _choice: String = "") -> void:
	if nid == "aegir":
		aegir = true
		hunters_applied = -1


func _update_aegir() -> void:
	if not aegir:
		return
	var n := 0
	for o in g.squad.ops:
		if o.id in ["skadi", "specter_unchained", "ulpianus"]:
			n += 1
	if n == hunters_applied:
		return
	hunters_applied = n
	g.stats.remove_source("specter_aegir")
	if n > 0:
		g.stats.add(&"max_hp", "add", 0.05 * n, "specter_aegir")
	g._sync_stats()


# ---------------------------------------------------------------- 绘制

func draw_body() -> void:
	if away():
		return
	super()


func draw_auras() -> void:
	if pos != Vector2.INF and not away() and (s1_t > 0.0 or s2_t > 0.0 or s3_t > 0.0):
		var c: Color = RED if s3_t > 0.0 else GHOST
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, _reach(), 0.0, TAU, 36, Color(c.r, c.g, c.b, 0.25 + 0.1 * sin(g.t * 6.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if doll_t > 0.0 and doll_pos != Vector2.INF and elite >= 1:
		g.draw_set_transform(doll_pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, base("doll_r", 120.0), 0.0, TAU, 36, Color(GHOST.r, GHOST.g, GHOST.b, 0.2 + 0.08 * sin(g.t * 3.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_skill_over() -> void:
	if away():
		return
	if s2_t > 0.0 or s3_t > 0.0:
		var p := pos + Vector2(4.0 * face, -38)
		var c: Color = RED if s3_t > 0.0 else GHOST
		g.draw_circle(p, 2.5 + sin(g.t * 24.0), Color(c.r * 2.0, c.g * 1.6, c.b * 1.6, 0.9))


func extra_bodies() -> Array:
	if doll_t > 0.0 and doll_pos != Vector2.INF:
		return [{"y": doll_pos.y + 2.0}]
	return []


func draw_extra(_it: Dictionary) -> void:
	var tx: Texture2D = anim_tex("doll")
	if tx == null:
		g.draw_circle(doll_pos + Vector2(0, -20), 12.0, GHOST)
		return
	var n: int = anim_hframes(tx, "doll")
	var fr: int = int(doll_at * 4.0) % n
	var sway: float = sin(doll_at * 2.0) * 1.0
	g._draw_sprite_at(doll_pos + Vector2(sway, 0), face < 0.0, Color(0.95, 0.95, 1.0), fr, tx, n, foot_off(tx, "doll"))


func draw_extra_shadows() -> void:
	if doll_t > 0.0 and doll_pos != Vector2.INF:
		g._spr("shadow", 1, 0, doll_pos + Vector2(0, 4), g.PX)


func status_items() -> Array:
	var out: Array = []
	if s2_t > 0.0:
		out.append(["不倒", GHOST])
	if s3_t > 0.0:
		out.append(["求生之压", RED])
	if doll_t > 0.0:
		out.append(["替身 %d" % int(ceil(doll_t)), GHOST])
	return out
