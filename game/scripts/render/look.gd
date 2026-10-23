## 画面观感预设（用户 10-12「我觉得整体都有点白灰」；量测与对照 tools/look_contrast.py）：一个旋钮 render/look（0–4）切整套参数，
## 只改画面，不碰对局（同 seed TRACE 不变）。各档逐级叠加：
##   0 现状：主控本体被灯火乘到 R×1.5 G×1.4 B×1.2 再乘亮度 110% × ambient_gain，脸 / 白色截成纯白
##   1 + 角色受光封顶：干员 / 博士 / 敌人本体按所在位置的灯火倍率整体缩放（保色相），软膝封到 actor_cap
##   2 + 亮度缺省 100%（设置里的亮度滑杆照旧可调，只是缺省值不同）
##   3 + 后期曲线：暗部伽马（中暗调压回去，黑位本来就是黑的不动）、高光软肩（亮度 > 1 时不硬截白）、
##       辉光门槛提高、远景光束（加法层乳白雾）减淡到 60%
##   4 + 鲜艳度（灰的多加、已饱和 / 近截顶的少加）
##   5 + 白色不偏黄发灰（用户 10-12「浊心斯卡蒂的色调怎么有点偏黄发灰」）：actor_neutral 0.7 + white_lift 1（见下）
## 白色偏黄发灰（用户 10-12「浊心斯卡蒂的色调怎么有点偏黄发灰」）两个独立旋钮，缺省 0 = 不改：
##   actor_tint：角色本体接收灯火的强度不变、颜色去暖——灯色朝白色插值这么多（0–1），地面 / 场景照旧暖光
##   actor_neutral：只去暖不加冷——本体受光倍率（ambient + 灯）里 G / B 低于 R 的部分按这个比例补到 R（0–1）；
##               灯下的暖白回到中性，离灯远、ambient 偏蓝的地方不动（不会像 actor_tint 那样把队友推成蓝灰）
##   white_lift：白色保护——干员本体近白、低饱和的贴图像素按逐像素高光软肩走（可到 ~0.95–1.0），
##               中间调照旧走 actor_cap 软膝（不让 L4 修好的脸 / 中间调截白回来）；用 shaders/actor_light.gdshader
## 调试（只 debug 构建）：--bal=render/look=N 切档，--bal=render/look_<键>=值 单项覆盖；
## --lookdbg=nolamp,nonormal,nobloom,nofilter,nodof,nogod,nooutline,noflash,bright=1.0 逐项关掉某一层，
## 量各层对「白灰」的贡献（tools/look_contrast.py）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const A = preload("res://scripts/art.gd")

## 每档参数（缺省值 = 现状）。actor_cap / actor_knee 是「屏幕上最终倍率」（灯火 × 后期亮度）的封顶与起弯点；
## black = 黑位（减掉再拉伸），toe = 暗部伽马（>1 压暗部，只作用在 pivot 以下），shoulder = 高光起弯点（0 = 不压），
## sat = 饱和度增量，bloom_th = 辉光门槛，bright_def = 设置里亮度滑杆的缺省值
const BASE := {"actor_cap": 0.0, "actor_knee": 1.0, "bright_def": 1.1, "black": 0.0, "toe": 1.0, "pivot": 0.35,
	"shoulder": 0.0, "sat": 0.0, "bloom_th": 0.84, "god": 1.0,
	"actor_tint": 0.0, "actor_neutral": 0.0, "white_lift": 0.0, "white_sh": 0.8, "white_gain": 1.0}
const PRESETS := [
	{},
	{"actor_cap": 1.12, "actor_knee": 0.9},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0, "toe": 1.15, "shoulder": 0.8, "bloom_th": 0.92, "god": 0.6},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0, "toe": 1.15, "shoulder": 0.8, "bloom_th": 0.92, "god": 0.6, "sat": 0.18},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0, "toe": 1.15, "shoulder": 0.8, "bloom_th": 0.92, "god": 0.6, "sat": 0.18,
		"actor_neutral": 0.7, "white_lift": 1.0},
]

static var _p: Dictionary = {}
static var _dbg: Dictionary = {}
static var _dbg_read := false


static func level() -> int:
	return clampi(Bal.vi("render/look", 0), 0, PRESETS.size() - 1)


static func p(key: String) -> float:
	if _p.is_empty():
		_p = BASE.duplicate()
		_p.merge(PRESETS[level()], true)
	# 单项微调（调参用，也可写进 balance.json）：render/look_<键>，例如 --bal=render/look_actor_cap=1.1
	return Bal.v("render/look_" + key, float(_p.get(key, 0.0)))


## --lookdbg=a,b,bright=1.0：逐层开关（调试量测用）；发布版恒空
static func dbg(key: String) -> String:
	if not _dbg_read:
		_dbg_read = true
		for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
			if a.begins_with("--lookdbg="):
				for t in a.substr(10).split(","):
					var kv: PackedStringArray = t.split("=")
					_dbg[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return str(_dbg.get(key, ""))


## 灯火贴图（art/px/light.png，128×128，中心到边 64 格）的径向衰减表；PointLight2D 按 texture_scale 放大采样
static var _lut: PackedFloat32Array = PackedFloat32Array()


static func _atten(tex: Texture2D, d_tex: float) -> float:
	if _lut.is_empty():
		_lut.resize(65)
		var img: Image = tex.get_image() if tex != null else null
		if img != null and img.is_compressed():
			img.decompress()
		for i in 65:
			if img == null:
				_lut[i] = clampf(1.0 - i / 64.0, 0.0, 1.0)
			else:
				var cx := mini(img.get_width() / 2 + i, img.get_width() - 1)
				var c := img.get_pixel(cx, img.get_height() / 2)
				_lut[i] = c.a * c.r
	var f := clampf(d_tex, 0.0, 64.0)
	var i0 := int(f)
	var i1 := mini(i0 + 1, 64)
	return lerpf(_lut[i0], _lut[i1], f - i0)


## 角色本体的受光封顶：返回乘在本体 modulate 上的缩放色（1 = 不变）。
## 倍率 m = ambient + 灯色 × 能量 × 衰减（× 法线光照的平面项），再乘后期亮度得屏幕倍率 M；
## M 的最大通道过了 actor_knee 后按软膝压到 actor_cap 以内，三通道同比例缩（灯光的暖色相保留）
static var _cap := -1.0
static var _knee := 1.0
static var _gain := 1.0
static var _tint := 0.0
static var _neu := 0.0
static var _wl := 0.0


static func _read() -> void:
	_cap = p("actor_cap")
	_knee = p("actor_knee")
	_gain = Bal.v("render/ambient_gain", 1.0)
	_tint = clampf(p("actor_tint"), 0.0, 1.0)
	_neu = clampf(p("actor_neutral"), 0.0, 1.0)
	_wl = p("white_lift")


## actor_tint > 0 时三通道不再同比例：每通道再乘 (ambient + 去暖灯色 × a) / (ambient + 灯色 × a)，软膝按去暖后的最大通道算。
## raw = true：只要去暖那一项、不封顶（白色保护开着时干员由 actor_light.gdshader 逐像素封顶）
## 每帧一份的灯火参数缓存（性能，docs/50 §11）：actor_mod 每只敌人每帧都调，原来每次都读十来个灯光节点属性 / 设置。
## 灯光只在 _process（world.update_visuals、开场演出）里改，绘制阶段不变；按「哪个 game 实例 + 第几帧」失效（图鉴演示是另一个实例）
static var _fc_frame := -1
static var _fc_g: Object = null
static var _fc_on := false
static var _fc_lpos := Vector2.ZERO
static var _fc_ltex: Texture2D = null
static var _fc_lscale := 1.0
static var _fc_lenergy := 1.0
static var _fc_lh := 0.0
static var _fc_lcol := Color.WHITE
static var _fc_amb := Color.WHITE
static var _fc_br := 1.0


static func _fc_fill(g) -> void:
	var f: int = Engine.get_process_frames()
	if f == _fc_frame and is_same(_fc_g, g):
		return
	_fc_frame = f
	_fc_g = g
	var L: PointLight2D = g.lamp_light
	_fc_on = L != null and L.visible and L.enabled
	if not _fc_on:
		return
	_fc_lpos = L.position
	_fc_ltex = L.texture
	_fc_lscale = L.texture_scale
	_fc_lenergy = L.energy
	_fc_lh = L.height
	_fc_lcol = L.color
	_fc_amb = g.map.ambient
	_fc_br = Cfg.brightness * _gain


static func actor_mod(g, pos: Vector2, raw := false) -> Color:
	if _cap < 0.0:   # 开局读一次（每只敌人每帧都要调，别每次查字典 / 拆路径）
		_read()
	var cap := _cap
	if cap <= 0.0 and _tint <= 0.0 and _neu <= 0.0:
		return Color.WHITE
	_fc_fill(g)
	if not _fc_on:
		return Color.WHITE
	var c := pos + Vector2(0, -16.0) - _fc_lpos   # 本体中心约在脚底上方 16 世界像素
	var d := c.length()
	var a := _atten(_fc_ltex, d / maxf(_fc_lscale, 0.001)) * _fc_lenergy
	if A.normal_maps:
		a *= _fc_lh / sqrt(d * d + _fc_lh * _fc_lh)
	return _actor_mod_tail(a, _fc_amb, _fc_lcol, _fc_br, cap, raw)


## 敌人逐只调用的快速版（性能 docs/50 §14，OPT_EDRAW）：每帧排序层开画前 actor_mod_begin(g) 一次——判开关、填灯光缓存；
## 返回 1 = 恒为白（同 actor_mod 的提前返回），2 = 逐只用 actor_mod_at（算式同 actor_mod）
static func actor_mod_begin(g) -> int:
	if _cap < 0.0:
		_read()
	if _cap <= 0.0 and _tint <= 0.0 and _neu <= 0.0:
		return 1
	_fc_fill(g)
	return 2 if _fc_on else 1


static func actor_mod_at(pos: Vector2) -> Color:
	var c := pos + Vector2(0, -16.0) - _fc_lpos
	var d := c.length()
	var a := _atten(_fc_ltex, d / maxf(_fc_lscale, 0.001)) * _fc_lenergy
	if A.normal_maps:
		a *= _fc_lh / sqrt(d * d + _fc_lh * _fc_lh)
	return _actor_mod_tail(a, _fc_amb, _fc_lcol, _fc_br, _cap, false)


## 整屏统一算一次（docs/50 §15 D2，OPT_LIGHT）：受光封顶只跟「到灯的距离」有关（同一帧灯的位置 / 半径 / 能量 / 颜色、ambient、亮度都一样），
## 每帧在 actor_mod_begin 之后按距离建一张 LUT_N + 1 格的表（灯火贴图半径 64 格均分，每格的值按 actor_mod_at 同一算式），
## 逐只敌人只算到灯的距离、查表线性插值（原来每只都走衰减表 + 法线项 + 软膝的三层函数）。灯外（贴图半径以外）取表末格。
## 与逐只算的差别只在格与格之间的插值（亮度差远小于 1/255 量级），见 docs/50 §15 截图
const LUT_N := 32
static var _lt := PackedColorArray()
static var _lt_inv := 0.0

static func actor_mod_lut_build() -> void:
	if _lt.size() != LUT_N + 1:
		_lt.resize(LUT_N + 1)
	var span: float = 64.0 * maxf(_fc_lscale, 0.001)   # 灯火贴图半径（世界像素）
	for i in LUT_N + 1:
		var d: float = span * float(i) / float(LUT_N)
		var a := _atten(_fc_ltex, d / maxf(_fc_lscale, 0.001)) * _fc_lenergy
		if A.normal_maps:
			a *= _fc_lh / sqrt(d * d + _fc_lh * _fc_lh)
		_lt[i] = _actor_mod_tail(a, _fc_amb, _fc_lcol, _fc_br, _cap, false)
	_lt_inv = float(LUT_N) / span


static func actor_mod_lut(pos: Vector2) -> Color:
	var f: float = (pos + Vector2(0, -16.0) - _fc_lpos).length() * _lt_inv
	if f >= LUT_N:
		return _lt[LUT_N]
	var i := int(f)
	return _lt[i].lerp(_lt[i + 1], f - i)



static func _actor_mod_tail(a: float, amb: Color, lcol: Color, br: float, cap: float, raw: bool) -> Color:
	if _neu > 0.0:
		# 去暖：G / B 往 R 补（只补低于 R 的部分），最大通道不变 → 软膝缩放和不去暖时一样
		var rr := amb.r + lcol.r * a
		var rg := amb.g + lcol.g * a
		var rb := amb.b + lcol.b * a
		var s3 := knee_scale(maxf(rr, maxf(rg, rb)) * br, _knee, cap) if cap > 0.0 and not raw else 1.0
		return Color(s3, s3 * (1.0 + _neu * maxf(rr - rg, 0.0) / maxf(rg, 0.001)), s3 * (1.0 + _neu * maxf(rr - rb, 0.0) / maxf(rb, 0.001)), 1.0)
	if _tint <= 0.0:
		var mx := maxf(amb.r + lcol.r * a, maxf(amb.g + lcol.g * a, amb.b + lcol.b * a)) * br
		var s := knee_scale(mx, _knee, cap) if cap > 0.0 and not raw else 1.0
		return Color(s, s, s, 1.0)
	var lc: Color = lcol.lerp(Color.WHITE, _tint)
	var tr := amb.r + lc.r * a
	var tg := amb.g + lc.g * a
	var tb := amb.b + lc.b * a
	var s2 := knee_scale(maxf(tr, maxf(tg, tb)) * br, _knee, cap) if cap > 0.0 and not raw else 1.0
	return Color(s2 * tr / maxf(amb.r + lcol.r * a, 0.001), s2 * tg / maxf(amb.g + lcol.g * a, 0.001),
		s2 * tb / maxf(amb.b + lcol.b * a, 0.001), 1.0)


## 干员本体的最终 modulate：白色保护关 = col × actor_mod；开 = col × 去暖项，RGB 取负作「走逐像素受光」标记
## （actor_light.gdshader 的 vertex() 认负号、还原，再按像素位置算灯火倍率与软膝 / 白色软肩）。col 的 RGB 须 ≥ 0
static func op_mod(g, pos: Vector2, col: Color) -> Color:
	if _cap < 0.0:
		_read()
	if _wl <= 0.0 or g.get("actor_mat") == null:
		return col * actor_mod(g, pos)
	var m: Color = col * actor_mod(g, pos, true)
	if g.lamp_light == null or not g.lamp_light.visible or not g.lamp_light.enabled:
		return m
	return Color(-m.r, -m.g, -m.b, m.a)


## 白色保护的材质（挂在 game 节点上，只有 RGB 为负的绘制走逐像素受光，其余原样）；white_lift = 0 时不建
static func make_actor_mat() -> ShaderMaterial:
	if _cap < 0.0:
		_read()
	if _wl <= 0.0:
		return null
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/actor_light.gdshader")
	m.set_shader_parameter("knee", _knee)
	m.set_shader_parameter("cap", _cap)
	m.set_shader_parameter("white_lift", _wl)
	m.set_shader_parameter("white_sh", p("white_sh"))
	m.set_shader_parameter("white_gain", p("white_gain"))
	m.set_shader_parameter("use_nm", 1.0 if A.normal_maps else 0.0)
	m.set_shader_parameter("rim", Bal.v("render/rim", 0.0))   # 朝灯边缘亮线原型（docs/127，缺省 0 = 关）
	m.set_shader_parameter("rim_px", Bal.v("render/rim_px", 2.0))
	m.set_shader_parameter("rim_floor", Bal.v("render/rim_floor", 0.15))
	return m


## 每帧把灯火状态推给白色保护材质（灯跟着主控走、半径随灯火变）
static func update_actor_mat(g) -> void:
	var m: ShaderMaterial = g.get("actor_mat")
	if m == null:
		return
	var L: PointLight2D = g.lamp_light
	var on: bool = L != null and L.visible and L.enabled
	m.set_shader_parameter("lamp_on", 1.0 if on else 0.0)
	if not on:
		return
	m.set_shader_parameter("lamp_tex", L.texture)
	m.set_shader_parameter("lamp_pos", L.position)
	m.set_shader_parameter("lamp_scale", L.texture_scale)
	m.set_shader_parameter("lamp_energy", L.energy)
	m.set_shader_parameter("lamp_h", L.height)
	var lc: Color = L.color.lerp(Color.WHITE, _tint)
	m.set_shader_parameter("lamp_col", Vector3(lc.r, lc.g, lc.b))
	var amb: Color = g.map.ambient
	m.set_shader_parameter("amb", Vector3(amb.r, amb.g, amb.b))
	m.set_shader_parameter("br", Cfg.brightness * _gain)


## 软膝：屏幕倍率 mx 过了 knee 之后按指数曲线趋近 cap，返回要乘的缩放（≤ 1；mx ≤ knee 时 = 1）
static func knee_scale(mx: float, knee: float, cap: float) -> float:
	if mx <= knee or mx <= 0.0:
		return 1.0
	var room := maxf(cap - knee, 0.001)
	return (knee + room * (1.0 - exp(-(mx - knee) / room))) / mx
