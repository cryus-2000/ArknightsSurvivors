extends RefCounted
## 对局倍速时钟：调用方仅在 PLAY 时传入真实 delta。界面、音频与自动平衡测试保持原时钟。
## 将本帧模拟时间均分为小步，倍速不放大单步位移，避免弹体穿透与高速冲锋越界。
const SPEEDS := [1.0, 1.5, 2.0]
const MAX_STEP := 1.0 / 60.0

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
	var duration: float = real_delta * (current_speed() if accelerated else 1.0)
	var count: int = maxi(1, ceili(duration / MAX_STEP))
	out.resize(count)
	out.fill(duration / float(count))
	return out
