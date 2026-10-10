## 全屏后期层（layer 6，在 HUD 之下）：辉光 / 水下滤镜 / 亮度 / 受伤红边。开关与强度来自 Cfg，每帧同步。
extends CanvasLayer

const Bal = preload("res://scripts/core/balance.gd")

var rect: ColorRect
var mat: ShaderMaterial
var hurt := 0.0        # 由 game.gd 写入
var crowd := 0.0       # 特效密度 0–1（render/world.gd 写入）：后期满屏特效时辉光减半，免得整片过曝
var desat := 0.0       # 0..1 去色（最终 Boss 击破演出，screens/boss_intro.gd 写入；低画质恒 0）
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
	mat.set_shader_parameter("bloom", 0.3 * (1.0 - 0.5 * crowd) if Cfg.bloom else 0.0)
	mat.set_shader_parameter("filter_on", 1.0 if Cfg.water_filter else 0.0)
	# 全局亮度 = 玩家设置 × render/ambient_gain（界面与美术 10-01：整体略提亮；乘在最后，低灯和正常灯的明暗比例不变）
	var br: float = Cfg.brightness * Bal.v("render/ambient_gain", 1.0)
	mat.set_shader_parameter("brightness", br)
	mat.set_shader_parameter("hurt", hurt)
	mat.set_shader_parameter("desat", desat)
	# 全关时整层隐藏，省一次全屏采样
	rect.visible = Cfg.bloom or Cfg.water_filter or absf(br - 1.0) > 0.01 or hurt > 0.001 or desat > 0.001
