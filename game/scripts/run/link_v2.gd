## 连携 v2（docs/209 §2，开关 balance link/v2；0 = 旧的「E 连携技 + 技能连携、按 E 或自动」）：
## 全自动、只由队长触发——队长放技能（全队共用间隔 link/v2_gap）或放完终结技（不占间隔）时，按当前姿态挑一名队友接一招互补的
## （20 人接法照用 skill_link 的 SAMPLE / KIND4）。E 连携技（combo.gd A–D 四类）不再亮起；每次连携 +1 协同格（喂连携终结技）。
## 不抽随机数：同类按「最久没接过」轮换，区域取最密一团（ult._densest）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Link = preload("res://scripts/run/skill_link.gd")

## 姿态 → 接法类别的优先顺序（随行护队长、突击追着打、部署把怪拖进阻挡线；终结技之后收割）
const PREF := {
	"guard": ["掩护", "附加", "冲阵", "追击", "聚拢"],
	"roam": ["追击", "冲阵", "附加", "聚拢", "掩护"],
	"deploy": ["聚拢", "附加", "追击", "冲阵", "掩护"],
	"ult": ["追击", "冲阵", "附加", "聚拢", "掩护"],
}


static func on() -> bool:
	return Bal.vi("link/v2", 1) > 0


## 当前姿态：随行（含归队）/ 突击 / 部署（突击里下了移动或肃清指令）
static func stance_key(g) -> String:
	var sq = g.squad
	if sq == null or sq.stance != sq.ROAM:
		return "guard"
	return "deploy" if str(sq.order_kind) in ["point", "clear"] else "roam"


## 队长放技能（skill_link.on_skill 在 v2 下转到这里）：只认队长；全队共用间隔
static func on_skill(u, o, _i: int) -> void:
	if not o.is_leader or u.g.t < float(u.get_meta("link_next", -INF)):
		return
	var key: String = stance_key(u.g)
	if lit(u, key, Vector2.INF):
		u.set_meta("link_next", u.g.t + Bal.v("link/v2_gap", 60.0))


## 队长终结技放出（ult._cast）：在落点 / 方向上最密的一团接一招收割；不占技能间隔
static func on_ult(u, at: Vector2) -> void:
	lit(u, "ult", at)


static func area_r() -> float:
	return Bal.v("ult/link_area_r", 150.0) * Bal.v("link/v2_area", 1.3)


## 挑人 + 定区域 + 排进队首（auto 出手由 ult._tick_combo 做）；返回是否亮起
static func lit(u, key: String, at: Vector2) -> bool:
	var g = u.g
	var ld = g.squad.leader()
	if ld == null or ld.pos == Vector2.INF:
		return false
	var pref: Array = PREF.get(key, PREF.guard)
	var cands: Array = []
	for p in g.squad.ops:
		var kind: String = str(Link.SAMPLE.get(str(p.id), ""))
		if kind == "" or p.is_leader or p.pos == Vector2.INF or p.cmd_down > 0.0 or u._queued(p) or u._busy(p):
			continue
		if g.squad.has_method("retreating") and g.squad.retreating(p):
			continue   # 残血撤回中的不接（docs/209 §1.1）
		var rank: int = pref.find(str(Link.KIND4.get(str(p.id), "")))
		cands.append([p, rank if rank >= 0 else 99, float(u.get_meta("lv2_" + str(p.id), -INF))])
	if cands.is_empty():
		return false
	cands.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and (a[2] < b[2] or (a[2] == b[2] and int(a[0].slot) < int(b[0].slot)))))
	var ar: float = area_r()
	for c in cands:
		var p = c[0]
		var pos: Vector2 = _area(u, key, p, ld, at, ar)
		if pos == Vector2.INF:
			continue
		u.queue.push_front({"o": p, "info": {"link": str(Link.SAMPLE[str(p.id)]), "from": ld, "pos": pos, "r": ar, "skill": -1, "v2": key}, "t0": g.t,
			"left": Bal.v("ult/link_window", 1.5)})
		u.set_meta("lv2_" + str(p.id), g.t)
		u.stats.lit += 1
		u.stats["v2_" + key] = int(u.stats.get("v2_" + key, 0)) + 1
		return true
	return false


## 区域：随行 = 队长身边 260 内最密（聚拢类把拉拢中心推到离队长 ≥ 220 的外侧，不把怪拖到队长脚下）；
## 突击 = 接手队友自己身边 300 内最密；部署 = 部署点 260 内最密；终结技 = 落点 300 内最密
static func _area(u, key: String, p, ld, at: Vector2, ar: float) -> Vector2:
	var g = u.g
	match key:
		"roam":
			return u._densest(p.pos, 300.0, ar)
		"deploy":
			var op: Vector2 = g.squad.order_pos if g.squad.order_pos != Vector2.INF else p.pos
			return u._densest(op, 260.0, ar)
		"ult":
			return u._densest(at if at != Vector2.INF else ld.pos, 300.0, ar)
	var c: Vector2 = u._densest(ld.pos, 260.0, ar)
	if c != Vector2.INF and str(Link.KIND4.get(str(p.id), "")) == "聚拢":
		var off: Vector2 = c - ld.pos
		var out_d: float = Bal.v("link/v2_gather_out", 220.0)
		if off.length() < out_d:
			c = ld.pos + (off.normalized() if off.length() > 1.0 else Vector2(float(g.facing), 0.0)) * out_d
	return c
