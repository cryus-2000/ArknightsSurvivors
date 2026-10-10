extends RefCounted
## 掉落与拾取：经验结晶 / 灯油 / 源石锭 / 宝箱的掉落、吸附、拾取结算，经验与升级触发。
## 升级后的选卡在 run/progression.gd。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


## 场上的磁铁 + 回复药剂数；传 kind 时只数这一种（磁铁单独上限用）
func count_items(kind := "") -> int:
	var n := 0
	for g_item in g.gems:
		if kind != "":
			if g_item.kind == kind and not g_item.dead:
				n += 1
		elif g_item.kind == "magnet" or g_item.kind == "heal":
			n += 1
	return n


func drop(pos: Vector2, kind: String, val: float) -> void:
	if kind == "xp":
		xp_dropped += val
		# 兜底（docs/38 §8.13 方案 A）：场上掉落物 > pickup/gem_overflow（400）时新掉的经验直接入账，算回收、另记次数。
		# recall_after = 0（关回收、走旧逻辑对照）时同一条就是旧的「溢出自动入账」
		if g.gems.size() > int(Bal.v("pickup/gem_overflow", 400.0)):
			recall_backstop += 1
			xp_backstop += val
			_count_xp("recall", val)
			gain_xp(val)
			return
	# 2.5D：掉落物带高度，从敌人位置弹出并落地回弹。弹出随机走独立随机流（局种子派生，§8.13）：掉落怎么改都不影响对局 g.rng 的序列
	var r := _drop_rng()
	var sp := Vector2.from_angle(r.randf() * TAU) * r.randf_range(20.0, 70.0)
	var special := kind == "magnet" or kind == "heal" or kind == "chest"
	g.gems.append({"pos": pos, "kind": kind, "val": val, "dead": false, "mag": false, "mag_t": 0.0,
		"z": 6.0, "vz": r.randf_range(260.0, 300.0) if special else r.randf_range(190.0, 260.0), "vel": sp * (0.5 if special else 1.1),
		"special": special, "landed": false, "age": 0.0, "seed": r.randf() * TAU, "out_t": 0.0})


## 掉落弹出用的独立随机流：第一次用时按局种子派生（g.rng.seed 只读、不消耗），同 seed 可复现
var _drop_r: RandomNumberGenerator = null

func _drop_rng() -> RandomNumberGenerator:
	if _drop_r == null:
		_drop_r = RandomNumberGenerator.new()
		_drop_r.seed = hash([g.rng.seed, "pickups.drop"])
	return _drop_r


## 经验分来源计数（BALANCE：xp_walk / xp_magnet / xp_recall 与各自按分钟分段，docs/38 §8.13 第 6 条）
func _count_xp(src: String, v: float) -> void:
	xp_src[src] += v
	var arr: Array = xp_src_min[src]
	var mi: int = int(g.t / 60.0)
	while arr.size() <= mi:
		arr.append(0.0)
	arr[mi] += v


## 视野外回收（docs/38 §8.13 方案 A，数值 10-01）：落地、没被吸起的经验结晶，持续在逻辑视野（view_center ± 640×360，
## 再外扩 pickup/recall_margin）之外累计满 pickup/recall_after 秒就直接入账并移除；回到视野内重新计时。
## 每 pickup/recall_tick 秒批量判定一次。只回收 kind == "xp"；recall_after = 0 关闭（走旧的溢出逻辑）。
## 逻辑视野用固定的项目分辨率、不读实际窗口和镜头震动，同 seed 在任何机器上结果一致。
## HUD（界面与美术）读 recall_hud_n / recall_hud_t：最近一次判定回收的经验量与时刻（按判定间隔自然聚合）
var recall_acc := 0.0
var recall_hud_n := 0.0
var recall_hud_t := -INF

func _recall_tick(dt: float) -> void:
	var after: float = Bal.v("pickup/recall_after", 6.0)
	if after <= 0.0:
		return
	recall_acc += dt
	var tick: float = maxf(Bal.v("pickup/recall_tick", 1.0), 0.05)
	if recall_acc < tick:
		return
	var step := recall_acc
	recall_acc = 0.0
	var half := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)), float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))) * 0.5
	var view := Rect2(g.view_center() - half, half * 2.0).grow(Bal.v("pickup/recall_margin", 96.0))
	var got := 0.0
	for g_item in g.gems:
		if g_item.dead or g_item.kind != "xp" or g_item.mag or g_item.get("z", 0.0) > 0.0:
			continue
		if view.has_point(g_item.pos):
			g_item.out_t = 0.0
			continue
		g_item.out_t = float(g_item.get("out_t", 0.0)) + step
		if g_item.out_t >= after:
			g_item.dead = true
			got += g_item.val
	if got > 0.0:
		recall_n += 1
		_count_xp("recall", got)
		gain_xp(got)
		recall_hud_n = got
		recall_hud_t = g.t
		g.xp_flash = 0.3


## 拾取范围随等级成长（§8.13 第 3 条）：属性系统里独立的乘区，来源「等级」；× (1 + range_per_level × (等级 − 1))，封顶 +range_level_cap
func sync_level_pickup() -> void:
	var bonus: float = minf(Bal.v("pickup/range_per_level", 0.01) * float(g.level - 1), Bal.v("pickup/range_level_cap", 0.25))
	g.stats.remove_source("等级")
	if bonus > 0.0:
		g.stats.add(&"pickup", "mult", 1.0 + bonus, "等级")
	g.sync_stats()


## 地上还没捡的经验（BALANCE 守恒用）
func xp_on_ground() -> float:
	var s := 0.0
	for g_item in g.gems:
		if not g_item.dead and g_item.kind == "xp":
			s += g_item.val
	return s


func update(dt: float) -> void:
	_recall_tick(dt)
	for g_item in g.gems:
		if g_item.dead:
			continue
		if g_item.has("vz") and (g_item.z > 0.0 or g_item.vz != 0.0):
			g_item.vz -= 700.0 * dt
			g_item.z += g_item.vz * dt
			g_item.pos += g_item.vel * dt
			if g_item.z <= 0.0:
				g_item.z = 0.0
				g_item.vel *= 0.4
				if g_item.special and not g_item.landed:
					g_item.landed = true
					var lc := item_col(g_item.kind)
					g.fx.append({"kind": "ring", "pos": g_item.pos, "r": 34.0, "life": 0.4, "max": 0.4, "col": lc})
					g.vfx.sparks(g_item.pos, Vector2.ZERO, lc, 10, 160.0)
					if g_item.kind != "chest":
						g.vfx.add_text(g_item.pos + Vector2(0, -34), item_name(g_item.kind), lc, 15)
					Sfx.play("pickup", -8.0, 0.7, 0.0)
				g_item.vz = -g_item.vz * 0.35 if g_item.vz < -60.0 else 0.0
				if g_item.vz == 0.0:
					g_item.vel = Vector2.ZERO
		g_item.age = g_item.get("age", 0.0) + dt
		var d: float = g_item.pos.distance_to(g.ppos)
		if g_item.get("special", false) and g_item.kind != "chest" and d > 40.0 and not g_item.mag:
			continue
		# 掉落先弹出落地、停留一瞬（让玩家看见），再被吸向水月：越吸越快
		var settled: bool = g_item.get("z", 0.0) <= 0.0 and g_item.age > 0.4
		if g_item.mag or (settled and d < g.pickup * (1.2 if g.lamp >= 70.0 else (0.7 if g.lamp < 30.0 else 1.0))):
			g_item.mag = true
			g_item["mag_t"] = g_item.get("mag_t", 0.0) + dt
			g_item.z = 0.0
			g_item.pos = g_item.pos.move_toward(g.ppos + Vector2(0, -12), (240.0 + 1300.0 * g_item.mag_t) * dt)
			d = g_item.pos.distance_to(g.ppos + Vector2(0, -12))
		if d < 20.0:
			g_item.dead = true
			if g_item.kind != "xp":
				g.vfx.pickup_burst(g_item.kind, UI.GOLD if g_item.kind == "oil" else item_col(g_item.kind))   # docs/54 ⑦（fx/pickup_burst）
			match g_item.kind:
				"xp":
					_count_xp("magnet" if g_item.get("by_magnet", false) else "walk", g_item.val)
					gain_xp(g_item.val)
					g.xp_flash = 0.3
					g.vfx.sparks(g.ppos + Vector2(0, -22), Vector2.ZERO, UI.CYAN if g_item.val < 5.0 else Color(0.85, 0.6, 1.0), 3 if g_item.val < 5.0 else 7, 150.0)
					Sfx.play("pickup", -14.0, 1.0 + min(g.xp / g.xp_need, 1.0) * 0.4, 0.03)
				"oil":
					var add: float = g_item.val * g.oil_mult
					g.lamp = min(g.lamp_cap, g.lamp + add)
					Sfx.play("oil", -4.0)
					g.vfx.add_text(g.ppos + Vector2(0, -90), "灯火 +%d" % int(add), UI.GOLD, 16)
				"chest":
					g.pending_chests += 1
				"ingot":
					g.ingots += int(g_item.val)
					Sfx.play("pickup", -10.0, 1.6, 0.05)
				"magnet":
					# 磁铁：吸取全场的经验、灯油和源石锭
					item_log.magnet_pick += 1
					for o in g.gems:
						if not o.dead and (o.kind == "xp" or o.kind == "oil" or o.kind == "ingot"):
							if not o.mag:
								o["by_magnet"] = true   # 经验分来源：磁铁吸回（已经在吸的不改）
							o.mag = true
					g.fx.append({"kind": "ring", "pos": g.ppos, "r": 420.0, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.45, 0.5)})
					g.vfx.add_text(g.ppos + Vector2(0, -90), "磁铁：吸取全场掉落", Color(1.0, 0.55, 0.6), 17)
					Sfx.play("relic", -4.0, 1.2, 0.0)
				"heal":
					item_log.heal_pick += 1
					var hv := g.max_hp * 0.3
					g.combat.heal(hv, "拾取")
					g.fx.append({"kind": "ring", "pos": g.ppos, "r": 90.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.65)})
					g.vfx.sparks(g.ppos + Vector2(0, -20), Vector2.ZERO, Color(0.5, 1.0, 0.65), 16, 200.0)
					g.vfx.add_text(g.ppos + Vector2(0, -90), "+%d 生命" % int(hv), Color(0.5, 1.0, 0.65), 18)
					Sfx.play("relic", -4.0, 1.5, 0.0)


func item_col(kind: String) -> Color:
	match kind:
		"magnet":
			return Color(1.0, 0.5, 0.55)
		"heal":
			return Color(0.5, 1.0, 0.65)
		"chest":
			return UI.GOLD
	return UI.CYAN


func item_name(kind: String) -> String:
	return {"magnet": "磁铁", "heal": "回复药剂"}.get(kind, "")


## 前 12 级保持原曲线，之后逐级增加费用，至 30 级达到后期倍率。
func xp_required(level: int) -> float:
	var base: float = Bal.v("xp/a", 24.0) + level * Bal.v("xp/b", 8.0) + floor(level * level * Bal.v("xp/c", 0.8))
	var start: float = Bal.v("xp/late_from_level", 12.0)
	var finish: float = Bal.v("xp/late_full_level", 30.0)
	var ramp: float = clampf((float(level) - start) / maxf(1.0, finish - start), 0.0, 1.0)
	return ceil(base * lerpf(1.0, Bal.v("xp/late_mult", 1.95), ramp))


## 平衡输出（telemetry）：一局经验总量、其中溢出直接入账的量、按分钟分段的溢出量
var xp_total := 0.0
var item_log := {"magnet_mob": 0, "magnet_elite": 0, "heal_mob": 0, "heal_elite": 0, "magnet_pick": 0, "heal_pick": 0, "mob_rolled": 0, "mob_capped": 0}   # 磁铁 / 回复药剂的掉落（按小怪 / 精英 Boss）与拾取次数（平衡输出）
## 经验分来源（docs/38 §8.13）：walk 走近捡、magnet 磁铁吸回、recall 视野外回收（含兜底直接入账）；守恒：
## xp_dropped = walk + magnet + recall + xp_on_ground()（BALANCE 逐局，tools/check.py 断言）
var xp_src := {"walk": 0.0, "magnet": 0.0, "recall": 0.0}
var xp_src_min := {"walk": [], "magnet": [], "recall": []}
var xp_dropped := 0.0        # drop() 收到的经验总值（含兜底直接入账的）
var xp_backstop := 0.0       # 其中兜底直接入账的经验（已算进 recall）
var recall_backstop := 0     # 兜底触发次数
var recall_n := 0            # 视野外回收发生的判定次数（有回收的那几次）
var xp_total_min: Array = []   # 按分钟分段的总经验（和 xp_src_min 对齐，下标 = 游戏分钟）


func gain_xp(v: float) -> void:
	if g.demo_op != "":
		return
	xp_total += v
	var tm: int = int(g.t / 60.0)
	while xp_total_min.size() <= tm:
		xp_total_min.append(0.0)
	xp_total_min[tm] += v
	g.xp += v
	var lv0: int = g.level
	while g.xp >= g.xp_need:
		g.xp -= g.xp_need
		g.level += 1
		g.xp_need = xp_required(g.level)
		g.pending_levelups += 1
		g.lv_times.append(int(g.t))
		levelup_fx()
	if g.level != lv0:
		sync_level_pickup()


## 升级演出：金色光环 + 冲击波推开周围敌人 + 头顶字样，0.5 秒后再弹出选项
func levelup_fx() -> void:
	g.lvup_show = 1.3
	g.hud_lv_flash = 1.0
	if g.lvup_delay <= 0.0:
		g.lvup_delay = 0.5
	g.invuln = max(g.invuln, 0.9)
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 150.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4)})
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 80.0, "life": 0.35, "max": 0.35, "col": Color(0.6, 1.0, 0.95)})
	g.vfx.sparks(g.ppos + Vector2(0, -20), Vector2.ZERO, Color(1.0, 0.85, 0.45), 18, 320.0)
	g.vfx.levelup_burst(g.ppos)   # docs/54 ②：柔光 + 光柱 + 光尘 + 轻闪（fx/levelup_burst）
	for e in g.enemies_sys.query(g.ppos, 170.0):
		var en: Dictionary = g.enemies[e]
		if en.boss or en.chest:
			continue
		var d: Vector2 = en.pos - g.ppos
		en.kb = d.normalized() * 480.0 if d.length() > 0.1 else Vector2.RIGHT * 480.0
	Sfx.play("levelup", -6.0, 1.3, 0.0)
