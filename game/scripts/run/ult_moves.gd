## 终结技形态（docs/198 §4.1–4.5，第一批 5 人）+ 连携终结技通用版（§7.3）。框架在 run/ult.gd（u），本文件只写各人怎么出招。
## 约定：start 返回动作状态字典，step 每帧推进、返回 true = 结束；伤害一律走 u.hit（按目标生命定的预算，frac = 这段占预算的比例）；
## 画面一律走 u.shape（程序占位：圆 / 环 / 扇形 / 长方形带 / 线 / 点），不用美术素材。
extends RefCounted


static func aim_kind(_id: String) -> String:
	return "none"


## 瞄准指示的半径（选落点：落点圆；不瞄：以自身为中心的圈）
static func aim_r(_id: String) -> float:
	return 460.0


static func start(_u, _o, _aim: Vector2, _dir: Vector2) -> Dictionary:
	return {}


static func step(_u, _a: Dictionary, _dt: float) -> bool:
	return true


static func start_cult(_u, _o, _aim: Vector2, _dir: Vector2) -> Dictionary:
	return {}


static func step_cult(_u, _a: Dictionary, _dt: float) -> bool:
	return true
