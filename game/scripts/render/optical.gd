## 光学观感原型（10-23，协调人单 / 用户参照 build/ui_ref/look_ref_cave_1023.webp，docs/50 §25）：一个全屏 pass（shaders/optical.gdshader）
## 在 HUD 之下取代 post_fx + dof：像素格（格子锁世界坐标）、灯火光池、调色 LUT、只从发光体散出的柔和辉光、暗角。
## 开关：balance render/optical（缺省 0 = 关）；g.optical_on 每帧由这里写，world / look 据此打开朝灯亮线、敌人发光点、荧光颗粒。纯画面，不进模拟。
extends CanvasLayer

const Bal = preload("res://scripts/core/balance.gd")

var g
var rect: ColorRect
var mat: ShaderMaterial
var force := -1        # --opticalab 同局轮换用：-1 = 按 balance，0 / 1 = 强制关 / 开
var glow_layer: CanvasLayer   # 发光层（layer 1，跟随镜头）：敌人发光点、荧光颗粒；不受 CanvasModulate 环境暗色与灯光影响
var glow_node: Node2D
var particles   # render/optical_particles.gd：击杀碎屑 / 荧光孢子 / 灯火余烬 / 命中迸溅
var _was_on := false


func _ready() -> void:
	layer = 6
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/optical.gdshader")
	mat.set_shader_parameter("lut", load("res://shaders/optical_lut.png"))
	rect.material = mat
	add_child(rect)
	visible = false
	glow_layer = CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	glow_layer.visible = false
	glow_node = Node2D.new()
	glow_node.draw.connect(_draw_glow)
	glow_layer.add_child(glow_node)
	call_deferred("_attach_glow")


func _attach_glow() -> void:
	if g != null:
		g.add_child(glow_layer)
		particles = preload("res://scripts/render/optical_particles.gd").new()
		add_child(particles)
		particles.setup(g, g, glow_node)


## 发光层：上一帧世界绘制排好的敌人发光点（孢子 / 余烬 / 体液 / 迸溅是同层的 GPUParticles2D）
func _draw_glow() -> void:
	for p in g.glow_cur:
		glow_node.draw_rect(Rect2(p[0], Vector2(p[1], p[1])), p[2])


func wanted() -> bool:
	if force >= 0:
		return force == 1
	return Bal.v("render/optical", 0.0) > 0.0


func _process(_dt: float) -> void:
	if g == null:
		return
	var on := wanted() and DisplayServer.get_name() != "headless"
	g.optical_on = on
	visible = on
	glow_layer.visible = on
	g.glow_cur = g.glow_next
	g.glow_next = []
	if particles != null:
		if on != _was_on:
			particles.set_active(on)
		if on and g.cam != null and g.lamp_light != null:
			particles.step(g.cam.get_screen_center_position(), g.lamp_light.global_position)
	_was_on = on
	if on:
		glow_node.queue_redraw()
	if g.post != null:
		g.post.visible = not on
	if g.dof_layer != null:
		g.dof_layer.visible = Cfg.dof and not on
	if not on:
		return
	var vp: Viewport = g.get_viewport()
	var xf: Transform2D = vp.get_final_transform() * vp.get_canvas_transform()
	var k: float = xf.get_scale().x
	mat.set_shader_parameter("cell", g.PX * k)
	mat.set_shader_parameter("pixel_on", Bal.v("render/optical_pixel", 1.0))
	mat.set_shader_parameter("grid_origin", xf * Vector2.ZERO)
	var L: PointLight2D = g.lamp_light
	if L != null and L.visible and L.enabled:
		mat.set_shader_parameter("lamp_px", xf * L.global_position)
		mat.set_shader_parameter("lamp_r", 64.0 * L.texture_scale * k * Bal.v("render/optical_pool_r", 0.7))
	else:
		mat.set_shader_parameter("lamp_r", 1.0)
	mat.set_shader_parameter("pool_dark", Bal.v("render/optical_pool_dark", 1.0))
	mat.set_shader_parameter("glow", Bal.v("render/optical_glow", 0.9))
	mat.set_shader_parameter("emissive_th", Bal.v("render/optical_emissive_th", 0.72))
	mat.set_shader_parameter("lut_on", Bal.v("render/optical_lut", 1.0))
	mat.set_shader_parameter("brightness", Cfg.brightness * Bal.v("render/ambient_gain", 1.0))
	if Cfg.dev_args().has("--opticaldbg") and Engine.get_process_frames() % 60 == 0:
		print("OPTICAL cell=%.2f origin=%s lamp=%s r=%.1f scale=%s" % [g.PX * k, str(xf * Vector2.ZERO), str(xf * L.global_position) if L != null else "-", 64.0 * (L.texture_scale if L != null else 0.0) * k, str(L.texture_scale if L != null else 0.0)])
	if g.post != null:
		mat.set_shader_parameter("hurt", g.post.hurt)
		mat.set_shader_parameter("desat", g.post.desat)
