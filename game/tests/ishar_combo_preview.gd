extends "res://tests/final_boss_fx_preview.gd"
## 伊莎玛拉连段录像（docs/170）：每段只强制起一组连段，之后由正式 AI、弹幕、预警推进；玩家无敌并连续移动。
## 第 7 秒击破一只连线海嗣，演示拆网减弹。
const SEG := 16.0
var only := ""   # --only=<连段名>：只录这一组
var seg := SEG    # --seg=<秒>：每段时长（判定点 / 擦弹录像 40 秒，10-29）
var act_only := -1   # --act=<1..3>：只录这一幕的第一组连段（之后由正式 AI 接着出）
var every := 2    # --every=1：每帧都存（30 帧/秒原速）；缺省隔帧 15 帧/秒

func _ready() -> void:
	kind = "ishar"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shotdir="): out_dir = arg.substr(10)
		if arg.begins_with("--quality="): quality = arg.substr(10)
		if arg.begins_with("--only="): only = arg.substr(7)
		if arg.begins_with("--seg="): seg = float(arg.substr(6))
		if arg.begins_with("--act="): act_only = int(arg.substr(6)) - 1
		if arg.begins_with("--every="): every = maxi(1, int(arg.substr(8)))
	var check_only := out_dir.is_empty()
	Cfg.quality = quality
	Cfg.character_id = "mizuki"
	AudioServer.set_bus_mute(0, true)
	g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	g.state = g.S.PLAY
	g.mode = g.Mode.PLAY
	g.hud.visible = false
	g.panel.hide()
	g.t = 100.0
	g.zone_frozen = true
	g.zone_state = 3
	g.zone_c = Vector2.ZERO
	g.zone_next_c = Vector2.ZERO
	g.zone_r = 650.0
	g.zone_next_r = 650.0
	g.invuln = 999.0
	g.rng.seed = 271027
	g.vrng.seed = 271028
	seed(271029)
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
	var cards = g.bai.boss("ishar").cards()
	for act in 3:
		for c in cards.CARDS[act]:
			if only != "" and c.name != only:
				continue
			if act_only >= 0 and (act != act_only or c != cards.CARDS[act][0]):
				continue
			fresh()
			g.ppos = Vector2(200, 60)
			boss.gates_passed = act
			boss.cds = {"ishar_close": INF}
			if act >= 1:
				g.bai.boss("ishar")._eyes_spawn(boss)
			for sl in boss.web:
				sl.next = INF
				sl.o.web_of = boss
			if load("res://scripts/core/balance.gd").v("test/preview_webwalk", 0.0) > 0.0:
				# 10-31 录「海嗣从屏幕外走进来」：清空环上的海嗣，1 秒后召唤合唱现叫
				for sl in boss.web:
					if sl.o != null:
						sl.o.dead = true
						sl.o = null
				boss.choir_next = g.t + 1.0
			var events: Array = []
			var watched: Array = []
			var peak := 0
			for frame_i in int(seg / DT):
				var elapsed: float = frame_i * DT
				g.invuln = 999.0
				g.ppos = g.ppos.move_toward(route(elapsed), 110.0 * DT)
				g.doc_pos = g.ppos + Vector2(10, 35)
				g.t += DT
				if frame_i == 6:
					cards.force(boss, c.name)
				if frame_i == int(7.0 / DT):
					for sl in boss.web:
						if sl.o != null and not sl.o.dead:
							g.combat.kill(sl.o)
							events.append({"event": "web_kill", "t": elapsed})
							break
				g.enemies_sys.build_grid()
				var nfx: int = g.fx.size()
				g.enemies_sys.update(DT)
				g.vfx.mark_enemy_fx(nfx)
				g.shots.step(DT)
				g.tele.update_warns(DT)
				g.enemies_sys.update_status(DT)
				for w in g.warns:
					if not is_same(w.owner, boss) or w.dmg <= 0.0 or watched.any(func(o): return is_same(o, w)): continue
					watched.append(w)
					if str(w.name) != "": events.append({"event": "warning", "name": str(w.name), "t": elapsed})
				peak = maxi(peak, g.ebullets.filter(func(b): return b.life > 0.0).size())
				var brk: float = boss.get("break_t", 0.0)
				var state: String = ("破绽 %.1fs" % brk) if brk > 0.0 else ("连段 · 剩 %d 段" % boss.get("card_q", []).size() if boss.get("card_live", false) else "调整")
				title.text = "伊莎玛拉 · 第%d幕 · %s · %s · %.1fs\n%s · %s" % [act + 1, c.name, quality, elapsed, str(boss.get("move_name", "")), state]
				g.vfx.update(DT)
				g.fx = g.fx.filter(func(f): return f.life > 0.0)
				visual_step(DT)
				await get_tree().process_frame
				if not check_only: await RenderingServer.frame_post_draw
				if frame_i % every == 0 and not check_only:
					if get_viewport().get_texture().get_image().save_png(out_dir.path_join("frame_%05d.png" % shot_i)) != OK:
						push_error("Could not save frame")
						get_tree().quit(4)
						return
					shot_i += 1
			print("FX_PREVIEW_METRICS ", JSON.stringify({"move": c.name, "act": act + 1, "bullet_peak": peak, "events": events}))
	print("FX_PREVIEW_DONE boss=ishar quality=%s frames=%d combos=true optical=%s" % [quality, shot_i, g.optical_on])
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()

## 连续绕行：玩家一直在跑
func route(t: float) -> Vector2:
	return Vector2(60, 0) + Vector2.from_angle(t * 0.55) * Vector2(250, 190)
