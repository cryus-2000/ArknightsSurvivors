extends Node
## 新手引导强制部分（docs/219 §6，check.py 场景回归 onboard_forced；参数 --onboard=ask 走第一次进游戏的强制版，不读不写存档）。
## 1. 第一次进游戏：问题框只有「玩过 / 没玩过」、Esc 不选、skip_all 不生效；2. 两条线的演示局步骤：都含招募 / 连携 / 终结技 / 指挥圆盘，按顺序出；
## 3. 「连携」一步：充满队长技力 + 身边放怪，到点还没放技能就直接触发；3b. 指挥两步：部署以指令生效 + 队友到位为准、随行以部署撤销为准；4. 存档：onboard_done 往返，旧档走完过旧演示局的算完成；
## 5. 云存档：prog.onb 取或、旧正文没有就不补；cloud_apply 不把本机的完成改回去；6. 走完之后不再强制（_first_time 读 Cfg.onboard_done）。
## 11-07（Toy 预览实测）：3e. 灯火一步：压低灯火 + 身边放灯油，捡到才算；3d. 集火下令后等精英倒下才算；
## 7. 两卡不重叠：演示局 / 教程卡在时 tour 小提示不查、小字提示不计时不显示；8. 教过的提示正式局不弹，没教过的走小字提示（不出大卡）；
## 9. 结尾：「演示结束」是模态框，不自动跳走，按确认 / 点按钮才进正式局；总上限兜底也出这张框。
const CloudPack = preload("res://scripts/core/cloud_pack.gd")
const Game = preload("res://scripts/game.gd")

var failures := 0
var g


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("ONBOARD FORCED: " + what)
		print("FAIL ", what)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 4:
		await get_tree().process_frame
	g.set_process(false)
	var ob = g.onboard
	# 1. 第一次进游戏：问题框不给跳过
	check(ob.forced, "--onboard=ask 按第一次进游戏走（forced）")
	check(ob.ask_on, "开局弹问题框")
	var opts: Array = ob._ask_opts()
	check(opts.size() == 2 and not opts.any(func(o): return str(o[2]) == "off"), "强制时问题框只有玩过 / 没玩过：" + str(opts.map(func(o): return o[0])))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	ob.input(esc)
	check(ob.ask_on, "Esc 不关问题框、不选跳过")
	ob._choose(0)   # 玩过 → 快速演示局
	check(not ob.ask_on and ob.mode == "vet" and ob.drill, "选玩过：走快速演示局（drill_vet）")
	ob.skip_all()
	check(ob.mode == "vet" and ob.drill, "强制时 skip_all 不生效")
	# 2. 两条线的步骤：都含本作特色，按顺序
	for key in ["drill", "drill_vet"]:
		var lst: Array = ob.data.get(key, [])
		for need in ["recruit", "link", "ult", "deploy", "regroup", "lamp", "beacon", "focus"]:
			check(lst.has(need), "%s 缺 %s" % [key, need])
		check(lst.back() == "drill_end", key + " 以演示结束收尾")
	check(ob.data.get("drill", []).has("move") and not ob.data.get("drill_vet", []).has("move"), "没玩过才教移动 / 升级")
	check(ob.drill_ids() == ["recruit", "link", "ult", "deploy", "regroup", "lamp", "beacon", "focus"], "快速线步骤：" + str(ob.drill_ids()))
	check(ob._trigger("recruit") and not ob._trigger("link") and not ob._trigger("ult"), "按顺序：先出招募")
	ob.seen_mem.append("recruit")
	check(ob._trigger("link") and not ob._trigger("ult"), "招募做完才出连携")
	# 3. 连携：放怪 + 充满技力；到点直接触发
	g.state = Game.S.PLAY
	if g.squad.size() < 2:
		g.squad.add("skadi")
	var n0: int = g.enemies.size()
	ob.cur = ""
	ob._show("link")
	check(g.enemies.size() - n0 == ob.LINK_PACK, "连携一步在队长身边放 %d 只怪（实际 %d）" % [ob.LINK_PACK, g.enemies.size() - n0])
	var ld = g.squad.leader()
	check(ld != null and ld.sp[0] >= ld.sp_need(0), "连携一步充满队长技力")
	ob.cur_t = ob.LINK_NUDGE + 0.1
	ob.update(0.016)
	check(ob._nudged, "到点还没放技能：直接触发一次连携")
	# 3b. 指挥：部署（怪群从一侧涌来；以指令实际生效、队友走到驻扎位为准）→ 随行
	ob._finish()
	ob.cur = ""
	var n1: int = g.enemies.size()
	ob._show("deploy")
	check(g.enemies.size() - n1 == ob.PACK_N, "部署一步从一侧放 %d 只怪" % ob.PACK_N)
	check(ob.wheel_tour(), "部署一步：打开圆盘时扇区依次亮起")
	g.wheel.open()
	g.wheel.t_open = 0.1
	check(g.wheel._tour_hover() == 0, "圆盘刚打开亮第一项")
	g.wheel.t_open = g.wheel.TOUR_STEP * (g.wheel.ITEMS.size() + 1)
	check(g.wheel._tour_hover() == g.wheel.item_index("point"), "转完一圈停在「部署」")
	g.wheel.confirm(g.wheel.item_index("point"))
	check(not ob._deployed(), "只点了扇区（还在选点）不算部署")
	g.pick.cancel()
	g.squad.apply_order("point", g.ppos - ob.pack_dir * 260.0, null)
	check(ob._deployed(), "下了部署就算（11-08：不等队友走到、不限方向）")
	ob._finish()
	ob.cur = ""
	ob._show("regroup")
	check(not ob._done("regroup"), "随行一步：还没下令不算")
	g.wheel.open()
	g.wheel.confirm(g.wheel.item_index("guard"))
	check(g.squad.order_kind == "" and g.squad.stance != g.squad.ROAM and ob._done("regroup"), "选随行：部署撤销、回到随行")
	# 3e. 灯火：灯火压低一截 + 身边两份灯油；捡到（灯火回升）才算，等太久也往下走
	ob._finish()
	ob.cur = ""
	g.lamp = 100.0
	var pk0: int = g.gems.size()
	ob._show("lamp")
	check(absf(g.lamp - ob.LAMP_SET) < 0.01, "灯火一步：灯火压到 %d（实际 %.1f）" % [int(ob.LAMP_SET), g.lamp])
	check(ob._oil_pos != Vector2.INF, "灯火一步：身边放了灯油")
	if pk0 >= 0:
		check(g.gems.size() - pk0 == 2, "灯火一步：放两份灯油（实际 %d）" % (g.gems.size() - pk0))
	check(not ob._done("lamp"), "灯火一步：还没捡不算")
	g.lamp += ob.LAMP_OIL
	check(ob._done("lamp"), "灯火一步：捡到灯油（灯火回升）算做完")
	g.lamp = ob.LAMP_SET
	ob.cur_t = ob.LAMP_WAIT + 0.1
	check(ob._done("lamp"), "灯火一步：等太久也往下走")
	# 3c. 引航灯标：身边放一座 + 溟痕；等太久代点亮；灯标没了重放、放不下跳过
	ob._finish()
	ob.cur = ""
	var m0: int = g.mires.size()
	var bc0: int = g.beacons.size()
	ob._show("beacon")
	check(ob.demo_beacon != null and g.beacons.size() == bc0 + 1, "灯标一步：身边放一座灯标")
	check(g.mires.size() - m0 == ob.BEACON_MIRES, "灯标一步：周围放 %d 片溟痕" % ob.BEACON_MIRES)
	check(ob.demo_beacon.pos.distance_to(g.ppos) > 100.0 and ob.demo_beacon.pos.distance_to(g.ppos) < 400.0, "灯标离队长一小段路")
	check(not ob._done("beacon"), "灯标一步：还没点燃不算")
	ob.cur_t = ob.BEACON_WAIT + 0.1
	ob._beacon_tick()
	check(bool(ob.demo_beacon.lit) and ob._done("beacon"), "等太久没点：引导代点亮并算做完")
	ob.cur = ""
	ob.demo_beacon.dead = true
	ob.beacon_tries = ob.STEP_TRIES
	ob.cur = "beacon"
	ob.demo_beacon = {"dead": true, "lit": false}
	ob._beacon_tick()
	check(ob._skip_beacon and ob._done("beacon"), "灯标重放用完：跳过这一步")
	# 3d. 集火：身边放一只精英；等太久代下；精英没了重放、放不下跳过
	ob._finish()
	ob.cur = ""
	var n2: int = g.enemies.size()
	ob._show("focus")
	check(ob.focus_tgt != null and g.enemies.size() - n2 == 1 and bool(ob.focus_tgt.elite), "集火一步：身边放一只精英")
	check(not ob._done("focus"), "集火一步：还没下令不算")
	ob.cur_t = ob.FOCUS_WAIT + 0.1
	g.squad.clear_order()
	ob._focus_tick()
	check(ob._focus_given or ob._skip_focus, "等太久没下：引导代下一次集火")
	if ob._focus_given:
		ob.cur_t = ob._focus_t
		check(not ob._done("focus"), "集火刚下令：先停 FOCUS_SHOW 秒看转火")
		ob.cur_t = ob._focus_t + ob.FOCUS_SHOW + 0.1
		check(ob._done("focus"), "下了集火就算做完（11-08：不等精英倒下）")
	check(ob.text_of("focus", false).find("精英") >= 0 and ob.text_of("focus", false).find("宝箱") >= 0, "集火卡讲了精英（金色光环 / 掉落）")
	check(ob.text_of("focus", false).find("{cmd}") < 0, "集火文案里的键名占位已替换：" + ob.text_of("focus", false))
	ob._focus_t = -1.0
	ob.cur = "focus"
	ob._focus_given = false
	ob._skip_focus = false
	ob.focus_tries = ob.STEP_TRIES
	ob.focus_tgt = {"dead": true}
	g.squad.clear_order()
	ob._focus_tick()
	check(ob._skip_focus and ob._done("focus"), "精英重放用完：跳过这一步")
	# 7. 两卡不重叠：演示局 / 教程卡在时，tour 到点小提示不查，小字提示不计时也不画
	ob.cur = "focus"
	check(ob.busy(), "演示局 / 教程卡在：busy")
	var elite: Dictionary = g.spawner.new_enemy("mother", g.ppos + Vector2(120, 0))
	g.enemies.append(elite)
	Cfg.seen_tips.erase("elite")
	var gm0 = g.mode
	g.mode = g.Mode.PLAY   # tour 只在真人局查
	g.tour._poll = 1.0
	g.tour.update(0.6)
	g.mode = gm0
	check(Cfg.seen_tips.find("elite") < 0 and not ob.toast_active(), "教程卡在时 tour 不弹精英提示（11-07 集火卡与 TIP · ELITE 叠在一起）")
	ob.toast_q.append({"id": "x", "title": "测试", "text": "测试"})
	ob._toast_tick(1.0)
	check(ob.toast.is_empty(), "教程卡在时小字提示不轮到")
	ob.toast_q.clear()
	elite.dead = true
	# 8. 教过的正式局不弹、没教过的走小字提示（不出大卡）
	ob._shown = ["recruit", "deploy", "lamp", "beacon", "focus"]
	ob._mark_taught()
	for tid in ["elite", "mire", "lamp", "squad", "command", "levelup"]:
		check(ob._seen(tid), "演示局教过 → 正式局记成看过：" + tid)
	check(not ob.toast_tip("elite", "精英", "x"), "教过的精英：tour 转来的提示不弹")
	ob._finish()
	ob.cur = ""
	ob.out_id = ""
	ob._drill_off()
	ob.gap_t = 0.0
	g.state = Game.S.PLAY
	g.merchant = {"pos": g.ppos + Vector2(300, 0), "life": 60.0}
	check(not ob._seen("merchant"), "商人还没提示过")
	ob.update(0.016)
	check(ob.cur == "", "正式局碰到商人：不出大卡片")
	check(ob._seen("merchant") and (ob.toast_q.any(func(x): return x.id == "merchant") or str(ob.toast.get("id", "")) == "merchant"), "正式局碰到商人：排上小字提示")
	ob.update(0.016)
	check(str(ob.toast.get("id", "")) == "merchant", "小字提示显示出来：" + str(ob.toast))
	var vs: Vector2 = g.hud.size
	var tr: Rect2 = ob.toast_rect(vs)
	check(tr.has_area() and tr.size.y <= 60.0 and tr.size.x <= 470.0, "小字提示是一两行小条：" + str(tr))
	ob.skip_rect = Rect2()
	g.merchant = {}
	ob.update(ob.TOAST_SECS + 0.1)
	ob.update(0.016)
	check(ob.toast.is_empty(), "小字提示 %d 秒后自己收起" % int(ob.TOAST_SECS))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	check(not ob.input(click), "小字提示不拦输入")
	for tid in ["boss", "final", "duck", "merchant"]:
		check(ob.data.tips.has(tid) and ob.card(tid).has("title"), "没教过的提示有文案：" + tid)
	check(not ob.data.tips.has("nodes") and not ob.data.cards.has("nodes"), "节点卡不再弹首次介绍（11-09 用户）")
	# 4. 存档往返与旧档迁移
	var saved: bool = Cfg.onboard_done
	var cf := ConfigFile.new()
	cf.set_value("progress", "onboard_seen", ["drill", "lamp"])
	Cfg.onboard_done = false
	Cfg._read_cfg(cf)
	check(Cfg.onboard_done, "旧档：走完过旧演示局的算完成")
	var fresh := ConfigFile.new()
	fresh.set_value("progress", "onboard_seen", ["lamp"])
	Cfg._read_cfg(fresh)
	check(not Cfg.onboard_done, "旧档：没走完演示局的仍要强制一次")
	var explicit := ConfigFile.new()
	explicit.set_value("progress", "onboard_done", true)
	Cfg._read_cfg(explicit)
	check(Cfg.onboard_done, "onboard_done 读入")
	# 5. 云存档：取或，旧正文不补
	var a := {"set": {"t": 1, "d": {}}, "prog": {"onb": false}}
	var b := {"set": {"t": 2, "d": {}}, "prog": {"onb": true}}
	check(bool(CloudPack.merge(a, b).prog.get("onb", false)), "云端走完 + 本机没走完 → 走完")
	check(bool(CloudPack.merge(b, a).prog.get("onb", false)), "本机走完 + 云端没走完 → 走完（不被改回）")
	check(not CloudPack.merge({"set": {"t": 1, "d": {}}, "prog": {}}, {"set": {"t": 2, "d": {}}, "prog": {}}).prog.has("onb"), "旧正文没有 onb 不补")
	Cfg.onboard_done = true
	check(Cfg.cloud_body().prog.get("onb") == true, "cloud_body 带 onb")
	Cfg.onboard_done = true
	Cfg.cloud_apply({"set": {"t": 0, "d": {}}, "prog": {"onb": false}})
	check(Cfg.onboard_done, "cloud_apply 不把本机的完成改回去")
	Cfg.onboard_done = false
	Cfg.cloud_apply({"set": {"t": 0, "d": {}}, "prog": {"onb": true}})
	check(Cfg.onboard_done, "cloud_apply 读入云端的完成")
	# 6. 走完之后不再强制（真人局读 Cfg.onboard_done）
	var dev0: String = ob.dev
	ob.dev = ""
	Cfg.onboard_done = false
	check(ob._first_time(), "没有完成记录 → 强制")
	Cfg.onboard_done = true
	check(not ob._first_time(), "有完成记录 → 不强制")
	ob.dev = dev0
	Cfg.onboard_done = saved
	# 9. 结尾：「演示结束」模态框，不自动跳走；确认 / 点按钮才进正式局（测试里进正式局 = 退出，放最后）
	ob.drill = true
	ob.mode = "vet"
	ob.end_auto = false
	g.state = Game.S.PLAY
	ob.cur = ""
	ob._show("drill_end")
	check(ob.end_on and ob.modal() and g.state == Game.S.INTRO, "演示结束：弹模态框并暂停")
	for i in 20:
		ob.update(1.0)
	check(ob.end_on and ob.drill, "演示结束框不自动倒计时跳走（等 20 秒仍在）")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	check(ob.input(click) and ob.end_on, "点框外不算确认")
	ob.end_on = false
	g.state = Game.S.PLAY
	ob.drill_t0 = g.t - 9999.0
	ob.cur = "focus"
	ob.cur_t = ob.DRILL_STUCK + 1.0
	ob.update(0.016)
	check(ob.end_on, "总上限 + 卡住兜底：也出演示结束框")
	ob.end_t = 1.0
	ob.input(enter)
	check(not ob.end_on and not ob.drill and g.state == Game.S.PLAY, "按确认：进正式局")
	print("ONBOARD FORCED failures=", failures)
	get_tree().quit(1 if failures else 0)
