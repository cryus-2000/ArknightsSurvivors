extends Node
## B站 Toy 云存档单元测试（docs/89，check.py 场景回归 cloud_save）：
## 1. core/cloud_pack.gd：打包 / 分片 / 平台限制（key 字符集与长度、value ≤ 1024 字节、key 总数）/ 非 ASCII 转义 / 校验（缺片、篡改、
##    长度、头坏、正文结构坏）/ 版本更新时不读 / 空云端 / 超限拒绝打包；
## 2. 合并：进度并集、已解锁难度取较大值、布尔取或、设置取较新、一样新用本地、云端为空 = 本地；
## 3. settings.gd：cloud_body ↔ cloud_apply 往返、类型错误与越界的项被夹取或忽略、采用云端设置不算本机新修改；
## 4. 非网页平台 Cloud 自动加载什么都不做（OFF、不显示存档页、flush 无效）。
## 不写 settings.cfg（测试参数下 Cfg.save() 本来就不落盘）。
const Pack = preload("res://scripts/core/cloud_pack.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("CLOUD SAVE: " + what)
		print("FAIL ", what)


func _ready() -> void:
	call_deferred("run")


func body(set_t: int, diff: int, rel: Array, extra := {}) -> Dictionary:
	var d := {"master": 0.8, "music": 0.5, "dmg_numbers": true, "touch_layout": {}}
	d.merge(extra, true)
	return {"set": {"t": set_t, "d": d}, "prog": {"diff": diff, "gal": ["enemy:bone"], "rel": rel, "end": ["standard"], "shows": [], "intro": false, "open": true}}


func run() -> void:
	pack_tests()
	merge_tests()
	cfg_tests()
	compat_tests()
	await platform_tests()
	print("CLOUD SAVE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func pack_tests() -> void:
	# 小存档：1 片 + 头
	var b := body(100, 1, ["1", "2"])
	var pk := Pack.pack(b, 12345)
	check(pk.err == "" and pk.items.size() == 2, "小存档应为 1 片 + 头：%s" % [pk.items.keys()])
	check(Pack.items_ok(pk.items), "打包结果不符合平台限制")
	var un := Pack.unpack(pk.items)
	check(un.status == "ok" and Pack.canon(un.body) == Pack.canon(b) and un.t == 12345, "往返不一致：%s" % un)
	# 满图鉴量级：264 件藏品 + 120 条图鉴 → 多片，每片 ≤ 1024 字节，往返一致
	var rel := []
	for i in 264:
		rel.append(str(i + 1))
	var big := body(5, 2, rel)
	for i in 120:
		big.prog.gal.append("enemy:some_long_enemy_name_%d" % i)
	pk = Pack.pack(big, 1)
	var n := int(JSON.parse_string(pk.items[Pack.HEAD_KEY]).n)
	print("CLOUD SIZE big body=%d bytes chunks=%d keys=%d" % [int(JSON.parse_string(pk.items[Pack.HEAD_KEY]).len), n, pk.items.size()])
	# 当前版本全收集（全部藏品 + 全部敌人 / 物件 + 全结局 + 七个触屏键自定义）的实际大小
	var full := Cfg.cloud_body()
	var db = preload("res://scripts/core/relic_db.gd").new()
	db.load_files()
	full.prog.rel = db.implemented().map(func(r): return str(r.id))
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")).enemies
	full.prog.gal = en.keys().map(func(k): return "enemy:" + str(k)) + ["item:EXP", "item:OIL", "item:INGOT", "item:MAGNET", "item:HEAL", "item:CHEST", "item:PILLAR", "item:RUINED WALL", "item:WRECK", "item:RIDGE", "item:PEAK", "item:MIRE", "item:MERCHANT"]
	full.prog.end = preload("res://scripts/data.gd").ENDINGS.keys()
	for k in preload("res://scripts/touch_layout.gd").KEYS:
		full.set.d.touch_layout[k] = {"ax": 1, "ay": 1, "x": 1234.0, "y": 456.0, "s": 1.25}
	var fpk := Pack.pack(full, 1)
	print("CLOUD SIZE full body=%d bytes chunks=%d keys=%d (relics=%d gal=%d)" % [int(JSON.parse_string(fpk.items[Pack.HEAD_KEY]).len), fpk.items.size() - 1, fpk.items.size(), full.prog.rel.size(), full.prog.gal.size()])
	check(fpk.items.size() <= 8, "当前全收集存档应在 8 个 key 以内")
	check(n >= 3 and pk.items.size() == n + 1, "大存档应拆成多片：n=%d" % n)
	check(Pack.items_ok(pk.items), "大存档分片超出平台限制")
	for k in pk.items:
		check(str(pk.items[k]).to_utf8_buffer().size() <= Pack.VALUE_LIMIT, "%s 超过 1024 字节" % k)
	un = Pack.unpack(pk.items)
	check(un.status == "ok" and Pack.canon(un.body) == Pack.canon(big), "大存档往返不一致")
	# 非 ASCII：转成 \uXXXX，字节数 = 字符数；含超出基本平面的字
	var cn := body(1, 0, [], {"cover_character_id": "水月🌊"})
	pk = Pack.pack(cn, 1)
	for k in pk.items:
		var v := str(pk.items[k])
		check(v.to_utf8_buffer().size() == v.length(), "%s 含非 ASCII 字符" % k)
	un = Pack.unpack(pk.items)
	check(un.status == "ok" and str(un.body.set.d.cover_character_id) == "水月🌊", "非 ASCII 往返不一致：%s" % un.body)
	# 平台限制自检
	check(not Pack.items_ok({"__x": "1"}), "__ 开头的 key 应判为不合法")
	check(not Pack.items_ok({"a b": "1"}), "含空格的 key 应判为不合法")
	check(not Pack.items_ok({"k": "x".repeat(1025)}), "超 1024 字节的 value 应判为不合法")
	var many := {}
	for i in 129:
		many["k%d" % i] = "1"
	check(not Pack.items_ok(many), "129 个 key 应判为不合法")
	# 超限：正文超过 MAX_CHUNKS 片时拒绝打包
	var huge := body(1, 0, [])
	for i in 6000:
		huge.prog.gal.append("item:%08d" % i)
	pk = Pack.pack(huge, 1)
	check(pk.err == "too_big" and pk.items.is_empty(), "超限存档应拒绝打包")
	# 校验失败的几种情况：都返回 bad，不给正文
	var good: Dictionary = Pack.pack(big, 1).items
	var miss := good.duplicate()
	miss.erase(Pack.CHUNK_PREFIX + "1")
	check(Pack.unpack(miss).status == "bad", "缺片应判为 bad")
	var tamper := good.duplicate()
	tamper[Pack.CHUNK_PREFIX + "0"] = str(tamper[Pack.CHUNK_PREFIX + "0"]).replace("1", "2")
	check(Pack.unpack(tamper).status == "bad", "篡改应判为 bad")
	var badhead := good.duplicate()
	badhead[Pack.HEAD_KEY] = "{not json"
	check(Pack.unpack(badhead).status == "bad", "头坏应判为 bad")
	var badbody: Dictionary = Pack.pack({"set": 1, "prog": {}}, 1).items
	check(Pack.unpack(badbody).status == "bad", "正文结构坏应判为 bad")
	# 版本：更新版本写的存档不读（newer），旧版 v0 判 bad；空云端 = empty；别的 key 不影响
	var newer := good.duplicate()
	var h = JSON.parse_string(newer[Pack.HEAD_KEY])
	h.v = Pack.VERSION + 1
	h.minv = Pack.VERSION + 1
	newer[Pack.HEAD_KEY] = JSON.stringify(h)
	check(Pack.unpack(newer).status == "newer", "要求更高版本（minv）应判为 newer")
	h.v = 0
	newer[Pack.HEAD_KEY] = JSON.stringify(h)
	check(Pack.unpack(newer).status == "bad", "版本 0 应判为 bad")
	check(Pack.unpack({}).status == "empty" and Pack.unpack({"other_key": "x"}).status == "empty", "没有头应判为 empty")
	var withother := good.duplicate()
	withother["score_cache"] = "1"
	check(Pack.unpack(withother).status == "ok", "云端有别的 key 不应影响解包")


func merge_tests() -> void:
	var l := body(200, 1, ["1", "2", "3"])
	var c := body(100, 2, ["3", "4"], {"master": 0.3})
	c.prog.gal = ["enemy:runner"]
	c.prog.end = ["standard", "e2"]
	c.prog.intro = true
	c.prog.open = false
	var m := Pack.merge(l, c)
	check(m.prog.rel == ["1", "2", "3", "4"], "藏品应取并集：%s" % [m.prog.rel])
	var dk := Pack.diff_keys(l, m)
	check("prog.rel" in dk and "prog.diff" in dk and not ("set.d.master" in dk) and Pack.diff_keys(m, m).is_empty(), "diff_keys：%s" % [dk])
	check(m.prog.gal == ["enemy:bone", "enemy:runner"], "图鉴应取并集")
	check(m.prog.end == ["standard", "e2"], "结局应取并集")
	check(int(m.prog.diff) == 2, "已解锁难度应取较大值")
	check(m.prog.intro == true and m.prog.open == true, "看过指南 / 开场应取或")
	check(float(m.set.d.master) == 0.8 and int(m.set.t) == 200, "本地设置较新：应保留本地")
	c.set.t = 300
	m = Pack.merge(l, c)
	check(float(m.set.d.master) == 0.3 and int(m.set.t) == 300, "云端设置较新：应采用云端")
	c.set.t = 200
	m = Pack.merge(l, c)
	check(float(m.set.d.master) == 0.8, "一样新：应用本地")
	m = Pack.merge(l, {})
	check(Pack.canon(m) == Pack.canon(l), "云端为空：结果应等于本地")
	# 幂等：合并结果再和云端合并不再变化（上传后两边一致）
	var m2 := Pack.merge(m, m)
	check(Pack.canon(m2) == Pack.canon(m), "合并应幂等")
	# int / float 不影响比较（JSON 往返后数字都是 float）
	var lf: Dictionary = JSON.parse_string(JSON.stringify(l))
	check(Pack.canon(lf) == Pack.canon(l) and Pack.sig(lf) == Pack.sig(l), "JSON 往返后签名应不变")


func cfg_tests() -> void:
	var keep := Cfg.cloud_body()
	var keep_t := Cfg.cloud_set_t
	var b := Cfg.cloud_body()
	b.set.t = 777
	b.set.d.master = 0.4
	b.set.d.ui_size_pct = 113        # 夹到 5 的倍数
	b.set.d.cam_zoom_pct = 999       # 夹到上限
	b.set.d.play_speed = 3.0         # 不合法：忽略
	b.set.d.dmg_numbers = "yes"      # 类型不对：忽略
	b.set.d.cover_character_id = "no_such_op"   # 不存在：忽略
	b.set.d.touch_layout = {"dash": {"ax": 1, "ay": 1, "x": 120.0, "y": 200.0, "s": 9.0}, "bogus": 1}
	b.prog.diff = 99
	b.prog.rel = ["5", "6"]
	b.set.d.difficulty = 5
	var speed0 := Cfg.play_speed
	var dmg0 := Cfg.dmg_numbers
	var cover0 := Cfg.cover_character_id
	Cfg.cloud_apply(JSON.parse_string(JSON.stringify(b)))   # 模拟云端来的数据（数字都是 float）
	check(is_equal_approx(Cfg.master, 0.4), "音量应采用正文")
	check(Cfg.ui_size_pct == 110, "界面大小应夹到 5 的倍数：%d" % Cfg.ui_size_pct)
	check(Cfg.cam_zoom_pct == Cfg.ZOOM_PCT_MAX, "战斗画面缩放应夹到上限")
	check(Cfg.play_speed == speed0 and Cfg.dmg_numbers == dmg0 and Cfg.cover_character_id == cover0, "不合法的项应保持本地值")
	check(Cfg.touch_layout.size() == 1 and is_equal_approx(float(Cfg.touch_layout.dash.s), 1.5), "触屏布局应清洗：%s" % Cfg.touch_layout)
	var maxd: int = preload("res://scripts/data.gd").DIFFICULTY_TIERS.size() - 1
	check(int(Cfg.cloud_body().prog.diff) == maxd, "已解锁难度应夹到最高档")
	check(Cfg.difficulty <= maxd, "所选难度不超过已解锁")
	check(Cfg.cloud_body().prog.rel == ["5", "6"], "藏品列表应采用正文")
	check(Cfg.cloud_set_t == 777, "采用正文的设置时刻")
	check(Cfg._settings_sig() == Cfg._set_sig, "采用云端设置后签名同步，不算本机新修改")
	# 往返：cloud_body → cloud_apply → cloud_body 不变
	var cur := Cfg.cloud_body()
	Cfg.cloud_apply(JSON.parse_string(JSON.stringify(cur)))
	check(Pack.canon(Cfg.cloud_body()) == Pack.canon(cur), "cloud_body ↔ cloud_apply 往返应不变")
	# 本机改设置：签名变化（save() 据此更新 cloud_set_t）
	Cfg.master = 0.1
	check(Cfg._settings_sig() != Cfg._set_sig, "本机改了设置，签名应变化")
	Cfg.cloud_apply(keep)
	Cfg.cloud_set_t = keep_t


func platform_tests() -> void:
	await get_tree().process_frame
	check(not OS.has_feature("web"), "单元测试应在桌面无头跑")
	check(Cloud.st == Cloud.St.OFF and not Cloud.supported, "非网页平台 Cloud 应为 OFF")
	Cloud.flush("test")
	Cloud.local_saved()
	check(Cloud.requests == 0, "非网页平台不应发请求")
	check(Cloud.status_text() == "", "非网页平台没有状态行")
	# 只读保护的提示与入口（状态机本身在网页 mock 里验证）
	Cloud.st = Cloud.St.NEWER
	check(Cloud.status_text() == "云存档版本较新，请更新游戏", "版本较新的提示")
	check(not Cloud.can_push(), "版本较新时不许以本地覆盖云端")
	Cloud.st = Cloud.St.OFF


## 版本升级不丢档（用户 10-13，docs/89 §3.1）
func compat_tests() -> void:
	# 1. 旧格式云档（缺 shows / open / 部分设置项）+ 本地新版本多出的字段（新干员）：缺的按缺省补齐，新字段保留，其余照常合并
	var old := {"set": {"t": 50, "d": {"master": 0.2}}, "prog": {"diff": 1, "gal": ["enemy:runner"], "rel": ["9"], "end": ["standard"], "intro": true}}
	var oldp := Pack.pack(old, 1, 1, 1)
	var ou := Pack.unpack(oldp.items)
	check(ou.status == "ok" and ou.body.prog.shows == [] and ou.body.prog.open == false, "旧档缺的字段应按缺省补齐：%s" % ou.body)
	var local := body(100, 0, ["1"], {"new_op_setting": "texas_alt"})
	local.prog["ops_seen"] = ["texas"]
	var m := Pack.merge(local, ou.body)
	check(m.prog.rel == ["1", "9"] and m.prog.gal == ["enemy:bone", "enemy:runner"] and int(m.prog.diff) == 1, "旧档与新字段合并：进度并集")
	check(m.prog.get("ops_seen") == ["texas"] and m.set.d.get("new_op_setting") == "texas_alt", "本地新增的干员字段不应丢：%s" % m)
	check(float(m.set.d.master) == 0.8 and m.set.d.has("music"), "本地设置较新：保留本地，云端缺的设置项不清空")
	# Cfg：旧档缺字段时 cloud_apply 不清空本地
	var keep := Cfg.cloud_body()
	var keep_t := Cfg.cloud_set_t
	var keep_ex: Dictionary = Cfg.cloud_extra.duplicate(true)
	Cfg.gallery_seen = ["enemy:bone"]
	Cfg.seen_shows = ["x"]
	Cfg.cloud_apply({"set": {"t": 1, "d": {}}, "prog": {"diff": 0}})
	check(Cfg.gallery_seen == ["enemy:bone"] and Cfg.seen_shows == ["x"], "云档缺的列表不应清空本地")
	# 2. 新版本（v2，只加字段，minv 仍为 1）写的云档：本版能读；未知字段（顶层 / set / set.d / prog）合并、写回本地、再上传都不丢，头里版本不降
	var nb := body(300, 2, ["5"], {"new_setting": 5})
	nb["ops"] = {"texas": {"elite": 2}}
	nb.set["x"] = 1
	nb.prog["ops_seen"] = ["texas", "angelina"]
	var np := Pack.pack(nb, 9, 2, 1)
	var nu := Pack.unpack(np.items)
	check(nu.status == "ok" and int(nu.v) == 2 and int(nu.minv) == 1, "v2 / minv1 的云档本版应能读：%s" % nu.status)
	var cur := Cfg.cloud_body()
	var nm := Pack.merge(cur, nu.body)
	check(Pack.canon(nm.get("ops")) == Pack.canon({"texas": {"elite": 2}}) and int(nm.set.get("x", 0)) == 1 and int(nm.set.d.get("new_setting", 0)) == 5 and nm.prog.get("ops_seen") == ["texas", "angelina"], "合并时未知字段应透传：%s" % nm)
	Cfg.cloud_apply(nm)
	Cfg.cloud_v = maxi(Cfg.cloud_v, int(nu.v))
	Cfg.cloud_minv = maxi(Cfg.cloud_minv, int(nu.minv))
	var back := Cfg.cloud_body()
	check(Pack.canon(back.get("ops")) == Pack.canon({"texas": {"elite": 2}}) and int(back.set.d.get("new_setting", 0)) == 5 and back.prog.get("ops_seen") == ["texas", "angelina"] and int(back.set.get("x", 0)) == 1, "写回本地后再取正文，未知字段应还在")
	var rp := Pack.pack(back, 10, Cfg.cloud_v, Cfg.cloud_minv)
	var rh = JSON.parse_string(rp.items[Pack.HEAD_KEY])
	check(int(rh.v) == 2 and int(rh.minv) == 1, "旧代码回写时头里版本不降：%s" % rh)
	var ru := Pack.unpack(rp.items)
	check(Pack.canon(ru.body) == Pack.canon(Pack.normalize(back)), "回写后的云档往返一致")
	# 默认参数打包也不降：v / minv 至少是本版
	var dh = JSON.parse_string(Pack.pack(back, 1, 0, 0).items[Pack.HEAD_KEY])
	check(int(dh.v) == Pack.VERSION and int(dh.minv) == Pack.MIN_READ, "版本号不低于本版")
	Cfg.cloud_apply(keep)
	Cfg.cloud_extra = keep_ex
	Cfg.cloud_set_t = keep_t
	Cfg.cloud_v = 0
	Cfg.cloud_minv = 0
	# 3. 不兼容的新格式（minv 高于本版）：只读保护
	var hp := Pack.pack(nb, 9, 3, 3)
	var hu := Pack.unpack(hp.items)
	check(hu.status == "newer" and hu.body.is_empty(), "minv 高于本版应判为 newer、不给正文")
	# 4. 迁移：v → v+1 逐级按顺序执行；本版读旧档时生效
	var steps := {1: _m12, 2: _m23}
	var mig := Pack.migrate({"set": {}, "prog": {}}, 1, 3, steps)
	check(mig.get("m12") == true and mig.get("m23") == true, "迁移应逐级按顺序执行：%s" % mig)
	var v1items: Dictionary = Pack.pack(body(1, 0, []), 1, 1, 1).items
	var mu := Pack.unpack(v1items, 3, steps)
	check(mu.status == "ok" and mu.body.get("m23") == true, "读旧版本的档时应走迁移")
	check(Pack.migrate({"a": 1}, 1, 1, steps) == {"a": 1}, "同版本不迁移")


func _m12(b: Dictionary) -> Dictionary:
	var o: Dictionary = b.duplicate(true)
	o["m12"] = true
	return o


func _m23(b: Dictionary) -> Dictionary:
	var o: Dictionary = b.duplicate(true)
	o["m23"] = bool(o.get("m12", false))
	return o
