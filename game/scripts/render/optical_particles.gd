## 光学观感原型 · 粒子（10-23 协调人 / 用户「最想看粒子感」，docs/50 §25）：全部 GPUParticles2D（兼容渲染器 / WebGL2 可用），CPU 只在触发时摆位置。
## 颗粒固定 2 世界像素（= 1 美术像素）、最近邻；只用 GPU 自己的随机，不碰 g.rng / g.vrng，同 seed 模拟不变。中画质数量减半，低画质不开。
##   ⑦ 击杀碎屑：把怪物帧条首帧（开局后第一次击杀时按种类烘一次）的像素位置 + 颜色做成发射纹理，从怪物脚下按原样炸开、减速、下沉、熄灭；
##      另从发光层喷几颗该怪发光色的荧光体液。对象池轮转，总数有上限
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
var embers: GPUParticles2D
var _mat_cache := {}          # 帧条名 → [ParticleProcessMaterial, 发光色]
var fluid_mat: ParticleProcessMaterial
var spark_mat: ParticleProcessMaterial
var k_amount := 1.0
var active := false


func setup(game, wp: Node2D, gp: Node2D) -> void:
	g = game
	world_parent = wp
	glow_parent = gp
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	px_tex = ImageTexture.create_from_image(img)
	k_amount = 0.5 if Cfg.quality == "mid" else 1.0
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
	spores = _ambient(glow_parent, int(70 * k_amount), 9.0, Color(0.35, 0.95, 1.0))
	var sm: ParticleProcessMaterial = spores.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	sm.emission_box_extents = Vector3(760, 440, 0)
	sm.direction = Vector3(0, -1, 0)
	sm.spread = 40.0
	sm.initial_velocity_min = 3.0
	sm.initial_velocity_max = 9.0
	spores.preprocess = 9.0
	embers = _ambient(glow_parent, int(16 * k_amount), 1.6, Color(1.0, 0.62, 0.25))
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


func set_active(on: bool) -> void:
	active = on and k_amount > 0.0 and Cfg.quality != "low"
	spores.visible = active
	spores.emitting = active
	embers.visible = active
	embers.emitting = active
	if not active:
		for p in debris + fluid + sparks:
			p.visible = false
			p.emitting = false


## 每帧（optical.gd）：孢子发射区跟着镜头，余烬跟着灯火
func step(cam_center: Vector2, lamp_pos: Vector2) -> void:
	if not active:
		return
	spores.global_position = cam_center
	embers.global_position = lamp_pos + Vector2(0, -6)


## 某种怪的碎屑材质：首帧像素（1 美术像素取 1 个）均匀抽 DEBRIS_PTS 个，位置相对锚点、按画面缩放
func _debris_mat(e: Dictionary, sc: float, anc: Vector2) -> Array:
	var key := "%s@%.2f" % [e.tex, sc]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Array = [null, Color(0.5, 1.0, 1.0)]
	var tx: Texture2D = g.tex.get(e.tex)
	if tx != null:
		var img: Image = tx.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var fh: int = img.get_height()
			var frames: int = maxi(1, int(round(img.get_width() / float(fh))))
			var fw: int = img.get_width() / frames
			var dens: float = A.hires_of(tx)
			var st: int = maxi(1, int(dens))
			var pts: Array = []
			var best := -1.0
			for y in range(0, fh, st):
				for x in range(0, fw, st):
					var c: Color = img.get_pixel(x, y)
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


## ⑦ 击杀碎屑（combat.kill 在光学观感开着时调；只做画面）
func kill_burst(e: Dictionary) -> void:
	if not active or debris.is_empty() or e.get("chest", false):
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
		f.modulate = mc[1]
		f.visible = true
		f.restart()


## 命中迸溅（vfx.hit_react 调）：限频，几颗被打者发光色 / 白色像素
func hit_spark(pos: Vector2, col: Color) -> void:
	if not active or sparks.is_empty():
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
