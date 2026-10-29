extends Node
## 分支培养 + 培养保底回归（docs/119 §4.1 / §4.2，试点 4 人：德克萨斯 / 星熊 / 艾雅法拉 / 铃兰）：
##   godot --headless --path game res://tests/build_progression_test.tscn -- --regression --balance --seed=1 --op=texas --squad=hoshiguma,eyjafjalla
## 校验：外层只出一张培养卡；选中进二选一、「返回」恢复原卡组（同一个数组、不重抽、不扣升级）；确认只扣一次升级、节点攻击 +6% 只加一次；
## 节点 5 按路线解析；赠送推进（典训 / 博士银印）玩家局排队进同一事务（只能确认、不扣升级）、机器人局固定路线；
## 换入继承到节点 4 以上时在换人流程里选路线并按新路线一次性重建；机器人在路线屏选固定路线；其余干员无分支节点、校验通过；
## 培养保底：最近培养的干员有合法成长卡时固定占一个位。全部通过时打印 "BUILD PROGRESSION failures=0"

const Ch = preload("res://scripts/characters/character.gd")
const Bal = preload("res://scripts/core/balance.gd")

## 干员攻击倍率的基础值（基础砍 squad/op_atk_base，docs/109 §14.1）：节点 +6% 是 add，按它放大
func atk_base() -> float:
	return Bal.v("squad/op_atk_base", 1.0)
const Prog = preload("res://scripts/run/progression.gd")
## 已接分支的干员（docs/120；p2 逐批加入）——其余干员必须没有分支节点
const PILOT := ["texas", "hoshiguma", "eyjafjalla", "suzuran", "exusiai", "skadi", "siege", "saria", "wisadel", "lumen", "kaltsit",
	"logos", "skalter", "mizuki", "specter_unchained", "irene", "angelina", "ulpianus",
	"lappland", "gladiia"]   # 10-22 第四批（docs/122 / 123）

var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


var shot_mode := false   # --branch_shot：开窗口，打开德克萨斯的路线屏停 40 帧后截图 build/shots/branch_panel.png（看卡面绘制不报错）
var shot_frame := -1


func _process(_d: float) -> void:
	frames += 1
	if shot_mode and shot_frame > 0:
		if frames == shot_frame:
			var img := get_viewport().get_texture().get_image()
			var dir: String = ProjectSettings.globalize_path("res://").path_join("../build/shots")
			DirAccess.make_dir_recursive_absolute(dir)
			var rc: int = img.save_png(dir.path_join("branch_panel.png"))
			print("BRANCH SHOT saved rc=%d %s" % [rc, dir])
		elif frames == shot_frame + 2:
			print("BUILD PROGRESSION failures=%d" % fails)
			get_tree().quit(1 if fails > 0 else 0)
		return
	if frames != 5:
		return
	shot_mode = OS.get_cmdline_user_args().has("--branch_shot")
	if shot_mode:
		game.pending_levelups = 0
		game.pending_chests = 0
		game.show_queue.clear()
		var o = game.squad.get_op("texas")
		for k in 3:
			o.advance("")
		game.show_queue.clear()
		var pc := prog_cards(o)
		game.pending_levelups = 1
		game.panel_ui.show_choices("升级", [pc[0], {"kind": "filler", "id": "heal", "name": "急救补给", "desc": ""}], "level", "", true)
		game.progression.pick(0)
		ok(game.choice_kind == "branch", "路线屏已打开")
		game.mode = game.Mode.PLAY   # 机器人（--balance）会立刻替玩家选卡；截图期间当玩家局
		shot_frame = frames + 110
		return
	set_process(false)
	game.set_process(false)
	game.pending_levelups = 0
	game.pending_chests = 0
	game.show_queue.clear()
	test_cards_and_cancel()
	test_confirm_once()
	test_node5_by_route()
	test_gift_player_queue()
	test_gift_bot_fixed()
	test_gift_relic()
	test_swap_inherit()
	test_bot_branch_pick()
	test_others_compat()
	test_focus_guard()
	test_catchup()
	print("%d checks, %d failed" % [n, fails])
	print("BUILD PROGRESSION failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func idx(pred: Callable) -> int:
	for i in game.choices.size():
		if pred.call(game.choices[i]):
			return i
	return -1


func prog_cards(o) -> Array:
	return o.deep_cards().filter(func(c): return c.get("kind", "") == "prog")


func op_atk(o) -> float:
	return game.stats.value_for(&"op_atk", o.scopes())


## 德克萨斯推进到节点 3（精一）：外层只出一张培养卡；选中进二选一；返回恢复同一个卡组、不扣升级
func test_cards_and_cancel() -> void:
	var o = game.squad.get_op("texas")
	ok(o != null, "德克萨斯在编队里")
	for k in 3:
		o.advance("")
	game.show_queue.clear()   # 精一演出不入队（否则 check_pending 先开演出）
	ok(o.prog == 3 and o.elite == 1 and o.needs_route(), "精一后下一节点是分支节点（needs_route）")
	var pc := prog_cards(o)
	ok(pc.size() == 1 and pc[0].get("branch", false) and str(pc[0].get("choice", "")) == "", "外层只出一张带 branch 的培养卡（%d 张）" % pc.size())
	var rc: Dictionary = o.route_choices()
	ok(rc.keys() == ["back", "rain"], "路线 id = back / rain：%s" % str(rc.keys()))
	game.pending_levelups = 1
	game.panel_ui.show_choices("升级", [pc[0], {"kind": "filler", "id": "heal", "name": "急救补给", "desc": ""}], "level", "", true)
	var opts0: Array = game.choices
	game.progression.pick(0)
	ok(game.state == game.S.CHOICE and game.choice_kind == "branch", "选中培养卡进入路线屏（kind=branch）")
	ok(game.choices.filter(func(c): return c.kind == "branch_pick").size() == 2 and idx(func(c): return c.kind == "branch_back") >= 0, "路线屏：2 条路线 + 返回")
	ok(game.pending_levelups == 1, "进路线屏不扣升级")
	var t0: int = o.taken.size()
	var p0: int = o.prog
	game.progression.pick(idx(func(c): return c.kind == "branch_back"))
	ok(game.choice_kind == "level" and game.choices == opts0, "返回：回到原卡组（同一个数组，不重抽）")
	ok(game.pending_levelups == 1 and o.prog == p0 and o.taken.size() == t0 and o.route == "", "返回：不扣升级、不推进、路线未定")
	ok(game.nav_sel == 0, "返回：焦点留在原来那张卡")


## 确认路线：只扣一次升级、只推进一个节点、节点攻击 +6% 只加一次、taken 只有所选路线的节点 id
func test_confirm_once() -> void:
	var o = game.squad.get_op("texas")
	var a0: float = op_atk(o)
	var lv0: int = o.node_lv
	game.progression.pick(0)   # 培养卡 → 路线屏
	var ri := idx(func(c): return c.kind == "branch_pick" and str(c.route) == "rain")
	ok(ri >= 0, "路线屏有「剑雨」路线")
	game.progression.pick(ri)
	ok(game.state == game.S.PLAY, "确认后回到战斗（state=%d）" % game.state)
	ok(game.pending_levelups == 0, "只扣一次升级（%d）" % game.pending_levelups)
	ok(o.prog == 4 and o.route == "rain", "推进到节点 4、路线 rain（prog=%d route=%s）" % [o.prog, o.route])
	ok(o.taken.has("rain2") and not o.taken.has("back"), "taken 只有所选路线的节点 id：%s" % str(o.taken))
	ok(o.node_lv == lv0 + 1, "普通节点计数只 +1")
	ok(is_equal_approx(op_atk(o) - a0, Ch.NODE_ATK * atk_base()), "节点攻击 +6%% 只加一次（Δ=%.3f）" % (op_atk(o) - a0))
	ok(game.progression.focus_op == "texas", "培养保底：德克萨斯成为最近培养对象")


## 节点 5 按路线解析：卡面名字与 id 都是路线版（rain → rain3「剑雨·连绵」，10-25 德克萨斯改名；不是旧线 rain2 / 不是另一条的 back2）
func test_node5_by_route() -> void:
	var o = game.squad.get_op("texas")
	var pc := prog_cards(o)
	ok(pc.size() == 1 and not pc[0].get("branch", false) and "剑雨·连绵" in str(pc[0].name), "节点 5 卡面按路线：%s" % str(pc[0].get("name", "")))
	var n5: Dictionary = o.node_view(o.next_node())
	ok(str(n5.get("id", "")) == "rain3", "节点 5 解析 id = rain3（%s）" % str(n5.get("id", "")))
	o.advance("")
	ok(o.prog == 5 and o.taken.has("rain3") and not o.taken.has("back2") and o.taken.count("rain2") == 1, "节点 5 生效、不重复：%s" % str(o.taken))
	ok(o.node_view(o.progression()[3], "back").get("id", "") == "back" and o.prog_view()[4].get("id", "") == "rain3", "node_view / prog_view 按路线解析")


## 赠送推进（玩家局）：advance("") 不推进而是排队；check_pending 弹出路线屏（没有「返回」）；确认后推进、不扣升级
func test_gift_player_queue() -> void:
	var o = game.squad.get_op("hoshiguma")
	for k in 3:
		o.advance("")
	game.show_queue.clear()   # 精一演出不入队（否则 check_pending 先开演出）
	ok(o.prog == 3 and o.needs_route(), "星熊到分支节点")
	var mode0 = game.mode
	game.mode = game.Mode.PLAY
	var bot0 = game.bot
	game.bot = null
	game.pending_levelups = 2
	o.advance("")
	ok(o.prog == 3 and o.route == "" and game.progression.branch_queue == ["hoshiguma"], "玩家局赠送推进：不静默选，排进 branch_queue")
	o.advance("")
	ok(game.progression.branch_queue.size() == 1, "重复触发不重复排队")
	game.state = game.S.PLAY
	game.check_pending()
	ok(game.state == game.S.CHOICE and game.choice_kind == "branch", "check_pending 弹出路线屏")
	ok(idx(func(c): return c.kind == "branch_back") < 0 and game.choices.size() == 2, "赠送推进的路线屏只能确认（无返回）")
	var ei := idx(func(c): return c.kind == "branch_pick" and str(c.route) == "ember")
	var a0: float = op_atk(o)
	game.progression.pick(ei)
	ok(o.prog == 4 and o.route == "ember" and o.taken.has("ember") and not o.taken.has("wall"), "确认后推进节点 4、路线 ember：%s" % str(o.taken))
	ok(game.pending_levelups == 2, "赠送推进不扣升级")
	ok(is_equal_approx(op_atk(o) - a0, Ch.NODE_ATK * atk_base()), "赠送推进节点攻击只加一次")
	ok(game.progression.branch_queue.is_empty(), "队列清空")
	ok(game.state == game.S.CHOICE and game.choice_kind == "level", "确认后 check_pending 接着处理待办的升级（pending=2）")
	game.panel.visible = false
	game.state = game.S.PLAY
	game.mode = mode0
	game.bot = bot0
	game.pending_levelups = 0


## 赠送推进（机器人 / 测试）：固定路线 bot_route（JSON "bot"），不进界面
func test_gift_bot_fixed() -> void:
	var o = game.squad.get_op("eyjafjalla")
	for k in 3:
		o.advance("")
	game.show_queue.clear()   # 精一演出不入队（否则 check_pending 先开演出）
	ok(o.needs_route() and o.bot_route(o.next_node()) == "ignite", "艾雅法拉固定路线 = ignite（JSON bot）")
	o.advance("")
	ok(o.prog == 4 and o.route == "ignite" and o.taken.has("ignite_blobs") and not o.taken.has("meteor"), "机器人局 advance(\"\") 按固定路线推进：%s" % str(o.taken))
	ok(game.progression.branch_queue.is_empty(), "机器人局不排队")
	o.advance("")
	ok(o.taken.has("ignite2") and not o.taken.has("meteor2"), "节点 5 = ignite2：%s" % str(o.taken))


## 典训（藏品 35：推进一名重装）走同一事务：机器人局直接按固定路线推进；只结算一次（星熊已到节点 4，典训推进节点 5 → ember2）
func test_gift_relic() -> void:
	var o = game.squad.get_op("hoshiguma")
	var p0: int = o.prog
	var lv0: int = game.pending_levelups
	var got: bool = game.progression.gain_relic("35")
	ok(got, "拿到典训（重装）")
	ok(o.prog == p0 + 1 and o.taken.has("ember2") and not o.taken.has("wall2"), "典训推进节点 5 按路线 ember 解析：%s" % str(o.taken))
	ok(game.pending_levelups == lv0, "典训不额外给升级次数")


## 换入继承：艾雅法拉（节点 5、路线 ignite）换成铃兰 → 换人确认前先选铃兰的路线；按新路线一次性重建（taken 只有 hearth 线），只扣一次升级
func test_swap_inherit() -> void:
	ok(game.squad.is_full(), "编队满员（3 人）")
	var card := {"kind": "recruit", "swap": true, "id": "suzuran", "name": "铃兰", "cls": "辅助", "desc": ""}
	game.pending_levelups = 1
	game.panel_ui.show_choices("升级", [card], "level", "", true)
	game.progression.pick(0)
	ok(game.choice_kind == "swap", "满员招募卡进更换队友屏")
	var si := idx(func(c): return c.kind == "swap_out" and str(c.op) == "eyjafjalla")
	ok(si >= 0, "有「换下艾雅法拉」")
	game.progression.pick(si)
	ok(game.choice_kind == "branch" and game.choices.size() == 3, "继承到节点 4 以上：先选换入干员的路线")
	ok(game.pending_levelups == 1, "路线屏不扣升级")
	game.progression.pick(idx(func(c): return c.kind == "branch_back"))
	ok(game.choice_kind == "swap", "路线屏返回 → 回到更换队友屏")
	game.progression.pick(si)
	var hi := idx(func(c): return c.kind == "branch_pick" and str(c.route) == "hearth")
	game.progression.pick(hi)
	var s = game.squad.get_op("suzuran")
	ok(s != null and not game.squad.has("eyjafjalla"), "铃兰接替艾雅法拉")
	if s != null:
		ok(s.prog == 5 and s.elite == 1 and s.route == "hearth", "继承 5 个节点、精一、路线 hearth（prog=%d route=%s）" % [s.prog, s.route])
		ok(s.taken.has("fox_hearth") and s.taken.has("fox_hearth2") and not s.taken.has("fox_seal") and not s.taken.has("fox_seal2"), "按新路线一次性重建：%s" % str(s.taken))
		ok(s.node_lv == 4 and is_equal_approx(op_atk(s), atk_base() * (1.0 + 4 * Ch.NODE_ATK)), "继承的普通节点攻击加成 = 4 × 6%%（op_atk=%.3f）" % op_atk(s))
	ok(game.pending_levelups == 0 and game.state == game.S.PLAY, "换人只扣一次升级")
	# 继承不足节点 4：不进路线屏（铃兰换回艾雅法拉时艾雅法拉继承 5 → 要选；这里用 prog 2 的临时情形）
	var card2 := {"kind": "recruit", "swap": true, "id": "eyjafjalla", "name": "艾雅法拉", "cls": "术师", "desc": ""}
	s.prog = 2
	game.pending_levelups = 1
	game.panel_ui.show_choices("升级", [card2], "level", "", true)
	game.progression.pick(0)
	var si2 := idx(func(c): return c.kind == "swap_out" and str(c.op) == "suzuran")
	game.progression.pick(si2)
	var e = game.squad.get_op("eyjafjalla")
	ok(game.state == game.S.PLAY and e != null and e.prog == 2 and e.route == "", "继承不足节点 4：不选路线，直接换入（prog=%d）" % (e.prog if e != null else -1))
	game.pending_levelups = 0


## 机器人在路线屏选固定路线（德克萨斯 bot=back）：auto_branch_pick 指向 back 那张
func test_bot_branch_pick() -> void:
	var o = game.squad.get_op("texas")
	o.prog = 3
	o.route = ""
	var pc := prog_cards(o)
	ok(pc.size() == 1 and pc[0].get("branch", false), "回到节点 3 后再出培养卡")
	game.pending_levelups = 1
	game.panel_ui.show_choices("升级", [pc[0]], "level", "", true)
	game.progression.pick(0)
	var bi: int = game.progression.auto_branch_pick()
	ok(game.choices[bi].get("kind", "") == "branch_pick" and str(game.choices[bi].get("route", "")) == "back", "机器人选固定路线 back")
	ok(game.progression.auto_choices().size() == game.choices.size(), "路线屏候选不被 auto_choices 滤掉")
	game.progression.pick(idx(func(c): return c.kind == "branch_back"))
	game.panel.visible = false
	game.state = game.S.PLAY
	game.pending_levelups = 0
	o.prog = 5
	o.route = "rain"


## 其余干员：没有分支节点、契约校验通过；带分支的干员（PILOT）的 blocks.progression 含全部路线节点 id
func test_others_compat() -> void:
	var others := 0
	for cid in Ch.list_ids():
		var d: Dictionary = Ch.load_def(cid)
		ok(Ch.validate_operator(cid, d), "%s 契约校验通过" % cid)
		var bn: Array = Prog.branch_node_of(d)
		if cid in PILOT:
			ok(bn[1] == 3 and (bn[0].branch as Dictionary).size() == 2, "%s 分支节点在第 4 位、两条路线" % cid)
			var pg5: Dictionary = d.progression[4]
			ok(pg5.get("routes", {}).keys() == bn[0].branch.keys(), "%s 节点 5 routes 键与分支一致" % cid)
			for rk in bn[0].branch:
				ok(d.blocks.progression.has(str(bn[0].branch[rk].id)) and d.blocks.progression.has(str(pg5.routes[rk].id)), "%s 路线 %s 的两个节点都有积木" % [cid, rk])
		else:
			others += 1
			ok(bn[1] == -1, "%s 没有分支节点" % cid)
	ok(others == Ch.list_ids().size() - PILOT.size(), "其余 %d 人没有分支节点（%d）" % [Ch.list_ids().size() - PILOT.size(), others])
	# 安洁莉娜（docs/202 10-29：alt 删除，致密恢复可选）：节点 1 双重引力、节点 2 致密（含重力透镜）、节点 4 起沿分支；顶层不再有死节点
	var ad: Dictionary = Ch.load_def("angelina")
	ok(not ad.progression[0].has("alt") and not ad.progression[1].has("alt"), "安洁莉娜没有 alt")
	ok(str(ad.progression[0].id) == "pull2" and str(ad.progression[1].id) == "dense" and str(ad.progression[3].id) == "pull2" and str(ad.progression[4].id) == "lock2", "安洁莉娜成长线：双重引力 / 致密 / 精一 / 分支 / 路线")


## 培养保底（§4.2 简化版）：最近培养的干员有合法成长卡时，升级三选一固定含它的成长卡；离队 / 养满自然失效
func test_focus_guard() -> void:
	if not game.guide.focus_on():
		return
	var cu = Bal._data["levelup"].get("catchup", 1)
	Bal._data["levelup"]["catchup"] = 0   # 这里测旧保底（只看最近培养对象）；落后补偿下的保底见 test_catchup
	game.level = 6
	game.progression.focus_op = "hoshiguma"
	var hits := 0
	for k in 6:
		game.pending_levelups = 1
		game.progression.open_levelup()
		if idx(func(c): return c.kind == "prog" and str(c.op) == "hoshiguma") >= 0:
			hits += 1
		game.panel.visible = false
		game.state = game.S.PLAY
	ok(hits == 6, "最近培养对象（星熊）6 次升级都占一个位（%d/6）" % hits)
	game.progression.focus_op = "texas"
	hits = 0
	for k in 6:
		game.pending_levelups = 1
		game.progression.open_levelup()
		if idx(func(c): return c.kind == "prog" and str(c.op) == "texas") >= 0:
			hits += 1
		game.panel.visible = false
		game.state = game.S.PLAY
	ok(hits == 6, "切换对象后德克萨斯 6 次都占一个位（%d/6）" % hits)
	game.progression.focus_op = "nobody"
	game.pending_levelups = 1
	game.progression.open_levelup()
	ok(game.progression.focus_op == "", "对象不在编队：清除")
	game.panel.visible = false
	game.state = game.S.PLAY
	game.pending_levelups = 0
	Bal._data["levelup"]["catchup"] = cu


## 精英化落后补偿（docs/173）：权重按落后阶段 ×catchup_mult^gap 封顶；排序只重排不加卡；保底让给落后 ≥ catchup_focus_gap 的队友；关 = 旧行为
func test_catchup() -> void:
	var P = game.progression
	var cu = Bal._data["levelup"].get("catchup", 1)
	Bal._data["levelup"]["catchup"] = 1
	var m: float = Bal.v("levelup/catchup_mult", 1.8)
	var cap: float = Bal.v("levelup/catchup_cap", 3.0)
	ok(is_equal_approx(game.guide.catchup_weight(4, 4), 1.0), "进度最高者权重 1")
	ok(is_equal_approx(game.guide.catchup_weight(1, 4), m), "落后 1 个精英阶段（3 节点）×%.1f" % m)
	ok(is_equal_approx(game.guide.catchup_weight(0, 6), minf(m * m, cap)), "落后 2 阶段按封顶")
	ok(game.guide.catchup_weight(0, 6) <= cap, "不超过封顶 %.1f" % cap)
	# 造一个断层：德克萨斯（队长）比星熊 / 艾雅法拉领先 ≥ 3 节点
	var tx = game.squad.get_op("texas")
	var hs = game.squad.get_op("hoshiguma")
	var ey = game.squad.get_op("eyjafjalla")
	tx.prog = 5
	hs.prog = 1
	ey.prog = 0
	game.level = 8
	var deep: Array = P.deep_cards()
	var n0 := deep.size()
	var ord: Array = game.guide.catchup_order(deep.duplicate())
	ok(ord.size() == n0, "加权排序不增减卡（%d → %d）" % [n0, ord.size()])
	ok(game.guide.catchup_focus(deep, "texas") == "eyjafjalla", "最近培养对象领先最落后者 ≥ catchup_focus_gap 节点：保底让给最落后的艾雅法拉")
	ok(game.guide.catchup_focus(deep, "hoshiguma") == "hoshiguma", "最近培养对象本身不领先：保底不变")
	# 统计：多次升级里第一深度位的归属，落后者应多于领先者
	var first := {}
	for k in 60:
		var o2: Array = game.guide.catchup_order(deep.duplicate())
		var who := str(o2[0].get("op", ""))
		first[who] = first.get(who, 0) + 1
	ok(int(first.get("eyjafjalla", 0)) > int(first.get("texas", 0)), "第一深度位：落后者多于领先者 %s" % str(first))
	P.focus_op = "texas"
	var hits := 0
	for k in 6:
		game.pending_levelups = 1
		P.open_levelup()
		if idx(func(c): return c.kind == "prog" and str(c.op) == "eyjafjalla") >= 0:
			hits += 1
		game.panel.visible = false
		game.state = game.S.PLAY
	ok(hits == 6, "队长领先时保底位给最落后的队友（%d/6）" % hits)
	# 关：同一状态下保底仍给最近培养对象
	Bal._data["levelup"]["catchup"] = 0
	hits = 0
	for k in 6:
		game.pending_levelups = 1
		P.open_levelup()
		if idx(func(c): return c.kind == "prog" and str(c.op) == "texas") >= 0:
			hits += 1
		game.panel.visible = false
		game.state = game.S.PLAY
	ok(hits == 6, "catchup=0：保底仍给最近培养对象（%d/6）" % hits)
	Bal._data["levelup"]["catchup"] = cu
	game.pending_levelups = 0
