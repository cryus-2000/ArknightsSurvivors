extends Node
## Suno 整首分层配乐回归（docs/163，10-27）：五首（battle1-3 三层 / boss 一层 / final 两层）载入、同曲各层同长度（±3 毫秒）、
## 开播后各层同时在放、战斗强度（set_battle）在小节线上开关层、战斗换段等当前曲小节线再换、Boss / 最终 Boss 二阶段叠层、
## 回到战斗时清层状态。只看 Sfx 的调度状态（不依赖真的出声，自动测试本来就静音 Master）。
## 全部通过时打印 "SUNO LAYERS: 0 failures"。
var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)


func _ready() -> void:
	call_deferred("run")


func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func run() -> void:
	var want := {"battle1": 3, "battle2": 3, "battle3": 3, "boss": 1, "final": 2}
	for tn in want:
		check(Sfx.lay.has(tn), "整首分层载入：" + tn)
		if not Sfx.lay.has(tn):
			continue
		var pls: Array = Sfx.lay[tn].players
		check(pls.size() == int(want[tn]), "%s 层数 %d（期望 %d）" % [tn, pls.size(), want[tn]])
		var l0: float = (pls[0].stream as AudioStream).get_length()
		check(l0 > 120.0, "%s 时长 > 120 秒（%.1f）" % [tn, l0])
		for pl in pls:
			check(absf((pl.stream as AudioStream).get_length() - l0) < 0.003, "%s 各层同长度" % tn)
		check(float(Sfx.lay[tn].bpm) > 100.0 and float(Sfx.lay[tn].bpm) < 200.0, "%s bpm 合理（%.2f）" % [tn, Sfx.lay[tn].bpm])
		check(not Sfx.seq.has(tn), "%s 不再走 SEQ 乐句拼接" % tn)
	# 战斗一：平静只有底层；交战 / 激战在小节线上进层
	Sfx.set_battle(0, false)
	Sfx.play_music("battle1")
	await wait(0.6)
	check(Sfx.cur_track == "battle1", "进 battle1：" + Sfx.cur_track)
	var b1: Array = Sfx.lay["battle1"].players
	for pl in b1:
		check(pl.playing, "battle1 各层同时在放")
	check(Sfx.stem_on["battle1"] == [1.0, 0.0, 0.0], "平静：只开底层 " + str(Sfx.stem_on["battle1"]))
	Sfx.set_battle(1, false)
	await wait(2.2)   # 一小节约 1.7 秒（bpm 140.8），进层落在下一条小节线
	check(Sfx.stem_on["battle1"] == [1.0, 1.0, 0.0], "交战：底层 + 打击乐 " + str(Sfx.stem_on["battle1"]))
	Sfx.set_battle(2, false)
	await wait(2.2)
	check(Sfx.stem_on["battle1"] == [1.0, 1.0, 1.0], "激战：三层全开 " + str(Sfx.stem_on["battle1"]))
	check(float(Sfx.stem_vol["battle1"][2]) > 0.9, "驱动层淡入完成（%.2f）" % Sfx.stem_vol["battle1"][2])
	# 危险层没有素材：危险时把驱动层拉出来代替
	Sfx.set_battle(0, true)
	await wait(2.2)
	check(Sfx.stem_on["battle1"][2] == 1.0, "危险：驱动层顶替危险层")
	Sfx.set_battle(0, false)
	await wait(2.2)
	check(Sfx.stem_on["battle1"] == [1.0, 0.0, 0.0], "回平静：只剩底层 " + str(Sfx.stem_on["battle1"]))
	# 战斗换段：等 battle1 的小节线再换 battle2，新曲从头开
	var pos1: float = Sfx._lay_pos("battle1")
	Sfx.play_music("battle2")
	check(Sfx.pending.get("track", "") == "battle2" and Sfx.pending.has("at"), "换段：挂起到小节线（pending=%s）" % str(Sfx.pending))
	var bar: float = 240.0 / float(Sfx.lay["battle1"].bpm)
	var wait_s: float = float(Sfx.pending.get("at", 0.0)) - Sfx._now()
	check(wait_s >= 0.0 and wait_s <= bar + 0.1, "换段最多等一小节（%.2f 秒，小节 %.2f）" % [wait_s, bar])
	await wait(bar + 0.6)
	check(Sfx.cur_track == "battle2", "换到 battle2：" + Sfx.cur_track)
	check((Sfx.lay["battle2"].players[0] as AudioStreamPlayer).playing, "battle2 在放")
	check(Sfx._lay_pos("battle2") < bar + 1.5, "battle2 从头开（%.2f 秒）" % Sfx._lay_pos("battle2"))
	# Boss：单层
	Sfx.play_music("boss")
	await wait(1.2)
	check(Sfx.cur_track == "boss" and (Sfx.lay["boss"].players[0] as AudioStreamPlayer).playing, "Boss 曲在放：" + Sfx.cur_track)
	# 最终 Boss：一阶段只有 p1，二阶段在小节线上叠 p2
	Sfx.set_final_phase(false)
	Sfx.play_music("final")
	await wait(1.5)
	check(Sfx.cur_track == "final", "最终 Boss 曲：" + Sfx.cur_track)
	check(Sfx.stem_on["final"] == [1.0, 0.0], "一阶段只开 p1 " + str(Sfx.stem_on["final"]))
	Sfx.set_final_phase(true)
	await wait(2.2)
	check(Sfx.stem_on["final"] == [1.0, 1.0], "二阶段叠 p2 " + str(Sfx.stem_on["final"]))
	# 回战斗：二阶段状态不残留
	Sfx.set_final_phase(false)
	Sfx.play_music("battle3")
	await wait(2.5)
	check(Sfx.cur_track == "battle3", "回战斗 battle3：" + Sfx.cur_track)
	check(Sfx.stem_on["battle3"][0] == 1.0, "battle3 底层开")
	print("SUNO LAYERS: %d failures" % failures)
	get_tree().quit(1 if failures > 0 else 0)
