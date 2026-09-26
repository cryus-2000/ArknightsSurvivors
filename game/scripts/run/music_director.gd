extends RefCounted
## 局内配乐调度：按战斗强度 / Boss / 灯火选曲与分层（Sfx 负责播放与对拍），--musiclog 记录。
## 2026-09-26 从 game.gd 拆出。

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
var stinger_done := false
var music_lv := 0               # 战斗配乐强度：0 平静 / 1 交战（打击乐）/ 2 激战（全奏），docs/21 v2.0
var music_hold := 0.0           # 降一档之前还要保持的秒数
var music_calm := 0.0           # Boss 倒下后的喘息（秒）：只要局面不到激战，就压回平静层
var music_boss := false
var music_hp_avg := -1.0        # 生命的 4 秒指数均值：当前生命比它低多少 = 近几秒的净掉血（治疗抵掉的不算）
var music_t := 0.0              # 上次更新时的局内时间：各计时按局内时间走（暂停 / 选卡时不动，平衡批跑加速时也对）
var music_horde := 0.0          # 大群来袭后维持激战的秒数
var music_hot := 0.0            # 分数连续够「激战」的秒数（一闪而过的尖峰不升档）
var music_danger := false
var music_log: bool = OS.get_cmdline_user_args().has("--musiclog")   # 打印配乐状态切换（调强度阈值用）
var music_log_key := ""
var music_log_tick := -1


func _init(game: Game) -> void:
	g = game


func update(_dt: float) -> void:
	if g.demo_op != "":
		return
	var target := 20000.0
	if g.state == g.S.PLAY and g.lamp < 30.0:
		target = lerp(700.0, 4000.0, g.lamp / 30.0)
	if g.state == g.S.PAUSE or g.state == g.S.CHOICE or g.state == g.S.SHOP or g.state == g.S.SHOW or g.state == g.S.STATS or g.state == g.S.INTRO or g.state == g.S.OPENING:
		target = 1800.0
	Sfx.cut_target = target
	Sfx.vol_target = -4.0
	# ---- 选曲与战斗分层（v2.0 配乐，docs/21）
	if g.state == g.S.DEAD or g.state == g.S.WIN:
		if not stinger_done:
			stinger_done = true
			Sfx.play_stinger("win" if g.state == g.S.WIN else "lose")
		return
	if g.state == g.S.SHOP:
		Sfx.play_music("shop")
		return
	if g.state == g.S.OPENING or (g.state == g.S.INTRO and g.intro_back == g.S.PLAY and Sfx.track_playing("opening")):
		# 开场动画（及首次进入的指南）：播放开场引子《沉降》，动画结束后战斗曲淡入
		Sfx.play_music("opening")
		return
	if g.final_boss != null and not g.final_boss.dead:
		Sfx.play_music("final")
		Sfx.set_final_phase(g.final_boss.hp < g.final_boss.maxhp * 0.5)
		music_boss = true
		write_log("final")
		return
	if g.spawner.boss_alive():
		Sfx.play_music("boss")
		music_boss = true
		write_log("boss")
		return
	if music_boss:
		music_boss = false
		music_calm = 12.0
		music_lv = 0
		music_horde = 0.0
	# 战斗曲三段：按威胁等级推进（0–1 开局 / 2–3 中期 / 4+ 后期），换段落在小节线上
	var sec := "battle1" if g.threat < 2 else ("battle2" if g.threat < 4 else "battle3")
	Sfx.play_music(sec)
	var dt := clampf(g.t - music_t, 0.0, 1.0)
	music_t = g.t
	# 强度打分：一屏内的敌人密度（门槛随时间提高）+ 精英 + 大群 + 缩圈 + 近几秒掉血；技能不再算（几乎一直有技能在放）
	var near := 0
	var elite := false
	for e in g.enemies:
		if e.dead or e.chest:
			continue
		if e.elite:
			elite = true
		if e.pos.distance_squared_to(g.ppos) < 640000.0:
			near += 1
	if music_hp_avg < 0.0:
		music_hp_avg = g.hp
	music_hp_avg += (g.hp - music_hp_avg) * minf(1.0, dt / 4.0)
	var hurt := (music_hp_avg - g.hp) / maxf(g.max_hp, 1.0)
	if g.horde_warn > 0.0 or g.horde_hit > 0.0:
		music_horde = 15.0
	music_horde = maxf(0.0, music_horde - dt)
	# 正常密度（机器人实测 800 像素内敌人数，中位到上四分位之间，docs/21 标定记录）≈ 55 + 0.25·t；比它多出来的部分才加分
	var score := maxf(0.0, float(near) / (55.0 + 0.25 * g.t) - 1.0)
	if elite:
		score += 0.45
	if music_horde > 0.0:
		score += 1.0
	if g.zone_state == 2:
		score += 0.45
	if hurt > 0.12:
		score += 0.5
	if g.threat >= 4:
		score += 0.15
	var lv := 2 if score >= 1.15 else (1 if score >= 0.35 or g.t > 20.0 else 0)
	music_hot = music_hot + dt if lv == 2 else 0.0
	if lv == 2 and music_lv < 2 and music_hot < 1.5:
		lv = 1
	music_calm = maxf(0.0, music_calm - dt)
	if music_calm > 0.0 and lv < 2:
		lv = 0
	# 升档马上（落在下一个小节线；激战要连续 1.5 秒够格），降档要这一档连续 12 秒不够格
	if lv >= music_lv:
		music_lv = lv
		music_hold = 12.0
	else:
		music_hold -= dt
		if music_hold <= 0.0:
			music_lv -= 1
			music_hold = 8.0
	var out_zone := g.zone_state != 0 and g.ppos.distance_to(g.zone_c) > g.zone_r
	music_danger = g.hp < g.max_hp * (0.42 if music_danger else 0.35) or g.lamp <= 0.0 or out_zone
	Sfx.set_battle(music_lv, music_danger)
	write_log("%s lv%d%s score=%.2f near=%d" % [sec, music_lv, " danger" if music_danger else "", score, near])


## --musiclog：配乐状态变化时打印一行（只比较曲目 / 档位 / 危险，分数随附）；另外每 5 秒采样一行（MUSICS）
func write_log(s: String) -> void:
	if not music_log:
		return
	var key := s.get_slice(" score", 0)
	if key != music_log_key:
		music_log_key = key
		print("MUSIC t=%.1f %s" % [g.t, s])
	if int(g.t / 5.0) != music_log_tick:
		music_log_tick = int(g.t / 5.0)
		var close := 0
		var elite := 0
		for e in g.enemies:
			if not e.dead and not e.chest:
				if e.pos.distance_squared_to(g.ppos) < 90000.0:
					close += 1
				if e.elite:
					elite += 1
		print("MUSICS t=%.0f n=%d close=%d elite=%d horde=%.0f zone=%d hurt=%.2f threat=%d hp=%.2f | %s" % [
			g.t, g.enemies.size(), close, elite, music_horde, g.zone_state, (music_hp_avg - g.hp) / maxf(g.max_hp, 1.0), g.threat, g.hp / maxf(g.max_hp, 1.0), s])
