extends Node
## 最终 Boss 预警不退回通用画法（docs/215 §5，11-01 巡检）：四个最终 Boss 一、二阶段逐招 force_move，跑 4 秒收集出现过的全部预警。
## ① act final_attack 的预警喂给 boss_attack_draw._warning，走到通用粉框 / 粉圈 / 通用扇形分支（on_generic 钩子）= 失败——
##    骑士侧踏挑枪 / 冰枪封径 / 冻潮夹击当初就是新 skin 没登记、静默退回通用画法；
## ② 其余 act 由 telegraph_draw / world.draw_warn_outlines 画通用描边，只允许下面 GENERIC_OK 名单里的「Boss / act / 形状」，
##    新招要么接专属画法，要么有意加进名单（写明为什么）。
const Draw = preload("res://scripts/render/boss_attack_draw.gd")
const TeleDraw = preload("res://scripts/render/telegraph_draw.gd")
const IsharTell = preload("res://scripts/render/ishar_tell_draw.gd")
const BOSSES := ["paranoia", "ishar", "knight_boss", "izumik"]
## 有意用通用描边的预警（2026-11-01 的全集）。新增前先想：这招是不是该有这只 Boss 自己的预警样式？
## 现有 9 类都是通用描边的设计用法：Boss 冲锋线（dash）、缺口环 / 落点圈（pattern_ring、song_ring、burst、pattern_rain）、
## 扇形扫击（izumik sweep）、伊祖米克全场浪的描边（izu_wave，光学观感下另有 field_warning 全场预警）。改成专属画法时从名单删掉
const GENERIC_OK := [
	"paranoia/burst/circle", "paranoia/dash/line", "paranoia/pattern_ring/circle",
	"ishar/song_ring/circle", "ishar/dash/line",
	"izumik/sweep/cone", "izumik/pattern_rain/circle", "izumik/pattern_ring/circle", "izumik/izu_wave/circle",
]
var g
var failures := 0
var generic_hits: Array = []


func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL ", label)


func _ready() -> void:
	g = load("res://game.tscn").instantiate()
	g.demo_op = "mizuki"
	add_child(g)
	await get_tree().process_frame
	g.set_process(false)
	Draw.on_generic = func(w): generic_hits.append(w)
	var seen_keys := {}
	var moves_n := 0
	for type in BOSSES:
		for phase in [1, 2]:
			var e: Dictionary = fresh(type, phase)
			var h = g.bai.boss(type)
			for name in h.demo_moves(e):
				e = fresh(type, phase)
				var dir: Vector2 = (g.ppos - e.pos).normalized()
				if not h.force_move(e, str(name), dir, e.pos.distance_to(g.ppos)):
					continue
				moves_n += 1
				var seen: Array = []
				for i in 80:
					for w in g.warns:
						if not seen.any(func(x): return is_same(x, w)):
							seen.append(w)
					tick(e, 0.05)
				for w in seen:
					_classify(type, str(name), w, seen_keys)
	# 自检：钩子确实拦得住「没登记的 skin」（同骑士侧踏挑枪当初的粉框）
	generic_hits.clear()
	var fake := {"owner": fresh("knight_boss", 1), "act": "final_attack", "shape": "line", "skin": "unregistered", "pos": Vector2.ZERO, "ang": 0.0, "len": 200.0, "wid": 20.0, "t": 0.5, "dur": 1.0, "done": false}
	Draw._warning(g, fake, 0.9)
	check(generic_hits.size() == 1, "hook catches an unregistered knight skin")
	Draw.on_generic = Callable()
	check(moves_n >= 40, "forced at least 40 final-boss moves (got %d)" % moves_n)
	for k in seen_keys:
		if not GENERIC_OK.has(k):
			check(false, "generic telegraph outline: %s (moves %s)" % [k, seen_keys[k]])
	print("FINAL BOSS TELLS moves=%d generic_keys=%s" % [moves_n, str(seen_keys.keys())])
	print("FINAL BOSS TELLS failures=", failures)
	g.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures else 0)


func _classify(type: String, move: String, w: Dictionary, seen_keys: Dictionary) -> void:
	var o = w.get("owner")
	if not (o is Dictionary) or str(o.get("type", "")) != type:
		return
	if str(w.get("act", "")) == "final_attack":
		if IsharTell.owns(w) or str(w.get("skin", "")) == "bubble":
			return   # 同 boss_attack_draw.draw 的分流
		var probe: Dictionary = w.duplicate()
		probe.t = maxf(float(w.get("tell_after", 0.0)) + 0.01, float(w.dur) * 0.6)
		probe.done = false
		generic_hits.clear()
		Draw._warning(g, probe, 0.9)
		check(generic_hits.is_empty(), "%s %s: final_attack %s / skin '%s' falls back to the generic tell" % [type, move, str(w.shape), str(w.get("skin", ""))])
		return
	if TeleDraw.quiet(w) or IsharTell.owns(w) or bool(w.get("dim", false)):
		return
	var k := "%s/%s/%s" % [type, str(w.get("act", "")), str(w.shape)]
	if not seen_keys.has(k):
		seen_keys[k] = []
	if not seen_keys[k].has(move):
		seen_keys[k].append(move)


func fresh(type: String, phase: int) -> Dictionary:
	g.warns.clear()
	g.bai.finals.hazards.clear()
	g.enemies.clear()
	g.fx.clear()
	g.bai.token_owner = null
	g.t = 150.0
	var e: Dictionary = g.spawner.new_enemy(type, Vector2.ZERO)
	e.age = 20.0
	e.invuln = false
	e.channel = 0.0
	if type == "knight_boss":
		e.stakes = [{"pos": Vector2(2000, 2000), "born": 0.0, "until": INF}]
	g.bosses = [e]
	g.boss = e
	g.final_boss = e
	g.enemies.append(e)
	if phase == 2:
		g.bai.setup_preview_phase2(e)
		e.invuln = false
		e.channel = 0.0
	g.ppos = Vector2(350, 0)
	return e


func tick(e: Dictionary, dt: float) -> void:
	g.t += dt
	e.wind = maxf(0.0, float(e.get("wind", 0.0)) - dt)
	e.stun = maxf(0.0, float(e.get("stun", 0.0)) - dt)
	e.break_t = maxf(0.0, float(e.get("break_t", 0.0)) - dt)
	e.hp = e.maxhp if phase_of(e) == 1 or e.type != "knight_boss" else e.maxhp * 0.5
	g.invuln = 999.0
	g.bai.boss_step(e, dt, (g.ppos - e.pos).normalized(), g.ppos.distance_to(e.pos))
	g.tele.update_warns(dt)


func phase_of(e: Dictionary) -> int:
	return int(e.get("phase", 1))
