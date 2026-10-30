extends RefCounted
## 结算改版原型的公共件（10-28 用户「结算页设计的不太好看，重新设计一下」，三个方向待挑）：
## 只读 settlement_screen 的 model / rows / art，画在 1280×720 版面单位里（调用方已 draw_set_transform 到 s.origin + s.scale）。
## 子类实现 draw()、buttons()、end_t()；入场时间轴按胜利写，失败乘 loss_k 拉长。
const HH = preload("res://scripts/screens/hh_style.gd")
const UM = preload("res://scripts/ui_motion.gd")
const TUI = preload("res://scripts/screens/tide_ui.gd")
const D = preload("res://scripts/data.gd")
const Roster = preload("res://scripts/core/roster.gd")
const OpFig = preload("res://scripts/screens/op_figure.gd")

const MAG := Color8(232, 64, 128)      # 失败 / 击倒（洋红，docs/37）
const PHONE_MIN_FS := 15

var s          # settlement_screen
var ci: CanvasItem
var won := true
var t := 0.0
var fa := 1.0  # 当前组透明度
var _pc := {}  # 像素字上下文（含页面缩放）


func _init(screen) -> void:
	s = screen


func end_win() -> float:
	return 3.2


func end_loss() -> float:
	return 3.8


func end_t() -> float:
	return end_win() if s._won() else end_loss()


## 画一帧：子类先调 begin
func begin(canvas: CanvasItem) -> void:
	ci = canvas
	won = s._won()
	t = s.elapsed
	fa = 1.0
	_base = TUI.ctx(ci).xf
	reset_xf()


var _base := Transform2D.IDENTITY


## 局部变换：绕版面点 c 旋转 rot、缩放 sv（翻牌 / 盖章用）；像素字上下文跟着换
func xf(c: Vector2, rot := 0.0, sv := Vector2.ONE, off := Vector2.ZERO) -> void:
	var L := Transform2D(0.0, Vector2.ONE * s.scale, 0.0, s._o) * Transform2D(rot, sv, 0.0, c + off) * Transform2D(0.0, -c)
	ci.draw_set_transform_matrix(L)
	var x: Transform2D = _base * L
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, absf(x.get_scale().y))}


func reset_xf() -> void:
	ci.draw_set_transform(s._o, 0, Vector2.ONE * s.scale)
	var x: Transform2D = _base * Transform2D(0.0, Vector2.ONE * s.scale, 0.0, s._o)
	_pc = {"xf": x, "inv": x.affine_inverse(), "k": maxf(0.01, x.get_scale().x)}


## 时间轴进度（t0 / dur 按胜利写）
func k(t0: float, dur: float) -> float:
	var f: float = 1.0 if won else end_loss() / end_win()
	return clampf((t - t0 * f) / maxf(0.001, dur * f), 0.0, 1.0)


func ek(t0: float, dur: float) -> float:
	return UM.out_cubic(k(t0, dur))


func fs(size: int) -> int:
	return maxi(size, PHONE_MIN_FS) if Cfg.phone_ui() else size


## 中文字：pos 左上；align 0 左 1 中 2 右
func txt(x: float, y: float, text: String, size := 18, col := HH.LIGHT, align := 0, width := -1.0) -> float:
	if fa <= 0.0 or text == "":
		return 0.0
	var z := fs(size)
	var w: float = s.g.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, z).x
	if width > 0.0:
		w = minf(w, width)
	var ox := 0.0 if align == 0 else (w * 0.5 if align == 1 else w)
	ci.draw_string(s.g.font, Vector2(x - ox, y + size), text, HORIZONTAL_ALIGNMENT_LEFT, width, z, Color(col, col.a * fa))
	return w


func tw(text: String, size: int) -> float:
	return s.g.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs(size)).x


## 像素字（5×7，按屏幕像素取整）；pos.y 是字的竖直中线
func px(pos: Vector2, text: String, kk: float, col: Color, align := 0, track := 1) -> float:
	if fa <= 0.0:
		return TUI.ptext_w(_pc, text, kk, track)
	return TUI.ptext(ci, _pc, pos, text, kk, Color(col, col.a * fa), track, align)


func px_w(text: String, kk: float, track := 1) -> float:
	return TUI.ptext_w(_pc, text, kk, track)


## 像素描边字（一圈 line、中间 fill）
func px_line(pos: Vector2, text: String, kk: float, line: Color, fill: Color, align := 0) -> float:
	var d := maxf(1.0, kk / 3.0)
	for o in [Vector2(-d, 0), Vector2(d, 0), Vector2(0, -d), Vector2(0, d), Vector2(-d, -d), Vector2(d, d), Vector2(-d, d), Vector2(d, -d)]:
		px(pos + o, text, kk, line, align)
	return px(pos, text, kk, fill, align)


func rect(r: Rect2, col: Color, filled := true, w := 1.0) -> void:
	if fa <= 0.0:
		return
	ci.draw_rect(r, Color(col, col.a * fa), filled, w if not filled else -1.0)


func poly(pts: PackedVector2Array, col: Color) -> void:
	if fa > 0.0:
		HH.fill(ci, pts, Color(col, col.a * fa))


## 平行四边形（左下 → 右上斜，斜率 HH.SKEW）
func para(r: Rect2, col: Color, line := Color(0, 0, 0, 0), w := 1.5) -> void:
	if fa > 0.0:
		HH.para(ci, r, Color(col, col.a * fa), Color(line, line.a * fa), w)


## 干员待机第一帧（screens/op_figure.gd：全员同一比例、脚底对齐框底、超出裁掉）。max_k = 每美术像素最多几屏幕像素。返回实际画出的矩形
func art(key: String, box: Rect2, mod := Color.WHITE, max_k := 6.0) -> Rect2:
	if fa <= 0.0:
		return Rect2()
	var idle: Dictionary = s.g.panel_ui.op_idle(key)
	return OpFig.draw(ci, idle, box, 0, Color(mod, mod.a * fa), minf(max_k, OpFig.k_for(box.size.y)))


func relic_tex(id: String) -> Texture2D:
	return s.g.run_stats._relic_tex(id)


func num(v: float) -> String:
	return s.g.run_stats.fmt_n(v)


func mmss(v: float) -> String:
	return "%02d:%02d" % [int(v) / 60, int(v) % 60]


func diff_name() -> String:
	return str(D.DIFF_PRESETS[clampi(s.g.preset, 0, D.DIFF_PRESETS.size() - 1)].name)


func grade() -> String:
	return s.grade(s.model, s.g.preset)


## 队长主题色（10-28 用户：结算 / 分享卡配色跟随本局队长；col 取 data/characters/*.json，选人 / 图鉴同一张）：
## OKHSL 明度夹 0.62–0.84、饱和封顶 0.85（过暗 / 过亮的设定色在暗底上仍能作字色）；失败同色降饱和、略压暗
static func lead_theme(c: Color, win: bool) -> Color:
	var sa := minf(c.ok_hsl_s, 0.85)
	var l := clampf(c.ok_hsl_l, 0.62, 0.84)
	if not win:
		sa *= 0.3
		l = minf(l, 0.66)
	return Color.from_ok_hsl(c.ok_hsl_h, sa, l)


func m() -> Dictionary:
	return s.model


## 主控行（rows 里 leader 的那一行；没有就第一行）
func leader_row() -> Dictionary:
	for r in s.rows:
		if r.leader:
			return r
	return s.rows[0] if not s.rows.is_empty() else {}


## 输出最高的干员行
func mvp_row() -> Dictionary:
	var best: Dictionary = {}
	for r in s.rows:
		if best.is_empty() or float(r.dmg) > float(best.dmg):
			best = r
	return best


## 失败时击倒者一行字 / 胜利时结局名
func sub_line() -> String:
	if won:
		return str(m().get("ending_name", ""))
	var kl: Dictionary = m().get("killer", {})
	var n := str(kl.get("name", ""))
	return ("击倒：" + n) if n != "" else "探索终止"


func boss_kills() -> int:
	var n := 0
	for b in m().get("bosses", []):
		if float(b.t1) >= 0.0 and not bool(b.get("retreat", false)):
			n += 1
	return n


## 关键藏品：按稀有度排（升华 / 遭诅 / 稀有 / 其余）
func key_relics(n: int) -> Array:
	var rank := {"升华": 0, "遭诅古物": 1, "稀有": 2}
	var out: Array = (m().get("relic_list", []) as Array).duplicate()
	out.sort_custom(func(a, b): return int(rank.get(str(a.rarity), 4)) < int(rank.get(str(b.rarity), 4)))
	return out.slice(0, n)


## 按钮表：[id, x, 宽, 文字, 主按钮, Rect2]；子类给位置
func btn_text(id: String) -> String:
	var tch: bool = Pad.touch_ui()
	var pad: bool = Pad.using
	match id:
		"share": return "分享战绩" if (pad or tch) else "分享  V"
		"records": return "作战数据  SELECT" if pad else ("作战数据" if tch else "作战数据  Tab")
		"runs": return "对局记录"
		"title": return "返回主界面  B" if pad else ("返回主界面" if tch else "返回主界面  Esc")
		"meta": return "认知塑造  Y" if pad else ("认知塑造" if tch else "认知塑造  X")
		"hunt": return ("寻访 ×%d  A" if pad else ("寻访 ×%d" if tch else "寻访 ×%d  Enter")) % Roster.tickets()
	return id


func btn(id: String, r: Rect2) -> Array:
	return [id, r.position.x, r.size.x, btn_text(id), id == "hunt" and Roster.tickets() > 0, r]


## 底栏缺省排法：一行从 x0 排到 x1，寻访最宽在最右；y / h 由子类定
func footer(y: float, h: float, x0 := 28.0, x1 := 1252.0, with_share := true) -> Array:
	var ids: Array = ["records"]
	if Cfg.runs_log_enabled():
		ids.append("runs")
	if with_share:
		ids.append("share")
	ids.append_array(["title", "meta", "hunt"])
	var ws := {"records": 150.0, "runs": 120.0, "share": 130.0, "title": 200.0, "meta": 180.0, "hunt": 260.0}
	var total := 0.0
	for id in ids:
		total += float(ws[id])
	var gap := (x1 - x0 - total) / maxf(1.0, ids.size() - 1)
	var out: Array = []
	var x := x0
	for id in ids:
		out.append(btn(id, Rect2(x, y, ws[id], h)))
		x += float(ws[id]) + gap
	return out
