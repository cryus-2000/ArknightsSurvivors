extends Node
## 能天使积木（docs/61 §14）的局内单元测试：godot --headless --path game res://tests/exusiai_blocks_test.tscn -- --regression --balance --seed=1 --op=exusiai
## 把 game.tscn 当子节点跑起来，第 5 帧冻结主场景，直接调积木执行器逐条检查：校验正反例、子弹数（op_shots）、弹体命中、
## 次数型 S1（dur.ammo + attack_patch）、弹匣（verb.counter + trig.on_attack）、精英二改上限（verb.counter_cap）、
## S2 结束过热（end + verb.attack_lock）、S3 连射（burst + last_on_hit 的 st.pause）、跳弹节点、没有跳弹时不碰 g.rng、老数据干员不受影响、
## 各模式的弹药颜色（tex / muzzle_fx / hit_fx，docs/25 §6.1）与帧条登记。
## 全部通过时打印 "EXUSIAI BLOCKS failures=0"。

const OB = preload("res://scripts/characters/op_blocks.gd")
const Ch = preload("res://scripts/characters/character.gd")

var game: Node
var frames := 0
var n := 0
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
	test_validate()
	var o = game.squad.get_op("exusiai")
	ok(o != null, "能天使在编队里（--op=exusiai）")
	if o != null:
		test_runtime(o)
	test_old_data_op()
	print("%d checks, %d failed" % [n, fails])
	print("EXUSIAI BLOCKS failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.001) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


func spawn(pos: Vector2, hp := 99999.0) -> Dictionary:
	var e: Dictionary = game.spawner.spawn_enemy("runner", pos)
	e.hp = hp
	e.max_hp = hp
	game.enemies_sys.build_grid()
	return e


func clear_enemies() -> void:
	for e in game.enemies:
		e.dead = true
	game.enemies = []
	game.enemies_sys.build_grid()


## 弹体推进到全部落地（或超时）
func run_bullets(o, max_t := 2.0) -> void:
	var t := 0.0
	while t < max_t and not o.ext.get("bul", []).is_empty():
		OB.exu_tick(o, 1.0 / 60.0)
		game.enemies_sys.build_grid()
		t += 1.0 / 60.0


# ---------------------------------------------------------------- 校验（docs/61 §8 + §11）

func test_validate() -> void:
	var d: Dictionary = Ch.load_def("exusiai")
	ok(d.has("blocks") and Ch.validate_operator("exusiai", d), "能天使 JSON 通过积木校验")
	var bads := {
		"普攻弹道缺 shots": func(x): x.blocks.attack.erase("shots"),
		"trig.on_attack 缺 counter": func(x): x.blocks.talent[1].erase("counter"),
		"dur.ammo 多了别的键": func(x): x.blocks.skills[0]["dur"] = {"ammo": 6, "t": 1},
		"attack_patch 不认识的键": func(x): x.blocks.skills[2].attack_patch["bogus"] = 1,
		"跳弹来源没登记": func(x): x.blocks.progression.ricochet["src"] = "没登记",
		"常驻 counter_cap 放进技能 do": func(x): x.blocks.skills[1].do.append({"verb": "counter_cap", "name": "mag", "value": 3}),
		"st.pause 时长超出范围": func(x): x.blocks.skills[2].attack_patch.last_on_hit[0]["dur"] = 5,
		"瞬时弹道放进常驻节点": func(x): x.blocks.progression["twin"] = {"shape": "projectile", "src": "速射"},
		"计数器缺 cap": func(x): x.blocks.talent[0].do[0].erase("cap"),
		"子弹数超出夹紧": func(x): x.blocks.attack["shots"] = 40,
		"attack_patch 配瞬发技能": func(x): x.blocks.skills[2]["dur"] = 0,
		"muzzle 写错": func(x): x.blocks.attack["muzzle"] = [30],
		"attack_patch.tex 不是帧条名": func(x): x.blocks.skills[1].attack_patch["tex"] = 3,
		"hit_fx 前缀不对": func(x): x.blocks.attack["hit_fx"] = "proj_exusiai_bullet",
	}
	for why in bads:
		var d2: Dictionary = d.duplicate(true)
		bads[why].call(d2)
		ok(not Ch.validate_operator("exusiai", d2), "积木校验应拒绝：" + why)
	# 弹药颜色：JSON 里写到的帧条都在 V6_FRAMES 登记、贴图读得到
	var names: Array = []
	var blks: Array = [d.blocks.attack] + d.blocks.talent[1].do
	for sk in d.blocks.skills:
		if sk.has("attack_patch"):
			blks.append(sk.attack_patch)
	for b in blks:
		for k in ["tex", "muzzle_fx", "hit_fx"]:
			if b.has(k):
				names.append(str(b[k]))
	ok(names.size() == 13, "JSON 写了 13 处弹药帧条（实际 %d）" % names.size())
	for nm in names:
		ok(game.V6_FRAMES.has(nm) and game.tex.get(nm) != null, "帧条已登记且读得到：" + nm)


## 最近一次 spawn_fx_sprite 播的帧条名（枪口焰）
func last_fx() -> String:
	return str(game.fx[-1].get("name", "")) if not game.fx.is_empty() else ""


# ---------------------------------------------------------------- 运行时

func test_runtime(o) -> void:
	clear_enemies()
	o.pos = game.ppos + Vector2(-40, 0)
	o.face = 1.0
	o.cd = 0.0
	o.attack_t = 0.0
	var a: Dictionary = o.B.attack
	# 1. 单发 → op_shots +1.0 → 两发打两个不同目标
	var e1 := spawn(o.pos + Vector2(140, 0))
	var e2 := spawn(o.pos + Vector2(200, 30))
	var st: Dictionary = OB.exu_st(o)
	OB.exu_fire(o, a)
	ok(st.bul.size() == 1, "基础 1 发（实际 %d）" % st.bul.size())
	ok(str(st.bul[0].src) == "速射", "普攻子弹来源 = 速射")
	ok(str(st.bul[0].tex) == "proj_exusiai_bullet" and str(st.bul[0].hfx) == "fx_exusiai_hit" and last_fx() == "fx_exusiai_muzzle", "普攻：红弹体 / 红命中 / 红枪口焰")
	var mz: Vector2 = o.pos + Vector2(30, -35)
	ok(st.bul[0].p.distance_to(mz) < 0.01, "子弹从枪口出（脚底 +30, −35）")
	var d_basic: float = st.bul[0].dmg
	near(d_basic, o.base("atk", 0.0) * float(o.loc.dmg) * o._dmg_bonus(), "普攻伤害 = atk × 局部倍率 × 通用倍率")
	st.bul.clear()
	game.stats.add(&"op_shots", "add", 1.0, "exu_test", "op:exusiai")
	OB.exu_fire(o, a)
	ok(st.bul.size() == 2, "op_shots +1.0 → 每次射击 2 发（实际 %d）" % st.bul.size())
	if st.bul.size() == 2:
		var a0: float = st.bul[0].v.angle()
		var a1: float = st.bul[1].v.angle()
		ok(absf(a0 - a1) > 0.05, "两发各自瞄准不同目标")
	game.stats.remove_source("exu_test")
	# 2. 弹体命中：敌人掉血、子弹消失、没穿透
	var hp0: float = e1.hp
	st.bul.clear()
	OB.exu_fire(o, a)
	var rng0 = game.rng.state
	run_bullets(o)
	ok(e1.hp < hp0, "子弹命中掉血（%.1f → %.1f）" % [hp0, e1.hp])
	ok(float(e1.kb.x) > 0.0, "子弹沿弹道方向轻微击退（kb.x = %.1f）" % float(e1.kb.x))
	ok(st.bul.is_empty(), "子弹打完穿透次数或飞完射程后消失")
	ok(game.rng.state == rng0, "没有跳弹节点时弹体结算不碰 g.rng")
	# 3. S1 次数型：装填 6 发，每发 ×1.8 × 技能强度、穿透 1，打完为止
	o.cur_skill = 0
	o._release_skill()
	ok(int(st.ammo[0]) == 6 and is_equal_approx(o.skill_active_left(0), 6.0), "S1 装填 6 发，HUD 剩余 6")
	near(o.skill_active_dur(0), 6.0, "S1 HUD 总数 6")
	st.bul.clear()
	OB.exu_fire(o, a)
	ok(int(st.ammo[0]) == 5, "射一发扣一发（剩 %d）" % int(st.ammo[0]))
	if not st.bul.is_empty():
		ok(str(st.bul[0].src) == "冲锋模式" and int(st.bul[0].pierce) == int(o.base("s1_pierce", -1.0)), "强力弹：来源冲锋模式、穿透 s1_pierce")
		near(st.bul[0].dmg / d_basic, 1.8 * o.skill_power(), "强力弹伤害 ×1.8 × 技能强度")
		ok(str(st.bul[0].tex) == "proj_exusiai_bullet_s1" and str(st.bul[0].hfx) == "fx_exusiai_hit_s1", "强力弹换冰青弹体与命中")
		ok(last_fx() == "fx_exusiai_muzzle_s1", "次数型补丁的枪口焰跟第一发走：冰青（实际 %s）" % last_fx())
	st.ammo[0] = 0
	st.bul.clear()
	# 4. 弹匣：精一后击杀 +1，灯光里 +2，别人的击杀不算；满 8 下一次射击换成 8 发扇形倾泻并清空
	o.elite = 1
	st.cnt.clear()
	o.log_hit("速射")
	o.on_kill({"pos": game.ppos + Vector2(3000, 0), "elite": false, "boss": false})
	near(float(st.cnt.get("mag", 0.0)), 1.0, "灯光外击杀 +1")
	o.on_kill({"pos": game.ppos + Vector2(10, 0), "elite": false, "boss": false})
	near(float(st.cnt.get("mag", 0.0)), 3.0, "灯光里击杀 +2")
	game.hit = {"src": "别人", "op": "siege"}
	o.on_kill({"pos": game.ppos, "elite": false, "boss": false})
	near(float(st.cnt.get("mag", 0.0)), 3.0, "别人的击杀不喂弹匣")
	near(float(st.cap.get("mag", 0.0)), 8.0, "精一弹匣上限 8")
	st.cnt["mag"] = 8.0
	OB.exu_fire(o, a)
	ok(st.bul.size() == 8, "弹匣满：倾泻 8 发（实际 %d）" % st.bul.size())
	ok(st.bul.all(func(b): return str(b.src) == "弹匣倾泻" and int(b.pierce) == 1), "倾泻：来源弹匣倾泻、穿透 1，不再另射普攻")
	ok(st.bul.all(func(b): return str(b.tex) == "proj_exusiai_bullet_power" and str(b.hfx) == "fx_exusiai_hit_gold") and last_fx() == "fx_exusiai_muzzle_gold", "倾泻：金弹体 / 金命中 / 金枪口焰")
	near(float(st.cnt.get("mag", -1.0)), 0.0, "倾泻后弹匣清空")
	if st.bul.size() == 8:
		var spread: float = absf(st.bul[0].v.angle() - st.bul[7].v.angle())
		near(spread, deg_to_rad(50.0), "倾泻扇形 ±25°", 0.01)
	st.bul.clear()
	# 5. 精英二「天使的祝福」（docs/91 §2，10-13 起取代子弹数 +1）：子弹数不变、弹匣上限 12；精一「穿甲连射」的叠层（st.stack）照常生效
	o.elite = 2
	o._sustain(0.0)
	near(o.stat(&"op_shots"), 1.0, "精英二不再加子弹（天使的祝福改给队友攻速）")
	ok(o.el.get("stack_on", []).size() == 1, "精一起穿甲连射（st.stack）生效")
	o.log_hit("速射")
	o.on_kill({"pos": game.ppos + Vector2(3000, 0), "elite": false, "boss": false})
	near(float(st.cap.get("mag", 0.0)), 12.0, "精英二弹匣上限 12（verb.counter_cap）")
	st.cnt["mag"] = 0.0
	# 6. S2：结束时过热 1 秒不普攻（end + verb.attack_lock）
	o.cur_skill = 1
	o._release_skill()
	near(o.s_t[1], 8.0, "S2 持续 8 秒")
	o._sustain(0.0)
	near(float(o.loc.interval), 0.20 / 0.35, "S2 射击间隔 0.35 → 0.20", 0.0001)
	st.bul.clear()
	OB.exu_fire(o, a)
	ok(not st.bul.is_empty() and st.bul.all(func(b): return str(b.tex) == "proj_exusiai_bullet_s2" and str(b.hfx) == "fx_exusiai_hit_s2" and str(b.src) == "速射"), "S2：琥珀橙弹体 / 命中，来源仍是速射")
	ok(last_fx() == "fx_exusiai_muzzle_s2", "S2 枪口焰琥珀橙")
	st.bul.clear()
	OB.exu_tick(o, 0.0)
	o.s_t[1] = 0.0
	OB.exu_tick(o, 0.0)
	near(float(st.lock), 1.0, "S2 结束：过热 1 秒")
	ok(o.no_attack, "过热期间不普攻")
	OB.exu_tick(o, 1.1)
	ok(float(st.lock) == 0.0, "过热结束")
	# 7. S3：每次射击 4 连射（同一轮间隔 0.06），每发 ×0.7，最后一轮带 0.2 秒停顿
	o.cur_skill = 2
	o._release_skill()
	o._sustain(0.0)
	st.bul.clear()
	OB.exu_fire(o, a)
	var per: int = st.bul.size()
	ok(per == 1, "S3 第一轮 = 子弹数（精英二 1 发，实际 %d）" % per)
	ok(st.burst.size() == 1 and int(st.burst[0].left) == 3, "S3 连射队列还剩 3 轮")
	if per > 0:
		ok(str(st.bul[0].src) == "过载模式", "S3 子弹来源 = 过载模式")
		ok(str(st.bul[0].tex) == "proj_exusiai_bullet_s3" and str(st.bul[0].hfx) == "fx_exusiai_hit_s3" and last_fx() == "fx_exusiai_muzzle_s3", "S3：过热白弹体 / 命中 / 枪口焰")
		ok(st.bul[0].on_hit.is_empty(), "前几轮不带停顿")
	var sv: Array = st.bul.duplicate()
	st.bul.clear()
	for k in 30:
		OB.exu_tick(o, 0.01)
		if st.burst.is_empty():
			break
	ok(st.burst.is_empty(), "连射 0.2 秒内打完")
	var lasts: Array = st.bul.filter(func(b): return not b.on_hit.is_empty())
	ok(lasts.size() == per and str(lasts[0].on_hit[0].get("st", "")) == "pause", "最后一轮 %d 发带停顿（实际 %d）" % [per, lasts.size()])
	o.s_t[2] = 0.0
	st.bul.clear()
	st.burst.clear()
	# 8. 停顿只对非精英
	var ep := spawn(o.pos + Vector2(60, 0))
	OB.apply_status(o, ep, {"st": "pause", "dur": 0.2})
	near(float(ep.stun), 0.2, "停顿 0.2 秒")
	ep.elite = true
	ep.stun = 0.0
	OB.apply_status(o, ep, {"st": "pause", "dur": 0.2})
	near(float(ep.stun), 0.0, "精英不吃停顿")
	ep.elite = false
	# 9. 跳弹节点：选下后常驻生效，命中时按 g.rng 判定，跳出的子弹 ×0.5、来源跳弹、不再跳
	o.on_custom_node("ricochet")
	ok(not OB._exu_active(o, "verb.ricochet").is_empty(), "跳弹节点选下后生效")
	var found := false
	for k in 12:
		st.bul.clear()
		OB.exu_fire(o, a)
		run_bullets(o, 0.6)
		for b in st.bul:
			if str(b.src) == "跳弹":
				found = true
		if found:
			break
	# 跳出的子弹可能当帧就落地：改看伤害统计里有没有跳弹
	ok(found or float(game.dmg_out.get("跳弹", 0.0)) > 0.0, "跳弹出现（12 次射击内）")
	st.bul.clear()


## 老数据干员（浊心斯卡蒂）不受本段影响：不建 ext、技能剩余照旧
func test_old_data_op() -> void:
	var sk = Ch.create(game, "skalter")
	ok(sk != null and not OB._exu_used(sk), "浊心斯卡蒂用不到能天使段")
	if sk != null:
		OB.exu_tick(sk, 0.1)
		ok(sk.ext.is_empty(), "exu_tick 不给老数据干员建状态")
		near(sk.skill_active_left(0), 0.0, "老数据干员技能剩余照旧")
