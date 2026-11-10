extends Node
## 开场运输机「坏家伙号」释放验收（--openingmem / --openingmem=skip，11-10 用户：确保飞机飞走之后内存清理干净）。
## intro.start_opening 在带参数时把它挂到对局下：记下运输机贴图与引擎声的弱引用，
## 正常路线等到 CLEAR_SKY 之后、跳过路线在落地前点跳过，再过 0.5 秒检查两份资源都已释放、播放器已删、没进资源缓存。
var g
var tex_ref: WeakRef
var snd_ref: WeakRef
var player_ref: WeakRef
var skip := false
var t := 0.0
var t_check := -1.0
var done := false
var failures := 0
var ms_check := -1   # 放手后按真实时间再等：无头 --fixed-fps 跑得比真实时间快，音频线程要真实时间才处理 stop 释放回放（流引用在回放里）


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)


func _process(dt: float) -> void:
	if done or g == null:
		return
	t += dt
	var it = g.intro_screen
	if skip and t_check < 0.0 and it.opening_t >= 1.5:
		it.end_opening()   # 玩家点跳过
		t_check = t + 0.5
		ms_check = Time.get_ticks_msec() + 1500
	if not skip and t_check < 0.0 and it.opening_t >= it.CLEAR_SKY:
		t_check = t + 0.5
		ms_check = Time.get_ticks_msec() + 1500
	if t_check >= 0.0 and t >= t_check and Time.get_ticks_msec() >= ms_check:
		done = true
		_check(it.transport == null, "transport field cleared")
		_check(it.engine_player == null, "engine player field cleared")
		_check(tex_ref.get_ref() == null, "transport texture freed")
		_check(snd_ref == null or snd_ref.get_ref() == null, "rumble stream freed")
		_check(player_ref == null or player_ref.get_ref() == null, "engine player node freed")
		_check(not ResourceLoader.has_cached(it.TRANSPORT_PATH), "transport texture not in resource cache")
		_check(not ResourceLoader.has_cached(it.RUMBLE_PATH), "rumble stream not in resource cache")
		print("OPENING TRANSPORT route=%s failures=%d" % ["skip" if skip else "full", failures])
		get_tree().quit()
