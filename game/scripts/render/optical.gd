## 光学观感原型（10-23，协调人单 / 用户参照 build/ui_ref/look_ref_cave_1023.webp，docs/50 §25）：一个全屏 pass（shaders/optical.gdshader）
## 在 HUD 之下取代 post_fx + dof：像素格（格子锁世界坐标）、灯火光池、调色 LUT、只从发光体散出的柔和辉光、暗角。
## 开关：balance render/optical（10-23 起缺省 1 = 开，画质「低」自动关）；g.optical_on 每帧由这里写，world / look 据此打开朝灯亮线、敌人发光点、荧光颗粒。纯画面，不进模拟。
extends CanvasLayer

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")
const A = preload("res://scripts/art.gd")
const FD = preload("res://scripts/render/frame_dst.gd")

var g
var rect: ColorRect
var mat: ShaderMaterial
var force := -1        # --opticalab 同局轮换用：-1 = 按 balance，0 / 1 = 强制关 / 开
var glow_layer: CanvasLayer   # 发光层（layer 1，跟随镜头）：敌人发光点、荧光颗粒；不受 CanvasModulate 环境暗色与灯光影响
var glow_node: Node2D
var particles   # render/optical_particles.gd：击杀碎屑 / 荧光孢子 / 灯火余烬 / 命中迸溅
var grains      # render/fx_grains.gd：像素粒子模板（刀光第四版等，docs/136）
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
var _pa_last := false   # GPU 粒子上次 set_active 的值（光学开关 + --stackab 第 2 位）
## --stackab（docs/50 §26，仅测试）：同局逐层关闭的位掩码，只关画面。1 CPU 颗粒（fx_grains 全关，调用方退回非粒子画法）、2 GPU 粒子、
## 4 特效动态照明、8 发光层、16 低分辨率世界层、32 整套光学观感、64 GPU 粒子爆发隔一次发一次（近似池子减半）
var ab_mask := 0
var auto_mask := 0   # 画质自动档逐级降（game._auto_quality，docs/50 §28）：同 ab_mask 的位，正常游戏掉帧时才非 0
## 发光颜色语言（10-23 用户定，同日按原作改：原作海嗣发光以青蓝为主）：每类一组 render/optical_col_<类>_h / _s / _v（色相 0–1）。
##   enemy 海嗣本体发光点（眼睛 / 核心 / 发光器官）原作青蓝，不再取各怪 ecol / 帧条亮色；elite 精英同色相更亮（并多一处发光点、大一号）；
##   boss 专属暖色；danger「危险」洋红偏深红：敌方攻击预警、敌方弹幕与拖尾，horde_h 黑潮（缩圈开始后 1.5 秒内渐变）往正红偏，紫色调下可读；
##   env 环境（孢子、地面荧光斑、怪死后体液）暗青灰，比海嗣明显更暗、更低饱和，退到背景；lamp 我方灯火余烬琥珀暖橙；
##   loot 经验结晶光晕与掉落淡金白。干员技能保留原作色（不经过这里）
var col_env := Color(0.34, 0.42, 0.42)
var col_enemy := Color(0.3, 0.75, 1.0)
var col_danger := Color(1.0, 0.15, 0.4)
## 敌弹色（10-24 用户「怪物的子弹能改成蓝色吗」，docs/139 §6.7）：敌弹本体 / 弹芯 / 拖尾 / 描边 / 地面临时光从危险色里拆出来，
## render/optical_col_ebullet_h / _s / _v；攻击预警仍用危险色。光学观感开着时把粉 / 紫弹体贴图换成这个色相（旧开关 render/ebullet_recolor 10-29 已删）
var col_ebullet := Color(0.3, 0.85, 1.0)
const EB_RECOLOR := ["ebullet", "proj_nova", "proj_floater_nerve"]
var _eb_orig := {}
var _eb_hue := -1.0
var col_elite := Color(1.0, 0.45, 0.6)
var col_boss := Color(1.0, 0.4, 0.15)
var col_lamp := Color(1.0, 0.62, 0.25)
var col_loot := Color(1.0, 0.95, 0.75)
var _tide_k := 0.0
## 特效处理第 1 步（10-23 用户定）：
##   ① 压阶帧条（render/optical_fxq，缺省 1）：tools/optical_fx_quant.py 离线生成 art/incoming/optical_fx/<名>.png（3 阶 alpha、每色相 3 阶明度，
##      形状与色相不变；维什戴尔炮击的落点标记 / 地面红盘帧掏成描边）。开着时把 g.tex 里同名贴图换成压阶版（每帧最多 FXQ_PER_FRAME 条，开局几帧换完），关掉换回
##   ② 亮度上限（render/optical_fx_cap，缺省 1.4）：特效绘制色的通道上限（FD.col_cap，原来常见 ×2–2.8 的过曝色）；
##      全屏发光总量预算（render/optical_glow_budget，缺省 0.06 = 屏幕平均发光度）：超出按比例压辉光、压亮部（着色器）
const FXQ_PER_FRAME := 16
var fx1 := true   # 特效处理第 1 步总开关（render/optical_fx1，缺省 1；0 = 回到上一版，前后对照用）
var fx1_force := -1   # --fx1ab 同局轮换用：-1 = 按 balance，0 / 1 = 强制关 / 开
## ⑥ 特效动态照明（10-23）：发光特效 / 投射物 / 爆炸在地面投临时光，不用 Light2D 节点（兼容渲染器下每盏灯重画受光物体）：
## 每帧在 CPU 上挑出最亮的 render/optical_dl_max（缺省 12）个，作为数组传给全屏着色器，和灯火光池同一处算（柔和半径、随寿命衰减）
const DL_MAX := 12
var _dl_pos := PackedVector4Array()
var _dl_col := PackedVector4Array()
var _fxsz := {}   # 帧条名 → 1x 帧高（世界像素换算用）
var _fxq_names: Array = []
var _fxq_orig := {}
var _fxq_i := 0
var _fxq_miss := {}


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
	col_ebullet = Color.from_hsv(Bal.v("render/optical_col_ebullet_h", 0.54), Bal.v("render/optical_col_ebullet_s", 0.8), Bal.v("render/optical_col_ebullet_v", 1.0))


## ⑥ 动态照明：候选 = 一次性帧条特效（按剩余寿命衰减、半径随帧高）+ 我方弹 + 敌弹（危险色、弱）；按亮度取前 N 个
func _dyn_lights(xf: Transform2D, k: float) -> void:
	var nmax: int = mini(DL_MAX, int(Bal.v("render/optical_dl_max", 12.0))) if fx1 and ((ab_mask | auto_mask) & 4) == 0 else 0
	var cand: Array = []
	if nmax > 0:
		var cc: Vector2 = g.cam.get_screen_center_position() if g.cam != null else g.ppos
		var vr := Rect2(cc - Vector2(900, 560), Vector2(1800, 1120))
		for f in g.fx:   # 一遍扫完：帧条特效 + 刀光（docs/50 §26：原来两遍、每项两次取 kind 字符串）
			var kd: String = str(f.get("kind", ""))
			if kd == "marc":
				# 刀光：挥刀瞬间短暂打亮脚下与附近怪（刀光寿命前段 ≈ 0.08–0.12 秒）
				var lf: float = float(f.life) / maxf(0.001, float(f.max))
				if lf < 0.35:
					continue
				var mo = g.squad.get_op(str(f.get("op", ""))) if g.squad != null else null
				var mp: Vector2 = (mo.pos + f.get("off", Vector2.ZERO)) if mo != null and mo.pos != Vector2.INF else f.pos
				if not vr.has_point(mp):
					continue
				cand.append([0.55 + 0.25 * int(f.tier), mp + Vector2.from_angle(float(f.ang)) * float(f.r) * 0.45, float(f.r) * 0.9, f.col])
				continue
			if kd != "sprite" and kd != "anim" and kd != "grain_light":
				continue
			var p: Vector2 = f.get("pos", Vector2.INF)
			if not vr.has_point(p):
				continue
			var nm: String = str(f.get("name", ""))
			if nm == "" or nm == "fx_death_dissolve" or g.tex.get(nm) == null:
				continue
			var life: float = clampf(float(f.life) / maxf(0.001, float(f.max)), 0.0, 1.0)
			if not _fxsz.has(nm):
				_fxsz[nm] = g.tex[nm].get_height() / A.hires_of(g.tex[nm])
			var r: float = clampf(float(_fxsz[nm]) * float(f.get("scale", g.PX)) * 0.9, 32.0, 170.0)
			var inten: float = life * (0.6 + r / 170.0)
			cand.append([inten, p, r, particles.fx_color(nm)])
		var nb := 0
		for b in g.bullets:
			if nb >= 60:
				break
			if b.life <= 0.0 or b.get("hidden", false) or not vr.has_point(b.pos):
				continue
			nb += 1
			cand.append([0.7, b.pos, 84.0, particles._bullet_col(b)])
		var ne := 0
		for b in g.ebullets:
			if ne >= 40:
				break
			if b.life <= 0.0 or not vr.has_point(b.pos):
				continue
			ne += 1
			cand.append([0.3, b.pos + Vector2(0, -16), 44.0, eb_col(b)])
		if grains != null:
			for L in grains.lights:   # 颗粒簇登记的灯（fx_grains.light）
				if vr.has_point(L[0]):
					cand.append([0.6 * float(L[3]) / maxf(0.001, float(L[4])) + 0.3, L[0], float(L[1]), L[2]])
		if cand.size() > nmax:
			cand = _top_n(cand, nmax)
		# 局部预算（防油腻 ②）：队长 render/optical_local_r（120）内入选的光强度总和封顶 render/optical_local_light（1.6），超出按比例压
		var lr: float = Bal.v("render/optical_local_r", 120.0)
		var lsum := 0.0
		for i in mini(nmax, cand.size()):
			if (cand[i][1] as Vector2).distance_to(g.ppos) < lr:
				lsum += float(cand[i][0])
		var lcap: float = Bal.v("render/optical_local_light", 1.6)
		if lsum > lcap:
			for i in mini(nmax, cand.size()):
				if (cand[i][1] as Vector2).distance_to(g.ppos) < lr:
					cand[i][0] = float(cand[i][0]) * lcap / lsum
	_dl_pos.resize(DL_MAX)
	_dl_col.resize(DL_MAX)
	var n: int = mini(nmax, cand.size())
	var gain: float = Bal.v("render/optical_dl_gain", 1.3)
	for i in DL_MAX:
		if i < n:
			var c: Array = cand[i]
			var sp: Vector2 = xf * (c[1] as Vector2)
			var col: Color = c[3]
			_dl_pos[i] = Vector4(sp.x, sp.y, float(c[2]) * k, 0.0)
			_dl_col[i] = Vector4(col.r * c[0] * gain, col.g * c[0] * gain, col.b * c[0] * gain, 0.0)
		else:
			_dl_pos[i] = Vector4(0, 0, 1, 0)
			_dl_col[i] = Vector4.ZERO
	mat.set_shader_parameter("dl_n", n)
	mat.set_shader_parameter("dl_pos", _dl_pos)
	mat.set_shader_parameter("dl_col", _dl_col)


## 按强度（[0]）从大到小取前 n 个：插入选择，代替整表 sort_custom（候选上百个时多数一次比较就被拒，docs/50 §26）
static func _top_n(cand: Array, n: int) -> Array:
	var top: Array = []
	for c in cand:
		var v: float = c[0]
		if top.size() == n and v <= float(top[n - 1][0]):
			continue
		var j: int = top.size()
		while j > 0 and float(top[j - 1][0]) < v:
			j -= 1
		top.insert(j, c)
		if top.size() > n:
			top.pop_back()
	return top


## ① 压阶帧条换入 / 换回（g.tex 同名替换：所有绘制路径都读 g.tex，不用逐处改）
func _fxq_step(on: bool) -> void:
	if on:
		if _fxq_names.is_empty():
			for k in g.tex:
				var s: String = str(k)
				if s.begins_with("fx_") or s.begins_with("proj_"):
					_fxq_names.append(s)
		var n := 0
		while _fxq_i < _fxq_names.size() and n < FXQ_PER_FRAME:
			var nm: String = _fxq_names[_fxq_i]
			_fxq_i += 1
			if _fxq_orig.has(nm) or _fxq_miss.has(nm) or g.tex.get(nm) == null:
				continue
			n += 1
			var q: Texture2D = A.tex("optical_fx/" + nm)
			if q == null or q.get_width() != g.tex[nm].get_width():
				_fxq_miss[nm] = true   # 没有压阶版（敌方特效 / 寻访），或尺寸对不上（原图换过、压阶版过期）就用原图
				continue
			_fxq_orig[nm] = g.tex[nm]
			g.tex[nm] = q
	elif not _fxq_orig.is_empty():
		for nm in _fxq_orig:
			g.tex[nm] = _fxq_orig[nm]
		_fxq_orig.clear()
		_fxq_i = 0


## 某颗敌弹的光晕 / 弹芯 / 拖尾 / 地面光颜色（docs/139 §7.3）：杂兵弹 = 敌弹色（青蓝）；
## Boss 弹（docs/142b §8.4）：该 Boss 专属色（enemies.json bcol，vfx.boss_color；不加危险色外圈，用户 10-25「描边不要加」；
## 旧开关 render/ebullet_boss_own 10-29 已删）；render/ebullet_boss_danger 1 = 旧口径（Boss 弹统一危险洋红），缺省 0
func eb_col(b: Dictionary) -> Color:
	if not b.get("boss", false):
		return col_ebullet
	if Bal.v("render/ebullet_boss_danger", 0.0) > 0.0:
		return col_danger
	return b.own_col if b.has("own_col") else g.vfx.boss_color(str(b.get("src_type", "")))   # own_col：伊祖米克分幕弹色（docs/170 §16）


## 敌弹弹体换色相（g.tex 同名替换，同压阶帧条的做法；关掉或色相变了换回原图再重做）：粉 / 紫（240–345°）→ 敌弹色色相
func _eb_step(on: bool) -> void:
	var hue: float = col_ebullet.h * 360.0
	if not _eb_orig.is_empty() and (not on or absf(hue - _eb_hue) > 0.5):
		for nm in _eb_orig:
			g.tex[nm] = _eb_orig[nm]
			g.tex.erase(nm + "@boss")
		_eb_orig.clear()
	if not on or not _eb_orig.is_empty():
		return
	_eb_hue = hue
	for nm in EB_RECOLOR:
		var t: Texture2D = g.tex.get(nm)
		if t == null:
			continue
		_eb_orig[nm] = t
		g.tex[nm] = A.hue_to(t, hue, 240.0, 345.0)
		g.tex[nm + "@boss"] = t   # Boss 弹仍画原色（粉 / 紫）弹体


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
		grains = preload("res://scripts/render/fx_grains.gd").new()
		g.add_child(grains)   # 挂在世界节点下：进低分辨率层，颗粒落在 2 px 世界格上
		grains.setup(g)


## 世界子树（game 节点下、不跨进 CanvasLayer——发光层 / 低分辨率层 / 界面各有自己的画布）的可见层：灯光与环境色 1 | 2，其余 lay
func _lay_tree(n: Node, lay: int) -> void:
	for c in n.get_children():
		if c == op_node or c is CanvasLayer:
			continue
		if c is CanvasItem:
			(c as CanvasItem).visibility_layer = (1 | VIS_LO) if (c is Light2D or c is CanvasModulate) else lay
		_lay_tree(c, lay)


func _on_node_added(n: Node) -> void:
	if not _lo_on or not (n is CanvasItem) or n == op_node or g == null or not g.is_ancestor_of(n) or Bal.v("render/optical_layer_follow", 1.0) <= 0.0:
		return
	var p: Node = n.get_parent()
	while p != null and p != g:
		if p is CanvasLayer or p == op_node:
			return
		p = p.get_parent()
	(n as CanvasItem).visibility_layer = (1 | VIS_LO) if (n is Light2D or n is CanvasModulate) else VIS_LO


## 低分辨率层开 / 关：世界节点的可见层在 1 ↔ 2 之间切，主视口剔除第 2 位；灯光与环境色两边都要（1 | 2）
func _set_lo(on: bool) -> void:
	_lo_on = on
	if not on and g.has_method("_apply_zoom"):
		g._apply_zoom()   # 关掉时镜头缩放回到设置里的「战斗画面缩放」
	g.optical_lo = on
	# 10-23 干员 1 倍帧条合入（claude/op-1x）后缺省 0：干员进低分辨率层，与怪物同一像素格、同一次脚底 y 排序（恢复前后遮挡）；1 = 旧的高清干员层
	g.optical_ops_hi = on and Bal.v("render/optical_ops_hi", 0.0) > 0.0
	lo_layer.visible = on
	op_node.visible = g.optical_ops_hi
	lo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	g.get_viewport().set_canvas_cull_mask_bit(VIS_LO - 1, not on)
	var lay: int = VIS_LO if on else 1
	g.visibility_layer = lay
	# 10-24（docs/136 §2 排查）：画布剔除按「本节点 + 每一层父节点」的可见层都要在掩码里，所以整棵世界子树都要切，
	# 之后才挂进来的节点（新发射器、新画布）也要跟着切（_on_node_added）——原来只切 game 的直接子节点、只在开关那一刻切，
	# 后挂的 GPUParticles2D / 子画布留在第 1 层，低分辨率层（掩码 2）和主视口（父节点 game 被剔）都不画
	_lay_tree(g, lay)
	if on and not g.get_tree().node_added.is_connected(_on_node_added):
		g.get_tree().node_added.connect(_on_node_added)
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
	view_k = Cfg.view_k()
	# 设置里的「战斗画面缩放」叠在整数像素镜头上（Cfg.battle_zoom，低档 cam.zoom 也用它，三档同一个镜头，docs/50 §32；
	# 非整数倍时 1 美术像素占的屏幕像素不再恒为整数，用户 10-24 要求先看 ×1.15 再定）
	var rel: float = Cfg.cam_zoom() / (Cfg.ZOOM_PHONE_DEF / 100.0 if Cfg.phone_ui() else 1.0)
	var zw: float = Cfg.battle_zoom()
	if g.demo_op != "":
		rel *= Bal.v("gallery/demo_zoom", 0.68)   # 图鉴演示小窗再拉远（用户 10-24），视野更大
		zw *= Bal.v("gallery/demo_zoom", 0.68)
	if Bal.v("render/optical_int_zoom", 0.0) > 0.0:
		var target: float = Bal.v("render/optical_view_h_phone", 360.0) if Cfg.phone_ui() else Bal.v("render/optical_view_h", 450.0)
		# docs/139 试验旋钮：把「战斗画面缩放」并进整数倍率（1 美术像素恒占整数个物理像素），不再出现 2.3 / 3.45 这种非整数放大
		zw = maxi(2, roundi(vs.y * sx * rel / target)) / (2.0 * sx)
	var pk: float = g.cam_fx.punch()   # 演出推镜（run/cam_fx.gd）：没有来源时恒 1
	zw *= pk
	if g.cam != null and absf(g.cam.zoom.x - zw) > 0.0001:
		g.cam.zoom = Vector2(zw, zw)
	var xf: Transform2D = vp.get_canvas_transform()
	var z: float = xf.x.x   # 本帧实际生效的镜头缩放（改了缩放的那一帧还是旧值，下一帧对齐）
	var cellw: float = 2.0 * z   # 1 个低分辨率像素 = 多少设计单位
	var lsz := Vector2i(ceili(vs.x / cellw) + 3, ceili(vs.y / cellw) + 3)
	if lo_vp.size != lsz and (pk <= 1.0 or lsz.x > lo_vp.size.x or lsz.y > lo_vp.size.y):
		lo_vp.size = lsz   # 推镜期间画布只放大不缩小（拉近时需要的格子变少，沿用大的那块，不每帧重分配）
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
	var pt: int = Time.get_ticks_usec() if g.prof_on else 0
	if grains != null:
		grains.draw_material_glow(glow_node)
	_draw_ground_glow()
	for p in g.glow_cur:
		glow_node.draw_rect(Rect2(p[0], Vector2(p[1], p[1])), p[2])
	for q in g.glow_tex_cur:
		glow_node.draw_texture_rect_region(q[0], q[1], q[2], q[3])   # _emit 发光层（溟痕 / 结晶 / 退散，同位置 1:1）
	if not g.world.gem_emit:
		_draw_loot()   # 没有结晶 _emit 图（旧结晶）时退回每颗一个发光点
	if Bal.v("render/optical_trail", 1.0) > 0.0:
		_draw_trails(g.bullets, false)
		_draw_trails(g.ebullets, true)
	_pt("op_glow_draw", pt)


## ⑧ 投射物发光像素拖尾：每颗弹沿速度反方向 5 个 2 px 像素、由亮到灭，吸附到 2 世界像素格；
## 我方取弹体颜色（没有就青白），敌方一律危险色（颜色语言）。最多画 300 颗
func _draw_trails(list: Array, enemy: bool) -> void:
	if fx1 and not enemy:
		return   # fx1 开着时我方弹拖尾全由 GPU 粒子簇画，这里原来逐颗取速度后 continue，什么也不画（docs/50 §26）
	var n := 0
	for b in list:
		if n >= 300:
			break
		var v: Vector2 = b.get("vel", Vector2.ZERO)
		var sp := v.length()
		if enemy and fx1 and b.get("life", 1.0) > 0.0:
			var c0: Vector2 = ((b.pos + Vector2(0, -16)) / 2.0).floor() * 2.0   # 敌弹红核心（危险色，所有敌弹，不只快的）
			var ecc: Color = eb_col(b)
			glow_node.draw_rect(Rect2(c0 - Vector2(1, 1), Vector2(4, 4)), Color(ecc.r, ecc.g, ecc.b, 0.95))
		if sp < 40.0 or fx1:
			continue   # fx1 开着时拖尾改由 GPU 粒子簇画（optical_particles.step_trails），这里只留敌弹红核心
		n += 1
		var col: Color
		if enemy:
			col = eb_col(b)   # 颜色语言：杂兵弹敌弹色、Boss 弹专属色（不再取各怪 ecol；docs/139 §7.3、docs/142b §8.4）
			if b.get("boss", false):
				var tc = D.ENEMIES.get(str(b.get("src_type", "")), {}).get("bcol_trail")
				if tc is Color:
					col = tc   # 伊比利亚：拖尾用中间调（同色相、比亮边暗，用户 10-25「有层次感」）
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
	var dens: float = Bal.v("render/optical_ground_glow", 0.1)
	if dens <= 0.0 or g.cam == null:
		return
	var vs: Vector2 = g.get_viewport().get_visible_rect().size / g.cam.zoom
	var c: Vector2 = g.cam.get_screen_center_position()
	var x0: int = floori((c.x - vs.x * 0.5) / 64.0)
	var y0: int = floori((c.y - vs.y * 0.5) / 64.0)
	var t: float = Time.get_ticks_msec() / 1000.0
	var warm: float = Bal.v("render/ground_glow_warm", 0.4)
	for cy in range(y0, y0 + ceili(vs.y / 64.0) + 1):
		for cx in range(x0, x0 + ceili(vs.x / 64.0) + 1):
			var hsh: int = (cx * 73856093) ^ (cy * 19349663)
			var r: float = float(hsh & 1023) / 1024.0
			if r >= dens:
				continue
			var ox: float = float((hsh >> 10) & 31) * 2.0
			var oy: float = float((hsh >> 15) & 31) * 2.0
			var a: float = 0.25 + 0.45 * (0.5 + 0.5 * sin(t * 0.7 + float((hsh >> 20) & 63)))
			# docs/139 §6.6 试验旋钮 render/ground_glow_warm（缺省 0）：这一比例的斑改用灯火琥珀色（暖色兜底，小面积点缀）
			var gc: Color = col_lamp if r < dens * warm else col_env
			glow_node.draw_rect(Rect2(Vector2(cx * 64.0 + ox, cy * 64.0 + oy), Vector2(2, 2)), Color(gc.r, gc.g, gc.b, a))


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


## --prof：把 t0 到现在的耗时记到 g.prof[k]（光学观感各段，docs/50 §26；不在 --prof 下直接返回 0）
func _pt(k: String, t0: int) -> int:
	if not g.prof_on:
		return 0
	var now := Time.get_ticks_usec()
	g.prof[k] = int(g.prof.get(k, 0)) + (now - t0)
	return now


func wanted() -> bool:
	if (ab_mask | auto_mask) & 32:
		return false
	if force >= 0:
		return force == 1
	# 10-23 用户：光学观感正式打开（render/optical 缺省 1）；画质「低」时自动关（低配兜底），中 / 高开
	return Bal.v("render/optical", 1.0) > 0.0 and Cfg.quality != "low"


func _process(_dt: float) -> void:
	if g == null:
		return
	_update_cols(_dt)
	var pt: int = Time.get_ticks_usec() if g.prof_on else 0
	if grains != null:
		grains.kill = ((ab_mask | auto_mask) & 1) != 0
		grains.step(_dt)
		grains.flush()
	pt = _pt("op_grains", pt)
	fx1 = (fx1_force == 1) if fx1_force >= 0 else Bal.v("render/optical_fx1", 1.0) > 0.0
	_fxq_step(fx1 and wanted() and DisplayServer.get_name() != "headless" and Bal.v("render/optical_fxq", 1.0) > 0.0)
	FD.col_cap = Bal.v("render/optical_fx_cap", 1.4) if g.optical_on and fx1 else 0.0
	_eb_step(wanted() and DisplayServer.get_name() != "headless")   # 光学关（低画质 / 无头）时换回原图
	var on := wanted() and DisplayServer.get_name() != "headless"
	g.optical_on = on
	visible = on
	glow_layer.visible = on and ((ab_mask | auto_mask) & 8) == 0
	var lo_want: bool = on and Bal.v("render/optical_lowres", 1.0) > 0.0 and lo_vp != null and ((ab_mask | auto_mask) & 16) == 0
	if lo_want != _lo_on:
		_set_lo(lo_want)
	if _lo_on:
		_lo_step()
	g.glow_cur = g.glow_next
	g.glow_next = []
	g.glow_tex_cur = g.glow_tex_next
	g.glow_tex_next = []
	pt = _pt("op_lowres", pt)
	if particles != null:
		var pa: bool = on and ((ab_mask | auto_mask) & 2) == 0
		if pa != _pa_last:
			particles.set_active(pa)
			_pa_last = pa
		if pa and g.cam != null and g.lamp_light != null:
			particles.step(g.cam.get_screen_center_position(), g.lamp_light.global_position, col_env, col_lamp)
	_was_on = on
	pt = _pt("op_particles", pt)
	if glow_layer.visible:
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
	mat.set_shader_parameter("glow_budget", Bal.v("render/optical_glow_budget", 0.06) if fx1 else 99.0)
	mat.set_shader_parameter("steps", Bal.v("render/optical_steps", 3.0) if fx1 else 0.0)
	mat.set_shader_parameter("local_budget", Bal.v("render/optical_local_budget", 0.5) if fx1 else 99.0)
	mat.set_shader_parameter("local_r", Bal.v("render/optical_local_r", 120.0) * k)
	pt = _pt("op_shader", pt)
	_dyn_lights(xf, k)
	pt = _pt("op_dynlights", pt)
	if particles != null:
		particles.step_trails(col_ebullet, fx1)
	pt = _pt("op_trails", pt)
	mat.set_shader_parameter("emissive_th", Bal.v("render/optical_emissive_th", 0.72))
	mat.set_shader_parameter("lut_on", Bal.v("render/optical_lut", 1.0))
	mat.set_shader_parameter("sat", Bal.v("render/optical_sat", 1.0))
	mat.set_shader_parameter("brightness", Cfg.brightness * Bal.v("render/ambient_gain", 1.05))
	mat.set_shader_parameter("sea_amt", Bal.v("render/optical_sea", 0.55))
	mat.set_shader_parameter("caustics", Bal.v("render/optical_caustics", 0.02))
	mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	if Cfg.dev_args().has("--opticaldbg") and Engine.get_process_frames() % 60 == 0:
		print("OPTICAL cell=%.2f origin=%s lamp=%s r=%.1f scale=%s" % [g.PX * k, str(xf * Vector2.ZERO), str(xf * L.global_position) if L != null else "-", 64.0 * (L.texture_scale if L != null else 0.0) * k, str(L.texture_scale if L != null else 0.0)])
	if g.post != null:
		mat.set_shader_parameter("hurt", g.post.hurt)
		mat.set_shader_parameter("desat", g.post.desat)
		mat.set_shader_parameter("zone_amt", g.post.zone_amt)
		mat.set_shader_parameter("zone_c", g.post.zone_c)
		mat.set_shader_parameter("zone_r", g.post.zone_r)
		mat.set_shader_parameter("zone_hole", g.post.zone_hole)
		g.post.apply_if(mat)   # 终结技冲击帧
		g.post.apply_zone_guards(mat)
