extends Node2D
## Disposable isolated visual study. No game simulation, damage or production resources are changed.
## Baseline reproduces the large-effect 10+10+3 GPU burst, not the complete in-game compositing pass.
var mode := "compare"
var outdir := ""
var count := 1
var capture := false
var particles_only := false
var groups: Array = []
var clocks: Array[float] = []
var elapsed := 0.0
var tick := 0
var last_usec := 0
var samples: Array[float] = []
var splash: Texture2D
var point: Texture2D
var base_color := Color.WHITE
var ink := Color(0.23, 0.29, 0.3)
const PERIOD := 2.4

func ramp(colors: Array, stops: PackedFloat32Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = stops
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.get_slice("=", 1)
		if arg.begins_with("--out="): outdir = arg.substr(6)
		if arg.begins_with("--count="): count = int(arg.get_slice("=", 1))
		if arg == "--capture": capture = true
		if arg == "--particles-only": particles_only = true
	AudioServer.set_bus_mute(0, true)
	var root := ProjectSettings.globalize_path("res://").path_join("../..")
	var im := Image.load_from_file(root.path_join("art/incoming/optical_fx/fx_eyja_lava_splash@2x.png"))
	assert(im != null and im.get_width() == 480 and im.get_height() == 56)
	var best := -1.0
	for y in range(56):
		for x in range(80):
			var c := im.get_pixel(x, y)
			var score := c.v * (0.3 + c.s)
			if c.a >= 0.6 and score > best:
				best = score
				base_color = Color.from_hsv(c.h, clampf(c.s, 0.25, 0.9), 1.0) if c.s > 0.12 else Color.WHITE
	splash = ImageTexture.create_from_image(im)
	var px := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	px.fill(Color.WHITE)
	point = ImageTexture.create_from_image(px)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var modes: Array = ["base", "trial"] if mode == "compare" else [mode]
	for side in modes.size():
		for i in count:
			var center := Vector2(240 + side * 480, 310) if mode == "compare" else Vector2(480, 300)
			if count > 1: center += Vector2((i % 4 - 1.5) * 140, (i / 4 - 1) * 110)
			var group: Array = []
			for kind in 3:
				group.append(make_particle(modes[side] == "trial", kind, center, i))
			groups.append(group)
			clocks.append(-float(i) * 0.031 - 0.25)
	last_usec = Time.get_ticks_usec()
	print("TRIAL_READY mode=", mode, " groups=", groups.size(), " particles_per_burst=23")

func make_particle(proposed: bool, kind: int, center: Vector2, index: int) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = [10, 10, 3][kind]
	p.lifetime = [0.7, 0.7, 0.9][kind]
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.emitting = false
	p.texture = point
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = center
	p.use_fixed_seed = true
	p.seed = 7201 + index * 37 + kind
	p.fixed_fps = 60
	p.visibility_rect = Rect2(-500, -500, 1000, 1000)
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, -1, 0)
	m.spread = [180.0, 70.0, 180.0][kind]
	m.initial_velocity_min = [60.0, 15.0, 8.0][kind]
	m.initial_velocity_max = [190.0, 50.0, 30.0][kind]
	m.damping_min = [126.0, 28.0, 14.0][kind]
	m.damping_max = [180.0, 40.0, 20.0][kind]
	m.gravity = [Vector3(0, 160, 0), Vector3(0, -30, 0), Vector3(0, -18, 0)][kind]
	m.color_ramp = ramp([Color.WHITE, Color(1,1,1,0.9), Color(0.5,0.5,0.5,0)], PackedFloat32Array([0,0.55,1]))
	p.modulate = base_color if kind < 2 else Color(0.16,0.17,0.2,0.55)
	if proposed:
		# Same 23 particles and three emitters; material identity comes from trajectories and cooling.
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = [10.0, 16.0, 12.0][kind]
		p.lifetime = [0.7, 0.7, 0.9][kind]
		m.spread = [68.0, 30.0, 60.0][kind]
		m.initial_velocity_min = [65.0, 26.0, 10.0][kind]
		m.initial_velocity_max = [165.0, 80.0, 28.0][kind]
		m.damping_min = [12.0, 18.0, 8.0][kind]
		m.damping_max = [25.0, 30.0, 16.0][kind]
		m.gravity = [Vector3(0, 360, 0), Vector3(0, -24, 0), Vector3(0, -16, 0)][kind]
		p.modulate = Color.WHITE
		if kind == 0:
			m.color_ramp = ramp([Color(1,.63,.22),Color(.65,.22,.08),Color(.21,.16,.13),Color(.14,.14,.13,0)],PackedFloat32Array([0,.18,.68,1]))
		elif kind == 1:
			m.color_ramp = ramp([Color(1,.86,.46),Color(1,.46,.12),Color(.46,.18,.08),Color(.18,.13,.10,0)],PackedFloat32Array([0,.2,.65,1]))
		else:
			m.color_ramp = ramp([Color(.22,.23,.23,0),Color(.30,.29,.26,.7),Color(.18,.21,.22,0)],PackedFloat32Array([0,.25,1]))
	p.process_material = m
	add_child(p)
	return p

func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	if elapsed > 2.0 and not capture: samples.append(float(now - last_usec) / 1000.0)
	last_usec = now
	elapsed += dt
	for i in clocks.size():
		var old := clocks[i]
		clocks[i] += dt
		if old < 0 and clocks[i] >= 0:
			for p in groups[i]: p.restart()
		if clocks[i] >= PERIOD: clocks[i] -= PERIOD
		if old > clocks[i]:
			for p in groups[i]: p.restart()
	queue_redraw()
	if capture:
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png(outdir.path_join("frame_%04d.png" % tick))
		assert(err == OK)
		tick += 1
		if tick >= 150: get_tree().quit()
	elif elapsed > 8.0:
		samples.sort()
		var mean := 0.0
		for v in samples: mean += v
		mean /= max(1, samples.size())
		print("PERF ", JSON.stringify({"mode":mode,"groups":count,"frames":samples.size(),"mean_ms":mean,"p95_ms":samples[int(samples.size()*.95)],"p99_ms":samples[int(samples.size()*.99)],"gpu":RenderingServer.get_video_adapter_name()}))
		get_tree().quit()

func _draw() -> void:
	draw_rect(Rect2(0,0,960,540), Color(.055,.082,.095))
	for x in range(0,960,32):
		for y in range(0,540,32):
			var n := posmod(x*13+y*31,7)
			draw_rect(Rect2(x+4,y+4,2+n,2),Color(.09,.12,.13))
	if mode == "compare": draw_line(Vector2(480,0),Vector2(480,540),ink,2)
	for i in groups.size():
		var center: Vector2 = groups[i][0].position
		draw_line(center+Vector2(-75,28),center+Vector2(75,28),Color(.14,.19,.20),2)
		var age := clocks[i]
		if not particles_only and age >= 0 and age < 6.0/18.0:
			var fr := mini(5,int(age*18))
			draw_texture_rect_region(splash,Rect2(center-Vector2(80,56),Vector2(160,112)),Rect2(fr*80,0,80,56))
