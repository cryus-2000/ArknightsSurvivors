extends "res://themes/deep_sea/mech/mech_tide_zone.gd"
## 萨米主题机制 · 风雪缩圈 + 圈外寒冷 / 冻结（docs/394 §8，用户 11-20 定，替代水月黑潮的圈外直接掉血）。
## 缩圈日程照水月黑潮（mech_tide_zone 的 _zone_schedule：150 秒起、Boss 在场暂停、最终 Boss 冻结成场地），只换横幅措辞；
## 圈外不直接掉血，改成每人一份寒冷值 0–100：涨满冻结 1.75 秒（不能动 / 攻击 / 技能 / 冲刺 / 终结技，按位置掉血），解冻后 3 秒免疫。
## 数值全读 themes/sami/data/mechanics.json cold。只做队长；出击队友的寒冷（§8.3）未做。
## 冰系敌人的加值（cold_add / cold_aura / cold_pulse）经 add_cold() 进同一个量表（mech_foes 调）；Boss 来源最多加到 boss_cap（90）。

const MJ := "res://themes/sami/data/mechanics.json"
var C: Dictionary = {}
var cold := 0.0          # 队长寒冷值 0–100（HUD / 机器人读）
var immune := 0.0        # 解冻后免疫剩余秒
var _txt_t := 0.0
var freezes := 0         # 本局冻结次数（遥测）


func _init(game) -> void:
	super(game)
	var f := FileAccess.open(MJ, FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			C = d.get("cold", {})


func _v(path: String, dflt: float) -> float:
	var cur = C
	for k in path.split("/"):
		if not (cur is Dictionary) or not cur.has(k):
			return dflt
		cur = cur[k]
	return float(cur) if (cur is float or cur is int) else dflt


## 主题机制挂钩：game._update_player 每帧（同黑潮的调用位置）
func on_player_tick(dt: float) -> void:
	var live: bool = g.zone_frozen or _zone_schedule(dt)
	if g.state != g.S.PLAY:
		return
	immune = maxf(0.0, immune - dt)
	var out: float = (g.ppos.distance_to(g.zone_c) - g.zone_r) if live and g.zone_state != 0 else -1.0
	var outside: bool = out > 0.0 and not g.squad.in_sanctuary(g.ppos)
	var ph: float = float(maxi(zone_phase, 0))
	if g.frozen_t > 0.0:
		g.frozen_t = maxf(0.0, g.frozen_t - dt)
		if not outside and C.get("thaw", {}).get("in_ring_ends_freeze", true) and _froze_out:
			g.frozen_t = 0.0   # 回圈立即解冻（§8.2）
		var dps: float = _v("freeze/dps_k", 1.3) * (2.5 + 1.5 * (ph if outside else 0.0)) * (1.0 + (minf(out / 300.0, 1.0) if outside else 0.0))
		g.combat.lose_hp(dps * dt, "cold")
		if g.frozen_t <= 0.0:
			cold = _v("freeze/reset_to", 0.0)
			immune = _v("thaw/immune", 3.0)
	elif outside:
		zone_out_t += dt
		if immune <= 0.0:
			var gain: float = _v("gain_out/base", 20.0) * (1.0 + _v("gain_out/phase_k", 0.15) * ph) * (1.0 + _v("gain_out/depth_k", 1.0) * minf(out / _v("gain_out/depth_px", 300.0), 1.0))
			add_cold(gain * dt, false, true)
		_txt_t -= dt
		if _txt_t <= 0.0:
			_txt_t = 1.2
			g.vfx.add_text(g.ppos + Vector2(0, -84), "寒冷", Color(0.65, 0.85, 1.0), 15)
	else:
		zone_out_t = 0.0
		cold = maxf(0.0, cold - _v("decay_in/per_sec", 50.0) * dt)
	# 减速：移速 × (1 − 0.5 × 寒冷值 / 100)，与其他控制减速合计封顶 −50%
	var want: float = 1.0 - _v("slow/max", 0.5) * cold / 100.0
	var other: float = maxf(0.05, g.combat.ctrl_slow())
	g.cold_move = maxf(want, minf(1.0, 0.5 / other)) if cold > 0.0 else 1.0


var _froze_out := false


## 加寒冷值（圈外上涨 / 冰系敌人命中）：boss = Boss 来源（最多加到 boss_cap，单独冻不住人）
func add_cold(v: float, boss := false, zone := false) -> void:
	if v <= 0.0 or g.frozen_t > 0.0 or immune > 0.0 or g.state != g.S.PLAY:
		return
	var cap: float = _v("enemy_src/boss_cap", 90.0) if boss else _v("max", 100.0)
	if boss and cold >= cap:
		return
	cold = minf(cold + v, cap)
	if cold >= _v("freeze/at", 100.0):
		_freeze(zone)


func _freeze(zone: bool) -> void:
	g.frozen_t = _v("freeze/dur", 1.75)
	_froze_out = zone
	freezes += 1
	g.dash_t = 0.0
	cold = _v("max", 100.0)
	g.hurt_flash = maxf(g.hurt_flash, 0.12)
	g.head_bar_t = 2.0
	g.vfx.add_text(g.ppos + Vector2(0, -96), "冻结", Color(0.75, 0.92, 1.0), 18)
	if g.mech("fx") == null:   # 萨米 mech_fx 在：冻结画成冰壳（mech_fx.cold_draw），不画通用细圈（协调人 11-26）
		g.fx.append({"kind": "ring", "pos": g.ppos, "r": 34.0, "life": g.frozen_t, "max": g.frozen_t, "col": Color(0.7, 0.9, 1.0)})
	Sfx.play("skill", -6.0, 0.6)


## 净化类：清寒冷、解冻（§8.5）
func cleanse() -> void:
	cold = 0.0
	if g.frozen_t > 0.0:
		g.frozen_t = 0.0
		immune = _v("thaw/immune", 3.0)


## 缩圈日程：照黑潮，只换横幅措辞（banner 在父类里写死「黑潮」，这里整段复写）
func _zone_schedule(dt: float) -> bool:
	if g.zone_state == 0:
		if g.t < ZONE_START:
			return false
		g.zone_c = g.ppos
		g.zone_r = ZONE_RADII[0] + 400.0
		zone_phase = -1
		g.zone_state = 3
		g.zone_t = 0.0
	var paused: bool = g.spawner.boss_alive()
	if paused != zone_paused:
		zone_paused = paused
		if g.zone_state != 3 or zone_phase >= 0:
			g.vfx.show_banner("Boss 在场：风雪暂歇" if paused else "风雪再起")
	if not paused:
		g.zone_t += dt
	match g.zone_state:
		3:
			if g.zone_t >= (0.0 if zone_phase < 0 else 45.0) and zone_phase < ZONE_RADII.size() - 1:
				zone_phase += 1
				g.zone_next_r = ZONE_RADII[zone_phase]
				var off := Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(0.0, (g.zone_r - g.zone_next_r) * 0.7)
				g.zone_next_c = g.zone_c + off
				g.zone_state = 1
				g.zone_t = 0.0
				g.vfx.show_banner("风雪将至：%d 秒后安全区缩小" % 20)
				Sfx.play("roar", -6.0, 0.5, 0.0)
		1:
			if g.zone_t >= 20.0:
				g.zone_state = 2
				g.zone_t = 0.0
				zone_from_c = g.zone_c
				zone_from_r = g.zone_r
				g.vfx.show_banner("风雪正在逼近！")
		2:
			var k := clampf(g.zone_t / 25.0, 0.0, 1.0)
			g.zone_c = zone_from_c.lerp(g.zone_next_c, k)
			g.zone_r = lerpf(zone_from_r, g.zone_next_r, k)
			if k >= 1.0:
				g.zone_state = 3
				g.zone_t = 0.0
	return true


## 寒冷条占位画法：队长脚下一段弧（寒冷值 / 100）
func draw_ground(w) -> void:
	if cold <= 0.0 and g.frozen_t <= 0.0:
		return
	var fxm = g.mech("fx")
	if fxm != null and fxm.has_method("cold_draw"):
		fxm.cold_draw(cold, g.frozen_t)   # 萨米：连续霜带弧 + 冻结冰壳（不画细弧 / 半透明圆）
		return
	var cv = g.wcv
	var p: Vector2 = g.ppos + Vector2(0, 14)
	var k: float = cold / 100.0
	cv.draw_arc(p, 22.0, -PI * 0.5, -PI * 0.5 + TAU * k, 24, Color(0.7, 0.9, 1.0, 0.85), 3.0)
	if g.frozen_t > 0.0:
		cv.draw_circle(p + Vector2(0, -14), 20.0, Color(0.75, 0.92, 1.0, 0.35))


## 机器人：寒冷值已经很高时更想回圈（父类缩圈打分之外再扣）
func bot_score(q: Vector2, s: float) -> float:
	s = super(q, s)
	if g.zone_state != 0 and cold > 40.0 and q.distance_to(g.zone_c) > g.zone_r:
		s -= cold * 0.3
	return s
