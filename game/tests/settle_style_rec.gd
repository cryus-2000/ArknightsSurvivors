extends Node
## 结算录帧（10-28 结算改版；不进快检）：开窗口、--fixed-fps 30 逐帧存 rec_<段>_<帧>.png。
##   godot --fixed-fps 30 --path game res://tests/settle_style_rec.tscn -- --shotdir=<目录> [--settle_style=N] [--touch] [--rec_ops=N] [--rec_leader=<干员 id>]
## 两段：胜利完整出场 + 停 1.2 秒 → 失败完整出场 + 停 1.2 秒。--rec_ops = 编队人数（缺省 6）；--rec_leader 换队长（看配色跟随）。

const RunStats = preload("res://scripts/run/run_stats.gd")
const Game = preload("res://scripts/game.gd")
const Screen = preload("res://scripts/screens/settlement_screen.gd")

class Probe extends Screen:
	func _run(_id: String) -> void:
		pass   # 录像里不真的跳转

var game: Node
var frames := 0
var shot_dir := ""
var rec_i := 0
var s
var seg := -1
var seg_f := 0
var seg_n := 0
var n_ops := 6
var leader := ""
const SEGS := ["win", "dead"]
const EXTRA := [["texas", "德克萨斯", "TEXAS", [0.95, 0.62, 0.3], 300.0, -1.0], ["lumen", "流明", "LUMEN", [0.6, 0.85, 1.0], 520.0, -1.0],
	["exusiai", "能天使", "EXUSIAI", [1.0, 0.45, 0.45], 560.0, -1.0], ["hoshiguma", "星熊", "HOSHIGUMA", [0.5, 0.9, 0.6], 610.0, -1.0]]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = a.substr(10)
		elif a.begins_with("--rec_ops="):
			n_ops = int(a.substr(10))
		elif a.begins_with("--rec_leader="):
			leader = a.substr(13)
	game = load("res://game.tscn").instantiate()
	add_child(game)


func _raw(result: String) -> Dictionary:
	var raw: Dictionary = RunStats.fake_raw()
	for e in EXTRA.slice(0, maxi(0, n_ops - raw.ops.size())):
		raw.ops.append({"id": e[0], "name": e[1], "en": e[2], "col": e[3], "leader": false, "t": e[4], "left": e[5], "elite": 1})
		raw.op_out[e[0]] = {"普攻": 30000.0 + 9000.0 * raw.ops.size(), "技能": 20000.0}
		raw.op_kills[e[0]] = 120 + 40 * raw.ops.size()
		raw.op_casts[e[0]] = 4 + raw.ops.size()
		for bi in raw.bins.size():
			if bi * 10.0 >= float(e[4]):
				raw.bins[bi][e[0]] = 3000.0 + 500.0 * ((bi * 3) % 4)
	if leader != "":
		_set_leader(raw)
	raw.result = result
	if result != "win":
		raw.killer = {"type": "", "env": "", "name": "被「溺亡的忏悔者」击倒", "cause": ""}
		raw.t = 655.0
		raw.bosses = [{"type": "path", "name": "塑路者", "t0": 210.0, "t1": 262.0}, {"type": "bishop", "name": "接潮主教", "t0": 420.0, "t1": 497.0},
			{"type": "paranoia", "name": "偏执泡影", "t0": 600.0, "t1": -1.0}]
		raw.final_boss = {}
	return raw


## 换队长：已在编队里就改 leader 标记，否则按 data/characters/<id>.json 加一名开局就在、输出最高的队长
func _set_leader(raw: Dictionary) -> void:
	var found := false
	for o in raw.ops:
		o.leader = o.id == leader
		if o.leader:
			o.t = 0.0
			found = true
	if found:
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/%s.json" % leader))
	raw.ops.insert(0, {"id": leader, "name": str(d.name), "en": str(d.get("en", leader.to_upper())), "col": d.col, "leader": true, "t": 0.0, "left": -1.0, "elite": 2})
	raw.op_out[leader] = {"普攻": 290000.0, "技能": 210000.0}
	raw.op_kills[leader] = 900
	raw.op_casts[leader] = 24
	for bi in raw.bins.size():
		raw.bins[bi][leader] = 6000.0 + 900.0 * ((bi * 5) % 4)
	var gone: Dictionary = raw.ops.pop_back()   # 编队人数不变
	raw.op_out.erase(gone.id)
	raw.op_kills.erase(gone.id)
	raw.op_casts.erase(gone.id)
	for bin in raw.bins:
		bin.erase(gone.id)


func _start(i: int) -> void:
	seg = i
	seg_f = 0
	var res: String = SEGS[i]
	game.state = Game.S.WIN if res == "win" else Game.S.DEAD
	game.state_age = 99.0
	if s != null and is_instance_valid(s.squad_canvas):
		s.squad_canvas.queue_free()
	s = Probe.new(game)
	game.settlement = s
	s.set_model(RunStats.model(_raw(res)))
	s.cells = 86 if res == "win" else 41
	s.vouchers = 2 if res == "win" else 1
	seg_n = int(ceil((s._end() + 1.2) * 30.0))


func _process(d: float) -> void:
	frames += 1
	if frames == 4:
		game.set_process(false)
		game.hud.size = get_viewport().get_visible_rect().size
		_start(0)
	if s == null:
		return
	s.tick(d)
	game.hud.queue_redraw()
	get_viewport().get_texture().get_image().save_png(shot_dir + "/rec_%d_%03d.png" % [seg, seg_f])
	rec_i += 1
	seg_f += 1
	if seg_f >= seg_n:
		if seg + 1 >= SEGS.size():
			get_tree().quit(0)
		else:
			_start(seg + 1)
