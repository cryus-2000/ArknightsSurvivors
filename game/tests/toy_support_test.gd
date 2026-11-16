extends Node
## B站 Toy「支持作者」奖励回归（docs/313，core/toy_support.gd + screens/support_view.gd）：
##   godot --headless --path game res://tests/toy_support_test.tscn -- --regression --fbtoy --toybv=BV1xx411c7mD
## 模拟 SDK 的三种返回：关注（yes / no）、三连（yes / 缺项 no）、unsupported（外部浏览器）+ 未登录；每项只发一次；
## 11-16 用户：查到满足只标「可领取」（ready），点领取（claim）才到账、只发一次、写存档；已领过的照旧「已领取」。
## 云存档正文带 tsup、两台设备的领取记录取并集；浮层收到 unsupported 写「请在 B站 App 中打开」且不再查下一项。全部通过打印 "TOY SUPPORT failures=0"

const TS = preload("res://scripts/core/toy_support.gd")
const Roster = preload("res://scripts/core/roster.gd")
const CloudPack = preload("res://scripts/core/cloud_pack.gd")
var fails := 0


func ok(c: bool, what: String) -> void:
	if not c:
		fails += 1
		push_error("TOY SUPPORT: " + what)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	Cfg.toy_support = []
	Cfg.roster_tickets[Roster.T_HUNT] = 0
	ok(TS.is_toy(), "--fbtoy 应按 Toy 环境走")
	ok(TS.enabled(), "Toy 版应显示入口")
	ok(TS.items() == ["follow", "triple"], "配了 --toybv 时两项都在（%s）" % [TS.items()])
	ok(TS.pending(), "都没领时 pending")
	ok(TS.pending_tickets() == TS.REWARD * 2, "角标两项都算（%d）" % TS.pending_tickets())
	ok(TS.entry_label() == "支持作者：关注 +5 · 三连 +5 张寻访凭证", "统一入口文案（%s）" % TS.entry_label())
	# 11-08 用户：三连没配视频时照样列出、置灰、领不了，角标仍按两项算
	TS.bv_test = ""
	ok(TS.items() == ["follow", "triple"] and not TS.triple_open() and not TS.claimable("triple") and TS.claimable("follow"), "没配视频：三连列出但不能领")
	ok(TS.pending_tickets() == TS.REWARD * 2, "没配视频角标仍是 10（%d）" % TS.pending_tickets())
	var r0: Dictionary = TS.apply("triple", "yes")
	ok(not bool(r0.ready) and r0.msg == "PV 发布后开放" and not TS.claimed("triple") and TS.claim("triple") == 0, "没配视频不发三连（%s）" % r0.msg)
	TS.bv_test = null
	# unsupported / 未登录 / 其他错误：不发、不记
	var r: Dictionary = TS.apply("follow", "unsupported")
	ok(not bool(r.ready) and str(r.msg) == "请在 B站 App 中打开", "unsupported 提示去 App（%s）" % r.msg)
	r = TS.apply("triple", "login")
	ok(not bool(r.ready) and str(r.msg).contains("登录"), "未登录提示登录")
	r = TS.apply("follow", "err")
	ok(not bool(r.ready) and not TS.claimed("follow") and TS.claim("follow") == 0, "出错不记领取、领不了")
	# 关注：没关注 → 关注后只标可领取、不加券 → 点领取到账 5 张 → 重复点 / 再查不重复发
	r = TS.apply("follow", "no")
	ok(not bool(r.ready) and str(r.msg) == "还没有关注作者" and TS.ready_tickets() == 0, "没关注（%s）" % r.msg)
	r = TS.apply("follow", "yes")
	ok(bool(r.ready) and TS.is_ready("follow") and Roster.tickets() == 0 and not TS.claimed("follow"), "关注满足只标可领取、不自动发（凭证 %d）" % Roster.tickets())
	ok(TS.ready_tickets() == TS.REWARD and TS.entry_label() == "支持作者：可领取 5 张寻访凭证", "可领取角标 / 入口文案（%s）" % TS.entry_label())
	var before := Roster.tickets()
	ok(TS.claim("follow") == TS.REWARD and Roster.tickets() == before + TS.REWARD and TS.claimed("follow"), "点领取后凭证 %d → %d" % [before, Roster.tickets()])
	ok(TS.claim("follow") == 0 and Roster.tickets() == before + TS.REWARD, "重复点领取不再发")
	ok(TS.entry_label() == "支持作者：三连 +5 张寻访凭证" and TS.pending_tickets() == TS.REWARD and TS.ready_tickets() == 0, "领过关注后入口只写三连（%s）" % TS.entry_label())
	r = TS.apply("follow", "yes")
	ok(not bool(r.ready) and TS.claim("follow") == 0 and Roster.tickets() == TS.REWARD, "关注奖励只发一次（再查也不再可领取）")
	# 重载：ready 只在本次运行里，领取记录在存档里——模拟重载（清 ready）后领过的照旧「已领取」、不能再领
	TS.ready = []
	ok(TS.claimed("follow") and TS.claim("follow") == 0, "重载后领过的不重复发")
	ok(TS.frames() == ["ri"], "关注解锁罗德岛边框（%s）" % [TS.frames()])
	# 三连：缺投币 / 收藏 → 补齐后领 5 张 + 深海边框
	r = TS.apply("triple", "no", "coin,fav")
	ok(str(r.msg) == "三连还差：投币、收藏", "缺项写清楚（%s）" % r.msg)
	r = TS.apply("triple", "yes")
	ok(bool(r.ready) and Roster.tickets() == TS.REWARD, "三连满足不自动发（凭证 %d）" % Roster.tickets())
	var ra: Dictionary = TS.claim_all()
	ok(int(ra.granted) == TS.REWARD and Roster.tickets() == TS.REWARD * 2, "三连领取 5 张（凭证 %d）" % Roster.tickets())
	ok(TS.frames() == ["ri", "deep"] and str(ra.msg) == "已领取 5 张寻访凭证和专属分享卡边框「深海」", "三连送深海边框（%s / %s）" % [ra.msg, TS.frames()])
	ok(int(TS.claim_all().granted) == 0, "领完再全部领取不发")
	var keep: Array = Cfg.toy_support.duplicate()
	Cfg.toy_support = ["triple"]
	ok(TS.frames() == ["deep"], "只领三连只有深海边框")
	Cfg.toy_support = []
	ok(TS.frames().is_empty() and not TS.frame_unlocked(), "都没领没有边框")
	Cfg.toy_support = keep
	ok(not TS.pending(), "都领完不再 pending")
	# 云存档：正文带 tsup；两台设备各领一项，合并取并集
	var body: Dictionary = Cfg.cloud_body()
	ok(body.prog.get("tsup", []) == ["follow", "triple"], "云存档正文带 tsup（%s）" % [body.prog.get("tsup")])
	var a: Dictionary = body.duplicate(true)
	var b: Dictionary = body.duplicate(true)
	a.prog["tsup"] = ["follow"]
	b.prog["tsup"] = ["triple"]
	var m: Dictionary = CloudPack.merge(a, b)
	ok(m.prog.get("tsup", []).has("follow") and m.prog.get("tsup", []).has("triple"), "云存档领取记录取并集（%s）" % [m.prog.get("tsup")])
	# 一台没领、一台只领了关注：合并后边框算解锁
	var e: Dictionary = body.duplicate(true)
	e.prog.erase("tsup")
	var m2: Dictionary = CloudPack.merge(e, a)
	var keep2: Array = Cfg.toy_support.duplicate()
	Cfg.toy_support = (m2.prog.get("tsup", []) as Array).duplicate()
	ok(TS.frames() == ["ri"], "云存档合并后领过关注就有罗德岛边框（%s）" % [m2.prog.get("tsup")])
	Cfg.toy_support = keep2
	var c: Dictionary = body.duplicate(true)
	c.prog.erase("tsup")
	ok(not CloudPack.merge(c, {}).prog.has("tsup"), "没领过的存档不多出 tsup 字段")
	# 浮层：unsupported 只写一次环境提示、不再查下一项；领完按钮变「已全部领取」
	Cfg.toy_support = []
	var v: Control = load("res://scripts/screens/support_view.gd").new()
	add_child(v)
	await get_tree().process_frame
	v.open()
	v.busy = true
	v._queue = ["triple"]
	v.result("follow", "unsupported", "")
	ok(v.note == "请在 B站 App 中打开" and v._queue.is_empty() and not v.busy, "浮层 unsupported：提示去 App、停止查询（note=%s）" % v.note)
	v._queue = []
	Cfg.roster_tickets[Roster.T_HUNT] = 0
	v.result("follow", "yes", "")
	v.result("triple", "yes", "")
	ok(v.granted == 0 and Roster.tickets() == 0 and not v.all_claimed() and TS.ready_tickets() == TS.REWARD * 2, "浮层查到满足只标可领取（凭证 %d）" % Roster.tickets())
	await get_tree().process_frame
	ok(v.btns.has("claim_all"), "可领取时出「领取 10 张寻访凭证」按钮（%s）" % [v.btns.keys()])
	v.key(KEY_ENTER)   # 键盘 / 手柄确认 = 全部领取
	ok(v.granted == TS.REWARD * 2 and Roster.tickets() == TS.REWARD * 2 and v.all_claimed(), "Enter 领完两项（本次 %d，凭证 %d）" % [v.granted, Roster.tickets()])
	ok(v.note == "已领取 10 张寻访凭证和专属分享卡边框「罗德岛」「深海」" and v._fx_t >= 0.0, "领取提示 + 动效（%s）" % v.note)
	v.key(KEY_ENTER)
	ok(Roster.tickets() == TS.REWARD * 2, "再按 Enter 不重复发")
	await get_tree().process_frame
	ok(not v.btns.has("claim_all"), "领完底部按钮收起")
	ok(v.btns.has("go_follow") and v.btns.has("go_triple") and v.btns.has("close"), "浮层两项各一枚领取按钮（%s）" % [v.btns.keys()])
	ok(v.btns.go_follow.position.y == v.btns.go_triple.position.y and v.btns.go_follow.end.x < v.btns.go_triple.position.x, "两项并排")
	# 单项领取：只查这一项
	Cfg.toy_support = []
	v.check("triple")
	ok(v.busy and v._cur == "triple" and v._queue.is_empty(), "点三连只查三连（cur=%s）" % v._cur)
	v.result("triple", "yes", "")
	ok(TS.is_ready("triple") and not TS.claimed("triple") and not v.busy, "三连单独查到满足")
	v.claim("triple")
	ok(TS.claimed("triple") and not TS.claimed("follow"), "三连单独领到")
	# 标题页后台查询（桌面走 --toysim；本测试没给 = unsupported）：不发券、不标可领取
	TS.ready = []
	Cfg.toy_support = []
	var t0 := Roster.tickets()
	TS.probe()
	ok(TS.ready.is_empty() and Roster.tickets() == t0, "后台查询不自动发")
	TS.bv_test = ""
	Cfg.toy_support = []
	v.check("triple")
	ok(not v.busy, "没配视频点三连不查询")
	TS.bv_test = null
	print("TOY SUPPORT failures=%d" % fails)
	Cfg.toy_support = []
	get_tree().quit(1 if fails > 0 else 0)
