extends RefCounted
## 指点（选目标）阶段——**示意原型**（docs/196，只为录操作示意录像；缺省关：balance command/target_proto = 0 时整段不执行）。
## 圆盘选「点位」/「集火」后进入：局内保持慢动作（和圆盘同一个系数），出现一个准星——电脑跟鼠标，手机是「手指 + 向上偏移」；
## 「点位」= 点地面：全队去那里、在半径 R 内作战；「集火」= 点精英 / Boss：全队集火该目标（屏外的精英 / Boss 在屏幕边缘有小标签，指到标签上也算）。
## 松手 / 点击确认，右键 / Esc / 回到圆盘区取消。选点期间每个真实秒从作战时限里扣一点（command/pick_cost），上限 command/pick_cap 秒。
## 不抽随机数；不改镜头（缩放留给正式实现，见 docs/196 §6.4）。
## 触屏「点选 → 预选 → 再点确认」（11-07 用户「手机端指挥圆盘一点不明确」，docs/315；command/touch_confirm = 1 缺省，0 = 旧的按住拖、松手确认）：
##   选完指令后手指抬起也不下令。集火：场上可选的精英 / Boss 框常亮（白）→ 点一只 = 预选（框变金色）→ 再点同一只 = 下令；
##   点别的目标 = 换预选，点空白 = 取消（落在摇杆区时这一下同时起摇杆）。部署：点虚线圈内的地面 = 预选落点（金色标记）→ 再点标记 = 下令，
##   点别处 = 换落点。两种都可点信息板上的「取消」或「指挥」键退出。没有准星偏移（点哪儿就是哪儿）。时限 command/pick_cap_touch 秒，
##   到时有预选就按预选下令，没有就取消

const UI = preload("res://scripts/ui.gd")
const Bal = preload("res://scripts/core/balance.gd")
const Tactics = preload("res://scripts/characters/tactics.gd")   # 指挥 v2：部署的阻挡数 / 职业（docs/209 §1.4）

var g
var active := false
var mode := ""              # "point"（移动）/ "clear"（肃清）/ "focus"（集火）
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
var _clear_at := Vector2.INF   # 肃清目标格最近一次「亮起」的位置与时刻（毫秒）：下令 / 目标区挪动超过 2 格时整片亮 1.5 秒
var _clear_ms := 0
# 触屏点选确认（docs/315）
var tap := false            # 本次选点走「点选 → 预选 → 再点确认」
var pre_set := false        # 已有预选
var pre_target = null       # 集火的预选目标（敌人字典）
var pre_pt := Vector2.ZERO  # 部署的预选落点（世界坐标）
var _pre_t := 0.0           # 预选换了之后的真实秒（金框弹一下）
var _miss_t := -1.0         # 部署点到圈外：警示字留 1 秒
var _cancel_r := Rect2()    # 信息板「取消」键（UI 坐标，绘制时更新）
var _near_r := Rect2()      # 集火「最近的 Boss / 精英」键
var _begin_frame := -1
const PRE_COL := Color(1.0, 0.82, 0.26)   # 预选色（金）
const CAND_COL := Color(0.93, 0.95, 0.96)  # 可选目标（PRTS 白，11-07 用户：可选都用白、选上用金）
const TAP_SAME := 64.0      # 再点确认的容差（屏幕像素）


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
	tap = kind == "touch" and Bal.v("command/touch_confirm", 1.0) > 0.0
	_begin_frame = Engine.get_process_frames()
	pre_set = false
	pre_target = null
	_miss_t = -1.0
	_cancel_r = Rect2()
	_near_r = Rect2()
	_refresh()


func _offset() -> Vector2:
	return Vector2(0.0, -96.0) if kind == "touch" and not tap else Vector2.ZERO


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
	if tap:   # 点选确认：没有准星，状态全由预选决定
		if pre_target != null and pre_target.dead:
			pre_set = false
			pre_target = null
		snapped = pre_target if mode == "focus" else null
		valid = pre_set
		world_pt = (pre_target.pos if pre_target != null else pre_pt) if pre_set else g.ppos
		reticle = ct * world_pt
		return
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
	_pre_t += rd
	if _miss_t >= 0.0:
		_miss_t += rd
		if _miss_t > 1.0:
			_miss_t = -1.0
	if tap:
		_refresh()
		g.squad.stamina = maxf(0.0, g.squad.stamina - Bal.v("command/pick_cost", 0.03) * rd)
		if t >= Bal.v("command/pick_cap_touch", 6.0):
			if pre_set:
				confirm()
			else:
				cancel()
		return
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
	if event is InputEventMouseButton and kind == "touch" and event.device == InputEvent.DEVICE_ID_EMULATION:
		return true   # 触点模拟出来的鼠标键（Godot 缺省 emulate_mouse_from_touch）：触点本身已经处理过，这一下不能再当「左键确认」
	if event is InputEventMouseButton and tap:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tap_at(event.position / Cfg.ui_k)   # 桌面 --touch 调试：鼠标当手指点
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		return true
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				pointer = event.position / Cfg.ui_k
				_refresh()
				confirm()
		return true
	if tap and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		# 点选确认只认「按下」；抬起 / 拖动放行给 touch.gd（摇杆的手指照常松开 / 拖动）
		if event is InputEventScreenTouch and event.pressed:
			return tap_at(event.position / Cfg.ui_k)
		return false
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


## 触屏点选确认（docs/315）：p = UI 坐标的一次按下。返回 true = 吃掉这一下（false = 交给 touch.gd，例如起摇杆 / 按冲刺）
func tap_at(p: Vector2) -> bool:
	if not active or not tap:
		return false
	if Engine.get_process_frames() == _begin_frame:
		return true   # 选指令的那一下（同一帧的模拟鼠标键 / 触点）不算点目标
	if _cancel_r.has_area() and _cancel_r.grow(6.0).has_point(p):
		cancel()
		return true
	if mode == "focus" and _near_r.has_area() and _near_r.grow(6.0).has_point(p):
		var cs: Array = _cands()
		if not cs.is_empty():
			_tap_focus(cs[0])
		return true
	if g.touch != null:
		for b in g.touch.btn_rects:
			if (b[0] as Rect2).has_point(p):
				if str(b[1]) == "cmd":   # 再点「指挥」键 = 退出选点
					cancel()
					return true
				return false   # 冲刺 / 技能 / 暂停等照常
	var ct: Transform2D = g.hud_ct()
	if mode == "focus":
		var e = _cand_at(p)
		if e == null:
			cancel()   # 点空白 = 取消；正好在摇杆区时这一下同时起摇杆
			return not g.touch.wants_stick(p) if g.touch != null else true
		_tap_focus(e)
		return true
	var w: Vector2 = ct.affine_inverse() * p
	if w.distance_to(g.ppos) > Bal.v("command/order_r", 560.0):
		_miss_t = 0.0
		Sfx.play("ui_move", -10.0)
		return true
	if pre_set and (ct * pre_pt).distance_to(p) <= TAP_SAME:
		_refresh()
		confirm()
		return true
	pre_set = true
	pre_pt = w
	_pre_t = 0.0
	_miss_t = -1.0
	Sfx.play("ui_move", -6.0)
	_refresh()
	return true


func _tap_focus(e) -> void:
	if pre_set and is_same(e, pre_target):
		_refresh()
		confirm()
		return
	pre_set = true
	pre_target = e
	_pre_t = 0.0
	Sfx.play("ui_move", -6.0)
	_refresh()


## 点在哪只可选目标上：框内，或离框心 72 像素内（屏外的看边缘标签）；多只取最近
func _cand_at(p: Vector2) -> Variant:
	var ct: Transform2D = g.hud_ct()
	var vs: Vector2 = g.hud.size
	var best = null
	var bd := INF
	for e in _cands():
		var sp: Vector2 = ct * e.pos + Vector2(0, -float(e.r) * 0.5)
		var rr: float = (float(e.r) * 1.25 + 8.0) * ct.get_scale().x
		if not Rect2(Vector2(20, 20), vs - Vector2(40, 40)).has_point(ct * e.pos):
			sp = _edge(ct * e.pos, vs)
			rr = 26.0
		var d: float = sp.distance_to(p)
		if d <= maxf(rr + 12.0, 72.0) and d < bd:
			bd = d
			best = e
	return best


# ---------------------------------------------------------------- 绘制（PRTS 风：作战终端的范围格 / 取景角标 / 警戒斜纹，配色跟圆盘 command/wheel_style）
const CELL := 48.0   # 范围格边长（世界像素，和地图格同量级，只为「格子感」）


func draw(vs: Vector2) -> void:
	if not proto_on():
		return
	g.wheel._apply_style()
	var hud: CanvasItem = g.hud
	var font: Font = g.font
	var ct: Transform2D = g.hud_ct()
	var sq = g.squad
	var W = g.wheel
	if sq.order_kind != "" and not active:
		_draw_order(hud, ct)
	if not active:
		_draw_boss_marks(hud, ct)
	if _done_t >= 0.0 and not active and _done_ok:
		var a: float = 1.0 - _done_t / 0.6
		var sp: Vector2 = ct * _done_pt
		_corners(hud, sp, 30.0 + 80.0 * (1.0 - a), Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, a * 0.9), 2.0)
	_caption(hud, font, vs)
	if not active:
		return
	var e: float = clampf(t / 0.1, 0.0, 1.0)
	hud.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.012, 0.016, 0.26 * e))
	var lp: Vector2 = ct * g.ppos
	var R: float = Bal.v("command/order_r", 560.0)
	var Rs: float = ct.basis_xform(Vector2(R, 0)).length()
	_range_ring(hud, font, lp, Rs, e, int(R))
	if tap:
		_draw_tap(hud, font, ct, vs, e)
		return
	# 屏外的精英 / Boss：边缘小标签（方框 + 方向箭头，PRTS 的目标条）
	for en in _cands():
		var sp2: Vector2 = ct * en.pos
		var inside: bool = Rect2(Vector2(20, 20), vs - Vector2(40, 40)).has_point(sp2)
		var col: Color = W.C_WARN if en.boss else W.C_ACC
		var picked: bool = is_same(en, snapped)
		if inside:
			if mode == "focus":
				_lock(hud, font, ct, en, col, picked, e)
		elif mode == "focus":
			var cp: Vector2 = _edge(sp2, vs)
			var rc := Rect2(cp - Vector2(24, 12), Vector2(48, 24))
			hud.draw_rect(rc, Color(0.03, 0.03, 0.035, 0.92))
			hud.draw_rect(rc, Color(col.r, col.g, col.b, 1.0 if picked else 0.7), false, 3.0 if picked else 1.5)
			UI.ctext(hud, font, cp + Vector2(-24, 4), "BOSS" if en.boss else "ELITE", 10, col, HORIZONTAL_ALIGNMENT_CENTER, 48)
			var dv: Vector2 = (sp2 - cp).normalized()
			hud.draw_colored_polygon(PackedVector2Array([cp + dv * 24.0, cp + dv * 14.0 + dv.orthogonal() * 6.0, cp + dv * 14.0 - dv.orthogonal() * 6.0]), col)
	# 肃清：范围格（以点为心、半径 clear_r 内的格子，向外渐淡，最外一圈亮边）；移动：只画一个小标记（驻扎点，10-30 用户「变成一个小点」）；
	# 无效（超出范围）整体变警示色
	if mode != "focus":
		var col2: Color = W.C_ACC if valid else W.C_WARN
		var rr: float = Bal.v("command/clear_r", 220.0) if mode == "clear" else 24.0
		var cp2: Vector2 = ct * world_pt
		if mode == "clear":
			_tiles(hud, ct, world_pt, rr, col2, e)
		else:
			_station_mark(hud, cp2, Color(col2.r, col2.g, col2.b, e))
		for o in g.squad.ops:
			if o.is_leader or not o.cmd_roam() or o.pos == Vector2.INF:
				continue
			_dash(hud, ct * o.pos, cp2, Color(col2.r, col2.g, col2.b, 0.4 * e), true)
		var gx: int = int(floor(world_pt.x / CELL))
		var gy: int = int(floor(world_pt.y / CELL))
		var ro: String = "OK" if valid else "OUT OF RANGE"
		_tag(hud, font, cp2 + Vector2(ct.basis_xform(Vector2(rr, 0)).length() * 0.7 + 8.0, -ct.basis_xform(Vector2(rr, 0)).length() * 0.7 - 6.0), "PT %03d/%03d" % [absi(gx) % 1000, absi(gy) % 1000], ro, col2)
	# 准星：取景角标 + 十字 + 中心点；手机再画手指圈 + 连线
	var rp: Vector2 = reticle
	var rc2: Color = W.C_ACC if valid else W.C_WARN
	_corners(hud, rp, 20.0, rc2, 2.0)
	hud.draw_line(rp + Vector2(-34, 0), rp + Vector2(-9, 0), rc2, 1.5)
	hud.draw_line(rp + Vector2(9, 0), rp + Vector2(34, 0), rc2, 1.5)
	hud.draw_line(rp + Vector2(0, -34), rp + Vector2(0, -9), rc2, 1.5)
	hud.draw_line(rp + Vector2(0, 9), rp + Vector2(0, 34), rc2, 1.5)
	hud.draw_rect(Rect2(rp - Vector2(2, 2), Vector2(4, 4)), rc2)
	if kind == "touch":
		hud.draw_circle(pointer, 30.0, Color(1, 1, 1, 0.12))
		hud.draw_arc(pointer, 30.0, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 2.0)
		_dash(hud, pointer + Vector2(0, -30), rp + Vector2(0, 22), Color(1, 1, 1, 0.45), false)
	# 底部信息板：左端警戒斜纹 + PRTS 标签 + 类型 / 状态 / 提示（切角板）
	var v2: bool = Tactics.on()
	var title: String = {"point": "指挥 · 部署" if v2 else "指点 · 移动", "clear": "指点 · 肃清"}.get(mode, "指点 · 集火")
	var code: String = {"point": "ORDER // DEPLOY" if v2 else "ORDER // POINT", "clear": "ORDER // CLEAR"}.get(mode, "ORDER // FOCUS FIRE")
	var stt: String
	if mode == "focus":
		stt = ("锁定 %s" % ("Boss" if snapped.boss else "精英")) if snapped != null else "把准星移到精英或 Boss 上"
	else:
		stt = ("队友前往此处落位，重装 / 近卫阻挡敌人" if v2 and mode == "point" else "全队前往此处作战") if valid else "太远了"
	var w: float = minf(vs.x - 40.0, 440.0)
	var r := Rect2(Vector2((vs.x - w) / 2.0, vs.y * 0.76), Vector2(w, 76))
	_plate(hud, r, e)
	UI.ctext(hud, font, r.position + Vector2(34, 14), "PRTS // " + code, 9, Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.6 * e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	UI.text(hud, font, r.position + Vector2(34, 35), title, 17, Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	UI.text(hud, font, r.position + Vector2(34, 53), stt, 13, Color(1, 1, 1, e) if valid else Color(W.C_WARN.r, W.C_WARN.g, W.C_WARN.b, e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	var tip: String = ("松手确认 · 拖回圆盘处取消" if kind == "touch" else "左键确认 · 右键 / Esc 取消")
	UI.text(hud, font, r.position + Vector2(34, 69), tip + "  ·  选点每秒 −3% 作战时限", 11, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	if kind == "touch" and mode == "focus":
		var b := Rect2(Vector2(vs.x / 2.0 - 120, r.end.y + 8), Vector2(240, 34))
		_plate(hud, b, e)
		UI.text(hud, font, b.position + Vector2(30, 22), "最近的 Boss / 精英", 14, W.C_WARN, HORIZONTAL_ALIGNMENT_LEFT, 200)


## 触屏点选确认的画面（docs/315）：可选目标常亮 PRTS 白（深色衬底 + 亮角标，1 倍下也读得出）→ 预选变金色、弹一下（11-07 用户：不要「再点一次确认」浮字）；
## 部署落点预选同色；信息板写当前一步该做什么，右侧「最近目标」（集火）/「取消」两个键，底边细条是剩余选点时间
func _draw_tap(hud: CanvasItem, font: Font, ct: Transform2D, vs: Vector2, e: float) -> void:
	var W = g.wheel
	var cs: Array = _cands() if mode == "focus" else []
	var pop: float = 1.0 + 0.22 * (1.0 - clampf(_pre_t / 0.18, 0.0, 1.0)) if not Cfg.reduce_motion else 1.0
	var pu: float = 0.0 if Cfg.reduce_motion else 0.5 + 0.5 * sin(t * 7.0)
	for en in cs:
		var col: Color = CAND_COL   # 可选目标一律 PRTS 白，选中才变金（11-07 用户）
		var pre: bool = pre_set and is_same(en, pre_target)
		var spw: Vector2 = ct * en.pos
		if Rect2(Vector2(20, 20), vs - Vector2(40, 40)).has_point(spw):
			var sp: Vector2 = spw + Vector2(0, -float(en.r) * 0.5)
			var r: float = (float(en.r) * 1.25 + 8.0) * ct.get_scale().x
			if pre:
				r *= pop
				hud.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, 0.14 * e))
				hud.draw_rect(Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, 0.55 * e), false, 1.0)
				_corners(hud, sp, r, Color(0, 0, 0, 0.7 * e), 6.5)
				_corners(hud, sp, r, Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, e), 3.5)
			else:
				_corners(hud, sp, r, Color(0, 0, 0, 0.6 * e), 5.0)
				_corners(hud, sp, r, Color(col.r, col.g, col.b, (0.75 + 0.25 * pu) * e), 2.6)
				UI.ctext(hud, font, sp + Vector2(-r, -r - 7.0), "BOSS" if en.boss else "ELITE", 11, Color(col.r, col.g, col.b, 0.9 * e), HORIZONTAL_ALIGNMENT_LEFT, 80)
			var hp: float = clampf(float(en.hp) / maxf(1.0, float(en.maxhp)), 0.0, 1.0)
			hud.draw_rect(Rect2(sp + Vector2(-r, r + 6.0), Vector2(r * 2.0, 4)), Color(0, 0, 0, 0.7 * e))
			hud.draw_rect(Rect2(sp + Vector2(-r, r + 6.0), Vector2(r * 2.0 * hp, 4)), Color(PRE_COL if pre else col, 0.95 * e))
		else:
			var cp: Vector2 = _edge(spw, vs)
			var cc: Color = PRE_COL if pre else col
			var rc := Rect2(cp - Vector2(28, 14), Vector2(56, 28))
			hud.draw_rect(rc, Color(0.03, 0.03, 0.035, 0.92))
			hud.draw_rect(rc, cc, false, 3.0 if pre else 1.8)
			UI.ctext(hud, font, cp + Vector2(-28, 5), "BOSS" if en.boss else "ELITE", 11, cc, HORIZONTAL_ALIGNMENT_CENTER, 56)
			var dv: Vector2 = (spw - cp).normalized()
			hud.draw_colored_polygon(PackedVector2Array([cp + dv * 28.0, cp + dv * 17.0 + dv.orthogonal() * 7.0, cp + dv * 17.0 - dv.orthogonal() * 7.0]), cc)
	if mode != "focus" and pre_set:
		var cp2: Vector2 = ct * pre_pt
		var pc := Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, e)
		for o in g.squad.ops:
			if o.is_leader or not o.cmd_roam() or o.pos == Vector2.INF:
				continue
			_dash(hud, ct * o.pos, cp2, Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, 0.45 * e), true)
		var rr: float = TAP_SAME * 0.55 * pop
		hud.draw_circle(cp2, rr, Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, 0.12 * e))
		hud.draw_arc(cp2, rr, 0.0, TAU, 40, Color(0, 0, 0, 0.6 * e), 4.0)
		hud.draw_arc(cp2, rr, 0.0, TAU, 40, Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, (0.7 + 0.3 * pu) * e), 2.0)
		_station_mark(hud, cp2, pc)
	# 信息板
	var ph: bool = Cfg.phone_ui()
	var v2: bool = Tactics.on()
	var title: String = {"point": "指挥 · 部署" if v2 else "指点 · 移动", "clear": "指点 · 肃清"}.get(mode, "指挥 · 集火")
	var code: String = {"point": "ORDER // DEPLOY" if v2 else "ORDER // POINT", "clear": "ORDER // CLEAR"}.get(mode, "ORDER // FOCUS FIRE")
	var stt: String
	var warn := false
	if mode == "focus":
		if pre_set:
			stt = "已选中%s · 再点一次下令，点其他目标可改选" % ("Boss" if pre_target.boss else "精英")
		elif cs.is_empty():
			stt = "附近没有精英或 Boss"
			warn = true
		else:
			stt = "点场上的精英或 Boss 选中目标"
	elif _miss_t >= 0.0:
		stt = "超出指挥范围，请点虚线圈内"
		warn = true
	elif pre_set:
		stt = "落点已选 · 再点一次标记下令，点别处可改"
	else:
		stt = "点虚线圈内的地面选落点"
	var tip: String = ("点空白处或「取消」退出" if mode == "focus" else "点「取消」或「指挥」键退出") + " · 选点每秒 −3% 作战时限"
	var w: float = minf(vs.x - 40.0, 600.0 if ph else 560.0)
	var h: float = 96.0 if ph else 88.0
	var r := Rect2(Vector2(round((vs.x - w) / 2.0), round(vs.y * (0.72 if ph else 0.75))), Vector2(w, h))
	_plate(hud, r, e)
	var bw: float = 84.0
	var bh: float = 44.0 if ph else 40.0
	_cancel_r = Rect2(Vector2(r.end.x - bw - 14.0, r.position.y + (h - bh) / 2.0), Vector2(bw, bh))
	_near_r = Rect2(Vector2(_cancel_r.position.x - 112.0 - 10.0, _cancel_r.position.y), Vector2(112.0, bh)) if (mode == "focus" and not cs.is_empty()) else Rect2()
	var tw: float = (_near_r.position.x if _near_r.has_area() else _cancel_r.position.x) - r.position.x - 44.0
	UI.ctext(hud, font, r.position + Vector2(34, 16), "PRTS // " + code, 9, Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.6 * e), HORIZONTAL_ALIGNMENT_LEFT, tw)
	UI.text(hud, font, r.position + Vector2(34, 39), title, 19 if ph else 17, Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, e), HORIZONTAL_ALIGNMENT_LEFT, tw)
	var sc: Color = Color(W.C_WARN.r, W.C_WARN.g, W.C_WARN.b, e) if warn else (Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, e) if pre_set else Color(1, 1, 1, e))
	var sf: Dictionary = UI.fit(font, stt, tw, 20.0, [16 if ph else 14, 15 if ph else 13, 13 if ph else 12])
	UI.draw_fit(hud, font, r.position + Vector2(34, 46), sf, sc)
	var tf: Dictionary = UI.fit(font, tip, tw, 16.0, [13 if ph else 11, 12 if ph else 10, 11 if ph else 10])
	UI.draw_fit(hud, font, r.position + Vector2(34, h - 24.0), tf, Color(UI.SUB.r, UI.SUB.g, UI.SUB.b, e))
	_small_btn(hud, font, _cancel_r, "取消", W.C_DIAL, e)
	if _near_r.has_area():
		_small_btn(hud, font, _near_r, "最近目标", W.C_WARN, e)
	# 剩余选点时间（底边细条）
	var left: float = clampf(1.0 - t / maxf(0.1, Bal.v("command/pick_cap_touch", 6.0)), 0.0, 1.0)
	hud.draw_rect(Rect2(Vector2(r.position.x + 16.0, r.end.y - 3.0), Vector2((w - 16.0) * left, 3.0)), Color(PRE_COL.r, PRE_COL.g, PRE_COL.b, 0.8 * e) if pre_set else Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, 0.7 * e))


func _small_btn(hud: CanvasItem, font: Font, r: Rect2, s: String, col: Color, e: float) -> void:
	hud.draw_rect(r, Color(0.04, 0.06, 0.08, 0.9 * e))
	hud.draw_rect(r, Color(col.r, col.g, col.b, 0.85 * e), false, 1.5)
	UI.text(hud, font, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.5), s, 16 if Cfg.phone_ui() else 15, Color(1, 1, 1, e), HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## 信息板：碳黑底 + 左端警戒斜纹 + 切角（右上）+ 细白底线
func _plate(hud: CanvasItem, r: Rect2, e: float) -> void:
	var W = g.wheel
	var cut := 12.0
	hud.draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x - cut, 0), r.position + Vector2(r.size.x, cut), r.end, r.position + Vector2(0, r.size.y)]), Color(W.C_PLATE.r, W.C_PLATE.g, W.C_PLATE.b, 0.94 * e))
	W.hazard(hud, Rect2(r.position, Vector2(16, r.size.y)), e)
	hud.draw_line(Vector2(r.position.x, r.end.y), r.end, Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.3 * e), 1.0)


## 范围格：以 center 为心、半径 rr 内的世界格（CELL 对齐），内填淡色 + 细边，越靠外越淡，最外一圈格加亮边
func _tiles(hud: CanvasItem, ct: Transform2D, center: Vector2, rr: float, col: Color, e: float) -> void:
	var n: int = int(ceil(rr / CELL))
	var base := Vector2(floor(center.x / CELL), floor(center.y / CELL))
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var cc := (base + Vector2(ix, iy) + Vector2(0.5, 0.5)) * CELL
			var d: float = cc.distance_to(center)
			if d > rr:
				continue
			var k: float = 1.0 - d / rr
			var edge: bool = d > rr - CELL * 0.9
			var q0: Vector2 = ct * (cc - Vector2(CELL, CELL) * 0.46)
			var q1: Vector2 = ct * (cc + Vector2(CELL, CELL) * 0.46)
			var rc := Rect2(q0, q1 - q0)
			hud.draw_rect(rc, Color(col.r, col.g, col.b, (0.05 + 0.13 * k) * e))
			hud.draw_rect(rc, Color(col.r, col.g, col.b, (0.75 if edge else 0.22) * e), false, 1.2 if edge else 1.0)


## 范围虚线圈：刻度（每 30°）+ 标注「RANGE 数值」
func _range_ring(hud: CanvasItem, font: Font, c: Vector2, rs: float, e: float, r: int) -> void:
	var W = g.wheel
	var col := Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.4 * e)
	for i in 72:
		var a0: float = TAU * float(i) / 72.0
		hud.draw_arc(c, rs, a0, a0 + TAU / 144.0, 3, col, 1.5)
	for i in 12:
		var v := Vector2.from_angle(TAU * float(i) / 12.0)
		hud.draw_line(c + v * (rs - 7.0), c + v * (rs + 7.0), Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.6 * e), 1.5)
	UI.ctext(hud, font, c + Vector2(rs * 0.7071 + 10.0, -rs * 0.7071 - 4.0), "RANGE %d" % r, 9, Color(W.C_DIAL.r, W.C_DIAL.g, W.C_DIAL.b, 0.7 * e), HORIZONTAL_ALIGNMENT_LEFT, 120)


## 取景角标（四个 L）
func _corners(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	var l: float = r * 0.5
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx * r, sy * r) + c
			ci.draw_line(corner, corner + Vector2(-sx * l, 0), col, w)
			ci.draw_line(corner, corner + Vector2(0, -sy * l), col, w)


## 小标签：两行（标题 + 状态），碳黑底、左端 3 像素色条
func _tag(hud: CanvasItem, font: Font, p: Vector2, a: String, b: String, col: Color) -> void:
	var W = g.wheel
	var rc := Rect2(p, Vector2(112, 30))
	hud.draw_rect(rc, Color(W.C_PLATE.r, W.C_PLATE.g, W.C_PLATE.b, 0.9))
	hud.draw_rect(Rect2(p, Vector2(3, 30)), col)
	UI.ctext(hud, font, p + Vector2(9, 12), a, 10, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_LEFT, 100)
	UI.ctext(hud, font, p + Vector2(9, 25), b, 9, col, HORIZONTAL_ALIGNMENT_LEFT, 100)


## 集火目标：取景角标 + 血条 + 锁定状态（选中时加粗、带「LOCK」）
func _lock(hud: CanvasItem, font: Font, ct: Transform2D, en: Dictionary, col: Color, picked: bool, e: float) -> void:
	var sp: Vector2 = ct * en.pos + Vector2(0, -float(en.r) * 0.5)
	var r: float = (float(en.r) * 1.25 + 8.0) * ct.get_scale().x
	_corners(hud, sp, r, Color(col.r, col.g, col.b, 0.95 if picked else 0.55), 3.0 if picked else 1.6)
	var hp: float = clampf(float(en.hp) / maxf(1.0, float(en.maxhp)), 0.0, 1.0)
	var bw: float = r * 2.0
	hud.draw_rect(Rect2(sp + Vector2(-r, r + 6.0), Vector2(bw, 4)), Color(0, 0, 0, 0.7 * e))
	hud.draw_rect(Rect2(sp + Vector2(-r, r + 6.0), Vector2(bw * hp, 4)), Color(col.r, col.g, col.b, 0.95 * e))
	if picked:
		UI.ctext(hud, font, sp + Vector2(-r, -r - 8.0), "LOCK // " + ("BOSS" if en.boss else "ELITE"), 10, col, HORIZONTAL_ALIGNMENT_LEFT, 120)


## 中期 Boss 常驻锁定框（docs/283 §6 第 1 条，11-06 用户「中期 Boss 不明显」）：集火时才有的取景角标 + 「BOSS」小字，改成中期 Boss
## 在画面里就一直画，亮度低于集火锁定；正被集火的那只由 _draw_order 画（不重复）。只画，不改判定。
## render/boss_mark：1 = 开（缺省），0 = 关。框按 world.mid_boss_k 跟着放大后的身体走
func _draw_boss_marks(hud: CanvasItem, ct: Transform2D) -> void:
	if Bal.v("render/boss_mark", 1.0) <= 0.0 or g.state != g.S.PLAY:
		return
	var W = g.wheel
	var tgt = g.squad.order_target if g.squad.order_kind == "focus" else null
	for b in g.bosses:
		if b.dead or b.get("friendly", false) or b.get("part", false) or is_same(b, tgt):
			continue
		if not g.world.is_mid_boss(b):
			continue
		var k: float = g.world.mid_boss_k(b)
		var r0: float = float(b.r) * k
		var sp: Vector2 = ct * (b.pos + Vector2(0, -r0 * 0.6))
		var r: float = (r0 * 1.1 + 8.0) * ct.get_scale().x
		var pu: float = 0.0 if Cfg.reduce_motion else 0.5 + 0.5 * sin(g.t * 3.0)
		var col := Color(W.C_WARN.r, W.C_WARN.g, W.C_WARN.b, 0.8 + 0.2 * pu)
		# 深色衬底再画亮色角（特效堆里也读得出来）
		_corners(hud, sp, r, Color(0, 0, 0, 0.6), 4.5)
		_corners(hud, sp, r, col, 2.4)
		var tl: Vector2 = sp + Vector2(-r, -r - 17.0)
		hud.draw_rect(Rect2(tl, Vector2(38, 14)), Color(W.C_PLATE.r, W.C_PLATE.g, W.C_PLATE.b, 0.85))
		hud.draw_rect(Rect2(tl, Vector2(2, 14)), col)
		UI.ctext(hud, g.font, tl + Vector2(5, 11), "BOSS", 11, col, HORIZONTAL_ALIGNMENT_LEFT, 60)


## 录片说明字幕（--democap 才画，只在示意录像里用）：按当前状态自动换——圆盘开着 / 选点中 / 指令生效中
var _cap_on := -1

func _caption(hud: CanvasItem, font: Font, vs: Vector2) -> void:
	if _cap_on < 0:
		_cap_on = 1 if Cfg.dev_args().has("--democap") else 0
	if _cap_on == 0:
		return
	var W = g.wheel
	var touch: bool = g.touch != null and g.touch.active
	var dev: String = "手机 · 触屏" if touch else "电脑 · 鼠标"
	var line := ""
	if g.wheel.is_open:
		line = "① 点「指挥」键弹出圆盘，局内放慢 → 选「移动」（去那里）、「肃清」（清一块区域）或「集火」（打这个）"
	elif active:
		if touch and tap:
			line = "② 点精英 / Boss 选中（框变金色），再点一次下令；点别的目标改选，点空白取消" if mode == "focus" else "② 点地面选落点（标记变金色），再点一次标记下令；点别处改选，点「取消」退出"
		elif touch:
			line = "② 手指不抬起，拖到目标：准星在手指上方；松手确认，拖回圆盘处取消" if mode != "focus" else "② 拖向精英 / Boss（屏外的看边缘标签），或点下方「最近的 Boss / 精英」；松手确认"
		else:
			line = "② 准星跟着鼠标：点地面（超出虚线圈算太远）· 左键确认 · 右键 / Esc 取消" if mode != "focus" else "② 把准星移到精英 / Boss 上（屏外的看边缘标签），左键确认 · 右键 / Esc 取消"
	elif g.squad.order_kind == "point":
		line = "③ 队友走到标记点驻扎，自动攻击射程内的敌人；下别的指令才离开；作战时限照扣"
	elif g.squad.order_kind == "clear":
		line = "③ 队友前往肃清圈、清掉圈内敌人；清空或 9 秒后回到随行；作战时限照扣"
	elif g.squad.order_kind == "focus":
		line = "③ 全队集火标记的目标；目标死了指令结束，作战时限照扣"
	if line == "":
		return
	var w: float = minf(vs.x - 40.0, 900.0)
	var r := Rect2(Vector2((vs.x - w) / 2.0, vs.y * 0.115), Vector2(w, 52))
	_plate(hud, r, 1.0)
	var sn: String = ["终末地蓝", "PRTS·警戒", "PRTS·终端"][clampi(W.style, 0, 2)]
	UI.ctext(hud, font, r.position + Vector2(34, 16), "PRTS // 示意原型 · " + dev + " · 配色 " + sn, 9, Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b), HORIZONTAL_ALIGNMENT_LEFT, w - 40)
	UI.text(hud, font, r.position + Vector2(34, 38), line, 14, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_LEFT, w - 40)


func _draw_order(hud: CanvasItem, ct: Transform2D) -> void:
	var sq = g.squad
	var W = g.wheel
	if sq.order_kind != "clear":
		_clear_at = Vector2.INF
	if sq.order_kind == "clear":
		var cp: Vector2 = ct * sq.order_pos
		# 11-01 巡检 D5：整片格子常驻会一直铺在怪群上、和特效叠成一片。下令 / 目标区挪动后整片亮 1.5 秒，
		# 0.3 秒淡掉，之后只留外圈一层格（约三成亮度）+ 中心角标
		if _clear_at == Vector2.INF or _clear_at.distance_to(sq.order_pos) > CELL * 2.0:
			_clear_at = sq.order_pos
			_clear_ms = Time.get_ticks_msec()
		var age: float = (Time.get_ticks_msec() - _clear_ms) / 1000.0
		var fade: float = clampf((age - 1.5) / 0.3, 0.0, 1.0)
		if fade < 1.0:
			_tiles(hud, ct, sq.order_pos, sq.order_radius(), W.C_ACC, 0.8 * (1.0 - fade))
		if fade > 0.0:
			_edge_tiles(hud, ct, sq.order_pos, sq.order_radius(), W.C_ACC, 0.4 * fade)
		_corners(hud, cp, 14.0, Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, 0.95 - 0.35 * fade), 2.0)
	elif sq.order_kind == "point":
		_station_mark(hud, ct * sq.order_pos, Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, 0.9))
		if Tactics.on():
			_draw_deploy(hud, ct)
	elif sq.order_kind == "focus" and sq.order_target != null and not sq.order_target.dead:
		var en = sq.order_target
		_lock(hud, g.font, ct, en, W.C_WARN, true, 1.0)
		for o in sq.ops:
			if o.is_leader or not o.cmd_roam() or o.pos == Vector2.INF:
				continue
			_dash(hud, ct * o.pos, ct * en.pos, Color(W.C_WARN.r, W.C_WARN.g, W.C_WARN.b, 0.4), true)


## 部署（指挥 v2，docs/209 §1.4）：站定的远程干员地面画攻击范围的边格（同范围格画法，只画外圈一层，不糊敌人）；
## 阻挡者脚下一排小方块 = 阻挡数，挡住几个亮几个（精英占 2）
func _draw_deploy(hud: CanvasItem, ct: Transform2D) -> void:
	var W = g.wheel
	var sq = g.squad
	for o in sq.ops:
		if o.is_leader or o.pos == Vector2.INF or not sq.roaming_op(o):
			continue
		var st: Vector2 = sq.station_of(o)
		if st == Vector2.INF or o.pos.distance_to(st) > Bal.v("command/block_at", 40.0):
			continue
		if Tactics.role(o) == "ranged":
			_edge_tiles(hud, ct, o.pos, o.cmd_attack_range(), W.C_ACC, 0.55)
		var cap: int = Tactics.block_cap(o)
		if cap <= 0:
			continue
		var used := 0
		for e in o.cmd_blk:
			used += 2 if e.elite else 1
		var fp: Vector2 = ct * (o.pos + Vector2(0, 12))
		var w: float = cap * 9.0 - 3.0
		for i in cap:
			var r := Rect2(fp + Vector2(-w * 0.5 + i * 9.0, 0), Vector2(6, 6))
			hud.draw_rect(r.grow(1.0), Color(0.02, 0.03, 0.04, 0.8))
			hud.draw_rect(r, W.C_WARN if i < used else Color(W.C_ACC.r, W.C_ACC.g, W.C_ACC.b, 0.35))


## 范围的外圈格（只画边上一层）：远程部署的射程
func _edge_tiles(hud: CanvasItem, ct: Transform2D, center: Vector2, rr: float, col: Color, e: float) -> void:
	var n: int = int(ceil(rr / CELL))
	var base := Vector2(floor(center.x / CELL), floor(center.y / CELL))
	for iy in range(-n, n + 1):
		for ix in range(-n, n + 1):
			var cc := (base + Vector2(ix, iy) + Vector2(0.5, 0.5)) * CELL
			var d: float = cc.distance_to(center)
			if d > rr or d < rr - CELL * 0.9:
				continue
			var q0: Vector2 = ct * (cc - Vector2(CELL, CELL) * 0.46)
			var q1: Vector2 = ct * (cc + Vector2(CELL, CELL) * 0.46)
			var rc := Rect2(q0, q1 - q0)
			hud.draw_rect(rc, Color(col.r, col.g, col.b, 0.08 * e))
			hud.draw_rect(rc, Color(col.r, col.g, col.b, 0.6 * e), false, 1.2)


## 驻扎点标记（移动）：深色描边的小菱形 + 四角刻度，屏幕像素约 28 见方，不画范围；画在地面层，被干员挡住时角标仍露在外面
func _station_mark(ci: CanvasItem, c: Vector2, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -10), c + Vector2(10, 0), c + Vector2(0, 10), c + Vector2(-10, 0)]), Color(0.02, 0.03, 0.04, 0.75 * col.a))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)]), col)
	_corners(ci, c, 14.0, Color(0.02, 0.03, 0.04, 0.6 * col.a), 3.5)
	_corners(ci, c, 14.0, col, 2.0)


func _dash(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, arrow: bool) -> void:
	var d: Vector2 = b - a
	var n: int = int(d.length() / 14.0)
	for i in range(0, n, 2):
		ci.draw_line(a + d * (float(i) / n), a + d * (float(i + 1) / n), col, 1.5)
	if arrow and d.length() > 40.0:
		var u: Vector2 = d.normalized()
		var m: Vector2 = a + d * 0.5
		ci.draw_colored_polygon(PackedVector2Array([m + u * 7.0, m - u * 4.0 + u.orthogonal() * 5.0, m - u * 4.0 - u.orthogonal() * 5.0]), col)


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
			"tap":   # 触屏点选确认：在 UI 坐标 x:y 点一下（docs/315）
				tap_at(Vector2(float(s[2]), float(s[3])))
			"tapf":
				var vs4: Vector2 = g.hud.size
				tap_at(Vector2(float(s[2]) / 1000.0 * vs4.x, float(s[3]) / 1000.0 * vs4.y))
			"tapsnap":   # 点离队长第 i 近的精英 / Boss（屏外的点边缘标签）
				var cs4: Array = _cands()
				if not cs4.is_empty():
					var en4 = cs4[mini(int(s[2]) if s.size() > 2 else 0, cs4.size() - 1)]
					var ct4: Transform2D = g.hud_ct()
					var vs5: Vector2 = g.hud.size
					var sp4: Vector2 = ct4 * en4.pos + Vector2(0, -float(en4.r) * 0.5)
					if not Rect2(Vector2(20, 20), vs5 - Vector2(40, 40)).has_point(ct4 * en4.pos):
						sp4 = _edge(ct4 * en4.pos, vs5)
					tap_at(sp4)
			"tappre":   # 再点一次当前预选（集火 = 预选目标，部署 = 预选落点）→ 下令
				if pre_set:
					var ct6: Transform2D = g.hud_ct()
					var vs6: Vector2 = g.hud.size
					var sp6: Vector2 = ct6 * pre_pt
					if pre_target != null:
						sp6 = ct6 * pre_target.pos + Vector2(0, -float(pre_target.r) * 0.5)
						if not Rect2(Vector2(20, 20), vs6 - Vector2(40, 40)).has_point(ct6 * pre_target.pos):
							sp6 = _edge(ct6 * pre_target.pos, vs6)
					tap_at(sp6)
			"tapdeploy":   # 点队长前方 fx 世界像素处的地面（部署预选 / 再点确认，录片用）
				var ct5: Transform2D = g.hud_ct()
				tap_at(ct5 * (g.ppos + Vector2(float(s[2]) if s.size() > 2 else 220.0, float(s[3]) if s.size() > 3 else -60.0)))
			"ok":
				_refresh()
				confirm()
			"cancel":
				cancel()
