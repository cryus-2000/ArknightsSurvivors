extends Node
## Real warning/resolve regression for data-driven ordinary and elite secondary attacks.
const D = preload("res://scripts/data.gd")
var g: Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	call_deferred("run_checks")
func run_checks() -> void:
	g.set_process(false)
	g.t = 100.0
	var early_bone: Dictionary = g.spawner.new_enemy("bone", Vector2.ZERO)
	early_bone.age = 8.0
	early_bone.extra_next = 0.0
	g.ppos = Vector2(60, 0)
	g.eai.pattern(early_bone, Vector2.RIGHT, 60.0, 0.01, early_bone.spd)
	check(g.warns.is_empty(), "starter bones save their secondary attack for later threat stages")
	for kind in D.ENEMIES:
		var row: Dictionary = D.ENEMIES[kind]
		if row.get("role", "") != "boss" and kind != "tear":
			check(row.has("extra") or row.has("pattern") or row.get("burst", false), kind + " has an active attack beyond contact")
	for kind in ["reaper", "founder", "tracer", "nest"]:
		var row: Dictionary = D.ENEMIES[kind]
		check(float(row.extra.range) >= 140.0, kind + " late attack has useful reach")
		check(float(row.extra.get("first_delay", 9.0)) <= 1.4, kind + " late attack starts soon after entry")
	for kind in ["stone", "offspring", "spitter", "floater", "reaper", "founder", "tracer", "nest", "pocket", "skimmer", "mother", "mimic", "knight"]:
		var d: Dictionary = D.ENEMIES[kind]
		check(d.has("extra"), kind + " has secondary attack data")
		if not d.has("extra"):
			continue
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 5.0
		e.dormant = false
		e.wake_t = 0.0
		e.extra_next = 0.0
		if d.has("scream_r"):
			e["scream_t0"] = g.t - 3.0   # 箱形恐鱼：尖叫已结束（尖叫期间不出额外招式，见下方专项）
			e["scream_t1"] = g.t - 0.5
		g.warns.clear()
		g.ebullets.clear()
		g.ppos = Vector2(minf(float(d.extra.range) - 10.0, 140.0), 0.0)
		g.eai.pattern(e, Vector2.RIGHT, g.ppos.x, 0.01, e.spd)
		var warnings: Array = g.warns.filter(func(w): return w.get("secondary", false))
		check(warnings.size() == 1, kind + " creates one secondary warning")
		if warnings.is_empty():
			continue
		var w: Dictionary = warnings[0]
		check(w.owner == e and w.dur >= 0.6 and w.cancel_dead, kind + " readable cancellable warning")
		if kind == "founder":
			check(float(w.get("frost", 0.0)) > 0.0 and not e.has("frost_attack"), "founder crystal warning carries bounded frost")
		if kind == "tracer":
			check(float(w.get("nerve", 0.0)) > 0.0, "tracer tail warning carries nerve buildup")
		if kind == "pocket":
			check(float(w.get("stun", 0.0)) > 0.0 and float(w.stun) <= 0.25, "pocket pulse has brief capped stagger")
		check(e.extra_next > g.t, kind + " cooldown advances")
		var count: int = g.warns.size()
		g.eai.pattern(e, Vector2.RIGHT, g.ppos.x, 0.01, e.spd)
		check(g.warns.size() == count, kind + " no immediate repeat")
		if str(d.extra.mode) == "volley":
			g.bai._warn_resolve(w)
			check(g.ebullets.size() == int(d.extra.count), kind + " volley emits configured bullets")
			if not g.ebullets.is_empty():
				check(is_equal_approx(float(g.ebullets[0].get("corrode", -1.0)), e.corrode), kind + " inherits corrosion")
	g.warns.clear()
	g.ebullets.clear()
	# A new late enemy can start its special shortly after spawning, while the global warning cap still applies.
	g.t = 350.0
	var fresh: Dictionary = g.spawner.new_enemy("founder", Vector2.ZERO)
	check(fresh.extra_next - g.t <= 1.5, "late enemy first special no longer waits several seconds")
	fresh.age = 0.9
	g.t = fresh.extra_next + 0.01
	g.ppos = Vector2(280, 0)
	g.eai.pattern(fresh, Vector2.RIGHT, 280.0, 0.01, fresh.spd)
	check(g.warns.any(func(w): return w.get("secondary", false)), "fresh late enemy actually telegraphs an early attack")
	g.warns.clear()
	var second: Dictionary = g.spawner.new_enemy("founder", Vector2.ZERO)
	second.age = 5.0
	second.extra_next = 0.0
	g.eai.pattern(second, Vector2.RIGHT, 280.0, 0.01, second.spd)
	check(g.warns.is_empty(), "late secondary attacks are staggered across the crowd")
	g.t += 1.0
	g.eai.pattern(second, Vector2.RIGHT, 280.0, 0.01, second.spd)
	check(g.warns.size() == 1, "deferred secondary still fires after crowd spacing")
	g.warns.clear()
	g.eai.next_secondary_at = 0.0
	var stagger: Dictionary = g.spawner.new_enemy("pocket", Vector2.ZERO)
	stagger.age = 5.0
	stagger.extra_next = 0.0
	g.ppos = Vector2(50, 0)
	g.eai.pattern(stagger, Vector2.RIGHT, 50.0, 0.01, stagger.spd)
	var stagger_warning: Dictionary = g.warns[0]
	g.demo_op = ""
	g.hp = g.max_hp
	g.invuln = 0.0
	g.shield = 0
	g.bai._warn_resolve(stagger_warning)
	check(g.pstun > 0.0 and g.pstun <= 0.25, "pocket pulse stagger is short")
	g.pstun = 0.0
	g.invuln = 0.0
	g.bai._warn_resolve(stagger_warning)
	check(g.pstun == 0.0, "repeated stagger is gated globally")
	g.warns.clear()
	g.eai.next_secondary_at = 0.0
	var ice: Dictionary = g.spawner.new_enemy("founder", Vector2.ZERO)
	ice.age = 5.0
	ice.extra_next = 0.0
	g.ppos = Vector2(100, 0)
	g.invuln = 0.0
	g.hp = g.max_hp
	g.eai.pattern(ice, Vector2.RIGHT, 100.0, 0.01, ice.spd)
	var ice_warning: Dictionary = g.warns[0]
	g.bai._warn_resolve(ice_warning)
	check(g.frost > 0.0 and g.hp < g.max_hp, "telegraphed crystal strike applies short frost only on hit")
	g.frost = 0.0
	g.invuln = 0.0
	g.shield = 1
	g.bai._warn_resolve(ice_warning)
	check(g.frost == 0.0, "shield prevents special frost")
	g.shield = 0
	g.warns.clear()
	# Large packs must not fill the arena with simultaneous secondary warnings.
	var crowded: Dictionary = g.spawner.new_enemy("stone", Vector2.ZERO)
	crowded.age = 5.0
	crowded.extra_next = 0.0
	g.ppos = Vector2(140, 0)
	g.warns.clear()
	for i in 12:
		g.warns.append({"secondary": true})
	g.eai.pattern(crowded, Vector2.RIGHT, 140.0, 0.01, crowded.spd)
	check(g.warns.size() == 12 and crowded.extra_next == 0.0, "crowded secondary warnings wait without spending cooldown")
	g.warns.clear()
	# The third move must be reachable through the actual boss scheduler.
	# docs/95（10-14）起每只 Boss 4 招 = 数据招式 + 手写招式，数据条目数不再固定 3；这里只查「最后一条数据招式走得到调度器」，
	# 没有数据招式的（伊莎玛拉、骑士全手写）跳过
	for kind in ["path", "izumik", "iberia", "carmen", "bishop", "archon", "immortal", "paranoia", "ishar", "knight_boss"]:
		var d: Dictionary = D.ENEMIES[kind]
		var pats: Array = d.get("patterns", [])
		if pats.is_empty():
			continue
		var last: int = pats.size() - 1
		var e: Dictionary = g.spawner.new_enemy(kind, Vector2.ZERO)
		e.age = 5.0
		if kind in ["ishar", "izumik"]:
			g.bai.setup_preview_phase2(e)
		g.warns.clear()
		g.ppos = Vector2(280, 0)
		e.pattern_cycle = last
		e.pattern_next = g.t
		e.gates_passed = 9   # phase_min 条目也要走得到
		var lm: Dictionary = pats[last]
		if lm.get("manual", false) or lm.get("on_reload", false):
			e.pattern_force = str(lm.name)   # docs/95 §12 / §16：manual（订正）/ on_reload（清膛）不进轮转，只由 Boss 脚本点名；这里查点名路径走得到
		check(g.bai.patterns.try_attack(e, Vector2.RIGHT, 280.0), kind + " schedules new move")
		check(g.warns.any(func(w): return w.get("pattern_id", "") == kind + ":" + str(last)), kind + " last warning visible")
		if str(pats[last].mode) == "line" and not g.warns.is_empty():
			var line_warning: Dictionary = g.warns[0]
			check(line_warning.shape == "line" and g.warns[0].dur >= 0.6, kind + " line warning readable")
			g.invuln = 0.0
			g.shield = 0
			g.hp = g.max_hp
			g.demo_op = ""
			g.combat.boss_log.clear()
			g.combat.loss_log.clear()
			g.combat.any_log.clear()
			g.ppos = line_warning.pos + Vector2.from_angle(line_warning.ang) * 150.0 + Vector2(0, 14)
			g.bai._warn_resolve(g.warns[0])
			check(g.hp < g.max_hp, kind + " line move can hit")
		g.warns.clear()
	# Queued attacks must vanish with their owner, even for circle warnings.
	var fallen: Dictionary = g.spawner.new_enemy("pocket", Vector2.ZERO)
	fallen.age = 5.0
	fallen.extra_next = 0.0
	g.ppos = Vector2(70, 0)
	g.eai.pattern(fallen, Vector2.RIGHT, 70.0, 0.01, fallen.spd)
	var hp_before: float = g.hp
	fallen.dead = true
	g.bai._update_warns(2.0)
	check(is_equal_approx(g.hp, hp_before) and g.ebullets.is_empty(), "dead secondary owner cannot deal damage")
	# docs/96 第 3 批挂点（Codex 未交）：帧条名经 enemies.json 传到出招 / 弹体 / 抛射物；有图时自爆与冲刺水痕放帧条
	# （借第 1 批已有的 fx_corrode_hit 代替还没交的 fx_runner_blast / fx_slider_dash，测完还原数据）
	g.invuln = 100.0
	var keep_blast = D.ENEMIES["runner"].get("blast_fx")
	D.ENEMIES["runner"]["blast_fx"] = "fx_corrode_hit"
	var ru: Dictionary = g.spawner.new_enemy("runner", Vector2.ZERO)
	ru.blast_w = 0.01
	g.fx.clear()
	g.eai.pattern(ru, Vector2.RIGHT, 300.0, 0.05, ru.spd)
	check(ru.dead and g.fx.any(func(f): return f.get("name", "") == "fx_corrode_hit") and not g.fx.any(func(f): return f.kind == "explode"), "runner blast_fx replaces the program explosion")
	D.ENEMIES["runner"]["blast_fx"] = keep_blast
	var keep_dash = D.ENEMIES["slider"].get("dash_fx")
	D.ENEMIES["slider"]["dash_fx"] = "fx_corrode_hit"
	var sl: Dictionary = g.spawner.new_enemy("slider", Vector2.ZERO)
	sl.dash_t = 0.3
	sl.dash_dir = Vector2.LEFT
	g.fx.clear()
	g.eai.pattern(sl, Vector2.RIGHT, 300.0, 0.05, sl.spd)
	check(g.fx.any(func(f): return f.kind == "gsprite" and f.get("name", "") == "fx_corrode_hit"), "slider dash leaves a ground-layer dash_fx trail")
	D.ENEMIES["slider"]["dash_fx"] = keep_dash
	var os_e: Dictionary = g.spawner.new_enemy("offspring", Vector2.ZERO)
	os_e.nova_w = 0.01
	g.ebullets.clear()
	g.eai.pattern(os_e, Vector2.RIGHT, 300.0, 0.05, os_e.spd)
	check(not g.ebullets.is_empty() and g.ebullets.all(func(b): return str(b.get("tex", "")) == "proj_offspring_spore"), "offspring nova carries shot_tex")
	g.ebullets.clear()
	var mi: Dictionary = g.spawner.new_enemy("mimic", Vector2.ZERO)
	mi.age = 5.0
	mi.dormant = false
	mi.extra_next = INF   # 只看尖叫与啃咬，箱舌突刺上面已测
	g.warns.clear()
	g.ppos = Vector2(40, 0)
	# 现形尖叫（docs/145 §4 A）：第一次靠近即开始；张口 + 尖叫期间不咬、照常移动、圈内累积神经损伤
	var md: Dictionary = D.ENEMIES["mimic"]
	g.nerve_aura_t = 0.0
	check(g.eai.pattern(mi, Vector2.RIGHT, 40.0, 0.05, mi.spd) == Vector2.INF and mi.has("scream_t0"), "mimic starts screaming on first approach and keeps normal movement")
	check(g.warns.is_empty(), "mimic does not bite while screaming")
	g.t = float(mi.scream_t0) + 0.1
	g.invuln = 0.0
	g.eai.pattern(mi, Vector2.RIGHT, 40.0, 0.05, mi.spd)
	check(g.nerve_aura_t > 0.0 and g.warns.is_empty(), "mimic scream builds nerve inside its radius without biting")
	g.nerve_aura_t = 0.0
	g.eai.pattern(mi, Vector2.RIGHT, float(md.scream_r) + 20.0, 0.05, mi.spd)
	check(g.nerve_aura_t <= 0.0, "mimic scream does not reach outside its radius")
	g.t = float(mi.scream_t1) + 0.01
	g.eai.pattern(mi, Vector2.RIGHT, 40.0, 0.05, mi.spd)
	check(g.warns.any(func(w): return w.get("act", "") == "bite" and str(w.get("atk_fx", "")) == "fx_mimic_bite"), "mimic bite carries atk_fx")
	# 连咬（docs/145 §4 B）：第一口结算时补第二口，单独预警、伤害 × bite2_mult
	var b1: Dictionary = g.warns.filter(func(w): return w.get("act", "") == "bite")[0]
	g.warns.clear()
	mi.wind = 0.0
	g.t = float(mi.bite2_at) + 0.01
	g.eai.pattern(mi, Vector2.RIGHT, 40.0, 0.05, mi.spd)
	var b2: Array = g.warns.filter(func(w): return w.get("act", "") == "bite")
	check(b2.size() == 1 and is_equal_approx(float(b2[0].dmg), float(b1.dmg) * float(md.bite2_mult)) and is_equal_approx(float(b2[0].dur), float(md.bite2_delay)), "mimic second bite has its own warning and reduced damage")
	g.warns.clear()
	var st_e: Dictionary = g.spawner.new_enemy("stone", Vector2.ZERO)
	g.lobs.clear()
	g.eai.lob(st_e)
	check(not g.lobs.is_empty() and str(g.lobs[g.lobs.size() - 1].get("hit_fx", "")) == "fx_rock_hit" and float(g.lobs[g.lobs.size() - 1].get("hit_org", [0, 0])[0]) == 10.0 and float(g.lobs[g.lobs.size() - 1].get("hit_org", [0, 0])[1]) == 10.0, "stone lob carries hit_fx and its origin")
	g.lobs.clear()
	print("ENEMY ATTACK VARIETY failures=", failures)
	g.warns.clear()
	g.enemies.clear()
	g.bosses.clear()
	g.queue_free()
	g = null
	Sfx.set_process(false)
	await get_tree().create_timer(0.25, true, false, true).timeout
	for player in Sfx.get_children():
		if player is AudioStreamPlayer:
			player.stop()
			player.stream = null
			player.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout
	get_tree().quit(0 if failures == 0 else 1)

