extends SceneTree


func _initialize() -> void:
	if not ClassDB.class_exists("EnemyCore"):
		push_error("EnemyCore extension did not load")
		quit(1)
		return
	var core = ClassDB.instantiate("EnemyCore")
	var result: Array = core.step(PackedVector2Array(), PackedFloat64Array(), PackedFloat64Array(), PackedInt32Array(),
		PackedByteArray(), PackedVector2Array(), PackedInt32Array(), PackedFloat64Array([0.016, 64, 0, 0, 0, 0, 0, 0, 64, 0, 0, -4, 4, -4, 4]),
		PackedInt32Array(), PackedVector2Array(), PackedFloat64Array())
	if result.size() != 5 or result[4] != 0:
		push_error("EnemyCore empty step failed")
		quit(1)
		return
	print("NATIVE CORE TEST PASSED: ", core.version())
	quit(0)
