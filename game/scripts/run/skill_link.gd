## 技能连携样片（用户 10-29，看完 final3 后定方向；开关 balance combo/skill_link，10-30 起缺省 1（协调人代定：定稿数值开着测），0 = 只剩 E 连携技）：
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
const LFX = preload("res://scripts/run/link_fx_common.gd")   # 连携画面公用件：衔接（接力光 + 光柱）/ 变体种子（用户 10-31 连携美术重做）
const LFB = preload("res://scripts/run/link_fx_b.gd")   # B 组 10 人画面（link-fx-b）
const LFA = preload("res://scripts/run/link_fx_a.gd")   # 连携画面 A 组 10 人（德克萨斯 / 能天使 / 浊心斯卡蒂 / 凯尔希 / 乌尔比安 / 斯卡蒂 / 歌蕾蒂娅 / 安洁莉娜 / 艾雅法拉 / 维什戴尔）

## 放技能的干员 id → {技能序号: [搭档 id, 合成类型]}
const LINKS := {
	"texas": {0: ["exusiai", "boom_rain"]},
	"lappland": {1: ["texas", "cross"]},
}
const WARM := Color(1.0, 0.55, 0.18)
const HOT := Color(1.0, 0.86, 0.45)
const CRIMSON := Color(1.0, 0.25, 0.22)


static func on() -> bool:
	return Bal.vi("combo/skill_link", 1) > 0


## squad.syn_skill → ult.on_skill：放技能的那一刻
## 间隔（10-30 实测：队长技能一放就亮，2 分钟接了 36 次）：两次技能连携亮起至少隔 ult/link_gap（25）秒，一局约 20–30 次
static func on_skill(u, o, i: int) -> void:
	if u.g.t < float(u.get_meta("link_next", -INF)):
		return
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
	u.set_meta("link_next", u.g.t + Bal.v("ult/link_gap", 25.0))
	u.stats.lit += 1
	var sfx: Node = u.g.get_node_or_null("/root/Sfx") if u.g.is_inside_tree() else null
	if sfx != null:
		sfx.play("ui_ok", -4.0, 1.25)


static func _dmg(o, mult: float, e = null) -> float:
	var atk: float = o.base("atk", 0.0) * mult * o._dmg_bonus()
	if Bal.vi("link/v2", 1) <= 0 or e == null or o.g.get("ult") == null:
		return atk
	# 连携 v2（docs/209 §2.2「少而重」）：和终结技同一套「按目标生命的预算」——小怪按当前基准生命、精英 / Boss 按最大生命的比例，
	# 后期也打得动；× 这一下的倍率（各接法原倍率）× link/v2_mult。取它和攻击力口径的较大者
	var b: float
	if e.boss:
		b = e.maxhp * (Bal.v("link/v2_final", 0.004) if e == o.g.final_boss else Bal.v("link/v2_boss", 0.01))
	elif e.elite or e.get("part", false):
		b = e.maxhp * Bal.v("link/v2_elite", 0.06)
	else:
		b = o.g.ult.ref_hp() * Bal.v("link/v2_minion", 0.9)
	return maxf(atk, b * mult * Bal.v("link/v2_mult", 1.0) * o.g.ult.build_mult(o))


static func _src(o, kind: String) -> String:
	var k: String = "技能连携·%s·%s" % [kind, str(o.id)]
	if not o.g.hit_src.has(k):
		o.g.hit_src[k] = {"emitter": "operator", "origin": "skill", "range": "范围", "kind": "物理", "tags": ["skill", "连携"], "class": o.cls, "op": str(o.id)}
	return k


## 出手：返回动作（u.combo_acts 推进）
static func fire(u, p, info: Dictionary) -> Dictionary:
	if not u.lf_on():   # link/flash 开着时由 ult.link_flash 演（_fire_head）
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
	u.light(c, r * 1.8, c1, 0.12)   # 用户 10-31「一直闪频不太好」：原来的实心白闪改成短灯（两人颜色），不再整团发白
	u.shape({"kind": "ring", "c": c, "r": r * 1.6, "r1": r * 0.5, "w": 4.0, "col": LFX.tint(c2, 1.0, 0.8), "life": 0.18})
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
				p.deal_damage(e, _dmg(p, Bal.v("ult/link_boom_mult", 0.8), e))
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
				who.deal_damage(e, _dmg(who, Bal.v("ult/link_cross_mult", 1.5), e))
		_merge_flash(u, c, c1.lerp(Color.WHITE, 0.4), c2, 40.0)
		u.g.vfx.stop(0.05, "link", true)
	return t >= 0.5

# ================================================================ 四类样片（协调人 10-29「先看样片再定」）：主技能用队长现有技能，接的人按类出手
## 规则：① 接的干员本人出现在画面里做动作；② 0.5–1 秒结束、范围只比原技能大一点；③ 不碰她终结技 / S1–S3 的标志元素。
## 技能区域：队长放技能那一刻，身边 260 内最密的一团（半径 ult/link_area_r 150）；没有敌人就不亮
const SAMPLE := {"texas": "pursue", "eyjafjalla": "lava", "gladiia": "gather", "hoshiguma": "cover",
	# 其余 16 人（10-30 协调人「连携补齐 20 人」，接法按协调人 10-30 接法表；做法见 docs/199 §7.5）
	"lappland": "l_lappland", "specter_unchained": "l_specter", "irene": "l_irene", "mizuki": "l_mizuki", "skadi": "l_skadi", "siege": "l_siege",
	"exusiai": "l_exusiai", "wisadel": "l_wisadel", "logos": "l_logos", "suzuran": "l_suzuran",
	"angelina": "l_angelina",
	"ulpianus": "l_ulpianus", "saria": "l_saria", "kaltsit": "l_kaltsit", "lumen": "l_lumen", "skalter": "l_skalter"}
## 每人所属四类（文档 / 遥测用）
const KIND4 := {"texas": "追击", "lappland": "追击", "skadi": "追击", "specter_unchained": "追击", "siege": "冲阵",
	"exusiai": "附加", "eyjafjalla": "附加", "suzuran": "附加", "irene": "附加", "wisadel": "附加", "logos": "附加",
	"angelina": "聚拢", "gladiia": "聚拢", "ulpianus": "聚拢", "mizuki": "聚拢",
	"saria": "掩护", "hoshiguma": "掩护", "kaltsit": "掩护", "lumen": "掩护", "skalter": "掩护"}
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
		u.set_meta("link_next", u.g.t + Bal.v("ult/link_gap", 25.0))
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
	if LFX.appear(u, p, t, PRE, cp):   # 衔接：队长亮 → 接力光飞到队友脚下 → 本人色光柱（贴图缺时照旧画下面的程序光柱）
		return
	var k: float = clampf(t / PRE, 0.0, 1.0)
	u.shape({"kind": "ring", "c": p.pos, "r": lerpf(70.0, 26.0, k), "w": 4.0, "col": cp.lerp(Color.WHITE, 0.3), "life": 0.04})
	u.shape({"kind": "band", "a": p.pos + Vector2(0, 6), "b": p.pos + Vector2(0, -90), "w": 22.0 * (1.0 - 0.5 * k), "col": cp, "fill": 0.35, "life": 0.04})
	u.grain("mote_up", p.pos + Vector2(0, -10), Vector2.UP, cp, 1)   # 光柱里往上飘的光点（光学观感）
	u.light(p.pos, 90.0, cp, 0.05)


## 出手瞬间：轻微放慢（比终结技弱一档）
static func _beat(u) -> void:
	if not u.lf_on():   # link/flash 开着时慢放在出手那一刻做（ult.link_flash）
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
				if LFA.on(u, "fx_lk_tx1"):
					LFA.texas_cut(u, a.from_p, a.to_p, mid)
				else:
					u.shape({"kind": "blade", "a": mid - d2 * 110.0, "b": mid + d2 * 110.0, "w": 7.0, "col": Color.WHITE, "glow": cp, "grow": 0.03, "life": 0.7})
					u.shape({"kind": "line", "a": a.from_p, "b": a.to_p, "w": 4.0, "col": cp, "life": 0.45})
					for q in 6:   # 斩痕上迸刀光颗粒 + 一盏短灯
						u.grain("blade", mid + d2 * (q - 2.5) * 36.0, d2.orthogonal() * (1.0 if q % 2 == 0 else -1.0), cp, 3)
					u.light(mid, 180.0, cp, 0.35)
				for e in u.in_band(a.from_p, a.to_p, 34.0):
					p.log_hit(_src(p, "追击"), ["连携"])
					p.deal_damage(e, _dmg(p, Bal.v("ult/link_pursue_mult", 1.6), e))
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
				if LFB.ey_rock(u, a, pos, k, R):
					rock.fill = 0.0   # 贴图熔岩块代替程序岩块
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
				var ey2: bool = LFB.ey_slam(u, c, hr, R)
				# 冲击：一圈压扁的亮橙冲击带（碎裂）+ 中心一团橙白
				if not ey2:
					u.shape({"kind": "ring", "c": c, "r": hr, "r1": 30.0, "w": 9.0, "col": CRACK, "life": 0.4})
				u.shape({"kind": "rock", "c": c, "r": R * 0.9, "col": CRACK, "glow": CORE, "core": CORE, "seed": 7.0, "hold": false, "life": 0.18})
				# 碎岩迸溅：岩块带重力往外飞
				for k2 in (0 if ey2 else 9):
					var ang: float = k2 * TAU / 9.0 + 0.3
					var sd: Vector2 = Vector2.from_angle(ang)
					var sp: float = 160.0 + 70.0 * fposmod(k2 * 0.618, 1.0)
					u.shape({"kind": "rock", "c": c + sd * 14.0, "r": 7.0 + 6.0 * fposmod(k2 * 0.37, 1.0), "col": CRUST, "glow": CRACK, "seed": 11.0 + k2,
						"spin": 6.0, "v": sd * sp + Vector2(0, -170.0), "grav": 620.0, "hold": false, "life": 0.55})
				# 熔岩溅落灼地（地面层，压在怪脚下）：几块不规则暗红斑 + 亮橙点，慢慢冷却
				for k3 in (0 if ey2 else 6):   # 新版由分叉熔缝代替这圈等角度溅落斑（预审：像等距瓦片）
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
					p.deal_damage(e, _dmg(p, Bal.v("ult/link_lava_mult", 1.0), e))
			for j in 2:
				var tj: float = T + 0.3 * (j + 1)
				var key := "b%d" % j
				if t >= tj and not a.done.has(key):
					a.done[key] = true
					for e in a.burn:
						if e.dead:
							continue
						p.log_hit(_src(p, "点燃"), ["连携"])
						p.deal_damage(e, _dmg(p, Bal.v("ult/link_burn_mult", 0.25), e))
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
				if not LFB.gl_land(u, c, r):
					u.shape({"kind": "ring", "c": c, "r": r, "r1": r * 0.4, "w": 4.0, "col": HOOK, "life": 0.5})
					u.light(c, 220.0, HOOK, 0.4)
				for e in pull:
					if not e.dead:
						u.grain("water", e.pos, Vector2.UP, HOOK, 6)   # 被拖到的怪落地溅水
						u.shape({"kind": "line", "a": p.pos + Vector2(0, -20), "b": e.pos, "w": 2.0, "col": HOOK, "life": 0.5})   # 钩索残留
						p.log_hit(_src(p, "聚拢"), ["连携"])
						p.deal_damage(e, _dmg(p, Bal.v("ult/link_gather_mult", 0.6), e))
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
				if LFX.on() and u.fx_ready(LFB.HS_SHIELD):
					LFB.hs_plant(u, lp + side2 * 46.0, side2)
				else:
					u.grain("sh_glint", lp + side2 * 46.0, side2, AMBER, 8)
					u.light(lp + side2 * 46.0, 140.0, AMBER, 0.6)
				for e in a.taunt:
					if not e.dead:
						u.shape({"kind": "line", "a": e.pos + Vector2(0, -24), "b": e.pos + Vector2(0, -38), "w": 3.0, "col": AMBER, "life": 1.0})
			if t < 1.5:
				var fa: float = 1.0 if t < 1.0 else 1.0 - (t - 1.0) / 0.5
				if t < 0.1 or not LFB.hs_shield(u, lp + side2 * 46.0, side2, fa, t):
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
	p.deal_damage(e, _dmg(p, mult * Bal.v("ult/link16_mult", 1.0), e))


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


## 凯尔希的 Mon3tr（召唤物字典，有 pos）；不在场返回 null
static func _m3(p):
	var sm = p.get("sm")
	if sm is Dictionary and sm.has("list"):
		for x in sm.list:
			if str(x.kind) == "mon3tr" and not x.get("gone", false):
				return x
	return null


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
		"l_lappland":   # 月牙剑气：她站到区域边缘，掷一道大月牙剑气横扫过区域（宽 60、长 = 区域直径 + 80），命中沉默 1 秒
			if once.call("go"):
				var d0: Vector2 = (c - p.pos).normalized() if c != p.pos else Vector2.RIGHT
				var ep: Vector2 = c - d0 * (r + 30.0)
				_dash(p, ep, 0.1)
				a["d"] = d0
				a["sp"] = ep
			var T := 0.28
			if t >= 0.1 and t < 0.1 + T:
				if once.call("beat"):
					_beat(u)
					p.play_vis_anim("attack")
				var k: float = (t - 0.1) / T
				var dd: Vector2 = a.d
				var q: Vector2 = Vector2(a.sp).lerp(c + dd * (r + 50.0), k)
				var nv: Vector2 = dd.orthogonal()
				if not LFB.lp_wave(u, a, q, dd, k):
					for j in 5:   # 月牙：一串弧形排开的刃块（中间厚两端尖）
						var off: float = (float(j) - 2.0) / 2.0
						var bp: Vector2 = q + nv * off * 70.0 - dd * (off * off) * 26.0
						u.shape({"kind": "blade", "a": bp - nv * 16.0, "b": bp + nv * 16.0, "w": 9.0 * (1.0 - absf(off) * 0.5), "col": Color(0.95, 0.93, 1.0), "glow": cl, "life": 0.05})
					u.grain("blade", q, dd, cl, 2)
				for e in u.in_circle(q, 70.0):
					if not a.done.has("h%d" % int(e.id)):
						a.done["h%d" % int(e.id)] = true
						_hit16(p, e, "月牙剑气", 1.4)
						u.g.enemies_sys.silence(e, u.g.t + 1.0)
				return false
			if once.call("trail"):
				u.light(c, 150.0, cl, 0.3)
				LFB.lp_scar(u, a, a.sp, c + Vector2(a.d) * (r + 50.0))
			return t >= 0.1 + T + 0.45
		"l_specter":   # 替身：她身后分出一个暗红替身，冲过区域斩一次（替身 = 一串干员色残影块 + 一刀）；本人不动
			if once.call("go"):
				p.play_vis_anim("skill")
				var tp: Vector2 = _tgp(a)
				var d0: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["fp"] = p.pos
				a["tp"] = tp + d0 * 120.0
			var T := 0.2
			if t < T:
				var q: Vector2 = Vector2(a.fp).lerp(a.tp, t / T)
				if not LFB.sp_ghost(u, p, q, (Vector2(a.tp) - Vector2(a.fp)).normalized()):
					u.shape({"kind": "ellipse", "c": q + Vector2(0, -20), "rx": 10.0, "ry": 22.0, "col": cl, "fill": 0.55, "life": 0.18})   # 替身残影（人形竖块）
					u.shape({"kind": "ellipse", "c": q + Vector2(0, -46), "rx": 7.0, "ry": 7.0, "col": cl, "fill": 0.55, "life": 0.18})
				u.grain("fluid", q, Vector2.UP, Color(0.5, 0.05, 0.08), 1)
				return false
			if once.call("cut"):
				_beat(u)
				var fp: Vector2 = a.fp
				var tp2: Vector2 = a.tp
				if not LFB.sp_cut(u, fp, tp2):
					u.shape({"kind": "blade", "a": fp, "b": tp2, "w": 7.0, "col": Color(1.0, 0.86, 0.84), "glow": cl, "grow": 0.03, "life": 0.6})
					u.grain("blade", fp.lerp(tp2, 0.5), (tp2 - fp).normalized().orthogonal(), cl, 8)
					u.light(fp.lerp(tp2, 0.6), 150.0, cl, 0.3)
				for e in u.in_band(fp, tp2, 40.0):
					_hit16(p, e, "替身斩", 1.6)
				_sfx_hit(u)
			return t >= T + 0.6
		"l_irene":   # 提灯一照：区域被暖金灯光照亮，区域内敌人 3 秒受到的伤害 +20%；随后她补一刺穿过主目标
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				_beat(u)
				if not LFB.ir_lamp(u, p, c, r):
					u.light(c, r + 60.0, cl, 0.9)
					u.shape({"kind": "circle", "c": c, "r": r, "col": cl, "fill": 0.16, "layer": "back", "life": 0.9})
					u.shape({"kind": "dots", "c": c, "r": r, "n": 22, "col": cl.lerp(Color.WHITE, 0.3), "life": 0.8})
				for e in u.in_circle(c, r):
					e["frag_t"] = maxf(float(e.get("frag_t", 0.0)), u.g.t + 3.0)
					e["frag_v"] = maxf(float(e.get("frag_v", 0.0)), Bal.v("ult/link_irene_amp", 0.2))
			if t >= 0.3 and once.call("dash"):
				var tp: Vector2 = _tgp(a)
				var d: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["fp"] = p.pos
				a["tp"] = tp + d * 110.0
				_dash(p, a.tp, 0.12)
			if t >= 0.42 and once.call("cut"):
				var fp: Vector2 = a.fp
				var tp2: Vector2 = a.tp
				u.shape({"kind": "blade", "a": fp, "b": tp2, "w": 3.0, "col": Color(1.0, 0.96, 0.85), "glow": cl, "grow": 0.04, "life": 0.55})
				for q in 5:
					u.spark(fp.lerp(tp2, (q + 0.5) / 5.0), cl, 2, 10.0)
				for e in u.in_band(fp, tp2, 30.0):
					_hit16(p, e, "补刺", 1.2)
				_sfx_hit(u)
			return t >= 1.0
		"l_mizuki":   # 小触手：区域里 6 名敌人脚下钻出小触手，缠住 1 秒（束缚 = 眩晕，精英减半）
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				var ts: Array = u.in_circle(c, r)
				ts.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
				a["ts"] = ts.slice(0, 6)
				for e in a.ts:
					_hit16(p, e, "小触手", 0.5)
					_cc(p, e, 1.0)
					u.grain("water", e.pos, Vector2.UP, cl, 3)
				a["mzv2"] = LFB.mz_tentacles(u, a.ts)
			if t < 1.0 and a.get("mzv2", false):
				if once.call("lt"):
					u.light(c, 150.0, cl, 0.6)
				return false
			if t < 1.0:
				var hk: float = minf(1.0, t / 0.12)
				for j in a.ts.size():
					var e = a.ts[j]
					if e.dead:
						continue
					var bp: Vector2 = e.pos + Vector2(10.0 if j % 2 == 0 else -10.0, 6.0)
					var sw: float = sin(t * 9.0 + j) * 5.0
					u.shape({"kind": "band", "a": bp, "b": bp + Vector2(sw, -30.0 * hk), "w": 6.0, "col": cl, "fill": 0.9, "life": 0.04})
					u.shape({"kind": "band", "a": bp + Vector2(sw, -30.0 * hk), "b": bp + Vector2(sw * 2.0 - 6.0, -42.0 * hk), "w": 3.0, "col": cl.lerp(Color.WHITE, 0.3), "fill": 0.9, "life": 0.04})
				if once.call("lt"):
					u.light(c, 150.0, cl, 0.6)
				return false
			return t >= 1.1
		"l_skadi":   # 拖刃冲锋：跑着冲过区域、大剑拖地，身后留一道水痕 1.5 秒，踩在上面的敌人每 0.5 秒受伤
			if once.call("go"):
				var tp: Vector2 = _tgp(a)
				var d: Vector2 = (tp - p.pos).normalized() if tp != p.pos else Vector2.RIGHT
				a["fp"] = p.pos
				a["tp"] = tp + d * 120.0
				_dash(p, a.tp, 0.24)
				_beat(u)
			if t < 0.24:
				var q: Vector2 = Vector2(a.fp).lerp(a.tp, t / 0.24)
				if LFA.on(u, LFA.SD_TRAIL):
					LFA.skadi_run(u, q, t)
				else:
					u.grain("water", q + Vector2(0, 8), Vector2.UP, Color(0.3, 0.55, 0.75), 2)
				return false
			var fp: Vector2 = a.fp
			var tp2: Vector2 = a.tp
			if once.call("cut"):
				if LFA.on(u, LFA.SD_TRAIL):
					LFA.skadi_trail(u, fp, tp2)
				else:
					u.shape({"kind": "band", "a": fp + Vector2(0, 8), "b": tp2 + Vector2(0, 8), "w": 34.0, "col": Color(0.12, 0.25, 0.4), "fill": 0.6, "layer": "back", "life": 1.6})   # 水痕
					u.shape({"kind": "band", "a": fp + Vector2(0, 8), "b": tp2 + Vector2(0, 8), "w": 6.0, "col": cl, "fill": 0.9, "layer": "back", "life": 0.5})
					u.light(fp.lerp(tp2, 0.5), 150.0, cl, 0.3)
				for e in u.in_band(fp, tp2, 38.0):
					_hit16(p, e, "拖刃", 1.2)
				_sfx_hit(u)
			for j in 3:   # 水痕持续伤害
				if t >= 0.24 + 0.5 * (j + 1) and once.call("w%d" % j):
					for e in u.in_band(fp, tp2, 20.0):
						_hit16(p, e, "水痕", 0.25)
					if LFA.on(u, LFA.SD_TRAIL):
						LFA.skadi_tick(u, fp, tp2, j)
					else:
						u.grain("water", fp.lerp(tp2, 0.5), Vector2.UP, Color(0.3, 0.55, 0.75), 4)
			return t >= 0.24 + 1.6
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
				if not LFB.sg_dash(u, q, (Vector2(a.tp) - Vector2(a.fp)).normalized()):
					u.grain("bfx_dust", q + Vector2(0, 8), Vector2.UP, Color(0.4, 0.36, 0.3), 1)
				return false
			if once.call("slam"):
				_beat(u)
				u.g.vfx.stop(0.05, "link", true)
				if not LFB.sg_slam(u, c):
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
		"l_exusiai":   # 穿透扫射：原地朝区域打一轮 8 发红金交替的细长曳光（±8° 散开），每发穿过区域再往后 250；不用爆裂弹
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
				var tc: Color = Color(1.0, 0.3, 0.25) if i % 2 == 0 else Color(1.0, 0.82, 0.4)   # 红金交替
				if LFA.on(u, "fx_lk_tx1"):
					LFA.exusiai_shot(u, fp, tp, i)
				else:
					u.shape({"kind": "line", "a": fp, "b": tp, "w": 3.0, "col": tc, "life": 0.16})
					u.grain("bfx_flash", fp + d * 30.0, d, tc, 2)
				for e in u.in_band(fp, tp, 14.0):
					_hit16(p, e, "穿透扫射", 0.35)
				a.k = i + 1
			if t >= 0.1 and once.call("lt"):
				u.light(p.pos, 120.0, cl, 0.3)
			return t >= 0.7
		"l_wisadel":   # 好礼（天赋）：这次技能 1 秒内在区域里打死的敌人原地留下暗红残影，0.35 秒后炸开（半径 60）；一个都没死就在主目标处补一发
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				a["watch"] = u.in_circle(c, r + 40.0)
				a["gh"] = []
			if t < 1.0:
				for e in a.watch:
					if e.dead and not a.done.has("d%d" % int(e.id)):
						a.done["d%d" % int(e.id)] = true
						a.gh.append([e.pos, t])
						if not LFB.wd_ghost(u, e.pos):
							u.shape({"kind": "ellipse", "c": e.pos + Vector2(0, -16), "rx": 12.0, "ry": 18.0, "col": cl, "fill": 0.55, "life": 0.35})
			if t >= 0.8 and a.gh.is_empty() and once.call("fallback"):
				a.gh.append([_tgp(a), t - 0.35])
			for j in a.gh.size():
				var gp: Vector2 = a.gh[j][0]
				if t >= float(a.gh[j][1]) + 0.35 and once.call("b%d" % j):
					if not LFB.wd_blast(u, gp, j):
						u.shape({"kind": "ring", "c": gp, "r": 60.0, "r1": 12.0, "w": 6.0, "col": cl, "life": 0.3})
						u.shape({"kind": "rock", "c": gp, "r": 22.0, "col": cl, "glow": Color(1.0, 0.8, 0.55), "seed": 9.0 + j, "hold": false, "life": 0.14})
						u.shape({"kind": "ellipse", "c": gp + Vector2(0, 4), "rx": 26.0, "ry": 11.0, "col": Color(0.12, 0.06, 0.06), "fill": 0.7, "layer": "back", "life": 0.9})
						u.debris(gp, cl, 1)
						if j % 3 == 0:
							u.light(gp, 110.0, cl, 0.25)
					for e in u.in_circle(gp, 60.0):
						_hit16(p, e, "好礼", 0.6)
			return t >= 1.0 + 0.35 + 0.45
		"l_logos":   # 消弹：区域上空浮出一圈黑金咒文，区域内敌方弹幕当场消掉（每颗留一个小碎块），区域内敌人减速 50% 1 秒
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				_beat(u)
				var R2: float = r + 40.0
				var gone: PackedVector2Array = u.g.shots.cancel_in(func(q: Vector2) -> bool: return q.distance_to(c) <= R2)
				for q in gone:
					u.shape({"kind": "rock", "c": q, "r": 6.0, "col": cl, "glow": Color(0.15, 0.12, 0.05), "seed": q.x, "hold": false, "life": 0.3})
				for e in u.in_circle(c, r):
					u.g.enemies_sys.lite_slow(e, 0.5, 1.0)
				u.light(c, r + 40.0, cl, 0.6)
			if t < 0.8:
				if not LFB.lo_ring(u, c, r + 20.0, t):
					for j in 8:
						var gp: Vector2 = c + Vector2.from_angle(TAU * j / 8.0 + t * 1.5) * (r + 20.0)
						u.shape({"kind": "rock", "c": gp, "r": 8.0, "col": Color(0.12, 0.1, 0.06), "glow": cl, "seed": 4.0 + j, "rot": PI * 0.25, "life": 0.04})
				return false
			return t >= 0.9
		"l_suzuran":   # 狐火：4 团狐火绕她转一圈，再各追向区域内一名敌人；命中 0.6 倍 + 减速 30% 1.5 秒
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				var ts: Array = u.in_circle(c, r)
				ts.sort_custom(func(x, y): return x.pos.distance_squared_to(c) < y.pos.distance_squared_to(c))
				a["ts"] = ts.slice(0, 4)
			var T1 := 0.35
			var T2 := 0.25
			for j in 4:
				var orb: Vector2 = p.pos + Vector2(0, -24) + Vector2.from_angle(TAU * (j / 4.0 + minf(t, T1) / T1)) * 40.0
				var q: Vector2 = orb
				if t >= T1:
					var e = a.ts[j] if j < a.ts.size() else null
					var to: Vector2 = (e.pos + Vector2(0, -12)) if e != null and not e.dead else c
					q = orb.lerp(to, minf(1.0, (t - T1) / T2))
					if t >= T1 + T2 and once.call("h%d" % j):
						if e != null and not e.dead:
							_hit16(p, e, "狐火", 0.6)
							u.g.enemies_sys.lite_slow(e, 0.3, 1.5)
						if LFX.on() and u.fx_ready(LFB.SZ_FOX[0]):
							LFB.sz_pop(u, to)
						else:
							u.grain("fire", to, Vector2.UP, cl, 4)
							u.light(to, 90.0, cl, 0.2)
				if t < T1 + T2:
					var dv: Vector2 = (q - orb).normalized() if t >= T1 and q != orb else Vector2.from_angle(TAU * (j / 4.0 + minf(t, T1) / T1) + PI / 2.0)
					if not LFB.sz_fox(u, q, dv, j):
						u.shape({"kind": "rock", "c": q, "r": 8.0, "col": cl, "glow": Color(1.0, 0.92, 0.75), "core": Color(1.0, 0.95, 0.85), "seed": 6.0 + j, "life": 0.04})
					u.grain("fire", q, Vector2.UP, cl, 1)
			return t >= T1 + T2 + 0.45
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
					if not LFB.an_core(u, sp, k2, j):
						u.shape({"kind": "rock", "c": sp, "r": 9.0, "col": Color(0.2, 0.1, 0.3), "glow": cl, "seed": 3.0 + j, "rot": k2 * 6.0, "life": 0.04})
					u.grain("mote_in", sp, (c - sp).normalized(), cl, 1)
				for e in a.outs:
					if not e.dead:
						var to: Vector2 = c + (e.pos - c).normalized() * r * 0.45
						p.nudge(e, (to - e.pos) * 0.16)
				return false
			if once.call("land"):
				if not LFB.an_land(u, c, r):
					u.light(c, 160.0, cl, 0.4)
					u.shape({"kind": "ring", "c": c, "r": r * 0.6, "r1": r * 0.2, "w": 5.0, "col": cl, "life": 0.4})
				for e in a.outs:
					if not e.dead:
						_hit16(p, e, "引力环", 0.5)
						p.add_cc(e, -INF, 0.6)
				_sfx_hit(u)
			return t >= T2 + 0.55
		# ---------------------------------------------------------------- 掩护（以队长为圆心）
		"l_ulpianus":   # 掷锚：锚钉在区域主目标（精英优先）身上，把它钉住 1.5 秒；附近 180 内的小怪被拖向它
			if once.call("go"):
				p._set_face(1.0 if c.x >= p.pos.x else -1.0, true)
				p.play_vis_anim("skill")
				a["fp"] = p.pos + Vector2(0, -20)
			var T := 0.2
			var tp: Vector2 = _tgp(a)
			if t < T:
				var q: Vector2 = Vector2(a.fp).lerp(tp, t / T)
				if LFA.on(u, "fx_ult_ulpianus_anchor_front"):
					LFA.ulpianus_fly(u, a.fp, q, t / T)
					return false
				u.shape({"kind": "line", "a": a.fp, "b": q, "w": 3.0, "col": cl.darkened(0.2), "life": 0.04})
				u.shape({"kind": "rock", "c": q, "r": 14.0, "col": Color(0.12, 0.2, 0.22), "glow": cl, "seed": 8.0, "life": 0.04})
				return false
			if once.call("pin"):
				_beat(u)
				u.g.vfx.stop(0.05, "link", true)
				var tg: Variant = a.get("tg")
				if tg != null and not tg.dead:
					_hit16(p, tg, "掷锚", 1.0)
					if not tg.boss:
						p.add_cc(tg, 1.5)
				a["pull"] = []
				for e in u.in_circle(tp, 180.0):
					if e != tg and not e.boss and not e.elite:
						a.pull.append(e)
				if LFA.on(u, "fx_ult_ulpianus_anchor_front"):
					LFA.ulpianus_pin(u, tp)
				else:
					u.debris(tp, cl, 2)
					u.light(tp, 150.0, cl, 0.4)
				_sfx_hit(u)
			if t < T + 0.5:
				if LFA.on(u, "fx_ult_ulpianus_anchor_front"):
					LFA.ulpianus_hold(u, p.pos + Vector2(0, -20), tp)
				else:
					u.shape({"kind": "rock", "c": tp + Vector2(0, -6), "r": 14.0, "col": Color(0.12, 0.2, 0.22), "glow": cl, "seed": 8.0, "life": 0.04})
					u.shape({"kind": "line", "a": p.pos + Vector2(0, -20), "b": tp, "w": 2.0, "col": cl.darkened(0.2), "life": 0.04})
				for e in a.pull:
					if not e.dead:
						p.nudge(e, (tp - e.pos) * 0.12)
				return false
			if once.call("land"):
				for e in a.pull:
					if not e.dead and e.pos.distance_to(tp) < 90.0:
						_hit16(p, e, "掷锚", 0.4)
			return t >= T + 0.95
		"l_saria":   # 钙质护盾：给队长一层钙质护盾（挡一次伤害，1.5 秒没用掉收回），区域地面钙化 1.5 秒（琥珀色碎晶斑，踩上的敌人减速 40%）
			var lp2: Vector2 = u.g.ppos
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				a["shield0"] = int(u.g.shield)
				u.g.shield = int(u.g.shield) + 1
				if not LFB.sa_ground(u, c, r):
					for j in 7:
						var off: Vector2 = Vector2.from_angle(j * 2.39996) * r * (0.25 + 0.55 * fposmod(j * 0.618, 1.0))
						u.shape({"kind": "ellipse", "c": c + off, "rx": 30.0, "ry": 13.0, "col": cl.darkened(0.35), "fill": 0.6, "layer": "back", "life": 1.6})
						u.shape({"kind": "rock", "c": c + off + Vector2(0, -4), "r": 7.0, "col": cl, "glow": Color(1.0, 0.92, 0.7), "seed": 3.0 + j, "life": 1.5, "layer": "back"})
				u.light(c, r, cl, 0.6)
			if t < 1.5:
				var hk: float = 1.0 if t < 1.2 else (1.5 - t) / 0.3
				for j in 6:   # 队长身周一圈钙质护盾块
					var sp: Vector2 = lp2 + Vector2(0, -16) + Vector2.from_angle(TAU * j / 6.0 + t) * 30.0
					u.shape({"kind": "rock", "c": sp, "r": 6.0, "col": cl, "glow": Color(1.0, 0.92, 0.7), "seed": float(j), "fill": hk, "life": 0.04})
				if int(t * 10.0) % 3 == 0:
					for e in u.in_circle(c, r):
						u.g.enemies_sys.lite_slow(e, 0.4, 0.4)
				return false
			if once.call("unshield"):
				if int(u.g.shield) > int(a.shield0):
					u.g.shield = int(u.g.shield) - 1
			return true
		"l_kaltsit":   # Mon3tr 掩护：Mon3tr 落到队长前方（面朝最近的敌人那侧）挡一下：挡一次伤害（1.2 秒）+ 把身前敌人推开；凯尔希给队长回复 3% 最大生命
			var lp3: Vector2 = u.g.ppos
			if once.call("go"):
				var ne: Variant = _main(u, lp3, 300.0)
				var side: Vector2 = ((ne.pos - lp3).normalized() if ne != null else Vector2.RIGHT)
				a["side"] = side
				a["mp"] = lp3 + side * 50.0
				a["shield0"] = int(u.g.shield)
				u.g.shield = int(u.g.shield) + 1
				p.play_vis_anim("skill")
				var m3 = _m3(p)
				if m3 != null:
					m3.pos = a.mp
			if t >= 0.08 and once.call("block"):
				_beat(u)
				var sd: Vector2 = a.side
				var mp: Vector2 = a.mp
				if not LFB.ka_block(u, mp, sd):
					u.debris(mp, cl, 2)
					u.light(mp, 150.0, cl, 0.5)
				p.heal_leader(u.g.max_hp * Bal.v("ult/link_kaltsit_heal", 0.03), "技能连携")
				for e in u.in_circle(mp + sd * 40.0, 90.0):
					_hit16(p, e, "Mon3tr", 0.8)
					if not e.boss:
						p.apply_kb(e, sd * 260.0)
				_sfx_hit(u)
			if t < 1.2:
				var sd2: Vector2 = a.side
				var mp2: Vector2 = a.mp
				var fa: float = 1.0 if t < 0.9 else (1.2 - t) / 0.3
				if _m3(p) == null:   # 没有 Mon3tr 在场时画一个绿色占位身形
					u.shape({"kind": "rock", "c": mp2 + Vector2(0, -22), "r": 18.0, "col": Color(0.1, 0.25, 0.15), "glow": cl, "seed": 2.0, "fill": fa, "life": 0.04})
				var nv: Vector2 = sd2.orthogonal()
				u.shape({"kind": "line", "a": mp2 + sd2 * 22.0 + nv * 34.0, "b": mp2 + sd2 * 22.0 - nv * 34.0, "w": 5.0, "col": Color(cl, fa), "life": 0.04})   # 挡格面
				return false
			if once.call("unshield"):
				if int(u.g.shield) > int(a.shield0):
					u.g.shield = int(u.g.shield) - 1
			return true
		"l_lumen":   # 灯火：队长灯火 +10、清神经损伤；区域里飘起灼烧光点 1.2 秒（每 0.3 秒对区域内敌人小伤害）
			var lp4: Vector2 = u.g.ppos
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				u.g.lamp = minf(float(u.g.lamp_cap), float(u.g.lamp) + Bal.v("ult/link_lumen_lamp", 10.0))
				u.g.nerve = 0.0
				u.light(lp4, 160.0, cl, 0.6)
				u.grain("mote_up", lp4, Vector2.UP, cl, 10)
			if t < 1.2:
				if int(t * 30.0) % 2 == 0:
					u.grain("mote_up", c + Vector2.from_angle(t * 11.0) * r * fposmod(t * 3.7, 1.0), Vector2.UP, cl, 2)
				if not LFB.lu_motes(u, c, r, t):
					u.shape({"kind": "dots", "c": c, "r": r, "n": 16, "col": cl.lerp(Color.WHITE, 0.3), "life": 0.04})
				for j in 4:
					if t >= 0.3 * j and once.call("b%d" % j):
						for e in u.in_circle(c, r):
							_hit16(p, e, "灼烧光点", 0.2)
						u.light(c, r, cl, 0.2)
				return false
			return t >= 1.3
		"l_skalter":   # 歌声：她唱一句，歌声覆盖区域 3 秒（一圈红色音点绕区域转）；队长站在区域里时全队攻击 +20%
			if once.call("go"):
				p.play_vis_anim("skill")
				_beat(u)
				u.team_buff("link:skalter", 3.0, [[&"dmg", "mult", Bal.v("ult/link_skalter_atk", 1.2)]], c, r)
				u.light(c, r, cl, 0.5)
			if t < 3.0:
				var fa: float = 1.0 if t < 2.6 else (3.0 - t) / 0.4
				if LFA.on(u, "fx_ult_skalter_domain_back"):
					LFA.skalter_song(u, c, r, t, a)
					return false
				for j in 8:
					var np: Vector2 = c + Vector2.from_angle(TAU * (t * 0.25 + j / 8.0)) * r
					u.shape({"kind": "rock", "c": np, "r": 6.0, "col": cl, "glow": Color(1.0, 0.8, 0.8), "seed": float(j), "fill": fa, "life": 0.04})
				if int(t * 30.0) % 15 == 0:
					u.grain("mote_up", c, Vector2.UP, cl, 3)
				return false
			return true
	return true
