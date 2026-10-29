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
	if str(a.link).begins_with("l_"):
		return _step16(u, a)
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
const SAMPLE := {"texas": "pursue", "eyjafjalla": "lava", "gladiia": "gather", "hoshiguma": "cover",
	# 其余 16 人（10-30 协调人「连携补齐 20 人」；接法与做法见 docs/199 §7.5，不碰各人终结技 / S1–S3 标志元素）
	"lappland": "l_lappland", "specter_unchained": "l_specter", "irene": "l_irene", "mizuki": "l_mizuki", "skadi": "l_skadi", "siege": "l_siege",
	"exusiai": "l_exusiai", "wisadel": "l_wisadel", "logos": "l_logos", "suzuran": "l_suzuran",
	"angelina": "l_angelina",
	"ulpianus": "l_ulpianus", "saria": "l_saria", "kaltsit": "l_kaltsit", "lumen": "l_lumen", "skalter": "l_skalter"}
## 每人所属四类（文档 / 遥测用）
const KIND4 := {"texas": "追击", "lappland": "追击", "specter_unchained": "追击", "irene": "追击", "mizuki": "追击", "skadi": "追击", "siege": "追击",
	"eyjafjalla": "附加", "exusiai": "附加", "wisadel": "附加", "logos": "附加", "suzuran": "附加",
	"gladiia": "聚拢", "angelina": "聚拢",
	"hoshiguma": "掩护", "ulpianus": "掩护", "saria": "掩护", "kaltsit": "掩护", "lumen": "掩护", "skalter": "掩护"}
const LAVA := Color(1.0, 0.42, 0.12)
## 连携熔岩块（用户 10-30「没有熔岩的力量感」）：暗红岩壳 + 裂缝透亮橙 + 橙白芯，沉甸甸地抛过去；
## 她自己技能的熔岩池是亮橙圆片，这里主体是暗色岩块（形态 / 明度跳开，不用白金）
const CRUST := Color(0.15, 0.045, 0.035)
const CRACK := Color(1.0, 0.45, 0.1)
const CORE := Color(1.0, 0.8, 0.45)
const SMOKE := Color(0.32, 0.27, 0.26)
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
	if str(info.link).begins_with("l_"):
		a["tg"] = _main(u, c, r)
		return
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
	u.grain("mote_up", p.pos + Vector2(0, -10), Vector2.UP, cp, 1)   # 光柱里往上飘的光点（光学观感）
	u.light(p.pos, 90.0, cp, 0.05)


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
				for q in 6:   # 斩痕上迸刀光颗粒 + 一盏短灯
					u.grain("blade", mid + d2 * (q - 2.5) * 36.0, d2.orthogonal() * (1.0 if q % 2 == 0 else -1.0), cp, 3)
				u.light(mid, 180.0, cp, 0.35)
				for e in u.in_band(a.from_p, a.to_p, 34.0):
					p.log_hit(_src(p, "追击"), ["连携"])
					p.deal_damage(e, _dmg(p, Bal.v("ult/link_pursue_mult", 1.6)))
					if not e.dead and not e.boss:
						p.add_cc(e, 0.5 * (0.5 if e.elite else 1.0))
				u.g.vfx.stop(0.04, "link", true)
			return t >= 0.85
		"lava":   # 艾雅法拉：抬杖 → 熔岩块（约 2 倍大、旋转、滴火星冒烟、地上有影子）0.42 秒砸进区域 → 顿帧 + 碎岩迸溅 + 熔岩溅落灼地 → 两跳点燃
			var T := 0.42
			var R: float = Bal.v("ult/link_lava_rock_r", 42.0)
			if not a.done.has("go"):
				a.done["go"] = true
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				a["from_p"] = p.pos + Vector2(float(p.face) * 10.0, -44.0)
				u.grain("fire", a.from_p, Vector2.UP, Color.WHITE, 8)
				u.light(a.from_p, 120.0, CRACK, 0.3)
				var rock := {"kind": "rock", "c": a.from_p, "r": R * 0.5, "col": CRUST, "glow": CRACK, "core": CORE, "seed": 3.0, "life": T + 0.2}
				var shadow := {"kind": "ellipse", "c": p.pos, "rx": R, "ry": R * 0.4, "col": Color(0.04, 0.02, 0.02), "fill": 0.45, "hold": true, "layer": "back", "life": T + 0.2}
				u.shape(rock)
				u.shape(shadow)
				a["rock"] = rock
				a["shadow"] = shadow
			if t < T:
				var k: float = t / T
				var gp: Vector2 = Vector2(a.from_p).lerp(c, k)   # 地面投影
				var hgt: float = 140.0 * sin(PI * k)
				var pos: Vector2 = gp + Vector2(0, -hgt)
				var rock: Dictionary = a.rock
				rock.c = pos
				rock.r = R * minf(1.0, 0.5 + k * 3.0)   # 出手时从杖头长大
				rock.rot = k * 5.0
				var sh: Dictionary = a.shadow
				sh.c = gp + Vector2(0, 10)
				sh.fill = 0.2 + 0.35 * k
				u.grain("bfx_dust", pos + Vector2(0, -R * 0.4), Vector2.UP, SMOKE, 1)   # 拖烟
				u.grain("lava", pos, Vector2.DOWN, Color.WHITE, 2)
				if int(t * 60.0) % 3 == 0:
					u.spark(pos + Vector2(0, R * 0.5), CRACK, 1, hgt)   # 往下滴的火星，落到地面
				u.light(gp, 120.0, CRACK, 0.06)   # 灯打在地面投影上（照在岩块上会把暗壳照成亮红）
				return false
			if not a.done.has("hit"):
				a.done["hit"] = true
				a.rock.life = 0.0
				a.rock.max = 0.0
				a.shadow.max = 0.0
				_beat(u)
				u.g.vfx.stop(0.07, "link", true)   # 砸地顿一下
				var hr: float = r * 0.75
				u.light(c, 300.0, CRACK, 0.7)
				u.debris(c, CRACK, 3)
				u.grain("lava", c, Vector2.UP, Color.WHITE, 40)
				u.grain("bfx_dust", c, Vector2.UP, SMOKE, 18)
				u.spark(c + Vector2(0, -6), CRACK, 14, 8.0)
				# 冲击：一圈压扁的亮橙冲击带（碎裂）+ 中心一团橙白
				u.shape({"kind": "ring", "c": c, "r": hr, "r1": 30.0, "w": 9.0, "col": CRACK, "life": 0.4})
				u.shape({"kind": "rock", "c": c, "r": R * 0.9, "col": CRACK, "glow": CORE, "core": CORE, "seed": 7.0, "hold": false, "life": 0.18})
				# 碎岩迸溅：岩块带重力往外飞
				for k2 in 9:
					var ang: float = k2 * TAU / 9.0 + 0.3
					var sd: Vector2 = Vector2.from_angle(ang)
					var sp: float = 160.0 + 70.0 * fposmod(k2 * 0.618, 1.0)
					u.shape({"kind": "rock", "c": c + sd * 14.0, "r": 7.0 + 6.0 * fposmod(k2 * 0.37, 1.0), "col": CRUST, "glow": CRACK, "seed": 11.0 + k2,
						"spin": 6.0, "v": sd * sp + Vector2(0, -170.0), "grav": 620.0, "hold": false, "life": 0.55})
				# 熔岩溅落灼地（地面层，压在怪脚下）：几块不规则暗红斑 + 亮橙点，慢慢冷却
				for k3 in 6:
					var ang3: float = k3 * TAU / 6.0 + 0.8
					var off: Vector2 = Vector2.from_angle(ang3) * hr * (0.25 + 0.45 * fposmod(k3 * 0.618, 1.0))
					var sz: float = 14.0 + 10.0 * fposmod(k3 * 0.41, 1.0)
					u.shape({"kind": "ellipse", "c": c + off, "rx": sz, "ry": sz * 0.55, "col": Color(0.22, 0.05, 0.03), "fill": 0.75, "layer": "back", "life": 1.6})
					u.shape({"kind": "ellipse", "c": c + off, "rx": sz * 0.45, "ry": sz * 0.25, "col": CRACK, "fill": 0.9, "layer": "back", "life": 0.9})
				u.shape({"kind": "ellipse", "c": c, "rx": R * 1.3, "ry": R * 0.6, "col": Color(0.2, 0.05, 0.03), "fill": 0.8, "layer": "back", "life": 1.8})
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
						u.grain("fire", e.pos + Vector2(0, -12), Vector2.UP, Color.WHITE, 3)
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
				u.light(c, 220.0, HOOK, 0.4)
				for e in pull:
					if not e.dead:
						u.grain("water", e.pos, Vector2.UP, HOOK, 6)   # 被拖到的怪落地溅水
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
				u.grain("sh_glint", lp + side2 * 46.0, side2, AMBER, 8)
				u.light(lp + side2 * 46.0, 140.0, AMBER, 0.6)
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


# ================================================================ 其余 16 人（10-30 协调人「连携补齐 20 人」，口径同四段样片）
## 共同规则：现身 PRE（0.18 秒光柱）→ 出手（_beat 轻放慢）→ 痕迹残留 0.4–0.6 秒；范围只比原技能大一点（区域半径 ult/link_area_r 150，
## 追击路径宽 30–40、附加爆点 ≤ 90、掩护以队长为圆心 ≤ 150）；伤害按出手干员攻击力：追击约 1.4–1.6 倍、附加约 1.0、聚拢 0.5–0.6、掩护以保命为主。
## 每人的接法避开她 / 他自己终结技与 S1–S3 的标志元素（docs/199 §7.5 表）。全部 3 像素格画法（ult.gd 光栅化）+ 光学颗粒 / 短灯。
const LINK_COL := {
	"lappland": Color(0.78, 0.74, 0.95), "specter_unchained": Color(0.95, 0.3, 0.35), "irene": Color(1.0, 0.85, 0.45), "mizuki": Color(0.55, 0.5, 1.0),
	"skadi": Color(0.95, 0.25, 0.3), "siege": Color(1.0, 0.72, 0.3), "exusiai": Color(1.0, 0.45, 0.35), "wisadel": Color(1.0, 0.35, 0.4),
	"logos": Color(0.95, 0.8, 0.45), "suzuran": Color(1.0, 0.7, 0.35), "angelina": Color(0.75, 0.5, 1.0), "ulpianus": Color(0.3, 0.75, 0.8),
	"saria": Color(1.0, 0.78, 0.35), "kaltsit": Color(0.45, 0.95, 0.6), "lumen": Color(0.6, 0.9, 1.0), "skalter": Color(0.95, 0.3, 0.4)}


static func _lc(u, p) -> Color:
	return LINK_COL.get(str(p.id), u._col(p))


static func _hit16(p, e, name: String, mult: float) -> void:
	p.log_hit(_src(p, name), ["连携"])
	p.deal_damage(e, _dmg(p, mult * Bal.v("ult/link16_mult", 1.0)))


static func _cc(p, e, stun: float) -> void:
	if not e.dead and not e.boss:
		p.add_cc(e, stun * (0.5 if e.elite else 1.0))


## 瞬身 / 冲锋：dur 秒从当前位置到 to（期间无敌），并朝向目标
static func _dash(p, to: Vector2, dur: float, anim := "attack") -> void:
	var d: Vector2 = to - p.pos
	p.syn_mv = {"from": p.pos, "to": to, "t": 0.0, "dur": dur}
	p.cmd_inv = maxf(p.cmd_inv, dur + 0.3)
	p._set_face(1.0 if d.x >= 0.0 else -1.0, true)
	p.play_vis_anim(anim)


static func _tgp(a: Dictionary) -> Vector2:
	var tg: Variant = a.get("tg")
	return tg.pos if tg != null and not tg.dead else Vector2(a.pos)


static func _sfx_hit(u) -> void:
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play("hit", -5.0, 1.2)


static func _step16(u, a: Dictionary) -> bool:
	var p = a.p
	var t0: float = a.age
	if t0 < PRE:
		_appear(u, p, t0)
		return false
	var t: float = t0 - PRE
	var c: Vector2 = a.pos
	var r: float = float(a.get("r", 150.0))
	var cl: Color = _lc(u, p)
	var once := func(k: String) -> bool:
		if a.done.has(k):
			return false
		a.done[k] = true
		return true
	match str(a.link):
		# ---------------------------------------------------------------- 追击
		"l_lappland":   # 狼影：贴地突进穿过主目标到身后 110，路径上留两道平行的灰紫爪痕；眩晕 0.4
			if once.call("go"):
				var tp: Vector2 = _tgp(a)
				var d: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["fp"] = p.pos
				a["tp"] = tp + d * 110.0
				_dash(p, a.tp, 0.14)
			if t >= 0.14 and once.call("cut"):
				_beat(u)
				var fp: Vector2 = a.fp
				var tp2: Vector2 = a.tp
				var nv: Vector2 = (tp2 - fp).normalized().orthogonal()
				for sgn in [-1.0, 1.0]:
					u.shape({"kind": "blade", "a": fp + nv * 9.0 * sgn, "b": tp2 + nv * 9.0 * sgn, "w": 4.0, "col": Color(0.92, 0.9, 1.0), "glow": cl, "grow": 0.04, "life": 0.65})
				for q in 5:
					u.grain("blade", fp.lerp(tp2, (q + 0.5) / 5.0), nv * (1.0 if q % 2 == 0 else -1.0), cl, 3)
				u.light(fp.lerp(tp2, 0.5), 150.0, cl, 0.3)
				for e in u.in_band(fp, tp2, 34.0):
					_hit16(p, e, "狼影", 1.5)
					_cc(p, e, 0.4)
				_sfx_hit(u)
			return t >= 0.85
		"l_specter":   # 双斩：闪到主目标身前，0.1 秒内两刀交叉成 X，斩痕停住再碎；周围 70 内各吃两下
			if once.call("go"):
				var tp: Vector2 = _tgp(a)
				_dash(p, tp + (p.pos - tp).normalized() * 40.0, 0.1)
				a["xc"] = tp
			for j in 2:
				if t >= 0.1 + 0.1 * j and once.call("x%d" % j):
					var xc: Vector2 = a.xc
					var dd: Vector2 = Vector2.from_angle(PI * 0.25 + PI * 0.5 * j)
					u.shape({"kind": "blade", "a": xc - dd * 85.0, "b": xc + dd * 85.0, "w": 7.0, "col": Color(1.0, 0.88, 0.86), "glow": cl, "grow": 0.03, "life": 0.6 - 0.1 * j})
					u.grain("blade", xc, dd.orthogonal(), cl, 6)
					if j == 0:
						_beat(u)
					for e in u.in_circle(xc, 70.0):
						_hit16(p, e, "双斩", 0.75)
					_sfx_hit(u)
			if t >= 0.2 and once.call("lt"):
				u.light(a.xc, 140.0, cl, 0.3)
			return t >= 0.8
		"l_irene":   # 穿刺：一记长距离直刺穿过区域，留一道细长金线 + 沿线火花；路径 1.6 倍，敌人被往前带一点
			if once.call("go"):
				var tp: Vector2 = _tgp(a)
				var d: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["fp"] = p.pos
				a["tp"] = tp + d * 140.0
				a["d"] = d
				_dash(p, a.tp, 0.12)
			if t >= 0.12 and once.call("cut"):
				_beat(u)
				var fp: Vector2 = a.fp
				var tp2: Vector2 = a.tp
				u.shape({"kind": "blade", "a": fp, "b": tp2 + Vector2(a.d) * 40.0, "w": 3.0, "col": Color(1.0, 0.96, 0.85), "glow": cl, "grow": 0.04, "life": 0.6})
				for q in 6:
					u.spark(fp.lerp(tp2, (q + 0.5) / 6.0), cl, 2, 10.0)
				u.light(tp2, 130.0, cl, 0.3)
				for e in u.in_band(fp, tp2, 30.0):
					_hit16(p, e, "穿刺", 1.6)
					if not e.boss:
						p.apply_kb(e, Vector2(a.d) * 160.0)
				_sfx_hit(u)
			return t >= 0.8
		"l_mizuki":   # 伞落：跳到主目标头顶落下一击，溅开一圈水珠（像素点）；半径 70 内 1.5 倍 + 减速 40% 1 秒
			if once.call("go"):
				var tp: Vector2 = _tgp(a)
				a["xc"] = tp
				_dash(p, tp + Vector2(0, -6), 0.16, "skill")
			if t >= 0.16 and once.call("hit"):
				_beat(u)
				var xc: Vector2 = a.xc
				u.shape({"kind": "ellipse", "c": xc + Vector2(0, 4), "rx": 64.0, "ry": 26.0, "col": cl.darkened(0.5), "fill": 0.5, "layer": "back", "life": 0.7})
				u.shape({"kind": "dots", "c": xc, "r": 80.0, "n": 18, "col": cl.lerp(Color.WHITE, 0.3), "life": 0.5})
				u.grain("water", xc, Vector2.UP, cl, 14)
				u.light(xc, 150.0, cl, 0.35)
				for e in u.in_circle(xc, 70.0):
					_hit16(p, e, "伞落", 1.5)
					u.g.enemies_sys.lite_slow(e, 0.4, 1.0)
				_sfx_hit(u)
			return t >= 0.8
		"l_skadi":   # 拖刃冲锋：不瞬移，0.24 秒跑着冲过区域、大剑拖地，地上留一道暗红刮痕 + 火星；路径 1.6 倍、往两侧击退
			if once.call("go"):
				var tp: Vector2 = _tgp(a)
				var d: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["fp"] = p.pos
				a["tp"] = tp + d * 120.0
				_dash(p, a.tp, 0.24)
				_beat(u)
			if t < 0.24:
				var q: Vector2 = Vector2(a.fp).lerp(a.tp, t / 0.24)
				u.spark(q + Vector2(0, 8), cl, 1, 6.0)
				u.grain("bfx_dust", q + Vector2(0, 8), Vector2.UP, Color(0.35, 0.3, 0.3), 1)
				return false
			if once.call("cut"):
				var fp: Vector2 = a.fp
				var tp2: Vector2 = a.tp
				var nv: Vector2 = (tp2 - fp).normalized().orthogonal()
				u.shape({"kind": "band", "a": fp + Vector2(0, 8), "b": tp2 + Vector2(0, 8), "w": 14.0, "col": Color(0.3, 0.06, 0.07), "fill": 0.7, "layer": "back", "life": 0.9})
				u.shape({"kind": "band", "a": fp + Vector2(0, 8), "b": tp2 + Vector2(0, 8), "w": 4.0, "col": cl, "fill": 0.9, "layer": "back", "life": 0.5})
				u.light(fp.lerp(tp2, 0.5), 150.0, cl, 0.3)
				for e in u.in_band(fp, tp2, 38.0):
					_hit16(p, e, "拖刃", 1.6)
					if not e.boss:
						var side: float = signf((e.pos - fp).dot(nv))
						p.apply_kb(e, nv * (side if side != 0.0 else 1.0) * 220.0)
				_sfx_hit(u)
			return t >= 0.9
		"l_siege":   # 冲阵：从队长身边冲进区域（不跃起），沿途撞开敌人，尾端一锤砸地（碎裂冲击 + 碎石）
			if once.call("go"):
				var lp: Vector2 = u.g.ppos
				var d: Vector2 = (c - lp).normalized() if c != lp else Vector2.RIGHT
				p.pos = lp + d.orthogonal() * 30.0
				a["fp"] = p.pos
				a["tp"] = c
				_dash(p, c, 0.26)
			if t < 0.26:
				var q: Vector2 = Vector2(a.fp).lerp(a.tp, t / 0.26)
				var nv: Vector2 = (Vector2(a.tp) - Vector2(a.fp)).normalized().orthogonal()
				for e in u.in_circle(q, 40.0):
					if not e.boss and not a.done.has("pushed%d" % int(e.id)):
						a.done["pushed%d" % int(e.id)] = true
						var side: float = signf((e.pos - q).dot(nv))
						p.apply_kb(e, nv * (side if side != 0.0 else 1.0) * 200.0)
						_hit16(p, e, "冲阵", 0.6)
				u.grain("bfx_dust", q + Vector2(0, 8), Vector2.UP, Color(0.4, 0.36, 0.3), 1)
				return false
			if once.call("slam"):
				_beat(u)
				u.g.vfx.stop(0.05, "link", true)
				u.shape({"kind": "ring", "c": c, "r": 95.0, "r1": 20.0, "w": 8.0, "col": cl, "life": 0.4})
				u.shape({"kind": "ellipse", "c": c + Vector2(0, 4), "rx": 50.0, "ry": 20.0, "col": Color(0.12, 0.1, 0.08), "fill": 0.7, "layer": "back", "life": 1.0})
				u.debris(c, cl, 2)
				u.grain("bfx_dust", c, Vector2.UP, Color(0.45, 0.4, 0.34), 14)
				u.light(c, 170.0, cl, 0.35)
				for e in u.in_circle(c, 90.0):
					_hit16(p, e, "冲阵", 1.4)
					_cc(p, e, 0.5)
				_sfx_hit(u)
			return t >= 0.95
		# ---------------------------------------------------------------- 附加
		"l_exusiai":   # 穿透曳光：原地朝区域打 8 发细长曳光（±8° 散开），每发穿过区域再往后 250；不爆炸（爆裂弹只留给终结技）
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("attack")
				_beat(u)
				a["base"] = (c - p.pos).normalized() if c != p.pos else Vector2.RIGHT
			var n: int = mini(8, int(t / 0.03) + 1)
			while int(a.k) < n:
				var i: int = int(a.k)
				var d: Vector2 = Vector2(a.base).rotated(deg_to_rad((float(i % 4) - 1.5) * 5.3 * (1.0 if i % 2 == 0 else -1.0)))
				var fp: Vector2 = p.pos + Vector2(0, -20)
				var tp: Vector2 = fp + d * (fp.distance_to(c) + 250.0)
				u.shape({"kind": "line", "a": fp, "b": tp, "w": 3.0, "col": cl.lerp(Color(1.0, 0.85, 0.5), 0.4 if i % 2 == 0 else 0.0), "life": 0.16})
				u.grain("bfx_flash", fp + d * 30.0, d, cl, 2)
				for e in u.in_band(fp, tp, 14.0):
					_hit16(p, e, "穿透曳光", 0.35)
				a.k = i + 1
			if t >= 0.1 and once.call("lt"):
				u.light(p.pos, 120.0, cl, 0.3)
			return t >= 0.7
		"l_wisadel":   # 子母弹：一发炮弹高抛到区域上空裂成 5 颗子弹，环形落下各自小爆（碎裂冲击 + 碎屑）
			var T := 0.3
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("attack")
				a["fp"] = p.pos + Vector2(0, -30)
				var shell := {"kind": "rock", "c": a.fp, "r": 12.0, "col": Color(0.2, 0.08, 0.1), "glow": cl, "seed": 2.0, "life": T + 0.05}
				u.shape(shell)
				a["shell"] = shell
			if t < T:
				var k: float = t / T
				var pos: Vector2 = Vector2(a.fp).lerp(c + Vector2(0, -60), k) + Vector2(0, -90.0 * sin(PI * k))
				a.shell.c = pos
				u.grain("bfx_dust", pos, Vector2.UP, Color(0.3, 0.28, 0.3), 1)
				return false
			if once.call("split"):
				a.shell.max = 0.0
				_beat(u)
				u.grain("bfx_flash", c + Vector2(0, -60), Vector2.UP, cl, 10)
			for j in 5:
				var land: float = T + 0.12 + 0.05 * j
				if t >= land and once.call("b%d" % j):
					var bp: Vector2 = c + Vector2.from_angle(j * TAU / 5.0 + 0.4) * 62.0
					u.shape({"kind": "ring", "c": bp, "r": 52.0, "r1": 10.0, "w": 6.0, "col": cl, "life": 0.3})
					u.shape({"kind": "rock", "c": bp, "r": 20.0, "col": cl, "glow": Color(1.0, 0.8, 0.55), "seed": 9.0 + j, "hold": false, "life": 0.14})
					u.shape({"kind": "ellipse", "c": bp + Vector2(0, 4), "rx": 26.0, "ry": 11.0, "col": Color(0.12, 0.06, 0.06), "fill": 0.7, "layer": "back", "life": 0.9})
					u.debris(bp, cl, 1)
					if j % 2 == 0:
						u.light(bp, 110.0, cl, 0.25)
					for e in u.in_circle(bp, 50.0):
						_hit16(p, e, "子母弹", 0.6)
			return t >= T + 0.8
		"l_logos":   # 咒印：区域内至多 6 名敌人头顶浮出一枚方形咒文，0.35 秒后依次炸开（黑金碎块）；单体 1.3 倍 + 周围 40 内 0.5 倍
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				_beat(u)
				var ts: Array = u.in_circle(c, r)
				ts.sort_custom(func(x, y): return (x.elite or x.boss) and not (y.elite or y.boss))
				a["ts"] = ts.slice(0, 6)
			var ts2: Array = a.ts
			for j in ts2.size():
				var e = ts2[j]
				if e.dead:
					continue
				var mp: Vector2 = e.pos + Vector2(0, -34)
				if t < 0.35 + 0.05 * j:
					u.shape({"kind": "rock", "c": mp, "r": 9.0, "col": Color(0.12, 0.1, 0.06), "glow": cl, "seed": 4.0, "rot": PI * 0.25, "life": 0.04})
				elif once.call("g%d" % j):
					u.shape({"kind": "rock", "c": e.pos, "r": 24.0, "col": cl, "glow": Color(0.15, 0.12, 0.05), "seed": 5.0 + j, "hold": false, "life": 0.16})
					u.grain("bfx_burst", e.pos, Vector2.UP, cl, 5)
					if j % 2 == 0:
						u.light(e.pos, 100.0, cl, 0.2)
					_hit16(p, e, "咒印", 1.3)
					for e2 in u.in_circle(e.pos, 40.0):
						if e2 != e:
							_hit16(p, e2, "咒印", 0.5)
			return t >= 0.35 + 0.05 * 6 + 0.45
		"l_suzuran":   # 灵狐：一只狐灵（亮橙白像素团 + 拖尾）从她脚边窜出，依次扑过区域内 5 名敌人；每下 0.6 倍 + 减速 30% 1.5 秒
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				var ts: Array = u.in_circle(c, r)
				ts.sort_custom(func(x, y): return x.pos.distance_squared_to(p.pos) < y.pos.distance_squared_to(p.pos))
				a["ts"] = ts.slice(0, 5)
				a["fox"] = p.pos
				var fox := {"kind": "rock", "c": p.pos, "r": 10.0, "col": cl, "glow": Color(1.0, 0.92, 0.75), "core": Color(1.0, 0.95, 0.85), "seed": 6.0, "life": 1.0}
				u.shape(fox)
				a["foxs"] = fox
			var ts3: Array = a.ts
			var hop := 0.11
			var i3: int = int(t / hop)
			while int(a.k) < mini(i3, ts3.size()):   # 已扑完的那几下按序结算（不靠帧时刻卡窗口）
				var eh = ts3[int(a.k)]
				if not eh.dead:
					a.fox = eh.pos
					_hit16(p, eh, "灵狐", 0.6)
					u.g.enemies_sys.lite_slow(eh, 0.3, 1.5)
					u.light(eh.pos, 90.0, cl, 0.15)
				a.k = int(a.k) + 1
			if i3 < ts3.size():
				var e = ts3[i3]
				var from: Vector2 = a.fox
				var to: Vector2 = e.pos if not e.dead else from
				var q: Vector2 = from.lerp(to, fposmod(t, hop) / hop)
				a.foxs.c = q + Vector2(0, -10)
				u.grain("fire", q + Vector2(0, -10), Vector2.UP, cl, 1)
				return false
			a.foxs.max = 0.0
			if once.call("end"):
				u.grain("mote_up", a.fox, Vector2.UP, cl, 6)
			return t >= hop * ts3.size() + 0.4
		# ---------------------------------------------------------------- 聚拢
		"l_angelina":   # 引力环：三枚紫色碎片绕区域外圈转一圈、往里收，把区域外 180 内的敌人一路带进来；落定 0.5 倍 + 减速
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				_beat(u)
				var outs: Array = []
				for e in u.in_circle(c, r + 180.0):
					if e.pos.distance_to(c) > r * 0.5 and not e.boss:
						outs.append(e)
				a["outs"] = outs.slice(0, 14)
			var T2 := 0.45
			if t < T2:
				var k2: float = t / T2
				var rr: float = lerpf(r + 150.0, r * 0.4, k2)
				for j in 3:
					var sp: Vector2 = c + Vector2.from_angle(TAU * (k2 * 1.0 + j / 3.0)) * rr
					u.shape({"kind": "rock", "c": sp, "r": 9.0, "col": Color(0.2, 0.1, 0.3), "glow": cl, "seed": 3.0 + j, "rot": k2 * 6.0, "life": 0.04})
					u.grain("mote_in", sp, (c - sp).normalized(), cl, 1)
				for e in a.outs:
					if not e.dead:
						var to: Vector2 = c + (e.pos - c).normalized() * r * 0.45
						p.nudge(e, (to - e.pos) * 0.16)
				return false
			if once.call("land"):
				u.light(c, 160.0, cl, 0.4)
				u.shape({"kind": "ring", "c": c, "r": r * 0.6, "r1": r * 0.2, "w": 5.0, "col": cl, "life": 0.4})
				for e in a.outs:
					if not e.dead:
						_hit16(p, e, "引力环", 0.5)
						p.add_cc(e, -INF, 0.6)
				_sfx_hit(u)
			return t >= T2 + 0.55
		# ---------------------------------------------------------------- 掩护（以队长为圆心）
		"l_ulpianus":   # 锚链回旋：瞬到队长身侧，锚拖着链子绕队长甩一整圈（半径 110），身边 130 内的敌人被甩开
			var lp: Vector2 = u.g.ppos
			if once.call("go"):
				_dash(p, lp + Vector2(-36.0, 0.0), 0.1, "skill")
			var T3 := 0.36
			if t >= 0.1 and t < 0.1 + T3:
				if once.call("beat"):
					_beat(u)
				var k3: float = (t - 0.1) / T3
				var ap: Vector2 = lp + Vector2.from_angle(TAU * k3 - PI * 0.5) * 110.0
				u.shape({"kind": "line", "a": p.pos + Vector2(0, -18), "b": ap, "w": 3.0, "col": cl.darkened(0.2), "life": 0.04})
				u.shape({"kind": "rock", "c": ap, "r": 16.0, "col": Color(0.12, 0.2, 0.22), "glow": cl, "seed": 8.0, "rot": k3 * 8.0, "life": 0.04})
				u.grain("water", ap, Vector2.from_angle(TAU * k3), cl, 1)
				for e in u.in_circle(ap, 40.0):
					if not e.boss and not a.done.has("u%d" % int(e.id)):
						a.done["u%d" % int(e.id)] = true
						p.apply_kb(e, (e.pos - lp).normalized() * 260.0)
						_hit16(p, e, "锚链回旋", 0.8)
				return false
			if t >= 0.1 + T3 and once.call("end"):
				u.light(lp, 150.0, cl, 0.3)
				u.shape({"kind": "ring", "c": lp, "r": 120.0, "r1": 100.0, "w": 5.0, "col": cl, "life": 0.4})
			return t >= 0.1 + T3 + 0.45
		"l_saria":   # 急救：现身在队长身旁，掷一支针剂扎到队长身上：回复 4% 最大生命、神经损伤 −20；队长头顶亮一个琥珀色十字
			var lp2: Vector2 = u.g.ppos
			if once.call("go"):
				_dash(p, lp2 + Vector2(60.0, 0.0), 0.1, "skill")
			if t >= 0.16 and once.call("heal"):
				_beat(u)
				u.shape({"kind": "line", "a": p.pos + Vector2(0, -24), "b": lp2 + Vector2(0, -20), "w": 2.0, "col": Color(1.0, 0.95, 0.85), "life": 0.12})
				p.heal_leader(u.g.max_hp * Bal.v("ult/link_saria_heal", 0.04), "技能连携")
				u.g.nerve = maxf(0.0, float(u.g.nerve) - 20.0)
				u.grain("mote_up", lp2, Vector2.UP, cl, 10)
				u.light(lp2, 130.0, cl, 0.5)
			if t >= 0.16 and t < 0.86:
				var cc: Vector2 = lp2 + Vector2(0, -62)
				u.shape({"kind": "band", "a": cc + Vector2(-12, 0), "b": cc + Vector2(12, 0), "w": 6.0, "col": cl, "fill": 0.95, "life": 0.04})
				u.shape({"kind": "band", "a": cc + Vector2(0, -12), "b": cc + Vector2(0, 12), "w": 6.0, "col": cl, "fill": 0.95, "life": 0.04})
			return t >= 0.95
		"l_kaltsit":   # 护卫扑击：朝队长身边最近的敌人那侧，一记绿色扇形扫击（半径 140），击退 300 + 1.0 倍
			var lp3: Vector2 = u.g.ppos
			if once.call("go"):
				var ne: Variant = _main(u, lp3, 260.0)
				var side: Vector2 = ((ne.pos - lp3).normalized() if ne != null else Vector2.RIGHT)
				a["side"] = side
				_dash(p, lp3 + side * 30.0, 0.1, "attack")
			if t >= 0.12 and once.call("hit"):
				_beat(u)
				var sd: Vector2 = a.side
				u.shape({"kind": "sector", "c": lp3, "r": 140.0, "a": sd.angle(), "half": 0.9, "col": cl, "fill": 0.45, "life": 0.3})
				for m in 5:
					var dm: Vector2 = sd.rotated((m - 2) * 0.36)
					u.shape({"kind": "blade", "a": lp3 + dm * 50.0, "b": lp3 + dm * 140.0, "w": 4.0, "col": Color(0.85, 1.0, 0.9), "glow": cl, "grow": 0.04, "life": 0.5})
				u.grain("blade", lp3 + sd * 90.0, sd, cl, 8)
				u.light(lp3 + sd * 80.0, 140.0, cl, 0.3)
				for e in u.in_circle(lp3, 140.0):
					if (e.pos - lp3).normalized().dot(sd) > cos(0.9):
						_hit16(p, e, "护卫扑击", 1.0)
						if not e.boss:
							p.apply_kb(e, (e.pos - lp3).normalized() * 300.0)
				_sfx_hit(u)
			return t >= 0.8
		"l_lumen":   # 提灯：把灯抛到队长脚下炸开一团光点：身边 150 内敌人减速 50% 1.2 秒、神经损伤 −25（不回血，回血是他的 S1）
			var lp4: Vector2 = u.g.ppos
			if once.call("go"):
				p.play_vis_anim("skill")
				a["fp"] = p.pos + Vector2(0, -30)
				var lamp := {"kind": "rock", "c": a.fp, "r": 9.0, "col": Color(0.25, 0.3, 0.35), "glow": cl, "core": Color(0.9, 0.95, 1.0), "seed": 1.0, "life": 0.3}
				u.shape(lamp)
				a["lamp"] = lamp
			if t < 0.22:
				var k4: float = t / 0.22
				a.lamp.c = Vector2(a.fp).lerp(lp4, k4) + Vector2(0, -60.0 * sin(PI * k4))
				return false
			if once.call("pop"):
				a.lamp.max = 0.0
				_beat(u)
				u.light(lp4, 220.0, cl, 0.8)
				u.grain("mote_up", lp4, Vector2.UP, cl, 16)
				u.shape({"kind": "dots", "c": lp4, "r": 150.0, "n": 26, "col": cl.lerp(Color.WHITE, 0.3), "life": 0.8})
				u.g.nerve = maxf(0.0, float(u.g.nerve) - 25.0)
				for e in u.in_circle(lp4, 150.0):
					u.g.enemies_sys.lite_slow(e, 0.5, 1.2)
			return t >= 1.0
		"l_skalter":   # 歌护：她唱一句，一圈红色音点绕队长转 1.2 秒；期间队长受到的伤害 −30%
			var lp5: Vector2 = u.g.ppos
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				u.team_buff("link:skalter", 1.4, [[&"dmg_taken", "mult", Bal.v("ult/link_skalter_dr", 0.7)]])
			if t < 1.2:
				for j in 6:
					var np: Vector2 = lp5 + Vector2.from_angle(TAU * (t * 0.8 + j / 6.0)) * 52.0 + Vector2(0, -10)
					u.shape({"kind": "rock", "c": np, "r": 5.0, "col": cl, "glow": Color(1.0, 0.8, 0.8), "seed": float(j), "life": 0.04})
				if int(t * 30.0) % 6 == 0:
					u.light(lp5, 100.0, cl, 0.1)
				return false
			return t >= 1.3
	return true
