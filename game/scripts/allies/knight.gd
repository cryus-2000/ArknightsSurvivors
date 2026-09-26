## 猎潮的骑士（结局二同伴，docs/18 §2）：不占援护位；跟在水月侧后方，每 4 秒对 320 内目标冲锋→刺击；
## 有生命（固定 600，不随时间涨），会被接触与弹幕伤害，50% 的近战敌人把他当目标；血量 <30% 退到水月身后 3 秒（2026-09-27 协调人定）。
## 阵亡 → 退行的罗辛南特 (223)，结局回退；10:00 若结局为骑士，走入黑潮中心重生为 Boss（由 game.gd 调 walk_to_center / take_over）。
extends RefCounted

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")

const R := 17.0            # 2026-09-27 画面缩到 0.7 后判定跟着缩一点（22 → 17，Boss与怪物建议 0.75–0.8）；冲锋命中半径按 R 算，同比变小
const SPEED := 240.0
const FOLLOW_SPD := 6.0
const CHARGE_RANGE := 320.0
const CHARGE_CD := 4.0
const CHARGE_WIND := 0.3
const CHARGE_T := 0.42
const CHARGE_SPD := 760.0
const STAB_T := 0.4
const STAB_HIT_T := 0.2      # 第 3 帧（零基 2）命中
const FROST_T := 1.2
## 画面缩放（2026-09-27 用户反馈：骑士帧 96×80 按 2 倍画约 192×160，是主控的两倍，挡视线）：画到 0.7 倍
const DRAW_K := 0.7
const ICE := Color(0.7, 0.9, 1.4)
var trail: Array = []          # 冲锋残影：[pos, frame, life]

var g
var alive := false
var pos := Vector2.ZERO
var hp := 600.0
var maxhp := 600.0
var face := 1.0
var state := "idle"           # idle / wind / charge / stab / retreat / walk
var cd := 2.0
var st := 0.0                 # 当前状态计时
var retreat_t := 0.0
var dash_dir := Vector2.RIGHT
var dash_hit: Dictionary = {}  # 冲锋中已命中的敌人 id
var hit_cd: Dictionary = {}    # 敌人 id -> 下次可造成接触伤害的时间
var flash := 0.0
var mv := 0.0
var mt := 0.0
var walk_to := Vector2.INF     # 终局：走向黑潮中心
var arrived := false
var fallen := false            # 道中阵亡过（退行）
var low_armed := true          # 低血撤退每个"低血阶段"只触发一次，回到 45% 以上再重新武装


func _init(game) -> void:
	g = game


## 获得「海潮的气息」：骑士从画面外奔来
func spawn() -> void:
	alive = true
	fallen = false
	maxhp = 600.0   # 2026-09-27：原 900 起、随时间涨到 1350，改为固定 600
	hp = maxhp
	pos = g.ppos + Vector2(-g.facing * 520.0, 40.0)
	state = "idle"
	cd = 1.5
	walk_to = Vector2.INF
	arrived = false
	g.knight_alive = true


## 骑士离队（选了深蓝之心）：无法接受海嗣的气息
func leave() -> void:
	if not alive:
		return
	alive = false
	g.knight_alive = false
	g.vfx.show_banner("骑士无法接受海嗣的气息 —— 他离开了")
	g.vfx.sparks(pos, Vector2.UP, Color(0.6, 0.8, 1.0), 12, 200.0)
	if not g.relics.has("223"):
		g.progression.gain_relic("223")


## 道中阵亡：退行为罗辛南特
func die() -> void:
	if g.balance:
		print("KNIGHT died t=%d hp_max=%d" % [int(g.t), int(maxhp)])
	alive = false
	fallen = true
	g.knight_alive = false
	var foot: Vector2 = pos + Vector2(0, R * 0.8 + 3.0 * g.PX)
	if g.tex.get("e_knight_death") != null:
		g.vfx.fx_sprite("e_knight_death", foot + Vector2(0, -(80.0 - 3.0) * g.PX * 0.5), g.PX, 0.0)
	g.vfx.sparks(pos, Vector2.ZERO, Color(0.7, 0.85, 1.0), 16, 220.0)
	g.vfx.show_banner("骑士倒下了 —— 罗辛南特退行，黑潮中出现了敌对的骑士")
	Sfx.play("boom", -2.0, 0.8, 0.0)
	g.vfx.shake_screen(0.8)
	if D.ENEMIES.has("knight"):
		D.ENEMIES.knight.no_spawn = false
	if not g.relics.has("223"):
		g.progression.gain_relic("223")


## 终局：走向黑潮中心（9:45 起）
func walk_to_center(target: Vector2) -> void:
	if alive and state != "walk":
		state = "walk"
		walk_to = target
		g.vfx.show_banner("骑士走向了黑潮中心……")


## 10:00：在骑士所在处重生为 Boss；返回生成位置
func take_over() -> Vector2:
	var p: Vector2 = pos
	alive = false
	# knight_alive 保持 true：结局判定（requires flag）在 Boss 战期间不能回退
	if not g.vfx.fx_sprite("fx_knight_rebirth", pos + Vector2(0, -20), g.PX * 1.4, 0.0):
		g.fx.append({"kind": "ring", "pos": pos, "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.9, 1.4)})
	g.vfx.sparks(pos, Vector2.ZERO, Color(0.7, 0.9, 1.4), 24, 260.0)
	g.vfx.shake_screen(1.2)
	return p


func update(dt: float) -> void:
	if not alive:
		return
	flash -= dt
	mt += dt
	var prev: Vector2 = pos
	# 伤害随时间成长（与敌人生命曲线同步），再乘援护倍率
	var lvm: float = g.ally_mult * (1.0 + minf(g.t, 480.0) / 120.0 + maxf(g.t - 480.0, 0.0) / 300.0)
	match state:
		"walk":
			var d: Vector2 = walk_to - pos
			if d.length() > 6.0:
				pos += d.normalized() * minf(110.0 * dt, d.length())
				face = signf(d.x) if absf(d.x) > 1.0 else face
			else:
				arrived = true
		"retreat":
			retreat_t -= dt
			var slot: Vector2 = g.ppos + Vector2(-g.facing * 44.0, 30.0)
			pos = pos.lerp(slot, minf(1.0, dt * FOLLOW_SPD))
			hp = minf(maxhp, hp + maxhp * 0.012 * dt)
			if retreat_t <= 0.0 or hp > maxhp * 0.45:
				state = "idle"
				cd = 1.0
				low_armed = false
		"idle":
			var slot: Vector2 = g.ppos + Vector2(-g.facing * 66.0, 26.0)
			pos = pos.lerp(slot, minf(1.0, dt * FOLLOW_SPD))
			if absf(g.ppos.x - pos.x) > 8.0:
				face = signf(g.ppos.x - pos.x)
			cd -= dt
			if cd <= 0.0:
				var tgt: Dictionary = _target()
				if tgt.is_empty():
					cd = 0.3
				else:
					state = "wind"
					st = 0.0
					dash_dir = (tgt.pos - pos).normalized()
					face = signf(dash_dir.x) if absf(dash_dir.x) > 0.05 else face
					dash_hit.clear()
		"wind":
			st += dt
			if st >= CHARGE_WIND:
				state = "charge"
				st = 0.0
				Sfx.play("swing", -6.0, 0.6)
		"charge":
			st += dt
			pos += dash_dir * CHARGE_SPD * dt
			if g.zone_state != 0 and pos.distance_to(g.zone_c) > g.zone_r - 20.0:
				st = CHARGE_T
			for j in g.enemies_sys.query(pos, 60.0):
				var e: Dictionary = g.enemies[j]
				if e.dead or e.chest or dash_hit.has(e.id) or e.pos.distance_to(pos) > e.r + R + 6.0:
					continue
				dash_hit[e.id] = true
				g.combat.hit("骑士", ["ally", "charge"])
				g.combat.damage(e, 45.0 * lvm * g.dmg_mult)
				if not e.dead:
					e.kb += dash_dir * 260.0
				g.vfx.sparks(e.pos, dash_dir, ICE, 5, 160.0)
				g.vfx.fx_sprite("fx_knight_impact", e.pos + Vector2(0, -e.r * 0.5), g.PX * 0.8, dash_dir.angle())   # 冲锋撞到的每个敌人都有冲击
			# 冲锋残影（每 0.05 秒一个，0.25 秒淡出）+ 脚下冰霜拖尾
			if trail.is_empty() or trail[trail.size() - 1][0].distance_to(pos) > 26.0:
				trail.append([pos, 2 if st < CHARGE_T * 0.7 else 3, 0.25])
				g.fx.append({"kind": "frost_step", "pos": pos + Vector2(0, R * 0.6), "life": 0.6, "max": 0.6, "r": 12.0})
			if st >= CHARGE_T:
				state = "stab"
				st = 0.0
				dash_hit.clear()
		"stab":
			st += dt
			if st >= STAB_HIT_T and not dash_hit.has(-1):
				dash_hit[-1] = true
				var ang: float = dash_dir.angle()
				var nd: float = 110.0
				for j in g.enemies_sys.query(pos, 110.0):
					var ne: Dictionary = g.enemies[j]
					if ne.dead or ne.chest:
						continue
					var dd: float = ne.pos.distance_to(pos)
					if dd < nd:
						nd = dd
						ang = (ne.pos - pos).angle()
				face = signf(cos(ang)) if absf(cos(ang)) > 0.05 else face
				var tip: Vector2 = pos + Vector2.from_angle(ang) * 46.0 * DRAW_K / 0.7
				if not g.vfx.fx_sprite("fx_knight_impact", tip, g.PX * 1.2, ang):
					g.fx.append({"kind": "ring", "pos": tip, "r": 30.0, "life": 0.25, "max": 0.25, "col": ICE})
				# 刺击刀光：沿判定扇形（半角 0.9、半径 92）画一道冰蓝弧光 + 一圈冰晶
				g.vfx.slash_fx(pos, ang, 0.9, 92.0, Color(0.75, 0.95, 1.6), "slash", 0.24)
				g.fx.append({"kind": "ring", "pos": tip, "r": 26.0, "life": 0.3, "max": 0.3, "col": ICE})
				for e in g.enemies_sys.arc_hit(pos, ang, 0.9, 92.0):
					if e.chest:
						continue
					g.combat.hit("骑士", ["ally", "stab"])
					g.combat.damage(e, 60.0 * lvm * g.dmg_mult)
					if not e.dead:
						e.slow = maxf(e.slow, FROST_T)
				Sfx.play("swing", -4.0, 0.9)
			if st >= STAB_T:
				state = "idle"
				cd = CHARGE_CD
				dash_hit.clear()
	for tr in trail:
		tr[2] -= dt
	trail = trail.filter(func(tr): return tr[2] > 0.0)
	# 移动量（帧条选择用）
	var vel: Vector2 = (pos - prev) / maxf(dt, 0.0001)
	mv = lerpf(mv, vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if state == "walk":
		return
	# 仇恨：50% 的近战敌人把骑士当目标（按 id 固定，避免来回摇摆；2026-09-27 原 30%）
	for j in g.enemies_sys.query(pos, 420.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.boss or e.ai != "melee" or e.id % 10 >= 5:
			continue
		e.aggro = pos
	# 接触伤害（每个敌人 1 秒一次）
	for j in g.enemies_sys.query(pos, 80.0):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.dmg <= 0.0 or e.ai != "melee" or e.get("coma", false) or e.get("under", false):
			continue
		# 只有把他当目标的那 30%（以及精英 / Boss）会伤到他；路过的杂兵不打他
		if not (e.boss or e.elite or e.id % 10 < 3):
			continue
		if e.pos.distance_to(pos) > e.r + R and not (e.boss and e.pos.distance_to(pos) > e.r + R + 10.0):
			continue
		if g.t < hit_cd.get(e.id, 0.0):
			continue
		hit_cd[e.id] = g.t + 1.0
		_hurt(e.dmg * 0.4)
	# 弹幕
	for b in g.ebullets:
		if b.life <= 0.0:
			continue
		if b.pos.distance_to(pos + Vector2(0, -20)) < b.r + 16.0:
			b.life = 0.0
			_hurt(b.dmg * 0.6)
	if hp <= 0.0:
		die()
		return
	hp = minf(maxhp, hp + maxhp * 0.005 * dt)
	if hp > maxhp * 0.45:
		low_armed = true
	if state in ["idle", "wind"] and hp < maxhp * 0.3 and low_armed:
		state = "retreat"
		retreat_t = 3.0   # 2026-09-27 原 6 秒
		g.vfx.add_text(pos + Vector2(0, -60), "骑士退到了你身后", Color(0.7, 0.85, 1.0), 14)


func _hurt(v: float) -> void:
	hp -= v
	flash = 0.1
	g.vfx.sparks(pos + Vector2(0, -24), Vector2.UP, Color(0.7, 0.85, 1.0), 3, 160.0)


func heal(v: float) -> void:
	if alive:
		hp = minf(maxhp, hp + v)


func _target() -> Dictionary:
	var best: Dictionary = {}
	var bd: float = CHARGE_RANGE
	for j in g.enemies_sys.query(pos, CHARGE_RANGE):
		var e: Dictionary = g.enemies[j]
		if e.dead or e.chest or e.get("under", false) or e.get("coma", false):
			continue
		var d: float = e.pos.distance_to(pos)
		if d < bd and d > 40.0:
			bd = d
			best = e
	return best


## 绘制（在 2.5D 排序中按脚底 y 调用）；本体帧条 96×80，脚底锚点 (48,77)
func draw() -> void:
	if not alive:
		return
	var name := "e_knight"
	var frames := 2
	var frame := int(g.t * 3.0) % 2
	if state == "wind" or state == "charge":
		if g.tex.get("e_knight_charge") != null:
			name = "e_knight_charge"
			frames = 4
			frame = (0 if st < CHARGE_WIND * 0.5 else 1) if state == "wind" else (2 if st < CHARGE_T * 0.7 else 3)
	elif state == "stab":
		if g.tex.get("e_knight_attack") != null:
			name = "e_knight_attack"
			frames = 4
			frame = clampi(int(st * 10.0), 0, 3)
	elif mv > 40.0 and g.tex.get("e_knight_move") != null:
		name = "e_knight_move"
		frames = 4
		frame = int(mt * 8.0) % 4
	if g.tex.get(name) == null:
		g.draw_circle(pos, R, Color(0.6, 0.8, 1.0))
		return
	var anc := Vector2(0.5, 77.0 / 80.0)
	var sc: float = g.PX * DRAW_K
	var bpos: Vector2 = pos + Vector2(0, R * 0.8 + 3.0 * sc)
	var flip: bool = face < 0.0
	# 冲锋预警线（友方冰蓝，不伤水月）：蓄力时从骑士往外长出，冲锋终点一个小冰晶
	if state == "wind":
		var k: float = st / CHARGE_WIND
		var end: Vector2 = pos + dash_dir * CHARGE_SPD * CHARGE_T
		g.draw_line(pos, end, Color(0.6, 0.85, 1.3, 0.15 + 0.25 * k), 8.0 * k + 2.0)
		g.draw_line(pos, pos + (end - pos) * k, Color(0.9, 1.1, 1.6, 0.8), 2.0)
		UI.diamond(g, end, 4.0 + 3.0 * k, Color(0.9, 1.1, 1.6, 0.5 + 0.4 * k))
	if state == "charge":
		g.vfx.sparks(pos, -dash_dir, Color(0.8, 0.9, 1.4), 2, 110.0)
	# 冲锋残影：冲锋帧条的白色剪影，冰蓝色、渐隐
	if g.tex.has("e_knight_charge_white"):
		for tr in trail:
			g.vfx.spr("e_knight_charge_white", 4, tr[1], tr[0] + Vector2(0, R * 0.8 + 3.0 * sc), sc, flip, Color(0.55, 0.85, 1.4, tr[2] / 0.25 * 0.45), anc)
	if Cfg.outline and g.tex.has(name + "_white"):
		for d in [Vector2(g.PX, 0), Vector2(-g.PX, 0), Vector2(0, g.PX), Vector2(0, -g.PX)]:
			g.vfx.spr(name + "_white", frames, frame, bpos + d * DRAW_K, sc, flip, Color(1.2, 2.2, 3.2, 0.5), anc)
	var col := Color.WHITE
	if state == "retreat":
		col = Color(0.8, 0.85, 0.95, 0.85)
	g.vfx.spr(name, frames, frame, bpos, sc, flip, col, anc)
	if flash > 0.0 and g.tex.has(name + "_white"):
		g.vfx.spr(name + "_white", frames, frame, bpos, sc, flip, Color(1, 1, 1, 0.9), anc)
	# 血条
	var w := 48.0
	var top: Vector2 = pos + Vector2(-w / 2.0, -80.0 * sc + 16.0)
	g.draw_rect(Rect2(top, Vector2(w, 4)), Color(0, 0, 0, 0.6))
	g.draw_rect(Rect2(top, Vector2(w * clampf(hp / maxhp, 0.0, 1.0), 4)), Color(0.6, 0.85, 1.0))


## HUD：援护栏右侧的骑士格（不占 3 个援护位）
func draw_hud(hud: CanvasItem, c: Vector2) -> void:
	if not alive:
		return
	var font: Font = g.font
	var acol := Color(0.6, 0.85, 1.0)
	UI.ring(hud, c, 21.0, clampf(hp / maxhp, 0.0, 1.0), acol)
	var at: Texture2D = g.tex.get("e_knight")
	if at != null:
		var fw := at.get_width() / 2
		var ks: float = 34.0 / at.get_height()
		hud.draw_texture_rect_region(at, Rect2(c + Vector2(-fw * ks / 2.0, 16 - at.get_height() * ks), Vector2(fw, at.get_height()) * ks), Rect2(0, 0, fw, at.get_height()))
	UI.text(hud, font, c + Vector2(-30, 36), "骑士", 11, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 60, 2)
	if state == "retreat":
		UI.text(hud, font, c + Vector2(-30, -40), "撤退", 10, Color(1.0, 0.7, 0.5), HORIZONTAL_ALIGNMENT_CENTER, 60, 2)
