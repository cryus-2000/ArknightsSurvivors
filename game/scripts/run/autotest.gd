extends RefCounted
## 自动测试 / 平衡机器人（docs/29、docs/36）：--autotest / --balance 的逐帧驱动、截图开关、机器人走位与选卡。
## 只在带测试参数启动时运行；正常游戏不经过这里。2026-09-26 从 game.gd 拆出。

const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var winshot := false
var touchtest_p0 := Vector2.ZERO
var bal_done := false
var shop_visits := 0
var lv_marks := {}
var bosstest := false
var choice_wait := 0
var choice_shot := false
var trace_last := -1


func _init(game: Game) -> void:
	g = game


## 平衡机器人选卡（docs/27 §6）：像一个「懂玩」的玩家——优先干员深度 / 技能卡，早期见招募就招，
## 被动按 data/balance.json bot.growth_weights 加权，填充卡只在没得选时拿；--botrandom 退回纯随机
func bot_pick() -> int:
	if g.choices.is_empty():
		return 0
	if g.bot != null:
		var bp: int = g.bot.pick(g.choices)
		if bp >= 0:
			return bp
	if OS.get_cmdline_user_args().has("--botrandom"):
		return g.rng.randi() % g.choices.size()
	var W: Dictionary = Bal.sec("bot/weights")
	var GW: Dictionary = Bal.sec("bot/growth_weights")
	var early_recruit: int = Bal.vi("bot/prefer_recruit_before", 8)
	var ws: Array = []
	var total := 0.0
	for c in g.choices:
		var w: float = float(W.get(c.get("kind", ""), 1.0))
		if c.kind == "recruit" and g.level < early_recruit:
			w = 100.0
		elif c.kind == "growth":
			w *= float(GW.get(c.get("id", ""), 1.0))
		elif c.kind == "prog" and int(c.get("elite", 0)) > 0:
			w *= 1.5   # 精英化卡：解锁技能与天赋，价值最高
		ws.append(w)
		total += w
	var r := g.rng.randf() * total
	for i in ws.size():
		r -= ws[i]
		if r <= 0.0:
			return i
	return ws.size() - 1


## 仅用于开发自测：快速模拟一整局，自动选择升级，打印状态后退出
func step() -> void:
	g.at_frames += 1
	if g.state == g.S.OPENING and OS.get_cmdline_user_args().has("--openshot"):
		if g.at_frames % 3 == 0 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_open_%03d.png" % g.at_frames)
		if g.at_frames > 240:
			g.get_tree().quit()
		return
	if g.state == g.S.INTRO:
		if g.intro_t > 0.5 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_intro_%d.png" % g.intro_page)
			if g.intro_page >= g.INTRO_PAGES.size() - 1:
				g.get_tree().quit()
				return
			g.intro_page += 1
			g.intro_t = 0.0
		return
	if OS.get_cmdline_user_args().has("--gallery"):
		g.demo_sys.gallery_step()
		return
	if g.state == g.S.SHOP:
		for i in g.shop_items.size():
			if not g.shop_items[i].sold and g.ingots >= g.shop_items[i].price:
				g.shop_sys.buy(i)
				break
		if shop_visits == 1 and DisplayServer.get_name() != "headless" and not g.balance:
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_shop.png")
		shop_visits += 1
		if shop_visits % 3 == 0:
			g.shop_sys.close()
	for m in [120, 300, 480]:
		if g.t >= m and not lv_marks.has(m):
			lv_marks[m] = g.level
	if OS.get_cmdline_user_args().has("--fxtest"):
		g.ppos = Vector2(1500, 900)
		if g.at_frames == 90:
			g.hp = g.max_hp * 0.2
			g.combat.hurt(g.max_hp * 0.1)
		if g.at_frames == 96 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_hurt.png")
		if g.at_frames == 175:
			g.zone_c = g.ppos + Vector2(560, 60)
			g.zone_r = 480.0
			g.zone_state = 3
			g.zone_t = -999.0
		if g.at_frames == 188 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_zone.png")
		if g.at_frames == 130:
			g.state = g.S.STATS
		if g.at_frames == 132:
			for c in g.stats_cells:
				if c[1] == "relic":
					Input.warp_mouse(c[0].get_center())
					break
		if g.at_frames == 134 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_stats.png")
			g.state = g.S.PLAY
		if g.at_frames == 20:
			g.weapons = {"drone": 4}
			for rid in ["118", "199", "100"]:
				g.relics.append(rid)
				g.progression.apply_relic(rid)
			g.shield = 2
			g.ch.elite = 2
			g.ch.fill_sp()
			for k in ["wisadel", "eyjafjalla", "suzuran"]:
				var op = g.squad.add(k)
				if op != null:
					op.advance()
					op.advance()
			g.t = 149.0
			g.next_horde = g.t + 60.0
			g.merchant = {"pos": g.ppos + Vector2(900, -300), "life": 60.0, "near": false}
		if g.at_frames == 150 and not g.tray_cells.is_empty():
			Input.warp_mouse(g.tray_cells[0][0].get_center())
		if g.at_frames == 60:
			g.pickups.drop(g.ppos + Vector2(120, 40), "magnet", 1.0)
			g.pickups.drop(g.ppos + Vector2(-120, 40), "heal", 1.0)
		for f in [64, 72, 100, 125, 160, 200]:
			if g.at_frames == f and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_fx_%d.png" % f)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bosstest="):
			# Boss 招式测试：在水月旁刷出指定 Boss，定时截图
			bosstest = true
			if g.at_frames == 20:
				g.ppos = Vector2(1500, 900)
				g.max_hp = 900.0
				g.hp = 900.0
				g.t = 150.0
				for bt in a.substr(11).split(","):
					var b := g.spawner.spawn_enemy(bt.trim_suffix("2"), g.ppos + Vector2(230, -40))
					b.age = 5.0
					if bt.ends_with("2"):
						b.phase = 2
						b.range = 400.0
					g.bosses.append(b)
					g.boss = b
				if g.bosses.size() == 2:
					g.bosses[0].partner = g.bosses[1]
					g.bosses[1].partner = g.bosses[0]
			if g.at_frames > 20 and g.at_frames % 30 == 0 and g.at_frames <= 600 and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_boss_%s_%03d.png" % [a.substr(11).replace(",", "_"), g.at_frames])
	if OS.get_cmdline_user_args().has("--fastlevel") and g.state == g.S.PLAY and (g.at_frames == 30 or g.at_frames == 400):
		g.level = 9 if g.at_frames == 30 else 19
		g.pickups.gain_xp(g.xp_need + 0.1)
	if g.state == g.S.SHOW:
		if g.balance:
			g.show_t = 2.0
			g.show_screen.close()
			return
		if g.show_t > 1.4 and not g.show_shot and DisplayServer.get_name() != "headless":
			g.show_shot = true
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_show_%d.png" % g.ch.elite)
		if g.show_t > 1.6:
			g.show_screen.close()
		return
	if g.at_frames == 30 and g.state == g.S.PLAY:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--grant="):
				for rid in a.substr(8).split(","):
					g.progression.gain_relic(rid)
	# --shots 在平衡模式下也生效（平衡分支会提前 return）：特效连拍用 --balance --nodeath 跳过精英化演出
	if g.balance and g.shot_at.has(g.at_frames) and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_%d.png" % g.at_frames)
	# 机器人的手动技能（契约 v2.3：只有主控有手动技能）：就绪且干员自己想放时替玩家按下。
	# 时机由干员的 bot_wants_manual 决定：缺省保命型（主控生命 < bot/manual_hp），乌尔比安 S3 就绪即放
	if g.state == g.S.PLAY:
		for o in g.squad.ops:
			var mi: int = o.manual_index()
			if o.manual_ready(mi) and o.bot_wants_manual(mi):
				o.cast_manual(mi)
				break
	# --relics=id,id… 或 --relics=all（仅 --balance）：开局第 20 帧直接获得这些藏品，冒烟测试藏品效果（docs/35 / docs/36）
	# --maxprog（仅 --balance）：同一帧把编队里每名干员推到成长线末端（精二 + 全部节点），让所有技能与成长钩子都跑一遍
	if g.balance and g.at_frames == 20:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--relics="):
				var want: String = a.substr(9)
				var ids: Array = g.RL.keys() if want == "all" else Array(want.split(","))
				for rid in ids:
					if g.RL.has(rid):
						g.progression.gain_relic(rid)
		if OS.get_cmdline_user_args().has("--maxprog"):
			for o in g.squad.ops:
				var guard := 0
				while not o.next_node().is_empty() and guard < 12:
					o.advance("")
					guard += 1
	if g.balance and OS.get_cmdline_user_args().has("--sptest") and g.at_frames % 45 == 0:
		for o in g.squad.ops:
			o.fill_sp()
	if g.balance:
		if g.trace_every > 0.0 and g.state == g.S.PLAY and int(g.t / g.trace_every) != trace_last:
			trace_last = int(g.t / g.trace_every)
			var hsum := 0.0
			for e in g.enemies:
				hsum += e.pos.x * 0.37 + e.pos.y * 0.11 + e.hp * 0.01
			print("TRACE t=%.2f lv=%d k=%d hp=%.2f n=%d rng=%d pos=%.2f,%.2f h=%.3f" % [g.t, g.level, g.kills, g.hp, g.enemies.size(), g.rng.state, g.ppos.x, g.ppos.y, hsum])
		if g.bot != null and g.state == g.S.PLAY:
			g.bot.tick(0.066)
		if false:
			print("dbg t=%d state=%d lv=%d hp=%d en=%d" % [g.t, g.state, g.level, g.hp, g.enemies.size()])
		if g.state == g.S.CHOICE:
			var pi := bot_pick()
			for a in OS.get_cmdline_user_args():
				# --evpick=1 或 --evpick=madness:0,knight_stay:0,default:1
				if a.begins_with("--evpick=") and g.choice_kind == "event":
					var spec: String = a.substr(9)
					if spec.is_valid_int():
						pi = mini(int(spec), g.choices.size() - 1)
					else:
						var evid: String = String(g.choices[0].id).split(":")[0]
						for part in spec.split(","):
							var kv: PackedStringArray = part.split(":")
							if kv.size() == 2 and (kv[0] == evid or kv[0] == "default") and (kv[0] != "default" or not spec.contains(evid + ":")):
								pi = mini(int(kv[1]), g.choices.size() - 1)
			g.progression.pick(pi)
		# 10:00 最终 Boss 登场后给 3 分钟打完（之前 620 秒截断只留 20 秒，胜负基本看不出来）
		if (g.state == g.S.DEAD or g.state == g.S.WIN or g.t > g.bal_maxt) and not bal_done:
			bal_done = true
			print("BALANCE ", JSON.stringify({"win": g.state == g.S.WIN, "t": int(g.t), "lv": g.level, "marks": lv_marks, "lv_times": g.lv_times, "ops": g.squad.ops.map(func(o): return {"id": o.id, "elite": o.elite, "prog": o.prog}), "prog_offer": g.dbg_offer, "prog_pick": g.dbg_pick, "relic_offer": g.dbg_relic_offer, "relic_take": g.dbg_relic_take, "relic_out": g.relic_out, "prof": g.prof, "kills": g.kills,
				"elites": g.elites_killed, "relics": g.relics.size(), "ingots": g.ingots, "maxhp": g.max_hp, "bosses": g.bosses.map(func(b): return "%s:%s" % [b.type, "dead" if b.dead else "%d%%" % int(100 * b.hp / b.maxhp)]), "allies": g.squad.size() - 1, "squad": g.squad.ids(), "elite_stage": g.ch.elite,
				"boss_hp": (g.boss.hp / g.boss.maxhp) if g.boss != null else -1.0, "dmg": g.dmg_log, "out": g.dmg_out, "out_type": g.dmg_type_out, "out_tag": g.dmg_tag_out, "ending": g.ending, "lamp": int(g.lamp), "rej": g.doctor.rej(), "heal": g.heal_log, "drone": g.weapons.get("drone", 0), "floor_hits": g.floor_hits, "floor_times": g.floor_times, "hordes": g.horde_log.map(func(h): return {"t": h.t, "n": h.n, "hp": int(h.hp), "t80": h.t80, "hp0": int(h.hp0), "minhp": int(h.minhp), "comp": h.comp}), "final_out": g.dmg_out, "ctrl": g.combat.ctrl_report(), "bot": g.bot.report() if g.bot != null else {}}))
			g.get_tree().quit()
		return
	if not (OS.get_cmdline_user_args().has("--fxtest") and g.at_frames >= 90 and g.at_frames < 100):
		g.hp = g.max_hp
	if g.lvup_show > 1.05 and g.lvup_show < 1.12 and g.level == 3 and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_lvup.png")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--eventtest=") and g.at_frames == 30:
			for ev in g.endg.events:
				if ev.id == a.substr(12):
					g.endg._spawn_box(ev)
					g.endg.done.append(ev.id)
					for e in g.enemies:
						if e.chest and e.get("event", "") != "":
							e.pos = g.ppos + Vector2(120, 0)
	if OS.get_cmdline_user_args().has("--touchtest") and g.state == g.S.PLAY:
		# 模拟：第 60 帧按下左半屏，拖到右上，第 120 帧松开；第 90 帧截图
		if g.at_frames == 60:
			var tp := InputEventScreenTouch.new()
			tp.index = 0
			tp.pressed = true
			tp.position = Vector2(200, 500)
			Input.parse_input_event(tp)
			touchtest_p0 = g.ppos
		elif g.at_frames > 60 and g.at_frames < 120:
			var td := InputEventScreenDrag.new()
			td.index = 0
			td.position = Vector2(200, 500) + Vector2(1.2, -0.7) * float(g.at_frames - 60)
			Input.parse_input_event(td)
		elif g.at_frames == 120:
			var tr := InputEventScreenTouch.new()
			tr.index = 0
			tr.pressed = false
			tr.position = Vector2(272, 458)
			Input.parse_input_event(tr)
			print("TOUCHTEST moved=%s" % str((g.ppos - touchtest_p0).round()))
		if g.at_frames == 90 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_touch.png")
		if g.at_frames == 130:
			g.get_tree().quit()
	if OS.get_cmdline_user_args().has("--gemshot"):
		if g.at_frames == 60:
			for k in 14:
				g.pickups.drop(g.ppos + Vector2.from_angle(TAU * k / 14.0) * 150.0, "xp", 8.0 if k % 4 == 0 else 1.0)
			g.pickups.drop(g.ppos + Vector2(60, -40), "xp", 1.0)
		if g.at_frames in [72, 100] and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_gem_%d.png" % g.at_frames)
			if g.at_frames == 100:
				g.get_tree().quit()
	if OS.get_cmdline_user_args().has("--relicshot"):
		if g.at_frames == 30:
			g.pending_chests = 1
			g.ingots = 40
		if g.at_frames == 400:
			g.merchant = {"pos": g.ppos, "life": 60.0, "near": false}
			g.shop_sys.open()
		if g.at_frames == 440 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_shop.png")
			g.get_tree().quit()
	if g.state == g.S.CHOICE:
		choice_wait += 1
		if choice_wait == 40 and not choice_shot and DisplayServer.get_name() != "headless" and (g.choice_kind == "relic" or not OS.get_cmdline_user_args().has("--relicshot")):
			choice_shot = true
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_choice.png")
		if choice_wait > 45:
			choice_wait = 0
			# 机器人像真人一样偏好干员深度 / 精英化卡（70%），其余均匀随机
			var deep: Array = []
			for ci in g.choices.size():
				if g.choices[ci].kind == "prog":
					deep.append(ci)
			if not deep.is_empty() and g.rng.randf() < 0.7:
				g.progression.pick(deep[g.rng.randi() % deep.size()])
			else:
				g.progression.pick(g.rng.randi() % g.choices.size())
	if g.at_frames % 1200 == 0:
		print("t=%d lv=%d E%d hp=%d enemies=%d kills=%d lamp=%d growth=%s relics=%s squad=%s fps=%d" % [g.t, g.level, g.ch.elite, g.hp, g.enemies.size(), g.kills, g.lamp, g.growth, g.relics, g.squad.ops.map(func(o): return "%s%d/%d" % [o.id, o.elite, o.prog]), Engine.get_frames_per_second()])
	for bb in g.bosses:
		if not bb.dead and not bb.invuln and not bosstest:
			bb.hp -= 4.0 if bosstest else 40.0
			if bb.hp <= 0.0:
				g.combat.kill(bb)
	for a in OS.get_cmdline_user_args():
		# --winshot=deep：第 60 帧直接进入胜利结算并截图
		if a.begins_with("--winshot=") and g.at_frames == 60:
			winshot = true
			g.ending = a.substr(10)
			g.endg.cur = g.ending
			g.ending_new = true
			g.state = g.S.WIN
		if a.begins_with("--winshot=") and g.at_frames == 130 and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_win.png")
			g.get_tree().quit()
	# --sptest：每 2 秒把全队技力充满（截图 / 观察技能特效用）
	if OS.get_cmdline_user_args().has("--sptest") and g.at_frames % 120 == 0:
		for o in g.squad.ops:
			o.fill_sp()
	if g.shot_at.has(g.at_frames) and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_%d.png" % g.at_frames)
	if bosstest and g.at_frames > 610:
		g.get_tree().quit()
	if (g.state == g.S.WIN and not winshot) or g.at_frames > 14000:
		print("AUTOTEST END state=%d t=%d" % [g.state, g.t])
		g.get_tree().quit()


## 平衡测试用的简单 AI：躲开贴身的敌人、保持在挥伞距离、捡掉落物
func bot_move() -> Vector2:
	var push := Vector2.ZERO
	var nearest_d := 99999.0
	var nearest_p := g.ppos
	for j in g.enemies_sys.query(g.ppos, 220.0):
		var e: Dictionary = g.enemies[j]
		if e.dead:
			continue
		var d: Vector2 = g.ppos - e.pos
		var l := d.length()
		if l < nearest_d:
			nearest_d = l
			nearest_p = e.pos
		var danger: float = 48.0 + e.r
		if l < danger and l > 0.01:
			push += d / l * (danger - l) / danger * (3.0 if (e.elite or e.boss) else 1.0)
		# 远程怪：像真人一样不站在它射程里干等（保持在它射程外沿）
		if e.ai == "ranged" and not e.boss and l > 0.01 and l < e.range + 20.0:
			push += d / l * 0.6
	# 低血量：远离敌群重心，先活下来再打
	if g.hp < g.max_hp * 0.5:
		var cen := Vector2.ZERO
		var cn := 0
		for j in g.enemies_sys.query(g.ppos, 320.0):
			var e2: Dictionary = g.enemies[j]
			if not e2.dead:
				cen += e2.pos
				cn += 1
		if cn > 0:
			var away: Vector2 = g.ppos - cen / cn
			if away.length() > 1.0:
				push += away.normalized() * (1.6 if g.hp < g.max_hp * 0.3 else 0.9)
	# 躲开招式预警、溟痕与敌方弹幕（让自测更接近真人）
	for w in g.warns:
		if w.done:
			continue
		var dv: Vector2 = g.ppos - w.pos
		if w.shape == "circle" and dv.length() < w.r + 30.0:
			push += (dv.normalized() if dv.length() > 1.0 else Vector2.RIGHT) * 1.4
		elif w.shape == "line":
			var b2: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			var cp: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos, w.pos, b2)
			if cp.distance_to(g.ppos) < w.wid + 40.0:
				var away: Vector2 = g.ppos - cp
				push += (away.normalized() if away.length() > 1.0 else Vector2.from_angle(w.ang).orthogonal()) * 1.4
		elif w.shape == "cone" and dv.length() < w.r + 30.0:
			push += dv.normalized() * 1.4
	for m in g.mires:
		var dm: Vector2 = g.ppos - m.pos
		if dm.length() < m.r + 24.0:
			push += dm.normalized() * 2.0
	for bl in g.ebullets:
		if bl.life <= 0.0 or bl.pos.distance_to(g.ppos) > 170.0:
			continue
		var toward: Vector2 = (g.ppos - bl.pos)
		if bl.vel.dot(toward) <= 0.0:
			continue
		# 只躲会打到自己的子弹：算它的直线路径离自己多近，往远离路径的一侧闪
		var vdir: Vector2 = bl.vel.normalized()
		var along: float = toward.dot(vdir)
		var side: Vector2 = toward - vdir * along
		var miss: float = side.length()
		if miss < bl.r + 40.0:
			var sdir: Vector2 = side.normalized() if miss > 1.0 else vdir.orthogonal()
			var urgency: float = clampf(1.0 - along / 170.0, 0.3, 1.0)
			push += sdir * 1.6 * urgency
	var pull := Vector2.ZERO
	var best := 260.0
	for g_item in g.gems:
		var gd: float = g_item.pos.distance_to(g.ppos)
		var w: float = gd * (0.4 if (g_item.kind == "oil" and g.lamp < 60.0) or g_item.kind == "chest" else 1.0)
		if w < best:
			best = w
			pull = (g_item.pos - g.ppos).normalized() * 0.7
	if g.hp > g.max_hp * 0.5:
		for bb in g.bosses:
			if not bb.dead and not bb.invuln and bb.pos.distance_to(g.ppos) > 90.0:
				pull = (bb.pos - g.ppos).normalized() * 0.8
				break
	if not g.merchant.is_empty() and g.merchant.pos.distance_to(g.ppos) < 500.0 and not g.merchant.near:
		pull = (g.merchant.pos - g.ppos).normalized() * 0.9
	for e in g.enemies:
		if e.chest and not e.dead and e.pos.distance_to(g.ppos) < 400.0:
			pull = (e.pos - g.ppos).normalized() * 0.8
			break
	if pull == Vector2.ZERO and nearest_d > 100.0 and nearest_d < 99999.0 and g.hp > g.max_hp * 0.4:
		pull = (nearest_p - g.ppos).normalized() * 0.5
	var mv := push * 2.2 + pull
	# 溟痕：像真人玩家一样绕开（在里面时全力往外走）
	for m in g.mires:
		var md: Vector2 = g.ppos - m.pos
		var ml := md.length()
		if ml < m.r + 50.0 and ml > 0.01:
			mv += md / ml * (2.5 if ml < m.r else 1.2)
	# 缩圈：靠近圈边时往圈内走
	if g.zone_state != 0:
		var zc: float = g.ppos.distance_to(g.zone_c)
		var target_c: Vector2 = g.zone_next_c if g.zone_state == 1 else g.zone_c
		var target_r: float = g.zone_next_r if g.zone_state == 1 else g.zone_r
		if g.ppos.distance_to(target_c) > target_r - 160.0 or zc > g.zone_r - 160.0:
			mv += (target_c - g.ppos).normalized() * 3.0
	if mv.length() < 0.15:
		mv = Vector2.from_angle(g.t * 0.3) * 0.3
	return mv
