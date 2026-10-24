extends Control
## 标题页背景·深海水母（docs/67 §13，10-24 用户定：Codex 47-C 构图 + 方向二「青光航标」精修）。
## 场景着色器（shaders/title_deep.gdshader）画进 1280×720 的 SubViewport，最多每秒更新 30 次；这里把它铺满屏幕（保持比例裁切）
## 并叠屏幕空间压暗（title_deep_view.gdshader）。减少动态效果：只画一次静帧。标题被别的界面整屏盖住时（paused）不再更新。
## 原来的蓝眼泪沙滩（title_bg.gd）不再挂在标题页上。

const HZ := 30.0
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
	_vp.size = Vector2i(1280, 720)
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(1280, 720)
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/title_deep.gdshader")
	_mat.set_shader_parameter("image", preload("res://art/ui/title_deep/scene.png"))
	_mat.set_shader_parameter("glow", preload("res://art/ui/title_deep/glow.png"))
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
		_mat.set_shader_parameter("time", fmod(_clock, 20.0))
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

