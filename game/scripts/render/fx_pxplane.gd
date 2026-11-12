## pixelfx「转平面」试验（docs/246，11-05 用户「把 pixelfx 的二维平面转移到我们这个平面上来，再结合 Noita 特效」）：斯卡蒂（docs/246）、星熊（docs/254）、流明（docs/255）、艾雅法拉（docs/259）、水月（docs/261）、德克萨斯（docs/257）、歌蕾蒂娅（docs/263，单独文件 fx_pxplane_gl.gd），各自一节在文件末尾；逻各斯（docs/258）见文件末段。；归溟幽灵鲨（docs/268）在 fx_pxplane_su.gd。
## 开关 fx/px_plane（balance.json，缺省 0 = 关）：1 = 转平面版，2 = 旧做法原样贴（对照用，重现之前的问题）。
## 借配方系统（fx_recipe.gd）的接管：开着时 Fxr.owns(斯卡蒂) 为真，她原来的刀光 / 帧条 / pfx / 命中颗粒只跳过绘制（玩法照旧，TRACE 逐行一致）；
## 事件由 fx_recipe._ev 转到这里，颗粒（Noita 水滴）和照地光走 fx_recipe 的颗粒池与灯光预算。
## 转平面版的三条（对应协调人诊断的三个丑因）：
##   ① 视角：每招拆成贴地层（接触阴影、水痕、冲击环、积水；帧条生成时已按 GROUND_Y 压扁，地面层画、被单位挡）和立起层
##      （刀光幕、水柱、潮刃浪头；竖直，进 world 单位排序按脚底 y 排，脚下有接触阴影）；
##   ② 像素格：帧条按目标尺寸用 pixelfx 生成（tools/pxplane_bake.py），1 帧条像素 = 1 美术像素，游戏里只按 g.PX（2）整数放大、不旋转，
##      位置对齐 2 世界像素格；方向件按 5 个平面角预生成，另一半水平翻转；
##   ③ 吃光：色层当普通物体画（受 CanvasModulate 与光学层光照压暗 / 受光），最亮的热芯像素（emit 点表）进光学发光层；
##      命中 / 爆点挂一盏 ≤ 0.15 秒的照地点光（fx_recipe 灯光预算）。
##   ④ 帧率（协调人 11-05 补充）：统一一个动画时钟——帧条一律 15 fps 烘焙，选帧按全局节拍 floor(g.t × 15)（60 Hz 下每帧正好停 4 个游戏帧，
##      同屏所有件同一拍换帧）；潮刃 / 浪墙的位置也按同一 15 fps 节拍跳格、对齐美术像素格，不做 60 Hz 亚像素滑动；颗粒与光照旧平滑（颗粒位置取整到像素格）。
##      fx/px_plane_fps ≠ 15 时退回「各件自己的小数帧率 + 平滑位移」（帧率统一前后对照用）。
## 旧做法（2）：光晕烤进颜色的正俯视 / 正圆帧条，按判定半径小数缩放、按出手方向旋转，整张盖在所有单位上面（不排序、无阴影、无 emit），
##      帧率按旧帧条常见的小数帧率 fx/px_plane_raw_fps（缺省 12.8）播。
## 画面随机只用 g.vrng（颗粒）；本模块不抽随机数。
extends RefCounted

const PxU = preload("res://scripts/render/px_util.gd")   # 共用小工具（docs/286 §2）
const BatchCanvas = preload("res://scripts/characters/batch_canvas.gd")
const Bal = preload("res://scripts/core/balance.gd")
# 大部分帧条在读取时补上干员前缀，另四张表在烘焙时已把前缀写进键名。斯卡蒂的通用键没有统一前缀。
const META_PREFIXED := {
	"an": "angelina", "ey": "eyjafjalla", "ex": "exusiai", "gl": "gladiia",
	"ir": "irene", "ka": "kaltsit", "lg": "logos", "lm": "lumen", "lp": "lappland",
	"sa": "saria", "sk": "skalter", "su": "specter_unchained", "sz": "suzuran",
	"ul": "ulpianus", "wd": "wisadel",
}
const META_BAKED_PREFIX := {"hsg": "hoshiguma", "mz": "mizuki", "sg": "siege", "tx": "texas"}
const MI = preload("res://scripts/render/melee_impact.gd")   # 近战打击感包（docs/246 §11）：斩痕 / 照地光提亮
const ART := "res://art/fx/pxp/pxp_%s.png"
const IDS := {"logos": true, "skadi": true, "hoshiguma": true, "lumen": true, "eyjafjalla": true, "siege": true, "exusiai": true, "mizuki": true, "angelina": true, "saria": true, "texas": true, "gladiia": true, "ulpianus": true, "suzuran": true, "irene": true, "kaltsit": true, "wisadel": true, "skalter": true, "specter_unchained": true, "lappland": true}
const GL = preload("res://scripts/render/fx_pxplane_gl.gd")   # 歌蕾蒂娅一节（docs/263）单独成文件
const UL = preload("res://scripts/render/fx_pxplane_ul.gd")   # 乌尔比安一节（docs/266）单独成文件
const KA = preload("res://scripts/render/fx_pxplane_kal.gd")   # 凯尔希一节（docs/265）单独成文件
const SU = preload("res://scripts/render/fx_pxplane_su.gd")
const CUE = preload("res://scripts/render/fx_pxplane_cue.gd")   # 成长节点通用提示（docs/310 §2）   # 归溟幽灵鲨一节（docs/268）单独成文件
const TX = preload("res://scripts/render/fx_pxplane_tx.gd")   # 德克萨斯一节（docs/286 §4 拆出）
const SK = preload("res://scripts/render/fx_pxplane_sk.gd")   # 浊心斯卡蒂一节（docs/286 §4 拆出）
const MZ = preload("res://scripts/render/fx_pxplane_mz.gd")   # 水月一节（docs/286 §4 拆出）
const SG = preload("res://scripts/render/fx_pxplane_sg.gd")   # 推进之王一节（docs/286 §4 拆出）
const EY = preload("res://scripts/render/fx_pxplane_ey.gd")   # 艾雅法拉一节（docs/286 §4 拆出）
const LG = preload("res://scripts/render/fx_pxplane_lg.gd")   # 逻各斯一节（docs/286 §4 拆出）
const LM = preload("res://scripts/render/fx_pxplane_lm.gd")   # 流明一节（docs/286 §4 拆出）
const HSG = preload("res://scripts/render/fx_pxplane_hsg.gd")   # 星熊一节（docs/286 §4 拆出）
## 接管时仍照画的原 pfx 帧条（状态提示，不属于攻击特效）：星熊格挡闪光、反击架势盾沿光
const KEEP_PFX := {"hoshiguma": {"fx_hoshiguma_block": true, "fx_hoshiguma_guard_glow": true}, "gladiia": {"fx_gladiia_water_glide": true}}   # 歌蕾蒂娅水滑行是跑动拖尾，不属攻击特效
const DIRS := [-90, -45, 0, 45, 90]
const EMIT_CAP := 360     # 每帧送进发光层的 emit 点上限（整队）
const ITEM_MAX := 120   # 逻各斯（docs/258）消弹墨点 / 跳转笔较多：72 → 120

var g
var meta := {}
var _meta_loaded := {}
var tex := {}
var cues: Array = []      # 成长节点通用提示件（fx_pxplane_cue.gd，docs/310 §2）
# 一次性件按入场顺序存放；干员与立起层的视图引用同一批字典，跟随位置、一次性发光等改动两边都可见。
var _items_by_owner := {}
var _upright_items: Array = []
var items: Array = []:
	set(value):
		items = value
		_items_by_owner = {}
		_upright_items = []
		for it in items:
			_index_item(it)
var _mode := 0
var _mode_frame := -1
var _emit_n := 0
var _emit_frame := -1
var _ecol := {}
var _fol_tick := -1


static func of(game):
	if game == null:
		return null
	if game.has_meta("fx_pxplane"):
		return game.get_meta("fx_pxplane")
	var r = new()
	r.g = game
	game.set_meta("fx_pxplane", r)
	return r


## 0 关 / 1 转平面 / 2 旧做法原样贴（每帧读一次）
func mode() -> int:
	var fr: int = Engine.get_process_frames()
	if fr != _mode_frame:
		_mode_frame = fr
		_mode = 0 if g.headless_batch else clampi(int(Bal.v("fx/px_plane", 0.0)), 0, 2)
	return _mode


static func owns_id(game, oid: String) -> bool:
	if game == null or not IDS.has(oid):
		return false
	if oid in ["exusiai", "angelina", "saria", "suzuran", "irene", "kaltsit", "wisadel", "lappland"]:   # 能天使（docs/262）/ 安洁莉娜（docs/267）/ 塞雷娅（docs/269）/ 艾丽妮（docs/272）没有「旧做法原样贴」对照：2 = 不接管（当前游戏原样）
		return of(game).mode() == 1
	return of(game).mode() > 0


## 能天使一节（docs/262，单独文件 fx_pxplane_exu.gd；运行时 load 避免循环 preload）
var _exm = null


## 开火后坐（docs/262，只改画面）：character.draw_body 每帧每人调一次；不是能天使 / 没接管时返回 0
static func recoil(o) -> Vector2:
	if str(o.id) != "exusiai" or o.g == null or not o.g.has_meta("fx_pxplane"):
		return Vector2.ZERO
	var r = o.g.get_meta("fx_pxplane")
	if r.mode() != 1:
		return Vector2.ZERO
	return r._ex().kick(o)

func _ex():
	if _exm == null:
		_exm = load("res://scripts/render/fx_pxplane_exu.gd").new(self)
	return _exm
## 安洁莉娜一节（docs/267，单独文件 fx_pxplane_ang.gd；运行时 load 避免循环 preload）
var _anm = null


func _an():
	if _anm == null:
		_anm = load("res://scripts/render/fx_pxplane_ang.gd").new(self)
	return _anm


## world.gd 画悬浮敌人时调（docs/267，只画）：x = 影子缩放，y = 悬停上下浮动；不是安洁莉娜托起的 / 没接管时 (1, 0) = 原样
static func air_look(game, e: Dictionary) -> Vector2:
	if game == null or not game.has_meta("fx_pxplane"):
		return Vector2(1.0, 0.0)
	var r = game.get_meta("fx_pxplane")
	if r.mode() != 1:
		return Vector2(1.0, 0.0)
	if r._anm != null:
		var v: Vector2 = r._anm.air_look(e)
		if v != Vector2(1.0, 0.0):
			return v
	if r._irm != null:   # 艾丽妮挑起 / 掀起的敌人（docs/272）
		return r._irm.air_look(e)
	return Vector2(1.0, 0.0)
## 塞雷娅一节（docs/269，单独文件 fx_pxplane_sa.gd；运行时 load 避免循环 preload）
var _sam = null


func _sa():
	if _sam == null:
		_sam = load("res://scripts/render/fx_pxplane_sa.gd").new(self)
	return _sam
## 铃兰一节（docs/271，单独文件 fx_pxplane_sz.gd；运行时 load 避免循环 preload）
var _szm = null


func _szx():
	if _szm == null:
		_szm = load("res://scripts/render/fx_pxplane_sz.gd").new(self)
	return _szm

## 艾丽妮一节（docs/272，单独文件 fx_pxplane_ir.gd；运行时 load 避免循环 preload）
var _irm = null


func _ir():
	if _irm == null:
		_irm = load("res://scripts/render/fx_pxplane_ir.gd").new(self)
	return _irm

## 维什戴尔一节（docs/274，单独文件 fx_pxplane_wd.gd；运行时 load 避免循环 preload）
var _wdm = null


func _wd():
	if _wdm == null:
		_wdm = load("res://scripts/render/fx_pxplane_wd.gd").new(self)
	return _wdm


## 拉普兰德一节（docs/273，单独文件 fx_pxplane_lp.gd；运行时 load 避免循环 preload）
var _lpm = null


func _lp():
	if _lpm == null:
		_lpm = load("res://scripts/render/fx_pxplane_lp.gd").new(self)
	return _lpm


## ob_summon.sm_draw_over 转来（docs/273，只画）：拉普兰德接管时封印标记画成被斩断的符印、观察层数画成头顶刻痕。没接管返回 null
static func lp_marks(game):
	if not (game is Object) or not owns_id(game, "lappland"):
		return null
	return of(game)._lp()


func _meta(k: String) -> Dictionary:
	var cached = meta.get(k)
	if cached != null:
		return cached
	var prefix := k.get_slice("_", 0)
	var owner: String = META_PREFIXED.get(prefix, META_BAKED_PREFIX.get(prefix, "skadi"))
	if _meta_loaded.has(owner):
		return {}
	_meta_loaded[owner] = true
	var path := "res://data/pxp_%s.json" % owner
	var text: String
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	elif FileAccess.file_exists(path + ".gz"):
		# 网页主包常驻 MEMFS；只在首次用到这位干员时展开元数据。
		var packed := FileAccess.get_file_as_bytes(path + ".gz")
		text = packed.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	else:
		return {}
	var entries = JSON.parse_string(text)
	if entries is Dictionary:
		var key_prefix := prefix + "_" if META_PREFIXED.has(prefix) else ""
		for local_key in entries:
			if local_key != "_doc":
				meta[key_prefix + str(local_key)] = entries[local_key]
	return meta.get(k, {})


## 帧条按用到才读、60 秒（TEX_KEEP，局内时间）没画过就放掉（docs/287 §3 ⑥：原来读了整局不放，三人编队最重约 150 MB）；
## 再用到时重读（一张几 MB，几毫秒）。OPT_PXEVICT（--optold=536870912）置位不放
const TEX_KEEP := 60.0
var _tex_t := {}
var _tex_sweep := 0.0
var _strip_files := {}   # 只记导入资源是否存在；不持有贴图，也不改烘焙元数据

func _tex_evict() -> void:
	if g.opt_old & g.OPT_PXEVICT or g.t - _tex_sweep < 10.0:
		return
	_tex_sweep = g.t
	var drop: Array = []
	for k in _tex_t:
		if g.t - float(_tex_t[k]) > TEX_KEEP:
			drop.append(k)
	for k in drop:
		_tex_t.erase(k)
		tex.erase(k)


func _tex_path(k: String) -> String:
	return ART % k.replace("_d-", "_dm").to_lower()


func _tex(k: String) -> Texture2D:
	_tex_t[k] = g.t
	if not tex.has(k):
		var p := _tex_path(k)
		tex[k] = load(p) if ResourceLoader.exists(p) else null
		if _strip_files.has(k):
			_strip_files[k] = tex[k] != null
	return tex[k]


## 屏外仍须排队原有发光点：下一帧才合成，而且先排的点会占用整队预算。只确认资源存在，不解码 / 续期。
func _has_strip(k: String) -> bool:
	if tex.has(k):
		return tex[k] != null
	if not _strip_files.has(k):
		_strip_files[k] = ResourceLoader.exists(_tex_path(k))
	return _strip_files[k]


class ViewBounds:
	var transform := Transform2D.IDENTITY
	var viewport_rect := Rect2()
	var local_rect := Rect2()
	var valid := false

	func intersects(xf: Transform2D, area: Rect2, bounds: Rect2) -> bool:
		if xf != transform or area != viewport_rect:
			transform = xf
			viewport_rect = area
			valid = area.has_area() and not is_zero_approx(xf.determinant())
			if valid:
				local_rect = xf.affine_inverse() * area
		return not valid or local_rect.intersects(bounds, true)


var _main_view := ViewBounds.new()
var _low_view := ViewBounds.new()


func _strip_in_view(ci, bounds: Rect2, inherit_transform := false) -> bool:
	var target: CanvasItem
	if ci is BatchCanvas:
		target = ci.g
		if inherit_transform:
			if not ci.active:
				return true
			bounds = ci.xf * bounds
	else:
		# 裸画布和未合批画布的 draw_set_transform 可被调用方直写，Godot 没有查询接口。
		if inherit_transform:
			return true
		target = ci as CanvasItem
	if target == null or not target.is_inside_tree():
		return true
	if _main_view.intersects(target.get_global_transform_with_canvas(), target.get_viewport_rect(), bounds):
		return true
	if g.optical_lo:
		# 低分辨率层共享 World2D，画布平移取整、有额外边格；推镜时还可能保留较大的画布。
		var low: SubViewport = g.optical.lo_vp
		if low != null:
			return _low_view.intersects(low.canvas_transform * target.get_global_transform(), low.get_visible_rect(), bounds)
	return false


## 镜像 / 旋转画完会重置 draw transform。跳过颜色提交也保留该副作用；原图缺失时原来就不会重置。
func _reset_skipped_transform(ci, k: String) -> void:
	if ci is BatchCanvas and ci.active and ci.xf == Transform2D.IDENTITY:
		return
	if _has_strip(k):
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 动画时钟（fps）：15 = 统一节拍
func clock() -> float:
	return Bal.v("fx/px_plane_fps", 15.0)


## 帧号：统一节拍时按全局 15 fps 拍子数（同屏同拍换帧）；否则按自己的年龄 × 小数帧率
func frame_of(t0: float) -> int:
	var c: float = clock()
	if is_equal_approx(c, 15.0):
		return int(floor(g.t * 15.0)) - int(floor(t0 * 15.0))
	return int((g.t - t0) * c)


func tier(o) -> int:
	var f: float = Bal.v("fx/px_plane_tier", -1.0)   # 三档图用：强制某一档画面（只改画面）
	if f >= 0.0:
		return clampi(int(f), 0, 2)
	return clampi(int(o.elite), 0, 2)


## 平面角 → [预生成方向, 是否水平翻转]
static func pick_dir(ang: float) -> Array:
	var a: float = wrapf(rad_to_deg(ang), -180.0, 180.0)
	var flip := false
	if absf(a) > 90.0:
		a = wrapf(180.0 - a, -180.0, 180.0)
		flip = true
	var best: int = 0
	for d in DIRS:
		if absf(a - d) < absf(a - best):
			best = d
	return [best, flip]


static func _snap(v: Vector2) -> Vector2:
	return (v / 2.0).round() * 2.0


# ================================================================ 事件（fx_recipe._ev 转来；只记画面）

func ev(o, kind: String, d: Dictionary) -> void:
	if kind == "node_cue":   # 成长节点通用提示（docs/310 §2）：所有干员共用，不进各人分发
		if mode() == 1:
			CUE.push(self, o, d)
		return
	var raw: bool = mode() == 2
	var t: int = tier(o)
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var p: Dictionary = R.pal(o)
	if str(o.id) == "hoshiguma":
		HSG._ev_hsg(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "lumen":
		LM._ev_lumen(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "skalter":
		SK._ev_skalter(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "gladiia":
		GL.ev(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "ulpianus":
		UL.ev(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "eyjafjalla":
		EY._ev_ey(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "kaltsit":
		KA.ev(self, o, kind, d, t, R, p)
		return
	if str(o.id) == "specter_unchained":
		SU.ev(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "siege":
		SG._ev_sg(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "exusiai":
		_ex().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "texas":
		TX._ev_tx(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "mizuki":
		MZ._ev_mz(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "angelina":   # docs/267：没有「旧做法原样贴」对照，2 时同 1 不画（owns_id 只在 1 接管）
		_an().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "saria":
		_sa().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "logos":
		LG._ev_logos(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "suzuran":
		_szx().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "irene":
		_ir().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "wisadel":
		_wd().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "lappland":
		_lp().ev(o, kind, d, t, R, p)
		return
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			if Bal.v("fx/recipe_log", 0.0) > 0.0:
				print("PXPLOG %s %s %d %d %s" % [src, "c" if d.get("circle", false) else "%.2f" % float(d.get("half", 0.0)), Engine.get_process_frames(), int(d.get("r", 0.0)), "skill" if "skill" in d.get("tags", []) else "-"])
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 60.0))
				# 分支招各有各的样子（11-05 用户「分支招数能不能做出点差距出来」）
				if src == "大剑":   # 冲刺收尾的响应横扫（圆形）：按全向旋斩画
					_add(o, "spin_e%d" % t, c, 0.0, r, raw, "raw_spin_e%d" % t, 62.0)
				elif raw:
					_add_gd(o, "", c, raw, "raw_ring_e%d" % t, r, 60.0)
				elif src == "跃浪":   # 回澜：海水倒卷回脚下，汇到中心冲起一柱水
					_add_pair(o, "backwash", c)
				elif src == "涌潮" and r >= 160.0:   # 怒涛：悲歌结束环身一记大碎浪
					_add_pair(o, "nutao", c)
				elif src == "涌潮" and "skill" in d.get("tags", []):   # 怒涛：0.4 秒后的第二圈，更高 + 海绿
					_add_pair(o, "swell2", c)
				elif src == "涌潮":   # 涌潮：脚下涌出一圈矮水涌往外推
					_add_pair(o, "swell_e%d" % t, c)
				else:
					_add_gd(o, "pulse_e%d" % t, c, raw, "raw_ring_e%d" % t, r, 60.0)
				_burst(o, R, p, c + Vector2(0, -10), c.y + 4.0, d.get("es", []), 4 + 2 * t, 120.0, 0.45)
				return
			var ang: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 112.0))
			var dv := Vector2.from_angle(ang)
			var es: Array = d.get("es", [])
			match src:
				"大剑", "反手斩":
					if float(d.get("half", 1.4)) >= 3.1:
						var big: bool = r2 >= 160.0
						_add(o, "spin_s3" if big else "spin_e%d" % t, o.pos, 0.0, r2, raw, "raw_spin_e%d" % t, 62.0)
						_cuts(o, es, t, 3)
						_burst(o, R, p, o.pos + dv * r2 * 0.5 + Vector2(0, -12), o.pos.y + dv.y * r2 * 0.5 * 0.72, es, 3 + t, 110.0, 0.35)
					else:
						_add(o, "basic_e%d" % t, o.pos, ang, r2, raw, "raw_basic_e%d" % t, 56.0)
						_cuts(o, es, t, 2)
						_burst(o, R, p, o.pos + dv * r2 * 0.6 + Vector2(0, -12), o.pos.y + dv.y * r2 * 0.6 * 0.72, es, 2 + t, 90.0, 0.3)
				"迅捷打击·γ型":
					_add(o, "s1_e%d" % t, o.pos, ang, r2, raw, "raw_s1_e%d" % t, 73.0)
					_cuts(o, es, t, 4)
					_burst(o, R, p, o.pos + dv * r2 * 0.6 + Vector2(0, -14), o.pos.y + dv.y * r2 * 0.6 * 0.72, es, 4 + 2 * t, 140.0, 0.5)
					_s1_land(o, R, p, o.pos + Vector2(dv.x, dv.y * 0.72) * r2 * 0.55)
				"跃浪击":
					# 跃浪击（11-05 用户「每个技能要做出视觉上的区别」）：不用月牙，前方立起一道弧形水墙、往前卷倒拍下
					var at: Vector2 = o.pos + Vector2(dv.x, dv.y * 0.72) * r2 * 0.56
					var tt: int = maxi(t, 1)
					if raw:
						_add_up(o, "s2_e%d" % tt, at, raw, "raw_splash_e%d" % tt, r2, 75.0, ang)
					else:
						_add_dir(o, "s2_e%d" % tt, o.pos, ang)
					_burst(o, R, p, at + Vector2(0, -30), at.y, es, 7 + 2 * tt, 170.0, 0.7)
				"破浪下劈":
					var at2: Vector2 = o.pos + Vector2(dv.x, dv.y * 0.72) * r2 * 0.5
					var t2: int = maxi(t, 1)
					_add_up(o, "leap_e%d" % t2, at2, raw, "raw_splash_e%d" % t2, r2, 65.0, ang)
					_add_gd(o, "leap_e%d" % t2, at2, raw, "", r2, 65.0)
					_burst(o, R, p, at2 + Vector2(0, -22), at2.y, es, 5 + t2, 140.0, 0.55)
		"combo":   # 连携技「落潮横扫」（docs/246 §9，不分档）：整圈白刃大月牙 + 脚下一圈矮浪往外推 + 水滴、照地光
			var at3: Vector2 = d.get("at", o.pos)
			if Bal.v("fx/recipe_log", 0.0) > 0.0:
				print("PXPLOG combo c %d 115 -" % Engine.get_process_frames())
			if raw:
				_add(o, "", at3, 0.0, float(d.get("r", 115.0)), raw, "raw_spin_e1", 62.0)
			else:
				_add_pair(o, "combo_spin", at3, true)   # 挂在人身上的整圈月牙：跟人走
				_add_pair(o, "combo_swell", at3)
				_cuts(o, d.get("es", []), 1, 4)
			_burst(o, R, p, at3 + Vector2(0, -14), at3.y, d.get("es", []), 8, 160.0, 0.65)
		"skill":
			if int(d.get("i", -1)) == 2:   # 涌潮悲歌起手：身边冲起一柱大水 + 脚下一圈贴地水环
				_add_gd(o, "s3cast", o.pos, raw, "raw_ring_e2", 185.0, 92.0)
				_add_up(o, "s3cast", o.pos + Vector2(0, 2), raw, "raw_splash_e2", 185.0, 75.0, 0.0, true)
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -60), o.pos.y, "ink", 8, {"tier": 2})
				R._light(o, o.pos + Vector2(0, -10), 150.0, 0.6, 0.15, p.light)


## 命中：少量大颗水滴（Noita，有重量、落地成水点）+ 一盏照地短光。颗粒、光不随旧做法（2）出现
func _burst(o, R, p: Dictionary, at: Vector2, gy: float, es: Array, n: int, lr: float, li: float) -> void:
	if mode() != 1:
		return
	var m := {"tier": tier(o), "grain_spd": 1.0}
	if not es.is_empty():
		var e: Dictionary = es[0]
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
		R._grains(o, hp, float(e.pos.y) + 2.0, "ink", mini(n, 2 + es.size()), m, (hp - o.pos).normalized())
		R._light(o, hp, lr, li * MI.lit_k(g), 0.12, p.light)
	else:
		R._grains(o, at, gy, "ink", maxi(1, n / 2), m)
		R._light(o, at, lr * 0.8, li * 0.6 * MI.lit_k(g), 0.1, p.light)


## S1 十字斩落点（docs/270 光感补齐，11-05）：落点挂一盏照地灯（fx/px_plane_s1_light_r / _i，缺省 160 / 0.7）+ 交叉中心一颗十字亮芯（4 拍，进 emit）。只画
func _s1_land(o, R, p: Dictionary, at: Vector2) -> void:
	if mode() != 1:
		return
	var li: float = minf(0.88, Bal.v("fx/px_plane_s1_light_i", 0.65) * MI.lit_k(g))   # 打击感包开时 ×1.35，封在 docs/270 爆发类上限 0.9 以内
	R._light(o, at, Bal.v("fx/px_plane_s1_light_r", 160.0), li, 0.15, p.light)
	_push({"core": true, "t0": g.t + 0.06, "gp": at + Vector2(0, -12), "gy": at.y + 2.0, "ly": "up", "oid": str(o.id), "k": "", "life": 0.36, "o": o, "li": li, "at": at})


## 十字亮芯：第 0 拍长臂白芯，之后逐拍收短、转冰蓝；每格进 emit
func _draw_core(ci, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	if f < 0 or f > 3:
		return
	var px: float = g.PX
	var c0: Vector2 = _snap(_gp(it))
	var m: int = [6, 4, 3, 1][f]
	var col := Color(1, 1, 1) if f <= 1 else Color.html("#c4dcff")
	if f <= 2 and is_instance_valid(it.o):   # 落点灯撑到横斩落下：每帧跟一盏（0.05 秒寿命，走配方灯光预算），逐拍减弱
		var R = load("res://scripts/render/fx_recipe.gd").of(g)
		R._light_follow(it.o, it.at, Bal.v("fx/px_plane_s1_light_r", 160.0), float(it.li) * [1.0, 0.85, 0.6][f], R.pal(it.o).light)
	for i in range(-m, m + 1):
		for q in ([Vector2(i, 0)] if i == 0 else [Vector2(i, 0), Vector2(0, i)]):
			var pp: Vector2 = _snap(c0 + q * px)
			ci.draw_rect(Rect2(pp, Vector2(px, px)), col)
			if absi(i) <= m - 1:
				_glow(pp, Color(1, 1, 1))
	if f == 0:
		for q in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var pp: Vector2 = _snap(c0 + q * px)
			ci.draw_rect(Rect2(pp, Vector2(px, px)), col)
			_glow(pp, Color(1, 1, 1))


## 命中斩痕（刀剑感：被砍中的那只身上一道 1 美术像素白芯的斜线，3 拍收掉；精二交叉成 X）。只在转平面版；至多 n 只（离斯卡蒂由近到远）
func _cuts(o, es: Array, t: int, n: int) -> void:
	if mode() != 1 or es.is_empty():
		return
	var lst: Array = es.duplicate()
	lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
	for i in mini(n, lst.size()):
		var e: Dictionary = lst[i]
		var rd: Vector2 = (e.pos - o.pos)
		var tg: Vector2 = Vector2(-rd.y, rd.x).normalized() if rd.length() > 1.0 else Vector2.RIGHT
		tg = tg.rotated(-0.45 if tg.x * tg.y >= 0.0 else 0.45)   # 斜一点，不是正横正竖
		_push({"cut": true, "e": e, "t0": g.t, "gp": e.pos + Vector2(0, -float(e.r) * 0.55), "gy": float(e.pos.y) + 1.0, "d": tg, "x": t >= 2, "L": 9.0 + 2.0 * t + minf(6.0, float(e.r) * 0.25), "ly": "up", "oid": str(o.id), "k": ""})


func items_for(owner: String) -> Array:
	var owned = _items_by_owner.get(owner)
	if owned == null:
		owned = []
		_items_by_owner[owner] = owned
	return owned


func _index_item(it: Dictionary) -> void:
	items_for(str(it.oid)).append(it)
	if str(it.ly) == "up":
		_upright_items.append(it)


func _push(it: Dictionary) -> void:
	if items.size() >= ITEM_MAX:
		var oldest: Dictionary = items.pop_front()
		_items_by_owner[str(oldest.oid)].pop_front()
		if str(oldest.ly) == "up":
			_upright_items.pop_front()
	items.append(it)
	_index_item(it)


## 横扫 / 旋斩：立起层（刀光幕）+ 贴地层（接触阴影 + 水痕），同一个原点（脚底）
func _add(o, key: String, at: Vector2, ang: float, r: float, raw: bool, rawk: String, fit: float) -> void:
	if raw:
		_push({"k": rawk, "t0": g.t, "gp": at + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	# 11-05 用户「还有碎斩击」：同一名干员出新一刀时，只留上一刀（正在收）+ 这一刀，更早的刀痕立刻收掉
	var sl: Array = []
	for it in items:
		if str(it.oid) == str(o.id) and it.get("slash", false) and str(it.ly) == "up":
			sl.append(it.t0)
	if sl.size() >= 2:
		sl.sort()
		var keep_t: float = float(sl[sl.size() - 1])
		items = items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == str(o.id) and float(it.t0) < keep_t))
	var dk: Array = pick_dir(ang)
	var spin: bool = key.begins_with("spin")
	var ku: String = (key + "_up") if spin else "%s_up_d%d" % [key, dk[0]]
	var kg: String = (key + "_gd") if spin else "%s_gd_d%d" % [key, dk[0]]
	_push({"k": ku, "t0": g.t, "gp": _snap(at), "flip": dk[1] and not spin, "ly": "up", "oid": str(o.id), "slash": true, "fo": at - o.pos})
	_push({"k": kg, "t0": g.t, "gp": _snap(at), "flip": dk[1] and not spin, "ly": "gd", "oid": str(o.id), "slash": true, "fo": at - o.pos})


## 以脚底为原点的一对件（立起 + 贴地）
func _add_pair(o, key: String, at: Vector2, follow := false) -> void:
	var a := {"k": key + "_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	var b := {"k": key + "_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	if follow:
		a["fo"] = at - o.pos
		b["fo"] = at - o.pos
	_push(a)
	_push(b)


## 方向件（不是斩击：不参与「只留最近两刀」）
func _add_dir(o, key: String, at: Vector2, ang: float) -> void:
	var dk: Array = pick_dir(ang)
	_push({"k": "%s_up_d%d" % [key, dk[0]], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "up", "oid": str(o.id)})
	_push({"k": "%s_gd_d%d" % [key, dk[0]], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "gd", "oid": str(o.id)})


func _add_up(o, key: String, at: Vector2, raw: bool, rawk: String, r: float, fit: float, ang: float, follow := false) -> void:
	if raw:
		_push({"k": rawk, "t0": g.t, "gp": at + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	var it := {"k": key + "_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": str(o.id)}
	if follow:
		it["fo"] = at - o.pos
	_push(it)


func _add_gd(o, key: String, at: Vector2, raw: bool, rawk: String, r: float, fit: float) -> void:
	if raw:
		if rawk != "":
			_push({"k": rawk, "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / fit, "oid": str(o.id)})
		return
	_push({"k": key + "_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})


## 件的当前地面点（docs/246 §11，11-05 用户「斩击没有绑定人，会在别的地方出现」）：
## 挂在人身上的件（fo = 出手时相对施放者脚底的偏移）每次绘制按施放者当前位置重算，朝向保持出手时的方向；
## 斩痕（e）跟着被砍的那只；其余（落地类：冲击环、碎浪、碎沫、积水、湿痕）留在出手时的世界坐标
func _gp(it: Dictionary) -> Vector2:
	if it.has("mv"):   # 推进之王锤击冲击波（docs/264）：自己往前推（前快后慢），按 15 fps 节拍跳格
		var mv: Dictionary = it.mv
		var age: float = float(int(floor(g.t * 15.0)) - int(floor(float(it.t0) * 15.0))) / 15.0
		return _snap(mv.p0 + (mv.dir as Vector2) * (600.0 * age - 500.0 * age * age))
	if it.has("fo"):
		var op = _op(str(it.oid))
		if op != null and op.pos != Vector2.INF:
			return _snap(op.pos + (it.fo as Vector2))
	elif it.has("e"):
		var e: Dictionary = it.e
		if not e.get("dead", false):
			return e.pos + Vector2(0, -float(e.r) * 0.55)
	elif it.has("ef"):   # 缠绕（docs/261 水月）：跟着被缠住那只的脚底
		var ef: Dictionary = it.ef
		if not ef.get("dead", false):
			return _snap(ef.pos)
	return it.gp


func _op(oid: String):
	for o in g.squad.ops:
		if str(o.id) == oid:
			return o
	return null


var _step_fr := -1
func _step() -> void:
	var fr: int = Engine.get_process_frames()
	if fr == _step_fr and not (g.opt_old & g.OPT_PXSTEP):   # 一帧只清一次（docs/287 §3 ⑤）：原来每名干员每个绘制层进来都整表 filter 一遍；同一帧 g.t 不变，结果相同
		return
	_step_fr = fr
	_tex_evict()
	var now: float = g.t
	CUE.step(self)
	var tk := int(floor(now * 15.0))
	var follow := tk != _fol_tick
	_fol_tick = tk
	var live = null   # 首次到期才复制此前的存活项；旧列表留给尚在遍历它的调用方。
	var fps_cap := _life_fps() if not items.is_empty() else 0.0
	for i in items.size():
		var it: Dictionary = items[i]
		var life: float = float(it.life) if it.has("life") else _life(str(it.k), fps_cap)
		var alive: bool = now - float(it.t0) < life + 0.02 and not (it.has("ef") and it.ef.get("dead", false))
		if not alive:
			if live == null:
				live = items.slice(0, i)
			continue
		if live != null:
			live.append(it)
		if it.has("stk") and frame_of(float(it.t0)) >= 2:   # 卡肉：先判寿命，再将首帧停顿计入时间。
			it.t0 = float(it.t0) + float(it.stk)
			it.erase("stk")
		if not follow:
			continue
		if it.has("fol") and g.ppos != Vector2.INF:   # 举盾：跟着队长
			it.gp = _snap(g.ppos + (it.fol as Vector2))
		elif it.get("fop", false):   # 星熊挂在身上的件（月牙刀痕、下劈弧、力之锯起手弧）：存续期间跟着出手的干员（11-05 用户实机「斩击不跟着人走」）
			var op = _op_by_id(str(it.oid))
			if op != null and op.pos != Vector2.INF:
				it.gp = _snap(op.pos)
		elif it.has("fe") and not it.fe.dead:   # 德克萨斯钉剑：跟着被钉的敌人（只读位置）
			it.gp = _snap(it.fe.pos)
		if it.has("fopo") and is_instance_valid(it.fopo) and it.fopo.pos != Vector2.INF:
			var np: Vector2 = _snap(it.fopo.pos + (it.foff as Vector2))
			if it.has("at"):
				it.at = np
			else:
				it.gp = np
		if it.has("fopl"):
			var fo = it.fopl
			if is_instance_valid(fo) and fo.pos != Vector2.INF:
				it.gp = _snap(fo.pos)
				it.flip = float(fo.face) < 0.0
				if it.has("gy"):
					it.gy = float(fo.pos.y) + 2.0
	if live != null:
		items = live


func _life_fps() -> float:
	return minf(Bal.v("fx/px_plane_raw_fps", 12.8), clock())


func _life(k: String, fps_cap: float) -> float:
	if k == "":
		return 3.0 / 15.0   # 斩痕 3 拍
	var m: Dictionary = _meta(k)
	if m.is_empty():
		return 0.0
	return float(m.n) / minf(float(m.fps), fps_cap) + 0.07


# ================================================================ 绘制

## 地面层（data_operator.draw_entities_floor → fx_recipe.draw_floor 转来）：贴地件、潮刃 / 浪墙的地面尾迹
func draw_floor(o) -> void:
	_step()
	if str(o.id) == "mizuki" and o.hw.has("mz"):
		MZ._smz(self)._h3mz_draw_keep(o)   # 缠住标记 / 触手桩范围 / 灯火圈：状态件，接管时照画（docs/261）
	if mode() != 1:
		return
	var cv = o.cv
	var id: String = str(o.id)
	CUE.floor_layer(self, o)
	if id == "hoshiguma":
		HSG._floor_hsg(self, o)
		return
	if id == "lumen":
		LM._lm_draw_floor(self, o)
		return
	if id == "skalter":
		SK._sk_draw_floor(self, o)
		return
	if id == "gladiia":
		GL.floor_layer(self, o)
		return
	if id == "eyjafjalla":
		EY._ey_floor(self, o)
		return
	if id == "kaltsit":
		KA.floor_layer(self, o)
		return
	if id == "specter_unchained":
		SU.floor_layer(self, o)
		return
	if id == "siege":
		SG._floor_sg(self, o)
		return
	if id == "exusiai":
		_ex().draw_floor(o)
		return
	if id == "texas":
		TX._floor_tx(self, o)
		return
	if id == "mizuki":
		MZ._mz_draw_floor(self, o)
		return
	if id == "angelina":
		_an().draw_floor(o)
		return
	if id == "saria":
		_sa().draw_floor(o)
		return
	if id == "logos":
		LG._lg_draw_floor(self, o)
		return
	if id == "ulpianus":
		UL.floor_layer(self, o)
		return
	if id == "suzuran":
		_szx().draw_floor(o)
		return
	if id == "irene":
		_ir().draw_floor(o)
		return
	if id == "wisadel":
		_wd().draw_floor(o)
		return
	if id == "lappland":
		_lp().draw_floor(o)
		return
	if o.skill_active_left(2) > 0.0:   # 涌潮悲歌持续期间：脚下一滩积水（循环，跟着人走）
		_draw_strip(cv, "pool_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for it in items_for(id):
		if str(it.ly) == "gd":
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)
	_wall_spawn(o)
	_draw_qi_wakes(o, cv)
	for w in _waves(o):
		_draw_strip(cv, w[0] + "_gd_d%d" % w[3], frame_of(0.0), w[1], w[2], false)


## 上层（_draw_skill_over → fx_recipe.draw_over 转来）：旧做法（2）的整张贴图都画在这里（盖在所有单位上）
func draw_over(o) -> void:
	if str(o.id) == "specter_unchained":
		SU.over(self, o)   # 火星、连携斩线；旧做法对照（2）的整张贴图
		return
	if str(o.id) == "lumen" and o.hw.has("lm"):
		_sl()._h3lm_draw_units(o)   # 发光单元是本体附属物（不是攻击特效），接管时照画
	if str(o.id) == "gladiia":
		_step()
		GL.over(self, o)   # 链 + 钩头（转平面版、旧做法对照都画）；旧做法的整张贴图
		return
	if str(o.id) == "siege" and mode() == 1:
		SG._sg_draw_motes(self, o)   # 冲锋号令 / 跃空锤的全队技力粒子（状态提示：技力飞向队友）
	if str(o.id) == "saria":
		if mode() == 1:
			_sa().draw_over(o)   # 状态提示 + 钙化斑（docs/269）
		return
	if str(o.id) == "ulpianus":
		_step()
		UL.over(self, o)   # 锁链 + 锚（转平面版、旧做法对照都画）
		return
	if str(o.id) == "wisadel":
		if mode() == 1:
			_wd().draw_over(o)   # 残影标记 + 续燃引线（docs/274）
		return
	if str(o.id) == "lappland":
		if mode() == 1:
			_lp().draw_over(o)   # 封印传染细虚线（docs/273）
		return
	if mode() != 2:
		return
	var cv = o.cv
	var id: String = str(o.id)
	if id == "lumen":
		LM._lm_draw_raw(self, o)
		return
	if id == "skalter":
		SK._sk_draw_raw(self, o)
		return
	if id == "eyjafjalla":
		EY._ey_draw_raw(self, o)
		return
	if id == "texas":
		_tx_draw_raw_lines(o)
	if id == "mizuki" and o.hw.has("mz"):
		MZ._smz(self)._h3mz_draw_jellies(o)   # 旧做法对照：深蓝之籽照原画法
	if id == "logos":
		LG._lg_draw_raw(self, o)
	for it in items_for(id):
		if str(it.ly) != "raw":
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8)), it.gp, float(it.rot), float(it.sc))
	if id == "logos":
		return
	if id == "hoshiguma":   # 般若回旋的锯盾：旧做法整张贴（正圆、光晕烤进颜色、盖在上面）
		for bm in HSG._booms(self, o):
			_draw_raw(cv, "hsg_raw_saw", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(_meta("hsg_raw_saw").get("n", 1))), o.pos + bm.dir * HSG._boom_d(bm) + Vector2(0, -22), 0.0, g.PX)
		return
	if id == "skadi" and o.get("vg") is Dictionary and not o.vg.is_empty():   # 斯卡蒂剑气（docs/246 §9）；星熊走上面自己的
		for q in o.vg.get("qi", []):
			_draw_raw(cv, "raw_blade", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(_meta("raw_blade").get("n", 1))), q.p + Vector2(0, -16), (q.v as Vector2).angle(), g.PX * 1.3)
	for w in o.hw.get("waves", []):
		var b: Dictionary = w.b
		if not b.has("proj") and not b.has("tex"):
			continue
		var big: bool = not b.has("proj")
		_draw_raw(cv, "raw_blade", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(_meta("raw_blade").get("n", 1))), w.pos + Vector2(0, -16), (w.dir as Vector2).angle(), g.PX * (float(w.w) * 0.5) / 26.0 * (1.0 if not big else 1.0))


## world._sorted_fast 的排序项（kind 7）：立起件按脚底 y 排进单位层
static func sort_items(game) -> Array:
	if game == null or not game.has_meta("fx_pxplane"):
		return []
	var r = game.get_meta("fx_pxplane")
	if r.mode() != 1:
		return []
	var out: Array = []
	for it in r._upright_items:
		it["skey"] = r._skey(it)   # 跟人 / 跟怪的件按当前位置排序（另存 skey，不动星熊地刺的 sk 偏移）
		out.append(it)
	CUE.sort_items(r, out)
	for o in game.squad.ops:
		if IDS.has(str(o.id)) and o.pos != Vector2.INF:
			if str(o.id) == "lumen":
				LM._lm_sort_items(r, o, out)
				continue
			if str(o.id) == "skalter":
				SK._sk_sort_items(r, o, out)
				continue
			if str(o.id) == "gladiia":
				GL.sort_items(r, o, out)
				continue
			if str(o.id) == "eyjafjalla":
				EY._ey_sort_items(r, o, out)
				continue
			if str(o.id) == "kaltsit":
				KA.sort_items(r, o, out)
				continue
			if str(o.id) == "specter_unchained":
				SU.sort_items(r, o, out)
				continue
			if str(o.id) == "mizuki":
				MZ._mz_sort_items(r, o, out)
				continue
			if str(o.id) == "exusiai":
				r._ex().sort_items(o, out)
				continue
			if str(o.id) == "texas":
				TX._tx_sort_items(r, o, out)
				continue
			if str(o.id) == "angelina":
				r._an().sort_items(o, out)
				continue
			if str(o.id) == "saria":
				r._sa().sort_items(o, out)
				continue
			if str(o.id) == "logos":
				LG._lg_sort_items(r, o, out)
				continue
			if str(o.id) == "ulpianus":
				UL.sort_items(r, o, out)
				continue
			if str(o.id) == "suzuran":
				r._szx().sort_items(o, out)
				continue
			if str(o.id) == "irene":
				r._ir().sort_items(o, out)
				continue
			if str(o.id) == "wisadel":
				r._wd().sort_items(o, out)
				continue
			if str(o.id) == "lappland":
				r._lp().sort_items(o, out)
				continue
			for w in r._waves(o):
				out.append({"wave": w})
			if str(o.id) == "skadi":   # 斯卡蒂剑气浪头（docs/246 §9）
				for qw in r._qis(o):
					out.append({"wave": qw})
			elif str(o.id) == "hoshiguma":   # 星熊锯盾 + 剑气齐射（docs/254）
				for bm in HSG._booms(r, o):
					out.append({"k": "hsg_saw_up", "t0": 0.0, "gp": HSG._boom_gp(r, o, bm), "flip": false, "loop": true})
				for qv in HSG._qi_volleys(r, o):
					out.append({"k": qv.k + "_up_d%d" % qv.d, "fi": qv.f, "gp": qv.gp, "flip": qv.flip})
	return out


static func draw_sorted(game, ci, it: Dictionary) -> void:
	var r = game.get_meta("fx_pxplane")
	if it.has("cue"):   # 成长节点通用提示（docs/310 §2）
		CUE.draw_up(r, ci, it.cue)
		return
	if it.has("skr"):   # 浊心斯卡蒂（docs/260）：运行时立起件
		SK._sk_draw_up(r, ci, it)
		return
	if it.has("skr_s"):
		SK._sk_draw_state_up(r, ci, it)
		return
	if it.has("surt"):   # 归溟幽灵鲨运行时件（docs/268）
		SU.draw_rt(r, ci, it)
		return
	if it.has("lp"):   # 拉普兰德运行时件（docs/273）
		r._lp().draw_rt(ci, it)
		return
	if it.has("ex"):   # 能天使运行时件（docs/262）
		r._ex().draw_rt(ci, it)
		return
	if it.has("wave"):
		var w: Array = it.wave
		r._draw_strip(ci, w[0] + "_up_d%d" % w[3], r.frame_of(0.0), w[1], w[2], false)
		return
	if it.get("cut", false):
		r._draw_cut(ci, it)
		return
	if it.get("core", false):
		r._draw_core(ci, it)
		return
	if it.has("ln"):   # 德克萨斯：运行时直线刀光（冲刺 / 次元斩 / 连携）
		TX._tx_draw_line(r, ci, it, false)
		return
	if it.has("fi"):   # 星熊剑气：帧号按剑气年龄 / 剩余寿命挑
		r._draw_strip(ci, str(it.k), int(it.fi), r._gp(it), it.flip, true)
		return
	if it.has("an"):   # 安洁莉娜运行时件（docs/267）
		r._an().draw_rt(ci, it)
		return
	if it.has("sa"):   # 塞雷娅运行时件（docs/269）
		r._sa().draw_rt(ci, it)
		return
	if it.has("ulrt"):   # 乌尔比安运行时件（docs/266）
		UL.draw_rt(r, ci, it)
		return
	if it.has("sz"):   # 铃兰运行时件（docs/271）
		r._szx().draw_rt(ci, it)
		return
	if it.has("ir"):   # 艾丽妮运行时件（docs/272）
		r._ir().draw_rt(ci, it)
		return
	if it.has("wd"):   # 维什戴尔运行时件（docs/274）：炮弹
		r._wd().draw_rt(ci, it)
		return
	if it.has("ert"):   # 艾雅法拉运行时件（docs/259）
		EY._ey_draw_rt(r, ci, it)
		return
	if it.has("rt"):
		LM._lm_draw_rt(r, ci, it)
		return
	if it.has("glrt"):
		GL.draw_rt(r, ci, it)
		return
	if it.has("mzj"):
		MZ._mz_draw_jelly(r, ci, it)
		return
	if it.has("lrt"):
		LG._lg_draw_rt(r, ci, it)
		return
	if it.has("loopk"):
		r._draw_strip(ci, str(it.loopk), r.frame_of(0.0), r._gp(it), false, false)
		return
	if it.get("loop", false) and it.has("life"):   # 循环一次性件（艾雅法拉连携熔岩泡）：带淡入淡出
		r._draw_strip(ci, str(it.k), r.frame_of(0.0), r._gp(it), false, false, Color(1, 1, 1, EY._ey_loop_a(r, it)))
		return
	r._draw_strip(ci, str(it.k), r.frame_of(float(it.t0)), r._gp(it), it.flip, not it.get("loop", false))


## 斩痕：沿方向逐美术像素画（2 世界像素格），第 0 拍白芯 + 两侧浅蓝、第 1 拍浅蓝变短、第 2 拍只剩两头几点
func _draw_cut(ci, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	if f < 0 or f > 2:
		return
	var px: float = g.PX
	var c0: Vector2 = _snap(_gp(it))
	var dirs: Array = [it.d]
	if it.x:
		dirs.append((it.d as Vector2).rotated(1.25))
	var core := Color(1, 1, 1) if f == 0 else Color.html(str(it.get("c1", "#cddcfb")))   # c1 / c2 / c3：干员自己的斩痕色（德克萨斯琥珀）
	var side := Color.html(str(it.get("c2", "#93b4f7"))) if f == 0 else Color.html(str(it.get("c3", "#598cf2")))
	var lk: float = MI.lit_k(g)
	var L: float = float(it.L) * [1.0, 0.8, 0.5][f] * (1.0 + (lk - 1.0) * 0.6)   # 打击感包开：斩痕长一点、亮一点
	for d in dirs:
		var dv: Vector2 = d
		var nv := Vector2(-dv.y, dv.x)
		var m: int = int(L)
		for i in range(-m, m + 1):
			if f == 2 and absi(i) < m - 2:
				continue
			var w: float = 1.0 - absf(float(i)) / float(m + 1)   # 两头收尖
			var p: Vector2 = _snap(c0 + dv * float(i) * px)
			ci.draw_rect(Rect2(p, Vector2(px, px)), core if w > 0.25 else side)
			if f == 0 and w > (0.55 if lk <= 1.0 else 0.3):
				ci.draw_rect(Rect2(_snap(p + nv * px), Vector2(px, px)), side)
			if f <= 1 and lk > 1.0 and w > 0.5:
				ci.draw_rect(Rect2(_snap(p - nv * px), Vector2(px, px)), side)
			var ek: bool = it.has("emk")   # emk：斩痕白芯每格都进发光层、留两拍（德克萨斯，docs/270 §5「核心辉光 0」）
			if (f == 0 or (ek and f == 1)) and w > (0.25 if ek else 0.4) and g.optical_on and _emit_n < EMIT_CAP and ((i & 1) == 0 or ek):
				_emit_n += 1
				g.glow_next.append([p, px, Color(1, 1, 1, minf(1.0, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)) * lk)) if not ek else Color(1.0, 0.9, 0.7, minf(1.0, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)) * lk * (1.0 if f == 0 else 0.7)))])


## 立起件当前的排序位置：有 gyo（相对原点的脚底偏移）按当前原点 + gyo；有 gy 的跟着原点平移；斩痕按被砍那只的脚底；其余原点 + 1；再加 sk 偏移（星熊地刺）。
## 运行时线状件（流明光弹 / 光柱 / 折光）没有 gp，直接用 gy
func _skey(it: Dictionary) -> float:
	if not it.has("gp"):
		return float(it.get("gy", 0.0)) + float(it.get("sk", 0.0))
	var gp: Vector2 = _gp(it)
	var base: float
	if it.has("gyo"):
		base = gp.y + float(it.gyo)
	elif it.has("gy"):
		base = float(it.gy) + (gp.y - float((it.gp as Vector2).y))
	elif it.get("cut", false) and it.has("e"):
		base = gp.y + float(it.e.r) * 0.55 + 1.0
	else:
		base = gp.y + 1.0
	return base + float(it.get("sk", 0.0))


static func sort_key(it: Dictionary) -> float:
	if it.has("skey"):
		return float(it.skey)
	if it.has("wave"):
		return float((it.wave[1] as Vector2).y) + 2.0
	if it.get("cut", false) or it.has("gy"):
		return float(it.gy)
	return float((it.gp as Vector2).y) + 1.0 + float(it.get("sk", 0.0))   # sk：身后半圈的件往前排（星熊地刺）


## 「跃浪」浪墙：推进途中每两拍（15 fps）在浪头位置生成一道小碎浪（一次性件，原点放在浪头后方 36 美术像素，让碎浪的浪线落在浪头上）。
## 只读玩法状态，画面计时记在浪字典的 _pxs（玩法不读）
func _wall_spawn(o) -> void:
	if mode() != 1 or o.hw.is_empty() or not o.hw.has("waves"):
		return
	var tick: int = int(floor(g.t * 15.0))
	var t: int = clampi(tier(o), 1, 2)
	for w in o.hw.waves:
		if w.b.has("proj"):
			continue
		if w.has("_pxs") and tick - int(w._pxs) < 2:
			continue
		w["_pxs"] = tick
		var dv: Vector2 = w.dir
		var org: Vector2 = w.pos - Vector2(dv.x, dv.y * 0.72) * 36.0 * g.PX
		_add_dir(o, "wallbrk_e%d" % t, org, dv.angle())


## late_shape / 可见成长的额外剑气（o.vg.qi）→ 水刃：[帧条前缀, 地面点（按 15 fps 节拍跳格）, 翻转, 方向]
func _qis(o) -> Array:
	var out: Array = []
	if mode() != 1 or not (o.get("vg") is Dictionary) or o.vg.is_empty():
		return out
	var t: int = tier(o)
	for q in o.vg.get("qi", []):
		var dk: Array = pick_dir((q.v as Vector2).angle())
		out.append(["qi_e%d" % t, _wpos({"pos": q.p, "_pxq": q.get("_pxq")}, q), dk[1], dk[0]])
	return out


## 剑气身后地上的 V 字白沫浪痕：从出手点到当前位置，越靠后越稀、越暗；逐美术像素画（对齐 2 世界像素格）
func _draw_qi_wakes(o, cv) -> void:
	if not (o.get("vg") is Dictionary) or o.vg.is_empty():
		return
	var px: float = g.PX
	for q in o.vg.get("qi", []):
		var dv: Vector2 = (q.v as Vector2).normalized()
		if absf(dv.y) > 0.6 and Bal.v("fx/skadi_qi_wake_vert", 0.0) <= 0.0:
			continue   # 11-07 用户截图「奇怪」：竖着跑的剑气，身后 V 字浪痕变成两条垂下的虚线，配上浪头像降落伞——竖向不画浪痕（横 / 斜照旧）
		var nv := Vector2(-dv.y, dv.x * 0.72)
		var head: Vector2 = _wpos({"pos": q.p, "_pxq": q.get("_pxq")}, q)
		var L: float = minf(90.0, (q.p as Vector2).distance_to(q.get("p0", q.p)) + 20.0)
		var sd: int = int(q.get("o0", Vector2.ZERO).x * 7.0) & 1023
		var s := 4.0
		while s < L:
			var u: float = s / L
			for side in [-1.0, 1.0]:
				if Fxr_h(sd + int(s) * 3 + (1 if side > 0 else 0)) < 0.25 + 0.6 * u:
					continue
				var pp: Vector2 = _snap(head - Vector2(dv.x, dv.y * 0.72) * s + nv * side * (3.0 + s * 0.32))
				cv.draw_rect(Rect2(pp, Vector2(px, px)), Color.html("#ffffff") if u < 0.25 else (Color.html("#93b4f7") if u < 0.6 else Color.html("#446ec0")))
			s += px


static func Fxr_h(i: int) -> float:
	var x: int = (i * 0x9E3779B1) & 0x7fffffff
	x = x ^ (x >> 13)
	x = (x * 1103515245 + 12345) & 0x7fffffff
	return float((x >> 8) & 0xffff) / 65535.0


## 潮刃（弹体式）：直接读玩法状态 o.hw.waves → [帧条前缀, 地面点, 翻转, 方向]（浪墙改由 _wall_spawn 生成碎浪，不在这里）
func _waves(o) -> Array:
	var out: Array = []
	if o.hw.is_empty() or not o.hw.has("waves"):
		return out
	for w in o.hw.waves:
		var b: Dictionary = w.b
		if not b.has("proj"):
			continue
		var dk: Array = pick_dir((w.dir as Vector2).angle())
		out.append(["blade" if b.has("proj") else "wall", _wpos(w), dk[1], dk[0]])
	return out


## 潮刃 / 浪墙的画面位置：统一节拍时每 1/15 秒才跳一次格（对齐 2 世界像素 = 1 美术像素）；对照档平滑跟随。
## 记在浪自己的字典里（画面专用键 _pxq，玩法不读）
func _wpos(w: Dictionary, store = null) -> Vector2:
	if not is_equal_approx(clock(), 15.0):
		return w.pos
	var tick: int = int(floor(g.t * 15.0))
	var q = w.get("_pxq")
	if q == null or int(q[0]) != tick:
		q = [tick, _snap(w.pos)]
		if store != null:
			store["_pxq"] = q
		else:
			w["_pxq"] = q
	return q[1]


## 网页版帧条可以共用相邻帧的透明边。绘制矩形与旧版相同，旋转和像素对齐照旧。
func _frame_region(m: Dictionary, fi: int) -> Rect2:
	var x := fi * int(m.w)
	var y := 0
	if m.has("frame_offsets"):
		var offset := int(m.frame_offsets[fi])
		x = maxi(0, offset)
		y = maxi(0, -offset)
	return Rect2(x, y, int(m.w), int(m.h))


## 一张帧条的一帧：1 帧条像素 = g.PX 世界像素（整数倍），原点对齐 2 像素格；不旋转（方向靠预生成 + 水平翻转）
func _draw_strip(ci, k: String, fi: int, gp: Vector2, flip: bool, once: bool, mod := Color.WHITE, emit := true) -> void:
	var m: Dictionary = _meta(k)
	if m.is_empty():
		return
	var n: int = int(m.n)
	if once and (fi < 0 or fi >= n):
		return
	fi = posmod(fi, n)
	var w: float = float(m.w)
	var h: float = float(m.h)
	var px: float = g.PX
	var top: float = gp.y - float(m.oy) * px
	var left: float = gp.x - (w - float(m.ox)) * px if flip else gp.x - float(m.ox) * px
	var dst := Rect2(left, top, w * px, h * px)
	if not _strip_in_view(ci, dst, not flip):
		if flip:
			_reset_skipped_transform(ci, k)
		if emit and g.optical_on and _has_strip(k):
			_emit(m, fi, dst.position, w, flip)
		return
	var tx: Texture2D = _tex(k)
	if tx == null:
		return
	var src := _frame_region(m, fi)
	if flip:   # 水平翻转用镜像变换，不用负宽矩形：负宽矩形在 GL 兼容渲染下整张往右错开一个帧宽（11-05 德克萨斯旋斩实测，发光点却在原位）
		ci.draw_set_transform(Vector2(left + w * px, top), 0.0, Vector2(-1.0, 1.0))
		ci.draw_texture_rect_region(tx, Rect2(Vector2.ZERO, Vector2(w * px, h * px)), src, mod)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tx, dst, src, mod)
	if emit:   # 残影 / 半透明副本可以不发光（docs/273 拉普兰德剑气残光，体检 emit 顶上限）
		_emit(m, fi, Vector2(left, top), w, flip)


## 热芯像素进光学发光层（同 world._glow_pts 的格式：[左上角, 边长, 颜色]）
func _emit(m: Dictionary, fi: int, tl: Vector2, w: float, flip: bool) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	if _emit_n >= EMIT_CAP or fi >= m.emit.size():
		return
	var pts: Array = m.emit[fi]
	if pts.is_empty():
		return
	var px: float = g.PX
	var k: float = Bal.v("fx/px_plane_emit", 0.8)
	for q in pts:
		if _emit_n >= EMIT_CAP:
			return
		_emit_n += 1
		var x: float = float(q[0])
		if flip:
			x = w - 1.0 - x
		var c: Color = _hexc(str(q[2]))
		g.glow_next.append([tl + Vector2(x, float(q[1])) * px, px, Color(c.r, c.g, c.b, k)])


func _hexc(s: String) -> Color:
	if not _ecol.has(s):
		_ecol[s] = Color.html(s)
	return _ecol[s]


## 旧做法：光晕烤进颜色的帧条，按判定半径小数缩放、旋转，中心对原点
func _draw_raw(cv, k: String, fi: int, at: Vector2, rot: float, sc: float) -> void:
	var m: Dictionary = _meta(k)
	if m.is_empty() or fi < 0 or fi >= int(m.n):
		return
	var w: float = float(m.w)
	var h: float = float(m.h)
	var rect := Rect2(-float(m.ox), -float(m.oy), w, h)
	if not _strip_in_view(cv, Transform2D(rot, Vector2(sc, sc), 0.0, at) * rect):
		_reset_skipped_transform(cv, k)
		return
	var tx: Texture2D = _tex(k)
	if tx == null:
		return
	cv.draw_set_transform(at, rot, Vector2(sc, sc))
	cv.draw_texture_rect_region(tx, rect, _frame_region(m, fi))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ================================================================ 星熊（docs/254，照 docs/246 斯卡蒂的做法） → fx_pxplane_hsg.gd（docs/286 §4 第三批拆出）


## 命中：少量颗粒（材质可选）+ 一盏照地短光；只在转平面版
func _burst_m(o, R, p: Dictionary, at: Vector2, gy: float, es: Array, n: int, mat: String, lr: float, li: float, light := true) -> void:
	if mode() != 1:
		return
	var m := {"tier": tier(o), "grain_spd": 1.0}
	if not es.is_empty():
		var e: Dictionary = es[0]
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
		R._grains(o, hp, float(e.pos.y) + 2.0, mat, mini(n, 2 + es.size()), m, (hp - o.pos).normalized())
		if light:
			R._light(o, hp, lr, li, 0.12, p.light)
	else:
		R._grains(o, at, gy, mat, maxi(1, n / 2), m)
		if light:
			R._light(o, at, lr * 0.8, li * 0.6, 0.1, p.light)


## 尺寸档：判定半径（美术像素）挑最近的一档（帧条按几档预生成，游戏只整数放大）
static func _bucket(v: float, opts: Array) -> int:
	return PxU.nearest(opts, v)


func _qpos(q: Dictionary) -> Vector2:
	if not is_equal_approx(clock(), 15.0):
		return q.p
	var tick: int = int(floor(g.t * 15.0))
	var c = q.get("_pxq")
	if c == null or int(c[0]) != tick:
		c = [tick, q.p]
		q["_pxq"] = c
	return c[1]

# ================================================================ 流明（docs/255，照斯卡蒂 docs/246 的做法） → fx_pxplane_lm.gd（docs/286 §4 第三批拆出）

var _slm = null

func _sl():
	if _slm == null:
		_slm = load("res://scripts/characters/blocks/seg_lumen.gd")   # 运行时取（避免和积木链循环 preload）
	return _slm


## 同一名干员这一拍（1/15 秒）已出的某类件数（额外弹命中 / 连锁），超过上限就不再加画面
var _beat_cnt := {}

func _lm_beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat_cnt, g.t, str(o.id) + k)


func _px(ci, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(_snap(p), Vector2(g.PX, g.PX)), c)


func _glow(p: Vector2, c: Color) -> void:
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	if _emit_n >= EMIT_CAP:
		return
	_emit_n += 1
	g.glow_next.append([_snap(p), g.PX, Color(c.r, c.g, c.b, Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k))])   # lf_emit_k：后期队友减量（docs/293）


# ================================================================ 逻各斯（docs/258，照斯卡蒂 docs/246 / 流明 docs/255 的做法） → fx_pxplane_lg.gd（docs/286 §4 第三批拆出）


var _lg_fire_t := -9.0


var _lg_fill_tex := {}


func _op_by_id(oid: String):
	for m in g.squad.ops:
		if str(m.id) == oid:
			return m
	return null


# ================================================================ 艾雅法拉（docs/259，照斯卡蒂 docs/246 的做法；11-05 用户「火山和熔岩的感觉要做出来，火球也是，参考 pixelfx 的做法」） → fx_pxplane_ey.gd（docs/286 §4 第三批拆出）


var _sey = null


## 帧条只有 5 个 45° 角：挑最近的一张后再转掉剩下的偏差（≤ 22.5°），火球朝向和真实飞行方向一致——
## 原来 25° 飞的火球画成 45°，看着像斜着「平移」（11-06）。热芯发光点按同一变换放
const EY_BALL_VIS := {-90: -85.6, -45: -40.7, 0: 4.4, 45: 49.3, 90: 94.4}   # 标称角 → 帧条里火体（亮像素，不含烟）实测主轴（度；烤图整体顺时针偏约 4.5°，lava / pow / ign 同）


func _ey_strip_rot(ci, k: String, fi: int, gp: Vector2, flip: bool, ang: float, bucket: float, ln := 1.0) -> void:
	var m: Dictionary = _meta(k)
	if m.is_empty():
		return
	fi = posmod(fi, int(m.n))
	var w: float = float(m.w)
	var h: float = float(m.h)
	var px: float = g.PX
	# 帧条里火体主轴比标称角顺时针偏约 4.5°（烤图带的；亮像素主成分，18 帧中位数，tools/eyja_ball_dir_sheet.py 核对图）
	var vis: float = float(EY_BALL_VIS.get(int(bucket), bucket))
	var shown: float = deg_to_rad(180.0 - vis if flip else vis)
	var res: float = wrapf(ang - shown, -PI, PI)
	# 局部坐标：锚点（ox, oy）在原点；翻转时镜像
	var xf := Transform2D(res, gp)
	if flip:
		xf = xf * Transform2D(0.0, Vector2(-1.0, 1.0), 0.0, Vector2.ZERO)
	if ln < 1.0:   # 帧条局部坐标里沿火体主轴（vis 角）压短，锚点（弹头）不动
		xf = xf * EY._ey_squash(deg_to_rad(vis), ln)
	var tl := Vector2(-float(m.ox) * px, -float(m.oy) * px)
	var rect := Rect2(tl, Vector2(w * px, h * px))
	if _strip_in_view(ci, xf * rect):
		var tx: Texture2D = _tex(k)
		if tx == null:
			return
		ci.draw_set_transform_matrix(xf)
		ci.draw_texture_rect_region(tx, rect, _frame_region(m, fi))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		_reset_skipped_transform(ci, k)
		if not g.optical_on or not _has_strip(k):
			return
	if not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	var pts: Array = m.emit[fi] if fi < m.emit.size() else []
	var ke: float = Bal.v("fx/px_plane_emit", 0.8)
	for q in pts:
		if _emit_n >= EMIT_CAP:
			return
		_emit_n += 1
		var c: Color = _hexc(str(q[2]))
		g.glow_next.append([_snap(xf * (tl + Vector2(float(q[0]), float(q[1])) * px)), px, Color(c.r, c.g, c.b, ke)])


## --balldbg（调试，只开发版）：青线 = 该弹此刻的速度方向（真实飞行方向），白点 = 所有火球最近 10 帧的真实位置（看弹道是否拐弯、火球主轴是否顺着点列）
var _bdbg := -1
var _bdbg_pts: Array = []   # [帧号, 位置]


# ================================================================ 推进之王（docs/264，照 docs/246 斯卡蒂 / docs/254 星熊的做法） → fx_pxplane_sg.gd（docs/286 §4 第三批拆出）

var _motes: Array = []   # 技力粒子：{to 队友, from, t0, life, bend}（只画）
var _sg_imp := {}        # 干员 id → 最近一锤的落点（只画）
var _sg_cores: Array = []   # 锤击落点亮芯：{at, t0, big}，3 拍（0.2 秒）内每帧排进发光层


## 后期剑气（late_shape → vis_growth._fire_qi，只读 o.vg.qi）：每次出手新生成的几道合成一道冲击波，自己往前推约 0.5 秒（判定照旧，画面比判定走得远）；
## 前沿扫过的怪打出火星（每道冲击波至多 5 只）。同屏每人至多两道。新剑气记一个画面专用键 _pxw（玩法不读）
var _sgw: Array = []   # {oid, mv, t0, hits, S}


var _smzs = null


# ================================================================ 浊心斯卡蒂（docs/260，照 docs/246 斯卡蒂的做法） → fx_pxplane_sk.gd（docs/286 §4 第三批拆出）

var _sk_st := {}          # 干员 id → 画面状态（缓动半径、潮涌下次时刻、上一拍去重），玩法不读


## 歌域笔触弧的缓存写法（docs/287 §3 ②，OPT_SKDOM）：角度的 cos / sin 与逐点粗细只跟（a0, a1, 点数, 宽, 种子, 收尖）有关，
## 转动按 15 fps 节拍走，60 帧下同一拍 4 帧共用；每帧只做「圆心 + 半径 × 方向 → 对齐 2 像素格」。
## 浮点算式与 _sk_arc_old 逐项同序（角度两种写法 span * u 与 span * i / n 各存一份），顶点逐位相同（--skdomtest 校验）
class _SkRec:
	var calls: Array = []
	func add_tris(pts: PackedVector2Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
		if cols.size() == 1:
			var col := cols[0]
			cols = PackedColorArray()
			cols.resize(pts.size())
			cols.fill(col)
		calls.append([pts, cols, idx])
	func same(o) -> bool:
		if calls.size() != o.calls.size():
			return false
		for i in calls.size():
			for j in 3:
				if calls[i][j] != o.calls[i][j]:
					return false
		return true

var _sk_test: bool = (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--skdomtest")
var _sk_test_n := 0
var _sk_test_bad := 0
var _sk_ac := {}          # 弧几何缓存：键 → [cos(a), sin(a), 粗细, 迎光 / 暗边 cos, sin]
var _sk_ac_beat := -1
var _sk_idx := {}
var _sk_gc := {}          # 贴边渐变：点数 → [cos, sin, 下标表]         # 条带下标表：点数 → PackedInt32Array（只跟点数有关）


## 小图案的合批写法（docs/287 §3 ⑧，OPT_SKPAT）：同一（图案, 翻转, 颜色, 头色, 投影色）把逐像素矩形展开成三角形（先投影后本体、
## 行列次序同上），以左上角为原点缓存；每次平移后一条 canvas_item_add_triangle_array 交给画布（原来每个美术像素一次 draw_rect，
## 鱼 / 音符 / 上浮箭头带投影每个图案几十次）。左上角对齐 2 像素格、顶点都是整数，覆盖的像素与逐个 draw_rect 相同
var _skp_cache := {}
var _skp_idx := {}

class _SkRectRec:
	var rects: Array = []
	func draw_rect(r: Rect2, c: Color, _f := true, _w := -1.0, _aa := false) -> void:
		rects.append([r, c])

var _skp_test: bool = (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--skpattest")
var _skp_test_n := 0
var _skp_test_bad := 0


# ================================================================ 德克萨斯（docs/257，照 docs/246 斯卡蒂 / docs/254 星熊的做法） → fx_pxplane_tx.gd（docs/286 §4 第三批拆出）

const TX_H := 24.0                       # 腰高（世界像素）：直线刀光离地高度

var _tx_spin := 0
var _txq: Array = []                     # 画面延时事件：[时刻, 种类, 数据]（落剑落地那一下的碎晶 / 照地光）


## 旧做法（2）：直线刀光 = 一张光晕烤进颜色的横条，旋转 + 横向拉伸到线长，盖在最上层
func _tx_draw_raw_lines(o) -> void:
	var cv = o.cv
	var m: Dictionary = _meta("tx_raw_line")
	if m.is_empty():
		return
	var tx: Texture2D
	var w: float = float(m.w)
	var h: float = float(m.h)
	var rect := Rect2(-float(m.ox), -float(m.oy), w, h)
	for it in items_for(str(o.id)):
		if str(it.ly) != "rawln" or str(it.oid) != str(o.id):
			continue
		var fi: int = int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8))
		if fi < 0 or fi >= int(m.n):
			continue
		var a: Vector2 = it.a
		var b: Vector2 = it.b
		var pos := (a + b) * 0.5 + Vector2(0, -TX_H)
		var rot := (b - a).angle()
		var sc := Vector2(a.distance_to(b) / w, g.PX * 1.37)
		if not _strip_in_view(cv, Transform2D(rot, sc, 0.0, pos) * rect):
			_reset_skipped_transform(cv, "tx_raw_line")
			continue
		if tx == null:
			tx = _tex("tx_raw_line")
			if tx == null:
				return
		cv.draw_set_transform(pos, rot, sc)
		cv.draw_texture_rect_region(tx, rect, _frame_region(m, fi))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 卡肉（render/melee_impact.meat 调）：这名干员最近出的斩击件（刀痕 / 旋斩 / 直线刀光）在命中那一拍多停 sec（按 15 fps 拍取整，至少 1 拍）
func stuck(o, sec: float) -> void:
	var b: float = maxf(1.0, round(sec * 15.0)) / 15.0
	var id: String = str(o.id)
	var n := 0
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if str(it.oid) != id or it.has("stk") or g.t - float(it.t0) > 0.1:
			continue
		if it.get("slash", false) or it.has("ln") or str(it.k).begins_with("tx_spin"):
			it["stk"] = b
			n += 1
			if n >= 4:
				return

