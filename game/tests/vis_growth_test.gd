extends Node
## 可见成长藏品（docs/163）的回归：
##   godot --headless --path game res://tests/vis_growth_test.tscn -- --regression --balance --seed=1 --op=exusiai --squad=lappland,wisadel
## 一、曲线（纯函数 compute）：数量 ×0.7 / 尺寸 ×0.8 递减、eps 汇总 T、剑气取最强档、范围与 #81 共用曲线、副体取整、体型 / 时长。
## 二、局内：拿到前后同一段战斗——能天使多出小弹（散射 / 连发）、拉普兰德多出剑气且范围变大、维什戴尔魂灵之影多 1 个副体（伤害 ×0.6）、
##     Mon3tr 不 +1、凯尔希（没有普攻弹体的远程）改为伤害 ×T、手机低画质档同屏上限生效（超出的并入直接伤害）、旋钮 0 退回旧数值。
## 全部通过时打印 "VIS GROWTH failures=0"。

const DT := 1.0 / 60.0
const Bal = preload("res://scripts/core/balance.gd")
const VG = preload("res://scripts/characters/blocks/vis_growth.gd")
const RelicDb = preload("res://scripts/core/relic_db.gd")

var fails := 0
var n := 0


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func near(a: float, b: float, what: String, eps := 0.001) -> void:
	ok(absf(a - b) < eps, "%s（期望 %s，实际 %s）" % [what, b, a])


func _ready() -> void:
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	test_curves(g.rfx.db)
	test_legacy()
	await test_live(g)
	print("%d checks, %d failed" % [n, fails])
	print("VIS GROWTH failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func test_curves(db) -> void:
	var s: Dictionary = VG.compute({"58": 1}, db)
	near(s.e_scatter, 1.0, "银餐叉 1 层：额外 1 发")
	near(s.t_shots, 1.15, "银餐叉 1 层：额外弹部分 ×1.15（eps 0.15；另有远程伤害 +10% 属性，合计同旧稿 25%）")
	s = VG.compute({"58": 1, "59": 1}, db)
	near(s.e_shots, 1.7, "散射 + 连发：E = 1 + 0.7")
	near(s.e_burst, 1.0, "eps 大的连发排第一层（与获得顺序无关）")
	near(s.e_scatter, 0.7, "散射排第二层 ×0.7")
	near(s.t_shots, 1.0 + 0.25 + 0.15 * 0.7, "T = 1 + Σ eps·w")
	s = VG.compute({"58": 3, "59": 3}, db)
	near(s.e_shots, 1.0 + 0.7 + 0.49 + 0.343 + 0.2401 + 0.16807, "6 层 E 渐近不封顶")
	s = VG.compute({"63": 1, "56": 1}, db)
	near(s.e_qi, 1.7, "两件剑气：道数 1 + 0.7")
	near(s.qi_mult, 0.6, "剑气按锋芒档 60%")
	ok(int(s.qi_hits) == 2, "锋芒：可命中 2 名")
	s = VG.compute({"63": 1}, db)
	near(s.qi_mult, 0.35, "锈蚀刀片：剑气 35%")
	ok(int(s.qi_hits) == 1, "锈蚀刀片：命中 1 名后消失")
	s = VG.compute({"64": 1}, db)
	near(s.range, 0.18, "长鞭 1 层：范围 +18%")
	s = VG.compute({"64": 2}, db)
	near(s.range, 0.18 + 0.18 * 0.8, "长鞭 2 层：+18% + 14.4%")
	s = VG.compute({"64": 1, "81": 1}, db)
	near(s.range, 0.18 * 0.8, "已有漆黑的舞鞋：长鞭从第 2 层算（×0.8）")
	s = VG.compute({"129": 1}, db)
	ok(int(s.sub_n) == 1, "散轶诗简 1 层：副体 1")
	s = VG.compute({"129": 2}, db)
	ok(int(s.sub_n) == 1, "2 层：E 1.7 → 副体仍 1（向下取整）")
	s = VG.compute({"129": 3}, db)
	ok(int(s.sub_n) == 2, "3 层：E 2.19 → 副体 2")
	s = VG.compute({"130": 1}, db)
	near(s.size, 1.15, "衍生者终端：体型 +15%")
	near(s.life, 1.2, "衍生者终端：时长 +20%")
	s = VG.compute({}, db)
	ok(s.e_shots == 0.0 and s.e_qi == 0.0 and s.range == 0.0 and int(s.sub_n) == 0 and s.size == 1.0, "不持有：全部为零")
	var v := {"a": 0.0}
	var tot := 0
	for i in 10:
		tot += VG._take(v, "a", 0.7)
	ok(tot == 7, "累加器：E 0.7 × 10 次 = 7 发（实际 %d）" % tot)
	for id in ["58", "59", "63", "56", "64", "129"]:
		var r: Dictionary = db.get_relic(id)
		ok(int(r.get("max_lv", 0)) == 3, "#%s 仍可叠到 3 级" % id)
		ok(str(r.desc).contains("每多一层，增益递减"), "#%s 卡面写「每多一层，增益递减」" % id)
	ok(str(db.get_relic("129").desc).contains("Mon3tr 不增加数量"), "#129 卡面写明 Mon3tr 例外")


## 旋钮 relic/visible_growth = 0：载入 legacy（旧数值、旧说明、旧等级上限）
func test_legacy() -> void:
	if not Bal._data.has("relic"):
		Bal._data["relic"] = {}
	Bal._data["relic"]["visible_growth"] = 0
	var db0 = RelicDb.new()
	db0.load_files()
	Bal._data["relic"]["visible_growth"] = 1
	var r: Dictionary = db0.get_relic("58")
	ok(r.effects.size() == 1 and str(r.effects[0].get("stat", "")) == "ranged_dmg", "旋钮 0：银餐叉退回远程伤害 +20%")
	ok(not str(r.desc).contains("散射"), "旋钮 0：说明退回旧版")
	near(VG.compute({"58": 3, "63": 1, "129": 1}, db0).e_shots, 0.0, "旋钮 0：没有任何可见成长效果")


func step(g, frames: int) -> void:
	for f in frames:
		g._update(DT)


func setup_field(g) -> void:
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	var c: Vector2 = g.ppos
	for k in 10:
		var e: Dictionary = g.spawner.spawn_enemy("stone", c + Vector2(110 + (k % 5) * 26, (k / 5 - 0.5) * 70 + (k % 3 - 1) * 14))
		e.hp = 1.0e9
		e.max_hp = 1.0e9
		e.speed = 0.0
	g.enemies_sys.build_grid()


func test_live(g) -> void:
	g.state = g.S.PLAY
	g.t = 60.0
	g.invuln = 1.0e9
	g.xp_need = 1.0e12
	var exu = g.squad.get_op("exusiai")
	var lap = g.squad.get_op("lappland")
	var wis = g.squad.get_op("wisadel")
	if g.squad.get_op("kaltsit") == null:
		g.squad.extra_slot = true   # 编队常规上限 3：第 4 位开额外槽（同罐头藏品）
		g.squad.add("kaltsit")
	var kal = g.squad.get_op("kaltsit")
	ok(exu != null and lap != null and wis != null and kal != null, "编队：能天使 / 拉普兰德 / 维什戴尔 / 凯尔希（--op / --squad）")
	if exu == null or lap == null or wis == null or kal == null:
		return
	for o in g.squad.ops:
		o.sp = [-1.0e9, -1.0e9, -1.0e9]   # 不放技能，只看普攻
		o.pos = g.ppos + Vector2(-10, 0)
	wis.elite = 2
	wis.refresh_stats()
	setup_field(g)
	step(g, 240)
	ok(exu.vg.is_empty() and lap.vg.is_empty(), "不持有：干员不建可见成长状态（vg 空）")
	var souls0: int = wis.hw.get("wd", {}).get("souls", []).size()
	ok(souls0 == 2, "维什戴尔精二：魂灵之影 2 个（实际 %d）" % souls0)
	var lap_r0: float = lap.stat(&"op_range")
	var exu_r0: float = exu.stat(&"op_range")
	var kal_d0: float = kal.stat(&"dmg")
	var exu_d0: float = exu.stat(&"dmg")
	# ---- 远程：散射 + 连发
	ok(g.progression.gain_relic("58"), "获得银餐叉")
	ok(g.progression.gain_relic("59"), "获得损坏的左轮弹巢")
	near(kal.stat(&"dmg") / kal_d0, 1.355, "凯尔希（没有普攻弹体）：伤害 ×T（远程伤害 +10% 另由属性给）")
	near(exu.stat(&"dmg") / exu_d0, 1.0, "能天使（吃弹）：不加直接伤害")
	var atk0: int = exu.atk_n
	step(g, 300)
	var vs: Dictionary = exu.vg
	ok(not vs.is_empty() and int(vs.n_shots) > 0, "能天使：拿到后有额外弹（%d）" % int(vs.get("n_shots", 0)))
	var vw: Dictionary = wis.vg
	ok(not vw.is_empty() and int(vw.n_shots) > 0, "维什戴尔：炮击也带额外弹（%d）" % int(vw.get("n_shots", 0)))
	ok(lap.vg.is_empty() or int(lap.vg.n_shots) == 0, "拉普兰德（近战）：不射额外弹")
	# 每次普攻额外发数 = E 的累加：两件 E = 1.7，统计 300 帧里的比值
	var per: float = float(vs.n_shots) / maxf(1.0, float(exu.atk_n - atk0))
	ok(per > 1.2 and per < 2.2, "能天使：每次普攻额外 ≈1.7 发（实际 %.2f）" % per)
	# ---- 近战：剑气 + 范围
	ok(g.progression.gain_relic("63"), "获得锈蚀刀片")
	ok(g.progression.gain_relic("64"), "获得赶车夫的长鞭")
	near(lap.stat(&"op_range") / lap_r0, (lap_r0 + 0.18) / lap_r0, "拉普兰德：攻击范围 +18%（与其他加成相加）")
	near(exu.stat(&"op_range"), exu_r0, "能天使（远程）：范围不变")
	step(g, 300)
	var vl: Dictionary = lap.vg
	ok(not vl.is_empty() and int(vl.n_qi) > 0, "拉普兰德：拿到后普攻带剑气（%d 道）" % int(vl.get("n_qi", 0)))
	ok(exu.vg.n_qi == 0, "能天使（远程）：没有剑气")
	# ---- 召唤物：副体、Mon3tr 例外
	ok(g.progression.gain_relic("129"), "获得散轶诗简")
	ok(g.progression.gain_relic("130"), "获得衍生者终端-超级改")
	ok(VG.summon_subs(g, "mon3tr") == 0, "Mon3tr 例外：数量不 +1")
	ok(VG.summon_subs(g, "soul") == 1, "其他召唤物：副体 +1")
	ok(VG.summon_subs(g, "stake") == 1, "水月触手桩：在场上限 +1")
	near(VG.summon_scale(g), 1.15, "召唤物体型 ×1.15")
	step(g, 30)
	var souls: Array = wis.hw.get("wd", {}).get("souls", [])
	ok(souls.size() == 3, "维什戴尔：魂灵之影 2 → 3（实际 %d）" % souls.size())
	ok(souls.size() == 3 and souls[2].get("sub", false) and not souls[0].get("sub", false), "第 3 个是副体，本体不是")
	ok(kal.sm.is_empty() or kal.sm.list.filter(func(q): return str(q.kind) == "mon3tr").size() <= 1, "Mon3tr 仍只有 1 只")
	# ---- 手机降级：低画质档同屏额外弹上限
	var q0: String = Cfg.quality
	Cfg.quality = "low"
	if not Bal._data.has("vgrowth"):
		Bal._data["vgrowth"] = {}
	var caps = Bal._data["vgrowth"].get("cap_shots", [64, 32, 16])
	Bal._data["vgrowth"]["cap_shots"] = [64, 32, 2]
	exu.vg.n_merged = 0
	var cap_ok := true
	for f in 240:
		g._update(DT)
		var live: int = 0
		for o in g.squad.ops:
			if not o.vg.is_empty():
				live += o.vg.bul.size()
		if live > 2:
			cap_ok = false
	ok(cap_ok, "低画质档：同屏额外弹不超过上限 2")
	ok(int(exu.vg.n_merged) + int(wis.vg.n_merged) > 0, "超出上限的额外弹并入直接伤害（%d）" % (int(exu.vg.n_merged) + int(wis.vg.n_merged)))
	Bal._data["vgrowth"]["cap_shots"] = caps
	Cfg.quality = q0
