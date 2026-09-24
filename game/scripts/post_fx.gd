## 全屏后期层（layer 6，在 HUD 之下）：辉光 / 水下滤镜 / 亮度 / 受伤红边。开关与强度来自 Cfg，每帧同步。
extends CanvasLayer

var rect: ColorRect
var mat: ShaderMaterial
var hurt := 0.0        # 由 game.gd 写入
var t := 0.0


func _ready() -> void:
	layer = 6
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/post.gdshader")
	rect.material = mat
	add_child(rect)


func _process(delta: float) -> void:
	t += delta
	mat.set_shader_parameter("time", t)
	mat.set_shader_parameter("bloom", 0.38 if Cfg.bloom else 0.0)
	mat.set_shader_parameter("filter_on", 1.0 if Cfg.water_filter else 0.0)
	mat.set_shader_parameter("brightness", Cfg.brightness)
	mat.set_shader_parameter("hurt", hurt)
	# 三项全关时整层隐藏，省一次全屏采样
	rect.visible = Cfg.bloom or Cfg.water_filter or absf(Cfg.brightness - 1.0) > 0.01 or hurt > 0.001
