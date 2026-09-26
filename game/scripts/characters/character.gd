## 编队干员的基类（docs/23）：开局干员是玩家操控的主控（唯一受击体，生命 / 减伤 / 法抗见 JSON leader 段），
## 招募的干员跟随主控、自动输出、不会倒下；定义 game.gd / squad.gd 调用的接口，默认实现为空。
## 每个干员 = data/characters/<id>.json（名字、职业、贴图集、技能表、成长线）+ scripts/characters/<id>.gd（行为）。
## 生命、等级、经验、拾取由 game.gd 持有；博士是挂件（characters/doctor.gd：指挥技能、被动、排异反应）。
## 干员调用 game.gd 的能力一律走 op_api.gd（本类的父类），不直接调用 g._ 开头的内部函数。
extends "res://scripts/characters/op_api.gd"

const A = preload("res://scripts/art.gd")

var def: Dictionary = {}   # 角色定义（JSON）
var id := ""
var cls := ""              # 职业：先锋/近卫/重装/狙击/术师/医疗/辅助/特种（def.class）

# ---- 场上实体：位置 / 朝向 / 移动（squad.gd 每帧调 follow）
var pos := Vector2.INF
var face := 1.0
var mv := 0.0              # 平滑后的移动速度（切换跑步动画用）
var mt := 0.0              # 移动计时（跑步循环）
var slot := 0              # 编队位序号
var is_leader := false     # 主控干员（玩家操控、唯一受击体，docs/23 v0.7）
var node_lv := 0           # 已拿的普通成长节点数（0–4），驱动统一小强化与气场
const NODE_ATK := 0.06
var aura_t := 0.0
var voice_t := 25.0        # 战斗台词计时（squad.gd 每帧递减）
var elite := 0             # 精英化阶段 0 / 1 / 2
var prog := 0              # 已应用的成长节点数（progression 数组下标）
var sp: Array = [0.0, 0.0, 0.0]   # 三个自动技能的充能（契约 v2.1：招募 S1 / 精一 S2 / 精二 S3）
var cur_skill := 0                # 正在起手的技能序号（start_skill → _release_skill）
var rej: Dictionary = {}          # 排异反应：被海嗣化的技能序号 → true
var perm: Array = [false, false, false]   # 永久型技能（JSON permanent）：充能一次释放后永久生效，不再充能
var attack_t := 0.0        # >0 表示正在播放攻击动作（由干员在出手时设置）
var attack_dur := 0.25
var fire_t := -1.0         # 出手帧倒计时（start_attack / start_skill 后到点调用 _release / _release_skill）
var act_kind := "attack"   # 当前动作的逻辑类型：attack（出手调 _release）/ skill（出手调 _release_skill）
var act_anim := "attack"   # 当前动作实际播放的帧条（通常同 act_kind；技能可借用别的帧条，见 skill_anim）
# ---- 动画：贴图槽来自 def.sprites（idle / run / attack / hurt / death），帧数 = 宽 / 高
var anim_kind := ""
var anim_t := 0.0
const ANIM_FPS := {"idle": 4.0, "run": 10.0, "hurt": 10.0, "death": 6.0}
# ---- 干员自己的特效粒子（docs/25）：{kind, pos, life, max, col, r, vel, floor, …}，squad.gd 每帧 tick、按层绘制
var pfx: Array = []
## 职业主色（干员 JSON 可用 "col": [r, g, b] 覆盖）：HUD 环、卡面、默认特效色
const CLASS_COL := {
	"先锋": Color(1.0, 0.78, 0.35), "近卫": Color(0.55, 0.75, 1.0), "重装": Color(1.0, 0.72, 0.38), "狙击": Color(1.0, 0.42, 0.38),
	"术师": Color(1.0, 0.5, 0.22), "医疗": Color(0.55, 1.0, 0.6), "辅助": Color(1.0, 0.85, 0.5), "特种": Color(0.75, 0.6, 1.0),
}


func _init(game, def_: Dictionary) -> void:
	g = game
	def = def_
	id = def.get("id", "")
	cls = def.get("class", "")


static func list_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://data/characters")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	return out


static func load_def(cid: String) -> Dictionary:
	var f := FileAccess.open("res://data/characters/%s.json" % cid, FileAccess.READ)
	if f == null:
		push_error("character def missing: " + cid)
		return {"id": cid}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {"id": cid}


## 按 id 实例化角色（脚本路径来自定义里的 script 字段，默认 scripts/characters/<id>.gd）
static func create(game, cid: String) -> RefCounted:
	var d := load_def(cid)
	var path: String = d.get("script", "res://scripts/characters/%s.gd" % cid)
	var scr = load(path)
	if scr == null:
		push_error("character script missing: " + path)
		return null
	var inst = scr.new(game, d)
	validate_operator(cid, d)
	return inst


## 干员契约 v2.1（docs/23 §4.2）：attack（普攻）+ 恰好 3 个自动技能 skills[0..2]（招募 / 精一 / 精二解锁）；talent 可选（精一）；
## 手动技能只属于博士；progression 若存在必须是数组，节点 type ∈ stat / elite / custom，elite 节点带 level
static func validate_operator(cid: String, d: Dictionary) -> bool:
	var ok := true
	if not d.has("attack") or not (d.attack is Dictionary):
		push_error("干员 %s 缺少 attack 定义" % cid)
		ok = false
	var sk = d.get("skills", null)
	if not (sk is Array) or sk.size() != 3:
		push_error("干员 %s 必须恰好定义 3 个技能（skills 数组）" % cid)
		ok = false
	else:
		for i in 3:
			if not (sk[i] is Dictionary) or not sk[i].has("name"):
				push_error("干员 %s 的技能 %d 缺 name" % [cid, i + 1])
				ok = false
			elif not sk[i].get("mode", "auto") in ["auto", "manual"]:
				push_error("干员 %s 的技能 %d 的 mode 只能是 auto / manual" % [cid, i + 1])
				ok = false
			elif sk[i].has("anim") and not d.get("sprites", {}).has(str(sk[i].anim)):
				push_error("干员 %s 的技能 %d 的 anim「%s」不是它的帧条（sprites 里没有）" % [cid, i + 1, sk[i].anim])
				ok = false
		if sk.filter(func(x): return x is Dictionary and x.get("mode", "auto") == "manual").size() > 1:
			push_error("干员 %s 最多只能有 1 个手动技能" % cid)
			ok = false
	var prog = d.get("progression", [])
	if not (prog is Array):
		push_error("干员 %s 的 progression 必须是数组" % cid)
		return false
	for i in prog.size():
		var n = prog[i]
		if not (n is Dictionary) or not n.get("type", "") in ["stat", "elite", "custom"]:
			push_error("干员 %s 的成长节点 %d 类型非法" % [cid, i])
			ok = false
		elif n.type == "elite" and not n.has("level"):
			push_error("干员 %s 的精英化节点 %d 缺 level" % [cid, i])
			ok = false
	return ok


## 手动技能入口（Q / J）：三自动角色返回 false；两自动一主动的角色在这里校验解锁与资源后施放
func try_manual_skill() -> bool:
	return false


## 图鉴 / 面板显示用的能力标签（3–5 个玩家能懂的词），来自角色 JSON 的 gallery.tags
func display_tags() -> Array:
	return def.get("gallery", {}).get("tags", [])


# ---------------------------------------------------------------- 每帧

## 普攻节奏、技能计时、专属实体（在敌人更新之后、援护之前调用）
func update(_dt: float) -> void:
	pass


# ---------------------------------------------------------------- 开局干员接口（任何干员都可以是 ch；水月覆盖其中的旧三技能 / 路线部分）

func col() -> Color:
	var c = def.get("col", null)
	if c is Array and c.size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]))
	return CLASS_COL.get(cls, Color(0.6, 0.9, 1.0))


## 任一持续型技能是否生效中（音乐强度 / 黑色郁金香）
func skill_active() -> bool:
	for i in 3:
		if skill_active_left(i) > 0.0:
			return true
	return false


## 持续型技能 i 的剩余秒数 / 总时长（HUD 环倒计时；生效期间该技能不充能）；瞬发技能返回 0
func skill_active_left(_i: int) -> float:
	return 0.0


func skill_active_dur(i: int) -> float:
	return float(skill_def(i).get("dur", 1.0))


## HUD 右下三个环：[字, 名, 已解锁, 生效剩余, 生效总长, 充能比例, 颜色, 计数格数, 已有计数, 图标名]
func skill_hud() -> Array:
	var out: Array = []
	var c := col()
	for i in 3:
		var sd := skill_def(i)
		var need := sp_need(i)
		var sc: Color = Color(0.85, 0.55, 1.0) if rej.has(i) else c
		var nm: String = sd.get("name", "技能 %d" % (i + 1)) + ("·永久" if perm[i] else "")
		out.append([sd.get("name", "技").substr(0, 1), nm, skill_unlocked(i), skill_active_left(i), skill_active_dur(i),
			(sp[i] / need) if need > 0.0 else 1.0, sc, 0, 0, sd.get("icon", "")])
	return out


## 编队栏头像环：已解锁的最高技能的充能比例
func hud_sp_frac() -> float:
	for i in [2, 1, 0]:
		if skill_unlocked(i) and sp_need(i) > 0.0 and not perm[i]:
			return clampf(sp[i] / sp_need(i), 0.0, 1.0)
	return 1.0


## 三个技能同时充能（生效中的不充）；返回本帧该释放的技能序号（S3 > S2 > S1，一次只放一个），没有返回 -1
## 充能改由 squad.update 每帧调 tick_sp()（2026-09-26 修：以前充能写在各干员「出手中就 return」之后，
## 攻速快的干员几乎一直在出手，技能实际要等 2–3 倍时间）。这里只判断谁充满了；dt 参数保留兼容
func charge_skills(_dt: float) -> int:
	var ready := -1
	for i in 3:
		if not skill_unlocked(i):
			continue
		var need := sp_need(i)
		if need <= 0.0 or skill_active_left(i) > 0.0 or perm[i]:
			continue
		if sp[i] >= need and not is_manual(i):
			ready = i
	return ready


## 技能充能（每帧，不论是否在出手）：生效中的持续型技能与永久型不充
func tick_sp(dt: float) -> void:
	for i in 3:
		if not skill_unlocked(i):
			continue
		var need := sp_need(i)
		if need <= 0.0 or skill_active_left(i) > 0.0 or perm[i]:
			continue
		if sp[i] < need:
			sp[i] = minf(need, sp[i] + dt * g.sp_mult * stat(&"op_skill_sp") * lamp_sp())
	_tick_manual_buf(dt)


## 手动技能（契约 v2.3，2026-09-26 用户定）：技能 JSON 带 "mode": "manual" 时，只有该干员当主控才手动——照常充能、
## 充满不自动放，等玩家按 Q / J（手柄 Ⓐ / Ⓧ，手机技能键），入口是 doctor.try_manual_skill()；当队友时照旧自动释放。
## 主控换人时随 is_leader 自动切换。每名干员最多一个（校验按 JSON 的 mode 计数，与是否主控无关）
func is_manual(i: int) -> bool:
	return is_leader and skill_def(i).get("mode", "auto") == "manual"


func manual_index() -> int:
	for i in 3:
		if is_manual(i):
			return i
	return -1


## 手动技能此刻能否释放（已解锁、已充满、不在生效中、本体在场且没在出手）。dir：玩家给的方向（单位向量），
## Vector2.ZERO = 自动瞄准。干员可重写追加自己的条件（乌尔比安：锚已收回、自动瞄准时 400 内有敌人）：return super(i, dir) and ……
func manual_ready(i: int, _dir: Vector2 = Vector2.ZERO) -> bool:
	return i >= 0 and skill_unlocked(i) and not perm[i] and sp_need(i) > 0.0 and sp[i] >= sp_need(i) 		and skill_active_left(i) <= 0.0 and not acting() and pos != Vector2.INF and not (has_method("away") and call("away"))


## 带方向的手动技能（契约 v2.4，2026-09-26 用户定）：技能 JSON 带 "aim": true 时，按键会把方向传进来——键鼠 = 当前移动方向，
## 手柄 = 右摇杆（没推取左摇杆移动方向），手机 = 按住技能键拖出的方向；站着不动 / 直接点 = Vector2.ZERO（自动瞄准）。
## 干员在出手帧读 manual_dir（读完清零），并重写 manual_aim_point 给出预计落点（界面画瞄准线与落点圈）。机器人一律自动瞄准
func manual_aims(i: int) -> bool:
	return i >= 0 and bool(skill_def(i).get("aim", false))


var manual_dir := Vector2.ZERO

func cast_manual(i: int, dir: Vector2 = Vector2.ZERO) -> bool:
	if not manual_aims(i):
		dir = Vector2.ZERO
	if not manual_ready(i, dir):
		return false
	manual_buf = 0.0
	manual_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.ZERO
	start_skill(pos + manual_dir * 60.0 if manual_dir != Vector2.ZERO else Vector2.INF, i)
	return true


## 预计落点（瞄准指示用）：dir 同上；干员没实现或此刻没有落点返回 Vector2.INF
func manual_aim_point(_i: int, _dir: Vector2 = Vector2.ZERO) -> Vector2:
	return Vector2.INF


## 玩家按下手动技能键（doctor.try_manual_skill 调用）：就绪就放；充能已满、只是正在出手（或干员自己的「稍等」条件，
## manual_block_reason 返回空串）时先记下这次按键（连同方向），MANUAL_BUF 秒内一满足就放，免得按键撞上出手被吞。
## 返回 "" = 已放出或已记下；否则返回提示原因
const MANUAL_BUF := 1.0
var manual_buf := 0.0
var manual_buf_dir := Vector2.ZERO

func press_manual(i: int, dir: Vector2 = Vector2.ZERO) -> String:
	if not manual_aims(i):
		dir = Vector2.ZERO
	if cast_manual(i, dir):
		return ""
	if skill_active_left(i) > 0.0:
		return "生效中"
	if has_method("away") and call("away"):
		return "暂时离场"
	if sp[i] < sp_need(i):
		return "充能中"
	var why := manual_block_reason(i, dir)
	if why == "":
		manual_buf = MANUAL_BUF
		manual_buf_dir = dir
	return why


func _tick_manual_buf(dt: float) -> void:
	if manual_buf <= 0.0:
		return
	manual_buf -= dt
	var i := manual_index()
	if i < 0:
		manual_buf = 0.0
	elif manual_ready(i, manual_buf_dir):
		cast_manual(i, manual_buf_dir)


## 充能已满但干员自己的条件不满足、等也没用时，按键提示的原因（如「附近没有敌人」）；空串 = 只是稍等，按键先记下
func manual_block_reason(_i: int, _dir: Vector2 = Vector2.ZERO) -> String:
	return ""


## 机器人（自动测试 / 批跑）是否替玩家按下手动技能 i：已就绪时每帧询问。缺省按保命型：主控生命低于
## balance.json bot/manual_hp（0.3）才按；进攻型手动技能重写成自己的时机（乌尔比安 S3：就绪即放）
func bot_wants_manual(_i: int) -> bool:
	return g.hp < g.max_hp * preload("res://scripts/core/balance.gd").v("bot/manual_hp", 0.3)


## 消费技能 i 的充能并通知藏品（技能开始事件）
func spend_sp(i: int) -> void:
	sp[i] = 0.0
	# 技能发动音（op_<id>_s1/s2/s3）。character.gd 也被 -s 测试脚本直接加载，那时没有 Sfx 自动加载，所以按节点路径取
	var sfx: Node = g.get_node_or_null("/root/Sfx") if g != null and g.is_inside_tree() else null
	if sfx != null:
		sfx.op(id, "s%d" % (i + 1), 0.0, 1.0, 0.0)
		if g.demo_op == "":
			sfx.voice(id, "skill_%d" % (i + 1))   # 技能语音（>3 秒的不播，见 sfx.gd）
	if skill_def(i).get("permanent", false):
		perm[i] = true
		sp[i] = sp_need(i)
	g.rfx.on_skill_start(self, i)


## 藏品 / 先锋等给的技力：已解锁技能各按需求百分比充能
func gain_sp(pct: float) -> void:
	for i in 3:
		if skill_unlocked(i) and sp_need(i) > 0.0 and not perm[i]:
			sp[i] = minf(sp_need(i), sp[i] + sp_need(i) * pct)


## 测试：全部充满
func fill_sp() -> void:
	for i in 3:
		if skill_unlocked(i):
			sp[i] = sp_need(i)


## 排异反应（结局四）：随机一个已解锁、未海嗣化的技能被海嗣化——技能强度 +40%、充能需求 +30%，主控最大生命 -10
func apply_rejection() -> String:
	var cands: Array = []
	for i in 3:
		if skill_unlocked(i) and not rej.has(i):
			cands.append(i)
	if cands.is_empty():
		return ""
	var i: int = cands[g.rng.randi() % cands.size()]
	rej[i] = true
	g.stats.add(&"op_skill_power", "add", 0.4, "rej:%s:%d" % [id, i], "op:" + id)
	g.stats.add(&"max_hp", "flat", -10.0, "rej:%s:%d" % [id, i])
	refresh_stats()
	g.hp = minf(g.hp, g.max_hp)
	return "%s「%s」海嗣化：技能强度 +40%%、充能 +30%%；主控最大生命 -10" % [display_name(), skill_def(i).get("name", "")]


## 精英化演出：新技能（+ 精一天赋）
func _elite_show(stage: int) -> void:
	var items: Array = [skill_item(stage)]
	var td := talent_def()
	if stage == 1 and not td.is_empty():
		items.append({"tag": "天赋", "tag_en": "TALENT", "glyph": td.get("name", "赋").substr(0, 1), "name": td.get("name", ""), "desc": td.get("desc", ""), "col": col().lerp(Color(1, 1, 1), 0.3)})
	g.show_queue.append({"head": "%s · 精英%s" % [display_name(), ["", "一", "二"][stage]], "en": "ELITE  PROMOTION  " + ["", "I", "II"][stage], "col": col(), "op": self, "elite": stage, "items": items})


# ---------------------------------------------------------------- 干员特效粒子（docs/25）

## 加一个粒子：kind / pos / life 必填；col、r、vel、drag、grav、ang、floor（地面层）按 kind 取用
func fx(f: Dictionary) -> void:
	f["max"] = f.life
	pfx.append(f)


func _tick_pfx(dt: float) -> void:
	# 气场：节点数 / 精英阶段越高，身上升起的职业色光点越密、越亮（精零无节点时没有）
	var power: int = node_lv + elite * 2
	if power > 0 and pos != Vector2.INF:
		aura_t -= dt
		if aura_t <= 0.0:
			aura_t = 0.5 / float(power)
			var c: Color = col().lerp(Color.WHITE, 0.25)
			var br: float = 1.0 + 0.12 * power
			fx({"kind": "mote", "pos": pos + Vector2(g.rng.randf_range(-14, 14), g.rng.randf_range(-40, -6)), "vel": Vector2(g.rng.randf_range(-6, 6), -30.0 - 3.0 * power),
				"life": 0.6 + 0.05 * power, "col": Color(c.r * br, c.g * br, c.b * br), "sz": 1.6 + 0.15 * power})
	if pfx.is_empty():
		return
	for f in pfx:
		f.life -= dt
		if f.has("vel"):
			f.pos += f.vel * dt
			if f.has("drag"):
				f.vel *= maxf(0.0, 1.0 - f.drag * dt)
			if f.has("grav"):
				f.vel.y += f.grav * dt
		if f.has("spin"):
			f.ang = f.get("ang", 0.0) + f.spin * dt
	pfx = pfx.filter(func(f): return f.life > 0.0)


## 绘制某一层的粒子；子类可覆盖 _draw_pfx 画自己的 kind（返回 true 表示已画）
func draw_pfx(floor_layer: bool) -> void:
	for f in pfx:
		if f.get("floor", false) != floor_layer:
			continue
		var a: float = clampf(f.life / f.max, 0.0, 1.0)
		if _draw_pfx(f, a):
			continue
		var c: Color = f.get("col", col())
		match f.kind:
			"ring":
				# 扩散环：r0 → r
				var k := 1.0 - a
				var rr: float = lerpf(f.get("r0", f.r * 0.3), f.r, 1.0 - (1.0 - k) * (1.0 - k))
				if f.get("floor", false):
					g.draw_set_transform(f.pos, 0.0, Vector2(1.0, 0.55))
					g.draw_arc(Vector2.ZERO, rr, 0.0, TAU, 40, Color(c.r, c.g, c.b, a * f.get("alpha", 0.9)), f.get("w", 3.0))
					g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					g.draw_arc(f.pos, rr, 0.0, TAU, 40, Color(c.r, c.g, c.b, a * f.get("alpha", 0.9)), f.get("w", 3.0))
			"spark":
				g.draw_rect(Rect2(f.pos.round(), Vector2(f.get("sz", 3.0), f.get("sz", 3.0))), Color(c.r, c.g, c.b, a))
			"glow":
				# 发光团：先胀后缩
				var k2: float = sin(a * PI)
				g.draw_circle(f.pos, f.r * (0.4 + 0.6 * k2), Color(c.r, c.g, c.b, f.get("alpha", 0.35) * a))
				g.draw_circle(f.pos, f.r * 0.35 * k2, Color(c.r * 1.8, c.g * 1.8, c.b * 1.8, 0.7 * a))
			"shard":
				# 碎片：旋转的细三角
				var sv: Vector2 = Vector2.from_angle(f.get("ang", 0.0)) * f.get("sz", 6.0)
				g.draw_colored_polygon(PackedVector2Array([f.pos - sv, f.pos + sv.orthogonal() * 0.45, f.pos + sv]), Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, a))
			"line":
				g.draw_line(f.pos, f.get("to", f.pos), Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, a), f.get("w", 2.0))
			"flame":
				# 火舌：底宽上尖，随时间抖动
				var h: float = f.get("sz", 10.0) * (0.6 + 0.4 * a)
				var wob: float = sin(g.t * 24.0 + f.pos.x) * 2.0
				var bp: Vector2 = f.pos
				g.draw_colored_polygon(PackedVector2Array([bp + Vector2(-h * 0.35, 0), bp + Vector2(wob, -h), bp + Vector2(h * 0.35, 0)]), Color(c.r, c.g, c.b, 0.8 * a))
				g.draw_colored_polygon(PackedVector2Array([bp + Vector2(-h * 0.16, 0), bp + Vector2(wob * 0.6, -h * 0.55), bp + Vector2(h * 0.16, 0)]), Color(2.2, 1.9, 1.2, 0.8 * a))
			"mote":
				g.draw_circle(f.pos, f.get("sz", 2.0), Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, a))
			"crack":
				_draw_crack(f, a, c)


## 地裂（2026-09-26 重做，用户：原来的均匀放射线不像裂地）：第一次绘制时按落点生成并缓存在 f.crack：
## 中心是实心的不规则碎坑（深色填充 + 更深的坑心）；主裂缝 n 条（方向 / 长短随机）是实心楔形，从坑边最宽（8–12px）
## 不规则地收细到 1px，途中随机分出支裂（从主裂缝当前宽度的六成开始收细）。贴地透视（y × 0.55），中心线对齐 2 像素网格；
## 前 0.06 秒从中心裂开，暗色裂缝停留到后半程再淡出，干员色亮芯先消失。
func _draw_crack(f: Dictionary, a: float, c: Color) -> void:
	if not f.has("crack"):
		f["crack"] = _crack_build(f)
	var cd: Dictionary = f.crack
	var age: float = f.max - f.life
	var grow: float = clampf(age / 0.06, 0.0, 1.0)
	var al: float = minf(1.0, a * 2.0)             # 前半程保持不透明，后半程淡出
	var glow: float = clampf((a - 0.5) * 2.0, 0.0, 1.0)
	var dark := Color(0.045, 0.035, 0.04, 0.9 * al)
	# 裂缝：逐段画实心梯形（中心线两侧按该点半宽展开）
	for sg in cd.segs:
		var pts: PackedVector2Array = sg.pts
		var ws: PackedFloat32Array = sg.ws
		var m: int = mini(pts.size(), maxi(2, int(ceil(pts.size() * grow))))
		for i in m - 1:
			var p0: Vector2 = pts[i]
			var p1: Vector2 = pts[i + 1]
			var d: Vector2 = p1 - p0
			if d.length() < 1.0:
				continue
			var nrm: Vector2 = d.normalized().orthogonal()
			var q := PackedVector2Array([p0 + nrm * ws[i], p1 + nrm * ws[i + 1], p1 - nrm * ws[i + 1], p0 - nrm * ws[i]])
			if ws[i] + ws[i + 1] < 1.2:
				g.draw_line(p0, p1, dark, 1.0)
			else:
				g.draw_colored_polygon(q, dark)
			if glow > 0.0 and ws[i] > 1.4:
				g.draw_line(p0, p1, Color(c.r * 1.6, c.g * 1.4, c.b * 1.2, 0.75 * glow), maxf(1.0, ws[i] * 0.6))
	# 中心碎坑：实心深色 + 略亮的边 + 几道坑内裂纹
	var ring: PackedVector2Array = cd.ring
	var sc: float = 0.35 + 0.65 * grow
	var ctr: Vector2 = cd.center
	var rp := PackedVector2Array()
	for v in ring:
		rp.append(ctr + (v - ctr) * sc)
	g.draw_colored_polygon(rp, Color(0.06, 0.05, 0.05, al))
	# 坑心再压一层更深的（凹陷感），不画亮边——亮边会让中心看起来是空的
	var core := PackedVector2Array()
	for v in rp:
		core.append(ctr + (v - ctr) * 0.55)
	g.draw_colored_polygon(core, Color(0.02, 0.015, 0.02, al))
	for ln in cd.inner:
		g.draw_line(ctr + (ln[0] - ctr) * sc, ctr + (ln[1] - ctr) * sc, Color(0.16, 0.13, 0.13, 0.8 * al), 1.0)


func _crack_build(f: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(f.pos.x), int(f.pos.y))) + int(f.get("ang", 0.0) * 1000.0)
	var R: float = f.r
	var o: Vector2 = f.pos
	var snap := func(v: Vector2) -> Vector2: return ((o + Vector2(v.x, v.y * 0.55)) / 2.0).round() * 2.0   # 贴地透视 + 对齐 2 像素网格
	# 中心碎坑（不规则多边形，凸的，保证能三角化）
	var ring := PackedVector2Array()
	var nv: int = rng.randi_range(8, 11)
	var cr: float = R * rng.randf_range(0.22, 0.3)
	for i in nv:
		var an: float = TAU * float(i) / nv + rng.randf_range(-0.12, 0.12)
		ring.append(o + Vector2.from_angle(an) * cr * rng.randf_range(0.8, 1.15) * Vector2(1.0, 0.55))
	var inner: Array = []
	for i in 3:
		var an2: float = rng.randf() * TAU
		inner.append([o + Vector2.from_angle(an2) * cr * 0.15 * Vector2(1.0, 0.55), o + Vector2.from_angle(an2 + rng.randf_range(-0.4, 0.4)) * cr * 0.85 * Vector2(1.0, 0.55)])
	var segs: Array = []
	var n: int = f.get("n", 8)
	var base_ang: float = f.get("ang", rng.randf() * TAU)
	for q in n:
		var ang: float = base_ang + TAU * q / n + rng.randf_range(-0.35, 0.35)
		var L: float = R * rng.randf_range(0.5, 1.0)
		var steps: int = rng.randi_range(5, 7)
		var w0: float = rng.randf_range(4.0, 6.0)          # 半宽：坑边最宽处 8–12px
		var p: Vector2 = Vector2.from_angle(ang) * cr * 0.8
		var pts := PackedVector2Array([snap.call(p)])
		var ws := PackedFloat32Array([w0])
		for st in steps:
			ang += rng.randf_range(-0.55, 0.55)
			p += Vector2.from_angle(ang) * (L - cr) / steps * rng.randf_range(0.7, 1.3)
			pts.append(snap.call(p))
			var t: float = float(st + 1) / steps
			# 不规则收细：整体按 (1-t)^0.9 由宽到细，每个点再乘 0.65–1.25 的起伏，末端 0.5px
			ws.append(maxf(0.5, w0 * pow(1.0 - t, 0.9) * rng.randf_range(0.65, 1.25)))
			if st >= 1 and st < steps - 1 and rng.randf() < 0.4:
				var ba: float = ang + rng.randf_range(0.6, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
				var bp: Vector2 = p
				var bw: float = ws[ws.size() - 1] * 0.6
				var bpts := PackedVector2Array([snap.call(bp)])
				var bws := PackedFloat32Array([bw])
				var bn: int = rng.randi_range(2, 3)
				for bs in bn:
					ba += rng.randf_range(-0.4, 0.4)
					bp += Vector2.from_angle(ba) * (L - cr) / steps * rng.randf_range(0.5, 0.9)
					bpts.append(snap.call(bp))
					bws.append(maxf(0.5, bw * (1.0 - float(bs + 1) / bn) * rng.randf_range(0.7, 1.2)))
				segs.append({"pts": bpts, "ws": bws})
		segs.append({"pts": pts, "ws": ws})
	return {"ring": ring, "inner": inner, "segs": segs, "center": o}


## 子类的自定义粒子；返回 true 表示已绘制
func _draw_pfx(_f: Dictionary, _a: float) -> bool:
	return false


## 一圈火花
func fx_sparks(p: Vector2, c: Color, n: int, spd: float, life := 0.4, sz := 3.0, grav := 0.0, floor_layer := false) -> void:
	n = int(round(n * (1.0 + 0.2 * node_lv)))   # 节点越多火花越多（每节点 +20%）
	for k in n:
		fx({"kind": "spark", "pos": p, "vel": Vector2.from_angle(g.rng.randf() * TAU) * g.rng.randf_range(spd * 0.4, spd), "life": life * g.rng.randf_range(0.7, 1.2),
			"col": c, "sz": sz, "drag": 2.0, "grav": grav, "floor": floor_layer})


# ---------------------------------------------------------------- 数值

## 角色 JSON 的 base 段：专属基础数值（如伞击伤害、挥砍半径），缺项用默认
func base(key: String, default: float) -> float:
	return float(def.get("base", {}).get(key, default))


## 角色专属属性定义（stat 名 -> {base, min, max, name}），带角色前缀
func stat_defs() -> Dictionary:
	return {}


## 近战职业（其余为远程）：藏品「近战干员 / 远程干员」按职业判定（docs/35）
const MELEE_CLASSES := ["近卫", "重装", "先锋", "特种"]


func range_cls() -> String:
	return "近战" if cls in MELEE_CLASSES else "远程"


## 本干员命中的作用域（docs/23 §5）；range:近战 / range:远程 给按近远生效的藏品用（docs/35）
func scopes() -> Array:
	return ["class:" + cls, "range:" + range_cls(), "op:" + id]


## 干员视角的属性值：全局修正 + 职业 / 本人作用域的修正
func stat(name: StringName) -> float:
	return g.stats.value_for(name, scopes())


## 普攻 / 自动技能 / 天赋定义（JSON）
func attack_def() -> Dictionary:
	return def.get("attack", {})


## 三个技能的定义（JSON skills 数组）：{name, en, sp, desc, dur, icon}
func skills_def() -> Array:
	return def.get("skills", [])


func skill_def(i: int) -> Dictionary:
	var sk := skills_def()
	return sk[i] if i >= 0 and i < sk.size() else {}


## 技能 i 是否已解锁：招募 S1 / 精一 S2 / 精二 S3
func skill_unlocked(i: int) -> bool:
	return i < skills_def().size() and elite >= i


## 技能 i 的充能需求（海嗣化 +30%）
func sp_need(i: int) -> float:
	return float(skill_def(i).get("sp", 0.0)) * (1.3 if rej.has(i) else 1.0)


func talent_def() -> Dictionary:
	return def.get("talent", {})


func display_name() -> String:
	return def.get("name", id)


# ---------------------------------------------------------------- 成长线（docs/23 §7）

func progression() -> Array:
	return def.get("progression", [])


func next_node() -> Dictionary:
	var pg := progression()
	return pg[prog] if prog < pg.size() else {}


## 精英化条件是否满足：requires {relic: [id…], level: N, class_in_squad: 职业, doctor_passive: id}
func node_available(n: Dictionary) -> bool:
	if n.is_empty():
		return false
	var req: Dictionary = n.get("requires", {})
	for rid in req.get("relic", []):
		if not g.relics.has(str(rid)):
			return false
	if g.level < int(req.get("level", 0)):
		return false
	var need_cls: String = req.get("class_in_squad", "")
	if need_cls != "":
		var found := false
		for o in g.squad.ops:
			if o.cls == need_cls and o != self:
				found = true
		if not found:
			return false
	var dp: String = req.get("doctor_passive", "")
	if dp != "" and g.growth.get(dp, 0) <= 0:
		return false
	return true


## 条件说明（卡面 / 图鉴）
func node_requires_text(n: Dictionary) -> String:
	var req: Dictionary = n.get("requires", {})
	var parts: Array = []
	for rid in req.get("relic", []):
		parts.append("持有藏品「%s」" % g.rfx.display_name(str(rid)))
	if req.has("level"):
		parts.append("博士 Lv.%d" % int(req.level))
	if req.has("class_in_squad"):
		parts.append("编队中有%s干员" % req.class_in_squad)
	if req.has("doctor_passive"):
		parts.append("博士被动「%s」" % g.doctor.PASSIVES.get(req.doctor_passive, {"name": req.doctor_passive}).name)
	return "、".join(parts)


## 应用下一个成长节点（elite 节点可带 choice）
func advance(choice: String = "") -> void:
	var n := next_node()
	if n.is_empty():
		return
	prog += 1
	match n.type:
		"stat":
			for ef in n.get("effects", []):
				g.stats.add(StringName(ef.key), ef.get("op", "add"), float(ef.value), "prog:%s:%d" % [id, prog], "op:" + id)
			refresh_stats()
		"elite":
			elite = int(n.level)
			on_elite(elite, choice)
			# 新解锁的技能立即充满：选下精英化卡的当下就能看到新技能（原来从 0 充能，要等 15–30 秒）
			if elite < 3 and skill_unlocked(elite) and not perm[elite]:
				sp[elite] = sp_need(elite)
			_elite_show(elite)
		"custom":
			on_custom_node(n.get("id", ""), choice)
	# 每个普通节点的统一小强化（docs/25 §5.1 第 9 条）：攻击 +6%；气场与命中火花随节点数增强
	if n.type != "elite":
		node_lv += 1
		g.stats.add(&"op_atk", "add", NODE_ATK, "node:%s:%d" % [id, prog], "op:" + id)
		refresh_stats()
		# 升级瞬间：职业色光柱 + 一圈光点，告诉玩家「她变强了」
		if pos != Vector2.INF:
			fx({"kind": "ring", "pos": pos, "r": 46.0, "r0": 6.0, "life": 0.45, "col": col(), "floor": true, "w": 3.0})
			fx_sparks(pos + Vector2(0, -24), col().lerp(Color.WHITE, 0.4), 12, 180.0, 0.5, 3.0, -120.0)
	if n.has("banner"):
		show_banner(n.banner % display_name() if "%s" in n.banner else n.banner)


## 干员深度卡：下一个成长节点（elite 带 choices 时每个选项一张）+ 子类追加的卡（技能进阶等）
func deep_cards() -> Array:
	var out: Array = []
	var n := next_node()
	if not n.is_empty():
		var avail := node_available(n)
		var stage_txt := "%d/%d" % [prog + 1, progression().size()]
		var chs: Dictionary = elite_choices(n) if n.type == "elite" else {}
		if not chs.is_empty():
			for c in chs:
				var cd: Dictionary = chs[c]
				out.append({"kind": "prog", "op": id, "choice": c, "name": "%s · %s" % [n.get("name", "精英化"), cd.get("name", c)],
					"desc": cd.get("desc", n.get("desc", "")), "icon": cd.get("icon", n.get("icon", "")), "col": cd.get("col", null), "avail": avail, "req": node_requires_text(n), "elite": n.level})
		else:
			var req_txt := node_requires_text(n)
			out.append({"kind": "prog", "op": id, "choice": "", "name": "%s · %s" % [display_name(), n.get("name", "成长 " + stage_txt)],
				"desc": n.get("desc", "") + (("\n条件：%s（已满足）" % req_txt) if req_txt != "" and avail else ""), "icon": n.get("icon", ""), "avail": avail, "req": req_txt, "elite": n.get("level", 0)})
	out.append_array(extra_cards())
	return out


## 精英化节点的选项（默认读 JSON 的 choices：{id: {name, desc, icon}} 或 [id…]）
func elite_choices(n: Dictionary) -> Dictionary:
	var raw = n.get("choices", null)
	var out: Dictionary = {}
	if raw is Dictionary:
		for k in raw:
			out[k] = raw[k]
	elif raw is Array:
		for k in raw:
			out[k] = {"name": k, "desc": ""}
	return out


## 子类追加的深度卡（默认无）
func extra_cards() -> Array:
	return []


## 子类处理自己追加的卡；返回 true 表示已处理
func apply_extra_card(_card: Dictionary) -> bool:
	return false


## 精英化钩子（stage 1 / 2，choice 为精英化二的路线选择）
func on_elite(_stage: int, _choice: String = "") -> void:
	pass


func on_custom_node(_nid: String, _choice: String = "") -> void:
	pass


func on_kill(_e: Dictionary) -> void:
	pass


## 属性块有变化时由 game.gd 调用：把 g.stats 里的专属属性同步到角色缓存变量
func sync_stats(_st) -> void:
	pass


## 普攻半径（自动索敌 / 机器人走位用）
func _swing_radius() -> float:
	return 90.0


## 伤害通用倍率：全伤害倍率（全局 + 本干员作用域）× 干员攻击倍率
func _dmg_bonus() -> float:
	return stat(&"dmg") * stat(&"op_atk") * g.ally_mult


# ---------------------------------------------------------------- 绘制（世界坐标，用 g.draw_*）

## 角色脚下的技能表现
func _draw_skill_floor() -> void:
	pass


## 角色身上的技能表现
func _draw_skill_over() -> void:
	pass


## 专属实体：地面层（触手桩 / 符阵等）
func draw_entities_floor() -> void:
	pass


## 专属实体：角色之上（巨触等）
func draw_entities_over() -> void:
	pass


func draw_auras() -> void:
	pass


func draw_fx_add(_ci: CanvasItem, _loop: int) -> void:
	pass


## Tab 面板：本干员的状态行 [[名, 值], …]
func stats_rows() -> Array:
	return []


func status_items() -> Array:
	return []


## HUD 头像：g.tex 里的贴图名 + 帧数
func portrait() -> Dictionary:
	var spec := sprite_spec("idle")
	var tx: Texture2D = anim_tex("idle")
	return {"tex": spec.get("tex", ""), "frames": anim_hframes(tx, "idle") if tx != null else 1}


# ---------------------------------------------------------------- 跟随与动画（squad.gd 调用）

## 跟随主控的编队位：近处慢慢挪、远处快步跟上；离得太远（开局 / 传送）直接归位
func follow(dt: float, target: Vector2) -> void:
	if pos == Vector2.INF or pos.distance_to(target) > 700.0:
		pos = target
		mv = 0.0
		return
	var prev: Vector2 = pos
	if is_leader:
		pos = target   # 主控：位置就是玩家位置（g.ppos），不走编队跟随 / 近战前压
	else:
		target = follow_target(target)
		var d: float = pos.distance_to(target)
		var k: float = clampf(dt * (3.0 if d < 20.0 else 6.0), 0.0, 1.0)
		pos = pos.lerp(target, k)
		if g.tex.get("prop_pillar") != null:
			pos = g.map.push_out(pos, 10.0)
	var vel: Vector2 = (pos - prev) / maxf(dt, 0.0001)
	_sample_motion(vel, dt)
	mv = lerpf(mv, vel.length(), clampf(dt * 10.0, 0.0, 1.0))
	if attack_t <= 0.0:
		if absf(vel.x) > 25.0 and mv > 30.0:
			face = signf(vel.x)
		elif mv < 20.0:
			face = g.facing
	attack_t = maxf(0.0, attack_t - dt)
	if fire_t >= 0.0:
		fire_t -= dt
		if fire_t < 0.0:
			fire_t = -1.0
			if act_kind == "skill":
				_release_skill()
			else:
				_release()
	mt += dt
	# 动画状态
	var want := "idle"
	if attack_t > 0.0 and anim_tex(act_anim) != null:
		want = act_anim
	elif mv > 30.0 and anim_tex("run") != null:
		want = "run"
	if want != anim_kind:
		anim_kind = want
		anim_t = 0.0
	anim_t += dt


## 起手：面向目标、播攻击条（4 帧 8fps 约定：0.5 秒，零基第 2 帧出手）；没有攻击条就立即出手
## 贴图槽带 fps + fire（出手帧，零基）时，时长与出手时刻按帧条算，dur / fire_at 参数被忽略（docs/24 §1）
## anim：这一击改播别的帧条（例如斯卡蒂潮汐期间播 "attack_spin"）；缺图时退回 attack 条。出手仍调 _release（逻辑类型不变）
func start_attack(aim: Vector2, dur: float = 0.5, fire_at: float = 0.25, anim := "") -> void:
	_start_action("attack", aim, dur, fire_at, anim)


## 起手技能动作；idx 为技能序号（默认沿用 cur_skill）。播哪套帧条由 skill_anim() 决定（缺省 skill 条），
## anim 参数可临时指定；那套帧条不存在时退回 skill 条，都没有就直接出手
func start_skill(aim: Vector2, idx: int = -1, dur: float = 0.6, fire_at: float = 0.3, anim := "") -> void:
	if idx >= 0:
		cur_skill = idx
		spend_sp(idx)
	_start_action("skill", aim, dur, fire_at, anim if anim != "" else skill_anim(cur_skill))


## 技能 i 播放的帧条（2026-09-26）：缺省读干员 JSON skills[i].anim（例如 "attack" = 放技能时播普攻动作），没写就是 "skill"。
## 干员脚本也可以重写这个函数按状态决定。出手时机按实际播放的那套帧条的 fps / fire 算。
func skill_anim(i: int) -> String:
	return str(skill_def(i).get("anim", "skill")) if i >= 0 else "skill"


## kind：逻辑类型（attack / skill，决定出手调哪个函数）；anim：播放的帧条（缺省同 kind）
func _start_action(kind: String, aim: Vector2, dur: float, fire_at: float, anim := "") -> void:
	if aim != Vector2.INF and absf(aim.x - pos.x) > 2.0:
		face = signf(aim.x - pos.x)
	act_kind = kind
	act_anim = anim if anim != "" and anim_tex(anim) != null else kind
	if anim_tex(act_anim) == null:
		if kind == "skill":
			_release_skill()
		else:
			_release()
		return
	var spec := sprite_spec(act_anim)
	if spec.has("fps") and spec.has("fire"):
		var n := float(spec.get("frames", anim_hframes(anim_tex(act_anim), act_anim)))
		dur = n / float(spec.fps)
		fire_at = (float(spec.fire) + 0.5) / float(spec.fps)
	# 攻速快于动作时压缩动作，保证出手不被下一次起手打断
	attack_dur = dur
	attack_t = dur
	fire_t = fire_at
	anim_kind = ""


## 出手（到出手帧时调用；重新找目标，动作期间原目标可能已死）
func _release() -> void:
	pass


## 技能出手帧（cur_skill 为技能序号）
func _release_skill() -> void:
	pass


## 是否正在播放动作（攻击 / 技能），用于避免打断
func acting() -> bool:
	return attack_t > 0.0


## 跟随目标点：默认是编队位；近战干员可以改成"前压到敌人身边"（离主控不超过 leash）
func follow_target(slot_pos: Vector2) -> Vector2:
	return slot_pos


## 近战前压：主控 leash 范围内最近的敌人；返回站位点（敌人朝主控一侧、身前 gap 处）或 INF。
## 目标带滞回（现目标死亡或超出 leash × 1.3 才换），已经够得着时原地不动，避免在两个目标 / 两侧之间来回抖。
var melee_tgt = null

func melee_spot(leash: float, gap: float) -> Vector2:
	if g.demo_op != "":
		leash *= 2.0   # 图鉴演示：场地里全是靶子，近战放宽前压范围，一直追着怪海打
	var e = melee_tgt
	if e == null or e.dead or e.pos.distance_to(g.ppos) > leash * 1.3:
		var ts: Array = nearest_enemies(1, leash, g.ppos)
		e = ts[0] if not ts.is_empty() else null
		melee_tgt = e
	if e == null:
		return Vector2.INF
	var reach: float = gap + e.r
	if pos.distance_to(e.pos) <= reach + 14.0:
		return pos
	var d: Vector2 = g.ppos - e.pos
	if d.length() < 1.0:
		d = Vector2(-face, 0)
	return e.pos + d.normalized() * reach


## 召唤物等附属实体：参与 2.5D 排序的条目 [{"y": 脚底 y, …}]，由 draw_extra 绘制
func extra_bodies() -> Array:
	return []


func draw_extra(_it: Dictionary) -> void:
	pass


func draw_extra_shadows() -> void:
	pass


## 近战扇形命中：对 origin 周围 radius、朝 ang ±half 的敌人造成伤害；返回命中的敌人
func melee_hit(src: String, origin: Vector2, ang: float, half: float, radius: float, dmg: float, kb := 0.0, stun := 0.0, tags: Array = []) -> Array:
	var hits: Array = arc_targets(origin, ang, half, radius)
	for e in hits:
		log_hit(src, tags)
		deal_damage(e, dmg)
		if e.dead or e.boss:
			continue
		if kb > 0.0:
			e.kb += (e.pos - origin).normalized() * kb * (0.3 if e.elite else 1.0)
		if stun > 0.0:
			e.stun = maxf(e.stun, stun * (0.5 if e.elite else 1.0))
	for e in hits:
		_hit_fx(e, origin)
	return hits


## 命中一名敌人时的特效钩子（默认无；各干员按 docs/25 覆盖）
func _hit_fx(_e: Dictionary, _origin: Vector2) -> void:
	pass


## 圆形范围伤害（技能 / 爆炸）：返回命中的敌人
func area_hit(src: String, c: Vector2, radius: float, dmg: float, kb := 0.0, stun := 0.0, tags: Array = []) -> Array:
	return melee_hit(src, c, 0.0, PI, radius, dmg, kb, stun, tags)


## 技能强度倍率（全队被动「协同·锐」等）
func skill_power() -> float:
	return stat(&"op_skill_power")


## 干员面向某个方向（出手时由干员调用）
func face_to(ang: float) -> void:
	face = 1.0 if cos(ang) >= 0.0 else -1.0


func facing_angle() -> float:
	return 0.0 if face >= 0.0 else PI


## 贴图槽：def.sprites[kind] 可以是贴图名，或 {tex, frames, foot, fps}（攻击条画布比帧宽时用）
func sprite_spec(kind: String) -> Dictionary:
	var sp: Dictionary = def.get("sprites", {})
	if not sp.has(kind):
		return {}
	var v = sp[kind]
	if v is String:
		return {"tex": v}
	return v


func anim_tex(kind: String) -> Texture2D:
	var spec := sprite_spec(kind)
	if spec.is_empty():
		return null
	return g.tex.get(spec.tex)


func anim_hframes(tx: Texture2D, kind: String = "") -> int:
	var spec := sprite_spec(kind) if kind != "" else {}
	if spec.has("frames"):
		return int(spec.frames)
	return max(1, tx.get_width() / tx.get_height())


## 当前帧（贴图 / 帧序号 / 帧数），残影 / 分身等复用
func anim_state() -> Dictionary:
	var tx: Texture2D = anim_tex(anim_kind)
	if tx == null:
		tx = anim_tex("idle")
	if tx == null:
		return {}
	var kind: String = anim_kind if anim_tex(anim_kind) != null else "idle"
	var n: int = anim_hframes(tx, kind)
	var fr := 0
	match kind:
		"attack", "skill":
			fr = clampi(int(anim_t / attack_dur * n), 0, n - 1)
		_:
			fr = int(anim_t * float(sprite_spec(kind).get("fps", ANIM_FPS.get(kind, 4.0)))) % n
	return {"tex": tx, "frame": fr, "hf": n, "flip": face < 0.0, "kind": kind}


## 脚底锚点在帧内的位置（该贴图槽的 foot，否则 def.sprites.foot，默认帧底部上方 2px）
func foot_off(tx: Texture2D, kind: String = "") -> float:
	var sp: Dictionary = def.get("sprites", {})
	var hires: float = A.hires_of(tx)
	var spec := sprite_spec(kind) if kind != "" else {}
	if spec.has("foot"):
		return (tx.get_height() - float(spec.foot[1]) * hires)
	if sp.has("foot"):
		return (tx.get_height() - float(sp.foot[1]) * hires)
	return 2.0 * hires


## 画干员本体（世界坐标，脚底在 pos）
func draw_body() -> void:
	var st := anim_state()
	if st.is_empty():
		g.draw_circle(pos, 10.0, Color(0.6, 0.9, 1.0))
		return
	# 残影（动态模糊，用户选定方案 A，2026-09-25）：突然冲刺时身后 3–4 个带职业色的渐隐分身，先画在本体下面
	var c: Color = col().lerp(Color.WHITE, 0.35)
	for gh in ghosts:
		var a: float = GHOST_ALPHA * (1.0 - gh.age / GHOST_LIFE)
		draw_sprite_at(gh.p, gh.st.flip, Color(c.r * 1.4, c.g * 1.4, c.b * 1.4, a), gh.st.frame, gh.st.tex, gh.st.hf, foot_off(gh.st.tex, gh.st.get("kind", "")))
	# 主控：受击闪白 / 闪红 / 无敌闪烁沿用 game.gd 算好的 sprite.modulate
	var mod: Color = g.sprite.modulate if is_leader else Color.WHITE
	draw_sprite_at(pos, st.flip, mod, st.frame, st.tex, st.hf, foot_off(st.tex, st.get("kind", "")))


## 残影采样（follow() 每帧调用）：瞬时速度 > GHOST_SPEED 时每 GHOST_EVERY 秒留一个分身，存活 GHOST_LIFE 秒。
## 跟着主控慢走不触发，只在前压 / 追赶 / 技能位移这种「一下子移动」时出现
const GHOST_SPEED := 200.0
const GHOST_EVERY := 0.04
const GHOST_LIFE := 0.18
const GHOST_ALPHA := 0.55
var ghosts: Array = []           # [{p, st, age}]
var ghost_t := 0.0

func _sample_motion(vel: Vector2, dt: float) -> void:
	for gh in ghosts:
		gh.age += dt
	ghosts = ghosts.filter(func(gh): return gh.age < GHOST_LIFE)
	ghost_t -= dt
	if vel.length() > GHOST_SPEED and ghost_t <= 0.0:
		ghost_t = GHOST_EVERY
		var st := anim_state()
		if not st.is_empty():
			ghosts.push_front({"p": pos, "st": st, "age": 0.0})


## 在别处画一份当前帧（分身 / 残影）
func draw_body_at(p: Vector2, flip: bool, col: Color, st: Dictionary = {}) -> void:
	if st.is_empty():
		st = anim_state()
	if st.is_empty():
		return
	draw_sprite_at(p, flip, col, st.frame, st.tex, st.hf, foot_off(st.tex, st.get("kind", "")))
