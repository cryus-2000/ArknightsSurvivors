extends SubViewport
## 着色器预热（docs/50 §27，10-25 用户「等能渲染到稳定 60 帧之后再正式进入游戏主界面」）：
## 启动页盖着标题页的那段时间里，在一块 64×64 的离屏视口里把对局 / 图鉴会用到的着色器各画几帧——
## 兼容渲染器（桌面 GL / 网页 WebGL）在第一次画某个着色器 / 粒子处理材质时才编译，以前就落在进局后最初几帧、第一次放技能、第一次开图鉴时。
## 画的东西：光学全屏 pass、景深、后期、受光保护、磨砂玻璃、横条、加色混合、点光源受光，加光学 GPU 粒子的四种处理材质
## （爆开 / 环境盒 / 环境球 / 发射点贴图，与 render/optical_particles.gd 同一份构造）。
## 一帧只加一项（一次全加，桌面实测一帧卡 2.7 秒，启动页进度停住），全部画过再多画 HOLD 帧后自己释放；视口不挂到屏幕上，看不见。

const HOLD := 3
const OP = preload("res://scripts/render/optical_particles.gd")
const SHADERS := ["res://shaders/optical.gdshader", "res://shaders/dof.gdshader", "res://shaders/post.gdshader",
	"res://shaders/actor_light.gdshader", "res://shaders/ui_glass.gdshader", "res://shaders/ui_band.gdshader"]

var steps: Array = []        # 待加的项（Callable）
var total := 0
var _hold := HOLD
var _tex: Texture2D
var _op
var _x := 0.0


func _ready() -> void:
	size = Vector2i(64, 64)
	disable_3d = true
	transparent_bg = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var px := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	px.fill(Color.WHITE)
	_tex = ImageTexture.create_from_image(px)
	for path in SHADERS:
		if ResourceLoader.exists(path):
			steps.append(_add_shader.bind(path))
	steps.append(_add_blend_light)
	for k in 4:
		steps.append(_add_particles.bind(k))
	total = steps.size()


## 进度 0–1（启动页显示用）
func progress() -> float:
	return 1.0 - (steps.size() + _hold * 0.25) / (total + HOLD * 0.25)


func _process(_delta: float) -> void:
	if not steps.is_empty():
		(steps.pop_front() as Callable).call()
		return
	_hold -= 1
	if _hold <= 0:
		queue_free()


func _add_shader(path: String) -> void:
	var r := TextureRect.new()
	r.texture = _tex
	r.position = Vector2(_x, 0)
	r.size = Vector2(8, 8)
	var m := ShaderMaterial.new()
	m.shader = load(path)
	r.material = m
	add_child(r)
	_x += 8.0


func _add_blend_light() -> void:
	var add := Sprite2D.new()   # 加色混合（对局 fx_add 层）
	add.texture = _tex
	add.position = Vector2(4, 20)
	var am := CanvasItemMaterial.new()
	am.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.material = am
	add_child(add)
	var lit := Sprite2D.new()   # 点光源受光（灯火 / 商人灯 / 骑士暖光都是 PointLight2D）
	lit.texture = _tex
	lit.position = Vector2(16, 20)
	add_child(lit)
	var L := PointLight2D.new()
	L.texture = _tex
	L.texture_scale = 8.0
	L.position = Vector2(16, 20)
	add_child(L)


## 光学粒子的四种处理材质：0 爆开（碎屑 / 体液 / 火星 / 命中三档）、1 环境盒（孢子）、2 环境球（余烬）、3 发射点贴图（拖尾 / 怪物碎开）
func _add_particles(kind: int) -> void:
	if _op == null:
		_op = OP.new()
		add_child(_op)
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_op.px_tex = ImageTexture.create_from_image(img)
		_op.glow_parent = Node2D.new()
		_op.glow_parent.position = Vector2(32, 44)
		add_child(_op.glow_parent)
	var gp: Node2D = _op.glow_parent
	var p: GPUParticles2D
	match kind:
		0:
			p = _op._one_shot(gp, 6, 0.35)
			p.process_material = _op._burst_mat(Vector2(60, 160), 260.0, Vector2.ZERO, 0.35)
		1:
			p = _op._ambient(gp, 8, 1.0, Color.WHITE)
			var sm: ParticleProcessMaterial = p.process_material
			sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			sm.emission_box_extents = Vector3(16, 16, 0)
		2:
			p = _op._ambient(gp, 8, 1.0, Color.WHITE)
			var em: ParticleProcessMaterial = p.process_material
			em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			em.emission_sphere_radius = 10.0
		_:
			_op._setup_trails()
			p = _op.trails
	p.visible = true
	p.emitting = true
