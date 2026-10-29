## 技能连携样片（用户 10-29，看完 final3 后定方向；只做样片，开关 balance combo/skill_link 缺省 0，现有连携系统不动）：
## 任一干员放 S1–S3 的那一刻开 ult/link_window（1.5）秒连携窗口，可接的队友头像亮起（走 ult 的亮起排队，info.link）；
## 按 E（或自动）后队友**接进这个技能**，合成一个强化版：
##   texas S1「剑雨」+ exusiai  → 能天使朝剑雨落点倾泻扫射，剑雨变成爆炸剑雨（每把剑落地炸开）
##   lappland S2「狼魂」+ texas → 两道剑气交叉成十字斩（「宿敌」）
## 层级（用户 10-29 返工：「连携技变成大招一样了，范围太大了」）：普攻 < 技能 < 技能连携 < 终结技，只有终结技是全屏级。
## 范围 = 原技能 ×1.3（剑雨原圈 130 → 约 170；十字斩长约 480、主体宽约 90），伤害约「原技能 + 50%」；一局 20–30 次，要轻要快：
## 舞台减半（压暗到约 75%、0.45 秒、推镜 1.1、出手队友 ×1.25 两层残影），不出立绘条带、不慢放。
## 辨识度靠两人合力：两人各自的干员色在合成点交汇（剑身带能天使的曳光色、十字两道各是两人的颜色）+ 合成瞬间一个短促双色闪 + 专属音效。
## 伤害按出手干员攻击力（同连携技口径），纯演出部分不碰随机数。
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
		var dp: Vector2 = u._densest(o.pos, 240.0, 110.0)   # 十字交点：身前 240 内最密的一团（没有就身前 120）
		pos = dp if dp != Vector2.INF else o.pos + Vector2(float(o.face), 0.0) * 120.0
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
	u.stage(info.pos, p)
	var a := {"p": p, "link": info.link, "from": info.from, "pos": info.pos, "age": 0.0, "done": {}, "k": 0}
	if str(info.link) == "boom_rain":
		var R: float = float(info.from.base("s1_r", 130.0)) * Bal.v("ult/link_range", 1.3)
		var pts: Array = []
		for i in 9:   # 内 3 外 6，按序号排、不抽随机数
			var r: float = R * (0.35 if i < 3 else 0.85)
			pts.append(info.pos + Vector2.from_angle(i * 2.39996) * r)
		a["pts"] = pts
		a["R"] = R
	return a


## 合成瞬间：两人颜色的短促双色闪 + 专属音效
static func _merge_flash(u, c: Vector2, c1: Color, c2: Color, r: float) -> void:
	u.shape({"kind": "circle", "c": c, "r": r, "col": c1, "fill": 0.85, "life": 0.08})
	u.shape({"kind": "ring", "c": c, "r": r * 1.6, "r1": r * 0.5, "w": 6.0, "col": c2, "life": 0.18})
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play("crit_tick", -2.0, 0.7)
		sfx.play("hit", -4.0, 1.35)


## 每帧；true = 结束
static func step(u, a: Dictionary, dt: float) -> bool:
	a.age = float(a.age) + dt
	match str(a.link):
		"boom_rain":
			return _step_boom(u, a)
		"cross":
			return _step_cross(u, a)
	return true


## ① 爆炸剑雨：能天使 6 道曳光（她的颜色）打进剑雨圈 → 9 把剑落下（剑身带她的曳光色）、落地小爆（两人颜色）
static func _step_boom(u, a: Dictionary) -> bool:
	var p = a.p
	var o = a.from
	var t: float = a.age
	var pts: Array = a.pts
	var cp: Color = u._col(p)
	var co: Color = u._col(o) if o != null else HOT
	var shots: int = mini(6, int(t / 0.03))
	while int(a.k) < shots:
		var tp: Vector2 = pts[int(a.k) % pts.size()]
		u.shape({"kind": "line", "a": p.pos + Vector2(0, -20), "b": tp, "w": 4.0, "col": cp.lerp(Color.WHITE, 0.3), "life": 0.1})
		a.k = int(a.k) + 1
	if not a.done.has("merge") and t >= 0.18:
		a.done["merge"] = true
		_merge_flash(u, a.pos, co.lerp(Color.WHITE, 0.4), cp, 46.0)
	for i in pts.size():
		var land: float = 0.2 + 0.035 * i
		var key := "s%d" % i
		if t >= land - 0.12 and not a.done.has(key + "f"):
			a.done[key + "f"] = true
			u.strip("fx_ult_texas_sword_front", pts[i], {"o": Vector2(32, 224), "sc": 1.0, "seg": [0, 4], "col": co.lerp(cp, 0.45)})
			u.shape({"kind": "line", "a": pts[i] + Vector2(0, -150), "b": pts[i], "w": 3.0, "col": cp, "life": 0.12})   # 剑身带能天使的曳光
		if t >= land and not a.done.has(key):
			a.done[key] = true
			var c: Vector2 = pts[i]
			u.shape({"kind": "circle", "c": c, "r": 34.0, "col": cp, "fill": 0.9, "life": 0.1})
			u.shape({"kind": "ring", "c": c, "r": 52.0, "r1": 16.0, "w": 4.0, "col": co.lerp(Color.WHITE, 0.3), "life": 0.2})
			u.strip("fx_ult_exusiai_burst_front", c, {"o": Vector2(64, 64), "sc": 1.2})
			for e in u.in_circle(c, 46.0):
				p.log_hit(_src(p, "爆炸剑雨"), ["连携"])
				p.deal_damage(e, _dmg(p, Bal.v("ult/link_boom_mult", 0.8)))
	return t >= 0.2 + 0.035 * pts.size() + 0.25


## ② 十字斩：两道剑气各是两人的干员色（拉普兰德 / 德克萨斯），0.15 秒画进来、0.18 秒交叉斩开；长约 480、主体宽约 90
static func _step_cross(u, a: Dictionary) -> bool:
	var p = a.p
	var o = a.from
	var t: float = a.age
	var c: Vector2 = a.pos
	var L: float = Bal.v("ult/link_cross_len", 480.0)
	var W: float = Bal.v("ult/link_cross_w", 90.0)
	var d1 := Vector2.from_angle(PI / 4.0)
	var d2 := Vector2.from_angle(-PI / 4.0)
	var c1: Color = u._col(o) if o != null else CRIMSON
	var c2: Color = u._col(p)
	if not a.done.has("pre"):
		a.done["pre"] = true
		u.shape({"kind": "band", "a": c - d1 * L * 0.5, "b": c + d1 * L * 0.5, "w": 8.0, "col": c1, "fill": 0.6, "life": 0.18})
		u.shape({"kind": "band", "a": c - d2 * L * 0.5, "b": c + d2 * L * 0.5, "w": 8.0, "col": c2, "fill": 0.6, "life": 0.18})
	if t >= 0.18 and not a.done.has("cut"):
		a.done["cut"] = true
		for pair in [[d1, c1, o], [d2, c2, p]]:
			var d: Vector2 = pair[0]
			var col: Color = pair[1]
			u.shape({"kind": "band", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": W, "col": col, "fill": 0.85, "life": 0.18})
			u.shape({"kind": "band", "a": c - d * L * 0.5, "b": c + d * L * 0.5, "w": W * 0.3, "col": Color.WHITE, "fill": 0.95, "life": 0.1})
			u.strip("fx_ult_texas_slash_front", c, {"o": Vector2(384, 40), "ang": d.angle(), "sx": L / 768.0, "sy": W / 80.0, "seg": [3, 7], "col": col.lerp(Color.WHITE, 0.25)})
			var who = pair[2] if pair[2] != null and pair[2].pos != Vector2.INF else p
			for e in u.in_band(c - d * L * 0.5, c + d * L * 0.5, W * 0.5):
				who.log_hit(_src(who, "十字斩"), ["连携"])
				who.deal_damage(e, _dmg(who, Bal.v("ult/link_cross_mult", 1.5)))
		_merge_flash(u, c, c1.lerp(Color.WHITE, 0.4), c2, 40.0)
		u.g.vfx.stop(0.05, "link", true)
	return t >= 0.5
