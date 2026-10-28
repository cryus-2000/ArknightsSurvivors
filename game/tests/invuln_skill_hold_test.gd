extends Node
## 无敌暂缓技能（10-28 用户：「在面对无敌的敌人的时候可以继续普通攻击，但是可以不放技能，等不无敌了再放，这对手感很重要」）：
## 真游戏 + 真最终 Boss（paranoia）贴脸站桩，Boss 无敌 3 秒 → 普攻照常出手、自动技能一次不放、Boss 不掉血；
## 解除无敌后 1 秒内技能放出；combat/hold_skill_on_invuln 0 时无敌期也放（旧行为）
const Ch = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")
class HoldOp extends "res://scripts/characters/data_operator.gd":
	var attacks := 0
	var casts := 0
	func _release() -> void:
		attacks += 1
		super()
	func _release_skill() -> void:
		casts += 1
		super()
const OPS := ["exusiai", "texas", "lappland", "skadi", "mizuki", "eyjafjalla"]
const DT := 1.0 / 60.0
var g
var checks := 0
var failures := 0
func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	for id in OPS:
		run_one(id, false, 1.0)
	run_one("exusiai", true, 1.0)    # 队长：非手动的自动技能同样暂缓
	run_one("texas", false, 0.0)     # 开关关掉 = 旧行为（无敌期照放）
	print("INVULN SKILL HOLD checks=%d failures=%d" % [checks, failures])
	g.queue_free()
	get_tree().quit(1 if failures else 0)


func run_one(id: String, leader: bool, sw: float) -> void:
	Bal.v("combat/hold_skill_on_invuln", 1.0)   # 先触发载入
	Bal._data["combat"] = {"hold_skill_on_invuln": sw}
	g.enemies.clear()
	g.bosses.clear()
	var o = HoldOp.new(g, Ch.load_def(id).duplicate(true))
	o.is_leader = leader
	o.elite = 2
	o.pos = g.ppos
	var boss: Dictionary = g.spawner.spawn_enemy("paranoia", g.ppos + Vector2(110, 0))
	boss.invuln = true
	boss.maxhp = 1.0e9
	boss.hp = 1.0e9
	for i in 3:
		if o.skill_unlocked(i) and not o.is_manual(i):
			o.sp[i] = o.sp_need(i)
	var tag := "%s%s%s" % [id, " leader" if leader else "", " switch-off" if sw <= 0.0 else ""]
	g.enemies_sys.build_grid()
	var hp0: float = boss.hp
	for f in 180:
		g.t += DT
		g.frame_n += 1
		boss.pos = g.ppos + Vector2(110, 0)
		g.enemies_sys.build_grid()
		o.follow(DT, g.ppos)
		o.update(DT)
	if sw > 0.0:
		ok(o.attacks > 0, "%s: keeps auto-attacking the invulnerable boss (%d)" % [tag, o.attacks])
		ok(o.casts == 0, "%s: no skill cast while the boss is invulnerable (%d)" % [tag, o.casts])
		ok(boss.hp == hp0, "%s: invulnerable boss takes no damage" % tag)
	else:
		ok(o.casts > 0, "%s: skill fires on the invulnerable boss (old behaviour)" % tag)
	boss.invuln = false
	var c0: int = o.casts
	var t_cast := -1.0
	for f in 60:
		g.t += DT
		g.frame_n += 1
		boss.pos = g.ppos + Vector2(110, 0)
		g.enemies_sys.build_grid()
		o.follow(DT, g.ppos)
		o.update(DT)
		if t_cast < 0.0 and o.casts > c0:
			t_cast = (f + 1) * DT
	if sw > 0.0:
		ok(t_cast >= 0.0, "%s: skill released within 1 s after invulnerability ends (%.2f s)" % [tag, t_cast])
	print("HOLD %s: attacks=%d casts=%d released_after=%.2fs" % [tag, o.attacks, o.casts, t_cast])
	boss.dead = true
	Bal._data.erase("combat")
