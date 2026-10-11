extends RefCounted
## 界面动效公共骨架（docs/62 §2.7）：纯静态函数 + 一只界面时钟，各界面自己存开始时刻、在 _draw 里插值。
## 规则（docs/62 §2）：
## - 计时用界面时钟 now()：由 game.gd / title.gd 的 _process(delta) 累计真实帧间隔（不乘对局倍速、对局暂停时照走；
##   --fixed-fps 录片时按固定步长走，录出来的节奏和真机一致）。不读 g.t，不碰 g.rng。
## - 无头批跑（skip_all）直接终态；「减少动态效果」（Cfg.reduce_motion，rm()）只留 ≤ T1 的透明度渐变。
## - 缓动只用这 6 条：out_cubic / in_out_cubic / out_back(s ∈ 1.2, 1.4, 1.6) / in_quad / linear / steps(n)。

const T1 := 0.12   # 微：按下反馈、悬停、减少动态时唯一允许的淡入淡出
const T2 := 0.22   # 短：单个元素进出
const T3 := 0.38   # 中：面板进出、一组元素的整段
const T4 := 0.60   # 招牌：每个界面的招牌动效整段（≤ 0.9）

static var _clock := 0.0
static var _frame := -1


## 每帧推进一次界面时钟（同一帧多处调用只算一次）；delta 截到 0.25 秒，卡顿一下不会直接跳过整段动效
static func advance(delta: float) -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	_frame = f
	_clock += clampf(delta, 0.0, 0.25)


## 界面时钟（秒）
static func now() -> float:
	return _clock


## 进度 0–1：从 t0 起 dur 秒；t < 0 取 now()。无头批跑恒为 1
static func prog(t0: float, dur: float, t := -1.0) -> float:
	if skip_all() or dur <= 0.0:
		return 1.0
	return clampf(((now() if t < 0.0 else t) - t0) / dur, 0.0, 1.0)


## 一组元素的错开：第 i 个的延迟（只取 0.06 / 0.09 / 0.12 三档；超过 5 个的整组一起动）
static func stagger(i: int, step: float) -> float:
	return mini(i, 4) * step


## 减少动态效果：位移 / 缩放 / 旋转 / 翻面 / 扫入 / 下落直接终态
static func rm() -> bool:
	return Cfg.reduce_motion


## 无头批跑：界面动效整段跳过
static func skip_all() -> bool:
	return DisplayServer.get_name() == "headless"


static func out_cubic(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func in_out_cubic(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


## 落位的一点过冲；s 只取 1.2 / 1.4 / 1.6（一屏最多一处用）
static func out_back(x: float, s := 1.4) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)


## 下落（重力感），只用于部署落地
static func in_quad(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x


static func linear(x: float) -> float:
	return clampf(x, 0.0, 1.0)


## 硬步进：⌊x·n⌋ / n（钟表嘀嗒、像素硬切）；x ≥ 1 时为 1
static func steps(x: float, n: int) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 if x >= 1.0 else floorf(x * n) / float(n)


## 减少动态时的淡入（T1）：从 t0 起 120 ms
static func rm_fade(t0: float) -> float:
	return prog(t0, T1)


## 像素风：位移取整
static func px(v: Vector2) -> Vector2:
	return v.round()
