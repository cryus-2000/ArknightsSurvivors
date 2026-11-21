## 干员积木 · seg_sbell2（docs/403 圣聆初雪：特性「无垠的雪景」积雪地格、S1「铃音吹雪」、S2 永久开阵的积雪规则、S3 积雪加速、
## 天赋「圣山的祝福」寒冷反击与一局一次免死、精一「铃落」、精二「霜涛」、成长节点 雪径 / 檐雪 / 封冻 / 雪崩 / 凝冰之阵 / 风雪漫卷）
## 积雪落在世界地格上（格宽 cell，键 Vector2i），不跟人走；每格 1–5 层。状态全在 o.gn.sb（字典），没带 verb.sb_* 的干员一律不走本文件。
## 接入：瞬时积木 verb.sb_*（seg_hoshiguma.EXT_BLOCKS、data_operator.EXEC_SEG → _ext_exec → sb_exec）；
## 每帧软减速 sb_frame（data_operator.update）、地面画法 sb_draw_ground（data_operator.draw_ground_fx）、免死 sb_prevent_death（data_operator.prevent_death）。
## 确定性：玩法不取随机数（遍历 g.enemies 的固定顺序、字典插入顺序）；画面花样按格子键哈希。
## 画面是占位（docs/403 §6.0：浅冰蓝雪斑 + 层数亮点 + 暗铜铃纹），转平面特效另做。
extends "res://scripts/characters/blocks/seg_ling.gd"

const SB_ICE := Color(0.62, 0.85, 1.0)      # 积雪冰蓝 #9fd8ff
const SB_EDGE := Color(0.30, 0.52, 0.82)    # 雪斑描边（压暗的宝蓝）
const SB_PIP := Color(0.96, 1.0, 1.0)       # 层数亮点
const SB_BELL := Color(0.63, 0.48, 0.29)    # 暗铜铃纹 #a07a4a
const SB_TEX_N := 14                        # 雪斑贴图边长（texel），每 texel = 3 世界单位（3 像素格）
static var _sb_tex: Array = []              # [变体][层数-1] → ImageTexture（只画）


## data_operator._ext_exec 转来
static func sb_exec(o, b: Dictionary, at: Vector2) -> void:
	match str(b.get("_tag", "")):
		"verb.sb_snow":
			_sb_tick(o, b)
		"verb.sb_blast":
			_sb_blast(o, b)
		"verb.sb_lay":
			_sb_lay_ring(o, b, at)
		"verb.sb_chill":
			_sb_chill(o, b)


## 积雪状态（第一次用时建）。cells：键 → 层数；order：键的先后（超上限先清最早的）；on：敌人 id → {k, hit}；slow：敌人 id → [e, pct, last]
static func sb_st(o) -> Dictionary:
	if not o.gn.has("sb"):
		o.gn["sb"] = {"cells": {}, "order": [], "on": {}, "slow": {}, "acc": 0.0, "scan": 0, "cyc": 0, "wave": {}, "storms": [],
			"bless": false, "bless_pending": false, "s2_was": false, "last_pp": Vector2.INF, "b": {}}
	return o.gn.sb


static func _sb_cell(o) -> float:
	return float(sb_st(o).b.get("cell", 42.0))


static func sb_key(o, p: Vector2) -> Vector2i:
	var c := _sb_cell(o)
	return Vector2i(floori(p.x / c), floori(p.y / c))


static func sb_center(o, k: Vector2i) -> Vector2:
	var c := _sb_cell(o)
	return Vector2((float(k.x) + 0.5) * c, (float(k.y) + 0.5) * c)


static func _sb_in_zone(o, p: Vector2) -> bool:
	var g = o.g
	return float(g.zone_r) >= 99000.0 or p.distance_to(g.zone_c) <= float(g.zone_r)


## 给一格 +n 层（至多 max）；超出格数上限先清最早的格。返回加之后的层数（0 = 没加上）
static func sb_add(o, k: Vector2i, n: int) -> int:
	var st := sb_st(o)
	var cap: int = int(st.b.get("cap", 240))
	var mx: int = int(st.b.get("max", 5))
	if not _sb_in_zone(o, sb_center(o, k)):
		return 0
	var cells: Dictionary = st.cells
	if not cells.has(k):
		while st.order.size() >= cap and not st.order.is_empty():
			cells.erase(st.order.pop_front())
		st.order.append(k)
		cells[k] = 0
	cells[k] = mini(mx, int(cells[k]) + n)
	return int(cells[k])


static func sb_remove(o, k: Vector2i) -> void:
	var st := sb_st(o)
	if st.cells.has(k):
		st.cells.erase(k)
		st.order.erase(k)


## 圆内的格子（按格心），固定顺序（行优先）
static func sb_keys_in(o, c: Vector2, r: float) -> Array:
	var cs := _sb_cell(o)
	var k0 := sb_key(o, c - Vector2(r, r))
	var k1 := sb_key(o, c + Vector2(r, r))
	var out: Array = []
	for y in range(k0.y, k1.y + 1):
		for x in range(k0.x, k1.x + 1):
			var k := Vector2i(x, y)
			if sb_center(o, k).distance_to(c) <= r + cs * 0.25:
				out.append(k)
	return out


## 伤害（法术，乘本干员局部伤害倍率与全局加成；精英 / Boss 吃 vs_elite）
static func sb_hit(o, e: Dictionary, mult: float, src: String, tags: Array) -> void:
	if e.dead or mult <= 0.0:
		return
	o.log_hit(src, tags)
	o.deal_damage(e, o.base("atk", 0.0) * mult * float(o.loc.dmg) * o._dmg_bonus() * (o.vs_elite() if e.elite or e.boss else 1.0))


## 冻结 = 眩晕（精英减半、Boss 不受）
static func sb_freeze(o, e: Dictionary, secs: float, growth := false) -> void:
	if e.dead or e.boss or secs <= 0.0:
		return
	var s: float = secs * (0.5 if e.elite else 1.0)
	if growth:
		o.add_cc_growth(e, s)
	else:
		o.add_cc(e, s)
	o.fx({"kind": "ring", "pos": e.pos, "r": float(e.r) + 6.0, "r0": float(e.r) + 6.0, "life": minf(s, 1.2), "col": SB_ICE, "floor": true, "w": 2.0, "alpha": 0.9})


## 寒冷 = 减速状态（Boss 也吃，同 st.slow）
static func sb_cold(o, e: Dictionary, secs: float) -> void:
	if e.dead or secs <= 0.0:
		return
	o.add_cc(e, -INF, secs * (1.0 if e.boss else (0.5 if e.elite else 1.0)))


static func _sb_ground_enemy(e: Dictionary) -> bool:
	return not e.dead and not e.get("chest", false) and not e.get("hover", false) and not e.get("fly", false)


# ---------------------------------------------------------------- 特性：积雪节拍 + 踏雪扫描（trait 的 trig.tick 每 scan 秒调）

static func _sb_tick(o, b: Dictionary) -> void:
	var st := sb_st(o)
	st.b = b
	var g = o.g
	var dt: float = float(b.get("scan", 0.1))
	var e2: int = clampi(int(o.elite), 0, 2)
	var s2: bool = o.skill_on(1)
	var s3: bool = o.skill_on(2)
	# S2 刚结束（永久技能被打断 / 离队清场）时：凝冰之阵
	if bool(st.s2_was) and not s2 and o.taken.has(str(b.get("n5a", "ningbing"))):
		_sb_shatter_all(o, b)
	st.s2_was = s2
	_sb_guard(o, b)
	# 一：积雪节拍
	if o.pos != Vector2.INF:
		var cd: float = float(b.get("cd%d" % e2, b.get("cd0", 3.0))) * (float(b.get("s3_snow", 0.5)) if s3 else 1.0)
		st.acc = float(st.acc) + dt
		if float(st.acc) >= cd:
			st.acc = float(st.acc) - cd
			_sb_snowfall(o, b, s2)
	# 二：雪径（节点 1）：队长冲刺途经的格子 +n 层
	if o.taken.has(str(b.get("n1", "xuejing"))) and float(g.dash_t) > 0.0 and st.last_pp != Vector2.INF:
		var a: Vector2 = st.last_pp
		var z: Vector2 = g.ppos
		var steps: int = clampi(int(ceil(a.distance_to(z) / (_sb_cell(o) * 0.6))), 1, 8)
		for i in steps + 1:
			sb_add(o, sb_key(o, a.lerp(z, float(i) / float(steps))), int(b.get("n1_layers", 2)))
	st.last_pp = g.ppos
	# 三：踏雪扫描
	_sb_scan(o, b, s2)
	# 四：霜涛（精二）推进、风雪（节点 5B）
	if not st.wave.is_empty():
		_sb_wave_step(o, b, dt)
	if not st.storms.is_empty():
		_sb_storm_step(o, b, dt)
	# 五：免死回复（prevent_death 当帧被游戏设成 1 点，这里补回）
	if bool(st.bless_pending):
		_sb_bless_apply(o, b)


## 一次积雪：身边 r 内每格 +1 层；S2 期间满层的格子向相邻 8 格溢出；精二每 wave_n 次推一圈霜涛
static func _sb_snowfall(o, b: Dictionary, s2: bool) -> void:
	var st := sb_st(o)
	var r: float = float(b.get("r", 150.0)) * o.stat(&"op_range")
	var mx: int = int(b.get("max", 5))
	var full_now: Array = []
	var spill: Array = []
	for k in sb_keys_in(o, o.pos, r):
		var had: int = int(st.cells.get(k, 0))
		if had >= mx and s2:
			spill.append(k)
			continue
		var n := sb_add(o, k, 1)
		if n >= mx and had < mx:
			full_now.append(k)
	if s2:
		var budget: int = int(b.get("s2_spread", 60))
		for k in spill:
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if (dx != 0 or dy != 0) and budget > 0:
						var kk: Vector2i = k + Vector2i(dx, dy)
						var had2: int = int(st.cells.get(kk, 0))
						if had2 < mx:
							budget -= 1
							if sb_add(o, kk, 1) >= mx:
								full_now.append(kk)
		# S2「冻结点」：积到满层的那一刻，格上的敌人冻结
		if not full_now.is_empty():
			var fz: float = float(b.get("s2_freeze", 1.0))
			var want := {}
			for k in full_now:
				want[k] = true
			for id in st.on:
				var rec: Dictionary = st.on[id]
				if want.has(rec.k):
					sb_freeze(o, rec.e, fz)
	st.cyc = int(st.cyc) + 1
	if int(o.elite) >= 2 and int(st.cyc) % maxi(1, int(b.get("wave_n", 3))) == 0:
		st.wave = {"t": 0.0, "c": o.pos, "hit": {}}
	_FXR.ev(o, "sb_snow", {"p": o.pos, "r": r})


## 踏雪：遍历地面敌人，进了有雪的格子就受伤一次；离开一格时带走那格雪（首个离开者）；层数软减速；S2 雪上持续伤 / 离雪寒冷
static func _sb_scan(o, b: Dictionary, s2: bool) -> void:
	var st := sb_st(o)
	var g = o.g
	var cells: Dictionary = st.cells
	var e2: int = clampi(int(o.elite), 0, 2)
	var hit_mult: float = float(b.get("hit%d" % e2, b.get("hit0", 0.25)))
	var slow_per: float = float(b.get("slow2", 0.12)) if e2 >= 2 else float(b.get("slow0", 0.10))
	var mx: int = int(b.get("max", 5))
	var src: String = str(b.get("src", "积雪"))
	var on: Dictionary = st.on
	var non := {}
	var nslow := {}
	st.scan = int(st.scan) + 1
	var dot_now: bool = s2 and int(st.scan) % 5 == 0
	var dot: float = float(b.get("s2_dot", 0.08)) * 0.5
	var fengdong: bool = o.taken.has(str(b.get("n4a", "fengdong")))
	var yanxue: bool = o.taken.has(str(b.get("n2", "yanxue")))
	if cells.is_empty() and on.is_empty():
		return
	for e in g.enemies:
		if not _sb_ground_enemy(e):
			continue
		var k := sb_key(o, e.pos)
		var id: int = int(e.id)
		var prev: Dictionary = on.get(id, {})
		var n: int = int(cells.get(k, 0))
		if not prev.is_empty() and prev.k != k:   # 离开上一格：带走那格雪（若还在）
			var pn: int = int(cells.get(prev.k, 0))
			if pn > 0 and bool(prev.hit):
				_sb_break(o, b, prev.k, pn, e)
				if s2 and n <= 0:
					sb_cold(o, e, float(b.get("s2_leave_cold", 2.0)))
			prev = {}
		if n <= 0:
			if cells.is_empty():
				continue
			non[id] = {"k": k, "hit": false, "e": e}
			continue
		var rec: Dictionary = prev if not prev.is_empty() else {"k": k, "hit": false, "e": e}
		if not bool(rec.hit):   # 踏上（或积雪生成到脚下）：立即受伤一次
			rec.hit = true
			sb_hit(o, e, hit_mult, src, ["basic", "area"])
			if fengdong and n >= mx:
				_sb_fengdong(o, b, k, e, s2)
			_FXR.ev(o, "sb_step", {"e": e, "n": n})
		if yanxue and float(e.get("sb_push", 0.0)) > float(g.t) and float(e.get("sb_push", 0.0)) - float(g.t) < 0.45:   # 檐雪：吹雪推开的敌人落在雪上
			e["sb_push"] = 0.0
			sb_freeze(o, e, float(b.get("n2_freeze", 1.0)), true)
			_sb_break(o, b, k, n, e)
			continue
		if dot_now:
			sb_hit(o, e, dot, "霜涛覆岭", ["skill", "area"])
		rec.e = e
		non[id] = rec
		if not e.boss:
			var old: Array = st.slow.get(id, [])
			nslow[id] = [e, minf(0.9, slow_per * float(n)), old[2] if old.size() >= 3 else e.pos]
	st.on = non
	st.slow = nslow


## 一格雪被踏碎：清掉；雪崩（4B）≥3 层炸冰屑；风雪漫卷（5B）留一团风雪
static func _sb_break(o, b: Dictionary, k: Vector2i, n: int, _e: Dictionary) -> void:
	var st := sb_st(o)
	sb_remove(o, k)
	var c := sb_center(o, k)
	if o.taken.has(str(b.get("n4b", "xuebeng"))) and n >= int(b.get("n4b_min", 3)):
		var r: float = float(b.get("n4b_r", 60.0)) * o.stat(&"op_range")
		var dmg: float = o.base("atk", 0.0) * float(b.get("n4b_mult", 0.2)) * float(n) * float(o.loc.dmg) * o._dmg_bonus()
		o.area_hit("雪崩", c, r, dmg, 0.0, 0.0, ["area"], 0)
		o.fx({"kind": "ring", "pos": c, "r": r, "r0": 6.0, "life": 0.25, "col": SB_ICE, "floor": true, "w": 2.0, "alpha": 0.8})
	if o.taken.has(str(b.get("n5b", "fengxue"))) and st.storms.size() < 16:
		st.storms.append({"c": c, "t": 0.0, "acc": 0.0})


## 封冻（4A）：满层积雪被踏上 → 冻结；S2 期间连相邻格上的敌人一起
static func _sb_fengdong(o, b: Dictionary, k: Vector2i, e: Dictionary, s2: bool) -> void:
	var fz: float = float(b.get("n4a_freeze", 1.0))
	if not s2:
		sb_freeze(o, e, fz, true)
		return
	var st := sb_st(o)
	for id in st.on:
		var rec: Dictionary = st.on[id]
		var kk: Vector2i = rec.k
		if absi(kk.x - k.x) <= 1 and absi(kk.y - k.y) <= 1:
			sb_freeze(o, rec.e, fz, true)
	sb_freeze(o, e, fz, true)


## 凝冰之阵（5A）：S2 结束时，≥ min 层的积雪同时碎裂，冻结其上敌人
static func _sb_shatter_all(o, b: Dictionary) -> void:
	var st := sb_st(o)
	var mn: int = int(b.get("n5a_min", 3))
	var fz: float = float(b.get("n5a_freeze", 1.5))
	var bad := {}
	for k in st.cells:
		if int(st.cells[k]) >= mn:
			bad[k] = true
	for id in st.on:
		if bad.has(st.on[id].k):
			sb_freeze(o, st.on[id].e, fz, true)
	for k in bad:
		sb_remove(o, k)
	_FXR.ev(o, "sb_shatter", {"n": bad.size()})


## 精二霜涛：wave_t 秒内从中心扩到 wave_r，只打站在雪上、本圈没打过的敌人
static func _sb_wave_step(o, b: Dictionary, dt: float) -> void:
	var st := sb_st(o)
	var w: Dictionary = st.wave
	var t0: float = float(w.t)
	w.t = t0 + dt
	var T: float = float(b.get("wave_t", 0.6))
	var R: float = float(b.get("wave_r", 240.0)) * o.stat(&"op_range")
	var r0: float = R * clampf(t0 / T, 0.0, 1.0) - 24.0
	var r1: float = R * clampf(float(w.t) / T, 0.0, 1.0) + 8.0
	for id in st.on:
		var rec: Dictionary = st.on[id]
		if w.hit.has(id):
			continue
		var d: float = rec.e.pos.distance_to(w.c)
		if d >= r0 and d <= r1:
			w.hit[id] = true
			sb_hit(o, rec.e, float(b.get("wave_mult", 0.8)), "霜涛", ["basic", "area"])
			sb_cold(o, rec.e, float(b.get("wave_cold", 1.5)))
	if float(w.t) >= T:
		st.wave = {}


## 风雪漫卷（5B）：每团 dur 秒，每 every 秒对 r 内敌人造成伤害 + 寒冷
static func _sb_storm_step(o, b: Dictionary, dt: float) -> void:
	var st := sb_st(o)
	var keep: Array = []
	var r: float = float(b.get("n5b_r", 50.0)) * o.stat(&"op_range")
	var ev: float = float(b.get("n5b_every", 0.5))
	var dmg: float = o.base("atk", 0.0) * float(b.get("n5b_mult", 0.1)) * float(o.loc.dmg) * o._dmg_bonus()
	for s in st.storms:
		s.t = float(s.t) + dt
		s.acc = float(s.acc) + dt
		if float(s.acc) >= ev:
			s.acc = float(s.acc) - ev
			for e in o.area_hit("风雪漫卷", s.c, r, dmg, 0.0, 0.0, ["area"], 0):
				sb_cold(o, e, 1.0)
		if float(s.t) < float(b.get("n5b_dur", 2.0)):
			keep.append(s)
	st.storms = keep


## 守阵（特性）：担任队长且 S2 还没放出时，队长护甲 / 法抗 + guard（来源 sbg:<id>，状态变了才重写）
static func _sb_guard(o, b: Dictionary) -> void:
	var st := sb_st(o)
	var want: bool = o.is_leader and not o.skill_on(1)
	if want == bool(st.get("guard", false)):
		return
	st.guard = want
	var src: String = "sbg:" + str(o.id)
	o.g.stats.remove_source(src)
	if want:
		o.g.stats.add(&"armor", "add", float(b.get("guard_armor", 1.5)), src)
		o.g.stats.add(&"arts_res", "add", float(b.get("guard_res", 0.15)), src)
	o.refresh_stats()


## 离队：撤守阵加成、清掉积雪与减速记录
static func sb_leave(o) -> void:
	o.g.stats.remove_source("sbg:" + str(o.id))
	o.gn.erase("sb")
	o.refresh_stats()


# ---------------------------------------------------------------- 每帧：积雪软减速（不是减速状态，同 st.slow_soft：退回这一帧的位移）

static func sb_frame(o, _dt: float) -> void:
	var st: Dictionary = o.gn.sb
	for id in st.slow:
		var s: Array = st.slow[id]
		var e: Dictionary = s[0]
		if e.dead:
			continue
		var last: Vector2 = s[2]
		e.pos -= (e.pos - last) * float(s[1])
		s[2] = e.pos


# ---------------------------------------------------------------- S1「铃音吹雪」：朝最密方向的扇形，两下；推开 + 寒冷 + 雪道

static func _sb_blast(o, b: Dictionary) -> void:
	if o.pos == Vector2.INF:
		return
	var g = o.g
	var r: float = float(b.get("r", 170.0)) * o.stat(&"op_range")
	var look: float = float(b.get("look", 260.0)) * o.stat(&"op_range")
	var half: float = float(b.get("half", 1.05))
	var skip: float = INF if not b.get("second", false) else float(o.gn.get("sb_s1_ang", INF))
	var ang := _sb_densest(o, look, half, skip)
	if not b.get("second", false):
		o.gn["sb_s1_ang"] = ang
		var b2: Dictionary = b.duplicate()   # 原作「可充能 2 次」：gap 秒后朝另一个最密方向再吹一下（延迟队列，同 seed 可复现）
		b2["second"] = true
		o.pending.append({"t": float(b.get("gap", 0.6)), "do": [b2]})
	var dir := Vector2.from_angle(ang)
	var dmg: float = o.base("atk", 0.0) * float(b.get("mult", 2.4)) * float(o.loc.dmg) * o._dmg_bonus() * o.skill_power()
	var kb: float = float(b.get("kb", 90.0))
	var hits: Array = o.arc_targets(o.pos, ang, half, r)
	for e in hits:
		if e.dead:
			continue
		o.log_hit(str(b.get("src", "铃音吹雪")), ["skill", "area"])
		o.deal_damage(e, dmg * (o.vs_elite() if e.elite or e.boss else 1.0))
		sb_cold(o, e, float(b.get("cold", 2.0)))
		if not e.dead and not e.boss and _movable(e):
			o.apply_kb(e, dir * kb * (0.3 if e.elite else 1.0))
			e["sb_push"] = float(g.t) + 0.8
	# 雪道：沿方向 n 格，每格 + layers 层
	var cs := _sb_cell(o)
	for i in int(b.get("lane_n", 5)):
		sb_add(o, sb_key(o, o.pos + dir * cs * (float(i) + 1.0)), int(b.get("lane_layers", 2)))
	_FXR.ev(o, "sb_blast", {"p": o.pos, "ang": ang, "r": r, "half": half, "es": hits})
	o.fx({"kind": "ring", "pos": o.pos + dir * r * 0.5, "r": r * 0.5, "r0": r * 0.2, "life": 0.3, "col": SB_ICE, "floor": true, "w": 3.0, "alpha": 0.8})


## look 内敌人最多的方向（8 方向扇形计数，同数取序号小的；skip = 第二下避开的方向，相差 < 半角的跳过）
static func _sb_densest(o, look: float, half: float, skip: float) -> float:
	var best := -1
	var ba := 0.0
	var near: Array = o.nearest_enemies(40, look, o.pos)
	for i in 8:
		var a: float = i * TAU / 8.0
		if skip != INF and absf(angle_difference(a, skip)) < half:
			continue
		var n := 0
		for e in near:
			if not e.dead and absf(angle_difference((e.pos - o.pos).angle(), a)) <= half:
				n += 1
		if n > best:
			best = n
			ba = a
	return ba


## 铺一圈雪（at 为心；r 内每格 + layers）：精一铃落（开阵命中处）、连携、终结技用
static func _sb_lay_ring(o, b: Dictionary, at: Vector2) -> void:
	var c: Vector2 = o.pos if str(b.get("at", "self")) == "self" else at
	if str(b.get("at", "")) == "leader":
		c = o.g.ppos
	if c == Vector2.INF:
		return
	var r: float = float(b.get("r", 60.0)) * o.stat(&"op_range")
	if b.get("hits", false):   # 铃落：开阵半径内的敌人脚下各 +layers 层
		for e in o.nearest_enemies(int(b.get("n", 12)), r, c):
			if _sb_ground_enemy(e):
				sb_add(o, sb_key(o, e.pos), int(b.get("layers", 1)))
		return
	for k in sb_keys_in(o, c, r):
		sb_add(o, k, int(b.get("layers", 1)))


# ---------------------------------------------------------------- 天赋「圣山的祝福」

## 队长受击（trig.on_hurt，延迟到下一帧执行）：队长周围 r 内敌人寒冷
static func _sb_chill(o, b: Dictionary) -> void:
	var g = o.g
	var r: float = float(b.get("r", 90.0))
	for e in o.nearest_enemies(16, r, g.ppos):
		sb_cold(o, e, float(b.get("cold", 1.5)))
	o.fx({"kind": "ring", "pos": g.ppos, "r": r, "r0": 12.0, "life": 0.25, "col": SB_ICE, "floor": true, "w": 2.0, "alpha": 0.7})


## data_operator.prevent_death：精一起一局一次；返回 true 时游戏把生命设成 1，下一次 tick 再补回 heal 比例
static func sb_prevent_death(o) -> bool:
	if int(o.elite) < 1 or not o.gn.has("sb"):
		return false
	var st: Dictionary = o.gn.sb
	if bool(st.bless) or not st.b.has("bless_heal"):
		return false
	st.bless = true
	st.bless_pending = true
	o.g.invuln = maxf(float(o.g.invuln), float(st.b.get("bless_self", 2.0)))
	return true


static func _sb_bless_apply(o, b: Dictionary) -> void:
	var st := sb_st(o)
	st.bless_pending = false
	var g = o.g
	g.hp = maxf(float(g.hp), float(g.max_hp) * float(b.get("bless_heal", 0.3)))
	var secs: float = float(b.get("bless_self", 2.0))
	g.invuln = maxf(float(g.invuln), secs)
	g.combat.add_root(secs, "冰封")
	var r: float = float(b.get("bless_r", 240.0))
	for e in o.nearest_enemies(200, r, g.ppos):
		sb_freeze(o, e, float(b.get("bless_freeze", 5.0)))
	for k in sb_keys_in(o, g.ppos, r):
		sb_add(o, k, int(b.get("max", 5)))
	g.vfx.show_banner("圣山的祝福 —— 队长免于倒下")
	_FXR.ev(o, "sb_bless", {"p": g.ppos, "r": r})


# ---------------------------------------------------------------- 画法（占位，只画；data_operator.draw_ground_fx 调）

## 雪斑贴图：3 种外形 × 5 层（层数 = 填充不透明度 + 底部亮点数），中上一个暗铜小铃
static func _sb_textures() -> Array:
	if not _sb_tex.is_empty():
		return _sb_tex
	var N := SB_TEX_N
	var bell := [Vector2i(6, 2), Vector2i(7, 2), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(4, 5), Vector2i(9, 5), Vector2i(6, 6), Vector2i(7, 6)]
	for v in 3:
		var row: Array = []
		for layer in 5:
			var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
			var inside := {}
			for y in N:
				for x in N:
					var dx: float = float(x) - 6.5
					var dy: float = float(y) - 6.5
					var ang: float = atan2(dy, dx)
					var wob: float = 0.55 * sin(ang * float(3 + v) + float(v) * 1.7) + 0.35 * cos(ang * 5.0 - float(v))
					if sqrt(dx * dx + dy * dy) <= 6.0 + wob:
						inside[Vector2i(x, y)] = true
			var fa: float = 0.40 + 0.11 * float(layer)
			for p in inside:
				var edge := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not inside.has(p + d):
						edge = true
				var c: Color = SB_EDGE if edge else SB_ICE
				var a: float = minf(1.0, fa + (0.18 if edge else 0.0))
				if not edge and (p.x + p.y * 3 + v) % 11 == 0:
					c = Color(0.86, 0.95, 1.0)
				img.set_pixelv(p, Color(c.r, c.g, c.b, a))
			for p in bell:
				if inside.has(p):
					img.set_pixelv(p, Color(SB_BELL.r, SB_BELL.g, SB_BELL.b, 0.55 + 0.08 * float(layer)))
			var n := layer + 1
			var x0 := 7 - n
			for i in n:
				var pp := Vector2i(x0 + i * 2, 10)
				if inside.has(pp):
					img.set_pixelv(pp, Color(SB_PIP.r, SB_PIP.g, SB_PIP.b, 1.0))
			row.append(ImageTexture.create_from_image(img))
		_sb_tex.append(row)
	return _sb_tex


static func sb_draw_ground(o) -> void:
	var st: Dictionary = o.gn.sb
	if st.cells.is_empty() and st.wave.is_empty() and st.storms.is_empty():
		return
	var cv = o.cv
	var tx := _sb_textures()
	var cs := _sb_cell(o)
	var px: float = cs / float(SB_TEX_N)
	var sz := Vector2(SB_TEX_N * px, SB_TEX_N * px)
	var w: Dictionary = st.wave
	var wr := -1.0
	if not w.is_empty():
		wr = float(st.b.get("wave_r", 240.0)) * o.stat(&"op_range") * clampf(float(w.t) / float(st.b.get("wave_t", 0.6)), 0.0, 1.0)
	for k in st.order:
		var n: int = int(st.cells.get(k, 0))
		if n <= 0:
			continue
		var h: int = absi(k.x * 73856093 ^ k.y * 19349663)
		var tex: Texture2D = tx[h % 3][clampi(n, 1, 5) - 1]
		var c := sb_center(o, k)
		var mod := Color(1, 1, 1, 1)
		if wr >= 0.0 and absf(c.distance_to(w.c) - wr) < cs * 0.7:   # 霜涛经过的雪格提亮（没雪处圈是断的）
			mod = Color(1.6, 1.7, 1.8, 1.0)
		cv.draw_texture_rect(tex, Rect2(c - sz * 0.5, sz), false, mod)
	for s in st.storms:
		var r: float = float(st.b.get("n5b_r", 50.0))
		cv.draw_set_transform(s.c, 0.0, Vector2(1.0, 0.55))
		cv.draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(SB_ICE.r, SB_ICE.g, SB_ICE.b, 0.5), 2.0)
		cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
