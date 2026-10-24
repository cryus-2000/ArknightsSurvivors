extends Node

var checks := 0
var failures := 0

func _ready() -> void:
	load("res://tests/command_wheel_cases.gd").new().run(check)
	print("COMMAND WHEEL checks=%d failures=%d" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
