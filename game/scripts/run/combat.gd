extends RefCounted
## 战斗结算：对敌伤害（伤害描述符、护甲 / 易伤 / 藏品倍率，契约 v2.0）、击杀与掉落触发、主控受击（闪避 / 护盾 / 减伤 / 法抗）、
## 治疗、神经损伤、缩圈（黑潮区域）。干员经 characters/op_api.gd 调用。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 「追击」（docs/35）：带这些标签的伤害吃 followup_dmg 与追击类藏品（追击、余震、殉爆、召唤物）
const FOLLOWUP_TAGS := ["follow_up", "aftershock", "detonation", "entity"]
const ECOL := {"bone": Color(0.85, 0.9, 0.85), "slider": Color(0.45, 0.7, 1.0), "stone": Color(0.7, 0.7, 0.75), "offspring": Color(0.6, 0.9, 0.5),
	"brood": Color(0.9, 0.6, 0.8), "pocket": Color(0.8, 0.55, 1.0), "skimmer": Color(0.4, 0.9, 0.9), "mother": Color(0.9, 0.5, 0.7),
	"mimic": Color(1.0, 0.75, 0.4), "path": Color(0.6, 0.7, 1.0), "fractal": Color(0.6, 0.7, 1.0), "izumik": Color(0.5, 1.0, 0.7),
	"ishar": Color(0.75, 0.55, 1.0), "tear": Color(0.75, 0.55, 1.0), "iberia": Color(1.0, 0.6, 0.5), "carmen": Color(0.7, 0.7, 1.0),
	"ripper": Color(0.95, 0.55, 0.6), "burrower": Color(0.7, 0.5, 1.0), "spitter": Color(0.6, 1.0, 0.65), "hulk": Color(1.0, 0.95, 0.75),
	"bishop": Color(0.7, 1.0, 0.9), "archon": Color(0.5, 0.9, 0.9), "immortal": Color(0.6, 0.8, 1.0), "paranoia": Color(0.8, 0.6, 1.0)}
var flesh_heal := false
var ember := false
var zone_from_c := Vector2.ZERO
var zone_from_r := 99999.0
var zone_phase := 0
var zone_hurt_t := 0.0
const ZONE_START := 150.0
const ZONE_RADII := [1300.0, 1000.0, 780.0, 600.0, 480.0]
var low_warned := false


func _init(game: Game) -> void:
	g = game


## 敌人命中水月：闪避判定、侵蚀、神经损伤
func enemy_hit(dmg: float, src: Dictionary, ignore_armor := false, no_dodge := false) -> void:
	if g.demo_op != "":
		return
	if not no_dodge and g.in_type[1] != "真实" and g.rng.randf() < min(g.dodge + (g.dodge_arts if g.in_type[1] == "法术" else g.dodge_phys), 0.6):
		g.invuln = 0.3
		Sfx.play("dodge", -4.0)
		g.vfx.add_text(g.ppos + Vector2(0, -80), "闪避", Color(0.6, 0.85, 1.0), 16)
		on_dodge()
		return
	if g.shield > 0:
		shield_block()
		return
	for o in g.squad.ops:
		if o.has_method("dmg_taken_mult"):
			dmg *= o.dmg_taken_mult()
	hurt(dmg * (1.15 if g.lamp < 30.0 else 1.0), ignore_armor)
	# 灯火只在受击时熄灭：基础 4 + 伤害占最大生命的比例 × 30（10% 血的一击 -7），受「灯火消耗」修正
	var lamp_loss: float = (Bal.v("lamp/hit_base", 4.0) + Bal.v("lamp/hit_scale", 30.0) * dmg / g.max_hp) * g.lamp_decay
	g.lamp = maxf(0.0, g.lamp - lamp_loss)
	if lamp_loss >= 6.0:
		g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -%d" % int(lamp_loss), Color(1.0, 0.6, 0.4), 13)
	if src.get("corrode", 0.0) > 0.0:
		g.corrode_pool += dmg * src.corrode * Bal.v("enemy/corrode_mult", 2.0) * g.corrode_taken_mult
		g.vfx.add_text(g.ppos + Vector2(14, -64), "侵蚀", Color(0.8, 0.5, 1.0), 13)
	if src.get("nerve", 0.0) > 0.0:
		add_nerve(src.nerve * g.nerve_taken_mult)


func on_dodge() -> void:
	g.rfx.on_dodge()


func add_nerve(v: float) -> void:
	g.nerve += v
	if g.nerve >= 100.0:
		g.nerve = 0.0
		g.pstun = 0.4
		g.atk_slow = maxf(g.atk_slow, 2.5)
		g.dmg_src = "nerve"
		g.in_type = ["近战", "真实"]
		hurt(g.max_hp * 0.08, true)
		g.vfx.add_text(g.ppos + Vector2(0, -100), "神经损伤！", Color(1.0, 0.5, 0.9), 20)
		Sfx.play("skill", -4.0, 1.6)


func hurt(amount: float, ignore_armor := false) -> void:
	if g.in_type[1] != "真实":
		amount *= g.rfx.taken_mult()
	if not ignore_armor and g.in_type[1] == "物理":
		amount = max(1.0, amount - g.armor)
	elif g.in_type[1] == "法术":
		amount = max(1.0, amount * (1.0 - minf(g.arts_res, 0.7)))
	g.hp -= amount
	g.rfx.on_hurt(g.dmg_src == "nerve")
	g.dmg_log[g.dmg_src] = g.dmg_log.get(g.dmg_src, 0.0) + amount
	g.invuln = 0.45
	g.hurt_flash = 0.2
	# 受击反馈按伤害占最大生命的比例分级
	var sev := clampf(amount / g.max_hp / 0.12, 0.0, 1.0)
	g.hurt_vignette = 0.6 + 0.4 * sev
	g.red_flash = maxf(g.red_flash, 0.12 + 0.25 * sev)
	g.hp_shake = 0.35
	g.head_bar_t = 2.5
	g.vfx.shake_screen(0.55 + 0.8 * sev)
	g.hitstop = max(g.hitstop, 0.045 + 0.06 * sev)
	Sfx.play("hurt", -1.0 + 3.0 * sev, 1.0 - 0.2 * sev, 0.05)
	Pad.rumble(0.25 + 0.35 * sev, 0.1 + 0.6 * sev, 0.12 + 0.12 * sev)
	g.vfx.sparks(g.ppos + Vector2(0, -24), Vector2.UP, Color(1.0, 0.3, 0.35), 6 + int(8 * sev), 220.0)
	g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, -10), "r": 40.0 + 30.0 * sev, "life": 0.25, "max": 0.25, "col": Color(1.0, 0.3, 0.35)})
	g.vfx.add_text(g.ppos + Vector2(randf_range(-14, 14), -84), "-%d" % int(amount), Color(1.0, 0.3, 0.3), int(20 + 10 * sev))
	# 首次跌破 30%：时间短暂变慢 + 警告
	if g.hp > 0.0 and g.hp < g.max_hp * 0.3 and not low_warned:
		low_warned = true
		g.hitstop = max(g.hitstop, 0.35)
		g.vfx.show_banner("生命垂危！")
	elif g.hp > g.max_hp * 0.45:
		low_warned = false


## 缩圈：预告 20 秒 → 收缩 25 秒 → 稳定，直到下一轮；圈外为「黑潮」
func update_zone(dt: float) -> void:
	if g.zone_state == 0:
		if g.t < ZONE_START:
			return
		g.zone_c = g.ppos
		g.zone_r = ZONE_RADII[0] + 400.0
		zone_phase = -1
		g.zone_state = 3
		g.zone_t = 0.0
	g.zone_t += dt
	match g.zone_state:
		3:
			if g.zone_t >= (0.0 if zone_phase < 0 else 45.0) and zone_phase < ZONE_RADII.size() - (2 if g.ending == "resolve" else 1):
				zone_phase += 1
				g.zone_next_r = ZONE_RADII[zone_phase]
				var off := Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(0.0, (g.zone_r - g.zone_next_r) * 0.7)
				g.zone_next_c = g.zone_c + off
				g.zone_state = 1
				g.zone_t = 0.0
				g.vfx.show_banner("黑潮将至：%d 秒后安全区缩小" % 20)
				Sfx.play("roar", -6.0, 0.5, 0.0)
		1:
			if g.zone_t >= 20.0:
				g.zone_state = 2
				g.zone_t = 0.0
				zone_from_c = g.zone_c
				zone_from_r = g.zone_r
				g.vfx.show_banner("黑潮正在逼近！")
		2:
			var k := clampf(g.zone_t / 25.0, 0.0, 1.0)
			g.zone_c = zone_from_c.lerp(g.zone_next_c, k)
			g.zone_r = lerpf(zone_from_r, g.zone_next_r, k)
			if k >= 1.0:
				g.zone_state = 3
				g.zone_t = 0.0
	# 圈外：黑潮伤害 + 灯火流失 + 神经损伤
	var out := g.ppos.distance_to(g.zone_c) - g.zone_r
	if out > 0.0 and g.state == g.S.PLAY and not g.squad.in_sanctuary(g.ppos):
		var dps: float = (2.5 + 1.5 * max(zone_phase, 0)) * (1.0 + minf(out / 300.0, 1.0))
		g.hp -= dps * dt
		g.dmg_log["zone"] = g.dmg_log.get("zone", 0.0) + dps * dt
		g.lamp = maxf(0.0, g.lamp - 6.0 * dt)
		zone_hurt_t -= dt
		if zone_hurt_t <= 0.0:
			zone_hurt_t = 0.8
			g.hurt_flash = maxf(g.hurt_flash, 0.08)
			g.head_bar_t = 2.0
			g.vfx.add_text(g.ppos + Vector2(0, -84), "黑潮", Color(0.8, 0.4, 1.0), 16)


func in_zone(p: Vector2, margin := 0.0) -> bool:
	return g.zone_state == 0 or p.distance_to(g.zone_c) < g.zone_r - margin


## 护盾抵挡一次伤害：碎裂特效，可选冲击波与回复
func shield_block() -> void:
	g.shield -= 1
	g.shield_flash = 0.3
	g.invuln = 0.5
	if g.shield < g.shield_max and g.shield_cd <= 0.0:
		g.shield_cd = g.shield_every
	Sfx.play("dodge", -2.0, 1.4, 0.0)
	g.vfx.add_text(g.ppos + Vector2(0, -84), "护盾抵挡", Color(0.6, 0.9, 1.0), 16)
	# 碎片
	for k in 14:
		g.fx.append({"kind": "shard", "pos": g.ppos + Vector2(0, -24), "vel": Vector2.from_angle(randf() * TAU) * randf_range(120, 260),
			"life": 0.5, "max": 0.5, "rot": randf() * TAU})
	g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, -20), "r": 50.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 0.9, 1.0)})
	if g.shield_heal:
		heal(g.max_hp * 0.03, "藏品")
	if g.shield_burst:
		for j in g.enemies_sys.query(g.ppos, 140.0):
			var e: Dictionary = g.enemies[j]
			if not e.dead and e.pos.distance_to(g.ppos) < 140.0:
				damage(e, 30.0 * g.dmg_mult)
				if not e.boss:
					e.kb += (e.pos - g.ppos).normalized() * 420.0
		g.fx.append({"kind": "explode", "pos": g.ppos, "r": 140.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.85, 1.0)})
		g.vfx.shake_screen(0.6)


## 这次伤害是否算「追击」（docs/35）
func is_followup(h: Dictionary) -> bool:
	for tg in h.tags:
		if tg in FOLLOWUP_TAGS:
			return true
	return false


## 敌人生命的时间倍率（不含难度）：藏品的直接伤害按它缩放，保证各时段同样「有感」
func enemy_hp_time_mult() -> float:
	var hk: float = Bal.v("enemy/hp_knee", 480.0)
	return 1.0 + minf(g.t, hk) / Bal.v("enemy/hp_div", 120.0) + maxf(g.t - hk, 0.0) / Bal.v("enemy/hp_late_div", 300.0)


## 设置当前伤害描述符（extra_tags 追加本次特有标签，如 empowered）
func hit(src: String, extra_tags: Array = []) -> void:
	var base: Dictionary = g.hit_src.get(src, {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []})
	g.hit = {"src": src, "emitter": base.emitter, "origin": base.origin, "range": base.range, "kind": base.kind, "tags": base.tags + extra_tags,
		"class": base.get("class", ""), "op": base.get("op", "")}


func damage(e: Dictionary, dmg: float) -> void:
	if e.dead:
		return
	# 灯火照亮：光中的敌人受到的伤害 +25%（流明光弹的「照亮」e.lit 同样视为在灯光内）
	if e.pos.distance_squared_to(g.ppos) < g._lamp_r() * g._lamp_r() or e.get("lit", 0.0) > 0.0:
		dmg *= 1.25
	if e.invuln:
		if g.texts.size() < 80 and g.vrng.randf() < 0.2:
			g.vfx.add_text(e.pos + Vector2(0, -e.r - 10), "无效", Color(0.6, 0.7, 0.8), 13)
		return
	if e.chest and e.hidden:
		e.hidden = false
		g.spawner.reveal_mimic(e)
		return
	var ty: Array = [g.hit.range, g.hit.kind]
	var weak_hit := false
	if ty[1] != "真实":
		dmg *= e.def * g.rfx.dmg_extra()
		# 弱点：对应类型伤害 +50%（藏品可加成 / 赋予双弱点）
		var wk: String = e.get("weak", "")
		if wk == ty[1] or (wk == "双" and ty[1] != "真实") or (g.rfx.rule("all_weak") > 0):
			dmg *= 1.5 + g.weak_bonus
			weak_hit = true
		dmg *= g.melee_mult if ty[0] == "近战" else g.ranged_mult
		if e.get("aura_weak", 0.0) > 0.0:
			dmg *= 1.1
		dmg *= g.arts_mult if ty[1] == "法术" else g.phys_mult
		if is_followup(g.hit):
			dmg *= g.followup_mult * g.rfx.followup_extra()
		dmg *= g.rfx.hit_mult(g.hit)
		# Logos「安魂」：受到的法术伤害 +15%
		if ty[1] == "法术" and e.get("requiem", 0.0) > 0.0:
			dmg *= 1.15
		if g.low_hp_bonus > 0.0 and e.hp < e.maxhp * 0.5:
			dmg *= 1.0 + g.low_hp_bonus
		if e.boss and g.final_boss != null and is_same(e, g.final_boss):
			dmg *= 1.0 + 0.01 * g.rfx.rule("final_taken") + (0.8 if g.rfx.rule("bone_blood") > 0 else 0.0)
	g.rfx.on_hit(e, g.hit)
	e.hp -= dmg
	var eff: float = minf(dmg, maxf(e.hp + dmg, 0.0))
	g.dmg_out[g.hit.src] = g.dmg_out.get(g.hit.src, 0.0) + eff
	if g.hit.origin == "relic":
		g.relic_out += eff
	g.dmg_type_out[ty[1]] = g.dmg_type_out.get(ty[1], 0.0) + eff
	for tg in g.hit.tags:
		g.dmg_tag_out[tg] = g.dmg_tag_out.get(tg, 0.0) + eff
	e.hits += 1
	e.flash = 0.08
	e.squash = 0.14
	# 伤害数字的位置抖动是纯画面，用 g.vrng：飘字数量取决于画面随机数（上面的「无效」），设置里还能关掉伤害数字，
	# 用 g.rng 会让机器负载 / 玩家设置改变对局随机数（docs/36 §3）
	if g.texts.size() < 80 and Cfg.dmg_numbers:
		if g.crit_hit:
			g.vfx.add_text(e.pos + Vector2(g.vrng.randf_range(-6, 6), -e.r - 10), str(int(round(dmg))), UI.GOLD, 22)
		elif weak_hit:
			g.vfx.add_text(e.pos + Vector2(g.vrng.randf_range(-6, 6), -e.r - 12), "弱点 " + str(int(round(dmg))), Color(1.0, 0.85, 0.35), 18)
		else:
			g.vfx.add_text(e.pos + Vector2(g.vrng.randf_range(-6, 6), -e.r - 8), str(int(round(dmg))), Color(1, 1, 1, 0.95), 14)
	# 圣徒装填时被打断
	if e.get("channel", 0.0) > 0.0:
		e.channel = 0.0
		e.stun = 6.0
		e.ammo = 0
		e.ai = "melee"
		g.vfx.add_text(e.pos + Vector2(0, -50), "装填被打断！", UI.GOLD, 20)
		g.vfx.shake_screen(0.5)
	# "偏执泡影"：首次被控制后失去悬浮，进入第二形态
	if e.type == "paranoia" and e.phase == 1 and e.stun > 0.3:
		e.phase = 2
		e.range = 400.0
		e.weak = "物理"
		e.dmg *= 1.2
		g.vfx.show_banner("\"偏执泡影\" 失去悬浮 —— 第二形态")
		Sfx.play("roar", 0.0, 1.2, 0.0)
	# 掠海漂移体被控制后落地，改为近战
	if e.get("hover_lost", false) == false and D.ENEMIES.has(e.type) and D.ENEMIES[e.type].get("hover", false) and e.stun > 0.3:
		e.hover_lost = true
		e.ai = "melee"
		e.spd = 70.0
		g.vfx.add_text(e.pos + Vector2(0, -30), "坠落", Color(0.6, 0.9, 1.0), 16)
	if e.hp <= 0.0:
		# 最后的骑士：第一次归零不死，寒冰重生（二阶段）
		if e.type == "knight_boss" and e.phase == 1:
			e.phase = 2
			e.hp = e.maxhp * 0.5
			e.spd *= 1.2
			e.invuln = true
			e.channel = 1.5
			e.stun = 0.0
			e.kb = Vector2.ZERO
			if not g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0):
				g.fx.append({"kind": "ring", "pos": e.pos, "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.9, 1.4)})
			g.vfx.show_banner("寒冰重生 —— 最后的骑士 第二阶段")
			Sfx.play("roar", 0.0, 0.9, 0.0)
			g.vfx.shake_screen(1.2)
			return
		if D.ENEMIES.get(e.type, {}).get("pair", false) and e.get("partner") != null and not e.partner.dead:
			e.hp = 1.0
			e.coma = true
			e.invuln = true
			e.stun = 0.0
			g.vfx.add_text(e.pos + Vector2(0, -50), "昏迷（同时击倒另一体）", Color(0.6, 1.0, 0.9), 16)
			return
		kill(e)


func heal(v: float, src: String = "其他") -> void:
	v *= g.heal_mult
	var got: float = minf(v, maxf(0.0, g.max_hp - g.hp))
	g.heal_log[src] = float(g.heal_log.get(src, 0.0)) + got
	if v > got:
		g.rfx.on_overheal(v - got)
	g.hp = min(g.max_hp, g.hp + v)


func kill(e: Dictionary) -> void:
	g.rfx.on_kill(e)
	if e.dead:
		return
	e.dead = true
	# 海嗣祭坛：打开事件选项
	if e.chest and e.get("event", "") != "":
		Sfx.play("relic", -2.0, 0.8)
		g.vfx.sparks(e.pos, Vector2.UP, Color(0.5, 0.8, 1.4), 18, 260.0)
		g.fx.append({"kind": "rays", "pos": e.pos, "life": 0.7, "max": 0.7, "col": Color(0.5, 0.8, 1.0)})
		g.endg.open(e.event)
		return
	# 补给箱被打碎
	if e.chest:
		Sfx.play("relic", -6.0, 1.3)
		g.vfx.sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 12, 220.0)
		for k in g.rng.randi_range(3, 6):
			g.pickups.drop(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(4.0, 18.0), "ingot", 1.0)
		if g.rng.randf() < 0.3:
			g.pickups.drop(e.pos + Vector2(10, 6), "oil", 15.0)
		return
	if e.type != "tear":
		g.kills += 1
	if e.has("horde") and e.horde < g.horde_log.size():
		var hl: Dictionary = g.horde_log[e.horde]
		hl.killed += 1
		if hl.t80 < 0 and hl.killed >= int(hl.n * 0.8):
			hl.t80 = int(g.t) - hl.t
	var col: Color = ECOL.get(e.type, Color(0.6, 0.9, 0.9))
	g.vfx.sparks(e.pos, Vector2.ZERO, col, 7, 160.0)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 1.2, "life": 0.18, "max": 0.18, "col": col})
	Sfx.play("kill", -8.0)
	if e.get("tex_death", false) and g.V6_FRAMES.has(e.tex + "_death"):
		var dtx: Texture2D = g.tex[e.tex + "_death"]
		var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * g.PX)
		g.vfx.fx_sprite(e.tex + "_death", foot + Vector2(0, -(dtx.get_height() - 3) * g.PX * 0.5), g.PX, 0.0)
	elif not g.vfx.fx_sprite("fx_death_dissolve", e.pos, g.PX * max(1.0, e.r / 12.0)):
		g.vfx.anim("fx_death", e.pos, 0.3, g.PX * max(1.0, e.r / 12.0))
	if e.elite:
		g.elites_killed += 1
	if e.elite or e.boss:
		Sfx.play("boom", 0.0, 1.0, 0.0)
		g.hitstop = max(g.hitstop, 0.12)
		g.vfx.shake_screen(1.0)
		g.vfx.sparks(e.pos, Vector2.ZERO, UI.GOLD, 24, 320.0)
	g.squad.on_kill(e)
	if flesh_heal and e.evo:
		heal(g.max_hp * 0.03, "藏品")
	if ember and e.elite:
		g.lamp = min(g.lamp_cap, g.lamp + 20.0)
	if e.xp > 0.0:
		g.pickups.drop(e.pos, "xp", e.xp * g.xp_mult)
	if g.rng.randf() < 0.012 * (0.5 if g.diff >= 3 else 1.0):
		g.pickups.drop(e.pos + Vector2(8, 0), "oil", 15.0)
	# 特殊道具：磁铁 / 回复（小怪低概率，精英与 Boss 必掉其一）
	if e.elite or e.boss:
		g.pickups.drop(e.pos + Vector2(-16, 8), "magnet" if g.rng.randf() < 0.5 else "heal", 1.0)
	elif g.pickups.count_items() < 3:
		var r := g.rng.randf()
		if r < 0.0025:
			g.pickups.drop(e.pos, "magnet", 1.0)
		elif r < 0.006:
			g.pickups.drop(e.pos, "heal", 1.0)
	var ing: int = D.ENEMIES.get(e.type, {}).get("ingots", 0)
	if e.elite:
		ing = max(ing, g.rng.randi_range(3, 5))
		g.pickups.drop(e.pos, "chest", 1.0)
		g.pickups.drop(e.pos + Vector2(20, 10), "oil", 25.0)
	if e.boss:
		ing = 20
		if not is_same(e, g.final_boss) and not g.spawner.boss_alive():
			Sfx.play_overlay("boss_down")   # 最终 Boss 走结算乐句；双 Boss 需全部倒下
		g.pickups.drop(e.pos + Vector2(-20, 0), "chest", 1.0)
		for j in 12:
			g.pickups.drop(e.pos + Vector2.from_angle(TAU * j / 12.0) * 30.0, "xp", 20.0)
		# Boss 倒下时清除它召唤的东西
		for o in g.enemies:
			if (o.type == "tear" and e.type == "ishar") or (o.feed and is_same(o.get("feed_to"), e)):
				o.dead = true
	if g.diff >= 5 and ing > 0:
		ing = int(floor(ing * 0.7 + g.rng.randf()))
	for k in ing:
		g.pickups.drop(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(6.0, 26.0), "ingot", 1.0)
