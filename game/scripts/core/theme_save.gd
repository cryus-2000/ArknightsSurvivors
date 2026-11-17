extends RefCounted
## 存档按主题分开（docs/357 §4、docs/365）：主题相关的进度字段按主题 id 存，其余（干员、寻访凭证、认知塑造、设置、键位、引导）全局。
## 纯函数，不碰 Cfg 以外的东西；settings.gd 读写存档、云存档打包时调，tests/theme_save_test.gd 直接测。
##
## 内存里 Cfg 的这几个字段始终是「当前主题」那一份（读它们的几十处代码不用改）；别的主题的存在 Cfg.theme_saves。
## settings.cfg：
##   [theme_<id>] 段：每个主题一段，键 = 下面 FIELDS 的字段名。
##   旧位置（[progress] diff_unlocked / diff_best / gallery_seen / seen_relics / event_log / endings_cleared、[meta] bounty、
##   [medals] got / best）：继续写水月（deep_sea）那一份，给旧版本读（降级不丢进度）。
## 读档：水月 = [theme_deep_sea] 段与旧位置按字段合并（并集 / 取大，MERGE），所以
##   - 旧存档（没有主题段）：旧位置原样成为水月的进度——迁移；
##   - 新存档：两处相同，合并结果不变——幂等；
##   - 新版写过、旧版又玩过再回到新版：旧版在旧位置新增的进度也并进来，不丢。
## 云存档（docs/89）：prog 里原有的 diff / gal / rel / end / dbest / med / meta.bounty 继续是水月那一份（旧版本照常读写）；
##   其他主题放进 prog.th = {id: {"diff", "gal", "rel", "end", "dbest", "bounty", "med"}}（CloudPack.VERSION 2；旧版本把 th 当未知字段原样透传）。
##   事件图鉴 event_log 本来就不上云，主题段里也不上。

const CloudPack = preload("res://scripts/core/cloud_pack.gd")

const LEGACY := "deep_sea"     # 旧存档的进度都属于这个主题（水月与深蓝之树）
const SEC := "theme_"          # settings.cfg 段名前缀
## 字段 → 合并方式
const FIELDS := {
	"endings_cleared": "list",   # 已达成的结局 id
	"gallery_seen": "list",      # 图鉴已见（enemy:<敌种> / item:<掉落物、景物、商人>）
	"seen_relics": "list",       # 获得过的藏品
	"event_log": "evlog",        # 事件图鉴 {seen, opt, pick}
	"diff_unlocked": "max",      # 已解锁的最高难度档
	"diff_best": "dbest",        # 各档最佳成绩
	"meta_bounty": "list",       # 已领首通赏金的潮位
	"medals": "got",             # 蚀刻章 {key: 获得时刻}
	"medal_best": "maxmap",      # 蚀刻章历史最好进度 {key: 数}
}
## 内存里全部解锁（调试 / 对内包）时真实值在 Cfg._real_progress 的字段
const REAL_KEYS := ["diff_unlocked", "seen_relics", "endings_cleared"]


static func defaults() -> Dictionary:
	return {"endings_cleared": [], "gallery_seen": [], "seen_relics": [], "event_log": {}, "diff_unlocked": 0, "diff_best": {},
		"meta_bounty": [], "medals": {}, "medal_best": {}}


## 当前主题的进度（从 Cfg 字段拷出来；全部解锁时取真实值）
static func snapshot(cfg) -> Dictionary:
	var out := {}
	var real: Dictionary = cfg.get("_real_progress") if cfg.get("_real_progress") is Dictionary else {}
	for f in FIELDS:
		var v = real[f] if real.has(f) else cfg.get(f)
		out[f] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## 写回 Cfg 字段（缺的字段用缺省；类型不对的也用缺省）
static func restore(cfg, d: Dictionary) -> void:
	var df := defaults()
	for f in FIELDS:
		var v = d.get(f, df[f])
		if typeof(v) != typeof(df[f]) and not (f == "diff_unlocked" and v is float):
			v = df[f]
		if f == "diff_unlocked":
			v = int(v)
		cfg.set(f, v.duplicate(true) if (v is Array or v is Dictionary) else v)


## 两份主题进度按字段合并（a 的顺序在前）：列表并集、难度取大、最佳成绩 / 蚀刻章按云存档同样的规则、事件图鉴次数取大
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	var df := defaults()
	for f in FIELDS:
		var has_a := a.has(f)
		var has_b := b.has(f)
		if not has_a and not has_b:
			continue
		var x = a.get(f, df[f])
		var y = b.get(f, df[f])
		match FIELDS[f]:
			"list":
				out[f] = CloudPack.union(x if x is Array else [], y if y is Array else [])
			"max":
				out[f] = maxi(int(x), int(y))
			"dbest":
				out[f] = CloudPack.merge_dbest(x, y)
			"got":
				out[f] = CloudPack.merge_med({"got": x}, {"got": y}).got
			"maxmap":
				out[f] = CloudPack.merge_med({"best": x}, {"best": y}).best
			"evlog":
				out[f] = merge_evlog(x, y)
	return out


## 事件图鉴：遇到 / 选过次数取大，见过的选项取或；本版不认识的子段以 a 为准
static func merge_evlog(a, b) -> Dictionary:
	var x: Dictionary = a if a is Dictionary else {}
	var y: Dictionary = b if b is Dictionary else {}
	var out: Dictionary = y.duplicate(true)
	out.merge(x.duplicate(true), true)
	for k in ["seen", "pick"]:
		if x.get(k) is Dictionary or y.get(k) is Dictionary:
			var m := {}
			for src in [x.get(k, {}), y.get(k, {})]:
				if src is Dictionary:
					for e in src:
						m[e] = maxi(int(m.get(e, 0)), int(src[e]))
			out[k] = m
	if x.get("opt") is Dictionary or y.get("opt") is Dictionary:
		var o := {}
		for src in [x.get("opt", {}), y.get("opt", {})]:
			if src is Dictionary:
				for e in src:
					o[e] = bool(o.get(e, false)) or bool(src[e])
		out["opt"] = o
	return out


## ---- settings.cfg
static func section(tid: String) -> String:
	return SEC + tid


## 读一个主题段（只含存在的键）
static func read_section(c: ConfigFile, tid: String) -> Dictionary:
	var out := {}
	var sec := section(tid)
	if not c.has_section(sec):
		return out
	for f in FIELDS:
		if c.has_section_key(sec, f):
			out[f] = c.get_value(sec, f)
	return out


## 存档里所有主题段 {id: 进度}
static func read_all(c: ConfigFile) -> Dictionary:
	var out := {}
	for sec in c.get_sections():
		if str(sec).begins_with(SEC):
			out[str(sec).substr(SEC.length())] = read_section(c, str(sec).substr(SEC.length()))
	return out


static func write_section(c: ConfigFile, tid: String, d: Dictionary) -> void:
	var df := defaults()
	for f in FIELDS:
		c.set_value(section(tid), f, d.get(f, df[f]))


## 旧位置（给旧版本读的水月镜像）
static func read_legacy(c: ConfigFile) -> Dictionary:
	var out := {}
	for pair in [["progress", "endings_cleared", "endings_cleared"], ["progress", "gallery_seen", "gallery_seen"], ["progress", "seen_relics", "seen_relics"],
			["progress", "event_log", "event_log"], ["progress", "diff_unlocked", "diff_unlocked"], ["progress", "diff_best", "diff_best"],
			["meta", "bounty", "meta_bounty"], ["medals", "got", "medals"], ["medals", "best", "medal_best"]]:
		if c.has_section_key(pair[0], pair[1]):
			out[pair[2]] = c.get_value(pair[0], pair[1])
	return out


static func write_legacy(c: ConfigFile, d: Dictionary) -> void:
	var df := defaults()
	c.set_value("progress", "endings_cleared", d.get("endings_cleared", df.endings_cleared))
	c.set_value("progress", "gallery_seen", d.get("gallery_seen", df.gallery_seen))
	c.set_value("progress", "seen_relics", d.get("seen_relics", df.seen_relics))
	c.set_value("progress", "event_log", d.get("event_log", df.event_log))
	c.set_value("progress", "diff_unlocked", d.get("diff_unlocked", df.diff_unlocked))
	c.set_value("progress", "diff_best", d.get("diff_best", df.diff_best))
	c.set_value("meta", "bounty", d.get("meta_bounty", df.meta_bounty))
	c.set_value("medals", "got", d.get("medals", df.medals))
	c.set_value("medals", "best", d.get("medal_best", df.medal_best))


## ---- 云存档：prog.th 里一个主题的正文（短键，同 prog 的旧键）
static func to_cloud(d: Dictionary) -> Dictionary:
	var df := defaults()
	return {"diff": int(d.get("diff_unlocked", 0)), "gal": (d.get("gallery_seen", []) as Array).duplicate(), "rel": (d.get("seen_relics", []) as Array).duplicate(),
		"end": (d.get("endings_cleared", []) as Array).duplicate(), "dbest": (d.get("diff_best", df.diff_best) as Dictionary).duplicate(true),
		"bounty": (d.get("meta_bounty", []) as Array).duplicate(), "med": {"got": (d.get("medals", {}) as Dictionary).duplicate(), "best": (d.get("medal_best", {}) as Dictionary).duplicate()}}


## 云端一个主题的正文 → 进度字段（类型不对的项跳过；event_log 不上云，不在这里）
static func from_cloud(t) -> Dictionary:
	var out := {}
	if not (t is Dictionary):
		return out
	if t.get("diff") is int or t.get("diff") is float:
		out["diff_unlocked"] = int(t.diff)
	for pair in [["gal", "gallery_seen"], ["rel", "seen_relics"], ["end", "endings_cleared"]]:
		if t.get(pair[0]) is Array:
			out[pair[1]] = t[pair[0]].map(func(x): return str(x))
	if t.get("bounty") is Array:
		out["meta_bounty"] = t.bounty.map(func(x): return int(x))
	if t.get("dbest") is Dictionary:
		out["diff_best"] = (t.dbest as Dictionary).duplicate(true)
	if t.get("med") is Dictionary:
		var m := CloudPack.merge_med(t.med, {})
		out["medals"] = m.got
		out["medal_best"] = m.best
	return out


## 两份 prog.th 合并（每个主题：难度取大、列表并集、最佳成绩 / 蚀刻章同旧键的规则）；本版不认识的子键以云端为准
static func merge_cloud_th(l, c) -> Dictionary:
	var a: Dictionary = l if l is Dictionary else {}
	var b: Dictionary = c if c is Dictionary else {}
	var out := {}
	for tid in CloudPack._keys(a, b):
		var x: Dictionary = a.get(tid, {}) if a.get(tid) is Dictionary else {}
		var y: Dictionary = b.get(tid, {}) if b.get(tid) is Dictionary else {}
		var o: Dictionary = x.duplicate(true)
		o.merge(y.duplicate(true), true)
		if x.has("diff") or y.has("diff"):
			o["diff"] = maxi(int(x.get("diff", 0)), int(y.get("diff", 0)))
		for k in ["gal", "rel", "end", "bounty"]:
			if x.has(k) or y.has(k):
				o[k] = CloudPack.union(x.get(k, []) if x.get(k) is Array else [], y.get(k, []) if y.get(k) is Array else [])
		if x.has("dbest") or y.has("dbest"):
			o["dbest"] = CloudPack.merge_dbest(x.get("dbest", {}), y.get("dbest", {}))
		if x.has("med") or y.has("med"):
			o["med"] = CloudPack.merge_med(x.get("med", {}), y.get("med", {}))
		out[tid] = o
	return out
