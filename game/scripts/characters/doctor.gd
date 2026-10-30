## 博士（docs/23 §3）：场上唯一的受击体。生命 / 位置 / 移动 / 拾取 / 灯火 / 等级这些通用状态仍由 game.gd 持有（ppos / hp / …），
## 本文件放博士层的专属逻辑：指挥技能（唯一的手动技能）、排异反应、局外成长接入。
extends RefCounted

var g
var def: Dictionary = {}
var rej_count := 0             # 排异反应次数（结局线用）
var rej_log: Array = []        # 每次排异的说明文字

## 被动成长卡（docs/23 §6；10-13 用户 / 协调人改版，docs/83）。内部类别 key 不改，玩家看到的类别名见 CAT_LABEL：
##   doctor → 生存（主控的生命 / 回复 / 减伤 / 闪避 / 拾取 / 护灯），种类上限 PASSIVE_CAP 4
##   mobility → 机动（移动速度 + 冲刺三张），种类上限 balance.json levelup/mobility_kinds（缺省 3）
##   squad → 协同（全队干员），种类上限 PASSIVE_CAP 4
## 选满种类后只出已有种类。desc 里的数字由 passive_desc() 按 balance.json 现值生成的，以它为准。
## 卡的定义在 data/cards.json（10-22 从这里的常量原样迁出，docs/126 A1）：键序 = 出卡 / 机器人遍历的顺序；新卡只填 json
static var _card_data = null
static var PASSIVES: Dictionary = _cards().get("passives", {})
static var FILLERS: Array = _cards().get("fillers", [])


static func _cards() -> Dictionary:
	if _card_data == null:
		_card_data = {}
		var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary:
			_card_data = d
		else:
			push_error("data/cards.json 缺失或格式不对：升级卡为空")
	return _card_data


## 一张卡的效果数值：value，或 value_bal [balance.json 路径, 缺省]（invert = 取 1 − 值）
static func card_value(c: Dictionary) -> float:
	if c.has("value_bal"):
		var v: float = Bal.v(str(c.value_bal[0]), float(c.value_bal[1]))
		return 1.0 - v if c.get("invert", false) else v
	return float(c.get("value", 0.0))
const PASSIVE_CAP := 4         # 生存 / 协同每类最多几种；机动见 cat_cap()
const CAT_LABEL := {"doctor": "生存  SURVIVAL", "mobility": "机动  MOBILITY", "squad": "协同  SQUAD", "fire": "火力  FIREPOWER", "lane": "流派  BUILD"}
const CATS := ["doctor", "mobility", "squad", "fire", "lane"]
## 流派卡（docs/203）卡面类别写流派名（颜色走 UI.CAT_COL），名字同 relics.json lane_names
const LANE_LABEL := {"melee": "近战扩域  MELEE", "multi": "多弹火力  MULTI", "summon": "召唤驻场  SUMMON", "control": "控场引爆  CONTROL", "weak": "弱点收割  WEAK", "shield": "护盾反击  SHIELD"}   # fire（火力，10-23 用户定）：远程普攻子弹的成长，只在编队有能穿透的远程普攻干员时出卡（cards.json requires: ranged_basic）


## 类别的种类上限
static func cat_cap(cat: String) -> int:
	return Bal.vi("levelup/mobility_kinds", 3) if cat == "mobility" else PASSIVE_CAP


## 被动卡的类别中文名（「生存」「机动」「协同」）：精英二条件等提示用
static func cat_name(pid: String) -> String:
	return str(CAT_LABEL.get(PASSIVES.get(pid, {}).get("cat", ""), "成长")).split("  ")[0]


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


# ---------------------------------------------------------------- 按住瞄准与选落点（契约 v2.5，docs/26 §v2.5；10-31 用户定取消「手动普攻」）

## 普攻永远自动起手；主控「按住瞄准」期间普攻的方向 / 目标改朝玩家指向，松手立即回到自动索敌。队友、机器人、图鉴演示不响应。
## 按住瞄准：键鼠 = 按住左键（不在界面按钮上），手柄 = 右摇杆推过 AIM_STICK，触屏 = 瞄准键拖过死区（touch.gd 写 touch_atk / touch_atk_dir）
const Bal = preload("res://scripts/core/balance.gd")
const StatDefs = preload("res://scripts/core/stat_defs.gd")

var aim_on := false            # 这一局主控响应按住瞄准（开局定：机器人 / 自动测试 / 图鉴演示不响应）
var atk_edge := false          # 这一帧刚开始按住瞄准（凯尔希：按下时给 Mon3tr 换目标）
var _atk_prev := false
var touch_atk := false         # 触屏瞄准键按住（touch.gd 写）
var touch_atk_dir := Vector2.ZERO   # 触屏瞄准键拖出的方向；ZERO = 没拖过死区（仍是自动）
var sim_atk := false           # 测试脚本模拟按住瞄准（方向取 sim_dir）
var sim_dir := Vector2.ZERO    # 测试脚本给的瞄准方向；ZERO = 朝向
var _mouse_last := Vector2.INF
var _mouse_t := -99.0          # 最近一次鼠标移动 / 点击的时刻（g.t）：只给选落点技能的 point_now 用
var charge := {}               # 选落点技能键盘蓄距离中：{"i": 技能序号, "t": 已蓄秒数}


## 开局调用：机器人 / 自动测试 / 图鉴演示不响应按住瞄准
func init_aim() -> void:
	aim_on = g.bot == null and g.mode == g.Mode.PLAY and g.demo_op == ""


## 每帧（squad.update 开头）：瞄准边沿、鼠标活动、键盘蓄距离
var _ma_init := false

func tick_input(dt: float) -> void:
	if not _ma_init:
		_ma_init = true
		init_aim()
	var held := aim_held()
	atk_edge = held and not _atk_prev
	_atk_prev = held
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


## 此刻是否在按住瞄准：键鼠左键（不在界面按钮上）、手柄右摇杆推过 AIM_STICK、触屏瞄准键拖过死区
func aim_held() -> bool:
	if sim_atk:
		return true
	if not aim_on or g.state != g.S.PLAY:
		return false
	if _touching():
		return touch_atk and touch_atk_dir != Vector2.ZERO   # 触屏会模拟鼠标左键，只认瞄准键；按着不拖 = 自动
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _over_hud_btn():
		return true
	return _stick_aim() != Vector2.ZERO


## 手柄右摇杆推过 AIM_STICK 的方向（单位向量），没推 = ZERO
func _stick_aim() -> Vector2:
	for dev in Input.get_connected_joypads():
		var r := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if r.length() >= AIM_STICK:
			return r.normalized()
	return Vector2.ZERO


## 键鼠此刻用鼠标给落点（选落点技能 point_now 用）：最近 manual/mouse_idle 秒动过鼠标或按着左键，且没在用手柄 / 触屏
func mouse_aim() -> bool:
	if _touching() or Pad.using:
		return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or g.t - _mouse_t < Bal.v("manual/mouse_idle", 8.0)


## 光标所在的世界坐标
func mouse_world() -> Vector2:
	return g.get_viewport().get_canvas_transform().affine_inverse() * g.get_viewport().get_mouse_position()


## 按住瞄准的方向（单位向量，永远非零）：测试 = sim_dir；触屏 = 瞄准键拖出的方向；鼠标按住 = 主控指向光标；手柄 = 右摇杆；都没有取朝向
func attack_dir() -> Vector2:
	if sim_atk:
		return sim_dir.normalized() if sim_dir != Vector2.ZERO else Vector2(g.facing, 0.0)
	if _touching():
		return touch_atk_dir.normalized() if touch_atk_dir != Vector2.ZERO else Vector2(g.facing, 0.0)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not Pad.using:
		var off: Vector2 = mouse_world() - g.ppos
		if off.length() > 4.0:
			return off.normalized()
	var d := _stick_aim()
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


## 鼠标左键点场地放选落点技能（用户 10-26「乌尔比安的三技能要设置成鼠标点击也能够触发，否则的话太鸡肋了」）：
## 队长的手动技能是选落点（JSON "aim": "point"）、已解锁、技力满且此刻放得出时接管这次点击，落点 = 点击处（press_manual 里夹在 aim_range 内）；
## 其余情况（技力没满、不是选落点技能、正在出手放不了…）返回 false，点击照旧（左键 = 按住瞄准）。触屏（会模拟鼠标左键）、
## 键盘正在蓄距离、点在 HUD 上（hud.blocks_click）不接管。Q / E / J、手柄、触屏技能键照旧。vp = 视口坐标（事件 position）
func click_skill(vp: Vector2) -> bool:
	if _touching() or not charge.is_empty() or Bal.v("manual/click_cast", 1.0) <= 0.0:
		return false
	if g.hud_view.blocks_click(vp / Cfg.ui_k):
		return false
	var ld = g.squad.leader()
	var i: int = ld.manual_index() if ld != null else -1
	if i < 0 or not ld.skill_unlocked(i) or not ld.manual_point(i) or ld.perm[i]:
		return false
	if ld.sp[i] < ld.sp_need(i) or ld.skill_active_left(i) > 0.0 or ld.manual_block_reason(i, Vector2.RIGHT) != "":
		return false
	_mouse_t = g.t
	_press_point(ld, i, g.get_viewport().get_canvas_transform().affine_inverse() * vp)
	return true


## 光标在对局右上角的倍速 / 暂停按钮上：左键是点按钮，不算按住瞄准（game.gd 处理那次点击）
func _over_hud_btn() -> bool:
	var mp: Vector2 = g.get_viewport().get_mouse_position() / Cfg.ui_k   # 两个按钮记的是界面坐标（界面大小 ≠ 100% 时要换算）
	for k in ["speed_btn", "pause_btn"]:
		var r = g.get(k)
		if r is Rect2 and r.has_area() and r.has_point(mp):
			return true
	return false


func _touching() -> bool:
	return g.touch != null and g.touch.active


func _skill_key_held() -> bool:
	if Pad.key_down(KEY_Q) or Pad.key_down(KEY_E) or Pad.key_down(KEY_J):
		return true
	for dev in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_A) or Input.is_joy_button_pressed(dev, JOY_BUTTON_Y) \
				or Input.is_joy_button_pressed(dev, JOY_BUTTON_X):
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
	# 达里奥的提灯 / 郁金香的秘方 / 养育者基因种（docs/57 P18）：免疫次数 > 0 时这次排异被抑制
	if g.get("rfx") != null and g.rfx.rule("rej_immune") > 0:
		g.rfx.use_rule("rej_immune")
		rej_log.append("已被抑制")
		return "已被抑制"
	rej_count += 1
	var cands: Array = []
	for o in g.squad.ops:
		if o.has_method("apply_rejection"):
			cands.append(o)
	var what := ""
	g.shuffle(cands)   # 对局随机数（同 seed 可复现，docs/36）
	for c in cands:
		what = c.apply_rejection()
		if what != "":
			break
	if what == "":
		g.stats.add(&"max_hp", "flat", -20.0, "rejection")
		g.sync_stats()
		g.hp = minf(g.hp, g.max_hp)
		what = "队长最大生命 -20"
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
	var full: bool = passive_kinds(cat) >= cat_cap(cat)
	for pid in PASSIVES:
		var pdef: Dictionary = PASSIVES[pid]
		if pdef.cat != cat:
			continue
		var n: int = g.growth.get(pid, 0)
		if n >= pdef.max or (full and n == 0):
			continue
		if not pdef.get("pool", true):
			continue   # 精简停用（docs/203）：生存属性只在认知塑造
		var rq: String = str(pdef.get("requires", ""))
		if rq.begins_with("lane:") and not g.squad.ops.any(func(o): return o.in_lane(rq.substr(5))):
			continue   # 流派卡：编队里有该流派干员才出
		if str(pdef.get("stat", "")) == "shield_interval" and g.shield_max <= 0:
			continue   # 护盾·充能：没有护盾层数时没用
		if str(pdef.get("requires", "")) == "ranged_basic" and not _squad_has_pierce_atk():
			continue   # 贯穿（10-23）：编队里没有子弹能穿透的远程普攻干员就不进池
		var nm: String = pdef.name if pdef.max > 90 else "%s  %d/%d" % [pdef.name, n + 1, pdef.max]
		var cl: String = LANE_LABEL.get(rq.substr(5), CAT_LABEL.get(cat, "")) if cat == "lane" else CAT_LABEL.get(cat, "")
		out.append({"kind": "growth", "id": pid, "name": nm, "desc": passive_desc(pid) + "\n" + passive_preview(pid), "cat": cl})
	return out


## 编队里有没有普攻子弹能穿透的干员（data_operator.pierce_atk：能天使弹道 / 流明光弹 / 拉普兰德普攻剑气）
func _squad_has_pierce_atk() -> bool:
	for o in g.squad.ops:
		if o.get("pierce_atk") == true:
			return true
	return false


func apply_passive(pid: String) -> bool:
	if not PASSIVES.has(pid):
		return false
	var c: Dictionary = PASSIVES[pid]
	g.stats.add(StringName(str(c.stat)), str(c.op), card_value(c), "growth:" + pid, str(c.get("scope", "")))
	g.sync_stats()
	return true


## 卡面说明（数字按 balance.json 现值；「自愈」写的是选中后实际多出的每秒回复，含回复效果倍率）
func passive_desc(pid: String) -> String:
	match pid:
		"regen":
			var d: float = g.combat.regen_per_sec(Bal.v("sustain/regen_card", 0.4)) - g.combat.regen_per_sec()
			return "队长生命回复 +%s / 秒" % _num(d)
		"armor":
			return "队长受到的物理伤害 -%d%%（乘算；对法术、真实伤害无效）" % int(round(Bal.v("growth/armor_pct", 0.08) * 100.0))
		"dash_cd":
			return "冲刺冷却 -%d%%" % int(round((1.0 - Bal.v("dash/cd_card", 0.88)) * 100.0))
		"dash_dist":
			return "冲刺距离 +%d%%" % int(round(Bal.v("dash/dist_card", 0.12) * 100.0))
	return str(PASSIVES.get(pid, {}).get("desc", ""))


static func _num(v: float) -> String:
	var t := "%.2f" % v
	while t.ends_with("0"):
		t = t.substr(0, t.length() - 1)
	return t.trim_suffix(".")


## 卡面预览「现值 → 选中后」：都按属性系统算最终值（StatBlock.value_with），和属性面板、实际生效一致（docs/83 §2）。
## 坚韧的 +20 是固定加成：最大生命的固定加成放在倍率之后（stat_block.FLAT_AFTER，docs/199），卡上写多少就加多少
func passive_preview(pid: String) -> String:
	var st = g.stats
	match pid:
		"hp": return "最大生命 %d → %d" % [int(g.max_hp), int(maxf(20.0, st.value_with(&"max_hp", "flat", 20.0)))]
		"regen": return "生命回复 %.1f → %.1f / 秒" % [g.combat.regen_per_sec(), g.combat.regen_per_sec(Bal.v("sustain/regen_card", 0.4))]
		"armor": return "受到的物理伤害 ×%.2f → ×%.2f" % [g.phys_taken_mult, st.value_with(&"phys_taken", "mult", 1.0 - Bal.v("growth/armor_pct", 0.08))]
		"dodge": return "闪避 %d%% → %d%%" % [int(round(g.dodge * 100)), int(round(st.value_with(&"dodge", "flat", 0.05) * 100))]
		"speed": return "移动速度 %d → %d" % [int(g.speed), int(st.value_with(&"move_speed", "mult", 1.1))]
		"pickup": return "拾取范围 %d → %d" % [int(g.pickup), int(st.value_with(&"pickup", "mult", 1.3))]
		"wick": return "受击灯火损失 ×%.2f → ×%.2f" % [g.lamp_decay, st.value_with(&"light_decay", "mult", 0.85)]
		"dash_cd": return "冲刺冷却 %.2f → %.2f 秒" % [g.dash_cd_full(), Bal.v("dash/cd", 1.2) * st.value_with(&"dash_cd", "mult", Bal.v("dash/cd_card", 0.88))]
		"dash_dist": return "冲刺距离 %d → %d" % [int(round(g.dash_dist())), int(round(Bal.v("dash/dist", 107.0) * st.value_with(&"dash_dist", "add", Bal.v("dash/dist_card", 0.12))))]
		"dash_charge": return "可储存次数 %d → %d" % [g.dash_max(), g.dash_max() + 1]
		"sp": return "技力回复 ×%.2f → ×%.2f" % [g.sp_mult, g.sp_mult * 1.15]
		"squad_atk": return "全队攻击 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_atk", ["squad"]), g.stats.value_for(&"op_atk", ["squad"]) + Bal.v("squad/op_atk_base", 0.9) * 0.08]   # 加算：+0.08 乘在基础 op_atk_base 上（10-28 原写 +0.08，实际 +0.072）
		"squad_aspd": return "全队攻速 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_aspd", ["squad"]), g.stats.value_for(&"op_aspd", ["squad"]) + 0.06]
		"squad_range": return "全队范围 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_range", ["squad"]), g.stats.value_for(&"op_range", ["squad"]) + 0.08]
		"squad_crit": return "技能强度 ×%.2f → ×%.2f" % [g.stats.value_for(&"op_skill_power", ["squad"]), g.stats.value_for(&"op_skill_power", ["squad"]) + 0.1]
	# 新卡（cards.json 里有、上面没写特别写法的）：属性 现值 → 选中后
	var c: Dictionary = PASSIVES.get(pid, {})
	if c.has("stat") and str(c.get("scope", "")) == "":
		var sn := StringName(str(c.stat))
		# 卡面不露内部键名：用属性表的中文名（去掉括注）；倍率类（基值 1）写成 ×，其余写数值
		var d: Dictionary = StatDefs.PLAYER.get(sn, {})
		var label := str(d.get("name", c.stat)).get_slice("（", 0)
		var now: float = st.value(sn)
		var nxt: float = st.value_with(sn, str(c.op), card_value(c))
		if is_equal_approx(float(d.get("base", 0.0)), 1.0):
			return "%s ×%.2f → ×%.2f" % [label.trim_suffix("倍率"), now, nxt]
		return "%s %s → %s" % [label, _num(now), _num(nxt)]
	return ""


## 填充卡：其他类别都满时（cards.json fillers）
func filler_cards() -> Array:
	var out: Array = []
	for c in FILLERS:
		if not c.get("pool", true):
			continue   # 「急救补给」停用（docs/203 §3：回血收成 5 条）
		out.append({"kind": "filler", "id": str(c.id), "name": str(c.name), "desc": str(c.desc), "cat": "补给  SUPPLY"})
	return out


func apply_filler(fid: String) -> void:
	for c in FILLERS:
		if str(c.id) != fid:
			continue
		match str(c.get("effect", "")):
			"heal_pct": g.combat.heal(g.max_hp * float(c.value), "填充卡")
			"lamp": g.lamp = minf(g.lamp_cap, g.lamp + float(c.value))
			"stat":
				g.stats.add(StringName(str(c.stat)), str(c.op), float(c.value), "filler", str(c.get("scope", "")))
				g.sync_stats()
		return


# ---------------------------------------------------------------- 博士挂件跟随（docs/23 v0.7；10-15 从 game.gd 搬来，docs/101 S5）
## 不受击、不攻击，慢慢跑着跟在主控身后；离太远（传送 / 开局）才直接归位。位置 / 跑停 / 朝向（g.doc_pos / doc_moving / doc_face）仍放在 game.gd（绘制与排序要读）
const DOC_SPEED := 175.0        # 略快于主控基础移速 150，追得上但不会贴身
const DOC_BEHIND := Vector2(-40, 30)
const DOC_STOP_T := 0.15
var doc_still_t := 0.0           # 博士连续「几乎没动」的时间：超过 DOC_STOP_T 才切站立（走停滞后，免得跑 / 站帧条来回闪）


func update_follow(dt: float) -> void:
	var want: Vector2 = g.ppos + Vector2(DOC_BEHIND.x * g.facing, DOC_BEHIND.y)
	if g.doc_pos == Vector2.INF or g.doc_pos.distance_to(want) > 600.0:
		g.doc_pos = want
	var d: Vector2 = want - g.doc_pos
	var step: float = minf(d.length(), DOC_SPEED * dt * clampf(d.length() / 60.0, 0.35, 1.0))
	var mv: Vector2 = d.normalized() * step if d.length() > 1.0 else Vector2.ZERO
	g.doc_pos += mv
	# 走停滞后：起步要够快（> 30 像素 / 秒）；停下要连续慢（< 20）DOC_STOP_T 秒
	var spd: float = mv.length() / maxf(dt, 0.0001)
	if g.doc_moving:
		doc_still_t = doc_still_t + dt if spd < 20.0 else 0.0
		g.doc_moving = doc_still_t < DOC_STOP_T
	else:
		g.doc_moving = spd > 30.0
		doc_still_t = 0.0
	if absf(mv.x) > 6.0 * dt:
		g.doc_face = signf(mv.x)
	elif not g.doc_moving:
		g.doc_face = g.facing
