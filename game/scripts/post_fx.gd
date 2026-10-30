## 全屏后期层（layer 6，在 HUD 之下）：辉光 / 水下滤镜 / 亮度 / 受伤红边。开关与强度来自 Cfg，每帧同步。
extends CanvasLayer

const Bal = preload("res://scripts/core/balance.gd")
const Look = preload("res://scripts/render/look.gd")
const A = preload("res://scripts/art.gd")

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
var if_amt := 0.0      # 终结技冲击帧（ult.gd _if_tick 每帧写）：0 关 / 1 开；if_bg / if_fg 底色与剪影色，if_c / if_r 局部圆（uv），if_r = 0 整屏
var if_bg := Color.BLACK
var if_fg := Color.WHITE
var if_c := Vector2(0.5, 0.5)
var if_r := 0.0
var zone_mask: SubViewport
var mask_canvas: Node2D
var mask_game
const MASK_IDLE_SECONDS := 2.0
var _mask_idle := 0.0
var _mask_targets: Array[WeakRef] = []

## 只用友方当前动画帧的透明度遮罩，避免矩形保色区把周围地面也挖出色块。
func refresh_zone_guards(g) -> void:
	mask_game = g
	if zone_amt <= 0.001:
		return
	_mask_idle = 0.0
	if zone_mask == null:
		zone_mask = SubViewport.new()
		zone_mask.world_2d = World2D.new()
		zone_mask.disable_3d = true
		zone_mask.transparent_bg = true
		zone_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(zone_mask)
		mask_canvas = Node2D.new()
		zone_mask.add_child(mask_canvas)
		mask_canvas.draw.connect(_draw_zone_mask)
	zone_mask.size = Vector2i(g.get_viewport().get_visible_rect().size)
	zone_mask.canvas_transform = g.get_viewport().get_canvas_transform()
	zone_mask.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	mask_canvas.queue_redraw()

func _draw_zone_mask() -> void:
	var g = mask_game
	if g == null or not is_instance_valid(g) or g.squad == null:
		return
	# 复用高清干员层的绘制路由：只重画本体与召唤物，不推进动画或玩法。
	var bc = g.squad.cv
	var old = bc.g
	var old_target = g.world.draw_target
	bc.g = mask_canvas
	g.world.draw_target = mask_canvas
	for o in g.squad.ops:
		if o.pos.is_finite():
			o.draw_body()
			for body in o.extra_bodies():
				o.draw_extra(body)
	bc.flush()
	bc.g = old
	g.world.draw_target = old_target
	if g.knight.alive:
		g.knight.draw(mask_canvas)
	var tx: Texture2D = g.sprite.texture
	if tx != null:
		var size := Vector2(float(tx.get_width()) / g.sprite.hframes, tx.get_height())
		var pk: float = g.PX / A.hires_of(tx)
		var sx := -pk if g.sprite.flip_h else pk
		mask_canvas.draw_set_transform(g.sprite.position + g.p_off, g.sprite.rotation + g.p_lean, Vector2(sx * g.p_sq.x, pk * g.p_sq.y))
		mask_canvas.draw_texture_rect_region(tx, Rect2(-size * 0.5 + g.sprite.offset, size), Rect2(Vector2(size.x * g.sprite.frame, 0), size))
		mask_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func apply_zone_guards(target: ShaderMaterial) -> void:
	target.set_shader_parameter("zone_mask_on", zone_mask != null and zone_amt > 0.001)
	if zone_mask != null:
		var tracked := false
		for ref in _mask_targets:
			if ref.get_ref() == target:
				tracked = true
				break
		if not tracked:
			_mask_targets.append(weakref(target))
		target.set_shader_parameter("zone_mask", zone_mask.get_texture())
		if zone_amt <= 0.001:
			zone_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	else:
		target.set_shader_parameter("zone_mask", null)

## 冲击帧参数（普通后期与光学后期共用；平时只写一个 0）
func apply_if(target: ShaderMaterial) -> void:
	target.set_shader_parameter("if_amt", if_amt)
	if if_amt > 0.5:
		target.set_shader_parameter("if_bg", Vector3(if_bg.r, if_bg.g, if_bg.b))
		target.set_shader_parameter("if_fg", Vector3(if_fg.r, if_fg.g, if_fg.b))
		target.set_shader_parameter("if_c", if_c)
		target.set_shader_parameter("if_r", if_r)

func _retire_zone_mask(delta: float) -> void:
	if zone_mask == null:
		return
	if zone_amt > 0.001:
		_mask_idle = 0.0
		return
	_mask_idle += delta
	if _mask_idle < MASK_IDLE_SECONDS:
		return
	# Both optical and ordinary post materials may retain this ViewportTexture.
	# Unbind before deferred destruction; weak references do not retain old scenes.
	for ref in _mask_targets:
		var target = ref.get_ref()
		if target != null:
			target.set_shader_parameter("zone_mask_on", false)
			target.set_shader_parameter("zone_mask", null)
	_mask_targets.clear()
	zone_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	zone_mask.queue_free()
	zone_mask = null
	mask_canvas = null
	mask_game = null

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
	_retire_zone_mask(delta)
	t += delta
	mat.set_shader_parameter("time", t)
	mat.set_shader_parameter("bloom", 0.3 * (1.0 - bloom_cut * crowd) if Cfg.bloom and not crisp else 0.0)
	mat.set_shader_parameter("filter_on", 1.0 if Cfg.water_filter and not crisp else 0.0)
	# 全局亮度 = 玩家设置 × render/ambient_gain（界面与美术 10-01：整体略提亮；乘在最后，低灯和正常灯的明暗比例不变）
	var br: float = Cfg.brightness * Bal.v("render/ambient_gain", 1.05)
	mat.set_shader_parameter("brightness", br)
	mat.set_shader_parameter("hurt", hurt)
	mat.set_shader_parameter("desat", desat)
	mat.set_shader_parameter("zone_amt", zone_amt)
	mat.set_shader_parameter("zone_c", zone_c)
	mat.set_shader_parameter("zone_r", zone_r)
	mat.set_shader_parameter("zone_hole", zone_hole)
	apply_if(mat)
	apply_zone_guards(mat)
	# 全关时整层隐藏，省一次全屏采样
	rect.visible = ((Cfg.bloom or Cfg.water_filter) and not crisp) or absf(br - 1.0) > 0.01 or hurt > 0.001 or desat > 0.001 or zone_amt > 0.001 or _curve or if_amt > 0.5
	# 图鉴开着时，手机网页 / 苹果 WebKit 不叠后期（不读屏，亮度不乘）：iOS 上这一层会把整屏盖成图鉴中途拷屏时的画面（Cfg.screen_copy_ok）
	if crisp and not Cfg.screen_copy_ok():
		rect.visible = false
