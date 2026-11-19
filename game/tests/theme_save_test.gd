extends Node
## 存档按主题分开（docs/366，core/theme_save.gd，check.py 场景回归 theme_save）。只改内存里的 Cfg 和临时 ConfigFile，不调 save()，不碰 user://settings.cfg。
## 1. 典型旧存档（新玩家 / 通关结局一 / 四结局全通 / 深潮进度 + 首通赏金 + 蚀刻章）：读档后玩家可见的进度、解锁、名册、认知塑造、凭证与旧版读到的完全一样；
##    写出（主题段 + 旧位置）再读、再写再读，三次一致（迁移幂等），旧位置仍是同样的值（旧版本读得到）。
## 2. 降级再升级：旧版本只改旧位置（多一个结局、多一件藏品、难度升一档）→ 新版本读到并集，不丢。
## 3. 第二个主题：切过去从空开始；记进度后写出再读，两个主题各是各的，旧位置始终是水月。
## 4. 云存档：只有水月时正文没有 th（与旧版本逐字相同）；有第二主题时 th 带上、旧键仍是水月；头版本 2 / 最低读者 1，旧版本（reader 1）照常解包；
##    两台设备冲突：水月的旧键与 th 里的主题各自取并集 / 取大，Cfg 套用后两个主题都对。

const ThemeSave = preload("res://scripts/core/theme_save.gd")
const Pack = preload("res://scripts/core/cloud_pack.gd")

var failures := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("THEME SAVE: " + what)
		print("FAIL ", what)


## 一份旧格式存档（11-17 之前：没有 [theme_*] 段）
func legacy(p: Dictionary) -> ConfigFile:
	var c := ConfigFile.new()
	c.set_value("progress", "diff_ver", 4)
	c.set_value("progress", "difficulty", int(p.get("difficulty", 0)))
	c.set_value("progress", "diff_unlocked", int(p.get("unlocked", 0)))
	c.set_value("progress", "diff_best", p.get("dbest", {}))
	c.set_value("progress", "endings_cleared", p.get("end", []))
	c.set_value("progress", "gallery_seen", p.get("gal", []))
	c.set_value("progress", "seen_relics", p.get("rel", []))
	c.set_value("progress", "event_log", p.get("evl", {}))
	c.set_value("progress", "seen_shows", p.get("shows", []))
	c.set_value("roster", "unlocked", p.get("ops", []))
	c.set_value("roster", "tickets", p.get("tk", {}))
	c.set_value("roster", "tiers", p.get("tiers", []))
	c.set_value("roster", "v", 2)
	c.set_value("meta", "shape", p.get("shape", {}))
	c.set_value("meta", "earned", p.get("earned", {}))
	c.set_value("meta", "bounty", p.get("bounty", []))
	c.set_value("medals", "got", p.get("med", {}))
	c.set_value("medals", "best", p.get("medb", {}))
	return c


func reset_cfg() -> void:
	Cfg.theme_saves = {}
	Cfg.theme_cur = ThemeSave.LEGACY
	ThemeSave.restore(Cfg, {})
	for k in ["roster_unlocked", "seen_shows", "roster_tiers"]:
		Cfg.set(k, [])
	for k in ["roster_tickets", "meta_shape", "meta_earned"]:
		Cfg.set(k, {})


func read(c: ConfigFile) -> void:
	reset_cfg()
	Cfg._read_cfg(c)


## 玩家看得到的状态：主题进度 + 全局（名册、凭证、认知塑造、已看演出、难度选择）
func visible() -> Dictionary:
	var v := ThemeSave.snapshot(Cfg)
	v["roster_unlocked"] = Cfg.roster_unlocked.duplicate()
	v["roster_tickets"] = Cfg.roster_tickets.duplicate()
	v["roster_tiers"] = Cfg.roster_tiers.duplicate()
	v["meta_shape"] = Cfg.meta_shape.duplicate()
	v["meta_earned"] = Cfg.meta_earned.duplicate()
	v["seen_shows"] = Cfg.seen_shows.duplicate()
	v["difficulty"] = Cfg.difficulty
	v["budget"] = load("res://scripts/core/meta.gd").budget()
	return v


func canon(v) -> String:
	return Pack.canon(v)


## 读一份旧存档再写出（迁移后的第一次存档）
func migrate(c0: ConfigFile) -> ConfigFile:
	read(c0)
	return write(c0)


## 按 Cfg 当前状态写出一份（同 save() 的进度部分：旧位置 + 主题段），返回新的 ConfigFile；调用前 Cfg 必须是 c0 读进来的状态
func write(c0: ConfigFile) -> ConfigFile:
	var c := ConfigFile.new()
	c.parse(c0.encode_to_text())
	if Cfg.theme_cur == ThemeSave.LEGACY:
		ThemeSave.write_legacy(c, ThemeSave.snapshot(Cfg))
	Cfg._theme_write(c)
	return c


func samples() -> Dictionary:
	var dbest := {"0": {"wins": 2, "best_t": 760, "fast_t": 701}, "1": {"wins": 0, "best_t": 512, "fast_t": 0}}
	var evl := {"seen": {"madness": 2, "opening": 1}, "opt": {"madness:0": true}, "pick": {"madness:0": 1}}
	return {
		"新玩家": {},
		"通关结局一": {"unlocked": 1, "difficulty": 1, "end": ["standard"], "gal": ["enemy:bone", "enemy:path", "item:EXP"], "rel": ["r_lamp", "r_shell"],
			"dbest": {"0": {"wins": 1, "best_t": 731, "fast_t": 731}}, "ops": ["mizuki", "suzuran"], "tk": {"hunt": 3}, "earned": {"devA": 40},
			"med": {"end_standard": 1763000000}, "evl": evl},
		"四结局全通": {"unlocked": 2, "difficulty": 2, "end": ["standard", "knight", "deep", "resolve"], "gal": ["enemy:bone", "enemy:ishar", "enemy:paranoia", "item:MIRE"],
			"rel": ["r_lamp", "r_shell", "r_heart"], "dbest": dbest, "ops": ["mizuki", "skadi", "wisadel"], "tiers": [0, 1, 2],
			"med": {"end_standard": 1763000000, "end_knight": 1763100000, "end_deep": 1763200000, "end_resolve": 1763300000}, "medb": {"sync_elite": 3}, "evl": evl,
			"shape": {"atk1": true}, "earned": {"devA": 300}},
		"深潮进度": {"unlocked": 2, "difficulty": 2, "end": ["standard"], "dbest": {"2": {"wins": 1, "best_t": 780, "fast_t": 690}}, "bounty": [0, 5, 10],
			"tiers": [0, 1, 2], "earned": {"devA": 120, "devB": 60}, "shape": {"atk1": true, "hp1": true}},
	}


func _ready() -> void:
	# ---- 1. 典型旧存档：迁移前后玩家可见的一样；写出再读两轮一致；旧位置原样
	for name in samples():
		var p: Dictionary = samples()[name]
		var c0 := legacy(p)
		read(c0)
		var v0 := visible()
		var exp := {"diff_unlocked": int(p.get("unlocked", 0)), "endings_cleared": p.get("end", []), "gallery_seen": p.get("gal", []),
			"seen_relics": p.get("rel", []), "diff_best": p.get("dbest", {}), "meta_bounty": p.get("bounty", []), "medals": p.get("med", {}),
			"medal_best": p.get("medb", {}), "event_log": p.get("evl", {}), "roster_tiers": p.get("tiers", [])}
		for f in exp:
			check(canon(v0[f]) == canon(exp[f]), "%s：读旧档后 %s 应原样 %s，实际 %s" % [name, f, canon(exp[f]), canon(v0[f])])
		check(Cfg.theme_cur == ThemeSave.LEGACY and Cfg.theme_saves.is_empty(), "%s：旧档归水月、没有别的主题" % name)
		var c1 := write(c0)
		check(c1.has_section(ThemeSave.section(ThemeSave.LEGACY)), "%s：写出后有 [theme_deep_sea] 段" % name)
		read(c1)
		var v1 := visible()
		check(canon(v1) == canon(v0), "%s：迁移写出再读应一致\n  前 %s\n  后 %s" % [name, canon(v0), canon(v1)])
		var c2 := write(c1)
		read(c2)
		check(canon(visible()) == canon(v0), "%s：第二轮写出再读仍一致（幂等）" % name)
		check(canon(ThemeSave.read_legacy(c2)) == canon(ThemeSave.read_legacy(c0)), "%s：旧位置的值不变（旧版本读得到）" % name)
		check(canon(ThemeSave.read_section(c2, ThemeSave.LEGACY)) == canon(ThemeSave.snapshot(Cfg)), "%s：主题段 = 当前进度" % name)

	# ---- 2. 降级再升级：旧版本只改旧位置
	var cd := migrate(legacy(samples()["通关结局一"]))
	read(cd)
	cd.set_value("progress", "endings_cleared", ["standard", "knight"])
	cd.set_value("progress", "seen_relics", ["r_lamp", "r_shell", "r_new"])
	cd.set_value("progress", "diff_unlocked", 2)
	read(cd)
	check(Cfg.endings_cleared == ["standard", "knight"] and Cfg.seen_relics.has("r_new") and Cfg.diff_unlocked == 2,
		"旧版本在旧位置新增的进度应并进来（%s / %s / %d）" % [str(Cfg.endings_cleared), str(Cfg.seen_relics), Cfg.diff_unlocked])

	# ---- 3. 第二个主题
	var c3 := migrate(legacy(samples()["四结局全通"]))
	read(c3)
	var ds_before := ThemeSave.snapshot(Cfg)
	Cfg.theme_switch("phantom")
	check(Cfg.endings_cleared.is_empty() and Cfg.diff_unlocked == 0 and Cfg.seen_relics.is_empty() and Cfg.medals.is_empty(), "切到新主题从空开始")
	check(Cfg.roster_unlocked.has("skadi") and not Cfg.meta_shape.is_empty(), "切主题时名册 / 认知塑造（全局）不变")
	check(Cfg.roster_tiers.is_empty() and Cfg.theme_saves.deep_sea.roster_tiers == [0, 1, 2], "已首通档按主题（11-18）：新主题从空开始，水月的留着")
	Cfg.roster_tiers.append(0)
	Cfg.endings_cleared.append("ph_ball")
	Cfg.diff_unlocked = 1
	Cfg.gallery_seen.append("enemy:ph_lucien")
	var c4 := write(c3)
	check(c4.has_section("theme_phantom") and canon(ThemeSave.read_legacy(c4)) == canon(ThemeSave.read_legacy(c3)), "新主题有自己的段，旧位置仍是水月")
	read(c4)
	check(Cfg.theme_cur == ThemeSave.LEGACY and canon(ThemeSave.snapshot(Cfg)) == canon(ds_before), "重新读档：当前主题水月，进度不变")
	check(Cfg.theme_saves.has("phantom") and Cfg.theme_saves.phantom.endings_cleared == ["ph_ball"] and int(Cfg.theme_saves.phantom.diff_unlocked) == 1, "新主题的进度读回来了")
	check(Cfg.roster_tiers == [0, 1, 2] and Cfg.theme_saves.phantom.roster_tiers == [0], "已首通档：两个主题各存各的（%s / %s）" % [str(Cfg.roster_tiers), str(Cfg.theme_saves.phantom.roster_tiers)])
	check(c4.get_value("roster", "tiers") == [0, 1, 2], "旧位置 [roster] tiers 仍是水月")
	Cfg.theme_switch("phantom")
	check(Cfg.endings_cleared == ["ph_ball"] and Cfg.gallery_seen == ["enemy:ph_lucien"], "切回新主题看到它自己的进度")
	Cfg.theme_switch(ThemeSave.LEGACY)
	check(canon(ThemeSave.snapshot(Cfg)) == canon(ds_before), "再切回水月：进度不变")

	# ---- 4. 云存档
	read(migrate(legacy(samples()["四结局全通"])))
	var b1: Dictionary = Cfg.cloud_body()
	check(not b1.prog.has("th"), "只有水月时云存档正文没有 th（与旧版本相同）")
	check(int(b1.prog.diff) == 2 and b1.prog.end.size() == 4, "云存档旧键是水月的进度")
	read(c4)
	var b2: Dictionary = Cfg.cloud_body()
	check(b2.prog.get("th", {}).has("phantom") and b2.prog.th.phantom.end == ["ph_ball"] and b2.prog.end.size() == 4, "有第二主题时 th 带上，旧键仍是水月")
	check(b2.prog.optier == [0, 1, 2] and b2.prog.th.phantom.optier == [0], "云存档已首通档：旧键 optier 是水月、th 里是傀影")
	var pk := Pack.pack(b2, 1000)
	var head = Pack.parse(str(pk.items[Pack.HEAD_KEY]))
	check(int(head.v) == 2 and int(head.minv) == 1, "头版本 2、最低读者 1（%s）" % str(head))
	var old_read := Pack.unpack(pk.items, 1)
	check(old_read.status == "ok" and old_read.body.prog.end.size() == 4, "旧版本（reader 1）照常解包，水月进度在旧键里")
	var mine := Pack.unpack(pk.items)
	check(mine.status == "ok" and mine.body.prog.th.phantom.end == ["ph_ball"], "本版解包 th 原样")
	# 冲突：本机水月多一个结局、傀影到 1 档；云端水月另一件藏品、傀影另一个结局 + 难度 2
	var local := b2.duplicate(true)
	local.prog.end = ["standard", "knight", "deep", "resolve"]
	var cloud := b2.duplicate(true)
	cloud.prog.end = ["standard"]
	cloud.prog.rel = cloud.prog.rel + ["r_cloud"]
	cloud.prog.th.phantom.end = ["ph_curtain"]
	cloud.prog.th.phantom.diff = 2
	cloud.prog.th["future"] = {"diff": 1, "end": ["x"], "zz": 7}
	var m := Pack.merge(local, cloud)
	check(m.prog.end.size() == 4 and m.prog.rel.has("r_cloud"), "冲突合并：水月旧键取并集")
	check(m.prog.th.phantom.end == ["ph_ball", "ph_curtain"] and int(m.prog.th.phantom.diff) == 2, "冲突合并：th 里的主题按主题取并集 / 取大（%s）" % str(m.prog.th.phantom))
	check(m.prog.th.has("future") and int(m.prog.th.future.zz) == 7, "冲突合并：本版不认识的主题 / 子键原样保留")
	Cfg.cloud_apply(m)
	check(Cfg.theme_cur == ThemeSave.LEGACY and Cfg.seen_relics.has("r_cloud") and Cfg.endings_cleared.size() == 4, "套用合并结果：水月对")
	check(Cfg.theme_saves.phantom.endings_cleared == ["ph_ball", "ph_curtain"] and int(Cfg.theme_saves.phantom.diff_unlocked) == 2, "套用合并结果：傀影对")
	check(Cfg.theme_saves.has("future") and Cfg.theme_saves.future.endings_cleared == ["x"], "套用合并结果：不认识的主题也收下")
	var rt: Dictionary = Cfg.cloud_body()
	check(rt.prog.th.has("future") and rt.prog.th.phantom.end == ["ph_ball", "ph_curtain"], "回写云端：所有主题都在")
	# 当前主题不是水月时：旧键仍写水月、cloud_apply 后仍在原主题
	Cfg.theme_switch("phantom")
	var b3: Dictionary = Cfg.cloud_body()
	check(b3.prog.end.size() == 4 and b3.prog.th.phantom.end == ["ph_ball", "ph_curtain"], "当前在傀影时：云端旧键仍是水月、傀影在 th")
	Cfg.cloud_apply(Pack.merge(b3, {}))
	check(Cfg.theme_cur == "phantom" and Cfg.endings_cleared == ["ph_ball", "ph_curtain"] and Cfg.theme_saves.deep_sea.endings_cleared.size() == 4, "当前在傀影时 cloud_apply 后仍在傀影、两边进度都对")
	Cfg.theme_switch(ThemeSave.LEGACY)

	# ---- 5. 全部解锁（调试 / 对内包）时换主题：真实进度跟着主题走，不串（11-18）
	read(c4)
	var ds_real := ThemeSave.snapshot(Cfg)
	Cfg.unlock_all = true
	Cfg._unlock_display()
	check(Cfg.endings_cleared.size() >= 4 and Cfg._real_progress.endings_cleared == ds_real.endings_cleared, "全开：界面全开、真实进度在 _real_progress")
	Cfg.theme_switch("phantom")
	check(Cfg._real_progress.endings_cleared == ["ph_ball"] and int(Cfg._real_progress.diff_unlocked) == 1, "全开换主题：_real_progress 换成新主题的真实值（%s）" % str(Cfg._real_progress))
	check(Cfg.theme_saves.deep_sea.endings_cleared == ds_real.endings_cleared and int(Cfg.theme_saves.deep_sea.diff_unlocked) == int(ds_real.diff_unlocked), "全开换主题：水月收进去的是真实进度，不是全开的演示数据")
	var c5 := write(c4)
	check(ThemeSave.read_section(c5, "phantom").endings_cleared == ["ph_ball"], "全开换主题后写档：新主题段是它自己的真实进度")
	check(canon(ThemeSave.read_section(c5, ThemeSave.LEGACY).endings_cleared) == canon(ds_real.endings_cleared), "全开换主题后写档：水月段没被新主题 / 演示数据覆盖")
	Cfg.theme_switch(ThemeSave.LEGACY)
	check(Cfg._real_progress.endings_cleared == ds_real.endings_cleared and Cfg.theme_saves.phantom.endings_cleared == ["ph_ball"], "全开再切回：两边真实进度都对")
	Cfg.unlock_all = false
	Cfg._real_progress = {}
	print("THEME SAVE checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
