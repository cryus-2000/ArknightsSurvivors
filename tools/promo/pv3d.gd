extends SceneTree
## PV 3D 开头（11-08，参考「回声行动」PV 开头的实物卡 + 暗场 + 浅景深）：游戏里的招募卡 / 升级卡当成金边实体卡，
## 深海暗场里漂浮下落 → 低机位贴着海床，一排卡依次立起 → 74 小节重拍一张卡砸到镜头前，镜头推进卡面。
## 时长 = battle2 第 70–77 小节（7 小节 = 11.507 秒），77 小节接 PV 的终结技钩子。
##   godot --path game --write-movie <目录>/f.png --fixed-fps 60 --resolution 1920x1080 -s <本文件绝对路径> -- --pv3d_cards=<卡面目录> --pv3d_lamp=<灯 png>
## 卡面目录：c0.png … cN.png（tools/promo 从实机录像里按原尺寸抠的招募卡 / 升级卡），_back.png 卡背。

const FPS := 60.0
const BAR := 4.0 * 60.0 / 145.99
const DUR := 7.0 * BAR
const CW := 1.0
const CH := 1.405

var cam: Camera3D
var attrs: CameraAttributesPractical
var env: Environment
var lamp: OmniLight3D
var lamp_spr: Sprite3D
var faces: Array = []
var back_tex: Texture2D
var fall: Array = []       # 镜头一：漂浮下落的卡 {n, p0, v, r0, w}
var row: Array = []        # 镜头二：一排立起的卡 {n, x, t_up}
var hero: Node3D           # 镜头三：砸到镜头前的那张
var floor_m: MeshInstance3D
var snow: GPUParticles3D
var root3: Node3D
var f := 0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var cdir := ""
	var lamp_png := ""
	for s in a:
		if s.begins_with("--pv3d_cards="):
			cdir = s.substr(13)
		elif s.begins_with("--pv3d_lamp="):
			lamp_png = s.substr(12)
	var i := 0
	while FileAccess.file_exists(cdir + "/c%d.png" % i):
		faces.append(ImageTexture.create_from_image(Image.load_from_file(cdir + "/c%d.png" % i)))
		i += 1
	back_tex = ImageTexture.create_from_image(Image.load_from_file(cdir + "/_back.png"))
	print("PV3D faces=", faces.size())
	root3 = Node3D.new()
	root.add_child(root3)
	_env()
	_lights(lamp_png)
	_snow()
	_floor()
	cam = Camera3D.new()
	cam.fov = 38.0
	attrs = CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_amount = 0.5
	cam.attributes = attrs
	root3.add_child(cam)
	cam.current = true
	_build_fall()
	_build_row()
	hero = _card(5)   # 斯卡蒂（小队成员）
	root3.add_child(hero)
	hero.visible = false


func _env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.006, 0.012, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.16, 0.22)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.03, 0.08, 0.11)
	env.fog_density = 0.035
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.55, 0.7, 0.8)
	env.volumetric_fog_emission = Color(0.0, 0.01, 0.02)
	env.volumetric_fog_length = 40.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.92
	we.environment = env
	root3.add_child(we)


func _lights(lamp_png: String) -> void:
	lamp = OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.68, 0.32)
	lamp.light_energy = 9.0
	lamp.omni_range = 9.0
	lamp.light_volumetric_fog_energy = 2.5
	lamp.shadow_enabled = true
	root3.add_child(lamp)
	if lamp_png != "" and FileAccess.file_exists(lamp_png):
		var img := Image.load_from_file(lamp_png)
		var fw := img.get_height() * 240 / 288
		lamp_spr = Sprite3D.new()
		lamp_spr.texture = ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, fw, img.get_height())))
		lamp_spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		lamp_spr.pixel_size = 0.0022
		lamp_spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lamp_spr.shaded = false
		lamp_spr.modulate = Color(1.6, 1.3, 1.0)
		root3.add_child(lamp_spr)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.8, 0.95)
	rim.light_energy = 1.0
	rim.rotation_degrees = Vector3(-25, 160, 0)
	rim.light_volumetric_fog_energy = 0.6
	root3.add_child(rim)


func _snow() -> void:
	snow = GPUParticles3D.new()
	snow.amount = 1800
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9, 7, 9)
	pm.gravity = Vector3(0, -0.06, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 60.0
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	snow.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.9, 1.0, 0.55)
	q.material = m
	snow.draw_pass_1 = q
	snow.fixed_fps = 60
	root3.add_child(snow)


func _floor() -> void:
	floor_m = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_m.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.006, 0.01, 0.014)
	m.metallic = 0.0
	m.roughness = 0.85
	m.metallic_specular = 0.15
	floor_m.material_override = m
	floor_m.position.y = -1.0
	root3.add_child(floor_m)


func _card(n: int) -> Node3D:
	var c := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(CW, CH, 0.03)
	box.mesh = bm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.78, 0.6, 0.3)
	gold.metallic = 1.0
	gold.roughness = 0.3
	box.material_override = gold
	c.add_child(box)
	for side in [1, -1]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(CW * 0.965, CH * 0.975)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = faces[n % faces.size()] if side == 1 else back_tex
		m.roughness = 0.6 if side == 1 else 0.9
		m.metallic_specular = 0.3 if side == 1 else 0.08
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = 0.8 if side == 1 else 0.18
		q.material_override = m
		q.position.z = 0.0155 * side
		if side == -1:
			q.rotation_degrees.y = 180
		c.add_child(q)
	return c


func _build_fall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 22:
		var c := _card(i)
		root3.add_child(c)
		var p := Vector3(rng.randf_range(-4.5, 4.5), rng.randf_range(-1.0, 5.5), rng.randf_range(-7.0, 1.5))
		fall.append({"n": c, "p0": p, "v": rng.randf_range(0.35, 0.7),
			"r0": Vector3(rng.randf_range(-180, 180), rng.randf_range(-180, 180), rng.randf_range(-180, 180)),
			"w": Vector3(rng.randf_range(-40, 40), rng.randf_range(-70, 70), rng.randf_range(-30, 30))})


func _build_row() -> void:
	for i in 9:
		var c := _card(i)
		root3.add_child(c)
		row.append({"n": c, "x": (i - 4) * 1.22, "t_up": BAR * 2 + 0.25 + i * (BAR / 8.0)})


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _process(_d: float) -> bool:
	var t := f / FPS
	f += 1
	if t > DUR:
		quit()
		return true
	var shot := 0 if t < 2 * BAR else (1 if t < 4 * BAR else 2)
	for o in fall:
		o.n.visible = shot == 0
	for o in row:
		o.n.visible = shot >= 1
	hero.visible = shot == 2
	floor_m.visible = shot >= 1
	if shot == 0:
		# 漂浮下落：镜头缓慢下沉前推，焦点在 4 米
		for o in fall:
			o.n.position = o.p0 + Vector3(0, -o.v * t, 0)
			o.n.rotation_degrees = o.r0 + o.w * t
		var u := t / (2 * BAR)
		cam.position = Vector3(0.2, 2.6 - 0.8 * u, 6.0 - 1.4 * u)
		cam.look_at(Vector3(0, 1.6 - 0.8 * u, -2), Vector3.UP)
		attrs.dof_blur_far_distance = 5.5
		attrs.dof_blur_far_transition = 1.8
		attrs.dof_blur_near_distance = 3.2
		attrs.dof_blur_near_transition = 1.5
		lamp.position = Vector3(-2.3, 2.5, -2.6)
	else:
		# 低机位贴着海床横移；卡依次从平躺立起（八分音符一张）
		var u := (t - 2 * BAR) / (2 * BAR)
		for o in row:
			var k := _ease((t - o.t_up) / 0.28)
			o.n.position = Vector3(o.x, -1.0 + 0.02 + (CH / 2.0) * k, -1.0)
			o.n.rotation_degrees = Vector3(90.0 * (1.0 - k), 0, 0)   # 卡背朝上平躺 → 立起翻出正面
		lamp.position = Vector3(0.6, 0.9, -3.4)
		if shot == 1:
			cam.position = Vector3(-4.2 + 6.0 * u, -0.72, 2.6)
			cam.look_at(Vector3(-2.4 + 6.0 * u, -0.45, -1.0), Vector3.UP)
			attrs.dof_blur_far_distance = 4.0
			attrs.dof_blur_far_transition = 1.4
			attrs.dof_blur_near_distance = 2.0
			attrs.dof_blur_near_transition = 1.0
		else:
			# 74 小节重拍：一张卡从上方砸到镜头前立住，灯火一闪；之后镜头推进卡面
			var lt := t - 4 * BAR
			var dropk := _ease(lt / 0.16)
			hero.position = Vector3(0.0, -1.0 + CH / 2.0 + 2.6 * (1.0 - dropk), 0.9)
			hero.rotation_degrees = Vector3(0, 0, -8.0 * (1.0 - dropk))
			var pk := _ease(maxf(0.0, lt - 0.3) / (3 * BAR - 0.3))
			cam.position = Vector3(0.0, -0.3, 4.6 - 2.05 * pk)
			cam.look_at(hero.position + Vector3(0, 0.08, 0), Vector3.UP)
			var dist := cam.position.distance_to(hero.position)
			attrs.dof_blur_far_distance = dist + 0.5
			attrs.dof_blur_far_transition = 0.9
			attrs.dof_blur_near_distance = maxf(0.05, dist - 0.8)
			attrs.dof_blur_near_transition = 0.6
			var flash := maxf(0.0, 1.0 - lt / 0.35)
			lamp.light_energy = 9.0 + 24.0 * flash
			# 末一拍压暗，切到实机
			env.tonemap_exposure = 1.05 * (1.0 - _ease((lt - (3 * BAR - 0.35)) / 0.35) * 0.85)
	if lamp_spr:
		lamp_spr.position = lamp.position
	return false
