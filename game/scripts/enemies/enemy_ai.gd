## 小怪行为（从 game.gd 拆出）：按 data/enemies.json 的字段分派，不再按 type 名硬编码。
##   pattern: burrow 潜行破土咬击 / stomp 踏地震荡 / dash 蓄力冲刺 / acid 站桩吐酸 / nova 蓄力环形弹幕
##   V8：blast 冲到身边自爆 / reap 休眠唤醒后扇形斩 / thrust 直线前刺 + 半血狂暴铺痕 / nest 神经光环 + 触须爆发
##   远程：shot_n 弹数、shot_kind 弹种、shot_home 追踪、shot_spd 弹速、spit 抛射（落点预警）、spawn_on_shot 射击时召唤
## 状态仍在 game.gd 的敌人字典里，本文件通过 g 访问；Boss 招式见 boss_ai.gd。
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

var g  # Game (Node2D)
var next_secondary_at := 0.0  # 大群额外招式错峰，避免同帧连环预警


func _init(game) -> void:
	g = game


const _NONE := {}   # 只读默认值：.get(k, {}) 每次调用都会新建一个空字典（docs/50 §9.11 ④）


func def_of(e: Dictionary) -> Dictionary:
	return D.ENEMIES.get(e.type, _NONE)


## 小怪的攻击模式（返回额外速度；返回 INF 表示走常规 AI）
func pattern(e: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	var d := def_of(e)
	_prepare_pose(e, d, dist)
	if _secondary(e, d, dir, dist):
		return Vector2.ZERO
	match d.get("pattern", ""):
		"bite":
			return _bite(e, d, dir, dist)
		"burrow":
			return _burrow(e, d, dir, dist, dt, spd)
		"stomp":
			return _stomp(e, d, dist)
		"dash":
			return _dash(e, d, dir, dist, dt, spd)
		"acid":
			return _acid(e, d, dir, dist, dt)
		"nova":
			return _nova(e, d, dist, dt)
		"blast":
			return _blast(e, d, dist, dt)
		"reap":
			return _reap(e, d, dir, dist, dt)
		"thrust":
			return _thrust(e, d, dir, dist, dt)
		"nest":
			return _nest(e, d, dist, dt)
	return Vector2.INF


## 额外招式由 enemies.json 配置；只在独立窗口释放，群怪共享预警上限。
func _secondary(e: Dictionary, d: Dictionary, dir: Vector2, dist: float) -> bool:
	var a: Dictionary = d.get("extra", _NONE)
	if a.is_empty() or g.t < float(a.get("min_time", 0.0)) or e.age < float(a.get("first_delay", 2.0)) or dist > float(a.range) or g.t < float(e.get("extra_next", INF)):
		return false
	if e.wind > 0.0 or e.get("dash_w", 0.0) > 0.0 or e.get("dash_t", 0.0) > 0.0 or e.get("nova_w", 0.0) > 0.0 or e.get("blast_w", 0.0) > 0.0:
		return false
	if e.get("dormant", false) or e.get("wake_t", 0.0) > 0.0 or e.get("under", false) or e.get("coma", false) or e.get("friendly", false) or e.get("channel", 0.0) > 0.0:
		return false
	if g.warns.size() >= 10 or (g.t >= 280.0 and g.t < next_secondary_at):
		return false
	if str(a.mode) in ["pierce", "volley"] and g.beacon_sys.ranged_held(e):
		return false   # 圈内安全：读条期间远程额外招式（凿石贯射、齐射）不起手，冷却不推进（docs/49g）
	var reach: float = float(a.range)
	var warn_color := Color(0.64, 0.95, 1.0) if float(a.get("frost", 0.0)) > 0.0 else (Color(0.95, 0.55, 1.0) if float(a.get("nerve", 0.0)) > 0.0 else Color(0.75, 0.55, 1.0))
	var data := {"secondary": true, "cancel_dead": true, "ang": dir.angle(), "name": "", "dmg": e.dmg * float(a.damage_mult),
		"corrode": e.corrode, "nerve": float(a.get("nerve", float(d.get("shot_nerve", e.nerve)) * 0.6)),
		"frost": float(a.get("frost", 0.0)), "stun": float(a.get("stun", 0.0)),
		"col": warn_color, "extra": a}
	var shape := "cone"
	var dur := 0.75
	match str(a.mode):
		"swipe":
			data.merge({"act": "bite", "follow": true, "half": 0.72, "r": reach}, true)
		"pulse":
			shape = "circle"
			data.merge({"act": "burst", "follow": true, "r": minf(reach, 110.0)}, true)
		"pierce":
			shape = "line"
			dur = 0.85
			data.merge({"act": "shot", "len": reach, "wid": 10.0, "track": 0.25}, true)
		"volley":
			data.merge({"act": "extra_volley", "half": float(a.spread) * 0.5, "r": reach}, true)
		_:
			return false
	g.bai._warn(e, shape, dur, data)
	if g.t >= 280.0:
		next_secondary_at = g.t + 0.9
	e.extra_next = g.t + float(a.cd)
	e.shot_ready = false
	return true


## 箱形恐鱼现形后张口蓄势再啃咬，用现有预警/命中机制；不再无动作地接触扣血。
func _bite(e: Dictionary, d: Dictionary, dir: Vector2, dist: float) -> Vector2:
	var reach := float(d.get("bite_range", 76.0))
	if dist < reach and e.wind <= 0.0 and g.bai._cd(e, "bite", float(d.get("bite_cd", 2.6))):
		Sfx.enemy("screech", dist)
		g.bai._warn(e, "cone", 0.6, {"ang": dir.angle(), "half": 0.9, "r": reach, "track": 0.2, "act": "bite", "dmg": e.dmg})
	return Vector2.INF


## 感知阶段只提前展示蓄势姿态，继续接近；不创建伤害、不消耗攻击冷却。
## 到实际攻击距离后仍由原技能提供完整预警，不能把远处的准备当成已预警。
func _prepare_pose(e: Dictionary, d: Dictionary, dist: float) -> void:
	var sense := float(d.get("prepare_range", 0.0))
	e["attack_preparing"] = sense > 0.0 and dist < sense and not e.get("dormant", false) and e.get("stun", 0.0) <= 0.0
	if e.attack_preparing and not e.has("prepare_started"):
		e["prepare_started"] = g.t


## 壳海狂奔者（V8）：冲到 blast_range 内停下鼓胀 blast_fuse 秒后自爆，自身消失、不掉经验；鼓胀中被打死就不炸
func _blast(e: Dictionary, d: Dictionary, dist: float, dt: float) -> Vector2:
	if e.blast_w > 0.0:
		e.blast_w -= dt
		if e.blast_w <= 0.0:
			var r := float(d.get("blast_r", 62))
			# 敌方洋红爆炸（docs/48 P0-8：原来和艾雅法拉的火焰爆炸同色同形，大群里认不出）
			g.fx.append({"kind": "explode", "pos": e.pos, "r": r, "life": 0.35, "max": 0.35, "col": Color(1.0, 0.3, 0.72)})
			g.vfx.sparks(e.pos, Vector2.ZERO, Color(1.8, 0.6, 1.4), 12, 260.0)
			Sfx.play("boom", -8.0, 1.3, 0.0)
			if g.combat.ground_d(g.ppos, e.pos) < r and g.invuln <= 0.0:   # 画即判（§1.9）
				g.dmg_src = "blast_" + e.type
				g.in_type = ["近战", "法术"]
				g.combat.enemy_hit(e.dmg, {"corrode": 0.0, "nerve": 0.0}, false)
			e.dead = true
		return Vector2.ZERO
	if dist < float(d.get("blast_range", 60)):
		e.blast_w = float(d.get("blast_fuse", 0.8))
		return Vector2.ZERO
	return Vector2.INF


## 钵海收割者（V8）：休眠（不动、不接触）直到主控进入 wake_r 或受到伤害；唤醒 0.4 秒后追击，近身扇形斩
func _reap(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float) -> Vector2:
	if e.dormant:
		if dist < float(d.get("wake_r", 160)) or e.hp < e.maxhp:
			e.dormant = false
			e.wake_t = 0.4
			g.vfx.sparks(e.pos, Vector2.UP, Color(1.2, 0.5, 0.5), 10, 200.0)
			Sfx.enemy("screech", dist)
		return Vector2.ZERO
	if e.wake_t > 0.0:
		e.wake_t -= dt
		return Vector2.ZERO
	var rr := float(d.get("reap_range", 88))
	if dist < rr and e.wind <= 0.0 and g.bai._cd(e, "reap", float(d.get("reap_cd", 2.2))):
		Sfx.enemy("bite", dist)
		# 扇形斩前摇 enemy/reaper_windup（0.8 秒），醒来后第一下再加 reaper_first_extra（0.2 秒）：数值 9/29「先让它可躲」；倍率读 reap_mult
		var wu: float = Bal.v("enemy/reaper_windup", 0.8) + (Bal.v("enemy/reaper_first_extra", 0.2) if not e.get("reaped", false) else 0.0)
		e.reaped = true
		g.bai._warn(e, "cone", wu, {"ang": dir.angle(), "half": 0.9, "r": rr + 10.0, "track": 0.2, "act": "bite", "col": Color(1.0, 0.35, 0.35), "dmg": e.dmg * float(d.get("reap_mult", 1.2))})
	return Vector2.INF


## 深溟引痕者（V8）：蓄力直线前刺；生命低于 enrage_at 时狂暴（移速 ×enrage_spd，沿路留下小片溟痕）
func _thrust(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float) -> Vector2:
	# 前刺（_warn_resolve 的 "stab"）写入的冲刺计时：小怪不走 _dash，在这里递减
	if e.dash_t > 0.0:
		e.dash_t = maxf(0.0, e.dash_t - dt)
	if not e.enraged and e.hp <= e.maxhp * float(d.get("enrage_at", 0.5)):
		e.enraged = true
		e.spd *= float(d.get("enrage_spd", 1.35))
		g.vfx.add_text(e.pos + Vector2(0, -e.r - 20.0), "狂暴", Color(1.0, 0.4, 0.5), 14)
	if e.enraged and d.get("trail_mire", false):
		e.trail_t -= dt
		if e.trail_t <= 0.0 and g.mires.size() < 32:
			e.trail_t = 0.7
			g.mires.append({"pos": e.pos + Vector2(0, 8), "r": 8.0, "maxr": 30.0, "life": 5.0, "seed": g.rng.randf() * 100.0, "boss": false})
	var tr := float(d.get("thrust_range", 170))
	if dist < tr and dist > 30.0 and e.wind <= 0.0 and g.bai._cd(e, "thrust", float(d.get("thrust_cd", 3.2))):
		Sfx.enemy("bite", dist)
		g.bai._warn(e, "line", 0.55, {"ang": dir.angle(), "len": tr + 20.0, "wid": 12.0, "track": 0.25, "act": "stab", "spd": 700.0, "col": Color(1.0, 0.35, 0.45), "dmg": e.dmg * float(d.get("thrust_mult", 1.2))})
	return Vector2.INF


## 深溟巢涌者（V8）：神经光环（主控在 aura_r 内每 0.5 秒累积神经损伤）+ 近身触须爆发（圆形预警）
func _nest(e: Dictionary, d: Dictionary, dist: float, dt: float) -> Vector2:
	if dist < float(d.get("aura_r", 110)):
		e.aura_t += dt
		if e.aura_t >= 0.5:
			e.aura_t = 0.0
			if g.invuln <= 0.0:
				g.nerve_aura_t = 0.6   # 神经光环按「站在溟痕里」累积神经损伤（combat.update_nerve）
	if dist < float(d.get("lash_range", 120)) and e.wind <= 0.0 and g.bai._cd(e, "lash", float(d.get("lash_cd", 5.0))):
		Sfx.enemy("screech", dist)
		g.bai._warn(e, "circle", 0.7, {"follow": true, "r": float(d.get("lash_r", 105)), "act": "burst", "col": Color(0.75, 0.45, 1.0), "dmg": e.dmg * 1.3})
	return Vector2.INF


## 潜行接近（半伤、不接触），近身后破土咬击，露头 up_time 秒再潜回
func _burrow(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	if e.get("under", true):
		e.under = true
		e.def = 1.0
		if dist < float(d.get("burrow_range", 84)) and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0:
			e.under = false
			e.def = 1.0
			e.up_t = float(d.get("up_time", 3.2))
			Sfx.enemy("bite", dist)
			g.bai._warn(e, "circle", 0.6, {"follow": true, "r": 50.0, "act": "bite", "col": Color(0.8, 0.5, 1.0), "dmg": e.dmg * 1.3})
			g.vfx.sparks(e.pos, Vector2.UP, Color(0.5, 0.4, 0.7), 10, 200.0)
			return Vector2.ZERO
		return dir * spd
	e.up_t = e.get("up_t", 3.0) - dt
	if e.up_t <= 0.0 and dist > 120.0:
		e.under = true
		g.vfx.sparks(e.pos, Vector2.DOWN, Color(0.5, 0.4, 0.7), 8, 160.0)
	return Vector2.INF


## 近身时踏地震荡
func _stomp(e: Dictionary, d: Dictionary, dist: float) -> Vector2:
	if dist < float(d.get("stomp_range", 170)) and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and g.bai._cd(e, "stomp", float(d.get("stomp_cd", 6.0))):
		Sfx.enemy("screech", dist)
		g.bai._warn(e, "circle", 0.9, {"follow": true, "r": float(d.get("stomp_r", 135)), "act": "slam", "col": Color(1.0, 0.8, 0.5), "dmg": e.dmg * 1.2})
	return Vector2.INF


## 蓄力 dash_wind 秒后高速冲刺
func _dash(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	e["dash_cd"] = e.get("dash_cd", g.rng.randf_range(1.5, 3.5)) - dt
	if e.get("dash_w", 0.0) > 0.0:
		e.dash_w -= dt
		if e.dash_w <= 0.0:
			Sfx.enemy("bite", dist)
			e["dash_t"] = e.get("dash_dur", 0.35)
			e.last_act = {"act": "charge", "shape": "line", "pos": e.pos, "ang": e.dash_dir.angle(), "len": e.get("dash_len", 0.0), "t": g.t}
		return Vector2.ZERO
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t -= dt
		return e.dash_dir * spd * float(d.get("dash_speed", 3.8))
	if e.dash_cd <= 0.0 and dist < float(d.get("dash_range", 240)) and dist > 40.0 and g.beacon_sys.slow_mult(e) >= 1.0:   # safe_slow 对照组：读条光圈附近不起冲刺
		e.dash_cd = g.rng.randf_range(3.0, 4.5)
		e["dash_w"] = float(d.get("dash_wind", 0.5))
		e["dash_dir"] = dir
		# 冲刺时长按起冲时的距离算，保证能冲到主控身上再多 30（原来固定 0.35 秒，滑动者只冲 96、骑士精英 135，起冲距离却是 240 / 300，
		# 根本碰不到人——用户实机反馈 9/27）；夹在 0.2–1.0 秒。dash_len = 实际冲出距离，画冲刺预警线用
		var dv_spd: float = maxf(1.0, spd * float(d.get("dash_speed", 3.8)))
		e["dash_dur"] = clampf((dist + 30.0) / dv_spd, 0.2, 1.0)
		e["dash_len"] = dv_spd * e.dash_dur
		return Vector2.ZERO
	return Vector2.INF


## 站桩吐酸
func _acid(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float) -> Vector2:
	e.cdt -= dt
	if e.cdt <= 0.0 and dist < float(d.get("acid_range", 300)) and not g.beacon_sys.ranged_held(e):   # 圈内安全（docs/49g）
		e.cdt = float(d.get("acid_cd", 4.2))
		Sfx.enemy("acid", dist)   # 站桩吐酸：酸弹声（尖，要躲）
		e.atk_until = g.t + 0.3
		g.ebullets.append({"pos": e.pos, "vel": dir * 180.0, "dmg": 5.0 * (1.0 + minf(g.t, 480.0) / 300.0), "slow": false, "r": 5.0, "life": 2.6,
			"corrode": e.corrode, "nerve": 0.0, "true": false, "kind": "acid", "home": false, "src_type": e.type})
	return Vector2.INF


## 发光蓄力后环形弹幕
func _nova(e: Dictionary, d: Dictionary, dist: float, dt: float) -> Vector2:
	e["nova_cd"] = e.get("nova_cd", g.rng.randf_range(2.0, 4.0)) - dt
	if e.get("nova_w", 0.0) > 0.0:
		e.nova_w -= dt
		if e.nova_w <= 0.0:
			var n: int = int(d.get("nova_n", 6)) + (2 if e.evo else 0)
			for k in n:
				g.ebullets.append({"pos": e.pos, "vel": Vector2.from_angle(TAU * k / n + e.id) * 180.0, "dmg": e.dmg * 0.3, "slow": false,
					"r": 5.0, "life": 2.6, "corrode": e.corrode, "nerve": 0.0, "true": false, "kind": "nova", "home": false, "src_type": e.type})
			Sfx.play("tentacle", -12.0, 0.7, 0.05)
		return Vector2.ZERO
	if e.nova_cd <= 0.0 and dist < float(d.get("nova_range", 320)):
		e.nova_cd = g.rng.randf_range(4.0, 5.5)
		e["nova_w"] = 0.6
		return Vector2.ZERO
	return Vector2.INF


## 远程攻击（小怪按表；Boss 的弹数 / 弹种分支保留在这里，等 Boss 表数据化时再迁）
func shoot(e: Dictionary, dir: Vector2) -> void:
	# 人形治疗另走 IsharEncounter；通用敌方射击绝不能把第一形态的弹打向主控。
	if e.get("friendly", false) or (e.type == "ishar" and e.phase != 2):
		return
	var d := def_of(e)
	if d.get("spit", false) or d.get("lob", false):
		lob(e)
		return
	if e.type not in ["iberia", "carmen"]:
		Sfx.enemy(shot_sfx(e, d), e.pos.distance_to(g.ppos))
	var spd: float = float(d.get("shot_spd", 280.0 if e.boss else 200.0)) * 1.2
	var n: int = int(d.get("shot_n", 1))
	var kind: String = d.get("shot_kind", "orb")
	var home: bool = d.get("shot_home", false)
	if e.type == "ishar" and e.phase == 2:
		n = 3
	if e.type == "paranoia":
		n = 3 if e.phase == 1 else 5
	if e.type == "iberia":
		n = 5
	if e.has("ammo"):
		e.ammo -= 1
		if e.ammo <= 0:
			e.ai = "melee"
			# 打空后先近战追击一段再装填（docs/38 §8.2）：不然她一直保持射程，低射程编队打不到（9/29 实测伊比利亚 >120 秒）
			e.reload_t = maxf(e.get("reload_t", 0.0), float(Bal.v("boss/saint_melee", 8.0)))
			g.vfx.add_text(e.pos + Vector2(0, -40), "弹药耗尽", Color(1.0, 0.8, 0.5), 14)
	for k in n:
		var dk := dir.rotated((k - (n - 1) / 2.0) * 0.22)
		g.ebullets.append({"pos": e.pos, "vel": dk * spd, "dmg": e.dmg * (0.7 if e.boss else 0.45) * (2.0 if e.has("ammo") else 1.0),
			"slow": e.type == "paranoia", "r": 7.0 if e.boss else 5.0, "life": 2.0 if not home else 3.5,
			"corrode": e.corrode, "frost": e.get("frost", 0.0), "nerve": float(d.get("shot_nerve", 0.0)), "true": e.type == "ishar" and e.phase == 2, "kind": kind, "home": home, "atk": d.get("atk", "法术"),
			"mire": (e.type == "paranoia" and e.phase == 2) or d.get("shot_mire", false), "mire_r": float(d.get("shot_mire_r", 52.0)), "mire_life": float(d.get("shot_mire_life", 10.0)), "boss": e.boss, "hit_cap": e.get("hit_cap", 0.0), "src_type": e.type})
	if e.boss:
		e.pose = 0.4
		e.pose_max = 0.4
	e.atk_until = g.t + 0.2   # 小怪攻击帧条（atk_anim）：出手后播第 3、4 帧
	# 射击时召唤（投嗣育母：在水月附近放下注亡拟嗣，场上上限 spawn_max）
	var so: String = d.get("spawn_on_shot", "")
	if so != "":
		var nb := 0
		for o in g.enemies:
			if o.type == so and not o.dead:
				nb += 1
		if nb < int(d.get("spawn_max", 12)):
			var sp_pos: Vector2 = g.ppos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(45.0, 75.0)
			# 先在落点画 0.6 秒预告圈，结算时才刷出（docs/48 P0-7；boss_ai._warn_resolve 的 "spawn"），育母被打死也照常刷出
			g.bai._warn(e, "circle", 0.6, {"pos": sp_pos, "r": 22.0, "act": "spawn", "spawn": so, "lock": false, "col": Color(1.0, 0.3, 0.72), "dmg": 0.0})
			# 出生特效（docs/48 P0-7）：地面裂隙 + 洋红火花，看得出「这里冒出来一只」
			g.fx.append({"kind": "rift", "pos": sp_pos, "r": 22.0, "life": 0.5, "max": 0.5})
			g.vfx.sparks(sp_pos, Vector2.ZERO, Color(1.8, 0.6, 1.4), 8, 140.0)


## 远程开火音（音频，协调人 9/30 定）：要躲的弹用专属声、替换通用吐射声（不叠加）——
## 侵蚀酸弹 acid（尖，辨识度优先）> 远程精英 elite > 神经弹 nerve > 其余照旧 spit。Boss 的开火也走这里，Boss 一律用通用声
func shot_sfx(e: Dictionary, d: Dictionary) -> String:
	if e.boss:
		return "spit"
	if str(d.get("shot_kind", "")) == "acid":
		return "acid"
	if e.get("elite", false) or str(d.get("role", "")) == "elite":
		return "elite"
	if str(d.get("shot_kind", "")) == "nerve":
		return "nerve"
	return "spit"


## 抛射碎石：落点预警，落地范围伤害（spit 的落点留下溟痕）
func lob(e: Dictionary) -> void:
	Sfx.enemy(shot_sfx(e, def_of(e)), e.pos.distance_to(g.ppos))
	e.atk_until = g.t + 0.3
	var to: Vector2 = g.ppos + Vector2(g.rng.randf_range(-30, 30), g.rng.randf_range(-30, 30)) + g.pvel * 0.6   # 落点散布是玩法：用对局随机数
	g.lobs.append({"from": e.pos, "to": to, "t": 0.0, "dur": 0.85, "r": 46.0, "dmg": e.dmg * 0.6, "mire": def_of(e).get("spit", false), "hit_cap": e.get("hit_cap", 0.0),
		"corrode": e.corrode, "frost": e.get("frost", 0.0), "boss": e.boss, "src_type": e.type})
