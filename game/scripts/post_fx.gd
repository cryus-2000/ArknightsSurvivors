## 全屏后期层（layer 6，在 HUD 之下）：辉光 / 水下滤镜 / 亮度 / 受伤红边。开关与强度来自 Cfg，每帧同步。
extends CanvasLayer

const Bal = preload("res://scripts/core/balance.gd")
const Look = preload("res://scripts/render/look.gd")

var rect: ColorRect
var mat: ShaderMaterial
var hurt := 0.0        # 由 game.gd 写入
var crowd := 0.0       # 特效密度 0–1（render/world.gd 写入）：后期满屏特效时辉光减半，免得整片过曝
var bloom_cut := 0.5   # crowd = 1 时辉光减掉的比例（render/declutter 的 bloom_cut，world.gd 写入）
var desat := 0.0       # 0..1 去色（最终 Boss 击破演出，screens/boss_intro.gd 写入；低画质恒 0）
var zone_amt := 0.0    # 失色区强度 0..1（拉普兰德 S3「噤声」，ob_summon._mark_draw 每帧写；低画质恒 0）
var zone_c := Vector2(0.5, 0.5)   # 屏幕 uv
var zone_r := 0.0      # uv（按屏幕高）
var zone_hole := Vector3(0.5, 0.5, 0.0)
var t := 0.0
var world := false    # 对局画面（game.gd 在 add_child 前设）：才叠观感曲线
var _curve := false   # 观感曲线开着时整层常显
var crisp := false     # 图鉴打开时（title.gd 写入）：不加辉光与水下滤镜（色差会把浅色终端面板的黑细线染出红绿边），亮度照常


func _ready() -> void:
	layer = 6
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/post.gdshader")
	rect.material = mat
	add_child(rect)
	# 观感预设（render/look，开局读一次）：高光软肩 / 黑位 / 暗部伽马 / 饱和度 / 辉光门槛。
	# 曲线只给对局画面（world = true，game.gd 设）；标题 / 选人 / 图鉴是界面配色（docs/37），只吃亮度
	mat.set_shader_parameter("bloom_threshold", Look.p("bloom_th"))
	if world:
		for k in ["shoulder", "toe", "pivot", "sat"]:
			mat.set_shader_parameter(k, Look.p(k))
		mat.set_shader_parameter("black_pt", Look.p("black"))
		_curve = Look.p("shoulder") > 0.0 or Look.p("black") > 0.0 or Look.p("toe") > 1.001 or absf(Look.p("sat")) > 0.001


func _process(delta: float) -> void:
	t += delta
	mat.set_shader_parameter("time", t)
	mat.set_shader_parameter("bloom", 0.3 * (1.0 - bloom_cut * crowd) if Cfg.bloom and not crisp else 0.0)
	mat.set_shader_parameter("filter_on", 1.0 if Cfg.water_filter and not crisp else 0.0)
	# 全局亮度 = 玩家设置 × render/ambient_gain（界面与美术 10-01：整体略提亮；乘在最后，低灯和正常灯的明暗比例不变）
	var br: float = Cfg.brightness * Bal.v("render/ambient_gain", 1.0)
	mat.set_shader_parameter("brightness", br)
	mat.set_shader_parameter("hurt", hurt)
	mat.set_shader_parameter("desat", desat)
	mat.set_shader_parameter("zone_amt", zone_amt)
	mat.set_shader_parameter("zone_c", zone_c)
	mat.set_shader_parameter("zone_r", zone_r)
	mat.set_shader_parameter("zone_hole", zone_hole)
	# 全关时整层隐藏，省一次全屏采样
	rect.visible = ((Cfg.bloom or Cfg.water_filter) and not crisp) or absf(br - 1.0) > 0.01 or hurt > 0.001 or desat > 0.001 or zone_amt > 0.001 or _curve
	# 图鉴开着时，手机网页 / 苹果 WebKit 不叠后期（不读屏，亮度不乘）：iOS 上这一层会把整屏盖成图鉴中途拷屏时的画面（Cfg.screen_copy_ok）
	if crisp and not Cfg.screen_copy_ok():
		rect.visible = false
