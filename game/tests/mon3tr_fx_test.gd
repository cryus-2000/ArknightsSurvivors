## Mon3tr 爪击特效与熔毁帧条（10-12 起凯尔希是数据干员，Mon3tr 是 blocks.summons.mon3tr 随行召唤物，docs/61 §15.9）：
## 普通 / 战术协同 / 熔毁 × 朝右 / 朝左各挥一爪，查对应的 vfx 帧条（爪痕 / 猩红月牙）出现且朝左时翻转；熔毁期间攻击帧条换 op_mon3tr_attack_melt。
## --capture-fx 时把每种情况截图到 build/mon3tr_fx_<模式>_<朝向>.png
extends Node
const OB = preload("res://scripts/characters/op_blocks.gd")
var g
var frames := 0
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	g.set_process(false)
	var op = g.squad.get_op("kaltsit")
	assert(op != null)
	var failures := 0
	if op.pos == Vector2.INF:
		op.pos = g.ppos
	OB.mf_tick(op, 0.0, [0.0, 0.0, 0.0])   # 局还没开始跑时（第 5 帧）手动执行 trig.on_deploy 放出 Mon3tr
	if op.sm.is_empty() or op.sm.list.is_empty():
		print("MISSING Mon3tr summon after deploy")
		print("MON3TR FX failures=1")
		get_tree().quit.call_deferred(1)
		return
	var s: Dictionary = op.sm.list[0]
	var kd: Dictionary = OB.sm_kind(op, "mon3tr")
	s.pos = g.ppos
	for mode in [0, 1, 2]:
		for face in [1.0, -1.0]:
			g.fx.clear()
			s.face = face
			s.ak = "attack"
			s.at = 2.0 / 14.0
			op.perm_on[1] = mode == 1
			op.s_t[2] = 1.0 if mode == 2 else 0.0
			op._sustain(0.0)
			OB._mf_patch_tick(op, s, kd, 0.0)
			OB._mf_claw(op, s, kd, 1.0, false)
			var expected := "fx_mon3tr_melt_slash" if mode == 2 else "fx_mon3tr_claw"
			var found := false
			var n_claw := 0
			for f in g.fx:
				if f.get("name", "") == expected:
					found = true
					n_claw += 1
					assert(f.flip == (face < 0.0))
			if not found:
				failures += 1
				print("MISSING ", expected, " mode=", mode, " face=", face)
			if mode == 1 and n_claw < 2:   # 战术协同：叠一道反向爪痕
				failures += 1
				print("MISSING coord second claw mark face=", face)
			if OS.get_cmdline_user_args().has("--capture-fx"):
				for f in g.fx:
					if f.get("kind", "") == "sprite":
						f.life = f.max * 0.4
				g.queue_redraw()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("../build/mon3tr_fx_%s_%s.png" % [mode, int(face)])
	op.s_t[2] = 1.0
	OB._mf_patch_tick(op, s, kd, 0.0)
	var attack_frame: Array = OB._mf_frame(op, s, kd, "attack", 2.0 / 14.0)
	if attack_frame.is_empty() or attack_frame[0] != load("res://scripts/art.gd").tex("op_mon3tr_attack_melt"):
		failures += 1
		print("MISSING meltdown attack body animation")
	var idle_frame: Array = OB._mf_frame(op, s, kd, "idle", 0.0)
	if idle_frame.is_empty() or idle_frame[0] != load("res://scripts/art.gd").tex("op_mon3tr_skill"):
		failures += 1
		print("MISSING meltdown idle strip (m_skill)")
	print("MON3TR FX failures=", failures)
	op = null
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
