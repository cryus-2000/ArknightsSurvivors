extends RefCounted
## 敌人图鉴实机演示：只调敌方的正式 AI / 弹幕 / 预警，不更新刷怪、干员攻击、掉落或存档。
## 主控是不会死亡的受击靶；切换条目时整个 SubViewport 销毁，状态不带进正式对局。

const Game = preload("res://scripts/game.gd")
const D = preload("res://scripts/data.gd")
var g: Game
var elapsed := 0.0
var phase_mode := 0             # 0 自动轮播，1 / 2 固定形态
var cycle := 0
var subject: Dictionary = {}
var started := false


func _init(game: Game) -> void:
	g = game


func configure(mode: int) -> void:
	phase_mode = clampi(mode, 0, 2)
	cycle = 0
	started = false


func reset() -> void:
	elapsed = 0.0
	started = true
	for arr in [g.enemies, g.bosses, g.bullets, g.ebullets, g.lobs, g.shocks, g.warns, g.mires, g.gems, g.fx, g.texts]:
		arr.clear()
	g.final_boss = null
	g.hitstop = 0.0
	g.invuln = 0.0
	g.corrode_pool = 0.0
	g.nerve = 0.0
	g.pstun = 0.0
	g.atk_slow = 0.0
	g.frost = 0.0
	g.world.boss_seen.clear()
	if g.demo_origin == Vector2.INF:
		g.demo_origin = g.ppos
	g.ppos = g.map.push_out(g.demo_origin + Vector2(110, 72), 12.0)
	g.doc_pos = g.ppos + Vector2(26, 20)
	g.facing = -1.0
	g.pvel = Vector2.ZERO
	g.moving = false
	g.ch.pos = g.ppos
	g.ch.face = -1.0
	g.cam.zoom = Vector2(0.8, 0.8)
	g.lamp = 100.0
	g.zone_state = 0
	var id: String = g.demo_enemy
	if not D.ENEMIES.has(id):
		return
	subject = g.spawner.spawn_enemy(id, g.demo_origin + Vector2(-130, 72))
	subject.age = 2.1           # 图鉴跳过登场保护；所有预警时长、弹速、技能与正式局完全一致
	subject.cdt = 0.4
	subject["dash_cd"] = 0.4
	subject["nova_cd"] = 0.4
	if subject.boss:
		g.bosses.append(subject)
		g.boss = subject
		if D.ENEMIES[id].get("pair", false):
			var partner_id := "archon" if id == "bishop" else "bishop"
			var partner := g.spawner.spawn_enemy(partner_id, subject.pos + Vector2(0, -40))
			subject.partner = partner
			partner.partner = subject
			g.bosses.append(partner)
		if phase_mode == 2 or (id != "ishar" and phase_mode == 0 and cycle % 2 == 1):
			g.bai.setup_preview_phase2(subject)
	else:
		# 囊海爬行者靠失血触发爆裂；演示只设置一次场景条件，不用假特效替代技能。
		if subject.has("burst_at"):
			subject.hp = subject.maxhp * 0.8
		if id == "tear":
			# 泪滴单独条目也复用中立泪滴机制，不演示已移除的踩踏伤害。
			subject.friendly = true
			subject.invuln = true
			subject.owner = g.spawner.spawn_enemy("ishar", subject.pos + Vector2(-130, -20))
		if id == "tear" or id == "brood":
			g.ppos = subject.pos + Vector2(8, 0)
			g.ch.pos = g.ppos
	if id == "ishar" and subject.get("friendly", false):
		_seed_heal_targets()
	g.demo_label = "真实 AI · 移动 → 蓄势 → 攻击 · 主控为不死演示靶"


func _seed_heal_targets() -> void:
	# 人形阶段提供真正受伤的普通海嗣；只设置初始伤势，治疗与特效均走正式逻辑。
	for offset in [Vector2(90, -65), Vector2(150, 0), Vector2(100, 75)]:
		var target := g.spawner.spawn_enemy("bone", subject.pos + offset)
		target["heal_demo_target"] = true
		target.hp = target.maxhp * 0.35


func cycle_period() -> float:
	if subject.get("type", "") == "ishar":
		return 40.0 if phase_mode == 0 else (10.0 if phase_mode == 1 else 18.0)
	return 18.0 if subject.get("boss", false) else 10.0


func step(dt: float) -> void:
	if not started:
		reset()
	if subject.is_empty():
		return
	elapsed += dt
	g.hp = g.max_hp
	g.xp = 0.0
	g.invuln = maxf(0.0, g.invuln - dt)
	g.hurt_flash = maxf(0.0, g.hurt_flash - dt)
	g.pstun = 0.0
	g.lamp = 100.0
	g.frame_n += 1
	if subject.type == "ishar" and subject.get("friendly", false) and not g.enemies.any(func(e): return e.get("heal_demo_target", false) and not e.dead):
		_seed_heal_targets()
	g.enemies_sys.build_grid()
	g.enemies_sys.update(dt)
	g.enemies_sys.update_ebullets(dt)
	g.bai._update_warns(dt)
	g.enemies_sys.update_status(dt)
	g.vfx.update(dt)
	g.hp = g.max_hp
	g.gems.clear()
	g.texts = g.texts.filter(func(tx): return tx.life > 0.0)
	g.enemies = g.enemies.filter(func(e): return not e.dead)
	# 看完一整轮再重置位置。死亡型 / 蜕变型有 2 秒收尾，Boss 留 18 秒展示多招。
	var period := cycle_period()
	if (subject.dead and elapsed > 3.0) or elapsed >= period or (subject.type == "ishar" and phase_mode == 1 and subject.phase == 2):
		cycle += 1
		reset()
	if not subject.is_empty():
		var stage := " · 二阶段" if subject.phase == 2 else ""
		var action: String = subject.get("move_name", "")
		if action == "":
			action = "预警中" if subject.wind > 0.0 else ("攻击中" if g.t < float(subject.get("atk_until", 0.0)) else "接近目标")
		if subject.type == "ishar" and subject.get("friendly", false):
			var charge: float = float(subject.get("ally_charge", 0.0)) / maxf(0.01, float(subject.get("ally_charge_need", 30.0)))
			g.demo_label = "人形 · 治疗海嗣 / 转化充能 %d%%" % roundi(clampf(charge, 0.0, 1.0) * 100.0)
		elif subject.type == "tear":
			g.demo_label = "泪滴不伤害主控 · " + ("靠近压制充能中" if subject.get("blocked", false) else "远离时加速转化")
		else:
			g.demo_label = "%s%s · %s · 主控为不死演示靶" % [subject.name, stage, action]
