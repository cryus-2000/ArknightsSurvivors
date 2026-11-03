## 羁绊连携（连携 v2 第二期，docs/217；开关 balance link/bond，缺省 1，0 = 完全不求值，回到 v2 按姿态挑人）：
## 队长放技能触发 v2 连携时，队里有和队长有原作关系的队友 → 优先由他接，换成这对人的专属合击（配对表 skill_link.BONDS）。
## 两人都出手：队长原地出一招（不位移、不扣技力、不打断普攻），队友按自己的方式进场；配对对称，谁当队长谁原地出手。
## 伤害走 skill_link._dmg（v2 的按目标生命预算）× link/bond_mult；不抽随机数（多对同时满足时群体优先，其余「最久没接过」轮换）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Link = preload("res://scripts/run/skill_link.gd")
const LFA = preload("res://scripts/run/link_fx_a.gd")   # 乌尔比安锚链的放开版画法（ulpianus_fly / pin / hold，开关 fx/px_unleashed）

const HUNT_MAX := 3
const DIM := Color(0.5, 0.53, 0.56)   # 羁绊未成立（搭档不在队）的灰显色
## 常驻加成（协调人 11-01 追加，用户批准）：羁绊成立（成对两人 / 群猎 ≥ 3 人同在编队）时全队得一个和关系相符的被动，量级约一张普通升级卡；
## 8 条各一个属性、不重复。[属性, 修正方式, 旋钮 link/bond_buff_<键>, 缺省值, 文案（%s = 百分数）]
const BUFF := {
	"b_penguin": [&"op_aspd", "add", "penguin", 0.08, "全队攻速 +%s%%"],
	"b_rival": [&"elite_dmg", "add", "rival", 0.10, "对精英伤害 +%s%%"],
	"b_lesson": [&"op_skill_sp", "add", "lesson", 0.08, "全队技力回复 +%s%%"],
	"b_tide": [&"control_dur", "add", "tide", 0.15, "控制持续时间 +%s%%"],
	"b_vortex": [&"enemy_speed", "mult", "vortex", -0.05, "敌人移动速度 -%s%%"],
	"b_fins": [&"move_speed", "add", "fins", 0.06, "移动速度 +%s%%"],
	"b_inq": [&"boss_dmg", "add", "inq", 0.10, "对 Boss 伤害 +%s%%"],
	"b_hunt": [&"dmg_taken", "mult", "hunt", -0.06, "全队受到伤害 -%s%%"],
}   # 群猎：除队长外最多几名猎人出手


static func on() -> bool:
	return Bal.vi("link/bond", 1) > 0


static func buff_on() -> bool:
	return on() and Bal.vi("link/bond_buff", 1) > 0


static func buff_v(bid: String) -> float:
	var bf: Array = BUFF.get(bid, [])
	return Bal.v("link/bond_buff_" + str(bf[2]), float(bf[3])) if not bf.is_empty() else 0.0


## 加成文案，例「全队攻速 +8%」
static func buff_text(bid: String) -> String:
	var bf: Array = BUFF.get(bid, [])
	if bf.is_empty():
		return ""
	return str(bf[4]) % str(snappedf(absf(buff_v(bid)) * 100.0, 0.1)).trim_suffix(".0")


## 编队 ids 下成立的羁绊（按表序）
static func formed(ids: Array) -> Array:
	var out: Array = []
	for b in Link.BONDS:
		var mem: Array = b.get("ops", b.get("group", []))
		var n: int = mem.filter(func(m): return ids.has(m)).size()
		if n >= int(b.get("min", 2)):
			out.append(b)
	return out


## 编队变化（squad._add / remove）：按成立的羁绊重挂全队加成（来源 "bond"）；新成立的闪一次「羁绊成立」+ 轻提示音、记进作战记录。
## link/bond_buff 0 时什么都不做（同 seed TRACE 不变）
static func refresh(g) -> void:
	if not buff_on() or g.stats == null or not g.stats.has_stat(&"op_aspd"):
		return
	var ids: Array = g.squad.ops.map(func(p): return str(p.id))
	var fm: Array = formed(ids)
	g.stats.remove_source("bond")
	for b in fm:
		var bf: Array = BUFF.get(str(b.id), [])
		if bf.is_empty() or not g.stats.has_stat(bf[0]):
			continue
		var v: float = buff_v(str(b.id))
		g.stats.add(bf[0], bf[1], (1.0 + v) if str(bf[1]) == "mult" else v, "bond")
	g.sync_stats()
	var log: Array = g.get_meta("bond_log", [])
	var had := {}
	for x in log:
		had[str(x.id)] = true
	for b in fm:
		if had.has(str(b.id)):
			continue
		log.append({"id": str(b.id), "tag": str(b.tag), "name": str(b.name), "t": snappedf(g.t, 0.1)})
		if g.get("vfx") != null and g.demo_op == "":
			g.vfx.show_banner("羁绊成立 · %s：%s" % [str(b.tag), buff_text(str(b.id))], 1)
			var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
			if sfx != null:
				sfx.play("ui_ok", -6.0, 1.1)
	g.set_meta("bond_log", log)


## 界面提示（选人页 / 招募卡 / 图鉴）：羁绊挂在连携 v2 上，v2 关时不列
static func ui_on() -> bool:
	return on() and Bal.vi("link/v2", 1) > 0


## 某干员参与的羁绊（图鉴 / 选人页 / 招募卡用）：[{bond, mates: [搭档 id…]}]
static func of(oid: String) -> Array:
	var out: Array = []
	for b in Link.BONDS:
		var ids: Array = b.get("ops", b.get("group", []))
		if ids.has(oid):
			out.append({"bond": b, "mates": ids.filter(func(x): return x != oid)})
	return out


## 和这些干员同队时成立的羁绊标签（去重，按表序）：[[标签, 是否成立]]；ids = 当前编队
static func tags_for(oid: String, ids: Array) -> Array:
	var out: Array = []
	var seen := {}
	for r in of(oid):
		var b: Dictionary = r.bond
		var n: int = 0
		for m in r.mates:
			if ids.has(m):
				n += 1
		var ok: bool = n >= int(b.get("min", 2)) - 1
		var tag: String = str(b.tag)
		var bt: String = buff_text(str(b.id)) if buff_on() else ""
		if seen.has(tag):   # 同名羁绊（深海猎人）合并：任一条成立就点亮，加成文案并列
			var row: Array = out[int(seen[tag])]
			if ok:
				row[1] = true
			if bt != "":
				row[2] = (str(row[2]) + "，" if str(row[2]) != "" else "") + bt
			continue
		seen[tag] = out.size()
		out.append([tag, ok, bt])
	return out


## 从 v2 已筛好、已排序的候选里挑羁绊接手；返回 {} 表示没有（照普通 v2 挑人）。
## cands = link_v2.lit 的 [[p, rank, last], …]；不改任何状态
static func pick(u, ld, cands: Array) -> Dictionary:
	var lid: String = str(ld.id)
	var free: Array = []
	var syn = u.g.squad.get("syn")
	for c in cands:
		var p = c[0]
		if syn is Dictionary and syn.has("acts") and syn.acts.any(func(x): return x.get("p") == p):
			continue   # docs/160 的小合击正占用他：羁绊让路
		free.append(p)
	var best := {}
	var best_t := INF
	for b in Link.BONDS:
		if b.has("group"):
			if not b.group.has(lid):
				continue
			var mates: Array = free.filter(func(p): return b.group.has(str(p.id)))
			if mates.size() >= int(b.get("min", 3)) - 1:
				return {"bond": b, "p": mates[0], "mates": mates.slice(0, HUNT_MAX)}   # 群体优先
			continue
		if not b.ops.has(lid):
			continue
		var oid: String = str(b.ops[1] if str(b.ops[0]) == lid else b.ops[0])
		for p in free:
			if str(p.id) == oid:
				var lt: float = float(u.get_meta("lb_" + str(b.id), -INF))
				if lt < best_t:
					best_t = lt
					best = {"bond": b, "p": p, "mates": [p]}
	return best


static func info(u, b: Dictionary, ld, pos: Vector2, r: float, mates: Array) -> Dictionary:
	u.set_meta("lb_" + str(b.id), u.g.t)
	u.stats["bond_" + str(b.id)] = int(u.stats.get("bond_" + str(b.id), 0)) + 1
	return {"link": str(b.id), "bond": str(b.id), "from": ld, "pos": pos, "r": r, "skill": -1, "mates": mates}


static var _names := {}


## 干员显示名（data/characters/<id>.json 的 name），界面列搭档用
static func op_name(oid: String) -> String:
	if not _names.has(oid):
		var p := "res://data/characters/%s.json" % oid
		var j = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
		_names[oid] = str(j.get("name", oid)) if j is Dictionary else oid
	return str(_names[oid])


## 图鉴连携栏的一段：「合击」名 + 说明 + 羁绊名 / 搭档 / 条件
static func gallery_rows(oid: String) -> Array:
	var out: Array = []
	for r in of(oid):
		var b: Dictionary = r.bond
		var who: String = "、".join(r.mates.map(func(m): return op_name(str(m))))
		var cond: String = ("与%s中至少 %d 人同队" % [who, int(b.get("min", 3)) - 1]) if b.has("group") else ("与%s同队" % who)
		var bt: String = ("同队期间%s；" % buff_text(str(b.id))) if buff_on() else ""
		out.append([str(b.name), str(b.tag), "%s。\n羁绊 · %s：%s时，%s队长放技能触发的连携优先由羁绊成员接手，换成这招合击。" % [str(b.desc), str(b.tag), cond, bt]])
	return out


static func bond_name(id: String) -> String:
	for b in Link.BONDS:
		if str(b.id) == id:
			return str(b.name)
	return ""


# ================================================================ 出手

static func _hit(p, e, nm: String, mult: float) -> void:
	Link._hit16(p, e, nm, mult * Bal.v("link/bond_mult", 1.0))


static func _ok(p) -> bool:
	return p != null and p.pos != Vector2.INF


## 按干员 id 在本次合击的两方里找人（队长 / 搭档）
static func _who(a: Dictionary, oid: String):
	var ld = a.from
	if ld != null and str(ld.id) == oid:
		return ld
	for m in a.get("mates", [a.p]):
		if str(m.id) == oid:
			return m
	return null


static func _col(u, p) -> Color:
	return Link._lc(u, p) if p != null else Color.WHITE


## 进场或原地：非队长冲到 to（dur 秒，期间无敌）；队长不动，画一道从脚下射向 to 的刃光。返回起点
static func _go(u, p, to: Vector2, dur: float, col: Color) -> Vector2:
	var fp: Vector2 = p.pos
	if p.is_leader:
		p._set_face(1.0 if to.x >= fp.x else -1.0, true)
		p.play_vis_anim("attack")
		u.shape({"kind": "blade", "a": fp + Vector2(0, -16), "b": to, "w": 5.0, "col": Color(1, 1, 1, 0.95), "glow": col, "grow": 0.04, "life": 0.35})
		u.light(fp, 110.0, col, 0.25)
	else:
		Link._dash(p, to, dur)
	return fp


## 主目标：精英 / Boss 优先，否则离中心最近
static func _tp(u, a: Dictionary) -> Vector2:
	if not a.has("tg"):
		a["tg"] = Link._main(u, a.pos, float(a.r))
	var tg: Variant = a.tg
	return tg.pos if tg != null and not tg.dead else Vector2(a.pos)


static func _sfx(u, k := "hit", db := -4.0, pitch := 1.2) -> void:
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play(k, db, pitch)


## 每帧；true = 结束（结束时清掉群猎里其余猎人的冲刺位移，a.p 的由 ult 清）
static func step(u, a: Dictionary, dt: float) -> bool:
	a.age = float(a.age) + dt
	var t0: float = a.age
	if t0 < Link.PRE:
		for m in a.get("mates", [a.p]):
			if _ok(m):
				Link._appear(u, m, t0)
		var ld = a.from
		if _ok(ld) and not a.done.has("ldl"):
			a.done["ldl"] = true
			u.light(ld.pos, 120.0, _col(u, ld), 0.3)
		return false
	var t: float = t0 - Link.PRE
	var end: bool = true
	match str(a.link):
		"b_penguin":
			end = _penguin(u, a, t)
		"b_rival":
			end = _rival(u, a, t)
		"b_lesson":
			end = _lesson(u, a, t)
		"b_tide":
			end = _tide(u, a, t)
		"b_vortex":
			end = _vortex(u, a, t)
		"b_fins":
			end = _fins(u, a, t)
		"b_inq":
			end = _inq(u, a, t)
		"b_hunt":
			end = _hunt(u, a, t)
	if end:
		for m in a.get("mates", []):
			if m != a.p and m != null and not m.syn_mv.is_empty():
				m.syn_mv = {}
	return end


static func _once(a: Dictionary, k: String) -> bool:
	if a.done.has(k):
		return false
	a.done[k] = true
	return true


## B1 急件专送（德克萨斯 × 能天使）：能天使朝区域打 8 发穿透曳光；第 4 发起德克萨斯一侧 6 把剑从区域上空落下（剑身德克萨斯色、带能天使曳光），落地小爆
static func _penguin(u, a: Dictionary, t: float) -> bool:
	var ex = _who(a, "exusiai")
	var tx = _who(a, "texas")
	var c: Vector2 = a.pos
	var R: float = float(a.r) * 0.75
	var ce: Color = _col(u, ex)
	var ct: Color = u._col(tx) if tx != null else Color(1.0, 0.86, 0.45)
	if _once(a, "go"):
		var pts: Array = []
		for i in 6:   # 内 2 外 4，按序号排、不抽随机数
			pts.append(c + Vector2.from_angle(i * 2.39996 + 0.4) * R * (0.3 if i < 2 else 0.8))
		a["pts"] = pts
		if _ok(ex):
			ex._set_face(1.0 if c.x >= ex.pos.x else -1.0, true)
			ex.play_vis_anim("attack")
		if _ok(tx):
			tx.play_vis_anim("skill")
	var shots: int = mini(8, int(t / 0.035) + 1)
	while int(a.k) < shots and _ok(ex):
		var k: int = int(a.k)
		var aim: Vector2 = c + Vector2.from_angle(k * 2.39996) * R * (0.2 + 0.08 * (k % 4))
		var d: Vector2 = (aim - ex.pos).normalized() if aim != ex.pos else Vector2.RIGHT
		var b: Vector2 = aim + d * 250.0
		u.shape({"kind": "line", "a": ex.pos + Vector2(0, -20), "b": b, "w": 3.0, "col": ce.lerp(Color.WHITE, 0.35), "life": 0.09})
		u.spark(ex.pos + Vector2(0, -20) + d * 14.0, ce, 1, 6.0)
		for e in u.in_band(ex.pos, b, 14.0):
			_hit(ex, e, "急件专送", 0.35)
		a.k = k + 1
	var pts2: Array = a.pts
	for i in pts2.size():
		var land: float = 0.16 + 0.045 * i
		var key := "s%d" % i
		if t >= land - 0.1 and _once(a, key + "f"):
			u.strip("fx_ult_texas_sword_front", pts2[i], {"o": Vector2(32, 224), "sc": 1.0, "seg": [0, 4], "col": ct.lerp(ce, 0.35)})
			u.shape({"kind": "line", "a": pts2[i] + Vector2(0, -150), "b": pts2[i], "w": 3.0, "col": ce, "life": 0.1})   # 剑身带能天使曳光
		if t >= land and _once(a, key):
			var p: Vector2 = pts2[i]
			u.shape({"kind": "ring", "c": p, "r": 50.0, "r1": 14.0, "w": 4.0, "col": ct.lerp(Color.WHITE, 0.3), "life": 0.2})
			u.shape({"kind": "circle", "c": p, "r": 26.0, "col": ce, "fill": 0.75, "life": 0.08})
			u.light(p, 90.0, ct, 0.2)
			var who = tx if _ok(tx) else ex
			for e in u.in_circle(p, 46.0):
				_hit(who, e, "急件专送", 0.9)
			if i % 2 == 0:
				_sfx(u, "hit", -5.0, 1.3)
	return t >= 0.16 + 0.045 * pts2.size() + 0.3


## B2 旧怨交锋（德克萨斯 × 拉普兰德）：非队长一方瞬身穿过主目标，队长一方原地甩出剑气；两道刃光在主目标处交叉成 X（各是本人颜色）。拉普兰德那道沉默 1 秒
static func _rival(u, a: Dictionary, t: float) -> bool:
	var ld = a.from
	var mv = a.p
	var L: float = 520.0
	var W: float = 80.0
	if _once(a, "go"):
		var tp: Vector2 = _tp(u, a)
		var d1: Vector2 = (tp - mv.pos).normalized() if tp != mv.pos else Vector2.RIGHT
		var d2: Vector2 = (tp - ld.pos).normalized() if _ok(ld) and tp != ld.pos else d1.orthogonal()
		if absf(d1.dot(d2)) > 0.82:   # 两道太接近平行就转成正交，保证是 X
			d2 = d1.rotated(PI / 2.0 * (1.0 if d1.cross(d2) >= 0.0 else -1.0))
		a["c"] = tp
		a["d1"] = d1
		a["d2"] = d2
		Link._dash(mv, tp + d1 * 120.0, 0.12)
		if _ok(ld):
			ld._set_face(1.0 if tp.x >= ld.pos.x else -1.0, true)
			ld.play_vis_anim("attack")
	var c: Vector2 = a.c
	var cm: Color = _col(u, mv)
	var cl: Color = _col(u, ld)
	if t < 0.14:
		if _ok(ld):   # 队长的剑气在路上
			var q: Vector2 = Vector2(ld.pos).lerp(c, t / 0.14)
			u.shape({"kind": "blade", "a": q - Vector2(a.d2) * 40.0, "b": q + Vector2(a.d2) * 40.0, "w": 6.0, "col": Color.WHITE, "glow": cl, "life": 0.04})
		return false
	if _once(a, "cut"):
		for pr in [[mv, a.d1, cm], [ld, a.d2, cl]]:
			var who = pr[0]
			if not _ok(who):
				continue
			var d: Vector2 = pr[1]
			var col: Color = pr[2]
			u.shape({"kind": "band", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": W, "col": col, "fill": 0.8, "life": 0.18})
			u.shape({"kind": "blade", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": 6.0, "col": Color.WHITE, "glow": col, "grow": 0.03, "life": 0.45})
			for e in u.in_band(c - d * L * 0.5, c + d * L * 0.5, W * 0.5):
				_hit(who, e, "旧怨交锋", 1.5)
				if str(who.id) == "lappland":
					u.g.enemies_sys.silence(e, u.g.t + (0.5 if e.elite else 1.0))
		Link._merge_flash(u, c, cm.lerp(Color.WHITE, 0.4), cl, 40.0)
	return t >= 0.6


## B3 潮下授课（乌尔比安 × 斯卡蒂）：锚钉住主目标 1.2 秒、把 180 内小怪拖过去；0.35 秒后斯卡蒂大剑砸在钉住处
static func _lesson(u, a: Dictionary, t: float) -> bool:
	var up = _who(a, "ulpianus")
	var sk = _who(a, "skadi")
	var cu: Color = _col(u, up)
	var cs: Color = _col(u, sk)
	if _once(a, "go"):
		a["tpos"] = _tp(u, a)
		a["fp"] = (up.pos if _ok(up) else Vector2(a.pos)) + Vector2(0, -20)
		if _ok(up):
			up._set_face(1.0 if a.tpos.x >= up.pos.x else -1.0, true)
			up.play_vis_anim("skill")
	var tp: Vector2 = a.tpos
	var tg: Variant = a.tg
	if tg != null and not tg.dead:
		tp = tg.pos
	if t < 0.18:
		var q: Vector2 = Vector2(a.fp).lerp(tp, t / 0.18)
		if LFA._ulpx(u):   # pixelfx 放开版：锚 + 新锁链 + 水尾（同连携「掷锚」）
			LFA.ulpianus_fly(u, a.fp, q, t / 0.18)
			return false
		u.shape({"kind": "line", "a": a.fp, "b": q, "w": 3.0, "col": cu.darkened(0.2), "life": 0.04})
		u.shape({"kind": "rock", "c": q, "r": 14.0, "col": Color(0.12, 0.2, 0.22), "glow": cu, "seed": 8.0, "life": 0.04})
		return false
	if _once(a, "pin"):
		if tg != null and not tg.dead and _ok(up):
			_hit(up, tg, "潮下授课", 1.0)
			if not tg.boss:
				up.add_cc(tg, 0.6 if tg.elite else 1.2)
		a["pull"] = u.in_circle(tp, 180.0).filter(func(e): return e != tg and not e.boss and not e.elite)
		if LFA._ulpx(u):
			LFA.ulpianus_pin(u, tp)
		else:
			u.debris(tp, cu, 2)
			u.light(tp, 150.0, cu, 0.4)
		_sfx(u)
	if t < 0.53:
		if LFA._ulpx(u):
			LFA.ulpianus_hold(u, (up.pos if _ok(up) else Vector2(a.fp)) + Vector2(0, -20), tp)
		else:
			if _ok(up):
				u.shape({"kind": "line", "a": up.pos + Vector2(0, -20), "b": tp, "w": 2.0, "col": cu.darkened(0.2), "life": 0.04})
			u.shape({"kind": "rock", "c": tp + Vector2(0, -6), "r": 14.0, "col": Color(0.12, 0.2, 0.22), "glow": cu, "seed": 8.0, "life": 0.04})
		for e in a.pull:
			if not e.dead and _ok(up):
				up.nudge(e, (tp - e.pos) * 0.12)
		if t >= 0.35 and _ok(sk) and _once(a, "sk"):
			var d: Vector2 = (tp - sk.pos).normalized() if tp != sk.pos else Vector2.RIGHT
			a["sfp"] = _go(u, sk, tp - d * 30.0, 0.15, cs)
		return false
	if _once(a, "slam"):
		for e in a.pull:
			if not e.dead and e.pos.distance_to(tp) < 90.0 and _ok(up):
				_hit(up, e, "潮下授课", 0.4)
		if _ok(sk):
			if not sk.is_leader:
				sk.play_vis_anim("skill")
			for e in u.in_circle(tp, 120.0):
				_hit(sk, e, "潮下授课", 1.8)
				Link._cc(sk, e, 0.5)
				if not e.boss:
					sk.apply_kb(e, (e.pos - tp).normalized() * 150.0)
		u.shape({"kind": "ring", "c": tp, "r": 120.0, "r1": 24.0, "w": 9.0, "col": cs, "life": 0.35})
		u.shape({"kind": "blade", "a": tp + Vector2(-70, -90), "b": tp + Vector2(10, 10), "w": 10.0, "col": Color.WHITE, "glow": cs, "life": 0.3})
		u.shape({"kind": "ellipse", "c": tp + Vector2(0, 6), "rx": 70.0, "ry": 24.0, "col": Color(0.1, 0.22, 0.35), "fill": 0.6, "layer": "back", "life": 1.0})
		u.grain("water", tp, Vector2.UP, Color(0.35, 0.6, 0.8), 18)
		u.debris(tp, cs, 3)
		Link._merge_flash(u, tp, cu.lerp(Color.WHITE, 0.4), cs, 44.0)
	return t >= 0.95


## B4 引潮夺命（歌蕾蒂娅 × 归溟幽灵鲨）：钩索把区域外最近 6 名敌人拖进中心；0.3 秒后幽灵鲨冲进中心横斩
static func _tide(u, a: Dictionary, t: float) -> bool:
	var gl = _who(a, "gladiia")
	var sp = _who(a, "specter_unchained")
	var c: Vector2 = a.pos
	var r: float = float(a.r)
	var cg := Color(0.35, 0.85, 0.95)   # 歌蕾蒂娅的钩索色（同 skill_link.HOOK）
	var cs: Color = _col(u, sp)
	if _once(a, "go"):
		var outs: Array = []
		for e in u.in_circle(c, r + 210.0):
			if e.pos.distance_to(c) > r * 0.5 and not e.boss:
				outs.append(e)
		outs.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
		a["outs"] = outs.slice(0, 6)
		if _ok(gl):
			gl._set_face(1.0 if c.x >= gl.pos.x else -1.0, true)
			gl.play_vis_anim("skill")
	if t < 0.3:
		for e in a.outs:
			if not e.dead and _ok(gl):
				u.shape({"kind": "line", "a": gl.pos + Vector2(0, -20), "b": e.pos, "w": 2.0, "col": cg, "life": 0.04})
				gl.nudge(e, (c - e.pos) * 0.16)
		return false
	if _once(a, "land"):
		for e in a.outs:
			if not e.dead and _ok(gl):
				_hit(gl, e, "引潮夺命", 0.5)
		u.shape({"kind": "ring", "c": c, "r": 90.0, "r1": 20.0, "w": 5.0, "col": cg, "life": 0.3})
		if _ok(sp):
			var d: Vector2 = (c - sp.pos).normalized() if c != sp.pos else Vector2.RIGHT
			a["sd"] = d
			_go(u, sp, c - d * 20.0, 0.12, cs)
	if t >= 0.45 and _once(a, "cut"):
		var d2: Vector2 = a.get("sd", Vector2.RIGHT)
		var nv: Vector2 = d2.orthogonal()
		u.shape({"kind": "band", "a": c - nv * 120.0, "b": c + nv * 120.0, "w": 60.0, "col": cs, "fill": 0.75, "life": 0.18})
		u.shape({"kind": "blade", "a": c - nv * 130.0, "b": c + nv * 130.0, "w": 7.0, "col": Color(1.0, 0.86, 0.84), "glow": cs, "grow": 0.03, "life": 0.5})
		u.grain("fluid", c, Vector2.UP, Color(0.5, 0.05, 0.08), 10)
		if _ok(sp):
			for e in u.in_circle(c, 110.0):
				_hit(sp, e, "引潮夺命", 1.6)
		Link._merge_flash(u, c, cg.lerp(Color.WHITE, 0.4), cs, 40.0)
	return t >= 0.85


## B5 漩涡钉锚（歌蕾蒂娅 × 乌尔比安）：中心起 0.6 秒小漩涡把敌人拉拢；漩涡收紧时乌尔比安的锚从高处砸进漩涡眼
static func _vortex(u, a: Dictionary, t: float) -> bool:
	var gl = _who(a, "gladiia")
	var up = _who(a, "ulpianus")
	var c: Vector2 = a.pos
	var rv: float = float(a.r) * 0.6
	var cg: Color = Color(0.35, 0.85, 0.95)
	var cu: Color = _col(u, up)
	if _once(a, "go"):
		if _ok(gl):
			gl.play_vis_anim("skill")
		if _ok(up):
			up._set_face(1.0 if c.x >= up.pos.x else -1.0, true)
	if t < 0.6:
		var k: float = t / 0.6
		for j in 10:   # 螺旋水点往里收
			var ang: float = TAU * j / 10.0 + t * 9.0
			var rr: float = rv * (1.0 - 0.6 * k) * (0.5 + 0.5 * fposmod(j * 0.618, 1.0))
			u.shape({"kind": "circle", "c": c + Vector2.from_angle(ang) * rr, "r": 4.0, "col": cg, "fill": 0.8, "life": 0.04})
		u.shape({"kind": "ring", "c": c, "r": rv * (1.0 - 0.5 * k), "r1": rv * 0.2, "w": 3.0, "col": Color(cg, 0.6), "life": 0.04})
		for e in u.in_circle(c, rv + 40.0):
			if not e.boss and _ok(gl):
				gl.nudge(e, (c - e.pos) * 0.1)
		for j in 3:
			if t >= 0.2 * j and _once(a, "v%d" % j) and _ok(gl):
				for e in u.in_circle(c, rv):
					_hit(gl, e, "漩涡钉锚", 0.2)
		if t >= 0.4 and _ok(up):   # 锚从高处落下
			var q: Vector2 = (c + Vector2(0, -260)).lerp(c, (t - 0.4) / 0.2)
			if _once(a, "upa"):
				up.play_vis_anim("skill")
			if LFA._ulpx(u):   # pixelfx 放开版：锚从高处带着锁链砸下
				LFA.ulpianus_fly(u, up.pos + Vector2(0, -20), q, (t - 0.4) / 0.2)
			else:
				u.shape({"kind": "line", "a": up.pos + Vector2(0, -20), "b": q, "w": 2.0, "col": cu.darkened(0.2), "life": 0.04})
				u.shape({"kind": "rock", "c": q, "r": 18.0, "col": Color(0.12, 0.2, 0.22), "glow": cu, "seed": 8.0, "life": 0.04})
		return false
	if _once(a, "slam"):
		if _ok(up):
			for e in u.in_circle(c, 130.0):
				_hit(up, e, "漩涡钉锚", 1.6)
				Link._cc(up, e, 0.5)
		if LFA._ulpx(u):   # pixelfx 放开版：锚砸进漩涡眼（深沟 + 裂网），不画圆环
			LFA.ulpianus_pin(u, c)
		else:
			u.shape({"kind": "ring", "c": c, "r": 130.0, "r1": 24.0, "w": 9.0, "col": cu, "life": 0.4})
			u.shape({"kind": "rock", "c": c + Vector2(0, -6), "r": 18.0, "col": Color(0.12, 0.2, 0.22), "glow": cu, "seed": 8.0, "life": 0.5})
		u.grain("water", c, Vector2.UP, Color(0.35, 0.6, 0.8), 20)
		u.debris(c, cu, 3)
		Link._merge_flash(u, c, cg.lerp(Color.WHITE, 0.4), cu, 46.0)
		_sfx(u, "hit", -3.0, 0.9)
	return t >= 1.0


## B6 双鳍（斯卡蒂 × 归溟幽灵鲨）：非队长一方冲过区域，队长一方沿同方向原地放一道冲击波；两道轨迹在中心交错，各留水痕 1.5 秒
static func _fins(u, a: Dictionary, t: float) -> bool:
	var c: Vector2 = a.pos
	var r: float = float(a.r)
	var ld = a.from
	var mv = a.p
	if _once(a, "go"):
		var lines: Array = []
		for who in [mv, ld]:
			if not _ok(who):
				continue
			var d: Vector2 = (c - who.pos).normalized() if c != who.pos else Vector2.RIGHT
			var fp: Vector2 = who.pos if not who.is_leader else c - d * minf(who.pos.distance_to(c), r + 60.0)
			var tp: Vector2 = c + d * r
			lines.append([who, fp, tp])
			if who.is_leader:
				_go(u, who, tp, 0.0, _col(u, who))
			else:
				Link._dash(who, tp, 0.18)
		a["lines"] = lines
	if t < 0.18:
		for ln in a.lines:
			var q: Vector2 = Vector2(ln[1]).lerp(ln[2], t / 0.18)
			u.grain("water", q + Vector2(0, 8), Vector2.UP, Color(0.3, 0.55, 0.75), 2)
		return false
	if _once(a, "cut"):
		for ln in a.lines:
			var who = ln[0]
			var col: Color = _col(u, who)
			u.shape({"kind": "band", "a": ln[1] + Vector2(0, 8), "b": ln[2] + Vector2(0, 8), "w": 34.0, "col": Color(0.12, 0.25, 0.4), "fill": 0.6, "layer": "back", "life": 1.6})
			u.shape({"kind": "blade", "a": ln[1], "b": ln[2], "w": 6.0, "col": Color.WHITE, "glow": col, "grow": 0.03, "life": 0.45})
			for e in u.in_band(ln[1], ln[2], 38.0):
				_hit(who, e, "双鳍", 1.2)
		Link._merge_flash(u, c, Color(0.6, 0.85, 1.0), _col(u, mv), 40.0)
		_sfx(u)
	for j in 3:
		if t >= 0.18 + 0.5 * (j + 1) and _once(a, "w%d" % j):
			for ln in a.lines:
				for e in u.in_band(ln[1], ln[2], 20.0):
					_hit(ln[0], e, "双鳍", 0.25)
			u.grain("water", c, Vector2.UP, Color(0.3, 0.55, 0.75), 4)
	return t >= 0.18 + 1.6


## B7 灯下审决（艾丽妮 × 流明）：流明提灯照亮区域 3 秒（区域内敌人受伤 +15%，队长灯火 +10、清神经损伤）；艾丽妮随后一刺穿过主目标
static func _inq(u, a: Dictionary, t: float) -> bool:
	var ir = _who(a, "irene")
	var lu = _who(a, "lumen")
	var c: Vector2 = a.pos
	var r: float = float(a.r)
	var cl: Color = _col(u, lu)
	var ci: Color = _col(u, ir)
	if _once(a, "go"):
		if _ok(lu):
			lu.play_vis_anim("skill")
		u.g.lamp = minf(float(u.g.lamp_cap), float(u.g.lamp) + Bal.v("ult/link_lumen_lamp", 10.0))
		u.g.nerve = 0.0
		u.light(c, r + 40.0, Color(1.0, 0.9, 0.7), 0.8)   # 预审 11-02：3 秒实心光罩叠起来发白 → 只留 1.2 秒淡底 + 一圈灯色边（增伤仍是 3 秒）
		u.shape({"kind": "circle", "c": c, "r": r, "col": Color(1.0, 0.86, 0.6), "fill": 0.07, "layer": "back", "life": 1.2})
		u.shape({"kind": "ring", "c": c, "r": r, "r1": r * 0.9, "w": 3.0, "col": cl, "life": 1.0})
		for e in u.in_circle(c, r):
			e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), u.g.t + 3.0)
			e["frag_v"] = maxf(float(e.get("frag_v", 0.0)), 0.15)
	if t < 0.6 and int(t * 30.0) % 2 == 0:
		u.grain("mote_up", c + Vector2.from_angle(t * 11.0) * r * fposmod(t * 3.7, 1.0), Vector2.UP, cl, 2)
	if t >= 0.3 and _ok(ir) and _once(a, "dash"):
		var tp: Vector2 = _tp(u, a)
		var d: Vector2 = (tp - ir.pos).normalized() if tp != ir.pos else Vector2.RIGHT
		a["fp"] = ir.pos
		a["tp2"] = tp + d * 110.0
		if not ir.is_leader:
			Link._dash(ir, a.tp2, 0.12)
		else:
			ir._set_face(1.0 if d.x >= 0.0 else -1.0, true)
			ir.play_vis_anim("attack")
	if t >= 0.42 and a.has("fp") and _once(a, "cut"):
		var fp: Vector2 = a.fp
		var tp2: Vector2 = a.tp2
		u.shape({"kind": "blade", "a": fp, "b": tp2, "w": 4.0, "col": Color(1.0, 0.96, 0.85), "glow": ci, "grow": 0.04, "life": 0.55})
		for k in [0.14, 0.33, 0.52, 0.81]:   # 火花不等距（预审 11-02：等距排列像贴图拼接）
			u.spark(fp.lerp(tp2, k), ci, 1 + int(k * 3.0) % 2, 10.0)
		for e in u.in_band(fp, tp2, 30.0):
			_hit(ir, e, "灯下审决", 1.6)
		Link._merge_flash(u, tp2.lerp(fp, 0.3), cl.lerp(Color.WHITE, 0.4), ci, 38.0)
		_sfx(u)
	return t >= 1.0


## B8 群猎（深海猎人 ≥ 3）：其余猎人依次（间隔 0.09 秒）扑向主目标；浊心斯卡蒂不冲、原地唱一句（全队攻击 +20%）；队长原地一击；主目标 4 秒受伤 +10%
static func _hunt(u, a: Dictionary, t: float) -> bool:
	var ld = a.from
	var mates: Array = a.get("mates", [a.p])
	var tp: Vector2 = _tp(u, a)
	if _once(a, "mark"):
		var tg: Variant = a.tg
		if tg != null and not tg.dead:
			tg["frag_t"] = maxf(float(tg.get("frag_t", 0.0)), u.g.t + 4.0)
			tg["frag_v"] = maxf(float(tg.get("frag_v", 0.0)), 0.1)
	for k in mates.size():
		var m = mates[k]
		if not _ok(m):
			continue
		var t0: float = 0.09 * k
		if str(m.id) == "skalter":
			if t >= t0 and _once(a, "sing"):
				m.play_vis_anim("skill")
				u.team_buff("link:skalter", 3.0, [[&"dmg", "mult", Bal.v("ult/link_skalter_atk", 1.2)]], a.pos, float(a.r))
				u.light(a.pos, float(a.r), _col(u, m), 0.5)
				for j in 8:
					u.shape({"kind": "rock", "c": Vector2(a.pos) + Vector2.from_angle(TAU * j / 8.0) * float(a.r), "r": 6.0, "col": _col(u, m), "glow": Color(1.0, 0.8, 0.8), "seed": float(j), "life": 1.2})
			continue
		if t >= t0 and _once(a, "d%d" % k):
			var d: Vector2 = (tp - m.pos).normalized() if tp != m.pos else Vector2.RIGHT
			a["fp%d" % k] = m.pos
			Link._dash(m, tp - d * 30.0, 0.14)
		if t >= t0 and t < t0 + 0.14 and a.has("fp%d" % k):
			u.shape({"kind": "line", "a": a["fp%d" % k], "b": m.pos, "w": 4.0, "col": _col(u, m), "life": 0.12})
		if t >= t0 + 0.14 and _once(a, "h%d" % k):
			u.shape({"kind": "ring", "c": tp, "r": 70.0, "r1": 16.0, "w": 5.0, "col": _col(u, m), "life": 0.25})
			for e in u.in_circle(tp, 70.0):
				_hit(m, e, "群猎", 1.1)
			_sfx(u, "hit", -5.0, 1.1 + 0.1 * k)
	var tl: float = 0.09 * mates.size() + 0.05
	if _ok(ld) and t >= tl and _once(a, "ld"):
		_go(u, ld, tp, 0.0, _col(u, ld))
		for e in u.in_band(ld.pos, tp, 30.0):
			_hit(ld, e, "群猎", 1.0)
		u.debris(tp, _col(u, ld), 2)
		Link._merge_flash(u, tp, _col(u, ld).lerp(Color.WHITE, 0.4), _col(u, mates[0]), 44.0)
	return t >= 1.0
