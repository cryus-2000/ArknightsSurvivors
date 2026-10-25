extends RefCounted
## 只扩展 BossAI 的空闲窗口；预警和受击复用原有管线。
## 数据招式（enemies.json 各 Boss 的 patterns，docs/95 §12 字段约定，10-14）：
##   mode      fan / ring / rain / line / cleave / stack；stack = 序列落点圈，每圈位置 = 锁定时刻主控位置（叠影）
##   waves     波数 / 圈数；waves_p2：最终 Boss 二阶段（enhanced）改用的圈数（叠影 3 → 5）
##   mult      单发伤害倍率（缺省：最终 Boss 0.65、其余 0.8；cleave 固定 1.1）；corrode：附带侵蚀
##   radius    rain / stack / cleave 的半径；rain 加 arc: true = 落点排成朝主控方向的弧（圆心 = 主控，半径 arc_r 缺省 108，相邻圈夹角 arc_step 缺省 0.5）
##   gap       ring 的缺口半角；gaps：缺口数（等分，缺省 1）
##   cd / cd_p2  这招放完到下一招的间隔（缺省：最终 Boss 5 秒、其余 6.5 秒）；p2_every：二阶段每几轮才放一次（泡影环 2）
##   phase_min 过了几道卡点（gates_passed）才进轮转（订正、接潮扇浪）
##   no_ammo   带弹药的 Boss 也不耗弹、近战段也放（散射）；ammo_cost：耗弹数（缺省 1）；on_reload：不进轮转，只由 e.pattern_force 点名（清膛）
##   e.pattern_force = 招式名：下一次 try_attack 无视轮转和 pattern_next 直接放它（回流→订正、装填完毕→清膛、验收 --bossmoves）
## 第 2 批加的字段（docs/95 §5–§7，都可选，缺省 = 原行为）：
##   manual    不进轮转，只由 Boss 脚本经 pattern_force 点名（订正：二阶段由 path.gd 按 correct 冷却点名，第一次先亮招式名）
##   min_dist / max_dist  主控距离在这个范围内才进轮转（散射 <220、环射 120–320）
##   dur / track  预警总时长 / 追踪段（覆盖缺省 0.9 + 0.6 × 波序）；warn_r：fan 扇形预警半径（缺省 140）
##   ring_r    ring 预警与出弹的起始半径（缺省 88）；gap_face：缺口之一朝主控（缺省缺口在主控方向的侧面）
##   gap_jitter  ring 每波缺口的左右错开（缺省 0.12；交错潮环 0 = 两波缺口同向，docs/95 §8.2 B）
##   cone_dmg  fan 结算时扇形本身再判定一次，伤害 = e.dmg × cone_dmg（接潮扇浪 0.9）
##   bullet    非刃弹的弹体种类（缺省 nova；圣徒的散射 / 清膛 / 环射用 orb = 普通实弹，不画成紫色新星弹）
##   life      弹体寿命秒（缺省 2.8）；fx：结算时在出弹点放的特效帧条名（缺图不放）；fx_col：给 fx 乘色（卡门借伊比利亚的清膛环换金色）
const D = preload("res://scripts/data.gd")
const Game = preload("res://scripts/game.gd")
const FINAL_TYPES := ["paranoia", "knight_boss", "ishar", "izumik"]
const OWNER_CAP := 160   # 10-25 弹幕加密（×1.4 + 多一圈）后放宽：原 120 / 240，解读旋涡 3 圈 × 50 会被截
const TOTAL_CAP := 320
var g: Game
func _init(game: Game) -> void:
	g = game


## 这条招式现在能不能进轮转（卡点门槛、装填专用、近身劈需要距离）
func allowed(e: Dictionary, move: Dictionary, dist: float) -> bool:
	if int(e.get("gates_passed", 0)) < int(move.get("phase_min", 0)):
		return false
	if move.get("on_reload", false) or move.get("manual", false):
		return false
	if dist < float(move.get("min_dist", 0.0)) or dist > float(move.get("max_dist", INF)):
		return false
	if move.mode == "cleave" and dist > float(move.radius) + 20.0:
		return false
	if e.has("ammo") and not move.get("no_ammo", false) and (e.ammo < int(move.get("ammo_cost", 1)) or e.channel > 0.0):
		return false
	return true


func try_attack(e: Dictionary, dir: Vector2, dist: float) -> bool:
	if e.dead or e.get("friendly", false) or e.get("coma", false) or e.get("invuln", false):
		return false
	if e.type in ["ishar", "izumik"] and e.phase != 2:
		return false
	if e.get("dash2", false) or e.get("combo_n", 0) > 0 or e.has("leap"):
		return false
	var moves: Array = D.ENEMIES[e.type].get("patterns", [])
	if moves.is_empty() or dist > 760.0:
		return false
	var forced: String = str(e.get("pattern_force", ""))
	var index: int = -1
	if forced != "":
		e.erase("pattern_force")
		for i in moves.size():
			if str(moves[i].name) == forced:
				index = i
		if index < 0:
			return false
	else:
		if not e.has("pattern_next"):
			e.pattern_next = g.t + 3.0
			return false
		if g.t < e.pattern_next:
			return false
		index = int(e.get("pattern_cycle", 0)) % moves.size()
		var tries := 0
		while not allowed(e, moves[index], dist) and tries < moves.size():
			index = (index + 1) % moves.size()
			tries += 1
		if tries >= moves.size():
			return false
	var move: Dictionary = moves[index]
	var enhanced: bool = FINAL_TYPES.has(e.type) and e.phase == 2
	if forced == "" and enhanced and int(move.get("p2_every", 1)) > 1:
		# 二阶段每 p2_every 轮才放一次（泡影环）：没轮到就跳过这一条、轮转照走
		var ps: Dictionary = e.get("pattern_skip", {})
		ps[move.name] = int(ps.get(move.name, 0)) + 1
		e.pattern_skip = ps
		if int(ps[move.name]) % int(move.get("p2_every", 1)) != 0:
			e.pattern_cycle = (index + 1) % moves.size()
			e.pattern_next = g.t + 0.3
			return false
	var waves: int = int(move.get("waves_p2", move.waves)) if enhanced else int(move.waves)
	if e.has("ammo") and not move.get("no_ammo", false):
		waves = mini(waves, int(e.ammo))
	var end := 0.0
	var base_mult: float = float(move.get("mult", 0.65 if FINAL_TYPES.has(e.type) else 0.8))
	for k in waves:
		var angle: float = dir.angle() + (0.10 if k % 2 else -0.10)
		var data := {"pattern_id": str(e.type) + ":" + str(index), "pattern": move,
			"wave": k, "enhanced": enhanced, "ang": angle, "cancel_dead": true,
			"name": move.name if k == 0 else "", "col": g.vfx.boss_color(e.type),
			"dmg": e.dmg * base_mult, "corrode": float(move.get("corrode", 0.0)),
			"true": e.type == "ishar", "track": 0.0, "lock": k == 0}
		var shape := "cone"
		var dur: float = float(move.get("dur", 0.9)) + 0.6 * k
		match str(move.mode):
			"fan":
				data.act = "pattern_fan"
				data.half = float(move.spread) * 0.5
				data.r = float(move.get("warn_r", 140.0))
			"ring":
				shape = "circle"
				data.act = "pattern_ring"
				data.r = float(move.get("ring_r", 88.0))
				var gj: float = float(move.get("gap_jitter", 0.12))
				# gap_face 多波时缺口左右错开 gap_stagger（泡影环落地 2 波，docs/142b §8.2：冲进去要连穿两道缺口）
				var gst: float = float(move.get("gap_stagger", 0.0)) * (1.0 if k % 2 else -1.0) if waves > 1 else 0.0
				data.gap_ang = dir.angle() + (gst if move.get("gap_face", false) else PI * 0.5 + (gj if k % 2 else -gj))
				data.gap_half = float(move.gap)
				var ng: int = int(move.get("gaps", 1))
				if ng > 1:
					var gs: Array = []
					for q in ng:
						gs.append(float(data.gap_ang) + TAU * q / ng)
					data.gaps = gs
			"rain":
				shape = "circle"
				data.act = "pattern_rain"
				data.r = float(move.radius)
				if move.get("arc", false):
					# 朝主控方向的弧（docs/95 §3.2 A）：圆心 = 主控，落点在半径 arc_r 的弧上、弧朝向本体，留出「背向 Boss 走」的生路
					var to_boss: float = (e.pos - g.ppos).angle()
					data.pos = g.combat.arena_clamp(g.ppos + Vector2.from_angle(to_boss + (k - (waves - 1) * 0.5) * float(move.get("arc_step", 0.5))) * float(move.get("arc_r", 108.0)), 90.0)
				else:
					data.pos = g.combat.arena_clamp(g.ppos + dir.orthogonal() * (ceili(k / 2.0) * (1 if k % 2 else -1)) * 108.0, 90.0)
				dur = 0.9
			"line":
				shape = "line"
				data.act = "pattern_line"
				data.len = float(move.length)
				data.wid = float(move.width)
				data.track = 0.35
				data.ang = dir.angle() + (0.16 * (2 * k - (waves - 1)) if waves > 1 else 0.0)
				dur = 0.9
			"cleave":
				data.act = "pattern_cleave"
				data.r = float(move.radius)
				data.half = float(move.half)
				data.ang = dir.angle() + (-0.42 if k == 0 else 0.42)
				data.dmg = e.dmg * 1.1
			"stack":
				# 叠影（docs/95 §1.2 C）：第 1 圈追踪 track 秒后锁定，之后每圈在前一圈锁定后 0.6 秒再以主控当时位置锁定；
				# 每圈锁定 ≥ lock 秒（r45 按 §1.9 ≥0.64）；结算走 burst
				shape = "circle"
				data.act = "burst"
				data.r = float(move.get("radius", 45.0))
				data.track_pos = "leader"
				data.track = float(move.get("track", 0.5)) + 0.6 * k
				data.seq_no = k + 1
				data.pos = g.ppos
				dur = data.track + float(move.get("lock", 0.65))
		if move.has("track"):
			data.track = float(move.track)
		var w: Dictionary = g.tele.warn(e, shape, dur, data)
		end = maxf(end, w.dur)
	e.pattern_cycle = (index + 1) % moves.size()
	var cd_key: String = "cd_p2" if (enhanced and move.has("cd_p2")) else "cd"
	e.pattern_next = g.t + end + float(move.get(cd_key, 5.0 if FINAL_TYPES.has(e.type) else 6.5))
	e.wind = maxf(e.wind, end + 1.0)
	e.cdt = maxf(e.cdt, end + 1.0)
	return true

func resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	if e.dead or e.get("coma", false) or e.get("friendly", false) or e.stun > 0.0 or e.get("break_t", 0.0) > 0.0 or e.get("channel", 0.0) > 0.0:
		return
	var move: Dictionary = w.pattern
	if w.act in ["pattern_cleave", "pattern_rain", "pattern_line"]:
		g.tele.warn_damage(w)
		g.vfx.boss_pattern(w)
		return
	if e.has("ammo") and not move.get("no_ammo", false):
		var cost: int = int(move.get("ammo_cost", 1))
		if e.ammo < cost:
			return
		e.ammo -= cost
		if e.ammo <= 0:
			e.ai = "melee"
	if w.act == "pattern_fan" and float(move.get("cone_dmg", 0.0)) > 0.0:
		var cw: Dictionary = w.duplicate()
		cw.dmg = e.dmg * float(move.cone_dmg)
		g.tele.warn_damage(cw)   # 扇形本身一次（接潮扇浪的浪头），弹幕另算
	var count: int = int(move.count) + (4 if w.enhanced and not move.get("blade", false) else 0)
	var own := 0
	var total := 0
	for b in g.ebullets:
		if b.life > 0.0:
			total += 1
			if b.get("source_id", -1) == e.id:
				own += 1
	for i in count:
		if own >= OWNER_CAP or total >= TOTAL_CAP:
			break
		var angle: float
		if w.act == "pattern_ring":
			angle = w.ang + TAU * float(i) / count + float(w.wave) * PI / count
			if g.tele.in_gap(w, angle):
				continue
		else:
			angle = w.ang + lerpf(-float(move.spread) * 0.5, float(move.spread) * 0.5, float(i) / maxf(count - 1, 1))
		var blade: bool = move.get("blade", false)
		g.ebullets.append({"pos": w.pos, "vel": Vector2.from_angle(angle) * float(move.speed),
			"dmg": w.dmg, "r": 12.0 if blade else 7.0, "life": float(move.get("life", 2.8)),
			"slow": false, "frost": e.get("frost", 0.0), "corrode": 0.15, "nerve": 0.0, "true": w.get("true", false),
			"kind": "boss_blade" if blade else str(move.get("bullet", "nova")), "home": false, "boss": true,
			"atk": "物理" if e.has("ammo") or blade else "法术", "hit_cap": e.get("hit_cap", 0.0),
			"source_id": e.id, "col": w.col, "src_type": e.type})
		own += 1
		total += 1
	if move.has("fx"):
		# 出招特效帧条（散射炮口火舌 fx_saint_scatter、清膛 / 环射出环 fx_saint_clear_ring、订正出环 fx_path_correct_ring）：缺图只走 boss_pattern 的程序画面
		var col: Color = Color(move.fx_col[0], move.fx_col[1], move.fx_col[2]) if move.has("fx_col") else Color.WHITE
		var at: Vector2 = w.pos + (Vector2.from_angle(w.ang) * 36.0 if w.act == "pattern_fan" else Vector2.ZERO)
		if g.vfx.fx_sprite(str(move.fx), at, g.PX * float(move.get("fx_scale", 1.4)), w.ang if w.act == "pattern_fan" else 0.0, false, false, col, w.act == "pattern_ring"):
			g.fx[g.fx.size() - 1]["enemy"] = true
	g.vfx.boss_pattern(w)
