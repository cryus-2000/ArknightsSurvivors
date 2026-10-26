extends Node
## 乌尔比安 S3 冲锋特效录帧 / 帧时探针（docs/143；不进快检）：开窗口跑，tools/probes/ulp_charge_shot.py 调。
##   godot --fixed-fps 60 --path game res://tests/ulp_charge_shot.tscn -- --op=ulpianus --ulpn=100 --shotdir=<目录> [--ulprec] [--ulpperf=N] [--ulpold]
## 第 30 帧清场（停刷怪）、在队长周围摆 --ulpn 只不动的高血量小怪（路径上另摆 5 只），第 40 帧起每 120 帧放一次 S3（前摇约 20 帧 + 掷锚 13 帧 + 冲锋约 15 帧）（左右来回）。
## --ulprec：第一次放技能起连存 90 帧 rec_<帧>.png；--ulpold：冲锋颗粒关（旋钮 fx/ulp_charge_grains = 0，= 旧版 / 低画质画法；刀光第四版照常）。
## --ulpperf=N：放 N 次（前 2 次只预热不计：首次冲锋有着色器编译尖峰，网页实测 4 秒），单数次冲锋颗粒开、双数次关（同局轮换，只切 fx/ulp_charge_grains），关垂直同步不锁帧，量每次冲锋窗口（放技能后第 16–75 帧：掷锚 → 冲锋 → 落地颗粒散尽）的真实帧间隔与同屏颗粒数（Performance 的 process 监视器是采样保持值，不可用），打印 ULPPERF {json}

const Bal = preload("res://scripts/core/balance.gd")

var game: Node
var frames := 0
var n_en := 100
var rec := false
var old := false
var perf := 0
var shot_dir := ""
var casts := 0
var cast_at := -1
var last_us := 0
var buckets := {"g1": [], "g0": []}
var gbuckets := {"g1": [], "g0": []}
var rec_i := 0
var click := false   # --ulpclick：左键点击释放演示（10-26），见 _click_demo
var n_alive := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ulpn="):
			n_en = int(a.substr(7))
		elif a == "--ulprec":
			rec = true
		elif a == "--ulpclick":
			click = true
		elif a == "--ulpold":
			old = true
		elif a.begins_with("--ulpperf="):
			perf = int(a.substr(10))
		elif a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
	if perf > 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # 不锁帧：帧间隔 = 真实开销
		Engine.max_fps = 0
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	var now := Time.get_ticks_usec()
	var dt_us := now - last_us
	last_us = now
	if frames == 30:
		_setup()
	if frames < 40:
		return
	var o = game.squad.get_op("ulpianus")
	if o == null:
		print("ULPPERF no ulpianus")
		get_tree().quit(1)
		return
	if click:
		_click_demo(o)
		return
	var gr = game.optical.grains if game.optical != null else null
	if (frames - 40) % 120 == 0:
		var lim: int = perf if perf > 0 else 1
		if casts >= lim:
			_finish()
			return
		if casts > 0:
			_setup()   # 每次放技能前补满 --ulpn 只（被击退 / 远离队长回收的会少），队长回到同一起点
		_set_new(not old if perf == 0 else casts % 2 == 0)
		var dir := 1.0 if casts % 2 == 0 else -1.0
		o.sp[2] = o.sp_need(2)
		o.elite = 2
		o.attack_t = 0.0
		o.fire_t = -1.0
		var okc: bool = o.cast_manual(2, Vector2.ZERO, game.ppos + Vector2(300.0 * dir, 40.0))
		if not okc:
			print("ULPCAST %d failed" % casts)
		cast_at = frames
		casts += 1
	if rec and casts == 1 and frames - cast_at < 90 and shot_dir != "":
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1
	if perf > 0 and casts > 2 and cast_at > 0 and frames - cast_at > 15 and frames - cast_at <= 75:
		if frames - cast_at == 16:
			n_alive = game.enemies.filter(func(e): return not e.dead).size()
		var key := "g1" if Bal.v("fx/ulp_charge_grains", 1.0) > 0.0 else "g0"
		buckets[key].append(dt_us / 1000.0)
		gbuckets[key].append(gr.pos.size() + gr.sparks.size() if gr != null else 0)


## 只切冲锋特效（旋钮 fx/ulp_charge_grains），刀光第四版等其余颗粒照常
func _set_new(on: bool) -> void:
	Bal.v("fx/ulp_charge_grains", 1.0)   # 先触发读 balance.json
	if not (Bal._data.get("fx") is Dictionary):
		Bal._data["fx"] = {}
	Bal._data.fx["ulp_charge_grains"] = 1.0 if on else 0.0
	Bal._data.fx["ulp_burst"] = 1.0 if on else 0.0   # 落地冲击环（docs/143 §8）随新旧一起切


## --ulpclick：左键点击释放 S3 的演示（10-26 用户「三技能要设置成鼠标点击也能够触发」），往视口推真实的鼠标事件（不动系统光标）：
## 第 55 帧技力半满点地面（不放、点击照旧）→ 第 110 帧技力满时点右下编队栏（HUD，不放）→ 第 150 帧技力满时点地面（放出）。
## 每帧存 rec_<帧>.png；每次点击打印 ULPCLICK <录制帧号> <视口 x> <视口 y> <是否放出>，出片时据此画光标与点击圈
func _click_demo(o) -> void:
	var f: int = frames - 40
	if f == 0:
		o.elite = 2
		o.sp[2] = o.sp_need(2) * 0.5
	if f == 108 or f == 150:
		o.sp[2] = o.sp_need(2)   # 点击那一帧前后才充满：--bot=afk 的机器人技力一满会自己放 S3（本节点先于游戏处理，点击当帧机器人抢不到）
	if f == 112:
		o.sp[2] = o.sp_need(2) * 0.6
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var tgt: Vector2 = game.get_viewport().get_canvas_transform() * (game.ppos + Vector2(280, 30))
	for c in [[55, tgt], [110, vs - Vector2(70, 70)], [150, tgt]]:
		if f == c[0]:
			var sp0: float = o.sp[2]
			for down in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = down
				ev.position = c[1]
				ev.global_position = c[1]
				get_viewport().push_input(ev)
			print("ULPCLICK %d %.0f %.0f %s" % [rec_i, (c[1] as Vector2).x, (c[1] as Vector2).y, str(o.sp[2] < sp0 or o.manual_buf > 0.0 or not o.hw.get("anchor", {}).is_empty())])
	if shot_dir != "":
		get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%03d.png" % rec_i)
		rec_i += 1
	if f >= 240:
		print("ULPSHOT done frames=%d rec=%d" % [frames, rec_i])
		get_tree().quit(0)


func _setup() -> void:
	var g = game
	g.sandbox = true
	g.fx.clear()   # 停刷怪
	g.max_hp = 99999.0
	g.hp = 99999.0
	for e in g.enemies:
		e.dead = true
	g.enemies = []
	g.ppos = Vector2(1500, 900)
	var cols: int = int(ceil(sqrt(float(n_en))))
	var k := 0
	for i in n_en:
		var p := Vector2(1500 - 330 + float(i % cols) * 660.0 / cols, 900 - 200 + float(i / cols) * 400.0 / cols)
		if p.distance_to(Vector2(1500, 900)) < 70.0:
			continue   # 起点周围留空（贴身的怪会出攻击预警圈，盖住起冲画面）
		if absf(p.y - 920.0) < 46.0 and absf(p.x - 1500.0) < 330.0:
			p.y += 92.0 * (1.0 if p.y >= 920.0 else -1.0)   # 冲锋路径留出走廊，路径上的另摆
		_spawn(p)
		k += 1
	for i in 5:
		_spawn(Vector2(1500 + 60 + i * 45, 905 + i * 6))
		_spawn(Vector2(1500 - 60 - i * 45, 905 + i * 6))
	g.enemies_sys.build_grid()


func _spawn(p: Vector2) -> void:
	var e: Dictionary = game.spawner.spawn_enemy("bone", p)
	e.hp = 1e7
	e.max_hp = 1e7
	e.spd = 0.0
	e.age = 5.0


func _stat(a: Array) -> Dictionary:
	if a.is_empty():
		return {}
	var s := a.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	return {"n": s.size(), "mean": snappedf(sum / s.size(), 0.01), "p50": snappedf(float(s[s.size() / 2]), 0.01), "p95": snappedf(float(s[int(s.size() * 0.95)]), 0.01), "max": snappedf(float(s[-1]), 0.01)}


func _finish() -> void:
	if perf > 0:
		var line := "ULPPERF " + JSON.stringify({"enemies": n_alive, "frame_g1": _stat(buckets.g1), "frame_g0": _stat(buckets.g0),
			"grains_g1": _stat(gbuckets.g1), "grains_g0": _stat(gbuckets.g0)})
		print(line)
		if OS.has_feature("web"):
			printerr(line)   # 网页测量副本（perf_web.py）只回传 console.error 与 PERF / BALANCE 开头的行
	print("ULPSHOT done frames=%d rec=%d" % [frames, rec_i])
	get_tree().quit(0)
