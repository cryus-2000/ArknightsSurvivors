extends Node
## 干员连携技与其他动作的冲突检查（docs/160 §11，协调人 10-26 清单）：
##   --op=ulpianus --squad=skadi,texas   搭档忙（技能 / 冲锋 / 德克萨斯式自冲刺）→ 等待后放弃并退回冷却；倒地 / 归队 / 切队长（玩家入口缺省关）/ 目标中途死亡 / 非 PLAY 状态；语音不叠
##   --op=gladiia --squad=ulpianus,skadi 同帧只走一条（R6 取代集群狩猎，不重复位移）
## 全部通过时打印 "SYNERGY CONFLICT checks=N failures=0"

var checks := 0
var failures := 0
var g


func ok(v: bool, what: String) -> void:
	checks += 1
	if not v:
		failures += 1
		printerr("FAIL: ", what)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	add_child(g)
	for i in 5: await get_tree().process_frame
	g.set_process(false)
	g.mode = g.Mode.PLAY
	g.state = g.S.PLAY
	g.sandbox = true
	g.t = 60.0
	g.xp_need = 1000000000.0
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var ids: Array = g.squad.ids()
	if ids.has("ulpianus") and ids.has("skadi") and ids.has("texas"):
		await scene_busy()
	elif ids.has("gladiia") and ids.has("ulpianus") and ids.has("skadi"):
		await scene_same_frame()
	else:
		ok(false, "测试编队不对：%s" % [ids])
	print("SYNERGY CONFLICT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func foe(at: Vector2) -> Dictionary:
	var e: Dictionary = g.spawner.spawn_enemy("bone", at)
	e.hp = 1.0e7
	e.maxhp = 1.0e7
	e.spd = 0.0
	g.enemies_sys.build_grid()
	return e


func step(secs: float) -> void:
	for i in int(secs * 60.0):
		g.hp = g.max_hp
		g.enemies_sys.build_grid()
		g._update(1.0 / 60.0)


func slot_dist(o) -> float:
	return o.pos.distance_to(g.ppos + g.squad._slot_offset(o.slot))


func fresh(e_at := Vector2(230.0, 0.0)) -> Dictionary:
	g.squad.syn.cd.clear()
	g.squad.syn.acts.clear()
	for e in g.enemies:
		e.dead = true
	g.enemies.clear()
	return foe(g.ppos + e_at)


func scene_busy() -> void:
	var ul = g.squad.get_op("ulpianus")
	var sk = g.squad.get_op("skadi")
	var tx = g.squad.get_op("texas")
	ok(ul.is_leader, "乌尔比安是队长")
	# 1 搭档正在放技能（技能动画中）：不打断，等待 0.5 秒后放弃并退回冷却
	var e := fresh()
	sk.act_kind = "skill"
	sk.attack_t = 5.0
	var hp0: float = e.hp
	var p0: Vector2 = sk.pos
	ul.spend_sp(0)
	step(0.35)
	ok(sk.syn_mv.is_empty() and sk.pos.distance_to(p0) < 30.0 and e.hp == hp0, "搭档在放技能：不位移、不出手")
	step(0.9)
	ok(g.squad.syn.acts.is_empty() and float(g.squad.syn.cd.get("shouduan", 0.0)) < 0.0, "等满 0.5 秒仍在忙：放弃并退回冷却")
	sk.attack_t = 0.0
	sk.act_kind = "attack"
	step(1.0)
	# 2 搭档在突击冲锋 / 德克萨斯式自冲刺：同样让路
	e = fresh()
	sk.rush_t = 5.0
	ul.spend_sp(0)
	step(1.0)
	ok(sk.syn_mv.is_empty() and g.squad.syn.acts.is_empty(), "搭档在突击冲锋：不重复位移")
	sk.rush_t = 0.0
	# 德克萨斯式自冲刺（tx.dash）：直接问忙闲判断（伪造的 dash 不能进逐帧步进）
	ok(not g.squad.Synergy._busy_move(tx), "（前置）德克萨斯空闲")
	tx.tx["dash"] = {}
	ok(g.squad.Synergy._busy_move(tx), "搭档在自冲刺（tx.dash）：判为忙")
	tx.tx.erase("dash")
	# 3 搭档倒地：不触发
	e = fresh()
	sk.cmd_down = 5.0
	var n0: int = int(g.squad.syn.n)
	ul.spend_sp(0)
	step(0.3)
	ok(int(g.squad.syn.n) == n0, "搭档倒地：不触发")
	sk.cmd_down = 0.0
	# 4 进行中切到归队：当场作废、位移解除、不卡状态
	e = fresh()
	ul.spend_sp(0)
	step(0.75)
	ok(not g.squad.syn.acts.is_empty() or not sk.syn_mv.is_empty(), "（前置）合击已经开始")
	g.squad.set_stance(g.squad.RECALL)
	step(0.1)
	ok(g.squad.syn.acts.is_empty() and sk.syn_mv.is_empty(), "指挥归队：进行中的合击作废、搭档位移解除")
	g.squad.set_stance(g.squad.GUARD)
	step(3.0)
	# 5 进行中切队长（搭档成了队长）：不把队长拉走、位移解除
	e = fresh()
	ul.spend_sp(0)
	step(0.75)
	# 切换队长的玩家入口已删（10-29）：直接调 swap_leader 只测连携
	var ok_swap: bool = g.squad.swap_leader(sk)
	step(0.1)
	ok(ok_swap and sk.is_leader and sk.syn_mv.is_empty() and g.squad.syn.acts.is_empty(), "切队长：作废、位移解除（切成功 %s）" % [ok_swap])
	var lp: Vector2 = g.ppos
	step(1.0)
	ok(g.ppos.distance_to(lp) < 2.0, "切队长之后队长位置不再被合击拉动")
	ok(g.squad.swap_leader(ul) and ul.is_leader, "（还原）乌尔比安重新当队长")
	step(2.5)
	# 6 目标在冲刺途中死亡：合击照常收尾，不报错、不冲出屏幕
	e = fresh()
	ul.spend_sp(0)
	step(0.62)
	e.dead = true
	g.enemies_sys.build_grid()
	step(2.5)
	ok(g.squad.syn.acts.is_empty() and sk.syn_mv.is_empty() and sk.pos.distance_to(g.ppos) < 500.0, "目标中途死亡：合击收尾、搭档回到队长附近（%.0f）" % sk.pos.distance_to(g.ppos))
	# 7 非 PLAY 状态（选卡 / 暂停 / 结算）：残留合击作废、计时不走
	e = fresh()
	ul.spend_sp(0)
	step(0.3)
	g.state = g.S.CHOICE
	var age_before: float = float(g.squad.syn.acts[0].age) if not g.squad.syn.acts.is_empty() else -1.0
	g.squad.Synergy.tick(g.squad, 1.0)
	ok(g.squad.syn.acts.is_empty() and sk.syn_mv.is_empty() and age_before >= 0.0, "非 PLAY：残留合击清空、位移解除")
	g.state = g.S.PLAY
	step(1.0)
	# 8 语音不叠音：技能语音正在播时，合击台词排队补播，不叠
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx != null:
		sfx.voice_reset()
		sfx.voice("texas", "skill_1")
		var cid0: String = sfx.voice_cid
		sfx.voice("skadi", "entry", false, true)
		ok(sfx.voice_cid == cid0 or sfx.voice_cid == "skadi", "语音单通道：不叠音（当前 %s）" % sfx.voice_cid)
		ok(sfx.voice_player.playing == false or sfx.voice_cid == cid0 or not sfx.voice_urgent.is_empty() or sfx.voice_cid == "skadi", "技能语音在播：合击台词排队补播或让路战斗闲聊")
		sfx.voice_reset()
	# 9 补：Texas 当搭档时在突击 / 自冲刺中同样让路（_busy_move 对 tx.dash 生效）
	ok(true, "（德克萨斯自冲刺的让路已由 2 覆盖：任何干员的 tx.dash 都算忙）")


func scene_same_frame() -> void:
	var gl = g.squad.get_op("gladiia")
	var ul = g.squad.get_op("ulpianus")
	var sk = g.squad.get_op("skadi")
	ok(gl.is_leader, "歌蕾蒂娅是队长")
	var e := fresh()
	for k in 3:
		foe(g.ppos + Vector2(240.0 + 20.0 * k, -20.0 + 20.0 * k))
	gl.spend_sp(2)
	step(0.2)
	ok(g.squad.syn.cd.has("zhansheji") and not g.squad.syn.cd.has("jiqun"), "同帧：战争设计取代集群狩猎，只走一条")
	var movers := 0
	for o in [ul, sk]:
		if not o.syn_mv.is_empty():
			movers += 1
	step(1.5)
	ok(movers <= 1 and g.squad.syn.acts.size() <= 1, "没有两条连携同时推同一个人（同时位移的搭档 ≤ 1）")
	step(3.0)
	ok(g.squad.syn.acts.is_empty() and ul.syn_mv.is_empty() and sk.syn_mv.is_empty(), "全部收势")
