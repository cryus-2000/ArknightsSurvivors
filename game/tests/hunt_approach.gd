extends Node
## 围猎从屏幕外压过来（10-24）：开始时整圈在屏幕外（离主控 > 画面对角线一半）、合拢途中整圈同速收到 260 钉住、
## 钉住后照旧规则（缺口突围 / 夹回 / 20 秒散去）；合拢途中打穿一侧冲出去算提前突围；没有凭空出现的光圈（vis 合拢途中为空）
var game: Node
var frames := 0
var fails := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		push_error(label)
func _ready() -> void:
	game = load("res://game.tscn").instantiate()
	add_child(game)
func step(sec: float) -> void:
	var t := 0.0
	while t < sec:
		game.t += 0.05
		game.hunt.update(0.05)
		game.hunt.clamp_player()
		t += 0.05
func _process(_dt: float) -> void:
	frames += 1
	if frames != 5:
		return
	game.set_process(false)
	game.enemies.clear()
	game.ppos = Vector2.ZERO
	var h = game.hunt
	game.t = h.start_at
	h.update(0.05)
	check(h.state == 2 and h.ring.size() == 18, "hunt begins with a full ring")
	var half_diag: float = game.get_viewport_rect().size.length() * 0.5
	var far := true
	for e in h.ring:
		if e.pos.distance_to(game.ppos) < half_diag * 1.05:
			far = false
	check(far, "ring spawns off screen")
	check(h.vis().is_empty(), "no ring drawn while closing")
	var d0: float = h.ring[0].pos.distance_to(game.ppos)
	step(2.0)
	var d1: float = h.ring[0].pos.distance_to(game.ppos)
	check(d1 < d0 and not h.settled, "ring is closing")
	var d2 := 0.0
	step(h.approach_t())
	check(h.settled, "ring settles after the approach time")
	var rok := true
	for e in h.ring:
		if absf(e.pos.distance_to(h.c) - h.radius()) > 1.0:
			rok = false
	check(rok and h.radius() == 260.0, "settled ring sits at radius 260 around the leader")
	check(not h.vis().is_empty(), "ring is drawn once settled")
	# 钉住后：往外走被夹回；打死一只就是缺口
	game.ppos = h.c + Vector2(h.radius() + 60.0, 0.0)
	h.clamp_player()
	check(game.ppos.distance_to(h.c) <= h.radius() - 19.0, "player is held inside by a living ring member")
	h.ring[0].dead = true
	game.ppos = h.c + Vector2(h.radius() + 60.0, 0.0)
	var hp0: float = game.hp
	step(0.1)
	check(h.broke, "leaving through a gap breaks out")
	step(25.0)
	check(h.state == 3, "hunt ends after its duration")
	# 第二局：合拢途中打穿一侧提前突围
	var h2 = load("res://scripts/run/hunt.gd").new(game)
	game.hunt = h2
	game.enemies.clear()
	game.ppos = Vector2.ZERO
	game.t = h2.start_at
	h2.update(0.05)
	h2.ring[0].dead = true   # 一侧已被打穿（缺口在 0 方位）
	var guard := 0
	while not h2.broke and not h2.settled and guard < 200:
		game.ppos += Vector2(400.0 * 0.05, 0.0)   # 迎着缺口那一侧全速走
		step(0.05)
		guard += 1
	check(h2.broke and not h2.settled, "breaking through during the approach counts as an early breakout")
	print("HUNT APPROACH: %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)
