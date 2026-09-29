## 博士（docs/23 §3）：场上唯一的受击体。生命 / 位置 / 移动 / 拾取 / 灯火 / 等级这些通用状态仍由 game.gd 持有（ppos / hp / …），
## 本文件放博士层的专属逻辑：指挥技能（唯一的手动技能）、排异反应、局外成长接入。
extends RefCounted

var g
var def: Dictionary = {}
var rej_count := 0             # 排异反应次数（结局线用）
var rej_log: Array = []        # 每次排异的说明文字

## 博士被动（cat doctor）与全队被动（cat squad），docs/23 §6：各自最多选 4 种，选满后只出已有种类
const PASSIVES := {
	"hp": {"name": "坚韧", "desc": "主控最大生命 +20", "max": 99, "cat": "doctor"},
	"regen": {"name": "自愈", "desc": "主控每秒回复生命 +0.6", "max": 5, "cat": "doctor"},
	"armor": {"name": "硬化", "desc": "主控物理减伤 +2（对法术、真实伤害无效）", "max": 4, "cat": "doctor"},
	"dodge": {"name": "水影", "desc": "主控闪避率 +5%", "max": 4, "cat": "doctor"},
	"speed": {"name": "轻盈", "desc": "主控移动速度 +10%", "max": 5, "cat": "doctor"},
	"pickup": {"name": "感知", "desc": "主控拾取范围 +30%", "max": 5, "cat": "doctor"},
	"wick": {"name": "护灯", "desc": "主控受击时灯火损失 -15%", "max": 4, "cat": "doctor"},
	"sp": {"name": "协同·技", "desc": "全队技能充能 +15%", "max": 4, "cat": "squad"},
	"squad_atk": {"name": "协同·攻", "desc": "全队干员攻击 +8%", "max": 5, "cat": "squad"},
	"squad_aspd": {"name": "协同·迅", "desc": "全队干员攻速 +6%", "max": 5, "cat": "squad"},
	"squad_range": {"name": "协同·广", "desc": "全队干员攻击范围 +8%", "max": 4, "cat": "squad"},
	"squad_crit": {"name": "协同·锐", "desc": "全队干员技能强度 +10%", "max": 4, "cat": "squad"},
}
const PASSIVE_CAP := 4         # 每类最多几种


func _init(game) -> void:
	g = game
	var f := FileAccess.open("res://data/doctor.json", FileAccess.READ)
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			def = d


func name() -> String:
	return def.get("name", "博士")


## 唯一的手动技能入口（Q / J，手柄 Ⓐ / Ⓧ，手机技能键）：路由到主控的手动技能（契约 v2.3：手动只对主控生效，队友一律自动）。
## 就绪就放；只是正在出手时先记下、出手完立即放（character.press_manual）；放不了时提示原因并吞掉按键；
## 主控没有已解锁的手动技能返回 false
## dir（契约 v2.4，带方向的手动技能）：Vector2.INF = 读键鼠 / 手柄当前方向（manual_input_dir，Q / J / Ⓐ 走这里）；
## Vector2.ZERO = 自动瞄准；其余 = 指定方向（手机技能键拖动）
## 选落点技能（契约 v2.5，JSON "aim": "point"）：鼠标 / 右摇杆 / 触屏拖动直接给点；键盘（和没推右摇杆的手柄）按下开始蓄距离，
## 松手放（tick_input）；触屏没拖 = 自动瞄准
func try_manual_skill(dir: Vector2 = Vector2.INF) -> bool:
	var from_keys := dir == Vector2.INF
	if dir == Vector2.INF:
		dir = manual_input_dir()
	for o in g.squad.ops:
		var i: int = o.manual_index()
		if i < 0 or not o.skill_unlocked(i):
			continue
		if o.manual_point(i):
			if not charge.is_empty():
				return true
			var pt: Vector2 = point_now(o, i)
			if pt == Vector2.INF and from_keys and not _touching():
				# 键盘：按住蓄距离，松手放。充能已满、只是正在出手（或锚还没收回）也先蓄，松手时 press_manual 会记下、一空出来就放
				if o.sp[i] >= o.sp_need(i) and o.skill_active_left(i) <= 0.0 and not o.perm[i] and o.manual_block_reason(i, Vector2.RIGHT) == "":
					charge = {"i": i, "t": 0.0}
					return true
				pt = charge_point(o, i)   # 放不了：照常提示原因（正在出手时按最短距离记下）
			_press_point(o, i, pt)
			return true
		var why: String = o.press_manual(i, dir)
		if why != "":
			g.vfx.add_text(g.ppos + Vector2(0, -96), "%s %s" % [o.skill_def(i).get("name", ""), why], Color(0.7, 0.75, 0.85), 14)
			Sfx.play("ui_move", -8.0, 0.7)
		return true
	return false


## 键鼠 / 手柄此刻的瞄准方向（用户定 2026-09-26）：手柄右摇杆推着就用右摇杆；否则用当前移动方向（WASD / 左摇杆 / 十字键，
## 和冲刺同一套）；站着不动 = Vector2.ZERO（自动瞄准）。界面画键鼠 / 手柄的瞄准指示也用它
const AIM_STICK := 0.5

func manual_input_dir() -> Vector2:
	for dev in Input.get_connected_joypads():
		var r := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if r.length() >= AIM_STICK:
			return r.normalized()
	if g.move_in != Vector2.ZERO:
		return g.move_in.normalized()
	return Vector2.ZERO


# ---------------------------------------------------------------- 手动普攻与选落点（契约 v2.5，docs/26 §v2.5）

## 设置「普通攻击：手动」（Cfg.manual_attack，玩法系统的设置项）时主控的普攻要按键才出；队友、机器人、图鉴演示一律自动。
## 开发测试：--manualatk 强制打开
const Bal = preload("res://scripts/core/balance.gd")

var manual_attack := false
var atk_buf := 0.0             # 轻点攻击键的缓冲：冷却没转好时先记下，manual/atk_buf 秒内一转好就出（不白按）
var atk_edge := false          # 这一帧刚按下攻击键（凯尔希：按下时给 Mon3tr 换目标）
var _atk_prev := false
var touch_atk := false         # 触屏攻击键按住（touch.gd 写）
var touch_atk_dir := Vector2.ZERO   # 触屏攻击键拖出的方向；ZERO = 不拖，吸附最近目标
var sim_atk := false           # 测试脚本模拟按住攻击键
var _mouse_last := Vector2.INF
var _mouse_t := -99.0          # 最近一次鼠标移动 / 点击的时刻（g.t）
var charge := {}               # 选落点技能键盘蓄距离中：{"i": 技能序号, "t": 已蓄秒数}


## 开局调用：读设置；机器人 / 自动测试 / 图鉴演示不开
func init_manual_attack() -> void:
	var on: bool = ("manual_attack" in Cfg and bool(Cfg.get("manual_attack"))) or Cfg.dev_args().has("--manualatk")
	manual_attack = on and g.bot == null and not g.autotest and g.demo_op == ""


## 每帧（squad.update 开头）：攻击键边沿与缓冲、鼠标活动、键盘蓄距离
var _ma_init := false

func tick_input(dt: float) -> void:
	if not _ma_init:
		_ma_init = true
		init_manual_attack()
	var held := attack_held()
	atk_edge = held and not _atk_prev
	_atk_prev = held
	if atk_edge:
		atk_buf = Bal.v("manual/atk_buf", 0.3)
	else:
		atk_buf = maxf(0.0, atk_buf - dt)
	if not _touching():
		var mp: Vector2 = g.get_viewport().get_mouse_position()
		if mp != _mouse_last or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _mouse_last != Vector2.INF:
				_mouse_t = g.t
			_mouse_last = mp
	if not charge.is_empty():
		charge.t += dt
		# 蓄距离循环音（音频）：每帧 loop_start（已在播只改音高），暂停时 music_director 停掉、回来自动续上
		Sfx.loop_start("ulp_charge_loop", Sfx.ULP_LOOP_DB, 0.8 + 0.8 * clampf(charge.t / Bal.v("manual/point_charge", 0.6), 0.0, 1.0))
		if not _skill_key_held():
			var i: int = charge.i
			Sfx.loop_stop("ulp_charge_loop")
			var ld = g.squad.leader()
			var pt: Vector2 = charge_point(ld, i) if ld != null else Vector2.INF   # 先按蓄到的时长算落点，再清蓄力（清完再算恒为最短 150）
			charge = {}
			if ld != null and ld.manual_index() == i:
				_press_point(ld, i, pt)


## 攻击键此刻是否按着：键鼠左键 / J，手柄 RT / Ⓧ，触屏攻击键
func attack_held() -> bool:
	if not manual_attack:
		return false
	if sim_atk or touch_atk:
		return true
	if _touching():
		return false   # 触屏会模拟鼠标左键，不能当攻击
	if (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _over_hud_btn()) or Input.is_key_pressed(KEY_J):
		return true
	for dev in Input.get_connected_joypads():
		if Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.5 or Input.is_joy_button_pressed(dev, JOY_BUTTON_X):
			return true
	return false


## 主控这一帧要不要普攻（按着，或刚轻点过还在缓冲里）
func attack_want() -> bool:
	return manual_attack and (atk_buf > 0.0 or attack_held())


## 键鼠此刻用鼠标瞄准：最近 manual/mouse_idle 秒动过鼠标或按着左键，且没在用手柄 / 触屏
func mouse_aim() -> bool:
	if _touching() or Pad.using:
		return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or g.t - _mouse_t < Bal.v("manual/mouse_idle", 8.0)


## 光标所在的世界坐标
func mouse_world() -> Vector2:
	return g.get_viewport().get_canvas_transform().affine_inverse() * g.get_viewport().get_mouse_position()


## 手动普攻的瞄准方向（单位向量）：鼠标 = 主控指向光标；手柄 = 右摇杆，没推取左摇杆 / 朝向；键盘 = 移动方向，站着取朝向；
## 触屏 = 攻击键拖出的方向，不拖返回 Vector2.ZERO（吸附最近目标）
func attack_dir() -> Vector2:
	if _touching():
		return touch_atk_dir.normalized() if touch_atk_dir != Vector2.ZERO else Vector2.ZERO
	if mouse_aim():
		var off: Vector2 = mouse_world() - g.ppos
		if off.length() > 4.0:
			return off.normalized()
	var d := manual_input_dir()
	return d if d != Vector2.ZERO else Vector2(g.facing, 0.0)


## 选落点技能（JSON "aim": "point"）此刻给的落点；Vector2.INF = 要走键盘蓄距离（或触屏没拖 = 自动瞄准）。
## 鼠标 = 光标；手柄右摇杆 = 方向 × 推量 × aim_range；触屏 = 技能键拖多远落多远（manual/touch_full 像素拖满 = aim_range）
func point_now(ld, i: int) -> Vector2:
	var rng: float = ld.aim_range(i)
	if _touching():
		var a: Vector2 = g.touch.aim_dir()
		if a == Vector2.ZERO:
			return Vector2.INF
		var k: float = clampf(a.length() / Bal.v("manual/touch_full", 110.0), 0.0, 1.0)
		return ld.pos + a.normalized() * maxf(Bal.v("manual/point_min", 150.0), k * rng)
	if mouse_aim():
		return mouse_world()
	for dev in Input.get_connected_joypads():
		var r := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if r.length() >= AIM_STICK:
			return ld.pos + r.limit_length(1.0) * rng
	return Vector2.INF


## 键盘 / 左摇杆蓄距离的落点：manual/point_charge 秒内从 manual/point_min 涨到 aim_range，沿移动方向（站着取朝向）。
## 没在蓄（轻点预览）时按最短距离
func charge_point(ld, i: int) -> Vector2:
	var t: float = float(charge.get("t", 0.0)) if not charge.is_empty() else 0.0
	var k: float = clampf(t / Bal.v("manual/point_charge", 0.6), 0.0, 1.0)
	var lo: float = Bal.v("manual/point_min", 150.0)
	var d := manual_input_dir()
	if d == Vector2.ZERO:
		d = Vector2(g.facing, 0.0)
	return ld.pos + d * lerpf(lo, maxf(lo, ld.aim_range(i)), k)


## 选落点技能的预览落点（界面画落点圈）：蓄距离中 / 鼠标 / 右摇杆 / 触屏拖动；都没有返回 Vector2.INF
func point_preview(ld, i: int) -> Vector2:
	if not charge.is_empty():
		return charge_point(ld, i)
	var p := point_now(ld, i)
	if p == Vector2.INF and not _touching():
		return charge_point(ld, i)   # 键盘站着：轻点的落点（朝向 150）
	return p


## 光标在对局右上角的倍速 / 暂停按钮上：左键是点按钮，不算攻击（game.gd 处理那次点击）
func _over_hud_btn() -> bool:
	var mp: Vector2 = g.get_viewport().get_mouse_position()
	for k in ["speed_btn", "pause_btn"]:
		var r = g.get(k)
		if r is Rect2 and r.has_area() and r.has_point(mp):
			return true
	return false


func _touching() -> bool:
	return g.touch != null and g.touch.active


func _skill_key_held() -> bool:
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_E) or (not manual_attack and Input.is_key_pressed(KEY_J)):
		return true
	for dev in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_A) or Input.is_joy_button_pressed(dev, JOY_BUTTON_Y) \
				or (not manual_attack and Input.is_joy_button_pressed(dev, JOY_BUTTON_X)):
			return true
	return false


func _press_point(o, i: int, pt: Vector2) -> void:
	var why: String = o.press_manual(i, Vector2.ZERO, pt)
	if why != "":
		g.vfx.add_text(g.ppos + Vector2(0, -96), "%s %s" % [o.skill_def(i).get("name", ""), why], Color(0.7, 0.75, 0.85), 14)
		Sfx.play("ui_move", -8.0, 0.7)


## 排异反应：博士承受，效果落在编队里随机一名能被海嗣化的干员身上（干员实现 apply_rejection）；
## 没有可承受的干员时改为直接削减博士生命上限
func apply_rejection() -> String:
	rej_count += 1
	var cands: Array = []
	for o in g.squad.ops:
		if o.has_method("apply_rejection"):
			cands.append(o)
	var what := ""
	g._shuffle(cands)   # 对局随机数（同 seed 可复现，docs/36）
	for c in cands:
		what = c.apply_rejection()
		if what != "":
			break
	if what == "":
		g.stats.add(&"max_hp", "flat", -20.0, "rejection")
		g.sync_stats()
		g.hp = minf(g.hp, g.max_hp)
		what = "生命上限 -20"
	rej_log.append(what)
	return what


## 排异记录（结算 / Tab 面板）：合并各干员的 rej 字典
func rej() -> Dictionary:
	var out: Dictionary = {}
	for o in g.squad.ops:
		if "rej" in o:
			for k in o.rej:
				out[k] = true
	return out


# ---------------------------------------------------------------- 被动

func passive_cat(pid: String) -> String:
	return PASSIVES.get(pid, {}).get("cat", "")


## 已选种类数（按类别）
func passive_kinds(cat: String) -> int:
	var n := 0
	for pid in PASSIVES:
		if PASSIVES[pid].cat == cat and g.growth.get(pid, 0) > 0:
			n += 1
	return n


## 可出的被动卡（按类别；种类满 4 后只出已有的）
func passive_cards(cat: String) -> Array:
	var out: Array = []
	var full: bool = passive_kinds(cat) >= PASSIVE_CAP
	for pid in PASSIVES:
		var pdef: Dictionary = PASSIVES[pid]
		if pdef.cat != cat:
			continue
		var n: int = g.growth.get(pid, 0)
		if n >= pdef.max or (full and n == 0):
			continue
		var nm: String = pdef.name if pdef.max > 90 else "%s  %d/%d" % [pdef.name, n + 1, pdef.max]
		out.append({"kind": "growth", "id": pid, "name": nm, "desc": pdef.desc + "\n" + passive_preview(pid), "cat": ("博士被动  DOCTOR" if cat == "doctor" else "全队被动  SQUAD")})
	return out


func apply_passive(pid: String) -> bool:
	if not PASSIVES.has(pid):
		return false
	var st = g.stats
	var src := "growth:" + pid
	match pid:
		"hp": st.add(&"max_hp", "flat", 20.0, src)
		"regen": st.add(&"regen", "flat", 0.6, src)
		"armor": st.add(&"armor", "flat", 2.0, src)
		"dodge": st.add(&"dodge", "flat", 0.05, src)
		"speed": st.add(&"move_speed", "mult", 1.1, src)
		"pickup": st.add(&"pickup", "mult", 1.3, src)
		"wick": st.add(&"light_decay", "mult", 0.85, src)
		"sp": st.add(&"sp_gain", "mult", 1.15, src)
		"squad_atk": st.add(&"op_atk", "add", 0.08, src, "squad")
		"squad_aspd": st.add(&"op_aspd", "add", 0.06, src, "squad")
		"squad_range": st.add(&"op_range", "add", 0.08, src, "squad")
		"squad_crit": st.add(&"op_skill_power", "add", 0.1, src, "squad")
	g.sync_stats()
	return true


func passive_preview(pid: String) -> String:
	match pid:
		"hp": return "最大生命 %d → %d" % [int(g.max_hp), int(g.max_hp) + 20]
		"regen": return "生命回复 %.1f → %.1f / 秒" % [g.regen, g.regen + 0.6]
		"armor": return "减伤 %d → %d" % [int(g.armor), int(g.armor) + 2]
		"dodge": return "闪避 %d%% → %d%%" % [int(g.dodge * 100), int(g.dodge * 100) + 5]
		"speed": return "移动速度 %d → %d" % [int(g.speed), int(g.speed * 1.1)]
		"pickup": return "拾取范围 %d → %d" % [int(g.pickup), int(g.pickup * 1.3)]
		"wick": return "受击灯火损失 ×%.2f → ×%.2f" % [g.lamp_decay, g.lamp_decay * 0.85]
		"sp": return "技力回复 ×%.2f → ×%.2f" % [g.sp_mult, g.sp_mult * 1.15]
		"squad_atk": return "全队攻击 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_atk", ["squad"]), g.stats.value_for(&"op_atk", ["squad"]) + 0.08]
		"squad_aspd": return "全队攻速 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_aspd", ["squad"]), g.stats.value_for(&"op_aspd", ["squad"]) + 0.06]
		"squad_range": return "全队范围 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_range", ["squad"]), g.stats.value_for(&"op_range", ["squad"]) + 0.08]
		"squad_crit": return "技能强度 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_skill_power", ["squad"]), g.stats.value_for(&"op_skill_power", ["squad"]) + 0.1]
	return ""


## 填充卡：其他类别都满时
func filler_cards() -> Array:
	return [
		{"kind": "filler", "id": "heal", "name": "急救补给", "desc": "主控立刻回复 30% 最大生命", "cat": "补给  SUPPLY"},
		{"kind": "filler", "id": "oil", "name": "灯油补给", "desc": "灯火 +30", "cat": "补给  SUPPLY"},
		{"kind": "filler", "id": "atk", "name": "临时协同", "desc": "全队干员攻击 +4%（可叠加）", "cat": "补给  SUPPLY"},
	]


func apply_filler(fid: String) -> void:
	match fid:
		"heal": g.combat.heal(g.max_hp * 0.3, "填充卡")
		"oil": g.lamp = minf(g.lamp_cap, g.lamp + 30.0)
		"atk":
			g.stats.add(&"op_atk", "add", 0.04, "filler", "squad")
			g.sync_stats()
