extends Node
const Ch = preload("res://scripts/characters/character.gd")
const Op = preload("res://scripts/characters/data_operator.gd")
const NM = preload("res://scripts/characters/native_motion.gd")
const Contract = preload("res://scripts/characters/operator_contract.gd")
const Irene = preload("res://scripts/characters/blocks/seg_irene.gd")
class ClockOp extends "res://scripts/characters/data_operator.gd":
	var attacks := 0
	var casts := 0
	func _release() -> void: attacks += 1
	func _release_skill() -> void: casts += 1
var g
var checks := 0
var failures := 0
func ok(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.00001
func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var approved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data_ops/approved_attack_rhythm.json"))
	var gallery = load("res://scripts/gallery.gd").new()
	for id in approved:
		var expected: Dictionary = approved[id]
		for slot in Ch.load_def(id).sprites.values():
			if slot is Dictionary and slot.has("attack_timing"):
				ok(Contract.valid_attack_timing(slot), "%s every timed variant is valid" % id)
		var form: Dictionary = gallery._sprite_form("attack",Ch.load_def(id).sprites.attack,12.0,true)
		ok(form.frame_durations == expected.times, "%s gallery shares approved rhythm" % id)
		for rate in [1.0, 2.0, 4.0, 8.0]:
			var o = ClockOp.new(g, Ch.load_def(id).duplicate(true))
			o.pos = g.ppos
			o.cd = float(expected.cycle)/rate
			o.start_attack(o.pos+Vector2(80,0))
			var spec: Dictionary = o.sprite_spec("attack")
			var timing: Dictionary = spec.get("attack_timing", {})
			ok(timing.has("frame_durations"), "%s approved timeline" % id)
			if timing.is_empty(): continue
			var duration := maxf(0.03, minf(float(expected.duration), float(expected.cycle)/rate*float(timing.active_ratio)))
			ok(near(o.attack_dur,duration), "%s x%s duration compresses" % [id,rate])
			ok(near(o.attack_fire_at,float(expected.fire)*duration/float(expected.duration)), "%s x%s release scales" % [id,rate])
			if rate == 1.0:
				ok(near(o.attack_dur,float(expected.duration)) and near(o.attack_fire_at,float(expected.fire)), "%s approved baseline" % id)
			# Tick the real action clock: no early / duplicate hit, including a skill takeover.
			var release_at: float=o.attack_fire_at
			for tick in int(ceil(duration*60))+3:
				o.follow(1.0/60.0,o.pos)
				if float(tick+1)/60.0 < release_at-0.000001:
					ok(o.attacks==0, "%s no early event" % id)
			ok(o.attacks==1 and o.fire_t<0.0, "%s exactly one attack event" % id)
			if id=="irene":
				ok(near(Irene._h3_stage_gap(o,o.B.attack), (2.0/12.0)*duration/float(expected.duration)), "Irene follow-up scales with its attack")
			if id=="lumen":
				o.cd=float(expected.cycle)/rate
				o.start_attack(o.pos+Vector2(80,0),0.5,0.25,"attack_beam")
				ok(o.attack_phased and near(o.attack_dur,duration) and near(o.attack_fire_at,release_at), "Lumen empowered beam keeps attack rhythm")
				o.cd=float(expected.cycle)/rate
				o.start_attack(o.pos+Vector2(80,0))
			# Every frame midpoint must map to the same approved pose after compression.
			var elapsed := 0.0
			for f in expected.times.size():
				var mid: float = (elapsed + float(expected.times[f])*0.5)*duration/float(expected.duration)
				o.attack_t = duration-mid
				o.anim_kind = "attack"
				var raw: Dictionary = o._anim_state_raw()
				var kk: float = float(expected.duration)/duration   # 动画倍率超过 atkspeed/anim_k_cap（3）后隔帧抽取：不超前、落后不超过一个步长，出手帧本身在出手后一定显示
				var step_f: float = maxf(1.0, kk/3.0)
				if kk <= 3.0 + 0.0001:
					ok(int(raw.frame)==f, "%s x%s frame %s" % [id,rate,f])
				else:
					ok(int(raw.frame)<=f and float(f-int(raw.frame))<=ceil(step_f)+1.0, "%s x%s frame %s skips within step" % [id,rate,f])
				# A stale native clip must not overwrite the authoritative pose.
				o.native_motion = {"clip":"attack","t":mid,"from":0}
				var shown: Dictionary = NM.state(o,raw)
				if kk <= 3.0 + 0.0001:
					ok(int(shown.frame)==f, "%s x%s native frame %s" % [id,rate,f])
				else:
					ok(int(shown.frame)==int(raw.frame), "%s x%s native frame %s follows raw" % [id,rate,f])
				elapsed += float(expected.times[f])
			# Completed attack must not linger over idle.
			o.attack_t=0.0
			o.anim_kind="idle"
			var idle: Dictionary=o._anim_state_raw()
			ok(NM.state(o,idle).kind=="idle", "%s no lingering recovery" % id)
			# Moving after release: with a move_attack strip (docs/128) the recovery keeps playing as the running
			# variant (character._move_swap, covered by move_attack_test); without one it yields to run. Logical clock unchanged.
			o.attack_t=duration*0.1
			o.mv=100.0
			# hover_attack（悬浮移动，浊心斯卡蒂，docs/140）：移动时照播不让
			ok(o.act_anim_yield() == (o.anim_tex("move_" + o.act_anim) == null and not o.def.get("sprites", {}).get("hover_attack", false) == true), "%s moving recovery yields unless a move_attack strip plays" % id)
			var before: float=o.attack_t
			o.anim_kind="run"
			NM.state(o,o._anim_state_raw())
			ok(o.attack_t==before, "%s presentation does not advance logic" % id)
			# A new skill action is independent of attack compression and stale native tails.
			o._start_action("skill",o.pos+Vector2(80,0),0.6,0.3,"skill")
			ok(not o.attack_phased, "%s skill does not inherit attack clock" % id)
			if NM.enabled(o):
				ok(str(o.native_motion.get("clip",""))!="attack", "%s skill clears previous attack clip" % id)
			o.cancel_skill_action()
			ok(o.attack_t==0.0 and o.fire_t<0.0 and o.native_motion.is_empty() and not o.attack_phased, "%s cancel clears action and display" % id)
			o.cd=float(expected.cycle)/rate
			o.start_attack(o.pos+Vector2(80,0))
			var attacks_before: int=o.attacks
			var casts_before: int=o.casts
			o._start_action("skill",o.pos+Vector2(80,0),0.6,0.3,"skill")
			for tick in 120: o.follow(1.0/60.0,o.pos)
			ok(o.attacks==attacks_before and o.casts==casts_before+1, "%s skill replaces pending attack exactly once" % id)
	# Malformed timing data must be rejected before a run.
	var invalid: Dictionary=Ch.load_def("skadi").sprites.attack.duplicate(true)
	invalid.attack_timing.frame_durations[0] = -1.0
	ok(not Contract.valid_attack_timing(invalid), "negative pose duration rejected")
	invalid=Ch.load_def("skadi").sprites.attack.duplicate(true)
	invalid.attack_timing.frame_durations[0] += 0.01
	ok(not Contract.valid_attack_timing(invalid), "mismatched event boundary rejected")
	gallery.free()
	# 真实射击路径不能在出手时截掉高攻速下保留的收势。
	var shooter = Op.new(g,Ch.load_def("exusiai").duplicate(true))
	shooter.pos=g.ppos
	shooter.cd=0.35/8.0
	shooter.start_attack(shooter.pos+Vector2(80,0))
	var hit_at: float=shooter.attack_fire_at+0.00001
	shooter.cd -= hit_at
	shooter.follow(hit_at,shooter.pos)
	ok(near(shooter.attack_t,shooter.attack_dur-hit_at),"Exusiai real release preserves recovery floor")
	for rate in [1.0,4.0,8.0]:
		var swordswoman = Op.new(g,Ch.load_def("irene").duplicate(true))
		swordswoman.pos=g.ppos
		swordswoman.taken.append("retrial")
		swordswoman.cd=float(approved.irene.cycle)/rate
		swordswoman.start_attack(swordswoman.pos+Vector2(80,0))
		ok(swordswoman.act_anim=="attack_retrial", "Irene retrial owns its full action window")
		var scale: float=swordswoman.attack_dur/0.62
		for stab in 3:
			var at: float=(0.125+stab/6.0)*scale+0.000001
			var got_f: int=swordswoman.attack_phase_frame(12,2,at,"attack_retrial")
			if 0.62/swordswoman.attack_dur <= 3.0+0.0001:
				ok(got_f==2+stab*2,"Irene each stab matches its pose")
			else:
				ok(got_f<=2+stab*2 and got_f>=2,"Irene each stab matches its pose (skips beyond anim_k_cap)")
		for tick in int(ceil(swordswoman.attack_dur*60)):
			Irene._h3_stage_tick(swordswoman,swordswoman.hw.ir,1.0/60.0)
			swordswoman.follow(1.0/60.0,swordswoman.pos)
		ok(swordswoman.hw.ir.st_i==3 and swordswoman.hw.ir.st_t<0.0,"Irene real third stab completes within action")
	var dasher = ClockOp.new(g,Ch.load_def("texas").duplicate(true))
	dasher.pos=g.ppos
	dasher.cd=float(approved.texas.cycle)
	dasher.start_attack(dasher.pos+Vector2(80,0))
	for elapsed in [0.30,0.34,0.36]:
		dasher.attack_t=dasher.attack_dur-elapsed
		dasher.tx["dash"]={"b":{},"t":elapsed-dasher.attack_fire_at,"dur":0.24,"hold":0.0}
		var during: int=dasher.anim_state().frame
		dasher.tx.erase("dash")
		ok(dasher.anim_state().frame==during,"Texas dash ending cannot rewind the attack pose")
	for rate in [4.0,8.0]:
		dasher.cd=float(approved.texas.cycle)/rate
		dasher.start_attack(dasher.pos+Vector2(80,0))
		dasher.attack_t=0.0
		dasher.tx["dash"]={"b":{},"t":0.1,"dur":0.24,"hold":0.0,"attack_pose":true}
		ok(dasher.anim_state().frame==7,"Texas same-round dash holds final pose after compressed recovery")
		dasher.tx.dash.attack_pose=false
		ok(dasher.anim_state().frame<7,"Texas independent dash does not inherit old attack pose")
	dasher.tx.erase("dash")
	print("ATTACK RHYTHM %d checks, %d failed" % [checks,failures])
	get_tree().quit(1 if failures else 0)
