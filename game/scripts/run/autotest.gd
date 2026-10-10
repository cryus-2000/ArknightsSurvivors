extends RefCounted
## 自动测试 / 平衡机器人（docs/29、docs/36）：--autotest / --balance 的逐帧驱动、截图开关、机器人走位与选卡。
## 只在带测试参数启动时运行；正常游戏不经过这里。2026-09-26 从 game.gd 拆出。

const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var winshot := false
var touchtest_p0 := Vector2.ZERO
var bal_done := false
var zone_out_since := -1.0   # 普通机器人：本次出圈的开始时间（-1 = 在圈内）
var want_dash := false       # 普通机器人：这一帧要冲刺（出圈回圈用；game.gd 在记下移动方向后执行）
var shop_visits := 0
var lv_marks := {}
var bosstest := false
var bossintro_kill_at := -1   # --bossintro：登场演完后击杀 Boss 的帧号（之后 90 帧退出）
var choice_wait := 0
var choice_shot := false
var trace_last := -1
# --perf（仅测试，开窗口跑 --balance 时用）：按游戏时间分段记真实帧时间、渲染 CPU / GPU 时间与同屏敌人数，
# 结束时打印一行 PERF {...}。注意 --balance 每帧推进 0.066 秒（正常游戏约 0.017 秒），每帧的模拟量偏大，帧时间是偏保守的上界
var perf_on := false
var perf_last := 0
var perf := {}
var perf_prev := {}            # 上一帧的 g.prof 累计（配合 --prof：逐帧分段）
var perf_slow: Array = []      # 慢帧（≥ 33 毫秒）明细，结束时取最慢 25 帧
var perf_kills := 0


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
	if Cfg.dev_args().has("--botrandom"):
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
	if g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--perf"):
		_perf_sample()
	if g.state == g.S.OPENING and Cfg.dev_args().has("--openshot"):
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
	if Cfg.dev_args().has("--gallery"):
		g.demo_sys.gallery_step()
		return
	if g.state == g.S.SHOP:
		var lane_i: int = g.bot.shop_pick() if g.bot != null else -1
		if lane_i >= 0:
			g.shop_sys.buy(lane_i)
		for i in (g.shop_items.size() if lane_i < 0 else 0):
			if g.shop_sys.can_buy(g.shop_items[i]):
				g.shop_sys.buy(i)
				break
		if shop_visits == 1 and DisplayServer.get_name() != "headless" and g.mode != g.Mode.BALANCE:
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_shop.png")
		shop_visits += 1
		if shop_visits % 3 == 0:
			g.shop_sys.close()
	for m in [120, 300, 480]:
		if g.t >= m and not lv_marks.has(m):
			lv_marks[m] = g.level
	if Cfg.dev_args().has("--fxtest"):
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
	for a in Cfg.dev_args():
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
						g.bai.setup_preview_phase2(b)   # 与演练 / 图鉴使用同一阵营、形态和技能初始化。
					# 只有 role == boss 的进 bosses（HUD 大血条、Boss 在场判定）；参数里列的小怪（碎片、之泪等）照常刷出来当靶子
					if not b.boss:
						continue
					g.bosses.append(b)
					g.boss = b
					# 结局 Boss 也设「最终 Boss」标记，走终局音乐 / 终局藏品倍率（docs/38 B0 第 9 项）
					if g.final_boss == null and g.spawner.is_final_boss_type(b.type):
						g.final_boss = b
				if g.bosses.size() == 2:
					g.bosses[0].partner = g.bosses[1]
					g.bosses[1].partner = g.bosses[0]
			if g.at_frames > 20 and g.at_frames % 30 == 0 and g.at_frames <= 600 and DisplayServer.get_name() != "headless":
				g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_boss_%s_%03d.png" % [a.substr(11).replace(",", "_"), g.at_frames])
		if a.begins_with("--bossintro="):
			# Boss 登场演出测试（docs/36 §5）：第 20 帧在主控旁刷出指定 Boss（逗号分隔 = 同组登场）并走一遍登场，
			# 登场进行到 0.35 / 0.6 / 0.85 / 1.1 秒各截一张；演完后把 Boss 击杀，击破一拍 0.12 / 0.35 秒再各截一张，然后退出
			bosstest = true   # 别让自测每帧扣 Boss 血
			var tag: String = a.substr(12).replace(",", "_")
			if g.at_frames == 20:
				g.ppos = Vector2(1500, 900)
				g.t = 150.0
				var grp: Array = []
				for bt in a.substr(12).split(","):
					var b := g.spawner.spawn_enemy(bt, g.ppos + Vector2(230 + 90 * grp.size(), -40))
					b.age = 5.0
					if not b.boss:
						continue
					g.bosses.append(b)
					g.boss = b
					grp.append(b)
				if grp.size() == 2:
					grp[0].partner = grp[1]
					grp[1].partner = grp[0]
				g.boss_intro.on_spawn(grp, true)
				g.boss_intro._test_shots = [0.35, 0.6, 0.85, 1.1]
			if g.at_frames > 20 and DisplayServer.get_name() != "headless":
				var bi = g.boss_intro
				if bi.active() and not bi._test_shots.is_empty() and bi.cur.t >= float(bi._test_shots[0]):
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossintro_%s_%03d.png" % [tag, int(bi.cur.t * 100.0)])
					bi._test_shots.pop_front()
				if not bi.active() and bi.outro.is_empty() and g.at_frames > 40 and bossintro_kill_at < 0 and g.bosses.any(func(b): return not b.dead):
					for b in g.bosses:
						if not b.dead:
							g.combat.kill(b)
					bossintro_kill_at = g.at_frames
					bi._test_shots = [0.12, 0.35]
				if not bi.outro.is_empty() and not bi._test_shots.is_empty() and bi.outro.t >= float(bi._test_shots[0]):
					g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_bossout_%s_%03d.png" % [tag, int(bi.outro.t * 100.0)])
					bi._test_shots.pop_front()
				if bossintro_kill_at >= 0 and g.at_frames > bossintro_kill_at + 90:
					g.get_tree().quit()
	if Cfg.dev_args().has("--fastlevel") and g.state == g.S.PLAY and (g.at_frames == 30 or g.at_frames == 400):
		g.level = 9 if g.at_frames == 30 else 19
		g.pickups.gain_xp(g.xp_need + 0.1)
	if g.state == g.S.SHOW:
		if g.mode == g.Mode.BALANCE:
			g.show_t = 2.0
			g.show_screen.close()
			return
		if g.show_t > 1.4 and not g.show_shot and DisplayServer.get_name() != "headless":
			g.show_shot = true
			# 按演出的干员和阶段命名（编队里别的干员精英化时，主控的 elite 对不上）
			var sc: Dictionary = g.show_screen.show_cur
			var tag: String = "%s_%d" % [sc.op.id, int(sc.get("elite", 0))] if sc.has("op") and sc.op != null else str(g.ch.elite)
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_show_%s.png" % tag)
		if g.show_t > 1.6:
			g.show_screen.close()
		return
	if g.at_frames == 30 and g.state == g.S.PLAY:
		for a in Cfg.dev_args():
			if a.begins_with("--grant="):
				for rid in a.substr(8).split(","):
					g.progression.gain_relic(rid)
	# --shots 在平衡模式下也生效（平衡分支会提前 return）：特效连拍用 --balance --nodeath 跳过精英化演出
	if g.mode == g.Mode.BALANCE and g.shot_at.has(g.at_frames) and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_%d.png" % g.at_frames)
	# 机器人的手动技能（契约 v2.3：只有主控有手动技能）：就绪且干员自己想放时替玩家按下。
	# 时机由干员的 bot_wants_manual 决定：缺省保命型（主控生命 < bot/manual_hp），乌尔比安 S3 就绪即放
	if g.state == g.S.PLAY:
		for o in g.squad.ops:
			var mi: int = o.manual_index()
			if o.manual_ready(mi) and o.bot_wants_manual(mi):
				o.cast_manual(mi)
				break
	# --evignore=<事件 id,…|all>[@秒]：机器人打不开这些海嗣祭坛（生命锁住），到「秒」之后恢复 22 点、可以打开；
	# 用来复现「祭坛晾着不开」（EA 验收 P0-1 / P1-2，原为测试与验收的 probe.gd --pk_ignore / --pk_ign_t）
	for a in Cfg.dev_args():
		if a.begins_with("--evignore="):
			var spec: PackedStringArray = a.substr(11).split("@")
			var ids: PackedStringArray = spec[0].split(",")
			var until: float = float(spec[1]) if spec.size() > 1 else 1.0e9
			for e in g.enemies:
				if e.chest and not e.dead and e.get("event", "") != "" and (ids.has(e.event) or spec[0] == "all"):
					if g.t < until:
						e.hp = 1.0e9
						e.maxhp = 1.0e9
					elif e.hp > 22.0:
						e.hp = 1.0
						e.maxhp = 22.0
	# --relics=id,id… 或 --relics=all（仅 --balance）：开局第 20 帧直接获得这些藏品，冒烟测试藏品效果（docs/35 / docs/36）
	# --maxprog（仅 --balance）：同一帧把编队里每名干员推到成长线末端（精二 + 全部节点），让所有技能与成长钩子都跑一遍
	if g.mode == g.Mode.BALANCE and g.at_frames == 20:
		for a in Cfg.dev_args():
			if a.begins_with("--relics="):
				var want: String = a.substr(9)
				var ids: Array = g.RL.keys() if want == "all" else Array(want.split(","))
				for rid in ids:
					if g.RL.has(rid):
						g.progression.gain_relic(rid)
		if Cfg.dev_args().has("--maxprog"):
			for o in g.squad.ops:
				var guard := 0
				while not o.next_node().is_empty() and guard < 12:
					o.advance("")
					guard += 1
	if g.mode == g.Mode.BALANCE and Cfg.dev_args().has("--sptest") and g.at_frames % 45 == 0:
		for o in g.squad.ops:
			o.fill_sp()
	if g.mode == g.Mode.BALANCE:
		if g.trace_every > 0.0 and g.state == g.S.PLAY and int(g.t / g.trace_every) != trace_last:
			trace_last = int(g.t / g.trace_every)
			var hsum := 0.0
			for e in g.enemies:
				hsum += e.pos.x * 0.37 + e.pos.y * 0.11 + e.hp * 0.01
			print("TRACE t=%.2f lv=%d k=%d hp=%.2f n=%d rng=%d pos=%.2f,%.2f h=%.3f" % [g.t, g.level, g.kills, g.hp, g.enemies.size(), g.rng.state, g.ppos.x, g.ppos.y, hsum])
		if g.bot != null and g.state == g.S.PLAY:
			g.telemetry.tick(0.066)   # 整局指标（原 bot.tick，挪到 run/telemetry.gd）
		if false:
			print("dbg t=%d state=%d lv=%d hp=%d en=%d" % [g.t, g.state, g.level, g.hp, g.enemies.size()])
		if g.state == g.S.CHOICE:
			var pi := bot_pick()
			for a in Cfg.dev_args():
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
			if perf_on:
				print("PERF ", JSON.stringify(_perf_summary()))
			print("BALANCE ", JSON.stringify(g.telemetry.record(lv_marks)))   # 整局记录的格式在 run/telemetry.gd（与玩家本地记录同一份）
			g.get_tree().quit()
		return
	if not (Cfg.dev_args().has("--fxtest") and g.at_frames >= 90 and g.at_frames < 100):
		g.hp = g.max_hp
	if g.lvup_show > 1.05 and g.lvup_show < 1.12 and g.level == 3 and DisplayServer.get_name() != "headless":
		g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_lvup.png")
	for a in Cfg.dev_args():
		if a.begins_with("--eventtest=") and g.at_frames == 30:
			for ev in g.endg.events:
				if ev.id == a.substr(12):
					g.endg._spawn_box(ev)
					g.endg.done.append(ev.id)
					for e in g.enemies:
						if e.chest and e.get("event", "") != "":
							e.pos = g.ppos + Vector2(120, 0)
	if Cfg.dev_args().has("--touchtest") and g.state == g.S.PLAY:
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
	if Cfg.dev_args().has("--gemshot"):
		if g.at_frames == 60:
			for k in 14:
				g.pickups.drop(g.ppos + Vector2.from_angle(TAU * k / 14.0) * 150.0, "xp", 8.0 if k % 4 == 0 else 1.0)
			g.pickups.drop(g.ppos + Vector2(60, -40), "xp", 1.0)
		if g.at_frames in [72, 100] and DisplayServer.get_name() != "headless":
			g.get_viewport().get_texture().get_image().save_png(g.shot_dir + "/shot_gem_%d.png" % g.at_frames)
			if g.at_frames == 100:
				g.get_tree().quit()
	if Cfg.dev_args().has("--relicshot"):
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
		if choice_wait == 40 and not choice_shot and DisplayServer.get_name() != "headless" and (g.choice_kind == "relic" or not Cfg.dev_args().has("--relicshot")):
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
		print("t=%d lv=%d E%d hp=%d enemies=%d mires=%d kills=%d lamp=%d growth=%s relics=%s squad=%s fps=%d" % [g.t, g.level, g.ch.elite, g.hp, g.enemies.size(), g.mires.size(), g.kills, g.lamp, g.growth, g.relics, g.squad.ops.map(func(o): return "%s%d/%d" % [o.id, o.elite, o.prog]), Engine.get_frames_per_second()])
	for bb in g.bosses:
		if not bb.dead and not bb.invuln and not bosstest:
			bb.hp -= 4.0 if bosstest else 40.0
			if bb.hp <= 0.0:
				g.combat.kill(bb)
	for a in Cfg.dev_args():
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
	if Cfg.dev_args().has("--sptest") and g.at_frames % 120 == 0:
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
		# 海嗣祭坛只有走近才打开、又刷在 520–650 外：像真人看方位指示那样走过去（同 bot.gd 高手的 1600）
		var reach: float = 1600.0 if e.get("event", "") != "" else 400.0
		if e.chest and not e.dead and e.pos.distance_to(g.ppos) < reach:
			pull = (e.pos - g.ppos).normalized() * (1.0 if e.get("event", "") != "" else 0.8)
			break
	# 引航灯标：没点燃、血量还行就过去站着（光圈半径 70，站到离中心 40 以内就不再拉，免得来回抖）
	for b in g.beacons:
		if not b.lit and g.hp > g.max_hp * 0.45 and b.pos.distance_to(g.ppos) < 700.0:
			pull = (b.pos - g.ppos).normalized() * 0.9 if b.pos.distance_to(g.ppos) > 40.0 else Vector2.ZERO
			break
	if pull == Vector2.ZERO and nearest_d > 100.0 and nearest_d < 99999.0 and g.hp > g.max_hp * 0.4:
		pull = (nearest_p - g.ppos).normalized() * 0.5
	var mv := push * 2.2 + pull
	# 缩圈：靠近圈边时往圈内走
	if g.zone_state != 0:
		var zc: float = g.ppos.distance_to(g.zone_c)
		var target_c: Vector2 = g.zone_next_c if g.zone_state == 1 else g.zone_c
		var target_r: float = g.zone_next_r if g.zone_state == 1 else g.zone_r
		var od: float = zc - g.zone_r
		if od > -30.0:
			# 已贴圈边 / 出圈：真人会先回圈。敌群的「往外推」只留侧向分量（侧身绕过去；溟痕在后面单独加，照样绕开），经验 / 商人等拉力朝外的不跟，
			# 回圈拉力随出圈距离加大；出圈超过 0.5 秒且冲刺好了就朝圈心冲（2026-09-27：v11-ab 黑潮死亡多是普通机器人被怪群推在圈外，
			# 实测圈外 165–196 像素、怪群推力 −2.6…−4.8 压过固定的 3.0 回圈拉力）
			var toc: Vector2 = (g.zone_c - g.ppos).normalized()
			var rad: float = mv.dot(toc)
			if rad < 0.0:
				mv -= toc * rad
			mv += toc * (3.0 + clampf(od / 50.0, 0.0, 4.0))
			if od > 0.0:
				if zone_out_since < 0.0:
					zone_out_since = g.t
				elif g.t - zone_out_since > 0.5 and g.dash_cd <= 0.0:
					want_dash = true
			else:
				zone_out_since = -1.0
		else:
			zone_out_since = -1.0
			if g.ppos.distance_to(target_c) > target_r - 160.0 or zc > g.zone_r - 160.0:
				mv += (target_c - g.ppos).normalized() * 3.0
	# 溟痕：像真人玩家一样绕开（在里面时全力往外走）；放在回圈之后，回圈时也照样绕开（2026-09-27：放在前面时外推被回圈一起削掉，机器人直穿圈边溟痕，溟痕 / 侵蚀死亡变多）
	for m in g.mires:
		var md: Vector2 = g.ppos - m.pos
		var ml := md.length()
		if ml < m.r + 50.0 and ml > 0.01:
			mv += md / ml * (2.5 if ml < m.r else 1.2)
	if mv.length() < 0.15:
		mv = Vector2.from_angle(g.t * 0.3) * 0.3
	return mv


func _perf_sample() -> void:
	var rid: RID = g.get_viewport().get_viewport_rid()
	if not perf_on:
		perf_on = true
		RenderingServer.viewport_set_measure_render_time(rid, true)
	var now := Time.get_ticks_usec()
	if perf_last > 0 and g.state == g.S.PLAY:
		var w := "0-8" if g.t < 480.0 else ("8-10" if g.t < 600.0 else "10+")
		if not perf.has(w):
			perf[w] = {"ft": PackedFloat32Array(), "rcpu": PackedFloat32Array(), "gpu": PackedFloat32Array(), "en": PackedInt32Array(), "stage": {}, "slow_stage": {}, "slow_n": 0,
				"sfx0": _sfx_snap(), "fps40": 0}
		var d: Dictionary = perf[w]
		d.ft.append((now - perf_last) / 1000.0)
		d.rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		d.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		d.en.append(g.enemies.size())
		if (now - perf_last) > 25000:
			d.fps40 += 1   # 帧时间 > 25 毫秒（低于 40 fps）
		var ft: float = (now - perf_last) / 1000.0
		var br := {}
		if g.prof_on:
			for k in g.prof:
				var v: int = int(g.prof[k]) - int(perf_prev.get(k, 0))
				if v > 0:
					br[k] = v / 1000.0
					d.stage[k] = float(d.stage.get(k, 0.0)) + v / 1000.0
					if ft >= 33.3:
						d.slow_stage[k] = float(d.slow_stage.get(k, 0.0)) + v / 1000.0
		if ft >= 33.3:
			d.slow_n += 1
			perf_slow.append({"t": snappedf(g.t, 0.1), "ft": snappedf(ft, 0.1), "en": g.enemies.size(), "kills": g.kills - perf_kills,
				"ebul": g.ebullets.size(), "warns": g.warns.size(), "fx": g.fx.size(), "gems": g.gems.size(), "mires": g.mires.size(), "boss": g.bosses.size(), "btypes": g.bosses.filter(func(b): return not b.dead).map(func(b): return str(b.type)), "stage": _top_stages(br, 8)})
			if perf_slow.size() > 400:
				perf_slow.sort_custom(func(a, b): return a.ft > b.ft)
				perf_slow.resize(100)
	if g.prof_on:
		perf_prev = g.prof.duplicate()
	perf_kills = g.kills
	perf_last = now


## 各段：帧数、帧时间中位 / 最差 1%（P99）/ 最大、渲染 CPU 中位 / P99、GPU 中位 / P99（毫秒）、敌人数中位 / 峰值
func _perf_summary() -> Dictionary:
	var out := {}
	for w in perf:
		var d: Dictionary = perf[w]
		out[w] = {"n": d.ft.size(), "ft_med": _pct(d.ft, 0.5), "ft_p99": _pct(d.ft, 0.99), "ft_max": _pct(d.ft, 1.0),
			"rcpu_med": _pct(d.rcpu, 0.5), "rcpu_p99": _pct(d.rcpu, 0.99), "gpu_med": _pct(d.gpu, 0.5), "gpu_p99": _pct(d.gpu, 0.99),
			"en_med": _pct(d.en, 0.5), "en_peak": _pct(d.en, 1.0), "slow_n": d.slow_n,
			"stage_ms": _per_frame(d.stage, d.ft.size()), "slow_stage_ms": _per_frame(d.slow_stage, d.slow_n),
			"below40_pct": snappedf(100.0 * d.fps40 / maxf(1.0, d.ft.size()), 0.1), "sfx": _sfx_delta(d.sfx0)}
	perf_slow.sort_custom(func(a, b): return a.ft > b.ft)
	out["slow_top"] = perf_slow.slice(0, 25)
	out["realtime"] = g.realtime
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx != null and "sfx_by" in sfx and not sfx.sfx_by.is_empty():
		out["sfx_by_cat"] = _sfx_cats(sfx.sfx_by)
		var names: Array = sfx.sfx_by.keys()
		names.sort_custom(func(x, y): return sfx.sfx_by[x][0] > sfx.sfx_by[y][0])
		var top := {}
		for n in names.slice(0, 20):
			top[n] = sfx.sfx_by[n]
		out["sfx_by_top"] = top   # 音名 -> [请求, 实播, 合并, 丢弃, 降音量]
	out["video"] = {"bloom": Cfg.bloom, "dof": Cfg.dof, "normal_maps": Cfg.normal_maps, "water_filter": Cfg.water_filter,
		"size": str(g.get_viewport().get_visible_rect().size), "window": str(DisplayServer.window_get_size())}
	return out


func _pct(a, q: float) -> float:
	if a.size() == 0:
		return 0.0
	var b: Array = Array(a)
	b.sort()
	return snappedf(float(b[mini(b.size() - 1, int(q * (b.size() - 1) + 0.5))]), 0.01)


## 分段耗时按帧平均（毫秒 / 帧），从大到小
func _per_frame(tot: Dictionary, n: int) -> Dictionary:
	var out := {}
	var ks: Array = tot.keys()
	ks.sort_custom(func(a, b): return tot[a] > tot[b])
	for k in ks:
		out[k] = snappedf(float(tot[k]) / maxf(1.0, float(n)), 0.01)
	return out


func _top_stages(br: Dictionary, n: int) -> Dictionary:
	var ks: Array = br.keys()
	ks.sort_custom(func(a, b): return br[a] > br[b])
	var out := {}
	for k in ks.slice(0, n):
		out[k] = snappedf(br[k], 0.1)
	return out


## 音效计数（sfx.gd 的 sfx_stat：实际播放 / 同名合并 / 满槽丢弃 / 抢占 / 降音量 / 同时发声峰值）；--perf 按段给增量
func _sfx_snap() -> Dictionary:
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx == null or not ("sfx_stat" in sfx):
		return {}
	return sfx.sfx_stat.duplicate()


func _sfx_delta(s0: Dictionary) -> Dictionary:
	var s1 := _sfx_snap()
	var out := {}
	for k in s1:
		if k == "voices_max":
			out[k] = s1[k]
		else:
			out[k] = int(s1[k]) - int(s0.get(k, 0))
	return out


## 音效按类别汇总：命中 / 击杀 / 拾取 / 受击 / 干员普攻 / 干员技能 / 敌人 / Boss 与演出 / 其他；每类 [请求, 实播, 合并, 丢弃, 降音量]
func _sfx_cats(by: Dictionary) -> Dictionary:
	var out := {}
	for n in by:
		var c := "其他"
		if n == "hit" or n.ends_with("_hit"):
			c = "命中"
		elif n == "kill":
			c = "击杀"
		elif n == "pickup":
			c = "拾取"
		elif n == "hurt" or n == "heartbeat":
			c = "受击"
		elif n.begins_with("op_") and (n.ends_with("_s1") or n.ends_with("_s2") or n.ends_with("_s3") or n.ends_with("_big")):
			c = "干员技能"
		elif n.begins_with("op_") or n == "swing":
			c = "干员普攻"
		elif n.begins_with("enemy_"):
			c = "敌人"
		elif n.begins_with("boss_") or n.begins_with("cue_") or n.ends_with("_break") or n == "roar":
			c = "Boss 与演出"
		if not out.has(c):
			out[c] = [0, 0, 0, 0, 0]
		for i in 5:
			out[c][i] += int(by[n][i])
	return out
