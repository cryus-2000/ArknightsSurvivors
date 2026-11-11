extends Node
## 本地化快检（docs/276 §10）：
##   ① 英文模式：原文键 / 路径键 / 模板（填过数的句子）/ 短版查得到；查不到原样返回中文，不出空串、不出裸 key；
##   ② 20 名干员 load_def 后：说明类长文本换成英文且没有残留 {$…} 占位；名字（ID）仍是中文，显示时 Loc.s 能译；
##   ③ 切回中文：load_def 与 Loc.s 都是原文，和不接本地化时一字不差。
## 全部通过打印 "L10N TEST failures=0"
const Loc = preload("res://scripts/core/loc.gd")
const Character = preload("res://scripts/characters/character.gd")

var n := 0
var fails := 0


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

	Loc.setup("zh")
	for cid in Character.list_ids():
		ok(JSON.stringify(Character.load_def(cid)) == JSON.stringify(zh_defs[cid]), "%s：切回中文后与原文一字不差" % cid)
	print("%d checks, %d failed" % [n, fails])
	print("L10N TEST failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
