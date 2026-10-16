extends Node
## 图鉴敌人演示回归（用户 10-16）：
##   godot --headless --path game res://tests/gallery_demo_test.tscn -- --regression
## ① 近战主体（骨海漂流体）走到演示靶脚下不再定住：贴身循环「扑上来 → 弹开 → 再上来」（enemy_demo._contact_cycle），
##    10 秒内至少扑 3 次，贴着靶（< e.r + 12）连续不超过 1 秒，弹开后离靶 ≥ e.r + 20；
## 全部通过时打印 "GALLERY DEMO failures=0"。
const D = preload("res://scripts/data.gd")
var g
var failures := 0


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "skadi"
	g.demo_enemy = "bone"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	g.t = 100.0
	g.enemy_demo.reset()
	test_melee()
	print("GALLERY DEMO failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func test_melee() -> void:
	var e: Dictionary = g.enemy_demo.subject
	check(e.type == "bone" and e.ai == "melee", "melee subject spawned")
	var bites := 0
	var last_bite := -1.0
	var hug := 0.0
	var hug_max := 0.0
	var bounced := false
	var dt := 1.0 / 60.0
	for frame in 600:
		g.t += dt
		g.enemy_demo.step(dt)
		if e.dead or g.enemy_demo.subject != e:
			break
		var d: float = e.pos.distance_to(g.ppos)
		var bt: float = float(e.get("demo_bite", -1.0))
		if bt != last_bite:
			last_bite = bt
			bites += 1
		if d < e.r + 12.0:
			hug += dt
			hug_max = maxf(hug_max, hug)
		else:
			hug = 0.0
			if bites > 0 and d >= e.r + 20.0:
				bounced = true
	check(bites >= 3, "melee subject bites the target repeatedly (bites=%d)" % bites)
	check(hug_max <= 1.0, "melee subject never stays glued to the target (max %.2f s)" % hug_max)
	check(bounced, "melee subject bounces away after a bite and walks back")

