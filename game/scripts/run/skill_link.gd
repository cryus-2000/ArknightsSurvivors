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
		_sample_lit(u, o, i)   # 四类样片：表里没有专属组合时，按在队的接法干员亮
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
	var a := {"p": p, "link": info.link, "from": info.from, "pos": info.pos, "r": info.get("r", 150.0), "age": 0.0, "done": {}, "k": 0}
	if SAMPLE.values().has(str(info.link)):
		_fire_sample(u, p, info, a)
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
		"pursue", "lava", "gather", "cover":
			return _step_sample(u, a)
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

# ================================================================ 四类样片（协调人 10-29「先看样片再定」）：主技能用队长现有技能，接的人按类出手
## 规则：① 接的干员本人出现在画面里做动作；② 0.5–1 秒结束、范围只比原技能大一点；③ 不碰她终结技 / S1–S3 的标志元素。
## 技能区域：队长放技能那一刻，身边 260 内最密的一团（半径 ult/link_area_r 150）；没有敌人就不亮
const SAMPLE := {"texas": "pursue", "eyjafjalla": "lava", "gladiia": "gather", "hoshiguma": "cover"}
const LAVA := Color(1.0, 0.42, 0.12)
const MOLTEN := Color(1.0, 0.93, 0.6)    # 连携熔岩弹：白金芯 + 暗红描边（她自己技能的熔岩池是橙色圆片，连携换形态 / 颜色跳出来）
const MOLTEN_RIM := Color(0.45, 0.04, 0.06)
const PRE := 0.18    # 现身：接的人先亮起 0.18 秒再出手（用户 10-29「展示的可以稍微久一点」）
const HOOK := Color(0.35, 0.85, 0.95)
const AMBER := Color(1.0, 0.72, 0.3)


static func _sample_lit(u, o, i: int) -> void:
	var area_r: float = Bal.v("ult/link_area_r", 150.0)
	var c: Vector2 = u._densest(o.pos, 260.0, area_r)
	if c == Vector2.INF:
		return
	for p in u.g.squad.ops:
		var kind: String = str(SAMPLE.get(str(p.id), ""))
		if kind == "" or p == o or p.is_leader or p.pos == Vector2.INF or p.cmd_down > 0.0 or u._queued(p) or u._busy(p):
			continue
		u.queue.push_front({"o": p, "info": {"link": kind, "from": o, "pos": c, "r": area_r, "skill": i}, "t0": u.g.t, "left": Bal.v("ult/link_window", 1.5)})
		u.stats.lit += 1
		var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
		if sfx != null:
			sfx.play("ui_ok", -4.0, 1.25)
		return


## 区域里的主目标：精英 / Boss 优先，其次离中心最近
static func _main(u, c: Vector2, r: float) -> Variant:
	var best: Variant = null
	var bd := INF
	for e in u.in_circle(c, r):
		var d: float = e.pos.distance_to(c) - (10000.0 if (e.elite or e.boss) else 0.0)
		if d < bd:
			bd = d
			best = e
	return best


static func _fire_sample(u, p, info: Dictionary, a: Dictionary) -> void:
	var c: Vector2 = info.pos
	var r: float = float(info.r)
	match str(info.link):
		"pursue":
			var tg: Variant = _main(u, c, r)
			a["tg"] = tg
		"gather":
			var outs: Array = []
			for e in u.in_circle(c, r + 210.0):
				if e.pos.distance_to(c) > r and not e.boss:
					outs.append(e)
			outs.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
			a["pull"] = outs.slice(0, 6)
		"cover":
			var taunt: Array = []
			for e in u.in_circle(c, r):
				if str(e.get("ai", "")) == "melee" and not e.boss:
					taunt.append(e)
			a["taunt"] = taunt


## 现身（0..PRE）：接的人脚下干员色光柱 + 收拢光环，告诉玩家「谁来了」
static func _appear(u, p, t: float) -> void:
	var cp: Color = u._col(p)
	var k: float = clampf(t / PRE, 0.0, 1.0)
	u.shape({"kind": "ring", "c": p.pos, "r": lerpf(70.0, 26.0, k), "w": 4.0, "col": cp.lerp(Color.WHITE, 0.3), "life": 0.04})
	u.shape({"kind": "band", "a": p.pos + Vector2(0, 6), "b": p.pos + Vector2(0, -90), "w": 22.0 * (1.0 - 0.5 * k), "col": cp, "fill": 0.35, "life": 0.04})


## 出手瞬间：轻微放慢（比终结技弱一档）
static func _beat(u) -> void:
	u.link_slow()


static func _step_sample(u, a: Dictionary) -> bool:
	var p = a.p
	var t0: float = a.age
	if t0 < PRE:
		_appear(u, p, t0)
		return false
	var t: float = t0 - PRE
	var c: Vector2 = a.pos
	var r: float = float(a.get("r", 150.0))
	var cp: Color = u._col(p)
	match str(a.link):
		"pursue":   # 德克萨斯：瞬身穿过主目标到其身后 120（0.12 秒），留橙色直线短斩痕，残留 0.6 秒
			if not a.done.has("go"):
				a.done["go"] = true
				var tg: Variant = a.tg
				var tp: Vector2 = tg.pos if tg != null and not tg.dead else c
				var d: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["from_p"] = p.pos
				a["to_p"] = tp + d * 120.0
				p.syn_mv = {"from": p.pos, "to": a.to_p, "t": 0.0, "dur": 0.12}
				p.cmd_inv = maxf(p.cmd_inv, 0.5)
				p._set_face(1.0 if d.x >= 0.0 else -1.0, true)
				p.play_vis_anim("attack")
			if t >= 0.12 and not a.done.has("cut"):
				a.done["cut"] = true
				_beat(u)
				var tg2: Variant = a.tg
				var mid: Vector2 = tg2.pos if tg2 != null and not tg2.dead else (Vector2(a.from_p) + Vector2(a.to_p)) * 0.5
				var d2: Vector2 = (Vector2(a.to_p) - Vector2(a.from_p)).normalized()
				u.shape({"kind": "blade", "a": mid - d2 * 110.0, "b": mid + d2 * 110.0, "w": 7.0, "col": Color.WHITE, "glow": cp, "grow": 0.03, "life": 0.7})
				u.shape({"kind": "line", "a": a.from_p, "b": a.to_p, "w": 4.0, "col": cp, "life": 0.45})
				for e in u.in_band(a.from_p, a.to_p, 34.0):
					p.log_hit(_src(p, "追击"), ["连携"])
					p.deal_damage(e, _dmg(p, Bal.v("ult/link_pursue_mult", 1.6)))
					if not e.dead and not e.boss:
						p.add_cc(e, 0.5 * (0.5 if e.elite else 1.0))
				u.g.vfx.stop(0.04, "link", true)
			return t >= 0.85
		"lava":   # 艾雅法拉：抬杖 → 白金熔岩弹（暗红描边 + 拖尾）0.32 秒抛进区域 → 星芒炸开 + 点燃，余辉 0.6 秒
			var T := 0.32
			if not a.done.has("go"):
				a.done["go"] = true
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				a["from_p"] = p.pos + Vector2(float(p.face) * 10.0, -44.0)
				u.shape({"kind": "circle", "c": a.from_p, "r": 20.0, "col": MOLTEN, "fill": 0.95, "life": 0.2})
			if t < T:
				var k: float = t / T
				var pos: Vector2 = Vector2(a.from_p).lerp(c, k) + Vector2(0, -110.0 * sin(PI * k))
				u.shape({"kind": "circle", "c": pos, "r": 17.0, "col": MOLTEN_RIM, "fill": 1.0, "life": 0.05})
				u.shape({"kind": "circle", "c": pos, "r": 12.0, "col": MOLTEN, "fill": 1.0, "life": 0.05})
				u.shape({"kind": "circle", "c": pos, "r": 6.0, "col": MOLTEN, "fill": 0.6, "life": 0.35})   # 拖尾：每帧留一个小点、慢慢淡
				return false
			if not a.done.has("hit"):
				a.done["hit"] = true
				_beat(u)
				var hr: float = r * 0.75
				u.shape({"kind": "circle", "c": c, "r": hr * 0.55, "col": MOLTEN, "fill": 0.9, "life": 0.22})
				u.shape({"kind": "ring", "c": c, "r": hr, "r1": 24.0, "w": 6.0, "col": MOLTEN_RIM, "life": 0.6})
				for k2 in 8:   # 星芒：八道白金短线往外射（不是她技能那种橙色圆片）
					var sd: Vector2 = Vector2.from_angle(k2 * TAU / 8.0 + 0.2)
					u.shape({"kind": "blade", "a": c + sd * 18.0, "b": c + sd * hr * 0.95, "w": 6.0, "col": MOLTEN, "glow": MOLTEN_RIM, "grow": 0.05, "life": 0.6})
					u.shape({"kind": "circle", "c": c + sd * hr * 0.5, "r": 6.0, "col": MOLTEN, "fill": 0.95, "life": 0.7, "v": sd * 140.0 + Vector2(0, -60)})
				var burn: Array = u.in_circle(c, hr)
				a["burn"] = burn
				for e in burn:
					p.log_hit(_src(p, "熔岩"), ["连携"])
					p.deal_damage(e, _dmg(p, Bal.v("ult/link_lava_mult", 1.0)))
			for j in 2:
				var tj: float = T + 0.3 * (j + 1)
				var key := "b%d" % j
				if t >= tj and not a.done.has(key):
					a.done[key] = true
					for e in a.burn:
						if e.dead:
							continue
						p.log_hit(_src(p, "点燃"), ["连携"])
						p.deal_damage(e, _dmg(p, Bal.v("ult/link_burn_mult", 0.25)))
						u.shape({"kind": "circle", "c": e.pos + Vector2(0, -14), "r": 6.0, "col": MOLTEN, "fill": 0.95, "life": 0.4, "v": Vector2(0, -50)})
			return t >= T + 0.9
		"gather":   # 歌蕾蒂娅：甩钩 0.14 秒 → 拖 0.36 秒 → 落地，钩索残留 0.5 秒慢慢收
			var pull: Array = a.pull
			if not a.done.has("go"):
				a.done["go"] = true
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("attack")
			if t < 0.14:
				for e in pull:
					if not e.dead:
						u.shape({"kind": "line", "a": p.pos + Vector2(0, -20), "b": Vector2(p.pos).lerp(e.pos, t / 0.14), "w": 3.0, "col": HOOK, "life": 0.04})
				return false
			if t < 0.5:
				if not a.done.has("beat"):
					a.done["beat"] = true
					_beat(u)
				for e in pull:
					if e.dead:
						continue
					var to: Vector2 = c + (e.pos - c).normalized() * r * 0.45
					p.nudge(e, (to - e.pos) * 0.22)
					u.shape({"kind": "line", "a": p.pos + Vector2(0, -20), "b": e.pos, "w": 3.0, "col": HOOK, "life": 0.04})
					u.shape({"kind": "circle", "c": e.pos, "r": 6.0, "col": HOOK, "fill": 1.0, "life": 0.04})
				return false
			if not a.done.has("land"):
				a.done["land"] = true
				u.shape({"kind": "ring", "c": c, "r": r, "r1": r * 0.4, "w": 4.0, "col": HOOK, "life": 0.5})
				for e in pull:
					if not e.dead:
						u.shape({"kind": "line", "a": p.pos + Vector2(0, -20), "b": e.pos, "w": 2.0, "col": HOOK, "life": 0.5})   # 钩索残留
						p.log_hit(_src(p, "聚拢"), ["连携"])
						p.deal_damage(e, _dmg(p, Bal.v("ult/link_gather_mult", 0.6)))
						if not e.boss:
							p.add_cc(e, 0.4 * (0.5 if e.elite else 1.0))
			return t >= 1.0
		"cover":   # 星熊：瞬到队长身侧（0.1 秒）举盾 1.0 秒、盾面再淡出 0.5 秒；挡一次 + 嘲讽区域内近战 1 秒
			var lp: Vector2 = u.g.ppos
			if not a.done.has("go"):
				a.done["go"] = true
				var ld = u.g.squad.leader()
				var ne: Variant = _main(u, lp, 300.0)
				var side: Vector2 = ((ne.pos - lp).normalized() if ne != null else Vector2(float(ld.face) if ld != null else 1.0, 0.0))
				a["side"] = side
				p.syn_mv = {"from": p.pos, "to": lp + side * 46.0, "t": 0.0, "dur": 0.1}
				p.cmd_inv = maxf(p.cmd_inv, 1.2)
				p._set_face(1.0 if side.x >= 0.0 else -1.0, true)
				p.play_vis_anim("skill")
				a["shield0"] = int(u.g.shield)
				u.g.shield = int(u.g.shield) + 1
			var side2: Vector2 = a.side
			if t >= 0.1 and not a.done.has("beat"):
				a.done["beat"] = true
				_beat(u)
				for e in a.taunt:
					if not e.dead:
						u.shape({"kind": "line", "a": e.pos + Vector2(0, -24), "b": e.pos + Vector2(0, -38), "w": 3.0, "col": AMBER, "life": 1.0})
			if t < 1.5:
				var fa: float = 1.0 if t < 1.0 else 1.0 - (t - 1.0) / 0.5
				u.shape({"kind": "sector", "c": lp + side2 * 46.0, "r": 60.0, "a": side2.angle(), "half": 0.9, "col": AMBER, "fill": 0.5 * fa, "life": 0.04})
				u.shape({"kind": "line", "a": lp + side2 * 46.0 + side2.orthogonal() * 42.0, "b": lp + side2 * 46.0 - side2.orthogonal() * 42.0, "w": 5.0, "col": Color(AMBER, fa), "life": 0.04})
				if t < 1.0:
					for e in a.taunt:
						if not e.dead:
							u.g.enemies_sys.set_aggro(e, p.pos)
			if t >= 1.5 and not a.done.has("unshield"):
				a.done["unshield"] = true
				if int(u.g.shield) > int(a.shield0):
					u.g.shield = int(u.g.shield) - 1
			return t >= 1.5
	return true
