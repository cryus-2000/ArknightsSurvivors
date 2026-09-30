extends RefCounted
## 人形治疗海嗣、对干员不可索敌；中立泪滴加速转化，主控靠近可压制该枚充能。
## friendly 仅表示不进入干员索敌/伤害管线，不代表协助干员。
## 原作参考与改编差异见 docs/ea_ishar_20260927.md。敌对形态的攻击仍由 BossAI 管理。
const Game = preload("res://scripts/game.gd")
const Bal = preload("res://scripts/core/balance.gd")
const HEAL_COLOR := Color(0.25, 1.0, 0.85)
var g: Game

func _init(game: Game) -> void:
	g = game

func step_ally(e: Dictionary, dt: float) -> void:
	if e.type == "tear":
		step_tear(e, dt)
		return
	if e.type != "ishar" or e.phase != 1:
		return
	if not e.has("ally_charge"):
		e.ally_charge = 0.0
		# ishar_p1_scale（协调人 9/30 定，缺省 0.6 = 30 → 18 秒，1 = 关）：人形阶段打不了她，缩短这段空等
		e.ally_charge_need = snappedf(Bal.v("boss/ishar_ally_charge", 30.0) * Bal.v("boss/ishar_p1_scale", 0.6), 0.1)
		e.ally_attack_cd = 0.8
		e.ally_tear_cd = 5.0
		g.vfx.show_banner("伊莎玛拉治疗海嗣 · 靠近泪滴可延缓转化")
	var tear_bonus := 0.0
	for o in g.enemies:
		if not o.dead and o.type == "tear" and is_same(o.get("owner"), e) and not tear_blocked(o):
			tear_bonus += Bal.v("boss/ishar_tear_charge", 0.35)
	e.ally_charge += dt * (1.0 + tear_bonus)
	if e.ally_charge >= e.ally_charge_need:
		g.bai.transform_ishar(e)
		return
	# 跟随主控，保留空隙；不走敌人接触伤害 / 寻路追击分支。
	var want: Vector2 = g.ppos + Vector2(-110.0, -45.0)
	var old: Vector2 = e.pos
	if e.pos.distance_to(want) > 60.0:
		e.pos = e.pos.move_toward(want, 72.0 * dt)
		e.mv_until = g.t + 0.12
		if absf(e.pos.x - old.x) > 0.01:
			e.fx = signf(e.pos.x - old.x)
	# 即使暂时静止也要重新限位，避免缩圈或障碍推挤使本体落入黑潮。
	e.pos = g.spawner.safe_event_pos(g.map.push_out(g.combat.arena_clamp(e.pos, 110.0), e.r), 110.0)
	e.ally_tear_cd -= dt
	if e.ally_tear_cd <= 0.0:
		e.ally_tear_cd = Bal.v("boss/ishar_tear_every", 8.0)
		spawn_tear(e)
	e.ally_attack_cd -= dt
	if e.ally_attack_cd > 0.0:
		return
	var candidates: Array = []
	var reach: float = Bal.v("boss/ishar_heal_range", 480.0)
	for o in g.enemies:
		if not o.dead and not o.boss and not o.chest and not o.get("friendly", false) and o.type != "tear" and o.hp < o.maxhp and o.pos.distance_to(e.pos) <= reach:
			candidates.append(o)
	if candidates.is_empty():
		e.ally_attack_cd = 0.2
		return
	candidates.sort_custom(func(a, b): return a.hp / a.maxhp < b.hp / b.maxhp)
	e.ally_attack_cd = Bal.v("boss/ishar_heal_cd", 2.2)
	e.pose = 0.55
	e.pose_max = 0.55
	e.atk_until = g.t + 0.55
	for target in candidates.slice(0, 3):
		if absf(target.pos.x - e.pos.x) > 1.0:
			e.fx = signf(target.pos.x - e.pos.x)
		g.fx.append({"kind": "beam", "pos": e.pos, "a": e.pos + Vector2(0, -40), "b": target.pos + Vector2(0, -12), "w": 4.0, "col": HEAL_COLOR, "life": 0.32, "max": 0.32})
		var healed: float = minf(e.dmg, target.maxhp - target.hp)
		target.hp += healed
		g.fx.append({"kind": "cross", "pos": target.pos + Vector2(0, -18), "sz": 4.5, "delay": 0.0, "life": 0.65, "max": 0.65})
		g.vfx.add_text(target.pos + Vector2(0, -30), "+%d" % roundi(healed), HEAL_COLOR, 13)

func tear_blocked(e: Dictionary) -> bool:
	return e.pos.distance_to(g.ppos) <= Bal.v("boss/ishar_tear_block_radius", 32.0)

func spawn_tear(owner: Dictionary) -> Dictionary:
	var count := 0
	for e in g.enemies:
		if not e.dead and e.type == "tear" and is_same(e.get("owner"), owner):
			count += 1
	if count >= 3:
		return {}
	var at: Vector2 = g.combat.arena_clamp(g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * 100.0, 50.0)
	var tear: Dictionary = g.spawner.spawn_enemy("tear", at)
	tear.owner = owner
	tear.friendly = true
	tear.invuln = true
	tear.blocked = false
	tear.pulse_cd = 0.0
	return tear

func step_tear(e: Dictionary, dt: float) -> void:
	var owner = e.get("owner")
	if owner == null or owner.dead or owner.phase != 1:
		e.dead = true
		return
	var blocked := tear_blocked(e)
	if blocked and not e.get("blocked", false):
		g.vfx.add_text(e.pos + Vector2(0, -26), "充能已压制", HEAL_COLOR, 13)
	e.blocked = blocked
	e.pulse_cd = float(e.get("pulse_cd", 0.0)) - dt
	if e.pulse_cd <= 0.0:
		e.pulse_cd = 0.65
		g.fx.append({"kind": "ring", "pos": e.pos, "r": Bal.v("boss/ishar_tear_block_radius", 32.0), "life": 0.6, "max": 0.6, "col": HEAL_COLOR if blocked else Color(0.65, 0.7, 1.0), "floor": true})

## 演练单独提供少量低威胁目标，正式对局仍只使用现有波次的敌人。
func practice_targets(e: Dictionary) -> void:
	if e.dead or e.phase != 1:
		return
	if g.t < float(e.get("practice_next_at", -1.0)):
		return
	for target in g.enemies:
		if not target.dead and not target.boss and not target.chest and not target.get("friendly", false):
			return
	e.practice_next_at = g.t + 2.0
	for i in 3:
		var pos: Vector2 = g.combat.arena_clamp(e.pos + Vector2(100.0 + i * 35.0, 80.0 - i * 60.0), 70.0)
		var target: Dictionary = g.spawner.spawn_enemy("bone", pos)
		target.hp = target.maxhp * 0.5
