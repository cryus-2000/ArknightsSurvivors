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
const UM = preload("res://scripts/ui_motion.gd")

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

# ---- 增益、画面
var _buffs: Array = []      # {"src", "until"}：到点 g.stats.remove_source
var shapes: Array = []      # 程序占位图形（draw_world 画），见 shape()
var cutins: Array = []      # 立绘切入条带（HUD 画）：{"id", "name", "col", "t0", "dur", "i"}；t0 / dur 按真实时间（UM.now）

# ---- 统计（批跑汇总 / ult_bench）
var stats := {"ult": 0, "cult": 0, "combo": 0, "combo_auto": 0, "combo_e": 0, "combo_up": 0, "lit": 0, "miss": 0,
	"first_full": -1.0, "ult_times": [], "cult_times": [], "lit_by": {}, "e_out": 0.0, "e_kill": 0.0, "e_hurt": 0.0, "e_combo": 0.0}


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
	if g.state != g.S.PLAY:
		_clear()
		return
	_events()
	if not _filled and g.t >= Bal.v("ult/test_fill_at", -1.0) and Bal.v("ult/test_fill_at", -1.0) >= 0.0:
		_filled = true   # 测试 / 录像用（缺省 -1 = 关）：到点直接充满能量，协同给 ult/test_cells 格
		energy = FULL
		full_since = g.t
		cells = mini(CELLS, Bal.vi("ult/test_cells", 0))
	_tick_buffs()
	_tick_shapes(dt)
	Moves.tick_bg(self)   # 终结技的延后部分（凯尔希 Mon3tr 8 秒后重构）
	if phase != "":
		_tick_ult(dt)
	_tick_combo(dt)
	if phase == "" and energy >= FULL and _auto_ult():
		_auto_cast()


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
	var slow: float = Bal.v("ult/cult_slow_t" if k == "cult" else "ult/slow_t", 0.8 if k == "cult" else 0.5)
	var sc: float = Bal.v("ult/cult_slow" if k == "cult" else "ult/slow", 0.2 if k == "cult" else 0.25)
	_aim_min = slow * sc   # 游戏时间：0.5 秒真实时间 × 25%
	_aim_max = _aim_min + Bal.v("ult/hold_max", 1.0) * sc
	phase = "aim"
	g.vfx.stop(Bal.v("ult/cult_freeze" if k == "cult" else "ult/freeze", 0.15 if k == "cult" else 0.1), "ult", true)
	_cutin(ld, k)
	shape({"kind": "ring", "c": ld.pos, "r": 90.0, "r1": 20.0, "w": 4.0, "col": _col(ld).lerp(Color.WHITE, 0.4), "life": _aim_min + 0.1})
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g.is_inside_tree() else null
	if sfx != null:
		sfx.voice(str(ld.id), "skill_3", false, true)   # 语音方案 A（§11-5）：终结技播现 S3 那句


func _tick_ult(dt: float) -> void:
	if caster == null or caster.pos == Vector2.INF:
		phase = ""
		act = {}
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
		var done: bool = Moves.step_cult(self, act, dt) if kind == "cult" else Moves.step(self, act, dt)
		if done:
			phase = ""
			act = {}


func _cast() -> void:
	phase = "cast"
	_cast_t = g.t
	ev.ult_t = g.t
	if kind == "cult":
		ev.cult_t = g.t
		act = Moves.start_cult(self, caster, aim, aim_dir)
		var dur: float = Bal.v("ult/cult_buff_t", 10.0)
		team_buff("ult:cult_buff", dur, [[&"dmg", "mult", Bal.v("ult/cult_atk", 1.2)], [&"sp_gain", "mult", Bal.v("ult/cult_sp", 1.3)],
			[&"dmg_taken", "mult", Bal.v("ult/cult_taken", 0.8)]])
	else:
		act = Moves.start(self, caster, aim, aim_dir)


## 选落点的默认光标：队长前方 260，那一带（≤ 520）敌人最密处（§2.4 / §10.2）
func _default_point(ld) -> Vector2:
	var fwd: Vector2 = ld.pos + _default_dir(ld) * 260.0
	var dp: Vector2 = g.enemies_sys.densest_point(200.0, ld.pos)
	if dp != Vector2.INF and dp.distance_to(ld.pos) <= 520.0:
		return dp
	return fwd


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
		if Combo.step(self, a, dt):
			if p != null and not p.syn_mv.is_empty():
				p.syn_mv = {}
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


## 组合升级等「自动接一段」用：不走亮起、不占冷却，直接挂一个动作
func add_act(a: Dictionary) -> void:
	if not a.is_empty():
		stats.combo_up += 1
		combo_acts.append(a)


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
		last_hit_t = g.t
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
func team_buff(src: String, dur: float, mods: Array) -> void:
	g.stats.remove_source(src)
	for m in mods:
		g.stats.add(m[0], m[1], float(m[2]), src)
	for b in _buffs:
		if b.src == src:
			b.until = g.t + dur
			g.sync_stats()
			return
	_buffs.append({"src": src, "until": g.t + dur})
	g.sync_stats()


func _tick_buffs() -> void:
	for k in range(_buffs.size() - 1, -1, -1):
		if g.t >= float(_buffs[k].until):
			g.stats.remove_source(str(_buffs[k].src))
			_buffs.remove_at(k)
			g.sync_stats()


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
## 共有：life（秒，游戏时间）、delay（秒后才出现）；Boss 战整体透明度 × 0.5（§7.4）
func shape(s: Dictionary) -> void:
	s["max"] = float(s.get("life", 0.4))
	s["age"] = -float(s.get("delay", 0.0))
	shapes.append(s)
	if shapes.size() > 160:
		shapes.pop_front()


func _tick_shapes(dt: float) -> void:
	for k in range(shapes.size() - 1, -1, -1):
		var s: Dictionary = shapes[k]
		s.age += dt
		if s.age >= s.max:
			shapes.remove_at(k)


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
		cutins.append({"id": str(ld.id), "name": ld.display_name(), "col": _col(ld), "t0": now, "dur": 0.9, "i": 0, "cult": false})
	while cutins.size() > 8:
		cutins.pop_front()


## 推镜（run/cam_fx.gd 读，§7.1）：瞄准 1.08 → 出招前 0.6 秒 1.12 → 0.4 秒拉回 1.0；按游戏时间算，纯画面
var _cast_t := -99.0


func cam_punch() -> float:
	if phase == "aim":
		return Bal.v("ult/cam_aim", 1.08)
	var age: float = g.t - _cast_t
	if age < 0.0 or age > 1.0:
		return 1.0
	var hi: float = Bal.v("ult/cam_cast", 1.12)
	return hi if age < 0.6 else lerpf(hi, 1.0, (age - 0.6) / 0.4)


## 时间缩放（run/time_dilation.gd 读，登记为 fx 类：只在玩家局 / --realtime / --playclock 生效）
func time_scale() -> float:
	if phase != "aim":
		return 1.0
	return Bal.v("ult/cult_slow", 0.2) if kind == "cult" else Bal.v("ult/slow", 0.25)


## 世界层（world.gd 在干员技能层之后）：瞄准指示 + 占位图形
func draw_world(w) -> void:
	var dim: float = 0.5 if (g.final_boss != null and not g.final_boss.dead) or not g.bosses.is_empty() else 1.0
	for s in shapes:
		if s.age < 0.0:
			continue
		var k: float = 1.0 - s.age / maxf(0.001, s.max)
		var col: Color = s.get("col", Color.WHITE)
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
			w.tb_ring(aim, r, 3.0, Color(c, 0.9), 56)
			w.tb_circle(aim, r, Color(c, 0.12), 1.0, 40)
			w.tb_line(caster.pos, aim, Color(c, 0.6), 2.0)
		elif aim_kind == "dir":
			w.tb_line(caster.pos, caster.pos + aim_dir * 520.0, Color(c, 0.8), 4.0)
		else:
			var r2: float = Moves.aim_r(str(caster.id)) if kind != "cult" else VIEW.x * 0.5
			w.tb_ring(caster.pos, r2, 3.0, Color(c, 0.8), 56)
	w.tb_flush()


## 批跑汇总（autotest / bot 结果行带上）
func report() -> Dictionary:
	return {"ult": stats.ult, "cult": stats.cult, "combo": stats.combo, "combo_auto": stats.combo_auto, "combo_up": stats.combo_up,
		"lit": stats.lit, "lit_by": stats.lit_by, "miss": stats.miss, "first_full": snappedf(float(stats.first_full), 0.1), "ult_times": stats.ult_times, "cult_times": stats.cult_times,
		"e_out": snappedf(float(stats.e_out), 0.1), "e_kill": snappedf(float(stats.e_kill), 0.1), "e_hurt": snappedf(float(stats.e_hurt), 0.1), "e_combo": snappedf(float(stats.e_combo), 0.1)}
