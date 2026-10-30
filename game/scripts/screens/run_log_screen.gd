extends RefCounted
## 界面 · 对局记录（10-29 用户：结算「对局记录」原来直接用系统打开 runs.jsonl，改成游戏内面板）。
## 只在 Cfg.runs_log_enabled()（调试版 / 对内包）时有入口；读本机 user://runs/runs.jsonl（写入逻辑不动，run/telemetry.gd save_local），
## 列最近 MAX_N 局（新的在上）：时间、版本、编队头像（队长在前）、结局 / 击倒者、用时、击杀、藏品数。
## ↑ ↓ 选、ENTER / 点一局进它的作战记录（run_stats_screen，数据由 RunStats.from_log 还原），ESC 回结算。
## 视觉同结算「作战报告」（docs/37、settle_report.gd）：暗底 + 斜向浅光 + 左上徽记，选中行按那局队长配色。

const HH = preload("res://scripts/screens/hh_style.gd")
const UM = preload("res://scripts/ui_motion.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const RunStats = preload("res://scripts/run/run_stats.gd")
const SB = preload("res://scripts/screens/settle/settle_base.gd")
const Telemetry = preload("res://scripts/run/telemetry.gd")
const D = preload("res://scripts/data.gd")

const MAX_N := 40

var g
var open := false
var entries: Array = []   # [{line, when, ver, ops, lead, won, quit, end, t, kills, relics, acc}]
var sel := 0
var top := 0              # 列表最上面一行的下标
var cells: Array = []     # [Rect2, 动作, 参数]
var t_open := 0.0
var _vis := 8
var _c := {}
var _ph := false
var _last_mouse := Vector2(-1, -1)


func _init(game) -> void:
	g = game


## 记录文件：自测用 --runslog=<路径>（同 telemetry.save_local），平时是玩家目录下的 runs.jsonl
static func path() -> String:
	for a in Cfg.dev_args():
		if a.begins_with("--runslog="):
			return a.substr(10)
	return Telemetry.RUNS_PATH


func open_log() -> void:
	entries = load_entries(path(), MAX_N)
	open = true
	sel = 0
	top = 0
	t_open = UM.now()
	_last_mouse = Vector2(-1, -1)
	Sfx.play("ui_ok", -4.0)


func close() -> void:
	open = false
	cells.clear()


## 读最后 n 行（坏行跳过），新的在前
static func load_entries(p: String, n: int) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(p):
		return out
	var lines := FileAccess.get_file_as_string(p).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if out.size() >= n:
			break
		var d = JSON.parse_string(lines[i])
		if d is Dictionary and d.get("run") is Dictionary:
			out.append(summary(d))
	return out


## 一行记录 → 列表要显示的摘要
static func summary(d: Dictionary) -> Dictionary:
	var meta: Dictionary = d.get("meta", {})
	var run: Dictionary = d.get("run", {})
	var res := str(meta.get("result", ""))
	var won := res == "win"
	var lead := str(meta.get("start_op", ""))
	var ops: Array = []
	for s in run.get("op_stats", []):
		if str(s.get("id", "")) != RunStats.OTHER:
			ops.append(str(s.id))
	if ops.is_empty():
		for id in run.get("squad", []):
			ops.append(str(id))
	if lead != "" and ops.has(lead):
		ops.erase(lead)
		ops.push_front(lead)
	var end := ""
	if won:
		end = str(D.ENDINGS.get(str(run.get("ending", "")), {}).get("name", "探索完成"))
	elif res == "quit":
		end = "中途退出"
	else:
		var kd := RunStats.killer_info(RunStats.log_killer(str(run.get("bot", {}).get("death_src", ""))))
		end = ("击倒者：" + str(kd.name)) if not kd.is_empty() else "探索终止"
	var c: Array = RunStats._char_def(lead).get("col", [0.22, 0.84, 0.94])
	return {"line": d, "when": local_time(str(meta.get("time", ""))), "ver": "v%s · %s" % [str(meta.get("version", "?")), str(meta.get("commit", "?"))],
		"ops": ops, "lead": lead, "won": won, "quit": res == "quit", "end": end, "t": float(run.get("t", 0)), "kills": int(run.get("kills", 0)),
		"relics": int(run.get("relics", 0)), "acc": SB.lead_theme(Color(c[0], c[1], c[2]), won)}


## 记录里的时间是 UTC（Time.get_datetime_string_from_system(true)）→ 本机时间「10-29 02:26」
static func local_time(s: String) -> String:
	if s == "":
		return "--"
	var u := Time.get_unix_time_from_datetime_string(s) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var dt := Time.get_datetime_dict_from_unix_time(u)
	return "%02d-%02d %02d:%02d" % [int(dt.month), int(dt.day), int(dt.hour), int(dt.minute)]


# ================================================================== 输入
func key(k: int) -> bool:
	if not open:
		return false
	var n := entries.size()
	match k:
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_PAGEUP:
			_move(-_vis)
		KEY_PAGEDOWN:
			_move(_vis)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if n > 0:
				enter(sel)
		KEY_ESCAPE, KEY_BACKSPACE:
			Sfx.play("ui_ok", -6.0)
			close()
		_:
			return false
	return true


func _move(d: int) -> void:
	var s2 := clampi(sel + d, 0, maxi(0, entries.size() - 1))
	if s2 != sel:
		sel = s2
		g.kb_nav = true
		Sfx.play("ui_move")


## 进第 i 局的作战记录（返回时回到这里）
func enter(i: int) -> void:
	sel = i
	var rs = g.run_stats
	rs.show_model(RunStats.model(RunStats.from_log(entries[i].line, g.RL)))
	rs.back_label = "返回对局记录"
	Sfx.play("ui_ok", -4.0)


func click(mp: Vector2) -> bool:
	if not open:
		return false
	for c in cells:
		if c[0].has_point(mp):
			match str(c[1]):
				"row":
					enter(int(c[2]))
				"back":
					Sfx.play("ui_ok", -6.0)
					close()
			return true
	return true


func wheel(dy: int) -> void:
	top = clampi(top + dy, 0, maxi(0, entries.size() - _vis))


# ================================================================== 绘制
func _ci() -> CanvasItem:
	return g.hud


func _t(pos: Vector2, s: String, size: int, col: Color, align := 0, max_w := -1.0) -> float:
	var fs: int = maxi(size, 13) if _ph else size
	var w: float = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if max_w > 0.0 and w > max_w:
		while fs > 10 and g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			fs -= 1
		w = g.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	_ci().draw_string(g.font, Vector2(roundf(x), roundf(pos.y + fs * 0.36)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return w


func _p(pos: Vector2, s: String, k: float, col: Color, align := 0, track := 1) -> float:
	return TUI.ptext(_ci(), _c, pos, s, k, col, track, align)


func draw(vs: Vector2) -> void:
	if not open:
		return
	var ci := _ci()
	_c = TUI.ctx(ci)
	_ph = Cfg.touch_device() or vs.y < 560.0
	cells.clear()
	var mp: Vector2 = g.hud.get_local_mouse_position()
	if mp.distance_to(_last_mouse) > 2.0:
		if _last_mouse.x >= 0.0:
			g.kb_nav = false
		_last_mouse = mp
	var a0: float = UM.prog(t_open, UM.T2)
	ci.draw_rect(Rect2(Vector2.ZERO, vs), HH.DARK)
	HH.fill(ci, PackedVector2Array([Vector2(vs.x * 0.48, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(vs.x * 0.36, vs.y)]), Color(1, 1, 1, 0.03))
	var M := 40.0 if not _ph else 24.0
	var acc: Color = entries[sel].acc if not entries.is_empty() else HH.CYB
	# 左上徽记 + 小英文 + 标题
	var ec := Vector2(M + 12.0, 34.0)
	for q in [[15.0, HH.LIGHT], [10.0, HH.DARK], [5.0, acc]]:
		var r: float = q[0]
		HH.fill(ci, PackedVector2Array([ec + Vector2(0, -r), ec + Vector2(r, 0), ec + Vector2(0, r), ec + Vector2(-r, 0)]), q[1])
	_p(Vector2(M + 36, 28), "RHODES ISLAND", 1.0, HH.MUTE, 0, 2)
	_p(Vector2(M + 36, 40), "RUN LOG", 1.0, HH.MUTE, 0, 2)
	var hy := 84.0 if not _ph else 70.0
	var tw := _t(Vector2(M, hy), "对局记录", 30 if not _ph else 24, HH.LIGHT)
	_t(Vector2(M + tw + 16, hy + 4), "最近 %d 局 · 只存在本机" % entries.size(), 13, HH.MUTE)
	# 列表
	var y0 := hy + (34.0 if not _ph else 28.0)
	var bot := vs.y - (70.0 if not _ph else 66.0)
	var rh := 58.0 if not _ph else 54.0
	_vis = maxi(1, int((bot - y0) / rh))
	if entries.is_empty():
		_t(Vector2(M, y0 + 40), "还没有对局记录：每局结束（胜利 / 失败 / 中途退出，满 %d 秒）会记一条。" % int(Telemetry.MIN_SAVE_T), 15, HH.MUTE)
	sel = clampi(sel, 0, maxi(0, entries.size() - 1))
	top = clampi(top, sel - _vis + 1, sel)
	top = clampi(top, 0, maxi(0, entries.size() - _vis))
	var x1 := vs.x - M
	# 列头
	var cx := _cols(M, x1)
	for h in [["时间 / 版本", cx.when], ["编队", cx.ops], ["结局", cx.end], ["用时", cx.t], ["击杀", cx.kills], ["藏品", cx.relics]]:
		_t(Vector2(h[1], y0 - 4), str(h[0]), 11, HH.MUTE, 2 if str(h[0]) in ["用时", "击杀", "藏品"] else 0)
	y0 += 10.0
	for k in mini(_vis, entries.size() - top):
		var i := top + k
		var e: Dictionary = entries[i]
		var r := Rect2(M, y0 + k * rh, x1 - M, rh - 6.0)
		if not g.kb_nav and not Pad.using and r.has_point(mp):
			sel = i
		var on := i == sel
		var ea := clampf(a0 * 3.0 - k * 0.15, 0.0, 1.0) if not UM.rm() else a0
		var dx := 24.0 * (1.0 - UM.out_cubic(ea)) if not UM.rm() else 0.0
		r.position.x += dx
		var ac: Color = e.acc
		ci.draw_rect(r, Color(HH.DARK2.lerp(ac, 0.14 if on else 0.0), ea))
		ci.draw_rect(Rect2(r.position, Vector2(4.0 if not on else 6.0, r.size.y)), Color(ac if (e.won or on) else SB.MAG.darkened(0.2), ea))
		if on:
			ci.draw_rect(r, Color(ac, 0.8 * ea), false, 1.0)
		cells.append([r, "row", i])
		var cy := r.get_center().y
		var ink := Color(HH.LIGHT, ea)
		var sub := Color(HH.MUTE, ea)
		_p(Vector2(r.position.x + 18, cy), "%02d" % (i + 1), 2.0, Color(ac if on else HH.MUTE, ea))
		_t(Vector2(cx.when + dx, cy - 9), str(e.when), 15, ink)
		_t(Vector2(cx.when + dx, cy + 11), str(e.ver), 11, sub, 0, cx.ops - cx.when - 12.0)
		# 编队头像：队长在前、大一号
		var hx: float = cx.ops + dx
		for j in mini((e.ops as Array).size(), 6):
			var box := Rect2(hx, r.position.y + 2.0, 44.0, r.size.y - 4.0)   # 框高 = 行高：所有人同一比例（op_figure，48 高 → 1 倍）
			g.run_stats._c = _c
			g.run_stats._portrait(str(e.ops[j]), box)
			hx += 46.0
		_t(Vector2(cx.end + dx, cy - 9), "探索完成" if e.won else ("中途退出" if e.quit else "探索终止"), 15, Color(ac if e.won else SB.MAG.lightened(0.25), ea))
		_t(Vector2(cx.end + dx, cy + 11), str(e.end) if not e.quit else "", 12, sub, 0, cx.t - cx.end - 70.0)
		_p(Vector2(cx.t + dx, cy), "%02d:%02d" % [int(e.t) / 60, int(e.t) % 60], 2.0, ink, 2)
		_p(Vector2(cx.kills + dx, cy), g.run_stats.fmt_n(float(e.kills)), 2.0, ink, 2)
		_p(Vector2(cx.relics + dx, cy), "%d" % int(e.relics), 2.0, ink, 2)
	if entries.size() > _vis:
		_p(Vector2(x1, hy), "%d-%d / %d" % [top + 1, mini(top + _vis, entries.size()), entries.size()], 1.0, HH.MUTE, 2)
	# 底栏
	var bw := 180.0 if not _ph else 160.0
	var br := Rect2(x1 - bw, vs.y - (54.0 if not _ph else 58.0), bw, 36.0 if not _ph else 44.0)
	var hov: bool = not g.kb_nav and not Pad.using and br.has_point(mp)
	HH.ghost_btn(ci, g.font, br, "返回结算", "" if (Pad.touch and not Pad.using) else ("B" if Pad.using else "ESC"))
	if hov:
		ci.draw_rect(br, Color(acc, 0.9), false, 2.0)
	cells.append([br.grow(6.0 if _ph else 0.0), "back", null])
	if not (Pad.touch and not Pad.using):
		var x := M
		for pr in [["↑ ↓", "选择"], ["ENTER" if not Pad.using else "A", "看作战记录"]]:
			x += _p(Vector2(x, br.get_center().y), str(pr[0]), 1.0, HH.MUTE) + 6.0
			x += _t(Vector2(x, br.get_center().y), str(pr[1]), 12, HH.MUTE) + 18.0


## 各列的 x（右对齐列给右边界）
func _cols(x0: float, x1: float) -> Dictionary:
	var w := x1 - x0
	return {"when": x0 + 64.0, "ops": x0 + 64.0 + w * 0.16, "end": x0 + 64.0 + w * 0.44, "t": x1 - w * 0.2, "kills": x1 - w * 0.09, "relics": x1 - 16.0}
