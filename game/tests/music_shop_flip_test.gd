extends Node
## 商店 ↔ 战斗来回切的配乐防抖对照（11-11 iPhone 四 Boss 连测第 2 局 2:43 闪退前约 1 分钟，配乐每 2 秒在 shop / battle1 之间切、30 多次）。
## 桌面无头复现手机网页的「出包配乐」判定：给商店曲与战斗一的占位器挂上假的 web_music 条目（Sfx._wm / _wm_reg），打开手机网页的快换（_swap_fast），
## 照 music_director 每帧调 play_music：前 120 秒每 2 秒进 / 出商店一次，后 30 秒留在战斗。
## 浏览器那边的行为按 sfx.gd 实际发出的调用推：曲目被放掉（Sfx._freed）后再开播 = 一次 fetch + decodeAudioData + 混单声道。
## 驻留 MiB 按手机口径（24 kHz 单声道，战斗曲只留底层 mobile_music_lite）。
## 跑法：godot --headless --audio-driver Dummy --path game res://tests/music_shop_flip_test.tscn [-- --bal=web/music_shop_hold=0]（后者 = 修前写法）
const FLIP := 2.0
const FLIP_FOR := 120.0
const TAIL := 30.0
var t := 0.0
var want := "battle1"
var resident := {}
var decodes := 0
var reuse := 0
var log_t := 0.0
var peak := 0.0
var low := 1e9
var flips := 0
var curve: Array = []
var last_cur := ""

func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	var S = get_node("/root/Sfx")
	for tn in ["shop", "battle1"]:
		var pls: Array = S.lay[tn].players if S.lay.has(tn) else S.groups[tn]
		for i in pls.size():
			var pl: AudioStreamPlayer = pls[i]
			var fn := "fake_%s_%d.m4a" % [tn, i]
			S._wm[fn] = {"len": pl.stream.get_length() if pl.stream != null else 100.0, "url": fn}
			S._wm_reg(pl, tn, fn)
	S._swap_fast = 1
	S.play_music("battle1")

func mib(S, tn: String) -> float:
	var pls: Array = S.lay[tn].players if S.lay.has(tn) else S.groups[tn]
	var ln: float = pls[0].stream.get_length() if pls[0].stream != null else 0.0
	return ln * 24000.0 * 4.0 / 1048576.0

func _process(delta: float) -> void:
	var S = get_node("/root/Sfx")
	t += delta
	if t < FLIP_FOR:
		var w := "shop" if int(t / FLIP) % 2 == 1 else "battle1"
		if w != want:
			want = w
			flips += 1
	else:
		want = "battle1"
	S.play_music(want)
	# 浏览器侧模型：开播时不在内存 = 重新解码；被放掉 = 丢缓冲
	for tn in ["shop", "battle1"]:
		if S._freed.has(tn):
			resident[tn] = false
	if S.cur_track != last_cur:
		last_cur = S.cur_track
		if resident.get(last_cur, false):
			reuse += 1
		else:
			decodes += 1
			resident[last_cur] = true
	var m := 0.0
	for tn in resident:
		if resident[tn]:
			m += mib(S, tn)
	peak = maxf(peak, m)
	if t > 5.0:
		low = minf(low, m)
	log_t += delta
	if log_t >= 2.0:
		log_t = 0.0
		curve.append("%d:%s/%.0f" % [int(t), "+".join(resident.keys().filter(func(k): return resident[k])), m])
	if t >= FLIP_FOR + TAIL:
		var mode := "old" if S._shop_k == 0 else "hold"
		print("SHOPFLIP curve " + " ".join(curve))
		print("SHOPFLIP mode=%s flips=%d decodes=%d reuse=%d mib_peak=%.1f mib_low=%.1f mib_end=%.1f end=%s" % [mode, flips, decodes, reuse, peak, low, m, "+".join(resident.keys().filter(func(k): return resident[k]))])
		get_tree().quit()
