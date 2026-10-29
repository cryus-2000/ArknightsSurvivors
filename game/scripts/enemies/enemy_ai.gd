## 小怪行为（从 game.gd 拆出）：按 data/enemies.json 的字段分派，不再按 type 名硬编码。
##   pattern: burrow 潜行破土咬击 / stomp 踏地震荡 / dash 蓄力冲刺 / acid 站桩吐酸 / nova 蓄力环形弹幕
##   V8：blast 冲到身边自爆 / reap 休眠唤醒后扇形斩 / thrust 直线前刺 + 半血狂暴铺痕 / nest 神经光环 + 触须爆发
##   远程：shot_n 弹数、shot_kind 弹种、shot_home 追踪、shot_spd 弹速、spit / lob 抛射（落点预警；lob_kind brood = 投嗣育母投出拟嗣、落地孵化）
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
	if d.get("pattern", "") == "reap" and e.hp < e.maxhp and not e.enraged:
		return _reap(e, d, dir, dist, dt)   # 受伤形态切换先于额外招式，避免同帧被直刺抢走
	if d.get("pattern", "") == "thrust" and not e.enraged and e.hp <= e.maxhp * float(d.get("enrage_at", 0.5)):
		return _thrust(e, d, dir, dist, dt)
	if d.has("scream_r") and _scream(e, d, dist, dt):
		return Vector2.INF   # 箱形恐鱼尖叫期间照常移动，不啃咬、不出额外招式
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


## 封印（docs/61 §15 st.seal）期间仍要推进的招式状态：已经起手的蓄力 / 冲刺 / 环弹蓄力 / 自爆照常走完，不卡在半截
func busy(e: Dictionary) -> bool:
	return e.get("dash_w", 0.0) > 0.0 or e.get("dash_t", 0.0) > 0.0 or e.get("nova_w", 0.0) > 0.0 or e.get("blast_w", 0.0) > 0.0


## 普通怪的蓄力 / 预警时长（用户 10-28「收割者这种小怪的蓄力也可以加速」，docs/182）：非精英非 Boss 的蓄力 × enemy/windup_mult（0.7），
## 但不短于 enemy/windup_min（0.4 秒，手机上看得清；原本就更短的不拉长）；预警圈 / 线 / 扇形的显示与判定读同一个时长，伤害不改。1 = 关
func _wu(e: Dictionary, dur: float) -> float:
	if e.elite or e.boss:
		return dur
	return maxf(dur * Bal.v("enemy/windup_mult", 1.0), minf(dur, Bal.v("enemy/windup_min", 0.4)))


## 额外招式由 enemies.json 配置；只在独立窗口释放，群怪共享预警上限。
func _secondary(e: Dictionary, d: Dictionary, dir: Vector2, dist: float) -> bool:
	var a: Dictionary = d.get("extra", _NONE)
	if a.is_empty() or g.t < float(a.get("min_time", 0.0)) or e.age < float(a.get("first_delay", 2.0)) or dist > float(a.range) or g.t < float(e.get("extra_next", INF)):
		return false
	if e.wind > 0.0 or e.get("dash_w", 0.0) > 0.0 or e.get("dash_t", 0.0) > 0.0 or e.get("nova_w", 0.0) > 0.0 or e.get("blast_w", 0.0) > 0.0:
		return false
	if e.get("dormant", false) or e.get("wake_t", 0.0) > 0.0 or e.get("depart_t", 0.0) > 0.0 or e.get("under", false) or e.get("coma", false) or e.get("friendly", false) or e.get("channel", 0.0) > 0.0:
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
			data.merge({"act": "burst", "follow": true, "r": reach}, true)   # 按 json 范围（囊壳震爆 135、酸蚀脉冲 100）；原 110 截断去掉（docs/145 §2.3）
		"pierce":
			shape = "line"
			dur = 0.85
			data.merge({"act": "shot", "len": reach, "wid": 10.0, "track": 0.25}, true)
		"volley":
			data.merge({"act": "extra_volley", "half": float(a.spread) * 0.5, "r": reach}, true)
		_:
			return false
	g.tele.warn(e, shape, _wu(e, dur), data)
	if g.t >= 280.0:
		next_secondary_at = g.t + 0.9
	e.extra_next = g.t + float(a.cd)
	e.shot_ready = false
	return true


## 箱形恐鱼现形尖叫（docs/145 §4 A，用户 10-25：尖叫期间照常移动）：现形或第一次走到 scream_wake_r 内时开始，
## 张口 scream_delay 秒后尖叫 scream_t 秒——队长在 scream_r 内就累积神经损伤（同巢涌者光环，走 g.nerve_aura_t），光环随它移动；
## 画面 world._scream_aura（地面层常亮淡底 + 不转的虚线边界、危险色、不闪）。返回 true = 尖叫中（含张口），这一帧不啃咬、不出额外招式。
## 原作「宝箱恐鱼」：惊醒后尖叫，周围持续神经损伤
## 用户 10-28：圈内除神经损伤（enemy/mimic_scream_nerve 倍率，缺省 1.6 = 约 19/秒）外还吞噬灯火（enemy/mimic_scream_lamp 每秒，缺省 7 ≈ 满 2.5 秒扣上限 17%）；
## 流明光域里两样都不生效，灯火扣减走 lamp_loss_mult，每累计 ≥ 3 点飘一次「灯火 -N」
func _scream(e: Dictionary, d: Dictionary, dist: float, dt := 0.0) -> bool:
	if not e.has("scream_t0"):
		if dist >= float(d.get("scream_wake_r", 260.0)):
			return false
		start_scream(e, d)
	if g.t >= float(e.scream_t1):
		return false
	if g.t >= float(e.scream_t0) and dist < float(d.get("scream_r", 150.0)) and g.invuln <= 0.0:
		g.telemetry.aura_type = str(e.type)
		g.nerve_aura_t = 0.6
		g.nerve_aura_k = Bal.v("enemy/mimic_scream_nerve", 1.6)
		if not g.squad.in_sanctuary(g.ppos):
			var l0: float = g.lamp
			g.lamp = maxf(0.0, g.lamp - Bal.v("enemy/mimic_scream_lamp", 7.0) * dt * g.lamp_loss_mult)
			g.telemetry.lamp_note("尖叫", g.lamp - l0)
			e["scream_lamp"] = float(e.get("scream_lamp", 0.0)) + (l0 - g.lamp)
			if float(e.scream_lamp) >= 3.0:
				g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -%d" % int(e.scream_lamp), Color(1.0, 0.6, 0.4), 13)
				e["scream_lamp"] = 0.0
	return true


## 尖叫起点（现形时由 spawner.reveal_mimic 调，刷出来的在第一次靠近时由 _scream 调）
func start_scream(e: Dictionary, d: Dictionary) -> void:
	e["scream_t0"] = g.t + float(d.get("scream_delay", 0.4))
	e["scream_t1"] = float(e.scream_t0) + float(d.get("scream_t", 2.5))
	Sfx.enemy("screech", e.pos.distance_to(g.ppos))
	g.vfx.add_text(e.pos + Vector2(0, -e.r - 24.0), "尖叫", Color(0.55, 0.85, 1.0), 14)


## 箱形恐鱼现形后张口蓄势再啃咬，用现有预警/命中机制；不再无动作地接触扣血。
## 连咬（docs/145 §4 B）：第一口起手后 bite_dur + bite2_delay 秒朝队长补第二口（扇形同第一口、伤害 × bite2_mult），第二口单独出预警
func _bite(e: Dictionary, d: Dictionary, dir: Vector2, dist: float) -> Vector2:
	var reach := float(d.get("bite_range", 76.0))
	if e.has("bite2_at") and g.t >= float(e.bite2_at):
		e.erase("bite2_at")
		if e.stun <= 0.0 and dist < reach + 60.0:
			g.tele.warn(e, "cone", float(d.get("bite2_delay", 0.35)), {"ang": dir.angle(), "half": 0.9, "r": reach, "track": 0.1, "act": "bite", "dmg": e.dmg * float(d.get("bite2_mult", 0.6)),
				"atk_fx": str(d.get("atk_fx", "")), "atk_fx_origin": d.get("atk_fx_origin", [-1, -1])})
		return Vector2.INF
	if dist < reach and e.wind <= 0.0 and g.bai.cd_ready(e, "bite", float(d.get("bite_cd", 2.6))):
		Sfx.enemy("screech", dist)
		g.tele.warn(e, "cone", 0.6, {"ang": dir.angle(), "half": 0.9, "r": reach, "track": 0.2, "act": "bite", "dmg": e.dmg,
			"atk_fx": str(d.get("atk_fx", "")), "atk_fx_origin": d.get("atk_fx_origin", [-1, -1])})   # 出手帧条（docs/96 §3 箱形恐鱼 fx_mimic_bite，缺图只有刀光）
		if d.has("bite2_mult"):
			e["bite2_at"] = g.t + 0.6
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
			# 敌方洋红爆炸（docs/48 P0-8：原来和艾雅法拉的火焰爆炸同色同形，大群里认不出）；Codex fx_runner_blast（docs/96 §3，enemies.json blast_fx）到了就用帧条
			var bfx: String = str(d.get("blast_fx", ""))
			if bfx == "" or not g.vfx.fx_sprite(bfx, e.pos, g.PX, 0.0):
				g.fx.append({"kind": "explode", "pos": e.pos, "r": r, "life": 0.35, "max": 0.35, "col": Color(1.0, 0.3, 0.72)})
				g.vfx.sparks(e.pos, Vector2.ZERO, Color(1.8, 0.6, 1.4), 12, 260.0)
			else:
				g.fx[g.fx.size() - 1]["enemy"] = true
			Sfx.play("boom", -8.0, 1.3, 0.0)
			if g.combat.ground_d(g.ppos, e.pos) < r and g.invuln <= 0.0:   # 画即判（§1.9）
				g.combat.enemy_hit(e.dmg, {"corrode": 0.0, "nerve": 0.0}, false, false, ["近战", "法术"], "blast_" + e.type)
			e.dead = true
		return Vector2.ZERO
	if dist < float(d.get("blast_range", 60)):
		e.blast_w = _wu(e, float(d.get("blast_fuse", 0.8)))
		e["blast_w0"] = e.blast_w   # 画面按这一次实际引信时长算进度（render/world.gd）
		return Vector2.ZERO
	return Vector2.INF


## 钵海收割者：受伤后展开一对镰肢并狂奔；近身高举后劈砍，周围产生神经波纹。
func _reap(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float) -> Vector2:
	if e.hp < e.maxhp and not e.enraged:
		e.enraged = true
		e.dormant = false
		e.wake_t = 0.4
		e.spd *= float(d.get("rush_speed_mult", 1.45))
		e.aura_t = 0.0
		g.vfx.sparks(e.pos, Vector2.UP, Color(0.35, 0.75, 1.0), 8, 160.0)
		Sfx.enemy("screech", dist)
	if e.dormant:
		if dist < float(d.get("wake_r", 160)):
			e.dormant = false
			e.wake_t = 0.4
			g.vfx.sparks(e.pos, Vector2.UP, Color(0.35, 0.75, 1.0), 8, 160.0)
			Sfx.enemy("screech", dist)
		return Vector2.ZERO
	if e.wake_t > 0.0:
		e.wake_t -= dt
		return Vector2.ZERO
	if e.enraged:
		var ar: float = float(d.get("nerve_aura_r", 90.0))
		e.aura_t -= dt
		if e.aura_t <= 0.0:
			e.aura_t = float(d.get("nerve_pulse_cd", 0.9))
			if dist < 460.0:
				g.fx.append({"kind": "ring", "pos": e.pos, "r": ar, "life": 0.45, "max": 0.45, "col": Color(0.35, 0.72, 1.0), "enemy": true})
		if dist < ar and g.invuln <= 0.0:
			g.telemetry.aura_type = str(e.type)
			g.nerve_aura_t = 0.6
		# 临战自身流失（docs/95 §18，原作每秒 4%）已删：用户 10-29「它现在没有什么威胁，直接删掉这个特性」
	var rr := float(d.get("reap_range", 88))
	if dist < rr and e.wind <= 0.0 and g.bai.cd_ready(e, "reap", float(d.get("reap_cd", 2.2))):
		Sfx.enemy("bite", dist)
		# 扇形斩前摇 enemy/reaper_windup（0.8 秒），醒来后第一下再加 reaper_first_extra（0.2 秒）：数值 9/29「先让它可躲」；倍率读 reap_mult
		var wu: float = Bal.v("enemy/reaper_windup", 0.8) + (Bal.v("enemy/reaper_first_extra", 0.2) if not e.get("reaped", false) else 0.0)
		e.reaped = true
		g.tele.warn(e, "cone", _wu(e, wu), {"ang": dir.angle(), "half": 0.9, "r": rr + 10.0, "track": 0.2, "act": "bite", "name": "镰肢劈砍", "col": Color(0.35, 0.72, 1.0), "dmg": e.dmg * float(d.get("reap_mult", 1.2)),
			"atk_fx": str(d.get("atk_fx", "")), "atk_fx_origin": d.get("atk_fx_origin", [-1, -1])})
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
	# 拖痕（docs/155）：原来每 0.7 秒铺一片、常驻且共用 32 片总上限，一追就是一长串，顶满后全图溟痕都不再生成。
	# 现在每走 enemy/trail_spacing 铺一片（站着不动不铺），每只最多留 trail_max 片，更旧的淡出；怪物溟痕总量另有上限（combat.add_enemy_mire）
	if e.enraged and d.get("trail_mire", false):
		var lp = e.get("trail_last")
		var tp: Vector2 = e.pos + Vector2(0, 8)
		if (lp == null or tp.distance_to(lp) >= Bal.v("enemy/trail_spacing", 40.0)) and not g.combat.mire_blocked(tp, 30.0):
			e["trail_last"] = tp
			var tm := {"pos": tp, "r": 12.0, "maxr": 30.0, "life": 5.0, "seed": g.vrng.randf() * 100.0, "boss": false}
			g.combat.add_enemy_mire(tm, "trail")
			if not e.has("trail_list"):
				e["trail_list"] = []
			e.trail_list.append(tm)
			if e.trail_list.size() > int(Bal.v("enemy/trail_max", 8.0)):
				g.combat.fade_mire(e.trail_list.pop_front())
	var tr := float(d.get("thrust_range", 170))
	if dist < tr and dist > 30.0 and e.wind <= 0.0 and g.bai.cd_ready(e, "thrust", float(d.get("thrust_cd", 3.2))):
		Sfx.enemy("bite", dist)
		g.tele.warn(e, "line", _wu(e, 0.55), {"ang": dir.angle(), "len": tr + 20.0, "wid": 12.0, "track": 0.25, "act": "stab", "spd": 700.0, "col": Color(1.0, 0.35, 0.45), "dmg": e.dmg * float(d.get("thrust_mult", 1.2)),
			"atk_fx": str(d.get("atk_fx_enraged", d.get("atk_fx", "")) if e.enraged else d.get("atk_fx", "")), "atk_fx_origin": d.get("atk_fx_origin", [-1, -1])})
	return Vector2.INF


## 深溟巢涌者（V8）：神经光环（主控在 aura_r 内每 0.5 秒累积神经损伤）+ 近身触须爆发（圆形预警）
func _nest(e: Dictionary, d: Dictionary, dist: float, dt: float) -> Vector2:
	if dist < float(d.get("aura_r", 110)):
		e.aura_t += dt
		if e.aura_t >= 0.5:
			e.aura_t = 0.0
			if g.invuln <= 0.0:
				g.telemetry.aura_type = str(e.type)   # 作战记录：神经损伤记给放光环的敌人
				g.nerve_aura_t = 0.6   # 神经光环按「站在溟痕里」累积神经损伤（combat.update_nerve）
	if dist < float(d.get("lash_range", 120)) and e.wind <= 0.0 and g.bai.cd_ready(e, "lash", float(d.get("lash_cd", 5.0))):
		Sfx.enemy("screech", dist)
		g.tele.warn(e, "circle", _wu(e, 0.7), {"follow": true, "r": float(d.get("lash_r", 105)), "act": "burst", "col": Color(0.75, 0.45, 1.0), "dmg": e.dmg * 1.3,
			"atk_fx": str(d.get("atk_fx", "")), "atk_fx_origin": d.get("atk_fx_origin", [-1, -1])})
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
			g.tele.warn(e, "circle", 0.6, {"follow": true, "r": 50.0, "act": "bite", "col": Color(0.8, 0.5, 1.0), "dmg": e.dmg * 1.3})
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
	if dist < float(d.get("stomp_range", 170)) and e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and g.bai.cd_ready(e, "stomp", float(d.get("stomp_cd", 6.0))):
		Sfx.enemy("screech", dist)
		g.tele.warn(e, "circle", _wu(e, 0.9), {"follow": true, "r": float(d.get("stomp_r", 135)), "act": "slam", "col": Color(1.0, 0.8, 0.5), "dmg": e.dmg * 1.2, "ground": true})   # ground：轮廓画在地面层，不盖住单位（用户 10-24）
	return Vector2.INF


## 蓄力 dash_wind 秒后高速冲刺
func _dash(e: Dictionary, d: Dictionary, dir: Vector2, dist: float, dt: float, spd: float) -> Vector2:
	if not e.has("dash_cd"):
		e["dash_cd"] = g.rng_enemy.randf_range(1.5, 3.5)   # 首次才抽（原来缺省值参数每帧都求值，白抽一次；docs/101 §3.4 ①）
	e.dash_cd -= dt
	if e.get("dash_w", 0.0) > 0.0:
		e.dash_w -= dt
		if e.dash_w <= 0.0:
			Sfx.enemy("bite", dist)
			e["dash_t"] = e.get("dash_dur", 0.35)
			e.last_act = {"act": "charge", "shape": "line", "pos": e.pos, "ang": e.dash_dir.angle(), "len": e.get("dash_len", 0.0), "t": g.t}
		return Vector2.ZERO
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t -= dt
		var dfx: String = str(d.get("dash_fx", ""))
		if dfx != "":
			# 冲刺拖出的扁平水痕（docs/96 §3 滑动者 fx_slider_dash，地面层；缺图不画）：纯画面计时，不碰随机数
			e["dfx_t"] = float(e.get("dfx_t", 0.0)) - dt
			if e.dfx_t <= 0.0:
				e.dfx_t = 0.08
				if g.vfx.fx_sprite(dfx, e.pos, g.PX, e.dash_dir.angle(), false, false, Color.WHITE, true):
					g.fx[g.fx.size() - 1]["enemy"] = true
		return e.dash_dir * spd * float(d.get("dash_speed", 3.8))
	if e.dash_cd <= 0.0 and dist < float(d.get("dash_range", 240)) and dist > 40.0:
		e.dash_cd = g.rng_enemy.randf_range(3.0, 4.5)
		e["dash_w"] = _wu(e, float(d.get("dash_wind", 0.5)))
		e["dash_w0"] = e.dash_w   # 画面按这一次实际蓄力时长算进度（render/world.gd）
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
	if not e.has("nova_cd"):
		e["nova_cd"] = g.rng_enemy.randf_range(2.0, 4.0)   # 同上（§3.4 ①）
	e.nova_cd -= dt
	if e.get("nova_w", 0.0) > 0.0:
		e.nova_w -= dt
		if e.nova_w <= 0.0:
			var n: int = int(d.get("nova_n", 6)) + (2 if e.evo else 0)
			for k in n:
				g.ebullets.append({"pos": e.pos, "vel": Vector2.from_angle(TAU * k / n + e.id) * 180.0, "dmg": e.dmg * 0.3, "slow": false,
					"r": 5.0, "life": 2.6, "corrode": e.corrode, "nerve": 0.0, "true": false, "kind": "nova", "home": false, "src_type": e.type,
					"tex": str(d.get("shot_tex", ""))})   # 专属弹体（docs/96 §3 子代 proj_offspring_spore）
			Sfx.play("tentacle", -12.0, 0.7, 0.05)
		return Vector2.ZERO
	if e.nova_cd <= 0.0 and dist < float(d.get("nova_range", 320)):
		e.nova_cd = g.rng_enemy.randf_range(4.0, 5.5)
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
			"mire": (e.type == "paranoia" and e.phase == 2) or d.get("shot_mire", false), "mire_r": float(d.get("shot_mire_r", 52.0)), "mire_life": float(d.get("shot_mire_life", 10.0)), "boss": e.boss, "hit_cap": e.get("hit_cap", 0.0), "src_type": e.type,
			"tex": str(d.get("shot_tex", "")), "hit_fx": str(d.get("hit_fx", "")), "hit_org": d.get("hit_fx_origin", [12, 19])})   # 专属弹体 / 命中帧条（docs/96，纯画面；缺图回退程序画法）
	if e.boss:
		e.pose = 0.4
		e.pose_max = 0.4
	e.atk_until = g.t + 0.2   # 小怪攻击帧条（atk_anim）：出手后播第 3、4 帧
	_muzzle_fx(e, d)


## 出手帧的发射口特效（enemies.json muzzle_fx / muzzle_off，docs/96 §1.2 漂移体 fx_skimmer_muzzle）：纯画面，缺图不画。
## muzzle_off 是攻击帧 f2 里发射口相对脚底锚点的 1x 美术像素偏移（朝右），按本体缩放、随朝向镜像；脚底 = world 的 bpos（e.pos 往下 r × 0.8 + 3 × PX）
func _muzzle_fx(e: Dictionary, d: Dictionary) -> void:
	var mf: String = str(d.get("muzzle_fx", ""))
	if mf == "" or g.tex.get(mf) == null:
		return
	var off: Array = d.get("muzzle_off", [0, 0])
	var s1: float = D.enemy_scale(e, g.t, g.PX)   # 1 个 1x 美术像素 = 多少世界像素（含 draw_scale，不含 @2x 密度）
	var flip: bool = e.fx < 0.0
	var at: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * g.PX) + Vector2((-1.0 if flip else 1.0) * float(off[0]) * s1, float(off[1]) * s1) + D.enemy_offset(e, g.t, Bal.v("fx/recoil_px", 3.0), maxf(0.01, Bal.v("fx/recoil_t", 0.1)))
	g.vfx.fx_sprite(mf, at, s1, 0.0, flip)


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
## lob_kind "brood"（投嗣育母，用户 10-14 定）：投出的是一只注亡拟嗣——低弧抛射 lob_dur 秒、落点预警圈半径 lob_r、
## 散布 ±lob_spread；落地造成原酸弹的接触伤害 + 侵蚀，并在落点孵化一只拟嗣（场上上限 spawner.type_cap，到上限只伤不孵；run/enemies.update_lobs）
func lob(e: Dictionary) -> void:
	var d := def_of(e)
	Sfx.enemy(shot_sfx(e, d), e.pos.distance_to(g.ppos))
	e.atk_until = g.t + 0.3
	var kind: String = str(d.get("lob_kind", "rock"))
	if kind == "brood":
		var sp: float = float(d.get("lob_spread", 40.0))
		var to: Vector2 = g.ppos + Vector2(g.rng_enemy.randf_range(-sp, sp), g.rng_enemy.randf_range(-sp, sp)) + g.pvel * 0.5
		g.lobs.append({"from": e.pos, "to": to, "t": 0.0, "dur": float(d.get("lob_dur", 0.8)), "r": float(d.get("lob_r", 30.0)), "dmg": e.dmg * 0.45,
			"mire": false, "kind": "brood", "spawn": "brood", "hit_cap": e.get("hit_cap", 0.0), "corrode": e.corrode, "frost": 0.0, "boss": e.boss, "src_type": e.type})
		# 出手特效 fx_mother_throw（docs/96 §1.1，Codex enemy_fx_1：原点 (6,12) 对齐口器，装在 e_mother_attack 的 (29,12)，
		# 本体 34×32 脚底锚点 → 相对 e.pos (+12,-20) 美术像素；朝队长一侧、朝左镜像；缺图时无）
		var face: float = 1.0 if g.ppos.x >= e.pos.x else -1.0
		g.vfx.fx_sprite("fx_mother_throw", e.pos + Vector2(face * 12.0, -20.0) * g.PX, g.PX, 0.0, face < 0.0, false, Color.WHITE, false, Vector2(6, 12))
		return
	var to: Vector2 = g.ppos + Vector2(g.rng_enemy.randf_range(-30, 30), g.rng_enemy.randf_range(-30, 30)) + g.pvel * 0.6   # 落点散布是玩法：用对局随机数
	g.lobs.append({"from": e.pos, "to": to, "t": 0.0, "dur": 0.85, "r": 46.0, "dmg": e.dmg * 0.6, "mire": d.get("spit", false), "hit_cap": e.get("hit_cap", 0.0),
		"corrode": e.corrode, "frost": e.get("frost", 0.0), "boss": e.boss, "src_type": e.type,
		"tex": str(d.get("lob_tex", "")), "land_fx": str(d.get("land_fx", "")), "hit_fx": str(d.get("hit_fx", "")), "hit_org": d.get("hit_fx_origin", [12, 19])})   # 专属抛射物 / 落点 / 命中帧条（docs/96 §1.4 喷吐者，纯画面）
