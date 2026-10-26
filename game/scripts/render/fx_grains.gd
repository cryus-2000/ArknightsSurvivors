## 像素粒子模板（10-24 协调人单 / 用户「先做能稳做的，考虑网页端性能」，docs/136）：特效「粒子化」的可复用积木。
## CPU 颗粒 + 一个画布批绘（本节点 _draw 里 draw_rect，2×2 世界像素 = 640×360 世界格上的 1 格），挂在世界节点下进低分辨率层。
## 复用 CPU 池；GPU 可见层问题已在 main 修复。网页 / 桌面性能仍需分别验证。
## 模板参数（TEMPLATES）：ramp 颜色阶（硬边：按年龄落在哪一段就用哪一段的色，不插值；值 > 1 = 发光）、life 寿命 / life_rand 散布、
##   speed 初速区间、spread 散射角（度）、grav 重力、drag 阻力（惯性：越小飘越远）、per_frame 单帧新增上限；
##   budget 每档画质同屏上限（高 / 中；低画质不开，调用方退回非粒子画法）。超预算时新颗粒直接丢（不挤掉旧的），单帧超上限均匀抽稀由调用方做。
## 另带 CPU 火星（spark）：带重力、落到「地面高度」（物体脚底 y）停住、冷却变暗后熄灭——俯视游戏没有真碰撞，按脚底 y 处理。
## 只用 g.vrng（画面随机流），不碰玩法随机数
extends Node2D

const Bal = preload("res://scripts/core/balance.gd")
# 形状颗粒化（10-24 用户「斯卡蒂的那个能不能根据形状改成粒子的」，docs/138 §13）：这些帧条不画贴图，每换一帧按这一帧的
# 可见像素在 2 px 世界格上生成颗粒（刀光模板：热白 → 本色冷却散开），形状由颗粒拼出来。开关 fx/grain_body
const GRAIN_BODY := {"fx_slash_heavy_deep": true}

const TEMPLATES := {
	# 刀光：热白 → 亮本色 → 本色 → 冷暗四阶，带挥刀惯性散开、轻微下落、逐颗熄灭
	"slash": {"ramp": [[0.0, Color(2.0, 2.0, 2.0, 1)], [0.12, Color(1.35, 1.35, 1.35, 1)], [0.38, Color(0.9, 0.9, 0.9, 1)], [0.7, Color(0.45, 0.45, 0.5, 0.9)]],
		"life": 0.3, "life_rand": 0.45, "speed": Vector2(10, 46), "spread": 26.0, "grav": 80.0, "drag": 5.0, "per_frame": 140, "budget": [900, 450]},
}
# 材质仅改变颗粒运动与冷却，所有材质共享 slash 的总预算。
const MATERIALS := {
	"blade": {"life": 0.42, "life_rand": 0.2, "speed": Vector2(90, 175), "spread": 9.0, "grav": 35.0, "drag": 2.8, "per_frame": 144,
		"ramp": [[0.0, Color(1.2, 1.2, 1.2)], [0.25, Color(0.85, 0.95, 1)], [0.6, Color(0.4, 0.55, 0.65, 0.8)], [0.85, Color(0.2, 0.3, 0.35, 0.35)]]},
	"lava": {"life": 0.4, "life_rand": 0.2, "speed": Vector2(25, 65), "spread": 60.0, "grav": 220.0, "drag": 3.0, "per_frame": 96,
		"ramp": [[0.0, Color(1.2, 1.0, 0.8)], [0.3, Color(0.8, 0.45, 0.25)], [0.7, Color(0.25, 0.15, 0.12, 0.7)]]},
	"fire": {"life": 0.38, "life_rand": 0.3, "speed": Vector2(8, 22), "spread": 22.0, "grav": -40.0, "drag": 6.0, "per_frame": 96,
		"ramp": [[0.0, Color(1.4, 1.3, 1.1)], [0.18, Color(1, 0.8, 0.6)], [0.55, Color(0.55, 0.35, 0.3)], [0.8, Color(0.25, 0.25, 0.25, 0.6)]]},
	"water": {"life": 0.34, "life_rand": 0.3, "speed": Vector2(8, 24), "spread": 40.0, "grav": 95.0, "drag": 5.5, "per_frame": 96,
		"ramp": [[0.0, Color(1.2, 1.2, 1.2)], [0.2, Color(0.9, 0.95, 1)], [0.7, Color(0.45, 0.55, 0.65, 0.65)]]},
	"electric": {"life": 0.1, "life_rand": 0.2, "speed": Vector2.ZERO, "spread": 0.0, "grav": 0.0, "drag": 0.0, "per_frame": 96,
		"ramp": [[0.0, Color(1.5, 1.5, 1.5)], [0.3, Color(1, 1, 1)], [0.7, Color(0.5, 0.55, 0.65, 0.7)]]},
	"fluid": {"life": 0.36, "life_rand": 0.25, "speed": Vector2(8, 24), "spread": 50.0, "grav": 95.0, "drag": 6.0, "per_frame": 96,
		"ramp": [[0.0, Color(1, 1.1, 1.1)], [0.25, Color(0.8, 0.9, 0.95)], [0.7, Color(0.35, 0.45, 0.5, 0.65)]]},
	# Boss 各幕常驻颗粒（docs/142b §8.2，render/boss_beam.act_look）：上升雾 / 下落屑 / 流入本体；转幕迸散一圈（不闪，docs/137）
	"mote_up": {"life": 1.1, "life_rand": 0.4, "speed": Vector2(6, 18), "spread": 30.0, "grav": -28.0, "drag": 1.2, "per_frame": 8,
		"ramp": [[0.0, Color(1.25, 1.25, 1.25, 0.9)], [0.3, Color(1, 1, 1, 0.8)], [0.75, Color(0.6, 0.6, 0.6, 0.45)]]},
	"mote_down": {"life": 1.1, "life_rand": 0.4, "speed": Vector2(4, 12), "spread": 20.0, "grav": 34.0, "drag": 1.2, "per_frame": 8,
		"ramp": [[0.0, Color(1.2, 1.2, 1.2, 0.9)], [0.35, Color(0.95, 0.95, 0.95, 0.8)], [0.75, Color(0.55, 0.55, 0.55, 0.45)]]},
	"mote_in": {"life": 0.9, "life_rand": 0.3, "speed": Vector2(55, 85), "spread": 6.0, "grav": 0.0, "drag": 0.4, "per_frame": 8,
		"ramp": [[0.0, Color(0.7, 0.7, 0.7, 0.5)], [0.4, Color(1, 1, 1, 0.85)], [0.85, Color(1.3, 1.3, 1.3, 0.9)]]},
	# Boss 结算特效颗粒化（render/world._bfx_grains）：迸散（快出、阻力大、慢慢升起变暗）/ 尘（慢、散得开、飘得久）
	"bfx_burst": {"life": 0.55, "life_rand": 0.35, "speed": Vector2(45, 130), "spread": 12.0, "grav": -10.0, "drag": 3.4, "per_frame": 160,
		"ramp": [[0.0, Color(1.35, 1.35, 1.35, 1)], [0.2, Color(1, 1, 1, 0.95)], [0.55, Color(0.62, 0.62, 0.62, 0.7)], [0.85, Color(0.32, 0.32, 0.32, 0.35)]]},
	"bfx_dust": {"life": 0.85, "life_rand": 0.4, "speed": Vector2(10, 42), "spread": 45.0, "grav": -16.0, "drag": 2.0, "per_frame": 120,
		"ramp": [[0.0, Color(1.1, 1.1, 1.1, 0.9)], [0.35, Color(0.8, 0.8, 0.8, 0.7)], [0.75, Color(0.45, 0.45, 0.45, 0.35)]]},
	# 激光 / 弹道沿线的短闪（用户 10-26「激光打完消失得慢」：≤ 0.22 秒收完）
	"bfx_flash": {"life": 0.22, "life_rand": 0.35, "speed": Vector2(20, 60), "spread": 25.0, "grav": 0.0, "drag": 4.0, "per_frame": 120,
		"ramp": [[0.0, Color(1.4, 1.4, 1.4, 1)], [0.3, Color(1, 1, 1, 0.85)], [0.7, Color(0.55, 0.55, 0.55, 0.4)]]},
	"mote_shed": {"life": 0.55, "life_rand": 0.35, "speed": Vector2(12, 34), "spread": 35.0, "grav": -22.0, "drag": 2.5, "per_frame": 14,
		"ramp": [[0.0, Color(1.3, 1.3, 1.3, 0.95)], [0.3, Color(1, 1, 1, 0.8)], [0.7, Color(0.5, 0.5, 0.5, 0.4)]]},
	"mote_burst": {"life": 0.6, "life_rand": 0.35, "speed": Vector2(70, 150), "spread": 8.0, "grav": 0.0, "drag": 3.5, "per_frame": 72,
		"ramp": [[0.0, Color(1.3, 1.3, 1.3, 1)], [0.25, Color(1, 1, 1, 0.9)], [0.7, Color(0.55, 0.55, 0.55, 0.5)]]},
}
# 只替换短命中效果，不接管地面预警、持续领域或触手本体。
# 10-24 第 2 批（docs/138 §7）：盘点后只加蓝水花。炮弹爆炸 / 日炎 / 维什戴尔炮击试过，用户看后定退回原版（原版更有冲击感、更省帧）；体液另两条（水母刺 / 血肉命中）也不加
const MATERIAL_FX := {"fx_flam_hit": "fire", "fx_water_splash": "water", "fx_corrode_hit": "fluid", "fx_eyja_lava_splash": "lava", "fx_eyja_ignite_hit": "fire", "fx_eyja_ignite_boom": "fire",
	"fx_splash_blue": "water",
	"fx_skadi_surge_release": "water", "fx_skadi_surge_hit": "water", "fx_skadi_surge": "water", "fx_skadi_leap_splash": "water"}
# 帧条后半段换颗粒（10-24 协调人转用户「斯卡蒂旧特效 Noita 重置」，docs/138 §11）：ob_fx 一次性帧条播到 [比例] 时，从当时那一帧迸出材质颗粒、
# 帧条 0.08 秒内淡出——形状由帧条前半段交代，原来的棋盘格抖动消散改由真颗粒做
const MAT_HANDOFF := {"fx_skadi_surge_release": 0.5, "fx_skadi_surge_hit": 0.4, "fx_skadi_surge": 0.67, "fx_skadi_leap_splash": 0.4}
const MAT_SHARE := 0.6   # 材质颗粒最多占共用预算的六成：留四成给刀光第四版，大混战时材质先退回帧条，刀光不被挤掉
var templates: Dictionary = TEMPLATES.duplicate(true)
var _samples := {}
var _art = null
const SPARK_MAX := [0, 120, 240]

var g
var level := 2      # 2 高 / 1 中 / 0 低（低 = 不开）
var off := false    # --grainab 同局轮换：true = 这一段退回第二版画法
var kill := false   # --stackab 第 1 位（docs/50 §26，仅测试）：整套 CPU 颗粒关，调用方退回非粒子画法
var mat_off := false   # --matab 同局轮换：true = 这一段材质颗粒关（只关材质，刀光第四版照旧）
# 颗粒（结构数组）：位置、速度、剩余寿命、总寿命、颜色、模板序号
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var lmax := PackedFloat32Array()
var delay := PackedFloat32Array()   # 待发射颗粒也占总预算，防止延迟队列绕过上限
var col := PackedColorArray()
var tpl := PackedInt32Array()
var _names: Array = []
var _ramps: Array = []   # 模板序号 → [[阈值（年龄比例）, 颜色], …]
var _frame_n := {}
var sparks: Array = []   # CPU 火星：[pos, vel, ground_y, life, max, col]
## 颗粒 / 火星上限的设备系数 adapt_k（10-27 起固定，docs/50 §36）：原来按帧时自适应、掉帧时每秒往下收到最低 0.35（docs/50 §26），
## 手机后期几乎一直贴在 0.35——也是「局中自动降特效」，用户要求去掉。现在启动时按设备定一次：手机网页 render/grains_mobile_k（0.35，
## 与原来手机后期实际得到的量相同，帧时不变），其余 1；局中不变
var adapt_k := 1.0
## 屏外不发（docs/50 §26）：镜头可见范围外扩 VIEW_PAD 世界像素，范围外的 push / spark 直接丢，整团材质颗粒按「已处理」返回（不退回帧条）
const VIEW_PAD := 64.0
var view := Rect2(-1e9, -1e9, 2e9, 2e9)
# 模板参数按序号缓存（每颗每帧不再查 Dictionary）
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _rt: Array = []   # 序号 → 颜色阶阈值（PackedFloat32Array）
var _rc: Array = []   # 序号 → 颜色阶颜色（PackedColorArray）
const RAMP_N := 4     # 颜色阶摊平成每模板 4 段（不足的用 2.0 阈值补，永远到不了）：_draw 里不再调函数、不再取子数组
var _rth := PackedFloat32Array()
var _rcol := PackedColorArray()
var _blade_i := -1
var _fire_i := -1
var _slash_i := -1
var lights: Array = []   # 颗粒簇登记的灯（docs/138 §8）：[pos, r, col, life, max]；optical._dyn_lights 当候选，同 12 灯预算
const LIGHT_MAX := 16
var _drawn := false


func setup(game) -> void:
	g = game
	level = {"high": 2, "mid": 1, "low": 0}.get(Cfg.quality, 2)
	if level == 1 and Bal.v("render/mid_full_fx", 1.0) > 0.0:
		level = 2   # 中档颗粒量同高档（render/mid_full_fx，docs/50 §26）：上限 900 / 火星 240（手机再乘固定的 adapt_k）
	templates.merge(MATERIALS)
	for name in templates:
		_names.append(name)
		_ramps.append(templates[name].ramp)
		_grav.append(float(templates[name].grav))
		_drag.append(float(templates[name].drag))
		var rt := PackedFloat32Array()
		var rc := PackedColorArray()
		for st in templates[name].ramp:
			rt.append(float(st[0]))
			rc.append(st[1])
		_rt.append(rt)
		_rc.append(rc)
		for j in RAMP_N:
			_rth.append(rt[j] if j < rt.size() else 2.0)
			_rcol.append(rc[mini(j, rc.size() - 1)])
	adapt_k = clampf(Bal.v("render/grains_mobile_k", 0.35), 0.05, 1.0) if Cfg.mobile_web() else 1.0
	_blade_i = _names.find("blade")
	_fire_i = _names.find("fire")
	_slash_i = _names.find("slash")


func on() -> bool:
	_knobs()
	return level > 0 and not kill and g != null and (g.optical_on or Cfg.quality == "low") and _k_grains


## 材质颗粒（fx/material_grains，10-24 起缺省开；拉普兰德 / 体液各自另有开关，缺省关）：模板开着、未被 --grainab / --matab 轮换关掉
func material_on() -> bool:
	return on() and not off and not mat_off and _k_mat


## fx/grains、fx/material_grains 每帧读一次（on() 每帧被调十几次；docs/50 §26）
var _k_frame := -1
var low_k := 1.0
var _low_acc := 0.0
var _k_grains := true
var _k_mat := false
func _knobs() -> void:
	var fr: int = Engine.get_process_frames()
	if fr == _k_frame:
		return
	# 档位每帧跟画质（10-26 晚：设置里换档要立刻生效）：高 2；中 2（render/mid_full_fx）或 1；低 1（用户「低档也要保留一点点粒子」，原来低 = 全关）
	var lv0: int = {"high": 2, "mid": 1, "low": 1}.get(Cfg.quality, 2)
	if Cfg.quality == "mid" and Bal.v("render/mid_full_fx", 1.0) > 0.0:
		lv0 = 2
	level = lv0
	# 低档的「少量」（10-27 用户「最低的特效保留一点点粒子效果，一点点不保留有点太干枯了」，docs/50 §36）：所有颗粒（命中火星、技能、Boss 特效）
	# 按中档的 render/low_grains（0.4）保留——push 按累加器均匀抽（不抽随机数），火星按颗数缩；后期与光学层照旧关
	low_k = clampf(Bal.v("render/low_grains", 0.4), 0.0, 1.0) if Cfg.quality == "low" else 1.0
	_k_frame = fr
	_k_grains = Bal.v("fx/grains", 1.0) > 0.0
	_k_mat = Bal.v("fx/material_grains", 0.0) > 0.0


func budget() -> int:
	# 低档：中档上限 × low_k（不再用旧的「中档减半」那一列，免得叠成更少）
	return int(float(TEMPLATES.slash.budget[0 if level >= 2 or low_k < 1.0 else 1]) * adapt_k * low_k)


## 每帧（step 开头）：镜头可见范围 → view（帧时自适应已删，见 adapt_k）
func _adapt(_dt: float) -> void:
	if g != null and g.cam != null and is_inside_tree():
		var vs: Vector2 = get_viewport().get_visible_rect().size / g.cam.zoom
		view = Rect2(g.cam.get_screen_center_position() - vs * 0.5, vs).grow(VIEW_PAD)


## 生成一颗：p 世界坐标、dir 初速基准方向（单位向量；模板 spread 内散开）、c 颜色（乘在颜色阶上）
func push(name: String, p: Vector2, dir: Vector2, c: Color, emit_delay := 0.0) -> void:
	if pos.size() >= budget() or not view.has_point(p):
		return
	if low_k < 1.0:
		_low_acc += low_k
		if _low_acc < 1.0:
			return
		_low_acc -= 1.0
	var t: Dictionary = templates.get(name, {})
	if t.is_empty():
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
	delay.append(maxf(0.0, emit_delay))
	col.append(c)
	tpl.append(_names.find(name))


## 颗粒簇登记一盏短灯（乌尔比安冲锋前沿等，docs/138 §8）：p 世界坐标、r 半径（世界像素）、c 颜色、life 秒；按剩余寿命线性变暗。纯画面
func light(p: Vector2, r: float, c: Color, life: float) -> void:
	if not on() or lights.size() >= LIGHT_MAX:
		return
	lights.append([p, r, c, life, life])


## CPU 火星：从 p 带重力迸出，落到 ground_y 停住、冷却变暗后熄灭（同屏上限 SPARK_MAX）
func spark(p: Vector2, ground_y: float, c: Color, n: int) -> void:
	if not on() or not view.has_point(p):
		return
	var smax: int = int(float(SPARK_MAX[level]) * adapt_k)
	if low_k < 1.0:
		n = maxi(1, roundi(float(n) * low_k))   # 低档少量（同 push）
	for i in n:
		if sparks.size() >= smax:
			return
		var a: float = -PI * 0.5 + (float(i) / maxf(1.0, float(n - 1)) - 0.5) * 2.4 + g.vrng.randf_range(-0.2, 0.2)
		var v: Vector2 = Vector2.from_angle(a) * g.vrng.randf_range(70.0, 170.0)
		var l: float = g.vrng.randf_range(0.45, 0.8)
		sparks.append([p, v, maxf(ground_y, p.y + 2.0), l, l, c])


func step(dt: float) -> void:
	if g != null and visibility_layer != g.visibility_layer:
		visibility_layer = g.visibility_layer   # 跟世界节点同一可见层（光学观感低分辨率层开着时 = 第 2 位；本节点比 _set_lo 晚挂上）
	_frame_n.clear()
	_adapt(dt)
	if kill and (pos.size() > 0 or sparks.size() > 0):
		pos.clear()
		vel.clear()
		life.clear()
		lmax.clear()
		delay.clear()
		col.clear()
		tpl.clear()
		sparks.clear()
		lights.clear()
	_lappland_step()
	var n: int = pos.size()
	var k := 0
	for i in n:
		var active_dt: float = maxf(0.0, dt - delay[i])
		var wait: float = maxf(0.0, delay[i] - dt)
		var l: float = life[i] - active_dt
		if l <= 0.0:
			continue
		var ti: int = tpl[i]
		var v: Vector2 = vel[i]
		v.y += _grav[ti] * active_dt
		v *= maxf(0.0, 1.0 - _drag[ti] * active_dt)
		pos[k] = pos[i] + v * active_dt
		vel[k] = v
		life[k] = l
		lmax[k] = lmax[i]
		delay[k] = wait
		col[k] = col[i]
		tpl[k] = tpl[i]
		k += 1
	if k < n:
		pos.resize(k)
		vel.resize(k)
		life.resize(k)
		lmax.resize(k)
		delay.resize(k)
		col.resize(k)
		tpl.resize(k)
	var lk := 0
	for L in lights:
		L[3] = float(L[3]) - dt
		if float(L[3]) > 0.0:
			lights[lk] = L
			lk += 1
	lights.resize(lk)
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
	var pt: int = Time.get_ticks_usec() if g != null and g.prof_on else 0
	_drawn = pos.size() > 0 or sparks.size() > 0
	var sz := Vector2(2, 2)
	for i in pos.size():
		if delay[i] > 0.0:
			continue
		# 颜色同 grain_color(i)，就地展开（每帧上千颗，省函数调用）
		var ti: int = tpl[i]
		var lf: float = life[i] / lmax[i]
		var age: float = 1.0 - lf
		var b: int = ti * RAMP_N
		var rc: Color = _rcol[b]
		if age >= _rth[b + 1]:
			rc = _rcol[b + 1]
			if age >= _rth[b + 2]:
				rc = _rcol[b + 2]
				if age >= _rth[b + 3]:
					rc = _rcol[b + 3]
		var c: Color = col[i]
		var gc: Color
		if ti == _fire_i and age >= 0.8:
			var ash: float = (c.r + c.g + c.b) / 3.0 * 0.22
			gc = Color(ash, ash, ash, c.a * 0.6)
		else:
			var hot: float = maxf(0.0, rc.r - 1.0) * 0.5
			gc = Color(c.r * rc.r + hot, c.g * rc.g + hot, c.b * rc.b + hot, c.a * rc.a)
		var p: Vector2 = (pos[i] * 0.5).floor() * 2.0
		if ti == _blade_i and lf > 0.45:
			draw_line(((pos[i] - vel[i] * 0.045) * 0.5).floor() * 2.0, p, gc, 2.0, false)
		else:
			draw_rect(Rect2(p, sz), gc)
	for s in sparks:
		var u: float = float(s[3]) / float(s[4])   # 1 → 0
		var c: Color = s[5]
		# 冷却三阶：热白 → 本色 → 暗；落地后（速度为 0）直接进暗阶
		var landed: bool = (s[1] as Vector2) == Vector2.ZERO
		var kk: float = 1.8 if u > 0.7 and not landed else (1.0 if u > 0.4 and not landed else 0.45)
		var a: float = 1.0 if u > 0.15 else u / 0.15
		var add: float = 0.6 if kk > 1.5 else 0.0
		draw_rect(Rect2(((s[0] as Vector2) * 0.5).floor() * 2.0, sz), Color(minf(2.0, c.r * kk + add), minf(2.0, c.g * kk + add), minf(2.0, c.b * kk + add), a))
	if pt > 0:
		g.prof["op_grains_draw"] = int(g.prof.get("op_grains_draw", 0)) + Time.get_ticks_usec() - pt


## 兼容旧调用：GPU 版要在这里写贴图，CPU 版颗粒在 push 时就生成
func flush() -> void:
	pass


## 首次缓存固定最多 16×16 个采样点；不逐帧读贴图，不建立新节点。
## 整个效果先验收预算：失败时调用方完整保留帧条，成功时不叠加原帧条/GPU爆发。
func material_burst(name: String, tx: Texture2D, frames: int, at: Vector2, angle: float, sc: float, anchor: Vector2, flip: bool, tint: Color, frame_at := -1) -> bool:
	if not material_on() or not MATERIAL_FX.has(name):
		return false
	var kind: String = MATERIAL_FX[name]
	if kind == "fluid" and Bal.v("fx/material_fluid", 0.0) <= 0.0:
		return false   # 体液单独一道开关（缺省关，balance.json fx._material_doc）
	if not view.grow(64.0).has_point(at):
		return true   # 整团在屏外（再外扩 64）：不发颗粒也不画帧条
	var skey: String = name if frame_at < 0 else "%s#%d" % [name, frame_at]   # frame_at：指定从哪一帧取形状（帧条交接用）
	if not _samples.has(skey):
		var img: Image = tx.get_image()
		if img == null or img.is_empty() or img.is_compressed():
			return false
		var fw: int = tx.get_width() / frames
		var fh: int = tx.get_height()
		var points: Array = []
		# 从前半段选可见采样最多的一帧，保留原贴图色和形状。
		for frame in ([frame_at] if frame_at >= 0 else range(mini(frames, 4))):
			var candidate: Array = []
			for y in 16:
				for x in 16:
					var px := mini(fw - 1, int((x + 0.5) * fw / 16.0))
					var py := mini(fh - 1, int((y + 0.5) * fh / 16.0))
					var color: Color = img.get_pixel(frame * fw + px, py)
					if color.a >= 0.5:
						candidate.append([Vector2(px, py), color])
			if candidate.size() > points.size():
				points = candidate
		_samples[skey] = points
	var source: Array = _samples[skey]
	var count := mini(source.size(), 48 if level >= 2 else 32)
	if count < 8 or pos.size() + count > int(budget() * MAT_SHARE) or int(_frame_n.get(kind, 0)) + count > int(templates[kind].per_frame):
		return false
	var cell: float = float(tx.get_width() / frames) / 16.0   # 采样格（贴图像素）：格内随机抖开，否则颗粒排成 16×16 点阵（10-24 验收录像可见）
	for i in count:
		var sample: Array = source[int(float(i) * source.size() / count)]
		var jit := Vector2(g.vrng.randf_range(-0.5, 0.5), g.vrng.randf_range(-0.5, 0.5)) * cell
		var offset: Vector2 = (sample[0] + jit - anchor) * sc
		if frame_at >= 0:
			pass   # 帧条交接：颗粒就落在当时看得到的像素上，不往里收
		elif kind == "water":
			offset *= 0.72
		elif kind == "fire":
			offset *= 0.7
		if flip:
			offset.x = -offset.x
		offset = offset.rotated(angle)
		var direction := offset.normalized()
		if kind == "fire":
			direction = Vector2.UP
		push(kind, at + offset, direction, sample[1] * tint, float(i % 6) * 0.05 if kind == "fire" else 0.0)
	return true


## 新生材质颗粒进入现有辉光层；不另建发光节点或粒子池。
func draw_material_glow(ci: CanvasItem) -> void:
	if not on() or off:
		return
	for i in pos.size():
		if delay[i] > 0.0 or tpl[i] == _slash_i:
			continue
		var age: float = 1.0 - life[i] / lmax[i]
		if age >= 0.4:
			continue
		var c: Color = col[i]
		c.a *= 0.5 * (1.0 - age / 0.4)
		ci.draw_rect(Rect2((pos[i] * 0.5).floor() * 2.0, Vector2(2, 2)), c)


func grain_color(i: int) -> Color:
	var age: float = 1.0 - life[i] / lmax[i]
	var ti: int = tpl[i]
	var rt: PackedFloat32Array = _rt[ti]
	var rcs: PackedColorArray = _rc[ti]
	var rc: Color = rcs[0]
	for j in rt.size():
		if age >= rt[j]:
			rc = rcs[j]
	var c: Color = col[i]
	if ti == _fire_i and age >= 0.8:
		# 最后转成无辉光的灰烬，不一直维持橙色发亮。
		var ash: float = (c.r + c.g + c.b) / 3.0 * 0.22
		return Color(ash, ash, ash, c.a * 0.6)
	var hot: float = maxf(0.0, rc.r - 1.0) * 0.5
	return Color(c.r * rc.r + hot, c.g * rc.g + hot, c.b * rc.b + hot, c.a * rc.a)


func _lappland_step() -> void:
	if not material_on() or Bal.v("fx/material_lappland", 0.0) <= 0.0 or not "squad" in g or g.squad == null:
		return
	var o = g.squad.get_op("lappland")
	if o == null:
		return
	for f in o.pfx:
		if str(f.get("name", "")) != "fx_lappland_slash" or f.get("material_preview_old", false) or f.get("slash_emitted", false):
			continue
		var elapsed: float = float(f.max) - float(f.life) - float(f.get("dly", 0.0))
		if elapsed < 0.16 or float(f.life) <= 0.0:
			continue
		f.slash_emitted = true
		var tx: Texture2D = g.tex.get("fx_lappland_slash")
		if tx == null:
			continue
		var key := "lappland_break"
		var fw: int = tx.get_width() / int(f.fr)
		var fh: int = tx.get_height()
		if not _samples.has(key):
			var img := tx.get_image()
			if img == null or img.is_compressed():
				continue
			var points: Array = []
			# 64格采样一次，取出手帧本身，避免凭空拼出另一道弧线。
			for y in 64:
				for x in 64:
					var px: int = mini(fw - 1, int((x + 0.5) * fw / 64.0))
					var py: int = mini(fh - 1, int((y + 0.5) * fh / 64.0))
					var c: Color = img.get_pixel(fw + px, py)
					if c.a >= 0.35:
						points.append([Vector2(px, py), c])
			_samples[key] = points
		var points: Array = _samples[key]
		var count: int = mini(points.size(), 72 if level >= 2 else 40)
		# 预算不足保留完整原帧条，不能先隐藏本体再漏发碎片。
		if count < 8 or pos.size() + count > int(budget() * MAT_SHARE) or int(_frame_n.get("blade", 0)) + count > int(templates.blade.per_frame):
			continue
		f.slash_material = true
		f.slash_break_at = elapsed
		for i in count:
			var sample: Array = points[int(float(i) * points.size() / count)]
			var local: Vector2 = (sample[0] / Vector2(fw, fh) - Vector2(0.5, 0.5)) * 64.0
			var offset: Vector2 = (local * float(f.sc)).rotated(float(f.ang))
			var dir: Vector2 = Vector2(1.0, local.y * 0.025).normalized().rotated(float(f.ang))
			push("blade", f.pos + offset, dir, sample[1] * Color(0.75, 0.85, 0.9, 1.0), float(i % 3) * 0.02)


## 形状颗粒化（GRAIN_BODY）：world 画 "sprite" 前调。返回 true = 这一帧由颗粒负责、不画贴图；
## 预算不够整帧颗粒时返回 false，照原样画贴图（不会出现半个形状）
func body_frame(f: Dictionary, fr: int, frames: int) -> bool:
	if not on() or off or f.get("gb_skip", false) or Bal.v("fx/grain_body", 0.0) <= 0.0 or not GRAIN_BODY.has(str(f.name)):
		return false
	if int(f.get("gb_fr", -1)) == fr:
		return bool(f.get("gb_ok", false))
	f["gb_fr"] = fr
	f["gb_ok"] = false
	var tx: Texture2D = g.tex.get(str(f.name))
	if tx == null:
		return false
	if _art == null:
		_art = load("res://scripts/art.gd")   # 运行时取：契约测试把本文件单独拷进最小工程，不能 preload art.gd
	var h: float = _art.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var sc: float = absf(float(f.scale)) / h   # 每个贴图像素的世界像素数
	var step: int = maxi(1, int(round(2.0 / maxf(0.01, sc))))   # 每 2 世界像素取一个样
	var key: String = "gb#%s#%d#%d" % [f.name, fr, step]
	if not _samples.has(key):
		var img: Image = tx.get_image()
		if img == null or img.is_empty() or img.is_compressed():
			return false
		var pts: Array = []
		for y in range(0, fh, step):
			for x in range(0, fw, step):
				var c: Color = img.get_pixel(fr * fw + x, y)
				if c.a >= 0.4:
					pts.append([Vector2(x, y), c])
		_samples[key] = pts
	var pts: Array = _samples[key]
	var n: int = mini(pts.size(), 160 if level >= 2 else 90)
	if n == 0:
		f["gb_ok"] = true
		return true
	if pos.size() + n > int(budget() * MAT_SHARE):
		return false
	var an: Vector2 = f.get("anchor", Vector2(fw, fh) / 2.0)
	var flip: bool = f.get("flip", false)
	var tint: Color = f.get("col", Color.WHITE)
	for i in n:
		var s: Array = pts[int(float(i) * pts.size() / n)]
		var o: Vector2 = (s[0] - an) * sc
		if flip:
			o.x = -o.x
		o = o.rotated(float(f.ang))
		push("slash", f.pos + o, o.normalized(), s[1] * tint)
	f["gb_ok"] = true
	return true
