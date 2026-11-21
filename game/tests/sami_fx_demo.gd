extends Node
## 萨米敌人攻击特效试点演示（docs/401 §4）：--theme=sami 下跑正式 enemies_sys / Boss 脚本 / 弹幕 / 预警，四段：
## 染污躯壳（爪击 + 受击暴冲）→ 歪曲施法者（黑针法术弹）→ 冰爆源石虫（死亡冰爆）→ 邪魔的利刃（逐招强制出招）。
## 队长不会死（每帧补满血，照常挨打好看命中件）。录像：--write-movie <avi> --fixed-fps 30（tools 调用见 docs/401 §4）；--check 只跑模拟。
var g
var title: Label
const DT := 1.0 / 30.0
const O := Vector2(0, 0)   # 出生点附近有营地光（开场飞行器靠每帧切回 PLAY 去掉）
const SEGMENTS := [
	{"name": "染污躯壳 · 爪击 / 受击暴冲", "dur": 9.0, "spawn": [["husk", 6, 150.0]], "hurt": "husk"},
	{"name": "歪曲施法者 · 法术弹", "dur": 8.0, "rad": 0.0, "spawn": [["caster", 3, 230.0]]},
	{"name": "冰爆源石虫 · 死亡冰爆", "dur": 7.0, "spawn": [["icebug", 5, 120.0]], "kill": "icebug"},
	{"name": "邪魔的利刃", "dur": 22.0, "boss": "blade", "moves": ["斩击", "投刃", "回旋", "国度爆发", "追猎", "刃雨"]},
]


func _ready() -> void:
	var check_only := "--check" in OS.get_cmdline_user_args()
	Cfg.quality = "high"
	Cfg.character_id = "mizuki"
	AudioServer.set_bus_mute(0, true)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	g.state = g.S.PLAY
	g.mode = g.Mode.PLAY
	g.hud.visible = false
	g.panel.hide()
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = O
	g.zone_next_c = O
	g.zone_r = 900.0
	g.zone_next_r = 900.0
	var overlay := CanvasLayer.new()
	overlay.layer = 120
	add_child(overlay)
	title = Label.new()
	title.position = Vector2(22, 14)
	title.add_theme_font_override("font", load("res://fonts/ui.ttf"))
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	overlay.add_child(title)
	var counts := {}
	var only := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seg="): only = int(arg.substr(6))
	for si in SEGMENTS.size():
		if only >= 0 and si != only:
			continue
		var seg: Dictionary = SEGMENTS[si]
		setup(seg)
		var n: int = int(float(seg.dur) / DT)
		var mi := 0
		for frame_i in n:
			var el: float = frame_i * DT
			g.t += DT
			g.hp = g.max_hp
			g.invuln = maxf(0.0, g.invuln - DT)
			g.state = g.S.PLAY   # 开场飞行器只在 OPENING 画；游戏自己可能延后切回开场
			# 队长：慢慢绕小圈（躯壳 / 冰爆虫能贴上来），Boss 段绕大一点
			var rad: float = float(seg.get("rad", 150.0 if seg.has("boss") else 40.0))
			var a: float = el * 0.6
			g.ppos = O + Vector2(cos(a), sin(a) * 0.75) * rad + Vector2(60, 0)
			g.doc_pos = g.ppos + Vector2(10, 35)
			if seg.has("hurt") and frame_i % 20 == 0:
				_poke(str(seg.hurt))
			if seg.has("kill") and el > 1.2 and frame_i % 30 == 0:
				_kill_near(str(seg.kill))
			if seg.has("boss") and el > 1.0 and mi < seg.moves.size() and el >= 1.0 + 3.4 * mi:
				var b: Dictionary = g.bosses[0]
				var sc = g.bai.boss(b.type)
				var dv: Vector2 = g.ppos - b.pos
				if sc != null and sc.force_move(b, str(seg.moves[mi]), dv.normalized(), dv.length()):
					counts[str(seg.moves[mi])] = 1
				b.busy_t = g.t + 3.0
				mi += 1
			g.enemies_sys.build_grid()
			var nfx: int = g.fx.size()
			g.enemies_sys.update(DT)
			g.vfx.mark_enemy_fx(nfx)
			g.shots.step(DT)
			g.tele.update_warns(DT)
			g.enemies_sys.update_status(DT)
			g.enemies = g.enemies.filter(func(e): return not e.dead)
			title.text = "%s · %.1fs" % [seg.name, el] + ("\n" + str(seg.moves[maxi(0, mi - 1)]) if seg.has("boss") and mi > 0 else "")
			g.vfx.update(DT)
			g.fx = g.fx.filter(func(f): return f.life > 0.0)
			visual_step(DT)
			if frame_i % 45 == 0 and "--check" in OS.get_cmdline_user_args():
				var al: Array = g.enemies.filter(func(e): return not e.dead)
				print("DBG seg=%s f=%d alive=%d %s" % [seg.name.substr(0, 4), frame_i, al.size(), str(al.slice(0, 2).map(func(e): return [e.type, e.pos.round(), e.hp, e.get("tex", "")]))])
			await get_tree().process_frame
	var fx = g.mech("fx")
	print("SAMI_FX_DEMO moves=%d hits=%s" % [counts.size(), JSON.stringify(fx.hits if fx else {})])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func setup(seg: Dictionary) -> void:
	g.t = 100.0 + randf()
	for arr in [g.warns, g.enemies, g.fx, g.ebullets, g.shocks, g.lobs]:
		arr.clear()
	g.bosses = []
	g.boss = null
	g.bai.token_owner = null
	g.rng.seed = 40121
	g.rng_enemy.seed = 40122
	g.vrng.seed = 40123
	g.ppos = O + Vector2(60, 0)
	var km = g.mech("kingdom")
	if km != null:
		km.list.clear()
	for sp in seg.get("spawn", []):
		for i in int(sp[1]):
			var p: Vector2 = g.ppos + Vector2.from_angle(TAU * float(i) / float(sp[1]) + 0.4) * float(sp[2])
			var e: Dictionary = g.spawner.new_enemy(str(sp[0]), p)
			e.age = 3.0
			e.cdt = 0.3 + 0.5 * float(i)
			g.enemies.append(e)
	if seg.has("boss"):
		var e: Dictionary = g.spawner.new_enemy(str(seg.boss), O + Vector2(-120, 0))
		e.age = 3.0
		e.invuln = false
		e.wind = 0.0
		e.friendly = false
		e.hp = 1e9
		e.maxhp = 1e9
		g.enemies.append(e)
		g.bosses = [e]
		g.boss = e
		if km != null:
			for k in 4:
				km.add(O + Vector2(-260 + 170 * k, 150 - 90 * (k % 2)), 70.0, "boss", e, 40.0)


## 打一下离队长最近的躯壳（触发受击暴冲）
func _poke(type: String) -> void:
	var best = null
	var bd := 1e9
	for e in g.enemies:
		if e.dead or e.type != type or e.hp <= 2.0:
			continue
		var d: float = e.pos.distance_to(g.ppos)
		if d < bd:
			bd = d
			best = e
	if best != null:
		best.hp -= 1.0


func _kill_near(type: String) -> void:
	for e in g.enemies:
		if not e.dead and e.type == type:
			g.combat.kill(e)
			return


func visual_step(dt: float) -> void:
	for op in g.squad.ops:
		op.pos = g.ppos if op.is_leader else g.ppos + Vector2(-45, 45)
		op.anim_t += dt
	g.world.update_visuals(dt)
	g.queue_redraw()
	g.fx_add.queue_redraw()
	g.fg.queue_redraw()
	if g.foe_top != null:
		g.foe_top.queue_redraw()
