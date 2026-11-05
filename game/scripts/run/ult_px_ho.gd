## 星熊终结技「般若反震」配色对齐 + 转平面加强（docs/254 §9，开关 ult/px_plane 总开关或 ult/px_plane_hoshiguma 单人，缺省 0 = 原画面）。
## 11-05 晚用户「星熊改配色」：以原版为底，盾阵六边形、石尘环、盾下裂地、隆起、烟尘这些造型和节奏一律不动，只做三件事：
##   ① 配色：满屏橙黄（她的旧代表色）→ 这次普攻 / 技能定稿的 PRTS 发色青绿 #58C4AB；挡住期间越挡越热改成青绿 → 暖金（原版是白 → 红，红只给危险），反震那一下暖金芯；
##      贴图件（裂地 fx_hs_crack、石尘环 fx_hs_ring、烟尘、隆起、碎石、粒子）按青绿灰着色，不另画；
##   ② 去平涂叠层：反震时六边形每帧画一圈、每圈留 0.06 秒，叠成满屏同心条纹（docs/280「大面积平涂、半透明叠层盖住整屏」）→ 每帧只留当前这一圈、线加粗、真 alpha；
##   ③ 怪物崩解：反震打中的怪当拍补一次引擎击杀碎屑 + 一圈怪物本色像素往外喷（同 docs/275 §1.0、斯卡蒂 ult_px_sd）。
## 冲击帧（v3 石尘环进剪影）和顿帧 + 慢放（ult.impact，反震第一下真伤害自动触发）原版就有，照旧。只画，不碰玩法、不抽随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const D = preload("res://scripts/data.gd")   # 怪物代表色 ecol

const JADE := Color(0.345, 0.769, 0.671)        # #58c4ab
const JADE_L := Color(0.706, 0.941, 0.886)      # #b4f0e2
const JADE_D := Color(0.18, 0.54, 0.46)         # #2f8a76
const AMBER := Color(0.949, 0.749, 0.298)       # #f2bf4c 暖金（精二点缀色）
const STONE := Color(0.82, 1.02, 0.96)          # 贴图件着色：青绿灰（石尘、裂地、尘、碎石）
const STONE_D := Color(0.5, 0.6, 0.57)
const SPRAY_N := 22
const SPRAY_MAX := 120

var g
var sprays: Array = []


static func on() -> bool:
	return Bal.v("ult/px_plane", 0.0) > 0.0 or Bal.v("ult/px_plane_hoshiguma", 0.0) > 0.0


static func of(game):
	if game.has_meta("ult_px_ho"):
		return game.get_meta("ult_px_ho")
	var r = new()
	r.g = game
	game.set_meta("ult_px_ho", r)
	return r


## 挡住期间的热度色：k = 0 → 1（青绿 → 暖金）
static func heat(k: float) -> Color:
	return JADE_L.lerp(AMBER, clampf(k, 0.0, 1.0))


static func _hf(x: int, y: int, k: int) -> float:
	return float(((x * 73856093) ^ (y * 19349663) ^ (k * 83492791)) & 0xFFFF) / 65535.0


## 反震打中一只怪（ult_moves_c._ho_step 反震段，只画）：补引擎击杀碎屑 + 本色像素往外喷；k = 1 近处、外圈弱一号
func burst(e: Dictionary, c: Vector2, R: float) -> void:
	if e.get("boss", false):
		return
	if g.optical_on and g.optical != null and g.optical.particles != null:
		g.optical.particles.kill_burst(e)
	var p: Vector2 = e.pos
	var rel: Vector2 = p - c
	var out: Vector2 = Vector2(rel.x, rel.y / 0.72).normalized() if rel.length() > 1.0 else Vector2.RIGHT
	var col: Color = D.ENEMIES.get(str(e.get("type", "")), {}).get("ecol", Color(0.6, 0.9, 0.9))
	var k: float = 1.0 + 0.4 * clampf(1.0 - rel.length() / maxf(1.0, R), 0.0, 1.0)
	sprays.append({"p": p + Vector2(0, -10), "t0": g.t, "col": col, "out": out, "k": k, "sd": int(e.get("id", 0)) * 13 + 7})
	if sprays.size() > SPRAY_MAX:
		sprays.pop_front()


## 上层（ult.draw_world 转来）：崩解喷散，逐格画在美术像素格上
func draw_front(_u, w) -> void:
	if sprays.is_empty():
		return
	w.tb_flush()
	var px: float = g.PX
	var keep: Array = []
	for sp in sprays:
		var age: float = g.t - float(sp.t0)
		if age > 1.3 or age < 0.0:
			continue
		keep.append(sp)
		var col: Color = sp.col
		var cols: Array = [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.3)]
		var k: float = float(sp.k)
		var base: Vector2 = ((sp.p as Vector2) / 2.0).round() * 2.0
		var sd: int = int(sp.sd)
		for q in int(SPRAY_N * k):
			var ang: float = (sp.out as Vector2).angle() + (_hf(q, sd, 71) - 0.5) * 1.8
			var spd: float = (40.0 + 90.0 * _hf(q, sd, 72)) * k
			var vh: float = 30.0 + 60.0 * _hf(q, sd, 73)
			var t_land: float = 2.0 * vh / 260.0
			var t: float = minf(age, 0.9)
			var tt: float = minf(t, t_land)
			var hgt: float = maxf(0.0, vh * tt - 130.0 * tt * tt) if t < t_land else 0.0
			var off := Vector2(cos(ang) * spd * tt, sin(ang) * spd * tt * 0.72 - hgt)
			var c: Color = cols[q % 4]
			var hot: bool = age < 2.0 / 15.0 and q % 3 == 0
			if hot:
				c = Color.WHITE
			c.a = 1.0 if age < 0.9 else maxf(0.0, (1.3 - age) / 0.4)
			var sz: float = px * (2.0 if q % 3 != 2 else 1.0)
			g.draw_rect(Rect2(base + (off / 2.0).round() * 2.0, Vector2(sz, sz)), c)
	sprays = keep
