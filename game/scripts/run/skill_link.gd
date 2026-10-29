## 技能连携样片（用户 10-29，看完 final3 后定方向；只做样片，开关 balance combo/skill_link 缺省 0，现有连携系统不动）：
## 任一干员放 S1–S3 的那一刻开 ult/link_window（1.5）秒连携窗口，可接的队友头像亮起（走 ult 的亮起排队，info.link）；
## 按 E（或自动）后队友**接进这个技能**，合成一个强化版：
##   texas S1「剑雨」+ exusiai  → 能天使朝剑雨落点倾泻扫射，剑雨变成爆炸剑雨（每把剑落地炸开）
##   lappland S2「狼魂」+ texas → 两道剑气交叉成十字斩（「宿敌」）
## 表现（终结技之后也要用的「舞台」）：接上那一刻背景压暗到约 40%、镜头推到约 1.3、出手的队友放大 1.5 倍带残影、
## 合成特效粗一档、实心有体积、暖色（和青蓝环境拉开）。伤害按出手干员攻击力（同连携技口径），纯演出部分不碰随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const UM = preload("res://scripts/ui_motion.gd")

## 放技能的干员 id → {技能序号: [搭档 id, 合成类型]}
const LINKS := {
	"texas": {0: ["exusiai", "boom_rain"]},
	"lappland": {1: ["texas", "cross"]},
}
const WARM := Color(1.0, 0.55, 0.18)
const HOT := Color(1.0, 0.86, 0.45)
const CRIMSON := Color(1.0, 0.25, 0.22)


static func on() -> bool:
	return Bal.vi("combo/skill_link", 0) > 0


## squad.syn_skill → ult.on_skill：放技能的那一刻
static func on_skill(u, o, i: int) -> void:
	var t: Dictionary = LINKS.get(str(o.id), {})
	if not t.has(i):
		return
	var pid: String = str(t[i][0])
	var p = u.g.squad.get_op(pid)
	if p == null or p.pos == Vector2.INF or p.cmd_down > 0.0 or p == o or u._queued(p) or u._busy(p):
		return
	var pos: Vector2 = o.pos
	if str(t[i][1]) == "cross":
		pos = o.pos + Vector2(float(o.face), 0.0) * 140.0
	var info := {"link": str(t[i][1]), "from": o, "pos": pos, "skill": i}
	u.queue.push_front({"o": p, "info": info, "t0": u.g.t, "left": Bal.v("ult/link_window", 1.5)})   # 插到队首：技能连携优先
	u.stats.lit += 1
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play("ui_ok", -4.0, 1.25)


static func _dmg(o, mult: float) -> float:
	return o.base("atk", 0.0) * mult * o._dmg_bonus()


static func _src(o, kind: String) -> String:
	var k: String = "技能连携·%s·%s" % [kind, str(o.id)]
	if not o.g.hit_src.has(k):
		o.g.hit_src[k] = {"emitter": "operator", "origin": "skill", "range": "范围", "kind": "物理", "tags": ["skill", "连携"], "class": o.cls, "op": str(o.id)}
	return k


## 出手：返回动作（u.combo_acts 推进）
static func fire(u, p, info: Dictionary) -> Dictionary:
	var g = u.g
	u.stage(info.pos, p)
	var a := {"p": p, "link": info.link, "from": info.from, "pos": info.pos, "age": 0.0, "done": {}, "k": 0}
	if str(info.link) == "boom_rain":
		# 剑落点：剑雨范围里按序号排两圈（不抽随机数）
		var pts: Array = []
		for i in 14:
			var r: float = 90.0 if i < 5 else 210.0
			pts.append(info.pos + Vector2.from_angle(i * 2.39996) * r * (0.8 + 0.2 * float(i % 3)))
		a["pts"] = pts
	return a


## 每帧；true = 结束
static func step(u, a: Dictionary, dt: float) -> bool:
	a.age = float(a.age) + dt
	match str(a.link):
		"boom_rain":
			return _step_boom(u, a)
		"cross":
			return _step_cross(u, a)
	return true


## ① 爆炸剑雨：0–0.5 秒能天使扫射（粗曳光，暖色），0.35 秒起剑一把把落下、落地炸开（实心火球 + 爆裂帧条放大）
static func _step_boom(u, a: Dictionary) -> bool:
	var p = a.p
	var g = u.g
	var t: float = a.age
	var pts: Array = a.pts
	# 扫射：每 0.04 秒一道
	var shots: int = mini(12, int(t / 0.04))
	while int(a.k) < shots and int(a.k) < 12:
		var tp: Vector2 = pts[int(a.k) % pts.size()]
		var from: Vector2 = p.pos + Vector2(0, -20)
		u.shape({"kind": "line", "a": from, "b": tp, "w": 9.0, "col": HOT, "life": 0.14})
		u.shape({"kind": "line", "a": from, "b": tp, "w": 3.0, "col": Color.WHITE, "life": 0.1})
		a.k = int(a.k) + 1
	# 剑雨：第 i 把在 0.35 + 0.05 i 秒落地
	for i in pts.size():
		var land: float = 0.35 + 0.05 * i
		var key := "s%d" % i
		if t >= land - 0.15 and not a.done.has(key + "f"):
			a.done[key + "f"] = true
			u.strip("fx_ult_texas_sword_front", pts[i], {"o": Vector2(32, 224), "sc": 1.6, "seg": [0, 4], "col": Color(1.0, 0.85, 0.6)})
		if t >= land and not a.done.has(key):
			a.done[key] = true
			var c: Vector2 = pts[i]
			u.shape({"kind": "circle", "c": c, "r": 78.0, "col": WARM, "fill": 0.95, "life": 0.16})
			u.shape({"kind": "circle", "c": c, "r": 48.0, "col": HOT, "fill": 1.0, "life": 0.1})
			u.shape({"kind": "ring", "c": c, "r": 120.0, "r1": 30.0, "w": 9.0, "col": CRIMSON, "life": 0.35})
			u.strip("fx_ult_exusiai_burst_front", c, {"o": Vector2(64, 64), "sc": 2.6, "col": Color(1.0, 0.8, 0.55)})
			for e in u.in_circle(c, 85.0):
				p.log_hit(_src(p, "爆炸剑雨"), ["连携"])
				p.deal_damage(e, _dmg(p, Bal.v("ult/link_boom_mult", 1.2)))
			if i == 0:
				g.vfx.stop(0.06, "link", true)
	return t >= 0.35 + 0.05 * pts.size() + 0.4


## ② 十字斩：0–0.25 秒两道剑气（拉普兰德 / 德克萨斯各一道）从两侧画进来，0.3 秒交叉斩开（粗实心带 + 刀痕帧条），伤害两条带都算
static func _step_cross(u, a: Dictionary) -> bool:
	var p = a.p
	var o = a.from
	var t: float = a.age
	var c: Vector2 = a.pos
	var L := 900.0
	var d1 := Vector2.from_angle(PI / 4.0)
	var d2 := Vector2.from_angle(-PI / 4.0)
	if not a.done.has("pre"):
		a.done["pre"] = true
		u.shape({"kind": "band", "a": c - d1 * L * 0.5, "b": c + d1 * L * 0.5, "w": 26.0, "col": CRIMSON, "fill": 0.7, "life": 0.3})
		u.shape({"kind": "band", "a": c - d2 * L * 0.5, "b": c + d2 * L * 0.5, "w": 26.0, "col": HOT, "fill": 0.7, "life": 0.3})
	if t >= 0.3 and not a.done.has("cut"):
		a.done["cut"] = true
		for pair in [[d1, CRIMSON, o], [d2, HOT, p]]:
			var d: Vector2 = pair[0]
			var col: Color = pair[1]
			u.shape({"kind": "band", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": 150.0, "col": col, "fill": 0.92, "life": 0.3})
			u.shape({"kind": "band", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": 56.0, "col": Color.WHITE, "fill": 1.0, "life": 0.18})
			u.shape({"kind": "band", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": 230.0, "col": col, "fill": 0.28, "life": 0.55})   # 外圈余辉：有体积
			u.strip("fx_ult_texas_slash_front", c, {"o": Vector2(384, 40), "ang": d.angle(), "sx": L / 768.0, "sy": 3.6, "seg": [3, 7], "col": col.lerp(Color.WHITE, 0.3)})
			var who = pair[2] if pair[2] != null and pair[2].pos != Vector2.INF else p
			for e in u.in_band(c - d * L * 0.5, c + d * L * 0.5, 80.0):
				who.log_hit(_src(who, "十字斩"), ["连携"])
				who.deal_damage(e, _dmg(who, Bal.v("ult/link_cross_mult", 2.2)))
		u.shape({"kind": "circle", "c": c, "r": 150.0, "col": HOT, "fill": 1.0, "life": 0.16})
		u.shape({"kind": "ring", "c": c, "r": 260.0, "r1": 40.0, "w": 12.0, "col": CRIMSON, "life": 0.45})
		u.g.vfx.stop(0.09, "link", true)
	return t >= 0.85
