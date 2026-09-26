extends RefCounted
## 掉落与拾取：经验结晶 / 灯油 / 源石锭 / 宝箱的掉落、吸附、拾取结算，经验与升级触发。
## 升级后的选卡在 run/progression.gd。2026-09-26 从 game.gd 拆出。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game


func _init(game: Game) -> void:
	g = game


func count_items() -> int:
	var n := 0
	for g_item in g.gems:
		if g_item.kind == "magnet" or g_item.kind == "heal":
			n += 1
	return n


func drop(pos: Vector2, kind: String, val: float) -> void:
	if kind == "xp" and g.gems.size() > 350:
		gain_xp(val)
		return
	# 2.5D：掉落物带高度，从敌人位置弹出并落地回弹
	var sp := Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(20.0, 70.0)
	var special := kind == "magnet" or kind == "heal" or kind == "chest"
	g.gems.append({"pos": pos, "kind": kind, "val": val, "dead": false, "mag": false, "mag_t": 0.0,
		"z": 6.0, "vz": g.rng.randf_range(260.0, 300.0) if special else g.rng.randf_range(190.0, 260.0), "vel": sp * (0.5 if special else 1.1),
		"special": special, "landed": false, "age": 0.0, "seed": g.rng.randf() * TAU})


func update(dt: float) -> void:
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
					g._sparks(g_item.pos, Vector2.ZERO, lc, 10, 160.0)
					if g_item.kind != "chest":
						g._add_text(g_item.pos + Vector2(0, -34), item_name(g_item.kind), lc, 15)
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
			match g_item.kind:
				"xp":
					gain_xp(g_item.val)
					g.xp_flash = 0.3
					g._sparks(g.ppos + Vector2(0, -22), Vector2.ZERO, UI.CYAN if g_item.val < 5.0 else Color(0.85, 0.6, 1.0), 3 if g_item.val < 5.0 else 7, 150.0)
					Sfx.play("pickup", -14.0, 1.0 + min(g.xp / g.xp_need, 1.0) * 0.4, 0.03)
				"oil":
					var add: float = g_item.val * g.oil_mult
					g.lamp = min(g.lamp_cap, g.lamp + add)
					Sfx.play("oil", -4.0)
					g._add_text(g.ppos + Vector2(0, -90), "灯火 +%d" % int(add), UI.GOLD, 16)
				"chest":
					g.pending_chests += 1
				"ingot":
					g.ingots += int(g_item.val)
					Sfx.play("pickup", -10.0, 1.6, 0.05)
				"magnet":
					# 磁铁：吸取全场的经验、灯油和源石锭
					for o in g.gems:
						if not o.dead and (o.kind == "xp" or o.kind == "oil" or o.kind == "ingot"):
							o.mag = true
					g.fx.append({"kind": "ring", "pos": g.ppos, "r": 420.0, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.45, 0.5)})
					g._add_text(g.ppos + Vector2(0, -90), "磁铁：吸取全场掉落", Color(1.0, 0.55, 0.6), 17)
					Sfx.play("relic", -4.0, 1.2, 0.0)
				"heal":
					var hv := g.max_hp * 0.3
					g._heal(hv, "事件")
					g.fx.append({"kind": "ring", "pos": g.ppos, "r": 90.0, "life": 0.5, "max": 0.5, "col": Color(0.5, 1.0, 0.65)})
					g._sparks(g.ppos + Vector2(0, -20), Vector2.ZERO, Color(0.5, 1.0, 0.65), 16, 200.0)
					g._add_text(g.ppos + Vector2(0, -90), "+%d 生命" % int(hv), Color(0.5, 1.0, 0.65), 18)
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


func gain_xp(v: float) -> void:
	if g.demo_op != "":
		return
	g.xp += v
	while g.xp >= g.xp_need:
		g.xp -= g.xp_need
		g.level += 1
		g.xp_need = Bal.v("xp/a", 24.0) + g.level * Bal.v("xp/b", 8.0) + floor(g.level * g.level * Bal.v("xp/c", 0.8))
		g.pending_levelups += 1
		g.lv_times.append(int(g.t))
		levelup_fx()


## 升级演出：金色光环 + 冲击波推开周围敌人 + 头顶字样，0.5 秒后再弹出选项
func levelup_fx() -> void:
	g.lvup_show = 1.3
	g.hud_lv_flash = 1.0
	if g.lvup_delay <= 0.0:
		g.lvup_delay = 0.5
	g.invuln = max(g.invuln, 0.9)
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 150.0, "life": 0.5, "max": 0.5, "col": Color(1.0, 0.85, 0.4)})
	g.fx.append({"kind": "ring", "pos": g.ppos, "r": 80.0, "life": 0.35, "max": 0.35, "col": Color(0.6, 1.0, 0.95)})
	g._sparks(g.ppos + Vector2(0, -20), Vector2.ZERO, Color(1.0, 0.85, 0.45), 18, 320.0)
	for e in g.enemies_sys.query(g.ppos, 170.0):
		var en: Dictionary = g.enemies[e]
		if en.boss or en.chest:
			continue
		var d: Vector2 = en.pos - g.ppos
		en.kb = d.normalized() * 480.0 if d.length() > 0.1 else Vector2.RIGHT * 480.0
	Sfx.play("levelup", -6.0, 1.3, 0.0)
