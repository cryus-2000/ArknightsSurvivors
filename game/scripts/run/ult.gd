## 终结技 · 连携技 · 连携终结技 框架（docs/198 §2 / §3.3 / §7 / §10.2；原型 claude/ult-proto，10-29）
## 总开关 balance.json ult/on（缺省 1）：0 = 本模块完全不求值，旧的响应动作 / 隐藏连携 / 钩与锚 / 手动技能照旧（同 seed TRACE 与基线逐行相同）。
## 分工：本文件管能量、协同格、Q / E 输入、顿帧与慢动作、立绘切入、连携排队、自动档与机器人、按目标生命定的伤害预算、程序占位图形；
##   每人的终结技形态与连携终结技在 run/ult_moves.gd，20 人连携触发与动作在 run/combo.gd，HUD / 手机键在 screens/hud_ult.gd。
## 时间：所有阶段按游戏时间走（批跑可复现）；慢动作只在玩家局 / --realtime / --playclock 缩放真实步长（time_scale），顿帧走 vfx.stop，
## 机器人批跑里两者都不生效、阶段长度照旧，不碰随机数。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Moves = preload("res://scripts/run/ult_moves.gd")
const Combo = preload("res://scripts/run/combo.gd")
const Link = preload("res://scripts/run/skill_link.gd")   # 技能连携（combo/skill_link，10-30 起缺省开）
const UM = preload("res://scripts/ui_motion.gd")
const A = preload("res://scripts/art.gd")

var CELLS := 7                # 协同格数（balance ult/cells，_init 读；HUD 读 u.CELLS）
const FULL := 100.0
const VIEW := Vector2(1524.0, 857.0)   # 桌面参考视野（docs/198 §3.1）：机器人「屏内」口径、连携终结技「全屏」口径

var g

# ---- 能量与协同（§2.1 / §2.2）
var energy := 0.0
var cells := 0
var _cell_t := -999.0       # 上一格协同的时刻（每格最短 ult/cell_gap 秒）
var _combo_e_t := -999.0    # 上一次连携计入能量的时刻（每 ult/e_combo_gap 秒至多 1 次）
var _sec := -1
var _sec_gain := 0.0        # 本秒已获取（每秒总上限 ult/e_sec_cap）
var _hurt_t0 := -999.0
var _hurt_gain := 0.0       # 受伤来源本窗口已获取（每 10 秒至多 ult/e_hurt_cap）
var full_since := -1.0      # 能量满的时刻（机器人等连携终结技的 30 秒）

# ---- 进行中的终结技（phase：""、"aim" 瞄准慢动作、"cast" 出招中）
var phase := ""
var kind := ""              # "ult" | "cult"
var caster = null
var aim_kind := "none"      # "none" | "point" | "dir"（Moves.aim_kind）
var aim := Vector2.INF      # 选落点：落点
var aim_dir := Vector2.RIGHT
var _phase_t := 0.0
var _aim_min := 0.0
var _aim_max := 0.0
var act: Dictionary = {}    # Moves.start / start_cult 返回的动作状态
var serial := 0             # 第几次终结技（伤害预算按它分次记账：e.ult_s / e.ult_d）
var q_held := false
var last_hit_t := -1.0       # 终结技最后一次造成伤害的时刻（ult_bench 量时长）
var kills_now := 0          # 本次终结技已击杀数：超过 ult/fx_kill_cap（60，§7.4）后普通怪静默倒下（combat.quiet）
var tier := "ult"           # 当前伤害档：ult / cult（hit 读）

# ---- 连携（§2.5 / §5）
var cd := {}                # 干员 id → 冷却结束时刻
var queue: Array = []       # 亮起排队：{"o", "info", "t0", "left"}；只有队首倒计时
var combo_acts: Array = []  # Combo.fire 返回的动作，Combo.step 推进
var ev := {
	"dash_start_t": -99.0, "dash_dir": Vector2.RIGHT, "dash_from": Vector2.ZERO,
	"dash_end_t": -99.0, "dash_end_pos": Vector2.ZERO,
	"ult_t": -99.0,         # 队长上一次放终结技 / 连携终结技（出招那一刻）
	"cult_t": -99.0,
	"hits": [],             # 连携命中记录 [{"t", "pos", "op", "n", "gathered"}]（D 类读，最近 4 条）
	"melee_t": [],          # 队长被近战命中的时刻（最近 6 条）
	"big_t": -99.0, "big_src": {},   # 队长一次吃 ≥ 10% 最大生命的时刻与来源敌人
	"last_src": {},         # 最近一次打到队长的敌人
}
var _prev_dash := 0.0
var _filled := false
var _refill_t := 0.0
var _swarm_t := -1.0
var _skill_t := -1.0


## 录像用（缺省 ult/test_skill_at = -1 关）：到点起每 ult/test_skill_every（4）秒把队长第 ult/test_skill_idx 个技能充满，让技能（和技能连携样片）在录像窗口里放出来
func _test_skill() -> void:
	var at: float = Bal.v("ult/test_skill_at", -1.0)
	if at < 0.0 or g.t < at or (_skill_t >= 0.0 and g.t - _skill_t < Bal.v("ult/test_skill_every", 4.0)):
		return
	var ld = g.squad.leader()
	var i: int = Bal.vi("ult/test_skill_idx", 0)
	if ld == null or i < 0 or i >= ld.sp.size() or not ld.skill_unlocked(i):
		return
	_skill_t = g.t
	ld.sp[i] = ld.sp_need(i)


## 录像用（用户 10-29「怪物要多一点、聚集一点」；缺省 ult/test_swarm_at = -1 关，正常局 / 批跑不走）：到点在队长前方
## ult/test_swarm_d（300）处刷一团 ult/test_swarm_n（80）只普通怪（半径 ult/test_swarm_r 250，按序号排成葵花点阵、不抽随机数）
## + ult/test_swarm_elites（3）只精英；ult/test_swarm_every > 0 时之后每隔这么多秒再刷一团
func _test_swarm() -> void:
	var at: float = Bal.v("ult/test_swarm_at", -1.0)
	if at < 0.0 or g.t < at:
		return
	var every: float = Bal.v("ult/test_swarm_every", 0.0)
	if _swarm_t >= 0.0 and (every <= 0.0 or g.t - _swarm_t < every):
		return
	_swarm_t = g.t
	var ld = g.squad.leader()
	var c0: Vector2 = g.ppos + _default_dir(ld) * Bal.v("ult/test_swarm_d", 300.0) if ld != null else g.ppos + Vector2(300, 0)
	var n: int = int(Bal.v("ult/test_swarm_n", 80.0))
	var r: float = Bal.v("ult/test_swarm_r", 250.0)
	var types := ["fractal", "slider", "runner", "fractal", "bone"]
	for i in n:
		var p: Vector2 = c0 + Vector2.from_angle(i * 2.39996) * r * sqrt(float(i + 1) / n)
		g.spawner.spawn_enemy(types[i % types.size()], p)
	for i in int(Bal.v("ult/test_swarm_elites", 3.0)):
		var e: Dictionary = g.spawner.spawn_enemy("skimmer", c0 + Vector2.from_angle(i * TAU / 3.0 + 0.5) * r * 0.5)
		if not e.elite:
			e.elite = true
			e.hp *= Bal.v("enemy/elite_hp_mult", 7.0)
			e.maxhp = e.hp

# ---- 增益、画面
var _buffs: Array = []      # {"src", "until", "mods", "zc", "zr", "on"}：到点 g.stats.remove_source；zr > 0 时按队长在不在领域里开关
var shapes: Array = []      # 程序占位图形（draw_world 画），见 shape()
var cutins: Array = []      # 立绘切入条带（HUD 画）：{"id", "name", "col", "t0", "dur", "i"}；t0 / dur 按真实时间（UM.now）

# ---- 统计（批跑汇总 / ult_bench）
var stats := {"ult": 0, "cult": 0, "combo": 0, "combo_auto": 0, "combo_e": 0, "combo_up": 0, "lit": 0, "miss": 0,
	"first_full": -1.0, "ult_times": [], "cult_times": [], "lit_by": {}, "link_by": {}, "e_out": 0.0, "e_kill": 0.0, "e_hurt": 0.0, "e_combo": 0.0}


func _init(game) -> void:
	g = game
	CELLS = maxi(1, Bal.vi("ult/cells", 7))
	energy = clampf(Bal.v("ult/start_energy", 0.0), 0.0, FULL)   # 开局自带的能量（让首次约 2:30 而不加快之后的节奏）


static func on() -> bool:
	return Bal.vi("ult/on", 1) > 0


# ================================================================ 能量

## 「当前时刻普通怪基准最大生命」（§2.1 / §3.3）：按敌人生命时间倍率与难度倍率归一，后期不暴涨
func ref_hp() -> float:
	return Bal.v("ult/ref_hp", 20.0) * g.combat.enemy_hp_time_mult() * float(g.dmod.enemy_hp) * g.enemy_hp_mult


func _gain(v: float, src: String) -> void:
	if v <= 0.0 or energy >= FULL:
		return
	var s := int(g.t)
	if s != _sec:
		_sec = s
		_sec_gain = 0.0
	v = minf(v * Bal.v("ult/e_mult", 1.0), Bal.v("ult/e_sec_cap", 1.0) - _sec_gain)
	if v <= 0.0:
		return
	_sec_gain += v
	energy = minf(FULL, energy + v)
	stats["e_" + src] += v
	if energy >= FULL:
		full_since = g.t
		if stats.first_full < 0.0:
			stats.first_full = g.t


static func _ult_hit(h: Dictionary) -> bool:
	for tg in h.get("tags", []):
		if tg == "终结技":
			return true
	return false


## combat._damage：全队实际造成的伤害（终结技自己的不算）
func on_dmg(eff: float, h: Dictionary) -> void:
	if eff > 0.0 and energy < FULL and not _ult_hit(h):
		_gain(eff / maxf(1.0, ref_hp()) * Bal.v("ult/e_out", 0.06), "out")


## combat.kill：普通怪 / 精英 / Boss
func on_kill(e: Dictionary) -> void:
	if energy >= FULL or e.get("chest", false) or _ult_hit(g.hit):
		return
	_gain(Bal.v("ult/e_boss", 5.0) if e.boss else (Bal.v("ult/e_elite", 3.0) if e.elite else Bal.v("ult/e_kill", 0.1)), "kill")


## combat.lose_hp：每损失 1% 最大生命 +0.15，每 10 秒至多 +1.5
func on_lose(amount: float) -> void:
	if amount <= 0.0:
		return
	if g.t - _hurt_t0 >= 10.0:
		_hurt_t0 = g.t
		_hurt_gain = 0.0
	var v: float = minf(amount / maxf(1.0, g.max_hp) * 100.0 * Bal.v("ult/e_hurt", 0.15), Bal.v("ult/e_hurt_cap", 1.5) - _hurt_gain)
	if v > 0.0:
		_hurt_gain += v
		_gain(v, "hurt")


## combat.hurt（敌人打到队长，扣血之后）：连携 C 类的判定记录
func on_hurt(amount: float, src: Dictionary) -> void:
	if not src.is_empty():
		ev.last_src = src
	if str(g.in_type[0]) == "近战":
		var mt: Array = ev.melee_t
		mt.append(g.t)
		if mt.size() > 6:
			mt.pop_front()
	if amount >= 0.1 * g.max_hp:
		ev.big_t = g.t
		ev.big_src = src if not src.is_empty() else ev.last_src


## 连携命中（combo.gd 在第一下命中时调）：能量 +2（每 12 秒至多 1 次）、协同 +1 格（每 40 秒至多 1 格）；记进 ev.hits 给 D 类
func combo_landed(o, pos: Vector2, n_hit: int, gathered := 0) -> void:
	_combo_hit_fx(o, pos)
	var hs: Array = ev.hits
	hs.append({"t": g.t, "pos": pos, "op": str(o.id), "n": n_hit, "gathered": gathered})
	if hs.size() > 4:
		hs.pop_front()
	if g.t - _combo_e_t >= Bal.v("ult/e_combo_gap", 12.0):
		_combo_e_t = g.t
		_gain(Bal.v("ult/e_combo", 2.0), "combo")
	if cells < CELLS and g.t - _cell_t >= Bal.v("ult/cell_gap", 40.0):
		_cell_t = g.t
		cells += 1


func full() -> bool:
	return energy >= FULL


func can_cult() -> bool:
	return energy >= FULL and cells >= CELLS


# ================================================================ 每帧

## squad.update 开头调（在干员 follow 之前，连携位移 syn_mv 当帧生效；取代 Synergy.tick）
func tick(dt: float) -> void:
	if g.state == g.S.PAUSE:
		return   # 暂停菜单：终结技原样冻住，回来接着播（原来走 _clear 会把正在放的终结技直接掐掉）
	if g.state != g.S.PLAY:
		_clear()
		return
	_events()
	_test_swarm()
	_test_skill()
	if not _filled and g.t >= Bal.v("ult/test_fill_at", -1.0) and Bal.v("ult/test_fill_at", -1.0) >= 0.0:
		_filled = true   # 测试 / 录像用（缺省 -1 = 关）：到点直接充满能量，协同给 ult/test_cells 格
		energy = FULL
		full_since = g.t
		cells = mini(CELLS, Bal.vi("ult/test_cells", 0))
		_refill_t = g.t
	var fe: float = Bal.v("ult/test_fill_every", -1.0)   # 录像用（缺省 -1 = 关）：充满之后每 fe 秒再充满一次，连放几次看特效变体
	if _filled and fe > 0.0 and phase == "" and energy < FULL and g.t - _refill_t >= fe:
		_refill_t = g.t
		energy = FULL
		full_since = g.t
	_tick_buffs()
	_tick_shapes(dt)
	Moves.tick_bg(self)   # 终结技的延后部分（凯尔希 Mon3tr 8 秒后重构）
	if phase != "":
		_tick_ult(dt)
	if playing() and Bal.vi("ult/play_invuln", 1) > 0:
		g.invuln = maxf(g.invuln, 0.1)   # 播放期间队长不能走也不能冲刺：无敌，不闪烁（同技能位移的无敌）
		g.invuln_move_until = maxf(g.invuln_move_until, g.t + 0.1)
	_tick_combo(dt)
	if phase == "" and energy >= FULL and _auto_ult():
		_auto_cast()


## 播放形式（用户 10-31）：按下 Q 起到这一招演出结束（瞄准 + 出招两段），队长不吃移动输入、不冲刺、不位移，
## 要突进的招式自己写 g.ppos（ult_moves._ul_step / ult_moves_c._lead_move）；移动输入只用来挪落点 / 转方向。
## 这段时间里升级 / 宝箱三选一、路口发牌、精英化演出都排队（game.check_pending、endings.update），播完按原顺序依次弹。
## ult/playback 0 = 恢复旧行为（放终结技时照常走路）；ult/play_max 是兜底上限（游戏秒），哪一招收尾没报完成也不会一直锁着
var _play_t0 := -99.0


func playing() -> bool:
	return phase != "" and Bal.vi("ult/playback", 1) > 0 and g.t - _play_t0 < Bal.v("ult/play_max", 6.0)


func _clear() -> void:
	for a in combo_acts:
		if a.get("p") != null:
			a.p.syn_mv = {}
	combo_acts.clear()
	queue.clear()
	if phase != "":
		phase = ""
		act = {}


func _events() -> void:
	if g.dash_t > 0.0 and _prev_dash <= 0.0:
		ev.dash_start_t = g.t
		ev.dash_dir = g.dash_dir
		ev.dash_from = g.ppos
	elif g.dash_t <= 0.0 and _prev_dash > 0.0:
		ev.dash_end_t = g.t
		ev.dash_end_pos = g.ppos
	_prev_dash = g.dash_t


# ================================================================ 终结技：输入、阶段

## Q（手柄 RB / Ⓐ、手机终结技键按下）：能量满就进入顿帧 + 慢动作瞄准；松开（release_q）或时间到放出
func press_q() -> bool:
	if phase != "" or energy < FULL:
		return false
	var ld = g.squad.leader() if g.squad != null else null
	if ld == null or ld.pos == Vector2.INF or ld.cmd_down > 0.0:
		return false
	q_held = true
	_begin(ld, "cult" if cells >= CELLS else "ult")
	return true


func release_q() -> void:
	q_held = false


func _begin(ld, k: String) -> void:
	kind = k
	tier = k
	caster = ld
	serial += 1
	kills_now = 0
	energy = 0.0
	full_since = -1.0
	if k == "cult":
		cells = 0
		_cell_t = g.t   # 清零后重新计 40 秒
		stats.cult += 1
		stats.cult_times.append(snappedf(g.t, 0.1))
	else:
		stats.ult += 1
		stats.ult_times.append(snappedf(g.t, 0.1))
	aim_kind = "dir" if k == "cult" else Moves.aim_kind(str(ld.id))
	aim_dir = _default_dir(ld)
	aim = _default_point(ld)
	_phase_t = 0.0
	_play_t0 = g.t
	if Bal.vi("ult/playback", 1) > 0:
		g.dash_t = 0.0   # 冲刺到一半按 Q：冲刺就此停住，原地起手
		if Bal.vi("ult/play_invuln", 1) > 0:
			g.invuln = maxf(g.invuln, 0.1)   # 起手这一帧就无敌（tick 里每帧续上）
			g.invuln_move_until = maxf(g.invuln_move_until, g.t + 0.1)
	var slow: float = Bal.v("ult/cult_slow_t" if k == "cult" else "ult/slow_t", 0.8 if k == "cult" else 0.5)
	var sc: float = Bal.v("ult/cult_slow" if k == "cult" else "ult/slow", 0.2 if k == "cult" else 0.25)
	_aim_min = slow * sc   # 游戏时间：0.5 秒真实时间 × 25%
	_aim_max = _aim_min + Bal.v("ult/hold_max", 1.0) * sc
	phase = "aim"
	if k != "cult" and Bal.vi("ult/mate_voice_mute", 1) > 0:
		_mute_mates(str(ld.id))   # 终结技期间队友不出声（到这次终结技收尾为止，队长自己的终结技语音照播）
	if k != "cult" and sf_on():
		_sf_start(ld)   # 超必杀暂停：世界冻结 ult/sf_t 秒（只在看得见的局里），立绘切入推到暂停结束（fx_tick）
	else:
		g.vfx.stop(Bal.v("ult/cult_freeze" if k == "cult" else "ult/freeze", 0.15 if k == "cult" else 0.1), "ult", true)
		_cutin(ld, k)
	shape({"kind": "ring", "c": ld.pos, "r": 90.0, "r1": 20.0, "w": 4.0, "col": _col(ld).lerp(Color.WHITE, 0.4), "life": _aim_min + 0.1})
	# 声音顺序（用户 10-31「开启终结技时先一下提示音效，然后放语音和对应音效」）：超必杀暂停时先只响定格提示音（sf_sound），
	# 暂停结束（立绘切入那一刻，_sf_tick）才开口说固定句 + 播蓄力；没有暂停（连携终结技 / 关掉开关）就立刻开口
	if k != "cult" and sf_on():
		var sx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
		if sx != null:
			sx.voice_hush(Bal.v("ult/sf_t", 0.35) + 0.1)   # 正在说的淡出、提示音期间别的干员不开口
		_sf_voice = true
	else:
		_ult_voice(ld)


## 终结技开口：每人固定一句（docs/205，data/ult_audio.json voice；没填时从技能池挑一句），开口即停掉别人的语音（10-30 用户）；接着播蓄力
func _ult_voice(ld) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null:
		sfx.voice(str(ld.id), "ult", false, true, str(_aud(str(ld.id)).get("voice", "")))
	_ua("charge")


func _tick_ult(dt: float) -> void:
	if caster == null or caster.pos == Vector2.INF:
		phase = ""
		act = {}
		_mute_mates("")
		return
	if phase == "aim":
		_phase_t += dt
		var mv: Vector2 = g.move_in
		var auto_aim: bool = g.bot != null or not q_held
		if aim_kind == "point":
			if mv != Vector2.ZERO and not auto_aim:
				aim += mv.normalized() * Bal.v("ult/aim_spd", 2400.0) * dt
			var off: Vector2 = aim - caster.pos
			if off.length() > 520.0:
				aim = caster.pos + off.normalized() * 520.0
		elif aim_kind == "dir" and mv != Vector2.ZERO and not auto_aim:
			aim_dir = mv.normalized()
		if (_phase_t >= _aim_min and not q_held) or _phase_t >= _aim_max:
			_cast()
		return
	if phase == "cast":
		var sx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
		if sx != null:
			sx.voice_lock(0.5)   # 招式没放完，别的干员不开口（结束后再静 0.5 秒）
			sx.op_skill_mute(0.25)   # 招式放出期间干员技能音效不出声（落地回技力当场放出的技能，10-31 用户）
		var done: bool = Moves.step_cult(self, act, dt) if kind == "cult" else Moves.step(self, act, dt)
		if done:
			phase = ""
			act = {}
			_mute_mates("")   # 最后一下伤害 / 演出收尾：队友恢复说话


func _cast() -> void:
	phase = "cast"
	_cast_t = g.t
	ev.ult_t = g.t
	_ua("cast")
	if kind == "cult":
		ev.cult_t = g.t
		act = Moves.start_cult(self, caster, aim, aim_dir)
		var dur: float = Bal.v("ult/cult_buff_t", 10.0)
		team_buff("ult:cult_buff", dur, [[&"dmg", "mult", Bal.v("ult/cult_atk", 1.2)], [&"sp_gain", "mult", Bal.v("ult/cult_sp", 1.3)],
			[&"dmg_taken", "mult", Bal.v("ult/cult_taken", 0.8)]])
	else:
		act = Moves.start(self, caster, aim, aim_dir)


## 选落点的默认光标 / 机器人落点（§2.4 / §10.2）：队长 520 内「这一招范围里能罩住最多敌人」的地方（精英算 3 只）；
## 原来用 enemies_sys.densest_point（只看离队长最近的 12 只），聚怪时永远落在最近那一团（docs/199 §5.1 聚怪表，协调人 10-29）。没有敌人时取队长前方 260
func _default_point(ld) -> Vector2:
	var dp: Vector2 = _densest(ld.pos, 520.0, maxf(120.0, Moves.aim_r(str(ld.id)) * 0.6))
	return dp if dp != Vector2.INF else ld.pos + _default_dir(ld) * 260.0


## c0 周围 maxd 内，以哪只敌人为中心半径 r 罩住的敌人最多（候选最多取 48 只均匀抽样，按 g.enemies 顺序，不抽随机数）；返回那一团的质心
func _densest(c0: Vector2, maxd: float, r: float) -> Vector2:
	var cand: Array = []
	for e in g.enemies:
		if not e.dead and not e.get("friendly", false) and e.pos.distance_squared_to(c0) <= maxd * maxd:
			cand.append(e)
	if cand.is_empty():
		return Vector2.INF
	var step: int = maxi(1, cand.size() / 48)
	var best := Vector2.INF
	var bn := -1
	for i in range(0, cand.size(), step):
		var p: Vector2 = cand[i].pos
		var n := 0
		var sum := Vector2.ZERO
		var m := 0
		for j in g.enemies_sys.query(p, r):
			var e2: Dictionary = g.enemies[j]
			if not e2.dead and not e2.get("friendly", false) and e2.pos.distance_squared_to(p) < r * r:
				n += 3 if (e2.elite or e2.boss) else 1
				sum += e2.pos
				m += 1
		if n > bn:
			bn = n
			best = sum / maxf(1.0, m)
	if best != Vector2.INF and best.distance_to(c0) > maxd:
		best = c0 + (best - c0).normalized() * maxd
	return best


## 指方向的默认：有移动输入朝移动方向，否则朝 8 方向里敌人最多的一边
func _default_dir(ld) -> Vector2:
	if g.move_in != Vector2.ZERO and g.bot == null:
		return g.move_in.normalized()
	var best := Vector2(g.facing, 0.0)
	var bn := -1
	var cnt := [0, 0, 0, 0, 0, 0, 0, 0]
	for e in g.enemies:
		if e.dead:
			continue
		var d: Vector2 = e.pos - ld.pos
		if d.length_squared() > 640.0 * 640.0 or d == Vector2.ZERO:
			continue
		cnt[int(posmod(roundi(d.angle() / (PI / 4.0)), 8))] += 1
	for i in 8:
		if cnt[i] > bn:
			bn = cnt[i]
			best = Vector2.from_angle(i * PI / 4.0)
	return best if bn > 0 else best


# ================================================================ 自动终结技 / 机器人（§10.2）

func _cfg(key: String, def: bool) -> bool:
	var v = Cfg.get(key) if Cfg != null else null
	return def if v == null else bool(v)


func _auto_ult() -> bool:
	return g.bot != null or g.autotest or _cfg("auto_ult", false)


func auto_combo() -> bool:
	return g.bot != null or g.autotest or _cfg("auto_combo", g.touch != null and g.touch.active)


func _auto_cast() -> void:
	var ld = g.squad.leader()
	if ld == null or ld.pos == Vector2.INF or ld.cmd_down > 0.0:
		return
	var fb_live: bool = g.final_boss != null and not g.final_boss.dead
	if g.t >= Bal.v("ult/bot_hold_from", 570.0) and not fb_live and g.t < 600.0:
		return   # 9:30 之后留给最终 Boss 进场
	if cells >= CELLS - 2 and cells < CELLS and full_since >= 0.0 and g.t - full_since < Bal.v("ult/bot_cult_wait", 30.0) and g.hp > 0.3 * g.max_hp:
		return   # 协同差 ≤ 2 格：最多等 30 秒凑连携终结技
	var n := 0
	var elite_core := false
	var hx: float = VIEW.x * 0.5
	var hy: float = VIEW.y * 0.5
	for e in g.enemies:
		if e.dead or e.get("friendly", false):
			continue
		var d: Vector2 = e.pos - ld.pos
		if absf(d.x) <= hx and absf(d.y) <= hy:
			n += 1
			if (e.elite or e.boss) and d.length() <= 460.0:
				elite_core = true
	if n >= int(Bal.v("ult/bot_n", 40.0)) or elite_core or g.hp < 0.3 * g.max_hp:
		if press_q():
			q_held = false


# ================================================================ 连携：亮起、排队、出手

func _tick_combo(dt: float) -> void:
	for k in range(combo_acts.size() - 1, -1, -1):
		var a: Dictionary = combo_acts[k]
		var p = a.get("p")
		if p != null and (p.pos == Vector2.INF or p.cmd_down > 0.0 or p.is_leader):
			p.syn_mv = {}
			combo_acts.remove_at(k)
			continue
		if (Link.step(self, a, dt) if a.has("link") else Combo.step(self, a, dt)):
			if p != null and not p.syn_mv.is_empty():
				p.syn_mv = {}
			if p != null and p.pos != Vector2.INF and p.pos.distance_to(g.ppos) > 80.0:
				shape({"kind": "line", "a": p.pos, "b": g.ppos, "w": 5.0, "col": _col(p), "life": 0.3})   # 残影回队
			combo_acts.remove_at(k)
	# 亮起判定（队长不放连携；冷却中 / 已在排队 / 正在出连携的不判）
	for o in g.squad.ops:
		if o.is_leader or o.pos == Vector2.INF or o.cmd_down > 0.0:
			continue
		var oid := str(o.id)
		if g.t < float(cd.get(oid, -99.0)) or _queued(o) or _busy(o):
			continue
		var info: Dictionary = Combo.check(self, o)
		if not info.is_empty():
			if queue.is_empty():
				var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
				if sfx != null:
					sfx.play("ui_ok", -6.0, 1.45)   # 就绪音（队首亮起时）
			queue.append({"o": o, "info": info, "t0": g.t, "left": Bal.v("ult/lit_t", 2.5)})
			stats.lit += 1
			stats.lit_by[oid] = int(stats.lit_by.get(oid, 0)) + 1
			Combo.on_lit(self, o, info)
	if queue.is_empty():
		return
	var head: Dictionary = queue[0]
	head.left -= dt
	if head.o.pos == Vector2.INF or head.o.cmd_down > 0.0 or head.o.is_leader:
		queue.pop_front()
		return
	if head.left <= 0.0:
		queue.pop_front()   # 漏按：什么也不发生，冷却不走
		stats.miss += 1
		return
	if auto_combo() and Bal.v("ult/lit_t", 2.5) - head.left >= Bal.v("ult/auto_delay", 0.6):
		_fire_head(true)


## E（手柄 Ⓨ、手机连携键）：放队首
func press_e() -> bool:
	if queue.is_empty() or g.state != g.S.PLAY:
		return false
	_fire_head(false)
	return true


func _fire_head(auto: bool) -> void:
	var q: Dictionary = queue.pop_front()
	var o = q.o
	if q.info.has("link"):   # 技能连携：接进那个技能，不走连携冷却
		var la: Dictionary = Link.fire(self, o, q.info)
		stats.link_by[str(o.id)] = int(stats.link_by.get(str(o.id), 0)) + 1   # 遥测：每人技能连携出手次数
		stats.combo += 1
		if auto:
			stats.combo_auto += 1
		else:
			stats.combo_e += 1
		combo_acts.append(la)
		if lf_on():
			link_flash(o, str(LINK_NAME.get(str(q.info.link), o.display_name())))
		var tc: Color = _col(o)
		shape({"kind": "line", "a": o.pos, "b": q.info.pos, "w": 5.0, "col": tc, "life": 0.2})   # 技能连携：只留一道干员色残影（不出条带、不慢放）
		return
	var dir: Vector2 = g.move_in.normalized() if (not auto and g.move_in != Vector2.ZERO) else Vector2.ZERO
	var a: Dictionary = Combo.fire(self, o, q.info, dir)
	cd[str(o.id)] = g.t + Combo.cd_of(str(o.id)) * Bal.v("ult/combo_cd_mult", 1.0)
	stats.combo += 1
	if auto:
		stats.combo_auto += 1
	else:
		stats.combo_e += 1
	if not a.is_empty():
		a["p"] = a.get("p", o)
		combo_acts.append(a)
		_combo_fx(o, q.info)


## 组合升级等「自动接一段」用：不走亮起、不占冷却，直接挂一个动作
func add_act(a: Dictionary) -> void:
	if not a.is_empty():
		stats.combo_up += 1
		combo_acts.append(a)
		var p = a.get("p")
		var hs: Array = ev.hits
		if p != null and p.pos != Vector2.INF:
			_combo_fx(p, {"tgt": a.get("tgt"), "pos": a.get("tpos", p.pos)}, str(hs[-1].op) if not hs.is_empty() and str(hs[-1].op) != str(p.id) else "")


func _queued(o) -> bool:
	for q in queue:
		if q.o == o:
			return true
	return false


func _busy(o) -> bool:
	for a in combo_acts:
		if a.get("p") == o:
			return true
	return false


func lit(o) -> Dictionary:
	for q in queue:
		if q.o == o:
			return q
	return {}


# ================================================================ 伤害预算（§3.3 / §7.3）

## 这名敌人这次终结技的总预算（含持续段与余波）
func budget(e: Dictionary, edge := false) -> float:
	var cult := tier == "cult"
	if e.boss:
		var fin: bool = e == g.final_boss
		return e.maxhp * (Bal.v("ult/cult_final", 0.08) if cult else Bal.v("ult/final", 0.06)) if fin else e.maxhp * (Bal.v("ult/cult_boss", 0.10) if cult else Bal.v("ult/boss", 0.08))
	if e.elite or e.get("part", false):
		return e.maxhp * (Bal.v("ult/cult_elite", 0.5) if cult else Bal.v("ult/elite", 0.4))
	var m: float = Bal.v("ult/minion", 2.0) * (Bal.v("ult/cult_minion", 1.0) if cult else 1.0)
	if edge:
		m *= Bal.v("ult/edge", 0.8) / maxf(0.01, Bal.v("ult/minion", 2.0))
	return ref_hp() * m


## 构筑影响：× (1 + 0.5 × 全队伤害加成)，上限 × 1.3
func build_mult(o) -> float:
	var b: float = (o._dmg_bonus() - 1.0) if o != null else 0.0
	return clampf(1.0 + 0.5 * b, 1.0, Bal.v("ult/build_cap", 1.3))


## 终结技 / 连携终结技的一段伤害：frac = 这段占预算的比例（各段 frac 之和 ≈ 1）；edge = 外缘衰减带。
## 精英「重伤不死」：本次最多打到剩 10%；Boss 本次合计不超过预算。真实伤害（不吃防御 / 法抗），灯火照亮的 ×1.25 折回去。
## opt：stun（秒，精英 ≤ 1.5、Boss 0.3 硬直由 enemies.add_cc 自己的免疫照旧）、kb（Vector2 冲量）、src（来源名后缀）
func hit(o, e: Dictionary, frac: float, opt: Dictionary = {}) -> float:
	if e.dead or e.get("friendly", false) or frac <= 0.0:
		return 0.0
	if int(e.get("ult_s", -1)) != serial:
		e["ult_s"] = serial
		e["ult_d"] = 0.0
	var full_b: float = budget(e, bool(opt.get("edge", false))) * build_mult(o)
	var amt: float = full_b * frac
	if not e.boss and not e.elite and not e.get("part", false):
		# 只乘普通小怪，精英 / Boss 的份额上限不动：ult/minion_k 全员统一上调（协调人 10-31「范围内普通小怪基本清光」，docs/199 §5.11）×
		# ult/dmgk_<干员> 范围统一后的输出补偿（§5.10）；ult/minion_hpk > 0（试验，缺省关）：预算至少是这只小怪自身最大生命 × hpk（后期高血种类也能清）
		amt = maxf(amt, e.maxhp * Bal.v("ult/minion_hpk", 0.0) * frac)
		amt *= Bal.v("ult/minion_k", 1.0) * Bal.v("ult/dmgk_" + str(o.id), 1.0)
	if e.boss:
		amt = minf(amt, maxf(0.0, full_b - float(e.ult_d)))
	elif e.elite or e.get("part", false):
		amt = minf(amt, maxf(0.0, e.hp - Bal.v("ult/elite_floor", 0.1) * e.maxhp))
	if amt <= 0.0:
		return 0.0
	if e.pos.distance_squared_to(g.ppos) < g.lamp_r() * g.lamp_r() or e.get("lit", 0.0) > 0.0:
		amt /= 1.25
	var src: String = _src(o, str(opt.get("src", "")))
	var hp0: float = e.hp
	g.combat.quiet = kills_now >= int(Bal.v("ult/fx_kill_cap", 60.0))
	g.combat.damage(e, amt, g.combat.make_hit(src, ["终结技"]))
	g.combat.quiet = false
	if e.dead:
		kills_now += 1
	var got: float = maxf(0.0, hp0 - float(e.hp))
	e.ult_d = float(e.ult_d) + got
	if got > 0.0:
		stats["hit_n"] = int(stats.get("hit_n", 0)) + 1   # 终结技掉血次数（批跑统计用，10-31 塞雷娅朝前打对照）
	if got > 0.0:
		last_hit_t = g.t
		if not opt.get("pre", false):
			impact(e.pos)   # 冲击帧（这一次终结技第一下掉血）
		_seg_sfx(str(opt.get("src", "")))
	if not e.dead:
		var st: float = float(opt.get("stun", 0.0))
		if st > 0.0:
			g.enemies_sys.add_cc(e, minf(st, 1.5) if e.elite else (0.3 if e.boss else st))
		var kb: Vector2 = opt.get("kb", Vector2.ZERO)
		if kb != Vector2.ZERO and not e.boss:
			g.enemies_sys.apply_kb(e, kb * (0.5 if e.elite else 1.0))
	return got


func _src(o, sub: String) -> String:
	var oid: String = str(o.id) if o != null else "?"
	var k: String = ("连携终结技·%s" if tier == "cult" else "终结技·%s") % oid
	if sub != "":
		k += "·" + sub
	if not g.hit_src.has(k):
		g.hit_src[k] = {"emitter": "operator", "origin": "skill", "range": "范围", "kind": "真实", "tags": ["skill", "终结技"],
			"class": o.cls if o != null else "", "op": oid}
	return k


# ---- 几何查询（各段用；不抽随机数，按 g.enemies 顺序）

func in_circle(c: Vector2, r: float) -> Array:
	var out: Array = []
	var r2 := r * r
	for e in g.enemies:
		if not e.dead and not e.get("friendly", false) and e.pos.distance_squared_to(c) <= r2:
			out.append(e)
	return out


## 线段 a→b 两侧 half_w 以内（带状 / 路径）
func in_band(a: Vector2, b: Vector2, half_w: float) -> Array:
	var out: Array = []
	var ab: Vector2 = b - a
	var l2: float = maxf(1.0, ab.length_squared())
	for e in g.enemies:
		if e.dead or e.get("friendly", false):
			continue
		var t: float = clampf((e.pos - a).dot(ab) / l2, 0.0, 1.0)
		if e.pos.distance_to(a + ab * t) <= half_w + float(e.get("r", 10.0)) * 0.5:
			out.append(e)
	return out


## 屏内（参考视野，以 c 为中心）
func in_view(c: Vector2) -> Array:
	var out: Array = []
	for e in g.enemies:
		if not e.dead and not e.get("friendly", false) and absf(e.pos.x - c.x) <= VIEW.x * 0.5 and absf(e.pos.y - c.y) <= VIEW.y * 0.5:
			out.append(e)
	return out


# ================================================================ 增益

## 全队限时增益：mods = [[stat, op, value], …] 挂 g.stats（同一 src 重复挂先摘旧的）
## zone_r > 0：只在队长站进 zone_c 为圆心、zone_r 为半径的领域里时生效（浊心斯卡蒂，协调人 10-30「站在她领域里才拿得到」），走出去即失效、回来再生效
func team_buff(src: String, dur: float, mods: Array, zone_c := Vector2.ZERO, zone_r := 0.0) -> void:
	g.stats.remove_source(src)
	for b in _buffs:
		if b.src == src:
			_buffs.erase(b)
			break
	var b2 := {"src": src, "until": g.t + dur, "mods": mods, "zc": zone_c, "zr": zone_r, "on": false}
	_buffs.append(b2)
	_buff_apply(b2)
	g.sync_stats()


func _buff_apply(b: Dictionary) -> void:
	var want: bool = float(b.zr) <= 0.0 or g.ppos.distance_to(b.zc) <= float(b.zr)
	if want == b.on:
		return
	b.on = want
	if want:
		for m in b.mods:
			g.stats.add(m[0], m[1], float(m[2]), b.src)
	else:
		g.stats.remove_source(str(b.src))
	g.sync_stats()


func _tick_buffs() -> void:
	for k in range(_buffs.size() - 1, -1, -1):
		var b: Dictionary = _buffs[k]
		if g.t >= float(b.until):
			g.stats.remove_source(str(b.src))
			_buffs.remove_at(k)
			g.sync_stats()
		elif float(b.zr) > 0.0:
			_buff_apply(b)


# ================================================================ 画面：占位图形 + 立绘切入

static func _col(o) -> Color:
	return o.col() if o != null and o.has_method("col") else Color(0.9, 0.9, 1.0)


## 程序占位图形（素材到位前；看得出范围即可）。kind：
##   circle {c, r, col, fill}          实心圆（fill = 透明度）
##   ring   {c, r, w, col, r1?}        圆环（给 r1 时从 r1 扩到 r）
##   sector {c, r, a, half, col, fill} 扇形（朝向 a、半角 half）
##   band   {a, b, w, col, fill}       长方形带（a→b，总宽 w）
##   line   {a, b, w, col}             线
##   dots   {c, r, n, col}             简单粒子（n 个点散在 r 内，位置按 i 定、不抽随机数）
##   blade  {a, b, w, col, glow}       两端尖细的直线斩痕（菱形：中段宽 w，白芯 + glow 色辉光宽 w × 3）；grow 秒内从中间拉满
##   v      Vector2（可选）            每秒位移（碎片飞散用；c / a / b 一起挪）；drag 每秒阻尼（粒子迸开后减速扩散）
## 共有：life（秒，游戏时间）、delay（秒后才出现）；Boss 战整体透明度 × 0.5（§7.4）
func shape(s: Dictionary) -> void:
	s["max"] = float(s.get("life", 0.4))
	s["age"] = -float(s.get("delay", 0.0))
	shapes.append(s)
	if phase == "cast" and caster != null:
		_fx_tag(s)
	if shapes.size() > 900:   # 粒子爆一次两三百颗（凯尔希 v2）
		shapes.pop_front()


func _tick_shapes(dt: float) -> void:
	if not _stops.is_empty():
		_tick_stops(dt)
	for k in range(shapes.size() - 1, -1, -1):
		var s: Dictionary = shapes[k]
		s.age += dt
		if s.has("_ar") and s.age >= float(s._ar.get("at", 0.0)):
			_fx_sfx(s)
		if s.age >= s.max:
			shapes.remove_at(k)
			continue
		if s.has("v") and s.age > 0.0:
			if s.has("grav"):   # 碎岩等：带重力（画面）
				s.v = s.v + Vector2(0, float(s.grav) * dt)
			if s.has("drag"):
				s.v = s.v * exp(-float(s.drag) * dt)
			var dv: Vector2 = s.v * dt
			for key in ["c", "a", "b"]:
				if s.has(key):
					s[key] = s[key] + dv


func _cutin(ld, k: String) -> void:
	var now := UM.now()
	if k == "cult":
		var i := 0
		var ops: Array = [ld]
		for o in g.squad.ops:
			if o != ld and o.pos != Vector2.INF:
				ops.append(o)
		for o in ops.slice(0, 4):
			cutins.append({"id": str(o.id), "name": o.display_name(), "col": _col(o), "t0": now + 0.12 * i, "dur": 1.1, "i": i, "cult": true})
			i += 1
	else:
		cutins.append({"id": str(ld.id), "name": ld.display_name(), "col": _col(ld), "t0": now, "dur": 0.7, "i": 0, "cult": false})
	while cutins.size() > 8:
		cutins.pop_front()


# ================================================================ 帧条（Codex 第一批终结技特效 art/fx/fx_ult_*，manifest：art/incoming/ult_batch1_1029/manifest.json）
## 一个帧条实例也是一个 shape（kind = "strip"），和程序占位图形共用寿命 / 延迟；字段：
##   name 帧条名（A.V6_FRAMES 登记帧数 / fps）、c 原点的世界坐标、o 原点在 @2x 单帧里的像素（manifest origin_px_2x）、
##   ang 旋转、sc 缩放（缺省 1 = 美术 1x 像素 × g.PX）、sx / sy 额外拉伸（拼接段铺满用）、
##   seg [起, 止] 帧段（缺省整条）、fps（缺省登记值）、loop（帧段循环，否则停在末帧）、f 固定帧（巨锚角度帧之类）、
##   layer "back"（地面，画在干员之下）/ "front"（缺省，干员之上；orbit 也画这里）、col 调色（含透明度）。
##   动画（单张大贴图用，乌尔比安裂地 v2）：rev 秒内从原点往 +x 逐渐显现（rev0 = 一开始已显现的比例；裂缝延伸）、spin 每秒转角、
##   sc1 在 scd 秒内缓出放大到的缩放（冲击环扩散）、fade 最后几秒淡出；
##   ux / uw 只取单帧里从 ux 起宽 uw 的一段（长贴图截一截当拼接段，o 相对这一段）；col1 / cold 冷却到的颜色与秒数。
## 帧号按游戏时间推进（慢放里跟着慢），纯画面。
func strip(name: String, c: Vector2, opt: Dictionary = {}) -> Dictionary:
	var s := opt.duplicate()
	s["kind"] = "strip"
	s["name"] = name
	s["c"] = c
	if not s.has("life"):
		var fr: Array = A.V6_FRAMES.get(name, [1, 10.0])
		var seg: Array = s.get("seg", [0, int(fr[0]) - 1])
		var fps: float = float(s.get("fps", fr[1]))
		s["life"] = (float(int(seg[1]) - int(seg[0]) + 1) / fps) if fps > 0.0 else 1.0
	shape(s)
	return s


## 线状拼接段（刀痕残痕 / 光束 / 锁链）：从 a 到 b 平铺，每段等比拉到正好铺满；原点在段左端中心（manifest「左端中心」）
func tiles_line(name: String, a: Vector2, b: Vector2, opt: Dictionary = {}) -> Array:
	var out: Array = []
	var fr: Array = A.V6_FRAMES.get(name, [1, 10.0])
	var t: Texture2D = _strip_tex(name)
	if t == null:
		return out
	var hi: float = A.hires_of(t)
	var fw: float = t.get_width() / float(fr[0]) / hi   # 1x 单帧宽
	var sc: float = float(opt.get("sc", 1.0))
	var tile: float = fw * g.PX * sc
	var L: float = a.distance_to(b)
	if L < 1.0:
		return out
	var n: int = maxi(1, roundi(L / tile))
	var sx: float = L / (n * tile)
	var ang: float = (b - a).angle()
	for i in n:
		var o2 := opt.duplicate()
		o2["ang"] = ang
		o2["sx"] = sx * float(opt.get("sx", 1.0))
		if not o2.has("o"):
			o2["o"] = Vector2(0.0, t.get_height() * 0.5)
		out.append(strip(name, a.lerp(b, float(i) / n), o2))
	return out


## 弧状拼接段（领域花纹 / 熔毁裂纹 / 裂地）：沿圆心 c、半径 r 摆一圈，段数按周长取整、每段等比拉到正好闭合；原点在弧中心
func tiles_arc(name: String, c: Vector2, r: float, opt: Dictionary = {}) -> Array:
	var out: Array = []
	var fr: Array = A.V6_FRAMES.get(name, [1, 10.0])
	var t: Texture2D = _strip_tex(name)
	if t == null or r < 4.0:
		return out
	var hi: float = A.hires_of(t)
	var fw: float = t.get_width() / float(fr[0]) / hi
	var sc: float = float(opt.get("sc", 1.0))
	var tile: float = fw * g.PX * sc
	var n: int = maxi(6, roundi(TAU * r / tile))
	var sx: float = TAU * r / (n * tile)
	var a0: float = float(opt.get("a0", 0.0))
	for i in n:
		var ai: float = a0 + TAU * i / n
		var o2 := opt.duplicate()
		o2["ang"] = ai + PI / 2.0
		o2["sx"] = sx * float(opt.get("sx", 1.0))
		if not o2.has("o"):
			o2["o"] = Vector2(t.get_width() / float(fr[0]) * 0.5, t.get_height() * 0.5)
		out.append(strip(name, c + Vector2.from_angle(ai) * r, o2))
	return out


var _stex := {}


## 素材到了没有（帧条 PNG 在 game/art/fx/ 里）：招式里「有帧条就画帧条、没有就画程序占位」用（docs/199 待合入清单）；只影响画面
func fx_ready(name: String) -> bool:
	return _strip_tex(name) != null


func _strip_tex(name: String) -> Texture2D:
	if not _stex.has(name):
		var t: Texture2D = g.tex.get(name) if g.tex.has(name) else A.tex(name)
		_stex[name] = t
	return _stex[name]


func _strip_frame(s: Dictionary) -> int:
	if s.has("f"):
		return int(s.f)
	var fr: Array = A.V6_FRAMES.get(str(s.name), [1, 10.0])
	var seg: Array = s.get("seg", [0, int(fr[0]) - 1])
	var fps: float = float(s.get("fps", fr[1]))
	var n: int = int(seg[1]) - int(seg[0]) + 1
	var k: int = int(maxf(0.0, float(s.age)) * fps) if fps > 0.0 else 0
	return int(seg[0]) + (k % n if s.get("loop", false) else mini(k, n - 1))


func _draw_strip(w, s: Dictionary, dim: float) -> void:
	var t: Texture2D = _strip_tex(str(s.name))
	if t == null:
		return
	var fr: Array = A.V6_FRAMES.get(str(s.name), [1, 10.0])
	var fw: float = t.get_width() / float(fr[0])
	var fh: float = float(t.get_height())
	var hi: float = A.hires_of(t)
	var age: float = maxf(0.0, float(s.age))
	var sc: float = float(s.get("sc", 1.0))
	if s.has("sc1"):
		var q: float = clampf(age / maxf(0.001, float(s.get("scd", s.max))), 0.0, 1.0)
		sc = lerpf(sc, float(s.sc1), 1.0 - (1.0 - q) * (1.0 - q))
	var k: float = g.PX * sc / hi
	var f: int = clampi(_strip_frame(s), 0, int(fr[0]) - 1)
	var o: Vector2 = s.get("o", Vector2(fw * 0.5, fh * 0.5))
	var col: Color = s.get("col", Color.WHITE)
	col.a *= dim
	if s.has("col1"):   # 冷却：cold 秒内从 col 变到 col1（裂缝爆亮后退成暗色余烬）
		var ca: float = col.a
		col = col.lerp(s.col1, clampf(age / maxf(0.001, float(s.get("cold", 0.4))), 0.0, 1.0))
		col.a = ca
	if s.has("fade"):
		col.a *= clampf((float(s.max) - age) / maxf(0.001, float(s.fade)), 0.0, 1.0)
	var ux: float = float(s.get("ux", 0.0))
	var uw: float = minf(float(s.get("uw", fw)), fw - ux)
	var vw: float = uw
	if s.has("rev"):   # 逐渐显现：只画原点往 +x 的前一段（按整纹素截，保持硬边）
		var r0: float = float(s.get("rev0", 0.0))
		vw = minf(uw, o.x + ceilf((uw - o.x) * clampf(r0 + (1.0 - r0) * age / maxf(0.001, float(s.rev)), 0.0, 1.0)))
		if vw <= o.x:
			return
	var ang: float = float(s.get("ang", 0.0)) + float(s.get("spin", 0.0)) * age
	g.draw_set_transform(s.c, ang, Vector2(k * float(s.get("sx", 1.0)), k * float(s.get("sy", 1.0))))
	g.draw_texture_rect_region(t, Rect2(-o, Vector2(vw, fh)), Rect2(f * fw + ux, 0.0, vw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 地面层（world.gd 在干员地面特效那一步调）：layer = back 的帧条
func draw_world_back(w) -> void:
	var dim: float = _dim()
	for s in shapes:
		if s.age >= 0.0 and str(s.get("layer", "front")) == "back":
			if str(s.kind) == "strip":
				_draw_strip(w, s, dim)
			else:
				_px_shape(w, s, 1.0 - s.age / maxf(0.001, s.max), s.get("col", Color.WHITE), dim)   # 灼地 / 影子等地面图形（一律像素画法）
	w.tb_flush()


# ================================================================ 舞台（技能连携样片，用户 10-29；之后终结技也用）
## stage(pos, op)：背景压暗到约 75%（ult/stage_dim 0.25 的黑）、镜头推到 ult/stage_cam（1.1）、出手队友放大 ult/stage_pop（1.25）带两层残影，
## 持续 ult/stage_t（0.45）真实秒：0.06 秒压下 → 停 → 最后 0.15 秒恢复（用户 10-29 返工：一局 20–30 次，要轻要快，不抢镜）。纯画面
var _stage_rt := -99.0
var _stage_pos := Vector2.ZERO
var _stage_op = null


func on_skill(o, i: int) -> void:
	if Link.on():
		Link.on_skill(self, o, i)


func stage(pos: Vector2, op) -> void:
	_stage_rt = UM.now()
	_stage_pos = pos
	_stage_op = op


## 0..1：舞台强度（压暗 / 推镜 / 放大共用）
func stage_k() -> float:
	var t: float = UM.now() - _stage_rt
	var T: float = Bal.v("ult/stage_t", 0.45)
	if t < 0.0 or t > T:
		return 0.0
	if t < 0.06:
		return t / 0.06
	if t > T - 0.15:
		return (T - t) / 0.15
	return 1.0


func _draw_stage(w) -> void:
	var k: float = stage_k()
	if k <= 0.0:
		return
	var c: Vector2 = g.ppos
	var R := Vector2(2400.0, 1600.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("ult/stage_dim", 0.25) * k))
	w.tb_flush()
	if _stage_op == null or _stage_op.pos == Vector2.INF:
		return
	var pr: Dictionary = _stage_op.portrait()
	var t: Texture2D = g.tex.get(str(pr.get("tex", "")))
	if t == null:
		return
	var n: int = maxi(1, int(pr.get("frames", 1)))
	var fw: float = t.get_width() / float(n)
	var fh: float = float(t.get_height())
	var hi: float = A.hires_of(t)
	var s: float = g.PX / hi * lerpf(1.0, Bal.v("ult/stage_pop", 1.25), k)
	var flip: float = -1.0 if float(_stage_op.face) < 0.0 else 1.0
	var col: Color = _col(_stage_op)
	for j in 2:   # 残影：往出手来的方向拖两层干员色
		var off: Vector2 = (g.ppos - _stage_op.pos).normalized() * (26.0 * (j + 1)) * k
		g.draw_set_transform(_stage_op.pos + off, 0.0, Vector2(s * flip, s))
		g.draw_texture_rect_region(t, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(col.r, col.g, col.b, 0.35 * k / (j + 1)))
	g.draw_set_transform(_stage_op.pos, 0.0, Vector2(s * flip, s))
	g.draw_texture_rect_region(t, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(1, 1, 1, k))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 推镜（run/cam_fx.gd 读，§7.1）：瞄准 1.08 → 出招前 0.6 秒 1.12 → 0.4 秒拉回 1.0；按游戏时间算，纯画面
var _cast_t := -99.0


func cam_punch() -> float:
	var sk: float = stage_k()
	if sk > 0.0:
		return lerpf(1.0, Bal.v("ult/stage_cam", 1.1), sk)
	var ip: float = _imp_punch()
	if ip > 1.0:
		return ip
	if phase == "aim":
		return Bal.v("ult/cam_aim", 1.08)
	var age: float = g.t - _cast_t
	if age < 0.0 or age > 1.0:
		return 1.0
	var hi: float = Bal.v("ult/cam_cast", 1.12)
	return hi if age < 0.6 else lerpf(hi, 1.0, (age - 0.6) / 0.4)


## 时间缩放（run/time_dilation.gd 读，登记为 fx 类：只在玩家局 / --realtime / --playclock 生效）
func time_scale() -> float:
	var s := 1.0
	if sf_active():
		return 0.0   # 超必杀暂停：世界冻结（敌人、弹幕、计时都停，只有演出层动）
	if phase == "aim":
		s = Bal.v("ult/cult_slow", 0.2) if kind == "cult" else Bal.v("ult/slow", 0.25)
		if kind != "cult" and _sf_rt > 0.0 and sf_on():   # 暂停后接的瞄准慢放缩短：游戏时间不变，真实时间 slow_t → sf_slow_t
			s = minf(1.0, s * Bal.v("ult/slow_t", 0.5) / maxf(0.05, Bal.v("ult/sf_slow_t", 0.3)))
	s = minf(s, _imp_scale())
	if lf_slow_on():
		s = minf(s, Bal.v("link/slow", 0.3))   # 连携轻量演出：0.3 倍 0.2 真实秒后弹回（link/flash）
	if UM.now() - _cmb_rt < Bal.v("ult/combo_slow_t", 0.3):
		s = minf(s, Bal.v("ult/combo_slow", 0.5))
	if UM.now() - _link_rt < Bal.v("ult/link_slow_t", 0.12):
		s = minf(s, Bal.v("ult/link_slow", 0.6))   # 技能连携出手瞬间的轻微放慢（比终结技弱一档）
	if UM.now() - _prep_rt < _prep_t:
		s = minf(s, _prep_s)   # 招式自己要的预备式慢动作（prep_slow；铃兰忍冬拔刀蓄势，用户 10-31）
	return s


func _dim() -> float:
	return 0.5 if (g.final_boss != null and not g.final_boss.dead) or not g.bosses.is_empty() else 1.0


## 世界层（world.gd 在干员技能层之后）：瞄准指示 + 占位图形 + 主体层帧条（地面层帧条在 draw_world_back）
func draw_world(w) -> void:
	var dim: float = _dim()
	var px: bool = Bal.vi("ult/px_style", 1) > 0   # 像素风光栅化（用户 10-30）
	_draw_stage(w)   # 舞台：压暗 + 放大的出手队友（在本层图形之前画，特效亮在上面）
	_draw_sf(w)   # 超必杀暂停：压暗到约 30% + 队长轮廓光 + 手部闪光 + 干员色放射速度线
	_draw_lf(w)   # 连携轻量演出：压暗到约 60% + 接手队友原亮度（link/flash）
	for s in shapes:
		if s.age < 0.0:
			continue
		if str(s.get("layer", "front")) == "back":
			continue
		if str(s.kind) == "strip":
			w.tb_flush()
			_draw_strip(w, s, dim)
			continue
		var k: float = 1.0 - s.age / maxf(0.001, s.max)
		var col: Color = s.get("col", Color.WHITE)
		if px:
			_px_shape(w, s, k, col, dim)
			continue
		match str(s.kind):
			"circle":
				w.tb_circle(s.c, s.r, Color(col, float(s.get("fill", 0.3)) * k * dim), 1.0, 40)
			"ring":
				var r: float = lerpf(float(s.get("r1", s.r)), float(s.r), clampf(s.age / maxf(0.001, s.max * 0.5), 0.0, 1.0))
				w.tb_ring(s.c, r, float(s.get("w", 3.0)), Color(col, 0.85 * k * dim), 48)
			"sector":
				var pts := PackedVector2Array([s.c])
				var a0: float = float(s.a) - float(s.half)
				for i in 21:
					pts.append(s.c + Vector2.from_angle(a0 + float(s.half) * 2.0 * i / 20.0) * float(s.r))
				w.tb_poly(pts, Color(col, float(s.get("fill", 0.3)) * k * dim))
			"band":
				var d: Vector2 = (s.b - s.a).normalized().orthogonal() * float(s.w) * 0.5
				w.tb_quad(s.a + d, s.b + d, s.b - d, s.a - d, Color(col, float(s.get("fill", 0.3)) * k * dim))
			"line":
				w.tb_line(s.a, s.b, Color(col, 0.9 * k * dim), float(s.get("w", 3.0)))
			"blade":
				var gr: float = float(s.get("grow", 0.0))
				var gk: float = clampf(s.age / gr, 0.0, 1.0) if gr > 0.0 else 1.0
				var m: Vector2 = (s.a + s.b) * 0.5
				var ha: Vector2 = (s.a - m) * gk
				var nrm: Vector2 = (s.b - s.a).normalized().orthogonal()
				var fo: float = float(s.get("fo", 0.08))   # 停住时满亮，最后 fo 秒淡出（缺省 0.08；德克萨斯 10-31 起不碎、慢慢淡 0.7 秒）
				var fa: float = 1.0 if s.age < s.max - fo else maxf(0.0, (s.max - s.age) / fo)
				var bw: float = float(s.get("w", 8.0))
				var gc: Color = s.get("glow", Color(0.45, 0.85, 1.0))
				w.tb_quad(m + ha, m + nrm * bw * 1.5, m - ha, m - nrm * bw * 1.5, Color(gc, 0.35 * fa * dim))
				w.tb_quad(m + ha, m + nrm * bw * 0.5, m - ha, m - nrm * bw * 0.5, Color(col, fa * dim))
			"dots":
				var n: int = int(s.get("n", 12))
				for i in n:
					var ang: float = i * 2.39996
					var rr: float = float(s.r) * sqrt(float(i + 1) / n) * (0.6 + 0.4 * (1.0 - k))
					w.tb_circle(s.c + Vector2.from_angle(ang) * rr, 3.0, Color(col, 0.9 * k * dim), 1.0, 6)
	if phase == "aim" and caster != null:
		var c: Color = _col(caster).lerp(Color.WHITE, 0.3)
		if aim_kind == "point":
			var r: float = Moves.aim_r(str(caster.id))
			_px_disc(w, aim, r + 1.5, r - 1.5, _pc(c, 0.4))   # 落点提示：只在瞄准慢动作里、淡（用户 10-29）；像素画法（10-30）
			_px_thick(w, caster.pos, aim, 1.5, _pc(c, 0.3))
		elif aim_kind == "dir":
			_px_thick(w, caster.pos, caster.pos + aim_dir * 520.0, 4.0, _pc(c, 0.8))
		else:
			var r2: float = Moves.aim_r(str(caster.id)) if kind != "cult" else VIEW.x * 0.5
			_px_disc(w, caster.pos, r2 + 1.5, r2 - 1.5, _pc(c, 0.8))
	w.tb_flush()
	_draw_hit_frame(w)


## 冲击帧（中村丰式，用户 10-31；docs/199 §7.10，pixfx §6.6）：命中那一下（impact 起算、真实时间）第 1 拍白底 + 主体黑剪影，
## 第 2 拍黑底 + 主体白剪影，各 ult/hit_frame_t（0.04 秒，30 帧录像里各 1 帧），然后回正常画面。
## 开关 ult/hit_frame（缺省 1）；只有动作字典里 hf = true 的招式启用；主体 = 标了 "hf": true 的帧条 / 图形。减少动态效果开时不画。纯画面
## 冲击帧只给队长终结技（用户 10-31：连携技 / 连携终结技不要冲击帧）
func _hf_on() -> bool:
	return kind == "ult" and act.get("hf", false) and Bal.v("ult/hit_frame", 1.0) > 0.0 and not Cfg.reduce_motion


var _hf_serial := -1
var _hf_n := [0, 0]   # 本次冲击帧白 / 黑两拍已画的帧数
var _hf_t0 := 0.0


func _draw_hit_frame(w) -> void:
	if not _hf_on():
		return
	# 每拍按真实时间 ult/hit_frame_t，且至少画满 2 帧（卡顿 / 录像时一帧超过一拍，按时间会把黑底那拍整个跳过）；
	# 按这次终结技（serial）只起算一次：反震 / 炮击会连着 impact 好几次，按 impact 重置会再闪一轮
	var ht: float = Bal.v("ult/hit_frame_t", 0.067)
	if _hf_serial != serial:
		_hf_serial = serial
		_hf_n = [0, 0]
		_hf_t0 = UM.now()
	var t: float = UM.now() - _hf_t0
	var inv: bool = t < ht or _hf_n[0] < 2   # 第 1 拍：白底黑剪影
	if not inv and _hf_n[1] >= 2 and t >= ht * 2.0:
		act["hf"] = false   # 一次终结技只闪一次（维什戴尔后几排落地也会 impact）
		act["hf_done"] = true
		return
	_hf_n[0 if inv else 1] += 1
	var bg := Color(0.92, 0.9, 0.86) if inv else Color(0.02, 0.02, 0.03)
	var hc: Array = act.get("hf_cols", [])   # 招式自定两拍配色 [底 1, 剪影 1, 底 2, 剪影 2]（流明：冷暖反差，用户 10-31 不要纯白）
	if hc.size() == 4:
		bg = hc[0] if inv else hc[2]
	var c: Vector2 = g.ppos
	var R := Vector2(2600.0, 1700.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), bg)
	w.tb_flush()
	var fg := Color(0.0, 0.0, 0.0) if inv else Color(1.6, 1.6, 1.6)   # 黑底那拍：贴图保持本色提亮（乘 8 会把红压成粉）；程序斩线照样纯白
	if hc.size() == 4:
		fg = hc[1] if inv else hc[3]
	for s in shapes:
		if s.age < 0.0 or not s.get("hf", false):
			continue
		if str(s.kind) == "strip":
			var s2: Dictionary = s.duplicate()
			s2["col"] = Color(fg, 1.0)
			s2.erase("col1")
			s2.erase("fade")
			_draw_strip(w, s2, 1.0)
		else:
			var s3: Dictionary = s.duplicate()
			s3["glow"] = Color(fg, 1.0)
			_px_shape(w, s3, 1.0, Color(fg.r, fg.g, fg.b) if (inv or hc.size() == 4) else Color.WHITE, 1.0)
	w.tb_flush()


# ================================================================ 像素风光栅化（用户 10-30「特效都要对齐我们的美术风格」）
## 占位图形不再画平滑的矢量圆 / 线：按 ult/px_grid（3 世界像素格，≈ 本作光学低分辨率格）一行一行算出水平跨度，
## 每段画一个对齐网格的矩形——硬边、无抗锯齿、无渐变；颜色亮度封顶 ult/px_lum（0.9，受光封顶不发白）。
## ult/px_style = 0 退回原来的矢量画法（对照用）。帧条（strip）不受影响
func _pxg() -> float:
	return maxf(1.0, Bal.v("ult/px_grid", 3.0))


func _pc(col: Color, a: float) -> Color:
	var m: float = maxf(col.r, maxf(col.g, col.b))
	var cap: float = Bal.v("ult/px_lum", 0.9)
	var c := col
	if m > cap:
		c = Color(col.r * cap / m, col.g * cap / m, col.b * cap / m)
	return Color(c, clampf(a, 0.0, 1.0))


func _span(w, y: float, x0: float, x1: float, G: float, col: Color) -> void:
	var a: float = floorf(x0 / G) * G
	var b: float = ceilf(x1 / G) * G
	if b - a < G * 0.5:
		return
	w.tb_quad(Vector2(a, y), Vector2(b, y), Vector2(b, y + G), Vector2(a, y + G), col)


## 任意多边形（奇偶填充）：逐行求与各边的交点，两两成段
func _px_poly(w, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3 or col.a <= 0.003:
		return
	var G: float = _pxg()
	var y0: float = INF
	var y1: float = -INF
	for p in pts:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var y: float = floorf(y0 / G) * G
	var n: int = pts.size()
	while y < y1:
		var yc: float = y + G * 0.5
		var xs: Array = []
		for i in n:
			var p: Vector2 = pts[i]
			var q: Vector2 = pts[(i + 1) % n]
			if (p.y <= yc and q.y > yc) or (q.y <= yc and p.y > yc):
				xs.append(p.x + (yc - p.y) * (q.x - p.x) / (q.y - p.y))
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			_span(w, y, xs[j], xs[j + 1], G, col)
			j += 2
		y += G


func _px_disc(w, c: Vector2, ro: float, ri: float, col: Color) -> void:
	if ro <= 0.0 or col.a <= 0.003:
		return
	var G: float = _pxg()
	var y: float = floorf((c.y - ro) / G) * G
	while y < c.y + ro:
		var dy: float = y + G * 0.5 - c.y
		if absf(dy) < ro:
			var ho: float = sqrt(ro * ro - dy * dy)
			if ri > 0.0 and absf(dy) < ri:
				var hi: float = sqrt(ri * ri - dy * dy)
				_span(w, y, c.x - ho, c.x - hi, G, col)
				_span(w, y, c.x + hi, c.x + ho, G, col)
			else:
				_span(w, y, c.x - ho, c.x + ho, G, col)
		y += G


## 碎裂冲击波（不画整圆环）：沿圆周撒像素块，块大小 / 半径按序号确定性抖动、约三成留空，越往后块越碎小
func _px_frag(w, c: Vector2, r: float, wd: float, col: Color, k: float) -> void:
	var G: float = _pxg()
	var n: int = clampi(int(TAU * r / (G * 5.0)), 8, 220)
	for i in n:
		var h: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		if h < 0.3:
			continue
		var p: Vector2 = c + Vector2.from_angle(TAU * (float(i) + h * 0.6) / n) * (r + (h - 0.65) * wd * 2.0)
		var sz: float = maxf(G, roundf(wd * (0.4 + 0.6 * h) * (0.5 + 0.5 * k) / G) * G)
		var q := Vector2(floorf(p.x / G) * G, floorf(p.y / G) * G)
		w.tb_quad(q, q + Vector2(sz, 0), q + Vector2(sz, sz), q + Vector2(0, sz), col)


func _px_thick(w, a: Vector2, b: Vector2, wd: float, col: Color) -> void:
	var d: Vector2 = (b - a).normalized().orthogonal() * maxf(_pxg(), wd) * 0.5
	_px_poly(w, PackedVector2Array([a + d, b + d, b - d, a - d]), col)


func _px_shape(w, s: Dictionary, k: float, col: Color, dim: float) -> void:
	var G: float = _pxg()
	match str(s.kind):
		"circle":
			_px_disc(w, s.c, float(s.r), 0.0, _pc(col, float(s.get("fill", 0.3)) * k * dim))
		"ring":
			var r: float = lerpf(float(s.get("r1", s.r)), float(s.r), clampf(s.age / maxf(0.001, s.max * 0.5), 0.0, 1.0))
			var wd: float = maxf(G, float(s.get("w", 3.0)))
			if s.get("frag", Bal.vi("ult/px_ring_frag", 1) > 0 and not s.get("solid", false)):   # 缺省碎裂（10-30「不用纯几何圆环当主体」）；solid = true 保留整环
				_px_frag(w, s.c, r, wd, _pc(col, 0.85 * k * dim), k)
			else:
				_px_disc(w, s.c, r + wd * 0.5, maxf(0.0, r - wd * 0.5), _pc(col, 0.85 * k * dim))
		"sector":
			var pts := PackedVector2Array([s.c])
			var a0: float = float(s.a) - float(s.half)
			for i in 21:
				pts.append(s.c + Vector2.from_angle(a0 + float(s.half) * 2.0 * i / 20.0) * float(s.r))
			_px_poly(w, pts, _pc(col, float(s.get("fill", 0.3)) * k * dim))
		"band":
			_px_thick(w, s.a, s.b, float(s.w), _pc(col, float(s.get("fill", 0.3)) * k * dim))
		"line":
			_px_thick(w, s.a, s.b, float(s.get("w", 3.0)), _pc(col, 0.9 * k * dim))
		"blade":
			var gr: float = float(s.get("grow", 0.0))
			var gk: float = clampf(s.age / gr, 0.0, 1.0) if gr > 0.0 else 1.0
			var m: Vector2 = (s.a + s.b) * 0.5
			var ha: Vector2 = (s.a - m) * gk
			var nrm: Vector2 = (s.b - s.a).normalized().orthogonal()
			var fo: float = float(s.get("fo", 0.08))
			var fa: float = 1.0 if s.age < s.max - fo else maxf(0.0, (s.max - s.age) / fo)
			var bw: float = maxf(G, float(s.get("w", 8.0)))
			var gc: Color = s.get("glow", Color(0.45, 0.85, 1.0))
			_px_poly(w, PackedVector2Array([m + ha, m + nrm * bw * 1.5, m - ha, m - nrm * bw * 1.5]), _pc(gc, 0.45 * fa * dim))
			_px_poly(w, PackedVector2Array([m + ha, m + nrm * bw * 0.5, m - ha, m - nrm * bw * 0.5]), _pc(col, fa * dim))
		"rock":   # 熔岩块 / 碎岩：不规则多边形外壳 + 裂缝透光 + 芯（c、r、rot，col 外壳、glow 裂缝、core 芯；seed 定形状）
			var sd: float = float(s.get("seed", 1.0))
			var rot: float = float(s.get("rot", 0.0)) + float(s.get("spin", 0.0)) * s.age
			var rr: float = float(s.r)
			var fa: float = float(s.get("fill", 1.0)) * (1.0 if s.get("hold", true) else k) * dim
			var pts := PackedVector2Array()
			for i in 9:
				var h: float = fposmod(sin(sd * 7.13 + float(i) * 12.9898) * 43758.5453, 1.0)
				pts.append(s.c + Vector2.from_angle(rot + TAU * float(i) / 9.0) * rr * (0.72 + 0.28 * h))
			_px_poly(w, pts, _pc(col, fa))
			if s.has("glow"):
				var gl: Color = _pc(s.glow, fa)
				for i in 3:
					var h2: float = fposmod(sin(sd * 3.7 + float(i) * 78.233) * 43758.5453, 1.0)
					var dd: Vector2 = Vector2.from_angle(rot + TAU * (float(i) + h2 * 0.5) / 3.0)
					_px_thick(w, s.c + dd * rr * 0.15, s.c + dd * rr * (0.55 + 0.25 * h2), G * (2.0 if rr >= 24.0 else 1.0), gl)
				_px_disc(w, s.c, rr * 0.3, 0.0, gl)
			if s.has("core"):
				_px_disc(w, s.c, maxf(G, rr * 0.15), 0.0, _pc(s.core, fa))
		"ellipse":   # 地面影子 / 灼地：c、rx、ry
			var pe := PackedVector2Array()
			for i in 16:
				pe.append(s.c + Vector2(cos(TAU * i / 16.0) * float(s.rx), sin(TAU * i / 16.0) * float(s.ry)))
			_px_poly(w, pe, _pc(col, float(s.get("fill", 0.3)) * (1.0 if s.get("hold", false) else k) * dim))
		"dots":
			var n: int = int(s.get("n", 12))
			var cc: Color = _pc(col, 0.9 * k * dim)
			for i in n:
				var ang: float = i * 2.39996
				var rr: float = float(s.r) * sqrt(float(i + 1) / n) * (0.6 + 0.4 * (1.0 - k))
				var p: Vector2 = s.c + Vector2.from_angle(ang) * rr
				var q: Vector2 = Vector2(floorf(p.x / G) * G, floorf(p.y / G) * G)
				w.tb_quad(q, q + Vector2(G * 2.0, 0), q + Vector2(G * 2.0, G * 2.0), q + Vector2(0, G * 2.0), cc)


## 光学光照（本作光学观感：发光的特效照亮地面与怪，docs/130）：登记一盏短命动态灯；光学 / 颗粒关时无事
func light(pos: Vector2, r: float, col: Color, life: float) -> void:
	if g.optical != null and g.optical.grains != null:
		g.optical.grains.light(pos, r, _pc(col, 1.0), life)


## 像素颗粒（fx_grains 模板：lava / fire / bfx_dust / sh_shard / blade …；n 颗沿 dir 散开）与带重力落地的火星；颗粒关时无事
func grain(name: String, pos: Vector2, dir: Vector2, col: Color, n := 6) -> void:
	if g.optical == null or g.optical.grains == null or not g.optical.grains.on():
		return
	for i in n:
		g.optical.grains.push(name, pos, dir, col)


func spark(pos: Vector2, col: Color, n := 6, drop := 24.0) -> void:
	if g.optical != null and g.optical.grains != null:
		g.optical.grains.spark(pos, pos.y + drop, col, n)


## 碎屑 / 余烬（光学粒子三档迸溅，GPU、不碰模拟随机数）；光学关时无事
func debris(pos: Vector2, col: Color, tier := 2) -> void:
	if g.optical_on and g.optical != null and g.optical.particles != null:
		g.optical.particles.tier_burst(pos, _pc(col, 1.0), clampi(tier, 1, 3))


# ================================================================ 冲击帧与连携演出（10-29 用户看录像反馈）
## ① 终结技的强调放在**打出大范围伤害的那一帧**：顿帧 ult/imp_freeze（0.1）→ ×ult/imp_slow（0.25）慢放 ult/imp_slow_t（0.45 真实秒）
##   → ult/imp_ease（0.35 秒）先慢后快缓动回 1；推镜 1.15 在慢放里缓慢拉回；闪白（减少动态效果开时换暗色描边扩散）；
##   冲击时压低配乐、恢复速度那一刻爆一声（镜头震动全项目已移除，这里用一次小推镜代替）。
##   冲击帧 = 这一次终结技第一下真正掉血的命中（hit() 自动标；opt.pre = true 的段不算，乌尔比安锁链路径就是 pre，冲击帧落在第一圈裂地）。
## ② 连携技：出手时干员色残影 → 0.3 秒 ×0.5 慢放 + 小号立绘条带；第一下命中顿帧 0.05 + 大号冲击环；结束时残影回队；
##   组合升级自动接的那段条带写两人名字、两张立绘。
## 全是演出：时间缩放登记为 fx 类、镜头走 cam_fx、按真实时间（UM.now）算，批跑不缩、不碰随机数。
var _imp_rt := -99.0
var _imp_serial := -1
var _imp_boom := true
var _imp_pos := Vector2.ZERO
var flash_rt := -99.0          # HUD 闪白起点（真实时间）
var _cmb_rt := -99.0           # 连携短慢放起点（真实时间）
var _link_rt := -99.0          # 技能连携出手瞬间放慢起点（真实时间）


func link_slow() -> void:
	_link_rt = UM.now()


## 预备式慢动作：从现在起 dur 真实秒内时间 × scale（演出类，同瞄准慢放：只在玩家局 / 录像生效，批跑不改模拟步长）
var _prep_rt := -99.0
var _prep_t := 0.0
var _prep_s := 1.0


## 延时顿帧：delay 游戏秒后顿 dur（画面层，同 vfx.stop；终结技结束后的收招一下用）
var _stops: Array = []


func stop_later(delay: float, dur: float) -> void:
	_stops.append([delay, dur])


func _tick_stops(dt: float) -> void:
	for i in range(_stops.size() - 1, -1, -1):
		_stops[i][0] = float(_stops[i][0]) - dt
		if float(_stops[i][0]) <= 0.0:
			g.vfx.stop(float(_stops[i][1]), "ult", true)
			_stops.remove_at(i)


func prep_slow(dur: float, scale: float) -> void:
	_prep_rt = UM.now()
	_prep_t = dur
	_prep_s = scale


## 终结技轻震（用户 10-30：歌蕾蒂娅收拢、浊心斯卡蒂激光点名要震屏；全项目镜头震动早先因「看着头疼」移除，这里只给终结技、幅度小）：
## shake(像素, 真实秒) 取较大者；按真实时间线性衰减，方向用正弦组合（不抽随机数）；减少动态效果开时不震
var _shk_px := 0.0
var _shk_t0 := -99.0
var _shk_dur := 0.0


func shake(px: float, dur: float) -> void:
	var now := UM.now()
	var left: float = _shk_px * maxf(0.0, 1.0 - (now - _shk_t0) / maxf(0.01, _shk_dur))
	if px * Bal.v("ult/shake_k", 1.0) >= left:
		_shk_px = px * Bal.v("ult/shake_k", 1.0)
		_shk_t0 = now
		_shk_dur = dur


func shake_off() -> Vector2:
	if Cfg.reduce_motion or _shk_px <= 0.0:
		return Vector2.ZERO
	var t: float = UM.now() - _shk_t0
	if t < 0.0 or t > _shk_dur:
		return Vector2.ZERO
	var a: float = _shk_px * (1.0 - t / _shk_dur)
	return Vector2(sin(t * 71.0) + 0.5 * sin(t * 133.0), cos(t * 89.0) + 0.5 * sin(t * 157.0)).round() * a * 0.66


func impact(pos: Vector2) -> void:
	if _imp_serial == serial:
		return
	_imp_serial = serial
	_imp_rt = UM.now()
	_imp_pos = pos
	_imp_boom = false
	_ua("impact")
	g.vfx.stop(Bal.v("ult/imp_freeze", 0.1), "ult_imp", true)
	if not (_hf_on() or act.get("hf_done", false) or act.get("soft", false)):   # soft：温柔型招式（流明）不闪白
		flash_rt = _imp_rt   # 冲击帧招式不叠共用白闪：白闪会把冲击帧和拖影一起盖掉（用户 10-31「看不出区别」）
	light(pos, 320.0, _col(caster), 0.6)   # 冲击帧：一盏大灯照亮地面（光学观感）
	debris(pos, _col(caster), 3)
	g.hurt_duck = maxf(float(g.hurt_duck), Bal.v("ult/imp_duck", 0.8))   # 配乐低通：冲击前一瞬压下去
	var c: Color = _col(caster).lerp(Color.WHITE, 0.5)
	if not act.get("no_ring", false):   # 招式自己不要圈（德克萨斯：范围由斩线表达）
		shape({"kind": "ring", "c": pos, "r": 520.0, "r1": 40.0, "w": 10.0, "col": c, "life": 0.9, "frag": true})   # 碎裂冲击波（10-30 美术口径：不用整圆环）
	if Cfg.reduce_motion:
		shape({"kind": "ring", "c": pos, "r": 600.0, "r1": 60.0, "w": 16.0, "col": Color(0.02, 0.03, 0.05), "life": 0.6})


func _imp_age() -> float:
	return UM.now() - _imp_rt


## 冲击慢放的倍率（真实时间轴）：顿帧期间由 hitstop 接管，这里从顿帧结束起算
func _imp_scale() -> float:
	var t: float = _imp_age() - Bal.v("ult/imp_freeze", 0.1)
	var st: float = Bal.v("ult/imp_slow_t", 0.45)
	var et: float = Bal.v("ult/imp_ease", 0.35)
	var lo: float = Bal.v("ult/imp_slow", 0.25)
	if t < 0.0 or t >= st + et:
		return 1.0
	if t < st:
		return lo
	var k: float = (t - st) / et
	return lerpf(lo, 1.0, k * k)   # 先慢后快（ease-in），不线性


func _imp_punch() -> float:
	var t: float = _imp_age()
	var fr: float = Bal.v("ult/imp_freeze", 0.1)
	var st: float = Bal.v("ult/imp_slow_t", 0.45)
	var et: float = Bal.v("ult/imp_ease", 0.35)
	var hi: float = Bal.v("ult/imp_cam", 1.15)
	if t < 0.0 or t > fr + st + et + 0.3:
		return 1.0
	if t < fr:
		return hi
	if t < fr + st:
		return lerpf(hi, hi - 0.06, (t - fr) / st)   # 慢放里缓慢拉回
	var k: float = clampf((t - fr - st) / (et + 0.3), 0.0, 1.0)
	var kick: float = 0.025 * maxf(0.0, 1.0 - (t - fr - st) / 0.1)   # 恢复速度那一刻轻推一下（代替震屏）
	return lerpf(hi - 0.06, 1.0, 1.0 - (1.0 - k) * (1.0 - k)) + kick


## 每帧真实时间钩子（game._process）：恢复速度那一刻爆一声
func fx_tick() -> void:
	_sf_tick()
	if not _imp_boom and _imp_age() >= Bal.v("ult/imp_freeze", 0.1) + Bal.v("ult/imp_slow_t", 0.45):
		_imp_boom = true
		var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
		var bm: Array = _aud(str(caster.id) if caster != null else "").get("boom", ["boom", 2.0, 0.8])
		if sfx != null and bm.size() >= 3 and str(bm[0]) != "":
			sfx.play(str(bm[0]), float(bm[1]), float(bm[2]))


## 终结技专属音效 / 语音表（docs/205，data/ult_audio.json）：干员的条目叠在 default 上；只在 _begin / _cast / impact / hit 四处读
const AUDIO_PATH := "res://data/ult_audio.json"
var _aud_tab := {}
var _hit_rt := -99.0


func _aud(oid: String) -> Dictionary:
	if _aud_tab.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_PATH)) if FileAccess.file_exists(AUDIO_PATH) else null
		_aud_tab = d if d is Dictionary else {"default": {}}
	if _aud_tab.has("_m:" + oid):
		return _aud_tab["_m:" + oid]
	var m: Dictionary = (_aud_tab.get("default", {}) as Dictionary).duplicate(true)
	var o: Dictionary = _aud_tab.get("ops", {}).get(oid, {})
	for k in o:
		if k == "vol":
			for s in o.vol:
				m["vol"][s] = o.vol[s]
		else:
			m[k] = o[k]
	_aud_tab["_m:" + oid] = m
	return m


## 播施放者这一槽的专属音效（charge / cast / impact / hit）：audio/sfx/ult_<干员>_<槽>.wav，缺文件 Sfx 静默
func _ua(slot: String, vol = null) -> void:
	if caster == null or not g.is_inside_tree():
		return
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx == null:
		return
	var oid := str(caster.id)
	var nm := "ult_%s_%s" % [oid, slot]
	sfx.ensure([nm])
	var vt: Dictionary = _aud(oid).get("vol", {})
	if vol == null:
		vol = vt.get(slot, vt.get("hit" if slot.ends_with("_hit") else "seg", 0.0))
	sfx.play(nm, float(vol), 1.0, 0.03)


## 招式里点名的额外一声（docs/205 §3.4，如收尾大爆 u.cue("finale")）：audio/sfx/ult_<干员>_<槽>.wav，音量取表里同名槽（缺省 0 dB）
func cue(slot: String) -> void:
	_ua(slot)


## 按招式分段配声（用户 10-30「按每个人的终结技特色来做」）：每段伤害带段名（opt.src，如「斩开」「剑雨」「反震」），
## 表里 seg.<段名> = {"on": 这段第一下播的槽, "hit": 之后每下播的槽, "gap": 节流秒}；冲击那一下 0.06 秒内不叠。
## 表里没写的段走通用 hit（hit_gap 节流）。录屏开 --sfxtrace 时每下记一条 ultev:<段名>（离线混音会跳过），用来对时间线
var _seg_on := {}           # 本次终结技已响过开头的段名
var _seg_serial := -1
var _seg_rt := {}           # 段名 -> 上次连击声的真实秒


func _seg_sfx(sg: String) -> void:
	if caster == null or not g.is_inside_tree():
		return
	var sfx: Node = g.get_node_or_null("/root/Sfx")
	if sfx != null and sfx.trace_on:
		sfx.trace.append([Engine.get_process_frames(), "ultev:" + sg, 0.0, 1.0])
	if _seg_serial != serial:
		_seg_serial = serial
		_seg_on.clear()
		_seg_rt.clear()
	var now := UM.now()
	var cfg = (_aud(str(caster.id)).get("seg", {}) as Dictionary).get(sg)
	if not cfg is Dictionary:
		if now - _imp_rt >= 0.06 and now - _hit_rt >= float(_aud(str(caster.id)).get("hit_gap", 0.08)):
			_hit_rt = now
			_ua("hit")
		return
	if not _seg_on.has(sg):
		_seg_on[sg] = true
		_seg_rt[sg] = now
		if str(cfg.get("on", "")) != "":
			_ua(str(cfg.on))
		return
	if str(cfg.get("hit", "")) != "" and now - _imp_rt >= 0.06 and now - float(_seg_rt.get(sg, -99.0)) >= float(cfg.get("gap", 0.08)):
		_seg_rt[sg] = now
		_ua(str(cfg.hit))


## 画面配声（用户 10-30「画面上几道剑痕就几声剑声」，docs/205 §4）：招式放出期间画的每个图形 / 帧条，
## 按 data/ult_audio.json 的 fx.<键> 在它出现的那一刻（+ at 秒游戏时间，如剑帧条插地那一帧）播一声。
## 键 = 图形 kind（"line" / "blade" …）或 "strip:<帧条名>"；带速度 v 的（碎片）先找 "<键>+v"。
## 规则：slot 槽名或槽名数组（数组按序轮换，每声略不同）、gap 真实秒节流（同一帧冒出的几道合成一声）、vol dB、
## w / r 只认这个线宽 / 半径（和连携拖尾、枪口火光等同 kind 图形分开）、min_t 放出后至少多少游戏秒才认（避开起手同款图形）、min_sc 帧条缩放至少多少才认（收尾大爆）、then 第二次起改播的槽、match {字段: 值} 任意字段等值匹配；同一种图形要分几条时键后加 #2 / #3。
var _fx_rt := {}
var _fx_n := {}
var _fx_serial := -1


func _fx_tag(s: Dictionary) -> void:
	var rules: Dictionary = _aud(str(caster.id)).get("fx", {})
	if rules.is_empty():
		return
	var key: String = ("strip:" + str(s.get("name", ""))) if str(s.get("kind", "")) == "strip" else str(s.get("kind", ""))
	if s.has("v") and rules.has(key + "+v"):
		key += "+v"
	for k in [key, key + "#2", key + "#3"]:   # 同一种图形可写几条规则（键后加 #2 / #3），按序取第一条对得上的
		var r = rules.get(k)
		if r is Dictionary and _fx_match(s, r):
			s["_ar"] = r
			s["_ak"] = k
			if s.age >= float(r.get("at", 0.0)):
				_fx_sfx(s)
			return


func _fx_match(s: Dictionary, r: Dictionary) -> bool:
	for f in ["w", "r"]:
		if r.has(f) and absf(float(s.get(f, 0.0)) - float(r[f])) > 0.01:
			return false
	var mt: Dictionary = r.get("match", {})
	for f in mt:   # 任意字段等值匹配（如归溟幽灵鲨弹射小锯的 scd 0.05，和同名的大锯分开）
		if absf(float(s.get(f, -999.0)) - float(mt[f])) > 0.001:
			return false
	return g.t - _cast_t >= float(r.get("min_t", -1.0)) and float(s.get("sc", 1.0)) >= float(r.get("min_sc", -1.0))


func _fx_sfx(s: Dictionary) -> void:
	var r: Dictionary = s._ar
	var key: String = s._ak
	s.erase("_ar")
	if caster == null:
		return
	if _fx_serial != serial:
		_fx_serial = serial
		_fx_rt.clear()
		_fx_n.clear()
	var now := UM.now()
	if now - float(_fx_rt.get(key, -99.0)) < float(r.get("gap", 0.0)) - 1e-6:
		return
	_fx_rt[key] = now
	var sl = r.get("slot", "")
	var i: int = int(_fx_n.get(key, 0))
	_fx_n[key] = i + 1
	if i > 0 and r.has("then"):   # 同一招里第二次起改播 then（如推进之王再跃的小砸地，不再整声大爆）
		sl = r.then
	var nm: String = str(sl)
	if sl is Array:
		nm = str(sl[i % sl.size()])
	if nm != "":
		_ua(nm, r.get("vol"))


## 连携出手演出：残影拖尾 + 短慢放 + 小立绘条带（自动连携同样）
func _combo_fx(o, info: Dictionary, pair_id := "") -> void:
	var tp: Vector2 = o.pos
	var tg = info.get("tgt")
	if tg is Dictionary and not tg.get("dead", true):
		tp = tg.pos
	elif info.has("pos"):
		tp = info.pos
	var c: Color = _col(o)
	shape({"kind": "line", "a": o.pos, "b": tp, "w": 8.0, "col": c.lerp(Color.WHITE, 0.25), "life": 0.35})
	for k in 4:
		shape({"kind": "circle", "c": o.pos.lerp(tp, 0.25 * k), "r": 16.0 - 2.0 * k, "col": c, "fill": 0.55 - 0.1 * k, "life": 0.25 + 0.06 * k})
	if lf_on():   # 连携轻量演出代替小条带 + 0.5 倍慢放
		link_flash(o, o.display_name() if pair_id == "" else "%s × %s" % [g.squad.get_op(pair_id).display_name() if g.squad.get_op(pair_id) != null else "", o.display_name()])
		return
	_cmb_rt = UM.now()
	var ci := {"id": str(o.id), "name": o.display_name(), "col": c, "t0": _cmb_rt, "dur": 0.8, "i": 0, "cult": false, "small": true}
	if pair_id != "":
		var po = g.squad.get_op(pair_id)
		if po != null:
			ci["id2"] = pair_id
			ci["name"] = "%s × %s" % [po.display_name(), o.display_name()]
	cutins.append(ci)
	while cutins.size() > 8:
		cutins.pop_front()


## 连携命中（combo_landed 里调）：顿帧 0.05 + 大号冲击环（比普攻明显大一号）
func _combo_hit_fx(o, pos: Vector2) -> void:
	g.vfx.stop(Bal.v("ult/combo_freeze", 0.05), "combo", true)
	var c: Color = _col(o).lerp(Color.WHITE, 0.35)
	shape({"kind": "ring", "c": pos, "r": 150.0, "r1": 20.0, "w": 8.0, "col": c, "life": 0.4})
	shape({"kind": "circle", "c": pos, "r": 90.0, "col": c, "fill": 0.35, "life": 0.18})
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0 + 0.2)
		shape({"kind": "line", "a": pos + d * 30.0, "b": pos + d * 140.0, "w": 4.0, "col": c, "life": 0.22})


## 批跑汇总（autotest / bot 结果行带上）
func report() -> Dictionary:
	return {"ult": stats.ult, "cult": stats.cult, "combo": stats.combo, "combo_auto": stats.combo_auto, "combo_up": stats.combo_up,
		"lit": stats.lit, "lit_by": stats.lit_by, "link_by": stats.link_by, "miss": stats.miss, "first_full": snappedf(float(stats.first_full), 0.1), "ult_times": stats.ult_times, "cult_times": stats.cult_times,
		"e_out": snappedf(float(stats.e_out), 0.1), "e_kill": snappedf(float(stats.e_kill), 0.1), "e_hurt": snappedf(float(stats.e_hurt), 0.1), "e_combo": snappedf(float(stats.e_combo), 0.1), "hit_n": int(stats.get("hit_n", 0))}

# ================================================================ 超必杀暂停（用户 10-30「终结技还不够明显，借鉴 MUGEN / 格斗游戏超必杀，先试试看」）
## 开关 ult/superflash（缺省 1，0 = 现行起手）。按下 Q 的瞬间：
##   世界冻结 ult/sf_t（0.35）真实秒——走 time_dilation 的 fx 类来源（倍率 0），只在玩家局 / --realtime / --playclock 生效，
##   机器人批跑不冻结，所以同 seed TRACE 与关掉时逐行相同；暂停期间队长不受伤（时间不走，另在看得见的局里给一点无敌兜底）；
##   背景与敌人压暗到约 30%（ult/sf_dim 0.7 的黑），队长原亮度 + 一圈干员代表色轮廓光，手 / 武器位置闪一道像素光（3 像素格、亮度封顶 0.9）；
##   干员色放射速度线 ult/sf_lines（28 条，手机网页减半），暂停结束 ult/sf_out（0.2）秒内退掉；
##   起手音 sf_sound（每人专属 ult_<干员>_sf，docs/205 §3.6）。
## 暂停结束才出立绘切入，接着是瞄准慢放（真实时间 ult/sf_slow_t 0.3 秒，原 0.5；游戏时间里的瞄准时长不变）。不加镜头震动。
## 减少动态效果：压暗改淡入淡出、不画速度线。连携终结技不走这里（先不做）。
var _sf_rt := -99.0        # 暂停起点（真实时间）；< 0 = 这一发没有暂停
var _sf_ld = null
var _sf_cut := false       # 暂停结束时是否已补立绘切入
var _sf_voice := false     # 暂停结束时补开口 + 蓄力（提示音先单独响）


## 终结技从起手到收尾这段（队友静音、「LEVEL UP」等横幅推迟到结束后再显示）
func show_busy() -> bool:
	return phase != "" and kind != "cult"


func _mute_mates(cid: String) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null and sfx.has_method("mute_mates") and (cid != "" or str(sfx.get("voice_only")) != ""):
		sfx.mute_mates(cid)


func sf_on() -> bool:
	return Bal.vi("ult/superflash", 1) > 0


func sf_age() -> float:
	return UM.now() - _sf_rt


func sf_active() -> bool:
	return _sf_rt > 0.0 and sf_age() < Bal.v("ult/sf_t", 0.35)


func _sf_visual() -> bool:
	return g.mode == g.Mode.PLAY or g.realtime or g.playclock_test


func _sf_start(ld) -> void:
	_sf_rt = UM.now()
	_sf_ld = ld
	_sf_cut = false
	sf_sound(ld)


## 起手音：每人专属 audio/sfx/ult_<干员>_sf.wav（docs/205 §3.6，共用「定格」瞬态 + 各人身份的一声）；缺文件退回金属剑声
func sf_sound(ld) -> void:
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx == null:
		return
	var oid := str(ld.id)
	var nm := "ult_%s_sf" % oid
	if ResourceLoader.exists("res://audio/sfx/%s.wav" % nm):
		sfx.ensure([nm])
		sfx.play(nm, float(_aud(oid).get("vol", {}).get("sf", 0.0)), 1.0, 0.0)
	else:
		sfx.play("carmen_sword", 1.0, 1.3, 0.0)


func _sf_tick() -> void:
	if _sf_rt <= 0.0:
		return
	if sf_active():
		if _sf_visual():   # 时间不走本来就不会挨打；看得见的局里再给一点无敌兜底（批跑不走这里，不改模拟）
			g.invuln = maxf(g.invuln, 0.05)
			g.invuln_move_until = maxf(g.invuln_move_until, g.t + 0.05)   # 这段无敌不闪烁
		return
	if not _sf_cut:
		_sf_cut = true
		if _sf_ld != null and caster == _sf_ld:
			_cutin(_sf_ld, kind)
			if _sf_voice:
				_sf_voice = false
				_ult_voice(_sf_ld)


## 队长白剪影（轮廓光用）：按贴图缓存一张，不透明像素全白；调色成干员色画在本体外圈
var _sf_wcache := {}


func _sf_white(tx: Texture2D) -> Texture2D:
	var key := tx.get_rid()
	if not _sf_wcache.has(key):
		var img: Image = tx.get_image()
		if img == null or img.is_empty():
			_sf_wcache[key] = tx
		else:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			for y in img.get_height():
				for x in img.get_width():
					var a: float = img.get_pixel(x, y).a
					img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.3 else 0.0))
			_sf_wcache[key] = ImageTexture.create_from_image(img)
	return _sf_wcache[key]


func _draw_sf(w) -> void:
	if _sf_rt <= 0.0 or _sf_ld == null or _sf_ld.pos == Vector2.INF:
		return
	var T: float = Bal.v("ult/sf_t", 0.35)
	var out: float = Bal.v("ult/sf_out", 0.2)
	var t: float = sf_age()
	if t < 0.0 or t > T + out:
		return
	var rm: bool = Cfg.reduce_motion
	var k: float = 1.0 if t < T else 1.0 - (t - T) / out
	if rm:   # 减少动态效果：压暗淡入淡出
		k = minf(k, clampf(t / 0.12, 0.0, 1.0))
	var col: Color = _col(_sf_ld)
	var c: Vector2 = _sf_ld.pos
	var R := Vector2(2400.0, 1600.0)
	var gc: Vector2 = g.ppos
	w.tb_quad(gc - R, gc + Vector2(R.x, -R.y), gc + R, gc + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("ult/sf_dim", 0.7) * k))
	# 干员色放射速度线（往外流）：位置按序号哈希定，不抽随机数
	if not rm:
		var n: int = Bal.vi("ult/sf_lines", 28)
		if Cfg.mobile_web():
			n = maxi(4, n / 2)
		var G: float = _pxg()
		for i in n:   # 每条长短 / 粗细 / 速度 / 角度都打散（10-30 预审：等间距同长的线像重复矩形拼出来的）；尖头细尾
			var h1: float = fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
			var h2: float = fposmod(sin(float(i) * 78.233) * 12345.678, 1.0)
			var h3: float = fposmod(sin(float(i) * 39.425) * 24634.633, 1.0)
			var d: Vector2 = Vector2.from_angle(TAU * h3 + 0.35 * (h1 - 0.5))
			var spd: float = 900.0 + 1400.0 * h2
			var r0: float = 50.0 + fposmod(t * spd + h1 * 900.0, 860.0)
			var ln: float = 50.0 + 320.0 * h1 * h1
			var wd: float = G * (1.0 + floorf(h2 * 2.99))
			var lc: Color = col.lerp(Color.WHITE, 0.4 * h3)
			var a0: float = (0.25 + 0.5 * h2) * k
			var p0: Vector2 = c + d * r0
			_px_thick(w, p0, p0 + d * ln * 0.35, wd, _pc(lc, a0))                         # 亮头
			_px_thick(w, p0 + d * ln * 0.35, p0 + d * ln, maxf(G, wd - G), _pc(col, a0 * 0.55))   # 细尾
	w.tb_flush()
	# 队长：原亮度 + 一圈干员色轮廓光（画在压暗层之上）
	var pr: Dictionary = _sf_ld.portrait()
	var tx: Texture2D = g.tex.get(str(pr.get("tex", "")))
	if tx != null:
		var nf: int = maxi(1, int(pr.get("frames", 1)))
		var fw: float = tx.get_width() / float(nf)
		var fh: float = float(tx.get_height())
		var hi: float = A.hires_of(tx)
		var sc: float = g.PX / hi
		var flip: float = -1.0 if float(_sf_ld.face) < 0.0 else 1.0
		var G2: float = _pxg()
		var wt: Texture2D = _sf_white(tx)
		for ring in [[2.0, _pc(col, 0.55 * k)], [1.0, _pc(col.lerp(Color.WHITE, 0.35), k)]]:   # 外圈 2 格淡、内圈 1 格亮（10-30 用户嫌读不出）
			var d: float = G2 * float(ring[0])
			for off in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d), Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]:
				g.draw_set_transform(c + off, 0.0, Vector2(sc * flip, sc))
				g.draw_texture_rect_region(wt, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), ring[1])
		g.draw_set_transform(c, 0.0, Vector2(sc * flip, sc))
		g.draw_texture_rect_region(tx, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(1, 1, 1, k))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 手 / 武器位置一道像素闪光：十字 + 斜十字，暂停前段长出、后段收回
	if t < T:
		var hp: Vector2 = c + Vector2(14.0 * (1.0 if float(_sf_ld.face) >= 0.0 else -1.0), -34.0)
		var ph: float = t / T
		var L: float = 46.0 * sin(PI * minf(1.0, ph * 1.4))
		var fc: Color = _pc(col.lerp(Color.WHITE, 0.6), 1.0)
		var G3: float = _pxg()
		_px_thick(w, hp - Vector2(L, 0), hp + Vector2(L, 0), G3 * 2.0, fc)
		_px_thick(w, hp - Vector2(0, L * 0.8), hp + Vector2(0, L * 0.8), G3 * 2.0, fc)
		_px_thick(w, hp - Vector2(L, L) * 0.4, hp + Vector2(L, L) * 0.4, G3, _pc(col, 0.85))
		_px_thick(w, hp - Vector2(L, -L) * 0.4, hp + Vector2(L, -L) * 0.4, G3, _pc(col, 0.85))
		_px_disc(w, hp, maxf(G3, L * 0.18), 0.0, _pc(Color.WHITE, 0.9))
		w.tb_flush()

# ================================================================ 连携轻量演出（用户 10-31 批准；协调人：在超必杀那套上加、比终结技低一档）
## 开关 link/flash（缺省 1；0 = 原来的：技能连携舞台压暗 25% + 队友放大残影 + 出手瞬间 0.6 倍、普通连携小条带 + 0.5 倍）。
## 连携出手（技能连携 Link.fire / 普通连携 Combo.fire，E 或自动）那一刻：
##   压暗：背景压到约 60%（link/dim 0.4 的黑），link/dim_in（0.06）秒淡入、停到 link/dim_t（0.25）秒、再 link/dim_out（0.15）秒淡出；
##     接手队友原大小原亮度画在压暗层之上；连携自己的特效（前景层 u.shape / u.strip，含 link_fx_common 的接力光与光柱）本来就画在压暗层之后，保持原亮度；
##   聚光：队友脚下一圈本人色光（地面椭圆 + u.light，link/spot_t 0.5 秒，亮度封顶 0.85），压暗时照样亮；
##   慢放：link/slow（0.3）倍、link/slow_t（0.2）真实秒，到点直接弹回（不定格）；
##   标识：HUD 左侧闪出队友小头像 + 连携名，link/tag_t（0.6）秒淡出（hud_ult._draw_link_tag；不做斜带切入）；
##   防疲劳：离上一次连携演出不到 link/calm（8）游戏秒，只打聚光，不压暗、不慢放、不出标识。
## 不加冲击帧、不白闪（用户 10-31「一直闪频不好」）。压暗 / 慢放都是画面与 time_dilation 的 fx 类：批跑不生效，同 seed TRACE 不变。
const LINK_NAME := {"pursue": "追击", "lava": "熔岩", "gather": "钩索", "cover": "举盾", "boom_rain": "爆炸剑雨", "cross": "十字斩",
	"l_lappland": "月牙剑气", "l_specter": "替身斩", "l_irene": "提灯一照", "l_mizuki": "小触手", "l_skadi": "拖刃冲锋", "l_siege": "冲阵",
	"l_exusiai": "穿透扫射", "l_wisadel": "好礼", "l_logos": "消弹", "l_suzuran": "狐火", "l_angelina": "引力环", "l_ulpianus": "掷锚",
	"l_saria": "钙质护盾", "l_kaltsit": "Mon3tr 掩护", "l_lumen": "灯火", "l_skalter": "歌声"}
var lf_rt := -99.0        # 本次演出起点（真实时间）
var lf_full := false      # 完整演出（否则防疲劳：只打聚光）
var lf_op = null
var lf_name := ""
var _lf_g := -INF         # 上一次演出的游戏时刻


func lf_on() -> bool:
	return Bal.vi("link/flash", 1) > 0


func link_flash(p, nm: String) -> void:
	if p == null or p.pos == Vector2.INF:
		return
	lf_full = g.t - _lf_g >= Bal.v("link/calm", 8.0)
	_lf_g = g.t
	lf_rt = UM.now()
	lf_op = p
	lf_name = nm
	var cp: Color = _col(p)
	var m: float = maxf(cp.r, maxf(cp.g, cp.b))
	var sc: Color = cp * minf(1.0, 0.85 / maxf(0.01, m))   # 亮度封顶 0.85
	var st: float = Bal.v("link/spot_t", 0.5)
	shape({"kind": "ellipse", "c": p.pos + Vector2(0, 6), "rx": 58.0, "ry": 22.0, "col": Color(sc, 1.0), "fill": 0.42, "life": st})
	shape({"kind": "ellipse", "c": p.pos + Vector2(0, 6), "rx": 34.0, "ry": 13.0, "col": Color(sc.lerp(Color.WHITE, 0.25), 1.0), "fill": 0.38, "life": st * 0.8})
	light(p.pos, 150.0, sc, st)


## 压暗强度 0..1（只在完整演出里）
func lf_dim_k() -> float:
	if not lf_full:
		return 0.0
	var t: float = UM.now() - lf_rt
	var ti: float = Bal.v("link/dim_in", 0.06)
	var th: float = Bal.v("link/dim_t", 0.25)
	var to: float = Bal.v("link/dim_out", 0.15)
	if t < 0.0 or t > th + to:
		return 0.0
	if t < ti:
		return t / ti
	if t > th:
		return 1.0 - (t - th) / to
	return 1.0


func lf_slow_on() -> bool:
	return lf_full and UM.now() - lf_rt < Bal.v("link/slow_t", 0.2)


func _draw_lf(w) -> void:
	var k: float = lf_dim_k()
	if k <= 0.0:
		return
	var c: Vector2 = g.ppos
	var R := Vector2(2400.0, 1600.0)
	w.tb_quad(c - R, c + Vector2(R.x, -R.y), c + R, c + Vector2(-R.x, R.y), Color(0.0, 0.0, 0.02, Bal.v("link/dim", 0.4) * k))
	w.tb_flush()
	if lf_op == null or lf_op.pos == Vector2.INF:
		return
	var pr: Dictionary = lf_op.portrait()
	var t: Texture2D = g.tex.get(str(pr.get("tex", "")))
	if t == null:
		return
	var n: int = maxi(1, int(pr.get("frames", 1)))
	var fw: float = t.get_width() / float(n)
	var fh: float = float(t.get_height())
	var s: float = g.PX / A.hires_of(t)
	var flip: float = -1.0 if float(lf_op.face) < 0.0 else 1.0
	g.draw_set_transform(lf_op.pos, 0.0, Vector2(s * flip, s))   # 接手队友原大小原亮度压在暗层之上
	g.draw_texture_rect_region(t, Rect2(-fw * 0.5, -fh * 0.92, fw, fh), Rect2(0, 0, fw, fh), Color(1, 1, 1, k))
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
