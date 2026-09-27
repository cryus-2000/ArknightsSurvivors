extends Node
const Clock = preload("res://scripts/run/play_clock.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("Play clock: " + message)

func _ready() -> void:
	for speed in [1.0, 1.5, 2.0]:
		Cfg.play_speed = speed
		for delta in [0.001, 1.0 / 144.0, 1.0 / 60.0, 1.0 / 30.0, 0.05, 0.125]:
			var total := 0.0
			for step in Clock.steps(delta):
				check(step > 0.0 and step <= Clock.MAX_STEP + 0.000000001, "bounded positive step")
				total += step
			check(absf(total - delta * speed) < 0.000000001, "preserve scaled time")
			var menu_total := 0.0
			for step in Clock.steps(delta, false):
				menu_total += step
			check(absf(menu_total - delta) < 0.000000001, "unscaled callers preserve real time")
	Cfg.play_speed = 1.0
	check(Clock.cycle() == 1.5 and Clock.current_label() == "1.5×", "cycle to 1.5")
	check(Clock.cycle() == 2.0 and Clock.current_label() == "2×", "cycle to 2")
	check(Clock.cycle() == 1.0 and Clock.current_label() == "1×", "cycle to 1")
	Cfg.play_speed = -5.0
	check(Clock.current_speed() == 1.0, "invalid settings fallback")
	for delta in [0.0, -0.01, INF, NAN]:
		check(Clock.steps(delta).is_empty(), "invalid delta has no steps")
	Cfg.play_speed = 1.0
	print("Play clock regression: %d failures" % failures)
	get_tree().quit.call_deferred(1 if failures else 0)
