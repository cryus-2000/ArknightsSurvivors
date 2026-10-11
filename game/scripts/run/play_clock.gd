extends RefCounted
## 对局倍速时钟：调用方仅在 PLAY 时传入真实 delta。界面、音频与自动平衡测试保持原时钟。
## 将本帧模拟时间均分为小步，倍速不放大单步位移，避免弹体穿透与高速冲锋越界。
const SPEEDS := [1.0, 1.5, 2.0]
## 后期卡顿的放大器（docs/50 §10）：原来按 1/60 切步、不封顶——60 Hz 下帧间隔常略超 1/60（59.94 Hz 屏、帧时间抖动）就跑两个半步，
## 30 fps 跑三步、2× 倍速跑到六步，模拟开销翻倍让下一帧更慢，越卡越追、越追越卡。现在：
## - 单步上限 1/48 秒（仍远小于平衡测试的 0.066 秒步长），帧间隔略超 1/60 只跑一步；
## - 每帧最多 MAX_STEPS 步（倍速计入后最多 2 × 1/48 ≈ 0.042 秒模拟时间）：掉帧时模拟略放慢，不再追帧。
## 只影响玩家局（game.gd 的 PLAY 分支）；平衡 / 批跑不走这里，同 seed TRACE / BALANCE 不变
const MAX_STEP := 1.0 / 48.0
const MAX_STEPS := 2
static var test_legacy := false   # 仅测试（--perfab 同局轮换）：旧切法（1/60、不封顶）

static func current_speed() -> float:
	return Cfg.play_speed if Cfg.play_speed in SPEEDS else 1.0

static func current_label() -> String:
	return "1.5×" if current_speed() == 1.5 else ("2×" if current_speed() == 2.0 else "1×")

static func cycle() -> float:
	var index: int = SPEEDS.find(current_speed())
	Cfg.play_speed = SPEEDS[(index + 1) % SPEEDS.size()]
	Cfg.save()
	return Cfg.play_speed

static func steps(real_delta: float, accelerated := true) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if not is_finite(real_delta) or real_delta <= 0.0:
		return out
	# 防「越卡越追」：先把真实帧间隔封到 MAX_STEPS × 1/60（30 fps 以下模拟略放慢），再乘倍速——
	# 这样 2× 倍速照样是 2×（10-11 补：原写法封的是乘倍速后的时长，30 fps + 2× 时只剩约 1.25×）
	var rd: float = real_delta if (test_legacy or not accelerated) else minf(real_delta, MAX_STEPS / 60.0)
	var duration: float = rd * (current_speed() if accelerated else 1.0)
	var count: int = maxi(1, ceili(duration / (1.0 / 60.0 if test_legacy else MAX_STEP)))
	out.resize(count)
	out.fill(duration / float(count))
	return out
