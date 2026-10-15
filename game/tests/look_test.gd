extends Node
## 观感预设（render/look，scripts/render/look.gd；用户 10-12「整体都有点白灰」）快检：
## 档位逐级叠加、亮度缺省在滑杆范围内、软膝封顶数学、角色受光缩放只改画面（不碰 g.rng）、后期着色器带全部参数。
const Look = preload("res://scripts/render/look.gd")

var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("LOOK: " + label)


func _ready() -> void:
	# 档位：0 = 现状（空表），后一档包含前一档的全部键（逐级叠加，方便单独回退某一步）
	check(Look.PRESETS[0].is_empty(), "L0 必须是现状（空表）")
	for i in range(1, Look.PRESETS.size()):
		for k in Look.PRESETS[i - 1]:
			check(Look.PRESETS[i].has(k), "L%d 缺 L%d 的键 %s" % [i, i - 1, k])
		for k in Look.PRESETS[i]:
			check(Look.BASE.has(k), "L%d 未知键 %s" % [i, k])
	for i in Look.PRESETS.size():
		var pr: Dictionary = Look.BASE.duplicate()
		pr.merge(Look.PRESETS[i], true)
		var bd: float = pr.bright_def
		check(bd >= 0.8 and bd <= 1.4 and absf(bd / 0.05 - roundf(bd / 0.05)) < 0.001, "L%d 亮度缺省 %.2f 不在滑杆刻度上" % [i, bd])
		if pr.actor_cap > 0.0:
			check(pr.actor_cap > pr.actor_knee, "L%d 封顶要高于起弯点" % i)
			# 软膝：起弯点以下不变；以上单调、连续、永远不超过 cap
			var last := 0.0
			for j in 60:
				var mx := 0.5 + j * 0.05
				var out: float = mx * Look.knee_scale(mx, pr.actor_knee, pr.actor_cap)
				if mx <= pr.actor_knee:
					check(is_equal_approx(out, mx), "L%d 起弯点以下应不变" % i)
				check(out <= pr.actor_cap + 0.0001, "L%d 倍率 %.2f 超过封顶" % [i, mx])
				check(out >= last - 0.0001, "L%d 软膝不单调" % i)
				last = out
	# 当前档：设置里的亮度缺省跟随预设（快检的临时存档不写亮度）
	check(is_equal_approx(Cfg.brightness, Look.p("bright_def")), "Cfg.brightness 缺省 %.2f ≠ 预设 %.2f" % [Cfg.brightness, Look.p("bright_def")])
	# 旧存档亮度迁移：旧缺省 110% 跟到新缺省，自己调过的、新口径存档都不动
	var Settings = load("res://scripts/settings.gd")
	check(is_equal_approx(Settings.migrate_brightness(1.1, 0), Look.p("bright_def")), "旧缺省 110% 应跟到新缺省")
	check(is_equal_approx(Settings.migrate_brightness(1.25, 0), 1.25), "自己调过的亮度不动")
	check(is_equal_approx(Settings.migrate_brightness(1.1, Settings.LOOK_VER), 1.1), "新口径存档的 110% 不动")
	# 后期着色器带全部观感参数
	var names: Array = []
	for u in load("res://shaders/post.gdshader").get_shader_uniform_list():
		names.append(u.name)
	for k in ["brightness", "bloom_threshold", "shoulder", "black_pt", "toe", "pivot", "sat"]:
		check(names.has(k), "post.gdshader 缺参数 " + k)
	# 角色受光缩放：只读灯光、不碰对局随机数；离灯越远越接近 1，灯下不超过 1
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	g.set_process(false)
	var st: Array = g.rng_states()
	g.lamp_light.position = Vector2(100, 100)
	g.lamp_light.texture_scale = 520.0 / 64.0
	var near: Color = Look.actor_mod(g, Vector2(100, 136))
	var far: Color = Look.actor_mod(g, Vector2(3000, 3000))
	check(near.r <= 1.0 and near.r > 0.5, "灯下缩放 %.3f 应在 (0.5, 1]" % near.r)
	if Look.p("actor_tint") <= 0.0 and Look.p("actor_neutral") <= 0.0:
		check(is_equal_approx(near.r, near.b), "不去暖时三通道应相同")
	if Look.p("actor_neutral") > 0.0:
		# 只去暖：R 缩放不变（软膝照旧按最大通道），G / B 只往上补、不超过把它们补满到 R 的量
		check(near.g >= near.r - 0.0001 and near.b >= near.g - 0.0001, "去暖应只抬 G / B（%.3f %.3f %.3f）" % [near.r, near.g, near.b])
	# 白色保护：材质挂在 game 节点上；干员 modulate 走负号标记，灯外 / 关掉时原样
	if Look.p("white_lift") > 0.0:
		check(g.actor_mat != null and g.material == g.actor_mat, "白色保护开着却没挂材质")
		var om: Color = Look.op_mod(g, Vector2(100, 136), Color.WHITE)
		check(om.r < 0.0 and om.g < 0.0 and om.b < 0.0 and om.a == 1.0, "白色保护：干员 modulate 应带负号标记")
	else:
		check(g.actor_mat == null and g.material == null, "白色保护关着不该挂材质")
		check(Look.op_mod(g, Vector2(100, 136), Color.WHITE) == near, "白色保护关着 op_mod 应等于 actor_mod")
	check(far == Color.WHITE, "远离灯火应不缩放")
	if Look.p("actor_cap") <= 0.0:
		check(near == Color.WHITE, "L0 不缩放")
	check(g.rng_states() == st, "Look.actor_mod 碰了 g.rng")
	print("LOOK TEST failures=%d (look=%d)" % [failures, Look.level()])
	get_tree().quit(1 if failures > 0 else 0)
