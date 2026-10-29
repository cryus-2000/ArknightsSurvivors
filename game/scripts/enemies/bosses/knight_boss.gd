## 最后的骑士（type knight_boss，docs/38 §2.7 / §8.8；招式改版 docs/95 §4，10-14；主轴改版 docs/142b §3.1 / §8.2 样板，10-25）
## Boss 行为脚本（docs/55 §6 拆分，10-10）：状态仍在敌人字典 e 上，预警 / 冷却 / 迫近经基类转给 boss_ai.gd。本文件只有这只 Boss 自己的招式与阶段逻辑。
## 主轴「斗牛」：平时重甲（受伤 × knight_armor 0.4），引它冲锋撞上冰柱 → 眩晕 knight_stake_break（2.5）秒（受伤 × knight_break_taken 2.0；用户 10-25「撞上冰柱之后让他眩晕一会」）。
##   原作反冻（受到伤害时给来源附加寒冷）按自动攻击改成「寒气圈」：队长在它脚下 knight_cold_r 内寒冷条上涨，满了冻伤（减速 + 下一击 × 1.75，原作打冻结 175%）。
##   五根冰柱分散成批；全部撞完后统一预告再生，不到期、不由掷枪或转幕补齐。
##   首次插枪布五柱；整批耗尽后等连招结束，掷枪落地补五柱。普通攻击掷枪不补柱。
##   三幕「掷枪」（33%）：掷枪两连；冲锋后再转向冲一次（折线）；寒气圈 180、冻伤更久
##   重生「冲锋形态」（原作）：残柱碎裂且不再布柱；平时走得慢（× knight_reborn_spd 0.5），靠冲锋三连追人，连冲后喘气破绽；
##       重生时原作「释放当前波次」：刷一波 knight_rebirth_wave（16）只
## 最终 Boss 保留已有小怪，停止普通刷新；重生那一波属于机制召唤。
extends "res://scripts/enemies/bosses/boss_base.gd"

const ICE := Color(0.6, 0.9, 1.4)
const IceFx = preload("res://scripts/render/final_attack_grains.gd")
const SHARD_CAP := 18
const MOVES := ["冲锋", "冰线", "长枪连刺", "掷枪", "长枪回旋"]


## Bounded authored chains. Each child warning still owns its full tell and lock window.
func on_warning(e: Dictionary, w: Dictionary) -> void:
	if e.dead or e.get("friendly",false) or e.get("invuln",false): return
	# 近战招配冰屑（用户 10-30「骑士的加频率、加弹量还是要的」，docs/201 §8）：跳斩 / 横扫 / 劈 / 冲锋收尾结算时，从本体朝队长放一扇冰屑
	if float(w.dmg) > 0.0 and Bal.v("boss/knight_melee_shards", 0.0) > 0.0 and (str(w.shape) == "cone" or str(w.act) in ["dash", "stab", "sweep", "bite"] or str(w.name) in MELEE_SHARD_MOVES):
		if not e.has("kn_shard_q"):
			e.kn_shard_q = []
		e.kn_shard_q.append(g.t + float(w.dur))
	if w.dmg <= 0.0 and not (w.act=="final_attack" and w.get("motion","")=="sidestep"): return
	if not e.get("knight_combo_active",false):
		var chain: Array = []
		match str(w.name):
			"断潮劈击", "雪幕劈": chain = ["冲锋","再冲锋","@近身收招"] if e.phase==2 else ["冲锋","@近身收招"]
			"踏冰裂阵": chain = ["掷枪" if e.phase==1 and _act(e)>=1 else "断潮劈击","冲锋"]
			"侧踏挑枪": chain = ["@侧击"]
			"掷枪": chain = ["冲锋"]
			"长枪回旋": chain = [] if e.phase==2 else ["长枪连刺"]   # 重生：回旋后接冰锥 + 2 秒破绽（_reborn_step），不接连刺
			"长枪连刺": chain = ["断潮劈击"]
			"冲锋": chain = ["再冲锋","再冲锋"] if e.phase==2 else (["再冲锋","@近身收招"] if _act(e)>=2 else ["@近身收招"])
			"冰线": chain = ["寒冷追击","再冲锋"] if e.phase==2 else ["寒冷追击","@近身收招"]
		if chain.is_empty(): return
		e.knight_combo_active = true
		e.knight_combo_queue = chain
		e.knight_combo_phase = e.phase
		e.knight_combo_until = g.t + 18.0
		e.knight_combo_next = g.t
	# 分阶段节奏（docs/169 分阶段风格）：一幕 0.22、二幕 0.18、三幕 0.15、重生 0.10 秒
	e.knight_combo_next = maxf(float(e.knight_combo_next),g.t+w.dur+(0.10 if e.phase==2 else [0.22,0.18,0.15][clampi(_act(e),0,2)]))

func cancel_combo(e: Dictionary) -> void:
	_cancel_stake_cast(e)
	e.knight_combo_active = false
	e.knight_combo_queue = []
	e.dash2 = 0
	e.hunt_follow_at = INF
	e.erase("breath_at")
	e.erase("kn_drive")
	e.erase("kn_lap")
	e.erase("kn_lap_brk_at")
	e.erase("kn_z")
	g.warns = g.warns.filter(func(w):return not is_same(w.owner,e) or (w.dmg<=0.0 and w.act!="final_attack"))
	for h in g.bai.finals.hazards:
		if is_same(h.owner,e): g.bai.finals._pop(h)
	g.bai.finals.hazards = g.bai.finals.hazards.filter(func(h):return not is_same(h.owner,e))

## Called before the shared optional attacks, so a reserved follow-up cannot be stolen.
func combo_step(e: Dictionary, dir: Vector2, dist: float, ready: bool) -> bool:
	if not e.get("knight_combo_active",false): return false
	if e.dead or e.get("friendly",false) or e.get("invuln",false) or e.stun>0.0 or e.get("break_t",0.0)>0.0 \
		or e.phase!=e.knight_combo_phase or g.t>float(e.knight_combo_until):
		cancel_combo(e)
		return true
	# The old ice-line follow-up timer must not dispatch a second charge alongside this chain.
	e.hunt_follow_at = INF
	if not ready or g.t<float(e.knight_combo_next) or (e.get("kb_self",false) and e.kb.length()>40.0): return true
	if g.warns.any(func(w):return is_same(w.owner,e) and not w.done and w.dmg>0.0): return true
	var queue: Array = e.knight_combo_queue
	# Entering a break cancels hazards: let the final blade finish before granting recovery.
	if queue.is_empty() and g.bai.finals.hazards.any(func(h):return is_same(h.owner,e)): return true
	var next: String = str(queue.pop_front()) if not queue.is_empty() else ""
	var close_distance: float = g.combat.ground_d(g.ppos,e.pos) if e.phase==2 else dist
	if next=="@近身收招":
		next = ("长枪回旋" if e.phase==2 else "长枪连刺") if close_distance<300.0 else ""
	elif next=="@侧击":
		next = ("长枪回旋" if e.phase==2 else "长枪连刺") if close_distance<300.0 else "冲锋"
	if next=="":
		e.knight_combo_active = false
		e.knight_combo_queue = []
		# 收招破绽（用户 10-27「每个 Boss 都要给干员输出的机会和时间」）：一阶段 1.6→2.4、二阶段 2.5→3.0 秒；
		# 收招时离队长远（冲锋连段常停在 360–520 外）再按距离补最多 1.2 秒，近战走得过去。只延长破绽，不改单发伤害
		var recovery: float = Bal.v("boss/knight_combo_brk2", 3.0) if e.phase==2 else Bal.v("boss/knight_combo_brk1", 2.4)
		recovery += clampf((g.combat.ground_d(g.ppos, e.pos) - 200.0) / 220.0, 0.0, 1.2) * Bal.v("boss/knight_brk_far", 1.0)
		g.combat.start_break(e,recovery)
		e.brk_label = "破绽"
		e.wind = maxf(e.wind,recovery)
		e.final_next = maxf(float(e.get("final_next",0.0)),g.t+recovery)
		return true
	if next in ["再冲锋","寒冷追击"]:
		var angle: float = float(e.get("hunt_angle",dir.angle())) if next=="寒冷追击" else dir.angle()
		var z: bool = e.phase==2 and next=="再冲锋" and e.has("kn_z") and g.t-float(e.kn_z.t)<8.0
		if z:
			# 重生 Z 字三连（docs/171 重生 v3）：第二冲朝队长那一侧折 90°，第三冲回到第一冲的方向（与第一冲平行）
			if int(e.kn_z.k) == 0:
				e.kn_z.a = float(e.get("last_act",{}).get("ang",dir.angle()))
			var a0: float = float(e.kn_z.a)
			if int(e.kn_z.k) == 0:
				e.kn_z.s = 1.0 if Vector2.from_angle(a0).cross(g.ppos - e.pos) >= 0.0 else -1.0
				angle = a0 + PI * 0.5 * float(e.kn_z.s)
			else:
				angle = a0
			e.kn_z.k = int(e.kn_z.k) + 1
		_warn(e,"line",0.6 if e.phase==2 else 0.8,{"ang":angle,"len":520.0 if next=="寒冷追击" else 364.0,"wid":34.0,
			"track":0.0 if (next=="寒冷追击" or z) else (0.2 if e.phase==2 else 0.35),"act":"dash","fit_len":true,"name":next,"col":ICE,
			"dmg":_bite(e,e.dmg*1.35)})
	else:
		force_move(e,next,dir,dist)
	return true


## 当前第几幕：0 = 一幕，1 = 二幕（66%），2 = 三幕（33%）；重生后按 phase 2 另算
func _act(e: Dictionary) -> int:
	return int(e.get("gates_passed", 0))


## 每帧（boss_ai._boss_ai 公共段之后）：ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
## 近战招配冰屑：这些名字的招不论形状都带（docs/201 §8）
const MELEE_SHARD_MOVES := ["断潮劈击", "雪幕劈", "踏冰裂阵", "长枪回旋", "长枪连刺", "冻结重击", "侧踏挑枪"]


## 冰屑加弹（docs/201 §8）：近战招结算时一扇 knight_melee_shards 发；走位间隙每 knight_walk_shard_t 秒朝队长连射 knight_walk_shard_n 发冰锥
func _extra_shards(e: Dictionary, dt: float) -> void:
	if e.dead or e.get("friendly", false):
		return
	var q: Array = e.get("kn_shard_q", [])
	if not q.is_empty():
		var keep: Array = []
		for at in q:
			if g.t >= float(at):
				ice_shards(e, e.pos, aim(e.pos), int(Bal.v("boss/knight_melee_shards", 0.0)), 1.1, 180.0)
			else:
				keep.append(at)
		e.kn_shard_q = keep
	var wt: float = Bal.v("boss/knight_walk_shard_t", 0.0)
	if wt <= 0.0 or float(e.get("wind", 0.0)) > 0.0 or float(e.get("break_t", 0.0)) > 0.0 or float(e.get("dash_t", 0.0)) > 0.0:
		return
	if g.t >= float(e.get("kn_walk_shard_at", 0.0)):
		e.kn_walk_shard_at = g.t + wt
		ice_shards(e, e.pos, aim(e.pos), int(Bal.v("boss/knight_walk_shard_n", 2.0)), 0.25, 200.0)


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	_extra_shards(e, dt)
	if e.get("channel", 0.0) > 0.0:
		e.channel -= dt
		if e.channel <= 0.0:
			e.invuln = false
	if e.has("brk_label") and float(e.get("break_t", 0.0)) <= 0.0:
		e.erase("brk_label")   # 撞柱眩晕 / 喘气破绽结束：别的破绽（韧性）照旧写「破绽」
	elif str(e.get("brk_label", "")) == "眩晕":
		# 撞柱眩晕期间完全定住：不走（wind 让移动速度为 0）、不被击退、不转向（enemies.gd 每帧按主控方向翻面，这里改回撞柱时的朝向）
		e.wind = maxf(float(e.get("wind", 0.0)), float(e.break_t))
		e.kb = Vector2.ZERO
		e.fx = float(e.get("stun_fx", e.fx))
	if _leap_step(e, dt, dir):
		return
	_cold_step(e, dt)
	_ice_step(e)
	_reborn_step(e)
	_big_hold(e)
	if _drive_step(e, dt) or _lap_step(e, dt):
		return
	# 冲锋自然停下：向前碎出 3 片冰屑（撞柱眩晕不出）
	if e.get("kb_self", false):
		e.kn_dashing = true
	elif e.get("kn_dashing", false):
		e.kn_dashing = false
		var la: Dictionary = e.get("last_act", {})
		if str(la.get("act", "")) == "dash" and str(e.get("brk_label", "")) != "眩晕":
			ice_shards(e, e.pos, aim(e.pos), int(round(3 * Bal.v("boss/knight_dense_k", 1.0))), 0.8, 150.0)   # 冰屑一律朝队长（10-28 用户「boss 的子弹没有追着人打」）
			if e.phase == 2:
				_crack_charge(e, float(la.get("ang", 0.0)))
	# 连冲：重生后一组 1 + knight_p2_chain 次（第一次全长、后两次 70%，docs/49d 11.8）；三幕冲锋后再转向冲一次。连冲完喘气 2.5 秒（普通破绽，docs/38 §8.8）
	if int(e.get("dash2", 0)) > 0 and e.get("dash_t", 0.0) <= 0.0 and e.get("wind", 0.0) <= 0.0:
		e.dash2 = int(e.dash2) - 1
		var rw := _warn(e, "line", 0.6, {"ang": dir.angle(), "len": 364.0, "wid": 34.0, "track": 0.3, "act": "dash", "fit_len": true, "name": "再冲锋", "col": ICE,
			"dmg": _bite(e, e.dmg * Bal.v("boss/knight_charge_mult", 1.7))})
		if int(e.dash2) <= 0:
			e.breath_at = g.t + rw.dur + 0.6
	if e.has("breath_at") and g.t >= float(e.breath_at):
		e.erase("breath_at")
		g.combat.start_break(e, Bal.v("boss/knight_breath", 2.5))
		e.brk_label = "破绽"
	if not (ready and e.channel <= 0.0 and e.get("wind", 0.0) <= 0.0):
		return
	# 冰线之后的寒冷追击（沿冰线冲锋）：最高优先；二阶段它就是三连的第一冲
	if g.t >= float(e.get("hunt_follow_at", INF)):
		e.hunt_follow_at = INF
		_warn(e, "line", 0.7, {"ang": float(e.get("hunt_angle", dir.angle())), "len": 520.0, "wid": 32.0,
			"fit_len": true, "act": "dash", "name": "寒冷追击", "col": Color(0.65, 0.95, 1.4), "dmg": _bite(e, e.dmg * 1.35)})
		if e.phase == 2:
			e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))
		return
	if e.phase == 2:
		_reborn_pick(e, dir)
		return
	# 一阶段被贴身绕圈（贴身挨打 ≥ knight_hug_spin 秒）也放长枪回旋：连刺 / 劈击都是从身体中心瞄人的窄线，贴身绕圈角速度大，锁定后总扫空（10-28 用户实玩）
	var hugged: bool = e.phase == 1 and float(e.get("kn_hug", 0.0)) >= Bal.v("boss/knight_hug_spin", 1.5)
	if g.combat.ground_d(g.ppos,e.pos) < 280.0 and (e.phase == 2 or hugged) and float(e.get("cds", {}).get("spin", 0.0)) <= g.t:
		# D 长枪回旋：二阶段近身先回旋后连刺（和连刺互斥）；第一次先亮招式名 0.6 秒（§0.2）——喘气结束时还贴着它就吃这一下
		if _first_tell(e, "spin", "长枪回旋") and _cd(e, "spin", 7.0):
			_spin(e, dir)
		return
	# 冻结重击（三幕，原作「攻击被冻结的目标攻击力 175%」）：冻伤期间、主控在 220 内优先放
	if e.phase == 1 and _act(e) >= 2 and g.t < float(e.get("frostbite_until", 0.0)) and dist < 220.0 and _cd(e, "fzhit", 4.0):
		_frost_hit(e)
		return
	# 普通掷枪（二幕起，重生后不放）：主控在 160–620 时；不补柱。
	if e.phase == 1 and _act(e) >= 1 and dist >= 160.0 and dist <= 620.0 \
			and _cd(e, "spear", Bal.v("boss/knight_spear_cd", 8.0)):
		_spear(e, dir, dist)
		return
	if dist < 260.0 and e.phase == 1 and _cd(e, "stab", 8.0 if _act(e) >= 2 else 5.0):   # 三幕让位给寒潮回卷
		_stab(e, dir)
	elif (dist >= 260.0 or e.phase == 2) and _cd(e, "charge", 4.5 if e.phase == 2 else 6.0):
		# A 冲锋；冰线是它的变体：hunt 冷却到了（18 秒）且主控在 120–600 时改放冰线，0.25 秒后沿线寒冷追击
		if e.phase == 1 and _act(e) != 1 and Bal.v("boss/knight_hunt", 1.0) > 0.0 and dist >= 120.0 and dist <= 600.0 and _cd(e, "hunt", 26.0 if _act(e) >= 2 else 18.0):   # 冰线移出二幕
			_hunt(e, dir, dist)
		else:
			_charge(e, dir)


## 图鉴 / Boss 演练：直接进入二阶段的完整状态
func setup_preview_phase2(e: Dictionary) -> void:
	cancel_combo(e)
	e.phase = 2
	_clear_stakes(e)
	e.final_cycle = 0
	e.hp = e.maxhp * 0.5
	e.spd *= Bal.v("boss/knight_reborn_spd", 0.5)
	e.invuln = true
	e.channel = 1.5
	e.stun = 0.0
	e.kb = Vector2.ZERO
	e.stakes = []
	_tint2(e, STAGE_TINT[3])
	e.kn_reborn_pos = e.pos
	g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0)


func demo_moves(e: Dictionary) -> Array:
	return MOVES + g.bai.finals.names_for(e)


func force_move(e: Dictionary, name: String, dir: Vector2, dist: float) -> bool:
	if g.bai.finals.force_move(e, name, dir, dist):
		return true
	match name:
		"冲锋":
			_charge(e, dir)
		"冰线":
			_hunt(e, dir, dist)
		"长枪连刺":
			_stab(e, dir)
		"掷枪":
			if e.phase != 1:
				return false
			_spear(e, dir, dist)
		"长枪回旋":
			if e.phase != 2:
				return false
			_spin(e, dir)
		"长驱冲锋":
			if e.phase != 2:
				return false
			_drive_start(e, dir)
		"绕场巡猎":
			if e.phase != 2 or not g.zone_frozen:
				return false
			_lap_start(e)
		_:
			return false
	return true


## 冻伤的下一击 × knight_frostbite_mult（1.75，原作「攻击冻结目标攻击力 175%」）：放招时消耗
func _bite(e: Dictionary, dmg: float) -> float:
	if e.get("frostbite_hit", false):
		e.frostbite_hit = false
		return dmg * Bal.v("boss/knight_frostbite_mult", 1.75)
	return dmg


## A · 冲锋：520 × 34 条纹线，追踪 0.4 秒后锁定，总 0.8 秒；e.dmg × 1.7（冲锋期间碰到结算一次）；重生后带三连；三幕后面再转向冲一次（折线）
func _charge(e: Dictionary, dir: Vector2) -> void:
	_warn(e, "line", 0.6 if e.phase==2 else 0.8, {"ang": dir.angle(), "len": 520.0, "wid": 34.0, "track": 0.2 if e.phase==2 else 0.4, "act": "dash", "fit_len": true, "name": "冲锋", "col": ICE,
		"dmg": _bite(e, e.dmg * Bal.v("boss/knight_charge_mult", 1.7))})
	if e.get("knight_combo_active",false):
		e.dash2 = 0
	elif e.phase == 2:
		e.dash2 = int(Bal.v("boss/knight_p2_chain", 2.0))
	elif _act(e) >= 2:
		e.dash2 = 1


## A 变体 · 冰线（用户 9/28 加、10-14 定保留）：细线 18 宽、追踪 0.25，结算留冰脊并标出追击方向，0.25 秒后「寒冷追击」沿线冲锋
func _hunt(e: Dictionary, dir: Vector2, dist: float) -> void:
	_warn(e, "line", 0.85, {"ang": dir.angle(), "len": clampf(dist + 60.0, 240.0, 560.0), "wid": 18.0,
		"track": 0.25, "act": "frost_track", "name": "冰线", "col": Color(0.65, 0.95, 1.4), "dmg": e.dmg * 0.4})


## B · 长枪连刺：三次独立追踪与锁定，逐刺发出向前飞行的短冰锋；末刺射程更长。
func _stab(e: Dictionary, dir: Vector2) -> void:
	var m: float = _bite(e,e.dmg*1.1)
	for k in 3:
		g.bai.finals._warn(e,"line",0.6+0.6*k,{"name":"长枪连刺" if k==0 else "","ang":dir.angle(),
			"len":520.0 if k==2 else 400.0,"wid":24.0,"track":0.2+0.6*k,"skin":"ice_thrust",
			"motion":"linear","speed":700.0,"life":0.62 if k==2 else 0.45,"dmg":m,"chill":0.4})
	e.wind=maxf(e.wind,1.9)

## 掷枪（本作拟，docs/142b §3.1 / §8.2；二幕起）：朝主控掷出长枪，直线 14 宽、追踪 0.4 秒、总 1.0 秒；e.dmg × 1.0；
## 普通掷枪只攻击，不补冰柱。整批耗尽后由独立布柱动作补充；三幕普通掷枪两连。
func _spear(e: Dictionary, dir: Vector2, dist: float) -> void:
	var n: int = 2 if _act(e) >= 2 else 1
	if e.phase == 1 and _act(e) == 1 and Bal.v("boss/knight_prisms", 1.0) > 0.0:
		_prism_plan(e, dir, clampf(dist, 160.0, 520.0))
	for k in n:
		_warn(e, "line", 1.0 + 0.6 * k, {"ang": dir.angle(), "len": clampf(dist, 160.0, 520.0), "wid": 14.0, "track": 0.4 + 0.6 * k, "act": "shot",
			"name": "掷枪", "col": Color(0.75, 0.95, 1.4), "dmg": e.dmg, "lock": k == 0, "spear": true})


## D · 长枪回旋（二阶段，本作改编）：冰面冲击环由内向外扩张，中心与身后缺口安全；只在波前抵达时判定。
func _spin(e: Dictionary, dir: Vector2) -> void:
	g.bai.finals._warn(e,"circle",1.0,{"r":560.0,"inner_r":70.0,"ang":dir.angle(),"gap_ang":dir.angle()+PI,"gap_half":0.7,
		"name":"长枪回旋","skin":"ice_wave","motion":"expanding","speed":0.0,"wave_speed":400.0,"life":1.4,
		"dmg":_bite(e,e.dmg*1.3),"chill":1.0})
	if e.phase == 2:
		e.kn_cone_at = g.t + 1.4
		e.kn_cone_gap = dir.angle() + PI
		e.kn_spin_brk_at = g.t + 2.45

## 寒气圈与寒冷条（原作反冻，按自动攻击改，docs/142b §3.1）：队长在 kcold_r 内、或站在冲锋留下的冰面上 → 寒冷条每秒涨 1 / knight_cold_fill；
## 不在 → 每秒落 1 / knight_cold_decay。破绽期间不涨。满了「冻伤」：knight_frostbite 秒减速（受 Boss 战移速下限 0.7）、下一击 × 1.75，然后清零
func _cold_step(e: Dictionary, dt: float) -> void:
	e.kcold_r = Bal.v("boss/knight_cold_r3", 180.0) if (_act(e) >= 2 and e.phase == 1) else Bal.v("boss/knight_cold_r", 140.0)
	if float(e.get("break_t", 0.0)) > 0.0 or e.get("invuln", false):
		e.kcold = maxf(0.0, float(e.get("kcold", 0.0)) - dt / Bal.v("boss/knight_cold_decay", 2.5))
		return
	var near: bool = g.combat.ground_d(g.ppos, e.pos) < float(e.kcold_r)
	var on_ice: bool = false
	for s in e.get("ice_strips", []):
		if Geometry2D.get_closest_point_to_segment(g.ppos, s.a, s.b).distance_to(g.ppos) < 26.0:
			on_ice = true
			break
	if near or on_ice:
		e.kcold = float(e.get("kcold", 0.0)) + dt / Bal.v("boss/knight_cold_fill", 3.0) * (Bal.v("boss/knight_cold_hot", 1.5) if _cold_hot(e) else 1.0)
	else:
		e.kcold = maxf(0.0, float(e.get("kcold", 0.0)) - dt / Bal.v("boss/knight_cold_decay", 2.5))
	if float(e.kcold) >= 1.0:
		e.kcold = 0.0
		var t: float = Bal.v("boss/knight_frostbite", 1.5) * (2.0 if _cold_hot(e) else 1.0)
		e.frostbite_until = g.t + t
		e.frostbite_hit = true
		g.combat.slow_leader("knight_frostbite", t, 0.5)
		g.combat.frost_leader(t, "boss")
		g.vfx.add_text(g.ppos + Vector2(0, -104), "冻伤！下一击加重", Color(0.75, 0.95, 1.4), 16)
		g.vfx.sparks(g.ppos, Vector2.UP, Color(0.8, 1.2, 1.6), 12, 160.0)
		Sfx.play("stake_shatter", -10.0, 1.3, 0.0)


## 二幕起冲锋路径留冰面 3 秒（冰棱带）：读 last_act（warn_resolve 写），每次冲锋记一条
func _ice_step(e: Dictionary) -> void:
	var st: Array = e.get("ice_strips", [])
	if e.phase == 1 and _act(e) == 1:
		for s in st:
			if g.t >= float(s.until):
				_strip_shards(e, s)   # 冰面碎屑（二幕，docs/183 v2）
	st = st.filter(func(s): return g.t < float(s.until))
	var la: Dictionary = e.get("last_act", {})
	if e.phase == 1 and _act(e) >= 1 and str(la.get("act", "")) == "dash" and float(la.get("t", -1.0)) > float(e.get("ice_last_t", -1.0)):
		e.ice_last_t = float(la.t)
		var a: Vector2 = la.pos
		var b: Vector2 = a + Vector2.from_angle(float(la.ang)) * float(la.len)
		st.append({"a": a, "b": b, "until": g.t + Bal.v("boss/knight_ice_life", 3.0)})
		g.fx.append({"kind": "ice_sheet", "pts": [a, b], "life": Bal.v("boss/knight_ice_life", 3.0), "max": Bal.v("boss/knight_ice_life", 3.0), "enemy": true, "ground": true})
	e.ice_strips = st


## 布柱是独立动作，普通掷枪的 last_act 不再生成单柱。


## ---- 最后的骑士：冰柱（docs/38 §8.8 的冰枪桩；docs/142b §3.1 改为开局就有，10-25 用户「设置成冰柱，多一点，4–5 个」）。
## 场上 boss/knight_stakes（5）根冰柱（判定 r 22），离主控 ≥120、离场地边 ≥100、彼此 ≥90；破土升起帧条见 tools/gen_ice_pillar.py。
## 冰柱只挡骑士：整批耗尽至少等 1.5 秒及当前连招结束，掷枪落地后预告 1 秒升起新柱。
## 仅一阶段布柱；重生时清除残柱，二阶段不再布柱。主控和子弹不受冰柱阻挡。
func _knight_stakes(e: Dictionary, _dt: float) -> void:
	if e.phase != 1:
		_clear_stakes(e)
		return
	if not e.has("stakes"):
		e.stakes = []
		e.stakes_empty_at = g.t
	e.stakes = e.stakes.filter(func(s): return float(s.until) > 0.0)
	if e.stakes.is_empty():
		if not e.has("stakes_empty_at"):
			e.stakes_empty_at = g.t + 1.5

	# 冲锋中撞桩
	if e.get("kb_self", false) and e.kb.length() > 100.0:
		for s in e.stakes:
			if g.t >= float(s.born) and e.pos.distance_to(s.pos) < e.r + 22.0:
				s.until = 0.0
				_shatter(s.pos, 1.0)   # 撞柱崩碎
				g.vfx.sparks(s.pos, Vector2.UP, Color(0.8, 1.2, 1.6), 16, 260.0)
				e.kb = Vector2.ZERO
				e.kb_self = false
				e.dash_t = 0.0
				e.dash2 = 0
				cancel_combo(e)
				e.erase("breath_at")
				g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
				# 撞柱眩晕（用户 10-25）：knight_stake_break（2.5）秒不动不出招、受伤 × knight_break_taken（2.0）；头顶星 + 「眩晕」读秒（world 读 brk_label；骑士别的破绽不写字）
				g.combat.start_break(e, Bal.v("boss/knight_stake_break", 2.5))
				e.brk_label = "眩晕"
				e.stun_fx = e.fx
				Sfx.play("stake_hit", 2.0, 1.0, 0.0)   # 撞桩、长枪脱手
				# 撞柱冲锋是骑士独有的招（10-27）：碎柱冰爆 = 地面星形冰裂 + 冰霜圆盘（render/boss_attack_draw）+ 碎冰 / 冷雾颗粒
				g.fx.append({"kind": "knight_crash", "pos": s.pos, "ang": float(e.get("fx", 1.0)), "life": 1.4, "max": 1.4, "enemy": true})
				IceFx.pillar_crash(g, s.pos)
				Sfx.play("boom", -4.0, 1.2, 0.0)
				break


func _clear_stakes(e: Dictionary) -> void:
	_cancel_stake_cast(e)
	for stake in e.get("stakes", []):
		if float(stake.until) > 0.0:
			_shatter(stake.pos, 1.0)
	e.stakes = []
	e.erase("stakes_empty_at")


## 冰柱崩碎：有冰柱帧条用 prop_knight_frost_stake_break（整数像素，同 world._draw_stakes），没有退回旧冰枪桩碎裂；a = 透明度（自然到期半透明）
func _shatter(pos: Vector2, a: float) -> void:
	if g.tex.get("prop_knight_frost_stake_break") != null:
		g.vfx.fx_sprite("prop_knight_frost_stake_break", pos, 1.0, 0.0, false, true, Color(1, 1, 1, a))
	else:
		g.vfx.fx_sprite("prop_ice_stake_break", pos, g.PX, 0.0, false, true, Color(1, 1, 1, a))


## Reserve a real action before replenishment; timers only make the action eligible.
func stake_cast_step(e: Dictionary, dir: Vector2, ready: bool) -> bool:
	if e.phase != 1:
		_cancel_stake_cast(e)
		return false
	if e.has("stake_cast"):
		var cast: Dictionary=e.stake_cast
		e.fx=cast.face
		if e.dead or e.get("friendly",false) or e.get("invuln",false) or e.stun>0.0 or e.get("break_t",0.0)>0.0 or e.phase!=cast.phase:
			_cancel_stake_cast(e)
			return false
		if cast.stage=="wind" and cast.warning.done:
			cast.stage="flight"
			cast.release_at=g.t
			cast.at=g.t
			cast.land_at=g.t+(0.55 if cast.throw else 0.0)
			if cast.throw:
				g.fx.append({"kind":"final_impact","skin":"stake_flight","pos":e.pos,"target":cast.target,"life":.55,"max":.55,"enemy":true,"owner":e})
		if cast.stage=="flight" and g.t>=cast.land_at:
			cast.stage="rise"
			cast.at=g.t
			_place_stakes(e,int(Bal.v("boss/knight_stakes",5)))
			e.stakes_seeded=true
			e.erase("stakes_empty_at")
			var ends: Array=[]
			cast.end_at=g.t+1.25
			for stake in e.stakes:
				ends.append(stake.pos)
				cast.end_at=maxf(cast.end_at,float(stake.born)+.25)
			g.fx.append({"kind":"final_impact","skin":"stake_roots","pos":cast.target,"ends":ends,"life":1.25,"max":1.25,"enemy":true,"owner":e})
			g.vfx.fx_sprite("fx_knight_ice_hit",cast.target,g.PX,0.0)
			Sfx.play("stake_shatter",-12.0,.8,0.0)
		if cast.stage=="rise" and g.t>=cast.end_at:
			e.erase("stake_cast")
			e.cdt=maxf(e.cdt,.3)
			return true
		e.wind=maxf(e.wind,.1)
		return true
	if not ready or not e.get("stakes",[]).is_empty() or e.get("knight_combo_active",false) \
		or e.get("invuln",false) or e.get("friendly",false) or e.dead or int(e.get("dash2",0))>0 \
		or e.has("breath_at") or float(e.get("hunt_follow_at",INF))<INF \
		or g.t<float(e.get("stakes_empty_at",INF)):
		return false
	var throwing: bool=e.get("stakes_seeded",false)
	var target: Vector2=g.combat.arena_clamp(e.pos+dir*(240.0 if throwing else 45.0),110.0)
	e.fx=dir.x
	var w: Dictionary=_warn(e,"circle",1.0,{"act":"knight_seed","name":"掷枪布柱" if throwing else "插枪布柱","pos":target,"r":34.0,"dmg":0.0,"cancel_dead":true,"col":Color(.48,.65,.72)})
	e.stake_cast={"stage":"wind","warning":w,"throw":throwing,"target":target,"phase":e.phase,"at":g.t,"face":e.fx}
	return true

func _cancel_stake_cast(e: Dictionary) -> void:
	if not e.has("stake_cast"): return
	e.erase("stake_cast")
	g.warns=g.warns.filter(func(w):return not is_same(w.owner,e) or w.act!="knight_seed")
	g.fx=g.fx.filter(func(f):return not (f.get("skin","") in ["stake_flight","stake_roots"] and is_same(f.get("owner"),e)))

func _place_stakes(e: Dictionary, want: int) -> void:
	# Batch invariant: no source (throw, phase change, time) fills a partially used batch.
	if e.phase != 1 or not e.stakes.is_empty():
		return
	var center: Vector2 = g.zone_next_c if g.zone_frozen else e.pos
	var radius: float = minf(360.0, (g.zone_next_r - 110.0) * 0.72) if g.zone_frozen else 320.0
	var offset: float = g.rng_enemy.randf() * TAU
	for k in want:
		var p: Vector2 = center + Vector2.from_angle(offset + TAU * k / want) * radius
		# Keep five sectors, move a sector radially if the player occupies its landing point.
		if p.distance_to(g.ppos) < 100.0:
			p = center + Vector2.from_angle(offset + TAU * k / want) * radius * 0.6
		p = g.combat.arena_clamp(p, 110.0)
		var warning: Dictionary=_warn(e, "circle", 1.0, {"pos": p, "r": 24.0, "act": "", "dmg": 0.0, "lock": false, "col": ICE})
		e.stakes.append({"pos": p, "until": INF, "born": g.t + warning.dur})


## ---- 受击钩子
## 重甲（docs/142b §3.1）：平时受伤 × knight_armor（0.4）；破绽期（撞桩 / 喘气）合计 × knight_break_taken（2.0，除掉公共破绽加成 boss/break_mult）
func taken_mult(e: Dictionary) -> float:
	if float(e.get("break_t", 0.0)) > 0.0:
		return Bal.v("boss/knight_break_taken", 2.0) / maxf(0.01, Bal.v("boss/break_mult", 1.4))
	return Bal.v("boss/knight_armor", 0.4)


## 转幕保留当前冰柱批次，不额外补柱。
## 分阶段风格（docs/169，10-28 用户「每个 boss 不同阶段是不是得做出点不同的风格来？」）：过幕换本体乘色 + 横幅；场地与冰色由 render/boss_attack_draw 按阶段画
const STAGE_TINT := [Color(1, 1, 1), Color(0.9, 1.0, 1.08), Color(0.8, 0.9, 1.28), Color(0.94, 1.0, 1.14)]
const STAGE_BANNER := ["", "冰棱带：冲锋会留下冰面，开始掷枪", "寒潮：掷枪两连，冲锋会折返"]

## 0 一幕 / 1 二幕 / 2 三幕 / 3 重生
static func stage(e: Dictionary) -> int:
	return 3 if int(e.get("phase", 1)) == 2 else clampi(int(e.get("gates_passed", 0)), 0, 2)

func on_gate(e: Dictionary) -> void:
	cancel_combo(e) # Existing pillars persist; only the attack sequence ends.
	var st := stage(e)
	if Cfg.dev_args().has("--kgate"):
		print("KNIGHT_GATE %d t=%.2f" % [st, g.t])   # 仅测试：录像按幕切段
	if st > 0 and st < 3:
		_tint2(e, STAGE_TINT[st])
		g.vfx.show_banner(STAGE_BANNER[st])


## 第一次归零不死，寒冰重生（二阶段「冲锋形态」）
func on_lethal(e: Dictionary) -> bool:
	cancel_combo(e)
	if e.phase != 1:
		return super.on_lethal(e)
	Sfx.play_cue("phase", e.type, "start")
	if Cfg.dev_args().has("--kgate"):
		print("KNIGHT_GATE 3 t=%.2f" % g.t)   # 仅测试：录像按幕切段（重生）
	e.phase = 2
	_clear_stakes(e)
	e.final_cycle = 0
	e.hp = e.maxhp * 0.5
	e.spd *= Bal.v("boss/knight_reborn_spd", 0.5)   # 原作冲锋形态：移速 −50%，靠冲锋三连追人
	e.invuln = true
	e.channel = 1.5
	e.stun = 0.0
	e.kb = Vector2.ZERO
	e.kcold = 0.0
	e.ice_strips = []
	e["tint2"] = STAGE_TINT[3]   # 重生常驻黑冰着色（docs/95 §4.2 → docs/169 分阶段风格；render/world 乘色，不改帧条）
	e.kn_reborn_pos = e.pos   # 重生点：场地画放射状裂冰
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))   # 重生清预警（§4.3 节奏表）
	if not g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0):
		g.fx.append({"kind": "ring", "pos": e.pos, "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.9, 1.4)})
	g.vfx.show_banner("冲锋形态：引它撞上场边就会眩晕")
	Sfx.play("roar", 0.0, 0.9, 0.0)
	g.vfx.shake_screen(1.2)
	# 原作「释放当前波次」：刷一波普通海嗣（场地边缘）
	for k in int(Bal.v("boss/knight_rebirth_wave", 16.0)):
		g.spawner.spawn_enemy(g.spawner.pick_type(), g.combat.arena_clamp(g.spawner.edge_pos(), 60.0))   # 夹进场地圈内：别刷到够不着的地方
	return true

## 脱身跳（10-28 用户实玩「一直在骑士旁边转圈，他放不出攻击并且一直挨打 … 挨打超过一段时间一下子跳走」）：
## 贴身（地面距离扣半径 < knight_hug_r 130）且 0.5 秒内掉过血 → 贴身挨打计时涨；离开或没挨打按 0.5 倍落回。破绽 / 眩晕 / 重生读条期间不计（那是给的输出窗口）。
## 计时满 knight_hug_t（3.5 秒）、冷却 knight_leap_cd（12 秒）到了、手上没有在结算的有伤招 → 取消连段，下蹲 LEAP_CROUCH 后向远离队长的方向
## 跃出 knight_leap_len（280，贴墙时在 ±70° 里挑离队长最远的落点），空中 LEAP_AIR 秒；不算破绽、照常受伤、空中无接触伤害。
## 落地：冰爆（knight_crash 画法缩小）+ 朝队长 5 片冰屑，随后立刻接冲锋（一阶段二幕起改掷枪）。开关 boss/knight_leap（0 = 关）
const LEAP_CROUCH := 0.3
const LEAP_AIR := 0.5

func _leap_step(e: Dictionary, dt: float, dir: Vector2) -> bool:
	var lp = e.get("kn_leap")
	if lp != null:
		e.kb = Vector2.ZERO
		var k: float = (g.t - float(lp.t0)) / LEAP_AIR
		if k < 1.0:
			e.wind = maxf(float(e.wind), 0.05)
			if k >= 0.0:
				var q: float = 1.0 - (1.0 - k) * (1.0 - k)   # 起跳快、落地收
				e.pos = (lp.a as Vector2).lerp(lp.b, q)
				e.air = sin(k * PI) * 56.0
			return true
		e.pos = lp.b
		e.air = 0.0
		e.erase("kn_leap")
		e.wind = 0.0
		e.kn_hug = 0.0
		g.fx.append({"kind": "knight_crash", "pos": e.pos, "r": 70.0, "life": 0.9, "max": 0.9, "enemy": true})
		IceFx.pillar_crash(g, e.pos)
		g.vfx.shake_screen(0.6)
		Sfx.play("stake_shatter", -6.0, 0.9, 0.0)
		var to: Vector2 = g.ppos - e.pos
		ice_shards(e, e.pos, to.angle(), int(round(5 * Bal.v("boss/knight_dense_k", 1.0))), 0.9, 170.0)   # 密度招：跳斩落地冰屑（docs/201 §8）
		var dd: float = to.length()
		if e.phase == 1 and _act(e) >= 1 and dd >= 160.0 and dd <= 620.0:
			_spear(e, to.normalized(), dd)
			_cd(e, "spear", Bal.v("boss/knight_spear_cd", 8.0))   # 照常记冷却
		else:
			_charge(e, to.normalized())
			_cd(e, "charge", 4.5 if e.phase == 2 else 6.0)
		return true
	var calm: bool = float(e.get("break_t", 0.0)) > 0.0 or e.stun > 0.0 or float(e.get("channel", 0.0)) > 0.0 or e.get("invuln", false)
	if e.hp < float(e.get("kn_hp_prev", e.hp)) - 0.01 and not calm:
		e.kn_hit_t = g.t
	e.kn_hp_prev = e.hp
	var near: bool = g.combat.ground_d(g.ppos, e.pos) - float(e.r) < Bal.v("boss/knight_hug_r", 130.0)
	if near and not calm and g.t - float(e.get("kn_hit_t", -9.0)) < 0.5:
		e.kn_hug = float(e.get("kn_hug", 0.0)) + dt
	else:
		e.kn_hug = maxf(0.0, float(e.get("kn_hug", 0.0)) - dt * 0.5)
	if Bal.v("boss/knight_leap", 1.0) <= 0.0 or float(e.kn_hug) < Bal.v("boss/knight_hug_t", 3.5) or g.t < float(e.get("kn_leap_at", 0.0)):
		return false
	if calm or e.get("kb_self", false) or int(e.get("dash2", 0)) > 0 or float(e.get("dash_t", 0.0)) > 0.0 or e.has("breath_at") or e.has("kn_drive") or e.has("kn_lap"):
		return false
	if g.warns.any(func(w): return is_same(w.owner, e) and not w.done and float(w.dmg) > 0.0):
		return false
	if g.bai.finals.hazards.any(func(h): return is_same(h.owner, e)):
		return false
	cancel_combo(e)
	var away: Vector2 = (e.pos - g.ppos).normalized() if e.pos != g.ppos else Vector2.from_angle(-dir.angle())
	var best: Vector2 = e.pos
	for da in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var c: Vector2 = g.combat.arena_clamp(e.pos + away.rotated(da) * Bal.v("boss/knight_leap_len", 280.0), 80.0)
		if c.distance_to(g.ppos) > best.distance_to(g.ppos) + 1.0:
			best = c
	e.kn_leap = {"a": e.pos, "b": best, "t0": g.t + LEAP_CROUCH}
	e.kn_leap_at = g.t + Bal.v("boss/knight_leap_cd", 12.0)
	e.kn_hug = 0.0
	e.wind = maxf(float(e.wind), LEAP_CROUCH + LEAP_AIR)
	e.pose = LEAP_CROUCH
	e.pose_max = LEAP_CROUCH
	# 落点预告：无伤低亮圈（样式 0），只告诉玩家它要落在哪
	_warn(e, "circle", LEAP_CROUCH + LEAP_AIR, {"pos": best, "r": 64.0, "act": "knight_leap", "name": "", "col": ICE, "dmg": 0.0})
	g.vfx.sparks(e.pos, away, Color(0.8, 1.0, 1.4), 10, 140.0)
	Sfx.play("swing", -4.0, 0.6, 0.0)
	return true


## 出招霸体（10-28 用户「骑士的攻击会被打断」）：自己的预警在走（起手到出手）、冰锋在结算、连段进行中、自冲、脱身跳期间，
## 干员的眩晕 / 浮空 / 击退 / 拖拽都不生效（boss_ai.super_armor → enemies.add_cc / apply_kb / hold_at）。
## 只有设计里的撞柱眩晕、收招破绽能打断；破绽期照常吃控制。开关 boss/knight_armor_cast（0 = 关）
func super_armor(e: Dictionary) -> bool:
	if Bal.v("boss/knight_armor_cast", 1.0) <= 0.0 or e.dead or float(e.get("break_t", 0.0)) > 0.0:
		return false
	if e.get("knight_combo_active", false) or e.has("kn_leap") or e.has("kn_roll_end") or int(e.get("dash2", 0)) > 0 or e.has("kn_drive") or e.has("kn_lap"):
		return true
	if e.get("kb_self", false) and (e.kb as Vector2).length() > 40.0:
		return true
	if g.warns.any(func(w): return is_same(w.owner, e) and not w.done):
		return true
	return g.bai.finals.hazards.any(func(h): return is_same(h.owner, e))


## ---- 三幕 · 寒潮（docs/183 v2）
## 冻结重击：主控脚下 r70 圈，0.8 秒预警；冻伤那一下由 _bite × 1.75（原作 175%）。范围小，躲开即可
func _frost_hit(e: Dictionary) -> void:
	g.bai.finals._warn(e, "circle", 0.8, {"name": "冻结重击", "pos": g.ppos, "r": 70.0, "skin": "ice_field", "dmg": _bite(e, e.dmg * 1.2), "chill": 0.6})


## 寒潮回卷：插枪站定 0.8 秒起手，之后 4 秒两臂螺旋雪片（每臂每 0.12 秒 1 片、110 速、自转 1.5 弧度/秒），
## 从身外 90 处起射：贴身的风眼是安全的；结束给 3 秒破绽。雪片走公共 g.ebullets，同屏 ≤ ROLL_CAP
const ROLL_CAP := 60
func roll_start(e: Dictionary, dir: Vector2) -> void:
	g.bai.finals._warn(e, "circle", 0.8, {"name": "寒潮回卷", "pos": e.pos, "r": 90.0, "skin": "ice_field", "dmg": 0.0})
	e.kn_roll_next = g.t + 0.8
	e.kn_roll_end = g.t + 0.8 + Bal.v("boss/knight_roll_t", 4.0)
	e.kn_roll_a = dir.angle()
	e.wind = maxf(float(e.wind), 0.8 + Bal.v("boss/knight_roll_t", 4.0))


func _roll_step(e: Dictionary) -> void:
	if not e.has("kn_roll_end"):
		return
	if e.dead or float(e.get("break_t", 0.0)) > 0.0 or e.phase != 1:
		e.erase("kn_roll_end")
		return
	e.kb = Vector2.ZERO
	while g.t >= float(e.kn_roll_next) and float(e.kn_roll_next) < float(e.kn_roll_end):
		var a: float = float(e.kn_roll_a) + (float(e.kn_roll_next) - float(e.kn_roll_end)) * 1.5
		for arm in 2:
			var d: Vector2 = Vector2.from_angle(a + PI * arm)
			_snow(e, e.pos + Vector2(d.x, d.y * 0.72) * 90.0, d * 110.0)
		e.kn_roll_next = float(e.kn_roll_next) + 0.12
	if g.t >= float(e.kn_roll_end):
		e.erase("kn_roll_end")
		g.combat.start_break(e, Bal.v("boss/knight_roll_brk", 3.0))
		e.brk_label = "破绽"


func _snow(e: Dictionary, from: Vector2, vel: Vector2) -> void:
	var own := 0
	for b in g.ebullets:
		if b.get("knight_snow", false) and b.get("source_id", -1) == e.id:
			own += 1
	if own >= ROLL_CAP:
		return
	g.ebullets.append({"pos": from, "vel": vel, "dmg": e.dmg * 0.35 * Bal.v("boss/knight_ice_dmg_k", 0.8),
		"r": 7.0, "life": 6.0, "slow": false, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "boss_blade",
		"home": false, "boss": true, "atk": "物理", "source_id": e.id, "col": Color(0.92, 0.97, 1.0), "src_type": e.type, "knight_snow": true})


## ---- 二幕 · 冰棱带（docs/183 v2）
## 冰棱阵列：掷枪落地（1.0 秒）后沿投掷路径每 60 立一根冰棱（无伤低亮预告），再 1 秒同时炸开，向路径两侧各射 1 发细长冰棱弹（180）；
## 落地同时给 knight_spear_brk（1.0）秒硬直。开关 boss/knight_prisms（0 = 关）
func _prism_plan(e: Dictionary, dir: Vector2, length: float) -> void:
	var pts: Array = []
	var n: int = int(length / 60.0)
	for i in n:
		pts.append(e.pos + dir * (60.0 * (i + 1)))
	e.kn_prisms = {"land": g.t + 1.0, "burst": g.t + 2.0, "pts": pts, "ang": dir.angle(), "shown": false}


func _prism_step(e: Dictionary) -> void:
	var pr = e.get("kn_prisms")
	if pr == null:
		return
	if not pr.shown and g.t >= float(pr.land):
		pr.shown = true
		for p in pr.pts:
			g.tele.warn(e, "circle", 1.0, {"pos": p, "r": 16.0, "act": "knight_prism", "name": "", "col": ICE, "dmg": 0.0})
		if float(e.get("break_t", 0.0)) <= 0.0 and not e.get("knight_combo_active", false):   # 连段里的掷枪不硬直（破绽会取消连段）
			g.combat.start_break(e, Bal.v("boss/knight_spear_brk", 1.0))
			e.brk_label = "破绽"
	if g.t >= float(pr.burst):
		e.erase("kn_prisms")
		for p in pr.pts:
			_prism_bolt(e, p, Vector2.from_angle(aim(p)) * 180.0)   # 每根冰棱朝队长射 1 发（10-28 用户：子弹要追着人打）
			g.fx.append({"kind": "knight_crash", "pos": p, "r": 26.0, "life": 0.5, "max": 0.5, "enemy": true})


func _prism_bolt(e: Dictionary, from: Vector2, vel: Vector2) -> void:
	g.ebullets.append({"pos": from, "vel": vel, "dmg": e.dmg * 0.35 * Bal.v("boss/knight_ice_dmg_k", 0.8),
		"r": 8.0, "life": 2.2, "slow": false, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "boss_blade",
		"home": false, "boss": true, "atk": "物理", "source_id": e.id, "col": Color(0.55, 0.95, 1.0), "src_type": e.type, "knight_prism": true})


## 冰面碎屑：冲锋冰面（3 秒）消失时，沿冰面均匀碎出 ≤ 6 片冰屑，向两侧慢飞（120）
func _strip_shards(e: Dictionary, s: Dictionary) -> void:
	var a: Vector2 = s.a
	var b: Vector2 = s.b
	var n: int = clampi(int(a.distance_to(b) / 90.0), 2, 6)
	var side: Vector2 = (b - a).normalized().orthogonal()
	for i in n:
		var p: Vector2 = a.lerp(b, (i + 0.5) / n)
		ice_shards(e, p, aim(p), 1, 0.0, 120.0)


## 原作「生命值低于 50% 时寒冷持续时间延长」（2 → 4 秒）：重生冲锋形态起寒冷条涨速 × knight_cold_hot（1.5）、冻伤时长 × 2（docs/183 v2）
func _cold_hot(e: Dictionary) -> bool:
	return e.phase == 2 or _act(e) >= 2


## ---- 重生冲锋形态专属（docs/183 v2）
## 裂地冲锋：每段冲锋自然停下，向前扇形裂出 3 道地缝（ice_lance 直线，地面判定、不是弹），0.6 / 0.75 / 0.9 秒依次喷冰刺；
## 三连的喘气推迟到最后一道地缝结算之后（破绽会取消在途的最终 Boss 招）。开关 boss/knight_crack（0 = 关）
func _crack_charge(e: Dictionary, ang: float) -> void:
	if Bal.v("boss/knight_crack", 1.0) <= 0.0:
		return
	for i in 3:
		var a: float = ang + (i - 1) * 0.45
		g.bai.finals._warn(e, "line", 0.6 + 0.15 * i, {"name": "裂地冲锋" if i == 0 else "", "pos": e.pos, "ang": a, "len": 260.0, "wid": 22.0,
			"skin": "ice_lance", "dmg": e.dmg * 0.9, "chill": 0.6})
	if e.has("breath_at"):
		e.breath_at = maxf(float(e.breath_at), g.t + 1.0)


## 黑冰回旋 → 回旋冰锥：长枪回旋起手后 1.4 秒（冲击环出去 0.4 秒）从本体外射 8 枚冰锥（220，缺口方向不放），
## 冲击环走完（起手后 2.45 秒）给 knight_spin_brk（2.0）秒破绽。冰锥走公共 g.ebullets（冰屑同口径）
func _reborn_step(e: Dictionary) -> void:
	_prism_step(e)
	_roll_step(e)
	if e.has("kn_cone_at") and g.t >= float(e.kn_cone_at):
		ice_shards(e, e.pos, float(e.kn_cone_gap) + PI, int(round(8 * Bal.v("boss/knight_dense_k", 1.0))), TAU, 220.0, float(e.kn_cone_gap), 0.7)   # 密度招：重生冰棱环（缺口半角不变）
		e.erase("kn_cone_at")
	if e.has("kn_spin_brk_at") and g.t >= float(e.kn_spin_brk_at):
		e.erase("kn_spin_brk_at")
		if float(e.get("break_t", 0.0)) <= 0.0 and not e.dead:
			g.combat.start_break(e, Bal.v("boss/knight_spin_brk", 2.0))
			e.brk_label = "破绽"
			e.wind = maxf(float(e.wind), Bal.v("boss/knight_spin_brk", 2.0))


## ---- 重生 v3 · 冲锋形态（docs/171「重生 v3」，10-28 用户批）
## 大招洗牌轮换：长驱冲锋 / 长枪回旋 / 绕场巡猎 / Z 字三连，同一招不连续出；大招之间慢走 knight_big_walk（2.5）秒，期间由最终招轮换补冰枪封径 / 冻潮夹击
const BIG_MOVES := ["drive", "spin", "lap", "triple"]

## 忙（出招 / 破绽 / 读条）的每一帧把下一个大招往后推，保证两个大招之间至少慢走 knight_big_walk 秒
func _big_hold(e: Dictionary) -> void:
	if e.phase != 2:
		return
	if float(e.get("break_t", 0.0)) > 0.0 or e.get("knight_combo_active", false) or e.has("kn_drive") or e.has("kn_lap") \
			or e.has("kn_lap_brk_at") or int(e.get("dash2", 0)) > 0 or e.has("breath_at") or e.has("kn_spin_brk_at") \
			or float(e.get("channel", 0.0)) > 0.0:
		e.kn_big_next = maxf(float(e.get("kn_big_next", 0.0)), g.t + Bal.v("boss/knight_big_walk", 2.5))


func _big_ok(e: Dictionary, mv: String) -> bool:
	match mv:
		"drive":
			return Bal.v("boss/knight_drive", 1.0) > 0.0 and g.zone_frozen
		"lap":
			return Bal.v("boss/knight_lap", 1.0) > 0.0 and g.zone_frozen
		"spin":
			return g.combat.ground_d(g.ppos, e.pos) < 420.0   # 冲击环 560，太远放了也打不到
		"triple":
			return g.t >= float(e.get("kn_triple_at", 0.0))
	return false


func _reborn_pick(e: Dictionary, dir: Vector2) -> void:
	if g.t < float(e.get("kn_big_next", 0.0)):
		return
	var bag: Array = e.get("kn_bag", [])
	for _i in BIG_MOVES.size():
		if bag.is_empty():
			bag = BIG_MOVES.duplicate()
			for i in range(bag.size() - 1, 0, -1):
				var j: int = g.rng_enemy.randi() % (i + 1)
				var t = bag[i]
				bag[i] = bag[j]
				bag[j] = t
			if str(bag[0]) == str(e.get("kn_big_last", "")):
				bag.push_back(bag.pop_front())
		var mv: String = str(bag.pop_front())
		if not _big_ok(e, mv):
			continue
		e.kn_bag = bag
		e.kn_big_last = mv
		e.kn_big_next = g.t + 1.0
		if Cfg.dev_args().has("--kgate"):
			print("KNIGHT_BIG %s t=%.2f" % [mv, g.t])   # 仅测试：重生大招轮换
		match mv:
			"drive":
				_drive_start(e, dir)
			"spin":
				_spin(e, dir)
			"lap":
				_lap_start(e)
			"triple":
				e.kn_z = {"k": 0, "t": g.t}
				e.kn_triple_at = g.t + Bal.v("boss/knight_triple_cd", 20.0)
				_charge(e, dir)
		return
	e.kn_bag = bag


## 长驱冲锋：0.9 秒直线预警（追踪 0.5 秒）后起冲，速度 knight_drive_v0 → v1（320 → 900，knight_drive_acc 1.2 秒加满），
## 每秒最多转 knight_drive_turn（0.52 弧度 ≈ 30°）追队长；冲过的路每 0.2 秒记一段冰面（3 秒，站上去寒冷条涨）。
## 冲出 120 以后撞上场地边缘 → 眩晕 knight_drive_stun（2.5）秒（受伤 × 2，接替一幕撞柱），碎冰向场内反弹 5 片；
## 超过 knight_drive_max（3.0）秒还没撞边 → 收招破绽 knight_drive_brk（1.0）秒。伤害 = 冲锋本体接触（同普通冲锋）
## 骑士本体能到的场地半径：同 enemies._hot_gather 的 Boss 边距（骑士按整个画幅最远顶角留边），场边判定和绕场跑道都用它
func _rim(e: Dictionary) -> float:
	var ds: float = g.PX * float(D.ENEMIES[e.type].get("draw_scale", 1.0))
	return maxf(0.0, g.zone_r - maxf(float(e.r), Vector2(48.0 * ds * 1.3 + 2.0, 80.0 * ds + 16.0).length()))


func _drive_start(e: Dictionary, dir: Vector2) -> void:
	var w := _warn(e, "line", 0.9, {"ang": dir.angle(), "len": 560.0, "wid": 40.0, "track": 0.5, "act": "knight_drive", "name": "长驱冲锋",
		"col": ICE, "dmg": _bite(e, e.dmg * Bal.v("boss/knight_charge_mult", 1.7))})
	e.kn_drive = {"w": w, "go": g.t + float(w.dur), "ang": dir.angle(), "v": 0.0, "dist": 0.0, "seg": e.pos, "seg_t": g.t + float(w.dur)}
	e.wind = maxf(float(e.wind), float(w.dur))


func _drive_step(e: Dictionary, dt: float) -> bool:
	if not e.has("kn_drive"):
		return false
	var d: Dictionary = e.kn_drive
	if g.t < float(d.go):
		d.ang = float(d.w.ang)
		e.wind = maxf(float(e.wind), 0.05)
		return true
	var k: float = clampf((g.t - float(d.go)) / Bal.v("boss/knight_drive_acc", 1.2), 0.0, 1.0)
	d.v = lerpf(Bal.v("boss/knight_drive_v0", 320.0), Bal.v("boss/knight_drive_v1", 900.0), k)
	var turn: float = Bal.v("boss/knight_drive_turn", 0.52) * dt
	d.ang = float(d.ang) + clampf(angle_difference(float(d.ang), (g.ppos - e.pos).angle()), -turn, turn)
	var dv := Vector2.from_angle(float(d.ang))
	d.dist = float(d.dist) + float(d.v) * dt
	e.kb = dv * float(d.v)
	e.kb_self = true
	e.dash_decel = 0.0
	e.dash_dir = dv
	e.dash_t = maxf(float(e.get("dash_t", 0.0)), 0.1)
	e.wind = maxf(float(e.wind), 0.1)
	if absf(dv.x) > 0.05:
		e.fx = signf(dv.x)
	if g.t - float(d.seg_t) >= 0.2:
		var life: float = Bal.v("boss/knight_ice_life", 3.0)
		var st: Array = e.get("ice_strips", [])
		st.append({"a": d.seg, "b": e.pos, "until": g.t + life})
		e.ice_strips = st
		# 冰面画成一整条（ice_sheet 折线随冲锋延长），冲锋期间不淡，停下后按 knight_ice_life 整条淡出
		if not d.has("sheet"):
			d.sheet = {"kind": "ice_sheet", "pts": [d.seg], "life": life, "max": life, "enemy": true, "ground": true}
			g.fx.append(d.sheet)
		d.sheet.pts.append(e.pos)
		d.sheet.life = life
		d.seg = e.pos
		d.seg_t = g.t
	var edge: bool = g.zone_frozen and float(d.dist) > 120.0 and (e.pos - g.zone_c).length() >= _rim(e) - 8.0
	if edge or g.t - float(d.go) >= Bal.v("boss/knight_drive_max", 3.0):
		_drive_end(e, edge)
	return true


func _drive_end(e: Dictionary, edge: bool) -> void:
	var ang: float = float(e.kn_drive.ang)
	e.erase("kn_drive")
	e.kb = Vector2.ZERO
	e.kb_self = false
	e.dash_t = 0.0
	var t: float
	if Cfg.dev_args().has("--kgate"):
		print("KNIGHT_DRIVE_END edge=%s t=%.2f" % [edge, g.t])
	if edge:
		t = Bal.v("boss/knight_drive_stun", 2.5)
		g.combat.start_break(e, t)
		e.brk_label = "眩晕"
		e.stun_fx = e.fx
		g.fx.append({"kind": "knight_crash", "pos": e.pos, "ang": float(e.fx), "life": 1.4, "max": 1.4, "enemy": true})
		IceFx.pillar_crash(g, e.pos)
		Sfx.play("stake_hit", 2.0, 1.0, 0.0)
		Sfx.play("boom", -4.0, 1.2, 0.0)
		g.vfx.shake_screen(0.8)
		ice_shards(e, e.pos, aim(e.pos), int(round(5 * Bal.v("boss/knight_dense_k", 1.0))), 1.0, 150.0)   # 密度招：长驱冲锋收尾冰屑（docs/201 §8）
	else:
		t = Bal.v("boss/knight_drive_brk", 1.0)
		g.combat.start_break(e, t)
		e.brk_label = "破绽"
	e.wind = maxf(float(e.wind), t)


## 绕场巡猎（坐骑罗辛南特）：0.8 秒预告落点 → 以 800 速跑到场地内缘（离边 120）→ 沿内缘绕 knight_lap_t（4.0）秒（约 0.85 圈），
## 每 0.5 秒从所在位置朝队长掷一根冰枪（直线预警 0.6 秒，地面判定、不是弹，e.dmg × knight_lap_lance 0.7）；
## 绕完朝场心收尾冲锋（0.7 秒预警），冲完且自己的有伤预警都结算后给 knight_lap_brk（2.0）秒破绽
func _lap_start(e: Dictionary) -> void:
	var c: Vector2 = g.zone_c
	var R: float = maxf(160.0, _rim(e) - 20.0)
	var a0: float = (e.pos - c).angle() if e.pos.distance_to(c) > 1.0 else 0.0
	var rim: Vector2 = c + Vector2.from_angle(a0) * R
	var w := _warn(e, "circle", 0.8, {"pos": rim, "r": 60.0, "act": "knight_lap", "name": "绕场巡猎", "col": ICE, "dmg": 0.0})
	e.kn_lap = {"stage": "wind", "go": g.t + float(w.dur), "c": c, "R": R, "a": a0, "rim": rim,
		"s": 1.0 if g.rng_enemy.randf() < 0.5 else -1.0, "t0": 0.0, "throw": 0.0}
	e.wind = maxf(float(e.wind), float(w.dur))


func _lap_step(e: Dictionary, dt: float) -> bool:
	if not e.has("kn_lap"):
		if e.has("kn_lap_brk_at") and g.t >= float(e.kn_lap_brk_at) and not e.get("kb_self", false) \
				and not g.warns.any(func(w): return is_same(w.owner, e) and not w.done and float(w.dmg) > 0.0):
			e.erase("kn_lap_brk_at")
			if float(e.get("break_t", 0.0)) <= 0.0 and not e.dead:
				var t: float = Bal.v("boss/knight_lap_brk", 2.0)
				g.combat.start_break(e, t)
				e.brk_label = "破绽"
				e.wind = maxf(float(e.wind), t)
		return false
	var L: Dictionary = e.kn_lap
	e.wind = maxf(float(e.wind), 0.1)
	e.kb = Vector2.ZERO
	if g.t < float(L.go):
		return true
	var c: Vector2 = L.c
	if str(L.stage) != "lap":
		var to: Vector2 = (L.rim as Vector2) - e.pos
		var mv: float = 800.0 * dt
		if to.length() <= mv:
			e.pos = L.rim
			L.stage = "lap"
			L.t0 = g.t
			L.throw = g.t + 0.3
		else:
			e.pos += to.normalized() * mv
			if absf(to.x) > 1.0:
				e.fx = signf(to.x)
		e.dash_t = maxf(float(e.get("dash_t", 0.0)), 0.1)
		return true
	var lt: float = Bal.v("boss/knight_lap_t", 4.0)
	var k: float = g.t - float(L.t0)
	var a: float = float(L.a) + float(L.s) * TAU * 0.85 * minf(k, lt) / lt
	var np: Vector2 = c + Vector2.from_angle(a) * float(L.R)
	if absf(np.x - e.pos.x) > 0.5:
		e.fx = signf(np.x - e.pos.x)
	e.pos = np
	e.dash_t = maxf(float(e.get("dash_t", 0.0)), 0.1)
	if g.t >= float(L.throw) and k < lt:
		L.throw = float(L.throw) + 0.5
		g.bai.finals._warn(e, "line", 0.6, {"name": "", "pos": e.pos, "ang": (g.ppos - e.pos).angle(), "len": 620.0, "wid": 20.0,
			"skin": "ice_lance", "dmg": e.dmg * Bal.v("boss/knight_lap_lance", 0.7), "chill": 0.4})
	if k >= lt:
		e.erase("kn_lap")
		var to_c: Vector2 = c - e.pos
		var w := _warn(e, "line", 0.7, {"ang": to_c.angle(), "len": minf(520.0, to_c.length() + 120.0), "wid": 34.0, "track": 0.0, "act": "dash",
			"fit_len": true, "name": "", "col": ICE, "dmg": _bite(e, e.dmg * Bal.v("boss/knight_charge_mult", 1.7))})
		e.kn_lap_brk_at = g.t + float(w.dur) + 0.6
	return true


func on_kill(e: Dictionary) -> void:
	cancel_combo(e)


## 冰屑弹（用户 10-27「可以增加一些弹幕，但是不用太多，因为是近战攻击为主」）：冰锋 / 冰波 / 冲锋自然收尾时碎出几片慢速冰屑，
## 同屏最多 SHARD_CAP（18）片；走公共 g.ebullets（判定、机器人躲避、干员消弹同一管线）。单发 e.dmg × 0.35 × knight_ice_dmg_k。
## 只在自然结束时出：被打断 / 撞柱 / 转幕不出。开关 boss/knight_shards（0 = 关）
## 从 from 指向队长的角度：骑士所有冰屑扇 / 冰棱弹都按这个瞄准（螺旋雪片、回旋冰锥是图案弹，不瞄）
func aim(from: Vector2) -> float:
	return (g.ppos - from).angle() if g.ppos.distance_to(from) > 1.0 else 0.0


func ice_shards(e: Dictionary, from: Vector2, ang: float, n: int, spread: float, spd: float, gap_ang := INF, gap_half := 0.0) -> void:
	if Bal.v("boss/knight_shards", 1.0) <= 0.0 or e.get("dead", false):
		return
	if n > 1:
		n = int(round(n * Bal.v("boss/count_k_knight_boss", 1.0)))   # 10-29 docs/201 §7：每波冰屑数（缺口半角不变）
	var own := 0
	for b in g.ebullets:
		if b.get("knight_shard", false) and b.get("source_id", -1) == e.id:
			own += 1
	for i in n:
		if own >= int(Bal.v("boss/knight_shard_cap", SHARD_CAP)):   # 同屏上限旋钮（docs/201 §8：原 18 片把加弹全截掉了）
			return
		var a: float = ang + (lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, n - 1)) if spread < TAU else TAU * float(i) / n)
		if gap_ang != INF and absf(angle_difference(a, gap_ang)) < gap_half:
			continue
		g.ebullets.append({"pos": from, "vel": Vector2.from_angle(a) * spd, "dmg": e.dmg * 0.35 * Bal.v("boss/knight_ice_dmg_k", 0.8),
			"r": 9.0, "life": 1.8, "slow": false, "frost": 0.0, "corrode": 0.0, "nerve": 0.0, "true": false, "kind": "boss_blade",
			"home": false, "boss": true, "atk": "物理", "source_id": e.id, "col": Color(0.62, 0.88, 1.0), "src_type": e.type, "knight_shard": true})
		own += 1
