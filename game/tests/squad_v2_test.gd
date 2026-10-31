extends Node
## 小队指挥 v2（docs/209 §1 / §2）：护卫阵型站位、突击职业分工、部署阻挡、突击中吃敌弹 / 预警、残血撤回、医疗回血、
## 圆盘「随行」合并归队、以施放者为中心、连携 v2 按姿态挑人。用真游戏场景，直接调编队函数（不跑整局）。
## godot --headless --path game res://tests/squad_v2_test.tscn -- --regression --balance --seed=1 --op=texas --squad=hoshiguma,exusiai
## 全部通过时打印 "SQUAD V2 checks=N failures=0"

const Bal = preload("res://scripts/core/balance.gd")
const Tactics = preload("res://scripts/characters/tactics.gd")
const LinkV2 = preload("res://scripts/run/link_v2.gd")

var checks := 0
var failures := 0
var g


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func _foe(p: Vector2, elite := false) -> Dictionary:
	var e: Dictionary = g.spawner.spawn_enemy("bone", p)
	e.hp = 1.0e9
	e.maxhp = 1.0e9
	e.spd = 0.0
	e.ai = "melee"
	if elite:
		e.elite = true
	return e


func _clear() -> void:
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	g.enemies_sys.build_grid()


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	g.bot = null
	_clear()
	var sq = g.squad
	sq.extra_slot = true
	if not sq.has("lumen"):
		sq.add("lumen", false)
	var ld = sq.leader()
	var heavy = sq.get_op("hoshiguma")
	var sniper = sq.get_op("exusiai")
	var medic = sq.get_op("lumen")
	ok(Tactics.on() and heavy != null and sniper != null and medic != null, "v2 开着、编队里有重装 / 狙击 / 医疗")
	if heavy == null or sniper == null or medic == null:
		_done()
		return
	var dt := 1.0 / 60.0
	# 1. 护卫阵型：怪群在右边 → 重装站右（前）、狙击 / 医疗站左（后）
	for k in 8:
		_foe(g.ppos + Vector2(300, -60 + k * 15))
	g.enemies_sys.build_grid()
	sq.escort_dir = Vector2.ZERO
	for f in 90:
		sq.escort_dir = Tactics.threat_dir(g, sq.escort_dir, dt)
	ok(sq.escort_dir.x > 0.95, "威胁方向朝怪群（%.2f, %.2f）" % [sq.escort_dir.x, sq.escort_dir.y])
	var offs: Dictionary = Tactics.escort_offsets(sq, sq.escort_dir)
	ok(offs[heavy].x > 50.0, "重装挡在队长和怪群之间（%.0f）" % offs[heavy].x)
	ok(offs[sniper].x < -50.0, "狙击站后排（%.0f）" % offs[sniper].x)
	ok(offs[medic].x < 0.0 and offs[medic].length() < 60.0, "医疗贴身靠后（%.0f）" % offs[medic].x)
	_clear()
	# 2. 突击职业分工：狙击偏好精英、术师偏好密集、先锋偏好前方、近卫按离队长距离
	var mob := _foe(g.ppos + Vector2(200, 0))
	var eli := _foe(g.ppos + Vector2(300, 0), true)
	ok(Tactics.role_score(sniper, eli, 300.0) < Tactics.role_score(sniper, mob, 200.0), "狙击：远一点的精英排在近处杂兵前")
	_clear()
	# 3. 代价：突击中吃敌弹（子弹消失），随行不吃
	sq.set_stance(sq.ROAM)
	sniper.pos = g.ppos + Vector2(-200, 0)
	sniper.cmd_hp = 1.0
	sniper.cmd_inv = 0.0
	ok(sq.roaming_op(sniper), "突击中狙击算出击")
	var bl := {"pos": sniper.pos + Vector2(0, -16), "life": 1.0, "r": 6.0, "dmg": 40.0, "vel": Vector2.ZERO}
	g.ebullets.append(bl)
	sq._tick_hp(dt)
	ok(sniper.cmd_hp < 1.0 and bl.life <= 0.0, "突击中敌弹打到队友并消失（生命 %.3f）" % sniper.cmd_hp)
	var hp0: float = sniper.cmd_hp
	var w := {"shape": "circle", "pos": sniper.pos, "r": 80.0, "dmg": 30.0}
	sq.warn_hit(w)
	ok(sniper.cmd_hp < hp0, "突击中站在预警圈里吃招式伤害")
	# 4. 残血撤回 / 归位
	sniper.cmd_hp = 0.25
	sq._tick_hp(dt)
	ok(sniper.cmd_retreat and not sq.roaming_op(sniper), "生命 < 30% 自动撤回、不再算出击")
	sniper.cmd_hp = 0.65
	sq._tick_hp(dt)
	ok(not sniper.cmd_retreat, "回到 60% 以上归位")
	# 5. 以施放者为中心：突击中的队友 lead_pos = 自己，随行时 = 队长
	ok(sniper.lead_pos() == sniper.pos, "突击中「以队长为中心」改以自己为中心")
	# 6. 随行不吃弹；医疗给队友回血
	sq.set_stance(sq.GUARD)
	sniper.cmd_hp = 0.5
	var bl2 := {"pos": sniper.pos + Vector2(0, -16), "life": 1.0, "r": 6.0, "dmg": 40.0, "vel": Vector2.ZERO}
	g.ebullets.append(bl2)
	sq._tick_hp(dt)
	ok(bl2.life > 0.0, "随行中队友不吃敌弹")
	ok(sniper.lead_pos() == g.ppos, "随行时仍以队长为中心")
	medic.pos = sniper.pos + Vector2(40, 0)
	var h0: float = sniper.cmd_hp
	Tactics.tick_medic(sq, 1.0)
	ok(sniper.cmd_hp > h0 + 0.03, "医疗给生命最低的队友回血（%.3f → %.3f）" % [h0, sniper.cmd_hp])
	g.ebullets.clear()
	# 7. 部署阻挡：重装站到驻扎点，挡住 3 个（精英占 2）
	sq._order_cd = 0.0
	ok(sq.apply_order("point", g.ppos + Vector2(300, 0), null), "下部署指令")
	heavy.pos = sq.station_of(heavy)
	heavy.cmd_down = 0.0
	heavy.cmd_retreat = false
	var foes: Array = []
	for k in 5:
		foes.append(_foe(heavy.pos + Vector2.from_angle(TAU * k / 5.0) * 26.0))
	g.enemies_sys.build_grid()
	Tactics.tick_block(sq)
	ok(heavy.cmd_blk.size() == Tactics.block_cap(heavy), "重装挡满阻挡数（%d / %d）" % [heavy.cmd_blk.size(), Tactics.block_cap(heavy)])
	var held := true
	for e in heavy.cmd_blk:
		held = held and e.get("aggro", Vector2.INF) == e.pos
	ok(held, "被挡住的敌人原地停步")
	_clear()
	var big := _foe(heavy.pos + Vector2(24, 0), true)
	var small := _foe(heavy.pos + Vector2(-24, 0))
	var third := _foe(heavy.pos + Vector2(0, 24))
	g.enemies_sys.build_grid()
	heavy.cmd_blk.clear()
	Tactics.tick_block(sq)
	var used := 0
	for e in heavy.cmd_blk:
		used += 2 if e.elite else 1
	ok(used <= Tactics.block_cap(heavy) and heavy.cmd_blk.size() == 2, "精英占 2 格（挡了 %d 个，占 %d）" % [heavy.cmd_blk.size(), used])
	sq.set_stance(sq.GUARD)
	Tactics.tick_block(sq)
	ok(heavy.cmd_blk.is_empty(), "离开部署全部放开")
	_clear()
	# 8. 圆盘「随行」：队友远 → 闪回集合（归队）；近 → 直接随行
	sq.set_stance(sq.ROAM)
	sniper.pos = g.ppos + Vector2(600, 0)
	sq.apply_command("guard")
	ok(sq.stance == sq.RECALL, "随行：队友离得远时先闪回集合")
	sq.set_stance(sq.ROAM)
	for o in sq.ops:
		o.pos = g.ppos + Vector2(20, 0)
	sq.apply_command("guard")
	ok(sq.stance == sq.GUARD, "随行：都在身边时直接随行")
	# 9. 连携 v2：随行挑「掩护」、突击挑「追击 / 附加」
	_clear()
	for k in 10:
		_foe(g.ppos + Vector2(150, -40 + k * 8))
	g.enemies_sys.build_grid()
	var u = g.ult
	if u != null and LinkV2.on():
		u.queue.clear()
		ok(LinkV2.lit(u, "guard", Vector2.INF), "随行：队长放技能有队友接")
		var kind_g: String = str(preload("res://scripts/run/skill_link.gd").KIND4.get(str(u.queue[0].o.id), "")) if not u.queue.is_empty() else ""
		ok(kind_g == "掩护", "随行优先掩护类（%s）" % kind_g)
		u.queue.clear()
		sq.set_stance(sq.ROAM)
		ok(LinkV2.lit(u, "roam", Vector2.INF), "突击：队长放技能有队友接")
		var kind_r: String = str(preload("res://scripts/run/skill_link.gd").KIND4.get(str(u.queue[0].o.id), "")) if not u.queue.is_empty() else ""
		ok(kind_r in ["追击", "冲阵", "附加"], "突击优先进攻类（%s）" % kind_r)
		u.queue.clear()
		ok(not u.press_e(), "v2 没有 E 键")
	sq.set_stance(sq.GUARD)
	# 10. 开关 0：圆盘回旧项、不吃弹
	Bal.sec("command")["v2"] = 0
	ok(not Tactics.on() and preload("res://scripts/screens/command_wheel.gd")._items().size() == 6, "command/v2 0：圆盘回到 6 项")
	sq.set_stance(sq.ROAM)
	sniper.pos = g.ppos + Vector2(-200, 0)
	sniper.cmd_hp = 1.0
	var bl3 := {"pos": sniper.pos + Vector2(0, -16), "life": 1.0, "r": 6.0, "dmg": 40.0, "vel": Vector2.ZERO}
	g.ebullets.append(bl3)
	sq._tick_hp(dt)
	ok(bl3.life > 0.0 and sniper.cmd_hp == 1.0, "command/v2 0：突击中不吃敌弹（旧规则）")
	Bal.sec("command")["v2"] = 1
	_done()


func _done() -> void:
	print("SQUAD V2 checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
