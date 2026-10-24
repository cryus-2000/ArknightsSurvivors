extends Control
## 标题页背景·深海水母（docs/67 §13，10-24 用户定：Codex 47-C 构图 + 方向二「青光航标」；v2 按游戏像素精度、水母会游）。
## 场景着色器（shaders/title_deep.gdshader）画进 428×240 的 SubViewport（1 美术像素 = 3 逻辑像素），最多每秒更新 30 次；
## 这里把它最近邻铺满屏幕（保持比例裁切），叠屏幕空间压暗（title_deep_view.gdshader）。
## 减少动态效果：只画一次静帧。标题被别的界面整屏盖住时（paused）不再更新。素材由 art/incoming/title_jelly_1024/bake_v2.py 烘焙。

const HZ := 30.0
const GRID := Vector2i(428, 240)
const DIR := "res://art/ui/title_deep/"
## 三只水母图层的位置 / 伞顶锚点 / 主轴 / 伞体长度（美术像素；bake_v2.py 重烘后照它打印的参数改这里）
const JELLY := [
	{"rect": [196, 47, 135, 146], "anchor": [287.56, 57.51], "axis": [-0.5593, 0.829], "bell": 42.8},
	{"rect": [165, 132, 34, 52], "anchor": [184.57, 131.74], "axis": [-0.1498, 0.9887], "bell": 14.71},
	{"rect": [339, 60, 24, 36], "anchor": [348.42, 61.52], "axis": [-0.0499, 0.9988], "bell": 10.03},
]
const GLOW_PAD := 12.0
const SWAY := [3.0, 2.0, 1.5]   # 触须末端横摆幅度（美术像素）：主水母 / 近处小水母 / 远处小水母
var paused := false
var fade := 0.0               # 开场黑幕 0–1（title.gd 每帧给）
var corner := 0.0             # 手机版式：右下压暗（集结出发挪到右下）
var _vp: SubViewport
var _mat: ShaderMaterial
var _view: TextureRect
var _clock := 0.0
var _acc := 0.0
var _still := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = GRID
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(GRID)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/title_deep.gdshader")
	_mat.set_shader_parameter("bg", load(DIR + "bg.png"))
	for i in 3:
		var m: Dictionary = JELLY[i]
		_mat.set_shader_parameter("j%d" % i, load(DIR + "jelly_%d.png" % i))
		_mat.set_shader_parameter("g%d" % i, load(DIR + "jglow_%d.png" % i))
		var r: Array = m.rect
		_mat.set_shader_parameter("rect%d" % i, Vector4(r[0], r[1], r[2], r[3]))
		_mat.set_shader_parameter("pose%d" % i, Vector4(m.anchor[0], m.anchor[1], m.bell, SWAY[i]))
		_mat.set_shader_parameter("axis%d" % i, Vector2(m.axis[0], m.axis[1]))
	_mat.set_shader_parameter("glow_pad", GLOW_PAD)
	rect.material = _mat
	_vp.add_child(rect)
	_view = TextureRect.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.texture = _vp.get_texture()
	var vm := ShaderMaterial.new()
	vm.shader = preload("res://shaders/title_deep_view.gdshader")
	_view.material = vm
	add_child(_view)


func _process(delta: float) -> void:
	var vm := _view.material as ShaderMaterial
	vm.set_shader_parameter("fade", fade)
	vm.set_shader_parameter("br", corner)
	var still := 1.0 if Cfg.reduce_motion else 0.0
	if still != _still:
		_still = still
		_mat.set_shader_parameter("still", still)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if paused or still > 0.5:
		return
	_clock += delta
	_acc += delta
	if _acc >= 1.0 / HZ - 0.002:
		_acc = 0.0
		_mat.set_shader_parameter("time", fmod(_clock, 7200.0))   # 两小时取一次模，长挂机浮点精度不变差
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
