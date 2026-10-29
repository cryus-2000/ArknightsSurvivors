extends RefCounted
## 战斗结算：对敌伤害（伤害描述符、护甲 / 易伤 / 藏品倍率，契约 v2.0）、击杀与掉落触发、主控受击（闪避 / 护盾 / 减伤 / 法抗）、
## 治疗、神经损伤、缩圈（黑潮区域）。干员经 characters/op_api.gd 调用。2026-09-26 从 game.gd 拆出。

const A = preload("res://scripts/art.gd")
const D = preload("res://scripts/data.gd")
const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")   # data/balance.json 数值旋钮（docs/27）
const Meta = preload("res://scripts/core/meta.gd")   # 认知塑造质变节点（docs/109 §14 v5）

const Game = preload("res://scripts/game.gd")   # 带类型：g.xxx 能推断类型，成员名拼错在加载时就报错
var g: Game
## 「追击」（docs/35）：带这些标签的伤害吃 followup_dmg 与追击类藏品（追击、余震、殉爆、召唤物）
const FOLLOWUP_TAGS := ["follow_up", "aftershock", "detonation", "entity"]
var zone_from_c := Vector2.ZERO
var zone_from_r := 99999.0
var zone_phase := 0
var zone_hurt_t := 0.0
var zone_out_t := 0.0     # 本次出圈了几秒（圈内为 0）：前 ZONE_GRACE 秒不掉血；界面据此画回圈方向提示
var zone_paused := false  # Boss 在场，缩圈计时暂停
const ZONE_START := 150.0
const ZONE_GRACE := 2.0   # 1.1 用户决定：出圈后 2 秒内不掉血
const ZONE_RADII := [1300.0, 1000.0, 780.0, 600.0, 480.0]
var low_warned := false
## lose_hp 不记 dmg_log 的来源：泪和熄灯掉血原本就不进 dmg_log（bot.gd 单独记熄灯掉血），BALANCE 输出保持不变
const NO_LOG := ["tear", "dark"]
## 主控保护（docs/38 §1.11）：只管 Boss 来源的扣血（Boss 本体接触、Boss 预警 / 冲击环 / 子弹、Boss 子弹留下的溟痕、
## Boss 招式追加的侵蚀、伊莎玛拉之泪）；自然溟痕、黑潮、小怪都不算。数值旋钮 boss/*（Bal.v，默认值即现值）
const BOSS_DOT := ["corrode", "mire", "izu_burn"]   # 算「持续伤害」的来源：Boss 在场时合计每秒封顶（izu_burn：伊祖米克「震撼」33% 后的持续法伤，docs/95 §3.2 D）
## 「任意 2 秒合计 ≤50%」按两种口径同时截，同一份伤害在每个口径里只算一次：
var boss_log: Array = []     # [时刻, 数值]：Boss 扣血 + Boss 招式追加进侵蚀池的量（docs/38 §1.11「含追加的侵蚀」；窗口满时追加的侵蚀也作废）
var loss_log: Array = []     # [时刻, 数值]：Boss 来源的实际扣血，含 Boss 侵蚀结算（实际掉血口径）
var dot_log: Array = []      # [时刻, 实际扣血]：Boss 来源的持续伤害，查「每秒上限」
var corrode_boss := 0.0      # 侵蚀池 g.corrode_pool 里由 Boss 招式追加的那部分；用之前先 _boss_pool() 截到池子以内
var corrode_amp_until := -1.0   # 蚀潮吐息（docs/95 §9.2 C）：到这一刻之前侵蚀结算伤害 × corrode_amp_mult（Boss 部分仍受持续伤害上限）
var corrode_amp_mult := 1.0
var high_t := -INF           # 最近一次「扣血前生命 ≥ fullhp_guard_at」的时刻，满血保护用
var guard_end := -INF        # 满血保护触发后兜底到的时刻（这一轮连击结束：high_t + fullhp_guard_combo）
var guard_ready := 0.0       # 满血保护下次可用的时刻（g.t）
var enemy_stun_next := 0.0   # 普通怪短僵直的全局间隔，避免多只怪连续控住主控


func _init(game: Game) -> void:
	g = game


## 低频面板（事件卡 / 路口卡 / 安全的角落 / 紧急作战 / 诡意行商）关闭后的保护（10-28 用户定 A：「选完事件被围着打到一滴血」）：
## 队长 protect/panel_grace（0.8）秒无敌，脚下淡金环收拢表示保护中（world.draw_panel_grace）；升级 / 宝箱选卡不加，队友不加
func panel_grace() -> void:
	var t: float = Bal.v("protect/panel_grace", 0.8)
	if t <= 0.0:
		return
	g.invuln = maxf(g.invuln, t)
	g.panel_grace_until = g.t + t


## 敌人命中水月：闪避判定、侵蚀、神经损伤。src.boss 为真 = Boss 来源（src 是 Boss 本体，或带 boss 标记的预警 / 冲击环 / 子弹），
## 扣血和追加的侵蚀受主控保护（docs/38 §1.11）
func enemy_hit(dmg: float, src: Dictionary, ignore_armor := false, no_dodge := false, in_type: Array = [], dmg_src := "") -> void:
	# 伤害上下文（docs/101 B1）：调用方显式传伤害类型 in_type（[距离, 类型]）与来源名 dmg_src，由这里写 g.in_type / g.dmg_src
	# 给 hurt / lose_hp 读；外部模块不再自己写这两个全局。不传则沿用当前值
	if not in_type.is_empty():
		g.in_type = in_type
	if dmg_src != "":
		g.dmg_src = dmg_src
	if g.demo_op != "" and g.demo_enemy == "":
		return
	if g.ult != null and not src.is_empty():
		g.ult.ev.last_src = src   # 连携（归溟幽灵鲨）：伤害来源
	if not no_dodge and g.in_type[1] != "真实" and g.rng.randf() < min(g.dodge + g.rfx.dodge_extra() + (g.dodge_arts if g.in_type[1] == "法术" else g.dodge_phys), 0.6):
		g.invuln = 0.3
		Sfx.play("dodge", -4.0)
		g.vfx.add_text(g.ppos + Vector2(0, -80), "闪避", Color(0.6, 0.85, 1.0), 16)
		on_dodge()
		return
	if g.shield > 0:
		shield_block(dmg)
		return
	var negated := false
	for o in g.squad.ops:
		if o.has_method("dmg_taken_mult"):
			# 受击询问（docs/101 B1：显式传参）：src = 这一下的来源（数据干员 trig.on_hurt 读 boss，docs/61「星熊」节）；
			# dmg = 这一下（已乘前面干员的减伤）的伤害，干员护盾（docs/61 §15 verb.shield）按它算吸收量
			var m: float = o.dmg_taken_mult(src, dmg)
			negated = negated or m <= 0.0
			if g.bot != null and m < 1.0:
				g.telemetry.note_dr(str(o.id), dmg * (1.0 - maxf(0.0, m)))   # docs/88 遥测：只在 --balance 下记
			dmg *= m
	# 干员格挡（dmg_taken_mult 返回 0，docs/59 §3 星熊「战术装甲」）：这一下整个作废——不扣血、不掉灯火、不吃控制 / 侵蚀，同闪避给 0.3 秒无敌
	if negated:
		g.invuln = maxf(g.invuln, 0.3)
		return
	var boss: bool = src.get("boss", false)
	g.telemetry.hit_type = g.telemetry.src_type(src)
	if g.telemetry.rich:
		g.telemetry.hit_elite = src.get("elite", false)   # docs/200：逐笔明细要带精英 / Boss 弹标记（只读）
		g.telemetry.hit_boss = boss
	if src.get("elite", false):
		dmg *= g.elite_taken_mult   # 王庭盟约（docs/57 P7）：精英来源对主控的伤害
	if boss:
		dmg *= final_boss_hit_x()
	one_cap = float(src.get("hit_cap", 0.0))   # 来源自带的单次上限（玩法系统「围猎」事件敌人 e.hit_cap，其子弹 / 抛石照带）
	# 认知塑造「自我保护」末节：连续 meta/calm_t 秒未受伤后，下一次受到的伤害 × meta/calm_mult（受击后 rfx.on_hurt 归零计时）
	if g.rfx.rule("calm_guard") > 0 and g.rfx.calm_t >= Bal.v("meta/calm_t", 5.0):
		dmg *= Bal.v("meta/calm_mult", 0.5)
		g.vfx.add_text(g.ppos + Vector2(0, -100), "静守", Color(0.7, 0.9, 1.0), 15)
	var lost := hurt(dmg * (Bal.v("lamp/dark_taken", 1.05) if g.lamp < 30.0 else 1.0), ignore_armor, boss)   # 灯火暗淡（< 30）受到的伤害倍率（docs/88 旋钮，缺省 1.15 不变）
	one_cap = 0.0
	if lost <= 0.0:
		return
	ctrl_hit_cat = ctrl_cat(src)   # 控制遥测：这一下吃到的冰霜 / 寒霜 / 束缚记到这个来源
	if float(src.get("frost", 0.0)) > 0.0:
		frost_leader(float(src.frost), ctrl_hit_cat)
	# 小怪控制：按来源敌人的 enemies.json 字段（cold_hit 寒霜层 / wound_hit 侵蚀创口 / root_hit 束缚秒数，束缚只认预警招式）
	if ctrl_on():
		var sd: Dictionary = D.ENEMIES.get(str(src.get("type", src.get("src_type", ""))), {})
		if not sd.is_empty():
			add_cold(int(sd.get("cold_hit", 0)))
			g.afflict.add_wound(int(sd.get("wound_hit", 0)))
			if int(sd.get("wound_hit", 0)) > 0:
				g.telemetry.on_status("wound", g.telemetry.hit_type, float(sd.wound_hit))
			if src.get("warn", false):
				add_root(float(sd.get("root_hit", 0.0)), "束缚")
	ctrl_hit_cat = "other"
	# 凋亡损伤：小怪来源按 ctrl_start 生效，Boss 来源（伊祖米克）一直生效
	var ad: Dictionary = D.ENEMIES.get(str(src.get("type", src.get("src_type", ""))), {})
	if float(ad.get("apop_hit", 0.0)) > 0.0 and (ctrl_on() or ad.get("role", "") == "boss"):
		add_apop(float(ad.apop_hit))
	# 灯火只在受击时熄灭：基础 4 + 伤害占最大生命的比例 × 30（10% 血的一击 -7），受「灯火消耗」修正
	var lamp_loss: float = (Bal.v("lamp/hit_base", 2.0) + Bal.v("lamp/hit_scale", 18.0) * dmg / g.max_hp) * g.lamp_decay * g.lamp_loss_mult
	var l0: float = g.lamp
	g.lamp = maxf(0.0, g.lamp - lamp_loss)
	g.telemetry.lamp_note("受击", g.lamp - l0)
	if lamp_loss >= 6.0:
		g.vfx.add_text(g.ppos + Vector2(20, -60), "灯火 -%d" % int(lamp_loss), Color(1.0, 0.6, 0.4), 13)
	if src.get("corrode", 0.0) > 0.0:
		g.afflict.add_corrode(dmg, src.corrode, boss, lost)
	# 命中附带的神经损伤：用户 9/29 按原作改成只有溟痕累积，命中来源乘 enemy/nerve_hit_mult（缺省 0 = 不累积）
	if src.get("nerve", 0.0) > 0.0:
		g.telemetry.on_status("nerve", g.telemetry.hit_type, float(src.nerve))
		g.afflict.add_nerve(src.nerve * g.nerve_taken_mult * Bal.v("enemy/nerve_hit_mult", 0.0), boss)


## 最终 Boss 加伤（用户 10-29，docs/201）：最终 Boss 在场时，Boss 来源的一下按来源分两档放大，血量不动。
## 敌弹（dmg_src = bullet）× boss/final_bullet_x_<类型>，其余（预警招式、冲击环、接触）× boss/final_move_x_<类型>；缺省 1 = 不变。
## 在护甲 / 法抗与主控保护（单发 40%、2 秒 50%、满血保护）之前乘，保护照旧兜底
func final_boss_hit_x() -> float:
	var fb = g.final_boss
	if fb == null or fb.dead:
		return 1.0
	var k: String = ("boss/final_bullet_x_" if g.dmg_src == "bullet" else "boss/final_move_x_") + str(fb.type)
	return Bal.v(k, 1.0)


func on_dodge() -> void:
	g.telemetry.dodges += 1
	g.rfx.on_dodge()


## ---- 神经损伤（用户 9/29，按原作 PRTS：溟痕每秒累积，满格一次真伤 + 眩晕）
## 站在溟痕里（自然 / 小怪 / Boss 溟痕、巢涌者的神经光环都算）每秒 +enemy/nerve_mire × 难度修正 nerve_rate，离开后每秒 −nerve_decay，
## 流明光域里不累积且回落加倍。满 nerve_max：一次真伤 nerve_burst（最大生命 12%，走 lose_hp，受 2 秒合计上限）+ 眩晕 nerve_stun 秒
## （按硬控规则：冲刺挣脱、之后免疫、Boss 在场换成减速），然后清零并 nerve_lock 秒不再累积——满格惩罚是一次性的，不是持续的。
## 字段 g.nerve（0–nerve_max）、g.nerve_lock；净化清 g.nerve
func nerve_max() -> float:
	return g.afflict.nerve_max()


## 转发到 afflict（10-29 起累积 / 结算 / 清除都在 run/afflict.gd）
func add_nerve(v: float) -> void:
	g.afflict.add_nerve(v)


func update_nerve(dt: float, in_src: bool, sanct: bool, mire_mult := 1.0) -> void:
	g.afflict.update_nerve(dt, in_src, sanct, mire_mult)


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

## 控制遥测（用户 10-01，docs/41「EA 后待派」：设计 Ⅳ / Ⅷ「改操作」机制的前置数据）：只记账，不改玩法。
## 按来源分四类（CTRL_CATS + Boss，其余记 other），每类记：被冻结次数 freeze_n、冻结总秒数 freeze_t（冲刺提前挣脱按实际算）、
## 冲刺挣脱冻结次数 dash_break_n、被减速总秒数 slow_t（冰霜 g.frost、寒霜层 g.cold、slows 里的减速；同一类同一时刻只算一次）。
## slow_any_t = 有任何一种减速在身上的总秒数（不同来源同时生效只算一次）。BALANCE / 本地记录的 "ctrl_src"（telemetry.record）
const CTRL_CATS := {"founder": "founder", "skimmer": "skimmer"}   # 敌人 type -> 分类：奠基者、漂移体
var ctrl_src := {}             # 分类 -> {freeze_n, freeze_t, dash_break_n, slow_t}（ctrl_src_report 输出）
var ctrl_slow_any := 0.0
var ctrl_hit_cat := "other"    # enemy_hit 这一下的来源分类：add_cold / add_root 在这一下里读，结束后回到 other
var cold_cat := "other"        # 当前寒霜层最后一次叠层的来源
var frost_cat := "other"       # 当前冰霜减速（g.frost）的来源
var root_cat := "other"        # 当前冻结 / 束缚的来源
var root_kind := ""            # 当前 g.root_t 的种类：冻结 / 束缚 / 眩晕
var slow_cat := {}             # slows 的种类 -> 来源分类


## 敌人来源 → 控制遥测分类：Boss 本体 / 带 boss 标记的预警、子弹 → boss；奠基者 / 漂移体按 type；其余 other
func ctrl_cat(src: Dictionary) -> String:
	var t := str(src.get("type", src.get("src_type", "")))
	if src.get("boss", false) or str(D.ENEMIES.get(t, {}).get("role", "")) == "boss":
		return "boss"
	return CTRL_CATS.get(t, "other")


func _ctrl_entry(cat: String) -> Dictionary:
	if not ctrl_src.has(cat):
		ctrl_src[cat] = {"freeze_n": 0, "freeze_t": 0.0, "dash_break_n": 0, "slow_t": 0.0}
	return ctrl_src[cat]


## 每帧（update_ctrl 开头，减速计时递减之前）：按来源累计冻结秒数与减速秒数
func _ctrl_tally(dt: float) -> void:
	if g.root_t > 0.0 and root_kind == "冻结":
		_ctrl_entry(root_cat).freeze_t += minf(dt, g.root_t)
	var cats := {}
	if g.frost > 0.0:
		cats[frost_cat] = true
	if g.cold > 0:
		cats[cold_cat] = true
	for k in slows:
		cats[slow_cat.get(k, "boss")] = true
	for c in cats:
		_ctrl_entry(c).slow_t += dt
	if not cats.is_empty():
		ctrl_slow_any += dt


## 冲刺时（game._try_dash 清 root_t 之前）：正在冻结就记一次挣脱
func on_dash_break() -> void:
	if g.root_t > 0.0 and root_kind == "冻结":
		_ctrl_entry(root_cat).dash_break_n += 1


## 冰霜减速（g.frost 秒）：取较长的时长，记下来源
func frost_leader(t: float, cat: String) -> void:
	g.frost = maxf(g.frost, t)
	frost_cat = cat


## BALANCE / 本地记录用：四类都输出（没吃到的为 0），秒数取两位小数
func ctrl_src_report() -> Dictionary:
	var r := {"slow_any_t": snappedf(ctrl_slow_any, 0.01)}
	for c in ["founder", "skimmer", "boss", "other"]:
		var e: Dictionary = _ctrl_entry(c)
		r[c] = {"freeze_n": e.freeze_n, "freeze_t": snappedf(e.freeze_t, 0.01), "dash_break_n": e.dash_break_n, "slow_t": snappedf(e.slow_t, 0.01)}
	return r


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


## 给主控挂一种移速减速：t 秒、倍率 mult；同种只刷新（取较长的时长、用这次的倍率）。cat = 控制遥测的来源分类
func slow_leader(kind: String, t: float, mult: float, cat := "boss") -> void:
	if not slows.has(kind):
		g.vfx.add_text(g.ppos + Vector2(0, -96), "减速", Color(0.6, 0.8, 1.0), 14)
	var old: float = slows[kind][0] if slows.has(kind) else 0.0
	slows[kind] = [maxf(old, t), mult]
	slow_cat[kind] = cat


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
	_ctrl_tally(dt)
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
			slow_cat.erase(k)


## BALANCE 输出用：ctrl 里的秒数 / 倍率取两位小数，附上移速下限 floor
func ctrl_report() -> Dictionary:
	var r := {"floor": Bal.v("boss/move_floor", 0.7)}
	for k in ctrl:
		r[k] = snappedf(ctrl[k], 0.01) if ctrl[k] is float else ctrl[k]
	return r


## 主控扣血统一入口（docs/38 §1.11、§1.17）：主控的扣血路径全部走这里——受击 hurt、黑潮、伊莎玛拉之泪、侵蚀结算、溟痕、灯火熄灭。
## 以后新增扣血来源也走这里。src 记入 g.dmg_log（NO_LOG 里的不记）。boss = Boss 来源，按主控保护截断（_boss_clamp）。
## 返回实际扣掉的生命。
var one_cap := 0.0   # enemy_hit 这一次的单次上限（最大生命比例，0 = 无）；只在 enemy_hit 调 hurt 期间有效


func lose_hp(amount: float, src: String, boss := false) -> float:
	var pre_all := amount   # 遥测补洞（docs/200）：各级上限截之前的量，只在 telemetry.rich 下用
	if one_cap > 0.0:
		amount = minf(amount, one_cap * g.max_hp)
	var pre_boss := amount
	if g.hp >= Bal.v("boss/fullhp_guard_at", 0.9) * g.max_hp:
		high_t = g.t   # 满血保护的「受击前生命」：只记账，不改非 Boss 来源的扣血
	if boss:
		amount = _boss_clamp(amount, src)
	var pre_any := amount
	amount = _any_clamp(amount)
	g.hp -= amount
	if g.ult != null:
		g.ult.on_lose(amount)   # 终结技能量：受伤来源
	if g.telemetry.rich:
		g.telemetry.cap_note(pre_all, pre_boss, pre_any, amount, src, boss)   # 上限触发计数 + 逐笔明细（只读）
	if g.bench.live:
		g.bench.on_lose(amount)   # Boss 单场测试台：队长承伤（docs/170）
	g.telemetry.on_lose(amount, src)   # 作战记录：击倒者归属（持续伤害记给施加它的敌人，docs/77）
	if not src in NO_LOG:
		g.dmg_log[src] = g.dmg_log.get(src, 0.0) + amount
	return amount


## 通用 2 秒掉血上限（用户 9/27「后期暴毙」方案 3-A，数值旋钮，缺省关）：任何来源（含 Boss、黑潮、熄灯、侵蚀结算）
## 在 2 秒窗口内的实际扣血合计超过 最大生命 × protect/any_2s_cap 的部分，再乘 protect/any_excess_mult。
## Boss 来源先走上面 _boss_clamp 那套，这里按截过之后的实际扣血记账，不重复截同一口径
var any_log: Array = []   # [时刻, 实际扣血]


func _any_clamp(amount: float) -> float:
	var cap: float = Bal.v("protect/any_2s_cap", 0.7)
	if cap <= 0.0 or amount <= 0.0:
		return amount
	var lim: float = cap * g.max_hp
	var used := _window_sum(any_log, 2.0)
	var over: float = maxf(0.0, used + amount - maxf(lim, used))
	amount = amount - over + over * Bal.v("protect/any_excess_mult", 0.6)
	any_log.append([g.t, amount])
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
	amount = _guard(minf(amount, maxf(0.0, Bal.v("boss/leader_2s_cap", 0.68) * mh - used)))
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
	var room: float = g.hp - _boss_pool() - Bal.v("boss/fullhp_guard_left", 0.05) * g.max_hp
	if amount <= 0.0 or amount <= room:
		return amount
	if g.t > guard_end:
		var combo: float = Bal.v("boss/fullhp_guard_combo", 2.0)
		if g.t < guard_ready or g.t - high_t > combo:
			return amount
		guard_ready = g.t + Bal.v("boss/fullhp_guard_cd", 60.0)
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
	var room: float = dot_room() if bt > 0.0 else 0.0
	if bt > 0.0:
		bt = minf(bt, room)
	g.corrode_pool -= nt + bt
	corrode_boss -= bt
	# 蚀潮吐息增幅：流出量不变，扣血 × corrode_amp_mult；Boss 部分增幅后仍截到持续伤害余量以内（docs/38 §1.11）
	var amp: float = corrode_amp_mult if g.t < corrode_amp_until else 1.0
	lose_hp(nt * amp, "corrode")
	if bt > 0.0:
		lose_hp(minf(bt * amp, room), "corrode", true)


## 受击扣血（伤害类型见 g.in_type、来源见 g.dmg_src）：藏品承伤、护甲、法抗算完后走 lose_hp。返回实际扣掉的生命
func hurt(amount: float, ignore_armor := false, boss := false) -> float:
	if g.in_type[1] != "真实":
		amount *= g.rfx.taken_mult()
	if g.in_type[1] == "物理":
		amount *= g.phys_taken_mult   # 硬化（docs/83）：所有物理伤害按比例减，在固定减伤之前；不吃护甲的冲击环也减
	var pre := amount
	if not ignore_armor and g.in_type[1] == "物理":
		amount = max(1.0, amount - g.armor)
	elif g.in_type[1] == "法术":
		amount = max(1.0, amount * (1.0 - minf(g.arts_res, 0.7)))
	_armor_cf(pre, amount, not ignore_armor and g.in_type[1] == "物理")
	if boss:
		preload("res://scripts/run/boss_diag.gd").on_phit(g, amount, pre)
	amount = lose_hp(amount, g.dmg_src, boss)
	if g.ult != null:
		g.ult.on_hurt(amount, {})   # 连携 C 类判定：近战命中 / 一次大伤害
	g.rfx.on_hurt(g.dmg_src == "nerve", amount)
	g.invuln = 0.45
	g.hurt_flash = 0.2
	# 受击反馈按伤害占最大生命的比例分级
	var sev := clampf(amount / g.max_hp / 0.12, 0.0, 1.0)
	g.hurt_vignette = 0.6 + 0.4 * sev
	g.red_flash = maxf(g.red_flash, 0.12 + 0.25 * sev)
	g.hp_shake = 0.35
	g.head_bar_t = 2.5
	g.vfx.shake_screen(0.55 + 0.8 * sev)
	g.vfx.stop(0.045 + 0.06 * sev, "hurt")
	Sfx.play("hurt", 3.0 + 3.0 * sev, 1.0 - 0.2 * sev, 0.05)   # 打击感检查：原来实际只有 -24 左右，比命中声还轻，+4 dB
	# 重击（单发 ≥ 最大生命 12% × fx/hurt_heavy_sev，Boss 招式基本都到）：再叠一层次低频 hurt_heavy，并把配乐低通压到 fx/hurt_duck_hz、
	# 保持 fx/hurt_duck_t 秒（music_director 读 g.hurt_duck，world.update_player_feel 按真实时间衰减）。docs/53
	if sev >= Bal.v("fx/hurt_heavy_sev", 0.5):
		Sfx.play("hurt_heavy", Bal.v("fx/hurt_heavy_db", -8.0), 1.0, 0.05)   # 正式次低频层（gen_sfx_hitfeel.py）；缺文件时 sfx.ALT 借 boom ×0.7 −2 dB
		g.hurt_duck = Bal.v("fx/hurt_duck_t", 0.4)
		Sfx.duck_music(Bal.v("fx/hurt_duck_hz", 900.0))
	Pad.rumble(0.25 + 0.35 * sev, 0.1 + 0.6 * sev, 0.12 + 0.12 * sev)
	g.vfx.sparks(g.ppos + Vector2(0, -24), Vector2.UP, Color(1.0, 0.3, 0.35), 6 + int(8 * sev), 220.0)
	g.fx.append({"kind": "ring", "pos": g.ppos + Vector2(0, -10), "r": 40.0 + 30.0 * sev, "life": 0.25, "max": 0.25, "col": Color(1.0, 0.3, 0.35)})
	if amount >= 1.0 or not boss:   # Boss 这一击被主控保护截到不足 1 点（2 秒合计已满、满血保护）时不飘「-0」
		g.vfx.add_text(g.ppos + Vector2(randf_range(-14, 14), -84), "-%d" % int(amount), Color(1.0, 0.3, 0.3), int(20 + 10 * sev))
	# 首次跌破 30%：时间短暂变慢 + 警告
	if g.hp > 0.0 and g.hp < g.max_hp * 0.3 and not low_warned:
		low_warned = true
		g.vfx.stop(0.35, "low_hp", true)
		g.vfx.show_banner("生命垂危！")
	elif g.hp > g.max_hp * 0.45:
		low_warned = false
	return amount


## 物理减伤遥测（docs/83 §4，只记账、不读随机数）：按 0–4 / 4–8 / 8 分钟以后三段，记受击总量（护甲 / 法抗之后、主控保护之前）、
## 吃护甲的物理受击（护甲前 / 后），以及「再多 2 / 4 / 8 点护甲」时这些物理受击会是多少。BALANCE 记录 armor_cf 字段
var armor_cf := {}

func _armor_cf(pre: float, post: float, phys: bool) -> void:
	var seg: String = "m0" if g.t < 240.0 else ("m4" if g.t < 480.0 else "m8")
	if not armor_cf.has(seg):
		armor_cf[seg] = {"all": 0.0, "n": 0, "phys_n": 0, "phys_pre": 0.0, "phys": 0.0, "a2": 0.0, "a4": 0.0, "a8": 0.0, "armor": 0.0}
	var c: Dictionary = armor_cf[seg]
	c.all += post
	c.n += 1
	if phys:
		c.phys_n += 1
		c.phys_pre += pre
		c.phys += post
		c.armor += g.armor
		for k in [2, 4, 8]:
			c["a%d" % k] += maxf(1.0, pre - g.armor - float(k))


## 缩圈：预告 20 秒 → 收缩 25 秒 → 稳定，直到下一轮；圈外为「黑潮」。
## 1.1（用户决定）：Boss 在场时缩圈计时整体暂停（预告 / 收缩停在原处，Boss 倒下后接着走）；出圈后前 2 秒不掉血
func update_zone(dt: float) -> void:
	# 最终 Boss 场地冻结后不再走缩圈日程（也不弹「黑潮停滞」横幅），只把圈插值到场地；圈外判定照常走下面那段（docs/38 §1.7）
	if g.zone_frozen:
		_arena_step(dt)
	elif not _zone_schedule(dt):
		return
	# 圈外：黑潮伤害 + 灯火流失 + 神经损伤
	var out := g.ppos.distance_to(g.zone_c) - g.zone_r
	if out > 0.0 and g.state == g.S.PLAY and not g.squad.in_sanctuary(g.ppos):
		zone_out_t += dt
		var lz: float = g.lamp
		g.lamp = maxf(0.0, g.lamp - 6.0 * dt * g.lamp_loss_mult)
		g.telemetry.lamp_note("圈外", g.lamp - lz)
		if zone_out_t < ZONE_GRACE:
			return
		var dps: float = (2.5 + 1.5 * max(zone_phase, 0)) * (1.0 + minf(out / 300.0, 1.0))
		lose_hp(dps * dt, "zone")
		zone_hurt_t -= dt
		if zone_hurt_t <= 0.0:
			zone_hurt_t = 0.8
			g.hurt_flash = maxf(g.hurt_flash, 0.08)
			g.head_bar_t = 2.0
			g.vfx.add_text(g.ppos + Vector2(0, -84), "黑潮", Color(0.8, 0.4, 1.0), 16)
	elif g.state == g.S.PLAY:
		zone_out_t = 0.0   # 回到圈内（或庇护所）：缓冲重置


## 缩圈日程（原 update_zone 前半段，逻辑不变）：返回 false = 黑潮还没开始，本帧不做圈外判定
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
			g.vfx.show_banner("Boss 在场：黑潮停滞" if paused else "黑潮再度涌动")
	if not paused:
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
	return true
## ---- 最终 Boss 场地（docs/38 §1.7，B1 第二批）
## 最终 Boss 登场时 freeze_zone(arena_r)：黑潮圈 3 秒内平滑变到场地半径；主控离新圈边不足 100（或在圈外）就把圆心往主控挪；
## 黑潮还没开始（zone_state == 0）时以主控为圆心新建。冻结后 zone_state = 3、zone_next_* 同步成场地，机器人读到的边界与实际一致。
var arena_from_c := Vector2.ZERO
var arena_from_r := 0.0
var arena_t := 0.0


func freeze_zone(r: float) -> void:
	if g.zone_state == 0:
		g.zone_c = g.ppos
		g.zone_r = r + 400.0
		zone_phase = -1
	var c: Vector2 = g.zone_c
	var d: float = g.ppos.distance_to(c)
	if d > r - 100.0 and d > 0.001:
		c = g.ppos + (c - g.ppos) / d * (r - 100.0)
	arena_from_c = g.zone_c
	arena_from_r = g.zone_r
	arena_t = 0.0
	g.zone_next_c = c
	g.zone_next_r = r
	g.zone_state = 3
	g.zone_t = 0.0
	g.zone_frozen = true
	# 场地整理仅作后台规则，不暴露禁生成区域或播放净化演出。
	var remaining: Array = []
	for m in g.mires:
		if not mire_blocked(m.pos, float(m.get("maxr", m.r))):
			remaining.append(m)
	g.mires = remaining


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


## 最终 Boss 场地是禁生成圆区；最大半径与圆区相交（含相切）就禁止整片生成。
func mire_blocked(pos: Vector2, radius: float = 0.0) -> bool:
	return g.zone_frozen and pos.distance_squared_to(g.zone_next_c) <= pow(maxf(0.0, g.zone_next_r) + maxf(0.0, radius), 2.0)


func _arena_step(dt: float) -> void:
	if arena_t >= 3.0:
		return
	arena_t = minf(arena_t + dt, 3.0)
	var k := smoothstep(0.0, 1.0, arena_t / 3.0)
	g.zone_c = arena_from_c.lerp(g.zone_next_c, k)
	g.zone_r = lerpf(arena_from_r, g.zone_next_r, k)


## 把 Boss 本体、召唤物 / 落点的生成点约束在场地内、离圈边 ≥ margin；场地没冻结时原样返回
func arena_clamp(p: Vector2, margin := 80.0) -> Vector2:
	if not g.zone_frozen:
		return p
	var lim: float = maxf(0.0, g.zone_next_r - margin)
	var v: Vector2 = p - g.zone_next_c
	return p if v.length() <= lim else g.zone_next_c + v.normalized() * lim


## 主控指向安全区圆心的单位向量（圈外方向提示用）
func zone_dir() -> Vector2:
	return (g.zone_c - g.ppos).normalized() if g.zone_state != 0 else Vector2.ZERO


## 护盾抵挡一次伤害：碎裂特效，可选冲击波与回复
func shield_block(dmg := 0.0) -> void:
	g.shield -= 1
	g.telemetry.blocks += 1
	g.telemetry.shield_abs += dmg   # 遥测：层数抵挡掉的原始伤害（护盾复核 10-30）
	g.shield_flash = 0.3
	g.invuln = maxf(g.invuln, Bal.v("shield/block_invuln", 0.0))   # 抵挡后的无敌秒数（10-30 用户定取消，缺省 0；碎裂反馈保留）
	if g.shield < g.shield_max and g.shield_cd <= 0.0:
		g.shield_cd = g.shield_every * Bal.v("shield/every_x", 1.0)
	Sfx.play("stake_shatter", -9.0, 1.5, 0.0)   # 轻脆碎裂声（原 dodge 呼声读不出「碎了」）
	g.vfx.add_text(g.ppos + Vector2(0, -84), "护盾抵挡", Color(1.0, 0.9, 0.7), 16)
	# 碎片 / 闪环 / 无敌微光：render/world.gd draw_shield 比对层数变化自己画（淡金色，用户 10-28 重画）
	if g.shield_heal:
		heal(g.max_hp * 0.03, "藏品")
	if g.shield_burst:
		for j in g.enemies_sys.query(g.ppos, 140.0):
			var e: Dictionary = g.enemies[j]
			if not e.dead and e.pos.distance_to(g.ppos) < 140.0:
				damage(e, 60.0 * g.dmg_mult * enemy_hp_time_mult())
				if not e.boss:
					g.enemies_sys.apply_kb(e, (e.pos - g.ppos).normalized() * 420.0)
		g.fx.append({"kind": "explode", "pos": g.ppos, "r": 140.0, "life": 0.4, "max": 0.4, "col": Color(0.5, 0.85, 1.0)})
		g.vfx.shake_screen(0.6)
	if g.rfx.rule("shield_shatter") > 0:
		meta_shatter()


## 认知塑造「危机感」末节（docs/109 §14 v5）：护盾被击碎时反震，周围 meta/shatter_r 内的敌人受到 队长攻击 × meta/shatter_mult 的物理伤害并被击退（Boss 不击退）
func meta_shatter() -> void:
	var r: float = Bal.v("meta/shatter_r", 140.0)
	var dmg: float = Meta.leader_atk(g) * Bal.v("meta/shatter_mult", 3.0)
	var hd: Dictionary = make_hit("认知塑造")
	for j in g.enemies_sys.query(g.ppos, r + 24.0):
		var e: Dictionary = g.enemies[j]
		if not e.dead and not e.chest and e.pos.distance_to(g.ppos) < r + e.r:
			damage(e, dmg, hd)
			if not e.boss:
				g.enemies_sys.apply_kb(e, (e.pos - g.ppos).normalized() * Bal.v("meta/shatter_kb", 420.0))
	g.fx.append({"kind": "explode", "pos": g.ppos, "r": r, "life": 0.4, "max": 0.4, "col": Color(0.7, 0.9, 1.0)})
	g.vfx.add_text(g.ppos + Vector2(0, -100), "反震", Color(0.7, 0.9, 1.0), 15)


## 这次伤害是否算「追击」（docs/35）
func is_followup(h: Dictionary) -> bool:
	for tg in h.tags:
		if tg in FOLLOWUP_TAGS:
			return true
	return false


## 敌人生命的时间倍率（不含难度）：藏品的直接伤害按它缩放，保证各时段同样「有感」
func enemy_hp_time_mult() -> float:
	var hk: float = Bal.v("enemy/hp_knee", 480.0)
	return 1.0 + minf(g.t, hk) / Bal.v("enemy/hp_div", 110.0) + maxf(g.t - hk, 0.0) / Bal.v("enemy/hp_late_div", 120.0)


## 主控生命回复的时间倍率（docs/82，10-13）：1 + min(t, regen_knee) / regen_div。敌人攻击随时间涨（enemy/dmg_div），
## 自身回复原来恒定，无医疗编队 6–9 分钟靠它撑不住；regen_div = 0 关（恒为 1）
func regen_time_mult() -> float:
	var dv: float = Bal.v("sustain/regen_div", 0.0)
	if dv <= 0.0:
		return 1.0
	return 1.0 + minf(g.t, Bal.v("sustain/regen_knee", 480.0)) / dv


## 主控实际每秒回复（生命 / 秒）：game._update 按它回血，属性面板、「自愈」卡预览、招募卡都读它，保证三处一致（docs/83 §2）。
## add_flat / add_pct：预览「再加一张卡」时额外加进 regen / regen_pct 的量
func regen_per_sec(add_flat := 0.0, add_pct := 0.0, max_hp := -1.0) -> float:
	var mh: float = g.max_hp if max_hp < 0.0 else max_hp
	var v: float = (g.regen + add_flat + (g.regen_pct + add_pct) * mh) * g.heal_mult * regen_time_mult() * song_heal_mult()
	# 认知塑造「生命感悟」末节：队长生命低于 meta/low_regen_at 最大生命时回复 × meta/low_regen_mult
	if g.rfx.rule("low_hp_regen") > 0 and g.hp < mh * Bal.v("meta/low_regen_at", 0.35):
		v *= Bal.v("meta/low_regen_mult", 2.0)
	return v


## 构造伤害描述符（extra_tags 追加本次特有标签，如 empowered）；不写全局，直接传给 damage(e, dmg, h)（docs/101 B7 ⑤）
func make_hit(src: String, extra_tags: Array = []) -> Dictionary:
	var base: Dictionary = g.hit_src.get(src, {"emitter": "operator", "origin": "core", "range": "近战", "kind": "物理", "tags": []})
	return {"src": src, "emitter": base.emitter, "origin": base.origin, "range": base.range, "kind": base.kind, "tags": base.tags + extra_tags,
		"class": base.get("class", ""), "op": base.get("op", "")}


## 设置「当前」伤害描述符 g.hit：干员门面 op_api.log_hit → deal_damage 用（deal_damage 把 g.hit 显式传给 damage）
func hit(src: String, extra_tags: Array = []) -> void:
	g.hit = make_hit(src, extra_tags)


## 可按难度档覆盖的 enemy 段旋钮（ctrl_start / frost_max / affix_start / affix_max）：本档 dmod 里 ≥ 0 就用它，否则读 balance.json enemy/<key>
func enemy_knob(key: String, def: float) -> float:
	var v := float(g.dmod.get(key, -1.0))
	return v if v >= 0.0 else Bal.v("enemy/" + key, def)


## ---- 小怪控制（用户 9/29「后期小怪加控制」；机制在这里，数值都是旋钮，缺省 enemy/ctrl_start = 永不 = 关）
## 寒霜 cold：有效命中叠层，每层移速 −frost_slow、攻速 −frost_aspd，最多 frost_max 层，frost_dur 秒整体清零；
##   满层时冻结 frost_root 秒（不能移动，可以攻击，冲刺挣脱），之后 frost_immune 秒不再叠层。
## 束缚 root：巢涌者触须 / 巨骸踏地等预警招式命中后 root_hit 秒不能移动（同样冲刺挣脱）。冻结 / 束缚之后 root_immune 秒不再被硬控；
##   任何 Boss 在场时一律换成减速（延续「Boss 战不硬控主控」）。
## 侵蚀创口 wound：有效命中叠层，每层受治疗 −wound_heal_cut、每秒掉 wound_dot 最大生命，最多 wound_max 层，wound_dur 秒；可被净化。
## 合计上限：寒霜 + 冰霜移速最多 −ctrl_move_cap（45%），寒霜攻速最多 −ctrl_aspd_cap（30%）。所有掉血走 lose_hp，受 2 秒合计上限保护。
func ctrl_on() -> bool:
	return g.t >= enemy_knob("ctrl_start", 1.0e9)


func ctrl_slow() -> float:
	var m: float = (0.6 if g.frost > 0.0 else 1.0) * (1.0 - Bal.v("enemy/frost_slow", 0.12) * g.cold)
	return maxf(m, 1.0 - Bal.v("enemy/ctrl_move_cap", 0.45))


func add_cold(n: int) -> void:
	if n <= 0 or g.cold_immune > 0.0:
		return
	var mx: int = int(enemy_knob("frost_max", 3.0))
	g.cold = mini(g.cold + n, mx)
	cold_cat = ctrl_hit_cat
	g.cold_t = Bal.v("enemy/frost_dur", 3.0)
	sync_cold()
	if g.cold >= mx:
		g.cold_immune = Bal.v("enemy/frost_immune", 4.0)
		add_root(Bal.v("enemy/frost_root", 0.6), "冻结")


## 寒霜的攻速减益走 stats 的 "cold" 来源（全队 op_aspd）；层数变了就调一次，净化清层后也要调
func sync_cold() -> void:
	g.stats.remove_source("cold")
	if g.cold > 0:
		g.stats.add(&"op_aspd", "mult", maxf(1.0 - Bal.v("enemy/frost_aspd", 0.08) * g.cold, 1.0 - Bal.v("enemy/ctrl_aspd_cap", 0.30)), "cold")
	g.sync_stats()


func add_root(t: float, label: String) -> void:
	if t <= 0.0 or g.root_immune > 0.0 or g.root_t > 0.0:
		return
	if g.spawner.boss_alive():
		slow_leader("root", t, Bal.v("boss/stun_as_slow_mult", 0.7), ctrl_hit_cat)
		return
	g.root_t = t
	root_cat = ctrl_hit_cat
	root_kind = label
	if label == "冻结":
		_ctrl_entry(root_cat).freeze_n += 1
	g.root_immune = t + Bal.v("enemy/root_immune", 3.0)
	g.vfx.add_text(g.ppos + Vector2(0, -96), label, Color(0.6, 0.9, 1.4) if label == "冻结" else Color(0.8, 0.5, 1.2), 18)


## 凋亡损伤（docs/49b §4.4，用户 9/29）：有效命中累积量表，满 100 时全队技能充能暂停 enemy/apop_pause 秒（上限 4 秒）后清零；
## 离开来源 1 秒后每秒回落 apop_decay；冲刺清 apop_dash；来源死了就不再累积；净化清 g.apop / g.apop_t。
## 只来自 enemies.json 写了 apop_hit 的敌人（伊祖米克的子代、伊祖米克），小怪按 ctrl_start 生效，Boss 来源不受 ctrl_start 限制
func add_apop(v: float) -> void:
	if v <= 0.0 or g.apop_t > 0.0:
		return
	g.apop += v
	g.apop_hold = 0.0
	if g.apop >= 100.0:
		g.apop = 0.0
		g.apop_t = minf(Bal.v("enemy/apop_pause", 4.0), 4.0)
		g.vfx.add_text(g.ppos + Vector2(0, -104), "凋亡 · 技力暂停", Color(0.6, 1.0, 0.6), 18)
		Sfx.play("apop_pause", -6.5, 1.0, 0.0)


## 每帧（enemies.update_status）：控制计时递减、创口掉血
func update_ailments(dt: float) -> void:
	var apop_was := g.apop_t > 0.0
	g.apop_t = maxf(0.0, g.apop_t - dt)
	if apop_was and g.apop_t <= 0.0:
		Sfx.play("apop_resume", -8.4, 1.0, 0.0)   # 技力恢复
	g.apop_hold += dt
	if g.apop > 0.0 and g.apop_hold > 1.0:
		g.apop = maxf(0.0, g.apop - Bal.v("enemy/apop_decay", 15.0) * dt)
	g.root_t = maxf(0.0, g.root_t - dt)
	g.root_immune = maxf(0.0, g.root_immune - dt)
	g.cold_immune = maxf(0.0, g.cold_immune - dt)
	if g.cold > 0:
		g.cold_t -= dt
		if g.cold_t <= 0.0:
			g.cold = 0
			g.cold_t = 0.0
			sync_cold()
	g.afflict.tick_wound(dt)


## ---- 地面形状统一判定（docs/38 §1.9「画即判」、docs/48 §1 第 1 项）：预警圈、冲击环、寒冰领域、抛石落点、溟痕都画成
## 纵向 ×GROUND_Y 的椭圆；判定点统一用主控脚底，纵向距离先除以 GROUND_Y 再和半径比。游戏判定与机器人走位共用
const GROUND_Y := 0.72


func ground_d(p: Vector2, c: Vector2) -> float:
	var v: Vector2 = p - c
	return Vector2(v.x, v.y / GROUND_Y).length()


## ---- Boss 阶段卡点与每幕最短时长（docs/38 §1.3，B1 ①；2026-09-27 用户确认，不做力竭）
## 刻度在 enemies.json 的 gates（最大生命比例，从高到低）；没写时中期 [0.5]、最终 [0.66, 0.33]。
## 只在「这一击前高于刻度、这一击后不高于刻度」时触发，伤害截在刻度上：
##   这一幕已满最短时长 → 立刻过卡点；没满 → 停在刻度上升起阶段护盾，满了再过。
## 过卡点：0.8 秒不受伤、取消它瞄准主控的预警、0.8 秒内不出新招；最终 Boss 另掉回复和灯油。
## 总开关 boss/gates_on（1 = 开）。每幕计时 e.act_t 只在 Boss 可受伤时走（boss_ai.gd 调 gate_update）。
func gate_init(e: Dictionary, type: String) -> void:
	var d: Dictionary = D.ENEMIES.get(type, {})
	var fin: bool = g.spawner.is_final_boss_type(type)
	var gl: Array = d.get("gates", [0.66, 0.33] if fin else [0.5])
	e.gates = gl.duplicate() if Bal.v("boss/gates_on", 1.0) > 0.0 else []
	var am = d.get("act_min", Bal.v("boss/act_min_final", 13.0) if fin else Bal.v("boss/act_min_mid", 6.0))
	# act_min 可写数组 = 逐幕最短时长（过一道卡点取下一项；多出的项由 Boss 脚本自己用，例如偏执泡影破茧后一段，docs/170 §3w）
	e.act_mins = (am as Array).duplicate() if am is Array else []
	e.act_min = float(e.act_mins.pop_front()) if am is Array else float(am)
	e.act_t = 0.0
	e.gate_hold = false
	e.gate_inv = 0.0
	e.gate_final = fin
	e.shield_t = 0.0   # 阶段护盾累计秒数（报表用）
	e.last_done = e.gates.is_empty()   # 关掉卡点时最后一幕也不守
	e.gates_passed = 0
	# 破绽与韧性（§1.5，B1 ③）
	e.break_t = 0.0
	e.tough = 0.0
	e.tough_need = Bal.v("boss/tough_first", 25.0)
	# 伤害预算（§1.4，B1 ④）：按结构最短用时算补充速度，开局存满 4 秒
	var ng: int = e.gates.size()
	var tmin: float = e.act_min * (ng + 1) + Bal.v("boss/gate_inv", 0.8) * ng
	if am is Array:
		tmin = Bal.v("boss/gate_inv", 0.8) * ng
		for x in am:
			tmin += float(x)
	e.budget_rate = e.maxhp / maxf(1.0, tmin * 0.8)
	e.budget = e.budget_rate * Bal.v("boss/budget_store", 4.0)


func gate_clamp(e: Dictionary, dmg: float) -> float:
	var gates: Array = e.get("gates", [])
	if dmg <= 0.0:
		return dmg
	if gates.is_empty():
		# 最后一幕也有最短时长（§1.3）：没满时停在这一幕血池剩 boss/last_hold（3%）处升护盾，满了护盾碎、剩下的照常打；只守一次
		if e.get("last_done", true):
			return dmg
		var lh: float = e.maxhp * Bal.v("boss/last_hold", 0.03)
		if e.hp > lh and e.hp - dmg <= lh and e.act_t < e.act_min:
			dmg = e.hp - lh
			e.gate_hold = true
			g.vfx.add_text(e.pos + Vector2(0, -e.r - 36.0), "阶段护盾", UI.GOLD, 18)
		return dmg
	var line: float = e.maxhp * float(gates[0])
	if e.hp > line and e.hp - dmg <= line:
		dmg = e.hp - line
		if e.act_t >= e.act_min:
			gate_pass(e)   # 这一击照样结算（截在刻度上），之后 0.8 秒不受伤
		else:
			e.gate_hold = true
			g.vfx.add_text(e.pos + Vector2(0, -e.r - 36.0), "阶段护盾", UI.GOLD, 18)
	return dmg


## 每帧由 boss_ai.gd 调用：可受伤时推进这一幕的计时；护盾撑满最短时长后过卡点
func gate_update(e: Dictionary, dt: float) -> void:
	if e.get("gate_inv", 0.0) > 0.0:
		e.gate_inv = maxf(0.0, e.gate_inv - dt)
	if e.get("break_t", 0.0) > 0.0:
		e.break_t = maxf(0.0, e.break_t - dt)   # 破绽时长固定，不受 control_mult 影响
	if e.has("budget_rate"):
		e.budget = minf(e.budget + e.budget_rate * dt, e.budget_rate * Bal.v("boss/budget_store", 4.0))
	if not e.invuln and not e.get("coma", false):
		e.act_t = e.get("act_t", 0.0) + dt
	# 「血量或秒数先到先换幕」（docs/49d，缺省关）：这一幕打满 boss/act_max_mid / act_max_final 秒还没到刻度，就直接换幕
	var amax: float = Bal.v("boss/act_max_final" if e.get("gate_final", false) else "boss/act_max_mid", 0.0)
	if amax > 0.0 and not e.get("gates", []).is_empty() and not e.get("gate_hold", false) and e.act_t >= amax and not e.invuln:
		e.hp = minf(e.hp, e.maxhp * float(e.gates[0]))
		gate_pass(e)
	if e.get("gate_hold", false):
		e.shield_t += dt
		if e.act_t >= e.act_min:
			if e.gates.is_empty():
				e.gate_hold = false   # 最后一幕的护盾：到时碎掉，不给过卡点的无敌和掉落
				e.last_done = true
			else:
				gate_pass(e)


## ---- 破绽与韧性（docs/38 §1.5，B1 ③）。破绽只有一种状态：e.break_t > 0 时受伤 ×boss/break_mult（1.4）；
## Boss 自己的硬直一律写 e.break_t（不写 e.stun），boss_ai.gd 判断能否出招时同时看它。
## 韧性只对白名单 Boss（enemies.json 写 "tough": true；B1 时名单为空，纵切重做时逐只加入）：每打掉 1% 最大生命积 1 点，
## 满 tough_need（首次 25，之后 ×1.5）进 boss/break_t 秒破绽；玩家的眩晕由 enemies.gd 的钩子换成韧性（1 秒 ≈ 5 点）后清零。
## 击退免疫要等白名单 Boss 的冲锋改用脚本位移 e.move（§1.14）后再加，现在骑士等 Boss 的冲锋还写 e.kb。
func tough_on(e: Dictionary) -> bool:
	return e.boss and bool(D.ENEMIES.get(e.type, {}).get("tough", false))


func add_tough(e: Dictionary, pts: float) -> void:
	if e.break_t > 0.0 or pts <= 0.0:
		return
	e.tough += pts
	if e.tough >= e.tough_need:
		e.tough = 0.0
		e.tough_need *= 1.5
		start_break(e, Bal.v("boss/break_t", 3.0))
		Sfx.play("break_open", 0.0, 1.0, 0.0)   # 韧性打满、露出破绽


func start_break(e: Dictionary, t: float) -> void:
	e.break_t = maxf(e.break_t, t)
	e.brk_len = e.break_t   # 破绽总长（render/break_ring 倒计时弧用）
	if final_break_quiet(e):
		return
	g.vfx.add_text(e.pos + Vector2(0, -e.r - 36.0), "破绽", UI.GOLD, 20)


## 最终 Boss 破绽不写字（用户 10-28；中期 Boss 照旧，玩家在那里学会破绽）：boss/break_text_final 0 = 不写（缺省），1 = 恢复。
## 头顶读秒（world）、伤害数字前缀（vfx）、本函数的「破绽」弹字都读它；画面由 render/break_ring 的金环 + 倒计时弧表示
func final_break_quiet(e: Dictionary) -> bool:
	return Bal.v("boss/break_text_final", 0.0) <= 0.0 and g.spawner.is_final_boss_type(str(e.get("type", "")))


## ---- 伤害预算（docs/38 §1.4，B1 ④；保险丝，默认关 boss/budget_on 0）：隐形令牌桶，额度用完后超出部分只算 boss/budget_over（35%）；
## 破绽期间不计。玩家看不到。只有批跑发现阶段护盾出现得太频繁时才打开
func budget_clamp(e: Dictionary, dmg: float) -> float:
	if Bal.v("boss/budget_on", 0.0) <= 0.0 or e.break_t > 0.0 or not e.has("budget"):
		return dmg
	if dmg <= e.budget:
		e.budget -= dmg
		return dmg
	var over: float = dmg - e.budget
	e.budget = 0.0
	return dmg - over + over * Bal.v("boss/budget_over", 0.35)


func gate_pass(e: Dictionary) -> void:
	if e.dead or e.get("gates", []).is_empty():
		return
	Sfx.play_cue("phase", e.type, "start")   # 过卡点：阶段音（docs/38 §8.11）
	e.gates.pop_front()
	e.gates_passed += 1
	e.gate_hold = false
	e.act_t = 0.0
	if not e.get("act_mins", []).is_empty():
		e.act_min = float(e.act_mins.pop_front())
	e.gate_inv = Bal.v("boss/gate_inv", 0.8)
	e.wind = maxf(e.get("wind", 0.0), e.gate_inv)   # 0.8 秒内不出新招
	g.warns = g.warns.filter(func(w): return not is_same(w.owner, e) or w.done)
	g.fx.append({"kind": "ring", "pos": e.pos, "r": e.r * 2.2, "life": 0.5, "max": 0.5, "col": g.vfx.boss_color(str(e.type))})   # 专属色（docs/142b §9 特效精修）
	Sfx.play("roar", -4.0, 1.1, 0.0)
	var bh = g.bai.boss(e.type)   # Boss 过卡点钩子（偏执泡影坠落进二阶段，docs/101 B1c）
	if bh != null:
		bh.on_gate(e)
	if e.gate_final:
		# 最终 Boss 每过一道卡点：回复道具与灯油各一个（boss/gate_drop_*，小数部分按概率）
		for kd in [["heal", "boss/gate_drop_heal", 1.0], ["oil", "boss/gate_drop_oil", 15.0]]:
			var n: float = Bal.v(kd[1], 1.0)
			var cnt := int(n) + (1 if g.rng_drop.randf() < n - floorf(n) else 0)
			for k in cnt:
				g.pickups.drop(e.pos + Vector2.from_angle(g.rng_drop.randf() * TAU) * 40.0, kd[0], kd[2])


func damage(e: Dictionary, dmg: float, h: Dictionary = {}) -> void:
	if g.prof_on:   # --prof：伤害结算总耗时（含嵌套触发，docs/50 §35）
		var _t0 := Time.get_ticks_usec()
		_dmg_depth += 1
		_damage(e, dmg, h)
		_dmg_depth -= 1
		if _dmg_depth == 0:
			g.prof_add("dmg_total", _t0)
		return
	_damage(e, dmg, h)


var _dmg_depth := 0
var quiet := false   # 静默击杀（arch_review_1029 P1-3 / docs/198 §7.4）：开着时普通怪倒下不播击杀爆点 / 击杀音 / 死亡帧条 / 碎屑（精英、Boss 照常）；终结技一次清屏用，缺省关

func _damage(e: Dictionary, dmg: float, h: Dictionary = {}) -> void:
	if e.dead or e.get("friendly", false):
		return
	if h.is_empty():
		h = g.hit   # 没传描述符：沿用当前的（旧调用方式）；之后全程只读局部 h（docs/101 B7 ⑤）
	var bh = g.bai.boss(e.type)   # Boss 行为脚本（受击钩子 block_damage / absorb_damage / on_damaged / on_lethal，docs/101 B1c）；不是 Boss 为 null
	if bh != null and bh.block_damage(e):
		return
	# 灯火照亮：光中的敌人受到的伤害 +25%（流明光弹的「照亮」e.lit 同样视为在灯光内）
	if e.pos.distance_squared_to(g.ppos) < g.lamp_r() * g.lamp_r() or e.get("lit", 0.0) > 0.0:
		if g.bot != null and e.get("lit", 0.0) > 0.0 and e.pos.distance_squared_to(g.ppos) >= g.lamp_r() * g.lamp_r():
			g.telemetry.sus_seg().lit += dmg * 0.25   # docs/88 遥测：只因「照亮」多打的伤害（只在 --balance 下记）
		dmg *= 1.25
	if bh != null and bh.absorb_damage(e, dmg):
		return
	# 过卡点后的 0.8 秒无敌 / 阶段护盾：伤害全部挡掉，不飘「无效」（docs/38 §1.3）
	if e.boss and (e.get("gate_inv", 0.0) > 0.0 or e.get("gate_hold", false)):
		return
	if e.get("burst_w", 0.0) > 0.0:
		return   # 囊海爬行者鼓胀期间无敌（enemies.gd）：不飘字、不累计
	if e.invuln:
		g.vfx.immune_text(e)   # 伊祖米克学习期飘「学习中」，其余无敌不再飘「无效」（docs/38 §1.15，显示逻辑在 vfx）
		return
	if e.chest and e.hidden:
		e.hidden = false
		g.spawner.reveal_mimic(e)
		return
	var _pf: bool = g.prof_on and _dmg_depth == 1
	var _pt := Time.get_ticks_usec() if _pf else 0
	var ty: Array = [h.range, h.kind]
	var weak_hit := false
	# 出手干员：流派藏品（docs/181）把近战 / 远程 / 追击倍率、弱点与低血加成挂在 lane:<键> 作用域上，按干员取值（全局 + 本人作用域）
	var hop = g.squad.get_op(str(h.get("op", ""))) if h.has("op") and g.squad != null else null
	if ty[1] != "真实":
		# 养育者基因种（docs/57 P6）：无视敌人一部分防御（e.def < 1 的部分按比例折回）
		var edef: float = e.def
		# 原作的防御只折算物理承伤；不改变法术与真实伤害。
		if ty[1] == "物理":
			var ed: Dictionary = D.ENEMIES.get(e.type, {})
			if float(e.get("set_t", 0.0)) > 0.0:
				edef *= float(ed.get("entrench_phys_taken", 1.0))
			if e.enraged:
				edef *= float(ed.get("enrage_phys_taken", 1.0))
		if float(e.get("seal_t", 0.0)) > g.t and e.get("affix", "") == "armor":
			edef /= Bal.v("enemy/affix_armor", 0.75)   # 封印（docs/61 §15 st.seal）：甲壳词条失效
		var pierce: int = g.rfx.rule("def_pierce")
		if pierce > 0 and edef < 1.0:
			edef = 1.0 - (1.0 - edef) * (1.0 - 0.01 * pierce)
		dmg *= edef * g.rfx.dmg_extra()
		# 分类型抗性（enemies.json phys_taken / arts_taken，缺省 1 = 不变）：偏执泡影按原作防御 700 / 法抗 70（docs/170 §3v）
		var edt: Dictionary = D.ENEMIES.get(e.type, {})
		dmg *= float(edt.get("phys_taken" if ty[1] == "物理" else "arts_taken", 1.0))
		if e.boss:
			dmg *= g.boss_mult   # “文明的存续”（docs/57 P3）
		elif e.elite:
			dmg *= g.elite_mult   # 认知塑造「攻击性」（docs/109 §4）
		# 弱点：对应类型伤害 +50%（藏品可加成 / 赋予双弱点）
		var wk: String = e.get("weak", "")
		if wk == ty[1] or (wk == "双" and ty[1] != "真实") or (g.rfx.rule("all_weak") > 0):
			dmg *= 1.5 + (hop.stat(&"weak_bonus") if hop != null else g.weak_bonus)
			weak_hit = true
		if hop != null:
			dmg *= hop.stat(&"melee_dmg") if ty[0] == "近战" else hop.stat(&"ranged_dmg")
		else:
			dmg *= g.melee_mult if ty[0] == "近战" else g.ranged_mult
		if e.get("aura_weak", 0.0) > 0.0:
			dmg *= 1.1
		if float(e.get("frag_t", 0.0)) > g.t:   # 铃兰精一「狐火灼印」：frag_t 之前受到的伤害 + frag_v（docs/91 §15；同名取最高）
			dmg *= 1.0 + float(e.frag_v)
		if e.has("tr_t") and float(e.tr_t) > g.t and h.has("op") and str(h.op) != str(e.tr_op):   # 能天使曳光弹标记（docs/202）：其他干员打到被标记的敌人 + tr_v
			dmg *= 1.0 + float(e.tr_v)
		dmg *= g.arts_mult if ty[1] == "法术" else g.phys_mult
		if is_followup(h):
			dmg *= (hop.stat(&"followup_dmg") if hop != null else g.followup_mult) * g.rfx.followup_extra(hop)
		dmg *= g.rfx.hit_mult(h, e)
		# Logos「安魂」：受到的法术伤害 +base.requiem_bonus（缺省 15%，e.requiem_v）；精一「剜魂」叠层时每层 +6%（e.requiem_k，docs/91 §7）
		if ty[1] == "法术" and e.get("requiem", 0.0) > 0.0:
			dmg *= (1.0 + float(e.get("requiem_v", 0.15))) if not e.has("requiem_k") else 1.0 + float(e.requiem_k)
		# 艾雅法拉精一「熔蚀」：melt_t 之前受到的法术伤害 + melt_v（docs/91 §3）
		if ty[1] == "法术" and float(e.get("melt_t", 0.0)) > g.t:
			dmg *= 1.0 + float(e.melt_v)
		var lowb: float = (hop.stat(&"enemy_low_hp_dmg_taken") - 1.0) if hop != null else g.low_hp_bonus
		if lowb > 0.0 and e.hp < e.maxhp * 0.5:
			dmg *= 1.0 + lowb
		if e.boss and g.final_boss != null and is_same(e, g.final_boss):
			dmg *= 1.0 + 0.01 * g.rfx.rule("final_taken") + (0.8 if g.rfx.rule("bone_blood") > 0 else 0.0)
	if _pf:
		_pt = g.prof_add("dm_mult", _pt)
	# 终结技按目标最大生命定档（docs/198 §3.3）：不再吃 Boss 受伤倍率 / 伤害预算 / 单次上限，阶段卡点照旧
	var ult_pct: bool = e.boss and g.ult != null and "终结技" in h.tags
	# Boss 脚本自己的受伤倍率（骑士重甲、破绽期另算，docs/142b §3.1；缺省 1）
	if bh != null and not ult_pct:
		dmg *= bh.taken_mult(e)
	# 破绽受伤加成、伤害预算（§1.5 / §1.4）
	if e.boss and not ult_pct:
		if e.get("break_t", 0.0) > 0.0:
			dmg *= Bal.v("boss/break_mult", 1.4)
			Sfx.play("break_hit", 0.0, 1.0, 0.05)   # 打在破绽上：更重更脆的一层（音频，打击感检查 10/1）
		dmg = budget_clamp(e, dmg)
	# Boss 单次伤害上限（boss/hit_cap_pct，缺省 0 = 关）：一次最多打掉最大生命的这个比例，防爆发一击秒杀；开不开、开多少由数值按实测定
	if e.boss and not ult_pct:
		var hcap: float = Bal.v("boss/hit_cap_pct", 0.04)
		if hcap > 0.0:
			dmg = minf(dmg, e.maxhp * hcap)
	if e.boss:
		dmg = gate_clamp(e, dmg)
	# 潮盾词条：先扣护盾（spawner.roll_affix）
	if e.get("shield_hp", 0.0) > 0.0 and dmg > 0.0 and float(e.get("seal_t", 0.0)) <= g.t:   # 封印期间潮盾不挡（docs/61 §15）
		var ab: float = minf(e.shield_hp, dmg)
		e.shield_hp -= ab
		dmg -= ab
	if _pf:
		_pt = g.prof_add("dm_boss", _pt)
	g.rfx.on_hit(e, h, dmg)
	if _pf:
		_pt = g.prof_add("dm_rfx_on_hit", _pt)
	e.hp -= dmg
	# 认知塑造「攻击性」末节「处决」：普通敌人生命低于 meta/execute_pct、精英低于 meta/execute_elite_pct 时直接击杀（Boss / 补给箱除外）
	if e.hp > 0.0 and not e.boss and not e.chest and g.rfx.rule("execute") > 0 and e.hp < e.maxhp * Bal.v("meta/execute_elite_pct" if e.elite else "meta/execute_pct", 0.08 if e.elite else 0.15):
		dmg += e.hp
		e.hp = 0.0
		g.vfx.add_text(e.pos + Vector2(0, -30), "处决", Color(1.0, 0.55, 0.4), 15)
	if e.get("panic", false):
		e.panic_dmg = float(e.get("panic_dmg", 0.0)) + minf(dmg, e.hp + dmg)   # 遥测 panic_hit：主教慌乱期间掉的血（boss_ai 主教慌乱）
	if e.boss and tough_on(e):
		add_tough(e, minf(dmg, maxf(e.hp + dmg, 0.0)) / e.maxhp * 100.0)
	var eff: float = minf(dmg, maxf(e.hp + dmg, 0.0))
	g.dmg_out[h.src] = g.dmg_out.get(h.src, 0.0) + eff
	if g.ult != null:
		g.ult.on_dmg(eff, h)   # 终结技能量：输出来源（docs/198 §2.1）
	if e.boss and g.bench.live:
		g.bench.boss_hit(e, eff)   # Boss 单场测试台：破绽期输出占比（docs/170）
	if _pf:
		_pt = g.prof_add("dm_misc", _pt)
	g.telemetry.on_dmg(e, eff, dmg, h)   # 作战记录：按干员拆的输出、时间线、最高单次（docs/77）
	if _pf:
		_pt = g.prof_add("dm_telemetry", _pt)
	if h.origin == "relic":
		g.relic_out += eff
	g.dmg_type_out[ty[1]] = g.dmg_type_out.get(ty[1], 0.0) + eff
	for tg in h.tags:
		g.dmg_tag_out[tg] = g.dmg_tag_out.get(tg, 0.0) + eff
	if e.hits == 0:
		e["h0"] = g.t   # 首次受击时刻（遥测 kill_hits 的实际 TTK，docs/116 §6）
	e.hits += 1
	if _pf:
		_pt = g.prof_add("dm_misc", _pt)
	g.vfx.hit_react(e, g.crit_hit, weak_hit, h, dmg)   # 白闪 / 形变 / 命中粒子按普攻、技能、暴击、弱点、破绽分档（纯画面，界面与美术；参数 balance.json fx 段）
	# 伤害数字的位置抖动是纯画面，用 g.vrng：飘字数量取决于画面随机数（上面的「无效」），设置里还能关掉伤害数字，
	# 用 g.rng 会让机器负载 / 玩家设置改变对局随机数（docs/36 §3）
	if g.crit_hit:
		Sfx.play("crit_tick", -6.8, 1.0, 0.05)   # 暴击：清脆的「叮」叠在命中声上
	if _pf:
		_pt = g.prof_add("dm_hit_react", _pt)
	g.vfx.dmg_number(e, dmg, g.crit_hit, weak_hit, h)   # 对 Boss 0.3 秒合并、Boss 战期间普通怪只飘暴击（docs/38 §1.15，显示逻辑在 vfx）
	if _pf:
		_pt = g.prof_add("dm_number", _pt)
	# Boss 受击后（最后的骑士寒冷滑窗、圣徒装填打断）：dmg = 扣完潮盾的伤害，eff = 实际掉的血
	if bh != null:
		bh.on_damaged(e, dmg, eff)
	# "偏执泡影"：首次被控制后失去悬浮，进入第二形态
	# 掠海漂移体被控制后落地，改为近战
	if e.get("hover_lost", false) == false and not e.boss and D.ENEMIES.has(e.type) and D.ENEMIES[e.type].get("hover", false) and e.stun > 0.3:
		e.hover_lost = true
		e.ai = "melee"
		e.spd = 70.0
		e.vis_act = "change"   # 重画 e_skimmer_change 落地变身帧条（纯画面）
		e.vis_t0 = g.t
		g.vfx.add_text(e.pos + Vector2(0, -30), "坠落", Color(0.6, 0.9, 1.0), 16)
	if e.hp <= 0.0:
		# Boss 不死的归零（偏执泡影结茧、最后的骑士寒冰重生、接潮假死）：钩子返回 true 就不走击杀
		if bh != null and bh.on_lethal(e):
			return
		g.telemetry.on_kill_credit(e)   # 作战记录：参与击杀（死前 3 秒内命中过的干员各记一次，docs/77）
		if _pf:
			_pt = g.prof_add("dm_misc", _pt)
		kill(e, h)
		if _pf:
			_pt = g.prof_add("dm_kill", _pt)


## 伊莎玛拉歌声地带（docs/170 §12）：队长站在地带内时受治疗 × (1 − boss/ishar_song_heal_cut)，离开即恢复；地带由 ishar_combos 每帧写 e.song_cut_until
func song_heal_mult() -> float:
	for b in g.bosses:
		if not b.dead and float(b.get("song_cut_until", 0.0)) > g.t:
			return maxf(0.0, 1.0 - Bal.v("boss/ishar_song_heal_cut", 0.7))
	return 1.0


## 治疗唯一入口。mode：HEAL_FULL = 吃 heal_mult、创口、歌声地带；HEAL_NO_MULT = 不吃 heal_mult（补给箱，docs/133）；
## HEAL_PRESCALED = 调用方已乘过 heal_mult 和歌声地带（每秒自身回复 regen_per_sec），这里只补创口。返回实际加的量（含倍率，含溢出部分）
## overheal = false：溢出不喂食腐者手杖（补给箱原来就不算）
const HEAL_FULL := 0
const HEAL_NO_MULT := 1
const HEAL_PRESCALED := 2


func heal(v: float, src: String = "其他", sub: String = "", mode := HEAL_FULL, overheal := true) -> float:
	if mode == HEAL_FULL:
		v *= g.heal_mult * g.afflict.wound_heal_mult() * song_heal_mult()   # 侵蚀创口 / 歌声地带减受治疗
	elif mode == HEAL_NO_MULT:
		v *= g.afflict.wound_heal_mult()
		v *= song_heal_mult()
	else:
		v *= g.afflict.wound_heal_mult()
	var got: float = minf(v, maxf(0.0, g.max_hp - g.hp))
	g.heal_log[src] = float(g.heal_log.get(src, 0.0)) + got
	if g.bot != null and mode == HEAL_FULL:   # 自身回复 / 补给原来不进 sus.heal，保持（金样比 sus）
		g.telemetry.note_heal_sub(src, sub, got, v)   # docs/88 遥测：只在 --balance 下记
	if overheal and v > got:
		g.rfx.on_overheal(v - got)
	g.hp = min(g.max_hp, g.hp + v)
	return v


## h：致命一击的描述符（damage 传来）；给了就设成当前 g.hit——击杀回调（藏品 on_kill、干员 on_kill）里读 g.hit 的旧代码看到的是这一下
func kill(e: Dictionary, h: Dictionary = {}) -> void:
	if not h.is_empty():
		g.hit = h
	g.rfx.on_kill(e, h)
	if e.dead:
		return
	e.dead = true
	if g.ult != null:
		g.ult.on_kill(e)   # 终结技能量：击杀来源
	# 补给箱被打碎
	if e.chest:
		g.telemetry.chests += 1   # 作战记录（docs/77）
		Sfx.play("relic", -6.0, 1.3)
		g.vfx.sparks(e.pos, Vector2.ZERO, Color(1.0, 0.8, 0.4), 12, 220.0)
		for k in g.rng_drop.randi_range(3, 6):
			g.pickups.drop(e.pos + Vector2.from_angle(g.rng_drop.randf() * TAU) * g.rng_drop.randf_range(4.0, 18.0), "ingot", 1.0)
		if g.rng_drop.randf() < 0.3:
			g.pickups.drop(e.pos + Vector2(10, 6), "oil", 15.0)
		# 补给箱回血（docs/133，用户 10-24：参照吸血鬼幸存者靠打可破坏道具回血）：箱子里主要是应急补给（回 crate/pack_pct 最大生命，不吃 heal_mult），
		# 少量磁铁 / 临时护盾；伪装箱形恐鱼（现形）和祭坛不走这里。crate/pack_p 0 = 关（旧行为：只有源石锭 / 灯油）
		var cpk: float = Bal.v("crate/pack_p", 0.9)
		if cpk > 0.0:
			if g.rng_drop.randf() < cpk:
				g.pickups.drop(e.pos + Vector2(-10, -4), "pack", Bal.v("crate/pack_pct", 0.3))
				g.pickups.item_log["pack_drop"] += 1
			if g.rng_drop.randf() < Bal.v("crate/magnet_p", 0.1):
				g.pickups.drop(e.pos + Vector2(14, -6), "magnet", 1.0)
			if g.rng_drop.randf() < Bal.v("crate/shield_p", 0.1):
				g.shield = mini(g.shield + 1, maxi(g.shield_max, 1) + 1)
				g.shield_pop = 0.4
				g.vfx.add_text(e.pos + Vector2(0, -30), "护盾 +1", Color(1.0, 0.9, 0.7), 16)
				g.pickups.item_log["crate_shield"] += 1
		return
	if e.type != "tear":
		g.kills += 1
		g.telemetry.on_kill(e)
	if e.has("horde") and e.horde < g.horde_log.size():
		var hl: Dictionary = g.horde_log[e.horde]
		hl.killed += 1
		if hl.t80 < 0 and hl.killed >= int(hl.n * 0.8):
			hl.t80 = int(g.t) - hl.t
	var col: Color = D.ENEMIES.get(e.type, {}).get("ecol", Color(0.6, 0.9, 0.9))   # ecol：enemies.json（受击 / 击杀碎屑色）
	# 光学观感下的击杀（docs/130 C5，用户 10-24 定；旧开关 render/kill_style 已删）：所有怪统一「死亡动作（按帧等比加快到普通 ≤ fx/death_max、
	# 精英 ≤ fx/death_max_elite、Boss 不变）→ 最后一帧碎成像素碎屑」，不画溶解帧条、不叠老 CPU 火花 / 冲击环 / 尘土（击杀音与顿帧照旧）；
	# 没有死亡帧条的怪当帧碎。光学关（低档）走原来的帧条 / 溶解 + 火花。纯画面
	var lean: bool = g.optical_on and g.optical.particles != null
	var q: bool = quiet and not e.elite and not e.boss   # 静默：下面的画面 / 音效整段跳过（纯表现，掉落与结算照常）
	if not q:
		g.vfx.kill_burst(e, col, g.crit_hit, lean)   # 击杀爆点 / 击杀音按体型分档 + 大体型或暴击击杀的短顿帧（docs/53，纯画面与音效）
	var body_on: bool = not q and (not g.optical_on or lean or Bal.v("render/optical_kill_body", 1.0) > 0.0)
	var shattered := false   # 碎屑已交给死亡帧条最后一帧（vfx.update 到点喷）
	if not body_on:
		pass
	elif e.get("tex_death", false) and g.V6_FRAMES.has(e.tex + "_death"):
		var dtx: Texture2D = g.tex[e.tex + "_death"]
		var foot: Vector2 = e.pos + Vector2(0, e.r * 0.8 + 3.0 * g.PX)
		var dsc: float = g.PX * float(e.get("sc", 1.0))   # 怪物体型（spawner.escale）放大过的按同一倍数画
		var death_name: String = e.tex + "_death"
		if not A.enemy_pixel_spec(death_name).is_empty():
			var frames: int = g.V6_FRAMES[death_name][0]
			var size := Vector2(dtx.get_width() / float(frames), dtx.get_height()) / A.hires_of(dtx)
			var anchor := A.enemy_pixel_anchor(death_name, Vector2(0.5, 1.0))
			var origin: Vector2 = foot if g.foot_anchor.has(e.tex) else e.pos
			dsc = D.enemy_scale(e, g.t, g.PX) * A.enemy_pixel_scale(death_name)
			if g.vfx.fx_sprite(death_name, origin, dsc, 0.0, e.fx < 0.0, false, Color.WHITE, false, anchor * size) and lean:
				shattered = g.vfx.death_shatter(e, death_name, origin, dsc, anchor)
		else:
			var dp: Vector2 = foot + Vector2(0, -(dtx.get_height() - 3) * dsc * 0.5)
			if g.vfx.fx_sprite(death_name, dp, dsc, 0.0) and lean:
				shattered = g.vfx.death_shatter(e, death_name, dp, dsc, Vector2(0.5, 0.5))
	elif lean or q:
		pass   # 光学 + 新击杀：没有死亡帧条的怪不画溶解，下面当帧碎
	elif not g.vfx.fx_sprite("fx_death_dissolve", e.pos, g.PX * max(1.0, e.r / 12.0)):
		g.vfx.anim("fx_death", e.pos, 0.3, g.PX * max(1.0, e.r / 12.0))
	if not q and not shattered and g.optical_on and g.optical.particles != null and (lean or Bal.v("render/optical_kill_debris", 1.0) > 0.0):
		g.optical.particles.kill_burst(e)   # 光学观感原型：击杀碎屑（纯画面，GPU 随机，不碰模拟随机数）
	if e.elite:
		g.elites_killed += 1
	if e.elite or e.boss:
		Sfx.play("boom", 0.0, 1.0, 0.0)
		g.vfx.stop(0.12, "elite_kill", true)
		g.vfx.shake_screen(1.0)
		g.vfx.sparks(e.pos, Vector2.ZERO, UI.GOLD, 24, 320.0)
	g.squad.on_kill(e)
	var bh = g.bai.boss(e.type)   # Boss 击杀钩子（偏执泡影撤认知负担光环，docs/101 B1c）
	if bh != null:
		bh.on_kill(e)
	# 部件可以靠击杀周围小怪间接削（docs/49d）：普通敌人死在部件 boss/part_chip_r 内，部件掉 part_chip 比例的血（茧掉壳）
	# 怪物密度（spawner._dens_apply，docs/50 §16）：按密度缩放过的普通怪 dk = 1/density，掉率 / 掉量 / 削血按 dk 放大，总期望不变；其余敌人 dk = 1
	var dk: float = float(e.get("dk", 1.0))
	if not e.boss and not e.get("part", false):
		var chip: float = Bal.v("boss/part_chip", 0.05) * dk
		if chip > 0.0:
			var cr: float = Bal.v("boss/part_chip_r", 160.0)
			for o in g.enemies_sys.parts():   # 部件登记表（docs/101 S7：原来每次击杀扫全表找部件），顺序同 g.enemies
				if o.dead or not o.get("part", false) or o.pos.distance_squared_to(e.pos) > cr * cr:
					continue
				g.fx.append({"kind": "drain", "a": e.pos, "b": o.pos, "life": 0.45, "max": 0.45, "enemy": true})   # 部件吸取（world.gd 画）
				if o.get("cocoon_t", 0.0) > 0.0:
					o.shell_hp -= o.shell_max * chip
					if o.shell_hp <= 0.0:
						g.bai.paranoia_hatch(o, true)
				else:
					o.hp -= o.maxhp * chip
					if o.hp <= 0.0:
						kill(o)
	# 深溟奠基者（V8）：死亡时留下一片溟痕（death_mire = 最大半径）
	var dmire := float(D.ENEMIES.get(e.type, {}).get("death_mire", 0.0))
	if dmire > 0.0 and not mire_blocked(e.pos + Vector2(0, 8), dmire):
		add_enemy_mire({"pos": e.pos + Vector2(0, 8), "r": 10.0, "maxr": dmire, "life": 12.0, "seed": g.vrng.randf() * 100.0, "boss": false}, "death")
	if e.xp > 0.0:
		g.pickups.drop(e.pos, "xp", e.xp * g.xp_mult)
	if g.rng_drop.randf() < Bal.v("lamp/oil_kill_chance", 0.006) * float(g.dmod.oil_drop):
		g.pickups.drop(e.pos + Vector2(8, 0), "oil", 15.0 * dk)
	# 特殊道具：磁铁 / 回复（小怪低概率，精英与 Boss 必掉其一）；旋钮在 balance.json pickup 段
	if e.elite or e.boss:
		var mag: bool = g.rng_drop.randf() < Bal.v("pickup/elite_magnet_share", 0.5)
		g.pickups.drop(e.pos + Vector2(-16, 8), "magnet" if mag else "heal", 1.0)
		g.pickups.item_log["magnet_elite" if mag else "heal_elite"] += 1
	elif int(Bal.v("pickup/magnet_cap", 2.0)) > 0:
		# 磁铁单独上限（协调人 9/30）：小怪掉磁铁只看场上磁铁数 < magnet_cap，不再被回复药剂占位；回复药剂仍按「道具合计 < item_cap」
		if g.pickups.count_items("magnet") < int(Bal.v("pickup/magnet_cap", 2.0)):
			g.pickups.item_log.mob_rolled += 1
			if g.rng_drop.randf() < Bal.v("pickup/magnet_kill_chance", 0.00375) * dk:
				g.pickups.drop(e.pos, "magnet", 1.0)
				g.pickups.item_log.magnet_mob += 1
		else:
			g.pickups.item_log.mob_capped += 1
		# 低血补给（docs/82，10-13）：主控生命 < heal_low_hp 时，小怪掉回复药剂的概率 × heal_low_mult，
		# 且场上道具已满时只要回复药剂 < heal_low_cap 仍可掉（磁铁 / 远处没捡的药剂不再挡住）。生命不低时与原规则逐帧相同（不多耗随机数）
		var low_hp: bool = g.hp < g.max_hp * Bal.v("pickup/heal_low_hp", 0.7)
		var heal_room: bool = g.pickups.count_items() < int(Bal.v("pickup/item_cap", 3.0))
		if low_hp and not heal_room:
			heal_room = g.pickups.count_items("heal") < int(Bal.v("pickup/heal_low_cap", 2.0))
		var hc: float = Bal.v("pickup/heal_kill_chance", 0.0035) * (Bal.v("pickup/heal_low_mult", 2.0) if low_hp else 1.0) * dk
		if heal_room and g.rng_drop.randf() < hc:
			g.pickups.drop(e.pos, "heal", 1.0)
			g.pickups.item_log.heal_mob += 1
			if low_hp:
				g.pickups.item_log.heal_low += 1
	elif g.pickups.count_items() >= int(Bal.v("pickup/item_cap", 3.0)):
		g.pickups.item_log.mob_capped += 1   # 场上道具已满，这次小怪击杀不掷骰（magnet_cap = 0 时的原行为，不耗随机数）
	else:
		g.pickups.item_log.mob_rolled += 1
		var r := g.rng_drop.randf()
		var pm: float = Bal.v("pickup/magnet_kill_chance", 0.00375) * dk
		if r < pm:
			g.pickups.drop(e.pos, "magnet", 1.0)
			g.pickups.item_log.magnet_mob += 1
		elif r < pm + Bal.v("pickup/heal_kill_chance", 0.0035) * dk:   # 回复区间宽度独立，调磁铁不挤占回复
			g.pickups.drop(e.pos, "heal", 1.0)
			g.pickups.item_log.heal_mob += 1
	var ing: int = D.ENEMIES.get(e.type, {}).get("ingots", 0)
	if e.elite:
		ing = max(ing, g.rng_drop.randi_range(3, 5))
		if elite_drops_relic():
			g.pickups.drop(e.pos, "chest", 1.0, "elite")
		if g.rng_drop.randf() < Bal.v("lamp/elite_oil_chance", 0.65):
			g.pickups.drop(e.pos + Vector2(20, 10), "oil", Bal.v("lamp/elite_oil_amount", 25.0))
	if float(e.get("scream_t1", INF)) > g.t and D.ENEMIES.get(e.type, {}).has("scream_ingot_mult"):
		ing = int(round(ing * float(D.ENEMIES[e.type].scream_ingot_mult)))   # 箱形恐鱼尖叫结束前击倒（含还没尖叫）：源石锭 ×1.5（docs/145 §4 A，原作宝箱恐鱼）
	if e.boss:
		ing = 20
		if not is_same(e, g.final_boss):
			g.mid_boss_down = true   # 核心延后解锁（docs/191 §6）
		if not is_same(e, g.final_boss) and not g.spawner.boss_alive():
			Sfx.play_overlay("boss_down")   # 最终 Boss 走结算乐句；双 Boss 需全部倒下
		g.pickups.drop(e.pos + Vector2(-20, 0), "chest", 1.0, "boss")
		for j in 12:
			g.pickups.drop(e.pos + Vector2.from_angle(TAU * j / 12.0) * 30.0, "xp", 20.0)
		# Boss 倒下时清除它召唤的东西
		for o in g.enemies:
			if (o.type == "tear" and e.type == "ishar") or (o.feed and int(o.get("feed_to_id", -1)) == int(e.id)):
				o.dead = true
		# 清掉它还没结算的预警（圆形预警在放招者死后仍会结算），下一波大群至少推迟到 12 秒后，照常给 3 秒预警（docs/38 B0 第 7 项）
		g.warns = g.warns.filter(func(w): return not is_same(w.owner, e))
		g.next_horde = maxf(g.next_horde, g.t + 12.0)
	if float(g.dmod.ingot) != 1.0 and ing > 0:
		ing = int(floor(ing * float(g.dmod.ingot) + g.rng_drop.randf()))
	for k in ing:
		g.pickups.drop(e.pos + Vector2.from_angle(g.rng_drop.randf() * TAU) * g.rng_drop.randf_range(6.0, 26.0), "ingot", 1.0)


## 精英不再必掉藏品；共用对局随机数，种子可复现。Boss 奖励仍按原结算。
## relic/elite_drop_from 秒前的精英不掉宝箱（docs/191：首件藏品推到约 2:00）；先抽随机数再判时间，随机数消耗不变
func elite_drops_relic() -> bool:
	var roll: bool = g.rng_drop.randf() < Bal.v("relic/elite_drop_chance", 0.25)
	return roll and g.t >= Bal.v("relic/elite_drop_from", 120.0)
