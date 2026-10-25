extends RefCounted
## 干员定义的读取与文字占位（docs/126 C3，10-22 由 characters/character.gd 原样搬出；Character 留同名转发）：
## 名单、data/characters/<id>.json（+ 测试专用干员）、--bal=opbase 覆盖、desc / banner 的「{表达式}」填数、技能帧条段的帧条名。
## 全是静态函数，不碰局内状态


## 目录内容运行中不变：第一次扫完记住（10-25 帧率：界面每帧经 op_idle 调到，每次都是一次目录扫描）。返回副本，调用方改了不影响缓存
static var _ids: Array = []

static func list_ids() -> Array:
	if _ids.is_empty():
		var d := DirAccess.open("res://data/characters")
		if d != null:
			for f in d.get_files():
				if f.ends_with(".json"):
					_ids.append(f.get_basename())
	return _ids.duplicate()


static func load_def(cid: String) -> Dictionary:
	var f := FileAccess.open(def_path(cid), FileAccess.READ)
	if f == null:
		push_error("character def missing: " + cid)
		return {"id": cid}
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return {"id": cid}
	# 测试旋钮（docs/88）：--bal=opbase/<id>/<base 键>=值 覆盖干员 JSON 的 base 段（含数据干员 "$键" 引用）；
	# 只在命令行带 --bal 时才有这一段（Bal 只在 debug 构建读命令行），正式游玩与发布版不受影响
	var ob: Dictionary = preload("res://scripts/core/balance.gd").sec("opbase/" + cid)
	if not ob.is_empty() and d.get("base") is Dictionary:
		for k in ob:
			d.base[k] = ob[k]
	fill_text(d, d.get("base", {}) if d.get("base") is Dictionary else {})
	return d


## 玩家可见文字里的数值占位（docs/61 §1.4）：desc / banner 里的「{表达式}」按 base 求值后填进去。
## 表达式至少引用一个 $键，支持数字、+ - * / 与括号，例如 {$s1_mult}、{$e1_per*100}%、{$n2_mult*100-100}%、{(1-$slow)*100}%；末尾 :N 指定小数位（{$a*$b:0}）；
## 结果按 text_fmt 去掉多余的小数（最多 3 位）。填在 load_def 里：选人 / 图鉴 / 升级卡 / 精英化演出 / 属性面板读到的都是填好的文字，
## 改 base 数值（含 --bal=opbase）文字自动跟着变。求不出值的占位原样留下并报错（tools/op_text_check.py 同规则静态检查）
const TEXT_FILL_KEYS := ["desc", "banner", "branch_desc"]


static func fill_text(n, base: Dictionary) -> void:
	if n is Dictionary:
		for k in n:
			if k == "base" or k == "_doc":
				continue
			var v = n[k]
			if v is String and k in TEXT_FILL_KEYS and v.contains("{"):
				n[k] = fill_line(v, base)
			elif v is Dictionary or v is Array:
				fill_text(v, base)
	elif n is Array:
		for v in n:
			if v is Dictionary or v is Array:
				fill_text(v, base)


## 一行文字里的全部 {…$键…} 占位换成数值
static func fill_line(s: String, base: Dictionary) -> String:
	var out := ""
	var i := 0
	while i < s.length():
		var a := s.find("{", i)
		if a < 0:
			break
		var b := s.find("}", a + 1)
		if b < 0:
			break
		var expr := s.substr(a + 1, b - a - 1)
		out += s.substr(i, a - i)
		if expr.contains("$"):
			var nd := 3
			var ci := expr.rfind(":")
			if ci > 0 and expr.substr(ci + 1).is_valid_int():   # {表达式:N}：四舍五入到 N 位小数（150.15 → {…:0} → 150）
				nd = clampi(expr.substr(ci + 1).to_int(), 0, 3)
				expr = expr.substr(0, ci)
			var r := text_eval(expr, base)
			if r[0]:
				out += text_fmt(r[1], nd)
			else:
				push_error("干员文字占位「{%s}」求值失败：%s" % [expr, r[2]])
				out += s.substr(a, b - a + 1)
		else:
			out += "{" + expr + "}"
		i = b + 1
	return out + s.substr(i)


## 去掉多余的小数：最多保留 nd 位（缺省 3：0.15 → 0.15，1.50 → 1.5，15.0 → 15，1.275 → 1.275）
static func text_fmt(v: float, nd := 3) -> String:
	var k := pow(10.0, nd)
	var r := floorf(v * k + 0.5) / k   # 与 tools/op_text_check.py 同算法（.5 进位）
	if absf(r - roundf(r)) < 0.0001:
		return str(int(roundf(r)))
	var t := ("%." + str(nd) + "f") % r
	while t.ends_with("0"):
		t = t.left(-1)
	return t


## 文字占位的表达式求值：[ok, 值, 错误说明]；递归下降（加减 < 乘除 < 负号 / 括号）
static func text_eval(expr: String, base: Dictionary) -> Array:
	var toks: Array = []
	var s := expr.replace(" ", "")
	var i := 0
	while i < s.length():
		var c := s[i]
		if c in "+-*/()":
			toks.append(c)
			i += 1
		elif c == "$" or c.is_valid_int() or c == ".":
			var j := i + 1
			while j < s.length() and not (s[j] in "+-*/()"):
				j += 1
			toks.append(s.substr(i, j - i))
			i = j
		else:
			return [false, 0.0, "看不懂的字符「%s」" % c]
	var st := {"t": toks, "i": 0, "err": ""}
	var v := _te_sum(st, base)
	if st.err == "" and int(st.i) != toks.size():
		st.err = "多余的「%s」" % str(toks[st.i])
	return [st.err == "", v, st.err]


static func _te_sum(st: Dictionary, base: Dictionary) -> float:
	var v := _te_prod(st, base)
	while st.err == "" and int(st.i) < st.t.size() and st.t[st.i] in ["+", "-"]:
		var op: String = st.t[st.i]
		st.i += 1
		var r := _te_prod(st, base)
		v = v + r if op == "+" else v - r
	return v


static func _te_prod(st: Dictionary, base: Dictionary) -> float:
	var v := _te_atom(st, base)
	while st.err == "" and int(st.i) < st.t.size() and st.t[st.i] in ["*", "/"]:
		var op: String = st.t[st.i]
		st.i += 1
		var r := _te_atom(st, base)
		if op == "*":
			v *= r
		elif r == 0.0:
			st.err = "除以 0"
		else:
			v /= r
	return v


static func _te_atom(st: Dictionary, base: Dictionary) -> float:
	if int(st.i) >= st.t.size():
		st.err = "表达式不完整"
		return 0.0
	var t: String = st.t[st.i]
	st.i += 1
	if t == "-":
		return -_te_atom(st, base)
	if t == "(":
		var v := _te_sum(st, base)
		if int(st.i) >= st.t.size() or st.t[st.i] != ")":
			st.err = "缺「)」"
			return 0.0
		st.i += 1
		return v
	if t.begins_with("$"):
		var k := t.substr(1)
		if not base.has(k) or not (base[k] is int or base[k] is float):
			st.err = "base 里没有数字「%s」" % k
			return 0.0
		return float(base[k])
	if t.is_valid_float():
		return t.to_float()
	st.err = "看不懂的「%s」" % t
	return 0.0


## 测试专用干员（docs/61 §测试）：不在 data/characters/ 里（不进名单 / 招募池 / 图鉴），只能用 --op=<id> 指名加载
const TEST_OPS_DIR := "res://tests/data_ops/"


## 干员定义文件：data/characters/<id>.json；没有时找测试专用干员
static func def_path(cid: String) -> String:
	var p := "res://data/characters/%s.json" % cid
	if not FileAccess.file_exists(p) and FileAccess.file_exists(TEST_OPS_DIR + cid + ".json"):
		return TEST_OPS_DIR + cid + ".json"
	return p


## 能按 id 加载（正式名单 + 测试专用干员）
static func exists(cid: String) -> bool:
	return cid != "" and FileAccess.file_exists(def_path(cid))


## 技能帧条「段」的帧条名（段可写成名字或 {anim, frames, reverse}）
static func seq_anim(seg) -> String:
	if seg is Dictionary:
		return str(seg.get("anim", ""))
	return str(seg) if seg != null else ""
