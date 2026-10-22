extends Node
## 10-23 手动普攻探针（用户定：手动模式按攻击键不要求有目标，方向由玩家指向，不吸附最近敌人）：
## 以 PLAY 模式起一局（无机器人），清空敌人，打开手动普攻并模拟按住攻击键、指向右；在队长左侧 220 处放一只不动的木桩。
## 跑 probe 秒后打印：普攻出手次数 atk_n、队长子弹 / 弹体数、木桩掉血（应为 0 = 没吸附到背后的敌人）。
## 用法：tools/probes/manual_aim_probe.py [--ops a,b] [--t 6]

func _ready() -> void:
	var id := "exusiai"
	var probe_t := 6.0
	var dx := -220.0      # 木桩相对队长的 x（负 = 背后，指向为右）
	var line := 1         # 沿 +x 每 60 px 放几只木桩（穿透验收用）
	var card := 0         # 先选几次「贯穿」卡
	var relic := ""       # 先给的藏品编号（穿甲弹 265）
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-op="): id = arg.get_slice("=", 1)
		if arg.begins_with("--probe-t="): probe_t = float(arg.get_slice("=", 1))
		if arg.begins_with("--probe-dx="): dx = float(arg.get_slice("=", 1))
		if arg.begins_with("--probe-line="): line = int(arg.get_slice("=", 1))
		if arg.begins_with("--probe-card="): card = int(arg.get_slice("=", 1))
		if arg.begins_with("--probe-relic="): relic = arg.get_slice("=", 1)
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	var o = g.squad.get_op(id)
	assert(o != null)
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var dummies: Array = []
	for i in line:
		var dm: Dictionary = g.spawner.spawn_enemy("stone", g.ppos + Vector2(dx + 60.0 * i, 0))
		dm.hp = 100000.0
		dm.max_hp = dm.hp
		dm.spd = 0.0
		dummies.append(dm)
	g.enemies_sys.build_grid()
	for i in card:
		g.doctor.apply_passive("pierce")
	if relic != "":
		g.relics.append(relic)
		g.rfx.rebuild()
	g.doctor.manual_attack = true
	g.doctor.sim_atk = true
	g.move_in = Vector2.ZERO
	g.facing = 1.0
	var hp0: float = dummies[0].hp
	var steps := int(probe_t * 60.0)
	var bul_max := 0
	var atk0: int = int(o.get("atk_n")) if o.get("atk_n") != null else 0
	for k in steps:
		o.sp = [-100000.0, -100000.0, -100000.0]   # 不放技能，只看普攻
		for i in dummies.size():
			dummies[i].pos = g.ppos + Vector2(dx + 60.0 * i, 0)
			dummies[i].kb = Vector2.ZERO
			dummies[i].hp = maxf(dummies[i].hp, 1.0)
			dummies[i].dead = false
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)
		var n_b := 0
		for b in g.bullets:
			if str(b.get("op", "")) == id: n_b += 1
		var st = o.get("hw")
		if st is Dictionary:
			for key in ["waves", "bolts", "lobs", "shells"]:
				if st.has(key) and st[key] is Array: n_b += st[key].size()
		var ex = o.get("exu")
		if ex is Dictionary and ex.has("bul"): n_b += ex.bul.size()
		var lm = o.get("lm")
		if lm is Dictionary and lm.has("bolts"): n_b += lm.bolts.size()
		bul_max = maxi(bul_max, n_b)
		if k % 120 == 0:
			await get_tree().process_frame
	var atk_n: int = (int(o.get("atk_n")) if o.get("atk_n") != null else 0) - atk0
	var dmgs := []
	for dm in dummies:
		dmgs.append(snappedf(hp0 - float(dm.hp), 0.1))
	print("MANUALPROBE op=%s atk_n=%d bullets_max=%d dummy_dmg=%s face=%d" % [id, atk_n, bul_max, str(dmgs), int(o.face)])
	get_tree().quit()
