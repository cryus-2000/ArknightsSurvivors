extends Node
## 局外配乐回归（docs/21「局外配乐」，用户 10-12）：每个局外界面请求对的曲目（标题 / 设置 / 操作说明 / 致谢 / 换封面 = title，
## 图鉴 = archive，选人 / 难度 / Boss 演练 = deploy）；从图鉴回标题时标题曲接着放（位置 > 0，不从头）；选人 ↔ 难度共用一首不重开；
## 进局（开场引子开播）清空记忆，再回标题从头放。只看 Sfx 的调度状态（cur_track / menu_pos / track_pos，按墙钟算），
## 不依赖真的出声（自动测试本来就静音 Master）
var failures := 0
var title: Control


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)


func _ready() -> void:
	call_deferred("run")


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func run() -> void:
	for tn in ["title", "archive", "deploy"]:
		check(Sfx.groups.has(tn) and Sfx.groups[tn].size() == 1, "局外曲目载入：" + tn)
		if Sfx.groups.has(tn) and not Sfx.groups[tn].is_empty():
			var st: AudioStream = Sfx.groups[tn][0].stream
			check(st != null and st.get_length() > 60.0, "%s 长度 > 60 秒（%s）" % [tn, st.get_length() if st != null else -1.0])
	title = load("res://main.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	title.intro = title.INTRO_LEN
	await frames()
	check(title.menu_track() == "title" and Sfx.cur_track == "title", "标题页放 title：" + Sfx.cur_track)
	await wait(0.8)
	var t_before: float = Sfx.track_pos("title")
	check(t_before > 0.5, "标题曲在走：%.2f" % t_before)
	# 图鉴：archive；标题曲淡完停下时记住位置
	title.gallery.open()
	await frames()
	check(Sfx.cur_track == "archive", "图鉴放 archive：" + Sfx.cur_track)
	await wait(1.5)
	check(not Sfx.groups["title"][0].playing, "标题曲约 1 秒淡完停下")
	var saved: float = float(Sfx.menu_pos.get("title", -1.0))
	check(saved >= t_before, "离开标题时记住位置：%.2f（离开前 %.2f）" % [saved, t_before])
	check(Sfx.track_pos("archive") > 1.0, "图鉴曲在走：%.2f" % Sfx.track_pos("archive"))
	# 回标题：接着放，不从头
	title.gallery.close()
	await frames()
	check(Sfx.cur_track == "title", "关图鉴回 title：" + Sfx.cur_track)
	var t_back: float = Sfx.track_pos("title")
	check(t_back >= saved and t_back > 0.5, "回标题接着放：%.2f（记下 %.2f）" % [t_back, saved])
	await wait(1.5)
	check(float(Sfx.menu_pos.get("archive", -1.0)) > 1.0, "图鉴曲也记住位置：%s" % Sfx.menu_pos.get("archive", -1.0))
	# 切走又在淡完之前切回：不重开（开播时刻不变）
	var t0_title: float = Sfx.track_t0["title"]
	title.gallery.open()
	await frames(2)
	title.gallery.close()
	await frames()
	check(Sfx.cur_track == "title" and Sfx.track_t0["title"] == t0_title, "没淡完就切回：不重开")
	await wait(1.2)
	# 选人（出发前）：deploy；选人 → 难度共用一首，不重开
	title._open_op_pick(false)
	await frames()
	check(Sfx.cur_track == "deploy", "选人放 deploy：" + Sfx.cur_track)
	var t0_dep: float = Sfx.track_t0.get("deploy", -1.0)
	await wait(0.3)
	title.op_pick = false
	title.diff_pick = true
	await frames()
	check(Sfx.cur_track == "deploy" and Sfx.track_t0.get("deploy", -2.0) == t0_dep, "选人 → 难度不重开 deploy")
	title.diff_pick = false
	await frames()
	check(Sfx.cur_track == "title", "退回标题：" + Sfx.cur_track)
	# 换封面干员（同一个选人页，但不是出发前）：仍是 title
	title._open_op_pick(true)
	await frames()
	check(Sfx.cur_track == "title", "换封面干员仍放 title：" + Sfx.cur_track)
	title.op_pick = false
	title.cover_pick = false
	await frames()
	# Boss 演练：deploy（对外包没有这个入口时跳过）
	if Cfg.can_boss_trial():
		title.boss_trial.open()
		await frames()
		check(Sfx.cur_track == "deploy", "Boss 演练放 deploy：" + Sfx.cur_track)
		title.boss_trial.close()
		await frames()
	# 设置 / 操作说明 / 致谢：title
	title.settings.open()
	await frames()
	check(Sfx.cur_track == "title", "设置放 title：" + Sfx.cur_track)
	title.settings.visible = false
	title.guide = true
	await frames()
	check(Sfx.cur_track == "title", "操作说明放 title：" + Sfx.cur_track)
	title.guide = false
	title.credits = true
	await frames()
	check(Sfx.cur_track == "title", "致谢放 title：" + Sfx.cur_track)
	title.credits = false
	# 出发（载入中）：不换曲
	title._open_op_pick(false)
	await frames()
	title.op_pick = false
	title.leaving = 0.0   # 0.7 秒后才切场景，这里几帧就查完
	await frames()
	check(Sfx.cur_track == "deploy", "出发后保持 deploy：" + Sfx.cur_track)
	title.queue_free()
	await frames()
	# 进局：开场引子开播清空记忆；再回标题从头放
	Sfx.play_music("opening")
	await frames()
	check(Sfx.menu_pos.is_empty(), "进局清空局外曲目位置：%s" % Sfx.menu_pos)
	await wait(1.5)
	Sfx.play_music("title")
	await frames()
	check(Sfx.track_pos("title") < 0.5, "打完一局回标题从头放：%.2f" % Sfx.track_pos("title"))
	# 音乐总线：局外曲目都走 Music（音量 / 静音设置对它们生效）
	for tn in ["title", "archive", "deploy"]:
		check(Sfx.groups[tn][0].bus == "Music", tn + " 走 Music 总线")
	print("MENU BGM: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
