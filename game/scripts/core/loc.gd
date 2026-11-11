extends RefCounted
## 本地化（docs/276 §10）：TranslationServer + game/l10n/<模块>.csv（Godot CSV 翻译表，列 keys,en,_zh,_source,_note；_ 开头的列导入时跳过）。
## 中文是源语言：中文模式下一律原样返回，不查表；英文模式下查不到也原样返回中文——不会出现空串或裸 key。
## 两种查法：
##   1. 路径键（op.mizuki.skills.1.desc、lore.bone.lore、enemy.izumik.intro.line）：tree() 在读 JSON 时按路径换长文本（说明 / 简介 / 档案），
##      换在填数之前，{$键} 占位照常由 operator_defs.fill_line 填。名字、伤害来源名、标签不在读时换——代码里拿它们当 ID 比（fx_pxplane 按技能名分派、
##      melee_impact.HEAVY、run_stats 伤害来源），换了逻辑会断。
##   2. 原文键（键 = 中文原文本身）：s() 在 ui.gd 的绘制 / 量宽助手里查，名字、标签、Boss 招式名、横幅都走这里；已填过数的句子
##      （终结技说明、「-12 震撼」这类飘字）按模板（{$…} / %d / %s 换成数字）匹配后把数字填进英文模板。
## 短版：short() 先查 short:<原文>（定宽格子用，docs/276 §9 第 4 条），没有就同 s()。

## 已接入的模块（game/l10n/<名>.csv）。新模块：加 CSV + .import（compress=0，要能列出全部键给模板用），名字加到这里
const MODULES := ["ops", "enemies", "ui", "relics", "events", "meta", "run", "extra"]
## 「跟随系统」解析成英文的开关：英文翻译未覆盖全部模块前保持 false——系统语言是英文的玩家先看到完整中文，
## 不会看到中英夹杂的半成品；在设置里手动选 English 不受影响。全部模块翻完、第三步验收后改 true（docs/276 §10）
const AUTO_EN_READY := true   # 11-12 用户已授权合入（不过目，标 AI 翻译）：非中文系统的「自动」选英文

static var lang := "zh"          # 当前生效语言："zh" / "en"
static var _ready_tr := false
static var _cache := {}          # 原文 → 译文（含查不到的，存原文）；超过 4096 条整表清空
static var _tpl := {}            # 首个中文二字组 → [[RegEx, 英文模板, 占位记号表], …]
static var _cjk: RegEx
static var _ph: RegEx
static var _re_fwp: RegEx   # 全角标点（英文模式下没有汉字的串也换成英文标点）


static func en() -> bool:
	return lang == "en"


## 设置里的选项（"auto" / "zh" / "en"）→ 生效语言。B站 Toy 版固定中文（toy = true）
static func resolve(pref: String, toy := false) -> String:
	if toy:
		return "zh"
	if pref == "zh" or pref == "en":
		return pref
	if AUTO_EN_READY and not OS.get_locale_language().begins_with("zh") and not _test_run():
		return "en"
	return "zh"


## 测试 / 无头 / 带启动参数的 debug 运行：「自动」一律中文（断言中文文案的测试不随云端机器的系统语言变）；
## 英文测试显式传 --lang=en（settings.gd 读命令行，优先于这里）。只靠系统语言判断的逻辑留给正式运行
static func _test_run() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	if not OS.is_debug_build():
		return false
	if not (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).is_empty():
		return true
	for a in OS.get_cmdline_args():
		if a.begins_with("res://tests/") or a.contains("/tests/"):
			return true
	return false


## 启动 / 设置改语言时调用。英文翻译表只在第一次切到英文时读
static func setup(new_lang: String) -> void:
	lang = new_lang if new_lang == "en" else "zh"
	_cache.clear()
	if lang == "en" and not _ready_tr:
		_load()
	TranslationServer.set_locale("en" if lang == "en" else "zh_CN")


static func _load() -> void:
	_ready_tr = true
	_cjk = RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]")
	_ph = RegEx.create_from_string("\\{\\$[^}]*\\}|%[-+0-9.]*[dsf]|%%")
	_re_fwp = RegEx.create_from_string("[。、；（），：！？]")
	for m in MODULES:
		var p := "res://l10n/%s.en.translation" % m
		if not ResourceLoader.exists(p):
			push_warning("翻译表缺失：" + p)
			continue
		var t: Translation = load(p)
		if t == null:
			continue
		TranslationServer.add_translation(t)
		for k in t.get_message_list():
			var ks := str(k)
			if _ph.search(ks) != null and _cjk.search(ks) != null:
				_add_tpl(ks, str(t.get_message(k)))


## 模板：把原文里的占位换成捕获组，按第一个中文二字组分桶（查找时只试同桶的模板）
static func _add_tpl(zh: String, en_s: String) -> void:
	var pat := "^"
	var toks: Array = []
	var i := 0
	var first_bigram := ""
	for m in _ph.search_all(zh):
		var lit := zh.substr(i, m.get_start() - i)
		if first_bigram == "":
			first_bigram = _bigram(lit)
		pat += _esc(lit)
		var tk := m.get_string()
		if tk == "%%":
			pat += "%"
		elif tk.ends_with("s") and tk.begins_with("%"):
			pat += "(.+?)"
			toks.append(tk)
		else:
			pat += "([-+]?[0-9]+(?:\\.[0-9]+)?)"
			toks.append(tk)
		i = m.get_end()
	var tail := zh.substr(i)
	if first_bigram == "":
		first_bigram = _bigram(tail)
	pat += _esc(tail) + "$"
	if first_bigram == "":
		return
	var re := RegEx.create_from_string(pat)
	if re == null or not re.is_valid():
		return
	if not _tpl.has(first_bigram):
		_tpl[first_bigram] = []
	_tpl[first_bigram].append([re, en_s, toks])


static func _bigram(s: String) -> String:
	var m := _cjk.search(s)
	if m == null:
		return ""
	var a := m.get_start()
	return s.substr(a, 2) if a + 1 < s.length() and _cjk.search(s.substr(a + 1, 1)) != null else s.substr(a, 1)


static func _esc(s: String) -> String:
	var out := ""
	for ch in s:
		if ch in "\\^$.|?*+()[]{}":
			out += "\\" + ch
		else:
			out += ch
	return out


## 路径键：查到返回英文，查不到返回 fallback（中文模式直接返回 fallback）
static func k(key: String, fallback: String) -> String:
	if lang != "en":
		return fallback
	var t := TranslationServer.translate(key)
	return fallback if t == key or t == "" else String(t)


## 原文键：显示用。中文模式 / 不含中文 / 查不到都原样返回
static func s(text: String) -> String:
	if lang != "en" or text == "":
		return text
	var hit = _cache.get(text)
	if hit != null:
		return hit
	var out := text
	if _cjk != null and _cjk.search(text) != null:
		var t := String(TranslationServer.translate(text))
		if t != text and t != "":
			out = t
		else:
			out = _match_tpl(text)
			if out == text:
				out = _split_fallback(text)
	elif _re_fwp != null and _re_fwp.search(text) != null:   # 没有汉字但带全角标点（「PRTS Wiki；ArknightsGameData（Kengxxiao）。」）：换成英文标点
		out = _ascii_punct(text)
	if _cache.size() >= 4096:
		_cache.clear()
	_cache[text] = out
	if record_missing and out == text and _cjk != null and _cjk.search(text) != null:
		missing[text] = true
	return out


## 截图 / 冒烟时打开：英文模式下查完仍是中文的原文记下来（tests/l10n_shots 跑完写 missing.txt，送去补翻）
static var record_missing := false
static var missing := {}


## 全角标点 → 英文标点（只用在没有汉字的串上；括号前补空格）
static func _ascii_punct(t: String) -> String:
	for pr in [["（", " ("], ["）", ")"], ["；", "; "], ["，", ", "], ["：", ": "], ["！", "!"], ["？", "?"], ["、", ", "], ["。", "."]]:
		t = t.replace(pr[0], pr[1])
	return t.replace("  (", " (").replace(" .", ".").replace(" ,", ",")


## 整串、模板都查不到时：代码拼出来的文字按常见拼法拆开逐段查（docs/276 §12）。
## 多行 → 逐行；「A · B」「A·B」「A / B」→ 逐段；「标签：内容」→「Label: 内容」；末尾计数（「扩散 1/2」「×3」「+25%」「Lv.2」）→ 只查前面。
## 一段都没变就原样返回（不产出半中半英的拆法以外的东西）
static var _re_suffix: RegEx
static var _re_br: RegEx
static func _split_fallback(text: String) -> String:
	var st := text.strip_edges()
	if st != text and st != "":   # 首尾带空白：按去空白的原文查，再把空白补回
		var se := s(st)
		if se != st:
			var a := text.find(st)
			return text.substr(0, a) + se + text.substr(a + st.length())
	else:   # 表里的键可能带首尾空格（代码字面量 "  精英一解锁"）：补两格前导空格再查一次
		var t2 := String(TranslationServer.translate("  " + text))
		if t2 != "  " + text and t2 != "":
			return t2.strip_edges()
	if text.contains("\n"):
		# 排版折行折在名字中间（「S1「指令\n结构加固」」）：先去掉换行整串查，查到了就交给英文自己折行
		if not text.contains("\n\n") and text.count("\n") <= 2:
			for jc in ["", "：", "·"]:   # 折在冒号 / 中点处的（「指令：结构加固」排成两行、冒号被吃掉）把它补回来
				var jn0 := text.replace("\n", jc)
				var rm0 := record_missing
				record_missing = false   # 试拼出来的串查不到不算缺译（不然 missing 里全是两行粘在一起的假条目）
				var je0 := s(jn0)
				record_missing = rm0
				if je0 != jn0 and _cjk.search(je0) == null:
					return je0
		var lines := text.split("\n")
		for li in lines.size():
			lines[li] = s(lines[li])
		return "\n".join(lines)
	# 「触发：<整句线索>」：冒号前后各自整串查得到就先这么拆（不然下面的括号 / 逗号规则会把整句线索拆碎）
	var c0 := text.find("：")
	if c0 > 0 and c0 < 12 and c0 < text.length() - 1:
		var h0 := text.substr(0, c0)
		var t0 := text.substr(c0 + 1)
		var he0 := s(h0)
		var te0 := s(t0)
		if he0 != h0 and te0 != t0 and _cjk.search(te0) == null:
			return he0 + ": " + te0
	# 卡名显示时把「协同·专」排成「协同 · 专」、日文中点（U+30FB）：换回表里的写法再查一次
	for pair in [[" · ", "·"], [" " + String.chr(0x30fb) + " ", "·"], [String.chr(0x30fb), "·"]]:   # 中点用 chr 构造：字面量会被 release_slim 当成要显示的字（字体里没有）
		if text.contains(pair[0]):
			var nt := text.replace(pair[0], pair[1])
			var ne := s(nt)
			if ne != nt:
				return ne
	# 「S1「秘杖·速充模式」」：括号里的名字单独查，括号换成英文引号
	if text.contains("「") and text.contains("」"):
		if _re_br == null:
			_re_br = RegEx.create_from_string("「([^」]+)」")
		var bout := ""
		var at := 0
		var hit := false
		for bm in _re_br.search_all(text):
			var inner := bm.get_string(1)
			var ie := s(inner)
			hit = hit or ie != inner
			var head := text.substr(at, bm.get_start() - at)
			bout += (s(head) if head.strip_edges() != "" else head) + (" " if head != "" and not head.ends_with(" ") else "") + "\"" + ie + "\""
			at = bm.get_end()
		if hit:
			return (bout + s(text.substr(at))).strip_edges()
	# 末尾计数 / 括号先剥（「协同·专  1/4」「唤醒（所需技力 7 · 0%）」「探索用时 12:22」）
	if _re_suffix == null:
		_re_suffix = RegEx.create_from_string("^(.*?\\S)(\\s*(?:[0-9]+\\s*/\\s*[0-9]+|[0-9]+:[0-9]+(?::[0-9]+)?|Lv\\.?\\s*[0-9]+|[×x]\\s*[0-9.]+|[+\\-−]?[0-9]+(?:\\.[0-9]+)?%?|（[^）]*）|\\([^)]*\\)))$")
	var m := _re_suffix.search(text)
	if m != null:
		var base := m.get_string(1)
		var be := s(base)
		if be != base:
			var suf := m.get_string(2)
			if suf.begins_with("（"):
				suf = " (" + s(suf.substr(1, suf.length() - 2)) + ")"
			return be + suf
	for sep in ["  //  ", " // ", "//", " · ", "·", " / ", "／", "  ", "　", "，"]:
		if text.contains(sep):
			var parts := text.split(sep)
			for pi2 in parts.size():
				parts[pi2] = s(parts[pi2])
			var jn: String = {"·": " · ", "　": "  ", "，": ", "}.get(sep, sep)
			return jn.join(parts)
	var ci := text.find("：")
	if ci > 0 and ci < text.length() - 1:
		return s(text.substr(0, ci)) + ": " + s(text.substr(ci + 1))
	# 最后一招：单个空格隔开的几个中文词（「难度 常规」「深蓝之下 未获得」）逐词查；每段都得含中文才拆
	if text.contains(" "):
		var ws := text.split(" ", false)
		var all_cjk := ws.size() >= 2 and ws.size() <= 6
		for w in ws:
			if _cjk.search(w) == null:
				all_cjk = false
		if all_cjk:
			var changed := false
			for wi in ws.size():
				var we := s(ws[wi])
				changed = changed or we != ws[wi]
				ws[wi] = we
			if changed:
				return " ".join(ws)
	return text


## 定宽格子用的短版（short:<原文>），没有短版就同 s()
static func short(text: String) -> String:
	if lang != "en" or text == "":
		return text
	var t := String(TranslationServer.translate("short:" + text))
	return t if t != "short:" + text and t != "" else s(text)


static func _match_tpl(text: String) -> String:
	var seen := {}
	var n := text.length()
	for a in n:
		var bg := text.substr(a, 2)
		for key in [bg, text.substr(a, 1)]:
			if seen.has(key) or not _tpl.has(key):
				continue
			seen[key] = true
			for tp in _tpl[key]:
				var m: RegExMatch = tp[0].search(text)
				if m == null:
					continue
				return _fill(tp[1], tp[2], m)
	return text


## 把捕获到的数字按占位记号填进英文模板：{$…} 按记号文字对应，%d / %s 按出现顺序；%s 捕到的中文再查一次
static func _fill(en_s: String, toks: Array, m: RegExMatch) -> String:
	var vals := {}
	var pos: Array = []
	for ti in toks.size():
		var v := m.get_string(ti + 1)
		if str(toks[ti]).begins_with("%"):
			pos.append(s(v) if str(toks[ti]).ends_with("s") else v)
		else:
			vals[toks[ti]] = v
	var out := ""
	var at := 0
	var pn := 0
	for mm in _ph.search_all(en_s):
		out += en_s.substr(at, mm.get_start() - at)
		var tk := mm.get_string()
		if tk == "%%":
			out += "%"
		elif tk.begins_with("%"):
			out += str(pos[pn]) if pn < pos.size() else tk
			pn += 1
		else:
			out += str(vals.get(tk, tk))
		at = mm.get_end()
	return out + en_s.substr(at)


## 读 JSON 时按路径换长文本（只换这些字段；名字、标签、伤害来源名留中文，显示时再 s()）
## hint（指挥响应短名，responses.gd 校验 ≤ 6 字）与 text（飘字 {s, col}）是短名 / 结构，不在读时换，显示时 s() 查
const LONG := {"desc": true, "brief": true, "branch_desc": true, "intro": true, "lore": true, "trigger": true,
	"banner": true, "line": true}


static func tree(node, prefix: String) -> void:
	if lang != "en":
		return
	_tree(node, prefix, "")


static func _tree(node, path: String, field: String) -> void:
	if node is Dictionary:
		for kk in node.keys():
			var ks := str(kk)
			if ks.begins_with("_"):
				continue
			var v = node[kk]
			if v is String:
				if LONG.has(ks) and v != "":
					node[kk] = k(path + "." + ks, v)
			elif v is Dictionary or v is Array:
				_tree(v, path + "." + ks, ks)
	elif node is Array:
		for i in node.size():
			var v = node[i]
			if v is String:
				if LONG.has(field) and v != "":
					node[i] = k(path + "." + str(i), v)
			elif v is Dictionary or v is Array:
				_tree(v, path + "." + str(i), field)
