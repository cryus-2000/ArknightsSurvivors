## 终结技慢动作瞄准 v2（docs/209 §3，开关 balance ult/aim；0 = 旧的「移动键挪落点、0.25 倍 0.5 秒 + 按住最多 1 秒」）。
## 按下 Q 后 ult/aim_slow（0.3）倍速、最长 ult/aim_max（1.5）真实秒：电脑跟鼠标、手机拖终结技键、手柄右摇杆（没推看左摇杆），
## 没有这些输入时照旧用移动键挪；松开 Q / 手指释放，轻点（< TAP）则保持瞄准、再按一次 Q 或点左键释放，到上限自动释放。
## 自身周围类（aim_kind none）不需要选：只闪一下范围就放。机器人 / 批跑不走这里（旧的自动瞄准，同 seed 不变）。
## 画面：HUD 层画 PRTS 范围格 + 取景角标 + 信息板，和指挥的部署范围格 / 圆盘同一套配色（command_wheel 的 C_* 与 command_pick 的格子）。
extends RefCounted

const Bal = preload("res://scripts/core/balance.gd")
const UI = preload("res://scripts/ui.gd")
const UM = preload("res://scripts/ui_motion.gd")
const Moves = preload("res://scripts/run/ult_moves.gd")

const TAP := 0.2          # 轻点 / 按住的分界（真实秒）
const REACH := 520.0      # 落点离队长最远（同旧口径）
const CELL := 48.0        # 范围格边长（同 command_pick.CELL）
const MOUSE_DEAD := 6.0   # 鼠标挪动多少像素算「在用鼠标瞄」

static var _arg := -1     # --ultaim：autotest 录像也走 v2（缺省 autotest 不走）
static var _plan_src := ""


static func on(u) -> bool:
	if Bal.vi("ult/aim", 1) <= 0 or u.g.bot != null:
		return false
	if _arg < 0:
		_arg = 0
		for a in Cfg.dev_args():
			if a == "--ultaim" or a.begins_with("--ultaimplan="):
				_arg = 1
				if a.begins_with("--ultaimplan="):
					_plan_src = a.substr(13)
	return not u.g.autotest or _arg == 1


## 进入瞄准（ult._begin 调）：记下按下时刻与鼠标起点，返回 [aim_min, aim_max]（游戏秒）
static func begin(u) -> Array:
	var sc: float = Bal.v("ult/aim_slow", 0.3)
	u.aim_v2 = true
	u.aim_latched = false
	u.aim_src = "key"
	u._q_rt0 = UM.now()
	u._aim_rt0 = UM.now()
	u._aim_plan = _parse_plan()
	u._mouse0 = u.g.hud.get_local_mouse_position() if u.g.get("hud") != null else Vector2.ZERO
	var mn: float = Bal.v("ult/aim_min_t", 0.12) * sc
	if u.aim_kind == "none":
		return [mn, mn]   # 自身周围：不用选，闪一下范围就放
	return [mn, Bal.v("ult/aim_max", 1.5) * sc]


## 每帧（ult._tick_ult 的瞄准段）：按输入源写落点 / 方向
static func tick(u, dt: float) -> void:
	var g = u.g
	var c = u.caster
	if c == null:
		return
	_run_plan(u)
	if u.aim_src == "plan":
		return
	var tc = g.get("touch")
	if tc != null and tc.active and tc.skill_id >= 0:
		u.aim_src = "touch"   # touch._ult_aim 每帧写拖动的落点 / 方向
		return
	var pv := Vector2.ZERO
	if Pad.device >= 0:
		pv = Vector2(Input.get_joy_axis(Pad.device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(Pad.device, JOY_AXIS_RIGHT_Y))
		if pv.length() < 0.35:
			pv = Vector2(Input.get_joy_axis(Pad.device, JOY_AXIS_LEFT_X), Input.get_joy_axis(Pad.device, JOY_AXIS_LEFT_Y))
	if pv.length() >= 0.35:
		u.aim_src = "pad"
		_point_at(u, c.pos + pv.normalized() * clampf((pv.length() - 0.35) / 0.6, 0.0, 1.0) * REACH, pv.normalized())
		return
	if g.get("hud") != null and not (tc != null and tc.active):
		var mp: Vector2 = g.hud.get_local_mouse_position()
		if u.aim_src == "mouse" or mp.distance_to(u._mouse0) > MOUSE_DEAD:
			u.aim_src = "mouse"
			var w: Vector2 = g.hud_ct().affine_inverse() * mp
			var d: Vector2 = w - c.pos
			_point_at(u, w, d.normalized() if d.length() > 1.0 else u.aim_dir)
			return
	var mv: Vector2 = g.move_in
	if mv != Vector2.ZERO:
		u.aim_src = "key"
		if u.aim_kind == "point":
			u.aim += mv.normalized() * Bal.v("ult/aim_spd", 2400.0) * dt
			_clamp(u)
		elif u.aim_kind == "dir":
			u.aim_dir = mv.normalized()


static func _point_at(u, w: Vector2, d: Vector2) -> void:
	if u.aim_kind == "point":
		u.aim = w
		_clamp(u)
	elif u.aim_kind == "dir" and d != Vector2.ZERO:
		u.aim_dir = d


static func _clamp(u) -> void:
	var off: Vector2 = u.aim - u.caster.pos
	if off.length() > REACH:
		u.aim = u.caster.pos + off.normalized() * REACH


## 松开 Q：按下不到 TAP 秒 = 轻点，保持瞄准（再按一次 Q / 点左键释放）
static func release(u) -> void:
	if u.phase == "aim" and u.aim_kind != "none" and UM.now() - u._q_rt0 < TAP:
		u.aim_latched = true


## 鼠标左键（game._unhandled_input）：瞄准中点一下 = 释放
static func click(u) -> bool:
	if not u.aim_v2 or u.phase != "aim":
		return false
	u.aim_latched = false
	u.q_held = false
	u.confirm_aim()
	return true


# ---------------------------------------------------------------- 录片计划：--ultaimplan=rel@0.3:320:-140,ok@1.0（秒 = 进入瞄准后的真实秒；rel 把落点缓动到「队长 + 偏移」；ok 释放）
static func _parse_plan() -> Array:
	var out: Array = []
	if _plan_src == "":
		return out
	for tok in _plan_src.split(","):
		var at: PackedStringArray = tok.split("@")
		if at.size() != 2:
			continue
		var ps: PackedStringArray = at[1].split(":")
		var row: Array = [float(ps[0]), at[0]]
		for k in range(1, ps.size()):
			row.append(float(ps[k]))
		out.append(row)
	return out


static func _run_plan(u) -> void:
	var pl: Array = u._aim_plan
	if pl.is_empty() and u.aim_src != "plan":
		return
	var rt: float = UM.now() - u._aim_rt0
	while not pl.is_empty() and rt >= float(pl[0][0]):
		var s: Array = pl.pop_front()
		match str(s[1]):
			"rel":
				u.aim_src = "plan"
				u._plan_goal = Vector2(float(s[2]), float(s[3]))
			"ok":
				u.aim_latched = false
				u.q_held = false
				u.confirm_aim()
				return
	if u.aim_src == "plan":
		var goal: Vector2 = u.caster.pos + u._plan_goal
		var cur: Vector2 = u.aim if u.aim_kind == "point" else u.caster.pos + u.aim_dir * u._plan_goal.length()
		var nxt: Vector2 = cur.lerp(goal, 0.12)   # 像人手挪鼠标
		_point_at(u, nxt, (nxt - u.caster.pos).normalized())


# ---------------------------------------------------------------- 范围形状（预览用；和各招实际判定同一组 balance 键）
## {"kind": "disc", "c", "r"} / {"kind": "band", "o", "d", "len", "hw", "back"} / {"kind": "sector", "o", "d", "r", "half"}
static func shape_of(u) -> Dictionary:
	var c = u.caster
	var id: String = str(c.id)
	var r: float = Moves.aim_r(id) if u.kind != "cult" else u.VIEW.x * 0.5
	if u.aim_kind == "point":
		return {"kind": "disc", "c": u.aim, "r": r}
	if u.aim_kind == "dir":
		match id:
			"skadi":
				return {"kind": "band", "o": c.pos, "d": u.aim_dir, "len": Bal.v("ult/sd_len", 1500.0), "hw": Bal.v("ult/sd_w", 920.0) * 0.5, "back": Bal.v("ult/sd_back", 200.0)}
			"suzuran":
				return {"kind": "band", "o": c.pos, "d": u.aim_dir, "len": Bal.v("ult/su_len", 900.0), "hw": Bal.v("ult/su_w", 1000.0) * 0.5, "back": Bal.v("ult/su_back", 150.0)}
			"saria":
				return {"kind": "sector", "o": c.pos, "d": u.aim_dir, "r": r, "half": Bal.v("ult/sa_half", 1.05)}
		return {"kind": "sector", "o": c.pos, "d": u.aim_dir, "r": r, "half": 0.6}
	return {"kind": "disc", "c": c.pos, "r": r}


static func _inside(s: Dictionary, p: Vector2) -> bool:
	match str(s.kind):
		"disc":
			return p.distance_to(s.c) <= float(s.r)
		"band":
			var q: Vector2 = p - Vector2(s.o)
			var along: float = q.dot(s.d)
			return along >= -float(s.back) and along <= float(s.len) and absf(q.dot(Vector2(s.d).orthogonal())) <= float(s.hw)
		"sector":
			var v: Vector2 = p - Vector2(s.o)
			return v.length() <= float(s.r) and absf(angle_difference(v.angle(), Vector2(s.d).angle())) <= float(s.half)
	return false


## 形状的包围圆（只遍历这一圈里的格子）
static func _bound(s: Dictionary) -> Array:
	match str(s.kind):
		"disc":
			return [s.c, float(s.r)]
		"band":
			var mid: Vector2 = Vector2(s.o) + Vector2(s.d) * (float(s.len) - float(s.back)) * 0.5
			return [mid, Vector2((float(s.len) + float(s.back)) * 0.5, float(s.hw)).length()]
	return [s.o, float(s.r)]


# ---------------------------------------------------------------- 绘制（hud.gd 在指点之后调；同圆盘 / 指点的 PRTS 配色）
static func draw(u, vs: Vector2) -> void:
	if not u.aim_v2 or u.phase != "aim" or u.caster == null or u.caster.pos == Vector2.INF:
		return
	var g = u.g
	var W = g.wheel
	W._apply_style()
	var P = g.pick
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var ct: Transform2D = g.hud_ct()
	var rt: float = UM.now() - u._aim_rt0
	var e: float = clampf(rt / 0.12, 0.0, 1.0)
	var oc: Color = u._col(u.caster)
	var acc: Color = W.C_ACC.lerp(oc, 0.45)
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.012, 0.016, 0.22 * e))
	var s: Dictionary = shape_of(u)
	var lp: Vector2 = ct * u.caster.pos
	if u.aim_kind == "point":
		P._range_ring(hud, font, lp, ct.basis_xform(Vector2(REACH, 0)).length(), e, int(REACH))
	_cells(hud, ct, s, acc, e)
	var tip_w: Vector2
	match str(s.kind):
		"disc":
			tip_w = s.c
		"band":
			tip_w = Vector2(s.o) + Vector2(s.d) * float(s.len) * 0.6
		_:
			tip_w = Vector2(s.o) + Vector2(s.d) * float(s.r) * 0.75
	var tp: Vector2 = ct * tip_w
	if u.aim_kind != "none":
		P._dash(hud, lp, tp, Color(acc.r, acc.g, acc.b, 0.55 * e), true)
		P._corners(hud, tp, 22.0, Color(acc.r, acc.g, acc.b, e), 2.0)
		hud.draw_rect(Rect2(tp - Vector2(2, 2), Vector2(4, 4)), Color(acc.r, acc.g, acc.b, e))
	# 底部信息板：同指点的切角板 + 警戒斜纹；剩余慢动作时间条
	var w: float = minf(vs.x - 40.0, 440.0)
	var r := Rect2(Vector2((vs.x - w) / 2.0, vs.y * 0.76), Vector2(w, 76))
	P._plate(hud, r, e)
	UI.ctext(hud, font, r.position + Vector2(34, 14), "PRTS // ULTIMATE · " + ("AREA" if u.aim_kind == "point" else ("VECTOR" if u.aim_kind == "dir" else "SELF")), 9, Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.6 * e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	UI.text(hud, font, r.position + Vector2(34, 35), "%s · 终结技" % u.caster.display_name(), 17, Color(acc.r, acc.g, acc.b, e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	UI.text(hud, font, r.position + Vector2(34, 53), "选落点" if u.aim_kind == "point" else ("选方向" if u.aim_kind == "dir" else "以自身为中心"), 13, Color(1, 1, 1, e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	UI.text(hud, font, r.position + Vector2(34, 69), _tip(u), 11, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	var left: float = 1.0 - clampf(u._phase_t / maxf(0.001, u._aim_max), 0.0, 1.0)
	hud.draw_rect(Rect2(r.position + Vector2(16, r.size.y - 3), Vector2((r.size.x - 16) * left, 3)), Color(acc.r, acc.g, acc.b, 0.9 * e))


static func _tip(u) -> String:
	match str(u.aim_src):
		"touch":
			return "拖动选择 · 松手释放"
		"pad":
			return "摇杆选择 · 松开释放"
	if u.aim_latched:
		return "鼠标选择 · 再按 Q 或左键释放"
	return "鼠标选择 · 松开 Q 释放"


## 范围格：形状里的 48 格，越靠外越淡、边上一圈亮边（同 command_pick._tiles 的画法）
static func _cells(hud: CanvasItem, ct: Transform2D, s: Dictionary, col: Color, e: float) -> void:
	var b: Array = _bound(s)
	var center: Vector2 = b[0]
	var rr: float = b[1]
	var n: int = int(ceil(rr / CELL))
	var base := Vector2(floor(center.x / CELL), floor(center.y / CELL))
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var cc := (base + Vector2(ix, iy) + Vector2(0.5, 0.5)) * CELL
			if not _inside(s, cc):
				continue
			var edge := false
			for dv in [Vector2(CELL, 0), Vector2(-CELL, 0), Vector2(0, CELL), Vector2(0, -CELL)]:
				if not _inside(s, cc + dv):
					edge = true
					break
			var k: float = 1.0 - clampf(cc.distance_to(center) / maxf(1.0, rr), 0.0, 1.0)
			var q0: Vector2 = ct * (cc - Vector2(CELL, CELL) * 0.46)
			var q1: Vector2 = ct * (cc + Vector2(CELL, CELL) * 0.46)
			var rc := Rect2(q0, q1 - q0)
			hud.draw_rect(rc, Color(col.r, col.g, col.b, (0.06 + 0.14 * k) * e))
			hud.draw_rect(rc, Color(col.r, col.g, col.b, (0.8 if edge else 0.2) * e), false, 1.4 if edge else 1.0)
