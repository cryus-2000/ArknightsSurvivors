extends RefCounted
## 指点（选目标）阶段——**示意原型**（docs/196，只为录操作示意录像；缺省关：balance command/target_proto = 0 时整段不执行）。
## 圆盘选「点位」/「集火」后进入：局内保持慢动作（和圆盘同一个系数），出现一个准星——电脑跟鼠标，手机是「手指 + 向上偏移」；
## 「点位」= 点地面：全队去那里、在半径 R 内作战；「集火」= 点精英 / Boss：全队集火该目标（屏外的精英 / Boss 在屏幕边缘有小标签，指到标签上也算）。
## 松手 / 点击确认，右键 / Esc / 回到圆盘区取消。选点期间每个真实秒从作战时限里扣一点（command/pick_cost），上限 command/pick_cap 秒。
## 不抽随机数；不改镜头（缩放留给正式实现，见 docs/196 §6.4）。

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")

var g
var active := false
var mode := ""              # "point" / "focus"
var kind := "mouse"         # "mouse" / "touch" / "pad"
var t := 0.0                # 选点阶段已过的真实秒
var pointer := Vector2.ZERO # 鼠标 / 手指的 UI 坐标
var finger_id := -1
var reticle := Vector2.ZERO # 准星的 UI 坐标（手机 = 手指上方偏移）
var snapped = null          # 吸附到的精英 / Boss（敌人字典）
var valid := false
var world_pt := Vector2.ZERO
var _plan: Array = []       # 测试 / 录片：[[秒, 命令, 参数…], …]（--pickplan=mv@0.4:620:360,ok@2.8）
var _plan_read := false
var _goal := Vector2.INF    # 计划里「鼠标 / 手指」的目标位置（UI 坐标），pointer 朝它缓动
var _done_t := -1.0         # 确认 / 取消后的残影计时
var _done_ok := false
var _done_pt := Vector2.ZERO
var _done_target = null


func _init(game) -> void:
	g = game


static func proto_on() -> bool:
	return Bal.v("command/target_proto", 0.0) > 0.0


## 圆盘确认「点位」/「集火」后调用（command_wheel.confirm → squad.apply_command）
func begin(m: String, touch_finger := -1, finger_pos := Vector2.INF) -> void:
	if active or not proto_on():
		return
	active = true
	mode = m
	t = 0.0
	snapped = null
	valid = false
	_done_t = -1.0
	var vs: Vector2 = g.hud.size
	kind = "touch" if (g.touch != null and g.touch.active) else "mouse"
	finger_id = touch_finger
	pointer = finger_pos if finger_pos != Vector2.INF else (g.hud.get_local_mouse_position() if (kind == "mouse" and _plan.is_empty() and _plan_read) else vs / 2.0)
	_goal = Vector2.INF
	_refresh()


func _offset() -> Vector2:
	return Vector2(0.0, -96.0) if kind == "touch" else Vector2.ZERO


func cancel() -> void:
	_finish(false)


func confirm() -> void:
	if not valid:
		Sfx.play("ui_move", -10.0)
		_finish(false)
		return
	_finish(true)


func _finish(ok: bool) -> void:
	if not active:
		return
	_done_ok = ok
	_done_pt = world_pt
	_done_target = snapped
	_done_t = 0.0
	active = false
	if ok:
		Sfx.play("ui_ok", -6.0)
		g.squad.apply_order(mode, world_pt, snapped)
	else:
		Sfx.play("ui_move", -10.0)


## 候选：圈内的精英 / Boss / 部件（离队长不超过 order_r），按离队长远近
func _cands() -> Array:
	var out: Array = []
	var R: float = Bal.v("command/order_r", 560.0)
	for e in g.enemies:
		if e.dead or e.get("chest", false) or e.get("friendly", false):
			continue
		if not (e.boss or e.elite or e.get("part", false)):
			continue
		if e.pos.distance_to(g.ppos) <= R * 1.6:
			out.append(e)
	out.sort_custom(func(a, b): return a.pos.distance_squared_to(g.ppos) < b.pos.distance_squared_to(g.ppos))
	return out


func _refresh() -> void:
	var ct: Transform2D = g.hud_ct()
	var vs: Vector2 = g.hud.size
	reticle = pointer + _offset()
	world_pt = ct.affine_inverse() * reticle
	var R: float = Bal.v("command/order_r", 560.0)
	snapped = null
	var snap_px: float = 100.0 if kind == "touch" else 64.0
	var bd: float = snap_px
	var cands: Array = _cands()
	for e in cands:
		var sp: Vector2 = ct * e.pos
		var chip: bool = not Rect2(Vector2(20, 20), vs - Vector2(40, 40)).has_point(sp)
		if chip:
			sp = _edge(sp, vs)
		var d: float = sp.distance_to(reticle)
		if d < bd:
			bd = d
			snapped = e
	if mode == "focus":
		valid = snapped != null
		if snapped != null:
			world_pt = snapped.pos
	else:
		valid = world_pt.distance_to(g.ppos) <= R
		if not valid:
			world_pt = g.ppos + (world_pt - g.ppos).limit_length(R)


func _edge(sp: Vector2, vs: Vector2) -> Vector2:
	var c: Vector2 = vs / 2.0
	var d: Vector2 = (sp - c)
	if d.length() < 1.0:
		return c
	var k: float = minf(absf((vs.x / 2.0 - 40.0) / maxf(absf(d.x), 0.01)), absf((vs.y / 2.0 - 40.0) / maxf(absf(d.y), 0.01)))
	return c + d * k


func update(rd: float) -> void:
	_run_plan()
	if _done_t >= 0.0:
		_done_t += rd
		if _done_t > 0.6:
			_done_t = -1.0
	if not active:
		return
	if g.state != g.S.PLAY:
		_finish(false)
		return
	t += rd
	if _goal != Vector2.INF:
		pointer += (_goal - pointer) * (1.0 - exp(-rd * 9.0))   # 计划里的「鼠标 / 手指」缓动过去（像人手挪）
	_refresh()
	g.squad.stamina = maxf(0.0, g.squad.stamina - Bal.v("command/pick_cost", 0.03) * rd)   # 选点期间扣作战时限（防滥用，docs/196 §5）
	if t >= Bal.v("command/pick_cap", 3.0):
		confirm()   # 到上限：落在有效目标上就算数，否则取消


func input(event: InputEvent) -> bool:
	if not active:
		return false
	if event is InputEventKey:
		if event.pressed and not event.echo and Pad.kc(event) in [KEY_ESCAPE, KEY_F, KEY_K]:
			cancel()
		return true
	if event is InputEventMouseMotion:
		if kind == "mouse":
			pointer = event.position / Cfg.ui_k
		return false
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				pointer = event.position / Cfg.ui_k
				_refresh()
				confirm()
		return true
	if event is InputEventScreenDrag:
		if kind == "touch" and (finger_id < 0 or event.index == finger_id):
			pointer = event.position / Cfg.ui_k
		return false
	if event is InputEventScreenTouch:
		if kind == "touch" and not event.pressed and (finger_id < 0 or event.index == finger_id):
			pointer = event.position / Cfg.ui_k
			_refresh()
			confirm()
		return true
	return false


# ---------------------------------------------------------------- 绘制

const C_ACC := Color(0.122, 0.659, 0.941)
const C_OK := Color(0.184, 0.827, 0.627)
const C_BAD := Color(1.0, 0.239, 0.545)


func draw(vs: Vector2) -> void:
	if not proto_on():
		return
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var ct: Transform2D = g.hud_ct()
	var sq = g.squad
	# 已下达的指令：点位 = 地面一圈 + 每名突击队友一条虚线；集火 = 目标括号
	if sq.order_kind != "" and not active:
		_draw_order(hud, ct)
	if _done_t >= 0.0 and not active and _done_ok:
		var a: float = 1.0 - _done_t / 0.6
		var sp: Vector2 = ct * _done_pt
		hud.draw_arc(sp, 26.0 + 90.0 * (1.0 - a), 0.0, TAU, 40, Color(C_OK.r, C_OK.g, C_OK.b, a * 0.8), 2.5)
	_caption(hud, font, vs)
	if not active:
		return
	var e: float = clampf(t / 0.1, 0.0, 1.0)
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05, 0.22 * e))
	var lp: Vector2 = ct * g.ppos
	var R: float = Bal.v("command/order_r", 560.0)
	var Rs: float = ct.basis_xform(Vector2(R, 0)).length()
	# 指点范围：队长周围一圈虚线（超出算「太远」）
	for i in 48:
		var a0: float = TAU * float(i) / 48.0
		hud.draw_arc(lp, Rs, a0, a0 + TAU / 96.0, 4, Color(1, 1, 1, 0.3 * e), 1.5)
	hud.draw_string(font, lp + Vector2(Rs * 0.7071 + 6.0, -Rs * 0.7071), "指点范围", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45 * e))
	# 屏外的精英 / Boss：边缘小标签
	var show_chips: bool = mode == "focus"
	for en in _cands():
		var sp: Vector2 = ct * en.pos
		var inside: bool = Rect2(Vector2(20, 20), vs - Vector2(40, 40)).has_point(sp)
		var col: Color = C_BAD if en.boss else Color(1.0, 0.62, 0.3)
		var picked: bool = is_same(en, snapped)
		if inside:
			if mode == "focus":
				_bracket(hud, sp + Vector2(0, -float(en.r) * 0.5), float(en.r) * 1.25 + 8.0, Color(col.r, col.g, col.b, 0.9 if picked else 0.5), picked)
		elif show_chips:
			var cp: Vector2 = _edge(sp, vs)
			hud.draw_circle(cp, 18.0, Color(0.03, 0.05, 0.07, 0.9))
			hud.draw_arc(cp, 18.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 1.0 if picked else 0.7), 3.0 if picked else 1.8)
			UI.text(hud, font, cp + Vector2(-20, 5), "Boss" if en.boss else "精英", 11, col, HORIZONTAL_ALIGNMENT_CENTER, 40)
	# 点位：地面一圈（半径 R_point）；无效（超出范围）变红
	if mode == "point":
		var pr: float = ct.basis_xform(Vector2(Bal.v("command/order_pt_r", 240.0), 0)).length()
		var col2: Color = C_ACC if valid else C_BAD
		var cp2: Vector2 = ct * world_pt
		hud.draw_circle(cp2, pr, Color(col2.r, col2.g, col2.b, 0.10 * e))
		hud.draw_arc(cp2, pr, 0.0, TAU, 56, Color(col2.r, col2.g, col2.b, 0.9 * e), 2.0)
		for en2 in g.squad.ops:
			if en2.is_leader or not en2.cmd_roam() or en2.pos == Vector2.INF:
				continue
			_dash(hud, ct * en2.pos, cp2, Color(col2.r, col2.g, col2.b, 0.35 * e))
	# 准星 + 手指
	var rp: Vector2 = reticle
	var rc: Color = C_ACC if valid else C_BAD
	hud.draw_arc(rp, 16.0, 0.0, TAU, 28, rc, 2.0)
	hud.draw_line(rp + Vector2(-26, 0), rp + Vector2(-8, 0), rc, 2.0)
	hud.draw_line(rp + Vector2(8, 0), rp + Vector2(26, 0), rc, 2.0)
	hud.draw_line(rp + Vector2(0, -26), rp + Vector2(0, -8), rc, 2.0)
	hud.draw_line(rp + Vector2(0, 8), rp + Vector2(0, 26), rc, 2.0)
	if kind == "touch":
		hud.draw_circle(pointer, 30.0, Color(1, 1, 1, 0.14))
		hud.draw_arc(pointer, 30.0, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 2.0)
		hud.draw_line(pointer + Vector2(0, -30), rp + Vector2(0, 14), Color(1, 1, 1, 0.35), 1.5)
	# 文案：类型 / 状态 / 提示 + 作战时限消耗
	var title: String = "指点 · 点位" if mode == "point" else "指点 · 集火"
	var stt: String
	if mode == "focus":
		stt = ("锁定 %s" % ("Boss" if snapped.boss else "精英")) if snapped != null else "把准星移到精英或 Boss 上"
	else:
		stt = "全队前往此处作战" if valid else "太远了"
	var tx: float = vs.x / 2.0
	UI.text(hud, font, Vector2(tx - 200, vs.y * 0.80), title, 18, Color(C_ACC.r, C_ACC.g, C_ACC.b, e), HORIZONTAL_ALIGNMENT_CENTER, 400)
	UI.text(hud, font, Vector2(tx - 200, vs.y * 0.80 + 24), stt, 14, Color(1, 1, 1, e) if valid else Color(C_BAD.r, C_BAD.g, C_BAD.b, e), HORIZONTAL_ALIGNMENT_CENTER, 400)
	var tip: String = ("松手确认 · 拖回圆盘处取消" if kind == "touch" else "左键确认 · 右键 / Esc 取消")
	UI.text(hud, font, Vector2(tx - 220, vs.y * 0.80 + 46), tip + "  ·  选点中每秒扣 3% 作战时限", 12, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e), HORIZONTAL_ALIGNMENT_CENTER, 440)
	if kind == "touch" and mode == "focus":
		var b := Rect2(Vector2(tx - 110, vs.y * 0.80 + 62), Vector2(220, 34))
		hud.draw_rect(b, Color(0.03, 0.05, 0.07, 0.85))
		hud.draw_rect(b, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.8), false, 1.5)
		UI.text(hud, font, b.position + Vector2(0, 22), "最近的 Boss / 精英", 14, C_BAD, HORIZONTAL_ALIGNMENT_CENTER, b.size.x)


## 录片说明字幕（--democap 才画，只在示意录像里用）：按当前状态自动换——圆盘开着 / 选点中 / 指令生效中
var _cap_on := -1

func _caption(hud: CanvasItem, font: Font, vs: Vector2) -> void:
	if _cap_on < 0:
		_cap_on = 1 if Cfg.dev_args().has("--democap") else 0
	if _cap_on == 0:
		return
	var touch: bool = g.touch != null and g.touch.active
	var dev: String = "手机 · 触屏" if touch else "电脑 · 鼠标"
	var line := ""
	if g.wheel.is_open:
		line = "① 点「指挥」键弹出圆盘，局内放慢 → 选「点位」（去那里）或「集火」（打这个）"
	elif active:
		if touch:
			line = "② 手指不抬起，拖到目标：准星在手指上方；松手确认，拖回圆盘处取消" if mode == "point" else "② 拖向精英 / Boss（屏外的看边缘标签），或点下方「最近的 Boss / 精英」；松手确认"
		else:
			line = "② 准星跟着鼠标：点地面（点位，超出虚线圈算太远）· 左键确认 · 右键 / Esc 取消" if mode == "point" else "② 把准星移到精英 / Boss 上（屏外的看边缘标签），左键确认 · 右键 / Esc 取消"
	elif g.squad.order_kind == "point":
		line = "③ 全队前往点位、在圈内作战；圈里没敌人 2.5 秒后自动归队；作战时限照扣"
	elif g.squad.order_kind == "focus":
		line = "③ 全队集火标记的目标；目标死了指令结束，作战时限照扣"
	if line == "":
		return
	var w: float = minf(vs.x - 40.0, 900.0)
	var r := Rect2(Vector2((vs.x - w) / 2.0, vs.y * 0.115), Vector2(w, 52))
	hud.draw_rect(r, Color(0.02, 0.04, 0.06, 0.82))
	hud.draw_rect(r, Color(C_ACC.r, C_ACC.g, C_ACC.b, 0.8), false, 1.5)
	UI.text(hud, font, r.position + Vector2(0, 18), "示意原型 · " + dev, 12, Color(C_ACC.r, C_ACC.g, C_ACC.b), HORIZONTAL_ALIGNMENT_CENTER, w)
	UI.text(hud, font, r.position + Vector2(0, 40), line, 15, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_order(hud: CanvasItem, ct: Transform2D) -> void:
	var sq = g.squad
	if sq.order_kind == "point":
		var pr: float = ct.basis_xform(Vector2(Bal.v("command/order_pt_r", 240.0), 0)).length()
		var cp: Vector2 = ct * sq.order_pos
		hud.draw_circle(cp, pr, Color(C_ACC.r, C_ACC.g, C_ACC.b, 0.07))
		hud.draw_arc(cp, pr, 0.0, TAU, 56, Color(C_ACC.r, C_ACC.g, C_ACC.b, 0.75), 2.0)
		hud.draw_arc(cp, 10.0, 0.0, TAU, 20, Color(C_ACC.r, C_ACC.g, C_ACC.b, 0.9), 2.0)
	elif sq.order_kind == "focus" and sq.order_target != null and not sq.order_target.dead:
		var en = sq.order_target
		var sp: Vector2 = ct * en.pos
		_bracket(hud, sp + Vector2(0, -float(en.r) * 0.5), float(en.r) * 1.25 + 10.0, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.95), true)
		for o in sq.ops:
			if o.is_leader or not o.cmd_roam() or o.pos == Vector2.INF:
				continue
			_dash(hud, ct * o.pos, sp, Color(C_BAD.r, C_BAD.g, C_BAD.b, 0.3))


func _bracket(ci: CanvasItem, c: Vector2, r: float, col: Color, strong: bool) -> void:
	var w: float = 2.6 if strong else 1.6
	var l: float = r * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx * r, sy * r) + c
			ci.draw_line(corner, corner + Vector2(-sx * l, 0), col, w)
			ci.draw_line(corner, corner + Vector2(0, -sy * l), col, w)


func _dash(ci: CanvasItem, a: Vector2, b: Vector2, col: Color) -> void:
	var d: Vector2 = b - a
	var n: int = int(d.length() / 14.0)
	for i in range(0, n, 2):
		ci.draw_line(a + d * (float(i) / n), a + d * (float(i + 1) / n), col, 1.5)


# ---------------------------------------------------------------- 测试 / 录片计划
## --pickplan=mv@0.4:620:360,ok@2.6（秒 = 选点开始后的真实秒；mv 把「鼠标 / 手指」缓动到 UI 坐标 x:y，ok 确认，cancel 取消；
## fx / fy 版本 mvf@0.4:500:420 = 屏幕宽 / 高的千分比）
func _run_plan() -> void:
	if not _plan_read:
		_plan_read = true
		for a in Cfg.dev_args():
			if a.begins_with("--pickplan="):
				for tok in a.substr(11).split(","):
					var at: PackedStringArray = tok.split("@")
					if at.size() != 2:
						continue
					var ps: PackedStringArray = at[1].split(":")
					var row: Array = [float(ps[0]), at[0]]
					for k in range(1, ps.size()):
						row.append(float(ps[k]))
					_plan.append(row)
	while active and not _plan.is_empty() and t >= float(_plan[0][0]):
		var s: Array = _plan.pop_front()
		match str(s[1]):
			"mv":
				_goal = Vector2(float(s[2]), float(s[3]))
			"mvf":
				var vs: Vector2 = g.hud.size
				_goal = Vector2(float(s[2]) / 1000.0 * vs.x, float(s[3]) / 1000.0 * vs.y)
			"horde":   # 「鼠标 / 手指」缓动到范围内最密的一团杂兵（离队长 ≥ 200 的）的屏幕位置（录片用）
				var ct3: Transform2D = g.hud_ct()
				var R3: float = Bal.v("command/order_r", 560.0)
				var bestp := Vector2.INF
				var bestc := -1
				for e3 in g.enemies:
					if e3.dead or e3.boss or e3.elite or e3.get("chest", false) or e3.get("friendly", false):
						continue
					var dl: float = e3.pos.distance_to(g.ppos)
					if dl < 200.0 or dl > R3 * 0.9:
						continue
					var cnt := 0
					for e4 in g.enemies:
						if not e4.dead and e4.pos.distance_squared_to(e3.pos) < 14400.0:
							cnt += 1
					if cnt > bestc:
						bestc = cnt
						bestp = e3.pos
				if bestp != Vector2.INF:
					_goal = ct3 * bestp - _offset()
			"snap":   # 「鼠标 / 手指」缓动到离队长最近的精英 / Boss 的屏幕位置（录片用，手机的话准星落在目标上 = 手指在目标下方一个偏移）
				var cs: Array = _cands()
				if not cs.is_empty():
					var ct2: Transform2D = g.hud_ct()
					var vs2: Vector2 = g.hud.size
					var sp2: Vector2 = ct2 * (cs[int(s[2]) if s.size() > 2 else 0].pos)
					if not Rect2(Vector2(20, 20), vs2 - Vector2(40, 40)).has_point(sp2):
						sp2 = _edge(sp2, vs2)
					_goal = sp2 - _offset()
			"ok":
				_refresh()
				confirm()
			"cancel":
				cancel()
