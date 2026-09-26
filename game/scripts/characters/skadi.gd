## 斯卡蒂（近卫，契约 v2.1）：近战输出。前压到主控身边的敌人面前高频横扫大剑。
## S1 潮涌斩：立即一次 ×2 宽幅横扫；S2 重斩：高举下劈大范围重击并击退；S3 潮汐：8 秒全方向横扫、范围与伤害提升。
## 特效（docs/25）：深海蓝 + 白浪。横扫双层弧光（深蓝 + 窄白边）+ 水珠飞溅；重斩抬剑时眼位红光，下劈巨大新月 + 地裂 + 水花柱。
## 可见成长（docs/25 §5，档案「挥剑扭曲狂放，像跳异国舞蹈」）：一击 → 两连斩（镜像弧）→ 三连斩（第三下旋身斩）；
## 重斩掀起海浪墙；潮汐期间脚下每秒涌出水环；精二每轮连斩收尾涌起一圈小海浪。
extends "res://scripts/characters/character.gd"

const BLUE := Color(0.35, 0.55, 0.95)
const FOAM := Color(0.8, 0.95, 1.0)
const DROP := Color(0.6, 0.9, 1.0)
const LEASH := 160.0
const S3_DUR := 8.0

var cd := 0.3
var swings := 0               # 横扫计数（天赋：每第 3 次追加反手斩）
var tide := 0.0               # S3 潮汐剩余
# ---- 可见成长
var combo_n := 1              # N1「狂舞」2 连斩 / N2「异乡之舞」3 连斩
var wave_on := false          # N4「跃浪」：重斩掀起一道向前推进的海浪墙
var surge_on := false         # N5「涌潮」：潮汐期间每秒从脚下涌出一圈水环
var elegy_on := false         # 精二「悲歌」：每轮连斩收尾，身边涌起一圈小海浪
var pending: Array = []       # 连斩后续段 {at, step, dmg}
var waves: Array = []         # 跃浪海浪墙 {pos, dir, dist, max, w, dmg, hit, drop}
var pulse_t := 0.0            # 涌潮计时
const WAVE_MAX := 2


## 基础数值全部可由 data/characters/skadi.json 的 base 段覆盖（docs/27 §3）
func _reach() -> float:
	return base("reach", 88.0) * stat(&"op_range") * (1.4 if tide > 0.0 else 1.0)


func follow_target(slot_pos: Vector2) -> Vector2:
	var p := melee_spot(LEASH, 30.0)
	return p if p != Vector2.INF else slot_pos


## 成长节点（data/characters/skadi.json 的 custom 节点）
func on_custom_node(nid: String, _choice: String = "") -> void:
	match nid:
		"combo2":
			combo_n = maxi(combo_n, 2)
		"combo3":
			combo_n = maxi(combo_n, 3)
		"leap_wave":
			wave_on = true
		"surge":
			surge_on = true


func on_elite(stage: int, _choice: String = "") -> void:
	if stage >= 2:
		elegy_on = true


func update(dt: float) -> void:
	cd -= dt
	tide = maxf(0.0, tide - dt)
	_update_waves(dt)
	# 连斩的后续段（与动作无关，按时间出手）
	for i in range(pending.size() - 1, -1, -1):
		var pd: Dictionary = pending[i]
		pd.at -= dt
		if pd.at <= 0.0:
			pending.remove_at(i)
			_combo_step(pd)
	# 涌潮：潮汐期间每秒一圈水环
	if surge_on and tide > 0.0:
		pulse_t -= dt
		if pulse_t <= 0.0:
			pulse_t = base("pulse_every", 1.0)
			_surge_pulse()
	if acting():
		return
	var ready := charge_skills(dt)
	if ready >= 0:
		var ts: Array = nearest_enemies(1, 200.0, pos)
		start_skill(ts[0].pos if not ts.is_empty() else Vector2.INF, ready)
		if ready == 1:
			fx({"kind": "glow", "pos": pos + Vector2(0, -20), "r": 26.0, "life": 0.3, "col": BLUE, "alpha": 0.35})
		return
	if cd <= 0.0:
		var ts: Array = nearest_enemies(1, _reach() + 30.0, pos)
		if ts.is_empty():
			cd = 0.1
		else:
			cd = base("cd", 0.75) / stat(&"op_aspd")
			start_attack(ts[0].pos)


func _aim() -> float:
	var ts: Array = nearest_enemies(1, _reach() + 60.0, pos)
	if ts.is_empty():
		return facing_angle()
	var a: float = (ts[0].pos - pos).angle()
	face_to(a)
	return a


## 斩击弧光（Ninja Adventure Slash 调深海蓝：普通 / 重斩 / 潮汐全方向三条帧条；缺图退回程序双层弧）+ 水珠
## mirror：沿挥砍方向镜像（连斩第二下反向挥回来）；tint 覆盖帧条的染色
func _slash(ang: float, half: float, r: float, main: Color, edge: Color, life: float, mirror := false, tint := Color(0.72, 0.86, 1.05, 0.88)) -> void:
	var name := "fx_slash_arc_deep"
	var sc: float = r * 1.15 / 40.0
	if half >= PI - 0.01:
		name = "fx_slash_circle_deep"
		sc = r * 2.0 / 66.0
	elif half > 1.6:
		name = "fx_slash_heavy_deep"
		sc = r * 1.2 / 28.0
	var at: Vector2 = pos + Vector2(0, -14) + (Vector2.ZERO if name == "fx_slash_circle_deep" else Vector2.from_angle(ang) * r * 0.5)
	# 镜像：水平翻转 + 转半圈 = 沿挥砍方向上下翻转
	var sa: float = 0.0
	var sf := false
	if name != "fx_slash_circle_deep":
		sa = ang + (PI if mirror else 0.0)
		sf = mirror
	else:
		sf = mirror
	# 染一层深海蓝、略透明：帧条高光接近纯白，叠辉光后会糊成一整片白
	if not spawn_fx_sprite(name, at, sc, sa, sf, false, tint):
		slash_fx(pos + Vector2(0, -14), ang, half, r, main, "slash", life)
		slash_fx(pos + Vector2(0, -14), ang, half * 0.9, r * 0.9, edge, "slash", life * 0.7)
	var sp: Vector2 = pos + Vector2(0, -10) + Vector2.from_angle(ang) * r * 0.6
	for k in 5:
		fx({"kind": "mote", "pos": sp + Vector2(g.rng.randf_range(-12, 12), g.rng.randf_range(-8, 8)), "vel": Vector2.from_angle(ang + g.rng.randf_range(-0.8, 0.8)) * g.rng.randf_range(40, 110) + Vector2(0, -60), "life": 0.4, "col": DROP, "sz": 2.0, "grav": 260.0})


func _release() -> void:
	var ang := _aim()
	var dmg: float = base("atk", 26.0) * _dmg_bonus() * (base("s3_mult", 1.5) * skill_power() if tide > 0.0 else 1.0)
	var half: float = PI if tide > 0.0 else 1.4
	var hits := melee_hit("大剑", pos + Vector2(0, -10), ang, half, _reach(), dmg, 60.0)
	_slash(ang, half, _reach(), BLUE if tide <= 0.0 else Color(0.25, 0.4, 0.85), FOAM, 0.22)
	Sfx.op(id, "atk", 0.0, 1.0, 0.08)
	if not hits.is_empty():
		Sfx.op(id, "hit", 2.0 if tide > 0.0 else 0.0)
	swings += 1
	if elite >= 1 and swings % 3 == 0 and tide <= 0.0:
		var back: float = ang + PI
		melee_hit("反手斩", pos + Vector2(0, -10), back, 1.4, _reach(), dmg * 0.7, 60.0)
		_slash(back, 1.4, _reach(), FOAM, Color(1.2, 1.5, 1.7), 0.2)
	# 狂舞 / 异乡之舞：连斩后续段；只有一击时这一击就是整轮连斩的收尾
	if combo_n >= 2:
		pending.append({"at": base("combo2_delay", 0.12), "step": 2, "dmg": dmg})
	elif elegy_on:
		_elegy(dmg)


## 连斩后续段：第二下镜像回挥（70%），第三下旋身斩一整圈（80%）；最后一段收尾时触发悲歌
func _combo_step(pd: Dictionary) -> void:
	var ang := _aim()
	var dmg: float = pd.dmg
	if pd.step == 2:
		var half: float = PI if tide > 0.0 else 1.4
		melee_hit("大剑", pos + Vector2(0, -10), ang, half, _reach(), dmg * base("combo2_mult", 0.55), 60.0, 0.0, ["follow_up"])
		_slash(ang, half, _reach(), Color(0.3, 0.5, 0.95), FOAM, 0.2, true, Color(0.8, 0.92, 1.1, 0.85))
		Sfx.op(id, "atk", -3.0, 1.12, 0.08)
		if combo_n >= 3:
			pending.append({"at": base("combo3_delay", 0.12), "step": 3, "dmg": dmg})
			return
	else:
		# 旋身斩：一整圈，略大一圈，白浪色，外加一圈沿切线甩出的水珠
		var r: float = _reach() * base("combo3_reach", 1.1)
		melee_hit("大剑", pos + Vector2(0, -10), ang, PI, r, dmg * base("combo3_mult", 0.6), 90.0, 0.0, ["follow_up"])
		_slash(ang, PI, r, FOAM, Color(1.2, 1.5, 1.7), 0.24, face < 0.0, Color(0.95, 1.05, 1.2, 0.8))
		for k in 12:
			var a: float = k * TAU / 12.0
			var p: Vector2 = pos + Vector2(0, -12) + Vector2(cos(a), sin(a) * 0.55) * r * 0.8
			fx({"kind": "mote", "pos": p, "vel": Vector2.from_angle(a + PI / 2.0 * face) * 140.0 + Vector2(0, -40), "life": 0.35, "col": FOAM, "sz": 2.0, "grav": 200.0})
		Sfx.op(id, "atk", -1.0, 0.9, 0.08)
	if elegy_on:
		_elegy(dmg)


## 悲歌（精二）：一轮连斩收尾，身边涌起一圈小海浪（50% 伤害，击退）
func _elegy(dmg: float) -> void:
	var r: float = base("elegy_r", 90.0)
	area_hit("悲歌", pos, r, dmg * base("elegy_mult", 0.5), base("elegy_kb", 220.0))
	if not _surge_fx(pos + Vector2(0, 4), r):
		fx({"kind": "ring", "pos": pos + Vector2(0, 4), "r": r, "r0": 16.0, "life": 0.4, "col": BLUE, "floor": true, "w": 5.0, "alpha": 0.8})
		fx({"kind": "ring", "pos": pos + Vector2(0, 4), "r": r * 0.8, "r0": 10.0, "life": 0.32, "col": FOAM, "floor": true, "w": 2.0})
	for k in 10:
		var a: float = k * TAU / 10.0 + g.rng.randf_range(-0.2, 0.2)
		fx({"kind": "mote", "pos": pos + Vector2(cos(a) * r * 0.8, sin(a) * r * 0.44 + 2.0), "vel": Vector2(cos(a) * 30.0, g.rng.randf_range(-170, -90)), "life": 0.45, "col": DROP, "sz": 2.5, "grav": 360.0})


## 涌潮（N5）：潮汐期间每秒从脚下涌出一圈水环（潮汐普攻 40% 伤害，击退）
func _surge_pulse() -> void:
	var r: float = base("pulse_r", 120.0)
	var dmg: float = base("atk", 26.0) * _dmg_bonus() * base("s3_mult", 1.5) * skill_power() * base("pulse_mult", 0.4)
	area_hit("涌潮", pos, r, dmg, base("pulse_kb", 200.0))
	if not _surge_fx(pos + Vector2(0, 4), r):
		fx({"kind": "ring", "pos": pos + Vector2(0, 4), "r": r, "r0": 12.0, "life": 0.5, "col": Color(0.3, 0.55, 1.0), "floor": true, "w": 6.0, "alpha": 0.7})
		fx({"kind": "ring", "pos": pos + Vector2(0, 4), "r": r * 0.9, "r0": 8.0, "life": 0.42, "col": FOAM, "floor": true, "w": 2.0})
	spawn_fx_sprite("fx_splash_blue", pos + Vector2(0, 6), g.PX * 0.9, 0.0, false, true)


## 涌潮 / 悲歌水环帧条 fx_skadi_surge（Codex 成长线，80×44、6 帧 14fps 单次、椭圆中心 = 作用中心）：
## 第 2 帧最宽的水环半宽约 37 美术像素，按作用半径缩放让它正好压在判定圈上；播完最后一帧即移除。缺图返回 false，调用方画程序水环
func _surge_fx(at: Vector2, r: float) -> bool:
	if A.tex("fx_skadi_surge") == null:
		return false
	fx({"kind": "surge", "pos": at, "sc": r / 37.0, "life": 6.0 / 14.0, "floor": true})
	return true


func _draw_pfx(f: Dictionary, a: float) -> bool:
	if f.kind == "surge":
		var tx: Texture2D = A.tex("fx_skadi_surge")
		if tx != null:
			_strip(tx, 6, clampi(int((1.0 - a) * 6.0), 0, 5), f.pos, f.sc, Vector2(40, 22))
		return true
	return false


## 跃浪（N4）：重斩落点掀起一道向前推进的海浪墙（重斩 80% 伤害，每名敌人只打一次，击退）
func _spawn_wave(ang: float, dmg: float, from: Vector2) -> void:
	if waves.size() >= WAVE_MAX:
		waves.pop_front()
	waves.append({"pos": from, "dir": Vector2.from_angle(ang), "dist": 0.0, "max": base("wave_dist", 200.0), "w": base("wave_w", 140.0),
		"dmg": dmg * base("wave_mult", 0.8), "hit": {}, "drop": 0.0})


func _update_waves(dt: float) -> void:
	if waves.is_empty():
		return
	var spd: float = base("wave_spd", 480.0)
	for w in waves:
		var step: float = spd * dt
		w.pos += w.dir * step
		w.dist += step
		var nrm: Vector2 = w.dir.orthogonal()
		for j in query_ids(w.pos, w.w * 0.5 + 40.0):
			var e: Dictionary = g.enemies[j]
			if e.dead or w.hit.has(e.id):
				continue
			var rel: Vector2 = e.pos - w.pos
			if absf(rel.dot(w.dir)) > 18.0 + e.r or absf(rel.dot(nrm)) > w.w * 0.5 + e.r:
				continue
			w.hit[e.id] = true
			log_hit("跃浪")
			deal_damage(e, w.dmg)
			if not e.dead and not e.boss:
				e.kb += w.dir * base("wave_kb", 260.0) * (0.3 if e.elite else 1.0)
		w.drop -= dt
		if w.drop <= 0.0:
			w.drop = 0.03
			var l: float = g.rng.randf_range(-0.5, 0.5) * w.w
			fx({"kind": "mote", "pos": w.pos + nrm * l + Vector2(0, -18), "vel": w.dir * 120.0 + Vector2(0, g.rng.randf_range(-120, -60)), "life": 0.4, "col": FOAM, "sz": 2.0, "grav": 320.0})
	waves = waves.filter(func(w): return w.dist < w.max)


func _hit_fx(e: Dictionary, origin: Vector2) -> void:
	var d: Vector2 = (e.pos - origin).normalized()
	fx({"kind": "line", "pos": e.pos + Vector2(0, -e.r * 0.5) - d.orthogonal() * 8.0, "to": e.pos + Vector2(0, -e.r * 0.5) + d.orthogonal() * 8.0, "life": 0.15, "col": FOAM, "w": 2.0})


func _release_skill() -> void:
	match cur_skill:
		0:
			# 潮涌斩：一次 ×2 宽幅横扫
			var ang := _aim()
			if not melee_hit("潮涌斩", pos + Vector2(0, -10), ang, 1.75, _reach() * 1.1, base("atk", 26.0) * base("s1_mult", 2.0) * _dmg_bonus() * skill_power(), 120.0).is_empty():
				Sfx.op(id, "hit", 5.0, 0.85)
			_slash(ang, 1.75, _reach() * 1.1, Color(0.3, 0.5, 0.9), FOAM, 0.26)
			Sfx.op(id, "atk", 5.0, 0.8)
		1:
			_heavy(_aim())
		2:
			tide = S3_DUR
			pulse_t = base("pulse_every", 1.0)
			fx({"kind": "ring", "pos": pos, "r": 120.0, "r0": 10.0, "life": 0.5, "col": BLUE, "floor": true})
			g.fx.append({"kind": "rays", "pos": pos + Vector2(0, -20), "life": 0.5, "max": 0.5, "col": BLUE})
			for k in 16:
				fx({"kind": "mote", "pos": pos + Vector2(g.rng.randf_range(-40, 40), 0), "vel": Vector2(g.rng.randf_range(-40, 40), g.rng.randf_range(-220, -100)), "life": 0.6, "col": DROP, "sz": 2.5, "grav": 300.0})
			show_banner("潮汐")


func skill_active_left(i: int) -> float:
	return tide if i == 2 else 0.0


func skill_active_dur(i: int) -> float:
	return S3_DUR if i == 2 else 1.0


func _heavy(ang: float) -> void:
	var r: float = base("s2_r", 150.0) * stat(&"op_range")
	var hdmg: float = base("atk", 26.0) * base("s2_mult", 3.0) * _dmg_bonus() * skill_power()
	melee_hit("重斩", pos + Vector2(0, -10), ang, 1.92, r, hdmg, 240.0)
	_slash(ang, 1.92, r, Color(0.25, 0.4, 0.85), FOAM, 0.32)
	var c: Vector2 = pos + Vector2.from_angle(ang) * r * 0.45
	fx({"kind": "crack", "pos": c, "r": r * 0.6, "life": 0.45, "col": BLUE, "floor": true, "n": 9, "ang": ang})
	fx({"kind": "ring", "pos": c, "r": r * 0.7, "r0": 10.0, "life": 0.35, "col": BLUE, "floor": true, "w": 3.0})
	fx({"kind": "glow", "pos": c + Vector2(0, -10), "r": 34.0, "life": 0.2, "col": FOAM, "alpha": 0.5})
	# 蓝色水花（ansimuz water splash）：落点一大团 + 两侧各一小团
	spawn_fx_sprite("fx_splash_blue", c + Vector2(0, 6), g.PX * 1.4, 0.0, false, true)
	for sd in [-1.0, 1.0]:
		spawn_fx_sprite("fx_splash_blue", c + Vector2(sd * r * 0.3, 10), g.PX * 0.9, 0.0, sd < 0.0, true)
	for k in 18:
		fx({"kind": "mote", "pos": c + Vector2(g.rng.randf_range(-r * 0.3, r * 0.3), 0), "vel": Vector2(g.rng.randf_range(-70, 70), g.rng.randf_range(-260, -120)), "life": 0.6, "col": DROP, "sz": 2.5, "grav": 380.0})
	if wave_on:
		_spawn_wave(ang, hdmg, c)
	g.shake = maxf(g.shake, 4.0)
	Sfx.op(id, "big")


func draw_auras() -> void:
	if tide > 0.0 and pos != Vector2.INF:
		g.draw_set_transform(pos + Vector2(0, 4), 0.0, Vector2(1.0, 0.55))
		g.draw_arc(Vector2.ZERO, _reach(), 0.0, TAU, 36, Color(BLUE.r, BLUE.g, BLUE.b, 0.3 + 0.1 * sin(g.t * 5.0)), 2.0)
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 地面层：跃浪海浪墙——贴地的弧形水墙（中间高两头低），深蓝水体 + 白色浪尖，推进到尽头时淡出
## 有帧条 fx_skadi_wave（Codex 成长线，64×32、6 帧、朝右、底部锚点 (32, 30)）时：沿浪墙排三朵浪（两头略靠后，按 y 由远到近画），
## 朝左推进时水平镜像（像素图不旋转）；帧按推进进度 dist / max 走完 0–5——默认 200 / 480 ≈ 0.42 秒，几乎就是原速 14fps 的 6 帧，
## 改了射程 / 速度也会整条拉伸或压缩到浪墙寿命上，推进到尽头正好播完最后一帧并移除
func draw_entities_floor() -> void:
	var wtx: Texture2D = A.tex("fx_skadi_wave")
	if wtx != null:
		for w in waves:
			var nrm2: Vector2 = w.dir.orthogonal()
			var wf: int = clampi(int(w.dist / w.max * 6.0), 0, 5)
			var pts: Array = []
			for u in [-0.62, 0.0, 0.62]:
				pts.append(w.pos + nrm2 * u * w.w * 0.5 - w.dir * (u * u) * 16.0)
			pts.sort_custom(func(p1, p2): return p1.y < p2.y)
			for bp in pts:
				_strip(wtx, 6, wf, bp, g.PX, Vector2(32, 30), w.dir.x < 0.0)
		return
	for w in waves:
		var a: float = clampf((w.max - w.dist) / 60.0, 0.0, 1.0)
		var nrm: Vector2 = w.dir.orthogonal()
		var basel := PackedVector2Array()
		var top := PackedVector2Array()
		var N := 12
		for i in N + 1:
			var u: float = float(i) / N * 2.0 - 1.0
			var bp: Vector2 = w.pos + nrm * u * w.w * 0.5 - w.dir * (u * u) * 16.0
			var h: float = 26.0 * (1.0 - u * u) + 4.0 + sin(g.t * 14.0 + i) * 2.0
			basel.append(bp)
			top.append(bp + Vector2(0, -h))
		var poly: PackedVector2Array = basel.duplicate()
		var rt: PackedVector2Array = top.duplicate()
		rt.reverse()
		poly.append_array(rt)
		g.draw_colored_polygon(poly, Color(0.25, 0.45, 0.95, 0.45 * a))
		g.draw_polyline(top, Color(1.4, 1.8, 2.2, 0.9 * a), 3.0)
		g.draw_polyline(basel, Color(0.5, 0.8, 1.4, 0.5 * a), 2.0)


func _draw_skill_over() -> void:
	# 重斩 / 潮汐起手：眼位一点红光（精二红瞳）
	if (acting() and act_kind == "skill" and fire_t >= 0.0) or tide > 0.0:
		var p := pos + Vector2(5.0 * face, -38)
		g.draw_circle(p, 3.0 + sin(g.t * 30.0), Color(2.4, 0.4, 0.4, 0.9))
		g.draw_circle(p, 7.0, Color(1.0, 0.2, 0.2, 0.25))


func status_items() -> Array:
	if tide > 0.0:
		return [["潮汐", BLUE]]
	return []


## 画一帧横向帧条（Codex 成长线 growth_fx，双密度）：anchor_px 按 @1x 帧内像素给，sc 为 @1x 每像素的世界尺寸；
## @2x 贴图自动把倍率减半、锚点加倍（同 game.gd _spr_rot 的口径）
func _strip(tx: Texture2D, frames: int, fr: int, p: Vector2, sc: float, anchor_px: Vector2, flip := false, col := Color.WHITE) -> void:
	var hi: float = A.hires_of(tx)
	var fw: int = tx.get_width() / frames
	var fh: int = tx.get_height()
	var k: float = sc / hi
	g.draw_set_transform(p.round(), 0.0, Vector2(-k if flip else k, k))
	g.draw_texture_rect_region(tx, Rect2(-anchor_px * hi, Vector2(fw, fh)), Rect2(fw * (fr % frames), 0, fw, fh), col)
	g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
