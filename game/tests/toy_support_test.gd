extends Node
## B站 Toy「支持作者」奖励回归（docs/313，core/toy_support.gd + screens/support_view.gd）：
##   godot --headless --path game res://tests/toy_support_test.tscn -- --regression --fbtoy --toybv=BV1xx411c7mD
## 模拟 SDK 的三种返回：关注（yes / no）、三连（yes / 缺项 no）、unsupported（外部浏览器）+ 未登录；每项只发一次；
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
	# unsupported / 未登录 / 其他错误：不发、不记
	var r: Dictionary = TS.apply("follow", "unsupported")
	ok(int(r.granted) == 0 and str(r.msg) == "请在 B站 App 中打开", "unsupported 提示去 App（%s）" % r.msg)
	r = TS.apply("triple", "login")
	ok(int(r.granted) == 0 and str(r.msg).contains("登录"), "未登录提示登录")
	r = TS.apply("follow", "err")
	ok(int(r.granted) == 0 and not TS.claimed("follow"), "出错不记领取")
	# 关注：没关注 → 关注后领 5 张 → 再查不重复发
	r = TS.apply("follow", "no")
	ok(int(r.granted) == 0 and str(r.msg) == "还没有关注作者", "没关注（%s）" % r.msg)
	r = TS.apply("follow", "yes")
	ok(int(r.granted) == TS.REWARD and Roster.tickets() == TS.REWARD and TS.claimed("follow"), "关注后发 5 张（凭证 %d）" % Roster.tickets())
	r = TS.apply("follow", "yes")
	ok(int(r.granted) == 0 and Roster.tickets() == TS.REWARD, "关注奖励只发一次")
	ok(not TS.frame_unlocked(), "关注不解锁边框")
	# 三连：缺投币 / 收藏 → 补齐后领 5 张 + 边框
	r = TS.apply("triple", "no", "coin,fav")
	ok(str(r.msg) == "三连还差：投币、收藏", "缺项写清楚（%s）" % r.msg)
	r = TS.apply("triple", "yes")
	ok(int(r.granted) == TS.REWARD and Roster.tickets() == TS.REWARD * 2, "三连发 5 张（凭证 %d）" % Roster.tickets())
	ok(TS.frame_unlocked(), "三连解锁专属分享卡边框")
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
	v.result("follow", "yes", "")
	v.result("triple", "yes", "")
	ok(v.granted == TS.REWARD * 2 and v.all_claimed(), "浮层领完两项（本次 %d）" % v.granted)
	await get_tree().process_frame
	ok(v.btns.has("go"), "浮层画出按钮")
	print("TOY SUPPORT failures=%d" % fails)
	Cfg.toy_support = []
	get_tree().quit(1 if fails > 0 else 0)
