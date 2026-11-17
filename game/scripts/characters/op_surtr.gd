## 史尔特尔（docs/369）：数据干员 + 积木表达不了的四处时序（docs/61 §6 逃生口：只做时序，数值全读 base）。
## 1. 烈焰魔剑：这一剑击倒敌人时回复技力（精英 / Boss 回满，普通敌人回 s1_refund；每一剑只结算一次）。
## 2. 余烬（天赋）：队长受到致命伤害时生命保持 1，ember_dur 秒内不会倒下（精二 ember_dur2）；ember_cd 秒内至多一次。
## 3. 黄昏：生效那一帧队长回满生命（不是队长时回 s3_mate_heal）；她是队长时，持续期间队长生命逐渐流失（从 0 线性升到 s3_drain × 最大生命 / 秒），流失不会让生命低于 s3_floor。
## 确定性：不取随机数；独立文件，不进 op_blocks 继承链（-s 契约测试不加载本文件，但仍不引用自动加载）。
extends "res://scripts/characters/data_operator.gd"

var _s1_swing_t := -1.0      # 上一次魔剑回技力结算的时刻（同一剑多杀只算一次）
var _ember_until := -1.0     # 余烬不倒的截止时刻
var _ember_ready_t := 0.0    # 余烬下一次可用的时刻


func on_kill(e: Dictionary) -> void:
	super(e)
	var h = g.hit
	if not (h is Dictionary) or str(h.get("src", "")) != "烈焰魔剑":
		return
	var full: bool = bool(e.get("elite", false)) or bool(e.get("boss", false))
	if not full and is_equal_approx(_s1_swing_t, g.t):
		return
	_s1_swing_t = g.t
	var need: float = sp_need(0)
	sp[0] = minf(need, float(sp[0]) + need * (1.0 if full else base("s1_refund", 0.34)))


func prevent_death() -> bool:
	if super():
		return true
	if elite < 1:
		return false
	if g.t < _ember_until:
		return true
	if g.t < _ember_ready_t:
		return false
	_ember_until = g.t + (base("ember_dur2", 6.0) if elite >= 2 else base("ember_dur", 4.0))
	_ember_ready_t = g.t + base("ember_cd", 90.0)
	if g.vfx != null:
		g.vfx.add_text(g.ppos + Vector2(0, -46), "余烬", Color(1.0, 0.55, 0.25), 18)
	return true


func update(dt: float) -> void:
	var was_on: bool = float(s_t[2]) > 0.0
	super(dt)
	if not was_on and float(s_t[2]) > 0.0:   # 黄昏生效的那一帧：队长回满（verb.heal 单次上限 20%，表达不了「回满」）
		var amt: float = (g.max_hp - g.hp) if is_leader else g.max_hp * base("s3_mate_heal", 0.3)
		if amt > 0.0:
			g.combat.heal(amt, "黄昏")
	var floor_hp: float = maxf(1.0, g.max_hp * base("s3_floor", 0.3))
	if is_leader and float(s_t[2]) > 0.0 and g.hp > floor_hp:
		var dur: float = maxf(0.1, base("s3_dur", 18.0))
		var k: float = clampf(1.0 - float(s_t[2]) / dur, 0.0, 1.0)
		var amt: float = minf(g.max_hp * base("s3_drain", 0.02) * k * dt, g.hp - floor_hp)
		if amt > 0.0:
			g.combat.lose_hp(amt, "黄昏")
