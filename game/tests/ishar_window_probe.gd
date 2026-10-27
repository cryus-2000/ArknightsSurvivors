extends Node
## 伊莎玛拉输出窗口探针（docs/170 §8）：三幕各 60 秒正式 AI 自然流程（不强制起手），玩家无敌、贴着 Boss 130px 绕圈移动（近战站位）。
## 量：「Boss 在近战射程内（地面距离 ≤ 200）且同屏敌弹 < 20」的时间占比、破绽次数与时长、同屏敌弹峰值。只读，不改模拟。
## godot --headless --path game res://tests/ishar_window_probe.tscn
var g
const DT := 1.0 / 30.0
const SEC := 60.0
const MELEE := 200.0
const LOW := 20

func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	var out := []
	for act in 3:
		g.t = 100.0
		g.zone_frozen = true
		g.zone_state = 3
		g.zone_c = Vector2.ZERO
		g.zone_next_c = Vector2.ZERO
		g.zone_r = 650.0
		g.zone_next_r = 650.0
		g.warns.clear()
		g.enemies.clear()
		g.ebullets.clear()
		g.shocks.clear()
		g.bai.finals.hazards.clear()
		g.bai.token_owner = null
		var e: Dictionary = g.spawner.new_enemy("ishar", Vector2.ZERO)
		e.age = 20.0
		g.enemies.append(e)
		g.bosses = [e]
		g.boss = e
		g.final_boss = e
		g.ppos = Vector2(130, 0)
		g.bai.setup_preview_phase2(e)
		e.gates_passed = act
		if act >= 1:
			g.bai.boss("ishar")._eyes_spawn(e)
		var low := 0.0
		var near := 0.0
		var peak := 0
		var breaks: Array = []
		var prev := 0.0
		var n := int(SEC / DT)
		for i in n:
			var tt: float = i * DT
			g.invuln = 999.0
			var want: Vector2 = e.pos + Vector2.from_angle(tt * 0.6) * 130.0
			g.ppos = g.ppos.move_toward(g.combat.arena_clamp(want, 40.0), 150.0 * DT)
			g.doc_pos = g.ppos + Vector2(10, 35)
			g.t += DT
			g.enemies_sys.build_grid()
			g.enemies_sys.update(DT)
			g.shots.step(DT)
			g.tele.update_warns(DT)
			g.enemies_sys.update_status(DT)
			g.ebullets = g.ebullets.filter(func(b): return b.life > 0.0)
			g.fx.clear()
			var live: int = g.ebullets.size()
			peak = maxi(peak, live)
			var d: float = g.combat.ground_d(g.ppos, e.pos)
			if d <= MELEE:
				near += DT
				if live < LOW:
					low += DT
			var brk: float = float(e.get("break_t", 0.0))
			if brk > prev + 0.1:
				breaks.append(snappedf(brk, 0.01))
			prev = brk
		out.append({"act": act + 1, "seconds": SEC, "melee_low_pct": snappedf(low / SEC * 100.0, 0.1), "melee_pct": snappedf(near / SEC * 100.0, 0.1),
			"breaks": breaks, "break_sum": snappedf(breaks.reduce(func(a, b): return a + b, 0.0), 0.01), "bullet_peak": peak})
	print("ISHAR_WINDOW ", JSON.stringify(out))
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit()
