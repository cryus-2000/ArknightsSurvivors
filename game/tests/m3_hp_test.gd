extends Node
## Mon3tr 血条 / 倒下 / 复活 / 治疗分配（docs/plans/2026-10-29-mon3tr-hp-plan.md，用户 10-29 定 5 项）：
##   godot --headless --path game res://tests/m3_hp_test.tscn -- --regression --balance --seed=1 --op=texas --squad=kaltsit
##   godot --headless --path game res://tests/m3_hp_test.tscn -- --regression --balance --seed=1 --op=texas --squad=kaltsit --bal=kaltsit/m3_hp=0   （总开关关：回旧行为）
## 冻结主循环，手动改状态后推 update。全部通过时打印 "M3 HP failures=0"。

const M3 = preload("res://scripts/characters/blocks/m3_hp.gd")
const ObSummonRef = preload("res://scripts/characters/blocks/ob_summon.gd")
const DT := 1.0 / 60.0
var game: Node
var frames := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var g = game
	g.state = g.S.PLAY
	g.invuln = 999.0
	var k = g.squad.get_op("kaltsit")
	ok(k != null, "凯尔希在队")
	if k == null:
		finish()
		return
	k.refresh_stats()
	var s = _m3(k)
	ok(s != null, "Mon3tr 在场")
	if s == null:
		finish()
		return
	if not M3.on():
		test_off(g, k, s)
	else:
		test_on(g, k, s)
	finish()


func finish() -> void:
	print("M3 HP failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _m3(k):
	for s in k.sm.list:
		if str(s.kind) == "mon3tr":
			return s
	return null


func tick(k) -> void:
	k.update(DT)


func clear_enemies(g) -> void:
	for e in g.enemies:
		e.dead = true
	g.enemies_sys.build_grid()


func spawn(g, p: Vector2, hp := 1000000.0) -> Dictionary:
	var e: Dictionary = g.spawner.spawn_enemy("bone", p)
	e.hp = hp
	e.maxhp = hp
	e.age = 99.0
	g.enemies_sys.build_grid()
	return e


## 总开关关：Mon3tr 无敌、没有 m3 状态、治疗拍只给队长
func test_off(g, k, s) -> void:
	ok(s.inv and not s.has("m3"), "开关关：Mon3tr 无敌、不走血条规则")
	var hp0: float = s.hp
	clear_enemies(g)
	var e := spawn(g, s.pos)
	for i in 10:
		tick(k)
	ok(s.hp == hp0, "开关关：怪碰它不扣血")
	ok(M3.heal_pick(k) == null, "开关关：治疗不分配")


func test_on(g, k, s) -> void:
	var kd: Dictionary = k.B.summons.mon3tr
	ok(not s.inv and s.has("m3"), "Mon3tr 有血条（不再无敌）")
	ok(absf(float(s.max_hp) - g.max_hp * float(kd.hp_k)) < 0.01 and float(kd.hp_k) == 3.0, "上限 = 队长上限 × 3（%.0f / %.0f）" % [float(s.max_hp), g.max_hp])
	var mx: float = s.max_hp
	# ---- 接触受击：每只怪每秒一次，敌伤 × 0.4
	clear_enemies(g)
	g.t = 100.0
	var e := spawn(g, s.pos)
	var dm: float = float(e.dmg) * 0.4
	tick(k)
	ok(absf(float(s.hp) - (mx - dm)) < 0.01, "近战怪碰到它：扣 敌伤 × 0.4（%.2f，期望 %.2f）" % [mx - float(s.hp), dm])
	tick(k)
	ok(absf(float(s.hp) - (mx - dm)) < 0.01, "同一只怪 1 秒内不重复扣")
	g.t += 1.05
	tick(k)
	ok(absf(float(s.hp) - (mx - 2.0 * dm)) < 0.01, "过 1 秒再扣一次")
	# ---- 仇恨：圈内按怪 id 黄金比哈希，比例 0.35
	clear_enemies(g)
	var ring: Array = []
	for i in 40:
		ring.append(spawn(g, s.pos + Vector2.from_angle(TAU * i / 40.0) * 110.0))
	for q in ring:
		q.erase("aggro")
	tick(k)
	var pulled := 0
	var okh := true
	for q in ring:
		var want: bool = fposmod(float(q.id) * 0.6180339887, 1.0) < 0.35
		var got: bool = q.get("aggro", Vector2.INF) != Vector2.INF
		okh = okh and want == got
		pulled += 1 if got else 0
	ok(okh and pulled > 0 and pulled < 40, "圈内 %d / 40 只改追它，与 id 哈希一致" % pulled)
	var far := spawn(g, s.pos + Vector2(400, 0))
	far.erase("aggro")
	tick(k)
	ok(far.get("aggro", Vector2.INF) == Vector2.INF, "圈外的怪不被拉")
	# ---- 回血：脱战 3 秒后 20 秒回满
	clear_enemies(g)
	s.hp = mx * 0.5
	s.m3.calm = 5.0
	tick(k)
	ok(absf(float(s.hp) - (mx * 0.5 + mx / 20.0 * DT)) < 0.01, "脱战回血 上限 / 20 秒")
	s.m3.calm = 1.0
	var h1: float = s.hp
	tick(k)
	ok(float(s.hp) == h1, "脱战不足 3 秒不回血")
	# ---- 倒下：精英二前不爆
	clear_enemies(g)
	var near_e := spawn(g, s.pos + Vector2(30, 0), 5000.0)
	k.elite = 1
	var hp_e0: float = near_e.hp
	s.hp = 0.0
	tick(k)
	ok(M3.is_down(s) and absf(float(s.down) - 18.0) < 0.1, "血空倒地 18 秒（%.1f）" % float(s.down))
	ok(near_e.hp == hp_e0 and float(near_e.get("stun", 0.0)) <= 0.0, "精英二前倒下不爆")
	# ---- 倒地中：不被打、不拉仇恨、不接指挥
	near_e.erase("aggro")
	var dn: float = s.down
	tick(k)
	ok(float(s.down) < dn and near_e.get("aggro", Vector2.INF) == Vector2.INF and float(s.hp) == 0.0, "倒地中读秒、不被打、不拉仇恨")
	var el = load("res://scripts/characters/blocks/ob_elite.gd")
	for sm in k.sm.list:
		sm.erase("dash")
	el.el_summon_cmd(k, {"kind": "mon3tr", "action": "leap", "to": "leader", "t": 0.25}, Vector2.ZERO)
	ok(not s.has("dash"), "倒地的不接跃回指挥")
	# ---- 复活
	s.down = 0.02
	s.pos = g.ppos + Vector2(400, 0)
	tick(k)
	tick(k)
	ok(not M3.is_down(s) and absf(float(s.hp) - mx * 0.5) < 1.0 and float(s.m3.inv) > 0.5, "到时复活：50% 血、1 秒无敌")
	ok(s.pos.distance_to(g.ppos) < 120.0, "复活在队长身边（%.0f）" % s.pos.distance_to(g.ppos))
	var hp_r: float = s.hp
	clear_enemies(g)
	spawn(g, s.pos)
	tick(k)
	ok(float(s.hp) == hp_r, "复活无敌期不扣血")
	# ---- 精英二：倒下触发小爆
	clear_enemies(g)
	k.elite = 2
	k.refresh_stats()
	var near2 := spawn(g, s.pos + Vector2(30, 0), 5000.0)
	var hp2: float = near2.hp
	s.m3.inv = 0.0
	s.hp = 0.0
	tick(k)
	ok(M3.is_down(s) and (near2.hp < hp2 or float(near2.get("stun", 0.0)) > 0.0), "精英二倒下触发「不毁重构」小爆（hp %.0f→%.0f stun %.1f）" % [hp2, near2.hp, float(near2.get("stun", 0.0))])
	s.down = 0.0
	s.hp = mx
	# ---- 终结技用掉它：同一倒计时、不触发小爆
	clear_enemies(g)
	var near3 := spawn(g, s.pos + Vector2(30, 0), 5000.0)
	var hp3: float = near3.hp
	M3.down(k, s, kd, 18.0, true)
	ok(M3.is_down(s) and near3.hp == hp3, "终结技用掉（silent）：倒计时 18 秒、不触发倒下小爆")
	s.down = 0.0
	s.hp = mx
	# ---- 治疗分配
	clear_enemies(g)
	g.hp = g.max_hp
	s.hp = mx * 0.5
	s.m3.hit_t = -99.0
	k.sm["m3heal"] = []
	k.sm["lhist"] = []
	ok(M3.heal_pick(k) == s, "队长满血、Mon3tr 50%：治疗给 Mon3tr")
	k.sm["m3heal"] = []
	g.hp = g.max_hp * 0.40
	ok(M3.heal_pick(k) == null, "队长生命 < 45%：队长优先")
	g.hp = g.max_hp * 0.75
	k.sm["m3heal"] = []
	k.sm["lhist"] = [[g.t - 1.0, g.max_hp]]
	ok(M3.heal_pick(k) == null, "队长 3 秒内掉 ≥ 20%：队长优先")
	k.sm["lhist"] = []
	s.hp = mx * 0.9
	g.hp = g.max_hp * 0.9
	k.sm["m3heal"] = []
	ok(M3.heal_pick(k) == null, "Mon3tr 不比队长低（同为 90%）：留给队长")
	s.hp = mx * 0.5
	g.hp = g.max_hp * 0.9
	k.sm["m3heal"] = []
	var to_m3 := 0
	for i in 10:
		if M3.heal_pick(k) != null:
			to_m3 += 1
	ok(to_m3 >= 3 and to_m3 <= 4, "占比上限 40%%：10 拍里 Mon3tr %d 拍" % to_m3)
	k.sm["m3heal"] = []
	M3.down(k, s, kd, 18.0, true)
	ok(M3.heal_pick(k) == null, "Mon3tr 倒地：治疗给队长")
	s.down = 0.0
	s.hp = mx * 0.5
	# ---- _heal：落到 Mon3tr、庇护算它的溢出；S1（无 split）永远给队长
	var hb: Dictionary = k.B.attack.do[0]
	ok(hb.get("split", false), "治疗块写了 split")
	g.hp = g.max_hp * 0.95
	var gh: float = g.hp
	var hm0: float = s.hp
	k.sm["m3heal"] = []
	k._heal(hb)
	ok(float(s.hp) > hm0 and g.hp == gh, "治疗拍落在 Mon3tr：它回血、队长不变（+%.1f）" % (float(s.hp) - hm0))
	s.hp = mx - 0.5
	k.sm["m3heal"] = []
	g.hp = g.max_hp * 0.95
	k._heal(hb)
	ok(M3.hurt_any(k) == false, "Mon3tr 满血后 hurt_any 不再因它成立")
	# 庇护算 Mon3tr 身上的溢出：队长满血、Mon3tr 99% → 拍给 Mon3tr 且溢出 → 庇护触发
	g.hp = g.max_hp
	s.hp = mx * 0.99
	k.sm["m3heal"] = []
	k.mf = {} if k.mf == null else k.mf
	var guard0: float = ObSummonRef.mf_guard_mult(k, 1.0)
	k._heal(hb)
	ok(float(s.hp) == mx and ObSummonRef.mf_guard_mult(k, 1.0) < guard0, "治疗拍溢出在 Mon3tr 身上：庇护触发（%.2f → %.2f）" % [guard0, ObSummonRef.mf_guard_mult(k, 1.0)])
	var s1: Dictionary = k.B.skills[0].do[0]
	ok(not s1.get("split", false), "S1 结构加固不分配（永远队长）")
	k.sm["m3heal"] = []
	s.hp = mx * 0.5
	g.hp = g.max_hp * 0.5
	var gh1: float = g.hp
	k._heal(s1)
	ok(g.hp > gh1 and float(s.hp) == mx * 0.5, "S1：只治队长")


func ok(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: " + msg)
