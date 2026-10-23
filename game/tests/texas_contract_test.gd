extends Node
## 新契约「只填 json」试点（docs/108 §9.1，德克萨斯）：帧条不变，只在 json 写 sprites.skills / extra_sprites。
##   godot --headless --path game res://tests/texas_contract_test.tscn -- --regression --balance --seed=1 --op=texas
## 校验：数据契约零错误；S1 / S2 单条与原来相同；S3 起手播 s3_start → 持续期站立播 idle、移动播 run → 结束播剑雨收势 → 回普通状态；
## 冲刺按进度换播（native_motion：普攻 attack 2–7、技能 s3_dash、回马剑等待 / 反冲 back_native）；
## S2 永久技能由生命周期默认绑定（后台、permanent）。全部通过时打印 "TEXAS CONTRACT failures=0"。

const Ch = preload("res://scripts/characters/character.gd")
const C = preload("res://scripts/characters/operator_contract.gd")
const DT := 1.0 / 60.0

var game: Node
var frames := 0
var n := 0
var fails := 0


func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _process(_d: float) -> void:
	frames += 1
	if frames != 5:
		return
	set_process(false)
	game.set_process(false)
	var d: Dictionary = Ch.load_def("texas")
	ok(Ch.validate_operator("texas", d) and C.errors(d).is_empty(), "德克萨斯 json 通过契约校验")
	var o = game.squad.get_op("texas")
	ok(o != null, "德克萨斯在编队里（--op=texas）")
	if o != null:
		test_s1(o)
		test_s3(o)
		test_s2(o)
		test_dash(o)
		test_leader_dash(o)
		test_triple(o)
	print("%d checks, %d failed" % [n, fails])
	print("TEXAS CONTRACT failures=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func ok(cond: bool, what: String) -> void:
	n += 1
	if not cond:
		fails += 1
		printerr("FAIL: ", what)


func kind(o) -> String:
	return str(o.anim_state().get("kind", ""))


## 推进 t 秒；vel ≠ 0 时每帧把目标往前挪（主控 follow 把 pos 设成目标，速度由位移算）
func step(o, t: float, vel := Vector2.ZERO) -> void:
	for i in int(round(t / DT)):
		o.follow(DT, o.pos + vel * DT)


func settle(o) -> void:
	o.s_t = [0.0, 0.0, 0.0]
	step(o, 1.0)


func test_s1(o) -> void:
	o.start_skill(Vector2.INF, 0)
	ok(o.sq_ph == 0 and o.act_anim == "skill", "S1 单条 anim = skill，不进序列")
	ok(absf(o.attack_t - 7.0 / 12.0) < 0.002 and absf(o.fire_t - 3.5 / 12.0) < 0.002, "S1 窗口 / 出手与原单条相同（7 帧 12fps，f3 中点）")
	settle(o)


func test_s3(o) -> void:
	o.start_skill(Vector2.INF, 2)
	ok(o.sq_ph == 1 and o.act_anim == "s3_start" and kind(o) == "s3_start", "S3 进序列起手段，播 s3_start（10-20 换 64 画布）")
	ok(absf(o.attack_t - 7.0 / 12.0) < 0.002 and absf(o.fire_t - 3.5 / 12.0) < 0.002, "S3 起手窗口与原单条相同")
	step(o, 0.7)
	ok(o.skill_active_left(2) > 0.0 and o.sq_ph == 2 and kind(o) == "idle", "S3 持续期站立：循环播 idle")
	step(o, 0.5, Vector2(240, 0))
	ok(o.sq_ph == 2 and kind(o) == "run", "S3 持续期移动：播 run")
	step(o, 0.5)
	o.s_t[2] = 0.0
	step(o, 0.05)
	ok(o.sq_ph == 3 and kind(o) == "skill", "S3 结束：收势播剑雨（skill 后 6 帧）")
	step(o, 0.6)
	ok(o.sq_ph == 0, "S3 收势播完，序列退出")
	ok(kind(o) in ["idle", "run"], "S3 结束回普通待机 / 跑步")


func test_s2(o) -> void:
	o.start_skill(Vector2.INF, 1)
	step(o, 1.0)
	var st: Array = o.skill_effect_status(1)
	ok(o.perm_on[1] and not st.is_empty() and st[0].unit == "permanent" and st[0].background, "S2 永久：生命周期默认绑定为后台 permanent")
	ok(not o.skills_occupied(), "S2 永久不占用技能通道")


## 冲刺换播（10-20，docs/108 §3.5）：伪造一次冲刺 / 回马剑等待，只看画面槽与帧，不推进玩法
## 专属冲刺（10-23 用户）：队长精零自己按冲刺，路径上的敌人受冲刺斩伤害；响应块 cond is_leader && elite < 1
func test_leader_dash(o) -> void:
	var g = game
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	var e1: Dictionary = g.spawner.spawn_enemy("stone", g.ppos + Vector2(70, 0))
	e1.hp = 100000.0
	e1.max_hp = e1.hp
	e1.spd = 0.0
	g.enemies_sys.build_grid()
	o.elite = 0
	o.refresh_stats()
	g.dash_dir = Vector2.RIGHT
	g.dash_t = 0.0
	o.update(DT)
	g.dash_t = 0.18
	var hp0: float = e1.hp
	for i in 20:
		g.ppos += Vector2.RIGHT * 7.0
		o.pos = g.ppos
		o.update(DT)
	ok(e1.hp < hp0, "专属冲刺：精零队长自己冲刺，路径上的敌人受伤（%.0f → %.0f）" % [hp0, e1.hp])
	e1.dead = true


## 疾刃三连（10-23，取代短剑气）：每第 3 次出手原地连斩三下（replace + no_combo + 两个 delay 的追加段）；没有敌人照常两连斩；
## 钉剑 / 余像挂在三连上——直接放三连第一下的 do，精一起命中第一名敌人停顿、精二起前方留下余像
func test_triple(o) -> void:
	var g = game
	for e in g.enemies: e.dead = true
	g.enemies.clear()
	o.s_t = [0.0, 0.0, 0.0]
	o.no_attack = false
	o.attack_t = 0.0
	o.fire_t = -1.0
	o.tx.erase("dash")
	o.pos = g.ppos
	o.elite = 0
	o.refresh_stats()
	g.enemies_sys.build_grid()
	ok(o._replace_trig(3).is_empty(), "疾刃三连：场上没有敌人 → 第 3 次出手照常两连斩（不 replace）")
	var e1: Dictionary = g.spawner.spawn_enemy("stone", g.ppos + Vector2(90, 0))
	e1.hp = 100000.0
	e1.max_hp = e1.hp
	e1.spd = 0.0
	g.enemies_sys.build_grid()
	ok(not o._replace_trig(3).is_empty() and bool(o._replace_trig(3).no_combo), "疾刃三连：普攻范围内有敌人 → 第 3 次出手 replace（no_combo）")
	ok(o._replace_trig(1).is_empty() and o._replace_trig(2).is_empty() and o._replace_trig(4).is_empty() and not o._replace_trig(6).is_empty(), "疾刃三连：只在第 3 / 6 … 次出手")
	var tri_do: Array = o.B.trait[1].do
	for el in [0, 1, 2]:
		o.elite = el
		o.refresh_stats()
		e1.stun = 0.0
		e1.hp = e1.max_hp
		o.pos = g.ppos
		o.tx["trails"] = []
		o._exec_list(tri_do)
		var max_stun := float(e1.get("stun", 0.0))
		var trails: int = o.tx.get("trails", []).size()
		ok((max_stun > 0.0) == (el >= 1), "钉剑：精英 %d 疾刃三连第一下命中 → %s（眩晕 %.2f）" % [el, "停顿" if el >= 1 else "不停顿", max_stun])
		ok((trails > 0) == (el >= 2), "余像：精英 %d 疾刃三连出手 → %s（残像 %d 道）" % [el, "留残像" if el >= 2 else "没有残像", trails])
	# 三下：追加段 delay 0.125 / 0.25 各一次，入排队列
	o.elite = 0
	o.refresh_stats()
	o.pending.clear()
	var before: float = float(e1.max_hp) - float(e1.hp)
	o.atk_n = 2
	o.cd = 0.0
	o._release()
	ok(o.atk_n == 3 and o.pending.size() == 2 and absf(float(o.pending[0].t) - 0.125) < 0.0001 and absf(float(o.pending[1].t) - 0.25) < 0.0001, "疾刃三连：第 3 次出手排了两个追加斩（0.125 / 0.25 秒），没有接第二斩的 combo（排队 %d 个）" % o.pending.size())
	e1.dead = true


func test_dash(o) -> void:
	var tags := {"basic": ["basic"], "skill": ["skill"], "reverse": ["follow_up"]}
	var want := {"basic": ["attack", 2, 7], "skill": ["s3_dash", 0, 7], "reverse": ["back_native", 3, 7]}
	for k in tags:
		var b := {"aim": "reverse" if k == "reverse" else "nearest", "tags": tags[k]}
		for t in [0.0, 0.43]:
			o.tx["dash"] = {"b": b, "t": t, "dur": 0.24, "hold": 0.2}
			var st: Dictionary = o.anim_state()
			var w: Array = want[k]
			var fr: int = int(w[1]) if t == 0.0 else int(w[2])
			ok(str(st.get("kind", "")) == w[0] and int(st.get("frame", -1)) == fr, "冲刺 %s 进度 %.2f：播 %s 第 %d 帧（实得 %s %d）" % [k, t, w[0], fr, st.get("kind", ""), st.get("frame", -1)])
		o.tx.erase("dash")
	o.tx["queue"] = [{"t": 0.3, "t0": 0.3, "do": [{"_tag": "shape.dash_line", "aim": "reverse"}], "ctx": {}}]
	var sw: Dictionary = o.anim_state()
	ok(str(sw.get("kind", "")) == "back_native" and int(sw.get("frame", -1)) == 0, "回马剑等待开始：back_native 第 0 帧")
	o.tx["queue"] = []
