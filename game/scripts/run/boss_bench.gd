extends RefCounted
## Boss 单场测试台（docs/170）。只在 --balance 下生效，正常游戏不经过这里。
##   录制：--benchsnap=<路径前缀>：批跑局在每只 Boss 登场那一刻（刷出之前）写一份队伍快照 <前缀>_slot<k>.json，局照常往下跑；
##         每场 Boss 战结束（打死 / 局终）打印一行 BENCHREAL {...}（真实局里这场的结果，给测试台对照保真度）。
##   开打：--bossbench=<快照.json> [--benchboss=<id>[+<搭档>]] [--benchmaxt=秒] [--benchhp=snap]：
##         开局后按快照还原队伍，把时间拨到该 Boss 的登场时刻，由刷怪器照常刷出（场地规则、最终 Boss 场地冻结、伴随机制同正式局），
##         时间照常走；打到 Boss 全灭 / 队长倒下 / 超时，打印一行 BENCH {...} 退出。
## 快照 = 成长事件日志：每次「顶层」改动（藏品 / 入队 / 换人 / 推进成长节点 / 成长卡 / 补充卡 / 支援 / 事件给的最大生命与效果）
## 连同当时的 g.rng 状态与 g.t；还原时按顺序重放同一批函数，嵌套在里面的随机效果（藏品招募随机干员等）靠恢复 g.rng 逐个复现。
## 录制只读不写、不抽随机数：同 seed 结果不变。
const D = preload("res://scripts/data.gd")

var g
var rec_prefix := ""
var armed := false        # 开局设置完成后才开始记（开局编队 / 认知塑造由测试台自己的开局按同一组参数重做）
var depth := 0
var events: Array = []
var on := false           # 测试台局
var snap: Dictionary = {}
var stage := 0            # 0 等开局 / 1 已还原、等刷出 / 2 Boss 在场 / 3 已结束
var group_override: Array = []
var maxt := 180.0
var hp_mode := "full"
var fights: Array = []    # 进行中的 Boss 战 {slot, group, t0, n0, targets, ...}
var fp_diff: Array = []
var taken := 0.0          # 队长累计承伤（combat.lose_hp）
var live := false         # 录制或测试台开着（热路径钩子只读这个）
static var cur = null     # 开着的那一个（录制钩子走静态函数：编队 / 干员 / 藏品脚本里的 g 可能是测试替身）


func _init(game) -> void:
	g = game
	for a in _dev_args():
		if a.begins_with("--benchsnap="):
			rec_prefix = a.substr(12)
		elif a.begins_with("--bossbench="):
			var f := FileAccess.open(a.substr(12), FileAccess.READ)
			if f != null:
				var v = JSON.parse_string(f.get_as_text())
				if v is Dictionary:
					snap = v
					on = true
		elif a.begins_with("--benchboss="):
			group_override = Array(a.substr(12).split("+"))
		elif a.begins_with("--benchmaxt="):
			maxt = float(a.substr(12))
		elif a.begins_with("--benchhp="):
			hp_mode = a.substr(10)
	live = active()
	if live:
		cur = self


func active() -> bool:
	return rec_prefix != "" or on


static func rb(kind: String, args: Array) -> void:
	if cur != null:
		cur.begin(kind, args)


static func re() -> void:
	if cur != null:
		cur.end()


## ---- 录制钩子：被包住的函数在入口调 begin、出口调 end；只记最外层（depth 0）
func begin(kind: String, args: Array) -> void:
	if armed and depth == 0 and rec_prefix != "":
		events.append([kind, args, str(g.rng.state), g.t])
	depth += 1


func end() -> void:
	depth -= 1


## 每个模拟步调一次（autotest.step，只在 --balance）
func step() -> void:
	if not live:
		return
	if not armed and g.state == g.S.PLAY:
		armed = true
	if on and stage == 0 and g.state == g.S.PLAY and g.at_frames >= 2:
		_restore()
		stage = 1
	_tick_fights()


## 队长掉血（combat.lose_hp 实际扣的量）
func on_lose(amount: float) -> void:
	taken += amount
	for f in fights:
		if not f.done:
			f.taken += amount


## 打在 Boss 身上的实际伤害（combat._damage）；破绽 = e.break_t > 0 或 Boss 脚本受伤倍率 > 1（骑士撞柱 / 泡影坠地等）
func boss_hit(e: Dictionary, eff: float) -> void:
	if eff <= 0.0:
		return
	var bh = g.bai.boss(e.type)
	var brk: bool = float(e.get("break_t", 0.0)) > 0.0 or (bh != null and bh.taken_mult(e) > 1.0)
	for f in fights:
		if not f.done and f.targets.any(func(x): return is_same(x, e)):
			f.dmg += eff
			if brk:
				f.dmg_brk += eff


## 刷怪器决定好这一批 Boss、刷出之前调（spawner.update）；返回实际要刷的种类
func on_boss_group(slot: int, group: Array) -> Array:
	if not live:
		return group
	if on and not group_override.is_empty():
		group = group_override.duplicate()
		if slot == D.BOSS_TIMES.size():
			for k in D.ENDINGS:
				if str(D.ENDINGS[k].boss) == str(group[0]):
					g.ending = k
	if rec_prefix != "" and not on:
		_write_snap(slot, group)
	if on and stage != 1:
		return group   # 测试台只跟它自己那一场
	fights.append({"slot": slot, "group": group.duplicate(), "t0": g.t, "n0": g.bosses.size(), "targets": [], "done": false,
		"taken": 0.0, "dmg": 0.0, "dmg_brk": 0.0, "brk_t": 0.0, "last_t": g.t, "phases": [], "maxhp0": g.max_hp, "hp0": g.hp})
	if on:
		stage = 2
	return group


func _tick_fights() -> void:
	for f in fights:
		if f.done:
			continue
		if f.targets.is_empty() and g.bosses.size() > int(f.n0):
			f.targets = g.bosses.slice(int(f.n0))
			for e in f.targets:
				f.phases.append([str(e.type), int(e.get("phase", 1)), 0.0])
		var dt: float = g.t - float(f.last_t)
		f.last_t = g.t
		if f.targets.is_empty():
			continue
		var bh_any := false
		for e in f.targets:
			if e.dead:
				continue
			var bh = g.bai.boss(e.type)
			if float(e.get("break_t", 0.0)) > 0.0 or (bh != null and bh.taken_mult(e) > 1.0):
				bh_any = true
			var ph := int(e.get("phase", 1))
			var last := -1
			for p in f.phases:
				if p[0] == str(e.type):
					last = int(p[1])
			if ph != last:
				f.phases.append([str(e.type), ph, snappedf(g.t - float(f.t0), 0.1)])
		if bh_any:
			f.brk_t += dt
		var fin: bool = int(f.slot) == D.BOSS_TIMES.size()
		var all_dead: bool = f.targets.all(func(x): return x.dead)
		var res := ""
		if f.targets.any(func(x): return x.get("retreated", false)):
			res = "retreat"   # 中期 Boss 拖到最终 Boss 登场被撤走
		elif (fin and g.state == g.S.WIN) or (not fin and all_dead):
			res = "win"
		elif g.state == g.S.DEAD:
			res = "dead"
		elif on and g.t - float(f.t0) > maxt:
			res = "timeout"
		elif not on and (g.state == g.S.WIN or g.t > g.bal_maxt):
			res = "end"
		if res != "":
			_finish(f, res)


func _finish(f: Dictionary, res: String) -> void:
	f.done = true
	var ft: float = g.t - float(f.t0)
	var hp_left := 0.0
	var hp_max := 0.0
	for e in f.targets:
		hp_left += maxf(0.0, float(e.hp)) if not e.dead else 0.0
		hp_max += float(e.maxhp)
	var r := {"result": res, "win": res == "win", "slot": f.slot, "boss": "+".join(f.group), "fight_t": snappedf(ft, 0.1),
		"taken": snappedf(f.taken, 0.1), "taken_pct": snappedf(f.taken / maxf(1.0, float(f.maxhp0)), 0.001),
		"hp0_frac": snappedf(float(f.hp0) / maxf(1.0, float(f.maxhp0)), 0.001), "hp_end_frac": snappedf(maxf(0.0, g.hp) / maxf(1.0, g.max_hp), 0.001),
		"boss_hp_left": snappedf(hp_left / maxf(1.0, hp_max), 0.001), "boss_maxhp": snappedf(hp_max, 1.0),
		"dmg": snappedf(f.dmg, 1.0), "brk_dmg_share": snappedf(f.dmg_brk / maxf(1.0, f.dmg), 0.001),
		"brk_time_share": snappedf(f.brk_t / maxf(0.1, ft), 0.001), "phases": f.phases,
		"leader": str(g.ch.id) if g.ch != null else "", "squad": g.squad.ids(), "level": g.level, "max_hp": snappedf(g.max_hp, 1.0)}
	if on:
		r["snap"] = str(snap.get("name", ""))
		r["fp_diff"] = fp_diff
		r["seed"] = int(snap.get("seed", 0))
		print("BENCH ", JSON.stringify(r))
		stage = 3
		g.get_tree().quit()
	else:
		print("BENCHREAL ", JSON.stringify(r))


## ---- 快照
const G_VARS := ["level", "xp", "xp_need", "kills", "lamp", "lamp_cap", "ingots", "next_mire", "merchant_idx", "next_horde", "threat",
	"zone_c", "zone_r", "zone_next_c", "zone_next_r", "zone_state", "zone_t", "zone_frozen", "ppos", "shield", "shield_cd", "meta_once_heal", "ending"]
const OBJ_VARS := {
	"spawner": ["next_elite", "fixed_i", "next_chest", "spawn_acc", "mid_used"],
	"hunt": ["state"],
	"beacon_sys": ["next_at", "lit_n", "spawned_n"],
	"rfx": ["perm_dmg", "sp_stack", "medkits", "used", "revived", "kh_cnt", "kh_frac", "fuse_on", "fuse_pool", "contract_op", "shatter", "rules"],
	"progression": ["heal_pick", "focus_op"],
}


func _write_snap(slot: int, group: Array) -> void:
	var vars := {}
	for k in G_VARS:
		vars[k] = var_to_str(g.get(k))
	var objs := {}
	for on_ in OBJ_VARS:
		var o = g.get(on_)
		var d := {}
		for k in OBJ_VARS[on_]:
			if o != null and k in o:
				d[k] = var_to_str(o.get(k))
		objs[on_] = d
	var mobs: Array = []
	for e in g.enemies:
		if e.dead or e.boss or e.get("chest", false) or e.get("friendly", false) or mobs.size() >= 400:
			continue
		mobs.append([str(e.type), snappedf(e.pos.x, 0.1), snappedf(e.pos.y, 0.1), snappedf(float(e.hp) / maxf(1.0, float(e.maxhp)), 0.001)])
	var mires: Array = []
	for m in g.mires:
		mires.append(var_to_str({"pos": m.pos, "r": m.r, "maxr": m.maxr, "life": m.life, "seed": m.get("seed", 0.0)}))
	var args: Array = []
	for a in _dev_args():
		for p in ["--seed=", "--op=", "--squad=", "--bot=", "--meta=", "--metanodes=", "--tide=", "--diff=", "--tier=", "--bal=", "--dens="]:
			if a.begins_with(p):
				args.append(a)
	var seed := 0
	for a in args:
		if a.begins_with("--seed="):
			seed = int(a.substr(7))
	var name: String = rec_prefix.get_file() + "_slot%d" % slot
	var s := {"name": name, "slot": slot, "t": g.t, "real_group": group, "seed": seed, "args": args, "events": events.duplicate(true),
		"rng": str(g.rng.state), "rng_spawn": str(g.rng_spawn.state), "vars": vars, "objs": objs, "mobs": mobs, "mires": mires,
		"leader": str(g.ch.id) if g.ch != null else "", "hp": g.hp, "max_hp": g.max_hp, "growth": g.growth.duplicate(), "fp": fingerprint()}
	var f := FileAccess.open(rec_prefix + "_slot%d.json" % slot, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(s))
		f.close()
	print("BENCHSNAP slot=%d t=%.1f group=%s events=%d mobs=%d" % [slot, g.t, "+".join(group), events.size(), mobs.size()])


## 核对用：还原后与快照逐项比较（不一致的项写进 BENCH 的 fp_diff）
func fingerprint() -> Dictionary:
	var sq: Array = []
	for o in g.squad.ops:
		sq.append([str(o.id), int(o.elite), int(o.prog), str(o.route), bool(o.is_leader)])
	var rl := {}
	for id in g.relics:
		rl[str(id)] = int(g.rfx.lv.get(id, 1))
	var st := {}
	for k in ["max_hp", "speed", "armor", "regen", "regen_pct", "dmg_mult", "arts_mult", "ally_mult", "boss_mult", "dodge", "dmg_taken_mult", "followup_mult", "sp_mult", "heal_mult", "shield_max"]:
		if k == "regen_pct":
			continue   # 灯标庇护按站位临时 +1.5%
		st[k] = snappedf(float(g.get(k)), 0.001)
	# 属性修正逐条（来源 / 作用域 / 数值）：还原后缺了 / 多了哪一条一眼看出来；灯标庇护按站位临时加减，不算
	var mods := {}
	for k in g.stats._mods:
		var row: Array = []
		for m in g.stats._mods[k]:
			var src := str(m.source)
			if src != "beacon_zone" and src != "relic_haste" and not src.begins_with("blk"):   # 站位 / 叠层类临时修正：开战后按局内规则重建，不比
				row.append("%d|%s|%s|%s" % [int(m.op), str(snappedf(float(m.value), 0.0001)), src, str(m.scope)])
		row.sort()
		if not row.is_empty():
			mods[str(k)] = row
	return {"squad": sq, "relics": rl, "stats": st, "weapons": g.weapons.duplicate(), "level": g.level, "mods": mods}


func _restore() -> void:
	g.meta_start_relic = 0   # 「物由心生」的开局三选一已记在事件日志里（选中的藏品），别再弹一次
	for ev in snap.get("events", []):
		g.t = float(ev[3])
		g.rng.state = int(str(ev[2]))
		_replay(str(ev[0]), ev[1])
	var vars: Dictionary = snap.get("vars", {})
	for k in vars:
		g.set(k, str_to_var(str(vars[k])))
	var objs: Dictionary = snap.get("objs", {})
	for on_ in objs:
		var o = g.get(on_)
		if o == null:
			continue
		for k in objs[on_]:
			if k in o:
				o.set(k, str_to_var(str(objs[on_][k])))
	var ld = g.squad.get_op(str(snap.get("leader", "")))
	if ld != null and not ld.is_leader:
		g.squad.swap_cd = 0.0
		g.squad.swap_leader(ld)
		g.squad.swap_cd = 0.0
	var slot := int(snap.get("slot", 1))
	g.spawner.boss_idx = slot - 1
	g.t = float(D.BOSS_TIMES[slot - 1]) - 0.02
	g.rng.state = int(str(snap.get("rng", "0")))
	g.rng_spawn.state = int(str(snap.get("rng_spawn", "0")))
	g.bal_maxt = 1.0e9
	for m in snap.get("mobs", []):
		var e: Dictionary = g.spawner.spawn_enemy(str(m[0]), Vector2(float(m[1]), float(m[2])))
		if not e.is_empty():
			e.hp = float(e.maxhp) * clampf(float(m[3]), 0.05, 1.0)
	g.mires.clear()
	for ms in snap.get("mires", []):
		var m = str_to_var(str(ms))
		if m is Dictionary:
			g.mires.append(m)
	_backfill_mods()
	g.pickups.sync_level_pickup()   # 拾取范围随等级（来源「等级」）：等级是直接写回的，不经过升级
	g.rfx._fuse_sync()              # 源石锭熔铸的伤害加成按恢复后的熔铸池重算
	g.show_queue.clear()
	g.pending_levelups = 0
	g.pending_chests = 0
	g.chest_src.clear()
	g.choices = []
	g.panel.visible = false
	g.state = g.S.PLAY
	g.sync_stats()
	g.hp = g.max_hp if hp_mode != "snap" else minf(g.max_hp, float(snap.get("hp", g.max_hp)))
	g.hp_trail = g.hp
	var want: Dictionary = snap.get("fp", {})
	var got = JSON.parse_string(JSON.stringify(fingerprint()))   # 与快照同样过一遍 JSON（整数 / 小数写法一致）
	fp_diff = []
	for k in want:
		if JSON.stringify(want[k]) == JSON.stringify(got.get(k)):
			continue
		if want[k] is Dictionary:
			var gd: Dictionary = got.get(k, {})
			for kk in want[k]:
				var wv = want[k][kk]
				var gv = gd.get(kk)
				if JSON.stringify(wv) == JSON.stringify(gv):
					continue
				if wv is Array and (gv is Array or gv == null):
					var ga: Array = gv if gv is Array else []
					var miss: Array = wv.filter(func(x): return not ga.has(x))
					var extra: Array = ga.filter(func(x): return not wv.has(x))
					if miss.is_empty() and extra.is_empty():
						fp_diff.append("%s.%s: 条数 %d -> %d" % [k, kk, wv.size(), ga.size()])   # 同一条修正叠了不同次数
					else:
						fp_diff.append("%s.%s: 缺 %s 多 %s" % [k, kk, JSON.stringify(miss), JSON.stringify(extra)])
				else:
					fp_diff.append("%s.%s: %s -> %s" % [k, kk, JSON.stringify(wv), JSON.stringify(gv)])
			for kk in gd:
				if not (want[k] as Dictionary).has(kk):
					fp_diff.append("%s.%s: 多 %s" % [k, kk, JSON.stringify(gd[kk])])
		else:
			fp_diff.append("%s: %s -> %s" % [k, JSON.stringify(want[k]), JSON.stringify(got.get(k))])
	print("BENCHRESTORE events=%d mobs=%d fp_diff=%d %s" % [snap.get("events", []).size(), snap.get("mobs", []).size(), fp_diff.size(), JSON.stringify(fp_diff)])


## Boss 演练 · 成品分队（run/practice_squads.gd）：只把快照里的队伍成长还原到当前局——事件日志重放、等级 / 经验、
## 藏品与选卡的运行期变量、当时的队长、长期修正补齐；不碰时间、场地、刷怪、杂兵与随机数口径（演练自己摆场）。
## 调用方之后自己 sync_stats / 回满血。
const BUILD_VARS := ["level", "xp", "xp_need", "lamp_cap", "meta_once_heal"]


func apply_build(s: Dictionary) -> void:
	var keep_snap := snap
	snap = s
	var t0: float = g.t
	g.meta_start_relic = 0
	for ev in s.get("events", []):
		g.t = float(ev[3])
		g.rng.state = int(str(ev[2]))
		_replay(str(ev[0]), ev[1])
	g.t = t0
	var vars: Dictionary = s.get("vars", {})
	for k in BUILD_VARS:
		if vars.has(k):
			g.set(k, str_to_var(str(vars[k])))
	var objs: Dictionary = s.get("objs", {})
	for on_ in ["rfx", "progression"]:
		var o = g.get(on_)
		if o == null or not objs.has(on_):
			continue
		for k in objs[on_]:
			if k in o:
				o.set(k, str_to_var(str(objs[on_][k])))
	var ld = g.squad.get_op(str(s.get("leader", "")))
	if ld != null and not ld.is_leader:
		g.squad.swap_cd = 0.0
		g.squad.swap_leader(ld)
	g.squad.swap_cd = 0.0
	_backfill_mods()
	g.pickups.sync_level_pickup()
	g.rfx._fuse_sync()
	g.show_queue.clear()
	g.pending_levelups = 0
	g.pending_chests = 0
	g.chest_src.clear()
	g.choices = []
	g.panel.visible = false
	g.state = g.S.PLAY
	snap = keep_snap


## 局中按击杀 / 击败 Boss / 放技能累加、又不经过上面那批函数的长期修正（如「生还者合约」每击败一只 Boss +20%、
## 叠层藏品）：按快照指纹里逐条的修正补齐缺的那几条（只补藏品与事件来源；临时减益、站位加成不补）
const BACKFILL := ["relic:", "relic_stack:", "event:", "rej:"]


func _backfill_mods() -> void:
	var want: Dictionary = (snap.get("fp", {}) as Dictionary).get("mods", {})
	var have: Dictionary = fingerprint().mods
	for k in want:
		var pool: Array = (have.get(k, []) as Array).duplicate()
		for row in want[k]:
			var i := pool.find(row)
			if i >= 0:
				pool.remove_at(i)
				continue
			var f: PackedStringArray = str(row).split("|")
			if f.size() == 4 and BACKFILL.any(func(p): return f[2].begins_with(p)) and g.stats.has_stat(StringName(k)):
				g.stats.add(StringName(k), int(f[0]), float(f[1]), f[2], f[3])
	g.sync_stats()


func _replay(kind: String, a: Array) -> void:
	match kind:
		"relic":
			g.progression.gain_relic(str(a[0]))
		"add":
			g.squad.add(str(a[0]), bool(a[1]))
		"replace":
			g.squad.replace(str(a[0]), str(a[1]), str(a[2]))
		"adv":
			var o = g.squad.get_op(str(a[0]))
			if o != null:
				o.advance(str(a[1]))
		"growth":
			g.growth[str(a[0])] = int(g.growth.get(str(a[0]), 0)) + 1
			if not g.doctor.apply_passive(str(a[0])):
				var gop = g.squad.get_op(str(a[1]))
				if gop != null:
					gop._apply_growth(str(a[0]))
		"filler":
			g.doctor.apply_filler(str(a[0]))
		"weapon":
			g.weapons[str(a[0])] = int(a[1])
		"maxhp":
			g.endg._max_hp(float(a[0]))
		"gain":
			g.rfx._on_gain(str(a[0]), a[1] if a[1] is Dictionary else {})
		"rej", "unrej":
			var ro = g.squad.get_op(str(a[0]))
			if ro != null:
				if kind == "rej":
					ro.apply_rejection()
				else:
					ro.clear_rejection()


## 与 Cfg.dev_args 同口径（只在 debug 构建读命令行）；不直接引用 Cfg：settings.gd → relic_db → … → 本脚本 → Cfg 会循环编译失败（-s 测试里 core 挂）
static func _dev_args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()
