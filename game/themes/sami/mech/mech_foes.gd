extends "res://scripts/core/theme_mechanic.gd"
## 萨米主题机制 · 敌人行为（docs/392 §2–§3、§11；字段在 themes/sami/data/enemies.json）。核心经 g.foe（清单 id foes）在固定点调：
##   enemy_spd(e, spd, dist, dt)  enemies.update A 段：受击暴冲 hurt_rush、停火突进 idle_rush、馈赠加速（雪祀）、非线性移动范式、巨壳藤蔓逃跑
##   on_enemy_spawned(e)          spawner.spawn_enemy：范式改生命（非线性移动 / 情绪实体 / 睁眼瞎）、光环敌人登记
##   on_enemy_killed(e)           combat.kill：冰爆 death_blast、国度裂纹 / 撑持体、坍缩值（坍缩体精英 −0.5、中期 Boss −2）
##   player_hit_mult(src)         combat.enemy_hit：打冻结目标 frozen_mult、打寒冷 ≥50 目标 frosted_mult、站在国度里挨 Boss 招 ×1.5
##   on_player_hit(dmg, src)      主题挂钩：命中加寒冷 cold_add（Boss 来源封顶 90）
##   on_world_tick(dt)            寒霜光环 cold_aura；补给箱 20% 换成巨壳藤蔓（2:00 后、每局最多 2 次）

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
const MECH_BOSS_KINGDOM := ["blade", "wanderer", "cresson"]

var g: Game
var auras: Array = []        # 带 chill_aura / cold_aura 的在场敌人（mech_kingdom 攻速对账也读）
var _aura_t := 0.0
var vineboxes := 0
var rng := RandomNumberGenerator.new()
var _seeded := false
var gifts := 0               # 遥测：馈赠到小怪的次数
var ices: Array = []         # 冰爆源石虫死后留下的冰面 [pos, r, 到期]：站上去减速


func _init(game: Game) -> void:
	g = game


func _rng() -> RandomNumberGenerator:
	if not _seeded:
		_seeded = true
		rng.seed = hash(str(g.rng.seed) + "foes")
	return rng


func _cold():
	return g.mech("cold")


func _cm():
	return g.mech("collapse")


func enemy_spd(e: Dictionary, spd: float, _dist: float, _dt: float) -> float:
	if e.boss:
		return spd
	var d: Dictionary = D.ENEMIES.get(e.type, {})
	var hr = d.get("hurt_rush", null)
	if hr is Dictionary:
		var last: float = float(e.get("hr_hp", e.maxhp))
		if e.hp < last - 0.01 and g.t >= float(e.get("hr_cd", 0.0)):
			e["hr_until"] = g.t + float(hr.get("dur", 1.5))
			e["hr_cd"] = g.t + float(hr.get("cd", 3.0))
			var fx = g.mech("fx")
			if fx != null:
				fx.rush(e)   # 只画（docs/401）
		e["hr_hp"] = e.hp
		if g.t < float(e.get("hr_until", 0.0)):
			spd *= float(hr.get("mult", 2.0))
	var ir = d.get("idle_rush", null)
	if ir is Dictionary:
		var shot: float = float(e.atk_until) - 0.2
		var since: float = g.t - maxf(shot, float(e.get("born_t", 0.0)))
		if since > float(ir.get("after", 4.0)):
			spd *= float(ir.get("mult", 2.0))
	if d.get("collapse", false):
		var cm = _cm()
		if cm != null:
			spd *= 1.0 + cm.eff("chaos_3", "collapse_spd")
	if float(e.get("gift_until", 0.0)) > g.t:
		spd = minf(spd * 2.0, 140.0)   # 反自然馈赠：移速 ×2、封顶 140（docs/393 §2.3）
	if e.type == "vinebox":
		return _vinebox(e, spd)
	return spd


## 巨壳藤蔓：静止拟态，第一次挨打后逃跑（远离队长，移速 90），flee_t 秒内没打死就钻地消失
func _vinebox(e: Dictionary, spd: float) -> float:
	if not e.has("vb_wake"):
		if e.hp >= e.maxhp:
			return 0.0
		e["vb_wake"] = g.t
		g.vfx.add_alert(e.pos + Vector2(0, -30), "巨壳藤蔓", Color(0.6, 0.9, 0.5), 14)
	if g.t - float(e.vb_wake) > float(D.ENEMIES.vinebox.get("flee_t", 8.0)):
		e.dead = true
		g.vfx.sparks(e.pos, Vector2.UP, Color(0.6, 0.5, 0.4), 10, 160.0)
		return 0.0
	return -minf(absf(spd), 90.0)


func on_enemy_spawned(e: Dictionary) -> void:
	e["born_t"] = g.t
	var d: Dictionary = D.ENEMIES.get(e.type, {})
	if d.has("chill_aura") or d.has("cold_aura"):
		auras.append(e)
	if e.boss or e.get("chest", false):
		return
	var cm = _cm()
	if cm == null:
		return
	var k := 1.0
	if d.get("collapse", false):
		k *= 1.0 + cm.eff("chaos_3", "collapse_hp")
	if str(d.get("role", "")) == "" and cm.par("chaos_4") > 0 and _rng().randf() < cm.eff("chaos_4", "spawn_double_hp_p"):
		k *= 2.0
	k *= 1.0 + cm.eff("chaos_9", "enemy_hp")
	if k != 1.0:
		e.hp *= k
		e.maxhp = e.hp


func on_enemy_killed(e: Dictionary) -> void:
	var tm = g.mech("totem")
	if tm != null:
		tm.on_kill(e)   # 密文板掉落（精英 / 中期 Boss / 宝箱）
	var d: Dictionary = D.ENEMIES.get(e.type, {})
	var db = d.get("death_blast", null)
	if db is Dictionary:
		_blast(e, db, d)
	if int(e.get("crystal_of", -1)) >= 0:
		var vb = g.enemies_sys.by_id(int(e.crystal_of))
		if vb != null and not vb.dead:
			var vs = g.bai.boss(vb.type)
			if vs != null and vs.has_method("on_crystal"):
				vs.on_crystal(vb, e.pos)   # 古老藤蔓：高能源石虫（占位）死后留结晶
	var km = g.mech("kingdom")
	if km != null and not e.get("chest", false):
		km.on_kill(e)
	var cm = _cm()
	if cm != null:
		if e.get("elite", false) and d.get("collapse", false):
			cm.add(-cm._k("loss/elite_collapse", 0.5), "elite")
		elif e.boss and str(d.get("role", "")) == "boss" and not g.spawner.is_final_boss_type(e.type):
			cm.add(-cm._k("loss/mid_boss", 2.0), "mid_boss")
	if e.boss and km != null:
		km.clear_owner(int(e.id))


## 冰爆源石虫：死亡时半径 r 爆炸（伤害 = dmg × mult，算环境伤害）+ 寒冷 cold_add；纠缠 / 古老藤蔓在范围里吃 10 秒脆弱（docs/393 §2.5）
func _blast(e: Dictionary, db: Dictionary, d: Dictionary) -> void:
	var r: float = float(db.get("r", 55.0))
	var fx = g.mech("fx")
	if fx != null:
		fx.icebug_blast(e.pos, r)   # docs/401 §13：碎冰飞溅 + 寒雾 + 留霜（只画）
		e["no_body"] = true          # 本体（粉红源石晶体）不播死亡帧条、不碎像素（combat.kill 读）
	else:
		g.fx.append({"kind": "ring", "pos": e.pos, "r": r, "life": 0.35, "max": 0.35, "col": Color(0.7, 0.9, 1.0), "enemy": true})
		g.vfx.sparks(e.pos, Vector2.UP, Color(0.8, 1.0, 1.4), 10, 200.0)
	env_blast(e.pos, r, 10.0)
	if float(db.get("ice_t", 0.0)) > 0.0:
		ices.append([e.pos, r, g.t + float(db.ice_t)])
	if g.invuln <= 0.0 and g.ppos.distance_to(e.pos) < r + 12.0:
		g.combat.enemy_hit(e.dmg * float(db.get("mult", 1.2)), {"src_type": e.type, "env": true}, false, false, ["近战", "物理"], "atk_" + e.type)
		var c = _cold()
		if c != null:
			c.add_cold(float(d.get("cold_add", 40.0)), false)


## 环境伤害（熔岩口 / 源石结晶 / 冰爆）：在范围里的藤蔓 Boss 开脆弱窗口（脚本 sami_vine.gd on_env）
func env_blast(pos: Vector2, r: float, dur: float) -> void:
	for b in g.enemies:
		if b.dead or not b.boss:
			continue
		var sc = g.bai.boss(b.type)
		if sc != null and sc.has_method("on_env") and b.pos.distance_to(pos) < r + float(b.r):
			sc.on_env(b, dur)


func player_hit_mult(src: Dictionary) -> float:
	var t: String = str(src.get("type", src.get("src_type", "")))
	var d: Dictionary = D.ENEMIES.get(t, {})
	var m := 1.0
	var c = _cold()
	if g.frozen_t > 0.0 and d.has("frozen_mult"):
		m *= float(d.frozen_mult)
	elif c != null and c.cold >= 50.0 and d.has("frosted_mult"):
		m *= float(d.frosted_mult)
	if src.get("boss", false) and t in MECH_BOSS_KINGDOM:
		var km = g.mech("kingdom")
		if km != null and km.inside(g.ppos):
			m *= 1.5
	return m


func on_player_hit(dmg: float, src: Dictionary) -> void:
	if dmg <= 0.0:
		return
	var t: String = str(src.get("type", src.get("src_type", "")))
	var d: Dictionary = D.ENEMIES.get(t, {})
	if src.get("boss", false):
		for b in g.bosses:
			if not b.dead and b.type == t:
				var sc = g.bai.boss(b.type)
				if sc != null and sc.has_method("on_hit_leader"):
					sc.on_hit_leader(b)   # 哈兰【战意】叠层
	var ca: float = float(src.get("cold_add", d.get("cold_add", 0.0)))
	if ca > 0.0:
		var c = _cold()
		if c != null:
			c.add_cold(ca, bool(src.get("boss", false)))


func on_world_tick(dt: float) -> void:
	_aura_t += dt
	if _aura_t >= 0.2:
		var step: float = _aura_t
		_aura_t = 0.0
		auras = auras.filter(func(a): return not a.dead)
		var c = _cold()
		for a in auras:
			var ca = D.ENEMIES.get(a.type, {}).get("cold_aura", null)
			if c != null and ca is Dictionary and g.ppos.distance_to(a.pos) < float(ca.get("r", 150.0)):
				c.add_cold(float(ca.get("per_sec", 15.0)) * step, false)
	_vinebox_swap()
	if not ices.is_empty():
		ices = ices.filter(func(x): return float(x[2]) > g.t)
		for x in ices:
			if g.ppos.distance_to(x[0]) < float(x[1]):
				g.combat.slow_leader("ice", 0.15, 0.7)   # 冰面：站在上面移速 −30%
				break


## 补给箱换巨壳藤蔓（docs/392 §3.2）：2:00 以后新出的补给箱 20% 换成它，每局最多 2 次
func _vinebox_swap() -> void:
	if vineboxes >= 2 or g.t < 120.0 or not D.ENEMIES.has("vinebox"):
		return
	for e in g.enemies:
		if e.dead or not e.get("chest", false) or e.has("vb_rolled"):
			continue
		e["vb_rolled"] = true
		if _rng().randf() < 0.2:
			vineboxes += 1
			e.dead = true
			var v: Dictionary = g.spawner.spawn_enemy("vinebox", e.pos)
			v.ingots = int(D.ENEMIES.vinebox.get("ingots", 10))
			return


## 巨壳藤蔓 / 馈赠的占位标记；萨米 Boss 的场上实体（馈赠球、熔岩口、银凇、停驻点、稳定设施）由各 Boss 脚本 draw 画
func draw_ground(_w) -> void:
	var cv = g.wcv
	for x in ices:
		# 冰面（docs/401：原作 snslime dimian 冷白霜地）：淡霜面 + 边缘一圈 2 像素冰晶点，最后 0.6 秒淡出
		var fa: float = clampf((float(x[2]) - g.t) / 0.6, 0.0, 1.0)
		var r: float = float(x[1])
		for i in 18:
			var h: int = (i * 7919 + int(x[0].x) * 31 + int(x[0].y) * 17) & 1023
			var at: Vector2 = x[0] + Vector2.from_angle(TAU * float(i) / 18.0 + float(h % 13) * 0.02) * r * (0.62 + float(h % 37) / 100.0)
			cv.draw_rect(Rect2((at * 0.5).floor() * 2.0, Vector2(2, 2)), Color(0.86, 0.95, 1.0, 0.75 * fa))
	for b in g.bosses:
		if b.dead:
			continue
		var sc = g.bai.boss(b.type)
		if sc != null and sc.has_method("draw"):
			sc.draw(b, cv)
	for e in g.enemies:
		if e.dead:
			continue
		if float(e.get("gift_until", 0.0)) > g.t:
			cv.draw_arc(e.pos, float(e.r) + 6.0, 0.0, TAU, 16, Color(0.45, 0.5, 1.0, 0.7), 2.0)
		elif e.get("k_prop", false):
			cv.draw_colored_polygon(PackedVector2Array([e.pos + Vector2(0, -float(e.r) - 16), e.pos + Vector2(5, -float(e.r) - 10), e.pos + Vector2(0, -float(e.r) - 4), e.pos + Vector2(-5, -float(e.r) - 10)]), Color(0.7, 0.9, 1.0, 0.9))
