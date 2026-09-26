extends RefCounted
## 战斗结算：对敌伤害（伤害描述符、护甲 / 易伤 / 藏品倍率，契约 v2.0）、击杀与掉落触发、主控受击（闪避 / 护盾 / 减伤 / 法抗）、
## 治疗、神经损伤、缩圈（黑潮区域）。干员经 characters/op_api.gd 调用。2026-09-26 从 game.gd 拆出。

const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 「追击」（docs/35）：带这些标签的伤害吃 followup_dmg 与追击类藏品（追击、余震、殉爆、召唤物）
const FOLLOWUP_TAGS := ["follow_up", "aftershock", "detonation", "entity"]
const ECOL := {"bone": Color(0.85, 0.9, 0.85), "slider": Color(0.45, 0.7, 1.0), "stone": Color(0.7, 0.7, 0.75), "offspring": Color(0.6, 0.9, 0.5),
	"brood": Color(0.9, 0.6, 0.8), "pocket": Color(0.8, 0.55, 1.0), "skimmer": Color(0.4, 0.9, 0.9), "mother": Color(0.9, 0.5, 0.7),
	"mimic": Color(1.0, 0.75, 0.4), "path": Color(0.6, 0.7, 1.0), "fractal": Color(0.6, 0.7, 1.0), "izumik": Color(0.5, 1.0, 0.7),
	"ishar": Color(0.75, 0.55, 1.0), "tear": Color(0.75, 0.55, 1.0), "iberia": Color(1.0, 0.6, 0.5), "carmen": Color(0.7, 0.7, 1.0),
	"ripper": Color(0.95, 0.55, 0.6), "burrower": Color(0.7, 0.5, 1.0), "spitter": Color(0.6, 1.0, 0.65), "hulk": Color(1.0, 0.95, 0.75),
	"bishop": Color(0.7, 1.0, 0.9), "archon": Color(0.5, 0.9, 0.9), "immortal": Color(0.6, 0.8, 1.0), "paranoia": Color(0.8, 0.6, 1.0)}
var flesh_heal := false
var ember := false
var zone_from_c := Vector2.ZERO
var zone_from_r := 99999.0
var zone_phase := 0
var zone_hurt_t := 0.0
const ZONE_START := 150.0
const ZONE_RADII := [1300.0, 1000.0, 780.0, 600.0, 480.0]
var low_warned := false
## lose_hp 不记 dmg_log 的来源：泪和熄灯掉血原本就不进 dmg_log（bot.gd 单独记熄灯掉血），BALANCE 输出保持不变
const NO_LOG := ["tear", "dark"]
## 主控保护（docs/38 §1.11）：只管 Boss 来源的扣血（Boss 本体接触、Boss 预警 / 冲击环 / 子弹、Boss 子弹留下的溟痕、
## Boss 招式追加的侵蚀、伊莎玛拉之泪）；自然溟痕、黑潮、小怪都不算。数值旋钮 boss/*（Bal.v，默认值即现值）
const BOSS_DOT := ["corrode", "mire"]   # 算「持续伤害」的来源：Boss 在场时合计每秒封顶
## 「任意 2 秒合计 ≤50%」按两种口径同时截，同一份伤害在每个口径里只算一次：
var boss_log: Array = []     # [时刻, 数值]：Boss 扣血 + Boss 招式追加进侵蚀池的量（docs/38 §1.11「含追加的侵蚀」；窗口满时追加的侵蚀也作废）
var loss_log: Array = []     # [时刻, 数值]：Boss 来源的实际扣血，含 Boss 侵蚀结算（实际掉血口径）
var dot_log: Array = []      # [时刻, 实际扣血]：Boss 来源的持续伤害，查「每秒上限」
var corrode_boss := 0.0      # 侵蚀池 g.corrode_pool 里由 Boss 招式追加的那部分；用之前先 _boss_pool() 截到池子以内
var high_t := -INF           # 最近一次「扣血前生命 ≥ fullhp_guard_at」的时刻，满血保护用
var guard_end := -INF        # 满血保护触发后兜底到的时刻（这一轮连击结束：high_t + fullhp_guard_combo）
var guard_ready := 0.0       # 满血保护下次可用的时刻（g.t）


func _init(game: Game) -> void:
	g = game


## 敌人命中水月：闪避判定、侵蚀、神经损伤。src.boss 为真 = Boss 来源（src 是 Boss 本体，或带 boss 标记的预警 / 冲击环 / 子弹），
## 扣血和追加的侵蚀受主控保护（docs/38 §1.11）
func enemy_hit(dmg: float, src: Dictionary, ignore_armor := false, no_dodge := false) -> void:
	if g.demo_op != "":
		return
	if not no_dodge and g.in_type[1] != "真实" and g.rng.randf() < min(g.dodge + (g.dodge_arts if g.in_type[1] == "法术" else g.dodge_phys), 0.6):
		g.invuln = 0.3
		Sfx.play("dodge", -4.0)
		g.vfx.add_text(g.ppos + Vector2(0, -80), "闪避", Color(0.6, 0.85, 1.0), 16)
		on_dodge()
		return
	if g.shield > 0:
		shield_block()
		return
	for o in g.squad.ops:
		if o.has_method("dmg_taken_mult"):
			dmg *= o.dmg_taken_mult()
	var boss: bool = src.get("boss", false)
	var lost := hurt(dmg * (1.15 if g.lamp < 30.0 else 1.0), ignore_armor, boss)
	# 灯火只在受击时熄灭：基础 4 + 伤害占最大生命的比例 × 30（10% 血的一击 -7），受「灯火消耗」修正
	var lamp_loss: float = (Bal.v("lamp/hit_base", 4.0) + Bal.v("lamp/hit_scale", 30.0) * dmg / g.max_hp) * g.lamp_decay
	g.lamp = maxf(0.0, g.lamp - lamp_loss)
	if lamp_loss >= 6.0:
		g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -%d" % int(lamp_loss), Color(1.0, 0.6, 0.4), 13)
	if src.get("corrode", 0.0) > 0.0:
		var add: float = dmg * src.corrode * Bal.v("enemy/corrode_mult", 2.0) * g.corrode_taken_mult
		_boss_pool()   # 池子被清空过（流明净化）时先把 Boss 部分截到池子以内，免得这次追加的普通侵蚀被当成 Boss 的
		if boss:
			# 侵蚀算进上限：追加进侵蚀池的量 ≤ 单发上限 − 这一发实际扣的血，并计入 2 秒合计（窗口满了就作废）；满血保护也管追加的侵蚀。
			# 另外池里的 Boss 侵蚀合计 ≤ boss/corrode_pool_cap：Boss 在场时它的流出被封顶，不封池子会越攒越多，Boss 一死集中流出
			var mh: float = g.max_hp
			var room: float = minf(Bal.v("boss/leader_hit_cap", 0.40) * mh - lost, Bal.v("boss/leader_2s_cap", 0.50) * mh - _window_sum(boss_log, 2.0))
			room = minf(room, Bal.v("boss/corrode_pool_cap", 0.40) * mh - corrode_boss)
			add = _guard(clampf(add, 0.0, maxf(0.0, room)))
			if add > 0.0:
				boss_log.append([g.t, add])
				corrode_boss += add
		g.corrode_pool += add
		if not boss or add > 0.0:
			g.vfx.add_text(g.ppos + Vector2(14, -64), "侵蚀", Color(0.8, 0.5, 1.0), 13)
	if src.get("nerve", 0.0) > 0.0:
		add_nerve(src.nerve * g.nerve_taken_mult)


func on_dodge() -> void:
	g.rfx.on_dodge()


func add_nerve(v: float) -> void:
	g.nerve += v
	if g.nerve >= 100.0:
		g.nerve = 0.0
		if not stun_as_slow():
			g.pstun = 0.4
		if not atk_slow_as_slow(2.5):
			g.atk_slow = maxf(g.atk_slow, 2.5)
		g.dmg_src = "nerve"
		g.in_type = ["近战", "真实"]
		hurt(g.max_hp * 0.08, true)
		g.vfx.add_text(g.ppos + Vector2(0, -100), "神经损伤！", Color(1.0, 0.5, 0.9), 20)
		Sfx.play("skill", -4.0, 1.6)


## ---- 主控保护「永不硬控」「移速下限」「攻速」（docs/38 §1.11，B0-2 / B0-3）
## Boss 存活期间（或这一下本身是 Boss 来源），会让主控僵直的地方（预警僵直、冲击环、神经损伤溢出）改成移速减速：
## boss/stun_as_slow_t（0.5）秒 × boss/stun_as_slow_mult（0.7）。没有 Boss 时照旧僵直。冲刺不查僵直（game._try_dash）。
## 攻速减缓 g.atk_slow（只有水月读：挥伞间隔 ×1.5）同样改成等量的移速减速：时长不变、倍率 boss/atk_slow_as_slow_mult（0.67）。
## 同一种减速重复吃到只刷新时长、不叠乘；不同种之间相乘（move_mult），Boss 存活期间合计不低于 boss/move_floor（0.7）。
var slows: Dictionary = {}   # 主控移速减速：种类 -> [剩余秒数, 倍率]
var ctrl_boss := false       # 上一帧有没有 Boss 存活：Boss 刚出现时残留的僵直 / 攻速减缓直接换掉，不算违规
## 验收计数（BALANCE 的 "ctrl"，快检冒烟会查）：Boss 存活总秒数；其间主控仍处于僵直 / atk_slow 的秒数（应恒为 0）；
## 其间移速倍率的最小值 move_min（含下限，应 ≥ floor）和不含下限的减速乘积最小值 slow_min；僵直 / 攻速减缓换成减速的次数
var ctrl := {"boss_t": 0.0, "stun_t": 0.0, "aslow_t": 0.0, "move_min": 1.0, "slow_min": 1.0, "stun_slow": 0, "aslow_slow": 0}


## Boss 战里把一次僵直换成减速。返回 true = 已换成减速，调用处不再写 g.pstun
func stun_as_slow(boss_src := false) -> bool:
	if not boss_src and not g.spawner.boss_alive():
		return false
	slow_leader("stun", Bal.v("boss/stun_as_slow_t", 0.5), Bal.v("boss/stun_as_slow_mult", 0.7))
	ctrl.stun_slow += 1
	return true


## Boss 战里把一次攻速减缓（t 秒）换成等量的移速减速。返回 true = 已换成减速，调用处不再写 g.atk_slow
func atk_slow_as_slow(t: float, boss_src := false) -> bool:
	if not boss_src and not g.spawner.boss_alive():
		return false
	slow_leader("atk", t, Bal.v("boss/atk_slow_as_slow_mult", 0.67))
	ctrl.aslow_slow += 1
	return true


## 给主控挂一种移速减速：t 秒、倍率 mult；同种只刷新（取较长的时长、用这次的倍率）
func slow_leader(kind: String, t: float, mult: float) -> void:
	if not slows.has(kind):
		g.vfx.add_text(g.ppos + Vector2(0, -96), "减速", Color(0.6, 0.8, 1.0), 14)
	var old: float = slows[kind][0] if slows.has(kind) else 0.0
	slows[kind] = [maxf(old, t), mult]


## 主控移速倍率：raw = 溟痕 / 排异幻境 / 冰霜等原有减速的乘积，再乘上 slows 里的减速（game._update 每帧调一次）。
## Boss 存活期间不低于 boss/move_floor（0.7），并记下验收用的最小值；冲刺速度不走这里，不受减速影响
func move_mult(raw: float) -> float:
	for k in slows:
		raw *= float(slows[k][1])
	if not g.spawner.boss_alive():
		return raw
	ctrl.slow_min = minf(ctrl.slow_min, raw)
	raw = maxf(Bal.v("boss/move_floor", 0.7), raw)
	ctrl.move_min = minf(ctrl.move_min, raw)
	return raw


## 每帧（enemies.update_status，在僵直 / 攻速减缓计时递减之前）：推进减速计时；Boss 存活期间残留的僵直 / 攻速减缓换成减速并记账
func update_ctrl(dt: float) -> void:
	var on: bool = g.spawner.boss_alive()
	if on:
		ctrl.boss_t += dt
		if g.pstun > 0.0:
			if ctrl_boss:
				ctrl.stun_t += dt   # Boss 战中还有地方直接写了 g.pstun：违规，记下来（快检会报）
			g.pstun = 0.0
			stun_as_slow(true)
		if g.atk_slow > 0.0:
			if ctrl_boss:
				ctrl.aslow_t += dt   # 同上，g.atk_slow
			atk_slow_as_slow(g.atk_slow, true)
			g.atk_slow = 0.0
	ctrl_boss = on
	for k in slows.keys():
		slows[k][0] -= dt
		if slows[k][0] <= 0.0:
			slows.erase(k)


## BALANCE 输出用：ctrl 里的秒数 / 倍率取两位小数，附上移速下限 floor
func ctrl_report() -> Dictionary:
	var r := {"floor": Bal.v("boss/move_floor", 0.7)}
	for k in ctrl:
		r[k] = snappedf(ctrl[k], 0.01) if ctrl[k] is float else ctrl[k]
	return r


## 主控扣血统一入口（docs/38 §1.11、§1.17）：主控的扣血路径全部走这里——受击 hurt、黑潮、伊莎玛拉之泪、侵蚀结算、溟痕、灯火熄灭。
## 以后新增扣血来源也走这里。src 记入 g.dmg_log（NO_LOG 里的不记）。boss = Boss 来源，按主控保护截断（_boss_clamp）。
## 返回实际扣掉的生命。
func lose_hp(amount: float, src: String, boss := false) -> float:
	if g.hp >= Bal.v("boss/fullhp_guard_at", 0.9) * g.max_hp:
		high_t = g.t   # 满血保护的「受击前生命」：只记账，不改非 Boss 来源的扣血
	if boss:
		amount = _boss_clamp(amount, src)
	g.hp -= amount
	if not src in NO_LOG:
		g.dmg_log[src] = g.dmg_log.get(src, 0.0) + amount
	return amount


## 主控保护（docs/38 §1.11）：Boss 来源的一次扣血依次截断，并记账。调用时所有倍率（骨血、灯火 <30、护甲、法抗）都已算完。
##   单发上限：≤ boss/leader_hit_cap（40%）最大生命；
##   持续伤害：Boss 在场时，Boss 带来的侵蚀结算 + Boss 溟痕任意 1 秒合计 ≤ boss/dot_cap_per_s（4%）；
##   2 秒合计：任意 2 秒内 ≤ boss/leader_2s_cap（50%），超出作废。两种口径同时截：boss_log（Boss 扣血 + 追加的 Boss 侵蚀）
##   和 loss_log（实际扣血，含 Boss 侵蚀结算）；Boss 侵蚀结算追加时已计入 boss_log，这里只计 loss_log；
##   满血保护：见 _guard。
func _boss_clamp(amount: float, src: String) -> float:
	var mh: float = g.max_hp
	var dot: bool = src in BOSS_DOT
	var drain: bool = src == "corrode"
	amount = clampf(amount, 0.0, Bal.v("boss/leader_hit_cap", 0.40) * mh)
	if dot:
		amount = minf(amount, dot_room())
	var used := _window_sum(loss_log, 2.0)
	if not drain:
		used = maxf(used, _window_sum(boss_log, 2.0))
	amount = _guard(minf(amount, maxf(0.0, Bal.v("boss/leader_2s_cap", 0.50) * mh - used)))
	if amount > 0.0:
		loss_log.append([g.t, amount])
		if not drain:
			boss_log.append([g.t, amount])
		if dot:
			dot_log.append([g.t, amount])
	return amount


## 满血保护（docs/38 §1.11）：扣血前生命 ≥ boss/fullhp_guard_at（90%）之后的 boss/fullhp_guard_combo（2）秒内（一轮连击），
## Boss 来源的扣血和追加的侵蚀最多把「生命 − 池里待流出的 Boss 侵蚀」压到 boss/fullhp_guard_left（10%）。
## 每 boss/fullhp_guard_cd（30）秒触发一次，飘「险些倒下」；触发后兜底到这一轮连击结束。fullhp_guard_combo = 0 即字面规则「受击前生命 ≥90%」。
## amount = 这次要扣的血（g.hp 还没扣）或要追加进池子的 Boss 侵蚀；返回截过的量
func _guard(amount: float) -> float:
	var room: float = g.hp - _boss_pool() - Bal.v("boss/fullhp_guard_left", 0.10) * g.max_hp
	if amount <= 0.0 or amount <= room:
		return amount
	if g.t > guard_end:
		var combo: float = Bal.v("boss/fullhp_guard_combo", 2.0)
		if g.t < guard_ready or g.t - high_t > combo:
			return amount
		guard_ready = g.t + Bal.v("boss/fullhp_guard_cd", 30.0)
		guard_end = high_t + combo
		g.vfx.add_text(g.ppos + Vector2(0, -112), "险些倒下", UI.GOLD, 20)
	# 池里待流出的 Boss 侵蚀就已经压过线：清掉多出的那部分
	var cut: float = minf(corrode_boss, maxf(0.0, -room))
	corrode_boss -= cut
	g.corrode_pool -= cut
	return clampf(room + cut, 0.0, amount)


## 侵蚀池里的 Boss 部分：池子被别处清空或减少（流明净化）时跟着截到池子以内，返回截过的值
func _boss_pool() -> float:
	corrode_boss = maxf(0.0, minf(corrode_boss, g.corrode_pool))
	return corrode_boss


## Boss 在场时，Boss 来源的持续伤害这一秒还能扣多少；没有 Boss 在场时不限
func dot_room() -> float:
	if not g.spawner.boss_alive():
		return INF
	return maxf(0.0, Bal.v("boss/dot_cap_per_s", 0.04) * g.max_hp - _window_sum(dot_log, 1.0))


## 丢掉 span 秒之前的记录（[时刻, 数值]，按时间排好），返回剩下的合计
func _window_sum(rows: Array, span: float) -> float:
	while not rows.is_empty() and float(rows[0][0]) <= g.t - span:
		rows.pop_front()
	var s := 0.0
	for it in rows:
		s += float(it[1])
	return s


## 侵蚀结算（enemies.update_status 每帧调用，tick = 本帧流出量）：按池子里的比例拆成普通部分和 Boss 部分；
## Boss 部分受持续伤害上限，流不出去的留在池里下一帧再流；流出后被 2 秒合计 / 满血保护截掉的部分作废
func drain_corrode(tick: float) -> void:
	var cb := _boss_pool()
	var bt: float = tick * cb / g.corrode_pool if cb > 0.0 else 0.0
	var nt: float = tick - bt
	if bt > 0.0:
		bt = minf(bt, dot_room())
	g.corrode_pool -= nt + bt
	corrode_boss -= bt
	lose_hp(nt, "corrode")
	if bt > 0.0:
		lose_hp(bt, "corrode", true)


## 受击扣血（伤害类型见 g.in_type、来源见 g.dmg_src）：藏品承伤、护甲、法抗算完后走 lose_hp。返回实际扣掉的生命
func hurt(amount: float, ignore_armor := false, boss := false) -> float:
	if g.in_type[1] != "真实":
		amount *= g.rfx.taken_mult()
	if not ignore_armor and g.in_type[1] == "物理":
		amount = max(1.0, amount - g.armor)
	elif g.in_type[1] == "法术":
		amount = max(1.0, amount * (1.0 - minf(g.arts_res, 0.7)))
	amount = lose_hp(amount, g.dmg_src, boss)
	g.rfx.on_hurt(g.dmg_src == "nerve")
	g.invuln = 0.45
	g.hurt_flash = 0.2
	# 受击反馈按伤害占最大生命的比例分级
	var sev := clampf(amount / g.max_hp / 0.12, 0.0, 1.0)
	g.hurt_vignette = 0.6 + 0.4 * sev
	g.red_flash = maxf(g.red_flash, 0.12 + 0.25 * sev)
	g.hp_shake = 0.35
	g.head_bar_t = 2.5
	g.vfx.shake_screen(0.55 + 0.8 * sev)
	g.hitstop = max(g.hitstop, 0.045 + 0.06 * sev)
	Sfx.play("hurt", -1.0 + 3.0 * sev, 1.0 - 0.2 * sev, 0.05)
	Pad.rumble(0.25 + 0.35 * sev, 0.1 + 0.6 * sev, 0.12 + 0.12 * sev)
	g.vfx.sparks(g.ppos + Vector2(0, -24), Vector2.UP, Color(1.0, 0.3, 0.35), 6 + int(8 * sev), 220.0)
	g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, -10), "r": 40.0 + 30.0 * sev, "life": 0.25, "max": 0.25, "col": Color(1.0, 0.3, 0.35)})
	if amount >= 1.0 or not boss:   # Boss 这一击被主控保护截到不足 1 点（2 秒合计已满、满血保护）时不飘「-0」
		g.vfx.add_text(g.ppos + Vector2(randf_range(-14, 14), -84), "-%d" % int(amount), Color(1.0, 0.3, 0.3), int(20 + 10 * sev))
	# 首次跌破 30%：时间短暂变慢 + 警告
	if g.hp > 0.0 and g.hp < g.max_hp * 0.3 and not low_warned:
		low_warned = true
		g.hitstop = max(g.hitstop, 0.35)
		g.vfx.show_banner("生命垂危！")
	elif g.hp > g.max_hp * 0.45:
		low_warned = false
	return amount


## 缩圈：预告 20 秒 → 收缩 25 秒 → 稳定，直到下一轮；圈外为「黑潮」
func update_zone(dt: float) -> void:
	if g.zone_state == 0:
		if g.t < ZONE_START:
			return
		g.zone_c = g.ppos
		g.zone_r = ZONE_RADII[0] + 400.0
		zone_phase = -1
		g.zone_state = 3
		g.zone_t = 0.0
	g.zone_t += dt
	match g.zone_state:
		3:
			if g.zone_t >= (0.0 if zone_phase < 0 else 45.0) and zone_phase < ZONE_RADII.size() - (2 if g.ending == "resolve" else 1):
				zone_phase += 1
				g.zone_next_r = ZONE_RADII[zone_phase]
				var off := Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(0.0, (g.zone_r - g.zone_next_r) * 0.7)
				g.zone_next_c = g.zone_c + off
				g.zone_state = 1
				g.zone_t = 0.0
				g.vfx.show_banner("黑潮将至：%d 秒后安全区缩小" % 20)
				Sfx.play("roar", -6.0, 0.5, 0.0)
		1:
			if g.zone_t >= 20.0:
				g.zone_state = 2
				g.zone_t = 0.0
				zone_from_c = g.zone_c
				zone_from_r = g.zone_r
				g.vfx.show_banner("黑潮正在逼近！")
		2:
			var k := clampf(g.zone_t / 25.0, 0.0, 1.0)
			g.zone_c = zone_from_c.lerp(g.zone_next_c, k)
			g.zone_r = lerpf(zone_from_r, g.zone_next_r, k)
			if k >= 1.0:
				g.zone_state = 3
				g.zone_t = 0.0
	# 圈外：黑潮伤害 + 灯火流失 + 神经损伤
	var out := g.ppos.distance_to(g.zone_c) - g.zone_r
	if out > 0.0 and g.state == g.S.PLAY and not g.squad.in_sanctuary(g.ppos):
		var dps: float = (2.5 + 1.5 * max(zone_phase, 0)) * (1.0 + minf(out / 300.0, 1.0))
		lose_hp(dps * dt, "zone")
		g.lamp = maxf(0.0, g.lamp - 6.0 * dt)
		zone_hurt_t -= dt
		if zone_hurt_t <= 0.0:
			zone_hurt_t = 0.8
			g.hurt_flash = maxf(g.hurt_flash, 0.08)
			g.head_bar_t = 2.0
			g.vfx.add_text(g.ppos + Vector2(0, -84), "黑潮", Color(0.8, 0.4, 1.0), 16)


func in_zone(p: Vector2, margin := 0.0) -> bool:
	return g.zone_state == 0 or p.distance_to(g.zone_c) < g.zone_r - margin


## 护盾抵挡一次伤害：碎裂特效，可选冲击波与回复
func shield_block() -> void:
	g.shield -= 1
	g.shield_flash = 0.3
	g.invuln = 0.5
	if g.shield < g.shield_max and g.shield_cd <= 0.0:
		g.shield_cd = g.shield_every
	Sfx.play("dodge", -2.0, 1.4, 0.0)
	g.vfx.add_text(g.ppos + Vector2(0, -84), "护盾抵挡", Color(0.6, 0.9, 1.0), 16)
	# 碎片
	for k in 14:
		g.fx.append({"kind": "shard", "pos": g.ppos + Vector2(0, -24), "vel": Vector2.from_angle(randf() * TAU) * randf_range(120, 260),
			"life": 0.5, "max": 0.5, "rot": randf() * TAU})
	g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, -20), "r": 50.0, "life": 0.3, "max": 0.3, "col": Color(0.6, 0.9, 1.0)})
	if g.shield_heal:
		heal(g.max_hp * 0.03, "藏品")
	if g.shield_burst:
		for j in g.enemies_sys.query(g.ppos, 140.0):
			var e: Dictionary = g.enemies[j]
			if not e.dead and e.pos.distance_to(g.ppos) < 140.0:
				damage(e, 30.0 * g.dmg_mult * enemy_hp_time_mult())
				if not e.boss:
					e.kb += (e.pos - g.ppos).normalized() * 420.0
		g.fx.append({"kind": "explode", "pos": g.ppos, "r": 140.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.85, 1.0)})
		g.vfx.shake_screen(0.6)


## 这次伤害是否算「追击」（docs/35）
func is_followup(h: Dictionary) -> bool:
	for tg in h.tags:
		if tg in FOLLOWUP_TAGS:
			return true
	return false


## 敌人生命的时间倍率（不含难度）：藏品的直接伤害按它缩放，保证各时段同样「有感」
func enemy_hp_time_mult() -> float:
	var hk: float = Bal.v("enemy/hp_knee", 480.0)
	return 1.0 + minf(g.t, hk) / Bal.v("enemy/hp_div", 120.0) + maxf(g.t - hk, 0.0) / Bal.v("enemy/hp_late_div", 300.0)


## 设置当前伤害描述符（extra_tags 追加本次特有标签，如 empowered）
func hit(src: String, extra_tags: Array = []) -> void:
	var base: Dictionary = g.hit_src.get(src, {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []})
	g.hit = {"src": src, "emitter": base.emitter, "origin": base.origin, "range": base.range, "kind": base.kind, "tags": base.tags + extra_tags,
		"class": base.get("class", ""), "op": base.get("op", "")}


func damage(e: Dictionary, dmg: float) -> void:
	if e.dead:
		return
	# 灯火照亮：光中的敌人受到的伤害 +25%（流明光弹的「照亮」e.lit 同样视为在灯光内）
	if e.pos.distance_squared_to(g.ppos) < g._lamp_r() * g._lamp_r() or e.get("lit", 0.0) > 0.0:
		dmg *= 1.25
	if e.invuln:
		if g.texts.size() < 80 and g.vrng.randf() < 0.2:
			g.vfx.add_text(e.pos + Vector2(0, -e.r - 10), "无效", Color(0.6, 0.7, 0.8), 13)
		return
	if e.chest and e.hidden:
		e.hidden = false
		g.spawner.reveal_mimic(e)
		return
	var ty: Array = [g.hit.range, g.hit.kind]
	var weak_hit := false
	if ty[1] != "真实":
		dmg *= e.def * g.rfx.dmg_extra()
		# 弱点：对应类型伤害 +50%（藏品可加成 / 赋予双弱点）
		var wk: String = e.get("weak", "")
		if wk == ty[1] or (wk == "双" and ty[1] != "真实") or (g.rfx.rule("all_weak") > 0):
			dmg *= 1.5 + g.weak_bonus
			weak_hit = true
		dmg *= g.melee_mult if ty[0] == "近战" else g.ranged_mult
		if e.get("aura_weak", 0.0) > 0.0:
			dmg *= 1.1
		dmg *= g.arts_mult if ty[1] == "法术" else g.phys_mult
		if is_followup(g.hit):
			dmg *= g.followup_mult * g.rfx.followup_extra()
		dmg *= g.rfx.hit_mult(g.hit)
		# Logos「安魂」：受到的法术伤害 +15%
		if ty[1] == "法术" and e.get("requiem", 0.0) > 0.0:
			dmg *= 1.15
		if g.low_hp_bonus > 0.0 and e.hp < e.maxhp * 0.5:
			dmg *= 1.0 + g.low_hp_bonus
		if e.boss and g.final_boss != null and is_same(e, g.final_boss):
			dmg *= 1.0 + 0.01 * g.rfx.rule("final_taken") + (0.8 if g.rfx.rule("bone_blood") > 0 else 0.0)
	# Boss 单次伤害上限（boss/hit_cap_pct，缺省 0 = 关）：一次最多打掉最大生命的这个比例，防爆发一击秒杀；开不开、开多少由数值按实测定
	if e.boss:
		var hcap: float = Bal.v("boss/hit_cap_pct", 0.0)
		if hcap > 0.0:
			dmg = minf(dmg, e.maxhp * hcap)
	g.rfx.on_hit(e, g.hit)
	e.hp -= dmg
	var eff: float = minf(dmg, maxf(e.hp + dmg, 0.0))
	g.dmg_out[g.hit.src] = g.dmg_out.get(g.hit.src, 0.0) + eff
	if g.hit.origin == "relic":
		g.relic_out += eff
	g.dmg_type_out[ty[1]] = g.dmg_type_out.get(ty[1], 0.0) + eff
	for tg in g.hit.tags:
		g.dmg_tag_out[tg] = g.dmg_tag_out.get(tg, 0.0) + eff
	e.hits += 1
	e.flash = 0.08
	e.squash = 0.14
	# 伤害数字的位置抖动是纯画面，用 g.vrng：飘字数量取决于画面随机数（上面的「无效」），设置里还能关掉伤害数字，
	# 用 g.rng 会让机器负载 / 玩家设置改变对局随机数（docs/36 §3）
	if g.texts.size() < 80 and Cfg.dmg_numbers:
		if g.crit_hit:
			g.vfx.add_text(e.pos + Vector2(g.vrng.randf_range(-6, 6), -e.r - 10), str(int(round(dmg))), UI.GOLD, 22)
		elif weak_hit:
			g.vfx.add_text(e.pos + Vector2(g.vrng.randf_range(-6, 6), -e.r - 12), "弱点 " + str(int(round(dmg))), Color(1.0, 0.85, 0.35), 18)
		else:
			g.vfx.add_text(e.pos + Vector2(g.vrng.randf_range(-6, 6), -e.r - 8), str(int(round(dmg))), Color(1, 1, 1, 0.95), 14)
	# 圣徒装填时被打断
	if e.get("channel", 0.0) > 0.0:
		e.channel = 0.0
		e.stun = 6.0
		e.ammo = 0
		e.ai = "melee"
		g.vfx.add_text(e.pos + Vector2(0, -50), "装填被打断！", UI.GOLD, 20)
		g.vfx.shake_screen(0.5)
	# "偏执泡影"：首次被控制后失去悬浮，进入第二形态
	if e.type == "paranoia" and e.phase == 1 and e.stun > 0.3:
		e.phase = 2
		e.range = 400.0
		e.weak = "物理"
		e.dmg *= 1.2
		g.vfx.show_banner("\"偏执泡影\" 失去悬浮 —— 第二形态")
		Sfx.play("roar", 0.0, 1.2, 0.0)
	# 掠海漂移体被控制后落地，改为近战
	if e.get("hover_lost", false) == false and D.ENEMIES.has(e.type) and D.ENEMIES[e.type].get("hover", false) and e.stun > 0.3:
		e.hover_lost = true
		e.ai = "melee"
		e.spd = 70.0
		g.vfx.add_text(e.pos + Vector2(0, -30), "坠落", Color(0.6, 0.9, 1.0), 16)
	if e.hp <= 0.0:
		# 最后的骑士：第一次归零不死，寒冰重生（二阶段）
		if e.type == "knight_boss" and e.phase == 1:
			e.phase = 2
			e.hp = e.maxhp * 0.5
			e.spd *= 1.2
			e.invuln = true
			e.channel = 1.5
			e.stun = 0.0
			e.kb = Vector2.ZERO
			if not g.vfx.fx_sprite("fx_knight_rebirth", e.pos + Vector2(0, -20), g.PX * 1.4, 0.0):
				g.fx.append({"kind": "ring", "pos": e.pos, "r": 90.0, "life": 0.6, "max": 0.6, "col": Color(0.6, 0.9, 1.4)})
			g.vfx.show_banner("寒冰重生 —— 最后的骑士 第二阶段")
			Sfx.play("roar", 0.0, 0.9, 0.0)
			g.vfx.shake_screen(1.2)
			return
		if D.ENEMIES.get(e.type, {}).get("pair", false) and e.get("partner") != null and not e.partner.dead:
			e.hp = 1.0
			e.coma = true
			e.invuln = true
			e.stun = 0.0
			g.vfx.add_text(e.pos + Vector2(0, -50), "假死（同时击倒另一体）", Color(0.6, 1.0, 0.9), 16)
			return
		kill(e)


func heal(v: float, src: String = "其他") -> void:
	v *= g.heal_mult
	var got: float = minf(v, maxf(0.0, g.max_hp - g.hp))
	g.heal_log[src] = float(g.heal_log.get(src, 0.0)) + got
	if v > got:
		g.rfx.on_overheal(v - got)
	g.hp = min(g.max_hp, g.hp + v)


func kill(e: Dictionary) -> void:
	g.rfx.on_kill(e)
	if e.dead:
		return
	e.dead = true
	# 海嗣祭坛：打开事件选项
	if e.chest and e.get("event", "") != "":
		Sfx.play("relic", -2.0, 0.8)
		g.vfx.sparks(e.pos, Vector2.UP, Color(0.5, 0.8, 1.4), 18, 260.0)
		g.fx.append({"kind": "rays", "pos": e.pos, "life": 0.7, "max": 0.7, "col": Color(0.5, 0.8, 1.0)})
		g.endg.open(e.event)
		return
	# 补给箱被打碎
	if e.chest:
		Sfx.play("relic", -6.0, 1.3)
		g.vfx.sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 12, 220.0)
		for k in g.rng.randi_range(3, 6):
			g.pickups.drop(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(4.0, 18.0), "ingot", 1.0)
		if g.rng.randf() < 0.3:
			g.pickups.drop(e.pos + Vector2(10, 6), "oil", 15.0)
		return
	if e.type != "tear":
		g.kills += 1
	if e.has("horde") and e.horde < g.horde_log.size():
		var hl: Dictionary = g.horde_log[e.horde]
		hl.killed += 1
		if hl.t80 < 0 and hl.killed >= int(hl.n * 0.8):
			hl.t80 = int(g.t) - hl.t
	var col: Color = ECOL.get(e.type, Color(0.6, 0.9, 0.9))
	g.vfx.sparks(e.pos, Vector2.ZERO, col, 7, 160.0)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 1.2, "life": 0.18, "max": 0.18, "col": col})
	Sfx.play("kill", -8.0)
	if e.get("tex_death", false) and g.V6_FRAMES.has(e.tex + "_death"):
		var dtx: Texture2D = g.tex[e.tex + "_death"]
		var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * g.PX)
		g.vfx.fx_sprite(e.tex + "_death", foot + Vector2(0, -(dtx.get_height() - 3) * g.PX * 0.5), g.PX, 0.0)
	elif not g.vfx.fx_sprite("fx_death_dissolve", e.pos, g.PX * max(1.0, e.r / 12.0)):
		g.vfx.anim("fx_death", e.pos, 0.3, g.PX * max(1.0, e.r / 12.0))
	if e.elite:
		g.elites_killed += 1
	if e.elite or e.boss:
		Sfx.play("boom", 0.0, 1.0, 0.0)
		g.hitstop = max(g.hitstop, 0.12)
		g.vfx.shake_screen(1.0)
		g.vfx.sparks(e.pos, Vector2.ZERO, UI.GOLD, 24, 320.0)
	g.squad.on_kill(e)
	if flesh_heal and e.evo:
		heal(g.max_hp * 0.03, "藏品")
	if ember and e.elite:
		g.lamp = min(g.lamp_cap, g.lamp + 20.0)
	if e.xp > 0.0:
		g.pickups.drop(e.pos, "xp", e.xp * g.xp_mult)
	if g.rng.randf() < 0.012 * (0.5 if g.diff >= 3 else 1.0):
		g.pickups.drop(e.pos + Vector2(8, 0), "oil", 15.0)
	# 特殊道具：磁铁 / 回复（小怪低概率，精英与 Boss 必掉其一）
	if e.elite or e.boss:
		g.pickups.drop(e.pos + Vector2(-16, 8), "magnet" if g.rng.randf() < 0.5 else "heal", 1.0)
	elif g.pickups.count_items() < 3:
		var r := g.rng.randf()
		if r < 0.0025:
			g.pickups.drop(e.pos, "magnet", 1.0)
		elif r < 0.006:
			g.pickups.drop(e.pos, "heal", 1.0)
	var ing: int = D.ENEMIES.get(e.type, {}).get("ingots", 0)
	if e.elite:
		ing = max(ing, g.rng.randi_range(3, 5))
		g.pickups.drop(e.pos, "chest", 1.0)
		g.pickups.drop(e.pos + Vector2(20, 10), "oil", 25.0)
	if e.boss:
		ing = 20
		if not is_same(e, g.final_boss) and not g.spawner.boss_alive():
			Sfx.play_overlay("boss_down")   # 最终 Boss 走结算乐句；双 Boss 需全部倒下
		g.pickups.drop(e.pos + Vector2(-20, 0), "chest", 1.0)
		for j in 12:
			g.pickups.drop(e.pos + Vector2.from_angle(TAU * j / 12.0) * 30.0, "xp", 20.0)
		# Boss 倒下时清除它召唤的东西
		for o in g.enemies:
			if (o.type == "tear" and e.type == "ishar") or (o.feed and is_same(o.get("feed_to"), e)):
				o.dead = true
	if g.diff >= 5 and ing > 0:
		ing = int(floor(ing * 0.7 + g.rng.randf()))
	for k in ing:
		g.pickups.drop(e.pos + Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(6.0, 26.0), "ingot", 1.0)
