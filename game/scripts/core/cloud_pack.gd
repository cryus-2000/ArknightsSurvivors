extends RefCounted
## B站 Toy 云存档的数据格式与合并规则（docs/89）。纯函数，不碰 Cfg / JS，单元测试 tests/cloud_save_test.gd 直接调。
##
## 存档正文 body（逻辑结构，和 settings.cfg 的字段一一对应，见 settings.gd cloud_body / cloud_apply）：
##   {"set": {"t": 设置最后修改的 Unix 秒, "d": {设置键: 值, "touch_layout": 触屏按键布局}},
##    "prog": {"diff": 已解锁最高难度档, "gal": 图鉴已见, "rel": 已见藏品, "end": 已达成结局, "shows": 已看演出,
##             "intro": 看过开局指南, "open": 看过完整开场}}
## 上云格式：body → 排序键的 JSON（非 ASCII 字符转 \uXXXX，字符数 = 字节数）→ 每 CHUNK 字节一片，key sy_d0 … sy_d{n-1}；
## 头 sy_h = {"v": 格式版本, "minv": 能读这份存档的最低版本, "t": 上传时刻 Unix 秒, "n": 片数, "len": 总长, "md5": 全文 md5}。
## 头和各片在同一次 setCloudStorage 里写。
## 平台限制：每 Toy 每用户 ≤ 128 个 key，key [A-Za-z0-9_-] ≤ 128 字节、不以 __ 开头，value ≤ 1024 字节。
##
## 版本升级不丢档（用户 10-13，docs/89 §3.1）：
##   - 只加字段的改动（新干员 / 藏品 / 结局 / 设置项）不升 minv：旧版本照常读写，看不懂的字段（顶层、set.d、prog 里的未知键）
##     原样透传，合并、回写都不丢；缺的字段按缺省补齐（合并时只认存在的字段，cloud_apply 缺字段保持本地值）。
##   - v 只升不降：回写时头里写 max(本版, 云端 v)，minv 也取较大值。
##   - 不兼容的改动才升 minv：minv 高于本版 → 只读保护（不读、不写、不覆盖云端），本地照常玩。
##   - 新版本读旧格式：按 MIGRATIONS 逐级 v → v+1 迁移。

const VERSION := 1           # 本版写出的格式版本
const MIN_READ := 1          # 本版写出的存档，读者至少要是这个版本（只加字段时不升）
const HEAD_KEY := "sy_h"
const CHUNK_PREFIX := "sy_d"
const CHUNK := 1000          # 每片字节数（上限 1024，留余量）
const MAX_CHUNKS := 48       # 正文上限 48 KB（49 个 key）；其余 key 留给以后的功能
const KEY_LIMIT := 128
const VALUE_LIMIT := 1024
## ops = 解锁过的干员、optier = 已首通的难度档（发过人事调度函），都取并集；opst = 名册的券与抽取状态（merge_opst）
const LIST_KEYS := ["gal", "rel", "end", "shows", "ops", "optier"]
const OPTIONAL_KEYS := ["ops", "optier", "opst", "meta"]   # 只在正文里有时才规范化 / 合并
const PROG_KEYS := ["diff", "gal", "rel", "end", "shows", "intro", "open", "ops", "optier", "opst", "meta"]
## 格式迁移：{旧版本 v: 把 v 版正文改成 v+1 版的静态函数名}。目前只有 v1，没有迁移；以后改格式时在这里登记（单测覆盖）
const MIGRATIONS := {}


## 比较用的规范串：排序键 JSON，数字一律按 JSON 往返后的形式（int 2 与 float 2.0 视为相同）
static func canon(v) -> String:
	var p = parse(JSON.stringify(v, "", true))
	return JSON.stringify(p, "", true)


## body 的签名（上传内容是否变了）：不含头里的时间戳
static func sig(body: Dictionary) -> String:
	return canon(body).md5_text()


## 解析 JSON；不合法返回 null（不像 JSON.parse_string 那样往控制台报错）
static func parse(s: String):
	var j := JSON.new()
	return j.data if j.parse(s) == OK else null


## JSON 串里的非 ASCII 字符转成 \uXXXX（超出基本平面的拆成代理对）：之后字符数 = UTF-8 字节数，按字符切片不会切坏多字节字
static func ascii_json(v) -> String:
	var s := canon(v)
	if s.to_utf8_buffer().size() == s.length():
		return s
	var out := PackedStringArray()
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 128:
			out.append(String.chr(c))
		elif c < 0x10000:
			out.append("\\u%04x" % c)
		else:
			var u := c - 0x10000
			out.append("\\u%04x\\u%04x" % [0xD800 + (u >> 10), 0xDC00 + (u & 0x3FF)])
	return "".join(out)


## 打包：返回 {"items": {key: value}, "err": ""}；超出 MAX_CHUNKS 时 err = "too_big"、items 为空（不上传）。
## v / minv：头里写的版本，调用方传 max(本版, 见过的云端版本)，保证只升不降
static func pack(body: Dictionary, t: int, v := VERSION, minv := MIN_READ) -> Dictionary:
	var s := ascii_json(body)
	var n: int = maxi(1, ceili(s.length() / float(CHUNK)))
	if n > MAX_CHUNKS:
		return {"items": {}, "err": "too_big"}
	var items := {}
	for i in n:
		items[CHUNK_PREFIX + str(i)] = s.substr(i * CHUNK, CHUNK)
	items[HEAD_KEY] = JSON.stringify({"v": maxi(v, VERSION), "minv": maxi(minv, MIN_READ), "t": t, "n": n, "len": s.length(), "md5": s.md5_text()})
	return {"items": items, "err": ""}


## key / value 是否符合平台限制（打包结果自检，测试也用）
static func items_ok(items: Dictionary) -> bool:
	if items.size() > KEY_LIMIT:
		return false
	var re := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	for k in items:
		var ks := str(k)
		if ks.begins_with("__") or ks.to_utf8_buffer().size() > 128 or re.search(ks) == null:
			return false
		if not (items[k] is String) or str(items[k]).to_utf8_buffer().size() > VALUE_LIMIT:
			return false
	return true


## 解包：items 是 getCloudStorage 的结果（可含别的 key）。
## 返回 {"status": "empty" | "ok" | "bad" | "newer", "body": {}, "t": 上传时刻, "v": 版本, "minv": 最低读者版本, "err": 说明}
##   empty：云端没有本游戏的存档；bad：头 / 分片 / 校验 / 结构不对（不覆盖本地）；
##   newer：minv 高于本版（不兼容的新格式）→ 只读保护，不读也不写。v 高于本版但 minv 不高 → 照常 ok（未知字段透传）
static func unpack(items: Dictionary, reader := VERSION, migrations := MIGRATIONS) -> Dictionary:
	if not items.has(HEAD_KEY):
		return {"status": "empty", "body": {}, "t": 0, "v": 0, "minv": 0, "err": ""}
	var h = parse(str(items[HEAD_KEY]))
	if not (h is Dictionary) or not _num(h.get("v")) or not _num(h.get("n")) or not _num(h.get("len")) or not (h.get("md5") is String):
		return _bad("头格式不对")
	var v := int(h.v)
	var minv := int(h.minv) if _num(h.get("minv")) else v   # 没写 minv 的头按「要求读者 ≥ v」
	var t := int(h.t) if _num(h.get("t")) else 0
	if v < 1 or minv < 1 or minv > v:
		return _bad("版本号不对：v=%d minv=%d" % [v, minv])
	if minv > reader:
		return {"status": "newer", "body": {}, "t": t, "v": v, "minv": minv, "err": "云端存档要求版本 %d，本版 %d" % [minv, reader]}
	var n := int(h.n)
	if n < 1 or n > MAX_CHUNKS:
		return _bad("分片数不对：%d" % n)
	var parts := PackedStringArray()
	for i in n:
		var k := CHUNK_PREFIX + str(i)
		if not items.has(k):
			return _bad("缺分片 %s" % k)
		parts.append(str(items[k]))
	var s := "".join(parts)
	if s.length() != int(h.len) or s.md5_text() != str(h.md5):
		return _bad("校验不符")
	var body = parse(s)
	if body is Dictionary and v < reader:
		body = migrate(body, v, reader, migrations)
	if not valid_body(body):
		return _bad("正文结构不对")
	return {"status": "ok", "body": normalize(body), "t": t, "v": v, "minv": minv, "err": ""}


## 逐级迁移 from → to（每一级是 migrations[v]：Callable 或本脚本里的静态函数名）。缺某一级时原样返回（只加字段的版本不需要迁移）
static func migrate(body: Dictionary, from: int, to: int, migrations := MIGRATIONS) -> Dictionary:
	var b := body
	for v in range(from, to):
		if not migrations.has(v):
			continue
		var f = migrations[v]
		var cb: Callable = f if f is Callable else Callable(load("res://scripts/core/cloud_pack.gd"), str(f))
		b = cb.call(b)
	return b


static func _bad(why: String) -> Dictionary:
	return {"status": "bad", "body": {}, "t": 0, "v": 0, "minv": 0, "err": why}


static func _num(x) -> bool:
	return x is int or x is float


## 结构校验只看本版认识、且存在的字段的类型；缺的字段按缺省（normalize 补），多出的字段不管
static func valid_body(b) -> bool:
	if not (b is Dictionary):
		return false
	var st = b.get("set", {})
	var pr = b.get("prog", {})
	if not (st is Dictionary) or not (pr is Dictionary):
		return false
	if st.has("t") and not _num(st.t):
		return false
	if st.has("d") and not (st.d is Dictionary):
		return false
	if pr.has("diff") and not _num(pr.diff):
		return false
	for k in LIST_KEYS:
		if pr.has(k) and not (pr[k] is Array):
			return false
	return true


## 规范化：认识的字段补缺省并转类型（列表只留字符串并去重、数字转 int、布尔转 bool）；不认识的字段原样保留
static func normalize(b: Dictionary) -> Dictionary:
	var out: Dictionary = b.duplicate(true)
	var pr: Dictionary = (b.get("prog", {}) as Dictionary).duplicate(true)
	pr["diff"] = int(pr.get("diff", 0))
	pr["intro"] = bool(pr.get("intro", false))
	pr["open"] = bool(pr.get("open", false))
	if pr.has("opst"):
		pr["opst"] = (pr.opst as Dictionary).duplicate(true) if pr.opst is Dictionary else {}
	for k in LIST_KEYS:
		if k in OPTIONAL_KEYS and not pr.has(k):
			continue   # 名册字段（P1 之后才有）：旧正文里没有就不补，往返与旧版本逐字相同
		var arr := []
		for x in pr.get(k, []):
			var xs := str(x)
			if not arr.has(xs):
				arr.append(xs)
		pr[k] = arr
	var st: Dictionary = b.get("set", {})
	out["set"] = {"t": int(st.get("t", 0)), "d": (st.get("d", {}) as Dictionary).duplicate(true)}
	for k in st:
		if not (k in ["t", "d"]):
			out.set[k] = st[k]
	out["prog"] = pr
	return out


## 名册状态合并（docs/109 §12.5）：待用的券 / 多余的券按种类取较大值（两台设备各领一张不会翻倍；
## 一台用掉、另一台还没同步时可能多留一张，可接受）；已用券数取较大值，保底计数跟着已用券数较大的一份；
## 意向干员和种子优先本地（本地为空 / 0 时用云端）
static func merge_opst(l: Dictionary, c: Dictionary) -> Dictionary:
	var out := {}
	for key in ["tk", "sp"]:
		var m := {}
		var a: Dictionary = l.get(key, {}) if l.get(key) is Dictionary else {}
		var b: Dictionary = c.get(key, {}) if c.get(key) is Dictionary else {}
		for k in a:
			m[k] = maxi(int(a[k]), int(m.get(k, 0)))
		for k in b:
			m[k] = maxi(int(b[k]), int(m.get(k, 0)))
		out[key] = m
	var ld := int(l.get("draws", 0))
	var cd := int(c.get("draws", 0))
	out["draws"] = maxi(ld, cd)
	out["pity"] = int(l.get("pity", 0)) if ld >= cd else int(c.get("pity", 0))
	out["wish"] = str(l.get("wish", "")) if str(l.get("wish", "")) != "" else str(c.get("wish", ""))
	out["seed"] = int(l.get("seed", 0)) if int(l.get("seed", 0)) != 0 else int(c.get("seed", 0))
	return out


## 局外成长合并（docs/109 §7.2）：生机细胞按设备号逐项取较大值（总数 = 各设备之和；整体取大会丢另一台设备、整体相加会翻倍）；
## 首通赏金取并集；认知塑造跟修改时刻较新的一份（一样新用本地）。余额不够时由 Cfg 侧重置（免费）
static func merge_meta(l: Dictionary, c: Dictionary) -> Dictionary:
	var l2: Dictionary = l if l is Dictionary else {}
	var c2: Dictionary = c if c is Dictionary else {}
	var earned := {}
	for src in [l2.get("earned", {}), c2.get("earned", {})]:
		if src is Dictionary:
			for k in src:
				earned[k] = maxi(int(src[k]), int(earned.get(k, 0)))
	var newer: Dictionary = c2 if int(c2.get("t", 0)) > int(l2.get("t", 0)) else l2
	return {"earned": earned, "bounty": union(l2.get("bounty", []), c2.get("bounty", [])),
		"shape": (newer.get("shape", {}) as Dictionary).duplicate() if newer.get("shape") is Dictionary else {}, "t": int(newer.get("t", 0))}


## 两份正文哪些字段不同（日志用）：["set.t", "set.d.master", "prog.rel", "ops"……]
static func diff_keys(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	var na := normalize(a) if valid_body(a) else a
	var nb := normalize(b) if valid_body(b) else b
	for k in _keys(na, nb):
		if k == "set" or k == "prog":
			continue
		if canon(na.get(k)) != canon(nb.get(k)):
			out.append(str(k))
	for k in _keys(na.get("prog", {}), nb.get("prog", {})):
		if canon(na.get("prog", {}).get(k)) != canon(nb.get("prog", {}).get(k)):
			out.append("prog." + str(k))
	var sa: Dictionary = na.get("set", {})
	var sb: Dictionary = nb.get("set", {})
	for k in _keys(sa, sb):
		if k == "d":
			for dk in _keys(sa.get("d", {}), sb.get("d", {})):
				if canon(sa.get("d", {}).get(dk)) != canon(sb.get("d", {}).get(dk)):
					out.append("set.d." + str(dk))
		elif canon(sa.get(k)) != canon(sb.get(k)):
			out.append("set." + str(k))
	return out


static func _keys(a, b) -> Array:
	var out := []
	for d in [a, b]:
		if d is Dictionary:
			for k in d:
				if not out.has(k):
					out.append(k)
	return out


## 并集：保留 a 的顺序，再接上 b 里 a 没有的
static func union(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for x in b:
		if not out.has(x):
			out.append(x)
	return out


## 合并（启动读云端、每次上传前都走这里）：
##   进度：解锁 / 收集 / 结局 / 图鉴取并集，已解锁难度取较大值，看过指南 / 开场取「或」；
##   设置：取 set.t（最后修改时刻）较新的一份，一样新时用本地；
##   不认识的字段（新版本加的）：两边都透传，同名时设置跟着较新的一份、其余以云端为准（本版不知道怎么合并它，云端是写它的新版本给的）。
## cloud 为空字典 = 云端没有存档，结果就是本地。
static func merge(local: Dictionary, cloud: Dictionary) -> Dictionary:
	if cloud.is_empty():
		return local.duplicate(true)
	var l := normalize(local)
	var c := normalize(cloud)
	var out: Dictionary = l.duplicate(true)
	out.merge(c.duplicate(true), true)   # 顶层未知字段：云端为准、本地独有的保留
	var lp: Dictionary = l.prog
	var cp: Dictionary = c.prog
	var p: Dictionary = lp.duplicate(true)
	p.merge(cp.duplicate(true), true)    # prog 里的未知字段同上
	p["diff"] = maxi(int(lp.diff), int(cp.diff))
	p["intro"] = bool(lp.intro) or bool(cp.intro)
	p["open"] = bool(lp.open) or bool(cp.open)
	for k in LIST_KEYS:
		if lp.has(k) or cp.has(k):
			p[k] = union(lp.get(k, []), cp.get(k, []))
	if lp.has("opst") or cp.has("opst"):
		p["opst"] = merge_opst(lp.get("opst", {}), cp.get("opst", {}))
	if lp.has("meta") or cp.has("meta"):
		p["meta"] = merge_meta(lp.get("meta", {}), cp.get("meta", {}))
	var cloud_newer: bool = int(c.set.t) > int(l.set.t)
	var win: Dictionary = c.set if cloud_newer else l.set
	var lose: Dictionary = l.set if cloud_newer else c.set
	var s: Dictionary = lose.duplicate(true)
	s.merge(win.duplicate(true), true)   # set 顶层（t、d 以外的未知字段）
	var d: Dictionary = (lose.d as Dictionary).duplicate(true)
	d.merge((win.d as Dictionary).duplicate(true), true)   # 较新一份的设置为准；另一份独有的设置项（对方版本才有的）保留
	s["t"] = int(win.t)
	s["d"] = d
	out["set"] = s
	out["prog"] = p
	return out
