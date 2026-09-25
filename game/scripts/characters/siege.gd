## 推进之王（先锋，docs/23 §10 / §11.1）：节奏位。前压到博士身边的敌人面前抡锤，命中时为全队回复技力；
## 技能「震地」：双手砸地、范围晕眩，并按比例为全队充能。
extends "res://scripts/characters/character.gd"

const LEASH := 150.0          # 前压：只追博士这么远以内的敌人

var cd := 0.4


func _reach() -> float:
	return 72.0 * stat(&"op_range")


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 26.0)
	return p if p != Vector2.INF else slot_pos


func update(dt: float) -> void:
	cd -= dt
	if acting():
		return
	if charge_skill(dt):
		start_skill(Vector2.INF)
		return
	if cd <= 0.0:
		var ts: Array = g._nearest(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = 1.0 / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _release() -> void:
	var ang := facing_angle()
	var ts: Array = g._nearest(1, _reach() + 40.0, pos)
	if not ts.is_empty():
		ang = (ts[0].pos - pos).angle()
		face_to(ang)
	var hits := melee_hit("锤击", pos + Vector2(0, -10), ang, 1.2, _reach(), 30.0 * _dmg_bonus(), 140.0)
	g._slash_fx(pos + Vector2(0, -14), ang, 1.0, _reach(), Color(1.0, 0.8, 0.45))
	if not hits.is_empty():
		# 每次命中（不论几个目标）全队 +0.5 秒技力，精一翻倍
		_squad_sp_seconds(1.0 if elite >= 1 else 0.5)
		Sfx.play("swing", -11.0, 0.7, 0.05)


func _release_skill() -> void:
	var r: float = 110.0 * stat(&"op_range") * (1.3 if elite >= 2 else 1.0)
	area_hit("震地", pos, r, 30.0 * 2.2 * _dmg_bonus() * skill_power(), 220.0, 1.0 if elite >= 2 else 0.6)
	g.fx.append({"kind": "quake", "pos": pos, "r": r, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.8, 0.45)})
	g.fx.append({"kind": "ring", "pos": pos, "r": r, "life": 0.35, "max": 0.35, "col": Color(1.0, 0.85, 0.5)})
	g.shake = maxf(g.shake, 5.0)
	_squad_sp_pct(0.35 if elite >= 2 else 0.2)
	Sfx.play("boom", -9.0, 0.6)


## 全队（不含自己）技力 + 秒数
func _squad_sp_seconds(sec: float) -> void:
	for o in g.squad.ops:
		if o != self and float(o.skill_def().get("sp", 0.0)) > 0.0:
			o.sp += sec


## 全队（不含自己）技力 + 需求的百分比
func _squad_sp_pct(p: float) -> void:
	for o in g.squad.ops:
		var need: float = float(o.skill_def().get("sp", 0.0))
		if o != self and need > 0.0:
			o.sp = minf(need, o.sp + need * p)
