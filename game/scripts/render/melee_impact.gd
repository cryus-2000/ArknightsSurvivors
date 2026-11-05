## 近战打击感包（docs/246 §11，11-05 用户实机「现在近战打击感比较弱」）：开关 fx/melee_impact（缺省 0 = 关），先给斯卡蒂、星熊，11-05 加推进之王（docs/264）。
## 只改画面，不碰玩法与随机数（同种子 TRACE 开关逐行一致）：
##   ① 命中顿帧：走 vfx.stop 总闸（平衡 / 批跑局不消耗顿帧）；队长全量、队友按 fx/melee_impact_mate 比例；轻击 / 重击两档；
##   ② 重击轻震镜头：g.ult.shake（按真实时间、减少动态效果时为 0），用户同意的 3px / 0.12s 量级；
##   ③ 被打的怪闪本人色（取代白闪，经 fx_recipe.react_col 回落到这里）+ 画面上被推开一小段再弹回（world._eoff 叠加，判定位置不动）；
##   ④ 斩痕 / 照地光提亮（fx_pxplane 读 lit_k()）。命中音照旧（vfx._tier_fx 在接管判断之前就播）。
## 重击 = 技能来源（tags 带 skill）或下面 HEAVY 里的招式名。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const IDS := {"skadi": Color(0.55, 0.78, 1.0), "hoshiguma": Color(1.0, 0.78, 0.42), "siege": Color(1.0, 0.75, 0.3), "mizuki": Color(0.44, 0.91, 1.0), "gladiia": Color(0.62, 0.72, 1.0), "ulpianus": Color(0.62, 0.69, 0.94), "specter_unchained": Color(0.6, 0.85, 1.0), "lappland": Color(0.8, 0.76, 1.0)}   # 推进之王（docs/264）：锤击 / 跃空锤落地；水月（docs/261）：水母荧光青
const HEAVY := {"迅捷打击·γ型": true, "跃浪击": true, "破浪下劈": true, "反手斩": false, "大洋裂断": true, "冲撞": true, "狼之舞": true, "断喝": true, "噤声": true}
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
	if str(o.id) == "ulpianus" and src in ["撼地", "定点爆破", "锁链回旋"]:   # 乌尔比安（docs/266）：锚击的附带冲击不再顿一次
		return
	var g = o.g
	if not on(g):
		return
	var heavy: bool = "skill" in tags or bool(HEAVY.get(src, false))
	# ① 顿帧
	var sec: float = Bal.v("fx/melee_impact_stop_heavy", 0.0375) if heavy else Bal.v("fx/melee_impact_stop", 0.0225)
	if not o.is_leader:
		sec *= Bal.v("fx/melee_impact_mate", 0.6)
	if g.vfx != null:
		g.vfx.stop(sec, "melee_impact")
	# ② 重击轻震
	if heavy and g.ult != null:
		g.ult.shake(Bal.v("fx/melee_impact_shake_px", 3.0), Bal.v("fx/melee_impact_shake_t", 0.12))
	# ③ 闪色 + 画面击退（每只记在敌人字典的画面专用键 mi_*，玩法不读）
	var col: Color = IDS[str(o.id)]
	var px: float = Bal.v("fx/melee_impact_push_heavy", 4.7) if heavy else Bal.v("fx/melee_impact_push", 2.7)
	for e in hits:
		if not (e is Dictionary) or e.get("dead", false):
			continue
		var d: Vector2 = (e.pos - o.pos)
		e["mi_at"] = g.t
		e["mi_dir"] = d.normalized() if d.length() > 0.5 else Vector2.RIGHT
		e["mi_px"] = px * (0.4 if e.get("boss", false) else (0.7 if e.get("elite", false) else 1.0))
		e["mi_col"] = col


## world._eoff 叠加：推开 fx/melee_impact_push_in 秒、fx/melee_impact_push_back 秒弹回（画面位移，按美术像素取整）
## 11-05 用户「打击感现在又有点太钝了」：推开 0.04 → 0.027、弹回 0.12 → 0.08（时长约缩 1/3），位移 push 4 → 2.7 / 7 → 4.7
static func off(g, e: Dictionary) -> Vector2:
	if not e.has("mi_at") or not on(g):
		return Vector2.ZERO
	var age: float = g.t - float(e.mi_at)
	var ti: float = maxf(0.001, Bal.v("fx/melee_impact_push_in", 0.027))
	var tb: float = maxf(0.001, Bal.v("fx/melee_impact_push_back", 0.08))
	if age < 0.0 or age > ti + tb:
		return Vector2.ZERO
	var k: float = age / ti if age < ti else 1.0 - (age - ti) / tb
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
