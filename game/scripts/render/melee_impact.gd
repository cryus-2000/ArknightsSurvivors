## 近战打击感包（docs/246 §11，11-05 用户实机「现在近战打击感比较弱」）：开关 fx/melee_impact（缺省 0 = 关），先只给斯卡蒂、星熊。
## 只改画面，不碰玩法与随机数（同种子 TRACE 开关逐行一致）：
##   ① 命中顿帧：走 vfx.stop 总闸（平衡 / 批跑局不消耗顿帧）；队长全量、队友按 fx/melee_impact_mate 比例；轻击 / 重击两档；
##   ② 重击轻震镜头：g.ult.shake（按真实时间、减少动态效果时为 0），用户同意的 3px / 0.12s 量级；
##   ③ 被打的怪闪本人色（取代白闪，经 fx_recipe.react_col 回落到这里）+ 画面上被推开一小段再弹回（world._eoff 叠加，判定位置不动）；
##   ④ 斩痕 / 照地光提亮（fx_pxplane 读 lit_k()）。命中音照旧（vfx._tier_fx 在接管判断之前就播）。
## 重击 = 技能来源（tags 带 skill）或下面 HEAVY 里的招式名。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const IDS := {"skadi": Color(0.55, 0.78, 1.0), "hoshiguma": Color(1.0, 0.78, 0.42), "gladiia": Color(0.62, 0.72, 1.0)}   # 歌蕾蒂娅（docs/263）：钩索落地 / 拖回到位 / 冲撞
const HEAVY := {"迅捷打击·γ型": true, "跃浪击": true, "破浪下劈": true, "反手斩": false, "大洋裂断": true, "冲撞": true}
## 不走打击感包的招：歌蕾蒂娅 S3 每 0.75 秒一跳、反震（持续 / 被动，顿帧震屏会一直抖）
const SKIP := {"碎漩狂舞": true, "反震": true}
const FLASH_T := 0.07


static func on(g) -> bool:
	return g != null and not g.headless_batch and Bal.v("fx/melee_impact", 0.0) > 0.0


## 斩痕 / 照地光的提亮倍数（开关关时 1）
static func lit_k(g) -> float:
	return Bal.v("fx/melee_impact_lit", 1.35) if on(g) else 1.0


## ob_core.exec_shape 判定结算后调（只画）：o 出手的干员，src 招式名，tags，hits 被打中的敌人
static func hit(o, src: String, tags: Array, hits: Array) -> void:
	if hits.is_empty() or not IDS.has(str(o.id)) or SKIP.has(src):
		return
	var g = o.g
	if not on(g):
		return
	var heavy: bool = "skill" in tags or bool(HEAVY.get(src, false))
	# ① 顿帧
	var sec: float = Bal.v("fx/melee_impact_stop_heavy", 0.075) if heavy else Bal.v("fx/melee_impact_stop", 0.045)
	if not o.is_leader:
		sec *= Bal.v("fx/melee_impact_mate", 0.6)
	if g.vfx != null:
		g.vfx.stop(sec, "melee_impact")
	# ② 重击轻震
	if heavy and g.ult != null:
		g.ult.shake(Bal.v("fx/melee_impact_shake_px", 3.0), Bal.v("fx/melee_impact_shake_t", 0.12))
	# ③ 闪色 + 画面击退（每只记在敌人字典的画面专用键 mi_*，玩法不读）
	var col: Color = IDS[str(o.id)]
	var px: float = Bal.v("fx/melee_impact_push_heavy", 7.0) if heavy else Bal.v("fx/melee_impact_push", 4.0)
	for e in hits:
		if not (e is Dictionary) or e.get("dead", false):
			continue
		var d: Vector2 = (e.pos - o.pos)
		e["mi_at"] = g.t
		e["mi_dir"] = d.normalized() if d.length() > 0.5 else Vector2.RIGHT
		e["mi_px"] = px * (0.4 if e.get("boss", false) else (0.7 if e.get("elite", false) else 1.0))
		e["mi_col"] = col


## world._eoff 叠加：推开 0.04 秒、0.12 秒弹回（画面位移，按美术像素取整）
static func off(g, e: Dictionary) -> Vector2:
	if not e.has("mi_at") or not on(g):
		return Vector2.ZERO
	var age: float = g.t - float(e.mi_at)
	if age < 0.0 or age > 0.16:
		return Vector2.ZERO
	var k: float = age / 0.04 if age < 0.04 else 1.0 - (age - 0.04) / 0.12
	return ((e.mi_dir as Vector2) * float(e.mi_px) * k / 2.0).round() * 2.0


## fx_recipe.react_col 回落到这里：a < 0 = 不接管（照旧白闪），a > 0 = 闪本人色
static func col(g, e: Dictionary) -> Color:
	if not e.has("mi_at") or not on(g) or e.get("boss", false):
		return Color(0, 0, 0, -1)
	var age: float = g.t - float(e.mi_at)
	if age < 0.0 or age > FLASH_T:
		return Color(0, 0, 0, -1)
	var c: Color = e.mi_col
	return Color(c.r, c.g, c.b, 0.85)
