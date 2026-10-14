## Boss 行为与招式预警（从 game.gd 拆出）：所有状态仍在 game.gd，本文件通过 g 访问
## 10-10 起各 Boss 的招式分支在 scripts/enemies/bosses/<type>.gd（见下方 SCRIPTS 注册表与 docs/38 §1.17）；本文件是公共段 + 分派 + 预警管线
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")

# 只缩短招式之间的等待；预警、锁定、连段间隔与伤害保持原约定。
const SKILL_COOLDOWN_SCALE := 0.70

const Patterns = preload("res://scripts/enemies/boss_patterns.gd")
var patterns
# 招式令牌（docs/49d：7:00 两只 Boss 共存时不同时放大招）：有名字的 Boss 招式占用，结算后 0.6 秒释放
var token_owner = null
var token_until := 0.0
var g  # Game (Node2D)


func _init(game) -> void:
	g = game
	patterns = Patterns.new(game)


## Boss 行为
func boss_step(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	e.bt += dt
	g.combat.gate_update(e, dt)   # 阶段卡点：每幕计时、护盾到时过卡点（docs/38 §1.3）
	if g.zone_frozen and is_same(e, g.final_boss):
		e.pos = g.combat.arena_clamp(e.pos, 80.0)   # 最终 Boss 场地：本体离圈边 ≥80（docs/38 §1.7）
	# 冲锋 / 突刺计时（_warn_resolve 的 "dash" / "stab" 写入）：Boss 不走 enemy_ai 的冲刺递减，必须在这里递减，
	# 否则骑士二阶段「再冲锋」（等 dash_t 归零）永远不会触发，冲锋帧条也会一直停在冲刺姿势（docs/38 B0 第 1 项）
	if e.get("dash_t", 0.0) > 0.0:
		e.dash_t = maxf(0.0, e.dash_t - dt)
		# 冲刺落地后的破绽（伊莎玛拉潮涌迫近，boss/ishar_close_break 秒，0 = 关）
		if e.dash_t <= 0.0 and e.get("land_break", 0.0) > 0.0:
			g.combat.start_break(e, e.land_break)
			# 落地破绽（tools/gen_sfx_boss_events.py）：伊莎玛拉 = 水花拍地 + 下沉咕噜；偏执泡影 = 膜状「啵嗯」+ 泡沫嘶声
			if e.type == "paranoia":
				Sfx.play("paranoia_land_break", -8.0, 1.0, 0.0)
			else:
				Sfx.play("ishar_land_break", -0.6, 1.0, 0.0)
			e.land_break = 0.0
	# 接潮：昏迷后回复；两者同时昏迷则一起倒下
	if e.get("coma", false):
		# 假死赛跑（docs/38 §8.4）：boss/pair_race 秒内血条涨回 pair_revive_hp（50%），期间打倒另一具 = 两具一起倒下；到时复苏
		e.coma_t = e.get("coma_t", 0.0) + dt
		var race: float = Bal.v("boss/pair_race", 8.0)
		e.hp = maxf(1.0, e.maxhp * Bal.v("boss/pair_revive_hp", 0.5) * minf(e.coma_t / race, 1.0))
		var p = e.get("partner")
		if p != null and not p.dead and p.get("coma", false):
			e.coma = false
			p.coma = false
			e.invuln = false
			p.invuln = false
			g.combat.kill(e)
			g.combat.kill(p)
			g.vfx.show_banner("接潮双体 同时倒下")
			return
		if e.coma_t >= race:
			e.coma = false
			e.invuln = false
			e.coma_t = 0.0
			e.revives = int(e.get("revives", 0)) + 1
			g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.4, "life": 0.5, "max": 0.5, "col": Color(0.4, 1.0, 0.9), "enemy": true})
			g.vfx.add_text(e.pos + Vector2(0, -50), "复苏（%d / %d）" % [e.revives, int(Bal.v("boss/pair_revives", 2.0))], Color(0.6, 1.0, 0.9), 18)
			# 复苏回调（docs/95 §12 on_revive：斥亡体「迸发」等在这里起手）
			var hr = boss(e.type)
			if hr != null:
				hr.on_revive(e)
		return
	var ready: bool = e.get("wind", 0.0) <= 0.0 and e.stun <= 0.0 and e.get("channel", 0.0) <= 0.0 and e.get("dash_t", 0.0) <= 0.0 and e.age > 2.0 and e.get("break_t", 0.0) <= 0.0   # break_t：Boss 自己的破绽硬直（§1.5）
	# 封印（docs/61 §15 st.seal）：Boss 只是推迟出招——封印期间（已按 boss_mult / boss_max 缩到 ≤1.5 秒）不起新招，冷却照走；之后 boss_immune 秒免疫
	if ready and float(e.get("seal_t", 0.0)) > g.t:
		ready = false
	# 接潮「统一」（docs/95 §8.2 C，吸收原接潮共鸣）：两体之间的直线（b_owner 双端跟随），幽灵线 0.9 秒随两体移动、之后冻结锁定 0.6 秒、两体停步；
	# 平时由主教放（unite 9 秒，第二幕 7 秒，两体相距 120–520），主教假死时由搭档放（boss/tide_link_cd 4.5 秒，即原接潮共鸣）；占组内共用的招式令牌。
	# 第二幕（任一具过 50% 卡点）两体之间常亮一条低亮度幽灵线；假死时照旧画亮线。骑士的冰线 / 寒冷追击在 bosses/knight_boss.gd（docs/95 §4）
	var mate = e.get("partner")
	if mate != null and not mate.dead and e.type in ["bishop", "archon", "immortal"]:
		var mcoma: bool = mate.get("coma", false)
		var pair_p2: bool = int(e.get("gates_passed", 0)) >= 1 or int(mate.get("gates_passed", 0)) >= 1
		var linker: bool = mcoma or e.type == "bishop"
		if linker and (mcoma or pair_p2) and g.t >= float(e.get("link_visual_at", 0.0)):
			e.link_visual_at = g.t + 0.28
			var lc: Color = g.vfx.boss_color(e.type)
			if not mcoma:
				lc = Color(lc.r * 0.5, lc.g * 0.5, lc.b * 0.5, 0.55)   # 第二幕常亮的幽灵线：低亮度、不发光（§0.2 样式 0）
			g.fx.append({"kind": "tide_link", "a": e.pos, "b": mate.pos, "life": 0.36, "max": 0.36, "col": lc, "enemy": true})
		var dd: float = e.pos.distance_to(mate.pos)
		if ready and linker and dd >= 120.0 and dd <= 520.0 and g.t >= float(e.get("link_next_at", 0.0)):
			e.link_next_at = g.t + (Bal.v("boss/tide_link_cd", 4.5) if mcoma else (7.0 if pair_p2 else 9.0))
			unite(e, mate)
			ready = false
	# 招式令牌（docs/38 §1.10）：同一时刻只允许一个有名字的大招，接潮组两具也共用这一个名额（9/30 前误把搭档排除在外，7:00 双体大招会叠）；
	# 不在 g.bosses 里的（演练 / 图鉴）不算
	if ready and token_owner != null and not is_same(token_owner, e) and not token_owner.dead and g.t < token_until 			and g.bosses.has(token_owner):
		ready = false
	if ready and patterns.try_attack(e, dir, dist):
		ready = false
	var h = boss(e.type)
	if h != null:
		h.step(e, dt, dir, dist, ready, mate)


## 接潮「统一」一次（docs/95 §8.2 C）：两体之间 17 宽直线，幽灵线 0.9 秒双端跟随、锁定 0.6 秒冻结并让两体停步（_update_warns b_owner）；
## e.dmg × 0.55 法术、侵蚀 0.25（原接潮共鸣数值）。公共段和验收 --bossmoves 都走这里
func unite(e: Dictionary, mate: Dictionary) -> Dictionary:
	return warn(e, "line", 1.5, {"ang": (mate.pos - e.pos).angle(), "len": e.pos.distance_to(mate.pos), "wid": 17.0, "track": 0.9, "act": "tide_link", "name": "统一",
		"col": g.vfx.boss_color(e.type), "corrode": 0.25, "dmg": e.dmg * 0.55, "arts": false, "cancel_dead": true, "b_owner": mate, "lock": false})


## 远程 Boss 的迫近（协调人 9/30）：离主控超过 boss/<key>_close_min（300，0 = 关）时，每 <key>_close_cd（6）秒带直线预警冲到主控前约 140 处，
## 穿过杂兵墙进干员射程；冲刺本身无接触伤害，落地给 <key>_close_break（1）秒破绽。放了返回预警时长，没放返回 -1。伊莎玛拉二阶段、偏执泡影一阶段共用。
## 10-14（docs/95 §2.5）：它是机制不是招，dmg 0 → 预告样式 0（低亮度），和「无接触伤害」口径一致，不再和三线扫射 / 凝视抢直线
func close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	var cmin: float = Bal.v("boss/%s_close_min" % key, 300.0)
	if cmin <= 0.0 or dist <= cmin or not cd_ready(e, key + "_close", Bal.v("boss/%s_close_cd" % key, 6.0)):
		return -1.0
	var cw := warn(e, "line", 0.7, {"ang": dir.angle(), "len": clampf(dist - 140.0, 80.0, 700.0), "wid": 30.0, "track": 0.3, "act": "dash", "fit_len": true,
		"name": title, "col": col, "dmg": 0.0, "close_break": Bal.v("boss/%s_close_break" % key, 1.0)})
	return cw.dur


## ---- 每只 Boss 的行为脚本（docs/55 §6 拆分，10-10）：type → scripts/enemies/bosses/<文件>.gd；新 Boss = 加一个文件 + 在这里登记一行
## （圣徒两档共用 saint.gd）。脚本无状态（状态在敌人字典上），按 type 只实例化一次；没登记的 type 不出招（和拆分前的 match 缺省分支一样）
const SCRIPTS := {
	"iberia": "saint", "carmen": "saint", "path": "path", "bishop": "bishop", "archon": "archon", "immortal": "immortal",
	"paranoia": "paranoia", "izumik": "izumik", "knight_boss": "knight_boss", "ishar": "ishar",
}
var _bosses := {}   # type -> 脚本实例


func boss(type: String):
	var c = _bosses.get(type, false)   # 缓存里非 Boss 种类存 null；false = 还没查过
	if not (c is bool):
		return c
	var h = null
	if SCRIPTS.has(type):
		h = load("res://scripts/enemies/bosses/%s.gd" % SCRIPTS[type]).new(g)
	_bosses[type] = h
	return h


## 图鉴 / Boss 演练使用正式二阶段的完整状态，避免只改贴图标记、却还留着一阶段行为。
## 正式受击触发仍由 combat.gd 结算；此入口只用于预览场景的起始条件。
func setup_preview_phase2(e: Dictionary) -> void:
	if e.phase == 2:
		return
	var h = boss(e.type)
	if h != null:
		h.setup_preview_phase2(e)


## ---- 兼容旧调用点（combat / enemies / ishar_encounter / tests）：各 Boss 自己的入口已搬进 bosses/<type>.gd，这里只转发
func transform_ishar(e: Dictionary) -> void:
	boss("ishar").transform_ishar(e)


func _ishar_phase2(e: Dictionary, dir: Vector2, dist: float) -> void:
	boss("ishar")._ishar_phase2(e, dir, dist)


func _ishar_haste(e: Dictionary) -> float:
	return boss("ishar")._ishar_haste(e)


func _path_core(e: Dictionary) -> void:
	boss("path")._path_core(e)


func saint_interrupt(e: Dictionary) -> void:
	boss("iberia").saint_interrupt(e)


func _paranoia_p2(e: Dictionary) -> void:
	boss("paranoia")._paranoia_p2(e)


func _paranoia_aura(e: Dictionary, dist: float) -> void:
	boss("paranoia")._paranoia_aura(e, dist)


func paranoia_cocoon(e: Dictionary) -> void:
	boss("paranoia").paranoia_cocoon(e)


func _paranoia_cocoon_step(e: Dictionary, dt: float) -> void:
	boss("paranoia")._paranoia_cocoon_step(e, dt)


func paranoia_hatch(e: Dictionary, broken: bool) -> void:
	boss("paranoia").paranoia_hatch(e, broken)


func izumik_absorb(e: Dictionary) -> void:
	boss("izumik").izumik_absorb(e)


func _izumik_lamp_step(e: Dictionary, dt: float) -> void:
	boss("izumik")._izumik_lamp_step(e, dt)


func izumik_safe(e: Dictionary) -> bool:
	return boss("izumik").izumik_safe(e)


func _knight_stakes(e: Dictionary, dt: float) -> void:
	boss("knight_boss")._knight_stakes(e, dt)


## 预警 → 音效类别（docs/38 §8.11 对照表）：落地 land / 冲锋 charge / 光束 beam / 近身 melee / 全场 global
func cue_cat(w: Dictionary) -> String:
	if w.get("must_dash", false):
		return "global"
	match str(w.act):
		"dash", "stab":
			return "charge"
		"shot", "beam", "breath", "pattern_line", "ishar_line", "frost_track", "tide_link", "ishar_echo":
			return "beam"
		"bite", "sweep", "pattern_fan", "pattern_cleave", "spin_ring":
			return "melee"
	return "land"   # 落地圈、缺口环、大群之歌（song_ring：全场类的轻量版，不进全场警报）、轰击（lob）都算落地类


## Boss 招式冷却：到时返回 true 并重置
func cd_ready(e: Dictionary, key: String, dur: float) -> bool:
	if not e.has("cds"):
		e.cds = {}
	if e.cds.get(key, 0.0) <= g.t:
		e.cds[key] = g.t + dur * (SKILL_COOLDOWN_SCALE if e.boss else 1.0)
		return true
	return false



## Boss 招式预警：shape = circle / line / cone；dur 秒后结算 act
## 可选字段（docs/95 §12 底座，10-14）：
##   track_pos  "leader" / "self"：circle 在 track 秒内跟随主控 / 本体，之后冻结（叠影、寒冷）；line / cone 的 track 仍是转向追踪
##   seq_no     连发序号（1 / 2 / 3），画在预警起点 / 圈上（凝视、叠影）
##   gaps       缺口角度数组（与 gap_ang / gap_half 并存；多缺口环：大群之歌、环射）；circle 的 _warn_hit 排除缺口弧
##   slow_t / slow_mult / slow_kind  命中后移速减速（秒 / 倍率，缺省 0.7；呼号）；chill  命中后寒冷秒数（走 frost_leader，骑士）
##   b_owner    直线另一端跟随的敌人（接潮「统一」双端跟随）
##   spawn_after / spawn_r / spawn_cap / spawn_life  sweep 结算后在扇形轴线 spawn_r 处生成该敌人（分形塑路：fractal、r140、本体所属 <8、20 秒自灭；docs/95 §5.2 C）
##   cone_fx    sweep 结算时扇形里放的特效帧条（缺图只有刀光）
func warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	var w := {"shape": shape, "t": 0.0, "dur": dur, "owner": e, "pos": e.pos, "ang": 0.0, "r": 60.0, "len": 300.0, "wid": 14.0,
		"half": 0.8, "col": Color(1.0, 0.3, 0.35), "act": "", "dmg": e.dmg, "name": "", "corrode": 0.0, "done": false, "follow": false, "track": 0.0, "lock": true}
	w.merge(d, true)
	# 预警样式（docs/38 §8.11）：界面按 style 画，不再从 follow / gap_ang 猜。0 预告（无伤害，低亮度）；① 落点圈 ② 直线 ③ 扇形 ④ 缺口环 ⑤ 必须冲刺。
	# follow 只表示「圈跟着施法者走」，钻地咬击、踏地、触须爆发都是 ① —— 走出圈即可
	if not w.has("style"):
		if w.get("must_dash", false):
			w.style = 5
		elif float(w.dmg) <= 0.0:
			w.style = 0
		elif shape == "line":
			w.style = 2
		elif shape == "cone":
			w.style = 3
		elif w.has("gap_ang") or w.has("gaps") or w.act in ["song_ring", "spin_ring"]:
			w.style = 4
		else:
			w.style = 1
	if w.has("gaps") and not w.has("gap_ang"):
		w.gap_ang = float(w.gaps[0])   # 画面 / 判定都先看 gap_ang；多缺口再看 gaps
	if w.get("track_pos", "") != "" and w.track > 0.0:
		w.pos = g.combat.arena_clamp(e.pos if str(w.track_pos) == "self" else g.ppos, 90.0)
	# 时序下限（§1.9、docs/48 P0-2）：Boss 预警总时长 ≥0.6 秒；锁定（追踪结束 → 结算）≥0.4 秒，不够时缩短追踪段
	if e.boss:
		w.dur = maxf(w.dur, 0.6)
		w.track = minf(w.track, maxf(0.0, w.dur - 0.4))
	# 冲刺 / 突刺的预警线长 = 实际冲出的距离（docs/48 P0-3：原来斥亡体画 190 冲 373、塑路者画 440 冲 214）：
	# 按击退每秒衰减 900 算，距离 = v²/1800 + 本体半径（自冲不受重型削减）。fit_len：按设计线长反推速度（骑士冲锋、塑路者冲撞要真冲到位）
	if w.act in ["dash", "stab"] and shape == "line":
		if w.get("fit_len", false):
			w.spd = sqrt(1800.0 * maxf(w.len - e.r, 40.0))
		else:
			var v: float = float(w.get("spd", 600.0 if w.act == "dash" else 800.0))
			w.len = v * v / 1800.0 + e.r
		# 骑士冲锋：预先标出这一冲会不会撞上冰枪桩（画面画「破」字端盖，docs/38 §8.8）
		for st in e.get("stakes", []):
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			if Geometry2D.get_closest_point_to_segment(st.pos, w.pos, b).distance_to(st.pos) < e.r + 22.0:
				w.stake_hit = true
	# 难度缩短预警只压缩追踪段（跟着主控转向的那段），总时长至少 0.6 秒，原本就短于 0.6 的不动（docs/38 B0 第 5 项）；
	# 修正值大于 1（放宽）时整体拉长
	var wm := float(g.dmod.boss_warn)
	if wm < 1.0 and w.track > 0.0:
		var cut: float = minf(w.track * (1.0 - wm), maxf(0.0, w.dur - 0.6))
		w.track -= cut
		w.dur -= cut
	elif wm > 1.0:
		w.dur *= wm
		w.track *= wm
	g.warns.append(w)
	# 大招固定音效（docs/38 §8.11）：有名字的 Boss 招式起手播「类别起手音 + Boss 专属音色」，结算时播命中音
	if e.boss and w.name != "":
		w.cue = cue_cat(w)
		Sfx.play_cue(w.cue, e.type, "start")
	if e.boss and w.name != "":
		token_owner = e
		token_until = maxf(token_until if is_same(token_owner, e) else 0.0, g.t + w.dur + 0.6)
	if w.lock:
		e.wind = maxf(e.get("wind", 0.0), w.dur)
		e.pose = w.dur + 0.3
		e.pose_max = w.dur + 0.3
	if w.name != "":
		# 招式名进 Boss 血条的副标题行，不再头顶浮字（docs/38 §1.15，hud.gd 读 move_name / move_t）
		e["move_name"] = w.name
		e["move_t"] = g.t
		Sfx.play("skill", -12.0, 1.4)
	return w



func update_warns(dt: float) -> void:
	for w in g.warns:
		w.t += dt
		var e: Dictionary = w.owner
		if w.follow and not e.dead:
			w.pos = e.pos
		var bo = w.get("b_owner")
		if bo is Dictionary and not bo.dead and not e.dead:
			if w.t < w.track or w.track <= 0.0:
				# 双端跟随（接潮「统一」）：幽灵线段起点跟本体、终点跟另一具
				w.pos = e.pos
				w.ang = (bo.pos - e.pos).angle()
				w.len = e.pos.distance_to(bo.pos)
			elif not w.get("b_locked", false):
				# 锁定：线冻结在这一刻，两体停步到结算（docs/95 §8.2 C：线两端都在动，锁定段必须站住，画即判）
				w.b_locked = true
				var rem: float = w.dur - w.t
				e.wind = maxf(e.get("wind", 0.0), rem)
				bo.wind = maxf(bo.get("wind", 0.0), rem)
		if w.track > 0.0 and w.t < w.track:
			if w.shape != "circle" and not (bo is Dictionary):
				var want: float = (g.ppos + Vector2(0, -14) - w.pos).angle()
				w.ang = lerp_angle(w.ang, want, minf(1.0, dt * 10.0))
			elif w.get("track_pos", "") != "":
				# 落点圈追踪（叠影跟主控、寒冷跟本体）：track 秒内跟着走，之后冻结在锁定时刻的位置
				w.pos = g.combat.arena_clamp(e.pos if str(w.track_pos) == "self" else g.ppos, 90.0)
		if w.t >= w.dur and not w.done:
			w.done = true
			if not e.dead or (w.shape == "circle" and not w.get("cancel_dead", false)):
				warn_resolve(w)
	g.warns = g.warns.filter(func(w): return w.t < w.dur + 0.25)



func _warn_hit(w: Dictionary) -> bool:
	var pp: Vector2 = g.ppos + Vector2(0, -14)
	match w.shape:
		"circle":
			if g.combat.ground_d(g.ppos, w.pos) >= w.r:   # 画即判：主控脚底落在画出的椭圆里才算中（§1.9）
				return false
			return not in_gap(w, (g.ppos - w.pos).angle())   # 缺口环（长枪回旋等一次性判定）：站在缺口弧里不算中
		"line":
			var b: Vector2 = w.pos + Vector2.from_angle(w.ang) * w.len
			return Geometry2D.get_closest_point_to_segment(pp, w.pos, b).distance_to(pp) < w.wid + 12.0
		"cone":
			var dv: Vector2 = pp - w.pos
			return dv.length() < w.r + 10.0 and absf(angle_difference(dv.angle(), w.ang)) < w.half + 0.12
	return false



## 角度 a 是否落在预警 / 冲击环的缺口弧里（gap_ang + gap_half，或 gaps 数组里任一缺口）
func in_gap(w: Dictionary, a: float) -> bool:
	var gh: float = float(w.get("gap_half", 0.0))
	if gh <= 0.0:
		return false
	for ga in w.get("gaps", [w.get("gap_ang", INF)]):
		if absf(angle_difference(a, float(ga))) < gh:
			return true
	return false



func warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	if not _warn_hit(w):
		return
	var e: Dictionary = w.owner
	# 伤害来源名：Boss 的招式记 boss_<类型>，普通怪 / 精英借用预警系统的招式记 atk_<类型>（引痕者前刺、钻地咬击、踏地等；
	# 原来一律记 boss_，统计里被误算成 Boss。Boss 保护看的是 enemy_hit 的 boss 标记 = e.boss，不看这个名字）
	var dsrc: String = ("boss_" if e.boss else "atk_") + e.type
	var it: Array = ["远程", "法术"] if w.act in ["pillar", "burst", "beam", "pattern_rain", "tide_link"] else (["远程", "物理"] if w.act == "shot" else ["近战", "物理"])
	if w.get("arts", false):
		it = ["近战", "法术"]   # 伊祖米克「分享」：近战法术溅射（PRTS）
	var true_damage: bool = w.get("true", false)
	if true_damage:
		it = ["远程" if w.act in ["ishar_strike", "ishar_line", "ishar_volley", "ishar_echo"] else "近战", "真实"]
	if g.invuln <= 0.0:
		var hp_before: float = g.hp
		g.combat.enemy_hit(w.dmg, {"corrode": w.corrode, "boss": e.boss, "nerve": float(w.get("nerve", 0.0)),
			"frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "hit_cap": e.get("hit_cap", 0.0), "src_type": e.type, "warn": true}, true_damage, true, it, dsrc)   # 预警系统精英也在用（钻地咬击、踏地），按放招的敌人算
		if not e.boss and g.hp < hp_before and float(w.get("stun", 0.0)) > 0.0 and g.t >= g.combat.enemy_stun_next:
			g.combat.enemy_stun_next = g.t + 8.0
			if not g.combat.stun_as_slow():
				g.pstun = maxf(g.pstun, minf(float(w.stun), 0.25))
		if stun_t > 0.0 and not g.combat.stun_as_slow(e.boss):   # Boss 战里僵直改成减速（docs/38 §1.11）
			g.pstun = maxf(g.pstun, stun_t)
		if slow and not g.combat.atk_slow_as_slow(3.0, e.boss):   # Boss 来源不写 atk_slow，改成移速减速（docs/38 §1.11）
			g.atk_slow = 3.0
		if g.hp < hp_before:
			# 招式自带的命中附加（docs/95 §12）：移速减速 slow_t 秒（呼号 1.5 秒 −30%）/ 寒冷 chill 秒（骑士；走冰霜，受 Boss 战移速下限 0.7）
			if float(w.get("slow_t", 0.0)) > 0.0:
				g.combat.slow_leader(str(w.get("slow_kind", "boss_move")), float(w.slow_t), float(w.get("slow_mult", 0.7)))
			if float(w.get("chill", 0.0)) > 0.0:
				g.combat.frost_leader(float(w.chill), "boss")
				g.vfx.add_text(g.ppos + Vector2(0, -96), "寒冷", Color(0.65, 0.9, 1.3), 14)
			if float(w.get("corrode_amp", 0.0)) > 0.0:
				# 蚀潮吐息（docs/95 §9.2 C）：命中后 corrode_amp_t 秒内侵蚀结算伤害 ×（1 + corrode_amp），仍受 Boss 持续伤害上限（combat.drain_corrode）
				g.combat.corrode_amp_until = g.t + float(w.get("corrode_amp_t", 3.0))
				g.combat.corrode_amp_mult = 1.0 + float(w.corrode_amp)



func warn_resolve(w: Dictionary) -> void:
	var e: Dictionary = w.owner
	var c: Color = w.col
	if w.has("cue"):
		Sfx.play_cue(w.cue, e.type, "hit")
	if e.boss:
		# 预警结束后明确重新起攻击动作，而不是沿用蓄力末帧。
		e.pose = 0.35
		e.pose_max = 0.35
	# 出手事件（给画面层画攻击特效用，界面与美术读）：动作、形状、位置、朝向、范围、时刻
	e.last_act = {"act": w.act, "shape": w.shape, "pos": w.pos, "ang": w.ang, "r": w.r, "len": w.len, "wid": w.wid, "half": w.half, "t": g.t,
		"thrust": w.get("thrust", false), "name": w.name}
	if w.get("secondary", false):
		e.atk_until = g.t + 0.35
	var dv := Vector2.from_angle(w.ang)
	if str(w.act).begins_with("pattern_"):
		patterns.resolve(w)
		return
	if w.act == "tide_link" and (e.get("partner") == null or e.partner.dead):
		return
	if e.get("boss", false):
		g.vfx.boss_signature(w)
	if str(w.get("atk_fx", "")) != "":
		_atk_fx(e, w, dv)
	match w.act:
		"frost_track":
			g.fx.append({"kind": "frost_track", "a": w.pos, "b": w.pos + dv * w.len,
				"life": 1.0, "max": 1.0, "enemy": true})
			for i in 8:
				var pos: Vector2 = w.pos + dv * w.len * (float(i) + 0.5) / 8.0
				g.fx.append({"kind": "frost_step", "pos": pos, "r": 13.0, "life": 0.9, "max": 0.9, "enemy": true})
			g.vfx.fx_sprite("fx_knight_impact", w.pos + dv * w.len, g.PX * 1.2)
			g.vfx.sparks(w.pos + dv * w.len, dv, c, 10, 180.0)
			e.hunt_angle = w.ang
			e.hunt_follow_at = g.t + 0.25
			Sfx.play("hit", -9.0, 1.4)
			warn_damage(w)
		"tide_link":
			g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.55, "max": 0.55, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos + dv * w.len, g.PX * 1.2)
			Sfx.play("tentacle", -8.0, 1.1)
			warn_damage(w)
		"ishar_echo":
			g.fx.append({"kind": "tide_link", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.55, "max": 0.55, "col": c, "enemy": true})
			g.vfx.fx_sprite("fx_water_splash", w.pos, g.PX * 1.0)
			Sfx.play("tentacle", -8.0, 1.25)
			warn_damage(w)
		"extra_volley":
			var a: Dictionary = w.extra
			var count: int = mini(int(a.count), 5)
			var kind: String = D.ENEMIES[e.type].get("shot_kind", "orb")
			var speed: float = float(a.speed)
			var spread: float = float(a.spread)
			for i in count:
				if g.ebullets.size() >= 240:
					break
				var angle: float = w.ang + lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, float(count - 1)))
				g.ebullets.append({"pos": w.pos, "vel": Vector2.from_angle(angle) * speed, "dmg": w.dmg,
					"r": 5.0, "life": 2.4, "slow": false, "frost": maxf(float(e.get("frost", 0.0)), float(w.get("frost", 0.0))), "corrode": e.corrode,
					"nerve": float(w.get("nerve", 0.0)), "true": false, "kind": kind, "home": false,
					"atk": D.ENEMIES[e.type].get("atk", "法术"), "boss": false, "source_id": e.id, "no_rock": true})   # no_rock：预警类攻击不受地形阻挡
			g.fx.append({"kind": "rays", "pos": w.pos, "life": 0.25, "max": 0.25, "col": c, "enemy": true})
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
		"ishar_strike":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.45, "max": 0.45, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, c, 10, 230.0)
			Sfx.play("tentacle", -6.0, 1.2)
			g.vfx.shake_screen(0.3)
			warn_damage(w)
		"ishar_line":
			g.fx.append({"kind": "bbeam", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.28, "max": 0.28, "col": c, "wid": w.wid})
			if g.vfx.fx_sprite("fx_ishar_line_muzzle", w.pos + dv * 30.0, g.PX * 1.2, w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true   # 每条线起点的棘鳍闪光（Codex fx_ishar_line_muzzle；缺图只有光束）
			Sfx.enemy("spit", e.pos.distance_to(g.ppos))
			g.vfx.shake_screen(0.25)
			warn_damage(w)
		"song_ring":
			# 大群之歌（docs/95 §2.2 C）：以本体为心的扩散环进 g.shocks，带缺口（gaps）、扩散 ≤220px/s、真实伤害命中一次；缺口判定在 enemies.update 的冲击环循环
			g.shocks.append({"pos": w.pos, "r": w.r, "maxr": float(w.get("maxr", 600.0)), "dmg": w.dmg, "hit": false, "boss": e.boss, "src_type": e.type,
				"spd": float(w.get("spd", 220.0)), "gaps": w.get("gaps", [w.get("gap_ang", INF)]), "gap_half": float(w.get("gap_half", 0.0)),
				"true": w.get("true", false), "col": c, "owner": e})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c, "enemy": true})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.6, 1.4, 1.5), 12, 240.0)
			Sfx.play("tentacle", -6.0, 0.8)
			g.vfx.shake_screen(0.3)
		"spin_ring":
			# 长枪回旋（docs/95 §4.2 D）：静止缺口环一次性判定——主控在 r 内且不在缺口弧里才中（_warn_hit 的 circle 分支排除缺口）；
			# 环刀光按环切 8 段排布，缺口段不画
			for k in 8:
				var ka: float = w.ang + TAU * k / 8.0
				if in_gap(w, ka):
					continue
				var kp: Vector2 = w.pos + Vector2(cos(ka), sin(ka) * g.combat.GROUND_Y) * w.r * 0.8
				if not g.vfx.fx_sprite("fx_slash_heavy_steel", kp, g.PX * 1.2, ka + PI * 0.5):
					g.fx.append({"kind": "bslash", "pos": w.pos, "ang": ka, "half": 0.35, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.35, "max": 0.35, "col": c, "enemy": true})
			Sfx.play("swing", 0.0, 0.5)
			g.vfx.shake_screen(0.6)
			warn_damage(w)
		"lob":
			# 轰击（docs/95 §6.2 C，第 2 批用）：固定落点圈结算 + 1.5 秒火光（纯画面）；耗弹由放招方按 ammo_cost 处理
			if not g.vfx.fx_sprite("fx_saint_shell_burst", w.pos, g.PX * 1.5, 0.0):
				g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r * 0.8, "life": 1.5, "max": 1.5, "col": Color(c.r * 1.2, c.g * 0.8, c.b * 0.5), "enemy": true})
			g.vfx.sparks(w.pos, Vector2.UP, Color(1.6, 1.0, 0.5), 16, 280.0)
			Sfx.play("boom", -2.0, 0.9, 0.0)
			g.vfx.shake_screen(0.8)
			warn_damage(w)
		"pillar":
			g.fx.append({"kind": "wpillar", "pos": w.pos, "r": w.r, "life": 0.55, "max": 0.55, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.35, "max": 0.35, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.6, 1.2, 1.6), 14, 260.0)
			Sfx.play("tentacle", -5.0, 1.1)
			g.vfx.shake_screen(0.3)
			warn_damage(w, 0.4)
		"frost":
			# 寒冷（骑士，docs/95 §4.2 C）：结算圈 + 留 6 秒冰面（r = w.r，只减速；knight_boss.gd step）；Codex fx_knight_frost_burst 到了优先，缺图走程序冰晶
			e.frost_pos = w.pos
			e.frost_t = 6.0
			g.fx.append({"kind": "frost", "pos": w.pos, "r": w.r, "life": 6.0, "max": 6.0, "col": c})
			g.fx.append({"kind": "ring", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			if g.vfx.fx_sprite("fx_knight_frost_burst", w.pos, g.PX * 1.6, 0.0):
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.7, 1.0, 1.5), 16, 240.0)
			Sfx.play("skill", -4.0, 0.7)
			warn_damage(w)
		"slam":
			g.shocks.append({"pos": w.pos, "r": e.r, "maxr": w.r, "dmg": w.dmg, "hit": false, "boss": e.boss, "src_type": e.type})
			# 地裂（界面与美术 10-01，协调人定）：塑路者锈红、奠基者土黄暗色（起宽加粗），同干员的共用地裂画法（render/ground_crack.gd）；其他仍走旧放射线
			var gc_col = {"path": Color(0.95, 0.38, 0.22), "founder": Color(0.62, 0.46, 0.22)}.get(e.type)
			if gc_col != null:
				g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.7, "max": 0.7, "col": gc_col, "enemy": true,
					"opts": {"n": 10} if e.type == "path" else {"n": 11, "w0": Vector2(5.0, 7.0)}})
			else:
				g.fx.append({"kind": "quake", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": c})
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.8, 0.7, 0.6), 18, 300.0)
			Sfx.play("boom", 0.0, 0.6, 0.0)
			g.vfx.shake_screen(1.2)
			g.vfx.stop(0.05, "boss_slam")
		"burst":
			# 叠影每圈结算（docs/95 §1.2 C）：Codex fx_paranoia_stack（泡影从地面涌起破裂）优先，缺图走程序爆点；每圈一声「啵」按序号逐次升调
			if not (e.type == "paranoia" and g.vfx.fx_sprite("fx_paranoia_stack", w.pos, g.PX * 1.4, 0.0)):
				g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": Color(0.7, 0.35, 1.0)})
			g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.ZERO, Color(1.2, 0.6, 1.8), 12, 240.0)
			Sfx.play("boom", -8.0, 1.2 + 0.12 * float(w.get("seq_no", 1) - 1), 0.0)
			warn_damage(w)
		"shot":
			var b: Vector2 = w.pos + dv * w.len
			g.fx.append({"kind": "tracer", "a": w.pos + Vector2(0, -18), "b": b, "life": 0.35, "max": 0.35, "col": c, "wid": w.wid})
			g.vfx.sparks(w.pos + dv * 24.0, dv, c if w.get("secondary", false) else Color(2.0, 1.6, 0.8), 8, 320.0)
			Sfx.play("hit", 0.0, 0.5, 0.0)
			g.vfx.shake_screen(0.4)
			warn_damage(w)
		"beam":
			var b2: Vector2 = w.pos + dv * w.len
			g.fx.append({"kind": "bbeam", "a": w.pos + Vector2(0, -20), "b": b2, "life": 0.5, "max": 0.5, "col": c, "wid": w.wid})
			if e.type == "paranoia":
				# 凝视命中端的紫白爆点（Codex fx_paranoia_gaze_hit；缺图只有光束）：画在主控被打到的位置，没打到画在线端
				var hp: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos + Vector2(0, -14), w.pos, b2) if _warn_hit(w) else b2
				if g.vfx.fx_sprite("fx_paranoia_gaze_hit", hp, g.PX * 1.3, 0.0):
					g.fx[g.fx.size() - 1]["enemy"] = true
			Sfx.play("skill", -2.0, 0.5)
			g.vfx.shake_screen(0.7)
			warn_damage(w, 0.0, true)
		"sweep":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.3, "max": 0.3, "col": c})
			# 扇形内的喷涌特效（Codex 第 1 批：泡影呼号 fx_paranoia_howl、伊祖米克分享 fx_izumik_share；左中原点朝右，程序按扇形旋转、按 r 缩放；缺图只有刀光）
			var cone_fx: String = str(w.get("cone_fx", "fx_paranoia_howl" if w.get("howl", false) else ("fx_izumik_share" if w.get("arts", false) else "")))
			if cone_fx != "" and g.vfx.fx_sprite(cone_fx, w.pos + dv * w.r * 0.5, g.PX * clampf(w.r / 160.0, 0.8, 2.2), w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos + dv * w.r * 0.6, dv, Color(0.8, 1.4, 1.4), 12, 260.0)
			Sfx.play("swing", -2.0, 0.55)
			g.vfx.shake_screen(0.5)
			warn_damage(w, 0.25)
			if str(w.get("spawn_after", "")) != "" and not e.dead:
				_spawn_after(e, w, dv)
		"smash":
			# 炮身砸击（卡门第二幕，docs/95 §7.2 D）：落点圈结算（她在起手时已冲到圈边，saint.gd）；金色地裂 + Codex fx_carmen_smash（缺图只有地裂与尘土）
			g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": Color(1.0, 0.8, 0.35), "enemy": true, "opts": {"n": 8}})
			if g.vfx.fx_sprite("fx_carmen_smash", w.pos, g.PX * 1.4, 0.0, false, false, Color.WHITE, true):
				g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.UP, Color(1.4, 1.1, 0.6), 14, 240.0)
			Sfx.play("boom", -4.0, 1.1, 0.0)
			g.vfx.shake_screen(0.6)
			warn_damage(w)
		"breath":
			# 蚀潮吐息（蔑死体，docs/95 §9.2 C）：口部射出的腐蚀流；Codex fx_archon_breath（左中原点朝右，按线长拉伸）缺图走程序光束
			g.fx.append({"kind": "bbeam", "a": w.pos + Vector2(0, -16), "b": w.pos + dv * w.len, "life": 0.4, "max": 0.4, "col": c, "wid": w.wid, "enemy": true})
			if g.vfx.fx_sprite("fx_archon_breath", w.pos + Vector2(0, -16), g.PX * w.len / 320.0, w.ang, false, false, Color.WHITE, false, Vector2(0, 24)):
				g.fx[g.fx.size() - 1]["enemy"] = true
			Sfx.play("tentacle", -6.0, 1.3)
			g.vfx.shake_screen(0.3)
			warn_damage(w)
		"erupt":
			# 迸发（斥亡体，docs/95 §10.2 C）：以自身为心的落点圈结算；Codex fx_immortal_burst 优先，缺图走程序爆点
			if not g.vfx.fx_sprite("fx_immortal_burst", w.pos, g.PX * w.r / 60.0, 0.0, false, false, Color.WHITE, true):
				g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r, "life": 0.4, "max": 0.4, "col": c})
			g.fx[g.fx.size() - 1]["enemy"] = true
			g.vfx.sparks(w.pos, Vector2.UP, Color(0.7, 1.0, 1.5), 14, 260.0)
			Sfx.play("boom", -5.0, 1.3, 0.0)
			g.vfx.shake_screen(0.5)
			warn_damage(w)
		"leap":
			e.pos = w.pos
			e.air = 0.0
			e.erase("leap")
			# 冲击环不超过预警圆（docs/38 B0 第 5 项：原来 +40，圈外也会被打到）
			g.shocks.append({"pos": w.pos, "r": 10.0, "maxr": w.r, "dmg": w.dmg * 0.5, "hit": false, "boss": e.boss, "src_type": e.type})
			g.fx.append({"kind": "gcrack", "pos": w.pos, "r": w.r, "life": 0.6, "max": 0.6, "col": Color(0.85, 0.35, 0.95), "enemy": true, "opts": {"n": 9}})   # 地裂洋红紫（原青绿和友方撞色，界面与美术 10-01）
			g.fx.append({"kind": "explode", "pos": w.pos, "r": w.r * 0.8, "life": 0.3, "max": 0.3, "col": Color(0.5, 0.9, 0.9)})
			Sfx.play("boom", -2.0, 0.8, 0.0)
			g.vfx.shake_screen(1.0)
			warn_damage(w, 0.3)
		"dash":
			e.land_break = float(w.get("close_break", 0.0))
			e.kb = dv * w.get("spd", 600.0)
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.45
			e.pose = 0.45
			e.pose_max = 0.45
			g.vfx.sparks(e.pos, -dv, Color(0.9, 0.9, 1.0), 10, 200.0)
			Sfx.play("swing", -4.0, 0.5)
		"stab":
			e.kb = dv * w.get("spd", 800.0)
			e.kb_self = true
			e.dash_dir = dv
			e.dash_t = 0.2
			e.pose = 0.25
			e.pose_max = 0.25
			g.fx.append({"kind": "tracer", "a": w.pos, "b": w.pos + dv * w.len, "life": 0.22, "max": 0.22, "col": c, "wid": w.wid})
			Sfx.play("swing", -6.0, 0.7)
			warn_damage(w)
		"izu_wave":
			# 震撼（原全场地波）：没有缺口、覆盖全场；冲刺无敌或站在点亮的灯柱光圈里才躲得开。伤害 ≤ 最大生命 25%，减速 1.5 秒，不僵直；
			# 33% 后（w.burn > 0）命中者 4 秒持续法伤（izumik.gd _burn_step），地波环改双层
			g.fx.append({"kind": "ring", "pos": w.pos, "r": 900.0, "life": 0.7, "max": 0.7, "col": c, "enemy": true})
			if float(w.get("burn", 0.0)) > 0.0:
				g.fx.append({"kind": "ring", "pos": w.pos, "r": 760.0, "life": 0.9, "max": 0.9, "col": Color(c.r * 0.8, c.g * 1.1, c.b * 1.2), "enemy": true})
			g.fx.append({"kind": "gcrack", "pos": e.pos, "r": 170.0, "life": 0.9, "max": 0.9, "col": Color(0.9, 0.4, 1.15), "enemy": true, "opts": {"n": 12}})   # 地波源头：伊祖米克脚下大地裂（纯画面，界面与美术 10-01）
			Sfx.play("boom", -2.0, 0.5, 0.0)
			if g.invuln <= 0.0 and not izumik_safe(e):
				g.combat.enemy_hit(w.dmg, {"boss": true, "src_type": e.type}, false, true, ["远程", "法术"], "boss_" + e.type)
				g.combat.slow_leader("wave", 1.5, 0.6)
				if float(w.get("burn", 0.0)) > 0.0:
					e.burn_t = 4.0
					e.burn_dps = float(w.burn)
					e.burn_acc = 0.0
		"bite":
			g.fx.append({"kind": "bslash", "pos": w.pos, "ang": w.ang, "half": w.half, "r": w.r, "life": 0.25, "max": 0.25, "col": c})
			if w.get("thrust", false) and g.vfx.fx_sprite("fx_knight_thrust", w.pos + dv * w.r * 0.55, g.PX * 1.3, w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true   # 连刺第 3 段前刺的枪尖寒光（Codex fx_knight_thrust；缺图只有刀光）
			if w.get("mirror", false) and g.vfx.fx_sprite("fx_ishar_maw_red", w.pos + dv * w.r * 0.5, g.PX * 1.2, w.ang):
				g.fx[g.fx.size() - 1]["enemy"] = true   # 伊莎玛拉濒死强化第 2 段的红色牙光（Codex fx_ishar_maw_red）
			g.vfx.sparks(w.pos + dv * w.r * 0.65, dv, c, 6, 150.0)
			Sfx.play("swing", -6.0, 0.9)
			warn_damage(w)



## 小怪器官攻击的出手特效（docs/96 §2.2，Codex 第 2 批：收割者镰肢 fx_reaper_scythe、引痕者触须刺击 fx_tracer_thrust（狂暴 _enraged）、巢涌者触须横扫 fx_nest_sweep）：
## 帧条朝右，朝左出手时镜像（spr_rot 先镜像再转，角度减 π）；原点 = enemies.json atk_fx_origin（1x 美术像素，manifest 的 origin_1x，缺省帧中心），
## 画在本体中心偏上 0.6 r；按本体缩放（world.enemy_scale）。缺图 fx_sprite 返回 false，程序刀光照旧。纯画面，不碰随机数
func _atk_fx(e: Dictionary, w: Dictionary, dv: Vector2) -> void:
	var left: bool = dv.x < 0.0 and w.shape != "circle"
	var ang: float = 0.0 if w.shape == "circle" else (w.ang - PI if left else w.ang)
	var o: Array = w.get("atk_fx_origin", [-1, -1])
	if g.vfx.fx_sprite(str(w.atk_fx), e.pos + Vector2(0, -e.r * 0.6), D.enemy_scale(e, g.t, g.PX), ang, left, false, Color.WHITE, false, Vector2(float(o[0]), float(o[1]))):
		g.fx[g.fx.size() - 1]["enemy"] = true


## sweep 结算后的召唤（分形塑路，docs/95 §5.2 C）：不管命没命中，扇形轴线 spawn_r 处长出一只 spawn_after；本体所属的同类 ≥ spawn_cap 时不长。
## 长出来的记进 e.spawned_after（Boss 脚本按 expire_at 让它自灭）；Codex fx_path_fractal_rise（从劈痕里长出）缺图走程序光环
func _spawn_after(e: Dictionary, w: Dictionary, dv: Vector2) -> void:
	var kind: String = str(w.spawn_after)
	var n := 0
	for o in g.enemies:
		if o.type == kind and not o.dead and is_same(o.get("owner"), e):
			n += 1
	if n >= int(w.get("spawn_cap", 8)):
		return
	var at: Vector2 = g.combat.arena_clamp(w.pos + dv * float(w.get("spawn_r", 140.0)), 60.0)
	var o: Dictionary = g.spawner.spawn_enemy(kind, at)
	o.owner = e
	o.expire_at = g.t + float(w.get("spawn_life", 20.0))
	var lst: Array = e.get("spawned_after", [])
	lst.append(o)
	e["spawned_after"] = lst
	if g.vfx.fx_sprite("fx_path_fractal_rise", at, g.PX, 0.0, false, true):
		g.fx[g.fx.size() - 1]["enemy"] = true
	else:
		g.fx.append({"kind": "ring", "pos": at, "r": 26.0, "life": 0.35, "max": 0.35, "col": w.col, "enemy": true})


## 预警绘制（地面填充层；轮廓 / 出口 / 端盖在 world.draw_warn_outlines）：结算瞬间闪白。
## 填充样式按 docs/95 §0.2 全局固定，玩家看形状就知道躲法、看颜色就知道是谁放的：
## ① 落点圈 实填（主色 100%）；② 直线 斜条纹（主色 70%，条纹随结算进度流向终点）；③ 扇形 暗填 + 亮边（45% 填充、外弧 130% 亮）；
## ④ 缺口环 空心（只画线、无填充）；0 预告 低亮度（25%，不发光）；⑤ 必须冲刺 同 ①（屏幕级提示在 HUD）
func draw_warns() -> void:
	for w in g.warns:
		if w.get("dim", false):
			continue   # 打不到主控的杂兵预警只画淡轮廓（world.classify_tells / draw_warn_outlines，可读性 1.1.1，界面与美术）
		var k: float = clampf(w.t / w.dur, 0.0, 1.0)
		var c: Color = w.col
		var pulse: float = 0.5 + 0.5 * sin(g.t * 14.0)
		var fa := 0.10 + 0.14 * k
		var oa := 0.55 + 0.35 * pulse * k
		var st: int = int(w.get("style", 1))
		if w.done:
			var f: float = clampf(1.0 - (w.t - w.dur) / 0.25, 0.0, 1.0)
			c = Color(2.0, 2.0, 2.0)
			fa = 0.45 * f
			oa = 0.9 * f
			k = 1.0
		# 颜色不再乘 1.7–2.0：乘完在灯光里褪成白色 / 粉彩，色相丢失（docs/48 全局 ④）；亮度靠 alpha 和白芯（world.draw_warn_outlines）
		if st == 0:
			# 预告（如注亡拟嗣生成点、迫近）：没有伤害，压低亮度，别和伤害圈抢眼
			fa *= 0.25
			oa *= 0.45
		elif st == 2:
			fa *= 0.7
		elif st == 3:
			fa *= 0.45
		fa *= g.world.tell_fill   # 后期降噪（render/declutter tell_fill_k，缺省 1）：填充减淡、轮廓（world.draw_warn_outlines）加粗
		var fill := Color(c.r, c.g, c.b, fa * 1.3)
		var line := Color(c.r, c.g, c.b, oa)
		var bright := Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, oa)
		match w.shape:
			"circle":
				g.draw_set_transform(w.pos, 0.0, Vector2(1.0, g.combat.GROUND_Y))
				if st == 4 and not w.done:
					# ④ 空心环：只画线；进度用一圈从内向外长的细环表示
					g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 48, line, 2.5)
					g.draw_arc(Vector2.ZERO, maxf(2.0, w.r * k), 0.0, TAU, 40, Color(c.r, c.g, c.b, oa * 0.5), 1.5)
				else:
					g.draw_circle(Vector2.ZERO, w.r, fill)
					g.draw_circle(Vector2.ZERO, w.r * k, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
					g.draw_arc(Vector2.ZERO, w.r, 0.0, TAU, 40, line, 2.5)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"line":
				g.draw_set_transform(w.pos, w.ang, Vector2.ONE)
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), fill)
				if st == 2 and not w.done:
					# ② 斜条纹：间距 28，随结算进度向终点流动；总数按线长封顶（820 长约 30 条）
					var sc := Color(c.r, c.g, c.b, fa * 1.4)
					var off: float = fmod(k * 140.0 + g.t * 40.0, 28.0)
					var x: float = off - w.wid
					while x < w.len:
						g.draw_line(Vector2(x, -w.wid), Vector2(x + w.wid, w.wid), sc, 3.0)
						x += 28.0
				else:
					g.draw_rect(Rect2(0.0, -w.wid * k, w.len, w.wid * 2.0 * k), Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * 1.6))
				g.draw_rect(Rect2(0.0, -w.wid, w.len, w.wid * 2.0), line, false, 2.0)
				g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"cone":
				var pts := PackedVector2Array([w.pos])
				var pts2 := PackedVector2Array([w.pos])
				for q in 17:
					var a: float = w.ang - w.half + w.half * 2.0 * q / 16.0
					var dv := Vector2.from_angle(a)
					pts.append(w.pos + dv * w.r)
					pts2.append(w.pos + dv * w.r * k)
				g.draw_colored_polygon(pts, fill)
				if k > 0.05:
					g.draw_colored_polygon(pts2, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, fa * (1.0 if st == 3 else 1.6)))
				pts.append(w.pos)
				g.draw_polyline(pts, line, 2.5)
				if st == 3 and not w.done:
					g.draw_arc(w.pos, w.r, w.ang - w.half, w.ang + w.half, 20, bright, 3.5)   # ③ 亮边：外弧 130% 亮
		# 连发序号（凝视 1 / 2 / 3、叠影圈号）：circle 画在圈心上方，line / cone 画在起点
		var sq: int = int(w.get("seq_no", 0))
		if sq > 0 and not w.done:
			var sp: Vector2 = w.pos + (Vector2(0, -w.r * g.combat.GROUND_Y - 18.0) if w.shape == "circle" else Vector2.from_angle(w.ang) * 26.0 + Vector2(0, -22.0))
			g.draw_circle(sp, 9.0, Color(0.02, 0.02, 0.05, 0.8))
			g.draw_arc(sp, 9.0, 0.0, TAU, 16, Color(1, 1, 1, 0.9), 1.5)
			UI.text(g, g.font, sp + Vector2(-9.0, 5.0), str(sq), 12, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER, 18.0)


## 旧名转发（docs/101 S6，2026-10-15 改公开名）：tests/ 与未合入的分支还在调旧名，各分支合完后删
func _boss_ai(e: Dictionary, dt: float, dir: Vector2, dist: float) -> void:
	boss_step(e, dt, dir, dist)

func _close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	return close_in(e, dir, dist, key, title, col)

func _cd(e: Dictionary, key: String, dur: float) -> bool:
	return cd_ready(e, key, dur)

func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	return warn(e, shape, dur, d)

func _update_warns(dt: float) -> void:
	update_warns(dt)

func _warn_damage(w: Dictionary, stun_t := 0.0, slow := false) -> void:
	warn_damage(w, stun_t, slow)

func _warn_resolve(w: Dictionary) -> void:
	warn_resolve(w)

func _draw_warns() -> void:
	draw_warns()
