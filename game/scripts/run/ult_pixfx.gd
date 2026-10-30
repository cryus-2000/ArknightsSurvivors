## pixfx 公用画法（docs/199 §7.6–7.8，做法见 .claude/skills/pixfx）：pixgen 出的单张大贴图 + 代码驱动动画，给 ult_moves_b / _c 的各人终结技用。
## 全是画面：只调 u.strip / u.shape / u.grain / u.light，不碰 u.hit 与模拟随机数（散布按 h() 哈希）。
## 贴图都是 @2x、1 纹素 = 1 世界像素（sc 1 时），一格 3×3 纹素 = ult/px_grid。
## 变体（用户 10-30「一直用一种也会很单调」）：每种冲击类贴图 ≥ 3 个变体，每次出招按 vseed（出招时刻 + 落点的哈希：同种子同局可重现，
## 不抽模拟随机数、也不动 vrng）挑变体、镜像、旋转、散布。
extends RefCounted

const A = preload("res://scripts/art.gd")
const ROCKS := [["fx_ul_rock", [0, 1, 3]], ["fx_ul_rock2", [0, 1, 2, 3]]]   # 地块帧条组：[名, 可用帧]（fx_ul_rock 第 2 帧整块发青，不用）
const WALL := "fx_ul_dust_wall"   # 尘土墙长条（截弦长段沿圈摆）


static func h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


## 每次出招的变体种子（0..996）：出招时刻 + 落点的哈希，同种子同局可重现
static func vseed(u, c: Vector2) -> float:
	return floorf(h(u.g.t * 1.37 + c.x * 0.013 + c.y * 0.029) * 997.0)


## 从已到位的变体里按 x 哈希挑一个（都没到位返回 ""）
static func pick(u, names: Array, x: float) -> String:
	var ok: Array = []
	for n in names:
		if u.fx_ready(n):
			ok.append(n)
	return "" if ok.is_empty() else str(ok[int(h(x) * ok.size()) % ok.size()])


## 贴图在 sc 1 时的世界宽度
static func tex_w(u, name: String) -> float:
	var t: Texture2D = u._strip_tex(name)
	return t.get_width() / A.hires_of(t) * u.g.PX if t != null else 1.0


## 一块地块飞起落回：v 水平初速、vy 上抛速度（落回原高度的寿命 = 2·vy/grav）
static func rock(u, p: Vector2, v: Vector2, vy: float, hh: float, sc: float, delay: float, col := Color.WHITE) -> void:
	var sets: Array = []
	for rs in ROCKS:
		if u.fx_ready(rs[0]):
			sets.append(rs)
	if sets.is_empty():
		return
	var rs: Array = sets[int(h(hh * 53.0) * sets.size()) % sets.size()]
	var fr: Array = rs[1]
	var grav: float = 1500.0
	var f: int = int(fr[int(hh * 97.0) % fr.size()])
	var scc: float = sc + 0.2 * h(hh * 17.0)
	var fl: float = 2.0 * vy / grav
	var sx: float = -1.0 if h(hh * 29.0) < 0.5 else 1.0
	u.strip(rs[0], p, {"f": f, "sc": scc, "col": col, "sx": sx, "v": v + Vector2(0, -vy), "grav": grav, "life": fl, "spin": (hh - 0.5) * 10.0, "delay": delay})
	# 落地停住：落点（横向漂了 v·飞行时间）原地躺 0.6 秒再淡，转角停在落地那一刻（中村丰式碎屑有重量，pixfx §6.6）
	u.strip(rs[0], p + v * fl, {"f": f, "sc": scc, "col": col, "sx": sx, "ang": (hh - 0.5) * 10.0 * fl, "life": 0.9, "fade": 0.4, "delay": delay + fl, "layer": "back"})


## 沿圈隆起：半径 r 上一圈地块顶起一小跳落回、每 4 块 1 块高飞；delay 整圈延后（波前到达时刻）
static func heave(u, c: Vector2, r: float, seed0: float, delay := 0.0, col := Color.WHITE, per := 120.0) -> void:   # seed0 带上 vseed 就每次不同
	var nr: int = maxi(4, roundi(TAU * r / per))
	for q in nr:
		var hh: float = h(seed0 * 37.0 + q * 7.0)
		var dv: Vector2 = Vector2.from_angle(seed0 * 0.41 + TAU * (q + 0.6 * hh) / nr)
		var p: Vector2 = c + dv * r * (0.86 + 0.16 * hh)
		var high: bool = q % 4 == 0
		rock(u, p, dv * ((60.0 + 80.0 * hh) if high else 25.0), (260.0 + 160.0 * hh) if high else (110.0 + 60.0 * hh), hh, 0.5 if high else 0.42, delay + 0.02 * (q % 3), col)
		if q % 3 == 0:
			u.grain("bfx_dust", p, dv, Color(0.58, 0.58, 0.56), 3)


## 余震：delay 秒后半径 R 内再跳一批碎石
static func aftershock(u, c: Vector2, R: float, seed0: float, delay: float, n := 10, col := Color.WHITE) -> void:
	for q in n:
		var hh: float = h(q * 5.0 + seed0 * 11.0)
		rock(u, c + Vector2.from_angle(TAU * (q + hh) / n) * R * (0.25 + 0.7 * hh), Vector2.ZERO, 120.0 + 60.0 * hh, hh, 0.4, delay + 0.05 * (q % 3), col)


## 尘土墙：WALL 截成弦长段沿圈摆一圈，整圈往外推、淡出
static func wall(u, c: Vector2, r: float, delay := 0.0, col := Color(1, 1, 1, 0.85)) -> void:
	if not u.fx_ready(WALL):
		return
	var t: Texture2D = u._strip_tex(WALL)
	var k: float = u.g.PX / A.hires_of(t)
	var n: int = maxi(12, roundi(TAU * r / 150.0))
	var chord: float = 2.0 * r * sin(PI / n)
	var uw: float = minf(t.get_width(), chord * 1.15 / k)
	for q in n:
		var a0: float = TAU * q / n
		var p0: Vector2 = c + Vector2.from_angle(a0) * r
		var p1: Vector2 = c + Vector2.from_angle(a0 + TAU / n) * r
		var d: Vector2 = (p1 - p0).normalized()
		u.strip(WALL, p0 - d * chord * 0.07, {"layer": "back", "ang": d.angle(), "o": Vector2(0.0, t.get_height() * 0.5),
			"ux": floorf(h(q * 3.0 + 7.0) * (t.get_width() - uw)), "uw": uw, "v": Vector2.from_angle(a0 + PI / n) * 140.0,
			"life": 0.6, "fade": 0.4, "col": col, "delay": delay})


## 放射裂网：names = 分叉裂缝贴图变体（左粗右细带分叉，原点左端中心），每条按 seed 挑一个、随机镜像；angs 每条的角度，lens 每条的长度（世界）；
## opt：seed / r0（起点离中心的距离，按哈希 ×0.6–1.4）/ crop（截贴图不同段，增加形状变化）/ rev（显现秒数）/ rev0 / life / fade / col / col1 / cold / delay（最大随机错开）/ big（粗条的 sy）/ small
static func cracks(u, names: Array, c: Vector2, angs: Array, lens: Array, opt: Dictionary) -> void:
	var sd: float = float(opt.get("seed", 0.0))
	for j in angs.size():
		var name := pick(u, names, sd * 0.37 + j * 1.7)
		if name == "":
			return
		var t: Texture2D = u._strip_tex(name)
		var tw: float = tex_w(u, name)
		var s := {"layer": "back", "ang": float(angs[j]), "o": Vector2(0.0, t.get_height() * 0.5),
			"sx": float(lens[j]) / tw, "sy": float(opt.get("big", 0.85) if h(sd + j * 3.1) < 0.33 else opt.get("small", 0.55)) * (1.0 if h(sd * 1.3 + j) < 0.5 else -1.0),
			"delay": float(opt.get("delay", 0.04)) * h(j + 110.0), "rev": float(opt.get("rev", 0.3)), "rev0": float(opt.get("rev0", 0.15)),
			"life": float(opt.get("life", 1.4)), "fade": float(opt.get("fade", 0.6)), "col": opt.get("col", Color.WHITE)}
		if opt.get("crop", false):   # 截贴图不同的一段当这条裂缝（4 种形状截出几十种，预审报同形重复时用）：起点跳过 0–35%、尾部截掉 0–25%
			var W: float = float(t.get_width())
			var ux: float = floorf(h(sd * 0.9 + j * 4.3) * 0.35 * W)
			var uw: float = W - ux - floorf(h(sd * 1.7 + j * 2.9) * 0.25 * W)
			s["ux"] = ux
			s["uw"] = uw
			s["sx"] = float(lens[j]) / (tw * uw / W)
		if opt.has("col1"):
			s["col1"] = opt.col1
			s["cold"] = float(opt.get("cold", 0.6))
		var r0: float = float(opt.get("r0", 0.0)) * (0.6 + 0.8 * h(sd + j * 2.3))   # 起点离中心（坑口外起裂，避免全部从一点放射成星形）
		u.strip(name, c + Vector2.from_angle(float(angs[j])) * r0, s)


## 像素粒子爆（用户 10-30「粒子能够用贴图来替代，这样减小开销」）：播预烘焙的粒子扩散帧条（tools/imagegen/pxburst.py 离线模拟：
## 迸开 → 阻力减速扩散 → 冷却变暗，白灰色阶），col 着色；sc ≈ 2 时 1 纹素 = 2 世界像素，同 fx_grains 2 px 颗粒观感。
## kind：ult_burst = 大（半径约 reach，缺省 380）、ult_burst_s = 小（约 110）、ult_ember = 小号慢一点；n 只决定叠几层（每 300 颗一层，层间转角错开）
const DUST := "fx_dust_seq"


## 团块烟尘（pixfx §6.6）：逐帧帧条 fx_dust_seq（7 帧：喷出 → 往外冲 → 翻滚 → 撕开 → 散成丝 → 零星颗粒），
## 出现和消失都是画出来的帧，不靠缩放 / 淡出（用户 10-31：圆团像「棉花球」、块面不要、「只漂移没有出现消失」）。
## 主团 + 一团小一点、晚一拍、转个角度的暗团叠在下面（分层）；整体往 v 慢漂。没有贴图时什么都不画
static func dust(u, p: Vector2, size: float, delay: float, seed0: float, v := Vector2.ZERO, col := Color.WHITE) -> void:
	if not u.fx_ready(DUST):
		return
	var k: float = size / tex_w(u, DUST) * 7.0   # 帧条 7 帧并排，单帧宽 = 总宽 / 7
	var fps: float = 10.0
	var a0: float = h(seed0 * 7.0) * TAU
	var sx: float = -1.0 if h(seed0 * 3.0) < 0.5 else 1.0
	for l in 2:
		var cl: float = 1.0 if l == 0 else 0.55
		u.strip(DUST, p + Vector2.from_angle(a0 + 2.0) * size * 0.12 * l, {"sc": k * (1.0 if l == 0 else 0.8), "ang": a0 + 1.9 * l, "sx": sx * (1.0 if l == 0 else -1.0),
			"fps": fps * (1.0 if l == 0 else 0.85), "life": 7.0 / (fps * (1.0 if l == 0 else 0.85)), "delay": delay + 0.05 * l, "v": v * (1.0 - 0.3 * l),
			"col": Color(col.r * cl, col.g * cl, col.b * cl, 1.0), "layer": "back" if l == 1 else "front"})


const BURSTS := ["fx_px_burst1", "fx_px_burst2"]
const BURST_S := "fx_px_burst_s"


static func particles(u, p: Vector2, n: int, kind: String, cols: Array, delay := 0.0, seed0 := 0.0, reach := 0.0) -> void:
	var small: bool = kind != "ult_burst"
	var name: String = BURST_S if small else pick(u, BURSTS, seed0 * 0.61)
	if name == "" or not u.fx_ready(name):
		return
	var half: float = 48.0 if small else 180.0   # 帧半宽（纹素）；扩散到约 0.8 × half
	var rch: float = reach if reach > 0.0 else (110.0 if small else 380.0)
	var layers: int = clampi(n / 300, 1, 2) if not small else 1
	var slow: float = 1.4 if kind == "ult_ember" else 1.0
	for l in layers:
		var cc: Color = cols[(l + int(h(seed0) * cols.size())) % cols.size()]
		u.strip(name, p, {"sc": rch / (half * 0.8) * (1.0 - 0.15 * l), "ang": h(seed0 + l * 3.0) * TAU, "sx": -1.0 if h(seed0 + l) < 0.5 else 1.0,
			"fps": 8.0 / (0.9 * slow), "life": 0.95 * slow, "fade": 0.25, "delay": delay + 0.05 * l,
			"col": Color(minf(1.6, cc.r * 1.35), minf(1.6, cc.g * 1.35), minf(1.6, cc.b * 1.35), 1.0)})


## 节拍（顿感 / 节奏对齐乌尔比安的四圈：每 0.18 秒一拍，每拍一次震屏 + 一圈隆起 + 短灯 + 尘）：beats = [[t, r], ...]，在 step 里每帧调 tick_beats
static func beats_tick(u, a: Dictionary, t: float, c: Vector2, col: Color) -> void:
	if not a.has("beats"):
		return
	var bs: Array = a.beats
	while not bs.is_empty() and t >= float(bs[0][0]):
		var b: Array = bs.pop_front()
		var r: float = float(b[1])
		var i: int = int(b[2])
		u.shake(4.0 + 2.0 * i, 0.18)
		if a.has("beat_fan"):   # 朝前打：只在前方扇形里零散顶起几块（整圈等距隆起会被看成一圈贴片）
			var fan: Array = a.beat_fan
			for q in 5:
				var hq: float = h(float(a.get("vs", 0.0)) + i * 7.0 + q * 1.9)
				var dv := Vector2.from_angle(float(fan[0]) + (hq - 0.5) * 2.0 * float(fan[1]))
				rock(u, c + dv * r * (0.7 + 0.3 * h(hq * 5.0)), dv * 50.0, 140.0 + 140.0 * h(hq * 3.0), hq, 0.45 + 0.2 * hq, 0.03 * q)
		else:
			heave(u, c, r, float(a.get("vs", 0.0)) + 30.0 + i)
		u.light(c, r * 1.1, col, 0.2)
		for q in 10:
			var dq := Vector2.from_angle(TAU * (q + h(q + i)) / 10.0)
			u.grain("bfx_dust", c + dq * r, dq, Color(0.62, 0.6, 0.56), 3)


## 乌尔比安式裂网（用户 10-30「所有裂地的感觉都跟乌尔比安的对齐」）：names = 这人的分叉裂缝组（同形状、各人调色），
## n 条从 c 外 r0 起裂、角度 / 长短 / 粗细 / 起裂时刻按 seed 错开，grow 秒内往外长到 0.62–1.07 R，先亮（hot）再冷成暗色余烬（cold）
static func crack_net(u, names: Array, c: Vector2, R: float, n: int, base: float, seed0: float, grow: float, hot: Color, cold: Color, r0 := 0.0, crop := false) -> void:
	var angs: Array = []
	var lens: Array = []
	for j in n:
		angs.append(base + TAU * (float(j) + (h(j + 1.0 + seed0) - 0.5) * 0.75) / n)
		lens.append(R * (0.62 + 0.45 * h(j + 21.0 + seed0)))
	cracks(u, names, c, angs, lens, {"seed": seed0, "r0": r0, "rev": grow, "rev0": 0.18, "delay": 0.06, "life": grow + 1.6, "fade": 0.7,
		"col": hot, "col1": cold, "cold": grow + 0.45, "crop": crop, "small": 0.55 if not crop else 0.4})


## 不规整放射角度：n 条，从 a0 起均分、每条按哈希偏 ±0.35 格
static func angles(n: int, a0: float, seed0: float) -> Array:
	var out: Array = []
	for j in n:
		out.append(a0 + TAU * (j + (h(j + seed0) - 0.5) * 0.7) / n)
	return out


## 整圈环贴图从半径 r0 扩到 r1（dur 秒缓出），life 内淡出；names 变体按 opt.seed 挑、随机转角 + 镜像
static func ring(u, names: Array, c: Vector2, r0: float, r1: float, dur: float, life: float, opt := {}) -> Dictionary:
	var sd: float = float(opt.get("seed", 0.0))
	var name := pick(u, names, sd * 0.71 + 5.0)
	if name == "":
		return {}
	var rr: float = tex_w(u, name) * 0.5
	var s := {"layer": str(opt.get("layer", "back")), "sc": r0 / rr, "sc1": r1 / rr, "scd": dur, "life": life,
		"fade": float(opt.get("fade", life * 0.5)), "ang": h(sd + 9.0) * TAU, "sx": -1.0 if h(sd + 4.0) < 0.5 else 1.0, "col": opt.get("col", Color.WHITE), "delay": float(opt.get("delay", 0.0))}
	if opt.has("col1"):
		s["col1"] = opt.col1
		s["cold"] = float(opt.get("cold", 0.3))
	return u.strip(name, c, s)
