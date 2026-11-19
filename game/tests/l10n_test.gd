extends Node
## 本地化快检（docs/276 §10）：
##   ① 英文模式：原文键 / 路径键 / 模板（填过数的句子）/ 短版查得到；查不到原样返回中文，不出空串、不出裸 key；
##   ② 20 名干员 load_def 后：说明类长文本换成英文且没有残留 {$…} 占位；名字（ID）仍是中文，显示时 Loc.s 能译；
##   ③ 切回中文：load_def 与 Loc.s 都是原文，和不接本地化时一字不差。
## 全部通过打印 "L10N TEST failures=0"
const Loc = preload("res://scripts/core/loc.gd")
const Character = preload("res://scripts/characters/character.gd")
const UI_S = preload("res://scripts/ui.gd")

var n := 0
var fails := 0


## 日服官方技能名与中文同形（查表结果本来就等于原文），不算「没译」：黍 S1（ja_JP skill_table skchr_shu_1「化被草木」）
const JA_SAME_AS_ZH := ["化被草木"]

func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: L10N " + what)


func _ready() -> void:
	call_deferred("run")


func _has_cjk(t: String) -> bool:
	for ch in t:
		var c := ch.unicode_at(0)
		if c >= 0x4e00 and c <= 0x9fff:
			return true
	return false


func _has_hangul(t: String) -> bool:
	for ch in t:
		var c := ch.unicode_at(0)
		if c >= 0xac00 and c <= 0xd7a3:
			return true
	return false


func _has_kana(t: String) -> bool:
	for ch in t:
		var c := ch.unicode_at(0)
		if c >= 0x3041 and c <= 0x30ff:
			return true
	return false


func _texts(node, field: String, out: Array) -> void:
	if node is Dictionary:
		for k in node:
			if str(k).begins_with("_"):
				continue
			var v = node[k]
			if v is String:
				if Loc.LONG.has(str(k)):
					out.append([str(k), v])
			else:
				_texts(v, str(k), out)
	elif node is Array:
		for v in node:
			if v is String:
				if Loc.LONG.has(field):
					out.append([field, v])
			else:
				_texts(v, field, out)


func run() -> void:
	var zh_defs := {}
	Loc.setup("zh")
	for cid in Character.list_ids():
		zh_defs[cid] = Character.load_def(cid)
	ok(Loc.s("骨海漂流体") == "骨海漂流体", "中文模式原样返回")

	# 语言锁（B站 Toy 版固定中文，docs/276 §12）：锁住时任何选项都解析成中文；不锁时手动选英文生效
	ok(Loc.resolve("en", true) == "zh" and Loc.resolve("auto", true) == "zh", "语言锁：Toy 版切不到英文")
	ok(Loc.resolve("en", false) == "en" and Loc.resolve("zh", false) == "zh", "不锁时手动选择生效")
	ok(Cfg.lang_locked() == false, "源码运行（build.json 无 lang_lock、不在 Toy 容器）不锁语言")

	Loc.setup("en")
	ok(Loc.s("骨海漂流体") == "Bone Sea Drifter","原文键：敌人名 → %s" % Loc.s("骨海漂流体"))
	ok(Loc.s("跃浪击") == "Wave Strike", "原文键：官方技能名 → %s" % Loc.s("跃浪击"))
	ok(Loc.k("enemy.bone.name", "骨海漂流体") == "Bone Sea Drifter", "路径键")
	ok(Loc.s("二重咏唱 ×3") == "Duetto ×3", "模板 %%d：%s" % Loc.s("二重咏唱 ×3"))
	ok(Loc.short("碎漩狂舞") == "Maelstrom", "短版 → %s" % Loc.short("碎漩狂舞"))
	ok(Loc.short("骨海漂流体") == "Bone Sea Drifter", "没有短版时同 s()")
	ok(Loc.s("这一句表里没有") == "这一句表里没有", "查不到原样返回中文")
	ok(Loc.k("no.such.key", "中文") == "中文", "路径键查不到返回 fallback")
	ok(Loc.s("") == "", "空串")
	ok(Loc.s("HP 120") == "HP 120", "不含中文原样返回")

	var left := 0
	var cjk_left := 0
	var total := 0
	for cid in Character.list_ids():
		var d: Dictionary = Character.load_def(cid)
		var ts: Array = []
		_texts(d, "", ts)
		for t in ts:
			total += 1
			if str(t[1]).contains("{$"):
				left += 1
				printerr("  未填占位 %s.%s：%s" % [cid, t[0], str(t[1]).left(60)])
			if _has_cjk(str(t[1])):
				cjk_left += 1
		var sk: Array = d.get("skills", [])
		if sk.size() > 0:
			var nm: String = str(sk[0].get("name", ""))
			ok(_has_cjk(nm) or nm == "", "%s：技能名是中文 ID（不在读时翻）" % cid)
			ok(not _has_cjk(Loc.s(nm)), "%s：技能名显示时译成英文（%s → %s）" % [cid, nm, Loc.s(nm)])
		ok(zh_defs.has(cid) and str(zh_defs[cid].get("name")) == str(d.get("name")), "%s：干员名 ID 不变" % cid)
	ok(left == 0, "英文说明里残留 {$…} 占位 %d 条" % left)
	print("L10N 干员长文本 %d 条，仍是中文 %d 条（未翻的模块回退中文属正常）" % [total, cjk_left])
	ok(cjk_left * 10 < total, "干员长文本英文覆盖率 ≥ 90%%（仍中文 %d / %d）" % [cjk_left, total])

	# 日文（docs/276 §13）：官方名按日服、缺条退英文、说明换日文无残留占位、Toy 锁中文
	ok(Loc.resolve("ja", true) == "zh", "语言锁：Toy 版切不到日文")
	ok(Loc.resolve("ja", false) == "ja", "不锁时手动选日文生效")
	Loc.setup("ja")
	ok(Loc.ja() and Loc.on() and not Loc.en(), "日文模式标志")
	ok(Loc.s("骨海漂流体") == "骨海のワンダラー", "日文原文键：敌人名 → %s" % Loc.s("骨海漂流体"))
	ok(Loc.s("水月") == "ミヅキ", "日文原文键：干员名 → %s" % Loc.s("水月"))
	ok(Loc.k("enemy.bone.name", "骨海漂流体") == "骨海のワンダラー", "日文路径键")
	var duo := Loc.s("二重咏唱 ×3")
	ok(duo != "二重咏唱 ×3" and duo.contains("3"), "日文模板 %%d：%s" % duo)
	ok(Loc.s("这一句表里没有") == "这一句表里没有", "日文查不到原样返回中文")
	ok(Loc.s("中文") == "中文" and Loc.s("日本語") == "日本語", "语言选项名不翻")
	var jleft := 0
	var jkana := 0
	var jtotal := 0
	for cid in Character.list_ids():
		var dj: Dictionary = Character.load_def(cid)
		var tj: Array = []
		_texts(dj, "", tj)
		for t in tj:
			jtotal += 1
			if str(t[1]).contains("{$"):
				jleft += 1
				printerr("  日文未填占位 %s.%s：%s" % [cid, t[0], str(t[1]).left(60)])
			if _has_kana(str(t[1])):
				jkana += 1
		var skj: Array = dj.get("skills", [])
		if skj.size() > 0:
			var nmj: String = str(skj[0].get("name", ""))
			ok(Loc.s(nmj) != nmj or JA_SAME_AS_ZH.has(nmj), "%s：技能名显示时译成日文（%s → %s）" % [cid, nmj, Loc.s(nmj)])
	ok(jleft == 0, "日文说明里残留 {$…} 占位 %d 条" % jleft)
	print("L10N 日文 干员长文本 %d 条，含假名 %d 条" % [jtotal, jkana])
	ok(jkana * 10 >= jtotal * 9, "干员长文本日文覆盖率 ≥ 90%%（含假名 %d / %d）" % [jkana, jtotal])

	# 韩文（docs/276 §14）：官方名按韩服、缺条退英文、说明换韩文无残留占位、Toy 锁中文、按词断行
	ok(Loc.resolve("ko", true) == "zh", "语言锁：Toy 版切不到韩文")
	ok(Loc.resolve("ko", false) == "ko", "不锁时手动选韩文生效")
	Loc.setup("ko")
	ok(Loc.ko() and Loc.on() and not Loc.en() and not Loc.ja(), "韩文模式标志")
	ok(Loc.s("骨海漂流体") == "앙상한 표류체", "韩文原文键：敌人名 → %s" % Loc.s("骨海漂流体"))
	ok(Loc.s("水月") == "미즈키", "韩文原文键：干员名 → %s" % Loc.s("水月"))
	ok(Loc.k("enemy.bone.name", "骨海漂流体") == "앙상한 표류체", "韩文路径键")
	var kduo := Loc.s("二重咏唱 ×3")
	ok(kduo != "二重咏唱 ×3" and kduo.contains("3") and not _has_cjk(kduo), "韩文模板 %%d：%s" % kduo)
	ok(Loc.s("这一句表里没有") == "这一句表里没有", "韩文查不到原样返回中文")
	ok(Loc.s("한국어") == "한국어" and Loc.s("AI 번역") == "AI 번역", "语言选项名不翻")
	var kleft := 0
	var khan := 0
	var ktotal := 0
	for cid in Character.list_ids():
		var dk: Dictionary = Character.load_def(cid)
		var tk: Array = []
		_texts(dk, "", tk)
		for t in tk:
			ktotal += 1
			if str(t[1]).contains("{$"):
				kleft += 1
				printerr("  韩文未填占位 %s.%s：%s" % [cid, t[0], str(t[1]).left(60)])
			if _has_hangul(str(t[1])):
				khan += 1
		var skk: Array = dk.get("skills", [])
		if skk.size() > 0:
			var nmk: String = str(skk[0].get("name", ""))
			ok(Loc.s(nmk) != nmk and not _has_cjk(Loc.s(nmk)), "%s：技能名显示时译成韩文（%s → %s）" % [cid, nmk, Loc.s(nmk)])
	ok(kleft == 0, "韩文说明里残留 {$…} 占位 %d 条" % kleft)
	print("L10N 韩文 干员长文本 %d 条，含韩文 %d 条" % [ktotal, khan])
	ok(khan * 10 >= ktotal * 9, "干员长文本韩文覆盖率 ≥ 90%%（含韩文 %d / %d）" % [khan, ktotal])
	# 按词断行：窄宽度折行后，每行首尾都落在空格处（原文按空格切出的词一个都不被拆开）
	var kf: Font = load("res://fonts/ui.ttf")
	var ks := Loc.s("水月") + " 공격력이 증가하고 적에게 지속적으로 피해를 입힌다"
	var kl: PackedStringArray = UI_S.wrap_lines(kf, ks, 16, 120.0)
	var words := ks.split(" ", false)
	var rebuilt: Array = []
	for ln in kl:
		for w in ln.split(" ", false):
			rebuilt.append(w)
	ok(kl.size() >= 2 and rebuilt == Array(words), "韩文按词断行（%s）" % " | ".join(kl))

	Loc.setup("zh")
	for cid in Character.list_ids():
		ok(JSON.stringify(Character.load_def(cid)) == JSON.stringify(zh_defs[cid]), "%s：切回中文后与原文一字不差" % cid)
	print("%d checks, %d failed" % [n, fails])
	print("L10N TEST failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
