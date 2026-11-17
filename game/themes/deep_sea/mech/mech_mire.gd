extends "res://scripts/core/theme_mechanic.gd"
## 水月主题机制 · 溟痕（docs/49d、147、155、docs/364 §2）：自然溟痕刷新、灯火退散 / 逼近、站在溟痕里减速掉血累积神经损伤、
## 怪物留痕与淡出。溟痕列表仍存在 g.mires / g.in_mire / g.next_mire（画面、灯标、Boss 招式读写），地图参数仍在 map.json 的 mire 段。
## 本文件的函数体从 run/enemies.gd（update_status 溟痕段、lamp_mire_k、_lamp_mire、_lamp_hint）、run/spawner.gd（刷新段）、
## run/combat.gd（add_enemy_mire、fade_mire）原样搬来，随机数调用次数与顺序不变。

const Bal = preload("res://scripts/core/balance.gd")
const Game = preload("res://scripts/game.gd")
var g: Game
var mire_tick := 0.0
var lamp_band := 0         # 灯火与溟痕（docs/147）提示用的档：0 通明（≥ mire_hi）/ 1 中段 / 2 暗淡（< mire_lo），带回差
var lamp_hint_t := -INF    # 上一次灯火提示的时间（lamp/mire_hint_cd 内不重复）


func _init(game: Game) -> void:
	g = game


## 原 enemies.update_status 的溟痕段：减速 + 屏幕变暗 + 持续掉血；巢涌光环与神经损伤也在这里结算（返回 true）
func on_status_tick(dt: float) -> bool:
	var mired := false
	var mire_nat := false   # 站在自然溟痕里（不是 Boss 子弹留下的）：这一跳不算 Boss 来源
	var sanct: bool = g.squad.in_sanctuary(g.ppos)   # 流明灯塔：区内溟痕失效
	var lk: Vector2 = lamp_mire_k()
	_lamp_hint()
	var mire_full: bool = lk.y > 0.0 and g.map.mire_area_full()   # 自然溟痕总面积到上限：逼近只挪不长（enemy/mire_area_cap）
	for m in g.mires:
		# 溟痕常驻、只能净化（用户 10-24）；Boss 溟痕是招式残留，照旧按 life 到期。life <= 0 = 移除标记
		if m.get("boss", false):
			m.life -= dt
		if m.life <= 0.0:
			continue
		if m.has("fade"):
			m.fade -= dt   # 淡出中（docs/155）：不伤人、不长、不随灯火变化，到 0 移除
			if m.fade <= 0.0:
				m.life = 0.0
			continue
		if not m.get("boss", false) and (lk.x > 0.0 or lk.y > 0.0):
			_lamp_mire(m, lk, dt, mire_full)
			if m.life <= 0.0:
				continue
		m.r = min(m.maxr, m.r + 5.0 * dt)
		if g.combat.ground_d(g.ppos, m.pos) < m.r and not sanct:
			mired = true
			if not m.get("boss", false):
				mire_nat = true
	# 溟痕：减速 + 屏幕变暗 + 持续掉血；神经损伤在溟痕里累积（combat，Boss与怪物 419c84d）
	g.in_mire = move_toward(g.in_mire, 1.0 if mired else 0.0, dt * (4.0 if mired else 2.5))
	g.enemies_sys.update_nest_aura(dt, sanct)
	var ward: float = 1.0 - Bal.v("lamp/mire_ward_dmg", 0.8) * lk.x if mire_nat else 1.0   # 灯火高：自然溟痕伤害 / 神经损伤减免（docs/147）
	g.afflict.update_nerve(dt, mired, sanct, ward, mired and not mire_nat)   # 神经损伤：站在溟痕里累积（combat.gd）
	if mired:
		# 溟痕侵蚀：每 0.5 秒结算一次（3 + 1.5% 最大生命），带飘字与轻微红闪
		mire_tick -= dt
		if mire_tick <= 0.0:
			mire_tick = 0.5
			# 自然溟痕每跳（0.5 秒）：enemy/mire_flat + 最大生命 × enemy/mire_pct，再乘难度修正 mire_dmg（缺省 3 + 1.5%）；
			# 只踩在 Boss 溟痕里时每跳 boss/mire_pct 1%（每秒 2%，不再有固定 +3，docs/38 §1.7）
			var md: float = ((Bal.v("enemy/mire_flat", 3.0) + g.max_hp * Bal.v("enemy/mire_pct", 0.015)) * float(g.dmod.get("mire_dmg", 1.0)) * ward) if mire_nat else g.max_hp * Bal.v("boss/mire_pct", 0.01)
			md = g.combat.lose_hp(md, "mire", not mire_nat)
			if md >= 1.0:   # Boss 溟痕这一跳被持续伤害上限截到不足 1 点时不闪、不飘「-0」（自然溟痕每跳 ≥3，照旧）
				g.red_flash = maxf(g.red_flash, 0.08)
				g.hp_shake = 0.2
				g.hurt_flash = maxf(g.hurt_flash, 0.06)
				g.vfx.add_text(g.ppos + Vector2(randf_range(-10, 10), -80), "-%d 溟痕" % int(md), Color(0.85, 0.45, 1.0), 15)
		g.head_bar_t = maxf(g.head_bar_t, 0.6)
	else:
		mire_tick = 0.0
	g.mires = g.mires.filter(func(m): return m.life > 0.0)
	return true


## 原 spawner.update 的自然溟痕刷新段
func on_spawn_tick() -> void:
	# 溟痕：先照常采样，再排除最终 Boss 禁生成区域，区域外仍可生成。
	if g.t >= g.next_mire:
		# 溟痕随时间越来越多、越来越大；缩圈后多出现在圈边
		# 灯火低（docs/147）：间隔 × (1 − mire_spawn_iv × y)、离队长的距离 × (1 − mire_spawn_near × y)，随机数抽取次数不变
		var ly: float = lamp_mire_k().y
		g.next_mire = g.t + g.map.mire_next_interval(g.t) * (1.0 - Bal.v("lamp/mire_spawn_iv", 0.4) * ly)
		var mp := g.ppos + Vector2.from_angle(g.rng_spawn.randf() * TAU) * g.rng_spawn.randf_range(160.0, 380.0) * (1.0 - Bal.v("lamp/mire_spawn_near", 0.4) * ly)
		if g.zone_state != 0 and g.rng_spawn.randf() < 0.6:
			var ang := (g.ppos - g.zone_c).angle() + g.rng_spawn.randf_range(-0.8, 0.8)
			mp = g.zone_c + Vector2.from_angle(ang) * (g.zone_r - g.rng_spawn.randf_range(20.0, 120.0))
		# 只和自然溟痕比上限（docs/155：原来和怪物留痕共用总数，拖痕把名额占满后全图不再刷新）；
		# 满了就淡出离队长最远、且超过 enemy/mire_recycle_d 的一片自然溟痕再刷新的，溟痕跟着队长走而不是定格
		var nat: Array = g.mires.filter(func(x): return not x.has("src") and not x.get("boss", false) and x.life > 0.0 and not x.has("fade"))
		var room: bool = nat.size() < int(g.map.mire_cfg().get("max_count", 24))
		if not room:
			var far = null
			var far_d: float = Bal.v("enemy/mire_recycle_d", 520.0)
			for x in nat:
				var xd: float = x.pos.distance_to(g.ppos)
				if xd > far_d:
					far_d = xd
					far = x
			if far != null:
				fade_mire(far)
				room = true
		if room:
			# 总面积到 enemy/mire_area_cap 就跳过这次（先照常 mire_new 消耗随机数，保证不开上限时随机序列不变）
			var mire: Dictionary = g.map.mire_new(mp, g.t, true)
			if g.map.mire_area_full():
				mire.life = 0.0
			if mire.life > 0.0 and not g.combat.mire_blocked(mire.pos, float(mire.maxr)):
				mire["t0"] = g.t
				g.mires.append(mire)


## 灯火与溟痕（docs/147，用户 10-25 方案 B）：x = 退散强度（灯火 lamp/mire_lo → mire_hi 线性 0 → 1），y = 逼近强度（灯火 mire_lo → 0 线性 0 → 1）。
## 两个都是 0 时（lamp/mire_ward_r 与 mire_creep_r 都为 0）等于改动前
func lamp_mire_k() -> Vector2:
	var lo: float = Bal.v("lamp/mire_lo", 30.0)
	var hi: float = Bal.v("lamp/mire_hi", 70.0)
	var x: float = clampf((g.lamp - lo) / maxf(1.0, hi - lo), 0.0, 1.0) if Bal.v("lamp/mire_ward_r", 200.0) > 0.0 else 0.0
	var y: float = clampf((lo - g.lamp) / maxf(1.0, lo), 0.0, 1.0) if Bal.v("lamp/mire_creep_r", 380.0) > 0.0 else 0.0
	return Vector2(x, y)


## 一片自然溟痕随灯火变化（每帧，Boss 溟痕不参与）：
##   退散：边缘进入队长 lamp/mire_ward_r 内的溟痕每秒收缩 mire_recede × x（上限一并压低，不再长回），小于 10 就消失（不闪，慢慢褪）；
##   逼近：中心在 lamp/mire_creep_r 内的溟痕每秒朝队长挪 mire_creep_spd × y、上限长 mire_creep_grow × y（最多原上限 × mire_creep_cap）；
##   挪进最终 Boss 禁生成区或点燃灯标的禁刷区时不挪；中心离队长不到半径一半就不再挪（盖住队长后不跟着走）
func _lamp_mire(m: Dictionary, lk: Vector2, dt: float, full := false) -> void:
	var d: float = m.pos.distance_to(g.ppos)
	if lk.x > 0.0 and d < Bal.v("lamp/mire_ward_r", 200.0) + m.r and g.t - float(m.get("t0", -INF)) >= Bal.v("lamp/mire_ward_grace", 3.0):
		m.maxr = maxf(0.0, minf(float(m.maxr), float(m.r)) - Bal.v("lamp/mire_recede", 10.0) * lk.x * dt)
		m.r = m.maxr
		if m.r < 10.0:
			m.life = 0.0
		return
	if lk.y > 0.0 and d < Bal.v("lamp/mire_creep_r", 380.0) and d > float(m.r) * 0.5:
		if not m.has("maxr0"):
			m["maxr0"] = float(m.maxr)
		var np: Vector2 = m.pos.move_toward(g.ppos, Bal.v("lamp/mire_creep_spd", 14.0) * lk.y * dt)
		if not g.combat.mire_blocked(np, float(m.maxr)) and not g.beacon_sys.blocks(np):
			m.pos = np
		if not full:   # 自然溟痕总面积到 enemy/mire_area_cap 时不再长（用户 10-29「溟痕不能无限扩张」）
			m.maxr = minf(float(m.maxr) + Bal.v("lamp/mire_creep_grow", 6.0) * lk.y * dt, float(m.maxr0) * Bal.v("lamp/mire_creep_cap", 1.3))


## 灯火进出通明 / 暗淡档时在队长头上给一行小字（不用横幅；lamp/mire_hint_cd 秒内不重复；带 5 点回差）
func _lamp_hint() -> void:
	if Bal.v("lamp/mire_ward_r", 200.0) <= 0.0 and Bal.v("lamp/mire_creep_r", 380.0) <= 0.0:
		return
	var lo: float = Bal.v("lamp/mire_lo", 30.0)
	var hi: float = Bal.v("lamp/mire_hi", 70.0)
	var nb: int = lamp_band
	if g.lamp >= hi:
		nb = 0
	elif g.lamp < lo:
		nb = 2
	elif (lamp_band == 0 and g.lamp < hi - 5.0) or (lamp_band == 2 and g.lamp >= lo + 5.0):
		nb = 1
	if nb == lamp_band:
		return
	lamp_band = nb
	if nb == 1 or g.t - lamp_hint_t < Bal.v("lamp/mire_hint_cd", 10.0):
		return
	lamp_hint_t = g.t
	if nb == 0:
		g.vfx.add_text(g.ppos + Vector2(0, -96), "灯火通明：身边溟痕消退", Color(1.0, 0.85, 0.5), 13)
	else:
		g.vfx.add_text(g.ppos + Vector2(0, -96), "灯火暗淡：溟痕向你蔓延", Color(0.7, 0.55, 1.0), 13)



## 怪物留下的溟痕统一入口（docs/155）：拖痕 trail / 落点 lob / 神经弹 shot / 死亡留痕 death。打上 src 与出生时间 t0，
## 怪物溟痕超过 enemy/mire_enemy_cap 时最老的一片开始淡出（mire_fade 秒后移除，淡出中不再伤人）。常驻规则不变：没被挤掉的照旧常驻
func add_enemy_mire(m: Dictionary, src: String) -> void:
	if g.beacon_sys.holds(m.pos):
		return   # 生效中的引航灯标清除圈内不落怪物溟痕（10-26，用户「灯塔范围内的溟痕全部消失」）
	m["src"] = src
	m["t0"] = g.t
	var cap := int(Bal.v("enemy/mire_enemy_cap", 16.0))
	var n := 0
	var oldest = null
	for x in g.mires:
		if x.has("src") and x.life > 0.0 and not x.has("fade"):
			n += 1
			if oldest == null:
				oldest = x
	if n >= cap and oldest != null:
		fade_mire(oldest)
	g.mires.append(m)


## 让一片溟痕慢慢淡出（不是瞬间消失）：world 按 fade 画透明度，enemies.update_status 倒计时到 0 移除
func fade_mire(m: Dictionary) -> void:
	if not m.has("fade"):
		m["fade"] = Bal.v("enemy/mire_fade", 1.5)
