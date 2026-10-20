## Mon3tr 爪击特效与熔毁帧条（10-12 起凯尔希是数据干员，Mon3tr 是 blocks.summons.mon3tr 随行召唤物，docs/61 §15.9）：
## 普通 / 战术协同 / 熔毁 × 朝右 / 朝左各挥一爪；熔毁也必须使用新原生身体，不能回到旧虫形帧条。
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
	if attack_frame.is_empty() or attack_frame[0] != load("res://scripts/art.gd").tex("op_mon3tr_native_s3"):
		failures += 1
		print("MISSING native meltdown attack body animation")
	var idle_frame: Array = OB._mf_frame(op, s, kd, "idle", 0.0)
	if idle_frame.is_empty() or idle_frame[0] != load("res://scripts/art.gd").tex("op_mon3tr_native_idle"):
		failures += 1
		print("MISSING native meltdown idle strip")
	if not s.pcur.has("tint") or float(s.pcur.tint[0]) <= float(s.pcur.tint[1]):
		failures += 1
		print("MISSING crimson treatment on native meltdown body")
	op.s_t[2] = 0.0
	OB._mf_patch_tick(op, s, kd, 0.0)
	var out_frame: Array = OB._mf_frame(op, s, kd, "idle", 0.0)
	if out_frame.is_empty() or out_frame[0] != load("res://scripts/art.gd").tex("op_mon3tr_native_idle"):
		failures += 1
		print("MISSING native body during meltdown exit recovery")
	op.perm_on[1] = true
	OB._mf_patch_tick(op, s, kd, 0.0)
	var s2_frame: Array = OB._mf_frame(op, s, kd, "attack", 2.0 / 14.0)
	if s2_frame.is_empty() or s2_frame[0] != load("res://scripts/art.gd").tex("op_mon3tr_native_s2"):
		failures += 1
		print("MISSING original Skill mapped to S2")
	for skill in [1, 2]:
		op.perm_on[1] = skill == 1
		op.s_t[2] = 5.0 if skill == 2 else 0.0
		s.act = 0.0
		s.cd = 0.0
		s.lunge_cd = INF
		s.tgt = {"pos": s.pos + Vector2(20, 0), "dead": false, "r": 5.0}
		var test_kind: Dictionary = kd.duplicate(true)
		test_kind.erase("manual")
		OB.mf_step(op, s, test_kind, 0.0)
		var visual_slot := "native_m_attack_s2" if skill == 1 else "native_m_attack_melt"
		if not s.has("visual") or str(s.visual.meta.anim) != visual_slot:
			failures += 1
			print("MISSING selected skill timeline S", skill + 1)
		if not is_equal_approx(float(s.act), 4.0 / 14.0) or not is_equal_approx(float(s.fire), 2.5 / 14.0):
			failures += 1
			print("CHANGED gameplay windup for S", skill + 1)
		g.t += 0.19
		OB.mf_step(op, s, test_kind, 0.19)
		var fr: Array = OB._mf_frame(op, s, kd, "attack", float(s.at))
		var release: int = 5 if skill == 1 else 9
		if fr.is_empty() or fr[1] != release or not is_equal_approx(float(s.visual.hit), g.t):
			failures += 1
			print("MISSING exact native release at actual hit S", skill + 1)
		if skill == 1:
			g.t += 0.2
			OB.mf_step(op, s, test_kind, 0.2)
			for state in ["idle", "run"]:
				var recovery: Array = OB._mf_frame(op, s, kd, state, 0.0)
				if recovery.is_empty() or recovery[0] != load("res://scripts/art.gd").tex("op_mon3tr_native_s2"):
					failures += 1
					print("MISSING S2 native recovery in ", state)
			g.t += 2.0
			for state in ["idle", "run"]:
				var resting: Array = OB._mf_frame(op, s, kd, state, 0.0)
				if resting.is_empty() or resting[0] != load("res://scripts/art.gd").tex("op_mon3tr_native_idle"):
					failures += 1
					print("MISSING S2 native rest in ", state)
	print("MON3TR FX failures=", failures)
	op = null
	g.queue_free()
	g = null
	await get_tree().process_frame
	get_tree().quit.call_deferred(0 if failures == 0 else 1)
