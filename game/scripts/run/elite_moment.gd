extends RefCounted
## 精英化时刻（docs/249 §2，开关 growth/elite_show，缺省 0 = 关：push 不会被调用，其余函数全部直接返回）。
## 选下精英化卡 → 关掉选卡面板回到战斗的那一刻：
##   1. 定格 freeze 秒（真实时间；只在玩家局，同顿帧：平衡 / 批跑不定格，不改任何模拟步长）；
##   2. 屏幕上方一条横幅「能天使 · 精英二」（精二且开了 growth/visible_nodes 时下面加一行全队效果）；
##   3. 干员本体爆亮（sprite 调色 ×(1 + 2.2k)，k 0.08 秒冲到 1 再落下）+ 身后一道本人颜色的光柱，脚下光池放大；
##   4. 之后常驻：脚下本人颜色的光池（精一小、精二更大更亮，带一圈细边；不外扩、不闪）。
## 让位规则（同 game.check_pending 的顺序）：终结技播放中 → 等播完；然后本时刻（定格中挡住后面的弹窗）→ 全屏精英化演出（show_queue）
## → 路线选择 → 宝箱 → 升级三选一。本时刻的计时只在 state == PLAY 时走：全屏演出期间停住，关掉后横幅淡出、光柱收尾。
## 颜色：本人颜色偏红（色相在红区且饱和）时向白调淡，红色只留给危险（docs/243 §2、用户 11-05）。
## 纯画面：不读写 g.rng，抖动只用 vrng；不改敌人 / 干员状态。

const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")

var g
var queue: Array = []      # [{op, stage}]
var cur: Dictionary = {}   # 正在播的：{op, stage, t, freeze, team}
var hist: Array = []       # 量测 / 截图：[{t: g.t, op, stage}]


func _init(game) -> void:
	g = game


static func on(gg) -> bool:
	return gg != null and Bal.v("growth/elite_show", 0.0) > 0.0


func push(op, stage: int) -> void:
	queue.append({"op": op, "stage": stage})


func _blocks() -> bool:
	## 只在玩家局定格（同顿帧口径）；平衡 / 批跑 / 图鉴演示照常推进，不挡弹窗，保证模拟步长和弹窗时刻与关时相同
	return (g.mode == g.Mode.PLAY or g.playclock_test) and g.demo_op == ""


## game.check_pending 调：有待播的就开播；定格中返回 true（挡住后面的全屏演出 / 选卡）
func pending() -> bool:
	if not cur.is_empty() and cur.t < cur.freeze:
		return _blocks()
	if queue.is_empty():
		return false
	var q: Dictionary = queue.pop_front()
	var st: int = int(q.stage)
	cur = {"op": q.op, "stage": st, "t": 0.0, "freeze": Bal.v("elite_show/freeze_e2", 0.7) if st >= 2 else Bal.v("elite_show/freeze_e1", 0.45), "team": ""}
	if st >= 2 and Bal.v("growth/visible_nodes", 0.0) > 0.0:
		cur.team = load("res://scripts/characters/blocks/vis_nodes.gd").team_text(q.op)
	hist.append({"t": snappedf(float(g.t), 0.01), "op": str(q.op.id), "stage": st})
	if q.op.pos != Vector2.INF:
		_burst(q.op, st)
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null   # 核心契约测试不加载自动加载单例（同 link_bond.gd）
	if sfx != null:
		sfx.play("levelup", -2.0, 0.8 if st >= 2 else 0.95, 0.0)
	return _blocks()


## 每帧（真实时间）：game._process 调。定格结束那一帧接着走 check_pending（弹出后面排着的全屏演出 / 选卡）
func tick(delta: float) -> void:
	if cur.is_empty() or g.state != g.S.PLAY:
		return
	var was: bool = cur.t < cur.freeze
	cur.t += delta
	if was and cur.t >= cur.freeze:
		g.check_pending()
	if cur.t > cur.freeze + 0.9:
		cur = {}


## 本时刻的横幅在场（hud_banners：普通横幅只是不画，计时照走，同 Boss 名片）
func banner_busy() -> bool:
	return not cur.is_empty() and g.state == g.S.PLAY and cur.t < cur.freeze + 0.6


## 定格中（game._process 用它跳过模拟步，同 hitstop 分支）
func freezing() -> bool:
	return not cur.is_empty() and cur.t < cur.freeze and _blocks()


## 本人颜色，偏红的向白调淡（红色只给危险）
static func safe_col(o) -> Color:
	var c: Color = o.col()
	var h: float = c.h
	if (h < 0.05 or h > 0.92) and c.s > 0.35:
		c = c.lerp(Color(1.0, 0.93, 0.86), 0.7)
	return c


## 设置「减少动态效果」（Cfg 是自动加载单例，核心契约测试里没有：按节点取）
func _reduce() -> bool:
	var c: Node = g.get_node_or_null("/root/Cfg") if g.is_inside_tree() else null
	return c != null and bool(c.get("reduce_motion"))


## 爆亮系数 0–1（character.draw_body 读）
func flash(o) -> float:
	if cur.is_empty() or cur.op != o:
		return 0.0
	var t: float = cur.t
	var k: float = clampf(t / 0.08, 0.0, 1.0) if t < 0.08 else exp(-(t - 0.08) * 3.2)
	return k * (0.55 if _reduce() else 1.0)


func _burst(o, st: int) -> void:
	## 一次性光点上升（只用 vrng；不外扩环）
	var c: Color = safe_col(o).lerp(Color.WHITE, 0.35)
	for k in (18 if st >= 2 else 10):
		o.fx({"kind": "mote", "pos": o.pos + Vector2(g.vrng.randf_range(-16, 16), g.vrng.randf_range(-6, 2)), "vel": Vector2(g.vrng.randf_range(-10, 10), -g.vrng.randf_range(70, 150)),
			"life": g.vrng.randf_range(0.6, 1.0), "col": Color(c.r * 1.3, c.g * 1.3, c.b * 1.3), "sz": g.vrng.randf_range(1.6, 2.6), "keep": true})


# ---------------------------------------------------------------- 绘制

## 脚下光池（squad.draw_shadows，在影子之前）：常驻 + 时刻里的放大与光柱
func draw_ground(o, cv) -> void:
	if o.pos == Vector2.INF:
		return
	var el: int = int(o.elite)
	var mk: float = 0.0
	if not cur.is_empty() and cur.op == o:
		var t: float = cur.t
		mk = clampf(t / 0.1, 0.0, 1.0) * clampf(1.0 - (t - cur.freeze) / 0.9, 0.0, 1.0)
	if el <= 0 and mk <= 0.0:
		return
	var c: Color = safe_col(o)
	var big: bool = el >= 2
	var r: float = (27.0 if big else 19.0) * (1.0 + 0.35 * mk)
	var a: float = (0.36 if big else 0.26) + 0.3 * mk
	var p: Vector2 = o.pos + Vector2(0, 4)
	cv.draw_set_transform(p, 0.0, Vector2(1.0, 0.45))
	cv.draw_circle(Vector2.ZERO, r, Color(c.r, c.g, c.b, a * 0.45))
	cv.draw_circle(Vector2.ZERO, r * 0.66, Color(c.r, c.g, c.b, a * 0.6))
	cv.draw_circle(Vector2.ZERO, r * 0.34, Color(minf(1.0, c.r * 1.3), minf(1.0, c.g * 1.3), minf(1.0, c.b * 1.3), a * 0.8))
	if big:
		cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(minf(1.0, c.r * 1.25), minf(1.0, c.g * 1.25), minf(1.0, c.b * 1.25), 0.55 + 0.3 * mk), 1.5)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fl: float = flash(o)
	if fl > 0.0:
		# 爆亮：身后一团静止的本人颜色亮光（在本体之前画 = 在人身后；不外扩）
		var cb := Color(minf(1.0, c.r * 0.5 + 0.6), minf(1.0, c.g * 0.5 + 0.6), minf(1.0, c.b * 0.5 + 0.6), 0.0)
		for i in 3:
			cb.a = fl * (0.22 + 0.18 * i)
			cv.draw_circle(p + Vector2(0, -24), 30.0 - 8.0 * i, cb)
	if mk > 0.0:
		# 身后光柱：底宽 22、高 120，向上变细变淡（画在本体之前 = 在人身后）
		var h: float = 120.0 * (0.6 + 0.4 * mk)
		for i in 4:
			var w: float = (11.0 - i * 2.5) * (0.7 + 0.3 * mk)
			var ca := Color(minf(1.0, c.r * 1.2 + 0.15 * i), minf(1.0, c.g * 1.2 + 0.15 * i), minf(1.0, c.b * 1.2 + 0.15 * i), mk * (0.16 + 0.1 * i))
			cv.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(w, 0), p + Vector2(w * 0.35, -h), p + Vector2(-w * 0.35, -h)]), ca)


## 横幅（hud.gd，在指点 / 终结技瞄准之后、整屏状态界面之前）
func draw_hud(vs: Vector2) -> void:
	if cur.is_empty() or g.state != g.S.PLAY:
		return
	var t: float = cur.t
	var a: float = clampf(t / 0.12, 0.0, 1.0) * clampf(1.0 - (t - cur.freeze - 0.2) / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	var o = cur.op
	var st: int = int(cur.stage)
	var c: Color = safe_col(o)
	var y: float = vs.y * 0.22   # 与普通横幅同一带：横幅在场时普通横幅让位（hud_banners 读 banner_busy，计时照走）
	var sw: float = clampf(t / 0.22, 0.0, 1.0) if not _reduce() else 1.0
	var hgt: float = 74.0 if str(cur.team) == "" else 96.0
	var hud = g.hud
	hud.draw_rect(Rect2(0, y, vs.x * sw, hgt), Color(0.02, 0.03, 0.05, 0.62 * a))
	hud.draw_rect(Rect2(0, y, vs.x * sw, 2), Color(c.r, c.g, c.b, 0.95 * a))
	hud.draw_rect(Rect2(0, y + hgt - 2, vs.x * sw, 2), Color(c.r, c.g, c.b, 0.5 * a))
	UI.en(hud, g.font, Vector2(vs.x * 0.5 - 90, y + 20), "ELITE  PROMOTION  " + ["", "I", "II"][clampi(st, 0, 2)], 12, Color(c.r, c.g, c.b, a), 4.0)
	UI.text(hud, g.font, Vector2(0, y + 54), "%s · 精英%s" % [o.display_name(), ["", "一", "二"][clampi(st, 0, 2)]], 30, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	if str(cur.team) != "":
		UI.text(hud, g.font, Vector2(0, y + 82), "全队效果：" + str(cur.team) if not str(cur.team).begins_with("全队") else str(cur.team), 16, Color(0.85, 0.92, 0.95, a), HORIZONTAL_ALIGNMENT_CENTER, vs.x)
