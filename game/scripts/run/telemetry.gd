extends RefCounted
## 局内数据记录（2026-09-26，docs/40）：一局一条「整局记录」，平衡机器人与真实玩家同一格式。
## - 整局指标（受击、低血时长、死因、Boss 用时、精英化 / 入队时间、每 30 秒曲线……）原在 core/bot.gd，只有机器人局才采；
##   现在所有对局都采。机器人局由 run/autotest.gd 按原来的节奏驱动（tick(0.066)），真实玩家局由 game.gd _update 驱动。
## - record() 拼出整局记录：平衡测试照旧打印成 `BALANCE {...}`（字段与之前完全相同，批跑 / A/B 工具不用改）；
##   真实玩家局结束（胜 / 负 / 中途退出）时 save_local() 追加一行到 user://runs/runs.jsonl，外面再包一层 meta（版本、时间、种子……）。
## - 测试运行（带任何 --xxx 参数）与图鉴演示不写本地文件（docs/36：测试不写玩家存档）。
## - 发布版（导出的 release 包）不写：用户 2026-09-26 决定暂不收集任何数据（EA 版先发朋友试玩）；只在开发试玩时写。
## - 只在本地，不联网上传；上报通道与玩家同意流程等上线时再做（docs/40 §4）。
## 分析：python tools/runs_report.py 读本地记录，套用 balance_run 的汇总表。

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
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
var dark_s := 0.0               # 灯火熄灭的累计秒数
var dark_dmg := 0.0             # 熄灯每秒 3 点的持续掉血（不进 dmg_log，单独记）
var hits := 0                   # 受击次数
var taken_last := 0.0
var taken_window := 0.0         # 当前采样窗口内的承伤
var last_src := ""              # 最近一次掉血的来源（死因）
var last_log: Dictionary = {}
var boss_seen: Dictionary = {}  # id -> {type, t0, t1}
var elite_t: Dictionary = {}    # "<op>:<elite>" -> 秒
var recruit_t: Array = []       # 每名干员入队时间
var squad_n := 0
var dist_moved := 0.0
var last_pos := Vector2.ZERO
var still_s := 0.0              # 站着不动的累计秒数
var lv_marks := {}              # 2:00 / 5:00 / 8:00 时的等级（玩家局用；平衡局沿用 autotest 自己的）
var peak: Array = [0, 0, 0, 0, 0]   # 同屏数量峰值：敌人 / 敌方弹幕（含抛射物）/ 我方子弹 / 特效 / 飘字（后期画面优化的量化，2026-09-27）
var peak_min: Array = []            # 每分钟的峰值，同上 5 项；peak_min[i] 为第 i 分钟
# ---- 本地保存
var saved := false
var build: Dictionary = {}


func _init(game: Game) -> void:
	g = game
	var f := FileAccess.open("res://data/build.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			build = d


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
		if inc > inc_best:
			inc_best = inc
			last_src = k
		last_log[k] = v
	if tot > taken_last + 0.01:
		hits += 1
		taken_window += tot - taken_last
	taken_last = tot
	# Boss 出现 / 击杀时间
	for b in g.bosses:
		var key := str(b.get("id", b.type))
		if not boss_seen.has(key):
			boss_seen[key] = {"type": b.type, "t0": int(t), "t1": -1}
		elif b.dead and boss_seen[key].t1 < 0:
			boss_seen[key].t1 = int(t)
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
		curve.append({"t": int(t), "hp": int(100.0 * g.hp / maxf(1.0, g.max_hp)), "lamp": int(g.lamp), "lv": g.level,
			"kills": g.kills, "squad": g.squad.size(), "taken": int(taken_window), "enemies": g.enemies.size(),
			"zone": g.zone_state, "boss": int(_boss_alive())})
		taken_window = 0.0


func _boss_alive() -> bool:
	for b in g.bosses:
		if not b.dead:
			return true
	return false


## 结束时的局面（死因 × 缩圈阶段 × Boss 在场；A/B 缩圈规则用，2026-09-27）
func end_ctx() -> Dictionary:
	var out: float = g.ppos.distance_to(g.zone_c) - g.zone_r
	return {"t": int(g.t), "src": last_src, "zone_state": g.zone_state, "zone_phase": g.combat.zone_phase if g.zone_state > 0 else -1,
		"zone_out": out > 0.0, "boss": _boss_alive(), "hp": int(g.hp)}


## 整局指标块（记录里的 "bot" 字段：名字沿用平衡工具的历史叫法，玩家局 profile = "player"）
func metrics(profile: String) -> Dictionary:
	var t: float = maxf(1.0, g.t)
	return {"profile": profile, "hits": hits, "hits_pm": snappedf(hits / t * 60.0, 0.1), "taken": int(taken_last),
		"taken_pm": int(taken_last / t * 60.0), "low_hp_s": int(low_hp_s), "dark_s": int(dark_s), "dark_dmg": int(dark_dmg), "death_src": last_src,
		"moved_pm": int(dist_moved / t * 60.0), "still_pct": int(100.0 * still_s / t),
		"bosses": boss_seen.values(), "elite_t": elite_t, "recruit_t": recruit_t, "curve": curve,
		"peak": peak, "peak_min": peak_min, "end": end_ctx()}


## 整局记录（平衡测试打印的 BALANCE 同一份；字段改名 / 删除要同步 tools/balance_run.py 与 SCHEMA）
func record(marks = null) -> Dictionary:
	var prof_name := "player"
	if g.bot != null:
		prof_name = g.bot.profile
	var bot_block: Dictionary = metrics(prof_name) if (g.bot != null or not g.autotest) else {}
	return {"win": g.state == g.S.WIN, "t": int(g.t), "lv": g.level, "marks": lv_marks if marks == null else marks, "lv_times": g.lv_times,
		"ops": g.squad.ops.map(func(o): return {"id": o.id, "elite": o.elite, "prog": o.prog}), "prog_offer": g.dbg_offer, "prog_pick": g.dbg_pick,
		"relic_offer": g.dbg_relic_offer, "relic_take": g.dbg_relic_take, "relic_out": g.relic_out, "prof": g.prof, "kills": g.kills,
		"elites": g.elites_killed, "relics": g.relics.size(), "ingots": g.ingots, "maxhp": g.max_hp,
		"bosses": g.bosses.map(func(b): return "%s:%s" % [b.type, "dead" if b.dead else "%d%%" % int(100 * b.hp / b.maxhp)]),
		"allies": g.squad.size() - 1, "squad": g.squad.ids(), "elite_stage": g.ch.elite,
		"boss_hp": (g.boss.hp / g.boss.maxhp) if g.boss != null else -1.0, "dmg": g.dmg_log, "out": g.dmg_out, "out_type": g.dmg_type_out,
		"out_tag": g.dmg_tag_out, "ending": g.ending, "lamp": int(g.lamp), "rej": g.doctor.rej(), "heal": g.heal_log, "drone": g.weapons.get("drone", 0),
		"floor_hits": g.floor_hits, "floor_times": g.floor_times,
		"hordes": g.horde_log.map(func(h): return {"t": h.t, "n": h.n, "hp": int(h.hp), "t80": h.t80, "hp0": int(h.hp0), "minhp": int(h.minhp), "mix": h.get("mix", ""), "comp": h.comp}),
		"final_out": g.dmg_out, "ctrl": g.combat.ctrl_report(), "bot": bot_block}


## 状态切换时调用（game.gd _process）：进入胜 / 负就把这一局写进本地记录
func on_state(s: int) -> void:
	if s == g.S.WIN:
		save_local("win")
	elif s == g.S.DEAD:
		save_local("dead")


## 离开对局场景（回标题 / 关游戏）时调用：还没记过的算中途退出
func on_exit() -> void:
	save_local("quit")


func save_local(result: String) -> void:
	# 测试运行不写玩家的记录；自测写本地记录用 --runslog=<路径>（写到指定文件，不碰玩家目录）
	var path := RUNS_PATH
	var test_path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runslog="):
			test_path = a.substr(10)
	if test_path != "":
		path = test_path
	elif not OS.get_cmdline_user_args().is_empty():
		return
	elif not OS.is_debug_build():
		return   # 发布版（export-release）不记任何玩家数据：用户 2026-09-26 决定暂不收集（docs/43）；只在开发试玩（编辑器 / 调试版）时记
	if saved or g.demo_op != "" or g.t < MIN_SAVE_T:
		return
	saved = true
	var line := {"schema": SCHEMA, "meta": {
		"version": str(build.get("version", "dev")), "commit": str(build.get("commit", "dev")),
		"platform": OS.get_name(), "time": Time.get_datetime_string_from_system(true), "seed": g.rng.seed,
		"diff": g.diff, "map": Cfg.map_id, "start_op": g.ch.id if g.ch != null else "", "result": result},
		"run": record()}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_rotate_if_big(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(line))


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
