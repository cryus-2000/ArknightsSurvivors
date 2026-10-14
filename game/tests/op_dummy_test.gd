extends Node
## 干员木桩表（docs/79，制作人 10-12）：理论预算层，单名干员在受控场地里打 60 秒，记秒伤 / 治疗 / 护盾 / 击杀与运行时基础属性。
## 由 tools/op_dummy_table.py 批量调起（全部 --headless），也可手动跑：
##   godot --headless --path game res://tests/op_dummy_test.tscn -- --balance --bot=afk --nodeath --seed=1 --op=<主控> [--squad=<被测>]
##         --dummy_op=<被测> --dummy_role=leader|mate --dummy_scene=single|horde --dummy_stage=0|1|2 [--dummy_secs=60 --dummy_warm=20]
## 场地：g.sandbox = true（不刷怪、不走事件 / 围猎 / 灯标 / 商人 / 拾取，game.gd），主控站桩（--bot=afk）。
##   single：主控右侧 50 像素一只不动、不攻击、打不死的木桩（骨海漂流体外形，生命恒满）。
##   horde ：主控周围 180–240 像素持续补满 HORDE_N 只普通近战怪（固定种类轮换、固定生命 HORDE_HP、照常移动与攻击）。
##           怪物密度 enemy/density = k（docs/50 §16）时补满 round(HORDE_N × k) 只、每只 HORDE_HP / k（总血量池不变）；怪物体型 enemy/scale 时判定半径同乘。缺省 1 = 原样
## 每帧：主控生命压在 60%（治疗全部有效）、灯火 100、不升级不开箱；基准主控（队友身份时）技力压 0、不放技能；
##   被测干员的手动技能就绪即放（机器人缺省是保命型时机，这里取上限）。
## 先热身 dummy_warm 秒（技力从 0 开始充），再统计 dummy_secs 秒。结束打印一行 DUMMY {json}。
## --dummy_check：自检（快检用）：被测干员秒伤 > 0、没有异常，打印 OP DUMMY failures=N。

const HORDE_N := 30
const HORDE_HP := 400.0
const Bal = preload("res://scripts/core/balance.gd")
const HORDE_TYPES := ["bone", "slider", "runner", "offspring"]
const DUMMY_DX := 50.0
const HP_PIN := 0.6
const STAGE_PROG := [0, 3, 6]   # 成长线统一为 节点 节点 精一 节点 节点 精二：E0 = 0 个节点，E1 = 到精一为止，E2 = 全线

var game: Node
var frames := 0
var op_id := ""
var role := "leader"
var scene := "single"
var stage := 0
var secs := 60.0
var warm := 20.0
var check := false

var op = null          # 被测干员
var others: Array = [] # 编队里其余干员（队友身份时 = 基准主控）
var dummy: Dictionary = {}
var anchor := Vector2.ZERO
var hrng := RandomNumberGenerator.new()
var horde_k := 0

var measuring := false
var done := false
var t0 := 0.0
var out0: Dictionary = {}
var heal0: Dictionary = {}
var kills0 := 0
var opk0 := 0
var casts0 := 0
var core_prev := 0.0
var core_frames := 0
var shield_prev := 0.0
var shield_gain := 0.0
var layer_prev := 0
var layer_gain := 0
var manual_n := 0
var alive_sum := 0.0
var alive_n := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dummy_op="):
			op_id = a.substr(11)
		elif a.begins_with("--dummy_role="):
			role = a.substr(13)
		elif a.begins_with("--dummy_scene="):
			scene = a.substr(14)
		elif a.begins_with("--dummy_stage="):
			stage = clampi(int(a.substr(14)), 0, 2)
		elif a.begins_with("--dummy_secs="):
			secs = float(a.substr(13))
		elif a.begins_with("--dummy_warm="):
			warm = float(a.substr(13))
		elif a == "--dummy_check":
			check = true
	hrng.seed = 20261012
	game = load("res://game.tscn").instantiate()
	add_child(game)
	game.sandbox = true


func _process(_d: float) -> void:
	frames += 1
	if done:
		return
	if frames == 2:
		_setup()
	if op == null:
		return
	_pin()
	if scene == "single":
		_hold_dummy()
	else:
		_refill()
	if game.state != game.S.PLAY:
		return
	# 手动技能就绪即放（只有主控有手动技能）
	var mi: int = op.manual_index()
	if mi >= 0 and op.manual_ready(mi):
		if op.cast_manual(mi):
			manual_n += 1
	if not measuring and game.t >= warm:
		_begin()
	elif measuring:
		_sample()
		if game.t >= t0 + secs:
			_finish()


func _setup() -> void:
	for o in game.squad.ops:
		if o.id == op_id:
			op = o
		else:
			others.append(o)
	if op == null:
		print("DUMMY_ERR 被测干员不在编队里：%s（编队 %s）" % [op_id, str(game.squad.ops.map(func(o): return o.id))])
		if check:
			print("OP DUMMY failures=1")
		done = true
		get_tree().quit()
		return
	# 推进到目标精英阶段（全队同阶段；精英化节点有选项时取第一个，同图鉴演出）
	for o in game.squad.ops:
		var guard := 0
		while o.prog < STAGE_PROG[stage] and not o.next_node().is_empty() and guard < 12:
			guard += 1
			var n: Dictionary = o.next_node()
			var chs: Dictionary = o.elite_choices(n) if n.get("type", "") == "elite" else {}
			o.advance(chs.keys()[0] if not chs.is_empty() else "")
		for i in 3:
			if not o.perm[i]:
				o.sp[i] = 0.0   # 精英化当下会把新技能充满：统一从 0 开始充
	game.show_queue.clear()
	game.sync_stats()
	game.hp = game.max_hp * HP_PIN
	anchor = game.ppos
	if scene == "single":
		dummy = game.spawner.spawn_enemy("bone", anchor + Vector2(DUMMY_DX, 0))
		dummy.xp = 0.0
	else:
		_refill()


## 每帧压住的状态：生命 60%、灯火满、不升级 / 不开箱、掉落清空；基准主控不放技能
func _pin() -> void:
	game.hp = game.max_hp * HP_PIN
	game.lamp = 100.0
	game.xp = 0.0
	game.pending_levelups = 0
	game.pending_chests = 0
	game.gems.clear()
	for o in others:
		for i in 3:
			if not o.perm[i]:
				o.sp[i] = 0.0


func _hold_dummy() -> void:
	if dummy.is_empty():
		return
	dummy.dead = false
	dummy.maxhp = 1.0e9
	dummy.hp = 1.0e9
	dummy.spd = 0.0
	dummy.dmg = 0.0
	dummy.kb = Vector2.ZERO
	dummy.pos = anchor + Vector2(DUMMY_DX, 0)


func _refill() -> void:
	var alive := 0
	for e in game.enemies:
		if not e.dead and not e.chest and not e.get("friendly", false):
			alive += 1
	if measuring:
		alive_sum += alive   # 补怪前的在场数：接近 HORDE_N = 没打空；明显偏低 = 补怪速度成了上限
		alive_n += 1
	var dk: float = Bal.v("enemy/density", 1.0)
	var esc: float = Bal.v("enemy/scale", 1.0)
	var n_full: int = HORDE_N if dk == 1.0 else maxi(1, roundi(HORDE_N * dk))
	while alive < n_full:
		var ty: String = HORDE_TYPES[horde_k % HORDE_TYPES.size()]
		horde_k += 1
		var p: Vector2 = game.ppos + Vector2.from_angle(hrng.randf() * TAU) * hrng.randf_range(180.0, 240.0)
		var e: Dictionary = game.spawner.spawn_enemy(ty, p)
		var hpm: float = pow(1.0 / dk, Bal.v("enemy/density_hp_exp", 1.0))   # 同 spawner._dens_apply：单只生命 × (1/k)^density_hp_exp
		e.hp = HORDE_HP * hpm
		e.maxhp = HORDE_HP * hpm
		if dk != 1.0:
			e["dk"] = 1.0 / dk   # 击杀权重同 spawner（按击杀次数的积木补偿，docs/50 §16.8）
		if esc != 1.0:
			e.r *= esc
			e["sc"] = esc
		e.xp = 0.0
		alive += 1


## 怪群在场个体的已承伤合计（maxhp − hp），与击杀数一起做自检的「打中了」判定
func _horde_taken() -> float:
	var s := 0.0
	for e in game.enemies:
		if not e.dead and not e.chest and not e.get("friendly", false):
			s += maxf(0.0, float(e.maxhp) - float(e.hp))
	return s


func _op_out() -> Dictionary:
	return (game.telemetry.op_out.get(op.id, {}) as Dictionary).duplicate()


func _cat(src: String) -> String:
	var hs: Dictionary = game.hit_src.get(src, {})
	if str(hs.get("emitter", "")) == "summon":
		return "summon"
	match str(hs.get("origin", "")):
		"core":
			return "basic"
		"skill":
			return "skill"
	return "other"


func _core_now() -> float:
	var s := 0.0
	var d: Dictionary = game.telemetry.op_out.get(op.id, {})
	for k in d:
		if _cat(k) == "basic":
			s += float(d[k])
	return s


func _shield_now() -> float:
	var sm = op.get("sm")
	if sm is Dictionary and sm.has("shield"):
		return float(sm.shield)
	return 0.0


func _begin() -> void:
	measuring = true
	t0 = game.t
	out0 = _op_out()
	heal0 = game.heal_log.duplicate()
	kills0 = game.kills
	opk0 = int(game.telemetry.op_kills.get(op.id, 0))
	casts0 = int(game.telemetry.op_casts.get(op.id, 0))
	core_prev = _core_now()
	shield_prev = _shield_now()
	layer_prev = game.shield


func _sample() -> void:
	var c := _core_now()
	if c > core_prev + 0.001:
		core_frames += 1
	core_prev = c
	var s := _shield_now()
	if s > shield_prev:
		shield_gain += s - shield_prev
	shield_prev = s
	if game.shield > layer_prev:
		layer_gain += game.shield - layer_prev
	layer_prev = game.shield


func _finish() -> void:
	done = true
	var dur: float = maxf(0.001, game.t - t0)
	var o1 := _op_out()
	var by_src := {}
	var by_cat := {"basic": 0.0, "skill": 0.0, "summon": 0.0, "other": 0.0}
	var tot := 0.0
	for k in o1:
		var v: float = float(o1[k]) - float(out0.get(k, 0.0))
		if v <= 0.0:
			continue
		by_src[k] = snappedf(v, 0.1)
		by_cat[_cat(k)] += v
		tot += v
	# 治疗：除「自身回复」（主控回复属性）与基准主控名下的来源外都算被测干员的（场上没有藏品 / 无人机 / 拾取）
	var excl := {"自身回复": true}
	for o in others:
		excl[o.display_name()] = true
	var heal_src := {}
	var heal := 0.0
	for k in game.heal_log:
		var hv: float = float(game.heal_log[k]) - float(heal0.get(k, 0.0))
		if hv <= 0.0:
			continue
		heal_src[k] = snappedf(hv, 0.1)
		if not excl.has(k):
			heal += hv
	var sk_need: Array = []
	for i in 3:
		sk_need.append(op.sp_need(i))
	var rec := {
		"op": op.id, "name": op.display_name(), "cls": op.cls, "role": role, "scene": scene, "stage": stage,
		"elite": op.elite, "prog": op.prog, "secs": snappedf(dur, 0.01), "warm": warm,
		"leader": game.squad.leader().id, "squad": game.squad.ops.map(func(o): return o.id),
		"dps": snappedf(tot / dur, 0.01),
		"dps_basic": snappedf(by_cat.basic / dur, 0.01), "dps_skill": snappedf(by_cat.skill / dur, 0.01),
		"dps_summon": snappedf(by_cat.summon / dur, 0.01), "dps_other": snappedf(by_cat.other / dur, 0.01),
		"by_src": by_src,
		"hps": snappedf(heal / dur, 0.01), "heal_src": heal_src,
		"shield_ps": snappedf(shield_gain / dur, 0.01), "shield_layers": layer_gain,
		"kills": game.kills - kills0, "op_kills": int(game.telemetry.op_kills.get(op.id, 0)) - opk0,
		"casts": int(game.telemetry.op_casts.get(op.id, 0)) - casts0, "manual_casts": manual_n,
		"basic_hit_frames": core_frames, "horde_alive": snappedf(alive_sum / float(alive_n), 0.1) if alive_n > 0 else -1.0,
		"basic_interval": snappedf(dur / float(core_frames), 0.001) if core_frames > 0 else -1.0,
		# 运行时属性（被测干员作用域）
		"op_atk": snappedf(op.stat(&"op_atk"), 0.0001), "op_aspd": snappedf(op.stat(&"op_aspd"), 0.0001),
		"op_range": snappedf(op.stat(&"op_range"), 0.0001), "skill_power": snappedf(op.skill_power(), 0.0001),
		"sp_need": sk_need, "sp_mult": snappedf(float(game.sp_mult), 0.0001),
		# 主控（博士）层属性：主控身份时就是被测干员的 leader 段 + 博士基础；队友身份时是基准主控的
		"max_hp": snappedf(game.max_hp, 0.1), "armor": snappedf(game.armor, 0.0001), "arts_res": snappedf(game.arts_res, 0.0001),
		"regen": snappedf(game.regen + game.regen_pct * game.max_hp, 0.001), "speed": snappedf(game.speed, 0.1), "dodge": snappedf(game.dodge, 0.0001),
	}
	print("DUMMY ", JSON.stringify(rec))
	if check:
		var fails := 0
		if tot <= 0.0:
			fails += 1
			print("FAIL 被测干员 %s 统计期内没有伤害" % op.id)
		if scene == "horde" and game.kills - kills0 <= 0 and _horde_taken() <= 0.0:
			fails += 1
			print("FAIL 怪群场景没有击杀也没有承伤")   # 怪物密度 k < 1 时每只 HORDE_HP / k 血，几秒自检未必打死一只：总承伤 > 0 即算打中
		print("OP DUMMY failures=%d" % fails)
	get_tree().quit()
