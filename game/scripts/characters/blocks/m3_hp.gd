## Mon3tr 血条 / 倒下 / 复活 / 治疗分配（docs/plans/2026-10-29-mon3tr-hp-plan.md；用户 10-29 定 5 项）
## 随行召唤物定义里写了 hp_k 的才走这套（kaltsit.json blocks.summons.mon3tr）；总开关 balance.json kaltsit/m3_hp（0 = 回旧行为：Mon3tr 无敌、治疗只给队长）。
##
## 规则（数值缺省在干员 base 的 m3_*，balance.json kaltsit/m3_* 同名键可覆盖，云端配对 / 调参用）：
##   血量   上限 = 队长当前生命上限 × hp_k（m3_hp_k 3.0），随队长成长同比例涨；脱战 3 秒后 regen_secs（20 秒）回满
##   受击   近战怪（非 Boss）碰到它：每只怪每 1 秒一次，e.dmg × hurt_mult（0.4）；敌弹 / Boss / 区域不打它（v1）
##   仇恨   aggro_r（150）内的近战怪里 aggro_share（0.35）比例改追它（按怪 id 的黄金比哈希定，不取随机数、结果不变）
##   倒下   血空倒地 revive_secs（18）秒，躺在原地；到时在队长身边起身，回 revive_hp（50%）血、revive_inv（1）秒无敌。
##          精英二后倒下触发「不毁重构」小爆（blocks.summons.mon3tr.on_down，积木自己写 cond）；熔毁终结技用掉 Mon3tr 走同一倒计时（down(…, silent)）
##   治疗   凯尔希的治疗拍（attack 的 heal 积木，split: true）每拍只给一个人：队长危险 → 队长；否则百分比低的先治（不比队长低留给队长；m3_heal_gap 可加迟滞）；
##          Mon3tr 拿到的拍数在最近 10 秒里不超过 m3_heal_share_max（40%）；给 Mon3tr 的量 = pct × Mon3tr 上限 × 同样的干员倍率 × heal_k（2.0）。
##          庇护（积木的 on_over）算 Mon3tr 身上的溢出治疗
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const ArtS = preload("res://scripts/art.gd")
const VisGrowth = preload("res://scripts/characters/blocks/vis_growth.gd")

const GOLD := 0.6180339887


## 总开关（balance.json kaltsit/m3_hp，缺省 1）
static func on() -> bool:
	return Bal.v("kaltsit/m3_hp", 1.0) > 0.0


## 旋钮：balance.json kaltsit/<key> 覆盖，否则取干员 base 的 <key>，再否则 def
static func k(o, key: String, def: float) -> float:
	return Bal.v("kaltsit/" + key, o.base(key, def))


## 遥测（只记账；telemetry 没建时跳过）
static func _tel(g, key: String, v: float) -> void:
	if g.get("telemetry") != null:
		g.telemetry.note_m3(key, v)


## --m3log：倒地 / 复活 / 治疗落点打日志（找录像时刻用；不带参数不打印）
static func _log(g, text: String) -> void:
	if (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()).has("--m3log"):   # 不用 Cfg：核心契约测试以 --script 跑、没有 autoload
		print("M3 t=%.2f %s" % [g.t, text])


## 这只召唤物走血条规则吗（spawn 时写了 s.m3）
static func has(s: Dictionary) -> bool:
	return s.has("m3")


static func is_down(s: Dictionary) -> bool:
	return float(s.get("down", 0.0)) > 0.0


## 开场：血量 / 状态（sm_spawn 的随行分支调用；kd 没写 hp_k 或开关关 → 不动，保持无敌）
static func init(o, s: Dictionary, kd: Dictionary) -> void:
	if not kd.has("hp_k") or not on():
		return
	s["m3"] = {"inv": 0.0, "calm": 99.0, "show": 0.0, "hit_t": -99.0, "hurt_by": {}}
	s["down"] = 0.0
	s.inv = false
	s.max_hp = maxf(1.0, o.g.max_hp * float(kd.hp_k))
	s.hp = s.max_hp


## 每帧（sm_tick 的随行分支，在 mf_step 之前）。返回 true = 倒地中，调用方跳过移动 / 出手
static func tick(o, s: Dictionary, kd: Dictionary, dt: float, rest: Vector2) -> bool:
	var g = o.g
	var m: Dictionary = s.m3
	_lead_hist(o, dt)
	# 上限随队长成长换算，血量比例不变
	var mx: float = maxf(1.0, g.max_hp * float(kd.hp_k))
	if absf(mx - float(s.max_hp)) > 0.01:
		s.hp = float(s.hp) * mx / float(s.max_hp)
		s.max_hp = mx
	m.inv = maxf(0.0, float(m.inv) - dt)
	m.show = maxf(0.0, float(m.show) - dt)
	m.calm = float(m.calm) + dt
	if is_down(s):
		s.down = float(s.down) - dt
		_tel(g, "down_secs", dt)
		if float(s.down) <= 0.0:
			_revive(o, s, kd, rest)
		return is_down(s)
	_contact(o, s, kd, m)
	if float(s.hp) <= 0.0:
		down(o, s, kd, float(k(o, "m3_revive_secs", 18.0)), false)
		return true
	if float(m.calm) >= 3.0 and float(s.hp) < float(s.max_hp):
		var rs: float = maxf(1.0, k(o, "m3_regen_secs", 20.0))
		var add: float = float(s.max_hp) / rs * dt
		s.hp = minf(float(s.max_hp), float(s.hp) + add)
		_tel(g, "regen", add)
	return false


## 仇恨 + 接触伤害：近战怪（非 Boss、非箱子）进 aggro_r 内按怪 id 哈希定它追不追 Mon3tr；碰到身体的每 1 秒伤一次
static func _contact(o, s: Dictionary, kd: Dictionary, m: Dictionary) -> void:
	var g = o.g
	var ar: float = k(o, "m3_aggro_r", 150.0)
	var share: float = k(o, "m3_aggro_share", 0.35)
	var hm: float = k(o, "m3_hurt_mult", 0.4)
	var br: float = float(kd.get("r", 14.0))
	for j in o.query_ids(s.pos, maxf(ar, br + 40.0)):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.boss or e.ai != "melee" or e.get("coma", false) or e.get("under", false) or e.get("dormant", false):
			continue
		var d: float = e.pos.distance_to(s.pos)
		if d <= ar and fposmod(float(e.id) * GOLD, 1.0) < share:
			o.set_aggro(e, s.pos)
		if e.dmg <= 0.0 or float(m.inv) > 0.0 or d > float(e.r) + br or float(m.hurt_by.get(e.id, -1.0)) > g.t:
			continue
		m.hurt_by[e.id] = g.t + 1.0
		var dmg: float = float(e.dmg) * hm
		s.hp = float(s.hp) - dmg
		s.flash = 0.15
		m.show = 3.0
		m.calm = 0.0
		m.hit_t = g.t
		_tel(g, "hurt", dmg)
	if m.hurt_by.size() > 64:
		for key in m.hurt_by.keys():
			if float(m.hurt_by[key]) <= g.t:
				m.hurt_by.erase(key)


## 倒地：secs 秒后复活。silent = 终结技自爆用掉它（不播倒地提示、不触发 on_down 小爆，自己的爆炸另算）
static func down(o, s: Dictionary, kd: Dictionary, secs: float, silent: bool) -> void:
	var g = o.g
	s.down = maxf(0.1, secs)
	s.hp = 0.0
	s.erase("dash")
	s.act = 0.0
	s.fire = -1.0
	s.pend = []
	s.tgt = null
	s.mv = 0.0
	s.ak = "idle"
	s.m3.show = 0.0
	_tel(g, "downs", 1.0)
	_log(g, "down secs=%.0f silent=%s leader_hp=%.0f%%" % [secs, str(silent), 100.0 * g.hp / maxf(1.0, g.max_hp)])
	if silent:
		return
	_tel(g, "downs_hit", 1.0)
	o.fx({"kind": "ring", "pos": s.pos, "r": 26.0, "r0": 6.0, "life": 0.35, "col": Color(0.7, 0.72, 0.8), "floor": true, "w": 2.0, "alpha": 0.7})
	o.float_text(s.pos + Vector2(0, -56), "Mon3tr 倒地", Color(0.75, 0.78, 0.85), 14)
	if kd.has("on_down"):
		o._exec_list(kd.on_down, s.pos)   # 精英二：「不毁重构」小爆（积木自己写 cond: elite >= 2）


static func _revive(o, s: Dictionary, kd: Dictionary, rest: Vector2) -> void:
	var g = o.g
	s.down = 0.0
	s.pos = rest
	s.hp = float(s.max_hp) * clampf(k(o, "m3_revive_hp", 0.5), 0.05, 1.0)
	s.m3.inv = k(o, "m3_revive_inv", 1.0)
	s.m3.calm = 0.0
	s.m3.show = 3.0
	s.m3.hurt_by = {}
	s.flash = 0.3
	_log(g, "revive hp=%.0f" % float(s.hp))
	o.fx({"kind": "ring", "pos": s.pos, "r": 34.0, "r0": 6.0, "life": 0.4, "col": Color(0.55, 1.0, 0.5), "floor": true, "w": 2.5, "alpha": 0.8})
	o.float_text(s.pos + Vector2(0, -56), "Mon3tr 复活", Color(0.55, 1.0, 0.5), 14)


# ---------------------------------------------------------------- 治疗分配

## 在场且没倒的 Mon3tr（没有 = null）
static func live(o):
	if o.sm.is_empty():
		return null
	for s in o.sm.list:
		if has(s) and not is_down(s) and not s.gone:
			return s
	return null


## 起手条件 hurt_any 里的一项：Mon3tr 没满血
static func hurt_any(o) -> bool:
	var s = live(o)
	return on() and s != null and float(s.hp) < float(s.max_hp) - 0.5


## 队长生命的 3 秒滑窗（找 3 秒内掉了多少）
static func _lead_hist(o, dt: float) -> void:
	var g = o.g
	var st: Dictionary = o.sm
	if not st.has("lhist"):
		st["lhist"] = []
		st["m3heal"] = []
	var h: Array = st.lhist
	if h.is_empty() or g.t - float(h[-1][0]) >= 0.25:
		h.append([g.t, g.hp])
	while not h.is_empty() and float(h[0][0]) < g.t - 3.0:
		h.pop_front()


static func _burst(o) -> float:
	var top: float = o.g.hp
	for p in o.sm.get("lhist", []):
		top = maxf(top, float(p[1]))
	return top - o.g.hp


## 这一拍治疗给谁：返回 Mon3tr 的召唤物字典；null = 给队长
static func heal_pick(o):
	if not on():
		return null
	return _pick(o, live(o))


## 编队里第一只在场、没倒、没满血的 Mon3tr：[凯尔希, 召唤物]；没有 = []
static func hurt_entry(g) -> Array:
	if not on() or g.get("squad") == null:
		return []
	for o in g.squad.ops:
		if o.get("sm") is Dictionary and not o.sm.is_empty():
			var s = live(o)
			if s != null and float(s.hp) < float(s.max_hp) - 0.5:
				return [o, s]
	return []


## 别的医疗干员（流明）这一拍治疗给谁（10-31 修：原来只有凯尔希自己的治疗拍会分给 Mon3tr，别的医疗只治队长）。
## 规则与凯尔希同一套（队长危险 → 队长；Mon3tr 百分比更低才给；10 秒内给 Mon3tr 的拍数不超过 m3_heal_share_max，记在凯尔希身上共用）
static func heal_pick_mate(g) -> Array:
	var en := hurt_entry(g)
	if en.is_empty():
		return []
	return en if _pick(en[0], en[1]) != null else []


## 别的医疗干员治 Mon3tr：h = 这一拍本来给队长的量（世界数值）；按队长生命上限折成比例再 × Mon3tr 上限 × m3_heal_k（同凯尔希口径）
static func heal_from_mate(caster, owner, s: Dictionary, h: float, col: Color) -> void:
	var g = caster.g
	var v: float = float(s.max_hp) * h / maxf(1.0, g.max_hp) * k(owner, "m3_heal_k", 2.0) * g.heal_mult
	var got: float = minf(v, float(s.max_hp) - float(s.hp))
	s.hp = minf(float(s.max_hp), float(s.hp) + v)
	_tel(g, "heal_to_m3", got)
	_tel(g, "heal_ticks_m3", 1.0)
	_log(g, "heal(mate %s)->m3 +%.0f m3=%.0f%% leader=%.0f%% lead_h=%.1f" % [caster.id, v, 100.0 * float(s.hp) / float(s.max_hp), 100.0 * g.hp / maxf(1.0, g.max_hp), h])
	heal_fx(caster, s, v, col)


## 治疗打到 Mon3tr 身上的画面（凯尔希 / 别的医疗共用，10-31 用户「要看得出治疗打到了它身上」）：
## 施术者手部 → Mon3tr 胸口的治疗光束（命中端一圈闪光）、脚下扩散环、身上冒绿色治疗粒子、头顶飘「+数字」（同队长被治疗）
static func heal_fx(caster, s: Dictionary, v: float, col: Color) -> void:
	var g = caster.g
	var hit: Vector2 = s.pos + Vector2(0, -30)
	s.flash = 0.15
	s.m3.show = 3.0
	caster.fx({"kind": "beam", "a": caster.pos + Vector2(0, -28), "b": hit, "life": 0.3, "max": 0.3, "col": col, "w": 3.0})
	caster.fx({"kind": "glow", "pos": hit, "r": 14.0, "life": 0.3, "col": col, "alpha": 0.6})
	caster.fx({"kind": "ring", "pos": s.pos, "r": 26.0, "r0": 6.0, "life": 0.4, "col": HEAL_COL, "floor": true, "w": 2.0, "alpha": 0.7})
	for q in 7:
		caster.fx({"kind": "mote", "pos": s.pos + Vector2(g.vrng.randf_range(-14, 14), g.vrng.randf_range(-40, -6)), "vel": Vector2(g.vrng.randf_range(-10, 10), g.vrng.randf_range(-60, -35)),
			"life": g.vrng.randf_range(0.45, 0.75), "col": HEAL_COL * 1.4, "sz": 2.0})
	caster.float_text(s.pos + Vector2(0, -78), "+%d" % int(v), HEAL_COL, 14)


const HEAL_COL := Color(0.55, 1.0, 0.5)


## 治疗分配主体（凯尔希自己 / 别的医疗共用；rec 记在凯尔希 o.sm 上）
static func _pick(o, s):
	if s == null or float(s.hp) >= float(s.max_hp) - 0.5:
		return null
	var g = o.g
	var fl: float = g.hp / maxf(1.0, g.max_hp)
	if fl < k(o, "m3_danger_hp", 0.45) or g.nerve >= 0.6 * g.combat.nerve_max() or _burst(o) >= k(o, "m3_danger_burst", 0.2) * g.max_hp:
		return null
	var fm: float = float(s.hp) / float(s.max_hp)
	if fm >= fl - k(o, "m3_heal_gap", 0.0):
		return null
	var rec: Array = o.sm.get("m3heal", [])
	while not rec.is_empty() and float(rec[0][0]) < g.t - 10.0:
		rec.pop_front()
	var to_m3 := 0
	for r in rec:
		if r[1]:
			to_m3 += 1
	if rec.size() > 0 and float(to_m3) / float(rec.size()) >= k(o, "m3_heal_share_max", 0.4):
		rec.append([g.t, false])
		return null
	rec.append([g.t, true])
	return s


## 治疗拍落在 Mon3tr 身上：量 = pct × Mon3tr 上限 × 干员倍率 × heal_k；返回溢出量（庇护等 on_over 看它）
static func heal_apply(o, s: Dictionary, b: Dictionary) -> float:
	var g = o.g
	var mult: float = 1.0
	if str(b.get("scale", "")) == "op":
		mult = o.stat(&"op_atk") * g.ally_mult * o.stat(&"heal_out") * float(o.loc.heal)
	else:
		mult = float(o.loc.heal)
	var h: float = float(s.max_hp) * float(b.pct) * mult * k(o, "m3_heal_k", 2.0) * g.heal_mult
	var over: float = maxf(0.0, float(s.hp) + h - float(s.max_hp))
	var got: float = minf(h, float(s.max_hp) - float(s.hp))
	s.hp = minf(float(s.max_hp), float(s.hp) + h)
	_tel(g, "heal_to_m3", got)
	_tel(g, "heal_ticks_m3", 1.0)
	_log(g, "heal->m3 +%.0f m3=%.0f%% leader=%.0f%%" % [h, 100.0 * float(s.hp) / float(s.max_hp), 100.0 * g.hp / maxf(1.0, g.max_hp)])
	heal_fx(o, s, h, HEAL_COL)
	return over


# ---------------------------------------------------------------- 画面

## 倒地：待机帧转 90° 的灰色剪影 + 复活读秒弧（同无 death 条的队友，character._draw_downed）
static func draw_down(o, s: Dictionary, kd: Dictionary, fr: Array, hov: float) -> void:
	var g = o.g
	var tx: Texture2D = fr[0]
	var hf: int = maxi(1, int(fr[2]))
	var fw: float = float(tx.get_width()) / hf
	var fh: float = float(tx.get_height())
	var pk: float = g.PX / ArtS.hires_of(tx) * VisGrowth.summon_scale(g)
	var foot: Vector2 = (s.pos + Vector2(0, hov) + g.draw_off).round()
	o._cv_flush()
	o.cv.draw_set_transform(foot, -PI / 2.0 if float(s.face) >= 0.0 else PI / 2.0, Vector2(pk, pk))
	o.cv.draw_texture_rect_region(tx, Rect2(Vector2(-fw / 2.0, -fh + o.foot_off(tx, str(fr[3]))), Vector2(fw, fh)), Rect2(fw * int(fr[1]), 0, fw, fh), Color(0.55, 0.58, 0.68, 0.9))
	o.cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var total: float = maxf(0.1, k(o, "m3_revive_secs", 18.0))
	var c: Vector2 = s.pos + Vector2(0, -34)
	o.cv.draw_arc(c, 9.0, 0.0, TAU, 20, Color(0.02, 0.03, 0.04, 0.8), 3.0)
	o.cv.draw_arc(c, 9.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(1.0 - float(s.down) / total, 0.0, 1.0), 20, Color(0.85, 0.87, 0.9), 2.0)


## 头顶短血条：受击后 3 秒、或血量低于 60% 时画
## 编队里所有在场的 Mon3tr 条目 [[干员, 召唤物], …]（HUD 血条行用）
static func entries(g) -> Array:
	var out: Array = []
	if not on() or g.get("squad") == null:
		return out
	for o in g.squad.ops:
		var st = o.get("sm")
		if st is Dictionary and st.has("list"):
			for s in st.list:
				if has(s) and not s.gone:
					out.append([o, s])
	return out
