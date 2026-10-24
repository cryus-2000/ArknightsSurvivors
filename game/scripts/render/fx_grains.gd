## 像素粒子模板（10-24 协调人单 / 用户「先做能稳做的，考虑网页端性能」，docs/136）：特效「粒子化」的可复用积木。
## CPU 颗粒 + 一个画布批绘（本节点 _draw 里 draw_rect，2×2 世界像素 = 640×360 世界格上的 1 格），挂在世界节点下进低分辨率层。
## 不用 GPUParticles2D：它在光学观感的低分辨率层（共享 World2D 的 SubViewport）里不画（实测，docs/136 §2），网页 / 桌面行为也不必再分别核。
## 模板参数（TEMPLATES）：ramp 颜色阶（硬边：按年龄落在哪一段就用哪一段的色，不插值；值 > 1 = 发光）、life 寿命 / life_rand 散布、
##   speed 初速区间、spread 散射角（度）、grav 重力、drag 阻力（惯性：越小飘越远）、per_frame 单帧新增上限；
##   budget 每档画质同屏上限（高 / 中；低画质不开，调用方退回非粒子画法）。超预算时新颗粒直接丢（不挤掉旧的），单帧超上限均匀抽稀由调用方做。
## 另带 CPU 火星（spark）：带重力、落到「地面高度」（物体脚底 y）停住、冷却变暗后熄灭——俯视游戏没有真碰撞，按脚底 y 处理。
## 只用 g.vrng（画面随机流），不碰玩法随机数
extends Node2D

const Bal = preload("res://scripts/core/balance.gd")

const TEMPLATES := {
	# 刀光：热白 → 亮本色 → 本色 → 冷暗四阶，带挥刀惯性散开、轻微下落、逐颗熄灭
	"slash": {"ramp": [[0.0, Color(2.0, 2.0, 2.0, 1)], [0.12, Color(1.35, 1.35, 1.35, 1)], [0.38, Color(0.9, 0.9, 0.9, 1)], [0.7, Color(0.45, 0.45, 0.5, 0.9)]],
		"life": 0.3, "life_rand": 0.45, "speed": Vector2(10, 46), "spread": 26.0, "grav": 80.0, "drag": 5.0, "per_frame": 140, "budget": [900, 450]},
}
const SPARK_MAX := [0, 120, 240]

var g
var level := 2      # 2 高 / 1 中 / 0 低（低 = 不开）
var off := false    # --grainab 同局轮换：true = 这一段退回第二版画法
# 颗粒（结构数组）：位置、速度、剩余寿命、总寿命、颜色、模板序号
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var lmax := PackedFloat32Array()
var col := PackedColorArray()
var tpl := PackedInt32Array()
var _names: Array = []
var _ramps: Array = []   # 模板序号 → [[阈值（年龄比例）, 颜色], …]
var _frame_n := {}
var sparks: Array = []   # CPU 火星：[pos, vel, ground_y, life, max, col]
var _drawn := false


func setup(game) -> void:
	g = game
	level = {"high": 2, "mid": 1, "low": 0}.get(Cfg.quality, 2)
	for name in TEMPLATES:
		_names.append(name)
		_ramps.append(TEMPLATES[name].ramp)


func on() -> bool:
	return level > 0 and g != null and g.optical_on and Bal.v("fx/grains", 1.0) > 0.0


func budget() -> int:
	return int(TEMPLATES.slash.budget[0 if level >= 2 else 1])


## 生成一颗：p 世界坐标、dir 初速基准方向（单位向量；模板 spread 内散开）、c 颜色（乘在颜色阶上）
func push(name: String, p: Vector2, dir: Vector2, c: Color) -> void:
	var t: Dictionary = TEMPLATES.get(name, {})
	if t.is_empty() or pos.size() >= budget():
		return
	var fn: int = int(_frame_n.get(name, 0))
	if fn >= int(t.per_frame):
		return
	_frame_n[name] = fn + 1
	var a: float = dir.angle() + deg_to_rad(g.vrng.randf_range(-float(t.spread), float(t.spread)))
	var l: float = float(t.life) * (1.0 - float(t.life_rand) * g.vrng.randf())
	pos.append(p)
	vel.append(Vector2.from_angle(a) * g.vrng.randf_range(float(t.speed.x), float(t.speed.y)))
	life.append(l)
	lmax.append(l)
	col.append(c)
	tpl.append(_names.find(name))


## CPU 火星：从 p 带重力迸出，落到 ground_y 停住、冷却变暗后熄灭（同屏上限 SPARK_MAX）
func spark(p: Vector2, ground_y: float, c: Color, n: int) -> void:
	if not on():
		return
	for i in n:
		if sparks.size() >= SPARK_MAX[level]:
			return
		var a: float = -PI * 0.5 + (float(i) / maxf(1.0, float(n - 1)) - 0.5) * 2.4 + g.vrng.randf_range(-0.2, 0.2)
		var v: Vector2 = Vector2.from_angle(a) * g.vrng.randf_range(70.0, 170.0)
		var l: float = g.vrng.randf_range(0.45, 0.8)
		sparks.append([p, v, maxf(ground_y, p.y + 2.0), l, l, c])


func step(dt: float) -> void:
	if g != null and visibility_layer != g.visibility_layer:
		visibility_layer = g.visibility_layer   # 跟世界节点同一可见层（光学观感低分辨率层开着时 = 第 2 位；本节点比 _set_lo 晚挂上）
	_frame_n.clear()
	var n: int = pos.size()
	var k := 0
	for i in n:
		var l: float = life[i] - dt
		if l <= 0.0:
			continue
		var t: Dictionary = TEMPLATES[_names[tpl[i]]]
		var v: Vector2 = vel[i]
		v.y += float(t.grav) * dt
		v *= maxf(0.0, 1.0 - float(t.drag) * dt)
		pos[k] = pos[i] + v * dt
		vel[k] = v
		life[k] = l
		lmax[k] = lmax[i]
		col[k] = col[i]
		tpl[k] = tpl[i]
		k += 1
	if k < n:
		pos.resize(k)
		vel.resize(k)
		life.resize(k)
		lmax.resize(k)
		col.resize(k)
		tpl.resize(k)
	var m := 0
	for s in sparks:
		var p: Vector2 = s[0]
		var v: Vector2 = s[1]
		if p.y < float(s[2]):
			v.y += 520.0 * dt
			v *= maxf(0.0, 1.0 - 1.2 * dt)
			p += v * dt
			if p.y >= float(s[2]):
				p.y = float(s[2])   # 落到地面高度：停住
				v = Vector2.ZERO
		s[0] = p
		s[1] = v
		s[3] = float(s[3]) - dt
		if float(s[3]) > 0.0:
			sparks[m] = s
			m += 1
	sparks.resize(m)
	if k > 0 or m > 0 or _drawn:
		queue_redraw()


func _draw() -> void:
	_drawn = pos.size() > 0 or sparks.size() > 0
	var sz := Vector2(2, 2)
	for i in pos.size():
		var age: float = 1.0 - life[i] / lmax[i]   # 0 → 1
		var rp: Array = _ramps[tpl[i]]
		var rc: Color = rp[0][1]
		for st in rp:
			if age >= float(st[0]):
				rc = st[1]
		var c: Color = col[i]
		var hot: float = maxf(0.0, rc.r - 1.0) * 0.5   # 热阶往白里提
		draw_rect(Rect2((pos[i] * 0.5).floor() * 2.0, sz), Color(c.r * rc.r + hot, c.g * rc.g + hot, c.b * rc.b + hot, rc.a))
	for s in sparks:
		var u: float = float(s[3]) / float(s[4])   # 1 → 0
		var c: Color = s[5]
		# 冷却三阶：热白 → 本色 → 暗；落地后（速度为 0）直接进暗阶
		var landed: bool = (s[1] as Vector2) == Vector2.ZERO
		var kk: float = 1.8 if u > 0.7 and not landed else (1.0 if u > 0.4 and not landed else 0.45)
		var a: float = 1.0 if u > 0.15 else u / 0.15
		var add: float = 0.6 if kk > 1.5 else 0.0
		draw_rect(Rect2(((s[0] as Vector2) * 0.5).floor() * 2.0, sz), Color(minf(2.0, c.r * kk + add), minf(2.0, c.g * kk + add), minf(2.0, c.b * kk + add), a))


## 兼容旧调用：GPU 版要在这里写贴图，CPU 版颗粒在 push 时就生成
func flush() -> void:
	pass
