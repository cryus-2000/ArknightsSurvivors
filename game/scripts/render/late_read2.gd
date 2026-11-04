## 后期可读性第二批（docs/247，用户 11-05 批 V4 / V9 / V10）：三个独立开关，缺省 0 = 关，只改画面、不改玩法和数值。
##   render/light_share       V4 照地光按我方 / 敌方分账：总盏数不变（optical_dl_max），我方保底份额 light_share_ally（缺省一半），
##                            我方份额内按伤害档排序：终结技 > 重击（技能期间的帧条、三档命中）> 普攻；份额内可再分给外部来源（share_source）
##   render/ground_ring_edge  V9 地面光环叠层（巢穴光环、灯标 / 引路圈、伊祖米克灯柱光圈、遥乡 / 旗帜地圈）只画边 + 呼吸，填充 ≤ ring_fill_max（0.04）
##   render/crowd_env_dim     V10 怪群密集时压暗地面 / 溟痕 / 环境颗粒 10–20%；我方特效、小队、敌人、敌弹、预警都不压
## 只读状态、不抽 g.rng / g.vrng（同 seed TRACE 开关两边逐行一致，docs/36 §3.2）
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const Dc = preload("res://scripts/render/declutter.gd")

static var _f := -1
static var _v := {}


static func _tick() -> void:
	var fn: int = Engine.get_process_frames()
	if fn == _f:
		return
	_f = fn
	_v.clear()


## 开关是否开（"light_share" / "ground_ring_edge" / "crowd_env_dim"）；每帧读一次 balance
static func on(key: String) -> bool:
	_tick()
	var v = _v.get(key)
	if v == null:
		v = Bal.v("render/" + key, 0.0)
		_v[key] = v
	return float(v) > 0.0


static func k(key: String, def: float) -> float:
	return Bal.v("render/" + key, def)


## ---------------- V9：地面光环只画边 ----------------
## --clutterdbg=noring（量测，docs/247 §4）：V9 管的地面光环叠层整层不画（填充与边都为 0，代码照跑），开 / 关两边同一口径量「地面半透明占屏」
static func ring_vis() -> float:
	return 0.0 if Dc.dbg("noring") else 1.0


## 填充透明度：开关开时封顶 ring_fill_max（缺省 0.04），关时原样
static func fill_a(a: float) -> float:
	if Dc.dbg("noring"):
		return 0.0
	if not on("ground_ring_edge"):
		return a
	return minf(a, k("ring_fill_max", 0.04))


## 边的呼吸系数（0.5 秒级慢呼吸，ph 相位按位置 / id 错开）：开关开时边透明度 × (lo … 1)，关时 1
static func edge_breath(t: float, ph := 0.0) -> float:
	if Dc.dbg("noring"):
		return 0.0
	if not on("ground_ring_edge"):
		return 1.0
	var lo: float = k("ring_breath_lo", 0.6)
	return lerpf(lo, 1.0, 0.5 + 0.5 * sin((t / k("ring_breath_t", 1.6) + ph) * TAU))
