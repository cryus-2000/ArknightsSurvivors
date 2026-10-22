extends RefCounted
## 作战记录的数据模型（docs/77，2026-10-12）：局终统计界面（screens/run_stats_screen.gd）只画 model()，不直接读对局。
## - snapshot(g)：从对局与 telemetry 的计数拷一份「原始记录」（纯字典，可存可伪造：快检用假记录直接喂 model）。
## - model(raw)：纯函数，把原始记录整理成界面要的行：每名干员（含被替换离队的）+「藏品与支援」一行；
##   占比用最大余数法取整，整数百分比合计恰好 100；各行来源之和 = 该行伤害；各行之和 = 全队伤害。
## 只读计数，不碰 g.rng，不改对局状态。

const D = preload("res://scripts/data.gd")

const OTHER := "_other"
const ORIGIN_NAME := {"core": "普攻", "skill": "技能", "talent": "天赋", "route": "分支", "support": "支援", "relic": "藏品"}
## 承伤来源键（combat.lose_hp 的 src / g.dmg_src）里不是敌人类型的那些
const TAKEN_NAME := {"bullet": "敌方弹幕", "nerve": "神经损伤", "corrode": "侵蚀", "zone": "黑潮", "mire": "溟痕",
	"relic": "藏品代价", "hunt_ring": "围猎", "shock": "冲击环", "wound": "侵蚀创口", "dark": "寂灭（灯火归零）"}
const TAKEN_PREFIX := ["boss_", "atk_", "blast_", "contact_", "shock_"]
const LAMP_NAMES := ["通明", "摇曳", "暗淡", "寂灭"]


## 对局 → 原始记录
static func snapshot(g) -> Dictionary:
	var tm = g.telemetry
	var t_end: float = maxf(0.0, g.t - g.trial.started_at) if g.trial.active else g.t
	var won: bool = g.state == g.S.WIN
	var ops: Array = []
	for j in tm.joins:
		ops.append(j.duplicate())
	for o in g.squad.ops:   # 兜底：没走 squad.add 的（测试直接塞进来的）按开局算
		if not ops.any(func(j): return j.id == o.id):
			var c: Color = o.col()
			ops.append({"id": o.id, "name": o.display_name(), "en": str(o.def.get("en", o.id.to_upper())), "col": [c.r, c.g, c.b],
				"leader": o.is_leader, "t": 0.0, "left": -1.0, "cls": str(o.get("cls"))})
	for j in ops:
		var cur = null
		for o in g.squad.ops:
			if o.id == j.id:
				cur = o
		j["elite"] = int(cur.elite) if cur != null else 0
		j["leader"] = cur.is_leader if cur != null else bool(j.get("leader", false))
	var origin := {}
	for op in tm.op_out:
		for src in tm.op_out[op]:
			origin[src] = str(g.hit_src.get(src, {}).get("origin", "relic" if op == OTHER else "core"))
	var bosses: Array = []
	var friendly := {}
	for b in g.bosses:
		if b.get("friendly", false):
			friendly[str(b.type)] = true   # 伊莎玛拉友方形态等：不算击破的 Boss
	for bs in tm.boss_seen.values():
		var ty: String = str(bs.type)
		if friendly.has(ty):
			continue
		bosses.append({"type": ty, "name": str(D.ENEMIES.get(ty, {}).get("name", ty)).replace("\"", ""), "t0": float(bs.t0),
			"t1": float(bs.t1), "retreat": bs.has("retreat")})
	# 最终 Boss 死的同一帧就判胜利，t1 记不到（telemetry 注释）：胜利局还没记到击破时刻的按整局时间算
	for b in g.bosses:
		if b.dead and won:
			for bb in bosses:
				if bb.type == b.type and bb.t1 < 0.0 and not bb.retreat:
					bb.t1 = g.t
	var fuse := {}
	var rfx = g.get("rfx")
	if rfx != null and rfx.get("fuse_pool") != null and rfx.has_method("fuse_pct"):
		fuse = {"pool": int(rfx.fuse_pool), "pct": float(rfx.fuse_pct()), "on": bool(rfx.get("fuse_on"))}
	var ending_name := ""
	if won and not g.trial.active:
		ending_name = str(D.ENDINGS.get(g.ending, {}).get("name", ""))
	# 藏品（拾取顺序）：名字、分类、稀有度、等级、简短效果
	var relic_list: Array = []
	for id in g.relics:
		var rd: Dictionary = g.RL.get(id, {})
		var desc := str(rd.get("desc", ""))
		if rfx != null and rfx.has_method("display_desc"):
			desc = str(rfx.display_desc(id))
		relic_list.append({"id": str(id), "name": str(rd.get("name", id)), "cat": str(rd.get("cat", "")), "rarity": str(rd.get("rarity", "")),
			"lv": int(rfx.lv.get(id, 1)) if rfx != null else 1, "max": int(rfx.max_lv(id)) if rfx != null else 1, "desc": desc})
	# 击倒者（失败）：最后一次掉血的来源；最终 Boss（胜利）：结局对应的 Boss
	var killer := {}
	if not won:
		killer = killer_info(tm.killer())
	var final_boss := {}
	if won and not g.trial.active:
		var bt: String = str(D.ENDINGS.get(g.ending, {}).get("boss", ""))
		final_boss = {"type": bt, "name": str(D.ENEMIES.get(bt, {}).get("name", bt)).replace("\"", "")}
	return {"result": "win" if won else "dead", "trial": g.trial.active, "ending": str(g.ending), "ending_name": ending_name,
		"t": t_end, "t0": g.trial.started_at if g.trial.active else 0.0, "downs": int(g.squad.downs_n),
		"tier": g.tier, "tier_name": D.tier_name(g.tier), "level": g.level, "elite": g.ch.elite if g.ch != null else 0,
		"kills": g.kills, "elites": g.elites_killed, "relics": g.relics.size(),
		"ops": ops, "op_out": tm.op_out.duplicate(true), "op_kills": tm.op_kills.duplicate(), "op_casts": tm.op_casts.duplicate(),
		"bins": tm.out_bins.duplicate(true), "bin_s": tm.BIN_S, "origin": origin,
		"heal": g.heal_log.duplicate(), "taken": g.dmg_log.duplicate(), "dark_dmg": tm.dark_dmg, "hits": tm.hits,
		"best": tm.best_hit.duplicate(), "bosses": bosses, "lamp_s": tm.lamp_s.duplicate(),
		"beacons": [int(g.beacon_sys.lit_n), g.beacons.size()], "dodges": tm.dodges, "dashes": tm.dashes, "blocks": tm.blocks,
		"low_hp_s": tm.low_hp_s, "fuse": fuse, "relic_list": relic_list, "killer": killer, "final_boss": final_boss,
		"xp": float(g.pickups.xp_total), "chests": tm.chests, "altars": tm.altars, "ingots_got": tm.ingots_got, "ingots_spent": tm.ingots_spent}


static func _sum(d: Dictionary) -> float:
	var s := 0.0
	for k in d:
		s += float(d[k])
	return s


## 最大余数法：整数百分比合计恰好 100（全为 0 时全 0）
static func pct_ints(vals: Array) -> Array:
	var tot := 0.0
	for v in vals:
		tot += float(v)
	var out: Array = []
	if tot <= 0.0:
		for v in vals:
			out.append(0)
		return out
	var rem: Array = []
	var used := 0
	for i in vals.size():
		var r: float = float(vals[i]) * 100.0 / tot
		out.append(int(floor(r)))
		used += int(floor(r))
		rem.append([r - floor(r), i])
	rem.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for k in mini(100 - used, rem.size()):
		out[rem[k][1]] += 1
	return out


## 承伤来源键 → 显示名（敌人按类型取名，同一敌人的接触 / 招式 / 冲击环合并）
static func taken_name(k: String) -> String:
	if TAKEN_NAME.has(k):
		return TAKEN_NAME[k]
	for p in TAKEN_PREFIX:
		if k.begins_with(p):
			var ty := k.substr(p.length())
			return str(D.ENEMIES.get(ty, {}).get("name", ty)).replace("\"", "")
	return k


## 环境击倒者的名字（docs/76 术语）
const ENV_NAME := {"zone": "黑潮", "mire": "溟痕", "dark": "寂灭", "hunt_ring": "围猎", "relic": "藏品代价", "bullet": "敌方弹幕",
	"corrode": "侵蚀", "wound": "侵蚀创口", "nerve": "神经损伤"}
const ENV_SUB := {"zone": "安全区外", "mire": "站在溟痕里", "dark": "灯火寂灭后的持续伤害", "hunt_ring": "围猎圈", "relic": "藏品的代价"}


## telemetry.killer() 的结果 → {type（敌人类型）, env（环境）, name, cause}
static func killer_info(k: Dictionary) -> Dictionary:
	var key := str(k.get("key", ""))
	var cause := str(k.get("cause", ""))
	if key.begins_with("e:"):
		var ty := key.substr(2)
		return {"type": ty, "env": "", "name": str(D.ENEMIES.get(ty, {}).get("name", ty)).replace("\"", ""), "cause": cause}
	if key.begins_with("env:"):
		var ev := key.substr(4)
		return {"type": "", "env": ev, "name": str(ENV_NAME.get(ev, ev)), "cause": cause if cause != "" else str(ENV_SUB.get(ev, ""))}
	return {}


## 承伤来源键 → 敌人类型（画头像用；黑潮、侵蚀等环境来源返回空串）
static func taken_type(k: String) -> String:
	for p in TAKEN_PREFIX:
		if k.begins_with(p):
			return k.substr(p.length())
	return ""


## 行顺序：主控在前，其余按入队时间
static func _join_order(a: Dictionary, b: Dictionary) -> bool:
	var la: bool = bool(a.get("leader", false))
	var lb: bool = bool(b.get("leader", false))
	if la != lb:
		return la
	return float(a.t) < float(b.t)


## 原始记录 → 界面模型
static func model(raw: Dictionary) -> Dictionary:
	var t_end: float = maxf(1.0, float(raw.get("t", 0.0)))
	var t0: float = float(raw.get("t0", 0.0))
	var op_out: Dictionary = raw.get("op_out", {})
	var heal: Dictionary = raw.get("heal", {})
	var origin: Dictionary = raw.get("origin", {})
	var rows: Array = []
	var joins: Array = raw.get("ops", []).duplicate()
	joins.sort_custom(_join_order)
	var seen := {}
	for j in joins:
		if seen.has(j.id):
			continue
		seen[j.id] = true
		var left: float = float(j.get("left", -1.0))
		var t_in: float = maxf(0.0, float(j.t) - t0)
		var t_out: float = (left - t0) if left >= 0.0 else t_end
		var c: Array = j.get("col", [0.6, 0.9, 1.0])
		rows.append({"key": j.id, "name": str(j.name), "en": str(j.get("en", "")), "col": Color(c[0], c[1], c[2]),
			"leader": bool(j.get("leader", false)), "join_t": t_in, "left_t": (left - t0) if left >= 0.0 else -1.0,
			"in_s": maxf(1.0, t_out - t_in - float(j.get("away", 0.0))), "elite": int(j.get("elite", 0)), "heal": float(heal.get(str(j.name), 0.0)), "src_d": op_out.get(j.id, {})})
	# 记录里有输出、却不在入队名单里的干员（理论上不会有）：并进「藏品与支援」，保证合计守恒
	var other_d: Dictionary = (op_out.get(OTHER, {}) as Dictionary).duplicate()
	for k in op_out:
		if k != OTHER and not seen.has(k):
			for s in op_out[k]:
				other_d[s] = float(other_d.get(s, 0.0)) + float(op_out[k][s])
	if _sum(other_d) > 0.0:
		rows.append({"key": OTHER, "name": "藏品与支援", "en": "RELICS & SUPPORT", "col": Color(0.55, 0.62, 0.72), "leader": false,
			"join_t": 0.0, "left_t": -1.0, "in_s": t_end, "elite": 0, "heal": 0.0, "src_d": other_d})
	var total := 0.0
	var dmgs: Array = []
	for r in rows:
		var dsum := _sum(r.src_d)
		r["dmg"] = dsum
		dmgs.append(dsum)
		total += dsum
	var pcts := pct_ints(dmgs)
	var kills: Dictionary = raw.get("op_kills", {})
	var casts: Dictionary = raw.get("op_casts", {})
	for i in rows.size():
		var r: Dictionary = rows[i]
		r["share"] = r.dmg / total if total > 0.0 else 0.0
		r["pct"] = pcts[i]
		r["dps"] = r.dmg / r.in_s
		r["kills"] = int(kills.get(r.key, 0))
		r["casts"] = int(casts.get(r.key, 0))
		var srcs: Array = []
		for s in r.src_d:
			var v: float = float(r.src_d[s])
			srcs.append({"name": str(s), "v": v, "share": v / r.dmg if r.dmg > 0.0 else 0.0,
				"kind": ORIGIN_NAME.get(str(origin.get(s, "relic" if r.key == OTHER else "core")), "其他")})
		srcs.sort_custom(func(a, b): return a.v > b.v or (a.v == b.v and a.name < b.name))
		var sp := pct_ints(srcs.map(func(x): return x.v))
		for k in srcs.size():
			srcs[k]["pct"] = sp[k]
		r["sources"] = srcs
		r.erase("src_d")
	# 时间线：每格（10 秒）各行的每秒伤害；行顺序同 rows
	var bin_s: float = float(raw.get("bin_s", 10.0))
	var bins: Array = raw.get("bins", [])
	var b0 := int(t0 / bin_s)
	var nb := maxi(1, int(ceil(t_end / bin_s)))
	var series: Array = []
	var peak := 0.0
	for bi in nb:
		var src_b: Dictionary = bins[b0 + bi] if b0 + bi < bins.size() else {}
		var col: Array = []
		var tot_b := 0.0
		for r in rows:
			var v: float = float(src_b.get(r.key, 0.0))
			if r.key == OTHER:
				for k in src_b:
					if not seen.has(k) and k != OTHER:
						v += float(src_b[k])
			col.append(v / bin_s)
			tot_b += v / bin_s
		series.append(col)
		peak = maxf(peak, tot_b)
	# Boss：登场 / 击破时刻（演练从开练算）
	var bosses: Array = []
	for b in raw.get("bosses", []):
		bosses.append({"name": str(b.name), "t0": maxf(0.0, float(b.t0) - t0), "t1": (float(b.t1) - t0) if float(b.t1) >= 0.0 else -1.0,
			"retreat": bool(b.get("retreat", false))})
	bosses.sort_custom(func(a, b): return a.t0 < b.t0)
	# 主控：承伤（按敌人合并）与回复来源
	var taken := {}
	for k in raw.get("taken", {}):
		var nm := taken_name(str(k))
		taken[nm] = float(taken.get(nm, 0.0)) + float(raw.taken[k])
	if float(raw.get("dark_dmg", 0.0)) > 0.5:
		taken[TAKEN_NAME.dark] = float(raw.dark_dmg)
	var taken_l: Array = []
	for k in taken:
		if float(taken[k]) >= 0.5:
			taken_l.append({"name": k, "v": float(taken[k])})
	taken_l.sort_custom(func(a, b): return a.v > b.v)
	var heal_l: Array = []
	for k in heal:
		if float(heal[k]) >= 0.5:
			heal_l.append({"name": str(k), "v": float(heal[k])})
	heal_l.sort_custom(func(a, b): return a.v > b.v)
	var best: Dictionary = raw.get("best", {})
	var best_op := ""
	for r in rows:
		if r.key == str(best.get("op", "")):
			best_op = r.name
	var relic_list: Array = raw.get("relic_list", [])
	var killed := 0
	for b in bosses:
		if float(b.t1) >= 0.0:
			killed += 1
	var casts_all := 0
	for r in rows:
		casts_all += int(r.casts)
	var ls: Array = raw.get("lamp_s", [0.0, 0.0, 0.0, 0.0])
	var lt := 0.0
	for v in ls:
		lt += float(v)
	var bc: Array = raw.get("beacons", [0, 0])
	var fu: Dictionary = raw.get("fuse", {})
	# 右栏统计表（雨中冒险 2 结算的「标签 — 数值」一列；docs/77 §2.3）。fmt：n 千分位 / t 时间 / pct 百分比 / txt 原样
	var stats: Array = [
		{"label": "探索时间", "v": t_end, "fmt": "t"},
		{"label": "击杀", "v": float(raw.get("kills", 0)), "fmt": "n"},
		{"label": "精英击杀", "v": float(raw.get("elites", 0)), "fmt": "n"},
		{"label": "Boss 击破", "v": float(killed), "fmt": "n"},
		{"label": "造成伤害", "v": total, "fmt": "n", "sub": "每秒 %d" % int(total / t_end)},
		{"label": "最高单次伤害", "v": float(best.get("v", 0.0)), "fmt": "n", "sub": str(best.get("src", "")) + ("（%s）" % best_op if best_op != "" else "")},
		{"label": "受到的伤害", "v": _sum(taken), "fmt": "n"},
		{"label": "生命回复", "v": _sum(heal), "fmt": "n"},
		{"label": "获得经验", "v": float(raw.get("xp", 0.0)), "fmt": "n", "sub": "Lv.%d" % int(raw.get("level", 1))},
		{"label": "获得源石锭", "v": float(raw.get("ingots_got", 0)), "fmt": "n", "sub": "花费 %d" % int(raw.get("ingots_spent", 0))},
		{"label": "打开补给箱", "v": float(raw.get("chests", 0)), "fmt": "n"}]
	if int(raw.get("altars", 0)) > 0:
		stats.append({"label": "海嗣祭坛", "v": float(raw.altars), "fmt": "n"})
	if int(bc[0]) > 0 or int(bc[1]) > 0:
		stats.append({"label": "点亮引航灯标", "v": float(bc[0]), "fmt": "n"})   # 只写点燃数：熄灭消散的灯标会从 g.beacons 移除，「出现数」不可靠
	stats.append({"label": "通明时长", "v": (float(ls[0]) / lt * 100.0) if lt > 0.0 else 0.0, "fmt": "pct"})
	stats.append({"label": "冲刺", "v": float(raw.get("dashes", 0)), "fmt": "n"})
	stats.append({"label": "技能发动", "v": float(casts_all), "fmt": "n"})
	stats.append({"label": "藏品", "v": float(relic_list.size()), "fmt": "n"})
	if bool(fu.get("on", false)):
		stats.append({"label": "源石锭熔铸", "v": float(fu.get("pct", 0.0)) * 100.0, "fmt": "txt", "txt": "全队伤害 +%s%%" % str(snappedf(float(fu.get("pct", 0.0)) * 100.0, 0.1)).trim_suffix(".0")})
	return {"relic_list": relic_list, "killer": raw.get("killer", {}), "final_boss": raw.get("final_boss", {}), "stats": stats,
		"result": str(raw.get("result", "dead")), "trial": bool(raw.get("trial", false)), "ending": str(raw.get("ending", "")),
		"ending_name": str(raw.get("ending_name", "")), "t": t_end, "tier": int(raw.get("tier", 0)), "tier_name": str(raw.get("tier_name", "")),
		"level": int(raw.get("level", 1)), "elite": int(raw.get("elite", 0)), "kills": int(raw.get("kills", 0)), "elites": int(raw.get("elites", 0)),
		"relics": int(raw.get("relics", 0)), "total": total, "dps": total / t_end, "rows": rows,
		"best": {"v": float(best.get("v", 0.0)), "src": str(best.get("src", "")), "op": best_op},
		"timeline": {"bin_s": bin_s, "series": series, "peak": peak}, "bosses": bosses,
		"lamp_s": raw.get("lamp_s", [0.0, 0.0, 0.0, 0.0]), "beacons": raw.get("beacons", [0, 0]), "fuse": raw.get("fuse", {}),
		"leader": {"taken": _sum(taken), "hits": int(raw.get("hits", 0)), "taken_src": taken_l, "heal": _sum(heal), "heal_src": heal_l,
			"dodges": int(raw.get("dodges", 0)), "dashes": int(raw.get("dashes", 0)), "blocks": int(raw.get("blocks", 0)),
			"low_hp_s": float(raw.get("low_hp_s", 0.0))}}


## 快检用：一份编的原始记录（四名干员、其中一人中途被替换、藏品与支援、三个 Boss）
static func fake_raw() -> Dictionary:
	var ops := [
		{"id": "mizuki", "name": "水月", "en": "MIZUKI", "col": [0.62, 0.55, 1.0], "leader": true, "t": 0.0, "left": -1.0, "elite": 2},
		{"id": "skadi", "name": "斯卡蒂", "en": "SKADI", "col": [0.35, 0.55, 0.95], "leader": false, "t": 192.0, "left": -1.0, "elite": 1},
		{"id": "saria", "name": "塞雷娅", "en": "SARIA", "col": [1.0, 0.72, 0.38], "leader": false, "t": 400.0, "left": 610.0, "elite": 0},
		{"id": "kaltsit", "name": "凯尔希", "en": "KAL'TSIT", "col": [0.55, 1.0, 0.5], "leader": false, "t": 485.0, "left": -1.0, "elite": 1},
	]
	var op_out := {"mizuki": {"伞击": 268000.0, "技能": 172000.0, "触手": 96000.0, "触须阵": 61000.0, "水刃": 22000.0},
		"skadi": {"大剑": 154000.0, "迅捷打击·γ型": 121000.0, "跃浪": 48000.0, "反手斩": 20000.0},
		"saria": {"拳击": 52000.0, "碎晶": 39000.0, "阻挡": 6000.0},
		"kaltsit": {"Mon3tr": 88000.0, "Mon3tr · 熔毁": 61000.0},
		OTHER: {"援护": 41000.0, "藏品": 30000.0, "地雷": 12000.0}}
	var origin := {"伞击": "core", "技能": "skill", "触手": "talent", "触须阵": "route", "水刃": "route", "大剑": "core", "迅捷打击·γ型": "skill",
		"跃浪": "skill", "反手斩": "talent", "拳击": "core", "碎晶": "skill", "阻挡": "talent", "Mon3tr": "core", "Mon3tr · 熔毁": "skill",
		"援护": "support", "藏品": "relic", "地雷": "relic"}
	var t := 742.0
	var bins: Array = []
	for bi in int(ceil(t / 10.0)):
		var b := {}
		for o in ops:
			if bi * 10.0 >= float(o.t) and (float(o.left) < 0.0 or bi * 10.0 < float(o.left)):
				b[o.id] = 4000.0 + 60.0 * bi + 900.0 * ((bi * 7 + o.id.length()) % 5)
		b[OTHER] = 1100.0
		bins.append(b)
	return {"result": "win", "trial": false, "ending": "standard", "ending_name": "结局一 · 平凡即是喜乐", "t": t, "t0": 0.0,
		"tier": 1, "tier_name": "波涛迭起·Ⅳ", "level": 41, "elite": 2, "kills": 3057, "elites": 23, "relics": 19,
		"ops": ops, "op_out": op_out, "op_kills": {"mizuki": 1412, "skadi": 903, "saria": 211, "kaltsit": 344, OTHER: 187},
		"op_casts": {"mizuki": 31, "skadi": 14, "saria": 9, "kaltsit": 6}, "bins": bins, "bin_s": 10.0, "origin": origin,
		"heal": {"凯尔希": 2310.0, "塞雷娅": 1840.0, "自身回复": 1210.0, "吸血": 640.0, "击杀回复": 380.0, "拾取": 300.0},
		"taken": {"boss_bishop": 1400.0, "contact_bishop": 740.0, "corrode": 1180.0, "zone": 760.0, "contact_slider": 540.0}, "dark_dmg": 39.0, "hits": 412,
		"best": {"v": 18412.0, "src": "迅捷打击·γ型", "op": "skadi", "t": 655.0},
		"bosses": [{"type": "path", "name": "塑路者", "t0": 210.0, "t1": 262.0}, {"type": "bishop", "name": "接潮主教", "t0": 420.0, "t1": 497.0},
			{"type": "paranoia", "name": "偏执泡影", "t0": 600.0, "t1": 742.0}],
		"lamp_s": [402.0, 231.0, 96.0, 13.0], "beacons": [4, 5], "dodges": 38, "dashes": 214, "blocks": 12, "low_hp_s": 72.0,
		"fuse": {"pool": 90, "pct": 0.06, "on": true},
		"relic_list": [{"id": "1", "name": "精选兽肉罐头", "cat": "编队协同", "rarity": "稀有", "lv": 1, "max": 1, "desc": "示例效果说明。"},
			{"id": "4", "name": "咖啡平原咖啡糖", "cat": "攻击与输出", "rarity": "基础", "lv": 3, "max": 3, "desc": "示例效果说明，两行以内。"},
			{"id": "42", "name": "“静音小队”", "cat": "攻击与输出", "rarity": "升华", "lv": 1, "max": 1, "desc": "升华藏品示例。"},
			{"id": "13", "name": "玻璃小鸟", "cat": "经济", "rarity": "基础", "lv": 2, "max": 3, "desc": "示例。"},
			{"id": "999", "name": "遭诅示例", "cat": "生存", "rarity": "遭诅古物", "lv": 1, "max": 1, "desc": "遭诅藏品示例。"}],
		"killer": {}, "final_boss": {"type": "paranoia", "name": "偏执泡影"},
		"xp": 4210.0, "chests": 6, "altars": 2, "ingots_got": 148, "ingots_spent": 120}
