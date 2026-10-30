extends RefCounted
## 局内数据记录（2026-09-26，docs/40）：一局一条「整局记录」，平衡机器人与真实玩家同一格式。
## - 整局指标（受击、低血时长、死因、Boss 用时、精英化 / 入队时间、每 30 秒曲线……）原在 core/bot.gd，只有机器人局才采；
##   现在所有对局都采。机器人局由 run/autotest.gd 按原来的节奏驱动（tick(0.066)），真实玩家局由 game.gd _update 驱动。
## - record() 拼出整局记录：平衡测试照旧打印成 `BALANCE {...}`（字段与之前完全相同，批跑 / A/B 工具不用改）；
##   真实玩家局结束（胜 / 负 / 中途退出）时 save_local() 追加一行到 user://runs/runs.jsonl，外面再包一层 meta（版本、时间、种子……）。
## - 测试运行（带任何 --xxx 参数）与图鉴演示不写本地文件（docs/36：测试不写玩家存档）。
## - 发布版（导出的 release 包）：对内包（build.json audience = internal）写，与开发试玩相同（用户 2026-10-10：对内包给自己和
##   几位测试者玩，用真实对局判断难度；设置页有「打开记录文件夹」，测试者把 runs.jsonl 发回来，tools/runs_report.py 可合并多份）；
##   对外包（public）恒不写：用户 2026-09-26 决定暂不收集任何数据。判断集中在 Cfg.runs_log_enabled()。
## - 只在本地，不联网上传；上报通道与玩家同意流程等上线时再做（docs/40 §4）。
## 分析：python tools/runs_report.py 读本地记录，套用 balance_run 的汇总表。

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
const D = preload("res://scripts/data.gd")
const SCHEMA := 1                  # 记录格式版本：字段有不兼容改动时 +1，分析脚本按它区分
const SAMPLE_EVERY := 30.0         # 曲线采样间隔（局内秒）
const RUNS_PATH := "user://runs/runs.jsonl"
const MAX_BYTES := 8000000         # 本地记录上限（约 8 MB、上千局）：超过后丢掉较早的一半
const MIN_SAVE_T := 20.0           # 局内不足 20 秒就退出的不记（开局误点、立即重开）

var g: Game
# ---- 整局指标（原 core/bot.gd，2026-09-26 挪来）
var sample_next := 0.0          # 下一个采样时间点（按局内时间对齐到 0 / 30 / 60 …）
var curve: Array = []           # 每 30 秒：{t, hp, lamp, lv, kills, squad, taken, enemies}
var low_hp_s := 0.0             # 生命 < 35% 的累计秒数
var king_low_s := 0.0           # 带国王套且低血（relic/king_low）的累计秒数
var low20_s := 0.0              # 生命 < 20% 的累计秒数
var dark_s := 0.0               # 灯火熄灭的累计秒数
var dark_dmg := 0.0             # 熄灯每秒 3 点的持续掉血（不进 dmg_log，单独记）
var hits := 0                   # 受击次数
var taken_last := 0.0
var taken_window := 0.0         # 当前采样窗口内的承伤
var mire_win := 0.0             # 当前采样窗口内站在溟痕里的秒数（g.in_mire ≥ 0.5；难度曲线审计 docs/146，只读）
var hpmin_win := 100            # 当前采样窗口内主控最低生命百分比（同上）
var lampmin_win := 100.0        # 当前采样窗口内最低灯火（docs/146 §6 灯火统计，只读）
var lamp_gain: Dictionary = {}  # 灯火回补按来源累计（实际加上的量）：灯油 / 精英灯油 / 灯标 / 围猎 / 商人 / 其他（帧间净增减去已记的）
var lamp_loss: Dictionary = {}  # 灯火损失按来源累计：受击 / 圈外 / 冲撞吸灯 / 其他
var lamp_taken: Array = [0.0, 0.0, 0.0, 0.0]   # 各灯火档（通明 / 摇曳 / 暗淡 / 寂灭）里的承伤
var _lamp_prev := -1.0
var _lamp_noted := 0.0          # 本帧已按来源记过的净变化（+ 回补 / − 损失），tick 里用来算「其他」
var m3: Dictionary = {}         # 凯尔希 Mon3tr 血条遥测（downs 倒地次数 / down_secs 不在场秒数 / hurt 受伤 / regen 回血 / heal_to_m3 治疗拍给它的量 / heal_ticks_m3 拍数）；没有 Mon3tr 的局不写
var win_src: Dictionary = {}    # 当前采样窗口内按来源的承伤（docs/82：6–9 分钟承伤来源）
var heal_last: Dictionary = {}  # 上一个采样点的 heal_log（窗口治疗 = 增量）
var last_src := ""              # 最近一次掉血的来源（死因）
var last_log: Dictionary = {}
var boss_seen: Dictionary = {}  # id -> {type, t0, t1}
# Boss 在场采样（每秒一次，Boss与怪物 9/30 要：区分「杂兵墙挡输出」和「Boss 本身难打」）：
# 全场活着的敌人数、Boss 周围 300 内的敌人数、这一秒 Boss 掉的血占全队输出的比例
var boss_acc := 0.0
var boss_samp: Dictionary = {}   # key -> {n, alive, alive_pk, near, near_pk, hp_last, on_boss, out}
var out_last := 0.0
# docs/117 Boss 节奏审计（只读，不影响同 seed）：每 15 秒一个窗口，从 Boss 登场记到倒下 / 撤场，
# 看哪一段只在刮血、没有新东西发生（出招 / 小怪 / 受击都少）。key -> {out0, hits0, moves0}（上一个窗口结束时的基准值）
const BOSS_WIN_S := 15.0
var boss_win_acc := 0.0
var boss_win_base: Dictionary = {}   # key -> {out, hits, moves}
var elite_t: Dictionary = {}    # "<op>:<elite>" -> 秒
var recruit_t: Array = []       # 每名干员入队时间
var squad_n := 0
var dist_moved := 0.0
var last_pos := Vector2.ZERO
var still_s := 0.0              # 站着不动的累计秒数
var lv_marks := {}              # 2:00 / 5:00 / 8:00 时的等级（玩家局用；平衡局沿用 autotest 自己的）
var peak: Array = [0, 0, 0, 0, 0]   # 同屏数量峰值：敌人 / 敌方弹幕（含抛射物）/ 我方子弹 / 特效 / 飘字（后期画面优化的量化，2026-09-27）
var peak_min: Array = []            # 每分钟的峰值，同上 5 项；peak_min[i] 为第 i 分钟
# ---- 死前 15 秒（2026-09-27 数值要：「后期暴毙」根因）：每次掉血进环形缓冲，结束 / 不死模式托底时写一份快照
const RING_S := 15.0
var ring: Array = []            # {t, src, amt, hp_after, boss, zone_out}
var ring_ctx: Array = []        # [t, dt, corrode_pool, in_mire, 敌人数, 敌弹数, 熄灯]
var floor_snaps: Array = []     # 不死模式每次托底的快照（最多前 5 次）
var floor_seen := 0
var kill_hits: Dictionary = {}  # 普通怪击杀时挨了几下（docs/116 §6 打几下才死）："分钟:类型" -> [只数, 受击次数和, 首次受击到死亡秒数和]
# ---- 作战记录（局终统计界面，docs/77，2026-10-12）：按干员拆的输出 / 击杀 / 技能次数等。只累加、不读随机数，不影响同 seed 复现
const BIN_S := 10.0             # 时间线分箱（局内秒）
var op_out: Dictionary = {}     # 干员 id（没有干员的来源记 "_other"：援护 / 藏品 / 地雷……）-> {来源名: 有效伤害}
var op_kills: Dictionary = {}   # 干员 id -> 参与击杀数：敌人死前 KILL_WINDOW 秒内命中过它的干员各记一次（"_other" = 藏品 / 支援）
const KILL_WINDOW := 3.0
var op_casts: Dictionary = {}   # 干员 id -> 技能发动次数（spend_sp）
var out_bins: Array = []        # 每 10 秒一格：{干员 id: 有效伤害}
var joins: Array = []           # 入队记录：{id, name, en, col, leader, t, left, cls}（被事件替换的干员 left = 离队秒数）
var best_hit: Dictionary = {}   # 最高单次伤害：{v, src, op, t}
var dodges := 0                 # 闪避次数（enemy_hit 判定闪避）
var dashes := 0                 # 冲刺次数
var blocks := 0                 # 护盾抵挡次数
var shield_abs := 0.0           # 护盾层数抵挡掉的原始伤害合计（遥测，护盾复核 10-30）
var shield_t0 := -1.0           # 首次拥有护盾层数的时刻
var shield_peak := 0            # 护盾层数上限的峰值
var chests := 0                 # 打开补给箱
var nodes := 0                  # 翻开的节点卡（docs/154，取代「海嗣祭坛」计数 altars）
var reaper_drain_deaths := 0    # 钵海收割者临战自身流失耗死的只数（docs/95 §18，和被打死的分开）
var ingots_got := 0             # 获得源石锭（gain_ingots，含熔铸后进池的）
var ingots_spent := 0           # 商店花掉的源石锭（购买 + 刷新）
# 击倒者归属（docs/77 §2.1）：每次扣血记成 [时刻, 归属键, 死因, 量]，归属键 = "e:<敌人类型>" 或 "env:<zone|mire|dark|…>"；
# 侵蚀 / 侵蚀创口 / 神经损伤这类持续伤害记给最近 10 秒施加得最多的敌人（溟痕里的神经损伤算环境）。只记账，不读随机数
const BLAME_S := 3.0
var blame: Array = []
var hit_type := ""              # enemy_hit 这一下的来源敌人类型
var aura_type := ""             # 最近一次神经光环的敌人类型
var appliers: Dictionary = {}   # 状态 -> [[时刻, 敌人类型（"" = 环境）, 量]]
var lamp_s: Array = [0.0, 0.0, 0.0, 0.0]   # 灯火四档累计秒数：通明（≥ 70）/ 摇曳（30–69）/ 暗淡（< 30）/ 寂灭（0）
# ---- 本地保存
var saved := false

# ---- 遥测补洞 1（docs/200）：只在 --telemetry=full 下计算（云端批跑缺省开；本地 / 对内包 / 对外包不开，正式游戏路径只多一次布尔判断）。
# 全部只读：不用随机数、不改状态，同 seed TRACE 不变。
var rich := false
var hit_elite := false          # combat.enemy_hit 设置：这一下的来源是不是精英 / 是不是 Boss 来源
var hit_boss := false
var hits2: Array = []           # 最近 15 秒逐笔掉血：[t, 来源, 归属键, 精英(0/1), 上限截前量, 实际扣血, 之后生命]（持续 / 环境来源 0.5 秒内合并）
var tl: Array = []              # 死前时间线：每 0.5 秒一格 [t, 生命, 灯火, 在场敌人, 150 内, 300 内, 敌弹, 8 向被堵数(200 内), 无敌(0/1), 可用冲刺, 队伍人数]，保留 15 秒
var tl_next := 0.0
var near_miss: Array = []       # 险境快照：生命首次 < 20% 时存（每局最多 3 份，两份间隔 ≥ 20 秒）：{t, hp, tl, src}
var near_cool := -99.0
var ult: Array = []             # 占位（终结技 / 连携 / 连携终结技）：[t, 干员, kind(q/e/chain), 命中, 伤害, 击杀, 生命%]；ult-proto 合入后对齐字段名，现在不写
var cap_stats := {"hits": 0, "zero": 0, "pre": 0.0, "post": 0.0, "one_n": 0, "one_cut": 0.0, "boss_n": 0, "boss_cut": 0.0, "any_n": 0, "any_cut": 0.0, "big_n": 0}
## 医疗差距遥测（docs/88，只在 --balance 下记，g.bot == null 时各调用点直接跳过）：按 0–3 / 3–6 / 6–9 / 9+ 分钟分段
##   sus.heal["来源·子项"] = [实际回进去, 给出的量（含溢出）]；sus.dr[干员 id] = 干员减伤（dmg_taken_mult，护甲前）挡掉的伤害；
##   sus.clean[corrode / nerve] = 净化清掉的侵蚀池 / 神经损伤量；sus.lit = 只因「照亮」（灯光外）多打的伤害
var sus: Dictionary = {}


func sus_seg() -> Dictionary:
	var k: String = "m0" if g.t < 180.0 else ("m3" if g.t < 360.0 else ("m6" if g.t < 540.0 else "m9"))
	if not sus.has(k):
		sus[k] = {"heal": {}, "dr": {}, "clean": {}, "lit": 0.0}
	return sus[k]


func note_m3(key: String, v: float) -> void:
	m3[key] = float(m3.get(key, 0.0)) + v


func note_heal_sub(src: String, sub: String, got: float, offered: float) -> void:
	var h: Dictionary = sus_seg().heal
	var key: String = src if sub == "" else "%s·%s" % [src, sub]
	var a: Array = h.get(key, [0.0, 0.0])
	h[key] = [float(a[0]) + got, float(a[1]) + offered]


func note_dr(op_id: String, saved_dmg: float) -> void:
	if saved_dmg > 0.0:
		var d: Dictionary = sus_seg().dr
		d[op_id] = float(d.get(op_id, 0.0)) + saved_dmg


func note_clean(kind: String, amt: float) -> void:
	if amt > 0.0:
		var c: Dictionary = sus_seg().clean
		c[kind] = float(c.get(kind, 0.0)) + amt
var build: Dictionary = {}


func _init(game: Game) -> void:
	g = game
	var f := FileAccess.open("res://data/build.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			build = d
	rich = Cfg.dev_args().has("--telemetry=full")


## 每帧采样（只观察，不改状态、不用随机数，所以不影响同 seed 复现）
func tick(dt: float) -> void:
	var t: float = g.t
	if last_pos == Vector2.ZERO:
		last_pos = g.ppos
	var step: float = g.ppos.distance_to(last_pos)
	dist_moved += step
	if step < 0.5:
		still_s += dt
	last_pos = g.ppos
	if g.hp < g.max_hp * 0.35:
		low_hp_s += dt
	if g.rfx.king_n > 0 and g.rfx.king_low():
		king_low_s += dt   # 危险感回调（10-28）：带国王套且处于低血的累计秒数
	if g.hp < g.max_hp * 0.2:
		low20_s += dt
	if g.in_mire >= 0.5:
		mire_win += dt
	lampmin_win = minf(lampmin_win, g.lamp)
	if _lamp_prev >= 0.0:
		var rest: float = g.lamp - _lamp_prev - _lamp_noted
		if rest > 0.01:
			lamp_gain["其他"] = float(lamp_gain.get("其他", 0.0)) + rest
		elif rest < -0.01:
			lamp_loss["其他"] = float(lamp_loss.get("其他", 0.0)) - rest
	_lamp_prev = g.lamp
	_lamp_noted = 0.0
	hpmin_win = mini(hpmin_win, int(100.0 * g.hp / maxf(1.0, g.max_hp)))
	lamp_s[lamp_tier(g.lamp)] += dt
	if g.lamp <= 0.0:
		dark_s += dt
		dark_dmg += 3.0 * dt
		if g.hp <= 3.0 * dt * 2.0:
			last_src = "dark"
	# 承伤：比较 dmg_log 的增量，记录受击次数与最近的来源
	var tot := 0.0
	var inc_best := 0.0
	for k in g.dmg_log:
		var v: float = g.dmg_log[k]
		tot += v
		var inc: float = v - float(last_log.get(k, 0.0))
		if inc > 0.01:
			win_src[k] = float(win_src.get(k, 0.0)) + inc
			ring.append({"t": snappedf(t, 0.1), "src": k, "amt": snappedf(inc, 0.1), "hp_after": int(g.hp), "boss": _is_boss_src(k),
				"zone_out": g.zone_state > 0 and g.ppos.distance_to(g.zone_c) > g.zone_r})
		if inc > inc_best:
			inc_best = inc
			last_src = k
		last_log[k] = v
	if tot > taken_last + 0.01:
		hits += 1
		taken_window += tot - taken_last
		lamp_taken[lamp_tier(g.lamp)] += tot - taken_last
	taken_last = tot
	ring_ctx.append([t, dt, g.corrode_pool, g.in_mire, g.enemies.size(), g.ebullets.size() + g.lobs.size(), 1 if g.lamp <= 0.0 else 0])
	while not ring.is_empty() and ring[0].t < t - RING_S:
		ring.pop_front()
	while not ring_ctx.is_empty() and ring_ctx[0][0] < t - RING_S:
		ring_ctx.pop_front()
	if g.floor_hits > floor_seen:
		floor_seen = g.floor_hits
		if floor_snaps.size() < 5:
			floor_snaps.append(ring_snapshot())
	# Boss 出现 / 击杀时间；tv = 第一次可受伤的时刻（「可受伤起算」的击杀用时 = t1 − tv），shield = 阶段护盾累计秒数，
	# gates = 已过的卡点数（docs/38 B1 ⑤）。最终 Boss 死的同一帧就判胜利，t1 记不到，用整局 t 代替
	for b in g.bosses:
		var key := str(b.get("id", b.type))
		if not boss_seen.has(key):
			boss_seen[key] = {"type": b.type, "t0": int(t), "t1": -1, "tv": -1, "shield": 0.0, "gates": 0}
		var bs: Dictionary = boss_seen[key]
		if b.get("retreated", false):
			if not bs.has("retreat"):
				bs["retreat"] = int(t)   # 最终 Boss 登场时撤场：不算击杀，t1 保持 −1
		elif b.dead and bs.t1 < 0:
			bs.t1 = int(t)
		if bs.tv < 0 and not b.invuln and not b.dead:
			bs.tv = int(t)
		bs.shield = snappedf(b.get("shield_t", 0.0), 0.1)
		bs.gates = b.get("gates_passed", 0)
		if b.has("panic_n"):
			# 主教慌乱（协调人 9/30）：慌乱触发次数、慌乱期间掉血占最大生命的比例
			bs["panic_n"] = int(b.panic_n)
			bs["panic_hit"] = snappedf(float(b.get("panic_dmg", 0.0)) / maxf(1.0, float(b.maxhp)), 0.01)
	# docs/117 Boss 节奏审计：每 15 秒一个窗口，记 hp 剩余比例、这窗口的全队输出、受击次数、Boss 出招次数（telegraph.gd
	# e.moves_n）、全场怪物数——用来找「只在刮血、没有新东西发生」的空档。只读，不影响同 seed
	boss_win_acc += dt
	if boss_win_acc >= BOSS_WIN_S:
		boss_win_acc -= BOSS_WIN_S
		var win_out := 0.0
		for k in g.dmg_out:
			win_out += float(g.dmg_out[k])
		for b in g.bosses:
			if b.get("retreated", false) or b.get("friendly", false):
				continue
			var key := str(b.get("id", b.type))
			var bs: Dictionary = boss_seen.get(key, {})
			if bs.is_empty():
				continue
			if not boss_win_base.has(key):
				boss_win_base[key] = {"out": win_out, "hits": hits, "moves": int(b.get("moves_n", 0))}
			var base: Dictionary = boss_win_base[key]
			if not bs.has("windows"):
				bs["windows"] = []
			bs["windows"].append({"t": int(t) - int(bs.t0), "hp": 0.0 if b.dead else snappedf(float(b.hp) / maxf(1.0, float(b.maxhp)), 0.01),
				"out": int(win_out - float(base.out)), "hits": hits - int(base.hits), "moves": int(b.get("moves_n", 0)) - int(base.moves),
				"en": g.enemies.size()})
			base.out = win_out
			base.hits = hits
			base.moves = int(b.get("moves_n", 0))
	boss_acc += dt
	if boss_acc >= 1.0:
		boss_acc -= 1.0
		var out_now := 0.0
		for k in g.dmg_out:
			out_now += float(g.dmg_out[k])
		var out_inc: float = maxf(0.0, out_now - out_last)
		out_last = out_now
		for b in g.bosses:
			if b.dead or b.get("retreated", false) or b.get("friendly", false):
				continue
			var key := str(b.get("id", b.type))
			if not boss_samp.has(key):
				boss_samp[key] = {"n": 0, "alive": 0, "alive_pk": 0, "near": 0, "near_pk": 0, "hp_last": float(b.hp), "on_boss": 0.0, "out": 0.0}
			var sp: Dictionary = boss_samp[key]
			var near := 0
			for j in g.enemies_sys.query(b.pos, 300.0):
				var e: Dictionary = g.enemies[j]
				if not e.dead and not e.get("boss", false) and not e.get("chest", false) and not e.get("friendly", false):
					near += 1
			var alive: int = g.enemies.size()
			sp.n += 1
			sp.alive += alive
			sp.alive_pk = maxi(sp.alive_pk, alive)
			sp.near += near
			sp.near_pk = maxi(sp.near_pk, near)
			if not b.get("invuln", false):
				sp.on_boss += maxf(0.0, float(sp.hp_last) - float(b.hp))
				sp.out += out_inc
			sp.hp_last = float(b.hp)
			var bs2: Dictionary = boss_seen.get(key, {})
			if not bs2.is_empty():
				bs2["en_alive"] = int(round(float(sp.alive) / sp.n))
				bs2["en_alive_pk"] = sp.alive_pk
				bs2["en_near"] = int(round(float(sp.near) / sp.n))
				bs2["en_near_pk"] = sp.near_pk
				bs2["on_boss"] = snappedf(sp.on_boss / maxf(1.0, sp.out), 0.01)   # 可受伤期间：Boss 掉血 ÷ 全队输出
	# 精英化 / 入队时间
	for o in g.squad.ops:
		var ek := "%s:%d" % [o.id, o.elite]
		if o.elite > 0 and not elite_t.has(ek):
			elite_t[ek] = int(t)
	if g.squad.size() > squad_n:
		if squad_n > 0:
			recruit_t.append(int(t))
		squad_n = g.squad.size()
	for m in [120, 300, 480]:
		if t >= m and not lv_marks.has(m):
			lv_marks[m] = g.level
	var mi := int(t / 60.0)
	while peak_min.size() <= mi:
		peak_min.append([0, 0, 0, 0, 0])
	var now := [g.enemies.size(), g.ebullets.size() + g.lobs.size(), g.bullets.size(), g.fx.size(), g.texts.size()]
	for i in 5:
		peak[i] = maxi(peak[i], now[i])
		peak_min[mi][i] = maxi(peak_min[mi][i], now[i])
	if t >= sample_next:
		sample_next += SAMPLE_EVERY
		# 窗口内按来源的承伤 dsrc / 治疗 hsrc（docs/82，只记 ≥ 1 的来源）、最大生命 mhp：看「哪一段、谁打的、谁奶的」
		var dsrc := {}
		for k in win_src:
			if win_src[k] >= 1.0:
				dsrc[k] = int(win_src[k])
		var hsrc := {}
		for k in g.heal_log:
			var hv: float = float(g.heal_log[k]) - float(heal_last.get(k, 0.0))
			if hv >= 1.0:
				hsrc[k] = int(hv)
		heal_last = g.heal_log.duplicate()
		curve.append({"t": int(t), "hp": int(100.0 * g.hp / maxf(1.0, g.max_hp)), "lamp": int(g.lamp), "lv": g.level,
			"kills": g.kills, "squad": g.squad.size(), "taken": int(taken_window), "enemies": g.enemies.size(),
			"zone": g.zone_state, "boss": int(_boss_alive()), "mhp": int(g.max_hp), "dsrc": dsrc, "hsrc": hsrc,
			# 曲线审计（docs/116）：累计全队输出 outc、普通怪生命倍率 hpm（时间 × 难度 × 全局，不含密度换算）、主控每秒回复 rg
			"outc": int(out_last), "hpm": snappedf(g.combat.enemy_hp_time_mult() * float(g.dmod.enemy_hp) * g.enemy_hp_mult, 0.01),
			"rg": snappedf(g.combat.regen_per_sec(), 0.01),
			# 难度曲线审计（docs/146，只读）：窗口内最低生命 %、站溟痕秒数，采样时的溟痕片数、在场精英数、敌弹数
			"hpmin": hpmin_win, "lampmin": int(lampmin_win), "mire_s": snappedf(mire_win, 0.1), "mires": g.mires.size(), "elites": _elites_alive(), "ebul": g.ebullets.size() + g.lobs.size()})
		taken_window = 0.0
		mire_win = 0.0
		hpmin_win = 100
		lampmin_win = g.lamp
		win_src = {}
	if rich:
		_snap(t)


## lose_hp 调用（rich 下）：一次扣血的各级上限截前 / 截后量。one = 来源自带单次上限（围猎事件敌人），boss = Boss 保护（单发 / 持续 / 2 秒 / 满血保护合计），any = 任意来源 2 秒上限
func cap_note(pre_all: float, pre_boss: float, pre_any: float, post: float, src: String, boss: bool) -> void:
	if pre_all <= 0.0:
		return
	var one := pre_all - pre_boss
	var bc := pre_boss - pre_any
	var ac := pre_any - post
	cap_stats.hits += 1
	cap_stats.pre += pre_all
	cap_stats.post += post
	if post <= 0.0:
		cap_stats.zero += 1
	if one > 0.01:
		cap_stats.one_n += 1
		cap_stats.one_cut += one
	if bc > 0.01:
		cap_stats.boss_n += 1
		cap_stats.boss_cut += bc
	if ac > 0.01:
		cap_stats.any_n += 1
		cap_stats.any_cut += ac
	if pre_all - post >= pre_all * 0.5 and pre_all - post > 1.0:
		cap_stats.big_n += 1   # 被截掉一半以上的大头
	var direct := src == "bullet" or src == "tear"
	for p in DIRECT_PREFIX:
		if src.begins_with(p):
			direct = true
	var nm := src
	if src == "bullet" and hit_boss:
		nm = "bullet_boss"   # Boss 弹与普通敌弹分开命名（dmg_log 里仍叫 bullet，别的报告不受影响）
	var key: String = str(_attr(src)[0])
	var t := snappedf(g.t, 0.1)
	if not direct and not hits2.is_empty():
		var l: Array = hits2[hits2.size() - 1]
		if l[1] == nm and t - float(l[0]) < 0.5:
			l[4] = snappedf(float(l[4]) + pre_all, 0.1)
			l[5] = snappedf(float(l[5]) + post, 0.1)
			l[6] = int(g.hp)
			return
	hits2.append([t, nm, key, 1 if (direct and hit_elite) else 0, snappedf(pre_all, 0.1), snappedf(post, 0.1), int(g.hp)])
	while not hits2.is_empty() and float(hits2[0][0]) < g.t - RING_S:
		hits2.pop_front()


## 0.5 秒一格的死前时间线 + 险境快照（rich 下，tick 末尾）
func _snap(t: float) -> void:
	if t < tl_next:
		return
	tl_next = t + 0.5
	var pp: Vector2 = g.ppos
	var n150 := 0
	var n300 := 0
	var mask := 0
	for e in g.enemies:
		if e.dead:
			continue
		var d2: float = e.pos.distance_squared_to(pp)
		if d2 < 90000.0:
			n300 += 1
			if d2 < 22500.0:
				n150 += 1
			if d2 < 40000.0:
				mask |= 1 << posmod(int(floor((e.pos - pp).angle() / (TAU / 8.0))), 8)
	var blocked := 0
	for i in 8:
		if (mask & (1 << i)) != 0:
			blocked += 1
	tl.append([snappedf(t, 0.1), int(g.hp), int(g.lamp), g.enemies.size(), n150, n300, g.ebullets.size() + g.lobs.size(), blocked,
		1 if g.invuln > 0.0 else 0, g.dash_left(), g.squad.size()])
	while not tl.is_empty() and float(tl[0][0]) < t - RING_S:
		tl.pop_front()
	if g.hp > 0.0 and g.hp < g.max_hp * 0.2 and near_miss.size() < 3 and t - near_cool >= 20.0:
		near_cool = t
		var tot := {}
		for h in hits2:
			tot[h[1]] = snappedf(float(tot.get(h[1], 0.0)) + float(h[5]), 0.1)
		near_miss.append({"t": snappedf(t, 0.1), "hp": int(g.hp), "mhp": int(g.max_hp), "tl": tl.duplicate(true), "src": tot})


## 普通怪死亡时记一笔（combat 击杀结算调用）：按分钟 × 类型累计只数与受击次数，精英 / Boss / 友方不记
func on_kill(e: Dictionary) -> void:
	if e.elite or e.boss or e.get("friendly", false):
		return
	var k := "%d:%s" % [int(g.t / 60.0), e.type]
	if not kill_hits.has(k):
		kill_hits[k] = [0, 0, 0.0]
	kill_hits[k][0] += 1
	kill_hits[k][1] += int(e.hits)
	kill_hits[k][2] = snappedf(kill_hits[k][2] + (g.t - float(e.get("h0", g.t))), 0.01)   # 首次受击 → 死亡的秒数和（实际 TTK）


## 灯火档位（docs/76 §5，以 hud_bars.gd 为准）：0 通明 ≥ 70 / 1 摇曳 30–69 / 2 暗淡 < 30 / 3 寂灭 0
static func lamp_tier(v: float) -> int:
	if v <= 0.0:
		return 3
	if v < 30.0:
		return 2
	if v < 70.0:
		return 1
	return 0


## ---- 作战记录计数（combat / squad / character / game 调用；docs/77）
## 一次有效伤害：eff = 实际扣掉的生命（同 dmg_out），raw = 这一下算出来的伤害（不封顶到剩余生命，「最高单次」用）
func on_dmg(e: Dictionary, eff: float, raw: float, hd: Dictionary = {}) -> void:
	var h: Dictionary = hd if not hd.is_empty() else g.hit   # combat.damage 显式传（docs/101 B7 ⑤）
	var op: String = str(h.get("op", ""))
	if op == "":
		op = "_other"
	# 参与击杀：敌人身上记「谁最近一次命中我」（只是记账字段，不参与任何玩法判定）
	var hb = e.get("_hb")
	if hb == null:
		hb = {}
		e["_hb"] = hb
	hb[op] = g.t
	var src: String = str(h.get("src", "?"))
	var d: Dictionary = op_out.get(op, {})
	if d.is_empty():
		op_out[op] = d
	d[src] = float(d.get(src, 0.0)) + eff
	var bi := int(g.t / BIN_S)
	while out_bins.size() <= bi:
		out_bins.append({})
	var b: Dictionary = out_bins[bi]
	b[op] = float(b.get(op, 0.0)) + eff
	if raw > float(best_hit.get("v", 0.0)):
		best_hit = {"v": raw, "src": src, "op": op, "t": g.t}


## 参与击杀（combat.damage 里 kill 之前调用）：死前 KILL_WINDOW 秒内命中过这个敌人的干员各记一次；
## 致死那一下的干员也在 _hb 里（on_dmg 先记）。一个敌人可以记给多名干员，所以各行合计可能大于总击杀
func on_kill_credit(e: Dictionary) -> void:
	var hb = e.get("_hb")
	e.erase("_hb")
	if e.get("dead", false) or e.get("chest", false) or e.get("friendly", false) or hb == null:
		return
	for op in hb:
		if float(hb[op]) >= g.t - KILL_WINDOW:
			op_kills[op] = int(op_kills.get(op, 0)) + 1


## 伤害来源字典（enemy_hit 的 src：敌人本体 / 子弹 / 预警招式）→ 敌人类型；Boss 子弹没写类型时记在场的第一个 Boss
func src_type(src: Dictionary) -> String:
	var ty := str(src.get("type", src.get("src_type", "")))
	if ty == "" and src.get("boss", false):
		for b in g.bosses:
			if not b.dead and not b.get("friendly", false):
				return str(b.type)
	return ty


## 状态施加（侵蚀进池量 / 侵蚀创口层数 / 神经损伤量）：记下是谁施加的
func on_status(kind: String, ty: String, amt: float) -> void:
	var l: Array = appliers.get(kind, [])
	if l.is_empty():
		appliers[kind] = l
	if not l.is_empty() and str(l[l.size() - 1][1]) == ty and g.t - float(l[l.size() - 1][0]) < 0.5:
		l[l.size() - 1][2] = float(l[l.size() - 1][2]) + amt   # 同一来源半秒内合并（溟痕每帧都记）
		return
	l.append([g.t, ty, amt])
	while l.size() > 1 and float(l[0][0]) < g.t - 10.0:
		l.pop_front()


## 某种状态最近 10 秒施加得最多的来源（"" = 环境 / 不明）
func applier(kind: String) -> String:
	var l: Array = appliers.get(kind, [])
	var acc := {}
	var best := ""
	var bv := -1.0
	for x in l:
		if float(x[0]) >= g.t - 10.0 or l.size() == 1:
			acc[x[1]] = float(acc.get(x[1], 0.0)) + float(x[2])
			if acc[x[1]] > bv:
				bv = acc[x[1]]
				best = x[1]
	if best == "" and not l.is_empty():
		best = str(l[l.size() - 1][1])
	return best


const DOT_CAUSE := {"corrode": "侵蚀", "wound": "侵蚀创口", "nerve": "神经损伤"}
const DIRECT_PREFIX := ["contact_", "atk_", "boss_", "blast_", "shock_"]


## 来源 → [归属键, 持续伤害的死因]（on_lose 与 cap_note 共用；只读）
func _attr(src: String) -> Array:
	var key := ""
	var cause := ""
	if DOT_CAUSE.has(src):
		cause = DOT_CAUSE[src]
		var ty := applier(src)
		key = ("e:" + ty) if ty != "" else ("env:mire" if src == "nerve" else "env:" + src)
	elif src == "bullet":
		key = ("e:" + hit_type) if hit_type != "" else "env:bullet"
	elif src == "tear":
		key = "e:tear"
	else:
		for p in DIRECT_PREFIX:
			if src.begins_with(p):
				key = "e:" + src.substr(p.length())
		if key == "":
			key = "env:" + src   # zone 黑潮 / mire 溟痕 / dark 寂灭 / relic 藏品代价
	return [key, cause]


## lose_hp 每次扣血调用：换算成归属键
func on_lose(amount: float, src: String) -> void:
	if amount <= 0.0:
		return
	var kc := _attr(src)
	var key: String = kc[0]
	var cause: String = kc[1]
	blame.append([g.t, key, cause, amount])
	while blame.size() > 1 and float(blame[0][0]) < g.t - BLAME_S - 2.0:
		blame.pop_front()


## 击倒者：最近 3 秒造成伤害最多的归属键；死因 = 这个归属里占比最大的持续伤害（直接攻击为空串）
func killer() -> Dictionary:
	var by := {}
	var causes := {}
	for x in blame:
		if float(x[0]) < g.t - BLAME_S:
			continue
		by[x[1]] = float(by.get(x[1], 0.0)) + float(x[3])
		var c: Dictionary = causes.get(x[1], {})
		causes[x[1]] = c
		c[x[2]] = float(c.get(x[2], 0.0)) + float(x[3])
	var best := ""
	var bv := -1.0
	for k in by:
		if by[k] > bv:
			bv = by[k]
			best = k
	if best == "" and not blame.is_empty():
		best = str(blame[blame.size() - 1][1])
		causes[best] = {str(blame[blame.size() - 1][2]): 1.0}
	var cause := ""
	var cv := -1.0
	for c in causes.get(best, {}):
		if causes[best][c] > cv:
			cv = causes[best][c]
			cause = c
	return {"key": best, "cause": cause}


func on_cast(op_id: String) -> void:
	op_casts[op_id] = int(op_casts.get(op_id, 0)) + 1


## 入队 / 离队（squad.add / squad.remove）：名字、颜色等当场记下，被替换掉的干员结算时还能画
func on_join(op) -> void:
	for j in joins:
		if j.id == op.id and int(j.left) < 0:
			return
	# 换下后又被招回来（中途更换队友）：沿用原来那条，离队的这段记进 away（作战记录的在队时长扣掉它）
	for j in joins:
		if j.id == op.id:
			j["away"] = float(j.get("away", 0.0)) + maxf(0.0, g.t - float(j.left))
			j.left = -1.0
			return
	var c: Color = op.col()
	joins.append({"id": op.id, "name": op.display_name(), "en": str(op.def.get("en", op.id.to_upper())), "col": [c.r, c.g, c.b],
		"leader": op.is_leader, "t": g.t, "left": -1.0, "cls": str(op.get("cls"))})


func on_leave(op_id: String) -> void:
	for j in joins:
		if j.id == op_id and float(j.left) < 0.0:
			j.left = g.t


func _boss_alive() -> bool:
	for b in g.bosses:
		if not b.dead:
			return true
	return false


## 来源是不是真 Boss：boss_<类型>（预警招式，普通怪如引痕者 / 收割者也用这个前缀）和 contact_<类型> 都按类型判，
## 类型在 enemies.json 里 role 为 boss 才算（2026-09-27 数值指出 boss_tracer 被误算成 Boss）
func _is_boss_src(k: String) -> bool:
	var ty := ""
	if k.begins_with("boss_"):
		ty = k.substr(5)
	elif k.begins_with("contact_"):
		ty = k.substr(8)
	else:
		return false
	return str(D.ENEMIES.get(ty, {}).get("role", "")) == "boss"


## 最近 15 秒的掉血明细与环境峰值（结束时写进 end.last15，不死模式每次托底写进 floors）
func ring_snapshot() -> Dictionary:
	var cp := 0.0
	var mire_s := 0.0
	var en := 0
	var eb := 0
	var dark_s := 0.0
	for c in ring_ctx:
		cp = maxf(cp, c[2])
		if c[3] > 0.3:
			mire_s += c[1]
		en = maxi(en, c[4])
		eb = maxi(eb, c[5])
		dark_s += c[1] * c[6]
	var corrode_out := 0.0   # 这 15 秒侵蚀池流出合计（dmg_log 的 corrode 来源）
	var nerve_bursts := 0    # 神经损伤溢出次数（每次溢出记一笔 nerve 来源的掉血）
	for h in ring:
		if h.src == "corrode":
			corrode_out += h.amt
		elif h.src == "nerve":
			nerve_bursts += 1
	return {"t": snappedf(g.t, 0.1), "hits": ring.duplicate(true), "corrode_peak": snappedf(cp, 0.1), "mire_s": snappedf(mire_s, 0.1),
		"corrode_out": snappedf(corrode_out, 0.1), "nerve_bursts": nerve_bursts,
		"enemies_peak": en, "ebullets_peak": eb, "dark_s": snappedf(dark_s, 0.1)}


## 结束时的局面（死因 × 缩圈阶段 × Boss 在场；A/B 缩圈规则用，2026-09-27）
func end_ctx() -> Dictionary:
	var out: float = g.ppos.distance_to(g.zone_c) - g.zone_r
	var ec := {"t": int(g.t), "src": last_src, "zone_state": g.zone_state, "zone_phase": g.combat.zone_phase if g.zone_state > 0 else -1,
		"zone_out": out > 0.0, "boss": _boss_alive(), "hp": int(g.hp), "last15": ring_snapshot(), "killer": killer()}   # killer：最近 3 秒归属键 + 持续伤害施加者（docs/200，原来只给结算界面）
	if rich:
		ec["tl"] = tl
		ec["hits2"] = hits2
		ec["near"] = near_miss
	return ec


static func _rounded(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		o[k] = int(d[k])
	return o


## 灯火增减按来源记账（docs/146 §6，只读）：调用方传实际变化量（夹到 0 / 上限之后的差）
func lamp_note(src: String, delta: float) -> void:
	if absf(delta) < 0.001:
		return
	_lamp_noted += delta
	if delta > 0.0:
		lamp_gain[src] = float(lamp_gain.get(src, 0.0)) + delta
	else:
		lamp_loss[src] = float(lamp_loss.get(src, 0.0)) - delta


func _elites_alive() -> int:
	var n := 0
	for e in g.enemies:
		if e.elite and not e.dead and not e.boss:
			n += 1
	return n


## 最后一个不满 30 秒的采样窗口（死前那一段，docs/82）：承伤 / 按来源承伤 / 按来源治疗，字段同 curve
func curve_tail() -> Dictionary:
	var dsrc := {}
	for k in win_src:
		if win_src[k] >= 1.0:
			dsrc[k] = int(win_src[k])
	var hsrc := {}
	for k in g.heal_log:
		var hv: float = float(g.heal_log[k]) - float(heal_last.get(k, 0.0))
		if hv >= 1.0:
			hsrc[k] = int(hv)
	return {"t": int(g.t), "t0": int(sample_next - SAMPLE_EVERY), "taken": int(taken_window), "mhp": int(g.max_hp), "dsrc": dsrc, "hsrc": hsrc}


## 整局指标块（记录里的 "bot" 字段：名字沿用平衡工具的历史叫法，玩家局 profile = "player"）
func metrics(profile: String) -> Dictionary:
	var t: float = maxf(1.0, g.t)
	return {"profile": profile, "hits": hits, "hits_pm": snappedf(hits / t * 60.0, 0.1), "taken": int(taken_last),
		"taken_pm": int(taken_last / t * 60.0), "low_hp_s": int(low_hp_s), "king_low_s": int(king_low_s), "low20_s": int(low20_s), "dark_s": int(dark_s), "dark_dmg": int(dark_dmg), "death_src": last_src,
		"lamp_s": lamp_s.map(func(v): return int(v)), "lamp_gain": _rounded(lamp_gain), "lamp_loss": _rounded(lamp_loss), "lamp_taken": lamp_taken.map(func(v): return int(v)), "lamp_end": int(g.lamp),
		"moved_pm": int(dist_moved / t * 60.0), "still_pct": int(100.0 * still_s / t),
		"bosses": boss_seen.values(), "elite_t": elite_t, "recruit_t": recruit_t, "curve": curve, "curve_tail": curve_tail(),
		"peak": peak, "peak_min": peak_min, "end": end_ctx(), "floors": floor_snaps, "reaper_drain_deaths": reaper_drain_deaths}


## 整局记录（平衡测试打印的 BALANCE 同一份；字段改名 / 删除要同步 tools/balance_run.py 与 SCHEMA）
func record(marks = null) -> Dictionary:
	var prof_name := "player"
	if g.bot != null:
		prof_name = g.bot.profile
	var bot_block: Dictionary = metrics(prof_name) if (g.bot != null or g.mode == g.Mode.PLAY) else {}
	var rec := {"meta": g.meta_cells, "win": g.state == g.S.WIN or g.victory.recorded, "t": int(g.t), "lv": g.level, "marks": lv_marks if marks == null else marks, "lv_times": g.lv_times,
		"ops": g.squad.ops.map(func(o): return {"id": o.id, "elite": o.elite, "prog": o.prog}), "prog_offer": g.dbg_offer, "prog_pick": g.dbg_pick, "prog_log": g.progression.prog_log,
		"heal_offer": g.progression.heal_offer, "heal_pick": g.progression.heal_pick,
		"xp_total": snappedf(g.pickups.xp_total, 0.1),
		# 经验分来源（docs/38 §8.13 方案 A，替代旧的 xp_overflow）：走近捡 / 磁铁吸回 / 视野外回收（含兜底），各带按分钟分段；
		# 守恒 xp_dropped = xp_walk + xp_magnet + xp_recall + xp_ground（tools/check.py 逐局断言）
		"xp_walk": snappedf(g.pickups.xp_src.walk, 0.1), "xp_magnet": snappedf(g.pickups.xp_src.magnet, 0.1), "xp_recall": snappedf(g.pickups.xp_src.recall, 0.1),
		"xp_walk_min": g.pickups.xp_src_min.walk.map(func(x): return snappedf(x, 0.1)),
		"xp_magnet_min": g.pickups.xp_src_min.magnet.map(func(x): return snappedf(x, 0.1)),
		"xp_recall_min": g.pickups.xp_src_min.recall.map(func(x): return snappedf(x, 0.1)),
		"xp_dropped": snappedf(g.pickups.xp_dropped, 0.1), "xp_ground": snappedf(g.pickups.xp_on_ground(), 0.1),
		"xp_backstop": snappedf(g.pickups.xp_backstop, 0.1), "recall_backstop": g.pickups.recall_backstop, "recall_n": g.pickups.recall_n,
		"xp_total_min": g.pickups.xp_total_min.map(func(x): return snappedf(x, 0.1)),
		"items": g.pickups.item_log.duplicate(), "crates": chests,
		"low_levelups": g.progression.low_levelups, "heal_offer_low": g.progression.heal_offer_low,
		"relic_offer": g.dbg_relic_offer, "relic_take": g.dbg_relic_take, "relic_out": g.relic_out, "prof": g.prof, "kills": g.kills,
		"elites": g.elites_killed, "relics": g.relics.size(), "ingots": g.ingots, "maxhp": g.max_hp,
		# 源石锭熔铸（docs/74）：t 开始时刻（-1 = 没触发）、left 当时剩余、pool 总熔铸、pct 全队伤害加成
		"fuse": {"t": g.rfx.fuse_t, "left": g.rfx.fuse_left, "pool": g.rfx.fuse_pool, "pct": snappedf(g.rfx.fuse_pct(), 0.001)},
		"bosses": g.bosses.map(func(b): return "%s:%s" % [b.type, "dead" if b.dead else "%d%%" % int(100 * b.hp / b.maxhp)]),
		"allies": g.squad.size() - 1, "squad": g.squad.ids(), "elite_stage": g.ch.elite,
		"boss_hp": (g.boss.hp / g.boss.maxhp) if g.boss != null else -1.0, "dmg": g.dmg_log, "out": g.dmg_out, "out_type": g.dmg_type_out,
		"out_tag": g.dmg_tag_out, "ending": g.ending, "lamp": int(g.lamp), "rej": g.doctor.rej(), "heal": g.heal_log, "drone": g.weapons.get("drone", 0),
		"floor_hits": g.floor_hits, "floor_times": g.floor_times, "kill_hits": kill_hits,
		"hordes": g.horde_log.map(func(h): return {"t": h.t, "n": h.n, "hp": int(h.hp), "t80": h.t80, "hp0": int(h.hp0), "minhp": int(h.minhp), "mix": h.get("mix", ""), "comp": h.comp}),
		"armor_cf": g.combat.armor_cf, "growth": g.growth.duplicate(), "dashes": dashes, "swaps": g.progression.swaps.duplicate(), "recruit_offers": g.progression.recruit_offers.duplicate(), "levelup_t": g.progression.levelup_t.duplicate(),   # docs/83：物理减伤遥测、被动卡等级、冲刺次数
		"terrain": g.map.tb_log.duplicate(),   # 地形阻挡（只记录）：挡下的我方 / 敌方直线弹、撞停的冲刺
		"shield": {"blocks": blocks, "abs": snappedf(shield_abs, 0.1), "t0": shield_t0, "peak": shield_peak, "max": g.shield_max, "every": g.shield_every,
			"src_max": g.stats.breakdown(&"shield_max").sources, "src_int": g.stats.breakdown(&"shield_interval").sources},
		"sus": sus,   # docs/88：治疗分项 / 干员减伤 / 净化 / 照亮
		"final_out": g.dmg_out, "ctrl": g.combat.ctrl_report(), "ctrl_src": g.combat.ctrl_src_report(), "bot": bot_block}
	if rich:
		rec["tel"] = "full"
		rec["ult"] = ult
		if not bot_block.is_empty():
			var cs := cap_stats.duplicate()
			for k in ["pre", "post", "one_cut", "boss_cut", "any_cut"]:
				cs[k] = snappedf(cs[k], 0.1)
			bot_block["cap_stats"] = cs
	if not m3.is_empty():
		var mr := {}
		for key in m3:
			mr[key] = snappedf(float(m3[key]), 0.1)
		rec["m3"] = mr   # Mon3tr 血条（docs/plans/2026-10-29-mon3tr-hp-plan.md）：倒地次数、不在场秒数、受伤 / 回血 / 治疗拍；没有 Mon3tr 的局不写
	if not g.squad.stance_log.is_empty():
		rec["cmd"] = g.squad.cmd_stats()   # 指挥模式（docs/114 §7）：突击秒数、倒地次数、被引走的怪数；没切过模式的局不写（BALANCE 与 main 逐字相同）
	if g.ult != null:
		rec["ult"] = g.ult.report()   # 终结技 / 连携 / 连携终结技次数与能量来源（docs/198 原型；ult/on 关时没有这一项）
	return rec


## 状态切换时调用（game.gd _process）：进入胜 / 负就把这一局写进本地记录
func on_state(s: int) -> void:
	if s == g.S.WIN:
		save_local("win")
	elif s == g.S.DEAD:
		save_local("dead")


## 离开对局场景（回标题 / 关游戏）时调用：还没记过的算中途退出
func on_exit() -> void:
	save_local("quit")


## 当前场景是不是 res://tests/ 下的测试场景（玩家局的当前场景是 boot / main / game，不会命中）
static func scene_is_test(path: String) -> bool:
	return path.begins_with("res://tests/")


func _current_scene_path() -> String:
	var tree := Engine.get_main_loop() as SceneTree   # 退出流程里 g 可能已离树，所以不走 g.get_tree()
	var cs: Node = tree.current_scene if tree != null else null
	return cs.scene_file_path if cs != null else ""


func save_local(result: String) -> void:
	# 测试运行不写玩家的记录；自测写本地记录用 --runslog=<路径>（写到指定文件，不碰玩家目录）
	var path := RUNS_PATH
	var test_path := ""
	for a in Cfg.dev_args():
		if a.begins_with("--runslog="):
			test_path = a.substr(10)
	if test_path != "":
		path = test_path
	elif not Cfg.dev_args().is_empty() or scene_is_test(_current_scene_path()):
		return   # 不带 -- 参数直接起 tests/ 场景的回归（check.py 里额外参数为空的那些）同样不写：10-14 / 10-20 / 10-27 的「水月 lv1 0 击杀 quit」就是它们
	elif not Cfg.runs_log_enabled():
		return   # 对外发布包不记任何玩家数据（用户 2026-09-26 决定暂不收集，docs/43）；调试版与对内包（audience = internal）记
	if saved or g.demo_op != "" or g.t < MIN_SAVE_T:
		return
	saved = true
	var line := {"schema": SCHEMA, "meta": {
		"version": str(build.get("version", "dev")), "commit": str(build.get("commit", "dev")),
		"platform": OS.get_name(), "time": Time.get_datetime_string_from_system(true), "seed": g.rng.seed,
		"diff": g.diff, "map": Cfg.map_id, "start_op": g.ch.id if g.ch != null else "", "result": result},
		"run": record()}
	line.run["op_stats"] = op_summary()   # 作战记录的按干员汇总（docs/77；只进本地记录，对外包整段不写，见上面的判断）
	line.run["rs"] = rs_compact()        # 作战记录原始数据（10-29 用户：对局记录点开要和结算里的一样全；新增字段，旧行没有，SCHEMA 不变）
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_rotate_if_big(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(line))


## 按干员汇总（runs.jsonl 的 run.op_stats）：id、入队 / 离队秒数、伤害、占比、在队每秒、参与击杀、技能次数、治疗主控、主要来源
func op_summary() -> Array:
	var RS = load("res://scripts/run/run_stats.gd")
	var m: Dictionary = RS.model(RS.snapshot(g))
	var out: Array = []
	for r in m.rows:
		out.append({"id": r.key, "join": int(r.join_t), "left": int(r.left_t), "dmg": int(r.dmg), "share": snappedf(float(r.share), 0.001),
			"dps": snappedf(float(r.dps), 0.1), "kills": int(r.kills), "casts": int(r.casts), "heal": int(r.heal),
			"top": str(r.sources[0].name) if not (r.sources as Array).is_empty() else ""})
	return out


## 作战记录原始数据（RunStats.snapshot）的存盘版：去掉藏品说明（读的时候按 id 查表）、数值取 1 位小数，一局几 KB
func rs_compact() -> Dictionary:
	var RS = load("res://scripts/run/run_stats.gd")
	var raw: Dictionary = RS.snapshot(g)
	var rl: Array = []
	for it in raw.relic_list:
		rl.append({"id": it.id, "lv": it.lv, "max": it.max})
	raw.relic_list = rl
	return _round_deep(raw)


static func _round_deep(v):
	if v is float:
		return snappedf(v, 0.1)
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _round_deep(v[k])
		return o
	if v is Array:
		return v.map(func(x): return _round_deep(x))
	return v


func _rotate_if_big(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < MAX_BYTES:
		return
	var lines := f.get_as_text().split("\n", false)
	f = null
	var keep := lines.slice(lines.size() / 2)
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w != null:
		w.store_string("\n".join(keep) + "\n")
