## 画面观感预设（用户 10-12「我觉得整体都有点白灰」；量测与对照 tools/look_contrast.py）：一个旋钮 render/look（0–4）切整套参数，
## 只改画面，不碰对局（同 seed TRACE 不变）。各档逐级叠加：
##   0 现状：主控本体被灯火乘到 R×1.5 G×1.4 B×1.2 再乘亮度 110% × ambient_gain，脸 / 白色截成纯白
##   1 + 角色受光封顶：干员 / 博士 / 敌人本体按所在位置的灯火倍率整体缩放（保色相），软膝封到 actor_cap
##   2 + 亮度缺省 100%（设置里的亮度滑杆照旧可调，只是缺省值不同）
##   3 + 后期曲线：暗部伽马（中暗调压回去，黑位本来就是黑的不动）、高光软肩（亮度 > 1 时不硬截白）、
##       辉光门槛提高、远景光束（加法层乳白雾）减淡到 60%
##   4 + 鲜艳度（灰的多加、已饱和 / 近截顶的少加）
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
	"shoulder": 0.0, "sat": 0.0, "bloom_th": 0.84, "god": 1.0}
const PRESETS := [
	{},
	{"actor_cap": 1.12, "actor_knee": 0.9},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0, "toe": 1.15, "shoulder": 0.8, "bloom_th": 0.92, "god": 0.6},
	{"actor_cap": 1.12, "actor_knee": 0.9, "bright_def": 1.0, "toe": 1.15, "shoulder": 0.8, "bloom_th": 0.92, "god": 0.6, "sat": 0.18},
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


static func actor_mod(g, pos: Vector2) -> Color:
	if _cap < 0.0:   # 开局读一次（每只敌人每帧都要调，别每次查字典 / 拆路径）
		_cap = p("actor_cap")
		_knee = p("actor_knee")
		_gain = Bal.v("render/ambient_gain", 1.0)
	var cap := _cap
	if cap <= 0.0 or g.lamp_light == null or not g.lamp_light.visible or not g.lamp_light.enabled:
		return Color.WHITE
	var L: PointLight2D = g.lamp_light
	var amb: Color = g.map.ambient
	var c := pos + Vector2(0, -16.0) - L.position   # 本体中心约在脚底上方 16 世界像素
	var d := c.length()
	var a := _atten(L.texture, d / maxf(L.texture_scale, 0.001)) * L.energy
	if A.normal_maps:
		a *= L.height / sqrt(d * d + L.height * L.height)
	var br: float = Cfg.brightness * _gain
	var mx := maxf(amb.r + L.color.r * a, maxf(amb.g + L.color.g * a, amb.b + L.color.b * a)) * br
	var s := knee_scale(mx, _knee, cap)
	return Color(s, s, s, 1.0)


## 软膝：屏幕倍率 mx 过了 knee 之后按指数曲线趋近 cap，返回要乘的缩放（≤ 1；mx ≤ knee 时 = 1）
static func knee_scale(mx: float, knee: float, cap: float) -> float:
	if mx <= knee or mx <= 0.0:
		return 1.0
	var room := maxf(cap - knee, 0.001)
	return (knee + room * (1.0 - exp(-(mx - knee) / room))) / mx
