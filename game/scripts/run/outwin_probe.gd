## --outwin（仅测试，10-27 用户「每个 Boss 都要注意给干员输出的机会和时间」）：骑士战输出窗口统计。
## 每帧按真实步长累计：队长与骑士的地面距离（扣骑士半径）在近战距离内、同屏敌弹 < 20 的时间占比；
## 「骑士可近身」= 骑士不在自冲、没有它的有伤预警 / 移动冰锋在结算（与队长站位无关）；破绽每段时长；连段期间的同两项。
## 局末打印 OUTWIN {json}。只读游戏状态，不碰随机数
extends RefCounted

const MELEE := 112.0   # 近卫普攻距离（skadi / texas base.reach）
const BULLETS_MAX := 20
const VIEW_HALF := Vector2(700.0, 400.0)   # 同屏：以队长为中心 1400×800 世界像素（1 倍镜头 1280×720 外扩一点）

var acc := {}
var breaks: Array = []
var _brk_start := -1.0
var _last_t := -1.0


func _add(key: String, dt: float) -> void:
	acc[key] = float(acc.get(key, 0.0)) + dt


func step(g) -> void:
	var e = null
	for b in g.bosses:
		if b.type == "knight_boss" and not b.dead:
			e = b
	if e == null or g.state != g.S.PLAY:
		_last_t = -1.0
		return
	var dt: float = 0.0 if _last_t < 0.0 else maxf(0.0, g.t - _last_t)
	_last_t = g.t
	if dt <= 0.0 or dt > 0.2:
		return
	var ph := "p%d" % int(e.get("phase", 1))
	var gap: float = g.combat.ground_d(g.ppos, e.pos) - float(e.get("r", 0.0))
	var near: bool = gap <= MELEE
	var bullets := 0
	for bl in g.ebullets:
		var d: Vector2 = (bl.pos as Vector2) - g.ppos
		if absf(d.x) <= VIEW_HALF.x and absf(d.y) <= VIEW_HALF.y:
			bullets += 1
	var calm: bool = bullets < BULLETS_MAX
	var busy: bool = e.get("kb_self", false) and (e.kb as Vector2).length() > 40.0
	if not busy:
		for w in g.warns:
			if is_same(w.owner, e) and not w.done and float(w.get("dmg", 0.0)) > 0.0:
				busy = true
				break
	if not busy:
		for h in g.bai.finals.hazards:
			if is_same(h.owner, e):
				busy = true
				break
	var combo: bool = e.get("knight_combo_active", false)
	var brk: bool = float(e.get("break_t", 0.0)) > 0.0
	for scope in ["all", ph] + (["combo"] if combo else []):
		_add(scope + "/t", dt)
		if near: _add(scope + "/near", dt)
		if near and calm: _add(scope + "/near_calm", dt)
		if not busy: _add(scope + "/open", dt)
		if not busy and calm: _add(scope + "/open_calm", dt)
		if brk: _add(scope + "/break", dt)
		_add(scope + "/bullets_sum", dt * bullets)
	if brk and _brk_start < 0.0:
		_brk_start = g.t
	elif not brk and _brk_start >= 0.0:
		breaks.append([snappedf(_brk_start, 0.1), snappedf(g.t - _brk_start, 0.01), str(e.get("brk_label", "")), ph])
		_brk_start = -1.0


func report() -> Dictionary:
	var out := {"breaks": breaks}
	for scope in ["all", "p1", "p2", "combo"]:
		var t: float = float(acc.get(scope + "/t", 0.0))
		if t <= 0.0:
			continue
		var r := {"sec": snappedf(t, 0.1)}
		for k in ["near", "near_calm", "open", "open_calm", "break"]:
			r[k + "_pct"] = snappedf(100.0 * float(acc.get(scope + "/" + k, 0.0)) / t, 0.1)
		r["bullets_mean"] = snappedf(float(acc.get(scope + "/bullets_sum", 0.0)) / t, 0.1)
		out[scope] = r
	return out
