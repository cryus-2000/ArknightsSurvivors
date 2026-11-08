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
var sv: SubViewport
var out_dir := ""


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var cdir := ""
	var lamp_png := ""
	for s in a:
		if s.begins_with("--pv3d_cards="):
			cdir = s.substr(13)
		elif s.begins_with("--pv3d_out="):
			out_dir = s.substr(11)
		elif s.begins_with("--pv3d_lamp="):
			lamp_png = s.substr(12)
	var i := 0
	while FileAccess.file_exists(cdir + "/c%d.png" % i):
		faces.append(ImageTexture.create_from_image(Image.load_from_file(cdir + "/c%d.png" % i)))
		i += 1
	back_tex = ImageTexture.create_from_image(Image.load_from_file(cdir + "/_back.png"))
	print("PV3D faces=", faces.size())
	# 固定 1920×1080 离屏视口自己存帧：测试窗口按最小化启动，--write-movie 会跟着窗口录成 1280×720
	sv = SubViewport.new()
	sv.size = Vector2i(1920, 1080)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_4X
	sv.own_world_3d = true
	root.add_child(sv)
	root3 = Node3D.new()
	sv.add_child(root3)
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
	_jellies()
	hero = _card(5)   # 斯卡蒂（小队成员）
	root3.add_child(hero)
	hero.visible = false


func _env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.22, 0.26)   # 11-08 对齐官方水月 PV：亮灰蓝雾、去饱和
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.6, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.38, 0.44)
	env.fog_density = 0.045
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.045
	env.volumetric_fog_albedo = Color(0.85, 0.92, 0.98)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 40.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.25
	env.adjustment_saturation = 0.55
	we.environment = env
	root3.add_child(we)


func _lights(lamp_png: String) -> void:
	lamp = OmniLight3D.new()
	lamp.light_color = Color(0.85, 0.93, 1.0)
	lamp.light_energy = 3.0
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
	var rim := DirectionalLight3D.new()   # 从水面打下来的顶光，体积雾里出光束
	rim.light_color = Color(0.92, 0.97, 1.0)
	rim.light_energy = 2.4
	rim.rotation_degrees = Vector3(-72, 25, 0)
	rim.light_volumetric_fog_energy = 4.0
	rim.shadow_enabled = true
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
	pm.gravity = Vector3(0, 0.12, 0)   # 气泡上浮
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.12
	pm.direction = Vector3(0.1, 1, 0.05)
	pm.spread = 60.0
	pm.scale_min = 0.4
	pm.scale_max = 1.4
	snow.process_material = pm
	var q := SphereMesh.new()   # 圆气泡（方面片离镜头近了是白方块）
	q.radius = 0.012
	q.height = 0.024
	q.radial_segments = 8
	q.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.96, 1.0, 0.45)
	q.material = m
	snow.draw_pass_1 = q
	snow.fixed_fps = 60
	root3.add_child(snow)


const SEABED_SHADER := """
shader_type spatial;
render_mode diffuse_lambert;
uniform sampler2D hmap : repeat_enable;
uniform sampler2D caus : repeat_enable;
uniform vec3 sand = vec3(0.30, 0.34, 0.35);
uniform float caus_k = 1.1;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = texture(hmap, wpos.xz * 0.035).r;
	float d = clamp((length(wpos.xz - vec2(0.0, -1.0)) - 3.5) / 10.0, 0.0, 1.0);   // 镜头前平、远处起伏成沙丘
	VERTEX.y += (h - 0.5) * 2.4 * d + texture(hmap, wpos.xz * 0.4).r * 0.06;
	wpos.y = VERTEX.y;
}
void fragment() {
	float g = texture(hmap, wpos.xz * 0.25).r;
	ALBEDO = sand * (0.8 + 0.35 * g);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	// 焦散：两层滚动的胞状噪声取最小值，再压成细亮网纹
	vec2 uv = wpos.xz * 0.09;
	float c1 = texture(caus, uv + vec2(TIME * 0.05, TIME * 0.03)).r;
	float c2 = texture(caus, uv * 1.31 + vec2(-TIME * 0.04, TIME * 0.06)).r;
	float c = pow(1.0 - min(c1, c2), 10.0);
	EMISSION = vec3(0.75, 0.9, 1.0) * c * caus_k;
}
"""

const KELP_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform vec3 col = vec3(0.10, 0.16, 0.16);
uniform float phase = 0.0;
void vertex() {
	float k = UV.y;   // 0 顶 1 底
	float w = (1.0 - k) * (1.0 - k);
	VERTEX.x += sin(TIME * 1.1 + phase + VERTEX.y * 0.9) * 0.35 * w;
	VERTEX.z += cos(TIME * 0.8 + phase) * 0.15 * w;
}
void fragment() {
	float edge = smoothstep(0.0, 0.25, 0.5 - abs(UV.x - 0.5));
	if (edge < 0.05) { discard; }
	ALBEDO = col * (0.7 + 0.5 * (1.0 - UV.y));
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
}
"""

const SURFACE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D caus : repeat_enable;
void fragment() {
	vec2 uv = UV * 18.0;
	float a = texture(caus, uv + vec2(TIME * 0.03, 0.0)).r;
	float b = texture(caus, uv * 0.7 - vec2(0.0, TIME * 0.025)).r;
	float c = pow(1.0 - min(a, b), 5.0);
	float fade = 1.0 - smoothstep(0.15, 0.5, length(UV - vec2(0.5)));
	ALBEDO = vec3(0.55, 0.68, 0.76) * (0.55 + 1.6 * c) * (0.35 + 0.65 * fade);
}
"""

var kelps: Array = []


func _noise_tex(cellular: bool, seed: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.noise = n
	return t


func _floor() -> void:
	## 海底（11-08 用户：官方 PV 背景是海底）：起伏沙床 + 焦散光纹、礁石、摆动的海草、头顶发亮的水面
	var hm := _noise_tex(false, 3, 0.012)
	var cs := _noise_tex(true, 9, 0.02)
	floor_m = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	pm.subdivide_width = 260
	pm.subdivide_depth = 260
	floor_m.mesh = pm
	var sh := Shader.new()
	sh.code = SEABED_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("hmap", hm)
	m.set_shader_parameter("caus", cs)
	floor_m.material_override = m
	floor_m.position = Vector3(0, -1.0, -10.0)
	root3.add_child(floor_m)
	# 礁石：压扁、歪斜的球，远处成剪影
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var rock_m := StandardMaterial3D.new()
	rock_m.albedo_color = Color(0.13, 0.16, 0.17)
	rock_m.roughness = 0.95
	for i in 16:
		var r := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 9
		sm.rings = 6
		r.mesh = sm
		r.material_override = rock_m
		var big := rng.randf() < 0.35
		var sc := rng.randf_range(2.0, 4.5) if big else rng.randf_range(0.4, 1.3)
		r.scale = Vector3(sc * rng.randf_range(0.8, 1.6), sc * rng.randf_range(0.5, 1.1), sc * rng.randf_range(0.8, 1.4))
		var side := -1.0 if i % 2 == 0 else 1.0
		r.position = Vector3(side * rng.randf_range(3.0, 14.0), -1.0, rng.randf_range(-22.0, -3.0) if big else rng.randf_range(-12.0, -2.0))
		r.rotation_degrees = Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 360), rng.randf_range(-20, 20))
		root3.add_child(r)
	# 海草：长条面片成簇，顶部随水流摆
	var ksh := Shader.new()
	ksh.code = KELP_SHADER
	for i in 46:
		var k := MeshInstance3D.new()
		var q := QuadMesh.new()
		var hgt := rng.randf_range(1.6, 4.8)
		q.size = Vector2(rng.randf_range(0.07, 0.15), hgt)
		q.subdivide_depth = 12
		k.mesh = q
		var km := ShaderMaterial.new()
		km.shader = ksh
		km.set_shader_parameter("phase", rng.randf_range(0, 6.28))
		km.set_shader_parameter("col", Vector3(0.09, 0.15, 0.15) * rng.randf_range(0.8, 1.3))
		k.material_override = km
		var cl := Vector3((-1.0 if i % 2 == 0 else 1.0) * rng.randf_range(2.6, 11.0), 0, rng.randf_range(-16.0, -1.5))
		k.position = cl + Vector3(rng.randf_range(-0.6, 0.6), -1.0 + hgt / 2.0, rng.randf_range(-0.6, 0.6))
		k.rotation_degrees.y = rng.randf_range(0, 180)
		root3.add_child(k)
	# 水面：头顶一大片，发亮的波纹
	var surf := MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2(120, 120)
	surf.mesh = sp
	var ssh := Shader.new()
	ssh.code = SURFACE_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = ssh
	smat.set_shader_parameter("caus", cs)
	surf.material_override = smat
	surf.position = Vector3(0, 9.0, -12.0)
	root3.add_child(surf)


func _card(n: int) -> Node3D:
	var c := Node3D.new()
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(CW, CH, 0.03)
	box.mesh = bm
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.82, 0.86, 0.9)   # 冷银边
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


var jellies: Array = []


func _jellies() -> void:
	## 水月的水母（game/art/fx/fx_mizuki_jelly@2x.png 第 0 帧，像素放大）在雾里慢慢上浮
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/fx/fx_mizuki_jelly@2x.png"))
	if img == null:
		return
	var tex := ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, img.get_height(), img.get_height())))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 9:
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.pixel_size = rng.randf_range(0.02, 0.038)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false
		sp.modulate = Color(0.9, 1.15, 1.7, 0.9)
		root3.add_child(sp)
		jellies.append({"n": sp, "p0": Vector3(rng.randf_range(-6, 6), rng.randf_range(-1.5, 4.0), rng.randf_range(-9, -2)), "v": rng.randf_range(0.08, 0.2), "ph": rng.randf_range(0, 6.28)})


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _process(_d: float) -> bool:
	if f >= 2 and out_dir != "":   # 上一帧画好的：存成第 f-2 帧（前两帧预热）
		sv.get_texture().get_image().save_png(out_dir + "/f%08d.png" % (f - 2))
	var t := maxf(0.0, (f - 1) / FPS)
	f += 1
	if t > DUR + 1.0 / FPS:
		quit()
		return true
	var shot := 0 if t < 2 * BAR else (1 if t < 4 * BAR else 2)
	for o in fall:
		o.n.visible = shot == 0
	for o in row:
		o.n.visible = shot >= 1
	hero.visible = shot == 2
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
			lamp.light_energy = 3.0 + 14.0 * flash
			# 末一拍压暗，切到实机
			env.tonemap_exposure = 1.05 * (1.0 + _ease((lt - (3 * BAR - 0.35)) / 0.35) * 2.5)
	if lamp_spr:
		lamp_spr.position = lamp.position
	for j in jellies:
		j.n.position = j.p0 + Vector3(0.15 * sin(t * 0.7 + j.ph), j.v * t + 0.06 * sin(t * 2.2 + j.ph), 0)
	return false
