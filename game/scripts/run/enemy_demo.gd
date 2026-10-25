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
const BITE_OUT := 36.0      # 贴身循环：扑一口后弹到离接触半径外这么远（再按原速走回来）；冲量按主体自己的移速反算，见 _contact_cycle
const BITE_CD := 1.2        # 同一只至少隔这么久再扑


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
			subject.hp = subject.maxhp * 0.66
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
	g.demo_label = "真实 AI · 移动 → 蓄势 → 攻击 · 队长为不死演示靶"


func _seed_heal_targets() -> void:
	# 人形阶段提供真正受伤的普通海嗣；只设置初始伤势，治疗与特效均走正式逻辑。
	for offset in [Vector2(90, -65), Vector2(150, 0), Vector2(100, 75)]:
		var target := g.spawner.spawn_enemy("bone", subject.pos + offset)
		target["heal_demo_target"] = true
		target.hp = target.maxhp * 0.35


## 贴身循环（用户 10-16：图鉴里怪物卡在干员模型边缘停住不动；同 run/demo.gd _contact_cycle 的口径）：
## 演示靶不会死也不会走开，近战主体一路走到靶脚下之后就只剩每帧的接触判定（原地播攻击帧），再看不出「移动 → 蓄势 → 攻击」。
## 按正式局同一接触半径（e.r + 12）判「扑上来」：播攻击帧条（atk_until）、沿离靶方向弹开（走正式击退入口 apply_kb，重型怪补回 A 段的 ×0.3），
## 再以原速走回来，每只至少隔 BITE_CD 秒——「扑上来 → 弹开 → 再上来」。Boss / 远程 / 中立 / 正在放招（eai.busy）的不弹；只在图鉴里调用。
## 冲量按主体移速反算：击退 kb 按 900/s 衰减、同时它还在以 spd 往回走，净弹开 ≈ kb² / 1800 − spd·kb / 900；要弹到 e.r + BITE_OUT 外
## （正式移速的骨海漂流体 240 的固定冲量只弹开 15，没出接触半径就又贴上了）
func _contact_cycle() -> void:
	for e in g.enemies:
		if e.dead or e.boss or e.ai != "melee" or e.get("friendly", false) or g.t < float(e.get("demo_bite", 0.0)) or g.eai.busy(e):
			continue
		var off: Vector2 = e.pos - g.ppos
		var d: float = off.length()
		if d >= e.r + 12.0:
			continue
		e["demo_bite"] = g.t + BITE_CD
		e.atk_until = g.t + 0.25
		var want: float = e.r + BITE_OUT
		var kb: float = e.spd + sqrt(e.spd * e.spd + 1800.0 * want)
		if D.ENEMIES[e.type].get("heavy", false):
			kb /= 0.3
		g.enemies_sys.apply_kb(e, (off / d if d > 0.5 else Vector2.LEFT) * kb)


func cycle_period() -> float:
	if subject.get("type", "") == "ishar":
		return 50.0 if phase_mode == 0 else (10.0 if phase_mode == 1 else 35.0)
	return 35.0 if subject.get("boss", false) else 14.0


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
	_contact_cycle()
	g.enemies_sys.build_grid()
	g.enemies_sys.update(dt)
	g.shots.step(dt)
	g.tele.update_warns(dt)
	g.enemies_sys.update_status(dt)
	g.vfx.update(dt)
	g.lvup_delay -= dt   # 原在 vfx.update 里（docs/101 B3），顺序不变
	g.hp = g.max_hp
	g.gems.clear()
	g.texts = g.texts.filter(func(tx): return tx.life > 0.0)
	# 图鉴不走 game._cleanup：敌弹 / 抛物命中或到期只是 life 置 0（enemies/shot_pool.gd），回收在 _cleanup 里——这里不回收就一直留在原地画
	# （用户 10-16：图鉴里子弹命中后不消失）。我方子弹 / 特效同理
	g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
	g.bullets = g.bullets.filter(func(b): return b.life > 0.0)
	g.fx = g.fx.filter(func(f): return f.life > 0.0)
	g.enemies = g.enemies_sys.sweep_dead(g.enemies)
	# 看完一整轮再重置位置。死亡型 / 蜕变型有 2 秒收尾，Boss 留 35 秒展示三组招式。
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
			g.demo_label = "泪滴不伤害队长 · " + ("靠近压制充能中" if subject.get("blocked", false) else "远离时加速转化")
		else:
			g.demo_label = "%s%s · %s · 队长为不死演示靶" % [subject.name, stage, action]
