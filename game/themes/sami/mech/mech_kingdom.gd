extends "res://scripts/core/theme_mechanic.gd"
## 萨米主题机制 · 国度（docs/394 §3、docs/393 §1.3；数值读 themes/sami/data/mechanics.json kingdom）。
## 一块国度 = {pos, r, kind, crack, props, owner}：kind chaos（范式「实质性坍缩」，有撑持体）/ boss（利刃 / 游荡者铺的，无撑持体）/ nursery（克雷松苗圃，持续伤害、不连片）。
## 站在里面的队员攻速 −50%（蔓延性 −75%，跟寒霜光环相乘、最低 ×0.25）；对敌人无效；冲刺穿过无影响。
## 瓦解：撑持体全死，或在国度里 / 边缘 60 内击杀敌人让裂纹 +8% 到满。chaos 块瓦解：坍缩值 −1（每阶段最多 −3）+ 3 × 普通怪经验；本阶段不补。
## 连片：两块中心距 < 150（游荡者的块 220）补一条连接带，连接带也算国度；游荡者的块碎掉时相连的块裂纹 +50%。
## Boss 地块同时最多 12 块，超出删最旧；Boss 倒下时它的地块一起散掉。

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const MJ := "res://themes/sami/data/mechanics.json"
const BOSS_CAP := 12

var g: Game
var K: Dictionary = {}
var list: Array = []          # 全部地块
var links: Array = []         # [a, b, half_width]
var _links_dirty := true
var _aspd_t := 0.0
var _aspd_key := ""
var _far_t := 0.0
var _stage_broken := 0        # 本阶段瓦解的 chaos 块数（不补）
var rng := RandomNumberGenerator.new()
var _seeded := false
var breaks := 0               # 遥测：本局瓦解数
var prop_kills := 0
var in_t := 0.0               # 队长站在国度里的秒数


func _init(game: Game) -> void:
	g = game
	var f := FileAccess.open(MJ, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			K = d.get("kingdom", {})


func _rng() -> RandomNumberGenerator:
	if not _seeded:
		_seeded = true
		rng.seed = hash(str(g.rng.seed) + "kingdom")
	return rng


func _cm():
	return g.mech("collapse")


## 当前范式要几块（0 = 没有实质性坍缩）
func _want() -> int:
	var cm = _cm()
	if cm == null:
		return 0
	var lv: int = cm.par("chaos_2")
	if lv <= 0:
		return 0
	var c: Array = K.get("count", [4, 8])
	return int(c[clampi(lv - 1, 0, c.size() - 1)])


func _atk_pen() -> float:
	var cm = _cm()
	var lv: int = cm.par("chaos_2") if cm != null else 0
	var a: Array = K.get("atk_spd", [-0.5, -0.75])
	return float(a[clampi(maxi(lv, 1) - 1, 0, a.size() - 1)])


func on_stage() -> void:
	_stage_broken = 0
	_fill()


func on_paradigm() -> void:
	_fill()


## 按块数补齐 chaos 块（离队长 250–500 随机方向），本阶段瓦解的不补
func _fill() -> void:
	var want: int = _want() - _stage_broken
	var have: int = list.filter(func(k): return k.kind == "chaos").size()
	var sd: Array = K.get("spawn_dist", [250, 500])
	while have < want:
		var p: Vector2 = g.ppos + Vector2.from_angle(_rng().randf() * TAU) * _rng().randf_range(float(sd[0]), float(sd[1]))
		_add_chaos(p)
		have += 1


func _add_chaos(p: Vector2) -> void:
	var k := add(p, float(K.get("radius", 80.0)), "chaos", null)
	_spawn_props(k)


## 新地块：kind chaos / boss / nursery；owner = 放它的 Boss（字典）或 null
func add(p: Vector2, r: float, kind: String, owner, life := -1.0) -> Dictionary:
	var k := {"pos": p, "r": r, "kind": kind, "crack": 0.0, "props": [], "owner_id": int(owner.id) if owner != null else -1,
		"owner_type": str(owner.type) if owner != null else "", "life": life, "born": g.t, "far_t": 0.0, "dps": 0.0}
	if kind != "chaos":
		var mine: Array = list.filter(func(x): return x.kind != "chaos")
		if mine.size() >= BOSS_CAP:
			_remove(mine[0], false)
	list.append(k)
	_links_dirty = true
	return k


func _spawn_props(k: Dictionary) -> void:
	var pr: Dictionary = K.get("props", {})
	var cm = _cm()
	var lv: int = cm.level if cm != null else 0
	var n := 2
	for row in pr.get("rule", [[3, 2, 2], [5, 5, 3], [99, 99, 4]]):
		if g.threat + 1 <= int(row[0]):
			n = maxi(n, int(row[2]))
			break
	for row in pr.get("rule", [[3, 2, 2], [5, 5, 3], [99, 99, 4]]):
		if lv <= int(row[1]):
			n = maxi(n, int(row[2]))
			break
	var types: Array = []
	var pool: Array = D.THREAT[g.threat].get("pool", []) if g.threat < D.THREAT.size() else []
	for t in pool:
		if str(t) in pr.get("types", ["husk", "drone", "caster"]) and D.ENEMIES.get(str(t), {}).get("prop_ok", false):   # 能撑国度的坍缩体（enemies.json prop_ok）
			types.append(str(t))
	if types.is_empty():
		types = ["husk"]
	for i in n:
		var tp: String = types[_rng().randi() % types.size()]
		if not D.ENEMIES.has(tp):
			continue
		var pos: Vector2 = k.pos + Vector2.from_angle(TAU * i / float(n)) * k.r * 0.6
		var e: Dictionary = g.spawner.spawn_enemy(tp, pos)
		e.hp *= float(pr.get("hp", 2.5))
		e.maxhp = e.hp
		e.xp *= float(pr.get("xp", 2.0))
		e.spd *= float(pr.get("spd", 0.8))
		e.affix = ""
		e["k_prop"] = true
		if bool(pr.get("heavy", false)):
			e["heavy"] = true   # 撑持体算重型（mechanics.json kingdom.props.heavy，用户 11-21）：提丰优先点它、击退 ×0.3
		k.props.append(int(e.id))


## 点 p 在不在国度里（含连接带）；kinds 为空 = 全部种类
func inside(p: Vector2, kinds: Array = []) -> bool:
	return at(p, kinds) != null


func at(p: Vector2, kinds: Array = []):
	for k in list:
		if (kinds.is_empty() or k.kind in kinds) and p.distance_to(k.pos) < k.r:
			return k
	if _links_dirty:
		_relink()
	for l in links:
		var a: Dictionary = l[0]
		var b: Dictionary = l[1]
		if not kinds.is_empty() and not (a.kind in kinds):
			continue
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, a.pos, b.pos)
		if p.distance_to(q) < float(l[2]):
			return a if p.distance_to(a.pos) < p.distance_to(b.pos) else b
	return null


func _link_dist(k: Dictionary) -> float:
	var kl = D.ENEMIES.get(k.owner_type, {}).get("kingdom_link", null)
	if kl is Dictionary:
		return float(kl.get("dist", 150.0))
	return float(K.get("link", {}).get("dist", 150.0))


func _relink() -> void:
	_links_dirty = false
	links.clear()
	var lk: Dictionary = K.get("link", {})
	for i in list.size():
		var a: Dictionary = list[i]
		if a.kind == "nursery":
			continue
		for j in range(i + 1, list.size()):
			var b: Dictionary = list[j]
			if b.kind == "nursery":
				continue
			var ld: float = maxf(_link_dist(a), _link_dist(b))
			if a.pos.distance_to(b.pos) < ld:
				links.append([a, b, minf(a.r, b.r) * float(lk.get("width_mul", 1.2)) * 0.5])


## 击杀（mech_foes.on_enemy_killed 调）：撑持体 / 裂纹
func on_kill(e: Dictionary) -> void:
	if e.get("k_prop", false):
		for k in list:
			if int(e.id) in k.props:
				k.props.erase(int(e.id))
				prop_kills += 1
				if k.props.is_empty():
					_break(k)
				return
	if g.frozen_t > 0.0:
		return   # 冻结中队长没有击杀（docs/394 §8.5）
	var edge: float = float(K.get("crack", {}).get("edge", 60.0))
	var best = null
	var bd := INF
	for k in list:
		if k.kind == "nursery":
			continue
		var d: float = e.pos.distance_to(k.pos) - k.r
		if d < edge and d < bd:
			bd = d
			best = k
	if best == null:
		var k2 = at(e.pos)
		if k2 != null and k2.kind != "nursery":
			best = k2
	if best != null:
		best.crack += float(K.get("crack", {}).get("per_kill", 0.08))
		if best.crack >= 1.0:
			_break(best)


func _break(k: Dictionary) -> void:
	if not (k in list):
		return
	breaks += 1
	var spread: float = 0.0
	var kl = D.ENEMIES.get(k.owner_type, {}).get("kingdom_link", null)
	if kl is Dictionary:
		spread = float(kl.get("crack_spread", 0.0))
	var nb: Array = []
	if spread > 0.0:
		if _links_dirty:
			_relink()
		for l in links:
			if l[0] == k:
				nb.append(l[1])
			elif l[1] == k:
				nb.append(l[0])
	_remove(k, true)
	if int(k.owner_id) >= 0:
		var ob = g.enemies_sys.by_id(int(k.owner_id))
		if ob != null and not ob.dead:
			var sc = g.bai.boss(ob.type)
			if sc != null and sc.has_method("on_kingdom_break"):
				sc.on_kingdom_break(ob)
	g.fx.append({"kind": "ring", "pos": k.pos, "r": k.r, "life": 0.6, "max": 0.6, "col": Color(0.8, 0.85, 1.0)})
	g.vfx.sparks(k.pos, Vector2.UP, Color(0.8, 0.9, 1.2), 14, 220.0)
	if k.kind == "chaos":
		_stage_broken += 1
		var cm = _cm()
		if cm != null:
			cm.add(float(K.get("reward", {}).get("collapse", -1.0)), "kingdom")
		var tm = g.mech("totem")
		if tm != null:
			tm.on_kingdom_break()   # 瓦解国度 20% 掉 1 块密文板
		var xpv: float = float(K.get("reward", {}).get("xp_mobs", 3.0)) * maxf(1.0, g.spawner.xp_unit() if g.spawner.has_method("xp_unit") else 1.0)
		g.pickups.drop(k.pos, "xp", xpv)
	for n in nb:
		if n in list:
			n.crack += spread
			if n.crack >= 1.0:
				_break(n)


func _remove(k: Dictionary, _broken: bool) -> void:
	list.erase(k)
	for pid in k.props:
		var e = g.enemies_sys.by_id(int(pid))
		if e != null and not e.dead:
			e.k_prop = false   # 裂纹满碎时剩下的撑持体失去标记、照常存活
	_links_dirty = true


## Boss 倒下：它铺的地块散掉
func clear_owner(owner_id: int) -> void:
	for k in list.duplicate():
		if int(k.owner_id) == owner_id:
			_remove(k, false)


func on_world_tick(dt: float) -> void:
	# 限时地块（苗圃、Boss 小块）
	for k in list.duplicate():
		if float(k.life) > 0.0 and g.t - float(k.born) >= float(k.life):
			_remove(k, false)
	# 撑持体拴在国度中心 160 内
	var leash: float = float(K.get("props", {}).get("leash", 160.0))
	for k in list:
		for pid in k.props:
			var e = g.enemies_sys.by_id(int(pid))
			if e != null and not e.dead and e.pos.distance_to(k.pos) > leash:
				e.pos = k.pos + (e.pos - k.pos).normalized() * leash
	# 跟随：chaos 块离队长 900 以上超过 10 秒，移到前方 250–500（撑持体随行、裂纹清零）
	var rd: float = float(K.get("relocate_dist", 900.0))
	var sd: Array = K.get("spawn_dist", [250, 500])
	for k in list:
		if k.kind != "chaos":
			continue
		if k.pos.distance_to(g.ppos) > rd:
			k.far_t += dt
			if k.far_t > float(K.get("relocate_after", 10.0)):
				var fwd: Vector2 = g.pvel.normalized() if g.pvel.length() > 1.0 else Vector2.from_angle(_rng().randf() * TAU)
				var np: Vector2 = g.ppos + fwd.rotated(_rng().randf_range(-0.8, 0.8)) * _rng().randf_range(float(sd[0]), float(sd[1]))
				var dv: Vector2 = np - k.pos
				k.pos = np
				k.crack = 0.0
				k.far_t = 0.0
				for pid in k.props:
					var e = g.enemies_sys.by_id(int(pid))
					if e != null and not e.dead:
						e.pos += dv
				_links_dirty = true
		else:
			k.far_t = 0.0
	# 苗圃持续伤害（3%/秒，克雷松）
	var here = at(g.ppos)
	if here != null:
		in_t += dt
		if float(here.dps) > 0.0 and g.state == g.S.PLAY:
			g.combat.lose_hp(g.max_hp * float(here.dps) * dt, "nursery", true)
	_aspd_t -= dt
	if _aspd_t <= 0.0:
		_aspd_t = 0.1
		_tick_aspd()


## 每 0.1 秒对账：国度里的队员攻速 −50%，寒霜光环 −30%（相乘，最低 ×0.25），来源 sami_aspd、作用域 op:<id>
func _tick_aspd() -> void:
	var pen: float = _atk_pen()
	var auras: Array = g.foe.auras if g.foe != null else []
	var want: Dictionary = {}
	for o in g.squad.ops:
		var p: Vector2 = g.ppos if o.is_leader or o.pos == Vector2.INF else o.pos
		var m := 1.0
		if inside(p):
			m *= 1.0 + pen
		for a in auras:
			if a.dead:
				continue
			var ca = D.ENEMIES.get(a.type, {}).get("chill_aura", null)
			if ca is Dictionary and p.distance_to(a.pos) < float(ca.get("r", 150.0)):
				m *= 1.0 + float(ca.get("atk_spd", -0.3))
				break
		if m < 1.0:
			want[str(o.id)] = maxf(0.25, m)
	var key: String = str(want)
	if key == _aspd_key:
		return
	_aspd_key = key
	g.stats.remove_source("sami_aspd")
	if not g.stats.has_stat(&"op_aspd"):
		return
	for cid in want:
		g.stats.add(&"op_aspd", "mult", float(want[cid]), "sami_aspd", "op:" + cid)


## 占位画法：地块 = 低亮度圆 + 描边，连接带 = 粗线；裂纹 = 描边弧长
func draw_ground(_w) -> void:
	if list.is_empty():
		return
	var cv = g.wcv
	if _links_dirty:
		_relink()
	for l in links:
		cv.draw_line(l[0].pos, l[1].pos, Color(0.35, 0.3, 0.5, 0.28), float(l[2]) * 2.0)
	for k in list:
		var col: Color = Color(0.75, 0.85, 0.35, 0.22) if k.kind == "nursery" else (Color(0.35, 0.3, 0.55, 0.3) if k.kind == "chaos" else Color(0.15, 0.15, 0.2, 0.35))
		cv.draw_circle(k.pos, k.r, col)
		cv.draw_arc(k.pos, k.r, 0.0, TAU, 40, Color(col.r + 0.3, col.g + 0.3, col.b + 0.3, 0.6), 2.0)
		if float(k.crack) > 0.0:
			cv.draw_arc(k.pos, k.r - 4.0, -PI * 0.5, -PI * 0.5 + TAU * minf(1.0, float(k.crack)), 32, Color(1.0, 0.95, 0.8, 0.8), 3.0)
		for pid in k.props:
			var e = g.enemies_sys.by_id(int(pid))
			if e != null and not e.dead:
				cv.draw_line(k.pos, e.pos, Color(0.6, 0.8, 1.0, 0.35), 1.5)


## 机器人：候选点在国度里扣分（攻速 −50% 的区域尽量不站）
func bot_score(q: Vector2, s: float) -> float:
	if not list.is_empty() and inside(q):
		s -= 8.0
	return s
