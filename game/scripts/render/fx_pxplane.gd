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
const Bal = preload("res://scripts/core/balance.gd")
const METAS := {"res://data/pxp_logos.json": "lg_", "res://data/pxp_skadi.json": "", "res://data/pxp_hoshiguma.json": "", "res://data/pxp_lumen.json": "lm_", "res://data/pxp_eyjafjalla.json": "ey_", "res://data/pxp_siege.json": "", "res://data/pxp_exusiai.json": "ex_", "res://data/pxp_mizuki.json": "", "res://data/pxp_angelina.json": "an_", "res://data/pxp_saria.json": "sa_", "res://data/pxp_texas.json": "", "res://data/pxp_gladiia.json": "gl_", "res://data/pxp_ulpianus.json": "ul_", "res://data/pxp_suzuran.json": "sz_", "res://data/pxp_irene.json": "ir_", "res://data/pxp_kaltsit.json": "ka_", "res://data/pxp_wisadel.json": "wd_", "res://data/pxp_skalter.json": "sk_", "res://data/pxp_specter_unchained.json": "su_", "res://data/pxp_lappland.json": "lp_"}   # 帧条表 → 键前缀（星熊的键自带 hsg_，流明帧条 art/fx/pxp/pxp_lm_<键>.png）
const MI = preload("res://scripts/render/melee_impact.gd")   # 近战打击感包（docs/246 §11）：斩痕 / 照地光提亮
const ART := "res://art/fx/pxp/pxp_%s.png"
const IDS := {"logos": true, "skadi": true, "hoshiguma": true, "lumen": true, "eyjafjalla": true, "siege": true, "exusiai": true, "mizuki": true, "angelina": true, "saria": true, "texas": true, "gladiia": true, "ulpianus": true, "suzuran": true, "irene": true, "kaltsit": true, "wisadel": true, "skalter": true, "specter_unchained": true, "lappland": true}
const GL = preload("res://scripts/render/fx_pxplane_gl.gd")   # 歌蕾蒂娅一节（docs/263）单独成文件
const UL = preload("res://scripts/render/fx_pxplane_ul.gd")   # 乌尔比安一节（docs/266）单独成文件
const KA = preload("res://scripts/render/fx_pxplane_kal.gd")   # 凯尔希一节（docs/265）单独成文件
const SU = preload("res://scripts/render/fx_pxplane_su.gd")   # 归溟幽灵鲨一节（docs/268）单独成文件
## 接管时仍照画的原 pfx 帧条（状态提示，不属于攻击特效）：星熊格挡闪光、反击架势盾沿光
const KEEP_PFX := {"hoshiguma": {"fx_hoshiguma_block": true, "fx_hoshiguma_guard_glow": true}, "gladiia": {"fx_gladiia_water_glide": true}}   # 歌蕾蒂娅水滑行是跑动拖尾，不属攻击特效
const LM_C := [Color("#121a2a"), Color("#1d3150"), Color("#2a5282"), Color("#4285ad"), Color("#7fb2d6"), Color("#c4e0f2"), Color("#ffffff")]   # house.js OP.lumen 钢蓝 7 阶
const LM_AC := Color("#ff9640")   # 精二点缀灯火橙
const DIRS := [-90, -45, 0, 45, 90]
const EMIT_CAP := 360     # 每帧送进发光层的 emit 点上限（整队）
const ITEM_MAX := 120   # 逻各斯（docs/258）消弹墨点 / 跳转笔较多：72 → 120

var g
var meta := {}
var tex := {}
var items: Array = []     # 一次性件：{k 帧条键, t0, gp 地面点, flip, ly up/gd, raw, rot, sc, oid}
var _mode := 0
var _mode_frame := -1
var _emit_n := 0
var _emit_frame := -1
var _ecol := {}
var _fol_tick := -1
var _fopl_tick := -1
var _fopo_tick := -1   # 艾雅法拉跟施放者的件（fopo = 干员对象、foff = 偏移，docs/259）


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
	if meta.is_empty():
		for path in METAS:
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				for kk in v:
					if str(kk) != "_doc":
						meta[str(METAS[path]) + str(kk)] = v[kk]
	return meta.get(k, {})


## 帧条按用到才读、60 秒（TEX_KEEP，局内时间）没画过就放掉（docs/287 §3 ⑥：原来读了整局不放，三人编队最重约 150 MB）；
## 再用到时重读（一张几 MB，几毫秒）。OPT_PXEVICT（--optold=536870912）置位不放
const TEX_KEEP := 60.0
var _tex_t := {}
var _tex_sweep := 0.0

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


func _tex(k: String) -> Texture2D:
	_tex_t[k] = g.t
	if not tex.has(k):
		var p: String = ART % k.replace("_d-", "_dm").to_lower()   # 负方向键（d-45）的文件名写成 dm45：素材命名不许连字符 / 大写（asset_lint N1；塞雷娅 pilB / pilS 的文件名一律小写）
		tex[k] = load(p) if ResourceLoader.exists(p) else null
	return tex[k]


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
	var raw: bool = mode() == 2
	var t: int = tier(o)
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var p: Dictionary = R.pal(o)
	if str(o.id) == "hoshiguma":
		_ev_hsg(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "lumen":
		_ev_lumen(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "skalter":
		_ev_skalter(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "gladiia":
		GL.ev(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "ulpianus":
		UL.ev(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "eyjafjalla":
		_ev_ey(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "kaltsit":
		KA.ev(self, o, kind, d, t, R, p)
		return
	if str(o.id) == "specter_unchained":
		SU.ev(self, o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "siege":
		_ev_sg(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "exusiai":
		_ex().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "texas":
		_ev_tx(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "mizuki":
		_ev_mz(o, kind, d, raw, t, R, p)
		return
	if str(o.id) == "angelina":   # docs/267：没有「旧做法原样贴」对照，2 时同 1 不画（owns_id 只在 1 接管）
		_an().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "saria":
		_sa().ev(o, kind, d, t, R, p)
		return
	if str(o.id) == "logos":
		_ev_logos(o, kind, d, raw, t, R, p)
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


func _push(it: Dictionary) -> void:
	if items.size() >= ITEM_MAX:
		items.pop_front()
	items.append(it)


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
	items = items.filter(func(it): return now - float(it.t0) < (float(it.life) if it.has("life") else _life(str(it.k))) + 0.02 and not (it.has("ef") and it.ef.get("dead", false)))
	for it in items:   # 卡肉（melee_impact.meat）：命中那一拍（第 1 帧）多停 stk 秒再接着扫
		if it.has("stk") and frame_of(float(it.t0)) >= 2:
			it.t0 = float(it.t0) + float(it.stk)
			it.erase("stk")
	var tk: int = int(floor(g.t * 15.0))
	if tk != _fol_tick:   # 跟人走的件：位置每拍（15 fps）跳一格，对齐美术像素格
		_fol_tick = tk
		for it in items:
			if it.has("fol") and g.ppos != Vector2.INF:   # 举盾：跟着队长
				it.gp = _snap(g.ppos + (it.fol as Vector2))
			elif it.get("fop", false):   # 星熊挂在身上的件（月牙刀痕、下劈弧、力之锯起手弧）：存续期间跟着出手的干员（11-05 用户实机「斩击不跟着人走」）
				var op = _op_by_id(str(it.oid))
				if op != null and op.pos != Vector2.INF:
					it.gp = _snap(op.pos)
			elif it.has("fe") and not it.fe.dead:   # 德克萨斯钉剑：跟着被钉的敌人（只读位置）
				it.gp = _snap(it.fe.pos)
	if tk != _fopo_tick:   # 跟着施放者本人走的件（艾雅法拉咏唱火缕 / 火山喷柱 / 出手火光，docs/259）：位置每拍跳一格
		_fopo_tick = tk
		for it in items:
			if it.has("fopo") and is_instance_valid(it.fopo) and it.fopo.pos != Vector2.INF:
				var np: Vector2 = _snap(it.fopo.pos + (it.foff as Vector2))
				if it.has("at"):
					it.at = np
				else:
					it.gp = np
	if tk != _fopl_tick:   # 挂在施放者身上的件（逻各斯笔光 / 字环，docs/258）：每拍（15 fps）跟到施放者当前脚底与朝向
		_fopl_tick = tk
		for it in items:
			if it.has("fopl"):
				var fo = it.fopl
				if is_instance_valid(fo) and fo.pos != Vector2.INF:
					it.gp = _snap(fo.pos)
					it.flip = float(fo.face) < 0.0
					if it.has("gy"):
						it.gy = float(fo.pos.y) + 2.0


func _life(k: String) -> float:
	if k == "":
		return 3.0 / 15.0   # 斩痕 3 拍
	var m: Dictionary = _meta(k)
	if m.is_empty():
		return 0.0
	return float(m.n) / minf(minf(float(m.fps), Bal.v("fx/px_plane_raw_fps", 12.8)), clock()) + 0.07


# ================================================================ 绘制

## 地面层（data_operator.draw_entities_floor → fx_recipe.draw_floor 转来）：贴地件、潮刃 / 浪墙的地面尾迹
func draw_floor(o) -> void:
	_step()
	if str(o.id) == "mizuki" and o.hw.has("mz"):
		_smz()._h3mz_draw_keep(o)   # 缠住标记 / 触手桩范围 / 灯火圈：状态件，接管时照画（docs/261）
	if mode() != 1:
		return
	var cv = o.cv
	var id: String = str(o.id)
	if id == "hoshiguma":
		_floor_hsg(o)
		return
	if id == "lumen":
		_lm_draw_floor(o)
		return
	if id == "skalter":
		_sk_draw_floor(o)
		return
	if id == "gladiia":
		GL.floor_layer(self, o)
		return
	if id == "eyjafjalla":
		_ey_floor(o)
		return
	if id == "kaltsit":
		KA.floor_layer(self, o)
		return
	if id == "specter_unchained":
		SU.floor_layer(self, o)
		return
	if id == "siege":
		_floor_sg(o)
		return
	if id == "exusiai":
		_ex().draw_floor(o)
		return
	if id == "texas":
		_floor_tx(o)
		return
	if id == "mizuki":
		_mz_draw_floor(o)
		return
	if id == "angelina":
		_an().draw_floor(o)
		return
	if id == "saria":
		_sa().draw_floor(o)
		return
	if id == "logos":
		_lg_draw_floor(o)
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
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
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
		_sg_draw_motes(o)   # 冲锋号令 / 跃空锤的全队技力粒子（状态提示：技力飞向队友）
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
		_lm_draw_raw(o)
		return
	if id == "skalter":
		_sk_draw_raw(o)
		return
	if id == "eyjafjalla":
		_ey_draw_raw(o)
		return
	if id == "texas":
		_tx_draw_raw_lines(o)
	if id == "mizuki" and o.hw.has("mz"):
		_smz()._h3mz_draw_jellies(o)   # 旧做法对照：深蓝之籽照原画法
	if id == "logos":
		_lg_draw_raw(o)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8)), it.gp, float(it.rot), float(it.sc))
	if id == "logos":
		return
	if id == "hoshiguma":   # 般若回旋的锯盾：旧做法整张贴（正圆、光晕烤进颜色、盖在上面）
		for bm in _booms(o):
			_draw_raw(cv, "hsg_raw_saw", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), int(_meta("hsg_raw_saw").get("n", 1))), o.pos + bm.dir * _boom_d(bm) + Vector2(0, -22), 0.0, g.PX)
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
	for it in r.items:
		if str(it.ly) == "up":
			it["skey"] = r._skey(it)   # 跟人 / 跟怪的件按当前位置排序（另存 skey，不动星熊地刺的 sk 偏移）
			out.append(it)
	for o in game.squad.ops:
		if IDS.has(str(o.id)) and o.pos != Vector2.INF:
			if str(o.id) == "lumen":
				r._lm_sort_items(o, out)
				continue
			if str(o.id) == "skalter":
				r._sk_sort_items(o, out)
				continue
			if str(o.id) == "gladiia":
				GL.sort_items(r, o, out)
				continue
			if str(o.id) == "eyjafjalla":
				r._ey_sort_items(o, out)
				continue
			if str(o.id) == "kaltsit":
				KA.sort_items(r, o, out)
				continue
			if str(o.id) == "specter_unchained":
				SU.sort_items(r, o, out)
				continue
			if str(o.id) == "mizuki":
				r._mz_sort_items(o, out)
				continue
			if str(o.id) == "exusiai":
				r._ex().sort_items(o, out)
				continue
			if str(o.id) == "texas":
				r._tx_sort_items(o, out)
				continue
			if str(o.id) == "angelina":
				r._an().sort_items(o, out)
				continue
			if str(o.id) == "saria":
				r._sa().sort_items(o, out)
				continue
			if str(o.id) == "logos":
				r._lg_sort_items(o, out)
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
				for bm in r._booms(o):
					out.append({"k": "hsg_saw_up", "t0": 0.0, "gp": r._boom_gp(o, bm), "flip": false, "loop": true})
				for qv in r._qi_volleys(o):
					out.append({"k": qv.k + "_up_d%d" % qv.d, "fi": qv.f, "gp": qv.gp, "flip": qv.flip})
	return out


static func draw_sorted(game, ci, it: Dictionary) -> void:
	var r = game.get_meta("fx_pxplane")
	if it.has("skr"):   # 浊心斯卡蒂（docs/260）：运行时立起件
		r._sk_draw_up(ci, it)
		return
	if it.has("skr_s"):
		r._sk_draw_state_up(ci, it)
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
		r._tx_draw_line(ci, it, false)
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
		r._ey_draw_rt(ci, it)
		return
	if it.has("rt"):
		r._lm_draw_rt(ci, it)
		return
	if it.has("glrt"):
		GL.draw_rt(r, ci, it)
		return
	if it.has("mzj"):
		r._mz_draw_jelly(ci, it)
		return
	if it.has("lrt"):
		r._lg_draw_rt(ci, it)
		return
	if it.has("loopk"):
		r._draw_strip(ci, str(it.loopk), r.frame_of(0.0), r._gp(it), false, false)
		return
	if it.get("loop", false) and it.has("life"):   # 循环一次性件（艾雅法拉连携熔岩泡）：带淡入淡出
		r._draw_strip(ci, str(it.k), r.frame_of(0.0), r._gp(it), false, false, Color(1, 1, 1, r._ey_loop_a(it)))
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


## 一张帧条的一帧：1 帧条像素 = g.PX 世界像素（整数倍），原点对齐 2 像素格；不旋转（方向靠预生成 + 水平翻转）
func _draw_strip(ci, k: String, fi: int, gp: Vector2, flip: bool, once: bool, mod := Color.WHITE, emit := true) -> void:
	var m: Dictionary = _meta(k)
	var tx: Texture2D = _tex(k)
	if m.is_empty() or tx == null:
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
	var src := Rect2(fi * w, 0.0, w, h)
	if flip:   # 水平翻转用镜像变换，不用负宽矩形：负宽矩形在 GL 兼容渲染下整张往右错开一个帧宽（11-05 德克萨斯旋斩实测，发光点却在原位）
		ci.draw_set_transform(Vector2(left + w * px, top), 0.0, Vector2(-1.0, 1.0))
		ci.draw_texture_rect_region(tx, Rect2(Vector2.ZERO, Vector2(w * px, h * px)), src, mod)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_texture_rect_region(tx, Rect2(Vector2(left, top), Vector2(w * px, h * px)), src, mod)
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
	var pts: Array = m.emit[fi] if fi < m.emit.size() else []
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
	var tx: Texture2D = _tex(k)
	if m.is_empty() or tx == null:
		return
	if fi < 0 or fi >= int(m.n):
		return
	var w: float = float(m.w)
	var h: float = float(m.h)
	cv.draw_set_transform(at, rot, Vector2(sc, sc))
	cv.draw_texture_rect_region(tx, Rect2(Vector2(-float(m.ox), -float(m.oy)), Vector2(w, h)), Rect2(fi * w, 0.0, w, h))
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ================================================================ 星熊（docs/254，照 docs/246 斯卡蒂的做法）
## 普攻「盾斧斩」= 腰高钝头刀痕（精一盾缘崩钢屑、精二暖金副刃 + 金火星；精二另有「般若回旋」锯盾）；
## S1「战意」= 立起的下劈弧 + 裂网冲击环 + 碎石（精一尘墙、精二裂缝熔成暖金）；
## S2「荆棘」= 起手一圈地刺破土 + 每斩留的热砂（只画边 + 内边 + 几点热光）；
## S3「力之锯」= 起手腰高青绿弧旋起 + 直线撕裂（贴地撕裂沟 + 低处锯线 + 远端暖金火星），持续时脚下一圈转动的齿印。

func _ev_hsg(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG hsg %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			var es: Array = d.get("es", [])
			if d.get("line", false):   # 力之锯：直线斩（seg_hoshiguma.exec_line 的钩子）
				var ang: float = float(d.get("ang", 0.0))
				var L: float = float(d.get("len", 220.0))
				var dv := Vector2.from_angle(ang)
				if raw:
					_push({"k": "hsg_raw_rip", "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (L * 0.5) / 110.0, "oid": str(o.id)})
				else:
					_add_dir(o, "hsg_rip_l%d" % _bucket(L * 0.5, [110, 140]), o.pos, ang)
				_cuts(o, es, 2, 3)
				_burst_m(o, R, p, o.pos + dv * L * 0.9 + Vector2(0, -12), o.pos.y + dv.y * L * 0.9, es, 6, "shard", 130.0, 0.5)
				return
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 60.0))
				match src:
					"举盾反击":   # S1 战意：下劈 + 裂网冲击环（判定圈以星熊为心）
						var fl: bool = float(o.face) < 0.0
						if raw:
							_push({"k": "hsg_raw_slam_e%d" % t, "t0": g.t, "gp": c, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 75.0, "oid": str(o.id)})
						else:
							var sk: String = "hsg_slam_r%d_e%d" % [_bucket(r * 0.5, [75, 95]), t]
							_push({"k": sk + "_up", "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "up", "oid": str(o.id), "fop": true})   # 下劈弧跟人；裂网冲击环（_gd）是落在地上的，留在原地
							_push({"k": sk + "_gd", "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "gd", "oid": str(o.id)})
						_cuts(o, es, t, 4)
						_burst_m(o, R, p, c + Vector2(-30.0 if fl else 30.0, -6), c.y + 2.0, es, 8 + 3 * t, "rock", 0.0, 0.0, false)
						if mode() == 1:   # 落地那一下：一盏照地灯 200 / 0.80（docs/270 §3「爆发」140–240 / 0.6–0.9；协调人 11-05 定：有没有打中都挂），打中时挂在第一只敌人身上，没打中挂在落点
							R._light(o, (es[0].pos + Vector2(0, -float(es[0].r) * 0.5)) if not es.is_empty() else c + Vector2(-30.0 if fl else 30.0, -6), 200.0, 0.8, 0.12, p.light)
					"热砂", "热砂沸腾":
						pass   # 热砂每 0.5 秒结算一次：画面由区域本身（_floor_hsg 读 o.fields）表现，不逐跳画
					_:   # 般若之重 / 盾墙反震：贴地冲击环
						if not raw:
							_push({"k": "hsg_pulse_gd", "t0": g.t, "gp": _snap(c), "flip": false, "ly": "gd", "oid": str(o.id)})
						_burst_m(o, R, p, c + Vector2(0, -8), c.y + 2.0, es, 3, "rock", 110.0, 0.4)
				return
			# 锥形：盾斧斩（普攻）
			var ang2: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 94.0))
			var dv2 := Vector2.from_angle(ang2)
			_add(o, "hsg_sweep_r%d_e%d" % [_bucket(r2 * 0.5, [47, 56, 66]), t], o.pos, ang2, r2, raw, "hsg_raw_sweep_e%d" % t, 47.0)
			if not raw:
				_follow_last(o, 2)   # 刀痕（立起 + 投影）跟着星熊走
			_cuts(o, es, t, 2)
			_burst_m(o, R, p, o.pos + dv2 * r2 * 0.6 + Vector2(0, -12), o.pos.y + dv2.y * r2 * 0.6 * 0.72, es, 2 + t, "shard" if t >= 1 else "rock", 90.0, 0.35)
		"cover":   # 技能连携 v2「举盾」：队长身侧立起鬼面大盾 1.5 秒（盾跟着队长走：fol = 相对队长的偏移）
			var sd2: Vector2 = d.get("side", Vector2.RIGHT)
			var off: Vector2 = sd2 * 46.0
			if raw:
				_push({"k": "hsg_raw_slam_e0", "t0": g.t, "gp": g.ppos + off, "ly": "raw", "rot": 0.0, "sc": g.PX * 30.0 / 75.0, "oid": str(o.id)})
			else:
				_push({"k": "hsg_cover_up", "t0": g.t, "gp": _snap(g.ppos + off), "fol": off, "flip": sd2.x < 0.0, "ly": "up", "oid": str(o.id)})
				_push({"k": "hsg_cover_gd", "t0": g.t, "gp": _snap(g.ppos + off), "fol": off, "flip": sd2.x < 0.0, "ly": "gd", "oid": str(o.id)})
			_burst_m(o, R, p, g.ppos + off + Vector2(0, -20), g.ppos.y + off.y + 2.0, [], 6, "shard", 140.0, 0.6)
		"combo_dash":   # 连携技冲刺：沿途几颗碎石（代替通用干员色拖影）
			if mode() == 1:
				var a0: Vector2 = d.get("from", o.pos)
				var b0: Vector2 = d.get("to", o.pos)
				for k in 3:
					var q: Vector2 = a0.lerp(b0, 0.25 + 0.3 * k)
					R._grains(o, q + Vector2(0, -4), q.y + 2.0, "rock", 2, {"tier": 1})
		"combo":   # 连携技「举盾推挡」：盾落点立起大盾往外推 + 队长脚下冲击环与放射推痕
			var cc: Vector2 = d.get("c", o.pos)
			var at: Vector2 = d.get("at", o.pos)
			var sd: Vector2 = d.get("side", Vector2.RIGHT)
			if raw:
				_push({"k": "hsg_raw_slam_e1", "t0": g.t, "gp": cc, "ly": "raw", "rot": 0.0, "sc": g.PX * 70.0 / 75.0, "oid": str(o.id)})
			else:
				var dk: Array = pick_dir(sd.angle() if sd.length() > 0.5 else 0.0)
				_push({"k": "hsg_shove_up_d%d" % dk[0], "t0": g.t, "gp": _snap(at), "flip": dk[1], "ly": "up", "oid": str(o.id)})
				_push({"k": "hsg_shove_gd", "t0": g.t, "gp": _snap(cc), "flip": false, "ly": "gd", "oid": str(o.id)})
			_burst_m(o, R, p, cc + Vector2(0, -10), cc.y + 2.0, d.get("es", []), 8, "rock", 200.0, 0.8)
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1:   # 荆棘起手：一圈地刺破土（身后半圈排在她身后、身前半圈排在她身前）
				var tt: int = maxi(t, 1)
				if raw:
					_push({"k": "hsg_raw_thorns_e%d" % tt, "t0": g.t, "gp": o.pos + Vector2(0, -8), "ly": "raw", "rot": 0.0, "sc": g.PX, "oid": str(o.id)})
				else:
					_push({"k": "hsg_thorns_e%d_back_up" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "sk": -8.0})
					_push({"k": "hsg_thorns_e%d_front_up" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "sk": 4.0})
					_push({"k": "hsg_thorns_e%d_gd" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -20), o.pos.y, "shard", 6 + 3 * tt, {"tier": tt})
					R._light(o, o.pos + Vector2(0, -10), 120.0, 0.5, 0.15, p.accent)
			elif i == 2:   # 力之锯起手：腰高三道青绿弧旋起 + 脚下冲击环
				if raw:
					_push({"k": "hsg_raw_slam_e2", "t0": g.t, "gp": o.pos, "ly": "raw", "rot": 0.0, "sc": g.PX * 50.0 / 75.0, "oid": str(o.id)})
				else:
					_push({"k": "hsg_s3cast_up", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "fop": true})   # 身边旋起的青绿弧跟人
					_push({"k": "hsg_s3cast_gd", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if mode() == 1:
					R._light(o, o.pos + Vector2(0, -20), 140.0, 0.6, 0.15, p.light)


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


## 地面层（星熊）：贴地件、热砂（读 o.fields，循环 + 淡入淡出）、力之锯持续时脚下齿印、锯盾影子
func _floor_hsg(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var t: int = clampi(tier(o), 1, 2)
	for f in o.fields:
		if not f.get("sand", false):
			continue
		var fa: float = clampf((float(f.n) * float(f.every) - float(f.t)) / 0.4, 0.0, 1.0) * clampf(float(f.t) / 0.15, 0.0, 1.0)
		if fa <= 0.0:
			continue
		var rk: int = 40 if float(f.r) >= 70.0 else 30
		_draw_strip(cv, "hsg_sand%d_e%d_gd" % [rk, t], frame_of(0.0), _snap(f.pos), false, false, Color(1, 1, 1, fa))
	if o.skill_active_left(2) > 0.0:
		_draw_strip(cv, "hsg_s3aura_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)
	for bm in _booms(o):
		_draw_strip(cv, "hsg_saw_gd", frame_of(0.0), _boom_gp(o, bm), false, false)
	for qv in _qi_volleys(o):
		_draw_strip(cv, qv.k + "_gd_d%d" % qv.d, int(qv.f), qv.gp, qv.flip, true)


## 般若回旋：读玩法状态 o.el.boom（往返弹体）
func _booms(o) -> Array:
	var el = o.get("el")
	if not (el is Dictionary) or el.is_empty() or not el.has("boom"):
		return []
	return el.boom


## 弹体此刻离星熊的距离（同 ob_elite._el_boom_d，纯函数抄一份，只读）
static func _boom_d(bm: Dictionary) -> float:
	var t: float = float(bm.t)
	var to: float = float(bm.to)
	if t < to:
		var k: float = t / maxf(0.01, to)
		return float(bm.L) * (1.0 - (1.0 - k) * (1.0 - k))
	if t < to + float(bm.hold):
		return float(bm.L)
	var k2: float = clampf((t - to - float(bm.hold)) / maxf(0.01, float(bm.tb)), 0.0, 1.0)
	return float(bm.L) * (1.0 - k2 * k2)


## 锯盾的地面点：统一节拍时每 1/15 秒跳一格（记在弹体字典的画面专用键 _pxq，玩法不读）
func _boom_gp(o, bm: Dictionary) -> Vector2:
	var p: Vector2 = o.pos + bm.dir * _boom_d(bm)
	if not is_equal_approx(clock(), 15.0):
		return p
	var tick: int = int(floor(g.t * 15.0))
	var q = bm.get("_pxq")
	if q == null or int(q[0]) != tick:
		q = [tick, _snap(p)]
		bm["_pxq"] = q
	return q[1]


## 尺寸档：判定半径（美术像素）挑最近的一档（帧条按几档预生成，游戏只整数放大）
static func _bucket(v: float, opts: Array) -> int:
	return PxU.nearest(opts, v)


## 后期剑气（growth/late_shape → vis_growth._fire_qi）：同一次出手的几道剑气合成一道盾击冲击波（不碎）。
## 只读玩法状态 o.vg.qi；按出手时刻分组：位置 / 方向取平均，横向宽度按道数取 1 / 2 / 3+ 三档。
## 帧：出手第一拍热白（0）→ 常态（1）→ 剩余寿命 < 0.07 秒碎开（2）。位置按 15 fps 节拍跳格（记在剑气字典的画面专用键 _pxq，玩法不读）
func _qi_volleys(o) -> Array:
	var out: Array = []
	if mode() != 1 or o.vg.is_empty() or not o.vg.has("qi") or o.vg.qi.is_empty():
		return out
	var grp: Dictionary = {}
	for q in o.vg.qi:
		var key: int = int(round((g.t - float(q.t)) * 60.0))
		if not grp.has(key):
			grp[key] = {"p": Vector2.ZERO, "v": Vector2.ZERO, "n": 0, "t": float(q.t), "life": float(q.life), "qs": []}
		var e: Dictionary = grp[key]
		e.p += _qpos(q)
		e.v += (q.v as Vector2).normalized()
		e.n += 1
		e.life = minf(float(e.life), float(q.life))
		e.qs.append(q)
	var t: int = tier(o)
	var keys: Array = grp.keys()
	keys.sort()
	keys.reverse()
	for key in keys.slice(0, 2):   # 同屏至多两组（最新两次出手）
		var e: Dictionary = grp[key]
		var n: int = int(e.n)
		var S: int = 10 if n <= 1 else (16 if n == 2 else 22)
		var dk: Array = pick_dir((e.v as Vector2).angle())
		var f: int = 0 if float(e.t) < 1.0 / 15.0 else (2 if float(e.life) < 0.07 else 1)
		out.append({"k": "%s_qi_s%d_e%d" % ["sg" if str(o.id) == "siege" else "hsg", S, t], "d": dk[0], "flip": dk[1], "gp": _snap(e.p / float(n)), "f": f})
	return out


func _qpos(q: Dictionary) -> Vector2:
	if not is_equal_approx(clock(), 15.0):
		return q.p
	var tick: int = int(floor(g.t * 15.0))
	var c = q.get("_pxq")
	if c == null or int(c[0]) != tick:
		c = [tick, q.p]
		q["_pxq"] = c
	return c[1]

# ================================================================ 流明（docs/255，照斯卡蒂 docs/246 的做法）
## 帧条件（tools/pxplane_bake_lumen.py，键前缀 lm_）：光弹命中 / 折光落点 / 荧光治疗 / 出光点 / 沐雨 v3 / 光雨雨区（循环）/ 沛霖水柱 / 灯火不灭起手 · 光圈（循环）· 光爆；
## 线状件在运行时按美术像素格逐格画（光弹、折光、灯塔光柱 + 地面光痕、治疗连线、灯塔守望光扇）：方向任意，不旋转贴图，2 世界像素一格、15 fps 节拍换形。
## 光弹位置每帧走（380 像素 / 秒，按 15 fps 跳格一次跳 25 像素会一卡一卡），只取整到美术像素格；弹头形状按 15 fps 节拍换。
## 旧做法（2）：旧放开版帧条（tools/pixelfx_fx/lumen_ul_ref）光晕烤进颜色，小数缩放 + 旋转，盖在所有单位上。

var _slm = null

func _sl():
	if _slm == null:
		_slm = load("res://scripts/characters/blocks/seg_lumen.gd")   # 运行时取（避免和积木链循环 preload）
	return _slm


func _lm_up(o, k: String, at: Vector2, gy: float, fol := false, e = null) -> void:
	if k.begins_with("hit"):   # 命中水花同屏上限（同一名干员）：主弹至多 5 团、小水花（发光单元 / 额外弹 / 折光 / 连锁 / 光柱穿透）至多 3 团——后期弹多也不叠成一片白
		var small: bool = k.begins_with("hits")
		var n := 0
		for it in items:
			if str(it.oid) == str(o.id) and str(it.k).begins_with("lm_hits" if small else "lm_hit_") and str(it.ly) == "up":
				n += 1
		if n >= (3 if small else 5):
			return
	# 跟人（框架 11-05，docs/246 §10）：fol = 挂在队长身上（治疗、沐雨、沛霖、S3 起手、连携落点），按 15 fps 节拍跟着队长跳格；e = 跟着被打的那只（命中水花）
	var it := {"k": "lm_" + k, "t0": g.t, "gp": _snap(at), "gyo": gy - _snap(at).y, "flip": false, "ly": "up", "oid": str(o.id)}
	if fol and g.ppos != Vector2.INF:
		it["fol"] = _snap(at) - g.ppos
	if e != null:
		it["e"] = e
	_push(it)


func _lm_gd(o, k: String, at: Vector2, fol := false) -> void:
	var it := {"k": "lm_" + k, "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)}
	if fol and g.ppos != Vector2.INF:
		it["fol"] = _snap(at) - g.ppos
	_push(it)


func _lm_raw(o, k: String, at: Vector2, rot: float, sc: float) -> void:
	_push({"k": "lm_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


## 技能起手的照地光晚一拍（1/15 秒）亮：沐雨 / 沛霖 / 灯火不灭的帧条第 0 拍几乎是空的、主形第 1 拍才出来，发光层又晚一帧显示；
## 光若在施放那一帧就最亮，会比主形先到（光感体检 docs/270 量到的就是「有光没芯」那一帧）。走 fx_recipe 同一个灯表，只是起点挪后
func _lm_light_beat(R, o, at: Vector2, r: float, inten: float, col: Color) -> void:
	R.lights.append([at, r, col, g.t + 1.0 / 15.0, 0.15, inten, str(o.id)])
	if R.lights.size() > 32:
		R.lights.pop_front()


func _ev_lumen(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var px: float = g.PX
	match kind:
		"lm_hit":   # 光弹命中：立起水花（原点 = 命中点，按敌人脚底排序）+ 地上湿痕；发光单元的弹小一号、不留湿痕
			var e: Dictionary = d.e
			var at: Vector2 = d.at
			var small: bool = d.get("unit", false)
			if raw:
				_lm_raw(o, "raw_hit_e%d" % t, at, 0.0, px * (0.75 if small else 1.15))
				return
			_lm_up(o, ("hits_e%d_up" if small else "hit_e%d_up") % t, at, float(e.pos.y) + 1.0, false, e)
			if not small:
				_lm_gd(o, "hit_e%d_gd" % t, e.pos + Vector2(0, 2))
				# 命中亮芯（光感体检 docs/270：普攻命中帧发光核心只有 14 < 30）：水花的白芯只在第 0 拍，这里在命中点另挂 3 拍亮芯进发光层，跟着被打的那只
				_push({"rt": "hcore", "e": e, "a": at, "t": t, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(e.pos.y) + 1.5, "oid": str(o.id), "k": ""})
			_burst(o, R, p, at, float(e.pos.y) + 2.0, [e], (1 if small else 2) + t, 60.0 + 15.0 * t, 0.3 + 0.1 * t)
		"lm_refract":   # 精一折光：命中点到下一只之间一道 1 美术像素白芯细光，落点小水花
			var a: Vector2 = d.a
			var b: Vector2 = d.b
			if raw:
				_push({"rt": "rawline", "a": a, "b": b, "t0": g.t, "life": 0.12, "ly": "raw", "oid": str(o.id), "k": ""})
				_lm_raw(o, "raw_hit_e1", b, 0.0, px * 0.6)
				return
			_push({"rt": "line", "a": a, "b": b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", b.y + 10.0)), "oid": str(o.id), "k": ""})
			_lm_up(o, "hits_e%d_up" % t, b, float(d.get("gy", b.y + 10.0)))
			R._light(o, b, 60.0, 0.35, 0.1, p.light)
		"lm_pillar":   # 精二灯塔光柱：出光点一颗四芒星 + 一道实心光柱（任意方向逐格画）+ 地上一道光痕；命中的前 4 只各一团水花
			var from: Vector2 = d.from
			var dv: Vector2 = d.d
			var L: float = float(d.L)
			var foot: Vector2 = d.get("foot", from)
			var es: Array = d.get("es", [])
			if raw:
				_lm_raw(o, "raw_pillar", from, dv.angle(), px * L / 200.0 * 1.13)
				for e in es.slice(0, 4):
					_lm_raw(o, "raw_hit_e2", e.pos + Vector2(0, -float(e.r) * 0.5), 0.0, px * 1.15)
				return
			_push({"rt": "beam", "a": _snap(from), "d": dv, "L": L, "W": float(d.get("W", 10.0)), "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": foot.y + 1.0, "oid": str(o.id), "k": ""})
			_push({"rt": "streak", "a": _snap(foot), "d": dv, "L": L, "t0": g.t, "life": 3.0 / 15.0, "ly": "gd", "oid": str(o.id), "k": ""})
			_lm_up(o, "flare_up", from, foot.y + 2.0)
			items[items.size() - 1]["fo"] = _snap(from) - o.pos   # 出光点跟着流明走
			R._light(o, from, 90.0, 0.55, 0.12, p.light)
			R._light(o, foot + dv * L * 0.6, 110.0, 0.35, 0.12, p.light)
			for e in es.slice(0, 3):   # 一线穿透：每只一团小水花（至多 3 团），不叠成一片白
				var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.5)
				_lm_up(o, "hits_e2_up", hp, float(e.pos.y) + 1.0, false, e)
			if not es.is_empty():
				_burst(o, R, p, from, foot.y, [es[0]], 3, 70.0, 0.4)
		"lm_mend":   # 荧光治疗：队长身前一侧卷上去一缕水流
			var at2: Vector2 = d.at
			for it in items:   # 沐雨同一拍也会回血：只画沐雨，不再叠一缕水流（同一招元素 ≤ 3）
				if str(it.k).begins_with("lm_drizzle") or str(it.k).begins_with("lm_raw_drizzle"):
					if is_equal_approx(float(it.t0), g.t):
						return
			if raw:
				_lm_raw(o, "raw_mend_e%d" % t, at2, 0.0, px * 1.15)
				return
			_lm_up(o, "mend_e%d_up" % t, at2, at2.y + 1.0, true)
			R._light(o, at2 + Vector2(0, -30), 70.0, 0.35, 0.12, p.light)
		"lm_link":   # 提灯到治疗落点的细光（2 拍）
			if raw:
				_push({"rt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": 0.25, "ly": "raw", "oid": str(o.id), "k": ""})
				return
			_push({"rt": "link", "a": d.a, "b": d.b, "t0": g.t, "life": 2.0 / 15.0, "ly": "up", "gy": (d.b as Vector2).y + 24.0, "oid": str(o.id), "k": ""})
		"shape":   # 灯塔守望·回光（watch2：沐雨时与灯火不灭期间每秒一圈，玩法是 ob_core 圆形判定）：判定半径上边弧原地闪一下 + 一盏照地光
			if not d.get("circle", false):
				return
			var pc: Vector2 = d.get("c", g.ppos)
			if raw:
				_lm_raw(o, "raw_burst", pc, 0.0, px * float(d.get("r", 120.0)) / 220.0 * 1.13)
				return
			_lm_gd(o, "pulse_gd", pc)
			R._light(o, pc + Vector2(0, -10), float(d.get("r", 120.0)), 0.4, 0.12, p.light)
		"lm_xhit":   # 后期额外弹命中：小一号水花；同一拍至多 3 团（弹数随档位增加，画面不跟着碎）
			var xe: Dictionary = d.e
			if _lm_beat_n(o, "xh") >= 3:
				return
			if raw:
				_lm_raw(o, "raw_hit_e%d" % t, d.at, 0.0, px * 0.75)
				return
			_lm_up(o, "hits_e%d_up" % t, d.at, float(xe.pos.y) + 1.0, false, xe)
		"lm_chain":   # 「连锁」弹射：同折光一套 1 美术像素细光；同一拍至多 3 道
			if _lm_beat_n(o, "ch") >= 3:
				return
			if raw:
				_push({"rt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": 0.14, "ly": "raw", "oid": str(o.id), "k": ""})
				return
			_push({"rt": "line", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
			_lm_up(o, "hits_e%d_up" % t, d.b, float(d.get("gy", 0.0)))
		"lm_cshot":   # 连携技「清创光弹」出手：一颗大光弹飞向队长
			if raw:
				_push({"rt": "rawcbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "raw", "oid": str(o.id), "k": ""})
				return
			_push({"rt": "cbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "up", "gy": (d.b as Vector2).y + 31.0, "oid": str(o.id), "k": ""})
			R._light(o, d.a, 70.0, 0.4, 0.1, p.light)
		"lm_lfire":   # 连携 v2「清创光弹」（skill_link l_lumen）：提灯一颗大光弹 0.13 秒飞到队长胸口 → 炸开（同 lm_cleanse）；连携区域 1.2 秒内光尘往上飘
			var la: Vector2 = d.a
			var lt: Vector2 = d.at
			var lc: Vector2 = d.c
			if raw:
				_push({"rt": "rawcbolt", "a": la, "b": lt + Vector2(0, -30), "t0": g.t, "life": 0.13, "ly": "raw", "oid": str(o.id), "k": ""})
				_lm_raw(o, "raw_hit_e2", lt + Vector2(0, -30), 0.0, px * 1.7)
				return
			_push({"rt": "cbolt", "a": la, "b": lt + Vector2(0, -30), "t0": g.t, "life": 0.13, "ly": "up", "gy": lt.y + 1.0, "oid": str(o.id), "k": ""})
			var t1: float = g.t + 0.13
			_push({"k": "lm_cleanse_up", "t0": t1, "gp": _snap(lt + Vector2(0, -30)), "gyo": 31.0, "fol": _snap(lt + Vector2(0, -30)) - g.ppos, "flip": false, "ly": "up", "oid": str(o.id)})
			_push({"k": "lm_cleanse_gd", "t0": t1, "gp": _snap(lc), "flip": false, "ly": "gd", "oid": str(o.id)})
			_push({"k": "lm_lmotes_up", "t0": t1, "gp": _snap(lc), "gy": lc.y + 1.0, "flip": false, "ly": "up", "oid": str(o.id)})
			R._light(o, lt + Vector2(0, -20), 170.0, 0.8, 0.15, p.light)
			R._grains(o, lt + Vector2(0, -30), lt.y, "ink", 4, {"tier": 1})
		"lm_cleanse":   # 连携技落点：队长胸口一团大水花 + 灯火橙光尘上飘；地上照亮范围边弧原地闪一下
			var ct: Vector2 = d.at
			if raw:
				_lm_raw(o, "raw_hit_e2", ct + Vector2(0, -30), 0.0, px * 1.7)
				return
			_lm_up(o, "cleanse_up", ct + Vector2(0, -30), ct.y + 1.0, true)
			_lm_gd(o, "cleanse_gd", ct, true)
			R._light(o, ct + Vector2(0, -20), 170.0, 0.8, 0.15, p.light)
			R._grains(o, ct + Vector2(0, -30), ct.y, "ink", 4, {"tier": 1})
		"lm_burst":   # 灯火不灭结束光爆：短粗双层星芒 + 竖光柱；地上判定半径边弧原地闪一下
			var at3: Vector2 = d.at
			if raw:
				_lm_raw(o, "raw_burst", at3, 0.0, px * float(d.get("r", 220.0)) / 220.0 * 1.13)
				return
			_lm_up(o, "burst_up", at3, at3.y + 1.0)
			_lm_gd(o, "burst_gd", at3)
			R._light(o, at3 + Vector2(0, -60), 240.0, 0.9, 0.15, p.light)
			R._grains(o, at3 + Vector2(0, -60), at3.y, "ink", 8, {"tier": 2})
		"skill":
			var i: int = int(d.get("i", -1))
			var lp: Vector2 = g.ppos
			if i == 0:   # 沐雨 v3：脚下涟漪弧法阵（贴地）+ 斜细雨 / 十字星 / 精二灯塔光柱（立起）
				items = items.filter(func(it): return not ((str(it.k).begins_with("lm_mend") or str(it.k).begins_with("lm_raw_mend")) and is_equal_approx(float(it.t0), g.t)))
				if raw:
					_lm_raw(o, "raw_drizzle_e%d" % t, lp, 0.0, px * 1.07)
					return
				_lm_gd(o, "drizzle_e%d_gd" % t, lp, true)
				_lm_up(o, "drizzle_e%d_up" % t, lp, lp.y + 1.0, true)
				_lm_light_beat(R, o, lp + Vector2(0, -20), 150.0, 0.45 + 0.1 * t, p.light)
			elif i == 1:   # 沛霖：头顶水柱砸下（精二三道）+ 落点湿痕
				var tt: int = maxi(t, 1)
				if raw:
					_lm_raw(o, "raw_downpour_e%d" % tt, lp, 0.0, px * 1.13)
					return
				_lm_up(o, "downpour_e%d_up" % tt, lp, lp.y + 1.0, true)
				_lm_gd(o, "downpour_e%d_gd" % tt, lp, true)
				_lm_light_beat(R, o, lp + Vector2(0, -20), 130.0, 0.6, p.light)
				R._grains(o, lp + Vector2(0, -24), lp.y, "ink", 3 + 2 * tt, {"tier": tt})
			elif i == 2:   # 灯火不灭起手：头顶四芒灯光 + 水流卷上去；光圈原地亮起
				if raw:
					_lm_raw(o, "raw_lamp", lp, 0.0, px * 1.13)
					return
				_lm_up(o, "s3open_up", lp, lp.y + 1.0, true)
				_lm_gd(o, "s3open_gd", lp, true)
				_lm_light_beat(R, o, lp + Vector2(0, -96), 160.0, 0.7, p.light)


## 同一名干员这一拍（1/15 秒）已出的某类件数（额外弹命中 / 连锁），超过上限就不再加画面
var _beat_cnt := {}

func _lm_beat_n(o, k: String) -> int:
	return PxU.beat_n(_beat_cnt, g.t, str(o.id) + k)


## 贴地层：一次性件 + 运行时线状贴地件 + 状态件（光雨雨区、灯塔光圈、灯塔守望光扇）
func _lm_draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	for it in items:
		if str(it.ly) != "gd" or str(it.oid) != id:
			continue
		if it.has("rt"):
			_lm_draw_rt(cv, it)
		else:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	if float(lm.get("rain_t", 0.0)) > 0.0:
		_draw_strip(cv, "lm_rain_gd", frame_of(0.0), _snap(g.ppos), false, false)
	var S = _sl()
	if S._h3_tower_on(o):
		_draw_strip(cv, "lm_tower_gd", frame_of(0.0), _snap(lm.tower_pos), false, false)
	var bb: Dictionary = S._h3_beam_block(o)
	if S._h3_beam_on(o, bb):
		_lm_beam_trace(cv, o, lm, bb)


## 立起层的状态件：光弹（运行时）、光雨雨点（循环帧条）、灯塔光尘（循环帧条）
func _lm_sort_items(o, out: Array) -> void:
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	for b in lm.bolts:
		out.append({"rt": "bolt", "b": b, "o": o, "gy": (b.pos as Vector2).y + 30.0})
	if not o.vg.is_empty():   # 后期额外弹：同时最多画最新的 6 颗（更早的照常结算伤害，只是不画；弹数随档位增加，画面不变碎）
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"rt": "xbolt", "b": xb, "o": o, "gy": (xb.p as Vector2).y + 1.0})
	if float(lm.get("rain_t", 0.0)) > 0.0:
		out.append({"loopk": "lm_rain_up", "gp": _snap(g.ppos), "gy": g.ppos.y + 1.0})
	if _sl()._h3_tower_on(o):
		var tp: Vector2 = lm.tower_pos
		out.append({"loopk": "lm_tower_up", "gp": _snap(tp), "gy": tp.y + 1.0})
	var bb: Dictionary = _sl()._h3_beam_block(o)
	if _sl()._h3_beam_on(o, bb):   # 灯塔守望光束（立起层，和队长 / 灯塔一起按脚底 y 排）
		var gb: Vector2 = lm.tower_pos if _sl()._h3_tower_on(o) else g.ppos
		out.append({"rt": "wbeam", "o": o, "bb": bb, "gy": gb.y + 1.0})


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


## 运行时线状件：line 折光 / link 治疗连线 / beam 灯塔光柱 / streak 光柱地面光痕 / bolt 光弹
func _lm_draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	var C: Array = LM_C
	match str(it.rt):
		"line", "link":
			var f: int = frame_of(float(it.t0))
			var link: bool = str(it.rt) == "link"
			var nb: int = 2 if link else 3
			if f < 0 or f >= nb:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / px))
			for i in n + 1:
				var u: float = float(i) / float(n)
				if f == 2 and u < 0.5:
					continue   # 最后一拍只剩靠落点的一半
				var q: Vector2 = a.lerp(b, u)
				var core: Color = (C[6] if f == 0 else C[5]) if not link else (C[5] if f == 0 else C[4])
				_px(ci, q, core)
				if f == 0 and not link and i % 3 == 0:
					_glow(q, C[6])
		"beam":   # 光柱：第 0 拍满宽白芯 → 往中线收 → 从出光端熄；最远端 15% 收尖
			var f2: int = frame_of(float(it.t0))
			if f2 < 0 or f2 > 3:
				return
			var a2: Vector2 = it.a
			var dv: Vector2 = it.d
			var nv := Vector2(-dv.y, dv.x)
			var L: float = float(it.L)
			var hw: float = float(it.W) / px * 0.5 * [1.0, 0.75, 0.45, 0.25][f2]   # 半宽（美术像素）
			var s: float = L * [0.0, 0.0, 0.25, 0.55][f2]
			var k := 0
			while s <= L:
				var u: float = s / L
				var w: float = hw * (1.0 if u < 0.85 else (1.0 - u) / 0.15)
				var c0: Vector2 = a2 + dv * s
				var m: int = int(round(w))
				for q in range(-m, m + 1):
					var edge: bool = absi(q) == m and m > 0
					var col: Color = C[3] if edge else (C[6] if (f2 <= 1 and absi(q) <= maxi(0, m - 2)) else (C[5] if absi(q) <= 1 else C[4]))
					_px(ci, c0 + nv * float(q) * px, col)
				if f2 <= 1 and k % 3 == 0:
					_glow(c0, C[6])
				s += px
				k += 1
		"streak":   # 光柱在地上的光痕（照亮的地面）：1 美术像素钢蓝线，3 拍里从出光端往外熄
			var f3: int = frame_of(float(it.t0))
			if f3 < 0 or f3 > 2:
				return
			var a3: Vector2 = it.a
			var L3: float = float(it.L)
			var s3: float = L3 * [0.0, 0.3, 0.6][f3]
			while s3 <= L3:
				_px(ci, a3 + (it.d as Vector2) * s3, C[3] if f3 == 0 else C[2])
				s3 += px
		"bolt":   # 光弹（普攻 / 发光单元）
			var b: Dictionary = it.b
			_lm_bolt(ci, b.pos, b.vel, tier(it.o), b.get("big", false), str(b.get("src", "")) == "发光单元")
		"xbolt":   # 后期额外弹（growth/late_shape 等的 vis_growth 弹体）：同一套光弹，小一号（同发光单元）
			var xb: Dictionary = it.b
			_lm_bolt(ci, (xb.p as Vector2) + Vector2(0, -18.0), xb.v, tier(it.o), false, true)
		"wbeam":
			_lm_draw_wbeam(ci, it.o, it.bb)
		"hcore":   # 命中亮芯：第 0 拍 3×3 + 十字臂、第 1 拍 3×3、第 2 拍中心 + 四点；每点 1 美术像素白芯并进 emit（精二中心一点灯火橙）
			var fh: int = frame_of(float(it.t0))
			if fh < 0 or fh > 2:
				return
			var e: Dictionary = it.e
			var c: Vector2 = (e.pos + Vector2(0, -float(e.r) * 0.5)) if not e.get("dead", false) else (it.a as Vector2)
			var pts: Array = []
			if fh <= 1:
				for yy in [-1, 0, 1]:
					for xx in [-1, 0, 1]:
						pts.append(Vector2(xx, yy))
				if fh == 0:
					pts.append_array([Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2), Vector2(3, 0), Vector2(-3, 0)])
			else:
				pts = [Vector2.ZERO, Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
			for q in pts:
				var pp: Vector2 = c + q * px
				var col: Color = C[6] if (fh == 0 or (q as Vector2).length() < 1.5) else C[5]
				if int(it.t) >= 2 and q == Vector2.ZERO and fh <= 1:
					col = LM_AC
				_px(ci, pp, col)
				_glow(pp, C[6] if col != LM_AC else LM_AC)
		"cbolt":   # 连携技「清创光弹」：提灯到队长胸口飞 travel 秒，大一号、不分档（尾 18 格 + 两格宽芯 + 灯火橙芯）
			var u: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.life)), 0.0, 1.0)
			var ca: Vector2 = it.a
			var cb: Vector2 = it.b
			_lm_bolt(ci, ca.lerp(cb, u), cb - ca, 2, true, false, true)


## 一颗光弹：雨滴形弹头（白芯 + 冰蓝）+ 钢蓝尾，尾长分档；精一弹头前缘四芒折光星（按拍闪），精二尾更长、尾根一点灯火橙。位置每帧走、取整到美术像素格
func _lm_bolt(ci, pos: Vector2, vel: Vector2, t: int, big: bool, unit: bool, link := false) -> void:
	var px: float = g.PX
	var C: Array = LM_C
	var dv2: Vector2 = vel.normalized()
	var nv2 := Vector2(-dv2.y, dv2.x)
	var head: Vector2 = _snap(pos)
	var tl: int = [9, 12, 16][t] + (4 if big else 0) - (3 if unit else 0) + (2 if link else 0)
	var beat: int = int(floor(g.t * 15.0))
	for i in tl:
		var u: float = float(i) / float(tl)
		var w: int = 1 if i < 3 else 0
		if link and i < tl * 0.6:
			w = 1
		elif t >= 1 and i * 2 < tl and i >= 3:
			w = 1 if (i + beat) % 3 != 0 else 0
		var col: Color = C[6] if i == 0 else (C[5] if i < 3 else (C[4] if u < 0.55 else C[3]))
		var q: Vector2 = head - dv2 * float(i) * px
		_px(ci, q, col)
		for side in range(1, w + 1):
			_px(ci, q + nv2 * px * side, C[4] if i < 3 else C[3])
			_px(ci, q - nv2 * px * side, C[4] if i < 3 else C[3])
	_px(ci, head + dv2 * px, C[5])
	if t >= 2:
		_px(ci, head - dv2 * px * 2.0, LM_AC)
	if t >= 1 and beat % 2 == 0:   # 折光星
		for dd in [1, 2]:
			var cc: Color = C[6] if dd == 1 else C[5]
			_px(ci, head + dv2 * px * float(dd + 1), cc)
			_px(ci, head + nv2 * px * float(dd), cc)
			_px(ci, head - nv2 * px * float(dd), cc)
	if unit:
		_glow(head, C[6])
		_glow(head - dv2 * px, C[5])
	else:   # 主弹弹头一团 3×3 亮芯进发光层（光感体检 docs/270：发光层晚一帧显示，命中那一帧亮的是弹头上一帧留下的辉光，2 点太弱）
		for yy in [-1, 0, 1]:
			for xx in [-1, 0, 1]:
				_glow(head + Vector2(xx, yy) * px, C[6] if absi(xx) + absi(yy) <= 1 else C[5])


## 灯塔守望光束（11-05 用户「流明那个光束得重新做一下」；原来是贴地光扇、两道边带缺口——又碎又平、不亮）。
## 重做：一道实心光束从队长胸口（灯塔在场时从灯塔灯口）射出，由高到低斜落到判定线末端（立起、有高度差），窄 → 宽、整道连续；
## 白只给芯的前 35%，身子冰蓝 / 钢蓝，远端降一阶；出光点一颗小四芒星（精二芯一点灯火橙）；沿光束两盏照地光（亮度靠光，不靠大片白）；
## 地上一道 1 美术像素暗钢蓝光痕把光束「落」在地面上。方向取玩法的连续角度（每帧转，不按 15 fps 跳格：2 秒一圈、按拍跳一次就是 12°，末端一跳 50 多像素），形状逐格画、对齐像素格。
## 三档：光束末端半宽 5 / 6.5 / 8 美术像素，精一起芯加宽一格，精二出光点灯火橙。淡入淡出只收宽度、降色阶，不用半透明。
func _lm_wbeam_geo(o, lm: Dictionary, bb: Dictionary) -> Dictionary:
	var S = _sl()
	var twr: bool = S._h3_tower_on(o)
	var gorg: Vector2 = lm.tower_pos if twr else g.ppos
	var dv: Vector2 = S._h3_beam_dir(o, bb)
	var L: float = float(bb.get("len", 260.0))
	var src: Vector2 = S._h3_tower_lamp(o) if twr else g.ppos + Vector2(0, -34)
	var fade: float = clampf((float(lm.get("tower_t", 0.0)) if twr else float(lm.get("beam_t", 0.0))) / 0.5, 0.0, 1.0)
	return {"gorg": gorg, "dv": dv, "L": L, "src": src, "tip": gorg + dv * L + Vector2(0, -6), "fade": fade}


func _lm_beam_trace(cv, o, lm: Dictionary, bb: Dictionary) -> void:
	var ge: Dictionary = _lm_wbeam_geo(o, lm, bb)
	if float(ge.fade) <= 0.05:
		return
	var L: float = float(ge.L)
	var s: float = L * 0.2
	while s <= L:
		_px(cv, (ge.gorg as Vector2) + (ge.dv as Vector2) * s, LM_C[3] if s > L * 0.45 else LM_C[2])
		s += g.PX


func _lm_draw_wbeam(ci, o, bb: Dictionary) -> void:
	var lm: Dictionary = o.hw.lm
	var ge: Dictionary = _lm_wbeam_geo(o, lm, bb)
	var fade: float = float(ge.fade)
	if fade <= 0.05:
		return
	var px: float = g.PX
	var C: Array = LM_C
	var t: int = tier(o)
	var src: Vector2 = ge.src
	var tip: Vector2 = ge.tip
	var span: Vector2 = tip - src
	var Ls: float = span.length()
	if Ls < 4.0:
		return
	var du: Vector2 = span / Ls
	var nv := Vector2(-du.y, du.x)
	var w1: float = [5.0, 6.5, 8.0][t] * (0.35 + 0.65 * fade)
	var dim: int = 1 if fade < 0.5 else 0
	var core_w: int = 0 if t == 0 else 1
	var s: float = 0.0
	var k := 0
	while s <= Ls:
		var u: float = s / Ls
		var w: float = 1.0 + (w1 - 1.0) * u
		if u > 0.88:
			w *= 1.0 - (u - 0.88) / 0.12 * 0.6   # 远端收一点，不是方头
		var m: int = int(round(w))
		var far: int = (1 if u > 0.75 else 0) + dim
		var c0: Vector2 = src + du * s
		for q in range(-m, m + 1):
			var aq: int = absi(q)
			var ci_: int
			if aq <= core_w:
				ci_ = 6 if u < 0.35 else 5
			elif aq < maxi(1, int(m * 0.5)):
				ci_ = 5
			elif aq < m:
				ci_ = 4
			else:
				ci_ = 3
			_px(ci, c0 + nv * float(q) * px, C[clampi(ci_ - far, 2, 6)])
		if u < 0.6 and k % 3 == 0:
			_glow(c0, C[6] if u < 0.35 else C[5])
		s += px
		k += 1
	# 出光点：小四芒星（精二芯一点灯火橙）
	var arm: int = 3 + t
	for dd in range(1, arm + 1):
		var cc: Color = C[6] if dd <= 1 else C[5]
		for v in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_px(ci, src + v * px * float(dd), cc)
	_px(ci, src, LM_AC if t >= 2 else C[6])
	_glow(src, C[6])
	# 照地光：光束中段与末端各一盏（每帧跟着光束走，走配方灯光预算）
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var p: Dictionary = R.pal(o)
	R._light_follow(o, (ge.gorg as Vector2) + (ge.dv as Vector2) * float(ge.L) * 0.5, 80.0 + 10.0 * t, 0.45 * fade, p.light)
	R._light_follow(o, (ge.gorg as Vector2) + (ge.dv as Vector2) * float(ge.L) * 0.9, 70.0 + 10.0 * t, 0.35 * fade, p.light)


## 旧做法（2）：旧放开版帧条整张贴（光晕烤进颜色、小数缩放、旋转），盖在所有单位上
func _lm_draw_raw(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		if str(it.get("rt", "")) == "rawcbolt":
			var cu: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.life)), 0.0, 1.0)
			_draw_raw(cv, "lm_raw_bolt_e2", posmod(int(g.t * rf), maxi(1, int(_meta("lm_raw_bolt_e2").get("n", 1)))), (it.a as Vector2).lerp(it.b, cu), ((it.b as Vector2) - (it.a as Vector2)).angle(), g.PX * 1.6)
			continue
		if str(it.get("rt", "")) == "rawline":
			var kk: float = 1.0 - (g.t - float(it.t0)) / maxf(0.01, float(it.life))
			cv.draw_line(it.a, it.b, Color(0.77, 0.88, 0.95, 0.9 * kk), 2.0)
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
	if not o.hw.has("lm"):
		return
	var lm: Dictionary = o.hw.lm
	var t: int = tier(o)
	var lf: int = int(g.t * rf)
	for b in lm.bolts:
		var mk: Dictionary = _meta("lm_raw_bolt_e%d" % t)
		_draw_raw(cv, "lm_raw_bolt_e%d" % t, posmod(lf, maxi(1, int(mk.get("n", 1)))), b.pos, (b.vel as Vector2).angle(), g.PX * (1.4 if b.get("big", false) else 1.13))
	if not o.vg.is_empty():
		var mx: Dictionary = _meta("lm_raw_bolt_e%d" % t)
		for xb in o.vg.bul:
			_draw_raw(cv, "lm_raw_bolt_e%d" % t, posmod(lf, maxi(1, int(mx.get("n", 1)))), (xb.p as Vector2) + Vector2(0, -18.0), (xb.v as Vector2).angle(), g.PX * 0.9)
	if float(lm.get("rain_t", 0.0)) > 0.0:
		_draw_raw(cv, "lm_raw_rain", posmod(lf, maxi(1, int(_meta("lm_raw_rain").get("n", 1)))), g.ppos, 0.0, g.PX * 1.07)
	var S = _sl()
	if S._h3_tower_on(o):
		_draw_raw(cv, "lm_raw_tower", posmod(lf, maxi(1, int(_meta("lm_raw_tower").get("n", 1)))), lm.tower_pos, 0.0, g.PX * 1.07)
	var bb: Dictionary = S._h3_beam_block(o)
	if S._h3_beam_on(o, bb):
		var dv: Vector2 = S._h3_beam_dir(o, bb)
		_draw_raw(cv, "lm_raw_sweep", posmod(lf, maxi(1, int(_meta("lm_raw_sweep").get("n", 1)))), S._h3_beam_origin(o), dv.angle(), g.PX * float(bb.get("len", 260.0)) / 260.0 * 1.13)


# ================================================================ 逻各斯（docs/258，照斯卡蒂 docs/246 / 流明 docs/255 的做法）
## 帧条件（tools/pxplane_bake_logos.py，键前缀 lg_）：命中星芒 + 碎刺 / 地面墨环、出手笔光 + 字环、提喻每跳、殁亡交叉咒文链 + 墨柱、延异视阈起手。
## 运行时逐格画（2 世界像素一格，方向任意、不旋转贴图，形状按 15 fps 节拍换）：「言」墨迹彗星（白头尖细 + 深蓝墨尾）、提喻咒文行、连缀咒文链、
## 殁亡溢出跳转笔、咒域（只画边 + 淡渐变 + 外沿细字行）、连携字环 / 消弹墨点、铭文 / 墓志铭地面咒文。咒文一律 3×5 细字（1 美术像素笔画）。
## 彗星位置每帧走、只取整到像素格（同流明光弹：按 15 fps 跳格会一卡一卡）。
## 旧做法（2）：旧放开版帧条（tools/pixelfx_fx/logos_ul_ref）光晕烤进颜色，小数缩放 + 旋转，盖在所有单位上。

const LG_C := [Color("#28355f"), Color("#495694"), Color("#6a78ca"), Color("#8c99ff"), Color("#b4bdff"), Color("#dce0ff"), Color("#ffffff")]   # house.js OP.logos 7 阶
const LG_INK := [Color("#0b0d22"), Color("#161c3e")]   # 墨（压底两阶）
const LG_AC := Color("#a487ff")   # 精二点缀紫
const LG_GOLD := Color("#e8d6a0")   # 连携「黑金咒文」的淡金（只点在少数字上）
const LG_SY := 0.72
## 细字咒文 3×5（同 ak-logos-pp.js 的 GLYPHS）：每字 15 位，行优先
const LG_GL := ["111010010010011", "101111001001001", "110001010100011", "010111010010110", "100110101100111",
	"011100111001110", "101101010101101", "111100110100100", "010010111000101", "110101110100100"]
const LG_BOLT_LEN := [24, 28, 32]   # 墨尾长（美术像素，11-05 第四轮对原作：约 3/4 身高）：放大只放在长度上，弹头三档一样尖

var _lg_fire_t := -9.0


static func _lg_h(i: int) -> float:
	return fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)


func _lg_up(o, k: String, at: Vector2, gy: float, flip := false, follow := false) -> void:
	if k.begins_with("hit_"):   # 同屏上限：主命中至多 3 团同时在画，再多换小一号；小一号至多 3 团（后期多弹不叠成一片白）
		var n := 0
		for it in items:
			if str(it.oid) == "logos" and str(it.get("k", "")).begins_with("lg_hit_") and str(it.ly) == "up":
				n += 1
		if n >= (3 if tier(o) < 1 else 2):   # 第六轮：精一 / 精二命中亮核大，怪群密时同屏主命中压到 2 团
			k = k.replace("hit_", "hits_")
	if k.begins_with("hits_"):
		var n2 := 0
		for it in items:
			if str(it.oid) == "logos" and str(it.get("k", "")).begins_with("lg_hits_") and str(it.ly) == "up":
				n2 += 1
		if n2 >= 3:
			return
	var it := {"k": "lg_" + k, "t0": g.t, "gp": _snap(at), "gy": gy, "flip": flip, "ly": "up", "oid": "logos"}
	if follow:
		it["fopl"] = o   # 逻各斯跟施放者（对象本身；星熊用的 fop 是布尔 + 按 id 找人，键分开）
	_push(it)


func _lg_gd(k: String, at: Vector2) -> void:
	_push({"k": "lg_" + k, "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": "logos"})


func _lg_raw(k: String, at: Vector2, rot: float, sc: float) -> void:
	_push({"k": "lg_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": "logos"})


func _lg_tip(o) -> Vector2:
	var tv = o.B.get("attack", {}).get("tip", [40, -36])
	return o.pos + Vector2(float(tv[0]) * float(o.face), float(tv[1]))


func _ev_logos(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var px: float = g.PX
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG lg %s %s %.3f" % [kind, str(d.get("i", "")), g.t])
	match kind:
		"fire":   # 出手：身前笔光 → 身周细字字环 + 笔尖星芒（原点 = 脚底；朝左水平翻转）。连发（复指 / 天赋）0.25 秒内只画一次
			if g.t - _lg_fire_t < 0.25 and g.t >= _lg_fire_t:
				return
			_lg_fire_t = g.t
			var hand: Vector2 = d.get("at", _lg_tip(o))
			if raw:
				_lg_raw("raw_start_e%d" % t, hand, (d.get("dir", Vector2.RIGHT) as Vector2).angle(), px)
				return
			_lg_up(o, "fire_e%d_up" % t, o.pos, o.pos.y + 2.0, float(o.face) < 0.0, true)
			R._light(o, hand, 60.0, 0.3, 0.1, p.light)
			if t >= 1:
				R._grains(o, hand, o.pos.y + 2.0, "twinkle", 1 + t, {"tier": t}, d.get("dir", Vector2.RIGHT))
		"hit":   # 「言」命中（原作 hit_01）：白色星芒 + 不规整长碎刺，冷成深蓝 → 墨；地上一圈墨环
			var e: Dictionary = d.e
			var at: Vector2 = d.get("at", e.pos)
			if raw:
				_lg_raw("raw_hit_e%d" % t, at, (at - o.pos).angle(), px)
				return
			_lg_up(o, "hit_e%d_up" % t, at, float(e.pos.y) + 1.0)
			_lg_gd("hit_e%d_gd" % t, e.pos + Vector2(0, 2))
			R._light(o, at, 90.0 + 20.0 * t, 0.5 + 0.1 * t, 0.12, p.light)
			R._grains(o, at, float(e.pos.y) + 2.0, "ink", 1 + t, {"tier": t}, (at - o.pos).normalized())
			if t >= 1:
				R._grains(o, at, float(e.pos.y) + 2.0, "twinkle", t, {"tier": t})
		"exec":   # 殁亡处决（原作 hit_03）：交叉细字咒文链 + 竖墨柱；溢出伤害跳转 = 一笔墨（白笔头）写到下一只
			var e2: Dictionary = d.e
			var tt: int = maxi(t, 1)
			var foot: Vector2 = e2.pos
			if raw:
				_lg_raw("raw_epitaph", foot, 0.0, px * 0.9)
				if d.has("to"):
					var dv0: Vector2 = (d.to as Vector2) - (d.at as Vector2)
					_lg_raw("raw_link", d.at, dv0.angle(), px * dv0.length() / 128.0)
				return
			_lg_up(o, "exec_e%d_up" % tt, foot, foot.y + 1.0)
			_lg_gd("exec_e%d_gd" % tt, foot + Vector2(0, 2))
			R._light(o, foot + Vector2(0, -40), 150.0, 0.75, 0.14, p.light)
			R._grains(o, foot + Vector2(0, -30), foot.y + 2.0, "ink", 3 + tt, {"tier": tt})
			if d.has("to"):
				var b: Vector2 = d.to
				_push({"lrt": "jump", "a": d.at, "b": b, "t0": g.t + 0.05, "life": 4.0 / 15.0, "ly": "up", "gy": b.y + 12.0, "oid": "logos", "k": ""})
				_push({"k": "lg_hits_e%d_up" % t, "t0": g.t + 0.05 + 2.0 / 15.0, "gp": _snap(b), "gy": b.y + 12.0, "flip": false, "ly": "up", "oid": "logos"})
		"lock_tick":   # 提喻每一跳：目标身上一颗小星芒 + 碎刺（白 → 冷）
			var pts: Array = d.get("pts", [])
			if pts.is_empty():
				return
			var pt: Vector2 = pts[0][0]
			if raw:
				_lg_raw("raw_tick_e%d" % t, pt, (pt - o.pos).angle(), px * 0.8)
				return
			_lg_up(o, "tick_e%d_up" % t, pt, float(pts[0][1]))
			R._light(o, pt, 70.0, 0.35, 0.1, p.light)
		"fan_tick":   # 延异视阈每一跳：笔尖向咒域里至多 4 只各射一道墨迹彗星（0.2 秒飞到），落点小星芒
			var pts2: Array = d.get("pts", [])
			if raw:
				for q in pts2:
					_lg_raw("raw_hit_e2", q[0], 0.0, px * 0.7)
				return
			var tip: Vector2 = _lg_tip(o)
			for i in pts2.size():
				var q2: Vector2 = pts2[i][0]
				var t1: float = g.t + 0.03 * i
				_push({"lrt": "vbolt", "a": tip, "b": q2, "t0": t1, "life": 0.2, "ly": "up", "gy": float(pts2[i][1]), "oid": "logos", "k": "", "tier": 2, "side": 1.0 if i % 2 == 0 else -1.0})
				_push({"k": "lg_hits_e1_up", "t0": t1 + 0.2, "gp": _snap(q2), "gy": float(pts2[i][1]), "flip": false, "ly": "up", "oid": "logos"})
			if not pts2.is_empty():
				R._light(o, pts2[0][0], 110.0, 0.45, 0.12, p.light)
		"lg_xhit":   # 后期额外弹命中：小一号星芒；同一拍至多 3 团
			if _lm_beat_n(o, "xh") >= 3:
				return
			if raw:
				_lg_raw("raw_hit_e%d" % t, d.at, 0.0, px * 0.6)
				return
			_lg_up(o, "hits_e%d_up" % t, d.at, float((d.e as Dictionary).pos.y) + 1.0)
		"lg_chain":   # 「连锁」弹射：一笔墨跳转 + 落点小星芒；同一拍至多 3 道
			if _lm_beat_n(o, "ch") >= 3:
				return
			if raw:
				var dv1: Vector2 = (d.b as Vector2) - (d.a as Vector2)
				_lg_raw("raw_link", d.a, dv1.angle(), px * dv1.length() / 128.0)
				return
			_push({"lrt": "jump", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": "logos", "k": ""})
			_lg_up(o, "hits_e%d_up" % t, d.b, float(d.get("gy", 0.0)))
		"lg_link":   # 连携 v2「消弹」（skill_link l_logos）：区域上空浮起一圈细字咒文（少数淡金 = 原作黑金），被消的每颗敌弹化一点墨落下
			var c: Vector2 = d.c
			var r: float = float(d.r)
			var gone: PackedVector2Array = d.get("gone", PackedVector2Array())
			if raw:
				_lg_raw("raw_seal", c, 0.0, px * (r + 20.0) / 80.0)
				return
			_push({"lrt": "seal", "c": _snap(c), "r": r + 20.0, "t0": g.t, "life": 0.8, "ly": "up", "gy": c.y + (r + 20.0) * LG_SY, "oid": "logos", "k": ""})
			_push({"lrt": "ring", "c": _snap(c), "r": r + 20.0, "t0": g.t, "life": 0.6, "ly": "gd", "oid": "logos", "k": ""})
			for i in mini(gone.size(), 16):
				_push({"lrt": "pop", "c": _snap(gone[i]), "t0": g.t + 0.02 * (i % 5), "life": 0.4, "ly": "up", "gy": gone[i].y + 20.0, "oid": "logos", "k": "", "gi": i})
			R._light(o, c, r + 60.0, 0.6, 0.15, p.light)
		"lg_cshot":   # 连携技（combo.gd，link/v2 = 0）出手：一颗大彗星飞到落点
			if raw:
				_push({"lrt": "rawline", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "raw", "oid": "logos", "k": ""})
				return
			_push({"lrt": "vbolt", "a": d.a, "b": d.b, "t0": g.t, "life": float(d.travel), "ly": "up", "gy": (d.b as Vector2).y + 1.0, "oid": "logos", "k": "", "tier": 2, "side": 1.0, "big": true})
		"lg_combo":   # 连携技「咒文扩散」落点：大墨环闪一下；处决的每只一道墨笔 + 殁亡咒文链（至多 6）
			var tp: Vector2 = d.at
			var es: Array = d.get("es", [])
			if raw:
				_lg_raw("raw_seal", tp, 0.0, px * 1.5)
				return
			_push({"lrt": "ring", "c": _snap(tp), "r": 240.0, "t0": g.t, "life": 0.45, "ly": "gd", "oid": "logos", "k": ""})
			_lg_up(o, "hit_e2_up", tp + Vector2(0, -10), tp.y + 1.0)
			for i in mini(es.size(), 6):
				var ee: Dictionary = es[i]
				_push({"lrt": "jump", "a": tp + Vector2(0, -10), "b": ee.pos + Vector2(0, -8), "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": float(ee.pos.y) + 1.0, "oid": "logos", "k": ""})
				_push({"k": "lg_exec_e2_up", "t0": g.t + 0.1, "gp": _snap(ee.pos), "gy": float(ee.pos.y) + 1.0, "flip": false, "ly": "up", "oid": "logos"})
			R._light(o, tp, 260.0, 0.85, 0.15, p.light)
			R._grains(o, tp + Vector2(0, -20), tp.y, "ink", 6, {"tier": 2})
		"skill":
			var si: int = int(d.get("i", -1))
			if si == 1:   # 殁亡（永久）：起手一圈字环
				if raw:
					_lg_raw("raw_start_e%d" % maxi(t, 1), _lg_tip(o), 0.0, px * 1.2)
					return
				_lg_up(o, "fire_e%d_up" % maxi(t, 1), o.pos, o.pos.y + 2.0, float(o.face) < 0.0, true)
				R._light(o, o.pos + Vector2(0, -30), 110.0, 0.5, 0.14, p.light)
			elif si == 2:   # 延异视阈起手：双层字环 → 笔尖蓄势 → 开域爆亮
				if raw:
					_lg_raw("raw_seal", o.pos + Vector2(0, -20), 0.0, px)
					return
				_lg_up(o, "s3open_up", o.pos, o.pos.y + 2.0, float(o.face) < 0.0, true)
				var tip2: Vector2 = _lg_tip(o)
				R._light(o, tip2, 160.0, 0.8, 0.15, p.light)
				R._grains(o, tip2, o.pos.y + 2.0, "twinkle", 5, {"tier": 2})


## 贴地层：一次性件 + 运行时贴地件 + 状态件（咒域、提喻目标脚下墨环、铭文 / 墓志铭）
func _lg_draw_floor(o) -> void:
	var cv = o.cv
	for it in items:
		if str(it.ly) != "gd" or str(it.oid) != "logos":
			continue
		if it.has("lrt"):
			_lg_draw_rt(cv, it)
		else:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), it.gp, it.flip, true)
	var h: Dictionary = o.hw
	if h.has("s3_shots"):   # 原画法在绘制时清理出手轨迹；接管后由这里清，免得列表只增不减
		var now: float = g.t
		h["s3_shots"] = h.s3_shots.filter(func(sh): return now - float(sh.t0) < 0.3)
	if h.has("pools"):
		for l in h.pools:
			if str(l.b.get("look", "")) == "rune":
				_lg_pool(cv, l)
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.get("t", 0.0)) > 0.0 and lk.e != null and not lk.e.dead:
		var ramp: float = clampf(int(lk.n) / float(lk.b.get("ramp_n", 12.0)), 0.0, 1.0)
		var rr: float = 11.0 + 5.0 * ramp
		_lg_ell(cv, lk.e.pos + Vector2(0, 3), rr, 1.0, 1, 7)
		if tier(o) >= 1:
			_lg_ell(cv, lk.e.pos + Vector2(0, 3), rr + 5.0, 0.8, 0, 11)
	var fn = h.get("fan", {})
	if fn is Dictionary and not fn.is_empty() and float(fn.get("t", 0.0)) > 0.0:
		_lg_fan(cv, o, fn)


## 地面细椭圆环（美术像素格，按噪声断续）：r 美术像素
func _lg_ell(ci, c: Vector2, r: float, a: float, hi: int, sd: int) -> void:
	var px: float = g.PX
	var n: int = maxi(12, int(TAU * r))
	var cc: Vector2 = _snap(c)
	for i in n:
		var an: float = TAU * i / n
		var hv: float = _lg_h(sd * 977 + i)
		if hv < 0.22 or hv > a + 0.22:
			continue
		var q: Vector2 = cc + Vector2(cos(an) * r, sin(an) * r * LG_SY) * px
		var lit: bool = hi > 0 and sin(an) > 0.3 and hv > 0.55
		ci.draw_rect(Rect2(_snap(q), Vector2(px, px)), LG_C[4] if lit else (LG_C[2] if hv > 0.7 else LG_INK[1]))


## 二次贝塞尔（弯的符文行 / 锁链用）
static func _lg_bez(a: Vector2, c: Vector2, b: Vector2, s: float) -> Vector2:
	var u: float = 1.0 - s
	return a * (u * u) + c * (2.0 * u * s) + b * (s * s)


## a → b 往上拱 bow（世界像素）的控制点：弧顶离弦 bow
static func _lg_bow_ctrl(a: Vector2, b: Vector2, bow: float) -> Vector2:
	var d: Vector2 = b - a
	var n := Vector2(-d.y, d.x).normalized()
	if n.y > 0.0:
		n = -n
	return (a + b) * 0.5 + n * bow * 2.0


func _lg_glyph(ci, p: Vector2, gi: int, col: Color) -> void:
	var px: float = g.PX
	var s: String = LG_GL[posmod(gi, LG_GL.size())]
	var o0: Vector2 = _snap(p) - Vector2(px, 2.0 * px)
	for k in 15:
		if s.unicode_at(k) == 49:
			ci.draw_rect(Rect2(o0 + Vector2(k % 3, k / 3) * px, Vector2(px, px)), col)


## 铭文 / 墓志铭（成长节点）：地上一圈断续墨环 + 上方浮着几个细字；墓志铭从少到多写满
func _lg_pool(ci, l: Dictionary) -> void:
	var al: float = clampf(float(l.t) / 0.3, 0.0, 1.0)
	var burst: bool = l.b.get("burst", false)
	var k: float = 1.0 - float(l.t) / maxf(0.01, float(l.dur)) if burst else 1.0
	var r: float = float(l.r) / g.PX
	_lg_ell(ci, l.pos, r * (0.6 + 0.4 * k), al, 1, int(l.pos.x))
	var beat: int = int(floor(g.t * 15.0))
	var n: int = 3 if not burst else 1 + int(k * 4.0)
	for i in n:
		var x: float = (float(i) - (n - 1) * 0.5) * 5.0
		var bob: float = (2.0 if ((beat / 4 + i) % 2) == 0 else 0.0) - 0.12 * x * x   # 浮字排成一小段弧（第六轮：不留笔直的字行）
		var c: Color = LG_C[5] if (beat / 3 + i) % 4 != 0 else LG_C[6]
		c.a = al
		_lg_glyph(ci, l.pos + Vector2(x, -18.0 - bob) * g.PX, int(l.pos.x) + i * 3 + beat / 8, c)


## 延异视阈咒域（原作 range_01；11-05 第三轮用户「改成渐变填充」「符文条太直」）：
## 填充 = 亮蓝边缘往中心渐暗（7 阶，最浓 α 0.38，怪透得出来），每个美术像素按 interleaved gradient noise 抖动取相邻两阶，不出平涂色带；
## 外边 2 格亮边保留；域内随机冒出咒文段（第七轮：每段 6–10 字各走各的曲线，一个个写出来再扭一下，停 0.8–1.2 秒后逐字褪去，段尾细丝 + 墨点，部分字暗紫辉光，同屏至多 4 段）；每跳外边亮一拍
const LG_FILL := [[Color("#0b0d22"), 0.34], [Color("#161c3e"), 0.34], [Color("#28355f"), 0.32], [Color("#495694"), 0.33],
	[Color("#6a78ca"), 0.36], [Color("#8c99ff"), 0.38], [Color("#b4bdff"), 0.38]]
const LG_SEG_N := 4   # 咒文段同屏上限（第七轮：段变长，段数从 6 减到 4）
const LG_SEG_P := 2.1   # 每段一轮的秒数（书写 ≈ 0.4–0.6 秒 + 停 0.8–1.2 秒 + 褪去）
const LG_GLOW := Color("#6a4fc0")   # 咒文暗紫辉光（进发光层）


## 一段咒文的曲线（扇形平面坐标、美术像素、未压扁）：龟形走法每步 4 像素，转角按类型给——0 螺旋收拢 / 1 波浪起伏 / 2 弯钩 / 3 往外甩。
## 返回 [Vector3(x, y, 朝向)]，6–10 个
func _lg_seg_path(sd: int, rc: float, fa: float, half: float) -> Array:
	var typ: int = int(_lg_h(sd + 9) * 4.0)
	var n: int = 6 + int(_lg_h(sd + 3) * 5.0)
	var af: float = (_lg_h(sd + 1) * 2.0 - 1.0) * 0.8
	var rf: float = 0.30 + 0.5 * _lg_h(sd + 2)
	var a0: float = fa + half * af
	var x: float = cos(a0) * rc * rf
	var y: float = sin(a0) * rc * rf
	var head: float = a0 + (PI / 2.0 if _lg_h(sd + 5) < 0.5 else -PI / 2.0) + (_lg_h(sd + 6) - 0.5) * 0.8
	if typ == 3:
		head = a0 + (_lg_h(sd + 6) - 0.5) * 0.6
	var sg: float = 1.0 if _lg_h(sd + 7) < 0.5 else -1.0
	var out: Array = []
	for j in n:
		out.append(Vector3(x, y, head))
		var k: float
		match typ:
			0:
				k = sg * (0.28 + 0.05 * j)
			1:
				k = 0.55 * sin(j * 1.1 + sd) * sg
			2:
				k = 0.05 * sg if j < n * 0.5 else 0.62 * sg
			_:
				k = 0.10 * sg
		head += k
		x += cos(head) * 4.0
		y += sin(head) * 4.0
	return out
var _lg_fill_tex := {}


static func _lg_ign(x: int, y: int) -> float:   # interleaved gradient noise：细密、不成格子（不是 Bayer）
	return fposmod(52.9829189 * fposmod(0.06711056 * x + 0.00583715 * y, 1.0), 1.0)


## 整盘渐变（压扁椭圆，半径 R 美术像素）只生成一次（按 R 缓存）；扇形用带 UV 的多边形取其中一块，1 贴图像素 = 1 美术像素
func _lg_fill(R: int) -> Texture2D:
	if _lg_fill_tex.has(R):
		return _lg_fill_tex[R]
	var ry: int = int(ceil(R * LG_SY))
	var img := Image.create_empty(2 * R + 1, 2 * ry + 1, false, Image.FORMAT_RGBA8)
	var n: int = LG_FILL.size()
	for y in range(-ry, ry + 1):
		for x in range(-R, R + 1):
			var q: float = Vector2(float(x) / R, float(y) / (R * LG_SY)).length()
			if q > 1.0:
				continue
			var ang: float = atan2(float(y) / LG_SY, float(x))
			var flow: float = 0.35 * sin(ang * 5.0 + q * 7.0)   # 一道静止的旋涡纹，抖动阈值跟着弯（读作缓慢流动的墨域）
			var v: float = pow(q, 2.4) * (n - 1) + (_lg_ign(x + 4000, y + 4000) - 0.5) * 1.15 + flow * 0.5
			var k: int = clampi(int(floor(v + 0.5)), 0, n - 1)
			var c: Color = LG_FILL[k][0]
			c.a = float(LG_FILL[k][1])
			img.set_pixel(x + R, y + ry, c)
	var tx := ImageTexture.create_from_image(img)
	_lg_fill_tex[R] = tx
	return tx


func _lg_fan(ci, o, fn: Dictionary) -> void:
	var b: Dictionary = fn.b
	var px: float = g.PX
	var r: float = float(load("res://scripts/characters/blocks/seg_logos.gd").hw_fan_r(o, b))
	var half: float = deg_to_rad(float(b.get("deg", 100.0))) * 0.5
	var fa: float = float(o.hw.fan_ang)
	var dur: float = float(b.get("dur", 12.0))
	var el: float = dur - float(fn.t)
	var open: float = clampf(floor(el * 15.0) / 15.0 / 0.33, 0.0, 1.0)   # 按拍张开
	var fade: float = clampf(float(fn.t) / 0.35, 0.0, 1.0)
	var rr: float = r * (0.55 + 0.45 * (1.0 - pow(1.0 - open, 2.0)))
	var c: Vector2 = _snap(o.pos)
	var tk: float = float(b.get("tick", 0.5))
	var pulse: bool = float(fn.get("tick", 0.0)) > tk - 1.0 / 15.0
	var beat: int = int(floor(g.t * 15.0))
	# 渐变填充
	var R: int = maxi(8, int(round(r / px)))
	var tex: Texture2D = _lg_fill(R)
	var tw: float = 2.0 * R + 1.0
	var th: float = 2.0 * ceil(R * LG_SY) + 1.0
	var k: float = float(R) * px / rr   # 张开期间按比例取（张满后 = 1，贴图像素正好落在美术像素格上）
	var N := 40
	var pts := PackedVector2Array([c])
	var uvs := PackedVector2Array([Vector2((R + 0.5) / tw, (ceil(R * LG_SY) + 0.5) / th)])
	for i in N + 1:
		var a: float = fa - half + 2.0 * half * i / N
		var p: Vector2 = Vector2(cos(a), sin(a) * LG_SY) * rr
		pts.append(c + p)
		var lp: Vector2 = p * k / px
		uvs.append(Vector2((lp.x + R + 0.5) / tw, (lp.y + ceil(R * LG_SY) + 0.5) / th))
	ci.draw_colored_polygon(pts, Color(1, 1, 1, fade * float(g.world.late_fill_k())), uvs, tex)   # 后期填充变薄、边照画（docs/293 late_fx_fill）
	# 外边：2 美术像素（外亮内墨），按噪声断续加厚；两侧边：1 像素断续
	var rc: float = rr / px
	var n: int = maxi(16, int(2.0 * half * rc))
	for i in n + 1:
		var a3: float = fa - half + 2.0 * half * i / n
		var hv: float = _lg_h(i * 31 + 7)
		var q: Vector2 = c + Vector2(cos(a3), sin(a3) * LG_SY) * rr
		var ec: Color = LG_C[6] if pulse else (LG_C[5] if hv > 0.66 else LG_C[4])
		ec.a = fade
		ci.draw_rect(Rect2(_snap(q), Vector2(px, px)), ec)
		if hv > 0.45:
			ci.draw_rect(Rect2(_snap(c + Vector2(cos(a3), sin(a3) * LG_SY) * (rr + px)), Vector2(px, px)), Color(LG_C[4].r, LG_C[4].g, LG_C[4].b, fade))
		var ic: Color = LG_INK[1] if hv > 0.3 else LG_C[1]
		ic.a = fade
		ci.draw_rect(Rect2(_snap(c + Vector2(cos(a3), sin(a3) * LG_SY) * (rr - px * 1.2)), Vector2(px, px)), ic)
		if pulse and (i % 3) == 0:
			_glow(q, LG_C[5])
	for sgn in [-1.0, 1.0]:
		var ea: float = fa + half * sgn
		var dv := Vector2(cos(ea), sin(ea) * LG_SY)
		var m: int = int(dv.length() * rr / px)
		var dn: Vector2 = dv.normalized()
		for i in m:
			if (i / 3) % 3 == 2:
				continue
			ci.draw_rect(Rect2(_snap(c + dn * float(i) * px), Vector2(px, px)), Color(LG_C[3].r, LG_C[3].g, LG_C[3].b, 0.8 * fade))
	# 咒文段（11-05 第七轮用户「长一点没关系，要有咒术和巫术的感觉，每个字可以用不同的曲线」）：同屏至多 LG_SEG_N 段，每段 6–10 个细字，
	# 各走各的曲线（螺旋收拢 / 波浪起伏 / 弯钩 / 往外甩）；字一个个被写出来（第一拍白），写出后自己扭一下；停 0.8–1.2 秒后从头到尾逐字褪去；
	# 写完时段尾拖出一道细丝和三点墨；每三个字一个带暗紫辉光（进光学发光层）。位置 / 曲线按「段号 + 第几轮」固定种子取，时间按 15 fps 拍子取
	if open > 0.5:
		var tb: float = floor(g.t * 15.0) / 15.0
		for ks in LG_SEG_N:
			var P: float = LG_SEG_P + 0.23 * float(ks % 3)
			var lt0: float = tb + P * float(ks) / LG_SEG_N
			var cyc: int = int(floor(lt0 / P))
			var lt: float = lt0 - float(cyc) * P
			var sd: int = ks * 977 + cyc * 131
			var path: Array = _lg_seg_path(sd, rc, fa, half)
			var nseg: int = path.size()
			var hold: float = 0.8 + 0.4 * _lg_h(sd + 8)
			for j in nseg:
				var tin: float = 0.06 * j
				var tout: float = 0.06 * nseg + hold + 0.05 * j
				if lt < tin or lt > tout + 0.12:
					continue
				var pj: Vector3 = path[j]
				var ang: float = atan2(pj.y, pj.x)
				if Vector2(pj.x, pj.y).length() > rc * 0.97 or absf(wrapf(ang - fa, -PI, PI)) > half * 0.95:
					continue
				var al2: float = clampf(1.0 - (lt - tout) / 0.12, 0.0, 1.0)
				var age: float = lt - tin
				var wig: float = round(sin(age * 22.0) * 1.2) if age < 0.27 else 0.0   # 写出来后自己扭一下
				var gq := Vector2(pj.x - sin(pj.z) * wig, (pj.y + cos(pj.z) * wig) * LG_SY)
				var glow: bool = (j + sd) % 3 == 0
				var gc: Color = LG_C[6] if age < 1.0 / 15.0 else (LG_AC if glow else LG_C[5])
				gc.a = fade * al2
				var gp: Vector2 = c + gq * px
				_lg_glyph(ci, gp, sd + j * 3, gc)
				if glow and age >= 1.0 / 15.0 and al2 > 0.5:
					_glow(gp, LG_GLOW)
					_glow(gp + Vector2(0, -2.0 * px), LG_GLOW)
			# 段尾细丝 + 三点墨
			var tdone: float = 0.06 * nseg
			var toutn: float = 0.06 * nseg + hold + 0.05 * nseg
			if lt >= tdone and lt <= toutn + 0.12 and nseg > 0:
				var al3: float = minf(1.0, (lt - tdone) / 0.1) * clampf(1.0 - (lt - toutn) / 0.12, 0.0, 1.0) * fade
				var pe: Vector3 = path[nseg - 1]
				var hv := Vector2(cos(pe.z), sin(pe.z))
				for k3 in range(1, 7):
					var q3: Vector2 = Vector2(pe.x, pe.y) + hv * float(3 + k3) + Vector2(0, sin(k3 * 0.9) * 0.8)
					ci.draw_rect(Rect2(_snap(c + Vector2(q3.x, q3.y * LG_SY) * px), Vector2(px, px)), Color(LG_C[2].r, LG_C[2].g, LG_C[2].b, al3 * (1.0 - k3 / 8.0)))
				var dd: Array = [9.0, 11.5, 13.5]
				for k4 in 3:
					var q4: Vector2 = Vector2(pe.x, pe.y) + hv * float(dd[k4]) + Vector2(0, (k4 - 1) * 0.8)
					ci.draw_rect(Rect2(_snap(c + Vector2(q4.x, q4.y * LG_SY) * px), Vector2(px, px)), Color(LG_INK[1].r, LG_INK[1].g, LG_INK[1].b, al3))
	var R2 = load("res://scripts/render/fx_recipe.gd").of(g)
	R2._light_follow(o, c + Vector2(cos(fa), sin(fa) * LG_SY) * rr * 0.6, rr * 0.9, (0.45 if pulse else 0.25) * fade, LG_C[3])


## 立起层的状态件：「言」彗星（运行时）、后期额外弹、提喻咒文行、连缀咒文链
func _lg_sort_items(o, out: Array) -> void:
	var h: Dictionary = o.hw
	if h.has("bolts"):
		for bo in h.bolts:
			out.append({"lrt": "bolt", "b": bo, "o": o, "gy": float((bo.to as Vector2).y) + 14.0})
	if not o.vg.is_empty():   # 后期额外弹：同时最多画最新 6 颗（更早的照常结算，只是不画）
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"lrt": "xbolt", "b": xb, "o": o, "gy": (xb.p as Vector2).y + 1.0})
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.get("t", 0.0)) > 0.0 and lk.e != null and not lk.e.dead:
		out.append({"lrt": "lock", "o": o, "gy": float(lk.e.pos.y) + 1.0})
	if h.has("links") and not h.links.is_empty():
		for lkk in h.links:
			out.append({"lrt": "links", "l": lkk, "o": o, "gy": float((lkk.m[0] as Dictionary).pos.y) + 1.0})


## 法术弹道（只画面）：第四轮的上抛弧被用户否了（11-05「不应该是迫击炮的感觉，而应该是法术投射的感觉」），
## 改成贴着平面飞、只带一点侧向弯曲：一道浅弧（side 决定往哪边弯）加一点 S 形摆动，两端都落在 a / b 上，s ∈ [0, 1]；判定与命中时间仍走玩法里的追踪弹位
static func _lg_arc(a: Vector2, b: Vector2, s: float, lift: float, side := 1.0) -> Vector2:
	var d: Vector2 = b - a
	var n := Vector2(-d.y, d.x).normalized() * side
	return a.lerp(b, s) + n * (lift * sin(PI * s) + 0.3 * lift * sin(TAU * s))


## 沿弧线从弹头往回取墨尾的点（每点相隔约 1 美术像素），弹头在前
func _lg_arc_path(a: Vector2, b: Vector2, u: float, n: int, lift: float, side := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ds: float = g.PX / maxf(8.0, a.distance_to(b) * 1.15)
	for k in n + 1:
		var s: float = u - float(k) * ds
		if s < 0.0:
			break
		out.append(_lg_arc(a, b, s, lift, side))
	return out


func _lg_line_path(head: Vector2, dv: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n + 1:
		out.append(head - dv * float(k) * g.PX)
	return out


## 墨迹彗星（原作 trail_01）：path = 弹头在前的弧线点列。白头尖细（6 格箭头，不做光球）；墨尾深蓝（墨边 + 一根蓝芯线 + 按拍闪的蓝点），
## 粗在前三成、往后收尖，沿弧线拖；尾旁零星淡金小星（原作 0.88 s）。精一：墨尾分成两股绞着走；精二：尾后一行细字（白 / 紫）
func _lg_comet(ci, path: PackedVector2Array, t: int, al := 1.0, big := false, sd := 0) -> void:
	var px: float = g.PX
	var L: int = path.size() - 1
	if L < 1:
		return
	var beat: int = int(floor(g.t * 15.0))
	var W: float = 2.6 if big else 2.0
	var head: Vector2 = path[0]
	var dv0: Vector2 = (path[0] - path[1]).normalized()
	var nL: float = float(LG_BOLT_LEN[mini(t, 2)] if not big else 36)
	for i in range(2, L + 1):
		var v: float = float(i) / nL
		var dv: Vector2 = (path[i - 1] - path[i]).normalized()
		var nv := Vector2(-dv.y, dv.x)
		var w: float = W * (1.0 - pow((v - 0.3) / 0.7, 1.5)) if v > 0.3 else W * smoothstep(0.05, 0.3, v)
		var split: float = (1.2 + 2.6 * v) * absf(sin(v * 5.0 + float(beat) * 0.4)) + 0.8 if (t >= 1 and v > 0.12) else 0.0   # 精一新元素：墨尾分成两股绞着走
		var ctr: Vector2 = path[i]
		var sides: Array = [-1.0, 1.0] if split > 0.6 else [0.0]
		for sgn in sides:
			var c0: Vector2 = ctr + nv * float(sgn) * split * px
			var ww: int = int(round(w * (0.6 if split > 0.6 else 1.0)))
			for q in range(-ww, ww + 1):
				var col: Color
				if q == 0:
					col = LG_C[5] if ((i + beat) % 6 == 0 and v < 0.8) else (LG_C[3] if v < 0.7 else LG_C[2])
				elif absi(q) == ww:
					col = LG_INK[0]
				else:
					col = LG_INK[1]
				col.a = al * (1.0 if v < 0.75 else maxf(0.0, 1.0 - (v - 0.75) * 2.4))
				ci.draw_rect(Rect2(_snap(c0 + nv * float(q) * px), Vector2(px, px)), col)
	var h0: Vector2 = _snap(head)
	var nv0 := Vector2(-dv0.y, dv0.x)
	var cells: Array = [[1, 0], [0, 0], [-1, 0], [-1, 1], [-1, -1], [-2, 0]]
	for qq in cells:
		var cell: Vector2 = h0 + (dv0 * float(qq[0]) + nv0 * float(qq[1])) * px
		var hc: Color = Color(1, 1, 1, al) if int(qq[1]) == 0 else Color(LG_C[5].r, LG_C[5].g, LG_C[5].b, al)
		ci.draw_rect(Rect2(_snap(cell), Vector2(px, px)), hc)
	_glow(h0, LG_C[6])
	_glow(h0 - dv0 * px, LG_C[5])
	# 淡金小星：尾旁两颗，按拍明灭（亮的那拍是十字，暗的那拍一点）
	for k in 2:
		var idx: int = int(L * (0.55 + 0.3 * k))
		if idx >= path.size() or idx < 2:
			continue
		var ph: float = _lg_h(sd * 13 + k * 7 + beat / 2)
		if ph < 0.35:
			continue
		var dvk: Vector2 = (path[idx - 1] - path[idx]).normalized()
		var gp: Vector2 = _snap(path[idx] + Vector2(-dvk.y, dvk.x) * (4.0 if k == 0 else -5.0) * px)
		var gc := Color(LG_GOLD.r, LG_GOLD.g, LG_GOLD.b, al)
		ci.draw_rect(Rect2(gp, Vector2(px, px)), gc)
		if ph > 0.7:
			for o4 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ci.draw_rect(Rect2(gp + o4 * px, Vector2(px, px)), Color(gc.r, gc.g, gc.b, al * 0.7))
	# 咒文残光（法术弹的拖尾感）：尾后几个细字一路变淡；精零 1 个暗字、精一 2 个、精二 3 个亮字（白 / 紫）
	var tail: Vector2 = path[L]
	var dvt: Vector2 = (path[maxi(0, L - 1)] - path[L]).normalized()
	for k in t + 1:
		var gp2: Vector2 = tail - dvt * float(5 + 6 * k) * px
		var gc2: Color = (LG_AC if (k + beat / 3) % 3 == 0 else LG_C[5]) if t >= 2 else LG_C[3 + t]
		gc2.a = al * (0.9 - 0.25 * k) * (1.0 if t >= 2 else 0.7)
		_lg_glyph(ci, gp2, k + beat / 3 + sd, gc2)


## 运行时件
func _lg_draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	match str(it.lrt):
		"bolt":   # 「言」：画面走弧线（a = 出手点，b = 目标，u = 飞行进度），玩法弹位照旧追踪；只记画面专用键 _pxs0 / _pxu
			var bo: Dictionary = it.b
			var o = it.o
			var a0: Vector2
			var u0: float
			if bo.has("visual"):
				a0 = bo.visual.start
				u0 = float(bo.visual.u)
			else:
				if not bo.has("_pxs0"):
					bo["_pxs0"] = bo.pos
				a0 = bo._pxs0
				var d0: float = maxf(1.0, a0.distance_to(bo.to))
				u0 = maxf(float(bo.get("_pxu", 0.0)), clampf(1.0 - (bo.pos as Vector2).distance_to(bo.to) / d0, 0.0, 1.0))
				bo["_pxu"] = u0
			var tt: int = tier(o)
			var lift: float = minf(26.0, a0.distance_to(bo.to) * 0.12)
			var sd0: int = int(bo.get("rune", 0)) & 1023
			_lg_comet(ci, _lg_arc_path(a0, bo.to, u0, LG_BOLT_LEN[tt], lift, 1.0 if sd0 % 2 == 0 else -1.0), tt, 1.0, false, sd0)
		"xbolt":
			var xb: Dictionary = it.b
			_lg_comet(ci, _lg_line_path((xb.p as Vector2) + Vector2(0, -16), (xb.v as Vector2).normalized(), 14), mini(1, tier(it.o)))
		"vbolt":   # 咒域每跳 / 连携出手：贴着平面带一点侧弯飞到 b，飞到即止
			var u: float = (g.t - float(it.t0)) / float(it.life)
			if u < 0.0 or u > 1.0:
				return
			var big: bool = it.get("big", false)
			var lift2: float = minf(24.0, (it.a as Vector2).distance_to(it.b) * 0.12)
			_lg_comet(ci, _lg_arc_path(it.a, it.b, u, 36 if big else 24, lift2, float(it.get("side", 1.0))), int(it.tier), 1.0, big, int(it.get("side", 1.0) > 0.0))
		"lock":   # 提喻：笔尖 → 目标一道弯的蓝丝线（往上拱、随拍轻轻摆）+ 沿弧一行细字向目标流动；精一上下两行；精二字白紫相间、丝线成一串墨珠
			# 11-05 第六轮用户「还有笔直的符文条」：原来是一条直线，改成二次弧（不再有笔直的字行）
			var o2 = it.o
			var lk: Dictionary = o2.hw.lock
			var t2: int = tier(o2)
			var a2: Vector2 = _lg_tip(o2)
			var b2: Vector2 = lk.e.pos + Vector2(0, -float(lk.e.r) * 0.5)
			var head: float = minf(1.0, (int(lk.n) * float(lk.b.get("tick", 0.25)) + float(lk.tick)) / maxf(0.05, float(lk.b.get("tick", 0.25))))
			var Lf: float = a2.distance_to(b2) / px
			if Lf < 2.0:
				return
			var beat2: int = int(floor(g.t * 15.0))
			var bow: float = clampf(Lf * 0.1, 4.0, 16.0) + 1.0 * sin(float(beat2) * 0.35)
			var ctrl: Vector2 = _lg_bow_ctrl(a2, b2, bow * px)
			var n: int = int(Lf * head)
			var prev: Vector2 = a2
			var cum: float = 0.0
			var nextg: float = 3.0
			var k: int = 0
			var rows: Array = [6.0] if t2 < 1 else ([6.0, -6.0] if t2 < 2 else [7.0, 0.0, -7.0])   # 精二质变：丝线本身也写成一行字（三行字成链）
			var ng2: int = int(Lf * head / 5.0)
			for i in n:
				var s: float = float(i) / Lf
				var p2: Vector2 = _lg_bez(a2, ctrl, b2, s)
				if t2 >= 2 and i % 3 == 1:
					ci.draw_rect(Rect2(_snap(p2), Vector2(px, px)), LG_INK[1])
				else:
					ci.draw_rect(Rect2(_snap(p2), Vector2(px, px)), LG_C[3] if (i + beat2) % 7 != 0 else LG_C[5])
				cum += p2.distance_to(prev) / px
				prev = p2
				if cum >= nextg:
					nextg += 5.0
					var tg: Vector2 = (_lg_bez(a2, ctrl, b2, minf(1.0, s + 0.02)) - p2).normalized()
					var nv2 := Vector2(-tg.y, tg.x)
					if nv2.y > 0.0:
						nv2 = -nv2   # 字行在线的上方
					for ri in rows.size():
						var gc2: Color = LG_C[5]
						if t2 >= 2 and (k + beat2 / 2) % 2 == 0:
							gc2 = LG_AC
						elif k == ng2 - 1:
							gc2 = LG_C[6]
						_lg_glyph(ci, p2 + nv2 * float(rows[ri]) * px, k * 3 + ri * 5 - beat2 / 2, gc2)
					k += 1
			_glow(prev, LG_C[5])
		"links":   # 精二连缀：成员之间一道下垂的弧链（像挂着的锁链，不再是直线）：一串墨珠 + 每 9 像素一个细字，一颗白珠按拍沿链走
			var lkk: Dictionary = it.l
			var mm: Array = lkk.m
			var a0: Dictionary = mm[0]
			if a0.dead:
				return
			var al: float = clampf(float(lkk.t) / 0.25, 0.0, 1.0)
			var pa: Vector2 = a0.pos + Vector2(0, -float(a0.r) * 0.6)
			var beat3: int = int(floor(g.t * 15.0))
			for j in range(1, mm.size()):
				var q: Dictionary = mm[j]
				if q.dead:
					continue
				var pb: Vector2 = q.pos + Vector2(0, -float(q.r) * 0.6)
				var Lq: int = int(pa.distance_to(pb) / px)
				if Lq < 2:
					continue
				var sag: Vector2 = (pa + pb) * 0.5 + Vector2(0, minf(float(Lq) * 0.2, 14.0) * px)   # 往下垂
				var ctl: Vector2 = sag * 2.0 - (pa + pb) * 0.5
				for i in Lq:
					if i % 2 == 1:
						continue
					var cc: Color = LG_C[6] if (i / 2) == (beat3 % maxi(1, Lq / 2)) else (LG_C[3] if i % 4 == 0 else LG_INK[1])
					cc.a = al
					ci.draw_rect(Rect2(_snap(_lg_bez(pa, ctl, pb, float(i) / Lq)), Vector2(px, px)), cc)
				for k2 in range(1, Lq / 9):
					var gc3: Color = LG_C[5] if k2 % 2 else LG_AC
					gc3.a = al
					_lg_glyph(ci, _lg_bez(pa, ctl, pb, float(k2 * 9) / Lq) + Vector2(0, -4.0 * px), k2 + j * 4 + beat3 / 4, gc3)
		"jump":   # 一笔墨（白笔头）从 a 写到 b：第 0 拍写到 70%、第 1 拍写满、之后从笔尾干回去
			var f: int = frame_of(float(it.t0))
			if f < 0:
				return
			var a3: Vector2 = it.a
			var b3: Vector2 = it.b
			var Lj: int = int(a3.distance_to(b3) / px)
			if Lj < 2:
				return
			var dj: Vector2 = (b3 - a3) / (float(Lj) * px)
			var nj := Vector2(-dj.y, dj.x)
			var i1: int = int(Lj * (0.7 if f == 0 else 1.0))
			var i0: int = 0 if f <= 1 else int(Lj * (0.4 * (f - 1)))
			for i in range(i0, i1):
				var v: float = float(i) / Lj
				var p3: Vector2 = a3 + dj * float(i) * px
				var hot: bool = i >= i1 - 3
				ci.draw_rect(Rect2(_snap(p3), Vector2(px, px)), LG_C[6] if hot else LG_C[3])
				if not hot and v > 0.15 and v < 0.85:
					ci.draw_rect(Rect2(_snap(p3 + nj * px), Vector2(px, px)), LG_INK[1])
			if i1 > 0:
				_glow(a3 + dj * float(i1 - 1) * px, LG_C[6])
		"seal":   # 连携「消弹」：区域边上浮起一圈细字（少数淡金），整圈按拍转、往上浮，0.8 秒散
			var u2: float = (g.t - float(it.t0)) / float(it.life)
			if u2 < 0.0 or u2 > 1.0:
				return
			var c2: Vector2 = it.c
			var rr2: float = float(it.r)
			var beat4: int = int(floor(g.t * 15.0))
			var n2: int = clampi(int(TAU * rr2 / px / 8.0), 16, 56)   # 第六轮：字距 11 → 8
			var rise: float = minf(1.0, u2 / 0.15) * 10.0 + u2 * 8.0
			for i in n2:
				var an: float = TAU * float(i) / n2 + float(beat4 - int(floor(float(it.t0) * 15.0))) * 0.03
				var hv2: float = _lg_h(i * 17 + 3)
				if u2 > 0.6 and hv2 < (u2 - 0.6) * 2.5:
					continue
				var gp3: Vector2 = c2 + Vector2(cos(an) * rr2, sin(an) * rr2 * LG_SY) + Vector2(0, -rise * px)
				var back: bool = sin(an) < -0.2
				var gc4: Color = LG_GOLD if i % 4 == 0 else (LG_C[4] if back else LG_C[6])   # 第六轮：提亮一档（前半圈白、后半圈亮蓝、淡金 1/4）
				if u2 < 0.08:
					gc4 = LG_C[6]
				ci.draw_rect(Rect2(_snap(gp3) + Vector2(0, 3.0 * px), Vector2(px, px)), LG_INK[0])   # 字脚一点墨影
				ci.draw_rect(Rect2(_snap(gp3) + Vector2(px, 3.0 * px), Vector2(px, px)), LG_C[3])   # 字脚一道亮蓝底线（读作一圈环）
				if u2 < 0.3 and i % 2 == 0:
					_glow(gp3, LG_C[5])
				_lg_glyph(ci, gp3, i * 3 + beat4 / 3, gc4)
		"pop":   # 被消的敌弹：一点白 → 一团墨收紧 → 一小块细字碎块落下熄灭
			var f2: int = frame_of(float(it.t0))
			if f2 < 0 or f2 > 6:
				return
			var c3: Vector2 = it.c
			if f2 == 0:
				for qq in [[0, 0], [1, 0], [0, 1], [1, 1]]:
					ci.draw_rect(Rect2(_snap(c3) + Vector2(qq[0], qq[1]) * px, Vector2(px, px)), LG_C[6])
			elif f2 <= 2:
				for y in range(-1, 3):
					for x in range(-1, 3):
						var md: int = absi(x * 2 - 1) + absi(y * 2 - 1)
						if md <= 4:
							ci.draw_rect(Rect2(_snap(c3) + Vector2(x, y) * px, Vector2(px, px)), LG_INK[0] if md < 4 else LG_C[2])
			else:
				_lg_glyph(ci, c3 + Vector2(0, float((f2 - 2) * (f2 - 2)) * px), int(it.gi), LG_C[4] if f2 < 5 else LG_C[2])
		"ring":   # 贴地大墨环原地闪一下（不外扩）：外亮内墨 2 像素，按噪声断续
			var u3: float = (g.t - float(it.t0)) / float(it.life)
			if u3 < 0.0 or u3 > 1.0:
				return
			var rr3: float = float(it.r) / px
			var a5: float = 1.0 if u3 < 0.12 else 1.0 - (u3 - 0.12) / 0.88
			var n3: int = int(TAU * rr3)
			for i in n3:
				var hv3: float = _lg_h(i * 7 + 11)
				if hv3 > a5 + 0.15 or hv3 < 0.12:
					continue
				var an2: float = TAU * float(i) / n3
				var q3: Vector2 = (it.c as Vector2) + Vector2(cos(an2) * rr3, sin(an2) * rr3 * LG_SY) * px
				ci.draw_rect(Rect2(_snap(q3), Vector2(px, px)), LG_C[6] if u3 < 0.1 else (LG_C[4] if hv3 > 0.5 else LG_C[3]))
				ci.draw_rect(Rect2(_snap(q3 - Vector2(cos(an2), sin(an2) * LG_SY) * px * 1.2), Vector2(px, px)), LG_INK[1])


## 旧做法（2）：状态件整张贴（彗星帧条、锁定印、咒域帧条），旋转 + 小数缩放，盖在所有单位上
func _lg_draw_raw(o) -> void:
	var cv = o.cv
	var fps: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	var t: int = tier(o)
	var h: Dictionary = o.hw
	var fn = h.get("fan", {})
	if fn is Dictionary and not fn.is_empty() and float(fn.get("t", 0.0)) > 0.0:
		var r: float = float(load("res://scripts/characters/blocks/seg_logos.gd").hw_fan_r(o, fn.b))
		_draw_raw(cv, "lg_raw_field", posmod(int(g.t * fps), maxi(1, int(_meta("lg_raw_field").get("n", 1)))), o.pos, float(h.fan_ang), r / 150.0)
	if h.has("bolts"):
		for bo in h.bolts:
			var pose: Array = load("res://scripts/render/fx_recipe.gd")._bolt_pose(bo)
			_draw_raw(cv, "lg_raw_bolt_e%d" % t, posmod(int(g.t * fps), maxi(1, int(_meta("lg_raw_bolt_e%d" % t).get("n", 1)))), pose[0], float(pose[1]), g.PX * 1.1)
	if not o.vg.is_empty():
		for xb in o.vg.bul:
			_draw_raw(cv, "lg_raw_bolt_e0", posmod(int(g.t * fps), maxi(1, int(_meta("lg_raw_bolt_e0").get("n", 1)))), (xb.p as Vector2) + Vector2(0, -16), (xb.v as Vector2).angle(), g.PX * 0.8)
	var lk = h.get("lock", {})
	if lk is Dictionary and not lk.is_empty() and float(lk.get("t", 0.0)) > 0.0 and lk.e != null and not lk.e.dead:
		var b: Vector2 = lk.e.pos + Vector2(0, -float(lk.e.r) * 0.5)
		cv.draw_line(_lg_tip(o), b, Color(0.55, 0.6, 1.0, 0.9), 3.0)
		_draw_raw(cv, "lg_raw_lock", posmod(int(g.t * fps), maxi(1, int(_meta("lg_raw_lock").get("n", 1)))), lk.e.pos + Vector2(0, -float(lk.e.r) - 20.0), 0.0, g.PX * 1.3)
	if h.has("links"):
		for lkk in h.links:
			var mm: Array = lkk.m
			for j in range(1, mm.size()):
				if not mm[0].dead and not mm[j].dead:
					cv.draw_line(mm[0].pos + Vector2(0, -10), mm[j].pos + Vector2(0, -10), Color(0.65, 0.53, 1.0, 0.8), 2.0)
	for it in items:
		if str(it.oid) == "logos" and str(it.ly) == "raw" and str(it.get("lrt", "")) == "rawline":
			var u: float = (g.t - float(it.t0)) / maxf(0.01, float(it.life))
			if u >= 0.0 and u <= 1.0:
				cv.draw_line(it.a, (it.a as Vector2).lerp(it.b, u), Color(0.55, 0.6, 1.0, 0.9), 4.0)
## 最后 n 件标成「跟着出手的干员走」（fop）
func _follow_last(o, n: int) -> void:
	for i in range(maxi(0, items.size() - n), items.size()):
		if str(items[i].oid) == str(o.id):
			items[i]["fop"] = true


func _op_by_id(oid: String):
	for m in g.squad.ops:
		if str(m.id) == oid:
			return m
	return null


# ================================================================ 艾雅法拉（docs/259，照斯卡蒂 docs/246 的做法；11-05 用户「火山和熔岩的感觉要做出来，火球也是，参考 pixelfx 的做法」）
## 帧条件（tools/pxplane_bake_eyja.py，键前缀 ey_）：爆团 / 火柱 / 火山爆团 / 喷柱都用 pixelfx 库的粒子做法（火团冷却、火星、余烬、熔岩块），
## 火球 / 熔岩块用库里 fire/fireball（按 5 个平面角生成、另一半翻转、循环），熔岩池 / 熔池只画边 + 淡渐变 + 循环的熔岩泡（立起层）。
## 弹体、熔池、熔蚀裂纹、灼烧火苗直接读玩法状态（g.bullets 里本人的 fire 弹、o.hw 的 lobs / lobvol / erupts / pools / melt_list / burns、o.vg.bul），只读；
## 画面位置按帧走、取整到美术像素格（弹体快，按 15 fps 跳格会一卡一卡，同流明光弹）；帧条形状按 15 fps 节拍换。
## 原画面（MagmaProjectile 的弹体 / 落点 / 材质颗粒、hw_draw_*、o.fx 粒子、连携的岩块 / 冲击）接管时一律不画 / 不生成，玩法照旧。

const EY_C := [Color("#1a0705"), Color("#4a110a"), Color("#8f1d0d"), Color("#d2330f"), Color("#f6561a"), Color("#ff8a3d"), Color("#fff0e0"), Color("#ffaa45")]
const EY_BOOM_R := [26, 34, 44, 56]
const EY_S1_R := [40, 52, 66]
const EY_IG_R := [44, 56]
const EY_S3_R := [38, 46]
const EY_POOL_R := [25, 30]
const EY_LAVA_R := [30, 36]
const EY_SPL_R := [15, 22]
const EY_BURN_MAX := 16
const EY_MELT_MAX := 32

var _sey = null

func _se():
	if _sey == null:
		_sey = load("res://scripts/characters/blocks/seg_eyjafjalla.gd")   # 运行时取（避免和积木链循环 preload）
	return _sey


func _ey_push(o, k: String, at: Vector2, ly: String, extra := {}) -> void:
	var it := {"k": "ey_" + k, "t0": g.t, "gp": _snap(at), "flip": false, "ly": ly, "oid": str(o.id)}
	it.merge(extra, true)
	_push(it)


func _ey_rawi(o, k: String, at: Vector2, rot: float, sc: float) -> void:
	_push({"k": "ey_" + k, "t0": g.t, "gp": at, "ly": "raw", "rot": rot, "sc": sc, "oid": str(o.id)})


## 同一名干员正在画的某类立起件数（同屏封顶：后期弹多时爆团不叠成一片）
func _ey_cnt(o, pre: String) -> int:
	var n := 0
	for it in items:
		if str(it.oid) == str(o.id) and str(it.ly) == "up" and str(it.k).begins_with(pre):
			n += 1
	return n


func _ev_ey(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG ey %s %s %.3f" % [kind, str(d.get("k", d.get("i", ""))), g.t])
	var px: float = g.PX
	match kind:
		"ey_boom":   # 熔岩弹爆炸：普攻（atk）/ 三重咏唱每落一发（tri）/ 二重咏唱强化弹（s1）/ 点燃弹（s2）
			var at: Vector2 = d.at
			var r: float = float(d.r)
			match str(d.get("k", "atk")):
				"s2":
					var tt: int = maxi(t, 1)
					if raw:
						_ey_rawi(o, "raw_ignite", at, 0.0, px * r * 0.5 / 47.0)
						return
					var b2: int = _bucket(r * 0.5, EY_IG_R)
					_ey_push(o, "ignite_r%d_e%d_up" % [b2, tt], at, "up")
					_ey_push(o, "ignite_r%d_e%d_gd" % [b2, tt], at, "gd")
					if mode() == 1:
						R._grains(o, at + Vector2(0, -50), at.y, "streak", 5 + 3 * tt, {"tier": tt})
					R._light(o, at + Vector2(0, -40), r * 1.8, 0.65, 0.15, p.light)
				"s1":
					if raw:
						_ey_rawi(o, "raw_s1boom", at, 0.0, px * r * 0.5 / 44.0)
						return
					var b1: int = _bucket(r * 0.5, EY_S1_R)
					_ey_push(o, "s1boom_r%d_e%d_up" % [b1, t], at, "up")
					_ey_push(o, "s1boom_r%d_e%d_gd" % [b1, t], at, "gd")
					if mode() == 1:
						R._grains(o, at + Vector2(0, -30), at.y, "ember", 4 + 2 * t, {"tier": t})
					R._light(o, at + Vector2(0, -24), 160.0, 0.7, 0.15, p.light)   # docs/270 补齐（爆发类下限）：每发爆点一盏 160 / 0.7
					_push({"ert": "core", "at": at + Vector2(0, -float(b1) * 0.45 * g.PX), "rr": 5.0 + 0.5 * t, "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": at.y + 1.0, "oid": str(o.id), "k": ""})   # 爆心进 emit
				_:
					R._light(o, at + Vector2(0, -20), r * 1.3, 0.4, 0.12, p.light)
					if _ey_cnt(o, "ey_boom") >= 6:
						return
					if raw:
						_ey_rawi(o, "raw_boom_e%d" % t, at, 0.0, px * r * 0.5 / 30.0)
						return
					var b0: int = _bucket(r * 0.5, EY_BOOM_R)
					_ey_push(o, "boom_r%d_e%d_up" % [b0, t], at, "up")
					_ey_push(o, "boom_r%d_e%d_gd" % [b0, t], at, "gd")
					if mode() == 1:
						R._grains(o, at + Vector2(0, -20), at.y, "ember", 2 + t, {"tier": t})
		"ey_splash", "ey_xhit":   # 抛射熔岩落地（火星迸溅 / 星火燎原 / 熔岩天降）、后期额外弹命中：小一号
			var at2: Vector2 = d.at
			var r2: float = float(d.get("r", 30.0))
			if kind == "ey_xhit" and _lm_beat_n(o, "eyx") >= 3:
				return
			if _ey_cnt(o, "ey_splash") >= 5:
				return
			if raw:
				_ey_rawi(o, "raw_splash", at2, 0.0, px * r2 * 0.5 / 18.0)
				return
			var bs: int = _bucket(r2 * 0.5, EY_SPL_R)
			_ey_push(o, "splash_r%d_up" % bs, at2, "up")
			if kind == "ey_splash":
				_ey_push(o, "splash_r%d_gd" % bs, at2, "gd")
				if mode() == 1:
					R._grains(o, at2 + Vector2(0, -10), at2.y, "rock", 2, {"tier": t})
			R._light(o, at2 + Vector2(0, -10), r2 * 1.6, 0.4, 0.1, p.light)
		"ey_s3":   # 火山落点：实心大爆团（火团 + 往上冲的火 + 熔岩块 + 花瓣状暗红碎片 + 火星线）
			var at3: Vector2 = d.at
			var r3: float = float(d.r)
			R._light(o, at3 + Vector2(0, -30), r3 * 2.0, 0.7, 0.15, p.light)
			if raw:
				_ey_rawi(o, "raw_s3boom", at3, 0.0, px * r3 * 0.5 / 38.0)
				return
			var b3: int = _bucket(r3 * 0.5, EY_S3_R)
			_ey_push(o, "s3boom_r%d_up" % b3, at3, "up")
			_ey_push(o, "s3boom_r%d_gd" % b3, at3, "gd")
			if mode() == 1:
				R._grains(o, at3 + Vector2(0, -40), at3.y, "streak", 6, {"tier": 2})
				R._grains(o, at3 + Vector2(0, -20), at3.y, "rock", 3, {"tier": 2})
		"ey_fire":   # 出手：杖头两拍火光
			if raw:
				return
			_push({"ert": "muz", "at": _snap(d.at), "big": d.get("big", false), "t0": g.t, "life": 2.0 / 15.0, "ly": "up", "gy": o.pos.y + 1.0, "oid": str(o.id), "k": "", "fopo": o, "foff": (d.at as Vector2) - o.pos})
			R._light(o, d.at, 60.0, 0.35, 0.08, p.light)
		"ey_chain":   # 「连锁」弹射：一道 1 美术像素的火线（3 拍）
			if _lm_beat_n(o, "eych") >= 3 or raw:
				return
			_push({"ert": "chain", "a": d.a, "b": d.b, "t0": g.t, "life": 3.0 / 15.0, "ly": "up", "gy": float(d.get("gy", 0.0)), "oid": str(o.id), "k": ""})
		"ey_link":   # 连携 v2「熔岩」：杖头抛出一块大熔岩块（库里火球 + 岩壳），T 秒高抛砸进区域；地上影子跟着
			var la: Vector2 = d.a
			var lc: Vector2 = d.c
			var T: float = float(d.T)
			_push({"ert": "lrock", "a": la, "c": lc, "T": T, "t0": g.t, "life": T, "ly": "up", "gy": lc.y + 2.0, "oid": str(o.id), "k": "", "raw": raw})
			_push({"ert": "lshadow", "a": Vector2(la.x, (d.get("foot", la) as Vector2).y), "c": lc, "T": T, "t0": g.t, "life": T, "ly": "gd", "oid": str(o.id), "k": ""})
			R._light(o, la, 120.0, 0.5, 0.12, p.light)
		"ey_link_hit", "ey_combo":   # 连携熔岩块砸地 / 旧连携技「放大熔岩弹」落点：火山爆团 + 一摊熔岩（只画边 + 熔岩泡）
			var c: Vector2 = d.get("c", d.get("at", o.pos))
			var lr: float = float(d.get("r", 105.0))
			var dur: float = 2.0 if kind == "ey_combo" else 0.9
			R._light(o, c + Vector2(0, -30), maxf(240.0, lr * 2.0), 0.7, 0.15, p.light)
			if raw:
				_ey_rawi(o, "raw_s3boom", c, 0.0, px * lr * 0.5 / 38.0)
				return
			_ey_push(o, "s3boom_r46_up", c, "up")
			_ey_push(o, "s3boom_r46_gd", c, "gd")
			_ey_push(o, "lava_r36_gd", c, "gd", {"loop": true, "life": dur})
			_ey_push(o, "lavaup_l36_up", c, "up", {"loop": true, "life": dur})
			if mode() == 1:
				R._grains(o, c + Vector2(0, -40), c.y, "streak", 10, {"tier": 2})
				R._grains(o, c + Vector2(0, -20), c.y, "rock", 6, {"tier": 2})
		"ey_link_burn":   # 连携两跳点燃：被烧的那几只身上冒火星
			if mode() != 1:
				return
			var n := 0
			for e in d.get("es", []):
				if e.dead or n >= 6:
					continue
				n += 1
				R._grains(o, e.pos + Vector2(0, -float(e.r) * 0.6), float(e.pos.y), "ember", 2, {"tier": 1})
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 0:   # 二重咏唱起手：火缕绕身旋上杖头
				if raw:
					_ey_rawi(o, "raw_s1cast", o.pos, 0.0, px * 1.13)
					return
				_ey_push(o, "s1cast_e%d_up" % t, o.pos, "up", {"fopo": o, "foff": Vector2.ZERO})
				if t >= 2:
					_ey_push(o, "s1cast_e2_gd", o.pos, "gd", {"fopo": o, "foff": Vector2.ZERO})
				# docs/270 补齐：起手本身也按爆发档——杖头一盏 160 / 0.7、杖头热芯进发光层、迸几颗火星（强化弹要等下一次普攻约 1.2 秒后才落地）
				R._light(o, o.pos + Vector2(0, -100), 160.0, 0.7, 0.15, p.light)
				_push({"ert": "core", "at": o.pos + Vector2(0, -110), "rr": 6.0 + 0.5 * t, "t0": g.t, "life": 4.0 / 15.0, "ly": "up", "gy": o.pos.y + 1.0, "oid": str(o.id), "k": "", "fop": o, "foff": Vector2(0, -110)})
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -110), o.pos.y, "ember", 6 + t, {"tier": t})
			elif i == 2:   # 火山起手：身后熔岩喷柱 + 脚下裂缝圈
				var fl: bool = float(o.face) < 0.0
				if raw:
					_ey_rawi(o, "raw_s3cast", o.pos, 0.0, px * 1.13)
					return
				_ey_push(o, "s3cast_up", o.pos, "up", {"flip": fl, "sk": -6.0, "fopo": o, "foff": Vector2.ZERO})
				_ey_push(o, "s3cast_gd", o.pos, "gd", {"flip": fl, "fopo": o, "foff": Vector2.ZERO})
				R._light(o, o.pos + Vector2(0, -60), 170.0, 0.7, 0.15, p.light)
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -40), o.pos.y, "rock", 5, {"tier": 2})


## 地面层：一次性贴地件、循环熔岩（连携 / 旧连携技）、熔岩池 / 熔池（读 o.hw.pools）、熔蚀裂纹、抛射物影子、火山期间脚下热圈
func _ey_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var px: float = g.PX
	if not o.hw.is_empty() and o.hw.has("pulse") and not (o.hw.pulse as Dictionary).is_empty():
		_draw_strip(cv, "ey_aura_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for l in o.hw.get("pools", []):
		var key: String = _ey_pool_key(l, "gd")
		if key == "":
			continue
		_draw_strip(cv, key, frame_of(0.0) + int(l.get("pat", 0)) % 7, _snap(l.pos), false, false, Color(1, 1, 1, _ey_pool_a(l)))
	for it in items:
		if str(it.ly) != "gd" or str(it.oid) != id:
			continue
		if it.has("ert"):
			_ey_draw_rt(cv, it)
		elif it.get("loop", false):
			_draw_strip(cv, str(it.k), frame_of(0.0), it.gp, false, false, Color(1, 1, 1, _ey_loop_a(it)))
		else:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), it.gp, it.flip, true)
	# 熔蚀（精一普攻）：被熔岩弹命中的敌人脚下三小段暗红裂纹（状态提示）
	var nm := 0
	for m in o.hw.get("melt_list", []):
		var e: Dictionary = m.e
		var left: float = float(m.until) - g.t
		if e.dead or left <= 0.0 or nm >= EY_MELT_MAX:
			continue
		nm += 1
		var base: Vector2 = _snap(e.pos + Vector2(0, 2))
		var rr: float = clampf(float(e.r) * 0.5, 5.0, 12.0)
		for q in 3:
			var a0: float = q * TAU / 3.0 + float(e.id) * 0.7
			for s in 5:
				if left < 0.3 and s >= 2:
					continue
				var an: float = a0 + s * 0.13
				_px(cv, base + Vector2(cos(an) * rr, sin(an) * rr * 0.72) * px, EY_C[3] if (s + q) % 2 == 0 else EY_C[2])
	# 抛射物（熔岩块 / 三重咏唱低抛弹）的地面影子：暗色小椭圆，越高越小
	for l in o.hw.get("lobs", []):
		var k: float = clampf(float(l.t) / maxf(0.01, float(l.dur)), 0.0, 1.0)
		_ey_shadow(cv, (l.from as Vector2).lerp(l.to, k) + Vector2(0, (1.0 - k) * 6.0), 2.0 + 2.0 * float(l.sz), k)
	for v in o.hw.get("lobvol", []):
		for s in v.shots:
			if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
				continue
			var k2: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
			_ey_shadow(cv, (s.from as Vector2).lerp(s.to, k2) + Vector2(0, (1.0 - k2) * 40.0), 3.0, k2)


func _ey_shadow(cv, gp: Vector2, r: float, k: float) -> void:
	var px: float = g.PX
	var c := Color(0.05, 0.02, 0.02, 0.45)
	var rr: int = int(round(r * (0.6 + 0.4 * k)))
	var base: Vector2 = _snap(gp)
	for y in range(-1, 2):
		for x in range(-rr, rr + 1):
			if absi(y) == 1 and absi(x) >= rr:
				continue
			cv.draw_rect(Rect2(base + Vector2(x, y) * px, Vector2(px, px)), c)


## 熔岩池 / 熔池帧条键：S3 熔岩（look lava）或三重咏唱熔池（look pool / weighted）
func _ey_pool_key(l: Dictionary, ly: String) -> String:
	var b: Dictionary = l.b
	var look: String = str(b.get("look", ""))
	if look == "lava":
		return ("ey_lava_r%d_gd" if ly == "gd" else "ey_lavaup_l%d_up") % _bucket(float(l.r) * 0.5, EY_LAVA_R)
	if look == "pool" or b.get("weighted", false):
		return ("ey_pool_r%d_gd" if ly == "gd" else "ey_lavaup_p%d_up") % _bucket(float(l.r) * 0.5, EY_POOL_R)
	return ""


func _ey_pool_a(l: Dictionary) -> float:
	return clampf((float(l.dur) - float(l.t)) / 0.15, 0.0, 1.0) * clampf(float(l.t) / 0.3, 0.0, 1.0)


func _ey_loop_a(it: Dictionary) -> float:
	return clampf((g.t - float(it.t0)) / 0.12, 0.0, 1.0) * clampf((float(it.t0) + float(it.life) - g.t) / 0.3, 0.0, 1.0)


## 立起层的状态件：弹体（火球 / 熔岩块）、熔岩泡（循环）、灼烧火苗
func _ey_sort_items(o, out: Array) -> void:
	var S = _se()
	var oid: String = str(o.id)
	for bl in g.bullets:   # 本人的法术弹（普攻 / 二重咏唱强化 / 点燃弹）
		if bl.life <= 0.0 or str(bl.get("op", "")) != oid or str(bl.kind) != "fire" or not bl.has("hw_b"):
			continue
		var lk: Dictionary = bl.hw_b.get("look", {})
		var st: String = "ign" if lk.has("big_tex") else ("pow" if bl.get("pxs", false) else ("fire" if bl.get("hw_fireball", false) else "lava"))
		var lv: Array = _ey_lift(bl)
		out.append({"ert": "ball", "st": st, "pos": lv[0], "dir": lv[1], "gy": (bl.pos as Vector2).y + 40.0, "ph": int(absf(bl.pos.x)) % 7})
	if not o.hw.is_empty():
		var rot_all: bool = Bal.v("fx/eyja_ball_rot_all", 1.0) > 0.0
		for l in o.hw.get("lobs", []):   # 火星迸溅 / 星火燎原 / 熔岩天降的熔岩块
			if float(l.t) >= float(l.dur):
				continue
			var lp: Vector2 = S._hw_lob_pos(l)
			var lp0: Vector2 = S._hw_lob_pos_at(l, maxf(0.0, float(l.t) - 0.03))
			var ld: Vector2 = lp - lp0
			if ld.length_squared() <= 0.01 and rot_all:   # 刚抛出那一帧往回取不到：改往前取（原来退成朝下，火块竖着闪一帧）
				ld = S._hw_lob_pos_at(l, float(l.t) + 0.03) - lp
			var k: float = clampf(float(l.t) / maxf(0.01, float(l.dur)), 0.0, 1.0)
			var big: bool = float(l.sz) >= 1.1 or str(l.src) == "熔岩天降"
			out.append({"ert": "ball", "st": "rock" if big else "chip", "pos": lp, "dir": ld if ld.length_squared() > 0.01 else Vector2.DOWN, "gy": (l.from as Vector2).lerp(l.to, k).y + 2.0, "ph": int(absf(l.to.x)) % 7})
		for v in o.hw.get("lobvol", []):   # 三重咏唱低抛弹
			var apex: float = float(v.vol.b.lob.get("apex", 20.0))
			for s in v.shots:
				if float(s.t) < 0.0 or float(s.t) >= float(s.dur):
					continue
				var k2: float = clampf(float(s.t) / float(s.dur), 0.0, 1.0)
				var sp: Vector2 = _ey_arc(s.from, s.to, k2, apex) + Vector2(0, -8)
				var sp0: Vector2 = _ey_arc(s.from, s.to, maxf(0.0, k2 - 0.05), apex) + Vector2(0, -8)
				var sd: Vector2 = sp - sp0
				if sd.length_squared() <= 0.01 and rot_all:   # 出手那一帧：往前取切线（原来退成朝右）
					sd = _ey_arc(s.from, s.to, minf(1.0, k2 + 0.05), apex) + Vector2(0, -8) - sp
				out.append({"ert": "ball", "st": "lava", "pos": sp, "dir": sd if sd.length_squared() > 0.01 else Vector2.RIGHT, "gy": (s.from as Vector2).lerp(s.to, k2).y + 30.0, "ph": int(absf(s.to.x)) % 7,
					"len": Bal.v("fx/eyja_lob_len", 0.45)})
		for ev in o.hw.get("erupts", []):   # 火山弹
			if not ev.has("shot") or float(ev.t) <= 0.0:
				continue
			var shot: Dictionary = ev.shot
			var k3: float = clampf(1.0 - float(ev.t) / float(shot.dur), 0.0, 1.0)
			var ap: float = float(shot.get("apex", 24.0))
			var ep: Vector2 = _ey_arc(shot.from, ev.pos, k3, ap)
			var ep0: Vector2 = _ey_arc(shot.from, ev.pos, maxf(0.0, k3 - 0.05), ap)
			var ed: Vector2 = ep - ep0
			if ed.length_squared() <= 0.01 and rot_all:   # 刚射出那一帧：往前取切线（原来退成朝下）
				ed = _ey_arc(shot.from, ev.pos, minf(1.0, k3 + 0.05), ap) - ep
			out.append({"ert": "ball", "st": "rock", "pos": ep, "dir": ed if ed.length_squared() > 0.01 else Vector2.DOWN, "gy": (shot.from as Vector2).lerp(ev.pos, k3).y + 54.0 * (1.0 - k3), "ph": int(absf(ev.pos.x)) % 7})
		for l in o.hw.get("pools", []):   # 熔岩泡（循环，立起）
			var key: String = _ey_pool_key(l, "up")
			if key != "":
				out.append({"loopk": key, "gp": _snap(l.pos), "gy": (l.pos as Vector2).y + 1.0, "mod": Color(1, 1, 1, _ey_pool_a(l))})
		var nb := 0
		for bu in o.hw.get("burns", []):   # 灼烧：敌人身上两小簇火苗（状态提示）
			if nb >= EY_BURN_MAX:
				break
			if float(bu.t) <= 0.0 or bu.e.dead:
				continue
			nb += 1
			out.append({"ert": "burn", "e": bu.e, "gy": float(bu.e.pos.y) + 1.0})
	if not o.vg.is_empty():   # 后期额外弹：小熔岩块，同时最多画最新 6 颗
		var xs: Array = o.vg.bul
		for i in range(maxi(0, xs.size() - 6), xs.size()):
			var xb: Dictionary = xs[i]
			out.append({"ert": "ball", "st": "chip", "pos": (xb.p as Vector2) + Vector2(0, -18.0), "dir": xb.v, "gy": (xb.p as Vector2).y + 1.0, "ph": i % 7})


## 直线弹的画面抬升（11-06 用户「感觉是不是还是斜着飞过去的」）：弹从法杖尖（脚下往上 40）出手、瞄的是敌人脚下，
## 判定点一路往下斜着走；眼睛看的是敌人身子（脚下往上一截），于是火球总像斜着往地上扎。画面上把弹按飞行进度逐渐抬到敌人身子的高度
## （fx/eyja_ball_lift 像素，0 = 不抬），朝向 / 尾焰顺着抬升后的画面路径；判定、爆点位置不动。
func _ey_lift(bl: Dictionary) -> Array:
	var p: Vector2 = bl.pos
	var v: Vector2 = bl.vel
	var lift: float = Bal.v("fx/eyja_ball_lift", 20.0)
	if lift <= 0.0 or not bl.has("vt") or not bl.has("vf"):
		return [p, v]
	var f: Vector2 = bl.vf
	var t: Vector2 = bl.vt
	var seg: Vector2 = t - f
	var L2: float = seg.length_squared()
	if L2 < 1.0:
		return [p, v]
	var kr: float = (p - f).dot(seg) / L2
	var k: float = clampf(kr, 0.0, 1.0)
	if Bal.v("fx/eyja_ball_rot_all", 1.0) > 0.0:
		# 朝向 = 画面上这一帧实际的移动方向（11-07 用户「不能任意方向吗」）：画面位置 p - (0, lift·k)，k 在 0–1 之间随 p 线性变，
		# 对时间求导 = v - (0, lift)·(v·seg)/|seg|²；飞过瞄准点后 k 停在 1，画面速度就是 v
		var sv: Vector2 = v - Vector2(0, lift) * (v.dot(seg) / L2) if kr > 0.0 and kr < 1.0 else v
		return [p + Vector2(0, -lift * k), sv]
	var vd: Vector2 = (t - Vector2(0, lift)) - f   # 画面路径：出手点 → 敌人身子
	return [p + Vector2(0, -lift * k), vd.normalized() * v.length() if vd.length_squared() > 0.01 else v]


## MagmaProjectile.position_at 的同一条弧（纯函数抄一份，只读）
static func _ey_arc(from: Vector2, to: Vector2, k: float, height: float) -> Vector2:
	return from.lerp(to, k) + Vector2(0, -4.0 * height * k * (1.0 - k) * (1.18 - 0.36 * k))


## 运行时件：ball 弹体（帧条按方向挑）/ muz 出手火光 / chain 连锁火线 / lrock 连携熔岩块 / lshadow 它的影子 / burn 灼烧火苗
func _ey_draw_rt(ci, it: Dictionary) -> void:
	var px: float = g.PX
	match str(it.ert):
		"ball":
			_ey_ball(ci, str(it.st), it.pos, it.dir, int(it.get("ph", 0)), float(it.get("len", 1.0)))
		"core":   # 爆心发光点团（docs/270 补齐）：不画色块，只往发光层送一团热芯点，4 拍里由大到小
			var fc: int = frame_of(float(it.t0))
			if fc < 0 or fc > 3:
				return
			var rr: int = int(round(float(it.rr) * [1.0, 0.8, 0.55, 0.3][fc]))
			var cc: Vector2 = _snap(it.at)
			for yy in range(-rr, rr + 1):
				for xx in range(-rr, rr + 1):
					if xx * xx + yy * yy <= rr * rr:
						_glow(cc + Vector2(xx, yy) * px, EY_C[7] if xx * xx + yy * yy > rr * rr / 3 else EY_C[6])
		"muz":
			var f: int = frame_of(float(it.t0))
			if f < 0 or f > 1:
				return
			var c0: Vector2 = it.at
			var m: int = 3 if it.get("big", false) else 2
			_px(ci, c0, EY_C[6] if f == 0 else EY_C[7])
			for dv in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				for s in range(1, m + (1 if f == 0 else 0)):
					_px(ci, c0 + dv * float(s) * px, EY_C[7] if s == 1 else EY_C[5])
			if f == 0:
				_glow(c0, EY_C[7])
		"chain":
			var f2: int = frame_of(float(it.t0))
			if f2 < 0 or f2 > 2:
				return
			var a: Vector2 = it.a
			var b: Vector2 = it.b
			var n: int = maxi(1, int(a.distance_to(b) / px))
			for i in n + 1:
				var u: float = float(i) / float(n)
				if f2 == 2 and u < 0.5:
					continue
				_px(ci, a.lerp(b, u), EY_C[7] if f2 == 0 else EY_C[5])
				if f2 == 0 and i % 3 == 0:
					_glow(a.lerp(b, u), EY_C[7])
		"lrock":
			var u2: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.T)), 0.0, 1.0)
			var pos: Vector2 = _ey_lrock_pos(it, u2)
			var pos0: Vector2 = _ey_lrock_pos(it, maxf(0.0, u2 - 0.05))
			if it.get("raw", false):
				_draw_raw(ci, "ey_ball_boulder_d0", posmod(int(g.t * Bal.v("fx/px_plane_raw_fps", 12.8)), 18), pos, (pos - pos0).angle(), g.PX * 1.3)
			else:
				_ey_ball(ci, "boulder", pos, pos - pos0 if pos.distance_squared_to(pos0) > 0.01 else Vector2.DOWN, 0)
		"lshadow":
			var u3: float = clampf((g.t - float(it.t0)) / maxf(0.01, float(it.T)), 0.0, 1.0)
			_ey_shadow(ci, (it.a as Vector2).lerp(it.c, u3) + Vector2(0, 10), 6.0 + 8.0 * u3, u3)
		"burn":
			var e: Dictionary = it.e
			if e.dead:
				return
			var beat: int = int(floor(g.t * 15.0))
			var base: Vector2 = _snap(e.pos + Vector2(0, -float(e.r) * 0.55))
			var off: int = maxi(2, int(float(e.r) * 0.15))
			for j in 2:
				var x: int = -off if j == 0 else off
				var h: int = 2 + int(_hn(int(e.id) * 3 + j + beat) * 3.0)
				for s in h:
					_px(ci, base + Vector2(x, -s) * px, EY_C[5] if s == 0 else (EY_C[4] if s < h - 1 else EY_C[3]))
				if j == 0:
					_glow(base + Vector2(x, 0) * px, EY_C[5])


static func _hn(i: int) -> float:
	var x: int = (i * 1103515245 + 12345) & 0x7fffffff
	return float(x % 1000) / 1000.0


func _ey_lrock_pos(it: Dictionary, u: float) -> Vector2:
	var gp: Vector2 = (it.a as Vector2).lerp(it.c, u)
	return gp + Vector2(0, -140.0 * sin(PI * u))


## 一颗弹体：帧条 ey_ball_<样式>_d<方向>（按飞行方向挑最近的平面角 + 水平翻转），循环；原点 = 弹头，位置每帧走、取整到美术像素格
## ln < 1：沿飞行方向把弹身压短（弹头不动）、不加尾焰——精二三重咏唱 3 发低抛弹间隔 0.12 秒、走几乎同一条弧，
## 帧条弹身约 45 美术像素长，三发首尾相接连成一条「火绳」（11-06 用户「精二像条火绳」）；开关 fx/eyja_lob_len（1 = 原样）
## 朝向统一（11-07 用户「艾雅法拉这个火焰还是歪着过去的，不能任意方向吗」）：所有弹体样式（含火星迸溅 / 火山弹的 chip / rock / boulder，
## 原来不转、直接贴 5 个角里最近的一张，抛物线刚升起时就落到 45° 那张）一律「最近角 + 转掉剩余偏差」，朝向 = 调用方给的画面移动方向
## （直线弹 _ey_lift 的画面速度、抛射弹轨迹切线）。开关 fx/eyja_ball_rot_all（缺省 1；0 = 只有带尾焰的四种转）。帧条像素按最近邻转，不另烤方向
func _ey_ball(ci, st: String, pos: Vector2, dir: Vector2, ph: int, ln := 1.0) -> void:
	var has_dir: bool = dir.length_squared() > 0.0001
	var dk: Array = pick_dir(dir.angle() if has_dir else 0.0)
	var tail: bool = EY_TAIL.has(st) and has_dir and Bal.v("fx/eyja_ball_tail", 1.0) > 0.0
	if has_dir and (tail or Bal.v("fx/eyja_ball_rot_all", 1.0) > 0.0):
		if tail and ln >= 1.0:
			_ey_tail(ci, pos, dir.normalized(), float(EY_TAIL[st]), ph)
		_ey_strip_rot(ci, "ey_ball_%s_d%d" % [st, dk[0]], frame_of(0.0) + ph, _snap(pos), dk[1], dir.angle(), float(dk[0]), ln)
	else:
		_draw_strip(ci, "ey_ball_%s_d%d" % [st, dk[0]], frame_of(0.0) + ph, _snap(pos), dk[1], false)
	if has_dir and _ball_dbg():
		_ey_ball_dbg(ci, pos, dir)


## 帧条只有 5 个 45° 角：挑最近的一张后再转掉剩下的偏差（≤ 22.5°），火球朝向和真实飞行方向一致——
## 原来 25° 飞的火球画成 45°，看着像斜着「平移」（11-06）。热芯发光点按同一变换放
const EY_BALL_VIS := {-90: -85.6, -45: -40.7, 0: 4.4, 45: 49.3, 90: 94.4}   # 标称角 → 帧条里火体（亮像素，不含烟）实测主轴（度；烤图整体顺时针偏约 4.5°，lava / pow / ign 同）

## 局部坐标里沿角 a 方向缩放 ln、垂直方向不变：R(a) · diag(ln, 1) · R(-a)
static func _ey_squash(a: float, ln: float) -> Transform2D:
	var c := cos(a)
	var si := sin(a)
	var off := c * si * (ln - 1.0)
	return Transform2D(Vector2(c * c * ln + si * si, off), Vector2(off, si * si * ln + c * c), Vector2.ZERO)

func _ey_strip_rot(ci, k: String, fi: int, gp: Vector2, flip: bool, ang: float, bucket: float, ln := 1.0) -> void:
	var m: Dictionary = _meta(k)
	var tx: Texture2D = _tex(k)
	if m.is_empty() or tx == null:
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
		xf = xf * _ey_squash(deg_to_rad(vis), ln)
	var tl := Vector2(-float(m.ox) * px, -float(m.oy) * px)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture_rect_region(tx, Rect2(tl, Vector2(w * px, h * px)), Rect2(fi * w, 0.0, w, h))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
func _ball_dbg() -> bool:
	if _bdbg < 0:
		_bdbg = 1 if (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--balldbg") else 0
	return _bdbg == 1

func _ey_ball_dbg(ci, pos: Vector2, dir: Vector2) -> void:
	var d: Vector2 = dir.normalized()
	ci.draw_line(pos - d * 80.0, pos + d * 40.0, Color(0.2, 0.95, 1.0, 0.95), 1.0)
	var fr: int = Engine.get_process_frames()
	_bdbg_pts.append([fr, pos])
	while not _bdbg_pts.is_empty() and fr - int(_bdbg_pts[0][0]) > 10:
		_bdbg_pts.pop_front()
	for q in _bdbg_pts:
		ci.draw_rect(Rect2((q[1] as Vector2) - Vector2(1, 1), Vector2(2, 2)), Color.WHITE)


## 直线弹（普攻火球 / 熔岩弹 / 二重咏唱强化 / 点燃弹）的尾焰（11-06 用户「现在的普通攻击像是平移出去的火球，没有了之前的方向感」）：
## 帧条只有 5 个 45° 角、烟一律往上飘，看不出头尾；转平面前靠 proj_lavaball 按飞行角连续旋转的彗星形。
## 这里沿真实飞行反方向排一串由白热到暗红、由粗到细的像素团（帧条底下），头部一颗热芯进发光层；只画，不抽随机数（抖动按 g.t 与 ph）。
## 开关 fx/eyja_ball_tail（缺省 1，0 = 只有帧条）
const EY_TAIL := {"fire": 1.0, "lava": 1.1, "pow": 1.3, "ign": 1.45}
const EY_TAIL_C := [6, 7, 5, 5, 4, 4, 3, 3, 2, 2, 1]   # 从头到尾的 EY_C 色阶

func _ey_tail(ci, pos: Vector2, d: Vector2, k: float, ph: int) -> void:
	var px: float = g.PX
	var nrm: Vector2 = d.orthogonal()
	var n: int = int(round(9.0 * k))
	var flick: int = int(floor(g.t * 15.0)) + ph
	for i in n:
		var u: float = float(i) / float(maxi(1, n - 1))   # 0 头 → 1 尾
		var back: float = (3.0 + float(i) * 2.6) * px * 0.5 * (1.0 + 0.5 * (k - 1.0))
		var wob: float = sin(float(flick + i * 3) * 1.7) * u * 2.2 * px * 0.5
		var c: Vector2 = _snap(pos - d * back + nrm * wob)
		var r: int = 2 if u < 0.25 else (1 if u < 0.7 else 0)   # 半宽（美术像素）
		if k >= 1.3 and u < 0.45:
			r += 1
		var ci_k: int = EY_TAIL_C[mini(EY_TAIL_C.size() - 1, int(u * float(EY_TAIL_C.size() - 1) + 0.5))]
		var col: Color = EY_C[ci_k]
		col.a = 1.0 - 0.55 * u
		for yy in range(-r, r + 1):
			for xx in range(-r, r + 1):
				if xx * xx + yy * yy > r * r + (1 if r > 0 else 0):
					continue
				if r >= 2 and (xx + yy + flick + i) % 5 == 0:
					continue   # 边上缺几格，不成实心胶囊
				ci.draw_rect(Rect2(c + Vector2(xx, yy) * px, Vector2(px, px)), col)
		# 尾段偶尔甩出一颗火星（离轴）
		if u > 0.45 and (flick + i) % 4 == 0:
			var sp: Vector2 = _snap(c + nrm * (3.0 if (flick + i) % 8 == 0 else -3.0) * px)
			ci.draw_rect(Rect2(sp, Vector2(px, px)), Color(EY_C[5], 0.8 - 0.5 * u))
	_glow(_snap(pos - d * 2.0 * px), EY_C[6])


## 旧做法（2）：同一形状光晕烤进颜色、小数缩放、旋转，盖在所有单位上；弹体用 0° 帧条按飞行方向旋转 1.3 倍贴
func _ey_draw_raw(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	var lf: int = int(g.t * rf)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
	for l in o.hw.get("pools", []):
		if _ey_pool_key(l, "gd") != "":
			_draw_raw(cv, "ey_raw_lava", posmod(lf, 18), l.pos, 0.0, g.PX * float(l.r) * 0.5 / 30.0)
	var tmp: Array = []
	_ey_sort_items(o, tmp)
	for it in tmp:
		if str(it.get("ert", "")) == "ball":
			_draw_raw(cv, "ey_ball_%s_d0" % str(it.st), posmod(lf, 18), it.pos, (it.dir as Vector2).angle(), g.PX * 1.3)
		elif str(it.get("ert", "")) == "burn":
			_ey_draw_rt(cv, it)
	for it in items:
		if str(it.oid) == id and str(it.get("ert", "")) == "lrock" and it.get("raw", false):
			_ey_draw_rt(cv, it)


# ================================================================ 推进之王（docs/264，照 docs/246 斯卡蒂 / docs/254 星熊的做法）
## 帧条 pxp_sg_*（tools/pixelfx_fx/melee/ak-siege-pp.js，tools/pxplane_bake.py --op siege）。主色本人金（熔金 8 阶），尘 / 碎石暖土，精二点缀白金熔芯。
## 普攻「锤击」= 下砸锤弧（挂在人身上，跟人走）+ 落点白闪 / 火星线 / 分叉裂网（落地留在原地）；精一碎石 + 隆起尘墙 + 「粉碎」碎石迸开；精二裂缝熔芯 + 「破阵」地裂与岩刺；
## S1「冲锋号令·γ型」= 腰高号令声浪 + 脚下冲击环，下一锤换「号令一锤」（锤弧更粗、落点金色冲击环）；分支「万兽之王」号令波读玩法状态 o.hw.sg.waves；
## S2「跃空锤」= 起跳一小圈 → 落地竖直冲柱 + 大裂网 + 冲击环 + 碎石 + 尘墙（精二熔芯 + 环外前向枝裂）；
## S3「碎颅击」= 起手腰高横向光带 + 冲击环，持续时脚下炭火边，每锤横向扁白闪 + 向前分叉的地裂扇；
## 后期剑气（钝器）= 锤击冲击波（贴地往前滚的土浪 + 身后裂痕），同一次出手几道合成一道；技能连携 v2「冲阵」= 尾锤大砸坑。

var _motes: Array = []   # 技力粒子：{to 队友, from, t0, life, bend}（只画）
var _sg_imp := {}        # 干员 id → 最近一锤的落点（只画）
var _sg_cores: Array = []   # 锤击落点亮芯：{at, t0, big}，3 拍（0.2 秒）内每帧排进发光层


func _ev_sg(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用：事件的游戏时间
		print("PXPLOG sg %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	var id: String = str(o.id)
	match kind:
		"swing":   # 锤击（普攻 / 冲锋号令强化一锤 / 碎颅）：seg_siege._h4_hammer_release
			var ang: float = float(d.get("ang", 0.0))
			var reach: float = float(d.get("reach", 92.0))
			var heavy: bool = d.get("heavy", false)
			var patch: bool = d.get("patch", false)
			var dv := Vector2.from_angle(ang)
			var imp: Vector2 = o.pos + Vector2(dv.x, dv.y * 0.72) * reach * 0.7   # 锤弧落点（平面里压扁的那一点）
			var dk: Array = pick_dir(ang)
			_sg_imp[id] = imp   # 这一锤的落点（破阵地裂从这里裂出去；只画）
			if mode() == 1:   # 落点亮芯稳定进发光层（docs/270：普攻命中帧核心辉光 ≥ 30；帧条 emit 是均匀抽点，大多落在四散的火星上）
				if _sg_cores.size() >= 6:
					_sg_cores.pop_front()
				_sg_cores.append({"at": _snap(imp + Vector2(0, -6)), "t0": g.t, "big": bool(d.get("heavy", false)) or bool(d.get("patch", false))})
			if raw:
				var rk: String = "sg_raw_s3" if heavy else "sg_raw_imp_e%d" % t
				_push({"k": rk, "t0": g.t, "gp": imp + Vector2(0, -6), "ly": "raw", "rot": ang, "sc": g.PX * (reach * 0.5) / 46.0, "oid": id})
				return
			var ak: String
			if heavy:
				ak = "sg_arc_s3_up_d%d" % dk[0]
			elif patch:
				ak = "sg_arc_s1_e%d_up_d%d" % [t, dk[0]]
			else:
				ak = "sg_arc_r%d_e%d_up_d%d" % [_bucket(reach * 0.5, [46, 56, 66]), t, dk[0]]
			# 同一名干员同屏只留最新一锤 + 正在收的一锤（不叠成一团）
			var sl: Array = []
			for it in items:
				if str(it.oid) == id and it.get("slash", false):
					sl.append(float(it.t0))
			if sl.size() >= 2:
				sl.sort()
				var keep_t: float = float(sl[sl.size() - 1])
				items = items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == id and float(it.t0) < keep_t))
			_push({"k": ak, "t0": g.t, "gp": _snap(o.pos), "flip": dk[1], "ly": "up", "oid": id, "slash": true, "fo": Vector2.ZERO})   # 锤弧挂在人身上：跟人走
			if heavy:
				_push({"k": "sg_s3_up", "t0": g.t, "gp": _snap(imp), "flip": false, "ly": "up", "oid": id})
				_push({"k": "sg_s3_gd_d%d" % dk[0], "t0": g.t, "gp": _snap(imp), "flip": dk[1], "ly": "gd", "oid": id})
			else:
				var ik: String = "sg_imp_%s_e%d" % ["s1" if patch else "atk", t]
				_push({"k": ik + "_up", "t0": g.t, "gp": _snap(imp), "flip": false, "ly": "up", "oid": id})
				_push({"k": ik + "_gd", "t0": g.t, "gp": _snap(imp), "flip": false, "ly": "gd", "oid": id})
			var big: bool = heavy or patch
			_burst_m(o, R, p, imp + Vector2(0, -8), imp.y + 2.0, d.get("es", []), (2 + mini(t, 1)) + (4 if big else 0), "rock", 100.0 + (60.0 if big else 0.0), 0.4 + (0.3 if big else 0.0))   # docs/270：普攻颗粒中位 10 → 压回 3–8
		"crush":   # 精一「粉碎」：击倒处碎石迸开（强制低档画面时不画）
			if t < 1 or raw:
				return
			var at: Vector2 = d.get("at", o.pos)
			_push({"k": "sg_crush_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": id})
			_push({"k": "sg_crush_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": id})
			if mode() == 1:
				R._grains(o, at + Vector2(0, -8), at.y, "rock", 2, {"tier": t})
		"breach":   # 精二「破阵」地裂 + 岩刺 / 再跃（队长版）原地砸出的地裂（不出岩刺）
			var pts: PackedVector2Array = d.get("pts", PackedVector2Array())
			if pts.size() < 2 or raw:
				return
			var spikes: bool = d.get("spikes", false)
			if spikes and t < 2:
				return
			var a: Vector2 = pts[0]
			var b: Vector2 = pts[pts.size() - 1]
			var fa: float = (b - a).angle()
			var dk2: Array = pick_dir(fa)
			var st: Vector2 = _sg_imp.get(id, a) if spikes else o.pos + Vector2(a.x - o.pos.x, (a.y - o.pos.y) * 0.72)
			var L: int = 90 if spikes else _bucket(a.distance_to(b) * 0.5, [60, 90, 110])
			var pre: String = "sg_fis" if spikes else "sg_crk"
			_push({"k": "%s_l%d_gd_d%d" % [pre, L, dk2[0]], "t0": g.t, "gp": _snap(st), "flip": dk2[1], "ly": "gd", "oid": id})
			if spikes:
				_push({"k": "sg_fis_l90_up_d%d" % dk2[0], "t0": g.t, "gp": _snap(st), "flip": dk2[1], "ly": "up", "oid": id})
			if mode() == 1:
				var mid: Vector2 = st + Vector2(cos(fa), sin(fa) * 0.72) * float(L)
				R._grains(o, mid + Vector2(0, -6), mid.y, "rock", 1, {"tier": t})   # docs/270：普攻单次颗粒 ≤ 12
				R._light(o, mid, 120.0, 0.45, 0.15, p.light)
		"quake":   # 成长「震地」/「狮吼」：落点一圈贴地冲击环（狮吼双环）
			if raw:
				return
			var qa: Vector2 = d.get("at", o.pos)
			_push({"k": "sg_quake_r%d_%s_gd" % [_bucket(float(d.get("r", 70.0)) * 0.5, [35, 45, 55]), "roar" if d.get("roar", false) else "q"], "t0": g.t, "gp": _snap(qa), "flip": false, "ly": "gd", "oid": id})
		"crash":   # 狮吼：被击退的敌人撞上别的敌人 / 障碍
			if raw:
				return
			var ca: Vector2 = d.get("at", o.pos) + Vector2(0, 8)
			_push({"k": "sg_crash_up", "t0": g.t, "gp": _snap(ca), "flip": false, "ly": "up", "oid": id})
			_push({"k": "sg_crash_gd", "t0": g.t, "gp": _snap(ca), "flip": false, "ly": "gd", "oid": id})
			if mode() == 1:
				R._light(o, ca, 70.0, 0.35, 0.1, p.light)
		"leap":   # 跃空锤起跳：脚下一小圈 + 起跳点 → 落点一道金色残影弧（她在空中抡锤转一圈）
			if raw:
				return
			_push({"k": "sg_crash_gd", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": id})
			var to: Vector2 = d.get("to", o.pos)
			if to.distance_to(o.pos) > 8.0:
				var dk3: Array = pick_dir((to - o.pos).angle())
				_push({"k": "sg_trail_l%d_e%d_up_d%d" % [_bucket(to.distance_to(o.pos) * 0.5, [24, 45]), maxi(t, 1), dk3[0]], "t0": g.t, "gp": _snap(o.pos), "flip": dk3[1], "ly": "up", "oid": id})
			if mode() == 1:
				R._grains(o, o.pos + Vector2(0, -4), o.pos.y, "rock", 3, {"tier": t})
		"slam":   # 跃空锤落地（含再跃第二下）
			_sg_slam(o, R, p, d.get("at", o.pos), float(d.get("r", 110.0)), d.get("es", []), raw, maxi(t, 1), "slam")
			_sg_motes(o, 1)
		"shape":   # 路线「再跃·裂地」：跃空锤落地 0.8 秒后以自身为心再震一圈（circle 震地 r140）
			if d.get("circle", false) and str(d.get("src", "")) == "震地":
				_sg_slam(o, R, p, d.get("c", o.pos), float(d.get("r", 140.0)), d.get("es", []), raw, maxi(t, 1), "rift")
		"skill":
			var i: int = int(d.get("i", -1))
			if raw:
				return
			if i == 0:   # 冲锋号令：身后战旗 + 身前狮头剪影与狮吼声波环（朝她面向，跟人走）+ 脚下淡金涟漪 + 技力粒子飞向队友 + 轻震
				_push({"k": "sg_s1cast_e%d_up" % t, "t0": g.t, "gp": _snap(o.pos), "flip": float(o.face) < 0.0, "ly": "up", "oid": id, "fo": Vector2.ZERO})
				_push({"k": "sg_lion_e%d_up" % t, "t0": g.t, "gp": _snap(o.pos), "flip": float(o.face) < 0.0, "ly": "up", "oid": id, "fo": Vector2.ZERO})   # 狮头（生图转帧条，docs/264 §8）
				if mode() == 1 and g.ult != null:
					g.ult.shake(2.0, 0.12)   # 狮吼：轻微震屏（用户同意的 3px / 0.12s 量级以内，按真实时间）
				_push({"k": "sg_s1cast_e%d_gd" % t, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": id})
				_sg_motes(o, 2)
				if mode() == 1:
					R._light(o, o.pos + Vector2(0, -30), 130.0, 0.5, 0.15, p.light)
			elif i == 2:   # 碎颅击起手：腰高横向光带（跟人走）+ 脚下冲击环
				_push({"k": "sg_s3cast_up", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": id, "fo": Vector2.ZERO})
				_push({"k": "sg_s3cast_gd", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": id})
				if mode() == 1:
					R._light(o, o.pos + Vector2(0, -24), 150.0, 0.6, 0.15, p.light)
		"link_dash":   # 技能连携 v2「冲阵」冲刺途中：脚下扬起的碎土（代替通用拖影 / 尘）
			if mode() == 1 and g.vrng.randf() < 0.35:
				var q: Vector2 = d.get("q", o.pos)
				R._grains(o, q + Vector2(0, -2), q.y + 2.0, "rock", 1, {"tier": 1})
		"link_slam":   # 「冲阵」尾锤：大砸坑 + 裂网 + 冲击环 + 碎石 + 两层尘墙
			var lc: Vector2 = d.get("c", o.pos)
			if raw:
				_push({"k": "sg_raw_slam_e1", "t0": g.t, "gp": lc, "ly": "raw", "rot": 0.0, "sc": g.PX * 46.0 / 55.0, "oid": id})
				return
			_push({"k": "sg_link_up", "t0": g.t, "gp": _snap(lc), "flip": false, "ly": "up", "oid": id})
			_push({"k": "sg_link_gd", "t0": g.t, "gp": _snap(lc), "flip": false, "ly": "gd", "oid": id})
			_burst_m(o, R, p, lc + Vector2(0, -10), lc.y + 2.0, d.get("es", []), 10, "rock", 170.0, 0.7)


## S2 落地 = 环形尘浪（slam，不开裂）；路线「再跃·裂地」= 冲柱 + 裂网（rift）
func _sg_slam(o, R, p: Dictionary, at: Vector2, r: float, es: Array, raw: bool, t: int, kind: String) -> void:
	if raw:
		_push({"k": "sg_raw_slam_e%d" % t, "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 55.0, "oid": str(o.id)})
		return
	var sk: String = ("sg_rift_r70_e%d" % t) if kind == "rift" else ("sg_slam_r55_e%d" % t)
	_push({"k": sk + "_up", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "up", "oid": str(o.id)})
	_push({"k": sk + "_gd", "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})
	_burst_m(o, R, p, at + Vector2(0, -10), at.y + 2.0, es, 8 + 3 * t, "rock", 200.0, 0.85)


## 技力粒子：从她飞向每名队友（状态提示，原程序 h4_spmote 接管时不画，这里按美术像素格画）
func _sg_motes(o, n: int) -> void:
	if mode() != 1:
		return
	for m in g.squad.ops:
		if m == o or m.pos == Vector2.INF:
			continue
		for k in n:
			if _motes.size() >= 24:
				_motes.pop_front()
			_motes.append({"to": m, "from": o.pos + Vector2(0, -22), "t0": g.t + 0.06 * k, "life": 0.45 + 0.08 * k, "bend": g.vrng.randf_range(-40.0, 40.0)})


func _sg_draw_motes(o) -> void:
	if _motes.is_empty():
		return
	var cv = o.cv
	var px: float = g.PX
	var keep: Array = []
	for mt in _motes:
		var age: float = g.t - float(mt.t0)
		if age > float(mt.life):
			continue
		keep.append(mt)
		if age < 0.0 or mt.to.pos == Vector2.INF:
			continue
		var k: float = age / float(mt.life)
		var st: Vector2 = mt.from
		var to: Vector2 = mt.to.pos + Vector2(0, -24)
		var at: Vector2 = st.lerp(to, k) + Vector2(0, -sin(k * PI) * 30.0) + st.direction_to(to).orthogonal() * sin(k * PI) * float(mt.bend)
		var k2: float = maxf(0.0, k - 0.1)
		var tl: Vector2 = st.lerp(to, k2) + Vector2(0, -sin(k2 * PI) * 30.0) + st.direction_to(to).orthogonal() * sin(k2 * PI) * float(mt.bend)
		cv.draw_rect(Rect2(_snap(tl), Vector2(px, px)), Color("#e08e26"))
		var c: Vector2 = _snap(at)
		cv.draw_rect(Rect2(c - Vector2(px, px) * 0.5, Vector2(px, px) * 2.0), Color("#ffbf3c"))
		cv.draw_rect(Rect2(c, Vector2(px, px)), Color("#fff1b8"))
		if g.optical_on and _emit_n < EMIT_CAP:
			_emit_n += 1
			g.glow_next.append([c, px, Color(1.0, 0.85, 0.5, (Bal.v("fx/px_plane_emit", 0.8) * float(g.world.lf_emit_k)))])
	_motes = keep


## 地面层（推进之王）：贴地件、号令波（读 o.hw.sg.waves）、碎颅击持续时脚下炭火边、锤击冲击波的影子与裂痕
func _floor_sg(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	_sg_draw_cores()   # 落点亮芯先排进发光层：地面层每帧最先画，整队 EMIT_CAP 顶满时也不被挤掉（docs/270）
	if o.skill_active_left(2) > 0.0:
		_draw_strip(cv, "sg_s3aura_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	if o.hw.has("sg"):
		for w in o.hw.sg.get("waves", []):   # 万兽之王号令波：帧号按波自己的年龄（0.4 秒扩满 + 0.25 秒淡掉）
			_draw_strip(cv, "sg_cmd_gd", int(floor(float(w.t) * 15.0)), _snap(w.pos), false, true)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)
	_sg_qi_track(o)


## 后期剑气（late_shape → vis_growth._fire_qi，只读 o.vg.qi）：每次出手新生成的几道合成一道冲击波，自己往前推约 0.5 秒（判定照旧，画面比判定走得远）；
## 前沿扫过的怪打出火星（每道冲击波至多 5 只）。同屏每人至多两道。新剑气记一个画面专用键 _pxw（玩法不读）
var _sgw: Array = []   # {oid, mv, t0, hits, S}


func _sg_qi_track(o) -> void:
	var id: String = str(o.id)
	if not o.vg.is_empty() and o.vg.has("qi"):
		var grp: Array = []
		for q in o.vg.qi:
			if not q.has("_pxw"):
				q["_pxw"] = true
				grp.append(q)
		if not grp.is_empty():
			var p0 := Vector2.ZERO
			var dsum := Vector2.ZERO
			for q in grp:
				p0 += q.p
				dsum += (q.v as Vector2).normalized()
			p0 /= float(grp.size())
			var dir: Vector2 = dsum.normalized() if dsum.length() > 0.01 else Vector2.RIGHT
			var n: int = grp.size()
			var S: int = 18 if n <= 1 else (24 if n == 2 else 30)
			var dk: Array = pick_dir(dir.angle())
			var mv := {"p0": p0, "dir": Vector2(dir.x, dir.y * 0.72).normalized()}
			var k: String = "sg_wave_s%d_e%d" % [S, tier(o)]
			var mine: Array = _sgw.filter(func(w): return str(w.oid) == id)
			if mine.size() >= 2:   # 同屏每人至多两道：最早的一道立刻收掉
				var old: Dictionary = mine[0]
				var omv: Dictionary = old.mv
				items = items.filter(func(it): return not (it.has("mv") and is_same(it.mv, omv)))
				_sgw.erase(old)
			_push({"k": k + "_up_d%d" % dk[0], "t0": g.t, "gp": _snap(p0), "flip": dk[1], "ly": "up", "oid": id, "mv": mv})
			_push({"k": k + "_gd_d%d" % dk[0], "t0": g.t, "gp": _snap(p0), "flip": dk[1], "ly": "gd", "oid": id, "mv": mv})
			_sgw.append({"oid": id, "mv": mv, "t0": g.t, "hits": {}, "S": float(S) * 2.0})
	if _sgw.is_empty() or mode() != 1:
		return
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	var keep: Array = []
	for w in _sgw:
		if g.t - float(w.t0) > 0.55:
			continue
		keep.append(w)
		if str(w.oid) != id or w.hits.size() >= 5:
			continue
		var front: Vector2 = _gp({"mv": w.mv, "t0": w.t0})
		for j in o.query_ids(front, float(w.S) + 20.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or w.hits.has(e.id) or e.pos.distance_to(front) > float(w.S) * 0.8 + float(e.r):
				continue
			w.hits[e.id] = true
			R._grains(o, e.pos + Vector2(0, -float(e.r) * 0.5), float(e.pos.y) + 2.0, "streak", 2, {"tier": tier(o)}, w.mv.dir)
			if w.hits.size() >= 5:
				break
	_sgw = keep


# ================================================================ 水月（docs/261，照 docs/246 斯卡蒂的做法）
## 意象：深海、水母、触手、幻象。色：深蓝紫 8 阶（OP.mizuki）+ 水母荧光青；精二点缀荧光紫。
## 分档按「每升一档多一个新元素」（11-05 用户）：精零 = 伞面 + 水母；精一起触手出现；精二荧光紫 + 深蓝之籽 + 双触手 / 对缠。
## 普攻「伞击」= 腰高伞面月牙（伞沿扇贝 + 伞骨；精二伞骨荧光紫）+ 命中处青色水母绽开 + 精一起生命最低的那只脚下钻出触手（精零只绽开水母）；
## S1「唤醒」= 更大更白的伞面 + 青白沿 + 向外甩水，命中处三团大水母绽开 + 地上冲击环；精一起每团下面钻出触手；
## S2「囚徒困境」= 起手一圈触手钻出 + 中心冰蓝尖晶；持续期间伞击更薄更快、青白沿 + 幻影残弧，被触手打中的缠住（前后两半圈）；
## S3「镜花水月」= 起手大水母从脚下浮起 + 地上一圈水镜带月影；持续期间深蓝紫旋斩 + 荧光紫刃，脚下水镜，触手更粗；
## 触手五种形态按场合用：普攻追击拍击（精二多一根卷须）、唤醒刺穿、束缚卷须 + 缠绕、镜花水月粗拍击、连携群生。
## 精二「深蓝之籽」= 身后小水母改画像素水母（离身游猎时拖三点尾），蛰中一朵紫色小水母；连携「小触手」= 高触手钻出 + 缠住 1 秒。
const MZ_TENT_MAX := 5     # 同屏触手（同一名干员）；GCP 实机 E1 一次 5–6 根拍击堆成一丛，8 → 5
const MZ_COIL_MAX := 10    # 同屏缠绕
const MZ_BLOOM_MAX := 5    # 同屏命中水母绽开

var _smzs = null


func _smz():
	if _smzs == null:
		_smzs = load("res://scripts/characters/blocks/seg_mizuki.gd")   # 运行时取（避免和积木链循环 preload）
	return _smzs


static func _mz_pick(r: float, opts: Array) -> int:
	var best: int = int(opts[0])
	for v in opts:
		if absf(float(v) - r) < absf(float(best) - r):
			best = int(v)
	return best


func _mz_count(o, pre: String) -> int:
	var n := 0
	for it in items:
		if str(it.oid) == str(o.id) and str(it.k).begins_with(pre) and str(it.ly) == "up":
			n += 1
	return n


## 伞面月牙（方向件 / 旋斩）：挂在人身上（fo，跟人走）；同一名干员只留上一刀 + 这一刀（不碎）
func _mz_slash(o, key: String, ang: float, spin: bool) -> void:
	var sl: Array = []
	for it in items:
		if str(it.oid) == str(o.id) and it.get("slash", false) and str(it.ly) == "up":
			sl.append(it.t0)
	if sl.size() >= 2:
		sl.sort()
		var keep_t: float = float(sl[sl.size() - 1])
		items = items.filter(func(it): return not (it.get("slash", false) and str(it.oid) == str(o.id) and float(it.t0) < keep_t))
	var dk: Array = pick_dir(ang)
	var ku: String = (key + "_up") if spin else "%s_up_d%d" % [key, dk[0]]
	var kg: String = (key + "_gd") if spin else "%s_gd_d%d" % [key, dk[0]]
	var fl: bool = dk[1] and not spin
	_push({"k": ku, "t0": g.t, "gp": _snap(o.pos), "flip": fl, "ly": "up", "oid": str(o.id), "slash": true, "fo": Vector2.ZERO})
	_push({"k": kg, "t0": g.t, "gp": _snap(o.pos), "flip": fl, "ly": "gd", "oid": str(o.id), "slash": true, "fo": Vector2.ZERO})


## 命中水母绽开：原点 = 命中点，排在被打那只前面；同屏至多 MZ_BLOOM_MAX 团
func _mz_bloom(o, e: Dictionary, key: String, raw: bool, t: int) -> void:
	var hp: Vector2 = e.pos + Vector2(0, -float(e.r) * 0.55)
	if raw:
		_push({"k": "mz_raw_bloom_e%d" % t, "t0": g.t, "gp": hp, "ly": "raw", "rot": 0.0, "sc": g.PX * 1.2, "oid": str(o.id)})
		return
	if _mz_count(o, "mz_bloom") + _mz_count(o, "mz_sting") >= MZ_BLOOM_MAX:
		return
	_push({"k": key, "t0": g.t, "gp": _snap(hp), "gy": float(e.pos.y) + 2.0, "flip": false, "ly": "up", "oid": str(o.id)})


## 触手：目标脚边（离水月远的一侧）钻出，朝水月倾（拖拽感）；束缚（stun ≥ 0.45，非 Boss）时再缠住 min(stun, 1.2) 秒
func _mz_tent(o, e: Dictionary, at: Vector2, key: String, raw: bool, t: int, bind: float) -> void:
	var side: float = 1.0 if at.x >= o.pos.x else -1.0
	var er: float = float(e.get("r", 14.0))
	var arc: bool = key.contains("_slam_") or key.contains("_big_")   # 拍击要越过头顶拍下来：底座放远一点，落点正好在目标上（不拍到旁边空地）
	var base: Vector2 = at + Vector2(side * (er * 0.55 + (16.0 if arc else 0.0)), 3.0)
	if raw:
		_push({"k": "mz_raw_tent_e%d" % t, "t0": g.t, "gp": base, "ly": "raw", "rot": 0.0, "sc": g.PX * 1.15, "oid": str(o.id)})
		return
	var busy := false   # 同一只身上已经有一根还没缩回的触手：不再叠（囚徒困境 / 镜花水月连挥时不堆成一丛）
	for it in items:
		if it.has("tg") and is_same(it.tg, e) and g.t - float(it.t0) < 0.35:
			busy = true
			break
	if not busy and _mz_count(o, "mz_tent") < MZ_TENT_MAX:
		_push({"k": key + "_up", "t0": g.t, "gp": _snap(base), "gy": base.y + 0.5, "flip": side > 0.0, "ly": "up", "oid": str(o.id), "tg": e})
		_push({"k": key + "_gd", "t0": g.t, "gp": _snap(base), "flip": side > 0.0, "ly": "gd", "oid": str(o.id)})
	if bind >= 0.45 and not e.get("boss", false) and not e.get("dead", false):
		_mz_coil(o, e, clampi(t, 1, 2), minf(bind, 1.2))


func _mz_coil(o, e: Dictionary, t: int, life: float) -> void:
	var found := false
	for it in items:   # 同一只已经缠着：续时间，不叠
		if it.has("ef") and is_same(it.ef, e):
			it.life = maxf(float(it.life), g.t - float(it.t0) + life)
			found = true
	if found or _mz_count(o, "mz_coil") >= MZ_COIL_MAX * 2:
		return
	var rx: int = _mz_pick(float(e.r) * 0.5, [6, 9, 13, 18])
	for half in ["back", "front"]:
		_push({"k": "mz_coil_r%d_e%d_%s_up" % [rx, t, half], "t0": g.t, "gp": _snap(e.pos), "ef": e, "sk": -1.5 if half == "back" else 1.5,
			"flip": false, "ly": "up", "oid": str(o.id), "loop": true, "life": life})


func _ev_mz(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	match kind:
		"mz_umb":
			var ang: float = float(d.get("ang", 0.0))
			var r: float = float(d.get("r", 112.0))
			var lst: Array = (d.get("es", []) as Array).duplicate()
			lst.sort_custom(func(a, b): return a.pos.distance_squared_to(o.pos) < b.pos.distance_squared_to(o.pos))
			var nb := 2
			var bk: String = "mz_bloom_e%d_up" % t
			if d.get("s3", false):   # 镜花水月：全范围深蓝紫旋斩
				if raw:
					_push({"k": "mz_raw_spin3", "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": 0.0, "sc": g.PX * (r * 0.5) / 81.0, "oid": str(o.id)})
				else:
					_mz_slash(o, "mz_spin3_r%d" % _mz_pick(r * 0.5, [81, 104]), 0.0, true)
				nb = 3
				bk = "mz_bloom_e2_up"
			elif d.get("emp", false):   # 唤醒强化的那一击（命中处另有三团大水母：mz_burst）
				if raw:
					_push({"k": "mz_raw_s1_e%d" % t, "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / 73.0, "oid": str(o.id)})
				else:
					_mz_slash(o, "mz_s1_r%d_e%d" % [_mz_pick(r * 0.5, [73, 92]), t], ang, false)
				nb = 1
			else:
				var r0: int = _mz_pick(r * 0.5, [56, 70])
				if raw:
					_push({"k": "mz_raw_atk_e%d" % t, "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": ang, "sc": g.PX * (r * 0.5) / 56.0, "oid": str(o.id)})
				elif d.get("s2", false):   # 囚徒困境期间
					_mz_slash(o, "mz_s2_r%d_e%d" % [r0, clampi(t, 1, 2)], ang, false)
				else:
					_mz_slash(o, "mz_atk_r%d_e%d" % [r0, t], ang, false)
			for i in mini(nb, lst.size()):
				_mz_bloom(o, lst[i], bk, raw, t)
			if mode() == 1 and not lst.is_empty():
				var hp: Vector2 = lst[0].pos + Vector2(0, -float(lst[0].r) * 0.5)
				for i in mini(2, lst.size()):   # docs/270：命中帧要量得出核心辉光——命中点一小撮白芯进 emit（4 拍）
					var hot := {"k": "", "mzhot": true, "t0": g.t, "gp": _snap(lst[i].pos + Vector2(0, -float(lst[i].r) * 0.55)), "ly": "gd", "oid": str(o.id), "life": 4.0 / 15.0}
					if i == 0:   # 颗粒等白芯第一次画的时候再撒（发光层晚一帧上屏：颗粒和辉光落在同一帧）；每次挥伞 4–5 颗（原来伞击 + 每根触手各撒，一簇 13 颗）
						hot["gr"] = [hp, float(lst[0].pos.y) + 2.0, 4 + (1 if t >= 2 else 0), t, (hp - o.pos).normalized()]
					_push(hot)
				R._light(o, hp, 100.0, 0.5 * MI.lit_k(g), 0.12, p.light)   # docs/270 复测：照地亮度峰值 +42 → 0.45 时 +48（下限 +50）→ 0.5（实测约 0.68）
		"mz_tent":
			var e: Dictionary = d.get("e", {})
			if e.is_empty():
				return
			var s3: bool = d.get("s3", false)
			if t == 0 and not s3:   # 11-05 用户：精零普攻不出触手（触手是精一的招牌），追击那一下只在目标身上绽开一朵水母
				_mz_bloom(o, e, "mz_bloom_e0_up", raw, t)
				return
			var stn: float = float(d.get("stun", 0.0))
			_mz_tent(o, e, d.get("at", e.pos), _mz_tk("big", 2) if s3 else (_mz_tk("curl", t) if stn >= 0.45 else _mz_tk("slam", t)), raw, t, stn)   # 触手不再另撒颗粒（颗粒数算进伞击那一簇）
		"mz_burst":   # 唤醒创伤扩散：大水母绽开 + 地上冲击环
			var at: Vector2 = d.get("at", o.pos)
			if raw:
				_push({"k": "mz_raw_bloom_e%d" % t, "t0": g.t, "gp": at + Vector2(0, -16), "ly": "raw", "rot": 0.0, "sc": g.PX * 2.2, "oid": str(o.id)})
				return
			_push({"k": "mz_burst_e%d_up" % t, "t0": g.t, "gp": _snap(at + Vector2(0, -16)), "gy": at.y + 3.0, "flip": false, "ly": "up", "oid": str(o.id)})
			_push({"k": "mz_burst_e%d_gd" % t, "t0": g.t, "gp": _snap(at), "flip": false, "ly": "gd", "oid": str(o.id)})
			if t >= 1:   # 精一起：每团大水母下面钻出一根触手（分档加新元素，不靠换色）
				_mz_tent(o, {"pos": at, "r": 10.0, "boss": true}, at, _mz_tk("pierce", t), raw, t, 0.0)
			if mode() == 1:
				R._grains(o, at + Vector2(0, -18), at.y, "ink", 3, {"tier": t})   # docs/270：三团合一簇 ≤ 16（伞击 4–5 + 3 × 3）
				_push({"k": "", "mzhot": true, "t0": g.t, "gp": _snap(at + Vector2(0, -16)), "ly": "gd", "oid": str(o.id), "life": 4.0 / 15.0})
				R._light(o, at + Vector2(0, -14), 140.0, 0.55 * MI.lit_k(g), 0.14, p.light)
		"mz_sting":   # 深蓝之籽蛰中：一朵紫色小水母
			var e2: Dictionary = d.get("e", {})
			if not e2.is_empty() and not raw:
				_mz_bloom(o, e2, "mz_sting_up", raw, t)
		"mz_stake":
			var at2: Vector2 = d.get("at", o.pos)
			_mz_tent(o, {"pos": at2, "r": 8.0, "boss": true}, at2, _mz_tk("pierce", t), raw, t, 0.0)
		"mz_splash":   # 扩散：一圈细水纹（每拍至多 3 圈）
			if raw or _mz_count_gd(o, "mz_ripple") >= 3:
				return
			_push({"k": "mz_ripple_gd", "t0": g.t, "gp": _snap(d.get("at", o.pos)), "flip": false, "ly": "gd", "oid": str(o.id)})
		"mz_link":   # 连携「小触手」：高触手钻出 + 缠住 1 秒（不分档）
			for e3 in d.get("es", []):
				if e3.get("dead", false):
					continue
				_mz_tent(o, e3, e3.pos, _mz_tk("cluster", 2), raw, 2, 0.0 if e3.get("boss", false) else 1.0)
			if mode() == 1:
				R._light(o, d.get("c", o.pos), 150.0, 0.5, 0.15, p.light)
		"shape":   # 惊跳反射·余悸（circle，src 触手）：身边一圈触手抽打
			if d.get("circle", false) and not raw:
				var c: Vector2 = d.get("c", o.pos)
				_push({"k": "mz_awk2_up", "t0": g.t, "gp": _snap(c), "flip": false, "ly": "up", "oid": str(o.id)})
				_push({"k": "mz_awk2_gd", "t0": g.t, "gp": _snap(c), "flip": false, "ly": "gd", "oid": str(o.id)})
		"skill":
			if raw:
				return
			var i: int = int(d.get("i", -1))
			if i == 1:   # 囚徒困境起手：一圈触手钻出 + 中心冰蓝尖晶（跟人）
				var tt: int = clampi(t, 1, 2)
				_push({"k": "mz_s2cast_e%d_up" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
				_push({"k": "mz_s2cast_e%d_gd" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				R._light(o, o.pos + Vector2(0, -14), 160.0, 0.7, 0.15, p.hot)
			elif i == 2:   # 镜花水月起手：大水母浮起（跟人）+ 水镜月影
				_push({"k": "mz_moon_up", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
				_push({"k": "mz_moon_gd", "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				R._grains(o, o.pos + Vector2(0, -40), o.pos.y, "ink", 6, {"tier": 2})
				R._light(o, o.pos + Vector2(0, -30), 170.0, 0.7, 0.15, p.light)


## 触手形态键（11-05 用户「多做几个形态」）：slam 拍击（普攻追击）/ pierce 刺穿（唤醒大水母下、触手桩）/ curl 卷须（束缚）/ big 粗拍击（镜花水月）/ cluster 群生（连携）；
## 每种 3 个变体（弯向 / 长短 / 粗细不同），按画面随机数挑，不像复制粘贴
func _mz_tk(form: String, t: int) -> String:
	var tt: int = 2 if form in ["big", "cluster"] else clampi(t, 1, 2)
	return "mz_tent_%s_e%d_v%d" % [form, tt, g.vrng.randi_range(0, 2)]


func _mz_count_gd(o, pre: String) -> int:
	var n := 0
	for it in items:
		if str(it.oid) == str(o.id) and str(it.k).begins_with(pre) and str(it.ly) == "gd" and g.t - float(it.t0) < 1.0 / 15.0:
			n += 1
	return n


## 地面层：贴地件 + 唤醒充能小环 + 镜花水月水镜（跟人）
func _mz_draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	if o.ammo[0] > 0:
		_draw_strip(cv, "mz_ready_gd", frame_of(0.0), _snap(o.pos + Vector2(0, 4)), false, false)
	if o.skill_active_left(2) > 0.0:
		var rr: float = float(o.hw.mz.get("s3_fx_radius", 0.0)) if o.hw.has("mz") else 0.0
		if rr <= 0.0:
			rr = 162.0
		_draw_strip(cv, "mz_pool_r%d_gd" % _mz_pick(rr * 0.5, [81, 104]), frame_of(0.0), _snap(o.pos + Vector2(0, 2)), false, false)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id:
			if it.has("mzhot"):
				_mz_hot(it)
				continue
			_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)


## 命中白芯：只进发光层（4 拍：十字 + 斜角，逐拍收小变淡，emit 预算内），不画色层——色层的亮由水母绽开那一帧自己画；
## docs/270 复测：体检挑的命中帧在出手后约 0.2 秒，2 拍白芯已熄（辉光面积 8），延到 4 拍
func _mz_hot(it: Dictionary) -> void:
	if it.has("gr"):
		var gr: Array = it.gr
		it.erase("gr")
		var oo = _op(str(it.oid))
		if oo != null:
			load("res://scripts/render/fx_recipe.gd").of(g)._grains(oo, gr[0], gr[1], "ink", int(gr[2]), {"tier": int(gr[3])}, gr[4])
	if not g.optical_on:
		return
	var f: int = frame_of(float(it.t0))
	if f < 0 or f > 3:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:
		_emit_frame = fr
		_emit_n = 0
	var px: float = g.PX
	var c0: Vector2 = it.gp
	var k: float = minf(1.0, Bal.v("fx/px_plane_emit", 0.8) * MI.lit_k(g) * [1.0, 0.9, 0.75, 0.55][f])
	var pts: Array = [Vector2.ZERO, Vector2(px, 0), Vector2(-px, 0), Vector2(0, px), Vector2(0, -px), Vector2(px, px), Vector2(-px, px), Vector2(px, -px), Vector2(-px, -px)]
	if f <= 1:
		pts += [Vector2(px * 2, 0), Vector2(-px * 2, 0), Vector2(0, px * 2), Vector2(0, -px * 2)]
	for q in pts:
		if _emit_n >= EMIT_CAP:
			return
		_emit_n += 1
		g.glow_next.append([c0 + q, px, Color(0.85, 0.97, 1.0, k)])


## 排序项：深蓝之籽（身后 / 离身游猎的小水母）、藏品剑气（小水母游过去）
func _mz_sort_items(o, out: Array) -> void:
	var t: int = tier(o)
	var mz: Dictionary = o.hw.get("mz", {})
	for j in mz.get("jel", []):
		var jp: Vector2 = j.p
		out.append({"mzj": "mz_jelly_up", "a": jp, "v": j.get("v", Vector2.ZERO) if str(j.ph) != "home" else Vector2.ZERO, "gp": _snap(jp + Vector2(0, 6)), "gy": jp.y + 34.0})
	if o.get("vg") is Dictionary and not o.vg.is_empty():
		for q in o.vg.get("qi", []):
			var qp: Vector2 = _wpos({"pos": q.p, "_pxq": q.get("_pxq")}, q)
			out.append({"mzj": "mz_qi_e%d_up" % t, "a": qp + Vector2(0, -14), "v": q.v, "gp": _snap(qp + Vector2(0, -8)), "gy": qp.y + 1.0})


## 小水母：循环帧条 + 离身时身后三点尾（逐美术像素，越后越暗）
func _mz_draw_jelly(ci, it: Dictionary) -> void:
	var v: Vector2 = it.v
	if v.length() > 1.0:
		var back: Vector2 = -v.normalized()
		var cols := [Color.html("#9aa8ff"), Color.html("#5a7cf0"), Color.html("#3150c8")]
		for i in 3:
			var pp: Vector2 = _snap((it.a as Vector2) + back * float(6 + i * 6))
			ci.draw_rect(Rect2(pp, Vector2(g.PX, g.PX)), cols[i])
	_draw_strip(ci, str(it.mzj), frame_of(0.0), it.gp, false, false)


# ================================================================ 浊心斯卡蒂（docs/260，照 docs/246 斯卡蒂的做法）
## 她是召唤 + 控场的歌手，特效全是「圈」：判定半径随技能 / 精英化 / 成长连续变化，烤成帧条只能按整数倍放大对不上半径，
## 所以主形全部运行时画：笔触弧 = 三角形带（顶点对齐 2 世界像素格，进低分辨率层后正好 1 美术像素一格，硬边、无抗锯齿），
## 形状按 15 fps 全局节拍换（旋转角、扩散半径都按拍取值）。贴地件按 combat.GROUND_Y（0.72）压扁；音符、气泡、红光柱、小鱼是立起件，按脚底 y 和单位一起排序。
## 色层吃场景光（画在世界层），白热 / 红光柱芯出 emit 点进发光层，爆发与命中挂照地点光（fx_recipe 灯光预算）；颗粒只用 twinkle / drop 少量。
## 招式：普攻声浪 = 一圈断口笔触浪从 0.6 扩到判定边 + 命中处音符（E1 加厚 + 第二道浪 + 余音外环；E2 浪里夹一道酒红暗流 + 双音符）；
## 歌域（常驻地面区域）= 边上 3–5 段粗笔触 + 贴边淡渐变 + 内侧 2–4 道反向细笔触线；S1 = 身周气泡（E1 双层膜、E2 三团）+ 脚下酒红细环；
## S2 = 起手脚下旋涡 + 酒红小鱼（之后小鱼常驻绕歌域游，E1 3 条 / E2 5 条；E2 涡眼冲起一道水柱）；
## S3 = 起手与之后每 3 秒一次「潮涌」：粗笔触亮蓝环（深蓝内影）扩到歌域边 + 内部实心渐变（不透明度 0.5 → 0.35）+ 8 道旋转笔触线 + 5 根粗亮红竖光柱；持续期间歌域加粗加快。
## 伊莎玛拉（精二海嗣）的小歌域 = 酒红细笔触；连携 v2「歌声」= 区域笔触圈 + 酒红内圈 3 秒 + 音符；旧连携声浪 = 大一号声浪。
## 成长 / 后期：共鸣小声浪、潮汐和声回声（酒红细浪）、深海的回响爆点、late_shape「扩散」溅射环（同屏每拍至多 3 个）。

const SK_SY := 0.72
const SK_B := [Color("#070d22"), Color("#0e1d4a"), Color("#183486"), Color("#2752c4"), Color("#4f80ec"), Color("#9dbcff"), Color("#ffffff")]   # 深海蓝 7 阶（原作歌域蓝，避开敌弹青 #33ceff）
const SK_R := [Color("#3a0d1b"), Color("#5e1424"), Color("#86202d"), Color("#a8323c"), Color("#dc4048"), Color("#ffb4bc"), Color("#ffffff")]   # 酒红（house.js OP.skalter，亮段色相 357°，避开危险红 331–353°）
const SK_T := [Color("#06141c"), Color("#0b2a35"), Color("#124552"), Color("#1b6466"), Color("#3b8e89"), Color("#86c6bd"), Color("#e8f5f0")]   # 海嗣青（house.js OP.skalter_sea，原作海嗣色，偏灰、避开敌弹青）：伊莎玛拉小歌域与同步声浪
const SK_NOTE := ["....####", "....#..#", "....#..#", "....#...", "....#...", "....#...", ".####...", "#####...", "#####...", ".###...."]
const SK_NOTE2 := ["...########", "...#......#", "...#......#", "...#......#", "...#......#", ".###....###", "####...####", "####...####", ".##.....##."]
const SK_UP := ["..#..", ".###.", "#.#.#", "..#..", ".###.", "#.#.#"]   # 增益双箭头（往上）
const SK_FISH := ["#...####..", "##.######.", ".#########", "##.######.", "#...####.."]
var _sk_st := {}          # 干员 id → 画面状态（缓动半径、潮涌下次时刻、上一拍去重），玩法不读


func _sk_beat() -> int:
	return int(floor(g.t * 15.0))


func _sk_h(i: int, s: float) -> float:
	return fposmod(sin(float(i) * 12.9898 + s * 78.233) * 43758.5453, 1.0)


func _sk_state(o) -> Dictionary:
	var id: String = str(o.id)
	if not _sk_st.has(id):
		_sk_st[id] = {"r": {}, "s3_next": -1.0, "s3_on": false, "dd": {}}
	return _sk_st[id]


## 画面半径：判定半径一变（S1 开 / 关、S3、灯火档位……），画面在 SK_RT（0.3）秒里平滑过渡到新半径（smoothstep），
## 不一跳一跳（11-05 用户）；按美术像素取整；判定半径立即生效
const SK_RT := 0.3
func _sk_r(o, key: String, zr: float) -> float:
	var st: Dictionary = _sk_state(o)
	var e: Array = st.r.get(key, [zr, zr, zr, -99.0])   # [当前画面半径, 目标, 起点, 起变时刻]
	if absf(zr - float(e[1])) > 0.5:
		e = [float(e[0]), zr, float(e[0]), g.t]
	var u: float = clampf((g.t - float(e[3])) / SK_RT, 0.0, 1.0)
	e[0] = lerpf(float(e[2]), float(e[1]), u * u * (3.0 - 2.0 * u))
	st.r[key] = e
	return round(float(e[0]) / g.PX) * g.PX


## 跟歌域走的件（fz）的半径按画面半径同比缩放，和歌域边对齐
func _sk_rk(it: Dictionary) -> float:
	var o = it.get("o", null)
	if o == null or not it.get("fz", false) or not is_instance_valid(o):
		return 1.0
	var e: Array = _sk_state(o).r.get("self", [])
	if e.is_empty() or float(o.zr) <= 1.0:
		return 1.0
	return clampf(float(e[0]) / float(o.zr), 0.3, 3.0)


## 椭圆上一点（贴地：纵向 × GROUND_Y）
func _sk_ep(c: Vector2, rr: float, a: float) -> Vector2:
	return c + Vector2(cos(a) * rr, sin(a) * rr * SK_SY)


## 一笔贴地笔触弧：c 圆心（世界）、R 半径（世界）、a0 → a1 弧度、w 宽（美术像素）、taper 两头收尖、seed 粗细起伏；
## 主色一条带 + 外缘 1 美术像素迎光边（中段）+ 内缘 1 美术像素暗边；顶点对齐 2 世界像素格
func _sk_arc(cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	if g.opt_old & g.OPT_SKDOM:
		_sk_arc_old(cv, c, R, a0, a1, w, col, hi, lo, seed, taper)
		return
	if _sk_test:   # --skdomtest：新旧两种写法各算一遍、逐位比顶点 / 颜色 / 下标，不一致计数（PF SKDOM 打印），画的是旧写法
		var ra := _SkRec.new()
		var rb := _SkRec.new()
		_sk_arc_old(ra, c, R, a0, a1, w, col, hi, lo, seed, taper)
		_sk_arc_new(rb, c, R, a0, a1, w, col, hi, lo, seed, taper)
		_sk_test_n += 1
		if not ra.same(rb):
			_sk_test_bad += 1
		if _sk_test_n % 2000 == 0:
			print("PF SKDOM n=%d bad=%d" % [_sk_test_n, _sk_test_bad])
		_sk_arc_old(cv, c, R, a0, a1, w, col, hi, lo, seed, taper)
		return
	_sk_arc_new(cv, c, R, a0, a1, w, col, hi, lo, seed, taper)


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

func _sk_arc_geo(a0: float, a1: float, n: int, w: float, px: float, seed: float, taper: bool) -> Array:
	var bt: int = _sk_beat()
	if bt != _sk_ac_beat:
		_sk_ac_beat = bt
		_sk_ac.clear()
	var key := [a0, a1, n, w, px, seed, taper]
	var e = _sk_ac.get(key)
	if e != null:
		return e
	var span: float = a1 - a0
	var ca := PackedFloat64Array()
	var sa := PackedFloat64Array()
	var ths := PackedFloat64Array()
	var cb := PackedFloat64Array()
	var sb := PackedFloat64Array()
	ca.resize(n + 1)
	sa.resize(n + 1)
	ths.resize(n + 1)
	cb.resize(n + 1)
	sb.resize(n + 1)
	for i in n + 1:
		var u: float = float(i) / float(n)
		var a: float = a0 + span * u
		var th: float = w * px * (pow(maxf(0.0, sin(PI * u)), 0.55) if taper else 1.0) * (0.82 + 0.36 * _sk_h(i / 3, seed))
		th = maxf(th, px * 0.5) if taper else th
		ths[i] = th
		ca[i] = cos(a)
		sa[i] = sin(a)
		var a2: float = a0 + span * float(i) / float(n)
		cb[i] = cos(a2)
		sb[i] = sin(a2)
	e = [ca, sa, ths, cb, sb]
	_sk_ac[key] = e
	return e


func _sk_arc_new(cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	if R <= 2.0 or w <= 0.0 or col.a <= 0.003:
		return
	var px: float = g.PX
	var span: float = a1 - a0
	var n: int = clampi(int(absf(span) * R / (px * 3.0)), 3, 72)
	var geo: Array = _sk_arc_geo(a0, a1, n, w, px, seed, taper)
	var ca: PackedFloat64Array = geo[0]
	var sa: PackedFloat64Array = geo[1]
	var ths: PackedFloat64Array = geo[2]
	var cb: PackedFloat64Array = geo[3]
	var sb: PackedFloat64Array = geo[4]
	var pts := PackedVector2Array()
	pts.resize((n + 1) * 2)
	for i in n + 1:
		var th: float = ths[i]
		var r1: float = R + th * 0.5
		var r2: float = R - th * 0.5
		pts[i * 2] = ((c + Vector2(ca[i] * r1, sa[i] * r1 * SK_SY)) / 2.0).round() * 2.0
		pts[i * 2 + 1] = ((c + Vector2(ca[i] * r2, sa[i] * r2 * SK_SY)) / 2.0).round() * 2.0
	_sk_band_pts(cv, pts, n + 1, col)
	if w >= 2.0 and hi.a > 0.003:   # 迎光边：外缘中段 1 美术像素
		var lo_i: int = n / 5
		var hi_i: int = n - n / 5
		var m2: int = hi_i - lo_i + 1
		var p2 := PackedVector2Array()
		p2.resize(m2 * 2)
		for i in range(lo_i, hi_i + 1):
			var th: float = ths[i]
			var r1: float = R + th * 0.5
			var r2: float = R + th * 0.5 - px
			var k: int = (i - lo_i) * 2
			p2[k] = ((c + Vector2(cb[i] * r1, sb[i] * r1 * SK_SY)) / 2.0).round() * 2.0
			p2[k + 1] = ((c + Vector2(cb[i] * r2, sb[i] * r2 * SK_SY)) / 2.0).round() * 2.0
		_sk_band_pts(cv, p2, m2, hi)
	if w >= 3.0 and lo.a > 0.003:   # 内缘暗边
		var p3 := PackedVector2Array()
		p3.resize((n + 1) * 2)
		for i in n + 1:
			var th: float = ths[i]
			var r1: float = R - th * 0.5 + px
			var r2: float = R - th * 0.5
			p3[i * 2] = ((c + Vector2(cb[i] * r1, sb[i] * r1 * SK_SY)) / 2.0).round() * 2.0
			p3[i * 2 + 1] = ((c + Vector2(cb[i] * r2, sb[i] * r2 * SK_SY)) / 2.0).round() * 2.0
		_sk_band_pts(cv, p3, n + 1, lo)


## _sk_band 的已交错版本：pts 已是 外0, 内0, 外1, 内1 …（m 对）；下标表按 m 缓存（与 _sk_band 生成的相同）
func _sk_band_pts(cv, pts: PackedVector2Array, m: int, col: Color) -> void:
	if m < 2:
		return
	var idx = _sk_idx.get(m)
	if idx == null:
		idx = PackedInt32Array()
		for i in m - 1:
			var k: int = i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
		_sk_idx[m] = idx
	var cols := PackedColorArray([col])
	cv.add_tris(pts, cols, idx)


func _sk_arc_old(cv, c: Vector2, R: float, a0: float, a1: float, w: float, col: Color, hi: Color, lo: Color, seed: float, taper := true) -> void:
	if R <= 2.0 or w <= 0.0 or col.a <= 0.003:
		return
	var px: float = g.PX
	var span: float = a1 - a0
	var n: int = clampi(int(absf(span) * R / (px * 3.0)), 3, 72)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var ths: Array = []
	for i in n + 1:
		var u: float = float(i) / float(n)
		var a: float = a0 + span * u
		var th: float = w * px * (pow(maxf(0.0, sin(PI * u)), 0.55) if taper else 1.0) * (0.82 + 0.36 * _sk_h(i / 3, seed))
		th = maxf(th, px * 0.5) if taper else th
		ths.append(th)
		outer.append(_snap(_sk_ep(c, R + th * 0.5, a)))
		inner.append(_snap(_sk_ep(c, R - th * 0.5, a)))
	_sk_band(cv, outer, inner, col)
	if w >= 2.0 and hi.a > 0.003:   # 迎光边：外缘中段 1 美术像素
		var o2 := PackedVector2Array()
		var i2 := PackedVector2Array()
		var lo_i: int = n / 5
		var hi_i: int = n - n / 5
		for i in range(lo_i, hi_i + 1):
			var a: float = a0 + span * float(i) / float(n)
			var th: float = float(ths[i])
			o2.append(_snap(_sk_ep(c, R + th * 0.5, a)))
			i2.append(_snap(_sk_ep(c, R + th * 0.5 - px, a)))
		_sk_band(cv, o2, i2, hi)
	if w >= 3.0 and lo.a > 0.003:   # 内缘暗边
		var o3 := PackedVector2Array()
		var i3 := PackedVector2Array()
		for i in n + 1:
			var a: float = a0 + span * float(i) / float(n)
			var th: float = float(ths[i])
			o3.append(_snap(_sk_ep(c, R - th * 0.5 + px, a)))
			i3.append(_snap(_sk_ep(c, R - th * 0.5, a)))
		_sk_band(cv, o3, i3, lo)


func _sk_band(cv, outer: PackedVector2Array, inner: PackedVector2Array, col: Color) -> void:
	var m: int = mini(outer.size(), inner.size())
	if m < 2:
		return
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in m:
		pts.append(outer[i])
		pts.append(inner[i])
	for i in m - 1:
		var k: int = i * 2
		idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	cv.add_tris(pts, cols, idx)


## 贴边淡渐变 / 实心渐变：r0 → r1 两圈之间，透明度 a0（内）→ a1（外）
func _sk_grad(cv, c: Vector2, r0: float, r1: float, col: Color, a0: float, a1: float) -> void:
	if r1 <= 2.0 or (a0 <= 0.003 and a1 <= 0.003):
		return
	var n: int = clampi(int(r1 / 6.0), 20, 64)
	var ci := Color(col.r, col.g, col.b, a0)
	var co := Color(col.r, col.g, col.b, a1)
	if not (g.opt_old & g.OPT_SKDOM) and not _sk_test:   # 缓存写法（docs/287 §3 ②）：方向表与下标表只跟点数有关；算式同下
		var gt = _sk_gc.get(n)
		if gt == null:
			var gc := PackedFloat64Array()
			var gs := PackedFloat64Array()
			var gi := PackedInt32Array()
			for i in n:
				var a: float = TAU * float(i) / float(n)
				gc.append(cos(a))
				gs.append(sin(a))
			for i in n:
				var k: int = i * 2
				var k2: int = ((i + 1) % n) * 2
				gi.append_array([k, k + 1, k2, k + 1, k2 + 1, k2])
			gt = [gc, gs, gi]
			_sk_gc[n] = gt
		var gc2: PackedFloat64Array = gt[0]
		var gs2: PackedFloat64Array = gt[1]
		var rr0: float = maxf(0.0, r0)
		var pts2 := PackedVector2Array()
		pts2.resize(n * 2)
		var cols2 := PackedColorArray()
		cols2.resize(n * 2)
		for i in n:
			pts2[i * 2] = ((c + Vector2(gc2[i] * r1, gs2[i] * r1 * SK_SY)) / 2.0).round() * 2.0
			pts2[i * 2 + 1] = ((c + Vector2(gc2[i] * rr0, gs2[i] * rr0 * SK_SY)) / 2.0).round() * 2.0
			cols2[i * 2] = co
			cols2[i * 2 + 1] = ci
		cv.add_tris(pts2, cols2, gt[2])
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(_snap(_sk_ep(c, r1, a)))
		cols.append(co)
		pts.append(_snap(_sk_ep(c, maxf(0.0, r0), a)))
		cols.append(ci)
	for i in n:
		var k: int = i * 2
		var k2: int = ((i + 1) % n) * 2
		idx.append_array([k, k + 1, k2, k + 1, k2 + 1, k2])
	cv.add_tris(pts, cols, idx)


## 逐美术像素的小图案（立起件：音符、小鱼）；左上角 tl（世界），fl 水平翻转
func _sk_pat(ci, pat: Array, tl: Vector2, col: Color, head: Color, fl := false, sh := Color(0, 0, 0, 0)) -> void:
	if ci is CanvasItem and not (g.opt_old & g.OPT_SKPAT):
		if _skp_test:   # --skpattest：旧写法交出的矩形（记录器）与新写法的三角形逐个比（顶点 / 颜色 / 次序），PF SKPAT 打印
			var rec := _SkRectRec.new()
			_sk_pat(rec, pat, tl, col, head, fl, sh)
			var e2: Array = _sk_pat_geo(pat, fl, col, head, sh)
			var pts: PackedVector2Array = Transform2D(0.0, _snap(tl)) * (e2[0] as PackedVector2Array)
			var ok: bool = pts.size() == rec.rects.size() * 4
			for i in rec.rects.size():
				if not ok:
					break
				var r2: Rect2 = rec.rects[i][0]
				ok = pts[i * 4] == r2.position and pts[i * 4 + 1] == r2.position + Vector2(r2.size.x, 0.0) and pts[i * 4 + 2] == r2.end and pts[i * 4 + 3] == r2.position + Vector2(0.0, r2.size.y) and (e2[1] as PackedColorArray)[i * 4] == rec.rects[i][1]
			_skp_test_n += 1
			if not ok:
				_skp_test_bad += 1
			if _skp_test_n % 500 == 0:
				print("PF SKPAT n=%d bad=%d" % [_skp_test_n, _skp_test_bad])
		_sk_pat_tris(ci, pat, tl, col, head, fl, sh)
		return
	var px: float = g.PX
	var p0: Vector2 = _snap(tl)
	var hh: int = pat.size()
	if sh.a > 0.0:   # 1 美术像素暗描边（右下投影）：压在白色敌人 / 伤害数字上也读得出
		for y in hh:
			var row0: String = pat[y]
			var w0: int = row0.length()
			for x in w0:
				if row0[x] == "#":
					var x0: int = (w0 - 1 - x) if fl else x
					ci.draw_rect(Rect2(p0 + Vector2(x0 + 1, y + 1) * px, Vector2(px, px)), sh)
	for y in hh:
		var row: String = pat[y]
		var ww: int = row.length()
		for x in ww:
			if row[x] != "#":
				continue
			var xx: int = (ww - 1 - x) if fl else x
			ci.draw_rect(Rect2(p0 + Vector2(xx, y) * px, Vector2(px, px)), head if y >= hh - 2 else col)


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

func _sk_pat_tris(ci: CanvasItem, pat: Array, tl: Vector2, col: Color, head: Color, fl: bool, sh: Color) -> void:
	var e: Array = _sk_pat_geo(pat, fl, col, head, sh)
	if (e[0] as PackedVector2Array).is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), e[2], Transform2D(0.0, _snap(tl)) * (e[0] as PackedVector2Array), e[1])


func _sk_pat_geo(pat: Array, fl: bool, col: Color, head: Color, sh: Color) -> Array:
	var key := [pat, fl, col, head, sh]
	var e = _skp_cache.get(key)
	if e == null:
		var px: float = g.PX
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var hh: int = pat.size()
		var rects: Array = []
		if sh.a > 0.0:
			for y in hh:
				var row0: String = pat[y]
				var w0: int = row0.length()
				for x in w0:
					if row0[x] == "#":
						var x0: int = (w0 - 1 - x) if fl else x
						rects.append([Vector2(x0 + 1, y + 1) * px, sh])
		for y in hh:
			var row: String = pat[y]
			var ww: int = row.length()
			for x in ww:
				if row[x] != "#":
					continue
				var xx: int = (ww - 1 - x) if fl else x
				rects.append([Vector2(xx, y) * px, head if y >= hh - 2 else col])
		for rc in rects:
			var q0: Vector2 = rc[0]
			pts.append_array([q0, q0 + Vector2(px, 0.0), q0 + Vector2(px, px), q0 + Vector2(0.0, px)])
			for j in 4:
				cols.append(rc[1])
		var n: int = rects.size()
		var idx = _skp_idx.get(n)
		if idx == null:
			idx = PackedInt32Array()
			for i in n:
				var k: int = i * 4
				idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
			_skp_idx[n] = idx
		e = [pts, cols, idx]
		if _skp_cache.size() > 256:
			_skp_cache.clear()
		_skp_cache[key] = e
	return e


## 一圈断口笔触浪（普攻声浪 / 回声 / 海嗣同步 / 小声浪）：k 断成几段，w 宽，rot 起始角
func _sk_ring(cv, c: Vector2, R: float, k: int, w: float, col: Color, hi: Color, lo: Color, seed: float, rot: float, fill := 0.82) -> void:
	for j in k:
		var a0: float = rot + TAU * (float(j) + 0.06 * _sk_h(j, seed)) / float(k)
		var a1: float = a0 + TAU / float(k) * (fill - 0.12 * _sk_h(j + 7, seed))
		_sk_arc(cv, c, R * (0.98 + 0.04 * _sk_h(j + 13, seed)), a0, a1, w * (0.8 + 0.4 * _sk_h(j + 3, seed)), col, hi, lo, seed + float(j))


func _sk_push(o, it: Dictionary) -> void:
	it["oid"] = str(o.id)
	it["k"] = ""
	if not it.has("t0"):
		it["t0"] = g.t
	_push(it)


## 同屏件数（同一名干员、同一类）
func _sk_count(o, kind: String) -> int:
	var n := 0
	var id: String = str(o.id)
	for it in items:
		if str(it.get("skr", "")) == kind and str(it.oid) == id:
			n += 1
	return n


func _ev_skalter(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	var px: float = g.PX
	var st: Dictionary = _sk_state(o)
	if Bal.v("fx/recipe_log", 0.0) > 0.0:
		print("PXPLOG sk %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			if not d.get("circle", false):
				return
			var src: String = str(d.get("src", ""))
			var c: Vector2 = d.get("c", o.pos)
			var r: float = float(d.get("r", 190.0))
			var es: Array = d.get("es", [])
			var key: String = "%s|%d|%d" % [src, int(c.x), int(c.y)]
			if st.dd.get(key, -1.0) == g.t:
				return   # 她当队长时「领唱」与普攻同一帧同一圈：只画一次
			st.dd[key] = g.t
			if raw:
				var rk: String = "sk_raw_wave_e%d" % t
				if src == "共鸣" or src == "深海的回响":
					rk = "sk_raw_wave_e0"
				_push({"k": rk, "t0": g.t, "gp": c, "ly": "raw", "rot": 0.0, "sc": px * (r * 0.5) / 95.0, "oid": str(o.id)})
				return
			match src:
				"声浪":
					if mode() == 1 and (o.skill_active_left(0) > 0.0 or o.skill_active_left(2) > 0.0) and _sk_count(o, "buff") < 6:
						for q in g.squad.ops:   # 增益挂在吃到增益的人身上：歌域里的每名干员头顶一枚往上飘的双箭头（攻速 / 攻击提升），每圈声浪一次
							if q.pos != Vector2.INF and o.in_zone(q.pos):
								_sk_push(o, {"skr": "buff", "c": q.pos, "tgt": q, "s3": o.skill_active_left(2) > 0.0, "ly": "up", "gy": q.pos.y + 2.0, "life": 8.0 / 15.0})
					_sk_push(o, {"skr": "wave", "c": c, "r": r, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
					_sk_notes(o, es, t, R, p)
					var lp: Vector2 = c + Vector2(0, -6)
					for e0 in es:
						if e0 is Dictionary and not e0.get("dead", false):
							lp = e0.pos + Vector2(0, -float(e0.r) * 0.5)
							break
					var n2 := 0
					for e2 in es:   # 第二只命中的再挂一盏小的（每次 ≤ 2 盏）
						if e2 is Dictionary and not e2.get("dead", false):
							n2 += 1
							if n2 == 2:
								R._light(o, e2.pos + Vector2(0, -float(e2.r) * 0.5), 80.0, 0.38, 0.12, p.light)
								break
					R._light(o, lp, 100.0, 0.5, 0.12, p.light)   # docs/270：每次命中一盏、半径 100、强度 0.5（原来半径 = 0.7 歌域，摊满半屏照不出命中点）
				"余音":   # 精一：外圈回声
					_sk_push(o, {"skr": "echo_ring", "c": c, "r": r, "tier": t, "ly": "gd", "life": 4.0 / 15.0, "o": o, "fz": true})
				"潮汐和声":
					_sk_push(o, {"skr": "wave", "c": c, "r": r, "tier": t, "rose": true, "thin": true, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
				"海嗣":   # 精二伊莎玛拉同步声浪（酒红）
					_sk_push(o, {"skr": "wave", "c": c, "r": r, "tier": t, "sea": true, "ly": "gd", "life": 6.0 / 15.0})
					_sk_notes(o, es.slice(0, 2), t, R, p, true)
				"共鸣":   # 歌域内击杀处的小声浪
					if _sk_count(o, "mini") < 6:
						_sk_push(o, {"skr": "mini", "c": c, "r": r, "ly": "gd", "life": 4.0 / 15.0})
				_:
					if _sk_count(o, "mini") < 6:
						_sk_push(o, {"skr": "mini", "c": c, "r": r, "ly": "gd", "life": 4.0 / 15.0})
			if src != "声浪" and mode() == 1:   # docs/270：每一圈（海嗣 / 余音 / 回声 / 小声浪）也各挂一盏灯 + 2 颗水滴，落在第一只命中的敌人身上
				var hp2: Vector2 = c + Vector2(0, -8)
				var gy2: float = c.y + 2.0
				for e1 in es:
					if e1 is Dictionary and not e1.get("dead", false):
						hp2 = e1.pos + Vector2(0, -float(e1.r) * 0.5)
						gy2 = float(e1.pos.y) + 2.0
						break
				R._light(o, hp2, 90.0, 0.42, 0.12, SK_T[5] if src == "海嗣" else p.light)
				R._grains(o, hp2, gy2, "ink", 2, {"tier": t})
				if not es.is_empty() and _sk_count(o, "pop") < 8:   # 命中点白芯（同音符的起音），头两拍进发光层
					_sk_push(o, {"skr": "pop", "c": hp2, "sea": src == "海嗣", "ly": "up", "gy": gy2, "life": 2.0 / 15.0})
		"sk_burst":   # 深海的回响：满层爆开（酒红小爆环 + 几颗碎光）
			var at: Vector2 = d.at
			if raw:
				_push({"k": "sk_raw_wave_e0", "t0": g.t, "gp": at, "ly": "raw", "rot": 0.0, "sc": px * (float(d.r) * 0.5) / 95.0, "oid": str(o.id)})
				return
			if _sk_count(o, "burst") < 4:
				_sk_push(o, {"skr": "burst", "c": at, "r": float(d.r), "ly": "gd", "life": 5.0 / 15.0})
				if mode() == 1:
					R._grains(o, at + Vector2(0, -10), at.y + 2.0, "shard", 6, {"tier": t})
					R._light(o, at + Vector2(0, -8), 60.0, 0.35, 0.1, SK_R[4])
		"splash":   # late_shape「扩散」：命中溅射（同一拍至多 3 个）
			var at2: Vector2 = d.at
			if raw:
				_push({"k": "sk_raw_wave_e0", "t0": g.t, "gp": at2, "ly": "raw", "rot": 0.0, "sc": px * (float(d.r) * 0.5) / 95.0, "oid": str(o.id)})
				return
			if _lm_beat_n(o, "sk_splash") < 3:
				_sk_push(o, {"skr": "splash", "c": at2, "r": float(d.r), "ly": "gd", "life": 3.0 / 15.0})
		"skill":
			var i: int = int(d.get("i", -1))
			var zc: Vector2 = o.zone_c()
			var zr: float = float(o.zr)
			if raw:
				var rk2: String = ["sk_raw_s1_e%d" % t, "sk_raw_s2_e%d" % maxi(t, 1), "sk_raw_s3_e2"][clampi(i, 0, 2)]
				_push({"k": rk2, "t0": g.t, "gp": zc, "ly": "raw", "rot": 0.0, "sc": px * (zr * 0.5) / 95.0, "oid": str(o.id)})
				return
			match i:
				0:   # S1 同归殊途之吟：身周气泡（循环到技能结束，读 skill_active_left）+ 脚下酒红细环；歌域扩张一道浪
					_sk_push(o, {"skr": "wave", "c": zc, "r": zr, "tier": t, "ly": "gd", "life": 6.0 / 15.0, "o": o, "fz": true})
					R._light(o, zc + Vector2(0, -24), 90.0, 0.5, 0.15, SK_B[5])   # 歌域圆心 = 队长（她当队友时不在她脚下）
					if mode() == 1:
						R._grains(o, zc + Vector2(0, -30), zc.y, "ink", 3 + t, {"tier": t})
				1:   # S2 同葬无光之愿：脚下旋涡 + 小鱼散开
					var tt: int = maxi(t, 1)
					_sk_push(o, {"skr": "vortex", "c": zc, "tier": tt, "ly": "gd", "life": 12.0 / 15.0, "o": o, "fz": true})   # 歌域圆心 = 队长
					_sk_push(o, {"skr": "fishburst", "c": zc, "tier": tt, "ly": "up", "gy": zc.y + 1.0, "life": 12.0 / 15.0, "o": o, "fz": true})
					if tt >= 2:
						_sk_push(o, {"skr": "spout", "c": zc, "ly": "up", "gy": zc.y + 2.0, "life": 8.0 / 15.0, "o": o, "fz": true})
					R._light(o, zc + Vector2(0, -12), 110.0, 0.5, 0.15, SK_B[4])
				2:   # S3 潮涌，潮枯：起手就是第一次潮涌，之后每 3 秒一次（draw_floor 里按技能剩余时间续）
					st.s3_next = g.t
		"sk_link":   # 连携 v2「歌声」：区域笔触圈 3 秒 + 起手一道大浪 + 音符
			var lc: Vector2 = d.c
			var lr: float = float(d.r)
			if raw:
				_push({"k": "sk_raw_s1_e2", "t0": g.t, "gp": lc, "ly": "raw", "rot": 0.0, "sc": px * (lr * 0.5) / 95.0, "oid": str(o.id)})
				return
			_sk_push(o, {"skr": "song", "c": lc, "r": lr, "ly": "gd", "life": 3.0})
			_sk_push(o, {"skr": "wave", "c": lc, "r": lr, "tier": 2, "ly": "gd", "life": 6.0 / 15.0})
			_sk_push(o, {"skr": "songnotes", "c": lc, "r": lr, "ly": "up", "gy": lc.y, "life": 3.0})
			R._light(o, lc + Vector2(0, -10), lr, 0.6, 0.15, SK_B[4])
		"sk_combo":   # 旧连携（link/v2 关）：落点大一号声浪 + 命中音符
			var cc: Vector2 = d.at
			var cr: float = float(d.r)
			if raw:
				_push({"k": "sk_raw_wave_e2", "t0": g.t, "gp": cc, "ly": "raw", "rot": 0.0, "sc": px * (cr * 0.5) / 95.0, "oid": str(o.id)})
				return
			_sk_push(o, {"skr": "wave", "c": cc, "r": cr, "tier": 2, "big": true, "ly": "gd", "life": 6.0 / 15.0})
			_sk_notes(o, d.get("es", []), 2, R, p)
			R._light(o, cc + Vector2(0, -10), cr, 0.6, 0.15, SK_B[4])


## 命中音符：每下至多 2 / 3 / 4 个（E0 / E1 / E2），同屏至多 12 个
func _sk_notes(o, es: Array, t: int, R, p: Dictionary, rose := false) -> void:
	var nmax: int = [2, 3, 4][t]
	var n := 0
	for e in es:
		if n >= nmax or _sk_count(o, "note") >= 12:
			break
		if not (e is Dictionary) or e.get("dead", false):
			continue
		var hp: Vector2 = e.pos + Vector2(0, -float(e.r) - 6.0)
		_sk_push(o, {"skr": "note", "c": hp, "hp": e.pos + Vector2(0, -float(e.r) * 0.5), "tier": t, "rose": rose, "fl": (n % 2) == 1, "ly": "up", "gy": float(e.pos.y) + 1.0, "life": 9.0 / 15.0})
		if n == 0 and mode() == 1:
			R._grains(o, hp, float(e.pos.y) + 2.0, "ink", 3 + t, {"tier": t})   # docs/270：Noita 水滴 4–6 px、寿命约 0.9 秒，每下 3 / 4 / 5 颗
		n += 1


## 地面层：歌域（常驻）、伊莎玛拉小歌域、S3 持续加粗 / 潮涌、一次性贴地件
func _sk_draw_floor(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var t: int = tier(o)
	var st: Dictionary = _sk_state(o)
	var bt: float = float(_sk_beat()) / 15.0
	var s3: float = o.skill_active_left(2)
	if s3 > 0.0 and float(st.s3_next) >= 0.0 and g.t >= float(st.s3_next):   # 潮涌：起手一次，之后每 3 秒
		st.s3_next = g.t + 3.0
		_sk_push(o, {"skr": "surge", "c": o.zone_c(), "r": float(o.zr), "ly": "gd", "life": 7.0 / 15.0, "o": o, "fz": true})
		_sk_push(o, {"skr": "pillars", "c": o.zone_c(), "r": float(o.zr), "ly": "up", "gy": o.zone_c().y + 2.0, "life": 7.0 / 15.0, "o": o, "fz": true})
		var R = load("res://scripts/render/fx_recipe.gd").of(g)
		R._light(o, o.zone_c() + Vector2(0, -20), minf(float(o.zr), 220.0), 0.8, 0.15, SK_B[4])
		R._light(o, o.zone_c() + Vector2(0, -60), 120.0, 0.6, 0.15, SK_R[4])
		R._grains(o, o.zone_c() + Vector2(0, -30), o.zone_c().y, "ink", 10, {"tier": 2})
	elif s3 <= 0.0:
		st.s3_next = -1.0
	if o.pos != Vector2.INF and o.B.has("zone"):
		var zc: Vector2 = o.zone_c()
		var zv: float = _sk_r(o, "self", float(o.zr))
		var s1: bool = o.skill_active_left(0) > 0.0
		_sk_domain(cv, zc, zv, t, s1, s3 > 0.0, bt, 0.0, false)
	for s in (o.sm.list if not o.sm.is_empty() else []):
		var szr: float = float(s.get("zr", 0.0))
		if szr <= 0.0 or s.gone:
			continue
		var fa: float = clampf(float(s.t) / 0.5, 0.0, 1.0)
		_sk_domain(cv, s.pos, _sk_r(o, "sm", szr) * fa, t, false, false, bt, 3.7, true)
	for it in items:
		if str(it.ly) == "gd" and str(it.oid) == id and it.has("skr"):
			_sk_draw_gd(cv, o, it)


## 一个歌域：边上 3–5 段粗笔触（慢转）+ 贴边淡渐变 + 内侧反向细笔触线；rose = 伊莎玛拉小歌域（酒红、细）
func _sk_domain(cv, c: Vector2, R: float, t: int, s1: bool, s3: bool, bt: float, seed: float, rose: bool) -> void:
	if R <= 8.0:
		return
	var dim: float = clampf(float(g.world.fx_dim), 0.5, 1.0)
	var C: Array = SK_T if rose else SK_B
	var n: int = (3 + t) if not s3 else 6
	if s1 and not s3:
		n += 1
	var w: float = (3.0 if t < 2 else 4.0) if not s3 else 5.0
	if rose:
		n = 3
		w = 2.0
	var spin: float = (0.10 if not s3 else 0.28) * (1.0 if not rose else -1.3)
	var rot: float = bt * spin + seed
	var main: Color = C[3] if not (s1 or s3) else C[4]
	main.a = 0.92 * dim
	var hi: Color = C[5]
	hi.a = 0.9 * dim
	var lo: Color = C[1]
	lo.a = 0.8 * dim
	var cover: float = 0.62 if not s3 else 0.72
	for j in n:
		var a0: float = rot + TAU * (float(j) + 0.15 * _sk_h(j, seed + 1.0)) / float(n)
		var a1: float = a0 + TAU / float(n) * cover * (0.75 + 0.5 * _sk_h(j + 5, seed + 1.0))
		_sk_arc(cv, c, R * (0.985 + 0.03 * _sk_h(j + 11, seed)), a0, a1, w, main, hi, lo, seed + float(j) * 1.7)
	# 贴边淡渐变（不平涂中心）
	var ga: float = (0.10 if not s3 else 0.16) * dim * (0.7 if rose else 1.0)
	_sk_grad(cv, c, R - g.PX * (10.0 if not s3 else 18.0), R, C[3], 0.0, ga)
	# 内侧细笔触线（11-05 用户「内部可以稍微实一点，或者加点线条」）：2–4 道，反向慢转，1 美术像素
	if not rose:
		var nl: int = 2 + t if not s3 else 5
		var lc: Color = C[4]
		lc.a = (0.45 if not s3 else 0.6) * dim
		for j in nl:
			var rr: float = R * (0.62 + 0.22 * _sk_h(j + 31, seed))
			var a0: float = -bt * (0.18 if not s3 else 0.45) + TAU * float(j) / float(nl) + _sk_h(j + 41, seed)
			_sk_arc(cv, c, rr, a0, a0 + 0.9 + 0.5 * _sk_h(j + 51, seed), 1.0, lc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), seed + 9.0 + j)


## 挂在人身上的件（歌域圆心 fz / 本人脚下 fs）：持续期间跟着施放者当前位置走（按 15 fps 拍跳格）；落在地上的件留在原地
func _sk_c(it: Dictionary) -> Vector2:
	var o = it.get("o", null)
	if o != null and is_instance_valid(o) and o.pos != Vector2.INF:
		if it.get("fz", false):
			return _snap(o.zone_c())
		if it.get("fs", false):
			return _snap(o.pos)
	return it.c


func _sk_draw_gd(cv, o, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	var px: float = g.PX
	var c: Vector2 = _sk_c(it)
	match str(it.skr):
		"wave":   # 声浪：断口笔触浪 0.6R → R（4 拍扩到边、第 5 拍淡），E1 第二道、E2 夹酒红暗流
			if f < 0 or f > 5:
				return
			var t: int = int(it.tier)
			var rose: bool = it.get("rose", false)
			var thin: bool = it.get("thin", false)
			var sea: bool = it.get("sea", false)
			var C: Array = SK_T if sea else (SK_R if rose else SK_B)
			var R: float = float(it.r) * _sk_rk(it) * [0.6, 0.78, 0.9, 0.97, 1.0, 1.02][f]
			var w: float = ([4.0, 5.0, 6.0][t] if not thin else 2.0) * [1.0, 1.0, 0.85, 0.7, 0.5, 0.35][f]
			if it.get("big", false):
				w += 2.0
			var col: Color = C[6] if f == 0 else (C[5] if f == 1 else C[4])
			if f >= 4:
				col = C[3]
				col.a = 0.6 if f == 4 else 0.35
			var hi: Color = C[6] if f <= 2 else C[5]
			var lo: Color = C[2]
			var seed: float = float(int(it.t0 * 7.0) % 97)
			_sk_ring(cv, c, R, 7 if t < 2 else 8, w, col, hi, lo, seed, seed * 0.37)
			if t >= 1 and not thin and f >= 1:   # 精一：晚一拍的第二道细浪
				var c2: Color = C[4]
				c2.a = 0.7 if f < 4 else 0.3
				_sk_ring(cv, c, R * 0.86, 6, 2.0, c2, Color(0, 0, 0, 0), Color(0, 0, 0, 0), seed + 3.0, seed * 0.37 + 0.4, 0.7)
			if t >= 2 and not rose and not sea and f <= 4:   # 精二：浪里一道酒红暗流（专属色），紧贴浪内侧
				var rc: Color = SK_R[3] if f < 3 else SK_R[2]
				_sk_ring(cv, c, R - (w * 0.5 + 1.5) * px, 7, 2.0, rc, SK_R[4], Color(0, 0, 0, 0), seed + 5.0, seed * 0.37 + 0.2, 0.7)
			if f <= 1:
				var ne: int = clampi(int(R / (px * 3.0)), 16, 64)   # docs/270：浪头白热整圈进发光层（约每 16 世界像素一点）
				for j in ne:
					_glow(_sk_ep(c, R, seed + TAU * float(j) / float(ne)), C[6])
		"echo_ring":   # 余音：歌域外圈一道酒红细环闪 3 拍
			if f < 0 or f > 3:
				return
			var col2: Color = SK_R[4] if f < 2 else SK_R[3]
			col2.a = [0.9, 0.8, 0.5, 0.25][f]
			_sk_ring(cv, c, float(it.r) * _sk_rk(it) * 0.95, 9, 2.0, col2, SK_R[5] if f == 0 else Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(int(it.t0 * 5.0) % 31), 0.3)
		"mini", "splash":   # 小声浪 / 溅射环
			var nb: int = 4 if str(it.skr) == "mini" else 3
			if f < 0 or f >= nb:
				return
			var R2: float = float(it.r) * [0.5, 0.8, 1.0, 1.05][f]
			var col3: Color = SK_B[5] if f == 0 else SK_B[4]
			col3.a = [1.0, 0.85, 0.5, 0.3][f]
			_sk_ring(cv, c, R2, 5, 2.0 if f < 2 else 1.0, col3, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(int(it.t0 * 9.0) % 41), 0.0, 0.75)
		"burst":   # 深海的回响：酒红小爆环 + 实心亮芯一拍
			if f < 0 or f > 4:
				return
			var R3: float = float(it.r) * [0.35, 0.7, 0.9, 1.0, 1.05][f]
			var col4: Color = SK_R[5] if f == 0 else SK_R[4]
			col4.a = [1.0, 1.0, 0.8, 0.5, 0.25][f]
			_sk_ring(cv, c, R3, 6, 3.0 if f < 2 else 2.0, col4, SK_R[6] if f < 2 else Color(0, 0, 0, 0), SK_R[2], float(int(it.t0 * 3.0) % 23), 0.5)
			if f <= 1:
				_sk_grad(cv, c, 0.0, R3 * 0.6, SK_R[4], 0.55, 0.2)
		"vortex":   # S2 起手旋涡：3 / 5 条旋臂笔触从脚下卷开再淡
			if f < 0 or f > 11:
				return
			var t2: int = int(it.tier)
			var arms: int = 3 if t2 < 2 else 5
			var Rv: float = 130.0 * [0.4, 0.6, 0.75, 0.85, 0.92, 0.97, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0][f]
			var al: float = 1.0 if f < 7 else (1.0 - float(f - 6) / 6.0)
			for j in arms:
				var base: float = TAU * float(j) / float(arms) + float(f) * 0.35
				for s in 3:   # 每条旋臂三节，越往外越靠后（旋）
					var rr: float = Rv * (0.35 + 0.25 * float(s))
					var cl: Color = [SK_B[5], SK_B[4], SK_B[3]][s]
					cl.a = al * [1.0, 0.9, 0.75][s]
					_sk_arc(cv, c, rr, base + 0.55 * float(s), base + 0.55 * float(s) + 1.0, [4.0, 4.0, 3.0][s] + (1.0 if t2 >= 2 else 0.0), cl, SK_B[6] if s == 0 and f < 4 else Color(0, 0, 0, 0), SK_B[1], float(j) * 3.0 + float(s))
			_sk_grad(cv, c, 0.0, Rv * 0.5, SK_B[2], 0.35 * al, 0.0)
		"surge":   # S3 潮涌：粗笔触亮蓝环扩到歌域边 + 深蓝内影 + 内部实心渐变 + 8 道旋转笔触线
			if f < 0 or f > 6:
				return
			var Rs: float = float(it.r) * _sk_rk(it) * [0.6, 0.78, 0.9, 0.97, 1.0, 1.0, 1.0][f]
			var fa2: float = [1.0, 1.0, 1.0, 0.9, 0.75, 0.5, 0.25][f]
			if Bal.v("fx/px_plane_sk_fill", 1.0) <= 0.0:   # 0 = 旧版平滑渐变（对照用）
				var fill_k: float = [1.0, 0.9, 0.7, 0.45, 0.2, 0.0, 0.0][f]
				_sk_grad(cv, c, 0.0, Rs * 0.98, SK_B[2], 0.35 * fill_k, 0.5 * fill_k)
			else:
				_sk_surge_fill(cv, c, Rs, f)
			var nl: int = 8
			for j in nl:   # 旋转向心笔触线
				var a0: float = TAU * float(j) / float(nl) + float(f) * 0.32
				var lc: Color = SK_B[5] if f < 3 else SK_B[4]
				lc.a = fa2 * 0.9
				for s in 2:
					var rr2: float = Rs * (0.42 + 0.26 * float(s))
					_sk_arc(cv, c, rr2, a0 + 0.35 * float(s), a0 + 0.35 * float(s) + 0.55, 2.0, lc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j) + float(s) * 5.0)
			var mc: Color = SK_B[6] if f == 0 else (SK_B[5] if f <= 2 else SK_B[4])
			mc.a = fa2
			var w8: float = 8.0 * [1.0, 1.0, 0.95, 0.85, 0.7, 0.55, 0.4][f]
			_sk_ring(cv, c, Rs, 6, w8, mc, SK_B[6], Color(SK_B[1].r, SK_B[1].g, SK_B[1].b, fa2), 17.0, float(f) * 0.12, 0.9)
			if f <= 2:
				for j in 10:
					_glow(_sk_ep(c, Rs, TAU * float(j) / 10.0 + 0.3), SK_B[6])
		"song":   # 连携 v2「歌声」区域：4 段粗笔触 + 3 段酒红内圈（反向）+ 贴边渐变，3 秒，最后 0.4 秒淡
			var age: float = g.t - float(it.t0)
			var fa3: float = 1.0 if age < 2.6 else clampf((3.0 - age) / 0.4, 0.0, 1.0)
			var bt: float = float(_sk_beat()) / 15.0
			var Rg: float = float(it.r)
			var mcol: Color = SK_B[4]
			mcol.a = 0.95 * fa3
			for j in 4:
				var a0: float = bt * 0.35 + TAU * float(j) / 4.0
				_sk_arc(cv, c, Rg, a0, a0 + 1.05, 5.0, mcol, Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, fa3), Color(SK_B[1].r, SK_B[1].g, SK_B[1].b, fa3), 21.0 + float(j))
			var rcol: Color = SK_R[3]
			rcol.a = 0.9 * fa3
			for j in 3:
				var a0: float = -bt * 0.5 + TAU * float(j) / 3.0
				_sk_arc(cv, c, Rg * 0.82, a0, a0 + 1.2, 2.0, rcol, Color(SK_R[4].r, SK_R[4].g, SK_R[4].b, fa3), Color(0, 0, 0, 0), 31.0 + float(j))
			_sk_grad(cv, c, Rg - px * 14.0, Rg, SK_B[3], 0.0, 0.16 * fa3)


## S3 潮涌内部（11-05 用户「内部需要渐变填充或者别的填充方法吗」→ 试分阶色带）：贴着潮涌环往里 3 圈硬边色带
## （深 → 中 → 暗，每圈一个颜色、一个透明度，按颜色阶跳，不做平滑过渡），靠里 40% 不填（站人处清楚）；
## 色带里一层水纹：短亮线随节拍转（按固定散列成团，不抖动）；收的时候色带从外往里一段段断开，不整片淡出
func _sk_surge_fill(cv, c: Vector2, Rs: float, f: int) -> void:
	if f > 5:
		return
	var px: float = g.PX
	var cover: float = [1.0, 1.0, 1.0, 0.8, 0.55, 0.3][f]
	var widths: Array = [9.0, 9.0, 12.0]   # 美术像素
	var cols: Array = [SK_B[3], SK_B[2], SK_B[1]]
	var alps: Array = [0.5, 0.42, 0.34]
	var r: float = Rs - 4.0 * px   # 从潮涌环的内影往里
	for k in 3:
		var w: float = float(widths[k])
		var rc: float = r - w * px * 0.5
		var col: Color = cols[k]
		col.a = float(alps[k]) * (1.0 if f < 4 else 0.8)
		var kc: float = cover * (1.0 if k == 0 else (0.92 if k == 1 else 0.85)) if f >= 3 else 1.0
		if kc >= 0.999:
			_sk_grad(cv, c, rc - w * px * 0.5, rc + w * px * 0.5, col, col.a, col.a)
		else:   # 断开：每圈 10 段，覆盖率按拍降，外圈先断
			var nseg: int = 10
			for j in nseg:
				var a0: float = TAU * (float(j) + 0.3 * _sk_h(j + k * 13, 2.0)) / float(nseg) + 0.2 * float(k)
				var a1: float = a0 + TAU / float(nseg) * kc * (0.75 + 0.25 * _sk_h(j + 5, float(k)))
				_sk_arc(cv, c, rc, a0, a1, w, col, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j + k * 10), false)
		r -= w * px
		if r < Rs * 0.42:
			break
	# 水纹：色带里 14 道短亮线，按拍转、成团分布
	if f <= 4:
		var gc: Color = SK_B[5] if f <= 1 else SK_B[4]
		gc.a = [0.95, 0.9, 0.8, 0.6, 0.35][f]
		for j in 14:
			var rr: float = Rs * (0.5 + 0.42 * _sk_h(j, 7.0))
			var a0: float = TAU * _sk_h(j + 20, 7.0) + float(f) * (0.22 if j % 2 == 0 else -0.16)
			var ln: float = (6.0 + 8.0 * _sk_h(j + 40, 7.0)) * px / maxf(rr, 1.0)
			_sk_arc(cv, c, rr, a0, a0 + ln, 1.0, gc, Color(0, 0, 0, 0), Color(0, 0, 0, 0), float(j) + 90.0)


## 立起层（排序项 kind 7）
func _sk_draw_up(ci, it: Dictionary) -> void:
	var f: int = frame_of(float(it.t0))
	var px: float = g.PX
	var c: Vector2 = _sk_c(it)
	match str(it.skr):
		"note":   # 命中音符：第 0 拍白头，往上飘 9 拍，最后两拍只剩符头
			if f < 0 or f > 8:
				return
			var t: int = int(it.tier)
			var rose: bool = it.get("rose", false)
			var pat: Array = SK_NOTE2 if t >= 2 else SK_NOTE
			var C: Array = SK_T if rose else SK_R   # 酒红音符：敌人多是白 / 蓝，压在上面读得出来；海嗣的音符用海嗣青
			var col: Color = C[5] if f < 3 else C[4]
			var head: Color = C[6] if f == 0 else (C[5] if f < 4 else C[4])
			if f >= 7:
				col.a = 0.0
				head.a = 0.6
			var up: float = float(f) * px * (1.0 if f < 5 else 0.6)
			var w: float = float((pat[0] as String).length()) * px
			var shc: Color = C[0]
			shc.a = 0.85 if f < 7 else 0.0
			_sk_pat(ci, pat, c + Vector2(-w * 0.5 + (10.0 if it.get("fl", false) else -10.0), -float(pat.size()) * px - up - 8.0), col, head, it.get("fl", false), shc)
			if f <= 1 and it.has("hp"):   # 命中点白芯（音符的「起音」）：十字 5 格 + 外圈 4 格浅色，头两拍，整块进发光层（docs/270：命中帧核心辉光）
				var hc: Vector2 = _snap(it.hp)
				for dq in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
					var core: bool = absf(dq.x) + absf(dq.y) <= 1.0
					if f == 1 and not core:
						continue
					ci.draw_rect(Rect2(hc + dq * px, Vector2(px, px)), C[6] if core else C[5])
					_glow(hc + dq * px, C[6])
			if f <= 1:
				var tl: Vector2 = _snap(c + Vector2(-w * 0.5 + (10.0 if it.get("fl", false) else -10.0), -float(pat.size()) * px - up - 8.0))
				for y in pat.size():   # 命中头两拍：整枚音符进发光层（docs/270：命中帧核心辉光）
					var row: String = pat[y]
					for x in row.length():
						if row[x] == "#":
							_glow(tl + Vector2(float(x), float(y)) * px, C[6] if y >= pat.size() - 2 else C[5])
		"buff":   # 增益标记：吃到增益的干员头顶一枚双箭头，往上飘 8 拍（S1 蓝、S3 酒红），跟着那名干员走
			if f < 0 or f > 7:
				return
			var q2 = it.get("tgt", null)
			var bp: Vector2 = c
			if q2 != null and is_instance_valid(q2) and q2.pos != Vector2.INF:
				bp = q2.pos
			var Cb: Array = SK_R if it.get("s3", false) else SK_B
			var colb: Color = Cb[5] if f < 4 else Cb[4]
			colb.a = 1.0 if f < 6 else 0.5
			var tlb: Vector2 = bp + Vector2(-5.0 * px * 0.5, -58.0 - float(f) * px)
			_sk_pat(ci, SK_UP, tlb, colb, Cb[6] if f < 2 else colb, false, Color(Cb[0].r, Cb[0].g, Cb[0].b, 0.7))
			if f <= 1:
				_glow(tlb + Vector2(2.0 * px, 0.0), Cb[6])
		"pop":   # 命中点白芯：十字 5 格 + 外圈 4 格浅色（第 1 拍只剩十字），整块进发光层
			if f < 0 or f > 1:
				return
			var Cp: Array = SK_T if it.get("sea", false) else SK_B
			var hcp: Vector2 = _snap(c)
			for dq in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(2, 0), Vector2(-2, 0), Vector2(0, 2), Vector2(0, -2)]:
				var core2: bool = absf(dq.x) + absf(dq.y) <= 1.0
				if f == 1 and not core2:
					continue
				ci.draw_rect(Rect2(hcp + dq * px, Vector2(px, px)), Cp[6] if core2 else Cp[5])
				_glow(hcp + dq * px, Cp[6])
		"pillars":   # S3 潮涌：5 根粗亮红竖光柱从歌域里冲起又回落（原作 skill_03_buff_02 的红光柱）；白热芯、亮红身、暗酒红边，顶端淡出
			if f < 0 or f > 6:
				return
			var Rr: float = float(it.r) * _sk_rk(it)
			var H: float = 80.0 * px * [0.55, 1.0, 1.0, 0.95, 0.85, 0.7, 0.5][f]
			var W: int = [11, 15, 15, 13, 11, 7, 4][f]
			for j in 5:
				var a: float = TAU * float(j) / 5.0 + 0.6 + 0.2 * _sk_h(j, float(it.t0))
				var foot: Vector2 = _snap(_sk_ep(c, Rr * (0.28 + 0.22 * _sk_h(j + 3, 1.0)), a))   # 围在她身边冲起（原作光柱贴着人）
				var hj: float = H * (0.8 + 0.35 * _sk_h(j + 9, 2.0))
				_sk_pillar(ci, foot, W, hj, f)
		"fishburst":   # S2 起手：小鱼从脚下沿旋涡散开
			if f < 0 or f > 11:
				return
			var t2: int = int(it.tier)
			var n: int = 3 if t2 < 2 else 5
			for j in n:
				var a: float = TAU * float(j) / float(n) + float(f) * 0.3
				var rr: float = (12.0 + 7.0 * float(f)) * px
				var q: Vector2 = _sk_ep(c, rr, a) + Vector2(0, -10.0 - 1.5 * float(f))
				var fl: bool = cos(a + PI * 0.5) < 0.0
				_sk_pat(ci, SK_FISH, q, SK_R[3], SK_R[4], fl, Color(SK_R[0].r, SK_R[0].g, SK_R[0].b, 0.8))
		"spout":   # S2 精二：涡眼冲起一道水柱
			if f < 0 or f > 7:
				return
			var Hs: float = 52.0 * px * [0.4, 0.8, 1.0, 1.0, 0.9, 0.75, 0.55, 0.35][f]
			_sk_column(ci, _snap(c), [4, 5, 5, 5, 4, 4, 3, 2][f], Hs, SK_B, f)
		"songnotes":   # 连携 v2：区域里每 0.5 秒冒 3 个音符往上飘
			var age: float = g.t - float(it.t0)
			if age > 3.0:
				return
			var Rg: float = float(it.r)
			for k in 3:
				var wave: int = int(age * 2.0)
				var u: float = fposmod(age * 2.0, 1.0)
				var a: float = TAU * (float(k) / 3.0 + 0.37 * float(wave))
				var q: Vector2 = _sk_ep(c, Rg * (0.35 + 0.4 * _sk_h(k + wave * 3, 4.0)), a)
				var fb: int = int(u * 7.5)
				var colN: Color = (SK_R if k == 1 else SK_B)[5]
				var headN: Color = (SK_R if k == 1 else SK_B)[6 if fb == 0 else 5]
				if fb >= 6:
					colN.a = 0.0
				_sk_pat(ci, SK_NOTE, q + Vector2(-8.0, -30.0 - float(fb) * px), colN, headN, k == 2, Color(SK_B[0].r, SK_B[0].g, SK_B[0].b, 0.0 if fb >= 6 else 0.8))


## 红光柱：宽 W 美术像素、高 H 世界像素；脚下一小片亮红地光
func _sk_pillar(ci, foot: Vector2, W: int, H: float, f: int) -> void:
	var px: float = g.PX
	var x0: float = foot.x - float(W / 2) * px
	var steps: int = maxi(1, int(H / (px * 4.0)))
	for s in steps:   # 自下而上 4 美术像素一段，顶端三段淡出
		var y: float = foot.y - float(s + 1) * px * 4.0
		var top_k: float = 1.0 - clampf(float(s - (steps - 3)) / 3.0, 0.0, 1.0) * 0.85 if steps > 3 else 1.0
		for x in W:
			var dx: int = absi(x - W / 2)
			var edge: bool = x == 0 or x == W - 1
			var halo: bool = not edge and dx >= W / 2 - 2 and W >= 9
			var core: bool = W >= 5 and dx <= maxi(0, W / 5)
			var col: Color = SK_R[2] if edge else (SK_R[3] if halo else (SK_R[6] if core and f <= 2 else (SK_R[5] if core else SK_R[4])))
			col.a = top_k * (0.45 if edge else (0.75 if halo else 1.0))
			ci.draw_rect(Rect2(Vector2(x0 + float(x) * px, y), Vector2(px, px * 4.0)), col)
		if s % 2 == 0 and f <= 3:
			_glow(Vector2(foot.x, y), SK_R[5])
	var fc: Color = SK_R[4]
	fc.a = 0.6
	ci.draw_rect(Rect2(_snap(foot + Vector2(-float(W) * px, -px)), Vector2(float(W) * 2.0 * px, px * 2.0)), fc)


## 水柱（S2 涡眼）：同红光柱的画法，蓝色
func _sk_column(ci, foot: Vector2, W: int, H: float, C: Array, f: int) -> void:
	var px: float = g.PX
	var x0: float = foot.x - float(W / 2) * px
	var steps: int = maxi(1, int(H / (px * 3.0)))
	for s in steps:
		var y: float = foot.y - float(s + 1) * px * 3.0
		var top_k: float = 1.0 if s < steps - 2 else 0.55
		for x in W:
			var edge: bool = x == 0 or x == W - 1
			var col: Color = C[3] if edge else (C[6] if f <= 1 and x == W / 2 else C[5])
			col.a = top_k
			ci.draw_rect(Rect2(Vector2(x0 + float(x) * px, y), Vector2(px, px * 3.0)), col)


## 立起层的状态件：S1 身周气泡、S2 常驻小鱼
func _sk_sort_items(o, out: Array) -> void:
	var t: int = tier(o)
	if o.skill_active_left(0) > 0.0 and o.B.has("zone"):
		out.append({"skr_s": "bubble", "o": o, "gy": o.zone_c().y + 3.0})   # 气泡罩在歌域圆心 = 队长身上
	var s2on: bool = o.get("perm_on") != null and bool(o.perm_on[1])
	if s2on and o.B.has("zone"):
		out.append({"skr_s": "fish", "o": o, "gy": o.zone_c().y + 1.0})


func _sk_draw_state_up(ci, it: Dictionary) -> void:
	var o = it.o
	var t: int = tier(o)
	var px: float = g.PX
	var bt: int = _sk_beat()
	match str(it.skr_s):
		"bubble":   # S1：身周一团气泡（细膜 + 左上高光 + 淡淡的水 0.16）；E1 双层膜、E2 三团（主泡两侧各连一个小泡）
			var zc0: Vector2 = o.zone_c()
			var c: Vector2 = _snap(zc0 + Vector2(0, -26))
			var wob: float = [0.0, 1.0, 0.0, -1.0][bt % 4] * px
			var Rb: float = (23.0 if t == 0 else 26.0) * px
			var bubs: Array = [[c, Rb + wob]]
			if t >= 2:
				bubs.append([_snap(c + Vector2(-Rb * 1.05, Rb * 0.45)), Rb * 0.42 - wob * 0.5])
				bubs.append([_snap(c + Vector2(Rb * 1.0, Rb * 0.55)), Rb * 0.36 + wob * 0.5])
			for b in bubs:
				var bc: Vector2 = b[0]
				var br: float = b[1]
				ci.draw_circle(bc, br, Color(SK_B[3].r, SK_B[3].g, SK_B[3].b, 0.16))
				ci.draw_arc(bc, br, 0.0, TAU, clampi(int(br / 2.0), 12, 40), Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, 0.9), px)
				ci.draw_arc(bc, br - px * 2.0, PI * 1.05, PI * 1.45, 8, SK_B[6], px)   # 左上高光
				if t >= 1 and br > Rb * 0.6:
					ci.draw_arc(bc, br - px * 3.0, PI * 0.1, PI * 0.9, 14, Color(SK_B[4].r, SK_B[4].g, SK_B[4].b, 0.6), px)   # 精一：第二层膜（下半）
			for q in 10:   # 气泡左上高光弧进发光层（docs/270：持续类核心辉光）
				var aq: float = PI * (1.05 + 0.04 * float(q))
				_glow(c + Vector2(cos(aq), sin(aq)) * (Rb - px * 2.0), SK_B[6])
			# 脚下酒红细环（贴地，跟在立起件里画：它跟着气泡走、本来就在她脚下）
			var fr := PackedVector2Array()
			for k in 25:
				fr.append(_snap(_sk_ep(zc0 + Vector2(0, 2), 20.0 * px, TAU * float(k) / 24.0)))
			ci.draw_polyline(fr, Color(SK_R[3].r, SK_R[3].g, SK_R[3].b, 0.85), px)
			if t >= 1:   # 精一：外面再一圈酒红细环
				var fr2 := PackedVector2Array()
				for k in 25:
					fr2.append(_snap(_sk_ep(zc0 + Vector2(0, 2), 26.0 * px, TAU * float(k) / 24.0 + 0.1)))
				ci.draw_polyline(fr2, Color(SK_R[2].r, SK_R[2].g, SK_R[2].b, 0.7), px)
			# 上浮小泡：每拍错落 3–5 个
			var nb: int = 3 + t
			for k in nb:
				var ph: int = (bt + k * 5) % 15
				var bx: float = (_sk_h(k, 3.0) - 0.5) * Rb * 1.6
				var q: Vector2 = _snap(c + Vector2(bx, Rb * 0.6 - float(ph) * px * 2.0))
				ci.draw_rect(Rect2(q, Vector2(px, px)), Color(SK_B[5].r, SK_B[5].g, SK_B[5].b, 0.9 if ph < 10 else 0.4))
		"fish":   # S2 常驻：酒红小鱼绕歌域边慢慢游（E1 3 条 / E2 5 条）
			var zc: Vector2 = o.zone_c()
			var zv: float = _sk_r(o, "self", float(o.zr))
			var n: int = 3 if t < 2 else 5
			for j in n:
				var a: float = TAU * float(j) / float(n) + float(bt) / 15.0 * 0.22 * (1.0 if j % 2 == 0 else 0.8)
				var q: Vector2 = _sk_ep(zc, zv * (0.9 + 0.06 * _sk_h(j, 6.0)), a) + Vector2(-7.0, -16.0 - px * float((bt + j * 4) % 6 / 3))
				var fl: bool = sin(a) > 0.0   # 顺时针游：上半圈朝右、下半圈朝左
				_sk_pat(ci, SK_FISH, q, Color(SK_R[3].r, SK_R[3].g, SK_R[3].b, 0.9), SK_R[4], fl, Color(SK_R[0].r, SK_R[0].g, SK_R[0].b, 0.7))


## 旧做法（2）：整张贴（光晕烤进颜色，按歌域半径小数缩放、盖在所有单位上）；S1 / S3 期间按技能剩余时间循环
func _sk_draw_raw(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	var rf: float = Bal.v("fx/px_plane_raw_fps", 12.8)
	for it in items:
		if str(it.ly) != "raw" or str(it.oid) != id:
			continue
		_draw_raw(cv, str(it.k), int((g.t - float(it.t0)) * rf), it.gp, float(it.rot), float(it.sc))
## 锤击落点亮芯：白闪那三拍（0.2 秒）在落点排一块十字形发光点（中心 4×4 美术像素、四臂各 1 格；号令一锤 / 碎颅大一圈），之后每拍缩一格、变暗
func _sg_draw_cores() -> void:
	if _sg_cores.is_empty() or not g.optical_on:
		return
	var fr: int = Engine.get_process_frames()
	if fr != _emit_frame:   # 同 _emit：每帧重新计数（整队共用 EMIT_CAP）
		_emit_frame = fr
		_emit_n = 0
	var px: float = g.PX
	var k: float = Bal.v("fx/px_plane_emit", 0.8)
	var keep: Array = []
	for c in _sg_cores:
		var age: float = g.t - float(c.t0)
		if age > 0.2:
			continue
		keep.append(c)
		var f2: bool = age > 0.067
		var s: float = (4.0 if not c.big else 5.0) - (1.0 if f2 else 0.0) - (1.0 if age > 0.134 else 0.0)
		var col: Color = Color(1.0, 0.97, 0.85, minf(1.0, k * 1.2)) if not f2 else Color(1.0, 0.88, 0.55, k)
		var at: Vector2 = c.at
		var pts: Array = [[at - Vector2(s, s) * px * 0.5, s * px]]
		for dv in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			pts.append([_snap(at + dv * (s * 0.5 + 0.5 + (1.0 if c.big else 0.0)) * px) - Vector2(px, px) * 0.5, px])
		for q in pts:
			if _emit_n >= EMIT_CAP:
				break
			_emit_n += 1
			g.glow_next.append([q[0], q[1], col])
	_sg_cores = keep

# ================================================================ 德克萨斯（docs/257，照 docs/246 斯卡蒂 / docs/254 星熊的做法）
## 普攻「拔刀」= 腰高琥珀刀痕，两头针尖（精一刀头甩碎晶 + 钉剑，精二白刃内侧冷青刃光）；骤雨 / 回马剑 = 整道约 300° 旋斩；
## S1「剑雨」= 源石剑从天而降、插地、刃光沿刃走一趟、碎成碎晶（精一更多更大，精二再大一号 + 收尾中心巨剑 + 地面剑阵）；
## S2「冲锋号令·γ型」= 起手琥珀光柱，之后所有冲刺的直线刀光加粗（精二带冷青刃光点）；
## S3「剑雨滂沱」= 起手身边一圈落剑 + 剑阵；次元斩每刀一道腰高细长直线刀痕 + 目标处落一柄大剑；
## 精二余像 = 地上两道残像边线，消散时沿路落剑；后期剑气 = 飞出去的源石剑（同一次出手合成一柄），沿路落小剑；
## 连携（追击 / 冲刺斩）= 冲刺直线刀光 + 目标处十字斩。
## 帧条键前缀 tx_（data/pxp_texas.json，tools/pxplane_bake.py --op texas）；直线刀光按美术像素格运行时逐格画（方向任意，不旋转贴图）。

const TX_C: Array[Color] = [Color("#120804"), Color("#2c1406"), Color("#5a2808"), Color("#9c4610"), Color("#e2781c"), Color("#ffac3c"), Color("#ffdc9c"), Color("#ffffff")]
const TX_AC := Color("#9fe3ff")
const TX_H := 24.0                       # 腰高（世界像素）：直线刀光离地高度
const TX_RAIN_CAP := [10, 13, 16]        # 剑雨同一次至多画几柄（三档）；其余照常结算，只是不画
const TX_SW := [[16, 0], [19, 1], [22, 2]]   # 剑雨三档的剑：[剑长, 档]

var _tx_spin := 0
var _txq: Array = []                     # 画面延时事件：[时刻, 种类, 数据]（落剑落地那一下的碎晶 / 照地光）


func _ev_tx(o, kind: String, d: Dictionary, raw: bool, t: int, R, p: Dictionary) -> void:
	if Bal.v("fx/recipe_log", 0.0) > 0.0:   # 看图对齐用（tools/pxplane_shots.py）：事件的游戏时间
		print("PXPLOG tx %s %s %.3f" % [kind, str(d.get("src", d.get("i", ""))), g.t])
	match kind:
		"shape":
			var src: String = str(d.get("src", ""))
			var es: Array = d.get("es", [])
			if d.get("circle", false):
				var c: Vector2 = d.get("c", o.pos)
				var r: float = float(d.get("r", 100.0))
				match src:
					"骤雨", "回马剑":   # 360° 旋斩（骤雨连斩 4 下左右交替）
						_tx_spin += 1
						var sk: String = "tx_spin_r%d_e%d" % [_bucket(r * 0.5, [50, 56, 63]), t]
						if raw:
							_push({"k": "tx_raw_spin_e%d" % t, "t0": g.t, "gp": c + Vector2(0, -10), "ly": "raw", "rot": float(_tx_spin) * 1.3, "sc": g.PX * (r * 0.5) / 50.0, "oid": str(o.id)})
						else:
							var fl: bool = (_tx_spin % 2) == 1
							_push({"k": sk + "_up", "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
							_push({"k": sk + "_gd", "t0": g.t, "gp": _snap(c), "flip": fl, "ly": "gd", "oid": str(o.id), "fo": Vector2.ZERO})
						_tx_cuts(o, es, t, 2)
						_tx_hit(o, R, c + Vector2(0, -16), c.y + 2.0, es, 2 + t, 120.0, 0.5)   # docs/270：同拔刀，灯强度提到 0.5
					_:
						pass   # 剑雨 / 余像·剑雨的判定圈：画面由落剑（tx_rain 事件）画，不逐圈画
				return
			# 锥形：拔刀（普攻）
			var ang: float = float(d.get("ang", 0.0))
			var r2: float = float(d.get("r", 112.0))
			var dv := Vector2.from_angle(ang)
			_add(o, "tx_slash_r%d_e%d" % [_bucket(r2 * 0.5, [56, 63, 70]), t], o.pos, ang, r2, raw, "tx_raw_slash_e%d" % t, 56.0)
			_tx_cuts(o, es, t, 2)
			_tx_hit(o, R, o.pos + dv * r2 * 0.6 + Vector2(0, -14), o.pos.y + dv.y * r2 * 0.6 * 0.72, es, 2 + t, 110.0, 0.5)   # docs/270：普攻灯强度 0.3（全员最暗）→ 0.5
			if t >= 1 and not raw and mode() == 1:   # 精一钉剑：命中里离她最近的 2 名（非 Boss）各插一柄源石剑，跟着敌人，0.7 秒后碎掉
				var lst: Array = es.filter(func(x): return not x.boss and not x.dead)
				lst.sort_custom(func(x1, x2): return x1.pos.distance_squared_to(o.pos) < x2.pos.distance_squared_to(o.pos))
				for i in mini(2, lst.size()):
					var pe: Dictionary = lst[i]
					_push({"k": "tx_pin_h%d_e%d_up" % [15 if float(pe.r) >= 22.0 else 9, mini(t, 2)], "t0": g.t, "gp": _snap(pe.pos), "fe": pe, "flip": (pe.pos.x < o.pos.x), "ly": "up", "oid": str(o.id)})
		"tx_rain":   # verb.fx_rain（剑雨 / 剑雨·连 / 剑雨·连绵 / 余像·剑雨）：落剑清单由玩法画面那份（g.vrng）给出
			var bl: Array = d.get("bl", [])
			if bl.is_empty():
				return
			var path: bool = d.get("path", false)
			var sw: Array = [14, 2] if path else TX_SW[t]
			var cap: int = 12 if path else TX_RAIN_CAP[t]
			var lst2: Array = bl.slice(0, cap)
			var ft: float = float(d.get("ft", 0.1))
			var cc: Vector2 = d.get("c", o.pos)
			_tx_rain(o, lst2, "tx_sw_s%d_e%d" % [sw[0], sw[1]], raw, t)
			if not path:
				if t >= 2 and not d.get("echo", false):   # 精二收尾：中心一柄巨剑 + 地面剑阵（质变）
					var tm := 0.0
					for b in lst2:
						tm = maxf(tm, float(b.d))
					var fin_d: float = tm + 0.12
					_tx_rain(o, [{"p": cc, "d": fin_d, "a": 0.0, "fl": false}], "tx_sw_s40_e2", raw, t)
					if not raw:
						_push({"k": "tx_array_r65_gd", "t0": _tx_beat(g.t + fin_d, 2), "gp": _snap(cc), "flip": false, "ly": "gd", "oid": str(o.id)})   # 剑阵热白第一拍 = 巨剑插地那一拍 = 中心灯（docs/270：灯与辉光同帧）
					if mode() == 1:
						_txq.append([_tx_beat(g.t + fin_d, 2), "land", {"o": o, "p": cc, "n": 8, "lr": 220.0, "li": 0.8}])
				if mode() == 1:   # 剑雨中心那盏灯跟第一柄剑插地同一拍亮（docs/270：灯与辉光同帧）
					_txq.append([_tx_beat(g.t, 2), "lt", {"o": o, "p": cc + Vector2(0, -20), "lr": 180.0, "li": 0.6}])
		"tx_dash":   # 冲刺（拔刀冲刺 / 战术快递 / 突进 / 冲刺斩）：腰高直线刀光 + 地上焦痕；S2 永久生效后加粗
			var a0: Vector2 = d.get("from", o.pos)
			var b0: Vector2 = d.get("to", o.pos)
			var s2: bool = t >= 1 and o.perm.size() > 1 and o.perm[1]
			_tx_line(o, a0, b0, 2 if s2 else 1, 1, 1 if s2 else 0, raw, true)
			if mode() == 1:
				R._light(o, b0 + Vector2(0, -20), 120.0, 0.35, 0.1, p.light)
		"tx_trail":   # 精二余像：地上两道残像边线，life 秒内淡掉（消散时的落剑走 tx_rain path）
			if not raw:
				_push({"tr": true, "a": d.get("from", o.pos), "b": d.get("to", o.pos), "w": float(d.get("w", 44.0)), "t0": g.t, "life": float(d.get("life", 0.6)), "ly": "gd2", "oid": str(o.id), "k": ""})
		"tx_scar":   # 次元斩：一道腰高细长直线刀痕（判定线两端外延），scar 秒后碎开
			var hold: int = maxi(1, int(round(float(d.get("life", 0.22)) * 15.0)))
			if d.get("one", false):   # 一刀一道（fx/texas_s3_single_slash；11-06 用户「不要太粗，但是要亮」）：芯 2 格（末刀 3 格）近白 + 两侧一格淡琥珀，命中两拍过曝白 + 每格辉光，到点一拍断掉
				_tx_line(o, d.get("a", o.pos), d.get("c", o.pos), 3 if float(d.get("wmax", 4.0)) >= 5.0 else 2, hold, 3, raw, false)
			else:
				_tx_line(o, d.get("a", o.pos), d.get("c", o.pos), 2 if float(d.get("wmax", 2.0)) >= 3.0 else 1, hold, 2, raw, false)
		"tx_cut":   # 次元斩每一刀：目标处落一柄大剑（剑雨滂沱）
			var at: Vector2 = d.get("at", o.pos)
			if d.get("one", false):   # 一刀一道：不落剑（读起来像又一击），命中点一簇火星 + 沿刀线两头各几颗碎屑 + 照地光
				_burst_m(o, R, p, at + Vector2(0, -20), at.y + 2.0, [], 10 if d.get("last", false) else 7, "shard", 170.0, 0.7)
				if mode() == 1:   # 命中两拍：刀线中段再一盏亮照地光（和白芯辉光同一帧挂）
					_txq.append([g.t, "lt", {"o": o, "p": at + Vector2(0, -TX_H), "lr": 200.0, "li": 0.9}])
				if mode() == 1:
					var ca: Vector2 = d.get("a", at)
					var cc2: Vector2 = d.get("c", at)
					for q in [ca.lerp(cc2, 0.25), ca.lerp(cc2, 0.75)]:
						R._grains(o, q + Vector2(0, -TX_H), q.y + 2.0, "shard", 2, {"tier": 2}, (cc2 - ca).normalized())
				return
			_tx_rain(o, [{"p": at, "d": 0.0, "a": 0.0, "fl": (int(g.t * 15.0) % 2) == 0}], "tx_sw_s26_e2", raw, 2)
			_burst_m(o, R, p, at + Vector2(0, -20), at.y + 2.0, [], 4, "shard", 130.0, 0.45)
		"tx_link":   # 连携（技能连携 v2「追击」/ combo「冲刺斩」）：粗直线刀光 + 目标处十字斩
			var fa: Vector2 = d.get("from", o.pos)
			var tb: Vector2 = d.get("to", o.pos)
			var mid: Vector2 = d.get("mid", tb)
			var dv2: Vector2 = (tb - fa).normalized() if tb != fa else Vector2.RIGHT
			_tx_line(o, fa, tb, 2, 2, 1, raw, true)
			if raw:
				_push({"k": "tx_raw_xcut", "t0": g.t, "gp": mid + Vector2(0, -24), "ly": "raw", "rot": dv2.angle(), "sc": g.PX * 1.37, "oid": str(o.id)})
			else:
				var dk: Array = pick_dir(dv2.angle())
				_push({"k": "tx_xcut_up_d%d" % dk[0], "t0": g.t, "gp": _snap(mid), "flip": dk[1], "ly": "up", "oid": str(o.id)})
				_push({"k": "tx_xcut_gd_d%d" % dk[0], "t0": g.t, "gp": _snap(mid), "flip": dk[1], "ly": "gd", "oid": str(o.id)})
			_tx_cuts(o, d.get("es", []), 1, 3)
			_burst_m(o, R, p, mid + Vector2(0, -20), mid.y + 2.0, d.get("es", []), 8, "shard", 200.0, 0.8)
		"skill":
			var i: int = int(d.get("i", -1))
			if i == 1:   # 冲锋号令·γ型起手：琥珀光柱 + 脚下断续环
				var tt: int = maxi(t, 1)
				if raw:
					_push({"k": "tx_raw_spin_e%d" % tt, "t0": g.t, "gp": o.pos + Vector2(0, -10), "ly": "raw", "rot": 0.0, "sc": g.PX * 0.6, "oid": str(o.id)})
				else:
					_push({"k": "tx_order_e%d_up" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": float(o.face) < 0.0, "ly": "up", "oid": str(o.id), "fo": Vector2.ZERO})
					_push({"k": "tx_order_e%d_gd" % tt, "t0": g.t, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id), "fo": Vector2.ZERO})
				if mode() == 1:
					R._grains(o, o.pos + Vector2(0, -30), o.pos.y, "shard", 5 + 2 * tt, {"tier": tt})
					R._light(o, o.pos + Vector2(0, -30), 140.0, 0.6, 0.15, p.light)
			elif i == 2:   # 剑雨滂沱起手：身边一圈 8 柄剑依次落下 + 剑阵
				var ring: Array = []
				for k in 8:
					var a: float = TAU * float(k) / 8.0 + 0.2
					ring.append({"p": o.pos + Vector2(cos(a), sin(a) * 0.72) * 104.0, "d": 0.035 * float(k), "a": 0.0, "fl": k % 2 == 1})
				_tx_rain(o, ring, "tx_sw_s22_e2", raw, 2)
				if not raw:
					_push({"k": "tx_array_r56_gd", "t0": g.t + 0.1, "gp": _snap(o.pos), "flip": false, "ly": "gd", "oid": str(o.id)})
				if mode() == 1:
					R._light(o, o.pos + Vector2(0, -20), 180.0, 0.6, 0.15, p.light)


## 命中：碎晶当场生成；照地灯推迟到这一帧的绘制里再挂（docs/270：灯和斩痕白芯的辉光同一帧亮——emit 点在绘制时排进发光层、下一帧才显出，
## 灯在玩法更新里挂会比辉光早一帧，体检取的命中帧上就量不到辉光）
func _tx_hit(o, R, at: Vector2, gy: float, es: Array, n: int, lr: float, li: float) -> void:
	if mode() != 1:
		return
	var m := {"tier": tier(o), "grain_spd": 1.0}
	var hp: Vector2 = at
	if not es.is_empty():
		var e: Dictionary = es[0]
		hp = e.pos + Vector2(0, -float(e.r) * 0.5)
		R._grains(o, hp, float(e.pos.y) + 2.0, "shard", mini(n, 2 + es.size()), m, (hp - o.pos).normalized())
	else:
		R._grains(o, at, gy, "shard", maxi(1, n / 2), m)
		lr *= 0.8
		li *= 0.6
	_txq.append([g.t, "lt", {"o": o, "p": hp, "lr": lr, "li": li}])


## 某一时刻起第 k 拍（15 fps 节拍）开始的时刻：帧条第 k 帧被画出来的那一拍
func _tx_beat(t0: float, k: int) -> float:
	return (floor(t0 * 15.0) + float(k)) / 15.0


## 斩痕（同斯卡蒂 _cuts，琥珀色）
func _tx_cuts(o, es: Array, t: int, n: int) -> void:
	var k0: int = items.size()
	_cuts(o, es, t, n)
	for i in range(maxi(0, k0 - n), items.size()):
		var it: Dictionary = items[i]
		if it.get("cut", false) and str(it.oid) == str(o.id):
			it["emk"] = true
			it["c1"] = "#ffdc9c"
			it["c2"] = "#ffac3c"
			it["c3"] = "#e2781c"


## 一组落剑：bl = [{p 落点, d 延时, a 倾角, fl 翻转}]；一条组件（ly rain），画时按每柄的出手时刻展开（sort_items / 地面层）
func _tx_rain(o, bl: Array, key: String, raw: bool, t: int) -> void:
	if bl.is_empty():
		return
	var lf: float = _life(key + "_l0_up")
	var tm := 0.0
	for b in bl:
		tm = maxf(tm, float(b.d))
	if raw:   # 旧做法：每柄一张旋转 + 小数缩放的整张贴图，盖在最上层
		for b in bl.slice(0, 10):
			_push({"k": "tx_raw_sword_e%d" % t, "t0": g.t + float(b.d), "gp": (b.p as Vector2) + Vector2(0, -24), "ly": "raw", "rot": float(b.a), "sc": g.PX * 1.37, "oid": str(o.id)})
		return
	_push({"rain": bl, "key": key, "t0": g.t, "life": tm + lf, "ly": "rain", "oid": str(o.id), "k": ""})
	if mode() == 1:   # 前三柄落地那一下：几颗碎晶 + 一盏短照地光
		for b in bl.slice(0, 3):
			_txq.append([_tx_beat(g.t + float(b.d), 2), "land", {"o": o, "p": b.p, "n": 3, "lr": 110.0, "li": 0.45}])


## 直线刀光（运行时逐格）：w 芯宽（格）、hold 保持几拍再碎、style 0 冲刺 / 1 加粗（号令 · 连携）/ 2 次元斩；gs = 地上留焦痕
func _tx_line(o, a: Vector2, b: Vector2, w: int, hold: int, style: int, raw: bool, gs: bool) -> void:
	if a.distance_to(b) < 4.0:
		return
	if raw:
		_push({"rawln": true, "a": a, "b": b, "t0": g.t, "life": 0.34, "ly": "rawln", "oid": str(o.id), "k": ""})
		return
	_push({"ln": true, "a": a, "b": b, "w": w, "hold": hold, "st": style, "gs": gs, "cold": tier(o) >= 2, "t0": g.t, "life": float(hold + 4) / 15.0, "gy": maxf(a.y, b.y) + 2.0, "ly": "up", "oid": str(o.id), "k": ""})


func _tx_cell(ci, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(_snap(p), Vector2(g.PX, g.PX)), c)


## 直线刀光一帧：第 0 拍白芯 + 两侧亮琥珀；之后芯转淡琥珀、两侧暗一阶；hold 拍后两拍里逐格断开；两头收尖。ground = 地上的焦痕（只画暗琥珀，晚两拍断完）
func _tx_draw_line(ci, it: Dictionary, ground: bool) -> void:
	var f: int = frame_of(float(it.t0))
	var hold: int = int(it.hold)
	if f < 0:
		return
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	var L: float = a.distance_to(b)
	var dv: Vector2 = (b - a) / maxf(1.0, L)
	var nv := Vector2(-dv.y, dv.x)
	var n: int = maxi(2, int(L / px))
	if ground:
		if f > hold + 3:
			return
		var brk: float = clampf(float(f - hold + 1) / 4.0, 0.0, 1.0)
		for i in n + 1:
			if fposmod(float(i) * 0.618034 + float(int(absf(a.x)) % 13) * 0.07, 1.0) < brk:
				continue
			var u0: float = float(i) / float(n)
			if u0 < 0.06 or u0 > 0.96:
				continue
			_tx_cell(ci, a + dv * float(i) * px + Vector2(0, 2), TX_C[3] if f <= 1 else (TX_C[2] if f <= hold + 1 else TX_C[1]))
		return
	if f > hold + 1:
		return
	var st: int = int(it.st)
	var w: int = int(it.w)
	var lift := Vector2(0, -TX_H)
	if st == 3:
		_tx_draw_line1(ci, it, f, hold, a, b, dv, nv, n, w, lift)
		return
	var broke: bool = f >= hold
	var cold: bool = st == 1 and w >= 2 and it.get("cold", false)
	for i in n + 1:
		var u: float = float(i) / float(n)
		var prof: float = pow(sin(PI * clampf(u * 0.92 + 0.04, 0.0, 1.0)), 0.5)   # 两头收尖
		if broke and fposmod(float(i) * 0.618034 + float(f) * 0.31, 1.0) < (0.45 if f == hold else 0.75):
			continue
		var q: Vector2 = a + dv * float(i) * px + lift
		var cw: int = w if prof > 0.55 else 1
		var core: Color = Color(1, 1, 1) if f == 0 else (TX_C[6] if not broke else TX_C[5])
		var side: Color = TX_C[5] if f == 0 else (TX_C[4] if not broke else TX_C[3])
		for k in cw:
			_tx_cell(ci, q + nv * float(k) * px, core)
		if prof > 0.3:
			_tx_cell(ci, q - nv * px, TX_AC if (cold and (i % 7) == 3 and not broke) else side)   # 精二号令 / 连携：冷青刃光点
			_tx_cell(ci, q + nv * float(cw) * px, side)
			if st >= 1 and prof > 0.7 and f <= 1:
				_tx_cell(ci, q + nv * float(cw + 1) * px, TX_C[3])
		if f == 0 and (i & 1) == 0 and prof > 0.4:
			_glow(q, Color(1.0, 0.85, 0.6))


## 一刀一道（style 3，fx/texas_s3_single_slash）：一条细而亮的斩线——芯 2–3 格近白（第 0–1 拍过曝 + 每格辉光，命中那一拍停住）、两侧一格淡琥珀，没有暗外缘；
## hold 那一拍断一半，下一拍没了（干脆收掉，不拖碎尾）；两头收尖
func _tx_draw_line1(ci, it: Dictionary, f: int, hold: int, a: Vector2, b: Vector2, dv: Vector2, nv: Vector2, n: int, w: int, lift: Vector2) -> void:
	if f > hold:
		return
	var px: float = g.PX
	var hot: bool = f <= 1
	var broke: bool = f == hold and f > 1
	var core: Color = Color(1.35, 1.3, 1.2) if hot else Color(1.0, 0.95, 0.86)   # 芯近白（命中两拍过曝），琥珀只在两侧
	var side: Color = TX_C[6] if hot else TX_C[5]
	for i in n + 1:
		var u: float = float(i) / float(n)
		var prof: float = pow(sin(PI * clampf(u * 0.94 + 0.03, 0.0, 1.0)), 0.6)
		if broke and fposmod(float(i) * 0.618034 + 0.2, 1.0) < 0.5:
			continue
		var cw: int = maxi(1, int(round(float(w) * prof)))
		var q: Vector2 = a + dv * float(i) * px + lift - nv * float(cw / 2) * px
		for k in cw:
			_tx_cell(ci, q + nv * float(k) * px, core)
		if prof > 0.25:
			_tx_cell(ci, q - nv * px, side)
			_tx_cell(ci, q + nv * float(cw) * px, side)
		if hot and prof > 0.2:
			_glow(q + nv * float(cw / 2) * px, Color(1.0, 0.88, 0.66))
		elif (i & 1) == 0 and prof > 0.4 and not broke:
			_glow(q + nv * float(cw / 2) * px, Color(0.8, 0.6, 0.4))


## 精二余像：地上两道残像边线（断续、贴边一格暗内边），life 秒内淡掉；不铺满
func _tx_draw_trail(ci, it: Dictionary) -> void:
	var age: float = g.t - float(it.t0)
	var life: float = float(it.life)
	if age < 0.0 or age >= life:
		return
	var k: float = age / life
	var a: Vector2 = it.a
	var b: Vector2 = it.b
	var px: float = g.PX
	var L: float = a.distance_to(b)
	var dv: Vector2 = (b - a) / maxf(1.0, L)
	var nv := Vector2(-dv.y, dv.x * 0.72).normalized()
	var hw: float = float(it.w) * 0.5
	var n: int = maxi(2, int(L / px))
	var tick: int = int(floor(g.t * 15.0))
	for side in [-1.0, 1.0]:
		for i in n + 1:
			if fposmod(float(i) * 0.618034 + side * 0.3 + float(tick) * 0.11, 1.0) < 0.25 + 0.6 * k:   # 越来越稀
				continue
			var q: Vector2 = a + dv * float(i) * px + nv * hw * side
			_tx_cell(ci, q, TX_C[5] if k < 0.3 else (TX_C[4] if k < 0.65 else TX_C[3]))
			_tx_cell(ci, q - nv * px * side, TX_C[1])


func _tx_due() -> void:
	if _txq.is_empty():
		return
	var now: float = g.t
	var keep: Array = []
	var R = load("res://scripts/render/fx_recipe.gd").of(g)
	for q in _txq:
		if now < float(q[0]):
			keep.append(q)
			continue
		if mode() != 1 or now - float(q[0]) > 0.2:
			continue
		var dd: Dictionary = q[2]
		var o = dd.o
		if not is_instance_valid(o):
			continue
		var at: Vector2 = dd.p
		if str(q[1]) == "lt":
			R._light(o, at, float(dd.lr), float(dd.li), 0.12, R.pal(o).get("light", TX_C[5]))
			continue
		R._grains(o, at + Vector2(0, -6), at.y + 1.0, "shard", int(dd.n), {"tier": tier(o)})
		R._light(o, at + Vector2(0, -8), float(dd.lr), float(dd.li), 0.1, R.pal(o).get("light", TX_C[5]))
	_txq = keep


## 落剑组展开：每柄的立起件（出手前不画；按剑倾角挑 l0 / l1）
func _tx_rain_items(it: Dictionary, ground: bool) -> Array:
	var out: Array = []
	var key: String = it.key
	var t0: float = float(it.t0)
	var lf: float = _life(key + "_l0_up")
	for b in it.rain:
		var ts: float = t0 + float(b.d)
		if g.t < ts or g.t > ts + lf:
			continue
		var gp: Vector2 = _snap(b.p)
		if ground:
			out.append({"k": key + "_gd", "t0": ts, "gp": gp, "flip": b.fl})
		else:
			out.append({"k": key + ("_l1_up" if absf(float(b.a)) > 0.03 else "_l0_up"), "t0": ts, "gp": gp, "flip": b.fl})
	return out


func _tx_sort_items(o, out: Array) -> void:
	var id: String = str(o.id)
	for it in items:
		if str(it.ly) == "rain" and str(it.oid) == id:
			out.append_array(_tx_rain_items(it, false))
	for qv in _tx_qi(o):
		out.append({"k": qv.k + "_up_d%d" % qv.d, "fi": qv.f, "gp": qv.gp, "flip": qv.flip})


## 地面层（德克萨斯）：贴地件、落剑的冲击 / 焦痕、余像边线、直线刀光的地上焦痕、剑气影子
func _floor_tx(o) -> void:
	var cv = o.cv
	var id: String = str(o.id)
	_tx_due()
	for it in items:
		if str(it.oid) != id:
			continue
		match str(it.ly):
			"gd":
				_draw_strip(cv, str(it.k), frame_of(float(it.t0)), _gp(it), it.flip, true)   # 挂在人身上的件（fo）按施放者当前位置
			"gd2":
				_tx_draw_trail(cv, it)
			"rain":
				for s in _tx_rain_items(it, true):
					_draw_strip(cv, str(s.k), frame_of(float(s.t0)), s.gp, s.flip, true)
			"up":
				if it.has("ln") and it.gs:
					_tx_draw_line(cv, it, true)
	for qv in _tx_qi(o):
		_draw_strip(cv, qv.k + "_gd_d%d" % qv.d, int(qv.f), qv.gp, qv.flip, true)


## 旧做法（2）：直线刀光 = 一张光晕烤进颜色的横条，旋转 + 横向拉伸到线长，盖在最上层
func _tx_draw_raw_lines(o) -> void:
	var cv = o.cv
	var m: Dictionary = _meta("tx_raw_line")
	var tx: Texture2D = _tex("tx_raw_line")
	if m.is_empty() or tx == null:
		return
	for it in items:
		if str(it.ly) != "rawln" or str(it.oid) != str(o.id):
			continue
		var fi: int = int((g.t - float(it.t0)) * Bal.v("fx/px_plane_raw_fps", 12.8))
		if fi < 0 or fi >= int(m.n):
			continue
		var a: Vector2 = it.a
		var b: Vector2 = it.b
		var w: float = float(m.w)
		var h: float = float(m.h)
		cv.draw_set_transform((a + b) * 0.5 + Vector2(0, -TX_H), (b - a).angle(), Vector2(a.distance_to(b) / w, g.PX * 1.37))
		cv.draw_texture_rect_region(tx, Rect2(Vector2(-float(m.ox), -float(m.oy)), Vector2(w, h)), Rect2(fi * w, 0.0, w, h))
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 后期剑气（growth/late_shape → vis_growth._fire_qi）：同一次出手的几道合成一柄飞剑（同星熊 _qi_volleys 的分组）；
## 飞行途中每 3 拍在身后落一柄小剑（剑雨意象，每组至多 3 柄；画面计时记在剑气字典的画面专用键 _pxd，玩法不读）
func _tx_qi(o) -> Array:
	var out: Array = []
	if mode() != 1 or o.vg.is_empty() or not o.vg.has("qi") or o.vg.qi.is_empty():
		return out
	var grp: Dictionary = {}
	for q in o.vg.qi:
		var key: int = int(round((g.t - float(q.t)) * 60.0))
		if not grp.has(key):
			grp[key] = {"p": Vector2.ZERO, "v": Vector2.ZERO, "n": 0, "t": float(q.t), "life": float(q.life), "q0": q}
		var e: Dictionary = grp[key]
		e.p += _qpos(q)
		e.v += (q.v as Vector2).normalized()
		e.n += 1
		e.life = minf(float(e.life), float(q.life))
	var t: int = tier(o)
	var keys: Array = grp.keys()
	keys.sort()
	keys.reverse()
	var tick: int = int(floor(g.t * 15.0))
	for key in keys.slice(0, 2):   # 同屏至多两组（最新两次出手）
		var e: Dictionary = grp[key]
		var n: int = int(e.n)
		var S: int = 1 if n <= 1 else (2 if n == 2 else 3)
		var dk: Array = pick_dir((e.v as Vector2).angle())
		var f: int = 0 if float(e.t) < 1.0 / 15.0 else (2 if float(e.life) < 0.07 else 1)
		var gp: Vector2 = _snap(e.p / float(n))
		out.append({"k": "tx_qi_s%d_e%d" % [S, t], "d": dk[0], "flip": dk[1], "gp": gp, "f": f})
		var q0: Dictionary = e.q0
		if not q0.has("_pxd"):
			q0["_pxd"] = [tick, 0]
			continue
		var dn: Array = q0._pxd
		if tick - int(dn[0]) < 3 or int(dn[1]) >= 3:
			continue
		q0["_pxd"] = [tick, int(dn[1]) + 1]
		var back: Vector2 = gp - (e.v as Vector2).normalized() * 30.0
		_tx_rain(o, [{"p": back, "d": 0.0, "a": 0.0, "fl": (tick % 2) == 0}], "tx_sw_s14_e%d" % t, false, t)
	return out


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

