extends Node
## 新手引导强制部分（docs/219 §6，check.py 场景回归 onboard_forced；参数 --onboard=ask 走第一次进游戏的强制版，不读不写存档）。
## 1. 第一次进游戏：问题框只有「玩过 / 没玩过」、Esc 不选、skip_all 不生效；2. 两条线的演示局步骤：都含招募 / 连携 / 终结技 / 指挥圆盘，按顺序出；
## 3. 「连携」一步：充满队长技力 + 身边放怪，到点还没放技能就直接触发；3b. 指挥两步：部署以指令生效 + 队友到位为准、随行以部署撤销为准；4. 存档：onboard_done 往返，旧档走完过旧演示局的算完成；
## 5. 云存档：prog.onb 取或、旧正文没有就不补；cloud_apply 不把本机的完成改回去；6. 走完之后不再强制（_first_time 读 Cfg.onboard_done）。
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
		for need in ["recruit", "link", "ult", "deploy", "regroup", "beacon", "focus"]:
			check(lst.has(need), "%s 缺 %s" % [key, need])
		check(lst.back() == "drill_end", key + " 以演示结束收尾")
	check(ob.data.get("drill", []).has("move") and not ob.data.get("drill_vet", []).has("move"), "没玩过才教移动 / 升级")
	check(ob.drill_ids() == ["recruit", "link", "ult", "deploy", "regroup", "beacon", "focus"], "快速线步骤：" + str(ob.drill_ids()))
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
	check(not ob._deployed(), "部署到怪群反方向不算")
	g.squad.apply_order("point", g.ppos + ob.pack_dir * 260.0, null)
	check(not ob._deployed(), "下了部署但队友还没走到不算")
	for o in g.squad.ops:
		if not o.is_leader:
			o.pos = g.squad.station_of(o)
	check(ob._deployed(), "队友走到驻扎位：部署生效")
	ob._finish()
	ob.cur = ""
	ob._show("regroup")
	check(not ob._done("regroup"), "随行一步：还没下令不算")
	g.wheel.open()
	g.wheel.confirm(g.wheel.item_index("guard"))
	check(g.squad.order_kind == "" and g.squad.stance != g.squad.ROAM and ob._done("regroup"), "选随行：部署撤销、回到随行")
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
	check(ob._done("focus") and (g.squad.order_kind == "focus" or ob._skip_focus), "等太久没下：引导代下一次集火并算做完")
	check(ob.text_of("focus", false).find("{cmd}") < 0, "集火文案里的键名占位已替换：" + ob.text_of("focus", false))
	ob.cur = "focus"
	ob._focus_given = false
	ob._skip_focus = false
	ob.focus_tries = ob.STEP_TRIES
	ob.focus_tgt = {"dead": true}
	g.squad.clear_order()
	ob._focus_tick()
	check(ob._skip_focus and ob._done("focus"), "精英重放用完：跳过这一步")
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
	print("ONBOARD FORCED failures=", failures)
	get_tree().quit(1 if failures else 0)
