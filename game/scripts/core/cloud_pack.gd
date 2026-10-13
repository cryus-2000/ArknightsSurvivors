extends RefCounted
## B站 Toy 云存档的数据格式与合并规则（docs/89）。纯函数，不碰 Cfg / JS，单元测试 tests/cloud_save_test.gd 直接调。
##
## 存档正文 body（逻辑结构，和 settings.cfg 的字段一一对应，见 settings.gd cloud_body / cloud_apply）：
##   {"set": {"t": 设置最后修改的 Unix 秒, "d": {设置键: 值, "touch": 触屏按键布局}},
##    "prog": {"diff": 已解锁最高难度档, "gal": 图鉴已见, "rel": 已见藏品, "end": 已达成结局, "shows": 已看演出,
##             "intro": 看过开局指南, "open": 看过完整开场}}
## 上云格式：body → 排序键的 JSON（非 ASCII 字符转 \uXXXX，字符数 = 字节数）→ 每 CHUNK 字节一片，key sy_d0 … sy_d{n-1}；
## 头 sy_h = {"v": 格式版本, "t": 上传时刻 Unix 秒, "n": 片数, "len": 总长, "md5": 全文 md5}。头和各片在同一次 setCloudStorage 里写。
## 平台限制：每 Toy 每用户 ≤ 128 个 key，key [A-Za-z0-9_-] ≤ 128 字节、不以 __ 开头，value ≤ 1024 字节。

const VERSION := 1
const HEAD_KEY := "sy_h"
const CHUNK_PREFIX := "sy_d"
const CHUNK := 1000          # 每片字节数（上限 1024，留余量）
const MAX_CHUNKS := 48       # 正文上限 48 KB（49 个 key）；其余 key 留给以后的功能
const KEY_LIMIT := 128
const VALUE_LIMIT := 1024
const LIST_KEYS := ["gal", "rel", "end", "shows"]


## 比较用的规范串：排序键 JSON，数字一律按 JSON 往返后的形式（int 2 与 float 2.0 视为相同）
static func canon(v) -> String:
	var p = JSON.parse_string(JSON.stringify(v, "", true))
	return JSON.stringify(p, "", true)


## body 的签名（上传内容是否变了）：不含头里的时间戳
static func sig(body: Dictionary) -> String:
	return canon(body).md5_text()


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


## 打包：返回 {"items": {key: value}, "err": ""}；超出 MAX_CHUNKS 时 err = "too_big"、items 为空（不上传）
static func pack(body: Dictionary, t: int) -> Dictionary:
	var s := ascii_json(body)
	var n: int = maxi(1, ceili(s.length() / float(CHUNK)))
	if n > MAX_CHUNKS:
		return {"items": {}, "err": "too_big"}
	var items := {}
	for i in n:
		items[CHUNK_PREFIX + str(i)] = s.substr(i * CHUNK, CHUNK)
	items[HEAD_KEY] = JSON.stringify({"v": VERSION, "t": t, "n": n, "len": s.length(), "md5": s.md5_text()})
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
## 返回 {"status": "empty" | "ok" | "bad" | "newer", "body": {}, "t": 上传时刻, "err": 说明}
##   empty：云端没有本游戏的存档；bad：头 / 分片 / 校验 / 结构不对（不覆盖本地）；newer：更新版本的游戏写的（不读也不写）
static func unpack(items: Dictionary) -> Dictionary:
	if not items.has(HEAD_KEY):
		return {"status": "empty", "body": {}, "t": 0, "err": ""}
	var h = parse(str(items[HEAD_KEY]))
	if not (h is Dictionary) or not _num(h.get("v")) or not _num(h.get("n")) or not _num(h.get("len")) or not (h.get("md5") is String):
		return _bad("头格式不对")
	var v := int(h.v)
	if v > VERSION:
		return {"status": "newer", "body": {}, "t": int(h.get("t", 0)) if _num(h.get("t")) else 0, "err": "云端格式版本 %d 高于本版 %d" % [v, VERSION]}
	if v < 1:
		return _bad("版本号不对")
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
	if not valid_body(body):
		return _bad("正文结构不对")
	return {"status": "ok", "body": normalize(body), "t": int(h.get("t", 0)) if _num(h.get("t")) else 0, "err": ""}


## 解析 JSON；不合法返回 null（不像 JSON.parse_string 那样往控制台报错）
static func parse(s: String):
	var j := JSON.new()
	return j.data if j.parse(s) == OK else null


static func _bad(why: String) -> Dictionary:
	return {"status": "bad", "body": {}, "t": 0, "err": why}


static func _num(x) -> bool:
	return x is int or x is float


static func valid_body(b) -> bool:
	if not (b is Dictionary):
		return false
	var st = b.get("set")
	var pr = b.get("prog")
	if not (st is Dictionary) or not (pr is Dictionary):
		return false
	if not _num(st.get("t")) or not (st.get("d") is Dictionary):
		return false
	if not _num(pr.get("diff")):
		return false
	for k in LIST_KEYS:
		if not (pr.get(k, []) is Array):
			return false
	return true


## 规范化：列表只留字符串并去重、数字转 int、布尔转 bool（云端来的数据先过这里）
static func normalize(b: Dictionary) -> Dictionary:
	var pr: Dictionary = b.prog
	var out_p := {"diff": int(pr.diff), "intro": bool(pr.get("intro", false)), "open": bool(pr.get("open", false))}
	for k in LIST_KEYS:
		var arr := []
		for x in pr.get(k, []):
			var xs := str(x)
			if not arr.has(xs):
				arr.append(xs)
		out_p[k] = arr
	return {"set": {"t": int(b.set.t), "d": (b.set.d as Dictionary).duplicate(true)}, "prog": out_p}


## 并集：保留 a 的顺序，再接上 b 里 a 没有的
static func union(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for x in b:
		if not out.has(x):
			out.append(x)
	return out


## 合并（启动读云端、每次上传前都走这里）：
##   进度：解锁 / 收集 / 结局 / 图鉴取并集，已解锁难度取较大值，看过指南 / 开场取「或」；
##   设置：取 set.t（最后修改时刻）较新的一份，一样新时用本地。
## cloud 为空字典 = 云端没有存档，结果就是本地。
static func merge(local: Dictionary, cloud: Dictionary) -> Dictionary:
	if cloud.is_empty():
		return local.duplicate(true)
	var lp: Dictionary = local.prog
	var cp: Dictionary = cloud.prog
	var p := {"diff": maxi(int(lp.diff), int(cp.diff)),
		"intro": bool(lp.get("intro", false)) or bool(cp.get("intro", false)),
		"open": bool(lp.get("open", false)) or bool(cp.get("open", false))}
	for k in LIST_KEYS:
		p[k] = union(lp.get(k, []), cp.get(k, []))
	var s: Dictionary = (cloud.set if int(cloud.set.t) > int(local.set.t) else local.set).duplicate(true)
	return {"set": s, "prog": p}
