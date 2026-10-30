## 歌蕾蒂娅 S3「缺水的碎漩狂舞」画面（用户 10-31 重做；pixfx 做法，见 .claude/skills/pixfx）：
## 原作是束缚远处一名敌人、在那里卷起一道龙卷海流，周围敌人减速、每跳受伤并被拖向中心，结束时整团拖走。
## 这里只画画面（借终结技框架 g.ult 的 strip / 图形 / 灯 / 颗粒，g.ult 关时退回原帧条）：
##   起：地面一张深海漩涡（pixgen 3 种 fx_gl_pool1–3）从中心转开、铺满判定半径，中心水花往上翻（不叠侧视龙卷柱：用户 10-31 嫌漩涡 + 龙卷叠着像拼接）；
##   持续：外层漩涡慢转、内层快转（方向按变体），泡沫往中心卷；每跳一道泡沫环从外往里收（拉扯）+ 水花；
##   收：漩涡收拢 → 爆起一圈浪 + 水花 + 灯 + 轻震（≤ 3 像素、0.15 秒，用户同意），漩涡收缩淡出。
## 变体按区域生成时刻 + 位置的哈希挑：漩涡花纹、转向、摇摆相位、水花落点；同种子同局可重现，不抽模拟随机数。判定 / 数值不动。
extends RefCounted

const A = preload("res://scripts/art.gd")
const POOLS := ["fx_gl_pool1", "fx_gl_pool2", "fx_gl_pool3"]
const FOAM := Color(0.66, 0.85, 0.9)
const DEEP := Color(0.05, 0.1, 0.18)


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898 + 78.233) * 43758.5453, 1.0)


static func _half(u, name: String) -> float:   # 贴图半宽（世界像素，sc 1）
	var t: Texture2D = u._strip_tex(name)
	return t.get_width() * 0.5 / A.hires_of(t) * u.g.PX


static func ready(o) -> bool:
	var u = o.g.ult
	return u != null and u.fx_ready(POOLS[0])


## 区域生成：返回 false 表示没画（调用方退回原帧条）
static func start(o, f: Dictionary) -> bool:
	if not ready(o):
		return false
	var u = o.g.ult
	var c: Vector2 = f.pos
	var R: float = float(f.r)
	var life: float = float(f.dur) + 0.8
	var vs: float = floorf(_h(o.g.t * 1.37 + c.x * 0.013 + c.y * 0.029) * 997.0)
	var name: String = POOLS[int(_h(vs) * 3.0) % 3]
	var hr: float = _half(u, name)
	var dirn: float = -1.0 if _h(vs + 1.0) < 0.5 else 1.0
	var p := {"vs": vs, "dir": dirn, "hr": hr, "R": R}
	u.shape({"kind": "circle", "c": c, "r": R * 1.05, "col": DEEP, "fill": 0.45, "life": life, "layer": "back"})   # 海面压暗
	p["outer"] = u.strip(name, c, {"layer": "back", "sc": R * 0.2 / hr, "sc1": R * 0.95 / hr, "scd": 0.35, "life": life, "fade": 0.5, "col": Color(0.78, 0.82, 0.86, 0.55)})
	var name2: String = POOLS[(int(_h(vs) * 3.0) + 1) % 3]
	p["inner"] = u.strip(name2, c, {"layer": "back", "sc": R * 0.1 / _half(u, name2), "sc1": R * 0.5 / _half(u, name2), "scd": 0.4, "ang": 1.3, "life": life, "fade": 0.5,
		"col": Color(0.85, 0.9, 0.95, 0.5)})
	u.light(c, R * 1.3, Color(0.2, 0.45, 0.6), 0.3)
	for q in 10:
		var dq := Vector2.from_angle(TAU * (q + _h(vs + q)) / 10.0)
		u.grain("water", c + dq * R * 0.3, dq, FOAM, 4)
	f["pix"] = p
	return true


## 每帧：漩涡转、龙卷翻卷摇摆、泡沫往里卷
static func step(o, f: Dictionary) -> void:
	var u = o.g.ult
	if u == null or not f.has("pix"):
		return
	var p: Dictionary = f.pix
	var t: float = float(f.t)
	var d: float = float(p.dir)
	var vs: float = float(p.vs)
	p.outer.ang = d * t * 1.6
	p.inner.ang = 1.3 + d * t * 3.4
	if p.has("flash") and t - float(p.flash) > 0.08:
		p.outer.col = Color(0.78, 0.82, 0.86, 0.55)
		p.erase("flash")
	if not p.has("ending") and int(t * 60.0) % 3 == 0:   # 漩涡中心往上翻的水花（代替龙卷柱）
		var hc: float = _h(vs + t * 3.1)
		u.grain("water", Vector2(f.pos) + Vector2((hc - 0.5) * float(p.R) * 0.3, 0.0), Vector2.UP.rotated((hc - 0.5) * 0.8), FOAM, 3)
	if int(t * 60.0) % 5 == 0:
		var hq: float = _h(vs + t * 7.0)
		var R: float = float(p.R)
		var a: float = hq * TAU
		u.grain("mote_in", Vector2(f.pos) + Vector2.from_angle(a) * R * 0.95, Vector2.from_angle(a + PI - 0.6 * d), FOAM, 2)


## 每跳（伤害 + 拉扯那一下）：一道泡沫环从外往里收 + 沿圈 4 处水花往里打
static func tick(o, f: Dictionary) -> void:
	var u = o.g.ult
	if u == null or not f.has("pix"):
		return
	var p: Dictionary = f.pix
	var c: Vector2 = f.pos
	var R: float = float(p.R)
	var vs: float = float(p.vs) + float(f.done) * 13.0
	u.shape({"kind": "ring", "c": c, "r": R * 0.35, "r1": R * 1.02, "w": 4.0, "col": Color(FOAM, 0.55), "life": 0.35})
	for q in 4:
		var a: float = TAU * (q + _h(vs + q)) / 4.0
		var pt: Vector2 = c + Vector2.from_angle(a) * R * (0.75 + 0.2 * _h(vs + q * 3.0))
		u.grain("water", pt, Vector2.from_angle(a + PI), FOAM, 6)
	p.outer.col = Color(1.0, 1.05, 1.1, 0.7)
	p["flash"] = float(f.t)


## 收尾：漩涡收拢 → 一圈浪爆开 + 水花 + 灯 + 轻震，漩涡收缩淡出
static func finish(o, f: Dictionary) -> void:
	var u = o.g.ult
	if u == null or not f.has("pix"):
		return
	var p: Dictionary = f.pix
	if p.has("ending"):
		return
	p["ending"] = true
	var c: Vector2 = f.pos
	var R: float = float(p.R)
	var vs: float = float(p.vs) + 77.0
	for s in [p.outer, p.inner]:   # 缩放已到位：定住当前大小，0.4 秒退去
		s["sc"] = float(s.get("sc1", s.sc))
		s.erase("sc1")
		s.max = float(s.age) + 0.4
		s["fade"] = 0.4
	var name: String = POOLS[int(_h(vs) * 3.0) % 3]
	var hr: float = _half(u, name)
	u.strip(name, c, {"sc": R * 0.3 / hr, "sc1": R * 1.35 / hr, "scd": 0.3, "ang": _h(vs + 2.0) * TAU, "life": 0.5, "fade": 0.35, "col": Color(0.95, 1.0, 1.05, 0.5)})   # 浪圈外推
	u.shape({"kind": "circle", "c": c, "r": R * 0.45, "col": Color(0.6, 0.8, 0.86), "fill": 0.75, "life": 0.08})
	u.light(c, R * 1.6, Color(0.25, 0.5, 0.62), 0.3)
	u.shake(3.0, 0.15)
	for q in 16:
		var dq := Vector2.from_angle(TAU * (q + _h(vs + q)) / 16.0)
		u.grain("water", c + dq * R * (0.2 + 0.3 * _h(vs + q * 2.0)), dq, FOAM, 5)
