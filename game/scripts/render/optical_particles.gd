## 光学观感原型 · 粒子（10-23 协调人 / 用户「最想看粒子感」，docs/50 §25）：全部 GPUParticles2D（兼容渲染器 / WebGL2 可用），CPU 只在触发时摆位置。
## 颗粒固定 2 世界像素（= 1 美术像素）、最近邻；只用 GPU 自己的随机，不碰 g.rng / g.vrng，同 seed 模拟不变。中画质数量减半，低画质不开。
##   ⑦ 击杀碎屑：把怪物帧条首帧（开局后第一次击杀时按种类烘一次）的像素位置 + 颜色做成发射纹理，从怪物脚下按原样炸开、减速、下沉、熄灭；
##      另从发光层喷几颗荧光体液（环境色，颜色语言 10-23）。对象池轮转，总数有上限
##   ⑤ 漂浮荧光孢子：跟着镜头的一大块发射区，慢慢上漂、明灭（发光层，不受环境暗色影响）
##   灯火余烬：队长灯火处往上飘的暖色火星
##   命中迸溅：受击时几颗像素（限频）
extends Node

const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

const DEBRIS_PTS := 40        # 每只怪最多取多少个像素当碎屑
const DEBRIS_POOL := 20       # 同时在飞的击杀碎屑组数（中画质 10）
const FLUID_POOL := 16
const SPARK_POOL := 16
const SPARK_GAP := 0.05       # 命中迸溅最短间隔（秒，真实时间）
const SKILL_POOL := 24        # 技能点缀（火星 / 碎片 / 余烬）同时在飞的组数（中画质 12）
const SKILL_GAP := 0.03
const SMOKE_POOL := 10        # 爆炸少量烟（中画质 5）
const TIER_POOL := 14         # 特效第 2 步：命中三档迸溅，每档同时在飞的组数（中画质 7）
const TRAIL_PTS := 256        # ⑤ 投射物粒子簇：每帧汇总的发射点上限（我方弹 + 敌弹）
const TRAIL_AMOUNT := 700     # 拖尾颗粒总数（中画质 350）；全局颗粒上限 ≈ 碎屑 800 + 点缀 288 + 烟 60 + 拖尾 700 + 环境 86

var g
var world_parent: Node2D      # 受光的世界层（碎屑本体：吃灯光与光池）
var glow_parent: Node2D       # 发光层（荧光体液、孢子、余烬、迸溅）
var px_tex: ImageTexture      # 2×2 白点
var debris: Array = []
var fluid: Array = []
var sparks: Array = []
var _di := 0
var _fi := 0
var _si := 0
var _spark_t := 0.0
var spores: GPUParticles2D
var warm_spores: GPUParticles2D   # docs/139 §6.6 暖色孢子（render/warm_spores > 0 时才建）
var embers: GPUParticles2D
var _mat_cache := {}          # 帧条名 → [ParticleProcessMaterial, 发光色]
var fluid_mat: ParticleProcessMaterial
var skill: Array = []
var _ki := 0
var _skill_t := 0.0
var _fx_col := {}             # 帧条名 → 本色（最亮且饱和的像素色，第一次用到时算）
var skill_mat: ParticleProcessMaterial
var ember_mat: ParticleProcessMaterial
var smoke: Array = []
var tiers: Array = [[], [], []]   # 轻 / 中 / 重三个池（每颗组 3 / 6 / 12 颗，fx/hit_n*）
var _tii := [0, 0, 0]
var _mi := 0
var smoke_mat: ParticleProcessMaterial
var trails: GPUParticles2D    # ⑤ 一个节点包下全部投射物拖尾：每帧把弹的位置 / 颜色写进发射点贴图（EMISSION_SHAPE_POINTS），不逐颗 emit、不新建节点
var _tp_img: Image
var _tc_img: Image
var _tp_tex: ImageTexture
var _tc_tex: ImageTexture
var _near_load := 0.0
var _near_t := 0.0
var _bcol := {}               # 弹种 → 颜色（帧条本色，第一次用到时算）
var spark_mat: ParticleProcessMaterial
var k_amount := 1.0
var env_col := Color(0.39, 0.7, 0.7)   # 怪死后体液 = 环境色（颜色语言，optical.step 每帧写）
var active := false


func setup(game, wp: Node2D, gp: Node2D) -> void:
	g = game
	world_parent = wp
	glow_parent = gp
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	px_tex = ImageTexture.create_from_image(img)
	# 中档颗粒量同高档（render/mid_full_fx，缺省 1；10-25 用户「以现在高档的画质作为中档的画质来保障」，docs/50 §26）；0 = 旧的中档减半
	k_amount = 0.5 if Cfg.quality == "mid" and Bal.v("render/mid_full_fx", 1.0) <= 0.0 else 1.0
	var dn := int(DEBRIS_POOL * k_amount)
	for i in dn:
		debris.append(_one_shot(world_parent, DEBRIS_PTS, 0.9))
	fluid_mat = _burst_mat(Vector2(30, 70), 140.0, Vector2(0, 40), 0.9)
	for i in int(FLUID_POOL * k_amount):
		var p := _one_shot(glow_parent, 6, 1.0)
		p.process_material = fluid_mat
		fluid.append(p)
	spark_mat = _burst_mat(Vector2(60, 160), 260.0, Vector2(0, 0), 0.35)
	for i in int(SPARK_POOL * k_amount):
		var p := _one_shot(glow_parent, 3, 0.35)
		p.process_material = spark_mat
		sparks.append(p)
	skill_mat = _burst_mat(Vector2(60, 190), 180.0, Vector2(0, 160), 0.55)   # 火星 / 碎片：快、往下落
	ember_mat = _burst_mat(Vector2(15, 50), 40.0, Vector2(0, -30), 0.7)     # 余烬：慢、往上飘（防油腻 ③：短寿命）
	ember_mat.direction = Vector3(0, -1, 0)
	ember_mat.spread = 70.0
	for i in int(SKILL_POOL * k_amount):
		var p := _one_shot(glow_parent, 10, 0.7)
		p.process_material = skill_mat
		skill.append(p)
	smoke_mat = _burst_mat(Vector2(8, 30), 20.0, Vector2(0, -18), 0.9)   # 防油腻 ③：烟也是 2 px 颗粒、少量、短寿命
	for i in int(SMOKE_POOL * k_amount):
		var p := _one_shot(world_parent, 3, 0.9)
		p.process_material = smoke_mat
		p.modulate = Color(0.16, 0.17, 0.2, 0.55)
		smoke.append(p)
	_setup_trails()
	for ti in 3:
		var amt: int = maxi(1, int(round(Bal.vi("fx/hit_n%d" % (ti + 1), [3, 6, 12][ti]) * k_amount)))
		for i in int(TIER_POOL * k_amount):
			var p := _one_shot(glow_parent, amt, 0.35)
			p.process_material = spark_mat
			tiers[ti].append(p)
	spores = _ambient(glow_parent, int(70 * k_amount), 9.0, Color.WHITE)   # 颜色由 modulate 给（step）
	var sm: ParticleProcessMaterial = spores.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(760, 440, 0)
	sm.direction = Vector3(0, -1, 0)
	sm.spread = 40.0
	sm.initial_velocity_min = 3.0
	sm.initial_velocity_max = 9.0
	spores.preprocess = 9.0
	# docs/139 §6.6 试验旋钮：render/ember_n 灯火余烬数（缺省 16）；render/warm_spores 暖色孢子数（缺省 0 = 不开，琥珀色、与环境孢子同一套漂浮）
	embers = _ambient(glow_parent, maxi(1, int(Bal.v("render/ember_n", 16.0) * k_amount)), 1.6, Color.WHITE)
	var wn: int = int(Bal.v("render/warm_spores", 0.0) * k_amount)
	if wn > 0:
		warm_spores = _ambient(glow_parent, wn, 9.0, Color.WHITE)
		var wm: ParticleProcessMaterial = warm_spores.process_material
		wm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		wm.emission_box_extents = Vector3(760, 440, 0)
		wm.direction = Vector3(0, -1, 0)
		wm.spread = 40.0
		wm.initial_velocity_min = 3.0
		wm.initial_velocity_max = 9.0
		warm_spores.preprocess = 9.0
	var em: ParticleProcessMaterial = embers.process_material
	em.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	em.emission_sphere_radius = 10.0
	em.direction = Vector3(0, -1, 0)
	em.spread = 25.0
	em.initial_velocity_min = 12.0
	em.initial_velocity_max = 30.0
	em.gravity = Vector3(0, -6, 0)


func _one_shot(parent: Node, amount: int, life: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.texture = px_tex
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.visible = false
	parent.add_child(p)
	return p


## 爆开类的处理材质：速度区间、阻尼、重力、寿命内由亮到灭
func _burst_mat(vel: Vector2, damp: float, grav: Vector2, life: float) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0
	m.initial_velocity_min = vel.x
	m.initial_velocity_max = vel.y
	m.damping_min = damp * 0.7
	m.damping_max = damp
	m.gravity = Vector3(grav.x, grav.y, 0)
	m.color_ramp = _fade_ramp(life)
	return m


func _fade_ramp(_life: float) -> GradientTexture1D:
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(0.5, 0.5, 0.5, 0))
	gr.add_point(0.55, Color(1, 1, 1, 0.9))
	var t := GradientTexture1D.new()
	t.gradient = gr
	return t


## 常驻的环境粒子（孢子 / 余烬）：持续发射、淡入淡出
func _ambient(parent: Node, amount: int, life: float, col: Color) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.local_coords = false
	p.texture = px_tex
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.visible = false
	p.emitting = false
	var m := ParticleProcessMaterial.new()
	m.gravity = Vector3.ZERO
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r, col.g, col.b, 0.0))
	gr.set_color(1, Color(col.r, col.g, col.b, 0.0))
	gr.add_point(0.2, Color(col.r, col.g, col.b, 1.0))
	gr.add_point(0.7, Color(col.r, col.g, col.b, 0.8))
	var t := GradientTexture1D.new()
	t.gradient = gr
	m.color_ramp = t
	p.process_material = m
	parent.add_child(p)
	return p


## --stackab 第 64 位（docs/50 §26.9，仅测试）：爆发类隔一次发一次，近似「GPU 粒子池减半」的网页画质选项，同局轮换量帧时
var _half_n := 0
func _ab_half() -> bool:
	if g.optical == null or (int(g.optical.ab_mask) & 64) == 0:
		return false
	_half_n += 1
	return _half_n % 2 == 0


func set_active(on: bool) -> void:
	active = on and k_amount > 0.0 and Cfg.quality != "low"
	spores.visible = active
	spores.emitting = active
	if warm_spores != null:
		warm_spores.visible = active
		warm_spores.emitting = active
	embers.visible = active
	embers.emitting = active
	if not active:
		trails.emitting = false
		trails.visible = false
		for p in debris + fluid + sparks + skill + smoke + tiers[0] + tiers[1] + tiers[2]:
			p.visible = false
			p.emitting = false


## 每帧（optical.gd）：孢子发射区跟着镜头，余烬跟着灯火；颜色按颜色语言（孢子 = 环境色、余烬 = 灯火色）
func step(cam_center: Vector2, lamp_pos: Vector2, env: Color, lamp: Color, trail: Array = []) -> void:
	if not active:
		return
	spores.global_position = cam_center
	embers.global_position = lamp_pos + Vector2(0, -6)
	if warm_spores != null:
		warm_spores.global_position = cam_center
		warm_spores.modulate = lamp
	spores.modulate = env
	_ember_colors(trail)
	embers.modulate = lamp if _ember_key == "" else Color.WHITE
	env_col = env


## 跑动拖尾（余烬）用队长自己的代表色（character.trail_cols：[主色, 辅色]，10-26 用户定，docs/146）：每颗出生时在 主色 → 辅色 的渐变上随机取一个色
## （ParticleProcessMaterial.color_initial_ramp），数量 / 尺寸 / 寿命都不变；只在队长换人（颜色变了）时重建一次渐变；没有数据（空）退回灯火色
var _ember_key := ""
func _ember_colors(cols: Array) -> void:
	var key := ""
	if cols.size() >= 2:
		key = "%s|%s" % [cols[0], cols[1]]
	if key == _ember_key:
		return
	_ember_key = key
	var em: ParticleProcessMaterial = embers.process_material
	if key == "":
		em.color_initial_ramp = null
		return
	var gr := Gradient.new()
	gr.set_color(0, cols[0])
	gr.set_color(1, cols[1])
	var t := GradientTexture1D.new()
	t.gradient = gr
	em.color_initial_ramp = t


## 某种怪的碎屑材质：首帧像素（1 美术像素取 1 个）均匀抽 DEBRIS_PTS 个，位置相对锚点、按画面缩放
func _debris_mat(e: Dictionary, sc: float, anc: Vector2, src := "", frame := 0) -> Array:
	var tn: String = src if src != "" else str(e.tex)
	var key := "%s#%d@%.2f" % [tn, frame, sc]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Array = [null, Color(0.5, 1.0, 1.0)]
	var tx: Texture2D = g.tex.get(tn)
	if tx != null:
		var img: Image = tx.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var fh: int = img.get_height()
			var frames: int = int(g.V6_FRAMES[tn][0]) if src != "" and g.V6_FRAMES.has(tn) else maxi(1, int(round(img.get_width() / float(fh))))
			var fw: int = img.get_width() / frames
			var x0: int = clampi(frame, 0, frames - 1) * fw
			var dens: float = A.hires_of(tx)
			var st: int = maxi(1, int(dens))
			var pts: Array = []
			var best := -1.0
			for y in range(0, fh, st):
				for x in range(0, fw, st):
					var c: Color = img.get_pixel(x0 + x, y)
					if c.a < 0.6:
						continue
					pts.append([Vector2(x, y), c])
					var v: float = c.v * (0.4 + c.s)
					if v > best:
						best = v
						out[1] = Color.from_hsv(c.h if c.s > 0.15 else 0.5, maxf(c.s, 0.5), 1.0)
			if not pts.is_empty():
				var n: int = mini(DEBRIS_PTS, pts.size())
				var pimg := Image.create(n, 1, false, Image.FORMAT_RGF)
				var cimg := Image.create(n, 1, false, Image.FORMAT_RGBA8)
				for i in n:
					var pt: Array = pts[int(i * pts.size() / float(n))]
					var q: Vector2 = ((pt[0] as Vector2) - anc * Vector2(fw, fh)) * sc / dens
					pimg.set_pixel(i, 0, Color(q.x, q.y, 0, 1))
					cimg.set_pixel(i, 0, pt[1])
				var m := _burst_mat(Vector2(30, 110), 170.0, Vector2(0, 90), 0.9)
				m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
				m.emission_point_texture = ImageTexture.create_from_image(pimg)
				m.emission_color_texture = ImageTexture.create_from_image(cimg)
				m.emission_point_count = n
				out[0] = m
	_mat_cache[key] = out
	return out


## 新击杀（vfx.death_shatter / _shatter）：死亡帧条播完那一刻，按它最后一帧的像素碎开（位置 / 缩放 / 锚点 / 朝向与帧条绘制一致）
func kill_burst_frame(e: Dictionary, src: String, frame: int, origin: Vector2, sc: float, anc: Vector2, flip: bool) -> void:
	if not active or debris.is_empty() or e.get("chest", false) or _ab_half():
		return
	var mc: Array = _debris_mat(e, sc, anc, src, frame)
	if mc[0] == null:
		kill_burst(e)
		return
	var p: GPUParticles2D = debris[_di % debris.size()]
	_di += 1
	p.process_material = mc[0]
	p.global_position = origin
	p.scale = Vector2(-1 if flip else 1, 1)
	p.visible = true
	p.restart()
	if not fluid.is_empty():
		var f: GPUParticles2D = fluid[_fi % fluid.size()]
		_fi += 1
		f.global_position = e.pos
		f.modulate = env_col
		f.visible = true
		f.restart()


## ⑦ 击杀碎屑（combat.kill 在光学观感开着时调；只做画面）
func kill_burst(e: Dictionary) -> void:
	if not active or debris.is_empty() or e.get("chest", false) or _ab_half():
		return
	var foot: bool = g.foot_anchor.has(e.tex)
	var origin: Vector2 = e.pos + Vector2(0, e.r * 0.8) if foot else e.pos
	var anc: Vector2 = A.enemy_pixel_anchor(e.tex, Vector2(0.5, 1.0) if foot else Vector2(0.5, 0.5))
	var sc: float = D.enemy_scale(e, g.t, g.PX)
	var mc: Array = _debris_mat(e, sc, anc)
	if mc[0] == null:
		return
	var p: GPUParticles2D = debris[_di % debris.size()]
	_di += 1
	p.process_material = mc[0]
	p.global_position = origin
	p.scale = Vector2(-1 if e.get("fx", 1.0) < 0.0 else 1, 1)
	p.visible = true
	p.restart()
	if not fluid.is_empty():
		var f: GPUParticles2D = fluid[_fi % fluid.size()]
		_fi += 1
		f.global_position = e.pos
		f.modulate = env_col
		f.visible = true
		f.restart()


## ⑤ 投射物粒子簇 + 拖尾：一个 GPUParticles2D，发射点 = 这一帧所有在飞的弹（贴图里写位置 / 颜色），颗粒留在世界坐标里随弹移动拉成拖尾
func _setup_trails() -> void:
	trails = GPUParticles2D.new()
	trails.amount = maxi(1, int(TRAIL_AMOUNT * k_amount))
	trails.lifetime = 0.3
	trails.local_coords = false
	trails.texture = px_tex
	trails.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	trails.visible = false
	trails.emitting = false
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	m.direction = Vector3(0, -1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 4.0
	m.initial_velocity_max = 22.0
	m.damping_min = 20.0
	m.damping_max = 40.0
	m.gravity = Vector3.ZERO
	m.color_ramp = _fade_ramp(0.4)
	_tp_img = Image.create(TRAIL_PTS, 1, false, Image.FORMAT_RGF)
	_tc_img = Image.create(TRAIL_PTS, 1, false, Image.FORMAT_RGBA8)
	_tp_tex = ImageTexture.create_from_image(_tp_img)
	_tc_tex = ImageTexture.create_from_image(_tc_img)
	m.emission_point_texture = _tp_tex
	m.emission_color_texture = _tc_tex
	m.emission_point_count = 1
	trails.process_material = m
	glow_parent.add_child(trails)


func _bullet_col(b: Dictionary) -> Color:
	var bc = b.get("col")
	if bc is Color:
		return Color(minf(bc.r, 1.0), minf(bc.g, 1.0), minf(bc.b, 1.0))
	var kd: String = str(b.get("kind", ""))
	if _bcol.has(kd):
		return _bcol[kd]
	var tn: String = g.world.PROJ_TEX.get(kd, "")
	var c: Color = fx_color(tn) if tn != "" and g.tex.get(tn) != null else Color(0.75, 0.95, 1.0)
	_bcol[kd] = c
	return c


## 每帧（optical.gd，fx1 开着时）：汇总在飞的弹写进发射点贴图；没有弹就停发
func step_trails(danger: Color, on: bool) -> void:
	if not active or trails == null:
		return
	var n := 0
	if on:
		for b in g.bullets:
			if n >= TRAIL_PTS:
				break
			if b.life <= 0.0 or b.get("hidden", false):
				continue
			_tp_img.set_pixel(n, 0, Color(b.pos.x, b.pos.y, 0, 1))
			_tc_img.set_pixel(n, 0, _bullet_col(b))
			n += 1
		for b in g.ebullets:
			if n >= TRAIL_PTS:
				break
			if b.life <= 0.0:
				continue
			_tp_img.set_pixel(n, 0, Color(b.pos.x, b.pos.y - 16.0, 0, 1))
			_tc_img.set_pixel(n, 0, g.optical.eb_col(b) if g.optical != null else danger)   # Boss 弹危险色、杂兵弹敌弹色（docs/139 §7.3）
			n += 1
	trails.visible = n > 0
	trails.emitting = n > 0
	if n > 0:
		_tp_tex.update(_tp_img)
		_tc_tex.update(_tc_img)
		(trails.process_material as ParticleProcessMaterial).emission_point_count = n


## 帧条本色：首帧里最亮、偏饱和的像素色（拉满亮度）；没有就淡青白
func fx_color(name: String) -> Color:
	if _fx_col.has(name):
		return _fx_col[name]
	var col := Color(0.8, 0.95, 1.0)
	var tx: Texture2D = g.tex.get(name)
	if tx != null:
		var img: Image = tx.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var fw: int = img.get_width() / maxi(1, int(g.V6_FRAMES.get(name, [1])[0]))
			var best := -1.0
			var st: int = maxi(1, img.get_height() / 48)
			for y in range(0, img.get_height(), st):
				for x in range(0, fw, st):
					var c: Color = img.get_pixel(x, y)
					if c.a < 0.6:
						continue
					var sc: float = c.v * (0.3 + c.s)
					if sc > best:
						best = sc
						col = Color.from_hsv(c.h, clampf(c.s, 0.25, 0.9), 1.0) if c.s > 0.12 else Color(1, 1, 1)
	_fx_col[name] = col
	return col


## ③ 技能点缀：一次性帧条特效出现时，按它的本色在原点喷一组火星 / 碎片（大的特效另配余烬）。限频 SKILL_GAP、轮转池
func fx_burst(name: String, pos: Vector2, scale: float) -> void:
	if not active or skill.is_empty() or name == "fx_death_dissolve" or _ab_half():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _skill_t < SKILL_GAP:
		return
	_skill_t = now
	var p: GPUParticles2D = skill[_ki % skill.size()]
	_ki += 1
	var big: bool = scale >= 3.0 or (g.tex.get(name) != null and g.tex[name].get_height() / A.hires_of(g.tex[name]) >= 64.0)
	var col: Color = fx_color(name)
	p.process_material = skill_mat   # 迸射：快、往下落
	p.global_position = pos
	p.modulate = col
	p.visible = true
	p.restart()
	# 局部预算（防油腻 ②）：队长 render/optical_local_r 内最近的喷发次数（0.5 秒衰减）超过上限时，新喷发压暗、不配余烬 / 烟
	var near: bool = pos.distance_to(g.ppos) < Bal.v("render/optical_local_r", 120.0)
	if near:
		_near_load = _near_load * exp(-(now - _near_t) / 0.5) + 1.0
		_near_t = now
		if _near_load > Bal.v("render/optical_local_bursts", 4.0):
			p.modulate = Color(col.r, col.g, col.b, 0.45)
			return
	if big and _ki % 3 != 0:
		# 大的爆炸 / 命中：再配一组余烬（慢、往上飘）+ 少量烟（三次里配两次）
		var q: GPUParticles2D = skill[_ki % skill.size()]
		_ki += 1
		q.process_material = ember_mat
		q.global_position = pos
		q.modulate = col
		q.visible = true
		q.restart()
		if not smoke.is_empty():
			var m: GPUParticles2D = smoke[_mi % smoke.size()]
			_mi += 1
			m.global_position = pos + Vector2(0, -6)
			m.visible = true
			m.restart()


## 特效第 2 步：命中三档迸溅（vfx._tier_fx 调）。按档取池轮转；队长周围局部预算超了就压暗（同 fx_burst）
func tier_burst(pos: Vector2, col: Color, tier: int) -> void:
	if not active or tier < 1 or tiers[tier - 1].is_empty() or _ab_half():
		return
	var pool: Array = tiers[tier - 1]
	var p: GPUParticles2D = pool[_tii[tier - 1] % pool.size()]
	_tii[tier - 1] += 1
	var a := 1.0
	if pos.distance_to(g.ppos) < Bal.v("render/optical_local_r", 120.0):
		var now := Time.get_ticks_msec() / 1000.0
		_near_load = _near_load * exp(-(now - _near_t) / 0.5) + tier * 0.34
		_near_t = now
		if _near_load > Bal.v("render/optical_local_bursts", 4.0):
			a = 0.4
	p.global_position = pos
	p.modulate = Color(col.r, col.g, col.b, a)
	p.visible = true
	p.restart()


## 命中迸溅（vfx.hit_react 调）：限频，几颗被打者发光色 / 白色像素
func hit_spark(pos: Vector2, col: Color) -> void:
	if not active or sparks.is_empty() or _ab_half():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _spark_t < SPARK_GAP:
		return
	_spark_t = now
	var s: GPUParticles2D = sparks[_si % sparks.size()]
	_si += 1
	s.global_position = pos
	s.modulate = col
	s.visible = true
	s.restart()
