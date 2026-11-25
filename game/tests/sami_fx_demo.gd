extends Node
## 萨米敌人攻击特效试点演示（docs/401 §4 / §9）：--theme=sami 下跑正式 enemies_sys / Boss 脚本 / 弹幕 / 预警。
## 每个镜头录两遍：先 1 倍全景，再 2 倍放大中心（同种子重放，画面一致）。镜头：染污躯壳（爪击 + 受击暴冲）→ 歪曲施法者（黑针法术弹）
## → 冰爆源石虫（死亡冰爆）→ 邪魔的利刃逐招（docs/393 §11.2 七招 + 呼吸，每招一个镜头；队长绕小圈走，看瞄准 / 落点跟人）。
## 队长不会死（每帧补满血，照常挨打好看命中件）；水下滤镜（含暗角）关掉。
## 录像：--write-movie <avi> --fixed-fps 30，加 --nokingdomdraw 不画国度占位（国度画面暂停）；--seg=N 只录第 N 个镜头；--z1 只录 1 倍不放大；--check 无头只跑模拟。
var g
var title: Label
var base_zoom := Vector2.ONE
const DT := 1.0 / 30.0
const O := Vector2(0, 0)
const BLADE_MOVES := ["斩击·竖刃", "投刃·切雾", "国度爆发", "黑毯", "追猎·卷毯", "国度刃雨"]   # docs/393 §11.2 新招
const KINGDOM_SEGS := ["国度爆发", "国度刃雨"]   # 这几镜先摆 3 块它的国度


func _shots() -> Array:
	var a: Array = [
		{"name": "染污躯壳 · 爪击 / 受击暴冲", "dur": 6.0, "spawn": [["husk", 6, 150.0]], "hurt": "husk"},
		{"name": "歪曲施法者 · 法术弹", "dur": 6.0, "rad": 0.0, "spawn": [["caster", 3, 200.0]]},
		{"name": "冰爆源石虫 · 死亡冰爆", "dur": 5.0, "spawn": [["icebug", 4, 110.0]], "kill": "icebug"},
	]
	for m in BLADE_MOVES:
		a.append({"name": "邪魔的利刃 · " + m, "dur": 3.6, "boss": "blade", "move": m, "rad": 45.0})
	a.append({"name": "邪魔的利刃，游荡者 · 皇帝的猎杀", "dur": 3.6, "boss": "wanderer", "move": "皇帝的猎杀", "rad": 45.0})
	a.append({"name": "邪魔的利刃 · 呼吸（国度外胀）", "dur": 4.2, "boss": "blade", "rad": 0.0, "kd": true})
	return a


func _ready() -> void:
	var check_only := "--check" in OS.get_cmdline_user_args()
	Cfg.quality = "high"
	Cfg.character_id = "mizuki"
	Cfg.water_filter = false   # 水下滤镜带暗角（用户 11-25：看不清）
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
	base_zoom = g.cam.zoom
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
	var zooms := [1.0, 2.0]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seg="): only = int(arg.substr(6))
		if arg == "--z1": zooms = [1.0]   # 只录 1 倍全景
	var shots := _shots()
	for si in shots.size():
		if only >= 0 and si != only:
			continue
		var seg: Dictionary = shots[si]
		for zk in zooms:
			setup(seg)
			var n: int = int(float(seg.dur) / DT)
			var moved := false
			for frame_i in n:
				var el: float = frame_i * DT
				g.t += DT
				g.hp = g.max_hp
				g.invuln = maxf(0.0, g.invuln - DT)
				g.state = g.S.PLAY   # 开场飞行器只在 OPENING 画；游戏自己可能延后切回开场
				var rad: float = float(seg.get("rad", 40.0))
				var a: float = el * 0.6
				g.ppos = O + Vector2(cos(a), sin(a) * 0.75) * rad + Vector2(60, 0)
				g.doc_pos = g.ppos + Vector2(10, 35)
				if seg.has("hurt") and frame_i % 20 == 0:
					_poke(str(seg.hurt))
				if seg.has("kill") and el > 0.8 and frame_i % 30 == 0:
					_kill_near(str(seg.kill))
				if seg.has("move") and not moved and el >= 0.5:
					moved = true
					var b: Dictionary = g.bosses[0]
					var sc = g.bai.boss(b.type)
					var dv: Vector2 = g.ppos - b.pos
					if sc != null and sc.force_move(b, str(seg.move), dv.normalized(), dv.length()):
						counts[str(seg.move)] = 1
					b.busy_t = g.t + 9.0
				g.enemies_sys.build_grid()
				var nfx: int = g.fx.size()
				g.enemies_sys.update(DT)
				g.vfx.mark_enemy_fx(nfx)
				g.shots.step(DT)
				g.tele.update_warns(DT)
				g.enemies_sys.update_status(DT)
				g.enemies = g.enemies.filter(func(e): return not e.dead)
				title.text = "%s · %s" % [seg.name, "1 倍全景" if zk == 1.0 else "2 倍放大"]
				g.vfx.update(DT)
				g.fx = g.fx.filter(func(f): return f.life > 0.0)
				visual_step(DT, zk, seg)
				await get_tree().process_frame
	var fx = g.mech("fx")
	print("SAMI_FX_DEMO moves=%d hits=%s" % [counts.size(), JSON.stringify(fx.hits if fx else {})])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()


func setup(seg: Dictionary) -> void:
	g.t = 100.0
	for arr in [g.warns, g.enemies, g.fx, g.ebullets, g.shocks, g.lobs]:
		arr.clear()
	g.bosses = []
	g.boss = null
	g.bai.token_owner = null
	g.rng.seed = 40121
	g.rng_enemy.seed = 40122
	g.vrng.seed = 40123
	var fx = g.mech("fx")
	if fx != null:
		fx.rng.seed = 40124
		fx.strips.clear()
		fx.parts.clear()
		fx.rushers.clear()
		fx.marks.clear()
		fx.bevents.clear()
		fx.blade_list.clear()
	var foes = g.mech("foes")
	if foes != null:
		foes.ices.clear()
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
		var e: Dictionary = g.spawner.new_enemy(str(seg.boss), O + Vector2(-90, 0))
		e.age = 3.0
		e.invuln = false
		e.wind = 0.0
		e.friendly = false
		e.hp = 1e9
		e.maxhp = 1e9
		e.busy_t = 1e9   # 不自己挑招，只放镜头指定的那招
		e.lay_t = 1e9   # 镜头里不自己再铺国度（国度画面暂停；国度爆发只用下面摆好的几块）
		g.enemies.append(e)
		g.bosses = [e]
		g.boss = e
		if km != null and (str(seg.get("move", "")) in KINGDOM_SEGS or seg.get("kd", false)):
			for k in 3:
				km.add(O + Vector2(-150 + 150 * k, 110 - 70 * (k % 2)), 70.0, "boss", e, 40.0)


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


func visual_step(dt: float, zk: float, seg: Dictionary) -> void:
	for op in g.squad.ops:
		op.pos = g.ppos if op.is_leader else g.ppos + Vector2(-45, 45)
		op.anim_t += dt
	g.cam.zoom = base_zoom * zk
	g.world.update_visuals(dt)
	if zk > 1.0:
		# 2 倍放大中心：小怪镜头对准队长，Boss 镜头对准 Boss 与队长的中点
		var c: Vector2 = g.ppos
		if not g.bosses.is_empty():
			c = (g.ppos + (g.bosses[0].pos as Vector2)) * 0.5
		g.cam.position = c.round()
	g.queue_redraw()
	g.fx_add.queue_redraw()
	g.fg.queue_redraw()
	if g.foe_top != null:
		g.foe_top.queue_redraw()
