## 光学观感原型（10-23，协调人单 / 用户参照 build/ui_ref/look_ref_cave_1023.webp，docs/50 §25）：一个全屏 pass（shaders/optical.gdshader）
## 在 HUD 之下取代 post_fx + dof：像素格（格子锁世界坐标）、灯火光池、调色 LUT、只从发光体散出的柔和辉光、暗角。
## 开关：balance render/optical（缺省 0 = 关）；g.optical_on 每帧由这里写，world / look 据此打开朝灯亮线、敌人发光点、荧光颗粒。纯画面，不进模拟。
extends CanvasLayer

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")

var g
var rect: ColorRect
var mat: ShaderMaterial
var force := -1        # --opticalab 同局轮换用：-1 = 按 balance，0 / 1 = 强制关 / 开
var glow_layer: CanvasLayer   # 发光层（layer 1，跟随镜头）：敌人发光点、荧光颗粒；不受 CanvasModulate 环境暗色与灯光影响
var glow_node: Node2D
var particles   # render/optical_particles.gd：击杀碎屑 / 荧光孢子 / 灯火余烬 / 命中迸溅
## ① 低分辨率世界层（render/optical_lowres，缺省开）：另开一个与主视口共享 World2D 的 SubViewport，按「1 像素 = 2 世界像素」
## （镜头 100% 时 = 1 美术像素）渲染世界画布，最近邻放大铺在 layer −1；主视口剔除世界层（可见层 2），只画高清干员层与界面。
## 镜头平移：低分辨率画布的平移取整数，余下的小数在放大后的贴图上补（亚像素补偿，滚动不顿挫）
const VIS_LO := 2           # 世界画布的可见层位（第 2 位）
var lo_vp: SubViewport
var lo_layer: CanvasLayer
var lo_rect: TextureRect
var op_node: Node2D         # 高清干员层（可见层 1，主视口画；squad.cv 合批画布在它的 draw 回调里临时改指到这里）
var _lo_on := false
var _was_on := false
## 发光颜色语言（10-23 用户定，同日按原作改：原作海嗣发光以青蓝为主）：每类一组 render/optical_col_<类>_h / _s / _v（色相 0–1）。
##   enemy 海嗣本体发光点（眼睛 / 核心 / 发光器官）原作青蓝，不再取各怪 ecol / 帧条亮色；elite 精英同色相更亮（并多一处发光点、大一号）；
##   boss 专属暖色；danger「危险」洋红偏深红：敌方攻击预警、敌方弹幕与拖尾，horde_h 黑潮（缩圈开始后 1.5 秒内渐变）往正红偏，紫色调下可读；
##   env 环境（孢子、地面荧光斑、怪死后体液）暗青灰，比海嗣明显更暗、更低饱和，退到背景；lamp 我方灯火余烬琥珀暖橙；
##   loot 经验结晶光晕与掉落淡金白。干员技能保留原作色（不经过这里）
var col_env := Color(0.34, 0.42, 0.42)
var col_enemy := Color(0.3, 0.75, 1.0)
var col_danger := Color(1.0, 0.15, 0.4)
var col_elite := Color(1.0, 0.45, 0.6)
var col_boss := Color(1.0, 0.4, 0.15)
var col_lamp := Color(1.0, 0.62, 0.25)
var col_loot := Color(1.0, 0.95, 0.75)
var _tide_k := 0.0


func _hsv(key: String, h: float, s: float, v: float) -> Color:
	return Color.from_hsv(Bal.v("render/optical_col_%s_h" % key, h), Bal.v("render/optical_col_%s_s" % key, s), Bal.v("render/optical_col_%s_v" % key, v))


func _update_cols(dt: float) -> void:
	_tide_k = move_toward(_tide_k, 1.0 if g.zone_state > 0 else 0.0, dt / 1.5)
	col_env = _hsv("env", 0.5, 0.2, 0.42)
	col_lamp = _hsv("lamp", 0.075, 0.75, 1.0)
	col_loot = _hsv("loot", 0.13, 0.25, 1.0)
	col_boss = _hsv("boss", 0.05, 0.85, 1.0)
	var eh: float = Bal.v("render/optical_col_enemy_h", 0.55)
	col_enemy = Color.from_hsv(eh, Bal.v("render/optical_col_enemy_s", 0.7), Bal.v("render/optical_col_enemy_v", 1.0))
	col_elite = Color.from_hsv(eh, Bal.v("render/optical_col_elite_s", 0.35), Bal.v("render/optical_col_elite_v", 1.0))
	var dh: float = fposmod(lerpf(Bal.v("render/optical_col_danger_h", 0.95), Bal.v("render/optical_col_horde_h", 1.0), _tide_k), 1.0)
	col_danger = Color.from_hsv(dh, Bal.v("render/optical_col_danger_s", 0.85), Bal.v("render/optical_col_danger_v", 1.0))


## 某只怪的本体发光色：Boss 专属暖色、精英更亮、普通怪统一海嗣青蓝
func enemy_glow(e: Dictionary) -> Color:
	if e.get("boss", false):
		return col_boss
	if e.get("elite", false):
		return col_elite
	return col_enemy


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
		lo_layer = CanvasLayer.new()
		lo_layer.layer = -1
		lo_layer.visible = false
		g.add_child(lo_layer)
		lo_vp = SubViewport.new()
		lo_vp.world_2d = g.get_viewport().world_2d
		lo_vp.transparent_bg = false
		lo_vp.canvas_cull_mask = VIS_LO
		lo_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		lo_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		lo_layer.add_child(lo_vp)
		lo_rect = TextureRect.new()
		lo_rect.texture = lo_vp.get_texture()
		lo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lo_rect.stretch_mode = TextureRect.STRETCH_SCALE
		lo_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lo_layer.add_child(lo_rect)
		op_node = Node2D.new()
		op_node.z_index = 1
		op_node.visible = false
		op_node.draw.connect(_draw_ops)
		g.get_parent().add_child.call_deferred(op_node)   # 挂在 game 节点外面：game 在主视口里被剔除时，子节点会一起被剔除
		particles = preload("res://scripts/render/optical_particles.gd").new()
		add_child(particles)
		particles.setup(g, g, glow_node)


## 低分辨率层开 / 关：世界节点的可见层在 1 ↔ 2 之间切，主视口剔除第 2 位；灯光与环境色两边都要（1 | 2）
func _set_lo(on: bool) -> void:
	_lo_on = on
	if not on and g.has_method("_apply_zoom"):
		g._apply_zoom()   # 关掉时镜头缩放回到设置里的「战斗画面缩放」
	g.optical_lo = on
	# 10-23 用户：高清干员层「果然还是怪」、干员不再按站位前后遮挡 → 缺省干员也进低分辨率层（与怪物同一像素格、同一次 y 排序）
	g.optical_ops_hi = on and Bal.v("render/optical_ops_hi", 1.0) > 0.0
	lo_layer.visible = on
	op_node.visible = g.optical_ops_hi
	lo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	g.get_viewport().set_canvas_cull_mask_bit(VIS_LO - 1, not on)
	var lay: int = VIS_LO if on else 1
	g.visibility_layer = lay
	for c in g.get_children():
		if c == op_node or not (c is CanvasItem):
			continue
		(c as CanvasItem).visibility_layer = (1 | VIS_LO) if (c is Light2D or c is CanvasModulate) else lay
	if g.material != null:
		op_node.material = g.material   # 白色保护 / 朝灯亮线的角色材质（render/look.make_actor_mat）


## 每帧：整数像素镜头（10-23 用户：「走动时屏幕有点抖」「镜头能不能拉远一点，从像素整数的角度想」）。
## 1 美术像素在窗口上恒占 k 个物理像素（k 为整数）：按窗口实际高度和目标可见高度（桌面 render/optical_view_h 450、手机 360 美术像素）
## 取最接近的整数 k（至少 2），镜头缩放反推成 z = k / (2 × 拉伸倍率)；720p 窗口 k = 2（同现在），1080p k = 2（视野 1.5 倍），1440p k = 3。
## 低分辨率画布固定 1 像素 = 1 美术像素（= 2 世界像素），只在整格上平移；剩下的小数换算成整数物理像素摆在放大后的贴图上，
## 世界层、高清干员层、界面三者用同一套取整，平移时不再互相错开 1 像素来回跳
var view_k := 2
func _lo_step() -> void:
	var vp: Viewport = g.get_viewport()
	var vs: Vector2 = vp.get_visible_rect().size
	var sx: float = maxf(0.01, vp.get_final_transform().x.x)   # 窗口物理像素 / 设计单位
	var target: float = Bal.v("render/optical_view_h_phone", 360.0) if Cfg.phone_ui() else Bal.v("render/optical_view_h", 450.0)
	view_k = maxi(2, roundi(vs.y * sx / target))
	var zw: float = view_k / (2.0 * sx)
	if g.cam != null and absf(g.cam.zoom.x - zw) > 0.0001:
		g.cam.zoom = Vector2(zw, zw)
	var xf: Transform2D = vp.get_canvas_transform()
	var z: float = xf.x.x   # 本帧实际生效的镜头缩放（改了缩放的那一帧还是旧值，下一帧对齐）
	var cellw: float = 2.0 * z   # 1 个低分辨率像素 = 多少设计单位
	var lsz := Vector2i(ceili(vs.x / cellw) + 3, ceili(vs.y / cellw) + 3)
	if lo_vp.size != lsz:
		lo_vp.size = lsz
	var lo_off: Vector2 = (xf.origin / cellw).floor() + Vector2.ONE
	lo_vp.canvas_transform = Transform2D(Vector2(0.5, 0), Vector2(0, 0.5), lo_off)
	var rp: Vector2 = xf.origin - lo_off * cellw
	lo_rect.position = (rp * sx).round() / sx
	lo_rect.size = Vector2(lsz) * cellw
	op_node.queue_redraw()


## 高清干员层：按脚底 y 排序画干员本体与额外身体；合批画布临时改指到 op_node
func _draw_ops() -> void:
	var sq = g.squad
	if sq == null:
		return
	var bc = sq.cv
	var old = bc.g
	bc.g = op_node
	g.world.draw_target = op_node
	var ops: Array = []
	for o in sq.ops:
		if o.pos != Vector2.INF:
			ops.append(o)
	ops.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	if Cfg.dev_args().has("--opticaldbg") and Engine.get_process_frames() % 60 == 0:
		print("OPTICAL ops=%d in_tree=%s vis=%s layer=%d parent=%s" % [ops.size(), op_node.is_inside_tree(), op_node.is_visible_in_tree(), op_node.visibility_layer, op_node.get_parent()])
	for o in ops:
		o.draw_body()
		for xb in o.extra_bodies():
			o.draw_extra(xb)
	bc.flush()
	bc.g = old
	g.world.draw_target = null


## 发光层：上一帧世界绘制排好的敌人发光点（孢子 / 余烬 / 体液 / 迸溅是同层的 GPUParticles2D）+ ⑧ 投射物拖尾
func _draw_glow() -> void:
	_draw_ground_glow()
	for p in g.glow_cur:
		glow_node.draw_rect(Rect2(p[0], Vector2(p[1], p[1])), p[2])
	_draw_loot()
	if Bal.v("render/optical_trail", 1.0) > 0.0:
		_draw_trails(g.bullets, false)
		_draw_trails(g.ebullets, true)


## ⑧ 投射物发光像素拖尾：每颗弹沿速度反方向 5 个 2 px 像素、由亮到灭，吸附到 2 世界像素格；
## 我方取弹体颜色（没有就青白），敌方一律危险色（颜色语言）。最多画 300 颗
func _draw_trails(list: Array, enemy: bool) -> void:
	var n := 0
	for b in list:
		if n >= 300:
			break
		var v: Vector2 = b.get("vel", Vector2.ZERO)
		var sp := v.length()
		if sp < 40.0:
			continue
		n += 1
		var col: Color
		if enemy:
			col = col_danger   # 颜色语言：敌弹一律危险色（不再取各怪 ecol）；弹芯另点一颗亮像素
			var c0: Vector2 = ((b.pos + Vector2(0, -16)) / 2.0).floor() * 2.0
			glow_node.draw_rect(Rect2(c0 - Vector2(1, 1), Vector2(4, 4)), Color(col.r, col.g, col.b, 0.9))
		else:
			var bc = b.get("col")
			col = bc if bc is Color else Color(0.7, 0.95, 1.0)
		var dirn: Vector2 = -v / sp
		var gap: float = clampf(sp * 0.012, 3.0, 9.0)
		var p0: Vector2 = b.pos
		for i in range(1, 6):
			var q: Vector2 = p0 + dirn * gap * i
			q = (q / 2.0).floor() * 2.0
			var a: float = 0.75 * (1.0 - i / 6.0)
			glow_node.draw_rect(Rect2(q, Vector2(2, 2)), Color(col.r, col.g, col.b, a))


## 地面荧光斑（环境色）：按 64 世界像素一格哈希，约 render/optical_ground_glow（缺省 0.06）的格子有一颗 2 px 斑，各自慢慢明灭。
## 只看格坐标，镜头怎么走都固定在地上；只画镜头内（约 500 格）
func _draw_ground_glow() -> void:
	var dens: float = Bal.v("render/optical_ground_glow", 0.06)
	if dens <= 0.0 or g.cam == null:
		return
	var vs: Vector2 = g.get_viewport().get_visible_rect().size / g.cam.zoom
	var c: Vector2 = g.cam.get_screen_center_position()
	var x0: int = floori((c.x - vs.x * 0.5) / 64.0)
	var y0: int = floori((c.y - vs.y * 0.5) / 64.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	for cy in range(y0, y0 + ceili(vs.y / 64.0) + 1):
		for cx in range(x0, x0 + ceili(vs.x / 64.0) + 1):
			var hsh: int = (cx * 73856093) ^ (cy * 19349663)
			var r: float = float(hsh & 1023) / 1024.0
			if r >= dens:
				continue
			var ox: float = float((hsh >> 10) & 31) * 2.0
			var oy: float = float((hsh >> 15) & 31) * 2.0
			var a: float = 0.25 + 0.45 * (0.5 + 0.5 * sin(t * 0.7 + float((hsh >> 20) & 63)))
			glow_node.draw_rect(Rect2(Vector2(cx * 64.0 + ox, cy * 64.0 + oy), Vector2(2, 2)), Color(col_env.r, col_env.g, col_env.b, a))


## 经验结晶与掉落：中心一颗淡金白发光像素（辉光由全屏 pass 的发光门限散出）
func _draw_loot() -> void:
	var n := 0
	for gm in g.gems:
		if n >= 400:
			break
		if gm.get("dead", false):
			continue
		n += 1
		var q: Vector2 = ((gm.pos + Vector2(0, -4)) / 2.0).floor() * 2.0
		glow_node.draw_rect(Rect2(q, Vector2(2, 2)), Color(col_loot.r, col_loot.g, col_loot.b, 0.85))


func wanted() -> bool:
	if force >= 0:
		return force == 1
	return Bal.v("render/optical", 0.0) > 0.0


func _process(_dt: float) -> void:
	if g == null:
		return
	_update_cols(_dt)
	var on := wanted() and DisplayServer.get_name() != "headless"
	g.optical_on = on
	visible = on
	glow_layer.visible = on
	var lo_want: bool = on and Bal.v("render/optical_lowres", 1.0) > 0.0 and lo_vp != null
	if lo_want != _lo_on:
		_set_lo(lo_want)
	if _lo_on:
		_lo_step()
	g.glow_cur = g.glow_next
	g.glow_next = []
	if particles != null:
		if on != _was_on:
			particles.set_active(on)
		if on and g.cam != null and g.lamp_light != null:
			particles.step(g.cam.get_screen_center_position(), g.lamp_light.global_position, col_env, col_lamp)
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
	mat.set_shader_parameter("pixel_on", 0.0 if _lo_on else Bal.v("render/optical_pixel", 1.0))   # 低分辨率层开着时世界本来就是 2 px 格，干员要保持高清，不再按格取样
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
	mat.set_shader_parameter("sea_amt", Bal.v("render/optical_sea", 0.55))
	mat.set_shader_parameter("caustics", Bal.v("render/optical_caustics", 0.02))
	mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	if Cfg.dev_args().has("--opticaldbg") and Engine.get_process_frames() % 60 == 0:
		print("OPTICAL cell=%.2f origin=%s lamp=%s r=%.1f scale=%s" % [g.PX * k, str(xf * Vector2.ZERO), str(xf * L.global_position) if L != null else "-", 64.0 * (L.texture_scale if L != null else 0.0) * k, str(L.texture_scale if L != null else 0.0)])
	if g.post != null:
		mat.set_shader_parameter("hurt", g.post.hurt)
		mat.set_shader_parameter("desat", g.post.desat)
