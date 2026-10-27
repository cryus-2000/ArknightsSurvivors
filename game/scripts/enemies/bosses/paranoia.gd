## 偏执泡影（type paranoia，docs/38 §2.4 / §8.5；招式改版 docs/95 §1，10-14）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 4 招：A 凝视（② 直线，手写）/ B 泡影环（④ 缺口环，patterns 数据）/ C 叠影（① 序列落点圈，patterns stack）/ D 呼号（③ 扇形，二阶段，手写）
## 机制不占名额：认知负担光环、茧 / 破茧、漂近
## 主轴「打落」（docs/142b §3.5 / §8.2，10-25）：三幕都靠冲刺穿身，只是每幕冲刺的用处不同
##   一幕「凝望」：悬浮时受伤 × paranoia_hover_taken（0.5）；冲刺穿过她 → 坠地 paranoia_drop_t（4）秒（破绽，合计受伤 × paranoia_drop_taken 1.8），
##     起身后 paranoia_drop_cd（2）秒内不能再打落。凝视 = 两道平行光束；泡影环缺口朝着你（缺口就是冲进去的路）
##   二幕「狂望」：分出 2 个幻影（_decoy_step）一起漂，只有真身在地上有影子；幻影也吃自动攻击（op_api._focus_bosses），挨 3 下散、6 秒后重新分出；
##     冲刺穿过幻影 = 幻影炸开（小伤害 + 减速 1 秒），丢一次冲刺。凝视改 X 交叉（交点在你脚下）
##   三幕「失声」（落地二阶段，茧后同）：光环张开时她受伤 × paranoia_aura_taken（0.5，取代原作的重攻速减益——攻速削减上限 −15%，§1.11）；
##     冲刺穿身 = 光环散掉 paranoia_aura_off（5）秒，正常受伤；呼号只在光环张开时放（每 6 秒）；泡影环 2 波错位缺口
##   连携攻势（docs/170，10-27）：每幕两组有限连段轮流 + 本作弹幕图案，在 paranoia_combos.gd；boss/paranoia_combos 0 = 回到下面的独立轮换
extends "res://scripts/enemies/bosses/boss_base.gd"

const COL := Color(0.9, 0.4, 1.0)
const BossBeam = preload("res://scripts/render/boss_beam.gd")
const MOVES := ["叠影", "凝视", "泡影环", "呼号"]
const Combos = preload("res://scripts/enemies/bosses/paranoia_combos.gd")

var _pc = null


func combos():
	if _pc == null:
		_pc = Combos.new(g, self)
	return _pc


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	if e.get("cocoon_t", 0.0) > 0.0:
		_paranoia_cocoon_step(e, dt)
		return
	_drop_step(e)
	_beam_hold(e)
	_decoy_step(e, dt)
	_paranoia_aura(e, dist)
	if Combos.on(e) and combos().step(e, dt, dir, dist, ready):
		return
	if not ready:
		return
	# 一阶段悬浮远程时的迫近（泡影漂近，协调人 9/30 定 b；close6b：落地前 on_boss 0.01–0.10，用时一一对应）
	if e.phase == 1 and _close_in(e, dir, dist, "paranoia", "泡影漂近", Color(0.85, 0.45, 1.0)) >= 0.0:
		return
	# D 呼号：落地后、光环张开、主控在 260 内，howl 6 秒（docs/142b §8.2「惩罚」：光环散掉的 5 秒里不放）；第一次先亮招式名 0.6 秒（§0.2）
	if e.phase == 2 and not _aura_off(e) and dist < 260.0 and float(e.get("cds", {}).get("howl", 0.0)) <= g.t:
		if _first_tell(e, "howl", "呼号") and _cd(e, "howl", Bal.v("boss/paranoia_howl_cd", 6.0)):
			_howl(e, dir)
		return
	# A 凝视：gaze 11 秒（第二幕 ×0.9）；一阶段 2 道、二阶段 3 道、茧未打破 +1
	if _cd(e, "gaze", 11.0 * (0.9 if int(e.get("gates_passed", 0)) >= 1 and e.phase == 1 else 1.0)):
		_gaze(e, dir)


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	_paranoia_p2(e)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES + g.bai.finals.NAMES["paranoia"] + Combos.EMITTERS.keys() + ["幻象冲撞"]


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if g.bai.finals.force_move(e, name, dir, dist):
		return true
	if Combos.EMITTERS.has(name):
		combos()._emit(e, name, dir)
		return true
	if name == "幻象冲撞":
		combos().rush(e, dir)
		return true
	match name:
		"凝视":
			_gaze(e, dir)
			return true
		"呼号":
			if e.phase != 2:
				return false
			_howl(e, dir)
			return true
		"叠影", "泡影环":
			e.pattern_force = name
			return g.bai.patterns.try_attack(e, dir, dist)
	return false


## A · 凝视：直线 820 × 26，e.dmg × 2.0，侵蚀 0.5，Kanpelle 淡紫光束（docs/142b §8.5）。按幕换形（§8.2）：
##   一幕三道——一道追踪 0.65 秒瞄你，两侧两道出手即锁定你当时的位置、从她两侧斜穿过来（10-25 用户「都要瞄准人打」，原为平行跑道）：锁定后横移；
##   二幕 X 交叉——两道以你脚下为交点、与「她 → 你」各成 ±0.6 弧度，出手即锁定：斜着离开交点；
##   三幕 / 茧后（落地）——原来的 3 道依次追踪（每道间隔 0.6 秒）。茧没打破 +1 道（依次追踪接在后面）
func _gaze(e: Dictionary, dir: Vector2) -> void:
	var base: Dictionary = {"len": 820.0, "wid": 26.0, "act": "beam", "col": COL, "dmg": e.dmg * Bal.v("boss/paranoia_gaze_mult", 1.56), "corrode": 0.5, "kp": "paranoia", "kp_k": 2.0, "skin": "gaze",
		"kp_life": 1.0, "kp_on": 0.2, "hold": 0.8}   # 持续光束：预警期蓄力（paranoia_combo_draw）→ 开火短闪 → 0.2 秒张开、保持到 0.8 秒（期间碰到算一次伤害）→ 0.2 秒变细并碎成颗粒（用户 10-27）   # skin gaze：预警由 paranoia_combo_draw 画（暗红低填充 + 泡沫边）   # 原 2.0（10-25 加密 ×0.78）
	var ng: int = 4   # 落地后依次 4 道（10-25 加密：原 3）
	if e.phase == 1 and int(e.get("gates_passed", 0)) >= 1:
		ng = 0
		# 二幕交叉：两斜线 + 一道沿「她 → 你」的直线（米字，10-25 加密：原 X 两道），交点都在你脚下
		for s in [-1.0, 1.0, 0.0]:
			var a: float = dir.angle() + 0.6 * s
			_warn(e, "line", 1.3 if s != 0.0 else 1.6, base.merged({"pos": g.ppos - Vector2.from_angle(a) * 410.0, "ang": a, "track": 0.6, "track_center": true, "no_eye": true,
				"name": "凝视" if s < 0.0 else "", "seq_no": 1 if s < 0.0 else (2 if s > 0.0 else 3), "lock": s < 0.0}))
	elif e.phase == 1:
		ng = 1
		# 一幕：追踪的一道 + 两侧各一道；10-25 用户「三条激光都要瞄准人打」：两侧这两道出手即锁定你当时的位置、从她两侧斜穿过来（原来是平行跑道），1.6 秒后落
		var fan: Array = _aim_fan(e, 3, 820.0)
		for i in [0, 2]:
			_warn(e, "line", 1.6, base.merged({"pos": fan[i].pos, "ang": fan[i].ang, "len": fan[i].len, "track": 0.7, "seq_no": 2, "name": "", "lock": false}))
	for k in ng + int(e.get("gaze_bonus", 0)):
		_warn(e, "line", 1.3 + 0.6 * k, base.merged({"ang": dir.angle(), "track": 0.65 + 0.6 * k, "seq_no": k + 1, "name": "凝视" if k == 0 and ng != 0 else "", "lock": k == 0 and ng != 0}))


## 凝视持续光束的保持段（docs/170）：结算后 hold 秒内光束仍在，队长碰到就按同一道预警结算一次（结算瞬间已中的不再算）。
## 画面是 kp_beam 的 kp_life，判定只到保持段结束、收拢的 0.15 秒不伤人
func _beam_hold(e: Dictionary) -> void:
	var beams: Array = e.get("gaze_beams", [])
	for w in g.warns:
		if w.done and is_same(w.owner, e) and str(w.get("skin", "")) == "gaze" and float(w.get("hold", 0.0)) > 0.0 and not w.has("hold_until"):
			w.hold_until = g.t + float(w.hold) - (w.t - w.dur)
			if not g.tele.hits_leader(w):
				beams.append(w)   # 结算瞬间没中的才进保持段
			_beam_fx(w, "bfx_flash", 16)   # 开火瞬间沿线短闪
			var fxl: Array = e.get("gaze_fx", [])
			fxl.append(w)
			e.gaze_fx = fxl
	# 保持段结束：光束碎成颗粒散开（画面里 kp_beam 同时 0.2 秒变细收拢）
	var fx_live: Array = []
	for w in e.get("gaze_fx", []):
		if g.t >= float(w.hold_until):
			_beam_fx(w, "mote_burst", 30)
		else:
			fx_live.append(w)
	e.gaze_fx = fx_live
	var live: Array = []
	for w in beams:
		if g.t >= float(w.hold_until):
			continue
		if g.tele.hits_leader(w):
			g.tele.warn_damage(w)
			continue
		live.append(w)
	e.gaze_beams = live


func _beam_fx(w: Dictionary, tpl: String, n: int) -> void:
	var gr = BossBeam.grains(g)
	if gr == null:
		return
	var d := Vector2.from_angle(w.ang)
	var k: int = BossBeam.take(g, n)
	for i in k:
		var p: Vector2 = w.pos + Vector2(0, -18) + d * float(w.len) * (i + 0.5) / maxf(1.0, k)
		gr.push(tpl, p, d.orthogonal() * (1.0 if i % 2 == 0 else -1.0), Color(0.92, 0.82, 1.0))


## D · 呼号（二阶段，新；PRTS「大群的祈望堵住了她的喉咙，她发不出声音」→ 张口无声、只喷泡沫）：
## 扇形 r220 半角 0.8 暗填 + 亮边，追踪 0.4 + 锁定 0.9（§1.9 按扇边半宽的一半算）；e.dmg × 1.3，侵蚀 0.5，命中 1.5 秒移速 −30%
func _howl(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "cone", 1.3, {"ang": dir.angle(), "r": 220.0, "half": 0.8, "track": 0.4, "act": "sweep", "name": "呼号", "col": Color(0.85, 0.45, 1.0),
		"dmg": e.dmg * 1.3, "corrode": 0.5, "slow_t": 1.5, "slow_mult": 0.7, "slow_kind": "howl", "howl": true, "skin": "howl"})


## ---- 偏执泡影（docs/38 §8.5）
## 二阶段状态（破茧后 / 图鉴预览共用）：失去悬浮、转近战、弱物理、伤害 ×1.2；常驻淡紫着色（docs/95 §1.2）
func _paranoia_p2(e: Dictionary) -> void:
	if e.phase == 2:
		return
	e.phase = 2
	e.range = 400.0
	e.weak = "物理"
	e.dmg *= 1.2
	e.hover_lost = true
	e.ai = "melee"
	e.spd = 70.0
	_tint2(e, Color(0.92, 0.82, 1.12))


## ---- 主轴「打落」（docs/142b §3.5）
## 一 / 二幕（悬浮）：冲刺穿过真身 → 坠地 4 秒（借破绽：不出招、受伤 × break_mult，taken_mult 再补到合计 1.8）；三幕起（落地）：冲刺穿身 = 光环散掉 5 秒
func _drop_step(e: Dictionary) -> void:
	if e.phase == 1:
		if float(e.get("break_t", 0.0)) > 0.0 or g.t < float(e.get("drop_ok_at", 0.0)) or not _dash_through(e):
			return
		var t: float = Bal.v("boss/paranoia_drop_t", 4.0)
		g.combat.start_break(e, t)
		e.drop_until = g.t + t
		e.drop_ok_at = g.t + t + Bal.v("boss/paranoia_drop_cd", 2.0)
		g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done)
		combos().interrupt(e)   # 打落打断连段
		g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(0.45, 0.95, 1.0), "enemy": true})
		g.vfx.add_text(e.pos + Vector2(0, -70), "坠地", Color(0.45, 0.95, 1.0), 20)
		g.vfx.shake_screen(0.6)
		Sfx.play("shell_break", -6.0, 1.3, 0.0)
	elif not _aura_off(e) and e.get("cocoon_t", 0.0) <= 0.0 and _dash_through(e):
		var t2: float = Bal.v("boss/paranoia_aura_off", 5.0)
		e.aura_off_until = g.t + t2
		e.aura_off_max = t2
		combos().interrupt(e)   # 打散光环打断连段
		g.fx.append({"kind": "ring", "pos": e.pos, "r": float(e.get("burden_r", 300.0)), "life": 0.6, "max": 0.6, "col": Color(0.45, 0.95, 1.0), "enemy": true})
		g.vfx.add_text(e.pos + Vector2(0, -70), "光环散开", Color(0.45, 0.95, 1.0), 18)
		Sfx.play("shell_break", -6.0, 1.1, 0.0)


func _aura_off(e: Dictionary) -> bool:
	return float(e.get("aura_off_until", 0.0)) > g.t


## 二幕「狂望」叠影：2 个幻影（敌人字典，借 bone 的底子（ai static、伤害 0 = 无接触伤害、extra_next INF = 不出额外招），贴图换成泡影一阶段、不画影子 no_shadow、不走画法缓存），
## 绕真身 170 漂（每秒最多 160 像素）；血量不掉（挨打只计次数 hits），挨 paranoia_decoy_hits（3）下散，散后 paranoia_decoy_respawn（6）秒在原位重新分出；
## 冲刺穿过幻影 = 炸开（e.dmg × 0.3 + 减速 1 秒）。离开二幕（落地 / 结茧）全部散掉。自动索敌把它们当 Boss 一起比远近（op_api._focus_bosses 读 boss_decoys）
func _decoy_step(e: Dictionary, dt: float) -> void:
	var on: bool = e.phase == 1 and int(e.get("gates_passed", 0)) == 1 and e.get("cocoon_t", 0.0) <= 0.0
	var slots: Array = e.get("decoys", [])
	if not on:
		if not slots.is_empty():
			for sl in slots:
				if sl.o != null and not sl.o.dead:
					_decoy_pop(e, sl, false)
			e.decoys = []
			g.remove_meta("boss_decoys")
		return
	if slots.is_empty():
		for k in 2:
			slots.append({"k": k, "o": null, "next": g.t + 0.6 * k})
		e.decoys = slots
	var live: Array = []
	for sl in slots:
		if sl.o == null or sl.o.dead:
			sl.o = null
			if g.t >= float(sl.next):
				sl.o = _decoy_make(e, int(sl.k))
		var o = sl.o
		if o == null:
			continue
		var want: Vector2 = g.combat.arena_clamp(e.pos + Vector2.from_angle(g.t * 0.4 + TAU * (int(sl.k) + 1) / 3.0) * 170.0, 60.0)
		o.pos = o.pos.move_toward(want, 160.0 * dt)
		o.kb = Vector2.ZERO
		o.hp = o.maxhp
		# 幻影：整体更透、偏冷，透明度轻微闪动（纯画面字段，只读 g.t）；真身不变
		o["tint2"] = Color(0.78, 0.9, 1.25, 0.5 + 0.12 * sin(g.t * 7.0 + float(sl.k) * 2.1))
		o.phase = 1
		if int(o.hits) >= int(Bal.v("boss/paranoia_decoy_hits", 3.0)):
			_decoy_pop(e, sl, false)
		elif _dash_through(o):
			_decoy_pop(e, sl, true)
		else:
			live.append(o)
	g.set_meta("boss_decoys", live)


func _decoy_make(e: Dictionary, k: int) -> Dictionary:
	var o: Dictionary = g.spawner.spawn_enemy("bone", e.pos)
	o.name = e.name
	o.tex = e.tex
	o.tex_move = false
	o.tex_attack = false
	o.tex_charge = false
	o.tex_feign = false
	o.tex_death = false
	o.r = e.r
	o.r0 = e.r
	o.xp = 0.0
	o.dmg = 0.0
	o.spd = 0.0
	o.ai = "static"
	o.extra_next = INF
	o.affix = ""
	o.shield_hp = 0.0
	o.maxhp = 1.0e9
	o.hp = o.maxhp
	o.decoy_of = e
	o.no_shadow = true
	o["dcs"] = true   # 不走画法缓存（world._dc_ok）
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 1.6, "life": 0.4, "max": 0.4, "col": COL, "enemy": true})
	return o


func _decoy_pop(e: Dictionary, sl: Dictionary, dashed: bool) -> void:
	var o: Dictionary = sl.o
	o.dead = true
	sl.o = null
	sl.next = g.t + Bal.v("boss/paranoia_decoy_respawn", 6.0)
	g.fx.append({"kind": "ring", "pos": o.pos, "r": o.r * 2.0, "life": 0.45, "max": 0.45, "col": COL, "enemy": true})
	g.vfx.sparks(o.pos, Vector2.UP, COL, 14, 160.0)
	if dashed:
		g.combat.enemy_hit(e.dmg * 0.3, {"boss": true, "src_type": e.type}, false, true, ["法术"], "boss_" + e.type)
		g.combat.slow_leader("paranoia_decoy", 1.0, 0.7)
		g.vfx.add_text(o.pos + Vector2(0, -50), "幻影", Color(0.85, 0.7, 1.0), 16)
		Sfx.play("shell_break", -8.0, 1.6, 0.0)


## 主轴受伤倍率（combat.damage，乘在破绽倍率之前）：茧期 1；悬浮 0.5 / 坠地合计 1.8；落地光环张开 0.5、散开 1
func taken_mult(e: Dictionary) -> float:
	if e.get("cocoon_t", 0.0) > 0.0:
		return 1.0
	if e.phase == 1:
		if float(e.get("break_t", 0.0)) > 0.0:
			return Bal.v("boss/paranoia_drop_taken", 1.8) / maxf(0.01, Bal.v("boss/break_mult", 1.4))
		return Bal.v("boss/paranoia_hover_taken", 0.5)
	return 1.0 if _aura_off(e) else Bal.v("boss/paranoia_aura_taken", 0.5)


## 认知负担光环：主控站在 boss/paranoia_aura_r（220；二阶段 paranoia_aura_r2 300）内时，全队攻速 ×(1 − paranoia_aura_aspd)（一阶段 0.10、二阶段 paranoia_aura_aspd2 0.15；
## 合计攻速削减上限 −15%，§1.11；stats 来源 "paranoia_aura"）
func _paranoia_aura(e: Dictionary, dist: float) -> void:
	var p2: bool = e.phase == 2
	e.burden_r = Bal.v("boss/paranoia_aura_r2", 300.0) if p2 else Bal.v("boss/paranoia_aura_r", 220.0)   # 画面读这个半径画地面符文圈
	if p2 and _aura_off(e):
		e.burden_r = 0.0   # 三幕冲刺打散：光环散开期间不画、不减攻速（docs/142b §3.5）
	var inside: bool = dist < e.burden_r
	var want_k: int = (2 if p2 else 1) if inside else 0
	if want_k != int(e.get("burden_k", 0)):
		e.burden_k = want_k
		e.burden_in = inside
		g.stats.remove_source("paranoia_aura")
		if inside:
			g.stats.add(&"op_aspd", "mult", 1.0 - minf(0.15, Bal.v("boss/paranoia_aura_aspd2", 0.15) if p2 else Bal.v("boss/paranoia_aura_aspd", 0.10)), "paranoia_aura")
		g.sync_stats()


## 第一次血量归零：结成泡影茧 boss/paranoia_cocoon 秒。本体无敌，外壳是部件（shell_hp = 最大生命 × paranoia_shell），会吐慢速弹；
## 场地收到 paranoia_arena2。打破外壳 → 复活到 paranoia_revive（40%）并进入 5 秒大破绽；没打破 → 同样复活，但凝视永久 +1 道
func paranoia_cocoon(e: Dictionary) -> void:
	Sfx.play_cue("phase", e.type, "start")
	e.cocoon_done = true
	e.cocoon_t = Bal.v("boss/paranoia_cocoon", 8.0)
	Sfx.play("cocoon_form", -7.3, 1.0, 0.0)   # 结茧（tools/gen_sfx_boss_events.py），垫在阶段音下面
	e.hp = 1.0
	e.invuln = true
	e.part = true
	g.enemies_sys.part_add(e)   # 部件登记（docs/101 S7：击杀吸取不再扫全表）
	e.shell_max = e.maxhp * Bal.v("boss/paranoia_shell", 0.08)
	e.shell_hp = e.shell_max
	e.shell_room = 0.0
	e.count_end = g.t + e.cocoon_t
	e.count_max = e.cocoon_t
	e.shell_shot = 0.0
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	combos().reset(e)
	g.stats.remove_source("paranoia_aura")
	e.burden_in = false
	e.burden_k = 0
	g.sync_stats()
	if g.zone_frozen:
		g.combat.freeze_zone(Bal.v("boss/paranoia_arena2", 520.0))
	g.vfx.show_banner("\"偏执泡影\" 结茧 —— 打破外壳", 3)
	Sfx.play("roar", -2.0, 1.1, 0.0)


func _paranoia_cocoon_step(e: Dictionary, dt: float) -> void:
	e.cocoon_t -= dt
	# 外壳受伤额度按秒补充（combat.damage 里截），最多攒 0.5 秒的量
	var rate: float = e.shell_max / maxf(0.5, Bal.v("boss/paranoia_shell_min", 4.0))
	e.shell_room = minf(e.get("shell_room", 0.0) + rate * dt, rate * 0.5)
	e.shell_shot -= dt
	if e.shell_shot <= 0.0:
		e.shell_shot = 2.0
		for k in 11:   # 10-25 加密：原 8 发、e.dmg × 0.4
			g.ebullets.append({"pos": e.pos, "vel": Vector2.from_angle(TAU * k / 11.0 + g.t) * 120.0, "dmg": e.dmg * 0.31, "slow": false, "r": 7.0,
				"life": 3.0, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "nova", "home": false, "boss": true, "src_type": e.type})
	if e.cocoon_t <= 0.0:
		paranoia_hatch(e, false)


func paranoia_hatch(e: Dictionary, broken: bool) -> void:
	e.cocoon_t = 0.0
	e.shell_hp = 0.0
	e.part = false
	e.invuln = false
	e.count_end = 0.0
	e.hp = e.maxhp * Bal.v("boss/paranoia_revive", 0.8)
	_paranoia_p2(e)
	e.vis_act = "revive"   # 二阶段破茧：e_paranoia_phase2_revive（纯画面）
	e.vis_t0 = g.t
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 3.0, "life": 0.6, "max": 0.6, "col": Color(0.85, 0.45, 1.0), "enemy": true})
	if broken:
		g.combat.start_break(e, Bal.v("boss/paranoia_hatch_break", 5.0))
		g.vfx.add_text(e.pos + Vector2(0, -70), "破茧！", Color(1.0, 0.85, 0.4), 22)
	else:
		e.gaze_bonus = int(e.get("gaze_bonus", 0)) + 1
		g.vfx.add_text(e.pos + Vector2(0, -70), "蜕变 —— 凝视 +1", Color(0.9, 0.4, 1.0), 20)
	Sfx.play("shell_break" if broken else "cocoon_revive", 2.0 if broken else -5.2, 1.0, 0.0)   # 破茧 / 超时蜕变


## ---- 受击钩子（docs/101 B1c，10-15 从 combat.gd 搬来）
## 茧：本体无敌，伤害打在外壳上（docs/38 §8.5）。外壳受伤有速度上限（协调人 9/29：外壳要成为真分支）：每秒最多掉 shell_max / boss/paranoia_shell_min 秒，
## 再强的编队也要约 4 秒才能打破（换 5 秒破绽），输出低的可能 8 秒内打不破（凝视永久 +1）
func absorb_damage(e: Dictionary, dmg: float) -> bool:
	if not (e.get("cocoon_t", 0.0) > 0.0 and e.get("shell_hp", 0.0) > 0.0):
		return false
	var room: float = e.get("shell_room", 0.0)
	dmg = minf(dmg, room)
	e.shell_room = room - dmg
	e.shell_hp -= dmg
	if dmg > 0.0:
		g.vfx.boss_hit_flash(e, g.t)   # 壳面白闪与本体共用限频（docs/137）；零壳伤不闪
	if e.shell_hp <= 0.0:
		paranoia_hatch(e, true)
	return true


## 第一次归零结茧（docs/38 §8.5，取代原来「被控 0.3 秒进二阶段」）
func on_lethal(e: Dictionary) -> bool:
	if not e.get("cocoon_done", false):
		paranoia_cocoon(e)
		return true
	return super.on_lethal(e)


## 认知负担光环、幻影随本体撤掉
func on_kill(e: Dictionary) -> void:
	combos().reset(e)
	for sl in e.get("decoys", []):
		if sl.o != null and not sl.o.dead:
			sl.o.dead = true
	g.remove_meta("boss_decoys")
	g.stats.remove_source("paranoia_aura")
	g.sync_stats()


## 过最后一道卡点就落地进二阶段（近战、移速 70、凝视 3 道），茧仍在归零时结；原来一阶段悬浮远程一直拖到归零，
## 最后一幕 = 33% + 茧 8 秒 + 复活 40% 全在够不着的状态下打（数值 close5 am40：泡影 12 局超时全卡在最后一幕）。boss/paranoia_p2_at_gate 0 = 旧行为
func on_gate(e: Dictionary) -> void:
	if e.gates.is_empty() and e.phase == 1 and Bal.v("boss/paranoia_p2_at_gate", 1.0) > 0.0:
		_paranoia_p2(e)
		g.vfx.add_text(e.pos + Vector2(0, -70), "坠落", Color(0.9, 0.4, 1.0), 20)
