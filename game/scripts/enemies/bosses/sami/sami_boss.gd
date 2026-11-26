## 萨米 Boss 公共基类（docs/393、docs/392 §6；11-21 先接招式与数值，画面一律占位：预警走现成 telegraph 样式，弹幕走 mid_cards 通用弹体 + 专属色 bcol）。
## 伤害一栏按 docs/393 口径写「占队长最大生命的比例」：pd(e, 0.2) = e.dmg × 0.2 × 100 ÷ 数据 dmg，所以生命 / 伤害倍率、难度档照常作用在 e.dmg 上，
## 比例只决定招与招之间谁重谁轻。弹体伤害再除掉 mid_cards 的 boss/mid_pattern_dmg 与敌弹 enemy/bullet_dmg_mult，保证一发也是 pd。
## 每只 Boss 写 moves(e) 返回本幕可用的招式表 [[名, 冷却, 最近距离, 最远距离, Callable(e, dir, dist) -> 占用秒数（<0 = 放不出）], …]，
## 基类按顺序挑第一条冷却好、距离合适的；延时段（连发、波次）用 later(e, 秒, Callable) 排进 e.sq，每帧 tick 推进。
extends "res://scripts/enemies/bosses/boss_base.gd"

const MC = preload("res://scripts/enemies/mid_cards.gd")
const GAP := 0.38   # 缺口环每个缺口的半角（150 px 处约 110 px 弧长，≥80，docs/359 §2.3）

var tint2_col := Color(0.9, 0.95, 1.1)


func base_dmg(e: Dictionary) -> float:
	return maxf(1.0, float(D.ENEMIES.get(e.type, {}).get("dmg", 16.0)))


## 占队长最大生命 pct 的一下（再乘回荡段 / 决胜等脚本自己的倍率 e.dmg_k）
func pd(e: Dictionary, pct: float) -> float:
	return e.dmg * pct * 100.0 / base_dmg(e) * float(e.get("dmg_k", 1.0)) * Bal.v("boss/sami_dmg_k", 1.0)


func col(e: Dictionary) -> Color:
	return g.vfx.boss_color(e.type)


func act_i(e: Dictionary) -> int:
	return int(e.get("gates_passed", 0))


## ---- 弹幕（mid_cards 通用弹体：tier 0 小 / 1 中 / 2 大；o 同 MC.shot：hold 显形秒、acc、turn、split、life）
func shot(e: Dictionary, pos: Vector2, ang: float, spd: float, tier: int, pct: float, o := {}) -> void:
	var o2: Dictionary = o.duplicate()
	o2["mult"] = pd(e, pct) / maxf(0.01, e.dmg) / maxf(0.01, Bal.v("boss/mid_pattern_dmg", 0.7) * Bal.v("enemy/bullet_dmg_mult", 0.75))
	var n0: int = g.ebullets.size()
	MC.shot(g, e, pos, ang, spd, tier, o2)
	if o.get("small", false) and g.ebullets.size() > n0:
		g.ebullets[g.ebullets.size() - 1]["sfx_small"] = true   # 画面：成片铺满的招用 19 号小弹（docs/401 §19）


func ring(e: Dictionary, c: Vector2, n: int, spd: float, tier: int, pct: float, gaps: Array = [], a0 := 0.0, o := {}) -> void:
	for i in n:
		var a: float = a0 + TAU * float(i) / float(n)
		var skip := false
		for ga in gaps:
			if absf(angle_difference(a, float(ga))) < GAP:
				skip = true
		if not skip:
			shot(e, c, a, spd, tier, pct, o)


func fan(e: Dictionary, c: Vector2, ang: float, half: float, n: int, spd: float, tier: int, pct: float, o := {}) -> void:
	for i in n:
		var a: float = ang + (lerpf(-half, half, float(i) / float(n - 1)) if n > 1 else 0.0)
		shot(e, c, a, spd, tier, pct, o)


func aim(e: Dictionary, c: Vector2, n: int, step: float, spd: float, tier: int, pct: float, o := {}) -> void:
	fan(e, c, (g.ppos - c).angle(), step * float(n - 1) * 0.5, n, spd, tier, pct, o)


## 缺口朝向：缺口环两个缺口，一个朝主控（保证能躲），一个对面偏 90°
func gaps_at(c: Vector2, k := 2) -> Array:
	var a: float = (g.ppos - c).angle()
	return [a] if k <= 1 else [a, a + PI * 0.6]


## ---- 预警（结算走 telegraph 现成 act：sweep 扇形 / shot 直线 / lob 落点圈 / stab 突进）
func w_cone(e: Dictionary, ang: float, half: float, r: float, dur: float, pct: float, nm: String, x := {}) -> Dictionary:
	var d := {"ang": ang, "half": half, "r": r, "follow": true, "act": "sweep", "name": nm, "col": col(e), "dmg": pd(e, pct), "skin": "mc_cone"}
	if pct <= 0.0:
		d.act = "tell"   # 只画预警（雪幕扇形、道标线等弹幕前的提示），结算不判伤害
	d.merge(x, true)
	return _warn(e, "cone", dur, d)


func w_line(e: Dictionary, ang: float, ln: float, wid: float, dur: float, pct: float, nm: String, x := {}) -> Dictionary:
	var d := {"ang": ang, "len": ln, "wid": wid, "act": "shot", "name": nm, "col": col(e), "dmg": pd(e, pct), "skin": "mc_line"}
	if pct <= 0.0:
		d.act = "tell"   # 只画预警（雪幕扇形、道标线等弹幕前的提示），结算不判伤害
	d.merge(x, true)
	return _warn(e, "line", dur, d)


func w_circle(e: Dictionary, pos: Vector2, r: float, dur: float, pct: float, nm: String, x := {}) -> Dictionary:
	var d := {"pos": pos, "r": r, "act": "lob", "name": nm, "col": col(e), "dmg": pd(e, pct)}
	if pct <= 0.0:
		d.act = "tell"   # 只画预警（雪幕扇形、道标线等弹幕前的提示），结算不判伤害
	d.merge(x, true)
	return _warn(e, "circle", dur, d)


func w_self(e: Dictionary, r: float, dur: float, pct: float, nm: String, x := {}) -> Dictionary:
	var d := {"follow": true, "r": r, "act": "lob", "name": nm, "col": col(e), "dmg": pd(e, pct)}
	if pct <= 0.0:
		d.act = "tell"   # 只画预警（雪幕扇形、道标线等弹幕前的提示），结算不判伤害
	d.merge(x, true)
	return _warn(e, "circle", dur, d)


## 直线突进：沿线冲 ln（结算时一次性判定整条线 + 本体被推过去），冲完 e.kb 按 900/s² 减速
func w_stab(e: Dictionary, ang: float, ln: float, wid: float, dur: float, pct: float, nm: String, x := {}) -> Dictionary:
	var d := {"ang": ang, "len": ln, "wid": wid, "act": "stab", "spd": sqrt(1800.0 * ln), "name": nm, "col": col(e), "dmg": pd(e, pct), "skin": "mc_line"}
	if pct <= 0.0:
		d.act = "tell"   # 只画预警（雪幕扇形、道标线等弹幕前的提示），结算不判伤害
	d.merge(x, true)
	return _warn(e, "line", dur, d)


## ---- 直接判定（脚本自己的场上实体、地形推进等）：按落点圈结算一次，伤害口径同预警（docs/393 §12）
func hit_now(e: Dictionary, pos: Vector2, r: float, pct: float, x := {}) -> bool:
	var hp0: float = g.hp
	var w := {"shape": "circle", "pos": pos, "r": r, "owner": e, "dmg": pd(e, pct), "act": "lob", "corrode": 0.0}
	w.merge(x, true)
	g.tele.warn_damage(w)
	return g.hp < hp0


## ---- 临时障碍（冰桩 / 冰峰 / 冰柱，docs/393 §11.10）：e.obst = [{pos, r, until}]；挡队长走路（每帧推出去），也挡 Boss 自己的弹
func add_obst(e: Dictionary, pos: Vector2, r: float, life: float) -> void:
	if not e.has("obst"):
		e["obst"] = []
	e.obst.append({"pos": pos, "r": r, "until": g.t + life})


func obst_tick(e: Dictionary) -> void:
	if not e.has("obst") or e.obst.is_empty():
		return
	e.obst = e.obst.filter(func(o): return float(o.until) > g.t)
	for o in e.obst:
		var d: Vector2 = g.ppos - o.pos
		var rr: float = float(o.r) + 10.0
		if d.length() < rr:
			g.ppos = o.pos + (d.normalized() if d.length() > 0.1 else Vector2.DOWN) * rr
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id):
			for o in e.obst:
				if b.pos.distance_to(o.pos) < float(o.r):
					b.life = 0.0
					break


func obst_at(e: Dictionary, p: Vector2, pad := 0.0) -> bool:
	for o in e.get("obst", []):
		if p.distance_to(o.pos) < float(o.r) + pad:
			return true
	return false


## ---- 延时队列
func later(e: Dictionary, delay: float, f: Callable) -> void:
	if not e.has("sq"):
		e["sq"] = []
	e.sq.append([g.t + delay, f])


func tick(e: Dictionary, dt: float) -> void:
	MC.step_shots(g, e, dt)
	if e.has("sq") and not e.sq.is_empty():
		var due: Array = []
		var keep: Array = []
		for it in e.sq:
			if g.t >= float(it[0]):
				due.append(it)
			else:
				keep.append(it)
		e.sq = keep
		for it in due:
			if not e.dead and not e.get("coma", false):
				(it[1] as Callable).call()
	if act_i(e) >= 1:
		_tint2(e, tint2_col)


## 选招：本帧可以出招且不在上一招的占用时间里 → 可放的招里挑最久没放过的（11-26：原来按表顺序放第一条，表尾的招会被冷却短的招一直挤掉）
func pick(e: Dictionary, ready: bool, dir: Vector2, dist: float) -> void:
	if not ready or g.t < float(e.get("busy_t", 0.0)) or e.get("coma", false):
		return
	if not e.has("used_t"):
		e["used_t"] = {}
	var cand: Array = []
	for m in moves(e):
		if dist < float(m[2]) or dist > float(m[3]):
			continue
		if float(e.get("cds", {}).get(str(m[0]), 0.0)) > g.t:
			continue
		cand.append(m)
	cand.sort_custom(func(x, y): return float(e.used_t.get(str(x[0]), -1.0)) < float(e.used_t.get(str(y[0]), -1.0)))
	for m in cand:
		var busy: float = float((m[4] as Callable).call(e, dir, dist))
		if busy < 0.0:
			continue
		_cd(e, str(m[0]), float(m[1]) * float(e.get("cd_k", 1.0)))
		e.used_t[str(m[0])] = g.t
		e.busy_t = g.t + busy
		return


## 本幕招式表（子类覆写）
func moves(_e: Dictionary) -> Array:
	return []


## 验收用：全部招式（各幕合起来）
func all_moves(e: Dictionary) -> Array:
	return moves(e)


func demo_moves(e: Dictionary) -> Array:
	return all_moves(e).map(func(m): return str(m[0]))


func force_move(e: Dictionary, nm: String, dir: Vector2, dist: float) -> bool:
	for m in all_moves(e):
		if str(m[0]) == nm:
			return float((m[4] as Callable).call(e, dir, dist)) >= 0.0
	return false


## ---- 受伤倍率：脆弱窗口 vuln(e, 秒, 倍率) + 子类 base_taken
func vuln(e: Dictionary, dur: float, mult: float) -> void:
	e["vuln_until"] = maxf(float(e.get("vuln_until", 0.0)), g.t + dur)
	e["vuln_mult"] = mult
	e["brk_len"] = dur
	e["break_ring_until"] = e.vuln_until


func taken_mult(e: Dictionary) -> float:
	var m: float = base_taken(e)
	if float(e.get("vuln_until", 0.0)) > g.t:
		m *= float(e.get("vuln_mult", 1.0))
	return m


func base_taken(_e: Dictionary) -> float:
	return 1.0


## 召机制小怪（照常掉经验）
func summon(e: Dictionary, type: String, n: int, r := 60.0, at := Vector2.INF) -> Array:
	var out: Array = []
	if not D.ENEMIES.has(type):
		return out
	var c: Vector2 = e.pos if at == Vector2.INF else at
	for i in n:
		var p: Vector2 = c + Vector2.from_angle(TAU * float(i) / float(maxi(1, n)) + float(e.id % 7)) * r
		out.append(g.spawner.spawn_enemy(type, p))
	return out


func kingdoms():
	return g.mech("kingdom")


## 攻击特效模块（themes/sami/mech/mech_fx.gd，docs/401；只画）。没装（别的主题借脚本）时返回 null，调用方判空
func sfx():
	return g.mech("fx")


## ---- 常驻弹幕（11-26 用户：结局 Boss 弹幕密度不低于水月最终 Boss，同屏均值 ≥60）：慢、可躲、低伤的底层图案，招式叠在上面
## kind：snow（意志，北边落雪，银凇挡）/ shard（木裂，周身冰屑环，朝队长留缺口）/ petal（克雷松，苗圃飘出的打旋花瓣）/ sand（双王，自西向东的沙粒条）
func ambient(e: Dictionary, dt: float, kind: String) -> void:
	if e.get("coma", false) or e.get("invuln", false):
		return
	e["amb_acc"] = float(e.get("amb_acc", 0.0)) + dt
	var c: Vector2 = center(e)
	var ar: float = float(D.ENEMIES[e.type].get("arena_r", 520.0))
	var k: int = int(e.get("amb_n", 0))
	match kind:
		"snow":
			while float(e.amb_acc) >= 0.14:   # 每秒 7 片，速 90，约 9 秒落到底
				e.amb_acc = float(e.amb_acc) - 0.14
				k += 1
				var x: float = c.x + (float((k * 7919) % 1000) / 1000.0 * 2.0 - 1.0) * ar
				shot(e, Vector2(x, c.y - ar * 0.55), PI * 0.5 + (float((k * 31) % 7) - 3.0) * 0.04, 90.0, 1, 0.03, {"life": 9.5, "small": true})
		"shard":
			while float(e.amb_acc) >= 1.3:   # 每 1.3 秒一圈 14 片，速 80，朝队长留缺口
				e.amb_acc = float(e.amb_acc) - 1.3
				k += 1
				ring(e, e.pos, 14, 80.0, 1, 0.04, [(g.ppos - e.pos).angle()], float(k) * 0.26, {"life": 6.0, "small": true})
		"petal":
			while float(e.amb_acc) >= 0.25:   # 每秒 4 片，从苗圃（没有就从本体）飘出、打旋
				e.amb_acc = float(e.amb_acc) - 0.25
				k += 1
				var src: Vector2 = e.pos
				var km = kingdoms()
				if km != null:
					var ns: Array = km.list.filter(func(x): return x.kind == "nursery")
					if not ns.is_empty():
						src = ns[k % ns.size()].pos
				shot(e, src, float((k * 137) % 360) * PI / 180.0, 70.0, 1, 0.04, {"turn": 0.8 if k % 2 == 0 else -0.8, "life": 7.0, "small": true})
		"sand":
			while float(e.amb_acc) >= 1.6:   # 每 1.6 秒一行 7 粒，自西向东 110，行内留一个空位
				e.amb_acc = float(e.amb_acc) - 1.6
				k += 1
				var gap_i: int = k % 7
				for i in 7:
					if i == gap_i:
						continue
					var y: float = c.y - ar * 0.85 + ar * 1.7 * (float(i) + 0.5) / 7.0 + float(k % 3) * 20.0
					shot(e, Vector2(c.x - ar - 20.0, y), 0.0, 110.0, 1, 0.04, {"life": 9.8, "small": true})
	e["amb_n"] = k


## 场地中心（最终 Boss 冻结场地 = 缩圈圆心；中期 Boss 用出场时队长的位置）
func center(e: Dictionary) -> Vector2:
	if g.zone_frozen:
		return g.zone_c
	if not e.has("home"):
		e["home"] = g.ppos
	return e.home


## 占位画法挂钩（mech_kingdom.draw_ground 之后由 sami_draw 统一调；子类画自己的场上实体）
func draw(_e: Dictionary, _cv) -> void:
	pass


## ---- 测试机器人的主轴行为（docs/142b 第 7 条「测试机器人必须会主轴」；core/bot.gd 在 Boss 战里问这里）----
## 返回想去的方向（不必归一，长度当权重）；Vector2.INF = 没意见，走机器人原来的逻辑。
## --axisbot=0（调试）：机器人故意不理主轴（测「不理主轴用时 ×2」那一档）；各 Boss 的 axis_ignore 可写反着来的走法
static var _axis_mode := -1


func axis_on() -> bool:
	if _axis_mode < 0:
		_axis_mode = 0 if Cfg.dev_args().has("--axisbot=0") else 1
	return _axis_mode == 1


func bot_axis(e: Dictionary, p: Vector2) -> Vector2:
	return axis_do(e, p) if axis_on() else axis_ignore(e, p)


func axis_do(_e: Dictionary, _p: Vector2) -> Vector2:
	return Vector2.INF


func axis_ignore(_e: Dictionary, _p: Vector2) -> Vector2:
	return Vector2.INF


## 走到 q：到了（< tol）返回 ZERO（站定），否则单位方向
func go_to(p: Vector2, q: Vector2, tol := 14.0) -> Vector2:
	var d: Vector2 = q - p
	return Vector2.ZERO if d.length() < tol else d.normalized()


## 特效挂钩（docs/401 §11–14）：只画，不改玩法状态；没有 fx 机制时什么都不做
func _fx(kind: String, p: Vector2, a := 0.0, b := 0.0) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.blade_event(kind, p, a, b)


## 出招动作（纯画面，不进判定）：rel 秒后出手；world.gd._sfx_pose 按 <tex>_attack 帧条的出手帧对齐（docs/401 §17）
func pose(e: Dictionary, rel: float) -> void:
	e["sfx_pose"] = {"t0": g.t, "rel": g.t + maxf(0.0, rel)}


## 预警画法（docs/401 §12 / §15）：利刃 / 游荡者与结局四 Boss 有 fx 机制时挂 skin sami_blade，通用描边 / 填充跳过（telegraph_draw.quiet），
## 由 mech_fx 按各自元素画有体积的预警（裂缝 / 渗雾 / 实物先冒头）；原 skin 存 skin0
const FX_WARN := ["blade", "wanderer", "will", "lead", "cresson", "khan", "lion"]


func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	if g.mech("fx") != null and str(e.type) in FX_WARN:
		d["skin0"] = d.get("skin", "")
		d["skin"] = "sami_blade"
	return super(e, shape, dur, d)
