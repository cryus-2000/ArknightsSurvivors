## 哈兰杜汗（khan）与路加萨尔古斯（lion）（结局四 终始，双 Boss）：docs/393 §13 重写（用户 11-25 重点）+ §11.8 招式 + §12.4 威慑下限。
## 整只的读法：鞭、刻度、沙、两支军队。阶段按两王合计生命：
##   一幕「对峙」（>66%）：轮流单打。主攻王追人出整套招，牵制王退回自己的营地（西 = 哈兰、东 = 路加）只放小件；
##       主攻 9 秒后蓄大招（征服 / 敕令，r240，2.8 秒），牵制王起身走来接手 = 借刀；砸完换手。
##   二幕「分兵」（66–33%）：两王都上场，哈兰压近、路加控场（离队长 300–420）；合击「影下冲阵」「沙漏鞭笞」；每 15 秒双大招互瞄对方。
##   三幕「两军」（<33%）：开幕「两军」对冲一次；流沙河；新合招「对决」（每 12 秒，两王相向冲锋 460、撞后沙浪、后仰 1.5 秒）。
##   决胜：一王倒下 → 3 秒定格演出（剩下那位无敌、停手、致意），之后移速 100、冷却 ×0.6、受伤 ×0.7，大招改瞄队长；终局大招每 15 秒（4.5 秒蓄力、r440）；
##       倒下那位跪在原地，剩下那位的弹绕开他（r60）。
## 主轴「借刀」（docs/392 §15.4 A）：大招圈先画在队长身上，以 90 px/秒慢慢追队长（比走路慢），落定前 0.7 秒锁定——把圈牵到另一个王身上再跑出去；
##   砸中另一个王：晕眩 4 秒、受伤 ×2.0；两王平时受伤 ×0.6（「王者护卫」）。
## 配乐钩子（音频接，docs/393 §13.7）：_music("swap", 主攻王) / ("both") / ("fall") / ("decisive", 胜者) / ("end")；有 g.music.twin_event 就调，否则写 g 的 meta twin_music。
## 画面全部占位（营地、随从、沙河、门扉都只画简单图形），正式特效交 fx-declutter。
extends "res://scripts/enemies/bosses/sami/sami_boss.gd"

const CAMP_DX := 380.0
const ULT_R := 240.0
const ULT_DUR := 2.8
const ULT_LOCK := 0.7
const DRAG_SPD := 130.0   # 11-26 测试台：90 时 2 秒多只能拖 190，够不到牵制王
const STUN_T := 4.0
const GUARD := 0.2         # 平时受伤（王者护卫；§15.4 A 原拟 0.6，11-26 测试台多轮后下调）
const WINDOW := 3.0        # 被砸中窗口的总受伤倍率（§15.4 A 原拟 2.0）


func _khan(e: Dictionary) -> bool:
	return e.type == "khan"


func _nm(e: Dictionary) -> String:
	return "khan" if _khan(e) else "lion"


func mate_of(e: Dictionary):
	var want: String = str(D.ENEMIES[e.type].get("twin", ""))
	if e.has("twin_id"):
		var m = g.enemies_sys.by_id(int(e.twin_id))
		if m != null and not m.dead:
			return m
		return null
	for m in g.enemies:
		if not m.dead and m.type == want:
			e["twin_id"] = int(m.id)
			return m
	return null


## 两王共用的状态（存在 g 的 meta 上，按这场的哈兰 id 区分）
func _ctl(e: Dictionary) -> Dictionary:
	var key: int = int(e.id) if _khan(e) else int(e.get("twin_id", e.id))
	var c = g.get_meta("twin_ctl") if g.has_meta("twin_ctl") else null
	if not (c is Dictionary) or int(c.get("key", -1)) != key:
		c = {"key": key, "start": g.t, "attacker": "khan", "swap_t": g.t + 3.0 + 9.0, "phase": 0, "fall": {}, "combo_t": g.t + 6.0, "combo_i": 0,
			"double_t": 0.0, "duel_t": 0.0, "armies_done": false, "river": {}, "decisive_t": -1.0}
		g.set_meta("twin_ctl", c)
	return c


func _music(ev: String, who := "") -> void:
	var mu = g.get("music")
	if mu != null and mu.has_method("twin_event"):
		mu.twin_event(ev, who)
	else:
		g.set_meta("twin_music", [ev, who, g.t])


func _camp(e: Dictionary) -> Vector2:
	return center(e) + Vector2(-CAMP_DX if _khan(e) else CAMP_DX, 0.0)


func _phase(e: Dictionary, m) -> int:
	var hp: float = maxf(0.0, float(e.hp))
	var mx: float = float(e.maxhp)
	if m != null:
		hp += maxf(0.0, float(m.hp))
		mx += float(m.maxhp)
	var f: float = hp / maxf(1.0, mx)
	return 0 if f > 0.66 else (1 if f > 0.33 else 2)


## 主攻 / 牵制 / 都上场 / 单打
func _role(e: Dictionary, c: Dictionary, m) -> String:
	if m == null:
		return "solo"
	if int(c.phase) == 0:
		return "attack" if str(c.attacker) == _nm(e) else "support"
	return "close" if _khan(e) else "field"


func step(e: Dictionary, dt: float, dir: Vector2, dist: float, ready: bool, _mate) -> void:
	tick(e, dt)
	if _khan(e):
		ambient(e, dt, "sand")
	var c := _ctl(e)
	var m = mate_of(e)
	if _khan(e) or m == null or m.dead:
		c.phase = _phase(e, m)
	# 一王倒下：定格演出 3 秒，之后决胜
	if e.has("twin_id") and m == null and not e.get("decisive", false):
		if c.fall.is_empty():
			_on_fall(e, c)
		if g.t >= float(c.decisive_t):
			_go_decisive(e)
		else:
			e.invuln = true
			e.pos = e.get("hold_pos", e.pos)
			return
	if e.get("decisive", false):
		e.invuln = false
		_deflect(e, c)
	if g.t < float(c.start) + 3.0:
		_intro(e, c)
		return
	var role := _role(e, c, m)
	e["role"] = role
	if m != null:
		e["mate_last_pos"] = m.pos
	_tick_ult(e, c, m, dt)
	if float(e.get("duel_lock", 0.0)) > g.t:
		e.pos = e.get("hold_pos", e.pos)
	else:
		_tick_pos(e, c, m, role, dt)
	_tick_fervor(e)
	if role == "attack" and g.t >= float(c.swap_t) and not e.has("ult"):
		_start_ult(e, m, "drag")
		return
	if _khan(e):
		_director(e, c, m)
		_tick_river(e, c, dt)
	_tick_dial(e)
	_tick_hourglass(e)
	if e.has("ult") or e.get("duel_lock", 0.0) > g.t:
		return
	if role == "support":
		_support(e)
		return
	if role == "solo" and g.t >= float(e.get("final_t", 0.0)) and float(e.get("final_t", 0.0)) > 0.0:
		_final_ult(e)
		return
	pick(e, ready, dir, dist)
	if _khan(e) and role != "support" and dist > 380.0 and g.t >= float(e.get("ride_t", 0.0)):
		e.ride_t = g.t + 7.0
		w_stab(e, (g.ppos - e.pos).angle(), 460.0, 34.0, 0.7, 0.10, "", {"track": 0.2, "fit_len": true})   # 纵马（不算招）


## ---- 开场：两王从营地冲到场中撞一次，各退回（3 秒，不出招）
func _intro(e: Dictionary, c: Dictionary) -> void:
	var el: float = g.t - float(c.start)
	var cp: Vector2 = center(e)
	var camp: Vector2 = _camp(e)
	var mid: Vector2 = cp + (camp - cp).normalized() * 30.0
	var p: Vector2
	if el < 1.2:
		p = camp.lerp(mid, el / 1.2)
	elif el < 1.4:
		p = mid
		if not e.get("intro_hit", false) and _khan(e):
			e.intro_hit = true
			g.vfx.shake_screen(0.3)
			g.fx.append({"kind": "ring", "pos": cp, "r": 160.0, "life": 0.5, "max": 0.5, "col": Color(0.95, 0.85, 0.6)})
	else:
		p = mid.lerp(cp + (camp - cp).normalized() * 150.0, clampf((el - 1.4) / 0.8, 0.0, 1.0))
	e.pos = p
	e.hold_pos = p
	e.invuln = true
	if el >= 2.9:
		e.invuln = false


## ---- 站位：牵制王回营地、面朝主攻王；路加控场时离队长 300–420；两王相距 <200 互相推开
func _tick_pos(e: Dictionary, c: Dictionary, m, role: String, dt: float) -> void:
	var want = null
	if e.has("walk_to"):
		want = e.walk_to
	elif role == "support":
		want = _camp(e)
	elif role == "field":
		var d: float = e.pos.distance_to(g.ppos)
		if d < 300.0:
			want = g.ppos + (e.pos - g.ppos).normalized() * 340.0
		elif d > 420.0:
			want = g.ppos + (e.pos - g.ppos).normalized() * 380.0
	if want != null:
		var hp: Vector2 = e.get("hold_pos", e.pos)
		hp += ((want as Vector2) - hp).limit_length(float(e.spd) * 1.6 * dt)
		e.hold_pos = g.combat.arena_clamp(hp, 40.0)
		e.pos = e.hold_pos
	else:
		e.hold_pos = e.pos
	if m != null and e.pos.distance_to(m.pos) < 200.0 and g.t >= float(e.get("shove_t", 0.0)):
		e.shove_t = g.t + 1.0
		e.kb = (e.pos - m.pos).normalized() * 220.0


## ---- 大招（征服 / 敕令）：mode = drag（圈先画在队长身上，以 90 px/秒追队长，落定前 0.7 秒锁定）/ mate（画在另一个王脚下、跟着他）/ leader（决胜：瞄队长）
func _start_ult(e: Dictionary, m, mode: String) -> void:
	var nm: String = "征服" if _khan(e) else "敕令"
	if e.get("decisive", false):
		nm = "决胜·" + nm
	var p: Vector2 = g.ppos if mode != "mate" or m == null else m.pos
	var dur: float = ULT_DUR if not e.get("decisive", false) else 1.8 + ULT_LOCK
	var w := w_circle(e, p, ULT_R, dur, 0.30, nm, {"lock": true})
	e["ult"] = {"w": w, "mode": mode, "t0": g.t, "dur": dur}
	pose(e, dur)
	e.channel = dur
	if m != null and mode == "drag":
		m["walk_to"] = e.pos + ((m.pos as Vector2) - e.pos).normalized() * 280.0   # 牵制王起身走来接手，停在离施放者 280 处（不理主轴时圈砸不到他）
	w.cb = func(ww): _ult_land(e, ww)


func _tick_ult(e: Dictionary, _c: Dictionary, m, dt: float) -> void:
	var u = e.get("ult")
	if not (u is Dictionary):
		return
	var w: Dictionary = u.w
	var left: float = float(u.dur) - (g.t - float(u.t0))
	if left > ULT_LOCK:
		match str(u.mode):
			"drag":
				w.pos = (w.pos as Vector2) + (g.ppos - (w.pos as Vector2)).limit_length(DRAG_SPD * dt)
			"mate":
				if m != null:
					w.pos = m.pos
	if left <= -0.3:
		e.erase("ult")
		if m != null:
			m.erase("walk_to")


func _ult_land(e: Dictionary, w: Dictionary) -> void:
	var c := _ctl(e)
	var m = mate_of(e)
	var hit := false
	if m != null and (m.pos as Vector2).distance_to(w.pos) < float(w.r) + float(m.r) * 0.5:
		hit = true
		var st: float = STUN_T if str(e.get("ult", {}).get("mode", "")) != "mate" else 1.5   # 二幕双大招互瞄是白给的窗口，缩到 1.5 秒
		g.combat.start_break(m, st)
		vuln(m, st, WINDOW / GUARD / maxf(0.01, Bal.v("boss/break_mult", 1.4)))
		m.erase("walk_to")
	if e.get("decisive", false):
		vuln(e, 1.5, 1.5)
		# 带对方的标志（只改画面）：哈兰砸地多一道金色光柱，路加落下多一圈暗红鞭痕
		g.fx.append({"kind": "ring", "pos": w.pos, "r": float(w.r) * 0.6, "life": 0.8, "max": 0.8,
			"col": Color(1.0, 0.85, 0.3) if _khan(e) else Color(0.75, 0.2, 0.18)})
	if int(c.phase) == 0 and str(c.attacker) == _nm(e) and m != null:
		c.attacker = _nm(m)
		c.swap_t = g.t + (STUN_T + 8.5 if hit else 9.0)
		_music("swap", str(c.attacker))
	if str(e.get("ult", {}).get("mode", "")) == "mate":
		e.duel_lock = g.t + 0.5


## ---- 牵制王只放小件（一次 1 个图案、弹体可见半径 ≤12）
func _support(e: Dictionary) -> void:
	if g.t < float(e.get("small_t", 0.0)):
		return
	e.small_t = g.t + 2.0
	if _khan(e):
		var a: float = (g.ppos - e.pos).angle()
		for k in 5:
			shot(e, e.pos, a + (k - 2) * 0.06, 260.0, 1, 0.10, {"life": 3.0})   # 鞭梢单发
	else:
		ring(e, e.pos, 24, 150.0, 1, 0.10, [(g.ppos - e.pos).angle()], 0.0, {"hold": 0.6, "life": 4.0})   # 历盘小件


## ---- 二 / 三幕导演（只在哈兰的 step 里跑）
func _director(e: Dictionary, c: Dictionary, m) -> void:
	if m == null or e.has("ult"):
		return
	var ph: int = int(c.phase)
	if ph == 1:
		if g.t >= float(c.double_t) and float(c.double_t) > 0.0 and not m.has("ult"):
			c.double_t = g.t + 15.0
			_start_ult(e, m, "mate")
			_start_ult(m, e, "mate")
			e.walk_to = m.pos
			m.walk_to = e.pos
			_music("both")
			return
		if float(c.double_t) <= 0.0:
			c.double_t = g.t + 8.0
		if g.t >= float(c.combo_t):
			c.combo_t = g.t + 8.0
			c.combo_i = int(c.combo_i) + 1
			if int(c.combo_i) % 2 == 1:
				_dial(m, Vector2.ZERO, 0.0)
				later(e, 1.5, func(): _cavalry(e, Vector2.ZERO, 0.0))
			else:
				_hourglass(m, Vector2.ZERO, 0.0)
				later(e, 0.8, func(): _lash3(e, Vector2.ZERO, 0.0))
	elif ph == 2:
		if not c.armies_done:
			c.armies_done = true
			_armies(e)
			c.duel_t = g.t + 6.0
			return
		if g.t >= float(c.duel_t):
			c.duel_t = g.t + 12.0
			_duel(e, m)
		if c.river.is_empty() or g.t > float(c.river.get("until", 0.0)) + 8.0:
			_sand_river(e, m)
		if g.t >= float(c.swap_t) and not m.has("ult"):
			c.swap_t = g.t + 15.0
			var caster = e if int(c.combo_i) % 2 == 0 else m
			c.combo_i = int(c.combo_i) + 1
			_start_ult(caster, e if caster == m else m, "drag")


func moves(e: Dictionary) -> Array:
	var c := _ctl(e)
	var role := str(e.get("role", "attack"))
	if role == "solo":
		if _khan(e):
			return [["天途", 10.0, 0.0, 9999.0, _skyway], ["鞭扫", 4.0, 0.0, 9999.0, _sweep], ["鞭梢", 6.0, 0.0, 9999.0, _whip_tip]]
		return [["万历", 10.0, 0.0, 9999.0, _myriad], ["瞬身", 8.0, 0.0, 9999.0, _blink], ["历盘", 8.0, 0.0, 9999.0, _dial_ring]]
	var ph: int = int(c.phase)
	if _khan(e):
		if ph == 0:
			return [["鞭扫", 4.0, 0.0, 9999.0, _sweep], ["鞭梢", 6.0, 0.0, 9999.0, _whip_tip]]
		if ph == 1:
			return [["战意鞭笞", 9.0, 0.0, 9999.0, _lash3], ["鞭扫", 4.0, 0.0, 9999.0, _sweep], ["鞭梢", 6.0, 0.0, 9999.0, _whip_tip]]
		return [["鞭影", 7.0, 0.0, 9999.0, _shadow_whip], ["鞭扫", 4.0, 0.0, 9999.0, _sweep], ["鞭梢", 6.0, 0.0, 9999.0, _whip_tip]]
	if ph == 0:
		return [["历盘", 8.0, 0.0, 9999.0, _dial_ring], ["瞬身", 8.0, 0.0, 9999.0, _blink], ["王令", 10.0, 0.0, 9999.0, _edict]]
	if ph == 1:
		return [["历盘", 8.0, 0.0, 9999.0, _dial_ring], ["王令", 10.0, 0.0, 9999.0, _edict]]
	return [["逆历", 9.0, 0.0, 9999.0, _reverse], ["历盘", 8.0, 0.0, 9999.0, _dial_ring], ["瞬身", 8.0, 0.0, 9999.0, _blink]]


func all_moves(e: Dictionary) -> Array:
	var a: Array
	if _khan(e):
		a = [["鞭扫", 4.0, 0.0, 9999.0, _sweep], ["鞭梢", 6.0, 0.0, 9999.0, _whip_tip], ["可汗冲阵", 12.0, 0.0, 9999.0, _cavalry], ["战意鞭笞", 9.0, 0.0, 9999.0, _lash3],
			["鞭影", 7.0, 0.0, 9999.0, _shadow_whip], ["天途", 10.0, 0.0, 9999.0, _skyway], ["两军", 12.0, 0.0, 9999.0, _m_armies], ["流沙", 14.0, 0.0, 9999.0, _m_river],
			["对决", 12.0, 0.0, 9999.0, _m_duel], ["征服", 12.0, 0.0, 9999.0, _m_ult]]
	else:
		a = [["历盘", 8.0, 0.0, 9999.0, _dial_ring], ["瞬身", 8.0, 0.0, 9999.0, _blink], ["王令", 10.0, 0.0, 9999.0, _edict], ["日晷", 11.0, 0.0, 9999.0, _dial],
			["沙漏", 10.0, 0.0, 9999.0, _hourglass], ["逆历", 9.0, 0.0, 9999.0, _reverse], ["万历", 10.0, 0.0, 9999.0, _myriad], ["敕令", 12.0, 0.0, 9999.0, _m_ult]]
	return a


func _m_ult(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_start_ult(e, mate_of(e), "drag")
	return ULT_DUR


func _m_armies(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_armies(e)
	return 1.5


func _m_river(e: Dictionary, _dir: Vector2, _d: float) -> float:
	_sand_river(e, mate_of(e))
	return 1.0


func _m_duel(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var m = mate_of(e)
	if m == null:
		return -1.0
	_duel(e, m)
	return 3.0


## ---- 主轴收益（docs/392 §15.4 A）：平时 ×0.6；决胜 ×0.7
func base_taken(e: Dictionary) -> float:
	if e.get("decisive", false):
		return float(D.ENEMIES[e.type].get("decisive", {}).get("taken", 0.7))
	return GUARD


## 先倒下的王不掉额外奖励（docs/393 §8 第 7 条，enemies.json first_down_reward false）
func on_lethal(e: Dictionary) -> bool:
	if not bool(D.ENEMIES[e.type].get("first_down_reward", true)) and mate_of(e) != null:
		e.xp = 0.0
	return false


## 哈兰【战意】：每打中队长一次 +1 层（最多 10），4 秒没打中清零；战意鞭笞的间隔随层数缩短
func on_hit_leader(e: Dictionary) -> void:
	if not _khan(e):
		return
	e["fervor"] = mini(10, int(e.get("fervor", 0)) + 1)
	e["fervor_t"] = g.t


func _tick_fervor(e: Dictionary) -> void:
	if int(e.get("fervor", 0)) > 0 and g.t - float(e.get("fervor_t", 0.0)) > 4.0:
		e.fervor = 0


## ---- 一王倒下（docs/393 §13.5）
func _on_fall(e: Dictionary, c: Dictionary) -> void:
	var fallen_pos: Vector2 = e.get("mate_last_pos", e.pos)
	c.fall = {"pos": fallen_pos, "who": "lion" if _khan(e) else "khan", "t0": g.t}
	c.decisive_t = g.t + 3.0
	e.hold_pos = e.pos
	e.sq = []
	e.erase("ult")
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
	for b in g.ebullets:
		if int(b.get("source_id", -1)) == int(e.id):
			b.life = 0.0
	g.vfx.stop(0.15, "twin_fall")
	_music("fall")


func _go_decisive(e: Dictionary) -> void:
	e.decisive = true
	e.invuln = false
	var dc: Dictionary = D.ENEMIES[e.type].get("decisive", {})
	e.spd = float(dc.get("spd", 100.0))
	e.cd_k = float(dc.get("cd_k", 0.6))
	e.final_t = g.t + 6.0
	g.vfx.shake_screen(0.3)
	g.vfx.add_alert(e.pos + Vector2(0, -50), "决胜", col(e), 18)
	_music("decisive", _nm(e))


## 剩下那位的弹绕开倒下那位（r60）
func _deflect(e: Dictionary, c: Dictionary) -> void:
	if c.fall.is_empty():
		return
	var fp: Vector2 = c.fall.pos
	for b in g.ebullets:
		if b.life > 0.0 and int(b.get("source_id", -1)) == int(e.id):
			var d: Vector2 = b.pos - fp
			if d.length() < 60.0:
				b.pos = fp + d.normalized() * 60.0
				var t: Vector2 = d.orthogonal().normalized()
				if t.dot(b.vel) < 0.0:
					t = -t
				b.vel = t * b.vel.length()


## 终局大招（决胜每 15 秒）：蓄力 4.5 秒、r440 画在队长身上；锁定 (440 + 12) / 105 + 0.1 ≈ 4.4 秒，任何方向都能走出去
func _final_ult(e: Dictionary) -> void:
	e.final_t = g.t + 15.0
	var w := w_circle(e, g.ppos, 440.0, 4.5, 0.30, "决胜·" + ("征服" if _khan(e) else "敕令"))
	e.channel = 4.5
	e["ult"] = {"w": w, "mode": "leader", "t0": g.t, "dur": 4.5}
	w.cb = func(ww): _ult_land(e, ww)


## ---- 哈兰的招
## 鞭扫：120°、r260，只伤外缘弧带（内圈 100 安全）
func _sweep(e: Dictionary, dir: Vector2, _d: float) -> float:
	var w := w_cone(e, dir.angle(), PI / 3.0, 260.0, 1.4, 0.16, "鞭扫", {"track": 0.3, "inner_r": 100.0, "skin": "ice_field", "arena_center": e.pos, "arena_radius": 99999.0})
	pose(e, 1.4)
	w.cb = func(ww): _fx("whip", e.pos, float(ww.ang), PI / 3.0)
	return 1.6


## 鞭梢：长鞭直线抽出 620（半宽 20，0.8 / 0.4），再沿 S 形曲线甩回
func _whip_tip(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos + g.pvel.limit_length(150.0) * 0.25 - e.pos).angle()
	var w := w_line(e, a, 620.0, 20.0, 0.8, 0.15, "鞭梢", {"track": 0.4})
	pose(e, 0.8)
	w.cb = func(ww):
		_fx("lash", e.pos, float(ww.ang), 620.0)
		var tip: Vector2 = e.pos + Vector2.from_angle(float(ww.ang)) * 620.0
		var nrm: Vector2 = Vector2.from_angle(float(ww.ang)).orthogonal()
		for k in 8:
			var u: float = float(k + 1) / 9.0
			var p: Vector2 = tip.lerp(e.pos, u) + nrm * sin(u * TAU) * 90.0
			later(e, 0.05 * k, func(): w_circle(e, p, 22.0, 0.6, 0.15, "", {"lock": false}))
	return 1.6


## 可汗冲阵：4 骑可汗片影并排冲过场地（每骑半宽 26，全长 1280），骑与骑之间的缝是路
func _cavalry(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	var nrm: Vector2 = Vector2.from_angle(a).orthogonal()
	var shift: float = float((int(g.t * 10.0) % 3) - 1) * 40.0
	var first := true
	for off in [-165.0, -55.0, 55.0, 165.0]:
		var p: Vector2 = g.ppos - Vector2.from_angle(a) * 640.0 + nrm * (off + shift)
		var w := w_line(e, a, 1280.0, 26.0, 1.0, 0.18, "可汗冲阵" if first else "", {"lock": first})
		w.pos = p
		w.cb = func(ww): _fx("rider", ww.pos, float(ww.ang), 1280.0)
		first = false
	pose(e, 1.0)
	return 1.4


## 战意鞭笞：连抽 3 鞭（50°、r220），左右交替，战意越高越快（间隔 0.8 → 0.6）
func _lash3(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var gap: float = lerpf(0.8, 0.6, clampf(float(e.get("fervor", 0)) / 10.0, 0.0, 1.0))
	for k in 3:
		later(e, gap * k, func():
			var a: float = (g.ppos - e.pos).angle() + (0.4 if k % 2 == 0 else -0.4)
			var w := w_cone(e, a, deg_to_rad(25.0), 220.0, 0.8, 0.14, "战意鞭笞" if k == 0 else "", {"lock": k == 0})
			pose(e, 0.8)
			w.cb = func(ww):
				_fx("whip", e.pos, float(ww.ang), deg_to_rad(25.0))
				fan(e, e.pos, float(ww.ang), deg_to_rad(25.0), 7, 230.0, 1, 0.08, {"life": 2.5}))
	return 0.8 + gap * 3.0


## 鞭影：两个片影站在哈兰两侧，跟着他同步抽鞭（各 90°、r200）
func _shadow_whip(e: Dictionary, dir: Vector2, _d: float) -> float:
	var a: float = dir.angle()
	var nrm: Vector2 = Vector2.from_angle(a).orthogonal()
	var first := true
	for s in [-1.0, 1.0]:
		var w := w_cone(e, a, PI / 4.0, 200.0, 1.1, 0.16, "鞭影" if first else "", {"lock": first})
		w.follow = false
		w.pos = e.pos + nrm * 110.0 * s
		w.cb = func(ww): _fx("shade", ww.pos, float(ww.ang), PI / 4.0)
		first = false
	var w0 := w_cone(e, a, PI / 4.0, 200.0, 1.1, 0.16, "", {"lock": false})
	w0.cb = func(ww): _fx("whip", e.pos, float(ww.ang), PI / 4.0)
	pose(e, 1.1)
	return 1.4


## 天途（决胜）：哈兰带着片影排成 V 字冲锋（主线半宽 30，0.8 / 0.5），片影向两翼展开
func _skyway(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	w_stab(e, a, 520.0, 30.0, 0.8, 0.20, "天途", {"track": 0.3, "fit_len": true})
	pose(e, 0.8)
	for s in [-1.0, 1.0]:
		for k in 2:
			var w := w_line(e, a + s * (0.35 + 0.15 * k), 480.0, 24.0, 0.8, 0.14, "", {"lock": false})
			w.pos = e.pos + Vector2.from_angle(a + s * PI * 0.5) * 60.0 * (k + 1)
			w.cb = func(ww): _fx("rider", ww.pos, float(ww.ang), 480.0)
	return 1.6


## ---- 路加的招
## 历盘：24 枚短刻度排成刻度盘向外扩（r80 → 660），出口是「时针」那一格，每 0.5 秒跳一格（4 圈依次放，缺口每圈跳一格）
func _dial_ring(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle()
	e.move_name = "历盘"
	e.move_t = g.t
	pose(e, 0.0)
	_fx("flash", e.pos, 0.0, PI)
	for k in 6:
		var ga: float = a0 + TAU / 24.0 * k
		later(e, 0.5 * k, func():
			for i in 24:
				var a: float = TAU * i / 24.0
				if absf(angle_difference(a, ga)) < TAU / 48.0 + 0.01:
					continue
				_lion_shot(e, e.pos + Vector2.from_angle(a) * 80.0, a, 160.0, 1, 0.13, {"hold": 0.5, "life": 3.8}))
	return 2.4


## 路加放的弹记下发射点（逆历要倒放）
func _lion_shot(e: Dictionary, pos: Vector2, a: float, spd: float, tier: int, pct: float, o := {}) -> void:
	var n0: int = g.ebullets.size()
	shot(e, pos, a, spd, tier, pct, o)
	if g.ebullets.size() > n0:
		if not e.has("my_shots"):
			e["my_shots"] = []
		e.my_shots.append([g.ebullets[g.ebullets.size() - 1], pos])
		if e.my_shots.size() > 120:
			e.my_shots.pop_front()


## 瞬身：沿直线瞬移 400 穿过队长所在线（半宽 30），留下下陷的沙痕 2 秒（减速）
func _blink(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a: float = (g.ppos - e.pos).angle()
	var from: Vector2 = e.pos
	var w := w_line(e, a, 400.0, 30.0, 0.8, 0.18, "瞬身", {"track": 0.3})
	pose(e, 0.8)
	w.cb = func(ww):
		_fx("flash", from, float(ww.ang), 0.8)
		var to: Vector2 = g.combat.arena_clamp(from + Vector2.from_angle(float(ww.ang)) * 400.0, 60.0)
		e["trail"] = {"a": from, "b": to, "until": g.t + 2.0}
		e.pos = to
		e.hold_pos = to
	return 1.1


## 王令：绕着路加的 2 只王者友伴依次扑向队长（扑击 420、半宽 26）
func _edict(e: Dictionary, _dir: Vector2, _d: float) -> float:
	for k in 2:
		later(e, 0.5 * k, func():
			var src: Vector2 = e.pos + Vector2.from_angle(TAU * k / 2.0 + g.t) * 60.0
			var w := w_line(e, (g.ppos - src).angle(), 420.0, 26.0, 0.8, 0.14, "王令" if k == 0 else "", {"lock": k == 0, "track": 0.3})
			w.pos = src
			w.cb = func(ww): _fx("beast", ww.pos, float(ww.ang), 420.0))
	pose(e, 0.8)
	return 1.6


## 日晷：场中立一根晷针（光柱），影子绕着转（30°/秒，转 180°，影长 400，影尖线速 ≤210）；绕到晷针另一侧就安全
func _dial(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var pin: Vector2 = g.ppos.lerp(center(e), 0.5)
	var a0: float = (g.ppos - pin).angle() - PI * 0.5
	var w := w_line(e, a0, 400.0, 20.0, 1.0, 0.0, "日晷", {"lock": true})
	w.pos = pin
	e["sundial"] = {"pin": pin, "a0": a0, "t0": g.t + 1.0, "hit_t": 0.0}
	pose(e, 1.0)
	return 1.6


func _tick_dial(e: Dictionary) -> void:
	var sd = e.get("sundial")
	if not (sd is Dictionary) or g.t < float(sd.t0):
		return
	var el: float = g.t - float(sd.t0)
	if el > 6.0:
		e.erase("sundial")
		return
	var a: float = float(sd.a0) + deg_to_rad(30.0) * el
	sd["a"] = a
	var b: Vector2 = sd.pin + Vector2.from_angle(a) * 400.0
	if g.t >= float(sd.hit_t) and Geometry2D.get_closest_point_to_segment(g.ppos, sd.pin, b).distance_to(g.ppos) < 32.0:
		sd.hit_t = g.t + 1.5
		hit_now(e, g.ppos, 1.0, 0.12)
	# 沙痕减速（瞬身留下的）
	var tr = e.get("trail")
	if tr is Dictionary:
		if g.t > float(tr.until):
			e.erase("trail")
		elif Geometry2D.get_closest_point_to_segment(g.ppos, tr.a, tr.b).distance_to(g.ppos) < 30.0:
			g.combat.slow_leader("lion_trail", 0.3, 0.7)


## 沙漏：以路加为腰，上下两个三角（高 460）：先上半落沙（1.2），沙再流到下半（晚 1.0 秒）
func _hourglass(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var axis: Vector2 = (g.ppos - e.pos).normalized()
	if axis.length() < 0.5:
		axis = Vector2.DOWN
	var waist: Vector2 = e.pos
	var tris: Array = []
	for s in [1.0, -1.0]:
		var tip_c: Vector2 = waist + axis * 460.0 * s
		var nrm: Vector2 = axis.orthogonal() * 230.0
		tris.append(PackedVector2Array([waist, tip_c + nrm, tip_c - nrm]))
	e.move_name = "沙漏"
	e.move_t = g.t
	e["hourglass"] = {"tris": tris, "t": [g.t + 1.2, g.t + 2.2], "done": [false, false]}
	pose(e, 1.2)
	return 2.4


func _tick_hourglass(e: Dictionary) -> void:
	var hg = e.get("hourglass")
	if not (hg is Dictionary):
		return
	for i in 2:
		if not hg.done[i] and g.t >= float(hg.t[i]):
			hg.done[i] = true
			if Geometry2D.is_point_in_polygon(g.ppos, hg.tris[i]):
				hit_now(e, g.ppos, 1.0, 0.14)
	if hg.done[1] and g.t > float(hg.t[1]) + 0.3:
		e.erase("hourglass")


## 逆历：场上路加放过的弹全部倒着飞回发射点（0.6 秒闪一下）
func _reverse(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var live: Array = e.get("my_shots", []).filter(func(x): return x[0].life > 0.0)
	if live.size() < 3:
		return -1.0
	e.move_name = "逆历"
	e.move_t = g.t
	w_self(e, 50.0, 0.6, 0.0, "")
	pose(e, 0.6)
	later(e, 0.6, func():
		_fx("flash", e.pos, 0.0, PI)
		for x2 in e.get("my_shots", []):
			if x2[0].life > 0.0:
				_fx("rewind", x2[0].pos, 0.0, 0.0)
		for x in e.get("my_shots", []):
			var b: Dictionary = x[0]
			if b.life <= 0.0:
				continue
			var back: Vector2 = (x[1] as Vector2) - b.pos
			var sp: float = maxf(140.0, b.vel.length())
			b.vel = back.normalized() * sp
			b.life = back.length() / sp + 0.1
		e.my_shots = [])
	return 1.2


## 万历（决胜）：以路加为心分 12 个钟面扇区，每次 4 区（相隔 90°）结算，每 0.8 秒顺时针跳一格，共 6 跳
func _myriad(e: Dictionary, _dir: Vector2, _d: float) -> float:
	var a0: float = (g.ppos - e.pos).angle()
	for j in 6:
		for q in 4:
			var a: float = a0 + TAU / 12.0 * j + PI * 0.5 * q + TAU / 24.0
			var w := w_cone(e, a, TAU / 24.0, 660.0, 0.8 + 0.8 * j, 0.12, "万历" if j == 0 and q == 0 else "", {"lock": j == 0 and q == 0})
			w.follow = false
	return 1.2 + 0.8 * 6


## ---- 双王合招
## 两军：片影和王者友伴从场两侧对冲，交汇线（过队长、半宽 30）一齐结算
func _armies(e: Dictionary) -> void:
	var c: Vector2 = center(e)
	var w := w_line(e, PI * 0.5, 1200.0, 30.0, 1.0, 0.15, "两军", {"lock": false})
	w.pos = Vector2(g.ppos.x, c.y - 600.0)
	e["armies"] = {"x": g.ppos.x, "t0": g.t, "t1": g.t + 1.0}


## 流沙：两王之间连出一条弯曲的沙河（宽 100），在河里被冲向下游（40 px/秒，下游 = 哈兰那端）、每秒 3%
func _sand_river(e: Dictionary, m) -> void:
	if m == null:
		return
	var c := _ctl(e)
	var a: Vector2 = m.pos
	var b: Vector2 = e.pos
	var pts: Array = []
	var nrm: Vector2 = (b - a).orthogonal().normalized()
	for k in 9:
		var u: float = float(k) / 8.0
		pts.append(a.lerp(b, u) + nrm * sin(u * PI * 2.0) * 90.0)
	c.river = {"pts": pts, "t0": g.t + 1.0, "until": g.t + 7.0, "tick": 0.0}
	e.move_name = "流沙"
	e.move_t = g.t
	for p in pts:
		w_circle(e, p, 50.0, 1.0, 0.0, "", {"lock": false})


func _tick_river(e: Dictionary, c: Dictionary, dt: float) -> void:
	var rv: Dictionary = c.river
	if rv.is_empty() or g.t < float(rv.t0) or g.t > float(rv.until):
		return
	var pts: Array = rv.pts
	for k in pts.size() - 1:
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(g.ppos, pts[k], pts[k + 1])
		if q.distance_to(g.ppos) < 50.0:
			g.ppos += ((pts[k + 1] as Vector2) - (pts[k] as Vector2)).normalized() * 40.0 * dt
			rv.tick = float(rv.tick) - dt
			if rv.tick <= 0.0:
				rv.tick = 0.5
				hit_now(e, g.ppos, 1.0, 0.015)
			break


## 对决（三幕合招，每 12 秒）：交汇点 = 起手时队长位置；两王闪到两侧各 460 停 1.2 秒，相向冲锋（约 900 px/秒），
## 相撞处炸开沙浪（外扩 200 px/秒到 r380，缺口 2 个开在冲锋线垂直方向）；撞完两王后仰 1.5 秒受伤 ×1.3
func _duel(e: Dictionary, m) -> void:
	var x: Vector2 = g.combat.arena_clamp(g.ppos, 120.0)
	var a: float = (e.pos - m.pos).angle()
	var pk: Vector2 = g.combat.arena_clamp(x + Vector2.from_angle(a) * 460.0, 30.0)
	var pl: Vector2 = g.combat.arena_clamp(x - Vector2.from_angle(a) * 460.0, 30.0)
	e.pos = pk
	e.hold_pos = pk
	m.pos = pl
	m.hold_pos = pl
	e.duel_lock = g.t + 2.4
	m.duel_lock = g.t + 2.4
	e.move_name = "对决"
	e.move_t = g.t
	var w1 := w_line(e, (x - pk).angle(), 470.0, 40.0, 1.2, 0.20, "对决", {"lock": true})
	w1.pos = pk
	var w2 := w_line(m, (x - pl).angle(), 470.0, 40.0, 1.2, 0.20, "", {"lock": true})
	w2.pos = pl
	var gaps: Array = [a + PI * 0.5, a - PI * 0.5]
	w_circle(e, x, 380.0, 1.2, 0.0, "", {"lock": false, "gaps": gaps, "gap_half": 0.3})
	later(e, 1.2, func():
		e.pos = x + Vector2.from_angle(a) * 30.0
		m.pos = x - Vector2.from_angle(a) * 30.0
		e.hold_pos = e.pos
		m.hold_pos = m.pos
		g.vfx.shake_screen(0.3)
		ring(e, x, 56, 200.0, 2, 0.15, gaps, 0.0, {"life": 1.9})
		vuln(e, 1.5, 1.3 / GUARD)
		vuln(m, 1.5, 1.3 / GUARD)
		g.combat.start_break(e, 1.5)
		g.combat.start_break(m, 1.5))


func draw(e: Dictionary, cv) -> void:
	var fxm = g.mech("fx")
	if fxm != null:
		fxm.final_draw(e)   # 营地旗 / 刻度石、沙河、沙痕、日晷、沙漏、两军（docs/401 §18）
		return
	var c := _ctl(e)
	if _khan(e):
		var cp: Vector2 = center(e)
		cv.draw_rect(Rect2(cp + Vector2(-CAMP_DX - 6, -40), Vector2(12, 40)), Color(0.6, 0.15, 0.12, 0.9))   # 马鬃旗
		cv.draw_rect(Rect2(cp + Vector2(CAMP_DX - 10, -20), Vector2(20, 20)), Color(0.95, 0.8, 0.35, 0.9))   # 刻度石
		var rv: Dictionary = c.river
		if not rv.is_empty() and g.t <= float(rv.until):
			cv.draw_polyline(PackedVector2Array(rv.pts), Color(0.85, 0.75, 0.5, 0.45), 100.0)
		if not c.fall.is_empty():
			cv.draw_circle(c.fall.pos, 24.0, Color(0.75, 0.68, 0.52, 0.85))   # 倒下那位跪在原地（沙色）
			cv.draw_arc(c.fall.pos, 60.0, 0.0, TAU, 24, Color(0.9, 0.85, 0.7, 0.35), 2.0)
	if e.get("role", "") != "" and str(e.role) in ["attack", "close", "field", "solo"]:
		cv.draw_arc(e.pos, float(e.r) + 8.0, 0.0, TAU, 24, col(e), 2.0)
	var sd = e.get("sundial")
	if sd is Dictionary and sd.has("a"):
		cv.draw_circle(sd.pin, 10.0, Color(1.0, 0.9, 0.5, 0.9))
		cv.draw_line(sd.pin, sd.pin + Vector2.from_angle(float(sd.a)) * 400.0, Color(0.2, 0.15, 0.1, 0.6), 20.0)
	var hg = e.get("hourglass")
	if hg is Dictionary:
		for i in 2:
			if not hg.done[i]:
				cv.draw_colored_polygon(hg.tris[i], Color(0.95, 0.8, 0.4, 0.18 if i == 0 else 0.1))
	var tr = e.get("trail")
	if tr is Dictionary:
		cv.draw_line(tr.a, tr.b, Color(0.6, 0.5, 0.3, 0.5), 40.0)
	var ar = e.get("armies")
	if ar is Dictionary and g.t < float(ar.t1) + 0.3:
		var k: float = clampf((g.t - float(ar.t0)) / 1.0, 0.0, 1.0)
		var cp2: Vector2 = center(e)
		for i in 6:
			var y: float = cp2.y - 300.0 + 120.0 * i
			cv.draw_circle(Vector2(lerpf(cp2.x - 600.0, float(ar.x), k), y), 14.0, Color(0.6, 0.15, 0.12, 0.8))
			cv.draw_circle(Vector2(lerpf(cp2.x + 600.0, float(ar.x), k), y), 14.0, Color(0.95, 0.8, 0.35, 0.8))


## 机器人主轴（借刀，§15.4 A）：谁在蓄大招（圈跟着队长慢慢走），就跑到另一个王身后（圈会被拖过他），锁定前离开圈
func axis_do(e: Dictionary, p: Vector2) -> Vector2:
	var u = e.get("ult")
	if not (u is Dictionary) or str(u.mode) != "drag":
		return Vector2.INF
	var m = mate_of(e)
	if m == null:
		return Vector2.INF
	var w: Dictionary = u.w
	var left: float = float(u.dur) - (g.t - float(u.t0))
	if left > ULT_LOCK + 0.2:
		var beyond: Vector2 = m.pos + ((m.pos as Vector2) - (w.pos as Vector2)).normalized() * 120.0
		return go_to(p, beyond, 20.0)
	return (p - (w.pos as Vector2)).normalized()


## 不理主轴：蓄力时贴着施放者（圈拖在施放者身边，砸不到另一个王）
func axis_ignore(e: Dictionary, p: Vector2) -> Vector2:
	var u = e.get("ult")
	if not (u is Dictionary) or str(u.mode) != "drag":
		return Vector2.INF
	var left: float = float(u.dur) - (g.t - float(u.t0))
	if left > ULT_LOCK + 0.2:
		return go_to(p, e.pos, 60.0)
	return (p - (u.w.pos as Vector2)).normalized()
