## Boss 行为脚本基类（docs/55 §6，10-10）：每只 Boss 一个 scripts/enemies/bosses/<type>.gd，继承本类、覆写 step()；
## 多个 type 共用一份脚本时在 enemies.json 写同一个 "script"（圣徒 iberia / carmen → saint.gd；docs/126 A3）。
## 状态全部还在敌人字典 e 上（docs/39：敌人用字典），脚本本身无状态，所以同一只 Boss 的多个实例共用一个脚本对象。
## 预警管线在 enemies/telegraph.gd（g.tele，docs/101 B2）；招式冷却 _cd、远程迫近 _close_in、招式令牌都留在 boss_ai.gd，这里只转发。
extends RefCounted

const D = preload("res://scripts/data.gd")
const Bal = preload("res://scripts/core/balance.gd")

var g  # Game (Node2D)


func _init(game) -> void:
	g = game


## 每帧：boss_ai._boss_ai 跑完公共段（卡点、冲刺计时、假死、骑士追击、接潮统一、令牌、招式轮换）后调用。
## ready = 本帧可以出招；mate = 接潮搭档（没有则 null）
func step(_e: Dictionary, _dt: float, _dir: Vector2, _dist: float, _ready: bool, _mate) -> void:
	pass


## 图鉴 / Boss 演练：直接进入二阶段的完整状态（没有二阶段的 Boss 不用覆写）
func setup_preview_phase2(_e: Dictionary) -> void:
	pass


## 接潮假死复苏时（boss_ai 公共段）调用（docs/95 §12 on_revive；斥亡体「迸发」）
func on_revive(_e: Dictionary) -> void:
	pass


## 验收（autotest --bossmoves=<type>）：这只 Boss 的招式名列表（按节奏表顺序），和 force_move 一一对应
func demo_moves(_e: Dictionary) -> Array:
	return []


## 验收：无视冷却 / 距离条件立刻放出名为 name 的招（只放预警，结算走正式管线）；放了返回 true
func force_move(_e: Dictionary, _name: String, _dir: Vector2, _dist: float) -> bool:
	return false


## ---- 受击钩子（docs/101 B1c，10-15：原来 combat.gd 里按 type 写死的 Boss 特例搬到各自脚本；combat 在原位置调用，结算顺序不变）
## combat.damage 最前面（灯光增伤之前）：返回 true = 这一下整个不算（伊莎玛拉变身保护）
func block_damage(_e: Dictionary) -> bool:
	return false


## combat.damage 灯光增伤之后、卡点无敌之前：返回 true = 伤害由 Boss 自己吃掉、不再往下结算（偏执泡影的茧壳）
func absorb_damage(_e: Dictionary, _dmg: float) -> bool:
	return false


## combat.damage 弱点 / 灯光等加成之后、破绽加成之前：受伤倍率（骑士「斗牛」重甲 ×0.4、破绽期 ×2.0，docs/142b §3.1）。缺省 1
func taken_mult(_e: Dictionary) -> float:
	return 1.0


## combat.damage 扣血、飘伤害数字之后：dmg = 扣完潮盾的伤害，eff = 实际掉的血（最后的骑士寒冷滑窗、圣徒装填打断）
func on_damaged(_e: Dictionary, _dmg: float, _eff: float) -> void:
	pass


## combat.damage 血量归零时：返回 true = 这次不死（结茧 / 重生 / 假死），combat 不再走击杀。覆写的 Boss 自己的情况不成立时调 super。
## 基类 = 接潮假死（D.ENEMIES pair：主教 / 执政官 / 不朽者）：每具最多复苏 boss/pair_revives（2）次，之后直接倒下（docs/38 §8.4）
func on_lethal(e: Dictionary) -> bool:
	if D.ENEMIES.get(e.type, {}).get("pair", false) and e.get("partner") != null and not e.partner.dead and int(e.get("revives", 0)) < int(Bal.v("boss/pair_revives", 2.0)):
		e.hp = 1.0
		e.coma = true
		e.invuln = true
		e.stun = 0.0
		e.coma_t = 0.0
		e.count_end = g.t + Bal.v("boss/pair_race", 8.0)   # 倒计时环（界面与美术读 count_end / count_max）
		e.count_max = Bal.v("boss/pair_race", 8.0)
		g.vfx.add_text(e.pos + Vector2(0, -50), "假死 · %d 秒内击倒另一体" % int(e.count_max), Color(0.6, 1.0, 0.9), 16)
		return true
	return false


## combat.kill 里（干员击杀回调之后、部件吸取之前）
func on_kill(_e: Dictionary) -> void:
	pass


## combat.gate_pass 过卡点后（卡点无敌、清预警之后，最终 Boss 掉落之前）
func on_gate(_e: Dictionary) -> void:
	pass


## D 招（二阶段变化招）第一次出现前副标题先亮招式名 0.6 秒再出预警（docs/95 §0.2）：
## 第一次调用只点亮副标题并占住 0.6 秒出招窗口，返回 false；0.6 秒后再调用返回 true（之后每次都直接 true）
func _first_tell(e: Dictionary, key: String, name: String) -> bool:
	var k: String = "told_" + key
	if e.has(k) and float(e[k]) < 0.0:
		return true
	if not e.has(k):
		e[k] = g.t + 0.6
		e["move_name"] = name
		e["move_t"] = g.t
		e.wind = maxf(e.get("wind", 0.0), 0.6)
		return false
	if g.t >= float(e[k]):
		e[k] = -1.0
		return true
	return false


## 规则横幅（docs/142b §1.3 / §1.4）：第一次见这只 Boss（本局）先亮一句「要做什么」；过卡点换幕时亮这一幕的新规则。
## 同一 key 本局只亮一次（g 上记 meta）；Boss 战里走 vfx 的小通知（show_banner prio 2）
func _rule_banner(key: String, text: String) -> void:
	var mk: String = "boss_rule_" + key
	if g.has_meta(mk):
		return
	g.set_meta(mk, true)
	g.vfx.show_banner(text, 2)


## 二阶段常驻着色（docs/95 §0.2「阶段切换一眼可见」②）：低幅度乘色，render/world 画本体时乘上；不改帧条
func _tint2(e: Dictionary, col: Color) -> void:
	e["tint2"] = col


## 冲刺穿身（docs/142b §1.0 公共判定，10-25）：主控正在冲刺、且离本体中心 < 半径 + pad。圣徒装填打断、泡影打落 / 打散光环 / 戳破幻影共用
func _dash_through(e: Dictionary, pad: float = 24.0) -> bool:
	return g.dash_t > 0.0 and g.ppos.distance_to(e.pos) < float(e.r) + pad


## 接潮组「同步」（docs/142b §3.8，10-25；取材深岩银河：幸存者的无畏舰双子，原作没有）：两具血量比例差超过门槛（一幕 pair_shield_gap 0.25、
## 二幕 0.15）时，血少的那具出护盾、受伤 × pair_shield_mult（0.4）——自动攻击打射程内最近的 Boss，玩家靠站位决定打谁，要把两具拉平再一起打进假死
func _pair_shield(e: Dictionary) -> float:
	var m = e.get("partner")
	if m == null or m.dead or m.get("coma", false) or e.get("coma", false):
		e.pair_shield = false
		return 1.0
	var gap: float = Bal.v("boss/pair_shield_gap2", 0.15) if _pair_p2(e) else Bal.v("boss/pair_shield_gap", 0.25)
	e.pair_shield = e.hp / maxf(1.0, e.maxhp) < m.hp / maxf(1.0, m.maxhp) - gap
	return Bal.v("boss/pair_shield_mult", 0.4) if e.pair_shield else 1.0


## 接潮组一幕两具保持 ≥ pair_sep（360，比大多数干员射程远）的距离：近了每秒互相推开 60 像素（站位分得开，才分得出打谁）
func _pair_spread(e: Dictionary, dt: float) -> void:
	var m = e.get("partner")
	if m == null or m.dead or m.get("coma", false) or e.get("coma", false) or _pair_p2(e):
		return
	var d: float = e.pos.distance_to(m.pos)
	if d < Bal.v("boss/pair_sep", 360.0) and d > 1.0:
		e.pos = g.combat.arena_clamp(e.pos + (e.pos - m.pos).normalized() * 60.0 * dt, 80.0)


## 接潮组的「第二幕」（docs/95 §8–§10「合计 50% 卡点后」）：两具各有自己的 50% 卡点，任一具过了就算整组进第二幕
func _pair_p2(e: Dictionary) -> bool:
	var m = e.get("partner")
	return int(e.get("gates_passed", 0)) >= 1 or (m != null and not m.dead and int(m.get("gates_passed", 0)) >= 1)


## ---- 转发到 boss_ai.gd（docs/38 §1.17：包装方法放基类，各 Boss 脚本只调基类）
## boss_ai.gd 按 type 运行时 load() 这些脚本，所以这里 preload 它不构成循环
const SKILL_COOLDOWN_SCALE: float = preload("res://scripts/boss_ai.gd").SKILL_COOLDOWN_SCALE


func _warn(e: Dictionary, shape: String, dur: float, d: Dictionary) -> Dictionary:
	return g.tele.warn(e, shape, dur, d)


func _cd(e: Dictionary, key: String, dur: float) -> bool:
	return g.bai.cd_ready(e, key, dur)


func _close_in(e: Dictionary, dir: Vector2, dist: float, key: String, title: String, col: Color) -> float:
	return g.bai.close_in(e, dir, dist, key, title, col)
