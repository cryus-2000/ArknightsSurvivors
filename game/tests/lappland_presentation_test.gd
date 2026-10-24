extends Node
const Ch = preload("res://scripts/characters/character.gd")
const Op = preload("res://scripts/characters/data_operator.gd")
const Wave = preload("res://scripts/characters/blocks/seg_skadi.gd")
const NM = preload("res://scripts/characters/native_motion.gd")
const Fx = preload("res://scripts/characters/blocks/ob_fx.gd")
class CanvasProbe extends RefCounted:
	var frames: Array = []
	var alphas: Array = []
	func draw_set_transform(_pos, _ang, _scale): pass
	func draw_texture_rect_region(tx, _rect, region, _col):
		frames.append(int(region.position.x / (tx.get_width()/4)))
		alphas.append(_col.a)
class WaveView extends RefCounted:
	var hw: Dictionary
	var g
	var cv
var checks := 0
var failures := 0
var configured_waves := 0
func ok(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func check_config(v):
	if v is Dictionary:
		if v.get("shape")=="wave" and v.get("proj")=="proj_lappland_sword":
			configured_waves+=1
			ok(v.get("proj_hold")==1 and v.get("proj_front")==true, "all sword variants use approved playback and layer")
		for child in v.values(): check_config(child)
	elif v is Array:
		for child in v: check_config(child)
func _ready():
	var g = load("res://game.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var o = Op.new(g, Ch.load_def("lappland").duplicate(true))
	o.pos = g.ppos
	check_config(o.def)
	ok(configured_waves==9, "base, skills and progression sword variants covered")
	var b = {"from":"self", "basis":"atk", "mult":1.0, "dist":220.0, "speed":500.0,
		"w":60.0, "cap":9, "fan":[-18,0,18], "fan_once":true, "proj":"proj_lappland_sword", "proj_hold":1,
		"release_pose":{"slot":"throw", "skill":2, "cycle":0.6}}
	o.s_t[2] = 8.0
	o.sq_i = 2
	o.sq_ph = 2
	Wave.hw_wave_start(o,b)
	ok(o.hw.waves.size()==3, "one event launches three blades")
	o.hw.waves[0].hit[123] = true
	ok(o.hw.waves[2].hit.has(123), "fan shares hit registry")
	var probe = CanvasProbe.new()
	var view = WaveView.new()
	view.hw = o.hw
	view.g = g
	view.cv = probe
	for age in [0.0,0.04,0.07,0.2,0.4]:
		for global_time in [0.0,0.1,13.7]:
			g.t = global_time
			for w in o.hw.waves: w.dist = age*500.0
			probe.frames.clear()
			Wave.hw_draw_waves(view)
			ok(probe.frames.size()==3 and probe.frames.all(func(fr):return fr==(0 if age<0.0625 else 1)), "blade holds local flight pose age=%s clock=%s" % [age,global_time])
	ok(probe.alphas.all(func(a): return is_equal_approx(a,1.0)), "flight never fades before terminal frames")
	b["proj_front"]=true
	probe.frames.clear()
	Wave.hw_draw_waves(view)
	ok(probe.frames.is_empty(), "front blades are excluded from floor pass")
	Wave.hw_draw_waves(view,true)
	ok(probe.frames.size()==3, "front blades drawn once in over pass")
	var fallback = {"kind":"idle","frame":0}
	ok(NM.state(o,fallback).get("frame")==3, "actual wave event starts at release pose")
	o.act_kind="attack"
	o.act_anim="attack"
	NM.tick(o,0.15)
	var pose_before: Dictionary = NM.state(o,fallback)
	NM.started(o)
	ok(NM.state(o,fallback).frame==pose_before.frame, "ordinary attack does not restart skill event clock")
	o.mv=100.0
	ok(NM.state(o,fallback).kind=="run", "movement overrides throw pose")
	o.anim_kind="throw"
	o.run_ph=4.25
	o.anim_t=0.0
	NM.tick(o,0.1)
	var phase: float=o.run_ph
	ok(phase>4.25, "run phase advances while attack slot is underneath")
	o.mv=200.0
	NM.tick(o,0.1)
	ok(o.run_ph-phase > phase-4.25, "run phase follows movement speed")
	phase=o.run_ph
	NM.started(o)
	ok(NM.state(o,fallback).frame==int(phase)%int(o.sprite_spec("run").frames), "ordinary attack preserves running frame")
	ok(NM.state(o,{"kind":"run","frame":-1}).frame==int(o.run_ph)%int(o.sprite_spec("run").frames), "sequence run uses same continuous phase as attack override")
	o.mv=0.0
	ok(NM.state(o,fallback).kind=="throw", "stopping resumes current event")
	o.sq_ph=1
	ok(NM.state(o,{"kind":"skill","frame":6}).frame==6, "wave does not interrupt skill startup")
	o.sq_ph=2
	NM.tick(o,0.6)
	ok(NM.state(o,fallback).get("frame")==2, "between events holds prepared pose without fake release")
	o.s_t[2]=0.0
	NM.tick(o,0.01)
	ok(NM.state(o,fallback)==fallback, "skill expiration yields body")
	for w in o.hw.waves:
		w.dist=219.0
		w.pos=o.pos+w.dir*219.0
	o.pfx.clear()
	Wave._hw_waves(o,0.01)
	ok(o.hw.waves.is_empty(), "range completion removes damaging waves")
	ok(o.pfx.size()==3, "range completion emits visual tails")
	for f in o.pfx:
		ok(not f.floor, "terminal tails stay on front layer")
		probe.frames.clear()
		Fx.fx_draw(probe,g,f,1.0)
		f.life-=0.07
		Fx.fx_draw(probe,g,f,1.0)
		ok(probe.frames==[2,3], "tail plays only terminal frames")
	# 新一轮先播起手，不继承旧事件；站定后下一轮实际发射才恢复掷刃。
	o.s_t[2]=8.0
	o.sq_ph=1
	Wave.hw_wave_start(o,b)
	ok(not o.native_motion.has("wave_pose"), "new startup never inherits old event")
	o.hw.waves.clear()
	o.sq_ph=2
	o.face=1.0
	var enemy = g.spawner.spawn_enemy("stone",o.pos-Vector2(120,0))
	enemy.hp=1000000.0
	g.enemies_sys.build_grid()
	b["aim"]="nearest"
	b["aim_r"]=260.0
	Wave.hw_wave_start(o,b)
	ok(cos(o.native_motion.wave_pose.angle)<0.0 and o.face==1.0, "event records opposite aim without changing logic facing")
	ok(NM.state(o,fallback).flip != o.sprite_mirror("throw"), "release pose faces opposite target")
	o.act_kind="skill"
	o.attack_t=0.5
	var casting = {"kind":"skill","frame":5}
	ok(NM.state(o,casting)==casting, "another skill takes visual priority")
	NM.tick(o,0.01)
	ok(not o.native_motion.has("wave_pose"), "another skill clears obsolete event")
	# 走真实 follow/update，检查 JSON 中 S3 的实际事件驱动，而非只测人工构造事件。
	var live=Op.new(g,Ch.load_def("lappland").duplicate(true))
	live.pos=g.ppos
	live.elite=2
	live.refresh_stats()
	live.start_skill(enemy.pos,2)
	var events:=0
	for i in 180:
		live.follow(1.0/60.0,live.pos)
		live.update(1.0/60.0)
		var event: Dictionary=live.native_motion.get("wave_pose",{})
		if not event.is_empty() and is_zero_approx(event.elapsed):
			events+=1
			ok(live.anim_state().kind=="throw" and live.anim_state().frame==3, "live S3 wave and throw release coincide")
	ok(events>=2, "live S3 tick actually drives body events")
	print("LAPPLAND PRESENTATION %d checks, %d failed" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
