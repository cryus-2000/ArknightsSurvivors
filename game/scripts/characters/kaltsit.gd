## 凯尔希（医疗，docs/23 §11.1）：周期治疗博士（与骑士同伴）；Mon3tr 作为近身输出单位，撕咬博士身边的敌人。
## 技能「Mon3tr · 强化」：大治疗 + Mon3tr 狂暴；精二狂暴结束时熔毁（真实伤害）。
## Mon3tr 是本干员的附属实体（64×64 帧条，脚底 (32, 60)），自己寻敌、自己播动画，通过 extra_bodies 参与 2.5D 排序。
extends "res://scripts/characters/character.gd"

const M_LEASH := 190.0        # Mon3tr 离博士的最远距离
const M_REACH := 62.0         # 爪击半径（基础）

var cd := 1.0
var guard_t := 0.0            # 精二：溢出治疗后博士减伤的剩余时间
# ---- Mon3tr
var m := {"pos": Vector2.INF, "face": 1.0, "mv": 0.0, "kind": "idle", "at": 0.0, "act": 0.0, "fire": -1.0, "cd": 0.8, "tgt": null}
var frenzy := 0.0


func _heal_mult() -> float:
	return stat(&"op_atk") * g.ally_mult * (1.5 if elite >= 1 else 1.0)


func update(dt: float) -> void:
	cd -= dt
	guard_t = maxf(0.0, guard_t - dt)
	_update_mon3tr(dt)
	if acting():
		return
	if charge_skill(dt):
		start_skill(m.pos if m.pos != Vector2.INF else g.ppos)
		return
	if cd <= 0.0:
		cd = 3.5 / stat(&"op_aspd")
		if g.hp < g.max_hp or (g.knight.alive and g.knight.hp < g.knight.maxhp):
			start_attack(g.ppos)


func _release() -> void:
	if g.knight.alive:
		g.knight.heal(g.knight.maxhp * 0.05)
	if g.hp < g.max_hp:
		_heal(g.max_hp * 0.035 * _heal_mult(), 16)


func _heal(h: float, size: int) -> void:
	var over: float = maxf(0.0, g.hp + h - g.max_hp)
	g._heal(h)
	if elite >= 2 and over > 0.0:
		guard_t = 5.0
	g._add_text(g.ppos + Vector2(0, -90), "+%d" % int(h), Color(0.5, 1.0, 0.6), size)
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 26.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 1.0, 0.6)})
	for k in 6:
		g.fx.append({"kind": "cross", "pos": g.ppos + Vector2(randf_range(-22, 22), randf_range(-50, -5)), "life": 0.9, "max": 0.9,
			"delay": k * 0.08, "sz": randf_range(3.0, 5.0)})
	g.fx.append({"kind": "beam", "a": pos + Vector2(0, -24), "b": g.ppos + Vector2(0, -24), "life": 0.3, "max": 0.3, "col": Color(0.5, 1.0, 0.6), "w": 3.0})


func _release_skill() -> void:
	_heal(g.max_hp * 0.12 * _heal_mult(), 18)
	g.nerve = 0.0
	frenzy = 6.0
	if m.pos != Vector2.INF:
		g.fx.append({"kind": "rays", "pos": m.pos + Vector2(0, -30), "life": 0.5, "max": 0.5, "col": Color(0.6, 1.0, 0.5)})
		g.fx.append({"kind": "beam", "a": pos + Vector2(0, -26), "b": m.pos + Vector2(0, -30), "life": 0.35, "max": 0.35, "col": Color(0.6, 1.0, 0.5), "w": 3.0})
	Sfx.play("dodge", -8.0, 0.7)


# ---------------------------------------------------------------- Mon3tr

func _m_dmg() -> float:
	return 22.0 * _dmg_bonus() * (1.3 if elite >= 1 else 1.0) * (1.4 if frenzy > 0.0 else 1.0)


func _m_reach() -> float:
	return M_REACH * stat(&"op_range") * (1.2 if elite >= 1 else 1.0)


func _update_mon3tr(dt: float) -> void:
	if m.pos == Vector2.INF or m.pos.distance_to(g.ppos) > 700.0:
		m.pos = pos + Vector2(-30.0 * face, 10)
	if frenzy > 0.0:
		frenzy -= dt
		if frenzy <= 0.0 and elite >= 2:
			_meltdown()
	# 目标：博士 leash 范围内离 Mon3tr 最近的敌人；没有就回到凯尔希身边
	var tg = m.tgt
	if tg == null or tg.dead or tg.pos.distance_to(g.ppos) > M_LEASH + 40.0:
		var ts: Array = g._nearest(1, M_LEASH, g.ppos)
		tg = ts[0] if not ts.is_empty() else null
		m.tgt = tg
	var want: Vector2 = pos + Vector2(-34.0 * face, 14)
	if tg != null:
		var off: Vector2 = m.pos - tg.pos
		want = tg.pos + (off.normalized() if off.length() > 1.0 else Vector2(-m.face, 0)) * (tg.r + 26.0)
	var prev: Vector2 = m.pos
	if m.act <= 0.0:
		var spd: float = 260.0 * (1.3 if frenzy > 0.0 else 1.0)
		var d: Vector2 = want - m.pos
		m.pos += d.normalized() * minf(d.length(), spd * dt)
		if g.tex.get("prop_pillar") != null:
			m.pos = g.map.push_out(m.pos, 14.0)
	var vel: Vector2 = (m.pos - prev) / maxf(dt, 0.0001)
	m.mv = lerpf(m.mv, vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if absf(vel.x) > 20.0 and m.act <= 0.0:
		m.face = signf(vel.x)
	# 爪击
	m.cd -= dt * (1.7 if frenzy > 0.0 else 1.0)
	if m.act > 0.0:
		m.act -= dt
		if m.fire >= 0.0:
			m.fire -= dt
			if m.fire < 0.0:
				m.fire = -1.0
				_m_strike()
	elif tg != null and m.cd <= 0.0 and m.pos.distance_to(tg.pos) < tg.r + _m_reach():
		m.cd = 0.9 / stat(&"op_aspd")
		m.face = signf(tg.pos.x - m.pos.x) if absf(tg.pos.x - m.pos.x) > 2.0 else m.face
		var spec := sprite_spec("m_attack")
		var fps: float = float(spec.get("fps", 14))
		m.act = float(spec.get("frames", 4)) / fps
		m.fire = (float(spec.get("fire", 2)) + 0.5) / fps
		_m_set_kind("attack")
	var k: String = "attack" if m.act > 0.0 else ("run" if m.mv > 30.0 else "idle")
	_m_set_kind(k)
	m.at += dt


func _m_set_kind(k: String) -> void:
	if m.kind != k:
		m.kind = k
		m.at = 0.0


func _m_strike() -> void:
	var ang: float = 0.0 if m.face >= 0.0 else PI
	var hits := melee_hit("Mon3tr", m.pos + Vector2(0, -10), ang, 1.3, _m_reach() + 16.0, _m_dmg(), 120.0)
	g._slash_fx(m.pos + Vector2(0, -16), ang, 1.0, _m_reach(), Color(0.7, 1.0, 0.55))
	if not hits.is_empty():
		Sfx.play("swing", -12.0, 0.8, 0.05)


func _meltdown() -> void:
	var r := 130.0
	area_hit("Mon3tr · 熔毁", m.pos, r, 22.0 * 5.0 * _dmg_bonus() * skill_power(), 260.0, 0.5)
	g.fx.append({"kind": "explode", "pos": m.pos, "r": r, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.45)})
	g.fx.append({"kind": "quake", "pos": m.pos, "r": r, "life": 0.5, "max": 0.5, "col": Color(0.6, 1.0, 0.5)})
	g._add_text(m.pos + Vector2(0, -70), "熔毁", Color(0.6, 1.0, 0.5), 18)
	Sfx.play("boom", -9.0, 0.7)


func extra_bodies() -> Array:
	if m.pos == Vector2.INF:
		return []
	return [{"y": m.pos.y + 4.0}]


func draw_extra(_it: Dictionary) -> void:
	var kind: String = "m_" + m.kind
	var tx: Texture2D = anim_tex(kind)
	if tx == null:
		g.draw_circle(m.pos + Vector2(0, -14), 14.0, Color(0.3, 0.4, 0.3))
		return
	var n: int = anim_hframes(tx, kind)
	var fr: int
	if m.kind == "attack":
		var spec := sprite_spec("m_attack")
		fr = clampi(int(m.at * float(spec.get("fps", 14))), 0, n - 1)
	else:
		fr = int(m.at * float(sprite_spec(kind).get("fps", 4))) % n
	var col := Color(1.25, 1.35, 1.1) if frenzy > 0.0 else Color.WHITE
	g._draw_sprite_at(m.pos, m.face < 0.0, col, fr, tx, n, foot_off(tx, kind))


func draw_extra_shadows() -> void:
	if m.pos != Vector2.INF:
		g._spr("shadow", 1, 0, m.pos + Vector2(0, 4), g.PX * 1.5)


func draw_auras() -> void:
	if frenzy > 0.0 and m.pos != Vector2.INF:
		g.draw_arc(m.pos, 34.0, 0.0, TAU, 24, Color(0.6, 1.0, 0.5, 0.35 + 0.15 * sin(g.t * 10.0)), 2.0)


## 精二：溢出治疗后 5 秒博士受伤 -20%（game.gd _enemy_hit 查询）
func dmg_taken_mult() -> float:
	return 0.8 if guard_t > 0.0 else 1.0


func status_items() -> Array:
	var out: Array = []
	if frenzy > 0.0:
		out.append(["Mon3tr 狂暴", Color(0.6, 1.0, 0.5)])
	if guard_t > 0.0:
		out.append(["庇护", Color(0.5, 1.0, 0.6)])
	return out
