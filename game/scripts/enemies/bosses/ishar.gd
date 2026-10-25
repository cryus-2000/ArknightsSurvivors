## 伊莎玛拉（type ishar，docs/38 §2.5 / §8.6；变身后招式改版 docs/95 §2，10-14）；一阶段由 run/ishar_encounter.gd 负责
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 变身后 4 招固定轮转：A 三点落击（①）→ B 三线扫射（②，逐条锁定）→ C 大群之歌（④ 双缺口扩散环，真伤）→ D 撕咬 / 横扫（③；66% 卡点后「濒死强化」2 段）
## 人形 / 抗争之泪 / 压制 / 变身 / 泪滴共鸣 / 潮涌迫近是机制，不动（用户 10-14 定）
extends "res://scripts/enemies/bosses/boss_base.gd"

const COL := Color(0.3, 1.0, 0.65)   # 青绿（docs/142b §8.4）
const MOVES := ["三点落击", "三线扫射", "大群之歌", "撕咬"]


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(e: Dictionary, _dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	# P1 治疗海嗣和充能由 IsharEncounter 负责；这里仅调度敌对海嗣形态。
	if e.phase == 2 and _enraged(e) and not e.has("tint2"):
		_tint2(e, Color(1.18, 0.86, 0.9))   # 濒死强化：本体加红色着色（docs/95 §2.2 D）
	if e.phase == 2 and ready and g.t >= float(e.get("transform_until", 0.0)):
		_ishar_phase2(e, dir, dist)



## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	transform_ishar(e)


func demo_moves(_e: Dictionary) -> Array:
	return MOVES


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if e.phase != 2:
		return false
	var i: int = MOVES.find(name)
	if i < 0:
		return false
	e.tear_echoes = []
	e.ishar_cycle = i
	e.ishar_next_at = g.t
	e.cds = {"ishar_close": g.t + 100.0}   # 验收只看轮转招，不让迫近插队
	_ishar_phase2(e, dir, minf(dist, 180.0) if name == "撕咬" else dist)
	return true


## 以原作「三目标真实伤害」为基础的幸存者玩法改编。固定轮转避免近身招式永久压住远程招式。
func _ishar_phase2(e: Dictionary, dir: Vector2, dist: float) -> void:
	var d: Dictionary = D.ENEMIES.ishar.get("attack", {})
	# 潮涌迫近（协调人 9/30 定，见 _close_in）：原来她站在 660 射程边上、躲在杂兵墙后，近战队伍打不到（Boss A/B 9/30：高手用时中位 199 秒、15/50 没打死）
	if g.t >= float(e.get("ishar_next_at", 0.0)):
		var cdur := _close_in(e, dir, dist, "ishar", "潮涌迫近", COL)
		if cdur >= 0.0:
			e.ishar_next_at = g.t + cdur + 0.6
			return
	if dist > float(d.get("range", 660.0)) or g.t < float(e.get("ishar_next_at", 0.0)):
		return
	var move: int = int(e.get("ishar_cycle", 0)) % 4
	var end := 0.0
	var echoes: Array = e.get("tear_echoes", [])
	if not echoes.is_empty():
		# 只保存变身前未压制的泪滴；锁定一刻的主控位置，各束同时结算。
		var target: Vector2 = g.combat.arena_clamp(g.ppos, 80.0)
		for source in echoes:
			var to_target: Vector2 = target - source
			var w := _warn(e, "line", 1.0, {"pos": source, "ang": to_target.angle(), "len": to_target.length(),
				"wid": 13.0, "act": "ishar_echo", "true": true, "name": "泪滴共鸣" if source == echoes[0] else "",
				"col": COL, "dmg": e.dmg * Bal.v("boss/ishar_echo_mult", 0.6), "cancel_dead": true, "lock": source == echoes[0]})
			end = maxf(end, w.dur)
		e.tear_echoes = []
		e.wind = maxf(e.wind, end)
		e.cdt = maxf(e.cdt, end)
		e.ishar_next_at = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE * _ishar_haste(e)
		return
	e.ishar_cycle = (move + 1) % 4
	var enraged: bool = _enraged(e)
	match move:
		0:
			# A · 三点落击：主控脚底与两侧 106 处三圈 r56 实填，同时锁定 0.9 秒；e.dmg × 0.65 真伤 / 圈
			var side := dir.orthogonal()
			var offsets := [0.0, -1.0, 1.0]
			for k in 3:
				var pos: Vector2 = g.combat.arena_clamp(g.ppos + side * offsets[k] * float(d.get("mark_spacing", 106.0)), 90.0)
				var w := _warn(e, "circle", float(d.get("mark_warn", 0.9)),
					{"pos": pos, "r": float(d.get("mark_radius", 56.0)), "act": "ishar_strike", "true": true,
					"name": "三点落击" if k == 0 else "", "col": COL, "dmg": e.dmg * float(d.get("mark_mult", 0.65)),
					"cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		1:
			# B · 三线扫射：三条 660 × 14 条纹线，夹角 0.38；逐条锁定（第 1 条 0.3 秒、之后各晚 0.15 秒），同时结算；每条锁定 ≥0.4；e.dmg × 0.7 真伤 / 线
			for k in 3:
				var w := _warn(e, "line", float(d.get("line_warn", 1.0)),
					{"ang": dir.angle() + (k - 1) * float(d.get("line_spread", 0.38)),
					"len": float(d.get("range", 660.0)), "wid": float(d.get("line_width", 14.0)), "track": 0.3 + 0.15 * k, "seq_no": k + 1,
					"act": "ishar_line", "true": true, "name": "三线扫射" if k == 0 else "", "col": COL,
					"dmg": e.dmg * float(d.get("line_mult", 0.7)), "cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
		2:
			# C · 大群之歌（PRTS「她不再歌唱，它为大群发声」，招式名本作拟）：以本体为心 r90 起扩散的声波环（≤220px/s，到 r600 止），
			# 2 个缺口（朝主控 + 对侧），缺口在主控所在距离上弧长 ≥110px（濒死强化后缩到 80px 下限）、灯火 ≥70 加宽 1.5 倍；
			# 缺口提前 0.8 秒画出；环为真实伤害判定、命中一次；e.dmg × 0.9
			var arc: float = Bal.v("boss/ishar_song_gap_px", 110.0) if not enraged else 80.0
			if g.lamp >= 70.0:
				arc *= 1.5
			var gh: float = clampf(arc * 0.5 / maxf(dist, 90.0), 0.12, 1.0)
			var w := _warn(e, "circle", 0.8, {"r": 90.0, "act": "song_ring", "gaps": [dir.angle(), dir.angle() + PI], "gap_half": gh,
				"maxr": 600.0, "spd": Bal.v("boss/ishar_song_spd", 220.0), "true": true, "name": "大群之歌", "col": COL,
				"dmg": e.dmg * Bal.v("boss/ishar_song_mult", 0.9), "cancel_dead": true})
			end = w.dur
		3:
			# D · 撕咬（近，半角 0.85、r190）/ 横扫（远，半角 0.46、r 到主控 +40 ≤660）：暗填扇形，追踪 0.3；e.dmg × 0.9 真伤。
			# 濒死强化（66% 卡点后）：2 段（第 2 段 0.6 秒后、方向镜像），每段 ×1.125
			var near: bool = dist < float(d.get("bite_range", 190.0))
			var segs: int = 2 if enraged else 1
			var mult: float = float(d.get("maw_mult", 0.9)) * (1.125 if enraged else 1.0)
			var mw: float = float(d.get("bite_warn", 1.1)) if near else float(d.get("maw_warn", 0.85))   # 撕咬扇边半宽的一半 72 → 锁定 ≥0.78，总 1.1；横扫 ≥0.55，总 0.85
			for k in segs:
				var w := _warn(e, "cone", mw + 0.6 * k,
					{"ang": dir.angle(), "half": 0.85 if near else 0.46,
					"r": float(d.get("bite_range", 190.0)) if near else minf(dist + 40.0, float(d.get("range", 660.0))),
					"track": 0.3 + 0.6 * k, "act": "bite" if near else "sweep", "true": true, "mirror": k == 1,
					"name": ("撕咬" if near else "横扫") if k == 0 else "", "col": COL,
					"dmg": e.dmg * mult, "cancel_dead": true, "lock": k == 0})
				end = maxf(end, w.dur)
	# 完整连段期间停留且不插入普通射击；按经过难度修正后的真实预警长度计时。
	e.wind = maxf(e.wind, end)
	e.cdt = maxf(e.cdt, end)
	e["ishar_next_at"] = g.t + end + float(d.get("recovery", 1.25)) * SKILL_COOLDOWN_SCALE * _ishar_haste(e)


## 濒死强化（docs/95 §2.2 D）：过第一道卡点（66%）之后
func _enraged(e: Dictionary) -> bool:
	return int(e.get("gates_passed", 0)) >= 1


## 真实形态切换由逻辑记录起始时间，渲染和演练均使用同一个入口。
func transform_ishar(e: Dictionary) -> void:
	if e.phase == 2:
		return
	Sfx.play_cue("phase", e.type, "start")
	e.phase = 2
	e.friendly = false
	e.invuln = false   # 0.9 秒变身免伤由 combat 的 transform_until 护栏控制，不留永久无敌。
	e.ai = "melee"   # 接近主控，但伤害只从有预警的轮转招式结算。
	e["ishar_cycle"] = 0
	e["ishar_next_at"] = g.t + 0.9
	e["tear_echoes"] = []
	for o in g.enemies:
		if o.type == "tear" and is_same(o.get("owner", {}), e):
			if not o.dead and not g.ishar.tear_blocked(o):
				e.tear_echoes.append(o.pos)
				g.fx.append({"kind": "ring", "pos": o.pos, "r": 34.0, "life": 1.4, "max": 1.4,
					"col": COL, "enemy": true})
				g.fx.append({"kind": "tide_link", "a": o.pos, "b": e.pos, "life": 1.0, "max": 1.0,
					"col": COL, "enemy": true})
			o.dead = true
	e.dmg *= 1.6
	e.spd = maxf(e.spd, 58.0)
	e.r = 46.0
	e.r0 = 46.0
	e["transform_started"] = g.t
	e["transform_until"] = g.t + 0.9
	e.wind = maxf(e.wind, 0.9)
	e.pose = 0.0
	e.cdt = maxf(e.cdt, 0.9)
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	g.vfx.show_banner("伊莎玛拉 完成了转化！")
	Sfx.play("roar", 2.0, 0.6, 0.0)
	g.vfx.shake_screen(1.2)


## 伊莎玛拉强度上调（docs/38 §8.6）：过了卡点后轮换恢复时间 ×boss/ishar_gate_haste（0.8）
func _ishar_haste(e: Dictionary) -> float:
	return Bal.v("boss/ishar_gate_haste", 0.8) if int(e.get("gates_passed", 0)) >= 1 else 1.0


## ---- 受击钩子（docs/101 B1c，10-15 从 combat.gd 搬来）
## 变身动画保护（transform_until，0.9 秒）：独立计时，结束后无需清理永久无敌标记
func block_damage(e: Dictionary) -> bool:
	return g.t < float(e.get("transform_until", 0.0))
