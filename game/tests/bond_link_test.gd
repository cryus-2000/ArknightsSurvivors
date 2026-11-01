extends Node
## 羁绊连携（docs/217，link/bond）：挑人（羁绊优先、群体优先、轮换、synergy 占用让路、开关 0 照 v2 挑人）、
## 8 条合击都能跑完且双方都记到伤害、队长不位移、界面标签（选人 / 招募卡点亮灰显、图鉴行）。用真游戏场景，直接调连携函数（不跑整局）。
## godot --headless --path game res://tests/bond_link_test.tscn -- --regression --balance --seed=1 --op=texas --squad=exusiai,hoshiguma
## 全部通过时打印 "BOND LINK checks=N failures=0"

const Bal = preload("res://scripts/core/balance.gd")
const Link = preload("res://scripts/run/skill_link.gd")
const LinkV2 = preload("res://scripts/run/link_v2.gd")
const Bond = preload("res://scripts/run/link_bond.gd")

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


func _swarm(c: Vector2, n := 12) -> void:
	_clear()
	for k in n:
		_foe(c + Vector2.from_angle(k * 2.39996) * (20.0 + 12.0 * k))
	g.enemies_sys.build_grid()


## 把队友换成 ids（队长不动）
func _team(ids: Array) -> void:
	var sq = g.squad
	for o in sq.ops.duplicate():
		if not o.is_leader and not ids.has(str(o.id)):
			sq.remove(str(o.id))
	for id in ids:
		if not sq.has(id):
			sq.add(id, false)
	for o in sq.ops:
		o.syn_mv = {}
		o.pos = g.ppos + Vector2(-60.0 + 30.0 * o.slot, 40.0)


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
	var u = g.ult
	var ld = sq.leader()
	ok(u != null and LinkV2.on() and Bond.on() and str(ld.id) == "texas", "连携 v2 / 羁绊开着，队长德克萨斯")
	if u == null or ld == null:
		_done()
		return
	# 1. 数据：8 条、id 唯一、合击名不重名、成员都是本作干员
	var ids := {}
	var names := {}
	for b in Link.BONDS:
		ids[str(b.id)] = true
		names[str(b.name)] = true
		for m in b.get("ops", b.get("group", [])):
			ok(FileAccess.file_exists("res://data/characters/%s.json" % m), "羁绊成员 %s 是本作干员" % m)
	ok(Link.BONDS.size() == 8 and ids.size() == 8 and names.size() == 8, "8 条羁绊、id / 合击名各不相同")
	# 2. 挑人：德克萨斯队长 + 能天使 + 星熊，随行姿态本该挑掩护类（星熊），羁绊开时改由能天使接「急件专送」
	_team(["exusiai", "hoshiguma"])
	_swarm(g.ppos + Vector2(160, 0))
	u.queue.clear()
	ok(LinkV2.lit(u, "guard", Vector2.INF), "羁绊：有队友接")
	var q0: Dictionary = u.queue[0] if not u.queue.is_empty() else {}
	ok(not q0.is_empty() and str(q0.o.id) == "exusiai" and str(q0.info.get("link", "")) == "b_penguin", "企鹅物流：能天使优先接、换急件专送（%s）" % str(q0.get("info", {}).get("link", "")))
	ok(not q0.is_empty() and q0.info.has("v2") and q0.info.from == ld, "羁绊照 v2 记姿态、来源是队长")
	u.queue.clear()
	# 开关 0：照 v2 按姿态挑（随行 = 掩护类星熊）
	Bal.sec("link")["bond"] = 0
	ok(LinkV2.lit(u, "guard", Vector2.INF) and str(u.queue[0].o.id) == "hoshiguma" and not u.queue[0].info.has("bond"), "link/bond 0：随行照旧挑星熊、没有羁绊字段")
	ok(Bond.tags_for("texas", ["exusiai"]).size() > 0 and not Bond.ui_on(), "link/bond 0：界面不列羁绊")
	Bal.sec("link")["bond"] = 1
	u.queue.clear()
	# 3. 轮换：德克萨斯同队能天使与拉普兰德，两对交替
	_team(["exusiai", "lappland"])
	var seen: Array = []
	for k in 2:
		u.queue.clear()
		g.t += 1.0
		LinkV2.lit(u, "guard", Vector2.INF)
		seen.append(str(u.queue[0].info.get("bond", "")) if not u.queue.is_empty() else "")
	ok(seen.has("b_penguin") and seen.has("b_rival"), "两对羁绊轮换（%s）" % str(seen))
	u.queue.clear()
	# 4. synergy（docs/160）的小合击正占用搭档：羁绊让路
	if sq.get("syn") is Dictionary and sq.syn.has("acts"):
		var ex = sq.get_op("exusiai")
		var lp = sq.get_op("lappland")
		sq.syn.acts.append({"p": ex})
		sq.syn.acts.append({"p": lp})
		var bd: Dictionary = Bond.pick(u, ld, [[ex, 0, -INF], [lp, 0, -INF]])
		ok(bd.is_empty(), "搭档被 synergy 占用：不走羁绊")
		sq.syn.acts.pop_back()
		sq.syn.acts.pop_back()
	# 5. 群体优先（用假的干员字典测 pick，不改编队）
	var fk := func(id: String) -> Dictionary: return {"id": id, "pos": Vector2.ZERO}
	var bh: Dictionary = Bond.pick(u, fk.call("skadi"), [[fk.call("ulpianus"), 0, -INF], [fk.call("gladiia"), 0, -INF], [fk.call("saria"), 0, -INF]])
	ok(str(bh.get("bond", {}).get("id", "")) == "b_hunt" and bh.mates.size() == 2, "≥3 名深海猎人：群猎优先、两名猎人出手")
	var b1: Dictionary = Bond.pick(u, fk.call("skadi"), [[fk.call("ulpianus"), 0, -INF], [fk.call("saria"), 0, -INF]])
	ok(str(b1.get("bond", {}).get("id", "")) == "b_lesson", "两名猎人：走对子（潮下授课）")
	ok(Bond.pick(u, fk.call("saria"), [[fk.call("texas"), 0, -INF]]).is_empty(), "队长没有羁绊：不走羁绊")
	ok(Bond.pick(u, fk.call("irene"), [[fk.call("lumen"), 0, -INF]]).get("bond", {}).get("id", "") == "b_inq", "审判庭：艾丽妮 × 流明")
	# 6. 8 条合击：都跑得完、双方都记到伤害；队长原地出手（德克萨斯队长时不位移）
	var plan := [["b_penguin", ["exusiai"], ["texas", "exusiai"]], ["b_rival", ["lappland"], ["texas", "lappland"]],
		["b_lesson", ["ulpianus", "skadi"], ["ulpianus", "skadi"]], ["b_tide", ["gladiia", "specter_unchained"], ["gladiia", "specter_unchained"]],
		["b_vortex", ["gladiia", "ulpianus"], ["gladiia", "ulpianus"]], ["b_fins", ["skadi", "specter_unchained"], ["skadi", "specter_unchained"]],
		["b_inq", ["irene", "lumen"], ["irene"]], ["b_hunt", ["skadi", "specter_unchained", "skalter"], ["skadi", "specter_unchained"]]]
	for pl in plan:
		var bid: String = pl[0]
		_team(pl[1])
		var members: Array = pl[1].map(func(id): return sq.get_op(id))
		if members.has(null):
			ok(false, "%s：编队凑不齐 %s" % [bid, str(pl[1])])
			continue
		var from = ld if pl[2].has("texas") else members[0]
		var mates: Array = members.filter(func(m): return m != from)
		var c: Vector2 = g.ppos + Vector2(170, 0)
		_swarm(c)
		var hp0: float = 0.0
		for e in g.enemies:
			hp0 += e.hp
		var b: Dictionary = Link.BONDS.filter(func(x): return str(x.id) == bid)[0]
		var info: Dictionary = Bond.info(u, b, from, c, LinkV2.area_r(), mates)
		var lp0: Vector2 = ld.pos
		var a: Dictionary = Link.fire(u, mates[0], info)
		var done := false
		for f in 240:
			g.t += 1.0 / 60.0
			for m in sq.ops:
				if not m.syn_mv.is_empty():
					m.pos = m.syn_step(1.0 / 60.0) if m.has_method("syn_step") else m.pos
			if Bond.step(u, a, 1.0 / 60.0):
				done = true
				break
		ok(done, "%s：4 秒内演完" % bid)
		var hp1: float = 0.0
		for e in g.enemies:
			hp1 += e.hp
		ok(hp1 < hp0, "%s：打出伤害" % bid)
		for who in pl[2]:
			ok(g.hit_src.has("技能连携·%s·%s" % [str(b.name), who]), "%s：%s 记到伤害来源" % [bid, who])
		if from == ld:
			ok(ld.syn_mv.is_empty() and ld.pos == lp0, "%s：队长原地出手、不位移" % bid)
		for m in sq.ops:
			m.syn_mv = {}
	# 7. 常驻加成（docs/217 §7）：成对同队挂来源 "bond"，拆开就摘；新成立记进 bond_log；开关 0 不动属性
	_team(["exusiai", "hoshiguma"])
	var asp: float = g.stats.value(&"op_aspd")
	ok(g.stats.breakdown(&"op_aspd").sources.any(func(x): return str(x.source) == "bond"), "企鹅物流成立：攻速挂了羁绊来源")
	_team(["hoshiguma", "saria"])
	ok(g.stats.value(&"op_aspd") < asp - 0.05, "能天使离队：攻速加成摘掉（%.3f → %.3f）" % [asp, g.stats.value(&"op_aspd")])
	var lg: Array = g.get_meta("bond_log", [])
	ok(lg.any(func(x): return str(x.id) == "b_penguin"), "企鹅物流记进本局羁绊")
	Bal.sec("link")["bond_buff"] = 0
	var v0: float = g.stats.value(&"op_aspd")
	_team(["exusiai", "hoshiguma"])
	ok(g.stats.value(&"op_aspd") == v0, "link/bond_buff 0：成对也不加")
	Bal.sec("link")["bond_buff"] = 1
	var seen_stat := {}
	for k in Bond.BUFF:
		seen_stat[str(Bond.BUFF[k][0])] = true
		ok(Bond.buff_text(k) != "" and not Bond.buff_text(k).contains("%%") and not Bond.buff_text(k).contains("%s"), "%s：加成文案「%s」" % [k, Bond.buff_text(k)])
	ok(Bond.BUFF.size() == 8 and seen_stat.size() == 8, "8 条加成各用不同属性")
	ok(str(Bond.tags_for("texas", ["exusiai"])[0][2]) == "全队攻速 +8%", "选人 / 招募卡小字带加成")
	var rs = preload("res://scripts/run/run_stats.gd")
	var m: Dictionary = rs.model(rs.snapshot(g))
	ok(m.stats.any(func(x): return str(x.label) == "羁绊成立"), "作战记录列出本局成立的羁绊")
	# 8. 界面：标签点亮 / 灰显、图鉴行
	var tg: Array = Bond.tags_for("texas", ["exusiai"])
	ok(tg.size() == 2 and tg[0][0] == "企鹅物流" and tg[0][1] and tg[1][0] == "宿敌" and not tg[1][1], "德克萨斯：企鹅物流点亮、宿敌灰显（%s）" % str(tg))
	var th: Array = Bond.tags_for("skadi", ["ulpianus"])
	ok(th.size() == 1 and th[0][0] == "深海猎人" and th[0][1], "深海猎人同名标签合并、有一对成立就点亮（%s）" % str(th))
	ok(Bond.tags_for("saria", ["texas"]).is_empty(), "没有羁绊的干员不列")
	for oid in ["texas", "skadi", "lumen", "skalter"]:
		var rows: Array = Bond.gallery_rows(oid)
		ok(not rows.is_empty() and rows.all(func(r): return not str(r[2]).contains("{") and str(r[2]).contains("羁绊 · ")), "%s：图鉴有羁绊行、无占位" % oid)
	ok(Bond.gallery_rows("skalter").size() == 1 and str(Bond.gallery_rows("skalter")[0][2]).contains("至少 2 人"), "浊心斯卡蒂只在群猎里，写明人数条件")
	_done()


func _done() -> void:
	print("BOND LINK checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
