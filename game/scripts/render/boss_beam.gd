extends RefCounted
## Boss 改版样板的画面（docs/142b §8.5、§3.1，10-25）：
## 1. "kp_beam"：Kanpelle · Ultimate Laser Pack 光束（tools/gen_boss_laser.py 导出 fx_kp_<boss>_<段>，每段 16 × 48、4 帧）。
##    起点 + 中段平铺 + 命中端，沿 a → b 旋转；先播开启 4 帧，再循环持续帧，最后开启倒放 = 关闭。纯画面，不碰随机数。
## 2. 骑士「斗牛」的寒气圈（地面层）与主控的寒冷条（顶层）：读 e.kcold / e.kcold_r（knight_boss.gd 写）。
const A = preload("res://scripts/art.gd")

const SEG := 16.0     # 每段宽（美术像素）
const HALF_H := 24.0  # 帧高 48 的一半（光束竖直居中）
const ON_T := 0.12    # 开启 / 关闭各 0.12 秒（4 帧）
const FPS := 16.0     # 持续帧循环


static func _tex(g, name: String) -> Texture2D:
	if not g.tex.has(name):
		g.tex[name] = A.tex(name)
	return g.tex[name]


## f：{"kind": "kp_beam", "a", "b", "life", "max", "boss": "iberia", "k": 世界像素 / 美术像素（缺省 2 = 1 倍粗，3 = 1.5 倍粗）}
static func draw(g, f: Dictionary) -> bool:
	var boss: String = str(f.get("boss", ""))
	var el: float = float(f.max) - float(f.life)
	var on: bool = el < ON_T or float(f.life) < ON_T
	var fr: int
	if el < ON_T:
		fr = clampi(int(el / ON_T * 4.0), 0, 3)
	elif float(f.life) < ON_T:
		fr = clampi(int(float(f.life) / ON_T * 4.0), 0, 3)   # 关闭 = 开启倒放
	else:
		fr = int(el * FPS) % 4
	var suf: String = "_on" if on else ""
	var t_src := _tex(g, "fx_kp_%s_src%s" % [boss, suf])
	var t_mid := _tex(g, "fx_kp_%s_mid%s" % [boss, suf])
	var t_hit := _tex(g, "fx_kp_%s_hit%s" % [boss, suf])
	if t_src == null or t_mid == null or t_hit == null:
		return false   # 缺图交回原画法（tracer）
	var k: float = float(f.get("k", 2.0))
	var a: Vector2 = f.a
	var b: Vector2 = f.b
	var lp: float = maxf(a.distance_to(b) / k, SEG * 2.0)   # 光束长度（美术像素），至少起点 + 命中端
	var src_rect := Rect2(fr * SEG, 0, SEG, HALF_H * 2.0)
	g.draw_set_transform(a, (b - a).angle(), Vector2(k, k))
	g.draw_texture_rect_region(t_src, Rect2(0, -HALF_H, SEG, HALF_H * 2.0), src_rect)
	var x: float = SEG
	while x < lp - SEG:
		var w: float = minf(SEG, lp - SEG - x)
		g.draw_texture_rect_region(t_mid, Rect2(x, -HALF_H, w, HALF_H * 2.0), Rect2(fr * SEG, 0, w, HALF_H * 2.0))
		x += SEG
	g.draw_texture_rect_region(t_hit, Rect2(lp - SEG, -HALF_H, SEG, HALF_H * 2.0), src_rect)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 平铺一段光束中段（a → b，k 倍、透明度 al）：卡门的火线等「留在地上的光束」
static func _tile(g, tex: Texture2D, a: Vector2, b: Vector2, k: float, fr: int, al: float) -> void:
	var lp: float = a.distance_to(b) / k
	if lp <= 0.5:
		return
	g.draw_set_transform(a, (b - a).angle(), Vector2(k, k))
	var x: float = 0.0
	while x < lp:
		var w: float = minf(SEG, lp - x)
		g.draw_texture_rect_region(tex, Rect2(x, -HALF_H, w, HALF_H * 2.0), Rect2(fr * SEG, 0, w, HALF_H * 2.0), Color(1, 1, 1, al))
		x += SEG
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 卡门的封锁线（saint.gd _fire_step 写 e.fire_lines）：Kanpelle 象牙白中段压暗平铺，缺口空出来、画白圈；最后 0.6 秒淡出
static func _fire_lines(g, e: Dictionary) -> void:
	var tex := _tex(g, "fx_kp_%s_mid" % e.type)
	for fl in e.get("fire_lines", []):
		var left: float = float(fl.until) - g.t
		var al: float = 0.55 * clampf(left / 0.6, 0.0, 1.0) * clampf((g.t - float(fl.get("born", 0.0))) / 0.15, 0.0, 1.0)
		var a: Vector2 = fl.a
		var b: Vector2 = fl.b
		var L: float = a.distance_to(b)
		if L < 1.0:
			continue
		var gt: float = float(fl.gap_t)
		var gh: float = float(fl.gap_len) * 0.5 / L
		var fr: int = int(g.t * FPS) % 4
		if tex != null:
			_tile(g, tex, a, a.lerp(b, maxf(0.0, gt - gh)), 2.0, fr, al)
			_tile(g, tex, a.lerp(b, minf(1.0, gt + gh)), b, 2.0, fr, al)
		else:
			g.draw_line(a, a.lerp(b, gt - gh), Color(1.0, 0.94, 0.82, al), 6.0)
			g.draw_line(a.lerp(b, gt + gh), b, Color(1.0, 0.94, 0.82, al), 6.0)
		var gp: Vector2 = a.lerp(b, gt)
		g.draw_set_transform(gp, 0.0, Vector2(1.0, 0.6))
		g.draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 20, Color(1, 1, 1, minf(1.0, al * 1.6)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 塑路者的生路（path.gd 写 e.paths）：钢蓝折线（低亮度宽线 + 亮芯）、每段末端金色路标；截断的路变暗、断口画叉
static func _paths(g, e: Dictionary) -> void:
	for p in e.get("paths", []):
		var pts: Array = p.pts
		var cut: bool = p.cut
		var al: float = 0.18 if cut else 0.42
		var pa := PackedVector2Array(pts)
		g.draw_polyline(pa, Color(0.55, 0.65, 1.0, al * 0.6), 9.0)
		g.draw_polyline(pa, Color(0.8, 0.88, 1.0, al * 1.6), 2.0)
		for i in range(1, pts.size()):
			var q: Vector2 = pts[i]
			if cut and i == int(p.get("cut_i", -1)):
				g.draw_line(q + Vector2(-8, -8), q + Vector2(8, 8), Color(1.0, 0.85, 0.4, 0.9), 3.0)
				g.draw_line(q + Vector2(-8, 8), q + Vector2(8, -8), Color(1.0, 0.85, 0.4, 0.9), 3.0)
				continue
			var c := Color(1.0, 0.82, 0.3, 0.35 if cut else 1.0)
			g.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 0), q + Vector2(0, 9), q + Vector2(-7, 0)]), c)
			g.draw_polyline(PackedVector2Array([q + Vector2(0, -9), q + Vector2(7, 0), q + Vector2(0, 9), q + Vector2(-7, 0), q + Vector2(0, -9)]), Color(1, 1, 1, c.a), 1.5)


## 地面层：骑士的寒气圈（低亮度，0 区域样式：只提示「进来会涨寒冷」，不伤人）；卡门的封锁线；塑路者的生路
static func draw_ground(g) -> void:
	for e in g.bosses:
		if not e.dead and e.type == "carmen" and not e.get("fire_lines", []).is_empty():
			_fire_lines(g, e)
		if not e.dead and e.type == "path" and not e.get("paths", []).is_empty():
			_paths(g, e)
		if e.dead or e.type != "knight_boss" or float(e.get("kcold_r", 0.0)) <= 0.0:
			continue
		var r: float = float(e.kcold_r)
		var off: bool = float(e.get("break_t", 0.0)) > 0.0   # 破绽期不涨寒冷：圈变淡
		var al: float = 0.05 if off else 0.11
		g.draw_set_transform(e.pos, 0.0, Vector2(1.0, 0.72))
		g.draw_circle(Vector2.ZERO, r, Color(0.55, 0.85, 1.0, al))
		g.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.75, 0.95, 1.0, al * 2.6), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 顶层：主控脚下的寒冷条（骑士在场且寒冷 > 0 时）；满了之后「冻伤」期间整条变白
static func draw_top(g) -> void:
	for e in g.bosses:
		if e.dead or e.type != "knight_boss":
			continue
		var v: float = clampf(float(e.get("kcold", 0.0)), 0.0, 1.0)
		var bite: bool = float(e.get("frostbite_until", 0.0)) > g.t
		if v <= 0.01 and not bite:
			continue
		var p: Vector2 = g.ppos + Vector2(-22, 16)
		g.draw_rect(Rect2(p - Vector2(1, 1), Vector2(46, 6)), Color(0.02, 0.04, 0.08, 0.85))
		var c: Color = Color(0.95, 1.0, 1.0) if bite else Color(0.55, 0.85, 1.0).lerp(Color(0.9, 0.98, 1.0), v)
		g.draw_rect(Rect2(p, Vector2(44.0 * (1.0 if bite else v), 4)), c)
		return
